package engine

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:slice"
import "core:strings"

// ============================================================================
// Height layers (#171, stretch): a Height Output node turns a height map -
// any grid of 0..1 values (noise, a blur, a gradient...) - into stacked
// TileMaps. Its value is cut into `levels` heights (evenly, or at each
// level's own `min`), and level k is written into its own TileMap (`layer`,
// by name next to the main one; "": the main one): with fill `stack` a cell
// at level k fills levels 0..k (a plateau sits on the ground below), with
// `only` just level k.
//
// Each level names its tiles (one picked per cell) or a terrain of the
// output's tileset (#261): auto-tiled where the height drops below the level
// - a cell's neighbours count as the terrain when they are at that level or
// higher, so a level's edges are drawn where it ends, never against the
// ground above it. A level may also have a cliff face (top-down): tiles or a
// terrain for the cells just south of its edges - the grid's north
// neighbour at the level, the cell below it. A `solid` level's edges (and
// face) go into the walls TileMap (`walls`; make it Solid - hidden, if it
// shouldn't be seen) as `walls_tile`: cliff walls.
//
// Chunk-safe: every cell reads its neighbours within 1 (2 with a cliff
// terrain: a face cell's own neighbours) - its chunk apron (Gen_HeightReach).
// ============================================================================

GEN_HEIGHT_MAX :: 16

// Fill: which levels a cell fills.
GEN_HEIGHT_FILLS := []string{"stack", "only"}
// Where the levels start: evenly (k / levels), or each level's own `min`.
GEN_HEIGHT_THRESHOLDS := []string{"even", "custom"}

// One height of a Height Output: the TileMap it fills and what goes there.
Gen_Height_Level :: struct {
	min:           f32,          // custom thresholds: the lowest value at this level (level 0: unused)
	layer:         string,       // the TileMap it fills, by name ("": the main one; the graph's allocator)
	tiles:         [dynamic]i32, // one picked per cell (no terrain)
	terrain:       string,       // a terrain of the output's tileset instead of tiles (the graph's allocator)
	cliff:         [dynamic]i32, // the cliff face: tiles for the cells just south of its edges
	cliff_terrain: string,       // the face auto-tiled with a terrain instead (the graph's allocator)
	solid:         bool,         // its edges (and face) go into the walls map
}

// Gen_HeightCount: an output's number of levels (1-16).
Gen_HeightCount :: proc(n: ^Gen_Node) -> int {
	return clamp(int(Gen_Param(n, "levels")), 1, GEN_HEIGHT_MAX)
}

// Gen_HeightLevel: level k's settings (a level the node has none for: no
// tiles, the main map).
Gen_HeightLevel :: proc(n: ^Gen_Node, k: int) -> Gen_Height_Level {
	if k >= 0 && k < len(n.heights) do return n.heights[k]
	return {min = f32(k) / f32(Gen_HeightCount(n))}
}

// Gen_HeightThresholds: where each level starts (mins[0] unused): k /
// levels, or with custom thresholds each level's `min` - never below the
// level under it.
Gen_HeightThresholds :: proc(n: ^Gen_Node) -> (mins: [GEN_HEIGHT_MAX]f32) {
	count := Gen_HeightCount(n)
	custom := int(Gen_Param(n, "thresholds")) == 1
	for k in 1 ..< count {
		mins[k] = Gen_HeightLevel(n, k).min if custom else f32(k) / f32(count)
		if k > 1 do mins[k] = max(mins[k], mins[k - 1])
	}
	return
}

// Gen_HeightLevelsOf: each cell's level (0 .. levels - 1) for a grid: the
// highest whose threshold its value reaches.
Gen_HeightLevelsOf :: proc(n: ^Gen_Node, grid: Gen_Grid, allocator := context.allocator) -> []u8 {
	count := Gen_HeightCount(n)
	mins := Gen_HeightThresholds(n)
	lv := make([]u8, len(grid.v), allocator)
	#no_bounds_check for v, i in grid.v {
		l := 0
		for k in 1 ..< count {
			if v < mins[k] do break
			l = k
		}
		lv[i] = u8(l)
	}
	return lv
}

// Gen_HeightReach: the cells around a cell a height output reads - 1 (its
// edges, a face's north), 2 with a cliff terrain (a face cell's neighbours).
Gen_HeightReach :: proc(n: ^Gen_Node) -> int {
	for k in 1 ..< min(Gen_HeightCount(n), len(n.heights)) do if n.heights[k].cliff_terrain != "" do return 2
	return 1
}

// A height output's tiles: each level's (row-major, -1 empty) and the
// walls' (nil: no walls map, or no solid level).
Gen_Heights :: struct {
	levels: [][]i32,
	walls:  []i32,
}

