package engine

import "core:fmt"
import "core:log"
import "core:reflect"
import "core:strings"
import lua "lua54"

// ============================================================================
// Signal connections (Godot-style, saved with the scene).
//
// A node's events can be connected in the editor to a method of another
// node's script. The connection lives on the *source* node and is saved
// with it ("connections": [{"signal", "target", "method"}]); `target` is a
// path relative to the source ("." self, ".." parent, "../Player", "Gun"),
// so connections inside components keep working when instanced. When the
// event fires, the target's script method is called as
// `Target:method(value, source)` (after the source's own on_<event>).
//
// Events a node offers: Node_EventNames (every EventSubject field of its
// type), with Event_ParamName naming the value for generated handlers.
// ============================================================================

Signal_Connection :: struct {
	signal: string,
	target: string, // path relative to the source node
	method: string,
	node:   ^Node,  // runtime-only direct target (not saved), e.g. LDtk entity links
}

Event_Info :: struct {
	name:  string,
	param: string, // name of the value argument ("" = none)
	doc:   string,
}

// Event_Describe: argument name and a one-line description of an event.
Event_Describe :: proc(name: string) -> (param: string, doc: string) {
	switch name {
	case "entered_tree":       return "", "The node joined the scene"
	case "exited_tree":        return "", "The node is being removed"
	case "child_added":        return "child", "A child node was added"
	case "child_removed":      return "child", "A child node was removed"
	case "parent_added":       return "parent", "The node got a parent"
	case "parent_removed":     return "parent", "The node lost its parent"
	case "cycle":              return "cycles", "The oscillator finished a cycle (cycles so far)"
	case "timeout":            return "", "The timer's duration elapsed"
	case "tick":               return "elapsed", "Every frame while the timer runs"
	case "body_entered":       return "other", "A body entered the area"
	case "body_exited":        return "other", "A body left the area"
	case "collision_started":  return "other", "Contact with another body began"
	case "collision_ended":    return "other", "Contact with another body ended"
	case "hit_started":        return "other", "The ray started hitting a node"
	case "hit_ended":          return "other", "The ray stopped hitting a node"
	case "particle_hit":       return "other", "A particle hit a body (collision on; particle_get_last_hit: where)"
	case "animation_finished": return "name", "A non-looping animation ended (Aseprite: a tag's repeats are done)"
	case "animation_looped":   return "name", "An Aseprite tag started again (a repeat or a ping-pong turn)"
	case "frame_changed":      return "frame", "The Aseprite node shows another frame (0-based)"
	case "state_changed":      return "state", "The state machine entered a state"
	case "finished":           return "", "Playback, the dialogue or the oscillator's Loops ended"
	case "revealed":           return "", "The text finished revealing"
	case "line_shown":         return "index", "A dialogue line was fully shown (1-based)"
	case "chosen":             return "choice", "A dialogue choice was taken (1-based)"
	case "clicked":            return "", "The button was clicked"
	case "value_changed":      return "value", "The value changed"
	case "submitted":          return "text", "Enter was pressed"
	case "selected":           return "index", "The selection changed"
	case "row_selected":       return "row", "A table row was selected"
	case "sorted":             return "column", "The table was sorted (by a header click or set_property)"
	case "item_clicked":       return "id", "A toolbar item was clicked"
	case "tab_changed":        return "index", "Another tab was opened (0-based)"
	case "level_loaded":       return "identifier", "The LDtk level was built"
	case "entity_spawned":     return "node", "An LDtk entity was spawned"
	case "screen_entered":     return "", "The camera started seeing it"
	case "screen_exited":      return "", "The camera stopped seeing it"
	case "path_finished":      return "", "The follower reached the end of its path (loop: Stop)"
	case "navigation_finished": return "", "The agent arrived at its target"
	case "target_unreachable":  return "", "No way to the agent's target"
	case "animation_event":    return "method", "A Method key of the animation fired (its method name)"
	case "skeleton_event":     return "name", "An event key of the skeleton's animation fired (its name)"
	case "became_active":       return "", "The host camera switched to this advanced camera"
	case "became_inactive":     return "", "Another advanced camera took over"
	case "path_looped":        return "", "The follower wrapped round or turned back (Loop / Ping Pong)"
	case "spawned":            return "node", "The spawner made a node (the spawned root; spawn_info(node): its entry)"
	case "limit_reached":      return "", "The spawner reached its Total Limit"
	case "list_finished":      return "", "A Sequential spawner (Stop) spawned its last entry"
	case "generated":          return "seed", "The level generator's level is in (its seed)"
	case "generation_failed":  return "why", "The level generator couldn't make the level (why)"
	}
	return "value", ""
}

