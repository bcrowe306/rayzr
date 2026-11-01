package engine

import "core:c"
import "core:fmt"
import os "osx"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"
import lua "lua54"
import rl "vendor:raylib"

// ============================================================================
// Tests for game code (#284): the runner with --test plays a project's
// tests/*_test.lua files. Each test_<name>() function runs as a coroutine
// in the game's Lua state, so it reads top to bottom and waiting is a call:
//
//   function test_jump()
//       Test.load_scene("level1")
//       local player = Scene.find_node("Player")
//       local y = player:get_global_position().y
//       Test.press("jump")
//       Test.step(20)
//       Test.expect(player:get_global_position().y < y, "the player jumped")
//   end
//
// Every test starts from the project's first scene, input simulated (the
// keyboard is ignored), a fixed 1/60 s step and the same random seed.
// Test.expect records a failure and goes on; Test.require / fail stop the
// test. A test fails on a Lua error and after Test.timeout frames.
//
// Results go to stdout for the editor's Tests panel:
//   @rayzr:test {"event": "start" | "fail" | "pass" | "skip", "file", "name", ...}
//   @rayzr:tests {"event": "done", "passed", "failed", "skipped", "ms"}
// The process exits non-zero when a test failed.
// ============================================================================

TESTS_DIR :: "tests"
TEST_TIMEOUT_FRAMES :: 60 * 60 // a minute of game time
TEST_SEED :: 1234

Test_Case :: struct {
	file: string, // project-relative
	name: string,
	env:  c.int,  // registry ref: the file's environment
}

Test_Phase :: enum u8 {
	Idle,
	Loading,  // the first scene (re)loads before the test starts
	Running,
	Finished, // every test ran
}

Test_Wait :: enum u8 {
	None,
	Frames, // Test.step
	Until,  // Test.wait_until
	Replay, // Test.replay
	Scene,  // Test.load_scene
}

Test_Release :: struct {
	at:      int, // the test frame it goes up
	action:  string,
	key:     rl.KeyboardKey,
	isKey:   bool,
	mouse:   bool,
}

Test_Runner :: struct {
	active:      bool,
	filter:      string,
	cases:       [dynamic]Test_Case,
	index:       int,
	phase:       Test_Phase,
	loadFrames:  int,
	co:          ^lua.State,
	coRef:       c.int,
	wait:        Test_Wait,
	waitFrames:  int,
	untilRef:    c.int,
	untilLeft:   int,
	frame:       int, // frames into the current test
	timeout:     int,
	failures:    int, // this test's
	skipped:     bool,
	releases:    [dynamic]Test_Release,
	replay:      [dynamic]Input_Script_Event,
	replayStart: int,
	replayEnd:   int,
	startScene:  string,
	passed, failed, skippedCount: int,
	started:     time.Tick,
	testStarted: time.Tick,
}

gameTests: Test_Runner

// Tests_Active: the runner is playing tests (--test).
Tests_Active :: proc() -> bool {return gameTests.active}

// Tests_Start finds the tests (those whose "file:name" contains `filter`;
// "" or "*": all) once the project and its first scene are loaded.
Tests_Start :: proc(game: ^Game, filter: string) {
	context.allocator = Engine_HeapAllocator()
	gameTests = {}
	gameTests.active = true
	gameTests.filter = strings.clone(filter if filter != "*" else "")
	gameTests.started = time.tick_now()
	if s := game.sceneManager.currentScene; s != nil do gameTests.startScene = strings.clone(s.name)
	game.input.useSimulatedInput = true
	tests_discover(game)
	if len(gameTests.cases) == 0 do tests_out("@rayzr:tests {\"event\": \"none\"}")
	gameTests.index = -1
	tests_next(game)
}

// Tests_Shutdown frees the runner (the game ending).
Tests_Shutdown :: proc(game: ^Game) {
	context.allocator = Engine_HeapAllocator()
	L := game.scriptManager.L
	for tc in gameTests.cases {
		delete(tc.file)
		delete(tc.name)
		if L != nil && tc.env != 0 do lua.L_unref(L, lua.REGISTRYINDEX, tc.env)
	}
	tests_release_co(L)
	delete(gameTests.cases)
	for r in gameTests.releases do delete(r.action)
	delete(gameTests.releases)
	delete(gameTests.replay)
	delete(gameTests.filter)
	delete(gameTests.startScene)
	gameTests = {}
}

