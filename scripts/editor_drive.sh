#!/usr/bin/env bash
# Runs editor test-drives: each tests/drive/<name>.drive operates the editor
# through injected mouse/keyboard input against a fresh copy of the demo
# project (the real project is never modified).
#   scripts/editor_drive.sh                 # all drives
#   scripts/editor_drive.sh playtest nodes  # selected drives
# Screenshots + a report per drive: editor_screenshots/drive/<name>/index.md
#
# Drives run in the background: hidden windows that never take the focus
# (the editor's and the game's --hidden), JOBS at a time (default: half the
# performance cores, at least 2). Drives marked "# drive: serial" (they touch
# bin/runners or other shared files) run one at a time after the others.
#   JOBS=1 scripts/editor_drive.sh          # one at a time
#   VISIBLE=1 scripts/editor_drive.sh nodes # watch it (a visible window)
# macOS: the display must be awake (raylib's InitWindow fails on a sleeping
# one); caffeinate keeps it awake while drives run.
set -uo pipefail
cd "$(dirname "$0")/.."

# --- one drive (run by the parallel scheduler below) ------------------------
if [ "${1:-}" = --one ]; then
	d="$2"
	name="$(basename "$d" .drive)"
	tmp="$(mktemp -d /tmp/rayzr_drive_${name}.XXXXXX)"
	cp -R assets/demo_project "$tmp/project"
	# Scratch "new_scene*" scenes made while using the editor on the demo
	# project would shift the drives' expected default names: drop them
	# from the copy (the demo project itself is untouched).
	rm -f "$tmp/project"/scenes/new_scene*.scene.json
	python3 -I - "$tmp/project/project.json" <<-'EOF'
		import json, sys
		p = sys.argv[1]
		cfg = json.load(open(p))
		cfg["scenes"] = [s for s in cfg.get("scenes", []) if not s.startswith("scenes/new_scene")]
		if cfg.get("initial_scene", "").startswith("scenes/new_scene"):
		    cfg["initial_scene"] = "scenes/main.scene.json"
		# Settings drives toggle start from their defaults, whatever the demo
		# project has now.
		cfg.setdefault("physics", {})["debug_draw"] = True
		json.dump(cfg, open(p, "w"), indent=2)
	EOF
	# "# drive: copy <src> <dst>": fixture files into the scratch project.
	grep '^# drive: copy ' "$d" | while read -r _ _ _ src dst; do
		mkdir -p "$tmp/project/$dst" && cp -R "$src/." "$tmp/project/$dst/"
	done
	shots="editor_screenshots/drive/$name"
	rm -rf "$shots"
	hidden=--hidden
	[ -n "${VISIBLE:-}" ] && hidden=
	start=$(date +%s)
	editor="$EDITOR_BIN"
	case "$editor" in /*) ;; *) editor="./$editor" ;; esac
	# A pass needs the drive's own summary with 0 failures (an editor that
	# didn't start, or crashed, is a failure; perl's exec dies if it can't run).
	if perl -e 'alarm 600; exec @ARGV or die "cannot run $ARGV[0]: $!\n"' "$editor" --project "$tmp/project" --drive "$d" --shots "$shots" --no-build --user-data "$tmp/userdata" $hidden > "$tmp/editor.log" 2>&1 &&
		grep -q "^\[DRIVE\] $name.drive: [0-9]* passed, 0 failed" "$tmp/editor.log"; then
		cp "$tmp/editor.log" "$shots/editor.log" 2>/dev/null # kept (memory reports, ...)
		line="PASS  $name"
		pass=1
	else
		line="FAIL  $name   (log: $tmp/editor.log)"
	fi
	{
		echo "$line"
		grep "\[DRIVE\] FAIL" "$tmp/editor.log" | sed 's/^/      /'
	} > "$RESULTS/$name"
	printf '%s  (%ds)\n' "$line" $(( $(date +%s) - start ))
	# A passing drive's scratch project goes (about 7 MB each; a full run
	# makes ~170). A failing one stays for its log.
	[ -n "${pass:-}" ] && rm -rf "$tmp"
	exit 0
fi

# --- build --------------------------------------------------------------------
mkdir -p bin
# The Odin compiler very occasionally stalls; time out and retry.
build() {
	for attempt in 1 2 3; do
		perl -e 'alarm 90; exec @ARGV' odin build "$@" && return 0
		echo "odin build $* failed or stalled (attempt $attempt), retrying..." >&2
		pkill -f "odin build $1" 2>/dev/null
	done
	return 1
}
# EDITOR_DEFINES: extra build flags (e.g. -define:RAYZR_MEM_TRACK=true for leak reports).
# EDITOR_BIN: where to build the editor (a second run can use its own binary).
export EDITOR_BIN="${EDITOR_BIN:-bin/editor}"
build editor -out:"$EDITOR_BIN" ${EDITOR_DEFINES:-} || exit 1
# GAME_BIN: where to build the game Play runs (passed to the editor as
# RAYZR_GAME_BIN); SKIP_GAME_BUILD=1 keeps the existing one.
GAME_BIN="${GAME_BIN:-bin/rayzr}"
export RAYZR_GAME_BIN="$GAME_BIN"
[ -n "${SKIP_GAME_BUILD:-}" ] || build . -out:"$GAME_BIN" || exit 1

if [ $# -gt 0 ]; then
	drives=()
	for n in "$@"; do drives+=("tests/drive/$n.drive"); done
else
	drives=(tests/drive/*.drive)
fi

# --- run ----------------------------------------------------------------------
if [ -z "${JOBS:-}" ]; then
	perf=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || nproc 2>/dev/null || echo 4)
	JOBS=$(( perf / 2 > 2 ? perf / 2 : 2 ))
fi
[ -n "${VISIBLE:-}" ] && JOBS=1 # (visible windows would fight over the focus)
export RESULTS="$(mktemp -d /tmp/rayzr_drive_results.XXXXXX)"
export VISIBLE="${VISIBLE:-}"
if command -v caffeinate > /dev/null; then caffeinate -u -t 7200 & trap 'kill $! 2> /dev/null' EXIT; fi

parallel=()
serial=()
for d in "${drives[@]}"; do
	if grep -q '^# drive: serial' "$d"; then serial+=("$d"); else parallel+=("$d"); fi
done
started=$(date +%s)
echo "${#drives[@]} drives: ${#parallel[@]} in parallel ($JOBS at a time), ${#serial[@]} serial"
[ ${#parallel[@]} -gt 0 ] && printf '%s\n' "${parallel[@]}" | xargs -P "$JOBS" -I{} "$0" --one {}
for d in ${serial[@]+"${serial[@]}"}; do "$0" --one "$d"; done

# --- summary (in the drives' order) -------------------------------------------
fail=0
echo
for d in "${drives[@]}"; do
	r="$RESULTS/$(basename "$d" .drive)"
	if [ -f "$r" ]; then
		cat "$r"
		grep -q '^FAIL' "$r" && fail=1
	else
		echo "FAIL  $(basename "$d" .drive)   (no result)"
		fail=1
	fi
done
echo "$(( $(date +%s) - started )) s"
exit $fail
