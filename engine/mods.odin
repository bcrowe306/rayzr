package engine

import "base:runtime"
import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import os "osx"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import lua "lua54"

// ============================================================================
// Runtime mods for exported games (#286; guide: engine/docs/modding.md).
//
// A project allows mods with its export setting "mods" (project.json
// export.mods): "off" (the default), "assets" (file overrides and new
// files) or "scripts" (also sandboxed mod Lua). A game then looks for mods
// in mods/ next to the game and in <user data>/mods/ (the same id in both:
// the user-data one wins) - one folder per mod, with a mod.json:
//
//   {"id": "bigger_coins", "name": "Bigger Coins", "version": "1.0.0",
//    "game": ">=1.2.0", "load_order": 0, "dependencies": ["core_lib"],
//    "scenes": ["scenes/bonus.scene.json"], "main": "main.lua"}
//
// A mod's files mirror the game's: mods/bigger_coins/textures/coin.png
// replaces the game's textures/coin.png (later mods win); new paths are new
// files. <user data>/mods.json keeps the player's choices ({"disabled":
// [...], "order": [...]}: Mods.set_enabled / set_order write it; they apply
// on the next launch).
//
// Mod Lua (main.lua, the mod's require()d files, any .lua it adds or
// overrides) runs in the game's Lua state, each mod in its own environment:
// the game API, but no io / os (time only) / debug / package / dofile /
// loadfile, load() of text only, require() inside the mod's folder,
// Mods.fs for the mod's folder (and "save:" paths in its own save folder).
// A count hook charges every 1000 instructions to the running mod; a mod
// over its budget (a frame's, or its loading's) is stopped. A mod that
// fails (a load error, a failing main.lua or handler) is logged and set
// aside; the game goes on.
//
// Desktop only: the web and Android runners don't look for mods.
// ============================================================================

Mods_Mode :: enum u8 {Off, Assets, Scripts}

Mod_Status :: enum u8 {
	Loaded,
	Disabled,           // the player turned it off (mods.json)
	Incompatible,       // mod.json "game" asks for a newer game
	Missing_Dependency, // a dependency isn't there (or not loaded)
	Failed,             // a bad mod.json, a dependency cycle, an error in its Lua
	Stopped,            // ran past its instruction budget
}

Mod :: struct {
	id, name, version, description, author: string,
	gameReq:      string, // mod.json "game": the oldest game version it needs (">=1.2.0")
	main:         string, // mod.json "main" (default main.lua; scripts mode)
	dir:          string, // the mod's folder (absolute or as found)
	loadOrder:    int,
	dependencies: [dynamic]string,
	scenes:       [dynamic]string,
	status:       Mod_Status,
	enabledAtStart: bool, // (Mods.restart_needed)
	error:        string,
	envRef:       c.int,
	ticks:        int,    // instruction-budget ticks used (this frame / while loading)
}

Mods_State :: struct {
	arena:        runtime.Arena,
	alloc:        runtime.Allocator,
	ready:        bool,
	mode:         Mods_Mode,
	list:         [dynamic]Mod, // every mod found, in load order (the not loaded ones last)
	active:       [dynamic]int, // indices into list of the loaded mods, in load order
	folders:      [dynamic]string,
	settingsPath: string,       // <user data>/mods.json ("" = none: changes aren't kept)
	dataDir:      string,       // <user data>/mod_data (Mods.fs "save:" paths)
	disabled:     [dynamic]string, // mods.json "disabled"
	order:        [dynamic]string, // mods.json "order"
	restartNeeded: bool,
	L:            ^lua.State,
	preludeRef:   c.int,
	hooked:       bool,
	loading:      bool,
	frameBudget:  int, // ticks (of MODS_HOOK_EVERY instructions) a mod may use a frame
	loadBudget:   int, // ... while its main.lua runs
	lastScene:    rawptr,
	started:      bool,
}

mods: Mods_State

// Mods_Supported: false in runners that don't take mods (Android sets it).
Mods_Supported := ODIN_OS != .JS

MODS_HOOK_EVERY :: 1000
MODS_FRAME_BUDGET :: 20_000  // 20 M instructions a frame
MODS_LOAD_BUDGET :: 200_000  // 200 M while a mod's main.lua runs

Mods_ModeName :: proc(m: Mods_Mode) -> string {
	switch m {
	case .Off: return "off"
	case .Assets: return "assets"
	case .Scripts: return "scripts"
	}
	return "off"
}

Mods_ParseMode :: proc(s: string) -> Mods_Mode {
	switch strings.to_lower(strings.trim_space(s), context.temp_allocator) {
	case "assets": return .Assets
	case "scripts", "all": return .Scripts
	}
	return .Off
}

Mod_StatusName :: proc(s: Mod_Status) -> string {
	switch s {
	case .Loaded: return "loaded"
	case .Disabled: return "disabled"
	case .Incompatible: return "incompatible"
	case .Missing_Dependency: return "missing_dependency"
	case .Failed: return "failed"
	case .Stopped: return "stopped"
	}
	return ""
}

// Mods_Reset drops every mod (the overrides, the hook, the Lua state's
// mod environments are left to the state: call before closing it).
Mods_Reset :: proc() {
	if mods.hooked && mods.L != nil do lua.sethook(mods.L, nil, {}, 0)
	if mods.ready do runtime.arena_destroy(&mods.arena)
	mods = {}
}

@(private = "file")
mods_init :: proc() {
	if mods.ready do return
	_ = runtime.arena_init(&mods.arena, 0, Engine_HeapAllocator())
	mods.alloc = runtime.arena_allocator(&mods.arena)
	mods.list = make([dynamic]Mod, mods.alloc)
	mods.active = make([dynamic]int, mods.alloc)
	mods.folders = make([dynamic]string, mods.alloc)
	mods.disabled = make([dynamic]string, mods.alloc)
	mods.order = make([dynamic]string, mods.alloc)
	mods.frameBudget = MODS_FRAME_BUDGET
	mods.loadBudget = MODS_LOAD_BUDGET
	mods.ready = true
}

