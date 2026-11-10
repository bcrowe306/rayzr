package editor

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"
import e "../engine"
import lsp "../odin_editor/lsp"

// ============================================================================
// Generated Lua types for the project: <project>/.rayzr/definitions/
// project_types.lua, next to the engine API, so lua-language-server
// completes and checks this project's names:
//
//   InputAction   the project's input actions (Input.is_action_pressed(...))
//   SceneName     scene names (Scene.change_scene)
//   ScenePath, TexturePath, AudioPath, ComponentPath, LevelPath, ScriptPath
//   NodeName      node names in the project's scenes and components
//   NodeTag       tags used on those nodes (node:add_tag, Scene.find_by_tag)
//   overloads of Scene.find_node / node:get_child per node
//   name, returning that node's type (TextureNode, CameraNode...), so its
//   own methods complete; a script's `self.node` has the type of the nodes
//   it is attached to; a node name that runs a script returns NodeOf_<name>,
//   whose get_script() is that script's class (its fields and methods); a
//   script's self.node is <Script>Node_, whose get_node completes the paths
//   from it in its scenes / components, each returning that node's type
//   global scripts (Project Settings > Globals) as globals
//   AnimationName, StateMachineParam / Trigger / State (and on_enter_ / on_update_ /
//   on_exit_ / can_exit_ / can_enter_<state> on the script classes), SaveKey, LocaleKey,
//   Language, CollisionLayer   names the project uses (animation_play,
//   sm_*, Save.*, tr / Locale.set, set_collision_layer complete them)
//   ProjectEvent  the custom events the project's scripts emit (connect /
//   emit complete them; scripts get optional on_<event> methods for them
//   and for their node type's own events). Each node class's connect takes
//   its own events (engine_api.lua, checked by test_lua_node_events_definitions)
//   LdtkEntityName, LdtkLevelName, LdtkLayerName, LdtkEnumName, LdtkEnum_<Name>
//   one class per script with its exported properties, so `self.speed` is
//   typed (merged with the script's own ---@class)
//
// Rewritten (debounced) after saves, imports, renames and settings changes;
// the language server is told the file changed.
// ============================================================================

LUA_TYPES_FILE :: "project_types.lua"

@(private = "file")
types: struct {
	dirty:     bool,
	dirtySince: time.Tick,
}

// Lua_MarkProjectTypesDirty schedules a regeneration (debounced).
Lua_MarkProjectTypesDirty :: proc() {
	Editor_InvalidateProjectFiles() // files were added, saved, renamed or removed
	e.CustomNodes_Forget()          // (custom node types: read again when next needed)
	if !types.dirty do types.dirtySince = time.tick_now()
	types.dirty = true
}

// Lua_UpdateProjectTypes runs every frame: regenerates half a second after
// the last change.
Lua_UpdateProjectTypes :: proc(state: ^EditorState) {
	if !types.dirty || time.tick_since(types.dirtySince) < 500 * time.Millisecond do return
	types.dirty = false
	Lua_WriteProjectTypes(state)
}

@(private = "file")
alias :: proc(sb: ^strings.Builder, name, doc: string, values: []string) {
	fmt.sbprintf(sb, "\n-- %s\n---@alias %s", doc, name)
	if len(values) == 0 {
		strings.write_string(sb, " string\n")
		return
	}
	strings.write_byte(sb, '\n')
	for v in values {
		fmt.sbprintf(sb, "---| %q\n", v)
	}
}

@(private = "file")
sorted_unique :: proc(list: ^[dynamic]string) -> []string {
	slice.sort(list[:])
	out := make([dynamic]string, context.temp_allocator)
	for s, i in list do if s != "" && (i == 0 || s != list[i - 1]) do append(&out, s)
	return out[:]
}

// Node types seen per node name and per attached script ("" once two
// differ: plain Node).
@(private = "file")
// A node of a scene / component: its path from the root and type, for the
// paths scripts reach with get_node.
Tree_Node :: struct {
	path:   []string, // names from the root's child down
	type:   string,
	script: string,
}

Node_Types_Seen :: struct {
	byName:       map[string]string,
	byScript:     map[string]string,
	scriptByName: map[string]string, // node name -> its script ("" once two differ)
	customClass:  map[string]string, // custom node type (.node.json) -> its Lua class (HurtboxNode)
	customBase:   map[string]string, // that class -> its built-in type (events)
}

@(private = "file")
note_type :: proc(m: ^map[string]string, key, type: string) {
	if old, seen := m[key]; seen {
		if old != type do m[key] = ""
	} else {
		m[key] = type
	}
}

// node_names collects the "name" (and "tags", types) of every node of a
// scene/component JSON.
@(private = "file")
node_names :: proc(v: json.Value, out: ^[dynamic]string, tags: ^[dynamic]string, types: ^Node_Types_Seen = nil) {
	obj, ok := v.(json.Object)
	if !ok do return
	name, hasName := obj["name"].(json.String)
	if hasName do append(out, string(name))
	if types != nil {
		t := string(obj["type"].(json.String) or_else "Node")
		if info, found := e.Node_TypeInfoByName(t); found do t = info.name
		// A custom node type's node: its class.
		if path, isCustom := obj[e.CUSTOM_NODE_KEY].(json.String); isCustom {
			if cls, known := types.customClass[string(path)]; known do t = cls
		}
		if hasName do note_type(&types.byName, string(name), t)
		if sc, isObj := obj["script"].(json.Object); isObj {
			if path, isStr := sc["path"].(json.String); isStr {
				note_type(&types.byScript, string(path), t)
				if hasName do note_type(&types.scriptByName, string(name), string(path))
			}
		}
	}
	if ts, has := obj["tags"].(json.Array); has do for t in ts do if s, isStr := t.(json.String); isStr do append(tags, string(s))
	if kids, has := obj["children"].(json.Array); has do for k in kids do node_names(k, out, tags, types)
	if inner, has := obj["node"].(json.Object); has do node_names(inner, out, tags, types)
}

