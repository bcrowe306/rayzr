package engine

import "core:fmt"
import "core:log"
import os "osx"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// Generic game runner: plays a data-only project (a project directory or a
// packaged .rayzr) - scenes, scripts, assets - with no game-specific code.
// Used by the demo binary (`--project`) and by the standalone runner/
// program that "Export Standalone Game" ships next to a game's .rayzr.
// ============================================================================

Run_Options :: struct {
	projectPath:    string, // project directory or .rayzr package
	screenshotPath: string, // save a screenshot after a few frames, then quit
	maxFrames:      int,
	hidden:         bool,
	startScene:     string, // project-relative scene file to start in
	dumpScenePath:  string, // write the running scene's JSON (tests)
	userDataDir:    string, // Save data folder instead of the platform's
	benchFrames:    int,    // --bench N: N uncapped frames, then print frame timings and quit
	uncapped:       bool,   // --uncapped: no vsync, no frame cap, a frame time readout (also --bench)
	noRenderCache:  bool,   // --no-render-cache: no tile chunk cache, no draw reordering (comparisons)
	editorLink:     bool,   // --editor-link: driven by the editor over stdin/stdout (editor_link.odin)
	crashTest:      string, // --crash-test panic | segv | abort: crash once loaded (crash report tests)
	inputScript:    string, // --input-script <file>: keys pressed on given frames (Runner_LoadInputScript; game tests)
	trace:          string, // --trace <node name>: print "@trace <frame> <scene> <x> <y>" every frame (game tests, bots)
	console:        string, // --console "perf; outlines; open": the developer console on, these lines run once loaded (tests; dev_console.odin)
}

// An --input-script event: `key` goes down / up at `frame`; pad events
// (pad >= 0) press a button, move an axis, or plug a simulated pad in / out.
Input_Script_Event :: struct {
	frame:  int,
	key:    rl.KeyboardKey,
	down:   bool,
	pad:    i32, // -1: a key
	kind:   Input_Script_Pad,
	button: rl.GamepadButton,
	axis:   rl.GamepadAxis,
	value:  f32,
	name:   string, // connect
	mouse:  bool,   // a mouse event: moves to pos, the left button down / up (`down`, `button_change`)
	touch:  i32,    // a finger's id (1..10; 0: not a touch event): at pos, down / up
	pos:    [2]f32,
	button_change: bool,
}

Input_Script_Pad :: enum u8 {Button, Axis, Connect, Disconnect}

