#!/usr/bin/env bash
# Crash reports end to end (engine/crash_report.odin, editor/crash_reports.odin):
# the runner and the editor crash for real (--crash-test segv / panic / abort)
# and write a report with its reason, stack and recent lines; the editor's
# next start offers its report (tests/crash/reopen.drive).
#   scripts/test_crash.sh [runner] [editor]
#   (defaults: bin/runners/<platform>/runner, bin/editor; Linux CI: under xvfb-run)
set -uo pipefail
cd "$(dirname "$0")/.."
case "$(uname -s)" in Darwin) platform=macos ;; Linux) platform=linux ;; *) platform=windows ;; esac
runner="${1:-bin/runners/$platform/runner}"
editor="${2:-bin/editor}"
tmp="$(mktemp -d /tmp/rayzr_crash_test.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
fails=0
[ -x "$runner" ] && [ -x "$editor" ] || { echo "no runner / editor: build them (scripts/build_runners.sh, odin build editor -out:bin/editor)"; exit 1; }
check() { # check <description> <command...>
	if "${@:2}"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}
# (macOS: hardware faults reach the handlers even under a parent's Mach
# exception port - crash_report_posix.odin.)
run() { perl -e 'alarm 60; exec @ARGV' "$@"; }

for kind in segv panic abort; do
	ud="$tmp/runner_$kind"
	run "$runner" assets/demo_project --hidden --user-data "$ud" --crash-test "$kind" > "$tmp/runner_$kind.log" 2>&1
	code=$?
	report=$(ls "$ud"/crashes/crash-*.txt 2>/dev/null | head -1)
	check "runner $kind: crashed (exit $code)" test "$code" -ne 0 -a "$code" -ne 142
	check "runner $kind: a report" test -n "$report"
	[ -n "$report" ] || continue
	check "runner $kind: reason" grep -q "^reason: " "$report"
	check "runner $kind: a stack frame" test "$(sed -n '/^stack:/,/^recent:/p' "$report" | grep -c '0x')" -ge 1
	check "runner $kind: recent lines" grep -q "crash test: $kind" "$report"
	check "runner $kind: the path on stderr" grep -q "Crash report: " "$tmp/runner_$kind.log"
done
grep -q "SIGSEGV\|ACCESS_VIOLATION" "$tmp"/runner_segv/crashes/*.txt && echo "ok   runner segv: the signal named" || { echo "FAIL runner segv: the signal named"; fails=$((fails + 1)); }
# (#392) macOS / Linux: the faulting instruction (pc) with its procedure's
# name - Linux's from the executable's symbol table - and the address touched.
if [ "$platform" != windows ]; then
	segv=$(ls "$tmp"/runner_segv/crashes/crash-*.txt 2>/dev/null | head -1)
	check "runner segv: the pc, named (engine::...)" grep -Eq '^  pc  0x[0-9a-f]+  engine::' "$segv"
	check "runner segv: the address touched" grep -q '^address:  0x8 ' "$segv"
fi

# The editor: crash, then the next start offers the report.
cp -R assets/demo_project "$tmp/project"
ud="$tmp/editor"
run "$editor" --project "$tmp/project" --hidden --user-data "$ud" --crash-test panic > "$tmp/editor_crash.log" 2>&1
code=$?
report=$(ls "$ud"/crashes/crash-*.txt 2>/dev/null | head -1)
check "editor: crashed (exit $code)" test "$code" -ne 0 -a "$code" -ne 142
check "editor: a report" test -n "$report"
[ -n "$report" ] && check "editor: Rayzr Editor's report" grep -q "^Rayzr Editor crash report" "$report"
[ -n "$report" ] && check "editor: the panic" grep -q "panic: crash test" "$report"
run "$editor" --project "$tmp/project" --hidden --user-data "$ud" --drive tests/crash/reopen.drive --shots "$tmp/shots" --no-build > "$tmp/editor_reopen.log" 2>&1
check "editor: the next start offers it (tests/crash/reopen.drive)" grep -q "reopen.drive: [0-9]* passed, 0 failed" "$tmp/editor_reopen.log"

if [ "$fails" -gt 0 ]; then
	echo "$fails failed (logs: $tmp kept)"
	trap - EXIT
	exit 1
fi
echo "crash reports: all passed"
