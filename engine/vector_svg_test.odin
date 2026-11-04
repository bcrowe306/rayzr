package engine

import "core:math"
import os "osx"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"

// SVG import (Phase 14 M2): the path grammar, arcs, colours, transforms,
// units, CSS, inheritance, gradients, clips, groups and warnings - on
// fixtures shaped like Inkscape / Illustrator / Affinity / Figma exports
// (tests/vector/svg).

@(private = "file")
SVG_INKSCAPE :: #load("../tests/vector/svg/inkscape_character.svg", string)
@(private = "file")
SVG_ILLUSTRATOR :: #load("../tests/vector/svg/illustrator_css.svg", string)
@(private = "file")
SVG_AFFINITY :: #load("../tests/vector/svg/affinity_presentation.svg", string)
@(private = "file")
SVG_FIGMA :: #load("../tests/vector/svg/figma_export.svg", string)

@(private = "file")
shape_box :: proc(s: ^Vector_Shape) -> [4]f32 {
	b := [4]f32{max(f32), max(f32), min(f32), min(f32)}
	for p in s.path.pts {
		b[0] = min(b[0], p.x); b[1] = min(b[1], p.y)
		b[2] = max(b[2], p.x); b[3] = max(b[3], p.y)
	}
	return b
}

@(private = "file")
near :: proc(a, b: f32, eps: f32 = 0.01) -> bool {return abs(a - b) <= eps}

@(test)
test_svg_path_grammar :: proc(t: ^testing.T) {
	p: Vector_Path
	Vector_Path_Init(&p)
	defer Vector_Path_Destroy(&p)
	// Absolute / relative, implicit lines after M, H / V, smooth curves, packed numbers.
	Vector_ParsePathData("M10 10 20 10 h10 v10 H10 z m5,5 l5-5 c1,2,3,4,5,6 s7,8,9,10 Q0 0 1 1 T 4 4 .5.5", &p)
	cmds := p.cmds[:]
	testing.expect_value(t, cmds[0], Vector_Cmd.Move)
	testing.expect_value(t, cmds[1], Vector_Cmd.Line) // (implicit)
	testing.expect_value(t, p.pts[1], [2]f32{20, 10})
	testing.expect_value(t, p.pts[2], [2]f32{30, 10}) // h10
	testing.expect_value(t, p.pts[3], [2]f32{30, 20}) // v10
	testing.expect_value(t, p.pts[4], [2]f32{10, 20}) // H10
	testing.expect_value(t, cmds[5], Vector_Cmd.Close)
	testing.expect_value(t, p.pts[5], [2]f32{15, 15}) // m5,5 from the subpath start (10, 10)
	testing.expect_value(t, p.pts[6], [2]f32{20, 10}) // l5-5
	// s reflects the previous control point: c ended at (25, 16) with c2 (23, 14).
	ci := 0
	for c, i in cmds do if c == .Cubic {ci = i; break}
	_ = ci
	last := p.pts[len(p.pts) - 1]
	testing.expect(t, near(last.x, 0.5) && near(last.y, 0.5), "T then an implicit absolute T with packed .5.5")
	// Exponents and arc flags packed together.
	Vector_Path_Clear(&p)
	Vector_ParsePathData("M0 0L1e2 0a50 50 0 0150 50", &p)
	testing.expect_value(t, p.pts[1], [2]f32{100, 0})
	end := p.pts[len(p.pts) - 1]
	testing.expect(t, near(end.x, 150) && near(end.y, 50), "packed arc flags")
	// Junk stops the parse without crashing.
	Vector_Path_Clear(&p)
	Vector_ParsePathData("M 0 0 L 10 x 20", &p)
	testing.expect_value(t, len(p.cmds), 1)
}

@(test)
test_svg_arcs :: proc(t: ^testing.T) {
	p: Vector_Path
	Vector_Path_Init(&p)
	defer Vector_Path_Destroy(&p)
	// A half circle of radius 50 from (0, 0) to (100, 0), sweeping through (50, -50) or (50, 50).
	Vector_ParsePathData("M0 0 A50 50 0 0 1 100 0", &p)
	f: Vector_Flat
	defer Vector_Flat_Destroy(&f)
	Vector_Flatten(&p, 0.05, &f)
	minY, maxY: f32 = 1e9, -1e9
	for q in f.pts {
		d := math.sqrt((q.x - 50) * (q.x - 50) + q.y * q.y)
		testing.expectf(t, abs(d - 50) < 0.2, "on the circle: %v", d)
		minY = min(minY, q.y); maxY = max(maxY, q.y)
	}
	testing.expect(t, near(minY, -50, 0.2) && maxY < 0.01, "sweep 1 goes up (screen: clockwise)")
	// Radii too small are scaled up; zero radii are a line.
	Vector_Path_Clear(&p)
	Vector_ParsePathData("M0 0 A1 1 0 0 0 100 0", &p)
	testing.expect(t, near(p.pts[len(p.pts) - 1].x, 100), "small radii scaled")
	Vector_Path_Clear(&p)
	Vector_ParsePathData("M0 0 A0 10 0 0 0 100 0", &p)
	testing.expect_value(t, p.cmds[1], Vector_Cmd.Line)
}

