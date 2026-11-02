package engine

import "core:fmt"
import "core:math"
import "core:mem"
import "core:strconv"
import "core:strings"
import "core:text/regex"

// ============================================================================
// Ldtk_Doc field values (data/inst/FieldInstance.hx)
//
// A field instance keeps LDtk's "internal values" in realEditorValues, one
// per array element: null = use the definition's default, {"id": "V_Null"}
// = explicitly empty, {"id": "V_Int", "params": [5]} etc. __value is derived
// from them (and the defaults) for game readers - Ldtk_Doc_FieldRebuild
// writes it. Values are edited as text (Ldtk_Doc_SetFieldRaw):
//
//   Int / Float  a number (clamped to min / max)     Color   #RRGGBB
//   Bool         true / false                        Enum    a value id
//   String       one line (must match the regex)     Text    any text
//   Point        "cx,cy" (grid cells)                Path    a file path
//   EntityRef    an entity iid                       Tile    "x,y,w,h" px in the field's tileset
//
// Entities' __tile / __smartColor follow their fields (Ldtk_Doc_EntitySmart).
// ============================================================================

// ldtk_value_wrap: {"id": id, "params": [v]}.
@(private = "file")
fwrap :: proc(id: string, v: ^LdtkJson, a: mem.Allocator) -> ^LdtkJson {
	o := LdtkJson_New(.Object, a)
	append(&o.keys, strings.clone("id", a), strings.clone("params", a))
	p := LdtkJson_New(.Array, a)
	append(&p.items, v)
	append(&o.items, LdtkJson_NewString(id, a), p)
	return o
}

@(private = "file")
fnull_wrap :: proc(a: mem.Allocator) -> ^LdtkJson {
	o := LdtkJson_New(.Object, a)
	append(&o.keys, strings.clone("id", a))
	append(&o.items, LdtkJson_NewString("V_Null", a))
	return o
}

// Ldtk_Field_Raw: one internal value.
Ldtk_Field_Raw :: struct {
	isDefault: bool, // null: the definition's default
	isNull:    bool, // V_Null
	text:      string,
	num:       f64,
	b:         bool,
}

@(private = "file")
fraw_of :: proc(v: ^LdtkJson) -> Ldtk_Field_Raw {
	if v == nil || v.kind == .Null do return {isDefault = true}
	id := LdtkJson_Str(v, "id")
	if id == "V_Null" do return {isNull = true}
	p := LdtkJson_Arr(v, "params")
	if len(p) == 0 do return {isNull = true}
	x := p[0]
	r := Ldtk_Field_Raw{}
	switch x.kind {
	case .Number:
		r.num = x.num
		b := strings.builder_make(context.temp_allocator)
		ldtk_js_number(&b, x.num)
		r.text = strings.to_string(b)
	case .Bool:
		r.b = x.b
		r.text = x.b ? "true" : "false"
	case .String: r.text = x.text
	case .Null: r.isNull = true
	case .Array, .Object:
	}
	return r
}

// Ldtk_Doc_FieldArrayLen: the number of values (1 for single fields).
Ldtk_Doc_FieldArrayLen :: proc(doc: ^Ldtk_Doc, fi: ^LdtkJson) -> int {
	fd := Ldtk_Doc_FieldDef(doc, LdtkJson_Int(fi, "defUid", -1))
	if fd == nil || !LdtkJson_Bool(fd, "isArray") do return 1
	return len(LdtkJson_Arr(fi, "realEditorValues"))
}

// Ldtk_Doc_FieldRaw: the internal value at an index.
Ldtk_Doc_FieldRaw :: proc(fi: ^LdtkJson, idx: int) -> Ldtk_Field_Raw {
	rev := LdtkJson_Arr(fi, "realEditorValues")
	if idx < 0 || idx >= len(rev) do return {isDefault = true}
	return fraw_of(rev[idx])
}

// ----------------------------------------------------------------------------
// Defaults
// ----------------------------------------------------------------------------

