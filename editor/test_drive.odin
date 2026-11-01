package editor

import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:mem/virtual"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"
import imgui_rl "lib/imgui/imgui_impl_raylib"

// ============================================================================
// Scripted UI Test-Drives
//
//   bin/editor --project <copy of a project> --drive tests/drive/<name>.drive [--shots <dir>]
//
// A drive script operates the editor the way a user does: it moves the mouse,
// clicks, drags, scrolls, presses keys and types - by injecting ImGui input
// events (the real mouse/keyboard are ignored meanwhile) - then checks the
// result with `expect` and captures screenshots. Widgets are addressed by IDs
// the UI registers each frame (Drive_Item), so scripts don't depend on pixel
// positions.
//
// Commands (one per line, `#` comments):
//   wait <frames>                       let frames pass
//   wait-until <expr> [timeout=<frames>] repeat until <expr> holds (default 600)
//   move|hover <target>                 move the mouse
//   click|rclick|dblclick <target>      press+release (left/right/double)
//   drag <from> <to> [steps]            press at <from>, move, release at <to>
//   scroll <target> <dy>                mouse wheel over <target>
//   key <chord>                         e.g. w, delete, f5, ctrl+s, ctrl+shift+z
//   type <text>                         text input (rest of line)
//   expect <expr>                       check, e.g. `expect selected == Player`
//   screenshot <name>                   save <shots>/<NN>_<name>.png
//   drop-files <target> <path>...      files dropped from the OS at <target>
//   dialog-files <path>...              answer for the next system file dialog
//   bench <frames> [label]              time that many uncapped frames, print a [bench] line
//   command <action id>                 run an editor action (a plugin's: plugin.<plugin>.<id>)
//   log <text> | quit
// Targets: @<item-id>  @world:<x>,<y>  @node:<Name>  <x>,<y>
// Expressions: <query> <op> <value>, op ∈ == != contains !contains ~= >= <=
//   (~= compares numbers / "x,y" pairs within 0.5). Queries: see Drive_Query.
// ============================================================================

Drive_Rect :: struct {
	min, max:           [2]f32,
	clipMin, clipMax:   [2]f32, // visible area of the item's window
	hasClip:            bool,
	noScroll:           bool,   // in a window the wheel doesn't scroll (the viewport zooms): never scroll it into view
}

// Drive_Callout: a labelled rectangle (screen points) for the docs' annotated
// screenshots (`annotate`; the docs site draws the numbered markers).
Drive_Callout :: struct {
	label:    string,
	min, max: [2]f32,
}

Drive_Step :: enum {
	Start,
	Pressed,
	Moving,
	Released,
}

TestDrive :: struct {
	enabled:    bool,
	scriptPath: string,
	shotsDir:   string,
	lines:      [dynamic]string,
	pc:         int,      // next line
	step:       int,      // sub-step of the current command
	wait:       int,      // frames to wait before continuing
	untilFrames: int,     // frames spent in the current wait-until
	mouse:      [2]f32,
	items:      map[string]Drive_Rect, // registered this frame
	prevItems:  map[string]Drive_Rect, // registered last frame (used for lookups)
	// The ids' copies: one arena per frame, swapped with the maps (a
	// frame's ids live until the frame after it is done).
	idArenas:   [2]virtual.Arena,
	idArena:    int,
	passed:     int,
	failed:     int,
	shotIndex:  int,
	report:     [dynamic]string,
	pendingShot: string,
	callouts:   [dynamic]Drive_Callout, // `annotate`: written beside the next screenshot
	finished:   bool,
	dragFrom, dragTo: [2]f32,
	dragSteps:  int,
	keyUp:      [dynamic]imgui.Key,
	held:       [dynamic]imgui.Key, // `hold` modifiers
	frame:      int,
}

GlobalDrive: TestDrive

// TestDrive_Init enables driving when --drive <script> is given.
TestDrive_Init :: proc(d: ^TestDrive) -> bool {
	for i := 0; i < len(os.args); i += 1 {
		if os.args[i] == "--drive" && i + 1 < len(os.args) do d.scriptPath = os.args[i + 1]
		if os.args[i] == "--shots" && i + 1 < len(os.args) do d.shotsDir = os.args[i + 1]
	}
	if d.scriptPath == "" do return false
	data, err := os.read_entire_file(d.scriptPath, context.allocator)
	if err != nil {
		fmt.eprintln("[DRIVE] cannot read script:", d.scriptPath)
		os.exit(2)
	}
	for line in strings.split_lines(string(data)) {
		append(&d.lines, strings.trim_space(line))
	}
	if d.shotsDir == "" {
		d.shotsDir = fmt.aprintf("editor_screenshots/drive/%s", filepath.stem(d.scriptPath))
	}
	_ = os.make_directory_all(d.shotsDir)
	if abs, err := os.get_absolute_path(d.shotsDir, context.allocator); err == nil do d.shotsDir = abs
	// $SHOTS / $PROJECT / $CRASHDIR expand to the screenshot / project / crash report dir.
	project := "assets/demo_project"
	for i := 0; i < len(os.args); i += 1 {
		if os.args[i] == "--project" && i + 1 < len(os.args) do project = os.args[i + 1]
	}
	for &l in d.lines {
		l, _ = strings.replace_all(l, "$SHOTS", d.shotsDir)
		l, _ = strings.replace_all(l, "$PROJECT", project)
		l, _ = strings.replace_all(l, "$CRASHDIR", e.Crash_Dir()) // (crash_reports.odin)
	}
	d.enabled = true
	d.items = make(map[string]Drive_Rect)
	d.prevItems = make(map[string]Drive_Rect)
	d.mouse = {-100, -100}
	imgui_rl.input_override = true
	fmt.printfln("[DRIVE] %s  (screenshots -> %s)", d.scriptPath, d.shotsDir)
	return true
}

// Set while drawing windows whose mouse wheel isn't scrolling (the viewport).
driveNoScroll: bool

// Drive_Item registers the last submitted ImGui item under `id` (no-op
// unless driving).
Drive_Item :: proc(id: string) {
	if !GlobalDrive.enabled do return
	mn := imgui.GetItemRectMin()
	mx := imgui.GetItemRectMax()
	wp := imgui.GetWindowPos()
	ws := imgui.GetWindowSize()
	GlobalDrive.items[drive_id(id)] = {
		min = {mn.x, mn.y}, max = {mx.x, mx.y},
		clipMin = {wp.x, wp.y}, clipMax = {wp.x + ws.x, wp.y + ws.y}, hasClip = true,
		noScroll = driveNoScroll,
	}
}