// Runner_LoadInputScript reads an input script - one event per line:
//
//   # frame  key    down | up | tap [frames]
//   30       RIGHT  down
//   90       RIGHT  up
//   100      SPACE  tap 8        (down at 100, up 8 frames later; default 2)
//
//   # gamepads (simulated): pad1..pad4
//   5        pad2   connect Xbox Wireless Controller   (the name: the rest)
//   20       pad2   RIGHT_FACE_DOWN tap 5               (buttons: down / up / tap)
//   30       pad2   LEFT_X 1.0                           (axes: a value, kept)
//   60       pad2   disconnect
//
//   # the mouse (game units; the left button): click / down / up / move
//   40       mouse  640 360 click        (down at 40, up 2 frames later)
//   50       mouse  100 80 move
//   (UI widgets and Lua's Input.*mouse* read it; the UI's own keys -
//   Tab, arrows, Enter on a widget - stop once a mouse event played)
//
//   # fingers (game units): touch1..touch10  x y  down / move / up / tap [frames]
//   40       touch1 200 600 down     (a finger lands)
//   45       touch1 260 600 move     (and drags)
//   60       touch1 260 600 up
//   70       touch2 900 600 tap      (down, up 2 frames later)
//
// Keys are raylib key names as in project.json bindings (SPACE, LEFT, A, ...),
// pad buttons / axes raylib's (RIGHT_FACE_DOWN, LEFT_X, ...).
// The frames are the runner's (fixed 1/60 s steps with --frames /
// --dump-scene / --screenshot), so a script plays the same every time.
Runner_LoadInputScript :: proc(text: string, allocator := context.allocator) -> (events: [dynamic]Input_Script_Event, err: string) {
	events = make([dynamic]Input_Script_Event, allocator)
	for raw, n in strings.split_lines(text, context.temp_allocator) {
		line := strings.trim_space(raw)
		if i := strings.index_byte(line, '#'); i >= 0 do line = strings.trim_space(line[:i])
		if line == "" do continue
		f := strings.fields(line, context.temp_allocator)
		if len(f) < 3 do return events, fmt.tprintf("line %d: want <frame> <key> down|up|tap", n + 1)
		frame, fok := strconv.parse_int(f[0])
		if !fok do return events, fmt.tprintf("line %d: bad frame %q", n + 1, f[0])
		if lower := strings.to_lower(f[1], context.temp_allocator); len(lower) == 4 && strings.has_prefix(lower, "pad") && lower[3] >= '1' && lower[3] <= '4' {
			pad := i32(lower[3] - '1')
			ev := Input_Script_Event{frame = frame, pad = pad}
			switch {
			case f[2] == "connect":
				ev.kind = .Connect
				name := "Simulated Gamepad"
				if len(f) >= 4 do name = strings.trim_space(line[strings.index(line, "connect") + len("connect"):])
				ev.name = strings.clone(name, allocator)
				append(&events, ev)
			case f[2] == "disconnect":
				ev.kind = .Disconnect
				append(&events, ev)
			case:
				if b, ok := enum_parse(rl.GamepadButton, f[2]); ok {
					ev.kind, ev.button = .Button, b
					if len(f) < 4 do return events, fmt.tprintf("line %d: want down|up|tap after %s", n + 1, f[2])
					switch f[3] {
					case "down": ev.down = true; append(&events, ev)
					case "up": append(&events, ev)
					case "tap":
						hold := 2
						if len(f) >= 5 do hold, _ = strconv.parse_int(f[4])
						ev.down = true
						append(&events, ev)
						ev.down = false
						ev.frame = frame + max(hold, 1)
						append(&events, ev)
					case: return events, fmt.tprintf("line %d: %q is not down / up / tap", n + 1, f[3])
					}
				} else if a, aok := enum_parse(rl.GamepadAxis, f[2]); aok {
					if len(f) < 4 do return events, fmt.tprintf("line %d: want a value after %s", n + 1, f[2])
					v, vok := strconv.parse_f32(f[3])
					if !vok do return events, fmt.tprintf("line %d: bad axis value %q", n + 1, f[3])
					ev.kind, ev.axis, ev.value = .Axis, a, v
					append(&events, ev)
				} else {
					return events, fmt.tprintf("line %d: %q is not connect / disconnect / a pad button or axis", n + 1, f[2])
				}
			}
			continue
		}
		if lower := strings.to_lower(f[1], context.temp_allocator); strings.has_prefix(lower, "touch") && len(lower) > 5 {
			id, iok := strconv.parse_int(lower[5:])
			if !iok || len(f) < 5 do return events, fmt.tprintf("line %d: want <frame> touchN <x> <y> down|move|up|tap", n + 1)
			x, xok := strconv.parse_f32(f[2])
			y, yok := strconv.parse_f32(f[3])
			if !xok || !yok do return events, fmt.tprintf("line %d: bad touch position", n + 1)
			ev := Input_Script_Event{frame = frame, pad = -1, touch = i32(id), pos = {x, y}}
			switch f[4] {
			case "down", "move": ev.down = true; append(&events, ev)
			case "up": append(&events, ev)
			case "tap":
				hold := 2
				if len(f) >= 6 do hold, _ = strconv.parse_int(f[5])
				ev.down = true
				append(&events, ev)
				ev.down, ev.frame = false, frame + max(hold, 1)
				append(&events, ev)
			case: return events, fmt.tprintf("line %d: %q is not down / move / up / tap", n + 1, f[4])
			}
			continue
		}
		if strings.to_lower(f[1], context.temp_allocator) == "mouse" {
			if len(f) < 5 do return events, fmt.tprintf("line %d: want <frame> mouse <x> <y> click|down|up|move", n + 1)
			x, xok := strconv.parse_f32(f[2])
			y, yok := strconv.parse_f32(f[3])
			if !xok || !yok do return events, fmt.tprintf("line %d: bad mouse position", n + 1)
			ev := Input_Script_Event{frame = frame, pad = -1, mouse = true, pos = {x, y}}
			switch f[4] {
			case "move": append(&events, ev)
			case "down": ev.down, ev.button_change = true, true; append(&events, ev)
			case "up": ev.button_change = true; append(&events, ev)
			case "click":
				hold := 2
				if len(f) >= 6 do hold, _ = strconv.parse_int(f[5])
				ev.down, ev.button_change = true, true
				append(&events, ev)
				ev.down, ev.frame = false, frame + max(hold, 1)
				append(&events, ev)
			case: return events, fmt.tprintf("line %d: %q is not click / down / up / move", n + 1, f[4])
			}
			continue
		}
		key, kok := parse_keyboard_key(strings.to_upper(f[1], context.temp_allocator))
		if !kok do return events, fmt.tprintf("line %d: bad frame or key %q", n + 1, f[1])
		switch f[2] {
		case "down": append(&events, Input_Script_Event{frame = frame, key = key, down = true, pad = -1})
		case "up": append(&events, Input_Script_Event{frame = frame, key = key, down = false, pad = -1})
		case "tap":
			hold := 2
			if len(f) >= 4 do hold, _ = strconv.parse_int(f[3])
			append(&events, Input_Script_Event{frame = frame, key = key, down = true, pad = -1}, Input_Script_Event{frame = frame + max(hold, 1), key = key, down = false, pad = -1})
		case: return events, fmt.tprintf("line %d: %q is not down / up / tap", n + 1, f[2])
		}
	}
	return events, ""
}

