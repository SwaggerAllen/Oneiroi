#!/usr/bin/env bash
# Oneiroi's reader (xenia#11, kumbukumbu#48): the inbound hands on the
# witness's machine. It reads what reaches the resident (Substack DMs in
# a browser profile signed in as her, her Gmail through the witness's
# claude.ai connector), delivers it to Oneiroi, and sends the replies the
# witness approved, exactly as approved.
#
#   reader.sh wait    every few minutes (launchd): asks Oneiroi what waits
#                     for the reader and sends only when a reply does
#   reader.sh scrape  twice a day (launchd): reads and delivers
#   reader.sh send    sends the approved replies now
#   reader.sh research  researches the open questions now (seshat#38)
#   reader.sh login   opens the reader's browser profile, visible, to sign
#                     in to Substack as the resident once
#
# The model never holds the Oneiroi token: this script makes every call
# to Oneiroi, and headless Claude Code only reads and writes JSON files
# in `work/`. The browser reaches only the sites on the witness's
# allowlists, set on Connections and read from Oneiroi at each run
# (xenia#16): one for reading correspondence, one for research. A scrape
# run cannot type, so a stranger's message cannot make it send anything;
# a send run is given the approved replies and nothing else to do; a
# research run browses in a profile signed in nowhere, so whatever it
# types can post or send nothing as the resident.
#
# Reads ~/.config/oneiroi/reader.conf (ONEIROI_URL, ONEIROI_RESIDENT,
# SUBSTACK_ACCOUNT, EMAIL_ACCOUNT, READER_ORIGINS) and the token from
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
  local prompt="$1" tools="$2" origins="${3:-$SCRAPE_ORIGINS}" profile="${4:-browser-profile}" turns="${5:-${ONEIROI_READER_TURNS:-80}}"
  browser_config "$origins" "$profile"
  (cd "$READER" && "${ONEIROI_CLAUDE:-claude}" -p "$(cat "$KIT/prompts/$prompt.md")" \
    --mcp-config "$WORK/mcp.json" \
    --allowedTools "$tools" \
    --max-turns "$turns" \
    --output-format text)
}

# The witness's allowlists from Oneiroi; reader.conf's for reading
# correspondence when Oneiroi does not answer, and no research then.
sites() {
  local status
  SCRAPE_ORIGINS="${READER_ORIGINS:-$DEFAULT_ORIGINS}"
  RESEARCH_ORIGINS=""
  status="$(oneiroi_api GET "/v1/residents/$ONEIROI_RESIDENT/reader" "" "$OUT")"
  [ "$status" = 200 ] || return 0
  SCRAPE_ORIGINS="$(jq -r '.scrape | join(";")' "$OUT")"
  RESEARCH_ORIGINS="$(jq -r '.research | join(";")' "$OUT")"
}

wait_for_work() {
  local status fresh asked
  status="$(oneiroi_api GET "/v1/residents/$ONEIROI_RESIDENT/waiting" "" "$OUT")"
  [ "$status" = 200 ] || { say "Oneiroi answered $status to what waits"; return 0; }
  touch "$STATE/given-up" "$STATE/research-given-up"
  fresh="$(jq -r --rawfile gone "$STATE/given-up" \
    '($gone | split("\n")) as $g | [.replies[] | select((.number | tostring) as $n | ($g | index([$n])) == null)] | length' \
    "$OUT" 2>/dev/null)"
  asked="$(jq -r --rawfile gone "$STATE/research-given-up" \
    '($gone | split("\n")) as $g | [(.research // [])[] | select((.number | tostring) as $n | ($g | index([$n])) == null)] | length' \
    "$OUT" 2>/dev/null)"
  if [ "${fresh:-0}" -gt 0 ]; then
    say "$fresh approved repl$([ "$fresh" = 1 ] && echo y || echo ies) to send"
    send
    rmdir "$STATE/lock" 2>/dev/null
  fi
  if [ "${asked:-0}" -gt 0 ]; then
    say "$asked research question(s) open"
    research
    rmdir "$STATE/lock" 2>/dev/null
  fi
  if [ "$(jq -r '(.digests // []) | length' "$OUT" 2>/dev/null || echo 0)" -gt 0 ]; then
    say "a digest is asked"
    digest
  fi
}

