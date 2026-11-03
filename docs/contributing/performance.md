# Performance checks

Rayzr is measured on deliberately weak reference setups, so a change that
makes the editor or a game slower shows up before a user notices it. The
harness is `scripts/perf/perf.py`; the **Performance** workflow
(`.github/workflows/perf.yml`) runs it on the reference setups and fails
when a target is missed or a number regresses beyond the margin.

## What is measured

| Part | How | Numbers |
|---|---|---|
| Template games | Each template's first *play-through: from the title* test (`scripts/templates/tests/<id>.json`: its scripted input, fixed 1/60 s steps) played 3 times with uncapped frames. The test's own checks must still pass: a run that played differently is not compared. | Frame time (frame end to frame end): mean, p50, p95, p99, max; the update+draw part; the share of frames over 16.7 ms; startup (process start to the first frame) |
| Editor | `tests/perf/editor.drive` on the project of `scripts/make_bench_project.py`: the demo scene idle; 5000 sprites idle, clicked, box-selected, dragged, all selected and nudged with the arrow keys; a 400x400 tile map; Simulate with 5000 particles | Frame time (uncapped): mean, p95, p99, max, and the phases (ui, viewport, present) |
| Startup and Play | The same drive | Editor startup (process start to the first frame), time-to-Play: Play (F5) and Play Current Scene on the 5000-sprite scene (F6), from the key press to the game's first frame |

The runner writes a frame-time report with `--perf-report <file.json>`
(with `--uncapped`: no vsync, no frame cap). The editor's drive commands
`bench`, `bench-start` / `bench-stop` and `bench-value` print
`[bench-json]` lines ([Editor test drives](../../editor/TEST_DRIVE.md)).

## The reference setups

| Setup | What it is |
|---|---|
| `linux-llvmpipe-2core` | GitHub's Ubuntu 22.04 runner held to 2 cores (`taskset -c 0,1`, the X server too), Mesa's llvmpipe software OpenGL with 2 threads (`LIBGL_ALWAYS_SOFTWARE=1`, `LP_NUM_THREADS=2`) under Xvfb at 1280x720: no GPU, slower than any integrated graphics chip |
| `android-emulator-api34` | The Android 14 (API 34) x86_64 emulator with Google APIs, 2 cores, 2 GB of RAM and SwiftShader GL; the arm64 runner runs through its ARM translation: a budget phone or slower |

## Targets

The targets are in `tests/perf/baseline.json` (`targets`, per setup, with a
`default`). A `*` stands for any template or bench.

| Metric | Target | Why |
|---|---|---|
| Template frame time, p95 | 16.7 ms | The game holds 60 fps: 95 frames in 100 fit in a 60 Hz frame (the rest are loads and scene changes) |
| Template startup | 3 s (Android: 6 s) | Process start to the first frame: the game is on screen at once |
| Editor idle, p95 (demo, 5000 sprites, tile map, particles) | 33.3 ms | The editor stays responsive: 30 fps or better on software GL with a large scene open |
| Editor interaction, p95 (click, box select, drag, all selected, nudge) | 50 ms | Selecting and moving in a large scene keeps up with the mouse (20 fps or better) |
| Editor startup | 8 s | Process start to the first frame with the project open |
| Time-to-Play (F5, F6 on 5000 sprites) | 4 s | Play to the game's first frame |

The frame times are uncapped, so they show what a frame costs rather than
the display's pace. On faster machines the numbers are far lower: an
Apple M2 Pro plays every template at about 1-2 ms a frame (p95).

## The baseline and the margin

Besides the targets, each setup has a recorded baseline (`setups` in
`tests/perf/baseline.json`). A number fails when it is more than the
baseline plus `margin` (25%) plus `slack_ms` (1 ms for frame times, 250 ms
for startup and Play): enough room for a shared CI machine's noise, not for
a real slowdown. A setup with no baseline yet is checked against the
targets only.

The baseline changes only on purpose, after a change that is meant to make
things faster or that knowingly costs time:

1. Run the **Performance** workflow (Actions > Performance > Run workflow).
2. Download its artifact (`perf-linux-llvmpipe-2core`, `perf-android-emulator-api34`).
3. `python3 scripts/perf/perf.py --update-baseline report-linux.json` (and
   the Android report), then commit `tests/perf/baseline.json` with the
   reason in the message.

## Running it locally

```bash
odin build runner -o:speed -out:/tmp/rayzr_perf/runner
odin build editor -o:speed -out:/tmp/rayzr_perf/editor
python3 scripts/perf/perf.py --runner /tmp/rayzr_perf/runner --editor /tmp/rayzr_perf/editor \
    --setup local --out /tmp/rayzr_perf/report.json
python3 scripts/perf/perf.py --table /tmp/rayzr_perf/report.json   # the table again, with the targets
```

- Pass template ids to measure only those (`... platformer shmup`),
  `--no-templates` for the editor only, `--reps 1` for a quick look.
- `--android` measures on a device or emulator over adb (the test-hooks
  runner: `OUT=bin/runners/android-test scripts/build_android_runner.sh
  -define:RAYZR_TEST_HOOKS=true`).
- `PERF_TMP=<dir>` puts the scratch copies there.
- On Linux, `taskset -c 0,1 xvfb-run -a` with `LIBGL_ALWAYS_SOFTWARE=1
  LP_NUM_THREADS=2` reproduces the reference setup.
- On a Mac, `taskpolicy -c background python3 scripts/perf/perf.py ...` runs
  everything on the efficiency cores: a rough stand-in for a slow CPU (the
  GPU stays fast).

For where the time goes inside a frame, see the Profiler tab
([Profiler](../editor/tab-profiler.md)), a profiling build
(`-define:RAYZR_PROF=true`, `--prof trace.spall`, `scripts/spall_summary.py`)
and `scripts/bench.sh` (the engine's micro-benchmarks).
