package engine

import "core:fmt"
import b2 "vendor:box2d"

// ============================================================================
// Tile map colliders: a solid map's bodies, built from its tiles and their
// collision (tile_collision.odin).
//
// A collider body covers some cells (the whole map, or a chunk of an
// endless one) in sections of TILE_SECTION x TILE_SECTION cells: each shape
// belongs to one section, and an edit rebuilds only the sections it
// touched. Its shapes:
//   - Full tiles: the fewest boxes that cover them (greedy rectangles, per
//     material), or with Collider Shape: Outline, edge chains around them
//     (smooth sliding: no seams at all; rebuilt whole on an edit).
//   - Slopes, halves, custom polygons: a polygon per cell.
//   - One-way tiles: boxes on a child body that is one-way (land on top).
//   - Trigger tiles: a sensor per cell on a child body - "tile_entered" /
//     "tile_exited" on the map.
// Every shape knows its cells, so a contact names the exact tile it hit
// ("tile_hit", sent by the physics world: physics_world.odin).
// ============================================================================

TILE_SECTION :: 16

TileMap_Collider_Shape :: enum u8 {
	Boxes,   // merged boxes per section
	Outline, // edge chains around the solid tiles (square grids)
}

Tile_Collider_Kind :: enum u8 {
	Solid,
	One_Way,
	Trigger,
}

// The cells one shape of a collider body covers (lo .. hi, exclusive).
Tile_Shape_Cells :: struct {
	section: [2]i32,
	lo, hi:  [2]i32,
}

// OUTLINE_SECTION: the chains' (the whole body's) section key.
OUTLINE_SECTION :: [2]i32{max(i32), max(i32)}

// A tile map's collider body (StaticBodyNode.tileColliders).
Tile_Collider_Info :: struct {
	tileMap:  ^TileMapNode,
	kind:     Tile_Collider_Kind,
	lo, hi:   [2]int, // the cells the body covers
	cells:    [dynamic]Tile_Shape_Cells, // per shape (parallel to body.shapes)
	oneWay:   ^StaticBodyNode, // (the solid body's children, made when needed)
	triggers: ^StaticBodyNode,
}

// TileColliders_Create: a collider body for the cells lo .. hi, a
// transient child of the map, with its shapes. nil: no scene.
TileColliders_Create :: proc(tm: ^TileMapNode, name: string, lo, hi: [2]int, ctx: ^GameContext) -> ^StaticBodyNode {
	scene := ctx.scene if ctx != nil else nil
	if scene == nil && tm.gameContext != nil do scene = tm.gameContext.scene
	if scene == nil do return nil
	body := tile_collider_body(tm, scene, name, tm, .Solid, lo, hi, ctx)
	TileColliders_Rebuild(tm, body, ctx)
	return body
}

@(private = "file")
tile_collider_body :: proc(tm: ^TileMapNode, scene: ^Scene, name: string, parent: ^Node, kind: Tile_Collider_Kind, lo, hi: [2]int, ctx: ^GameContext) -> ^StaticBodyNode {
	body := StaticBodyNode_Create(scene, name, parent)
	body.position = {0, 0}
	body.transient = true
	body.gameContext = ctx
	body.oneWay = kind == .One_Way
	body.castsShadows = kind == .Solid
	info := new(Tile_Collider_Info, body.allocator)
	info^ = {tileMap = tm, kind = kind, lo = lo, hi = hi}
	info.cells = make([dynamic]Tile_Shape_Cells, body.allocator)
	body.tileColliders = info
	return body
}

// TileColliders_Free: a collider body's bookkeeping (StaticBodyNode_Destroy).
TileColliders_Free :: proc(sb: ^StaticBodyNode) {
	info := sb.tileColliders
	if info == nil do return
	delete(info.cells)
	free(info, sb.allocator)
	sb.tileColliders = nil
}

// TileColliders_Rebuild: every section of a collider body made again.
TileColliders_Rebuild :: proc(tm: ^TileMapNode, body: ^StaticBodyNode, ctx: ^GameContext) {
	info := body.tileColliders
	if info == nil do return
	sections := make(map[[2]i32]bool, allocator = context.temp_allocator)
	slo, shi := tile_section_range(info.lo, info.hi)
	for sy in slo.y ..= shi.y do for sx in slo.x ..= shi.x do sections[{sx, sy}] = true
	tile_colliders_rebuild_sections(tm, body, sections, true, ctx)
}