@(test)
test_svg_colors_transforms :: proc(t: ^testing.T) {
	c, ok := Vector_ParseColor("#f80")
	testing.expect(t, ok && c == {255, 136, 0, 255}, "#rgb")
	c, _ = Vector_ParseColor("#11223344")
	testing.expect_value(t, c, [4]u8{0x11, 0x22, 0x33, 0x44})
	c, _ = Vector_ParseColor("rgb(255, 0, 128)")
	testing.expect_value(t, c, [4]u8{255, 0, 128, 255})
	c, _ = Vector_ParseColor("rgba(100%, 50%, 0%, 0.5)")
	testing.expect_value(t, c, [4]u8{255, 127, 0, 128})
	c, _ = Vector_ParseColor("hsl(120, 100%, 50%)")
	testing.expect_value(t, c, [4]u8{0, 255, 0, 255})
	c, _ = Vector_ParseColor("RebeccaPurple")
	testing.expect_value(t, c, [4]u8{0x66, 0x33, 0x99, 255})
	_, ok = Vector_ParseColor("notacolour")
	testing.expect(t, !ok, "unknown")
	m := Vector_ParseTransform("translate(10, 20) scale(2)")
	testing.expect_value(t, m, [6]f32{2, 0, 0, 2, 10, 20})
	m = Vector_ParseTransform("rotate(90 10 10)")
	// (10, 0) rotated 90 degrees about (10, 10) -> (20, 10).
	x := m[0] * 10 + m[2] * 0 + m[4]
	y := m[1] * 10 + m[3] * 0 + m[5]
	testing.expect(t, near(x, 20) && near(y, 10), "rotate about a point")
	m = Vector_ParseTransform("matrix(1,0,0,1,5,6)skewX(0)")
	testing.expect_value(t, m, [6]f32{1, 0, 0, 1, 5, 6})
}

@(test)
test_svg_inkscape :: proc(t: ^testing.T) {
	doc: Vector_Doc
	defer Vector_Doc_Destroy(&doc)
	testing.expect(t, Vector_LoadSVG(SVG_INKSCAPE, &doc), "loaded")
	// 200mm with a 200-unit viewBox: 1 unit = 3.78 px.
	testing.expect(t, near(doc.size.x, 755.9, 0.2), "mm size")
	// Body, its button, head, 2 eyes, mouth (the display:none path and the text are skipped).
	testing.expect_value(t, len(doc.shapes), 6)
	// Layers as groups, by their labels.
	names := make([dynamic]string, context.temp_allocator)
	for g in doc.groups do append(&names, g.name)
	testing.expect(t, len(names) == 2 && names[0] == "Body" && names[1] == "Head", "layer labels")
	testing.expect_value(t, doc.groups[1].count, 4)
	// The body: blue fill, dark stroke scaled with the document (2.5 units).
	body := &doc.shapes[0]
	testing.expect_value(t, body.style.fillColor, [4]u8{0x5b, 0x7f, 0xd6, 255})
	testing.expect(t, near(body.style.strokeWidth, 2.5 * 3.7795, 0.01), "stroke width in px")
	testing.expect_value(t, body.style.join, Vector_Join.Round)
	// The layer's translate(0,10) is baked: the body's top is at (110 + 10) units.
	testing.expect(t, near(shape_box(body)[1], 120 * 3.7795, 0.1), "group transform baked")
	// The head: a radial gradient through the xlink:href chain (2 stops), user space.
	head := &doc.shapes[2]
	testing.expect_value(t, head.style.fillPaint.kind, Vector_Paint_Kind.Radial)
	testing.expect_value(t, head.style.fillPaint.stopCount, 2)
	testing.expect_value(t, head.style.fillPaint.stops[0].color, [4]u8{0xff, 0xd5, 0xa8, 255})
	// The gradient's centre maps to the head's centre in document space.
	g := Vector_PaintCoord(&head.style.fillPaint, {100 * 3.7795, 70 * 3.7795})
	testing.expect(t, abs(g.x) < 0.01 && abs(g.y) < 0.01, "gradient centre at the head's")
	// The mouth: an arc, round caps, no fill.
	mouth := &doc.shapes[5]
	testing.expect(t, !mouth.style.fill && mouth.style.stroke && mouth.style.cap == .Round, "the mouth's stroke")
	// Warnings: the text, the focal point.
	all := strings.join(doc.warnings[:], "|", context.temp_allocator)
	testing.expect(t, strings.contains(all, "text isn't supported"), "text warning")
	testing.expect(t, strings.contains(all, "focal"), "focal warning")
}