// script_class: the class a script declares (---@class X, else the table
// it returns).
@(private = "file")
script_class :: proc(text: string) -> string {
	for line in strings.split_lines(text, context.temp_allocator) {
		l := strings.trim_space(line)
		if strings.has_prefix(l, "---@class ") {
			rest := strings.trim_space(l[len("---@class "):])
			end := 0
			for end < len(rest) && (rest[end] == '_' || (rest[end] >= 'a' && rest[end] <= 'z') || (rest[end] >= 'A' && rest[end] <= 'Z') || (rest[end] >= '0' && rest[end] <= '9')) do end += 1
			if end > 0 do return rest[:end]
		}
	}
	lines := strings.split_lines(text, context.temp_allocator)
	#reverse for line in lines {
		l := strings.trim_space(line)
		if strings.has_prefix(l, "return ") {
			name := strings.trim_space(l[len("return "):])
			ok := len(name) > 0
			for ch in name do if !(ch == '_' || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')) do ok = false
			if ok do return name
			break
		}
	}
	return ""
}

@(private = "file")
lua_type_of :: proc(p: e.ScriptProperty) -> string {
	switch p.assetKind {
	case "texture":   return "TexturePath"
	case "audio":     return "AudioPath"
	case "scene":     return "ScenePath"
	case "component": return "ComponentPath"
	case "level":     return "LevelPath"
	case "script":    return "ScriptPath"
	case "node":      return "Node? # a node (set in the Inspector)"
	case "resource":  return "table? # a resource (set in the Inspector)"
	case "curve":     return "number[][] # a curve: {{t, v}, ...} (Curve.sample)"
	case "gradient":  return "number[][] # a gradient: {{t, r, g, b, a}, ...} (Gradient.sample)"
	case "enum":
		vals := make([dynamic]string, context.temp_allocator)
		for v in p.values do append(&vals, fmt.tprintf("%q", v))
		if len(vals) == 0 do return "string"
		return strings.join(vals[:], "|", context.temp_allocator)
	case "array":
		el := "string"
		switch p.elem {
		case "float", "number":  el = "number"
		case "int", "integer":   el = "integer"
		case "bool", "boolean":  el = "boolean"
		case "color", "vector2", "vec2": el = "number[]"
		case "node":             el = "Node"
		case "resource":         el = "table"
		}
		return fmt.tprintf("%s[]", el)
	}
	switch p.type {
	case .Float:   return "number"
	case .Int:     return "integer"
	case .String:  return "string"
	case .Boolean: return "boolean"
	case .Color:   return "number[] # r, g, b, a (0..1)"
	case .Vector2: return "number[] # x, y"
	}
	return "any"
}