// TileColliders_RebuildCells: the sections holding these cells made again
// (with Outline, the whole chain too). Cells outside the body are skipped.
TileColliders_RebuildCells :: proc(tm: ^TileMapNode, body: ^StaticBodyNode, cells: [][2]int, ctx: ^GameContext) {
	info := body.tileColliders
	if info == nil || len(cells) == 0 do return
	sections := make(map[[2]i32]bool, allocator = context.temp_allocator)
	for c in cells {
		if c.x < info.lo.x || c.y < info.lo.y || c.x >= info.hi.x || c.y >= info.hi.y do continue
		sections[tile_section_of(c)] = true
		// (A slope's neighbour can't change, but the Y-sort / iso runs can
		// span: the row's sections either side.)
	}
	if len(sections) == 0 do return
	tile_colliders_rebuild_sections(tm, body, sections, false, ctx)
}

// TileColliders_SectionCount: how many sections a body holds shapes in (tests).
TileColliders_ShapeCount :: proc(body: ^StaticBodyNode) -> (solid, oneWay, triggers: int) {
	if body == nil || body.tileColliders == nil do return
	solid = len(body.shapes)
	info := body.tileColliders
	if info.oneWay != nil && Node_IsAlive(info.oneWay) do oneWay = len(info.oneWay.shapes)
	if info.triggers != nil && Node_IsAlive(info.triggers) do triggers = len(info.triggers.shapes)
	return
}

tile_section_of :: proc(c: [2]int) -> [2]i32 {
	return {i32(floor_div(c.x, TILE_SECTION)), i32(floor_div(c.y, TILE_SECTION))}
}

@(private = "file")
tile_section_range :: proc(lo, hi: [2]int) -> (slo, shi: [2]i32) {
	if hi.x <= lo.x || hi.y <= lo.y do return {0, 0}, {-1, -1}
	return tile_section_of(lo), tile_section_of(hi - 1)
}

// TileMapNode_RefillAllChunks: every collider body of an endless map
// (its chunks') made again - a tile's collision changed.
TileMapNode_RefillAllChunks :: proc(tm: ^TileMapNode, ctx: ^GameContext) {
	if tm.gameContext == nil || tm.gameContext.scene == nil do return
	for child in GetChildrenTemp(tm.gameContext.scene.manager, tm) {
		if child.typeId != StaticBodyNode || child.removing do continue
		sb := cast(^StaticBodyNode)child
		if sb.tileColliders != nil && sb.tileColliders.tileMap == tm do TileColliders_Rebuild(tm, sb, ctx)
	}
}

// --- Rebuilding ----------------------------------------------------------------------

// The shapes one section makes, per body.
@(private = "file")
Tile_Built :: struct {
	shapes: [Tile_Collider_Kind][dynamic]PhysicsShape,
	cells:  [Tile_Collider_Kind][dynamic]Tile_Shape_Cells,
}

