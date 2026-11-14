package editor

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// A custom node type as a document (#155): its defaults edited like a node -
// the shape in the viewport, the values in the Inspector - and saved back
// into its .node.json ("defaults": what differs from its base type, or from
// its parent type). The document is a component document (its tab, save,
// revert, undo of the file) whose path ends in .node.json.
//
// When a type's file changes (this document, the Code tab, an undo), its
// nodes in the open documents - and those of the types built on it - are
// rebuilt: each keeps what it changed, the rest follows the type.
// ============================================================================

// Editor_IsCustomNodeDoc: a custom node type's document.
Editor_IsCustomNodeDoc :: proc(state: ^EditorState, scene: ^e.Scene) -> bool {
	return Editor_IsComponentDoc(state, scene) && strings.has_suffix(scene.filePath, e.CUSTOM_NODE_SUFFIX)
}

// Editor_RefreshCustomNodes: a type's file changed - the types are read
// again and its nodes (and those of the types built on it) rebuilt in every
// open document (`skip`: not that one). Returns how many.
Editor_RefreshCustomNodes :: proc(state: ^EditorState, rel: string, skip: ^e.Scene = nil) -> int {
	e.CustomNodes_Forget()
	Lua_MarkProjectTypesDirty()
	sel := Editor_SaveSelection(state)
	n := 0
	for _, s in state.game.sceneManager.scenes {
		if s == nil || s == skip || !s.isLoaded do continue
		n += e.Scene_RefreshCustomNodes(s, rel, &state.game.gameContext)
	}
	Editor_RestoreSelection(state, sel)
	return n
}

// Editor_OpenCustomNodeType opens a type for editing: a document holding
// one node of it at the origin.
Editor_OpenCustomNodeType :: proc(state: ^EditorState, rel: string) -> bool {
	for scene, _ in state.componentDocs {
		if scene.filePath == rel {
			Editor_SwitchView(state, scene)
			state.activeScene = scene
			state.game.sceneManager.currentScene = scene
			state.game.gameContext.scene = scene
			delete(state.activeScenePath)
			state.activeScenePath = strings.clone(rel)
			state.selectedNode = nil
			return true
		}
	}
	ctx := &state.game.gameContext
	t, problem := e.CustomNode_Get(ctx, rel)
	if t == nil {
		Editor_Log(state, .Error, "%s can't be edited: %s", rel, problem)
		return false
	}
	name := strings.clone(t.name, context.temp_allocator)
	scene := state.game.sceneManager.scenes[fmt.tprintf("component:%s", rel)]
	if scene == nil do scene = state.game->createScene(fmt.tprintf("component:%s", rel), false)
	scene.filePath = strings.clone(rel, state.game.sceneManager.allocator)
	scene.rootNode.gameContext = ctx
	node := custom_doc_build(state, scene, t)
	scene.isLoaded = true
	state.componentDocs[scene] = true
	Editor_SetSceneBaseline(state, scene)
	Editor_SwitchView(state, scene)
	state.sceneViews[scene] = {0, 0, 1}
	state.activeScene = scene
	state.game.sceneManager.currentScene = scene
	state.game.gameContext.scene = scene
	delete(state.activeScenePath)
	state.activeScenePath = strings.clone(rel)
	state.selectedNode = node
	state.cameraPos = {0, 0}
	state.cameraZoom = 1
	Editor_Log(state, .Info, "Editing the %s type - its values are what new %s nodes start with; save to update them", name, name)
	return true
}

@(private = "file")
custom_doc_build :: proc(state: ^EditorState, scene: ^e.Scene, t: ^e.CustomNodeType) -> ^e.Node {
	ctx := &state.game.gameContext
	node := e.Scene_CreateCustomNode(scene, t, scene.rootNode, ctx)
	if node != nil do node.position = {0, 0}
	// Its own signals are the type's (edited here, saved in its defaults).
	if node != nil do for s in e.CustomNode_Signals(t, ctx, ownOnly = true) do e.Node_AddSignal(node, s.decl)
	e.ProcessNodeQueues(scene.manager, ctx)
	e.Node_SetGlobalPositions(scene.manager, scene.rootNode)
	return node
}

