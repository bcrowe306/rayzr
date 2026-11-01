package engine

import "base:runtime"
import "core:c"
import "core:time"
import lua "lua54"

// ============================================================================
// Lua Scripting Data Types & Property Definitions
// ============================================================================

ScriptPropertyType :: enum {
	Float,
	Int,
	String,
	Boolean,
	Color,
	Vector2,
}

ScriptValue :: struct {
	type:      ScriptPropertyType,
	valFloat:  f32,
	valInt:    i64,
	valString: string,
	valBool:   bool,
	valColor:  [4]f32,
	valVec2:   [2]f32,
}

ScriptProperty :: struct {
	name:       string,
	type:       ScriptPropertyType,
	defaultVal: ScriptValue,
	min:        f32,
	max:        f32,
	label:      string,
	// Asset reference properties (type = "texture", "audio", "scene",
	// "script", "component", "level", "file"): a project-relative path
	// (String value) that the Inspector edits with an asset picker. Also
	// "node" (a path from the script's node), "enum" (one of `values`), and
	// JSON lists: "array" (of `elem`), "curve" ({{t, v}, ...}), "gradient"
	// ({{t, r, g, b, a}, ...}) - Lua tables.
	assetKind:  string,
	values:     [dynamic]string, // enum choices
	elem:       string,          // array element type ("string", "float", "node", "texture"...)
	slider:     bool,            // a slider between min and max (type = "range" or slider = true)
	group:      string,          // Inspector group header
	tooltip:    string,          // Inspector help
	// type = "resource" (or an array of = "resource"): a .resource.json path,
	// the resource's table in Lua (script_resources.odin).
	resourceClass: string,             // `class`: the script its files must use ("" = any)
	resourceLocal: Resource_LocalMode, // `local_copy` on the property
}

// Resource_LocalMode: a resource property's `local_copy`.
Resource_LocalMode :: enum u8 {
	Default, // the class's `resource.local_copy`
	Shared,  // local_copy = false: the one shared table
	Local,   // local_copy = true: one copy per component instance
}

// Script_IsResourceProp: a property holding resources (one, or a list).
Script_IsResourceProp :: proc(p: ScriptProperty) -> bool {
	return p.assetKind == "resource" || (p.assetKind == "array" && p.elem == "resource")
}

// Script_IsJsonKind: a property kind stored as JSON text (a Lua table).
Script_IsJsonKind :: proc(kind: string) -> bool {return kind == "array" || kind == "curve" || kind == "gradient"}

ScriptProperty_Destroy :: proc(p: ^ScriptProperty) {
	delete(p.name)
	delete(p.label)
	if p.assetKind != "" do delete(p.assetKind)
	if p.type == .String && len(p.defaultVal.valString) > 0 do delete(p.defaultVal.valString)
	for v in p.values do delete(v)
	delete(p.values)
	delete(p.elem)
	delete(p.group)
	delete(p.tooltip)
	delete(p.resourceClass)
}

// ScriptValue_Equal: same type and value (strings by content).
ScriptValue_Equal :: proc(a, b: ScriptValue) -> bool {
	if a.type != b.type do return false
	switch a.type {
	case .Float:   return a.valFloat == b.valFloat
	case .Int:     return a.valInt == b.valInt
	case .Boolean: return a.valBool == b.valBool
	case .String:  return a.valString == b.valString
	case .Vector2: return a.valVec2 == b.valVec2
	case .Color:   return a.valColor == b.valColor
	}
	return true
}

ScriptModule :: struct {
	path:        string,
	properties:  [dynamic]ScriptProperty,
	isLoaded:    bool,
	diskPath:    string,    // file the module was loaded from ("" = embedded)
	modTime:     time.Time, // its modification time at the last (re)load
	// A resource class (script_resources.odin): the script sets
	// `Class.resource = { local_copy = bool }`.
	isResourceClass:   bool,
	resourceLocalCopy: bool, // its resources are local to each component instance by default
	// The script it builds on (`Class.extends`, normalized path; "" = none):
	// script_extends.odin.
	extends: string,
	// A Behavior Tree leaf (`Class.behavior = "action" / "condition"`;
	// "" = not one): behavior_tree_node.odin.
	behavior: string,
	// A GOAP script (`Class.goap = "action" / "sensor" / "goal"`): goap_node.odin.
	goap: string,
}

// Forward declaration of ScriptManager
ScriptManager :: struct {
	nodeMetaRef: c.int, // registry index of the "Engine.Node" metatable (push_node_meta)
	L:         ^lua.State,
	game:      ^Game,
	isReady:   bool,
	// The context it was made in (the engine's allocators, logger): Lua's C
	// callbacks run with it (Script_Context), so what scripts create is
	// freed by the allocator that made it.
	ctx:       runtime.Context,
	hasCtx:    bool,
	modules:   map[string]^ScriptModule,
	instances: [dynamic]^ScriptInstance,
	// Lua event connections (script_events.odin) and the instance whose
	// code is running (owner of new connections).
	connections:      [dynamic]Lua_Connection,
	nextConnectionId: int,
	currentInstance:  ^ScriptInstance,
	// While suspended (the editor, outside Simulate) events are not
	// dispatched to Lua.
	suspended:        bool,
	lastHotReloadCheck: time.Tick,
	hotReload:          bool, // poll script files and reload changed ones
	globals:            [dynamic]Global_Script, // loaded global scripts (script_globals.odin)
	// Live resource tables (script_resources.odin) and the one whose
	// on_load is running (its Resource.new copies share its scope).
	resources:          [dynamic]^ResourceInstance,
	loadingResource:    ^ResourceInstance,
}

ScriptInstance :: struct {
	node:          ^Node,
	scriptManager: ^ScriptManager,
	modulePath:    string,
	registryRef:   c.int, // Reference to self table in Lua LUA_REGISTRYINDEX
	properties:    map[string]ScriptValue,
	isReady:       bool,
	drawState:     u8,     // on_draw: 0 not looked up, 1 none, 2 defined (vector_canvas.odin)
	canvas:        rawptr, // ^Vector_Canvas: what on_draw draws
}
