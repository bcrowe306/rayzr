package engine

import "core:fmt"
import os "osx"
import "core:slice"
import "core:strings"
import "core:testing"
import "core:time"
import lua "lua54"

// Chunked level generation (#171, stretch): seams (chunks against one big
// window and the plain level), each chunk's determinism, chunk safety and
// the apron, the TileMap's endless storage (negative cells), and the
// LevelGeneratorNode loading and unloading chunks as a camera moves.

// Chunk-safe: noise (Perlin and value), blur, threshold, random fill,
// combine, cellular, dilate, a gradient, a rectangle, a tile output with
// random picks, a pattern rule and a layer, surface -> scatter -> entities.
@(private = "file")
GCT_SAFE :: `{"size": [64, 48], "seed": 9, "output": 11, "nodes": [
	{"id": 1, "type": "noise", "params": {"type": "perlin", "scale": 10, "octaves": 3}},
	{"id": 2, "type": "blur", "inputs": {"in": 1}, "params": {"radius": 2}},
	{"id": 3, "type": "threshold", "inputs": {"in": 2}, "params": {"value": 0.5}},
	{"id": 4, "type": "random_fill", "params": {"density": 0.1}},
	{"id": 5, "type": "combine", "inputs": {"a": 3, "b": 4}, "params": {"op": "max"}},
	{"id": 6, "type": "cellular", "inputs": {"in": 5}, "params": {"iterations": 3}},
	{"id": 7, "type": "dilate", "inputs": {"in": 6}, "params": {"iterations": 1}},
	{"id": 8, "type": "noise", "params": {"scale": 6}},
	{"id": 9, "type": "gradient", "params": {"direction": "vertical"}},
	{"id": 10, "type": "combine", "inputs": {"a": 8, "b": 9}, "params": {"op": "average"}},
	{"id": 11, "type": "tile_output", "inputs": {"in": 7}, "rules": [{"min": 0.5, "max": 1, "tiles": [1, 2, 3]}],
	 "patterns": [{"min": 0.5, "max": 1, "cells": [0, -1, 0, 0, 1, 0, 0, 0, 0], "tiles": [7, 8], "chance": 0.7}]},
	{"id": 12, "type": "rect", "params": {"x": -5, "y": 3, "w": 20, "h": 4}},
	{"id": 13, "type": "combine", "inputs": {"a": 10, "b": 12}, "params": {"op": "max"}},
	{"id": 14, "type": "tile_output", "inputs": {"in": 13}, "layer": "Deco", "rules": [{"min": 0.6, "max": 2, "tiles": [4, 5]}]},
	{"id": 15, "type": "surface", "inputs": {"in": 7}},
	{"id": 16, "type": "scatter", "inputs": {"in": 15}, "params": {"chance": 0.2, "spacing": 3}},
	{"id": 17, "type": "entity_output", "inputs": {"in": 16}, "component": "c.component.json"}]}`

@(private = "file")
gct_graph :: proc(text: string) -> Gen_Graph {
	g, err := Gen_GraphParse(transmute([]u8)text, context.temp_allocator)
	assert(err == "", err)
	return g
}

// The area's entities, as absolute cells (sorted).
@(private = "file")
gct_entities :: proc(rs: []Gen_Result) -> [][2]int {
	out := make([dynamic][2]int, context.temp_allocator)
	for r in rs do for en in r.entities do append(&out, r.origin + en.cell)
	slice.sort_by(out[:], proc(a, b: [2]int) -> bool {return a.y < b.y || (a.y == b.y && a.x < b.x)})
	return out[:]
}

// A window's tile at an absolute cell (tiles: the result's main or a layer's).
@(private = "file")
gct_at :: proc(r: Gen_Result, tiles: []i32, c: [2]int) -> (i32, bool) {
	l := c - r.origin
	if l.x < 0 || l.y < 0 || l.x >= r.size.x || l.y >= r.size.y do return 0, false
	return tiles[l.y * r.size.x + l.x], true
}