// Runner_ApplyMouseEvent plays an --input-script mouse event: the game's
// test mouse (UI widgets, Lua's Input.*mouse*). Runner_MouseFrame clears
// the one-frame pressed / released first.
Runner_ApplyMouseEvent :: proc(game: ^Game, ev: Input_Script_Event) {
	game.uiTestInputEnabled = true
	game.uiTestMousePos = ev.pos
	if !ev.button_change do return
	if ev.down && !game.uiTestMouseDown do game.uiTestMousePressed = true
	if !ev.down && game.uiTestMouseDown do game.uiTestMouseReleased = true
	game.uiTestMouseDown = ev.down
}

Runner_MouseFrame :: proc(game: ^Game) {
	game.uiTestMousePressed = false
	game.uiTestMouseReleased = false
}

// Runner_ApplyInputEvent plays an --input-script event.
Runner_ApplyInputEvent :: proc(input: ^InputSystem, ev: Input_Script_Event) {
	if ev.mouse do return // (Runner_ApplyMouseEvent: the game's)
	if ev.touch > 0 {
		Input_SimulateTouch(input, ev.touch, ev.pos, ev.down)
		return
	}
	if ev.pad < 0 {
		Input_SetSimulatedKey(input, ev.key, ev.down)
		return
	}
	switch ev.kind {
	case .Connect: Input_SimulatePad(input, ev.pad, true, ev.name)
	case .Disconnect: Input_SimulatePad(input, ev.pad, false)
	case .Button: Input_SimulatePadButton(input, ev.pad, ev.button, ev.down)
	case .Axis: Input_SimulatePadAxis(input, ev.pad, ev.axis, ev.value)
	}
}

// Engine_ParseRunArgs reads --project/-p, --scene, --screenshot, --frames,
// --hidden, --dump-scene, --user-data, --bench, --uncapped and --no-render-cache. A bare argument is taken as the project.
Engine_ParseRunArgs :: proc(args: []string) -> (opts: Run_Options) {
	for a in args do if a == "--version" {
		fmt.println(RAYZR_RELEASE)
		os.exit(0)
	}
	for i := 0; i < len(args); i += 1 {
		arg := args[i]
		next := args[i + 1] if i + 1 < len(args) else ""
		switch {
		case (arg == "--project" || arg == "-p") && next != "":
			opts.projectPath = next; i += 1
		case strings.has_prefix(arg, "--project="):
			opts.projectPath = arg[10:]
		case arg == "--screenshot" && next != "":
			opts.screenshotPath = next; i += 1
		case strings.has_prefix(arg, "--screenshot="):
			opts.screenshotPath = arg[13:]
		case arg == "--frames" && next != "":
			n, _ := strconv.parse_int(next); opts.maxFrames = n; i += 1
		case arg == "--hidden":
			opts.hidden = true
		case arg == "--scene" && next != "":
			opts.startScene = next; i += 1
		case arg == "--dump-scene" && next != "":
			opts.dumpScenePath = next; i += 1
		case arg == "--user-data" && next != "":
			opts.userDataDir = next; i += 1
		case arg == "--no-render-cache":
			opts.noRenderCache = true
		case arg == "--trace" && next != "":
			opts.trace = next; i += 1
		case arg == "--input-script" && next != "":
			opts.inputScript = next; i += 1
		case arg == "--crash-test" && next != "":
			opts.crashTest = next; i += 1
		case arg == "--console" && next != "":
			opts.console = next; i += 1
		case arg == "--editor-link":
			opts.editorLink = true
		case arg == "--bench" && next != "":
			n, _ := strconv.parse_int(next); opts.benchFrames = n; opts.uncapped = true; i += 1
		case arg == "--uncapped":
			opts.uncapped = true
		case !strings.has_prefix(arg, "-") && opts.projectPath == "":
			opts.projectPath = arg
		}
	}
	return
}

// Engine_FindBundledProject looks for a game shipped next to the runner:
// game.rayzr, any other .rayzr, or a project/ directory (exe dir, then cwd).
Engine_FindBundledProject :: proc(exePath: string, allocator := context.allocator) -> string {
	dirs := make([dynamic]string, context.temp_allocator)
	exeDir := filepath.dir(exePath, context.temp_allocator)
	// macOS .app: Contents/MacOS/<exe> with the game in Contents/Resources.
	if res, _ := filepath.join({exeDir, "..", "Resources"}, context.temp_allocator); os.is_dir(res) do append(&dirs, res)
	append(&dirs, exeDir)
	if cwd, err := os.get_working_directory(context.temp_allocator); err == nil do append(&dirs, cwd)
	for dir in dirs {
		game, _ := filepath.join({dir, "game.rayzr"}, context.temp_allocator)
		if os.is_file(game) do return strings.clone(game, allocator)
		proj, _ := filepath.join({dir, "project", "project.json"}, context.temp_allocator)
		if os.is_file(proj) do return strings.clone(filepath.dir(proj, context.temp_allocator), allocator)
		h, err := os.open(dir)
		if err != nil do continue
		infos, _ := os.read_dir(h, -1, context.temp_allocator)
		os.close(h)
		for fi in infos {
			if fi.type != .Directory && Is_PackagePath(fi.name) {
				p, _ := filepath.join({dir, fi.name}, context.temp_allocator)
				return strings.clone(p, allocator)
			}
		}
	}
	return ""
}