@(private = "file")
tile_colliders_rebuild_sections :: proc(tm: ^TileMapNode, body: ^StaticBodyNode, sections: map[[2]i32]bool, all: bool, ctx: ^GameContext) {
	info := body.tileColliders
	outline := tm.colliderShape == .Outline && tm.layout == .Square
	// Drop the sections' shapes (the chain too: it's rebuilt whole).
	drop := proc(b: ^StaticBodyNode, sections: map[[2]i32]bool, all: bool) {
		if b == nil || !Node_IsAlive(b) || b.tileColliders == nil do return
		cells := &b.tileColliders.cells
		if all {
			for &s in b.shapes do PhysicsShape_Destroy(&s)
			clear(&b.shapes)
			clear(cells)
			return
		}
		k := 0
		for i in 0 ..< len(b.shapes) {
			sec := cells[i].section if i < len(cells) else OUTLINE_SECTION
			if sec in sections || sec == OUTLINE_SECTION {
				PhysicsShape_Destroy(&b.shapes[i])
				continue
			}
			b.shapes[k] = b.shapes[i]
			cells[k] = cells[i]
			k += 1
		}
		resize(&b.shapes, k)
		resize(cells, k)
	}
	drop(body, sections, all)
	drop(info.oneWay, sections, all)
	drop(info.triggers, sections, all)
	if tm.triggerInside != nil do tile_triggers_stale(tm, sections, all)

	built: Tile_Built
	for k in Tile_Collider_Kind {
		built.shapes[k] = make([dynamic]PhysicsShape, context.temp_allocator)
		built.cells[k] = make([dynamic]Tile_Shape_Cells, context.temp_allocator)
	}
	for sec in sections {
		lo := [2]int{max(int(sec.x) * TILE_SECTION, info.lo.x), max(int(sec.y) * TILE_SECTION, info.lo.y)}
		hi := [2]int{min(int(sec.x + 1) * TILE_SECTION, info.hi.x), min(int(sec.y + 1) * TILE_SECTION, info.hi.y)}
		if hi.x <= lo.x || hi.y <= lo.y do continue
		tile_section_shapes(tm, sec, lo, hi, !outline, &built)
	}
	if outline do tile_outline_chains(tm, info.lo, info.hi, &built)

	scene := ctx.scene if ctx != nil && ctx.scene != nil else (tm.gameContext.scene if tm.gameContext != nil else nil)
	for k in Tile_Collider_Kind {
		if len(built.shapes[k]) == 0 do continue
		b := body
		switch k {
		case .Solid:
		case .One_Way, .Trigger:
			child := &info.oneWay if k == .One_Way else &info.triggers
			if child^ == nil || !Node_IsAlive(child^) || child^.removing {
				if scene == nil do continue
				child^ = tile_collider_body(tm, scene, fmt.tprintf("%s_%s", body.name, "OneWay" if k == .One_Way else "Triggers"), body, k, info.lo, info.hi, ctx)
			}
			b = child^
		}
		for s, i in built.shapes[k] {
			s := s
			if s.chainPoints != nil {
				// (The body owns its chain's points: PhysicsShape_Destroy frees them.)
				pts := make([dynamic][2]f32, len(s.chainPoints), b.allocator)
				copy(pts[:], s.chainPoints[:])
				s.chainPoints = pts
			}
			StaticBodyNode_AddShape(b, s, ctx)
			append(&b.tileColliders.cells, built.cells[k][i])
		}
	}
}

// tile_material: a tile's friction and bounce (the map's where it has none).
@(private = "file")
tile_material :: proc(tm: ^TileMapNode, c: Tile_Collision) -> [2]f32 {
	return {c.friction if c.friction >= 0 else tm.friction, c.bounce if c.bounce >= 0 else tm.bounce}
}

@(private = "file")
tile_make_shape :: proc(tm: ^TileMapNode, shape: PhysicsShape, mat: [2]f32, kind: Tile_Collider_Kind) -> PhysicsShape {
	s := shape
	s.categoryLayers = tm.categoryLayers
	s.maskLayers = tm.maskLayers
	s.friction = mat[0]
	s.restitution = mat[1]
	if kind == .Trigger {
		s.isSensor = true
		s.enableSensorEvents = true
	}
	return s
}

// Tile_Cell_Class: what a cell builds.
@(private = "file")
Tile_Cell_Class :: struct {
	kind:    Tile_Collider_Kind,
	full:    bool, // the whole cell (else its polygon)
	mat:     [2]f32,
	coll:    Tile_Collision,
	present: bool,
}

@(private = "file")
tile_cell_class :: proc(tm: ^TileMapNode, x, y: int) -> (cl: Tile_Cell_Class) {
	t := TileMapNode_Get(tm, x, y)
	if t < 0 do return
	c := TileCollision_Get(tm.sidecar, t)
	if c.shape == .None do return
	if tm.layout != .Square && c.shape != .One_Way do c.shape = .Full // (partial shapes: square grids)
	cl.present = true
	cl.coll = c
	cl.mat = tile_material(tm, c)
	cl.kind = .Trigger if c.trigger else (.One_Way if c.shape == .One_Way else .Solid)
	cl.full = c.shape == .Full || c.shape == .One_Way
	return
}

