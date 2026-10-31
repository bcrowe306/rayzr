package engine

import "base:runtime"
import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import os "osx"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import b2 "vendor:box2d"
import rl "vendor:raylib"

// ============================================================================
// Data-Driven Project & Scene Format (.rayzr / JSON)
// ============================================================================

ProjectConfig :: struct {
	name:          string,
	version:       string,
	engineVersion: string, // the editor release that last saved it ("engine_version"; version.odin)
	initialScene:  string,
	windowTitle:   string,
	windowWidth:   int,
	windowHeight:  int,
	virtualWidth:  f32,
	virtualHeight: f32,
	targetFPS:     int,
	gravity:       [2]f32,
	debugDraw:     bool, // the running game draws colliders, joints and areas (physics.debug_draw)
	collisionLayers: [16]string, // collision layer names ("" = unnamed; physics_extras.odin)
	scenes:        [dynamic]string,
	icon:          string, // project-relative PNG: the game window's icon (and the exported app's)
	language:      string, // starting language of the locale/ tables ("" = their first)
	// The default scene transition (Scene.change_scene without options;
	// "scene_flow"; scene_transition.odin): "" = changes are at once.
	transition:         string,
	transitionDuration: f32,
	transitionEasing:   string,

	// Video
	fullscreen:    bool,
	fill:          Screen_Fill, // a window / screen of another shape than the virtual resolution (#174)
	sharpScaling:  bool, // the frame is scaled to the window nearest-neighbour (pixel art) - else smoothly
	integerScaling: bool, // scaled by a whole number (bars around): every game pixel the same size (pixel_perfect.odin)
	pixelSnap:     bool, // the camera and sprites on whole game pixels
	smoothCamera:  bool, // with pixel snap: the camera's sub-pixel motion kept (smooth pans)
	vsync:         bool,
	resizable:     bool,
	msaa:          bool,
	highDPI:       bool,
	// Audio (0..1)
	masterVolume:  f32,
	musicVolume:   f32,
	sfxVolume:     f32,
	mixerBuses:    string, // the mixer's buses ("audio": {"buses": [...]}, JSON text; mixer_config.odin) - "" = Master / Music / SFX
	accessibility: string, // the players' default accessibility settings ("accessibility": {...}, JSON text; accessibility.odin) - "" = the engine's
	// Input actions (empty = the built-in defaults)
	actions:       [dynamic]Input_Action_Config,
	touchAsMouse:  bool, // a finger is the left mouse button (default on; "input": {"touch_as_mouse"})
	consoleInRelease: bool,   // the developer console in release exports too ("debug": {"console_in_release"}; dev_console.odin)
	consoleKey:       string, // its key ("debug": {"console_key"}; "" = the backquote)
	// Export
	export:        Export_Settings,
	// Per-texture filtering / wrap / mipmaps (asset_paths.odin)
	textureImport: [dynamic]Texture_Import,
	// Global scripts (autoloads): loaded once at start, reachable from every
	// script as a Lua global (script_globals.odin)
	globals:       [dynamic]Global_Script,
}

Global_Script :: struct {
	name:   string, // the Lua global's name
	script: string, // project-relative .lua
}

Export_Target :: enum {
	MacOS,
	Windows,
	Linux,
	Web, // a page (index.html + wasm) and game.rayzr - runners/web/ (scripts/build_web_runner.sh)
}

Export_Settings :: struct {
	executableName: string,           // "" = the project name without spaces
	outputDir:      string,           // "" = <project>_standalone next to the project
	targets:        bit_set[Export_Target],
	compress:       bool,             // compress the .rayzr package
	includeFont:    bool,             // ship the UI font next to the runner
	// macOS .app
	bundleId:       string,           // "" = com.rayzr.<executable, lower case>
	macSign:        string,           // codesign identity: "" = ad-hoc, "none" = don't sign
	macNotaryProfile: string,         // notarytool keychain profile ("" = don't notarize)
	presets:        [dynamic]Export_Preset, // export_presets.odin (empty = one per target)
}

ProjectConfig_Destroy :: proc(cfg: ^ProjectConfig, allocator := context.allocator) {
	if cfg == nil do return
	if cfg.name != "" do delete(cfg.name, allocator)
	if cfg.version != "" do delete(cfg.version, allocator)
	if cfg.engineVersion != "" do delete(cfg.engineVersion, allocator)
	if cfg.initialScene != "" do delete(cfg.initialScene, allocator)
	if cfg.windowTitle != "" do delete(cfg.windowTitle, allocator)
	if cfg.icon != "" do delete(cfg.icon, allocator)
	if cfg.language != "" do delete(cfg.language, allocator)
	if cfg.consoleKey != "" do delete(cfg.consoleKey, allocator)
	if cfg.transition != "" do delete(cfg.transition, allocator)
	if cfg.transitionEasing != "" do delete(cfg.transitionEasing, allocator)
	if cfg.mixerBuses != "" do delete(cfg.mixerBuses, allocator)
	if cfg.accessibility != "" do delete(cfg.accessibility, allocator)
	for n in cfg.collisionLayers do if n != "" do delete(n, allocator)
	for s in cfg.scenes {
		delete(s, allocator)
	}
	delete(cfg.scenes)
	Input_ActionConfigs_Destroy(&cfg.actions, allocator)
	if cfg.export.executableName != "" do delete(cfg.export.executableName, allocator)
	if cfg.export.outputDir != "" do delete(cfg.export.outputDir, allocator)
	if cfg.export.bundleId != "" do delete(cfg.export.bundleId, allocator)
	if cfg.export.macSign != "" do delete(cfg.export.macSign, allocator)
	if cfg.export.macNotaryProfile != "" do delete(cfg.export.macNotaryProfile, allocator)
	for &pr in cfg.export.presets do Export_Preset_Destroy(&pr, allocator)
	delete(cfg.export.presets)
	for t in cfg.textureImport do delete(t.path, allocator)
	delete(cfg.textureImport)
	for g in cfg.globals {
		delete(g.name, allocator)
		delete(g.script, allocator)
	}
	delete(cfg.globals)
}

