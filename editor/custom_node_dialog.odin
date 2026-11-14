package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Custom node types in the editor (#154): the New Custom Node dialog (from
// Assets' Custom Nodes section, the + menu, the command palette, Add Node,
// and a node's Save as Custom Node), and adding a type's node to a scene.
//
// The dialog writes nodes/<Name>.node.json (engine/custom_nodes.odin) and,
// when asked, the type's script: a template suited to the base type, or
// one built on the parent type's script (`extends`).
// ============================================================================

// The icons a type can have (its "icon": the name).
CUSTOM_NODE_ICONS := [?]struct {
	name, glyph: string,
}{
	{"puzzle-piece", ""}, {"heart", ""}, {"shield", ""}, {"bolt", ""},
	{"star", ""}, {"skull", ""}, {"coins", ""}, {"gem", ""},
	{"key", ""}, {"door", ""}, {"flag", ""}, {"fire", ""},
	{"bomb", ""}, {"crosshairs", ""}, {"eye", ""}, {"ghost", ""},
	{"robot", ""}, {"bug", ""}, {"user", ""}, {"box", ""},
	{"wand", ""}, {"leaf", ""}, {"droplet", ""}, {"music", ""},
	{"hand", ""}, {"bullseye", ""}, {"cube", ""}, {"location", ""},
}

// CustomNode_Icon: a type's icon glyph (a puzzle piece when it has none).
CustomNode_Icon :: proc(t: ^e.CustomNodeType) -> string {
	if t != nil do for ic in CUSTOM_NODE_ICONS do if ic.name == t.icon do return ic.glyph
	return CUSTOM_NODE_ICONS[0].glyph
}

// CustomNode_Color: a type's colour (the custom-node purple-pink when none).
CustomNode_Color :: proc(t: ^e.CustomNodeType) -> imgui.Vec4 {
	if t != nil && len(t.color) == 9 && t.color[0] == '#' {
		if c, ok := e.Color_FromHex(t.color); ok do return {f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, 1}
	}
	return {0.93, 0.47, 0.80, 1}
}

// Editor_CustomNodesChanged: types were added or changed on disk.
Editor_CustomNodesChanged :: proc(state: ^EditorState) {
	Lua_MarkProjectTypesDirty() // (forgets the loaded types too)
}

// Editor_AddCustomNode adds a node of a type (by its .node.json) at a world
// position, under the insertion parent; undoable, selected.
Editor_AddCustomNode :: proc(state: ^EditorState, rel: string, worldPos: [2]f32) -> ^e.Node {
	if state.activeScene == nil do return nil
	ctx := &state.game.gameContext
	t, problem := e.CustomNode_Get(ctx, rel)
	if t == nil {
		Editor_Log(state, .Error, "%s can't be used: %s", rel, problem)
		return nil
	}
	Editor_RecordUndo(state, fmt.tprintf("Add %s", t.name))
	parent := Editor_InsertionParent(state)
	if root := e.Node_ComponentRoot(state.activeScene.manager, parent); root != nil do parent = e.GetParent(state.activeScene.manager, root)
	node := e.Scene_CreateCustomNode(state.activeScene, t, parent, ctx)
	if node == nil {
		Editor_Log(state, .Error, "A %s could not be created", t.name)
		return nil
	}
	node.name = strings.clone(Editor_UniqueChildName(state, parent, t.name, node), node.allocator)
	node.position = Editor_WorldToLocal(parent, worldPos)
	e.ProcessNodeQueues(state.activeScene.manager, ctx)
	e.Node_SetGlobalPositions(state.activeScene.manager, state.activeScene.rootNode)
	state.selectedNode = node
	Editor_Log(state, .Info, "Added a %s", t.name)
	return node
}

// --- the dialog ------------------------------------------------------------------

@(private = "file")
Script_Choice :: enum {
	New,      // a new script (a template / built on the parent's)
	Existing, // a project script
	None,
}

@(private = "file")
Custom_Node_Dialog :: struct {
	open:        bool,
	focus:       bool,
	name:        [64]u8,
	category:    [64]u8,
	description: [256]u8,
	base:        string, // a built-in type name, or a type's .node.json (heap)
	icon:        int,
	color:       [4]f32,
	script:      Script_Choice,
	template:    int,
	existing:    string, // (Existing) a project script (heap)
	// Save as Custom Node: the node becoming one of the type, and its values.
	from:         ^e.Node,
	fromDefaults: string, // (heap) JSON
	baseFilter:   [64]u8,
}

@(private = "file")
cdlg: Custom_Node_Dialog

@(private = "file")
cdlg_reset :: proc() {
	if cdlg.base != "" do delete(cdlg.base)
	if cdlg.existing != "" do delete(cdlg.existing)
	if cdlg.fromDefaults != "" do delete(cdlg.fromDefaults)
	cdlg = {}
	cdlg.color = {0.93, 0.47, 0.80, 1}
}

// CustomNodeDialog_Open opens the New Custom Node dialog; `base`: a built-in
// type or a type's .node.json to start from.
CustomNodeDialog_Open :: proc(state: ^EditorState, base := "AreaNode") {
	cdlg_reset()
	cdlg.open, cdlg.focus = true, true
	cdlg.base = strings.clone(base)
	cdlg.template = template_index(e.Script_TemplateFor(builtin_typeid(base)))
	// Based on a project type: its category, icon and colour to start with.
	if strings.has_suffix(base, e.CUSTOM_NODE_SUFFIX) {
		if parent, _ := e.CustomNode_Get(&state.game.gameContext, base); parent != nil {
			copy(cdlg.category[:len(cdlg.category) - 1], parent.category)
			for ic, i in CUSTOM_NODE_ICONS do if ic.name == parent.icon do cdlg.icon = i
			c := CustomNode_Color(parent)
			cdlg.color = {c.x, c.y, c.z, 1}
		}
	}
}

// CustomNodeDialog_OpenFromNode: Save as Custom Node - a type made from a
// configured node (its type, values and script); the node becomes one.
CustomNodeDialog_OpenFromNode :: proc(state: ^EditorState, node: ^e.Node) {
	if node == nil || state.activeScene == nil do return
	cdlg_reset()
	cdlg.open, cdlg.focus = true, true
	cdlg.from = node
	cdlg.base = strings.clone(e.Node_TypeName(node))
	cdlg.fromDefaults = e.CustomNode_DefaultsFromNode(node, state.activeScene.manager)
	name := strings.to_pascal_case(node.name, context.temp_allocator)
	if ok, _ := e.CustomNode_IsValidName(name); !ok do name = "MyNode"
	copy(cdlg.name[:len(cdlg.name) - 1], name)
	if inst := cast(^e.ScriptInstance)node.scriptInstance; inst != nil {
		cdlg.script = .Existing
		cdlg.existing = strings.clone(asset_rel_editor(state, inst.modulePath))
	} else {
		cdlg.script = .New
		cdlg.template = template_index(e.Script_TemplateFor(node.typeId))
	}
}

@(private = "file")
template_index :: proc(id: string) -> int {
	for tp, i in e.Script_Templates() do if tp.id == id do return i
	return 0
}

@(private = "file")
builtin_typeid :: proc(name: string) -> typeid {
	if info, ok := e.Node_TypeInfoByName(name); ok do return info.type
	return e.Node
}

@(private = "file")
cstr :: proc(buf: []u8) -> string {
	return strings.trim_space(string(cstring(raw_data(buf))))
}

// The base's label in the dialog: "Area (AreaNode)", or a type's name.
@(private = "file")
base_label :: proc(state: ^EditorState, base: string) -> string {
	if strings.has_suffix(base, e.CUSTOM_NODE_SUFFIX) {
		if t, _ := e.CustomNode_Get(&state.game.gameContext, base); t != nil do return fmt.tprintf("%s  %s (custom)", CustomNode_Icon(t), t.name)
		return base
	}
	for entry in NODE_CATALOG do if entry.typeName == base do return fmt.tprintf("%s  %s (%s)", entry.icon, entry.name, base)
	return base
}

CustomNodeDialog_Render :: proc(state: ^EditorState) {
	if cdlg.open && !imgui.IsPopupOpen("New Custom Node###CustomNodeDialog") do imgui.OpenPopup("New Custom Node###CustomNodeDialog")
	io := imgui.GetIO()
	imgui.SetNextWindowSize({880, 560}, .Appearing)
	imgui.SetNextWindowPos({io.DisplaySize.x * 0.5, io.DisplaySize.y * 0.5}, .Appearing, {0.5, 0.5})
	imgui.PushStyleVarImVec2(.WindowPadding, {16, 14})
	defer imgui.PopStyleVar()
	if !imgui.BeginPopupModal("New Custom Node###CustomNodeDialog", &cdlg.open, {.NoResize, .NoTitleBar}) do return
	ctx := &state.game.gameContext

	UI_PanelTitle(ICON_FA_PUZZLE_PIECE, "New Custom Node" if cdlg.from == nil else "Save as Custom Node")
	imgui.SameLine(0, UI_SPACE)
	UI_DimText("a node type of your own: a base type, a script and default values" if cdlg.from == nil else fmt.tprintf("from %s - it becomes one", cdlg.from.name))
	imgui.Dummy({0, 6})

	parentType: ^e.CustomNodeType
	if strings.has_suffix(cdlg.base, e.CUSTOM_NODE_SUFFIX) do parentType, _ = e.CustomNode_Get(ctx, cdlg.base)
	builtinBase := parentType.base if parentType != nil else cdlg.base

	leftW: f32 = 400
	listH := imgui.GetContentRegionAvail().y - 44
	if imgui.BeginChild("##cn_fields", {leftW, listH}, {}, {}) {
		// Name.
		field_label("Name", 110)
		if cdlg.focus {
			imgui.SetKeyboardFocusHere()
			cdlg.focus = false
		}
		imgui.SetNextItemWidth(-1)
		imgui.InputTextWithHint("##cn_name", "Hurtbox", cstring(raw_data(cdlg.name[:])), len(cdlg.name), {.CharsNoBlank, .AutoSelectAll})
		Drive_Item("customnode.name")
		name := cstr(cdlg.name[:])
		problem := custom_name_problem(state, name)
		if problem != "" {
			imgui.Dummy({110, 0}); imgui.SameLine(0, 0)
			imgui.PushStyleColorImVec4(.Text, UI_WARNING)
			imgui.TextWrapped("%s", strings.clone_to_cstring(problem, context.temp_allocator))
			imgui.PopStyleColor()
		}

		// Base: a built-in type or a project type.
		field_label("Based on", 110)
		imgui.SetNextItemWidth(-1)
		if imgui.BeginCombo("##cn_base", strings.clone_to_cstring(base_label(state, cdlg.base), context.temp_allocator), {.HeightLarge}) {
			imgui.SetNextItemWidth(-1)
			imgui.InputTextWithHint("##cn_base_filter", "Search types", cstring(raw_data(cdlg.baseFilter[:])), len(cdlg.baseFilter), {})
			filter := strings.to_lower(cstr(cdlg.baseFilter[:]), context.temp_allocator)
			if cdlg.from == nil {
				custom := e.CustomNodes_All(ctx)
				if len(custom) > 0 {
					UI_DimText("Project types")
					for t in custom {
						if filter != "" && !strings.contains(strings.to_lower(t.name, context.temp_allocator), filter) do continue
						if imgui.Selectable(fmt.ctprintf("%s  %s##cnb_%s", CustomNode_Icon(t), t.name, t.path), cdlg.base == t.path) {
							delete(cdlg.base)
							cdlg.base = strings.clone(t.path)
						}
						Drive_Item(fmt.tprintf("customnode.base:%s", t.name))
					}
					imgui.Separator()
				}
			}
			UI_DimText("Built-in types")
			for entry in NODE_CATALOG {
				if filter != "" && !strings.contains(strings.to_lower(entry.name, context.temp_allocator), filter) && !strings.contains(strings.to_lower(entry.typeName, context.temp_allocator), filter) do continue
				if cdlg.from != nil && entry.typeName != e.Node_TypeName(cdlg.from) do continue // (the node's own type)
				if imgui.Selectable(fmt.ctprintf("%s  %s  (%s)##cnb_%s", entry.icon, entry.name, entry.typeName, entry.name), cdlg.base == entry.typeName) {
					delete(cdlg.base)
					cdlg.base = strings.clone(entry.typeName)
					cdlg.template = template_index(e.Script_TemplateFor(builtin_typeid(entry.typeName)))
				}
				Drive_Item(fmt.tprintf("customnode.base:%s", entry.typeName))
			}
			imgui.EndCombo()
		}
		Drive_Item("customnode.base")

		// Script.
		field_label("Script", 110)
		parentScript := e.CustomNode_Script(parentType, ctx) if parentType != nil else ""
		newLabel := fmt.ctprintf("New, built on %s", filepath.base(parentScript)) if parentScript != "" else cstring("New, from a template")
		if imgui.RadioButton(newLabel, cdlg.script == .New) do cdlg.script = .New
		Drive_Item("customnode.script-new")
		imgui.Dummy({110, 0}); imgui.SameLine(0, 0)
		if imgui.RadioButton("A project script", cdlg.script == .Existing) do cdlg.script = .Existing
		Drive_Item("customnode.script-existing")
		imgui.Dummy({110, 0}); imgui.SameLine(0, 0)
		noneLabel := fmt.ctprintf("The parent's (%s)", filepath.base(parentScript)) if parentScript != "" else cstring("None")
		if imgui.RadioButton(noneLabel, cdlg.script == .None) do cdlg.script = .None
		Drive_Item("customnode.script-none")
		if cdlg.script == .New && parentScript == "" {
			imgui.Dummy({110, 0}); imgui.SameLine(0, 0)
			imgui.SetNextItemWidth(-1)
			templates := e.Script_Templates()
			if imgui.BeginCombo("##cn_template", strings.clone_to_cstring(templates[cdlg.template].label, context.temp_allocator)) {
				for tp, i in templates {
					if imgui.Selectable(fmt.ctprintf("%s##cnt_%s", tp.label, tp.id), cdlg.template == i) do cdlg.template = i
					Drive_Item(fmt.tprintf("customnode.template:%s", tp.id))
				}
				imgui.EndCombo()
			}
		}
		if cdlg.script == .Existing {
			imgui.Dummy({110, 0}); imgui.SameLine(0, 0)
			imgui.SetNextItemWidth(-1)
			scripts := Editor_ListProjectFiles(state, "scripts", {".lua"})
			if path, ok := asset_picker("customnode.existing", cdlg.existing, scripts, allowNone = false); ok {
				if cdlg.existing != "" do delete(cdlg.existing)
				cdlg.existing = strings.clone(path)
			}
		}

		// Look and place in Add Node.
		field_label("Category", 110)
		imgui.SetNextItemWidth(-1)
		imgui.InputTextWithHint("##cn_category", "Combat, Pickups, ... (Add Node groups by it)", cstring(raw_data(cdlg.category[:])), len(cdlg.category), {})
		Drive_Item("customnode.category")
		field_label("Icon", 110)
		imgui.SetNextItemWidth(160)
		ic := CUSTOM_NODE_ICONS[cdlg.icon]
		if imgui.BeginCombo("##cn_icon", fmt.ctprintf("%s  %s", ic.glyph, ic.name)) {
			for x, i in CUSTOM_NODE_ICONS {
				if imgui.Selectable(fmt.ctprintf("%s  %s##cni_%s", x.glyph, x.name, x.name), cdlg.icon == i) do cdlg.icon = i
			}
			imgui.EndCombo()
		}
		imgui.SameLine(0, UI_SPACE)
		imgui.ColorEdit4("##cn_color", &cdlg.color, {.NoInputs, .NoAlpha})
		UI_Tooltip("Its colour in Add Node and the hierarchy")
		field_label("Description", 110)
		imgui.SetNextItemWidth(-1)
		imgui.InputTextWithHint("##cn_description", "One line: what it does (shown in Add Node)", cstring(raw_data(cdlg.description[:])), len(cdlg.description), {})
		Drive_Item("customnode.description")
	}
	imgui.EndChild()

	// Preview: the files it writes.
	imgui.SameLine(0, 16)
	name := cstr(cdlg.name[:])
	defText, scriptText := custom_preview(state, name, parentType)
	if imgui.BeginChild("##cn_preview", {0, listH}, {}, {}) {
		UI_DimText(fmt.tprintf("nodes/%s.node.json", name if name != "" else "<Name>"))
		preview_box("##cn_def_preview", defText, 150)
		if scriptText != "" {
			UI_DimText(fmt.tprintf("scripts/%s.lua", custom_script_stem(name)))
			preview_box("##cn_script_preview", scriptText, 0)
		}
	}
	imgui.EndChild()

	imgui.Dummy({0, 6})
	create := imgui.IsKeyPressed(.Enter) || imgui.IsKeyPressed(.KeypadEnter)
	imgui.SetCursorPosX(imgui.GetWindowWidth() - 16 - 120 - 90 - UI_SPACE)
	if UI_Button("Cancel", "customnode.cancel", {90, 30}) || imgui.IsKeyPressed(.Escape) {
		cdlg.open = false
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine(0, UI_SPACE)
	problem := custom_name_problem(state, name)
	imgui.BeginDisabled(problem != "")
	if UI_PrimaryButton("Create", "customnode.create", {120, 30}) do create = true
	imgui.EndDisabled()
	if create && problem == "" {
		cdlg.open = false
		imgui.CloseCurrentPopup()
		custom_create(state, name, parentType, builtinBase)
	}
	imgui.EndPopup()
}

// field_label: a dim label in a fixed-width column, the field after it.
field_label :: proc(label: string, width: f32) {
	imgui.AlignTextToFramePadding()
	x := imgui.GetCursorPosX()
	imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
	imgui.TextUnformatted(strings.clone_to_cstring(label, context.temp_allocator))
	imgui.PopStyleColor()
	imgui.SameLine(x + width, 0)
}

@(private = "file")
preview_box :: proc(id: cstring, text: string, height: f32) {
	imgui.PushStyleColorImVec4(.ChildBg, UI_BG_APP)
	if imgui.BeginChild(id, {0, height}, {.Borders}, {.HorizontalScrollbar}) {
		if GlobalFonts.mono != nil do imgui.PushFont(GlobalFonts.mono)
		imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
		imgui.TextUnformatted(strings.clone_to_cstring(text, context.temp_allocator))
		imgui.PopStyleColor()
		if GlobalFonts.mono != nil do imgui.PopFont()
	}
	imgui.EndChild()
	imgui.PopStyleColor()
}

// custom_name_problem: why `name` can't be a new type ("" = it can).
@(private = "file")
custom_name_problem :: proc(state: ^EditorState, name: string) -> string {
	if ok, why := e.CustomNode_IsValidName(name); !ok do return why
	if e.CustomNode_FindByName(&state.game.gameContext, name) != nil do return fmt.tprintf("the project has a %s type already", name)
	full, _ := filepath.join({state.projectPath, "nodes", fmt.tprintf("%s%s", name, e.CUSTOM_NODE_SUFFIX)}, context.temp_allocator)
	if os.exists(full) do return fmt.tprintf("nodes/%s%s exists", name, e.CUSTOM_NODE_SUFFIX)
	return ""
}

@(private = "file")
custom_script_stem :: proc(name: string) -> string {
	s := strings.to_snake_case(name if name != "" else "my_node", context.temp_allocator)
	return s
}

// custom_definition: the dialog's type as a definition (its script: the
// path the new one gets, or the chosen one).
@(private = "file")
custom_definition :: proc(state: ^EditorState, name: string, parentType: ^e.CustomNodeType, builtinBase: string) -> e.CustomNode_Definition {
	d: e.CustomNode_Definition
	d.name = name
	// (Copies: making the script reloads the types, freeing parentType.)
	if parentType != nil do d.inherits = strings.clone(parentType.path, context.temp_allocator)
	else do d.base = strings.clone(builtinBase, context.temp_allocator)
	switch cdlg.script {
	case .New:      d.script = fmt.tprintf("scripts/%s.lua", custom_script_stem(name))
	case .Existing: d.script = strings.clone(cdlg.existing, context.temp_allocator)
	case .None:
	}
	d.icon = CUSTOM_NODE_ICONS[cdlg.icon].name
	d.color = fmt.tprintf("#%02x%02x%02xff", u8(cdlg.color[0] * 255), u8(cdlg.color[1] * 255), u8(cdlg.color[2] * 255))
	d.category = cstr(cdlg.category[:])
	d.description = cstr(cdlg.description[:])
	d.defaults = cdlg.fromDefaults if cdlg.from != nil else custom_starting_defaults(builtinBase) if parentType == nil else ""
	return d
}

// custom_starting_defaults: a new type's defaults - a 32x32 box for the
// physics types (a body or area without a shape does nothing).
@(private = "file")
custom_starting_defaults :: proc(base: string) -> string {
	switch base {
	case "AreaNode":
		return `{"shapes": [{"type": "Box", "size": [32, 32], "isSensor": true, "enableSensorEvents": true}]}`
	case "StaticBodyNode", "KinematicBodyNode", "DynamicBodyNode":
		return `{"shapes": [{"type": "Box", "size": [32, 32]}]}`
	}
	return ""
}

@(private = "file")
custom_script_text :: proc(state: ^EditorState, parentType: ^e.CustomNodeType) -> string {
	if cdlg.script != .New do return ""
	if parentType != nil {
		if ps := e.CustomNode_Script(parentType, &state.game.gameContext); ps != "" do return e.Script_ExtendsTemplate(&state.game.scriptManager, ps)
	}
	return e.Script_Templates()[cdlg.template].text
}

@(private = "file")
custom_preview :: proc(state: ^EditorState, name: string, parentType: ^e.CustomNodeType) -> (def, script: string) {
	builtinBase := parentType.base if parentType != nil else cdlg.base
	d := custom_definition(state, name if name != "" else "MyNode", parentType, builtinBase)
	def = e.CustomNode_DefinitionJSON(d, context.temp_allocator)
	if text := custom_script_text(state, parentType); text != "" {
		stem := custom_script_stem(name)
		script, _ = strings.replace_all(text, "$CLASS$", script_class_name(stem), context.temp_allocator)
		script, _ = strings.replace_all(script, "$NAME$", stem, context.temp_allocator)
	}
	return
}

// custom_create writes the type (and its script), and with Save as Custom
// Node turns the node into one of it.
@(private = "file")
custom_create :: proc(state: ^EditorState, name: string, parentType: ^e.CustomNodeType, builtinBase: string) {
	d := custom_definition(state, name, parentType, builtinBase)
	if cdlg.script == .New {
		// (Its own name if scripts/<name>.lua is taken: Editor_NewScript adds _2.)
		text := strings.clone(custom_script_text(state, parentType), context.temp_allocator) // (parentType: freed by what Editor_NewScript reloads)
		if rel := Editor_NewScript(state, custom_script_stem(name), text); rel != "" do d.script = rel
		else do d.script = ""
	}
	dir, _ := filepath.join({state.projectPath, "nodes"}, context.temp_allocator)
	os.make_directory(dir)
	rel := fmt.tprintf("nodes/%s%s", name, e.CUSTOM_NODE_SUFFIX)
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	if os.write_entire_file(full, transmute([]u8)e.CustomNode_DefinitionJSON(d, context.temp_allocator)) != nil {
		Editor_Log(state, .Error, "Could not write %s", rel)
		return
	}
	Editor_CustomNodesChanged(state)
	Editor_Log(state, .Info, "Created the %s node type (%s)", name, rel)

	// Save as Custom Node: the node is one now (same values: they're its
	// type's); its script becomes the type's.
	if node := cdlg.from; node != nil && state.activeScene != nil {
		Editor_RecordUndo(state, fmt.tprintf("Save as %s", name))
		node.customType = strings.clone(rel, node.allocator)
		node.customMissing = false
		clear(&node.signals) // (its signals are the type's now)
		if d.script != "" {
			inst := cast(^e.ScriptInstance)node.scriptInstance
			if inst == nil || asset_rel_editor(state, inst.modulePath) != d.script {
				node.gameContext = &state.game.gameContext
				e.Script_AttachToNode(node, d.script, nil, &state.game.scriptManager)
			}
		}
		state.selectedNode = node
	}
}
