package editor

import "core:fmt"
import "core:time"
import rl "vendor:raylib"
import e "../engine"

// ============================================================================
// Editor frame timing: where each frame's time goes, by phase.
//
//   Poll      file watchers, playtest output, hot reloads (before the UI)
//   UI        building the ImGui frame (panels, inspector, dialogs) minus the viewport
//   Viewport  the scene: Simulate's update and its render into the viewport texture
//   Draw      submitting ImGui's draw lists to raylib
//   Present   EndDrawing: the buffer swap, waiting for the GPU (and vsync / the FPS cap)
//
// The Profiler tab shows them (smoothed); the drive command `bench <frames>
// [label]` times that many uncapped frames and prints a [bench] line (and a
// [bench-json] one: percentiles, for scripts/perf/perf.py - #331);
// `bench-start [label]` .. `bench-stop` time the frames of the commands
// between them (a drag, clicks).
// `--uncapped` runs the editor without vsync or a frame cap.
// ============================================================================

Frame_Phase :: enum {
	Poll,
	UI,
	Viewport,
	Draw,
	Present,
}

FRAME_PHASE_NAMES := [Frame_Phase]string {
	.Poll     = "poll",
	.UI       = "ui",
	.Viewport = "viewport",
	.Draw     = "draw",
	.Present  = "present",
}

Frame_Timing :: struct {
	frameStart: time.Tick,
	mark:       time.Tick,
	viewport:   time.Duration,      // this frame's viewport (inside UI)
	last:       [Frame_Phase]f64,   // ms, the last frame
	smooth:     [Frame_Phase]f64,   // ms, averaged (Profiler)
	uncapped:   bool,               // --uncapped, or a drive's bench running
	// A drive's `bench`: frames left to time, and the sums.
	benchLeft:  int,
	benchFrames: int,
	benchSum:   [Frame_Phase]f64,
	benchWhole: f64,
	benchAllocs, benchTempBytes: int, // (profiling builds)
	benchSamples: [dynamic]f32,       // ms, each timed frame (percentiles)
	firstFrameMs: f64,                // process start to the end of the first frame (startup)
	frameIndex:   u64,                // frames begun
}

frameTiming: Frame_Timing

// FrameTiming_Begin starts a frame (top of the main loop).
FrameTiming_Begin :: proc() {
	ft := &frameTiming
	ft.frameStart = time.tick_now()
	ft.mark = ft.frameStart
	ft.frameIndex += 1
	ft.viewport = 0
	e.Prof_Begin("editor.frame")
	e.Prof_Begin("editor.poll")
	// (Loading a project applies its game's target FPS: undone every frame.)
	if ft.uncapped do rl.SetTargetFPS(0)
}

// FrameTiming_FrameIndex: the editor's frame number (caches valid for a frame).
FrameTiming_FrameIndex :: proc() -> u64 {return frameTiming.frameIndex}

// FrameTiming_Mark ends `phase` (the time since the previous mark).
FrameTiming_Mark :: proc(phase: Frame_Phase) {
	ft := &frameTiming
	now := time.tick_now()
	d := time.tick_diff(ft.mark, now)
	if phase == .UI do d -= ft.viewport
	ft.last[phase] = time.duration_milliseconds(d)
	ft.mark = now
	// The matching zones: each phase ends here and the next one begins.
	e.Prof_End()
	switch phase {
	case .Poll:     e.Prof_Begin("editor.ui")
	case .UI:       e.Prof_Begin("editor.draw")
	case .Draw:     e.Prof_Begin("editor.present")
	case .Viewport, .Present:
	}
}

// FrameTiming_Viewport records the viewport's share of the UI phase.
FrameTiming_Viewport :: proc(start: time.Tick) {
	ft := &frameTiming
	ft.viewport = time.tick_since(start)
	ft.last[.Viewport] = time.duration_milliseconds(ft.viewport)
}

