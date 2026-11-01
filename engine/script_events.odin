package engine

import "base:runtime"
import "core:c"
import "core:log"
import "core:strings"
import lua "lua54"

// ============================================================================
// Engine events in Lua
//
// Every node event (EventSubject with a name and owner) reaches Lua two ways:
//
//   1. The owner's own script: a method named on_<event>.
//        function Door:on_body_entered(other) ... end
//        function Spawner:on_timeout() ... end
//
//   2. Connections from any script (e.g. a menu script listening to buttons):
//        local id = button:connect("clicked", function(value, source) ... end)
//        button:disconnect(id)
//
// node:emit("event", value) raises a custom event the same way.
// Connections are released when either the connecting script or the source
// node is destroyed, so handlers never run on dead objects and Lua function
// references don't leak.
//
// Global events (the event bus, event_bus.odin) go through the Events table:
//   local id = Events.connect("score_changed", function(value, source) ... end)
//   Events.emit("score_changed", 120)
// Their connections are released with the connecting script, or with the
// node passed as their scope.
// ============================================================================

Lua_Connection :: struct {
	id:     int,
	source: ^Node,           // node whose event is connected
	event:  string,          // owned
	fnRef:  c.int,           // LUA_REGISTRYINDEX ref of the handler
	owner:  ^ScriptInstance, // script that connected (nil = global code)
	// Events.connect (event_bus.odin): a global event, not a node's (source
	// is nil); scope = the node it ends with; once = released when it runs.
	bus:    bool,
	once:   bool,
	scope:  ^Node,
}

@(private = "file")
manager_for :: proc(node: ^Node, ctx: ^GameContext) -> ^ScriptManager {
	if ctx != nil && ctx.scriptManager != nil do return ctx.scriptManager
	if node != nil && node.gameContext != nil && node.gameContext.scriptManager != nil do return node.gameContext.scriptManager
	return &scriptManager
}

// push_event_value pushes an EventValue onto the Lua stack.
push_event_value :: proc(L: ^lua.State, value: EventValue) {
	switch v in value {
	case int: lua.pushinteger(L, lua.Integer(v))
	case u32: lua.pushinteger(L, lua.Integer(v))
	case u64: lua.pushinteger(L, lua.Integer(v))
	case f32: lua.pushnumber(L, lua.Number(v))
	case f64: lua.pushnumber(L, lua.Number(v))
	case bool: lua.pushboolean(L, b32(v))
	case string: lua.pushstring(L, strings.clone_to_cstring(v, context.temp_allocator))
	case ^Node:
		if Node_IsAlive(v) do push_node_userdata(L, v)
		else do lua.pushnil(L)
	case Lua_Value_Ref:
		lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(v))
	case:
		lua.pushnil(L)
	}
}

// to_event_value reads a Lua value as an EventValue (node:emit).
to_event_value :: proc(L: ^lua.State, idx: c.int) -> EventValue {
	#partial switch lua.type(L, idx) {
	case .BOOLEAN: return bool(lua.toboolean(L, idx))
	case .NUMBER:
		if lua.isinteger(L, idx) do return int(lua.tointeger(L, idx))
		return f64(lua.tonumber(L, idx))
	case .STRING: return strings.clone(string(lua.tostring(L, idx)), context.temp_allocator)
	case .USERDATA:
		if n, ok := to_node_userdata(L, idx); ok do return n
	}
	return nil
}