// drive_id: a copy of `id` that lives until the end of the next frame.
@(private = "file")
drive_id :: proc(id: string) -> string {
	return strings.clone(id, virtual.arena_allocator(&GlobalDrive.idArenas[GlobalDrive.idArena]))
}

// Drive_ItemRect registers an explicit rectangle under `id`.
// Drive_ItemRect registers a rect that isn't the last item; inWindow:
// it's inside the current window (scrolled into view like other items).
Drive_ItemRect :: proc(id: string, mn, mx: [2]f32, inWindow := false) {
	if !GlobalDrive.enabled do return
	if inWindow {
		wp := imgui.GetWindowPos()
		ws := imgui.GetWindowSize()
		GlobalDrive.items[drive_id(id)] = {min = mn, max = mx, clipMin = {wp.x, wp.y}, clipMax = {wp.x + ws.x, wp.y + ws.y}, hasClip = true}
		return
	}
	GlobalDrive.items[drive_id(id)] = {min = mn, max = mx}
}

// TestDrive_BeginFrame runs before ImGui's NewFrame: it advances the script
// and queues this frame's input events.
TestDrive_BeginFrame :: proc(d: ^TestDrive, state: ^EditorState) -> (quit: bool) {
	if !d.enabled do return false
	d.frame += 1

	io := imgui.GetIO()
	for k in d.keyUp do imgui.IO_AddKeyEvent(io, k, false)
	clear(&d.keyUp)
	imgui.IO_AddMousePosEvent(io, d.mouse.x, d.mouse.y)

	if d.finished do return true
	if d.wait > 0 {
		d.wait -= 1
		return false
	}
	// Let the first frames lay the UI out before touching it.
	if d.frame < 8 do return false

	for d.pc < len(d.lines) {
		line := d.lines[d.pc]
		if line == "" || strings.has_prefix(line, "#") {
			d.pc += 1
			continue
		}
		done := drive_exec(d, state, line)
		if !done do return false
		d.pc += 1
		d.step = 0
		d.untilFrames = 0
		if d.wait > 0 || d.pendingShot != "" do return false
	}
	drive_finish(d)
	return false
}

// TestDrive_EndFrame runs after the UI is drawn (before the buffer swap):
// screenshots see the finished frame.
TestDrive_EndFrame :: proc(d: ^TestDrive) {
	if !d.enabled do return
	// This frame's registrations become the next frame's lookup table (their
	// ids are in this frame's arena); the frame before's arena is reused.
	d.items, d.prevItems = d.prevItems, d.items
	clear(&d.items)
	d.idArena = 1 - d.idArena
	virtual.arena_free_all(&d.idArenas[d.idArena])
	if d.pendingShot == "" do return
	d.shotIndex += 1
	path := fmt.tprintf("%s/%02d_%s.png", d.shotsDir, d.shotIndex, d.pendingShot)
	img := rl.LoadImageFromScreen()
	rl.ExportImage(img, strings.clone_to_cstring(path, context.temp_allocator))
	rl.UnloadImage(img)
	append(&d.report, fmt.aprintf("![%s](%s)", d.pendingShot, filepath.base(path)))
	fmt.printfln("[DRIVE] screenshot %s", path)
	if len(d.callouts) > 0 do drive_write_callouts(d, path)
	d.pendingShot = ""
}

TestDrive_Finished :: proc(d: ^TestDrive) -> bool {
	return d.enabled && d.finished
}

@(private = "file")
drive_finish :: proc(d: ^TestDrive) {
	if d.finished do return
	d.finished = true
	summary := fmt.tprintf("%d passed, %d failed", d.passed, d.failed)
	fmt.printfln("[DRIVE] %s: %s", filepath.base(d.scriptPath), summary)
	sb := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&sb, "# %s\n\n**%s**\n\n", filepath.base(d.scriptPath), summary)
	for r in d.report do fmt.sbprintf(&sb, "%s\n\n", r)
	_ = os.write_entire_file(fmt.tprintf("%s/index.md", d.shotsDir), transmute([]u8)strings.to_string(sb))
}

TestDrive_ExitCode :: proc(d: ^TestDrive) -> int {
	return 1 if d.failed > 0 || !d.finished else 0
}

@(private = "file")
drive_fail :: proc(d: ^TestDrive, msg: string) {
	d.failed += 1
	text := fmt.aprintf("FAIL line %d: %s - %s", d.pc + 1, d.lines[d.pc], msg)
	fmt.printfln("[DRIVE] %s", text)
	append(&d.report, fmt.aprintf("- ❌ %s", text))
}

@(private = "file")
drive_pass :: proc(d: ^TestDrive, what: string) {
	d.passed += 1
	fmt.printfln("[DRIVE] ok   %s", what)
	append(&d.report, fmt.aprintf("- ✅ %s", what))
}

// --- command execution ------------------------------------------------------------------

@(private = "file")
split_cmd :: proc(line: string) -> (cmd, rest: string) {
	i := strings.index_byte(line, ' ')
	if i < 0 do return line, ""
	return line[:i], strings.trim_space(line[i + 1:])
}

