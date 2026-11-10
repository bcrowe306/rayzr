package engine

import os "osx"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import lua "lua54"

// Runtime mods (#286, mods.odin): discovery and load order, mods.json, file
// overrides, the sandbox, and a broken mod not stopping the game.

@(private = "file")
put :: proc(path, text: string) {
	_ = os.make_directory_all(filepath.dir(path, context.temp_allocator))
	_ = os.write_entire_file(path, transmute([]u8)text)
}

@(private = "file")
status_of :: proc(id: string) -> Mod_Status {
	i := Mods_Find(id)
	return mods.list[i].status if i >= 0 else .Failed
}

@(private = "file")
active_ids :: proc() -> string {
	ids := make([dynamic]string, context.temp_allocator)
	for i in mods.active do append(&ids, mods.list[i].id)
	return strings.join(ids[:], " ", context.temp_allocator)
}

@(test)
test_mods_discover_order :: proc(t: ^testing.T) {
	dir :: "test_mods_discover"
	defer os.remove_all(dir)
	defer Mods_Reset()
	put(dir + "/game/a/mod.json", `{"name": "A", "version": "1.0.0", "load_order": 5}`)
	put(dir + "/game/b/mod.json", `{"dependencies": ["c"]}`)
	put(dir + "/game/c/mod.json", `{"load_order": 10}`)
	put(dir + "/game/d/mod.json", `{}`)
	put(dir + "/game/e/mod.json", `{"game": ">=9.0.0"}`)
	put(dir + "/game/f/mod.json", `{"dependencies": ["nope"]}`)
	put(dir + "/game/g/mod.json", `{bad`)
	put(dir + "/game/h/mod.json", `{"dependencies": ["d"]}`)
	put(dir + "/game/i/mod.json", `{"dependencies": ["c>=2.0.0"]}`)
	put(dir + "/game/j/mod.json", `{"id": "k", "dependencies": ["l"]}`)
	put(dir + "/game/l/mod.json", `{"dependencies": ["k"]}`)
	put(dir + "/game/notamod/readme.txt", `no mod.json`)
	put(dir + "/user/a/mod.json", `{"name": "A", "version": "2.0.0", "load_order": 5}`)
	put(dir + "/user/mods.json", `{"disabled": ["d"]}`)

	folders := []string{dir + "/game", dir + "/user"}
	Mods_Discover(folders, dir + "/user/mods.json", "1.2.0")
	// Load order: load_order then id, a mod after its dependencies.
	testing.expect_value(t, active_ids(), "c b a")
	testing.expect_value(t, mods.list[Mods_Find("a")].version, "2.0.0") // (the user-data folder wins)
	testing.expect_value(t, status_of("d"), Mod_Status.Disabled)
	testing.expect_value(t, status_of("e"), Mod_Status.Incompatible)
	testing.expect_value(t, status_of("f"), Mod_Status.Missing_Dependency)
	testing.expect_value(t, status_of("g"), Mod_Status.Failed)
	testing.expect_value(t, status_of("h"), Mod_Status.Missing_Dependency) // (its dependency is turned off)
	testing.expect_value(t, status_of("i"), Mod_Status.Missing_Dependency) // (too old)
	testing.expect(t, status_of("k") == .Failed || status_of("l") == .Failed, "a dependency cycle fails")
	testing.expect(t, Mods_Find("notamod") < 0, "a folder without mod.json isn't a mod")
	testing.expect(t, Mods_Find("j") < 0 && Mods_Find("k") >= 0, "mod.json's id over the folder's name")

	// mods.json "order" goes first; dependencies still come before.
	put(dir + "/user/mods.json", `{"disabled": ["d"], "order": ["b", "a"]}`)
	Mods_Discover(folders, dir + "/user/mods.json", "1.2.0")
	testing.expect_value(t, active_ids(), "c b a")
	put(dir + "/user/mods.json", `{"disabled": ["d"], "order": ["a"]}`)
	Mods_Discover(folders, dir + "/user/mods.json", "1.2.0")
	testing.expect_value(t, active_ids(), "a c b")

	// Enabling / disabling: written to mods.json, applied on the next launch.
	testing.expect(t, !mods.restartNeeded, "nothing changed yet")
	testing.expect(t, Mods_SetEnabled("b", false), "written")
	testing.expect(t, mods.restartNeeded, "b off: restart")
	testing.expect_value(t, status_of("b"), Mod_Status.Loaded) // (still running this launch)
	testing.expect(t, Mods_SetEnabled("b", true), "written")
	testing.expect(t, !mods.restartNeeded, "back as it started")
	testing.expect(t, Mods_SetEnabled("d", true), "written")
	testing.expect(t, !Mods_SetEnabled("nope", true), "no such mod")
	Mods_Discover(folders, dir + "/user/mods.json", "1.2.0")
	testing.expect_value(t, status_of("d"), Mod_Status.Loaded)
	testing.expect(t, Mods_SetOrder({"c", "a"}), "order written")
	Mods_Discover(folders, dir + "/user/mods.json", "1.2.0")
	testing.expect(t, strings.has_prefix(active_ids(), "c a"), active_ids())

	// Where a game looks: next to it (a macOS app: beside the .app), then
	// --mods, then the user-data folder.
	f := Mods_Folders("/games/Space.app/Contents/MacOS/Space", "/games/Space.app/Contents/Resources/game.rayzr", "/extra", "/home/me/Space")
	testing.expect_value(t, len(f), 3)
	if len(f) == 3 {
		testing.expect_value(t, f[0], "/games/mods")
		testing.expect_value(t, f[1], "/extra")
		testing.expect_value(t, f[2], "/home/me/Space/mods")
	}
	f = Mods_Folders("/games/space/space", "/games/space/space#game.rayzr", "", "/u")
	testing.expect(t, len(f) == 2 && f[0] == "/games/space/mods", "single-file game")

	opts := Engine_ParseRunArgs({"game.rayzr", "--mods", "my_mods", "--no-mods"})
	testing.expect(t, opts.modsDir == "my_mods" && opts.noMods && opts.projectPath == "game.rayzr", "run options")

	// The project setting.
	cfg, ok := Project_ParseConfig(transmute([]u8)string(`{"name": "g", "export": {"mods": "assets"}}`))
	defer ProjectConfig_Destroy(&cfg)
	testing.expect(t, ok && cfg.export.mods == .Assets, "parsed")
	testing.expect(t, strings.contains(Project_SerializeToJSON(&cfg, context.temp_allocator), `"mods": "assets"`), "written")
	cfg.export.mods = .Off
	testing.expect(t, !strings.contains(Project_SerializeToJSON(&cfg, context.temp_allocator), `"mods"`), "off: not written")
	testing.expect_value(t, Mods_ParseMode("Scripts"), Mods_Mode.Scripts)
	testing.expect_value(t, Mods_ParseMode("nonsense"), Mods_Mode.Off)
}

