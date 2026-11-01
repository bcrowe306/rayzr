package engine

import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"
import lua "lua54"

// ============================================================================
// Resources: data assets whose behaviour comes from Lua (engine/docs/resources.md).
//
// A class is a script marked `Class.resource = { local_copy = bool }` with
// `properties` and methods. An instance is a file
//
//   resources/sword.resource.json
//   {"type": "resource", "script": "scripts/weapon.lua", "properties": {"damage": 25}}
//
// that loads as a Lua table: its property values as fields, `resource_path`,
// and the class's methods (then ResourceBase's: duplicate) through its
// metatable. on_load(self) runs once per table, after the values are set.
//
//   Resource.load(path)  the shared table (one per file)
//   Resource.new(path)   a fresh table owned by the calling script's scope
//   res:duplicate()      a copy of res as it is now (same scope rule)
//
// A scope is the node a copy belongs to: the nearest component instance
// root above the script's node, else the tree's root (Resource_ScopeOf).
// Its copies are released when that node is destroyed. Shared tables last
// until the script manager resets (Simulate stop, shutdown).
// Changes made at runtime are never written back to the file. Saving the
// file re-applies its changed values to every live table (hot reload).
// ============================================================================

ResourceInstance :: struct {
	path:        string,                 // project-relative .resource.json (normalized)
	modulePath:  string,                 // the class script
	scope:       rawptr,                 // ^Node owning it (released with it); nil = the manager
	cached:      bool,                   // the one Resource_Load returns for (scope, path)
	properties:  map[string]ScriptValue, // the values applied from the file (not runtime writes)
	registryRef: c.int,                  // the Lua table
	diskPath:    string,                 // for hot reload ("" = embedded / packaged)
	modTime:     time.Time,
	overrides:   map[string]ScriptValue, // per-instance values over the file's (kept on hot reload; #266)
	embedded:    bool,                   // its values are in a scene / another resource, not a file
}

// Resource_File: a .resource.json as read (temp allocated). values are the
// file's raw values (script_property_value coerces them to a declaration);
// raw is every value's JSON text (kept for keys the class doesn't declare).
Resource_File :: struct {
	script: string,
	values: map[string]ScriptValue,
	raw:    map[string]string,
}

RESOURCE_EXT :: ".resource.json"

@(private = "file") RES_BASE_KEY :: "__Engine_ResourceBase"
@(private = "file") RES_SET_KEY :: "__Engine_ResourceTables"   // weak set of resource tables
@(private = "file") RES_META_KEY :: "__Engine_ResourceMetaOf"  // fn(module) -> metatable
@(private = "file") RES_COPY_KEY :: "__Engine_ResourceCopy"    // fn(table) -> deep copy

// Helpers run in Lua: the metatable (the class first, then ResourceBase) and
// the deep copy for duplicate (other resources stay shared references).
@(private = "file")
RESOURCE_LUA :: `
local Base, IsRes = ...
local getmt = debug and debug.getmetatable or getmetatable
local function meta(module)
    return {__index = function(_, k)
        local v = module[k]
        if v == nil then v = Base[k] end
        return v
    end}
end
local function copy(src)
    local seen = {}
    local function deep(v)
        if type(v) ~= "table" or IsRes[v] then return v end
        local c = seen[v]
        if c then return c end
        c = {}
        seen[v] = c
        for k, x in next, v do c[deep(k)] = deep(x) end
        local mt = getmt(v)
        if type(mt) == "table" then setmetatable(c, mt) end
        return c
    end
    local out = {}
    seen[src] = out
    for k, x in next, src do out[k] = deep(x) end
    return out
end
return meta, copy
`

// Script_RegisterResourceModule creates the global Resource table and the
// registry helpers (called from RegisterEngineLuaBindings).
Script_RegisterResourceModule :: proc(L: ^lua.State) {
	// ResourceBase: what every resource has after its class's methods.
	lua.newtable(L)
	lua.pushcfunction(L, lua_resource_duplicate)
	lua.setfield(L, -2, "duplicate")
	lua.pushvalue(L, -1)
	lua.setfield(L, lua.REGISTRYINDEX, RES_BASE_KEY)
	// The resource tables (weak keys: a released one goes with the GC).
	lua.newtable(L)
	lua.newtable(L)
	lua.pushstring(L, "k")
	lua.setfield(L, -2, "__mode")
	lua.setmetatable(L, -2)
	lua.pushvalue(L, -1)
	lua.setfield(L, lua.REGISTRYINDEX, RES_SET_KEY)
	// stack: Base, IsRes
	if lua.L_loadstring(L, RESOURCE_LUA) != .OK {
		Script_Problem(.Error, "[Resource] helpers: %s", lua.tostring(L, -1))
		lua.pop(L, 3)
	} else {
		lua.insert(L, -3) // chunk, Base, IsRes
		if lua.pcall(L, 2, 2, 0) != 0 {
			Script_Problem(.Error, "[Resource] helpers: %s", lua.tostring(L, -1))
			lua.pop(L, 1)
		} else {
			lua.setfield(L, lua.REGISTRYINDEX, RES_COPY_KEY)
			lua.setfield(L, lua.REGISTRYINDEX, RES_META_KEY)
		}
	}

	lua.newtable(L)
	lua.pushcfunction(L, lua_resource_load)
	lua.setfield(L, -2, "load")
	lua.pushcfunction(L, lua_resource_new)
	lua.setfield(L, -2, "new")
	lua.setglobal(L, "Resource")
}

