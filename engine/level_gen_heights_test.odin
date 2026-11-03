package engine

import "core:slice"
import "core:strings"
import "core:testing"

// Height layers (#171, stretch): a height map cut into levels (even and
// custom thresholds), stack and only fills, each level into its TileMap,
// terrain edges (the 47-tile blob) where the height drops, cliff faces,
// walls (colliders), chunk seams, and the file.

// A 10 x 8 height map: 0.1 around, 0.5 on x 1..7, y 1..5, 0.9 on x 3..5,
// y 2..3 - levels 0, 1 and 2 with 3 even levels.
@(private = "file")
GHT_STEPS :: `{"size": [10, 8], "seed": 4, "nodes": [
	{"id": 1, "type": "constant", "params": {"value": 0.1}},
	{"id": 2, "type": "rect", "params": {"x": 1, "y": 1, "w": 7, "h": 5, "value": 0.5}},
	{"id": 3, "type": "rect", "params": {"x": 3, "y": 2, "w": 3, "h": 2, "value": 0.9}},
	{"id": 4, "type": "combine", "inputs": {"a": 1, "b": 2}, "params": {"op": "max"}},
	{"id": 5, "type": "combine", "inputs": {"a": 4, "b": 3}, "params": {"op": "max"}},
	{"id": 6, "type": "height_output", "inputs": {"in": 5}, "params": {"levels": 3}, "tileset": "textures/h.png",
	 "heights": [{"min": 0, "layer": "", "tiles": [0]}, {"min": 0.34, "layer": "Mid", "tiles": [1]}, {"min": 0.67, "layer": "Top", "tiles": [2]}]}]}`

@(private = "file")
ght_graph :: proc(text: string) -> Gen_Graph {
	g, err := Gen_GraphParse(transmute([]u8)text, context.temp_allocator)
	assert(err == "", err)
	return g
}

// Terrains whose tile for a pattern is the mask plus a base: Ground (blob,
// 100), Hill (blob, 300), Face (edges, 500).
@(private = "file")
ght_terrains :: proc(g: ^Gen_Graph) {
	ts, _ := Terrains_Parse(nil, context.temp_allocator)
	add :: proc(ts: ^Tile_Terrains, name: string, kind: Terrain_Kind, base: i32) {
		t := Terrains_Add(ts, name)
		t.kind = kind
		for m in Terrain_Patterns(kind) do append(&t.tiles[m], i32(m) + base)
	}
	add(&ts, "Ground", .Blob, 100)
	add(&ts, "Hill", .Blob, 300)
	add(&ts, "Face", .Edges, 500)
	Gen_SetTerrainSource(g, "textures/h.png", Terrains_Serialize(&ts, context.temp_allocator))
}

// A layer's tiles by its map's name ("": the main map's).
@(private = "file")
ght_layer :: proc(r: Gen_Result, name: string) -> []i32 {
	if name == "" do return r.tiles
	for ly in r.layers do if ly.name == name do return ly.tiles
	return nil
}

@(private = "file")
ght_count :: proc(tiles: []i32, tile: i32) -> int {
	n := 0
	for t in tiles do if t == tile do n += 1
	return n
}

@(test)
test_level_gen_heights_quantise :: proc(t: ^testing.T) {
	g := ght_graph(GHT_STEPS)
	n := Gen_FindNode(&g, 6)
	grid := Gen_Grid{5, 1, {0, 0.32, 0.34, 0.66, 0.99}}
	testing.expect(t, slice.equal(Gen_HeightLevelsOf(n, grid, context.temp_allocator), []u8{0, 0, 1, 1, 2}), "even: thirds")
	Gen_SetParam(n, "levels", 4)
	testing.expect(t, slice.equal(Gen_HeightLevelsOf(n, grid, context.temp_allocator), []u8{0, 1, 1, 2, 3}), "even: quarters")
	// Custom: each level's own min (level 3 has none: k / levels), never
	// below the level under it.
	Gen_SetParam(n, "levels", 3)
	Gen_SetParam(n, "thresholds", 1)
	n.heights[1].min, n.heights[2].min = 0.3, 0.95
	testing.expect(t, slice.equal(Gen_HeightLevelsOf(n, grid, context.temp_allocator), []u8{0, 1, 1, 1, 2}), "custom thresholds")
	n.heights[2].min = 0.1
	testing.expect_value(t, Gen_HeightThresholds(n)[2], 0.3)
	Gen_SetParam(n, "levels", 1)
	testing.expect(t, slice.equal(Gen_HeightLevelsOf(n, grid, context.temp_allocator), []u8{0, 0, 0, 0, 0}), "one level: all ground")
	Gen_SetParam(n, "levels", 99)
	testing.expect_value(t, Gen_HeightCount(n), GEN_HEIGHT_MAX)
	free_all(context.temp_allocator)
}

