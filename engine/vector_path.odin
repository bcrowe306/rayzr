package engine

import "core:math"

// ============================================================================
// 2D vector art (TODO Phase 14; engine/docs/vector.md): paths and shapes.
//
//   Vector_Path    move / line / quad / cubic / close commands; the points
//                  are packed: move and line take 1, quad 2 (control, end),
//                  cubic 3 (control 1, control 2, end)
//   Vector_Style   fill (colour, rule) and stroke (colour, width, joins,
//                  caps, miter limit)
//   Vector_Shape   a path drawn with a style
//
// Shapes are tessellated into triangle meshes (vector_tess.odin) once and
// cached; drawing them only sets a transform (vector_mesh.odin).
// ============================================================================

Vector_Cmd :: enum u8 {
	Move,
	Line,
	Quad,
	Cubic,
	Close,
}

Vector_Path :: struct {
	cmds: [dynamic]Vector_Cmd,
	pts:  [dynamic][2]f32,
}

Vector_Fill_Rule :: enum u8 {
	NonZero,
	EvenOdd,
}

Vector_Join :: enum u8 {
	Miter,
	Round,
	Bevel,
}

Vector_Cap :: enum u8 {
	Butt,
	Round,
	Square,
}

// Paints: a solid colour (the style's fillColor / strokeColor) or a
// gradient. Gradients are defined in their own space, mapped onto the
// shape by `transform` (a 2x3 affine matrix: x' = a*x + c*y + e,
// y' = b*x + d*y + f - Flash's gradient transform tool, SVG's
// gradientTransform): linear from p0 to p1, radial around center with
// radius. Up to 16 stops (Flash allows 15), offsets 0..1 ascending.
Vector_Paint_Kind :: enum u8 {
	Solid,
	Linear,
	Radial,
}

Vector_Spread :: enum u8 {
	Pad,     // the end colours continue
	Reflect, // back and forth
	Repeat,  // over again
}

Vector_Stop :: struct {
	offset: f32,
	color:  [4]u8,
}

VECTOR_MAX_STOPS :: 16

Vector_Paint :: struct {
	kind:      Vector_Paint_Kind,
	spread:    Vector_Spread,
	stopCount: u8,
	stops:     [VECTOR_MAX_STOPS]Vector_Stop,
	p0, p1:    [2]f32, // linear: from, to
	center:    [2]f32, // radial
	radius:    f32,
	transform: [6]f32, // a, b, c, d, e, f (zero: identity)
}

// Vector_Dash: a dash pattern (on, off, on, off... in the shape's units;
// up to 8 values) shifted by offset; count 0 = a solid line.
Vector_Dash :: struct {
	count:  u8,
	values: [8]f32,
	offset: f32,
}

Vector_Style :: struct {
	fill:        bool,
	fillColor:   [4]u8,
	fillRule:    Vector_Fill_Rule,
	fillPaint:   Vector_Paint, // (kind .Solid: fillColor)
	stroke:      bool,
	strokeColor: [4]u8,
	strokeWidth: f32,
	strokePaint: Vector_Paint,
	join:        Vector_Join,
	cap:         Vector_Cap,
	miterLimit:  f32,
	dash:        Vector_Dash,
	opacity:     f32, // the whole shape (0: treated as 1)
}

// Vector_LinearGradient / Vector_RadialGradient: a paint from stops
// (offsets 0..1).
Vector_LinearGradient :: proc(p0, p1: [2]f32, stops: []Vector_Stop, spread := Vector_Spread.Pad) -> Vector_Paint {
	p := Vector_Paint{kind = .Linear, spread = spread, p0 = p0, p1 = p1}
	vector_paint_stops(&p, stops)
	return p
}

Vector_RadialGradient :: proc(center: [2]f32, radius: f32, stops: []Vector_Stop, spread := Vector_Spread.Pad) -> Vector_Paint {
	p := Vector_Paint{kind = .Radial, spread = spread, center = center, radius = radius}
	vector_paint_stops(&p, stops)
	return p
}

@(private = "file")
vector_paint_stops :: proc(p: ^Vector_Paint, stops: []Vector_Stop) {
	n := min(len(stops), VECTOR_MAX_STOPS)
	for i in 0 ..< n do p.stops[i] = stops[i]
	p.stopCount = u8(n)
}

