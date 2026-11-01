package engine

import "base:runtime"
import "core:c"
import "core:log"
import "core:math"
import "core:strings"
import lua "lua54"

// ============================================================================
// Lua Script Manager & Instance Lifecycle Controller
// ============================================================================

scriptManager: ScriptManager

ScriptManager_Init :: proc(sm: ^ScriptManager = nil, game: ^Game = nil) -> bool {
	mgr := sm if sm != nil else &scriptManager
	if mgr.isReady do return true

	// Script logs use the logger the game runs with (script_bindings.odin).
	if scriptLogger.procedure == nil do scriptLogger = context.logger
	mgr.ctx, mgr.hasCtx = context, true
	mgr.L = lua.L_newstate()
	if mgr.L == nil {
		log.error("[ScriptManager] Failed to create Lua 5.4 state")
		return false
	}
	Script_SetManager(mgr.L, mgr) // (before anything runs: Script_Context reads it)
	mgr.nodeMetaRef = 0          // (a new state: its metatable gets a new registry index)

	lua.L_openlibs(mgr.L)

	ScriptVFS_Init()
	ScriptVFS_RegisterLuaSearcher(mgr.L)
	RegisterEngineLuaBindings(mgr.L, mgr)
	Lua_RegisterVectors(mgr.L) // Vec2 / Vec3 / Vec4
	_ = lua.L_dostring(mgr.L, LUA_CURVE_HELPERS)

	mgr.game = game
	mgr.modules = make(map[string]^ScriptModule)
	mgr.instances = make([dynamic]^ScriptInstance)
	mgr.isReady = true

	log.info("[ScriptManager] Lua 5.4 scripting engine successfully initialized")
	return true
}

// Curve / Gradient: sampling the values of curve and gradient script
// properties (points {t, v}, stops {t, r, g, b, a}; t in 0..1).
LUA_CURVE_HELPERS :: `
Curve = {}
function Curve.sample(points, t)
    local n = #points
    if n == 0 then return 0 end
    if t <= points[1][1] then return points[1][2] end
    for i = 2, n do
        local a, b = points[i - 1], points[i]
        if t <= b[1] then
            local span = b[1] - a[1]
            local f = span > 0 and (t - a[1]) / span or 0
            return a[2] + (b[2] - a[2]) * f
        end
    end
    return points[n][2]
end
Gradient = {}
function Gradient.sample(stops, t)
    local n = #stops
    if n == 0 then return 1, 1, 1, 1 end
    local function rgba(s) return s[2], s[3], s[4], s[5] or 1 end
    if t <= stops[1][1] then return rgba(stops[1]) end
    for i = 2, n do
        local a, b = stops[i - 1], stops[i]
        if t <= b[1] then
            local span = b[1] - a[1]
            local f = span > 0 and (t - a[1]) / span or 0
            local function mix(k, d) return (a[k] or d) + ((b[k] or d) - (a[k] or d)) * f end
            return mix(2, 1), mix(3, 1), mix(4, 1), mix(5, 1)
        end
    end
    return rgba(stops[n])
end
`

ScriptManager_Destroy :: proc(sm: ^ScriptManager = nil) {
	mgr := sm if sm != nil else &scriptManager
	if !mgr.isReady do return

	Script_ReleaseAllConnections(mgr)
	globals_clear(mgr)
	delete(mgr.globals)
	Resource_ClearAll(mgr)
	delete(mgr.resources)
	mgr.resources = nil

	// Destroy all active instances
	for len(mgr.instances) > 0 {
		inst := mgr.instances[0]
		ScriptInstance_Destroy(inst, mgr)
	}
	delete(mgr.instances)

	// Clean up cached modules
	for k, mod in mgr.modules {
		delete(k)
		delete(mod.diskPath)
		if mod.extends != "" do delete(mod.extends)
		if mod.behavior != "" do delete(mod.behavior)
		if mod.goap != "" do delete(mod.goap)
		for &p in mod.properties do ScriptProperty_Destroy(&p)
		delete(mod.properties)
		free(mod)
	}
	delete(mgr.modules)

	if mgr.L != nil {
		lua.close(mgr.L)
		mgr.L = nil
	}
	mgr.isReady = false
	log.info("[ScriptManager] Lua scripting engine terminated")
}

