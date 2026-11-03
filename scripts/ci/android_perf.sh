#!/usr/bin/env bash
# CI's Android performance run (#331; .github/workflows/perf.yml), inside the
# emulator job once the emulator is up: the template games measured on the
# device by scripts/perf/perf.py --android (each template's play-through,
# uncapped, with the test-hooks runner: bin/runners/android-test).
#
#   scripts/ci/android_perf.sh perf/report-android.json
set -euo pipefail
cd "$(dirname "$0")/../.."
out="${1:-perf/report-android.json}"
mkdir -p "$(dirname "$out")"
adb wait-for-device
echo "emulator: $(adb shell getprop ro.product.cpu.abilist | tr -d '\r'); $(adb shell nproc | tr -d '\r') cores; $(adb shell cat /proc/meminfo | grep MemTotal | tr -d '\r')"
adb shell settings put global stay_on_while_plugged_in 7 || true
adb shell input keyevent 82 || true
python3 -u scripts/perf/perf.py --android --setup android-emulator-api34 --out "$out"
