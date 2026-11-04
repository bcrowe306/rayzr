package engine

import "core:log"
import "core:math"
import "core:testing"
import "core:time"
import lua "lua54"

// Phase 14 M0: vector paths, flattening, earcut, tessellation (fills with
// holes, strokes, anti-aliasing fringes), the cache's scale buckets and the
// node. Leaks: the test runner's tracking allocator.

@(private = "file")
tri_area :: proc(a, b, c: [2]f32) -> f32 {
	return abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) * 0.5
}

@(private = "file")
indices_area :: proc(pts: [][2]f32, idx: []u32) -> f32 {
	sum: f32
	for i := 0; i < len(idx); i += 3 do sum += tri_area(pts[idx[i]], pts[idx[i + 1]], pts[idx[i + 2]])
	return sum
}

// covered: a point inside a fully opaque triangle of the mesh.
@(private = "file")
covered :: proc(m: ^Vector_Mesh, p: [2]f32) -> bool {
	for i := 0; i < len(m.idx); i += 3 {
		a, b, c := m.idx[i], m.idx[i + 1], m.idx[i + 2]
		if m.cols[a].a == 0 || m.cols[b].a == 0 || m.cols[c].a == 0 do continue
		pa, pb, pc := m.verts[a], m.verts[b], m.verts[c]
		d1 := (p.x - pb.x) * (pa.y - pb.y) - (pa.x - pb.x) * (p.y - pb.y)
		d2 := (p.x - pc.x) * (pb.y - pc.y) - (pb.x - pc.x) * (p.y - pc.y)
		d3 := (p.x - pa.x) * (pc.y - pa.y) - (pc.x - pa.x) * (p.y - pa.y)
		neg := d1 < 0 || d2 < 0 || d3 < 0
		pos := d1 > 0 || d2 > 0 || d3 > 0
		if !(neg && pos) do return true
	}
	return false
}

@(test)
test_vector_flatten :: proc(t: ^testing.T) {
	p: Vector_Path
	Vector_Path_Init(&p)
	defer Vector_Path_Destroy(&p)
	Vector_Ellipse(&p, {10, 20}, {100, 100})
	f: Vector_Flat
	defer Vector_Flat_Destroy(&f)
	for tol in ([]f32{2, 0.25, 0.01}) {
		Vector_Flatten(&p, tol, &f)
		testing.expect_value(t, len(f.contours), 1)
		testing.expect(t, f.contours[0].closed, "closed")
		pts := Vector_Contour_Points(&f, f.contours[0])
		// (The cubic circle itself is off a true circle by 0.027%.)
		for q in pts {
			d := math.sqrt((q.x - 10) * (q.x - 10) + (q.y - 20) * (q.y - 20))
			testing.expectf(t, abs(d - 100) <= tol + 0.03, "tol %v: point at %v from the centre", tol, d)
		}
		// The first point isn't repeated at the end.
		testing.expect(t, pts[0] != pts[len(pts) - 1], "no closing duplicate")
	}
	// Finer tolerance: more points.
	Vector_Flatten(&p, 1, &f)
	coarse := len(f.pts)
	Vector_Flatten(&p, 0.01, &f)
	testing.expect(t, len(f.pts) > coarse * 4, "finer tolerance, more segments")
	// An open polyline and a lone move.
	Vector_Path_Clear(&p)
	Vector_MoveTo(&p, {0, 0}); Vector_LineTo(&p, {10, 0}); Vector_LineTo(&p, {10, 0}); Vector_LineTo(&p, {10, 10})
	Vector_MoveTo(&p, {50, 50})
	Vector_Flatten(&p, 0.25, &f)
	testing.expect_value(t, len(f.contours), 1)
	testing.expect_value(t, f.contours[0].count, 3) // (the duplicate dropped)
	testing.expect(t, !f.contours[0].closed, "open")
}