// --- class marker -----------------------------------------------------------------

// script_parse_resource_marker reads `resource` from a module table (at idx).
script_parse_resource_marker :: proc(L: ^lua.State, idx: c.int, modPath: string) -> (isClass, localCopy: bool) {
	idx := lua.absindex(L, idx)
	lua.getfield(L, idx, "resource")
	defer lua.pop(L, 1)
	#partial switch lua.type(L, -1) {
	case .NIL:
		return false, false
	case .TABLE:
		lua.getfield(L, -1, "local_copy")
		localCopy = bool(lua.toboolean(L, -1))
		lua.pop(L, 1)
		return true, localCopy
	}
	Script_Problem(.Warning, "[Resource] %s: `resource` must be a table ({{ local_copy = true / false }}); not a resource class", modPath)
	return false, false
}

// script_warn_resource_props: node properties mean nothing on a resource.
// (Resources inside resources work: resource_resolve_nested, #266.)
script_warn_resource_props :: proc(mod: ^ScriptModule) {
	for p in mod.properties {
		if p.assetKind == "node" || (p.assetKind == "array" && p.elem == "node") {
			Script_Problem(.Warning, "[Resource] %s: property %s is a node reference; a resource has no node (ignored)", mod.path, p.name)
		}
	}
}

// --- a resource property's value (#266) --------------------------------------------
//
//   "resources/sword.resource.json"                         the file
//   {"path": "resources/sword.resource.json", "properties": {"damage": 40}}
//                                 a copy of the file with these values on top
//                                 (the file's other values still hot-reload)
//   {"class": "scripts/weapon.lua", "properties": {...}}    embedded: no file

Resource_Value_Kind :: enum u8 {None, Path, Override, Embedded}

// Resource_IsObjectValue: an embedded / per-instance value (JSON object text).
Resource_IsObjectValue :: proc(value: string) -> bool {
	return strings.has_prefix(strings.trim_left_space(value), "{")
}

// Resource_CanonicalValue: an object value's JSON in a fixed order - "path"
// / "class" first, then "properties", keys sorted at every level - so
// saved scenes don't change from run to run.
Resource_CanonicalValue :: proc(v: json.Value, allocator := context.allocator) -> string {
	sb := strings.builder_make(context.temp_allocator)
	json_sorted(&sb, v, true)
	return strings.clone(strings.to_string(sb), allocator)
}

@(private = "file")
json_sorted :: proc(sb: ^strings.Builder, v: json.Value, top := false) {
	#partial switch x in v {
	case json.Object:
		keys := make([dynamic]string, context.temp_allocator)
		for k in x do append(&keys, k)
		rank :: proc(k: string) -> int {return 0 if k == "path" || k == "class" else 1 if k == "properties" else 2}
		if top do slice.sort_by(keys[:], proc(a, b: string) -> bool {
			ra, rb := rank(a), rank(b)
			return ra < rb if ra != rb else a < b
		})
		else do slice.sort(keys[:])
		strings.write_byte(sb, '{')
		for k, i in keys {
			if i > 0 do strings.write_string(sb, ", ")
			fmt.sbprintf(sb, "%q: ", k)
			child := x[k]
			// (an embedded resource inside: its own fixed order)
			_, isObj := child.(json.Object)
			json_sorted(sb, child, isObj && k != "properties")
		}
		strings.write_byte(sb, '}')
	case json.Array:
		strings.write_byte(sb, '[')
		for item, i in x {
			if i > 0 do strings.write_string(sb, ", ")
			json_sorted(sb, item)
		}
		strings.write_byte(sb, ']')
	case:
		strings.write_string(sb, string(Json_Compact(v)))
	}
}

// Resource_ParseValue reads a resource property's value (temp allocated).
Resource_ParseValue :: proc(value: string) -> (kind: Resource_Value_Kind, path, class: string, values: map[string]ScriptValue) {
	v := strings.trim_space(value)
	if v == "" do return .None, "", "", nil
	if !Resource_IsObjectValue(v) do return .Path, v, "", nil
	parsed, err := json.parse(transmute([]u8)v, allocator = context.temp_allocator)
	obj, ok := parsed.(json.Object)
	if err != .None || !ok do return .None, "", "", nil
	if props, has := obj["properties"].(json.Object); has do values = parse_script_overrides(props, context.temp_allocator)
	else do values = make(map[string]ScriptValue, allocator = context.temp_allocator)
	if p, has := obj["path"].(json.String); has && p != "" do return .Override, string(p), "", values
	if c, has := obj["class"].(json.String); has && c != "" do return .Embedded, "", string(c), values
	return .None, "", "", nil
}