// gct_same: the chunks give the area's cells (main tiles and the layer's)
// and entities exactly.
@(private = "file")
gct_same :: proc(t: ^testing.T, area: Gen_Result, chunks: []Gen_Result, what: string) {
	diff := 0
	for ch in chunks {
		testing.expect_value(t, len(ch.layers), 1)
		for y in 0 ..< ch.size.y do for x in 0 ..< ch.size.x {
			c := ch.origin + {x, y}
			want, ok := gct_at(area, area.tiles, c)
			testing.expectf(t, ok, "%s: %v inside the area", what, c)
			if ch.tiles[y * ch.size.x + x] != want do diff += 1
			wl, _ := gct_at(area, area.layers[0].tiles, c)
			if ch.layers[0].tiles[y * ch.size.x + x] != wl do diff += 1
		}
	}
	testing.expectf(t, diff == 0, "%s: %d cells differ at the seams", what, diff)
	a := gct_entities({area})
	b := gct_entities(chunks)
	testing.expectf(t, slice.equal(a, b), "%s: the same entities (%d against %d)", what, len(a), len(b))
	testing.expectf(t, len(a) > 0, "%s: some entities", what)
}

@(test)
test_level_gen_chunk_seams :: proc(t: ^testing.T) {
	g := gct_graph(GCT_SAFE)
	info := Gen_ChunkInfo(&g, context.temp_allocator)
	// Entities: scatter (spacing 3: 2) + surface (1) + dilate (1) + cellular
	// (3) + blur (2) = 9; the tiles' path 1 + 1 + 3 + 2 = 7.
	testing.expect_value(t, info.apron, 9)
	testing.expect_value(t, len(info.unsafe), 0)
	seed := u64(77)
	S :: 16
	// Chunks (0, 0) and (1, 0) against the 32 x 16 area as one window.
	area, err := Gen_GenerateWindow(&g, seed, {0, 0}, {2 * S, S}, info.apron, 0, context.temp_allocator)
	testing.expect_value(t, err, "")
	c0, e0 := Gen_GenerateChunk(&g, seed, {0, 0}, S, info.apron, context.temp_allocator)
	c1, e1 := Gen_GenerateChunk(&g, seed, {1, 0}, S, info.apron, context.temp_allocator)
	testing.expect(t, e0 == "" && e1 == "", "chunks made")
	testing.expect_value(t, c1.origin, [2]int{S, 0})
	testing.expect_value(t, c1.size, [2]int{S, S})
	gct_same(t, area, {c0, c1}, "chunks (0, 0) and (1, 0)")
	// Negative chunks: four around the origin against one 32 x 32 window.
	area2, _ := Gen_GenerateWindow(&g, seed, {-S, -S}, {2 * S, 2 * S}, info.apron, 0, context.temp_allocator)
	quad: [4]Gen_Result
	for c, i in ([4][2]int{{-1, -1}, {0, -1}, {-1, 0}, {0, 0}}) do quad[i], _ = Gen_GenerateChunk(&g, seed, c, S, info.apron, context.temp_allocator)
	testing.expect_value(t, quad[0].origin, [2]int{-S, -S})
	gct_same(t, area2, quad[:], "chunks around 0, 0")
	// With too small an apron the seams show (the test can tell).
	thin, _ := Gen_GenerateChunk(&g, seed, {1, 0}, S, 2, context.temp_allocator)
	d := 0
	for v, i in thin.tiles do if v != c1.tiles[i] do d += 1
	testing.expectf(t, d > 0, "apron 2 instead of 9: cells differ (%d)", d)
	// The plain level (Gen_Generate) agrees away from its edges: its tiles
	// at chunk (1, 1) are the chunk's (the scatter differs: a row scan there).
	whole, werr := Gen_Generate(&g, seed, context.temp_allocator)
	testing.expect_value(t, werr, "")
	c11, _ := Gen_GenerateChunk(&g, seed, {1, 1}, S, info.apron, context.temp_allocator)
	d = 0
	for y in 0 ..< S do for x in 0 ..< S do if whole.tiles[(S + y) * whole.size.x + S + x] != c11.tiles[y * S + x] do d += 1
	testing.expectf(t, d == 0, "the level's tiles at chunk (1, 1): %d differ", d)
}

