#!/usr/bin/env bash
# CI's Android play-throughs (#329), run inside the emulator job once the
# emulator is up (ci.yml: reactivecircus/android-emulator-runner): the
# templates' scripted tests on the device - each template packaged as an
# arm64 APK with the test-hooks runner (bin/runners/android-test), installed
# and played (scripts/templates/test_templates.py --android).
#
#   scripts/ci/android_playthroughs.sh platformer shmup puzzle
#
# The CI emulator is x86_64 (the only kind with KVM on the runners): it runs
# the arm64 runner through its ARM translation (API 30+ Google APIs images; 30's misses instructions the runner uses: CI runs 34) -
# checked first, so a missing translation fails here, saying so.
set -euo pipefail
cd "$(dirname "$0")/../.."
adb wait-for-device
abis="$(adb shell getprop ro.product.cpu.abilist | tr -d '\r')"
echo "emulator ABIs: $abis"
case ",$abis," in
	*,arm64-v8a,*) ;;
	*) echo "::error::the emulator can't run arm64 apps (ABIs: $abis) - an API 34 x86_64 google_apis image translates them"; exit 1 ;;
esac
adb shell settings put global stay_on_while_plugged_in 7 || true
adb shell input keyevent 82 || true
status=0
python3 -u scripts/templates/test_templates.py --android "$@" || status=$?
if [ $status != 0 ]; then
	echo "--- the app's log (logcat, last 200 lines)"
	adb logcat -d -v brief -s Rayzr:V libc:V DEBUG:V AndroidRuntime:V | tail -200 || true
	# (Everything else of the last run - a crash under the ARM translation,
	# EGL / the window, the activity manager - unfiltered.)
	echo "--- the device's log (logcat, last 400 lines, unfiltered)"
	adb logcat -d -v brief | grep -v -E "ro.build.fingerprint" | tail -400 || true
fi
exit $status