// --- discovery and load order -------------------------------------------------------

// Mods_Discover finds the mods in `folders` (later folders win for the same
// id), applies mods.json at `settingsPath` (may be "") and sorts them into
// load order: mods.json "order", then load_order, then id - a mod after its
// dependencies. `gameVersion`: the project's version (mod.json "game").
Mods_Discover :: proc(folders: []string, settingsPath: string, gameVersion: string, mode: Mods_Mode = .Scripts) {
	Mods_Reset()
	mods_init()
	a := mods.alloc
	mods.mode = mode
	mods.settingsPath = strings.clone(settingsPath, a)
	for f in folders do append(&mods.folders, strings.clone(f, a))
	mods_read_settings()

	found := make([dynamic]Mod, context.temp_allocator)
	for folder in folders {
		infos, err := os.read_all_directory_by_path(folder, context.temp_allocator)
		if err != nil do continue
		slice.sort_by(infos, proc(x, y: os.File_Info) -> bool {return x.name < y.name})
		for fi in infos {
			if fi.type != .Directory || strings.has_prefix(fi.name, ".") do continue
			m, ok := mods_read_manifest(fi.fullpath, fi.name)
			if !ok do continue
			replaced := false
			for &o in found do if o.id == m.id {o = m; replaced = true}
			if !replaced do append(&found, m)
		}
	}
	for &m in found {
		if m.status != .Loaded do continue
		if slice.contains(mods.disabled[:], m.id) {
			m.status = .Disabled
			continue
		}
		if req := strings.trim_left(m.gameReq, ">= "); req != "" && gameVersion != "" && Version_Compare(gameVersion, req) < 0 {
			m.status = .Incompatible
			m.error = fmt.aprintf("needs game version %s or newer (this is %s)", req, gameVersion, allocator = a)
		}
	}
	// The sort: mods.json order, load_order, id.
	rank :: proc(id: string) -> int {
		for o, i in mods.order do if o == id do return i
		return max(int)
	}
	slice.sort_by(found[:], proc(x, y: Mod) -> bool {
		rx, ry := rank(x.id), rank(y.id)
		if rx != ry do return rx < ry
		if x.loadOrder != y.loadOrder do return x.loadOrder < y.loadOrder
		return x.id < y.id
	})
	// Dependencies first (a depth-first walk; cycles fail).
	state := make([]u8, len(found), context.temp_allocator) // 0 new, 1 visiting, 2 done
	ordered := make([dynamic]int, context.temp_allocator)
	visit :: proc(found: []Mod, state: []u8, ordered: ^[dynamic]int, i: int) {
		if state[i] == 2 do return
		m := &found[i]
		if state[i] == 1 {
			if m.status == .Loaded {
				m.status = .Failed
				m.error = fmt.aprintf("dependency cycle through %s", m.id, allocator = mods.alloc)
			}
			return
		}
		state[i] = 1
		for dep in m.dependencies {
			depId, depMin := dep, ""
			if k := strings.index(dep, ">="); k >= 0 do depId, depMin = strings.trim_space(dep[:k]), strings.trim_space(dep[k + 2:])
			j := -1
			for &o, n in found do if o.id == depId do j = n
			if j < 0 {
				if m.status == .Loaded {
					m.status = .Missing_Dependency
					m.error = fmt.aprintf("needs the mod %s, which isn't installed", depId, allocator = mods.alloc)
				}
				continue
			}
			visit(found, state, ordered, j)
			why := ""
			switch {
			case found[j].status != .Loaded: why = fmt.tprintf("needs the mod %s, which is %s", depId, Mod_StatusName(found[j].status))
			case depMin != "" && Version_Compare(found[j].version, depMin) < 0: why = fmt.tprintf("needs %s %s or newer (installed: %s)", depId, depMin, found[j].version)
			}
			if why != "" && m.status == .Loaded {
				m.status = .Missing_Dependency
				m.error = strings.clone(why, mods.alloc)
			}
		}
		state[i] = 2
		append(ordered, i)
	}
	for _, i in found do visit(found[:], state, &ordered, i)
	for i in ordered do if found[i].status == .Loaded {
		append(&mods.list, found[i])
		append(&mods.active, len(mods.list) - 1)
	}
	for i in ordered do if found[i].status != .Loaded do append(&mods.list, found[i])
	for &m in mods.list {
		m.enabledAtStart = m.status != .Disabled
		if m.status != .Loaded && m.status != .Disabled do log.warnf("[Mods] %s (%s) not loaded: %s - %s", m.name, m.id, Mod_StatusName(m.status), m.error)
	}
	if len(mods.active) > 0 {
		names := make([dynamic]string, context.temp_allocator)
		for i in mods.active do append(&names, fmt.tprintf("%s %s", mods.list[i].id, mods.list[i].version))
		log.infof("[Mods] %d mod(s), %s: %s", len(mods.active), Mods_ModeName(mode), strings.join(names[:], ", ", context.temp_allocator))
	}
}

