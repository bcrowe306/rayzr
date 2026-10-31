package engine

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:strings"

// ============================================================================
// Terrain sets (#171): auto-tiling. A terrain is a set of a tileset's tiles
// for each way its neighbours can be the same terrain - a cell takes the
// tile of its pattern, so painting (or generating) "grass" draws the
// grass's edges, corners and middle by itself.
//
//   edges  16 patterns: which of the 4 sides (N, E, S, W) are the terrain
//   blob   47 patterns: the 8 neighbours, a corner counting only when both
//          sides next to it are the terrain (the common "47-tile blob")
//   hex    64 patterns: which of a hex cell's 6 sides are the terrain
//
// The directions are the grid's (Grid_Compass): on isometric and staggered
// maps north is the diamond's upper-right side, east its lower-right.
//
// A pattern may have several tiles (variants: one picked per cell by a
// hash); a pattern without tiles falls back to the same one without its
// corners, then to the full tile (every side), then to any tile.
//
// A tileset's terrains are kept next to its image: textures/Tiles.png ->
// textures/Tiles.tileset.json:
//
//   {"terrains": [{"name": "Grass", "kind": "blob",
//                  "tiles": [[mask, tile], [mask, tile], ...]}]}
//
// Masks: edges N 1, E 2, S 4, W 8; blob N 1, NE 2, E 4, SE 8, S 16, SW 32,
// W 64, NW 128 (corners without both sides cleared); hex: the sides
// clockwise, 1 2 4 8 16 32 - Hex Pointy from E (E, SE, SW, W, NW, NE), Hex
// Flat from N (N, NE, SE, S, SW, NW).
// ============================================================================

Terrain_Kind :: enum {
	Blob,  // 47 patterns, 8 neighbours
	Edges, // 16 patterns, 4 sides
	Hex,   // 64 patterns, a hex cell's 6 sides
}

TERRAIN_KIND_NAMES := [Terrain_Kind]string{.Blob = "blob", .Edges = "edges", .Hex = "hex"}

Tile_Terrain :: struct {
	name:  string,
	kind:  Terrain_Kind,
	tiles: [256][dynamic]i32, // by mask (edges: 0..15)
}

// A tileset's terrains (Terrains_Parse / Terrains_Load).
Tile_Terrains :: struct {
	terrains:   [dynamic]Tile_Terrain,
	animations: [dynamic]Tile_Anim, // animated tiles (tile_anims.odin)
	allocator:  runtime.Allocator,
}

// The blob masks' bits.
TERRAIN_N :: u8(1)
TERRAIN_NE :: u8(2)
TERRAIN_E :: u8(4)
TERRAIN_SE :: u8(8)
TERRAIN_S :: u8(16)
TERRAIN_SW :: u8(32)
TERRAIN_W :: u8(64)
TERRAIN_NW :: u8(128)

// Terrain_SidecarPath: where a tileset image's terrains are kept.
Terrain_SidecarPath :: proc(image: string, allocator := context.temp_allocator) -> string {
	if image == "" do return ""
	dot := strings.last_index_byte(image, '.')
	slash := strings.last_index_any(image, "/\\")
	stem := image[:dot] if dot > slash else image
	return strings.concatenate({stem, ".tileset.json"}, allocator)
}

// Terrain_Reduce: a blob mask with the corners whose two sides aren't both
// set cleared (the 47 that matter).
Terrain_Reduce :: proc(m: u8) -> u8 {
	r := m
	if r & TERRAIN_N == 0 || r & TERRAIN_E == 0 do r &= ~TERRAIN_NE
	if r & TERRAIN_E == 0 || r & TERRAIN_S == 0 do r &= ~TERRAIN_SE
	if r & TERRAIN_S == 0 || r & TERRAIN_W == 0 do r &= ~TERRAIN_SW
	if r & TERRAIN_W == 0 || r & TERRAIN_N == 0 do r &= ~TERRAIN_NW
	return r
}

// Terrain_Patterns: a kind's patterns, in a fixed order (the editor's).
Terrain_Patterns :: proc(kind: Terrain_Kind, allocator := context.temp_allocator) -> []u8 {
	out := make([dynamic]u8, allocator)
	switch kind {
	case .Edges:
		for m in 0 ..< 16 do append(&out, u8(m))
	case .Blob:
		for m in 0 ..< 256 do if Terrain_Reduce(u8(m)) == u8(m) do append(&out, u8(m))
	case .Hex:
		for m in 0 ..< 64 do append(&out, u8(m))
	}
	return out[:]
}