// Tests_ExitCode: 1 when a test failed (or none ran because of an error).
Tests_ExitCode :: proc() -> int {return 1 if gameTests.failed > 0 else 0}

// tests_out prints a protocol line (and flushes: the editor reads it live).
@(private = "file")
tests_out :: proc(line: string) {
	fmt.println(line) // (unbuffered: the editor reads it live)
}

@(private = "file")
json_str :: proc(sb: ^strings.Builder, s: string) {
	strings.write_byte(sb, '"')
	for ch in s {
		switch ch {
		case '"': strings.write_string(sb, "\\\"")
		case '\\': strings.write_string(sb, "\\\\")
		case '\n': strings.write_string(sb, "\\n")
		case '\t': strings.write_string(sb, "\\t")
		case: if ch >= 32 do strings.write_rune(sb, ch)
		}
	}
	strings.write_byte(sb, '"')
}

@(private = "file")
tests_event :: proc(event: string, tc: Test_Case, extra := "") {
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "@rayzr:test {\"event\": ")
	json_str(&sb, event)
	strings.write_string(&sb, ", \"file\": ")
	json_str(&sb, tc.file)
	strings.write_string(&sb, ", \"name\": ")
	json_str(&sb, tc.name)
	strings.write_string(&sb, extra)
	strings.write_byte(&sb, '}')
	tests_out(strings.to_string(sb))
}

// ----------------------------------------------------------------------------
// Finding the tests
// ----------------------------------------------------------------------------

@(private = "file")
tests_discover :: proc(game: ^Game) {
	dir, _ := filepath.join({game.assetManager.projectDir, TESTS_DIR}, context.temp_allocator)
	files := make([dynamic]string, context.temp_allocator)
	tests_walk(dir, TESTS_DIR, &files)
	slice.sort(files[:])
	L := game.scriptManager.L
	if L == nil do return
	for rel in files {
		text, ok := AssetManager_ReadFileString(&game.assetManager, rel, context.temp_allocator)
		if !ok do continue
		names := tests_function_names(text)
		wanted := make([dynamic]string, context.temp_allocator)
		for n in names {
			full := fmt.tprintf("%s:%s", rel, n)
			if gameTests.filter == "" || strings.contains(full, gameTests.filter) do append(&wanted, n)
		}
		if len(wanted) == 0 do continue
		// The file runs once, in an environment of its own (its globals
		// over _G), so its test_ functions don't clash with another file's.
		lua.createtable(L, 0, 0)
		lua.createtable(L, 0, 1)
		lua.pushglobaltable(L)
		lua.setfield(L, -2, "__index")
		lua.setmetatable(L, -2)
		envIdx := lua.gettop(L)
		chunk := fmt.ctprintf("@%s", rel)
		if lua.L_loadbuffer(L, raw_data(text), c.size_t(len(text)), chunk) != .OK {
			msg := strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
			lua.settop(L, envIdx - 1)
			tests_file_error(rel, msg)
			continue
		}
		lua.pushvalue(L, envIdx)
		_ = lua.setupvalue(L, -2, 1) // (its _ENV)
		if lua.pcall(L, 0, 0, 0) != 0 {
			msg := strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
			lua.settop(L, envIdx - 1)
			tests_file_error(rel, msg)
			continue
		}
		for n in wanted {
			lua.pushvalue(L, envIdx)
			ref := lua.L_ref(L, lua.REGISTRYINDEX) // (one ref per test: freed each)
			append(&gameTests.cases, Test_Case{strings.clone(rel, Engine_HeapAllocator()), strings.clone(n, Engine_HeapAllocator()), ref})
		}
		lua.settop(L, envIdx - 1)
	}
}

// Tests_FunctionNames: the test_<name> functions a file defines, in order
// ("function test_x(" at the file's level; not local ones). The editor
// lists tests with it too.
Tests_FunctionNames :: proc(text: string, allocator := context.temp_allocator) -> [dynamic]string {
	return tests_function_names(text, allocator)
}

