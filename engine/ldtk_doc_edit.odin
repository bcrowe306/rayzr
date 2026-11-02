package engine

import "core:fmt"
import "core:math"
import "core:mem"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Ldtk_Doc editing: entities, field values, levels, layer instances
//
// These write the JSON the way LDtk does (key order, the "__" cached fields
// game readers use, realEditorValues alongside __value), so LDtk opens the
// result as if it had saved it. Take an undo step first with
// Ldtk_Doc_Checkpoint (level edits: the level index; structural edits: -1).
// ============================================================================

@(private = "file")
jint :: proc(v: int, a: mem.Allocator) -> ^LdtkJson {return LdtkJson_NewInt(v, a)}
@(private = "file")
jstr :: proc(s: string, a: mem.Allocator) -> ^LdtkJson {return LdtkJson_NewString(s, a)}
@(private = "file")
jnull :: proc(a: mem.Allocator) -> ^LdtkJson {return LdtkJson_New(.Null, a)}
@(private = "file")
jarr :: proc(a: mem.Allocator, items: ..^LdtkJson) -> ^LdtkJson {
	arr := LdtkJson_New(.Array, a)
	append(&arr.items, ..items)
	return arr
}
@(private = "file")
jadd :: proc(o: ^LdtkJson, key: string, v: ^LdtkJson, a: mem.Allocator) {
	append(&o.keys, strings.clone(key, a))
	append(&o.items, v)
}

Ldtk_ColorHex :: proc(c: rl.Color, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("#%02X%02X%02X", c.r, c.g, c.b, allocator = allocator)
}

// ----------------------------------------------------------------------------
// Field values
// ----------------------------------------------------------------------------

Ldtk_FieldKind :: enum u8 {
	Other,
	Int,
	Float,
	Bool,
	String,
	Text,
	Color,
	Enum,
	Point,
	Path,
	EntityRef,
	Tile,
}

// Ldtk_FieldKindOf reads a field def's "type" ("F_Int", "F_Enum(12)", ...).
Ldtk_FieldKindOf :: proc(fieldDef: ^LdtkJson) -> Ldtk_FieldKind {
	t := LdtkJson_Str(fieldDef, "type")
	switch {
	case t == "F_Int": return .Int
	case t == "F_Float": return .Float
	case t == "F_Bool": return .Bool
	case t == "F_String": return .String
	case t == "F_Text": return .Text
	case t == "F_Color": return .Color
	case strings.has_prefix(t, "F_Enum"): return .Enum
	case t == "F_Point": return .Point
	case t == "F_Path": return .Path
	case t == "F_EntityRef": return .EntityRef
	case t == "F_Tile": return .Tile
	}
	return .Other
}

// Ldtk_FieldEnumUid: the enum def uid of an F_Enum(uid) field (-1 if none).
Ldtk_FieldEnumUid :: proc(fieldDef: ^LdtkJson) -> int {
	return Ldtk_FieldTypeEnumUid(LdtkJson_Str(fieldDef, "type"))
}

// Ldtk_FieldTypeEnumUid: the uid in "F_Enum(<uid>)" (-1 otherwise).
Ldtk_FieldTypeEnumUid :: proc(t: string) -> int {
	if !strings.has_prefix(t, "F_Enum(") || !strings.has_suffix(t, ")") do return -1
	v, ok := strconv.parse_int(t[7:len(t) - 1])
	return v if ok else -1
}

Ldtk_Doc_EnumDef :: proc(doc: ^Ldtk_Doc, uid: int) -> ^LdtkJson {
	defs := LdtkJson_Get(doc.root, "defs")
	for key in ([]string{"enums", "externalEnums"}) {
		for e in LdtkJson_Arr(defs, key) do if LdtkJson_Int(e, "uid", -1) == uid do return e
	}
	return nil
}

// ldtk_field_default: (json __value, internal ValueWrapper or nil) of a
// field def's default, as FieldInstance does it.
@(private = "file")
ldtk_field_default :: proc(doc: ^Ldtk_Doc, fd: ^LdtkJson, a: mem.Allocator) -> (^LdtkJson, ^LdtkJson) {
	kind := Ldtk_FieldKindOf(fd)
	canBeNull := LdtkJson_Bool(fd, "canBeNull")
	over := LdtkJson_Get(fd, "defaultOverride")
	param: ^LdtkJson
	if over != nil && over.kind == .Object {
		if p := LdtkJson_Arr(over, "params"); len(p) > 0 do param = p[0]
	}
	switch kind {
	case .Int, .Float:
		if param != nil && param.kind == .Number do return LdtkJson_NewFloat(param.num, a), nil
		if canBeNull do return jnull(a), nil
		mn := LdtkJson_Get(fd, "min")
		v := 0.0
		if mn != nil && mn.kind == .Number && mn.num > 0 do v = mn.num
		return LdtkJson_NewFloat(v, a), nil
	case .Bool:
		if param != nil && param.kind == .Bool do return LdtkJson_NewBool(param.b, a), nil
		return LdtkJson_NewBool(false, a), nil
	case .String, .Text, .Path:
		if param != nil && param.kind == .String do return jstr(param.text, a), nil
		if canBeNull || kind == .Path do return jnull(a), nil
		return jstr("", a), nil
	case .Color:
		c := 0
		if param != nil && param.kind == .Number do c = int(param.num)
		return jstr(fmt.tprintf("#%06X", c & 0xFFFFFF), a), nil
	case .Enum:
		if param != nil && param.kind == .String do return jstr(param.text, a), nil
		if !canBeNull {
			if ed := Ldtk_Doc_EnumDef(doc, Ldtk_FieldEnumUid(fd)); ed != nil {
				if vals := LdtkJson_Arr(ed, "values"); len(vals) > 0 do return jstr(LdtkJson_Str(vals[0], "id"), a), nil
			}
		}
		return jnull(a), nil
	case .Point, .EntityRef, .Tile, .Other:
	}
	return jnull(a), nil
}

