// Plays a web export in headless Chrome the way the desktop runner plays a
// game test: the page's ?test mode (scripts/web/shell.html) runs the game
// with runner arguments and reports when it's over. Used by
// scripts/templates/test_templates.py --web; DevTools protocol over Node's
// WebSocket (Node 22+), no packages.
//
//   node scripts/web/run_test.mjs spec.json result.json
//
// spec: {"url": "http://127.0.0.1:PORT/index.html?test", "timeout": seconds a run,
//        "runs": [{"args": ["--frames", "60", ...],             // the runner's arguments
//                  "files": {"/test/input.txt": "text"},          // written first (text)
//                  "clear_save": true,                            // empty /save (IndexedDB) first
//                  "save_files": {"slot_1.json": "text"},         // then put these in /save
//                  "dump": "/test/dump.json", "shot": "/test/shot.png"}]}
// result: {"runs": [{"ended": bool, "dump": text | null, "shot": base64 | null,
//                    "save": {"rel/path": text}, "log": [lines]}], "error": text | null}
// Each run is a fresh page load (the saves come back from IndexedDB, as
// they do when a player opens the game again).
import { spawn } from "node:child_process";
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const [specPath, outPath] = process.argv.slice(2);
const spec = JSON.parse(readFileSync(specPath, "utf8"));
const chrome = process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const port = 9300 + Math.floor(Math.random() * 500);
const profile = mkdtempSync(join(tmpdir(), "rayzr_chrome_"));
const proc = spawn(chrome, ["--headless=new", `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--window-size=1280,720",
  "--autoplay-policy=no-user-gesture-required", "--disable-background-timer-throttling",
  "--disable-renderer-backgrounding", "--disable-backgrounding-occluded-windows", "about:blank"], { stdio: "ignore" });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws, nextId = 1, log = [];
const pending = new Map();
const send = (method, params = {}) => new Promise((ok) => { const id = nextId++; pending.set(id, ok); ws.send(JSON.stringify({ id, method, params })); });
// evaluate: an expression's value (awaited when it's a promise); throws on a page exception.
const evaluate = async (expression) => {
  const r = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
  if (r?.exceptionDetails) throw new Error(`${expression.slice(0, 60)}...: ${r.exceptionDetails.exception?.description || r.exceptionDetails.text}`);
  return r?.result?.value;
};
const waitFor = async (expression, seconds) => {
  const t0 = Date.now();
  while (Date.now() - t0 < seconds * 1000) {
    if (await evaluate(expression)) return true;
    await sleep(100);
  }
  return false;
};

// (Page-side helpers: /save emptied, written and read back, recursively.)
const PAGE_HELPERS = `
window.rayzrRm = (dir) => { for (const n of FS.readdir(dir)) { if (n === "." || n === "..") continue;
  const p = dir + "/" + n; if (FS.isDir(FS.stat(p).mode)) { rayzrRm(p); FS.rmdir(p); } else FS.unlink(p); } };
window.rayzrRead = (dir, rel, out) => { for (const n of FS.readdir(dir)) { if (n === "." || n === "..") continue;
  const p = dir + "/" + n, r = rel ? rel + "/" + n : n;
  if (FS.isDir(FS.stat(p).mode)) rayzrRead(p, r, out); else out[r] = FS.readFile(p, { encoding: "utf8" }); } return out; };
window.rayzrWrite = (path, text) => { const parts = path.split("/").slice(1, -1); let d = "";
  for (const s of parts) { d += "/" + s; try { FS.mkdir(d); } catch (e) {} } FS.writeFile(path, text); };
window.rayzrSync = () => new Promise((ok) => FS.syncfs(false, () => ok(true)));
true`;

const result = { runs: [], error: null };
try {
  let target;
  for (let i = 0; i < 150 && !target; i++) { // (up to 30 s: a cold first start on a fresh CI image is slow)
    await sleep(200);
    try { target = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find((t) => t.type === "page"); } catch {}
  }
  if (!target) throw new Error("Chrome didn't start (set CHROME to its path)");
  ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((ok) => ws.addEventListener("open", ok));
  ws.addEventListener("message", (ev) => {
    const m = JSON.parse(ev.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result ?? { exceptionDetails: m.error && { text: m.error.message } }); pending.delete(m.id); return; }
    if (m.method === "Runtime.consoleAPICalled") log.push(`[${m.params.type}] ` + m.params.args.map((a) => a.value ?? a.description ?? "").join(" "));
    if (m.method === "Runtime.exceptionThrown") log.push("[exception] " + (m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text));
  });
  await send("Runtime.enable");
  await send("Page.enable");
  for (const run of spec.runs) {
    log = [];
    await send("Page.navigate", { url: spec.url });
    if (!(await waitFor("typeof ready != 'undefined' && ready === true", 30))) throw new Error("the page didn't load the game (ready never turned true)");
    await evaluate(PAGE_HELPERS);
    if (run.clear_save) await evaluate(`rayzrRm("/save"); rayzrSync()`);
    for (const [rel, text] of Object.entries(run.save_files || {})) await evaluate(`rayzrWrite(${JSON.stringify("/save/" + rel)}, ${JSON.stringify(text)})`);
    for (const [path, text] of Object.entries(run.files || {})) await evaluate(`rayzrWrite(${JSON.stringify(path)}, ${JSON.stringify(text)})`);
    await evaluate(`rayzrTest(${JSON.stringify(run.args)}); true`);
    const ended = await waitFor("ended === true", spec.timeout || 120);
    const out = { ended, dump: null, shot: null, save: {}, log: [] };
    if (run.dump) out.dump = await evaluate(`FS.analyzePath(${JSON.stringify(run.dump)}).exists ? FS.readFile(${JSON.stringify(run.dump)}, { encoding: "utf8" }) : null`);
    if (run.shot) out.shot = await evaluate(`(() => { const p = ${JSON.stringify(run.shot)}; if (!FS.analyzePath(p).exists) return null;
      const d = FS.readFile(p); let s = ""; for (let i = 0; i < d.length; i++) s += String.fromCharCode(d[i]); return btoa(s); })()`);
    out.save = await evaluate(`rayzrRead("/save", "", {})`);
    out.log = log;
    result.runs.push(out);
    if (!ended) break;
  }
} catch (err) {
  result.error = err.message;
} finally {
  try { ws?.close(); } catch {}
  proc.kill();
  await sleep(300);
  try { rmSync(profile, { recursive: true, force: true }); } catch {}
  writeFileSync(outPath, JSON.stringify(result));
}