// ProjectConfig_Clone deep-copies a config.
ProjectConfig_Clone :: proc(src: ^ProjectConfig, allocator := context.allocator) -> ProjectConfig {
	c := src^
	c.name = strings.clone(src.name, allocator)
	c.version = strings.clone(src.version, allocator)
	c.engineVersion = strings.clone(src.engineVersion, allocator)
	c.initialScene = strings.clone(src.initialScene, allocator)
	c.windowTitle = strings.clone(src.windowTitle, allocator)
	c.icon = strings.clone(src.icon, allocator)
	c.language = strings.clone(src.language, allocator)
	c.consoleKey = strings.clone(src.consoleKey, allocator) if src.consoleKey != "" else ""
	c.transition = strings.clone(src.transition, allocator) if src.transition != "" else ""
	c.transitionEasing = strings.clone(src.transitionEasing, allocator) if src.transitionEasing != "" else ""
	c.mixerBuses = strings.clone(src.mixerBuses, allocator) if src.mixerBuses != "" else ""
	c.accessibility = strings.clone(src.accessibility, allocator) if src.accessibility != "" else ""
	for n, i in src.collisionLayers do c.collisionLayers[i] = strings.clone(n, allocator) if n != "" else ""
	c.scenes = make([dynamic]string, allocator)
	for s in src.scenes do append(&c.scenes, strings.clone(s, allocator))
	c.actions = make([dynamic]Input_Action_Config, allocator)
	for a in src.actions {
		na := Input_Action_Config{name = strings.clone(a.name, allocator), bindings = make([dynamic]InputBinding, allocator)}
		append(&na.bindings, ..a.bindings[:])
		append(&c.actions, na)
	}
	c.export.executableName = strings.clone(src.export.executableName, allocator)
	c.export.outputDir = strings.clone(src.export.outputDir, allocator)
	c.export.bundleId = strings.clone(src.export.bundleId, allocator)
	c.export.macSign = strings.clone(src.export.macSign, allocator)
	c.export.macNotaryProfile = strings.clone(src.export.macNotaryProfile, allocator)
	c.export.presets = make([dynamic]Export_Preset, allocator)
	for &pr in src.export.presets do append(&c.export.presets, Export_Preset_Clone(&pr, allocator))
	c.textureImport = make([dynamic]Texture_Import, allocator)
	for t in src.textureImport {
		ct := t
		ct.path = strings.clone(t.path, allocator)
		append(&c.textureImport, ct)
	}
	c.globals = make([dynamic]Global_Script, allocator)
	for g in src.globals do append(&c.globals, Global_Script{strings.clone(g.name, allocator), strings.clone(g.script, allocator)})
	return c
}

// ----------------------------------------------------------------------------
// JSON Extraction Helpers
// ----------------------------------------------------------------------------

@(private="file")
json_get_string :: proc(obj: json.Object, key: string, defaultVal: string = "") -> string {
	if val, ok := obj[key]; ok {
		if s, isStr := val.(json.String); isStr do return s
	}
	return defaultVal
}

@(private="file")
json_get_int :: proc(obj: json.Object, key: string, defaultVal: int = 0) -> int {
	if val, ok := obj[key]; ok {
		if i, isInt := val.(json.Integer); isInt do return int(i)
		if f, isFloat := val.(json.Float); isFloat do return int(f)
	}
	return defaultVal
}

@(private="file")
json_get_float :: proc(obj: json.Object, key: string, defaultVal: f32 = 0.0) -> f32 {
	if val, ok := obj[key]; ok {
		if f, isFloat := val.(json.Float); isFloat do return f32(f)
		if i, isInt := val.(json.Integer); isInt do return f32(i)
	}
	return defaultVal
}

@(private="file")
json_get_bool :: proc(obj: json.Object, key: string, defaultVal: bool = false) -> bool {
	if val, ok := obj[key]; ok {
		if b, isBool := val.(json.Boolean); isBool do return bool(b)
	}
	return defaultVal
}

@(private="file")
json_get_vec2 :: proc(obj: json.Object, key: string, defaultVal: [2]f32 = {0, 0}) -> [2]f32 {
	if val, ok := obj[key]; ok {
		if arr, isArr := val.(json.Array); isArr && len(arr) >= 2 {
			x: f32 = defaultVal.x
			y: f32 = defaultVal.y
			if f0, ok0 := arr[0].(json.Float); ok0 do x = f32(f0)
			else if i0, ok0 := arr[0].(json.Integer); ok0 do x = f32(i0)
			if f1, ok1 := arr[1].(json.Float); ok1 do y = f32(f1)
			else if i1, ok1 := arr[1].(json.Integer); ok1 do y = f32(i1)
			return {x, y}
		}
	}
	return defaultVal
}

