package engine

import "core:fmt"
import "core:slice"
import "core:strings"
import "core:time"
import os "osx"

// ============================================================================
// Performance reports (#331, scripts/perf/perf.py): frame-time samples
// summarised as mean / percentiles / max, and the runner's --perf-report
// <file.json> - every frame's time and the startup times of one run, written
// when the run ends (the game quitting too).
//
//   {"frames": N, "frame_ms": {mean, p50, p95, p99, max},   (frame to frame: all of it)
//    "cpu_ms": {...},                                        (update + draw, before the buffer swap)
//    "over_budget": n,                                       (frames over 1/60 s: 16.7 ms)
//    "startup_ms": {"window", "project", "first_frame"}}    (from process start)
// ============================================================================

// Process_StartTick: when the process started (as near as Odin's init gets).
Process_StartTick: time.Tick

@(init, private = "file")
perf_init_start_tick :: proc "contextless" () {
	Process_StartTick = time.tick_now()
}

// Process_SinceStartMs: milliseconds since the process started.
Process_SinceStartMs :: proc() -> f64 {
	return time.duration_milliseconds(time.tick_since(Process_StartTick))
}

Perf_Summary :: struct {
	count: int,
	mean, p50, p95, p99, max: f64,
}

// PERF_FRAME_BUDGET_MS: one frame at 60 fps.
PERF_FRAME_BUDGET_MS :: 1000.0 / 60.0

// Perf_Summarize: mean, nearest-rank percentiles and max of `samples` (ms).
Perf_Summarize :: proc(samples: []f32) -> (s: Perf_Summary) {
	s.count = len(samples)
	if s.count == 0 do return
	sorted := slice.clone(samples, context.temp_allocator)
	slice.sort(sorted)
	sum: f64
	for v in sorted do sum += f64(v)
	s.mean = sum / f64(s.count)
	rank :: proc(sorted: []f32, p: f64) -> f64 {
		// Nearest rank: the smallest sample with at least p of them at or below it.
		i := int(p * f64(len(sorted)) + 0.999999) - 1
		return f64(sorted[clamp(i, 0, len(sorted) - 1)])
	}
	s.p50 = rank(sorted, 0.50)
	s.p95 = rank(sorted, 0.95)
	s.p99 = rank(sorted, 0.99)
	s.max = f64(sorted[s.count - 1])
	return
}

// Perf_OverBudget: samples longer than a 60 fps frame.
Perf_OverBudget :: proc(samples: []f32) -> int {
	n := 0
	for v in samples do if f64(v) > PERF_FRAME_BUDGET_MS do n += 1
	return n
}

// Perf_SummaryJSON: {"mean": .., "p50": .., "p95": .., "p99": .., "max": ..}.
Perf_SummaryJSON :: proc(s: Perf_Summary, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("{{\"mean\": %.3f, \"p50\": %.3f, \"p95\": %.3f, \"p99\": %.3f, \"max\": %.3f}}", s.mean, s.p50, s.p95, s.p99, s.max, allocator = allocator)
}

// Perf_Recorder: one run's samples (the runner's --perf-report).
Perf_Recorder :: struct {
	path:       string,
	frame:      [dynamic]f32, // ms, frame end to frame end
	cpu:        [dynamic]f32, // ms, update + draw
	lastEnd:    time.Tick,
	windowMs, projectMs, firstFrameMs: f64,
}

// Perf_RecordFrame: a frame ended (cpu: its update + draw time).
Perf_RecordFrame :: proc(r: ^Perf_Recorder, cpu: time.Duration) {
	now := time.tick_now()
	if r.firstFrameMs == 0 {
		r.firstFrameMs = Process_SinceStartMs()
	} else {
		append(&r.frame, f32(time.duration_milliseconds(time.tick_diff(r.lastEnd, now))))
		append(&r.cpu, f32(time.duration_milliseconds(cpu)))
	}
	r.lastEnd = now
}

// Perf_ReportJSON: the report (above).
Perf_ReportJSON :: proc(r: ^Perf_Recorder, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make(allocator)
	fmt.sbprintf(&sb, "{{\"frames\": %d, \"frame_ms\": %s, \"cpu_ms\": %s, \"over_budget\": %d, ",
		len(r.frame), Perf_SummaryJSON(Perf_Summarize(r.frame[:])), Perf_SummaryJSON(Perf_Summarize(r.cpu[:])), Perf_OverBudget(r.frame[:]))
	fmt.sbprintf(&sb, "\"startup_ms\": {{\"window\": %.1f, \"project\": %.1f, \"first_frame\": %.1f}}}}\n", r.windowMs, r.projectMs, r.firstFrameMs)
	return strings.to_string(sb)
}

// Perf_WriteReport writes the report to r.path (when set) and frees the samples.
Perf_WriteReport :: proc(r: ^Perf_Recorder) {
	if r.path != "" {
		text := Perf_ReportJSON(r)
		if err := os.write_entire_file(r.path, transmute([]u8)text); err != nil {
			fmt.eprintfln("--perf-report %s: %v", r.path, err)
		}
	}
	delete(r.frame)
	delete(r.cpu)
	r^ = {}
}
