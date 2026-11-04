#!/usr/bin/env bash
# DEBUG(#331): temporary llvmpipe experiments (removed before merge).
set -u
mkdir -p perf "$RUNNER_TEMP/perf"
run() { # name env... -- templates...
  name=$1; shift
  envs=(); while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  env "${envs[@]}" PERF_TMP="$RUNNER_TEMP/perf" taskset -c 0,1 xvfb-run -a -s "-screen 0 1920x1080x24" \
    python3 -u scripts/perf/perf.py --runner bin/perf/runner --reps 2 --setup x --out "perf/$name.json" "$@" > "perf/$name.log" 2>&1
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
sudo apt-get install -y -qq linux-tools-common linux-tools-$(uname -r) > /dev/null 2>&1 || sudo apt-get install -y -qq linux-tools-generic > /dev/null 2>&1
sudo sysctl -w kernel.perf_event_paranoid=-1 kernel.kptr_restrict=0 > /dev/null
PERFBIN=$(ls /usr/lib/linux-tools/*/perf 2>/dev/null | head -1); [ -n "$PERFBIN" ] || PERFBIN=perf
echo "perf: $PERFBIN"
prof() { # name template
  cat > /tmp/wrap.sh <<W
#!/bin/sh
exec $PERFBIN record -F 2000 -g -o $PWD/perf/$1.data -- $PWD/bin/perf/runner "\$@"
W
  chmod +x /tmp/wrap.sh
  PERF_TMP="$RUNNER_TEMP/perf" taskset -c 0,1 xvfb-run -a -s "-screen 0 1920x1080x24" \
    python3 -u scripts/perf/perf.py --runner /tmp/wrap.sh --reps 1 --setup x --out "perf/$1.json" "$2" > "perf/$1.log" 2>&1
  $PERFBIN report -i perf/$1.data --no-children --sort comm,dso,sym --stdio 2>/dev/null | grep -v "^$" | grep "%" | head -70 > perf/$1.txt
  $PERFBIN report -i perf/$1.data --no-children --sort comm --stdio 2>/dev/null | grep "%" | head -10 >> perf/$1.txt
  echo "=== $1"; cat perf/$1.txt
}
prof prof_vc vector_character
prof prof_pf platformer
exit 0
cp -r templates/vector_character /tmp/vc_orig
run base X=1 -- vector_character dungeon platformer
run noopaque RAYZR_X_NOOPAQUE=1 -- vector_character dungeon platformer
run simplefs RAYZR_X_FS=simple -- vector_character
run immediate RAYZR_VECTOR_MODE=immediate -- vector_character
hide Backdrop Backdrop2; run nobackdrop X=1 -- vector_character
rm -rf templates/vector_character; cp -r /tmp/vc_orig templates/vector_character
hide Rig PepRig; run norigs X=1 -- vector_character
rm -rf templates/vector_character; cp -r /tmp/vc_orig templates/vector_character
hide Backdrop Backdrop2 Rig PepRig Thorns1 Thorns2 Goal; run novector X=1 -- vector_character
rm -rf templates/vector_character; cp -r /tmp/vc_orig templates/vector_character
hide Backdrop Backdrop2; run nobd_simplefs RAYZR_X_FS=simple -- vector_character
