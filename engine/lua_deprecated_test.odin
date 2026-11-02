package engine

import "core:testing"
import lua "lua54"

// #327: a deprecated name still works, as its replacement, and warns once
// per call site (only when warnings are on).
@(test)
test_lua_deprecated_aliases :: proc(t: ^testing.T) {
	prev := Lua_WarnDeprecated
	defer Lua_WarnDeprecated = prev
	Lua_WarnDeprecated = true
	Lua_ForgetDeprecationWarnings()
	defer Lua_ForgetDeprecationWarnings()

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("deprecated", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	a := Node_CreateByTypeName(scene, "Node")
	a.name = "A"
	ProcessNodeQueues(scene.manager, &game.gameContext)

	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
same_open = Console.open == nil or type(Console.set_open) == "function"
draw_old, draw_new = Physics.get_debug_draw(), Physics.is_debug_draw()
for i = 1, 3 do local _ = Input.player_count() end -- one call site, three calls
local _ = Input.player_count()                    -- a second site
has_new = type(Input.get_player_count) == "function" and type(Save.get_path) == "function"
Scene.find_node("A"):queue_free()
`)
	testing.expect(t, ok == 0, "lua ran")
	if ok != 0 do testing.expectf(t, false, "%s", lua.tostring(L, -1))
	lua.getglobal(L, "draw_old")
	lua.getglobal(L, "draw_new")
	testing.expect(t, lua.toboolean(L, -1) == lua.toboolean(L, -2), "the old name returns what the new one does")
	lua.pop(L, 2)
	lua.getglobal(L, "has_new")
	testing.expect(t, bool(lua.toboolean(L, -1)), "the new names exist")
	lua.pop(L, 1)
	testing.expect_value(t, Lua_DeprecationWarningCount(), 4) // get_debug_draw, two player_count sites, queue_free
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect(t, Scene_FindNodeByName(scene, "A") == nil, "queue_free still destroys")

	// Release builds: silent.
	Lua_WarnDeprecated = false
	_ = lua.L_dostring(L, `local _ = Input.gamepads()`)
	testing.expect_value(t, Lua_DeprecationWarningCount(), 4)
}
