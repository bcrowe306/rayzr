package engine

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import lua "lua54"

// ============================================================================
// Declared signals: a project's own events on any node, next to the built-in
// ones (a Timer's timeout, an Area's body_entered). A signal has a name and
// one value (its name, a type hint, a description):
//
//   health_changed(health: number)  "Health went up or down"
//
// It is declared in one of three places:
//
//   - On a node (the Inspector's Signals section > Add Signal): the scene
//     saves it with the node, "signals": [{"name", "param", "type",
//     "description"}].
//   - On a custom node type (its document): in the type's defaults, so every
//     node of the type - and of the types built on it - has it. A node of the
//     type may declare more of its own; the type's stay the type's.
//   - In a script: `---@signal health_changed(health: number) Health went up`
//     lines; every node running the script (or one that `extends` it) has it.
//
// The same name declared twice is one signal: the type's, then the node's,
// then the script's description is the one shown. A declared signal is
// raised like any event - `self.node:emit("health_changed", 3)` calls
// on_health_changed, the Inspector's connections and every `connect`
// handler with (value, source). Emitting a name nothing declares still works
// but warns once per call site in the editor and debug builds.
// ============================================================================

Signal_Decl :: struct {
	name:        string,
	param:       string, // the value's name ("" = no value)
	type:        string, // its type hint: SIGNAL_TYPES ("" = any)
	description: string,
}

// The type hints a signal's value can have (Lua types).
SIGNAL_TYPES := [?]string{"any", "number", "integer", "string", "boolean", "node", "table", "Vec2"}

// Where a node's signal comes from.
Signal_Origin :: enum u8 {
	Builtin, // the node type's own (or every node's tree events)
	Type,    // its custom node type (or one that type builds on)
	Node,    // declared on the node
	Script,  // a ---@signal line of its script
}

Signal_Info :: struct {
	using decl: Signal_Decl,
	origin:     Signal_Origin,
	from:       string, // .Type: the type's .node.json; .Script: the script; else ""
	line:       int,    // .Script: the ---@signal line (1-based)
}

// Signal_IsValidName: lowercase letters, digits and underscores, starting
// with a letter or underscore (like the built-in events).
Signal_IsValidName :: proc(name: string) -> (ok: bool, problem: string) {
	if name == "" do return false, "a signal needs a name"
	if len(name) > 64 do return false, "64 characters at most"
	for ch, i in name {
		switch {
		case ch >= 'a' && ch <= 'z', ch == '_':
		case ch >= '0' && ch <= '9':
			if i == 0 do return false, "it can't start with a digit"
		case ch >= 'A' && ch <= 'Z':
			return false, "lowercase only (health_changed)"
		case:
			return false, "letters, digits and _ only"
		}
	}
	return true, ""
}

// Signal_IsValidParam: a Lua name for the value ("" = no value).
Signal_IsValidParam :: proc(name: string) -> bool {
	for ch, i in name {
		if !(ch == '_' || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (i > 0 && ch >= '0' && ch <= '9')) do return false
	}
	return true
}

// Signal_LuaType: a type hint as LuaLS spells it.
Signal_LuaType :: proc(t: string) -> string {
	switch t {
	case "", "any": return "any"
	case "node":    return "Node"
	}
	return t
}

Signal_DeclClone :: proc(d: Signal_Decl, allocator := context.allocator) -> Signal_Decl {
	return {
		name        = strings.clone(d.name, allocator),
		param       = strings.clone(d.param, allocator),
		type        = strings.clone(d.type, allocator),
		description = strings.clone(d.description, allocator),
	}
}

Signal_DeclDelete :: proc(d: Signal_Decl, allocator := context.allocator) {
	delete(d.name, allocator)
	delete(d.param, allocator)
	delete(d.type, allocator)
	delete(d.description, allocator)
}

// --- on a node ------------------------------------------------------------------------

// Node_FindOwnSignal: the index of a signal the node itself declares (-1).
Node_FindOwnSignal :: proc(node: ^Node, name: string) -> int {
	if node == nil do return -1
	for s, i in node.signals do if s.name == name do return i
	return -1
}

// Node_AddSignal declares a signal on the node (false: the name is taken by
// one it declares already).
Node_AddSignal :: proc(node: ^Node, d: Signal_Decl) -> bool {
	if node == nil || Node_FindOwnSignal(node, d.name) >= 0 do return false
	if node.signals == nil do node.signals = make([dynamic]Signal_Decl, node.allocator)
	append(&node.signals, Signal_DeclClone(d, node.allocator))
	return true
}

