package editor

import "core:fmt"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Level editor: field values (the Level tab, for the level or the selected
// entity) - LDtk's FieldInstancesForm
//
// Every type: Int, Float, Bool, String (regex), Multilines, Color, Enum,
// Point (picked in the level), FilePath (project files of the accepted
// types), EntityRef (picked in the level; go to it), Tile (from the palette).
// Arrays: add / remove / reorder. A value using the definition's default is
// marked; Reset brings the default back. Right-click a field for more.
// ============================================================================

// Field_Pick: picking a point / an entity in the canvas for a field value.
Field_Pick :: struct {
	active: bool,
	fi:     ^e.LdtkJson, // the field instance
	idx:    int,         // the value (-1: append to the array)
	owner:  ^e.LdtkJson, // the entity owning it (nil: a level field)
	layer:  int,         // the owner's layer (its grid for points)
	ownerLevel: int,     // the owner's level (references may point into other levels)
	kind:   e.Ldtk_FieldKind,
}

levelPick: Field_Pick

LevelFields_PickActive :: proc() -> bool {return levelPick.active}

LevelFields_CancelPick :: proc() {levelPick = {}}

@(private = "file")
field_changed :: proc(fi: ^e.LdtkJson, i: int, mirror: []^e.LdtkJson, owner: ^e.LdtkJson) {
	L := &GlobalLevel
	doc := L.doc
	if i < len(mirror) {
		for key in ([]string{"__value", "__tile", "realEditorValues"}) {
			e.LdtkJson_Set(mirror[i], key, e.LdtkJson_Clone(e.LdtkJson_Get(fi, key), doc.allocator), doc.allocator)
		}
	}
	if owner != nil do e.Ldtk_Doc_EntitySmart(doc, owner)
	L.doc.levels[L.level].dirty = true
}

// field_error: what is wrong with a value ("" = fine) - FieldInstance
// errors LDtk shows in red.
field_error :: proc(doc: ^e.Ldtk_Doc, fd: ^e.LdtkJson, fi: ^e.LdtkJson, idx: int, owner: ^e.LdtkJson) -> string {
	text, isNull := e.Ldtk_Doc_FieldText(doc, fi, idx)
	kind := e.Ldtk_FieldKindOf(fd)
	if isNull {
		if !e.LdtkJson_Bool(fd, "canBeNull") && kind != .Point && kind != .Path && kind != .EntityRef && kind != .Tile && !e.LdtkJson_Bool(fd, "isArray") do return "required"
		return ""
	}
	#partial switch kind {
	case .EntityRef:
		li, _, target, ok := e.Ldtk_Doc_FindEntity(doc, text)
		if !ok do return "lost reference"
		if owner != nil {
			if allowed, why := e.Ldtk_Doc_RefAllowed(doc, fd, owner, GlobalLevel.level, target, li); !allowed do return why
		}
	case .String:
		if !e.Ldtk_FieldRegexMatch(fd, text) do return "doesn't match the regex"
	case .Path:
		if !e.Ldtk_FieldPathAccepted(fd, text) do return "not an accepted file type"
	}
	return ""
}