// Ldtk_Doc_FieldDefault: a field def's default as text ("" + isNull when it
// has none) - FieldDef.getXDefault.
Ldtk_Doc_FieldDefault :: proc(doc: ^Ldtk_Doc, fd: ^LdtkJson) -> (text: string, isNull: bool) {
	kind := Ldtk_FieldKindOf(fd)
	canBeNull := LdtkJson_Bool(fd, "canBeNull")
	over := fraw_of(LdtkJson_Get(fd, "defaultOverride"))
	has := !over.isDefault && !over.isNull
	switch kind {
	case .Int, .Float:
		if has do return over.text, false
		if canBeNull do return "", true
		v := ldtk_clamp_field(fd, 0)
		b := strings.builder_make(context.temp_allocator)
		ldtk_js_number(&b, kind == .Int ? math.round(v) : v)
		return strings.to_string(b), false
	case .Bool:
		if has do return over.text, false
		return "false", false
	case .String, .Text:
		if has do return over.text, false
		if canBeNull do return "", true
		return "", false
	case .Color:
		if has do return fmt.tprintf("#%06X", int(over.num) & 0xFFFFFF), false
		if canBeNull do return "", true
		return "#000000", false
	case .Enum:
		if has do return over.text, false
		if !canBeNull {
			if ed := Ldtk_Doc_EnumDef(doc, Ldtk_FieldEnumUid(fd)); ed != nil {
				if vals := LdtkJson_Arr(ed, "values"); len(vals) > 0 do return LdtkJson_Str(vals[0], "id"), false
			}
		}
		return "", true
	case .Tile:
		if has do return over.text, false
		return "", true
	case .Point, .Path, .EntityRef, .Other:
	}
	return "", true
}

@(private = "file")
ldtk_clamp_field :: proc(fd: ^LdtkJson, v: f64) -> f64 {
	v := v
	if mn := LdtkJson_Get(fd, "min"); mn != nil && mn.kind == .Number do v = max(v, mn.num)
	if mx := LdtkJson_Get(fd, "max"); mx != nil && mx.kind == .Number do v = min(v, mx.num)
	return v
}

// Ldtk_Doc_FieldText: the value shown for an index (the default when the
// value isn't set); isNull when there is none.
Ldtk_Doc_FieldText :: proc(doc: ^Ldtk_Doc, fi: ^LdtkJson, idx: int) -> (text: string, isNull: bool) {
	fd := Ldtk_Doc_FieldDef(doc, LdtkJson_Int(fi, "defUid", -1))
	if fd == nil do return "", true
	r := Ldtk_Doc_FieldRaw(fi, idx)
	if r.isDefault do return Ldtk_Doc_FieldDefault(doc, fd)
	if r.isNull do return "", true
	if Ldtk_FieldKindOf(fd) == .Color do return fmt.tprintf("#%06X", int(r.num) & 0xFFFFFF), false
	return r.text, false
}

// ----------------------------------------------------------------------------
// Setting values
// ----------------------------------------------------------------------------

