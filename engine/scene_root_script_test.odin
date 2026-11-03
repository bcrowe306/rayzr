package engine

import "core:log"
import "core:strings"
import "core:testing"

// #370: a script on the scene's root node doesn't run (the root takes none:
// the editor offers no script there) - loading such a scene says so.
@(test)
test_scene_root_script_warns :: proc(t: ^testing.T) {
	Capture :: struct {warnings: [dynamic]string}
	cap := Capture{warnings = make([dynamic]string, context.temp_allocator)}
	logger := context.logger
	context.logger = log.Logger{
		procedure = proc(data: rawptr, level: log.Level, text: string, options: log.Options, location := #caller_location) {
			if level == .Warning do append(&(cast(^Capture)data).warnings, strings.clone(text, context.temp_allocator))
		},
		data = &cap,
		lowest_level = .Debug,
	}
	defer context.logger = logger

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("rooted", false)
	ok := Scene_InstantiateFromJSON(scene, transmute([]u8)string(`{"name": "rooted", "root": {"type": "Node", "name": "root",
		"script": {"path": "scripts/game.lua"},
		"children": [{"type": "Node", "name": "Child"}]}}`), &game.gameContext)
	testing.expect(t, ok, "loaded")
	found := false
	for w in cap.warnings do if strings.contains(w, "root node can't have a script") && strings.contains(w, "scripts/game.lua") do found = true
	testing.expectf(t, found, "a warning names the script: %v", cap.warnings[:])

	// No script on the root: no warning.
	clear(&cap.warnings)
	other := game->createScene("plain", false)
	Scene_InstantiateFromJSON(other, transmute([]u8)string(`{"name": "plain", "root": {"type": "Node", "name": "root", "children": []}}`), &game.gameContext)
	for w in cap.warnings do testing.expectf(t, !strings.contains(w, "script"), "no script warning: %s", w)
}
