package engine

import "core:c"
import "core:fmt"
import "core:log"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"
import lua "lua54"
import b2 "vendor:box2d"
import rl "vendor:raylib"

// ============================================================================
// The developer console (#285): a toggleable console in the running game -
// debug builds and the editor's Play always, release builds when the
// project turns it on ("debug": {"console_in_release"}). ` (the project's
// "console_key") opens it. A line is a command (help lists them; games add
// their own with Console.register) or else Lua, run in the game's state.
//
// Besides commands it has a perf overlay (perf), debug drawing (physics,
// nav, camera, outlines) and time controls (pause, step, timescale).
// While it is open the game gets no keys.
// ============================================================================

Console_Draw :: enum u8 {Navigation, Camera, Outlines}

Console_Line :: struct {
	text:  string, // (heap)
	color: rl.Color,
}

Console_Command :: struct {
	help:    string, // (heap)
	builtin: proc(game: ^Game, args: []string),
	L:       ^lua.State, // a Lua command: its function in L's registry
	ref:     c.int,
}

Dev_Console :: struct {
	enabled:   bool,
	open:      bool,
	key:       rl.KeyboardKey,
	input:     [dynamic]u8,
	lines:     [dynamic]Console_Line,
	scroll:    int, // lines up from the newest
	history:   [dynamic]string,
	histIdx:   int, // len(history): the line being typed
	commands:  map[string]Console_Command,
	perf:      bool,
	draws:     bit_set[Console_Draw],
	paused:    bool,
	steps:     int,
	frameMs:   [120]f32, // (the perf graph)
	frameIdx:  int,
}

devConsole: Dev_Console

CONSOLE_MAX_LINES :: 400
CONSOLE_MAX_HISTORY :: 100

// Console_Enable turns the console on for this run (the runner: debug
// builds, the editor's Play, or the project's release setting). `key` ""
// is the backquote.
Console_Enable :: proc(game: ^Game, key := "") {
	context.allocator = Engine_HeapAllocator()
	devConsole.enabled = true
	devConsole.key = .GRAVE
	if key != "" {
		if k, ok := parse_keyboard_key(key); ok do devConsole.key = k
	}
	console_add_builtins()
	Console_Print(fmt.tprintf("Rayzr developer console - %s to close, help for commands, anything else is Lua.", Console_KeyName(devConsole.key)), {150, 160, 180, 255})
}

// Console_Shutdown frees the console (the game ending; tests).
Console_Shutdown :: proc() {
	context.allocator = Engine_HeapAllocator()
	delete(devConsole.input)
	for l in devConsole.lines do delete(l.text)
	delete(devConsole.lines)
	for h in devConsole.history do delete(h)
	delete(devConsole.history)
	for name, cmd in devConsole.commands {
		delete(name)
		delete(cmd.help)
		if cmd.L != nil && cmd.ref != 0 do lua.L_unref(cmd.L, lua.REGISTRYINDEX, cmd.ref)
	}
	delete(devConsole.commands)
	devConsole = {}
}

Console_KeyName :: proc(k: rl.KeyboardKey) -> string {
	if k == .GRAVE do return "`"
	return fmt.tprintf("%v", k)
}

// Console_Print adds a line (split at newlines) - script logs, results.
Console_Print :: proc(text: string, color := rl.Color{220, 224, 232, 255}) {
	if !devConsole.enabled do return
	context.allocator = Engine_HeapAllocator()
	rest := text
	for line in strings.split_lines_iterator(&rest) {
		if len(devConsole.lines) >= CONSOLE_MAX_LINES {
			delete(devConsole.lines[0].text)
			ordered_remove(&devConsole.lines, 0)
		}
		append(&devConsole.lines, Console_Line{strings.clone(line), color})
	}
	devConsole.scroll = 0
}

// Console_Log: a script log line (Log.info / warn / error, print, script
// errors) - shown coloured by level.
Console_Log :: proc(level: log.Level, text: string) {
	if !devConsole.enabled do return
	switch level {
	case .Debug, .Info: Console_Print(text)
	case .Warning: Console_Print(text, {250, 204, 21, 255})
	case .Error, .Fatal: Console_Print(text, {248, 113, 113, 255})
	}
}