// Lua_ProjectTypesText builds project_types.lua for the open project.
Lua_ProjectTypesText :: proc(state: ^EditorState) -> string {
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "---@meta\n-- Generated by the editor from this project: types for lua-language-server.\n-- Don't edit: it is rewritten when the project changes.\n")

	// Input actions (the defaults when the project defines none).
	actions := make([dynamic]string, context.temp_allocator)
	if len(state.projectConfig.actions) > 0 {
		for a in state.projectConfig.actions do append(&actions, a.name)
	} else {
		defaults := e.Input_DefaultActionConfigs()
		defer e.Input_ActionConfigs_Destroy(&defaults)
		for a in defaults do append(&actions, strings.clone(a.name, context.temp_allocator))
	}
	alias(&sb, "InputAction", "Input actions (Project Settings > Input)", sorted_unique(&actions))

	// Scenes, assets.
	scenePaths := make([dynamic]string, context.temp_allocator)
	sceneNames := make([dynamic]string, context.temp_allocator)
	nodeNames := make([dynamic]string, context.temp_allocator)
	nodeTags := make([dynamic]string, context.temp_allocator)
	types: Node_Types_Seen
	types.byName = make(map[string]string, allocator = context.temp_allocator)
	types.byScript = make(map[string]string, allocator = context.temp_allocator)
	types.scriptByName = make(map[string]string, allocator = context.temp_allocator)
	types.customClass = make(map[string]string, allocator = context.temp_allocator)
	types.customBase = make(map[string]string, allocator = context.temp_allocator)
	// Custom node types (#156): a class each, <Name>Node; a type's script
	// runs on its nodes (self.node is one).
	for t in e.CustomNodes_All(&state.game.gameContext) {
		cls := custom_node_class(t.name)
		types.customClass[strings.clone(t.path, context.temp_allocator)] = cls
		types.customBase[cls] = strings.clone(t.base, context.temp_allocator)
		if script := e.CustomNode_Script(t, &state.game.gameContext); script != "" do note_type(&types.byScript, strings.clone(script, context.temp_allocator), cls)
	}
	// get_node paths per script: path -> type ("Node" once two differ).
	pathsOf := make(map[string]map[string]string, allocator = context.temp_allocator)
	for rel in Editor_ListProjectFiles(state, "", {".scene.json"}) {
		append(&scenePaths, rel)
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		data, err := os.read_entire_file(full, context.temp_allocator)
		if err != nil do continue
		val, perr := json.parse(data, allocator = context.temp_allocator)
		if perr != .None do continue
		root, _ := val.(json.Object)
		if n, ok := root["name"].(json.String); ok do append(&sceneNames, string(n))
		if r, ok := root["root"]; ok {
			if ro, isObj := r.(json.Object); isObj {
				if kids, has := ro["children"].(json.Array); has {
					for k in kids do node_names(k, &nodeNames, &nodeTags, &types)
					tree := make([dynamic]Tree_Node, context.temp_allocator)
					for k in kids do tree_nodes(k, {}, &tree)
					script_paths(tree[:], &pathsOf)
				}
			}
		}
	}
	components := make([dynamic]string, context.temp_allocator)
	for rel in Editor_ListProjectFiles(state, "", {".component.json"}) {
		append(&components, rel)
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		if data, err := os.read_entire_file(full, context.temp_allocator); err == nil {
			if val, perr := json.parse(data, allocator = context.temp_allocator); perr == .None {
				node_names(val, &nodeNames, &nodeTags, &types)
				tree := make([dynamic]Tree_Node, context.temp_allocator)
				tree_nodes(val, {}, &tree)
				script_paths(tree[:], &pathsOf)
			}
		}
	}
	alias(&sb, "SceneName", "Scene names (Scene.change_scene)", sorted_unique(&sceneNames))
	alias(&sb, "ScenePath", "Scene files", sorted_unique(&scenePaths))
	alias(&sb, "NodeName", "Node names in the project's scenes and components", sorted_unique(&nodeNames))
	alias(&sb, "NodeTag", "Tags used in the project's scenes and components", sorted_unique(&nodeTags))
	alias(&sb, "ComponentPath", "Component files", sorted_unique(&components))
	component_overloads(&sb, state, sorted_unique(&components))
	// Script classes (---@class / the returned table) by script path.
	classOf := make(map[string]string, allocator = context.temp_allocator)
	for rel in Editor_ListProjectFiles(state, "", {".lua"}) {
		if strings.has_prefix(rel, ".") do continue
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		if data, err := os.read_entire_file(full, context.temp_allocator); err == nil {
			if cls := script_class(string(data)); cls != "" do classOf[rel] = cls
		}
	}
	typed_lookups(&sb, &types, classOf)
	custom_node_types(&sb, state, &types, classOf)
	// Resources: their files, and Resource.load / new typed by each file's class.
	resourceFiles := make([dynamic]string, context.temp_allocator)
	for rel in Editor_ListProjectFiles(state, "resources", {e.RESOURCE_EXT}) do append(&resourceFiles, rel)
	alias(&sb, "ResourcePath", "Resource files (Resource.load, resource properties)", sorted_unique(&resourceFiles))
	resource_overloads(&sb, state, sorted_unique(&resourceFiles), classOf)
	list :: proc(state: ^EditorState, exts: []string) -> []string {
		l := make([dynamic]string, context.temp_allocator)
		for f in Editor_ListProjectFiles(state, "", exts) do append(&l, f)
		return sorted_unique(&l)
	}
	alias(&sb, "TexturePath", "Image files", list(state, TEXTURE_EXTS))
	alias(&sb, "AudioPath", "Audio files", list(state, AUDIO_EXTS))
	alias(&sb, "LevelPath", "LDtk projects", list(state, {".ldtk"}))
	alias(&sb, "ScriptPath", "Lua scripts", list(state, {".lua"}))
	// Global scripts: their tables as globals (require infers the fields and
	// methods from the script itself).
	if len(state.projectConfig.globals) > 0 {
		strings.write_string(&sb, "\n-- Global scripts (Project Settings > Globals): the same table in every script.\n")
		for g in state.projectConfig.globals {
			if !e.Globals_ValidName(g.name) do continue
			fmt.sbprintf(&sb, "---Global script %s\n%s = require(%q)\n", g.script, g.name, strings.trim_suffix(g.script, ".lua"))
		}
	}

	// LDtk names.
	entities := make([dynamic]string, context.temp_allocator)
	levels := make([dynamic]string, context.temp_allocator)
	layers := make([dynamic]string, context.temp_allocator)
	enumNames := make([dynamic]string, context.temp_allocator)
	enumValues := make(map[string][dynamic]string, allocator = context.temp_allocator)
	for rel in Editor_ListProjectFiles(state, "", {".ldtk"}) {
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		proj, ok := e.Ldtk_LoadProjectFromFile(full)
		if !ok || proj == nil do continue
		for d in proj.entityDefs do append(&entities, strings.clone(d.identifier, context.temp_allocator))
		for l in proj.levels do append(&levels, strings.clone(l.identifier, context.temp_allocator))
		for d in proj.layerDefs do append(&layers, strings.clone(d.identifier, context.temp_allocator))
		for en in proj.enums {
			name := strings.clone(en.identifier, context.temp_allocator)
			append(&enumNames, name)
			if name not_in enumValues do enumValues[name] = make([dynamic]string, context.temp_allocator)
			for v in en.values do append(&enumValues[name], strings.clone(v.id, context.temp_allocator))
		}
		e.Ldtk_DestroyProject(proj)
	}
	// (<X>Name: LdtkEntity, LdtkLevel and LdtkLayer are the engine's
	// classes of those objects, #403.)
	alias(&sb, "LdtkEntityName", "LDtk entity identifiers", sorted_unique(&entities))
	alias(&sb, "LdtkLevelName", "LDtk level identifiers", sorted_unique(&levels))
	alias(&sb, "LdtkLayerName", "LDtk layer identifiers", sorted_unique(&layers))
	names := sorted_unique(&enumNames)
	alias(&sb, "LdtkEnumName", "LDtk enums", names)
	for n in names {
		vals := enumValues[n]
		alias(&sb, fmt.tprintf("LdtkEnum_%s", n), fmt.tprintf("Values of the LDtk enum %s", n), sorted_unique(&vals))
	}

	// Names used across the project: animations and state machines (scenes,
	// components), save keys (scripts), locale keys and languages (locale/
	// tables), collision layers (Project Settings).
	anims := make([dynamic]string, context.temp_allocator)
	smParams := make([dynamic]string, context.temp_allocator)
	smStates := make([dynamic]string, context.temp_allocator)
	smTriggers := make([dynamic]string, context.temp_allocator)
	for rel in Editor_ListProjectFiles(state, "", {".scene.json", ".component.json"}) {
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		if data, err := os.read_entire_file(full, context.temp_allocator); err == nil {
			if val, perr := json.parse(data, allocator = context.temp_allocator); perr == .None do scene_names(val, &anims, &smParams, &smStates, &smTriggers)
		}
	}
	alias(&sb, "AnimationName", "Animations of the project's AnimationPlayers (animation_play)", sorted_unique(&anims))
	alias(&sb, "StateMachineParam", "State machine parameters (sm_set / sm_get)", sorted_unique(&smParams))
	alias(&sb, "StateMachineTrigger", "State machine triggers (sm_trigger / sm_trigger_pending / sm_clear_trigger)", sorted_unique(&smTriggers))
	alias(&sb, "StateMachineState", "State machine states (sm_transition / sm_can_transition / sm_start)", sorted_unique(&smStates))
	saveKeys := make([dynamic]string, context.temp_allocator)
	for rel in Editor_ListProjectFiles(state, "", {".lua"}) {
		if strings.has_prefix(rel, ".") do continue
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		if data, err := os.read_entire_file(full, context.temp_allocator); err == nil {
			for fn in ([]string{"Save.set(", "Save.get(", "Save.has(", "Save.delete("}) do string_args(string(data), fn, &saveKeys)
		}
	}
	alias(&sb, "SaveKey", "Save keys the project's scripts use (Save.set / get)", sorted_unique(&saveKeys))
	localeKeys := make([dynamic]string, context.temp_allocator)
	languages := make([dynamic]string, context.temp_allocator)
	for rel in Editor_ListProjectFiles(state, "locale", {".csv"}) {
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		if data, err := os.read_entire_file(full, context.temp_allocator); err == nil {
			rows := e.Locale_ParseCSV(string(data))
			for row, i in rows {
				if len(row) == 0 do continue
				if i == 0 {
					for lang in row[1:] do append(&languages, strings.clone(strings.trim_space(lang), context.temp_allocator))
				} else if k := strings.trim_space(row[0]); k != "" {
					append(&localeKeys, strings.clone(k, context.temp_allocator))
				}
			}
		}
	}
	alias(&sb, "LocaleKey", "Keys of the project's locale/ tables (tr)", sorted_unique(&localeKeys))
	alias(&sb, "Language", "Languages of the project's locale/ tables (Locale.set)", sorted_unique(&languages))
	layers_ := make([dynamic]string, context.temp_allocator)
	for n in state.projectConfig.collisionLayers do if n != "" do append(&layers_, n)
	alias(&sb, "CollisionLayer", "Collision layer names (Project Settings > General > Collision Layers)", sorted_unique(&layers_))

	// Custom events: what the project's scripts emit (connect / emit
	// complete them).
	custom := make([dynamic]string, context.temp_allocator)
	for rel in Editor_ListProjectFiles(state, "", {".lua"}) {
		if strings.has_prefix(rel, ".") do continue
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		if data, err := os.read_entire_file(full, context.temp_allocator); err == nil do emitted_events(string(data), &custom)
	}
	alias(&sb, "ProjectEvent", "Custom events the project's scripts emit (node:emit, Events.emit)", sorted_unique(&custom))
	customEvents := sorted_unique(&custom)

	// Script classes with their exported properties.
	strings.write_string(&sb, "\n-- Script classes: exported properties (set in the Inspector) are fields of self.\n")
	sm := &state.game.scriptManager
	Script_Node_Class :: struct {cls, nodeType: string, paths: map[string]string}
	nodeClasses := make([dynamic]Script_Node_Class, context.temp_allocator)
	for rel in Editor_ListProjectFiles(state, "", {".lua"}) {
		if strings.has_prefix(rel, ".") do continue
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		data, err := os.read_entire_file(full, context.temp_allocator)
		if err != nil do continue
		cls := script_class(string(data))
		if cls == "" do continue
		mod, ok := e.ScriptManager_LoadModule(rel, sm)
		nodeType := types.byScript[rel] or_else ""
		if (!ok || mod == nil || len(mod.properties) == 0) && nodeType == "" do continue
		isResource := ok && mod != nil && mod.isResourceClass
		if isResource {
			// A resource has no node: no node, events or state machine callbacks.
			fmt.sbprintf(&sb, "\n-- %s (a resource class)\n---@class %s : ResourceBase\n", rel, cls)
		} else {
			fmt.sbprintf(&sb, "\n-- %s\n---@class %s\n", rel, cls)
		}
		if isResource {
		} else if paths, has := pathsOf[rel]; has && len(paths) > 0 {
			// Its node's own class: get_node completes the paths from it.
			fmt.sbprintf(&sb, "---@field node %s The node this script is attached to.\n", script_node_class(cls))
			append(&nodeClasses, Script_Node_Class{cls, nodeType if nodeType != "" else "Node", paths}) // written after the script classes
		} else if nodeType != "" {
			fmt.sbprintf(&sb, "---@field node %s The node this script is attached to.\n", nodeType)
		}
		// Its node's own events (the tree ones are on ScriptInstanceBase) and
		// the project's custom events as optional methods.
		if !isResource do for ev in node_type_events(types.customBase[nodeType] or_else nodeType)[6:] do fmt.sbprintf(&sb, "---@field on_%s? fun(self: %s, value: any) %s event of its node\n", ev, cls, ev)
		if !isResource do for ev in customEvents do fmt.sbprintf(&sb, "---@field on_%s? fun(self: %s, value: any) custom event (emit)\n", ev, cls)
		// State machine callbacks for the project's states (on the machine's
		// script or its parent's).
		if !isResource do for st in sorted_unique(&smStates) {
			fmt.sbprintf(&sb, "---@field on_enter_%s? fun(self: %s, previous: string) state machine: entered %s\n", st, cls, st)
			fmt.sbprintf(&sb, "---@field on_update_%s? fun(self: %s, dt: number) state machine: every frame in %s\n", st, cls, st)
			fmt.sbprintf(&sb, "---@field on_exit_%s? fun(self: %s, next: string) state machine: left %s\n", st, cls, st)
			fmt.sbprintf(&sb, "---@field can_exit_%s? fun(self: %s, next: string): boolean state machine guard: false keeps it in %s\n", st, cls, st)
			fmt.sbprintf(&sb, "---@field can_enter_%s? fun(self: %s, previous: string): boolean state machine guard: false keeps it out of %s\n", st, cls, st)
		}
		if !ok || mod == nil do continue
		for p in mod.properties {
			// The script types it itself (---@field speed integer, a node
			// property ---@field map TileMapNode): its own type stands - two
			// declarations would be a union of both (#403).
			if script_declares_field(string(data), p.name) do continue
			t := lua_type_of(p)
			// A resource of a known class: typed as that class.
			if e.Script_IsResourceProp(p) && p.resourceClass != "" {
				if rc, has := classOf[e.ScriptVFS_NormalizePath(p.resourceClass)]; has {
					t = fmt.tprintf("%s? # a %s resource (set in the Inspector)", rc, rc) if p.assetKind == "resource" else fmt.tprintf("%s[]", rc)
				}
			}
			doc := p.tooltip
			if doc == "" do doc = Script_PropComment(string(data), p.name)
			if doc == "" do doc = p.label
			if i := strings.index(t, " # "); i >= 0 {
				if doc == "" do doc = t[i + 3:]
				t = t[:i]
			}
			fmt.sbprintf(&sb, "---@field %s %s%s\n", p.name, t, fmt.tprintf(" %s", doc) if doc != "" else "")
		}
	}
	// The scripts' node classes (typed get_node paths).
	for nc in nodeClasses do script_node_block(&sb, nc.cls, nc.nodeType, nc.paths)
	return strings.to_string(sb)
}