@(test)
test_level_gen_heights_fill :: proc(t: ^testing.T) {
	g := ght_graph(GHT_STEPS)
	// A graph with only a height output: it is the output; level 0 fills the
	// main map, levels 1 and 2 the maps Mid and Top.
	testing.expect_value(t, Gen_OutputNode(&g).id, 6)
	r, err := Gen_Generate(&g, 0, context.temp_allocator)
	testing.expect_value(t, err, "")
	testing.expect_value(t, len(r.layers), 2)
	main, mid, top := ght_layer(r, ""), ght_layer(r, "Mid"), ght_layer(r, "Top")
	at :: proc(tiles: []i32, x, y: int) -> i32 {return tiles[y * 10 + x]}
	// Stack: a cell fills its level and every one below.
	testing.expect_value(t, ght_count(main, 0), 80)
	testing.expect_value(t, ght_count(mid, 1), 35)
	testing.expect_value(t, ght_count(top, 2), 6)
	testing.expect_value(t, at(mid, 4, 2), 1) // (under the top: not holed)
	testing.expect_value(t, at(mid, 0, 0), -1)
	testing.expect_value(t, at(top, 3, 2), 2)
	testing.expect_value(t, at(top, 2, 2), -1)
	// Only: each cell in its own level's map.
	Gen_SetParam(Gen_FindNode(&g, 6), "fill", 1)
	r2, _ := Gen_Generate(&g, 0, context.temp_allocator)
	testing.expect_value(t, ght_count(ght_layer(r2, ""), 0), 45)
	testing.expect_value(t, ght_count(ght_layer(r2, "Mid"), 1), 29)
	testing.expect_value(t, ght_count(ght_layer(r2, "Top"), 2), 6)
	testing.expect_value(t, at(ght_layer(r2, "Mid"), 4, 2), -1)
	testing.expect_value(t, at(ght_layer(r2, ""), 4, 2), -1)
	// Two levels into one map: laid over each other (the higher on top).
	Gen_SetParam(Gen_FindNode(&g, 6), "fill", 0)
	Gen_HeightSetText(&g, &Gen_FindNode(&g, 6).heights[2].layer, "Mid")
	r3, _ := Gen_Generate(&g, 0, context.temp_allocator)
	testing.expect_value(t, len(r3.layers), 1)
	testing.expect_value(t, at(ght_layer(r3, "Mid"), 4, 2), 2)
	testing.expect_value(t, at(ght_layer(r3, "Mid"), 1, 1), 1)
	// With a tile output as the main map: a level naming "" lays over it.
	tg := ght_graph(`{"size": [4, 1], "output": 3, "nodes": [
		{"id": 1, "type": "rect", "params": {"x": 2, "y": 0, "w": 2, "h": 1, "value": 0.9}},
		{"id": 2, "type": "height_output", "inputs": {"in": 1}, "params": {"levels": 2},
		 "heights": [{"min": 0, "layer": "", "tiles": []}, {"min": 0.5, "layer": "", "tiles": [8]}]},
		{"id": 3, "type": "tile_output", "inputs": {"in": 1}, "rules": [{"min": 0, "max": 1, "tiles": [3]}]}]}`)
	r4, _ := Gen_Generate(&tg, 0, context.temp_allocator)
	testing.expect(t, slice.equal(r4.tiles, []i32{3, 3, 8, 8}), "over the tile output's tiles")
	free_all(context.temp_allocator)
}

