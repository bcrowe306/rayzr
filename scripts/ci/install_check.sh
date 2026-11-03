#!/usr/bin/env bash
# Installs a release package the way a user would and checks it works
# (#330; .github/workflows/install-check.yml runs it on fresh machines):
#
#   scripts/ci/install_check.sh <package> [--work DIR] [--version V] [--gl-dlls DIR]
#
#   .dmg       mounted (quarantined first, as a browser download is), the
#              .app copied out, Gatekeeper's verdict noted, the quarantine
#              removed (what a user's right-click > Open does: unsigned
#              until 1.0, #289)
#   .zip       extracted (PowerShell's Expand-Archive, as Explorer does)
#   .deb       `apt-get install ./file.deb` (its dependencies from apt)
#   .AppImage  marked executable and run (--appimage-extract-and-run when
#              there's no FUSE, which is noted)
#   .tar.gz    untarred
#
# Then, with the INSTALLED editor only (this checkout gives the test drives
# and scripts, never a binary): what its binaries need from the machine
# (libraries, glibc, the Visual C++ runtime, macOS version), --version, the
# bundled runner plays the bundled demo; the editor makes a project from the
# Platformer template (tests/package/install_create.drive), Plays it and
# exports it to every target (install_play_export.drive): macOS, Linux,
# Windows, the web, and Android when the Android SDK and Java are there;
# then the exports run: this OS's game, the web game in headless Chrome
# (when there's Chrome and Node 22+), the APK checked (signed with the
# debug key).
#
# --gl-dlls DIR: DLLs copied next to every Windows exe that opens a window
# (CI: Mesa's llvmpipe, scripts/ci/mesa_windows.sh - the runner has no GPU).
# A machine without accelerated OpenGL (GitHub's macOS VMs) skips the steps
# that open a window, and says so.
# Prints PASS / FAIL / SKIP / NOTE per step and a summary (also to
# $GITHUB_STEP_SUMMARY); exits 1 when a step failed. Leaves logs and
# screenshots in the work folder (default: a new one in $TMPDIR).
set -uo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
pkg=""; work=""; want_version=""; gl_dlls=""
while [ $# -gt 0 ]; do
	case "$1" in
		--work) work="$2"; shift 2 ;;
		--version) want_version="$2"; shift 2 ;;
		--gl-dlls) gl_dlls="$2"; shift 2 ;;
		-*) echo "unknown option $1" >&2; exit 2 ;;
		*) pkg="$1"; shift ;;
	esac
done
[ -f "$pkg" ] || { echo "usage: $0 <package> [--work DIR] [--version V] [--gl-dlls DIR]" >&2; exit 2; }
pkg=$(cd "$(dirname "$pkg")" && pwd)/$(basename "$pkg")
[ -n "$work" ] || work=$(mktemp -d "${TMPDIR:-/tmp}/rayzr_install_check.XXXXXX")
mkdir -p "$work"
work=$(cd "$work" && pwd)
mkdir -p "$work/apps" "$work/home" "$work/userdata" "$work/shots" "$work/projects" "$work/logs"
results="$work/results.tsv"
: > "$results"

case "$(uname -s)" in
	Darwin) os=macos ;;
	Linux) os=linux ;;
	MINGW*|MSYS*|CYGWIN*) os=windows ;;
	*) echo "unknown OS $(uname -s)" >&2; exit 2 ;;
esac
py=python3
command -v python3 > /dev/null 2>&1 && python3 -c 'import sys' > /dev/null 2>&1 || py=python
command -v "$py" > /dev/null 2>&1 || py=""