// tile_section_shapes: a section's shapes (solid full tiles too unless
// the outline builds them).
@(private = "file")
tile_section_shapes :: proc(tm: ^TileMapNode, sec: [2]i32, lo, hi: [2]int, fullSolid: bool, out: ^Tile_Built) {
	cs := TileMapNode_CellSize(tm)
	w, h := hi.x - lo.x, hi.y - lo.y
	classes := make([]Tile_Cell_Class, w * h, context.temp_allocator)
	for y in lo.y ..< hi.y do for x in lo.x ..< hi.x do classes[(y - lo.y) * w + (x - lo.x)] = tile_cell_class(tm, x, y)
	add :: proc(out: ^Tile_Built, kind: Tile_Collider_Kind, s: PhysicsShape, sec: [2]i32, clo, chi: [2]int) {
		append(&out.shapes[kind], s)
		append(&out.cells[kind], Tile_Shape_Cells{sec, {i32(clo.x), i32(clo.y)}, {i32(chi.x), i32(chi.y)}})
	}

	// Single cells: partial shapes, triggers, and every cell of a grid that
	// isn't square or isometric.
	for y in lo.y ..< hi.y do for x in lo.x ..< hi.x {
		cl := classes[(y - lo.y) * w + (x - lo.x)]
		if !cl.present do continue
		single := !cl.full || cl.kind == .Trigger || (tm.layout != .Square && tm.layout != .Isometric)
		if !single do continue
		if tm.layout != .Square {
			pts, n := TileMapNode_CellOutline(tm, {x, y})
			add(out, cl.kind, tile_make_shape(tm, MakePolygonPhysicsShape(pts[:n]), cl.mat, cl.kind), sec, {x, y}, {x + 1, y + 1})
			continue
		}
		poly := TileCollision_Polygon(cl.coll)
		if len(poly) < 3 do continue
		pts := make([][2]f32, len(poly), context.temp_allocator)
		for p, i in poly do pts[i] = {(f32(x) + p.x) * cs.x, (f32(y) + p.y) * cs.y}
		add(out, cl.kind, tile_make_shape(tm, MakePolygonPhysicsShape(pts), cl.mat, cl.kind), sec, {x, y}, {x + 1, y + 1})
	}

	// Whole cells, merged: per kind (solid / one-way) and material.
	mergeable :: proc(cl: Tile_Cell_Class, fullSolid: bool) -> bool {
		if !cl.present || !cl.full || cl.kind == .Trigger do return false
		return cl.kind == .One_Way || fullSolid
	}
	same :: proc(a, b: Tile_Cell_Class) -> bool {return a.present && b.present && a.kind == b.kind && a.full == b.full && a.mat == b.mat}
	if tm.layout == .Isometric {
		// Runs along x are parallelograms: the first cell's top and left
		// corners, the last one's right and bottom.
		for y in lo.y ..< hi.y {
			x := lo.x
			for x < hi.x {
				cl := classes[(y - lo.y) * w + (x - lo.x)]
				if !mergeable(cl, fullSolid) {
					x += 1
					continue
				}
				start := x
				for x < hi.x && same(classes[(y - lo.y) * w + (x - lo.x)], cl) do x += 1
				a, _ := TileMapNode_CellOutline(tm, {start, y})
				b, _ := TileMapNode_CellOutline(tm, {x - 1, y})
				add(out, cl.kind, tile_make_shape(tm, MakePolygonPhysicsShape({a[0], b[1], b[2], a[3]}), cl.mat, cl.kind), sec, {start, y}, {x, y + 1})
			}
		}
		return
	}
	if tm.layout != .Square do return
	used := make([]bool, w * h, context.temp_allocator)
	for y in 0 ..< h do for x in 0 ..< w {
		i := y * w + x
		cl := classes[i]
		if used[i] || !mergeable(cl, fullSolid) do continue
		// Greedy: as wide as it goes, then as tall as whole rows allow.
		rw := 1
		for x + rw < w && !used[i + rw] && same(classes[i + rw], cl) do rw += 1
		rh := 1
		grow: for y + rh < h {
			for k in 0 ..< rw {
				j := (y + rh) * w + x + k
				if used[j] || !same(classes[j], cl) do break grow
			}
			rh += 1
		}
		for yy in 0 ..< rh do for xx in 0 ..< rw do used[(y + yy) * w + x + xx] = true
		cx, cy := lo.x + x, lo.y + y
		bw, bh := f32(rw) * cs.x, f32(rh) * cs.y
		box := MakeBoxPhysicsShape(bw, bh, {f32(cx) * cs.x + bw * 0.5, f32(cy) * cs.y + bh * 0.5}, 0)
		add(out, cl.kind, tile_make_shape(tm, box, cl.mat, cl.kind), sec, {cx, cy}, {cx + rw, cy + rh})
	}
}