@(test)
test_svg_illustrator :: proc(t: ^testing.T) {
	doc: Vector_Doc
	defer Vector_Doc_Destroy(&doc)
	testing.expect(t, Vector_LoadSVG(SVG_ILLUSTRATOR, &doc), "loaded")
	testing.expect_value(t, doc.size, [2]f32{240, 160}) // (no width / height: the viewBox)
	// Sun circle, star polygon, polyline, clipped circle, gradient path, faded rect.
	testing.expect_value(t, len(doc.shapes), 6)
	testing.expect_value(t, doc.shapes[0].style.fillColor, [4]u8{0xe8, 0xb0, 0x4a, 255}) // .st0
	poly := &doc.shapes[1]
	testing.expect(t, !poly.style.fill && poly.style.stroke && near(poly.style.strokeWidth, 3), ".st1: stroke only")
	testing.expect_value(t, poly.style.miterLimit, 10)
	testing.expect_value(t, poly.path.cmds[len(poly.path.cmds) - 1], Vector_Cmd.Close) // polygon closes
	testing.expect(t, doc.shapes[2].path.cmds[len(doc.shapes[2].path.cmds) - 1] != .Close, "polyline stays open")
	// The clip (from <clipPath><use href=rect>) is the 60x60 square.
	clipped := &doc.shapes[3]
	testing.expect(t, clipped.clip != nil, "clipped")
	if clipped.clip != nil {
		b := [4]f32{max(f32), max(f32), min(f32), min(f32)}
		for q in clipped.clip.path.pts {
			b[0] = min(b[0], q.x); b[1] = min(b[1], q.y)
			b[2] = max(b[2], q.x); b[3] = max(b[3], q.y)
		}
		testing.expect_value(t, b, [4]f32{100, 20, 160, 80})
	}
	grad := &doc.shapes[4]
	testing.expect_value(t, grad.style.fillPaint.kind, Vector_Paint_Kind.Linear)
	testing.expect_value(t, grad.style.fillPaint.stopCount, 3)
	testing.expect(t, near(doc.shapes[5].style.opacity, 0.5), ".st4 opacity")
	testing.expect_value(t, doc.groups[0].name, "Sun")
}

@(test)
test_svg_affinity_figma :: proc(t: ^testing.T) {
	doc: Vector_Doc
	testing.expect(t, Vector_LoadSVG(SVG_AFFINITY, &doc), "affinity")
	// The artboard's empty rect (fill:none) is dropped: leaf and triangle.
	testing.expect_value(t, len(doc.shapes), 2)
	leaf := &doc.shapes[0]
	testing.expect_value(t, leaf.style.fillRule, Vector_Fill_Rule.EvenOdd) // inherited from the root's style
	testing.expect_value(t, leaf.style.fillColor, [4]u8{76, 175, 80, 255})
	testing.expect(t, near(leaf.style.strokeWidth, 4 * math.sqrt(f32(0.68)), 0.01), "stroke scaled by the matrix")
	testing.expect_value(t, doc.groups[1].name, "Leaf")
	testing.expect_value(t, doc.shapes[1].style.fillColor.a, 204) // fill-opacity 0.8
	Vector_Doc_Destroy(&doc)

	testing.expect(t, Vector_LoadSVG(SVG_FIGMA, &doc), "figma")
	defer Vector_Doc_Destroy(&doc)
	testing.expect_value(t, len(doc.shapes), 3)
	// The group's clip-path (a rounded rect) clips all three.
	for &sh in doc.shapes do testing.expect(t, sh.clip != nil, "the group's clip")
	// The rect: a gradient with rounded corners.
	rect := &doc.shapes[0]
	testing.expect_value(t, rect.style.fillPaint.kind, Vector_Paint_Kind.Linear)
	testing.expect(t, len(rect.path.cmds) > 5, "rounded corners")
	ring := &doc.shapes[1]
	testing.expect_value(t, ring.style.fillRule, Vector_Fill_Rule.EvenOdd)
	testing.expect_value(t, ring.style.fillColor.a, 230)
	line := &doc.shapes[2]
	testing.expect_value(t, line.style.dash.count, 2)
	testing.expect_value(t, line.style.cap, Vector_Cap.Round)
	// Tessellating the imported shapes works (the ring keeps its hole).
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	m: Vector_Mesh
	defer Vector_Mesh_Destroy(&m)
	Vector_Tessellate(&tess, doc.shapes[1:2], 1, &m)
	testing.expect(t, len(m.idx) > 0, "tessellated")
}

