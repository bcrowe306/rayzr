package engine

import "core:c"
import "core:fmt"
import "core:math"
import "core:path/filepath"
import "core:strings"
import lua "lua54"

// ============================================================================
// Components on a tile map: a second layer on the same grid. Painting a
// component puts a linked instance of it (a real child node, saved with the
// scene like any instance: select it, nudge it, override its properties)
// on the cell; editing the .component.json updates every painted copy.
//
// One component per cell. A component bigger than a cell takes its whole
// footprint (its drawn size rounded to cells), centred on what it was
// painted on: a 2 x 2 tree painted on a cell covers it and the cells right
// and below. Instances snap to the centre of their footprint; off-grid
// ones (Shift in the editor) occupy the footprint nearest to them.
//
// Nothing extra is saved: which cells an instance covers is worked out from
// its position and its component's footprint, so moving it by hand moves
// what it occupies. Every component instance directly under the tile map
// is on the layer. Its colliders are its own (`solid` only covers tiles).
// ============================================================================

// TILEMAP_FILL_MAX: the most instances one flood fill places.
TILEMAP_FILL_MAX :: 4096

// Tile_Component: an instance on the layer and the cells it covers.
Tile_Component :: struct {
	node:    ^Node,
	cell:    [2]int, // the footprint's top-left cell
	size:    [2]int, // the footprint in cells
}

// TileMapNode_ComponentFootprint: a component's size in cells (its drawn
// bounds, rounded to cells; at least 1 x 1), measured once per path.
TileMapNode_ComponentFootprint :: proc(tm: ^TileMapNode, path: string, sample: ^Node = nil) -> [2]int {
	if tm.layout != .Square do return {1, 1} // (a cell each off square grids)
	key := tilemap_fp_key(tm, path)
	if fp, ok := tm.compFootprints[key]; ok do return fp
	fp := [2]int{1, 1}
	if sample != nil && sample.gameContext != nil && sample.gameContext.scene != nil {
		m := sample.gameContext.scene.manager
		b, have := tilemap_subtree_bounds(m, sample)
		if have {
			s := [2]f32{abs(tm.globalScale.x), abs(tm.globalScale.y)}
			if s.x == 0 do s.x = 1
			if s.y == 0 do s.y = 1
			wpx := (b[2] - b[0]) / s.x
			hpx := (b[3] - b[1]) / s.y
			// (A little slack: a 33 px sprite on 32 px tiles is still one cell.)
			cs := TileMapNode_CellSize(tm)
			fp = {max(int(math.ceil(wpx / cs.x - 0.1)), 1), max(int(math.ceil(hpx / cs.y - 0.1)), 1)}
		}
	} else if sample == nil {
		return fp // (not measured: don't remember a guess)
	}
	if tm.compFootprints == nil do tm.compFootprints = make(map[string][2]int, tm.allocator)
	tm.compFootprints[strings.clone(key, tm.allocator)] = fp
	return fp
}

// tilemap_fp_key: footprints depend on the component and the tile size.
@(private = "file")
tilemap_fp_key :: proc(tm: ^TileMapNode, path: string) -> string {
	cs := TileMapNode_CellSize(tm)
	return fmt.tprintf("%s|%dx%d", path, int(cs.x), int(cs.y))
}

// TileMapNode_ForgetFootprints: measure components again (a component file
// changed).
TileMapNode_ForgetFootprints :: proc(tm: ^TileMapNode) {
	clear(&tm.compFootprints)
}