lua_traceback_error_handler :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	msg := lua.tostring(L, 1)
	lua.L_traceback(L, L, msg, 1)
	return 1
}

// Loads and compiles a Lua script module, parsing its exported properties
ScriptManager_LoadModule :: proc(path: string, sm: ^ScriptManager = nil) -> (^ScriptModule, bool) {
	mgr := sm if sm != nil else &scriptManager
	if !mgr.isReady {
		if !ScriptManager_Init(mgr) do return nil, false
	}

	normPath := ScriptVFS_NormalizePath(path)
	if existing, exists := mgr.modules[normPath]; exists {
		return existing, true
	}

	// Project scripts resolve through the asset manager first (project
	// directory or mounted .rayzr package), then the VFS / working directory.
	code, ok := "", false
	if mgr.game != nil {
		am := &mgr.game.assetManager
		rel := normPath
		if dir := strings.trim_suffix(am.projectDir, "/"); dir != "" && strings.has_prefix(rel, dir) && len(rel) > len(dir) && rel[len(dir)] == '/' {
			rel = rel[len(dir) + 1:]
		}
		code, ok = AssetManager_ReadFileString(am, rel)
	}
	if !ok do code, ok = ScriptVFS_Load(normPath)
	if !ok {
		log.errorf("[ScriptManager] Failed to find script file: %s", normPath)
		return nil, false
	}
	defer delete(code)

	L := mgr.L
	chunkNameC := strings.clone_to_cstring(strings.concatenate({"@", normPath}, context.temp_allocator), context.temp_allocator)
	codeC := raw_data(transmute([]u8)code)

	loadStatus := lua.L_loadbuffer(L, cast([^]u8)codeC, c.size_t(len(code)), chunkNameC)
	if loadStatus != .OK {
		errStr := lua.tostring(L, -1)
		Script_Problem(.Error, "[ScriptManager] Syntax error compiling '%s': %s", normPath, errStr)
		lua.pop(L, 1)
		return nil, false
	}

	// Execute chunk with pcall (0 args, 1 return value expected: the module table)
	pcallStatus := lua.pcall(L, 0, 1, 0)
	if pcallStatus != 0 {
		errStr := lua.tostring(L, -1)
		Script_Problem(.Error, "[ScriptManager] Runtime error loading '%s': %s", normPath, errStr)
		lua.pop(L, 1)
		return nil, false
	}

	if lua.type(L, -1) != .TABLE {
		log.warnf("[ScriptManager] Script '%s' did not return a table (got %s). Wrapping in empty table.", normPath, lua.typename(L, lua.type(L, -1)))
		lua.pop(L, 1)
		lua.newtable(L)
	}

	// Store module table in registry so it is not garbage collected
	moduleRefKey := strings.clone_to_cstring(strings.concatenate({"__Engine_Module_", normPath}, context.temp_allocator), context.temp_allocator)
	lua.setfield(L, lua.REGISTRYINDEX, moduleRefKey)

	mod := new(ScriptModule)
	mod.path = strings.clone(normPath)
	mod.properties = make([dynamic]ScriptProperty)
	mod.isLoaded = true

	// Retrieve module table to inspect its properties
	lua.getfield(L, lua.REGISTRYINDEX, moduleRefKey)
	script_extends_apply(mgr, mod, lua.gettop(L), true) // (`extends`: its base's methods and properties)
	delete(mod.properties)
	mod.properties = Script_ParseProperties(L, lua.gettop(L))
	mod.isResourceClass, mod.resourceLocalCopy = script_parse_resource_marker(L, lua.gettop(L), mod.path)
	if mod.isResourceClass do script_warn_resource_props(mod)
	Script_ParseBehaviorMarker(L, lua.gettop(L), mod)
	Script_ParseGoapMarker(L, lua.gettop(L), mod)
	lua.pop(L, 1) // module table
	ScriptModule_TrackFile(mgr, mod)


	mgr.modules[mod.path] = mod
	return mod, true
}