@(private = "file")
tests_function_names :: proc(text: string, allocator := context.temp_allocator) -> [dynamic]string {
	names := make([dynamic]string, allocator)
	KW :: "function"
	ident :: proc(b: u8) -> bool {return b == '_' || (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b >= '0' && b <= '9')}
	for i := 0; i + len(KW) < len(text); i += 1 {
		if text[i:i + len(KW)] != KW || (i > 0 && ident(text[i - 1])) do continue
		// At the start of a line (so not "local function", not inside an expression).
		j := i - 1
		for j >= 0 && (text[j] == ' ' || text[j] == '\t') do j -= 1
		if j >= 0 && text[j] != '\n' do continue
		p := i + len(KW)
		for p < len(text) && (text[p] == ' ' || text[p] == '\t') do p += 1
		start := p
		for p < len(text) && ident(text[p]) do p += 1
		name := text[start:p]
		for p < len(text) && (text[p] == ' ' || text[p] == '\t') do p += 1
		if strings.has_prefix(name, "test_") && p < len(text) && text[p] == '(' do append(&names, name)
		i = p
	}
	return names
}

@(private = "file")
tests_walk :: proc(abs, rel: string, out: ^[dynamic]string) {
	h, err := os.open(abs)
	if err != nil do return
	infos, _ := os.read_dir(h, -1, context.temp_allocator)
	os.close(h)
	for fi in infos {
		childAbs, _ := filepath.join({abs, fi.name}, context.temp_allocator)
		childRel := fmt.tprintf("%s/%s", rel, fi.name)
		if fi.type == .Directory {
			if fi.name != "recordings" do tests_walk(childAbs, childRel, out)
		} else if strings.has_suffix(fi.name, "_test.lua") {
			append(out, childRel)
		}
	}
}

// A file that doesn't load counts as a failed test named after it.
@(private = "file")
tests_file_error :: proc(rel, msg: string) {
	tc := Test_Case{file = rel, name = "(loading the file)"}
	tests_event("start", tc)
	line := tests_line_of(msg, rel)
	tests_event("fail", tc, fmt.tprintf(", \"line\": %d, \"message\": %s", line, tests_quote(msg)))
	tests_event("end", tc, ", \"passed\": false, \"frames\": 0")
	gameTests.failed += 1
}

@(private = "file")
tests_quote :: proc(s: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	json_str(&sb, s)
	return strings.to_string(sb)
}

// tests_line_of: the line in `file` a Lua message points at ("tests/x_test.lua:12: ...").
@(private = "file")
tests_line_of :: proc(msg, file: string) -> int {
	i := strings.index(msg, file)
	if i < 0 do return 0
	rest := msg[i + len(file):]
	if !strings.has_prefix(rest, ":") do return 0
	rest = rest[1:]
	n := 0
	for n < len(rest) && rest[n] >= '0' && rest[n] <= '9' do n += 1
	v, _ := strconv.parse_int(rest[:n])
	return v
}

// ----------------------------------------------------------------------------
// Running
// ----------------------------------------------------------------------------

@(private = "file")
tests_release_co :: proc(L: ^lua.State) {
	if L != nil && gameTests.coRef != 0 do lua.L_unref(L, lua.REGISTRYINDEX, gameTests.coRef)
	if L != nil && gameTests.untilRef != 0 do lua.L_unref(L, lua.REGISTRYINDEX, gameTests.untilRef)
	gameTests.co, gameTests.coRef, gameTests.untilRef = nil, 0, 0
}

// tests_next: the next test (its first scene loads first), or the summary.
@(private = "file")
tests_next :: proc(game: ^Game) {
	gameTests.index += 1
	if gameTests.index >= len(gameTests.cases) {
		gameTests.phase = .Finished
		ms := time.duration_milliseconds(time.tick_since(gameTests.started))
		tests_out(fmt.tprintf("@rayzr:tests {{\"event\": \"done\", \"passed\": %d, \"failed\": %d, \"skipped\": %d, \"ms\": %.1f}}", gameTests.passed, gameTests.failed, gameTests.skippedCount, ms))
		return
	}
	// A fresh start: the first scene again, input released, normal time, the same seed.
	Input_ClearSimulatedInputs(&game.input)
	game.input.simulatedActionsDown = {}
	game.input.useSimulatedInput = true
	Runner_MouseFrame(game)
	game.uiTestMouseDown = false
	for r in gameTests.releases do delete(r.action, Engine_HeapAllocator())
	clear(&gameTests.releases)
	clear(&gameTests.replay)
	GameFeel_Destroy(game)
	game.feel = {}
	game.feel.timeScale = 1
	game.treePaused = false
	if gameTests.startScene != "" do ChangeScene_ByName(&game.sceneManager, gameTests.startScene)
	gameTests.phase = .Loading
	gameTests.loadFrames = 2
	gameTests.frame = 0
	gameTests.failures = 0
	gameTests.skipped = false
	gameTests.timeout = TEST_TIMEOUT_FRAMES
	gameTests.wait = .None
	tests_event("start", gameTests.cases[gameTests.index])
}

