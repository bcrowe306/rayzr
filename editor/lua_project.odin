package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"

// ============================================================================
// Lua tooling files in the project.
//
// The engine's API definitions are compiled into the editor and written to
// <project>/.rayzr/definitions/ (rewritten when the editor's copy changes),
// and <project>/.luarc.json points lua-language-server at them - so the
// built-in code editor, and VS Code or any LuaLS editor opening the project
// folder, get the same completion and hover. Hidden files and folders
// (.rayzr/, .luarc.json, ...) are not packaged into games.
// ============================================================================

ENGINE_API_LUA :: #load("../engine/definitions/engine_api.lua", string)
EDITOR_API_LUA :: #load("definitions/editor_api.lua", string) // (plugins: editor/docs/plugins.md)

LUA_DEFINITIONS_DIR :: ".rayzr/definitions"
LUA_HISTORY_DIR     :: ".rayzr/history" // (code_history.odin: saved copies of scripts)

// write_if_changed writes a file unless it already has exactly this content.
@(private = "file")
write_if_changed :: proc(path, text: string) -> bool {
	if old, err := os.read_entire_file(path, context.temp_allocator); err == nil && string(old) == text do return true
	_ = os.make_directory_all(filepath.dir(path, context.temp_allocator))
	return os.write_entire_file(path, transmute([]u8)text) == nil
}

// The diagnostics presets (Project Settings > General > Scripting: Lua
// Checks; "scripting": {"lua_checks"} in project.json, #403), the same in
// .luarc.json and the Code tab's own server settings:
//   Relaxed (default)  nil checks (need-check-nil) are hints, not warnings;
//                      trailing spaces and lowercase globals (a test file's
//                      test_* functions) aren't reported
//   Standard           lua-language-server's defaults, without the trailing
//                      space hints
//   Strict             lua-language-server's defaults, and unused / redefined
//                      locals and lowercase globals as warnings
// Style checks (codestyle-check, spell-check, name-style-check) stay off in
// all three, as lua-language-server has them. Every preset re-checks the
// other scripts a second after a change (workspaceEvent OnChange): a fix in
// one file, or in the generated types, clears the warnings it caused in
// the others without saving them first.
Lua_Checks_Settings :: struct {
	disable:       []string,
	severity:      [][2]string, // diagnostic -> severity
	groupSeverity: [][2]string, // group -> severity
}

LUA_CHECKS_SETTINGS := [e.Lua_Checks]Lua_Checks_Settings{
	.Relaxed  = {disable = {"trailing-space", "lowercase-global"}, severity = {{"need-check-nil", "Hint"}}},
	.Standard = {disable = {"trailing-space"}},
	.Strict   = {groupSeverity = {{"unused", "Warning"}, {"redefined", "Warning"}}, severity = {{"lowercase-global", "Warning"}}},
}

LUA_WORKSPACE_DELAY :: 1000 // ms after a change before the other scripts are re-checked

@(private = "file")
json_list :: proc(sb: ^strings.Builder, values: []string) {
	strings.write_byte(sb, '[')
	for v, i in values {
		if i > 0 do strings.write_string(sb, ", ")
		fmt.sbprintf(sb, "%q", v)
	}
	strings.write_byte(sb, ']')
}

@(private = "file")
json_pairs :: proc(sb: ^strings.Builder, pairs: [][2]string) {
	strings.write_byte(sb, '{')
	for p, i in pairs {
		if i > 0 do strings.write_string(sb, ", ")
		fmt.sbprintf(sb, "%q: %q", p[0], p[1])
	}
	strings.write_byte(sb, '}')
}

// Lua_DiagnosticsJson: the "diagnostics" settings object of a preset (the
// language server's nested form, for workspace/configuration).
Lua_DiagnosticsJson :: proc(checks: e.Lua_Checks) -> string {
	set := LUA_CHECKS_SETTINGS[checks]
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, `{"globals": `)
	json_list(&sb, CODE_LUA_GLOBALS)
	strings.write_string(&sb, `, "disable": `)
	json_list(&sb, set.disable)
	strings.write_string(&sb, `, "severity": `)
	json_pairs(&sb, set.severity)
	strings.write_string(&sb, `, "groupSeverity": `)
	json_pairs(&sb, set.groupSeverity)
	fmt.sbprintf(&sb, `, "workspaceEvent": "OnChange", "workspaceDelay": %d}`, LUA_WORKSPACE_DELAY)
	return strings.to_string(sb)
}

