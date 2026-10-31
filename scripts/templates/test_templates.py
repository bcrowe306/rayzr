#!/usr/bin/env python3
"""Plays the New Project templates (templates/<id>/) in the runner with
scripted input and checks the result (TODO E.2):

    python3 scripts/templates/test_templates.py [--runner bin/runners/macos/runner] [platformer ...]
    python3 scripts/templates/test_templates.py --previews    # also writes templates/<id>/preview.png

Tests: scripts/templates/tests/<id>.json, a list of
    {"name": "...", "frames": 120,
     "input": ["10 RIGHT down", "40 SPACE tap 12",          # runner --input-script lines
               "50 mouse 640 360 click"],
     "patch": {"Player": {"position": [900, 100], "script.lives": 1}},  # optional: a copy's node fields / script properties
     "scene": "scenes/level1.scene.json",                  # optional: the scene patched / started
     "expect": [["Coins", "text", "==", "Coins 1 / 11"],   # node, field, op, value
                ["Player", "x", "<", 120],                  # x / y: position; others: properties
                ["Enemy1", "exists", "==", false]]}
Each runs on a fresh copy of the template (--user-data in it), with fixed
1/60 s frames: the same every time. Linux CI runs it under xvfb-run.

Render tests: "golden": {"image": "tests/vector/expected/x.png",
"max_pixels": 0.01, "threshold": 48} screenshots the last frame and fails
when more than max_pixels (a fraction) of its pixels differ from the image
by more than threshold (0-255) - room for GPUs' anti-aliasing differences
(png_diff.py). --update-goldens writes the images instead (tests with an
"env" are variants compared with the default's image: skipped then).
"""
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import png_diff  # noqa: E402

UPDATE_GOLDENS = False

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TESTS = os.path.join(os.path.dirname(__file__), "tests")


def default_runner():
    plat = {"Darwin": "macos", "Linux": "linux", "Windows": "windows"}[platform.system()]
    exe = "runner.exe" if plat == "windows" else "runner"
    return os.path.join(ROOT, "bin", "runners", plat, exe)


def find(node, name):
    if node.get("name") == name:
        return node
    for c in node.get("children", []):
        f = find(c, name)
        if f:
            return f
    return None


def field(node, key):
    if node is None:
        return None
    if key == "x":
        return node.get("position", [0, 0])[0]
    if key == "y":
        return node.get("position", [0, 0])[1]
    if "." in key and key.split(".")[0] in node:  # (a nested value: "tilemap.map_size")
        v = node
        for part in key.split("."):
            v = v.get(part) if isinstance(v, dict) else None
        return v
    if key in node:
        return node[key]
    return node.get("properties", {}).get(key, node.get("script", {}).get("properties", {}).get(key))


def check(op, got, want):
    if op == "==":
        return got == want
    if op == "!=":
        return got != want
    if op == "contains":
        return isinstance(got, str) and want in got
    if op == "!contains":
        return isinstance(got, str) and want not in got
    if got is None:
        return False
    return {"<": got < want, ">": got > want, "<=": got <= want, ">=": got >= want}[op]