@(private = "file")
mods_read_manifest :: proc(dir, folderName: string) -> (m: Mod, ok: bool) {
	a := mods.alloc
	path, _ := filepath.join({dir, "mod.json"}, context.temp_allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil do return m, false // (not a mod)
	m.dir = strings.clone(dir, a)
	m.id = strings.clone(folderName, a)
	m.name = m.id
	m.version = "0.0.0"
	m.main = "main.lua"
	m.dependencies = make([dynamic]string, a)
	m.scenes = make([dynamic]string, a)
	v, perr := json.parse(data, allocator = context.temp_allocator)
	o, isObj := v.(json.Object)
	if perr != nil || !isObj {
		m.status = .Failed
		m.error = fmt.aprintf("mod.json isn't a JSON object (%v)", perr, allocator = a)
		return m, true
	}
	str :: proc(o: json.Object, key, def: string) -> string {
		if s, isStr := o[key].(json.String); isStr && s != "" do return strings.clone(string(s), mods.alloc)
		return def
	}
	m.id = str(o, "id", m.id)
	m.name = str(o, "name", m.id)
	m.version = str(o, "version", m.version)
	m.description = str(o, "description", "")
	m.author = str(o, "author", "")
	m.gameReq = str(o, "game", "")
	m.main = str(o, "main", m.main)
	#partial switch n in o["load_order"] {
	case json.Integer: m.loadOrder = int(n)
	case json.Float: m.loadOrder = int(n)
	}
	if arr, isArr := o["dependencies"].(json.Array); isArr {
		for d in arr do if s, isStr := d.(json.String); isStr do append(&m.dependencies, strings.clone(string(s), a))
	}
	if arr, isArr := o["scenes"].(json.Array); isArr {
		for d in arr do if s, isStr := d.(json.String); isStr {
			if rel, safe := Mods_SafePath(string(s)); safe do append(&m.scenes, strings.clone(rel, a))
		}
	}
	return m, true
}

@(private = "file")
mods_read_settings :: proc() {
	if mods.settingsPath == "" do return
	data, err := os.read_entire_file(mods.settingsPath, context.temp_allocator)
	if err != nil do return
	v, perr := json.parse(data, allocator = context.temp_allocator)
	o, isObj := v.(json.Object)
	if perr != nil || !isObj {
		log.warnf("[Mods] %s isn't a JSON object: ignored", mods.settingsPath)
		return
	}
	if arr, isArr := o["disabled"].(json.Array); isArr {
		for d in arr do if s, isStr := d.(json.String); isStr do append(&mods.disabled, strings.clone(string(s), mods.alloc))
	}
	if arr, isArr := o["order"].(json.Array); isArr {
		for d in arr do if s, isStr := d.(json.String); isStr do append(&mods.order, strings.clone(string(s), mods.alloc))
	}
}

// Mods_WriteSettings writes mods.json (the disabled mods and the order).
Mods_WriteSettings :: proc() -> bool {
	if mods.settingsPath == "" do return false
	Settings :: struct {disabled: []string, order: []string}
	out, merr := json.marshal(Settings{mods.disabled[:], mods.order[:]}, {pretty = true}, context.temp_allocator)
	if merr != nil do return false
	_ = os.make_directory_all(filepath.dir(mods.settingsPath, context.temp_allocator))
	return os.write_entire_file(mods.settingsPath, out) == nil
}

// Mods_SetEnabled turns a mod on or off for the next launch (mods.json).
Mods_SetEnabled :: proc(id: string, on: bool) -> bool {
	idx := Mods_Find(id)
	if idx < 0 do return false
	for i := len(mods.disabled) - 1; i >= 0; i -= 1 do if mods.disabled[i] == id do ordered_remove(&mods.disabled, i)
	if !on do append(&mods.disabled, strings.clone(id, mods.alloc))
	mods.restartNeeded = false
	for m in mods.list do if m.enabledAtStart == slice.contains(mods.disabled[:], m.id) do mods.restartNeeded = true
	return Mods_WriteSettings()
}

// Mods_SetOrder sets the player's load order for the next launch (mods.json).
Mods_SetOrder :: proc(ids: []string) -> bool {
	if !mods.ready do return false
	clear(&mods.order)
	for id in ids do append(&mods.order, strings.clone(id, mods.alloc))
	mods.restartNeeded = true
	return Mods_WriteSettings()
}

Mods_Find :: proc(id: string) -> int {
	for m, i in mods.list do if m.id == id do return i
	return -1
}

// --- file overrides -----------------------------------------------------------------

// Mods_SafePath: a project-relative path a mod may provide or read - no
// absolute paths, no "..", forward slashes.
Mods_SafePath :: proc(path: string) -> (string, bool) {
	p, _ := strings.replace_all(strings.trim_space(path), "\\", "/", context.temp_allocator)
	for strings.has_prefix(p, "./") do p = p[2:]
	if p == "" || strings.has_prefix(p, "/") || (len(p) > 1 && p[1] == ':') do return "", false
	for part in strings.split(p, "/", context.temp_allocator) do if part == ".." do return "", false
	return p, true
}

// Mods_OverridePath: the file of the last loaded mod that has `rel`
// (a project-relative path), and that mod's index in mods.list.
Mods_OverridePath :: proc(rel: string, allocator := context.temp_allocator) -> (path: string, modIndex: int, ok: bool) {
	if len(mods.active) == 0 do return "", -1, false
	p, safe := Mods_SafePath(rel)
	if !safe || p == "project.json" do return "", -1, false
	if mods.mode != .Scripts && (strings.has_suffix(p, ".lua") || strings.has_suffix(p, ".luac")) do return "", -1, false
	#reverse for i in mods.active {
		full, _ := filepath.join({mods.list[i].dir, p}, allocator)
		if os.is_file(full) do return full, i, true
	}
	return "", -1, false
}

// Mods_ResourceDiskPath: the file a resource loader opens for `filePath`
// (project-relative, or under projectDir) - a mod's when one overrides it.
Mods_ResourceDiskPath :: proc(projectDir, filePath: string) -> (path: string, modded: bool) {
	if len(mods.active) == 0 do return filePath, false
	rel := filePath
	if dir := strings.trim_suffix(projectDir, "/"); dir != "" && len(rel) > len(dir) && rel[:len(dir)] == dir && rel[len(dir)] == '/' {
		rel = rel[len(dir) + 1:]
	}
	if p, _, ok := Mods_OverridePath(rel); ok do return p, true
	return filePath, false
}

