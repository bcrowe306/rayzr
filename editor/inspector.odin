package editor

import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Inspector: edits the selected node.
//
// Everything is generic where possible: the PROPERTIES section lists the
// node type's reflected properties (engine/node_properties.odin), so new node
// types and fields appear without editor changes. Resources (texture, audio,
// frames, timer, physics shapes, LDtk), the script and its properties get
// dedicated editors. Every edit is undoable (a snapshot is taken when a
// widget becomes active).
// ============================================================================

inspectorNameBuf: [256]u8
inspectorNameNode: ^e.Node

// undo_on_activate records an undo snapshot when the last widget was just
// activated (start of a drag / text edit / click).
undo_on_activate :: proc(state: ^EditorState, label: string) {
	if imgui.IsItemActivated() do Editor_RecordUndo(state, label)
}

PropertyInspector_RenderWindow :: proc(state: ^EditorState) {
	defer imgui.End()
	inspectorOpen := imgui.Begin("Inspector###InspectorWindow")
	Drive_Window("inspector") // (annotated docs screenshots)
	Dock_Remember(.Right)
	if !inspectorOpen do return
	helpH: f32 = INSPECTOR_HELP_HEIGHT if state.showInspectorHelp else 0
	if imgui.BeginChild("##inspbody", {0, -helpH}, {}, {}) do inspector_body(state)
	imgui.EndChild()
	if state.showInspectorHelp do Inspector_HelpPane(state)
}

@(private = "file")
inspector_body :: proc(state: ^EditorState) {
	if remoteView && RemoteGame_Connected() {
		// The running game's selected node (Scene panel > Remote).
		UI_PanelTitle(ICON_FA_GAMEPAD, "Live in the game")
		RemoteProps_Render(state)
		return
	}
	// A resource picked in Assets (until a node is selected).
	if state.inspectResource && state.inspectResourceNode == state.selectedNode && Editor_AssetSelectedCount(state) == 1 && Asset_KindOf(state.selectedAssetPath) == .Resource {
		ResourceInspector_Render(state, strings.trim_prefix(strings.trim_prefix(state.selectedAssetPath, state.projectPath), "/"))
		return
	}
	ResourceInspector_Flush(state) // (an edit made just before switching away)
	// A row's Revert / Apply (#84), before anything draws the node: the
	// instance is rebuilt.
	if a := inspOverrideAction; a.node != nil {
		inspOverrideAction = {}
		if a.node == state.selectedNode && state.activeScene != nil {
			if a.apply do Editor_ApplyOverride(state, a.node, a.key)
			else do Editor_RevertOverride(state, a.node, a.key)
		}
		delete(a.key)
	}
	inspOverrideNode = nil
	node := state.selectedNode
	if node == nil || state.activeScene == nil {
		imgui.Dummy({0, 24})
		UI_DimText("Nothing selected")
		imgui.PushStyleColorImVec4(.Text, UI_TEXT_FAINT)
		imgui.TextWrapped("Select a node in the viewport or the scene tree to edit it.")
		imgui.PopStyleColor()
		if state.activeScene != nil do scene_settings_pointer()
		return
	}
	isRoot := node == state.activeScene.rootNode

	// --- header: icon, name, type ---
	imgui.PushStyleColorImVec4(.Text, UI_ACCENT)
	imgui.TextUnformatted(strings.clone_to_cstring(Editor_NodeIcon(node), context.temp_allocator))
	imgui.PopStyleColor()
	imgui.SameLine(0, UI_SPACE)
	if inspectorNameNode != node {
		inspectorNameBuf = {}
		copy(inspectorNameBuf[:len(inspectorNameBuf) - 1], node.name)
		inspectorNameNode = node
	}
	imgui.SetNextItemWidth(-1 if isRoot else imgui.GetContentRegionAvail().x - 3 * 30 - 6)
	imgui.PushFont(GlobalFonts.semibold)
	if imgui.InputText("##NodeName", cstring(raw_data(inspectorNameBuf[:])), len(inspectorNameBuf), {.EnterReturnsTrue, .AutoSelectAll}) || imgui.IsItemDeactivatedAfterEdit() {
		newName := strings.trim_space(string(cstring(raw_data(inspectorNameBuf[:]))))
		if newName != "" && newName != node.name && !isRoot {
			Editor_RecordUndo(state, "Rename")
			parent := e.GetParent(state.activeScene.manager, node)
			snap := NodeRefs_Capture(state) // scripts / node properties pointing at it
			node.name = strings.clone(Editor_UniqueChildName(state, parent, newName, node), node.allocator)
			NodeRefs_AfterChange(state, snap)
			inspectorNameNode = nil
		}
	}
	imgui.PopFont()
	Drive_Item("insp.name")
	if !isRoot {
		imgui.SameLine(0, 2)
		if UI_IconButton(ICON_FA_POWER_OFF, "insp.enabled", "Enabled: updates and collides" if node.enabled else "Disabled", node.enabled) {
			Editor_RecordUndo(state, "Toggle enabled")
			on := !node.enabled
			for n in multi_selection(state) do n.enabled = on
			node.enabled = on
		}
		imgui.SameLine(0, 2)
		if UI_IconButton(ICON_FA_EYE if node.renderable else ICON_FA_EYE_SLASH, "insp.visible", "Visible" if node.renderable else "Hidden", node.renderable) {
			Editor_RecordUndo(state, "Toggle visible")
			on := !node.renderable
			for n in multi_selection(state) do n.renderable = on
			node.renderable = on
		}
		imgui.SameLine(0, 2)
		if UI_IconButton(ICON_FA_CIRCLE_QUESTION, "insp.node-docs", fmt.tprintf("%s documentation (Shift+F1)", e.Node_TypeName(node))) do NodeReference_Open(e.Node_TypeName(node))
	}
	imgui.PushFont(GlobalFonts.small)
	// A custom node type: "Hurtbox (AreaNode)" (#156).
	if t := e.Node_CustomType(node); t != nil {
		UI_DimText(fmt.tprintf("%s (%s)", t.name, e.Node_TypeName(node)))
		Drive_Item("insp.node-class")
		UI_Tooltip(fmt.tprintf("A %s: a custom node type (%s) - its values follow the type unless changed here", t.name, node.customType))
	} else {
		UI_DimText(e.Node_TypeName(node))
	}
	imgui.PopFont()
	Inspector_MultiBanner(state)

	// Component (prefab) instances: link banner; their insides are read-only.
	locked := Editor_NodeLocked(state, node)
	if node.componentPath != "" || locked {
		compRoot := e.Node_ComponentRoot(state.activeScene.manager, node)
		UI_BeginBanner()
		{
			imgui.PushStyleColorImVec4(.Text, {0.75, 0.62, 1.0, 1})
			imgui.TextUnformatted(fmt.ctprintf("%s  %s", ICON_FA_CUBES, compRoot.componentPath))
			imgui.PopStyleColor()
			if compRoot.componentMissing {
				imgui.PushStyleColorImVec4(.Text, UI_DANGER)
				imgui.TextWrapped("%s", fmt.ctprintf("%s  Can't load the component: %s. This placeholder keeps the instance's link and overrides; fix the file and reopen the scene.", ICON_FA_TRIANGLE_EXCLAMATION, compRoot.componentProblem if compRoot.componentProblem != "" else "the file is missing"))
				imgui.PopStyleColor()
				Drive_Item("insp.component-missing")
			} else {
			UI_DimText("Part of a component instance. Changes are saved as overrides on this instance." if locked else "Linked component instance. Contents come from the file; changes are saved as overrides.")
			}
			if !compRoot.componentMissing && UI_Button(fmt.tprintf("%s  Edit Component", ICON_FA_CUBES), "insp.edit-component") {
				Editor_EditComponentAt(state, node) // (this node selected there: #86)
			}
			// Overridden values (refreshed a few times a second).
			@(static) cachedFor: ^e.Node
			@(static) cachedFrame: int
			@(static) cachedUndo: int
			@(static) wasEditing: bool
			cached := &inspOverrideKeys
			frame := int(imgui.GetFrameCount())
			// Also right after an edit finishes (a field released, Enter) or an
			// undo step (gizmo drags, menus, undo/redo).
			editing := imgui.IsAnyItemActive()
			editDone := wasEditing && !editing
			wasEditing = editing
			if cachedFor != node || frame - cachedFrame > 15 || editDone || cachedUndo != len(state.undoStack) {
				cachedUndo = len(state.undoStack)
				for s in cached do delete(s)
				clear(cached)
				for k in e.Node_ComponentOverrides(state.activeScene.manager, node) do append(cached, strings.clone(k))
				cachedFor = node
				cachedFrame = frame
			}
			inspOverrideNode = node // (the rows mark these: #84)
			if len(cached) > 0 {
				imgui.SameLine()
				if UI_Button(fmt.tprintf("%s  Revert", ICON_FA_ROTATE_LEFT), "insp.revert-overrides") {
					Editor_RecordUndo(state, "Revert overrides")
					sel := Editor_SaveSelection(state) // (the instance is rebuilt: #74)
					e.Scene_RevertComponentOverrides(state.activeScene, node, &state.game.gameContext)
					Editor_RestoreSelection(state, sel)
					cachedFor = nil
				}
				UI_Tooltip("Drop this node's overrides (all of the instance's, on its root)")
				joined := strings.join(cached[:], ", ", context.temp_allocator)
				imgui.PushStyleColorImVec4(.Text, UI_WARNING)
				imgui.TextWrapped("%s", fmt.ctprintf("Overrides: %s", joined))
				imgui.PopStyleColor()
				Drive_Item("insp.overrides")
			}
			if !locked {
				imgui.SameLine()
				if UI_Button("Unlink", "insp.unlink-component") {
					Editor_RecordUndo(state, "Unlink component")
					e.Node_UnlinkComponent(node)
				}
				UI_Tooltip("Turn this instance into ordinary nodes (saved in full in this scene)")
			}
		}
		UI_EndBanner({0.70, 0.52, 1.0, 0.10})
	}

	// Node / Properties (#208): the script's properties in their own tab.
	if !isRoot && !Inspector_Tabs(state, node) {
		Inspector_PropertiesTab(state, node)
		return
	}
	imgui.Dummy({0, 4})
	if isRoot do scene_settings_pointer()
	Inspector_InstanceSection(state, node) // exposed properties (#85)
	Inspector_ExposedList(state, node)
	if !isRoot && UI_SectionHeader("Transform") {
		if UI_BeginProps("##transform") {
			// Each field edits every selected node (mixed values show "—").
			mpField := node_field(node, &node.position, "position", .Vec2, [2]f32)
			prop_row_label(state, node, "Position", mpField)
			mp := multi_begin(state, node, mpField)
			vec2_edit(state, "insp.position", &node.position, 1, "Move", mixed = mp.mixed)
			multi_end(&mp)
			// The origin (nodes that draw a rectangle): a fraction of the
			// drawn size; reset = the centre.
			if e.Node_HasOrigin(node) {
				moField := node_field(node, &node.pivot, "origin", .Vec2, [2]f32)
				prop_row_label(state, node, "Origin", moField)
				mo := multi_begin(state, node, moField)
				if vec2_edit(state, "insp.origin", &node.pivot, 0.005, "Edit origin", {0.5, 0.5}, mo.mixed) {
					if node.typeId == e.TextureNode do (cast(^e.TextureNode)node).origin = {} // the fraction rules now
					else if node.typeId == e.AtlasSpriteNode do (cast(^e.AtlasSpriteNode)node).origin = {}
				}
				multi_end(&mo)
				size := e.Node_OriginSize(node, &state.game.gameContext)
				UI_Tooltip(fmt.tprintf("%.0f, %.0f px of %.0f × %.0f", node.pivot.x * size.x, node.pivot.y * size.y, size.x, size.y))
				origin_presets(state, node)
			}
			mrField := node_field(node, &node.rotation, "rotation", .Float, f32)
			prop_row_label(state, node, "Rotation", mrField)
			mr := multi_begin(state, node, mrField)
			imgui.SetNextItemWidth(field_width())
			imgui.DragFloat("##rot", &node.rotation, 0.5, -36000, 36000, MIXED_TEXT if mr.mixed[0] else "%.1f°")
			undo_on_activate(state, "Rotate")
			Drive_Item("insp.rotation")
			if field_reset("insp.rotation", node.rotation != 0) {
				Editor_RecordUndo(state, "Reset rotation")
				node.rotation = 0
			}
			multi_end(&mr)
			msField := node_field(node, &node.scale, "scale", .Vec2, [2]f32)
			prop_row_label(state, node, "Scale", msField)
			ms := multi_begin(state, node, msField)
			vec2_edit(state, "insp.scale", &node.scale, 0.01, "Scale", {1, 1}, ms.mixed)
			multi_end(&ms)
			mlField := node_field(node, &node.layer, "layer", .Enum, e.RenderLayer)
			prop_row_label(state, node, "Layer", mlField)
			names := []string{"Layer 1 (back)", "Layer 2", "Layer 3", "Layer 4", "Layer 5", "Layer 6", "Layer 7", "Layer 8 (UI)"}
			defLayer := e.RenderLayer.Layer1
			if d := Editor_DefaultNode(node); d != nil do defLayer = d.layer
			ml := multi_begin(state, node, mlField)
			defer multi_end(&ml)
			imgui.SetNextItemWidth(field_width())
			if layer, changed := UI_Combo("insp.layer", int(node.layer), names, ml.mixed[0]); changed {
				Editor_RecordUndo(state, "Change layer")
				node.layer = e.RenderLayer(layer)
			}
			if field_reset("insp.layer", node.layer != defLayer) {
				Editor_RecordUndo(state, "Reset layer")
				node.layer = defLayer
			}
			mzField := node_field(node, &node.zIndex, "zIndex", .Int, i32)
			prop_row_label(state, node, "Z Index", mzField)
			mz := multi_begin(state, node, mzField)
			imgui.SetNextItemWidth(field_width())
			imgui.DragInt("##zindex", &node.zIndex, 0.1, -4096, 4096, MIXED_TEXT if mz.mixed[0] else "%d")
			undo_on_activate(state, "Z index")
			Drive_Item("insp.z-index")
			UI_Tooltip("Draw order within the layer, added to the parent's: higher draws on top")
			if field_reset("insp.z-index", node.zIndex != 0) {
				Editor_RecordUndo(state, "Reset z index")
				node.zIndex = 0
			}
			multi_end(&mz)
			mysField := node_field(node, &node.ySort, "ySort", .Bool, bool)
			prop_row_label(state, node, "Y Sort Children", mysField)
			mys := multi_begin(state, node, mysField)
			mixed_push(mys.mixed[0])
			imgui.Checkbox("##ysort", &node.ySort)
			mixed_pop(mys.mixed[0])
			undo_on_activate(state, "Y sort")
			Drive_Item("insp.y-sort")
			UI_Tooltip("Draw the children by their Y (lower = in front), each with its children: top-down / isometric depth")
			multi_end(&mys)
			if parent := e.GetParent(state.activeScene.manager, node); parent != nil && parent.ySort {
				myoField := node_field(node, &node.ySortOffset, "ySortOffset", .Float, f32)
				prop_row_label(state, node, "Y Sort Offset", myoField)
				myo := multi_begin(state, node, myoField)
				imgui.SetNextItemWidth(field_width())
				imgui.DragFloat("##ysortoff", &node.ySortOffset, 0.5, -4096, 4096, MIXED_TEXT if myo.mixed[0] else "%.1f")
				undo_on_activate(state, "Y sort offset")
				Drive_Item("insp.y-sort-offset")
				UI_Tooltip("Added to the Y it sorts by: put the line at the feet (the viewport shows it while selected)")
				if field_reset("insp.y-sort-offset", node.ySortOffset != 0) {
					Editor_RecordUndo(state, "Reset y sort offset")
					node.ySortOffset = 0
				}
				multi_end(&myo)
			}
			mpmField := node_field(node, &node.pauseMode, "pauseMode", .Enum, e.Pause_Mode)
			prop_row_label(state, node, "Pause Mode", mpmField)
			mpm := multi_begin(state, node, mpmField)
			defer multi_end(&mpm)
			imgui.SetNextItemWidth(field_width())
			if mode, changed := UI_Combo("insp.pause-mode", int(node.pauseMode), {"Inherit", "Pausable", "Always"}, mpm.mixed[0]); changed {
				Editor_RecordUndo(state, "Pause mode")
				node.pauseMode = e.Pause_Mode(mode)
			}
			UI_Tooltip("Pausable: stops when its parent or the game pauses (Engine.set_paused). Always: keeps running (pause menus)")
			mpaField := node_field(node, &node.paused, "paused", .Bool, bool)
			prop_row_label(state, node, "Paused", mpaField)
			mpa := multi_begin(state, node, mpaField)
			defer multi_end(&mpa)
			mixed_push(mpa.mixed[0])
			imgui.Checkbox("##paused", &node.paused)
			mixed_pop(mpa.mixed[0])
			undo_on_activate(state, "Toggle paused")
			Drive_Item("insp.paused")
			UI_Tooltip("Pauses this node and its children (except Always ones) while the game runs")
			UI_EndProps()
		}
	}

	inspector_resources(state, node)
	if node.typeId == e.ParticleEmitterNode {
		imgui.Dummy({0, 2})
		if UI_PrimaryButton(fmt.tprintf("%s  Open Particle Editor", ICON_FA_WAND_MAGIC_SPARKLES), "insp.particle-editor", {-1, 0}) do particleTabRequest = true
	}
	if node.typeId == e.AnimationPlayerNode {
		imgui.Dummy({0, 2})
		if UI_Button(fmt.tprintf("%s  Open Animation Timeline", ICON_FA_FILM), "insp.animation-editor", {-1, 0}) do animTabRequest = true
	}
	inspector_properties(state, node)
	if !isRoot do Inspector_Tags(state, node)
	if !isRoot do inspector_material(state, node)
	if !isRoot do inspector_script(state, node)
	if !isRoot do Inspector_Signals(state, node)
	PluginInspectors_Render(state, node) // (plugin_extend.odin)

	if !isRoot && UI_SectionHeader("Component", false) {
		imgui.PushStyleColorImVec4(.Text, UI_TEXT_FAINT)
		imgui.TextWrapped("Save this node and its children as a reusable component in components/.")
		imgui.PopStyleColor()
		if UI_Button(fmt.tprintf("%s  Save as Component", ICON_FA_CUBES), "insp.save-component", {-1, 0}) {
			_, _ = Editor_SaveComponent(state, node)
		}
	}
}