// Node_EventNames lists the events a node raises (its EventSubject fields).
Node_EventNames :: proc(node: ^Node, allocator := context.temp_allocator) -> []Event_Info {
	out := make([dynamic]Event_Info, allocator)
	if node == nil do return out[:]
	// Every node's tree events (kept outside the node: Node_Subject).
	for name in NODE_EVENT_NAMES {
		p, d := Event_Describe(name)
		append(&out, Event_Info{name, p, d})
	}
	walk :: proc(out: ^[dynamic]Event_Info, tid: typeid, base: rawptr) {
		for f in reflect.struct_fields_zipped(tid) {
			ptr := rawptr(uintptr(base) + f.offset)
			if f.type.id == EventSubject {
				subj := cast(^EventSubject)ptr
				if subj.name == "" do continue
				dup := false
				for e in out do if e.name == subj.name do dup = true
				if dup do continue
				p, d := Event_Describe(subj.name)
				append(out, Event_Info{subj.name, p, d})
				continue
			}
			if f.is_using {
				if _, isStruct := reflect.type_info_base(f.type).variant.(reflect.Type_Info_Struct); isStruct {
					walk(out, f.type.id, ptr)
				}
			}
		}
	}
	walk(&out, node.typeId, node)
	return out[:]
}

// Node_RelativePath: path from `from` to `to` ("." / "Child/Sub" / "../X").
Node_RelativePath :: proc(manager: ^NodeManager, from, to: ^Node, allocator := context.temp_allocator) -> string {
	if from == to do return "."
	// Ancestors of `from` (including itself).
	chain := make([dynamic]^Node, context.temp_allocator)
	for n := from; n != nil; n = GetParent(manager, n) do append(&chain, n)
	// Walk up from `to` until we meet that chain.
	down := make([dynamic]string, context.temp_allocator)
	common: ^Node
	for n := to; n != nil; n = GetParent(manager, n) {
		found := false
		for c in chain do if c == n {found = true; break}
		if found {common = n; break}
		inject_at(&down, 0, n.name)
	}
	if common == nil do return ""
	parts := make([dynamic]string, context.temp_allocator)
	for n := from; n != common; n = GetParent(manager, n) do append(&parts, "..")
	append(&parts, ..down[:])
	if len(parts) == 0 do return "."
	return strings.join(parts[:], "/", allocator)
}

// Node_ResolvePath follows a relative path from `from` (nil if missing).
// (The hierarchy is on the nodes: `manager` may be nil.)
Node_ResolvePath :: proc(manager: ^NodeManager, from: ^Node, path: string) -> ^Node {
	if from == nil do return nil
	cur := from
	if path == "" || path == "." do return cur
	for part in strings.split(path, "/", context.temp_allocator) {
		switch part {
		case ".", "":
		case "..":
			cur = GetParent(manager, cur)
		case:
			next: ^Node
			for c in GetChildrenView(manager, cur) do if c != nil && c.name == part {next = c; break}
			cur = next
		}
		if cur == nil do return nil
	}
	return cur
}

// Node_AddConnection connects `signal` of `source` to `method` on the
// script of `target` (saved with the scene). Returns false if it exists.
Node_AddConnection :: proc(source: ^Node, signal, targetPath, method: string) -> bool {
	for c in source.signalConnections {
		if c.signal == signal && c.target == targetPath && c.method == method do return false
	}
	if source.signalConnections == nil do source.signalConnections = make([dynamic]Signal_Connection, source.allocator)
	append(&source.signalConnections, Signal_Connection{
		signal = strings.clone(signal, source.allocator),
		target = strings.clone(targetPath, source.allocator),
		method = strings.clone(method, source.allocator),
	})
	return true
}

// Node_AddDirectConnection connects `signal` of `source` to `method` on a
// specific node (runtime only: not saved with the scene).
Node_AddDirectConnection :: proc(source: ^Node, signal: string, target: ^Node, method: string) -> bool {
	for c in source.signalConnections {
		if c.signal == signal && c.node == target && c.method == method do return false
	}
	if source.signalConnections == nil do source.signalConnections = make([dynamic]Signal_Connection, source.allocator)
	append(&source.signalConnections, Signal_Connection{
		signal = strings.clone(signal, source.allocator),
		method = strings.clone(method, source.allocator),
		node = target,
	})
	return true
}

Node_RemoveConnection :: proc(source: ^Node, signal, targetPath, method: string) -> bool {
	for c, i in source.signalConnections {
		if c.signal == signal && c.target == targetPath && c.method == method {
			ordered_remove(&source.signalConnections, i)
			return true
		}
	}
	return false
}

