package engine

import "core:c"
import "core:strings"
import lua "lua54"

// ============================================================================
// Tiles changed while the game runs (the guide: engine/docs/tilemaps.md).
//
// A script's edits (tilemap_set_tile, tilemap_set_terrain, tilemap_damage)
// go through TileMapNode_EditTile:
//   - Retile on Edit: the terrains the old or new tile belongs to re-pick
//     the edited cell's neighbours (their edges and corners follow);
//   - a Solid map's colliders follow at the end of the frame (a chunked
//     level's: just the chunks edited);
//   - "tile_changed" {x, y, old, new} for every cell that changed (the
//     neighbours too); block writes (a generator's level, chunks coming in
//     and out) send none - the generator has its own events;
//   - a chunked level remembers the edit (Tile_Chunk_Edits) and puts it
//     back when the chunk comes in again.
//
// Tile data (tile_data.odin) comes from the tileset's sidecar, loaded with
// the tileset. Cells keep values of their own (TileMapNode_SetCellData),
// dropped when their tile changes. tilemap_damage lowers a cell's
// "health" (its own, else the tile's): "tile_damaged", and at 0 the tile
// goes ("tile_destroyed").
//
// "tile_hit" {x, y, tile, other, point}: a body touched the map's
// colliders (the first touch of that body: Box2D reports a pair once while
// they stay in contact) - the tile it hit.
// ============================================================================

// A chunked generator's edits to one map: cells set by scripts, and the
// components placed ("") or cleared ("") there.
Tile_Chunk_Edits :: struct {
	tiles:      map[[2]int]i32,
	components: map[[2]int]string, // "" = cleared
}

TileMapNode_InitRuntime :: proc(tm: ^TileMapNode) {
	InitializeSubject(&tm.onTileChanged, "tile_changed", tm)
	InitializeSubject(&tm.onTileDamaged, "tile_damaged", tm)
	InitializeSubject(&tm.onTileDestroyed, "tile_destroyed", tm)
	InitializeSubject(&tm.onTileHit, "tile_hit", tm)
}

TileMapNode_FreeRuntime :: proc(tm: ^TileMapNode) {
	DestroySubject(&tm.onTileChanged)
	DestroySubject(&tm.onTileDamaged)
	DestroySubject(&tm.onTileDestroyed)
	DestroySubject(&tm.onTileHit)
	if tm.sidecar != nil {
		Terrains_Destroy(tm.sidecar)
		free(tm.sidecar, Engine_HeapAllocator())
		tm.sidecar = nil
	}
	for k in tm.cellData do tilemap_forget_cell(tm, {int(k.x), int(k.y)})
	delete(tm.cellData)
	tm.cellData = nil
	delete(tm.chunkDirty)
	tm.chunkDirty = nil
	tm.chunkEdits = nil
}

// TileMapNode_LoadSidecar: the tileset's terrains and tile data (kept for
// the map's scripts; an empty set when it has none).
TileMapNode_LoadSidecar :: proc(tm: ^TileMapNode, gc: ^GameContext, image: string) {
	if tm.sidecar != nil {
		Terrains_Destroy(tm.sidecar)
		free(tm.sidecar, Engine_HeapAllocator())
		tm.sidecar = nil
	}
	if image == "" do return
	a := Engine_HeapAllocator()
	ts := new(Tile_Terrains, a)
	ts^, _ = Terrains_Load(gc, image, a)
	tm.sidecar = ts
}

// tilemap_forget_cell drops a cell's own values (its tile changed).
tilemap_forget_cell :: proc(tm: ^TileMapNode, cell: [2]int) {
	k := [2]i32{i32(cell.x), i32(cell.y)}
	vals, ok := tm.cellData[k]
	if !ok do return
	a := Engine_HeapAllocator()
	for key, v in vals {
		delete(key, a)
		if s, isStr := v.(string); isStr do delete(s, a)
	}
	delete(vals)
	delete_key(&tm.cellData, k)
}

// --- Editing --------------------------------------------------------------------------