// LevelFields_Editor draws the field values of an entity (owner) or a level
// (owner = nil; `mirror` = the same fields in its external file).
LevelFields_Editor :: proc(state: ^EditorState, fields: []^e.LdtkJson, mirror: []^e.LdtkJson, owner: ^e.LdtkJson, ownerLayer: int) {
	L := &GlobalLevel
	doc := L.doc
	if !UI_BeginProps("##fields") do return
	defer UI_EndProps()
	for fi, i in fields {
		fd := e.Ldtk_Doc_FieldDef(doc, e.LdtkJson_Int(fi, "defUid", -1))
		if fd == nil do continue
		name := e.LdtkJson_Str(fi, "__identifier")
		kind := e.Ldtk_FieldKindOf(fd)
		isArray := e.LdtkJson_Bool(fd, "isArray")
		imgui.PushIDInt(i32(i))
		UI_PropLabel(name)
		raw0 := e.Ldtk_Doc_FieldRaw(fi, 0)
		if !isArray && raw0.isDefault {
			// the default is in use: dim, like LDtk
			imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
		}
		help := e.LdtkJson_Str(fd, "doc")
		tip := fmt.tprintf("%s (%s)%s%s", name, e.LdtkJson_Str(fd, "__type"), help != "" ? "\n" : "", help)
		if isArray {
			n := e.Ldtk_Doc_FieldArrayLen(doc, fi)
			UI_DimText(fmt.tprintf("%d value%s", n, n == 1 ? "" : "s"))
			level_tip(tip, "fields")
			imgui.SameLine()
			if UI_IconButton(ICON_FA_PLUS, fmt.tprintf("level.field.add:%s", name), "", false, 22) {
				e.Ldtk_Doc_Checkpoint(doc, L.level, "Add Value")
				j := e.Ldtk_Doc_FieldArrayAdd(doc, fi)
				if j < 0 do Editor_Log(state, .Warn, "%s can't have more values", name)
				field_changed(fi, i, mirror, owner)
				if j >= 0 && (kind == .Point || kind == .EntityRef) do start_pick(fi, j, owner, ownerLayer, kind)
			}
			level_tip(kind == .Point || kind == .EntityRef ? "Add a value (then click in the level to pick it)" : "Add a value", "fields")
			Drive_Item(fmt.tprintf("level.field:%s", name))
			field_menu(state, fd, fi, -1, i, mirror, owner, ownerLayer)
			for j in 0 ..< n {
				imgui.PushIDInt(i32(1000 + j))
				UI_PropLabel(fmt.tprintf("  [%d]", j))
				value_widget(state, fd, fi, j, i, mirror, owner, ownerLayer, kind, true)
				imgui.PopID()
			}
		} else {
			value_widget(state, fd, fi, 0, i, mirror, owner, ownerLayer, kind, false)
			level_tip(fmt.tprintf("%s%s", tip, raw0.isDefault ? "\n(the definition's default; right-click > Reset to default)" : ""), "fields")
			Drive_Item(fmt.tprintf("level.field:%s", name))
			field_menu(state, fd, fi, 0, i, mirror, owner, ownerLayer)
		}
		if !isArray && raw0.isDefault do imgui.PopStyleColor()
		if err := field_error(doc, fd, fi, 0, owner); err != "" && !isArray {
			UI_PropLabel("")
			imgui.PushStyleColorImVec4(.Text, UI_DANGER)
			imgui.TextUnformatted(fmt.ctprintf("%s  %s", ICON_FA_CIRCLE_INFO, err))
			imgui.PopStyleColor()
		}
		imgui.PopID()
	}
}

@(private = "file")
start_pick :: proc(fi: ^e.LdtkJson, idx: int, owner: ^e.LdtkJson, layer: int, kind: e.Ldtk_FieldKind) {
	levelPick = {active = true, fi = fi, idx = idx, owner = owner, layer = layer, kind = kind, ownerLevel = GlobalLevel.level}
}

