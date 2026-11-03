package engine

import "core:testing"
import rl "vendor:raylib"

// #362: simulated keys (--input-script, Test.press_key: the engine's input
// layer) reach the widgets - focus navigation, Enter / Space - not only the
// unit tests' uiTestKey* switches.
@(test)
test_ui_synthetic_keys :: proc(t: ^testing.T) {
	RunWithLeakTracking(t, proc(t: ^testing.T) {
		game := new(Game)
		InitializeGame(game)
		scene := game->createScene("ui_synthetic_keys", true)
		panel := UIPanelNode_Create(scene, "Panel", "Menu", {100, 100}, {400, 300}, .Vertical)
		vbox := UIVerticalContainerNode_Create(scene, "VBox", {360, 240}, 8, .Stretch, panel)
		clicked := 0
		btn1 := UIButtonNode_Create(scene, "Play", "Play", {120, 30}, vbox)
		btn2 := UIButtonNode_Create(scene, "Quit", "Quit", {120, 30}, vbox)
		btn2.onClick->subscribe(proc(source: rawptr, val: EventValue, ctx: ^GameContext, user_data: rawptr) {
			(cast(^int)user_data)^ += 1
		}, &clicked)
		chk := UICheckboxNode_Create(scene, "Sound", "Sound", false, vbox)
		game->run(0.016)

		// A tap: down one frame, up the next (as an input script's "tap").
		tap :: proc(game: ^Game, key: rl.KeyboardKey) {
			Input_SetSimulatedKey(&game.input, key, true)
			game->run(0.016)
			Input_SetSimulatedKey(&game.input, key, false)
			game->run(0.016)
		}
		tap(game, .TAB)
		testing.expect(t, UI_GetFocusedElement(scene) == &btn1.ui, "Tab focuses the first button")
		tap(game, .DOWN)
		testing.expect(t, UI_GetFocusedElement(scene) == &btn2.ui, "Down moves the focus")
		tap(game, .ENTER)
		testing.expect_value(t, clicked, 1)
		Input_SetSimulatedKey(&game.input, .ENTER, true)
		for _ in 0 ..< 3 do game->run(0.016)
		Input_SetSimulatedKey(&game.input, .ENTER, false)
		game->run(0.016)
		testing.expect_value(t, clicked, 2) // (held: pressed once)
		tap(game, .DOWN)
		testing.expect(t, UI_GetFocusedElement(scene) == &chk.ui, "Down again: the checkbox")
		tap(game, .SPACE)
		testing.expect(t, chk.checked, "Space toggles it")
		game->terminate()
	})
}