# --- reporting ---------------------------------------------------------------
record() { # STATUS STEP [DETAIL]
	printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >> "$results"
	printf '[%s] %s%s\n' "$1" "$2" "${3:+ - $3}"
}
pass() { record PASS "$@"; }
fail() { record FAIL "$@"; }
skip() { record SKIP "$@"; }
note() { record NOTE "$@"; }
# limited SECONDS CMD...: the command, killed after SECONDS.
limited() {
	local s="$1"; shift
	if [ "$os" != windows ] && command -v timeout > /dev/null 2>&1; then timeout "$s" "$@"
	else perl -e 'alarm shift; exec @ARGV' "$s" "$@"; fi
}
# show_log LOG: its last lines, for a FAIL's detail.
show_log() { echo "---- $1 (last 40 lines)"; tail -40 "$1"; echo "----"; }
as_root() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi; }
native_path() { if [ "$os" = windows ]; then cygpath -w "$1"; else echo "$1"; fi; }

summary() {
	local verdict=PASS
	grep -q '^FAIL' "$results" && verdict=FAIL
	{
		echo
		echo "==== Install check: $(basename "$pkg") on $(uname -s) $(uname -m)${host:+ ($host)}"
		awk -F '\t' '{ printf "  %-5s %s%s\n", $1, $2, ($3 != "" ? " - " $3 : "") }' "$results"
		echo "==== $verdict  $(basename "$pkg")  (logs: $work)"
	}
	if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
		{
			echo "### $verdict: \`$(basename "$pkg")\` on $(uname -s)${host:+ ($host)}"
			echo
			echo "| | Step | Detail |"
			echo "|---|---|---|"
			awk -F '\t' '{ gsub(/\|/, "/", $3); printf "| %s | %s | %s |\n", $1, $2, $3 }' "$results"
			echo
		} >> "$GITHUB_STEP_SUMMARY"
	fi
	[ "$verdict" = PASS ]
}
trap 'summary; exit $?' EXIT

case "$os" in
	macos) host="macOS $(sw_vers -productVersion)" ;;
	linux) host="$(. /etc/os-release 2> /dev/null && echo "$PRETTY_NAME"), glibc $(getconf GNU_LIBC_VERSION 2> /dev/null | cut -d' ' -f2)" ;;
	windows) host=$(powershell -NoProfile -Command '[System.Environment]::OSVersion.VersionString' 2> /dev/null | tr -d '\r') ;;
esac