// Standalone reflection helper to inspect properties of a script file without attaching
Script_InspectProperties :: proc(scriptPath: string, sm: ^ScriptManager = nil) -> ([]ScriptProperty, bool) {
	mgr := sm if sm != nil else &scriptManager
	mod, ok := ScriptManager_LoadModule(scriptPath, mgr)
	if !ok do return nil, false
	return mod.properties[:], true
}

// Attaches a script module to an existing node, instantiating its Lua table & properties
Script_AttachToNode :: proc(node: ^Node, scriptPath: string, overrides: map[string]ScriptValue = nil, sm: ^ScriptManager = nil) -> ^ScriptInstance {
	if node == nil do return nil
	mgr := sm
	if mgr == nil && node.gameContext != nil {
		mgr = node.gameContext.scriptManager
	}
	if mgr == nil do mgr = &scriptManager
	if !mgr.isReady {
		if !ScriptManager_Init(mgr) do return nil
	}

	// Detach previous script if one was attached
	if node.scriptInstance != nil {
		ScriptInstance_Destroy(cast(^ScriptInstance)node.scriptInstance, mgr)
		node.scriptInstance = nil
	}

	mod, ok := ScriptManager_LoadModule(scriptPath, mgr)
	if !ok do return nil

	L := mgr.L

	// 1. Create instance table: `local self = {}`
	lua.newtable(L)
	instanceTableIdx := lua.gettop(L)

	// 2. Set self.node = node_userdata
	push_node_userdata(L, node)
	lua.setfield(L, instanceTableIdx, "node")

	// 3. Set metatable: setmetatable(self, { __index = moduleTable })
	normPath := ScriptVFS_NormalizePath(scriptPath)
	moduleRefKey := strings.clone_to_cstring(strings.concatenate({"__Engine_Module_", normPath}, context.temp_allocator), context.temp_allocator)

	lua.newtable(L) // metatable
	lua.getfield(L, lua.REGISTRYINDEX, moduleRefKey) // module table
	lua.setfield(L, -2, "__index")
	lua.setmetatable(L, instanceTableIdx)

	inst := new(ScriptInstance)
	inst.node = node
	inst.scriptManager = mgr
	inst.modulePath = strings.clone(normPath)
	inst.properties = make(map[string]ScriptValue)
	inst.isReady = false

	// 4. Initialize instance properties with defaults, applying any overrides
	script_apply_properties(L, instanceTableIdx, mod, overrides, &inst.properties)

	// 5. Save self table into registry to keep it alive
	inst.registryRef = lua.L_ref(L, lua.REGISTRYINDEX)

	node.scriptInstance = inst
	append(&mgr.instances, inst)

	// If node is already ready, invoke script ready immediately
	if node.isReady {
		ScriptInstance_CallReady(inst, mgr)
	}

	return inst
}

// Alias for Script_AttachToNode
Node_AttachScript :: Script_AttachToNode

// script_property_value: a declared property's starting value - its
// default, or the override (coerced to the declared type). Strings are
// cloned: the caller owns the result.
script_property_value :: proc(prop: ScriptProperty, overrides: map[string]ScriptValue) -> ScriptValue {
	val := prop.defaultVal
	if overrides != nil {
		if overrideVal, hasOverride := overrides[prop.name]; hasOverride {
			val = overrideVal
			// A list kept as JSON: the saved array's text (overrides read
			// short arrays as vectors / colours otherwise).
			if Script_IsJsonKind(prop.assetKind) {
				val = {type = .String, valString = overrideVal.valString if overrideVal.valString != "" else prop.defaultVal.valString}
			}
			// Numbers take the declared type (JSON has one number type:
			// an "int" property set to 3 in a scene is the integer 3).
			if prop.type == .Int && val.type == .Float do val = {type = .Int, valInt = i64(math.round(val.valFloat))}
			if prop.type == .Float && val.type == .Int do val = {type = .Float, valFloat = f32(val.valInt)}
		}
	}
	if val.type != .String do val.valString = "" // (a list override's text, temp)
	// The owner keeps its own strings (the default belongs to the module,
	// overrides are often temp-allocated): sharing them double-freed.
	if val.type == .String do val.valString = strings.clone(val.valString)
	return val
}

