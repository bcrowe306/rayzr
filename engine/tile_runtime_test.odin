package engine

import "core:strings"
import "core:testing"
import lua "lua54"

// Runtime tiles: Retile on Edit / set_terrain, tile data and cells' own
// values, damage and the events, the tileset file's fields.

@(private = "file")
trt_setup :: proc() -> (^Game, ^Scene, ^TileMapNode) {
	game := new(Game)
	InitializeGame(game)
	scene := game->createScene("trt", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	tm := cast(^TileMapNode)Node_CreateByTypeName(scene, "TileMapNode")
	tm.name = "Ground"
	tm.gameContext = &game.gameContext
	tm.tileSize = {16, 16}
	tm.mapSize = {10, 5}
	TileMapNode_Layout(tm)
	// An edges terrain: pattern m -> tile m + 1 (tiles 1..16), and data.
	a := Engine_HeapAllocator()
	ts := new(Tile_Terrains, a)
	ts^, _ = Terrains_Parse(transmute([]u8)string(`{"terrains": [], "fields": [
		{"name": "health", "type": "number", "default": 0},
		{"name": "breakable", "type": "bool", "default": false},
		{"name": "sound", "type": "string", "default": "thud"}],
		"data": [[11, {"health": 3, "breakable": true}], [9, {"health": 2, "sound": "crack"}]]}`), a)
	t := Terrains_Add(ts, "Rock")
	t.kind = .Edges
	for m in 0 ..< 16 do append(&t.tiles[m], i32(m + 1))
	tm.sidecar = ts
	ProcessNodeQueues(scene.manager, &game.gameContext)
	return game, scene, tm
}

@(test)
test_tile_runtime_retile_and_terrain :: proc(t: ^testing.T) {
	game, _, tm := trt_setup()
	defer game->terminate()
	testing.expect(t, tm.retileOnEdit, "new maps retile")
	// A row of three Rock cells: W end (E side: 2 -> tile 3), middle (E|W 10 -> 11), E end (W 8 -> 9).
	for x in 2 ..< 5 do TileMapNode_SetTerrain(tm, {x, 2}, "Rock")
	testing.expect_value(t, TileMapNode_Get(tm, 2, 2), i32(3))
	testing.expect_value(t, TileMapNode_Get(tm, 3, 2), i32(11))
	testing.expect_value(t, TileMapNode_Get(tm, 4, 2), i32(9))

	// Dig the east end: the middle loses its east side (W only: 8 -> 9).
	testing.expect(t, TileMapNode_EditTile(tm, {4, 2}, -1), "dug")
	testing.expect_value(t, TileMapNode_Get(tm, 3, 2), i32(9))
	// Off: a raw edit, the neighbour stays.
	tm.retileOnEdit = false
	TileMapNode_EditTile(tm, {3, 2}, -1)
	testing.expect_value(t, TileMapNode_Get(tm, 2, 2), i32(3))
	tm.retileOnEdit = true
	// set_terrain "" empties and re-picks: the west end alone (0 -> 1).
	TileMapNode_SetTerrain(tm, {3, 2}, "Rock")
	testing.expect(t, TileMapNode_SetTerrain(tm, {3, 2}, ""), "emptied")
	testing.expect_value(t, TileMapNode_Get(tm, 2, 2), i32(1))
	testing.expect(t, !TileMapNode_SetTerrain(tm, {3, 2}, "Lava"), "no such terrain")
	testing.expect(t, tm.collidersDirty, "the colliders follow")
}

@(test)
test_tile_runtime_data_and_damage :: proc(t: ^testing.T) {
	game, _, tm := trt_setup()
	defer game->terminate()
	TileMapNode_Set(tm, 1, 1, 11)
	TileMapNode_Set(tm, 2, 1, 9)
	TileMapNode_Set(tm, 3, 1, 5) // (no values of its own: the defaults)
	v, ok := TileMapNode_CellData(tm, {1, 1}, "health")
	testing.expect(t, ok && v.(f64) == 3, "the tile's health")
	v, ok = TileMapNode_CellData(tm, {3, 1}, "sound")
	testing.expect(t, ok && v.(string) == "thud", "a default")
	_, ok = TileMapNode_CellData(tm, {1, 1}, "colour")
	testing.expect(t, !ok, "no such field")
	_, ok = TileMapNode_CellData(tm, {7, 4}, "health")
	testing.expect(t, !ok, "an empty cell has no data")

	// A cell's own value until its tile changes.
	TileMapNode_SetCellData(tm, {3, 1}, "sound", "clink")
	v, _ = TileMapNode_CellData(tm, {3, 1}, "sound")
	testing.expect_value(t, v.(string), "clink")
	TileMapNode_Set(tm, 3, 1, 6)
	v, _ = TileMapNode_CellData(tm, {3, 1}, "sound")
	testing.expect_value(t, v.(string), "thud")

	// Damage: 3 -> 2 (kept per cell), then destroyed.
	h, destroyed, dok := TileMapNode_Damage(tm, {1, 1}, 1)
	testing.expect(t, dok && h == 2 && !destroyed, "damaged")
	v, _ = TileMapNode_CellData(tm, {1, 1}, "health")
	testing.expect_value(t, v.(f64), 2)
	_, destroyed, _ = TileMapNode_Damage(tm, {1, 1}, 5)
	testing.expect(t, destroyed && TileMapNode_Get(tm, 1, 1) == -1, "destroyed at 0")
	_, _, dok = TileMapNode_Damage(tm, {1, 1}, 1)
	testing.expect(t, !dok, "an empty cell takes no damage")
	_, _, dok = TileMapNode_Damage(tm, {3, 1}, 1)
	testing.expect(t, dok, "a 0-health tile: damaged (and destroyed)")
	testing.expect_value(t, TileMapNode_Get(tm, 3, 1), i32(-1))
}

@(test)
test_tile_runtime_lua_and_events :: proc(t: ^testing.T) {
	game, scene, tm := trt_setup()
	defer game->terminate()
	TileMapNode_Set(tm, 1, 1, 11)
	TileMapNode_Set(tm, 2, 1, 9)
	_ = scene
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local map = Scene.find_node("Ground")
local log = {}
map:connect("tile_changed", function(c) log[#log + 1] = string.format("changed %d,%d %d>%d", c.x, c.y, c.old, c.new) end)
map:connect("tile_damaged", function(h) log[#log + 1] = string.format("damaged %d left %g", h.tile, h.health) end)
map:connect("tile_destroyed", function(h) log[#log + 1] = string.format("destroyed %d,%d", h.x, h.y) end)
local h1, d1 = map:tilemap_damage(1, 1, 1)
local h2, d2 = map:tilemap_damage(1, 1, 2)
map:tilemap_set_data(2, 1, "health", 7)
local own = map:tilemap_get_data(2, 1, "health")
local typed = map:tilemap_tile_data(9, "sound")
map:tilemap_set_data(2, 1, "health", "lots") -- (wrong type: warned, ignored)
local still = map:tilemap_get_data(2, 1, "health")
local ok = map:tilemap_set_terrain(5, 3, "Rock")
local names = map:tilemap_terrain_names()
local x, y, tile = map:tilemap_cell_hit({point_x = 5 * 16 + 8, point_y = 3 * 16 + 1, normal_x = 0, normal_y = -1})
probe = string.format("%g %s %g %s | %g %s %g | %s %s | %d %d %d", h1, tostring(d1), h2, tostring(d2), own, typed, still,
	tostring(ok), names[1], x, y, tile)
probe_log = table.concat(log, "; ")
`) == 0
	testing.expect(t, ok, "Lua ran")
	if !ok {
		testing.expectf(t, false, "%s", string(lua.tostring(L, -1)))
		return
	}
	lua.getglobal(L, "probe")
	testing.expect_value(t, string(lua.tostring(L, -1)), "2 false 0 true | 7 crack 7 | true Rock | 5 3 1")
	lua.pop(L, 1)
	lua.getglobal(L, "probe_log")
	log := string(lua.tostring(L, -1))
	testing.expectf(t, strings.contains(log, "damaged 11 left 2") && strings.contains(log, "changed 1,1 11>-1") && strings.contains(log, "destroyed 1,1") && strings.contains(log, "changed 5,3 -1>1"), "events: %s", log)
	lua.pop(L, 1)
}

@(test)
test_tile_data_file_round_trip :: proc(t: ^testing.T) {
	src := `{"terrains": [], "fields": [{"name": "health", "type": "number", "default": 3}, {"name": "kind", "type": "string", "default": "rock"}],
		"data": [[4, {"health": 9}], [2, {"kind": "glass", "health": 1}]]}`
	ts, err := Terrains_Parse(transmute([]u8)string(src), context.temp_allocator)
	testing.expect_value(t, err, "")
	v, ok := TileData_Get(&ts, 2, "kind")
	testing.expect(t, ok && v.(string) == "glass", "a tile's value")
	v, _ = TileData_Get(&ts, 7, "health")
	testing.expect_value(t, v.(f64), 3)
	testing.expect(t, TileData_AddField(&ts, "breakable", .Bool), "a new field")
	testing.expect(t, !TileData_AddField(&ts, "health", .Number), "a taken name")
	TileData_Set(&ts, 4, "breakable", true)
	testing.expect(t, TileData_RenameField(&ts, "kind", "material"), "renamed")
	TileData_Clear(&ts, 4, "health")
	text := Terrains_Serialize(&ts, context.temp_allocator)
	ts2, _ := Terrains_Parse(transmute([]u8)text, context.temp_allocator)
	v, _ = TileData_Get(&ts2, 2, "material")
	testing.expect(t, v.(string) == "glass", "renamed values kept")
	v, _ = TileData_Get(&ts2, 4, "health")
	testing.expect_value(t, v.(f64), 3)
	v, _ = TileData_Get(&ts2, 4, "breakable")
	testing.expect(t, v.(bool), "a bool saved")
	TileData_RemoveField(&ts2, "material")
	testing.expect_value(t, TileData_FieldIndex(&ts2, "material"), -1)
	testing.expect(t, !strings.contains(Terrains_Serialize(&ts2, context.temp_allocator), "glass"), "removed with its values")
}
