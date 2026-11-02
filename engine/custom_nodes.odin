package engine

import "core:encoding/json"
import "core:fmt"
import "core:log"
import os "osx"
import "core:path/filepath"
import "core:slice"
import "core:strings"

// ============================================================================
// Custom node types (#152): a project's own node types, made of a built-in
// base type, a script and default values - a Hurtbox is an Area with
// hurtbox.lua and a 32x32 box. A type is a file anywhere in the project:
//
//   nodes/Hurtbox.node.json
//   {"name": "Hurtbox", "base": "AreaNode", "script": "scripts/hurtbox.lua",
//    "icon": "heart", "color": "#ef4444ff", "category": "Combat",
//    "description": "Takes damage from hitboxes",
//    "defaults": {"shapes": [{"type": "Box", "size": [32, 32]}],
//                 "script": {"properties": {"max_health": 5}}}}
//
// "defaults" are node keys as a scene writes them (on top of the base
// type's own defaults and the script's property defaults).
//
// A type can build on another: "inherits": "nodes/Hurtbox.node.json" - its
// base type is the parent's, its defaults go on top of the parent's (a
// change to the parent reaches it), its script is the parent's unless it
// gives its own (usually one that `extends` the parent's), and its nodes
// are also of the parent's type (is()).
//
// A node of the type is saved as its base type, the link and only what
// differs from the type ("linked defaults", like a component instance):
//
//   {"type": "AreaNode", "name": "Hurtbox2", "node_type": "nodes/Hurtbox.node.json",
//    "position": [..], "scale": [..], "rotation": 0, "script": {"properties": {"max_health": 9}}}
//
// On load the node's keys are merged over the type's (CUSTOM_DIRECT_KEYS
// are always the node's own; "properties" and a script's "properties"
// merge key by key; other keys replace; null removes), so a changed type
// reaches every node except for what the node changed. A node whose type
// can't be loaded is its base type ("type" is always written) and keeps
// its keys as loaded, so saving doesn't lose them.
// ============================================================================

CUSTOM_NODE_SUFFIX :: ".node.json"
// The key linking a node to its type (a project-relative .node.json).
CUSTOM_NODE_KEY :: "node_type"

// Keys a custom node always writes itself (never from its type).
@(private = "file")
CUSTOM_DIRECT_KEYS :: []string{"type", "name", "uid", "position", "scale", "rotation", "pivot", "children", "connections", CUSTOM_NODE_KEY}

// Custom_IsDirectKey: a key every custom node writes itself.
Custom_IsDirectKey :: proc(k: string) -> bool {return slice.contains(CUSTOM_DIRECT_KEYS, k)}

CustomNodeType :: struct {
	path:        string, // project-relative .node.json
	name:        string, // "Hurtbox": Add Node, get_type(), is()
	base:        string, // the built-in type ("AreaNode")
	script:      string, // project-relative script ("" = none)
	icon:        string,
	color:       string, // "#rrggbbaa" ("" = the base type's)
	category:    string,
	description: string,
	defaults:    string, // JSON object: node keys the type starts with
	inherits:    string, // the parent type's .node.json ("" = none; base is then the parent's)
	canonical:   string, // (cache) the base type with the defaults, as a node writes it, without the script
}

// One project's types (its folder, or a mounted package).
@(private = "file")
Custom_Registry :: struct {
	types:    map[string]^CustomNodeType, // by path
	problems: map[string]string,          // path -> why it can't be loaded
	scanned:  bool,                       // every .node.json read (All, FindByName)
	list:     [dynamic]^CustomNodeType,   // (scanned) sorted by name
}

@(private = "file")
customRegistries: map[string]^Custom_Registry

@(private = "file")
custom_registry :: proc(ctx: ^GameContext) -> ^Custom_Registry {
	key := "|"
	if ctx != nil && ctx.game != nil {
		am := &ctx.game.assetManager
		key = fmt.tprintf("%s|%p", am.projectDir, am.package_)
	}
	if reg, ok := customRegistries[key]; ok do return reg
	heap := Engine_HeapAllocator()
	if customRegistries == nil do customRegistries = make(map[string]^Custom_Registry, 4, heap)
	reg := new(Custom_Registry, heap)
	reg.types = make(map[string]^CustomNodeType, 8, heap)
	reg.problems = make(map[string]string, 4, heap)
	reg.list = make([dynamic]^CustomNodeType, heap)
	customRegistries[strings.clone(key, heap)] = reg
	return reg
}

