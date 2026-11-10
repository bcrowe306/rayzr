package editor

import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"
import e "../engine"
import lua "../engine/lua54"
import imgui "lib/imgui"

// ============================================================================
// Editor plugins (design: docs/plugins.md): Lua that extends the editor.
//
// - Project plugins: <project>/plugins/<id>/; user plugins: the editor's
//   config folder (.../rayzr_editor/plugins/<id>/). Each has a plugin.json
//   (name, version, description, editor, main, permissions) and Lua files.
// - Each running plugin has its own Lua state: the safe standard libraries
//   (no io; os only for time; require from its own folder), the engine's
//   Node / Scene / vector API bound to the scene being edited, and the
//   Editor API (plugin_api.odin). Every call into it is protected: an error
//   stops that plugin (Settings > Plugins shows it), never the editor.
// - A project's plugins run once its folder is trusted (asked once, kept in
//   the editor settings); user plugins are the user's own and always run.
//   Settings > Plugins turns a plugin off / on and reloads it.
// - A plugin's files changing (saved in the Code tab or elsewhere) reload it.
// ============================================================================

Plugin_Scope :: enum {
	Project,
	User,
}

Plugin_State :: enum {
	Off,       // turned off in Settings > Plugins
	Untrusted, // a project plugin waiting for (or refused) trust
	Running,
	Failed,    // an error (Plugin.error) stopped it
}

Plugin_Permission :: enum {
	Process, // Editor.run
	Network, // Editor.http
}

Plugin :: struct {
	id:          string, // its folder's name
	dir:         string, // absolute
	scope:       Plugin_Scope,
	name:        string,
	version:     string,
	description: string,
	editorReq:   string, // plugin.json "editor": the oldest editor it needs (">=0.2.0")
	main:        string, // its entry file ("main.lua")
	permissions: bit_set[Plugin_Permission],
	state:       Plugin_State,
	error:       string,
	mgr:         ^e.ScriptManager, // its Lua state (Running)
	log:         [dynamic]string,  // its last lines (print, Editor.log, errors)
	stamp:       time.Time,        // the newest change of its files (hot reload)
}

PLUGIN_LOG_MAX :: 200
PLUGIN_REGISTRY_KEY :: "__Rayzr_Plugin"

@(private = "file")
plugins: struct {
	list:      [dynamic]^Plugin,
	project:   string, // the project they were loaded for (absolute)
	lastCheck: time.Tick,
	trustAsk:  bool,   // the trust prompt is wanted
}

// Plugins_List: every discovered plugin (Settings > Plugins).
Plugins_List :: proc() -> []^Plugin {
	return plugins.list[:]
}

// Plugins_UserDir: where user plugins live.
// (Under --user-data when given: drives and tests.)
Plugins_UserDir :: proc() -> string {
	return Editor_UserDir("plugins", GlobalEditor.userDataDir)
}

// Plugins_Load discovers the project's and the user's plugins and starts
// those that may run (after the project and the settings are loaded).
// ask: show the trust prompt when this project hasn't been asked (not from
// Settings > Plugins' Rescan: that page has its own Allow / Block).
Plugins_Load :: proc(state: ^EditorState, ask := true) {
	Plugins_Unload(state)
	project := state.projectPath
	if abs, err := os.get_absolute_path(project, context.temp_allocator); err == nil do project = abs
	plugins.project = strings.clone(project)
	projectDir, _ := filepath.join({project, "plugins"}, context.temp_allocator)
	plugins_discover(projectDir, .Project)
	// (Not while driving, unless the drive has its own --user-data folder:
	// tests don't run the user's own plugins.)
	if user := Plugins_UserDir(); user != "" && (!GlobalDrive.enabled || state.userDataDir != "") do plugins_discover(user, .User)
	if len(plugins.list) == 0 do return
	trusted, known := GlobalSettings.pluginTrust[plugins.project]
	for p in plugins.list {
		switch {
		case GlobalSettings.pluginsOff[p.dir]:
			p.state = .Off
		case p.scope == .Project && !trusted:
			p.state = .Untrusted
			if !known && ask do plugins.trustAsk = true
		case:
			plugin_start(state, p)
		}
	}

}