// Script_DispatchEvent delivers a node event to Lua: the owner's on_<event>
// method, then every connected handler.
Script_DispatchEvent :: proc(owner: ^Node, name: string, value: EventValue, ctx: ^GameContext) {
	if owner == nil do return
	if len(btWatchers) > 0 do BT_SignalSeen(owner, name) // (Behavior Trees' Wait For Signal)
	mgr := manager_for(owner, ctx)
	if mgr == nil || !mgr.isReady || mgr.L == nil || mgr.suspended do return
	L := mgr.L

	// 1. The owner's script method (once its ready() has run).
	if owner.scriptInstance != nil && (cast(^ScriptInstance)owner.scriptInstance).isReady {
		inst := cast(^ScriptInstance)owner.scriptInstance
		method := strings.concatenate({"on_", name}, context.temp_allocator)
		lua.pushcfunction(L, lua_traceback_error_handler)
		errHandler := lua.gettop(L)
		lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef))
		lua.getfield(L, -1, strings.clone_to_cstring(method, context.temp_allocator))
		if lua.type(L, -1) == .FUNCTION {
			lua.pushvalue(L, -2) // self
			push_event_value(L, value)
			prev := mgr.currentInstance
			mgr.currentInstance = inst
			if lua.pcall(L, 2, 0, errHandler) != 0 {
				Script_Problem(.Error, "[Script] Error in %s:%s(): %s", inst.modulePath, method, lua.tostring(L, -1))
				lua.pop(L, 1)
			}
			mgr.currentInstance = prev
		} else {
			lua.pop(L, 1)
		}
		lua.pop(L, 2) // self, errHandler
	}

	// 2. Connections saved with the scene (editor "Signals").
	Signals_Dispatch(mgr, owner, name, value, ctx)
	if !Node_IsAlive(owner) do return

	// 3. Handlers connected from Lua (snapshot: handlers may (dis)connect or destroy).
	if len(mgr.connections) == 0 do return
	ids := make([dynamic]int, context.temp_allocator)
	for conn in mgr.connections {
		if conn.source == owner && conn.event == name do append(&ids, conn.id)
	}
	for id in ids {
		if !Node_IsAlive(owner) do return
		idx := connection_index(mgr, id)
		if idx < 0 do continue // disconnected by an earlier handler
		conn := mgr.connections[idx]
		lua.pushcfunction(L, lua_traceback_error_handler)
		errHandler := lua.gettop(L)
		lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(conn.fnRef))
		push_event_value(L, value)
		push_node_userdata(L, owner)
		prev := mgr.currentInstance
		mgr.currentInstance = conn.owner
		if lua.pcall(L, 2, 0, errHandler) != 0 {
			Script_Problem(.Error, "[Script] Error in '%s' handler of %s: %s", name, owner.name, lua.tostring(L, -1))
			lua.pop(L, 1)
		}
		mgr.currentInstance = prev
		lua.pop(L, 1) // errHandler
	}
}

@(private = "file")
connection_index :: proc(mgr: ^ScriptManager, id: int) -> int {
	for conn, i in mgr.connections {
		if conn.id == id do return i
	}
	return -1
}

@(private = "file")
release_connection :: proc(mgr: ^ScriptManager, i: int) {
	conn := mgr.connections[i]
	if mgr.L != nil && conn.fnRef != 0 do lua.L_unref(mgr.L, lua.REGISTRYINDEX, conn.fnRef)
	delete(conn.event, Engine_HeapAllocator())
	ordered_remove(&mgr.connections, i)
}

// Script_ForgetNode drops every connection whose source is `node` (called
// when the node is destroyed).
Script_ForgetNode :: proc(node: ^Node) {
	mgr := manager_for(node, nil)
	if mgr == nil do return
	for i := len(mgr.connections) - 1; i >= 0; i -= 1 {
		if conn := mgr.connections[i]; conn.source == node || conn.scope == node do release_connection(mgr, i)
	}
}

// Script_ForgetInstance drops every connection made by a script instance.
Script_ForgetInstance :: proc(mgr: ^ScriptManager, inst: ^ScriptInstance) {
	if mgr == nil do return
	for i := len(mgr.connections) - 1; i >= 0; i -= 1 {
		if mgr.connections[i].owner == inst do release_connection(mgr, i)
	}
	if mgr.currentInstance == inst do mgr.currentInstance = nil
}

// Script_ReleaseAllConnections frees every connection (manager shutdown).
Script_ReleaseAllConnections :: proc(mgr: ^ScriptManager) {
	for len(mgr.connections) > 0 do release_connection(mgr, len(mgr.connections) - 1)
	delete(mgr.connections)
	mgr.connections = nil
}

// --- Lua bindings --------------------------------------------------------------------