@(private="file")
json_get_obj :: proc(obj: json.Object, key: string) -> (json.Object, bool) {
	if val, ok := obj[key]; ok {
		if child, isObj := val.(json.Object); isObj {
			return child, true
		}
	}
	return nil, false
}

@(private="file")
json_get_arr :: proc(obj: json.Object, key: string) -> (json.Array, bool) {
	if val, ok := obj[key]; ok {
		if arr, isArr := val.(json.Array); isArr {
			return arr, true
		}
	}
	return nil, false
}

// Project_ResolveAssetPath resolves a path: as given, then through the
// project directory (AssetManager), then under the working directory's
// assets/. Projects are found through the project directory only (no
// hidden fallbacks to a particular project).
Project_ResolveAssetPath :: proc(gameContext: ^GameContext, relPath: string, allocator := context.temp_allocator) -> string {
	if relPath == "" do return ""
	if os.exists(relPath) do return relPath
	if gameContext != nil && gameContext.game != nil {
		am := &gameContext.game.assetManager
		resolved := AssetManager_ResolveDiskPath(am, relPath, allocator)
		if os.exists(resolved) do return resolved

		if strings.has_prefix(relPath, "assets/") {
			sub := relPath[7:]
			resSub := AssetManager_ResolveDiskPath(am, sub, allocator)
			if os.exists(resSub) do return resSub
		}
	}
	// Relative to the working directory's assets/ (engine-bundled assets).
	p1, _ := filepath.join({"assets", relPath}, allocator)
	if os.exists(p1) do return p1
	return relPath
}

@(private)
json_extract_texture_path :: proc(nodeObj: json.Object) -> string {
	texPath := json_get_string(nodeObj, "texture_path", "")
	if texPath == "" {
		if texObj, hasTexObj := json_get_obj(nodeObj, "texture"); hasTexObj {
			texPath = json_get_string(texObj, "path", "")
		}
	}
	if texPath == "" {
		texPath = json_get_string(nodeObj, "texture", "")
	}
	return texPath
}

// ----------------------------------------------------------------------------
// Project JSON Parsing
// ----------------------------------------------------------------------------

