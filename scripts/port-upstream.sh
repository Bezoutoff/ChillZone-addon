#!/usr/bin/env bash
# Ports commits of Olympus (the remote "upstream") into ChillZone: each one rebranded by
# scripts/rebrand.py patch, then applied with git am, so it keeps its author, date and message.
#   bash scripts/port-upstream.sh <commit>          one commit
#   bash scripts/port-upstream.sh <from>..<to>      the commits after <from> up to <to> (merges left out)
# Each one ported gets a row in UPSTREAM.md's table; commit that file afterwards.
# A patch that does not apply (it touches what ChillZone changed by hand: the membership, the people,
# the texts about Asmon) stops the run: its rejected hunks are left in *.rej files beside their files
# for a hand merge, then: git add -A && git commit -C <upstream commit>.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$#" -eq 1 ] || { printf 'Usage: bash scripts/port-upstream.sh <commit>|<from>..<to>\n' >&2; exit 2; }
if ! git diff --quiet || ! git diff --cached --quiet; then
	printf 'The working tree has changes: commit or stash them first.\n' >&2
	exit 1
fi
git fetch --quiet upstream
case "$1" in
	*..*) range=$1 ;;
	*) range="$1^!" ;;
esac
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
git format-patch --quiet -o "$scratch" "$range"
set -- "$scratch"/*.patch
[ -e "$1" ] || { printf 'No commits to port in that range.\n' >&2; exit 1; }
for patch in "$@"; do
	sha=$(sed -n '1s/^From \([0-9a-f]*\) .*/\1/p' "$patch")
	python3 scripts/rebrand.py patch < "$patch" > "$patch.cz"
	if ! git am --quiet "$patch.cz"; then
		git am --abort
		git apply --reject "$patch.cz" || true
		printf '\n%s did not apply cleanly. Merge the *.rej hunks by hand, delete the .rej files, then:\n' "${sha:0:7}" >&2
		printf '  git add -A && git commit -C %s\n' "$sha" >&2
		exit 1
	fi
	printf '| %s | %s | %s |\n' "${sha:0:7}" "$(git rev-parse --short HEAD)" "$(git log -1 --format=%s)" >> UPSTREAM.md
done
printf 'Ported. Record them: git commit -m "Record ported upstream commits" UPSTREAM.md\n'