// --- runner integration -------------------------------------------------------------

// Mods_Folders: where a game looks for mods - mods/ next to the game (the
// executable's folder; a macOS .app: the folder holding it; a .rayzr
// elsewhere: its folder too), `extra` (--mods), then <user data>/mods.
Mods_Folders :: proc(exePath, projectPath, extra, userData: string, allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, allocator)
	add :: proc(out: ^[dynamic]string, dir: string, allocator: runtime.Allocator) {
		if dir == "" do return
		p, _ := filepath.join({dir, "mods"}, allocator)
		for o in out do if o == p do return
		append(out, p)
	}
	if exePath != "" {
		exeDir := filepath.dir(exePath, context.temp_allocator)
		if strings.has_suffix(exeDir, "Contents/MacOS") {
			exeDir = filepath.dir(filepath.dir(filepath.dir(exeDir, context.temp_allocator), context.temp_allocator), context.temp_allocator)
		}
		add(&out, exeDir, allocator)
	}
	if Is_PackagePath(projectPath) && !strings.contains(projectPath, APPENDED_PACKAGE_SUFFIX) {
		d := filepath.dir(projectPath, context.temp_allocator)
		if !strings.has_suffix(d, "Contents/Resources") do add(&out, d, allocator)
	}
	if extra != "" && !slice.contains(out[:], extra) do append(&out, strings.clone(extra, allocator))
	add(&out, userData, allocator)
	return out[:]
}

// Mods_Setup (the runner, before the project loads): finds the mods the
// project allows and puts their files over the game's.
Mods_Setup :: proc(game: ^Game, cfg: ^ProjectConfig, opts: Run_Options) {
	Mods_Reset()
	if !Mods_Supported || opts.noMods || opts.editorLink || slice.contains(os.args, "--editor-link") do return
	if cfg.export.mods == .Off {
		if opts.modsDir != "" do log.warnf("[Mods] --mods %s: this game doesn't allow mods (project export setting \"mods\")", opts.modsDir)
		return
	}
	userData := Save_UserDataDir(cfg.name)
	exe := os.args[0] if len(os.args) > 0 else ""
	folders := Mods_Folders(exe, opts.projectPath, opts.modsDir, userData)
	settings, _ := filepath.join({userData, "mods.json"}, context.temp_allocator)
	Mods_Discover(folders, settings, cfg.version, cfg.export.mods)
	mods.dataDir, _ = filepath.join({userData, "mod_data"}, mods.alloc)
	if game != nil && cfg.export.mods == .Scripts && len(mods.active) > 0 {
		game.scriptManager.hotReload = false // (a reload would run a mod's file as the game's)
		Mods_Attach(game.scriptManager.L)
	}
}

// Mods_Attach: script mods run in this Lua state (the game's), under the
// instruction-budget hook.
Mods_Attach :: proc(L: ^lua.State) {
	Mods_UseState(L)
	if L == nil || len(mods.active) == 0 || mods.mode != .Scripts do return
	lua.sethook(L, mods_hook, lua.MASKCOUNT, MODS_HOOK_EVERY)
	mods.hooked = true
}

// Mods_Start (once the project is loaded): registers the mods' scenes, runs
// each script mod's main.lua (in load order) and raises "mods_loaded".
Mods_Start :: proc(game: ^Game) {
	if len(mods.active) == 0 || mods.started do return
	mods.started = true
	if game != nil do for i in mods.active {
		for s in mods.list[i].scenes {
			if Game_FindSceneByFile(game, s) == nil && Game_RegisterSceneFile(game, s) == nil {
				log.warnf("[Mods] %s: scene %s not found", mods.list[i].id, s)
			}
		}
	}
	if mods.mode != .Scripts || mods.L == nil do return
	L := mods.L
	mods.loading = true
	for i in mods.active {
		m := &mods.list[i]
		if m.status != .Loaded do continue
		mainPath, _ := filepath.join({m.dir, m.main}, context.temp_allocator)
		if !os.is_file(mainPath) do continue
		m.ticks = 0
		base := lua.gettop(L)
		if !mods_load_chunk(L, i, m.main) {
			Mods_Fail(i, "main.lua", string(lua.tostring(L, -1)))
			lua.settop(L, base)
			continue
		}
		if lua.pcall(L, 0, 0, 0) != 0 do Mods_Fail(i, m.main, string(lua.tostring(L, -1)))
		lua.settop(L, base)
	}
	mods.loading = false
	for i in mods.active do mods.list[i].ticks = 0
	Mods_Dispatch(L, "mods_loaded", 0)
}

// Mods_Frame (every frame, before the game's): the budgets start over,
// "scene_ready" when the scene changed, then "update" (dt).
Mods_Frame :: proc(game: ^Game, dt: f32) {
	if len(mods.active) == 0 || mods.mode != .Scripts || mods.L == nil do return
	for i in mods.active do mods.list[i].ticks = 0
	L := mods.L
	if cur := game.sceneManager.currentScene; cur != nil && rawptr(cur) != mods.lastScene {
		mods.lastScene = cur
		lua.pushstring(L, strings.clone_to_cstring(cur.name, context.temp_allocator))
		Mods_Dispatch(L, "scene_ready", 1)
	}
	lua.pushnumber(L, lua.Number(dt))
	Mods_Dispatch(L, "update", 1)
}