// tests_begin: the scene is up - the test's coroutine starts.
@(private = "file")
tests_begin :: proc(game: ^Game) {
	L := game.scriptManager.L
	tc := gameTests.cases[gameTests.index]
	gameTests.testStarted = time.tick_now()
	_, _ = Lua_Eval(L, fmt.tprintf("math.randomseed(%d)", TEST_SEED), context.temp_allocator)
	gameTests.co = lua.newthread(L)
	gameTests.coRef = lua.L_ref(L, lua.REGISTRYINDEX) // (keeps the thread)
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(tc.env))
	lua.getfield(L, -1, strings.clone_to_cstring(tc.name, context.temp_allocator))
	lua.remove(L, -2)
	lua.xmove(L, gameTests.co, 1)
	gameTests.phase = .Running
	tests_resume(game, 0)
}

// tests_resume runs the test until it waits or ends.
@(private = "file")
tests_resume :: proc(game: ^Game, narg: c.int) {
	L := game.scriptManager.L
	co := gameTests.co
	gameTests.wait = .None
	nres: c.int
	st := lua.resume(co, L, narg, &nres)
	if st == .YIELD {
		lua.settop(co, 0)
		if gameTests.wait == .None do gameTests.wait, gameTests.waitFrames = .Frames, 1 // (a bare coroutine.yield: a frame)
		return
	}
	tc := gameTests.cases[gameTests.index]
	if st != .OK {
		msg := string(lua.tostring(co, -1)) if lua.type(co, -1) == .STRING else "error"
		if !strings.has_prefix(msg, TEST_STOP) {
			lua.L_traceback(L, co, strings.clone_to_cstring(msg, context.temp_allocator), 0)
			full := strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
			lua.pop(L, 1)
			tests_fail(tc, tests_line_of(msg, tc.file), full)
		}
	}
	tests_finish(game)
}

TEST_STOP :: "\x01rayzr-test-stop"

@(private = "file")
tests_fail :: proc(tc: Test_Case, line: int, message: string) {
	gameTests.failures += 1
	tests_event("fail", tc, fmt.tprintf(", \"line\": %d, \"frame\": %d, \"message\": %s", line, gameTests.frame, tests_quote(message)))
}

@(private = "file")
tests_finish :: proc(game: ^Game) {
	tc := gameTests.cases[gameTests.index]
	ms := time.duration_milliseconds(time.tick_since(gameTests.testStarted))
	if gameTests.skipped {
		gameTests.skippedCount += 1
		tests_event("end", tc, fmt.tprintf(", \"passed\": true, \"skipped\": true, \"frames\": %d, \"ms\": %.1f", gameTests.frame, ms))
	} else {
		ok := gameTests.failures == 0
		if ok do gameTests.passed += 1
		else do gameTests.failed += 1
		tests_event("end", tc, fmt.tprintf(", \"passed\": %t, \"frames\": %d, \"ms\": %.1f", ok, gameTests.frame, ms))
	}
	tests_release_co(game.scriptManager.L)
	tests_next(game)
}

