#!/usr/bin/env bash
# Refreshes engine/gamepad/gamecontrollerdb.txt (the controller database the
# engine ships: gamepad_mappings.odin) from SDL_GameControllerDB's latest
# commit. Prints "changed <sha>" or "unchanged <sha>".
#   scripts/update_gamepad_db.sh
# Needs curl. (.github/workflows/gamepad-db.yml runs it weekly.)
set -euo pipefail
cd "$(dirname "$0")/.."
repo="mdqinc/SDL_GameControllerDB"
out="engine/gamepad/gamecontrollerdb.txt"
sha="$(curl -fsSL "https://api.github.com/repos/$repo/commits/master" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["sha"])')"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
{
	echo "# SDL_GameControllerDB (zlib license) - https://github.com/$repo"
	echo "# commit $sha - refreshed by .github/workflows/gamepad-db.yml (scripts/update_gamepad_db.sh)"
	curl -fsSL "https://raw.githubusercontent.com/$repo/$sha/gamecontrollerdb.txt"
} > "$tmp"
lines="$(grep -c '^[0-9a-fA-F]\{32\},' "$tmp" || true)"
if [ "${lines:-0}" -lt 1000 ]; then
	echo "only $lines mappings in the download - not replacing $out" >&2
	exit 1
fi
# Only the mappings count as a change (not the commit line).
if [ -f "$out" ] && diff -q <(grep -v '^#' "$out") <(grep -v '^#' "$tmp") >/dev/null; then
	echo "unchanged $sha"
	exit 0
fi
cp "$tmp" "$out"
echo "changed $sha ($lines mappings)"
