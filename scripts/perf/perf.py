#!/usr/bin/env python3
"""Performance harness (#331): the template games, the editor and
time-to-Play, measured headless and compared with the targets and the
recorded baseline (tests/perf/baseline.json).

    python3 scripts/perf/perf.py --runner /tmp/claude-501/runner --editor bin/editor_speed \\
        --setup macos-local --out /tmp/claude-501/perf/report.json
    python3 scripts/perf/perf.py --android --setup android-emulator-api34 --out report.json
    python3 scripts/perf/perf.py --check report.json          # targets + baseline (exit 1 on a regression)
    python3 scripts/perf/perf.py --check report.json --report-only  # the same, warnings only (pull requests)
    python3 scripts/perf/perf.py --table report.json          # the readable table again
    python3 scripts/perf/perf.py --update-baseline report.json  # its numbers become its setup's baseline

What it measures:
  templates  each template's first "play-through: from the title" test
             (scripts/templates/tests/<id>.json: its scripted input, fixed
             1/60 s steps) played --reps times with uncapped frames; the
             runner's --perf-report gives every frame's time (frame to
             frame), the update+draw part and the startup times. The test's
             own checks must still pass (a run that played differently
             isn't comparable). Desktop runner or Android (--android: the
             test-hooks runner on a device / emulator, as
             scripts/templates/test_templates.py --android).
  editor     --editor: tests/perf/editor.drive on the project of
             scripts/make_bench_project.py - startup, a 5000-sprite scene
             idle / selecting / box-selecting / dragging / all selected /
             nudged, a 400x400 tile map, Simulate with 5000 particles, and
             time-to-Play (Play and Play Current Scene to the game's first
             frame). Each bench is one run (the drive is long).

Numbers per template are the median over the reps of each statistic.
Frame times are uncapped (no vsync): what a frame costs, not the display's
pace. Targets and the regression margin are in tests/perf/baseline.json
(docs/contributing/performance.md).
"""
import argparse
import datetime
import json
import os
import platform
import re
import shutil
import statistics
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "scripts", "templates"))
import test_templates  # noqa: E402

BASELINE = os.path.join(ROOT, "tests", "perf", "baseline.json")
DRIVE = os.path.join(ROOT, "tests", "perf", "editor.drive")
TEST_PREFIX = "play-through: from the title"
STATS = ("mean", "p50", "p95", "p99", "max")


def machine():
    m = {"os": platform.system(), "release": platform.release(), "arch": platform.machine(),
         "cpus": os.cpu_count(), "python": platform.python_version()}
    for k in ("LIBGL_ALWAYS_SOFTWARE", "GALLIUM_DRIVER", "LP_NUM_THREADS"):
        if os.environ.get(k):
            m[k] = os.environ[k]
    if platform.system() == "Darwin":
        m["cpu"] = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True, text=True).stdout.strip()
    elif os.path.isfile("/proc/cpuinfo"):
        names = re.findall(r"model name\s*:\s*(.*)", open("/proc/cpuinfo").read())
        if names:
            m["cpu"] = names[0]
    gl = os.environ.get("PERF_GL_RENDERER")  # (CI: glxinfo -B's renderer line)
    if gl:
        m["gl_renderer"] = gl
    return m


def median_summary(runs, key):
    return {s: round(statistics.median(r[key][s] for r in runs), 3) for s in STATS}


def template_tests(only):
    ids = only or sorted(f[:-5] for f in os.listdir(test_templates.TESTS) if f.endswith(".json"))
    for tid in ids:
        tests = json.load(open(os.path.join(test_templates.TESTS, tid + ".json")))
        test = next((t for t in tests if t["name"].startswith(TEST_PREFIX)), None)
        if test is None:
            sys.exit(f"{tid}: no '{TEST_PREFIX}' test to measure")
        yield tid, test


