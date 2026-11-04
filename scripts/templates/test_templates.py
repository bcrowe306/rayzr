#!/usr/bin/env python3
"""Plays the New Project templates (templates/<id>/) in the runner with
scripted input and checks the result (TODO E.2):

    python3 scripts/templates/test_templates.py [--runner bin/runners/macos/runner] [platformer ...]
    python3 scripts/templates/test_templates.py --previews    # also writes templates/<id>/preview.png
                                                              # (of its "preview" test: below)

Tests: scripts/templates/tests/<id>.json, a list of
    {"name": "...", "frames": 120,
     "input": ["10 RIGHT down", "40 SPACE tap 12",          # runner --input-script lines
               "50 mouse 640 360 click"],
     "patch": {"Player": {"position": [900, 100], "script.lives": 1}},  # optional: a copy's node fields / script properties
     "scene": "scenes/level1.scene.json",                  # optional: the scene patched / started
     "patch_scene": "scenes/level1.scene.json",            # optional: the scene patched, when not that one
     "expect": [["Coins", "text", "==", "Coins 1 / 11"],   # node, field, op, value
                ["Player", "x", "<", 120],                  # x / y: position; others: properties
                ["Enemy1", "exists", "==", false]],
     "quits": false}                                       # optional: true - the game must end itself first (no dump)
Saves (#295, the saving tutorial): "user_files": {"slot_1.json": {...}} are
written into the user-data folder first (a save from an older version);
"before": [{"frames": 60, "input": [...], "quits": true}, ...] are earlier
runs of the same copy with the same user-data folder (each must end
cleanly), so the test's own run sees what they saved; an expect row
["@file:slot_1.json", "game.gems", "==", 5] reads a user-data file.
A test with "preview": true is the Welcome window's picture (--previews:
its last frame, e.g. a level being played; none: the initial scene's 20th
frame); it runs only then.
Each runs on a fresh copy of the template (--user-data in it), with fixed
1/60 s frames: the same every time. "frames": N runs exactly N frames - the
dump (and screenshot) is of frame N, however small (#362: runners before it
ran at least 25 with a capture). Linux CI runs it under xvfb-run.

Render tests: "golden": {"image": "tests/vector/expected/x.png",
"max_pixels": 0.01, "threshold": 48} screenshots the last frame and fails
when more than max_pixels (a fraction) of its pixels differ from the image
by more than threshold (0-255) - room for GPUs' anti-aliasing differences
(png_diff.py). --update-goldens writes the images instead (tests with an
"env" are variants compared with the default's image: skipped then).

Platforms (#329): the same tests play in the other runners too -
    --web       the web runner (bin/runners/web: scripts/build_web_runner.sh) in headless
                Chrome (CHROME=its path; Node 22+): each test's copy is packed (game.rayzr)
                and served on localhost; the page's ?test mode (scripts/web/shell.html)
                takes the runner's arguments, saves live in IndexedDB and every run is a
                page load (scripts/web/run_test.mjs)
    --android   a device or emulator (adb, ADB=its path; one at a time): each template is
                packaged (arm64) with a runner built with -define:RAYZR_TEST_HOOKS=true
                (--android-runner libmain.so; default bin/runners/android-test - OUT=that
                scripts/build_android_runner.sh -define:RAYZR_TEST_HOOKS=true) and
                installed (debuggable); a run is the app started with its arguments in
                its own files folder (run-as; runner/android/main.odin), logcat is its log. An x86_64
                emulator runs it through its ARM translation (API 30+ images; CI: 34)
Tests with "audio_clock" check something timed by the audio clock against a
frame (lip-sync): skipped on Android and the web, where the frames (a slow
emulator, headless Chrome) fall behind the audio. Tests with a "golden" image or an "env" run on the desktop only; ones that
quit (Engine.quit: "quits", also in "before") are skipped on the web, where
quitting does nothing (saves still reach IndexedDB when a run ends).
"""
import json
import os
import base64
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import time

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


def errors_in(lines):
    return [l for l in lines if "[ERROR]" in l or "Lua error" in l]


