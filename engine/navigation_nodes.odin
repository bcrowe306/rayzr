package engine

import "base:runtime"
import "core:c"
import "core:math"
import "core:strings"
import lua "lua54"
import rl "vendor:raylib"

// ============================================================================
// Navigation nodes (docs/navigation.md; the grid and A*: navigation.odin).
//
// NavigationRegionNode: a rectangle (from the node's position) baked into
// cells: blocked by static physics shapes, solid tile maps and LDtk Solid
// cells inside it, plus cells scripts block at runtime (doors). It is a
// grid like a tile map's for Nav_GridFor / nav_find_path.
//
// NavigationAgentNode: put it under a moving node (a CharacterMover, a
// DynamicBody, any node); give it a target and it finds a path (in the
// region it stands in, or the map it names), follows it at its speed -
// keeping its radius from walls and steering away from other agents - and
// moves its parent (or leaves `velocity` to its script).
//
// Regions and agents are kept in their node manager's lists (navRegions,
// navAgents), so lookups don't walk the scene.
// ============================================================================

NavigationRegionNode :: struct {
	using node: Node,
	size:        [2]f32 `gui:"true" min:"16" max:"20000"`, // the area, from the node's position
	cellSize:    f32 `gui:"true" min:"2" max:"256"`,
	usePhysics:  bool `gui:"true"`, // static bodies' shapes block
	useTileMaps: bool `gui:"true"`, // solid tile maps' tiles block
	useLdtk:     bool `gui:"true"`, // LDtk cells with a Solid collision rule block
	// Baked (heap).
	cells:       [2]int,
	blocked:     []u8, // 1 = baked obstacle, 2 = blocked by a script (kept across bakes)
	baked:       bool,
	bakeVersion: u64,
	bakedAt:     [2]f32, // where the region was when baked
	bakedCell:   f32,    // the cell size it was baked with
}

NavigationRegionNode_Create :: proc(scene: ^Scene, name: string = "NavigationRegion", parent: ^Node = nil) -> ^NavigationRegionNode {
	r := CreateNode(scene.manager, NavigationRegionNode)
	r.name = strings.clone(name, r.allocator)
	r.size = {1280, 720}
	r.cellSize = 16
	r.usePhysics, r.useTileMaps, r.useLdtk = true, true, true
	r.renderable = true // (editor picking / bounds)
	r.drawBounds = proc(n: ^Node, ctx: ^GameContext, dt: f32) {NavRegion_Draw(cast(^NavigationRegionNode)n, true)}
	r.ready = proc(n: ^Node, ctx: ^GameContext) {NavRegion_Bake(cast(^NavigationRegionNode)n, ctx)}
	r.onDestroy = proc(n: ^Node, ctx: ^GameContext) {
		rr := cast(^NavigationRegionNode)n
		if rr.blocked != nil do delete(rr.blocked, Engine_HeapAllocator())
		rr.blocked = nil
		Nav_Forget(n)
	}
	scene->addNode(r, parent)
	return r
}