// script_call_method calls `Target:method(value, source)` if the target's
// script is ready and defines it.
@(private = "file")
script_call_method :: proc(mgr: ^ScriptManager, target: ^Node, method: string, value: EventValue, source: ^Node, quiet := false) {
	if target.scriptInstance == nil do return
	inst := cast(^ScriptInstance)target.scriptInstance
	if !inst.isReady do return
	L := mgr.L
	lua.pushcfunction(L, lua_traceback_error_handler)
	errHandler := lua.gettop(L)
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef))
	lua.getfield(L, -1, strings.clone_to_cstring(method, context.temp_allocator))
	if lua.type(L, -1) == .FUNCTION {
		lua.pushvalue(L, -2) // self
		push_event_value(L, value)
		push_node_userdata(L, source)
		prev := mgr.currentInstance
		mgr.currentInstance = inst
		if lua.pcall(L, 3, 0, errHandler) != 0 {
			log.errorf("[Script] Error in %s:%s(): %s", inst.modulePath, method, lua.tostring(L, -1))
			lua.pop(L, 1)
		}
		mgr.currentInstance = prev
	} else {
		lua.pop(L, 1)
		if !quiet do log.warnf("[Signals] %s has no method %s (connected from %s)", inst.modulePath, method, source.name)
	}
	lua.pop(L, 2) // self, errHandler
}

// Script_CallMethod calls `Target:method(value, target)` on a node's script
// if it's ready and defines it (animation method tracks, ...); quiet: no
// warning when it doesn't (optional callbacks like on_enter_<state>).
Script_CallMethod :: proc(mgr: ^ScriptManager, target: ^Node, method: string, value: EventValue, quiet := false) {
	if mgr == nil || target == nil || !Node_IsAlive(target) do return
	script_call_method(mgr, target, method, value, target, quiet)
}

// Signals_Dispatch runs a source node's saved connections for an event.
Signals_Dispatch :: proc(mgr: ^ScriptManager, owner: ^Node, name: string, value: EventValue, ctx: ^GameContext) {
	if len(owner.signalConnections) == 0 do return
	gc := ctx if ctx != nil else owner.gameContext
	if gc == nil || gc.scene == nil do return
	nodes := gc.scene.manager
	// Snapshot: a handler may change connections or destroy nodes.
	conns := make([dynamic]Signal_Connection, context.temp_allocator)
	for c in owner.signalConnections do if c.signal == name do append(&conns, Signal_Connection{strings.clone(c.signal, context.temp_allocator), strings.clone(c.target, context.temp_allocator), strings.clone(c.method, context.temp_allocator), c.node})
	for c in conns {
		if !Node_IsAlive(owner) do return
		target := c.node
		if target == nil {
			target = Node_ResolvePath(nodes, owner, c.target)
			if target == nil {
				log.warnf("[Signals] %s.%s: target '%s' not found", owner.name, name, c.target)
				continue
			}
		} else if !Node_IsAlive(target) {
			continue
		}
		if signals_builtin(mgr, target, c.method, gc) do continue
		script_call_method(mgr, target, c.method, value, owner)
	}
}

// script_has_method: does the node's script define `method`?
@(private = "file")
script_has_method :: proc(mgr: ^ScriptManager, target: ^Node, method: string) -> bool {
	if mgr == nil || mgr.L == nil || target.scriptInstance == nil do return false
	inst := cast(^ScriptInstance)target.scriptInstance
	L := mgr.L
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef))
	lua.getfield(L, -1, strings.clone_to_cstring(method, context.temp_allocator))
	found := lua.type(L, -1) == .FUNCTION
	lua.pop(L, 2)
	return found
}

// signals_builtin: connections to a node's own method, no script needed
// (a spawner's `spawn`, a level generator's `generate` - unless its script
// defines its own).
@(private = "file")
signals_builtin :: proc(mgr: ^ScriptManager, target: ^Node, method: string, ctx: ^GameContext) -> bool {
	if target.typeId == SpawnerNode && method == "spawn" && !script_has_method(mgr, target, method) {
		SpawnerNode_Spawn(cast(^SpawnerNode)target, ctx)
		return true
	}
	if target.typeId == LevelGeneratorNode && method == "generate" && !script_has_method(mgr, target, method) {
		LevelGeneratorNode_Generate(cast(^LevelGeneratorNode)target, ctx)
		return true
	}
	return false
}

// Signal_HandlerName: default method name for a connection, Godot style
// ("on_<source>_<signal>", snake case).
Signal_HandlerName :: proc(sourceName, signal: string, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make(allocator)
	strings.write_string(&sb, "on_")
	prevLower := false
	for ch in sourceName {
		switch {
		case ch >= 'A' && ch <= 'Z':
			if prevLower do strings.write_byte(&sb, '_')
			strings.write_rune(&sb, ch + 32)
			prevLower = false
		case (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9'):
			strings.write_rune(&sb, ch)
			prevLower = true
		case:
			strings.write_byte(&sb, '_')
			prevLower = false
		}
	}
	fmt.sbprintf(&sb, "_%s", signal)
	return strings.to_string(sb)
}
