package engine

import "core:math"
import clip "clipper"

// ============================================================================
// Vector tessellation: shapes -> one triangle mesh (positions, colours,
// indices), anti-aliased without MSAA by a feathered fringe: every filled
// outline is inset by half a pixel and wrapped in a 1-pixel strip fading to
// transparent (NanoVG's approach); strokes are strips of four lanes (fade -
// solid - solid - fade).
//
// `pixel` is the size of a screen pixel in the shapes' units (1 / the scale
// they are drawn at): curves are flattened to a quarter pixel and fringes
// are one pixel wide. A cached mesh stays valid while the drawing scale
// stays near the one it was made for (vector_mesh.odin re-tessellates when
// it changes by more than ~2x).
//
// Fills: the contours are normalized under the shape's fill rule by
// Clipper2 (engine/clipper: self-intersections, overlaps, holes assigned to
// their outer rings), then earcut triangulates (vector_earcut.odin).
// ============================================================================

Vector_Mesh :: struct {
	verts:     [dynamic][2]f32,
	cols:      [dynamic][4]u8,
	gc:        [dynamic][2]f32, // gradient coordinates (vector_path.odin Vector_PaintCoord)
	gi:        [dynamic][2]f32, // gradient row, mode (0: solid; 1 + kind * 4 + spread)
	idx:       [dynamic]u32,
	gradients: [dynamic][256][4]u8, // one baked row per gradient paint
	bounds:    [4]f32, // min x, min y, max x, max y
	// (While tessellating: the paint new vertices take.)
	curPaint:  ^Vector_Paint,
	curRow:    int,
}

Vector_Mesh_Clear :: proc(m: ^Vector_Mesh) {
	clear(&m.verts)
	clear(&m.cols)
	clear(&m.gc)
	clear(&m.gi)
	clear(&m.idx)
	clear(&m.gradients)
	m.bounds = {}
	m.curPaint = nil
}

Vector_Mesh_Destroy :: proc(m: ^Vector_Mesh) {
	delete(m.verts)
	delete(m.cols)
	delete(m.gc)
	delete(m.gi)
	delete(m.idx)
	delete(m.gradients)
	m^ = {}
}

// vector_mesh_paint: what the next vertices are painted with; returns the
// colour to give them (a gradient: white with the coverage / opacity in
// alpha; solid: the colour faded by the opacity).
@(private = "file")
vector_mesh_paint :: proc(m: ^Vector_Mesh, paint: ^Vector_Paint, solid: [4]u8, opacity: f32) -> [4]u8 {
	if paint.kind == .Solid || paint.stopCount == 0 {
		m.curPaint = nil
		return {solid.r, solid.g, solid.b, u8(f32(solid.a) * opacity + 0.5)}
	}
	row: [256][4]u8
	for i in 0 ..< 256 do row[i] = Vector_PaintColorAt(paint, f32(i) / 255)
	append(&m.gradients, row)
	m.curPaint = paint
	m.curRow = len(m.gradients) - 1
	return {255, 255, 255, u8(255 * opacity + 0.5)}
}

// Vector_Tess: scratch buffers kept between tessellations (no allocation per
// shape once warm). One per thread.
Vector_Tess :: struct {
	flat:    Vector_Flat,
	ring:    [dynamic][2]f32,
	normals: [dynamic][2]f32,
	poly:    [dynamic][2]f32,
	holes:   [dynamic]int,
	depth:   [dynamic]int,
	parent:  [dynamic]int,
	area:    [dynamic]f32,
	tri:     [dynamic]u32,
	ec:      Earcut,
	cxy:     [dynamic]f64, // contours for the clipper
	ccounts: [dynamic]i32,
	dashed:  Vector_Flat, // a dashed stroke's pieces
	clipFlat: Vector_Flat, // the shape's clip, flattened
	kxy:     [dynamic]f64, // the clip's contours for the clipper
	kcounts: [dynamic]i32,
}