// NavRegion_Bake rebuilds the cells from the scene (script blocks stay).
NavRegion_Bake :: proc(r: ^NavigationRegionNode, ctx: ^GameContext = nil) {
	gc := ctx if ctx != nil else r.gameContext
	scene := gc.scene if gc != nil else nil
	cell := max(r.cellSize, 1)
	w := max(int(math.ceil(r.size.x / cell)), 1)
	h := max(int(math.ceil(r.size.y / cell)), 1)
	a := Engine_HeapAllocator()
	nb := make([]u8, w * h, a)
	// Where it is now (globalPosition may still be last frame's: a script
	// moved it and rebaked at once).
	at := Node_ComputeWorldPosition(scene.manager, r) if scene != nil && scene.manager != nil else r.globalPosition
	if r.blocked != nil {
		// Script blocks stay where they were in the world, whatever the new
		// size, cell size or place.
		if r.cells == {w, h} && r.bakedAt == at && r.bakedCell == cell {
			for v, i in r.blocked do if v == 2 do nb[i] = 2
		} else {
			for y in 0 ..< r.cells.y do for x in 0 ..< r.cells.x {
				if r.blocked[y * r.cells.x + x] != 2 do continue
				mn := r.bakedAt + [2]f32{f32(x), f32(y)} * r.bakedCell - at
				mx := mn + r.bakedCell - 0.001
				for ny in max(int(math.floor(mn.y / cell)), 0) ..= min(int(math.floor(mx.y / cell)), h - 1) {
					for nx in max(int(math.floor(mn.x / cell)), 0) ..= min(int(math.floor(mx.x / cell)), w - 1) do nb[ny * w + nx] = 2
				}
			}
		}
		delete(r.blocked, a)
	}
	r.blocked, r.cells, r.bakedAt, r.bakedCell = nb, {w, h}, at, cell
	if scene != nil && scene.manager != nil {
		for n in scene.manager.nodes {
			if n == nil || !n.enabled || n.removing do continue
			switch n.typeId {
			case StaticBodyNode:
				if r.usePhysics do for &s in (cast(^StaticBodyNode)n).shapes do region_block_shape(r, n, &s)
			case TileMapNode:
				if r.useTileMaps do region_block_tilemap(r, cast(^TileMapNode)n)
			case LdtkLevelNode:
				if r.useLdtk do region_block_ldtk(r, cast(^LdtkLevelNode)n)
			}
		}
	}
	r.baked = true
	r.bakeVersion += 1
}

@(private = "file")
region_cell_center :: #force_inline proc(r: ^NavigationRegionNode, x, y: int) -> [2]f32 {
	return r.bakedAt + [2]f32{(f32(x) + 0.5) * r.cellSize, (f32(y) + 0.5) * r.cellSize}
}

@(private = "file")
region_cell_at :: #force_inline proc(r: ^NavigationRegionNode, p: [2]f32) -> [2]int {
	return {int(math.floor((p.x - r.bakedAt.x) / r.cellSize)), int(math.floor((p.y - r.bakedAt.y) / r.cellSize))}
}

// region_block_rect blocks the cells whose centres are in a world AABB.
@(private = "file")
region_block_rect :: proc(r: ^NavigationRegionNode, mn, mx: [2]f32) {
	c0, c1 := region_cell_at(r, mn), region_cell_at(r, mx)
	for y in max(c0.y, 0) ..= min(c1.y, r.cells.y - 1) do for x in max(c0.x, 0) ..= min(c1.x, r.cells.x - 1) {
		c := region_cell_center(r, x, y)
		i := y * r.cells.x + x
		if c.x >= mn.x && c.x <= mx.x && c.y >= mn.y && c.y <= mx.y && r.blocked[i] == 0 do r.blocked[i] = 1
	}
}

@(private = "file")
len2 :: #force_inline proc(v: [2]f32) -> f32 {return math.sqrt(v.x * v.x + v.y * v.y)}