// Tests_BeforeFrame (the runner, before the frame runs): this frame's
// replayed input and timed releases.
Tests_BeforeFrame :: proc(game: ^Game) {
	if !gameTests.active || gameTests.phase != .Running do return
	Runner_MouseFrame(game)
	f := gameTests.frame
	for i := len(gameTests.releases) - 1; i >= 0; i -= 1 {
		r := gameTests.releases[i]
		if r.at > f do continue
		if r.mouse do Runner_ApplyMouseEvent(game, Input_Script_Event{mouse = true, pos = game.uiTestMousePos, down = false, button_change = true})
		else if r.isKey do Input_SetSimulatedKey(&game.input, r.key, false)
		else do test_set_action(game, r.action, false)
		delete(r.action, Engine_HeapAllocator())
		ordered_remove(&gameTests.releases, i)
	}
	if gameTests.wait == .Replay {
		rf := f - gameTests.replayStart
		for ev in gameTests.replay do if ev.frame == rf {
			if ev.mouse do Runner_ApplyMouseEvent(game, ev)
			else do Runner_ApplyInputEvent(&game.input, ev)
		}
	}
}

// Tests_AfterFrame (after the frame ran): waits count down, the test goes
// on. false once every test ran (the runner quits).
Tests_AfterFrame :: proc(game: ^Game) -> bool {
	if !gameTests.active do return true
	switch gameTests.phase {
	case .Idle: return true
	case .Finished: return false
	case .Loading:
		gameTests.loadFrames -= 1
		if gameTests.loadFrames <= 0 do tests_begin(game)
		return true
	case .Running:
	}
	gameTests.frame += 1
	if gameTests.frame > gameTests.timeout {
		tests_fail(gameTests.cases[gameTests.index], 0, fmt.tprintf("timed out after %d frames (Test.timeout(frames) for longer)", gameTests.timeout))
		tests_finish(game)
		return true
	}
	L := game.scriptManager.L
	switch gameTests.wait {
	case .None:
		tests_resume(game, 0)
	case .Frames, .Scene:
		gameTests.waitFrames -= 1
		if gameTests.waitFrames <= 0 do tests_resume(game, 0)
	case .Replay:
		if gameTests.frame - gameTests.replayStart > gameTests.replayEnd do tests_resume(game, 0)
	case .Until:
		lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(gameTests.untilRef))
		done := false
		if lua.pcall(L, 0, 1, 0) != 0 {
			msg := strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
			lua.pop(L, 1)
			tc := gameTests.cases[gameTests.index]
			tests_fail(tc, tests_line_of(msg, tc.file), msg)
			tests_finish(game)
			return true
		}
		done = bool(lua.toboolean(L, -1))
		lua.pop(L, 1)
		gameTests.untilLeft -= 1
		if done || gameTests.untilLeft <= 0 {
			lua.L_unref(L, lua.REGISTRYINDEX, gameTests.untilRef)
			gameTests.untilRef = 0
			lua.pushboolean(gameTests.co, b32(done))
			tests_resume(game, 1)
		}
	}
	return true
}

// ----------------------------------------------------------------------------
// Input
// ----------------------------------------------------------------------------

// test_set_action presses / releases an action the way a player would: its
// first keyboard binding (or mouse button, or pad button); a built-in
// action with none is set directly.
@(private = "file")
test_set_action :: proc(game: ^Game, name: string, down: bool) -> bool {
	input := &game.input
	if m := Input_MappingOf(input, name); m != nil {
		for i in 0 ..< m.bindingCount {
			b := m.bindings[i]
			#partial switch b.deviceType {
			case .KeyboardKey:
				Input_SetSimulatedKey(input, b.key, down)
				return true
			case .MouseButton:
				Input_SetSimulatedMouseButton(input, b.mouseButton, down)
				return true
			}
		}
		for i in 0 ..< m.bindingCount do if m.bindings[i].deviceType == .GamepadButton {
			if down do Input_SimulatePad(input, 0, true)
			Input_SimulatePadButton(input, 0, m.bindings[i].gamepadButton, down)
			return true
		}
	}
	if a, ok := Builtin_ActionByName(name); ok {
		Input_SetSimulatedAction(input, a, down)
		return true
	}
	return false
}

// ----------------------------------------------------------------------------
// Lua: the Test module
// ----------------------------------------------------------------------------

@(private = "file")
test_game :: proc(L: ^lua.State) -> ^Game {
	sm := get_script_manager(L)
	return sm.game if sm != nil else nil
}