@(test)
test_vector_earcut :: proc(t: ^testing.T) {
	ec: Earcut
	defer Earcut_Destroy(&ec)
	out := make([dynamic]u32)
	defer delete(out)
	// Square: 2 triangles, both windings.
	sq := [][2]f32{{0, 0}, {10, 0}, {10, 10}, {0, 10}}
	testing.expect(t, Earcut_Triangulate(&ec, sq, nil, &out), "square")
	testing.expect_value(t, len(out), 6)
	testing.expect(t, abs(indices_area(sq, out[:]) - 100) < 1e-3, "square area")
	clear(&out)
	sqr := [][2]f32{{0, 0}, {0, 10}, {10, 10}, {10, 0}}
	Earcut_Triangulate(&ec, sqr, nil, &out)
	testing.expect(t, abs(indices_area(sqr, out[:]) - 100) < 1e-3, "reversed square area")
	// Concave (a star): the triangles cover exactly its area.
	star := make([dynamic][2]f32, context.temp_allocator)
	for i in 0 ..< 10 {
		a := f32(i) * math.PI / 5
		r: f32 = 100 if i % 2 == 0 else 40
		append(&star, [2]f32{math.cos(a) * r, math.sin(a) * r})
	}
	clear(&out)
	Earcut_Triangulate(&ec, star[:], nil, &out)
	testing.expect_value(t, len(out), 8 * 3)
	testing.expect(t, abs(indices_area(star[:], out[:]) - abs(Vector_SignedArea(star[:])) * 0.5) < 0.05, "star area")
	// A square with a square hole.
	holed := [][2]f32{{0, 0}, {10, 0}, {10, 10}, {0, 10}, {3, 3}, {3, 7}, {7, 7}, {7, 3}}
	clear(&out)
	Earcut_Triangulate(&ec, holed, []int{4}, &out)
	testing.expect(t, abs(indices_area(holed, out[:]) - (100 - 16)) < 1e-3, "holed area")
	// Big (z-order hashed: > 80 points): a 500-gon.
	big := make([dynamic][2]f32, context.temp_allocator)
	for i in 0 ..< 500 {
		a := f32(i) / 500 * 2 * math.PI
		append(&big, [2]f32{math.cos(a) * 300, math.sin(a) * 300})
	}
	clear(&out)
	Earcut_Triangulate(&ec, big[:], nil, &out)
	testing.expect_value(t, len(out), 498 * 3)
	testing.expect(t, abs(indices_area(big[:], out[:]) - abs(Vector_SignedArea(big[:])) * 0.5) < 1, "500-gon area")
	// Junk: too few points, all collinear, duplicates.
	clear(&out)
	testing.expect(t, !Earcut_Triangulate(&ec, [][2]f32{{0, 0}, {1, 1}}, nil, &out), "2 points")
	Earcut_Triangulate(&ec, [][2]f32{{0, 0}, {1, 1}, {2, 2}, {3, 3}}, nil, &out)
	Earcut_Triangulate(&ec, [][2]f32{{0, 0}, {0, 0}, {5, 0}, {5, 0}, {5, 5}}, nil, &out)
	// (A self-touching figure eight: no crash, some triangles.)
	Earcut_Triangulate(&ec, [][2]f32{{0, 0}, {10, 10}, {10, 0}, {0, 10}}, nil, &out)
}

@(test)
test_vector_tessellate_fill :: proc(t: ^testing.T) {
	shapes := make([dynamic]Vector_Shape)
	defer {
		for &s in shapes do Vector_Path_Destroy(&s.path)
		delete(shapes)
	}
	Vector_PresetShapes(.Ring, {255, 0, 0, 255}, {}, 0, &shapes)
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	m: Vector_Mesh
	defer Vector_Mesh_Destroy(&m)
	Vector_Tessellate(&tess, shapes[:], 1, &m)
	testing.expect(t, len(m.idx) > 0 && len(m.idx) % 3 == 0, "triangles")
	// Ring: outer radius 100, hole 55.
	testing.expect(t, covered(&m, {77, 0}), "the ring is filled")
	testing.expect(t, covered(&m, {0, -77}), "all around")
	testing.expect(t, !covered(&m, {0, 0}), "the hole is empty")
	testing.expect(t, !covered(&m, {30, 30}), "inside the hole")
	testing.expect(t, !covered(&m, {101, 0}), "outside")
	// The fringe fades out by the outline: transparent vertices exist, just past it.
	transparent := 0
	for c, i in m.cols do if c.a == 0 {
		transparent += 1
		r := math.sqrt(m.verts[i].x * m.verts[i].x + m.verts[i].y * m.verts[i].y)
		testing.expectf(t, abs(r - 100.5) < 0.6 || abs(r - 54.5) < 0.6, "fringe vertex at r=%v", r)
	}
	testing.expect(t, transparent > 0, "a fringe")
	testing.expect(t, m.bounds[0] < -100 && m.bounds[2] > 100, "bounds include the fringe")
	// Zoomed out (a pixel = 8 units): far fewer triangles, still a ring.
	fine := len(m.idx)
	Vector_Tessellate(&tess, shapes[:], 8, &m)
	testing.expect(t, len(m.idx) < fine / 2, "coarser when zoomed out")
	testing.expect(t, !covered(&m, {0, 0}), "the hole stays")
}