// ldtk_field_parse: text -> internal value for a field def (nil + ok: null).
@(private = "file")
ldtk_field_parse :: proc(doc: ^Ldtk_Doc, fd: ^LdtkJson, text: string, a: mem.Allocator) -> (^LdtkJson, bool) {
	kind := Ldtk_FieldKindOf(fd)
	t := strings.trim_space(text)
	if t == "" && kind != .Text do return nil, true
	switch kind {
	case .Int:
		v, ok := strconv.parse_f64(t)
		if !ok do return nil, false
		return fwrap("V_Int", LdtkJson_NewFloat(math.round(ldtk_clamp_field(fd, v)), a), a), true
	case .Float:
		v, ok := strconv.parse_f64(t)
		if !ok do return nil, false
		return fwrap("V_Float", LdtkJson_NewFloat(ldtk_clamp_field(fd, v), a), a), true
	case .Bool:
		l := strings.to_lower(t, context.temp_allocator)
		if l != "true" && l != "false" && l != "1" && l != "0" do return nil, false
		return fwrap("V_Bool", LdtkJson_NewBool(l == "true" || l == "1", a), a), true
	case .String:
		one, _ := strings.replace_all(t, "\n", " ", context.temp_allocator)
		if !Ldtk_FieldRegexMatch(fd, one) do return nil, false
		return fwrap("V_String", LdtkJson_NewString(one, a), a), true
	case .Text:
		if text == "" do return nil, true
		return fwrap("V_String", LdtkJson_NewString(text, a), a), true
	case .Path:
		one, _ := strings.replace_all(t, "\n", " ", context.temp_allocator)
		if !Ldtk_FieldPathAccepted(fd, one) do return nil, false
		return fwrap("V_String", LdtkJson_NewString(one, a), a), true
	case .Color:
		c := Ldtk_ParseHexColor(t, {0, 0, 0, 0})
		if c.a == 0 do return nil, false
		return fwrap("V_Int", LdtkJson_NewInt(int(c.r) << 16 | int(c.g) << 8 | int(c.b), a), a), true
	case .Enum:
		ed := Ldtk_Doc_EnumDef(doc, Ldtk_FieldEnumUid(fd))
		for v in LdtkJson_Arr(ed, "values") do if LdtkJson_Str(v, "id") == t do return fwrap("V_String", LdtkJson_NewString(t, a), a), true
		return nil, false
	case .Point:
		parts := strings.split(t, ",", context.temp_allocator)
		if len(parts) != 2 do return nil, false
		x, ok1 := strconv.parse_int(strings.trim_space(parts[0]))
		y, ok2 := strconv.parse_int(strings.trim_space(parts[1]))
		if !ok1 || !ok2 do return nil, false
		return fwrap("V_String", LdtkJson_NewString(fmt.tprintf("%d,%d", x, y), a), a), true
	case .EntityRef:
		return fwrap("V_String", LdtkJson_NewString(t, a), a), true
	case .Tile:
		parts := strings.split(t, ",", context.temp_allocator)
		if len(parts) != 4 do return nil, false
		for p in parts do if _, ok := strconv.parse_int(strings.trim_space(p)); !ok do return nil, false
		return fwrap("V_String", LdtkJson_NewString(t, a), a), true
	case .Other:
	}
	return nil, false
}

// Ldtk_FieldRegexMatch: a String field's regex ("/pattern/flags") accepts
// the text (no regex: anything).
Ldtk_FieldRegexMatch :: proc(fd: ^LdtkJson, text: string) -> bool {
	rx := LdtkJson_Str(fd, "regex")
	if rx == "" do return true
	pattern, flags := rx, ""
	if strings.has_prefix(rx, "/") {
		if end := strings.last_index_byte(rx, '/'); end > 0 {
			pattern, flags = rx[1:end], rx[end + 1:]
		}
	}
	rflags: regex.Flags
	if strings.contains(flags, "i") do rflags += {.Case_Insensitive}
	r, err := regex.create(pattern, rflags)
	if err != nil do return true // an invalid pattern doesn't block editing
	defer regex.destroy(r)
	capture, ok := regex.match(r, text)
	regex.destroy_capture(capture)
	return ok
}

// Ldtk_FieldPathAccepted: a FilePath field's accepted extensions.
Ldtk_FieldPathAccepted :: proc(fd: ^LdtkJson, path: string) -> bool {
	exts := LdtkJson_Arr(fd, "acceptFileTypes")
	if len(exts) == 0 do return true
	low := strings.to_lower(path, context.temp_allocator)
	for x in exts {
		ext := strings.to_lower(strings.trim_space(x.text), context.temp_allocator)
		if !strings.has_prefix(ext, ".") do ext = fmt.tprintf(".%s", ext)
		if strings.has_suffix(low, ext) do return true
	}
	return false
}