def run_templates(backend, only, reps, log):
    out = {}
    for tid, test in template_tests(only):
        runs, fails = [], []
        for rep in range(reps):
            with tempfile.TemporaryDirectory(prefix=f"rayzr_perf_{tid}_", dir=os.environ.get("PERF_TMP")) as tmp:
                perf = os.path.join(tmp, "perf.json")
                try:
                    f = test_templates.run_test(backend, tid, test, tmp, perf=perf)
                except (subprocess.SubprocessError, OSError, ValueError, KeyError) as err:
                    f = [f"{type(err).__name__}: {err}"]
                if f:
                    fails += f
                    break
                if not os.path.isfile(perf):
                    fails.append("no perf report (the runner didn't write --perf-report)")
                    break
                runs.append(json.load(open(perf)))
        if fails:
            out[tid] = {"test": test["name"], "passed": False, "failures": fails[:5]}
            log(f"FAIL {tid}: {test['name']}: {fails[0]}")
            continue
        r = {"test": test["name"], "passed": True, "reps": len(runs), "frames": runs[0]["frames"],
             "frame_ms": median_summary(runs, "frame_ms"), "cpu_ms": median_summary(runs, "cpu_ms"),
             "over_budget_pct": round(statistics.median(100 * x["over_budget"] / max(x["frames"], 1) for x in runs), 2),
             "startup_ms": {k: round(statistics.median(x["startup_ms"][k] for x in runs), 1) for k in ("window", "project", "first_frame")}}
        out[tid] = r
        log(f"ok   {tid}: p95 {r['frame_ms']['p95']:.2f} ms, mean {r['frame_ms']['mean']:.2f} ms, "
            f"startup {r['startup_ms']['first_frame']:.0f} ms")
    return out


def run_editor(editor, runner, log):
    tmp = tempfile.mkdtemp(prefix="rayzr_perf_editor_", dir=os.environ.get("PERF_TMP"))
    try:
        proj = os.path.join(tmp, "project")
        subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "make_bench_project.py"), proj], check=True,
                       capture_output=True)
        env = dict(os.environ, RAYZR_GAME_BIN=os.path.abspath(runner))
        cmd = [os.path.abspath(editor), "--project", proj, "--drive", DRIVE, "--shots", os.path.join(tmp, "shots"),
               "--no-build", "--user-data", os.path.join(tmp, "userdata"), "--hidden"]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=900,
                                 env=env, cwd=ROOT)
            text = res.stdout + res.stderr
        except subprocess.TimeoutExpired as err:
            text = (err.stdout or b"").decode("utf-8", "replace") if isinstance(err.stdout, bytes) else (err.stdout or "")
            text += "\n[DRIVE] timed out (900 s)"
        out = {}
        for line in text.splitlines():
            if line.startswith("[bench-json] "):
                v = json.loads(line[len("[bench-json] "):])
                out[v.pop("label")] = v
        fails = [l for l in text.splitlines() if l.startswith("[DRIVE] FAIL") or "timed out" in l]
        summary = next((l for l in text.splitlines() if re.match(r"\[DRIVE\] editor\.drive: \d+ passed", l)), None)
        ok = summary is not None and " 0 failed" in summary and not fails
        if not ok:
            keep = os.path.join(os.environ.get("PERF_TMP") or tempfile.gettempdir(), "rayzr_perf_editor.log")
            open(keep, "w").write(text)
            log(f"FAIL editor drive: {summary or 'did not finish'}; log: {keep}")
            for f in fails[:5]:
                log(f"     {f}")
        for k, v in out.items():
            log(f"ok   editor {k}: " + (f"{v['value']} ms" if "value" in v else f"p95 {v['frame_ms']['p95']:.2f} ms, mean {v['frame_ms']['mean']:.2f} ms"))
        return {"passed": ok, "benches": out, "failures": fails[:5]}
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# --- targets / baseline ----------------------------------------------------

def metrics(report):
    """The checked numbers: {name: value} (ms)."""
    m = {}
    for tid, r in report.get("templates", {}).items():
        if r.get("passed"):
            m[f"templates.{tid}.frame_p95"] = r["frame_ms"]["p95"]
            m[f"templates.{tid}.frame_mean"] = r["frame_ms"]["mean"]
            m[f"templates.{tid}.startup"] = r["startup_ms"]["first_frame"]
    ed = report.get("editor")
    if ed:
        for k, v in ed["benches"].items():
            if "value" in v:
                if v["value"] is not None:
                    m[f"editor.{k}"] = v["value"]
            else:
                m[f"editor.{k}.frame_p95"] = v["frame_ms"]["p95"]
                m[f"editor.{k}.frame_mean"] = v["frame_ms"]["mean"]
    return m