@(test)
test_level_gen_chunk_determinism :: proc(t: ^testing.T) {
	g := gct_graph(GCT_SAFE)
	info := Gen_ChunkInfo(&g, context.temp_allocator)
	a, _ := Gen_GenerateChunk(&g, 5, {3, -2}, 24, info.apron, context.temp_allocator)
	b, _ := Gen_GenerateChunk(&g, 5, {3, -2}, 24, info.apron, context.temp_allocator)
	c, _ := Gen_GenerateChunk(&g, 6, {3, -2}, 24, info.apron, context.temp_allocator)
	testing.expect(t, slice.equal(a.tiles, b.tiles) && slice.equal(gct_entities({a}), gct_entities({b})), "a chunk always comes out the same")
	testing.expect(t, !slice.equal(a.tiles, c.tiles), "another seed, another chunk")
	testing.expect_value(t, Gen_ChunkSeed(5, {3, -2}), Gen_ChunkSeed(5, {3, -2}))
	testing.expect(t, Gen_ChunkSeed(5, {3, -2}) != Gen_ChunkSeed(5, {-2, 3}) && Gen_ChunkSeed(5, {0, 0}) != 0, "chunk seeds differ")
	// A graph that isn't chunk-safe (rooms): each chunk its own dungeon,
	// the same one every time.
	rooms := gct_graph(`{"size": [40, 40], "seed": 3, "nodes": [
		{"id": 1, "type": "rooms"},
		{"id": 2, "type": "tile_output", "inputs": {"in": 1}, "rules": [{"min": 0.5, "max": 1, "tile": 1}]}]}`)
	ri := Gen_ChunkInfo(&rooms, context.temp_allocator)
	r1, _ := Gen_GenerateChunk(&rooms, 3, {0, 0}, 32, ri.apron, context.temp_allocator)
	r2, _ := Gen_GenerateChunk(&rooms, 3, {1, 0}, 32, ri.apron, context.temp_allocator)
	r3, _ := Gen_GenerateChunk(&rooms, 3, {1, 0}, 32, ri.apron, context.temp_allocator)
	testing.expect(t, !slice.equal(r1.tiles, r2.tiles), "rooms differ per chunk (its own seed)")
	testing.expect(t, slice.equal(r2.tiles, r3.tiles), "and stay the same")
	testing.expect_value(t, Gen_ChunkOf({-1, 0}, 32), [2]int{-1, 0})
	testing.expect_value(t, Gen_ChunkOf({-33, 31}, 32), [2]int{-2, 0})
	testing.expect_value(t, Gen_ChunkOf({64, -64}, 32), [2]int{2, -2})
}

@(test)
test_level_gen_chunk_safety :: proc(t: ^testing.T) {
	// Rooms and a border reach the output; the walker isn't connected;
	// blur 3 then cellular 2 then the output's 1: apron 6.
	g := gct_graph(`{"size": [32, 32], "nodes": [
		{"id": 1, "type": "rooms"},
		{"id": 2, "type": "border"},
		{"id": 3, "type": "combine", "inputs": {"a": 1, "b": 2}, "params": {"op": "max"}},
		{"id": 4, "type": "blur", "inputs": {"in": 3}, "params": {"radius": 3}},
		{"id": 5, "type": "cellular", "inputs": {"in": 4}, "params": {"iterations": 2}},
		{"id": 6, "type": "walker"},
		{"id": 7, "type": "tile_output", "inputs": {"in": 5}, "rules": [{"min": 0.5, "max": 1, "tile": 1}]}]}`)
	info := Gen_ChunkInfo(&g, context.temp_allocator)
	testing.expect_value(t, info.apron, 6)
	testing.expectf(t, slice.equal(info.unsafe, []int{1, 2}), "rooms and border, not the unconnected walker: %v", info.unsafe)
	for k in Gen_Kind do if k != .Custom && k != .Script {
		// (Every kind is classified: the editor's warnings rely on it.)
		_ = Gen_KindChunkSafe(k)
	}
	testing.expect(t, Gen_KindChunkSafe(.Noise) && Gen_KindChunkSafe(.Cellular) && Gen_KindChunkSafe(.Scatter), "position nodes are safe")
	testing.expect(t, !Gen_KindChunkSafe(.WFC) && !Gen_KindChunkSafe(.Poisson_Scatter) && !Gen_KindChunkSafe(.Check) && !Gen_KindChunkSafe(.Script), "global ones aren't")
	// A layer or entity output's path counts too.
	h := gct_graph(`{"size": [32, 32], "nodes": [
		{"id": 1, "type": "noise"},
		{"id": 2, "type": "tile_output", "inputs": {"in": 1}, "rules": []},
		{"id": 3, "type": "flood_fill", "inputs": {"in": 1}},
		{"id": 4, "type": "erode", "inputs": {"in": 3}, "params": {"iterations": 4}},
		{"id": 5, "type": "entity_output", "inputs": {"in": 4}, "component": "x.component.json"}]}`)
	hi := Gen_ChunkInfo(&h, context.temp_allocator)
	testing.expect_value(t, hi.apron, 4)
	testing.expect(t, slice.equal(hi.unsafe, []int{3}), "the entity path's flood fill")
}