// Ldtk_Doc_SetFieldRaw sets the value at an index from text ("" = empty,
// i.e. null, for nullable fields); `useDefault` resets it to the default.
// Returns false when the text doesn't fit (nothing changes).
Ldtk_Doc_SetFieldRaw :: proc(doc: ^Ldtk_Doc, fi: ^LdtkJson, idx: int, text: string, useDefault := false) -> bool {
	a := doc.allocator
	fd := Ldtk_Doc_FieldDef(doc, LdtkJson_Int(fi, "defUid", -1))
	if fd == nil do return false
	rev := LdtkJson_Get(fi, "realEditorValues")
	if rev == nil || rev.kind != .Array {
		rev = LdtkJson_New(.Array, a)
		LdtkJson_Set(fi, "realEditorValues", rev, a)
	}
	for len(rev.items) <= idx do append(&rev.items, LdtkJson_New(.Null, a))
	if useDefault {
		rev.items[idx] = LdtkJson_New(.Null, a)
	} else {
		v, ok := ldtk_field_parse(doc, fd, text, a)
		if !ok do return false
		kind := Ldtk_FieldKindOf(fd)
		if v == nil {
			// empty: null for nullable fields (and the kinds without a value)
			nullable := LdtkJson_Bool(fd, "canBeNull") || kind == .Point || kind == .Path || kind == .EntityRef || kind == .Tile || LdtkJson_Bool(fd, "isArray")
			if !nullable && kind != .String do return false
			v = nullable ? fnull_wrap(a) : fwrap("V_String", LdtkJson_NewString("", a), a)
		}
		rev.items[idx] = v
	}
	Ldtk_Doc_FieldRebuild(doc, fi)
	Ldtk_Doc_Touch(doc)
	return true
}

// Ldtk_Doc_FieldArrayAdd appends a value (the default) to an array field;
// returns its index.
Ldtk_Doc_FieldArrayAdd :: proc(doc: ^Ldtk_Doc, fi: ^LdtkJson) -> int {
	a := doc.allocator
	fd := Ldtk_Doc_FieldDef(doc, LdtkJson_Int(fi, "defUid", -1))
	if fd == nil || !LdtkJson_Bool(fd, "isArray") do return -1
	if mx := LdtkJson_Get(fd, "arrayMaxLength"); mx != nil && mx.kind == .Number && len(LdtkJson_Arr(fi, "realEditorValues")) >= int(mx.num) do return -1
	rev := LdtkJson_Get(fi, "realEditorValues")
	if rev == nil || rev.kind != .Array {
		rev = LdtkJson_New(.Array, a)
		LdtkJson_Set(fi, "realEditorValues", rev, a)
	}
	append(&rev.items, LdtkJson_New(.Null, a))
	Ldtk_Doc_FieldRebuild(doc, fi)
	Ldtk_Doc_Touch(doc)
	return len(rev.items) - 1
}

// Ldtk_Doc_FieldArrayRemove removes an array value.
Ldtk_Doc_FieldArrayRemove :: proc(doc: ^Ldtk_Doc, fi: ^LdtkJson, idx: int) -> bool {
	rev := LdtkJson_Get(fi, "realEditorValues")
	if rev == nil || idx < 0 || idx >= len(rev.items) do return false
	ordered_remove(&rev.items, idx)
	Ldtk_Doc_FieldRebuild(doc, fi)
	Ldtk_Doc_Touch(doc)
	return true
}

// Ldtk_Doc_FieldArrayMove moves an array value up / down.
Ldtk_Doc_FieldArrayMove :: proc(doc: ^Ldtk_Doc, fi: ^LdtkJson, idx: int, delta: int) -> bool {
	rev := LdtkJson_Get(fi, "realEditorValues")
	j := idx + delta
	if rev == nil || idx < 0 || j < 0 || idx >= len(rev.items) || j >= len(rev.items) do return false
	rev.items[idx], rev.items[j] = rev.items[j], rev.items[idx]
	Ldtk_Doc_FieldRebuild(doc, fi)
	Ldtk_Doc_Touch(doc)
	return true
}

// ----------------------------------------------------------------------------
// __value
// ----------------------------------------------------------------------------

