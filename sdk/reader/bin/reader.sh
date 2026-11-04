#!/usr/bin/env bash
# Oneiroi's reader (xenia #11, kumbukumbu #48): the inbound hands on the
# witness's machine. It reads what reaches the resident (Substack DMs in
# a browser profile signed in as her, her Gmail through the witness's
# claude.ai connector), delivers it to Oneiroi, and sends the replies the
# witness approved, exactly as approved.
#
#   reader.sh wait    every few minutes (launchd): asks Oneiroi what waits
#                     for the reader and sends only when a reply does
#   reader.sh scrape  twice a day (launchd): reads and delivers
#   reader.sh send    sends the approved replies now
#   reader.sh login   opens the reader's browser profile, visible, to sign
#                     in to Substack as the resident once
#
# The model never holds the Oneiroi token: this script makes every call
# to Oneiroi, and headless Claude Code only reads and writes JSON files
# in `work/`. The browser reaches Substack's origins alone. A scrape run
# cannot type, so a stranger's message cannot make it send anything; a
# send run is given the approved replies and nothing else to do.
#
# Reads ~/.config/oneiroi/reader.conf (ONEIROI_URL, ONEIROI_RESIDENT,
# SUBSTACK_ACCOUNT, EMAIL_ACCOUNT) and the token from
# ~/.config/oneiroi/reader.json, never from the environment of a model.
set -uo pipefail

# The kit (scripts, prompts) and the folder runs work in: one and the same
# once installed; apart only for the kit's test.
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
READER="${ONEIROI_READER_DIR:-$KIT}"
CONFIG="${ONEIROI_READER_CONFIG:-$HOME/.config/oneiroi}"
. "$KIT/lib/common.sh"

# How many times a reply is tried before it is left for the witness.
ATTEMPTS="${ONEIROI_READER_ATTEMPTS:-3}"

say() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) reader $*"; }

setup() {
  [ -r "$CONFIG/reader.conf" ] || { say "no $CONFIG/reader.conf; run install.sh"; exit 0; }
  # shellcheck disable=SC1091
  . "$CONFIG/reader.conf"
  ONEIROI_URL="${ONEIROI_URL%/}"
  ONEIROI_TOKEN="$(jq -r '.token // empty' "$CONFIG/reader.json" 2>/dev/null)"
  [ -n "$ONEIROI_URL" ] && [ -n "${ONEIROI_RESIDENT:-}" ] && [ -n "$ONEIROI_TOKEN" ] ||
    { say "the reader is not configured (url, resident or token missing)"; exit 0; }
  STATE="$READER/state"
  WORK="$READER/work"
  mkdir -p "$STATE" "$WORK" && chmod 700 "$STATE" "$WORK"
  OUT="$(mktemp)"
  trap 'rm -f "$OUT"; rmdir "$STATE/lock" 2>/dev/null' EXIT
}

# One run at a time: the browser profile is one Chrome's. A lock older
# than an hour is a run that died holding it.
lock() {
  find "$STATE/lock" -maxdepth 0 -mmin +60 -exec rmdir {} \; 2>/dev/null
  mkdir "$STATE/lock" 2>/dev/null || { say "another run holds the lock; later"; trap 'rm -f "$OUT"' EXIT; exit 0; }
}

# Headless Claude Code in this folder, on the witness's plan, with the
# reader's prompt and only the tools named. Anything else is refused,
# since a headless run asks nobody.
model() {
  local prompt="$1" tools="$2"
  (cd "$READER" && "${ONEIROI_CLAUDE:-claude}" -p "$(cat "$KIT/prompts/$prompt.md")" \
    --mcp-config "$READER/mcp.json" \
    --allowedTools "$tools" \
    --max-turns "${ONEIROI_READER_TURNS:-80}" \
    --output-format text)
}

wait_for_work() {
  local status fresh
  status="$(oneiroi_api GET "/v1/residents/$ONEIROI_RESIDENT/waiting" "" "$OUT")"
  [ "$status" = 200 ] || { say "Oneiroi answered $status to what waits"; return 0; }
  touch "$STATE/given-up"
  fresh="$(jq -r --rawfile gone "$STATE/given-up" \
    '($gone | split("\n")) as $g | [.replies[] | select((.number | tostring) as $n | ($g | index([$n])) == null)] | length' \
    "$OUT" 2>/dev/null)"
  [ "${fresh:-0}" -gt 0 ] || return 0
  say "$fresh approved repl$([ "$fresh" = 1 ] && echo y || echo ies) to send"
  send
}

