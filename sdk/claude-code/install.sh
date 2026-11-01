#!/usr/bin/env bash
# Oneiroi's Claude Code plugin: install it for one project folder, from a
# shell (spec §8; README.md here). The README's in-session steps do the
# same through /plugin; this is for a script or a second machine.
#
# Usage: install.sh <project-dir> [<resident-id> [<platform-url>]]
#
# Adds this repository as the `oneiroi` marketplace (or the source in
# ONEIROI_MARKETPLACE, e.g. SwaggerAllen/Oneiroi), installs the plugin at
# local scope in <project-dir> with the URL and the resident id as its
# options, enables it there, and saves the token. The token is taken from
# ONEIROI_TOKEN or asked for without echo, and reaches Claude Code on
# stdin (`claude plugin configure --values-stdin`), never on a command
# line; Claude Code keeps it in its secure credential store, not in a
# settings file. `claude plugin install` from a shell never prompts for
# options (Claude Code's plugin docs), which is why they are passed here.
#
# The options are per user, not per folder: Claude Code reads a plugin's
# saved options from user settings only and ignores project and local
# entries. The README says what that means for a second resident.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin="oneiroi@oneiroi"

die() {
  echo "install.sh: $*" >&2
  exit 1
}

[ $# -ge 1 ] || die "usage: install.sh <project-dir> [<resident-id> [<platform-url>]]"
command -v claude > /dev/null || die "the claude command is needed"
command -v jq > /dev/null || die "jq is needed (the hooks use it too)"
command -v curl > /dev/null || die "curl is needed by the hooks"
[ -d "$1" ] || die "no directory $1"
project="$(cd "$1" && pwd)"
marketplace="${ONEIROI_MARKETPLACE:-$(cd "$here/../.." && pwd)}"

resident="${2:-}"
url="${3:-https://oneiroi.onrender.com}"
token="${ONEIROI_TOKEN:-}"
[ -n "$resident" ] || read -r -p "Resident id: " resident
if [ -z "$token" ]; then
  read -r -s -p "Adapter token (shown once when the adapter was registered): " token
  echo
fi
url="${url%/}"
[ -n "$resident" ] && [ -n "$token" ] || die "the resident id and the token are both needed"

cd "$project"

# Installed already is not a failure: the steps after it set what changed.
if ! claude plugin install oneiroi --marketplace "$marketplace" --scope local \
  --config "url=$url" --config "resident=$resident"; then
  echo "install.sh: the install did not complete; enabling and configuring what is there" >&2
fi

# Enabled already is not a failure either; what counts is the state after.
claude plugin enable "$plugin" --scope local || true
claude plugin list --json | jq -e --arg id "$plugin" 'any(.[]; .id == $id and .enabled)' > /dev/null ||
  die "the plugin is not enabled in $project; see claude plugin list"

# The token rides stdin into jq too: an argument is in the process list.
printf '%s' "$token" |
  jq -cRs --arg url "$url" --arg resident "$resident" '{url: $url, resident: $resident, token: .}' |
  claude plugin configure "$plugin" --values-stdin

cat << EOF

The oneiroi plugin is enabled in $project, for you only.
Start Claude Code there and open it from the Claude app:

  cd "$project" && claude remote-control --spawn session

The README says how to check it worked.
EOF
