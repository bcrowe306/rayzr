package engine

import "core:testing"
import lua "lua54"
import rl "vendor:raylib"

// #327: colours take one form everywhere ("#hex", {r, g, b[, a]} 0..1,
// r, g, b[, a]; 0..255 still read), and points take x, y or a Vec2.
@(test)
test_lua_color_and_point_args :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("args", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	label := Node_CreateByTypeName(scene, "UILabelNode")
	label.name = "Label"
	light := Node_CreateByTypeName(scene, "LightNode")
	light.name = "Lamp"
	line := Node_CreateByTypeName(scene, "LineNode")
	line.name = "Line"
	ProcessNodeQueues(scene.manager, &game.gameContext)

	L := game.scriptManager.L
	run :: proc(t: ^testing.T, L: ^lua.State, code: cstring) {
		if lua.L_dostring(L, code) != 0 {
			testing.expectf(t, false, "%s", lua.tostring(L, -1))
			lua.pop(L, 1)
		}
	}
	color :: proc(scene: ^Scene) -> rl.Color {
		p, _ := Node_FindProperty(Scene_FindNodeByName(scene, "Label"), "textColor")
		return (^rl.Color)(p.ptr)^
	}
	run(t, L, `Scene.find_node("Label"):set_property("text_color", "#ff8000")`)
	testing.expect_value(t, color(scene), rl.Color{255, 128, 0, 255})
	run(t, L, `Scene.find_node("Label").text_color = {0, 0.5, 1, 0.5}`)
	testing.expect_value(t, color(scene), rl.Color{0, 128, 255, 128})
	run(t, L, `Scene.find_node("Label"):set_property("text_color", {r = 1, g = 0, b = 0})`)
	testing.expect_value(t, color(scene), rl.Color{255, 0, 0, 255})
	run(t, L, `Scene.find_node("Label"):set_property("text_color", {170, 170, 185, 255})`) // (0..255: still read)
	testing.expect_value(t, color(scene), rl.Color{170, 170, 185, 255})

	run(t, L, `Scene.find_node("Lamp"):light_set_color("#00ff00")`)
	testing.expect_value(t, (cast(^LightNode)light).color, rl.Color{0, 255, 0, 255})
	run(t, L, `Scene.find_node("Lamp"):light_set_color(1, 0, 0)`)
	testing.expect_value(t, (cast(^LightNode)light).color, rl.Color{255, 0, 0, 255})
	run(t, L, `Scene.set_ambient({0.2, 0.4, 0.6})`)
	testing.expect_value(t, scene.ambient, rl.Color{51, 102, 153, 255})

	run(t, L, `local l = Scene.find_node("Line"); l:line_add_point(Vec2(3, 4)); l:line_add_point(5, 6)`)
	pts := (cast(^LineNode)line).points[:]
	n := len(pts)
	testing.expectf(t, n >= 2 && pts[n - 2] == {3, 4} && pts[n - 1] == {5, 6}, "points as a Vec2 or x, y: %v", pts)
}