// TileMapNode_EditTile: a script's edit of one cell (-1 erases), with its
// neighbours re-picked (Retile on Edit), events and memory. True if it changed.
TileMapNode_EditTile :: proc(tm: ^TileMapNode, cell: [2]int, tile: i32) -> bool {
	old := TileMapNode_Get(tm, cell.x, cell.y)
	tile := max(tile, -1)
	if old == tile do return false
	TileMapNode_Set(tm, cell.x, cell.y, tile)
	tilemap_edited(tm, cell, old, tile)
	if tm.retileOnEdit && tm.sidecar != nil {
		for &t in tm.sidecar.terrains {
			if Terrain_Has(&t, old) || Terrain_Has(&t, tile) do tilemap_retile(tm, &t, cell)
		}
	}
	return true
}

// TileMapNode_SetTerrain: makes a cell the terrain (name "": empties it)
// and re-picks it and its neighbours. False: no such terrain / no change.
TileMapNode_SetTerrain :: proc(tm: ^TileMapNode, cell: [2]int, name: string) -> bool {
	if tm.sidecar == nil do return false
	if name == "" {
		old := TileMapNode_Get(tm, cell.x, cell.y)
		if old < 0 do return false
		TileMapNode_Set(tm, cell.x, cell.y, -1)
		tilemap_edited(tm, cell, old, -1)
		for &t in tm.sidecar.terrains do if Terrain_Has(&t, old) do tilemap_retile(tm, &t, cell)
		return true
	}
	t, _ := Terrains_Find(tm.sidecar, name)
	if t == nil do return false
	old := TileMapNode_Get(tm, cell.x, cell.y)
	if !Terrain_Has(t, old) {
		full := Terrain_Tile(t, Terrain_Full(t.kind), cell.x, cell.y)
		if full < 0 do return false
		TileMapNode_Set(tm, cell.x, cell.y, full)
		tilemap_edited(tm, cell, old, full)
	}
	tilemap_retile(tm, t, cell)
	return true
}

// tilemap_retile re-picks a terrain's cells around an edited one (as
// TileMapNode_RetileTerrain), each change an edit of its own.
@(private = "file")
tilemap_retile :: proc(tm: ^TileMapNode, t: ^Tile_Terrain, cell: [2]int) {
	members := make(map[i32]bool, allocator = context.temp_allocator)
	for list in t.tiles do for tile in list do members[tile] = true
	Ctx :: struct {tm: ^TileMapNode, members: ^map[i32]bool}
	cx := Ctx{tm, &members}
	member :: proc(cell: [2]int, data: rawptr) -> bool {
		c := cast(^Ctx)data
		return TileMapNode_Get(c.tm, cell.x, cell.y) in c.members
	}
	lo, hi := cell - {1, 2}, cell + {2, 3} // (staggered: two rows away)
	for y in lo.y ..< hi.y do for x in lo.x ..< hi.x {
		cur := TileMapNode_Get(tm, x, y)
		if cur not_in members do continue
		tile := Terrain_Tile(t, Terrain_MaskAt(t.kind, tm.layout, tm.stagger, {x, y}, &cx, member), x, y)
		if tile >= 0 && tile != cur {
			TileMapNode_Set(tm, x, y, tile)
			tilemap_edited(tm, {x, y}, cur, tile)
		}
	}
}

// tilemap_edited: after a cell changed by a script - colliders, memory, the event.
@(private = "file")
tilemap_edited :: proc(tm: ^TileMapNode, cell: [2]int, old, tile: i32) {
	if tm.unbounded do append(&tm.chunkDirty, cell) // (its chunk's colliders: the generator)
	else do tm.collidersDirty = true
	if e := tm.chunkEdits; e != nil {
		if e.tiles == nil do e.tiles = make(map[[2]int]i32, allocator = Engine_HeapAllocator())
		e.tiles[cell] = tile
	}
	if tile_event_wanted(tm, &tm.onTileChanged) {
		L, ref := tile_event_begin(tm)
		if L != nil {
			tile_field_int(L, "x", cell.x)
			tile_field_int(L, "y", cell.y)
			tile_field_int(L, "old", int(old))
			tile_field_int(L, "new", int(tile))
			tile_event_end(tm, &tm.onTileChanged, L, ref)
		}
	}
}

// TileMapNode_RecordComponentEdit: a script placed (path) or cleared ("")
// a component - remembered by a chunked level.
TileMapNode_RecordComponentEdit :: proc(tm: ^TileMapNode, cell: [2]int, path: string) {
	e := tm.chunkEdits
	if e == nil do return
	a := Engine_HeapAllocator()
	if e.components == nil do e.components = make(map[[2]int]string, allocator = a)
	if old, ok := e.components[cell]; ok do delete(old, a)
	e.components[cell] = strings.clone(path, a)
}