# --- 1. install ----------------------------------------------------------------
editor=""; res=""; app=""
install_dmg() {
	# As a browser saves it: quarantined (the files on the mounted image are too).
	cp "$pkg" "$work/download.dmg"
	xattr -w com.apple.quarantine "0081;$(printf %x "$(date +%s)");Safari;" "$work/download.dmg"
	mkdir -p "$work/mnt"
	hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$work/mnt" "$work/download.dmg" > "$work/logs/hdiutil.log" 2>&1 ||
		{ fail "install (.dmg)" "hdiutil attach failed"; show_log "$work/logs/hdiutil.log"; return 1; }
	local src
	src=$(ls -d "$work/mnt"/*.app 2> /dev/null | head -1)
	[ -n "$src" ] || { fail "install (.dmg)" "no .app on the disk image"; hdiutil detach -quiet "$work/mnt"; return 1; }
	ditto "$src" "$work/apps/$(basename "$src")" # (as Finder copies it: extended attributes kept)
	hdiutil detach -quiet "$work/mnt" || hdiutil detach -force -quiet "$work/mnt"
	app="$work/apps/$(basename "$src")"
	editor="$app/Contents/MacOS/rayzr-editor"
	res="$app/Contents/Resources"
	pass "install (.dmg)" "$(basename "$src") copied from the disk image"
	# Gatekeeper: what a user sees on first open.
	if xattr -p com.apple.quarantine "$editor" > /dev/null 2>&1 || xattr -p com.apple.quarantine "$app" > /dev/null 2>&1; then
		local verdict
		verdict=$(spctl --assess --type execute -vv "$app" 2>&1 | tr '\n' ' ')
		case "$verdict" in
			*accepted*) pass "Gatekeeper" "$verdict" ;;
			*) note "Gatekeeper" "rejects the quarantined app (unsigned until 1.0, #289): users right-click > Open; removed here with xattr -dr com.apple.quarantine. spctl: $verdict" ;;
		esac
		xattr -dr com.apple.quarantine "$app"
	else
		note "Gatekeeper" "the copied app isn't quarantined here (nothing to assess)"
	fi
}
install_zip() {
	powershell -NoProfile -Command "Expand-Archive -LiteralPath '$(cygpath -w "$pkg")' -DestinationPath '$(cygpath -w "$work/apps")' -Force" > "$work/logs/unzip.log" 2>&1 ||
		{ fail "install (.zip)" "Expand-Archive failed"; show_log "$work/logs/unzip.log"; return 1; }
	res="$work/apps/rayzr-editor-windows"
	editor="$res/rayzr-editor.exe"
	[ -f "$editor" ] || { fail "install (.zip)" "no rayzr-editor-windows/rayzr-editor.exe in the zip"; return 1; }
	pass "install (.zip)" "extracted"
}
install_deb() {
	export DEBIAN_FRONTEND=noninteractive
	as_root apt-get update -qq > "$work/logs/apt.log" 2>&1
	if as_root apt-get install -y --no-install-recommends "$pkg" >> "$work/logs/apt.log" 2>&1; then
		pass "install (.deb)" "apt-get install: $(grep -c '^Setting up' "$work/logs/apt.log") package(s) set up"
	else
		fail "install (.deb)" "apt-get install failed"; show_log "$work/logs/apt.log"; return 1
	fi
	# (Started by name, as a user types it: from PATH.)
	command -v rayzr-editor > /dev/null || { fail "install (.deb)" "no rayzr-editor on PATH"; return 1; }
	editor=rayzr-editor
	res=/opt/rayzr-editor
	[ -f /usr/share/applications/rayzr-editor.desktop ] && pass "desktop entry" "/usr/share/applications/rayzr-editor.desktop" ||
		fail "desktop entry" "missing"
}
install_appimage() {
	cp "$pkg" "$work/apps/"
	editor="$work/apps/$(basename "$pkg")"
	chmod +x "$editor"
	if limited 60 "$editor" --version > "$work/logs/appimage_probe.log" 2>&1; then
		pass "install (.AppImage)" "runs directly (FUSE available)"
	elif grep -qi fuse "$work/logs/appimage_probe.log"; then
		export APPIMAGE_EXTRACT_AND_RUN=1
		note "install (.AppImage)" "no FUSE here: run with --appimage-extract-and-run (APPIMAGE_EXTRACT_AND_RUN=1) - $(grep -i -m1 fuse "$work/logs/appimage_probe.log")"
	else
		fail "install (.AppImage)" "it doesn't start"; show_log "$work/logs/appimage_probe.log"; return 1
	fi
	# Its files, to check what's inside (the runs use the AppImage itself).
	(cd "$work/apps" && "$editor" --appimage-extract > /dev/null 2>&1)
	res="$work/apps/squashfs-root/usr/lib/rayzr-editor"
	[ -x "$res/rayzr-editor" ] || { fail "install (.AppImage)" "no usr/lib/rayzr-editor/rayzr-editor inside"; return 1; }
}
install_targz() {
	tar -xzf "$pkg" -C "$work/apps" || { fail "install (.tar.gz)" "tar failed"; return 1; }
	res="$work/apps/rayzr-editor-linux"
	editor="$res/rayzr-editor"
	[ -x "$editor" ] || { fail "install (.tar.gz)" "no rayzr-editor-linux/rayzr-editor (executable) in it"; return 1; }
	pass "install (.tar.gz)" "untarred"
}
case "$pkg" in
	*.dmg) install_dmg ;;
	*.zip) install_zip ;;
	*.deb) install_deb ;;
	*.AppImage) install_appimage ;;
	*.tar.gz) install_targz ;;
	*) fail "install" "unknown package type"; false ;;
esac || exit 1

case "$os" in
	macos) runner="$res/runners/macos/runner" ;;
	linux) runner="$res/runners/linux/runner" ;;
	windows) runner="$res/runners/windows/runner.exe" ;;
esac
for f in "$runner" "$res/fonts/OpenSans-Regular.ttf" "$res/templates/demo_project/project.json" "$res/templates/platformer/project.json"; do
	[ -s "$f" ] || fail "package contents" "missing ${f#$res/}"
done
for t in macos linux windows web android; do
	[ -d "$res/runners/$t" ] || note "package contents" "no runners/$t: the editor can't export to $t"
done

# --- 2. what the binaries need from this machine ---------------------------------
deps_ok=1
case "$os" in
macos)
	if codesign --verify --deep --strict "$app" > "$work/logs/codesign.log" 2>&1; then
		pass "signature" "$(codesign -dv "$app" 2>&1 | grep -E '^Signature|^Authority' | head -1 | tr '\n' ' ')"
	else
		fail "signature" "codesign --verify failed"; show_log "$work/logs/codesign.log"
	fi
	note "architectures" "editor: $(lipo -archs "$editor"); runner: $(lipo -archs "$runner")$(lipo -archs "$editor" | grep -q x86_64 || echo ' (no Intel editor)')"
	declared=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")
	bad=""
	libs_bad=""
	while IFS= read -r f; do
		file "$f" | grep -q Mach-O || continue
		minos=$(otool -l "$f" 2> /dev/null | awk '/LC_BUILD_VERSION/{b=1} b && $1=="minos"{print $2; exit}')
		if [ -n "$minos" ] && [ "$(printf '%s\n%s\n' "$minos" "$declared" | sort -V | tail -1)" != "$declared" ]; then
			bad="$bad ${f#$app/}($minos)"
		fi
		while IFS= read -r l; do
			case "$l" in
				/usr/lib/*|/System/*) ;;
				@rpath/*|@executable_path/*|@loader_path/*) [ -e "$app/Contents/Frameworks/$(basename "$l")" ] || [ -e "$(dirname "$f")/$(basename "$l")" ] || libs_bad="$libs_bad ${f#$app/}:$l" ;;
				*) libs_bad="$libs_bad ${f#$app/}:$l" ;;
			esac
		done < <(otool -L "$f" 2> /dev/null | awk 'NR > 1 {print $1}')
	done < <(find "$app/Contents" -type f \( -perm -u+x -o -name '*.dylib' \))
	[ -z "$bad" ] && pass "macOS version" "every binary runs on $declared (Info.plist); this Mac: $(sw_vers -productVersion)" ||
		{ fail "macOS version" "need a newer macOS than $declared:$bad"; deps_ok=0; }
	[ -z "$libs_bad" ] && pass "libraries" "only the system's and the bundle's" ||
		{ fail "libraries" "not on a fresh Mac:$libs_bad"; deps_ok=0; }
	;;
linux)
	bins=("$res/rayzr-editor" "$res/runners/linux/runner")
	[ -f "$res/runners/linux/runner-debug" ] && bins+=("$res/runners/linux/runner-debug")
	[ -f "$res/lua-language-server/bin/lua-language-server" ] && bins+=("$res/lua-language-server/bin/lua-language-server")
	if [ -n "$py" ]; then
		if "$py" -I "$repo/scripts/ci/binary_deps.py" --check "${bins[@]}" > "$work/logs/binary_deps.log" 2>&1; then
			pass "glibc and linked libraries" "$(sed -n 1p "$work/logs/binary_deps.log" | sed "s|$res/||")"
		else
			fail "glibc and linked libraries" "$(grep FAIL "$work/logs/binary_deps.log" | sed "s|$res/||" | tr '\n' ' ')"; deps_ok=0
		fi
	fi
	missing=$(for b in "${bins[@]}"; do ldd "$b" 2>&1 | grep 'not found' | awk '{print $1}'; done | sort -u | tr '\n' ' ')
	[ -z "$missing" ] && pass "ldd" "every linked library found" || { fail "ldd" "not found: $missing"; deps_ok=0; }
	# Loaded at run time (raylib's GLFW and miniaudio dlopen them).
	have_lib() { ldconfig -p 2> /dev/null | grep -q " $1 " || ls /usr/lib*/"$1" /usr/lib/*-linux-gnu/"$1" /lib/*-linux-gnu/"$1" > /dev/null 2>&1; }
	export PATH="$PATH:/sbin:/usr/sbin"
	for l in libGL.so.1 libX11.so.6; do have_lib "$l" || { fail "runtime libraries" "no $l: no window (OpenGL / X11)"; deps_ok=0; }; done
	opt=""
	for l in libasound.so.2 libXrandr.so.2 libXcursor.so.1 libXi.so.6 libXinerama.so.1; do have_lib "$l" || opt="$opt $l"; done
	[ -z "$opt" ] && pass "runtime libraries" "OpenGL, X11, ALSA, Xrandr, Xcursor, Xi, Xinerama" ||
		note "runtime libraries" "missing (optional: sound / cursors / monitors / raw mouse):$opt"
	;;
windows)
	bins=("$editor" "$res"/runners/windows/*.exe)
	[ -f "$res/lua-language-server/bin/lua-language-server.exe" ] && bins+=("$res/lua-language-server/bin/lua-language-server.exe")
	if "$py" -I "$repo/scripts/ci/binary_deps.py" --check "${bins[@]}" > "$work/logs/binary_deps.log" 2>&1; then
		pass "DLLs" "only Windows' own (no Visual C++ runtime needed)"
	else
		fail "DLLs" "$(grep FAIL "$work/logs/binary_deps.log" | sed 's|.*/||' | sort -u | tr '\n' ' ')"; deps_ok=0
	fi
	;;
esac

# --- 3. it runs -------------------------------------------------------------------
v=$(limited 60 "$editor" --version 2> "$work/logs/version.err" | tr -d '\r' | tail -1)
if [ -n "$want_version" ] && [ "$v" != "$want_version" ]; then
	if [ -z "$v" ] && [ "$os" = windows ]; then note "--version" "no output (a GUI exe's stdout)"
	else fail "--version" "printed '$v', expected '$want_version'"; fi
elif [ -n "$v" ]; then pass "--version" "$v"
else fail "--version" "nothing printed"; cat "$work/logs/version.err"; fi

if [ -n "$gl_dlls" ] && [ "$os" = windows ]; then
	cp "$gl_dlls"/*.dll "$res/" && cp "$gl_dlls"/*.dll "$res/runners/windows/"
	note "OpenGL" "$(ls "$gl_dlls"/*.dll | wc -l | tr -d ' ') DLLs from $gl_dlls next to the exes (this machine has no GPU driver)"
fi

demo="$work/projects/Demo_Project"
cp -R "$res/templates/demo_project" "$demo"
rm -rf "$work/projects/Demo_Project/.rayzr"
chmod -R u+w "$demo"
nogl=0
limited 180 "$runner" "$(native_path "$demo")" --frames 10 --hidden --user-data "$(native_path "$work/userdata/probe")" \
	--dump-scene "$(native_path "$work/shots/probe.json")" > "$work/logs/runner_probe.log" 2>&1
code=$?
if [ $code = 0 ] && grep -q '"root"' "$work/shots/probe.json" 2> /dev/null; then
	pass "bundled runner" "plays the bundled demo project"
elif [ $code = 1 ] && grep -q "Could not open the game window" "$work/logs/runner_probe.log"; then
	nogl=1
	skip "bundled runner" "no OpenGL 3.3 window on this machine ($(grep -o 'Could not open the game window.*' "$work/logs/runner_probe.log" | head -1)); the steps that open a window are skipped"
else
	fail "bundled runner" "exit $code"; show_log "$work/logs/runner_probe.log"
fi

if [ $nogl = 1 ]; then
	for s in "new project (Platformer template)" "Play" "export" "run the exports"; do skip "$s" "needs an OpenGL window"; done
	exit
fi

# --- 4. a project from a template, Play, export ------------------------------------
# (Outside the checkout, with a fresh home folder: the Android debug key and
# anything else per-user lands in the work folder.)
editor_run() { # NAME DRIVE PROJECT
	(cd "$work" && limited 900 env -u RAYZR_GAME_BIN -u RAYZR_EDITOR_RESOURCES HOME="$work/home" "$editor" --project "$(native_path "$3")" --drive "$(native_path "$repo/tests/package/$2")" \
		--shots "$(native_path "$work/shots/$1")" --user-data "$(native_path "$work/userdata/editor")" --hidden) > "$work/logs/editor_$1.log" 2>&1
}
editor_run create install_create.drive "$demo"
code=$?
proj="$work/projects/Install_Check"
if [ $code = 0 ] && [ -f "$proj/project.json" ]; then
	pass "new project (Platformer template)" "Help > Welcome > Create: $proj"
else
	fail "new project (Platformer template)" "editor exit $code"
	grep -E '\[DRIVE\] FAIL|Error' "$work/logs/editor_create.log" | head -10
	show_log "$work/logs/editor_create.log"
	exit 1
fi

# The targets: every desktop one and the web; Android when this machine can
# package it (the SDK's build tools 34 + android-34, Java 17+).
targets="macos linux windows web"
posix_path() { if [ "$os" = windows ] && [ -n "$1" ]; then cygpath -u "$1"; else echo "$1"; fi; }
sdk=$(posix_path "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}")
[ -z "$sdk" ] && [ -d /opt/homebrew/share/android-commandlinetools ] && sdk=/opt/homebrew/share/android-commandlinetools
[ -n "${JAVA_HOME:-}" ] && JAVA_HOME=$(posix_path "$JAVA_HOME")
java="${JAVA_HOME:+$JAVA_HOME/bin/}java"
[ -n "${JAVA_HOME:-}" ] || [ ! -x /opt/homebrew/opt/openjdk@21/bin/java ] || java=/opt/homebrew/opt/openjdk@21/bin/java
java_major=$("$java" -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+).*/\1/')
if [ ! -d "$res/runners/android" ]; then
	skip "Android export" "no Android runner in this package"
elif [ -n "$sdk" ] && ls -d "$sdk"/build-tools/34* > /dev/null 2>&1 && [ -d "$sdk/platforms/android-34" ] && [ "${java_major:-0}" -ge 17 ] 2> /dev/null; then
	targets="$targets android"
	[ -n "${JAVA_HOME:-}" ] || JAVA_HOME="$(dirname "$(dirname "$java")")"
	# (The editor reads these: Windows paths on Windows.)
	export ANDROID_HOME="$(native_path "$sdk")" JAVA_HOME="$(native_path "$JAVA_HOME")"
else
	skip "Android export" "no Android SDK (build-tools 34, android-34) and Java 17+ here (ANDROID_HOME='$sdk', java $java_major)"
fi
"${py:-python3}" -I - "$(native_path "$proj/project.json")" $targets <<-'EOF'
	import json, sys
	p, targets = sys.argv[1], sys.argv[2:]
	cfg = json.load(open(p))
	x = cfg.setdefault("export", {})
	x.update({"executable": "InstallCheck", "bundle_id": "com.rayzr.installcheck", "android_package": "com.rayzr.installcheck"})
	x["presets"] = [{"name": t, "target": t} for t in targets]
	json.dump(cfg, open(p, "w"), indent=1)
EOF

editor_run play install_play_export.drive "$proj"
code=$?
log="$work/logs/editor_play.log"
if grep -q '"TileMapNode"' "$work/shots/play/played.json" 2> /dev/null; then
	pass "Play" "the bundled runner played the project"
else
	fail "Play" "$(grep -m1 '\[DRIVE\] FAIL' "$log")"
fi
out="${proj}_standalone"
# (The editor's console isn't on stdout: each target is checked by what it wrote.)
for t in $targets; do
	case "$t" in
		macos) f="$out/macos/InstallCheck.app/Contents/MacOS/InstallCheck" ;;
		linux) f="$out/linux/InstallCheck" ;;
		windows) f="$out/windows/InstallCheck.exe" ;;
		web) f="$out/web/game.rayzr" ;;
		android) f=$(ls "$out"/android/*.apk 2> /dev/null | head -1); f="${f:-$out/android/installcheck.apk}" ;;
	esac
	if [ -s "$f" ]; then pass "export: $t" "${f#$work/}"
	elif [ ! -d "$res/runners/$t" ]; then skip "export: $t" "no runners/$t in this package"
	else fail "export: $t" "no ${f#$work/} (the drive's screenshots: shots/play/)"; fi
done
[ -n "$(ls "$out"/android/*.apk 2> /dev/null)" ] && [ -z "$(ls "$out"/android/*.aab 2> /dev/null)" ] &&
	note "export: android" "APK only, no AAB (Google Play): the editor couldn't download bundletool (its log says why)"
if [ $code != 0 ]; then
	fail "editor drive (Play + export)" "exit $code: $(grep '\[DRIVE\] FAIL' "$log" | head -3 | tr '\n' ' ')"
	show_log "$log"
fi

# --- 5. the exports run -------------------------------------------------------------
check_dump() { grep -q '"TileMapNode"' "$1" 2> /dev/null; }
run_game() { # NAME EXE (a game: plays 60 frames, dumps its scene)
	limited 180 "$2" --frames 60 --hidden --user-data "$(native_path "$work/userdata/$1")" \
		--dump-scene "$(native_path "$work/shots/$1.json")" > "$work/logs/game_$1.log" 2>&1
	local c=$?
	if [ $c = 0 ] && check_dump "$work/shots/$1.json"; then pass "run: $1" "plays (60 frames, the title scene)"
	else fail "run: $1" "exit $c"; show_log "$work/logs/game_$1.log"; fi
}
case "$os" in
macos)
	game="$out/macos/InstallCheck.app"
	if [ -d "$game" ]; then
		codesign --verify --deep --strict "$game" > /dev/null 2>&1 && pass "exported app signature" "$(codesign -dv "$game" 2>&1 | grep -m1 '^Signature' )" ||
			fail "exported app signature" "codesign --verify failed"
		run_game macos "$game/Contents/MacOS/InstallCheck"
	fi
	;;
linux)
	[ -x "$out/linux/InstallCheck" ] && run_game linux "$out/linux/InstallCheck"
	[ -x "$out/linux/InstallCheck.AppDir/AppRun" ] && run_game linux-appdir "$out/linux/InstallCheck.AppDir/AppRun"
	[ -n "$py" ] && [ -f "$out/linux/InstallCheck" ] && { "$py" -I "$repo/scripts/ci/binary_deps.py" --check "$out/linux/InstallCheck" > "$work/logs/game_deps.log" 2>&1 &&
		pass "exported game's libraries" "$(sed 's|.*: ||' "$work/logs/game_deps.log" | head -1)" || fail "exported game's libraries" "$(grep FAIL "$work/logs/game_deps.log")"; }
	;;
windows)
	if [ -f "$out/windows/InstallCheck.exe" ]; then
		"$py" -I "$repo/scripts/ci/binary_deps.py" --check "$out/windows/InstallCheck.exe" > "$work/logs/game_deps.log" 2>&1 &&
			pass "exported game's DLLs" "only Windows' own" || fail "exported game's DLLs" "$(grep FAIL "$work/logs/game_deps.log" | sed 's|.*/||' | tr '\n' ' ')"
		[ -n "$gl_dlls" ] && cp "$gl_dlls"/*.dll "$out/windows/"
		run_game windows "$out/windows/InstallCheck.exe"
	fi
	;;
esac

# The web export in headless Chrome (scripts/web/run_test.mjs: the page's ?test mode).
chrome="${CHROME:-}"
if [ -z "$chrome" ]; then
	for c in google-chrome google-chrome-stable chromium chromium-browser "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
		"/c/Program Files/Google/Chrome/Application/chrome.exe" "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe"; do
		if command -v "$c" > /dev/null 2>&1 || [ -x "$c" ]; then chrome=$(command -v "$c" 2> /dev/null || echo "$c"); break; fi
	done
fi
node_major=$(node -v 2> /dev/null | sed -E 's/^v([0-9]+).*/\1/')
if [ ! -f "$out/web/index.html" ]; then
	skip "run: web" "no web export"
elif [ -z "$chrome" ] || [ "${node_major:-0}" -lt 22 ] 2> /dev/null || [ -z "$py" ]; then
	skip "run: web" "needs Chrome and Node 22+ (chrome='$chrome', node ${node_major:-none})"
else
	(cd "$out/web" && exec "$py" -u -m http.server 0 --bind 127.0.0.1) > "$work/logs/web_server.log" 2>&1 &
	server=$!
	port=""
	for _ in $(seq 50); do
		port=$(grep -o 'port [0-9]*' "$work/logs/web_server.log" 2> /dev/null | head -1 | cut -d' ' -f2)
		[ -n "$port" ] && break
		perl -e 'select(undef, undef, undef, 0.2)'
	done
	cat > "$work/web_spec.json" <<-EOF
		{"url": "http://127.0.0.1:$port/index.html?test", "timeout": 120,
		 "runs": [{"args": ["--frames", "60", "--dump-scene", "/test/dump.json"], "dump": "/test/dump.json"}]}
	EOF
	CHROME="$(native_path "$chrome")" limited 300 node "$(native_path "$repo/scripts/web/run_test.mjs")" "$(native_path "$work/web_spec.json")" "$(native_path "$work/web_result.json")" > "$work/logs/web.log" 2>&1
	kill "$server" 2> /dev/null
	cat > "$work/web_verdict.py" <<-'EOF'
		import json, sys
		try:
		    r = json.load(open(sys.argv[1]))
		except Exception as e:
		    print(f"FAIL no result ({e})"); sys.exit()
		run = (r.get("runs") or [{}])[0]
		if r.get("error"):
		    print("FAIL", r["error"])
		elif not run.get("ended"):
		    print("FAIL the game didn't end:", " | ".join(run.get("log", [])[-5:]))
		elif '"TileMapNode"' not in (run.get("dump") or ""):
		    print("FAIL no scene dump")
		else:
		    print("PASS plays in headless Chrome (60 frames, the title scene)")
	EOF
	verdict=$("$py" -I "$(native_path "$work/web_verdict.py")" "$(native_path "$work/web_result.json")")
	case "$verdict" in PASS*) pass "run: web" "${verdict#PASS }" ;; *) fail "run: web" "${verdict#FAIL }"; tail -20 "$work/logs/web.log" ;; esac
