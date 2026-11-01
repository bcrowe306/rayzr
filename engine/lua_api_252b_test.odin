package engine

import os "osx"
import "core:strings"
import "core:testing"
import lua "lua54"

// #252, the rough edges: an unknown name fails with a warning (create_node,
// Tween.to / ease, sm_start), emit passes a table itself, Project.read_json,
// Locale.set remembers the language, Crash.* and set_fullscreen in the editor.
@(test)
test_lua_api_252_rough_edges :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("lua252b", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	ctx := &game.gameContext
	L := game.scriptManager.L
	run :: proc(t: ^testing.T, L: ^lua.State, code: cstring, loc := #caller_location) {
		if lua.L_dostring(L, code) != 0 {
			testing.fail_now(t, strings.clone(string(lua.tostring(L, -1)), context.temp_allocator), loc)
		}
	}
	gs :: proc(L: ^lua.State, n: cstring) -> string {
		lua.getglobal(L, n)
		defer lua.pop(L, 1)
		return strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
	}
	dir :: "test_lua_252b"
	_ = os.make_directory_all(dir + "/data")
	defer os.remove_all(dir)
	game.assetManager.projectDir = strings.clone(dir, game.assetManager.allocator)
	Save_SetDirectory(dir + "/save")
	defer Save_SetDirectory("")

	box := Node_CreateByTypeName(scene, "Node")
	box.name = strings.clone("Box", box.allocator)
	ProcessNodeQueues(scene.manager, ctx)

	// Unknown names: nothing made / started, a warning.
	run(t, L, `n = tostring(Scene.create_node("NoSuchNode", "X"))
		plain = tostring(Scene.create_node("Node", "P") ~= nil)
		id = Tween.to(Scene.find_node("Box"), "position", {10, 0}, 1, "bouncy")
		good = Tween.to(Scene.find_node("Box"), "position", {10, 0}, 1, "in_quad")
		e = tostring(Tween.ease("bouncy", 0.5)); e2 = Tween.ease("linear", 0.5)`)
	testing.expect_value(t, gs(L, "n"), "nil")
	testing.expect_value(t, gs(L, "plain"), "true")
	testing.expect_value(t, gs(L, "id"), "0")
	testing.expect(t, gs(L, "good") != "0", "a known ease tweens")
	testing.expect_value(t, gs(L, "e"), "nil")
	testing.expect_value(t, gs(L, "e2"), "0.5")

	// emit: a table arrives as itself (the same table), here and in on_ methods.
	run(t, L, `local b = Scene.find_node("Box"); local sent = {hp = 3}
		b:connect("hit", function(v) got = v; same = tostring(v == sent) end)
		b:emit("hit", sent); hp = got and got.hp`)
	testing.expect_value(t, gs(L, "same"), "true")
	testing.expect_value(t, gs(L, "hp"), "3")

	// Project.read_json.
	_ = os.write_entire_file(dir + "/data/items.json", transmute([]u8)string(`{"items": [{"name": "sword", "dmg": 5}, {"name": "bow"}], "ok": true, "none": null}`))
	_ = os.write_entire_file(dir + "/data/bad.json", transmute([]u8)string(`{"items": [`))
	run(t, L, `local d = Project.read_json("data/items.json")
		first = d.items[1].name; dmg = tostring(d.items[1].dmg == 5); count = #d.items; ok = tostring(d.ok); none = tostring(d.none)
		bad = tostring(Project.read_json("data/bad.json")); missing = tostring(Project.read_json("data/nope.json"))`)
	testing.expect_value(t, gs(L, "first"), "sword")
	testing.expect_value(t, gs(L, "dmg"), "true")
	testing.expect_value(t, gs(L, "count"), "2")
	testing.expect_value(t, gs(L, "ok"), "true")
	testing.expect_value(t, gs(L, "none"), "nil")
	testing.expect_value(t, gs(L, "bad"), "nil")
	testing.expect_value(t, gs(L, "missing"), "nil")

	// Locale.set remembers the language (false: a preview, not remembered).
	run(t, L, `Locale.set("fr", false)`)
	testing.expect(t, !os.exists(Locale_ChoicePath()), "a preview isn't remembered")
	run(t, L, `Locale.set("de")`)
	Locale_SetLanguage("en")
	testing.expect(t, Locale_LoadChoice(game) && Locale_Language() == "de", "remembered and loaded")

	// In the editor (Simulate): no crash folder, no fullscreen.
	game.inEditor = true
	run(t, L, `cd = Crash.dir(); cn = #Crash.pending(); Engine.set_fullscreen(true); fs = tostring(Engine.is_fullscreen())`)
	testing.expect_value(t, gs(L, "cd"), "")
	testing.expect_value(t, gs(L, "cn"), "0")
	testing.expect_value(t, gs(L, "fs"), "false")
	game.inEditor = false
	Locale_SetLanguage("")
	free_all(context.temp_allocator)
}
