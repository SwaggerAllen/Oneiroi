#!/usr/bin/env bash
# Oneiroi Claude Code adapter: the Stop hook (spec §8, interface 2).
#
# Reads the session transcript Claude Code names in the hook payload
# ({"session_id": ..., "transcript_path": ...}), takes the messages since
# the turn started, and posts them as the turn, idempotent on (session,
# started_at, hash). A failure spools the turn to retry on the next stop,
# so a turn is never lost to a blip and never stored twice.
# Needs ONEIROI_URL, ONEIROI_RESIDENT, ONEIROI_TOKEN; curl and jq.
#
# A claim about Claude Code's transcript format until a fixture is
# recorded from a real session (conventions §9).
set -euo pipefail

payload="$(cat)"
session="$(printf '%s' "$payload" | jq -r '.session_id // empty')"
transcript="$(printf '%s' "$payload" | jq -r '.transcript_path // empty')"
[ -n "$session" ] && [ -f "$transcript" ] || exit 0
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/oneiroi"
key="$(cat "$state_dir/$session.key" 2>/dev/null || true)"
ref="$(cat "$state_dir/$session.turn" 2>/dev/null || true)"
started="$(cat "$state_dir/$session.started" 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
[ -n "$key" ] || exit 0

# The turn's messages: user and assistant text since the turn started,
# in order, each with its timestamp and role; tool blocks are left out.
messages="$(jq -c --arg since "$started" '
  select(.type == "user" or .type == "assistant")
  | select((.timestamp // "") >= $since)
  | {role: .type, sent_at: .timestamp,
     content: (.message.content | if type == "string" then . else (map(select(.type == "text") | .text) | join("\n")) end)}
  | select(.content != "")' "$transcript" | jq -s '.')"

body="$(jq -n --arg k "$key" --arg r "$ref" --arg s "$started" --argjson m "$messages" \
  '{session_key: $k, turn_ref: $r, started_at: $s, messages: $m}')"

spool="$state_dir/spool"
mkdir -p "$spool"
printf '%s' "$body" > "$spool/$session-$ref.json"

# Deliver everything spooled, oldest first; capture is idempotent, so a
# turn delivered twice is stored once.
for f in "$spool"/*.json; do
  [ -e "$f" ] || continue
  if curl -sS -f -X POST "$ONEIROI_URL/v1/residents/$ONEIROI_RESIDENT/turns" \
       -H "Authorization: Bearer $ONEIROI_TOKEN" -H 'Content-Type: application/json' \
       --data-binary @"$f" > /dev/null; then
    rm -f "$f"
  else
    break
  fi
done