// Mods_Dispatch calls the Mods.on handlers of `event` with the `nargs`
// values on the stack (popped).
Mods_Dispatch :: proc(L: ^lua.State, event: cstring, nargs: c.int) {
	if mods.preludeRef == 0 {
		lua.pop(L, nargs)
		return
	}
	base := lua.gettop(L) - nargs
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(mods.preludeRef))
	lua.getfield(L, -1, "dispatch")
	lua.pushstring(L, event)
	for k in 1 ..= nargs do lua.pushvalue(L, base + k)
	if lua.pcall(L, nargs + 1, 0, 0) != 0 do log.warnf("[Mods] %s: %s", event, lua.tostring(L, -1))
	lua.settop(L, base)
}

// Mods_Fail sets a mod aside after an error in its Lua (its handlers no
// longer run; files it provides stay, as they're already in use).
Mods_Fail :: proc(index: int, where_: string, msg: string) {
	if index < 0 || index >= len(mods.list) {
		log.warnf("[Mods] %s: %s", where_, msg)
		return
	}
	m := &mods.list[index]
	if m.status == .Loaded {
		m.status = .Failed
		m.error = fmt.aprintf("%s: %s", where_, msg, allocator = mods.alloc)
	}
	log.warnf("[Mods] %s failed (%s): %s - the game goes on without it", m.id, where_, msg)
}

// --- the sandbox ----------------------------------------------------------------------

// mods_hook: every MODS_HOOK_EVERY instructions - charges the running mod.
@(private = "file")
mods_hook :: proc "c" (L: ^lua.State, ar: ^lua.Debug) {
	if lua.getinfo(L, "S", ar) == 0 || ar.source == nil do return
	src := string(ar.source)
	if len(src) < 5 || src[:5] != "@mod:" do return
	context = Script_Context(L)
	rest := src[5:]
	id := rest[:strings.index_byte(rest, ':')] if strings.index_byte(rest, ':') >= 0 else rest
	i := Mods_Find(id)
	if i < 0 do return
	m := &mods.list[i]
	if m.status == .Stopped {
		lua.L_error(L, "mod %s was stopped", strings.clone_to_cstring(id, context.temp_allocator))
		return
	}
	m.ticks += 1
	budget := mods.loadBudget if mods.loading else mods.frameBudget
	if m.ticks > budget {
		m.status = .Stopped
		m.error = fmt.aprintf("ran past its budget (%d M instructions %s): stopped", budget * MODS_HOOK_EVERY / 1_000_000, "while loading" if mods.loading else "in a frame", allocator = mods.alloc)
		log.warnf("[Mods] %s %s - the game goes on without it", id, m.error)
		lua.L_error(L, "mod %s ran too long and was stopped", strings.clone_to_cstring(id, context.temp_allocator))
	}
}

// Mods_ChunkName: the chunk name of a mod's file ("@mod:<id>:<path>": the
// hook charges code by it).
Mods_ChunkName :: proc(index: int, rel: string) -> cstring {
	return fmt.ctprintf("@mod:%s:%s", mods.list[index].id, rel)
}

// mods_load_chunk compiles a mod's file in its environment (true: the
// function on the stack; false: the error message).
@(private = "file")
mods_load_chunk :: proc(L: ^lua.State, index: int, rel: string) -> bool {
	m := &mods.list[index]
	full, _ := filepath.join({m.dir, rel}, context.temp_allocator)
	data, err := os.read_entire_file(full, context.temp_allocator)
	if err != nil {
		lua.pushstring(L, fmt.ctprintf("can't read %s", rel))
		return false
	}
	if lua.L_loadbuffer(L, raw_data(data), c.size_t(len(data)), Mods_ChunkName(index, rel), "t") != .OK do return false
	Mods_SetChunkEnv(L, index)
	return true
}

// Mods_SetChunkEnv makes the function on top of the stack (a chunk just
// loaded) run in the mod's environment.
Mods_SetChunkEnv :: proc(L: ^lua.State, index: int) {
	mods_push_env(L, index)
	if lua.setupvalue(L, -2, 1) == nil do lua.pop(L, 1)
}

// mods_push_env pushes the mod's environment (made on first use).
@(private = "file")
mods_push_env :: proc(L: ^lua.State, index: int) {
	m := &mods.list[index]
	if m.envRef != 0 {
		lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(m.envRef))
		return
	}
	if mods.preludeRef == 0 {
		lua.newtable(L) // (no prelude: an empty environment)
		return
	}
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(mods.preludeRef))
	lua.getfield(L, -1, "make_env")
	lua.pushinteger(L, lua.Integer(index))
	mods_push_info(L, index)
	mods_push_fs(L, index)
	if lua.pcall(L, 3, 1, 0) != 0 {
		log.warnf("[Mods] %s: environment: %s", m.id, lua.tostring(L, -1))
		lua.pop(L, 1)
		lua.newtable(L)
	}
	lua.remove(L, -2) // the prelude table
	lua.pushvalue(L, -1)
	m.envRef = lua.L_ref(L, lua.REGISTRYINDEX)
}

@(private = "file")
set_str :: proc(L: ^lua.State, key: cstring, v: string) {
	lua.pushstring(L, strings.clone_to_cstring(v, context.temp_allocator))
	lua.setfield(L, -2, key)
}

// mods_push_info: a mod as Mods.list() shows it.
@(private = "file")
mods_push_info :: proc(L: ^lua.State, index: int) {
	m := &mods.list[index]
	lua.newtable(L)
	set_str(L, "id", m.id)
	set_str(L, "name", m.name)
	set_str(L, "version", m.version)
	set_str(L, "description", m.description)
	set_str(L, "author", m.author)
	set_str(L, "folder", m.dir)
	set_str(L, "status", Mod_StatusName(m.status))
	lua.pushboolean(L, b32(m.status == .Loaded))
	lua.setfield(L, -2, "loaded")
	lua.pushboolean(L, b32(!slice.contains(mods.disabled[:], m.id)))
	lua.setfield(L, -2, "enabled")
	if m.error != "" do set_str(L, "error", m.error)
}

