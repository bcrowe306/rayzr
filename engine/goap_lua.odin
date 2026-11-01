package engine

import "core:c"
import "core:strings"
import lua "lua54"

// ============================================================================
// GOAP in Lua: goap_request_goal, goap_set_key / goap_get_key,
// goap_set_target / goap_get_target, goap_resolve, goap_goal, goap_action,
// goap_plan, goap_state, goap_enable_action / goap_disable_action; and the
// script marker (`X.goap = "action" / "sensor" / "goal"`).
// ============================================================================

GOAP_STATE_TEXT := [Goap_Agent_State]string{.No_Action = "no_action", .Moving_To_Target = "moving", .Performing_Action = "performing", .Moving_While_Performing = "moving_and_performing"}

@(private = "file")
lua_goap :: proc(L: ^lua.State) -> ^GoapNode {
	n, ok := to_node_userdata(L, 1)
	if !ok || n.typeId != GoapNode do return nil
	return cast(^GoapNode)n
}

@(private = "file")
goap_find_goal :: proc(g: ^GoapNode, name: string) -> int {
	for goal, i in g.goals do if goal.name == name do return i
	return -1
}

@(private = "file")
goap_find_action :: proc(g: ^GoapNode, name: string) -> int {
	for a, i in g.actions do if a.name == name do return i
	return -1
}

// goap_request_goal(name, ...) or ({names}, resolve): the goals it may
// pick from (the cheapest it can reach wins). Unknown names: warned.
@(private = "file")
lua_goap_request_goal :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	g := lua_goap(L)
	if g == nil do return 0
	names := make([dynamic]string, context.temp_allocator)
	resolve := true
	if lua.istable(L, 2) {
		n := lua.rawlen(L, 2)
		for i in 1 ..= n {
			lua.rawgeti(L, 2, lua.Integer(i))
			append(&names, strings.clone(string(lua.tostring(L, -1)), context.temp_allocator))
			lua.pop(L, 1)
		}
		if lua.gettop(L) >= 3 do resolve = bool(lua.toboolean(L, 3))
	} else {
		for i in 2 ..= lua.gettop(L) do if lua.type(L, i) == .STRING do append(&names, strings.clone(string(lua.tostring(L, i)), context.temp_allocator))
	}
	clear(&g.requested)
	for name in names {
		i := goap_find_goal(g, name)
		if i < 0 {
			Script_Problem(.Warning, "[GOAP] %s: no goal named %q", g.name, name)
			continue
		}
		append(&g.requested, i)
	}
	g.started = true // (a request replaces Request All)
	if resolve do g.needResolve = true
	return 0
}

@(private = "file")
lua_goap_set_key :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	g := lua_goap(L)
	if g == nil do return 0
	key := string(lua.L_checkstring(L, 2))
	v := 0
	#partial switch lua.type(L, 3) {
	case .BOOLEAN: v = 1 if lua.toboolean(L, 3) else 0
	case: v = int(lua.L_optinteger(L, 3, 0)) if lua.isinteger(L, 3) else int(lua.L_optnumber(L, 3, 0))
	}
	Goap_SetValue(g, key, v)
	return 0
}

@(private = "file")
lua_goap_get_key :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	g := lua_goap(L)
	if g == nil {
		lua.pushinteger(L, 0)
		return 1
	}
	v, _ := Goap_GetValue(g, string(lua.L_checkstring(L, 2)))
	lua.pushinteger(L, lua.Integer(v))
	return 1
}

@(private = "file")
lua_goap_set_target :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if g := lua_goap(L); g != nil do goap_set_target_from_lua(g, string(lua.L_checkstring(L, 2)), L, 3)
	return 0
}

@(private = "file")
lua_goap_get_target :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	g := lua_goap(L)
	if g != nil {
		if t, ok := Goap_GetTarget(g, string(lua.L_checkstring(L, 2))); ok && t.valid {
			Lua_PushVec2(L, t.pos)
			return 1
		}
	}
	lua.pushnil(L)
	return 1
}

