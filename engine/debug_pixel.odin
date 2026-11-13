package engine

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// Debug_PixelSize: how many world units one screen pixel is in the space
// being drawn now (the camera's zoom, or the editor view's). Gizmos that
// should keep their size on screen at any zoom - a raycast's end dots, a
// joint's anchors, line widths - multiply their sizes by it.
Debug_PixelSize :: proc() -> f32 {
	m := rlgl.GetMatrixModelview()
	s := math.sqrt(m[0, 0] * m[0, 0] + m[1, 0] * m[1, 0])
	if s < 0.0001 do return 1
	return 1 / s
}

// Debug_CircleSegments: enough segments for a circle of world radius r to
// look round on screen (raylib picks them from r alone: jagged zoomed in).
Debug_CircleSegments :: proc(r: f32) -> i32 {
	screenR := r / Debug_PixelSize()
	return i32(clamp(screenR * 0.75, 16, 256))
}

// Debug_Circle / Debug_CircleLines: a filled circle / its outline, round at
// any zoom (the outline 1 screen pixel wide).
Debug_Circle :: proc(c: [2]f32, r: f32, col: rl.Color) {
	rl.DrawCircleSector(c, r, 0, 360, Debug_CircleSegments(r), col)
}

Debug_CircleLines :: proc(c: [2]f32, r: f32, col: rl.Color) {
	px := Debug_PixelSize()
	rl.DrawRing(c, max(r - px * 0.5, 0), r + px * 0.5, 0, 360, Debug_CircleSegments(r), col)
}
