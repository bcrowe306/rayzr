package engine

import "core:log"
import "core:strings"
import "core:testing"
import lua "lua54"

// node:ui_focus() gives a widget the focus (Enter then presses it, Tab moves
// on from it); a label, a disabled or a hidden button return false and warn
// (#252). ui_has_focus() reads it.
@(test)
test_lua_ui_focus :: proc(t: ^testing.T) {
	@(static) got: [dynamic]string
	clear(&got)
	scriptLogSink = proc(level: log.Level, text: string) {
		if level == .Warning do append(&got, strings.clone(text, context.temp_allocator))
	}
	defer scriptLogSink = nil
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	game.uiTestInputEnabled = true
	scene := game->createScene("focus", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	layer := ScreenLayerNode_Create(scene, "Menu")
	clicks := [3]int{}
	names := [3]string{"First", "Second", "Third"}
	btns: [3]^UIButtonNode
	for i in 0 ..< 3 {
		btns[i] = UIButtonNode_Create(scene, names[i], names[i], {200, 36}, layer)
		btns[i].position = {100, 100 + f32(i) * 50}
		btns[i].onClick->subscribe(proc(source: rawptr, val: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &clicks[i])
	}
	_ = UILabelNode_Create(scene, "Caption", "Hello", 20, layer)
	off := UIButtonNode_Create(scene, "Off", "Off", {200, 36}, layer)
	off.enabled = false
	hidden := UIButtonNode_Create(scene, "Hidden", "Hidden", {200, 36}, layer)
	hidden.renderable = false
	game->run(0.016)

	L := game.scriptManager.L
	run :: proc(L: ^lua.State, code: cstring) -> (ok: bool, result: bool) {
		if lua.L_dostring(L, code) != 0 do return false, false
		result = bool(lua.toboolean(L, -1))
		lua.pop(L, 1)
		return true, result
	}
	ok, focused := run(L, `return Scene.find_node("Second"):ui_focus()`)
	testing.expect(t, ok && focused, "ui_focus on a button returns true")
	testing.expect(t, btns[1].focused && !btns[0].focused && !btns[2].focused, "the second button has the focus")
	ok, focused = run(L, `return Scene.find_node("Second"):ui_has_focus()`)
	testing.expect(t, ok && focused, "ui_has_focus: true")
	ok, focused = run(L, `return Scene.find_node("First"):ui_has_focus()`)
	testing.expect(t, ok && !focused, "ui_has_focus on another button: false")

	// Enter presses the focused button (the frame after it was focused).
	game.uiTestKeyEnter = true
	game->run(0.016)
	game.uiTestKeyEnter = false
	game->run(0.016)
	testing.expect_value(t, clicks, [3]int{0, 1, 0})
	// Tab moves on from it.
	game.uiTestKeyTab = true
	game->run(0.016)
	game.uiTestKeyTab = false
	testing.expect(t, btns[2].focused && !btns[1].focused, "Tab moves to the third button")

	// Can't take it: false, a warning naming why, the focus stays.
	ok, focused = run(L, `return Scene.find_node("Caption"):ui_focus()`)
	testing.expect(t, ok && !focused, "ui_focus on a label returns false")
	ok, focused = run(L, `return Scene.find_node("Off"):ui_focus()`)
	testing.expect(t, ok && !focused, "ui_focus on a disabled button returns false")
	ok, focused = run(L, `return Scene.find_node("Hidden"):ui_focus()`)
	testing.expect(t, ok && !focused, "ui_focus on a hidden button returns false")
	ok, focused = run(L, `return Scene.find_node("Caption"):ui_has_focus()`)
	testing.expect(t, ok && !focused, "ui_has_focus on a label: false")
	testing.expect(t, btns[2].focused, "the focus stays where it was")
	testing.expect_value(t, len(got), 3)
	if len(got) == 3 {
		testing.expect(t, strings.contains(got[0], "ui_focus: Caption is a UILabelNode"), got[0])
		testing.expect(t, strings.contains(got[1], "ui_focus: Off is disabled"), got[1])
		testing.expect(t, strings.contains(got[2], "ui_focus: Hidden is hidden"), got[2])
	}
	// Under a disabled node (a closed menu): false.
	layer.enabled = false
	ok, focused = run(L, `return Scene.find_node("First"):ui_focus()`)
	testing.expect(t, ok && !focused, "ui_focus under a disabled node returns false")
	delete(got)
	got = nil
}

// Engine.quit() asks the game to end: the runner's loop stops at its next
// frame (Runner_Frame), as when the window is closed; true on the desktop.
@(test)
test_lua_engine_quit :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	testing.expect(t, !game.shouldQuit, "not quitting at first")
	L := game.scriptManager.L
	testing.expect_value(t, lua.L_dostring(L, `return Engine.quit()`), i32(0))
	testing.expect(t, bool(lua.toboolean(L, -1)), "Engine.quit returns true")
	lua.pop(L, 1)
	testing.expect(t, game.shouldQuit, "the quit request is set")
	// The dev console's `quit` takes the same path.
	game.shouldQuit = false
	Game_RequestQuit(game)
	testing.expect(t, game.shouldQuit, "Game_RequestQuit sets it")
}