// CustomNodes_Forget drops every loaded type (files changed: they're read
// again when next needed; engine shutdown).
CustomNodes_Forget :: proc() {
	heap := Engine_HeapAllocator()
	for key, reg in customRegistries {
		for _, t in reg.types do free_custom_type(t)
		for k, p in reg.problems {
			delete(k, heap)
			delete(p, heap)
		}
		delete(reg.types)
		delete(reg.problems)
		delete(reg.list)
		free(reg, heap)
		delete(key, heap)
	}
	clear(&customRegistries)
}

@(private = "file")
free_custom_type :: proc(t: ^CustomNodeType) {
	heap := Engine_HeapAllocator()
	for s in ([]string{t.path, t.name, t.base, t.script, t.icon, t.color, t.category, t.description, t.defaults, t.inherits, t.canonical}) do delete(s, heap)
	free(t, heap)
}

// CustomNode_IsValidName: a name a type can have - an identifier (letters,
// digits, _; not starting with a digit), not a built-in type's.
CustomNode_IsValidName :: proc(name: string) -> (ok: bool, problem: string) {
	if name == "" do return false, "a name is needed"
	for r, i in name {
		letter := (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || r == '_'
		digit := r >= '0' && r <= '9'
		if !letter && !(digit && i > 0) do return false, "only letters, digits and _, not starting with a digit"
	}
	if _, builtin := Node_TypeInfoByName(name); builtin || name == "Node" do return false, fmt.tprintf("%s is a built-in node type", name)
	return true, ""
}

// CustomNode_Parse reads a type from its file's text (allocated on the
// engine heap; nil and why when it isn't a valid type).
CustomNode_Parse :: proc(path, text: string) -> (^CustomNodeType, string) {
	val, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None do return nil, fmt.tprintf("not valid JSON (%v)", err)
	obj, isObj := val.(json.Object)
	if !isObj do return nil, "not a JSON object"
	Format_Migrate(.CustomNode, &obj, path)
	str :: proc(o: json.Object, k: string) -> string {s, _ := o[k].(json.String); return string(s)}
	name, base, inherits := str(obj, "name"), str(obj, "base"), str(obj, "inherits")
	if ok, problem := CustomNode_IsValidName(name); !ok do return nil, fmt.tprintf("its name: %s", problem)
	if base == "" do base = "Node"
	if _, known := Node_TypeInfoByName(base); !known && base != "Node" && inherits == "" do return nil, fmt.tprintf("its base \"%s\" isn't a node type", base)
	defaults := "{}"
	if d, has := obj["defaults"].(json.Object); has {
		w := Json_Writer{sb = strings.builder_make(context.temp_allocator)}
		Json_WriteValue(&w, d)
		defaults = strings.to_string(w.sb)
	}
	heap := Engine_HeapAllocator()
	t := new(CustomNodeType, heap)
	t.path = strings.clone(path, heap)
	t.name = strings.clone(name, heap)
	t.base = strings.clone(base, heap)
	t.script = strings.clone(str(obj, "script"), heap)
	t.icon = strings.clone(str(obj, "icon"), heap)
	t.color = strings.clone(str(obj, "color"), heap)
	t.category = strings.clone(str(obj, "category"), heap)
	t.description = strings.clone(str(obj, "description"), heap)
	t.defaults = strings.clone(defaults, heap)
	t.inherits = strings.clone(inherits, heap)
	return t, ""
}

// (Types being loaded through "inherits": loops.)
@(private = "file")
customGetDepth: int

// CustomNode_Get: the type in a .node.json (read once; nil and why when it
// can't be loaded).
CustomNode_Get :: proc(ctx: ^GameContext, path: string) -> (^CustomNodeType, string) {
	reg := custom_registry(ctx)
	if t, ok := reg.types[path]; ok do return t, ""
	if p, failed := reg.problems[path]; failed do return nil, p
	heap := Engine_HeapAllocator()
	t: ^CustomNodeType
	problem := "the file can't be read"
	if data, ok := Component_ReadFile(ctx, path); ok do t, problem = CustomNode_Parse(path, string(data))
	// Built on another type: its base type is the parent's.
	if t != nil && t.inherits != "" {
		parent: ^CustomNodeType
		why := "a loop of types inheriting each other"
		if customGetDepth < 16 && t.inherits != path {
			customGetDepth += 1
			parent, why = CustomNode_Get(ctx, t.inherits)
			customGetDepth -= 1
		}
		if parent == nil {
			problem = fmt.tprintf("its parent type %s: %s", t.inherits, why)
			free_custom_type(t)
			t = nil
		} else {
			delete(t.base, heap)
			t.base = strings.clone(parent.base, heap)
		}
	}
	if t == nil {
		reg.problems[strings.clone(path, heap)] = strings.clone(problem, heap)
		return nil, problem
	}
	reg.types[t.path] = t
	return t, ""
}

// CustomNodes_All: every type in the project, by name.
CustomNodes_All :: proc(ctx: ^GameContext) -> []^CustomNodeType {
	reg := custom_registry(ctx)
	if !reg.scanned {
		reg.scanned = true
		for path in custom_node_files(ctx) {
			if t, _ := CustomNode_Get(ctx, path); t != nil do append(&reg.list, t)
		}
		slice.sort_by(reg.list[:], proc(a, b: ^CustomNodeType) -> bool {return a.name < b.name})
	}
	return reg.list[:]
}

// CustomNode_FindByName: the project's type with that name (nil if none).
CustomNode_FindByName :: proc(ctx: ^GameContext, name: string) -> ^CustomNodeType {
	for t in CustomNodes_All(ctx) do if t.name == name do return t
	return nil
}

// custom_node_files: the project's .node.json files (the mounted package's
// entries, else the project folder; hidden folders skipped).
@(private = "file")
custom_node_files :: proc(ctx: ^GameContext) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	if ctx == nil || ctx.game == nil do return out[:]
	am := &ctx.game.assetManager
	if am.package_ != nil {
		for k in am.package_.entries do if strings.has_suffix(k, CUSTOM_NODE_SUFFIX) do append(&out, k)
	}
	if len(out) == 0 && am.projectDir != "" {
		abs, err := filepath.abs(am.projectDir, context.temp_allocator)
		if err == nil {
			for full in os.walk_files(abs) {
				if !strings.has_suffix(full, CUSTOM_NODE_SUFFIX) do continue
				rel, rerr := filepath.rel(abs, full, context.temp_allocator)
				if rerr != nil do continue
				rel, _ = strings.replace_all(rel, "\\", "/", context.temp_allocator)
				if strings.has_prefix(rel, ".") || strings.contains(rel, "/.") do continue
				append(&out, strings.clone(rel, context.temp_allocator))
			}
		}
	}
	slice.sort(out[:])
	return out[:]
}