class Desktop:
    """The desktop runner: a process a run."""
    skips = ()
    notes = ()

    def __init__(self, runner):
        self.runner = runner

    def run_all(self, tid, proj, userdata, runs):
        out = []
        for r in runs:
            cmd = [self.runner, proj, "--hidden", "--user-data", userdata, "--frames", str(r["frames"]),
                   "--input-script", r["input_path"], "--dump-scene", r["dump"], "--scene", r["scene"]] + r["args"]
            if r.get("shot"):
                cmd += ["--screenshot", r["shot"]]
            if r.get("perf"):  # (scripts/perf/perf.py: uncapped frames, their times written)
                cmd += ["--uncapped", "--perf-report", r["perf"]]
            env = dict(os.environ, **r.get("env", {}))
            try:
                log = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace",
                                     timeout=120, env=env)
                out.append({"code": log.returncode, "tail": log.stderr[-600:],
                            "errors": errors_in(log.stderr.splitlines() + log.stdout.splitlines())})
            except subprocess.TimeoutExpired:
                out.append({"code": -1, "tail": "timed out (120 s)", "errors": []})
            if out[-1]["code"] != 0:
                break
        return out

    def close(self):
        pass


_PACKER = None


def pack(proj, out):
    """A project folder -> a .rayzr (scripts/pack_rayzr.odin, built once)."""
    global _PACKER
    if _PACKER is None:
        d = tempfile.mkdtemp(prefix="rayzr_packer_")
        _PACKER = os.path.join(d, "pack_rayzr.exe" if platform.system() == "Windows" else "pack_rayzr")
        subprocess.run(["odin", "build", os.path.join(ROOT, "scripts", "pack_rayzr.odin"), "-file", "-out:" + _PACKER],
                       check=True, cwd=ROOT)
    subprocess.run([_PACKER, proj, out], check=True, capture_output=True)