// Ldtk_Doc_NewFieldInstance builds a default field instance for a field def.
Ldtk_Doc_NewFieldInstance :: proc(doc: ^Ldtk_Doc, fd: ^LdtkJson, a: mem.Allocator) -> ^LdtkJson {
	o := LdtkJson_New(.Object, a)
	jadd(o, "__identifier", jstr(LdtkJson_Str(fd, "identifier"), a), a)
	jadd(o, "__type", jstr(LdtkJson_Str(fd, "__type"), a), a)
	if LdtkJson_Bool(fd, "isArray") {
		jadd(o, "__value", LdtkJson_New(.Array, a), a)
	} else {
		v, _ := ldtk_field_default(doc, fd, a)
		jadd(o, "__value", v, a)
	}
	jadd(o, "__tile", jnull(a), a)
	jadd(o, "defUid", jint(LdtkJson_Int(fd, "uid"), a), a)
	jadd(o, "realEditorValues", LdtkJson_New(.Array, a), a)
	return o
}

// Ldtk_Doc_FieldDef finds an entity / level field def by uid.
Ldtk_Doc_FieldDef :: proc(doc: ^Ldtk_Doc, uid: int) -> ^LdtkJson {
	defs := LdtkJson_Get(doc.root, "defs")
	for f in LdtkJson_Arr(defs, "levelFields") do if LdtkJson_Int(f, "uid", -1) == uid do return f
	for e in LdtkJson_Arr(defs, "entities") {
		for f in LdtkJson_Arr(e, "fieldDefs") do if LdtkJson_Int(f, "uid", -1) == uid do return f
	}
	return nil
}

// ldtk_wrap: {"id": "V_Int", "params": [v]}
@(private = "file")
ldtk_wrap :: proc(id: string, v: ^LdtkJson, a: mem.Allocator) -> ^LdtkJson {
	o := LdtkJson_New(.Object, a)
	jadd(o, "id", jstr(id, a), a)
	jadd(o, "params", jarr(a, v), a)
	return o
}

// Ldtk_Doc_SetFieldValue sets a single (non-array) field instance from
// text: numbers, "true"/"false", strings, "#RRGGBB" colours, enum value ids,
// "cx,cy" points; "" (or "null") clears nullable fields. Returns false when
// the text does not fit the type.
Ldtk_Doc_SetFieldValue :: proc(doc: ^Ldtk_Doc, fi: ^LdtkJson, text: string) -> bool {
	fd := Ldtk_Doc_FieldDef(doc, LdtkJson_Int(fi, "defUid", -1))
	if fd == nil || LdtkJson_Bool(fd, "isArray") do return false
	t := strings.trim_space(text) == "null" ? "" : text
	return Ldtk_Doc_SetFieldRaw(doc, fi, 0, t)
}

// Ldtk_FieldText: a field instance's value as text (for editing).
Ldtk_FieldText :: proc(fi: ^LdtkJson) -> string {
	v := LdtkJson_Get(fi, "__value")
	if v == nil do return ""
	switch v.kind {
	case .Null: return ""
	case .Bool: return v.b ? "true" : "false"
	case .Number:
		b := strings.builder_make(context.temp_allocator)
		ldtk_js_number(&b, v.num)
		return strings.to_string(b)
	case .String: return v.text
	case .Object:
		if LdtkJson_Get(v, "cx") != nil do return fmt.tprintf("%d,%d", LdtkJson_Int(v, "cx"), LdtkJson_Int(v, "cy"))
		if iid := LdtkJson_Str(v, "entityIid"); iid != "" do return iid
		return LdtkJson_ToString(v, .Minified, context.temp_allocator)
	case .Array: return LdtkJson_ToString(v, .Minified, context.temp_allocator)
	}
	return ""
}

// ----------------------------------------------------------------------------
// Entities
// ----------------------------------------------------------------------------

Ldtk_Doc_Entities :: proc(doc: ^Ldtk_Doc, li, layer: int) -> []^LdtkJson {
	return LdtkJson_Arr(doc.levels[li].layers[layer].obj, "entityInstances")
}

// Ldtk_Doc_LevelPos: a level's world position (computed in the linear
// layouts, like World.reorganizeWorld: in file order, 48 px apart).
Ldtk_Doc_LevelPos :: proc(doc: ^Ldtk_Doc, li: int) -> [2]int {
	lv := &doc.levels[li]
	layout := LdtkJson_Str(doc.worlds[lv.world].obj, "worldLayout", LdtkJson_Str(doc.root, "worldLayout"))
	if layout == "LinearHorizontal" || layout == "LinearVertical" {
		LINEAR_SPACING :: 48
		pos := 0
		for &o, i in doc.levels {
			if i == li do break
			if o.world != lv.world do continue
			pos += (layout == "LinearHorizontal" ? LdtkJson_Int(o.obj, "pxWid") : LdtkJson_Int(o.obj, "pxHei")) + LINEAR_SPACING
		}
		return layout == "LinearHorizontal" ? {pos, 0} : {0, pos}
	}
	return {LdtkJson_Int(lv.obj, "worldX"), LdtkJson_Int(lv.obj, "worldY")}
}

Ldtk_Doc_LevelSize :: proc(doc: ^Ldtk_Doc, li: int) -> [2]int {
	o := doc.levels[li].obj
	return {LdtkJson_Int(o, "pxWid"), LdtkJson_Int(o, "pxHei")}
}

// Ldtk_Doc_LayerOffset: the layer's total pixel offset in its level.
Ldtk_Doc_LayerOffset :: proc(ly: ^Ldtk_DocLayer) -> [2]int {
	return {LdtkJson_Int(ly.obj, "__pxTotalOffsetX"), LdtkJson_Int(ly.obj, "__pxTotalOffsetY")}
}

// Ldtk_Doc_EntityRect: the entity's box in level pixels (x, y, w, h).
Ldtk_Doc_EntityRect :: proc(ent: ^LdtkJson) -> [4]int {
	px := LdtkJson_Arr(ent, "px")
	pv := LdtkJson_Arr(ent, "__pivot")
	w := LdtkJson_Int(ent, "width", 16)
	h := LdtkJson_Int(ent, "height", 16)
	x, y := 0, 0
	if len(px) >= 2 do x, y = int(px[0].num), int(px[1].num)
	pvx, pvy := 0.0, 0.0
	if len(pv) >= 2 do pvx, pvy = pv[0].num, pv[1].num
	return {x - int(pvx * f64(w)), y - int(pvy * f64(h)), w, h}
}