Project_ParseConfig :: proc(jsonBytes: []u8, allocator := context.allocator) -> (ProjectConfig, bool) {
	context = Engine_DefaultContext()
	cfg := ProjectConfig{
		name          = "Untitled Project",
		version       = "1.0.0",
		initialScene  = "main",
		windowTitle   = "Rayzr",
		windowWidth   = 1280,
		windowHeight  = 720,
		virtualWidth  = 1280.0,
		virtualHeight = 720.0,
		targetFPS     = 60,
		gravity       = {0, 980.0},
		debugDraw     = true,
		scenes        = make([dynamic]string, allocator),
		vsync         = true,
		resizable     = true,
		masterVolume  = 1,
		musicVolume   = 1,
		sfxVolume     = 1,
		export        = {targets = {native_export_target()}, compress = true, includeFont = true},
		touchAsMouse  = true,
	}

	parsedVal, err := json.parse(jsonBytes, allocator = context.temp_allocator)
	if err != .None {
		log.errorf("[ProjectParser] JSON parse error: %v", err)
		return cfg, false
	}
	defer json.destroy_value(parsedVal, context.temp_allocator)

	rootObj, isObj := parsedVal.(json.Object)
	if !isObj {
		log.error("[ProjectParser] Expected root JSON object")
		return cfg, false
	}

	cfg.name = strings.clone(json_get_string(rootObj, "name", cfg.name), allocator)
	cfg.version = strings.clone(json_get_string(rootObj, "version", cfg.version), allocator)
	cfg.engineVersion = strings.clone(json_get_string(rootObj, "engine_version", ""), allocator)
	cfg.initialScene = strings.clone(json_get_string(rootObj, "initial_scene", cfg.initialScene), allocator)
	cfg.icon = strings.clone(json_get_string(rootObj, "icon", ""), allocator)
	cfg.language = strings.clone(json_get_string(rootObj, "language", ""), allocator)
	if flow, ok := json_get_obj(rootObj, "scene_flow"); ok {
		if t := json_get_string(flow, "transition", ""); t != "" do cfg.transition = strings.clone(t, allocator)
		cfg.transitionDuration = json_get_float(flow, "duration", 0)
		if e := json_get_string(flow, "easing", ""); e != "" do cfg.transitionEasing = strings.clone(e, allocator)
	}
	cfg.textureImport = make([dynamic]Texture_Import, allocator)
	texture_imports_read(rootObj, &cfg.textureImport, allocator)

	// Window settings
	if winObj, ok := json_get_obj(rootObj, "window"); ok {
		cfg.windowTitle = strings.clone(json_get_string(winObj, "title", cfg.windowTitle), allocator)
		cfg.windowWidth = json_get_int(winObj, "width", cfg.windowWidth)
		cfg.windowHeight = json_get_int(winObj, "height", cfg.windowHeight)
		cfg.virtualWidth = json_get_float(winObj, "virtual_width", cfg.virtualWidth)
		cfg.virtualHeight = json_get_float(winObj, "virtual_height", cfg.virtualHeight)
		cfg.targetFPS = json_get_int(winObj, "target_fps", cfg.targetFPS)
	} else {
		cfg.windowTitle = strings.clone(cfg.windowTitle, allocator) // owned like the rest (ProjectConfig_Destroy frees it)
	}

	cfg.fill = .Keep // (projects saved before fill modes: bars, as they looked)
	if videoObj, ok := json_get_obj(rootObj, "video"); ok {
		cfg.fullscreen = json_get_bool(videoObj, "fullscreen", cfg.fullscreen)
		cfg.fill = Screen_Fill_Parse(json_get_str(videoObj, "fill"))
		cfg.sharpScaling = json_get_bool(videoObj, "sharp_scaling", cfg.sharpScaling)
		cfg.integerScaling = json_get_bool(videoObj, "integer_scaling", cfg.integerScaling)
		cfg.pixelSnap = json_get_bool(videoObj, "pixel_snap", cfg.pixelSnap)
		cfg.smoothCamera = json_get_bool(videoObj, "smooth_camera", cfg.smoothCamera)
		cfg.vsync = json_get_bool(videoObj, "vsync", cfg.vsync)
		cfg.resizable = json_get_bool(videoObj, "resizable", cfg.resizable)
		cfg.msaa = json_get_bool(videoObj, "msaa", cfg.msaa)
		cfg.highDPI = json_get_bool(videoObj, "high_dpi", cfg.highDPI)
	}
	if audioObj, ok := json_get_obj(rootObj, "audio"); ok {
		cfg.masterVolume = json_get_float(audioObj, "master_volume", cfg.masterVolume)
		cfg.musicVolume = json_get_float(audioObj, "music_volume", cfg.musicVolume)
		cfg.sfxVolume = json_get_float(audioObj, "sfx_volume", cfg.sfxVolume)
		if buses, has := audioObj["buses"]; has {
			if text, merr := json.marshal(buses, {}, context.temp_allocator); merr == nil do cfg.mixerBuses = strings.clone(string(text), allocator)
		}
	}
	if accObj, ok := json_get_obj(rootObj, "accessibility"); ok {
		if text, merr := json.marshal(accObj, {}, context.temp_allocator); merr == nil && len(accObj) > 0 do cfg.accessibility = strings.clone(string(text), allocator)
	}
	if debugObj, ok := json_get_obj(rootObj, "debug"); ok {
		cfg.consoleInRelease = json_get_bool(debugObj, "console_in_release", false)
		if k := json_get_string(debugObj, "console_key", ""); k != "" do cfg.consoleKey = strings.clone(k, allocator)
	}
	if inputObj, ok := json_get_obj(rootObj, "input"); ok {
		cfg.touchAsMouse = json_get_bool(inputObj, "touch_as_mouse", true)
		if arr, has := json_get_arr(inputObj, "actions"); has {
			cfg.actions = make([dynamic]Input_Action_Config, allocator)
			for v in arr {
				ao, isObj := v.(json.Object)
				if !isObj do continue
				name := json_get_string(ao, "name", "")
				if name == "" do continue
				a := Input_Action_Config{name = strings.clone(name, allocator), bindings = make([dynamic]InputBinding, allocator)}
				if binds, hb := json_get_arr(ao, "bindings"); hb {
					for bv in binds {
						if bo, isB := bv.(json.Object); isB {
							if b, bok := InputBinding_FromJSON(bo); bok do append(&a.bindings, b)
						}
					}
				}
				append(&cfg.actions, a)
			}
		}
	}
	if exportObj, ok := json_get_obj(rootObj, "export"); ok {
		cfg.export.executableName = strings.clone(json_get_string(exportObj, "executable", ""), allocator)
		cfg.export.outputDir = strings.clone(json_get_string(exportObj, "output_dir", ""), allocator)
		cfg.export.bundleId = strings.clone(json_get_string(exportObj, "bundle_id", ""), allocator)
		cfg.export.macSign = strings.clone(json_get_string(exportObj, "macos_sign", ""), allocator)
		cfg.export.macNotaryProfile = strings.clone(json_get_string(exportObj, "macos_notary_profile", ""), allocator)
		cfg.export.compress = json_get_bool(exportObj, "compress", cfg.export.compress)
		cfg.export.includeFont = json_get_bool(exportObj, "include_font", cfg.export.includeFont)
		Export_PresetsParse(exportObj, &cfg.export, allocator)
		if arr, has := json_get_arr(exportObj, "targets"); has {
			cfg.export.targets = {}
			for v in arr {
				if s, isStr := v.(json.String); isStr {
					switch strings.to_lower(string(s), context.temp_allocator) {
					case "macos":   cfg.export.targets += {.MacOS}
					case "windows": cfg.export.targets += {.Windows}
					case "linux":   cfg.export.targets += {.Linux}
					}
				}
			}
		}
	}

	// Physics settings
	if physObj, ok := json_get_obj(rootObj, "physics"); ok {
		cfg.gravity = json_get_vec2(physObj, "gravity", cfg.gravity)
		if v, has := physObj["debug_draw"].(json.Boolean); has do cfg.debugDraw = bool(v)
		if arr, has := json_get_arr(physObj, "layers"); has {
			for v, i in arr {
				if i >= 16 do break
				if s, isStr := v.(json.String); isStr && s != "" do cfg.collisionLayers[i] = strings.clone(s, allocator)
			}
		}
	}

	// Global scripts
	cfg.globals = make([dynamic]Global_Script, allocator)
	if arr, ok := json_get_arr(rootObj, "globals"); ok {
		for v in arr {
			o, isObj := v.(json.Object)
			if !isObj do continue
			name, script := json_get_string(o, "name", ""), json_get_string(o, "script", "")
			if name == "" || script == "" do continue
			append(&cfg.globals, Global_Script{strings.clone(name, allocator), strings.clone(script, allocator)})
		}
	}

	// Scenes
	if sceneArr, ok := json_get_arr(rootObj, "scenes"); ok {
		for sVal in sceneArr {
			if s, isStr := sVal.(json.String); isStr {
				append(&cfg.scenes, strings.clone(s, allocator))
			}
		}
	}

	return cfg, true
}