def target_for(targets, name):
    """The target of a metric: the most specific key (exact name, else the
    pattern with the template / bench as *)."""
    if name in targets:
        return targets[name]
    parts = name.split(".")
    for i in range(len(parts) - 1, 0, -1):
        key = ".".join(parts[:i] + ["*"] + parts[i + 1:])
        if key in targets:
            return targets[key]
    return None


def check(report, baseline):
    setup = report["setup"]
    targets = dict(baseline["targets"].get("default", {}), **baseline["targets"].get(setup, {}))
    margin = baseline.get("margin", 0.25)
    slack = baseline.get("slack_ms", {"frame": 1.0, "time": 250.0})
    base = baseline.get("setups", {}).get(setup, {})
    # GitHub's runner CPUs vary (the same code's frame times differ by up to
    # ~2x between them): the baseline is compared only on the CPU it was
    # recorded on; another CPU is checked against the targets alone.
    recorded_cpu = baseline.get("recorded", {}).get(setup, {}).get("machine", {}).get("cpu")
    if base and recorded_cpu and recorded_cpu != report.get("machine", {}).get("cpu"):
        base = {}
    problems, rows = [], []
    for tid, r in report.get("templates", {}).items():
        if not r.get("passed"):
            problems.append(f"templates.{tid}: the play-through failed: {r.get('failures', ['?'])[0]}")
    ed = report.get("editor")
    if ed and not ed["passed"]:
        problems.append(f"editor: the drive failed: {(ed.get('failures') or ['did not finish'])[0]}")
    for name, value in sorted(metrics(report).items()):
        t = target_for(targets, name)
        b = base.get(name)
        s = slack["frame"] if "frame" in name else slack["time"]
        limit = None if b is None else round(b * (1 + margin) + s, 3)
        status = "ok"
        if t is not None and value > t:
            status = "OVER TARGET"
            problems.append(f"{name}: {value:.2f} ms > target {t} ms")
        elif limit is not None and value > limit:
            status = "REGRESSED"
            problems.append(f"{name}: {value:.2f} ms > baseline {b} ms + {int(margin * 100)}% + {s:g} ms = {limit} ms")
        rows.append((name, value, t, b, status))
    return problems, rows


def table(report, baseline=None):
    lines = [f"Rayzr performance: {report['setup']}  ({report['date']}; {report['machine'].get('cpu', '?')}, "
             f"{report['machine'].get('cpus')} cpus{'; ' + report['machine']['gl_renderer'] if 'gl_renderer' in report['machine'] else ''})", ""]
    tpl = report.get("templates", {})
    if tpl:
        lines.append(f"{'template':<18} {'frames':>6} {'mean':>7} {'p50':>7} {'p95':>7} {'p99':>7} {'max':>7} {'cpu p95':>8} {'>16.7':>6} {'startup':>8}")
        for tid, r in tpl.items():
            if not r.get("passed"):
                lines.append(f"{tid:<18} FAILED: {r['failures'][0][:80]}")
                continue
            f = r["frame_ms"]
            lines.append(f"{tid:<18} {r['frames']:>6} {f['mean']:>7.2f} {f['p50']:>7.2f} {f['p95']:>7.2f} {f['p99']:>7.2f} {f['max']:>7.2f} "
                         f"{r['cpu_ms']['p95']:>8.2f} {r['over_budget_pct']:>5.1f}% {r['startup_ms']['first_frame']:>7.0f}")
        lines.append("  (ms; frame = frame to frame, uncapped; >16.7: frames over a 60 fps frame; startup: process start to the first frame)")
        lines.append("")
    ed = report.get("editor")
    if ed:
        lines.append(f"{'editor':<24} {'frames':>6} {'mean':>7} {'p95':>7} {'p99':>7} {'max':>7} {'ui':>6} {'viewport':>8} {'present':>7}")
        for k, v in ed["benches"].items():
            if "value" in v:
                lines.append(f"{k:<24} {'':>6} {v['value'] if v['value'] is not None else 'n/a':>7} ms")
                continue
            f, p = v["frame_ms"], v["phases_ms"]
            lines.append(f"{k:<24} {v['frames']:>6} {f['mean']:>7.2f} {f['p95']:>7.2f} {f['p99']:>7.2f} {f['max']:>7.2f} {p['ui']:>6.2f} {p['viewport']:>8.2f} {p['present']:>7.2f}")
        if not ed["passed"]:
            lines.append("  the drive FAILED: " + "; ".join(ed.get("failures") or ["did not finish"]))
        lines.append("")
    if baseline is not None:
        problems, rows = check(report, baseline)
        lines.append(f"{'metric':<44} {'value':>9} {'target':>8} {'baseline':>9}  status")
        for name, value, t, b, status in rows:
            lines.append(f"{name:<44} {value:>9.2f} {t if t is not None else '-':>8} {b if b is not None else '-':>9}  {status}")
        lines.append("")
        rec = baseline.get("recorded", {}).get(report["setup"], {}).get("machine", {}).get("cpu")
        if report["setup"] not in baseline.get("setups", {}):
            lines.append(f"(no baseline recorded for {report['setup']}: the targets only - --update-baseline records one)")
        elif rec and rec != report["machine"].get("cpu"):
            lines.append(f"(the {report['setup']} baseline was recorded on {rec}; this run's CPU differs: the targets only)")
        lines.append("PASS: every target met, no regression" if not problems else f"{len(problems)} problem(s):")
        lines += [f"  {p}" for p in problems]
    return "\n".join(lines)