class Web:
    """The web runner in headless Chrome (scripts/web/run_test.mjs)."""
    skips = ("golden", "env", "quits", "audio_clock")  # (Engine.quit does nothing on the web: a page can't close itself; headless Chrome's frames don't keep pace with its audio clock)
    notes = ()

    def __init__(self):
        src = os.path.join(ROOT, "bin", "runners", "web")
        if not os.path.isfile(os.path.join(src, "index.wasm")):
            sys.exit("no web runner: scripts/build_web_runner.sh")
        self.dir = tempfile.mkdtemp(prefix="rayzr_web_")
        for f in ("index.html", "index.js", "index.wasm", "odin.js"):
            shutil.copy(os.path.join(src, f), self.dir)
        os.makedirs(os.path.join(self.dir, "fonts"))
        shutil.copy(os.path.join(ROOT, "engine", "Open_Sans", "static", "OpenSans-Regular.ttf"), os.path.join(self.dir, "fonts"))
        self.server = subprocess.Popen([sys.executable, "-u", "-m", "http.server", "0", "--bind", "127.0.0.1"], cwd=self.dir,
                                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        line = self.server.stdout.readline()  # "Serving HTTP on 127.0.0.1 port N ..."
        self.port = int(re.search(r"port (\d+)", line).group(1))

    def run_all(self, tid, proj, userdata, runs):
        pack(proj, os.path.join(self.dir, "game.rayzr"))
        spec = {"url": f"http://127.0.0.1:{self.port}/index.html?test", "timeout": 120, "runs": []}
        for i, r in enumerate(runs):
            args = ["--frames", str(r["frames"]), "--input-script", "/test/input.txt", "--dump-scene", "/test/dump.json",
                    "--scene", r["scene"]] + r["args"]
            run = {"args": args, "files": {"/test/input.txt": r["input"]}, "dump": "/test/dump.json"}
            if r.get("shot"):
                run["args"] += ["--screenshot", "/test/shot.png"]
                run["shot"] = "/test/shot.png"
            if i == 0:
                run["clear_save"] = True
                run["save_files"] = {f: open(os.path.join(userdata, f)).read() for f in os.listdir(userdata)}
            spec["runs"].append(run)
        sp, rp = os.path.join(self.dir, "spec.json"), os.path.join(self.dir, "result.json")
        json.dump(spec, open(sp, "w"))
        if os.path.isfile(rp):
            os.remove(rp)
        subprocess.run(["node", os.path.join(ROOT, "scripts", "web", "run_test.mjs"), sp, rp], timeout=150 * len(runs) + 60)
        res = json.load(open(rp))
        out = []
        for r, got in zip(runs, res["runs"]):
            if got["dump"] is not None:
                open(r["dump"], "w").write(got["dump"])
            if got.get("shot"):
                open(r["shot"], "wb").write(base64.b64decode(got["shot"]))
            # (The browser's saves -> the local user-data folder: @file checks read it.)
            shutil.rmtree(userdata)
            os.makedirs(userdata)
            for rel, text in got["save"].items():
                fp = os.path.join(userdata, rel)
                os.makedirs(os.path.dirname(fp), exist_ok=True)
                open(fp, "w").write(text)
            errs = errors_in(got["log"]) + [l for l in got["log"] if l.startswith("[exception]")]
            out.append({"code": 0 if got["ended"] else -1, "errors": errs,
                        "tail": "" if got["ended"] else "the game didn't end (timed out): " + " | ".join(got["log"][-8:])})
        if res.get("error"):
            out.append({"code": -1, "errors": [], "tail": "web: " + res["error"]})
        return out

    def close(self):
        self.server.terminate()
        shutil.rmtree(self.dir, ignore_errors=True)


class Android:
    """A device or emulator over adb: an APK a template (a runner built with
    RAYZR_TEST_HOOKS); a run is the app started with rayzr_test/args.txt."""
    skips = ("golden", "env", "audio_clock")  # (an emulator's frames don't keep pace with its audio clock)

    def __init__(self, runner):
        if not os.path.isfile(runner):
            sys.exit(f"no Android runner {runner}: scripts/build_android_runner.sh -define:RAYZR_TEST_HOOKS=true")
        self.runner = runner
        self.adb = os.environ.get("ADB", "adb")
        self.installed = {}
        self.notes = set()
        self.dir = tempfile.mkdtemp(prefix="rayzr_android_")
        self.sh("input", "keyevent", "82")  # (wakes / unlocks the screen)

    def sh(self, *cmd, check=False):
        return subprocess.run([self.adb, "shell"] + list(cmd), capture_output=True, text=True, check=check, timeout=60)

    def adb_(self, *cmd):
        return subprocess.run([self.adb] + list(cmd), capture_output=True, text=True, check=True, timeout=180)

    # The test folder is the app's own (files/rayzr_test - runner/android/
    # main.odin), reached as the app through run-as (the test APKs are
    # debuggable): from Android 11 on adb can't make folders in shared
    # storage's Android/data/<id>. (Names here are [a-z0-9._/] only: they go
    # through the device's shell.)
    def app(self, pkg, *cmd, check=False):
        return self.sh("run-as", pkg, *cmd, check=check)

    def put(self, pkg, local, rel):
        """A local file -> the app's folder (rel: from its data folder)."""
        with open(local, "rb") as f:
            subprocess.run([self.adb, "exec-in", f"run-as {pkg} sh -c 'cat > {rel}'"], stdin=f,
                           capture_output=True, check=True, timeout=180)

    def get(self, pkg, rel, local):
        """The app's file -> local (False: it has none)."""
        if self.app(pkg, "ls", rel).returncode != 0:
            return False
        data = subprocess.run([self.adb, "exec-out", f"run-as {pkg} cat {rel}"], capture_output=True,
                              check=True, timeout=180).stdout
        open(local, "wb").write(data)
        return True

    def install(self, tid):
        """The template's APK (once): id com.rayzr.test.<id>."""
        if tid not in self.installed:
            pkg = "com.rayzr.test." + re.sub(r"[^a-z0-9]", "", tid.lower())
            out = os.path.join(self.dir, "apk_" + tid)
            subprocess.run([os.path.join(ROOT, "scripts", "package_android.sh"), os.path.join(ROOT, "templates", tid), out,
                            "--id", pkg, "--no-aab", "--debuggable", "--runner", self.runner], check=True,
                           capture_output=True)
            apk = [f for f in os.listdir(out) if f.endswith(".apk")][0]
            self.adb_("install", "-r", os.path.join(out, apk))
            self.installed[tid] = pkg
        return self.installed[tid]

    def run_all(self, tid, proj, userdata, runs):
        pkg = self.install(tid)
        assert re.fullmatch(r"[a-z0-9.]+", pkg)
        ext = "files/rayzr_test"
        self.sh("am", "force-stop", pkg)
        self.app(pkg, "rm", "-r", "-f", ext)
        self.app(pkg, "mkdir", "-p", ext + "/userdata", check=True)
        game = os.path.join(self.dir, "game.rayzr")
        pack(proj, game)
        self.put(pkg, game, ext + "/game.rayzr")
        for f in os.listdir(userdata):
            assert re.fullmatch(r"[A-Za-z0-9._-]+", f), f
            self.put(pkg, os.path.join(userdata, f), ext + "/userdata/" + f)
        out = []
        for i, r in enumerate(runs):
            inp = os.path.join(self.dir, "input.txt")
            open(inp, "w").write(r["input"])
            self.put(pkg, inp, ext + "/input.txt")
            args = ["--project", "game.rayzr", "--user-data", "userdata", "--frames", str(r["frames"]),
                    "--input-script", "input.txt", "--dump-scene", f"dump{i}.json", "--scene", r["scene"]] + r["args"]
            if r.get("shot"):
                args += ["--screenshot", f"shot{i}.png"]
            if r.get("perf"):
                args += ["--uncapped", "--perf-report", f"perf{i}.json"]
            ap = os.path.join(self.dir, "args.txt")
            open(ap, "w").write("\n".join(args) + "\n")
            self.adb_("logcat", "-c")
            self.put(pkg, ap, ext + "/args.txt")  # (last: it makes the next start a test run)
            self.sh("am", "start", "-W", "-n", pkg + "/android.app.NativeActivity", check=True)
            # Over: exit.txt written, or the app's process gone (it ended - a
            # clean exit writes exit.txt first - or crashed: the log tells).
            t0, code, gone = time.time(), None, False
            while time.time() - t0 < 120 + r["frames"] / 30:
                got = self.app(pkg, "cat", ext + "/exit.txt")
                if got.returncode == 0 and got.stdout.strip().lstrip("-").isdigit():
                    code = int(got.stdout.strip())
                    break
                if self.sh("pidof", pkg).returncode != 0:
                    gone = True
                    break
                time.sleep(0.25)
            log = self.adb_("logcat", "-d", "-v", "brief", "-s", "Rayzr:V", "libc:V", "DEBUG:V").stdout.splitlines()
            if gone:
                # (The process ended: exit.txt written just before, or a crash -
                # the log says.)
                got = self.app(pkg, "cat", ext + "/exit.txt")
                ok = got.returncode == 0 and got.stdout.strip().lstrip("-").isdigit()
                code = int(got.stdout.strip()) if ok else -1
            self.sh("am", "force-stop", pkg)
            self.app(pkg, "rm", "-f", ext + "/exit.txt")
            self.get(pkg, f"{ext}/dump{i}.json", r["dump"])
            if r.get("shot"):
                self.get(pkg, f"{ext}/shot{i}.png", r["shot"])
            if r.get("perf"):
                self.get(pkg, f"{ext}/perf{i}.json", r["perf"])
            # (The app's saves -> the local user-data folder: @file checks read it.)
            shutil.rmtree(userdata)
            os.makedirs(userdata)
            listed = self.app(pkg, "find", ext + "/userdata", "-type", "f", check=True).stdout.split()
            for rel in listed:
                sub = rel[len(ext + "/userdata/"):]
                assert re.fullmatch(r"[A-Za-z0-9._/-]+", sub) and ".." not in sub, rel
                dst = os.path.join(userdata, *sub.split("/"))
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                self.get(pkg, rel, dst)
            errs = [l for l in log if l.startswith("E/") or "Lua error" in l or "[ERROR]" in l]
            out.append({"code": code if code is not None else -1, "errors": errs,
                        "tail": "" if code == 0 else
                        ("the app's process ended mid-run: " if gone else "the app didn't finish the run: ") + " | ".join(log[-10:])})
            if code != 0:
                break
        return out

    def close(self):
        shutil.rmtree(self.dir, ignore_errors=True)


def run_test(backend, tid, test, tmp, perf=None):
    """Plays a test; the failures (none: it passed). perf: a path - the
    test's own run is uncapped and writes its frame times there (the
    runner's --perf-report; scripts/perf/perf.py)."""
    proj = os.path.join(tmp, "project")
    shutil.copytree(os.path.join(ROOT, test.get("project", os.path.join("templates", tid))), proj)
    cfg = json.load(open(os.path.join(proj, "project.json")))
    scene_rel = test.get("scene", cfg["initial_scene"])
    if test.get("patch"):
        sp = os.path.join(proj, test.get("patch_scene", scene_rel))
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
    userdata = os.path.join(tmp, "userdata")
    os.makedirs(userdata, exist_ok=True)
    for fname, content in test.get("user_files", {}).items():
        json.dump(content, open(os.path.join(userdata, fname), "w"))
    # The runs: "before" (earlier runs on this copy and its user data - what
    # they save, the next one loads), then the test's own.
    before = test.get("before", [])
    runs = []
    for i, run in enumerate(before + [test]):
        own = i == len(before)
        r = {"frames": run["frames"], "input": "\n".join(run.get("input", [])) + "\n",
             "scene": scene_rel if own else run.get("scene", cfg["initial_scene"]),
             "args": test.get("args", []) if own else [], "env": test.get("env", {}) if own else {},
             "dump": os.path.join(tmp, f"dump{i}.json"), "input_path": os.path.join(tmp, f"input{i}.txt")}
        open(r["input_path"], "w").write(r["input"])
        runs.append(r)
    shot = test.get("screenshot")
    golden = test.get("golden")
    if golden:
        shot = os.path.join(ROOT, golden["image"]) if UPDATE_GOLDENS else os.path.join(tmp, "shot.png")
        if UPDATE_GOLDENS:
            os.makedirs(os.path.dirname(shot), exist_ok=True)
    runs[-1]["shot"] = shot
    runs[-1]["perf"] = perf
    results = backend.run_all(tid, proj, userdata, runs)
    missing = {"code": -1, "tail": "not run", "errors": []}
    for i, run in enumerate(before):
        res = results[i] if i < len(results) else missing
        if res["code"] != 0:
            return [f"run {i + 1} before: exit code {res['code']}: {res['tail']}"]
        if run.get("quits") and os.path.isfile(runs[i]["dump"]):
            return [f"run {i + 1} before: the game didn't quit: it ran all {run['frames']} frames"]
        if res["errors"]:
            return [f"run {i + 1} before: log: {e}" for e in res["errors"][:5]]
    res = results[len(runs) - 1] if len(results) >= len(runs) else (results[-1] if results else missing)
    dump = runs[-1]["dump"]
    if test.get("quits"):
        # ("quits": true - the game ends itself (Engine.quit) before its frame
        # count: the runner exits cleanly without writing the scene dump.)
        fails = []
        if res["code"] != 0:
            fails.append(f"exit code {res['code']}: {res['tail']}")
        if os.path.isfile(dump):
            fails.append(f"the game didn't quit: it ran all {test['frames']} frames")
        return fails + [f"log: {e}" for e in res["errors"][:5]]
    if not os.path.isfile(dump):
        return [f"no scene dump (exit {res['code']}): {res['tail']}"]
    top = json.load(open(dump))
    root = top["root"]
    fails = []
    for name, key, op, want in test["expect"]:
        if name.startswith("@file:"):  # (a user-data file's JSON, e.g. a save slot)
            fp = os.path.join(userdata, name[6:])
            node = json.load(open(fp)) if os.path.isfile(fp) else None
        else:
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
    fails += [f"log: {e}" for e in res["errors"][:5]]
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
    backend = Desktop(runner)
    if "--web" in args:
        args.remove("--web")
        backend = Web()
    if "--android" in args:
        args.remove("--android")
        so = os.path.join(ROOT, "bin", "runners", "android-test", "libmain.so")
        if "--android-runner" in args:
            i = args.index("--android-runner")
            so = os.path.abspath(args[i + 1])
            del args[i:i + 2]
        if suites:
            sys.exit("--android plays the templates (an APK each), not a --suite")
        backend = Android(so)
    ids = args or ([] if suites else sorted(f[:-5] for f in os.listdir(TESTS) if f.endswith(".json")))
    total = failed = skipped = 0
    for tid in ids + suites:
        path = tid if tid.endswith(".json") else os.path.join(TESTS, tid + ".json")
        tests = json.load(open(path if os.path.isabs(path) or not tid.endswith(".json") else os.path.join(ROOT, path)))
        tid = os.path.basename(tid)[:-5] if tid.endswith(".json") else tid
        if previews:
            # The Welcome window's picture, full size: the "preview" test's last
            # frame (else the initial scene's start).
            shot = {"name": "preview", "frames": 20}
            shot.update(next((t for t in tests if t.get("preview")), {}))
            shot.update({"name": "preview", "expect": [], "screenshot": os.path.join(ROOT, "templates", tid, "preview.png")})
            tests = [shot] + tests
        tests = [t for t in tests if not t.get("preview") or t.get("screenshot")]
        for test in tests:
            if UPDATE_GOLDENS and test.get("env"):
                continue
            if any(test.get(k) or any(b.get(k) for b in test.get("before", [])) for k in backend.skips):
                skipped += 1
                print(f"skip {tid}: {test['name']} (not on this platform: {', '.join(k for k in backend.skips if test.get(k) or any(b.get(k) for b in test.get('before', [])))})")
                continue
            total += 1
            with tempfile.TemporaryDirectory(prefix=f"rayzr_tpl_{tid}_") as tmp:
                try:
                    fails = run_test(backend, tid, test, tmp)
                except (subprocess.SubprocessError, OSError, ValueError, KeyError) as err:
                    fails = [f"{type(err).__name__}: {err}"]
            if fails:
                failed += 1
                print(f"FAIL {tid}: {test['name']}")
                for f in fails:
                    print(f"     {f}")
            else:
                print(f"ok   {tid}: {test['name']}")
    backend.close()
    for n in sorted(backend.notes):
        print(f"note: {n}")
    print(f"{total - failed} passed, {failed} failed" + (f", {skipped} skipped" if skipped else ""))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