@(test)
test_level_gen_heights_terrain_edges :: proc(t: ^testing.T) {
	g := ght_graph(GHT_STEPS)
	ght_terrains(&g)
	n := Gen_FindNode(&g, 6)
	Gen_HeightSetText(&g, &n.heights[0].terrain, "Ground")
	Gen_HeightSetText(&g, &n.heights[1].terrain, "Hill")
	Gen_HeightSetText(&g, &n.heights[2].terrain, "Hill")
	r, err := Gen_Generate(&g, 0, context.temp_allocator)
	testing.expect_value(t, err, "")
	main, mid, top := ght_layer(r, ""), ght_layer(r, "Mid"), ght_layer(r, "Top")
	at :: proc(tiles: []i32, x, y: int) -> i32 {return tiles[y * 10 + x]}
	FULL :: i32(255)
	// The ground: every cell the full pattern (it never drops below 0).
	testing.expect_value(t, ght_count(main, FULL + 100), 80)
	// Level 1's edges - the 47-blob patterns of the cells at 1 or higher.
	testing.expect_value(t, at(mid, 1, 1), i32(TERRAIN_E | TERRAIN_SE | TERRAIN_S) + 300) // top-left corner
	testing.expect_value(t, at(mid, 2, 1), i32(TERRAIN_E | TERRAIN_SE | TERRAIN_S | TERRAIN_SW | TERRAIN_W) + 300) // top edge
	testing.expect_value(t, at(mid, 7, 5), i32(TERRAIN_N | TERRAIN_W | TERRAIN_NW) + 300) // bottom-right corner
	testing.expect_value(t, at(mid, 1, 3), i32(TERRAIN_N | TERRAIN_NE | TERRAIN_E | TERRAIN_SE | TERRAIN_S) + 300) // left edge
	// Against the top level (higher): no edge - the middle's full.
	testing.expect_value(t, at(mid, 2, 2), FULL + 300)
	testing.expect_value(t, at(mid, 4, 2), FULL + 300)
	// Level 2's own edges.
	testing.expect_value(t, at(top, 3, 2), i32(TERRAIN_E | TERRAIN_SE | TERRAIN_S) + 300)
	testing.expect_value(t, at(top, 4, 3), i32(TERRAIN_W | TERRAIN_NW | TERRAIN_N | TERRAIN_NE | TERRAIN_E) + 300)
	// Every written cell matches Terrain_Mask of its neighbourhood (cells at
	// the level or higher; beyond the level: yes).
	lv := Gen_HeightLevelsOf(n, gen_ht_grid(&g), context.temp_allocator)
	for k in 1 ..< 3 {
		tiles := ght_layer(r, "Mid" if k == 1 else "Top")
		bad := 0
		for y in 0 ..< 8 do for x in 0 ..< 10 {
			if int(lv[y * 10 + x]) < k {
				if tiles[y * 10 + x] != -1 do bad += 1
				continue
			}
			nb: [3][3]bool
			for dy in 0 ..< 3 do for dx in 0 ..< 3 {
				q := [2]int{x + dx - 1, y + dy - 1}
				nb[dy][dx] = q.x < 0 || q.y < 0 || q.x >= 10 || q.y >= 8 || int(lv[q.y * 10 + q.x]) >= k
			}
			if tiles[y * 10 + x] != i32(Terrain_Mask(.Blob, nb)) + 300 do bad += 1
		}
		testing.expectf(t, bad == 0, "level %d: %d cells off the blob rules", k, bad)
	}
	// A terrain the tileset doesn't have: the level's cells empty.
	Gen_HeightSetText(&g, &n.heights[2].terrain, "Nope")
	r2, _ := Gen_Generate(&g, 0, context.temp_allocator)
	testing.expect_value(t, ght_count(ght_layer(r2, "Top"), -1), 80)
	free_all(context.temp_allocator)
}

// (The steps graph's height map.)
@(private = "file")
gen_ht_grid :: proc(g: ^Gen_Graph) -> Gen_Grid {
	grid, _ := Gen_Evaluate(g, 5, 0, context.temp_allocator)
	return grid
}

