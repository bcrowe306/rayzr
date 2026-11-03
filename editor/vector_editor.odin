package editor

import "core:fmt"
import os "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Vector art in the editor (Phase 14 M2): the Inspector's Vector section
// (the SVG a Vector Shape draws, what's in it, the importer's warnings),
// SVGs in Assets (thumbnails, drag into the viewport / onto a Vector Shape,
// double-click to edit in the system's vector app - saving reloads it).
// M3: the symbol (a named group) and frame (part swapping) pickers, and
// Explode into Parts (a Vector Shape per child group, to animate apart).
// ============================================================================

@(private = "file")
vector_files :: proc(state: ^EditorState) -> []string {
	return Editor_ListProjectFiles(state, "", {".svg"})
}

// Vector_EditExternal opens an SVG in the system's app for it (Inkscape,
// Illustrator, Affinity...): saving there reloads it in the editor.
Vector_EditExternal :: proc(state: ^EditorState, full: string) {
	abs := full
	if a, err := os.get_absolute_path(full, context.temp_allocator); err == nil do abs = a
	if GlobalDrive.enabled {
		Editor_Log(state, .Info, "Would open in the vector app: %s", abs) // (drives: no program)
		return
	}
	Editor_OpenExternally(state, abs)
	Editor_Log(state, .Info, "Editing %s (saving it reloads the art here)", filepath.base(abs))
}

