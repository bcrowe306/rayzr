package engine

import "core:encoding/json"
import "core:fmt"
import "core:reflect"
import "core:strconv"
import "core:strings"
import "core:unicode"
import rl "vendor:raylib"

// ============================================================================
// Reflected Node Properties
//
// Every struct field tagged `gui:"true"` is a node property: it is saved to
// and loaded from scene JSON, and the editor inspector shows an editor for
// it. Tags:
//   gui:"true"        expose the field
//   min:"0" max:"1"   value range (inspector drag limits)
//   save:"false"      runtime state: shown read-only, never saved
// A gui-tagged [dynamic]string is a String_List (one item a line). Nodes
// whose lists hold structs (a Table's rows, a Tree View's items...) add
// String_List properties through UI_LIST_PROPS (ui_list_props.odin) that
// read and write them as lines (#227).
// `using` fields are walked (so UIElement / Node fields are found) except the
// base Node, whose transform is handled explicitly. A gui-tagged field of
// struct type (e.g. ParticleEmitterNode.emitter) is walked with a prefix
// ("emitter.amount").
// ============================================================================

Property_Kind :: enum {
	Float,
	Int,
	Bool,
	Vec2,
	Color,
	Enum,
	Bit_Set,
	String,
	String_List, // [dynamic]string, or a list a node reads / writes as lines
}

Node_Property :: struct {
	name:      string, // path, e.g. "gravityScale" or "emitter.amount"
	kind:      Property_Kind,
	ptr:       rawptr,
	type:      ^reflect.Type_Info,
	min, max:  f32,
	has_range: bool,
	runtime:   bool, // save:"false"
	owner:     string, // the struct declaring the field ("CameraNode"), for Property_Doc
	// String_List adapters (ptr is then the node): the list as lines, and
	// back. nil: ptr is a ^[dynamic]string.
	list_get:  proc(node: ^Node, allocator := context.temp_allocator) -> []string,
	list_set:  proc(node: ^Node, items: []string),
}

// Node_CollectProperties lists the reflected properties of a node's concrete
// type (temp-allocated by default).
Node_CollectProperties :: proc(node: ^Node, allocator := context.temp_allocator) -> []Node_Property {
	out := make([dynamic]Node_Property, allocator)
	if node == nil || node.typeId == nil || node.typeId == Node do return out[:]
	collect_struct_props(&out, node.typeId, rawptr(node), "", allocator)
	for lp in UI_LIST_PROPS do if lp.type == node.typeId {
		append(&out, Node_Property{name = lp.name, kind = .String_List, ptr = rawptr(node), type = type_info_of([]string), owner = lp.owner, list_get = lp.get, list_set = lp.set})
	}
	return out[:]
}

// Struct_CollectProperties lists the gui-tagged fields of any struct value
// (e.g. a PhysicsShape).
Struct_CollectProperties :: proc(tid: typeid, base: rawptr, allocator := context.temp_allocator) -> []Node_Property {
	out := make([dynamic]Node_Property, allocator)
	collect_struct_props(&out, tid, base, "", allocator)
	return out[:]
}

// Node_FindProperty looks a property up by path.
Node_FindProperty :: proc(node: ^Node, name: string) -> (Node_Property, bool) {
	if p, ok := node_find_property_exact(node, name); ok do return p, true
	// Scripts may use other names for it (#327): the snake_case form of the
	// Inspector's camelCase name (z_index, emitter.gravity_velocity), or a
	// renamed property's new name.
	if alias := Property_Alias(node, name); alias != "" do return node_find_property_exact(node, alias)
	if strings.contains_rune(name, '_') {
		if camel := Property_CamelName(name); camel != name do return node_find_property_exact(node, camel)
	}
	return {}, false
}

@(private = "file")
node_find_property_exact :: proc(node: ^Node, name: string) -> (Node_Property, bool) {
	for p in Node_CollectProperties(node) {
		if p.name == name do return p, true
	}
	return Node_BaseProperty(node, name)
}