// Resource_ValueText: a resource property's value for an override / an
// embedded resource (values: what's set; for an override only the changed ones).
Resource_ValueText :: proc(kind: Resource_Value_Kind, pathOrClass: string, values: map[string]ScriptValue, mod: ^ScriptModule, allocator := context.allocator) -> string {
	switch kind {
	case .None, .Path: return strings.clone(pathOrClass, allocator)
	case .Override: return strings.clone(fmt.tprintf(`{{"path": %q, "properties": %s}}`, pathOrClass, resource_override_text(values, mod)), allocator)
	case .Embedded: return strings.clone(fmt.tprintf(`{{"class": %q, "properties": %s}}`, pathOrClass, resource_override_text(values, mod)), allocator)
	}
	return ""
}

@(private = "file")
resource_override_text :: proc(values: map[string]ScriptValue, mod: ^ScriptModule) -> string {
	// Every given value (they're the overrides), as the file writer writes them.
	keys := make([dynamic]string, context.temp_allocator)
	for k in values do append(&keys, k)
	slice.sort(keys[:])
	sb := strings.builder_make(context.temp_allocator)
	strings.write_byte(&sb, '{')
	for k, i in keys {
		if i > 0 do strings.write_string(&sb, ", ")
		fmt.sbprintf(&sb, "%q: ", k)
		kind := ""
		if mod != nil do for p in mod.properties do if p.name == k do kind = p.assetKind
		strings.write_string(&sb, script_value_json_text(values[k], kind))
	}
	strings.write_byte(&sb, '}')
	return strings.to_string(sb)
}

// script_value_json_text: one value as JSON (lists and resource objects raw).
script_value_json_text :: proc(v: ScriptValue, kind: string) -> string {
	switch v.type {
	case .Float:   return fmt.tprintf("%g", v.valFloat)
	case .Int:     return fmt.tprintf("%d", v.valInt)
	case .Boolean: return "true" if v.valBool else "false"
	case .Vector2: return fmt.tprintf("[%g, %g]", v.valVec2.x, v.valVec2.y)
	case .Color:   return fmt.tprintf("[%g, %g, %g, %g]", v.valColor[0], v.valColor[1], v.valColor[2], v.valColor[3])
	case .String:
		if (Script_IsJsonKind(kind) || Resource_IsObjectValue(v.valString)) && v.valString != "" do return v.valString
		return fmt.tprintf("%q", v.valString)
	}
	return "null"
}

// --- resource properties of node scripts ------------------------------------------

// Script_ResolveResource: the table a node script's resource property gets
// for a path - shared, or the copy of the script's scope when the property
// (or else the class) says local_copy. nil for "", a problem (reported) or
// a file of another class than the property's `class`.
Script_ResolveResource :: proc(mgr: ^ScriptManager, inst: ^ScriptInstance, prop: ScriptProperty, path: string) -> ^ResourceInstance {
	scope: rawptr = Resource_ScopeOf(inst.node) if inst.node != nil else nil
	return Resource_Resolve(mgr, inst.modulePath, prop, path, scope, inst.node)
}

// Resource_Resolve: the table a resource property's value gets (`owner`
// names the script for problems; `scope`: where copies belong). A file is
// shared unless local_copy says a copy (one per scope); per-instance values
// and embedded resources are always the property's own copy (owned by
// `node`'s scope, else `scope`).
Resource_Resolve :: proc(mgr: ^ScriptManager, owner: string, prop: ScriptProperty, value: string, scope: rawptr, node: ^Node = nil) -> ^ResourceInstance {
	kind, path, class, values := Resource_ParseValue(value)
	switch kind {
	case .None:
		if strings.trim_space(value) != "" do Script_Problem(.Warning, "%s: property %s: not a resource value: %s", owner, prop.name, value)
		return nil
	case .Path, .Override:
		file, ok := Resource_ReadFile(mgr, path)
		if !ok {
			Script_Problem(.Warning, "%s: property %s: can't load %s", owner, prop.name, path)
			return nil
		}
		if prop.resourceClass != "" && !Resource_ClassMatches(prop.resourceClass, file.script) {
			Script_Problem(.Warning, "%s: property %s takes %s resources; %s is a %s", owner, prop.name, prop.resourceClass, path, file.script)
			return nil
		}
		mod, _ := ScriptManager_LoadModule(file.script, mgr)
		if kind == .Override {
			merged := make(map[string]ScriptValue, allocator = context.temp_allocator)
			for k, v in file.values do merged[k] = v
			for k, v in values do merged[k] = v
			return resource_create(mgr, mod, ScriptVFS_NormalizePath(path), merged, scope, false, values, false)
		}
		localCopy := prop.resourceLocal == .Local || (prop.resourceLocal == .Default && mod != nil && mod.resourceLocalCopy)
		return Resource_Load(mgr, path, scope if localCopy else nil, true)
	case .Embedded:
		if prop.resourceClass != "" && !Resource_ClassMatches(prop.resourceClass, class) {
			Script_Problem(.Warning, "%s: property %s takes %s resources; its embedded one is a %s", owner, prop.name, prop.resourceClass, class)
			return nil
		}
		mod, ok := ScriptManager_LoadModule(class, mgr)
		if !ok {
			Script_Problem(.Warning, "%s: property %s: its embedded resource's class %s could not be loaded", owner, prop.name, class)
			return nil
		}
		return resource_create(mgr, mod, "", values, scope, false, nil, true)
	}
	return nil
}

