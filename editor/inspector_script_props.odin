package editor

import "core:c"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// The editor for a script's exported properties (the `properties` table):
// one row per value, grouped, with the widget its declaration asks for
// (enum, array, curve, gradient, slider, asset / node pickers...), help on
// hover and a reset to the default. What it edits and how a change is
// applied come from a Script_PropsTarget, so a node's script (inspector_script)
// and other owners of script values share the same controls.
// ============================================================================

// Script_PropsTarget: the values script_props_editor edits.
Script_PropsTarget :: struct {
	mod:         ^e.ScriptModule,           // the declaring script (nil: not loaded - values only)
	modulePath:  string,                    // its path (help comments are read from it)
	values:      ^map[string]e.ScriptValue, // current values by property name
	owner:       ^e.Node,                   // node references resolve from it (nil = none)
	idPrefix:    string,                    // Drive ids: "<idPrefix>:<name>", "<idPrefix>-group:<group>"
	data:        rawptr,                    // the hooks' context
	// set applies a new value (the editor never writes values itself).
	set:         proc(state: ^EditorState, t: ^Script_PropsTarget, name: string, val: e.ScriptValue),
	// record_undo snapshots before a change.
	record_undo: proc(state: ^EditorState, t: ^Script_PropsTarget, label: string),
	depth:       int,                        // nested under a resource field (indented; #266)
	baseline:    ^map[string]e.ScriptValue, // reset goes back to these (a file's values) instead of the defaults; a differing value is marked
}

// Script_ModProp: a property's declaration in a module (nil when unknown).
Script_ModProp :: proc(mod: ^e.ScriptModule, name: string) -> ^e.ScriptProperty {
	if mod == nil do return nil
	for &p in mod.properties do if p.name == name do return &p
	return nil
}

// script_props_editor draws the rows inside an open UI_BeginProps table.
// Returns the number of rows drawn.
script_props_editor :: proc(state: ^EditorState, t: ^Script_PropsTarget) -> int {
	// Stable order (map order is random): ungrouped first, then by group.
	Keyed :: struct {group, name: string}
	keyed := make([dynamic]Keyed, context.temp_allocator)
	for k in t.values {
		p := Script_ModProp(t.mod, k)
		append(&keyed, Keyed{p.group if p != nil else "", k})
	}
	slice.sort_by(keyed[:], proc(a, b: Keyed) -> bool {return a.group < b.group if a.group != b.group else a.name < b.name})
	lastGroup := ""
	for kk in keyed {
		name := kk.name
		if kk.group != lastGroup {
			lastGroup = kk.group
			UI_PropLabel("")
			imgui.PushStyleColorImVec4(.Text, UI_ACCENT)
			imgui.TextUnformatted(fmt.ctprintf("%s  %s", ICON_FA_LAYER_GROUP, kk.group))
			imgui.PopStyleColor()
			Drive_Item(fmt.tprintf("%s-group:%s", t.idPrefix, kk.group))
		}
		script_prop_row(state, t, name)
	}
	return len(keyed)
}

// script_prop_one draws one property's row (an exposed property on a
// component instance, #85); `label` = "" for its own.
script_prop_one :: proc(state: ^EditorState, t: ^Script_PropsTarget, name: string, label := "") {
	script_prop_row(state, t, name, label)
}