// Vector_PaintColorAt: the gradient's colour at t (0..1 along it, after
// the spread), interpolated between stops (the CPU side of the shader).
Vector_PaintColorAt :: proc(p: ^Vector_Paint, t: f32) -> [4]u8 {
	n := int(p.stopCount)
	if n == 0 do return {0, 0, 0, 0}
	if t <= p.stops[0].offset do return p.stops[0].color
	for i in 1 ..< n {
		a, b := p.stops[i - 1], p.stops[i]
		if t <= b.offset {
			span := b.offset - a.offset
			k := (t - a.offset) / span if span > 1e-6 else 1
			c: [4]u8
			for ch in 0 ..< 4 do c[ch] = u8(f32(a.color[ch]) + (f32(b.color[ch]) - f32(a.color[ch])) * k + 0.5)
			return c
		}
	}
	return p.stops[n - 1].color
}

// Vector_PaintSpread applies the spread mode to a raw gradient position.
Vector_PaintSpread :: proc(spread: Vector_Spread, t: f32) -> f32 {
	switch spread {
	case .Pad: return clamp(t, 0, 1)
	case .Reflect:
		m := t - 2 * math.floor(t / 2)
		return 1 - abs(m - 1)
	case .Repeat: return t - math.floor(t)
	}
	return t
}

// Vector_PaintCoord: a point's gradient coordinates - linear: (t along
// p0->p1, 0); radial: the offset from the centre in radii (length = t).
Vector_PaintCoord :: proc(p: ^Vector_Paint, pt: [2]f32) -> [2]f32 {
	q := pt
	if p.transform != {} {
		// The inverse of the gradient transform.
		a, b, c, d, e, f := p.transform[0], p.transform[1], p.transform[2], p.transform[3], p.transform[4], p.transform[5]
		det := a * d - b * c
		if abs(det) > 1e-12 {
			x, y := pt.x - e, pt.y - f
			q = {(d * x - c * y) / det, (-b * x + a * y) / det}
		}
	}
	switch p.kind {
	case .Linear:
		dir := p.p1 - p.p0
		l2 := dir.x * dir.x + dir.y * dir.y
		if l2 < 1e-12 do return {0, 0}
		return {((q.x - p.p0.x) * dir.x + (q.y - p.p0.y) * dir.y) / l2, 0}
	case .Radial:
		r := max(p.radius, 1e-6)
		return (q - p.center) / r
	case .Solid:
	}
	return {}
}

VECTOR_STYLE_DEFAULT :: Vector_Style {
	fill        = true,
	fillColor   = {255, 255, 255, 255},
	strokeColor = {0, 0, 0, 255},
	strokeWidth = 1,
	miterLimit  = 4,
	opacity     = 1,
}

Vector_Shape :: struct {
	path:  Vector_Path,
	style: Vector_Style,
	clip:  ^Vector_Clip, // only what lies inside it is drawn (nil: no clip; not owned)
}

// Vector_Clip: a clipping region - a path filled by its own rule (SVG
// clipPath / clip-rule, Flash masks of plain shapes).
Vector_Clip :: struct {
	path: Vector_Path,
	rule: Vector_Fill_Rule,
}

Vector_Path_Init :: proc(p: ^Vector_Path, allocator := context.allocator) {
	p.cmds = make([dynamic]Vector_Cmd, allocator)
	p.pts = make([dynamic][2]f32, allocator)
}

Vector_Path_Destroy :: proc(p: ^Vector_Path) {
	delete(p.cmds)
	delete(p.pts)
	p^ = {}
}

Vector_Path_Clear :: proc(p: ^Vector_Path) {
	clear(&p.cmds)
	clear(&p.pts)
}

Vector_MoveTo :: proc(p: ^Vector_Path, a: [2]f32) {
	append(&p.cmds, Vector_Cmd.Move)
	append(&p.pts, a)
}

Vector_LineTo :: proc(p: ^Vector_Path, a: [2]f32) {
	append(&p.cmds, Vector_Cmd.Line)
	append(&p.pts, a)
}

Vector_QuadTo :: proc(p: ^Vector_Path, c, a: [2]f32) {
	append(&p.cmds, Vector_Cmd.Quad)
	append(&p.pts, c, a)
}

Vector_CubicTo :: proc(p: ^Vector_Path, c1, c2, a: [2]f32) {
	append(&p.cmds, Vector_Cmd.Cubic)
	append(&p.pts, c1, c2, a)
}

Vector_Close :: proc(p: ^Vector_Path) {
	append(&p.cmds, Vector_Cmd.Close)
}

