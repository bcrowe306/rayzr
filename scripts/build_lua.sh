#!/usr/bin/env bash
# Builds Lua 5.4.7 as a static library for engine/lua54 (TODO D.3: no Lua
# shared library next to the editor or the runners):
#   macOS    engine/lua54/lib/liblua54_darwin.a      universal (arm64 + x86_64; in the repo)
#   Windows  engine/lua54/lib/lua54_windows_x64.lib  (MSVC, static CRT; CI builds it)
# Linux links Odin's vendor static library (vendor:lua/5.4/linux/liblua54.a).
#   scripts/build_lua.sh [--if-missing]
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=5.4.7
SHA256=9fbf5e28ef86c69858f6d3d34eccc32e911c1a28b4120ff3e84aaa70cfbf1e30
case "$(uname -s)" in
	Darwin) out=engine/lua54/lib/liblua54_darwin.a ;;
	MINGW*|MSYS*|CYGWIN*) out=engine/lua54/lib/lua54_windows_x64.lib ;;
	*) echo "Linux uses Odin's vendor static Lua: nothing to build"; exit 0 ;;
esac
if [ "${1:-}" = --if-missing ] && [ -f "$out" ]; then
	echo "$out exists"
	exit 0
fi
tmp=$(mktemp -d)
# lua.org, else its official mirror (CI's Windows runners sometimes can't
# reach lua.org); the same tarball either way, checked against SHA256.
got=
for url in "https://www.lua.org/ftp/lua-$VERSION.tar.gz" "https://www.tecgraf.puc-rio.br/lua/ftp/lua-$VERSION.tar.gz"; do
	if curl -fsSL --retry 2 --connect-timeout 15 -o "$tmp/lua.tar.gz" "$url"; then
		got=$url
		break
	fi
	echo "could not download $url" >&2
done
[ -n "$got" ] || { echo "Lua $VERSION: no download worked" >&2; exit 1; }
sum=$( (sha256sum "$tmp/lua.tar.gz" 2>/dev/null || shasum -a 256 "$tmp/lua.tar.gz") | cut -d' ' -f1)
[ "$sum" = "$SHA256" ] || { echo "Lua $VERSION from $got: checksum $sum, expected $SHA256" >&2; exit 1; }
tar -xzf "$tmp/lua.tar.gz" -C "$tmp"
src="$tmp/lua-$VERSION/src"
mkdir -p "$(dirname "$out")"
objs=()
for f in "$src"/*.c; do
	case "$(basename "$f")" in lua.c|luac.c) continue ;; esac
	objs+=("$f")
done
case "$(uname -s)" in
Darwin)
	mkdir -p "$tmp/o"
	for f in "${objs[@]}"; do
		clang -O2 -DLUA_USE_MACOSX -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 -c "$f" -o "$tmp/o/$(basename "${f%.c}").o"
	done
	rm -f "$out"
	libtool -static -o "$out" "$tmp"/o/*.o
	;;
*)
	# (MSVC's environment: ilammy/msvc-dev-cmd in CI, a Developer prompt locally.)
	mkdir -p "$tmp/o"
	(cd "$tmp/o" && for f in "${objs[@]}"; do cl -nologo -O2 -MT -c "$(cygpath -w "$f")" > /dev/null; done)
	lib -nologo "-OUT:$(cygpath -w "$out")" "$(cygpath -w "$tmp/o")"\\*.obj
	;;
esac
echo "Built $out (Lua $VERSION)"