// tilemap_subtree_bounds: the world rectangle a node and its children draw
// (bodies' shapes count too).
@(private = "file")
tilemap_subtree_bounds :: proc(m: ^NodeManager, n: ^Node) -> (b: [4]f32, have: bool) {
	add :: proc(b: ^[4]f32, have: ^bool, r: [4]f32) {
		if !have^ {b^, have^ = r, true; return}
		b^ = {min(b[0], r[0]), min(b[1], r[1]), max(b[2], r[2]), max(b[3], r[3])}
	}
	if r, ok := Node_RenderBounds(n); ok do add(&b, &have, {r.x, r.y, r.x + r.width, r.y + r.height})
	shapes: []PhysicsShape
	switch n.typeId {
	case StaticBodyNode: shapes = (cast(^StaticBodyNode)n).shapes[:]
	case DynamicBodyNode: shapes = (cast(^DynamicBodyNode)n).shapes[:]
	case KinematicBodyNode: shapes = (cast(^KinematicBodyNode)n).shapes[:]
	case AreaNode: shapes = (cast(^AreaNode)n).shapes[:]
	}
	for &s in shapes {
		g := PhysicsShape_Scaled(&s, n.globalScale)
		half := g.size * 0.5
		if g.type == .Circle do half = {g.radius, g.radius}
		if g.type == .Capsule do half = {g.radius, g.size.y * 0.5 + g.radius}
		cc := n.globalPosition + rotate_vec(g.offset, n.globalRotation)
		add(&b, &have, {cc.x - abs(half.x), cc.y - abs(half.y), cc.x + abs(half.x), cc.y + abs(half.y)})
	}
	if m != nil do for ch in GetChildrenView(m, n) do if ch != nil {
		if r, ok := tilemap_subtree_bounds(m, ch); ok do add(&b, &have, r)
	}
	return
}

// tilemap_block_of: the footprint (top-left cell) an instance at a local
// position covers.
@(private = "file")
tilemap_block_of :: proc(tm: ^TileMapNode, pos: [2]f32, size: [2]int) -> [2]int {
	if tm.layout != .Square do return TileMapNode_LocalCellAt(tm, pos)
	ts := TileMapNode_CellSize(tm)
	return {int(math.round(pos.x / ts.x - f32(size.x) * 0.5)), int(math.round(pos.y / ts.y - f32(size.y) * 0.5))}
}

// TileMapNode_BlockFor: the footprint a component painted on a cell covers.
TileMapNode_BlockFor :: proc(cell, size: [2]int) -> [2]int {
	return cell - (size - 1) / 2
}

// TileMapNode_BlockCenter: the local position of a footprint's centre.
// (Square grids; the others' components take a cell each.)
TileMapNode_BlockCenter :: proc(tm: ^TileMapNode, topLeft, size: [2]int) -> [2]f32 {
	if tm.layout != .Square do return TileMapNode_CellLocalCenter(tm, topLeft)
	cs := TileMapNode_CellSize(tm)
	return {(f32(topLeft.x) + f32(size.x) * 0.5) * cs.x, (f32(topLeft.y) + f32(size.y) * 0.5) * cs.y}
}

// TileMapNode_Components: the instances on the layer and their footprints.
TileMapNode_Components :: proc(tm: ^TileMapNode, allocator := context.temp_allocator) -> []Tile_Component {
	out := make([dynamic]Tile_Component, allocator)
	if tm.gameContext == nil || tm.gameContext.scene == nil do return out[:]
	for ch in GetChildrenView(tm.gameContext.scene.manager, tm) {
		if ch == nil || ch.componentPath == "" || ch.removing do continue
		size := TileMapNode_ComponentFootprint(tm, ch.componentPath, ch)
		append(&out, Tile_Component{ch, tilemap_block_of(tm, ch.position, size), size})
	}
	return out[:]
}

// TileMapNode_ComponentAt: the instance covering a cell (nil: none).
TileMapNode_ComponentAt :: proc(tm: ^TileMapNode, cell: [2]int) -> ^Node {
	for tc in TileMapNode_Components(tm) {
		if cell.x >= tc.cell.x && cell.y >= tc.cell.y && cell.x < tc.cell.x + tc.size.x && cell.y < tc.cell.y + tc.size.y do return tc.node
	}
	return nil
}

// tilemap_occupancy: cell -> the instance covering it.
@(private = "file")
tilemap_occupancy :: proc(tm: ^TileMapNode) -> map[[2]int]^Node {
	occ := make(map[[2]int]^Node, allocator = context.temp_allocator)
	for tc in TileMapNode_Components(tm) {
		for y in 0 ..< tc.size.y do for x in 0 ..< tc.size.x do occ[tc.cell + {x, y}] = tc.node
	}
	return occ
}