// runner_font_path: the UI font from the engine checkout, or fonts/ next
// to the executable / in a macOS .app's Resources (exported games).
@(private = "file")
runner_font_path :: proc() -> cstring {
	dev :: "engine/Open_Sans/static/OpenSans-Regular.ttf"
	when ODIN_OS == .JS do return "/fonts/OpenSans-Regular.ttf" // (the page fetches fonts/ next to it)
	if os.is_file(dev) || len(os.args) == 0 do return dev
	exeDir := filepath.dir(os.args[0], context.temp_allocator)
	nextTo, _ := filepath.join({exeDir, "fonts", "OpenSans-Regular.ttf"}, context.temp_allocator)
	inApp, _ := filepath.join({exeDir, "..", "Resources", "fonts", "OpenSans-Regular.ttf"}, context.temp_allocator)
	// (The editor's runners/<platform>/runner, played from the editor: the font is in runners/.)
	inRunners, _ := filepath.join({exeDir, "..", "OpenSans-Regular.ttf"}, context.temp_allocator)
	for f in ([]string{nextTo, inApp, inRunners}) do if os.is_file(f) do return strings.clone_to_cstring(f, context.temp_allocator)
	return dev
}

// Runner_State: a running game (Runner_Start / Runner_Frame / Runner_Stop) -
// the desktop loop below, or the web page calling Runner_Frame once per
// animation frame (runner_web).
Runner_State :: struct {
	game:               ^Game,
	opts:               Run_Options,
	video:              ProjectConfig,
	frameCount:         int,
	targetCaptureFrame: int,
	fixedStep:          bool,
	benchRun:           time.Duration,
	benchFrame:         time.Duration,
	benchAllocs, benchAllocBytes, benchTempBytes: int, // (profiling builds)
	windowOpen, audioOpen, fontsLoaded: bool,
	inputEvents:        [dynamic]Input_Script_Event, // --input-script
}

// Engine_RunProject opens a window and plays the project until it quits.
// Returns a process exit code.
Engine_RunProject :: proc(opts: Run_Options) -> int {
	// Crash reports (crash_report.odin): the folder is set once the project
	// is loaded (its user-data folder).
	context.assertion_failure_proc = Crash_AssertionFailure
	context.logger = Crash_Logger(context.logger)
	Crash_Install("Rayzr game")
	// Memory diagnostics builds (mem_track.odin): leaks and bad frees.
	context.allocator = MemTrack_Init(context.allocator)
	defer MemTrack_Shutdown()
	// Profiling builds (profiling.odin): the trace and the heap counters.
	Prof_ParseArgs(os.args[1:])
	context.allocator = Prof_Init(context.allocator)
	defer Prof_Shutdown()
	rs, ok := Runner_Start(opts)
	if !ok do return 1
	if opts.crashTest != "" do Crash_TestCrash(opts.crashTest)
	for Runner_Frame(rs) {}
	Runner_Stop(rs)
	return 0
}