// Gen_HeightsOf: a height output's tiles for its grid (already evaluated)
// and the evaluation's seed. `terrains`: its tileset's; a terrain it
// doesn't have leaves the level's cells empty. `origin`: the absolute cell
// of the grid's first (a chunk's window) - random picks are by absolute
// cell. Cells beyond the grid count as at every level for the edges (a
// plateau runs on past them) and as not raised for the faces.
Gen_HeightsOf :: proc(out: ^Gen_Node, grid: Gen_Grid, seed: u64, allocator := context.allocator, terrains: ^Tile_Terrains = nil, layout := TileMap_Layout.Square, stagger := TileMap_Stagger.Odd, origin := [2]int{}) -> (res: Gen_Heights) {
	count := Gen_HeightCount(out)
	w, h := grid.w, grid.h
	lv := Gen_HeightLevelsOf(out, grid, context.temp_allocator)
	stack := int(Gen_Param(out, "fill")) == 0
	res.levels = make([][]i32, count, allocator)
	wallTile := i32(Gen_Param(out, "walls_tile"))
	if out.layer != "" do for k in 1 ..< count do if Gen_HeightLevel(out, k).solid {
		res.walls = make([]i32, w * h, allocator)
		slice.fill(res.walls, -1)
		break
	}
	Ctx :: struct {
		lv:   []u8,
		face: []bool,
		w, h: int,
		k:    u8,
	}
	inside :: #force_inline proc(c: ^Ctx, q: [2]int) -> bool {return q.x >= 0 && q.y >= 0 && q.x < c.w && q.y < c.h}
	// At the level or higher (beyond the grid: yes).
	member :: proc(q: [2]int, data: rawptr) -> bool {
		c := cast(^Ctx)data
		return !inside(c, q) || c.lv[q.y * c.w + q.x] >= c.k
	}
	// A face cell (beyond the grid: no).
	isFace :: proc(q: [2]int, data: rawptr) -> bool {
		c := cast(^Ctx)data
		return inside(c, q) && c.face[q.y * c.w + q.x]
	}
	hex := layout == .HexPointy || layout == .HexFlat
	for k in 0 ..< count {
		hl := Gen_HeightLevel(out, k)
		tiles := make([]i32, w * h, allocator)
		slice.fill(tiles, -1)
		res.levels[k] = tiles
		pick := gen_mix(gen_mix(gen_mix(seed, u64(out.id)), 0x4e16), u64(k))
		ctx := Ctx{lv = lv, w = w, h = h, k = u8(k)}
		terrain: ^Tile_Terrain
		if hl.terrain != "" do terrain, _ = Terrains_Find(terrains, hl.terrain)
		#no_bounds_check for l, i in lv {
			if int(l) < k || (!stack && int(l) != k) do continue
			x, y := i % w, i / w
			ax, ay := origin.x + x, origin.y + y
			if hl.terrain != "" {
				if terrain != nil do tiles[i] = Terrain_Tile(terrain, Terrain_MaskAt(terrain.kind, layout, stagger, {x, y}, &ctx, member), ax, ay, pick)
			} else if len(hl.tiles) > 0 {
				tiles[i] = hl.tiles[0] if len(hl.tiles) == 1 else hl.tiles[int(gen_hash01(ax, ay, pick) * f32(len(hl.tiles))) % len(hl.tiles)]
			}
		}
		if k == 0 do continue // (the ground: no edges)
		hasCliff := len(hl.cliff) > 0 || hl.cliff_terrain != ""
		solid := hl.solid && res.walls != nil
		if !hasCliff && !solid do continue
		// The faces: below the level, the grid's north neighbour at it.
		if hasCliff {
			ctx.face = make([]bool, w * h, context.temp_allocator)
			for l, i in lv {
				if int(l) >= k do continue
				q := Grid_Compass(layout, stagger, {i % w, i / w})[0][1]
				if inside(&ctx, q) && int(lv[q.y * w + q.x]) >= k do ctx.face[i] = true
			}
			cliffT: ^Tile_Terrain
			if hl.cliff_terrain != "" do cliffT, _ = Terrains_Find(terrains, hl.cliff_terrain)
			cpick := pick ~ 0xc11ff
			for f, i in ctx.face {
				if !f do continue
				x, y := i % w, i / w
				ax, ay := origin.x + x, origin.y + y
				t := i32(-1)
				if hl.cliff_terrain != "" {
					if cliffT != nil do t = Terrain_Tile(cliffT, Terrain_MaskAt(cliffT.kind, layout, stagger, {x, y}, &ctx, isFace), ax, ay, cpick)
				} else {
					t = hl.cliff[0] if len(hl.cliff) == 1 else hl.cliff[int(gen_hash01(ax, ay, cpick) * f32(len(hl.cliff))) % len(hl.cliff)]
				}
				if t >= 0 do tiles[i] = t
			}
		}
		// Walls: the level's edge cells (a neighbour below it), and its face.
		if solid do for l, i in lv {
			c := [2]int{i % w, i / w}
			if ctx.face != nil && ctx.face[i] {
				res.walls[i] = wallTile
				continue
			}
			if int(l) < k do continue
			edge := false
			if hex {
				for q in Grid_HexSides(layout, stagger, c) do if !member(q, &ctx) do edge = true
			} else {
				nb := Grid_Compass(layout, stagger, c)
				for row in nb do for q in row do if !member(q, &ctx) do edge = true
			}
			if edge do res.walls[i] = wallTile
		}
	}
	return
}