// custom_base: the type as a node object - the base type's defaults, the
// type's defaults over them, its script with its property defaults - what
// a new node of it is, and what its nodes are compared with when saved.
@(private)
custom_base :: proc(t: ^CustomNodeType, ctx: ^GameContext) -> json.Object {
	// The defaults as a node of the base type writes them (every field of a
	// shape, not just the ones the file gives): built once on a scratch node.
	parent := custom_parent(t, ctx)
	if t.canonical == "" {
		base: json.Object
		ok: bool
		if parent != nil {
			_ = custom_base(parent, ctx) // (its canonical)
			val, err := json.parse(transmute([]u8)parent.canonical, allocator = context.temp_allocator)
			base, ok = val.(json.Object)
			ok = ok && err == .None
		} else {
			base, ok = type_defaults(t.base)
		}
		if !ok do base = make(json.Object, 0, context.temp_allocator)
		if val, err := json.parse(transmute([]u8)t.defaults, allocator = context.temp_allocator); err == .None {
			if d, isObj := val.(json.Object); isObj do merge_node(&base, d)
		}
		delete_key(&base, "script") // (added below: no script runs on the scratch node)
		delete_key(&base, "children")
		base["type"] = json.String(t.base)
		scratch := new(Scene)
		InitializeScene(scratch)
		text := "{}"
		if n := read_node(scratch, base, nil, nil, noCustom = true); n != nil {
			ProcessNodeQueues(scratch.manager, nil)
			text = Node_SerializeToJSON(n, scratch.manager, context.temp_allocator)
		}
		TerminateScene(scratch)
		free(scratch)
		t.canonical = strings.clone(text, Engine_HeapAllocator())
	}
	val, err := json.parse(transmute([]u8)t.canonical, allocator = context.temp_allocator)
	base, _ := val.(json.Object)
	if err != .None || base == nil do base = make(json.Object, 0, context.temp_allocator)
	delete_key(&base, "uid")
	if script := CustomNode_Script(t, ctx); script != "" {
		so := make(json.Object, 0, context.temp_allocator)
		so["properties"] = custom_script_defaults(t, ctx)
		so["path"] = json.String(script)
		base["script"] = so
	}
	base["type"] = json.String(t.base)
	base["name"] = json.String(t.name)
	normalize_base(&base, ctx) // (the script's property defaults)
	return base
}