@(private = "file")
seg_d2 :: proc(p, a, b: [2]f32) -> f32 {
	ab := b - a
	ll := ab.x * ab.x + ab.y * ab.y
	t := clamp(((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / ll, 0, 1) if ll > 0 else 0
	q := a + ab * t
	return (p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y)
}

@(private = "file")
in_poly :: proc(p: [2]f32, v: [][2]f32) -> bool {
	inside := false
	j := len(v) - 1
	for i in 0 ..< len(v) {
		if (v[i].y > p.y) != (v[j].y > p.y) && p.x < (v[j].x - v[i].x) * (p.y - v[i].y) / (v[j].y - v[i].y) + v[i].x do inside = !inside
		j = i
	}
	return inside
}

// region_block_shape blocks the cells a physics shape covers: its world
// bounds, then each cell centre tested in the shape's own frame.
@(private = "file")
region_block_shape :: proc(r: ^NavigationRegionNode, n: ^Node, s: ^PhysicsShape) {
	scl := n.globalScale
	sx, sy := abs(scl.x) if scl.x != 0 else 1, abs(scl.y) if scl.y != 0 else 1
	smax := max(sx, sy)
	rot := (n.globalRotation + s.rotation) * math.RAD_PER_DEG
	c, sn := math.cos(rot), math.sin(rot)
	center := n.globalPosition + rotate_vec(s.offset * scl, n.globalRotation)
	half := r.cellSize * 0.5
	ext: f32
	switch s.type {
	case .Circle: ext = s.radius * smax
	case .Box, .RoundedBox: ext = len2({s.size.x * sx, s.size.y * sy}) * 0.5
	case .Capsule: ext = (max(len2(s.point1), len2(s.point2)) + s.radius) * smax
	case .Polygon: for v in s.vertices[:s.vertexCount] do ext = max(ext, len2(v) * smax)
	case .Segment: ext = max(len2(s.point1), len2(s.point2)) * smax + half
	case .Chain:
		for v in s.chainPoints do ext = max(ext, len2(v) * smax)
		ext += half
	}
	c0, c1 := region_cell_at(r, center - ext), region_cell_at(r, center + ext)
	for y in max(c0.y, 0) ..= min(c1.y, r.cells.y - 1) do for x in max(c0.x, 0) ..= min(c1.x, r.cells.x - 1) {
		i := y * r.cells.x + x
		if r.blocked[i] != 0 do continue
		d := region_cell_center(r, x, y) - center
		l := [2]f32{(d.x * c + d.y * sn) / sx, (-d.x * sn + d.y * c) / sy} // in the shape's frame
		inside := false
		switch s.type {
		case .Circle: inside = l.x * l.x + l.y * l.y <= s.radius * s.radius
		case .Box, .RoundedBox: inside = abs(l.x) <= s.size.x * 0.5 && abs(l.y) <= s.size.y * 0.5
		case .Capsule: inside = seg_d2(l, s.point1, s.point2) <= s.radius * s.radius
		case .Polygon: inside = in_poly(l, s.vertices[:s.vertexCount])
		case .Segment: inside = seg_d2(l, s.point1, s.point2) <= half * half
		case .Chain:
			for k in 0 ..< len(s.chainPoints) - 1 do if seg_d2(l, s.chainPoints[k], s.chainPoints[k + 1]) <= half * half {inside = true; break}
			if s.isLoop && len(s.chainPoints) > 2 && seg_d2(l, s.chainPoints[len(s.chainPoints) - 1], s.chainPoints[0]) <= half * half do inside = true
		}
		if inside do r.blocked[i] = 1
	}
}

@(private = "file")
region_block_tilemap :: proc(r: ^NavigationRegionNode, tm: ^TileMapNode) {
	if !tm.solid do return
	cs := TileMapNode_CellSize(tm)
	ts := cs * tm.globalScale
	TileMapNode_Layout(tm)
	for t, i in tm.tiles {
		if t < 0 do continue
		cell := tm.dataOrigin + {i % max(tm.dataSize.x, 1), i / max(tm.dataSize.x, 1)}
		if tm.layout == .Square && tm.globalRotation == 0 {
			mn := TileMapNode_CellCorner(tm, cell)
			region_block_rect(r, mn, mn + ts)
			continue
		}
		// Any other cell: the region cells whose centres are in its outline.
		pts, n := TileMapNode_CellOutline(tm, cell)
		world: [6][2]f32
		mn, mx := [2]f32{math.F32_MAX, math.F32_MAX}, [2]f32{-math.F32_MAX, -math.F32_MAX}
		for p, k in pts[:n] {
			world[k] = TileMapNode_LocalToWorld(tm, p)
			mn = {min(mn.x, world[k].x), min(mn.y, world[k].y)}
			mx = {max(mx.x, world[k].x), max(mx.y, world[k].y)}
		}
		c0, c1 := region_cell_at(r, mn), region_cell_at(r, mx)
		for y in max(c0.y, 0) ..= min(c1.y, r.cells.y - 1) do for x in max(c0.x, 0) ..= min(c1.x, r.cells.x - 1) {
			if point_in_convex(region_cell_center(r, x, y), world[:n]) do r.blocked[y * r.cells.x + x] = max(r.blocked[y * r.cells.x + x], 1)
		}
	}
}

@(private = "file")
region_block_ldtk :: proc(r: ^NavigationRegionNode, ln: ^LdtkLevelNode) {
	for lvl in ln.activeLevels {
		off := ln.globalPosition + LdtkLevelNode_LevelOffset(ln, lvl) * ln.globalScale
		for &layer in lvl.layers {
			if layer.type != .IntGrid || len(layer.intGrid) == 0 do continue
			gs := f32(layer.gridSize) * ln.globalScale
			for v, i in layer.intGrid {
				if v == 0 || LdtkLevelNode_CollisionRule(ln, layer.identifier, v).type != .Solid do continue
				mn := off + (layer.offset + {f32(i % max(layer.cWid, 1)), f32(i / max(layer.cWid, 1))} * f32(layer.gridSize)) * ln.globalScale
				region_block_rect(r, mn, mn + gs)
			}
		}
	}
}

// NavRegion_SetBlocked blocks / opens the cells under a world rectangle
// (doors, bridges, a placed tower).
NavRegion_SetBlocked :: proc(r: ^NavigationRegionNode, mn, mx: [2]f32, blocked: bool) {
	if !r.baked do NavRegion_Bake(r)
	c0, c1 := region_cell_at(r, mn), region_cell_at(r, mx - 0.001)
	for y in max(c0.y, 0) ..= min(c1.y, r.cells.y - 1) do for x in max(c0.x, 0) ..= min(c1.x, r.cells.x - 1) {
		i := y * r.cells.x + x
		if blocked do r.blocked[i] = 2
		else if r.blocked[i] == 2 do r.blocked[i] = 0
	}
	r.bakeVersion += 1 // (the grid cache rebuilds)
}

// Nav_RegionAt: the region whose rectangle holds a world point.
Nav_RegionAt :: proc(m: ^NodeManager, p: [2]f32) -> ^NavigationRegionNode {
	if m == nil do return nil
	for n in m.navRegions {
		r := cast(^NavigationRegionNode)n
		if !r.enabled || r.removing do continue
		o := r.bakedAt if r.baked else r.globalPosition // (the cells' place)
		if p.x >= o.x && p.y >= o.y && p.x < o.x + r.size.x && p.y < o.y + r.size.y do return r
	}
	return nil
}

// NavRegion_Draw (editor / debug bounds): the outline and blocked cells.
NavRegion_Draw :: proc(r: ^NavigationRegionNode, cellsToo: bool) {
	o := r.globalPosition // (the outline: where it is; the cells: where they were baked)
	rl.DrawRectangleLinesEx({o.x, o.y, r.size.x, r.size.y}, 1, {96, 165, 250, 200})
	if !cellsToo || !r.baked do return
	for y in 0 ..< r.cells.y do for x in 0 ..< r.cells.x {
		b := r.blocked[y * r.cells.x + x]
		if b == 0 do continue
		rl.DrawRectangleV(r.bakedAt + {f32(x), f32(y)} * r.cellSize, {r.cellSize, r.cellSize}, {239, 68, 68, 60} if b == 1 else {250, 204, 21, 90})
	}
}

// --- agents ------------------------------------------------------------------------------

NavigationAgentNode :: struct {
	using node: Node,
	speed:          f32 `gui:"true" min:"0" max:"2000"`, // px/s
	radius:         f32 `gui:"true" min:"0" max:"500"`,  // keeps this far from walls and from other agents
	arriveDistance: f32 `gui:"true" min:"1" max:"200"`,  // close enough to the target
	repathInterval: f32 `gui:"true" min:"0" max:"10"`,   // seconds between path updates (0: only for a new target)
	navMap:         string `gui:"true"`,                // a NavigationRegion / TileMap / LDtk level to path in ("" = the region it stands in)
	moveParent:     bool `gui:"true"`,                  // move the parent (else scripts read `velocity`)
	avoidance:      bool `gui:"true"`,                  // steer away from other agents
	velocity:       [2]f32 `gui:"true" save:"false"`,   // the velocity it wants now (px/s)
	// Runtime.
	target:     [2]f32,
	hasTarget:  bool,
	path:       [dynamic][2]f32, // world points (heap)
	pathIndex:  int,
	pathTarget: [2]f32,          // the target the path was found for
	repathT:    f32,
	finished:   bool,
	drove:      bool,            // it set its parent's velocity last frame (cleared once when it stops)
	onFinished: EventSubject,    // "navigation_finished": arrived
	onUnreachable: EventSubject, // "target_unreachable": no way there
}

NavigationAgentNode_Create :: proc(scene: ^Scene, name: string = "NavigationAgent", parent: ^Node = nil) -> ^NavigationAgentNode {
	a := CreateNode(scene.manager, NavigationAgentNode)
	a.name = strings.clone(name, a.allocator)
	a.speed, a.radius, a.arriveDistance, a.repathInterval = 120, 10, 6, 0.5
	a.moveParent, a.avoidance = true, true
	a.path = make([dynamic][2]f32, Engine_HeapAllocator())
	a.update = NavigationAgentNode_Update
	a.onDestroy = proc(n: ^Node, ctx: ^GameContext) {
		ag := cast(^NavigationAgentNode)n
		delete(ag.path)
		DestroySubject(&ag.onFinished)
		DestroySubject(&ag.onUnreachable)
	}
	InitializeSubject(&a.onFinished, "navigation_finished", a)
	InitializeSubject(&a.onUnreachable, "target_unreachable", a)
	scene->addNode(a, parent)
	return a
}

// NavAgent_Position: where the agent is (its parent's position).
NavAgent_Position :: proc(a: ^NavigationAgentNode, m: ^NodeManager) -> [2]f32 {
	if p := GetParent(m, a) if m != nil else nil; p != nil do return p.globalPosition
	return a.globalPosition
}

// NavAgent_SetTarget: go there (the path is found on the next update).
// Safe every frame (#218): the same target (within Arrive Distance) changes
// nothing - nor does it raise navigation_finished again once there; a moved
// one is taken up by the next repath (Repath Interval; 0: at once).
NavAgent_SetTarget :: proc(a: ^NavigationAgentNode, target: [2]f32) {
	d := target - a.target
	same := d.x * d.x + d.y * d.y <= a.arriveDistance * a.arriveDistance
	if (a.hasTarget || a.finished) && same do return
	if a.hasTarget && a.repathInterval > 0 {
		a.target = target
		return
	}
	a.target, a.hasTarget, a.finished = target, true, false
	a.repathT = 0
	clear(&a.path)
	a.pathIndex = 0
}

NavAgent_Stop :: proc(a: ^NavigationAgentNode) {
	a.hasTarget, a.velocity = false, {}
	clear(&a.path)
	a.pathIndex = 0
}

// nav_agent_grid: the grid the agent paths in.
@(private = "file")
nav_agent_grid :: proc(a: ^NavigationAgentNode, m: ^NodeManager, pos: [2]f32) -> ^Nav_Grid {
	if a.navMap != "" && m != nil {
		if n := Node_ResolvePath(m, a, a.navMap); n != nil do return Nav_GridFor(n)
	}
	if r := Nav_RegionAt(m, pos); r != nil do return Nav_GridFor(r)
	return nil
}

@(private = "file")
nav_agent_repath :: proc(a: ^NavigationAgentNode, m: ^NodeManager, pos: [2]f32, ctx: ^GameContext) {
	clear(&a.path)
	a.pathIndex = 0
	g := nav_agent_grid(a, m, pos)
	pts := Nav_FindPath(g, pos, a.target, {diagonal = true, smooth = true, radius = a.radius})
	a.pathTarget = a.target
	if pts == nil {
		a.hasTarget = false
		a.onUnreachable->notify(a, nil, ctx)
		return
	}
	for p in pts[1:] do append(&a.path, p) // (the first is where it stands)
}

NavigationAgentNode_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	a := cast(^NavigationAgentNode)node
	m := ctx.scene.manager if ctx != nil && ctx.scene != nil else nil
	body := GetParent(m, a) if m != nil else nil
	pos := NavAgent_Position(a, m)
	a.velocity = {}
	v: [2]f32
	moving := a.hasTarget && !a.finished
	if moving {
		a.repathT -= dt
		if len(a.path) == 0 || (a.repathInterval > 0 && a.repathT <= 0) {
			nav_agent_repath(a, m, pos, ctx)
			a.repathT = a.repathInterval
			moving = a.hasTarget
		}
	}
	if moving {
		for a.pathIndex < len(a.path) {
			d := a.path[a.pathIndex] - pos
			reach := a.arriveDistance if a.pathIndex == len(a.path) - 1 else max(a.arriveDistance, a.radius * 0.5)
			if d.x * d.x + d.y * d.y > reach * reach do break
			a.pathIndex += 1
		}
		// The end of a path to where the target was: go on to where it is.
		if a.pathIndex >= len(a.path) {
			d := a.target - a.pathTarget
			if d.x * d.x + d.y * d.y > a.arriveDistance * a.arriveDistance {
				nav_agent_repath(a, m, pos, ctx)
				a.repathT = a.repathInterval
				moving = a.hasTarget
			}
		}
		if !moving {
		} else if a.pathIndex >= len(a.path) {
			a.finished, a.hasTarget = true, false
			moving = false
			a.onFinished->notify(a, nil, ctx)
		} else {
			d := a.path[a.pathIndex] - pos
			l := len2(d)
			v = d / l * a.speed if l > 0 else [2]f32{}
			if l > 0 && l < a.speed * dt do v = d / dt // (don't overshoot the last point)
		}
	}
	// Separation from nearby agents - also when standing still, so a crowd
	// at one spot spreads out.
	if a.avoidance && m != nil {
		push: [2]f32
		for on in m.navAgents {
			o := cast(^NavigationAgentNode)on
			if o == a || !o.enabled || o.removing do continue
			dd := pos - NavAgent_Position(o, m)
			want := a.radius + o.radius
			dist := len2(dd)
			if dist >= want || want <= 0 do continue
			if dist < 0.01 do dd, dist = {1, 0} if uintptr(a) < uintptr(o) else {-1, 0}, 1
			push += dd / dist * (1 - dist / want)
		}
		v += push * a.speed
		if vl := len2(v); vl > a.speed do v = v / vl * a.speed
	}
	a.velocity = v
	if !a.moveParent || body == nil do return
	if v == {} {
		// Stopped: a body it was driving stops too (once - then physics owns it).
		if a.drove {
			if body.typeId == DynamicBodyNode do (cast(^DynamicBodyNode)body).linearVelocity = {}
			if body.typeId == KinematicBodyNode do (cast(^KinematicBodyNode)body).linearVelocity = {}
			if body.typeId == CharacterMoverNode do (cast(^CharacterMoverNode)body).velocity = {}
		}
		a.drove = false
		return
	}
	a.drove = true
	switch body.typeId {
	case CharacterMoverNode:
		cm := cast(^CharacterMoverNode)body
		cm.velocity = v
		if cm.controlMode == .Script do CharacterMoverNode_MoveAndSlide(cm, ctx, dt)
	case DynamicBodyNode:
		(cast(^DynamicBodyNode)body).linearVelocity = v
	case KinematicBodyNode:
		(cast(^KinematicBodyNode)body).linearVelocity = v
	case:
		body.position += Node_WorldToParent(m, body, pos + v * dt) - Node_WorldToParent(m, body, pos)
	}
}

// NavAgent_DistanceLeft: path length still to go (px).
NavAgent_DistanceLeft :: proc(a: ^NavigationAgentNode, from: [2]f32) -> f32 {
	total: f32
	p := from
	for i in a.pathIndex ..< len(a.path) {
		total += len2(a.path[i] - p)
		p = a.path[i]
	}
	return total
}

// --- Lua -------------------------------------------------------------------------------
// region:nav_rebake()                         after moving obstacles / changing the map
// region:nav_set_blocked(x, y, w, h, blocked) block / open a world rectangle (doors)
// agent:nav_set_target(x, y | Vec2) / agent:nav_stop() / agent:nav_is_finished()
// agent:nav_get_path() -> { {x, y}, ... } (still to go) / agent:nav_distance_left()

@(private = "file")
lua_region :: proc(L: ^lua.State) -> ^NavigationRegionNode {
	n, ok := to_node_userdata(L, 1)
	return cast(^NavigationRegionNode)n if ok && n.typeId == NavigationRegionNode else nil
}

@(private = "file")
lua_agent :: proc(L: ^lua.State) -> ^NavigationAgentNode {
	n, ok := to_node_userdata(L, 1)
	return cast(^NavigationAgentNode)n if ok && n.typeId == NavigationAgentNode else nil
}

@(private = "file")
lua_nav_rebake :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if r := lua_region(L); r != nil do NavRegion_Bake(r)
	return 0
}