@(test)
test_tilemap_endless_storage :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("tm_endless", true)
	tm := TileMapNode_Create(scene, "Map")
	tm.mapSize = {10, 10}
	TileMapNode_Layout(tm)
	// A plain map: a block beyond it, negative cells, grows the storage and
	// keeps the map covered.
	block := make([]i32, 4 * 3, context.temp_allocator)
	for &v, i in block do v = i32(i)
	TileMapNode_SetBlock(tm, {-6, -5}, {4, 3}, block)
	testing.expect_value(t, TileMapNode_Get(tm, -6, -5), 0)
	testing.expect_value(t, TileMapNode_Get(tm, -3, -3), 11)
	lo, hi := TileMapNode_Extent(tm)
	testing.expect(t, lo == {-6, -5} && hi == {10, 10}, "the storage covers the block and the map")
	TileMapNode_SetBlock(tm, {-6, -5}, {4, 3}, nil)
	testing.expect_value(t, TileMapNode_Get(tm, -3, -3), -1)
	// Endless: only what is laid out - far from the map, no storage between.
	tm.unbounded = true
	TileMapNode_Reset(tm)
	TileMapNode_FitStorage(tm, {-1000, 500}, {-968, 532})
	TileMapNode_SetBlock(tm, {-1000, 500}, {4, 3}, block)
	lo, hi = TileMapNode_Extent(tm)
	testing.expectf(t, lo == {-1000, 500} && hi == {-968, 532}, "endless: just the area (%v .. %v)", lo, hi)
	testing.expect_value(t, len(tm.tiles), 32 * 32)
	testing.expect_value(t, TileMapNode_Get(tm, -997, 502), 11)
	testing.expect_value(t, TileMapNode_Get(tm, 0, 0), -1)
	tm.mapSize = {40, 40}
	TileMapNode_Layout(tm) // (doesn't pull the map's cells in)
	testing.expect_value(t, len(tm.tiles), 32 * 32)
	// Fitting elsewhere keeps the tiles inside, drops the area left.
	TileMapNode_FitStorage(tm, {-1000, 500}, {-990, 510})
	testing.expect_value(t, TileMapNode_Get(tm, -997, 502), 11)
	testing.expect_value(t, len(tm.tiles), 100)
	// A painted cell outside grows it as before.
	TileMapNode_Set(tm, -1010, 499, 3)
	testing.expect_value(t, TileMapNode_Get(tm, -1010, 499), 3)
	// Colliders per area: a body of its own, none for the whole map.
	ctx := &game.gameContext
	ctx.scene = scene
	tm.solid = true
	TileMapNode_BuildColliders(tm, ctx)
	testing.expect(t, tm.staticBody == nil, "endless: no whole-map body")
	body := TileMapNode_BuildCollidersIn(tm, {-1000, 500}, {-990, 510}, ctx)
	testing.expect(t, body != nil && len(body.shapes) == 3, "three rows of the block: three boxes")
}

// --- the node -------------------------------------------------------------------------

@(private = "file")
GCT_DIR :: "test_level_gen_chunks"