// Runner_Start creates the game and its window and loads the project
// (false: it failed - everything is cleaned up).
Runner_Start :: proc(opts: Run_Options) -> (^Runner_State, bool) {
	rs := new(Runner_State)
	rs.opts = opts
	projectPath := opts.projectPath
	startScene := opts.startScene
	game := new(Game)
	rs.game = game
	InitializeGame(game)
	// (Instances don't keep a copy of their component's JSON in a game: #80.)
	Component_KeepBases = false
	if opts.userDataDir != "" do Save_SetDirectory(opts.userDataDir)
	if opts.noRenderCache {
		TileCache_SetEnabled(false)
		Render_SetBatching(false)
	}

	winW := i32(1280)
	winH := i32(720)
	winTitle := "Odin Raylib Game Engine"
	targetFPS := i32(60)
	video := ProjectConfig{vsync = true, resizable = true}

	// Attempt to read project.json to configure window size and title before window creation
	if Is_PackagePath(projectPath) {
		pkg, ok := RayzrPackage_Open(projectPath, context.temp_allocator)
		if ok {
			if b, bOk := RayzrPackage_ReadFile(pkg, "project.json", context.temp_allocator); bOk {
				if cfg, pOk := Project_ParseConfig(b, context.temp_allocator); pOk {
					if cfg.windowWidth > 0 do winW = i32(cfg.windowWidth)
					if cfg.windowHeight > 0 do winH = i32(cfg.windowHeight)
					if cfg.windowTitle != "" do winTitle = cfg.windowTitle
					if cfg.targetFPS > 0 do targetFPS = i32(cfg.targetFPS)
					video = cfg
				}
			}
			RayzrPackage_Close(pkg)
		}
	} else {
		jsonPath, _ := filepath.join({projectPath, "project.json"}, context.temp_allocator)
		if b, bErr := os.read_entire_file(jsonPath, context.temp_allocator); bErr == nil {
			if cfg, pOk := Project_ParseConfig(b, context.temp_allocator); pOk {
				if cfg.windowWidth > 0 do winW = i32(cfg.windowWidth)
				if cfg.windowHeight > 0 do winH = i32(cfg.windowHeight)
				if cfg.windowTitle != "" do winTitle = cfg.windowTitle
				if cfg.targetFPS > 0 do targetFPS = i32(cfg.targetFPS)
				video = cfg
			}
		}
	}
	rs.video = video

	// Project Video settings.
	flags: rl.ConfigFlags = {}
	if video.resizable do flags += {.WINDOW_RESIZABLE}
	if video.vsync && !opts.uncapped do flags += {.VSYNC_HINT}
	if video.msaa do flags += {.MSAA_4X_HINT}
	if video.highDPI do flags += {.WINDOW_HIGHDPI}
	if opts.hidden {
		flags += {.WINDOW_HIDDEN, .WINDOW_UNFOCUSED} // (never takes the focus)
	}
	rl.SetConfigFlags(flags)
	rl.SetTraceLogLevel(.ERROR) // raylib warns once per oversized icon glyph (thousands of lines)
	when ODIN_OS == .JS do rl.SetTraceLogLevel(.WARNING) // (the browser console: shader / GL problems)
	titleC := strings.clone_to_cstring(winTitle, context.temp_allocator)
	rl.InitWindow(winW, winH, titleC)
	if !rl.IsWindowReady() {
		// (No OpenGL 3.3 context: a machine without a GPU / display - raylib
		// would crash on the next window call.)
		log.errorf("Could not open the game window (OpenGL 3.3 is needed)")
		Runner_Stop(rs)
		return nil, false
	}
	rs.windowOpen = true
	// Fullscreen (project Video, Engine.set_fullscreen): applied from the
	// first frames on (Runner_ApplyFullscreen); the frame scales to the window.
	if video.fullscreen && !opts.hidden do game.fullscreenRequest = true
	if !opts.noRenderCache do Render_InitBatching()

	rl.SetTargetFPS(0 if opts.uncapped else targetFPS)
	when ODIN_OS == .JS do rl.SetTargetFPS(0) // (the page's requestAnimationFrame paces frames: raylib mustn't sleep)
	rl.InitAudioDevice()
	rs.audioOpen = true

	// Multi-size engine fonts
	InitEngineFonts(runner_font_path())
	rs.fontsLoaded = true

	// Load Project (populates scenes, sets gravity, activates initial_scene)
	if !game->loadProject(projectPath) {
		log.errorf("Failed to load project: %s", projectPath)
		Runner_Stop(rs)
		return nil, false
	}
	if video.icon != "" do Runner_SetWindowIcon(game, video.icon)
	// Crash reports go to the game's user-data folder (crash_report.odin).
	when ODIN_OS != .JS {
		Crash_Install(video.windowTitle if video.windowTitle != "" else Save_GameName(), Save_CrashDir())
	}
	// A project saved by a newer editor may use what this runner lacks.
	if !Version_IsDev(RAYZR_RELEASE) && !Version_IsDev(video.engineVersion) && Version_Compare(video.engineVersion, RAYZR_RELEASE) > 0 {
		log.warnf("This project was saved by Rayzr %s; this runner is %s - update the editor (and re-export) if something is missing", video.engineVersion, RAYZR_RELEASE)
	}
	// (Loading the project applies its target FPS: uncapped runs undo it.)
	if opts.uncapped do rl.SetTargetFPS(0)

	// --scene <file>: start in that scene instead of the project's initial
	// scene (the editor's "Play Current Scene").
	if startScene != "" {
		scene := Game_FindSceneByFile(game, startScene)
		if scene == nil do scene = Game_RegisterSceneFile(game, startScene)
		if scene != nil {
			ChangeScene_ByPtr(&game.sceneManager, scene)
			ProcessSceneChange(&game.sceneManager, &game.gameContext)
			log.infof("Starting in scene: %s", startScene)
		} else {
			log.errorf("Scene not found: %s", startScene)
		}
	}

	game.viewportCanvasRect = {0, 0, f32(winW), f32(winH)}
	if cur := game.sceneManager.currentScene; cur != nil {
		log.infof("[Game] Playing scene '%s' (%s)", cur.name, cur.filePath)
	}

	if game.backgroundColor == rl.BLACK {
		game.backgroundColor = rl.Color{8, 10, 18, 255}
	}

	// The editor's Play: it drives the game over stdin/stdout. (Read from the
	// command line too: front ends pass on only the options they know.)
	if opts.editorLink || slice.contains(os.args, "--editor-link") do EditorLink_Enable(game)
	// The developer console: debug builds, the editor's Play, or a release
	// build when the project allows it.
	if ODIN_DEBUG || EditorLink_Enabled() || video.consoleInRelease || opts.console != "" {
		Console_Enable(game, video.consoleKey)
		for line in strings.split(opts.console, ";", context.temp_allocator) {
			l := strings.trim_space(line)
			if l == "open" do devConsole.open = true
			else if l != "" do Console_Exec(game, l)
		}
	}

	rs.targetCaptureFrame = max(25, opts.maxFrames) if opts.maxFrames > 0 else 30
	// Captures for tests step a fixed 1/60 s, so runs are comparable.
	rs.fixedStep = opts.screenshotPath != "" || opts.dumpScenePath != "" || opts.inputScript != ""
	if opts.inputScript != "" {
		text, rerr := os.read_entire_file(opts.inputScript, context.temp_allocator)
		if rerr != nil {
			log.errorf("--input-script %s: %v", opts.inputScript, rerr)
		} else {
			events, why := Runner_LoadInputScript(string(text))
			rs.inputEvents = events
			game.input.useSimulatedInput = len(events) > 0
			if why != "" do log.errorf("--input-script %s: %s", opts.inputScript, why)
		}
	}
	return rs, true
}