// ldtk_entity_cached updates the "__" fields that follow position / size.
@(private)
ldtk_entity_cached :: proc(doc: ^Ldtk_Doc, li, layer: int, ent: ^LdtkJson) {
	a := doc.allocator
	ly := &doc.levels[li].layers[layer]
	d := Ldtk_Doc_LayerDef(doc, ly)
	grid := d != nil ? d.gridSize : 16
	px := LdtkJson_Arr(ent, "px")
	if len(px) < 2 do return
	x, y := int(px[0].num), int(px[1].num)
	LdtkJson_Set(ent, "__grid", jarr(a, jint(x / grid, a), jint(y / grid, a)), a)
	if LdtkJson_Get(ent, "__worldX") != nil || !ldtk_linear_layout(doc, li) {
		lp := Ldtk_Doc_LevelPos(doc, li)
		LdtkJson_SetInt(ent, "__worldX", x + lp.x, a)
		LdtkJson_SetInt(ent, "__worldY", y + lp.y, a)
	}
}

@(private)
ldtk_linear_layout :: proc(doc: ^Ldtk_Doc, li: int) -> bool {
	l := LdtkJson_Str(doc.worlds[doc.levels[li].world].obj, "worldLayout", LdtkJson_Str(doc.root, "worldLayout"))
	return l == "LinearHorizontal" || l == "LinearVertical"
}

// Ldtk_Doc_AddEntity places an entity of def `defUid` with its pivot at
// `px` (level pixels); returns its object.
Ldtk_Doc_AddEntity :: proc(doc: ^Ldtk_Doc, li, layer: int, defUid: int, px: [2]int) -> ^LdtkJson {
	a := doc.allocator
	ed := Ldtk_Doc_EntityDef(doc, defUid)
	if ed == nil do return nil
	lobj := doc.levels[li].layers[layer].obj
	list := LdtkJson_Get(lobj, "entityInstances")
	if list == nil || list.kind != .Array {
		list = LdtkJson_New(.Array, a)
		LdtkJson_Set(lobj, "entityInstances", list, a)
	}
	o := LdtkJson_New(.Object, a)
	jadd(o, "__identifier", jstr(ed.identifier, a), a)
	jadd(o, "__grid", jarr(a, jint(0, a), jint(0, a)), a)
	jadd(o, "__pivot", jarr(a, LdtkJson_NewFloat(ed.pivot.x, a), LdtkJson_NewFloat(ed.pivot.y, a)), a)
	tags := LdtkJson_New(.Array, a)
	for t in LdtkJson_Arr(ed.obj, "tags") do append(&tags.items, LdtkJson_Clone(t, a))
	jadd(o, "__tags", tags, a)
	tile := LdtkJson_Get(ed.obj, "tileRect")
	jadd(o, "__tile", tile != nil && tile.kind == .Object ? LdtkJson_Clone(tile, a) : jnull(a), a)
	jadd(o, "__smartColor", jstr(Ldtk_ColorHex(ed.color), a), a)
	jadd(o, "iid", jstr(Ldtk_Doc_Iid(context.temp_allocator), a), a)
	jadd(o, "width", jint(ed.size.x, a), a)
	jadd(o, "height", jint(ed.size.y, a), a)
	jadd(o, "defUid", jint(defUid, a), a)
	jadd(o, "px", jarr(a, jint(px.x, a), jint(px.y, a)), a)
	fields := LdtkJson_New(.Array, a)
	for fd in LdtkJson_Arr(ed.obj, "fieldDefs") do append(&fields.items, Ldtk_Doc_NewFieldInstance(doc, fd, a))
	jadd(o, "fieldInstances", fields, a)
	if !ldtk_linear_layout(doc, li) {
		jadd(o, "__worldX", jint(0, a), a)
		jadd(o, "__worldY", jint(0, a), a)
	}
	append(&list.items, o)
	ldtk_entity_cached(doc, li, layer, o)
	doc.levels[li].dirty = true
	Ldtk_Doc_Touch(doc)
	return o
}

