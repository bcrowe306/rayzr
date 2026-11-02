package engine

import "core:c"
import "core:fmt"
import "core:strings"
import lua "lua54"

// ============================================================================
// Deprecated Lua names (#327): the 1.x API promise. A name that is replaced
// keeps working until 2.0, as an alias of the new one that warns - once per
// call site (script:line), naming the replacement - in the editor, Play from
// the editor and debug builds. Release exports stay silent.
//
//     Lua_SetDeprecated(L, lua_node_destroy, "queue_free", "destroy")
//
// sets `queue_free` on the table at the top of the stack. The definitions
// (engine_api.lua) mark it `---@deprecated Use destroy` so the Code tab
// strikes it through.
// ============================================================================

// Deprecated calls warn (the runner turns it on for Play from the editor).
Lua_WarnDeprecated := ODIN_DEBUG

// Call sites already warned about ("old@script:line").
@(private = "file")
deprecatedSeen: map[string]bool

// Lua_SetDeprecated sets `old` on the table at -1: `fn`, warning that
// `replacement` is the name to use.
Lua_SetDeprecated :: proc(L: ^lua.State, fn: lua.CFunction, old, replacement: cstring) {
	lua.pushcfunction(L, fn)
	lua.pushstring(L, old)
	lua.pushstring(L, replacement)
	lua.pushcclosure(L, lua_deprecated_call, 3)
	lua.setfield(L, -2, old)
}

// Lua_WarnDeprecatedName warns (once per call site) that `old` - a function,
// a property, an option - is deprecated in favour of `replacement`.
Lua_WarnDeprecatedName :: proc(L: ^lua.State, old, replacement: string) {
	if !Lua_WarnDeprecated do return
	lua.L_where(L, 1)
	site := strings.trim_right(string(lua.tostring(L, -1)), ": ")
	lua.pop(L, 1)
	if deprecatedSeen == nil do deprecatedSeen = make(map[string]bool, 16, Engine_HeapAllocator())
	key := fmt.tprintf("%s@%s", old, site)
	if key in deprecatedSeen do return
	deprecatedSeen[strings.clone(key, Engine_HeapAllocator())] = true
	at := site if site != "" else "a script"
	Script_Problem(.Warning, "[Lua] %s: %s is deprecated, use %s (it stops working in Rayzr 2.0)", at, old, replacement)
}

// Lua_ForgetDeprecationWarnings: warn again (a new Play / script reload).
Lua_ForgetDeprecationWarnings :: proc() {
	for k in deprecatedSeen do delete(k, Engine_HeapAllocator())
	clear(&deprecatedSeen)
}

@(private = "file")
upvalue :: #force_inline proc "contextless" (i: c.int) -> c.int {return lua.REGISTRYINDEX - i}

@(private = "file")
lua_deprecated_call :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	Lua_WarnDeprecatedName(L, string(lua.tostring(L, upvalue(2))), string(lua.tostring(L, upvalue(3))))
	// The function, under its arguments: called with all of them, every result back.
	n := lua.gettop(L)
	lua.pushvalue(L, upvalue(1))
	lua.insert(L, 1)
	lua.call(L, n, lua.MULTRET)
	return lua.gettop(L)
}

// Lua_DeprecationWarningCount: call sites warned about so far (tests).
Lua_DeprecationWarningCount :: proc() -> int {
	return len(deprecatedSeen)
}