// Editor_RevertCustomNodeDoc: the document's node as the type is on disk.
Editor_RevertCustomNodeDoc :: proc(state: ^EditorState, scene: ^e.Scene) {
	e.CustomNodes_Forget()
	t, _ := e.CustomNode_Get(&state.game.gameContext, scene.filePath)
	e.Scene_Unload(scene, &state.game.gameContext)
	if t != nil do custom_doc_build(state, scene, t)
	scene.isLoaded = true
}

// Editor_SaveCustomNodeDoc writes the document's node back as the type's
// defaults (its name, base, script, look kept), then updates its nodes.
Editor_SaveCustomNodeDoc :: proc(state: ^EditorState, scene: ^e.Scene) -> bool {
	ctx := &state.game.gameContext
	kids := e.GetChildrenView(scene.manager, scene.rootNode)
	if len(kids) == 0 {
		Editor_Log(state, .Error, "The type's document is empty")
		return false
	}
	node := kids[0]
	if Editor_FormatBlocksSave(state, scene.filePath) do return false // (from a newer Rayzr: #326)
	t, problem := e.CustomNode_Get(ctx, scene.filePath)
	if t == nil {
		Editor_Log(state, .Error, "%s can't be saved: %s", scene.filePath, problem)
		return false
	}
	if len(e.GetChildrenView(scene.manager, node)) > 0 {
		Editor_Log(state, .Warn, "A custom node type is one node: its children aren't saved (make a component for a node tree)")
	}
	parent: ^e.CustomNodeType
	if t.inherits != "" do parent, _ = e.CustomNode_Get(ctx, t.inherits)
	d := e.CustomNode_Definition{
		name        = t.name,
		base        = t.base,
		inherits    = t.inherits,
		script      = t.script,
		icon        = t.icon,
		color       = t.color,
		category    = t.category,
		description = t.description,
		defaults    = e.CustomNode_DefaultsFromNode(node, scene.manager, context.temp_allocator, parent),
	}
	text := e.CustomNode_DefinitionJSON(d, context.temp_allocator) // (t is freed below: d's strings go with it)
	disk, _ := filepath.join({state.projectPath, scene.filePath}, context.temp_allocator)
	Editor_RecordFileUndo(state, scene.filePath, fmt.tprintf("Save %s", scene.filePath))
	if os.write_entire_file(disk, transmute([]u8)text) != nil {
		Editor_Log(state, .Error, "Failed to write %s", disk)
		return false
	}
	Editor_SetSceneBaseline(state, scene)
	n := Editor_RefreshCustomNodes(state, scene.filePath, scene)
	Editor_Log(state, .Info, "Saved the %s type (%d node(s) updated)", filepath.stem(filepath.stem(scene.filePath)), n)
	return true
}

// --- changing a type's base ---------------------------------------------------------
// Change Base Type (a type's right-click in Assets, or its document's root):
// a preview - what of the type's values doesn't carry over, the scenes and
// components with nodes of it (or of the types built on it) - then the type
// is rewritten and those files loaded and saved again: each node keeps what
// it changed that the new base has. Open documents with nodes of it must be
// saved first; each written file can be undone.

@(private = "file")
Rebase_File :: struct {
	rel:   string, // (heap)
	count: int,
}

@(private = "file")
Rebase_Dialog :: struct {
	open:    bool,
	typeRel: string,                // (heap)
	newBase: string,                // (heap)
	files:   [dynamic]Rebase_File,
	dropped: [dynamic]string,       // (heap) for newBase
	filter:  [64]u8,
}

@(private = "file")
rdlg: Rebase_Dialog

@(private = "file")
rdlg_clear :: proc() {
	if rdlg.typeRel != "" do delete(rdlg.typeRel)
	if rdlg.newBase != "" do delete(rdlg.newBase)
	for f in rdlg.files do delete(f.rel)
	delete(rdlg.files)
	for d in rdlg.dropped do delete(d)
	delete(rdlg.dropped)
	rdlg = {}
}

