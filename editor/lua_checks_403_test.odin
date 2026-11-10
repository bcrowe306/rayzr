package editor

import "core:encoding/json"
import "core:strings"
import "core:testing"
import e "../engine"

// #403: the Lua Checks presets, as the editor writes them into .luarc.json
// and sends them to the Code tab's server: valid JSON, each preset's
// diagnostics, and every preset re-checking the other scripts on a change
// (a fix in one file, or in the generated types, clears the others').
@(test)
test_lua_checks_presets :: proc(t: ^testing.T) {
	for checks in e.Lua_Checks {
		rc := luarc_text(checks)
		v, err := json.parse_string(rc, allocator = context.temp_allocator)
		testing.expectf(t, err == .None, "%v: .luarc.json isn't JSON: %s", checks, rc)
		o, _ := v.(json.Object)
		testing.expect_value(t, o["diagnostics.workspaceEvent"].(json.String) or_else "", "OnChange")
		testing.expect(t, strings.contains(rc, `"workspace.library": [".rayzr/definitions"]`), rc)

		d, derr := json.parse_string(Lua_DiagnosticsJson(checks), allocator = context.temp_allocator)
		testing.expectf(t, derr == .None, "%v: the server settings aren't JSON", checks)
		do_, _ := d.(json.Object)
		globals, _ := do_["globals"].(json.Array)
		testing.expect_value(t, len(globals), len(CODE_LUA_GLOBALS))
		testing.expect_value(t, do_["workspaceEvent"].(json.String) or_else "", "OnChange")
	}
	relaxed := luarc_text(.Relaxed)
	testing.expect(t, strings.contains(relaxed, `"diagnostics.severity": {"need-check-nil": "Hint"}`), relaxed)
	testing.expect(t, strings.contains(relaxed, `"trailing-space"`) && strings.contains(relaxed, `"lowercase-global"`), relaxed)
	standard := luarc_text(.Standard)
	testing.expect(t, !strings.contains(standard, "need-check-nil") && strings.contains(standard, `"diagnostics.disable": ["trailing-space"]`), standard)
	strict := luarc_text(.Strict)
	testing.expect(t, strings.contains(strict, `"unused": "Warning"`) && !strings.contains(strict, `"diagnostics.disable"`), strict)
	testing.expect_value(t, luarc_text(), relaxed) // (the default)
	free_all(context.temp_allocator)
}

// #403: a field the script types itself wins over the generated type of an
// exported property (a node property: ---@field map TileMapNode).
@(test)
test_script_declares_field :: proc(t: ^testing.T) {
	src := `---@class Player : ScriptInstanceBase
---@field path_map TileMapNode
---@field private  walls? TileMapNode The walls
---@field speedy number
local Player = {}
`
	testing.expect(t, script_declares_field(src, "path_map"))
	testing.expect(t, script_declares_field(src, "walls"))
	testing.expect(t, !script_declares_field(src, "speed"), "a longer name isn't it")
	testing.expect(t, !script_declares_field(src, "map"))
	free_all(context.temp_allocator)
}