// Console_Register adds a command run by a builtin proc (help: one line).
Console_Register :: proc(name, help: string, fn: proc(game: ^Game, args: []string)) {
	context.allocator = Engine_HeapAllocator()
	console_drop(name)
	devConsole.commands[strings.clone(name)] = {help = strings.clone(help), builtin = fn}
}

@(private = "file")
console_drop :: proc(name: string) {
	context.allocator = Engine_HeapAllocator()
	if name not_in devConsole.commands do return
	key, cmd := delete_key(&devConsole.commands, name)
	{
		delete(key)
		delete(cmd.help)
		if cmd.L != nil && cmd.ref != 0 do lua.L_unref(cmd.L, lua.REGISTRYINDEX, cmd.ref)
	}
}

// Console_Frame (before the frame runs): the toggle key, typing, and the
// pause / step state. true: this frame is a step (run it at 1/60 s).
Console_Frame :: proc(game: ^Game, frameSeconds: f32) -> (step: bool) {
	if !devConsole.enabled do return false
	devConsole.frameMs[devConsole.frameIdx] = frameSeconds * 1000
	devConsole.frameIdx = (devConsole.frameIdx + 1) % len(devConsole.frameMs)
	if rl.IsWindowReady() {
		if rl.IsKeyPressed(devConsole.key) {
			devConsole.open = !devConsole.open
			for rl.GetCharPressed() != 0 {} // (not the key's own character)
		} else if devConsole.open {
			console_type(game)
		}
	}
	game.input.keyboardBlocked = devConsole.open
	if devConsole.paused {
		game.frozen = devConsole.steps <= 0
		if devConsole.steps > 0 {
			devConsole.steps -= 1
			return true
		}
	} else if !game.linkPaused {
		game.frozen = false
	}
	return false
}

@(private = "file")
console_type :: proc(game: ^Game) {
	context.allocator = Engine_HeapAllocator()
	for ch := rl.GetCharPressed(); ch != 0; ch = rl.GetCharPressed() {
		if ch < 32 || ch == '`' && devConsole.key == .GRAVE do continue
		bytes, n := utf8.encode_rune(ch)
		append(&devConsole.input, ..bytes[:n])
	}
	pressed :: proc(k: rl.KeyboardKey) -> bool {return rl.IsKeyPressed(k) || rl.IsKeyPressedRepeat(k)}
	if pressed(.BACKSPACE) && len(devConsole.input) > 0 {
		// (a whole UTF-8 character)
		i := len(devConsole.input) - 1
		for i > 0 && devConsole.input[i] & 0xC0 == 0x80 do i -= 1
		resize(&devConsole.input, i)
	}
	if rl.IsKeyPressed(.ESCAPE) {
		if len(devConsole.input) > 0 do clear(&devConsole.input)
		else do devConsole.open = false
	}
	if pressed(.UP) && devConsole.histIdx > 0 {
		devConsole.histIdx -= 1
		console_set_input(devConsole.history[devConsole.histIdx])
	}
	if pressed(.DOWN) && devConsole.histIdx < len(devConsole.history) {
		devConsole.histIdx += 1
		console_set_input(devConsole.history[devConsole.histIdx] if devConsole.histIdx < len(devConsole.history) else "")
	}
	if pressed(.PAGE_UP) do devConsole.scroll = min(devConsole.scroll + 10, max(len(devConsole.lines) - 1, 0))
	if pressed(.PAGE_DOWN) do devConsole.scroll = max(devConsole.scroll - 10, 0)
	if wheel := rl.GetMouseWheelMove(); wheel != 0 {
		devConsole.scroll = clamp(devConsole.scroll + int(wheel * 3), 0, max(len(devConsole.lines) - 1, 0))
	}
	if rl.IsKeyPressed(.TAB) do Console_Complete()
	if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) {
		line := strings.clone(string(devConsole.input[:]), context.temp_allocator)
		clear(&devConsole.input)
		Console_Exec(game, line)
	}
}