Ldtk_Doc_MoveEntity :: proc(doc: ^Ldtk_Doc, li, layer: int, ent: ^LdtkJson, px: [2]int) {
	a := doc.allocator
	LdtkJson_Set(ent, "px", jarr(a, jint(px.x, a), jint(px.y, a)), a)
	ldtk_entity_cached(doc, li, layer, ent)
	doc.levels[li].dirty = true
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_ResizeEntity resizes keeping the box's top-left corner.
Ldtk_Doc_ResizeEntity :: proc(doc: ^Ldtk_Doc, li, layer: int, ent: ^LdtkJson, size: [2]int) {
	a := doc.allocator
	r := Ldtk_Doc_EntityRect(ent)
	pv := LdtkJson_Arr(ent, "__pivot")
	pvx, pvy := 0.0, 0.0
	if len(pv) >= 2 do pvx, pvy = pv[0].num, pv[1].num
	w, h := max(size.x, 1), max(size.y, 1)
	LdtkJson_SetInt(ent, "width", w, a)
	LdtkJson_SetInt(ent, "height", h, a)
	LdtkJson_Set(ent, "px", jarr(a, jint(r[0] + int(pvx * f64(w)), a), jint(r[1] + int(pvy * f64(h)), a)), a)
	ldtk_entity_cached(doc, li, layer, ent)
	doc.levels[li].dirty = true
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_ResizeEntityAround: ResizeTool / EntityInstanceEditor - a new
// size around the pivot; the position moves only when the dragged side
// (side.x: -1 left, 1 right; side.y: -1 top, 1 bottom) is the pivot's side.
Ldtk_Doc_ResizeEntityAround :: proc(doc: ^Ldtk_Doc, li, layer: int, ent: ^LdtkJson, size: [2]int, side: [2]int = {}) {
	a := doc.allocator
	pv := LdtkJson_Arr(ent, "__pivot")
	pvx, pvy := 0.0, 0.0
	if len(pv) >= 2 do pvx, pvy = pv[0].num, pv[1].num
	oldW, oldH := LdtkJson_Int(ent, "width", 16), LdtkJson_Int(ent, "height", 16)
	w, h := max(size.x, 1), max(size.y, 1)
	px := LdtkJson_Arr(ent, "px")
	x, y := len(px) >= 2 ? int(px[0].num) : 0, len(px) >= 2 ? int(px[1].num) : 0
	if side.x < 0 && pvx == 0 do x -= w - oldW
	if side.x > 0 && pvx == 1 do x += w - oldW
	if side.y < 0 && pvy == 0 do y -= h - oldH
	if side.y > 0 && pvy == 1 do y += h - oldH
	LdtkJson_SetInt(ent, "width", w, a)
	LdtkJson_SetInt(ent, "height", h, a)
	LdtkJson_Set(ent, "px", jarr(a, jint(x, a), jint(y, a)), a)
	ldtk_entity_cached(doc, li, layer, ent)
	doc.levels[li].dirty = true
	Ldtk_Doc_Touch(doc)
}

Ldtk_Doc_RemoveEntity :: proc(doc: ^Ldtk_Doc, li, layer: int, ent: ^LdtkJson) -> bool {
	list := LdtkJson_Get(doc.levels[li].layers[layer].obj, "entityInstances")
	if list == nil do return false
	for it, i in list.items {
		if it == ent {
			ordered_remove(&list.items, i)
			Ldtk_Doc_ClearRefsTo(doc, li, LdtkJson_Str(ent, "iid"))
			doc.levels[li].dirty = true
			Ldtk_Doc_Touch(doc)
			return true
		}
	}
	return false
}

// Ldtk_Doc_EntityAt: the topmost entity of a layer under a level pixel.
Ldtk_Doc_EntityAt :: proc(doc: ^Ldtk_Doc, li, layer: int, p: [2]int) -> ^LdtkJson {
	ents := Ldtk_Doc_Entities(doc, li, layer)
	#reverse for ent in ents {
		r := Ldtk_Doc_EntityRect(ent)
		if !(p.x >= r[0] && p.y >= r[1] && p.x < r[0] + r[2] && p.y < r[1] + r[3]) do continue
		// hollow entities are picked by their outline only (LDtk)
		if ed := Ldtk_Doc_EntityDef(doc, LdtkJson_Int(ent, "defUid", -1)); ed != nil && LdtkJson_Bool(ed.obj, "hollow") {
			border := max(min(r[2], r[3]) / 8, 3)
			if p.x >= r[0] + border && p.y >= r[1] + border && p.x < r[0] + r[2] - border && p.y < r[1] + r[3] - border do continue
		}
		return ent
	}
	return nil
}

// ----------------------------------------------------------------------------
// Levels
// ----------------------------------------------------------------------------

// Ldtk_Doc_NewLayerInstance builds an empty layer instance for a level.
Ldtk_Doc_NewLayerInstance :: proc(doc: ^Ldtk_Doc, d: ^Ldtk_DocLayerDef, levelUid: int, size: [2]int, a: mem.Allocator) -> ^LdtkJson {
	cw := int(math.ceil(f64(size.x - d.pxOffset.x) / f64(d.gridSize)))
	ch := int(math.ceil(f64(size.y - d.pxOffset.y) / f64(d.gridSize)))
	cw, ch = max(cw, 0), max(ch, 0)
	ts := Ldtk_Doc_Tileset(doc, d.tilesetUid)
	o := LdtkJson_New(.Object, a)
	jadd(o, "__identifier", jstr(d.identifier, a), a)
	jadd(o, "__type", jstr(LdtkJson_Str(d.obj, "__type", LdtkJson_Str(d.obj, "type")), a), a)
	jadd(o, "__cWid", jint(cw, a), a)
	jadd(o, "__cHei", jint(ch, a), a)
	jadd(o, "__gridSize", jint(d.gridSize, a), a)
	jadd(o, "__opacity", LdtkJson_NewFloat(f64(d.opacity), a), a)
	jadd(o, "__pxTotalOffsetX", jint(d.pxOffset.x, a), a)
	jadd(o, "__pxTotalOffsetY", jint(d.pxOffset.y, a), a)
	jadd(o, "__tilesetDefUid", ts != nil ? jint(ts.uid, a) : jnull(a), a)
	jadd(o, "__tilesetRelPath", ts != nil && ts.relPath != "" ? jstr(ts.relPath, a) : jnull(a), a)
	jadd(o, "iid", jstr(Ldtk_Doc_Iid(context.temp_allocator), a), a)
	jadd(o, "levelId", jint(levelUid, a), a)
	jadd(o, "layerDefUid", jint(d.uid, a), a)
	jadd(o, "pxOffsetX", jint(0, a), a)
	jadd(o, "pxOffsetY", jint(0, a), a)
	jadd(o, "visible", LdtkJson_NewBool(true, a), a)
	jadd(o, "optionalRules", LdtkJson_New(.Array, a), a)
	csv := LdtkJson_New(.Array, a)
	if d.type == .IntGrid {
		reserve(&csv.items, cw * ch)
		zero := jint(0, a)
		for _ in 0 ..< cw * ch do append(&csv.items, zero)
	}
	jadd(o, "intGridCsv", csv, a)
	jadd(o, "autoLayerTiles", LdtkJson_New(.Array, a), a)
	jadd(o, "seed", jint(int(Ldtk_RandSeedCoords(levelUid * 31 + d.uid, cw, ch, 9999999)) & 0x7FFFFF, a), a)
	jadd(o, "overrideTilesetUid", jnull(a), a)
	jadd(o, "gridTiles", LdtkJson_New(.Array, a), a)
	jadd(o, "entityInstances", LdtkJson_New(.Array, a), a)
	return o
}

// Ldtk_Doc_UniqueLevelName: the project's levelNamePattern ("Level_%idx",
// "%world_Level_%idx") with the first free index.
Ldtk_Doc_UniqueLevelName :: proc(doc: ^Ldtk_Doc, world: int, allocator := context.temp_allocator) -> string {
	pattern := LdtkJson_Str(doc.root, "levelNamePattern", "Level_%idx")
	wname := LdtkJson_Str(doc.worlds[world].obj, "identifier", "World")
	for idx in 0 ..< 100000 {
		s, _ := strings.replace_all(pattern, "%world", wname, context.temp_allocator)
		s, _ = strings.replace_all(s, "%idx", fmt.tprint(idx), context.temp_allocator)
		used := false
		for l in doc.levels do if LdtkJson_Str(l.obj, "identifier") == s do used = true
		if !used do return strings.clone(s, allocator)
	}
	return strings.clone("Level", allocator)
}

@(private)
ldtk_external_rel :: proc(doc: ^Ldtk_Doc, identifier: string) -> string {
	stem := strings.trim_suffix(filepath.base(doc.path), filepath.ext(doc.path))
	return fmt.tprintf("%s/%s.ldtkl", stem, identifier)
}

// Ldtk_Doc_AddLevel adds an empty level to a world at (x, y) with the size
// in pixels (0 = the project's default); returns its index.
Ldtk_Doc_AddLevel :: proc(doc: ^Ldtk_Doc, world: int, pos: [2]int, size: [2]int = {}) -> int {
	a := doc.allocator
	size := size
	if size.x <= 0 do size.x = Ldtk_Doc_WorldInt(doc, world, "defaultLevelWidth", 256)
	if size.y <= 0 do size.y = Ldtk_Doc_WorldInt(doc, world, "defaultLevelHeight", 256)
	uid := Ldtk_Doc_NextUid(doc)
	name := Ldtk_Doc_UniqueLevelName(doc, world)
	bg := LdtkJson_Str(doc.root, "defaultLevelBgColor", "#696A79")
	o := LdtkJson_New(.Object, a)
	jadd(o, "identifier", jstr(name, a), a)
	jadd(o, "iid", jstr(Ldtk_Doc_Iid(context.temp_allocator), a), a)
	jadd(o, "uid", jint(uid, a), a)
	jadd(o, "worldX", jint(pos.x, a), a)
	jadd(o, "worldY", jint(pos.y, a), a)
	jadd(o, "worldDepth", jint(0, a), a)
	jadd(o, "pxWid", jint(size.x, a), a)
	jadd(o, "pxHei", jint(size.y, a), a)
	jadd(o, "__bgColor", jstr(bg, a), a)
	jadd(o, "bgColor", jnull(a), a)
	jadd(o, "useAutoIdentifier", LdtkJson_NewBool(true, a), a)
	jadd(o, "bgRelPath", jnull(a), a)
	jadd(o, "bgPos", jnull(a), a)
	jadd(o, "bgPivotX", LdtkJson_NewFloat(0.5, a), a)
	jadd(o, "bgPivotY", LdtkJson_NewFloat(0.5, a), a)
	jadd(o, "__smartColor", jstr(bg, a), a)
	jadd(o, "__bgPos", jnull(a), a)
	jadd(o, "externalRelPath", jnull(a), a)
	fields := LdtkJson_New(.Array, a)
	for fd in LdtkJson_Arr(LdtkJson_Get(doc.root, "defs"), "levelFields") do append(&fields.items, Ldtk_Doc_NewFieldInstance(doc, fd, a))
	jadd(o, "fieldInstances", fields, a)
	layers := LdtkJson_New(.Array, a)
	for &d in doc.layerDefs do append(&layers.items, Ldtk_Doc_NewLayerInstance(doc, &d, uid, size, a))
	jadd(o, "layerInstances", layers, a)
	jadd(o, "__neighbours", LdtkJson_New(.Array, a), a)
	lv := Ldtk_DocLevel{obj = o, data = o, world = world}
	if doc.external {
		ext := LdtkJson_Clone(o, a)
		hdr := LdtkJson_Clone(LdtkJson_Get(doc.root, LDTK_JSON_HEADER_KEY), a)
		if hdr != nil {
			inject_at(&ext.keys, 0, strings.clone(LDTK_JSON_HEADER_KEY, a))
			inject_at(&ext.items, 0, hdr)
		}
		LdtkJson_Set(o, "layerInstances", jnull(a), a)
		LdtkJson_Set(o, "externalRelPath", jstr(ldtk_external_rel(doc, name), a), a)
		lv.extRoot = ext
		lv.data = ext
	}
	append(&doc.worlds[world].levelsArr.items, o)
	// keep doc.levels in world order
	at := 0
	for l, i in doc.levels do if l.world <= world do at = i + 1
	lv.layers = make([dynamic]Ldtk_DocLayer, doc.heap)
	inject_at(&doc.levels, at, lv)
	ldtk_level_index_layers(doc, &doc.levels[at])
	doc.levels[at].dirty = true
	Ldtk_Doc_UpdateNeighbours(doc)
	Ldtk_Doc_Touch(doc)
	return at
}

// Ldtk_Doc_RemoveLevel deletes a level (its external file is removed on
// the next save).
Ldtk_Doc_RemoveLevel :: proc(doc: ^Ldtk_Doc, li: int) -> bool {
	if li < 0 || li >= len(doc.levels) do return false
	lv := &doc.levels[li]
	arr := doc.worlds[lv.world].levelsArr
	for it, i in arr.items do if it == lv.obj {
		ordered_remove(&arr.items, i)
		break
	}
	if rel := LdtkJson_Str(lv.obj, "externalRelPath"); rel != "" do append(&doc.removedFiles, strings.clone(rel, doc.heap))
	for &ly in lv.layers {
		delete(ly.intGrid, doc.heap)
		delete(ly.gridTiles)
		delete(ly.autoTiles)
	}
	delete(lv.layers)
	ordered_remove(&doc.levels, li)
	Ldtk_Doc_UpdateNeighbours(doc)
	Ldtk_Doc_Touch(doc)
	return true
}

// ldtk_level_set_* write level metadata to the project file object and the
// external level file.
@(private)
ldtk_level_set_int :: proc(doc: ^Ldtk_Doc, lv: ^Ldtk_DocLevel, key: string, v: int) {
	LdtkJson_SetInt(lv.obj, key, v, doc.allocator)
	if lv.extRoot != nil do LdtkJson_SetInt(lv.extRoot, key, v, doc.allocator)
}

// Ldtk_Doc_RenameLevel changes a level's identifier (and its external file
// name, like LDtk).
Ldtk_Doc_RenameLevel :: proc(doc: ^Ldtk_Doc, li: int, name: string) -> bool {
	clean := strings.trim_space(name)
	if clean == "" do return false
	for l, i in doc.levels do if i != li && LdtkJson_Str(l.obj, "identifier") == clean do return false
	lv := &doc.levels[li]
	a := doc.allocator
	LdtkJson_SetStr(lv.obj, "identifier", clean, a)
	LdtkJson_SetBool(lv.obj, "useAutoIdentifier", false, a)
	if lv.extRoot != nil {
		LdtkJson_SetStr(lv.extRoot, "identifier", clean, a)
		LdtkJson_SetBool(lv.extRoot, "useAutoIdentifier", false, a)
		old := LdtkJson_Str(lv.obj, "externalRelPath")
		rel := ldtk_external_rel(doc, clean)
		if old != rel {
			if old != "" do append(&doc.removedFiles, strings.clone(old, doc.heap))
			LdtkJson_SetStr(lv.obj, "externalRelPath", rel, a)
		}
	}
	lv.dirty = true
	Ldtk_Doc_Touch(doc)
	return true
}

// Ldtk_Doc_MoveLevel puts a level at a world position.
Ldtk_Doc_MoveLevel :: proc(doc: ^Ldtk_Doc, li: int, pos: [2]int) {
	lv := &doc.levels[li]
	ldtk_level_set_int(doc, lv, "worldX", pos.x)
	ldtk_level_set_int(doc, lv, "worldY", pos.y)
	for &ly, j in lv.layers {
		for ent in Ldtk_Doc_Entities(doc, li, j) do ldtk_entity_cached(doc, li, j, ent)
		_ = ly
	}
	lv.dirty = true
	Ldtk_Doc_UpdateNeighbours(doc)
	Ldtk_Doc_Touch(doc)
}

Ldtk_Doc_SetLevelDepth :: proc(doc: ^Ldtk_Doc, li: int, depth: int) {
	ldtk_level_set_int(doc, &doc.levels[li], "worldDepth", depth)
	doc.levels[li].dirty = true
	Ldtk_Doc_UpdateNeighbours(doc)
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_SetLevelBgColor: "" uses the project's default.
Ldtk_Doc_SetLevelBgColor :: proc(doc: ^Ldtk_Doc, li: int, hex: string) {
	lv := &doc.levels[li]
	a := doc.allocator
	eff := hex != "" ? hex : LdtkJson_Str(doc.root, "defaultLevelBgColor", "#696A79")
	for o in ([]^LdtkJson{lv.obj, lv.extRoot}) {
		if o == nil do continue
		if hex == "" do LdtkJson_SetNull(o, "bgColor", a)
		else do LdtkJson_SetStr(o, "bgColor", hex, a)
		LdtkJson_SetStr(o, "__bgColor", eff, a)
	}
	lv.dirty = true
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_ResizeLevel changes a level's pixel size anchored top-left
// (Ldtk_Doc_ResizeLevelBounds from 0, 0); returns the entities removed.
Ldtk_Doc_ResizeLevel :: proc(doc: ^Ldtk_Doc, li: int, size: [2]int) -> int {
	return Ldtk_Doc_ResizeLevelBounds(doc, li, 0, 0, size.x, size.y)
}

// Ldtk_Doc_UpdateNeighbours recomputes every level's "__neighbours" like
// Level.getNeighboursJson: overlapping levels within one depth ("o" same
// depth, ">" above, "<" below), then touching levels of the same depth
// (n s e w ne nw se sw). None in the linear layouts.
Ldtk_Doc_UpdateNeighbours :: proc(doc: ^Ldtk_Doc) {
	a := doc.allocator
	overlaps :: proc(p, s, q, t: [2]int) -> bool {
		if p.y + s.y <= q.y || q.y + t.y <= p.y do return false
		if p.x + s.x <= q.x || q.x + t.x <= p.x do return false
		return true
	}
	for &lv, i in doc.levels {
		out := LdtkJson_New(.Array, a)
		layout := LdtkJson_Str(doc.worlds[lv.world].obj, "worldLayout", LdtkJson_Str(doc.root, "worldLayout"))
		linear := layout == "LinearHorizontal" || layout == "LinearVertical"
		p := Ldtk_Doc_LevelPos(doc, i)
		s := Ldtk_Doc_LevelSize(doc, i)
		depth := LdtkJson_Int(lv.obj, "worldDepth")
		add :: proc(out: ^LdtkJson, iid, dir: string, a: mem.Allocator) {
			n := LdtkJson_New(.Object, a)
			jadd(n, "levelIid", jstr(iid, a), a)
			jadd(n, "dir", jstr(dir, a), a)
			append(&out.items, n)
		}
		for pass in 0 ..< 2 {
			if linear do break
			for &o, j in doc.levels {
				if j == i || o.world != lv.world do continue
				q := Ldtk_Doc_LevelPos(doc, j)
				t := Ldtk_Doc_LevelSize(doc, j)
				od := LdtkJson_Int(o.obj, "worldDepth")
				iid := LdtkJson_Str(o.obj, "iid")
				if pass == 0 {
					if abs(depth - od) <= 1 && overlaps(p, s, q, t) do add(out, iid, od == depth ? "o" : od > depth ? ">" : "<", a)
					continue
				}
				dist := max(max(0, p.x - (q.x + t.x)) + max(0, q.x - (p.x + s.x)), max(0, p.y - (q.y + t.y)) + max(0, q.y - (p.y + s.y)))
				if dist != 0 || od != depth || overlaps(p, s, q, t) do continue
				dir := "s"
				switch {
				case q.x == p.x + s.x && q.y == p.y + s.y: dir = "se"
				case q.x + t.x == p.x && q.y == p.y + s.y: dir = "sw"
				case q.x == p.x + s.x && q.y + t.y == p.y: dir = "ne"
				case q.x + t.x == p.x && q.y + t.y == p.y: dir = "nw"
				case q.x >= p.x + s.x: dir = "e"
				case q.x + t.x <= p.x: dir = "w"
				case q.y + t.y <= p.y: dir = "n"
				}
				add(out, iid, dir, a)
			}
		}
		old := LdtkJson_Get(lv.obj, "__neighbours")
		if old != nil && LdtkJson_ToString(old, .Minified, context.temp_allocator) == LdtkJson_ToString(out, .Minified, context.temp_allocator) do continue
		LdtkJson_Set(lv.obj, "__neighbours", out, a)
		if lv.extRoot != nil do LdtkJson_Set(lv.extRoot, "__neighbours", LdtkJson_Clone(out, a), a)
		lv.dirty = true
	}
}

// Ldtk_Doc_SetLayerVisible toggles a layer instance's "visible".
Ldtk_Doc_SetLayerVisible :: proc(doc: ^Ldtk_Doc, li, layer: int, visible: bool) {
	LdtkJson_SetBool(doc.levels[li].layers[layer].obj, "visible", visible, doc.allocator)
	doc.levels[li].dirty = true
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_FreeLevelSpot: `pos`, or the first spot to its right (in `step`
// increments) where a level of `size` overlaps no level of the world.
Ldtk_Doc_FreeLevelSpot :: proc(doc: ^Ldtk_Doc, world: int, pos: [2]int, size: [2]int, step: int) -> [2]int {
	p := pos
	for _ in 0 ..< 10000 {
		free := true
		for &lv, i in doc.levels {
			if lv.world != world do continue
			q := Ldtk_Doc_LevelPos(doc, i)
			t := Ldtk_Doc_LevelSize(doc, i)
			if p.x < q.x + t.x && p.x + size.x > q.x && p.y < q.y + t.y && p.y + size.y > q.y {
				free = false
				p.x = q.x + t.x
				if step > 1 do p.x = (p.x + step - 1) / step * step
				break
			}
		}
		if free do return p
	}
	return p
}

// Ldtk_Doc_LevelAt: the level of a world under a world pixel (-1 none);
// the highest depth wins.
Ldtk_Doc_LevelAt :: proc(doc: ^Ldtk_Doc, world: int, p: [2]int) -> int {
	best, bestDepth := -1, min(int)
	for &lv, i in doc.levels {
		if lv.world != world do continue
		q := Ldtk_Doc_LevelPos(doc, i)
		s := Ldtk_Doc_LevelSize(doc, i)
		if p.x >= q.x && p.y >= q.y && p.x < q.x + s.x && p.y < q.y + s.y {
			d := LdtkJson_Int(lv.obj, "worldDepth")
			if d >= bestDepth do best, bestDepth = i, d
		}
	}
	return best
}

// Ldtk_Doc_UpdateToc rebuilds the project's "toc" (table of contents:
// instances of entities with "exportToToc", and their exported fields) the
// way Project.updateTableOfContent does. Ldtk_Doc_Save calls it for
// modified documents.
Ldtk_Doc_UpdateToc :: proc(doc: ^Ldtk_Doc) {
	a := doc.allocator
	oldData := false
	for f in LdtkJson_Arr(doc.root, "flags") do if f.kind == .String && f.text == "ExportOldTableOfContentData" do oldData = true
	toc := LdtkJson_New(.Array, a)
	for &ed in doc.entityDefs {
		if !LdtkJson_Bool(ed.obj, "exportToToc") do continue
		entry := LdtkJson_New(.Object, a)
		instances := LdtkJson_New(.Array, a)
		data := LdtkJson_New(.Array, a)
		jadd(entry, "identifier", jstr(ed.identifier, a), a)
		jadd(entry, "instances", instances, a)
		jadd(entry, "instancesData", data, a)
		append(&toc.items, entry)
		exported := make(map[int]bool, allocator = context.temp_allocator)
		for fd in LdtkJson_Arr(ed.obj, "fieldDefs") do if LdtkJson_Bool(fd, "exportToToc") do exported[LdtkJson_Int(fd, "uid")] = true
		for &lv, li in doc.levels {
			w := doc.worlds[lv.world].obj
			worldIid := doc.multiWorlds ? LdtkJson_Str(w, "iid") : LdtkJson_Str(doc.root, "dummyWorldIid")
			lp := Ldtk_Doc_LevelPos(doc, li)
			for &ly in lv.layers {
				for ent in LdtkJson_Arr(ly.obj, "entityInstances") {
					if LdtkJson_Int(ent, "defUid", -1) != ed.uid do continue
					refs :: proc(worldIid, levelIid, layerIid, entityIid: string, a: mem.Allocator) -> ^LdtkJson {
						o := LdtkJson_New(.Object, a)
						jadd(o, "worldIid", jstr(worldIid, a), a)
						jadd(o, "levelIid", jstr(levelIid, a), a)
						jadd(o, "layerIid", jstr(layerIid, a), a)
						jadd(o, "entityIid", jstr(entityIid, a), a)
						return o
					}
					wi, lvi, lyi, ei := worldIid, LdtkJson_Str(lv.obj, "iid"), LdtkJson_Str(ly.obj, "iid"), LdtkJson_Str(ent, "iid")
					if oldData do append(&instances.items, refs(wi, lvi, lyi, ei, a))
					fields := LdtkJson_New(.Object, a)
					for fi in LdtkJson_Arr(ent, "fieldInstances") {
						if !exported[LdtkJson_Int(fi, "defUid", -1)] do continue
						v := LdtkJson_Get(fi, "__value")
						jadd(fields, LdtkJson_Str(fi, "__identifier"), v != nil ? LdtkJson_Clone(v, a) : jnull(a), a)
					}
					px := LdtkJson_Arr(ent, "px")
					x, y := 0, 0
					if len(px) >= 2 do x, y = int(px[0].num), int(px[1].num)
					o := LdtkJson_New(.Object, a)
					jadd(o, "iids", refs(wi, lvi, lyi, ei, a), a)
					jadd(o, "worldX", jint(x + lp.x, a), a)
					jadd(o, "worldY", jint(y + lp.y, a), a)
					jadd(o, "widPx", jint(LdtkJson_Int(ent, "width"), a), a)
					jadd(o, "heiPx", jint(LdtkJson_Int(ent, "height"), a), a)
					jadd(o, "fields", fields, a)
					append(&data.items, o)
				}
			}
		}
	}
	old := LdtkJson_Get(doc.root, "toc")
	if old != nil && LdtkJson_ToString(old, .Minified, context.temp_allocator) == LdtkJson_ToString(toc, .Minified, context.temp_allocator) do return
	LdtkJson_Set(doc.root, "toc", toc, a)
}

LDTK_WORLD_LAYOUTS := [?]string{"Free", "GridVania", "LinearHorizontal", "LinearVertical"}

// Ldtk_Doc_SetWorldLayout changes a world's layout. Leaving a linear layout
// writes the computed positions; entering one stores -1 like LDtk (the
// positions are then computed from the level order).
Ldtk_Doc_SetWorldLayout :: proc(doc: ^Ldtk_Doc, world: int, layout: string) {
	a := doc.allocator
	w := doc.worlds[world].obj
	cur := LdtkJson_Str(w, "worldLayout", LdtkJson_Str(doc.root, "worldLayout"))
	if cur == layout do return
	// positions as they look now
	pos := make([][2]int, len(doc.levels), context.temp_allocator)
	for _, i in doc.levels do pos[i] = Ldtk_Doc_LevelPos(doc, i)
	LdtkJson_SetStr(w, "worldLayout", layout, a)
	if !doc.multiWorlds do LdtkJson_SetStr(doc.root, "worldLayout", layout, a)
	linear := layout == "LinearHorizontal" || layout == "LinearVertical"
	for &lv, i in doc.levels {
		if lv.world != world do continue
		p := linear ? [2]int{-1, -1} : pos[i]
		if layout == "GridVania" {
			gw := max(LdtkJson_Int(w, "worldGridWidth", 256), 1)
			gh := max(LdtkJson_Int(w, "worldGridHeight", 256), 1)
			p = {p.x / gw * gw, p.y / gh * gh}
		}
		ldtk_level_set_int(doc, &lv, "worldX", p.x)
		ldtk_level_set_int(doc, &lv, "worldY", p.y)
		for &ly, j in lv.layers {
			for ent in LdtkJson_Arr(ly.obj, "entityInstances") {
				if linear {
					LdtkJson_Remove(ent, "__worldX")
					LdtkJson_Remove(ent, "__worldY")
				} else {
					if LdtkJson_Get(ent, "__worldX") == nil do LdtkJson_Set(ent, "__worldX", jint(0, a), a)
					if LdtkJson_Get(ent, "__worldY") == nil do LdtkJson_Set(ent, "__worldY", jint(0, a), a)
					ldtk_entity_cached(doc, i, j, ent)
				}
			}
			_ = ly
		}
		lv.dirty = true
	}
	Ldtk_Doc_UpdateNeighbours(doc)
	Ldtk_Doc_Touch(doc)
}

// ldtk_new_iids gives every "iid" in a tree (levels, layers, entities) a
// fresh value.
@(private = "file")
ldtk_new_iids :: proc(n: ^LdtkJson, a: mem.Allocator) {
	if n == nil do return
	if n.kind == .Object {
		for k, i in n.keys {
			if k == "iid" && n.items[i].kind == .String do n.items[i] = jstr(Ldtk_Doc_Iid(context.temp_allocator), a)
			else do ldtk_new_iids(n.items[i], a)
		}
	} else if n.kind == .Array {
		for it in n.items do ldtk_new_iids(it, a)
	}
}

// Ldtk_Doc_DuplicateLevel copies a level (content, fields) next to it in a
// free spot; returns the copy's index.
Ldtk_Doc_DuplicateLevel :: proc(doc: ^Ldtk_Doc, li: int) -> int {
	a := doc.allocator
	src := &doc.levels[li]
	// the level with its layers as they are now (typed cells written in)
	text := Ldtk_Doc_LevelText(doc, li)
	obj, ok := LdtkJson_Parse(text, a)
	if !ok do return -1
	LdtkJson_Remove(obj, LDTK_JSON_HEADER_KEY)
	ldtk_new_iids(obj, a)
	uid := Ldtk_Doc_NextUid(doc)
	LdtkJson_SetInt(obj, "uid", uid, a)
	for ly in LdtkJson_Arr(obj, "layerInstances") do LdtkJson_SetInt(ly, "levelId", uid, a)
	name := Ldtk_Doc_UniqueLevelName(doc, src.world)
	LdtkJson_SetStr(obj, "identifier", name, a)
	p := Ldtk_Doc_LevelPos(doc, li)
	s := Ldtk_Doc_LevelSize(doc, li)
	step := 1
	if LdtkJson_Str(doc.worlds[src.world].obj, "worldLayout", LdtkJson_Str(doc.root, "worldLayout")) == "GridVania" do step = max(Ldtk_Doc_WorldInt(doc, src.world, "worldGridWidth", 256), 1)
	pos := Ldtk_Doc_FreeLevelSpot(doc, src.world, {p.x + s.x, p.y}, s, step)
	LdtkJson_SetInt(obj, "worldX", pos.x, a)
	LdtkJson_SetInt(obj, "worldY", pos.y, a)
	lv := Ldtk_DocLevel{obj = obj, data = obj, world = src.world}
	if doc.external {
		ext := LdtkJson_Clone(obj, a)
		if hdr := LdtkJson_Get(doc.root, LDTK_JSON_HEADER_KEY); hdr != nil {
			inject_at(&ext.keys, 0, strings.clone(LDTK_JSON_HEADER_KEY, a))
			inject_at(&ext.items, 0, LdtkJson_Clone(hdr, a))
		}
		LdtkJson_SetNull(ext, "externalRelPath", a)
		LdtkJson_Set(obj, "layerInstances", jnull(a), a)
		LdtkJson_SetStr(obj, "externalRelPath", ldtk_external_rel(doc, name), a)
		lv.extRoot, lv.data = ext, ext
	}
	// after the source in its world's list
	arr := doc.worlds[src.world].levelsArr
	at := len(arr.items)
	for it, i in arr.items do if it == src.obj do at = i + 1
	inject_at(&arr.items, at, obj)
	lv.layers = make([dynamic]Ldtk_DocLayer, doc.heap)
	inject_at(&doc.levels, li + 1, lv)
	ldtk_level_index_layers(doc, &doc.levels[li + 1])
	for &ly in doc.levels[li + 1].layers do ly.cellsDirty, ly.autoDirty = false, false
	doc.levels[li + 1].dirty = true
	// entities' cached world positions
	for &ly, j in doc.levels[li + 1].layers {
		for ent in LdtkJson_Arr(ly.obj, "entityInstances") do ldtk_entity_cached(doc, li + 1, j, ent)
		_ = ly
	}
	Ldtk_Doc_UpdateNeighbours(doc)
	Ldtk_Doc_Touch(doc)
	return li + 1
}

// Ldtk_Doc_MoveLevelOrder moves a level up / down in its world's list (the
// order of the linear layouts and of the Levels panel); returns its index.
Ldtk_Doc_MoveLevelOrder :: proc(doc: ^Ldtk_Doc, li: int, delta: int) -> int {
	lv := &doc.levels[li]
	j := li + delta
	if j < 0 || j >= len(doc.levels) || doc.levels[j].world != lv.world do return li
	arr := doc.worlds[lv.world].levelsArr
	a, b := -1, -1
	for it, i in arr.items {
		if it == doc.levels[li].obj do a = i
		if it == doc.levels[j].obj do b = i
	}
	if a < 0 || b < 0 do return li
	arr.items[a], arr.items[b] = arr.items[b], arr.items[a]
	doc.levels[li], doc.levels[j] = doc.levels[j], doc.levels[li]
	doc.levels[li].dirty, doc.levels[j].dirty = true, true
	Ldtk_Doc_UpdateNeighbours(doc)
	Ldtk_Doc_Touch(doc)
	return j
}