// Property_CamelName: a snake_case property path in the Inspector's form,
// segment by segment ("emitter.gravity_velocity" -> "emitter.gravityVelocity").
Property_CamelName :: proc(name: string, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make(allocator)
	up := false
	for r in name {
		if r == '_' {up = true; continue}
		if r == '.' do up = false
		strings.write_rune(&sb, unicode.to_upper(r) if up else r)
		up = false
	}
	return strings.to_string(sb)
}

// Property_SnakeName: the snake_case form scripts use for an Inspector
// property path ("zIndex" -> "z_index", "emitter.gravityVelocity" ->
// "emitter.gravity_velocity").
Property_SnakeName :: proc(name: string, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make(allocator)
	prev: rune
	for r in name {
		if unicode.is_upper(r) {
			if prev != 0 && prev != '.' && prev != '_' do strings.write_byte(&sb, '_')
			strings.write_rune(&sb, unicode.to_lower(r))
		} else {
			strings.write_rune(&sb, r)
		}
		prev = r
	}
	return strings.to_string(sb)
}

// Property_ScriptName: the name scripts use for an Inspector property path
// (its snake_case form, or the new name of a renamed one).
Property_ScriptName :: proc(node: ^Node, name: string, allocator := context.temp_allocator) -> string {
	if node != nil && node.typeId == PathFollowNode && name == "rotate" do return "face_direction"
	// Their snake_case forms are methods (is_paused(), is_awake()): the
	// properties keep the Inspector's names.
	if name == "isPaused" || name == "isAwake" do return name
	return Property_SnakeName(name, allocator)
}

// Property_Alias: the Inspector name of a property a script knows by
// another name ("" = none) - one renamed because a node method shares it.
Property_Alias :: proc(node: ^Node, name: string) -> string {
	if node == nil do return ""
	switch {
	case node.typeId == PathFollowNode && (name == "face_direction" || name == "faceDirection"):
		return "rotate" // (`rotate` is also Node:rotate(): follower.rotate reads the method)
	}
	return ""
}

// Node_BaseProperty: a field every node has (the Inspector's Transform
// section): position, rotation, scale, layer, zIndex, ySort, ySortOffset,
// pauseMode, paused, enabled, visible;
// origin (Node.pivot) for the nodes that have one.
Node_BaseProperty :: proc(node: ^Node, name: string) -> (Node_Property, bool) {
	if node == nil do return {}, false
	p := Node_Property{name = name, owner = "Node"}
	switch name {
	case "position": p.kind, p.ptr, p.type = .Vec2, &node.position, type_info_of([2]f32)
	case "scale":    p.kind, p.ptr, p.type = .Vec2, &node.scale, type_info_of([2]f32)
	case "rotation": p.kind, p.ptr, p.type = .Float, &node.rotation, type_info_of(f32)
	case "origin":
		if !Node_HasOrigin(node) do return {}, false
		p.kind, p.ptr, p.type = .Vec2, &node.pivot, type_info_of([2]f32)
	case "layer":    p.kind, p.ptr, p.type = .Enum, &node.layer, type_info_of(RenderLayer)
	case "zIndex":   p.kind, p.ptr, p.type = .Int, &node.zIndex, type_info_of(i32)
	case "ySort":    p.kind, p.ptr, p.type = .Bool, &node.ySort, type_info_of(bool)
	case "ySortOffset": p.kind, p.ptr, p.type = .Float, &node.ySortOffset, type_info_of(f32)
	case "pauseMode": p.kind, p.ptr, p.type = .Enum, &node.pauseMode, type_info_of(Pause_Mode)
	case "paused":   p.kind, p.ptr, p.type = .Bool, &node.paused, type_info_of(bool)
	case "enabled":  p.kind, p.ptr, p.type = .Bool, &node.enabled, type_info_of(bool)
	case "visible":  p.kind, p.ptr, p.type = .Bool, &node.renderable, type_info_of(bool) // (set_visible / is_visible)
	case: return node_type_property(node, name)
	}
	return p, true
}