@(private = "file")
jstr :: proc(sb: ^strings.Builder, s: string) {
	strings.write_byte(sb, '"')
	for r in s {
		switch r {
		case '"':  strings.write_string(sb, `\"`)
		case '\\': strings.write_string(sb, `\\`)
		case '\n': strings.write_string(sb, `\n`)
		case:      strings.write_rune(sb, r)
		}
	}
	strings.write_byte(sb, '"')
}

Project_SerializeToJSON :: proc(cfg: ^ProjectConfig, allocator := context.allocator) -> string {
	if cfg == nil do return "{}"
	sb: strings.Builder
	strings.builder_init(&sb, allocator)

	strings.write_string(&sb, "{\n  \"name\": "); jstr(&sb, cfg.name)
	strings.write_string(&sb, ",\n  \"version\": "); jstr(&sb, cfg.version)
	// The release that saved it (a development build keeps what was there).
	engineVersion := cfg.engineVersion if Version_IsDev(RAYZR_RELEASE) else RAYZR_RELEASE
	if engineVersion != "" {strings.write_string(&sb, ",\n  \"engine_version\": "); jstr(&sb, engineVersion)}
	strings.write_string(&sb, ",\n  \"initial_scene\": "); jstr(&sb, cfg.initialScene)
	if cfg.icon != "" {strings.write_string(&sb, ",\n  \"icon\": "); jstr(&sb, cfg.icon)}
	if cfg.language != "" {strings.write_string(&sb, ",\n  \"language\": "); jstr(&sb, cfg.language)}
	if cfg.transition != "" {
		strings.write_string(&sb, ",\n  \"scene_flow\": {\"transition\": "); jstr(&sb, cfg.transition)
		if cfg.transitionDuration > 0 do fmt.sbprintf(&sb, ", \"duration\": %.2f", cfg.transitionDuration)
		if cfg.transitionEasing != "" {strings.write_string(&sb, ", \"easing\": "); jstr(&sb, cfg.transitionEasing)}
		strings.write_string(&sb, "}")
	}
	strings.write_string(&sb, ",\n  \"window\": {\n    \"title\": "); jstr(&sb, cfg.windowTitle)
	fmt.sbprintf(&sb, ",\n    \"width\": %d,\n", cfg.windowWidth)
	fmt.sbprintf(&sb, "    \"height\": %d,\n", cfg.windowHeight)
	fmt.sbprintf(&sb, "    \"virtual_width\": %.2f,\n", cfg.virtualWidth)
	fmt.sbprintf(&sb, "    \"virtual_height\": %.2f,\n", cfg.virtualHeight)
	fmt.sbprintf(&sb, "    \"target_fps\": %d\n", cfg.targetFPS)
	strings.write_string(&sb, "  },\n")
	fmt.sbprintf(&sb, "  \"video\": {{\"fill\": \"%s\", \"fullscreen\": %t, \"vsync\": %t, \"resizable\": %t, \"msaa\": %t, \"high_dpi\": %t, \"sharp_scaling\": %t, \"integer_scaling\": %t, \"pixel_snap\": %t, \"smooth_camera\": %t}},\n", Screen_Fill_Name(cfg.fill), cfg.fullscreen, cfg.vsync, cfg.resizable, cfg.msaa, cfg.highDPI, cfg.sharpScaling, cfg.integerScaling, cfg.pixelSnap, cfg.smoothCamera)
	if cfg.consoleInRelease || cfg.consoleKey != "" {
		fmt.sbprintf(&sb, "  \"debug\": {{\"console_in_release\": %t", cfg.consoleInRelease)
		if cfg.consoleKey != "" {strings.write_string(&sb, ", \"console_key\": "); jstr(&sb, cfg.consoleKey)}
		strings.write_string(&sb, "},\n")
	}
	fmt.sbprintf(&sb, "  \"audio\": {{\"master_volume\": %.2f, \"music_volume\": %.2f, \"sfx_volume\": %.2f", cfg.masterVolume, cfg.musicVolume, cfg.sfxVolume)
	if cfg.mixerBuses != "" do fmt.sbprintf(&sb, ", \"buses\": %s", cfg.mixerBuses)
	strings.write_string(&sb, "},\n")
	if cfg.accessibility != "" do fmt.sbprintf(&sb, "  \"accessibility\": %s,\n", cfg.accessibility)
	strings.write_string(&sb, "  \"physics\": {\n")
	fmt.sbprintf(&sb, "    \"gravity\": [%.2f, %.2f],\n    \"debug_draw\": %t", cfg.gravity.x, cfg.gravity.y, cfg.debugDraw)
	last := -1
	for n, i in cfg.collisionLayers do if n != "" do last = i
	if last >= 0 {
		strings.write_string(&sb, ",\n    \"layers\": [")
		for i in 0 ..= last {
			if i > 0 do strings.write_string(&sb, ", ")
			jstr(&sb, cfg.collisionLayers[i])
		}
		strings.write_byte(&sb, ']')
	}
	strings.write_byte(&sb, '\n')
	strings.write_string(&sb, "  },\n")
	if len(cfg.actions) > 0 || !cfg.touchAsMouse {
		strings.write_string(&sb, "  \"input\": {")
		if !cfg.touchAsMouse do strings.write_string(&sb, "\"touch_as_mouse\": false, ")
		strings.write_string(&sb, "\"actions\": [\n")
		for a, i in cfg.actions {
			strings.write_string(&sb, "    {\"name\": "); jstr(&sb, a.name)
			strings.write_string(&sb, ", \"bindings\": [")
			for b, bi in a.bindings {
				if bi > 0 do strings.write_string(&sb, ", ")
				InputBinding_WriteJSON(&sb, b)
			}
			strings.write_string(&sb, "]}")
			strings.write_string(&sb, ",\n" if i < len(cfg.actions) - 1 else "\n")
		}
		strings.write_string(&sb, "  ]},\n")
	}
	strings.write_string(&sb, "  \"export\": {\"executable\": "); jstr(&sb, cfg.export.executableName)
	strings.write_string(&sb, ", \"output_dir\": "); jstr(&sb, cfg.export.outputDir)
	strings.write_string(&sb, ", \"targets\": [")
	n := 0
	for t in Export_Target {
		if t not_in cfg.export.targets do continue
		if n > 0 do strings.write_string(&sb, ", ")
		fmt.sbprintf(&sb, "\"%s\"", export_target_name(t))
		n += 1
	}
	fmt.sbprintf(&sb, "], \"compress\": %t, \"include_font\": %t", cfg.export.compress, cfg.export.includeFont)
	if cfg.export.bundleId != "" {strings.write_string(&sb, ", \"bundle_id\": "); jstr(&sb, cfg.export.bundleId)}
	if cfg.export.macSign != "" {strings.write_string(&sb, ", \"macos_sign\": "); jstr(&sb, cfg.export.macSign)}
	if cfg.export.macNotaryProfile != "" {strings.write_string(&sb, ", \"macos_notary_profile\": "); jstr(&sb, cfg.export.macNotaryProfile)}
	Export_PresetsWrite(&sb, &cfg.export)
	strings.write_string(&sb, "},\n")
	texture_imports_write(&sb, cfg.textureImport[:])
	if len(cfg.globals) > 0 {
		strings.write_string(&sb, "  \"globals\": [\n")
		for g, i in cfg.globals {
			strings.write_string(&sb, "    {\"name\": "); jstr(&sb, g.name)
			strings.write_string(&sb, ", \"script\": "); jstr(&sb, g.script)
			strings.write_string(&sb, "},\n" if i < len(cfg.globals) - 1 else "}\n")
		}
		strings.write_string(&sb, "  ],\n")
	}
	strings.write_string(&sb, "  \"scenes\": [\n")
	for sc, i in cfg.scenes {
		strings.write_string(&sb, "    "); jstr(&sb, sc)
		strings.write_string(&sb, ",\n" if i < len(cfg.scenes) - 1 else "\n")
	}
	strings.write_string(&sb, "  ]\n}\n")
	return strings.to_string(sb)
}