// value_widget: the editor of one value (array rows also get up / down /
// remove).
@(private = "file")
value_widget :: proc(state: ^EditorState, fd: ^e.LdtkJson, fi: ^e.LdtkJson, idx, i: int, mirror: []^e.LdtkJson, owner: ^e.LdtkJson, ownerLayer: int, kind: e.Ldtk_FieldKind, inArray: bool) {
	L := &GlobalLevel
	doc := L.doc
	name := e.LdtkJson_Str(fi, "__identifier")
	cur, isNull := e.Ldtk_Doc_FieldText(doc, fi, idx)
	set :: proc(state: ^EditorState, fi: ^e.LdtkJson, idx, i: int, mirror: []^e.LdtkJson, owner: ^e.LdtkJson, text: string, live := false) {
		L := &GlobalLevel
		if live do e.Ldtk_Doc_CheckpointOnce(L.doc, L.level, "Edit Field", fi)
		else do e.Ldtk_Doc_Checkpoint(L.doc, L.level, "Edit Field")
		if !e.Ldtk_Doc_SetFieldRaw(L.doc, fi, idx, text) {
			Editor_Log(state, .Warn, "\"%s\" doesn't fit field %s", text, e.LdtkJson_Str(fi, "__identifier"))
			return
		}
		field_changed(fi, i, mirror, owner)
	}
	rowW := imgui.GetContentRegionAvail().x - (inArray ? 3 * 24 : 0)
	imgui.SetNextItemWidth(rowW)
	// the value's tooltip: the field's doc and what it takes
	tip := e.LdtkJson_Str(fd, "doc")
	hint := ""
	#partial switch kind {
	case .Int, .Float:
		hint = "A number (Enter applies)"
		if mn := e.LdtkJson_Get(fd, "min"); mn != nil && mn.kind == .Number do hint = fmt.tprintf("%s, from %v", hint, mn.num)
		if mx := e.LdtkJson_Get(fd, "max"); mx != nil && mx.kind == .Number do hint = fmt.tprintf("%s, up to %v", hint, mx.num)
	case .Bool: hint = "On / off"
	case .Color: hint = "A colour"
	case .Enum: hint = "One of the enum's values"
	case .String: hint = "Text (Enter applies)"
	case .Text: hint = "Several lines of text"
	case .Path: hint = "A file of the project (relative to the .ldtk)"
	case .Point: hint = "A cell of the level: cx,cy (or pick it)"
	}
	valueTip := tip != "" ? fmt.tprintf("%s\n\n%s", tip, hint) : fmt.tprintf("%s: %s", name, hint)
	switch kind {
	case .Bool:
		b := cur == "true"
		if imgui.Checkbox("##f", &b) do set(state, fi, idx, i, mirror, owner, b ? "true" : "false")
		level_tip(valueTip, "fields")
	case .Int, .Float:
		v, _ := strconv.parse_f64(cur)
		buf: [64]u8
		copy(buf[:63], isNull ? "" : cur)
		if imgui.InputTextWithHint("##f", isNull ? "(empty)" : "", cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue, .CharsScientific}) || imgui.IsItemDeactivatedAfterEdit() do set(state, fi, idx, i, mirror, owner, string(cstring(raw_data(buf[:]))))
		level_tip(valueTip, "fields")
		_ = v
	case .Color:
		c := e.Ldtk_ParseHexColor(cur)
		col := [3]f32{f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255}
		if imgui.ColorEdit3("##f", &col, {.NoInputs}) do set(state, fi, idx, i, mirror, owner, e.Ldtk_ColorHex({u8(col[0] * 255 + 0.5), u8(col[1] * 255 + 0.5), u8(col[2] * 255 + 0.5), 255}), true)
		if imgui.IsItemDeactivated() do e.Ldtk_Doc_EndCoalesce(doc)
		level_tip(valueTip, "fields")
		if isNull {
			imgui.SameLine()
			UI_DimText("(empty)")
		}
	case .Enum:
		ed := e.Ldtk_Doc_EnumDef(doc, e.Ldtk_FieldEnumUid(fd))
		if imgui.BeginCombo("##f", fmt.ctprintf("%s", isNull ? "-" : cur)) {
			if (e.LdtkJson_Bool(fd, "canBeNull") || inArray) && imgui.Selectable("-", isNull) do set(state, fi, idx, i, mirror, owner, "")
			for v in e.LdtkJson_Arr(ed, "values") {
				id := e.LdtkJson_Str(v, "id")
				if imgui.Selectable(fmt.ctprintf("%s", id), id == cur) do set(state, fi, idx, i, mirror, owner, id)
				Drive_Item(fmt.tprintf("pick:%s", id))
			}
			imgui.EndCombo()
		}
		level_tip(valueTip, "fields")
	case .String, .Text:
		buf: [1024]u8
		copy(buf[:len(buf) - 1], cur)
		if kind == .Text {
			if imgui.InputTextMultiline("##f", cstring(raw_data(buf[:])), len(buf), {rowW, 60}, {}) do set(state, fi, idx, i, mirror, owner, string(cstring(raw_data(buf[:]))), true)
			if imgui.IsItemDeactivated() do e.Ldtk_Doc_EndCoalesce(doc)
			level_tip(valueTip, "fields")
		} else {
			if imgui.InputTextWithHint("##f", isNull ? "(empty)" : "", cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue}) || imgui.IsItemDeactivatedAfterEdit() do set(state, fi, idx, i, mirror, owner, string(cstring(raw_data(buf[:]))))
			level_tip(valueTip, "fields")
		}
	case .Path:
		buf: [512]u8
		copy(buf[:len(buf) - 1], cur)
		imgui.SetNextItemWidth(rowW - 28)
		if imgui.InputTextWithHint("##f", "(no file)", cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue}) || imgui.IsItemDeactivatedAfterEdit() do set(state, fi, idx, i, mirror, owner, string(cstring(raw_data(buf[:]))))
		level_tip(valueTip, "fields")
		imgui.SameLine(0, 2)
		if UI_IconButton(ICON_FA_FOLDER_OPEN, fmt.tprintf("level.field.file:%s:%d", name, idx), "", false, 24) do imgui.OpenPopup("##pickfile")
		level_tip("Pick a project file (paths are relative to the .ldtk)", "fields")
		if imgui.BeginPopup("##pickfile") {
			files := Editor_ListProjectFiles(state, "", {""})
			count := 0
			for rel in files {
				if !e.Ldtk_FieldPathAccepted(fd, rel) do continue
				count += 1
				if count > 400 do break
				if imgui.Selectable(fmt.ctprintf("%s", rel)) {
					relDoc, err := filepath.rel(doc.dir, level_abs(state, rel), context.temp_allocator)
					set(state, fi, idx, i, mirror, owner, err != nil ? rel : relDoc)
				}
				level_tip("Use this file", "fields")
				Drive_Item(fmt.tprintf("pick:%s", rel))
			}
			if count == 0 do UI_DimText("No project file of an accepted type.")
			imgui.EndPopup()
		}
	case .Point:
		buf: [64]u8
		copy(buf[:63], cur)
		imgui.SetNextItemWidth(rowW - 28)
		if imgui.InputTextWithHint("##f", "cx,cy", cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue}) || imgui.IsItemDeactivatedAfterEdit() do set(state, fi, idx, i, mirror, owner, string(cstring(raw_data(buf[:]))))
		level_tip(valueTip, "fields")
		imgui.SameLine(0, 2)
		picking := levelPick.active && levelPick.fi == fi && levelPick.idx == idx
		if UI_IconButton(ICON_FA_LOCATION_CROSSHAIRS, fmt.tprintf("level.field.pick:%s:%d", name, idx), "", picking, 24) {
			if picking do LevelFields_CancelPick()
			else do start_pick(fi, idx, owner, ownerLayer, .Point)
		}
		level_tip("Pick the point: click a cell in the level (Esc cancels)", "fields")
	case .EntityRef:
		label := "-"
		if !isNull {
			if _, _, target, ok := e.Ldtk_Doc_FindEntity(doc, cur); ok do label = fmt.tprintf("%s  %s", ICON_FA_LINK, e.LdtkJson_Str(target, "__identifier"))
			else do label = "(lost)"
		}
		imgui.AlignTextToFramePadding()
		imgui.TextUnformatted(fmt.ctprintf("%s", label))
		level_tip(isNull ? "No entity" : fmt.tprintf("Points at entity %s", cur), "fields")
		imgui.SameLine()
		picking := levelPick.active && levelPick.fi == fi && levelPick.idx == idx
		if UI_IconButton(ICON_FA_CROSSHAIRS, fmt.tprintf("level.field.pick:%s:%d", name, idx), "", picking, 24) {
			if picking do LevelFields_CancelPick()
			else do start_pick(fi, idx, owner, ownerLayer, .EntityRef)
		}
		level_tip("Pick the entity: click it in the level (Esc cancels)", "fields")
		if !isNull {
			imgui.SameLine(0, 2)
			if UI_IconButton(ICON_FA_UP_RIGHT_FROM_SQUARE, fmt.tprintf("level.field.goto:%s:%d", name, idx), "", false, 24) do level_goto_entity(cur)
			level_tip("Go to that entity (opens its level)", "fields")
			if !inArray {
				// (array values: the remove button)
				imgui.SameLine(0, 2)
				if UI_IconButton(ICON_FA_LINK_SLASH, fmt.tprintf("level.field.unlink:%s:%d", name, idx), "", false, 24) {
					e.Ldtk_Doc_Checkpoint(doc, L.level, "Unlink")
					if owner != nil do e.Ldtk_Doc_SetFieldRef(doc, fi, idx, owner, "") // (symmetrical refs)
					else do e.Ldtk_Doc_SetFieldRaw(doc, fi, idx, "")
					field_changed(fi, i, mirror, owner)
				}
				level_tip("Disconnect: point at no entity", "fields")
			}
		}
	case .Tile:
		ts := e.Ldtk_Doc_Tileset(doc, e.LdtkJson_Int(fd, "tilesetUid", -1))
		if !isNull && ts != nil {
			parts := strings.split(cur, ",", context.temp_allocator)
			if len(parts) == 4 {
				if ptr := level_texture_ptr(ts.uid); ptr != nil {
					x, _ := strconv.parse_int(parts[0])
					y, _ := strconv.parse_int(parts[1])
					w, _ := strconv.parse_int(parts[2])
					h, _ := strconv.parse_int(parts[3])
					tw, th := f32(ptr.width), f32(ptr.height)
					imgui.Image(transmute(imgui.TextureID)ptr, {24, 24}, {f32(x) / tw, f32(y) / th}, {f32(x + w) / tw, f32(y + h) / th})
					imgui.SameLine()
				}
			}
		}
		if UI_Button(ts == nil ? "No tileset" : "Use picked tile", fmt.tprintf("level.field.tile:%s:%d", name, idx)) && ts != nil {
			if len(L.tileSel) > 0 {
				// the palette's selection (in this field's tileset grid)
				src := e.Ldtk_Doc_TileSrc(ts, int(L.tileSel[0]))
				set(state, fi, idx, i, mirror, owner, fmt.tprintf("%d,%d,%d,%d", src.x, src.y, ts.gridSize * L.tileSelW, ts.gridSize * L.tileSelH))
			} else do Editor_Log(state, .Info, "Pick a tile in a tileset palette first")
		}
		level_tip(ts == nil ? "The field has no tileset (Entities tab > the field)" : "Use the tiles picked in a tileset palette", "fields")
	case .Other:
		UI_DimText(isNull ? "-" : cur)
	}
	if inArray {
		imgui.SameLine(0, 2)
		if UI_IconButton(ICON_FA_ARROW_UP, fmt.tprintf("level.field.up:%s:%d", name, idx), "", false, 22) {
			e.Ldtk_Doc_Checkpoint(doc, L.level, "Reorder Values")
			e.Ldtk_Doc_FieldArrayMove(doc, fi, idx, -1)
			field_changed(fi, i, mirror, owner)
		}
		level_tip("Move up", "fields")
		imgui.SameLine(0, 2)
		if UI_IconButton(ICON_FA_ARROW_DOWN, fmt.tprintf("level.field.down:%s:%d", name, idx), "", false, 22) {
			e.Ldtk_Doc_Checkpoint(doc, L.level, "Reorder Values")
			e.Ldtk_Doc_FieldArrayMove(doc, fi, idx, 1)
			field_changed(fi, i, mirror, owner)
		}
		level_tip("Move down", "fields")
		imgui.SameLine(0, 2)
		if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("level.field.remove:%s:%d", name, idx), "", false, 22) {
			e.Ldtk_Doc_Checkpoint(doc, L.level, "Remove Value")
			if kind == .EntityRef && owner != nil do e.Ldtk_Doc_SetFieldRef(doc, fi, idx, owner, "") // (symmetrical refs)
			e.Ldtk_Doc_FieldArrayRemove(doc, fi, idx)
			field_changed(fi, i, mirror, owner)
		}
		level_tip("Remove this value", "fields")
		if err := field_error(doc, fd, fi, idx, owner); err != "" {
			imgui.SameLine()
			imgui.PushStyleColorImVec4(.Text, UI_DANGER)
			imgui.TextUnformatted(fmt.ctprintf("%s", err))
			imgui.PopStyleColor()
		}
	}
}