Vector_Tess_Destroy :: proc(t: ^Vector_Tess) {
	Vector_Flat_Destroy(&t.flat)
	delete(t.ring)
	delete(t.normals)
	delete(t.poly)
	delete(t.holes)
	delete(t.depth)
	delete(t.parent)
	delete(t.area)
	delete(t.tri)
	delete(t.cxy)
	delete(t.ccounts)
	Vector_Flat_Destroy(&t.dashed)
	Vector_Flat_Destroy(&t.clipFlat)
	delete(t.kxy)
	delete(t.kcounts)
	Earcut_Destroy(&t.ec)
	t^ = {}
}

// Vector_Tessellate appends the shapes' triangles to `mesh` (cleared first).
Vector_Tessellate :: proc(t: ^Vector_Tess, shapes: []Vector_Shape, pixel: f32, mesh: ^Vector_Mesh) {
	Vector_Mesh_Clear(mesh)
	px := max(pixel, 1e-4)
	for &s in shapes {
		Vector_Flatten(&s.path, px * 0.25, &t.flat)
		if len(t.flat.contours) == 0 do continue
		opacity := s.style.opacity if s.style.opacity > 0 else 1
		clipped := s.clip != nil
		if clipped {
			Vector_Flatten(&s.clip.path, px * 0.25, &t.clipFlat)
			clear(&t.kxy); clear(&t.kcounts)
			for c in t.clipFlat.contours do if c.count >= 3 {
				for p in Vector_Contour_Points(&t.clipFlat, c) do append(&t.kxy, f64(p.x), f64(p.y))
				append(&t.kcounts, i32(c.count))
			}
			if len(t.kcounts) == 0 do continue // (an empty clip hides everything)
		}
		if s.style.fill && (s.style.fillColor.a > 0 || s.style.fillPaint.kind != .Solid) {
			col := vector_mesh_paint(mesh, &s.style.fillPaint, s.style.fillColor, opacity)
			tess_fill(t, s.style, col, px, mesh, s.clip)
		}
		if s.style.stroke && (s.style.strokeColor.a > 0 || s.style.strokePaint.kind != .Solid) && s.style.strokeWidth > 0 {
			col := vector_mesh_paint(mesh, &s.style.strokePaint, s.style.strokeColor, opacity)
			if s.style.dash.count > 0 do vector_dash(&t.flat, &t.dashed, s.style.dash)
			lines := &t.dashed if s.style.dash.count > 0 else &t.flat
			if clipped do tess_stroke_clipped(t, s.style, col, px, mesh, lines, s.clip)
			else do tess_stroke(t, s.style, col, px, mesh, lines)
		}
	}
	mesh.curPaint = nil
	Vector_MeshBakeLinearGradients(mesh)
	if len(mesh.verts) > 0 {
		b := [4]f32{max(f32), max(f32), min(f32), min(f32)}
		for v in mesh.verts {
			b[0] = min(b[0], v.x); b[1] = min(b[1], v.y)
			b[2] = max(b[2], v.x); b[3] = max(b[3], v.y)
		}
		mesh.bounds = b
	}
}

// Vector_MeshBakeLinearGradients turns gradient vertices into plain
// coloured ones wherever that draws the same: a linear, pad gradient whose
// baked row is a straight blend of its two ends (two stops: most SVG
// skies and hills), every vertex of it within the gradient's 0..1 (a
// little past for the edge fringe). The colour is linear in t and t is
// linear across a triangle, so the vertex colours interpolate to the same
// pixels (within two levels of rounding) - and a mesh left with no gradient
// vertices draws through the plain shader (vector_mesh.odin): no texture
// look-up and spread maths per pixel, which software GL pays for every
// pixel of a fill (#331). Rows no vertex uses any more are dropped when
// none is used.
Vector_MeshBakeLinearGradients :: proc(m: ^Vector_Mesh) {
	rows := len(m.gradients)
	if rows == 0 do return
	// Past 0..1 by this much (the fringe's outer vertices): extrapolated.
	MARGIN :: 0.05
	ok := make([]bool, rows, context.temp_allocator)
	for r in 0 ..< rows {
		row := &m.gradients[r]
		ok[r] = true
		check: for i in 0 ..< 256 {
			for ch in 0 ..< 4 {
				want := f32(row[0][ch]) + (f32(row[255][ch]) - f32(row[0][ch])) * f32(i) / 255
				if abs(f32(row[i][ch]) - want) > 1 {ok[r] = false; break check}
			}
		}
	}
	for g, v in m.gi do if g.y > 0 {
		r := clamp(int(g.x), 0, rows - 1)
		mode := int(g.y + 0.5) - 1
		t := m.gc[v].x
		if mode != 0 || t < -MARGIN || t > 1 + MARGIN do ok[r] = false // (radial, reflect / repeat, past the ends)
	}
	used := 0
	for &g, v in m.gi do if g.y > 0 {
		r := clamp(int(g.x), 0, rows - 1)
		if !ok[r] {used += 1; continue}
		a, b := m.gradients[r][0], m.gradients[r][255]
		t := m.gc[v].x
		c: [4]u8
		for ch in 0 ..< 4 do c[ch] = u8(clamp(f32(a[ch]) + (f32(b[ch]) - f32(a[ch])) * t + 0.5, 0, 255))
		// (As the shader: the gradient's colour, its alpha times the vertex's coverage / opacity.)
		c.a = u8((u32(c.a) * u32(m.cols[v].a) + 127) / 255)
		m.cols[v] = c
		m.gc[v] = {}
		g = {}
	}
	if used == 0 do clear(&m.gradients)
}