// node_type_property: settings a node type shows in its own Inspector rows
// (not reflected, saved by the type): AnimationPlayer fps / defaultAnimation.
@(private = "file")
node_type_property :: proc(node: ^Node, name: string) -> (Node_Property, bool) {
	if node.typeId == AnimationPlayerNode {
		apn := cast(^AnimationPlayerNode)node
		p := Node_Property{name = name, owner = "AnimationPlayerNode"}
		switch name {
		case "fps":
			p.kind, p.ptr, p.type = .Float, &apn.fps, type_info_of(f32)
			p.min, p.max, p.has_range = 1, 120, true
			return p, true
		case "defaultAnimation":
			p.kind, p.ptr, p.type = .String, &apn.defaultAnimation, type_info_of(string)
			return p, true
		}
	}
	return {}, false
}

// Node_PropertyChanged applies a property written by path (set_property)
// that needs more than the field: an AnimationPlayer's fps retimes it.
Node_PropertyChanged :: proc(node: ^Node, name: string) {
	if node.typeId == AnimationPlayerNode && name == "fps" {
		apn := cast(^AnimationPlayerNode)node
		AnimationPlayerNode_SetFPS(apn, apn.fps)
	}
}

@(private = "file")
collect_struct_props :: proc(out: ^[dynamic]Node_Property, tid: typeid, base: rawptr, prefix: string, allocator := context.temp_allocator) {
	for f in reflect.struct_fields_zipped(tid) {
		ptr := rawptr(uintptr(base) + f.offset)
		if f.is_using {
			if f.type.id == Node do continue
			collect_struct_props(out, f.type.id, ptr, prefix, allocator)
			continue
		}
		gui, has_gui := reflect.struct_tag_lookup(f.tag, "gui")
		if !has_gui || gui != "true" do continue

		name := f.name if prefix == "" else strings.concatenate({prefix, f.name}, allocator)
		kind, ok := property_kind(f.type)
		if !ok {
			// A tagged struct (not a value type we edit directly): walk it.
			if _, is_struct := reflect.type_info_base(f.type).variant.(reflect.Type_Info_Struct); is_struct {
				collect_struct_props(out, f.type.id, ptr, strings.concatenate({name, "."}, allocator), allocator)
			}
			continue
		}
		p := Node_Property{name = name, kind = kind, ptr = ptr, type = f.type, owner = struct_name(tid)}
		if mn, has_min := reflect.struct_tag_lookup(f.tag, "min"); has_min {
			if v, vok := strconv.parse_f32(mn); vok {p.min = v; p.has_range = true}
		}
		if mx, has_max := reflect.struct_tag_lookup(f.tag, "max"); has_max {
			if v, vok := strconv.parse_f32(mx); vok {p.max = v; p.has_range = true}
		}
		if sv, has_save := reflect.struct_tag_lookup(f.tag, "save"); has_save && sv == "false" {
			p.runtime = true
		}
		append(out, p)
	}
}

@(private = "file")
struct_name :: proc(tid: typeid) -> string {
	if named, ok := type_info_of(tid).variant.(reflect.Type_Info_Named); ok do return named.name
	return ""
}

@(private = "file")
property_kind :: proc(ti: ^reflect.Type_Info) -> (Property_Kind, bool) {
	if ti.id == rl.Color do return .Color, true
	#partial switch v in reflect.type_info_base(ti).variant {
	case reflect.Type_Info_Float:
		return .Float, true
	case reflect.Type_Info_Integer:
		return .Int, true
	case reflect.Type_Info_Boolean:
		return .Bool, true
	case reflect.Type_Info_Enum:
		return .Enum, true
	case reflect.Type_Info_Bit_Set:
		if _, is_enum := reflect.type_info_base(v.elem).variant.(reflect.Type_Info_Enum); is_enum {
			return .Bit_Set, true
		}
	case reflect.Type_Info_String:
		return .String, true
	case reflect.Type_Info_Array:
		if v.count == 2 && v.elem.id == f32 do return .Vec2, true
	case reflect.Type_Info_Dynamic_Array:
		if v.elem.id == string do return .String_List, true
	}
	return .Float, false
}

// --- typed access -----------------------------------------------------------

Property_GetFloat :: proc(p: Node_Property) -> f32 {
	#partial switch v in reflect.type_info_base(p.type).variant {
	case reflect.Type_Info_Float:
		if p.type.size == 8 do return f32((^f64)(p.ptr)^)
		return (^f32)(p.ptr)^
	}
	return 0
}