@(test)
test_vector_tessellate_stroke :: proc(t: ^testing.T) {
	shapes := make([dynamic]Vector_Shape)
	defer {
		for &s in shapes do Vector_Path_Destroy(&s.path)
		delete(shapes)
	}
	s := Vector_Shape{style = VECTOR_STYLE_DEFAULT}
	Vector_Path_Init(&s.path)
	s.style.fill = false
	s.style.stroke = true
	s.style.strokeWidth = 10
	s.style.join = .Miter
	s.style.cap = .Butt
	Vector_MoveTo(&s.path, {0, 0})
	Vector_LineTo(&s.path, {100, 0})
	Vector_LineTo(&s.path, {100, 100})
	append(&shapes, s)
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	m: Vector_Mesh
	defer Vector_Mesh_Destroy(&m)
	Vector_Tessellate(&tess, shapes[:], 1, &m)
	testing.expect(t, covered(&m, {50, 0}), "on the line")
	testing.expect(t, covered(&m, {50, 4}), "within half the width")
	testing.expect(t, !covered(&m, {50, 6}), "beyond it")
	testing.expect(t, covered(&m, {100, 50}), "the second segment")
	testing.expect(t, covered(&m, {104, -4}), "the miter corner")
	testing.expect(t, !covered(&m, {-3, 0}), "butt cap: nothing before the start")
	// Round caps reach half the width past the ends.
	shapes[0].style.cap = .Round
	Vector_Tessellate(&tess, shapes[:], 1, &m)
	testing.expect(t, covered(&m, {-3, 0}), "round cap")
	// Bevel: the corner's tip is cut.
	shapes[0].style.cap = .Butt
	shapes[0].style.join = .Bevel
	Vector_Tessellate(&tess, shapes[:], 1, &m)
	testing.expect(t, !covered(&m, {104.5, -4.5}), "bevel cuts the corner")
	// Hairline (0.25 px): drawn a pixel wide, fainter.
	shapes[0].style.strokeWidth = 0.25
	Vector_Tessellate(&tess, shapes[:], 1, &m)
	maxA: u8
	for c in m.cols do maxA = max(maxA, c.a)
	testing.expect(t, maxA > 0 && maxA < 100, "a faint hairline")
}

@(test)
test_vector_cache_buckets :: proc(t: ^testing.T) {
	shapes := make([dynamic]Vector_Shape)
	defer {
		for &s in shapes do Vector_Path_Destroy(&s.path)
		delete(shapes)
	}
	Vector_PresetShapes(.Character, {200, 60, 60, 255}, {30, 20, 10, 255}, 3, &shapes)
	testing.expect(t, len(shapes) > 190, "a busy character")
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	c: Vector_Cache
	defer Vector_Cache_Destroy(&c)
	testing.expect_value(t, Vector_PixelBucket(1), 1)
	testing.expect_value(t, Vector_PixelBucket(0.8), 1)
	testing.expect_value(t, Vector_PixelBucket(1.6), 2)
	testing.expect_value(t, Vector_PixelBucket(0.3), 0.25)
	Vector_Cache_Ensure(&c, &tess, shapes[:], 1)
	Vector_Cache_Ensure(&c, &tess, shapes[:], 0.9) // (same bucket)
	Vector_Cache_Ensure(&c, &tess, shapes[:], 1.2)
	testing.expect_value(t, c.stats.tessellations, 1)
	Vector_Cache_Ensure(&c, &tess, shapes[:], 0.4) // zoomed in 2.5x
	testing.expect_value(t, c.stats.tessellations, 2)
	c.dirty = true
	Vector_Cache_Ensure(&c, &tess, shapes[:], 0.4)
	testing.expect_value(t, c.stats.tessellations, 3)
	testing.expect(t, len(c.mesh.idx) > 3000, "thousands of triangles")
}

@(test)
test_vector_shape_node :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("vector", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	v := cast(^VectorShapeNode)Node_CreateByTypeName(scene, "VectorShapeNode")
	testing.expect(t, v != nil && v.typeId == VectorShapeNode, "created from the registry")
	VectorShapeNode_Build(v)
	testing.expect(t, len(v.shapes) == 1, "the star")
	v.preset = .Character
	VectorShapeNode_Build(v)
	testing.expect(t, len(v.shapes) > 190, "the character")
	// Properties round-trip through the scene file.
	v.preset = .Badge
	v.strokeWidth = 7
	json := Node_SerializeToJSON(v, scene.manager, context.temp_allocator)
	testing.expect(t, contains(json, `"preset": "Badge"`) && contains(json, `"strokeWidth": 7`), "saved")
}

