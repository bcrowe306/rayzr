#!/usr/bin/env bash
# Runs the performance benchmarks and prints their [bench] lines:
#   - engine (no window): node create/destroy, transforms, scene JSON,
#     particles, Lua scripts (engine/perf_bench_test.odin), component
#     instances (engine/component_bench_test.odin), level generation
#     (engine/level_gen_bench_test.odin)
#   - rendering (a window, uncapped frames): the runner's --bench on the
#     scenes of scripts/make_bench_project.py, with and without the render
#     caches (--no-render-cache)
#   - editor (uncapped frames, by phase): tests/bench/editor.drive on the
#     same project (frame_timing.odin)
#   scripts/bench.sh [engine|rendering|editor]...   (default: all)
# Baselines are recorded in engine/GAPS.md ("Performance baselines").
# macOS: needs an awake display for the rendering part.
set -uo pipefail
cd "$(dirname "$0")/.."
parts="${*:-engine rendering editor}"
want() { [[ " $parts " == *" $1 "* ]]; }
# (The display stays awake while it runs: raylib's InitWindow fails on a sleeping one.)
if command -v caffeinate > /dev/null; then caffeinate -u -t 900 & trap 'kill $! 2> /dev/null' EXIT; fi
python3 scripts/make_bench_project.py /tmp/rayzr_bench > /dev/null

if want engine; then
echo "== engine"
odin build engine -build-mode:test -o:speed -define:ODIN_TEST_THREADS=1 \
	-define:ODIN_TEST_NAMES=engine.bench_scene_hot_paths,engine.bench_particles,engine.bench_scripts,engine.bench_navigation,engine.bench_components,engine.bench_level_gen,engine.bench_level_gen_wfc \
	-out:/tmp/rayzr_bench_engine > /dev/null || exit 1
/tmp/rayzr_bench_engine 2>&1 | grep '\[bench\]' | sed 's/^.*\[bench\]/[bench]/'
fi

if want rendering; then
echo "== rendering"
odin build runner -o:speed -out:/tmp/rayzr_bench_runner || exit 1
for s in bench_sprites bench_sprites_overlap bench_tiles bench_particles bench_particles_circles bench_particles_20k bench_particles_gpu_100k bench_lights bench_physics bench_scripts bench_ysort main; do
	for flag in "" --no-render-cache; do
		line=$(perl -e 'alarm 120; exec @ARGV' /tmp/rayzr_bench_runner /tmp/rayzr_bench --scene "scenes/$s.scene.json" --bench 300 $flag 2>&1 | grep '\[bench\]')
		printf '%-24s %-18s %s\n' "$s" "${flag:-cached}" "${line#*frames: }"
	done
done
fi

if want editor; then
echo "== editor"
odin build editor -o:speed -out:/tmp/rayzr_bench_editor || exit 1
perl -e 'alarm 300; exec @ARGV' /tmp/rayzr_bench_editor --project /tmp/rayzr_bench --drive tests/bench/editor.drive --shots /tmp/rayzr_bench_shots 2>&1 \
	| grep -E '\[bench\]|FAIL' | sed 's/^\[bench\] editor //'
fi