// ldtk_field_json: one element's __value.
@(private = "file")
ldtk_field_json :: proc(doc: ^Ldtk_Doc, fd: ^LdtkJson, fi: ^LdtkJson, idx: int, a: mem.Allocator) -> ^LdtkJson {
	text, isNull := Ldtk_Doc_FieldText(doc, fi, idx)
	if isNull do return LdtkJson_New(.Null, a)
	switch Ldtk_FieldKindOf(fd) {
	case .Int, .Float:
		v, _ := strconv.parse_f64(text)
		return LdtkJson_NewFloat(v, a)
	case .Bool: return LdtkJson_NewBool(text == "true", a)
	case .String, .Text, .Path, .Color, .Enum: return LdtkJson_NewString(text, a)
	case .Point:
		parts := strings.split(text, ",", context.temp_allocator)
		o := LdtkJson_New(.Object, a)
		if len(parts) == 2 {
			x, _ := strconv.parse_int(parts[0])
			y, _ := strconv.parse_int(parts[1])
			append(&o.keys, strings.clone("cx", a), strings.clone("cy", a))
			append(&o.items, LdtkJson_NewInt(x, a), LdtkJson_NewInt(y, a))
		}
		return o
	case .EntityRef:
		o := LdtkJson_New(.Object, a)
		li, layer, _, found := Ldtk_Doc_FindEntity(doc, text)
		lyIid, lvIid, wIid := "?", "?", "?"
		if found {
			lv := &doc.levels[li]
			lyIid = LdtkJson_Str(lv.layers[layer].obj, "iid")
			lvIid = LdtkJson_Str(lv.obj, "iid")
			wIid = doc.multiWorlds ? LdtkJson_Str(doc.worlds[lv.world].obj, "iid") : LdtkJson_Str(doc.root, "dummyWorldIid")
		}
		append(&o.keys, strings.clone("entityIid", a), strings.clone("layerIid", a), strings.clone("levelIid", a), strings.clone("worldIid", a))
		append(&o.items, LdtkJson_NewString(text, a), LdtkJson_NewString(lyIid, a), LdtkJson_NewString(lvIid, a), LdtkJson_NewString(wIid, a))
		return o
	case .Tile:
		parts := strings.split(text, ",", context.temp_allocator)
		if len(parts) != 4 do return LdtkJson_New(.Null, a)
		return ldtk_tile_rect_json(LdtkJson_Int(fd, "tilesetUid", -1), parts, a)
	case .Other:
	}
	return LdtkJson_New(.Null, a)
}

@(private = "file")
ldtk_tile_rect_json :: proc(tsUid: int, parts: []string, a: mem.Allocator) -> ^LdtkJson {
	o := LdtkJson_New(.Object, a)
	keys := [?]string{"x", "y", "w", "h"}
	append(&o.keys, strings.clone("tilesetUid", a))
	append(&o.items, LdtkJson_NewInt(tsUid, a))
	for k, i in keys {
		v, _ := strconv.parse_int(strings.trim_space(parts[i]))
		append(&o.keys, strings.clone(k, a))
		append(&o.items, LdtkJson_NewInt(v, a))
	}
	return o
}

// Ldtk_Doc_FieldRebuild rewrites a field instance's __value (and __tile)
// from its internal values.
Ldtk_Doc_FieldRebuild :: proc(doc: ^Ldtk_Doc, fi: ^LdtkJson) {
	a := doc.allocator
	fd := Ldtk_Doc_FieldDef(doc, LdtkJson_Int(fi, "defUid", -1))
	if fd == nil do return
	v: ^LdtkJson
	if LdtkJson_Bool(fd, "isArray") {
		v = LdtkJson_New(.Array, a)
		for i in 0 ..< len(LdtkJson_Arr(fi, "realEditorValues")) do append(&v.items, ldtk_field_json(doc, fd, fi, i, a))
	} else {
		v = ldtk_field_json(doc, fd, fi, 0, a)
	}
	LdtkJson_Set(fi, "__value", v, a)
	tile := Ldtk_Doc_FieldSmartTile(doc, fi)
	LdtkJson_Set(fi, "__tile", tile != nil ? tile : LdtkJson_New(.Null, a), a)
}