@(private = "file")
add_vert :: #force_inline proc(m: ^Vector_Mesh, p: [2]f32, c: [4]u8) -> u32 {
	append(&m.verts, p)
	append(&m.cols, c)
	if m.curPaint != nil {
		append(&m.gc, Vector_PaintCoord(m.curPaint, p))
		mode := 1 + (0 if m.curPaint.kind == .Linear else 4) + int(m.curPaint.spread)
		append(&m.gi, [2]f32{f32(m.curRow), f32(mode)})
	} else {
		append(&m.gc, [2]f32{})
		append(&m.gi, [2]f32{})
	}
	return u32(len(m.verts) - 1)
}

@(private = "file")
fade :: #force_inline proc(c: [4]u8) -> [4]u8 {return {c.r, c.g, c.b, 0}}

// ring_normals: per-vertex miter vectors pointing away from the polygon's
// interior (scaled so offsetting by d along them moves each edge by d).
@(private = "file")
ring_normals :: proc(pts: [][2]f32, outward_sign: f32, out: ^[dynamic][2]f32) {
	clear(out)
	n := len(pts)
	for i in 0 ..< n {
		p0, p1, p2 := pts[(i + n - 1) % n], pts[i], pts[(i + 1) % n]
		n0 := edge_normal(p0, p1) * outward_sign
		n1 := edge_normal(p1, p2) * outward_sign
		append(out, miter(n0, n1))
	}
}

@(private = "file")
edge_normal :: #force_inline proc(a, b: [2]f32) -> [2]f32 {
	d := b - a
	l := math.sqrt(d.x * d.x + d.y * d.y)
	if l < 1e-9 do return {}
	return {d.y / l, -d.x / l}
}

// miter: the join vector of two unit normals (length 1 / cos(half angle),
// capped so a hairpin doesn't shoot off).
@(private = "file")
miter :: #force_inline proc(n0, n1: [2]f32) -> [2]f32 {
	dm := (n0 + n1) * 0.5
	d2 := dm.x * dm.x + dm.y * dm.y
	if d2 < 1e-6 do return n1
	s := min(1 / d2, 64)
	return dm * s
}