@(private = "file")
test_where :: proc(L: ^lua.State) -> (file: string, line: int) {
	lua.L_where(L, 1)
	w := strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
	lua.pop(L, 1)
	if gameTests.index >= 0 && gameTests.index < len(gameTests.cases) {
		file = gameTests.cases[gameTests.index].file
		line = tests_line_of(w, file)
	}
	return
}

@(private = "file")
test_record_fail :: proc(L: ^lua.State, what: string) {
	if gameTests.index < 0 || gameTests.index >= len(gameTests.cases) do return
	_, line := test_where(L)
	tests_fail(gameTests.cases[gameTests.index], line, what)
}

@(private = "file")
test_running :: proc(L: ^lua.State, fn: string) -> bool {
	if gameTests.active && gameTests.co == L do return true
	lua.L_error(L, "%s: only inside a test (tests/*_test.lua, run from the Tests panel)", strings.clone_to_cstring(fn, context.temp_allocator))
	return false
}

@(private = "file")
test_stop :: proc(L: ^lua.State) -> c.int {
	lua.pushstring(L, TEST_STOP)
	return c.int(lua.error(L))
}

@(private = "file")
test_message :: proc(L: ^lua.State, idx: c.int, fallback: string) -> string {
	if lua.type(L, idx) == .STRING do return strings.clone(string(lua.tostring(L, idx)), context.temp_allocator)
	return fallback
}

@(private = "file")
test_value_text :: proc(L: ^lua.State, idx: c.int) -> string {
	sb := strings.builder_make(context.temp_allocator)
	Lua_FormatValue(&sb, L, idx, 0)
	return strings.to_string(sb)
}

// Test.step(frames = 1): runs that many frames.
@(private = "file")
lua_test_step :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !test_running(L, "Test.step") do return 0
	n := int(lua.L_optinteger(L, 1, 1))
	if n <= 0 do return 0
	gameTests.wait, gameTests.waitFrames = .Frames, n
	return c.int(lua.yield(L, 0))
}

// Test.wait_until(fn, frames = 600) -> ok: steps until fn() is true.
@(private = "file")
lua_test_wait_until :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !test_running(L, "Test.wait_until") do return 0
	lua.L_checktype(L, 1, i32(lua.Type.FUNCTION))
	lua.pushvalue(L, 1)
	gameTests.untilRef = lua.L_ref(L, lua.REGISTRYINDEX)
	gameTests.untilLeft = int(lua.L_optinteger(L, 2, 600))
	gameTests.wait = .Until
	return c.int(lua.yield(L, 0))
}

// Test.load_scene(name or file): goes to the scene; returns once it's up.
@(private = "file")
lua_test_load_scene :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !test_running(L, "Test.load_scene") do return 0
	game := test_game(L)
	name := string(lua.L_checkstring(L, 1))
	scene, ok := game.sceneManager.scenes[name]
	if !ok {
		if s := Game_FindSceneByFile(game, name); s != nil do scene, ok = s, true
	}
	if !ok {
		test_record_fail(L, fmt.tprintf("Test.load_scene: no scene '%s'", name))
		return test_stop(L)
	}
	ChangeScene_ByName(&game.sceneManager, scene.name)
	gameTests.wait, gameTests.waitFrames = .Scene, 2
	return c.int(lua.yield(L, 0))
}

// Test.press(action, frames = 2): the action down for that many frames.
@(private = "file")
lua_test_press :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !test_running(L, "Test.press") do return 0
	name := string(lua.L_checkstring(L, 1))
	frames := max(int(lua.L_optinteger(L, 2, 2)), 1)
	if !test_set_action(test_game(L), name, true) {
		test_record_fail(L, fmt.tprintf("Test.press: no action '%s' (or it has no key, mouse or pad binding)", name))
		return 0
	}
	append(&gameTests.releases, Test_Release{at = gameTests.frame + frames, action = strings.clone(name, Engine_HeapAllocator())})
	return 0
}

@(private = "file")
lua_test_hold :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !test_running(L, "Test.hold") do return 0
	name := string(lua.L_checkstring(L, 1))
	if !test_set_action(test_game(L), name, true) do test_record_fail(L, fmt.tprintf("Test.hold: no action '%s'", name))
	return 0
}

