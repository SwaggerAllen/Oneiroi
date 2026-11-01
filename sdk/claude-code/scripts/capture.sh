#!/usr/bin/env bash
# Oneiroi Claude Code adapter: the Stop hook (spec §8, interface 2).
#
# Captures the turn from the hook payloads, never from the transcript's
# clock: the witness's words as the turn-start hook kept them from
# UserPromptSubmit's `prompt`, and the reply as Stop's
# `last_assistant_message`. Claude Code's docs say the transcript file
# "is written asynchronously and may lag", and that a Stop hook needing
# the final text should use that field instead of reading the file.
# The tool calls in between are not taken from the transcript, for the
# same reason; the memory tools' calls reach the platform through its
# MCP server under this turn, as events of their own.
#
# Posted with the turn's ref and the platform's start instant,
# idempotent on (session, start instant, content); spooled first and
# delivered with everything spooled before it, so a turn is never lost
# to a blip and never stored twice.
#
# `stop_hook_active` is true when another Stop hook kept Claude going.
# This hook never does (it never exits 2 and prints no decision); on
# such a Stop the turn's words are already captured, and what is taken
# is the reply's further words, once, under the same turn.
#
# Reads Claude Code's hook payload on stdin. A claim about that payload
# until fixtures are recorded from a real session (conventions §9). Does
# nothing at all until the plugin's options are set.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

main() {
  local payload session state active now
  payload="$(cat)"
  oneiroi_env || return 0
  oneiroi_record "$payload"

  session="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)"
  [ -n "$session" ] || return 0
  state="$(oneiroi_state "$session")" || return 0
  active="$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null)"
  printf '%s' "$payload" | jq -j '.last_assistant_message // ""' > "$state/reply" 2>/dev/null
  now="$(oneiroi_now)"

  if [ -f "$state/prompt" ]; then
    jq -n --rawfile u "$state/prompt" --rawfile a "$state/reply" \
      --arg at "$(cat "$state/started" 2>/dev/null)" --arg now "$now" \
      '[{role: "user", content: $u, sent_at: $at}]
       + (if $a == "" then [] else [{role: "assistant", content: $a, sent_at: $now}] end)' \
      > "$state/messages.json" &&
      oneiroi_spool "$state" "$state/messages.json" &&
      rm -f "$state/prompt" && mv "$state/reply" "$state/replied"
  elif [ "$active" = true ] && [ -s "$state/reply" ] && [ -f "$state/started" ] &&
    ! cmp -s "$state/reply" "$state/replied"; then
    jq -n --rawfile a "$state/reply" --arg now "$now" \
      '[{role: "assistant", content: $a, sent_at: $now}]' > "$state/messages.json" &&
      oneiroi_spool "$state" "$state/messages.json" &&
      mv "$state/reply" "$state/replied"
  fi
  rm -f "$state/messages.json" "$state/reply"

  oneiroi_deliver
}

main "$@"
exit 0