// --- reflected properties --------------------------------------------------------

@(private = "file")
inspector_properties :: proc(state: ^EditorState, node: ^e.Node) {
	props := e.Node_CollectProperties(node)
	editable := 0
	runtime := 0
	for p in props {
		if p.runtime do runtime += 1
		else do editable += 1
	}
	if editable > 0 && UI_SectionHeader("Properties") {
		if UI_BeginProps("##props") {
			for p in props {
				if p.runtime || !prop_relevant(node, p.name) do continue
				if len(state.selection) > 1 && !multi_shared(state, node, p) do continue
				prop_label(pretty_name(p.name), node, prop_script_path(node, p), prop_lua_value(p)) // drags into a script
				property_widget(state, node, p, false)
			}
			if node.typeId == e.CharacterMoverNode && (cast(^e.CharacterMoverNode)node).controlMode == .Script {
				UI_PropLabel("")
				UI_DimText("Script mode: the script moves it (character_move_and_slide).")
			}
			UI_EndProps()
		}
	}
	if runtime > 0 && UI_SectionHeader("Runtime State", false) {
		if UI_BeginProps("##runtime") {
			for p in props {
				if !p.runtime do continue
				UI_PropLabel(pretty_name(p.name))
				property_widget(state, node, p, true)
			}
			UI_EndProps()
		}
	}
}

// prop_relevant hides settings that don't apply in the node's current mode
// (a Script-mode CharacterMover ignores the built-in movement settings).
@(private = "file")
prop_relevant :: proc(node: ^e.Node, name: string) -> bool {
	// Textures are picked in the Texture section.
	if (node.typeId == e.NineSliceNode || node.typeId == e.ParallaxNode) && name == "texturePath" do return false
	// Fonts are picked in the Font section.
	if (node.typeId == e.TextNode || node.typeId == e.DialogueNode) && name == "font" do return false
	// (The Vector section picks the file; the preset's style only applies without one.)
	if node.typeId == e.VectorShapeNode {
		if name == "file" || name == "group" || name == "morphTo" || name == "skinBones" do return false
		// (Skinning only means something under a Skeleton.)
		if name == "skinSmooth" && e.VectorShapeNode_SkinTarget(cast(^e.VectorShapeNode)node) == nil do return false
		// (Collider settings only with a collider.)
		switch name {
		case "colliderDetail", "colliderFriction", "colliderBounce", "colliderDensity":
			if (cast(^e.VectorShapeNode)node).collider == .None do return false
		}
		if (cast(^e.VectorShapeNode)node).file != "" {
			switch name {
			case "preset", "fillColor", "strokeColor", "strokeWidth": return false
			}
		}
	}
	// A Tab Container's header is its tab bar (#229); a button with an icon
	// draws its text at the icon's size.
	if node.typeId == e.UITabContainerNode {
		switch name {
		case "title", "showHeader", "headerHeight", "headerColor", "titleColor", "direction", "columns", "autoSizeHeight": return false
		}
	}
	if node.typeId == e.UIButtonNode && name == "fontSize" && (cast(^e.UIButtonNode)node).icon != .None do return false
	// A camera: the Custom shake's settings, Screen Offset only when custom (#215).
	if node.typeId == e.CameraNode {
		cam := cast(^e.CameraNode)node
		switch name {
		case "shakeTypes", "shakeSpeed", "shakeIntensity": return cam.shakePreset == .Custom
		case "screenOffset": return cam.customScreenOffset
		}
	}
	// A Sound Effect: `single` only for the Single mode (#204).
	// An oscillator: Pulse Width for Square, Seed for the noises.
	if node.typeId == e.OscillatorNode {
		o := cast(^e.OscillatorNode)node
		if name == "pulseWidth" do return o.wave == .Square
		if name == "seed" do return o.wave == .Random || o.wave == .Smooth_Noise
	}
	if node.typeId == e.SoundNode && name == "single" && (cast(^e.SoundNode)node).playMode != .Single do return false
	// (The Aseprite section edits these.)
	if node.typeId == e.AsepriteNode {
		switch name {
		case "file", "animation", "hideLayers", "showLayers", "pivotSlice": return false
		}
	}
	// A joint shows only its type's parameters.
	if node.typeId == e.JointNode && strings.has_prefix(name, "joint.") && name != "joint.type" {
		jt := e.JointType_FieldName((cast(^e.JointNode)node).joint.type)
		return strings.has_prefix(name, strings.concatenate({"joint.", jt, "."}, context.temp_allocator))
	}
	if node.typeId == e.CharacterMoverNode && (cast(^e.CharacterMoverNode)node).controlMode == .Script {
		switch name {
		case "targetSpeedX", "maxSpeed", "acceleration", "jumpSpeed", "enableKeyboardInput", "playerIndex": return false
		}
	}
	return true
}