// script_apply_properties sets every property the module declares on the
// Lua table at tableIdx (default or override) and records the values in
// props (which owns its keys and strings). Node references and resources
// are set to nil: they are resolved before ready(), once the tree is built
// (and so edit mode never loads resources or runs their on_load).
script_apply_properties :: proc(L: ^lua.State, tableIdx: c.int, mod: ^ScriptModule, overrides: map[string]ScriptValue, props: ^map[string]ScriptValue) {
	for prop in mod.properties {
		val := script_property_value(prop, overrides)
		props[strings.clone(prop.name)] = val
		if val.type == .String && (prop.assetKind == "node" || Script_IsResourceProp(prop)) {
			lua.pushnil(L)
		} else {
			script_push_value(L, val, prop.assetKind)
		}
		lua.setfield(L, tableIdx, strings.clone_to_cstring(prop.name, context.temp_allocator))
	}
}

// script_push_value pushes a property value as its Lua value: JSON list
// kinds (array / curve / gradient) as tables, colours as {r, g, b, a},
// vectors as Vec2. Node references are the caller's (they need the owner).
script_push_value :: proc(L: ^lua.State, val: ScriptValue, assetKind: string) {
	switch val.type {
	case .Float:
		lua.pushnumber(L, lua.Number(val.valFloat))
	case .Int:
		lua.pushinteger(L, lua.Integer(val.valInt))
	case .String:
		if Script_IsJsonKind(assetKind) {
			Lua_PushJSONText(L, val.valString) // a list: a table
		} else {
			lua.pushstring(L, strings.clone_to_cstring(val.valString, context.temp_allocator))
		}
	case .Boolean:
		lua.pushboolean(L, b32(val.valBool))
	case .Color:
		lua.createtable(L, 4, 0)
		lua.pushnumber(L, lua.Number(val.valColor.r)); lua.rawseti(L, -2, 1)
		lua.pushnumber(L, lua.Number(val.valColor.g)); lua.rawseti(L, -2, 2)
		lua.pushnumber(L, lua.Number(val.valColor.b)); lua.rawseti(L, -2, 3)
		lua.pushnumber(L, lua.Number(val.valColor.a)); lua.rawseti(L, -2, 4)
	case .Vector2:
		Lua_PushVec2(L, val.valVec2) // a Vec2 (v.x / v[1])
	}
}

// script_prop_kind: a script property's kind (assetKind: "node", "enum",
// "array"..., "" for plain values).
script_prop_kind :: proc(inst: ^ScriptInstance, name: string, mgr: ^ScriptManager) -> string {
	mod, ok := mgr.modules[ScriptVFS_NormalizePath(inst.modulePath)]
	if !ok || mod == nil do return ""
	for p in mod.properties do if p.name == name do return p.assetKind
	return ""
}

// script_prop_decl: a script property's declaration (nil when unknown).
script_prop_decl :: proc(inst: ^ScriptInstance, name: string, mgr: ^ScriptManager) -> ^ScriptProperty {
	mod, ok := mgr.modules[ScriptVFS_NormalizePath(inst.modulePath)]
	if !ok || mod == nil do return nil
	for &p in mod.properties do if p.name == name do return &p
	return nil
}

// script_node_prop: whether a script property is a node reference.
script_node_prop :: proc(inst: ^ScriptInstance, name: string, mgr: ^ScriptManager) -> bool {
	mod, ok := mgr.modules[ScriptVFS_NormalizePath(inst.modulePath)]
	if !ok || mod == nil do return false
	for p in mod.properties do if p.name == name do return p.assetKind == "node"
	return false
}

