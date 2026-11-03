package runner_web

// ============================================================================
// The web runner (built by scripts/build_web_runner.sh into runners/web/):
// Odin compiled for js_wasm32 and linked by emscripten with raylib, Lua and
// Box2D built for the web. The page (scripts/web/shell.html) fetches
// game.rayzr into emscripten's file system, then calls main_start once and
// main_update every animation frame - a browser tab can't run a blocking
// loop. Memory comes from emscripten's malloc (engine/platform_js.odin);
// logs go to the browser console.
// ============================================================================

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:log"
import "core:strings"
import e "../../engine"
import os "../../engine/osx"
import rl "vendor:raylib"

@(default_calling_convention = "c")
foreign {
	puts :: proc(s: cstring) -> c.int ---
}

@(private = "file")
web_logger :: proc(data: rawptr, level: runtime.Logger_Level, text: string, options: runtime.Logger_Options, location := #caller_location) {
	prefix := "[ERROR] " if level >= .Error else ("[WARN] " if level == .Warning else "")
	puts(fmt.ctprintf("%s%s", prefix, text))
}

@(private = "file")
state: struct {
	rs: ^e.Runner_State,
}

// web_context: the engine's web context (emscripten's malloc, a temp
// arena) with logs going to the browser console.
@(private = "file")
web_context :: proc "contextless" () -> runtime.Context {
	ctx := e.Engine_DefaultContext()
	ctx.logger = {procedure = web_logger, lowest_level = .Info}
	return ctx
}

// main_start: the page has written game.rayzr into the file system.
@(export)
main_start :: proc "c" () {
	context = web_context()
	opts := e.Run_Options{projectPath = "/game.rayzr", userDataDir = "/save"}
	log.info("[web] starting /game.rayzr")
	rs, ok := e.Runner_Start(opts)
	if !ok {
		log.error("The game could not start (is game.rayzr there?)")
		return
	}
	state.rs = rs
	log.info("[web] started")
}

// main_start_test: main_start with runner arguments (--frames,
// --input-script, --dump-scene, --scene, --user-data...) read from
// /test/args.txt, one a line - the page's ?test mode, for scripted
// play-throughs in headless Chrome (scripts/templates/test_templates.py
// --web). The game is still /game.rayzr and its saves /save unless the
// arguments say otherwise.
@(export)
main_start_test :: proc "c" () {
	context = web_context()
	text, err := os.read_entire_file("/test/args.txt")
	if err != nil {
		log.errorf("[web] no /test/args.txt: %v", err)
		return
	}
	args := make([dynamic]string)
	for line in strings.split_lines(string(text)) do if line != "" do append(&args, line)
	opts := e.Engine_ParseRunArgs(args[:])
	if opts.projectPath == "" do opts.projectPath = "/game.rayzr"
	if opts.userDataDir == "" do opts.userDataDir = "/save"
	log.infof("[web] test run: %v", args[:])
	rs, ok := e.Runner_Start(opts)
	if !ok {
		log.error("The game could not start (is game.rayzr there?)")
		return
	}
	state.rs = rs
	log.info("[web] started")
}

// main_update: one frame; false when the game is over.
@(export)
main_update :: proc "c" () -> bool {
	context = web_context()
	if state.rs == nil do return false
	if !e.Runner_Frame(state.rs) {
		log.info("[web] the game ended")
		e.Runner_Stop(state.rs)
		state.rs = nil
		return false
	}
	return true
}

// main_flush_saves: the tab is hiding (it may be closed or discarded
// without a quit): the save data goes to /save before the page syncs it to
// IndexedDB (#378).
@(export)
main_flush_saves :: proc "c" () {
	context = web_context()
	e.Runner_FlushSaves()
}

// main_resize: the canvas changed size (the page follows the window).
@(export)
main_resize :: proc "c" (w, h: c.int) {
	context = web_context()
	if state.rs != nil do rl.SetWindowSize(w, h)
}