// luarc_text: the .luarc.json the editor writes into projects.
luarc_text :: proc(checks: e.Lua_Checks = .Relaxed) -> string {
	set := LUA_CHECKS_SETTINGS[checks]
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "{\n")
	strings.write_string(&sb, "  \"$schema\": \"https://raw.githubusercontent.com/LuaLS/vscode-lua/master/setting/schema.json\",\n")
	strings.write_string(&sb, "  \"runtime.version\": \"Lua 5.4\",\n")
	strings.write_string(&sb, "  \"workspace.library\": [\"" + LUA_DEFINITIONS_DIR + "\"],\n")
	strings.write_string(&sb, "  \"workspace.checkThirdParty\": false,\n")
	// The editor's file history keeps old copies of every script (each one
	// declaring the same ---@class): left in, LuaLS reports the real
	// script's methods as duplicate fields (#264).
	strings.write_string(&sb, "  \"workspace.ignoreDir\": [\"" + LUA_HISTORY_DIR + "\"],\n")
	strings.write_string(&sb, "  \"completion.callSnippet\": \"Replace\",\n")
	strings.write_string(&sb, "  \"diagnostics.globals\": ")
	json_list(&sb, CODE_LUA_GLOBALS)
	// The project's Lua Checks preset (LUA_CHECKS_SETTINGS).
	fmt.sbprintf(&sb, ",\n  \"diagnostics.workspaceEvent\": \"OnChange\",\n  \"diagnostics.workspaceDelay\": %d", LUA_WORKSPACE_DELAY)
	if len(set.disable) > 0 {
		strings.write_string(&sb, ",\n  \"diagnostics.disable\": ")
		json_list(&sb, set.disable)
	}
	if len(set.severity) > 0 {
		strings.write_string(&sb, ",\n  \"diagnostics.severity\": ")
		json_pairs(&sb, set.severity)
	}
	if len(set.groupSeverity) > 0 {
		strings.write_string(&sb, ",\n  \"diagnostics.groupSeverity\": ")
		json_pairs(&sb, set.groupSeverity)
	}
	strings.write_string(&sb, "\n}\n")
	return strings.to_string(sb)
}

// Lua_ProjectSetup writes the definitions and .luarc.json into the project;
// returns the absolute definitions directory ("" without a project).
Lua_ProjectSetup :: proc(state: ^EditorState) -> string {
	if state.projectPath == "" || !os.is_dir(state.projectPath) do return ""
	root := state.projectPath
	if !filepath.is_abs(root) {
		if abs, err := os.get_absolute_path(root, context.temp_allocator); err == nil do root = abs
	}
	defs, _ := filepath.join({root, LUA_DEFINITIONS_DIR}, context.temp_allocator)
	api, _ := filepath.join({defs, "engine_api.lua"}, context.temp_allocator)
	write_if_changed(api, ENGINE_API_LUA)
	// The plugin API (only in projects with plugins: game scripts don't see Editor).
	editorApi, _ := filepath.join({defs, "editor_api.lua"}, context.temp_allocator)
	pluginsDir, _ := filepath.join({root, "plugins"}, context.temp_allocator)
	if os.is_dir(pluginsDir) do write_if_changed(editorApi, EDITOR_API_LUA)
	else if os.is_file(editorApi) do _ = os.remove(editorApi)
	// .luarc.json: created, or refreshed when it's ours (points at our
	// definitions); a hand-written one is left alone.
	luarc, _ := filepath.join({root, ".luarc.json"}, context.temp_allocator)
	existing, err := os.read_entire_file(luarc, context.temp_allocator)
	// (".ore/definitions": ours, from before the rename.)
	if err != nil || strings.contains(string(existing), LUA_DEFINITIONS_DIR) || strings.contains(string(existing), ".ore/definitions") {
		write_if_changed(luarc, luarc_text(state.projectConfig.luaChecks))
	}
	Lua_WriteProjectTypes(state)
	return strings.clone(defs, context.temp_allocator)
}

// LuaSetup_Run (--lua-setup <project>): writes a project's Lua tooling files
// (.rayzr/definitions with project_types.lua, .luarc.json) without opening a
// window, as the editor does when it opens the project - so
// scripts/luals_check.sh can run `lua-language-server --check` over the
// templates, tutorials and demo project with the same types the Code tab
// sees (#403).
LuaSetup_Run :: proc(project: string) -> int {
	Resources_Init()
	state := &GlobalEditor
	state.game = new(e.Game)
	e.InitializeGame(state.game)
	state.projectPath = project
	cfg, ok := e.Game_LoadProjectForEditing(state.game, project)
	if !ok {
		fmt.eprintfln("--lua-setup: no project at %s", project)
		return 1
	}
	state.projectConfig = cfg
	state.projectLoaded = true
	defs := Lua_ProjectSetup(state)
	if defs == "" do return 1
	fmt.println(defs)
	return 0
}
