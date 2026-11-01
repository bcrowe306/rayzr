package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// A resource property's field (#266): a picker of the files of its class,
// a drop target for a resource dragged from Assets (another class: a red
// outline and why), Open (the file in the Inspector), and + for a new file,
// this node's own values on top of a file, or a resource embedded in the
// scene (no file). Own values and embedded ones edit in a foldout below,
// with the same rows; an own value is marked and reverts to the file's.
// ============================================================================

@(private = "file")
resFieldOpen: map[string]bool // foldouts open (by field id)

@(private = "file")
Res_Nested :: struct {
	parent:   ^Script_PropsTarget,
	name:     string,
	kind:     e.Resource_Value_Kind,
	ref:      string, // the file (override) / the class (embedded)
	mod:      ^e.ScriptModule,
	own:      map[string]e.ScriptValue, // the value's own values (overrides / embedded)
}

// resource_field draws a resource property's control (inside its row).
resource_field :: proc(state: ^EditorState, t: ^Script_PropsTarget, name: string, info: ^e.ScriptProperty, val: e.ScriptValue, id: string) {
	kind, path, class, own := e.Resource_ParseValue(val.valString)
	propClass := info.resourceClass if info != nil else ""
	set :: proc(state: ^EditorState, t: ^Script_PropsTarget, name, text, label: string) {
		t.record_undo(state, t, label)
		t.set(state, t, name, {type = .String, valString = strings.clone(text)})
	}
	// The foldout arrow (own values / embedded).
	nested := kind == .Override || kind == .Embedded
	if nested {
		open := resFieldOpen[id]
		if UI_IconButton(ICON_FA_CHEVRON_DOWN if open else ICON_FA_CHEVRON_RIGHT, fmt.tprintf("%s.fold", id), "Show / hide its values", size = 22) {
			if resFieldOpen == nil do resFieldOpen = make(map[string]bool)
			if id not_in resFieldOpen do resFieldOpen[strings.clone(id)] = !open
			else do resFieldOpen[id] = !open
		}
		imgui.SameLine(0, 2)
	}
	// The picker.
	fieldMin := imgui.GetCursorScreenPos()
	preview := "None"
	// (Short: the Inspector's column is narrow. The tooltip has it all.)
	short := strings.trim_suffix(filepath.base(path), e.RESOURCE_EXT)
	switch kind {
	case .Path: preview = short
	case .Override: preview = fmt.tprintf("%s *", short)
	case .Embedded: preview = fmt.tprintf("%s %s", ICON_FA_GEM, strings.trim_suffix(filepath.base(class), ".lua"))
	case .None:
	}
	imgui.SetNextItemWidth(max(field_width() - 2 * 26 - (24 if nested else 0), 60))
	if imgui.BeginCombo(fmt.ctprintf("##%s", id), fmt.ctprintf("%s", preview)) {
		if imgui.Selectable("None", kind == .None) do set(state, t, name, "", fmt.tprintf("Clear %s", name))
		for f in Resource_FilesOfClass(state, propClass) {
			if imgui.Selectable(fmt.ctprintf("%s", f), kind == .Path && path == f) do set(state, t, name, f, fmt.tprintf("Edit %s", name))
			Drive_Item(fmt.tprintf("pick:%s", f))
		}
		imgui.EndCombo()
	}
	Drive_Item(id)
	{
		now := ""
		switch kind {
		case .Path: now = path
		case .Override: now = fmt.tprintf("%s with this node's own values (*)", path)
		case .Embedded: now = fmt.tprintf("an embedded %s (in the scene, no file)", class)
		case .None: now = "none"
		}
		UI_Tooltip(fmt.tprintf("%s\n\nPick a file, or drop a .resource.json from Assets. + makes a new one, gives this node its own values, or embeds one in the scene", now))
	}
	// Open: the file in the Inspector (embedded: its class script).
	imgui.SameLine(0, 2)
	canOpen := kind != .None
	if !canOpen do imgui.BeginDisabled(true)
	if UI_IconButton(ICON_FA_UP_RIGHT_FROM_SQUARE, fmt.tprintf("%s.open", id), "Open it: the file in the Inspector (an embedded one: its class script)", size = 24) {
		switch kind {
		case .Path, .Override:
			full, _ := filepath.join({state.projectPath, path}, context.temp_allocator)
			Editor_SelectAsset(state, full)
		case .Embedded: Editor_OpenScript(state, class)
		case .None:
		}
	}
	if !canOpen do imgui.EndDisabled()
	// +: new, own values, embedded.
	imgui.SameLine(0, 2)
	popup := fmt.ctprintf("res_menu_%s", id)
	if UI_IconButton(ICON_FA_PLUS, fmt.tprintf("%s.new", id), "New resource, own values, embed...", size = 24) do imgui.OpenPopup(popup)
	if imgui.BeginPopup(popup) {
		classes := []string{propClass} if propClass != "" else Resource_ClassScripts(state)
		item :: proc(label, id: string) -> bool {
			r := imgui.MenuItem(fmt.ctprintf("%s", label))
			Drive_Item(id)
			return r
		}
		for cls in classes {
			short := strings.trim_suffix(filepath.base(cls), ".lua")
			if item(fmt.tprintf("New %s File...", short), fmt.tprintf("%s.new-file:%s", id, short)) {
				if rel := Editor_NewResource(state, fmt.tprintf("new_%s", short), cls); rel != "" do set(state, t, name, rel, fmt.tprintf("New %s", name))
			}
			if item(fmt.tprintf("New Embedded %s", short), fmt.tprintf("%s.new-embedded:%s", id, short)) {
				set(state, t, name, e.Resource_ValueText(.Embedded, cls, nil, nil, context.temp_allocator), fmt.tprintf("Embed %s", name))
				resource_field_open(id)
			}
		}
		switch kind {
		case .Path:
			imgui.Separator()
			if item("Own Values for This Node", fmt.tprintf("%s.own", id)) {
				set(state, t, name, e.Resource_ValueText(.Override, path, nil, nil, context.temp_allocator), fmt.tprintf("Own values %s", name))
				resource_field_open(id)
			}
			UI_Tooltip("This node gets its own copy of the file: change values here; the rest follow the file")
			if item("Embed a Copy (no file)", fmt.tprintf("%s.embed", id)) do resource_embed_file(state, t, name, path, nil)
		case .Override:
			imgui.Separator()
			if item("Back to the File (drop own values)", fmt.tprintf("%s.drop-own", id)) do set(state, t, name, path, fmt.tprintf("Drop own values %s", name))
			if item("Embed a Copy (no file)", fmt.tprintf("%s.embed", id)) do resource_embed_file(state, t, name, path, own)
		case .Embedded:
			imgui.Separator()
			if item("Save as File...", fmt.tprintf("%s.save-file", id)) {
				mod, _ := e.ScriptManager_LoadModule(class, &state.game.scriptManager)
				if rel := resource_save_embedded(state, class, own, mod); rel != "" do set(state, t, name, rel, fmt.tprintf("Save %s as a file", name))
			}
		case .None:
		}
		imgui.EndPopup()
	}
	// Dropped from Assets onto the field (picker, Open, +): a resource of
	// the property's class; another kind shows a red outline and why.
	resource_drop(state, t, name, id, propClass, fieldMin, imgui.GetItemRectMax())
	// The foldout: own values / embedded ones, with the same rows.
	if nested && resFieldOpen[id] do resource_nested_rows(state, t, name, id, kind, path if kind == .Override else class, own)
}

