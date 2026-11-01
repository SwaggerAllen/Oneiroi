#!/usr/bin/env bash
# Oneiroi Claude Code adapter: the SessionStart hook (spec §8, brain #42).
#
# Usage: session-start.sh PART PARTS, one hook per part (hooks/hooks.json). Prints part PART
# of the resident's session prefix (the prompt, the identity files, the
# contract, and how the platform's words read in Claude Code), which
# Claude Code adds to the session's context. Claude Code takes at most
# 10,000 characters from one hook (its hook docs), and the prefix is
# longer than that, so the hooks block registers PARTS of these and the
# platform cuts the prefix into that many parts; a part past the end
# prints nothing.
#
# By source (Claude Code's `source` field):
# - startup, clear, compact, fork: print. After a compact Claude Code
#   has dropped the old context, so the prefix is given again; a fork
#   is a new session id with none of this one's state, so it is too.
# - resume: print nothing. The prefix is in the resumed transcript
#   (Claude Code replays injected text on resume), and anything in it
#   that changed since rides the first turn, through the digest the
#   turn-start hook sends back.
#
# Reads Claude Code's hook payload on stdin. A claim about that payload
# until fixtures are recorded from a real session (conventions §9):
# `fixtures/` holds the docs' examples and the README says how to record.
# Does nothing at all until the plugin's options are set.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

main() {
  local part="${1:-1}" parts="${2:-1}" payload session source state out status
  payload="$(cat)"
  oneiroi_env || return 0
  [ "$part" = 1 ] && oneiroi_record "$payload"

  session="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)"
  source="$(printf '%s' "$payload" | jq -r '.source // "startup"' 2>/dev/null)"
  [ -n "$session" ] || return 0
  [ "$source" = resume ] && return 0
  state="$(oneiroi_state "$session")" || return 0

  out="$(mktemp)"
  status="$(oneiroi_api GET "/v1/residents/$ONEIROI_RESIDENT/context?runtime=claude-code&limit=$ONEIROI_LIMIT&part=$part&of=$parts" "" "$out")"

  if [ "$status" = 200 ]; then
    jq -j '.text' "$out" 2>/dev/null
    # One part writes the digest, and only after printing: a turn sends
    # it back as what this session holds.
    [ "$part" = 1 ] && jq -j '.digest' "$out" > "$state/digest" 2>/dev/null
  else
    # The session holds less than the digest would say: the first turn
    # sends none and the whole prefix rides it instead.
    : > "$state/prefix.failed"
    [ "$part" = 1 ] &&
      echo "(Oneiroi did not answer when this session started (status $status), so the resident's identity files and agreement are not in this context yet; the first message brings them.)"
  fi
  rm -f "$out"
}

main "$@"
exit 0