// script_push_node_prop pushes the node a node property points at (nil
// when unset or missing - warned about).
@(private = "file")
script_push_node_prop :: proc(L: ^lua.State, inst: ^ScriptInstance, name, path: string) {
	if path == "" || inst.node == nil || inst.node.gameContext == nil || inst.node.gameContext.scene == nil {
		lua.pushnil(L)
		return
	}
	found := Node_ResolvePath(inst.node.gameContext.scene.manager, inst.node, path)
	if found == nil do Script_Problem(.Warning, "%s: property %s points at \"%s\", which %s doesn't have", inst.modulePath, name, path, inst.node.name)
	push_node_userdata(L, found)
}

// script_resolve_node_props sets self's node properties to their nodes
// (self at the top of the stack).
@(private = "file")
script_resolve_node_props :: proc(L: ^lua.State, inst: ^ScriptInstance, mgr: ^ScriptManager) {
	mod, ok := mgr.modules[ScriptVFS_NormalizePath(inst.modulePath)]
	if !ok || mod == nil do return
	for p in mod.properties {
		if p.assetKind != "node" do continue
		// A node already in self (set before ready(), e.g. by a spawner) stays (#231).
		name := strings.clone_to_cstring(p.name, context.temp_allocator)
		lua.getfield(L, -1, name)
		set := lua.type(L, -1) == .USERDATA
		lua.pop(L, 1)
		if set do continue
		script_push_node_prop(L, inst, p.name, (inst.properties[p.name] or_else {}).valString)
		lua.setfield(L, -2, strings.clone_to_cstring(p.name, context.temp_allocator))
	}
}

ScriptInstance_CallReady :: proc(inst: ^ScriptInstance, sm: ^ScriptManager = nil) {
	if inst == nil || inst.isReady do return
	mgr := sm
	if mgr == nil && inst.scriptManager != nil do mgr = inst.scriptManager
	if mgr == nil do mgr = &scriptManager
	if !mgr.isReady || mgr.L == nil do return

	L := mgr.L
	lua.pushcfunction(L, lua_traceback_error_handler)
	errHandler := lua.gettop(L)

	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef)) // push self
	script_resolve_node_props(L, inst, mgr) // self.<node property> = the node
	script_resolve_resource_props(L, inst, mgr, keepSet = true) // self.<resource property> = its table
	lua.getfield(L, -1, "ready")
	if lua.type(L, -1) == .FUNCTION {
		lua.pushvalue(L, -2) // pass self as first arg
		prev := mgr.currentInstance
		mgr.currentInstance = inst
		status := lua.pcall(L, 1, 0, errHandler)
		mgr.currentInstance = prev
		if status != 0 {
			errStr := lua.tostring(L, -1)
			Script_Problem(.Error, "[ScriptInstance] Error in ready() for '%s': %s", inst.modulePath, errStr)
			lua.pop(L, 1)
		}
	} else {
		lua.pop(L, 1) // pop non-function
	}

	lua.pop(L, 1) // pop self
	lua.pop(L, 1) // pop errHandler
	inst.isReady = true
}

ScriptInstance_CallUpdate :: proc(inst: ^ScriptInstance, deltaTime: f32, sm: ^ScriptManager = nil) {
	if inst == nil do return
	mgr := sm
	if mgr == nil && inst.scriptManager != nil do mgr = inst.scriptManager
	if mgr == nil do mgr = &scriptManager
	if !mgr.isReady || mgr.L == nil do return

	L := mgr.L
	lua.pushcfunction(L, lua_traceback_error_handler)
	errHandler := lua.gettop(L)

	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef)) // push self
	lua.getfield(L, -1, "update")
	if lua.type(L, -1) == .FUNCTION {
		lua.pushvalue(L, -2) // pass self as 1st arg
		lua.pushnumber(L, lua.Number(deltaTime)) // pass dt as 2nd arg
		prev := mgr.currentInstance
		mgr.currentInstance = inst
		status := lua.pcall(L, 2, 0, errHandler)
		mgr.currentInstance = prev
		if status != 0 {
			errStr := lua.tostring(L, -1)
			Script_Problem(.Error, "[ScriptInstance] Error in update() for '%s': %s", inst.modulePath, errStr)
			lua.pop(L, 1)
		}
	} else {
		lua.pop(L, 1)
	}

	lua.pop(L, 1) // pop self
	lua.pop(L, 1) // pop errHandler
}

