package engine

import "core:math"
import "core:math/linalg"

// ============================================================================
// Freehand drawing (#267 part 3): what the editor's Pencil, Brush and Paint
// Bucket make.
//
// - Vector_FitCurve: a polyline (mouse samples) as a few cubic Béziers within
//   an error (Philip Schneider's algorithm, Graphics Gems 1990): fewer,
//   smoother curves as the error grows - the toolbar's smoothing.
// - Vector_BrushOutline: a brush stroke as a filled outline whose width
//   follows the samples' widths (the editor makes them from the drawing
//   speed: Flash's brush feel), with round ends, curve-fitted.
// - Vector_EnclosedArea: the region around a point that lines and fills
//   close in (a gap the Paint Bucket fills).
// ============================================================================

// Vector_FitCurve appends `pts` fitted to cubics within `err` (path units)
// to `out` (a Move first). Fewer than two points: nothing.
Vector_FitCurve :: proc(pts: [][2]f32, err: f32, out: ^Vector_Path) {
	clean := make([dynamic][2]f32, 0, len(pts), context.temp_allocator)
	for q in pts do if len(clean) == 0 || linalg.distance(clean[len(clean) - 1], q) > 1e-4 do append(&clean, q)
	if len(clean) < 2 do return
	Vector_MoveTo(out, clean[0])
	if len(clean) == 2 {
		Vector_LineTo(out, clean[1])
		return
	}
	t1 := fit_tangent(clean[:], 0, true)
	t2 := fit_tangent(clean[:], len(clean) - 1, false)
	fit_cubic(clean[:], t1, t2, max(err, 1e-3), out, 0)
}

@(private = "file")
fit_tangent :: proc(pts: [][2]f32, i: int, start: bool) -> [2]f32 {
	// (A few points in, not the next one: steadier for jittery input.)
	n := len(pts)
	j := min(i + 3, n - 1) if start else max(i - 3, 0)
	d := pts[j] - pts[i]
	if linalg.length(d) < 1e-6 do d = pts[i + 1] - pts[i] if start else pts[i - 1] - pts[i]
	return linalg.normalize0(d)
}

@(private = "file")
fit_cubic :: proc(pts: [][2]f32, t1, t2: [2]f32, err: f32, out: ^Vector_Path, depth: int) {
	n := len(pts)
	if n == 2 {
		d := linalg.distance(pts[0], pts[1]) / 3
		Vector_CubicTo(out, pts[0] + t1 * d, pts[1] + t2 * d, pts[1])
		return
	}
	u := chord_params(pts)
	bez := generate_bezier(pts, u, t1, t2)
	maxErr, split := max_error(pts, bez, u)
	if maxErr < err * err || depth > 24 {
		Vector_CubicTo(out, bez[1], bez[2], bez[3])
		return
	}
	// Close: a few Newton steps on the parameters first.
	if maxErr < err * err * 16 {
		for _ in 0 ..< 4 {
			reparameterize(pts, u, bez)
			bez = generate_bezier(pts, u, t1, t2)
			maxErr, split = max_error(pts, bez, u)
			if maxErr < err * err {
				Vector_CubicTo(out, bez[1], bez[2], bez[3])
				return
			}
		}
	}
	// Split where it's worst; the tangent there is shared (smooth).
	split = clamp(split, 1, n - 2)
	tc := linalg.normalize0(pts[split - 1] - pts[split + 1])
	fit_cubic(pts[:split + 1], t1, tc, err, out, depth + 1)
	fit_cubic(pts[split:], -tc, t2, err, out, depth + 1)
}

@(private = "file")
chord_params :: proc(pts: [][2]f32) -> []f32 {
	u := make([]f32, len(pts), context.temp_allocator)
	for i in 1 ..< len(pts) do u[i] = u[i - 1] + linalg.distance(pts[i], pts[i - 1])
	total := u[len(u) - 1]
	if total > 0 do for i in 1 ..< len(u) do u[i] /= total
	return u
}