@(private = "file")
lua_test_release :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !test_running(L, "Test.release") do return 0
	_ = test_set_action(test_game(L), string(lua.L_checkstring(L, 1)), false)
	return 0
}

@(private = "file")
test_key_arg :: proc(L: ^lua.State, fn: string) -> (rl.KeyboardKey, bool) {
	name := string(lua.L_checkstring(L, 1))
	k, ok := parse_keyboard_key(name)
	if !ok do test_record_fail(L, fmt.tprintf("%s: no key '%s'", fn, name))
	return k, ok
}

// Test.press_key(key, frames = 2) / hold_key / release_key: a key itself.
@(private = "file")
lua_test_press_key :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !test_running(L, "Test.press_key") do return 0
	k, ok := test_key_arg(L, "Test.press_key")
	if !ok do return 0
	Input_SetSimulatedKey(&test_game(L).input, k, true)
	append(&gameTests.releases, Test_Release{at = gameTests.frame + max(int(lua.L_optinteger(L, 2, 2)), 1), key = k, isKey = true})
	return 0
}

@(private = "file")
lua_test_hold_key :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !test_running(L, "Test.hold_key") do return 0
	if k, ok := test_key_arg(L, "Test.hold_key"); ok do Input_SetSimulatedKey(&test_game(L).input, k, true)
	return 0
}

@(private = "file")
lua_test_release_key :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !test_running(L, "Test.release_key") do return 0
	if k, ok := test_key_arg(L, "Test.release_key"); ok do Input_SetSimulatedKey(&test_game(L).input, k, false)
	return 0
}

// Test.click(x, y): the left mouse button at a point (game units) - UI
// widgets and Input's mouse read it.
@(private = "file")
lua_test_click :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !test_running(L, "Test.click") do return 0
	x, y := arg_xy(L, 1)
	Runner_ApplyMouseEvent(test_game(L), Input_Script_Event{mouse = true, pos = {x, y}, down = true, button_change = true})
	append(&gameTests.releases, Test_Release{at = gameTests.frame + 2, mouse = true})
	return 0
}

@(private = "file")
lua_test_move_mouse :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !test_running(L, "Test.move_mouse") do return 0
	x, y := arg_xy(L, 1)
	Runner_ApplyMouseEvent(test_game(L), Input_Script_Event{mouse = true, pos = {x, y}})
	return 0
}

// Test.replay(name): plays tests/recordings/<name>.txt (recorded in Play);
// its scene loads first. Returns once it has played.
@(private = "file")
lua_test_replay :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !test_running(L, "Test.replay") do return 0
	game := test_game(L)
	name := string(lua.L_checkstring(L, 1))
	rel := name if strings.has_suffix(name, ".txt") else fmt.tprintf("%s/recordings/%s.txt", TESTS_DIR, name)
	text, ok := AssetManager_ReadFileString(&game.assetManager, rel, context.temp_allocator)
	if !ok {
		test_record_fail(L, fmt.tprintf("Test.replay: no recording '%s'", rel))
		return test_stop(L)
	}
	events, why := Runner_LoadInputScript(text, Engine_HeapAllocator())
	if why != "" {
		delete(events)
		test_record_fail(L, fmt.tprintf("Test.replay: %s: %s", rel, why))
		return test_stop(L)
	}
	delete(gameTests.replay)
	gameTests.replay = events
	gameTests.replayEnd = 0
	for ev in events do gameTests.replayEnd = max(gameTests.replayEnd, ev.frame)
	gameTests.replayStart = gameTests.frame
	// "# scene <file>": where it was recorded.
	for line in strings.split_lines(text, context.temp_allocator) {
		l := strings.trim_space(line)
		if strings.has_prefix(l, "# scene ") {
			if s := Game_FindSceneByFile(game, strings.trim_space(l[len("# scene "):])); s != nil do ChangeScene_ByName(&game.sceneManager, s.name)
			gameTests.replayStart = gameTests.frame + 2 // (once the scene is up)
			break
		}
	}
	gameTests.wait = .Replay
	return c.int(lua.yield(L, 0))
}

// Test.expect(condition, message): a failure if false; the test goes on.
@(private = "file")
lua_test_expect :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !test_running(L, "Test.expect") do return 0
	ok := bool(lua.toboolean(L, 1))
	if !ok do test_record_fail(L, test_message(L, 2, "expectation failed"))
	lua.pushboolean(L, b32(ok))
	return 1
}