// inspector_vector: the Inspector's Vector section.
inspector_vector :: proc(state: ^EditorState, v: ^e.VectorShapeNode) {
	if !UI_SectionHeader("Vector") do return
	if !UI_BeginProps("##vec") do return
	UI_PropLabel("File")
	imgui.SetNextItemWidth(field_width() - 30)
	if path, ok := asset_picker("insp.vec.file", v.file, vector_files(state)); ok {
		Editor_RecordUndo(state, "Vector file")
		v.file = strings.clone(path, v.allocator)
	}
	UI_Tooltip("An SVG in the project (empty: the built-in preset below). Saving the file reloads it.")
	imgui.SameLine(0, 4)
	if UI_IconButton(ICON_FA_PEN_TO_SQUARE, "insp.vec.edit", "Edit in your vector app (saving there updates it here)", false, 26) && v.file != "" {
		Vector_EditExternal(state, e.Project_ResolveAssetPath(&state.game.gameContext, v.file))
	}
	vector_skin_picker(state, v)
	UI_PropLabel("")
	drawing := VectorDraw_Node() == v
	if UI_Button(fmt.tprintf("%s  %s", ICON_FA_PEN, "Done Drawing" if drawing else "Edit Art"), "insp.vec.draw") {
		if drawing do VectorDraw_Exit(state)
		else do VectorDraw_Enter(state, v)
	}
	UI_Tooltip("Draw in the viewport: select, node and pen tools; the edits are saved into the SVG (double-click the shape does the same)")
	UI_EndProps()
	if v.file == "" {
		UI_DimText("Draws its preset. Pick an SVG, drag one from Assets into the viewport, or Edit Art to draw one.")
		return
	}
	r := e.VectorShapeNode_Asset(v)
	if r == nil {
		UI_DimText("Could not load the file (see the console).")
		return
	}
	doc := &r.doc
	UI_DimText(fmt.tprintf("%.0f x %.0f px, %d shapes, %d groups", doc.size.x, doc.size.y, len(doc.shapes), len(doc.groups)))
	Drive_Item("insp.vec.info")
	for w in doc.warnings {
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextWrapped(fmt.ctprintf("%s  %s", ICON_FA_TRIANGLE_EXCLAMATION, w))
		imgui.PopStyleColor()
	}
	if len(doc.groups) == 0 do return
	g := e.Vector_ResourceGroup(r, v.group)
	if !UI_BeginProps("##vecsym") do return
	// The symbol: one named group (layers in Inkscape / Illustrator / Affinity).
	UI_PropLabel("Symbol")
	imgui.SetNextItemWidth(field_width())
	shown := v.group if v.group != "" else "Whole file"
	if g == -2 do shown = fmt.tprintf("%s (missing)", v.group)
	if imgui.BeginCombo("##vecsym", strings.clone_to_cstring(shown, context.temp_allocator), {.HeightLarge}) {
		if imgui.Selectable("Whole file", v.group == "") do vector_set_group(state, v, "")
		Drive_Item("pick:vec-group:")
		for grp, i in doc.groups {
			depth := 0
			for p := grp.parent; p >= 0; p = doc.groups[p].parent do depth += 1
			path := e.Vector_GroupPath(r, i)
			label := fmt.ctprintf("%*s%s##g%d", depth * 2, "", grp.name, i)
			if imgui.Selectable(label, i == g) do vector_set_group(state, v, path)
			Drive_Item(fmt.tprintf("pick:vec-group:%s", path))
		}
		imgui.EndCombo()
	}
	Drive_Item("insp.vec.group")
	UI_Tooltip("Draw one named group of the file (a symbol): a character's head, a prop on a shared sheet")
	// The frame: one child group at a time (part swapping: mouths, hands, eyes).
	frames := e.VectorShapeNode_Frames(v)
	if len(frames) > 0 {
		UI_PropLabel("Frame")
		imgui.SetNextItemWidth(field_width())
		current := "All"
		if v.frame >= 0 do current = frames[v.frame] if v.frame < len(frames) else fmt.tprintf("%d (missing)", v.frame)
		if imgui.BeginCombo("##vecframe", strings.clone_to_cstring(current, context.temp_allocator), {.HeightLarge}) {
			if imgui.Selectable("All", v.frame < 0) && v.frame != -1 {
				Editor_RecordUndo(state, "Vector frame")
				v.frame = -1
			}
			Drive_Item("pick:vec-frame:All")
			for f, i in frames {
				if imgui.Selectable(fmt.ctprintf("%d  %s##f%d", i, f, i), i == v.frame) && i != v.frame {
					Editor_RecordUndo(state, "Vector frame")
					v.frame = i
				}
				Drive_Item(fmt.tprintf("pick:vec-frame:%s", f))
			}
			imgui.EndCombo()
		}
		Drive_Item("insp.vec.frame")
		UI_Tooltip("Show one child group at a time (part swapping); the box stays the group's, so frames never jump. Scripts: node:swap(\"name\")")
	}
	// Shape tween: morph toward another group (keys on Morph animate it).
	UI_PropLabel("Morph to")
	imgui.SetNextItemWidth(field_width())
	morphShown := v.morphTo if v.morphTo != "" else "None"
	if v.morphTo != "" && e.Vector_ResourceGroup(r, v.morphTo) == -2 do morphShown = fmt.tprintf("%s (missing)", v.morphTo)
	if imgui.BeginCombo("##vecmorph", strings.clone_to_cstring(morphShown, context.temp_allocator), {.HeightLarge}) {
		if imgui.Selectable("None", v.morphTo == "") && v.morphTo != "" {
			Editor_RecordUndo(state, "Vector morph")
			v.morphTo = ""
		}
		Drive_Item("pick:vec-morph:")
		for grp, i in doc.groups {
			path := e.Vector_GroupPath(r, i)
			if imgui.Selectable(fmt.ctprintf("%s##m%d", path, i), path == v.morphTo) && path != v.morphTo {
				Editor_RecordUndo(state, "Vector morph")
				v.morphTo = strings.clone(path, v.allocator)
				if v.morph == 0 do v.morph = 0.5 // (show it at once)
			}
			Drive_Item(fmt.tprintf("pick:vec-morph:%s", path))
		}
		imgui.EndCombo()
	}
	Drive_Item("insp.vec.morph")
	UI_Tooltip("Shape tween: the group this one morphs into as Morph goes 0 -> 1 (paths, colours, outlines, gradients)")
	UI_EndProps()
	if g != -2 && len(e.Vector_GroupChildren(r, g)) > 0 {
		if UI_Button(fmt.tprintf("%s  Explode into Parts", ICON_FA_OBJECT_UNGROUP), "insp.vec.explode", {field_width() + 80, 0}) {
			Vector_ExplodeParts(state, v)
		}
		UI_Tooltip("Replace this node with a Node holding a Vector Shape per child group (pivots at their centres), to move and animate the parts apart")
	}
}

