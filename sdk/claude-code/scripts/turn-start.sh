#!/usr/bin/env bash
# Oneiroi Claude Code adapter: the UserPromptSubmit hook (spec §8, brain #42).
#
# Keeps the witness's words for the Stop hook to capture, starts the turn
# on the platform with those words, and prints the turn's context, which
# Claude Code adds beside the prompt: the room's bookmark index, the
# character lane and the madeleine run on the words just typed, what the
# resident has promised, the movement, dates, figures, journal, Honcho,
# a once-only notice when one is owed, and any part of the session prefix
# that changed since the session was given it. The platform records what
# it handed over as the turn's ContextAssembled, so the reply's "drew on"
# inspector shows it, and attributes the memory tools' calls to this turn.
#
# A turn whose Stop never came (Claude Code skips Stop on an interrupt)
# is captured here with the witness's words alone, so they are not lost.
#
# Reads Claude Code's hook payload on stdin ({"session_id", "prompt", ...}).
# A claim about that payload until fixtures are recorded from a real
# session (conventions §9). Does nothing at all until the plugin's
# options are set.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

main() {
  local payload session state key digest body out status
  payload="$(cat)"
  oneiroi_env || return 0
  oneiroi_record "$payload"

  session="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)"
  [ -n "$session" ] || return 0
  state="$(oneiroi_state "$session")" || return 0

  if [ -f "$state/prompt" ]; then
    jq -n --rawfile u "$state/prompt" --arg at "$(cat "$state/started" 2>/dev/null)" \
      '[{role: "user", content: $u, sent_at: $at}]' > "$state/messages.json" &&
      oneiroi_spool "$state" "$state/messages.json"
    rm -f "$state/prompt" "$state/messages.json" "$state/replied"
  fi

  # The words first, with this machine's clock: kept for the capture even
  # if the platform does not answer now. The platform's own instant
  # replaces the clock below when it does.
  printf '%s' "$payload" | jq -j '.prompt // ""' > "$state/prompt" 2>/dev/null
  oneiroi_now > "$state/started"
  rm -f "$state/turn"

  if ! key="$(oneiroi_session_key "$state")"; then
    echo "(Oneiroi did not answer, so this turn carries nothing of the resident's memory from the platform. The witness's words are kept and captured when it answers again.)"
    return 0
  fi

  digest=""
  if [ -f "$state/prefix.failed" ]; then
    rm -f "$state/prefix.failed"
  else
    digest="$(cat "$state/digest" 2>/dev/null)"
  fi

  out="$(mktemp)"
  body="$out.body"
  jq -n --arg k "$key" --rawfile text "$state/prompt" --arg d "$digest" --argjson limit "$ONEIROI_LIMIT" \
    '{session_key: $k, text: $text, prefix_digest: $d, runtime: "claude-code", limit: $limit}' > "$body"
  status="$(oneiroi_api POST "/v1/residents/$ONEIROI_RESIDENT/turn-start" "$body" "$out")"

  if [ "$status" = 201 ]; then
    jq -j '.turn_ref' "$out" > "$state/turn"
    jq -j '.started_at' "$out" > "$state/started"
    jq -j '.digest' "$out" > "$state/digest"
    jq -j '.text' "$out"
  else
    : > "$state/prefix.failed"
    echo "(Oneiroi did not answer this turn's request (status $status), so this turn carries nothing of the resident's memory from the platform. The witness's words are kept and captured when it answers again.)"
  fi
  rm -f "$out" "$body"
}

main "$@"
exit 0