@(private = "file")
console_set_input :: proc(s: string) {
	clear(&devConsole.input)
	append(&devConsole.input, ..transmute([]u8)s)
}

// Console_Complete: Tab completes the command being typed (to the longest
// common start; several matches are listed).
Console_Complete :: proc() {
	typed := string(devConsole.input[:])
	if strings.contains_rune(typed, ' ') do return
	matches := make([dynamic]string, context.temp_allocator)
	for name in devConsole.commands do if strings.has_prefix(name, typed) do append(&matches, name)
	if len(matches) == 0 do return
	if len(matches) == 1 {
		console_set_input(strings.concatenate({matches[0], " "}, context.temp_allocator))
		return
	}
	common := matches[0]
	for m in matches[1:] {
		n := 0
		for n < len(common) && n < len(m) && common[n] == m[n] do n += 1
		common = common[:n]
	}
	if len(common) > len(typed) {
		console_set_input(common)
		return
	}
	slice_sort_strings(matches[:])
	Console_Print(strings.join(matches[:], "  ", context.temp_allocator), {150, 160, 180, 255})
}

@(private = "file")
slice_sort_strings :: proc(s: []string) {
	for i in 1 ..< len(s) {
		for j := i; j > 0 && s[j] < s[j - 1]; j -= 1 do s[j], s[j - 1] = s[j - 1], s[j]
	}
}

// Console_Exec runs a line: a command (its first word) or else Lua.
Console_Exec :: proc(game: ^Game, line: string) {
	context.allocator = Engine_HeapAllocator()
	src := strings.trim_space(line)
	if src == "" do return
	if len(devConsole.history) == 0 || devConsole.history[len(devConsole.history) - 1] != src {
		if len(devConsole.history) >= CONSOLE_MAX_HISTORY {
			delete(devConsole.history[0])
			ordered_remove(&devConsole.history, 0)
		}
		append(&devConsole.history, strings.clone(src))
	}
	devConsole.histIdx = len(devConsole.history)
	Console_Print(strings.concatenate({"> ", src}, context.temp_allocator), {125, 211, 252, 255})
	words := strings.fields(src, context.temp_allocator)
	if cmd, ok := devConsole.commands[words[0]]; ok {
		if cmd.builtin != nil {
			cmd.builtin(game, words[1:])
		} else if cmd.L != nil {
			console_call_lua(cmd, words[1:])
		}
		return
	}
	L := game.scriptManager.L
	text, ok := Lua_Eval(L, src, context.temp_allocator)
	if ok && text == "ok" do return
	Console_Print(text, {220, 224, 232, 255} if ok else {248, 113, 113, 255})
}