@(private = "file")
contains :: proc(s, sub: string) -> bool {
	for i := 0; i + len(sub) <= len(s); i += 1 do if s[i:i + len(sub)] == sub do return true
	return false
}

// Cost of (re)tessellating the benchmark character (logged: the M0 numbers
// in engine/docs/vector.md); asserts only a generous ceiling.
@(test)
test_vector_tessellation_cost :: proc(t: ^testing.T) {
	shapes := make([dynamic]Vector_Shape)
	defer {
		for &s in shapes do Vector_Path_Destroy(&s.path)
		delete(shapes)
	}
	Vector_PresetShapes(.Character, {200, 60, 60, 255}, {30, 20, 10, 255}, 3, &shapes)
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	m: Vector_Mesh
	defer Vector_Mesh_Destroy(&m)
	for px in ([]f32{2, 1, 0.25}) {
		Vector_Tessellate(&tess, shapes[:], px, &m) // (warm the scratch buffers)
		start := time.tick_now()
		RUNS :: 20
		for _ in 0 ..< RUNS do Vector_Tessellate(&tess, shapes[:], px, &m)
		ms := time.duration_milliseconds(time.tick_since(start)) / RUNS
		log.infof("[vector] character at pixel %v: %v triangles, %v vertices, %.3f ms", px, len(m.idx) / 3, len(m.verts), ms)
		testing.expectf(t, ms < 50, "tessellation took %v ms", ms)
	}
}

// Fill rules (M1: Clipper2 normalization): self-intersections, overlapping
// contours, nesting in the same direction - each rule as SVG / Flash fill.
@(test)
test_vector_fill_rules :: proc(t: ^testing.T) {
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	m: Vector_Mesh
	defer Vector_Mesh_Destroy(&m)
	s := Vector_Shape{style = VECTOR_STYLE_DEFAULT}
	Vector_Path_Init(&s.path)
	shapes := []Vector_Shape{s}
	defer Vector_Path_Destroy(&shapes[0].path) // (the copy that grows)
	fill :: proc(tess: ^Vector_Tess, shapes: []Vector_Shape, rule: Vector_Fill_Rule, m: ^Vector_Mesh) {
		shapes[0].style.fillRule = rule
		Vector_Tessellate(tess, shapes, 1, m)
	}
	// A bowtie (one self-intersecting contour): both lobes, either rule.
	p := &shapes[0].path
	Vector_MoveTo(p, {0, 0}); Vector_LineTo(p, {100, 100}); Vector_LineTo(p, {100, 0}); Vector_LineTo(p, {0, 100}); Vector_Close(p)
	for rule in Vector_Fill_Rule {
		fill(&tess, shapes, rule, &m)
		testing.expectf(t, covered(&m, {20, 50}) && covered(&m, {80, 50}), "%v: both lobes", rule)
		testing.expectf(t, !covered(&m, {50, 20}), "%v: not between them", rule)
	}
	// Two overlapping squares, same direction: non-zero unites, even-odd cuts the overlap.
	Vector_Path_Clear(p)
	Vector_Rect(p, {0, 0}, {60, 60})
	Vector_Rect(p, {40, 40}, {100, 100})
	fill(&tess, shapes, .NonZero, &m)
	testing.expect(t, covered(&m, {50, 50}), "non-zero: the overlap is filled")
	testing.expect(t, covered(&m, {10, 10}) && covered(&m, {90, 90}), "non-zero: both squares")
	fill(&tess, shapes, .EvenOdd, &m)
	testing.expect(t, !covered(&m, {50, 50}), "even-odd: the overlap is empty")
	testing.expect(t, covered(&m, {10, 10}) && covered(&m, {90, 90}), "even-odd: both squares")
	// Concentric circles drawn the same way: non-zero fills the middle, even-odd makes a ring.
	Vector_Path_Clear(p)
	Vector_Ellipse(p, {0, 0}, {100, 100})
	Vector_Ellipse(p, {0, 0}, {50, 50})
	fill(&tess, shapes, .NonZero, &m)
	testing.expect(t, covered(&m, {0, 0}), "non-zero: same-direction inner circle filled")
	fill(&tess, shapes, .EvenOdd, &m)
	testing.expect(t, !covered(&m, {0, 0}) && covered(&m, {75, 0}), "even-odd: a ring")
	// An island in a hole in an outer (three levels).
	Vector_Ellipse(p, {0, 0}, {20, 20})
	fill(&tess, shapes, .EvenOdd, &m)
	testing.expect(t, covered(&m, {0, 0}) && !covered(&m, {35, 0}) && covered(&m, {75, 0}), "even-odd: island, hole, ring")
}