ScriptInstance_CallDestroy :: proc(inst: ^ScriptInstance, sm: ^ScriptManager = nil) {
	if inst == nil do return
	mgr := sm
	if mgr == nil && inst.scriptManager != nil do mgr = inst.scriptManager
	if mgr == nil do mgr = &scriptManager
	if !mgr.isReady || mgr.L == nil do return

	L := mgr.L
	lua.pushcfunction(L, lua_traceback_error_handler)
	errHandler := lua.gettop(L)

	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef))
	lua.getfield(L, -1, "on_destroy")
	if lua.type(L, -1) == .FUNCTION {
		lua.pushvalue(L, -2) // pass self
		status := lua.pcall(L, 1, 0, errHandler)
		if status != 0 {
			errStr := lua.tostring(L, -1)
			Script_Problem(.Error, "[ScriptInstance] Error in on_destroy() for '%s': %s", inst.modulePath, errStr)
			lua.pop(L, 1)
		}
	} else {
		lua.pop(L, 1)
	}

	lua.pop(L, 1) // pop self
	lua.pop(L, 1) // pop errHandler
}

ScriptInstance_Destroy :: proc(inst: ^ScriptInstance, sm: ^ScriptManager = nil) {
	if inst == nil do return
	mgr := sm
	if mgr == nil && inst.scriptManager != nil do mgr = inst.scriptManager
	if mgr == nil do mgr = &scriptManager

	if inst.node != nil {
		inst.node.scriptInstance = nil
		inst.node = nil
	}

	ScriptInstance_CallDestroy(inst, mgr)
	Script_ForgetInstance(mgr, inst)

	if mgr.L != nil && inst.registryRef != 0 {
		lua.L_unref(mgr.L, lua.REGISTRYINDEX, inst.registryRef)
		inst.registryRef = 0
	}

	// Remove from instances list
	for i in 0..<len(mgr.instances) {
		if mgr.instances[i] == inst {
			unordered_remove(&mgr.instances, i)
			break
		}
	}

	Vector_Canvas_Destroy(cast(^Vector_Canvas)inst.canvas)
	inst.canvas = nil
	delete(inst.modulePath)
	for k, v in inst.properties {
		delete(k)
		if v.type == .String && len(v.valString) > 0 {
			delete(v.valString)
		}
	}
	delete(inst.properties)
	free(inst)
}

// Set property value live on a ScriptInstance (reactively updates Lua table and Odin cache)
ScriptInstance_SetProperty :: proc(inst: ^ScriptInstance, name: string, val: ScriptValue, sm: ^ScriptManager = nil) -> bool {
	if inst == nil do return false
	mgr := sm
	if mgr == nil && inst.scriptManager != nil do mgr = inst.scriptManager
	if mgr == nil do mgr = &scriptManager
	if !mgr.isReady || mgr.L == nil do return false

	L := mgr.L
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef)) // push self
	propNameC := strings.clone_to_cstring(name, context.temp_allocator)

	decl := script_prop_decl(inst, name, mgr)
	if val.type == .String && script_node_prop(inst, name, mgr) {
		script_push_node_prop(L, inst, name, val.valString)
	} else if val.type == .String && decl != nil && Script_IsResourceProp(decl^) {
		// Resolved once the script runs (ready); until then nil.
		if inst.isReady do script_push_resource_prop(L, mgr, inst, decl^, val.valString)
		else do lua.pushnil(L)
	} else {
		script_push_value(L, val, script_prop_kind(inst, name, mgr) if val.type == .String else "")
	}
	lua.setfield(L, -2, propNameC)
	lua.pop(L, 1) // pop self

	// Update cached property. Copy the new key/value *before* releasing the
	// old entry: callers commonly pass the map's own key string as `name`
	// (and possibly its old string value), which the release would free.
	key := strings.clone(name)
	newVal := val
	if newVal.type == .String {
		newVal.valString = strings.clone(val.valString)
	}
	if _, exists := inst.properties[key]; exists {
		oldKey, oldVal := delete_key(&inst.properties, key)
		if oldVal.type == .String && len(oldVal.valString) > 0 {
			delete(oldVal.valString)
		}
		delete(oldKey)
	}
	inst.properties[key] = newVal
	return true
}