// drive_exec performs (a step of) one command; returns true when finished.
@(private = "file")
drive_exec :: proc(d: ^TestDrive, state: ^EditorState, line: string) -> bool {
	io := imgui.GetIO()
	cmd, rest := split_cmd(line)
	switch cmd {
	case "wait":
		n, _ := strconv.parse_int(rest)
		d.wait = max(0, n - 1)
		return true
	case "wait-until":
		expr := rest
		timeout := 600
		if i := strings.index(rest, " timeout="); i >= 0 {
			timeout, _ = strconv.parse_int(rest[i + 9:])
			expr = rest[:i]
		}
		ok, actual, _ := drive_eval(state, expr)
		if ok {
			drive_pass(d, fmt.tprintf("%s (after %d frames)", expr, d.untilFrames))
			return true
		}
		d.untilFrames += 1
		if d.untilFrames >= timeout {
			drive_fail(d, fmt.tprintf("timed out after %d frames; last value %q", timeout, actual))
			return true
		}
		return false
	case "move", "hover":
		if scrolling, _ := drive_scroll_into_view(d, rest); scrolling do return false
		p, ok := drive_target(d, state, rest)
		if !ok {drive_fail(d, "target not found"); return true}
		d.mouse = p
		imgui.IO_AddMousePosEvent(io, p.x, p.y)
		d.wait = 1
		return true
	case "click", "rclick", "dblclick":
		button: i32 = 1 if cmd == "rclick" else 0
		if d.step == 0 {
			if scrolling, ok := drive_scroll_into_view(d, rest); scrolling do return false
			else if !ok {drive_fail(d, "target not found"); return true}
			p, ok := drive_target(d, state, rest)
			if !ok {drive_fail(d, "target not found"); return true}
			d.mouse = p
			imgui.IO_AddMousePosEvent(io, p.x, p.y)
			d.step = 1
			return false
		}
		clicks := 2 if cmd == "dblclick" else 1
		// steps: 1 down, 2 up, 3 down, 4 up
		if d.step <= clicks * 2 {
			imgui.IO_AddMouseButtonEvent(io, button, d.step % 2 == 1)
			d.step += 1
			return false
		}
		d.wait = 1
		return true
	case "drag":
		parts := strings.fields(rest, context.temp_allocator)
		if len(parts) < 2 {drive_fail(d, "drag <from> <to>"); return true}
		if d.step == 0 {
			if scrolling, ok := drive_scroll_into_view(d, parts[0]); scrolling do return false
			else if !ok {drive_fail(d, "target not found"); return true}
			from, ok1 := drive_target(d, state, parts[0])
			to, ok2 := drive_target(d, state, parts[1])
			if !ok1 || !ok2 {drive_fail(d, "target not found"); return true}
			d.dragFrom, d.dragTo = from, to
			d.dragSteps = 10
			if len(parts) >= 3 do d.dragSteps, _ = strconv.parse_int(parts[2])
			d.mouse = from
			imgui.IO_AddMousePosEvent(io, from.x, from.y)
			d.step = 1
			return false
		}
		if d.step == 1 {
			imgui.IO_AddMouseButtonEvent(io, 0, true)
			d.step = 2
			return false
		}
		k := d.step - 1
		if k <= d.dragSteps {
			t := f32(k) / f32(d.dragSteps)
			d.mouse = d.dragFrom + (d.dragTo - d.dragFrom) * t
			imgui.IO_AddMousePosEvent(io, d.mouse.x, d.mouse.y)
			d.step += 1
			return false
		}
		imgui.IO_AddMouseButtonEvent(io, 0, false)
		d.wait = 1
		return true
	case "scroll":
		parts := strings.fields(rest, context.temp_allocator)
		if len(parts) < 2 {drive_fail(d, "scroll <target> <dy>"); return true}
		if d.step == 0 {
			p, ok := drive_target(d, state, parts[0])
			if !ok {drive_fail(d, "target not found"); return true}
			d.mouse = p
			imgui.IO_AddMousePosEvent(io, p.x, p.y)
			d.step = 1
			return false
		}
		dy, _ := strconv.parse_f32(parts[1])
		imgui.IO_AddMouseWheelEvent(io, 0, dy)
		d.wait = 1
		return true
	case "key":
		mods, key, ok := parse_chord(rest)
		if !ok {drive_fail(d, fmt.tprintf("unknown key %q", rest)); return true}
		for m in mods do imgui.IO_AddKeyEvent(io, m, true)
		imgui.IO_AddKeyEvent(io, key, true)
		append(&d.keyUp, key)
		for m in mods do append(&d.keyUp, m)
		d.wait = 1
		return true
	case "hold":
		// hold shift / hold ctrl+alt: modifiers stay down for following
		// clicks/keys until `release`.
		mods, _, _ := parse_chord(strings.concatenate({rest, "+a"}, context.temp_allocator))
		for m in mods {
			imgui.IO_AddKeyEvent(io, m, true)
			append(&d.held, m)
		}
		d.wait = 1
		return true
	case "release":
		for m in d.held do imgui.IO_AddKeyEvent(io, m, false)
		clear(&d.held)
		d.wait = 1
		return true
	case "type":
		// "\s" types a space (the command text is trimmed).
		text, _ := strings.replace_all(rest, "\\s", " ", context.temp_allocator)
		imgui.IO_AddInputCharactersUTF8(io, strings.clone_to_cstring(text, context.temp_allocator))
		d.wait = 1
		return true
	case "expect":
		ok, actual, err := drive_eval(state, rest)
		if err != "" do drive_fail(d, err)
		else if ok do drive_pass(d, rest)
		else do drive_fail(d, fmt.tprintf("got %q", actual))
		return true
	case "screenshot":
		d.pendingShot = strings.clone(rest if rest != "" else "shot")
		return true
	case "annotate":
		// annotate <target> <label...>: a numbered callout on the next
		// screenshot (its <name>.annotations.json; the docs site draws it).
		// Targets: @<item id>, @window:<panel>, @node:<name>.
		target, _, label := strings.partition(rest, " ")
		r, ok := drive_target_rect(d, state, target)
		if !ok {drive_fail(d, fmt.tprintf("annotate: target not found: %s", target)); return true}
		append(&d.callouts, Drive_Callout{label = strings.clone(strings.trim_space(label)), min = r.min, max = r.max})
		return true
	case "exec":
		// Run a command to completion (e.g. the game on an exported .rayzr).
		desc := os.Process_Desc{command = strings.fields(rest, context.temp_allocator)}
		p, err := os.process_start(desc)
		if err != nil {
			drive_fail(d, fmt.tprintf("could not start: %v", err))
			return true
		}
		st, werr := os.process_wait(p, 120 * time.Second)
		if werr != nil || st.exit_code != 0 {
			drive_fail(d, fmt.tprintf("exit code %d (%v)", st.exit_code, werr))
		} else {
			drive_pass(d, fmt.tprintf("exec %s", rest))
		}
		return true
	case "drop-files":
		// drop-files <target> <path>...: files dropped from the OS file
		// manager at <target> ("\s" in a path is a space).
		parts := strings.fields(rest, context.temp_allocator)
		if len(parts) < 2 {drive_fail(d, "drop-files <target> <path>..."); return true}
		p, ok := drive_target(d, state, parts[0])
		if !ok {drive_fail(d, "target not found"); return true}
		d.mouse = p
		imgui.IO_AddMousePosEvent(io, p.x, p.y)
		driveDrop.pos = p
		for path in parts[1:] {
			unescaped, _ := strings.replace_all(path, "\\s", " ", context.temp_allocator)
			append(&driveDrop.paths, strings.clone(unescaped))
		}
		d.wait = 2
		return true
	case "dialog-files":
		// dialog-files <path>... : what the next system file dialog returns
		// (no paths = Cancel).
		paths := make([dynamic]string)
		for path in strings.fields(rest, context.temp_allocator) {
			unescaped, _ := strings.replace_all(path, "\\s", " ", context.temp_allocator)
			append(&paths, strings.clone(unescaped))
		}
		append(&driveDialogAnswers, paths[:])
		return true
	case "game-args":
		clear(&state.extraGameArgs)
		for a in strings.fields(rest) do append(&state.extraGameArgs, a)
		return true
	case "command":
		// command <action id>: runs an editor action (plugins' too: plugin.<id>.<command>).
		a := Action_Find(rest)
		if a == nil {
			drive_fail(d, fmt.tprintf("no action %q", rest))
			return true
		}
		if !Action_Run(state, a) do drive_fail(d, fmt.tprintf("action %q is disabled", rest))
		return true
	case "crash-rescan":
		// crash-rescan: read the crash folder again (reports a drive put there; crash_reports.odin).
		CrashReports_Rescan()
		return true
	case "bench":
		// bench <frames> [label]: time that many uncapped frames (frame_timing.odin).
		if d.step == 0 {
			fields := strings.fields(rest, context.temp_allocator)
			n := 300
			if len(fields) > 0 do n, _ = strconv.parse_int(fields[0])
			FrameTiming_SetUncapped(true, false)
			FrameTiming_BenchStart(max(n, 1))
			d.step = 1
			return false
		}
		if !FrameTiming_BenchDone() do return false
		label := "frame"
		if fields := strings.fields(rest, context.temp_allocator); len(fields) > 1 do label = fields[1]
		line := FrameTiming_BenchReport(label)
		fmt.println(line)
		append(&d.report, fmt.aprintf("`%s`", line))
		FrameTiming_SetUncapped(false, false)
		return true
	case "log":
		fmt.printfln("[DRIVE] %s", rest)
		append(&d.report, fmt.aprintf("**%s**", rest))
		return true
	case "quit":
		d.pc = len(d.lines)
		return true
	}
	drive_fail(d, fmt.tprintf("unknown command %q", cmd))
	return true
}