def run_test(runner, tid, test, tmp):
    proj = os.path.join(tmp, "project")
    shutil.copytree(os.path.join(ROOT, test.get("project", os.path.join("templates", tid))), proj)
    cfg = json.load(open(os.path.join(proj, "project.json")))
    scene_rel = test.get("scene", cfg["initial_scene"])
    if test.get("patch"):
        sp = os.path.join(proj, scene_rel)
        sc = json.load(open(sp))
        for name, fields in test["patch"].items():
            n = find(sc["root"], name)
            assert n, f"patch: no node {name}"
            for k, v in fields.items():
                if k in ("position", "scale", "rotation", "enabled", "visible"):
                    n[k] = v
                elif k.startswith("script."):
                    n.setdefault("script", {}).setdefault("properties", {})[k[7:]] = v
                else:
                    n.setdefault("properties", {})[k] = v
        json.dump(sc, open(sp, "w"))
    inp = os.path.join(tmp, "input.txt")
    open(inp, "w").write("\n".join(test.get("input", [])) + "\n")
    dump = os.path.join(tmp, "dump.json")
    cmd = [runner, proj, "--hidden", "--user-data", os.path.join(tmp, "userdata"), "--frames", str(test["frames"]),
           "--input-script", inp, "--dump-scene", dump, "--scene", scene_rel]
    cmd += test.get("args", [])  # ("args": extra runner arguments, e.g. ["--console", "perf"])
    shot = test.get("screenshot")
    golden = test.get("golden")
    if golden:
        shot = os.path.join(ROOT, golden["image"]) if UPDATE_GOLDENS else os.path.join(tmp, "shot.png")
        if UPDATE_GOLDENS:
            os.makedirs(os.path.dirname(shot), exist_ok=True)
    if shot:
        cmd += ["--screenshot", shot]
    env = dict(os.environ, **test.get("env", {}))  # ("env": extra environment variables)
    log = subprocess.run(cmd, capture_output=True, text=True, timeout=120, env=env)
    if not os.path.isfile(dump):
        return [f"no scene dump (exit {log.returncode}): {log.stderr[-600:]}"]
    top = json.load(open(dump))
    root = top["root"]
    fails = []
    for name, key, op, want in test["expect"]:
        node = top if name == "@scene" else find(root, name)  # (@scene: the running scene - its "name")
        got = (node is not None) if key == "exists" else field(node, key)
        if not check(op, got, want):
            fails.append(f"{name}.{key} {op} {want!r}: got {got!r}")
    if golden and not UPDATE_GOLDENS:
        ref = os.path.join(ROOT, golden["image"])
        if not os.path.isfile(shot):
            fails.append("no screenshot")
        elif not os.path.isfile(ref):
            fails.append(f"no golden image {golden['image']} (--update-goldens writes it)")
        else:
            frac, mean = png_diff.diff(shot, ref, golden.get("threshold", 48))
            if frac > golden.get("max_pixels", 0.01):
                keep = os.path.join(ROOT, "build", "golden_failures", os.path.basename(golden["image"]))
                os.makedirs(os.path.dirname(keep), exist_ok=True)
                shutil.copyfile(shot, keep)
                fails.append(f"render differs from {golden['image']}: {frac:.2%} of pixels (mean {mean:.1f}); got: {keep}")
    errors = [l for l in log.stderr.splitlines() + log.stdout.splitlines() if "[ERROR]" in l or "Lua error" in l]
    fails += [f"log: {e}" for e in errors[:5]]
    return fails


def main():
    args = sys.argv[1:]
    runner = default_runner()
    previews = False
    if "--runner" in args:
        i = args.index("--runner")
        runner = os.path.abspath(args[i + 1])
        del args[i:i + 2]
    global UPDATE_GOLDENS
    if "--update-goldens" in args:
        UPDATE_GOLDENS = True
        args.remove("--update-goldens")
    if "--previews" in args:
        previews = True
        args.remove("--previews")
    # --suite file.json: tests of other projects (each test's "project": a
    # folder in the repository; e.g. tests/aseprite/runtime_tests.json).
    suites = []
    if "--suite" in args:
        i = args.index("--suite")
        suites.append(args[i + 1])
        del args[i:i + 2]
    ids = args or ([] if suites else sorted(f[:-5] for f in os.listdir(TESTS) if f.endswith(".json")))
    total = failed = 0
    for tid in ids + suites:
        path = tid if tid.endswith(".json") else os.path.join(TESTS, tid + ".json")
        tests = json.load(open(path if os.path.isabs(path) or not tid.endswith(".json") else os.path.join(ROOT, path)))
        tid = os.path.basename(tid)[:-5] if tid.endswith(".json") else tid
        if previews:
            # The Welcome window's picture: the first test's start, full size.
            tests = [{"name": "preview", "frames": 20, "expect": [], "screenshot": os.path.join(ROOT, "templates", tid, "preview.png")}] + tests
        for test in tests:
            if UPDATE_GOLDENS and test.get("env"):
                continue
            total += 1
            with tempfile.TemporaryDirectory(prefix=f"rayzr_tpl_{tid}_") as tmp:
                fails = run_test(runner, tid, test, tmp)
            if fails:
                failed += 1
                print(f"FAIL {tid}: {test['name']}")
                for f in fails:
                    print(f"     {f}")
            else:
                print(f"ok   {tid}: {test['name']}")
    print(f"{total - failed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