// custom_parent: the type `t` builds on (nil = none).
@(private = "file")
custom_parent :: proc(t: ^CustomNodeType, ctx: ^GameContext) -> ^CustomNodeType {
	if t == nil || t.inherits == "" do return nil
	p, _ := CustomNode_Get(ctx, t.inherits)
	return p
}

// CustomNode_Script: the script a type's nodes run - its own, else its
// parent's ("" = none).
CustomNode_Script :: proc(t: ^CustomNodeType, ctx: ^GameContext) -> string {
	for x, i := t, 0; x != nil && i < 16; x, i = custom_parent(x, ctx), i + 1 {
		if x.script != "" do return x.script
	}
	return ""
}

// custom_script_defaults: the script property values the type (and the
// types it builds on) set - the parent's, then its own. (Only those: the
// rest are the script's own defaults.)
@(private = "file")
custom_script_defaults :: proc(t: ^CustomNodeType, ctx: ^GameContext, depth := 0) -> json.Object {
	out := make(json.Object, 0, context.temp_allocator)
	if parent := custom_parent(t, ctx); parent != nil && depth < 16 {
		for k, v in custom_script_defaults(parent, ctx, depth + 1) do out[k] = v
	}
	if dv, err := json.parse(transmute([]u8)t.defaults, allocator = context.temp_allocator); err == .None {
		if d, isObj := dv.(json.Object); isObj {
			if ds, has := d["script"].(json.Object); has {
				if dp, hasProps := ds["properties"].(json.Object); hasProps do for k, v in dp do out[k] = v
			}
		}
	}
	return out
}

// CustomNode_Inherits: is type `t` `ancestor`, or built on it (directly or not)?
CustomNode_Inherits :: proc(t: ^CustomNodeType, ancestorName: string, ctx: ^GameContext) -> bool {
	for x, i := t, 0; x != nil && i < 16; x, i = custom_parent(x, ctx), i + 1 {
		if x.name == ancestorName do return true
	}
	return false
}

// read_custom_node builds a node of a type: the type's keys, the node's own
// over them.
@(private)
read_custom_node :: proc(scene: ^Scene, typePath: string, obj: json.Object, parent: ^Node, ctx: ^GameContext) -> ^Node {
	t, problem := CustomNode_Get(ctx, typePath)
	if t == nil {
		log.warnf("[SceneLoader] %s: custom node type %s can't be loaded: %s - kept as its base type", sj_string(obj, "name", "?"), typePath, problem)
		node := read_node(scene, obj, parent, ctx, noCustom = true)
		if node == nil do return nil
		node.customType = strings.clone(typePath, node.allocator)
		node.customMissing = true
		own := make(json.Object, len(obj), context.temp_allocator)
		for k, v in obj do if k != "children" do own[k] = v
		w := Json_Writer{sb = strings.builder_make(context.temp_allocator)}
		Json_WriteValue(&w, own)
		node.customRaw = strings.clone(strings.to_string(w.sb), node.allocator)
		return node
	}
	merged := custom_base(t, ctx)
	bw := Json_Writer{sb = strings.builder_make(context.temp_allocator)}
	Json_WriteValue(&bw, merged) // (before the node's own: what it's compared with when saved)
	own := make(json.Object, len(obj), context.temp_allocator)
	for k, v in obj do if k != CUSTOM_NODE_KEY && k != "type" do own[k] = v
	merge_node(&merged, own)
	node := read_node(scene, merged, parent, ctx, noCustom = true)
	if node == nil do return nil
	node.customType = strings.clone(t.path, node.allocator)
	node.customBase = strings.clone(strings.to_string(bw.sb), node.allocator)
	return node
}