@(test)
test_svg_rejects :: proc(t: ^testing.T) {
	doc: Vector_Doc
	defer Vector_Doc_Destroy(&doc)
	testing.expect(t, !Vector_LoadSVG("not xml at all", &doc), "junk")
	Vector_Doc_Destroy(&doc)
	testing.expect(t, !Vector_LoadSVG("<html><body/></html>", &doc), "not svg")
	Vector_Doc_Destroy(&doc)
	// A <use> loop doesn't hang.
	testing.expect(t, Vector_LoadSVG(`<svg xmlns="http://www.w3.org/2000/svg"><g id="a"><use href="#a"/></g></svg>`, &doc), "loop")
}

// Vector assets (M2): shared per path, reloaded when the file changes, the
// node's file / origin / bounds / hit test, culling bounds.
@(test)
test_vector_asset_resource :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("vasset", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	dir, _ := filepath.join({Engine_TempDir(), "rayzr_vector_asset_test"}, context.temp_allocator)
	_ = os.make_directory_all(dir)
	path := strings.concatenate({dir, "/ring.svg"}, context.temp_allocator)
	write :: proc(path, text: string) {_ = os.write_entire_file(path, transmute([]u8)text)}
	write(path, `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><path fill-rule="evenodd" fill="#f00" d="M0 0H100V100H0Z M30 30V70H70V30Z"/></svg>`)
	a := cast(^VectorShapeNode)Node_CreateByTypeName(scene, "VectorShapeNode")
	b := cast(^VectorShapeNode)Node_CreateByTypeName(scene, "VectorShapeNode")
	a.gameContext, b.gameContext = &game.gameContext, &game.gameContext
	a.file, b.file = path, path
	ra, rb := VectorShapeNode_Asset(a), VectorShapeNode_Asset(b)
	testing.expect(t, ra != nil && ra == rb, "one shared resource")
	testing.expect_value(t, ra.refs, 2)
	testing.expect_value(t, Vector_ResourceCount(&game.resourceManager), 1)
	testing.expect_value(t, VectorShapeNode_Size(a), [2]f32{100, 100})
	testing.expect(t, Node_HasOrigin(a), "an origin with a file")
	// Bounds: centred on the node (origin 0.5, 0.5).
	lb, ok := VectorShapeNode_LocalBounds(a)
	testing.expect(t, ok && lb == {-50, -50, 50, 50}, "local bounds centred")
	a.globalPosition = {200, 100}
	a.globalScale = {2, 2}
	cr, cok := Node_RenderBounds(a)
	testing.expect(t, cok && cr.x == 100 && cr.y == 0 && cr.width == 200, "culling bounds")
	// #390: mirrored with a corner pivot - the art is to the left of the
	// position (the matrix flips it round the position), and so the bounds.
	a.pivot = {0, 0}
	a.globalPosition = {2560, 0}
	a.globalScale = {-1, 1}
	cr, cok = Node_RenderBounds(a)
	testing.expectf(t, cok && cr == {2460, 0, 100, 100}, "flipped corner-pivot bounds: %v", cr)
	a.globalScale = {1, -2}
	cr, cok = Node_RenderBounds(a)
	testing.expectf(t, cok && cr == {2560, -200, 100, 200}, "flipped vertically: %v", cr)
	a.globalRotation = 90
	cr, cok = Node_RenderBounds(a)
	testing.expectf(t, cok && abs(cr.x - 2560) < 0.01 && abs(cr.y) < 0.01 && abs(cr.width - 200) < 0.01 && abs(cr.height - 100) < 0.01, "flipped and rotated: %v", cr)
	a.pivot = {0.5, 0.5}
	a.globalPosition, a.globalScale, a.globalRotation = {200, 100}, {2, 2}, 0
	// Hit test: on the frame, not in the hole (a mesh is needed: tessellate one).
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	_ = Vector_ResourceMesh(ra, &tess, 0.5)
	testing.expect(t, VectorShapeNode_HitTest(a, {110, 10}), "on the frame")
	testing.expect(t, !VectorShapeNode_HitTest(a, {200, 100}), "in the hole")
	testing.expect(t, !VectorShapeNode_HitTest(a, {500, 500}), "outside")
	// Buckets: a second zoom adds a cache, the same zoom reuses it.
	_ = Vector_ResourceMesh(ra, &tess, 2)
	_ = Vector_ResourceMesh(ra, &tess, 0.5)
	used := 0
	for c in ra.caches do if c.used != 0 do used += 1
	testing.expect_value(t, used, 2)
	// A change on disk reloads it (the version bumps; caches go dirty).
	write(path, `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 50 50"><circle cx="25" cy="25" r="25" fill="blue"/></svg>`)
	ra.modTime._nsec = 1 // (force the check: same-second writes)
	testing.expect_value(t, Vector_CheckForChanges(&game.resourceManager), 1)
	testing.expect_value(t, ra.version, 1)
	testing.expect_value(t, VectorShapeNode_Size(a), [2]f32{50, 50})
	// Releasing both frees it.
	b.file = ""
	_ = VectorShapeNode_Asset(b)
	testing.expect_value(t, ra.refs, 1)
	// A missing / broken file: no resource, no crash.
	c := cast(^VectorShapeNode)Node_CreateByTypeName(scene, "VectorShapeNode")
	c.gameContext = &game.gameContext
	c.file = strings.concatenate({dir, "/nope.svg"}, context.temp_allocator)
	{
		context.logger = {} // (the "not found" error is the point here)
		testing.expect(t, VectorShapeNode_Asset(c) == nil, "missing file")
	}
	write(path, "<html/>")
	ra.modTime._nsec = 1
	testing.expect_value(t, Vector_CheckForChanges(&game.resourceManager), 0) // (kept the last good one)
}

