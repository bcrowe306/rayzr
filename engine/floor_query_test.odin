package engine

import "core:testing"
import lua "lua54"

// character_get_floor / body_get_floor: what a Character Mover and a Dynamic
// Body stand on (nil in the air), where, its normal and slope; on a TileMap
// the map itself with the cell and tile under the feet.
@(test)
test_get_floor :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("get_floor", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	ctx := &game.gameContext

	ice := StaticBodyNode_Create(scene, "Ice")
	ice.position = {0, 200}
	ice.gameContext = ctx
	StaticBodyNode_AddShape(ice, MakeBoxPhysicsShape(400, 20), ctx) // top at y 190
	tm := cast(^TileMapNode)Node_CreateByTypeName(scene, "TileMapNode")
	tm.name = "Ground"
	tm.position = {600, 0}
	tm.tileSize = {16, 16}
	tm.mapSize = {20, 20}
	TileMapNode_Layout(tm)
	for x in 0 ..< 20 do TileMapNode_Set(tm, x, 12, 3) // top at y 192
	tm.solid = true
	tm.gameContext = ctx

	mover := CharacterMoverNode_Create(scene, "Player")
	mover.enableKeyboardInput = false
	mover.position = {0, 100}
	mover.gameContext = ctx
	mover2 := CharacterMoverNode_Create(scene, "Player2")
	mover2.enableKeyboardInput = false
	mover2.position = {760, 100}
	mover2.gameContext = ctx
	crate := DynamicBodyNode_Create(scene, "Crate")
	crate.position = {120, 120}
	crate.gameContext = ctx
	DynamicBodyNode_AddShape(crate, MakeBoxPhysicsShape(32, 32), ctx)
	crate2 := DynamicBodyNode_Create(scene, "Crate2")
	crate2.position = {700, 120}
	crate2.gameContext = ctx
	DynamicBodyNode_AddShape(crate2, MakeBoxPhysicsShape(32, 32), ctx)
	ProcessNodeQueues(scene.manager, ctx)
	TileMapNode_BuildColliders(tm, ctx)
	ProcessNodeQueues(scene.manager, ctx)

	L := game.scriptManager.L
	run :: proc(t: ^testing.T, L: ^lua.State, code: cstring, loc := #caller_location) {
		if lua.L_dostring(L, code) != 0 {
			testing.expectf(t, false, "Lua: %s", lua.tostring(L, -1), loc = loc)
			lua.pop(L, 1)
		}
	}
	num :: proc(L: ^lua.State, name: cstring) -> f64 {
		lua.getglobal(L, name)
		defer lua.pop(L, 1)
		return f64(lua.tonumber(L, -1))
	}
	str :: proc(L: ^lua.State, name: cstring) -> string {
		lua.getglobal(L, name)
		defer lua.pop(L, 1)
		return string(lua.tostring(L, -1)) if lua.isstring(L, -1) else ""
	}

	// In the air: nil.
	game->run(1.0 / 60)
	run(t, L, `air = Scene.find_node("Player"):character_get_floor() == nil and Scene.find_node("Crate"):body_get_floor() == nil`)
	lua.getglobal(L, "air")
	testing.expect(t, bool(lua.toboolean(L, -1)), "nothing under them while they fall")
	lua.pop(L, 1)

	for _ in 0 ..< 180 do game->run(1.0 / 60)

	// On a body: that node, the contact point on its top, a flat normal.
	run(t, L, `
		local f = Scene.find_node("Player"):character_get_floor()
		m_name = f and f.node:get_name() or ""
		m_y = f and f.point_y or 0
		m_ny = f and f.normal_y or 0
		m_angle = f and f.angle or -1
		local g = Scene.find_node("Crate"):body_get_floor()
		c_name = g and g.node:get_name() or ""
		c_y = g and g.point.y or 0
		c_ny = g and g.normal.y or 0
	`)
	testing.expectf(t, str(L, "m_name") == "Ice", "the mover stands on Ice (%q)", str(L, "m_name"))
	testing.expectf(t, abs(num(L, "m_y") - 190) < 3, "touching Ice's top (y %v)", num(L, "m_y"))
	testing.expectf(t, abs(num(L, "m_ny") + 1) < 0.01 && abs(num(L, "m_angle")) < 1, "flat floor (normal y %v, angle %v)", num(L, "m_ny"), num(L, "m_angle"))
	testing.expectf(t, str(L, "c_name") == "Ice", "the crate rests on Ice (%q)", str(L, "c_name"))
	testing.expectf(t, abs(num(L, "c_y") - 190) < 3, "the crate touches Ice's top (y %v)", num(L, "c_y"))
	testing.expectf(t, abs(num(L, "c_ny") + 1) < 0.01, "the crate's floor points up (%v)", num(L, "c_ny"))

	// On a TileMap: the map (not its collider body), the cell and the tile.
	run(t, L, `
		local f = Scene.find_node("Player2"):character_get_floor()
		t_name = f and f.node:get_name() or ""
		t_cy = f and f.cell_y or -1
		t_tile = f and f.tile or -1
		local g = Scene.find_node("Crate2"):body_get_floor()
		t2_name = g and g.node:get_name() or ""
		t2_tile = g and g.tile or -1
	`)
	testing.expectf(t, str(L, "t_name") == "Ground", "the mover stands on the TileMap (%q)", str(L, "t_name"))
	testing.expectf(t, num(L, "t_cy") == 12 && num(L, "t_tile") == 3, "cell row 12, tile 3 (%v, %v)", num(L, "t_cy"), num(L, "t_tile"))
	testing.expectf(t, str(L, "t2_name") == "Ground" && num(L, "t2_tile") == 3, "the crate on the TileMap, tile 3 (%q, %v)", str(L, "t2_name"), num(L, "t2_tile"))

	// Called on the wrong node type: nil.
	run(t, L, `wrong = Scene.find_node("Crate"):character_get_floor() == nil and Scene.find_node("Player"):body_get_floor() == nil`)
	lua.getglobal(L, "wrong")
	testing.expect(t, bool(lua.toboolean(L, -1)), "nil on the wrong node type")
	lua.pop(L, 1)
}