@(private = "file")
script_prop_row :: proc(state: ^EditorState, t: ^Script_PropsTarget, name: string, labelOverride := "") {
	val := t.values[name]
	info := Script_ModProp(t.mod, name)
	propLabel := info.label if info != nil && info.label != "" else pretty_name(name)
	if labelOverride != "" do propLabel = labelOverride
	// Nested under a resource field: indented; an own value (not the file's) marked.
	if t.baseline != nil && name in t.baseline^ && !script_value_equal(val, t.baseline[name]) do propLabel = fmt.tprintf("%s *", propLabel)
	if t.depth > 0 do propLabel = fmt.tprintf("%s%s", strings.repeat("    ", t.depth, context.temp_allocator), propLabel)
	prop_label(propLabel, t.owner, fmt.tprintf("script.%s", name), script_lua_value(val))
	TIP :: imgui.HoveredFlags_DelayNormal | imgui.HoveredFlags_Stationary
	if imgui.IsItemHovered() {
		// Help: `tooltip = "..."`, else the `---` comment above it in the script.
		help := info.tooltip if info != nil else ""
		if help == "" {
			path := code_abs_path(state, asset_rel_editor(state, t.modulePath))
			if data, err := os.read_entire_file(path, context.temp_allocator); err == nil do help = Script_PropComment(string(data), name)
		}
		if info != nil && info.assetKind == "resource" {
			// (#266) How the field works.
			class := fmt.tprintf(" of %s", info.resourceClass) if info.resourceClass != "" else ""
			help = fmt.tprintf("%s%sA resource%s. Pick a file or drop a .resource.json from Assets. + makes a new file, gives this node its own values over a file (the rest follow the file; marked * and reset to the file's), or embeds one in the scene (no file; Save as File later). Open shows the file in the Inspector.", help, "\n\n" if help != "" else "", class)
		}
		if t.baseline != nil && name in t.baseline^ && !script_value_equal(val, t.baseline[name]) do help = fmt.tprintf("%s%sThis node's own value (*): the file has another. Reset goes back to the file's.", help, "\n\n" if help != "" else "")
		script_prop_help(t.owner, t.modulePath, name, propLabel, val, imgui.IsItemHovered(TIP), help)
	}
	id := fmt.tprintf("%s:%s", t.idPrefix, name)
	label := fmt.ctprintf("##%s", id)
	changed := false
	defVal, hasDef := info.defaultVal if info != nil else e.ScriptValue{}, info != nil
	if t.baseline != nil && name in t.baseline^ do defVal, hasDef = t.baseline[name], true
	edit := fmt.tprintf("Edit %s", name)
	reset :: proc(state: ^EditorState, t: ^Script_PropsTarget, name: string, val: e.ScriptValue) {
		t.record_undo(state, t, fmt.tprintf("Reset %s", name))
		t.set(state, t, name, val)
	}
	imgui.SetNextItemWidth(field_width())
	// Node references need a node (a resource has none).
	if t.owner == nil && info != nil && (info.assetKind == "node" || (info.assetKind == "array" && info.elem == "node")) {
		UI_DimText("(a node reference: not on a resource)")
		return
	}
	// Enum, lists (array / curve / gradient), sliders.
	if info != nil && val.type == .String && (info.assetKind == "enum" || e.Script_IsJsonKind(info.assetKind)) {
		newText := val.valString
		edited := false
		switch info.assetKind {
		case "enum":
			idx := -1
			for v, i in info.values do if v == val.valString do idx = i
			if picked, ok := UI_Combo(id, idx, info.values[:]); ok && picked >= 0 do newText, edited = info.values[picked], true
		case "array":    newText, edited = script_array_field(state, t.owner, id, info.elem, val.valString, info.resourceClass)
		case "curve":    newText, edited = script_curve_field(id, val.valString)
		case "gradient": newText, edited = script_gradient_field(id, val.valString)
		}
		if edited && newText != val.valString {
			t.record_undo(state, t, edit)
			t.set(state, t, name, {type = .String, valString = newText})
		}
		if field_reset(id, hasDef && !script_value_equal(val, defVal)) do reset(state, t, name, defVal)
		return
	}
	if info != nil && info.slider && info.max > info.min && (val.type == .Float || val.type == .Int) {
		if val.type == .Float {
			changed = imgui.SliderFloat(label, &val.valFloat, info.min, info.max, "%.2f")
		} else {
			iv := c.int(val.valInt)
			if imgui.SliderInt(label, &iv, c.int(info.min), c.int(info.max)) {val.valInt = i64(iv); changed = true}
		}
		if imgui.IsItemActivated() do t.record_undo(state, t, edit)
		Drive_Item(id)
		if changed do t.set(state, t, name, val)
		if field_reset(id, hasDef && !script_value_equal(val, defVal)) do reset(state, t, name, defVal)
		return
	}
	if val.type == .Vector2 {
		undo :: proc(state: ^EditorState, label: string, data: rawptr) {
			t := (^Script_PropsTarget)(data)
			t.record_undo(state, t, label)
		}
		if vec2_edit(state, id, &val.valVec2, 0.5, edit, defVal.valVec2 if hasDef else {}, undo = undo, undoData = t) {
			t.set(state, t, name, val)
		}
		return
	}
	switch val.type {
	case .Float:
		changed = imgui.DragFloat(label, &val.valFloat, 0.1, 0, 0, float_format(val.valFloat))
	case .Int:
		iv := c.int(val.valInt)
		if imgui.DragInt(label, &iv, 0.2, 0, 0) {val.valInt = i64(iv); changed = true}
	case .Boolean:
		changed = imgui.Checkbox(label, &val.valBool)
	case .String:
		kind := info.assetKind if info != nil else ""
		if kind == "node" {
			// A node reference: a picker (or drop a node from the tree), saved as a path.
			if path, ok := node_ref_field(state, t.owner, id, val.valString); ok && path != val.valString {
				t.record_undo(state, t, edit)
				val.valString = path
				t.set(state, t, name, val)
			}
			if field_reset(id, val.valString != "") do reset(state, t, name, {type = .String})
			return
		} else if kind == "resource" {
			// A file, this node's own values over one, or an embedded one (#266).
			resource_field(state, t, name, info, val, id)
			if field_reset(id, hasDef && !script_value_equal(val, defVal)) do reset(state, t, name, defVal)
			return
		} else if kind != "" {
			// Assets: only files of the property's kind.
			files := Resource_FilesOfClass(state, info.resourceClass) if kind == "resource" else Script_AssetFiles(state, kind)
			if path, ok := asset_picker(id, val.valString, files, allowNone = true); ok && path != val.valString {
				t.record_undo(state, t, edit)
				val.valString = path
				t.set(state, t, name, val)
			}
			if field_reset(id, hasDef && !script_value_equal(val, defVal)) do reset(state, t, name, defVal)
			return
		}
		buf: [256]u8
		copy(buf[:len(buf) - 1], val.valString)
		if imgui.InputText(label, cstring(raw_data(buf[:])), len(buf), {}) {
			val.valString = strings.clone(string(cstring(raw_data(buf[:]))))
			changed = true
		}
	case .Vector2:
		changed = imgui.DragFloat2(label, &val.valVec2, 0.5, 0, 0, "%.2f")
	case .Color:
		changed = imgui.ColorEdit4(label, &val.valColor, {.AlphaBar})
	}
	if imgui.IsItemActivated() do t.record_undo(state, t, edit)
	Drive_Item(id)
	if changed do t.set(state, t, name, val)
	if field_reset(id, hasDef && !script_value_equal(val, defVal)) do reset(state, t, name, defVal)
}