// Runner_Frame runs and draws one frame; false when the game is over (the
// window closed, the game quit, a capture or benchmark finished).
Runner_Frame :: proc(rs: ^Runner_State) -> bool {
	game := rs.game
	opts := rs.opts
	video := rs.video
	screenshotPath := opts.screenshotPath
	dumpScenePath := opts.dumpScenePath
	// --bench: the first 30 frames warm up (loading, caches), then N timed.
	benchWarmup :: 30
	// (raylib's web WindowShouldClose sleeps for a blocking loop: a page never "closes")
	when ODIN_OS != .JS do if rl.WindowShouldClose() do return false
	if game.shouldQuit do return false
	{
		dt := 1.0 / 60 if rs.fixedStep else rl.GetFrameTime()
		if game.uiTestInputEnabled do Runner_MouseFrame(game)
		for ev in rs.inputEvents do if ev.frame == rs.frameCount {
			if ev.mouse do Runner_ApplyMouseEvent(game, ev)
			else do Runner_ApplyInputEvent(&game.input, ev)
		}
		EditorLink_BeginFrame(game)
		if game.linkPaused && !game.frozen do dt = 1.0 / 60 // a step
		if Console_Frame(game, rl.GetFrameTime()) do dt = 1.0 / 60 // (the console's step)

		if on, asked := game.fullscreenRequest.?; asked && rs.frameCount >= 2 {
			Runner_ApplyFullscreen(game, on)
			game.fullscreenRequest = nil
		}
		// The game draws at its virtual resolution into a texture, scaled to
		// the window (fullscreen, resized) - the mouse reads in game units.
		vw, vh := Runner_VirtualSize(game)
		dest := Runner_FitRect(vw, vh, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()))
		rl.SetMouseOffset(i32(-dest.x), i32(-dest.y))
		rl.SetMouseScale(vw / dest.width, vh / dest.height)
		game.screenToGame = {-dest.x, -dest.y, vw / dest.width, vh / dest.height} // (touches: as the mouse)
		game.viewportCanvasRect = {0, 0, vw, vh}
		target := Runner_FrameTarget(i32(vw), i32(vh), video.sharpScaling)

		frameStart := time.tick_now()
		Prof_Begin("frame")
		Render_SetFrameTarget(target)
		rl.BeginTextureMode(target^)
		// Smooth camera: the world gets its own texture; the frame holds the
		// layers on top (transparent elsewhere).
		rl.ClearBackground({0, 0, 0, 0} if renderPixel.smooth else Game_ClearColor(game))
		{
			Prof_Scope("game.run")
			game->run(dt)
		}
		// (Drawn over the black letterbox below: soft edges would darken.)
		if !renderPixel.smooth && Game_ClearColor(game).a == 255 do Render_MakeOpaque(vw, vh)
		rl.EndTextureMode()
		Render_SetFrameTarget(nil)
		frame := target.texture
		if effects := Scene_PostEffects(game.sceneManager.currentScene); len(effects) > 0 && !renderPixel.smooth {
			frame = Post_Process(effects, frame, &game.gameContext) // through each effect
		}
		runTime := time.tick_since(frameStart)

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK) // the letterbox bars
		// Accessibility: the frame through the colour-blind filter on its way out.
		filtered := Colorblind_Begin(access.colorblind, access.colorblindStrength, access.simulate)
		if renderPixel.smooth {
			// The background, the world moved by the camera's leftover
			// fraction (post effects on it), then the other layers on top.
			rl.DrawRectangleRec(dest, Game_ClearColor(game))
			if renderPixel.usedWorld {
				world := renderPixel.world.texture
				if effects := Scene_PostEffects(game.sceneManager.currentScene); len(effects) > 0 do world = Post_Process(effects, world, &game.gameContext)
				Pixel_DrawWorld(world, dest, vw, vh)
			}
			// (Premultiplied: scene.odin draws the layers over the world so.)
			rl.BeginBlendMode(.ALPHA_PREMULTIPLY)
			rl.DrawTexturePro(target.texture, {0, 0, f32(target.texture.width), -f32(target.texture.height)}, dest, {0, 0}, 0, rl.WHITE)
			rl.EndBlendMode()
		} else {
			// Copied as is: blending would let the bars' black through where the
			// frame's alpha dropped (anti-aliased text, translucent sprites).
			rlgl.DrawRenderBatchActive()
			rlgl.DisableColorBlend()
			rl.DrawTexturePro(frame, {0, 0, f32(frame.width), -f32(frame.height)}, dest, {0, 0}, 0, rl.WHITE)
			rlgl.DrawRenderBatchActive()
			rlgl.EnableColorBlend()
		}
		if filtered do Colorblind_End()
		if opts.uncapped && opts.benchFrames <= 0 do runner_draw_frame_time(rs)
		Console_DrawScreen(game) // (the developer console and its overlays)
		Prof_Begin("present")
		rl.EndDrawing()
		Prof_End()
		Prof_End() // frame
		Prof_FrameEnd()
		MemTrack_Frame()
		defer free_all(context.temp_allocator) // the frame's temp allocations (after the captures below)

		rs.frameCount += 1
		if opts.trace != "" {
			if scene := game.sceneManager.currentScene; scene != nil {
				if n := Scene_FindNodeByName(scene, opts.trace); n != nil {
					fmt.printfln("@trace %d %s %.1f %.1f", rs.frameCount, scene.name, n.globalPosition.x, n.globalPosition.y)
				}
			}
		}
		if opts.benchFrames > 0 && rs.frameCount > benchWarmup {
			rs.benchRun += runTime
			rs.benchFrame += time.tick_since(frameStart)
			last := Prof_Last()
			rs.benchAllocs += last.allocs
			rs.benchAllocBytes += last.bytes
			rs.benchTempBytes += last.tempBytes
			if rs.frameCount >= benchWarmup + opts.benchFrames {
				n := f64(opts.benchFrames)
				whole := time.duration_milliseconds(rs.benchFrame) / n
				fmt.printfln("[bench] %d frames: update+draw %.3f ms | whole frame (incl. GPU sync) %.3f ms (%.0f fps) | %d drawn, %d culled | %d tile chunks (%d built)",
					opts.benchFrames, time.duration_milliseconds(rs.benchRun) / n, whole, 1000 / whole, renderStats.drawn, renderStats.culled, TileCache_Stats(), TileCache_Builds())
				when RAYZR_PROF {
					fmt.printfln("[bench] per frame: %.1f heap allocations (%.1f KB) | temp arena %.1f KB",
						f64(rs.benchAllocs) / n, f64(rs.benchAllocBytes) / n / 1024, f64(rs.benchTempBytes) / n / 1024)
				}
				return false
			}
		}
		if (screenshotPath != "" || dumpScenePath != "") && rs.frameCount >= rs.targetCaptureFrame {
			// --dump-scene: what the game is actually running, for tests.
			if dumpScenePath != "" && game.sceneManager.currentScene != nil {
				dump := Scene_SerializeToJSON(game.sceneManager.currentScene, context.temp_allocator)
				_ = os.write_entire_file(dumpScenePath, transmute([]u8)dump)
			}
		}
		if screenshotPath == "" && dumpScenePath != "" && rs.frameCount >= rs.targetCaptureFrame do return false
		if screenshotPath != "" && rs.frameCount >= rs.targetCaptureFrame {
			img := rl.LoadImageFromScreen()
			cPath := strings.clone_to_cstring(screenshotPath, context.temp_allocator)
			rl.ExportImage(img, cPath)
			rl.UnloadImage(img)
			log.infof("[Gameplay Screenshot] Saved gameplay capture to: %s", screenshotPath)
			return false
		}
	}
	return true
}