// gen_heights_generate: a height output's levels (and walls) into a result
// - each into its map's tiles, cropped to the window's middle; levels (or
// outputs) naming the same map are laid over each other.
@(private)
gen_heights_generate :: proc(ev: ^Gen_Eval, n: ^Gen_Node, r: ^Gen_Result, apron: int, mid: [2]int, allocator: runtime.Allocator) -> string {
	grid, ok := gen_eval(ev, n.id)
	if !ok do return ev.err
	terrains: Tile_Terrains
	if text, have := ev.g.tilesets[n.tileset]; have do terrains, _ = Terrains_Parse(transmute([]u8)text, context.temp_allocator)
	hs := Gen_HeightsOf(n, grid, ev.seed, context.temp_allocator, &terrains, ev.g.layout, ev.g.stagger, ev.origin)
	crop :: proc(tiles: []i32, w, apron: int, mid: [2]int, allocator: runtime.Allocator) -> []i32 {
		out := make([]i32, mid.x * mid.y, allocator)
		for y in 0 ..< mid.y do copy(out[y * mid.x:(y + 1) * mid.x], tiles[(y + apron) * w + apron:][:mid.x])
		return out
	}
	for tiles, k in hs.levels do gen_result_put(r, Gen_HeightLevel(n, k).layer, crop(tiles, grid.w, apron, mid, allocator), allocator)
	if hs.walls != nil do gen_result_put(r, n.layer, crop(hs.walls, grid.w, apron, mid, allocator), allocator)
	return ""
}

// gen_result_put: tiles for the map `name` ("": the main one) - laid over
// the tiles already there for it (their non-empty cells win), else added.
@(private)
gen_result_put :: proc(r: ^Gen_Result, name: string, tiles: []i32, allocator: runtime.Allocator) {
	over :: proc(dst, src: []i32, allocator: runtime.Allocator) {
		for t, i in src do if t >= 0 do dst[i] = t
		delete(src, allocator)
	}
	if name == "" {
		if r.tiles == nil do r.tiles = tiles
		else do over(r.tiles, tiles, allocator)
		return
	}
	for &ly in r.layers do if ly.name == name {
		over(ly.tiles, tiles, allocator)
		return
	}
	append(&r.layers, Gen_Layer_Tiles{name, tiles})
}

// Gen_OutputMaps: the TileMaps (by name, next to the main one) an output
// fills besides the main one (temp).
Gen_OutputMaps :: proc(n: ^Gen_Node, allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, allocator)
	#partial switch n.kind {
	case .Tile_Output:
		if n.layer != "" do append(&out, n.layer)
	case .Height_Output:
		for k in 0 ..< Gen_HeightCount(n) do if l := Gen_HeightLevel(n, k).layer; l != "" && !slice.contains(out[:], l) do append(&out, l)
		if n.layer != "" && !slice.contains(out[:], n.layer) do append(&out, n.layer)
	}
	return out[:]
}

// --- editing ----------------------------------------------------------------------------

// Gen_HeightsEnsure: the node has settings for each of its levels (new ones:
// the main map, tile k, the even threshold).
Gen_HeightsEnsure :: proc(g: ^Gen_Graph, n: ^Gen_Node) {
	if n.kind != .Height_Output do return
	if n.heights == nil do n.heights = make([dynamic]Gen_Height_Level, g.allocator)
	count := Gen_HeightCount(n)
	for k := len(n.heights); k < count; k += 1 {
		hl := Gen_Height_Level{min = f32(k) / f32(count), tiles = make([dynamic]i32, g.allocator), cliff = make([dynamic]i32, g.allocator)}
		append(&hl.tiles, i32(k))
		append(&n.heights, hl)
	}
}

// Gen_HeightSetText: one of a level's names (layer, terrain, cliff_terrain)
// - the graph owns the text.
Gen_HeightSetText :: proc(g: ^Gen_Graph, field: ^string, text: string) {
	if field^ != "" do delete(field^, g.allocator)
	field^ = strings.clone(text, g.allocator) if text != "" else ""
}