def update_baseline(report, path):
    baseline = json.load(open(path))
    m = metrics(report)
    baseline.setdefault("setups", {})[report["setup"]] = {k: m[k] for k in sorted(m)}
    baseline.setdefault("recorded", {})[report["setup"]] = {"date": report["date"], "machine": report["machine"]}
    with open(path, "w") as f:
        json.dump(baseline, f, indent=2)
        f.write("\n")
    print(f"{path}: {report['setup']} baseline = {len(m)} numbers from {report['date']}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0], formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--runner", help="the desktop runner (default: bin/runners/<platform>/runner)")
    ap.add_argument("--android", action="store_true", help="play the templates on a device / emulator (adb)")
    ap.add_argument("--android-runner", default=os.path.join(ROOT, "bin", "runners", "android-test", "libmain.so"))
    ap.add_argument("--editor", help="also run the editor drive with this editor (desktop)")
    ap.add_argument("--no-templates", action="store_true", help="only the editor")
    ap.add_argument("--reps", type=int, default=3, help="runs per template (median; default 3)")
    ap.add_argument("--setup", default="local", help="the reference setup's name (a key of the baseline)")
    ap.add_argument("--out", help="write the JSON report here")
    ap.add_argument("--baseline", default=BASELINE)
    ap.add_argument("--check", metavar="REPORT", help="check a report against the targets and the baseline")
    ap.add_argument("--report-only", action="store_true",
                    help="with --check: report misses (a ::warning:: annotation each on GitHub Actions) but exit 0 - pull requests")
    ap.add_argument("--table", metavar="REPORT", help="print a report's table")
    ap.add_argument("--update-baseline", metavar="REPORT", help="record a report as its setup's baseline")
    ap.add_argument("templates", nargs="*")
    a = ap.parse_args()

    if a.update_baseline:
        update_baseline(json.load(open(a.update_baseline)), a.baseline)
        return
    if a.table or a.check:
        report = json.load(open(a.table or a.check))
        baseline = json.load(open(a.baseline))
        print(table(report, baseline))
        if a.check:
            problems = check(report, baseline)[0]
            if a.report_only:
                for p in problems:
                    print(f"::warning title=Performance::{p}" if os.environ.get("GITHUB_ACTIONS") else f"warning: {p}")
                return
            sys.exit(1 if problems else 0)
        return

    log = lambda s: print(s, flush=True)  # noqa: E731
    runner = os.path.abspath(a.runner) if a.runner else test_templates.default_runner()
    report = {"setup": a.setup, "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
              "machine": machine()}
    if a.android:
        report["machine"]["device"] = "android (adb)"
    if not a.no_templates:
        backend = test_templates.Android(os.path.abspath(a.android_runner)) if a.android else test_templates.Desktop(runner)
        try:
            report["templates"] = run_templates(backend, a.templates, max(a.reps, 1), log)
        finally:
            backend.close()
    if a.editor:
        report["editor"] = run_editor(a.editor, runner, log)
    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        with open(a.out, "w") as f:
            json.dump(report, f, indent=2)
            f.write("\n")
    baseline = json.load(open(a.baseline)) if os.path.isfile(a.baseline) else None
    print()
    print(table(report, baseline))
    failed = any(not r.get("passed") for r in report.get("templates", {}).values()) or \
        (report.get("editor") is not None and not report["editor"]["passed"])
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