// Scene_CreateCustomNode adds a new node of a type (its defaults) under
// `parent` (the scene's root when nil).
Scene_CreateCustomNode :: proc(scene: ^Scene, t: ^CustomNodeType, parent: ^Node, ctx: ^GameContext) -> ^Node {
	if scene == nil || t == nil do return nil
	target := parent if parent != nil else scene.rootNode
	obj := make(json.Object, 1, context.temp_allocator)
	obj[CUSTOM_NODE_KEY] = json.String(t.path)
	return read_custom_node(scene, t.path, obj, target, ctx)
}

// Set while a custom node is written in full (to compare it with its type).
@(private)
serializeFullCustom: ^Node

// write_custom_node writes a custom node as its link and what differs from
// its type (keys in the order and layout the full node has).
@(private)
write_custom_node :: proc(w: ^Json_Writer, node: ^Node, manager: ^NodeManager) {
	full := Json_Writer{sb = strings.builder_make(context.temp_allocator), indent = w.indent}
	prev := serializeFullCustom
	serializeFullCustom = node
	write_node(&full, node, manager)
	serializeFullCustom = prev
	text := strings.to_string(full.sb)
	entries := json_top_entries(text)

	keep := make(map[string]bool, 16, context.temp_allocator)
	nulls := make([dynamic]string, context.temp_allocator)
	diff: json.Object
	t: ^CustomNodeType
	if !node.customMissing do t, _ = CustomNode_Get(node.gameContext, node.customType)
	if t != nil {
		val, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
		inst, _ := val.(json.Object)
		if err == .None && inst != nil {
			// Compared with what it was built from (the type may have changed since).
			base: json.Object
			if node.customBase != "" {
				bv, berr := json.parse(transmute([]u8)node.customBase, allocator = context.temp_allocator)
				if berr == .None do base, _ = bv.(json.Object)
			}
			if base == nil do base = custom_base(t, node.gameContext)
			diff, _ = diff_node(base, inst, false)
			for k, v in diff {
				if _, isNull := v.(json.Null); isNull {
					append(&nulls, k)
				} else {
					keep[k] = true
				}
			}
		}
	} else if node.customMissing {
		// As loaded (the type's file is missing): its own keys back.
		if val, err := json.parse(transmute([]u8)node.customRaw, allocator = context.temp_allocator); err == .None {
			if raw, isObj := val.(json.Object); isObj do for k in raw do keep[k] = true
		}
	}
	slice.sort(nulls[:])

	strings.write_byte(&w.sb, '{')
	w.indent += 1
	first := true
	linked := false
	for e in entries {
		direct := slice.contains(CUSTOM_DIRECT_KEYS, e.key)
		if !direct && !keep[e.key] do continue
		Json_Key(w, e.key, &first)
		// (Properties and the script's: only the changed ones, key by key.)
		if v, partial := diff[e.key]; partial && !direct && (e.key == "properties" || e.key == "script") {
			Json_WriteValue(w, v)
		} else {
			strings.write_string(&w.sb, e.value)
		}
		if e.key == "name" {
			Json_Key(w, CUSTOM_NODE_KEY, &first); Json_String(w, node.customType)
			linked = true
		}
	}
	if !linked {Json_Key(w, CUSTOM_NODE_KEY, &first); Json_String(w, node.customType)}
	for k in nulls {
		if slice.contains(CUSTOM_DIRECT_KEYS, k) do continue
		Json_Key(w, k, &first); strings.write_string(&w.sb, "null")
	}
	w.indent -= 1
	Json_NewLine(w)
	strings.write_byte(&w.sb, '}')
}

@(private = "file")
Json_Entry :: struct {
	key, value: string, // value: its text as written
}