// Plugins_Unload stops every plugin (quit, project change).
Plugins_Unload :: proc(state: ^EditorState) {
	for p in plugins.list {
		plugin_stop(state, p)
		plugin_free(p)
	}
	delete(plugins.list)
	plugins.list = nil
	delete(plugins.project)
	plugins.project = ""
	plugins.trustAsk = false
}

// Plugins_Update: once a frame - hot reload (a plugin's files changed).
Plugins_Update :: proc(state: ^EditorState) {
	PluginAPI_Update(state) // finished jobs call back
	PluginEvents_Update(state) // selection_changed
	for p in plugins.list do if p.state == .Failed && p.mgr != nil do plugin_close(p)
	if time.tick_since(plugins.lastCheck) < time.Second do return
	plugins.lastCheck = time.tick_now()
	for p in plugins.list {
		stamp := plugin_newest(p.dir)
		if stamp == p.stamp do continue
		p.stamp = stamp
		if p.state != .Running && p.state != .Failed do continue
		plugin_log(p, "(files changed: reloading)")
		Plugin_Reload(state, p)
	}
}

// Plugin_Reload stops and starts a plugin again (its plugin.json re-read).
Plugin_Reload :: proc(state: ^EditorState, p: ^Plugin) {
	plugin_stop(state, p)
	plugin_read_manifest(p)
	plugin_start(state, p)
}

// Plugin_SetOff turns a plugin off (stopped, remembered) or on.
Plugin_SetOff :: proc(state: ^EditorState, p: ^Plugin, off: bool) {
	if off {
		plugin_stop(state, p)
		p.state = .Off
		if p.dir not_in GlobalSettings.pluginsOff do GlobalSettings.pluginsOff[strings.clone(p.dir)] = true
	} else {
		if k, ok := slice_key(GlobalSettings.pluginsOff, p.dir); ok {
			delete_key(&GlobalSettings.pluginsOff, p.dir)
			delete(k)
		}
		p.state = .Off
		if p.scope == .Project && !(GlobalSettings.pluginTrust[plugins.project] or_else false) {
			p.state = .Untrusted
		} else {
			plugin_start(state, p)
		}
	}
	_ = Editor_SaveSettings()
}

// Plugins_SetTrust answers the trust prompt for this project.
Plugins_SetTrust :: proc(state: ^EditorState, trusted: bool) {
	if k, ok := slice_key(GlobalSettings.pluginTrust, plugins.project); ok {
		GlobalSettings.pluginTrust[k] = trusted
	} else {
		GlobalSettings.pluginTrust[strings.clone(plugins.project)] = trusted
	}
	_ = Editor_SaveSettings()
	for p in plugins.list {
		if p.scope != .Project || p.state == .Off do continue
		if trusted do plugin_start(state, p)
		else {
			plugin_stop(state, p)
			p.state = .Untrusted
		}
	}
}

// Plugins_Trusted: this project's plugins may run (nil: not asked yet).
Plugins_Trusted :: proc() -> Maybe(bool) {
	if v, ok := GlobalSettings.pluginTrust[plugins.project]; ok do return v
	return nil
}