// Ldtk_Doc_FieldSmartTile: the tile a field gives its entity / level
// (FieldInstance.getSmartTile): with the EntityTile (LevelTile) display
// mode, an enum value's icon or a Tile field's value; nil otherwise.
Ldtk_Doc_FieldSmartTile :: proc(doc: ^Ldtk_Doc, fi: ^LdtkJson, forLevel := false) -> ^LdtkJson {
	a := doc.allocator
	fd := Ldtk_Doc_FieldDef(doc, LdtkJson_Int(fi, "defUid", -1))
	if fd == nil do return nil
	if LdtkJson_Str(fd, "editorDisplayMode") != (forLevel ? "LevelTile" : "EntityTile") do return nil
	text, isNull := Ldtk_Doc_FieldText(doc, fi, 0)
	if isNull do return nil
	#partial switch Ldtk_FieldKindOf(fd) {
	case .Enum:
		ed := Ldtk_Doc_EnumDef(doc, Ldtk_FieldEnumUid(fd))
		if ed == nil || LdtkJson_IsNull(ed, "iconTilesetUid") do return nil
		for ev in LdtkJson_Arr(ed, "values") {
			if LdtkJson_Str(ev, "id") != text do continue
			tr := LdtkJson_Get(ev, "tileRect")
			if tr != nil && tr.kind == .Object do return LdtkJson_Clone(tr, a)
		}
	case .Tile:
		parts := strings.split(text, ",", context.temp_allocator)
		if len(parts) == 4 do return ldtk_tile_rect_json(LdtkJson_Int(fd, "tilesetUid", -1), parts, a)
	}
	return nil
}

// Ldtk_Doc_EntitySmart updates an entity's __tile (a field shown as the
// entity's tile, else the definition's) and __smartColor (a colour / enum
// field used for the smart colour, else the definition's).
Ldtk_Doc_EntitySmart :: proc(doc: ^Ldtk_Doc, ent: ^LdtkJson) {
	a := doc.allocator
	ed := Ldtk_Doc_EntityDef(doc, LdtkJson_Int(ent, "defUid", -1))
	if ed == nil do return
	tile: ^LdtkJson
	color := ed.color
	for fi in LdtkJson_Arr(ent, "fieldInstances") {
		fd := Ldtk_Doc_FieldDef(doc, LdtkJson_Int(fi, "defUid", -1))
		if fd == nil do continue
		if tile == nil do tile = Ldtk_Doc_FieldSmartTile(doc, fi)
		if LdtkJson_Bool(fd, "useForSmartColor") {
			text, isNull := Ldtk_Doc_FieldText(doc, fi, 0)
			if isNull do continue
			#partial switch Ldtk_FieldKindOf(fd) {
			case .Color: color = Ldtk_ParseHexColor(text, color)
			case .Enum:
				if en := Ldtk_Doc_EnumDef(doc, Ldtk_FieldEnumUid(fd)); en != nil {
					for ev in LdtkJson_Arr(en, "values") do if LdtkJson_Str(ev, "id") == text {
						c := LdtkJson_Int(ev, "color")
						color = {u8(c >> 16), u8(c >> 8), u8(c), 255}
					}
				}
			}
		}
	}
	if tile == nil {
		tr := LdtkJson_Get(ed.obj, "tileRect")
		if tr != nil && tr.kind == .Object do tile = LdtkJson_Clone(tr, a)
	}
	LdtkJson_Set(ent, "__tile", tile != nil ? tile : LdtkJson_New(.Null, a), a)
	LdtkJson_SetStr(ent, "__smartColor", Ldtk_ColorHex(color), a)
}

// ----------------------------------------------------------------------------
// Entity references
// ----------------------------------------------------------------------------

// Ldtk_Doc_FindEntity finds an entity by iid in any level.
Ldtk_Doc_FindEntity :: proc(doc: ^Ldtk_Doc, iid: string) -> (li, layer: int, ent: ^LdtkJson, ok: bool) {
	if iid == "" do return
	for &lv, i in doc.levels {
		for &ly, j in lv.layers {
			for e in LdtkJson_Arr(ly.obj, "entityInstances") do if LdtkJson_Str(e, "iid") == iid do return i, j, e, true
		}
	}
	return
}

