package engine

import "core:c"
import "core:strings"
import lua "lua54"

// ============================================================================
// Behavior Trees in Lua: node methods (bt_tick, bt_interrupt, bt_status,
// bt_get / bt_set / bt_has / bt_erase, bt_blackboard, bt_running_action,
// bt_last_condition), the blackboard object leaf scripts get
// (bb:get / set / has / erase / keys), and the global one (Blackboard.*).
// ============================================================================

BT_STATUS_TEXT := [BT_Status]string{.None = "none", .Success = "success", .Failure = "failure", .Running = "running"}

@(private = "file")
lua_bt :: proc(L: ^lua.State) -> ^BehaviorTreeNode {
	n, ok := to_node_userdata(L, 1)
	if !ok || n.typeId != BehaviorTreeNode do return nil
	return cast(^BehaviorTreeNode)n
}

// bt_lua_value: a Lua value as a blackboard value (a node: its path from
// the tree; a table {x, y}: a vector).
@(private = "file")
bt_lua_value :: proc(L: ^lua.State, idx: c.int, t: ^BehaviorTreeNode) -> BB_Value {
	#partial switch lua.type(L, idx) {
	case .BOOLEAN: return bool(lua.toboolean(L, idx))
	case .NUMBER:  return f64(lua.tonumber(L, idx))
	case .STRING:  return strings.clone(string(lua.tostring(L, idx)), context.temp_allocator)
	case .TABLE:
		x, y := arg_xy(L, idx)
		return [2]f32{x, y}
	case .USERDATA:
		if n, ok := to_node_userdata(L, idx); ok {
			mgr: ^NodeManager
			for cur := n; cur != nil && mgr == nil; cur = cur.parent do if cur.gameContext != nil && cur.gameContext.scene != nil do mgr = cur.gameContext.scene.manager
			if mgr != nil && t != nil do return Node_RelativePath(mgr, t, n)
		}
	}
	return nil
}

@(private = "file")
bt_board_of :: proc(L: ^lua.State, t: ^BehaviorTreeNode, globalIdx: c.int) -> ^map[string]BB_Value {
	if globalIdx > 0 && lua.toboolean(L, globalIdx) do return &btGlobal
	return BehaviorTree_Blackboard(t)
}

@(private = "file")
lua_bt_tick :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	t := lua_bt(L)
	if t == nil {
		lua.pushnil(L)
		return 1
	}
	dt := f32(lua.L_optnumber(L, 2, 1.0 / 60))
	lua.pushstring(L, strings.clone_to_cstring(BT_STATUS_TEXT[BehaviorTree_Tick(t, dt)], context.temp_allocator))
	return 1
}

@(private = "file")
lua_bt_interrupt :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if t := lua_bt(L); t != nil do BehaviorTree_Interrupt(t)
	return 0
}

@(private = "file")
lua_bt_status :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	t := lua_bt(L)
	lua.pushstring(L, strings.clone_to_cstring(BT_STATUS_TEXT[t.status if t != nil else .None], context.temp_allocator))
	return 1
}

@(private = "file")
lua_bt_get :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	t := lua_bt(L)
	if t == nil {
		lua.pushnil(L)
		return 1
	}
	bb := bt_board_of(L, t, 3)
	bt_push_bb_value(L, bb[string(lua.L_checkstring(L, 2))] or_else nil)
	return 1
}

@(private = "file")
lua_bt_set :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	t := lua_bt(L)
	if t == nil do return 0
	key := string(lua.L_checkstring(L, 2))
	v := bt_lua_value(L, 3, t)
	bb := bt_board_of(L, t, 4)
	if v == nil do BB_Erase(bb, key)
	else do BB_Set(bb, key, v)
	return 0
}

@(private = "file")
lua_bt_has :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	t := lua_bt(L)
	ok := false
	if t != nil {
		bb := bt_board_of(L, t, 3)
		ok = string(lua.L_checkstring(L, 2)) in bb^
	}
	lua.pushboolean(L, b32(ok))
	return 1
}

@(private = "file")
lua_bt_erase :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if t := lua_bt(L); t != nil do BB_Erase(bt_board_of(L, t, 3), string(lua.L_checkstring(L, 2)))
	return 0
}

@(private = "file")
lua_bt_blackboard :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	t := lua_bt(L)
	if t == nil {
		lua.pushnil(L)
		return 1
	}
	BehaviorTree_PushBlackboard(L, t)
	return 1
}

// bt_running_action(): the running leaf's name (nil: none).
@(private = "file")
lua_bt_running_action :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	t := lua_bt(L)
	if t == nil || t.runningAction < 0 || t.runningAction >= len(t.nodes) {
		lua.pushnil(L)
		return 1
	}
	lua.pushstring(L, strings.clone_to_cstring(BT_NodeName(&t.nodes[t.runningAction]), context.temp_allocator))
	return 1
}

// bt_last_condition(): the last condition's name and its answer.
@(private = "file")
lua_bt_last_condition :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	t := lua_bt(L)
	if t == nil || t.lastCondition < 0 || t.lastCondition >= len(t.nodes) {
		lua.pushnil(L)
		lua.pushnil(L)
		return 2
	}
	lua.pushstring(L, strings.clone_to_cstring(BT_NodeName(&t.nodes[t.lastCondition]), context.temp_allocator))
	lua.pushstring(L, strings.clone_to_cstring(BT_STATUS_TEXT[t.lastConditionStatus], context.temp_allocator))
	return 2
}

