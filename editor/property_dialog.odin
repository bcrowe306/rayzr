package editor

import "core:fmt"
import "core:strings"
import e "../engine"
import buf "../odin_editor/buffer"
import imgui "lib/imgui"

// ============================================================================
// Add / Edit Property (#208): every field a script property can have - the
// name, its type, default, range, choices, list element, resource class
// (picked from the project's classes), label, help, group - written into the
// script's `properties` table (a preview of the Lua line). A node without a
// script gets one first. Remove asks first: the script lines that use it,
// the nodes with a value saved.
// ============================================================================

@(private = "file")
Prop_Kind :: struct {
	label, lua: string,
}

@(private = "file")
PROP_KINDS := [?]Prop_Kind{
	// (the common ones first: the list shows about eight at once)
	{"Number", "float"}, {"Integer", "int"}, {"Boolean", "bool"}, {"Text", "string"},
	{"Resource", "resource"}, {"Node", "node"}, {"Choice (enum)", "enum"}, {"Range (slider)", "range"},
	{"Vector2", "vector2"}, {"Color", "color"}, {"Texture", "texture"}, {"Audio", "audio"},
	{"Scene", "scene"}, {"Component", "component"}, {"Script", "script"}, {"Level", "level"},
	{"File", "file"}, {"List (array)", "array"}, {"Curve", "curve"}, {"Gradient", "gradient"},
}

// A script made to hold a node's first property: an empty table to fill.
@(private = "file")
PROPS_SCRIPT_TEMPLATE :: `-- $NAME$
---@class $CLASS$ : ScriptInstanceBase
local $CLASS$ = {}

-- Exported properties appear in the Inspector (the Properties tab).
$CLASS$.properties = {
}

function $CLASS$:ready()
end

---@param dt number
function $CLASS$:update(dt)
end

return $CLASS$
`

@(private = "file")
LIST_ELEMS := [?]string{"string", "float", "int", "bool", "color", "vector2", "texture", "audio", "scene", "component", "node", "resource"}

@(private = "file")
pd: struct {
	open:      bool,
	focus:     bool,
	node:      ^e.Node,
	editing:   string, // the property edited ("" = a new one; heap)
	name:      [64]u8,
	kind:      int,
	// Defaults by type
	f:         f32,
	i:         i32,
	b:         bool,
	text:      [256]u8,
	vec:       [2]f32,
	col:       [4]f32,
	choice:    int,
	asset:     string, // heap
	hasRange:  bool,
	min, max:  f32,
	slider:    bool,
	values:    [256]u8, // enum: comma-separated
	elem:      int,
	class:     string, // heap ("" = any)
	local:     int,
	label:     [64]u8,
	tooltip:   [256]u8,
	group:     [64]u8,
	// Remove
	removeOpen: bool,
	removeName: string, // heap
}

@(private = "file")
cbuf :: proc(b: []u8) -> string {return strings.trim_space(string(cstring(raw_data(b))))}

@(private = "file")
pd_reset :: proc() {
	delete(pd.editing)
	delete(pd.asset)
	delete(pd.class)
	delete(pd.removeName)
	pd = {}
	pd.max = 100
	pd.col = {1, 1, 1, 1}
}

