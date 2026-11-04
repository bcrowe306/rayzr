#!/usr/bin/env bash
# DEBUG(#331): temporary llvmpipe experiments (removed before merge).
set -u
mkdir -p perf "$RUNNER_TEMP/perf"; grep -m1 "model name" /proc/cpuinfo
run() { # name env... -- templates...
  name=$1; shift
  envs=(); while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  env "${envs[@]}" PERF_TMP="$RUNNER_TEMP/perf" taskset -c 0,1 xvfb-run -a -s "-screen 0 1920x1080x24" \
    python3 -u scripts/perf/perf.py --runner "$R" --reps 2 --setup x --out "perf/$name.json" "$@" > "perf/$name.log" 2>&1
  python3 - "$name" "perf/$name.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[2]))["templates"]
for k, v in d.items():
    if not v.get("passed"): print(f"{sys.argv[1]:14} {k:18} FAIL {v.get('failures')}"); continue
    f, c = v["frame_ms"], v["cpu_ms"]
    print(f"{sys.argv[1]:14} {k:18} mean {f['mean']:6.2f} p95 {f['p95']:6.2f} cpu {c['mean']:5.2f}")
PY
}
hide() { # names...: hidden in the vector template's stages (copied back after)
  python3 - "$@" <<'PY'
import json, sys, glob
names = set(sys.argv[1:])
for p in glob.glob("templates/vector_character/scenes/stage*.scene.json"):
    d = json.load(open(p))
    def walk(n):
        if n.get("name") in names: n["visible"] = False
        for c in n.get("children", []): walk(c)
    walk(d.get("root", d))
    json.dump(d, open(p, "w"))
PY
}
T="vector_character dungeon"
R=bin/perf/runner; run skin1 X=1 -- $T
R=bin/perf/runner_base; run noskinfix1 X=1 -- $T
R=bin/perf/runner; run skin2 X=1 -- $T
R=bin/perf/runner_base; run noskinfix2 X=1 -- $T
R=bin/perf/runner; run skin3 X=1 -- $T
R=bin/perf/runner_base; run noskinfix3 X=1 -- $T
