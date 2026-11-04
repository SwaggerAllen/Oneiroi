#!/usr/bin/env bash
# Oneiroi Claude Code adapter: the letter watch (kumbukumbu#48).
#
# Armed by the Stop hook as an `asyncRewake` hook: Claude Code runs it in
# the background once the turn has ended, and when it exits 2 Claude
# Code wakes the session, idle or not, with what it printed to stderr
# (its hook docs, "Run hooks in the background"). So a house letter
# addressed to this conversation reaches the same session that is open,
# the one whose letter it answers, rather than a new one.
#
# Every so often it asks the platform which letters wait for this
# conversation, by number and sender only (never their words, as the
# turn's notice is told them), and wakes the session for any it has not
# woken it for before. Each letter wakes a session once: one the woken
# turn leaves unread does not wake it again. letter_inbox, as ever, is
# the read that marks a letter read.
#
# One watch per session: every stop arms a new one and the one before
# it gives way. It ends when Claude Code ends (its parent goes), when the
# platform refuses the token, or at the hook's timeout. At most
# ONEIROI_WAKES_PER_HOUR wakes an hour (6 unless set), so two
# conversations answering each other cannot wake each other without end;
# a letter held back by the bound wakes the session once the hour allows.
#
# Reads Claude Code's Stop payload on stdin ({"session_id", ...}). Does
# nothing at all until the plugin's options are set, and nothing for a
# session that has no conversation on the platform yet.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# The poll's answer, a file the exit removes (a global, since the trap
# runs after main's locals are gone).
out=""
trap '[ -n "$out" ] && rm -f "$out"' EXIT

oneiroi_parent() { ps -o ppid= -p "$$" 2>/dev/null | tr -d ' '; }

main() {
  local payload session state key gen parent interval limit status fresh now count
  payload="$(cat)"
  oneiroi_env || return 0

  session="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)"
  [ -n "$session" ] || return 0
  state="$(oneiroi_state "$session")" || return 0
  [ -s "$state/key" ] || return 0
  key="$(cat "$state/key")"

  gen="$$-$(date +%s)-$RANDOM"
  printf '%s' "$gen" > "$state/watch"
  touch "$state/letters.woken"
  parent="$(oneiroi_parent)"
  interval="${ONEIROI_WATCH_SECONDS:-30}"
  limit="${ONEIROI_WAKES_PER_HOUR:-6}"
  out="$(mktemp)"

  while :; do
    sleep "$interval"
    # A newer stop armed its own watch, or Claude Code is gone.
    [ "$(cat "$state/watch" 2>/dev/null)" = "$gen" ] || return 0
    [ "$(oneiroi_parent)" = "$parent" ] || return 0

    status="$(oneiroi_api GET "/v1/residents/$ONEIROI_RESIDENT/waiting?session_key=$key" "" "$out")"
    case "$status" in
      200) ;;
      401 | 403 | 404) return 0 ;;
      *) continue ;;
    esac

    # The letters waiting that have not woken this session before.
    fresh="$(jq -c --rawfile woken "$state/letters.woken" '
      ($woken | split("\n")) as $w
      | [.letters[] | select((.number | tostring) as $n | ($w | index([$n])) == null)]
    ' "$out" 2>/dev/null)" || continue
    [ "$fresh" != "[]" ] && [ -n "$fresh" ] || continue

    now="$(date +%s)"
    count="$(awk -v since="$((now - 3600))" '$1 > since' "$state/wakes" 2>/dev/null | wc -l | tr -d ' ')"
    [ "${count:-0}" -lt "$limit" ] || continue

    printf '%s' "$fresh" | jq -r '.[].number' >> "$state/letters.woken"
    echo "$now" >> "$state/wakes"
    printf '%s' "$fresh" | jq -r '
      (if length == 1 then "A house letter waits" else "\(length) house letters wait" end)
      + " for this conversation: "
      + (map("#\(.number) from \(.from)"
             + (if .in_reply_to then " (in reply to #\(.in_reply_to))" else "" end))
         | join(", "))
      + ". letter_inbox reads them; letter_send with in_reply_to answers each in its thread."
    ' >&2
    return 2
  done
}

main
exit $?