// script_declares_field: the script's own annotations have ---@field <name>.
script_declares_field :: proc(text, name: string) -> bool {
	for line in strings.split_lines(text, context.temp_allocator) {
		l := strings.trim_space(line)
		if !strings.has_prefix(l, "---@field ") do continue
		rest := strings.trim_left_space(l[len("---@field "):])
		for scope in ([]string{"public ", "private ", "protected ", "package "}) do rest = strings.trim_left_space(strings.trim_prefix(rest, scope))
		if !strings.has_prefix(rest, name) do continue
		after := rest[len(name):]
		if after == "" || after[0] == ' ' || after[0] == '?' || after[0] == '\t' do return true
	}
	return false
}

// Lua_WriteProjectTypes writes project_types.lua (when it changed) and tells
// the language server.
Lua_WriteProjectTypes :: proc(state: ^EditorState) {
	if state.projectPath == "" || !os.is_dir(state.projectPath) do return
	root := state.projectPath
	if !filepath.is_abs(root) {
		if abs, err := os.get_absolute_path(root, context.temp_allocator); err == nil do root = abs
	}
	path, _ := filepath.join({root, LUA_DEFINITIONS_DIR, LUA_TYPES_FILE}, context.temp_allocator)
	text := Lua_ProjectTypesText(state)
	if old, err := os.read_entire_file(path, context.temp_allocator); err == nil && string(old) == text do return
	_ = os.make_directory_all(filepath.dir(path, context.temp_allocator))
	if os.write_entire_file(path, transmute([]u8)text) != nil do return
	Code_LspPushLibraryFile(path, text) // the language server takes the new text (code_editor_lsp.odin)
}

