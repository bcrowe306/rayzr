#!/usr/bin/env bash
# Builds the Android runner: bin/runners/android/libmain.so (arm64-v8a,
# Android 7 / API 24 and up). The editor's Android export puts it in an APK
# / AAB next to the game (scripts/package_android.sh does the same from the
# command line) - exporting needs the SDK's build tools and Java, not the NDK.
#
#   scripts/build_android_runner.sh            (deps are built once into bin/android_deps)
#   scripts/build_android_runner.sh -define:RAYZR_RELEASE=1.2.3   (extra odin flags)
#
# Needs the Android NDK ($ANDROID_NDK_HOME, else the newest under
# $ANDROID_HOME/ndk) and odin. Dependencies built with the NDK's clang:
# raylib 5.5 (OpenGL ES 3, NativeActivity), Lua 5.4.7, Box2D 3.1.1,
# Clipper2 (scripts/build_clipper.sh --android) - the versions the web
# runner uses.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
DEPS="$ROOT/bin/android_deps"
BUILD="$ROOT/bin/android_build"
OUT="${OUT:-$ROOT/bin/runners/android}"
API=24

ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/opt/homebrew/share/android-commandlinetools}}"
NDK="${ANDROID_NDK_HOME:-}"
if [ -z "$NDK" ] && [ -d "$ANDROID_HOME/ndk" ]; then NDK="$ANDROID_HOME/ndk/$(ls "$ANDROID_HOME/ndk" | sort -V | tail -1)"; fi
[ -n "$NDK" ] && [ -d "$NDK" ] || { echo "No Android NDK: set ANDROID_NDK_HOME (or install one: sdkmanager \"ndk;27.3.13750724\")" >&2; exit 1; }
case "$(uname -s)" in Darwin) HOST=darwin-x86_64 ;; Linux) HOST=linux-x86_64 ;; *) HOST=windows-x86_64 ;; esac
TOOL="$NDK/toolchains/llvm/prebuilt/$HOST/bin"
CC="$TOOL/aarch64-linux-android$API-clang"
CXX="$TOOL/aarch64-linux-android$API-clang++"
AR="$TOOL/llvm-ar"
GLUE="$NDK/sources/android/native_app_glue"
mkdir -p "$DEPS" "$BUILD" "$OUT"

fetch() { # url dir
	[ -d "$DEPS/$2" ] && return
	echo "Downloading $1"
	curl -sL -o "$DEPS/$2.tgz" "$1"
	tar -xzf "$DEPS/$2.tgz" -C "$DEPS"
}
fetch https://github.com/raysan5/raylib/archive/refs/tags/5.5.tar.gz raylib-5.5
fetch https://www.lua.org/ftp/lua-5.4.7.tar.gz lua-5.4.7
fetch https://github.com/erincatto/box2d/archive/refs/tags/v3.1.1.tar.gz box2d-3.1.1

lib() { # out.a  cc  flags...  -- sources...
	local out=$1 cc=$2; shift 2
	local flags=() srcs=()
	while [ "$1" != "--" ]; do flags+=("$1"); shift; done; shift
	srcs=("$@")
	local objdir="$out.objs"; mkdir -p "$objdir"
	for s in "${srcs[@]}"; do "$cc" "${flags[@]}" -c "$s" -o "$objdir/$(basename "${s%.*}").o"; done
	"$AR" rcs "$out" "$objdir"/*.o
}
R="$DEPS/raylib-5.5/src"
if [ ! -f "$DEPS/libraylib.a" ]; then
	echo "Building raylib (android)"
	lib "$DEPS/libraylib.a" "$CC" -O2 -fPIC -DPLATFORM_ANDROID -DGRAPHICS_API_OPENGL_ES3 -I"$R" -I"$GLUE" -- \
		"$R/rcore.c" "$R/rshapes.c" "$R/rtextures.c" "$R/rtext.c" "$R/rmodels.c" "$R/utils.c" "$R/raudio.c" "$GLUE/android_native_app_glue.c"
fi
L="$DEPS/lua-5.4.7/src"
if [ ! -f "$DEPS/liblua.a" ]; then
	echo "Building Lua (android)"
	srcs=(); for f in "$L"/*.c; do case "$(basename "$f")" in lua.c|luac.c) ;; *) srcs+=("$f") ;; esac; done
	lib "$DEPS/liblua.a" "$CC" -O2 -fPIC -DLUA_USE_LINUX -- "${srcs[@]}"
fi
B="$DEPS/box2d-3.1.1"
if [ ! -f "$DEPS/libbox2d.a" ]; then
	echo "Building Box2D (android)"
	lib "$DEPS/libbox2d.a" "$CC" -O2 -fPIC -std=gnu17 -DNDEBUG -I"$B/include" -I"$B/src" -- "$B"/src/*.c
fi
if [ ! -f "$DEPS/clipper/libclipper.a" ]; then
	echo "Building Clipper2 (android)"
	ANDROID_CXX="$CXX" ANDROID_AR="$AR" scripts/build_clipper.sh --android > /dev/null
fi

echo "Compiling the engine (linux_arm64, android)"
"$CC" -O2 -fPIC -I"$GLUE" -c runner/android/android_glue.c -o "$BUILD/android_glue.o"
python3 scripts/android_prepare.py "$ROOT" "$BUILD/src" "$(odin root)" > /dev/null
ODIN_ANDROID_NDK="$NDK" odin build "$BUILD/src/runner/android" -target:linux_arm64 -subtarget:android -minimum-os-version:$API \
	-build-mode:obj -o:speed -out:"$BUILD/rayzr.o" "$@"

echo "Linking"
"$CXX" -shared -o "$OUT/libmain.so" "$BUILD"/rayzr*.o "$BUILD/android_glue.o" \
	"$DEPS/libraylib.a" "$DEPS/liblua.a" "$DEPS/libbox2d.a" "$DEPS/clipper/libclipper.a" \
	-u ANativeActivity_onCreate -static-libstdc++ \
	-llog -landroid -lEGL -lGLESv3 -lOpenSLES -lz -lm -ldl \
	-Wl,-z,max-page-size=16384 -Wl,--gc-sections
cp engine/Open_Sans/static/OpenSans-Regular.ttf "$OUT/" 2>/dev/null || true
echo "Android runner: $OUT"
ls -la "$OUT"