// Terrain_Mask: the pattern of a cell from its 3x3 neighbourhood (nb[y][x],
// nb[1][1] the cell): which neighbours are the terrain.
Terrain_Mask :: proc(kind: Terrain_Kind, nb: [3][3]bool) -> u8 {
	switch kind {
	case .Edges:
		m: u8
		if nb[0][1] do m |= 1
		if nb[1][2] do m |= 2
		if nb[2][1] do m |= 4
		if nb[1][0] do m |= 8
		return m
	case .Blob:
		m: u8
		if nb[0][1] do m |= TERRAIN_N
		if nb[0][2] do m |= TERRAIN_NE
		if nb[1][2] do m |= TERRAIN_E
		if nb[2][2] do m |= TERRAIN_SE
		if nb[2][1] do m |= TERRAIN_S
		if nb[2][0] do m |= TERRAIN_SW
		if nb[1][0] do m |= TERRAIN_W
		if nb[0][0] do m |= TERRAIN_NW
		return Terrain_Reduce(m)
	case .Hex:
		// (Off a hex grid it sees the 4 sides: E, SW, W, NE - meant for hex maps.)
		m: u8
		if nb[1][2] do m |= 1
		if nb[2][1] do m |= 4
		if nb[1][0] do m |= 8
		if nb[0][1] do m |= 32
		return m
	}
	return 0
}

// Terrain_MaskAt: a cell's pattern on a grid, `member(cell, data)` saying
// which cells are the terrain.
Terrain_MaskAt :: proc(kind: Terrain_Kind, layout: TileMap_Layout, stagger: TileMap_Stagger, cell: [2]int, data: rawptr, member: proc(cell: [2]int, data: rawptr) -> bool) -> u8 {
	if kind == .Hex && (layout == .HexPointy || layout == .HexFlat) {
		m: u8
		for q, i in Grid_HexSides(layout, stagger, cell) do if member(q, data) do m |= 1 << uint(i)
		return m
	}
	cells := Grid_Compass(layout, stagger, cell)
	nb: [3][3]bool
	for dy in 0 ..< 3 do for dx in 0 ..< 3 do nb[dy][dx] = member(cells[dy][dx], data)
	return Terrain_Mask(kind, nb)
}

// The full pattern (every neighbour the terrain).
Terrain_Full :: proc(kind: Terrain_Kind) -> u8 {
	switch kind {
	case .Edges: return 15
	case .Hex: return 63
	case .Blob: return 255
	}
	return 255
}

// Terrain_Tile: the tile for a pattern (a variant picked by the cell and
// the seed); -1 when the terrain has no tiles at all.
Terrain_Tile :: proc(t: ^Tile_Terrain, mask: u8, x, y: int, seed: u64 = 0) -> i32 {
	pick :: proc(list: [dynamic]i32, x, y: int, seed: u64) -> i32 {
		if len(list) == 1 do return list[0]
		return list[int(gen_hash01(x, y, seed ~ 0x7e44a1) * f32(len(list))) % len(list)]
	}
	if len(t.tiles[mask]) > 0 do return pick(t.tiles[mask], x, y, seed)
	if t.kind == .Blob {
		sides := mask & (TERRAIN_N | TERRAIN_E | TERRAIN_S | TERRAIN_W)
		if len(t.tiles[sides]) > 0 do return pick(t.tiles[sides], x, y, seed)
	}
	full := Terrain_Full(t.kind)
	if len(t.tiles[full]) > 0 do return pick(t.tiles[full], x, y, seed)
	for list in t.tiles do if len(list) > 0 do return pick(list, x, y, seed)
	return -1
}

// Terrain_Has: the tile is one of the terrain's.
Terrain_Has :: proc(t: ^Tile_Terrain, tile: i32) -> bool {
	if tile < 0 do return false
	for list in t.tiles do for x in list do if x == tile do return true
	return false
}

Terrains_Find :: proc(ts: ^Tile_Terrains, name: string) -> (^Tile_Terrain, int) {
	if ts == nil do return nil, -1
	for &t, i in ts.terrains do if t.name == name do return &t, i
	return nil, -1
}

// --- the file -------------------------------------------------------------------------

