package engine

import "core:math"
import "core:math/linalg"
import "core:testing"

// #267 part 3: curve fitting stays within its error with few segments, a
// brush outline covers its stroke, and the bucket finds closed-in gaps.
@(test)
test_vector_freehand :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	// 200 samples on a half circle of radius 100.
	pts := make([][2]f32, 200)
	for i in 0 ..< 200 {
		a := math.PI * f32(i) / 199
		pts[i] = {math.cos(a) * 100, math.sin(a) * 100}
	}
	path: Vector_Path
	Vector_Path_Init(&path)
	Vector_FitCurve(pts, 0.5, &path)
	cubics := 0
	for c in path.cmds do if c == .Cubic do cubics += 1
	testing.expectf(t, cubics >= 1 && cubics <= 6, "a half circle in a few cubics: %d", cubics)
	// Every sample is near the fitted curve.
	worst: f32
	for q in pts {
		_, _, d := Vector_SegmentNearest(&path, q)
		worst = max(worst, d)
	}
	testing.expectf(t, worst < 1.5, "within the error: %.2f", worst)
	loose: Vector_Path
	Vector_Path_Init(&loose)
	Vector_FitCurve(pts, 8, &loose)
	testing.expect(t, len(loose.cmds) <= len(path.cmds), "a bigger error: no more segments")

	// A brush stroke along a line, 20 wide: closed, covering its middle, not far off it.
	line := [][2]f32{{0, 0}, {50, 0}, {100, 0}, {150, 0}}
	widths := []f32{20, 20, 20, 20}
	shape: Vector_Shape
	Vector_Path_Init(&shape.path)
	Vector_BrushOutline(line, widths, 0.5, &shape.path)
	testing.expect(t, shape.path.cmds[len(shape.path.cmds) - 1] == .Close, "closed")
	shape.style.fill = true
	area: Vector_Polys
	testing.expect(t, Vector_FillArea(&shape, 0.25, &area), "its area")
	testing.expect(t, Vector_PolysContains(&area, {75, 0}) && Vector_PolysContains(&area, {75, 8}) && !Vector_PolysContains(&area, {75, 15}), "about 20 wide")

	// Four strokes making a square (not one closed path): the bucket fills inside.
	sq := [][2][2]f32{{{0, 0}, {100, 0}}, {{100, -5}, {100, 105}}, {{105, 100}, {-5, 100}}, {{0, 105}, {0, -5}}}
	shapes := make([dynamic]Vector_Shape)
	for s in sq {
		sh: Vector_Shape
		Vector_Path_Init(&sh.path)
		Vector_MoveTo(&sh.path, s[0])
		Vector_LineTo(&sh.path, s[1])
		sh.style = Vector_Style{stroke = true, strokeColor = {0, 0, 0, 255}, strokeWidth = 4, miterLimit = 4, opacity = 1}
		append(&shapes, sh)
	}
	gap: Vector_Path
	Vector_Path_Init(&gap)
	testing.expect(t, Vector_EnclosedArea(shapes[:], {50, 50}, 0.25, &gap), "the inside is closed in")
	gs := []Vector_Shape{{path = gap}}
	b := Vector_ShapesBounds(gs, false)
	testing.expectf(t, abs(b[0] - 2) < 1 && abs(b[2] - 98) < 1 && abs(b[1] - 2) < 1 && abs(b[3] - 98) < 1, "the gap inside the lines: %v", b)
	nothing: Vector_Path
	Vector_Path_Init(&nothing)
	testing.expect(t, !Vector_EnclosedArea(shapes[:], {150, 50}, 0.25, &nothing), "outside: open")
	testing.expect(t, !Vector_EnclosedArea(shapes[:], {0, 50}, 0.25, &nothing), "on a line: nothing")
	_ = linalg.PI
}