Property_SetFloat :: proc(p: Node_Property, value: f32) {
	#partial switch v in reflect.type_info_base(p.type).variant {
	case reflect.Type_Info_Float:
		if p.type.size == 8 {
			(^f64)(p.ptr)^ = f64(value)
		} else {
			(^f32)(p.ptr)^ = value
		}
	}
}

Property_GetInt :: proc(p: Node_Property) -> i64 {
	v, _ := reflect.as_i64(any{p.ptr, p.type.id})
	return v
}

Property_SetInt :: proc(p: Node_Property, value: i64) {
	switch p.type.size {
	case 1: (^i8)(p.ptr)^ = i8(value)
	case 2: (^i16)(p.ptr)^ = i16(value)
	case 4: (^i32)(p.ptr)^ = i32(value)
	case 8: (^i64)(p.ptr)^ = value
	}
}

// Enum values are handled through their names (ordered as declared).
Property_EnumNames :: proc(p: Node_Property) -> []string {
	ti := p.type
	if p.kind == .Bit_Set {
		bs := reflect.type_info_base(p.type).variant.(reflect.Type_Info_Bit_Set)
		ti = bs.elem
	}
	if e, ok := reflect.type_info_base(ti).variant.(reflect.Type_Info_Enum); ok {
		return e.names
	}
	return nil
}

@(private = "file")
enum_values :: proc(p: Node_Property) -> []reflect.Type_Info_Enum_Value {
	ti := p.type
	if p.kind == .Bit_Set {
		ti = reflect.type_info_base(p.type).variant.(reflect.Type_Info_Bit_Set).elem
	}
	if e, ok := reflect.type_info_base(ti).variant.(reflect.Type_Info_Enum); ok {
		return e.values
	}
	return nil
}

// Property_GetEnumIndex returns the declared index of the current value.
Property_GetEnumIndex :: proc(p: Node_Property) -> int {
	cur := Property_GetInt(p)
	for v, i in enum_values(p) {
		if i64(v) == cur do return i
	}
	return 0
}

Property_SetEnumIndex :: proc(p: Node_Property, index: int) {
	values := enum_values(p)
	if index >= 0 && index < len(values) {
		Property_SetInt(p, i64(values[index]))
	}
}

// Bit sets: membership by declared enum index.
Property_BitSetHas :: proc(p: Node_Property, index: int) -> bool {
	values := enum_values(p)
	if index < 0 || index >= len(values) do return false
	bs := reflect.type_info_base(p.type).variant.(reflect.Type_Info_Bit_Set)
	bit := u64(i64(values[index]) - bs.lower)
	return (bitset_bits(p) >> bit) & 1 == 1
}

Property_BitSetSet :: proc(p: Node_Property, index: int, on: bool) {
	values := enum_values(p)
	if index < 0 || index >= len(values) do return
	bs := reflect.type_info_base(p.type).variant.(reflect.Type_Info_Bit_Set)
	bit := u64(i64(values[index]) - bs.lower)
	bits := bitset_bits(p)
	bits = bits | (1 << bit) if on else bits & ~(u64(1) << bit)
	switch p.type.size {
	case 1: (^u8)(p.ptr)^ = u8(bits)
	case 2: (^u16)(p.ptr)^ = u16(bits)
	case 4: (^u32)(p.ptr)^ = u32(bits)
	case 8: (^u64)(p.ptr)^ = bits
	}
}

@(private = "file")
bitset_bits :: proc(p: Node_Property) -> u64 {
	switch p.type.size {
	case 1: return u64((^u8)(p.ptr)^)
	case 2: return u64((^u16)(p.ptr)^)
	case 4: return u64((^u32)(p.ptr)^)
	case 8: return (^u64)(p.ptr)^
	}
	return 0
}

// Property_SetString replaces a string property, cloning into the node's
// allocator (the old value is left to the node arena).
Property_SetString :: proc(node: ^Node, p: Node_Property, value: string) {
	(^string)(p.ptr)^ = strings.clone(value, node.allocator)
}

// Property_GetList: a String_List's items (allocator: the slice; the strings
// are the node's).
Property_GetList :: proc(p: Node_Property, allocator := context.temp_allocator) -> []string {
	if p.list_get != nil do return p.list_get(cast(^Node)p.ptr, allocator)
	return (^[dynamic]string)(p.ptr)[:]
}