@(private = "file")
parse_chord :: proc(s: string) -> (mods: [dynamic]imgui.Key, key: imgui.Key, ok: bool) {
	mods = make([dynamic]imgui.Key, context.temp_allocator)
	parts := strings.split(strings.to_lower(s, context.temp_allocator), "+", context.temp_allocator)
	for p, i in parts {
		if i < len(parts) - 1 {
			switch p {
			case "ctrl": append(&mods, imgui.Key.ImGuiMod_Ctrl, imgui.Key.LeftCtrl)
			case "shift": append(&mods, imgui.Key.ImGuiMod_Shift, imgui.Key.LeftShift)
			case "alt": append(&mods, imgui.Key.ImGuiMod_Alt, imgui.Key.LeftAlt)
			case "cmd", "super": append(&mods, imgui.Key.ImGuiMod_Super, imgui.Key.LeftSuper)
			case: return mods, .None, false
			}
			continue
		}
		key, ok = key_by_name(p)
	}
	return
}

@(private = "file")
key_by_name :: proc(name: string) -> (imgui.Key, bool) {
	switch name {
	case "enter", "return": return .Enter, true
	case "esc", "escape": return .Escape, true
	case "tab": return .Tab, true
	case "space": return .Space, true
	case "backspace": return .Backspace, true
	case "delete", "del": return .Delete, true
	case "up": return .UpArrow, true
	case "down": return .DownArrow, true
	case "left": return .LeftArrow, true
	case "right": return .RightArrow, true
	case "home": return .Home, true
	case "end": return .End, true
	case "pageup": return .PageUp, true
	case "pagedown": return .PageDown, true
	case "slash", "/": return .Slash, true
	case "backslash", "\\": return .Backslash, true
	case "comma", ",": return .Comma, true
	case "period", ".": return .Period, true
	case "minus", "-": return .Minus, true
	case "equal", "=": return .Equal, true
	case "lbracket", "[": return .LeftBracket, true
	case "rbracket", "]": return .RightBracket, true
	}
	if len(name) == 1 {
		c := name[0]
		if c >= 'a' && c <= 'z' do return imgui.Key(int(imgui.Key.A) + int(c - 'a')), true
		if c >= '0' && c <= '9' do return imgui.Key(int(imgui.Key._0) + int(c - '0')), true
	}
	if len(name) >= 2 && name[0] == 'f' {
		if n, ok := strconv.parse_int(name[1:]); ok && n >= 1 && n <= 12 {
			return imgui.Key(int(imgui.Key.F1) + n - 1), true
		}
	}
	return .None, false
}

// drive_target resolves a target to window pixels.
// Drive_Window registers the current window's rectangle as "window:<id>"
// (annotated screenshots point at whole panels).
Drive_Window :: proc(id: string) {
	if !GlobalDrive.enabled do return
	wp := imgui.GetWindowPos()
	ws := imgui.GetWindowSize()
	Drive_ItemRect(fmt.tprintf("window:%s", id), {wp.x, wp.y}, {wp.x + ws.x, wp.y + ws.y})
}

// drive_target_rect: a target's rectangle - a registered item / window, or a
// node's position (a small box around it).
@(private = "file")
drive_target_rect :: proc(d: ^TestDrive, state: ^EditorState, t: string) -> (r: Drive_Rect, ok: bool) {
	if strings.has_prefix(t, "@") && !strings.has_prefix(t, "@node:") && !strings.has_prefix(t, "@world:") {
		r, ok = d.prevItems[t[1:]]
		return
	}
	p := drive_target(d, state, t) or_return
	return Drive_Rect{min = p - 28, max = p + 28}, true
}

// drive_write_callouts writes <shot>.annotations.json: the window size and
// each callout's rectangle (points; the PNG may be larger on HiDPI screens).
@(private = "file")
drive_write_callouts :: proc(d: ^TestDrive, png: string) {
	w: e.Json_Writer
	w.sb = strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&w.sb, "{{\n  \"width\": %d,\n  \"height\": %d,\n  \"callouts\": [", rl.GetScreenWidth(), rl.GetScreenHeight())
	for c, i in d.callouts {
		strings.write_string(&w.sb, "," if i > 0 else "")
		strings.write_string(&w.sb, "\n    {\"label\": ")
		e.Json_String(&w, c.label)
		fmt.sbprintf(&w.sb, ", \"x\": %.0f, \"y\": %.0f, \"w\": %.0f, \"h\": %.0f}}", c.min.x, c.min.y, c.max.x - c.min.x, c.max.y - c.min.y)
		delete(c.label)
	}
	strings.write_string(&w.sb, "\n  ]\n}\n")
	clear(&d.callouts)
	path := fmt.tprintf("%s.annotations.json", strings.trim_suffix(png, ".png"))
	_ = os.write_entire_file(path, transmute([]u8)strings.to_string(w.sb))
}