// json_top_entries splits a JSON object's text into its top-level keys and
// their values' text (layout kept).
@(private = "file")
json_top_entries :: proc(text: string) -> []Json_Entry {
	out := make([dynamic]Json_Entry, context.temp_allocator)
	i := strings.index_byte(text, '{')
	if i < 0 do return out[:]
	i += 1
	skip_ws :: proc(s: string, i: int) -> int {
		j := i
		for j < len(s) && (s[j] == ' ' || s[j] == '\n' || s[j] == '\r' || s[j] == '\t') do j += 1
		return j
	}
	string_end :: proc(s: string, i: int) -> int { // i: at the opening quote; returns past the closing one
		j := i + 1
		for j < len(s) {
			if s[j] == '\\' {j += 2; continue}
			if s[j] == '"' do return j + 1
			j += 1
		}
		return len(s)
	}
	for {
		i = skip_ws(text, i)
		if i >= len(text) || text[i] == '}' do break
		if text[i] == ',' {i += 1; continue}
		if text[i] != '"' do break
		kEnd := string_end(text, i)
		key := text[i + 1:kEnd - 1]
		i = skip_ws(text, kEnd)
		if i < len(text) && text[i] == ':' do i += 1
		i = skip_ws(text, i)
		start, depth := i, 0
		for i < len(text) {
			c := text[i]
			if c == '"' {i = string_end(text, i); continue}
			if c == '{' || c == '[' do depth += 1
			if c == '}' || c == ']' {
				if depth == 0 do break
				depth -= 1
			}
			if c == ',' && depth == 0 do break
			i += 1
		}
		append(&out, Json_Entry{key, strings.trim_right_space(text[start:i])})
	}
	return out[:]
}

// Node_CustomType: the node's custom type (nil: none, or not loaded).
Node_CustomType :: proc(node: ^Node) -> ^CustomNodeType {
	if node == nil || node.customType == "" || node.customMissing do return nil
	t, _ := CustomNode_Get(node.gameContext, node.customType)
	return t
}

// Node_ClassName: the node's type as scripts see it - its custom type's
// name, else its built-in type.
Node_ClassName :: proc(node: ^Node) -> string {
	if t := Node_CustomType(node); t != nil do return t.name
	return Node_TypeName(node)
}

// Node_Is: is the node of that type - its custom type, its built-in type,
// or "Node" (every node)?
Node_Is :: proc(node: ^Node, typeName: string) -> bool {
	if node == nil do return false
	if typeName == "Node" || typeName == Node_TypeName(node) do return true
	if t := Node_CustomType(node); t != nil && CustomNode_Inherits(t, typeName, node.gameContext) do return true
	// A script built on a type's script (`extends`, #153): one of that type too.
	if inst := cast(^ScriptInstance)node.scriptInstance; inst != nil && node.gameContext != nil && node.gameContext.game != nil {
		if t := CustomNode_FindByName(node.gameContext, typeName); t != nil {
			if script := CustomNode_Script(t, node.gameContext); script != "" {
				return Script_Extends(&node.gameContext.game.scriptManager, inst.modulePath, script)
			}
		}
	}
	return false
}

// Scene_FindNodesOfType: the scene's nodes of a type (Node_Is), in tree order.
Scene_FindNodesOfType :: proc(scene: ^Scene, typeName: string, allocator := context.temp_allocator) -> []^Node {
	out := make([dynamic]^Node, allocator)
	if scene == nil || scene.manager == nil || scene.rootNode == nil do return out[:]
	walk :: proc(m: ^NodeManager, n: ^Node, typeName: string, out: ^[dynamic]^Node) {
		for c in GetChildrenView(m, n) {
			if c == nil || c.removing do continue
			if Node_Is(c, typeName) do append(out, c)
			walk(m, c, typeName, out)
		}
	}
	walk(scene.manager, scene.rootNode, typeName, &out)
	return out[:]
}

// CustomNode_Definition: what a .node.json says (CustomNode_DefinitionJSON
// writes it).
CustomNode_Definition :: struct {
	name, base, inherits, script, icon, color, category, description: string,
	defaults: string, // JSON object text ("" = none)
}