// script_push_resource_prop pushes a resource property's Lua value: the
// resource's table, or for a list (of = "resource") a table of them
// (holes where an item has a problem).
script_push_resource_prop :: proc(L: ^lua.State, mgr: ^ScriptManager, inst: ^ScriptInstance, prop: ScriptProperty, value: string) {
	if prop.assetKind != "array" {
		Resource_Push(L, Script_ResolveResource(mgr, inst, prop, value))
		return
	}
	val, err := json.parse(transmute([]u8)value, allocator = context.temp_allocator)
	items, _ := val.(json.Array)
	lua.createtable(L, c.int(len(items)), 0)
	if err != .None do return
	for item, i in items {
		path, _ := item.(json.String)
		res := Script_ResolveResource(mgr, inst, prop, string(path))
		if res == nil do continue
		Resource_Push(L, res)
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
}

// script_resolve_resource_props sets self's resource properties to their
// tables (self at the top of the stack; before ready()).
// keepSet (ready): a resource table already in self - set by a spawner or
// another script before ready() - stays; the saved value is its default (#231).
script_resolve_resource_props :: proc(L: ^lua.State, inst: ^ScriptInstance, mgr: ^ScriptManager, keepSet := false) {
	mod, ok := mgr.modules[ScriptVFS_NormalizePath(inst.modulePath)]
	if !ok || mod == nil do return
	for p in mod.properties {
		if !Script_IsResourceProp(p) do continue
		if keepSet {
			name := strings.clone_to_cstring(p.name, context.temp_allocator)
			lua.getfield(L, -1, name)
			set := lua.type(L, -1) == .TABLE
			lua.pop(L, 1)
			if set do continue
		}
		script_push_resource_prop(L, mgr, inst, p, (inst.properties[p.name] or_else {}).valString)
		lua.setfield(L, -2, strings.clone_to_cstring(p.name, context.temp_allocator))
	}
}

// --- files ------------------------------------------------------------------------

// Resource_IsPath: a resource file name.
Resource_IsPath :: proc(path: string) -> bool {
	return strings.has_suffix(strings.to_lower(path, context.temp_allocator), RESOURCE_EXT)
}

// Resource_ReadFile reads and checks a .resource.json (temp allocated).
// Problems are reported (Script_Problem) and give ok = false.
Resource_ReadFile :: proc(mgr: ^ScriptManager, path: string) -> (file: Resource_File, ok: bool) {
	norm := ScriptVFS_NormalizePath(path)
	text: string
	found := false
	if mgr != nil && mgr.game != nil {
		text, found = AssetManager_ReadFileString(&mgr.game.assetManager, norm, context.temp_allocator)
	}
	if !found do text, found = ScriptVFS_Load(norm, context.temp_allocator)
	if !found {
		Script_Problem(.Warning, "[Resource] %s: file not found", norm)
		return
	}
	return Resource_ParseText(norm, text)
}

// Resource_ParseText parses a resource file's text (temp allocated);
// problems are reported unless quiet.
Resource_ParseText :: proc(path, text: string, quiet := false) -> (file: Resource_File, ok: bool) {
	val, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	obj, isObj := val.(json.Object)
	if err != .None || !isObj {
		if !quiet do Script_Problem(.Warning, "[Resource] %s: not a resource file (invalid JSON)", path)
		return
	}
	if t, has := obj["type"]; has {
		if s, isStr := t.(json.String); !isStr || s != "resource" {
			if !quiet do Script_Problem(.Warning, "[Resource] %s: \"type\" is not \"resource\"", path)
			return
		}
	}
	script, isStr := obj["script"].(json.String)
	if !isStr || script == "" {
		if !quiet do Script_Problem(.Warning, "[Resource] %s: no \"script\" (its class)", path)
		return
	}
	file.script = string(script)
	file.raw = make(map[string]string, allocator = context.temp_allocator)
	if props, has := obj["properties"].(json.Object); has {
		file.values = parse_script_overrides(props, context.temp_allocator)
		for k, v in props do file.raw[k] = Json_Compact(v)
	} else {
		file.values = make(map[string]ScriptValue, allocator = context.temp_allocator)
	}
	return file, true
}

// Resource_FileText is a resource file's JSON: the values that differ from
// the class's defaults (a changed default still reaches every file that
// doesn't set it), plus `extra` - raw JSON of keys the class doesn't
// declare (kept, not lost). Keys are sorted.
Resource_FileText :: proc(script: string, values: map[string]ScriptValue, mod: ^ScriptModule, extra: map[string]string = nil, allocator := context.allocator) -> string {
	Entry :: struct {key: string, val: ScriptValue, kind, raw: string}
	entries := make([dynamic]Entry, context.temp_allocator)
	if mod != nil {
		for p in mod.properties {
			v, has := values[p.name]
			if !has || ScriptValue_Equal(v, p.defaultVal) do continue
			append(&entries, Entry{key = p.name, val = v, kind = p.assetKind})
		}
	}
	for k, raw in extra {

		declared := false
		if mod != nil do for p in mod.properties do if p.name == k do declared = true
		if !declared do append(&entries, Entry{key = k, raw = raw})
	}
	slice.sort_by(entries[:], proc(a, b: Entry) -> bool {return a.key < b.key})

	w := Json_Writer{sb = strings.builder_make(context.temp_allocator)}
	strings.write_byte(&w.sb, '{')
	w.indent = 1
	first := true
	Json_Key(&w, "type", &first); Json_String(&w, "resource")
	Json_Key(&w, "script", &first); Json_String(&w, script)
	Json_Key(&w, "properties", &first)
	strings.write_byte(&w.sb, '{')
	w.indent += 1
	pfirst := true
	for e in entries {
		Json_Key(&w, e.key, &pfirst)
		if e.raw != "" {
			strings.write_string(&w.sb, e.raw)
			continue
		}
		v := e.val
		switch v.type {
		case .Float:   Json_Float(&w, v.valFloat)
		case .Int:     fmt.sbprintf(&w.sb, "%d", v.valInt)
		case .Boolean: strings.write_string(&w.sb, "true" if v.valBool else "false")
		case .Vector2: Json_Vec2(&w, v.valVec2)
		case .String:
			// Lists (array / curve / gradient) are JSON, not a string.
			if (Script_IsJsonKind(e.kind) || Resource_IsObjectValue(v.valString)) && v.valString != "" do strings.write_string(&w.sb, v.valString)
			else do Json_String(&w, v.valString)
		case .Color:
			strings.write_byte(&w.sb, '[')
			for ch, i in v.valColor {
				if i > 0 do strings.write_string(&w.sb, ", ")
				Json_Float(&w, ch)
			}
			strings.write_byte(&w.sb, ']')
		}
	}
	w.indent -= 1
	if !pfirst do Json_NewLine(&w)
	strings.write_byte(&w.sb, '}')
	w.indent = 0
	Json_NewLine(&w)
	strings.write_string(&w.sb, "}\n")
	return strings.clone(strings.to_string(w.sb), allocator)
}

// --- loading ----------------------------------------------------------------------

// Resource_ScopeOf: the node local resource copies of `node`'s script belong
// to - the nearest component instance root (itself included), else the
// root of its tree. Destroying it releases them.
Resource_ScopeOf :: proc(node: ^Node) -> rawptr {
	for n := node; n != nil; n = n.parent {
		if n.componentPath != "" || n.parent == nil do return n
	}
	return nil
}

// Resource_Load returns the table for a resource file: with cached, the one
// for (scope, path), loading it the first time; else always a new one
// (scope nil = owned by the manager). Its table is set up, then on_load
// runs. nil when the file or its class has a problem (reported).
Resource_Load :: proc(mgr: ^ScriptManager, path: string, scope: rawptr, cached := true) -> ^ResourceInstance {
	if mgr == nil do return nil
	if !mgr.isReady && !ScriptManager_Init(mgr) do return nil
	norm := ScriptVFS_NormalizePath(path)
	if cached {
		for r in mgr.resources do if r.cached && r.scope == scope && r.path == norm do return r
	}
	file, read := Resource_ReadFile(mgr, norm)
	if !read do return nil
	mod, ok := ScriptManager_LoadModule(file.script, mgr)
	if !ok {
		Script_Problem(.Warning, "[Resource] %s: its class %s could not be loaded", norm, file.script)
		return nil
	}
	return resource_create(mgr, mod, norm, file.values, scope, cached, nil, false)
}

// The resources being made (the cycle check of resources inside resources).
@(private = "file")
resourcesLoading: [dynamic]string

// resource_create makes a resource's table from values (a file's, merged
// overrides, or embedded ones), resolves its own resource properties and
// runs on_load. path "" for an embedded one.
@(private = "file")
resource_create :: proc(mgr: ^ScriptManager, mod: ^ScriptModule, path: string, values: map[string]ScriptValue, scope: rawptr, cached: bool, overrides: map[string]ScriptValue, embedded: bool) -> ^ResourceInstance {
	label := path if path != "" else fmt.tprintf("an embedded %s", mod.path if mod != nil else "resource")
	if mod == nil do return nil
	if !mod.isResourceClass {
		Script_Problem(.Warning, "[Resource] %s: %s is not a resource class (it needs `resource = {{}}` on its table)", label, mod.path)
		return nil
	}
	// A resource inside itself (directly or further down): stopped.
	if path != "" {
		for p in resourcesLoading do if p == path {
			Script_Problem(.Warning, "[Resource] %s contains itself (through its resource properties): left nil there", path)
			return nil
		}
		append(&resourcesLoading, strings.clone(path, Engine_HeapAllocator()))
	}
	defer if path != "" {
		delete(pop(&resourcesLoading), Engine_HeapAllocator())
		if len(resourcesLoading) == 0 {
			delete(resourcesLoading)
			resourcesLoading = nil
		}
	}
	L := mgr.L
	lua.newtable(L)
	idx := lua.gettop(L)
	resource_push_meta(L, mod.path)
	lua.setmetatable(L, idx)
	props := make(map[string]ScriptValue)
	script_apply_properties(L, idx, mod, values, &props)
	if path != "" {
		lua.pushstring(L, strings.clone_to_cstring(path, context.temp_allocator))
		lua.setfield(L, idx, "resource_path")
	}
	resource_resolve_nested(L, idx, mgr, mod, props, label, scope)
	res := resource_adopt(mgr, path, mod.path, scope, cached) // (pops the table)
	res.properties = props
	res.embedded = embedded
	if embedded {
		delete(res.diskPath)
		res.diskPath = ""
	}
	if len(overrides) > 0 {
		res.overrides = make(map[string]ScriptValue)
		for k, v in overrides {
			ov := v
			if ov.type == .String || ov.type == .Color || ov.type == .Vector2 do ov.valString = strings.clone(v.valString)
			res.overrides[strings.clone(k)] = ov
		}
	}
	resource_call_on_load(mgr, res)
	return res
}

// resource_resolve_nested sets a resource's own resource properties (the
// table at idx) to their tables: a file shared unless local_copy (then the
// parent's scope), per-instance values and embedded ones its own copies.
@(private = "file")
resource_resolve_nested :: proc(L: ^lua.State, idx: c.int, mgr: ^ScriptManager, mod: ^ScriptModule, props: map[string]ScriptValue, label: string, scope: rawptr) {
	for p in mod.properties {
		if p.assetKind != "resource" do continue // (lists of resources: paths, Resource.load)
		value := (props[p.name] or_else {}).valString
		if value == "" do continue
		res := Resource_Resolve(mgr, label, p, value, scope)
		Resource_Push(L, res)
		lua.setfield(L, idx, strings.clone_to_cstring(p.name, context.temp_allocator))
	}
}

// Resource_Push pushes a resource's table (nil for none).
Resource_Push :: proc(L: ^lua.State, res: ^ResourceInstance) {
	if res == nil || res.registryRef == 0 {
		lua.pushnil(L)
		return
	}
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(res.registryRef))
}