// PropertyDialog_Open: add a property to a node's script (editing "" = a
// new one), or edit one it has.
PropertyDialog_Open :: proc(state: ^EditorState, node: ^e.Node, editing := "") {
	pd_reset()
	pd.open, pd.focus, pd.node = true, true, node
	if editing == "" do return
	pd.editing = strings.clone(editing)
	copy(pd.name[:len(pd.name) - 1], editing)
	// Its definition as the script declares it.
	inst := cast(^e.ScriptInstance)node.scriptInstance if node != nil else nil
	if inst == nil do return
	mod := state.game.scriptManager.modules[e.ScriptVFS_NormalizePath(inst.modulePath)] or_else nil
	p := Script_ModProp(mod, editing)
	if p == nil do return
	lua := p.assetKind
	if lua == "" {
		#partial switch p.type {
		case .Float:   lua = "range" if p.slider else "float"
		case .Int:     lua = "int"
		case .Boolean: lua = "bool"
		case .Vector2: lua = "vector2"
		case .Color:   lua = "color"
		case:          lua = "string"
		}
	}
	for k, i in PROP_KINDS do if k.lua == lua do pd.kind = i
	d := p.defaultVal
	pd.f, pd.i, pd.b, pd.vec, pd.col = d.valFloat, i32(d.valInt), d.valBool, d.valVec2, {d.valColor.r, d.valColor.g, d.valColor.b, d.valColor.a}
	if d.type == .String do copy(pd.text[:len(pd.text) - 1], d.valString)
	if lua == "resource" || (len(lua) > 0 && is_asset_kind(lua)) do pd.asset = strings.clone(d.valString)
	pd.hasRange = p.min != 0 || p.max != 0
	pd.min, pd.max = p.min, p.max
	pd.slider = p.slider && lua != "range"
	copy(pd.values[:len(pd.values) - 1], strings.join(p.values[:], ", ", context.temp_allocator))
	for v, i in p.values do if d.type == .String && v == d.valString do pd.choice = i
	for el, i in LIST_ELEMS do if el == p.elem do pd.elem = i
	pd.class = strings.clone(p.resourceClass)
	pd.local = int(p.resourceLocal)
	copy(pd.label[:len(pd.label) - 1], p.label)
	copy(pd.tooltip[:len(pd.tooltip) - 1], p.tooltip)
	copy(pd.group[:len(pd.group) - 1], p.group)
}

// PropertyDialog_Remove asks before taking a property out of the script.
PropertyDialog_Remove :: proc(state: ^EditorState, node: ^e.Node, name: string) {
	pd_reset()
	pd.node = node
	pd.removeOpen = true
	pd.removeName = strings.clone(name)
}

@(private = "file")
is_asset_kind :: proc(k: string) -> bool {
	switch k {
	case "texture", "audio", "scene", "script", "component", "level", "file": return true
	}
	return false
}

// pd_def: the dialog's fields as a definition.
@(private = "file")
pd_def :: proc() -> Prop_Def {
	k := PROP_KINDS[pd.kind].lua
	d := Prop_Def{name = cbuf(pd.name[:]), kind = k, label = cbuf(pd.label[:]), tooltip = cbuf(pd.tooltip[:]), group = cbuf(pd.group[:])}
	switch k {
	case "float", "range":
		d.default = fmt.tprintf("%v", pd.f)
		d.hasRange = pd.hasRange || k == "range"
	case "int":
		d.default = fmt.tprintf("%d", pd.i)
		d.hasRange = pd.hasRange
	case "bool":
		d.default = "true" if pd.b else "false"
	case "string":
		d.default = fmt.tprintf("%q", cbuf(pd.text[:]))
	case "vector2":
		d.default = fmt.tprintf("{{%v, %v}}", pd.vec.x, pd.vec.y)
	case "color":
		d.default = fmt.tprintf("{{%v, %v, %v, %v}}", pd.col.r, pd.col.g, pd.col.b, pd.col.a)
	case "enum":
		vals := make([dynamic]string, context.temp_allocator)
		for v in strings.split(cbuf(pd.values[:]), ",", context.temp_allocator) do if t := strings.trim_space(v); t != "" do append(&vals, t)
		d.values = vals[:]
		if len(vals) > 0 do d.default = fmt.tprintf("%q", vals[clamp(pd.choice, 0, len(vals) - 1)])
	case "resource":
		d.class = pd.class
		d.local = pd.local
		if pd.asset != "" do d.default = fmt.tprintf("%q", pd.asset)
	case "array":
		d.elem = LIST_ELEMS[pd.elem]
		if d.elem == "resource" do d.class = pd.class
	case:
		if is_asset_kind(k) && pd.asset != "" do d.default = fmt.tprintf("%q", pd.asset)
	}
	if d.hasRange do d.min, d.max = pd.min, pd.max
	if (k == "float" || k == "int") && pd.slider do d.slider, d.hasRange = true, true
	return d
}