// CustomNode_DefinitionJSON: a type's file text (keys in a fixed order,
// empty ones left out).
CustomNode_DefinitionJSON :: proc(d: CustomNode_Definition, allocator := context.allocator) -> string {
	w := Json_Writer{sb = strings.builder_make(allocator)}
	strings.write_byte(&w.sb, '{')
	w.indent += 1
	first := true
	field :: proc(w: ^Json_Writer, k, v: string, first: ^bool) {
		if v == "" do return
		Json_Key(w, k, first); Json_String(w, v)
	}
	Json_Key(&w, FORMAT_KEY, &first); fmt.sbprintf(&w.sb, "%d", FORMAT_CURRENT[.CustomNode])
	field(&w, "name", d.name, &first)
	if d.inherits != "" do field(&w, "inherits", d.inherits, &first)
	else do field(&w, "base", d.base, &first)
	field(&w, "script", d.script, &first)
	field(&w, "icon", d.icon, &first)
	field(&w, "color", d.color, &first)
	field(&w, "category", d.category, &first)
	field(&w, "description", d.description, &first)
	if d.defaults != "" {
		if val, err := json.parse(transmute([]u8)d.defaults, allocator = context.temp_allocator); err == .None {
			if obj, isObj := val.(json.Object); isObj && len(obj) > 0 {
				Json_Key(&w, "defaults", &first)
				Json_WriteValue(&w, obj)
			}
		}
	}
	w.indent -= 1
	Json_NewLine(&w)
	strings.write_string(&w.sb, "}\n")
	return strings.to_string(w.sb)
}

// CustomNode_DefaultsFromNode: a configured node's values as a type's
// "defaults" (Save as Custom Node, a type's document) - what differs from
// its built-in type's defaults (`parent`: from that type's values), without
// its name, place, children or script file (its script's values are kept).
// JSON object text.
CustomNode_DefaultsFromNode :: proc(node: ^Node, manager: ^NodeManager, allocator := context.allocator, parent: ^CustomNodeType = nil) -> string {
	if node == nil do return "{}"
	prev := serializeFullCustom
	serializeFullCustom = node // (a custom node: all its values)
	text := Node_SerializeToJSON(node, manager, context.temp_allocator)
	serializeFullCustom = prev
	val, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	inst, isObj := val.(json.Object)
	if err != .None || !isObj do return strings.clone("{}", allocator)
	base: json.Object
	ok: bool
	if parent != nil {
		base, ok = custom_base(parent, node.gameContext), true
	} else {
		base, ok = type_defaults(Node_TypeName(node))
	}
	if !ok do base = make(json.Object, 0, context.temp_allocator)
	diff, _ := diff_node(base, inst, false)
	out := make(json.Object, 0, context.temp_allocator)
	for k, v in diff {
		if Custom_IsDirectKey(k) || k == "tags" && v == nil do continue
		if _, isNull := v.(json.Null); isNull do continue
		if k == "script" {
			// Its values, not its file (the type names its script).
			// (Only those that differ from the script's own defaults.)
			so, _ := inst["script"].(json.Object)
			props, hasProps := so["properties"].(json.Object)
			if !hasProps do continue
			defs: json.Object
			if bs, has := base["script"].(json.Object); has && parent != nil && json_equal(bs["path"], so["path"]) {
				defs, _ = bs["properties"].(json.Object) // (the parent type's values)
			} else {
				declared := make(json.Object, 1, context.temp_allocator)
				ds := make(json.Object, 1, context.temp_allocator)
				ds["path"] = so["path"]
				declared["script"] = ds
				normalize_base(&declared, node.gameContext)
				defs, _ = declared["script"].(json.Object)["properties"].(json.Object)
			}
			changed := make(json.Object, 0, context.temp_allocator)
			for pk, pv in props {
				dv, has := defs[pk]
				if !has || !json_equal(dv, pv) do changed[pk] = pv
			}
			if len(changed) > 0 {
				s := make(json.Object, 1, context.temp_allocator)
				s["properties"] = changed
				out[k] = s
			}
			continue
		}
		out[k] = v
	}
	w := Json_Writer{sb = strings.builder_make(allocator)}
	Json_WriteValue(&w, out)
	return strings.to_string(w.sb)
}

