package engine

import "core:encoding/json"
import "core:testing"
import "core:time"

// #331: the frame-time summary (nearest-rank percentiles) and the runner's
// --perf-report JSON.
@(test)
test_perf_summarize :: proc(t: ^testing.T) {
	samples := make([]f32, 100)
	defer delete(samples)
	for i in 0 ..< 100 do samples[i] = f32(100 - i) // 100 .. 1, unsorted
	s := Perf_Summarize(samples)
	testing.expect_value(t, s.count, 100)
	testing.expect_value(t, s.p50, 50)
	testing.expect_value(t, s.p95, 95)
	testing.expect_value(t, s.p99, 99)
	testing.expect_value(t, s.max, 100)
	testing.expect(t, abs(s.mean - 50.5) < 1e-9, "mean")
	testing.expect_value(t, samples[0], 100) // (the samples aren't reordered)
	one := Perf_Summarize({7})
	testing.expect(t, one.p50 == 7 && one.p99 == 7 && one.max == 7, "one sample")
	testing.expect_value(t, Perf_Summarize(nil).count, 0)
	testing.expect_value(t, Perf_OverBudget({10, 16.6, 16.8, 40}), 2)
	free_all(context.temp_allocator)
}

@(test)
test_perf_report_json :: proc(t: ^testing.T) {
	r: Perf_Recorder
	for i in 0 ..< 5 do Perf_RecordFrame(&r, time.Millisecond)
	r.windowMs, r.projectMs = 100, 200
	testing.expect_value(t, len(r.frame), 4) // (the first frame ends the startup)
	testing.expect(t, r.firstFrameMs > 0, "first frame time")
	v, err := json.parse(transmute([]u8)Perf_ReportJSON(&r), allocator = context.temp_allocator)
	testing.expect_value(t, err, json.Error.None)
	obj := v.(json.Object)
	testing.expect_value(t, obj["frames"].(json.Float), 4) // (core:encoding/json reads numbers as floats)
	cpu := obj["cpu_ms"].(json.Object)
	testing.expect(t, abs(cpu["p95"].(json.Float) - 1) < 1e-6, "cpu p95 1 ms")
	testing.expect_value(t, obj["startup_ms"].(json.Object)["project"].(json.Float), 200)
	Perf_WriteReport(&r) // (no path: frees the samples only)
	testing.expect_value(t, len(r.frame), 0)
	free_all(context.temp_allocator)
}