// Runner_Stop frees the game, its window and everything the runner made.
Runner_Stop :: proc(rs: ^Runner_State) {
	if rs == nil do return
	for ev in rs.inputEvents do if ev.kind == .Connect && ev.pad >= 0 do delete(ev.name)
	delete(rs.inputEvents)
	Pixel_Release()
	if rs.fontsLoaded do UnloadEngineFonts()
	if rs.audioOpen do rl.CloseAudioDevice()
	Post_Unload()
	Render_ReleaseBatching()
	if runnerTarget.id != 0 {
		rl.UnloadRenderTexture(runnerTarget)
		runnerTarget = {}
	}
	if rs.windowOpen do rl.CloseWindow()
	Console_Shutdown() // (before the game: its Lua commands)
	rs.game->terminate()
	free(rs)
}

// Runner_ApplyFullscreen switches the window to cover the monitor (a
// borderless window at its resolution - the display mode doesn't change) or
// back. Called at the start of a frame, once the window is up: on macOS the
// switch made right after InitWindow doesn't take.
Runner_ApplyFullscreen :: proc(game: ^Game, on: bool) {
	if rl.IsWindowState({.BORDERLESS_WINDOWED_MODE}) != on do rl.ToggleBorderlessWindowed()
	game.fullscreen = on
}