// typed_lookups: overloads returning each named node's type (names whose
// nodes all have the same, non-plain type).
// scene_names collects animation names and state machine parameters /
// states of a scene / component JSON.
@(private = "file")
scene_names :: proc(v: json.Value, anims, params, states, triggers: ^[dynamic]string) {
	#partial switch x in v {
	case json.Object:
		if arr, ok := x["animations"].(json.Array); ok {
			for a in arr do if o, isObj := a.(json.Object); isObj do if n, has := o["name"].(json.String); has do append(anims, string(n))
		}
		if sm, ok := x["state_machine"].(json.Object); ok {
			// params / triggers: [[name, ...], ...]; states: [{"name"}, ...].
			first :: proc(a: json.Value) -> (name: string, ok: bool) {
				arr := a.(json.Array) or_return
				if len(arr) == 0 do return
				n := arr[0].(json.String) or_return
				return string(n), true
			}
			if arr, has := sm["params"].(json.Array); has do for a in arr do if n, ok := first(a); ok do append(params, n)
			if arr, has := sm["triggers"].(json.Array); has do for a in arr do if n, ok := first(a); ok do append(triggers, n)
			if arr, has := sm["states"].(json.Array); has do for a in arr do if o, isObj := a.(json.Object); isObj do if n, hasN := o["name"].(json.String); hasN do append(states, string(n))
		}
		for _, child in x do scene_names(child, anims, params, states, triggers)
	case json.Array:
		for child in x do scene_names(child, anims, params, states, triggers)
	}
}