// Vector_Ellipse adds a closed ellipse (4 cubics, clockwise in screen space).
Vector_Ellipse :: proc(p: ^Vector_Path, c: [2]f32, r: [2]f32) {
	K :: 0.5522847498 // 4/3 * (sqrt(2) - 1): a circle's quarter as a cubic
	k := r * K
	Vector_MoveTo(p, {c.x + r.x, c.y})
	Vector_CubicTo(p, {c.x + r.x, c.y + k.y}, {c.x + k.x, c.y + r.y}, {c.x, c.y + r.y})
	Vector_CubicTo(p, {c.x - k.x, c.y + r.y}, {c.x - r.x, c.y + k.y}, {c.x - r.x, c.y})
	Vector_CubicTo(p, {c.x - r.x, c.y - k.y}, {c.x - k.x, c.y - r.y}, {c.x, c.y - r.y})
	Vector_CubicTo(p, {c.x + k.x, c.y - r.y}, {c.x + r.x, c.y - k.y}, {c.x + r.x, c.y})
	Vector_Close(p)
}

// Vector_Rect adds a closed rectangle (clockwise in screen space).
Vector_Rect :: proc(p: ^Vector_Path, min, max: [2]f32) {
	Vector_MoveTo(p, min)
	Vector_LineTo(p, {max.x, min.y})
	Vector_LineTo(p, max)
	Vector_LineTo(p, {min.x, max.y})
	Vector_Close(p)
}

// Vector_RoundRect adds a closed rectangle with rounded corners (radius
// clamped to half the shorter side; 0: square corners).
Vector_RoundRect :: proc(p: ^Vector_Path, min, max: [2]f32, radius: f32) {
	r := clamp(radius, 0, 0.5 * math.min(max.x - min.x, max.y - min.y))
	if r <= 0 {
		Vector_Rect(p, min, max)
		return
	}
	K :: 0.5522847498
	k := r * (1 - K)
	Vector_MoveTo(p, {min.x + r, min.y})
	Vector_LineTo(p, {max.x - r, min.y})
	Vector_CubicTo(p, {max.x - k, min.y}, {max.x, min.y + k}, {max.x, min.y + r})
	Vector_LineTo(p, {max.x, max.y - r})
	Vector_CubicTo(p, {max.x, max.y - k}, {max.x - k, max.y}, {max.x - r, max.y})
	Vector_LineTo(p, {min.x + r, max.y})
	Vector_CubicTo(p, {min.x + k, max.y}, {min.x, max.y - k}, {min.x, max.y - r})
	Vector_LineTo(p, {min.x, min.y + r})
	Vector_CubicTo(p, {min.x, min.y + k}, {min.x + k, min.y}, {min.x + r, min.y})
	Vector_Close(p)
}

// Vector_Polygon adds a closed regular polygon (`sides` >= 3) fitting the
// ellipse c, r, its first corner straight up; a star when `inner` (0..1:
// the inner corners' radius, a fraction of the outer) is above 0 - then
// `sides` is its number of points.
Vector_Polygon :: proc(p: ^Vector_Path, c, r: [2]f32, sides: int, inner: f32 = 0) {
	n := math.max(sides, 3)
	star := inner > 0
	count := n * 2 if star else n
	for i in 0 ..< count {
		a := -math.PI * 0.5 + f32(i) * 2 * math.PI / f32(count)
		rr := r * (inner if star && i % 2 == 1 else 1)
		pt := c + [2]f32{math.cos(a) * rr.x, math.sin(a) * rr.y}
		if i == 0 do Vector_MoveTo(p, pt)
		else do Vector_LineTo(p, pt)
	}
	Vector_Close(p)
}

// --- flattening ---------------------------------------------------------------------

// Vector_Contour: a flattened subpath (closed: the last point joins the first).
Vector_Contour :: struct {
	first, count: int, // into Vector_Flat.pts
	closed:       bool,
}

Vector_Flat :: struct {
	pts:      [dynamic][2]f32,
	contours: [dynamic]Vector_Contour,
}

Vector_Flat_Destroy :: proc(f: ^Vector_Flat) {
	delete(f.pts)
	delete(f.contours)
	f^ = {}
}

Vector_Contour_Points :: proc(f: ^Vector_Flat, c: Vector_Contour) -> [][2]f32 {
	return f.pts[c.first:c.first + c.count]
}