// Scene_RefreshCustomNodes rebuilds a scene's nodes of a type (and of the
// types built on it) from what they change, with the type as it is now (its
// file changed). A node inside a component instance: the instance is
// rebuilt. Returns how many were rebuilt; pointers into them are stale
// (callers keep the selection as paths).
Scene_RefreshCustomNodes :: proc(scene: ^Scene, typePath: string, ctx: ^GameContext) -> int {
	if scene == nil || scene.manager == nil do return 0
	targets := make([dynamic]^Node, context.temp_allocator)
	for n in scene.manager.nodes {
		if n == nil || n.removing || n.customType == "" do continue
		affected := n.customType == typePath
		for x, i := custom_parent(Node_CustomType(n), ctx), 0; !affected && x != nil && i < 16; x, i = custom_parent(x, ctx), i + 1 {
			if x.path == typePath do affected = true
		}
		if !affected do continue
		outer := n
		for p := GetParent(scene.manager, n); p != nil; p = GetParent(scene.manager, p) do if p.componentPath != "" do outer = p
		if !slice.contains(targets[:], outer) do append(&targets, outer)
	}
	// (A target inside another one: rebuilt with it.)
	count := 0
	for old in targets {
		skip := false
		for p := GetParent(scene.manager, old); p != nil; p = GetParent(scene.manager, p) do if slice.contains(targets[:], p) do skip = true
		if skip do continue
		if Scene_RebuildInstance(scene, old, "", ctx) != nil do count += 1
	}
	return count
}

// Node_FullJSON: a node's JSON with all its values (a custom node's too, not
// only what differs from its type).
Node_FullJSON :: proc(node: ^Node, manager: ^NodeManager, allocator := context.allocator) -> string {
	prev := serializeFullCustom
	serializeFullCustom = node
	defer serializeFullCustom = prev
	return Node_SerializeToJSON(node, manager, allocator)
}

// CustomNode_Rebase: a type's values for another base type - the new
// "defaults" (what the new base's node keeps of them) and what doesn't carry
// over (keys the new base doesn't have: "shapes", "properties.radius"...).
// Built on scratch nodes: the scene loader decides what applies.
CustomNode_Rebase :: proc(t: ^CustomNodeType, newBase: string, ctx: ^GameContext, allocator := context.allocator) -> (defaults: string, dropped: []string) {
	out := make([dynamic]string, allocator)
	scratch := new(Scene)
	InitializeScene(scratch)
	defer {
		TerminateScene(scratch)
		free(scratch)
	}
	old := Scene_CreateCustomNode(scratch, t, scratch.rootNode, ctx)
	if old == nil do return strings.clone("{}", allocator), out[:]
	ProcessNodeQueues(scratch.manager, ctx)
	oldVal, _ := json.parse(transmute([]u8)Node_FullJSON(old, scratch.manager, context.temp_allocator), allocator = context.temp_allocator)
	oldObj, _ := oldVal.(json.Object)
	obj := make(json.Object, len(oldObj), context.temp_allocator)
	for k, v in oldObj do if k != CUSTOM_NODE_KEY && k != "children" do obj[k] = v
	obj["type"] = json.String(newBase)
	fresh := read_node(scratch, obj, scratch.rootNode, ctx, noCustom = true)
	if fresh == nil do return strings.clone("{}", allocator), out[:]
	ProcessNodeQueues(scratch.manager, ctx)
	newVal, _ := json.parse(transmute([]u8)Node_SerializeToJSON(fresh, scratch.manager, context.temp_allocator), allocator = context.temp_allocator)
	newObj, _ := newVal.(json.Object)
	for k, v in oldObj {
		if Custom_IsDirectKey(k) || k == "script" || k == "uid" do continue
		nv, has := newObj[k]
		if !has {
			append(&out, strings.clone(k, allocator))
			continue
		}
		if k == "properties" {
			op, _ := v.(json.Object)
			np, _ := nv.(json.Object)
			for pk in op do if pk not_in np do append(&out, fmt.aprintf("properties.%s", pk, allocator = allocator))
		}
	}
	slice.sort(out[:])
	return CustomNode_DefaultsFromNode(fresh, scratch.manager, allocator), out[:]
}