export_target_name :: proc(t: Export_Target) -> string {
	switch t {
	case .MacOS: return "macos"
	case .Windows: return "windows"
	case .Linux: return "linux"
	case .Web: return "web"
	}
	return ""
}

native_export_target :: proc() -> Export_Target {
	when ODIN_OS == .Darwin do return .MacOS
	else when ODIN_OS == .Windows do return .Windows
	else do return .Linux
}

Project_SaveConfigToFile :: proc(projectDir: string, cfg: ^ProjectConfig) -> bool {
	if cfg == nil do return false
	jsonStr := Project_SerializeToJSON(cfg, context.temp_allocator)
	projPath, _ := filepath.join({projectDir, "project.json"}, context.temp_allocator)
	return os.write_entire_file(projPath, transmute([]u8)jsonStr) == nil
}

// ----------------------------------------------------------------------------
// High-Level Project Loading (From Directory or .rayzr Archive)
// ----------------------------------------------------------------------------

Game_LoadProjectConfig :: proc(game: ^Game, cfg: ^ProjectConfig, activate := true) -> bool {
	if game == nil || cfg == nil do return false
	Save_SetGameName(cfg.name) // Save data folder
	Locale_Reset()
	Locale_SetLanguage(cfg.language)
	Transition_SetDefault(game, cfg.transition, cfg.transitionDuration, cfg.transitionEasing)

	if cfg.virtualWidth > 0 && cfg.virtualHeight > 0 {
		game.virtualSize = {cfg.virtualWidth, cfg.virtualHeight}
		game.designSize = game.virtualSize
	}
	game.fill = cfg.fill
	Render_SetPixelSettings({integerScaling = cfg.integerScaling, snap = cfg.pixelSnap, smooth = cfg.smoothCamera})
	game.physicsWorld.gravity = cfg.gravity
	Physics_SetLayerNames(cfg.collisionLayers[:])
	game.musicVolume = cfg.musicVolume
	game.sfxVolume = cfg.sfxVolume
	game.masterVolume = cfg.masterVolume
	Mixer_ApplyProject(cfg) // buses, faders, effects (mixer_config.odin)
	Input_ApplyActionConfigs(&game.input, cfg.actions[:])
	game.input.touch.asMouse = cfg.touchAsMouse
	Input_RebindSetDefaults(&game.input, cfg.actions[:]) // (Input.reset_bindings)
	if activate do Input_LoadUserBindings(&game.input) // the player's own (the game, not the editor)
	Access_SetDefaults(ProjectConfig_Accessibility(cfg))
	if activate do Access_Load() // the player's accessibility settings (the game, not the editor)
	Texture_ImportsSet(cfg.textureImport[:])
	Asset_ImportsReset() // per-asset settings are read again as assets load
	// Global scripts exist before any scene; the game starts them (ready)
	// now, the editor when Simulate starts.
	Globals_Load(&game.scriptManager, cfg.globals[:])
	if activate do Globals_Ready(&game.scriptManager)

	if rl.IsWindowReady() {
		if cfg.windowTitle != "" {
			titleC := strings.clone_to_cstring(cfg.windowTitle, context.temp_allocator)
			rl.SetWindowTitle(titleC)
		}
		if cfg.windowWidth > 0 && cfg.windowHeight > 0 {
			rl.SetWindowSize(c.int(cfg.windowWidth), c.int(cfg.windowHeight))
		}
		if cfg.targetFPS > 0 {
			rl.SetTargetFPS(c.int(cfg.targetFPS))
		}
	}

	// Register each declared scene. Scenes are built lazily from their JSON
	// (Scene_JsonSetup) when entered, and rebuilt on every re-entry.
	for scenePath in cfg.scenes {
		_ = Game_RegisterSceneFile(game, scenePath, scenePath == cfg.initialScene)
	}
	// initial_scene may also name a scene instead of a path.
	if game.sceneManager.nextScene == nil && cfg.initialScene != "" {
		if s, ok := game.sceneManager.scenes[cfg.initialScene]; ok {
			game.sceneManager.nextScene = s
		} else {
			// Or point at a file that isn't in "scenes".
			_ = Game_RegisterSceneFile(game, cfg.initialScene, true)
		}
	}
	if game.sceneManager.nextScene == nil {
		log.warnf("[ProjectLoader] initial_scene '%s' not found", cfg.initialScene)
	}

	if activate {
		// The game (not the editor, which shows colliders itself).
		game.physicsWorld.drawPhysicsDebug = cfg.debugDraw
		ProcessSceneChange(&game.sceneManager, &game.gameContext)
	}
	return true
}