// Resource_ReleaseScope releases the copies a scope owns.
Resource_ReleaseScope :: proc(mgr: ^ScriptManager, scope: rawptr) {
	if mgr == nil || scope == nil do return
	for i := len(mgr.resources) - 1; i >= 0; i -= 1 {
		if mgr.resources[i].scope != scope do continue
		resource_release(mgr, mgr.resources[i])
		ordered_remove(&mgr.resources, i)
	}
}

// Resource_ReloadScope reloads a scope's local resource copies from their files
// and runs on_load again, then re-resolves resource properties on scripts in the
// scope's subtree. Used when reusing pooled nodes (#82).
Resource_ReloadScope :: proc(mgr: ^ScriptManager, scope: rawptr, rootNode: ^Node = nil) {
	if mgr == nil || scope == nil do return
	// 1. Reload the scope's resources from files and run on_load
	for r in mgr.resources {
		if r.scope != scope do continue
		file, ok := Resource_ReadFile(mgr, r.path)
		if !ok do continue
		resource_refresh(mgr, r, file.values)
		resource_call_on_load(mgr, r)
	}

	// 2. Re-resolve resource properties for scripts in the subtree
	if rootNode != nil && mgr.L != nil && mgr.isReady {
		resolve_node_resources(mgr, rootNode)
	}
}