// Node_SetSignal replaces the node's own signal `name` (renamed, retyped) -
// its place in the list kept. false: no such signal.
Node_SetSignal :: proc(node: ^Node, name: string, d: Signal_Decl) -> bool {
	i := Node_FindOwnSignal(node, name)
	if i < 0 do return false
	node.signals[i] = Signal_DeclClone(d, node.allocator) // (the node's arena: the old strings go with it)
	return true
}

Node_RemoveSignal :: proc(node: ^Node, name: string) -> bool {
	i := Node_FindOwnSignal(node, name)
	if i < 0 do return false
	ordered_remove(&node.signals, i)
	return true
}

// Node_RenameConnections: the node's saved connections of signal `old` now
// of `new` (how many).
Node_RenameConnections :: proc(node: ^Node, old, new: string) -> int {
	if node == nil do return 0
	n := 0
	for &c in node.signalConnections do if c.signal == old {
		c.signal = strings.clone(new, node.allocator)
		n += 1
	}
	return n
}

// Node_RemoveConnectionsOf drops the node's saved connections of a signal.
Node_RemoveConnectionsOf :: proc(node: ^Node, signal: string) -> int {
	if node == nil do return 0
	n := 0
	for i := len(node.signalConnections) - 1; i >= 0; i -= 1 {
		if node.signalConnections[i].signal == signal && node.signalConnections[i].node == nil {
			ordered_remove(&node.signalConnections, i)
			n += 1
		}
	}
	return n
}

// --- JSON ------------------------------------------------------------------------------

// Signals_WriteJSON writes a list of signals as a JSON array.
Signals_WriteJSON :: proc(w: ^Json_Writer, list: []Signal_Decl) {
	strings.write_byte(&w.sb, '[')
	for s, i in list {
		if i > 0 do strings.write_string(&w.sb, ", ")
		strings.write_string(&w.sb, "{\"name\": ")
		Json_String(w, s.name)
		if s.param != "" {strings.write_string(&w.sb, ", \"param\": "); Json_String(w, s.param)}
		if s.type != "" && s.type != "any" {strings.write_string(&w.sb, ", \"type\": "); Json_String(w, s.type)}
		if s.description != "" {strings.write_string(&w.sb, ", \"description\": "); Json_String(w, s.description)}
		strings.write_byte(&w.sb, '}')
	}
	strings.write_byte(&w.sb, ']')
}

// Signals_FromJSON reads a "signals" array (bad entries skipped).
Signals_FromJSON :: proc(v: json.Value, allocator := context.temp_allocator) -> []Signal_Decl {
	out := make([dynamic]Signal_Decl, allocator)
	arr, ok := v.(json.Array)
	if !ok do return out[:]
	str :: proc(o: json.Object, k: string) -> string {s, _ := o[k].(json.String); return string(s)}
	for e in arr {
		o, isObj := e.(json.Object)
		if !isObj do continue
		d := Signal_Decl{str(o, "name"), str(o, "param"), str(o, "type"), str(o, "description")}
		if ok, _ := Signal_IsValidName(d.name); !ok do continue
		dup := false
		for x in out do if x.name == d.name do dup = true
		if dup do continue
		append(&out, Signal_DeclClone(d, allocator))
	}
	return out[:]
}

// --- in a script ------------------------------------------------------------------------

// Script_ParseSignals reads a script's `---@signal name(param: type) text`
// lines (also `---@signal name` and `---@signal name(param)`). Allocated
// with `allocator`; each one's line (1-based) in `lines` when given.
Script_ParseSignals :: proc(code: string, allocator := context.allocator, lines: ^[dynamic]int = nil) -> [dynamic]Signal_Decl {
	out := make([dynamic]Signal_Decl, allocator)
	rest := code
	lineNo := 0
	for len(rest) > 0 {
		line := rest
		if nl := strings.index_byte(rest, '\n'); nl >= 0 {
			line = rest[:nl]
			rest = rest[nl + 1:]
		} else {
			rest = ""
		}
		lineNo += 1
		d, ok := Script_ParseSignalLine(line)
		if !ok do continue
		dup := false
		for x in out do if x.name == d.name do dup = true
		if dup do continue
		append(&out, Signal_DeclClone(d, allocator))
		if lines != nil do append(lines, lineNo)
	}
	return out
}