// Game_LoadProjectForEditing mounts a project directory and registers its
// scenes without entering one (no ready() calls, no scripts run) — the
// editor then opens scenes with Scene_LoadForEditing.
Game_LoadProjectForEditing :: proc(game: ^Game, projectDir: string) -> (ProjectConfig, bool) {
	cfg: ProjectConfig
	if game == nil do return cfg, false
	AssetManager_SetProjectDir(&game.assetManager, projectDir)
	game.resourceManager.projectDir = game.assetManager.projectDir // (borrowed: project-relative keys for import settings)
	projPath, _ := filepath.join({projectDir, "project.json"}, context.temp_allocator)
	bytes, readErr := os.read_entire_file(projPath, context.temp_allocator)
	if readErr != nil {
		log.errorf("[ProjectLoader] Missing project.json in directory: %s", projectDir)
		return cfg, false
	}
	parsed, parseOk := Project_ParseConfig(bytes)
	if !parseOk do return cfg, false
	cfg = parsed
	ok := Game_LoadProjectConfig(game, &cfg, activate = false)
	game.sceneManager.nextScene = nil
	return cfg, ok
}

// Scene_LoadForEditing builds a scene's nodes without calling ready() or
// starting scripts, so the editor shows (and saves) the scene as authored.
Scene_LoadForEditing :: proc(scene: ^Scene, gameContext: ^GameContext) {
	if scene == nil do return
	if scene.manager == nil {
		InitializeScene(scene)
	} else if scene.isLoaded {
		Scene_Unload(scene, gameContext)
	}
	if scene.rootNode != nil do scene.rootNode.gameContext = gameContext
	if scene.setup != nil do scene->setup(gameContext)
	ProcessNodeQueues(scene.manager, gameContext)
	Node_SetGlobalPositions(scene.manager, scene.rootNode)
	scene.isLoaded = true
}

