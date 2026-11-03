#!/usr/bin/env bash
# Puts LuaLS's prebuilt release for this platform into lua-language-server/
# (CI doesn't build the submodule: its release is the same version).
#   scripts/ci/fetch_luals.sh [version]
set -euo pipefail
cd "$(dirname "$0")/../.."
version="${1:-3.19.2}" # the lua-language-server submodule's version
case "$(uname -s)-$(uname -m)" in
	Darwin-arm64) asset="lua-language-server-$version-darwin-arm64.tar.gz" ;;
	Darwin-x86_64) asset="lua-language-server-$version-darwin-x64.tar.gz" ;;
	Linux-x86_64) asset="lua-language-server-$version-linux-x64.tar.gz" ;;
	Linux-aarch64) asset="lua-language-server-$version-linux-arm64.tar.gz" ;;
	MINGW*|MSYS*|CYGWIN*) asset="lua-language-server-$version-win32-x64.zip" ;;
	*) echo "No LuaLS release for $(uname -s) $(uname -m)" >&2; exit 1 ;;
esac
# The release assets' SHA-256 (GitHub's digests for 3.19.2; another version:
# none to check against, so it says so).
case "$asset" in
	lua-language-server-3.19.2-darwin-arm64.tar.gz) sha=79149584320a23bd5fcd5bc31f47a1975acd8a4560a0e89036bb1016fa61687f ;;
	lua-language-server-3.19.2-darwin-x64.tar.gz) sha=6f2174ece5ec63bcd9d5b22b2c902445c1cd9045fafe48c62602448ebf4c09cc ;;
	lua-language-server-3.19.2-linux-x64.tar.gz) sha=93ad326b10f6c00911dd8c450fa098332dbd8f9f45d1052f5636a2d54479b947 ;;
	lua-language-server-3.19.2-linux-arm64.tar.gz) sha=17b8e401a874440adeb649e5024c364f2bb9d15156c74a40e56d1ae9a1b2e4f2 ;;
	lua-language-server-3.19.2-win32-x64.zip) sha=4a3dc851b3b31e7b75a23f645d1ba4a2137579a55f5fa4edbb17a3e2a6254044 ;;
	*) sha="" ;;
esac
dst=lua-language-server
if [ -x "$dst/bin/lua-language-server" ] || [ -f "$dst/bin/lua-language-server.exe" ]; then
	echo "$dst is there"
	exit 0
fi
tmp=$(mktemp -d)
curl -fsSL --retry 3 -o "$tmp/$asset" "https://github.com/LuaLS/lua-language-server/releases/download/$version/$asset"
if [ -n "$sha" ]; then
	got=$( (sha256sum "$tmp/$asset" 2> /dev/null || shasum -a 256 "$tmp/$asset") | cut -d' ' -f1)
	[ "$got" = "$sha" ] || { echo "::error::$asset: SHA-256 $got, expected $sha" >&2; exit 1; }
else
	echo "::warning::no SHA-256 to check $asset against (add it to scripts/ci/fetch_luals.sh)" >&2
fi
mkdir -p "$dst"
case "$asset" in
	*.zip) unzip -q "$tmp/$asset" -d "$dst" ;;
	*) tar -xzf "$tmp/$asset" -C "$dst" ;;
esac
echo "LuaLS $version in $dst"