@(private = "file")
console_call_lua :: proc(cmd: Console_Command, args: []string) {
	L := cmd.L
	top := lua.gettop(L)
	defer lua.settop(L, top)
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(cmd.ref))
	lua.createtable(L, c.int(len(args)), 0)
	for a, i in args {
		lua.pushstring(L, strings.clone_to_cstring(a, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	if lua.pcall(L, 1, 1, 0) != 0 {
		Console_Print(string(lua.tostring(L, -1)), {248, 113, 113, 255})
		return
	}
	if lua.type(L, -1) != .NIL {
		sb := strings.builder_make(context.temp_allocator)
		if lua.type(L, -1) == .STRING do strings.write_string(&sb, string(lua.tostring(L, -1)))
		else do Lua_FormatValue(&sb, L, -1, 0)
		Console_Print(strings.to_string(sb))
	}
}

// ----------------------------------------------------------------------------
// Built-in commands
// ----------------------------------------------------------------------------

@(private = "file")
console_add_builtins :: proc() {
	Console_Register("help", "help [command]: the commands, or one's help", proc(game: ^Game, args: []string) {
		if len(args) > 0 {
			if cmd, ok := devConsole.commands[args[0]]; ok do Console_Print(cmd.help)
			else do Console_Print(fmt.tprintf("no command %q", args[0]), {248, 113, 113, 255})
			return
		}
		names := make([dynamic]string, context.temp_allocator)
		for name in devConsole.commands do append(&names, name)
		slice_sort_strings(names[:])
		for name in names do Console_Print(fmt.tprintf("  %s", devConsole.commands[name].help))
		Console_Print("Anything else runs as Lua: Scene.find_node(\"Player\"), GameState.lives = 9", {150, 160, 180, 255})
	})
	Console_Register("clear", "clear: empty the console", proc(game: ^Game, args: []string) {
		for l in devConsole.lines do delete(l.text, Engine_HeapAllocator())
		clear(&devConsole.lines)
	})
	Console_Register("scene", "scene [name or file]: go to a scene (none: list them)", proc(game: ^Game, args: []string) {
		if len(args) == 0 {
			cur := game.sceneManager.currentScene
			for name in game.sceneManager.scenes do Console_Print(fmt.tprintf("  %s%s", name, "  (current)" if cur != nil && cur.name == name else ""))
			return
		}
		scene, ok := game.sceneManager.scenes[args[0]]
		if !ok {
			if s := Game_FindSceneByFile(game, args[0]); s != nil do scene, ok = s, true
		}
		if !ok {
			Console_Print(fmt.tprintf("no scene %q", args[0]), {248, 113, 113, 255})
			return
		}
		ChangeScene_ByName(&game.sceneManager, scene.name)
	})
	Console_Register("reload", "reload: restart the current scene", proc(game: ^Game, args: []string) {
		if s := game.sceneManager.currentScene; s != nil do ChangeScene_ByName(&game.sceneManager, s.name)
	})
	Console_Register("timescale", "timescale [scale] [tag]: the game's (or a tag's) time scale - 0.25 slow motion, 1 normal", proc(game: ^Game, args: []string) {
		tag := args[1] if len(args) > 1 else ""
		if len(args) > 0 {
			v, ok := strconv.parse_f32(args[0])
			if !ok || v < 0 {
				Console_Print("timescale: a number, 0 or more", {248, 113, 113, 255})
				return
			}
			GameFeel_SetTimeScale(game, v, tag)
		}
		Console_Print(fmt.tprintf("time scale%s%s: %g", " of " if tag != "" else "", tag, GameFeel_TimeScale(game, tag)))
	})
	Console_Register("pause", "pause: freeze the game (again: go on); step runs a frame at a time", proc(game: ^Game, args: []string) {
		devConsole.paused = !devConsole.paused
		devConsole.steps = 0
		Console_Print("paused - step [frames] steps, pause goes on" if devConsole.paused else "running")
	})
	Console_Register("step", "step [frames]: pause and run that many frames (default 1)", proc(game: ^Game, args: []string) {
		n := 1
		if len(args) > 0 do n = max(strconv.parse_int(args[0]) or_else 1, 1)
		devConsole.paused = true
		devConsole.steps += n
	})
	Console_Register("perf", "perf: show / hide the performance overlay", proc(game: ^Game, args: []string) {
		devConsole.perf = !devConsole.perf
	})
	Console_Register("physics", "physics: show / hide colliders, joints and areas", proc(game: ^Game, args: []string) {
		game.physicsWorld.drawPhysicsDebug = !game.physicsWorld.drawPhysicsDebug
		Console_Print(fmt.tprintf("physics shapes %s", "on" if game.physicsWorld.drawPhysicsDebug else "off"))
	})
	toggle :: proc(d: Console_Draw, what: string) {
		devConsole.draws ~= {d}
		Console_Print(fmt.tprintf("%s %s", what, "on" if d in devConsole.draws else "off"))
	}
	Console_Register("nav", "nav: show / hide navigation regions and their blocked cells", proc(game: ^Game, args: []string) {toggle(.Navigation, "navigation")})
	Console_Register("camera", "camera: show / hide the camera's view and limits", proc(game: ^Game, args: []string) {toggle(.Camera, "camera bounds")})
	Console_Register("outlines", "outlines: show / hide every node's bounds (a dot where a node has none)", proc(game: ^Game, args: []string) {toggle(.Outlines, "outlines")})
	Console_Register("quit", "quit: end the game", proc(game: ^Game, args: []string) {game.shouldQuit = true})
}

// ----------------------------------------------------------------------------
// Drawing
// ----------------------------------------------------------------------------

// Console_DrawScreen (in window pixels, over the frame): the perf overlay
// and the console.
Console_DrawScreen :: proc(game: ^Game) {
	if !devConsole.enabled || !rl.IsWindowReady() do return
	if devConsole.paused do console_badge(game)
	defer if devConsole.perf do console_draw_perf(game) // (over the console)
	if !devConsole.open do return
	sw, sh := f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())
	fs: f32 = 18 if sh >= 600 else 14
	lineH := fs + 4
	h := max(sh * 0.45, lineH * 6)
	rl.DrawRectangleRec({0, 0, sw, h}, {12, 14, 22, 228})
	rl.DrawRectangleRec({0, h - 2, sw, 2}, {125, 211, 252, 200})
	font := rl.GetFontDefault()
	// The input line.
	inputY := h - lineH - 6
	rl.DrawRectangleRec({0, inputY - 3, sw, lineH + 4}, {255, 255, 255, 14})
	prompt := fmt.ctprintf("> %s", string(devConsole.input[:]))
	rl.DrawTextEx(font, prompt, {8, inputY}, fs, 1, rl.WHITE)
	w := rl.MeasureTextEx(font, prompt, fs, 1).x
	rl.DrawRectangleRec({8 + w + 2, inputY, 2, fs}, rl.WHITE) // (the cursor; steady, so captures compare)
	// The lines, newest at the bottom.
	y := inputY - lineH - 2
	for i := len(devConsole.lines) - 1 - devConsole.scroll; i >= 0 && y > -lineH; i -= 1 {
		l := devConsole.lines[i]
		rl.DrawTextEx(font, strings.clone_to_cstring(l.text, context.temp_allocator), {8, y}, fs, 1, l.color)
		y -= lineH
	}
	if devConsole.scroll > 0 {
		rl.DrawTextEx(font, fmt.ctprintf("(%d newer lines - Page Down)", devConsole.scroll), {sw - 260, inputY - lineH - 2}, fs * 0.8, 1, {150, 160, 180, 255})
	}
}

@(private = "file")
console_badge :: proc(game: ^Game) {
	sw := f32(rl.GetScreenWidth())
	text: cstring = "PAUSED (console: pause / step)"
	w := rl.MeasureTextEx(rl.GetFontDefault(), text, 16, 1).x
	rl.DrawRectangleRec({sw * 0.5 - w * 0.5 - 8, f32(rl.GetScreenHeight()) - 34, w + 16, 26}, {0, 0, 0, 190})
	rl.DrawTextEx(rl.GetFontDefault(), text, {sw * 0.5 - w * 0.5, f32(rl.GetScreenHeight()) - 29}, 16, 1, {250, 204, 21, 255})
}

// Console_Stats: the perf overlay's numbers (tests read them too).
Console_Stats :: struct {
	avgMs, worstMs: f32,
	nodes, bodies:  int,
	drawn, culled:  int,
}

Console_GetStats :: proc(game: ^Game) -> (s: Console_Stats) {
	n := 0
	for ms in devConsole.frameMs do if ms > 0 {
		s.avgMs += ms
		s.worstMs = max(s.worstMs, ms)
		n += 1
	}
	if n > 0 do s.avgMs /= f32(n)
	if scene := game.sceneManager.currentScene; scene != nil && scene.manager != nil {
		for node in scene.manager.nodes do if node != nil do s.nodes += 1
	}
	if b2.World_IsValid(game.physicsWorld.worldId) do s.bodies = int(b2.World_GetCounters(game.physicsWorld.worldId).bodyCount)
	s.drawn, s.culled = renderStats.drawn, renderStats.culled
	return
}

@(private = "file")
console_draw_perf :: proc(game: ^Game) {
	s := Console_GetStats(game)
	sw := f32(rl.GetScreenWidth())
	w, h: f32 = 250, 150
	x, y := sw - w - 8, f32(8)
	rl.DrawRectangleRec({x, y, w, h}, {0, 0, 0, 190})
	font := rl.GetFontDefault()
	fps := 1000 / s.avgMs if s.avgMs > 0 else 0
	lines := [?]string {
		fmt.tprintf("%.0f fps   %.2f ms (worst %.1f)", fps, s.avgMs, s.worstMs),
		fmt.tprintf("nodes %d   bodies %d", s.nodes, s.bodies),
		fmt.tprintf("drawn %d   culled %d", s.drawn, s.culled),
	}
	for l, i in lines do rl.DrawTextEx(font, strings.clone_to_cstring(l, context.temp_allocator), {x + 8, y + 6 + f32(i) * 18}, 16, 1, {190, 242, 100, 255})
	// The frame times: 16.7 ms (60 fps) is the line.
	gx, gy, gw, gh := x + 8, y + 64, w - 16, h - 72
	rl.DrawRectangleLinesEx({gx, gy, gw, gh}, 1, {255, 255, 255, 40})
	scale := gh / 33.3
	rl.DrawLineV({gx, gy + gh - 16.7 * scale}, {gx + gw, gy + gh - 16.7 * scale}, {255, 255, 255, 60})
	count := len(devConsole.frameMs)
	bw := gw / f32(count)
	for i in 0 ..< count {
		ms := devConsole.frameMs[(devConsole.frameIdx + i) % count]
		if ms <= 0 do continue
		bh := min(ms * scale, gh)
		col := rl.Color{190, 242, 100, 220} if ms <= 17.5 else (rl.Color{250, 204, 21, 220} if ms <= 34 else rl.Color{248, 113, 113, 220})
		rl.DrawRectangleRec({gx + f32(i) * bw, gy + gh - bh, max(bw - 0.5, 1), bh}, col)
	}
}

// Console_DrawWorld (after the scene's layers, in the game's frame):
// navigation regions, the camera's view and limits, node outlines.
Console_DrawWorld :: proc(game: ^Game) {
	if !devConsole.enabled || devConsole.draws == {} || !rl.IsWindowReady() do return
	scene := game.sceneManager.currentScene
	if scene == nil || scene.manager == nil do return
	cam := scene.camera
	if cam != nil && !(cam.enabled && cam.isCurrent) do cam = nil
	vw, vh: f32 = 1280, 720
	if game.virtualSize.x > 0 do vw, vh = game.virtualSize.x, game.virtualSize.y
	zoom: f32 = 1
	if cam != nil {
		c2 := CameraNode_GetCamera2D(cam, vw, vh)
		zoom = max(c2.zoom, 0.01)
		rl.BeginMode2D(c2)
	}
	inCam :: proc(cam: ^CameraNode, n: ^Node) -> bool {return cam != nil && n.layer in cam.targetLayers}
	for n in scene.manager.nodes {
		if n == nil || !n.enabled || n == scene.rootNode || n.isUI do continue
		if .Navigation in devConsole.draws && n.typeId == NavigationRegionNode && inCam(cam, n) {
			NavRegion_Draw(cast(^NavigationRegionNode)n, true)
		}
		if .Outlines in devConsole.draws && (inCam(cam, n) || cam == nil) {
			if r, ok := Node_RenderBounds(n); ok do rl.DrawRectangleLinesEx(r, 1 / zoom, {244, 114, 182, 230})
			rl.DrawCircleV(n.globalPosition, 1.5 / zoom, {244, 114, 182, 230})
		}
	}
	if .Camera in devConsole.draws && cam != nil {
		c2 := CameraNode_GetCamera2D(cam, vw, vh)
		view := rl.Rectangle{c2.target.x - c2.offset.x / zoom, c2.target.y - c2.offset.y / zoom, vw / zoom, vh / zoom}
		rl.DrawRectangleLinesEx({view.x + 2 / zoom, view.y + 2 / zoom, view.width - 4 / zoom, view.height - 4 / zoom}, 2 / zoom, {52, 211, 153, 220})
		rl.DrawLineV({c2.target.x - 6 / zoom, c2.target.y}, {c2.target.x + 6 / zoom, c2.target.y}, {52, 211, 153, 220})
		rl.DrawLineV({c2.target.x, c2.target.y - 6 / zoom}, {c2.target.x, c2.target.y + 6 / zoom}, {52, 211, 153, 220})
		if cam.hasLimits {
			rl.DrawRectangleLinesEx({cam.leftLimit, cam.topLimit, cam.rightLimit - cam.leftLimit, cam.bottomLimit - cam.topLimit}, 2 / zoom, {250, 204, 21, 220})
		}
	}
	if cam != nil do rl.EndMode2D()
	// UI nodes: in screen space.
	if .Outlines in devConsole.draws {
		for n in scene.manager.nodes do if n != nil && n.enabled && n.isUI {
			rl.DrawRectangleLinesEx(UI_GetElementRect(cast(^UIElement)n), 1, {96, 165, 250, 160})
		}
	}
}

// ----------------------------------------------------------------------------
// Lua: Console.register / unregister / print / is_open / open / execute
// ----------------------------------------------------------------------------

@(private = "file")
lua_console_register :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	name := lua.L_checkstring(L, 1)
	help := string(lua.tostring(L, 2)) if lua.type(L, 2) == .STRING else ""
	lua.L_checktype(L, 3, i32(lua.Type.FUNCTION))
	if strings.contains_rune(string(name), ' ') || len(name) == 0 {
		lua.L_error(L, "Console.register: a command name is one word")
		return 0
	}
	context.allocator = Engine_HeapAllocator()
	console_drop(string(name))
	lua.pushvalue(L, 3)
	ref := lua.L_ref(L, lua.REGISTRYINDEX)
	h := help if help != "" else string(name)
	devConsole.commands[strings.clone(string(name))] = {help = strings.clone(h), L = L, ref = ref}
	return 0
}