@(test)
test_vector_is_convex :: proc(t: ^testing.T) {
	testing.expect(t, Vector_IsConvex([][2]f32{{0, 0}, {10, 0}, {10, 10}, {0, 10}}), "square")
	testing.expect(t, Vector_IsConvex([][2]f32{{0, 0}, {0, 10}, {10, 10}, {10, 0}}), "square, other way")
	testing.expect(t, !Vector_IsConvex([][2]f32{{0, 0}, {10, 0}, {5, 2}, {10, 10}, {0, 10}}), "a dent")
	testing.expect(t, !Vector_IsConvex([][2]f32{{0, 0}, {100, 100}, {100, 0}, {0, 100}}), "a bowtie")
	// A pentagram traced point to point turns the same way but twice round.
	star := make([dynamic][2]f32, context.temp_allocator)
	for i in 0 ..< 5 {
		a := f32(i * 2) * math.PI * 2 / 5
		append(&star, [2]f32{math.cos(a), math.sin(a)} * 50)
	}
	testing.expect(t, !Vector_IsConvex(star[:]), "a self-crossing pentagram")
}

// Paints (M1): gradient coordinates, colours, spreads, transforms; the mesh's
// baked rows and per-vertex modes; dashes; opacity.
@(test)
test_vector_paints :: proc(t: ^testing.T) {
	stops := []Vector_Stop{{0, {0, 0, 0, 255}}, {1, {255, 255, 255, 255}}}
	lin := Vector_LinearGradient({0, 0}, {100, 0}, stops)
	testing.expect_value(t, Vector_PaintCoord(&lin, {50, 30}).x, 0.5)
	testing.expect_value(t, Vector_PaintCoord(&lin, {150, 0}).x, 1.5)
	c := Vector_PaintColorAt(&lin, 0.5)
	testing.expect(t, c.r >= 127 && c.r <= 128 && c.a == 255, "halfway grey")
	testing.expect_value(t, Vector_PaintSpread(.Pad, 1.5), 1)
	testing.expect_value(t, Vector_PaintSpread(.Repeat, 1.25), 0.25)
	testing.expect_value(t, Vector_PaintSpread(.Reflect, 1.25), 0.75)
	testing.expect_value(t, Vector_PaintSpread(.Reflect, -0.25), 0.25)
	rad := Vector_RadialGradient({10, 10}, 20, stops)
	g := Vector_PaintCoord(&rad, {30, 10})
	testing.expect(t, abs(g.x - 1) < 1e-5 && abs(g.y) < 1e-5, "radial: one radius out")
	// A transform moves the gradient: its centre is now at (110, 10).
	rad.transform = {1, 0, 0, 1, 100, 0}
	g = Vector_PaintCoord(&rad, {110, 10})
	testing.expect(t, abs(g.x) < 1e-5 && abs(g.y) < 1e-5, "transformed centre")
	// Scaled 2x: one radius is 40 units.
	rad.transform = {2, 0, 0, 2, 0, 0}
	g = Vector_PaintCoord(&rad, {60, 20})
	testing.expect(t, abs(g.x - 1) < 1e-5, "scaled gradient")
	// Multi-stop interpolation.
	three := Vector_LinearGradient({0, 0}, {1, 0}, {{0, {255, 0, 0, 255}}, {0.5, {0, 255, 0, 255}}, {1, {0, 0, 255, 255}}})
	testing.expect_value(t, Vector_PaintColorAt(&three, 0.5), [4]u8{0, 255, 0, 255})
	testing.expect_value(t, Vector_PaintColorAt(&three, 0.75), [4]u8{0, 128, 128, 255})

	// The preset: rows baked, gradient vertices tagged, dashes cut, opacity applied.
	shapes := make([dynamic]Vector_Shape)
	defer {
		for &s in shapes do Vector_Path_Destroy(&s.path)
		delete(shapes)
	}
	Vector_PresetShapes(.Gradients, {255, 200, 0, 255}, {40, 20, 10, 255}, 3, &shapes)
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	m: Vector_Mesh
	defer Vector_Mesh_Destroy(&m)
	Vector_Tessellate(&tess, shapes[:], 1, &m)
	testing.expect_value(t, len(m.gradients), 3) // sky, stripes, orb
	testing.expect_value(t, len(m.gc), len(m.verts))
	testing.expect_value(t, len(m.gi), len(m.verts))
	modes: [16]int
	for gi in m.gi do modes[int(gi.y)] += 1
	testing.expect(t, modes[0] > 0, "solid vertices (strokes, the glass)")
	testing.expect(t, modes[1 + 0 + int(Vector_Spread.Pad)] > 0, "linear pad (the sky)")
	testing.expect(t, modes[1 + 0 + int(Vector_Spread.Reflect)] > 0, "linear reflect (the stripes)")
	testing.expect(t, modes[1 + 4 + int(Vector_Spread.Pad)] > 0, "radial (the orb)")
	// The sky's row: dark blue at the top, warm at the bottom.
	testing.expect(t, m.gradients[0][0].b > 150 && m.gradients[0][255].r > 250, "baked sky row")
	// The glass: 35% opacity.
	testing.expect(t, covered(&m, {80, -80}), "the glass is drawn")
	found := false
	for col, i in m.cols do if m.verts[i] == {20 + 0.5, -90 + 0.5} || (abs(m.verts[i].x - 20.5) < 0.01 && abs(m.verts[i].y + 89.5) < 0.01) {
		testing.expectf(t, col.a == 89, "opacity alpha %v", col.a)
		found = true
	}
	testing.expect(t, found, "a glass corner vertex")
}