// string_args: the string literal passed first to `fn` ("Save.get(") in a
// script, each time it's called.
@(private = "file")
string_args :: proc(text, fn: string, out: ^[dynamic]string) {
	rest := text
	for {
		i := strings.index(rest, fn)
		if i < 0 do return
		rest = rest[i + len(fn):]
		t := strings.trim_left_space(rest)
		if len(t) < 2 || (t[0] != '"' && t[0] != '\'') do continue
		if j := strings.index_byte(t[1:], t[0]); j > 0 do append(out, strings.clone(t[1:1 + j], context.temp_allocator))
	}
}

// emitted_events: the names a script passes to emit("...") / :emit('...')
// (node events and Events.emit) and Events.emit_deferred("...").
@(private = "file")
emitted_events :: proc(text: string, out: ^[dynamic]string) {
	for call in ([]string{"emit(", "emit_deferred("}) do emitted_events_of(text, call, out)
}

@(private = "file")
emitted_events_of :: proc(text, call: string, out: ^[dynamic]string) {
	rest := text
	for {
		i := strings.index(rest, call)
		if i < 0 do return
		rest = rest[i + len(call):]
		t := strings.trim_left_space(rest)
		if len(t) < 2 || (t[0] != '"' && t[0] != '\'') do continue
		q := t[0]
		if j := strings.index_byte(t[1:], q); j > 0 {
			name := t[1:1 + j]
			ok := true
			for ch in name do if !(ch == '_' || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')) do ok = false
			if ok do append(out, strings.clone(name, context.temp_allocator))
		}
	}
}

// node_type_events: the events a node type raises - the tree events and its
// own, read from the engine definitions' `---@alias <Type>Event` lines.
node_type_events :: proc(nodeType: string) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	append(&out, "entered_tree", "exited_tree", "child_added", "child_removed", "parent_added", "parent_removed")
	if nodeType == "" do return out[:]
	api := ENGINE_API_LUA
	key := fmt.tprintf("---@alias %sEvent ", nodeType)
	i := strings.index(api, key)
	if i < 0 do return out[:]
	line := api[i + len(key):]
	if nl := strings.index_byte(line, '\n'); nl >= 0 do line = line[:nl]
	for part in strings.split(line, "|", context.temp_allocator) {
		p := strings.trim_space(part)
		if len(p) > 2 && p[0] == '"' do append(&out, p[1:len(p) - 1])
	}
	return out[:]
}

// tree_nodes flattens a scene / component JSON node tree.
@(private = "file")
tree_nodes :: proc(v: json.Value, parent: []string, out: ^[dynamic]Tree_Node) {
	obj, ok := v.(json.Object)
	if !ok do return
	if inner, has := obj["node"].(json.Object); has && obj["type"] == nil {
		tree_nodes(inner, parent, out) // a component file: {"node": {...}}
		return
	}
	name := string(obj["name"].(json.String) or_else "")
	t := string(obj["type"].(json.String) or_else "Node")
	if info, found := e.Node_TypeInfoByName(t); found do t = info.name
	path := make([]string, len(parent) + 1, context.temp_allocator)
	copy(path, parent)
	path[len(parent)] = name
	script := ""
	if sc, isObj := obj["script"].(json.Object); isObj do script = string(sc["path"].(json.String) or_else "")
	append(out, Tree_Node{path, t, script})
	if kids, has := obj["children"].(json.Array); has do for k in kids do tree_nodes(k, path, out)
}

MAX_SCRIPT_PATHS :: 200