// Property_SetList replaces a String_List's items (copied to the node).
Property_SetList :: proc(node: ^Node, p: Node_Property, items: []string) {
	if p.list_set != nil {
		p.list_set(node, items)
		return
	}
	list := (^[dynamic]string)(p.ptr)
	if list^ == nil do list^ = make([dynamic]string, node.allocator)
	clear(list)
	for it in items do append(list, strings.clone(it, node.allocator))
}

// --- colours ------------------------------------------------------------------

Color_ToHex :: proc(c: rl.Color, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("#%02x%02x%02x%02x", c.r, c.g, c.b, c.a, allocator = allocator)
}

Color_FromHex :: proc(s: string) -> (c: rl.Color, ok: bool) {
	h := strings.trim_prefix(strings.trim_space(s), "#")
	parse :: proc(h: string, i: int) -> (u8, bool) {
		v, ok := strconv.parse_uint(h[i:i + 2], 16)
		return u8(v), ok
	}
	switch len(h) {
	case 6, 8:
		r, ok1 := parse(h, 0)
		g, ok2 := parse(h, 2)
		b, ok3 := parse(h, 4)
		a: u8 = 255
		ok4 := true
		if len(h) == 8 do a, ok4 = parse(h, 6)
		if ok1 && ok2 && ok3 && ok4 do return {r, g, b, a}, true
	}
	return
}

// --- JSON -------------------------------------------------------------------------

// Property_WriteJSON writes the property's value as a JSON value.
Property_WriteJSON :: proc(w: ^Json_Writer, p: Node_Property) {
	switch p.kind {
	case .Float:
		Json_Float(w, Property_GetFloat(p))
	case .Int:
		fmt.sbprintf(&w.sb, "%d", Property_GetInt(p))
	case .Bool:
		strings.write_string(&w.sb, "true" if (^bool)(p.ptr)^ else "false")
	case .Vec2:
		v := (^[2]f32)(p.ptr)^
		Json_Vec2(w, v)
	case .Color:
		Json_String(w, Color_ToHex((^rl.Color)(p.ptr)^))
	case .Enum:
		names := Property_EnumNames(p)
		idx := Property_GetEnumIndex(p)
		Json_String(w, names[idx] if idx < len(names) else "")
	case .Bit_Set:
		names := Property_EnumNames(p)
		strings.write_byte(&w.sb, '[')
		first := true
		for n, i in names {
			if Property_BitSetHas(p, i) {
				if !first do strings.write_string(&w.sb, ", ")
				Json_String(w, n)
				first = false
			}
		}
		strings.write_byte(&w.sb, ']')
	case .String:
		Json_String(w, (^string)(p.ptr)^)
	case .String_List:
		strings.write_byte(&w.sb, '[')
		for it, i in Property_GetList(p) {
			if i > 0 do strings.write_string(&w.sb, ", ")
			Json_String(w, it)
		}
		strings.write_byte(&w.sb, ']')
	}
}