@(private = "file")
drive_target :: proc(d: ^TestDrive, state: ^EditorState, t_in: string) -> ([2]f32, bool) {
	// "+dx,dy" offsets any target by screen pixels (e.g. @node:Ship+80,0).
	t := t_in
	offset: [2]f32
	if strings.has_prefix(t, "@node:") || strings.has_prefix(t, "@world:") {
		if i := strings.last_index_byte(t, '+'); i > 0 {
			if o, ok := parse_vec2(t[i + 1:]); ok {
				offset = o
				t = t[:i]
			}
		}
	}
	if strings.has_prefix(t, "@world:") {
		v, ok := parse_vec2(t[7:])
		return Viewport_WorldToScreen(state, v) + offset, ok
	}
	if strings.has_prefix(t, "@node:") {
		n := drive_find_node(state, t[6:])
		if n == nil do return {}, false
		return Viewport_WorldToScreen(state, n.globalPosition) + offset, true
	}
	if strings.has_prefix(t, "@") {
		id := t[1:]
		offset: [2]f32
		if i := strings.index_byte(id, '+'); i >= 0 {
			offset, _ = parse_vec2(id[i + 1:])
			id = id[:i]
		}
		r, ok := d.prevItems[id]
		if !ok do return {}, false
		return (r.min + r.max) * 0.5 + offset, true
	}
	return parse_vec2(t)
}

// drive_scroll_into_view scrolls the target's window (mouse wheel over it,
// like a user) until the target is fully visible. Returns scrolling=true
// while it is still scrolling; ok=false if the id isn't registered (after
// giving the UI a few frames to show it).
@(private = "file")
drive_scroll_into_view :: proc(d: ^TestDrive, target: string) -> (scrolling: bool, ok: bool) {
	if !strings.has_prefix(target, "@") || strings.has_prefix(target, "@world:") || strings.has_prefix(target, "@node:") {
		return false, true
	}
	id := target[1:]
	if i := strings.index_byte(id, '+'); i >= 0 do id = id[:i]
	r, found := d.prevItems[id]
	if !found {
		// Popups/menus appear a frame or two after they're opened.
		d.untilFrames += 1
		if d.untilFrames < 10 do return true, true
		return false, false
	}
	if !r.hasClip || r.noScroll do return false, true
	io := imgui.GetIO()
	// Only items smaller than their window that are (partly) clipped need
	// scrolling; large items (the viewport image) never do.
	clipH := r.clipMax.y - r.clipMin.y
	if r.max.y - r.min.y > clipH * 0.6 do return false, true
	hiddenTop := r.min.y < r.clipMin.y + 20
	hiddenBottom := r.max.y > r.clipMax.y - 2
	if hiddenTop || hiddenBottom {
		d.untilFrames += 1
		if d.untilFrames > 120 do return false, true // give up; click anyway
		centre := (r.clipMin + r.clipMax) * 0.5
		d.mouse = centre
		imgui.IO_AddMousePosEvent(io, centre.x, centre.y)
		imgui.IO_AddMouseWheelEvent(io, 0, 1 if hiddenTop else -1)
		return true, true
	}
	return false, true
}

@(private = "file")
parse_vec2 :: proc(s: string) -> ([2]f32, bool) {
	parts := strings.split(s, ",", context.temp_allocator)
	if len(parts) != 2 do return {}, false
	x, ok1 := strconv.parse_f32(strings.trim_space(parts[0]))
	y, ok2 := strconv.parse_f32(strings.trim_space(parts[1]))
	return {x, y}, ok1 && ok2
}

// drive_find_node finds a node by name, or by path "Parent/Child".
drive_find_node :: proc(state: ^EditorState, name: string) -> ^e.Node {
	if state.activeScene == nil || state.activeScene.manager == nil do return nil
	if strings.contains_rune(name, '/') {
		n, ok := e.GetNodeByPath(state.activeScene, state.activeScene.rootNode, strings.concatenate({"/", name}, context.temp_allocator))
		return n if ok else nil
	}
	return e.Scene_FindNodeByName(state.activeScene, name)
}

// --- expressions & queries --------------------------------------------------------------

DRIVE_OPS :: [?]string{" !contains ", " contains ", " == ", " != ", " ~= ", " >= ", " <= "}

@(private = "file")
drive_eval :: proc(state: ^EditorState, expr_in: string) -> (ok: bool, actual: string, err: string) {
	// "x ==" / "x !=" compare against the empty string.
	expr := expr_in
	if strings.has_suffix(expr, " ==") || strings.has_suffix(expr, " !=") do expr = strings.concatenate({expr, " "}, context.temp_allocator)
	for op in DRIVE_OPS {
		i := strings.index(expr, op)
		if i < 0 do continue
		query := strings.trim_space(expr[:i])
		want := strings.trim_space(expr[i + len(op):])
		// Escapes: \n newline, \t tab, \s space (values are trimmed).
		want, _ = strings.replace_all(want, "\\n", "\n", context.temp_allocator)
		want, _ = strings.replace_all(want, "\\t", "\t", context.temp_allocator)
		want, _ = strings.replace_all(want, "\\s", " ", context.temp_allocator)
		value, qok := Drive_Query(state, query)
		if !qok do return false, value, fmt.tprintf("unknown query %q", query)
		switch strings.trim_space(op) {
		case "==": return value == want, value, ""
		case "!=": return value != want, value, ""
		case "contains": return strings.contains(value, want), value, ""
		case "!contains": return !strings.contains(value, want), value, ""
		case "~=": return approx_equal(value, want), value, ""
		case ">=", "<=":
			a, ok1 := strconv.parse_f32(value)
			b, ok2 := strconv.parse_f32(want)
			if !ok1 || !ok2 do return false, value, ""
			return (a >= b) if strings.trim_space(op) == ">=" else (a <= b), value, ""
		}
	}
	// A bare query must be "true".
	value, qok := Drive_Query(state, strings.trim_space(expr))
	if !qok do return false, value, fmt.tprintf("unknown query %q", expr)
	return value == "true", value, ""
}

@(private = "file")
approx_equal :: proc(a, b: string) -> bool {
	pa := strings.split(a, ",", context.temp_allocator)
	pb := strings.split(b, ",", context.temp_allocator)
	if len(pa) != len(pb) do return false
	for i in 0 ..< len(pa) {
		x, ok1 := strconv.parse_f32(strings.trim_space(pa[i]))
		y, ok2 := strconv.parse_f32(strings.trim_space(pb[i]))
		if !ok1 || !ok2 || math.abs(x - y) > 0.5 do return false
	}
	return true
}

@(private = "file")
fmt_vec :: proc(v: [2]f32) -> string {
	return fmt.tprintf("%.1f,%.1f", v.x, v.y)
}