// pretty_name: "emitter.gravityVelocity" -> "Gravity Velocity".
pretty_name :: proc(path: string) -> string {
	name := path
	if i := strings.last_index_byte(path, '.'); i >= 0 do name = path[i + 1:]
	sb := strings.builder_make(context.temp_allocator)
	// camelCase and snake_case: "jumpSpeed" / "jump_speed" -> "Jump Speed".
	upper := true
	for r, i in name {
		if r == '_' {
			if i > 0 do strings.write_byte(&sb, ' ')
			upper = true
			continue
		}
		if i > 0 && r >= 'A' && r <= 'Z' && !upper do strings.write_byte(&sb, ' ')
		strings.write_rune(&sb, r - 32 if upper && r >= 'a' && r <= 'z' else r)
		upper = false
	}
	return strings.to_string(sb)
}

// float_format: plain numbers in drag fields ("1800", not "1.8e+03").
float_format :: proc(v: f32) -> cstring {
	return "%.0f" if abs(v) >= 1000 else "%.3g"
}



// node_ref_field: a node-reference script property - a combo of the
// scene's nodes and a drop target for nodes from the tree; returns the
// picked node's path from `owner`.
node_ref_field :: proc(state: ^EditorState, owner: ^e.Node, id, current: string) -> (path: string, changed: bool) {
	mgr := state.activeScene.manager
	target := e.Node_ResolvePath(mgr, owner, current) if current != "" else nil
	shown := "(none)" if current == "" else (fmt.tprintf("%s  %s", Editor_NodeIcon(target), target.name) if target != nil else fmt.tprintf("%s  %s (missing)", ICON_FA_TRIANGLE_EXCLAMATION, current))
	imgui.SetNextItemWidth(field_width())
	if imgui.BeginCombo(fmt.ctprintf("##%s", id), strings.clone_to_cstring(shown, context.temp_allocator)) {
		if imgui.Selectable("(none)", current == "") do path, changed = "", true
		for n in mgr.nodes {
			if n == nil || n == state.activeScene.rootNode || n.transient do continue
			rel := e.Node_RelativePath(mgr, owner, n)
			if imgui.Selectable(fmt.ctprintf("%s  %s   %s", Editor_NodeIcon(n), n.name, rel), rel == current) do path, changed = rel, true
			Drive_Item(fmt.tprintf("pick:%s", n.name))
		}
		imgui.EndCombo()
	}
	Drive_Item(id)
	UI_Tooltip(fmt.tprintf("A node (path from this one: %q). Pick it, or drop one from the scene tree", current) if current != "" else "Pick a node, or drop one from the scene tree")
	if imgui.BeginDragDropTarget() {
		if pl := imgui.AcceptDragDropPayload("RAYZR_NODE"); pl != nil {
			if n := (^^e.Node)(pl.Data)^; e.Node_IsAlive(n) do path, changed = e.Node_RelativePath(mgr, owner, n), true
		}
		imgui.EndDragDropTarget()
	}
	return
}

// origin_presets: a row with a 3 x 3 grid of common origins (corners, edge
// middles, centre) in a popup.
@(private = "file")
origin_presets :: proc(state: ^EditorState, node: ^e.Node) {
	UI_PropLabel("")
	if UI_Button(fmt.tprintf("%s  Presets", ICON_FA_CROSSHAIRS), "insp.origin-presets") do imgui.OpenPopup("##origin_presets")
	UI_Tooltip("Set the origin to a corner, an edge's middle or the centre")
	if imgui.BeginPopup("##origin_presets") {
		UI_DimText("Origin")
		NAMES := [3][3]string{{"Top Left", "Top", "Top Right"}, {"Left", "Centre", "Right"}, {"Bottom Left", "Bottom", "Bottom Right"}}
		for row in 0 ..< 3 {
			for col in 0 ..< 3 {
				if col > 0 do imgui.SameLine(0, 4)
				p := [2]f32{f32(col) * 0.5, f32(row) * 0.5}
				on := node.pivot == p
				if UI_IconButton(ICON_FA_CIRCLE if on else ICON_FA_CIRCLE_DOT, fmt.tprintf("insp.origin:%s", NAMES[row][col]), NAMES[row][col], on, 28) {
					Editor_RecordUndo(state, "Set origin")
					targets := multi_selection(state)
					if len(targets) == 0 do targets = []^e.Node{node}
					for n in targets do if e.Node_HasOrigin(n) {
						n.pivot = p
						if n.typeId == e.TextureNode do (cast(^e.TextureNode)n).origin = {}
						else if n.typeId == e.AtlasSpriteNode do (cast(^e.AtlasSpriteNode)n).origin = {}
					}
					imgui.CloseCurrentPopup()
				}
			}
		}
		imgui.EndPopup()
	}
}

// --- overridden values (#84) ---------------------------------------------------------
// The inspected instance node's overridden values (keys as
// Node_ComponentOverrides lists them), refreshed by the instance banner;
// their rows are marked and get Revert / Apply in the label's menu.
inspOverrideKeys: [dynamic]string
inspOverrideNode: ^e.Node // (nil: not an instance node this frame)
// A Revert / Apply picked in a row's menu: done at the start of the next
// frame (the instance is rebuilt under the rows drawing it).
inspOverrideAction: struct {
	node:  ^e.Node,
	key:   string,
	apply: bool,
}

// override_key: the override key of an Inspector row's path (the origin is
// saved as "pivot").
override_key :: proc(path: string) -> string {
	return "pivot" if path == "origin" else path
}

// Inspector_IsOverridden: is the row with this path an overridden value of
// the inspected instance node?
Inspector_IsOverridden :: proc(node: ^e.Node, path: string) -> bool {
	if node == nil || path == "" || node != inspOverrideNode do return false
	return slice.contains(inspOverrideKeys[:], override_key(path))
}

// inspector_queue_override: Revert / Apply one row's value (next frame).
inspector_queue_override :: proc(node: ^e.Node, path: string, apply: bool) {
	delete(inspOverrideAction.key)
	inspOverrideAction = {node = node, key = strings.clone(override_key(path)), apply = apply}
}

// prop_row_label: a hand-drawn property row's label, with the help (pane and
// tooltip) and dragging into a script like the generated rows.
prop_row_label :: proc(state: ^EditorState, node: ^e.Node, label: string, p: e.Node_Property) {
	prop_label(label, node, prop_script_path(node, p), prop_lua_value(p))
	TIP :: imgui.HoveredFlags_DelayNormal | imgui.HoveredFlags_Stationary
	if imgui.IsItemHovered() do prop_help(state, node, p, true, imgui.IsItemHovered(TIP))
}

property_widget :: proc(state: ^EditorState, node: ^e.Node, p: e.Node_Property, readonly: bool) {
	id := fmt.tprintf("insp.prop:%s", p.name)
	label := fmt.ctprintf("##%s", id)
	if readonly do imgui.BeginDisabled(true)
	defer if readonly do imgui.EndDisabled()
	undoLabel := fmt.tprintf("Edit %s", pretty_name(p.name))
	// Several nodes selected: shows mixed values, applies the edit (or a
	// reset) to all; deferred first, so it runs last.
	m := multi_begin(state, node, p)
	defer multi_end(&m)
	mixed := m.mixed[0]
	def, hasDef := prop_default(node, p)
	defer if !readonly && p.kind != .Vec2 {
		if field_reset(id, hasDef && !prop_is_default(p, def)) do prop_reset(state, node, p, def)
	}
	// The label (the item just before) or the field: tooltip and help pane.
	TIP :: imgui.HoveredFlags_DelayNormal | imgui.HoveredFlags_Stationary
	labelHovered, labelTip := imgui.IsItemHovered(), imgui.IsItemHovered(TIP)
	defer {
		hovered := labelHovered || imgui.IsItemHovered(imgui.HoveredFlags_AllowWhenDisabled)
		prop_help(state, node, p, hovered, labelTip || imgui.IsItemHovered(TIP | imgui.HoveredFlags_AllowWhenDisabled))
	}
	imgui.SetNextItemWidth(field_width())

	switch p.kind {
	case .Float:
		v := e.Property_GetFloat(p)
		speed: f32 = 0.1
		if p.has_range && p.max - p.min > 0 do speed = (p.max - p.min) / 400
		if imgui.DragFloat(label, &v, speed, p.min if p.has_range else 0, p.max if p.has_range else 0, MIXED_TEXT if mixed else float_format(v)) {
			e.Property_SetFloat(p, v)
		}
		undo_on_activate(state, undoLabel)
	case .Int:
		v := c.int(e.Property_GetInt(p))
		if imgui.DragInt(label, &v, 0.2, c.int(p.min) if p.has_range else 0, c.int(p.max) if p.has_range else 0, MIXED_TEXT if mixed else "%d") {
			e.Property_SetInt(p, i64(v))
		}
		undo_on_activate(state, undoLabel)
	case .Bool:
		mixed_push(mixed)
		imgui.Checkbox(label, (^bool)(p.ptr))
		mixed_pop(mixed)
		undo_on_activate(state, undoLabel)
	case .Vec2:
		dv := (^[2]f32)(def.ptr)^ if hasDef else [2]f32{}
		vec2_edit(state, id, (^[2]f32)(p.ptr), 0.5, undoLabel, dv, m.mixed)
		return
	case .Color:
		col := (^rl.Color)(p.ptr)
		f := [4]f32{f32(col.r) / 255, f32(col.g) / 255, f32(col.b) / 255, f32(col.a) / 255}
		if imgui.ColorEdit4(label, &f, {.AlphaBar, .AlphaPreviewHalf, .NoInputs} if mixed else {.AlphaBar, .AlphaPreviewHalf}) {
			col^ = {u8(f.r * 255 + 0.5), u8(f.g * 255 + 0.5), u8(f.b * 255 + 0.5), u8(f.a * 255 + 0.5)}
		}
		undo_on_activate(state, undoLabel)
		if mixed {
			imgui.SameLine()
			UI_DimText(MIXED_TEXT)
		}
	case .Enum:
		names := e.Property_EnumNames(p)
		cur := e.Property_GetEnumIndex(p)
		preview := MIXED_TEXT if mixed else names[cur] if cur < len(names) else ""
		if imgui.BeginCombo(label, strings.clone_to_cstring(preview, context.temp_allocator)) {
			for n, i in names {
				if imgui.Selectable(strings.clone_to_cstring(n, context.temp_allocator), i == cur) {
					Editor_RecordUndo(state, undoLabel)
					e.Property_SetEnumIndex(p, i)
				}
				Drive_Item(fmt.tprintf("pick:%s", n))
			}
			imgui.EndCombo()
		}
	case .Bit_Set:
		names := e.Property_EnumNames(p)
		// Collision layers show the project's names (Project Settings > Physics).
		isLayers := p.type.id == typeid_of(e.CollisionLayerSet)
		count := 0
		for _, i in names do if e.Property_BitSetHas(p, i) do count += 1
		if imgui.BeginCombo(label, MIXED_TEXT if mixed else fmt.ctprintf("%d selected", count)) {
			for n, i in names {
				on := e.Property_BitSetHas(p, i)
				shown := e.CollisionLayer_DisplayName(e.CollisionLayer(i)) if isLayers && i < 16 else n
				if imgui.Checkbox(fmt.ctprintf("%s##%s", shown, n), &on) {
					Editor_RecordUndo(state, undoLabel)
					e.Property_BitSetSet(p, i, on)
				}
			}
			imgui.EndCombo()
		}
	case .String:
		if p.name == "bus" && (p.owner == "SoundNode" || p.owner == "MusicNode") {
			// The mixer's buses (the Mixer tab); "" = the default (SFX / Music).
			cur := (^string)(p.ptr)^
			def := "SFX" if p.owner == "SoundNode" else "Music"
			names := make([dynamic]string, context.temp_allocator)
			at := 0
			append(&names, fmt.tprintf("(default: %s)", def))
			for b in e.Mixer_Buses() {
				append(&names, b.name)
				if strings.equal_fold(b.name, cur) do at = len(names) - 1
			}
			if k, changed := UI_Combo(id, at, names[:], mixed); changed {
				Editor_RecordUndo(state, undoLabel)
				e.Property_SetString(node, p, "" if k == 0 else names[k])
			}
			UI_Tooltip("The mixer bus it plays into: its fader, effects and output (Mixer tab)")
			return
		}
		buf: [512]u8
		if !mixed do copy(buf[:len(buf) - 1], (^string)(p.ptr)^)
		if imgui.InputTextWithHint(label, MIXED_TEXT if mixed else "", cstring(raw_data(buf[:])), len(buf), {}) {
			e.Property_SetString(node, p, string(cstring(raw_data(buf[:]))))
		}
		undo_on_activate(state, undoLabel)
	case .String_List:
		// One item a line (#227; formats: engine/ui_list_props.odin).
		text := MIXED_TEXT if mixed else strings.join(e.Property_GetList(p), "\n", context.temp_allocator)
		buf := make([]u8, max(len(text) * 2 + 256, 2048), context.temp_allocator)
		copy(buf[:len(buf) - 1], text)
		lines := max(strings.count(text, "\n") + 2, 3)
		if imgui.InputTextMultiline(label, cstring(raw_data(buf)), len(buf), {field_width(), f32(min(lines, 10)) * imgui.GetTextLineHeight() + 8}, {}) {
			typed := string(cstring(raw_data(buf)))
			items := strings.split_lines(typed, context.temp_allocator)
			if typed == "" do items = nil
			e.Property_SetList(node, p, items)
		}
		undo_on_activate(state, undoLabel)
	}
	Drive_Item(id)
}