@(private = "file")
in_map :: proc(tm: ^TileMapNode, cell: [2]int) -> bool {
	return cell.x >= 0 && cell.y >= 0 && cell.x < tm.mapSize.x && cell.y < tm.mapSize.y
}

// TileMapNode_RemoveComponentAt removes the instance covering a cell.
TileMapNode_RemoveComponentAt :: proc(tm: ^TileMapNode, cell: [2]int) -> bool {
	n := TileMapNode_ComponentAt(tm, cell)
	if n == nil do return false
	m := tm.gameContext.scene.manager
	RemoveNode(m, n)
	ProcessNodeQueues(m, tm.gameContext)
	return true
}

// tilemap_instance makes a linked instance of a component under the map at
// a local position, named after the component and its cell.
@(private = "file")
tilemap_instance :: proc(tm: ^TileMapNode, path: string, pos: [2]f32, cell: [2]int) -> ^Node {
	ctx := tm.gameContext
	if ctx == nil || ctx.scene == nil do return nil
	m := ctx.scene.manager
	n := Scene_InstantiateComponent(ctx.scene, path, tm, ctx)
	if n == nil do return nil
	base := filepath.stem(filepath.stem(path))
	name := fmt.tprintf("%s_%d_%d", base, cell.x, cell.y)
	// (Unique among the map's children: a moved instance may hold the name.)
	for k := 2; ; k += 1 {
		taken := false
		for ch in GetChildrenView(m, tm) do if ch != n && ch.name == name {taken = true; break}
		if !taken do break
		name = fmt.tprintf("%s_%d_%d_%d", base, cell.x, cell.y, k)
	}
	n.name = strings.clone(name, n.allocator)
	n.position = pos
	ProcessNodeQueues(m, ctx)
	Node_SetGlobalPositions(m, tm.parent if tm.parent != nil else ctx.scene.rootNode)
	return n
}

// TileMapNode_PlaceComponent paints a component on a cell: its footprint
// (centred on the cell, kept inside the map) replaces what was there.
// offGrid: place it at `local` instead (it covers the footprint nearest).
// Returns the instance (nil: outside the map or the component can't load).
TileMapNode_PlaceComponent :: proc(tm: ^TileMapNode, cell: [2]int, path: string, offGrid := false, local: [2]f32 = {}) -> ^Node {
	if path == "" || !in_map(tm, cell) do return nil
	TileMapNode_Layout(tm)
	ctx := tm.gameContext
	if ctx == nil || ctx.scene == nil do return nil
	n := tilemap_instance(tm, path, local if offGrid else TileMapNode_BlockCenter(tm, cell, {1, 1}), cell)
	if n == nil do return nil
	size := TileMapNode_ComponentFootprint(tm, path, n)
	top := tilemap_block_of(tm, n.position, size) if offGrid else TileMapNode_BlockFor(cell, size)
	// Inside the map.
	top = {clamp(top.x, 0, max(tm.mapSize.x - size.x, 0)), clamp(top.y, 0, max(tm.mapSize.y - size.y, 0))}
	if !offGrid do n.position = TileMapNode_BlockCenter(tm, top, size)
	// What it covers goes.
	m := ctx.scene.manager
	for tc in TileMapNode_Components(tm) {
		if tc.node == n do continue
		if tc.cell.x < top.x + size.x && top.x < tc.cell.x + tc.size.x && tc.cell.y < top.y + size.y && top.y < tc.cell.y + tc.size.y {
			RemoveNode(m, tc.node)
		}
	}
	ProcessNodeQueues(m, ctx)
	Node_SetGlobalPositions(m, tm.parent if tm.parent != nil else ctx.scene.rootNode)
	return n
}