// field_menu: a field's right-click menu (idx -1: an array's).
@(private = "file")
field_menu :: proc(state: ^EditorState, fd: ^e.LdtkJson, fi: ^e.LdtkJson, idx, i: int, mirror: []^e.LdtkJson, owner: ^e.LdtkJson, ownerLayer: int) {
	L := &GlobalLevel
	doc := L.doc
	if !imgui.BeginPopupContextItem("##fieldctx") do return
	defer imgui.EndPopup()
	isArray := idx < 0
	if !isArray {
		raw := e.Ldtk_Doc_FieldRaw(fi, 0)
		if ctx_item(ICON_FA_ROTATE_LEFT, "Reset to default", "Use the definition's default value", !raw.isDefault) {
			e.Ldtk_Doc_Checkpoint(doc, L.level, "Reset Field")
			e.Ldtk_Doc_SetFieldRaw(doc, fi, 0, "", true)
			field_changed(fi, i, mirror, owner)
		}
		nullable := e.LdtkJson_Bool(fd, "canBeNull")
		if ctx_item(ICON_FA_ERASER, "Clear", "Make it empty (nullable fields)", nullable) {
			e.Ldtk_Doc_Checkpoint(doc, L.level, "Clear Field")
			if e.Ldtk_FieldKindOf(fd) == .EntityRef && owner != nil do e.Ldtk_Doc_SetFieldRef(doc, fi, 0, owner, "")
			else do e.Ldtk_Doc_SetFieldRaw(doc, fi, 0, "")
			field_changed(fi, i, mirror, owner)
		}
		kind := e.Ldtk_FieldKindOf(fd)
		if kind == .Point || kind == .EntityRef {
			if ctx_item(ICON_FA_CROSSHAIRS, "Pick in the level", "Click the point / entity in the canvas") do start_pick(fi, 0, owner, ownerLayer, kind)
		}
	} else {
		if ctx_item(ICON_FA_TRASH, "Remove all values", "Empty the array") {
			e.Ldtk_Doc_Checkpoint(doc, L.level, "Clear Array")
			for e.Ldtk_Doc_FieldArrayLen(doc, fi) > 0 {
				if e.Ldtk_FieldKindOf(fd) == .EntityRef && owner != nil do e.Ldtk_Doc_SetFieldRef(doc, fi, 0, owner, "")
				e.Ldtk_Doc_FieldArrayRemove(doc, fi, 0)
			}
			field_changed(fi, i, mirror, owner)
		}
	}
	if ctx_item(ICON_FA_COPY, "Copy value", "Copy the value as text") do imgui.SetClipboardText(fmt.ctprintf("%s", e.Ldtk_FieldText(fi)))
	imgui.Separator()
	if ctx_item(ICON_FA_SLIDERS, "Edit definition", owner != nil ? "The field in the Entities tab" : "Level fields in the Project tab") {
		if owner != nil {
			LevelDefs_SelectEntity(e.LdtkJson_Int(owner, "defUid", -1))
			LevelEditor_ShowTab(.Entities)
		} else do LevelEditor_ShowTab(.Project)
	}
	if ctx_item(ICON_FA_CIRCLE_QUESTION, "Help", "Fields in the reference") do LevelRef_Open("fields")
}

// level_goto_entity opens an entity's level and selects it.
level_goto_entity :: proc(iid: string) {
	L := &GlobalLevel
	li, layer, ent, ok := e.Ldtk_Doc_FindEntity(L.doc, iid)
	if !ok do return
	LevelEditor_SetLevel(li)
	level_select_entity(layer, ent)
	r := e.Ldtk_Doc_EntityRect(ent)
	p := e.Ldtk_Doc_LevelPos(L.doc, li)
	L.cam = {f32(p.x + r[0] + r[2] / 2), f32(p.y + r[1] + r[3] / 2)}
}