// Ldtk_Doc_RefAllowed: can a reference field of `from` (in level fromLi)
// point at `to` (FieldDef allowedRefs / allowedRefTags /
// allowedRefsEntityUid / allowOutOfLevelRef)? The reason when it can't.
Ldtk_Doc_RefAllowed :: proc(doc: ^Ldtk_Doc, fd: ^LdtkJson, from: ^LdtkJson, fromLi: int, to: ^LdtkJson, toLi: int) -> (bool, string) {
	if to == from do return false, "an entity can't point at itself"
	if !LdtkJson_Bool(fd, "allowOutOfLevelRef", true) && toLi != fromLi do return false, "only entities of the same level"
	switch LdtkJson_Str(fd, "allowedRefs", "OnlySame") {
	case "OnlySame":
		if LdtkJson_Int(to, "defUid", -1) != LdtkJson_Int(from, "defUid", -2) do return false, fmt.tprintf("only %s entities", LdtkJson_Str(from, "__identifier"))
	case "OnlySpecificEntity":
		if LdtkJson_Int(to, "defUid", -1) != LdtkJson_Int(fd, "allowedRefsEntityUid", -2) {
			ed := Ldtk_Doc_EntityDef(doc, LdtkJson_Int(fd, "allowedRefsEntityUid", -2))
			return false, fmt.tprintf("only %s entities", ed != nil ? ed.identifier : "?")
		}
	case "OnlyTags":
		want := LdtkJson_Arr(fd, "allowedRefTags")
		ok := len(want) == 0
		for w in want do for t in LdtkJson_Arr(to, "__tags") do if t.text == w.text do ok = true
		if !ok do return false, "only entities with the allowed tags"
	}
	return true, ""
}

// Ldtk_Doc_SetFieldRef points a reference field's value at an entity
// (targetIid "" clears it); with "symmetricalRef", the target's field of the
// same definition points back (FieldInstance.setSymmetricalRef). `from` is
// the entity owning the field.
Ldtk_Doc_SetFieldRef :: proc(doc: ^Ldtk_Doc, fi: ^LdtkJson, idx: int, from: ^LdtkJson, targetIid: string) -> bool {
	fd := Ldtk_Doc_FieldDef(doc, LdtkJson_Int(fi, "defUid", -1))
	if fd == nil || Ldtk_FieldKindOf(fd) != .EntityRef do return false
	old, _ := Ldtk_Doc_FieldText(doc, fi, idx)
	if !Ldtk_Doc_SetFieldRaw(doc, fi, idx, targetIid) do return false
	if !LdtkJson_Bool(fd, "symmetricalRef") || from == nil do return true
	fromIid := LdtkJson_Str(from, "iid")
	// the old target forgets us
	if old != "" && old != targetIid {
		if _, _, oe, ok := Ldtk_Doc_FindEntity(doc, old); ok {
			if ofi := ldtk_field_of(oe, LdtkJson_Int(fd, "uid")); ofi != nil {
				for i := Ldtk_Doc_FieldArrayLen(doc, ofi) - 1; i >= 0; i -= 1 {
					if t, _ := Ldtk_Doc_FieldText(doc, ofi, i); t == fromIid {
						if LdtkJson_Bool(fd, "isArray") do Ldtk_Doc_FieldArrayRemove(doc, ofi, i)
						else do Ldtk_Doc_SetFieldRaw(doc, ofi, i, "")
					}
				}
			}
		}
	}
	// the new target points back
	if targetIid != "" {
		if _, _, te, ok := Ldtk_Doc_FindEntity(doc, targetIid); ok {
			if tfi := ldtk_field_of(te, LdtkJson_Int(fd, "uid")); tfi != nil {
				n := Ldtk_Doc_FieldArrayLen(doc, tfi)
				for i in 0 ..< n do if t, _ := Ldtk_Doc_FieldText(doc, tfi, i); t == fromIid do return true
				if LdtkJson_Bool(fd, "isArray") {
					if j := Ldtk_Doc_FieldArrayAdd(doc, tfi); j >= 0 do Ldtk_Doc_SetFieldRaw(doc, tfi, j, fromIid)
				} else do Ldtk_Doc_SetFieldRaw(doc, tfi, 0, fromIid)
			}
		}
	}
	return true
}

