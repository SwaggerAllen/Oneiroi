#!/usr/bin/env bash
# Oneiroi Claude Code adapter: the UserPromptSubmit hook (spec §8, interface 2).
#
# Reports the turn to the platform under the adapter's session and
# prints the context index for Claude Code to inject into the prompt.
# Reads Claude Code's hook payload on stdin ({"session_id": ..., "prompt": ...}).
# Needs ONEIROI_URL, ONEIROI_RESIDENT, ONEIROI_TOKEN; curl and jq.
#
# A claim about Claude Code's hook payload until a fixture is recorded
# from a real session (conventions §9).
set -euo pipefail

payload="$(cat)"
session="$(printf '%s' "$payload" | jq -r '.session_id // empty')"
[ -n "$session" ] || exit 0
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/oneiroi"
mkdir -p "$state_dir"

# One platform session per Claude Code session: opened on the first turn.
key_file="$state_dir/$session.key"
if [ ! -s "$key_file" ]; then
  curl -sS -X POST "$ONEIROI_URL/v1/residents/$ONEIROI_RESIDENT/sessions" \
    -H "Authorization: Bearer $ONEIROI_TOKEN" -H 'Content-Type: application/json' \
    -d '{"kind":"main","adapter":"claude-code"}' | jq -r '.key' > "$key_file"
fi
key="$(cat "$key_file")"

ref="$(curl -sS -X POST "$ONEIROI_URL/v1/residents/$ONEIROI_RESIDENT/turn-start" \
  -H "Authorization: Bearer $ONEIROI_TOKEN" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg k "$key" '{session_key: $k}')" | jq -r '.turn_ref')"
printf '%s\n' "$ref" > "$state_dir/$session.turn"
date -u +%Y-%m-%dT%H:%M:%SZ > "$state_dir/$session.started"

# What the platform would put in front of its own brain: printed so Claude
# Code injects it as context for this prompt.
curl -sS "$ONEIROI_URL/v1/residents/$ONEIROI_RESIDENT/context" \
  -H "Authorization: Bearer $ONEIROI_TOKEN" | jq -r '.text // empty'