// --- resources ----------------------------------------------------------------------

// asset_picker shows a combo of project files; returns the chosen path.
asset_picker :: proc(id: string, current: string, files: []string, allowNone := true) -> (chosen: string, picked: bool) {
	preview := filepath.base(current) if current != "" else "None"
	if imgui.BeginCombo(fmt.ctprintf("##%s", id), strings.clone_to_cstring(preview, context.temp_allocator), {.HeightLarge}) {
		if allowNone {
			if imgui.Selectable("None", current == "") do chosen, picked = "", true
		}
		for f in files {
			if imgui.Selectable(strings.clone_to_cstring(f, context.temp_allocator), f == current) {
				chosen, picked = f, true
			}
			Drive_Item(fmt.tprintf("pick:%s", f))
		}
		if len(files) == 0 do UI_DimText("No matching files in the project")
		imgui.EndCombo()
	}
	Drive_Item(id)
	return
}

Editor_SetTexture :: proc(state: ^EditorState, tn: ^e.TextureNode, rel: string) {
	tn.filePath = strings.clone(rel, tn.allocator)
	e.TextureNode_SetTexture(tn, nil) // releases the previous texture
	tn.size = {0, 0}
	if rel == "" do return
	if e.Viewport_IsPath(rel) {
		// A Viewport's picture (drawn at the viewport's size).
		if v := e.Viewport_Find(state.activeScene, rel); v != nil do tn.size = v.size
		return
	}
	ctx := &state.game.gameContext
	rm := &state.game.resourceManager
	tex, ok := rm.loadTexture(rm, e.Project_ResolveAssetPath(ctx, rel))
	if ok && tex != nil {
		tn.texture = tex
		tn.size = {f32(tex.texture.width), f32(tex.texture.height)}
	}
}

Editor_SetAtlasTexture :: proc(state: ^EditorState, an: ^e.AtlasSpriteNode, rel: string) {
	an.filePath = strings.clone(rel, an.allocator)
	e.AtlasSpriteNode_SetTexture(an, nil)
	an.size = {0, 0}
	if rel == "" do return
	ctx := &state.game.gameContext
	rm := &state.game.resourceManager
	tex, ok := rm.loadTexture(rm, e.Project_ResolveAssetPath(ctx, rel))
	if ok && tex != nil {
		an.texture = tex
		if an.region.width <= 0 || an.region.height <= 0 {
			an.region = {0, 0, f32(tex.texture.width), f32(tex.texture.height)}
		}
		an.size = {an.region.width, an.region.height}
	}
}