// --- Mods.fs: the mod's folder, and "save:" paths in <user data>/mod_data/<id>/ ---

@(private = "file")
mods_push_fs :: proc(L: ^lua.State, index: int) {
	lua.newtable(L)
	fns := [?]struct {name: cstring, fn: lua.CFunction}{
		{"read", lua_modfs_read}, {"exists", lua_modfs_exists}, {"list", lua_modfs_list},
		{"write", lua_modfs_write}, {"mkdir", lua_modfs_mkdir}, {"remove", lua_modfs_remove},
	}
	for f in fns {
		lua.pushinteger(L, lua.Integer(index))
		lua.pushcclosure(L, f.fn, 1)
		lua.setfield(L, -2, f.name)
	}
}

// modfs_path: a Mods.fs path's file (its mod's folder, or "save:" its save
// folder); errors on an unsafe path.
@(private = "file")
modfs_path :: proc(L: ^lua.State, arg: c.int) -> (full: string, save: bool) {
	index := int(lua.tointeger(L, lua.REGISTRYINDEX - 1))
	p := string(lua.L_checkstring(L, arg))
	save = strings.has_prefix(p, "save:")
	if save do p = p[5:]
	if strings.trim_space(p) == "" || p == "." {
		base := mods.list[index].dir
		if save do base, _ = filepath.join({mods.dataDir, mods.list[index].id}, context.temp_allocator)
		return base, save
	}
	rel, ok := Mods_SafePath(p)
	if !ok || index < 0 || index >= len(mods.list) {
		lua.L_error(L, "Mods.fs: %s isn't a path inside the mod's folder (no absolute paths or ..)", strings.clone_to_cstring(p, context.temp_allocator))
		return "", false
	}
	if save {
		full, _ = filepath.join({mods.dataDir, mods.list[index].id, rel}, context.temp_allocator)
	} else {
		full, _ = filepath.join({mods.list[index].dir, rel}, context.temp_allocator)
	}
	return full, save
}

@(private = "file")
lua_modfs_read :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	full, _ := modfs_path(L, 1)
	data, err := os.read_entire_file(full, context.temp_allocator)
	if err != nil {
		lua.pushnil(L)
		return 1
	}
	lua.pushlstring(L, cstring(raw_data(data)), c.size_t(len(data)))
	return 1
}

@(private = "file")
lua_modfs_exists :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	full, _ := modfs_path(L, 1)
	lua.pushboolean(L, b32(os.exists(full)))
	return 1
}

// Mods.fs.list(folder?) -> names (folders end in "/"), sorted
@(private = "file")
lua_modfs_list :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if lua.isnoneornil(L, 1) do lua.pushstring(L, "")
	full, _ := modfs_path(L, 1)
	infos, _ := os.read_all_directory_by_path(full, context.temp_allocator)
	slice.sort_by(infos, proc(x, y: os.File_Info) -> bool {return x.name < y.name})
	lua.newtable(L)
	for fi, k in infos {
		name := fmt.tprintf("%s/", fi.name) if fi.type == .Directory else fi.name
		lua.pushstring(L, strings.clone_to_cstring(name, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(k + 1))
	}
	return 1
}

@(private = "file")
modfs_save_only :: proc(L: ^lua.State, save: bool, what: cstring) -> bool {
	if save do return true
	lua.L_error(L, "Mods.fs.%s: only \"save:\" paths (the mod's save folder) can be changed", what)
	return false
}

@(private = "file")
lua_modfs_write :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	full, save := modfs_path(L, 1)
	if !modfs_save_only(L, save, "write") do return 0
	n: c.size_t
	s := lua.L_checkstring(L, 2, &n)
	_ = os.make_directory_all(filepath.dir(full, context.temp_allocator))
	ok := os.write_entire_file(full, (cast([^]u8)s)[:n]) == nil
	lua.pushboolean(L, b32(ok))
	return 1
}

@(private = "file")
lua_modfs_mkdir :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	full, save := modfs_path(L, 1)
	if !modfs_save_only(L, save, "mkdir") do return 0
	lua.pushboolean(L, b32(os.make_directory_all(full) == nil || os.is_dir(full)))
	return 1
}

@(private = "file")
lua_modfs_remove :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	full, save := modfs_path(L, 1)
	if !modfs_save_only(L, save, "remove") do return 0
	lua.pushboolean(L, b32(os.exists(full) && os.remove_all(full) == nil))
	return 1
}

// --- the Mods table -----------------------------------------------------------------

// Script_RegisterModsModule creates the global Mods table (every game:
// with no mods its lists are empty) and the prelude its sandboxes use.
Script_RegisterModsModule :: proc(L: ^lua.State) {
	lua.newtable(L)
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "list", lua_mods_list)
	reg(L, "enabled", lua_mods_enabled)
	reg(L, "is_loaded", lua_mods_is_loaded)
	reg(L, "set_enabled", lua_mods_set_enabled)
	reg(L, "set_order", lua_mods_set_order)
	reg(L, "restart_needed", lua_mods_restart_needed)
	reg(L, "mode", lua_mods_mode)
	reg(L, "folders", lua_mods_folders)
	mods_table := lua.gettop(L)
	// The prelude (Mods.on / off / emit, the environments): it gets the
	// Mods table and its private helpers, and returns its own table.
	if lua.L_loadbuffer(L, raw_data(MODS_LUA_PRELUDE), len(MODS_LUA_PRELUDE), "=mods", "t") != .OK {
		log.errorf("[Mods] prelude: %s", lua.tostring(L, -1))
		lua.pop(L, 1)
	} else {
		lua.pushvalue(L, mods_table)
		lua.newtable(L)
		reg(L, "dead", lua_mods_p_dead)
		reg(L, "fail", lua_mods_p_fail)
		reg(L, "loadfile", lua_mods_p_loadfile)
		if lua.pcall(L, 2, 1, 0) != 0 {
			log.errorf("[Mods] prelude: %s", lua.tostring(L, -1))
			lua.pop(L, 1)
		} else {
			ref := lua.L_ref(L, lua.REGISTRYINDEX)
			if mods_preludes == nil do mods_preludes = make(map[^lua.State]c.int, allocator = Engine_HeapAllocator())
			mods_preludes[L] = ref
			if mods.L == L do mods.preludeRef = ref
		}
	}
	lua.setglobal(L, "Mods")
}