// TileMapNode_FillComponents flood-fills the empty cells connected to a
// cell with a component (bigger ones placed where their footprint fits).
// Returns how many it placed (at most TILEMAP_FILL_MAX).
TileMapNode_FillComponents :: proc(tm: ^TileMapNode, cell: [2]int, path: string) -> int {
	if path == "" || !in_map(tm, cell) do return 0
	occ := tilemap_occupancy(tm)
	if cell in occ do return 0
	// The region: empty cells connected to it.
	region := make(map[[2]int]bool, allocator = context.temp_allocator)
	stack := make([dynamic][2]int, context.temp_allocator)
	append(&stack, cell)
	for len(stack) > 0 {
		p := pop(&stack)
		if !in_map(tm, p) || p in region || p in occ do continue
		region[p] = true
		append(&stack, p + {1, 0}, p - {1, 0}, p + {0, 1}, p - {0, 1})
	}
	// The footprint (measured on a first instance if not known yet).
	size, known := tm.compFootprints[tilemap_fp_key(tm, path)]
	if !known do size = {1, 1}
	placed := 0
	used := make(map[[2]int]bool, allocator = context.temp_allocator)
	for y in 0 ..< tm.mapSize.y {
		for x in 0 ..< tm.mapSize.x {
			if placed >= TILEMAP_FILL_MAX do return placed
			top := [2]int{x, y}
			if !(top in region) || top in used do continue
			fits := top.x + size.x <= tm.mapSize.x && top.y + size.y <= tm.mapSize.y
			for dy in 0 ..< size.y do for dx in 0 ..< size.x {
				q := top + {dx, dy}
				if !(q in region) || q in used do fits = false
			}
			if !fits do continue
			n := tilemap_instance(tm, path, TileMapNode_BlockCenter(tm, top, size), top)
			if n == nil do return placed
			if !known {
				// (Now measured: a bigger one is placed again where it fits.)
				known = true
				real := TileMapNode_ComponentFootprint(tm, path, n)
				if real != size {
					RemoveNode(tm.gameContext.scene.manager, n)
					ProcessNodeQueues(tm.gameContext.scene.manager, tm.gameContext)
					size = real
					return placed + TileMapNode_FillComponents(tm, cell, path)
				}
			}
			for dy in 0 ..< size.y do for dx in 0 ..< size.x do used[top + {dx, dy}] = true
			placed += 1
		}
	}
	return placed
}

// Tile_Component_Place: a component to paint on a cell (TileMapNode_PlaceComponents).
Tile_Component_Place :: struct {
	component: string,
	cell:      [2]int,
}