@(private = "file")
tess_fill :: proc(t: ^Vector_Tess, style: Vector_Style, col: [4]u8, px: f32, mesh: ^Vector_Mesh, clipRegion: ^Vector_Clip) {
	f := &t.flat
	// Normalize: the area the contours cover under the fill rule, as simple
	// outer rings with their holes (Clipper2: self-intersections, overlaps,
	// either rule). Open contours are filled as if closed (like SVG).
	clear(&t.cxy); clear(&t.ccounts)
	for c in f.contours {
		if c.count < 3 do continue
		for p in Vector_Contour_Points(f, c) do append(&t.cxy, f64(p.x), f64(p.y))
		append(&t.ccounts, i32(c.count))
	}
	if len(t.ccounts) == 0 do return
	// Fast path: one convex outline (ellipses, eyes, buttons - most shapes)
	// needs no normalizing under either rule.
	if len(t.ccounts) == 1 && clipRegion == nil {
		for c in f.contours do if c.count >= 3 {
			pts := Vector_Contour_Points(f, c)
			if Vector_IsConvex(pts) {
				clear(&t.poly); clear(&t.holes)
				base := u32(len(mesh.verts))
				append_fill_ring(t, pts, 1 if Vector_SignedArea(pts) > 0 else -1, px * 0.5, col, mesh)
				clear(&t.tri)
				if Earcut_Triangulate(&t.ec, t.poly[:], nil, &t.tri) {
					for v in t.tri do append(&mesh.idx, base + v)
				}
				return
			}
		}
	}
	// (Decimal places: a twentieth of a pixel.)
	precision := i32(clamp(math.ceil(-math.log10(f64(px) * 0.05)), 1, 8))
	res: clip.Paths
	rule: clip.Fill_Rule = .NonZero if style.fillRule == .NonZero else .EvenOdd
	if clipRegion != nil {
		// (Subject and clip share a rule in the clipper: the clip's own rule
		// first makes it simple, then the intersection uses the shape's.)
		if !clip_region(t, clipRegion, precision) do return
		if clip.boolean(.Intersection, raw_data(t.cxy), raw_data(t.ccounts), i32(len(t.ccounts)), raw_data(t.kxy), raw_data(t.kcounts), i32(len(t.kcounts)), rule, precision, &res) == 0 do return
	} else {
		if clip.normalize(raw_data(t.cxy), raw_data(t.ccounts), i32(len(t.ccounts)), rule, precision, &res) == 0 do return
	}
	defer clip.free_paths(&res)
	tess_fill_paths(t, &res, col, px, mesh)
}

// clip_region: the clip's contours (t.kxy) normalized by its own rule, so
// the intersection can use the subject's rule.
@(private = "file")
clip_region :: proc(t: ^Vector_Tess, region: ^Vector_Clip, precision: i32) -> bool {
	res: clip.Paths
	rule: clip.Fill_Rule = .NonZero if region.rule == .NonZero else .EvenOdd
	if clip.normalize(raw_data(t.kxy), raw_data(t.kcounts), i32(len(t.kcounts)), rule, precision, &res) == 0 do return false
	defer clip.free_paths(&res)
	clear(&t.kxy); clear(&t.kcounts)
	for i in 0 ..< int(res.points) do append(&t.kxy, res.xy[i * 2], res.xy[i * 2 + 1])
	for i in 0 ..< int(res.contours) do append(&t.kcounts, i32(res.counts[i]))
	return len(t.kcounts) > 0
}

// tess_stroke_clipped: a clipped stroke - its outline as polygons (the
// clipper's offset: open pieces with their caps, closed contours on both
// sides), intersected with the clip, then filled with fringes.
@(private = "file")
tess_stroke_clipped :: proc(t: ^Vector_Tess, style: Vector_Style, col: [4]u8, px: f32, mesh: ^Vector_Mesh, f: ^Vector_Flat, clipRegion: ^Vector_Clip) {
	precision := i32(clamp(math.ceil(-math.log10(f64(px) * 0.05)), 1, 8))
	if !clip_region(t, clipRegion, precision) do return
	join: clip.Join = .Round if style.join == .Round else (.Bevel if style.join == .Bevel else .Miter)
	end: clip.End = .Round if style.cap == .Round else (.Square if style.cap == .Square else .Butt)
	hw := f64(max(style.strokeWidth, px) * 0.5)
	// The outline of the open and the closed contours (two offsets).
	outline := make([dynamic]f64, context.temp_allocator)
	counts := make([dynamic]i32, context.temp_allocator)
	for kind in ([]i32{0, 2}) {
		clear(&t.cxy); clear(&t.ccounts)
		for c in f.contours {
			if c.count < 2 || (kind == 2) != (c.closed && c.count > 2) do continue
			for p in Vector_Contour_Points(f, c) do append(&t.cxy, f64(p.x), f64(p.y))
			append(&t.ccounts, i32(c.count))
		}
		if len(t.ccounts) == 0 do continue
		res: clip.Paths
		if clip.offset(raw_data(t.cxy), raw_data(t.ccounts), i32(len(t.ccounts)), kind, hw, join, end, f64(style.miterLimit), f64(px) * 0.25, precision, &res) == 0 do continue
		for i in 0 ..< int(res.points) do append(&outline, res.xy[i * 2], res.xy[i * 2 + 1])
		for i in 0 ..< int(res.contours) do append(&counts, i32(res.counts[i]))
		clip.free_paths(&res)
	}
	if len(counts) == 0 do return
	res: clip.Paths
	if clip.boolean(.Intersection, raw_data(outline), raw_data(counts), i32(len(counts)), raw_data(t.kxy), raw_data(t.kcounts), i32(len(t.kcounts)), .NonZero, precision, &res) == 0 do return
	defer clip.free_paths(&res)
	tess_fill_paths(t, &res, col, px, mesh)
}

