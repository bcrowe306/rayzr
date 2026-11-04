package engine

import "core:slice"
import "core:strings"
import "core:testing"

// #388: Visible off hides the node and its whole subtree - not drawn, its
// UI takes no clicks or focus - but the subtree keeps updating.
@(test)
test_visible_hides_subtree :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("visible", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	game.virtualSize = {1280, 720}

	menu := Node_CreateByTypeName(scene, "Node")
	menu.name = "Menu"
	shade := Node_CreateByTypeName(scene, "TextureNode", menu)
	shade.name = "Shade"
	btn := cast(^UIButtonNode)Node_CreateByTypeName(scene, "UIButtonNode", menu)
	btn.name = "Resume"
	btn.position = {100, 100}
	btn.size = {100, 50}
	timer := cast(^TimerNode)Node_CreateByTypeName(scene, "TimerNode", menu)
	clicked := 0
	btn.onClick->subscribe(proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &clicked)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	timer->setDuration(100)
	timer->start()

	drawn :: proc(scene: ^Scene, n: ^Node) -> bool {
		for b in Scene_CollectRenderables(scene) do if slice.contains(b[:], n) do return true
		return false
	}
	click :: proc(game: ^Game, p: [2]f32) {
		game.uiTestMousePos = p
		game.uiTestMousePressed, game.uiTestMouseDown = true, true
		game->run(0.016)
		game.uiTestMousePressed, game.uiTestMouseDown, game.uiTestMouseReleased = false, false, true
		game->run(0.016)
		game.uiTestMouseReleased = false
	}
	game.uiTestInputEnabled = true
	testing.expect(t, drawn(scene, shade) && drawn(scene, btn), "shown: the children draw")
	click(game, {150, 125})
	testing.expect_value(t, clicked, 1)

	// Hidden: the children aren't drawn, the button takes no click or focus...
	menu.renderable = false
	testing.expect(t, !drawn(scene, shade) && !drawn(scene, btn), "hidden parent: its children aren't drawn")
	testing.expect(t, !Node_VisibleInTree(btn) && btn.renderable, "the child's own flag stays on")
	click(game, {150, 125})
	testing.expect_value(t, clicked, 1)
	testing.expect(t, !UI_IsFocusable(btn), "no focus under a hidden node")
	why := UI_FocusNode(game, btn)
	testing.expectf(t, strings.contains(why, "hidden node (Menu)"), "ui_focus says why: %q", why)
	// ...but everything keeps updating.
	before := timer.elapsed
	game->run(0.1)
	testing.expect(t, timer.elapsed > before, "a hidden subtree still updates")

	// Shown again: drawn and clickable.
	menu.renderable = true
	testing.expect(t, drawn(scene, shade), "shown again")
	click(game, {150, 125})
	testing.expect_value(t, clicked, 2)
}

// Nodes that draw nothing are visible (their children draw), also when an
// older scene saved them hidden.
@(test)
test_visible_nondrawing_nodes :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("visible2", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	for name in ([]string{"TimerNode", "BehaviorTreeNode", "GoapNode", "OscillatorNode"}) {
		n := Node_CreateByTypeName(scene, name)
		testing.expectf(t, n != nil && n.renderable, "%s: visible by default", name)
		if n != nil {
			n.renderable = false
			testing.expectf(t, Node_HiddenWasDefault(n), "%s loads visible", name)
		}
	}
}