@(private = "file")
resource_field_open :: proc(id: string) {
	if resFieldOpen == nil do resFieldOpen = make(map[string]bool)
	if id not_in resFieldOpen do resFieldOpen[strings.clone(id)] = true
	else do resFieldOpen[id] = true
}

// (The field a valid resource was last dragged over: the payload is gone
// by the frame the mouse is released, so the drop lands then.)
@(private = "file")
resDropArmed: struct {id, rel: string}

@(private = "file")
resource_drop :: proc(state: ^EditorState, t: ^Script_PropsTarget, name, id, class: string, lo, hiItem: [2]f32) {
	hi := [2]f32{hiItem.x, lo.y + imgui.GetFrameHeight()}
	pl := imgui.GetDragDropPayload()
	if pl == nil || string(cstring(&pl.DataType[0])) != ASSET_PAYLOAD {
		// Released over this field with a valid resource: assign it.
		if resDropArmed.id == id {
			if !imgui.IsMouseDown(.Left) && imgui.IsMouseHoveringRect(lo, hi, false) {
				t.record_undo(state, t, fmt.tprintf("Drop %s", name))
				t.set(state, t, name, {type = .String, valString = strings.clone(resDropArmed.rel)})
			}
			delete(resDropArmed.id)
			delete(resDropArmed.rel)
			resDropArmed = {}
		}
		return
	}
	hovering := imgui.IsMouseHoveringRect(lo, hi, false)
	if !hovering {
		if resDropArmed.id == id {
			delete(resDropArmed.id)
			delete(resDropArmed.rel)
			resDropArmed = {}
		}
		return
	}
	p := (^Asset_Payload)(pl.Data)
	rel := asset_rel_editor(state, string(p.path[:p.len]))
	why := resource_drop_problem(state, rel, class)
	col := col_u32({0.97, 0.45, 0.45, 1}) if why != "" else col_u32(UI_ACCENT)
	imgui.DrawList_AddRect(imgui.GetForegroundDrawList(), lo - 2, hi + 2, col, 3, {}, 2)
	imgui.SetTooltip(fmt.ctprintf("%s", why if why != "" else fmt.tprintf("Drop: %s", rel)))
	if why == "" && resDropArmed.rel != rel {
		delete(resDropArmed.id)
		delete(resDropArmed.rel)
		resDropArmed = {strings.clone(id), strings.clone(rel)}
	}
}