@(private = "file")
resolve_node_resources :: proc(mgr: ^ScriptManager, n: ^Node) {
	if n == nil || !Node_IsAlive(n) do return
	if n.scriptInstance != nil {
		inst := cast(^ScriptInstance)n.scriptInstance
		if inst.registryRef != 0 {
			lua.rawgeti(mgr.L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef))
			script_resolve_resource_props(mgr.L, inst, mgr)
			lua.pop(mgr.L, 1)
		}
	}
	if n.gameContext != nil && n.gameContext.scene != nil && n.gameContext.scene.manager != nil {
		for child in GetChildrenTemp(n.gameContext.scene.manager, n) {
			resolve_node_resources(mgr, child)
		}
	}
}

// Resource_ForgetScope: a node is being destroyed (Node_Terminate).
Resource_ForgetScope :: proc(node: ^Node) {
	mgr := &scriptManager
	if node.gameContext != nil && node.gameContext.scriptManager != nil do mgr = node.gameContext.scriptManager
	if len(mgr.resources) == 0 do return
	Resource_ReleaseScope(mgr, node)
}

// Resource_ClearAll releases every resource table (Simulate stop, shutdown).
Resource_ClearAll :: proc(mgr: ^ScriptManager) {
	if mgr == nil do return
	for r in mgr.resources do resource_release(mgr, r)
	clear(&mgr.resources)
	mgr.loadingResource = nil
}

// Resource_ReloadFile re-reads a resource file and applies its changed
// values to every live table for it (on_load is not run again).
Resource_ReloadFile :: proc(mgr: ^ScriptManager, path: string) -> bool {
	norm := ScriptVFS_NormalizePath(path)
	file, ok := Resource_ReadFile(mgr, norm)
	if !ok do return false
	for r in mgr.resources {
		if r.path != norm do continue
		r.modTime = file_mtime(r.diskPath)
		if ScriptVFS_NormalizePath(file.script) != r.modulePath {
			Script_Problem(.Warning, "[Resource] %s: its class changed to %s; tables already loaded keep %s", norm, file.script, r.modulePath)
			continue
		}
		resource_refresh(mgr, r, file.values)
	}
	return true
}