// --- Data -----------------------------------------------------------------------------

// TileMapNode_CellData: a cell's value of a field - its own, else its
// tile's (else the field's default). ok = false: no such field / value.
TileMapNode_CellData :: proc(tm: ^TileMapNode, cell: [2]int, name: string) -> (Tile_Value, bool) {
	if vals, has := tm.cellData[{i32(cell.x), i32(cell.y)}]; has {
		if v, set := vals[name]; set do return v, true
	}
	tile := TileMapNode_Get(tm, cell.x, cell.y)
	if tile < 0 || tm.sidecar == nil do return nil, false
	return TileData_Get(tm.sidecar, tile, name)
}

// TileMapNode_SetCellData: a cell's own value (until its tile changes).
TileMapNode_SetCellData :: proc(tm: ^TileMapNode, cell: [2]int, name: string, v: Tile_Value) {
	a := Engine_HeapAllocator()
	if tm.cellData == nil do tm.cellData = make(map[[2]i32]map[string]Tile_Value, allocator = a)
	k := [2]i32{i32(cell.x), i32(cell.y)}
	vals, has := tm.cellData[k]
	if !has do vals = make(map[string]Tile_Value, allocator = a)
	if old, set := vals[name]; set {
		if s, ok := old.(string); ok do delete(s, a)
		vals[name] = tile_value_clone(v, a)
	} else {
		vals[strings.clone(name, a)] = tile_value_clone(v, a)
	}
	tm.cellData[k] = vals
}

// TileMapNode_Damage lowers a cell's health ("health": its own, else its
// tile's); at 0 or less the tile goes. Returns its health left and whether
// it was destroyed; ok = false when the cell is empty or has no health.
TileMapNode_Damage :: proc(tm: ^TileMapNode, cell: [2]int, amount: f64) -> (health: f64, destroyed, ok: bool) {
	tile := TileMapNode_Get(tm, cell.x, cell.y)
	if tile < 0 do return 0, false, false
	v, has := TileMapNode_CellData(tm, cell, "health")
	h, isNum := v.(f64)
	if !has || !isNum do return 0, false, false
	health = h - amount
	TileMapNode_SetCellData(tm, cell, "health", health)
	if tile_event_wanted(tm, &tm.onTileDamaged) {
		L, ref := tile_event_begin(tm)
		if L != nil {
			tile_field_int(L, "x", cell.x)
			tile_field_int(L, "y", cell.y)
			tile_field_int(L, "tile", int(tile))
			tile_field_num(L, "amount", amount)
			tile_field_num(L, "health", health)
			tile_event_end(tm, &tm.onTileDamaged, L, ref)
		}
	}
	if health <= 0 {
		TileMapNode_EditTile(tm, cell, -1)
		destroyed = true
		if tile_event_wanted(tm, &tm.onTileDestroyed) {
			L, ref := tile_event_begin(tm)
			if L != nil {
				tile_field_int(L, "x", cell.x)
				tile_field_int(L, "y", cell.y)
				tile_field_int(L, "tile", int(tile))
				tile_event_end(tm, &tm.onTileDestroyed, L, ref)
			}
		}
	}
	return health, destroyed, true
}

// --- Tile pictures ----------------------------------------------------------------------

// TileMapNode_TileImageRect: where a tile is in the tileset image (px).
TileMapNode_TileImageRect :: proc(tm: ^TileMapNode, tile: i32) -> (r: [4]f32, ok: bool) {
	cols := TileMapNode_Columns(tm)
	if cols <= 0 || tile < 0 || int(tile) >= TileMapNode_TileCount(tm) do return
	tw, th := f32(tm.tileSize.x), f32(tm.tileSize.y)
	return {f32(int(tile) % cols) * tw, f32(int(tile) / cols) * th, tw, th}, true
}

// AtlasSprite_ShowTile: an Atlas Sprite shows a map's tile (its tileset
// image, the tile's rectangle, the tile's size): a tile picked up.
AtlasSprite_ShowTile :: proc(an: ^AtlasSpriteNode, tm: ^TileMapNode, tile: i32) -> bool {
	r, ok := TileMapNode_TileImageRect(tm, tile)
	if !ok do return false
	if an.filePath != tm.tilesetPath && tm.tileset != nil {
		// (The map's own tileset texture, shared.)
		if rm := Node_ResourceManager(tm); rm != nil {
			if tex, tok := rm.loadTexture(rm, Project_ResolveAssetPath(tm.gameContext, tm.tilesetPath)); tok do AtlasSpriteNode_SetTexture(an, tex)
		}
		an.filePath = strings.clone(tm.tilesetPath, an.allocator)
	}
	an.region = {r[0], r[1], r[2], r[3]}
	an.size = {r[2], r[3]}
	return true
}