// Runner_VirtualSize: the resolution the game draws at (project Video >
// virtual resolution, else the window's).
Runner_VirtualSize :: proc(game: ^Game) -> (f32, f32) {
	// Expand (#174): the design size grown to the window's shape, every frame
	// (the window may be resized, or go fullscreen).
	if game.fill == .Expand && game.designSize.x > 0 && game.designSize.y > 0 {
		game.virtualSize = Screen_FillSize(game.designSize, {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}, .Expand, renderPixel.integerScaling)
	}
	if game.virtualSize.x > 0 && game.virtualSize.y > 0 do return game.virtualSize.x, game.virtualSize.y
	return f32(max(rl.GetScreenWidth(), 1)), f32(max(rl.GetScreenHeight(), 1))
}

// Runner_FitRect: a w x h frame scaled to fit a screen, centred (bars on the
// sides that don't fill).
Runner_FitRect :: proc(w, h, screenW, screenH: f32) -> rl.Rectangle {
	return Pixel_FitRect(w, h, screenW, screenH) // (a whole-number scale with integer scaling)
}

@(private = "file")
runnerTarget: rl.RenderTexture2D

// Runner_FrameTarget: the virtual-resolution render texture (remade when
// the size changes). `sharp`: nearest-neighbour scaling (pixel art).
Runner_FrameTarget :: proc(w, h: i32, sharp: bool) -> ^rl.RenderTexture2D {
	if runnerTarget.id == 0 || runnerTarget.texture.width != w || runnerTarget.texture.height != h {
		if runnerTarget.id != 0 do rl.UnloadRenderTexture(runnerTarget)
		runnerTarget = rl.LoadRenderTexture(w, h)
	}
	rl.SetTextureFilter(runnerTarget.texture, .POINT if sharp else .BILINEAR)
	return &runnerTarget
}

// Runner_SetWindowIcon uses a project PNG (project.json "icon") as the
// window's icon.
Runner_SetWindowIcon :: proc(game: ^Game, path: string) -> bool {
	data, ok := AssetManager_ReadFileBytes(&game.assetManager, path, context.temp_allocator)
	if !ok || len(data) == 0 {
		log.warnf("[Game] Icon not found: %s", path)
		return false
	}
	ext := strings.clone_to_cstring(strings.to_lower(filepath.ext(path), context.temp_allocator), context.temp_allocator)
	img := rl.LoadImageFromMemory(ext, raw_data(data), i32(len(data)))
	if img.data == nil {
		log.warnf("[Game] Icon is not a readable image: %s", path)
		return false
	}
	defer rl.UnloadImage(img)
	rl.ImageFormat(&img, .UNCOMPRESSED_R8G8B8A8) // what SetWindowIcon expects
	rl.SetWindowIcon(img)
	return true
}

// runner_draw_frame_time (--uncapped): the average frame time and FPS over
// the last half second, top left.
@(private = "file")
runner_draw_frame_time :: proc(rs: ^Runner_State) {
	@(static) frames: int
	@(static) since: time.Tick
	@(static) text: [64]u8
	if since == {} do since = time.tick_now()
	frames += 1
	if elapsed := time.tick_since(since); elapsed >= 500 * time.Millisecond {
		ms := time.duration_milliseconds(elapsed) / f64(frames)
		text = {}
		_ = fmt.bprintf(text[:len(text) - 1], "%.2f ms  %.0f fps", ms, 1000 / ms)
		frames, since = 0, time.tick_now()
	}
	rl.DrawRectangle(4, 4, 170, 24, {0, 0, 0, 170})
	rl.DrawText(cstring(&text[0]), 10, 9, 16, rl.LIME)
}