// FrameTiming_End closes the frame (after EndDrawing).
FrameTiming_End :: proc() {
	ft := &frameTiming
	FrameTiming_Mark(.Present)
	e.Prof_End() // editor.frame
	e.Prof_FrameEnd()
	for p in Frame_Phase do ft.smooth[p] += (ft.last[p] - ft.smooth[p]) * 0.05
	if ft.firstFrameMs == 0 do ft.firstFrameMs = e.Process_SinceStartMs()
	if ft.benchLeft > 0 {
		for p in Frame_Phase do ft.benchSum[p] += ft.last[p]
		whole := time.duration_milliseconds(time.tick_since(ft.frameStart))
		ft.benchWhole += whole
		append(&ft.benchSamples, f32(whole))
		ft.benchAllocs += e.Prof_Last().allocs
		ft.benchTempBytes += e.Prof_Last().tempBytes
		ft.benchFrames += 1
		ft.benchLeft -= 1
	}
}

// FrameTiming_SetUncapped turns vsync and the frame cap off (or back on:
// 60 FPS, vsync unless driving).
FrameTiming_SetUncapped :: proc(on: bool, vsync: bool) {
	frameTiming.uncapped = on
	if on {
		rl.ClearWindowState({.VSYNC_HINT})
		rl.SetTargetFPS(0)
	} else {
		if vsync do rl.SetWindowState({.VSYNC_HINT})
		rl.SetTargetFPS(60)
	}
}

// FrameTiming_BenchStart / FrameTiming_BenchDone: a drive's `bench`.
FrameTiming_BenchStart :: proc(frames: int) {
	ft := &frameTiming
	ft.benchLeft = frames
	ft.benchFrames = 0
	ft.benchSum = {}
	ft.benchWhole = 0
	ft.benchAllocs = 0
	ft.benchTempBytes = 0
	clear(&ft.benchSamples)
}

// FrameTiming_BenchStop ends an open-ended bench (bench-start) now.
FrameTiming_BenchStop :: proc() {
	frameTiming.benchLeft = 0
}

// FrameTiming_Benching: a drive is timing frames (its own bookkeeping can skip work then).
FrameTiming_Benching :: proc() -> bool {return frameTiming.benchLeft > 0}

FrameTiming_BenchDone :: proc() -> bool {
	return frameTiming.benchLeft <= 0
}

// FrameTiming_BenchReport: the [bench] line for the frames just timed.
FrameTiming_BenchReport :: proc(label: string) -> string {
	ft := &frameTiming
	n := f64(max(ft.benchFrames, 1))
	whole := ft.benchWhole / n
	allocs := ""
	when e.RAYZR_PROF do allocs = fmt.tprintf(" | %.1f heap allocs, temp %.0f KB", f64(ft.benchAllocs) / n, f64(ft.benchTempBytes) / n / 1024)
	s := e.Perf_Summarize(ft.benchSamples[:])
	return fmt.tprintf("[bench] editor %-22s %d frames: whole frame %.3f ms (%.0f fps; p95 %.2f, p99 %.2f, max %.2f) | poll %.3f | ui %.3f | viewport %.3f | draw %.3f | present %.3f%s",
		label, ft.benchFrames, whole, 1000 / whole, s.p95, s.p99, s.max, ft.benchSum[.Poll] / n, ft.benchSum[.UI] / n, ft.benchSum[.Viewport] / n, ft.benchSum[.Draw] / n, ft.benchSum[.Present] / n, allocs)
}

// FrameTiming_BenchJSON: the frames just timed as a [bench-json] line -
// {"label", "frames", "frame_ms": {mean, p50, p95, p99, max}, "over_budget", "phases_ms": {...}}.
FrameTiming_BenchJSON :: proc(label: string) -> string {
	ft := &frameTiming
	n := f64(max(ft.benchFrames, 1))
	return fmt.tprintf("[bench-json] {{\"label\": %q, \"frames\": %d, \"frame_ms\": %s, \"over_budget\": %d, \"phases_ms\": {{\"poll\": %.3f, \"ui\": %.3f, \"viewport\": %.3f, \"draw\": %.3f, \"present\": %.3f}}}}",
		label, ft.benchFrames, e.Perf_SummaryJSON(e.Perf_Summarize(ft.benchSamples[:])), e.Perf_OverBudget(ft.benchSamples[:]),
		ft.benchSum[.Poll] / n, ft.benchSum[.UI] / n, ft.benchSum[.Viewport] / n, ft.benchSum[.Draw] / n, ft.benchSum[.Present] / n)
}
