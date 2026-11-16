#!/usr/bin/env bash
# Oneiroi on a Mac, for one resident, the same steps for the first or the
# fifth (dioscuri#8; the witness, 2026-11-16: "setting up one resident vs
# setting up two would ideally have identical steps"). Served by Oneiroi
# at /setup.sh with its own address filled in; the client's Connections
# screen gives the command with the resident's slug and id:
#
#   bash <(curl -fsSL <oneiroi>/setup.sh) writer --slug <slug> --resident <id>
#   bash <(curl -fsSL <oneiroi>/setup.sh) reader --slug <slug> --resident <id> \
#     [--substack <handle>] [--email <address>]
#
# Downloads the kit (the Claude Code plugin, its marketplace, the reader)
# from the same Oneiroi into ~/.oneiroi/kit, then runs the one asked for:
#
#   writer  her writing room, ~/Oneiroi/<slug>-writing, under her own
#           Claude Code configuration (~/.claude-<slug>): sdk/claude-code/writer.sh
#   reader  her reader, ~/.oneiroi/readers/<slug>, with its own jobs:
#           sdk/reader/install.sh
#
# The token is asked for without echo when it is needed (the one shown
# on Connections), or taken from ONEIROI_TOKEN; never an argument.
set -euo pipefail

URL="${ONEIROI_URL:-__ONEIROI_URL__}"
URL="${URL%/}"

die() {
  echo "setup.sh: $*" >&2
  exit 2
}

what="${1:-}"
[ $# -gt 0 ] && shift
SLUG="" RESIDENT="" SUBSTACK="" EMAIL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --slug) SLUG="$2"; shift 2 ;;
    --resident) RESIDENT="$2"; shift 2 ;;
    --substack) SUBSTACK="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    *) die "unknown option $1" ;;
  esac
done

case "$what" in writer | reader) ;; *) die "say writer or reader first" ;; esac
[ -n "$SLUG" ] && [ -n "$RESIDENT" ] || die "--slug and --resident are both needed"
printf '%s' "$SLUG" | grep -Eq '^[a-z][a-z0-9-]{1,39}$' || die "--slug is the resident's slug"
for tool in curl tar jq claude; do
  command -v "$tool" > /dev/null || die "$tool is needed and is not on PATH"
done

# The kit, fresh from this Oneiroi each time: what it runs is what it serves.
KIT="${ONEIROI_KIT_DIR:-$HOME/.oneiroi/kit}"
mkdir -p "$KIT.new"
curl -fsSL "$URL/setup/kit.tar.gz" | tar -xz -C "$KIT.new" || die "the kit did not download from $URL"
[ -f "$KIT.new/sdk/claude-code/install.sh" ] || die "the kit from $URL is not whole"
rm -rf "$KIT.old"
[ -d "$KIT" ] && mv "$KIT" "$KIT.old"
mv "$KIT.new" "$KIT"
rm -rf "$KIT.old"

case "$what" in
  writer)
    room="${ONEIROI_ROOMS_DIR:-$HOME/Oneiroi}/$SLUG-writing"
    exec bash "$KIT/sdk/claude-code/writer.sh" "$room" "$SLUG" "$RESIDENT" "$URL"
    ;;
  reader)
    exec bash "$KIT/sdk/reader/install.sh" --name "$SLUG" --url "$URL" --resident "$RESIDENT" \
      --substack "$SUBSTACK" --email "$EMAIL"
    ;;
esac