// Script_ParseSignalLine: one `---@signal` line (temp strings: slices of it).
Script_ParseSignalLine :: proc(line: string) -> (d: Signal_Decl, ok: bool) {
	t := strings.trim_space(line)
	if !strings.has_prefix(t, "---@signal") do return {}, false
	t = t[len("---@signal"):]
	if len(t) == 0 || (t[0] != ' ' && t[0] != '\t') do return {}, false
	t = strings.trim_space(t)
	// The name: up to "(", a space or the end.
	end := len(t)
	for ch, i in t do if ch == '(' || ch == ' ' || ch == '\t' {end = i; break}
	d.name = t[:end]
	if valid, _ := Signal_IsValidName(d.name); !valid do return {}, false
	t = t[end:]
	if strings.has_prefix(t, "(") {
		close := strings.index_byte(t, ')')
		if close < 0 do return {}, false
		inside := strings.trim_space(t[1:close])
		t = t[close + 1:]
		if colon := strings.index_byte(inside, ':'); colon >= 0 {
			d.param = strings.trim_space(inside[:colon])
			d.type = strings.trim_space(inside[colon + 1:])
		} else {
			d.param = inside
		}
		if !Signal_IsValidParam(d.param) do return {}, false
		if d.type == "Node" do d.type = "node"
		if d.type == "any" do d.type = ""
	}
	d.description = strings.trim_space(t)
	return d, true
}

// Script_SignalLine: a signal as a script declares it.
Script_SignalLine :: proc(d: Signal_Decl, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make(allocator)
	fmt.sbprintf(&sb, "---@signal %s", d.name)
	if d.param != "" {
		if d.type != "" && d.type != "any" do fmt.sbprintf(&sb, "(%s: %s)", d.param, d.type)
		else do fmt.sbprintf(&sb, "(%s)", d.param)
	}
	if d.description != "" do fmt.sbprintf(&sb, " %s", d.description)
	return strings.to_string(sb)
}

// --- what a node has --------------------------------------------------------------------

// CustomNode_Signals: the signals a custom node type declares - the types it
// builds on first, then its own (temp). ownOnly: just its own.
CustomNode_Signals :: proc(t: ^CustomNodeType, ctx: ^GameContext, ownOnly := false) -> []Signal_Info {
	out := make([dynamic]Signal_Info, context.temp_allocator)
	chain := make([dynamic]^CustomNodeType, context.temp_allocator)
	for x, i := t, 0; x != nil && i < 16; i += 1 {
		inject_at(&chain, 0, x)
		if ownOnly || x.inherits == "" do break
		x, _ = CustomNode_Get(ctx, x.inherits)
	}
	for x in chain {
		val, err := json.parse(transmute([]u8)x.defaults, allocator = context.temp_allocator)
		if err != .None do continue
		obj, isObj := val.(json.Object)
		if !isObj do continue
		for d in Signals_FromJSON(obj["signals"]) {
			if signal_listed(out[:], d.name) do continue
			append(&out, Signal_Info{decl = d, origin = .Type, from = x.path})
		}
	}
	return out[:]
}

@(private = "file")
signal_listed :: proc(list: []Signal_Info, name: string) -> bool {
	for s in list do if s.name == name do return true
	return false
}

// script_module_of: the loaded module a node's script runs (nil).
@(private = "file")
script_module_of :: proc(node: ^Node) -> ^ScriptModule {
	if node == nil || node.scriptInstance == nil do return nil
	inst := cast(^ScriptInstance)node.scriptInstance
	mgr := inst.scriptManager
	if mgr == nil && node.gameContext != nil do mgr = node.gameContext.scriptManager
	if mgr == nil do mgr = &scriptManager
	mod, _ := mgr.modules[ScriptVFS_NormalizePath(inst.modulePath)]
	return mod
}

// Script_ModuleSignals: the signals a script declares, those of the script
// it extends after its own (temp).
Script_ModuleSignals :: proc(mod: ^ScriptModule, mgr: ^ScriptManager) -> []Signal_Info {
	out := make([dynamic]Signal_Info, context.temp_allocator)
	for m, depth := mod, 0; m != nil && depth < 16; depth += 1 {
		for s, i in m.signals {
			if signal_listed(out[:], s.name) do continue
			line := m.signalLines[i] if i < len(m.signalLines) else 0
			append(&out, Signal_Info{decl = s, origin = .Script, from = m.path, line = line})
		}
		if m.extends == "" || mgr == nil do break
		m = mgr.modules[m.extends] or_else nil
	}
	return out[:]
}