// resources_check_for_changes: hot reload of edited resource files.
resources_check_for_changes :: proc(mgr: ^ScriptManager) -> int {
	changed := make([dynamic]string, context.temp_allocator)
	for r in mgr.resources {
		if r.diskPath == "" || slice.contains(changed[:], r.path) do continue
		if time.diff(r.modTime, file_mtime(r.diskPath)) > 0 do append(&changed, r.path)
	}
	n := 0
	for p in changed do if Resource_ReloadFile(mgr, p) do n += 1
	return n
}

// resources_module_reloaded: a class was reloaded - its resources get the
// properties it now declares (methods update through the module table).
resources_module_reloaded :: proc(mgr: ^ScriptManager, mod: ^ScriptModule) {
	files := make(map[string]Resource_File, allocator = context.temp_allocator)
	for r in mgr.resources {
		if r.modulePath != mod.path do continue
		file, ok := files[r.path]
		if !ok {
			file, ok = Resource_ReadFile(mgr, r.path)
			if !ok do continue
			files[r.path] = file
		}
		resource_refresh(mgr, r, file.values)
	}
}

// --- internals --------------------------------------------------------------------

// resource_refresh sets the properties whose file value changed (or that
// are new) on a live table.
@(private = "file")
resource_refresh :: proc(mgr: ^ScriptManager, r: ^ResourceInstance, values: map[string]ScriptValue) {
	mod, ok := mgr.modules[r.modulePath]
	if !ok || mod == nil do return
	L := mgr.L
	Resource_Push(L, r)
	defer lua.pop(L, 1)
	for prop in mod.properties {
		if prop.name in r.overrides do continue // (this copy's own value)
		val := script_property_value(prop, values)
		if old, has := r.properties[prop.name]; has && ScriptValue_Equal(old, val) {
			if val.type == .String do delete(val.valString)
			continue
		}
		if prop.assetKind == "node" do lua.pushnil(L)
		else do script_push_value(L, val, prop.assetKind)
		lua.setfield(L, -2, strings.clone_to_cstring(prop.name, context.temp_allocator))
		if oldKey, oldVal, had := delete_key_value(&r.properties, prop.name); had {
			delete(oldKey)
			if oldVal.type == .String do delete(oldVal.valString)
		}
		r.properties[strings.clone(prop.name)] = val
	}
}

@(private = "file")
delete_key_value :: proc(m: ^map[string]ScriptValue, key: string) -> (string, ScriptValue, bool) {
	if key not_in m^ do return "", {}, false
	k, v := delete_key(m, key)
	return k, v, true
}

// resource_adopt records the table at the top of the stack (popped) as a
// resource.
@(private = "file")
resource_adopt :: proc(mgr: ^ScriptManager, path, modulePath: string, scope: rawptr, cached: bool) -> ^ResourceInstance {
	L := mgr.L
	lua.getfield(L, lua.REGISTRYINDEX, RES_SET_KEY)
	if lua.type(L, -1) == .TABLE {
		lua.pushvalue(L, -2)
		lua.pushboolean(L, true)
		lua.rawset(L, -3)
	}
	lua.pop(L, 1)
	res := new(ResourceInstance)
	res.path = strings.clone(path)
	res.modulePath = strings.clone(modulePath)
	res.scope = scope
	res.cached = cached
	res.registryRef = lua.L_ref(L, lua.REGISTRYINDEX)
	res.diskPath = strings.clone(script_disk_path(mgr, path))
	res.modTime = file_mtime(res.diskPath)
	append(&mgr.resources, res)
	return res
}

@(private = "file")
resource_release :: proc(mgr: ^ScriptManager, r: ^ResourceInstance) {
	if mgr.L != nil && r.registryRef != 0 do lua.L_unref(mgr.L, lua.REGISTRYINDEX, r.registryRef)
	if mgr.loadingResource == r do mgr.loadingResource = nil
	delete(r.path)
	delete(r.modulePath)
	delete(r.diskPath)
	for k, v in r.properties {
		delete(k)
		if v.type == .String do delete(v.valString)
	}
	delete(r.properties)
	for k, v in r.overrides {
		delete(k)
		if v.valString != "" do delete(v.valString)
	}
	delete(r.overrides)
	free(r)
}

// resource_push_meta pushes the metatable of a class's resources (made once
// per class; the module table is updated in place on hot reload).
@(private = "file")
resource_push_meta :: proc(L: ^lua.State, modPath: string) {
	key := strings.clone_to_cstring(strings.concatenate({"__Engine_ResourceMeta_", modPath}, context.temp_allocator), context.temp_allocator)
	lua.getfield(L, lua.REGISTRYINDEX, key)
	if lua.type(L, -1) == .TABLE do return
	lua.pop(L, 1)
	lua.getfield(L, lua.REGISTRYINDEX, RES_META_KEY)
	lua.getfield(L, lua.REGISTRYINDEX, strings.clone_to_cstring(strings.concatenate({"__Engine_Module_", modPath}, context.temp_allocator), context.temp_allocator))
	if lua.pcall(L, 1, 1, 0) != 0 || lua.type(L, -1) != .TABLE {
		lua.pop(L, 1)
		lua.newtable(L) // (helpers missing: plain table, no methods)
		return
	}
	lua.pushvalue(L, -1)
	lua.setfield(L, lua.REGISTRYINDEX, key)
}

