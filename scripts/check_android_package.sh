#!/usr/bin/env bash
# Checks an exported Android app (tests: the export_android drive): the
# APK's signature, its package id, the runner and the game inside it, and
# (when given) the AAB next to it.
#   scripts/check_android_package.sh <app.apk> <package.id> [app.aab]
set -euo pipefail
apk="$1"; id="$2"; aab="${3:-}"
ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/opt/homebrew/share/android-commandlinetools}}"
BT="$ANDROID_HOME/build-tools/$(ls "$ANDROID_HOME/build-tools" | sort -V | tail -1)"
if [ -z "${JAVA_HOME:-}" ]; then
	for j in /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home "$(/usr/libexec/java_home -v 17+ 2>/dev/null || true)"; do
		[ -x "$j/bin/java" ] && { export JAVA_HOME="$j"; break; }
	done
fi
export PATH="${JAVA_HOME:+$JAVA_HOME/bin:}$PATH"
"$BT/apksigner" verify "$apk"
"$BT/aapt2" dump badging "$apk" | grep -q "package: name='$id'" || { echo "not $id" >&2; exit 1; }
list="$(unzip -l "$apk")"
for f in lib/arm64-v8a/libmain.so assets/game.rayzr assets/fonts/OpenSans-Regular.ttf; do
	grep -q "$f" <<< "$list" || { echo "no $f in $apk" >&2; exit 1; }
done
if [ -n "$aab" ]; then
	alist="$(unzip -l "$aab")"
	for f in base/manifest/AndroidManifest.xml base/lib/arm64-v8a/libmain.so base/assets/game.rayzr; do
		grep -q "$f" <<< "$alist" || { echo "no $f in $aab" >&2; exit 1; }
	done
fi
echo "ok: $apk${aab:+ and $aab}"