// tile_outline_chains: loops of edges around the solid full tiles (square
// grids), solid on the right of each edge as Box2D wants (outward normals).
// One loop per material run is overkill: chains take the map's material.
@(private = "file")
tile_outline_chains :: proc(tm: ^TileMapNode, lo, hi: [2]int, out: ^Tile_Built) {
	cs := TileMapNode_CellSize(tm)
	w, h := hi.x - lo.x, hi.y - lo.y
	if w <= 0 || h <= 0 do return
	solid := make([]bool, w * h, context.temp_allocator)
	for y in lo.y ..< hi.y do for x in lo.x ..< hi.x {
		cl := tile_cell_class(tm, x, y)
		solid[(y - lo.y) * w + (x - lo.x)] = cl.present && cl.full && cl.kind == .Solid
	}
	at :: proc(solid: []bool, w, h, x, y: int) -> bool {return x >= 0 && y >= 0 && x < w && y < h && solid[y * w + x]}
	// Directed edges, by start vertex: bit d = an edge leaving in direction d
	// (0 east, 1 south, 2 west, 3 north; y down). Clockwise on screen
	// around solid: Box2D's right normal points out.
	DIRS := [4][2]int{{1, 0}, {0, 1}, {-1, 0}, {0, -1}}
	vw := w + 1
	edges := make([]u8, (w + 1) * (h + 1), context.temp_allocator)
	count := 0
	for y in 0 ..< h do for x in 0 ..< w {
		if !solid[y * w + x] do continue
		if !at(solid, w, h, x, y - 1) {edges[y * vw + x] |= 1 << 0; count += 1}         // top: east
		if !at(solid, w, h, x + 1, y) {edges[y * vw + x + 1] |= 1 << 1; count += 1}     // right: south
		if !at(solid, w, h, x, y + 1) {edges[(y + 1) * vw + x + 1] |= 1 << 2; count += 1} // bottom: west
		if !at(solid, w, h, x - 1, y) {edges[(y + 1) * vw + x] |= 1 << 3; count += 1}   // left: north
	}
	mat := [2]f32{tm.friction, tm.bounce}
	for count > 0 {
		start := -1
		for e, i in edges do if e != 0 {start = i; break}
		if start < 0 do break
		v := [2]int{start % vw, start / vw}
		d := 0
		for k in 0 ..< 4 do if edges[start] & (1 << u8(k)) != 0 {d = k; break}
		pts := make([dynamic][2]f32, context.temp_allocator)
		first := v
		firstDir := d
		prevDir := -1
		for {
			vi := v.y * vw + v.x
			edges[vi] &~= 1 << u8(d)
			count -= 1
			if d != prevDir do append(&pts, [2]f32{f32(lo.x + v.x) * cs.x, f32(lo.y + v.y) * cs.y})
			prevDir = d
			v += DIRS[d]
			if v == first {
				if d == firstDir && len(pts) > 0 do ordered_remove(&pts, 0) // (the start was mid-edge)
				break
			}
			// Prefer a right turn, then straight, then left (diagonal
			// touches stay separate loops).
			ni := v.y * vw + v.x
			nd := -1
			for t in ([3]int{1, 0, 3}) {
				c := (d + t) % 4
				if edges[ni] & (1 << u8(c)) != 0 {nd = c; break}
			}
			if nd < 0 do break // (can't happen: every vertex balances)
			d = nd
		}
		if len(pts) < 4 do continue
		s: PhysicsShape
		PhysicsShape_InitDefault(&s, .Chain)
		s.offset = {}
		s.isLoop = true
		s.chainPoints = pts // (temp: copied to the body's when added)
		append(&out.shapes[.Solid], tile_make_shape(tm, s, mat, .Solid))
		append(&out.cells[.Solid], Tile_Shape_Cells{OUTLINE_SECTION, {i32(lo.x), i32(lo.y)}, {i32(hi.x), i32(hi.y)}})
	}
}