# The digest (seshat#40): asked, never on a clock. What reached her
# mailbox since the instant Oneiroi gives (newsletters, Substack's posts
# and notes, what she subscribes to), read through the Gmail connector
# and, for a post's page, the correspondence allowlist; a summary and an
# item per piece, in the reader's words. Tried twice, then said failed.
digest() {
  local number since status tries
  lock
  status="$(oneiroi_api GET "/v1/residents/$ONEIROI_RESIDENT/digests" "" "$OUT")"
  [ "$status" = 200 ] || { say "Oneiroi answered $status to the digests"; return 0; }
  number="$(jq -r '.[0].number // empty' "$OUT")"
  [ -n "$number" ] || return 0
  since="$(jq -r '.[0].since' "$OUT")"
  jq -n --arg since "$since" --arg email "${EMAIL_ACCOUNT:-}" --arg substack "${SUBSTACK_ACCOUNT:-}" \
    '{since: $since, email_account: $email, substack_account: $substack}' > "$WORK/digest.json"
  rm -f "$WORK/digested.json"

  model digest "Read(/work/digest.json),Write(/work/digested.json),$(browser read),mcp__claude_ai_Gmail__search_threads,mcp__claude_ai_Gmail__get_thread" \
    "$SCRAPE_ORIGINS" browser-profile "${ONEIROI_READER_DIGEST_TURNS:-150}" ||
    say "the digest run ended badly"

  if jq -e '(.summary | type == "string") and (.items | type == "array")' "$WORK/digested.json" > /dev/null 2>&1; then
    jq '{summary, items: [.items[] | {source, title, link, notes}]}' "$WORK/digested.json" > "$OUT.body"
    status="$(oneiroi_api POST "/v1/residents/$ONEIROI_RESIDENT/digests/$number/answer" "$OUT.body" "$OUT")"
    rm -f "$OUT.body"
    say "digest #$number compiled; Oneiroi answered $status"
  else
    tries="$(( $(grep -c "^$number\$" "$STATE/digest-tries" 2>/dev/null || echo 0) + 1 ))"
    echo "$number" >> "$STATE/digest-tries"
    say "digest #$number not compiled (try $tries of 2)"
    if [ "$tries" -ge 2 ]; then
      jq -n '{reason: "the reader ran twice and wrote no digest"}' > "$OUT.body"
      status="$(oneiroi_api POST "/v1/residents/$ONEIROI_RESIDENT/digests/$number/failed" "$OUT.body" "$OUT")"
      rm -f "$OUT.body"
      say "digest #$number said failed; Oneiroi answered $status"
    fi
  fi
}

# Research (seshat#38): each open question in turn, in its own profile
# signed in nowhere, held to the research allowlist. An answer is the
# notes it wrote; a question it could not answer is tried twice, then
# said failed with the reason.
research() {
  local number status tries
  lock
  [ -n "$RESEARCH_ORIGINS" ] || { say "no research allowlist; the witness sets it on Connections"; return 0; }
  status="$(oneiroi_api GET "/v1/residents/$ONEIROI_RESIDENT/research" "" "$OUT")"
  [ "$status" = 200 ] || { say "Oneiroi answered $status to the research"; return 0; }
  touch "$STATE/research-given-up"
  cp "$OUT" "$WORK/open-research.json"
  for number in $(jq -r '.[].number' "$WORK/open-research.json"); do
    grep -qx "$number" "$STATE/research-given-up" && continue
    jq --argjson n "$number" --arg sites "$RESEARCH_ORIGINS" \
      '[.[] | select(.number == $n)][0] | {number, question, urls, sites: ($sites | split(";"))}' \
      "$WORK/open-research.json" > "$WORK/research.json"
    rm -f "$WORK/found.json"

    model research "Read(/work/research.json),Write(/work/found.json),$(browser write)" \
      "$RESEARCH_ORIGINS" research-profile "${ONEIROI_READER_RESEARCH_TURNS:-200}" ||
      say "the research run ended badly"

    if jq -e '(.summary | type == "string") and (.sources | type == "array")' "$WORK/found.json" > /dev/null 2>&1; then
      jq '{summary, sources: [.sources[] | {url, title, notes}]}' "$WORK/found.json" > "$OUT.body"
      status="$(oneiroi_api POST "/v1/residents/$ONEIROI_RESIDENT/research/$number/answer" "$OUT.body" "$OUT")"
      say "research #$number answered; Oneiroi answered $status"
      rm -f "$OUT.body"
    else
      tries="$(( $(grep -c "^$number\$" "$STATE/research-tries" 2>/dev/null || echo 0) + 1 ))"
      echo "$number" >> "$STATE/research-tries"
      say "research #$number not answered (try $tries of 2)"
      if [ "$tries" -ge 2 ]; then
        echo "$number" >> "$STATE/research-given-up"
        jq -n '{reason: "the reader ran twice and wrote no notes"}' > "$OUT.body"
        status="$(oneiroi_api POST "/v1/residents/$ONEIROI_RESIDENT/research/$number/failed" "$OUT.body" "$OUT")"
        rm -f "$OUT.body"
        say "research #$number said failed; Oneiroi answered $status"
      fi
    fi
  done
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

# The browser for this run: Chrome on the reader's own profile,
# headless, held to the allowlist read from reader.conf at the run, so
# the list is edited there and nothing is reinstalled. `*` lifts it.
DEFAULT_ORIGINS="https://substack.com;https://www.substack.com"

browser_config() {
  local origins="$1" profile="$READER/$2"
  jq -n --arg profile "$profile" --arg origins "$origins" '{mcpServers: {playwright: {
    command: "npx",
    args: (["-y", "@playwright/mcp@0.0.84", "--browser", "chrome", "--headless", "--user-data-dir", $profile]
           + (if $origins == "*" then [] else ["--allowed-origins", $origins] end))}}}' > "$WORK/mcp.json"
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
  wait) setup && sites && wait_for_work ;;
  send) setup && sites && send ;;
  scrape) setup && sites && scrape ;;
  research) setup && sites && research ;;
  digest) setup && sites && digest ;;
  *) echo "usage: reader.sh wait|send|scrape|research|digest|login" >&2; exit 2 ;;
esac