@(test)
test_vector_dashes :: proc(t: ^testing.T) {
	s := Vector_Shape{style = VECTOR_STYLE_DEFAULT}
	Vector_Path_Init(&s.path)
	defer Vector_Path_Destroy(&s.path)
	s.style.fill = false
	s.style.stroke = true
	s.style.strokeWidth = 4
	s.style.cap = .Butt
	s.style.dash = {count = 2, values = {10, 10, 0, 0, 0, 0, 0, 0}}
	Vector_MoveTo(&s.path, {0, 0}); Vector_LineTo(&s.path, {100, 0})
	shapes := []Vector_Shape{s}
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	m: Vector_Mesh
	defer Vector_Mesh_Destroy(&m)
	Vector_Tessellate(&tess, shapes, 1, &m)
	testing.expect_value(t, len(tess.dashed.contours), 5) // 0-10, 20-30, ... 80-90
	testing.expect(t, covered(&m, {5, 0}) && covered(&m, {25, 0}) && covered(&m, {85, 0}), "dashes")
	testing.expect(t, !covered(&m, {15, 0}) && !covered(&m, {35, 0}) && !covered(&m, {95, 0}), "gaps")
	// Offset 5: starts halfway through a dash.
	shapes[0].style.dash.offset = 5
	Vector_Tessellate(&tess, shapes, 1, &m)
	testing.expect(t, covered(&m, {2, 0}) && !covered(&m, {8, 0}) && covered(&m, {18, 0}), "offset shifts the pattern")
	// A closed square's dashes go round the corner.
	Vector_Path_Clear(&shapes[0].path)
	Vector_Rect(&shapes[0].path, {0, 0}, {40, 40})
	shapes[0].style.dash = {count = 2, values = {30, 10, 0, 0, 0, 0, 0, 0}}
	Vector_Tessellate(&tess, shapes, 1, &m)
	testing.expect_value(t, len(tess.dashed.contours), 4)
	testing.expect(t, covered(&m, {40, 15}), "a dash turned the corner")
}