@(test)
test_mods_overrides :: proc(t: ^testing.T) {
	dir :: "test_mods_overrides"
	defer os.remove_all(dir)
	defer Mods_Reset()
	put(dir + "/project/project.json", `{"name": "g"}`)
	put(dir + "/project/data/a.txt", "game a")
	put(dir + "/project/data/b.txt", "game b")
	put(dir + "/project/scripts/x.lua", "return {}")
	put(dir + "/mods/m1/mod.json", `{}`)
	put(dir + "/mods/m1/data/a.txt", "m1 a")
	put(dir + "/mods/m1/data/new.txt", "m1 new")
	put(dir + "/mods/m1/scripts/x.lua", "return {mod = true}")
	put(dir + "/mods/m1/project.json", `{"name": "hijacked"}`)
	put(dir + "/mods/m2/mod.json", `{"load_order": 1}`)
	put(dir + "/mods/m2/data/a.txt", "m2 a")

	am: AssetManager
	AssetManager_Init(&am)
	defer AssetManager_Destroy(&am)
	AssetManager_SetProjectDir(&am, dir + "/project")

	Mods_Discover({dir + "/mods"}, "", "", .Assets)
	text, from, ok := AssetManager_ReadFileStringFrom(&am, "data/a.txt", context.temp_allocator)
	testing.expect(t, ok && text == "m2 a" && from == Mods_Find("m2"), "the later mod wins")
	text, from, ok = AssetManager_ReadFileStringFrom(&am, "data/b.txt", context.temp_allocator)
	testing.expect(t, ok && text == "game b" && from == -1, "the game's own file")
	text, _, ok = AssetManager_ReadFileStringFrom(&am, "./data/new.txt", context.temp_allocator)
	testing.expect(t, ok && text == "m1 new", "a new file")
	text, from, _ = AssetManager_ReadFileStringFrom(&am, "scripts/x.lua", context.temp_allocator)
	testing.expect(t, from == -1 && text == "return {}", "assets only: no Lua overrides")
	text, _, _ = AssetManager_ReadFileStringFrom(&am, "project.json", context.temp_allocator)
	testing.expect(t, strings.contains(text, `"g"`), "project.json isn't a mod's")
	_, _, escaped := Mods_OverridePath("../m1/data/a.txt")
	testing.expect(t, !escaped, "no .. paths")
	_, _, escaped = Mods_OverridePath("/etc/hosts")
	testing.expect(t, !escaped, "no absolute paths")
	p, modded := Mods_ResourceDiskPath(dir + "/project", dir + "/project/data/a.txt")
	testing.expect(t, modded && strings.has_suffix(p, "m2/data/a.txt"), p)
	p, modded = Mods_ResourceDiskPath("", "data/b.txt")
	testing.expect(t, !modded && p == "data/b.txt", "not overridden")

	Mods_Discover({dir + "/mods"}, "", "", .Scripts)
	text, from, _ = AssetManager_ReadFileStringFrom(&am, "scripts/x.lua", context.temp_allocator)
	testing.expect(t, from == Mods_Find("m1") && strings.contains(text, "mod = true"), "scripts mode: Lua too")

	Mods_Reset()
	text, from, _ = AssetManager_ReadFileStringFrom(&am, "data/a.txt", context.temp_allocator)
	testing.expect(t, from == -1 && text == "game a", "no mods: the game's")
}