@(private = "file")
gct_game :: proc() -> (^Game, ^Scene) {
	_ = os.make_directory_all(GCT_DIR + "/levels")
	_ = os.write_entire_file(GCT_DIR + "/levels/world.levelgen.json", transmute([]u8)string(`{"size": [64, 64], "seed": 4, "nodes": [
		{"id": 1, "type": "noise", "params": {"type": "simplex", "scale": 12, "octaves": 2}},
		{"id": 2, "type": "threshold", "inputs": {"in": 1}, "params": {"value": 0.55}},
		{"id": 3, "type": "cellular", "inputs": {"in": 2}, "params": {"iterations": 2}},
		{"id": 4, "type": "tile_output", "inputs": {"in": 3}, "rules": [{"min": 0.5, "max": 1, "tile": 1}]},
		{"id": 5, "type": "surface", "inputs": {"in": 3}},
		{"id": 6, "type": "scatter", "inputs": {"in": 5}, "params": {"chance": 0.1, "spacing": 4}},
		{"id": 7, "type": "entity_output", "inputs": {"in": 6}, "component": "coin.component.json"}]}`))
	_ = os.write_entire_file(GCT_DIR + "/levels/rooms.levelgen.json", transmute([]u8)string(`{"size": [32, 32], "seed": 4, "nodes": [
		{"id": 1, "type": "rooms"},
		{"id": 2, "type": "tile_output", "inputs": {"in": 1}, "rules": [{"min": 0.5, "max": 1, "tile": 1}]}]}`))
	_ = os.write_entire_file(GCT_DIR + "/coin.component.json", transmute([]u8)string(`{"type": "Node", "name": "Coin"}`))
	game := new(Game)
	InitializeGame(game)
	AssetManager_SetProjectDir(&game.assetManager, GCT_DIR)
	scene := game->createScene("gct", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.gameContext.scene = scene
	game.state = .Running
	return game, scene
}

@(private = "file")
Gct_Events :: struct {
	in_, out: [dynamic][2]int,
}

@(private = "file")
gct_record_in :: proc(source: rawptr, value: EventValue, ctx: ^GameContext, user: rawptr) {
	v := value.([2]f32)
	append(&(cast(^Gct_Events)user).in_, [2]int{int(v.x), int(v.y)})
}

@(private = "file")
gct_record_out :: proc(source: rawptr, value: EventValue, ctx: ^GameContext, user: rawptr) {
	v := value.([2]f32)
	append(&(cast(^Gct_Events)user).out, [2]int{int(v.x), int(v.y)})
}

// gct_settle updates until the chunks around the camera are all in and
// nothing is being made (or 20 s pass: a deadline, never a count of short
// sleeps). Returns the slowest update.
@(private = "file")
gct_settle :: proc(lg: ^LevelGeneratorNode, scene: ^Scene, ctx: ^GameContext) -> time.Duration {
	start := time.tick_now()
	slowest: time.Duration
	for time.tick_since(start) < 20 * time.Second {
		u := time.tick_now()
		LevelGeneratorNode_Update(lg, ctx, 0.016)
		slowest = max(slowest, time.tick_since(u))
		ProcessNodeQueues(scene.manager, ctx)
		if lg.progress >= 1 && !LevelGeneratorNode_Generating(lg) do break
		time.sleep(time.Millisecond)
	}
	return slowest
}

@(private = "file")
gct_loaded :: proc(lg: ^LevelGeneratorNode) -> [][2]int {
	cs := LevelGeneratorNode_LoadedChunks(lg)
	slice.sort_by(cs, proc(a, b: [2]int) -> bool {return a.y < b.y || (a.y == b.y && a.x < b.x)})
	return cs
}

@(private = "file")
gct_around :: proc(c: [2]int, r: int) -> [][2]int {
	out := make([dynamic][2]int, context.temp_allocator)
	for y in -r ..= r do for x in -r ..= r do append(&out, c + {x, y})
	return out[:]
}

@(private = "file")
gct_count :: proc(scene: ^Scene, tm: ^TileMapNode) -> (coins, bodies: int) {
	for ch in GetChildrenTemp(scene.manager, tm) {
		if ch == nil || ch.removing do continue
		if ch.name == "Coin" do coins += 1
		if ch.typeId == StaticBodyNode do bodies += 1
	}
	return
}

@(test)
test_level_gen_chunks_follow_camera :: proc(t: ^testing.T) {
	game, scene := gct_game()
	defer os.remove_all(GCT_DIR)
	defer game->terminate()
	ctx := &game.gameContext
	cam := Node_CreateByTypeName(scene, "Node")
	cam.name = "Cam"
	lg := LevelGeneratorNode_Create(scene, "Gen")
	lg.gameContext = ctx
	lg.generator = strings.clone("levels/world.levelgen.json", lg.allocator)
	lg.chunked, lg.chunkSize, lg.chunkRadius = true, 16, 1
	lg.background = true
	lg.cameraPath = strings.clone("../Cam", lg.allocator)
	tm := cast(^TileMapNode)Node_CreateByTypeName(scene, "TileMapNode", lg)
	tm.name = "Ground"
	tm.gameContext = ctx
	tm.tileSize = {16, 16}
	tm.solid = true
	ev: Gct_Events
	ev.in_ = make([dynamic][2]int, context.temp_allocator)
	ev.out = make([dynamic][2]int, context.temp_allocator)
	lg.onChunkGenerated->subscribe(gct_record_in, &ev)
	lg.onChunkUnloaded->subscribe(gct_record_out, &ev)
	ProcessNodeQueues(scene.manager, ctx)
	Scene_CallReady(scene, scene.rootNode, ctx) // (the map ready: solid maps get colliders)
	// Camera over cell (5, 5): chunk (0, 0) and the 8 around it.
	cam.position = {5 * 16, 5 * 16}
	Node_SetGlobalPositions(scene.manager, scene.rootNode)
	slow1 := gct_settle(lg, scene, ctx)
	testing.expect(t, lg.world != nil, "chunked")
	testing.expect(t, slice.equal(gct_loaded(lg), gct_around({0, 0}, 1)), "3 x 3 around (0, 0)")
	testing.expect_value(t, lg.loadedChunks, 9)
	testing.expect_value(t, len(ev.in_), 9)
	testing.expect(t, tm.unbounded, "the map is endless")
	testing.expect_value(t, lg.progress, 1)
	coins0, bodies0 := gct_count(scene, tm)
	testing.expect_value(t, bodies0, 9)
	testing.expect(t, coins0 > 0, "coins placed")
	// The map's cells are the level's: chunk (-1, -1)'s against a window.
	g, _ := Gen_LoadFile(ctx, "levels/world.levelgen.json", context.temp_allocator)
	info := Gen_ChunkInfo(&g, context.temp_allocator)
	area, _ := Gen_GenerateWindow(&g, lg.world.seed, {-16, -16}, {48, 48}, info.apron, 0, context.temp_allocator)
	d := 0
	for y in 0 ..< 48 do for x in 0 ..< 48 do if TileMapNode_Get(tm, x - 16, y - 16) != area.tiles[y * 48 + x] do d += 1
	testing.expectf(t, d == 0, "the 3 x 3 chunks are the level's cells (%d differ)", d)

	// Far to the right: chunk (3, 0). Those more than 2 away go.
	cam.position = {3 * 16 * 16 + 5 * 16, 5 * 16}
	Node_SetGlobalPositions(scene.manager, scene.rootNode)
	slow2 := gct_settle(lg, scene, ctx)
	ProcessNodeQueues(scene.manager, ctx)
	loaded := gct_loaded(lg)
	for c in gct_around({3, 0}, 1) do testing.expectf(t, slice.contains(loaded, c), "%v in", c)
	for c in loaded do testing.expectf(t, max(abs(c.x - 3), abs(c.y)) <= 2, "%v near", c)
	testing.expect(t, !LevelGeneratorNode_ChunkLoaded(lg, {0, 0}) && !LevelGeneratorNode_ChunkLoaded(lg, {-1, 1}), "the far ones went")
	testing.expect_value(t, len(ev.in_) - len(ev.out), len(loaded))
	testing.expect_value(t, TileMapNode_Get(tm, -16, -16) == -1 && TileMapNode_Get(tm, 5, 5) == -1, true)
	lo, hi := TileMapNode_Extent(tm)
	testing.expectf(t, (hi.x - lo.x) <= 5 * 16 && (hi.y - lo.y) <= 3 * 16, "the storage follows (%v .. %v)", lo, hi)
	_, bodies1 := gct_count(scene, tm)
	testing.expect_value(t, bodies1, len(loaded))

	// Back: the same chunks, the same coins - nothing left over.
	cam.position = {5 * 16, 5 * 16}
	Node_SetGlobalPositions(scene.manager, scene.rootNode)
	gct_settle(lg, scene, ctx)
	// (Settled: then the chunks 2 away have gone too.)
	LevelGeneratorNode_Update(lg, ctx, 0.016)
	ProcessNodeQueues(scene.manager, ctx)
	for c in gct_loaded(lg) do testing.expectf(t, max(abs(c.x), abs(c.y)) <= 2, "%v near the start", c)
	coins2, _ := gct_count(scene, tm)
	inner := 0
	for ch in GetChildrenTemp(scene.manager, tm) do if ch != nil && !ch.removing && ch.name == "Coin" {
		c := Gen_ChunkOf(TileMapNode_CellAt(tm, ch.position), 16)
		if max(abs(c.x), abs(c.y)) <= 1 do inner += 1
	}
	testing.expectf(t, inner == coins0, "the same coins around the start (%d, then %d; %d in all)", coins0, inner, coins2)
	d = 0
	for y in 0 ..< 48 do for x in 0 ..< 48 do if TileMapNode_Get(tm, x - 16, y - 16) != area.tiles[y * 48 + x] do d += 1
	testing.expectf(t, d == 0, "the same cells again (%d differ)", d)
	fmt.printfln("chunks: slowest update while loading %v (first area), %v (moving)", slow1, slow2)

	// Generating again (another seed) replaces it all; then not chunked.
	ok, why := LevelGeneratorNode_Generate(lg, ctx, 99)
	testing.expectf(t, ok, "again: %s", why)
	gct_settle(lg, scene, ctx)
	ProcessNodeQueues(scene.manager, ctx)
	testing.expect_value(t, lg.loadedChunks, 9)
	_, b3 := gct_count(scene, tm)
	testing.expect_value(t, b3, 9)
	lg.chunked, lg.background = false, false
	LevelGeneratorNode_Generate(lg, ctx, 5)
	ProcessNodeQueues(scene.manager, ctx)
	testing.expect(t, lg.world == nil && !tm.unbounded && tm.mapSize == {64, 64}, "a plain level again")
}

@(test)
test_level_gen_chunks_at_once_and_lua :: proc(t: ^testing.T) {
	game, scene := gct_game()
	defer os.remove_all(GCT_DIR)
	defer game->terminate()
	ctx := &game.gameContext
	lg := LevelGeneratorNode_Create(scene, "Gen")
	lg.gameContext = ctx
	lg.generator = strings.clone("levels/rooms.levelgen.json", lg.allocator)
	lg.generateOnReady = false
	lg.chunked, lg.chunkSize, lg.chunkRadius = true, 32, 0
	tm := cast(^TileMapNode)Node_CreateByTypeName(scene, "TileMapNode", lg)
	tm.name = "Ground"
	tm.gameContext = ctx
	ProcessNodeQueues(scene.manager, ctx)
	LevelGeneratorNode_Update(lg, ctx, 0.016)
	// Background off: the camera's chunk (no camera: (0, 0)) at once.
	ok, why := LevelGeneratorNode_Generate(lg, ctx, 3)
	testing.expectf(t, ok, "%s", why)
	testing.expect(t, LevelGeneratorNode_ChunkLoaded(lg, {0, 0}) && lg.loadedChunks == 1 && lg.progress == 1, "in at once")
	testing.expect(t, lg.world.unsafe == 1, "rooms: not chunk-safe (warned)")
	// Lua: the properties, the events (a Vec2), the chunk helpers.
	L := game.scriptManager.L
	run :: proc(t: ^testing.T, L: ^lua.State, code: string) {
		ok := lua.L_dostring(L, strings.clone_to_cstring(code, context.temp_allocator))
		testing.expectf(t, ok == 0, "lua: %s", lua.tostring(L, -1) if ok != 0 else "")
	}
	num :: proc(L: ^lua.State, name: cstring) -> f64 {
		lua.getglobal(L, name)
		defer lua.pop(L, 1)
		return f64(lua.tonumber(L, -1))
	}
	run(t, L, `
local gen = Scene.find_node("Gen")
got = {}
gen:connect("chunk_generated", function(c) got[#got + 1] = c end)
size, radius, chunked = gen.chunk_size, gen.chunk_radius, gen.chunked and 1 or 0
gen.chunk_radius = 1
gen:levelgen_generate(4)
n_got = #got
first_x, first_y = got[1].x, got[1].y
n_loaded = #gen:levelgen_loaded_chunks()
loaded_prop = gen.loaded_chunks
corner = gen:levelgen_is_chunk_loaded(-1, -1) and 1 or 0
far = gen:levelgen_is_chunk_loaded(5, 5) and 1 or 0
cx, cy = gen:levelgen_chunk_at(-1, 33 * 32)
`)
	testing.expect_value(t, num(L, "size"), 32)
	testing.expect_value(t, num(L, "radius"), 0)
	testing.expect_value(t, num(L, "chunked"), 1)
	testing.expect_value(t, num(L, "n_got"), 9)
	testing.expect(t, num(L, "first_x") == 0 && num(L, "first_y") == 0, "nearest first: the camera's")
	testing.expect_value(t, num(L, "n_loaded"), 9)
	testing.expect_value(t, num(L, "loaded_prop"), 9)
	testing.expect_value(t, num(L, "corner"), 1)
	testing.expect_value(t, num(L, "far"), 0)
	testing.expect(t, num(L, "cx") == -1 && num(L, "cy") == 1, "chunk_at: (-1, 1)")
}

// The main thread's part of a 32 x 32 chunk: its tiles and colliders in,
// later out. Printed; the bound is loose (CI machines are slow).
@(test)
test_level_gen_chunk_apply_time :: proc(t: ^testing.T) {
	game, scene := gct_game()
	defer os.remove_all(GCT_DIR)
	defer game->terminate()
	ctx := &game.gameContext
	tm := TileMapNode_Create(scene, "Map")
	tm.gameContext = ctx
	tm.tileSize = {16, 16}
	tm.unbounded = true
	ProcessNodeQueues(scene.manager, ctx)
	g, _ := Gen_LoadFile(ctx, "levels/world.levelgen.json", context.temp_allocator)
	info := Gen_ChunkInfo(&g, context.temp_allocator)
	worst, total, tiles, out: time.Duration
	N :: 25
	for i in 0 ..< N {
		c := [2]int{i % 5 - 2, i / 5 - 2}
		r, _ := Gen_GenerateChunk(&g, 1, c, 32, info.apron, context.temp_allocator)
		s := time.tick_now()
		TileMapNode_FitStorage(tm, {-64, -64}, {96, 96})
		TileMapNode_SetBlock(tm, c * 32, {32, 32}, r.tiles)
		tiles += time.tick_since(s)
		body := TileMapNode_BuildCollidersIn(tm, c * 32, c * 32 + 32, ctx)
		d := time.tick_since(s)
		worst = max(worst, d)
		total += d
		testing.expect(t, body != nil && len(body.shapes) > 0, "colliders")
		s = time.tick_now()
		TileMapNode_SetBlock(tm, c * 32, {32, 32}, nil)
		RemoveNode(scene.manager, body)
		ProcessNodeQueues(scene.manager, ctx)
		out += time.tick_since(s)
		TileMapNode_SetBlock(tm, c * 32, {32, 32}, r.tiles) // (back: the storage keeps growing over the 5 x 5)
	}
	fmt.printfln("chunk apply (32 x 32): mean %v (tiles %v, the rest colliders), worst %v; taking one out %v", total / N, tiles / N, worst, out / N)
	testing.expectf(t, total / N < 5 * time.Millisecond, "well under a frame (mean %v)", total / N)
}