@(private = "file")
inspector_resources :: proc(state: ^EditorState, node: ^e.Node) {
	ctx := &state.game.gameContext
	rm := &state.game.resourceManager
	switch node.typeId {
	case e.ParticleEmitterNode:
		// (The rest of the look is in the Particles panel's Texture tab.)
		if UI_SectionHeader("Particle Texture") {
			if UI_BeginProps("##ptexture") {
				ParticleTexture_Row(state, cast(^e.ParticleEmitterNode)node, "insp.particle-texture")
				UI_EndProps()
			}
		}
	case e.TextureNode:
		tn := cast(^e.TextureNode)node
		if UI_SectionHeader("Sprite") {
			if UI_BeginProps("##sprite") {
				UI_PropLabel("Texture")
				imgui.SetNextItemWidth(field_width())
				// The textures, and the scene's Viewports' pictures ("viewport:<name>").
				choices := make([dynamic]string, context.temp_allocator)
				append(&choices, ..Editor_ListProjectFiles(state, "textures", TEXTURE_EXTS))
				if state.activeScene != nil && state.activeScene.manager != nil {
					for n in state.activeScene.manager.nodes do if n != nil && n.typeId == e.ViewportNode do append(&choices, e.Viewport_Path(cast(^e.ViewportNode)n))
				}
				if path, ok := asset_picker("insp.texture", tn.filePath, choices[:]); ok {
					Editor_RecordUndo(state, "Set texture")
					Editor_SetTexture(state, tn, path)
				}
				if field_reset("insp.texture", tn.filePath != "") {
					Editor_RecordUndo(state, "Clear texture")
					Editor_SetTexture(state, tn, "")
				}
				if tn.texture != nil || e.Viewport_IsPath(tn.filePath) {
					UI_PropLabel("Size")
					UI_DimText(fmt.tprintf("%.0f × %.0f px", tn.size.x, tn.size.y))
				}
				UI_EndProps()
			}
			if tn.texture != nil {
				w := min(imgui.GetContentRegionAvail().x, 160)
				h := w * tn.size.y / max(tn.size.x, 1)
				imgui.Image(transmute(imgui.TextureID)&tn.texture.texture, {w, h})
			}
		}
	case e.AtlasSpriteNode:
		an := cast(^e.AtlasSpriteNode)node
		if UI_SectionHeader("Atlas Sprite") {
			if UI_BeginProps("##atlas_sprite") {
				UI_PropLabel("Texture")
				imgui.SetNextItemWidth(field_width())
				if path, ok := asset_picker("insp.texture", an.filePath, Editor_ListProjectFiles(state, "textures", TEXTURE_EXTS)); ok {
					Editor_RecordUndo(state, "Set texture")
					Editor_SetAtlasTexture(state, an, path)
				}
				if field_reset("insp.texture", an.filePath != "") {
					Editor_RecordUndo(state, "Clear texture")
					Editor_SetAtlasTexture(state, an, "")
				}
				if an.texture != nil {
					UI_PropLabel("Texture Size")
					UI_DimText(fmt.tprintf("%d × %d px", an.texture.texture.width, an.texture.texture.height))
					UI_PropLabel("Region")
					r := [4]f32{an.region.x, an.region.y, an.region.width, an.region.height}
					imgui.SetNextItemWidth(field_width())
					if imgui.DragFloat4("##atlas_region", &r, 1, 0, 8192, "%.0f") {
						Editor_RecordUndo(state, "Edit Atlas Region")
						e.AtlasSpriteNode_SetRegion(an, rl.Rectangle{r[0], r[1], r[2], r[3]})
					}
					Drive_Item("insp.atlas.region")
					UI_PropLabel("Region Size")
					UI_DimText(fmt.tprintf("%.0f × %.0f px", an.region.width, an.region.height))
				}
				UI_EndProps()
			}
			if an.texture != nil {
				if UI_Button(fmt.tprintf("%s  Edit Region...", ICON_FA_CROP), "insp.atlas.edit", {-1, 0}) {
					AtlasRegion_Open(state, an)
				}
				tw := f32(an.texture.texture.width)
				th := f32(an.texture.texture.height)
				if tw > 0 && th > 0 && an.region.width > 0 && an.region.height > 0 {
					w := min(imgui.GetContentRegionAvail().x, 160)
					h := w * an.region.height / max(an.region.width, 1)
					uv0 := [2]f32{an.region.x / tw, an.region.y / th}
					uv1 := [2]f32{(an.region.x + an.region.width) / tw, (an.region.y + an.region.height) / th}
					imgui.Image(transmute(imgui.TextureID)&an.texture.texture, {w, h}, uv0, uv1)
				}
			}
		}
	case e.FrameAnimationNode:
		fan := cast(^e.FrameAnimationNode)node
		if UI_SectionHeader("Animation") {
			if UI_BeginProps("##anim") {
				UI_PropLabel("Frames")
				UI_DimText(fmt.tprintf("%d frame(s)", len(fan.frames)))
				UI_PropLabel("Frames From")
				dirs := Editor_ListProjectDirs(state, "textures")
				if imgui.BeginCombo("##framesdir", "Choose folder...") {
					for d in dirs {
						if imgui.Selectable(strings.clone_to_cstring(d, context.temp_allocator)) {
							Editor_RecordUndo(state, "Set animation frames")
							e.FrameAnimationNode_ClearFrames(fan)
							for f in Editor_ListProjectFiles(state, d, {".png"}) {
								e.FrameAnimationNode_AddFrame(fan, rm, e.Project_ResolveAssetPath(ctx, f))
							}
							e.FrameAnimationNode_Start(fan)
						}
						Drive_Item(fmt.tprintf("pick:%s", d))
					}
					imgui.EndCombo()
				}
				Drive_Item("insp.frames")
				UI_PropLabel("FPS")
				fps := fan.ticker.framesPerSecond
				imgui.SetNextItemWidth(field_width())
				if imgui.DragFloat("##fps", &fps, 0.2, 1, 120, "%.0f") do fan.ticker->setFPS(fps)
				undo_on_activate(state, "Edit FPS")
				if reset_after(state, "insp.fps", &fps, 12, "FPS") do fan.ticker->setFPS(fps)
				UI_PropLabel("Loop")
				imgui.Checkbox("##loop", &fan.loop)
				undo_on_activate(state, "Toggle loop")
				reset_after(state, "insp.loop", &fan.loop, true, "loop")
				UI_EndProps()
			}
		}
	case e.AnimationPlayerNode:
		apn := cast(^e.AnimationPlayerNode)node
		inspector_animation_player(state, apn)
	case e.SoundNode:
		// Its sounds (#204): a list, previewed by the play mode.
		if UI_SectionHeader("Audio") {
			if UI_BeginProps("##audio") {
				Inspector_SoundList(state, cast(^e.SoundNode)node)
				AudioPreview_Row(state, node) // #196
				UI_EndProps()
			}
		}
	case e.MusicNode:
		if UI_SectionHeader("Audio") {
			if UI_BeginProps("##audio") {
				UI_PropLabel("Audio File")
				mn := cast(^e.MusicNode)node
				current := asset_rel_editor(state, mn.music.filePath) if mn.music != nil else ""
				imgui.SetNextItemWidth(field_width())
				picked, ok := asset_picker("insp.audio", current, Editor_ListProjectFiles(state, "audio", AUDIO_EXTS))
				if field_reset("insp.audio", current != "") {
					picked, ok = "", true
				}
				if path := picked; ok {
					Editor_RecordUndo(state, "Set audio")
					resolved := e.Project_ResolveAssetPath(ctx, path)
					if mn.music != nil do e.ResourceManager_ReleaseMusic(rm, mn.music)
					mn.music = nil
					if path != "" do if m, mok := rm.loadAudioMusic(rm, resolved); mok do mn.music = m
					AudioPreview_Stop() // (the old sound)
				}
				AudioPreview_Row(state, node) // #196
				UI_EndProps()
			}
		}
	case e.TimerNode:
		tm := cast(^e.TimerNode)node
		if UI_SectionHeader("Timer") {
			if UI_BeginProps("##timer") {
				UI_PropLabel("Duration (s)")
				secs := f32(f64(tm.duration) / 1e9)
				imgui.SetNextItemWidth(field_width())
				if imgui.DragFloat("##duration", &secs, 0.05, 0.01, 3600, "%.2f s") do tm->setDuration(secs)
				undo_on_activate(state, "Edit duration")
				Drive_Item("insp.timer.duration")
				if reset_after(state, "insp.timer.duration", &secs, 1, "duration") do tm->setDuration(secs)
				UI_PropLabel("Auto Start")
				imgui.Checkbox("##autostart", &tm.running)
				undo_on_activate(state, "Toggle auto start")
				reset_after(state, "insp.timer.autostart", &tm.running, false, "auto start")
				UI_PropLabel("Loop")
				imgui.Checkbox("##timerloop", &tm.loop)
				undo_on_activate(state, "Toggle loop")
				reset_after(state, "insp.timer.loop", &tm.loop, false, "loop")
				UI_EndProps()
			}
		}
	case e.TileMapNode:
		Inspector_TileMap(state, cast(^e.TileMapNode)node)
	case e.CameraNode:
		inspector_camera_follow(state, cast(^e.CameraNode)node)
	case e.JointNode:
		inspector_joint(state, cast(^e.JointNode)node)
	case e.TextNode, e.DialogueNode:
		inspector_font(state, node)
	case e.NineSliceNode, e.ParallaxNode:
		inspector_texture_path(state, node)
	case e.LineNode:
		inspector_line(state, cast(^e.LineNode)node)
	case e.PathNode:
		inspector_path(state, cast(^e.PathNode)node)
	case e.SpawnerNode:
		inspector_spawner(state, cast(^e.SpawnerNode)node)
	case e.OscillatorNode:
		inspector_oscillator(state, cast(^e.OscillatorNode)node) // (oscillator_editor.odin)
	case e.LevelGeneratorNode:
		inspector_level_generator(state, cast(^e.LevelGeneratorNode)node) // (level_gen_editor.odin)
	case e.SkeletonNode:
		inspector_skeleton(state, cast(^e.SkeletonNode)node)
	case e.AsepriteNode:
		inspector_aseprite(state, cast(^e.AsepriteNode)node) // (aseprite_editor.odin)
	case e.VectorShapeNode:
		inspector_vector(state, cast(^e.VectorShapeNode)node) // (vector_editor.odin)
	case e.AdvancedCameraNode:
		inspector_adv_camera(state, cast(^e.AdvancedCameraNode)node)
	case e.NavigationRegionNode:
		inspector_nav_region(state, cast(^e.NavigationRegionNode)node)
	case e.StateMachineNode:
		inspector_state_machine(state, cast(^e.StateMachineNode)node)
	case e.BehaviorTreeNode:
		inspector_behavior_tree(state, cast(^e.BehaviorTreeNode)node) // (behavior_tree_editor.odin)
	case e.GoapNode:
		inspector_goap(state, cast(^e.GoapNode)node) // (goap_editor.odin)
	case e.LdtkLevelNode:
		ln := cast(^e.LdtkLevelNode)node
		if UI_SectionHeader("LDtk Level") {
			if UI_BeginProps("##ldtk") {
				UI_PropLabel("Project")
				if path, ok := asset_picker("insp.ldtk", asset_rel_editor(state, ln.projectPath), Editor_ListProjectFiles(state, ".", {".ldtk"})); ok {
					Editor_RecordUndo(state, "Set LDtk project")
					e.LdtkLevelNode_SetProject(ln, e.Project_ResolveAssetPath(ctx, path) if path != "" else "", "")
				}
				if ln.projectPath != "" {
					UI_PropLabel("")
					if UI_Button(fmt.tprintf("%s  Edit in Level Tab", ICON_FA_MAP), "insp.ldtk.edit", {-1, 0}) {
						LevelEditor_OpenAt(state, asset_rel_editor(state, ln.projectPath), ln.levelIdentifier)
					}
					UI_PropLabel("")
					if UI_Button(fmt.tprintf("%s  Open in LDtk", ICON_FA_TABLE_CELLS), "insp.ldtk.open", {-1, 0}) {
						Editor_OpenExternally(state, ln.projectPath)
					}
				}
				if ln.project != nil {
					if len(ln.project.worlds) > 1 {
						UI_PropLabel("World")
						names := make([dynamic]string, context.temp_allocator)
						cur := 0
						for w, i in ln.project.worlds {
							append(&names, w.identifier)
							if w.identifier == ln.worldIdentifier do cur = i
						}
						if v, changed := UI_Combo("insp.ldtk.world", cur, names[:]); changed {
							Editor_RecordUndo(state, "Set LDtk world")
							e.LdtkLevelNode_SetWorld(ln, names[v])
						}
					}
					UI_PropLabel("Level")
					cur := ln.level.identifier if ln.level != nil else ""
					if imgui.BeginCombo("##ldtklevel", strings.clone_to_cstring(cur, context.temp_allocator)) {
						if w := e.Ldtk_WorldOf(ln.project, ln.level); w != nil {
							for i in w.levels {
								lvl := &ln.project.levels[i]
								if imgui.Selectable(strings.clone_to_cstring(lvl.identifier, context.temp_allocator), lvl == ln.level) {
									Editor_RecordUndo(state, "Set LDtk level")
									e.LdtkLevelNode_SetLevel(ln, lvl)
								}
								Drive_Item(fmt.tprintf("pick:%s", lvl.identifier))
							}
						}
						imgui.EndCombo()
					}
					Drive_Item("insp.ldtk.level")
					UI_PropLabel("World Mode")
					wm := ln.worldMode
					if imgui.Checkbox("##ldtkworldmode", &wm) {
						Editor_RecordUndo(state, "LDtk world mode")
						e.LdtkLevelNode_SetWorldMode(ln, wm)
					}
					Drive_Item("insp.ldtk.world-mode")
					UI_Tooltip("Show and build every level of the world at its world position")
					UI_PropLabel("")
					if UI_Button(fmt.tprintf("%s  Layers, Entities, Collision...", ICON_FA_TABLE_CELLS), "insp.ldtk.panel", {-1, 0}) do ldtkTabRequest = true
					UI_Tooltip("Open the LDtk tab of the bottom panel")
				}
				UI_EndProps()
			}
		}
	}

	if shapes := node_shapes_editor(node); shapes != nil && UI_SectionHeader("Collision Shapes") {
		editing := ShapeEdit_IsActive(state)
		if UI_Button(fmt.tprintf("%s  %s", ICON_FA_DRAW_POLYGON, "Stop Editing in Viewport" if editing else "Edit in Viewport"), "insp.shapes-edit", {-1, 0}) do ShapeEdit_SetActive(state, !editing)
		UI_Tooltip("Drag handles on the shapes in the viewport: move, rotate, resize, edit points")
		imgui.Dummy({0, 2})
		remove := -1
		for &shape, i in shapes {
			imgui.PushIDInt(c.int(i))
			if UI_BeginProps("##shape") {
				UI_PropLabel(fmt.tprintf("Shape %d", i + 1))
				names := []string{"Circle", "Capsule", "Box", "Rounded Box", "Polygon", "Segment", "Chain"}
				avail := imgui.GetContentRegionAvail().x
				imgui.SetNextItemWidth(avail - 34)
				if t, changed := UI_Combo(fmt.tprintf("insp.shape%d.type", i), int(shape.type), names); changed {
					Editor_RecordUndo(state, "Change shape type")
					from := shape.type
					shape.type = e.PhysicsShapeType(t)
					ShapeEdit_ConvertShape(&shape, from) // keep its footprint
				}
				imgui.SameLine(0, 4)
				if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("insp.shape%d.remove", i), "Remove shape", size = 26) do remove = i
				for p in e.Struct_CollectProperties(e.PhysicsShape, &shape) {
					if p.name == "type" do continue
					if !shape_prop_relevant(shape.type, p.name) do continue
					if node.typeId == e.AreaNode && !area_shape_prop(p.name) do continue
					UI_PropLabel(pretty_name(p.name))
					property_widget(state, node, p, false)
				}
				UI_EndProps()
			}
			imgui.PopID()
			imgui.Dummy({0, 4})
		}
		if remove >= 0 {
			Editor_RecordUndo(state, "Remove shape")
			e.PhysicsShape_Destroy(&shapes[remove])
			ordered_remove(shapes, remove)
		}
		if UI_Button(fmt.tprintf("%s  Add Shape", ICON_FA_PLUS), "insp.add-shape", {-1, 0}) {
			Editor_RecordUndo(state, "Add shape")
			s: e.PhysicsShape
			e.PhysicsShape_InitDefault(&s, .Box)
			s.size = {64, 64}
			s.isSensor = node.typeId == e.AreaNode
			for {
				conflict := false
				for &existing in shapes {
					if existing.offset == s.offset {
						conflict = true
						break
					}
				}
				if !conflict do break
				s.offset += {16, 16}
			}
			append(shapes, s)
		}
	}
}