@(private = "file")
report_bool :: proc(t: ^testing.T, L: ^lua.State, key: cstring, loc := #caller_location) {
	lua.getglobal(L, "reports")
	lua.getfield(L, -1, key)
	testing.expectf(t, bool(lua.toboolean(L, -1)), "report %s: %v", key, lua.toboolean(L, -1), loc = loc)
	lua.pop(L, 2)
}

@(private = "file")
report_number :: proc(L: ^lua.State, key: cstring) -> f64 {
	lua.getglobal(L, "reports")
	lua.getfield(L, -1, key)
	n := f64(lua.tonumber(L, -1))
	lua.pop(L, 2)
	return n
}

@(private = "file")
REPORTS_LUA :: `reports = {} function report(k, v) reports[k] = v end`

@(test)
test_mods_sandbox :: proc(t: ^testing.T) {
	dir :: "test_mods_sandbox"
	defer os.remove_all(dir)
	defer Mods_Reset()
	put(dir + "/project/project.json", `{"name": "g"}`)
	put(dir + "/project/scripts/x.lua", `return {where = "game"}`)
	put(dir + "/mods/sand/mod.json", `{"name": "Sandbox", "version": "1.0.0"}`)
	put(dir + "/mods/sand/data/info.txt", "hello")
	put(dir + "/mods/sand/lib/helper.lua", `return {value = 42}`)
	put(dir + "/mods/sand/scripts/x.lua", `return {where = "mod", sandboxed = (io == nil and package == nil)}`)
	put(dir + "/mods/sand/main.lua", `
report("io", io == nil)
report("os", os.execute == nil and os.getenv == nil and os.remove == nil and type(os.time()) == "number")
report("libs", package == nil and debug == nil and dofile == nil and loadfile == nil)
report("bytecode", not pcall(load, string.dump(function() end), "x", "b"))
report("load_text", load("return 1 + 1")() == 2)
report("require", require("lib.helper").value == 42)
report("require_escape", not pcall(require, "..secret"))
report("fs_read", Mods.fs.read("data/info.txt") == "hello")
report("fs_escape", not pcall(Mods.fs.read, "../../project/project.json"))
report("fs_absolute", not pcall(Mods.fs.read, "/etc/hosts"))
report("fs_write_mod", not pcall(Mods.fs.write, "data/info.txt", "x"))
report("fs_write_save", Mods.fs.write("save:state.txt", "saved") and Mods.fs.read("save:state.txt") == "saved")
report("fs_list", Mods.fs.list("data")[1] == "info.txt")
report("self", Mods.self.id == "sand" and Mods.self.loaded)
report("game_api", type(Events) == "table" and type(Save) == "table" and type(Scene) == "table")
report("project", Project ~= nil and Project.load == nil and Project.export_rayzr == nil and not pcall(Project.read_file, "../x"))
report("console", Console == nil or Console.execute == nil)
report("metatable", getmetatable("") == nil)
report("game_global", type(report) == "function")
leaked_global = true
string.custom = 1
Mods.on("update", function(dt) report("update", dt) end)
Mods.on("mods_loaded", function() report("loaded", true) end)
Mods.on("ping", function(v) report("ping", v) end)
`)

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, dir + "/project")
	L := game.scriptManager.L
	testing.expect(t, lua.L_dostring(L, REPORTS_LUA) == 0, "reports")

	Mods_Discover({dir + "/mods"}, "", "", .Scripts)
	mods.dataDir = dir + "/userdata/mod_data"
	Mods_Attach(L)
	Mods_Start(game)
	testing.expect_value(t, status_of("sand"), Mod_Status.Loaded)
	for k in ([]cstring{"io", "os", "libs", "bytecode", "load_text", "require", "require_escape", "fs_read", "fs_escape", "fs_absolute",
		"fs_write_mod", "fs_write_save", "fs_list", "self", "game_api", "project", "console", "metatable", "game_global", "loaded"}) {
		report_bool(t, L, k)
	}
	testing.expect(t, os.is_file(dir + "/userdata/mod_data/sand/state.txt"), "the mod's save folder")
	// Its globals and library changes stay its own.
	r := lua.L_dostring(L, `assert(leaked_global == nil, "a mod global leaked"); assert(string.custom == nil, "a mod changed string")`)
	if r != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	// Hooks: Mods.emit (game scripts), the event bus, the lifecycle.
	testing.expect(t, lua.L_dostring(L, `Mods.emit("ping", 7)`) == 0, "emit")
	testing.expect_value(t, report_number(L, "ping"), 7)
	testing.expect(t, lua.L_dostring(L, `Events.emit("ping", 5)`) == 0, "bus")
	testing.expect_value(t, report_number(L, "ping"), 5)
	lua.pushnumber(L, 0.25)
	Mods_Dispatch(L, "update", 1)
	testing.expect_value(t, report_number(L, "update"), 0.25)

	// A .lua the mod overrides runs in its sandbox, not with the game's privileges.
	mod, ok := ScriptManager_LoadModule("scripts/x.lua", &game.scriptManager)
	testing.expect(t, ok && mod != nil, "loaded")
	lua.getfield(L, lua.REGISTRYINDEX, "__Engine_Module_scripts/x.lua")
	lua.getfield(L, -1, "where")
	testing.expect_value(t, string(lua.tostring(L, -1)), "mod")
	lua.getfield(L, -2, "sandboxed")
	testing.expect(t, bool(lua.toboolean(L, -1)), "the override is sandboxed")
	lua.pop(L, 3)
}