// Plugins_TrustPrompt: the "this project has plugins" question (every frame).
Plugins_TrustPrompt :: proc(state: ^EditorState) {
	if plugins.trustAsk {
		plugins.trustAsk = false
		imgui.OpenPopup("Project Plugins###PluginTrust")
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if !imgui.BeginPopupModal("Project Plugins###PluginTrust", nil, {.AlwaysAutoResize}) do return
	UI_DimText("This project has editor plugins - code that runs in this editor:")
	for p in plugins.list do if p.scope == .Project {
		perms := ""
		if .Process in p.permissions do perms = "  - runs programs"
		if .Network in p.permissions do perms = fmt.tprintf("%s  - uses the network", perms)
		imgui.BulletText("%s", fmt.ctprintf("%s %s%s", p.name, p.version, perms))
		if p.description != "" {
			imgui.Indent()
			UI_DimText(p.description)
			imgui.Unindent()
		}
	}
	UI_DimText("Only allow them if you trust where the project comes from.")
	UI_DimText("(Remembered for this project; Settings > Plugins can change it.)")
	if UI_PrimaryButton("Allow", "plugins.trust.allow") {
		Plugins_SetTrust(state, true)
		imgui.CloseCurrentPopup()
	}
	UI_Tooltip("Run this project's plugins (now and next time)")
	imgui.SameLine()
	if UI_Button("Don't Allow", "plugins.trust.block") {
		Plugins_SetTrust(state, false)
		imgui.CloseCurrentPopup()
	}
	UI_Tooltip("Don't run them (Settings > Plugins can allow them later)")
	imgui.EndPopup()
}

// --- the Lua side --------------------------------------------------------------

// Plugin_Of: the plugin a Lua state belongs to (nil for other states).
Plugin_Of :: proc(L: ^lua.State) -> ^Plugin {
	lua.getfield(L, lua.REGISTRYINDEX, PLUGIN_REGISTRY_KEY)
	defer lua.pop(L, 1)
	return cast(^Plugin)lua.touserdata(L, -1)
}

// Plugin_Call calls a function the plugin defined (on the stack, with
// `nargs` arguments above it), protected: an error stops the plugin.
// Returns whether it ran; its `nresults` results stay on the stack then.
Plugin_Call :: proc(state: ^EditorState, p: ^Plugin, nargs, nresults: c.int, what: string) -> bool {
	L := p.mgr.L
	base := lua.gettop(L) - nargs
	lua.pushcfunction(L, e.lua_traceback_error_handler)
	lua.insert(L, base)
	status := lua.pcall(L, nargs, nresults, base)
	lua.remove(L, base)
	if status != 0 {
		msg := string(lua.tostring(L, -1))
		plugin_fail(state, p, fmt.tprintf("%s: %s", what, msg))
		lua.pop(L, 1)
		return false
	}
	return true
}

// plugin_call_global calls the plugin's global function `name` if defined.
@(private = "file")
plugin_call_global :: proc(state: ^EditorState, p: ^Plugin, name: cstring) {
	if p.mgr == nil do return
	L := p.mgr.L
	lua.getglobal(L, name)
	if lua.type(L, -1) != .FUNCTION {
		lua.pop(L, 1)
		return
	}
	_ = Plugin_Call(state, p, 0, 0, string(name))
}

// plugin_start creates the plugin's Lua state and runs its main file.
@(private = "file")
plugin_start :: proc(state: ^EditorState, p: ^Plugin) {
	if p.mgr != nil do return
	delete(p.error)
	p.error = ""
	if p.editorReq != "" {
		need := strings.trim_left(p.editorReq, ">= ")
		if !e.Version_IsDev(e.RAYZR_RELEASE) && e.Version_Compare(e.RAYZR_RELEASE, need) < 0 {
			plugin_fail(state, p, fmt.tprintf("needs Rayzr Editor %s or newer (this is %s)", need, e.RAYZR_RELEASE))
			return
		}
	}
	mgr := new(e.ScriptManager)
	p.mgr = mgr
	mgr.ctx, mgr.hasCtx = context, true
	L := lua.L_newstate()
	mgr.L = L
	e.Script_SetManager(L, mgr)
	plugin_open_libs(L, p)
	e.RegisterEngineLuaBindings(L, mgr)
	e.Lua_RegisterVectors(L)
	_ = lua.L_dostring(L, e.LUA_CURVE_HELPERS)
	// (The game's own services make no sense in the editor.)
	for g in ([]cstring{"Save", "Engine", "Input", "Pool", "Crash"}) {
		lua.pushnil(L)
		lua.setglobal(L, g)
	}
	mgr.game = state.game
	mgr.modules = make(map[string]^e.ScriptModule)
	mgr.instances = make([dynamic]^e.ScriptInstance)
	mgr.isReady = true
	lua.pushlightuserdata(L, p)
	lua.setfield(L, lua.REGISTRYINDEX, PLUGIN_REGISTRY_KEY)
	PluginAPI_Register(L, p) // the Editor table (plugin_api.odin)

	path, _ := filepath.join({p.dir, p.main}, context.temp_allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		plugin_fail(state, p, fmt.tprintf("cannot read %s", p.main))
		return
	}
	chunk := strings.clone_to_cstring(fmt.tprintf("@%s/%s", p.id, p.main), context.temp_allocator)
	if lua.L_loadbuffer(L, raw_data(data), c.size_t(len(data)), chunk) != .OK {
		plugin_fail(state, p, string(lua.tostring(L, -1)))
		lua.pop(L, 1)
		return
	}
	p.state = .Running
	if !Plugin_Call(state, p, 0, 0, p.main) do return
	plugin_call_global(state, p, "on_load")
	// (The project is open already: its handlers hear it now.)
	PluginEvents_EmitTo(state, p, "project_opened", state.projectConfig.name)
	if p.state == .Running do plugin_log(p, fmt.tprintf("started (%s)", p.version))
}

// plugin_stop runs on_unload and closes the plugin's Lua state; what it
// registered goes with it.
@(private = "file")
plugin_stop :: proc(state: ^EditorState, p: ^Plugin) {
	if p.mgr == nil do return
	if p.state == .Running do plugin_call_global(state, p, "on_unload")
	plugin_close(p) // its commands, panels, hooks go too (plugin_api.odin)
	if p.state == .Running do p.state = .Off
}

// plugin_fail stops a plugin with an error (Settings > Plugins, console).
// What it registered goes at once; its Lua state is closed by the next
// Plugins_Update (a call into it may still be on the stack).
@(private = "file")
plugin_fail :: proc(state: ^EditorState, p: ^Plugin, msg: string) {
	if p.state == .Failed do return
	delete(p.error)
	p.error = strings.clone(msg)
	plugin_log(p, fmt.tprintf("error: %s", msg))
	Editor_Log(state, .Error, "Plugin %s stopped: %s", p.name, msg)
	p.state = .Failed // (no on_unload after an error)
	PluginAPI_Forget(p)
}

// plugin_close closes a failed plugin's Lua state (between frames).
@(private = "file")
plugin_close :: proc(p: ^Plugin) {
	if p.mgr == nil do return
	PluginAPI_Forget(p)
	e.ScriptManager_Destroy(p.mgr)
	free(p.mgr)
	p.mgr = nil
}

// plugin_log keeps a line of the plugin's output.
plugin_log :: proc(p: ^Plugin, line: string) {
	if len(p.log) >= PLUGIN_LOG_MAX {
		delete(p.log[0])
		ordered_remove(&p.log, 0)
	}
	append(&p.log, strings.clone(line))
}

// plugin_open_libs: the safe standard libraries. No io, no dofile /
// loadfile / loadlib; os has only time functions; require searches the
// plugin's folder (Lua files only).
@(private = "file")
plugin_open_libs :: proc(L: ^lua.State, p: ^Plugin) {
	libs := [?]struct {
		name: cstring,
		open: lua.CFunction,
	}{
		{"_G", lua.open_base}, {"table", lua.open_table}, {"string", lua.open_string},
		{"math", lua.open_math}, {"utf8", lua.open_utf8}, {"coroutine", lua.open_coroutine},
		{"package", lua.open_package},
	}
	for l in libs {
		lua.L_requiref(L, l.name, l.open, 1)
		lua.pop(L, 1)
	}
	for g in ([]cstring{"dofile", "loadfile"}) {
		lua.pushnil(L)
		lua.setglobal(L, g)
	}
	// os: time only.
	lua.L_requiref(L, "os", lua.open_os, 0)
	lua.newtable(L)
	for f in ([]cstring{"clock", "time", "date", "difftime"}) {
		lua.getfield(L, -2, f)
		lua.setfield(L, -2, f)
	}
	lua.setglobal(L, "os")
	lua.pop(L, 1)
	// require: Lua files in the plugin's folder only.
	lua.getglobal(L, "package")
	pathC := strings.clone_to_cstring(fmt.tprintf("%s/?.lua;%s/?/init.lua", p.dir, p.dir), context.temp_allocator)
	lua.pushstring(L, pathC)
	lua.setfield(L, -2, "path")
	lua.pushstring(L, "")
	lua.setfield(L, -2, "cpath")
	lua.pushnil(L)
	lua.setfield(L, -2, "loadlib")
	lua.getfield(L, -1, "searchers")
	for i in 3 ..= 4 { // (the C library searchers)
		lua.pushnil(L)
		lua.rawseti(L, -2, lua.Integer(i))
	}
	lua.pop(L, 2)
}

// --- discovery -------------------------------------------------------------------

@(private = "file")
plugins_discover :: proc(dir: string, scope: Plugin_Scope) {
	infos, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil do return
	slice.sort_by(infos, proc(a, b: os.File_Info) -> bool {return a.name < b.name})
	for f in infos {
		if f.type != .Directory || strings.has_prefix(f.name, ".") do continue
		manifest, _ := filepath.join({f.fullpath, "plugin.json"}, context.temp_allocator)
		if !os.is_file(manifest) do continue
		p := new(Plugin)
		p.id = strings.clone(f.name)
		p.dir = strings.clone(f.fullpath)
		p.scope = scope
		plugin_read_manifest(p)
		p.stamp = plugin_newest(p.dir)
		append(&plugins.list, p)
	}
}

// plugin_read_manifest reads plugin.json (defaults for what's missing).
@(private = "file")
plugin_read_manifest :: proc(p: ^Plugin) {
	delete(p.name); delete(p.version); delete(p.description); delete(p.editorReq); delete(p.main)
	p.name, p.version, p.description, p.editorReq, p.main = strings.clone(p.id), strings.clone("0.0.0"), "", "", strings.clone("main.lua")
	p.permissions = {}
	path, _ := filepath.join({p.dir, "plugin.json"}, context.temp_allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil do return
	v, perr := json.parse(data, allocator = context.temp_allocator)
	if perr != nil do return
	o, ok := v.(json.Object)
	if !ok do return
	str :: proc(o: json.Object, k, def: string) -> string {
		if s, ok := o[k].(json.String); ok && s != "" do return strings.clone(s)
		return strings.clone(def)
	}
	delete(p.name); delete(p.version); delete(p.main)
	p.name = str(o, "name", p.id)
	p.version = str(o, "version", "0.0.0")
	p.description = str(o, "description", "")
	p.editorReq = str(o, "editor", "")
	p.main = str(o, "main", "main.lua")
	if perms, ok := o["permissions"].(json.Array); ok {
		for x in perms {
			s, _ := x.(json.String)
			switch s {
			case "process": p.permissions += {.Process}
			case "network": p.permissions += {.Network}
			}
		}
	}
}

// plugin_newest: the latest modification time among the plugin's files.
@(private = "file")
plugin_newest :: proc(dir: string) -> (newest: time.Time) {
	infos, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil do return
	for f in infos {
		t := f.modification_time
		if f.type == .Directory {
			if strings.has_prefix(f.name, ".") do continue
			t = plugin_newest(f.fullpath)
		}
		if time.diff(newest, t) > 0 do newest = t
	}
	return
}

@(private = "file")
plugins_any :: proc(scope: Plugin_Scope) -> bool {
	for p in plugins.list do if p.scope == scope do return true
	return false
}

@(private = "file")
plugin_free :: proc(p: ^Plugin) {
	delete(p.id); delete(p.dir); delete(p.name); delete(p.version); delete(p.description)
	delete(p.editorReq); delete(p.main); delete(p.error)
	for l in p.log do delete(l)
	delete(p.log)
	free(p)
}

// slice_key: the map's own copy of `key` (to free it when removing).
@(private = "file")
slice_key :: proc(m: map[string]bool, key: string) -> (string, bool) {
	for k in m do if k == key do return k, true
	return "", false
}

// Plugins_DriveQuery: "plugin:<id>.state" (off / untrusted / running /
// failed), ".error", ".log" (its lines, joined), ".count" (plugins found).
Plugins_DriveQuery :: proc(q: string) -> (string, bool) {
	rest := q[len("plugin:"):]
	if rest == "count" do return fmt.tprint(len(plugins.list)), true
	dot := strings.last_index_byte(rest, '.')
	if dot < 0 do return "", false
	id, field := rest[:dot], rest[dot + 1:]
	for p in plugins.list do if p.id == id {
		switch field {
		case "state":
			switch p.state {
			case .Off: return "off", true
			case .Untrusted: return "untrusted", true
			case .Running: return "running", true
			case .Failed: return "failed", true
			}
		case "error": return p.error, true
		case "log": return strings.join(p.log[:], "\n", context.temp_allocator), true
		}
	}
	return "missing", true
}

// Plugins_Create makes plugins/<id>/ from `name` (Tools > New Plugin): a
// plugin.json and a main.lua with a command, a panel and an event, then
// starts it (a plugin made here is trusted) and opens main.lua.
Plugins_Create :: proc(state: ^EditorState, name: string) {
	name := strings.trim_space(name)
	if name == "" do return
	sb := strings.builder_make(context.temp_allocator)
	for r in strings.to_lower(name, context.temp_allocator) {
		switch r {
		case 'a' ..= 'z', '0' ..= '9': strings.write_rune(&sb, r)
		case ' ', '-', '_': if strings.builder_len(sb) > 0 do strings.write_byte(&sb, '_')
		}
	}
	id := strings.trim_right(strings.to_string(sb), "_")
	if id == "" do id = "plugin"
	project := state.projectPath
	if abs, err := os.get_absolute_path(project, context.temp_allocator); err == nil do project = abs
	dir, _ := filepath.join({project, "plugins", id}, context.temp_allocator)
	if os.exists(dir) {
		Editor_Log(state, .Error, "plugins/%s already exists", id)
		return
	}
	if os.make_directory_all(dir) != nil {
		Editor_Log(state, .Error, "Could not create %s", dir)
		return
	}
	manifest, _ := strings.replace_all(PLUGIN_TEMPLATE_JSON, "$NAME", name, context.temp_allocator)
	main, _ := strings.replace_all(PLUGIN_TEMPLATE_LUA, "$NAME", name, context.temp_allocator)
	jsonPath, _ := filepath.join({dir, "plugin.json"}, context.temp_allocator)
	mainPath, _ := filepath.join({dir, "main.lua"}, context.temp_allocator)
	_ = os.write_entire_file(jsonPath, transmute([]u8)manifest)
	_ = os.write_entire_file(mainPath, transmute([]u8)main)
	// Made here: this project's plugins are trusted.
	if k, ok := slice_key(GlobalSettings.pluginTrust, project); ok do GlobalSettings.pluginTrust[k] = true
	else do GlobalSettings.pluginTrust[strings.clone(project)] = true
	_ = Editor_SaveSettings()
	Lua_ProjectSetup(state) // (editor_api.lua now that there's a plugins/ folder)
	Plugins_Load(state, ask = false)
	Editor_OpenScript(state, mainPath)
	PluginPanels_Show(fmt.tprintf("plugin.%s.panel", id))
	Editor_Log(state, .Info, "New plugin plugins/%s (Settings > Plugins; saving main.lua reloads it)", id)
}

PLUGIN_TEMPLATE_JSON :: `{
  "name": "$NAME",
  "version": "0.1.0",
  "description": "$NAME - a Rayzr editor plugin",
  "main": "main.lua",
  "permissions": []
}
`

PLUGIN_TEMPLATE_LUA :: `-- $NAME: a Rayzr editor plugin (editor/docs/plugins.md).
-- Saving this file reloads the plugin; Settings > Plugins shows its log.

local clicks = 0

-- A command: Tools menu, the command palette (Cmd/Ctrl+Shift+P), the keymap.
Editor.add_command{
    id = "hello",
    label = "Say Hello ($NAME)",
    menu = "Tools",
    run = function()
        local names = {}
        for _, n in ipairs(Editor.selection()) do names[#names + 1] = n.name end
        Editor.notify("Hello! Selected: " .. (#names > 0 and table.concat(names, ", ") or "nothing"))
    end,
}

-- A panel, docked next to the Inspector (View > Plugins).
Editor.add_panel{
    id = "panel",
    title = "$NAME",
    dock = "right",
    draw = function(ui)
        local scene = Editor.scene()
        ui.text("Scene: " .. (scene and scene.name or "none"))
        ui.text("Selected: " .. #Editor.selection())
        if ui.button("Click me") then clicks = clicks + 1 end
        ui.same_line()
        ui.dim(clicks .. " clicks")
    end,
}

-- An event.
Editor.on("scene_saved", function(path)
    print("saved " .. path)
end)
`
