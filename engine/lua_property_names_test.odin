package engine

import "core:fmt"
import "core:strings"
import "core:testing"
import lua "lua54"

// #327: scripts use snake_case property names (the Inspector's camelCase
// still works), Node has a `visible` property, and no node type has a
// property a method shadows (follower.rotate read Node:rotate()).
@(test)
test_lua_property_names :: proc(t: ^testing.T) {
	testing.expect_value(t, Property_SnakeName("zIndex"), "z_index")
	testing.expect_value(t, Property_SnakeName("emitter.gravityVelocity"), "emitter.gravity_velocity")
	testing.expect_value(t, Property_CamelName("emitter.gravity_velocity"), "emitter.gravityVelocity")
	testing.expect_value(t, Property_CamelName(Property_SnakeName("textColor")), "textColor")

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("prop_names", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	a := Node_CreateByTypeName(scene, "Node")
	a.name = "A"
	f := Node_CreateByTypeName(scene, "PathFollowNode")
	f.name = "F"
	ProcessNodeQueues(scene.manager, &game.gameContext)

	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local a, f = Scene.find_node("A"), Scene.find_node("F")
a.z_index = 4
a:set_property("pause_mode", "always")
snake_read = a.z_index == 4 and a.zIndex == 4 and a:get_property("pause_mode") == "Always"
a.visible = false
hidden = not a:is_visible() and a.visible == false
f.face_direction = false
faces = f.face_direction == false and f:get_property("rotate") == false
tweens = Tween.to(a, "y_sort_offset", 8, 0.5) ~= 0
`)
	testing.expect(t, ok == 0, "lua ran")
	if ok != 0 do testing.expectf(t, false, "%s", lua.tostring(L, -1))
	for name in ([]cstring{"snake_read", "hidden", "faces", "tweens"}) {
		lua.getglobal(L, name)
		testing.expectf(t, bool(lua.toboolean(L, -1)), "lua: %s", name)
		lua.pop(L, 1)
	}
	testing.expect(t, a.zIndex == 4 && !a.renderable, "the node changed")

	// No property is shadowed by a node method (node.<name> reads methods first).
	clashes := make([dynamic]string, context.temp_allocator)
	for info in NODE_TYPES {
		n := Node_CreateByTypeName(scene, info.name)
		if n == nil do continue
		for p in Node_CollectProperties(n) {
			if strings.contains(p.name, ".") do continue
			name := Property_ScriptName(n, p.name)
			push_node_userdata(L, n)
			lua.getfield(L, -1, strings.clone_to_cstring(name, context.temp_allocator))
			if lua.type(L, -1) == .FUNCTION do append(&clashes, fmt.tprintf("%s.%s", info.name, name))
			lua.pop(L, 2)
		}
	}
	testing.expectf(t, len(clashes) == 0, "properties shadowed by methods: %v", clashes)
}