// Test.expect_eq(actual, expected, message).
@(private = "file")
lua_test_expect_eq :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !test_running(L, "Test.expect_eq") do return 0
	ok := bool(lua.compare(L, 1, 2, .EQ))
	if !ok {
		what := test_message(L, 3, "values differ")
		test_record_fail(L, fmt.tprintf("%s: expected %s, got %s", what, test_value_text(L, 2), test_value_text(L, 1)))
	}
	lua.pushboolean(L, b32(ok))
	return 1
}

// Test.expect_near(actual, expected, tolerance = 0.001, message).
@(private = "file")
lua_test_expect_near :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !test_running(L, "Test.expect_near") do return 0
	a, b := f64(lua.L_checknumber(L, 1)), f64(lua.L_checknumber(L, 2))
	tol := f64(lua.L_optnumber(L, 3, 0.001))
	ok := abs(a - b) <= tol
	if !ok do test_record_fail(L, fmt.tprintf("%s: expected %g (within %g), got %g", test_message(L, 4, "not near"), b, tol, a))
	lua.pushboolean(L, b32(ok))
	return 1
}

// Test.require(condition, message): like expect, but a failure stops the test.
@(private = "file")
lua_test_require :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !test_running(L, "Test.require") do return 0
	if lua.toboolean(L, 1) do return 0
	test_record_fail(L, test_message(L, 2, "requirement failed"))
	return test_stop(L)
}

// Test.fail(message): a failure; the test stops.
@(private = "file")
lua_test_fail :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !test_running(L, "Test.fail") do return 0
	test_record_fail(L, test_message(L, 1, "failed"))
	return test_stop(L)
}

// Test.skip(reason): the test stops, counted as skipped.
@(private = "file")
lua_test_skip :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !test_running(L, "Test.skip") do return 0
	gameTests.skipped = true
	if gameTests.index >= 0 do tests_event("skipped", gameTests.cases[gameTests.index], fmt.tprintf(", \"message\": %s", tests_quote(test_message(L, 1, ""))))
	return test_stop(L)
}

// Test.frame(): frames since the test started.
@(private = "file")
lua_test_frame :: proc "c" (L: ^lua.State) -> c.int {
	lua.pushinteger(L, lua.Integer(gameTests.frame))
	return 1
}

// Test.timeout(frames): this test's limit (default a minute of game time).
@(private = "file")
lua_test_timeout :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !test_running(L, "Test.timeout") do return 0
	gameTests.timeout = max(int(lua.L_checkinteger(L, 1)), 1) + gameTests.frame
	return 0
}

// Test.is_running(): true inside a test (scripts can skip intros, music...).
@(private = "file")
lua_test_is_running :: proc "c" (L: ^lua.State) -> c.int {
	lua.pushboolean(L, b32(gameTests.active))
	return 1
}

// Script_RegisterTestModule: the global Test table (every game has it;
// most calls work only inside a test).
Script_RegisterTestModule :: proc(L: ^lua.State) {
	lua.newtable(L)
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "step", lua_test_step)
	reg(L, "wait_until", lua_test_wait_until)
	reg(L, "load_scene", lua_test_load_scene)
	reg(L, "press", lua_test_press)
	reg(L, "hold", lua_test_hold)
	reg(L, "release", lua_test_release)
	reg(L, "press_key", lua_test_press_key)
	reg(L, "hold_key", lua_test_hold_key)
	reg(L, "release_key", lua_test_release_key)
	reg(L, "click", lua_test_click)
	reg(L, "move_mouse", lua_test_move_mouse)
	reg(L, "replay", lua_test_replay)
	reg(L, "expect", lua_test_expect)
	reg(L, "expect_eq", lua_test_expect_eq)
	reg(L, "expect_near", lua_test_expect_near)
	reg(L, "require", lua_test_require)
	reg(L, "fail", lua_test_fail)
	reg(L, "skip", lua_test_skip)
	reg(L, "frame", lua_test_frame)
	reg(L, "timeout", lua_test_timeout)
	reg(L, "is_running", lua_test_is_running)
	lua.setglobal(L, "Test")
}