// custom_type_family: the type and the types built on it (paths).
@(private = "file")
custom_type_family :: proc(state: ^EditorState, rel: string) -> []string {
	ctx := &state.game.gameContext
	out := make([dynamic]string, context.temp_allocator)
	append(&out, rel)
	t, _ := e.CustomNode_Get(ctx, rel)
	if t == nil do return out[:]
	name := strings.clone(t.name, context.temp_allocator)
	for x in e.CustomNodes_All(ctx) do if x.path != rel && e.CustomNode_Inherits(x, name, ctx) do append(&out, strings.clone(x.path, context.temp_allocator))
	return out[:]
}

// custom_count_in_file: nodes of the family in a scene / component file.
@(private = "file")
custom_count_in_file :: proc(state: ^EditorState, rel: string, family: []string) -> int {
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	data, err := os.read_entire_file(full, context.temp_allocator)
	if err != nil do return 0
	text := string(data)
	found := false
	for p in family do if strings.contains(text, p) do found = true
	if !found do return 0
	val, perr := json.parse(data, allocator = context.temp_allocator)
	if perr != .None do return 0
	count := 0
	walk :: proc(v: json.Value, family: []string, count: ^int) {
		obj, isObj := v.(json.Object)
		if !isObj do return
		if t, has := obj[e.CUSTOM_NODE_KEY].(json.String); has {
			for p in family do if string(t) == p do count^ += 1
		}
		if kids, has := obj["children"].(json.Array); has do for k in kids do walk(k, family, count)
		if root, has := obj["root"]; has do walk(root, family, count)
	}
	walk(val, family, &count)
	return count
}

// CustomNodeRebase_Open: the Change Base Type preview for a type.
CustomNodeRebase_Open :: proc(state: ^EditorState, rel: string) {
	rdlg_clear()
	rdlg.open = true
	rdlg.typeRel = strings.clone(rel)
	t, _ := e.CustomNode_Get(&state.game.gameContext, rel)
	rdlg.newBase = strings.clone(t.base if t != nil else "Node")
	family := custom_type_family(state, rel)
	for f in Editor_ListProjectFiles(state, "", {".scene.json", ".component.json"}) {
		if n := custom_count_in_file(state, f, family); n > 0 do append(&rdlg.files, Rebase_File{strings.clone(f), n})
	}
}

@(private = "file")
rebase_preview :: proc(state: ^EditorState) {
	for d in rdlg.dropped do delete(d)
	clear(&rdlg.dropped)
	t, _ := e.CustomNode_Get(&state.game.gameContext, rdlg.typeRel)
	if t == nil || rdlg.newBase == t.base do return
	_, dropped := e.CustomNode_Rebase(t, rdlg.newBase, &state.game.gameContext, context.temp_allocator)
	for d in dropped do append(&rdlg.dropped, strings.clone(d))
}

// rebase_blockers: open documents with nodes of the type and unsaved changes.
@(private = "file")
rebase_blockers :: proc(state: ^EditorState) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	for _, s in state.game.sceneManager.scenes {
		if s == nil || !s.isLoaded || s.filePath == "" || !Editor_SceneIsModified(state, s) do continue
		for f in rdlg.files do if f.rel == s.filePath do append(&out, s.filePath)
	}
	return out[:]
}