// Ldtk_Doc_ClearRefsTo removes level li's references to entity `iid` (a
// deleted entity): array values go, single ones become null. Only that
// level, so one level undo step brings them back; references from other
// levels stay and show as lost.
Ldtk_Doc_ClearRefsTo :: proc(doc: ^Ldtk_Doc, li: int, iid: string) {
	if iid == "" || li < 0 || li >= len(doc.levels) do return
	for &ly in doc.levels[li].layers {
		for ent in LdtkJson_Arr(ly.obj, "entityInstances") {
			for fi in LdtkJson_Arr(ent, "fieldInstances") {
				fd := Ldtk_Doc_FieldDef(doc, LdtkJson_Int(fi, "defUid", -1))
				if fd == nil || Ldtk_FieldKindOf(fd) != .EntityRef do continue
				isArray := LdtkJson_Bool(fd, "isArray")
				for i := Ldtk_Doc_FieldArrayLen(doc, fi) - 1; i >= 0; i -= 1 {
					if t, _ := Ldtk_Doc_FieldText(doc, fi, i); t != iid do continue
					if isArray do Ldtk_Doc_FieldArrayRemove(doc, fi, i)
					else do Ldtk_Doc_SetFieldRaw(doc, fi, i, "")
					doc.levels[li].dirty = true
				}
			}
		}
	}
}

@(private = "file")
ldtk_field_of :: proc(ent: ^LdtkJson, fieldUid: int) -> ^LdtkJson {
	for fi in LdtkJson_Arr(ent, "fieldInstances") do if LdtkJson_Int(fi, "defUid", -1) == fieldUid do return fi
	return nil
}

// Ldtk_Doc_FieldDefDefaultSet sets a field def's default ("" = none).
Ldtk_Doc_FieldDefDefaultSet :: proc(doc: ^Ldtk_Doc, fd: ^LdtkJson, text: string) -> bool {
	a := doc.allocator
	if strings.trim_space(text) == "" {
		LdtkJson_SetNull(fd, "defaultOverride", a)
	} else {
		v, ok := ldtk_field_parse(doc, fd, text, a)
		if !ok || v == nil do return false
		LdtkJson_Set(fd, "defaultOverride", v, a)
	}
	// instances showing the default follow
	Ldtk_Doc_RefreshFieldInstances(doc, LdtkJson_Int(fd, "uid"))
	Ldtk_Doc_Touch(doc)
	return true
}

// Ldtk_Doc_RefreshFieldInstances rebuilds every instance of a field def (and
// its entities' smart tile / colour) after a definition change.
Ldtk_Doc_RefreshFieldInstances :: proc(doc: ^Ldtk_Doc, fieldUid: int) {
	for &lv in doc.levels {
		for fi in LdtkJson_Arr(lv.obj, "fieldInstances") do if LdtkJson_Int(fi, "defUid", -1) == fieldUid do Ldtk_Doc_FieldRebuild(doc, fi)
		if lv.extRoot != nil {
			for fi in LdtkJson_Arr(lv.extRoot, "fieldInstances") do if LdtkJson_Int(fi, "defUid", -1) == fieldUid do Ldtk_Doc_FieldRebuild(doc, fi)
		}
		for &ly in lv.layers {
			for ent in LdtkJson_Arr(ly.obj, "entityInstances") {
				hit := false
				for fi in LdtkJson_Arr(ent, "fieldInstances") do if LdtkJson_Int(fi, "defUid", -1) == fieldUid {
					Ldtk_Doc_FieldRebuild(doc, fi)
					hit = true
				}
				if hit {
					Ldtk_Doc_EntitySmart(doc, ent)
					lv.dirty = true
				}
			}
		}
	}
}