@(private = "file")
resource_call_on_load :: proc(mgr: ^ScriptManager, res: ^ResourceInstance) {
	L := mgr.L
	lua.pushcfunction(L, lua_traceback_error_handler)
	errHandler := lua.gettop(L)
	Resource_Push(L, res)
	lua.getfield(L, -1, "on_load")
	if lua.type(L, -1) == .FUNCTION {
		lua.pushvalue(L, -2) // self
		prevInst, prevRes := mgr.currentInstance, mgr.loadingResource
		mgr.currentInstance, mgr.loadingResource = nil, res
		if lua.pcall(L, 1, 0, errHandler) != 0 {
			Script_Problem(.Error, "[Resource] Error in %s:on_load() (%s): %s", res.path, res.modulePath, lua.tostring(L, -1))
			lua.pop(L, 1)
		}
		mgr.currentInstance, mgr.loadingResource = prevInst, prevRes
	} else {
		lua.pop(L, 1)
	}
	lua.pop(L, 2) // self, errHandler
}

// resource_current_scope: the scope of the code running now - the resource
// whose on_load runs, else the running script's node's, else none.
@(private = "file")
resource_current_scope :: proc(mgr: ^ScriptManager) -> rawptr {
	if mgr.loadingResource != nil do return mgr.loadingResource.scope
	if mgr.currentInstance != nil && mgr.currentInstance.node != nil do return Resource_ScopeOf(mgr.currentInstance.node)
	return nil
}

// resource_find: the resource whose table is at idx.
@(private = "file")
resource_find :: proc(mgr: ^ScriptManager, L: ^lua.State, idx: c.int) -> ^ResourceInstance {
	idx := lua.absindex(L, idx)
	for r in mgr.resources {
		lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(r.registryRef))
		same := lua.rawequal(L, -1, idx)
		lua.pop(L, 1)
		if same do return r
	}
	return nil
}

// --- Lua API ----------------------------------------------------------------------

// Resource.load(path) -> the shared table, or nil
@(private = "file")
lua_resource_load :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if lua.type(L, 1) != .STRING {
		Script_Problem(.Warning, "Resource.load: expected a path (\"resources/x%s\")", RESOURCE_EXT)
		lua.pushnil(L)
		return 1
	}
	Resource_Push(L, Resource_Load(Script_Manager(L), string(lua.tostring(L, 1)), nil, true))
	return 1
}

// Resource.new(path) -> a fresh table owned by the calling script's scope
@(private = "file")
lua_resource_new :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if lua.type(L, 1) != .STRING {
		Script_Problem(.Warning, "Resource.new: expected a path (\"resources/x%s\")", RESOURCE_EXT)
		lua.pushnil(L)
		return 1
	}
	mgr := Script_Manager(L)
	Resource_Push(L, Resource_Load(mgr, string(lua.tostring(L, 1)), resource_current_scope(mgr), false))
	return 1
}

// res:duplicate() -> a copy of res as it is now (tables deep-copied, other
// resources shared), owned by the calling script's scope. on_load is not run.
@(private = "file")
lua_resource_duplicate :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	mgr := Script_Manager(L)
	src := resource_find(mgr, L, 1) if lua.type(L, 1) == .TABLE else nil
	if src == nil {
		Script_Problem(.Warning, "duplicate: call it on a resource (res:duplicate())")
		lua.pushnil(L)
		return 1
	}
	lua.getfield(L, lua.REGISTRYINDEX, RES_COPY_KEY)
	lua.pushvalue(L, 1)
	if lua.pcall(L, 1, 1, 0) != 0 {
		Script_Problem(.Warning, "duplicate %s: %s", src.path, lua.tostring(L, -1))
		lua.pop(L, 1)
		lua.pushnil(L)
		return 1
	}
	resource_push_meta(L, src.modulePath)
	lua.setmetatable(L, -2)
	res := resource_adopt(mgr, src.path, src.modulePath, resource_current_scope(mgr), false)
	res.properties = make(map[string]ScriptValue, len(src.properties))
	for k, v in src.properties {
		nv := v
		if nv.type == .String do nv.valString = strings.clone(v.valString)
		res.properties[strings.clone(k)] = nv
	}
	Resource_Push(L, res)
	return 1
}

// Resource_ClassMatches: a resource property's `class` names this class
// script - its path ("scripts/weapon.lua"), or its name ("Weapon",
// "HealthPack" for health_pack.lua: case and underscores aside) (#208).
Resource_ClassMatches :: proc(class, script: string) -> bool {
	if class == "" do return true
	if strings.contains(class, "/") || strings.has_suffix(class, ".lua") do return ScriptVFS_NormalizePath(class) == ScriptVFS_NormalizePath(script)
	squash :: proc(s: string) -> string {
		out := make([dynamic]u8, context.temp_allocator)
		for i in 0 ..< len(s) do if s[i] != '_' && s[i] != '-' do append(&out, s[i] | 0x20 if s[i] >= 'A' && s[i] <= 'Z' else s[i])
		return string(out[:])
	}
	stem := filepath.stem(ScriptVFS_NormalizePath(script))
	return squash(class) == squash(stem)
}