@(test)
test_level_gen_heights_cliffs_and_walls :: proc(t: ^testing.T) {
	g := ght_graph(GHT_STEPS)
	ght_terrains(&g)
	n := Gen_FindNode(&g, 6)
	append(&n.heights[1].cliff, 50)
	Gen_HeightSetText(&g, &n.heights[2].cliff_terrain, "Face")
	at :: proc(tiles: []i32, x, y: int) -> i32 {return tiles[y * 10 + x]}
	r, _ := Gen_Generate(&g, 0, context.temp_allocator)
	mid, top := ght_layer(r, "Mid"), ght_layer(r, "Top")
	// Level 1's face: the row just south of its bottom edge.
	for x in 1 ..= 7 do testing.expectf(t, at(mid, x, 6) == 50, "face at %d, 6: %d", x, at(mid, x, 6))
	testing.expect_value(t, at(mid, 0, 6), -1)
	testing.expect_value(t, at(mid, 1, 7), -1)
	testing.expect_value(t, ght_count(mid, 50), 7)
	// Level 2's face (row 4, on level 1): a strip auto-tiled with the edges
	// terrain - its ends and middle.
	testing.expect_value(t, at(top, 3, 4), 2 + 500) // (E)
	testing.expect_value(t, at(top, 4, 4), 10 + 500) // (E, W)
	testing.expect_value(t, at(top, 5, 4), 8 + 500) // (W)
	testing.expect_value(t, at(top, 4, 5), -1)
	// A cliff terrain reads 2 cells: the apron.
	testing.expect_value(t, Gen_HeightReach(n), 2)
	testing.expect_value(t, Gen_ChunkInfo(&g, context.temp_allocator).apron, 2)

	// Walls: level 1 solid - its edge ring (20) and face (7) into Walls.
	testing.expect(t, ght_layer(r, "Walls") == nil, "no walls map: no walls")
	Gen_SetLayer(&g, n, "Walls")
	r1, _ := Gen_Generate(&g, 0, context.temp_allocator)
	testing.expect(t, ght_layer(r1, "Walls") == nil, "no solid level: no walls")
	n.heights[1].solid = true
	Gen_SetParam(n, "walls_tile", 9)
	r2, _ := Gen_Generate(&g, 0, context.temp_allocator)
	walls := ght_layer(r2, "Walls")
	testing.expect(t, walls != nil, "walls")
	testing.expect_value(t, ght_count(walls, 9), 27)
	testing.expect_value(t, at(walls, 1, 1), 9)
	testing.expect_value(t, at(walls, 4, 5), 9) // (bottom edge)
	testing.expect_value(t, at(walls, 4, 6), 9) // (its face)
	testing.expect_value(t, at(walls, 2, 2), -1) // (inside)
	testing.expect_value(t, at(walls, 0, 0), -1)
	testing.expect(t, slice.contains(Gen_OutputMaps(n), "Walls") && slice.contains(Gen_OutputMaps(n), "Top"), "its maps")

	// Into a scene: the main map, Mid, Top and a Solid Walls map - colliders
	// on the walls.
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("heights", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	root := CreateNode(scene.manager, Node)
	scene->addNode(root)
	ground := TileMapNode_Create(scene, "Ground", root)
	mm := TileMapNode_Create(scene, "Mid", root)
	tm := TileMapNode_Create(scene, "Top", root)
	wm := TileMapNode_Create(scene, "Walls", root)
	wm.solid = true
	ProcessNodeQueues(scene.manager, &game.gameContext)
	why := Gen_ApplyResult(&r2, ground, &game.gameContext, scene)
	testing.expect_value(t, why, "")
	testing.expect_value(t, TileMapNode_Get(ground, 0, 0), 0)
	testing.expect_value(t, TileMapNode_Get(mm, 1, 1), 1)
	testing.expect_value(t, TileMapNode_Get(mm, 3, 6), 50)
	testing.expect_value(t, TileMapNode_Get(tm, 4, 4), 510)
	testing.expect_value(t, TileMapNode_Get(wm, 1, 1), 9)
	if !wm.isReady do TileMapNode_BuildColliders(wm, &game.gameContext) // (not ready yet in a test)
	testing.expect(t, wm.staticBody != nil && len(wm.staticBody.shapes) > 0, "the walls' colliders")
	free_all(context.temp_allocator)
}

// A noise height map with terrains, a cliff terrain and walls: chunks give
// the area's cells on every map exactly.
@(private = "file")
GHT_NOISE :: `{"size": [64, 64], "seed": 21, "nodes": [
	{"id": 1, "type": "noise", "params": {"type": "perlin", "scale": 9, "octaves": 2}},
	{"id": 2, "type": "blur", "inputs": {"in": 1}, "params": {"radius": 1}},
	{"id": 3, "type": "height_output", "inputs": {"in": 2}, "params": {"levels": 3, "walls_tile": 4}, "tileset": "textures/h.png", "walls": "Walls",
	 "heights": [{"min": 0, "layer": "", "tiles": [0, 1], "terrain": "Ground"},
	             {"min": 0.4, "layer": "Mid", "tiles": [], "terrain": "Hill", "cliff": [60, 61], "solid": true},
	             {"min": 0.55, "layer": "Top", "tiles": [7, 8], "cliff_terrain": "Face", "solid": true}]}]}`

@(test)
test_level_gen_heights_chunk_seams :: proc(t: ^testing.T) {
	g := ght_graph(GHT_NOISE)
	ght_terrains(&g)
	Gen_SetParam(Gen_FindNode(&g, 3), "thresholds", 1)
	info := Gen_ChunkInfo(&g, context.temp_allocator)
	testing.expect_value(t, info.apron, 3) // (blur 1 + the cliff terrain's 2)
	testing.expect_value(t, len(info.unsafe), 0)
	testing.expect(t, Gen_KindChunkSafe(.Height_Output), "chunk-safe")
	S :: 16
	seed := u64(5)
	area, err := Gen_GenerateWindow(&g, seed, {-S, -S}, {2 * S, 2 * S}, info.apron, 0, context.temp_allocator)
	testing.expect_value(t, err, "")
	testing.expect_value(t, len(area.layers), 3)
	names := []string{"", "Mid", "Top", "Walls"}
	for name in names do testing.expectf(t, ght_count(ght_layer(area, name), -1) < 4 * S * S, "%q has tiles", name)
	testing.expect(t, ght_count(ght_layer(area, "Walls"), 4) > 0, "some walls")
	diff := 0
	for c in ([4][2]int{{-1, -1}, {0, -1}, {-1, 0}, {0, 0}}) {
		ch, cerr := Gen_GenerateChunk(&g, seed, c, S, info.apron, context.temp_allocator)
		testing.expect_value(t, cerr, "")
		for name in names {
			a, b := ght_layer(area, name), ght_layer(ch, name)
			if b == nil {
				diff += 1
				continue
			}
			for y in 0 ..< S do for x in 0 ..< S {
				l := ch.origin + {x, y} - area.origin
				if b[y * S + x] != a[l.y * area.size.x + l.x] do diff += 1
			}
		}
	}
	testing.expectf(t, diff == 0, "%d cells differ at the seams", diff)
	// Too small an apron: the seams show.
	thin, _ := Gen_GenerateChunk(&g, seed, {0, 0}, S, 0, context.temp_allocator)
	full, _ := Gen_GenerateChunk(&g, seed, {0, 0}, S, info.apron, context.temp_allocator)
	d := 0
	for name in names do for v, i in ght_layer(thin, name) do if v != ght_layer(full, name)[i] do d += 1
	testing.expectf(t, d > 0, "apron 0: cells differ (%d)", d)
	free_all(context.temp_allocator)
}

@(test)
test_level_gen_heights_file :: proc(t: ^testing.T) {
	g, err := Gen_GraphParse(transmute([]u8)string(GHT_NOISE))
	testing.expectf(t, err == "", "parse: %s", err)
	defer Gen_GraphDestroy(&g)
	n := Gen_FindNode(&g, 3)
	testing.expect_value(t, n.kind, Gen_Kind.Height_Output)
	testing.expect_value(t, len(n.heights), 3)
	testing.expect_value(t, n.layer, "Walls")
	testing.expect_value(t, n.tileset, "textures/h.png")
	testing.expect_value(t, n.heights[1].min, 0.4)
	testing.expect(t, n.heights[1].solid && !n.heights[0].solid, "solid")
	testing.expect(t, slice.equal(n.heights[1].cliff[:], []i32{60, 61}), "cliff tiles")
	testing.expect_value(t, n.heights[2].cliff_terrain, "Face")
	// Saved and read back the same.
	text := Gen_GraphSerialize(&g, context.temp_allocator)
	for s in ([]string{`"type": "height_output"`, `"heights": [`, `"walls": "Walls"`, `"cliff_terrain": "Face"`, `"solid": true`, `"cliff": [60, 61]`, `"fill": "stack"`, `"thresholds": "even"`}) {
		testing.expectf(t, strings.contains(text, s), "saved %s: %s", s, text)
	}
	g2, err2 := Gen_GraphParse(transmute([]u8)text)
	testing.expect_value(t, err2, "")
	defer Gen_GraphDestroy(&g2)
	testing.expect_value(t, Gen_GraphSerialize(&g2, context.temp_allocator), text)
	// Duplicated: its own copy of the levels.
	dup := Gen_DuplicateNode(&g, 3)
	testing.expect_value(t, len(dup.heights), 3)
	testing.expect(t, dup.heights[1].terrain == "Hill" && raw_data(dup.heights[1].terrain) != raw_data(n.heights[1].terrain) && raw_data(dup.heights[1].cliff) != raw_data(n.heights[1].cliff), "a deep copy")
	testing.expect_value(t, dup.layer, "Walls")
	// A new one: its levels set up (the main map, tile k).
	add := Gen_AddNode(&g, .Height_Output, {0, 0})
	testing.expect_value(t, len(add.heights), 3)
	testing.expect(t, slice.equal(add.heights[2].tiles[:], []i32{2}), "tile k")
	Gen_SetParam(add, "levels", 5)
	Gen_HeightsEnsure(&g, add)
	testing.expect_value(t, len(add.heights), 5)
	testing.expect_value(t, add.heights[4].min, 0.8)
	// Copy and paste carry the levels.
	clip := Gen_CopyNodes(&g, {3}, context.temp_allocator)
	ids, perr := Gen_PasteNodes(&g, clip, {10, 10}, context.temp_allocator)
	testing.expect_value(t, perr, "")
	testing.expect_value(t, len(Gen_FindNode(&g, ids[0]).heights), 3)
	Gen_RemoveNode(&g, dup.id)
	free_all(context.temp_allocator)
}