@(test)
test_mods_failure_isolation :: proc(t: ^testing.T) {
	dir :: "test_mods_failures"
	defer os.remove_all(dir)
	defer Mods_Reset()
	put(dir + "/project/project.json", `{"name": "g"}`)
	put(dir + "/mods/broken/mod.json", `{}`)
	put(dir + "/mods/broken/main.lua", `error("boom")`)
	put(dir + "/mods/syntax/mod.json", `{}`)
	put(dir + "/mods/syntax/main.lua", `this is not lua`)
	put(dir + "/mods/loop/mod.json", `{"load_order": 1}`)
	put(dir + "/mods/loop/main.lua", `while true do end`)
	put(dir + "/mods/catcher/mod.json", `{"load_order": 2}`)
	put(dir + "/mods/catcher/main.lua", `while true do pcall(function() while true do end end) end`)
	put(dir + "/mods/handler/mod.json", `{}`)
	put(dir + "/mods/handler/main.lua", `Mods.on("update", function() error("bad handler") end)`)
	put(dir + "/mods/slow/mod.json", `{}`)
	put(dir + "/mods/slow/main.lua", `Mods.on("update", function() while true do end end)`)
	put(dir + "/mods/fine/mod.json", `{"load_order": 9}`)
	put(dir + "/mods/fine/main.lua", `report("fine", true); Mods.on("update", function() report("fine_update", (reports.fine_update or 0) + 1) end)`)

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, dir + "/project")
	L := game.scriptManager.L
	testing.expect(t, lua.L_dostring(L, REPORTS_LUA) == 0, "reports")

	Mods_Discover({dir + "/mods"}, "", "", .Scripts)
	mods.loadBudget, mods.frameBudget = 2000, 2000 // (2 M instructions: quick)
	Mods_Attach(L)
	Mods_Start(game)
	testing.expect_value(t, status_of("broken"), Mod_Status.Failed)
	testing.expect_value(t, status_of("syntax"), Mod_Status.Failed)
	testing.expect_value(t, status_of("loop"), Mod_Status.Stopped)
	testing.expect_value(t, status_of("catcher"), Mod_Status.Stopped)
	testing.expect_value(t, status_of("fine"), Mod_Status.Loaded)
	report_bool(t, L, "fine")
	for _ in 0 ..< 2 {
		for i in mods.active do mods.list[i].ticks = 0 // (a frame: Mods_Frame)
		lua.pushnumber(L, 1.0 / 60)
		Mods_Dispatch(L, "update", 1)
	}
	testing.expect_value(t, status_of("handler"), Mod_Status.Failed)
	testing.expect_value(t, status_of("slow"), Mod_Status.Stopped)
	testing.expect_value(t, report_number(L, "fine_update"), 2)

	// What a game's mods menu reads.
	r := lua.L_dostring(L, `
local list = Mods.list()
assert(#list == 7, "seven mods: " .. #list)
local byId = {}
for _, m in ipairs(list) do byId[m.id] = m end
assert(byId.fine.loaded and byId.fine.status == "loaded" and byId.fine.enabled)
assert(byId.loop.status == "stopped" and byId.loop.error and not byId.loop.loaded)
assert(byId.broken.status == "failed" and byId.broken.error:find("boom"))
local on = Mods.enabled()
assert(#on == 1 and on[1] == "fine", "enabled: " .. table.concat(on, ","))
assert(Mods.is_loaded("fine") and not Mods.is_loaded("loop"))
assert(Mods.mode() == "scripts")
assert(#Mods.folders() == 1)
assert(Mods.set_enabled("fine", false) == false, "no mods.json here: not kept")
assert(Mods.restart_needed())
`)
	if r != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
}