@(private = "file")
lua_goap_resolve :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if g := lua_goap(L); g != nil do GoapNode_Resolve(g)
	return 0
}

@(private = "file")
lua_goap_goal :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	g := lua_goap(L)
	if g == nil || g.goal < 0 || g.goal >= len(g.goals) do lua.pushnil(L)
	else do lua.pushstring(L, strings.clone_to_cstring(g.goals[g.goal].name, context.temp_allocator))
	return 1
}

@(private = "file")
lua_goap_action :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	g := lua_goap(L)
	if g == nil || g.action < 0 || g.action >= len(g.actions) do lua.pushnil(L)
	else do lua.pushstring(L, strings.clone_to_cstring(g.actions[g.action].name, context.temp_allocator))
	return 1
}

@(private = "file")
lua_goap_plan :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	g := lua_goap(L)
	lua.newtable(L)
	if g == nil do return 1
	for a, i in g.plan {
		if a < 0 || a >= len(g.actions) do continue
		lua.pushstring(L, strings.clone_to_cstring(g.actions[a].name, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

@(private = "file")
lua_goap_state :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	g := lua_goap(L)
	lua.pushstring(L, strings.clone_to_cstring(GOAP_STATE_TEXT[g.state if g != nil else .No_Action], context.temp_allocator))
	return 1
}

@(private = "file")
lua_goap_enable_action :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	g := lua_goap(L)
	if g == nil do return 0
	if i := goap_find_action(g, string(lua.L_checkstring(L, 2))); i >= 0 {
		g.actions[i].disabledUntil = 0
		g.needResolve = true
	}
	return 0
}

// goap_disable_action(name [, seconds]): the planner skips it (for good,
// or for that long - a cooldown).
@(private = "file")
lua_goap_disable_action :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	g := lua_goap(L)
	if g == nil do return 0
	i := goap_find_action(g, string(lua.L_checkstring(L, 2)))
	if i < 0 do return 0
	secs := lua.L_optnumber(L, 3, 0)
	g.actions[i].disabledUntil = g.time + f64(secs) if secs > 0 else -1
	if g.action == i do g.needResolve = true
	return 0
}

// Script_ParseGoapMarker reads `Class.goap = "action" / "sensor" / "goal"`.
Script_ParseGoapMarker :: proc(L: ^lua.State, idx: c.int, mod: ^ScriptModule) {
	idx := lua.absindex(L, idx)
	lua.getfield(L, idx, "goap")
	defer lua.pop(L, 1)
	kind := ""
	if lua.type(L, -1) == .STRING {
		switch string(lua.tostring(L, -1)) {
		case "action", "sensor", "goal": kind = strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
		case: Script_Problem(.Warning, "[GOAP] %s: `goap` is \"action\", \"sensor\" or \"goal\"", mod.path)
		}
	}
	if mod.goap != kind {
		delete(mod.goap)
		mod.goap = strings.clone(kind) if kind != "" else ""
	}
}

// Script_RegisterGoapBindings: the node methods (on the node method table).
Script_RegisterGoapBindings :: proc(L: ^lua.State) {
	for f in ([]struct {name: cstring, fn: lua.CFunction}{
		{"goap_request_goal", lua_goap_request_goal},
		{"goap_set_key", lua_goap_set_key},
		{"goap_get_key", lua_goap_get_key},
		{"goap_set_target", lua_goap_set_target},
		{"goap_get_target", lua_goap_get_target},
		{"goap_resolve", lua_goap_resolve},
		{"goap_goal", lua_goap_goal},
		{"goap_action", lua_goap_action},
		{"goap_plan", lua_goap_plan},
		{"goap_state", lua_goap_state},
		{"goap_enable_action", lua_goap_enable_action},
		{"goap_disable_action", lua_goap_disable_action},
	}) {
		lua.pushcfunction(L, f.fn)
		lua.setfield(L, -2, f.name)
	}
}