// area_shape_prop: does a shape setting do anything on an Area (#173)? Its
// shapes are always sensors (no contacts, no material); their sensor events
// follow the Area's Monitoring. Its collision layers say what it detects.
@(private = "file")
area_shape_prop :: proc(name: string) -> bool {
	switch name {
	case "isSensor", "enableSensorEvents", "enableContactEvents", "enableHitEvents", "enablePreSolveEvents",
	     "density", "friction", "restitution", "rollingResistance", "tangentSpeed":
		return false
	}
	return true
}

// inspector_camera_follow: the node the camera follows (saved with the
// scene as a path relative to the camera). Pick it from the list or drop a
// node from the Scene panel on the field.
@(private = "file")
inspector_camera_follow :: proc(state: ^EditorState, cam: ^e.CameraNode) {
	if !UI_SectionHeader("Follow") do return
	mgr := state.activeScene.manager
	set :: proc(state: ^EditorState, cam: ^e.CameraNode, n: ^e.Node) {
		Editor_RecordUndo(state, "Camera follow target")
		e.CameraNode_SetFollowTarget(cam, state.activeScene.manager, n)
		if n != nil do Editor_Log(state, .Info, "%s follows %s", cam.name, n.name)
	}
	if !UI_BeginProps("##camfollow") do return
	defer UI_EndProps()
	UI_PropLabel("Follow Target")
	cur: ^e.Node
	if cam.followTarget != "" do cur = e.Node_ResolvePath(mgr, cam, cam.followTarget)
	preview := "None"
	if cur != nil do preview = cur.name
	else if cam.followTarget != "" do preview = fmt.tprintf("missing: %s", cam.followTarget)
	imgui.SetNextItemWidth(field_width())
	if imgui.BeginCombo("##camfollow", strings.clone_to_cstring(preview, context.temp_allocator)) {
		if imgui.Selectable("None", cur == nil) do set(state, cam, nil)
		Drive_Item("pick:None")
		// Every node of the scene in tree order (indented), except the camera.
		walk :: proc(state: ^EditorState, cam: ^e.CameraNode, cur, n: ^e.Node, depth: int) {
			for c in e.GetChildrenView(state.activeScene.manager, n) {
				if c == nil || c.transient do continue
				if c != cam {
					label := fmt.ctprintf("%*s%s  %s##follow_%p", depth * 2, "", Editor_NodeIcon(c), c.name, c)
					if imgui.Selectable(label, c == cur) do set(state, cam, c)
					Drive_Item(fmt.tprintf("pick:%s", c.name))
				}
				walk(state, cam, cur, c, depth + 1)
			}
		}
		walk(state, cam, cur, state.activeScene.rootNode, 0)
		imgui.EndCombo()
	}
	Drive_Item("insp.camera.follow")
	if imgui.BeginDragDropTarget() {
		if payload := imgui.AcceptDragDropPayload("RAYZR_NODE"); payload != nil {
			n := (^^e.Node)(payload.Data)^
			if e.Node_IsAlive(n) && n != cam do set(state, cam, n)
		}
		imgui.EndDragDropTarget()
	}
	UI_Tooltip("The camera follows this node (drop a node from the Scene panel here)")
	if field_reset("insp.camera.follow", cam.followTarget != "") do set(state, cam, nil)
	if cur == nil && cam.followTarget != "" {
		UI_PropLabel("")
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextWrapped(fmt.ctprintf("%s  No node at %s (renamed or moved?). The game also looks for it when it spawns.", ICON_FA_TRIANGLE_EXCLAMATION, cam.followTarget))
		imgui.PopStyleColor()
	} else if cur != nil {
		UI_PropLabel("")
		UI_DimText(fmt.tprintf("%s · offset, smoothing and limits below", cam.followTarget))
	}
}

// Only show the dimensions that apply to the shape type.
@(private = "file")
shape_prop_relevant :: proc(t: e.PhysicsShapeType, name: string) -> bool {
	switch name {
	case "radius": return t == .Circle || t == .Capsule
	case "size": return t == .Box || t == .RoundedBox || t == .Capsule
	case "cornerRadius": return t == .RoundedBox
	case "point1", "point2": return t == .Segment
	case "vertexCount": return t == .Polygon
	case "isLoop": return t == .Chain
	}
	return true
}

node_shapes_editor :: proc(node: ^e.Node) -> ^[dynamic]e.PhysicsShape {
	switch node.typeId {
	case e.StaticBodyNode: return &(cast(^e.StaticBodyNode)node).shapes
	case e.DynamicBodyNode: return &(cast(^e.DynamicBodyNode)node).shapes
	case e.KinematicBodyNode: return &(cast(^e.KinematicBodyNode)node).shapes
	case e.CharacterMoverNode: return &(cast(^e.CharacterMoverNode)node).shapes
	case e.AreaNode: return &(cast(^e.AreaNode)node).shapes
	}
	return nil
}

asset_rel_editor :: proc(state: ^EditorState, path: string) -> string {
	dir := strings.trim_suffix(state.projectPath, "/")
	p := strings.trim_prefix(path, "./")
	if strings.has_prefix(p, dir) && len(p) > len(dir) && p[len(dir)] == '/' do return p[len(dir) + 1:]
	return p
}

// Editor_ListProjectDirs lists sub-directories (recursive) of a project dir.
Editor_ListProjectDirs :: proc(state: ^EditorState, subdir: string) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	walk :: proc(state: ^EditorState, rel: string, out: ^[dynamic]string, depth: int) {
		if depth > 4 do return
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		h, err := os.open(full)
		if err != nil do return
		infos, _ := os.read_dir(h, -1, context.temp_allocator)
		os.close(h)
		for fi in infos {
			if fi.type != .Directory do continue
			child, _ := filepath.join({rel, fi.name}, context.temp_allocator)
			append(out, child)
			walk(state, child, out, depth + 1)
		}
	}
	walk(state, subdir, &out, 0)
	slice.sort(out[:])
	return out[:]
}

// --- script ---------------------------------------------------------------------------

@(private = "file")
inspector_script :: proc(state: ^EditorState, node: ^e.Node) {
	if !UI_SectionHeader("Script") do return
	sm := &state.game.scriptManager
	scripts := Editor_ListProjectFiles(state, "scripts", {".lua"})

	if node.scriptInstance == nil {
		imgui.SetNextItemWidth(-1)
		if path, ok := asset_picker("insp.script-attach", "", scripts, allowNone = false); ok && path != "" {
			Editor_RecordUndo(state, "Attach script")
			node.gameContext = &state.game.gameContext
			// Project-relative: resolves from the project dir or a .rayzr package.
			if e.Script_AttachToNode(node, path, nil, sm) != nil {
				Editor_Log(state, .Info, "Attached %s to %s", path, node.name)
			} else {
				Editor_Log(state, .Error, "Could not attach %s (see errors above)", path)
			}
		}
		if UI_Button(fmt.tprintf("%s  New Script...", ICON_FA_PLUS), "insp.script-new", {-1, 0}) do NewScriptDialog_Open(state, node)
		UI_DimText("Attach a Lua script to give this node behaviour.")
		return
	}

	inst := cast(^e.ScriptInstance)node.scriptInstance
	if UI_BeginProps("##script") {
		UI_PropLabel("Module")
		avail := imgui.GetContentRegionAvail().x
		imgui.SetNextItemWidth(avail - 94)
		current := asset_rel_editor(state, inst.modulePath)
		if path, ok := asset_picker("insp.script-change", current, scripts, allowNone = false); ok && path != current {
			Editor_RecordUndo(state, "Change script")
			e.Script_AttachToNode(node, path, nil, sm)
		}
		imgui.SameLine(0, 4)
		if UI_IconButton(ICON_FA_CODE, "insp.script-edit", "Edit script", size = 26) do Editor_OpenScript(state, current)
		imgui.SameLine(0, 4)
		if UI_IconButton(ICON_FA_CODE_BRANCH, "insp.script-extend", "Extend script: a new script built on this one (its methods and properties), attached instead, the node's values kept", size = 26) {
			NewScriptDialog_Open(state, node, extends = current)
		}
		imgui.SameLine(0, 4)
		if UI_IconButton(ICON_FA_TRASH, "insp.script-detach", "Detach script", size = 26) {
			Editor_RecordUndo(state, "Detach script")
			e.ScriptInstance_Destroy(inst, sm)
			node.scriptInstance = nil
			UI_EndProps()
			return
		}

		// Its properties: the Properties tab (#208).
		UI_PropLabel("Properties")
		n := len(inst.properties)
		if UI_Button(fmt.tprintf("%s  %d in the Properties tab", ICON_FA_SLIDERS, n) if n > 0 else fmt.tprintf("%s  Add in the Properties tab", ICON_FA_PLUS), "insp.script-props", {-1, 0}) do inspectorTabRequest = .Properties
		UI_EndProps()
	}
}

// Editor_NodeIcon picks an icon for a node type.
Editor_NodeIcon :: proc(node: ^e.Node) -> string {
	// A custom node type's own icon (#156).
	if node != nil && node.customType != "" && !node.customMissing {
		if t := e.Node_CustomType(node); t != nil do return CustomNode_Icon(t)
	}
	// Each node type's icon from the Add Node catalogue (one per type).
	@(static) byType: map[typeid]string
	if byType == nil {
		for entry in NODE_CATALOG {
			if info, ok := e.Node_TypeInfoByName(entry.typeName); ok do byType[info.type] = entry.icon
		}
	}
	if node.typeId != e.Node || node.scriptInstance == nil {
		if icon, ok := byType[node.typeId]; ok do return icon
	}
	switch node.typeId {
	case e.CameraNode: return ICON_FA_VIDEO
	case e.LightNode: return ICON_FA_LIGHTBULB
	case e.TextureNode, e.AtlasSpriteNode, e.FrameAnimationNode, e.AnimationPlayerNode: return ICON_FA_IMAGE
	case e.SoundNode, e.MusicNode: return ICON_FA_MUSIC
	case e.StaticBodyNode, e.DynamicBodyNode, e.KinematicBodyNode, e.CharacterMoverNode, e.AreaNode, e.RaycastNode: return ICON_FA_CUBES
	case e.ParticleEmitterNode: return ICON_FA_WAND_MAGIC_SPARKLES
	case e.TimerNode: return ICON_FA_CLOCK
	case e.StateMachineNode: return ICON_FA_DIAGRAM_PROJECT
	case e.BehaviorTreeNode: return ICON_FA_SITEMAP
	case e.GoapNode: return ICON_FA_BULLSEYE
	case e.JointNode: return ICON_FA_LINK
	case e.TextNode: return ICON_FA_FONT
	case e.DialogueNode: return ICON_FA_COMMENT
	case e.NineSliceNode: return ICON_FA_VECTOR_SQUARE
	case e.ParallaxNode: return ICON_FA_MOUNTAIN
	case e.LineNode: return ICON_FA_DRAW_POLYGON
	case e.VectorShapeNode: return ICON_FA_PAINTBRUSH
	case e.TrailNode: return ICON_FA_WIND
	case e.VisibilityNotifierNode: return ICON_FA_EYE
	case e.SpawnerNode: return ICON_FA_CLONE
	case e.LevelGeneratorNode: return ICON_FA_SHUFFLE
	case e.PathNode: return ICON_FA_BEZIER_CURVE
	case e.PathFollowNode: return ICON_FA_ROUTE
	case e.NavigationRegionNode: return ICON_FA_MAP
	case e.NavigationAgentNode: return ICON_FA_PERSON_RUNNING
	case e.AdvancedCameraNode: return ICON_FA_CAMERA
	case e.SkeletonNode: return ICON_FA_BONE
	case e.AsepriteNode: return ICON_FA_PALETTE
	case e.BoneAttachmentNode: return ICON_FA_LINK
	case e.PostEffectNode: return ICON_FA_FILTER
	case e.LdtkLevelNode: return ICON_FA_TABLE_CELLS
	case e.ScriptNode: return ICON_FA_CODE
	}
	if node.isUI do return ICON_FA_WINDOW_MAXIMIZE
	if node.scriptInstance != nil do return ICON_FA_CODE
	return ICON_FA_CIRCLE_DOT
}

