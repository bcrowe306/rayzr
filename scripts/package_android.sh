#!/usr/bin/env bash
# Packages a project as an Android app: an APK (install it: adb install)
# and an AAB (Google Play), arm64, Android 7+ - what the editor's Android
# export makes, from the command line (tests, CI):
#
#   scripts/package_android.sh <project-dir> <out-dir> [--name N] [--id com.x.y]
#        [--version 1.0] [--code 1] [--no-aab]
#
# Signed with the debug key (~/.android/debug.keystore, made when missing)
# unless RAYZR_ANDROID_KEYSTORE is set (with RAYZR_ANDROID_KEY_ALIAS and
# RAYZR_ANDROID_KEYSTORE_PASSWORD - passwords only from the environment).
#
# Needs bin/runners/android/libmain.so (scripts/build_android_runner.sh), the
# SDK's build-tools and platform (34), and Java 17+ (the AAB: bundletool,
# fetched once into bin/android_tools).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
proj="$1"; out="$2"; shift 2
name=""; id=""; version="1.0"; code=1; aab=1
while [ $# -gt 0 ]; do case "$1" in
	--name) name="$2"; shift 2 ;; --id) id="$2"; shift 2 ;; --version) version="$2"; shift 2 ;;
	--code) code="$2"; shift 2 ;; --no-aab) aab=0; shift ;; *) echo "unknown option $1" >&2; exit 2 ;;
esac; done

ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/opt/homebrew/share/android-commandlinetools}}"
BT="$ANDROID_HOME/build-tools/$(ls "$ANDROID_HOME/build-tools" | sort -V | tail -1)"
JAR="$ANDROID_HOME/platforms/android-34/android.jar"
[ -f "$JAR" ] || { echo "No Android platform 34: sdkmanager \"platforms;android-34\"" >&2; exit 1; }
if [ -z "${JAVA_HOME:-}" ] || ! "$JAVA_HOME/bin/java" -version 2>&1 | grep -q -E 'version "(1[7-9]|[2-9][0-9])'; then
	for j in "$(brew --prefix openjdk@21 2>/dev/null)/libexec/openjdk.jdk/Contents/Home" "$(/usr/libexec/java_home -v 17+ 2>/dev/null)"; do
		[ -x "$j/bin/java" ] && { JAVA_HOME="$j"; break; }
	done
fi
export JAVA_HOME PATH="$JAVA_HOME/bin:$PATH"
SO="$ROOT/bin/runners/android/libmain.so"
[ -f "$SO" ] || { echo "No Android runner: scripts/build_android_runner.sh" >&2; exit 1; }

cfgval() { python3 -I -c "import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], ''))" "$proj/project.json" "$1"; }
[ -n "$name" ] || name="$(cfgval name)"
[ -n "$name" ] || name="Game"
slug="$(echo "$name" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9')"
[ -n "$id" ] || id="com.rayzr.${slug:-game}"
landscape="$(python3 -I -c "import json,sys; w=json.load(open(sys.argv[1])).get('window', {}); print(1 if w.get('width', 1280) >= w.get('height', 720) else 0)" "$proj/project.json")"
orient="sensorLandscape"; [ "$landscape" = 1 ] || orient="sensorPortrait"

stage="$(mktemp -d /tmp/rayzr_android.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/assets/fonts" "$stage/res/mipmap" "$stage/lib/arm64-v8a" "$out"
odin run scripts/pack_rayzr.odin -file -- "$proj" "$stage/assets/game.rayzr" > /dev/null
cp engine/Open_Sans/static/OpenSans-Regular.ttf "$stage/assets/fonts/"
cp "$SO" "$stage/lib/arm64-v8a/libmain.so"
icon="$(cfgval icon)"
if [ -n "$icon" ] && [ -f "$proj/$icon" ]; then cp "$proj/$icon" "$stage/res/mipmap/icon.png"; else cp editor/assets/icon.png "$stage/res/mipmap/icon.png"; fi
esc() { python3 -I -c "import sys, html; print(html.escape(sys.argv[1]))" "$1"; }
cat > "$stage/AndroidManifest.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="$id"
    android:versionCode="$code" android:versionName="$(esc "$version")">
    <uses-feature android:glEsVersion="0x00030000" android:required="true"/>
    <application android:label="$(esc "$name")" android:icon="@mipmap/icon" android:hasCode="false"
        android:allowBackup="true" android:appCategory="game">
        <activity android:name="android.app.NativeActivity" android:exported="true"
            android:screenOrientation="$orient" android:launchMode="singleTask"
            android:configChanges="orientation|keyboardHidden|screenSize|screenLayout|keyboard|navigation|uiMode"
            android:theme="@android:style/Theme.NoTitleBar.Fullscreen">
            <meta-data android:name="android.app.lib_name" android:value="main"/>
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
XML
"$BT/aapt2" compile -o "$stage/res.zip" --dir "$stage/res"
link() { "$BT/aapt2" link -o "$1" -I "$JAR" --manifest "$stage/AndroidManifest.xml" --min-sdk-version 24 --target-sdk-version 34 -A "$stage/assets" "$stage/res.zip" "${@:2}"; }

# Signing: the given keystore, else the debug one.
ks="${RAYZR_ANDROID_KEYSTORE:-}"; alias="${RAYZR_ANDROID_KEY_ALIAS:-}"; pass="${RAYZR_ANDROID_KEYSTORE_PASSWORD:-}"
if [ -z "$ks" ]; then
	ks="$HOME/.android/debug.keystore"; alias="androiddebugkey"; pass="android"
	if [ ! -f "$ks" ]; then
		mkdir -p "$HOME/.android"
		keytool -genkeypair -keystore "$ks" -storepass android -keypass android -alias androiddebugkey \
			-dname "CN=Android Debug,O=Android,C=US" -keyalg RSA -keysize 2048 -validity 10000 > /dev/null 2>&1
	fi
fi
[ -n "$alias" ] || { echo "Set RAYZR_ANDROID_KEY_ALIAS for $ks" >&2; exit 1; }

# The APK.
link "$stage/base.apk"
(cd "$stage" && zip -q -r base.apk lib)
"$BT/zipalign" -f -p 4 "$stage/base.apk" "$stage/aligned.apk"
apk="$out/$slug.apk"
RAYZR_KS_PASS="$pass" "$BT/apksigner" sign --ks "$ks" --ks-key-alias "$alias" --ks-pass env:RAYZR_KS_PASS --key-pass env:RAYZR_KS_PASS --out "$apk" "$stage/aligned.apk"
echo "APK: $apk"

# The AAB: the same, resources in protobuf form, laid out as a bundle module.
if [ $aab = 1 ]; then
	BTOOL="$ROOT/bin/android_tools/bundletool-all-1.17.2.jar"
	if [ ! -f "$BTOOL" ]; then
		mkdir -p "$(dirname "$BTOOL")"
		echo "Downloading bundletool 1.17.2"
		curl -sL -o "$BTOOL" https://github.com/google/bundletool/releases/download/1.17.2/bundletool-all-1.17.2.jar
	fi
	link "$stage/proto.apk" --proto-format
	mkdir -p "$stage/module/manifest"
	(cd "$stage/module" && unzip -q ../proto.apk && mv AndroidManifest.xml manifest/ && cp -R ../lib ./lib && zip -q -r ../base.zip .)
	aabfile="$out/$slug.aab"
	rm -f "$aabfile"
	java -jar "$BTOOL" build-bundle --modules="$stage/base.zip" --output="$aabfile"
	jarsigner -keystore "$ks" -storepass "$pass" "$aabfile" "$alias" > /dev/null
	echo "AAB: $aabfile"
fi