// tess_fill_paths: simple polygons with their holes (a clipper result) as
// earcut triangles inside one-pixel fringes.
@(private = "file")
tess_fill_paths :: proc(t: ^Vector_Tess, res: ^clip.Paths, col: [4]u8, px: f32, mesh: ^Vector_Mesh) {
	// The result as f32 rings.
	clear(&t.ring)
	starts := make([]int, int(res.contours) + 1, context.temp_allocator)
	for i in 0 ..< int(res.points) do append(&t.ring, [2]f32{f32(res.xy[i * 2]), f32(res.xy[i * 2 + 1])})
	for i in 0 ..< int(res.contours) do starts[i + 1] = starts[i] + int(res.counts[i])
	contour :: proc(t: ^Vector_Tess, starts: []int, i: int) -> [][2]f32 {return t.ring[starts[i]:starts[i + 1]]}
	half := px * 0.5
	for i in 0 ..< int(res.contours) {
		if res.parents[i] >= 0 || res.counts[i] < 3 do continue // (holes: with their outer)
		// The outer ring inset by half a pixel, then its holes (each inset too:
		// moved away from the filled area); fringes around all of them.
		clear(&t.poly); clear(&t.holes)
		vmap := make([dynamic]u32, 0, int(res.counts[i]), context.temp_allocator)
		pts := contour(t, starts, i)
		base := u32(len(mesh.verts))
		append_fill_ring(t, pts, 1 if Vector_SignedArea(pts) > 0 else -1, half, col, mesh)
		for k in 0 ..< len(pts) do append(&vmap, base + u32(k))
		for j in 0 ..< int(res.contours) {
			if int(res.parents[j]) != i || res.counts[j] < 3 do continue
			hpts := contour(t, starts, j)
			append(&t.holes, len(t.poly))
			hbase := u32(len(mesh.verts))
			// (A hole's fill edge moves into the hole: its outward is away from the fill.)
			append_fill_ring(t, hpts, -1 if Vector_SignedArea(hpts) > 0 else 1, half, col, mesh)
			for k in 0 ..< len(hpts) do append(&vmap, hbase + u32(k))
		}
		clear(&t.tri)
		if Earcut_Triangulate(&t.ec, t.poly[:], t.holes[:], &t.tri) {
			for v in t.tri do append(&mesh.idx, vmap[v])
		}
	}
}

// append_fill_ring: a ring inset by `half` (its points join t.poly, the
// polygon earcut fills) and its fringe, solid inside to transparent outside.
@(private = "file")
append_fill_ring :: proc(t: ^Vector_Tess, pts: [][2]f32, outward: f32, half: f32, col: [4]u8, mesh: ^Vector_Mesh) {
	ring_normals(pts, outward, &t.normals)
	first := u32(len(mesh.verts))
	n := u32(len(pts))
	for p, k in pts {
		inner := p - t.normals[k] * half
		append(&t.poly, inner)
		add_vert(mesh, inner, col)
	}
	outer0 := u32(len(mesh.verts))
	for p, k in pts do add_vert(mesh, p + t.normals[k] * half, fade(col))
	for k in 0 ..< n {
		k1 := (k + 1) % n
		a, b := first + k, first + k1
		c, d := outer0 + k, outer0 + k1
		append(&mesh.idx, a, b, d, a, d, c)
	}
}