// Node_DeclaredSignals: the signals declared for a node - its type's, its
// own, its script's (a name once: the first) (temp). Not the built-in ones.
// typeDoc: the node is its type being edited (the editor's type document) -
// its own are the type's, so only the types it builds on count as the type's.
Node_DeclaredSignals :: proc(node: ^Node, typeDoc := false) -> []Signal_Info {
	out := make([dynamic]Signal_Info, context.temp_allocator)
	if node == nil do return out[:]
	if t := Node_CustomType(node); t != nil {
		from := t
		if typeDoc {
			from = nil
			if t.inherits != "" do from, _ = CustomNode_Get(node.gameContext, t.inherits)
		}
		if from != nil do for s in CustomNode_Signals(from, node.gameContext) do append(&out, s)
	}
	for s in node.signals {
		if signal_listed(out[:], s.name) do continue
		append(&out, Signal_Info{decl = s, origin = .Node})
	}
	if mod := script_module_of(node); mod != nil {
		mgr := (cast(^ScriptInstance)node.scriptInstance).scriptManager
		for s in Script_ModuleSignals(mod, mgr) {
			if signal_listed(out[:], s.name) do continue
			append(&out, s)
		}
	}
	return out[:]
}

// Node_Signals: every signal a node has - the built-in ones, then the
// declared ones (a declared name a built-in event already has is left out).
Node_Signals :: proc(node: ^Node, typeDoc := false) -> []Signal_Info {
	out := make([dynamic]Signal_Info, context.temp_allocator)
	if node == nil do return out[:]
	for ev in Node_EventNames(node) {
		append(&out, Signal_Info{decl = {name = ev.name, param = ev.param, description = ev.doc}, origin = .Builtin})
	}
	for s in Node_DeclaredSignals(node, typeDoc) do if !signal_listed(out[:], s.name) do append(&out, s)
	return out[:]
}

// Node_IsBuiltinEvent: a name the node's type raises itself.
Node_IsBuiltinEvent :: proc(node: ^Node, name: string) -> bool {
	for ev in Node_EventNames(node) do if ev.name == name do return true
	return false
}

// Node_HasSignal: a built-in event of the node or a signal declared for it.
Node_HasSignal :: proc(node: ^Node, name: string) -> bool {
	if Node_IsBuiltinEvent(node, name) do return true
	for s in Node_DeclaredSignals(node) do if s.name == name do return true
	return false
}

// Node_FindSignal: a signal of the node by name.
Node_FindSignal :: proc(node: ^Node, name: string) -> (Signal_Info, bool) {
	for s in Node_Signals(node) do if s.name == name do return s, true
	return {}, false
}

// script_module_set_signals: a module's ---@signal lines, read again.
script_module_set_signals :: proc(mod: ^ScriptModule, code: string) {
	for s in mod.signals do Signal_DeclDelete(s)
	delete(mod.signals)
	delete(mod.signalLines)
	mod.signalLines = make([dynamic]int)
	mod.signals = Script_ParseSignals(code, context.allocator, &mod.signalLines)
}

// --- emitting an undeclared name ----------------------------------------------------------

// Call sites already warned about ("name@script:line").
@(private = "file")
undeclaredSeen: map[string]bool

// Signal_WarnUndeclared: `emit` of a name the node doesn't declare - once
// per call site (editor, Play from the editor, debug builds).
Signal_WarnUndeclared :: proc(L: ^lua.State, node: ^Node, name: string) {
	lua.L_where(L, 1)
	site := strings.trim_right(string(lua.tostring(L, -1)), ": ")
	lua.pop(L, 1)
	if undeclaredSeen == nil do undeclaredSeen = make(map[string]bool, 16, Engine_HeapAllocator())
	key := fmt.tprintf("%s@%s", name, site)
	if key in undeclaredSeen || len(undeclaredSeen) > 1000 do return
	undeclaredSeen[strings.clone(key, Engine_HeapAllocator())] = true
	at := site if site != "" else "a script"
	Script_Problem(.Warning, "[Lua] %s: emit(\"%s\"): %s has no signal \"%s\" - declare it (Inspector > Signals > Add Signal, or ---@signal %s in its script)", at, name, node.name, name, name)
}

// Signal_ForgetWarnings: warn again (a new Play / script reload).
Signal_ForgetWarnings :: proc() {
	for k in undeclaredSeen do delete(k, Engine_HeapAllocator())
	clear(&undeclaredSeen)
}

// Signal_WarningCount: call sites warned about so far (tests).
Signal_WarningCount :: proc() -> int {return len(undeclaredSeen)}

// Node_DescribeSignal: a signal's value name, description and type hint
// (a declared one's, else the built-in event's).
Node_DescribeSignal :: proc(node: ^Node, name: string) -> (param, doc, type: string) {
	if node != nil {
		if s, ok := Node_FindSignal(node, name); ok do return s.param, s.description, s.type
	}
	param, doc = Event_Describe(name)
	if param == "value" && doc == "" do param = ""
	return
}