// Drive_Query answers a named question about the editor's state.
//   selected | scene | tool | nodes | modified | modified-count | undo | redo
//   game (running|stopped) | build (running|idle) | log (all console text)
//   last-log | add-node-open | item:<id> (visible|missing)
//   file:<project-relative path> (contents, "" if missing)
//   node:<Name>.<field> with field = exists type parent position global material
//     rotation scale visible enabled children script prop.<path> script.<prop>
Drive_Query :: proc(state: ^EditorState, q: string) -> (string, bool) {
	if strings.has_prefix(q, "code.") do return Code_DriveQuery(q)
	if strings.has_prefix(q, "plugin:") do return Plugins_DriveQuery(q)
	if strings.has_prefix(q, "crash-") do return CrashReports_DriveQuery(q)
	if strings.has_prefix(q, "aseprite-") do return Aseprite_DriveQuery(q)
	if strings.has_prefix(q, "panel-open:") do return "true" if PluginPanels_IsOpen(q[len("panel-open:"):]) else "false", true
	if strings.has_prefix(q, "import.") do return AssetImport_DriveQuery(q)
	if strings.has_prefix(q, "fb.") do return FileBrowser_DriveQuery(q)
	if strings.has_prefix(q, "lge.") do return LevelGenEditor_DriveQuery(q)
	if strings.has_prefix(q, "ldtk.") do return LdtkPanel_DriveQuery(state, q)
	if strings.has_prefix(q, "level.") do return LevelEditor_DriveQuery(state, q)
	if strings.has_prefix(q, "shape") do return ShapeEdit_DriveQuery(state, q)
	if strings.has_prefix(q, "atlas.") do return AtlasRegion_DriveQuery(q)
	switch q {
	case "palette.open": return "true" if Palette_IsOpen() else "false", true
	case "viewport.min-alpha":
		// The lowest alpha in the viewport's texture: 255 when it's opaque
		// (soft edges don't let the panel behind show through).
		if state.renderTexture.id == 0 do return "", false
		img := rl.LoadImageFromTexture(state.renderTexture.texture)
		defer rl.UnloadImage(img)
		px := ([^]rl.Color)(img.data)[:img.width * img.height]
		lo := u8(255)
		for c in px do lo = min(lo, c.a)
		return fmt.tprint(lo), true
	case "viewport.max-luma":
		// The brightest pixel in the viewport (0-255): whether bright things
		// (additive particles, ...) were drawn at all.
		if state.renderTexture.id == 0 do return "", false
		img := rl.LoadImageFromTexture(state.renderTexture.texture)
		defer rl.UnloadImage(img)
		px := ([^]rl.Color)(img.data)[:img.width * img.height]
		hi: int
		for c in px do hi = max(hi, (int(c.r) * 299 + int(c.g) * 587 + int(c.b) * 114) / 1000)
		return fmt.tprint(hi), true
	case "selection":
		sb := strings.builder_make(context.temp_allocator)
		for n, i in state.selection {
			if i > 0 do strings.write_string(&sb, ",")
			strings.write_string(&sb, n.name)
		}
		return strings.to_string(sb), true
	case "selection-count": return fmt.tprint(len(state.selection)), true
	case "quit-prompt": return "true" if state.quitRequested else "false", true
	case "simulating": return "true" if state.isSimulating else "false", true
	case "clipboard-nodes": return "true" if Editor_HasClipboardNodes() else "false", true
	case "anim-preview": return "paused" if AnimationPanel_PreviewPaused() else "playing", true
	case "preview-audio": return "playing" if state.previewAudioPlaying else "stopped", true // the Assets' Preview panel
	case "preview-anim": return fmt.tprintf("%s %d", "playing" if state.previewAnimPlaying else "paused", len(state.previewAnimFrames)), true
	case "asset-selected": return filepath.base(state.selectedAssetPath), true
	case "audio-preview": return "playing" if state.selectedNode != nil && AudioPreview_Playing(state.selectedNode) else "stopped", true
	case "sound-next": // the selected Sound Effect's own Sequential place (#217: previews don't move it)
		if n := state.selectedNode; n != nil && n.typeId == e.SoundNode do return fmt.tprint((cast(^e.SoundNode)n).nextIndex), true
		return "", true
	case "anim-keys": return AnimKeys_Summary(), true // selected keys in the timeline
	case "anim-zoom": return fmt.tprintf("%.2f", AnimationPanel_Zoom()), true
	case "slicer-selection": return Slicer_Selection(), true
	case "slicer-zoom": return fmt.tprintf("%.2f", Slicer_Zoom()), true
	case "hidden-tab-bars": return fmt.tprint(Dock_HiddenTabBars(editorDockspaceID)), true
	case "anim-names":
		// "<name>,<name>,..." of the selected AnimationPlayer, the current one in [brackets].
		if state.selectedNode == nil || state.selectedNode.typeId != e.AnimationPlayerNode do return "", true
		apn := cast(^e.AnimationPlayerNode)state.selectedNode
		sb := strings.builder_make(context.temp_allocator)
		for a, i in apn.animations {
			if i > 0 do strings.write_string(&sb, ",")
			fmt.sbprintf(&sb, "[%s]" if i == apn.animationIndex else "%s", a.name)
		}
		return strings.to_string(sb), true
	case "anim-info":
		// "frames=<n> range=<first>-<last> reverse=<b> fps=<f> default=<name>" (1-based) of the current animation.
		if state.selectedNode == nil || state.selectedNode.typeId != e.AnimationPlayerNode do return "", true
		apn := cast(^e.AnimationPlayerNode)state.selectedNode
		a := e.AnimationPlayerNode_GetAnimation(apn)
		if a == nil do return "none", true
		return fmt.tprintf("frames=%d range=%d-%d reverse=%t fps=%v default=%s", e.Animation_SourceCount(a), a.startFrame + 1, a.endFrame + 1, a.reverse, a.fps, apn.defaultAnimation), true
	case "anim":
		// "<animation>:<frame>/<length>:<tracks>" of the selected AnimationPlayer.
		if state.selectedNode == nil || state.selectedNode.typeId != e.AnimationPlayerNode do return "", true
		apn := cast(^e.AnimationPlayerNode)state.selectedNode
		a := e.AnimationPlayerNode_GetAnimation(apn)
		if a == nil do return "none", true
		return fmt.tprintf("%s:%d/%d:%d", a.name, apn.currentFrame - a.startFrame + 1, e.Animation_Length(a), len(a.tracks)), true
	case "shortcuts-open": return "true" if showShortcutsWindow else "false", true
	case "usages": return fmt.tprint(AssetUsages_Count()), true
	case "workspace": return currentWorkspace, true
	case "dialog-start": return nativeDialogLastStart, true // where the last file dialog opened
	case "last-dir:import": return GlobalSettings.lastImportDir, true
	case "last-dir:export": return GlobalSettings.lastExportDir, true
	case "last-dir:projects": return GlobalSettings.lastProjectDir, true
	case "theme": return GlobalSettings.theme.name, true // the saved theme
	case "theme-panel": return theme_color_text(UI_BG_PANEL), true // the colour panels draw with now
	case "node-icons":
		// "<distinct icons>/<node types>" in the Add Node catalogue.
		seen := make(map[string]bool, allocator = context.temp_allocator)
		for entry in NODE_CATALOG do seen[entry.icon] = true
		return fmt.tprintf("%d/%d", len(seen), len(NODE_CATALOG)), true
	case "search-total", "search-files": return Code_SearchQuery(q)
	case "smg-selected", "smg-zoom", "smg-pan", "smg-ways": return StateGraph_Query(q)
	case "bt-tree", "bt-live", "bt-view": return BehaviorTree_Query(state, q)
	case "goap-graph", "goap-live": return Goap_Query(state, q)
	case "mixer-buses", "mixer-voices": return MixerPanel_Query(q)
	case "remote-debug-draw", "remote-connected", "remote-paused", "remote-frame", "remote-steps", "remote-reloads", "remote-nodes", "remote-names", "remote-view", "remote-selected": return RemoteGame_Query(q)
	case "guides":
		if state.activeScene == nil do return "", true
		parts := make([dynamic]string, context.temp_allocator)
		for g in state.activeScene.guides[:state.activeScene.guideCount] do append(&parts, fmt.tprintf("%s=%v", "x" if g.vertical else "y", g.pos))
		return strings.join(parts[:], ",", context.temp_allocator), true
	case "insp-help": return fmt.tprintf("%s: %s", inspectorHelp.title, inspectorHelp.doc), true
	case "insp-help-path": return inspectorHelp.path, true
	case "insp-flash": return string(inspFlash.path[:inspFlash.pathLen]) if Inspector_FlashActive(inspFlash.node, string(inspFlash.path[:inspFlash.pathLen])) else "", true
	case "selected-bounds":
		// The selected node's bounds in the world: "minx,miny,maxx,maxy" (rounded).
		if state.selectedNode == nil do return "", true
		corners, _ := Node_Bounds(state, state.selectedNode)
		lo, hi := corners[0], corners[0]
		for c in corners {lo = {min(lo.x, c.x), min(lo.y, c.y)}; hi = {max(hi.x, c.x), max(hi.y, c.y)}}
		return fmt.tprintf("%d,%d,%d,%d", int(lo.x), int(lo.y), int(hi.x), int(hi.y)), true
	case "bottom-tab": return fmt.tprint(BottomPanel_Tab(state)), true
	}
	switch q {
	case "selected":
		return state.selectedNode.name if state.selectedNode != nil else "", true
	case "selection-alive":
		// Every selected node is a live node of the active scene (no stale pointers).
		if state.selectedNode != nil && !node_in_scene(state, state.selectedNode) do return "false", true
		for n in state.selection do if !node_in_scene(state, n) do return "false", true
		return "true", true
	case "scene":
		return state.activeScenePath, true
	case "scene-tabs":
		return fmt.tprint(len(SceneTabs_Open())), true
	case "tool":
		return strings.to_lower(fmt.tprint(state.toolMode), context.temp_allocator), true
	case "zoom":
		return fmt.tprintf("%.2f", state.cameraZoom), true
	case "undo-bytes":
		return fmt.tprint(Undo_StoreBytes()), true
	case "tile-chunks":
		return fmt.tprint(e.TileCache_Stats()), true
	case "camera":
		return fmt_vec(state.cameraPos), true
	case "nodes":
		n := 0
		if state.activeScene != nil && state.activeScene.manager != nil {
			for node in state.activeScene.manager.nodes do if node != nil do n += 1
		}
		return fmt.tprint(n), true
	case "modified":
		return "true" if Editor_SceneIsModified(state, state.activeScene) else "false", true
	case "modified-count":
		return fmt.tprint(Editor_ModifiedSceneCount(state)), true
	case "undo":
		return fmt.tprint(len(state.undoStack)), true
	case "redo":
		return fmt.tprint(len(state.redoStack)), true
	case "game":
		return "running" if state.gameProcessRunning else "stopped", true
	case "build":
		return "running" if state.buildRunning else "idle", true
	case "particle-preview": return "on" if particlePreview else "off", true
	case "refs-pending": return fmt.tprint(NodeRefs_Pending()), true
	case "ref-section": return ScriptReference_Selected() if ScriptReference_IsOpen() else "", true
	case "ref-api": return ScriptReference_Api(), true
	case "runtime-diags": return fmt.tprint(CodeRuntime_Count()), true
	case "game-pid": return fmt.tprint(state.gameProcess.pid if state.gameProcessRunning else 0), true
	case "last-played": return state.lastPlayedScene if state.lastPlayedScene != "" else "project", true
	case "log":
		sb := strings.builder_make(context.temp_allocator)
		for l in state.logs do fmt.sbprintf(&sb, "%s\n", l.message)
		return strings.to_string(sb), true
	case "last-log":
		return state.logs[len(state.logs) - 1].message if len(state.logs) > 0 else "", true
	case "add-node-open":
		return "true" if showAddNodeDialog else "false", true
	case "project-settings-open":
		return "true" if state.showProjectSettings else "false", true
	}
	// node-delta:A,B -> global position of B minus A ("dx,dy").
	if strings.has_prefix(q, "node-delta:") {
		parts := strings.split(q[11:], ",", context.temp_allocator)
		if len(parts) != 2 do return "<need A,B>", true
		a := drive_find_node(state, parts[0])
		b := drive_find_node(state, parts[1])
		if a == nil || b == nil do return "<no node>", true
		return fmt_vec(b.globalPosition - a.globalPosition), true
	}
	if strings.has_prefix(q, "remote-prop:") do return RemoteGame_Query(q)
	if strings.has_prefix(q, "debug-") do return Debug_Query(q)
	if strings.has_prefix(q, "window-h:") {
		// Height of the window an item is in ("window-h:bottom:console").
		r, ok := GlobalDrive.prevItems[q[len("window-h:"):]]
		if !ok || !r.hasClip do return "<none>", true
		return fmt.tprintf("%.0f", r.clipMax.y - r.clipMin.y), true
	}
	if strings.has_prefix(q, "folder-open:") {
		return "true" if assetFolderOpen[q[len("folder-open:"):]] else "false", true
	}
	if q == "noderef.open" do return "true" if NodeReference_IsOpen() else "false", true
	if q == "noderef.page" do return NodeReference_Page(), true
	if strings.has_prefix(q, "component-instances:") do return fmt.tprint(Editor_ComponentInstanceCount(state, q[len("component-instances:"):])), true
	if strings.has_prefix(q, "item:") {
		_, ok := GlobalDrive.prevItems[q[5:]]
		return "visible" if ok else "missing", true
	}
	if strings.has_prefix(q, "file:") {
		path, _ := filepath.join({state.projectPath, q[5:]}, context.temp_allocator)
		data, err := os.read_entire_file(path, context.temp_allocator)
		return string(data) if err == nil else "", true
	}
	if strings.has_prefix(q, "abs-file:") {
		data, err := os.read_entire_file(q[9:], context.temp_allocator)
		return string(data) if err == nil else "", true
	}
	if strings.has_prefix(q, "node:") {
		body := q[5:]
		dot := strings.index_byte(body, '.')
		name, field := body, "exists"
		if dot >= 0 do name, field = body[:dot], body[dot + 1:]
		n := drive_find_node(state, name)
		if field == "exists" do return "true" if n != nil else "false", true
		if n == nil do return "<no node>", true
		switch field {
		case "type": return e.Node_TypeName(n), true
		case "class": return e.Node_ClassName(n), true // its custom node type's name, else its type
		case "custom-type": return n.customType, true  // its custom node type's .node.json ("" = none)
		case "component": return n.componentPath, true // its component file ("" = not an instance root)
		case "component-missing": return "true" if n.componentMissing else "false", true
		case "parent":
			p := e.GetParent(state.activeScene.manager, n)
			return p.name if p != nil else "", true
		case "position": return fmt_vec(n.position), true
		case "locked": return "true" if n.editorLocked else "false", true
		case "editor-hidden": return "true" if n.editorHidden else "false", true
		case "tags": return strings.join(n.tags[:], ",", context.temp_allocator), true
		case "global": return fmt_vec(n.globalPosition), true
		case "rotation": return fmt.tprintf("%.1f", n.rotation), true
		case "scale": return fmt.tprintf("%.2f,%.2f", n.scale.x, n.scale.y), true
		case "origin": return fmt.tprintf("%.2f,%.2f", n.pivot.x, n.pivot.y), true
		case "visible": return "true" if n.renderable else "false", true
		case "material":
			// "<shader> <blend>" ("" without a material)
			if n.material == nil do return "", true
			return fmt.tprintf("%s %s", n.material.shader, e.Material_BlendName(n.material.blend)), true
		case "enabled": return "true" if n.enabled else "false", true
		case "particles": return fmt.tprint(ParticleAlive(n)), true // live particles of an emitter
		case "state":
			// A StateMachineNode's current state ("" until it runs) and state count.
			if n.typeId != e.StateMachineNode do return "<not a state machine>", true
			sm := cast(^e.StateMachineNode)n
			return fmt.tprintf("%s/%d", e.StateMachine_CurrentName(sm), len(sm.states)), true
		case "children":
			c := e.GetChildren(state.activeScene.manager, n)
			defer delete(c)
			return fmt.tprint(len(c)), true
		case "child-names":
			names := make([dynamic]string, context.temp_allocator)
			for c in e.GetChildrenView(state.activeScene.manager, n) do if c != nil && !c.transient do append(&names, c.name)
			return strings.join(names[:], ",", context.temp_allocator), true
		case "path-points":
			if n.typeId != e.PathNode do return "<not a path>", true
			return fmt.tprint(len((cast(^e.PathNode)n).points)), true
		case "tiles":
			if n.typeId != e.TileMapNode do return "<not a tile map>", true
			tm := cast(^e.TileMapNode)n
			count := 0
			for t in tm.tiles do if t >= 0 do count += 1
			return fmt.tprint(count), true
		case "tile-components":
			if n.typeId != e.TileMapNode do return "<not a tile map>", true
			return fmt.tprint(len(e.TileMapNode_Components(cast(^e.TileMapNode)n))), true
		case "connections":
			sb := strings.builder_make(context.temp_allocator)
			for c, i in n.signalConnections {
				if i > 0 do strings.write_string(&sb, ";")
				fmt.sbprintf(&sb, "%s->%s:%s", c.signal, c.target, c.method)
			}
			return strings.to_string(sb), true
		case "overrides":
			return strings.join(e.Node_ComponentOverrides(state.activeScene.manager, n), ",", context.temp_allocator), true
		case "uid":
			return n.uid, true
		case "script":
			if n.scriptInstance == nil do return "", true
			return (cast(^e.ScriptInstance)n.scriptInstance).modulePath, true
		}
		if strings.has_prefix(field, "prop.") {
			p, ok := e.Node_FindProperty(n, field[5:])
			if !ok do return "<no property>", true
			return property_text(p), true
		}
		if strings.has_prefix(field, "script.") {
			if n.scriptInstance == nil do return "<no script>", true
			inst := cast(^e.ScriptInstance)n.scriptInstance
			v, ok := inst.properties[field[7:]]
			if !ok do return "<no script property>", true
			switch v.type {
			case .Float: return fmt.tprintf("%g", v.valFloat), true
			case .Int: return fmt.tprint(v.valInt), true
			case .Boolean: return "true" if v.valBool else "false", true
			case .String: return v.valString, true
			case .Vector2: return fmt_vec(v.valVec2), true
			case .Color: return fmt.tprint(v.valColor), true
			}
		}
		return "", false
	}
	return "", false
}

@(private = "file")
property_text :: proc(p: e.Node_Property) -> string {
	switch p.kind {
	case .Float: return fmt.tprintf("%g", e.Property_GetFloat(p))
	case .Int: return fmt.tprint(e.Property_GetInt(p))
	case .Bool: return "true" if (^bool)(p.ptr)^ else "false"
	case .Vec2: return fmt_vec((^[2]f32)(p.ptr)^)
	case .Color: return e.Color_ToHex((^rl.Color)(p.ptr)^)
	case .Enum:
		names := e.Property_EnumNames(p)
		i := e.Property_GetEnumIndex(p)
		return names[i] if i < len(names) else ""
	case .Bit_Set: return fmt.tprint(e.Property_GetInt(p))
	case .String: return (^string)(p.ptr)^
	case .String_List: return strings.join(e.Property_GetList(p), "|", context.temp_allocator)
	}
	return ""
}
