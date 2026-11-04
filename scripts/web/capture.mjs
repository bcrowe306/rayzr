// Captures a web export in headless Chrome: its console (logs, errors,
// exceptions) and a screenshot - for testing the web runner without a
// person at a browser. Uses the DevTools protocol over Node's WebSocket.
//
//   node scripts/web/capture.mjs URL OUT.png [seconds] [--click] [--touches=steps.json]
//
// --click clicks the page centre once loaded (the start screen), else add
// ?autostart to the URL. --touches plays real touch events (a touch screen
// emulated): a JSON list of {"at": seconds after load, "type":
// "touchStart" | "touchMove" | "touchEnd", "points": [{"x", "y", "id"}]}
// (page pixels; touchEnd lists the fingers still down).
import { spawn } from "node:child_process";
import { writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const [url, out, secondsArg] = process.argv.slice(2);
const seconds = Number(secondsArg || 12);
const click = process.argv.includes("--click");
const touchArg = process.argv.find((a) => a.startsWith("--touches="));
const touches = touchArg ? JSON.parse((await import("node:fs")).readFileSync(touchArg.slice(10), "utf8")) : null;
const chrome = process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const port = 9300 + Math.floor(Math.random() * 500);
const profile = mkdtempSync(join(tmpdir(), "rayzr_chrome_"));
const proc = spawn(chrome, ["--headless=new", `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--window-size=1280,720", "--autoplay-policy=no-user-gesture-required", "about:blank"],
  { stdio: "ignore" });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws, nextId = 1;
const pending = new Map();
const send = (method, params = {}) => new Promise((ok) => { const id = nextId++; pending.set(id, ok); ws.send(JSON.stringify({ id, method, params })); });

try {
  let target;
  for (let i = 0; i < 150 && !target; i++) { // (up to 30 s: a cold first start on a fresh CI image is slow)
    await sleep(200);
    try { target = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find((t) => t.type === "page"); } catch {}
  }
  if (!target) throw new Error("Chrome didn't start");
  ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((ok) => ws.addEventListener("open", ok));
  ws.addEventListener("message", (ev) => {
    const m = JSON.parse(ev.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); return; }
    if (m.method === "Runtime.consoleAPICalled") console.log(`[${m.params.type}]`, m.params.args.map((a) => a.value ?? a.description ?? "").join(" "));
    if (m.method === "Runtime.exceptionThrown") console.log("[exception]", m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text);
    if (m.method === "Log.entryAdded") console.log(`[${m.params.entry.level}]`, m.params.entry.text, m.params.entry.url || "");
  });
  await send("Runtime.enable");
  await send("Log.enable");
  await send("Page.enable");
  if (touches) await send("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 5 });
  await send("Page.navigate", { url });
  if (click) {
    await sleep(3000);
    for (const type of ["mousePressed", "mouseReleased"]) await send("Input.dispatchMouseEvent", { type, x: 640, y: 360, button: "left", clickCount: 1 });
  }
  if (touches) {
    // (From load: wait for each step's time, then send it.)
    const t0 = Date.now();
    for (const step of touches) {
      const wait = step.at * 1000 - (Date.now() - t0);
      if (wait > 0) await sleep(wait);
      await send("Input.dispatchTouchEvent", { type: step.type, touchPoints: step.points.map((p) => ({ x: p.x, y: p.y, id: p.id ?? 0 })) });
    }
    const rest = seconds * 1000 - (Date.now() - t0);
    if (rest > 0) await sleep(rest);
  } else {
    await sleep(seconds * 1000);
  }
  // The page's state (the shell's flags) - why a capture is blank.
  const probe = await send("Runtime.evaluate", { expression: "JSON.stringify({ready: typeof ready != 'undefined' && ready, started: typeof started != 'undefined' && started, status: document.getElementById('status')?.textContent || null})", returnByValue: true });
  console.log("[page]", probe?.result?.value);
  const shot = await send("Page.captureScreenshot", { format: "png" });
  writeFileSync(out, Buffer.from(shot.data, "base64"));
  console.log("screenshot:", out);
} catch (err) {
  console.log("[capture failed]", err.message);
  process.exitCode = 1;
} finally {
  try { ws?.close(); } catch {}
  proc.kill();
}