Terrains_Parse :: proc(data: []u8, allocator := context.allocator) -> (ts: Tile_Terrains, err: string) {
	ts.allocator = allocator
	ts.terrains = make([dynamic]Tile_Terrain, allocator)
	ts.animations = make([dynamic]Tile_Anim, allocator)
	if len(data) == 0 do return
	value, perr := json.parse(data, allocator = context.temp_allocator)
	if perr != .None do return ts, fmt.tprintf("not valid JSON (%v)", perr)
	root, _ := value.(json.Object)
	list, _ := root["terrains"].(json.Array)
	for v in list {
		obj, ok := v.(json.Object)
		if !ok do continue
		name, _ := obj["name"].(json.String)
		t := Terrains_Add(&ts, string(name))
		if kind, kok := obj["kind"].(json.String); kok {
			for name, k in TERRAIN_KIND_NAMES do if string(kind) == name do t.kind = k
		}
		if pairs, pok := obj["tiles"].(json.Array); pok do for pv in pairs {
			pair, isArr := pv.(json.Array)
			if !isArr || len(pair) < 2 do continue
			m, _ := json_number(pair[0])
			tile, _ := json_number(pair[1])
			if int(m) < 0 || int(m) > 255 do continue
			append(&t.tiles[int(m)], i32(tile))
		}
	}
	anims, _ := root["animations"].(json.Array)
	for v in anims {
		obj, ok := v.(json.Object)
		if !ok do continue
		a := Tile_Anim{make([dynamic]i32, allocator), make([dynamic]f32, allocator), false}
		a.desync, _ = obj["desync"].(json.Boolean)
		if frames, fok := obj["frames"].(json.Array); fok do for fv in frames {
			pair, isArr := fv.(json.Array)
			if !isArr || len(pair) < 1 do continue
			tile, _ := json_number(pair[0])
			ms: f32 = 100
			if len(pair) > 1 do ms, _ = json_number(pair[1])
			append(&a.frames, i32(tile))
			append(&a.durations, max(ms, 1) / 1000)
		}
		append(&ts.animations, a)
	}
	return
}

// Terrains_AnimationOf: the animation starting on a tile (-1: none).
Terrains_AnimationOf :: proc(ts: ^Tile_Terrains, tile: i32) -> int {
	if ts == nil do return -1
	for &a, i in ts.animations do if len(a.frames) > 0 && a.frames[0] == tile do return i
	return -1
}

Terrains_Serialize :: proc(ts: ^Tile_Terrains, allocator := context.allocator) -> string {
	w: Json_Writer
	w.sb = strings.builder_make(allocator)
	strings.write_string(&w.sb, "{\"terrains\": [")
	for &t, i in ts.terrains {
		strings.write_string(&w.sb, "," if i > 0 else "")
		strings.write_string(&w.sb, "\n  {\"name\": ")
		Json_String(&w, t.name)
		strings.write_string(&w.sb, ", \"kind\": ")
		Json_String(&w, TERRAIN_KIND_NAMES[t.kind])
		strings.write_string(&w.sb, ", \"tiles\": [")
		k := 0
		for list, m in t.tiles do for tile in list {
			fmt.sbprintf(&w.sb, "%s[%d, %d]", ", " if k > 0 else "", m, tile)
			k += 1
		}
		strings.write_string(&w.sb, "]}")
	}
	strings.write_string(&w.sb, "\n]")
	if len(ts.animations) > 0 {
		strings.write_string(&w.sb, ",\n\"animations\": [")
		for &a, i in ts.animations {
			strings.write_string(&w.sb, "," if i > 0 else "")
			strings.write_string(&w.sb, "\n  {\"frames\": [")
			for f, k in a.frames do fmt.sbprintf(&w.sb, "%s[%d, %d]", ", " if k > 0 else "", f, int(a.durations[k] * 1000 + 0.5))
			fmt.sbprintf(&w.sb, "], \"desync\": %t}}", a.desync)
		}
		strings.write_string(&w.sb, "\n]")
	}
	strings.write_string(&w.sb, "}\n")
	return strings.to_string(w.sb)
}

// Terrains_Add: a new terrain (blob, no tiles yet).
Terrains_Add :: proc(ts: ^Tile_Terrains, name: string) -> ^Tile_Terrain {
	append(&ts.terrains, Tile_Terrain{name = strings.clone(name, ts.allocator)})
	t := &ts.terrains[len(ts.terrains) - 1]
	for &list in t.tiles do list = make([dynamic]i32, ts.allocator)
	return t
}