fi

# The APK: signed with the debug key, the project's package id, the runner and the game inside.
apk=$(ls "$out"/android/*.apk 2> /dev/null | head -1)
if [ -n "$apk" ]; then
	bt="$sdk/build-tools/$(ls "$sdk/build-tools" | sort -V | tail -1)"
	apksigner="$bt/apksigner"; [ -f "$apksigner.bat" ] && apksigner="$apksigner.bat"
	aapt2="$bt/aapt2"; [ -f "$aapt2.exe" ] && aapt2="$aapt2.exe"
	export PATH="$(dirname "$java"):$PATH"
	certs=$("$apksigner" verify --print-certs "$(native_path "$apk")" 2>&1)
	if [ $? = 0 ] && grep -q "CN=Android Debug" <<< "$certs"; then pass "APK signature" "verified, the debug key (CN=Android Debug)"
	else fail "APK signature" "$(echo "$certs" | head -3 | tr '\n' ' ')"; fi
	"$aapt2" dump badging "$(native_path "$apk")" 2> /dev/null | grep -q "package: name='com.rayzr.installcheck'" &&
		pass "APK package" "com.rayzr.installcheck" || fail "APK package" "not com.rayzr.installcheck"
	missing=$("$py" -I -c 'import sys, zipfile; n = set(zipfile.ZipFile(sys.argv[1]).namelist()); print(" ".join(f for f in sys.argv[2:] if f not in n))' \
		"$(native_path "$apk")" lib/arm64-v8a/libmain.so assets/game.rayzr assets/fonts/OpenSans-Regular.ttf)
	[ -z "$missing" ] && pass "APK contents" "the runner, the game, the font" || fail "APK contents" "missing $missing"
fi