send() {
  local status number tries url
  lock
  status="$(oneiroi_api GET "/v1/residents/$ONEIROI_RESIDENT/replies" "" "$OUT")"
  [ "$status" = 200 ] || { say "Oneiroi answered $status to the replies"; return 0; }
  touch "$STATE/given-up"
  jq --rawfile gone "$STATE/given-up" \
    '($gone | split("\n")) as $g
     | [.[] | select((.number | tostring) as $n | ($g | index([$n])) == null)
            | {number, platform, account, thread, to, in_reply_to, text}]' \
    "$OUT" > "$WORK/outbox.json" || return 0
  [ "$(jq length "$WORK/outbox.json")" -gt 0 ] || return 0
  rm -f "$WORK/sent.json"

  model send "Read(/work/outbox.json),Write(/work/sent.json),$(browser write),mcp__claude_ai_Gmail__reply" ||
    say "the send run ended badly"

  # Each reply the run says it sent is marked sent with where it is now;
  # one it did not is tried again later, up to ATTEMPTS times.
  for number in $(jq -r '.[].number' "$WORK/outbox.json"); do
    url="$(jq -r --argjson n "$number" '[.[]? | select(.number == $n)][0].url // empty' "$WORK/sent.json" 2>/dev/null)"
    if jq -e --argjson n "$number" 'any(.[]?; .number == $n)' "$WORK/sent.json" > /dev/null 2>&1; then
      jq -n --arg url "$url" 'if $url == "" then {} else {url: $url} end' > "$OUT.body"
      status="$(oneiroi_api POST "/v1/residents/$ONEIROI_RESIDENT/replies/$number/sent" "$OUT.body" "$OUT")"
      say "reply #$number sent; Oneiroi answered $status"
      rm -f "$OUT.body"
    else
      tries="$(( $(grep -c "^$number\$" "$STATE/tries" 2>/dev/null || echo 0) + 1 ))"
      echo "$number" >> "$STATE/tries"
      say "reply #$number not sent (try $tries of $ATTEMPTS)"
      [ "$tries" -lt "$ATTEMPTS" ] || { echo "$number" >> "$STATE/given-up"; say "reply #$number left for the witness"; }
    fi
  done
}

scrape() {
  local since count status
  lock
  since="$(cat "$STATE/last-scrape" 2>/dev/null || date -u -v-2d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)"
  jq -n --arg since "$since" --arg substack "${SUBSTACK_ACCOUNT:-}" --arg email "${EMAIL_ACCOUNT:-}" \
    '{since: $since, substack_account: $substack, email_account: $email}' > "$WORK/scrape.json"
  rm -f "$WORK/inbound.json"
  started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  model scrape "Read(/work/scrape.json),Write(/work/inbound.json),$(browser read),mcp__claude_ai_Gmail__search_threads,mcp__claude_ai_Gmail__get_thread" ||
    say "the scrape run ended badly"

  [ -s "$WORK/inbound.json" ] || { say "the scrape wrote nothing; nothing delivered"; return 0; }
  # Held to the delivery's shape here, whatever the run wrote: an id the
  # run did not give is the message's own digest, so a message read
  # twice is one.
  jq -c '[.[]? | select(.platform and .account and .sender and .text and .sent_at)
          | {platform, account, external_id: (.external_id // null | if . == null then null else tostring end),
             sender, sender_name, verified: (.verified == true), thread: (.thread // null | if . == null then null else tostring end),
             subject, text, sent_at}]' \
    "$WORK/inbound.json" > "$WORK/delivery.json" 2>/dev/null || { say "the scrape wrote something that is not a list of messages"; return 0; }
  # A message the run gave no id is named by a digest of what it is.
  jq -r '.[] | if .external_id == null then ([.platform, (.thread // ""), .sender, .sent_at, .text] | @json) else "" end' \
    "$WORK/delivery.json" | while IFS= read -r key; do
    if [ -n "$key" ]; then printf '%s' "$key" | shasum -a 256 | cut -c1-40; else echo ""; fi
  done | jq -R . | jq -s . > "$WORK/digests.json"
  jq --slurpfile d "$WORK/digests.json" \
    '[to_entries[] | .value + (if .value.external_id == null then {external_id: $d[0][.key]} else {} end)]' \
    "$WORK/delivery.json" > "$WORK/delivery.json.tmp" && mv "$WORK/delivery.json.tmp" "$WORK/delivery.json"
  count="$(jq length "$WORK/delivery.json")"
  for start in $(seq 0 40 $((count > 0 ? count - 1 : -1))); do
    jq "{messages: .[$start:$((start + 40))]}" "$WORK/delivery.json" > "$OUT.body"
    status="$(oneiroi_api POST "/v1/residents/$ONEIROI_RESIDENT/correspondence" "$OUT.body" "$OUT")"
    rm -f "$OUT.body"
    [ "$status" = 200 ] || { say "Oneiroi answered $status to a delivery; the window is kept for next time"; return 0; }
  done
  echo "$started" > "$STATE/last-scrape"
  say "$count message(s) delivered"
}

# The browser's tools: reading moves through pages and never types.
browser() {
  local read="mcp__playwright__browser_navigate,mcp__playwright__browser_navigate_back,mcp__playwright__browser_snapshot,mcp__playwright__browser_click,mcp__playwright__browser_wait_for,mcp__playwright__browser_tabs,mcp__playwright__browser_close"
  if [ "$1" = write ]; then
    echo "$read,mcp__playwright__browser_type,mcp__playwright__browser_press_key"
  else
    echo "$read"
  fi
}

login() {
  local profile="$READER/browser-profile"
  mkdir -p "$profile"
  say "opening Chrome on the reader's profile: sign in to Substack as the resident, then quit Chrome (Cmd-Q)"
  open -na "Google Chrome" --args --user-data-dir="$profile" --no-first-run "https://substack.com/sign-in"
}

case "${1:-}" in
  login) login ;;
  wait) setup && wait_for_work ;;
  send) setup && send ;;
  scrape) setup && scrape ;;
  *) echo "usage: reader.sh wait|send|scrape|login" >&2; exit 2 ;;
esac