// --- Tile hits -----------------------------------------------------------------------

// TileMapNode_WatchHits: the map's collider body reports the tiles bodies
// hit ("tile_hit").
TileMapNode_WatchHits :: proc(tm: ^TileMapNode, body: ^StaticBodyNode) {
	if body == nil do return
	body.onCollisionStarted->subscribe(tilemap_on_hit, tm)
}

@(private = "file")
tilemap_on_hit :: proc(source: rawptr, value: EventValue, ctx: ^GameContext, user: rawptr) {
	tm := cast(^TileMapNode)user
	other, isNode := value.(^Node)
	if tm == nil || !Node_IsAlive(tm) || !isNode do return
	ct := collisionContact // (the map's view: its normal points into the tile)
	if !ct.valid do return
	cs := TileMapNode_CellSize(tm)
	inside := ct.point + ct.normal * (min(cs.x, cs.y) * 0.25)
	cell := TileMapNode_CellAt(tm, inside)
	tile := TileMapNode_Get(tm, cell.x, cell.y)
	if tile < 0 {
		// (Right on an edge: the cell on the other side.)
		cell = TileMapNode_CellAt(tm, ct.point - ct.normal * (min(cs.x, cs.y) * 0.25))
		tile = TileMapNode_Get(tm, cell.x, cell.y)
	}
	if !tile_event_wanted(tm, &tm.onTileHit) do return
	L, ref := tile_event_begin(tm)
	if L == nil do return
	tile_field_int(L, "x", cell.x)
	tile_field_int(L, "y", cell.y)
	tile_field_int(L, "tile", int(tile))
	push_node_userdata(L, other)
	lua.setfield(L, -2, "other")
	Lua_PushVec2(L, ct.point)
	lua.setfield(L, -2, "point")
	tile_event_end(tm, &tm.onTileHit, L, ref)
}

// TileMapNode_HitCell: the cell a contact touched on the map - from a
// body's own collision (its normal points away from the map: back into it).
TileMapNode_HitCell :: proc(tm: ^TileMapNode, point, normal: [2]f32) -> (cell: [2]int, tile: i32) {
	cs := TileMapNode_CellSize(tm)
	d := min(cs.x, cs.y) * 0.25
	cell = TileMapNode_CellAt(tm, point - normal * d)
	tile = TileMapNode_Get(tm, cell.x, cell.y)
	if tile < 0 {
		cell = TileMapNode_CellAt(tm, point + normal * d)
		tile = TileMapNode_Get(tm, cell.x, cell.y)
	}
	return
}

// --- Events with a table --------------------------------------------------------------

// tile_event_wanted: someone could hear it (a listener, a script, a connection).
@(private = "file")
tile_event_wanted :: proc(tm: ^TileMapNode, subj: ^EventSubject) -> bool {
	return true // (a table per single-cell change: cheap; block writes send none)
}

@(private = "file")
tile_event_begin :: proc(tm: ^TileMapNode) -> (^lua.State, c.int) {
	gc := tm.gameContext
	if gc == nil || gc.game == nil || gc.game.scriptManager.L == nil do return nil, 0
	L := gc.game.scriptManager.L
	lua.newtable(L)
	return L, 0
}

@(private = "file")
tile_event_end :: proc(tm: ^TileMapNode, subj: ^EventSubject, L: ^lua.State, _: c.int) {
	ref := lua.L_ref(L, lua.REGISTRYINDEX) // (pops the table)
	subj->notify(tm, Lua_Value_Ref(ref), tm.gameContext)
	lua.L_unref(L, lua.REGISTRYINDEX, ref)
}

@(private = "file")
tile_field_int :: proc(L: ^lua.State, k: cstring, v: int) {
	lua.pushinteger(L, lua.Integer(v))
	lua.setfield(L, -2, k)
}

@(private = "file")
tile_field_num :: proc(L: ^lua.State, k: cstring, v: f64) {
	lua.pushnumber(L, lua.Number(v))
	lua.setfield(L, -2, k)
}