// TileMapNode_PlaceComponents paints many components at once (a level
// generator's output that writes components, #171), in order: each takes
// its footprint centred on its cell (kept inside the map) unless that
// overlaps one placed earlier in the call - then it is skipped. Instances
// already on the layer under a footprint go. The queues are processed once,
// at the end. Returns the instances placed (temp) and the first component
// that couldn't load.
//
// `area` (lo.x, lo.y, hi.x, hi.y; zero: the map): the cells it places in - a
// chunk of an endless map's (#171), negative cells too.
TileMapNode_PlaceComponents :: proc(tm: ^TileMapNode, items: []Tile_Component_Place, scene: ^Scene, ctx: ^GameContext, area := [4]int{}) -> (placed: []^Node, err: string) {
	out := make([dynamic]^Node, context.temp_allocator)
	gc := ctx if ctx != nil else tm.gameContext
	if scene == nil || scene.manager == nil || len(items) == 0 do return out[:], ""
	m := scene.manager
	TileMapNode_Layout(tm)
	top_node := tm.parent if tm.parent != nil else scene.rootNode
	// What is on the layer now, and the children's names.
	occ := make(map[[2]int]^Node, allocator = context.temp_allocator)
	names := make(map[string]bool, allocator = context.temp_allocator)
	for ch in GetChildrenView(m, tm) {
		if ch == nil || ch.removing do continue
		names[ch.name] = true
		if ch.componentPath == "" do continue
		size := TileMapNode_ComponentFootprint(tm, ch.componentPath, ch)
		top := tilemap_block_of(tm, ch.position, size)
		for y in 0 ..< size.y do for x in 0 ..< size.x do occ[top + {x, y}] = ch
	}
	taken := make(map[[2]int]bool, allocator = context.temp_allocator)
	bad := make(map[string]bool, allocator = context.temp_allocator)
	lo, hi := [2]int{0, 0}, tm.mapSize
	if area != {} do lo, hi = {area[0], area[1]}, {area[2], area[3]}
	for it in items {
		if it.component == "" || it.component in bad || it.cell.x < lo.x || it.cell.y < lo.y || it.cell.x >= hi.x || it.cell.y >= hi.y || it.cell in taken do continue
		size, known := tm.compFootprints[tilemap_fp_key(tm, it.component)]
		n: ^Node
		if !known {
			// Measured on a first instance (in the tree, placed).
			n = Scene_InstantiateComponent(scene, it.component, tm, gc)
			if n == nil {
				bad[it.component] = true
				if err == "" do err = fmt.tprintf("no component %s", it.component)
				continue
			}
			n.position = TileMapNode_BlockCenter(tm, it.cell, {1, 1})
			ProcessNodeQueues(m, gc)
			Node_SetGlobalPositions(m, top_node)
			size = TileMapNode_ComponentFootprint(tm, it.component, n)
		}
		top := TileMapNode_BlockFor(it.cell, size)
		top = {clamp(top.x, lo.x, max(hi.x - size.x, lo.x)), clamp(top.y, lo.y, max(hi.y - size.y, lo.y))}
		free := true
		for y in 0 ..< size.y do for x in 0 ..< size.x do if top + {x, y} in taken do free = false
		if !free {
			if n != nil do RemoveNode(m, n)
			continue
		}
		if n == nil {
			n = Scene_InstantiateComponent(scene, it.component, tm, gc)
			if n == nil {
				bad[it.component] = true
				if err == "" do err = fmt.tprintf("no component %s", it.component)
				continue
			}
		}
		for y in 0 ..< size.y do for x in 0 ..< size.x {
			c := top + {x, y}
			taken[c] = true
			if o, ok := occ[c]; ok && !o.removing do RemoveNode(m, o)
		}
		n.position = TileMapNode_BlockCenter(tm, top, size)
		base := filepath.stem(filepath.stem(it.component))
		name := fmt.tprintf("%s_%d_%d", base, top.x, top.y)
		for k := 2; (name in names); k += 1 {
			name = fmt.tprintf("%s_%d_%d_%d", base, top.x, top.y, k)
		}
		n.name = strings.clone(name, n.allocator)
		names[n.name] = true
		append(&out, n)
	}
	ProcessNodeQueues(m, gc)
	Node_SetGlobalPositions(m, top_node)
	if area == {} do TileMapNode_Changed(tm) // (a chunk's: its tiles' drawing is unchanged)
	return out[:], err
}

// --- Lua -----------------------------------------------------------------------------
// map:tilemap_component_at(x, y) -> node | nil          (cells, 0-based)
// map:tilemap_set_component(x, y, "components/Coin.component.json") -> node | nil
// map:tilemap_clear_component(x, y) -> bool
// map:tilemap_get_tile(x, y) -> tile | -1      map:tilemap_set_tile(x, y, tile) -> bool  (#220)
// map:tilemap_cell_at(wx, wy) -> x, y          map:tilemap_cell_position(x, y) -> wx, wy (centre)
// map:tilemap_neighbors(x, y) -> {{x, y}, ...}  (the cells sharing a side: 4, hex 6 - #278)
// map:tilemap_cell_outline(x, y) -> {{wx, wy}, ...}  (its corners in the world: 4, hex 6)

@(private = "file")
lua_tilemap_arg :: proc(L: ^lua.State) -> ^TileMapNode {
	n, ok := to_node_userdata(L, 1)
	if !ok || n.typeId != TileMapNode do return nil
	return cast(^TileMapNode)n
}

@(private = "file")
lua_cell :: proc(L: ^lua.State) -> [2]int {
	return {int(lua.tointeger(L, 2)), int(lua.tointeger(L, 3))}
}

@(private = "file")
lua_tilemap_component_at :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	tm := lua_tilemap_arg(L)
	push_node_userdata(L, TileMapNode_ComponentAt(tm, lua_cell(L)) if tm != nil else nil)
	return 1
}

@(private = "file")
lua_tilemap_set_component :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	tm := lua_tilemap_arg(L)
	if tm == nil || lua.type(L, 4) != .STRING {lua.pushnil(L); return 1}
	push_node_userdata(L, TileMapNode_PlaceComponent(tm, lua_cell(L), string(lua.tostring(L, 4))))
	return 1
}