@(private = "file")
lua_console_unregister :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	console_drop(string(lua.L_checkstring(L, 1)))
	return 0
}

@(private = "file")
lua_console_print :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sb := strings.builder_make(context.temp_allocator)
	nargs := lua.gettop(L)
	for i in 1 ..= nargs {
		n: c.size_t
		str := lua.L_tostring(L, c.int(i), &n)
		if str != nil do strings.write_string(&sb, string(str)[:n])
		lua.pop(L, 1)
		if i < nargs do strings.write_string(&sb, "\t")
	}
	Console_Print(strings.to_string(sb))
	return 0
}

@(private = "file")
lua_console_is_open :: proc "c" (L: ^lua.State) -> c.int {
	lua.pushboolean(L, b32(devConsole.open))
	return 1
}

@(private = "file")
lua_console_is_enabled :: proc "c" (L: ^lua.State) -> c.int {
	lua.pushboolean(L, b32(devConsole.enabled))
	return 1
}

@(private = "file")
lua_console_open :: proc "c" (L: ^lua.State) -> c.int {
	if devConsole.enabled do devConsole.open = lua.isnone(L, 1) || bool(lua.toboolean(L, 1))
	return 0
}

@(private = "file")
lua_console_execute :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	line := strings.clone(string(lua.L_checkstring(L, 1)), context.temp_allocator)
	sm := get_script_manager(L)
	if sm != nil && sm.game != nil && devConsole.enabled do Console_Exec(sm.game, line)
	return 0
}

// Script_RegisterConsole: the global Console table.
Script_RegisterConsole :: proc(L: ^lua.State) {
	lua.newtable(L)
	lua.pushcfunction(L, lua_console_register)
	lua.setfield(L, -2, "register")
	lua.pushcfunction(L, lua_console_unregister)
	lua.setfield(L, -2, "unregister")
	lua.pushcfunction(L, lua_console_print)
	lua.setfield(L, -2, "print")
	lua.pushcfunction(L, lua_console_is_open)
	lua.setfield(L, -2, "is_open")
	lua.pushcfunction(L, lua_console_is_enabled)
	lua.setfield(L, -2, "is_enabled")
	lua.pushcfunction(L, lua_console_open)
	lua.setfield(L, -2, "open")
	lua.pushcfunction(L, lua_console_execute)
	lua.setfield(L, -2, "execute")
	lua.setglobal(L, "Console")
}