@(private = "file")
lua_nav_set_blocked :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	r := lua_region(L)
	if r == nil do return 0
	// The corner and the size: numbers or Vec2s (#327); the flag after them.
	x, y, next := arg_xy_next(L, 2)
	w, h, flag := arg_xy_next(L, next)
	NavRegion_SetBlocked(r, {x, y}, {x + w, y + h}, lua.type(L, flag) != .BOOLEAN || bool(lua.toboolean(L, flag)))
	return 0
}

@(private = "file")
lua_nav_set_target :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if a := lua_agent(L); a != nil {
		x, y := arg_xy(L, 2)
		NavAgent_SetTarget(a, {x, y})
	}
	return 0
}

@(private = "file")
lua_nav_stop :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if a := lua_agent(L); a != nil do NavAgent_Stop(a)
	return 0
}

@(private = "file")
lua_nav_is_finished :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	a := lua_agent(L)
	lua.pushboolean(L, b32(a == nil || a.finished || !a.hasTarget))
	return 1
}

@(private = "file")
lua_nav_get_path :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	a := lua_agent(L)
	if a == nil {
		lua.createtable(L, 0, 0)
		return 1
	}
	pts := a.path[min(a.pathIndex, len(a.path)):]
	lua.createtable(L, c.int(len(pts)), 0)
	for p, i in pts {
		lua.createtable(L, 2, 0)
		lua.pushnumber(L, lua.Number(p.x)); lua.rawseti(L, -2, 1)
		lua.pushnumber(L, lua.Number(p.y)); lua.rawseti(L, -2, 2)
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

@(private = "file")
lua_nav_distance_left :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	a := lua_agent(L)
	sm := get_script_manager(L)
	m := sm.game.sceneManager.currentScene.manager if a != nil && sm != nil && sm.game != nil && sm.game.sceneManager.currentScene != nil else nil
	lua.pushnumber(L, lua.Number(NavAgent_DistanceLeft(a, NavAgent_Position(a, m)) if a != nil else 0))
	return 1
}

// Script_RegisterNavNodeBindings adds the region / agent methods to the
// node metatable (on the stack).
Script_RegisterNavNodeBindings :: proc(L: ^lua.State) {
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "nav_rebake", lua_nav_rebake)
	reg(L, "nav_set_blocked", lua_nav_set_blocked)
	reg(L, "nav_set_target", lua_nav_set_target)
	reg(L, "nav_stop", lua_nav_stop)
	reg(L, "nav_is_finished", lua_nav_is_finished)
	reg(L, "nav_get_path", lua_nav_get_path)
	reg(L, "nav_distance_left", lua_nav_distance_left)
}