// resource_drop_problem: why a dropped asset can't be this property's ("" fine).
@(private = "file")
resource_drop_problem :: proc(state: ^EditorState, rel, class: string) -> string {
	if !e.Resource_IsPath(rel) do return fmt.tprintf("%s isn't a resource (.resource.json)", filepath.base(rel))
	if class == "" do return ""
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	data, err := os.read_entire_file(full, context.temp_allocator)
	if err != nil do return ""
	file, ok := e.Resource_ParseText(rel, string(data), quiet = true)
	if ok && !e.Resource_ClassMatches(class, file.script) do return fmt.tprintf("This property takes %s resources; %s is a %s", filepath.base(class), filepath.base(rel), filepath.base(file.script))
	return ""
}

// resource_embed_file: the property becomes an embedded copy of a file's
// values (plus own ones).
@(private = "file")
resource_embed_file :: proc(state: ^EditorState, t: ^Script_PropsTarget, name, path: string, own: map[string]e.ScriptValue) {
	full, _ := filepath.join({state.projectPath, path}, context.temp_allocator)
	data, err := os.read_entire_file(full, context.temp_allocator)
	if err != nil do return
	file, ok := e.Resource_ParseText(path, string(data), quiet = true)
	if !ok do return
	values := make(map[string]e.ScriptValue, allocator = context.temp_allocator)
	for k, v in file.values do values[k] = v
	for k, v in own do values[k] = v
	mod, _ := e.ScriptManager_LoadModule(file.script, &state.game.scriptManager)
	text := e.Resource_ValueText(.Embedded, file.script, values, mod, context.temp_allocator)
	t.record_undo(state, t, fmt.tprintf("Embed %s", name))
	t.set(state, t, name, {type = .String, valString = strings.clone(text)})
}

// resource_save_embedded writes an embedded resource as resources/<class>.resource.json.
@(private = "file")
resource_save_embedded :: proc(state: ^EditorState, class: string, values: map[string]e.ScriptValue, mod: ^e.ScriptModule) -> string {
	rel := Editor_NewResource(state, strings.trim_suffix(filepath.base(class), ".lua"), class)
	if rel == "" do return ""
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	text := e.Resource_FileText(class, values, mod, nil, context.temp_allocator)
	_ = os.write_entire_file(full, transmute([]u8)text)
	return rel
}

// resource_nested_rows: the value's own values (overrides over the file's /
// an embedded resource's), as rows under the field.
@(private = "file")
resource_nested_rows :: proc(state: ^EditorState, t: ^Script_PropsTarget, name, id: string, kind: e.Resource_Value_Kind, ref: string, own: map[string]e.ScriptValue) {
	mgr := &state.game.scriptManager
	classPath := ref
	fileValues: map[string]e.ScriptValue
	if kind == .Override {
		full, _ := filepath.join({state.projectPath, ref}, context.temp_allocator)
		data, err := os.read_entire_file(full, context.temp_allocator)
		if err != nil do return
		file, ok := e.Resource_ParseText(ref, string(data), quiet = true)
		if !ok do return
		classPath = file.script
		fileValues = file.values
	}
	mod, ok := e.ScriptManager_LoadModule(classPath, mgr)
	if !ok || mod == nil do return
	// Every declared property: own value, else the file's, else the default.
	values := make(map[string]e.ScriptValue, allocator = context.temp_allocator)
	baseline := make(map[string]e.ScriptValue, allocator = context.temp_allocator)
	for p in mod.properties {
		base := p.defaultVal
		if p.name in fileValues do base = fileValues[p.name]
		baseline[p.name] = base
		values[p.name] = own[p.name] if p.name in own else base
	}
	data := new(Res_Nested, context.temp_allocator)
	data^ = {parent = t, name = name, kind = kind, ref = ref, mod = mod, own = own}
	sub := Script_PropsTarget{
		mod = mod, modulePath = classPath, values = &values, owner = nil,
		idPrefix = fmt.tprintf("%s/%s", t.idPrefix, name), data = data,
		depth = t.depth + 1,
		baseline = &baseline if kind == .Override else nil,
		set = proc(state: ^EditorState, st: ^Script_PropsTarget, key: string, v: e.ScriptValue) {
			d := (^Res_Nested)(st.data)
			next := make(map[string]e.ScriptValue, allocator = context.temp_allocator)
			for k, x in d.own do next[k] = x
			// An override back at the file's value: dropped (it follows the file again).
			if d.kind == .Override && st.baseline != nil && script_value_equal(v, st.baseline[key]) do delete_key(&next, key)
			else do next[key] = v
			text := e.Resource_ValueText(d.kind, d.ref, next, d.mod, context.temp_allocator)
			d.parent.set(state, d.parent, d.name, {type = .String, valString = strings.clone(text)})
		},
		record_undo = proc(state: ^EditorState, st: ^Script_PropsTarget, label: string) {
			d := (^Res_Nested)(st.data)
			d.parent.record_undo(state, d.parent, label)
		},
	}
	script_props_editor(state, &sub)
}