// script_paths: for each node with a script, the relative path to every
// other node of its tree (children, "..", siblings "../X"), with its type.
@(private = "file")
script_paths :: proc(tree: []Tree_Node, out: ^map[string]map[string]string) {
	for owner in tree {
		if owner.script == "" do continue
		if owner.script not_in out do out[owner.script] = make(map[string]string, allocator = context.temp_allocator)
		m := &out[owner.script]
		for other in tree {
			if len(m) >= MAX_SCRIPT_PATHS do break
			rel := relative_tree_path(owner.path, other.path)
			if rel == "" || rel == "." do continue
			if old, seen := m[rel]; seen {
				if old != other.type do m[rel] = "Node"
			} else {
				m[rel] = other.type
			}
		}
		// The parent ("..") too.
		if len(owner.path) > 1 {
			for other in tree do if len(other.path) == len(owner.path) - 1 && slice.equal(other.path, owner.path[:len(owner.path) - 1]) {
				if old, seen := m[".."]; seen && old != other.type do m[".."] = "Node"
				else if !seen do m[".."] = other.type
			}
		}
	}
}

// relative_tree_path: get_node path from one node to another ("Gun",
// "Gun/Muzzle", "../Camera", "../../X"); "" for itself or its ancestors.
@(private = "file")
relative_tree_path :: proc(from, to: []string) -> string {
	common := 0
	for common < len(from) && common < len(to) && from[common] == to[common] do common += 1
	if common == len(to) do return "" // itself or an ancestor
	parts := make([dynamic]string, context.temp_allocator)
	for _ in common ..< len(from) do append(&parts, "..")
	for p in to[common:] do append(&parts, p)
	return strings.join(parts[:], "/", context.temp_allocator)
}

// script_node_class: the class of a script's self.node with typed get_node.
script_node_class :: proc(cls: string) -> string {return fmt.tprintf("%sNode_", cls)}

// script_node_block writes that class: get_node overloads per path.
@(private = "file")
script_node_block :: proc(sb: ^strings.Builder, cls, nodeType: string, paths: map[string]string) {
	keys := make([dynamic]string, context.temp_allocator)
	for k in paths do append(&keys, k)
	slice.sort(keys[:])
	nc := script_node_class(cls)
	fmt.sbprintf(sb, "\n---@class %s : %s\nlocal %s = {{}}\n---A node by path from this one (\"Gun\", \"../Player\"): the paths in its scenes complete, typed.\n", nc, nodeType, nc)
	for k in keys do fmt.sbprintf(sb, "---@overload fun(self: %s, path: %q): %s\n", nc, k, paths[k])
	fmt.sbprintf(sb, "---@param path string\n---@return Node?\nfunction %s:get_node(path) end\n", nc)
}

// component_overloads: Scene.instantiate per component file, returning its
// root node's type.
// resource_overloads: Resource.load / Resource.new return each file's class.
@(private = "file")
resource_overloads :: proc(sb: ^strings.Builder, state: ^EditorState, files: []string, classOf: map[string]string) {
	if len(files) == 0 do return
	lines := make([dynamic]string, context.temp_allocator)
	for rel in files {
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		data, err := os.read_entire_file(full, context.temp_allocator)
		if err != nil do continue
		file, ok := e.Resource_ParseText(rel, string(data), quiet = true)
		if !ok do continue
		cls := classOf[e.ScriptVFS_NormalizePath(file.script)] or_else "ResourceBase"
		append(&lines, fmt.tprintf("---@overload fun(path: %q): %s\n", rel, cls))
	}
	if len(lines) == 0 do return
	strings.write_string(sb, "\n-- Resources by path: Resource.load / new return the file's class.\n---@class ResourceModule\nlocal ResourceModule = {}\n")
	for fn in ([]string{"load", "new"}) {
		for l in lines do strings.write_string(sb, l)
		fmt.sbprintf(sb, "---@param path ResourcePath|string\n---@return ResourceBase?\nfunction ResourceModule.%s(path) end\n", fn)
	}
}

@(private = "file")
component_overloads :: proc(sb: ^strings.Builder, state: ^EditorState, comps: []string) {
	if len(comps) == 0 do return
	strings.write_string(sb, "\n-- Components by path: Scene.instantiate returns the root's type.\n---@class SceneModule\nlocal SceneModule = {}\n")
	for rel in comps {
		t := "Node"
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		if data, err := os.read_entire_file(full, context.temp_allocator); err == nil {
			if v, perr := json.parse(data, allocator = context.temp_allocator); perr == .None {
				if o, ok := v.(json.Object); ok {
					if inner, isObj := o["node"].(json.Object); isObj && o["type"] == nil do o = inner
					if ty, has := o["type"].(json.String); has {
						t = string(ty)
						if info, found := e.Node_TypeInfoByName(t); found do t = info.name
					}
				}
			}
		}
		fmt.sbprintf(sb, "---@overload fun(component: %q, parent?: Node, x?: number|Vec2|table<string, any>, y?: number|table<string, any>, properties?: table<string, any>): %s\n", rel, t)
	}
	// (The same parameters as engine_api.lua's: a call with the properties
	// table was "redundant-parameter", #403.)
	strings.write_string(sb, "---@param component ComponentPath|string\n---@param parent? Node\n---@param x? number|Vec2|table<string, any>\n---@param y? number|table<string, any>\n---@param properties? table<string, any>\n---@return Node?\nfunction SceneModule.instantiate(component, parent, x, y, properties) end\n")
}

// node_class_name: the refined class of a node name that has a script.
node_class_name :: proc(name: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "NodeOf_")
	for ch in name do strings.write_rune(&sb, ch if ch == '_' || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') else '_')
	return strings.to_string(sb)
}

