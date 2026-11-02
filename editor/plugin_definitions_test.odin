package editor

import "core:slice"
import "core:strings"
import "core:testing"
import lua "../engine/lua54"

EDITOR_API_LUA_DEFS :: #load("definitions/editor_api.lua", string)

// #327: definitions/editor_api.lua (what plugins' completion knows) matches
// what PluginAPI_Register puts in a plugin's state - Editor, Editor.fs and
// ui - both ways.
@(test)
test_plugin_definitions_match_bindings :: proc(t: ^testing.T) {
	declared := make(map[string]map[string]bool, allocator = context.temp_allocator)
	for tbl in ([]string{"Editor", "Editor.fs", "ui"}) do declared[tbl] = make(map[string]bool, allocator = context.temp_allocator)
	tableOf := make(map[string]string, allocator = context.temp_allocator) // class in the definitions -> table
	tableOf["Editor"], tableOf["EditorFS"], tableOf["ui"] = "Editor", "Editor.fs", "ui"
	for line in strings.split_lines(EDITOR_API_LUA_DEFS, context.temp_allocator) {
		if !strings.has_prefix(line, "function ") do continue
		sig := line[len("function "):]
		dot := strings.index_byte(sig, '.')
		paren := strings.index_byte(sig, '(')
		if dot < 0 || paren < dot do continue
		if tbl, ok := tableOf[sig[:dot]]; ok {
			m := &declared[tbl]
			m[sig[dot + 1:paren]] = true
		}
	}

	L := lua.L_newstate()
	defer lua.close(L)
	p := Plugin{id = "defs_test", name = "Definitions test"}
	PluginAPI_Register(L, &p)
	for tbl, want in declared {
		if tbl == "Editor.fs" {
			lua.getglobal(L, "Editor")
			lua.getfield(L, -1, "fs")
			lua.remove(L, -2)
		} else {
			lua.getglobal(L, strings.clone_to_cstring(tbl, context.temp_allocator))
		}
		defer lua.pop(L, 1)
		if !testing.expectf(t, lua.istable(L, -1), "%s is registered", tbl) do continue
		have := make([dynamic]string, context.temp_allocator)
		lua.pushnil(L)
		for lua.next(L, -2) != 0 {
			if lua.type(L, -2) == .STRING && lua.type(L, -1) == .FUNCTION do append(&have, strings.clone(string(lua.tostring(L, -2)), context.temp_allocator))
			lua.pop(L, 1)
		}
		slice.sort(have[:])
		for f in have do testing.expectf(t, want[f], "%s.%s is registered but not in editor_api.lua", tbl, f)
		for f in want do testing.expectf(t, slice.contains(have[:], f), "editor_api.lua declares %s.%s, which isn't registered", tbl, f)
	}
}