// node:connect(event, fn) -> id
lua_node_connect :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || lua.type(L, 2) != .STRING || lua.type(L, 3) != .FUNCTION {
		lua.L_error(L, "usage: node:connect(event_name, function(value, source) ... end)")
		return 0
	}
	mgr := get_script_manager(L)
	if mgr == nil {
		lua.pushnil(L)
		return 1
	}
	lua.pushvalue(L, 3)
	ref := lua.L_ref(L, lua.REGISTRYINDEX)
	mgr.nextConnectionId += 1
	append(&mgr.connections, Lua_Connection{
		id     = mgr.nextConnectionId,
		source = node,
		event  = strings.clone(string(lua.tostring(L, 2)), Engine_HeapAllocator()), // made in a Lua callback
		fnRef  = ref,
		owner  = mgr.currentInstance,
	})
	lua.pushinteger(L, lua.Integer(mgr.nextConnectionId))
	return 1
}

// node:disconnect(id) -> bool
lua_node_disconnect :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	mgr := get_script_manager(L)
	id := int(lua.tointeger(L, 2))
	if mgr != nil {
		if i := connection_index(mgr, id); i >= 0 {
			release_connection(mgr, i)
			lua.pushboolean(L, true)
			return 1
		}
	}
	lua.pushboolean(L, false)
	return 1
}

// node:emit(event, value?) raises a custom event on the node.
lua_node_emit :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || lua.type(L, 2) != .STRING do return 0
	name := strings.clone(string(lua.tostring(L, 2)), context.temp_allocator)
	value := to_event_value(L, 3)
	// A table (or function) arrives as itself - the same table, by reference.
	ref: c.int
	if t := lua.type(L, 3); t == .TABLE || t == .FUNCTION {
		lua.pushvalue(L, 3)
		ref = lua.L_ref(L, lua.REGISTRYINDEX)
		value = Lua_Value_Ref(ref)
	}
	Script_DispatchEvent(node, name, value, node.gameContext)
	if ref != 0 do lua.L_unref(L, lua.REGISTRYINDEX, ref)
	return 0
}

// Script_RegisterEventBindings adds connect/disconnect/emit to the node
// metatable's method table at the top of the stack.
Script_RegisterEventBindings :: proc(L: ^lua.State) {
	lua.pushcfunction(L, lua_node_connect)
	lua.setfield(L, -2, "connect")
	lua.pushcfunction(L, lua_node_disconnect)
	lua.setfield(L, -2, "disconnect")
	lua.pushcfunction(L, lua_node_emit)
	lua.setfield(L, -2, "emit")
}

// --- Global events (Events, event_bus.odin) ------------------------------------------

// Script_DispatchBusEvent delivers a global event to the handlers connected
// with Events.connect, in connection order. luaRef: the published Lua value
// (a table, ...) handlers get instead of `value` (0 = push `value`).
Script_DispatchBusEvent :: proc(mgr: ^ScriptManager, name: string, value: EventValue, source: ^Node, luaRef: c.int) {
	if mgr == nil || !mgr.isReady || mgr.L == nil || mgr.suspended || len(mgr.connections) == 0 do return
	L := mgr.L
	// Snapshot: handlers may (dis)connect, emit or destroy.
	ids := make([dynamic]int, context.temp_allocator)
	for conn in mgr.connections do if conn.bus && conn.event == name do append(&ids, conn.id)
	for id in ids {
		idx := connection_index(mgr, id)
		if idx < 0 do continue // disconnected by an earlier handler
		conn := mgr.connections[idx]
		lua.pushcfunction(L, lua_traceback_error_handler)
		errHandler := lua.gettop(L)
		lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(conn.fnRef))
		if conn.once do release_connection(mgr, idx) // (the function stays on the stack)
		if luaRef != 0 do lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(luaRef))
		else do push_event_value(L, value)
		if Node_IsAlive(source) do push_node_userdata(L, source)
		else do lua.pushnil(L)
		prev := mgr.currentInstance
		mgr.currentInstance = conn.owner
		if lua.pcall(L, 2, 0, errHandler) != 0 {
			Script_Problem(.Error, "[Script] Error in '%s' event handler: %s", name, lua.tostring(L, -1))
			lua.pop(L, 1)
		}
		mgr.currentInstance = prev
		lua.pop(L, 1) // errHandler
	}
}

// Script_BusConnectionCount: the Lua handlers connected to a global event.
Script_BusConnectionCount :: proc(mgr: ^ScriptManager, name: string) -> int {
	if mgr == nil do return 0
	n := 0
	for conn in mgr.connections do if conn.bus && conn.event == name do n += 1
	return n
}