// Get property value live from a ScriptInstance
ScriptInstance_GetProperty :: proc(inst: ^ScriptInstance, name: string) -> (ScriptValue, bool) {
	if inst == nil do return {}, false
	val, ok := inst.properties[name]
	return val, ok
}

// Script_ParseProperties reads a module table's `properties` declarations
// (module table at stack index `moduleIdx`). Stack is left unchanged.
Script_ParseProperties :: proc(L: ^lua.State, moduleIdx: c.int) -> [dynamic]ScriptProperty {
	props := make([dynamic]ScriptProperty)
	lua.getfield(L, moduleIdx, "properties")
	if lua.type(L, -1) == .TABLE {
		// Iterate through properties table
		lua.pushnil(L)
		for lua.next(L, -2) != 0 {
			// key is at -2, value (property spec table) is at -1
			propNameC := lua.tostring(L, -2)
			if propNameC != nil && lua.type(L, -1) == .TABLE {
				prop := ScriptProperty{
					name = strings.clone(string(propNameC)),
				}

				// 1. Property Type
				lua.getfield(L, -1, "type")
				typeStr := lua.tostring(L, -1)
				if typeStr != nil {
					switch string(typeStr) {
					case "float", "number": prop.type = .Float
					case "int", "integer":  prop.type = .Int
					case "string":          prop.type = .String
					case "bool", "boolean": prop.type = .Boolean
					case "color":           prop.type = .Color
					case "vector2", "vec2": prop.type = .Vector2
					case "range":           prop.type = .Float; prop.slider = true
					case "enum", "array", "curve", "gradient":
						prop.type = .String
						prop.assetKind = strings.clone(string(typeStr))
					case "texture", "audio", "scene", "script", "component", "level", "file", "node", "resource":
						// Asset paths - and node references ("node": a path from
						// the script's node, the node itself in Lua) and resources
						// (a .resource.json path, its table in Lua).
						prop.type = .String
						prop.assetKind = strings.clone(string(typeStr))
					case:                   prop.type = .Float
					}
				}
				lua.pop(L, 1)

				// 2. Default Value
				lua.getfield(L, -1, "default")
				prop.defaultVal.type = prop.type
				switch prop.type {
				case .Float:
					prop.defaultVal.valFloat = f32(lua.tonumber(L, -1))
				case .Int:
					prop.defaultVal.valInt = i64(lua.tointeger(L, -1))
				case .String:
					if Script_IsJsonKind(prop.assetKind) {
						// A list: kept as JSON (pushed to Lua as a table).
						json_text := lua_to_json(L, -1) if lua.type(L, -1) == .TABLE else ""
						if json_text == "" {
							switch prop.assetKind {
							case "curve":    json_text = "[[0, 0], [1, 1]]"
							case "gradient": json_text = "[[0, 1, 1, 1, 1], [1, 1, 1, 1, 1]]"
							case:            json_text = "[]"
							}
						}
						prop.defaultVal.valString = strings.clone(json_text)
					} else if sC := lua.tostring(L, -1); sC != nil {
						prop.defaultVal.valString = strings.clone(string(sC))
					}
				case .Boolean:
					prop.defaultVal.valBool = bool(lua.toboolean(L, -1))
				case .Color:
					if lua.type(L, -1) == .TABLE {
						lua.rawgeti(L, -1, 1); prop.defaultVal.valColor.r = f32(lua.tonumber(L, -1)); lua.pop(L, 1)
						lua.rawgeti(L, -1, 2); prop.defaultVal.valColor.g = f32(lua.tonumber(L, -1)); lua.pop(L, 1)
						lua.rawgeti(L, -1, 3); prop.defaultVal.valColor.b = f32(lua.tonumber(L, -1)); lua.pop(L, 1)
						lua.rawgeti(L, -1, 4); prop.defaultVal.valColor.a = f32(lua.tonumber(L, -1)); lua.pop(L, 1)
					}
				case .Vector2:
					if lua.type(L, -1) == .TABLE {
						lua.rawgeti(L, -1, 1); prop.defaultVal.valVec2.x = f32(lua.tonumber(L, -1)); lua.pop(L, 1)
						lua.rawgeti(L, -1, 2); prop.defaultVal.valVec2.y = f32(lua.tonumber(L, -1)); lua.pop(L, 1)
					}
				}
				lua.pop(L, 1)

				// 3. Min / Max
				lua.getfield(L, -1, "min")
				if lua.isnumber(L, -1) {
					prop.min = f32(lua.tonumber(L, -1))
				}
				lua.pop(L, 1)

				lua.getfield(L, -1, "max")
				if lua.isnumber(L, -1) {
					prop.max = f32(lua.tonumber(L, -1))
				}
				lua.pop(L, 1)

				// Enum values, array element type, slider, group, tooltip.
				lua.getfield(L, -1, "values")
				if lua.type(L, -1) == .TABLE {
					for i in 1 ..= int(lua.rawlen(L, -1)) {
						lua.rawgeti(L, -1, lua.Integer(i))
						if v := lua.tostring(L, -1); v != nil do append(&prop.values, strings.clone(string(v)))
						lua.pop(L, 1)
					}
				}
				lua.pop(L, 1)
				if prop.assetKind == "enum" && prop.defaultVal.valString == "" && len(prop.values) > 0 {
					prop.defaultVal.valString = strings.clone(prop.values[0])
				}
				str_field :: proc(L: ^lua.State, key: cstring) -> string {
					lua.getfield(L, -1, key)
					defer lua.pop(L, 1)
					if lua.type(L, -1) == .STRING do return strings.clone(string(lua.tostring(L, -1)))
					return ""
				}
				prop.elem = str_field(L, "of")
				if prop.assetKind == "array" && prop.elem == "" do prop.elem = strings.clone("string")
				prop.group = str_field(L, "group")
				prop.tooltip = str_field(L, "tooltip")
				prop.resourceClass = str_field(L, "class")
				lua.getfield(L, -1, "local_copy")
				if lua.type(L, -1) == .BOOLEAN do prop.resourceLocal = .Local if lua.toboolean(L, -1) else .Shared
				lua.pop(L, 1)
				lua.getfield(L, -1, "slider")
				if lua.toboolean(L, -1) do prop.slider = true
				lua.pop(L, 1)

				// 4. Label / Tooltip
				lua.getfield(L, -1, "label")
				lblC := lua.tostring(L, -1)
				if lblC != nil {
					prop.label = strings.clone(string(lblC))
				}
				lua.pop(L, 1)

				append(&props, prop)
			}
			lua.pop(L, 1) // pop value, keep key for next iteration
		}
	}
	lua.pop(L, 1) // properties value
	return props
}

// Script_SetManager ties a Lua state to its script manager: in the state's
// extra space (read on every engine call: one load, where a registry lookup
// by name cost ~0.08 us; coroutines copy it from the main thread when
// created) and in the registry. Call right after creating the state (Lua
// doesn't clear the extra space).
Script_SetManager :: proc(L: ^lua.State, mgr: ^ScriptManager) {
	(cast(^rawptr)lua.getextraspace(L))^ = mgr
	lua.pushlightuserdata(L, mgr)
	lua.setfield(L, lua.REGISTRYINDEX, "__Engine_ScriptManager")
}

// Script_Manager: the state's script manager (Script_SetManager).
Script_Manager :: #force_inline proc "contextless" (L: ^lua.State) -> ^ScriptManager {
	return (cast(^^ScriptManager)lua.getextraspace(L))^
}

// Script_Context: the context a Lua C callback runs with - its script
// manager's (Script_Init's: the engine's allocators and logger), else the
// default one. `context = Script_Context(L)` at the top of every binding.
Script_Context :: proc "contextless" (L: ^lua.State) -> runtime.Context {
	if mgr := Script_Manager(L); mgr != nil && mgr.hasCtx do return mgr.ctx
	return Engine_DefaultContext()
}