@(private = "file")
lua_tilemap_clear_component :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	tm := lua_tilemap_arg(L)
	lua.pushboolean(L, b32(tm != nil && TileMapNode_RemoveComponentAt(tm, lua_cell(L))))
	return 1
}

@(private = "file")
lua_tilemap_get_tile :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	tm := lua_tilemap_arg(L)
	cell := lua_cell(L)
	lua.pushinteger(L, lua.Integer(TileMapNode_Get(tm, cell.x, cell.y) if tm != nil else -1))
	return 1
}

// (-1 / nil erases; a solid map's colliders follow at the end of the frame.)
@(private = "file")
lua_tilemap_set_tile :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	tm := lua_tilemap_arg(L)
	changed := false
	if tm != nil {
		cell := lua_cell(L)
		tile := i32(lua.tointeger(L, 4)) if !lua.isnoneornil(L, 4) else -1
		changed = TileMapNode_Set(tm, cell.x, cell.y, max(tile, -1))
		if changed do tm.collidersDirty = true
	}
	lua.pushboolean(L, b32(changed))
	return 1
}

@(private = "file")
lua_tilemap_cell_at :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	tm := lua_tilemap_arg(L)
	if tm == nil {lua.pushnil(L); lua.pushnil(L); return 2}
	x, y := arg_xy(L, 2)
	cell := TileMapNode_CellAt(tm, {x, y})
	lua.pushinteger(L, lua.Integer(cell.x))
	lua.pushinteger(L, lua.Integer(cell.y))
	return 2
}

@(private = "file")
lua_tilemap_cell_position :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	tm := lua_tilemap_arg(L)
	if tm == nil {lua.pushnil(L); lua.pushnil(L); return 2}
	cell := lua_cell(L)
	p := TileMapNode_CellCenter(tm, cell)
	lua.pushnumber(L, lua.Number(p.x))
	lua.pushnumber(L, lua.Number(p.y))
	return 2
}

@(private = "file")
lua_tilemap_neighbors :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	tm := lua_tilemap_arg(L)
	lua.createtable(L, 6, 0)
	if tm == nil do return 1
	nb, n := TileMapNode_Neighbors(tm, lua_cell(L))
	for q, i in nb[:n] {
		lua.createtable(L, 2, 0)
		lua.pushinteger(L, lua.Integer(q.x))
		lua.rawseti(L, -2, 1)
		lua.pushinteger(L, lua.Integer(q.y))
		lua.rawseti(L, -2, 2)
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

@(private = "file")
lua_tilemap_cell_outline :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	tm := lua_tilemap_arg(L)
	lua.createtable(L, 6, 0)
	if tm == nil do return 1
	pts, n := TileMapNode_CellOutline(tm, lua_cell(L))
	for p, i in pts[:n] {
		w := TileMapNode_LocalToWorld(tm, p)
		lua.createtable(L, 2, 0)
		lua.pushnumber(L, lua.Number(w.x))
		lua.rawseti(L, -2, 1)
		lua.pushnumber(L, lua.Number(w.y))
		lua.rawseti(L, -2, 2)
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

// Script_RegisterTileMapComponentBindings adds the tilemap_* component and tile
// methods to the node metatable (on the stack).
Script_RegisterTileMapComponentBindings :: proc(L: ^lua.State) {
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "tilemap_component_at", lua_tilemap_component_at)
	reg(L, "tilemap_set_component", lua_tilemap_set_component)
	reg(L, "tilemap_clear_component", lua_tilemap_clear_component)
	reg(L, "tilemap_get_tile", lua_tilemap_get_tile)
	reg(L, "tilemap_set_tile", lua_tilemap_set_tile)
	reg(L, "tilemap_cell_at", lua_tilemap_cell_at)
	reg(L, "tilemap_cell_position", lua_tilemap_cell_position)
	reg(L, "tilemap_neighbors", lua_tilemap_neighbors)
	reg(L, "tilemap_cell_outline", lua_tilemap_cell_outline)
}