@(private = "file")
LUA_KEYWORDS := [?]string{"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while", "self", "node"}

// pd_problem: why the name can't be used ("" = it can).
@(private = "file")
pd_problem :: proc(state: ^EditorState, name: string) -> string {
	if name == "" do return "Give it a name."
	for c, i in transmute([]u8)name {
		letter := (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
		if !letter && !(i > 0 && c >= '0' && c <= '9') do return "Letters, digits and _ only, not starting with a digit (it's self.<name> in the script)."
	}
	for k in LUA_KEYWORDS do if k == name do return fmt.tprintf("%s is a Lua word (or the script's own): pick another name.", name)
	if name != pd.editing && pd.node != nil {
		if inst := cast(^e.ScriptInstance)pd.node.scriptInstance; inst != nil && name in inst.properties do return fmt.tprintf("The script has %s already.", name)
	}
	if PROP_KINDS[pd.kind].lua == "enum" && cbuf(pd.values[:]) == "" do return "A choice needs its values (comma-separated)."
	return ""
}

@(private = "file")
field :: proc(label: string) {field_label(label, 110)}

PropertyDialog_Render :: proc(state: ^EditorState) {
	property_remove_render(state)
	TITLE :: "Property###PropertyDialog"
	if pd.open && !imgui.IsPopupOpen(TITLE) do imgui.OpenPopup(TITLE)
	io := imgui.GetIO()
	imgui.SetNextWindowSize({560, 0}, .Appearing)
	imgui.SetNextWindowPos({io.DisplaySize.x * 0.5, io.DisplaySize.y * 0.5}, .Appearing, {0.5, 0.5})
	imgui.PushStyleVarImVec2(.WindowPadding, {16, 14})
	defer imgui.PopStyleVar()
	if !imgui.BeginPopupModal(TITLE, &pd.open, {.NoResize, .NoTitleBar, .AlwaysAutoResize}) do return
	defer imgui.EndPopup()
	node := pd.node
	if node == nil || !e.Node_IsAlive(node) {
		pd.open = false
		imgui.CloseCurrentPopup()
		return
	}
	inst := cast(^e.ScriptInstance)node.scriptInstance
	scriptRel := asset_rel_editor(state, inst.modulePath) if inst != nil else ""
	UI_PanelTitle(ICON_FA_SLIDERS, "Edit Property" if pd.editing != "" else "Add Property")
	if scriptRel != "" {
		users := script_users(state, inst.modulePath)
		UI_DimText(fmt.tprintf("In %s%s", scriptRel, fmt.tprintf(" (used by %d nodes: each gets it)", users) if users > 1 else ""))
	} else {
		UI_DimText(fmt.tprintf("%s has no script: one is made for it (scripts/%s.lua).", node.name, strings.to_snake_case(node.name, context.temp_allocator)))
	}
	imgui.Dummy({0, 6})

	field("Name")
	if pd.focus {
		imgui.SetKeyboardFocusHere()
		pd.focus = false
	}
	imgui.SetNextItemWidth(-1)
	imgui.InputTextWithHint("##pd_name", "speed", cstring(raw_data(pd.name[:])), len(pd.name), {.CharsNoBlank, .AutoSelectAll})
	Drive_Item("prop.name")
	field("Type")
	kinds := make([dynamic]string, context.temp_allocator)
	for k in PROP_KINDS do append(&kinds, k.label)
	imgui.SetNextItemWidth(-1)
	if idx, ok := UI_Combo("prop.type", pd.kind, kinds[:]); ok do pd.kind = idx
	k := PROP_KINDS[pd.kind].lua

	// The default, by type.
	switch k {
	case "float", "range":
		field("Default")
		imgui.SetNextItemWidth(-1)
		imgui.DragFloat("##pd_f", &pd.f, 0.1)
		Drive_Item("prop.default")
	case "int":
		field("Default")
		imgui.SetNextItemWidth(-1)
		imgui.DragInt("##pd_i", &pd.i, 0.2)
		Drive_Item("prop.default")
	case "bool":
		field("Default")
		imgui.Checkbox("##pd_b", &pd.b)
		Drive_Item("prop.default")
	case "string":
		field("Default")
		imgui.SetNextItemWidth(-1)
		imgui.InputText("##pd_text", cstring(raw_data(pd.text[:])), len(pd.text))
		Drive_Item("prop.default")
	case "vector2":
		field("Default")
		imgui.SetNextItemWidth(-1)
		imgui.DragFloat2("##pd_vec", &pd.vec, 0.5)
		Drive_Item("prop.default")
	case "color":
		field("Default")
		imgui.ColorEdit4("##pd_col", &pd.col, {.AlphaBar})
		Drive_Item("prop.default")
	case "enum":
		field("Values")
		imgui.SetNextItemWidth(-1)
		imgui.InputTextWithHint("##pd_values", "Idle, Run, Jump", cstring(raw_data(pd.values[:])), len(pd.values))
		Drive_Item("prop.values")
		vals := make([dynamic]string, context.temp_allocator)
		for v in strings.split(cbuf(pd.values[:]), ",", context.temp_allocator) do if t := strings.trim_space(v); t != "" do append(&vals, t)
		if len(vals) > 0 {
			field("Default")
			imgui.SetNextItemWidth(-1)
			if idx, ok := UI_Combo("prop.default", clamp(pd.choice, 0, len(vals) - 1), vals[:]); ok do pd.choice = idx
		}
	case "resource":
		field("Class")
		pd_class_picker(state)
		field("Default")
		imgui.SetNextItemWidth(-1)
		if path, ok := asset_picker("prop.default", pd.asset, Resource_FilesOfClass(state, pd.class), allowNone = true); ok {
			delete(pd.asset)
			pd.asset = strings.clone(path)
		}
		field("Copies")
		imgui.SetNextItemWidth(-1)
		if idx, ok := UI_Combo("prop.local", pd.local, []string{"The class's setting", "One shared table", "One per component instance"}); ok do pd.local = idx
		UI_Tooltip("local_copy: whether instances share the resource's table or get their own copy")
	case "array":
		field("Of")
		imgui.SetNextItemWidth(-1)
		if idx, ok := UI_Combo("prop.elem", pd.elem, LIST_ELEMS[:]); ok do pd.elem = idx
		if LIST_ELEMS[pd.elem] == "resource" {
			field("Class")
			pd_class_picker(state)
		}
	case "node", "curve", "gradient":
	case:
		if is_asset_kind(k) {
			field("Default")
			imgui.SetNextItemWidth(-1)
			if path, ok := asset_picker("prop.default", pd.asset, Script_AssetFiles(state, k), allowNone = true); ok {
				delete(pd.asset)
				pd.asset = strings.clone(path)
			}
		}
	}
	// Range and slider (numbers).
	if k == "float" || k == "int" || k == "range" {
		field("Range")
		if k != "range" {
			imgui.Checkbox("##pd_hasrange", &pd.hasRange)
			Drive_Item("prop.has-range")
			imgui.SameLine()
		}
		if pd.hasRange || k == "range" {
			imgui.SetNextItemWidth(90)
			imgui.DragFloat("##pd_min", &pd.min, 0.1, 0, 0, "min %g")
			Drive_Item("prop.min")
			imgui.SameLine()
			imgui.SetNextItemWidth(90)
			imgui.DragFloat("##pd_max", &pd.max, 0.1, 0, 0, "max %g")
			Drive_Item("prop.max")
			if k != "range" {
				imgui.SameLine()
				imgui.Checkbox("Slider##pd_slider", &pd.slider)
				Drive_Item("prop.slider")
			}
		}
	}
	field("Label")
	imgui.SetNextItemWidth(-1)
	imgui.InputTextWithHint("##pd_label", "(the name, spaced)", cstring(raw_data(pd.label[:])), len(pd.label))
	Drive_Item("prop.label")
	field("Help")
	imgui.SetNextItemWidth(-1)
	imgui.InputTextWithHint("##pd_tooltip", "what it does (the Inspector's tooltip)", cstring(raw_data(pd.tooltip[:])), len(pd.tooltip))
	Drive_Item("prop.tooltip")
	field("Group")
	imgui.SetNextItemWidth(-1)
	imgui.InputTextWithHint("##pd_group", "(none) - a header the Inspector groups it under", cstring(raw_data(pd.group[:])), len(pd.group))
	Drive_Item("prop.group")

	// The Lua it writes.
	imgui.Dummy({0, 4})
	def := pd_def()
	problem := pd_problem(state, def.name)
	if problem != "" {
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextWrapped("%s", strings.clone_to_cstring(problem, context.temp_allocator))
		imgui.PopStyleColor()
	} else {
		if GlobalFonts.mono != nil do imgui.PushFont(GlobalFonts.mono)
		imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
		imgui.PushTextWrapPos(imgui.GetCursorPosX() + 520)
		imgui.TextWrapped("%s", strings.clone_to_cstring(Prop_EntryLua(def), context.temp_allocator))
		imgui.PopTextWrapPos()
		imgui.PopStyleColor()
		if GlobalFonts.mono != nil do imgui.PopFont()
		Drive_Item("prop.preview")
	}
	if pd.editing != "" && def.name != pd.editing && inst != nil {
		if uses := prop_uses_in(state, inst.modulePath, pd.editing); len(uses) > 0 {
			UI_DimText(fmt.tprintf("Renaming: the script still says self.%s on line(s) %v - change those.", pd.editing, uses))
		}
	}
	imgui.Dummy({0, 6})
	if UI_Button("Cancel", "prop.cancel", {100, 0}) || imgui.IsKeyPressed(.Escape) {
		pd.open = false
		imgui.CloseCurrentPopup()
		return
	}
	imgui.SameLine()
	if problem != "" do imgui.BeginDisabled(true)
	ok := UI_PrimaryButton(fmt.tprintf("%s  %s", ICON_FA_CHECK, "Save" if pd.editing != "" else "Add"), "prop.save", {120, 0})
	if problem != "" do imgui.EndDisabled()
	if ok && problem == "" {
		if Editor_WriteProperty(state, node, def, pd.editing) {
			pd.open = false
			imgui.CloseCurrentPopup()
		}
	}
}

@(private = "file")
pd_class_picker :: proc(state: ^EditorState) {
	classes := Resource_ClassScripts(state)
	names := make([dynamic]string, context.temp_allocator)
	append(&names, "(any class)")
	cur := 0
	for c, i in classes {
		append(&names, c)
		if e.Resource_ClassMatches(pd.class, c) && pd.class != "" do cur = i + 1
	}
	imgui.SetNextItemWidth(-1)
	if idx, ok := UI_Combo("prop.class", cur, names[:]); ok {
		delete(pd.class)
		pd.class = strings.clone(classes[idx - 1]) if idx > 0 else ""
	}
	if len(classes) == 0 do UI_DimText("No resource classes yet (Assets + > New Resource Class).")
	else do UI_Tooltip("Only resources of this class can be picked")
}

// script_users: the nodes in the open scene running a script.
@(private = "file")
script_users :: proc(state: ^EditorState, modulePath: string) -> int {
	n := 0
	if state.activeScene == nil do return 0
	want := e.ScriptVFS_NormalizePath(modulePath)
	for nd in state.activeScene.manager.nodes {
		if nd == nil || nd.scriptInstance == nil do continue
		if e.ScriptVFS_NormalizePath((cast(^e.ScriptInstance)nd.scriptInstance).modulePath) == want do n += 1
	}
	return n
}

@(private = "file")
prop_uses_in :: proc(state: ^EditorState, modulePath, name: string) -> []int {
	rel := asset_rel_editor(state, modulePath)
	doc := code_doc_for_script(state, rel, false)
	if doc == nil do return nil
	return Prop_Uses(buf.buffer_to_string(&doc.buffer, context.temp_allocator), name)
}

// script_rewrite replaces a script's text (one undo step in the Code tab,
// and with the scene in the editor's undo), then saves it: it reloads.
@(private = "file")
script_rewrite :: proc(state: ^EditorState, rel, label: string, edit: proc(text, cls: string, data: rawptr) -> (string, bool), data: rawptr) -> bool {
	doc := code_doc_for_script(state, rel, false)
	if doc == nil {
		Editor_Log(state, .Error, "Can't open %s", rel)
		return false
	}
	b := &doc.buffer
	text := buf.buffer_to_string(b, context.temp_allocator)
	cls := Script_ClassName(text)
	out, ok := edit(text, cls, data)
	if !ok {
		Editor_Log(state, .Error, "%s: its properties table (or `local %s = {{}}`) wasn't found", rel, cls)
		return false
	}
	Editor_RecordUndo(state, label, rel)
	group := buf.buffer_next_group(b)
	last := buf.buffer_line_count(b) - 1
	buf.buffer_delete_range(b, {0, 0}, {last, len(buf.buffer_line_str(b, last))}, group)
	buf.buffer_insert_text(b, {0, 0}, out, group)
	Code_SaveDoc(state, doc)
	return true
}

// Editor_WriteProperty adds or replaces a property in a node's script
// (made first when it has none); `old` = the name it had (a rename moves
// the nodes' values).
Editor_WriteProperty :: proc(state: ^EditorState, node: ^e.Node, def: Prop_Def, old := "") -> bool {
	if node.scriptInstance == nil {
		Editor_RecordUndo(state, "Attach script")
		base := strings.to_snake_case(node.name, context.temp_allocator)
		rel := Editor_NewScript(state, base if base != "" else "properties", PROPS_SCRIPT_TEMPLATE)
		if rel == "" do return false
		node.gameContext = &state.game.gameContext
		if e.Script_AttachToNode(node, rel, nil, &state.game.scriptManager) == nil do return false
		Editor_Log(state, .Info, "Made %s for %s", rel, node.name)
	}
	inst := cast(^e.ScriptInstance)node.scriptInstance
	rel := asset_rel_editor(state, inst.modulePath)
	sm := &state.game.scriptManager
	modKey := e.ScriptVFS_NormalizePath(inst.modulePath)
	// The default before (nodes still at it follow the new one).
	oldDefault: e.ScriptValue
	hadDefault := false
	if old != "" {
		if p := Script_ModProp(sm.modules[modKey] or_else nil, old); p != nil {
			oldDefault, hadDefault = p.defaultVal, true
			if oldDefault.type == .String do oldDefault.valString = strings.clone(oldDefault.valString, context.temp_allocator)
		}
	}
	Ctx :: struct {def: Prop_Def, old: string}
	ctx := Ctx{def, old}
	ok := script_rewrite(state, rel, "Add property" if old == "" else "Edit property", proc(text, cls: string, data: rawptr) -> (string, bool) {
		c := cast(^Ctx)data
		t := text
		if c.old != "" && c.old != c.def.name {
			// A rename: the old entry goes, the new one takes its place.
			if r, rok := Prop_Remove(t, cls, c.old); rok do t = r
		}
		return Prop_Upsert(t, cls, c.def)
	}, &ctx)
	if !ok do return false
	// A rename: each node's value follows (in the open scene).
	if old != "" && old != def.name && state.activeScene != nil {
		want := e.ScriptVFS_NormalizePath(inst.modulePath)
		for nd in state.activeScene.manager.nodes {
			if nd == nil || nd.scriptInstance == nil do continue
			si := cast(^e.ScriptInstance)nd.scriptInstance
			if e.ScriptVFS_NormalizePath(si.modulePath) != want do continue
			if v, has := si.properties[old]; has {
				e.ScriptInstance_SetProperty(si, def.name, v, &state.game.scriptManager)
				delete_key(&si.properties, old)
			}
		}
	}
	// Values still at the old default take the new one (the script reloaded
	// on save).
	if hadDefault && state.activeScene != nil {
		if p := Script_ModProp(sm.modules[modKey] or_else nil, def.name); p != nil {
			for nd in state.activeScene.manager.nodes {
				if nd == nil || nd.scriptInstance == nil do continue
				si := cast(^e.ScriptInstance)nd.scriptInstance
				if e.ScriptVFS_NormalizePath(si.modulePath) != modKey do continue
				if v, has := si.properties[def.name]; has && script_value_equal(v, oldDefault) do e.ScriptInstance_SetProperty(si, def.name, p.defaultVal, sm)
			}
		}
	}
	Editor_Log(state, .Info, "%s %s in %s", "Added" if old == "" else "Updated", def.name, rel)
	return true
}

// property_remove_render: the confirmation - the script lines that use it
// and the nodes with a value saved; Remove takes the entry and the values.
@(private = "file")
property_remove_render :: proc(state: ^EditorState) {
	TITLE :: "Remove Property###RemovePropertyDialog"
	if pd.removeOpen && !imgui.IsPopupOpen(TITLE) do imgui.OpenPopup(TITLE)
	if !imgui.BeginPopupModal(TITLE, &pd.removeOpen, {.NoResize, .AlwaysAutoResize}) do return
	defer imgui.EndPopup()
	node := pd.node
	inst := cast(^e.ScriptInstance)node.scriptInstance if node != nil && e.Node_IsAlive(node) else nil
	if inst == nil {
		pd.removeOpen = false
		imgui.CloseCurrentPopup()
		return
	}
	name := pd.removeName
	rel := asset_rel_editor(state, inst.modulePath)
	uses := prop_uses_in(state, inst.modulePath, name)
	want := e.ScriptVFS_NormalizePath(inst.modulePath)
	saved := 0
	for nd in state.activeScene.manager.nodes {
		if nd == nil || nd.scriptInstance == nil do continue
		si := cast(^e.ScriptInstance)nd.scriptInstance
		if e.ScriptVFS_NormalizePath(si.modulePath) == want && name in si.properties do saved += 1
	}
	imgui.TextUnformatted(fmt.ctprintf("Remove %s from %s?", name, rel))
	if len(uses) > 0 {
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextUnformatted(fmt.ctprintf("The script uses self.%s on line(s) %v: those break.", name, uses))
		imgui.PopStyleColor()
	}
	if saved > 0 do UI_DimText(fmt.tprintf("%d node(s) in this scene have a value: it goes too.", saved))
	UI_DimText("Undo (" + CMD + "+Z) brings it back.")
	imgui.Dummy({0, 6})
	if UI_Button("Cancel", "prop.remove-cancel", {100, 0}) {
		pd.removeOpen = false
		imgui.CloseCurrentPopup()
		return
	}
	imgui.SameLine()
	if UI_PrimaryButton(fmt.tprintf("%s  Remove", ICON_FA_TRASH), "prop.remove-confirm", {120, 0}) {
		n := strings.clone(name, context.temp_allocator)
		ok := script_rewrite(state, rel, "Remove property", proc(text, cls: string, data: rawptr) -> (string, bool) {
			return Prop_Remove(text, cls, (cast(^string)data)^)
		}, &n)
		if ok {
			for nd in state.activeScene.manager.nodes {
				if nd == nil || nd.scriptInstance == nil do continue
				si := cast(^e.ScriptInstance)nd.scriptInstance
				if e.ScriptVFS_NormalizePath(si.modulePath) == want do delete_key(&si.properties, n)
			}
			Editor_Log(state, .Info, "Removed %s from %s", n, rel)
		}
		pd.removeOpen = false
		imgui.CloseCurrentPopup()
	}
}