Terrains_Remove :: proc(ts: ^Tile_Terrains, index: int) {
	if index < 0 || index >= len(ts.terrains) do return
	terrain_free(ts, &ts.terrains[index])
	ordered_remove(&ts.terrains, index)
}

Terrain_Rename :: proc(ts: ^Tile_Terrains, t: ^Tile_Terrain, name: string) {
	delete(t.name, ts.allocator)
	t.name = strings.clone(name, ts.allocator)
}

@(private = "file")
terrain_free :: proc(ts: ^Tile_Terrains, t: ^Tile_Terrain) {
	delete(t.name, ts.allocator)
	for list in t.tiles do delete(list)
}

Terrains_Destroy :: proc(ts: ^Tile_Terrains) {
	for &t in ts.terrains do terrain_free(ts, &t)
	delete(ts.terrains)
	for &a in ts.animations {
		delete(a.frames)
		delete(a.durations)
	}
	delete(ts.animations)
	ts^ = {}
}

// Terrains_Load: a tileset image's terrains from the project (none: an
// empty set).
Terrains_Load :: proc(ctx: ^GameContext, image: string, allocator := context.allocator) -> (Tile_Terrains, string) {
	path := Terrain_SidecarPath(image)
	if ctx == nil || ctx.game == nil || path == "" do return Terrains_Parse(nil, allocator)
	text, ok := AssetManager_ReadFileString(&ctx.game.assetManager, path, context.temp_allocator)
	if !ok do return Terrains_Parse(nil, allocator)
	return Terrains_Parse(transmute([]u8)text, allocator)
}

// --- on a TileMap -------------------------------------------------------------------------

// TileMapNode_PaintTerrain makes a cell the terrain (on) or empties it
// (off), then gives it and the cells around it that are the terrain the
// tiles of their patterns. Cells outside what's painted aren't the terrain.
TileMapNode_PaintTerrain :: proc(tm: ^TileMapNode, t: ^Tile_Terrain, x, y: int, on: bool, seed: u64 = 0) {
	if t == nil do return
	if on {
		if !Terrain_Has(t, TileMapNode_Get(tm, x, y)) do TileMapNode_Set(tm, x, y, Terrain_Tile(t, Terrain_Full(t.kind), x, y, seed))
	} else {
		TileMapNode_Set(tm, x, y, -1)
	}
	TileMapNode_RetileTerrain(tm, t, {x - 1, y - 2}, {x + 2, y + 3}, seed) // (staggered: two rows away)
}

// TileMapNode_RetileTerrain: every cell of the terrain in lo..hi (hi
// exclusive) takes its pattern's tile.
TileMapNode_RetileTerrain :: proc(tm: ^TileMapNode, t: ^Tile_Terrain, lo, hi: [2]int, seed: u64 = 0) {
	if t == nil do return
	members := make(map[i32]bool, allocator = context.temp_allocator)
	for list in t.tiles do for tile in list do members[tile] = true
	Ctx :: struct {tm: ^TileMapNode, members: ^map[i32]bool}
	c := Ctx{tm, &members}
	member :: proc(cell: [2]int, data: rawptr) -> bool {
		c := cast(^Ctx)data
		return TileMapNode_Get(c.tm, cell.x, cell.y) in c.members
	}
	for y in lo.y ..< hi.y do for x in lo.x ..< hi.x {
		if TileMapNode_Get(tm, x, y) not_in members do continue
		tile := Terrain_Tile(t, Terrain_MaskAt(t.kind, tm.layout, tm.stagger, {x, y}, &c, member), x, y, seed)
		if tile >= 0 do TileMapNode_Set(tm, x, y, tile)
	}
	TileMapNode_Changed(tm)
}

// TileMapNode_FillTerrain flood-fills the region of equal tiles around
// (x, y) with the terrain (as TileMapNode_Fill), then tiles it and its rim.
TileMapNode_FillTerrain :: proc(tm: ^TileMapNode, t: ^Tile_Terrain, x, y: int, seed: u64 = 0) -> int {
	if t == nil do return 0
	full := Terrain_Tile(t, Terrain_Full(t.kind), x, y, seed)
	if full < 0 do return 0
	before := TileMapNode_Get(tm, x, y)
	if Terrain_Has(t, before) do return 0
	n := TileMapNode_Fill(tm, x, y, full)
	if n == 0 do return 0
	lo, hi := TileMapNode_Extent(tm)
	TileMapNode_RetileTerrain(tm, t, lo - 1, hi + 1, seed)
	return n
}