@(private = "file")
tess_stroke :: proc(t: ^Vector_Tess, style: Vector_Style, col_: [4]u8, px: f32, mesh: ^Vector_Mesh, f: ^Vector_Flat) {
	col := col_
	w := style.strokeWidth
	// Thinner than a pixel: a pixel-wide line, fainter.
	if w < px {
		col.a = u8(f32(col.a) * w / px)
		w = px
	}
	hw := w * 0.5
	solid := max(hw - px * 0.5, 0)
	edge := hw + px * 0.5
	for c in f.contours {
		pts := Vector_Contour_Points(f, c)
		n := len(pts)
		if n < 2 do continue
		closed := c.closed && n > 2
		// Spine samples: a position and its offset direction (unit-ish); joins
		// add samples (bevel: 2, round: an arc).
		clear(&t.ring); clear(&t.normals)
		sample :: proc(t: ^Vector_Tess, p, off: [2]f32) {
			append(&t.ring, p)
			append(&t.normals, off)
		}
		for i in 0 ..< n {
			p := pts[i]
			has_prev := closed || i > 0
			has_next := closed || i < n - 1
			p_prev := pts[(i + n - 1) % n]
			p_next := pts[(i + 1) % n]
			if !has_prev {
				nn := edge_normal(p, p_next)
				d := [2]f32{-nn.y, nn.x} // along the line
				if style.cap == .Square do p -= d * hw
				sample(t, p, nn)
				continue
			}
			if !has_next {
				nn := edge_normal(p_prev, p)
				d := [2]f32{-nn.y, nn.x}
				if style.cap == .Square do p += d * hw
				sample(t, p, nn)
				continue
			}
			n0, n1 := edge_normal(p_prev, p), edge_normal(p, p_next)
			dm := miter(n0, n1)
			mlen2 := dm.x * dm.x + dm.y * dm.y
			cross := n0.x * n1.y - n0.y * n1.x
			// (A miter longer than miterLimit half-widths becomes a bevel.)
			sharp := style.join == .Miter && mlen2 > style.miterLimit * style.miterLimit
			switch {
			case style.join == .Round && abs(cross) > 1e-3:
				a0 := math.atan2(n0.y, n0.x)
				a1 := math.atan2(n1.y, n1.x)
				da := a1 - a0
				for da > math.PI do da -= 2 * math.PI
				for da < -math.PI do da += 2 * math.PI
				steps := clamp(int(math.ceil(abs(da) / math.acos(1 - px * 0.25 / max(hw, px)) )), 1, 32)
				for k in 0 ..= steps {
					a := a0 + da * f32(k) / f32(steps)
					sample(t, p, {math.cos(a), math.sin(a)})
				}
			case style.join == .Bevel && abs(cross) > 1e-3, sharp:
				sample(t, p, n0)
				sample(t, p, n1)
			case:
				sample(t, p, dm)
			}
		}
		// Four lanes per sample: fade, solid, solid, fade.
		count := len(t.ring)
		first := u32(len(mesh.verts))
		for k in 0 ..< count {
			p, o := t.ring[k], t.normals[k]
			add_vert(mesh, p + o * edge, fade(col))
			add_vert(mesh, p + o * solid, col)
			add_vert(mesh, p - o * solid, col)
			add_vert(mesh, p - o * edge, fade(col))
		}
		segs := count if closed else count - 1
		for k in 0 ..< segs {
			a := first + u32(k) * 4
			b := first + u32((k + 1) % count) * 4
			for l in u32(0) ..< 3 {
				append(&mesh.idx, a + l, b + l, b + l + 1, a + l, b + l + 1, a + l + 1)
			}
		}
		if !closed && style.cap == .Round {
			stroke_round_cap(mesh, pts[0], pts[0] - pts[1], hw, solid, edge, col, px)
			stroke_round_cap(mesh, pts[n - 1], pts[n - 1] - pts[n - 2], hw, solid, edge, col, px)
		}
	}
}