// Vector import settings (M2): vector_scale / origin parse, round-trip and
// scale the document (points, strokes, gradients, clips, box).
@(test)
test_vector_import_settings :: proc(t: ^testing.T) {
	imp: Asset_Import
	Asset_ImportParse(`{"vector_scale": 0.5, "origin": [0.5, 1]}`, &imp, context.temp_allocator)
	testing.expect_value(t, imp.vectorScale, 0.5)
	testing.expect(t, imp.hasOrigin && imp.origin == {0.5, 1}, "origin")
	testing.expect(t, !Asset_ImportIsDefault(imp), "not default")
	text := Asset_ImportToJSON(imp, context.temp_allocator)
	back: Asset_Import
	Asset_ImportParse(text, &back, context.temp_allocator)
	testing.expect(t, back.vectorScale == 0.5 && back.origin == {0.5, 1}, "round trip")
	testing.expect(t, Asset_ImportIsDefault({vectorScale = 1}), "scale 1 is the default")

	doc: Vector_Doc
	defer Vector_Doc_Destroy(&doc)
	testing.expect(t, Vector_LoadSVG(SVG_ILLUSTRATOR, &doc), "loaded")
	before := doc.shapes[1].style.strokeWidth
	firstPt := doc.shapes[0].path.pts[0]
	Vector_DocScale(&doc, 0.5)
	testing.expect_value(t, doc.size, [2]f32{120, 80})
	testing.expect_value(t, doc.shapes[1].style.strokeWidth, before * 0.5)
	testing.expect_value(t, doc.shapes[0].path.pts[0], firstPt * 0.5)
	// The gradient follows: its start (170, 100) is now at (85, 50).
	g := &doc.shapes[4].style.fillPaint
	testing.expect(t, abs(Vector_PaintCoord(g, {85, 50}).x) < 1e-4, "scaled gradient")
	// The clip too (a 60 px square -> 30).
	k := doc.shapes[3].clip
	maxX: f32
	for q in k.path.pts do maxX = max(maxX, q.x)
	testing.expect_value(t, maxX, 80)
}

