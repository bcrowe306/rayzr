#!/usr/bin/env bash
# Smoke-tests a packaged editor (scripts/package_editor.sh) the way a user
# runs it: from outside the source checkout, no RAYZR_GAME_BIN, hidden.
# tests/package/installed.drive plays (the bundled runner), exports and
# starts the bundled language server.
#   scripts/test_package.sh [dist]
set -uo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
dist="${1:-dist}"
case "$(uname -s)" in
	Darwin) editor=$(ls -d "$dist"/*.app 2>/dev/null | head -1)/Contents/MacOS/rayzr-editor ;;
	MINGW*|MSYS*|CYGWIN*) editor="$dist/rayzr-editor-windows/rayzr-editor.exe" ;;
	*) editor="$dist/rayzr-editor-linux/rayzr-editor" ;;
esac
[ -x "$editor" ] || { echo "no packaged editor in $dist (scripts/package_editor.sh)" >&2; exit 1; }
editor=$(cd "$(dirname "$editor")" && pwd)/$(basename "$editor")

# macOS: no binary may need a newer macOS than the app says it runs on
# (Info.plist LSMinimumSystemVersion; 0.6.0 said 12.0 and needed 14).
if [ "$(uname -s)" = Darwin ]; then
	app=$(dirname "$(dirname "$editor")")
	declared=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Info.plist")
	bad=0
	while IFS= read -r f; do
		minos=$(otool -l "$f" 2>/dev/null | awk '/LC_BUILD_VERSION/{b=1} b && $1=="minos"{print $2; exit}')
		[ -z "$minos" ] && continue
		if [ "$(printf '%s\n%s\n' "$minos" "$declared" | sort -V | tail -1)" != "$declared" ]; then
			echo "FAIL: ${f#$app/} needs macOS $minos; the app declares $declared" >&2
			bad=1
		fi
	done < <(find "$app/Contents" -type f \( -perm -u+x -o -name '*.dylib' \))
	[ $bad = 0 ] || exit 1
	echo "macOS minimum: every binary runs on $declared"
fi

tmp=$(mktemp -d /tmp/rayzr_package_test.XXXXXX)
cp -R assets/demo_project "$tmp/project"
rm -rf "$tmp/project/.rayzr" "$tmp/project"/scenes/new_scene*.scene.json
case "$(uname -s)" in Darwin) native=macos ;; Linux) native=linux ;; *) native=windows ;; esac
python3 -I - "$tmp/project/project.json" "$native" <<-'EOF'
	import json, sys
	p = sys.argv[1]
	cfg = json.load(open(p))
	# Export for this platform (CI's packages have this platform's runner only).
	cfg.setdefault("export", {})["targets"] = [sys.argv[2]]
	cfg["export"].pop("presets", None)
	cfg["scenes"] = [s for s in cfg.get("scenes", []) if not s.startswith("scenes/new_scene")]
	if cfg.get("initial_scene", "").startswith("scenes/new_scene"):
	    cfg["initial_scene"] = "scenes/main.scene.json"
	json.dump(cfg, open(p, "w"), indent=2)
EOF
if command -v caffeinate > /dev/null; then caffeinate -u -t 900 & trap 'kill $! 2> /dev/null' EXIT; fi
cd /tmp # (not the checkout: the editor must find everything in its own package)
# (The update check reads a fixture manifest with no packages, not downloads.rayzr.app:
# nothing is downloaded, the packaged editor is never replaced.)
env -u RAYZR_GAME_BIN -u RAYZR_EDITOR_RESOURCES RAYZR_UPDATE_URL="file://$repo/tests/package/manifest.json" perl -e 'alarm 600; exec @ARGV' "$editor" \
	--project "$tmp/project" --drive "$repo/tests/package/installed.drive" --shots "$tmp/shots" \
	--user-data "$tmp/userdata" --hidden > "$tmp/editor.log" 2>&1
status=$?
grep -E "\[DRIVE\] (FAIL|.*passed)" "$tmp/editor.log"
[ $status -eq 0 ] && echo "PASS  packaged editor ($editor)" || echo "FAIL  packaged editor (log: $tmp/editor.log)"
exit $status