// typed_lookups: Scene.find_node / node:get_child overloads per node name,
// returning the node's type - or, for a node with a script, a class of its
// own (NodeOf_<name>) whose get_script() returns that script's class.
@(private = "file")
typed_lookups :: proc(sb: ^strings.Builder, types: ^Node_Types_Seen, classOf: map[string]string) {
	returns := make(map[string]string, allocator = context.temp_allocator)
	all := make([dynamic]string, context.temp_allocator)
	for n, t in types.byName do if t != "" do append(&all, n)
	slice.sort(all[:]) // stable output: the file is only rewritten when it changes
	names := make([dynamic]string, context.temp_allocator)
	for n in all {
		t := types.byName[n]
		ret := t
		if script := types.scriptByName[n] or_else ""; script != "" {
			if cls, ok := classOf[script]; ok {
				ret = node_class_name(n)
				fmt.sbprintf(sb, "\n-- %q runs %s\n---@class %s : %s\nlocal %s = {{}}\n---The node's script instance (%s): its fields and methods.\n---@return %s\nfunction %s:get_script() end\n", n, script, ret, t, ret, cls, cls, ret)
			}
		}
		if ret == "Node" do continue
		returns[n] = ret
		append(&names, n)
	}
	if len(names) == 0 do return
	slice.sort(names[:])
	strings.write_string(sb, "\n-- Nodes by name: these return the node's own type, so its methods complete.\n---@class SceneModule\nlocal SceneModule = {}\n")
	for n in names do fmt.sbprintf(sb, "---@overload fun(name: %q): %s\n", n, returns[n])
	strings.write_string(sb, "---@param name NodeName|string\n---@return Node?\nfunction SceneModule.find_node(name) end\n")
	strings.write_string(sb, "\n---@class Node\nlocal Node = {}\n")
	for n in names do fmt.sbprintf(sb, "---@overload fun(self: Node, name: %q): %s\n", n, returns[n])
	strings.write_string(sb, "---@param name NodeName|string\n---@return Node?\nfunction Node:get_child(name) end\n")
}

// custom_node_class: a custom node type's Lua class ("Hurtbox" ->
// HurtboxNode: the type's script usually has the class Hurtbox).
custom_node_class :: proc(name: string) -> string {return fmt.tprintf("%sNode", name)}

// custom_node_types: the custom node types' classes (#156) - built on their
// base type (or parent type), get_script() returning their script's class -
// and Scene.create / Scene.find_nodes_of_type returning them, and the
// built-in types (#403: Scene.create("TextureNode") is a TextureNode), by name.
@(private = "file")
custom_node_types :: proc(sb: ^strings.Builder, state: ^EditorState, types: ^Node_Types_Seen, classOf: map[string]string) {
	ctx := &state.game.gameContext
	all := e.CustomNodes_All(ctx)
	names := make([dynamic]string, context.temp_allocator)
	if len(all) > 0 do strings.write_string(sb, "\n-- Custom node types (nodes/*.node.json): <Name>Node classes.\n")
	for t in all {
		cls := custom_node_class(t.name)
		parent := t.base
		if t.inherits != "" {
			if p, _ := e.CustomNode_Get(ctx, t.inherits); p != nil do parent = custom_node_class(p.name)
		}
		desc := t.description if t.description != "" else fmt.tprintf("A %s (%s): a custom node type", t.name, t.base)
		fmt.sbprintf(sb, "\n---%s\n---@class %s : %s\nlocal %s = {{}}\n", desc, cls, parent, cls)
		if script := e.CustomNode_Script(t, ctx); script != "" {
			if sc, ok := classOf[script]; ok {
				fmt.sbprintf(sb, "---The node's script instance (%s): its fields and methods.\n---@return %s\nfunction %s:get_script() end\n", sc, sc, cls)
			}
		}
		append(&names, strings.clone(t.name, context.temp_allocator))
	}
	alias(sb, "CustomNodeType", "The project's custom node types (Scene.create, node:is)", sorted_unique(&names))
	// type name -> class: the custom types, then the built-in ones that have
	// a class in engine_api.lua.
	byName := make([dynamic][2]string, context.temp_allocator)
	for n in names do append(&byName, [2]string{n, custom_node_class(n)})
	for info in e.NODE_TYPES {
		if info.name == "Node" || !strings.contains(ENGINE_API_LUA, fmt.tprintf("---@class %s ", info.name)) do continue
		append(&byName, [2]string{info.name, info.name})
	}
	// (Its own local: the components' block may have declared SceneModule.)
	strings.write_string(sb, "\n-- Scene.create / Scene.find_nodes_of_type by type name: that type's class.\n---@class SceneModule\nlocal SceneModuleByType = {}\n")
	for p in byName do fmt.sbprintf(sb, "---@overload fun(typeName: %q, parent?: Node, x?: number|Vec2, y?: number): %s\n", p[0], p[1])
	strings.write_string(sb, "---@param typeName CustomNodeType|string\n---@param parent? Node\n---@param x? number|Vec2\n---@param y? number\n---@return Node?\nfunction SceneModuleByType.create(typeName, parent, x, y) end\n")
	for p in byName do fmt.sbprintf(sb, "---@overload fun(typeName: %q): %s[]\n", p[0], p[1])
	strings.write_string(sb, "---@param typeName CustomNodeType|string\n---@return Node[]\nfunction SceneModuleByType.find_nodes_of_type(typeName) end\n")
}
