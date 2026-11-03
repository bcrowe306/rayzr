package engine

import "core:slice"
import "core:strings"
import "core:testing"
import lua "lua54"

// definitions/engine_api.lua (what the language server knows) matches the
// functions the engine registers in Lua: every node method and module
// function is declared, and every declared one exists.
ENGINE_API_LUA :: #load("definitions/engine_api.lua", string)

@(test)
test_lua_definitions_match_bindings :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	L := game.scriptManager.L

	// Declared: "function Class:method(" on node classes (Node, its subtypes
	// and mixins) and "function XModule.fn(" with "Global = XModule".
	nodeDecl := make(map[string]bool, allocator = context.temp_allocator)
	modDecl := make(map[string]map[string]bool, allocator = context.temp_allocator) // module class -> fns
	globalOf := make(map[string]string, allocator = context.temp_allocator)         // module class -> global
	for line in strings.split_lines(ENGINE_API_LUA, context.temp_allocator) {
		l := strings.trim_space(line)
		if strings.has_prefix(l, "function ") {
			sig := l[len("function "):]
			paren := strings.index_byte(sig, '(')
			if paren < 0 do continue
			sig = sig[:paren]
			if i := strings.index_byte(sig, ':'); i >= 0 {
				cls := sig[:i]
				if cls == "Node" || strings.has_suffix(cls, "Node") || cls == "TextHolder" || cls == "NavGrid" || cls == "UIListHolder" || cls == "UIFocusable" do nodeDecl[sig[i + 1:]] = true
			} else if i := strings.index_byte(sig, '.'); i >= 0 {
				cls := sig[:i]
				if cls not_in modDecl do modDecl[cls] = make(map[string]bool, allocator = context.temp_allocator)
				m := &modDecl[cls]
				m[sig[i + 1:]] = true
			}
		} else if eq := strings.index(l, " = "); eq > 0 && strings.has_suffix(l, "Module") && !strings.contains(l[:eq], " ") {
			globalOf[l[eq + 3:]] = l[:eq]
		}
	}

	keys :: proc(L: ^lua.State, idx: i32) -> []string {
		out := make([dynamic]string, context.temp_allocator)
		lua.pushnil(L)
		for lua.next(L, idx - 1 if idx < 0 else idx) != 0 {
			if lua.type(L, -2) == .STRING && lua.type(L, -1) == .FUNCTION {
				k := string(lua.tostring(L, -2))
				if !strings.has_prefix(k, "__") do append(&out, strings.clone(k, context.temp_allocator))
			}
			lua.pop(L, 1)
		}
		slice.sort(out[:])
		return out[:]
	}

	// Node methods.
	lua.L_getmetatable(L, "Engine.Node")
	registered := keys(L, -1)
	lua.pop(L, 1)
	testing.expect(t, len(registered) > 150, "node methods registered")
	for m in registered do testing.expectf(t, nodeDecl[m], "node method %s is not in engine_api.lua", m)
	regSet := make(map[string]bool, allocator = context.temp_allocator)
	for m in registered do regSet[m] = true
	for m in nodeDecl do testing.expectf(t, regSet[m], "engine_api.lua declares Node method %s, which isn't registered", m)

	// Modules.
	testing.expect(t, len(globalOf) >= 10, "module globals found in the definitions")
	for cls, global in globalOf {
		lua.getglobal(L, strings.clone_to_cstring(global, context.temp_allocator))
		defer lua.pop(L, 1)
		if !testing.expectf(t, lua.istable(L, -1), "global %s missing", global) do continue
		fns := keys(L, -1)
		declared := modDecl[cls]
		have := make(map[string]bool, allocator = context.temp_allocator)
		for f in fns {
			have[f] = true
			testing.expectf(t, declared[f], "%s.%s is not in engine_api.lua", global, f)
		}
		for f in declared do testing.expectf(t, have[f], "engine_api.lua declares %s.%s, which isn't registered", global, f)
	}
}
