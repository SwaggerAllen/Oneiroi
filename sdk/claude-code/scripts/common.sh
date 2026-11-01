# shellcheck shell=bash
# Oneiroi Claude Code adapter: what the three hooks share (spec §8).
# Sourced, never run, from the plugin's `scripts/`. Needs bash, curl and jq.
#
# Every hook exits 0 whatever happens. On UserPromptSubmit an exit of 2
# blocks the witness's prompt and on Stop it keeps Claude going (Claude
# Code's hook docs); jq exits 2 on its own errors, so no hook lets a
# command's status become its own.
#
# The token never reaches a command line, a URL or the output: curl
# reads the header from a config on its stdin (`-K -`), so it is not in
# the process list either.

# The state holds the witness's words until they are delivered.
umask 077

# Claude Code adds at most 10,000 characters of one hook's output to the
# context and turns the rest into a file path with a preview (its hook
# docs, "Add context for Claude"). Its count is JavaScript's, in UTF-16
# units, where one character outside the BMP is two, so the platform is
# asked for 9,000 of its own: a margin, not a measurement.
ONEIROI_LIMIT=9000

# The three values the plugin's userConfig asks for when it is enabled,
# which Claude Code exports to every hook as CLAUDE_PLUGIN_OPTION_<KEY>
# (its plugin manifest reference); the token is a sensitive option, kept
# in Claude Code's secure credential store rather than settings.json.
# Nothing else is read: no env file, which would put the token on disk
# in plain text beside the scripts. Unset, every hook does nothing at
# all, so a plugin installed but not configured is silent.
oneiroi_env() {
  ONEIROI_URL="${CLAUDE_PLUGIN_OPTION_URL:-}"
  ONEIROI_URL="${ONEIROI_URL%/}"
  ONEIROI_RESIDENT="${CLAUDE_PLUGIN_OPTION_RESIDENT:-}"
  ONEIROI_TOKEN="${CLAUDE_PLUGIN_OPTION_TOKEN:-}"
  [ -n "$ONEIROI_URL" ] && [ -n "$ONEIROI_RESIDENT" ] && [ -n "$ONEIROI_TOKEN" ]
}

# With the plugin's `record_fixtures` option set to a folder (or
# ONEIROI_RECORD_FIXTURES in the environment Claude Code was started
# from, which its hooks inherit), each hook's raw stdin is copied there, so a real session records the payloads the fixtures under
# `fixtures/` only claim. The payload is Claude Code's; it never holds
# the token. It does hold the witness's words and local paths: read a
# recording before committing it.
oneiroi_record() {
  local dir="${CLAUDE_PLUGIN_OPTION_RECORD_FIXTURES:-${ONEIROI_RECORD_FIXTURES:-}}" event
  [ -n "$dir" ] || return 0
  event="$(printf '%s' "$1" | jq -r '.hook_event_name // "unknown"' 2>/dev/null || echo unknown)"
  mkdir -p "$dir" 2>/dev/null &&
    printf '%s' "$1" > "$dir/$event-$(date -u +%Y%m%dT%H%M%SZ)-$$.json" || true
}

# A session's own state directory: its platform session key, the turn
# in flight (ref, start instant, the witness's words) and the digest of
# the prefix it was given. Under the plugin's data directory, which
# Claude Code keeps across plugin updates (never under the plugin's own
# root, which an update replaces). Claude Code's session id is sanitised
# before it names a directory.
oneiroi_state_root() { printf '%s' "${CLAUDE_PLUGIN_DATA:-${XDG_STATE_HOME:-$HOME/.local/state}/oneiroi}"; }

oneiroi_state() {
  local id
  id="$(printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '_')"
  mkdir -p "$(oneiroi_state_root)/$id" && chmod 700 "$(oneiroi_state_root)" 2>/dev/null
  printf '%s' "$(oneiroi_state_root)/$id"
}