CustomNodeRebase_Render :: proc(state: ^EditorState) {
	if rdlg.open && !imgui.IsPopupOpen("Change Base Type###CustomNodeRebase") do imgui.OpenPopup("Change Base Type###CustomNodeRebase")
	io := imgui.GetIO()
	imgui.SetNextWindowSize({620, 0}, .Appearing)
	imgui.SetNextWindowPos({io.DisplaySize.x * 0.5, io.DisplaySize.y * 0.5}, .Appearing, {0.5, 0.5})
	imgui.PushStyleVarImVec2(.WindowPadding, {16, 14})
	defer imgui.PopStyleVar()
	if !imgui.BeginPopupModal("Change Base Type###CustomNodeRebase", &rdlg.open, {.NoTitleBar, .AlwaysAutoResize}) do return
	ctx := &state.game.gameContext
	t, _ := e.CustomNode_Get(ctx, rdlg.typeRel)
	if t == nil {
		imgui.CloseCurrentPopup()
		rdlg.open = false
		imgui.EndPopup()
		return
	}
	UI_PanelTitle(ICON_FA_PUZZLE_PIECE, fmt.tprintf("Change the base of %s", t.name))
	imgui.Dummy({0, 4})
	if t.inherits != "" {
		parent, _ := e.CustomNode_Get(ctx, t.inherits)
		imgui.TextWrapped("%s", fmt.ctprintf("%s is built on %s: its base is %s's (%s). Change it there.", t.name, parent.name if parent != nil else t.inherits, parent.name if parent != nil else "its parent", t.base))
		imgui.Dummy({0, 8})
		if UI_Button("Close", "rebase.close", {90, 30}) || imgui.IsKeyPressed(.Escape) {
			rdlg.open = false
			imgui.CloseCurrentPopup()
		}
		imgui.EndPopup()
		return
	}
	UI_DimText(fmt.tprintf("Now: %s", t.base))
	imgui.SetNextItemWidth(-1)
	if imgui.BeginCombo("##rebase_base", strings.clone_to_cstring(rdlg.newBase, context.temp_allocator), {.HeightLarge}) {
		imgui.SetNextItemWidth(-1)
		imgui.InputTextWithHint("##rebase_filter", "Search types", cstring(raw_data(rdlg.filter[:])), len(rdlg.filter), {})
		filter := strings.to_lower(strings.trim_space(string(cstring(raw_data(rdlg.filter[:])))), context.temp_allocator)
		for entry in NODE_CATALOG {
			if filter != "" && !strings.contains(strings.to_lower(entry.name, context.temp_allocator), filter) && !strings.contains(strings.to_lower(entry.typeName, context.temp_allocator), filter) do continue
			if imgui.Selectable(fmt.ctprintf("%s  %s  (%s)##rb_%s", entry.icon, entry.name, entry.typeName, entry.name), rdlg.newBase == entry.typeName) {
				delete(rdlg.newBase)
				rdlg.newBase = strings.clone(entry.typeName)
				rebase_preview(state)
			}
			Drive_Item(fmt.tprintf("rebase.base:%s", entry.typeName))
		}
		imgui.EndCombo()
	}
	Drive_Item("rebase.base")
	imgui.Dummy({0, 6})
	if len(rdlg.dropped) > 0 {
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextWrapped("%s", fmt.ctprintf("Doesn't carry over (a %s doesn't have it): %s", rdlg.newBase, strings.join(rdlg.dropped[:], ", ", context.temp_allocator)))
		imgui.PopStyleColor()
		Drive_Item("rebase.dropped")
	} else if rdlg.newBase != t.base {
		UI_DimText("All its values carry over.")
	}
	family := custom_type_family(state, rdlg.typeRel)
	if len(family) > 1 {
		names := make([dynamic]string, context.temp_allocator)
		for p in family[1:] do if x, _ := e.CustomNode_Get(ctx, p); x != nil do append(&names, x.name)
		UI_DimText(fmt.tprintf("Built on it (their base changes too): %s", strings.join(names[:], ", ", context.temp_allocator)))
	}
	imgui.Dummy({0, 4})
	if len(rdlg.files) == 0 {
		UI_DimText("No scene or component has nodes of it.")
	} else {
		UI_DimText("Converted (each file can be undone):")
		for f in rdlg.files do imgui.BulletText("%s", fmt.ctprintf("%s - %d node(s)", f.rel, f.count))
	}
	blockers := rebase_blockers(state)
	if len(blockers) > 0 {
		imgui.Dummy({0, 4})
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextWrapped("%s", fmt.ctprintf("Save first (unsaved changes): %s", strings.join(blockers, ", ", context.temp_allocator)))
		imgui.PopStyleColor()
	}
	imgui.Dummy({0, 8})
	imgui.SetCursorPosX(imgui.GetWindowWidth() - 16 - 120 - 90 - UI_SPACE)
	if UI_Button("Cancel", "rebase.cancel", {90, 30}) || imgui.IsKeyPressed(.Escape) {
		rdlg.open = false
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine(0, UI_SPACE)
	imgui.BeginDisabled(rdlg.newBase == t.base || len(blockers) > 0)
	convert := UI_PrimaryButton("Convert", "rebase.convert", {120, 30})
	imgui.EndDisabled()
	if convert {
		rdlg.open = false
		imgui.CloseCurrentPopup()
		Editor_RebaseCustomNode(state, rdlg.typeRel, rdlg.newBase)
	}
	imgui.EndPopup()
}

// Editor_RebaseCustomNode changes a type's base: its file (its values for
// the new base), then every scene / component with nodes of it (or of the
// types built on it) - open ones refreshed and saved, others loaded and
// saved again.
Editor_RebaseCustomNode :: proc(state: ^EditorState, rel, newBase: string) -> bool {
	ctx := &state.game.gameContext
	typeRel := strings.clone(rel, context.temp_allocator)
	base := strings.clone(newBase, context.temp_allocator)
	t, problem := e.CustomNode_Get(ctx, typeRel)
	if t == nil {
		Editor_Log(state, .Error, "%s: %s", typeRel, problem)
		return false
	}
	family := custom_type_family(state, typeRel)
	files := make([dynamic]string, context.temp_allocator)
	for f in Editor_ListProjectFiles(state, "", {".scene.json", ".component.json"}) {
		if custom_count_in_file(state, f, family) > 0 do append(&files, strings.clone(f, context.temp_allocator))
	}
	defaults, _ := e.CustomNode_Rebase(t, base, ctx, context.temp_allocator)
	d := e.CustomNode_Definition{
		name = t.name, base = base, script = t.script, icon = t.icon, color = t.color,
		category = t.category, description = t.description, defaults = defaults,
	}
	name := strings.clone(t.name, context.temp_allocator)
	text := e.CustomNode_DefinitionJSON(d, context.temp_allocator)
	disk, _ := filepath.join({state.projectPath, typeRel}, context.temp_allocator)
	Editor_RecordFileUndo(state, typeRel, fmt.tprintf("%s: base %s", name, base))
	if os.write_entire_file(disk, transmute([]u8)text) != nil {
		Editor_Log(state, .Error, "Could not write %s", typeRel)
		return false
	}
	// Open documents: their nodes rebuilt with the new type (then saved:
	// they had no unsaved changes); type documents of the family again.
	Editor_RefreshCustomNodes(state, typeRel)
	open := make(map[string]^e.Scene, 8, context.temp_allocator)
	for _, s in state.game.sceneManager.scenes do if s != nil && s.isLoaded && s.filePath != "" do open[s.filePath] = s
	for p in family {
		if doc, ok := open[p]; ok && Editor_IsCustomNodeDoc(state, doc) {
			Editor_RevertCustomNodeDoc(state, doc)
			Editor_SetSceneBaseline(state, doc)
		}
	}
	converted := 0
	for f in files {
		Editor_RecordFileUndo(state, f, fmt.tprintf("%s: base %s", name, base))
		if doc, ok := open[f]; ok {
			if Editor_SaveSceneDocument(state, doc) do converted += 1
			continue
		}
		if custom_resave_file(state, f) do converted += 1
	}
	Editor_InvalidateProjectFiles()
	Editor_Log(state, .Info, "%s is now based on %s (%d file(s) converted)", name, base, converted)
	return true
}

// custom_resave_file loads a scene or component file (with the types as
// they are now) and writes it again.
@(private = "file")
custom_resave_file :: proc(state: ^EditorState, rel: string) -> bool {
	if Editor_FormatBlocksSave(state, rel) do return false // (from a newer Rayzr: #326)
	ctx := &state.game.gameContext
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	data, err := os.read_entire_file(full, context.temp_allocator)
	if err != nil do return false
	scratch := new(e.Scene)
	e.InitializeScene(scratch)
	defer {
		e.TerminateScene(scratch)
		free(scratch)
	}
	out: string
	if strings.has_suffix(rel, ".component.json") {
		node := e.Scene_InstantiateNodeFromJSON(scratch, data, scratch.rootNode, ctx)
		if node == nil do return false
		e.ProcessNodeQueues(scratch.manager, ctx)
		out = e.Component_FileJSON(node, scratch.manager, context.temp_allocator)
	} else {
		if !e.Scene_InstantiateFromJSON(scratch, data, ctx) do return false
		e.ProcessNodeQueues(scratch.manager, ctx)
		out = e.Scene_SerializeToJSON(scratch, context.temp_allocator)
	}
	return os.write_entire_file(full, transmute([]u8)out) == nil
}