// Vector_CurveSegments: how many lines approximate a curve within `tol`
// (Wang's formula: the curve stays within tol of its chords).
Vector_QuadSegments :: proc(p0, p1, p2: [2]f32, tol: f32) -> int {
	dd := linalg_len(p0 - 2 * p1 + p2)
	n := math.sqrt(0.25 * dd / max(tol, 1e-4))
	return clamp(int(math.ceil(n)), 1, 512)
}

Vector_CubicSegments :: proc(p0, p1, p2, p3: [2]f32, tol: f32) -> int {
	dd := max(linalg_len(p0 - 2 * p1 + p2), linalg_len(p1 - 2 * p2 + p3))
	n := math.sqrt(0.75 * dd / max(tol, 1e-4))
	return clamp(int(math.ceil(n)), 1, 512)
}

@(private = "file")
linalg_len :: proc(v: [2]f32) -> f32 {return math.sqrt(v.x * v.x + v.y * v.y)}

// Vector_Flatten turns a path into polylines whose distance to the curves is
// at most `tol` (in the path's units: tessellating for a zoom divides the
// screen tolerance by the scale). Consecutive duplicate points are dropped.
Vector_Flatten :: proc(path: ^Vector_Path, tol: f32, out: ^Vector_Flat) {
	clear(&out.pts)
	clear(&out.contours)
	cur := Vector_Contour{first = 0}
	last: [2]f32
	start: [2]f32
	add :: proc(out: ^Vector_Flat, cur: ^Vector_Contour, p: [2]f32) {
		if cur.count > 0 {
			q := out.pts[len(out.pts) - 1]
			if abs(q.x - p.x) < 1e-5 && abs(q.y - p.y) < 1e-5 do return
		}
		append(&out.pts, p)
		cur.count += 1
	}
	finish :: proc(out: ^Vector_Flat, cur: ^Vector_Contour, closed: bool) {
		if cur.count >= 2 {
			// A closing point equal to the first is implied.
			if closed && cur.count > 2 {
				a, b := out.pts[cur.first], out.pts[cur.first + cur.count - 1]
				if abs(a.x - b.x) < 1e-5 && abs(a.y - b.y) < 1e-5 {
					pop(&out.pts)
					cur.count -= 1
				}
			}
			cur.closed = closed
			append(&out.contours, cur^)
		} else {
			resize(&out.pts, cur.first)
		}
		cur^ = {first = len(out.pts)}
	}
	pi := 0
	for cmd in path.cmds {
		switch cmd {
		case .Move:
			if cur.count > 0 do finish(out, &cur, false)
			last = path.pts[pi]; start = last; pi += 1
			add(out, &cur, last)
		case .Line:
			if cur.count == 0 do add(out, &cur, last)
			last = path.pts[pi]; pi += 1
			add(out, &cur, last)
		case .Quad:
			if cur.count == 0 do add(out, &cur, last)
			c, e := path.pts[pi], path.pts[pi + 1]; pi += 2
			n := Vector_QuadSegments(last, c, e, tol)
			for i in 1 ..= n {
				t := f32(i) / f32(n)
				u := 1 - t
				add(out, &cur, u * u * last + 2 * u * t * c + t * t * e)
			}
			last = e
		case .Cubic:
			if cur.count == 0 do add(out, &cur, last)
			c1, c2, e := path.pts[pi], path.pts[pi + 1], path.pts[pi + 2]; pi += 3
			n := Vector_CubicSegments(last, c1, c2, e, tol)
			for i in 1 ..= n {
				t := f32(i) / f32(n)
				u := 1 - t
				add(out, &cur, u * u * u * last + 3 * u * u * t * c1 + 3 * u * t * t * c2 + t * t * t * e)
			}
			last = e
		case .Close:
			finish(out, &cur, true)
			last = start
		}
	}
	if cur.count > 0 do finish(out, &cur, false)
}

// Vector_SignedArea: twice the signed area of a polygon (positive = clockwise
// in screen space, y down).
Vector_SignedArea :: proc(pts: [][2]f32) -> f32 {
	a: f32
	n := len(pts)
	for i in 0 ..< n {
		p, q := pts[i], pts[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	}
	return a
}

// Vector_PointInPolygon: even-odd test.
Vector_PointInPolygon :: proc(pts: [][2]f32, p: [2]f32) -> bool {
	inside := false
	n := len(pts)
	j := n - 1
	for i in 0 ..< n {
		a, b := pts[i], pts[j]
		if (a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x do inside = !inside
		j = i
	}
	return inside
}