animPreviewNode: ^e.AnimationPlayerNode

// inspector_animation_player: the player's own settings - its animations
// are edited in the bottom panel's Animation tab.
@(private = "file")
inspector_animation_player :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode) {
	if !UI_SectionHeader("Animation Player") do return
	if UI_BeginProps("##apn") {
		UI_PropLabel("Current")
		names := make([dynamic]string, context.temp_allocator)
		for a in apn.animations do append(&names, a.name)
		if idx, changed := UI_Combo("insp.anim.current", apn.animationIndex, names[:]); changed {
			Editor_RecordUndo(state, "Set animation")
			e.AnimationPlayerNode_SetAnimationIndex(apn, idx)
			if a := e.AnimationPlayerNode_GetAnimation(apn); a != nil do apn.currentFrame = a.startFrame
		}
		UI_Tooltip("The animation shown now (scripts: animation_play(\"name\"))")
		if p, ok := e.Node_FindProperty(apn, "defaultAnimation"); ok {
			prop_row_label(state, apn, "Default", p)
			defNames := make([dynamic]string, context.temp_allocator)
			append(&defNames, "(the saved current one)")
			defIdx := 0
			for a, i in apn.animations {
				append(&defNames, a.name)
				if a.name == apn.defaultAnimation do defIdx = i + 1
			}
			if idx, changed := UI_Combo("insp.anim.default", defIdx, defNames[:]); changed {
				Editor_RecordUndo(state, "Default animation")
				apn.defaultAnimation = "" if idx == 0 else strings.clone(apn.animations[idx - 1].name, apn.allocator)
			}
		}
		if p, ok := e.Node_FindProperty(apn, "fps"); ok {
			prop_row_label(state, apn, "FPS", p)
			fps := apn.fps
			if imgui.DragFloat("##apnfps", &fps, 0.2, 1, 120, "%.0f") do e.AnimationPlayerNode_SetFPS(apn, fps)
			undo_on_activate(state, "Edit FPS")
			Drive_Item("insp.anim.fps")
		}
		UI_PropLabel("Preview")
		previewing := animPreviewNode == apn && apn.ticker.running
		if UI_Button(previewing ? fmt.tprintf("%s  Stop", ICON_FA_STOP) : fmt.tprintf("%s  Play", ICON_FA_PLAY), "insp.anim.preview", {-1, 0}) {
			if previewing {
				e.AnimationPlayerNode_Stop(apn)
				animPreviewNode = nil
			} else {
				e.AnimationPlayerNode_Start(apn)
				animPreviewNode = apn
			}
		}
		UI_PropLabel("Animations")
		UI_DimText(fmt.tprintf("%d  ·  edit them in the Animation tab", len(apn.animations)))
		Drive_Item("insp.anim.count")
		UI_EndProps()
	}
	// The editor doesn't update nodes outside Simulate: advance the preview here.
	if animPreviewNode == apn do apn.ticker->process()
	if UI_Button(fmt.tprintf("%s  Slice a Sprite Sheet...", ICON_FA_TABLE_CELLS), "insp.anim.slicer", {-1, 0}) do Slicer_Open(state, "")
	UI_Tooltip("Pick cells of a sheet and make animations of them (added to this player)")
}

// scene_settings_pointer: the scene's settings live in the Scene panel's
// Settings tab (#195) - a button there.
@(private = "file")
scene_settings_pointer :: proc() {
	imgui.Dummy({0, 8})
	if UI_Button(fmt.tprintf("%s  Scene Settings...", ICON_FA_SLIDERS), "insp.scene-settings", {-1, 0}) do scenePanelTabRequest = .Settings
	UI_Tooltip("Background, ambient light and more: the Scene panel's Settings tab")
}

// inspector_scene_settings: scene-level properties (the Scene panel's
// Settings tab).
inspector_scene_settings :: proc(state: ^EditorState, scene: ^e.Scene) {
	if !UI_SectionHeader("Scene") do return
	if !UI_BeginProps("##scene_props") do return
	defer UI_EndProps()
	UI_PropLabel("File")
	UI_DimText(scene.filePath if scene.filePath != "" else "(not saved)")
	UI_PropLabel("Background")
	useBg := scene.backgroundColor.a > 0
	if imgui.Checkbox("##scene_bg_on", &useBg) {
		Editor_RecordUndo(state, "Scene background")
		scene.backgroundColor = {23, 26, 33, 255} if useBg else {}
	}
	Drive_Item("insp.scene-background-on")
	UI_Tooltip("Use a background colour for this scene (otherwise the game's default)")
	if useBg {
		imgui.SameLine()
		col := [4]f32{f32(scene.backgroundColor.r) / 255, f32(scene.backgroundColor.g) / 255, f32(scene.backgroundColor.b) / 255, 1}
		imgui.SetNextItemWidth(-1)
		if imgui.ColorEdit3("##scene_bg", (^[3]f32)(&col), {}) {
			scene.backgroundColor = {u8(col[0] * 255), u8(col[1] * 255), u8(col[2] * 255), 255}
		}
		undo_on_activate(state, "Scene background")
		Drive_Item("insp.scene-background")
	}
	UI_PropLabel("Ambient")
	amb := scene.ambient if scene.ambient != {} else rl.Color{255, 255, 255, 255}
	acol := [3]f32{f32(amb.r) / 255, f32(amb.g) / 255, f32(amb.b) / 255}
	imgui.SetNextItemWidth(field_width())
	if imgui.ColorEdit3("##scene_ambient", &acol, {}) {
		scene.ambient = {u8(acol[0] * 255 + 0.5), u8(acol[1] * 255 + 0.5), u8(acol[2] * 255 + 0.5), 255}
	}
	undo_on_activate(state, "Scene ambient")
	Drive_Item("insp.scene-ambient")
	UI_Tooltip("Light where no light reaches (white = unlit scene). Add Light nodes to light it.")
	if field_reset("insp.scene-ambient", scene.ambient != {} && scene.ambient != {255, 255, 255, 255}) {
		Editor_RecordUndo(state, "Scene ambient")
		scene.ambient = {}
	}
	UI_PropLabel("")
	presets := []string{"Presets...", "Day (unlit)", "Dusk", "Night", "Dark"}
	values := []rl.Color{{}, {}, {150, 110, 120, 255}, {40, 46, 70, 255}, {8, 8, 12, 255}}
	imgui.SetNextItemWidth(field_width())
	if v, changed := UI_Combo("insp.scene-ambient-preset", 0, presets); changed && v > 0 {
		Editor_RecordUndo(state, "Scene ambient")
		scene.ambient = values[v]
	}
	UI_PropLabel("Draw Bounds")
	bounds := scene.drawBounds
	if imgui.Checkbox("##scene_bounds", &bounds) {
		Editor_RecordUndo(state, "Draw bounds")
		scene.drawBounds = bounds
	}
	Drive_Item("insp.scene-draw-bounds")
	UI_Tooltip("Draw node bounds when the game runs (debug)")
}



script_value_equal :: proc(a, b: e.ScriptValue) -> bool {
	if a.type != b.type do return false
	switch a.type {
	case .Float:   return a.valFloat == b.valFloat
	case .Int:     return a.valInt == b.valInt
	case .Boolean: return a.valBool == b.valBool
	case .String:  return a.valString == b.valString
	case .Vector2: return a.valVec2 == b.valVec2
	case .Color:   return a.valColor == b.valColor
	}
	return true
}

// inspector_joint: the two bodies a JointNode connects.
@(private = "file")
inspector_joint :: proc(state: ^EditorState, j: ^e.JointNode) {
	if !UI_SectionHeader("Joint Bodies") do return
	if !UI_BeginProps("##jointbodies") do return
	defer UI_EndProps()
	mgr := state.activeScene.manager
	a, b := e.JointNode_Bodies(j, mgr)
	pick :: proc(state: ^EditorState, j: ^e.JointNode, which: int, cur: ^e.Node, id: string) {
		mgr := state.activeScene.manager
		path := j.bodyA if which == 0 else j.bodyB
		preview := cur.name if cur != nil else ("Parent" if which == 0 && path == "" else (fmt.tprintf("missing: %s", path) if path != "" else "None"))
		imgui.SetNextItemWidth(field_width())
		if imgui.BeginCombo(fmt.ctprintf("##%s", id), strings.clone_to_cstring(preview, context.temp_allocator)) {
			for n in mgr.nodes {
				if n == nil || n.transient || !e.b2_is_body_node(n) do continue
				if imgui.Selectable(fmt.ctprintf("%s  %s##%p", Editor_NodeIcon(n), n.name, n), n == cur) {
					Editor_RecordUndo(state, "Joint body")
					rel := e.Node_RelativePath(mgr, j, n)
					if which == 0 do e.JointNode_SetBodies(j, rel, j.bodyB)
					else do e.JointNode_SetBodies(j, j.bodyA, rel)
				}
				Drive_Item(fmt.tprintf("pick:%s", n.name))
			}
			imgui.EndCombo()
		}
		Drive_Item(id)
	}
	UI_PropLabel("Body A")
	pick(state, j, 0, a, "insp.joint.a")
	UI_Tooltip("Static, dynamic or character body (default: the joint's parent)")
	UI_PropLabel("Body B")
	pick(state, j, 1, b, "insp.joint.b")
	if a == nil || b == nil {
		UI_PropLabel("")
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextWrapped(fmt.ctprintf("%s  Pick two bodies; the joint is made when both exist (while simulating or playing).", ICON_FA_TRIANGLE_EXCLAMATION))
		imgui.PopStyleColor()
	}
}

FONT_EXTS := []string{".ttf", ".otf", ".fnt"}

// inspector_font: the font of a TextNode / DialogueNode (project fonts).
@(private = "file")
inspector_font :: proc(state: ^EditorState, node: ^e.Node) {
	if !UI_SectionHeader("Font") do return
	if !UI_BeginProps("##font") do return
	defer UI_EndProps()
	font := &(cast(^e.TextNode)node).font if node.typeId == e.TextNode else &(cast(^e.DialogueNode)node).font
	UI_PropLabel("Font")
	imgui.SetNextItemWidth(field_width())
	if path, ok := asset_picker("insp.font", font^, Editor_ListProjectFiles(state, "", FONT_EXTS)); ok {
		Editor_RecordUndo(state, "Font")
		font^ = strings.clone(path, node.allocator)
	}
	UI_Tooltip("None: the engine font. .ttf / .otf (any size; SDF for scaling), .fnt (BMFont)")
}