// vector_skin_picker: under a Skeleton, the bones the art bends with
// (vector skinning, V.10) - none, all, or any set, kept in the skeleton's
// bone order.
@(private = "file")
vector_skin_picker :: proc(state: ^EditorState, v: ^e.VectorShapeNode) {
	sn := e.VectorShapeNode_Skeleton(v)
	if sn == nil do return
	UI_PropLabel("Bend with")
	imgui.SetNextItemWidth(field_width())
	shown := v.skinBones
	switch strings.trim_space(v.skinBones) {
	case "": shown = "No bones (moves as one)"
	case "*": shown = "All bones"
	}
	if imgui.BeginCombo("##vecskin", strings.clone_to_cstring(shown, context.temp_allocator), {.HeightLarge}) {
		if imgui.Selectable("No bones (moves as one)", v.skinBones == "") do vector_set_skin(state, v, "")
		Drive_Item("pick:vec-skin:")
		if imgui.Selectable("All bones", strings.trim_space(v.skinBones) == "*") do vector_set_skin(state, v, "*")
		Drive_Item("pick:vec-skin:*")
		if sn.data == nil {
			UI_DimText("The skeleton has no file loaded.")
		} else {
			imgui.Separator()
			chosen := make([dynamic]int, context.temp_allocator)
			e.Vector_SkinBoneList(sn.data, v.skinBones, &chosen)
			for b, i in sn.data.bones {
				on := false
				for c in chosen do if c == i {on = true; break}
				depth := 0
				for p := b.parent; p >= 0; p = sn.data.bones[p].parent do depth += 1
				label := fmt.ctprintf("%s %*s%s##b%d", ICON_FA_CHECK if on else "   ", depth * 2, "", b.name, i)
				if imgui.Selectable(label, on, {.NoAutoClosePopups}) {
					// Toggle it; the list stays in the skeleton's order.
					sb := strings.builder_make(context.temp_allocator)
					for bb, j in sn.data.bones {
						in_list := false
						for c in chosen do if c == j {in_list = true; break}
						if j == i do in_list = !on
						if !in_list do continue
						if strings.builder_len(sb) > 0 do strings.write_string(&sb, ", ")
						strings.write_string(&sb, bb.name)
					}
					vector_set_skin(state, v, strings.to_string(sb))
				}
				Drive_Item(fmt.tprintf("pick:vec-skin:%s", b.name))
			}
		}
		imgui.EndCombo()
	}
	Drive_Item("insp.vec.skin")
	UI_Tooltip(fmt.tprintf("Vector skinning: the art bends with these bones of %s (in its setup pose, each point follows the bones nearest it; Skin Smooth blends them round the joints)", sn.name))
}

@(private = "file")
vector_set_skin :: proc(state: ^EditorState, v: ^e.VectorShapeNode, list: string) {
	if list == v.skinBones do return
	Editor_RecordUndo(state, "Vector skin bones")
	v.skinBones = strings.clone(list, v.allocator)
}

@(private = "file")
vector_set_group :: proc(state: ^EditorState, v: ^e.VectorShapeNode, path: string) {
	if path == v.group do return
	Editor_RecordUndo(state, "Vector symbol")
	v.group = strings.clone(path, v.allocator)
	v.frame = -1
}