// The prelude of each Lua state (a game's, and test states).
@(private = "file")
mods_preludes: map[^lua.State]c.int

// Mods_UseState: the Lua state mods run in (its prelude).
Mods_UseState :: proc(L: ^lua.State) {
	mods.L = L
	mods.preludeRef = mods_preludes[L] if L in mods_preludes else 0
}

// Mods_ForgetState: a Lua state closes.
Mods_ForgetState :: proc(L: ^lua.State) {
	delete_key(&mods_preludes, L)
	if len(mods_preludes) == 0 {
		delete(mods_preludes)
		mods_preludes = nil
	}
	if mods.L == L {
		if mods.hooked do lua.sethook(L, nil, {}, 0)
		mods.L, mods.preludeRef, mods.hooked = nil, 0, false
		for &m in mods.list do m.envRef = 0
	}
}

// Mods.list() -> every mod found (loaded or not), in load order
@(private = "file")
lua_mods_list :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	lua.newtable(L)
	for _, i in mods.list {
		mods_push_info(L, i)
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

// Mods.enabled() -> the ids of the loaded mods, in load order
@(private = "file")
lua_mods_enabled :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	lua.newtable(L)
	n := 0
	for i in mods.active do if mods.list[i].status == .Loaded {
		n += 1
		lua.pushstring(L, strings.clone_to_cstring(mods.list[i].id, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(n))
	}
	return 1
}

@(private = "file")
lua_mods_is_loaded :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	i := Mods_Find(string(lua.L_checkstring(L, 1)))
	lua.pushboolean(L, b32(i >= 0 && mods.list[i].status == .Loaded))
	return 1
}

// Mods.set_enabled(id, on) -> bool (false: no such mod, or mods.json not written)
@(private = "file")
lua_mods_set_enabled :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	id := string(lua.L_checkstring(L, 1))
	on := lua.isnoneornil(L, 2) || bool(lua.toboolean(L, 2))
	lua.pushboolean(L, b32(Mods_SetEnabled(id, on)))
	return 1
}

// Mods.set_order(ids) -> bool
@(private = "file")
lua_mods_set_order :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if lua.type(L, 1) != .TABLE {
		lua.L_error(L, "Mods.set_order: a list of mod ids")
		return 0
	}
	ids := make([dynamic]string, context.temp_allocator)
	n := int(lua.rawlen(L, 1))
	for k in 1 ..= n {
		lua.rawgeti(L, 1, lua.Integer(k))
		if lua.type(L, -1) == .STRING do append(&ids, strings.clone(string(lua.tostring(L, -1)), context.temp_allocator))
		lua.pop(L, 1)
	}
	lua.pushboolean(L, b32(Mods_SetOrder(ids[:])))
	return 1
}

@(private = "file")
lua_mods_restart_needed :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	lua.pushboolean(L, b32(mods.restartNeeded))
	return 1
}

@(private = "file")
lua_mods_mode :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	lua.pushstring(L, strings.clone_to_cstring(Mods_ModeName(mods.mode), context.temp_allocator))
	return 1
}

@(private = "file")
lua_mods_folders :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	lua.newtable(L)
	for f, k in mods.folders {
		lua.pushstring(L, strings.clone_to_cstring(f, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(k + 1))
	}
	return 1
}

// P.dead(index) -> bool: the mod no longer runs (failed / stopped)
@(private = "file")
lua_mods_p_dead :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	i := int(lua.tointeger(L, 1))
	lua.pushboolean(L, b32(i >= 0 && i < len(mods.list) && mods.list[i].status != .Loaded))
	return 1
}

// P.fail(index | nil, where, message)
@(private = "file")
lua_mods_p_fail :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	i := int(lua.tointeger(L, 1)) if lua.isinteger(L, 1) else -1
	where_ := string(lua.tostring(L, 2)) if lua.type(L, 2) == .STRING else "handler"
	msg := string(lua.tostring(L, 3)) if lua.type(L, 3) == .STRING else "error"
	if i < 0 {
		Script_Problem(.Error, "[Mods] Lua error in a Mods.on(\"%s\") handler: %s", where_, msg)
		return 0
	}
	Mods_Fail(i, where_, msg)
	return 0
}

// P.loadfile(index, module name) -> function | nil, error: require() in a
// mod (its folder: name.lua, name/init.lua)
@(private = "file")
lua_mods_p_loadfile :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	i := int(lua.tointeger(L, 1))
	name := string(lua.L_checkstring(L, 2))
	if i < 0 || i >= len(mods.list) {
		lua.pushnil(L)
		lua.pushstring(L, "not a mod")
		return 2
	}
	base, _ := strings.replace_all(name, ".", "/", context.temp_allocator)
	for cand in ([]string{fmt.tprintf("%s.lua", base), fmt.tprintf("%s/init.lua", base)}) {
		rel, safe := Mods_SafePath(cand)
		if !safe do continue
		full, _ := filepath.join({mods.list[i].dir, rel}, context.temp_allocator)
		if !os.is_file(full) do continue
		if !mods_load_chunk(L, i, rel) {
			lua.pushnil(L)
			lua.insert(L, -2)
			return 2
		}
		return 1
	}
	lua.pushnil(L)
	lua.pushstring(L, fmt.ctprintf("module '%s' not found in mod %s", name, mods.list[i].id))
	return 2
}