// ----------------------------------------------------------------------------
// The blackboard object: {__tree = <light userdata>} (nil: the global one)
// with get / set / has / erase / keys.
// ----------------------------------------------------------------------------

@(private = "file")
bb_self :: proc(L: ^lua.State) -> (bb: ^map[string]BB_Value, t: ^BehaviorTreeNode) {
	lua.L_checktype(L, 1, i32(lua.TTABLE))
	lua.getfield(L, 1, "__tree")
	defer lua.pop(L, 1)
	if lua.type(L, -1) != .LIGHTUSERDATA do return &btGlobal, nil
	t = cast(^BehaviorTreeNode)lua.touserdata(L, -1)
	if !Node_IsAlive(t) do return &btGlobal, nil
	return BehaviorTree_Blackboard(t), t
}

@(private = "file")
lua_bb_get :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	bb, _ := bb_self(L)
	key := string(lua.L_checkstring(L, 2))
	if v, ok := bb[key]; ok do bt_push_bb_value(L, v)
	else if lua.gettop(L) >= 3 do lua.pushvalue(L, 3) // a default
	else do lua.pushnil(L)
	return 1
}

@(private = "file")
lua_bb_set :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	bb, t := bb_self(L)
	key := string(lua.L_checkstring(L, 2))
	v := bt_lua_value(L, 3, t)
	if v == nil do BB_Erase(bb, key)
	else do BB_Set(bb, key, v)
	return 0
}

@(private = "file")
lua_bb_has :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	bb, _ := bb_self(L)
	lua.pushboolean(L, b32(string(lua.L_checkstring(L, 2)) in bb^))
	return 1
}

@(private = "file")
lua_bb_erase :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	bb, _ := bb_self(L)
	BB_Erase(bb, string(lua.L_checkstring(L, 2)))
	return 0
}

@(private = "file")
lua_bb_keys :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	bb, _ := bb_self(L)
	lua.createtable(L, c.int(len(bb^)), 0)
	i := 1
	for k in bb^ {
		lua.pushstring(L, strings.clone_to_cstring(k, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(i))
		i += 1
	}
	return 1
}

@(private = "file")
BB_META_KEY :: "__Engine_BlackboardMeta"

@(private = "file")
bb_push_meta :: proc(L: ^lua.State) {
	lua.getfield(L, lua.REGISTRYINDEX, BB_META_KEY)
	if lua.type(L, -1) == .TABLE do return
	lua.pop(L, 1)
	lua.newtable(L)
	lua.newtable(L) // __index: the methods
	for f in ([]struct {name: cstring, fn: lua.CFunction}{{"get", lua_bb_get}, {"set", lua_bb_set}, {"has", lua_bb_has}, {"erase", lua_bb_erase}, {"keys", lua_bb_keys}}) {
		lua.pushcfunction(L, f.fn)
		lua.setfield(L, -2, f.name)
	}
	lua.setfield(L, -2, "__index")
	lua.pushvalue(L, -1)
	lua.setfield(L, lua.REGISTRYINDEX, BB_META_KEY)
}

// BehaviorTree_PushBlackboard pushes a tree's blackboard object (made once).
BehaviorTree_PushBlackboard :: proc(L: ^lua.State, t: ^BehaviorTreeNode) {
	if t.bbRef != 0 {
		lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(t.bbRef))
		return
	}
	lua.newtable(L)
	lua.pushlightuserdata(L, t)
	lua.setfield(L, -2, "__tree")
	bb_push_meta(L)
	lua.setmetatable(L, -2)
	lua.pushvalue(L, -1)
	t.bbRef = i32(lua.L_ref(L, lua.REGISTRYINDEX))
}

// Script_ParseBehaviorMarker reads `Class.behavior = "action" / "condition"`
// (a Behavior Tree leaf script) into mod.behavior.
Script_ParseBehaviorMarker :: proc(L: ^lua.State, idx: c.int, mod: ^ScriptModule) {
	idx := lua.absindex(L, idx)
	lua.getfield(L, idx, "behavior")
	defer lua.pop(L, 1)
	b := ""
	if lua.type(L, -1) == .STRING {
		switch string(lua.tostring(L, -1)) {
		case "action":    b = "action"
		case "condition": b = "condition"
		case: Script_Problem(.Warning, "[BehaviorTree] %s: `behavior` is \"action\" or \"condition\"", mod.path)
		}
	}
	if mod.behavior != b {
		delete(mod.behavior)
		mod.behavior = strings.clone(b) if b != "" else ""
	}
}

// Script_RegisterBehaviorTreeBindings: the node methods (on the node method
// table) and the global `Blackboard`.
Script_RegisterBehaviorTreeBindings :: proc(L: ^lua.State) {
	for f in ([]struct {name: cstring, fn: lua.CFunction}{
		{"bt_tick", lua_bt_tick},
		{"bt_interrupt", lua_bt_interrupt},
		{"bt_status", lua_bt_status},
		{"bt_get", lua_bt_get},
		{"bt_set", lua_bt_set},
		{"bt_has", lua_bt_has},
		{"bt_erase", lua_bt_erase},
		{"bt_blackboard", lua_bt_blackboard},
		{"bt_running_action", lua_bt_running_action},
		{"bt_last_condition", lua_bt_last_condition},
	}) {
		lua.pushcfunction(L, f.fn)
		lua.setfield(L, -2, f.name)
	}
	// Blackboard: the global blackboard object (no __tree).
	lua.newtable(L)
	bb_push_meta(L)
	lua.setmetatable(L, -2)
	lua.setglobal(L, "Blackboard")
}