@(private = "file")
bez_at :: proc(b: [4][2]f32, t: f32) -> [2]f32 {
	s := 1 - t
	return b[0] * (s * s * s) + b[1] * (3 * s * s * t) + b[2] * (3 * s * t * t) + b[3] * (t * t * t)
}

// generate_bezier: the cubic with the end tangents that fits best (least
// squares on the handle lengths).
@(private = "file")
generate_bezier :: proc(pts: [][2]f32, u: []f32, t1, t2: [2]f32) -> [4][2]f32 {
	first, last := pts[0], pts[len(pts) - 1]
	c: [2][2]f32
	x: [2]f32
	for p, i in pts {
		t := u[i]
		s := 1 - t
		b0, b1, b2, b3 := s * s * s, 3 * s * s * t, 3 * s * t * t, t * t * t
		a0, a1 := t1 * b1, t2 * b2
		c[0][0] += linalg.dot(a0, a0)
		c[0][1] += linalg.dot(a0, a1)
		c[1][1] += linalg.dot(a1, a1)
		tmp := p - (first * (b0 + b1) + last * (b2 + b3))
		x[0] += linalg.dot(a0, tmp)
		x[1] += linalg.dot(a1, tmp)
	}
	c[1][0] = c[0][1]
	det := c[0][0] * c[1][1] - c[1][0] * c[0][1]
	alpha1, alpha2: f32
	if abs(det) > 1e-9 {
		alpha1 = (x[0] * c[1][1] - x[1] * c[0][1]) / det
		alpha2 = (c[0][0] * x[1] - c[1][0] * x[0]) / det
	}
	seg := linalg.distance(first, last)
	eps := 1e-6 * seg
	if alpha1 < eps || alpha2 < eps {
		alpha1 = seg / 3
		alpha2 = seg / 3
	}
	return {first, first + t1 * alpha1, last + t2 * alpha2, last}
}

@(private = "file")
max_error :: proc(pts: [][2]f32, b: [4][2]f32, u: []f32) -> (worst: f32, at: int) {
	at = len(pts) / 2
	for p, i in pts[1:len(pts) - 1] {
		d := linalg.length2(bez_at(b, u[i + 1]) - p)
		if d >= worst do worst, at = d, i + 1
	}
	return
}

@(private = "file")
reparameterize :: proc(pts: [][2]f32, u: []f32, b: [4][2]f32) {
	d1 := [3][2]f32{(b[1] - b[0]) * 3, (b[2] - b[1]) * 3, (b[3] - b[2]) * 3}
	d2 := [2][2]f32{(d1[1] - d1[0]) * 2, (d1[2] - d1[1]) * 2}
	for p, i in pts {
		t := u[i]
		s := 1 - t
		q := bez_at(b, t)
		q1 := d1[0] * (s * s) + d1[1] * (2 * s * t) + d1[2] * (t * t)
		q2 := d2[0] * s + d2[1] * t
		num := linalg.dot(q - p, q1)
		den := linalg.dot(q1, q1) + linalg.dot(q - p, q2)
		if abs(den) > 1e-9 do u[i] = clamp(t - num / den, 0, 1)
	}
}