// Property_ReadJSON sets the property from a JSON value; mismatched values
// are ignored.
Property_ReadJSON :: proc(node: ^Node, p: Node_Property, value: json.Value) {
	switch p.kind {
	case .Float:
		if f, ok := json_number(value); ok do Property_SetFloat(p, f)
	case .Int:
		#partial switch v in value {
		case json.Integer: Property_SetInt(p, i64(v))
		case json.Float: Property_SetInt(p, i64(v))
		}
	case .Bool:
		if b, ok := value.(json.Boolean); ok do (^bool)(p.ptr)^ = bool(b)
	case .Vec2:
		if arr, ok := value.(json.Array); ok && len(arr) >= 2 {
			x, okx := json_number(arr[0])
			y, oky := json_number(arr[1])
			if okx && oky do (^[2]f32)(p.ptr)^ = {x, y}
		}
	case .Color:
		#partial switch v in value {
		case json.String:
			if c, ok := Color_FromHex(v); ok do (^rl.Color)(p.ptr)^ = c
		case json.Array:
			if len(v) >= 3 {
				c: rl.Color = {0, 0, 0, 255}
				comps := [4]^u8{&c.r, &c.g, &c.b, &c.a}
				for i in 0 ..< min(4, len(v)) {
					if f, ok := json_number(v[i]); ok do comps[i]^ = u8(clamp(f, 0, 255))
				}
				(^rl.Color)(p.ptr)^ = c
			}
		}
	case .Enum:
		if s, ok := value.(json.String); ok {
			for n, i in Property_EnumNames(p) {
				if strings.equal_fold(n, s) do Property_SetEnumIndex(p, i)
			}
		}
	case .Bit_Set:
		if arr, ok := value.(json.Array); ok {
			names := Property_EnumNames(p)
			for i in 0 ..< len(names) do Property_BitSetSet(p, i, false)
			for item in arr {
				if s, is_str := item.(json.String); is_str {
					for n, i in names {
						if strings.equal_fold(n, s) do Property_BitSetSet(p, i, true)
					}
				}
			}
		}
	case .String:
		if s, ok := value.(json.String); ok do Property_SetString(node, p, s)
	case .String_List:
		if arr, ok := value.(json.Array); ok {
			items := make([dynamic]string, context.temp_allocator)
			for it in arr do if s, is_str := it.(json.String); is_str do append(&items, string(s))
			Property_SetList(node, p, items[:])
		}
	}
}

json_number :: proc(v: json.Value) -> (f32, bool) {
	#partial switch n in v {
	case json.Float: return f32(n), true
	case json.Integer: return f32(n), true
	}
	return 0, false
}

// ============================================================================
// Minimal JSON writer: escaped strings, stable number formatting, indentation.
// ============================================================================

Json_Writer :: struct {
	sb:     strings.Builder,
	indent: int,
}

Json_NewLine :: proc(w: ^Json_Writer) {
	strings.write_byte(&w.sb, '\n')
	for _ in 0 ..< w.indent do strings.write_string(&w.sb, "  ")
}

Json_String :: proc(w: ^Json_Writer, s: string) {
	strings.write_byte(&w.sb, '"')
	for r in s {
		switch r {
		case '"': strings.write_string(&w.sb, `\"`)
		case '\\': strings.write_string(&w.sb, `\\`)
		case '\n': strings.write_string(&w.sb, `\n`)
		case '\r': strings.write_string(&w.sb, `\r`)
		case '\t': strings.write_string(&w.sb, `\t`)
		case:
			if r < 0x20 {
				fmt.sbprintf(&w.sb, "\\u%04x", int(r))
			} else {
				strings.write_rune(&w.sb, r)
			}
		}
	}
	strings.write_byte(&w.sb, '"')
}

// Json_Float writes up to 4 decimals without trailing zeros ("0.455", "640").
Json_Float :: proc(w: ^Json_Writer, f: f32) {
	s := fmt.tprintf("%.4f", f)
	if strings.contains_rune(s, '.') {
		s = strings.trim_right(s, "0")
		s = strings.trim_suffix(s, ".")
	}
	if s == "-0" do s = "0"
	strings.write_string(&w.sb, s)
}

Json_Vec2 :: proc(w: ^Json_Writer, v: [2]f32) {
	strings.write_byte(&w.sb, '[')
	Json_Float(w, v.x)
	strings.write_string(&w.sb, ", ")
	Json_Float(w, v.y)
	strings.write_byte(&w.sb, ']')
}

Json_Rect :: proc(w: ^Json_Writer, r: rl.Rectangle) {
	strings.write_byte(&w.sb, '[')
	Json_Float(w, r.x)
	strings.write_string(&w.sb, ", ")
	Json_Float(w, r.y)
	strings.write_string(&w.sb, ", ")
	Json_Float(w, r.width)
	strings.write_string(&w.sb, ", ")
	Json_Float(w, r.height)
	strings.write_byte(&w.sb, ']')
}

// Json_Key starts `"key": ` on a new line, preceded by a comma unless first.
Json_Key :: proc(w: ^Json_Writer, key: string, first: ^bool) {
	if !first^ do strings.write_byte(&w.sb, ',')
	first^ = false
	Json_NewLine(w)
	Json_String(w, key)
	strings.write_string(&w.sb, ": ")
}