// --- The editor's view ---------------------------------------------------------------

// TileColliders_Shapes: the solid shapes a map's colliders would have
// (the editor's shadows before they exist: lighting_nodes.odin).
TileColliders_Shapes :: proc(tm: ^TileMapNode, out: ^[dynamic]PhysicsShape) {
	lo, hi := TileMapNode_Extent(tm)
	built: Tile_Built
	for k in Tile_Collider_Kind {
		built.shapes[k] = make([dynamic]PhysicsShape, context.temp_allocator)
		built.cells[k] = make([dynamic]Tile_Shape_Cells, context.temp_allocator)
	}
	slo, shi := tile_section_range(lo, hi)
	for sy in slo.y ..= shi.y do for sx in slo.x ..= shi.x {
		l := [2]int{max(int(sx) * TILE_SECTION, lo.x), max(int(sy) * TILE_SECTION, lo.y)}
		h := [2]int{min(int(sx + 1) * TILE_SECTION, hi.x), min(int(sy + 1) * TILE_SECTION, hi.y)}
		if h.x > l.x && h.y > l.y do tile_section_shapes(tm, {sx, sy}, l, h, true, &built)
	}
	for s in built.shapes[.Solid] do append(out, s)
}

// --- Which tile a shape hit -----------------------------------------------------------

// TileColliders_CellOf: the cell a contact on one of a collider body's
// shapes touched (point / normal: the map's view, the normal into the tile).
TileColliders_CellOf :: proc(body: ^StaticBodyNode, shapeId: b2.ShapeId, point, normal: [2]f32) -> (cell: [2]int, tile: i32, ok: bool) {
	info := body.tileColliders
	if info == nil || info.tileMap == nil || !Node_IsAlive(info.tileMap) do return
	tm := info.tileMap
	cs := TileMapNode_CellSize(tm)
	// Into the map's own space (its bodies sit at its origin).
	sc := tm.globalScale
	if sc.x == 0 || sc.y == 0 do sc = {1, 1}
	local := rotate_vec(point - tm.globalPosition, -tm.globalRotation) / sc
	ln := rotate_vec(normal, -tm.globalRotation)
	inside := local + ln * (min(cs.x, cs.y) * 0.25)
	for s, i in body.shapes {
		if s.shapeId != shapeId || i >= len(info.cells) do continue
		r := info.cells[i]
		if r.section == OUTLINE_SECTION do break
		if tm.layout == .Square {
			cell = {int(floor_f(inside.x / cs.x)), int(floor_f(inside.y / cs.y))}
			cell = {clamp(cell.x, int(r.lo.x), int(r.hi.x) - 1), clamp(cell.y, int(r.lo.y), int(r.hi.y) - 1)}
		} else if r.hi - r.lo == {1, 1} {
			cell = {int(r.lo.x), int(r.lo.y)}
		} else {
			cell = TileMapNode_CellAt(tm, point + normal * (min(cs.x, cs.y) * 0.25)) // (world space)
			cell = {clamp(cell.x, int(r.lo.x), int(r.hi.x) - 1), clamp(cell.y, int(r.lo.y), int(r.hi.y) - 1)}
		}
		tile = TileMapNode_Get(tm, cell.x, cell.y)
		return cell, tile, true
	}
	// A chain (or a shape not found): from the point.
	cell, tile = TileMapNode_HitCell(tm, point, -normal)
	return cell, tile, tile >= 0
}

@(private = "file")
floor_f :: proc(v: f32) -> f32 {
	i := f32(int(v))
	return i - 1 if v < 0 && i != v else i
}

// TileColliders_TriggerCell: the cell of a trigger body's sensor shape.
TileColliders_TriggerCell :: proc(body: ^StaticBodyNode, shapeId: b2.ShapeId) -> (cell: [2]int, ok: bool) {
	info := body.tileColliders
	if info == nil || info.kind != .Trigger do return
	for s, i in body.shapes do if s.shapeId == shapeId && i < len(info.cells) {
		return {int(info.cells[i].lo.x), int(info.cells[i].lo.y)}, true
	}
	return
}