@(private = "file")
events_bus :: proc(L: ^lua.State) -> (^EventBus, ^ScriptManager) {
	mgr := get_script_manager(L)
	if mgr == nil || mgr.game == nil do return nil, mgr
	return &mgr.game.events, mgr
}

@(private = "file")
events_connect :: proc(L: ^lua.State, once: bool) -> c.int {
	if lua.type(L, 1) != .STRING || lua.type(L, 2) != .FUNCTION {
		lua.L_error(L, "usage: Events.connect(event_name, function(value, source) ... end [, scope_node])")
		return 0
	}
	mgr := get_script_manager(L)
	if mgr == nil {
		lua.pushnil(L)
		return 1
	}
	scope, _ := to_node_userdata(L, 3)
	lua.pushvalue(L, 2)
	ref := lua.L_ref(L, lua.REGISTRYINDEX)
	mgr.nextConnectionId += 1
	append(&mgr.connections, Lua_Connection{
		id    = mgr.nextConnectionId,
		event = strings.clone(string(lua.tostring(L, 1)), Engine_HeapAllocator()),
		fnRef = ref,
		owner = mgr.currentInstance,
		bus   = true,
		once  = once,
		scope = scope,
	})
	lua.pushinteger(L, lua.Integer(mgr.nextConnectionId))
	return 1
}

// Events.connect(event, fn [, scope]) -> id
@(private = "file")
lua_events_connect :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	return events_connect(L, false)
}

// Events.once(event, fn [, scope]) -> id: released after its first call.
@(private = "file")
lua_events_once :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	return events_connect(L, true)
}

// Events.disconnect(id) -> bool
@(private = "file")
lua_events_disconnect :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	mgr := get_script_manager(L)
	ok := false
	if mgr != nil {
		if i := connection_index(mgr, int(lua.tointeger(L, 1))); i >= 0 && mgr.connections[i].bus {
			release_connection(mgr, i)
			ok = true
		}
	}
	lua.pushboolean(L, b32(ok))
	return 1
}

@(private = "file")
events_emit :: proc(L: ^lua.State, deferred: bool) {
	bus, mgr := events_bus(L)
	if bus == nil || lua.type(L, 1) != .STRING do return
	name := strings.clone(string(lua.tostring(L, 1)), context.temp_allocator)
	value := to_event_value(L, 2) // for Odin listeners
	// The source: the given node, else the node of the script emitting.
	source, ok := to_node_userdata(L, 3)
	if !ok && mgr.currentInstance != nil do source = mgr.currentInstance.node
	// Lua handlers get the Lua value itself (tables too).
	ref: c.int
	if !lua.isnoneornil(L, 2) {
		lua.pushvalue(L, 2)
		ref = lua.L_ref(L, lua.REGISTRYINDEX)
	}
	if deferred {
		EventBus_PublishDeferredLua(bus, name, value, source, ref)
		return
	}
	EventBus_PublishLua(bus, name, value, source, ref)
	if ref != 0 do lua.L_unref(L, lua.REGISTRYINDEX, ref)
}

// Events.emit(event [, value [, source]]): delivered now.
@(private = "file")
lua_events_emit :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	events_emit(L, false)
	return 0
}

// Events.emit_deferred(event [, value [, source]]): delivered at the end of the frame.
@(private = "file")
lua_events_emit_deferred :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	events_emit(L, true)
	return 0
}

// Events.listener_count(event) -> integer
@(private = "file")
lua_events_listener_count :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	bus, _ := events_bus(L)
	n := 0
	if bus != nil && lua.type(L, 1) == .STRING do n = EventBus_ListenerCount(bus, string(lua.tostring(L, 1)))
	lua.pushinteger(L, lua.Integer(n))
	return 1
}

// Script_RegisterEventsModule creates the global Events table.
Script_RegisterEventsModule :: proc(L: ^lua.State) {
	lua.newtable(L)
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "connect", lua_events_connect)
	reg(L, "once", lua_events_once)
	reg(L, "disconnect", lua_events_disconnect)
	reg(L, "emit", lua_events_emit)
	reg(L, "emit_deferred", lua_events_emit_deferred)
	reg(L, "listener_count", lua_events_listener_count)
	lua.setglobal(L, "Events")
}