// Vector_ExplodeParts replaces a Vector Shape with a Node in its place (same
// name, transform, children) holding a Vector Shape per child group of what
// it draws, each with its pivot at the part's centre and placed where the
// part was - one undo step. Returns the new Node.
Vector_ExplodeParts :: proc(state: ^EditorState, v: ^e.VectorShapeNode) -> ^e.Node {
	r := e.VectorShapeNode_Asset(v)
	if r == nil || state.activeScene == nil do return nil
	g, boxMin, boxSize, ok := e.VectorShapeNode_Part(v, r)
	if !ok do return nil
	if v.frame >= 0 do g = e.Vector_ResourceGroup(r, v.group) // (all the frames, not the one showing)
	kids := e.Vector_GroupChildren(r, g)
	if len(kids) == 0 do return nil
	mgr := state.activeScene.manager
	parent := e.GetParent(mgr, v)
	if parent == nil do return nil
	Editor_RecordUndo(state, fmt.tprintf("Explode %s", v.name))
	index := 0
	for c, i in e.GetChildrenTemp(mgr, parent) do if c == v do index = i
	holder := e.Node_CreateByTypeName(state.activeScene, "Node", parent)
	holder.gameContext = &state.game.gameContext
	holder.name = strings.clone(v.name, holder.allocator)
	holder.position, holder.rotation, holder.scale, holder.zIndex = v.position, v.rotation, v.scale, v.zIndex
	holder.enabled = v.enabled
	offset := -boxMin - e.Node_OriginPx(v, boxSize)
	for k in kids {
		part := cast(^e.VectorShapeNode)e.Node_CreateByTypeName(state.activeScene, "VectorShapeNode", holder)
		part.gameContext = &state.game.gameContext
		name := r.doc.groups[k].name
		part.name = strings.clone(Editor_UniqueChildName(state, holder, name if name != "" else "Part", part), part.allocator)
		part.file = strings.clone(v.file, part.allocator)
		part.group = strings.clone(e.Vector_GroupPath(r, k), part.allocator)
		part.tint, part.brightness, part.colorAdd = v.tint, v.brightness, v.colorAdd
		part.pivot = {0.5, 0.5}
		pMin, pSize := e.Vector_PartBox(r, k)
		part.position = pMin + pSize * 0.5 + offset
	}
	if loose := e.Vector_GroupLoose(r, g); loose > 0 {
		Editor_Log(state, .Warn, "%d shape(s) of %s are outside its child groups and were left out: group them in the vector app", loose, v.name)
	}
	e.ProcessNodeQueues(mgr, &state.game.gameContext)
	// The node's own children (a LipSync, scripts' helpers...) move over.
	for c in e.GetChildren(mgr, v) {
		e.RemoveChild(mgr, v, c)
		e.AddChild(mgr, holder, c)
	}
	e.MoveChild(mgr, parent, holder, index)
	if state.selectedNode == v do state.selectedNode = nil
	e.RemoveNode(mgr, v)
	e.ProcessNodeQueues(mgr, &state.game.gameContext)
	e.Node_SetGlobalPositions(mgr, state.activeScene.rootNode)
	state.selectedNode = holder
	Editor_Log(state, .Info, "Exploded %s into %d parts", holder.name, len(kids))
	return holder
}

// Vector_ImportRows: an SVG's import settings in the Preview panel - the
// scale (document units -> px) and the origin new Vector Shapes get.
Vector_ImportRows :: proc(state: ^EditorState, full: string) {
	root := strings.concatenate({state.projectPath, "/"}, context.temp_allocator)
	if state.projectPath == "" || !strings.has_prefix(full, root) do return
	rel := full[len(root):]
	imp := Editor_AssetImport(state, full)
	changed := false
	scale := imp.vectorScale if imp.vectorScale > 0 else 1
	imgui.SetNextItemWidth(90)
	if imgui.DragFloat("Scale##vecscale", &scale, 0.01, 0.01, 100, "%.2fx") {
		imp.vectorScale = max(scale, 0.01)
		changed = true
	}
	Drive_Item("preview.vec.scale")
	UI_Tooltip("Document units to pixels for every Vector Shape drawing this file (0.5: art drawn twice as big)")
	imgui.SameLine()
	presets := [?]struct {name: cstring, v: [2]f32}{{"Centre", {0.5, 0.5}}, {"Top left", {0, 0}}, {"Bottom centre", {0.5, 1}}}
	current: cstring = "Centre"
	if imp.hasOrigin do for p in presets do if p.v == imp.origin do current = p.name
	imgui.SetNextItemWidth(130)
	if imgui.BeginCombo("Origin##vecorigin", current) {
		for p in presets {
			if imgui.Selectable(p.name, p.name == current) {
				imp.origin = p.v
				imp.hasOrigin = p.v != {0.5, 0.5}
				changed = true
			}
			Drive_Item(fmt.tprintf("pick:vec-origin:%s", p.name))
		}
		imgui.EndCombo()
	}
	Drive_Item("preview.vec.origin")
	UI_Tooltip("The origin new Vector Shapes of this file get (each node's Origin can change it)")
	if changed {
		preview_save_import(state, full, rel, imp)
		// Loaded copies pick the scale up when they reload: force it.
		rm := &state.game.resourceManager
		if r, ok := rm.vectors[e.Project_ResolveAssetPath(&state.game.gameContext, rel)]; ok do r.modTime._nsec = 1
		Editor_Log(state, .Info, "Import settings of %s: scale %.2f", rel, imp.vectorScale if imp.vectorScale > 0 else 1)
	}
}
