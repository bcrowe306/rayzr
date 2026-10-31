#!/usr/bin/env bash
# Builds Clipper2 (polygon clipping, Boost license) with the engine's C
# interface (engine/clipper/rayzr_clipper.cpp) as a static library:
#   macOS    engine/clipper/lib/libclipper_darwin.a      universal (in the repo)
#   Linux    engine/clipper/lib/libclipper_linux_x64.a   (CI builds it)
#   Windows  engine/clipper/lib/clipper_windows_x64.lib  (MSVC, static CRT; CI)
#   --web    bin/web_deps/clipper/libclipper.a           (em++; build_web_runner.sh)
#   --android bin/android_deps/clipper/libclipper.a      (the NDK's clang++ in $ANDROID_CXX; build_android_runner.sh)
#   scripts/build_clipper.sh [--if-missing] [--web | --android]
# Needs git and a C++17 compiler (Windows: MSVC's environment).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=Clipper2_2.0.1
web=0; android=0; if_missing=0
for a in "$@"; do case "$a" in --web) web=1 ;; --android) android=1 ;; --if-missing) if_missing=1 ;; esac; done
if [ $web = 1 ]; then
	out=bin/web_deps/clipper/libclipper.a
elif [ $android = 1 ]; then
	out=bin/android_deps/clipper/libclipper.a
else
	case "$(uname -s)" in
		Darwin) out=engine/clipper/lib/libclipper_darwin.a ;;
		Linux) out=engine/clipper/lib/libclipper_linux_x64.a ;;
		MINGW*|MSYS*|CYGWIN*) out=engine/clipper/lib/clipper_windows_x64.lib ;;
		*) echo "Unknown platform $(uname -s)" >&2; exit 1 ;;
	esac
fi
if [ $if_missing = 1 ] && [ -f "$out" ]; then echo "$out exists"; exit 0; fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git -c advice.detachedHead=false clone -q --depth 1 --branch "$VERSION" https://github.com/AngusJohnson/Clipper2.git "$tmp/clipper2"
lib="$tmp/clipper2/CPP/Clipper2Lib"
srcs=("$lib/src/clipper.engine.cpp" "$lib/src/clipper.offset.cpp" "$lib/src/clipper.rectclip.cpp" engine/clipper/rayzr_clipper.cpp)
mkdir -p "$(dirname "$out")" "$tmp/obj"
if [ $android = 1 ]; then
	for s in "${srcs[@]}"; do "$ANDROID_CXX" -std=c++17 -O2 -DNDEBUG -fPIC -I"$lib/include" -c "$s" -o "$tmp/obj/$(basename "${s%.cpp}").o"; done
	"$ANDROID_AR" rcs "$out" "$tmp"/obj/*.o
elif [ $web = 1 ]; then
	for s in "${srcs[@]}"; do em++ -std=c++17 -O2 -DNDEBUG -I"$lib/include" -c "$s" -o "$tmp/obj/$(basename "${s%.cpp}").o"; done
	emar rcs "$out" "$tmp"/obj/*.o
else
	case "$(uname -s)" in
		Darwin)
			for s in "${srcs[@]}"; do c++ -std=c++17 -O2 -DNDEBUG -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 -I"$lib/include" -c "$s" -o "$tmp/obj/$(basename "${s%.cpp}").o"; done
			libtool -static -o "$out" "$tmp"/obj/*.o 2> /dev/null ;;
		Linux)
			for s in "${srcs[@]}"; do c++ -std=c++17 -O2 -DNDEBUG -fPIC -I"$lib/include" -c "$s" -o "$tmp/obj/$(basename "${s%.cpp}").o"; done
			ar rcs "$out" "$tmp"/obj/*.o ;;
		*)
			for s in "${srcs[@]}"; do cl -nologo -std:c++17 -O2 -MT -EHsc -DNDEBUG -I"$(cygpath -w "$lib/include")" -c "$(cygpath -w "$s")" -Fo"$(cygpath -w "$tmp/obj/$(basename "${s%.cpp}").obj")" > /dev/null; done
			lib -nologo -out:"$out" "$tmp"/obj/*.obj ;;
	esac
fi
echo "Built $out ($VERSION)"