// Background tessellation (M2): a new zoom draws the nearest mesh while a
// worker makes the new one; the pump installs it; a reload waits for jobs;
// shutting down joins them.
@(test)
test_vector_background_tessellation :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	rm := &game.resourceManager
	dir, _ := filepath.join({Engine_TempDir(), "rayzr_vector_jobs_test"}, context.temp_allocator)
	_ = os.make_directory_all(dir)
	path := strings.concatenate({dir, "/card.svg"}, context.temp_allocator)
	_ = os.write_entire_file(path, transmute([]u8)SVG_FIGMA)
	r := ResourceManager_LoadVector(rm, path)
	testing.expect(t, r != nil, "loaded")
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	// Nothing cached: tessellated at once even in background mode.
	c1 := Vector_ResourceMesh(r, &tess, 1, background = true)
	testing.expect(t, c1.bucket == 1 && len(c1.mesh.idx) > 0, "first mesh made now")
	// Zoomed in 4x: drawn from bucket 1 while a job runs.
	c2 := Vector_ResourceMesh(r, &tess, 0.25, background = true)
	testing.expect_value(t, c2.bucket, 1)
	testing.expect_value(t, r.pending, 1)
	testing.expect_value(t, r.refs, 2) // (the job's reference)
	// Asking again doesn't queue it twice.
	_ = Vector_ResourceMesh(r, &tess, 0.25, background = true)
	testing.expect_value(t, r.pending, 1)
	// A reload waits while the job runs.
	r.modTime._nsec = 1
	testing.expect_value(t, Vector_CheckForChanges(rm), 0)
	// Wait for the worker, pump: the new bucket is installed.
	for i := 0; i < 2000 && Vector_JobsRunning() > 0; i += 1 {
		Vector_JobPump()
		time.sleep(time.Millisecond)
	}
	testing.expect_value(t, r.pending, 0)
	testing.expect_value(t, r.refs, 1)
	c3 := Vector_ResourceMesh(r, &tess, 0.25, background = true)
	testing.expect(t, c3.bucket == 0.25 && len(c3.mesh.idx) > len(c1.mesh.idx), "the finer mesh")
	// A job outliving its asset's last user doesn't touch freed memory.
	_ = Vector_ResourceMesh(r, &tess, 4, background = true)
	ResourceManager_ReleaseVector(r) // (the job still holds it)
	testing.expect_value(t, Vector_ResourceCount(rm), 1)
	Vector_JobsShutdown() // joins, installs, releases: freed now
	testing.expect_value(t, Vector_ResourceCount(rm), 0)
}

@(private = "file")
SVG_PARTS :: #load("../tests/vector/svg/character_parts.svg", string)

// Symbols and part swapping (M3): a node draws one group of a file; frame
// picks one of its child groups (by index or name); the origin box stays the
// group's, so swapping never moves the part; meshes are per part.
@(test)
test_vector_symbols_swapping :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("vsym", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	dir, _ := filepath.join({Engine_TempDir(), "rayzr_vector_parts_test"}, context.temp_allocator)
	_ = os.make_directory_all(dir)
	path := strings.concatenate({dir, "/hero.svg"}, context.temp_allocator)
	_ = os.write_entire_file(path, transmute([]u8)SVG_PARTS)
	mouth := cast(^VectorShapeNode)Node_CreateByTypeName(scene, "VectorShapeNode")
	mouth.gameContext = &game.gameContext
	mouth.file = path
	mouth.group = "mouth"
	r := VectorShapeNode_Asset(mouth)
	testing.expect(t, r != nil, "loaded")
	frames := VectorShapeNode_Frames(mouth)
	testing.expect_value(t, len(frames), 9)
	testing.expect(t, frames[0] == "X" && frames[1] == "A" && frames[8] == "H", "Rhubarb's mouth shapes in order")
	// frame -1 draws every mouth; the box is the whole mouth group.
	part, boxMin, boxSize, ok := VectorShapeNode_Part(mouth, r)
	testing.expect(t, ok && part == Vector_ResourceGroup(r, "mouth"), "the group")
	// Swapping by name keeps the box (the origin doesn't jump).
	testing.expect(t, VectorShapeNode_Swap(mouth, "O") == false, "no O")
	testing.expect(t, VectorShapeNode_Swap(mouth, "D"), "D")
	testing.expect_value(t, mouth.frame, 4)
	part2, boxMin2, boxSize2, ok2 := VectorShapeNode_Part(mouth, r)
	testing.expect(t, ok2 && part2 != part && r.doc.groups[part2].name == "D", "frame D")
	testing.expect(t, boxMin2 == boxMin && boxSize2 == boxSize, "the same box for every frame")
	// A frame past the end: nothing drawn (no crash).
	mouth.frame = 20
	_, _, _, ok3 := VectorShapeNode_Part(mouth, r)
	testing.expect(t, !ok3, "no such frame")
	mouth.frame = -1
	// Nested names: "head/eyes" and a bare "eyes" find the same group.
	testing.expect_value(t, Vector_ResourceGroup(r, "head/eyes"), Vector_ResourceGroup(r, "eyes"))
	testing.expect_value(t, Vector_ResourceGroup(r, "nope"), -2)
	// Size: the group's box; the whole file without a group.
	testing.expect(t, VectorShapeNode_Size(mouth).x < 50, "the mouth is small")
	mouth.group = ""
	testing.expect_value(t, VectorShapeNode_Size(mouth), [2]f32{240, 320})
	// Per-part meshes: two parts, two caches (each the part's shapes only).
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	head := Vector_ResourceGroup(r, "head")
	arm := Vector_ResourceGroup(r, "arm_l")
	ch := Vector_ResourceMesh(r, &tess, 1, part = head)
	ca := Vector_ResourceMesh(r, &tess, 1, part = arm)
	testing.expect(t, ch != ca && len(ch.mesh.idx) > len(ca.mesh.idx), "separate part meshes")
	// Hidden groups (display:none) are frames: left out of what contains
	// them, drawn when picked themselves.
	mg := Vector_ResourceGroup(r, "mouth")
	dg := Vector_ResourceGroup(r, "D")
	testing.expect(t, r.doc.groups[dg].hidden && !r.doc.groups[Vector_ResourceGroup(r, "X")].hidden, "hidden frames")
	testing.expect_value(t, len(Vector_PartShapes(r, mg)), 1) // (only X shows)
	testing.expect_value(t, len(Vector_PartShapes(r, dg)), 2) // (D picked: its two shapes)
	testing.expect(t, len(Vector_PartShapes(r, -1)) < len(r.doc.shapes), "the whole file skips them")
	eyes := Vector_ResourceGroup(r, "eyes")
	testing.expect_value(t, len(Vector_PartShapes(r, eyes)), 2) // (open; closed is hidden)
	// The rescaled document keeps the hidden frames out.
	Vector_DocScale(&r.doc, 2)
	testing.expect_value(t, len(Vector_PartShapes(r, mg)), 1)
	testing.expect_value(t, Vector_PartShapes(r, dg)[0].style.fillColor, r.doc.shapes[r.doc.groups[dg].first].style.fillColor)
}