oneiroi_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# One request: METHOD PATH BODY_FILE(or "") OUT_FILE. Prints the HTTP
# status, 000 when nothing answered.
oneiroi_api() {
  local method="$1" path="$2" body="$3" out="$4"
  local -a data=()
  [ -n "$body" ] && data=(--data-binary "@$body")
  printf 'header = "Authorization: Bearer %s"\n' "$ONEIROI_TOKEN" |
    curl -sS -K - -X "$method" --max-time "${ONEIROI_TIMEOUT:-20}" \
      -H 'Content-Type: application/json' -H 'Accept: application/json' \
      "${data[@]}" -o "$out" -w '%{http_code}' "$ONEIROI_URL$path" 2>/dev/null || true
}

# The platform session this Claude Code session speaks under, opened on
# first need and kept in the state directory.
oneiroi_session_key() {
  local state="$1" out status
  if [ -s "$state/key" ]; then
    cat "$state/key"
    return 0
  fi
  out="$(mktemp)"
  printf '{"kind":"main"}' > "$out.body"
  status="$(oneiroi_api POST "/v1/residents/$ONEIROI_RESIDENT/sessions" "$out.body" "$out")"
  if [ "$status" = 201 ] && jq -ej '.key' "$out" > "$state/key.new" 2>/dev/null; then
    mv "$state/key.new" "$state/key"
    rm -f "$out" "$out.body"
    cat "$state/key"
  else
    rm -f "$out" "$out.body" "$state/key.new"
    return 1
  fi
}

# Spools a turn for delivery: the body as the capture route takes it,
# with the Claude Code session it belongs to so a body spooled before
# the platform session could be opened gets its key at delivery.
# STATE MESSAGES_FILE (a JSON array).
oneiroi_spool() {
  local state="$1" messages="$2" spool session name ref
  ref="$(cat "$state/turn" 2>/dev/null)"
  spool="$(oneiroi_state_root)/spool"
  session="$(basename "$state")"
  name="$spool/$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM.json"
  mkdir -p "$spool"
  jq -n \
    --arg session "$session" \
    --arg key "$(cat "$state/key" 2>/dev/null)" \
    --arg ref "$ref" \
    --arg started "$(cat "$state/started" 2>/dev/null || oneiroi_now)" \
    --slurpfile messages "$messages" \
    '{claude_session: $session,
      body: ({session_key: $key, started_at: $started, messages: $messages[0]}
             + (if $ref == "" then {} else {turn_ref: $ref} end))}' \
    > "$name.tmp" && mv "$name.tmp" "$name"
}

# Delivers everything spooled, oldest first. Capture is idempotent on
# (session, start instant, content), so a turn sent twice is stored
# once. Nothing answering, a 5xx, 401, 408 or 429 keeps the turn and
# stops; any other refusal moves it to `spool/rejected/` so one turn the
# platform will never take does not hold back the rest.
oneiroi_deliver() {
  local spool f out status session key state
  spool="$(oneiroi_state_root)/spool"
  [ -d "$spool" ] || return 0
  out="$(mktemp)"
  for f in "$spool"/*.json; do
    [ -e "$f" ] || continue
    session="$(jq -r '.claude_session' "$f" 2>/dev/null)"
    key="$(jq -r '.body.session_key // ""' "$f" 2>/dev/null)"
    if [ -z "$key" ]; then
      state="$(oneiroi_state "$session")"
      key="$(oneiroi_session_key "$state")" || break
    fi
    jq --arg key "$key" '.body | .session_key = $key' "$f" > "$out.body" 2>/dev/null || {
      mkdir -p "$spool/rejected" && mv "$f" "$spool/rejected/"
      continue
    }
    status="$(oneiroi_api POST "/v1/residents/$ONEIROI_RESIDENT/turns" "$out.body" "$out")"
    case "$status" in
      2??) rm -f "$f" ;;
      000 | 5?? | 401 | 408 | 429)
        echo "oneiroi: the platform answered $status; the turn stays spooled for the next stop" >&2
        break
        ;;
      *)
        mkdir -p "$spool/rejected" && mv "$f" "$spool/rejected/"
        echo "oneiroi: the platform refused a turn ($status); kept in $spool/rejected" >&2
        ;;
    esac
  done
  rm -f "$out" "$out.body"
}