// inspector_texture_path: the texture of a NineSlice / Parallax node.
@(private = "file")
inspector_texture_path :: proc(state: ^EditorState, node: ^e.Node) {
	if !UI_SectionHeader("Texture") do return
	if !UI_BeginProps("##texpath") do return
	defer UI_EndProps()
	path := &(cast(^e.NineSliceNode)node).texturePath if node.typeId == e.NineSliceNode else &(cast(^e.ParallaxNode)node).texturePath
	UI_PropLabel("Texture")
	imgui.SetNextItemWidth(field_width())
	if picked, ok := asset_picker("insp.texture-path", path^, Editor_ListProjectFiles(state, "", TEXTURE_EXTS)); ok {
		Editor_RecordUndo(state, "Texture")
		path^ = strings.clone(picked, node.allocator)
	}
	if node.typeId == e.NineSliceNode {
		UI_Tooltip("The borders (Margins) keep their size; the middle stretches")
	} else {
		UI_Tooltip("Factor 1 moves with the world, 0 stays on screen; repeat to tile it")
	}
}

// inspector_nav_region: bake the cells (the editor doesn't run ready) and
// what they hold.
@(private = "file")
inspector_nav_region :: proc(state: ^EditorState, r: ^e.NavigationRegionNode) {
	if !UI_SectionHeader("Navigation") do return
	if !r.baked do e.NavRegion_Bake(r, &state.game.gameContext)
	blocked := 0
	for b in r.blocked do if b != 0 do blocked += 1
	UI_DimText(fmt.tprintf("%d x %d cells, %d blocked (red in the viewport). The game bakes it when the scene starts.", r.cells.x, r.cells.y, blocked))
	if UI_Button(fmt.tprintf("%s  Bake", ICON_FA_ROTATE), "insp.nav.bake") {
		e.NavRegion_Bake(r, &state.game.gameContext)
		Editor_Log(state, .Info, "Baked %s: %d x %d cells", r.name, r.cells.x, r.cells.y)
	}
	UI_Tooltip("Rebuild the cells from the scene now (after moving walls or painting tiles)")
}

// inspector_path: a PathNode's points (local) and handles; Smooth / Sharp.
@(private = "file")
inspector_path :: proc(state: ^EditorState, p: ^e.PathNode) {
	if !UI_SectionHeader("Points") do return
	UI_DimText(fmt.tprintf("Length %.0f px. In the viewport: drag points and handles, double-click the curve to add, Alt+click to remove.", e.PathNode_Length(p)))
	sel := PathEdit_Selected(p)
	remove := -1
	w := imgui.GetContentRegionAvail().x
	for &pt, i in p.points {
		imgui.PushIDInt(i32(i))
		if i == sel do imgui.TextColored(UI_ACCENT, "%d", i32(i + 1))
		else do UI_DimText(fmt.tprintf("%d", i + 1))
		imgui.SameLine(28)
		imgui.SetNextItemWidth(w * 0.42)
		imgui.DragFloat2("##pos", &pt.pos, 1, 0, 0, "%.0f")
		undo_on_activate(state, "Path point")
		Drive_Item(fmt.tprintf("insp.path.point:%d", i))
		imgui.SameLine()
		smooth := pt.in_ != {} || pt.out != {}
		if UI_IconButton(ICON_FA_BEZIER_CURVE, fmt.tprintf("insp.path.smooth:%d", i), "Sharp corner" if smooth else "Smooth (add handles)", smooth, 24) {
			Editor_RecordUndo(state, "Path point handles")
			if smooth {
				pt.in_, pt.out = {}, {}
			} else {
				// Handles along the line through its neighbours.
				n := len(p.points)
				prev := p.points[(i + n - 1) % n].pos if i > 0 || p.closed else pt.pos
				next := p.points[(i + 1) % n].pos if i < n - 1 || p.closed else pt.pos
				d := (next - prev) * 0.25
				if d == {} do d = {30, 0}
				pt.in_, pt.out = -d, d
			}
		}
		if len(p.points) > 2 {
			imgui.SameLine()
			if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("insp.path.remove:%d", i), "Remove point", size = 24) do remove = i
		}
		if smooth {
			imgui.SetCursorPosX(imgui.GetCursorPosX() + 28)
			imgui.SetNextItemWidth(w * 0.36)
			imgui.DragFloat2("##in", &pt.in_, 1, 0, 0, "in %.0f")
			undo_on_activate(state, "Path handle")
			imgui.SameLine()
			imgui.SetNextItemWidth(w * 0.36)
			imgui.DragFloat2("##out", &pt.out, 1, 0, 0, "out %.0f")
			undo_on_activate(state, "Path handle")
		}
		imgui.PopID()
	}
	if remove >= 0 {
		Editor_RecordUndo(state, "Remove path point")
		ordered_remove(&p.points, remove)
	}
	if UI_Button(fmt.tprintf("%s  Add Point", ICON_FA_PLUS), "insp.path.add") {
		Editor_RecordUndo(state, "Add path point")
		last := p.points[len(p.points) - 1].pos if len(p.points) > 0 else [2]f32{}
		append(&p.points, e.Path_Point{pos = last + {80, 0}})
	}
	UI_Tooltip("A point 80 px after the last (or Ctrl+click in the viewport)")
}

// inspector_spawner: a spawner's list (components, weight, count, offset);
// components drop in from Assets. In Simulate: spawn now, what is alive.
@(private = "file")
inspector_spawner :: proc(state: ^EditorState, s: ^e.SpawnerNode) {
	if !UI_SectionHeader("Spawn List") do return
	files := make([dynamic]string, context.temp_allocator)
	for f in Editor_ListProjectFiles(state, "", {".json"}) do if strings.has_suffix(f, ".component.json") do append(&files, f)
	if len(s.entries) == 0 do UI_DimTextWrapped("Add the components it spawns (or drop them here from Assets).")
	remove, up := -1, -1
	weights := s.mode == .Random
	for &en, i in s.entries {
		imgui.PushIDInt(i32(i))
		UI_DimText(fmt.tprintf("%d", i + 1))
		imgui.SameLine(24)
		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x - (86 if len(s.entries) > 1 else 58))
		if path, ok := asset_picker(fmt.tprintf("insp.spawner.component:%d", i), en.component, files[:], false); ok {
			Editor_RecordUndo(state, "Spawner component")
			delete(en.component, s.allocator)
			en.component = strings.clone(path, s.allocator)
		}
		Drive_Item(fmt.tprintf("insp.spawner.component:%d", i))
		if len(s.entries) > 1 {
			imgui.SameLine()
			imgui.BeginDisabled(i == 0)
			if UI_IconButton(ICON_FA_ARROW_UP, fmt.tprintf("insp.spawner.up:%d", i), "Move up (the order Sequential spawns in)", size = 24) do up = i
			imgui.EndDisabled()
		}
		imgui.SameLine()
		if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("insp.spawner.remove:%d", i), "Remove", size = 24) do remove = i
		imgui.SetCursorPosX(imgui.GetCursorPosX() + 24)
		w := (imgui.GetContentRegionAvail().x - 8) / 3
		imgui.SetNextItemWidth(w)
		imgui.BeginDisabled(!weights)
		imgui.DragFloat("##weight", &en.weight, 0.05, 0, 1000, "weight %.2f")
		imgui.EndDisabled()
		undo_on_activate(state, "Spawner weight")
		UI_Tooltip("Random mode: how likely this one is, relative to the others")
		imgui.SameLine(0, 4)
		imgui.SetNextItemWidth(w)
		cnt := i32(en.count)
		if imgui.DragInt("##count", &cnt, 0.1, 1, 100, "x%d") do en.count = max(int(cnt), 1)
		undo_on_activate(state, "Spawner count")
		UI_Tooltip("How many of it each time it is picked")
		imgui.SameLine(0, 4)
		imgui.SetNextItemWidth(-1)
		imgui.DragFloat2("##offset", &en.offset, 1, -4096, 4096, "%.0f")
		undo_on_activate(state, "Spawner offset")
		UI_Tooltip("Its own offset from the spawn point (px, local to the spawner)")
		imgui.PopID()
	}
	if up > 0 {
		Editor_RecordUndo(state, "Reorder spawner list")
		s.entries[up], s.entries[up - 1] = s.entries[up - 1], s.entries[up]
	}
	if remove >= 0 {
		Editor_RecordUndo(state, "Remove from spawner")
		e.SpawnerNode_RemoveEntry(s, remove)
	}
	if path, ok := asset_picker("insp.spawner.add", "", files[:], false); ok {
		Editor_RecordUndo(state, "Add to spawner")
		e.SpawnerNode_AddEntry(s, path)
	}
	Drive_Item("insp.spawner.add")
	UI_Tooltip("Add a component to the list")
	// Components dragged in from Assets.
	if imgui.BeginDragDropTarget() {
		if payload := imgui.AcceptDragDropPayload(ASSET_PAYLOAD); payload != nil {
			p := (^Asset_Payload)(payload.Data)
			rel := strings.clone(string(p.path[:p.len]), context.temp_allocator)
			if strings.has_suffix(rel, ".component.json") {
				Editor_RecordUndo(state, "Add to spawner")
				e.SpawnerNode_AddEntry(s, rel)
			}
		}
		imgui.EndDragDropTarget()
	}
	if state.isSimulating {
		imgui.Dummy({0, 4})
		if UI_Button(fmt.tprintf("%s  Spawn Now", ICON_FA_CLONE), "insp.spawner.spawn") do e.SpawnerNode_Spawn(s, &state.game.gameContext)
		imgui.SameLine()
		UI_DimText(fmt.tprintf("%d alive · %d spawned", e.SpawnerNode_AliveCount(s), s.spawnedTotal))
	} else {
		UI_DimTextWrapped("Spawning happens in Simulate and in the game (spawn(), a signal to `spawn`, or Auto Spawn).")
	}
}

// inspector_line: a LineNode's points (local to the node).
@(private = "file")
inspector_line :: proc(state: ^EditorState, l: ^e.LineNode) {
	if !UI_SectionHeader("Points") do return
	remove := -1
	for &p, i in l.points {
		imgui.PushIDInt(i32(i))
		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x - 34)
		imgui.DragFloat2("##pt", &p, 1, 0, 0, "%.0f")
		undo_on_activate(state, "Line point")
		Drive_Item(fmt.tprintf("insp.line.point:%d", i))
		if len(l.points) > 2 {
			imgui.SameLine()
			if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("insp.line.remove:%d", i), "Remove point", size = 24) do remove = i
		}
		imgui.PopID()
	}
	if remove >= 0 {
		Editor_RecordUndo(state, "Remove point")
		ordered_remove(&l.points, remove)
	}
	if UI_Button(fmt.tprintf("%s  Add Point", ICON_FA_PLUS), "insp.line.add") {
		Editor_RecordUndo(state, "Add point")
		last := l.points[len(l.points) - 1] if len(l.points) > 0 else [2]f32{}
		append(&l.points, last + {40, 0})
	}
}