// Game_SceneNameForFile picks the registry name of a scene file: the file's
// "name", unless another file already uses it (then the file's stem, then
// the path) — two files can never shadow each other.
Game_SceneNameForFile :: proc(game: ^Game, scenePath: string, sceneBytes: []u8) -> string {
	stem := filepath.stem(filepath.stem(scenePath)) // "main.scene.json" -> "main"
	candidates := [3]string{Scene_ReadJSONName(sceneBytes), stem, scenePath}
	for name in candidates {
		if name == "" do continue
		existing, taken := game.sceneManager.scenes[name]
		if !taken || existing == nil || existing.filePath == scenePath do return name
		log.warnf("[ProjectLoader] Scene name '%s' of '%s' is already used by '%s'", name, scenePath, existing.filePath)
	}
	return scenePath
}

// Game_RegisterSceneFile registers (or re-registers) a scene file. Returns
// the scene, or nil if the file can't be read.
Game_RegisterSceneFile :: proc(game: ^Game, scenePath: string, makeCurrent: bool = false) -> ^Scene {
	sceneBytes, ok := AssetManager_ReadFileBytes(&game.assetManager, scenePath, context.temp_allocator)
	if !ok {
		log.warnf("[ProjectLoader] Scene file '%s' not found", scenePath)
		return nil
	}
	name := Game_SceneNameForFile(game, scenePath, sceneBytes)
	scene := game->createScene(name, makeCurrent, Scene_JsonSetup)
	if scene == nil do return nil
	allocator := game.sceneManager.allocator if game.sceneManager.allocator.procedure != nil else context.allocator
	scene.filePath = strings.clone(scenePath, allocator)
	scene.sourceJson = strings.clone(string(sceneBytes), allocator)
	return scene
}

// Game_FindSceneByFile finds a registered scene by its file path.
Game_FindSceneByFile :: proc(game: ^Game, scenePath: string) -> ^Scene {
	for _, s in game.sceneManager.scenes {
		if s != nil && s.filePath == scenePath do return s
	}
	return nil
}

Game_LoadProjectFromDirectory :: proc(game: ^Game, projectDir: string) -> bool {
	if game == nil do return false
	Project_MigrateLegacyDir(projectDir) // .ore/ -> .rayzr/ (branding.odin)
	AssetManager_SetProjectDir(&game.assetManager, projectDir)
	game.resourceManager.projectDir = game.assetManager.projectDir // (borrowed: project-relative keys for import settings)

	projPath, _ := filepath.join({projectDir, "project.json"}, context.temp_allocator)
	bytes, readErr := os.read_entire_file(projPath, context.temp_allocator)
	if readErr != nil {
		log.errorf("[ProjectLoader] Missing project.json in directory: %s", projectDir)
		return false
	}

	cfg, parseOk := Project_ParseConfig(bytes, context.temp_allocator)
	if !parseOk do return false

	return Game_LoadProjectConfig(game, &cfg)
}

Game_LoadProjectFromRayzr :: proc(game: ^Game, rayzrFilePath: string) -> bool {
	if game == nil do return false
	pkg, ok := RayzrPackage_Open(rayzrFilePath, game.assetManager.allocator)
	if !ok {
		log.errorf("[ProjectLoader] Failed to open .rayzr archive: %s", rayzrFilePath)
		return false
	}
	AssetManager_MountPackage(&game.assetManager, pkg)
	game.resourceManager.package_ = pkg
	if Atlas_Mount(&game.resourceManager) do log.infof("[ProjectLoader] Sprite atlas: %d images on %d page(s)", len(game.resourceManager.atlas.entries), len(game.resourceManager.atlas.pages))
	game.scriptManager.hotReload = false // packaged scripts don't change

	bytes, readOk := AssetManager_ReadFileBytes(&game.assetManager, "project.json", context.temp_allocator)
	if !readOk {
		log.error("[ProjectLoader] project.json not found in .rayzr archive")
		return false
	}

	cfg, parseOk := Project_ParseConfig(bytes, context.temp_allocator)
	if !parseOk do return false

	return Game_LoadProjectConfig(game, &cfg)
}

Game_LoadProject :: proc(game: ^Game, pathOrDir: string) -> bool {
	if Is_PackagePath(pathOrDir) {
		return Game_LoadProjectFromRayzr(game, pathOrDir)
	}
	return Game_LoadProjectFromDirectory(game, pathOrDir)
}

// ProjectConfig_Accessibility: the project's default accessibility settings.
ProjectConfig_Accessibility :: proc(cfg: ^ProjectConfig) -> Access_Settings {
	if cfg == nil || cfg.accessibility == "" do return ACCESS_DEFAULTS
	v, err := json.parse_string(cfg.accessibility, allocator = context.temp_allocator)
	if err != nil do return ACCESS_DEFAULTS
	o, ok := v.(json.Object)
	if !ok do return ACCESS_DEFAULTS
	return Access_FromJSON(o, ACCESS_DEFAULTS)
}

// ProjectConfig_SetAccessibility stores the defaults (only what differs
// from the engine's).
ProjectConfig_SetAccessibility :: proc(cfg: ^ProjectConfig, s: Access_Settings, allocator := context.allocator) {
	if cfg.accessibility != "" do delete(cfg.accessibility, allocator)
	text := Access_ToJSON(Access_Clamp(s), context.temp_allocator, ACCESS_DEFAULTS)
	cfg.accessibility = strings.clone(text, allocator) if text != "{}" else ""
}