// Vector_BrushOutline appends a brush stroke's outline (closed, to be
// filled) along `pts` with a width per point (`widths`, path units), round
// ends, fitted within `err`.
Vector_BrushOutline :: proc(pts: [][2]f32, widths: []f32, err: f32, out: ^Vector_Path) {
	n := len(pts)
	if n == 0 do return
	if n == 1 {
		Vector_Ellipse(out, pts[0], {widths[0], widths[0]} * 0.5)
		return
	}
	left := make([dynamic][2]f32, 0, n, context.temp_allocator)
	right := make([dynamic][2]f32, 0, n, context.temp_allocator)
	for i in 0 ..< n {
		a := pts[max(i - 1, 0)]
		b := pts[min(i + 1, n - 1)]
		d := linalg.normalize0(b - a)
		nrm := [2]f32{-d.y, d.x} * (widths[i] * 0.5)
		append(&left, pts[i] + nrm)
		append(&right, pts[i] - nrm)
	}
	ring := make([dynamic][2]f32, 0, 2 * n + 24, context.temp_allocator)
	append(&ring, ..left[:])
	cap :: proc(ring: ^[dynamic][2]f32, c: [2]f32, from: [2]f32, steps: int) {
		// A half circle round c, from `from` (turning clockwise in y-down space).
		v := from - c
		for s in 1 ..< steps {
			a := math.PI * f32(s) / f32(steps)
			co, si := math.cos(a), math.sin(a)
			append(ring, c + [2]f32{v.x * co + v.y * si, -v.x * si + v.y * co})
		}
	}
	cap(&ring, pts[n - 1], left[n - 1], 8)
	for i := n - 1; i >= 0; i -= 1 do append(&ring, right[i])
	cap(&ring, pts[0], right[0], 8)
	append(&ring, left[0]) // (back to the start: fitted as a closed curve)
	Vector_FitCurve(ring[:], err, out)
	Vector_Close(out)
}

// Vector_EnclosedArea: the region containing `q` that the shapes' fills and
// lines close in, as a closed path (its holes included) - false when `q` is
// on a shape or the area is open to the outside.
Vector_EnclosedArea :: proc(shapes: []Vector_Shape, q: [2]f32, tol: f32, out: ^Vector_Path) -> bool {
	ink: Vector_Polys
	ink.pts = make([dynamic][2]f32, context.temp_allocator)
	ink.rings = make([dynamic]Vector_Ring, context.temp_allocator)
	if !Vector_ShapesArea(shapes, tol, &ink) || len(ink.rings) == 0 do return false
	if Vector_PolysContains(&ink, q) do return false
	b := Vector_PolysBounds(&ink)
	m := max(b[2] - b[0], b[3] - b[1]) * 0.1 + 10
	box: Vector_Polys
	box.pts = make([dynamic][2]f32, context.temp_allocator)
	box.rings = make([dynamic]Vector_Ring, context.temp_allocator)
	frame := [4][2]f32{{b[0] - m, b[1] - m}, {b[2] + m, b[1] - m}, {b[2] + m, b[3] + m}, {b[0] - m, b[3] + m}}
	Vector_PolysAddRing(&box, frame[:])
	gaps: Vector_Polys
	gaps.pts = make([dynamic][2]f32, context.temp_allocator)
	gaps.rings = make([dynamic]Vector_Ring, context.temp_allocator)
	if !Vector_PolysBoolean(.Subtract, &box, &ink, tol, &gaps) do return false
	// The outer ring holding q (the innermost one, if they nest)...
	best, bestArea := -1, max(f32)
	for r, i in gaps.rings {
		if r.parent >= 0 do continue
		ring := Vector_Polys_Ring(&gaps, i)
		if !Vector_PointInPolygon(ring, q) do continue
		if a := abs(Vector_SignedArea(ring)); a < bestArea do best, bestArea = i, a
	}
	if best < 0 do return false
	// ...not the outside (the one reaching the frame).
	rb := [4]f32{max(f32), max(f32), -max(f32), -max(f32)}
	for p in Vector_Polys_Ring(&gaps, best) do rb = {min(rb[0], p.x), min(rb[1], p.y), max(rb[2], p.x), max(rb[3], p.y)}
	if rb[0] <= frame[0].x + 1e-3 || rb[1] <= frame[0].y + 1e-3 || rb[2] >= frame[2].x - 1e-3 || rb[3] >= frame[2].y - 1e-3 do return false
	// The ring and its holes (the islands inside it).
	one: Vector_Polys
	one.pts = make([dynamic][2]f32, context.temp_allocator)
	one.rings = make([dynamic]Vector_Ring, context.temp_allocator)
	Vector_PolysAddRing(&one, Vector_Polys_Ring(&gaps, best))
	for r, i in gaps.rings do if r.parent == best do Vector_PolysAddRing(&one, Vector_Polys_Ring(&gaps, i), 0)
	Vector_PolysToPath(&one, out)
	return true
}
