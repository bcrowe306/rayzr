package engine

import "core:fmt"
import os "osx"
import "core:strings"
import "core:testing"
import "core:time"
import lua "lua54"

// Level generator runtime and integrations (#171, part 3): progress (the
// fraction, its events, retries), outputs that write components on a tile
// map's component layer, navigation baked again after a level, and the Lua
// side of the progress.

@(private = "file")
LGR_DIR :: "test_level_gen_runtime"

@(private = "file")
lgr_game :: proc() -> (^Game, ^Scene) {
	_ = os.make_directory_all(LGR_DIR + "/levels")
	_ = os.make_directory_all(LGR_DIR + "/components")
	_ = os.write_entire_file(LGR_DIR + "/levels/cave.levelgen.json", transmute([]u8)string(`{"size": [96, 96], "seed": 5, "nodes": [
		{"id": 1, "type": "random_fill", "params": {"density": 0.5}},
		{"id": 2, "type": "cellular", "inputs": {"in": 1}, "params": {"iterations": 4}},
		{"id": 3, "type": "blur", "inputs": {"in": 2}, "params": {"radius": 1}},
		{"id": 4, "type": "threshold", "inputs": {"in": 3}},
		{"id": 5, "type": "noise", "params": {"scale": 8}},
		{"id": 6, "type": "combine", "inputs": {"a": 4, "b": 5}, "params": {"op": "max"}},
		{"id": 7, "type": "tile_output", "inputs": {"in": 6}, "rules": [{"min": 0.5, "max": 1, "tile": 1}]}]}`))
	// Never playable: every seed is refused.
	_ = os.write_entire_file(LGR_DIR + "/levels/refused.levelgen.json", transmute([]u8)string(`{"size": [16, 16], "seed": 5, "nodes": [
		{"id": 1, "type": "random_fill", "params": {"density": 0.5}},
		{"id": 2, "type": "blur", "inputs": {"in": 1}},
		{"id": 3, "type": "check", "inputs": {"in": 2}, "params": {"min_open": 1}},
		{"id": 4, "type": "tile_output", "inputs": {"in": 3}, "rules": [{"min": 0.5, "max": 1, "tile": 1}]}]}`))
	// Ground on the bottom row (tiles); coins on the row above it, on the
	// main map's component layer; 2 x 2 crates over the top-left 4 x 2 cells
	// on the Deco map's.
	_ = os.write_entire_file(LGR_DIR + "/levels/props.levelgen.json", transmute([]u8)string(`{"size": [8, 4], "seed": 1, "nodes": [
		{"id": 1, "type": "rect", "params": {"x": 0, "y": 3, "w": 8, "h": 1}},
		{"id": 2, "type": "tile_output", "inputs": {"in": 1}, "rules": [{"min": 0.5, "max": 1, "tile": 2}]},
		{"id": 3, "type": "surface", "inputs": {"in": 1}},
		{"id": 4, "type": "tile_output", "inputs": {"in": 3}, "params": {"writes": "components"},
		 "rules": [{"min": 0.5, "max": 1, "tiles": [], "component": "components/coin.component.json"}]},
		{"id": 5, "type": "rect", "params": {"x": 0, "y": 0, "w": 4, "h": 2}},
		{"id": 6, "type": "tile_output", "inputs": {"in": 5}, "params": {"writes": "components"}, "layer": "Deco",
		 "rules": [{"min": 0.5, "max": 1, "component": "components/crate.component.json"}]}]}`))
	// Walls around a 12 x 8 room.
	_ = os.write_entire_file(LGR_DIR + "/levels/room.levelgen.json", transmute([]u8)string(`{"size": [12, 8], "seed": 1, "nodes": [
		{"id": 1, "type": "border", "params": {"width": 1}},
		{"id": 2, "type": "tile_output", "inputs": {"in": 1}, "rules": [{"min": 0.5, "max": 1, "tile": 1}]}]}`))
	_ = os.write_entire_file(LGR_DIR + "/components/coin.component.json", transmute([]u8)string(`{"type": "Node", "name": "Coin"}`))
	_ = os.write_entire_file(LGR_DIR + "/components/crate.component.json", transmute([]u8)string(`{"type": "StaticBodyNode", "name": "Crate", "physics": {"shape": {"type": "box", "size": [32, 32]}}}`))
	game := new(Game)
	InitializeGame(game)
	AssetManager_SetProjectDir(&game.assetManager, LGR_DIR)
	scene := game->createScene("lgr", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.gameContext.scene = scene
	game.state = .Running
	return game, scene
}

// A generator (not generating on ready) with a TileMap child "Ground".
@(private = "file")
lgr_node :: proc(scene: ^Scene, ctx: ^GameContext, file: string) -> (^LevelGeneratorNode, ^TileMapNode) {
	lg := LevelGeneratorNode_Create(scene, "Gen")
	lg.gameContext = ctx
	lg.generator = strings.clone(file, lg.allocator)
	lg.generateOnReady = false
	tm := cast(^TileMapNode)Node_CreateByTypeName(scene, "TileMapNode", lg)
	tm.name = "Ground"
	tm.gameContext = ctx
	tm.tileSize = {16, 16}
	ProcessNodeQueues(scene.manager, ctx)
	LevelGeneratorNode_Update(lg, ctx, 0.016)
	return lg, tm
}

@(private = "file")
lgr_record :: proc(source: rawptr, value: EventValue, ctx: ^GameContext, user: rawptr) {
	append(cast(^[dynamic]f64)user, value.(f64))
}

@(private = "file")
lgr_monotonic :: proc(values: []f64) -> bool {
	for i in 1 ..< len(values) do if values[i] < values[i - 1] do return false
	return true
}

// lgr_wait updates `lg` until its background generation is in (or 20 s
// pass). A deadline, not a count of short sleeps: Windows rounds a sleep
// under a millisecond down to almost nothing.
@(private = "file")
lgr_wait :: proc(lg: ^LevelGeneratorNode, ctx: ^GameContext) {
	start := time.tick_now()
	for LevelGeneratorNode_Generating(lg) && time.tick_since(start) < 20 * time.Second {
		time.sleep(time.Millisecond)
		LevelGeneratorNode_Update(lg, ctx, 0.016)
	}
}

@(test)
test_level_gen_progress :: proc(t: ^testing.T) {
	game, scene := lgr_game()
	defer os.remove_all(LGR_DIR)
	defer game->terminate()
	ctx := &game.gameContext

	// The fraction itself: nodes computed of those needed, an attempt that
	// may be retried filling 90% of what is left, the last one all of it.
	g, err := Gen_LoadFile(ctx, "levels/cave.levelgen.json")
	testing.expect_value(t, err, "")
	testing.expect_value(t, Gen_NeededNodes(&g), 7)
	p: Gen_Progress
	Gen_ProgressAttempt(&p, Gen_NeededNodes(&g), false)
	r, gerr := Gen_Generate(&g, 3, context.temp_allocator, &p)
	testing.expect_value(t, gerr, "")
	testing.expectf(t, abs(Gen_ProgressValue(&p) - 0.9) < 1e-5, "a first of several attempts fills 90%% (%v)", Gen_ProgressValue(&p))
	Gen_ResultDestroy(&r, context.temp_allocator)
	Gen_ProgressAttempt(&p, Gen_NeededNodes(&g), true)
	testing.expect(t, abs(p.base - 0.9) < 1e-5, "the next carries on from there")
	r, _ = Gen_Generate(&g, 3, context.temp_allocator, &p)
	testing.expect_value(t, Gen_ProgressValue(&p), 1)
	Gen_ResultDestroy(&r, context.temp_allocator)
	Gen_GraphDestroy(&g)

	// In the background: "generation_progress" from 0 to 1, only growing,
	// a bounded number of times; `progress` 1 when the level is in.
	lg, tm := lgr_node(scene, ctx, "levels/cave.levelgen.json")
	values := make([dynamic]f64, context.temp_allocator)
	lg.onProgress->subscribe(lgr_record, &values)
	lg.background = true
	ok, why := LevelGeneratorNode_Generate(lg, ctx, 9)
	testing.expectf(t, ok, "started: %s", why)
	testing.expect(t, len(values) == 1 && values[0] == 0 && lg.progress == 0, "0 at the start")
	lgr_wait(lg, ctx)
	testing.expect(t, !LevelGeneratorNode_Generating(lg) && tm.mapSize == {96, 96}, "done, the level in")
	testing.expectf(t, lgr_monotonic(values[:]) && values[len(values) - 1] == 1, "0 .. 1, growing: %v", values[:])
	testing.expectf(t, len(values) >= 2 && len(values) <= 102, "a bounded number of events (%d)", len(values))
	for i in 1 ..< len(values) - 1 do testing.expectf(t, values[i] - values[i - 1] >= 0.01, "each moved 1%% or more (%v)", values[:])
	testing.expect_value(t, lg.progress, 1)

	// At once: 0 and 1.
	clear(&values)
	lg.background = false
	LevelGeneratorNode_Generate(lg, ctx, 4)
	testing.expectf(t, len(values) == 2 && values[0] == 0 && values[1] == 1, "at once: %v", values[:])

	// Retries count on: every seed refused - it grows, never reaches 1.
	delete(lg.generator, lg.allocator)
	lg.generator = strings.clone("levels/refused.levelgen.json", lg.allocator)
	lg.randomSeed, lg.attempts = true, 3
	clear(&values)
	ok, why = LevelGeneratorNode_Generate(lg, ctx)
	testing.expect(t, !ok && strings.contains(why, "3 seeds tried"), "refused")
	testing.expectf(t, lg.progress > 0.8 && lg.progress < 1, "the attempts carried it on (%v)", lg.progress)
	testing.expect(t, lgr_monotonic(values[:]), "growing")

	// Lua: the property and the event (at once, then in the background).
	delete(lg.generator, lg.allocator)
	lg.generator = strings.clone("levels/cave.levelgen.json", lg.allocator)
	lg.randomSeed = false
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
seen = {}
gen:connect("generation_progress", function(p) seen[#seen + 1] = p end)
before = gen.progress
gen:levelgen_generate(6)
after = gen.progress
count = #seen
gen.background = true
gen:levelgen_generate(8)
started = gen:get_property("progress")
`)
	testing.expect_value(t, num(L, "after"), 1)
	testing.expect_value(t, num(L, "count"), 2)
	testing.expect_value(t, num(L, "started"), 0)
	lgr_wait(lg, ctx)
	run(t, L, `
local gen = Scene.find_node("Gen")
last = seen[#seen]
grew = true
for i = count + 2, #seen do if seen[i] < seen[i - 1] then grew = false end end -- (the background run, after the first two)
bg_progress = gen.progress
total = #seen
`)
	testing.expect_value(t, num(L, "last"), 1)
	testing.expect_value(t, num(L, "bg_progress"), 1)
	lua.getglobal(L, "grew")
	testing.expect(t, bool(lua.toboolean(L, -1)), "growing in Lua")
	lua.pop(L, 1)
	testing.expect(t, num(L, "total") >= 4 && num(L, "total") <= 2 + 102, "bounded in Lua")
}

@(private = "file")
lgr_components :: proc(scene: ^Scene, tm: ^TileMapNode, name: string) -> (n: int, cells: [dynamic][2]int) {
	cells = make([dynamic][2]int, context.temp_allocator)
	for tc in TileMapNode_Components(tm) do if tc.node.name == name || strings.has_prefix(tc.node.name, fmt.tprintf("%s_", strings.to_lower(name, context.temp_allocator))) {
		n += 1
		append(&cells, tc.cell)
	}
	return
}

@(test)
test_level_gen_component_layers :: proc(t: ^testing.T) {
	game, scene := lgr_game()
	defer os.remove_all(LGR_DIR)
	defer game->terminate()
	ctx := &game.gameContext

	// The file: `writes` saved only when it isn't tiles; the main output is
	// the one writing tiles though outputs writing components come later.
	g, err := Gen_LoadFile(ctx, "levels/props.levelgen.json")
	testing.expect_value(t, err, "")
	testing.expect_value(t, Gen_OutputNode(&g).id, 2)
	text := Gen_GraphSerialize(&g, context.temp_allocator)
	testing.expectf(t, strings.count(text, `"writes": "components"`) == 2 && strings.contains(text, `"component": "components/crate.component.json"`), "saved: %s", text)
	back, perr := Gen_GraphParse(transmute([]u8)text, context.temp_allocator)
	testing.expect(t, perr == "" && Gen_WritesComponents(Gen_FindNode(&back, 4)) && !Gen_WritesComponents(Gen_FindNode(&back, 2)), "read back")
	testing.expect_value(t, Gen_FindNode(&back, 6).rules[0].component, "components/crate.component.json")
	dup := Gen_DuplicateNode(&g, 6)
	testing.expect_value(t, dup.rules[0].component, "components/crate.component.json")
	plain, _ := Gen_GraphParse(transmute([]u8)string(`{"nodes": [{"id": 1, "type": "tile_output"}]}`), context.temp_allocator)
	testing.expect(t, !strings.contains(Gen_GraphSerialize(&plain, context.temp_allocator), "writes"), "tiles: not saved")
	res, rerr := Gen_Generate(&g, 0, context.temp_allocator)
	testing.expect(t, rerr == "" && len(res.components) == 8 + 8, "8 coin cells, 8 crate cells")
	Gen_ResultDestroy(&res, context.temp_allocator)
	Gen_GraphDestroy(&g)

	// Into the maps: Ground gets the tiles and the coins (a painted coin
	// where one goes is replaced); Deco keeps its tiles and gets 2 x 2
	// crates where they fit.
	lg, ground := lgr_node(scene, ctx, "levels/props.levelgen.json")
	deco := cast(^TileMapNode)Node_CreateByTypeName(scene, "TileMapNode", lg)
	deco.name = "Deco"
	deco.gameContext = ctx
	deco.tileSize = {16, 16}
	deco.mapSize = {8, 4}
	ProcessNodeQueues(scene.manager, ctx)
	TileMapNode_Set(deco, 6, 3, 7)
	ground.mapSize = {8, 4}
	painted := TileMapNode_PlaceComponent(ground, {0, 2}, "components/coin.component.json")
	testing.expect(t, painted != nil, "a coin painted by hand")
	ok, why := LevelGeneratorNode_Generate(lg, ctx)
	testing.expectf(t, ok, "generated: %s", why)
	testing.expect(t, TileMapNode_Get(ground, 0, 3) == 2 && TileMapNode_Get(ground, 0, 2) == -1, "the ground tiles")
	coins, coinCells := lgr_components(scene, ground, "Coin")
	testing.expectf(t, coins == 8, "a coin on each of the 8 cells (%d)", coins)
	for c in coinCells do testing.expect_value(t, c.y, 2)
	for tc in TileMapNode_Components(ground) do testing.expect(t, Node_HasTag(tc.node, GEN_ENTITY_TAG), "tagged: replaced next time")
	crates, crateCells := lgr_components(scene, deco, "Crate")
	testing.expectf(t, crates == 2, "two 2 x 2 crates over the 4 x 2 area (%d: %v)", crates, crateCells[:])
	for tc in TileMapNode_Components(deco) do testing.expect_value(t, tc.size, [2]int{2, 2})
	testing.expect(t, TileMapNode_Get(deco, 6, 3) == 7, "Deco's tiles stay")
	testing.expect(t, TileMapNode_ComponentAt(deco, {3, 1}) != nil && TileMapNode_ComponentAt(deco, {4, 0}) == nil, "the crates cover their footprints")

	// Again: replaced, not added.
	LevelGeneratorNode_Generate(lg, ctx)
	coins, _ = lgr_components(scene, ground, "Coin")
	crates, _ = lgr_components(scene, deco, "Crate")
	testing.expect(t, coins == 8 && crates == 2, "replaced")

	// A missing layer map: reported, the rest written.
	RemoveNode(scene.manager, deco)
	ProcessNodeQueues(scene.manager, ctx)
	failed := ""
	lg.onFailed->subscribe(proc(source: rawptr, value: EventValue, ctx: ^GameContext, user: rawptr) {
		(cast(^string)user)^ = strings.clone(value.(string), context.temp_allocator)
	}, &failed)
	ok, _ = LevelGeneratorNode_Generate(lg, ctx)
	testing.expectf(t, !ok && strings.contains(failed, `"Deco"`), "no Deco map: %s", failed)
	coins, _ = lgr_components(scene, ground, "Coin")
	testing.expect_value(t, coins, 8)
}

@(test)
test_level_gen_rebake_navigation :: proc(t: ^testing.T) {
	game, scene := lgr_game()
	defer os.remove_all(LGR_DIR)
	defer game->terminate()
	ctx := &game.gameContext

	lg, tm := lgr_node(scene, ctx, "levels/room.levelgen.json")
	tm.solid = true
	region := NavigationRegionNode_Create(scene, "Nav")
	region.size, region.cellSize = {192, 128}, 16
	region.usePhysics, region.useLdtk = false, false
	region.gameContext = ctx
	ProcessNodeQueues(scene.manager, ctx)
	Node_SetGlobalPositions(scene.manager, scene.rootNode)
	NavRegion_Bake(region, ctx) // (the empty map: all open)
	blocked :: proc(r: ^NavigationRegionNode, c: [2]int) -> bool {return r.blocked[c.y * r.cells.x + c.x] != 0}
	testing.expect(t, region.cells == {12, 8} && !blocked(region, {0, 0}), "baked before the level: open")

	// Off: the region keeps its old cells.
	LevelGeneratorNode_Generate(lg, ctx)
	testing.expect(t, TileMapNode_Get(tm, 0, 0) == 1 && !blocked(region, {0, 0}), "not baked again")

	// On: baked again before "generated" - the walls block, the room is open.
	lg.rebakeNavigation = true
	Seen :: struct {region: ^NavigationRegionNode, wall, room: bool}
	seen := Seen{region = region}
	lg.onGenerated->subscribe(proc(source: rawptr, value: EventValue, ctx: ^GameContext, user: rawptr) {
		s := cast(^Seen)user
		s.wall = s.region.blocked[0] != 0
		s.room = s.region.blocked[4 * s.region.cells.x + 5] == 0
	}, &seen)
	version := region.bakeVersion
	ok, why := LevelGeneratorNode_Generate(lg, ctx)
	testing.expectf(t, ok, "generated: %s", why)
	testing.expect(t, region.bakeVersion > version, "baked again")
	testing.expect(t, seen.wall && seen.room, "before generated: the walls block, the room is open")
	for x in 0 ..< 12 do testing.expect(t, blocked(region, {x, 0}) && blocked(region, {x, 7}), "top and bottom walls")
	for y in 1 ..< 7 do for x in 1 ..< 11 do testing.expect(t, !blocked(region, {x, y}), "the room's floor")
	grid := Nav_GridFor(region)
	testing.expect(t, Nav_FindPath(grid, {40, 40}, {150, 90}) != nil, "a path across the room")
	testing.expect(t, Nav_FindPath(grid, {40, 40}, {8, 8}) == nil || !Nav_Walkable(grid, Nav_CellAt(grid, {8, 8})), "not into the wall")

	// From the background too.
	lg.background = true
	region.bakeVersion = 0
	LevelGeneratorNode_Generate(lg, ctx, 2)
	lgr_wait(lg, ctx)
	testing.expect(t, region.bakeVersion > 0 && blocked(region, {0, 0}), "baked after a background level")
}