// stroke_round_cap: a half disc past the line's end (fan + fringe).
@(private = "file")
stroke_round_cap :: proc(mesh: ^Vector_Mesh, p, dir: [2]f32, hw, solid, edge: f32, col: [4]u8, px: f32) {
	l := math.sqrt(dir.x * dir.x + dir.y * dir.y)
	if l < 1e-9 do return
	d := dir / l
	nrm := [2]f32{d.y, -d.x}
	a0 := math.atan2(nrm.y, nrm.x)
	// From +normal through the direction to -normal (the side d points to).
	sweep: f32 = math.PI if (math.cos(a0 + math.PI / 2) * d.x + math.sin(a0 + math.PI / 2) * d.y) > 0 else -math.PI
	steps := clamp(int(math.ceil(math.PI / math.acos(1 - px * 0.25 / max(hw, px)))), 2, 32)
	center := add_vert(mesh, p, col)
	first := u32(len(mesh.verts))
	for k in 0 ..= steps {
		a := a0 + sweep * f32(k) / f32(steps)
		o := [2]f32{math.cos(a), math.sin(a)}
		add_vert(mesh, p + o * solid, col)
		add_vert(mesh, p + o * edge, fade(col))
	}
	for k in u32(0) ..< u32(steps) {
		i0, o0 := first + k * 2, first + k * 2 + 1
		i1, o1 := first + (k + 1) * 2, first + (k + 1) * 2 + 1
		append(&mesh.idx, center, i0, i1, i0, o0, o1, i0, o1, i1)
	}
}

// Vector_IsConvex: a simple convex polygon (every turn the same way, one
// full turn - so no self-intersection).
Vector_IsConvex :: proc(pts: [][2]f32) -> bool {
	n := len(pts)
	if n < 3 do return false
	sign: f32
	turn: f32
	for i in 0 ..< n {
		a, b, c := pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
		d1, d2 := b - a, c - b
		cr := d1.x * d2.y - d1.y * d2.x
		if abs(cr) < 1e-9 do continue
		if sign == 0 do sign = cr
		else if (cr > 0) != (sign > 0) do return false
		turn += math.atan2(cr, d1.x * d2.x + d1.y * d2.y)
	}
	return sign != 0 && abs(abs(turn) - 2 * math.PI) < 0.01
}

// vector_dash: the flattened contours cut into dashes (open pieces) by the
// pattern; a closed contour's closing edge is dashed too.
vector_dash :: proc(src, dst: ^Vector_Flat, dash: Vector_Dash) {
	clear(&dst.pts)
	clear(&dst.contours)
	n := int(dash.count)
	total: f32
	for i in 0 ..< n do total += max(dash.values[i], 0)
	if total <= 1e-6 do return
	for c in src.contours {
		pts := Vector_Contour_Points(src, c)
		segs := len(pts) if c.closed else len(pts) - 1
		// Where in the pattern the contour starts (the offset shifts it).
		pos := dash.offset - total * math.floor(dash.offset / total)
		k := 0
		for pos >= max(dash.values[k], 0) {
			pos -= max(dash.values[k], 0)
			k = (k + 1) % n
		}
		left := max(dash.values[k], 0) - pos // of the current dash / gap
		on := k % 2 == 0
		cur := Vector_Contour{first = len(dst.pts)}
		if on {append(&dst.pts, pts[0]); cur.count = 1}
		for i in 0 ..< segs {
			a, b := pts[i], pts[(i + 1) % len(pts)]
			d := b - a
			l := math.sqrt(d.x * d.x + d.y * d.y)
			at: f32 = 0
			for l - at > left {
				at += left
				q := a + d * (at / l)
				if on {
					append(&dst.pts, q); cur.count += 1
					if cur.count >= 2 do append(&dst.contours, cur)
					cur = {first = len(dst.pts)}
				} else {
					append(&dst.pts, q)
					cur = {first = len(dst.pts) - 1, count = 1}
				}
				on = !on
				k = (k + 1) % n
				left = max(dash.values[k], 0)
				if left <= 0 {
					// (A zero-length dash: a dot, drawn by the caps.)
					continue
				}
			}
			left -= l - at
			if on {append(&dst.pts, b); cur.count += 1}
		}
		if on && cur.count >= 2 do append(&dst.contours, cur)
	}
}