// The Lua drawing API (M1 V.3): on_draw records paths and styles in the
// node's local space; transforms, gradients, dashes; the same drawing
// twice isn't re-tessellated; Vector.* outside on_draw is an error.
@(test)
test_vector_lua_on_draw :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("vector_draw.lua", `
local D = {}
D.properties = { wave = { type = "float", default = 0 } }
function D:on_draw()
    Vector.fill_color("#ff8800")
    Vector.rect(-50, -20, 100, 40)
    Vector.fill()
    Vector.save()
    Vector.translate(200, 0)
    Vector.scale(2)
    Vector.begin_path()
    Vector.circle(0, 0, 10 + self.wave)
    Vector.fill_paint(Vector.radial_gradient(0, 0, 10, { {0, "#ffffff"}, {1, {0, 0, 1, 1}} }))
    Vector.fill()
    Vector.stroke_color(0, 0, 0, 1)
    Vector.stroke_width(3)
    Vector.dash({4, 2})
    Vector.stroke()
    Vector.restore()
    Vector.begin_path()
    Vector.move_to(0, 50)
    Vector.arc(0, 50, 30, 0, 180)
    Vector.line_join("round")
    Vector.line_cap("round")
    Vector.stroke()
end
return D
`)
	ScriptVFS_RegisterEmbedded("vector_outside.lua", `
local O = {}
function O:ready()
    ok_outside, err_outside = pcall(function() Vector.rect(0, 0, 1, 1) end)
end
return O
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("vectordraw", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	n := Node_CreateByTypeName(scene, "Node")
	n.gameContext = &game.gameContext
	Script_AttachToNode(n, "vector_draw.lua", nil, &game.scriptManager)
	o := Node_CreateByTypeName(scene, "Node")
	o.gameContext = &game.gameContext
	Script_AttachToNode(o, "vector_outside.lua", nil, &game.scriptManager)
	game->run(0.016)

	testing.expect(t, Script_HasDraw(n, &game.scriptManager), "on_draw found")
	testing.expect(t, !Script_HasDraw(o, &game.scriptManager), "no on_draw")
	cv := Script_RunDraw(n, &game.gameContext)
	testing.expect(t, cv != nil, "recorded")
	shapes := Vector_CanvasShapes(cv)
	testing.expect_value(t, len(shapes), 4) // rect fill, circle fill, circle stroke, arc stroke
	testing.expect_value(t, shapes[0].style.fillColor, [4]u8{255, 136, 0, 255})
	testing.expect(t, shapes[0].style.fill && !shapes[0].style.stroke, "a fill")
	// The circle: translated 200 and scaled 2 -> its points around (200, 0), radius 20.
	maxX: f32
	for p in shapes[1].path.pts do maxX = max(maxX, p.x)
	testing.expect(t, abs(maxX - 220) < 0.01, "transformed points")
	testing.expect_value(t, shapes[1].style.fillPaint.kind, Vector_Paint_Kind.Radial)
	testing.expect_value(t, shapes[1].style.fillPaint.stopCount, 2)
	// The stroke scaled with the transform (3 * 2), the dash too.
	testing.expect_value(t, shapes[2].style.strokeWidth, 6)
	testing.expect_value(t, shapes[2].style.dash.values[0], 8)
	// After restore: back to the identity, round joins.
	testing.expect_value(t, shapes[3].style.join, Vector_Join.Round)
	testing.expect_value(t, shapes[3].style.strokeWidth, 1)
	// The same drawing: the cache isn't dirtied; a change is.
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	Vector_Cache_Ensure(&cv.cache, &tess, shapes, 1)
	before := cv.cache.stats.tessellations
	cv = Script_RunDraw(n, &game.gameContext)
	Vector_Cache_Ensure(&cv.cache, &tess, Vector_CanvasShapes(cv), 1)
	testing.expect_value(t, cv.cache.stats.tessellations, before)
	ScriptInstance_SetProperty(cast(^ScriptInstance)n.scriptInstance, "wave", ScriptValue{type = .Float, valFloat = 5}, &game.scriptManager)
	cv = Script_RunDraw(n, &game.gameContext)
	Vector_Cache_Ensure(&cv.cache, &tess, Vector_CanvasShapes(cv), 1)
	testing.expect_value(t, cv.cache.stats.tessellations, before + 1)
	// Outside on_draw: an error.
	L := game.scriptManager.L
	lua.getglobal(L, "ok_outside")
	testing.expect(t, !bool(lua.toboolean(L, -1)), "Vector outside on_draw fails")
	lua.pop(L, 1)
}

// Clip paths (M1): fills and strokes cut to a region (its own fill rule),
// from Odin and from Lua (Vector.clip until restore).
@(test)
test_vector_clip :: proc(t: ^testing.T) {
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	m: Vector_Mesh
	defer Vector_Mesh_Destroy(&m)
	k: Vector_Clip
	Vector_Path_Init(&k.path)
	defer Vector_Path_Destroy(&k.path)
	Vector_Ellipse(&k.path, {0, 0}, {50, 50})
	s := Vector_Shape{style = VECTOR_STYLE_DEFAULT, clip = &k}
	Vector_Path_Init(&s.path)
	Vector_Rect(&s.path, {-100, -10}, {100, 10})
	shapes := []Vector_Shape{s}
	defer Vector_Path_Destroy(&shapes[0].path) // (the copy that grows)
	Vector_Tessellate(&tess, shapes, 1, &m)
	testing.expect(t, covered(&m, {0, 0}) && covered(&m, {45, 0}), "inside the clip")
	testing.expect(t, !covered(&m, {60, 0}) && !covered(&m, {-80, 0}), "cut outside it")
	// A stroke is clipped too (its outline: open line, round caps).
	shapes[0].style.fill = false
	shapes[0].style.stroke = true
	shapes[0].style.strokeWidth = 8
	Vector_Path_Clear(&shapes[0].path)
	Vector_MoveTo(&shapes[0].path, {-100, 30}); Vector_LineTo(&shapes[0].path, {100, 30})
	Vector_Tessellate(&tess, shapes, 1, &m)
	testing.expect(t, covered(&m, {0, 30}) && covered(&m, {0, 33}), "stroke inside")
	testing.expect(t, !covered(&m, {48, 30}) && !covered(&m, {-90, 30}), "stroke cut at the circle")
	// A closed stroke (a ring) clipped to the right half.
	Vector_Path_Clear(&k.path)
	Vector_Rect(&k.path, {0, -100}, {100, 100})
	Vector_Path_Clear(&shapes[0].path)
	Vector_Ellipse(&shapes[0].path, {0, 0}, {40, 40})
	Vector_Tessellate(&tess, shapes, 1, &m)
	testing.expect(t, covered(&m, {40, 0}) && !covered(&m, {-40, 0}), "half a ring")
	testing.expect(t, !covered(&m, {20, 0}), "the ring's middle stays empty")
	// The clip's own rule: an even-odd ring clip leaves its hole out.
	Vector_Path_Clear(&k.path)
	Vector_Ellipse(&k.path, {0, 0}, {60, 60})
	Vector_Ellipse(&k.path, {0, 0}, {30, 30})
	k.rule = .EvenOdd
	shapes[0].style.fill = true
	shapes[0].style.stroke = false
	Vector_Path_Clear(&shapes[0].path)
	Vector_Rect(&shapes[0].path, {-100, -100}, {100, 100})
	Vector_Tessellate(&tess, shapes, 1, &m)
	testing.expect(t, covered(&m, {45, 0}) && !covered(&m, {0, 0}) && !covered(&m, {80, 0}), "a ring-shaped clip")
}

// #331: two-stop linear pad gradients within their 0..1 become vertex
// colours (the plain shader; the same pixels); anything else keeps its
// per-pixel gradient.
@(test)
test_vector_bake_linear_gradients :: proc(t: ^testing.T) {
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	mesh_of :: proc(tess: ^Vector_Tess, m: ^Vector_Mesh, paint: Vector_Paint) {
		s := Vector_Shape{style = VECTOR_STYLE_DEFAULT}
		Vector_Path_Init(&s.path)
		defer Vector_Path_Destroy(&s.path)
		Vector_Rect(&s.path, {0, 0}, {100, 100})
		s.style.fill = true
		s.style.stroke = false
		s.style.fillPaint = paint
		shapes := []Vector_Shape{s}
		Vector_Tessellate(tess, shapes, 1, m)
	}
	gradient_verts :: proc(m: ^Vector_Mesh) -> int {
		n := 0
		for g in m.gi do if g.y > 0 do n += 1
		return n
	}
	red, blue := [4]u8{255, 0, 0, 255}, [4]u8{0, 0, 255, 255}
	{
		// A sky: top to bottom, two stops - baked.
		m: Vector_Mesh
		defer Vector_Mesh_Destroy(&m)
		mesh_of(&tess, &m, Vector_LinearGradient({0, 0}, {0, 100}, {{0, red}, {1, blue}}))
		testing.expect(t, len(m.verts) > 0, "tessellated")
		testing.expect_value(t, gradient_verts(&m), 0)
		testing.expect_value(t, len(m.gradients), 0) // (no texture: the plain shader)
		for v, i in m.verts {
			tt := v.y / 100
			want := [2]f32{clamp(255 * (1 - tt), 0, 255), clamp(255 * tt, 0, 255)}
			col := m.cols[i]
			testing.expectf(t, abs(f32(col.r) - want[0]) <= 1 && abs(f32(col.b) - want[1]) <= 1 && col.g == 0, "vertex %v: %v (want r %v b %v)", v, col, want[0], want[1])
		}
		testing.expect(t, covered(&m, {50, 50}), "drawn")
	}
	kept :: proc(t: ^testing.T, tess: ^Vector_Tess, paint: Vector_Paint, what: string) {
		m: Vector_Mesh
		defer Vector_Mesh_Destroy(&m)
		mesh_of(tess, &m, paint)
		testing.expectf(t, gradient_verts(&m) == len(m.verts) && len(m.gradients) == 1, "%s: per pixel (%d of %d gradient vertices)", what, gradient_verts(&m), len(m.verts))
	}
	kept(t, &tess, Vector_LinearGradient({0, 0}, {0, 100}, {{0, red}, {0.5, {0, 255, 0, 255}}, {1, blue}}), "three stops")
	kept(t, &tess, Vector_LinearGradient({0, 0}, {0, 50}, {{0, red}, {1, blue}}), "padded past its end")
	kept(t, &tess, Vector_LinearGradient({0, 0}, {0, 100}, {{0, red}, {1, blue}}, .Reflect), "reflect")
	kept(t, &tess, Vector_RadialGradient({50, 50}, 50, {{0, red}, {1, blue}}), "radial")
}