// The prelude: Mods.on / off / emit and the mods' environments (it runs
// with the game's globals; the mods only see what make_env gives them).
MODS_LUA_PRELUDE := `
local Mods, P = ...
local G = _G
local type, error, pcall, tostring, setmetatable, getmetatable, rawload, select = type, error, pcall, tostring, setmetatable, getmetatable, load, select
local pairs, ipairs, collectgarbage = pairs, ipairs, collectgarbage
local unpack, tremove, pack = table.unpack, table.remove, table.pack
local real_os = os
local M = {}
local handlers, byId, nextId = {}, {}, 0
local LIFECYCLE = {mods_loaded = true, scene_ready = true, update = true}

local function call(h, ...)
    if h.mod and P.dead(h.mod) then return end
    local ok, err = pcall(h.fn, ...)
    if not ok then P.fail(h.mod, h.event, tostring(err)) end
end

local function on(event, fn, mod)
    if type(event) ~= "string" then error("Mods.on: the event must be a string", 3) end
    if type(fn) ~= "function" then error("Mods.on: the handler must be a function", 3) end
    nextId = nextId + 1
    local h = {id = nextId, event = event, fn = fn, mod = mod}
    local list = handlers[event]
    if not list then list = {}; handlers[event] = list end
    list[#list + 1] = h
    byId[nextId] = h
    local Events = G.Events
    if not LIFECYCLE[event] and Events and Events.connect then
        h.conn = Events.connect(event, function(...) call(h, ...) end)
    end
    return nextId
end

local function off(id)
    local h = byId[id]
    if not h then return false end
    byId[id] = nil
    local list = handlers[h.event]
    for i = #list, 1, -1 do if list[i] == h then tremove(list, i) end end
    if h.conn and G.Events then G.Events.disconnect(h.conn) end
    return true
end

function M.dispatch(event, ...)
    local list = handlers[event]
    if not list then return end
    local copy = {unpack(list)}
    for i = 1, #copy do
        if byId[copy[i].id] then call(copy[i], ...) end
    end
end

function Mods.on(event, fn) return on(event, fn, nil) end
function Mods.off(id) return off(id) end
function Mods.emit(event, ...)
    if type(event) ~= "string" then error("Mods.emit: the event must be a string", 2) end
    M.dispatch(event, ...)
end

local function copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

-- Globals a mod doesn't get from the game (or gets its own of).
local BLOCKED = {io = true, os = true, debug = true, package = true, dofile = true, loadfile = true,
    require = true, load = true, loadstring = true, collectgarbage = true, getmetatable = true,
    Mods = true, _G = true, Console = true, Project = true, Test = true,
    string = true, table = true, math = true, utf8 = true, coroutine = true, pcall = true, xpcall = true}

local function safe_path(p)
    if type(p) ~= "string" or p:find("^[/\\]") or p:find("^%a:") or p:find("%.%.") then
        error("not a project path: " .. tostring(p), 3)
    end
    return p
end

function M.make_env(index, info, fs)
    local env = {}
    local function dead_check(...)
        if P.dead(index) then error("mod " .. info.id .. " was stopped", 0) end
        return ...
    end
    env.Mods = setmetatable({fs = fs, self = info,
        on = function(event, fn) return on(event, fn, index) end},
        {__index = Mods, __newindex = function() error("Mods is read-only", 2) end, __metatable = false})
    env._G = env
    env.os = {clock = real_os.clock, time = real_os.time, date = real_os.date, difftime = real_os.difftime}
    for _, k in ipairs({"string", "table", "math", "utf8", "coroutine"}) do env[k] = copy(G[k]) end
    local resume = env.coroutine.resume
    env.coroutine.resume = function(...) return dead_check(resume(...)) end
    env.pcall = function(...) return dead_check(pcall(...)) end
    env.xpcall = function(...) return dead_check(G.xpcall(...)) end
    env.getmetatable = function(o)
        if type(o) == "string" then return nil end
        return getmetatable(o)
    end
    env.collectgarbage = function(opt, ...)
        if opt == nil or opt == "count" or opt == "step" or opt == "collect" then return collectgarbage(opt, ...) end
        error("collectgarbage('" .. tostring(opt) .. "') isn't available to mods", 2)
    end
    env.load = function(chunk, name, mode, e)
        if mode ~= nil and mode ~= "t" then error("mods load text chunks only", 2) end
        return rawload(chunk, "@mod:" .. info.id .. ":" .. tostring(name or "load"), "t", e == nil and env or e)
    end
    local loaded = {}
    env.require = function(name)
        if type(name) ~= "string" then error("require: a module name", 2) end
        local v = loaded[name]
        if v ~= nil then return v end
        local f, err = P.loadfile(index, name)
        if not f then error(err, 2) end
        v = f(name)
        if v == nil then v = true end
        loaded[name] = v
        return v
    end
    local Project = G.Project
    if Project then
        env.Project = {
            read_file = function(p) return Project.read_file(safe_path(p)) end,
            read_json = function(p) return Project.read_json(safe_path(p)) end,
            has_file = function(p) return Project.has_file(safe_path(p)) end,
            serialize_scene = Project.serialize_scene,
        }
    end
    if G.Console then
        local con = copy(G.Console)
        con.execute = nil
        env.Console = con
    end
    setmetatable(env, {__index = function(_, k)
        if BLOCKED[k] then return nil end
        return G[k]
    end, __metatable = false})
    return env
end

return M
`