@(private)
gen_heights_free :: proc(n: ^Gen_Node, allocator: runtime.Allocator) {
	for &hl in n.heights {
		delete(hl.tiles)
		delete(hl.cliff)
		for s in ([3]string{hl.layer, hl.terrain, hl.cliff_terrain}) do if s != "" do delete(s, allocator)
	}
	delete(n.heights)
	n.heights = nil
}

// gen_heights_copy: a deep copy of a node's levels (the graph's allocator).
@(private)
gen_heights_copy :: proc(src: []Gen_Height_Level, allocator: runtime.Allocator) -> [dynamic]Gen_Height_Level {
	if len(src) == 0 do return nil
	out := make([dynamic]Gen_Height_Level, allocator)
	for hl in src {
		c := hl
		c.tiles = make([dynamic]i32, allocator)
		append(&c.tiles, ..hl.tiles[:])
		c.cliff = make([dynamic]i32, allocator)
		append(&c.cliff, ..hl.cliff[:])
		c.layer = strings.clone(hl.layer, allocator) if hl.layer != "" else ""
		c.terrain = strings.clone(hl.terrain, allocator) if hl.terrain != "" else ""
		c.cliff_terrain = strings.clone(hl.cliff_terrain, allocator) if hl.cliff_terrain != "" else ""
		append(&out, c)
	}
	return out
}

// --- the file ---------------------------------------------------------------------------

@(private)
gen_heights_parse :: proc(n: ^Gen_Node, obj: json.Object, allocator: runtime.Allocator) {
	if ts, ok := obj["tileset"].(json.String); ok && ts != "" do n.tileset = strings.clone(string(ts), allocator)
	if wl, ok := obj["walls"].(json.String); ok && wl != "" do n.layer = strings.clone(string(wl), allocator)
	hs, ok := obj["heights"].(json.Array)
	if !ok do return
	n.heights = make([dynamic]Gen_Height_Level, allocator)
	ints :: proc(v: json.Value, into: ^[dynamic]i32) {
		if arr, isArr := v.(json.Array); isArr do for tv in arr do if t, isNum := json_number(tv); isNum do append(into, i32(t))
	}
	str :: proc(o: json.Object, key: string, allocator: runtime.Allocator) -> string {
		if s, isStr := o[key].(json.String); isStr && s != "" do return strings.clone(string(s), allocator)
		return ""
	}
	for hv, k in hs {
		ho, isObj := hv.(json.Object)
		if !isObj do continue
		hl := Gen_Height_Level{min = f32(k) / f32(Gen_HeightCount(n)), tiles = make([dynamic]i32, allocator), cliff = make([dynamic]i32, allocator)}
		if m, mok := json_number(ho["min"]); mok do hl.min = m
		ints(ho["tiles"], &hl.tiles)
		ints(ho["cliff"], &hl.cliff)
		hl.layer = str(ho, "layer", allocator)
		hl.terrain = str(ho, "terrain", allocator)
		hl.cliff_terrain = str(ho, "cliff_terrain", allocator)
		if b, bok := ho["solid"].(json.Boolean); bok do hl.solid = bool(b)
		append(&n.heights, hl)
	}
}

@(private)
gen_heights_serialize :: proc(w: ^Json_Writer, n: ^Gen_Node) {
	tiles :: proc(w: ^Json_Writer, list: []i32) {
		strings.write_byte(&w.sb, '[')
		for t, i in list do fmt.sbprintf(&w.sb, "%s%d", ", " if i > 0 else "", t)
		strings.write_byte(&w.sb, ']')
	}
	strings.write_string(&w.sb, ", \"heights\": [")
	for hl, k in n.heights {
		if k > 0 do strings.write_string(&w.sb, ", ")
		strings.write_string(&w.sb, "{\"min\": ")
		Json_Float(w, hl.min)
		strings.write_string(&w.sb, ", \"layer\": ")
		Json_String(w, hl.layer)
		strings.write_string(&w.sb, ", \"tiles\": ")
		tiles(w, hl.tiles[:])
		if hl.terrain != "" {
			strings.write_string(&w.sb, ", \"terrain\": ")
			Json_String(w, hl.terrain)
		}
		if len(hl.cliff) > 0 {
			strings.write_string(&w.sb, ", \"cliff\": ")
			tiles(w, hl.cliff[:])
		}
		if hl.cliff_terrain != "" {
			strings.write_string(&w.sb, ", \"cliff_terrain\": ")
			Json_String(w, hl.cliff_terrain)
		}
		if hl.solid do strings.write_string(&w.sb, ", \"solid\": true")
		strings.write_byte(&w.sb, '}')
	}
	strings.write_byte(&w.sb, ']')
	if n.tileset != "" {
		strings.write_string(&w.sb, ", \"tileset\": ")
		Json_String(w, n.tileset)
	}
	if n.layer != "" {
		strings.write_string(&w.sb, ", \"walls\": ")
		Json_String(w, n.layer)
	}
}