// Lip-sync (M3): Rhubarb cues (TSV / JSON), shapes over time, frame mapping
// and fallbacks, a LipSyncNode moving a mouth part to the end, a dialogue
// line's voice driving it.
@(test)
test_vector_lipsync :: proc(t: ^testing.T) {
	cues := make([dynamic]Lip_Cue)
	defer delete(cues)
	testing.expect(t, Lip_ParseCues("0.00\tX\n0.05\tD\n0.27\tC\n0.45\tX\n", &cues), "TSV")
	testing.expect_value(t, len(cues), 4)
	testing.expect_value(t, Lip_CueAt(cues[:], 0.1), 'D')
	testing.expect_value(t, Lip_CueAt(cues[:], 0.3), 'C')
	testing.expect_value(t, Lip_CueAt(cues[:], 9), 'X')
	testing.expect(t, Lip_ParseCues(`{"metadata": {}, "mouthCues": [{"start": 0.00, "end": 0.10, "value": "X"}, {"start": 0.10, "end": 0.30, "value": "B"}]}`, &cues), "JSON")
	testing.expect_value(t, Lip_CueAt(cues[:], 0.2), 'B')
	testing.expect(t, !Lip_ParseCues("not cues", &cues), "junk")
	frames := []string{"X", "A", "B", "C", "D", "E", "F"}
	testing.expect_value(t, Lip_FrameFor(frames, "", 'D'), 4)
	testing.expect_value(t, Lip_FrameFor(frames, "", 'G'), 2) // (no G: B)
	testing.expect_value(t, Lip_FrameFor(frames, "", 'H'), 3) // (no H: C)
	blair := []string{"rest", "MBP", "etc", "E", "AI", "O", "U"}
	testing.expect_value(t, Lip_FrameFor(blair, "A=MBP,B=etc,C=E,D=AI,E=O,F=U,X=rest", 'A'), 1)
	testing.expect_value(t, Lip_FrameFor(blair, "A=MBP,B=etc,C=E,D=AI,E=O,F=U,X=rest", 'X'), 0)
	testing.expect_value(t, Lip_FrameFor(blair, "", 'D'), -1)
	// Keyed swaps on the timeline hold until the next key (no tween through the frames between).
	track := Property_Track{property = "frame"}
	defer delete(track.keys)
	Track_SetKey(&track, 0, {1, 0, 0, 0})
	Track_SetKey(&track, 10, {4, 0, 0, 0})
	v, _ := Track_Sample(&track, 9)
	testing.expect_value(t, v[0], 1)
	v, _ = Track_Sample(&track, 10)
	testing.expect_value(t, v[0], 4)

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("vlips", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	dir, _ := filepath.join({Engine_TempDir(), "rayzr_vector_lips_test"}, context.temp_allocator)
	_ = os.make_directory_all(dir)
	svg := strings.concatenate({dir, "/hero.svg"}, context.temp_allocator)
	_ = os.write_entire_file(svg, transmute([]u8)SVG_PARTS)
	// A short silent WAV and its cues beside it.
	wav := strings.concatenate({dir, "/hello.wav"}, context.temp_allocator)
	write_silent_wav(wav, 0.5)
	_ = os.write_entire_file(strings.concatenate({dir, "/hello.tsv"}, context.temp_allocator), transmute([]u8)string("0.00\tX\n0.05\tD\n0.20\tA\n0.30\tX\n"))
	head := Node_CreateByTypeName(scene, "Node")
	head.name = "Head"
	head.gameContext = &game.gameContext
	mouth := cast(^VectorShapeNode)Node_CreateByTypeName(scene, "VectorShapeNode", head)
	mouth.name = "Mouth"
	mouth.gameContext = &game.gameContext
	mouth.file = svg
	mouth.group = "mouth"
	lips := cast(^LipSyncNode)Node_CreateByTypeName(scene, "LipSyncNode", head)
	lips.gameContext = &game.gameContext
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect(t, LipSyncNode_Mouth(lips) == mouth, "../Mouth found")
	finished := 0
	lips.onFinished->subscribe(proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &finished)
	testing.expect(t, LipSyncNode_Follow(lips, wav, {}), "cues beside the sound")
	LipSyncNode_Update(lips, &game.gameContext, 0.1) // t = 0.1: D
	testing.expect_value(t, mouth.frame, 4)
	LipSyncNode_Update(lips, &game.gameContext, 0.12) // t = 0.22: A
	testing.expect_value(t, mouth.frame, 1)
	LipSyncNode_Update(lips, &game.gameContext, 0.5) // past the end: rest (X)
	testing.expect(t, !lips.playing, "finished")
	testing.expect_value(t, mouth.frame, 0)
	testing.expect_value(t, finished, 1)
	// No cues: refuses.
	testing.expect(t, !LipSyncNode_Follow(lips, strings.concatenate({dir, "/none.wav"}, context.temp_allocator), {}), "no cues")
	// An exported game (the web, Android): the cues are read from its package.
	pdir := strings.concatenate({dir, "/pkg"}, context.temp_allocator)
	_ = os.make_directory_all(strings.concatenate({pdir, "/voice"}, context.temp_allocator))
	_ = os.write_entire_file(strings.concatenate({pdir, "/voice/packed_hi.tsv"}, context.temp_allocator), transmute([]u8)string("0.00\tX\n0.05\tE\n0.30\tX\n"))
	rayzr := strings.concatenate({dir, "/lips.rayzr"}, context.temp_allocator)
	testing.expect(t, RayzrPackage_CreateFromDirectory(pdir, rayzr, true), "package")
	if pkg, pok := RayzrPackage_Open(rayzr); pok {
		game.assetManager.package_ = pkg
		testing.expect(t, LipSyncNode_Follow(lips, "voice/packed_hi.wav", {}), "cues from the package")
		LipSyncNode_Update(lips, &game.gameContext, 0.1)
		testing.expect_value(t, mouth.frame, 5) // (E)
		LipSyncNode_Stop(lips)
		game.assetManager.package_ = nil
		RayzrPackage_Close(pkg)
	} else {
		testing.fail_now(t, "the package opens")
	}
	// A dialogue line with that voice moves the mouth.
	d := cast(^DialogueNode)Node_CreateByTypeName(scene, "DialogueNode", head)
	d.gameContext = &game.gameContext
	d.lipSync = "../LipSync"
	lips.name = "LipSync"
	ProcessNodeQueues(scene.manager, &game.gameContext)
	DialogueNode_Show(d, {{"Hero", "Hello", wav, nil}})
	game->run(0.016)
	testing.expect(t, lips.playing, "the line's voice drives it")
	DialogueNode_Close(d, &game.gameContext)
	testing.expect(t, !lips.playing, "closing the dialogue rests the mouth")
}

// write_silent_wav: a mono 16-bit 48 kHz WAV of silence.
@(private = "file")
write_silent_wav :: proc(path: string, seconds: f32) {
	n := int(48000 * seconds)
	b := make([dynamic]u8, context.temp_allocator)
	u32le :: proc(b: ^[dynamic]u8, v: u32) {append(b, u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24))}
	u16le :: proc(b: ^[dynamic]u8, v: u16) {append(b, u8(v), u8(v >> 8))}
	append(&b, ..transmute([]u8)string("RIFF"))
	u32le(&b, u32(36 + n * 2))
	append(&b, ..transmute([]u8)string("WAVEfmt "))
	u32le(&b, 16); u16le(&b, 1); u16le(&b, 1); u32le(&b, 48000); u32le(&b, 96000); u16le(&b, 2); u16le(&b, 16)
	append(&b, ..transmute([]u8)string("data"))
	u32le(&b, u32(n * 2))
	for _ in 0 ..< n * 2 do append(&b, 0)
	_ = os.write_entire_file(path, b[:])
}
