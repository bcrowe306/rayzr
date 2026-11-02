package editor

import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import e "../engine"

// ============================================================================
// Scene editing operations (create, duplicate, delete, components) and
// snapshot undo/redo. Every operation that changes the scene goes through
// here so undo, selection and naming behave the same from every entry point
// (menus, toolbar, shortcuts, inspector, viewport).
// ============================================================================

UNDO_LIMIT :: 100

// One undo stack for everything: scene edits (the active scene's apply,
// with the project file the same step wrote, e.g. Apply to Component) and
// edits of a project file alone (a resource in the Inspector, a saved
// component document; they apply whatever scene is active).
Undo_Kind :: enum u8 {
	Scene,
	File,
}

Undo_Entry :: struct {
	kind:     Undo_Kind,
	scene:    ^e.Scene,
	json:     Undo_Snapshot, // .Scene: the scene's JSON, in shared chunks (undo_store.odin)
	label:    string,
	selected: string, // child-index path of the selected node ("2/0"), "" = none
	version:  int,    // the scene's edit version this entry restores
	file:     string, // the project file (project-relative) the step wrote: always for .File, "" for most .Scene steps
	fileText: Undo_Snapshot, // its text before the step
}

// Editor_RecordFileUndo snapshots a project file before a change that
// writes only the file (a resource edit, saving a component document).
// (Recorded during Simulate too: these are saved to the file, not rolled
// back when the simulation stops.)
Editor_RecordFileUndo :: proc(state: ^EditorState, rel, label: string) {
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	data, err := os.read_entire_file(full, context.temp_allocator)
	if err != nil do return
	snap := Undo_Pack(string(data))
	for &r in state.redoStack do Undo_EntryDestroy(&r)
	clear(&state.redoStack)
	// Unchanged since the last step for this file: one step, not two.
	if n := len(state.undoStack); n > 0 && state.undoStack[n - 1].kind == .File && state.undoStack[n - 1].file == rel && Undo_Same(state.undoStack[n - 1].fileText, snap) {
		Undo_Release(snap)
		return
	}
	append(&state.undoStack, Undo_Entry{kind = .File, label = strings.clone(label), file = strings.clone(rel), fileText = snap})
	if len(state.undoStack) > UNDO_LIMIT {
		old := state.undoStack[0]
		Undo_EntryDestroy(&old)
		ordered_remove(&state.undoStack, 0)
	}
}

// Editor_RecordUndo snapshots the active scene before a change. `file`: a
// project file the change also writes (project-relative), snapshotted too,
// so one Undo restores both.
Editor_RecordUndo :: proc(state: ^EditorState, label: string, file := "") {
	if state.activeScene == nil || state.isSimulating do return
	state.modifiedCacheFrames = 0
	state.modifiedCountFrames = 0
	snap := Undo_Pack(e.Scene_SerializeToJSON(state.activeScene, context.temp_allocator))
	// Nothing changed since the last snapshot (e.g. a double-click
	// activating a field twice): one undo step, not two.
	if n := len(state.undoStack); file == "" && n > 0 && state.undoStack[n - 1].scene == state.activeScene && Undo_Same(state.undoStack[n - 1].json, snap) {
		Undo_Release(snap)
		// A change follows: what was undone can't be redone over it.
		for &r in state.redoStack do Undo_EntryDestroy(&r)
		clear(&state.redoStack)
		return
	}
	append(&state.undoStack, Undo_Entry{
		scene    = state.activeScene,
		json     = snap,
		label    = strings.clone(label),
		selected = Editor_NodePath(state, state.selectedNode),
		version  = state.sceneVersion[state.activeScene],
	})
	if file != "" {
		full, _ := filepath.join({state.projectPath, file}, context.temp_allocator)
		if data, err := os.read_entire_file(full, context.temp_allocator); err == nil {
			top := &state.undoStack[len(state.undoStack) - 1]
			top.file = strings.clone(file)
			top.fileText = Undo_Pack(string(data))
		}
	}
	state.nextVersion += 1
	state.sceneVersion[state.activeScene] = state.nextVersion
	if len(state.undoStack) > UNDO_LIMIT {
		old := state.undoStack[0]
		Undo_EntryDestroy(&old)
		ordered_remove(&state.undoStack, 0)
	}
	for &r in state.redoStack do Undo_EntryDestroy(&r)
	clear(&state.redoStack)
}

Undo_EntryDestroy :: proc(u: ^Undo_Entry) {
	Undo_Release(u.json)
	Undo_Release(u.fileText)
	delete(u.label)
	delete(u.selected)
	delete(u.file)
}

Editor_Undo :: proc(state: ^EditorState) -> bool {
	return undo_redo(state, &state.undoStack, &state.redoStack, "Undo")
}

Editor_Redo :: proc(state: ^EditorState) -> bool {
	return undo_redo(state, &state.redoStack, &state.undoStack, "Redo")
}

@(private = "file")
undo_redo :: proc(state: ^EditorState, from, to: ^[dynamic]Undo_Entry, verb: string) -> bool {
	ResourceInspector_Flush(state) // (an edit not written yet comes first)
	// Entries for the active scene apply, and file entries.
	for i := len(from) - 1; i >= 0; i -= 1 {
		if from[i].kind == .Scene && from[i].scene != state.activeScene do continue
		entry := from[i]
		ordered_remove(from, i)
		defer Undo_EntryDestroy(&entry)
		// The opposite step: the file and the scene as they are now.
		back := Undo_Entry{kind = entry.kind, label = strings.clone(entry.label)}
		full: string
		if entry.file != "" {
			full, _ = filepath.join({state.projectPath, entry.file}, context.temp_allocator)
			current, _ := os.read_entire_file(full, context.temp_allocator)
			back.file = strings.clone(entry.file)
			back.fileText = Undo_Pack(string(current))
		}
		if entry.kind == .Scene {
			back.scene = state.activeScene
			back.json = Undo_Pack(e.Scene_SerializeToJSON(state.activeScene, context.temp_allocator))
			back.selected = Editor_NodePath(state, state.selectedNode)
			back.version = state.sceneVersion[state.activeScene]
		}
		append(to, back)
		// The file first: the scene's instances load from it.
		if entry.file != "" && os.write_entire_file(full, transmute([]u8)Undo_Unpack(entry.fileText)) != nil {
			Editor_Log(state, .Error, "%s: could not write %s", verb, entry.file)
		}
		state.undoGeneration += 1
		if entry.kind == .Scene {
			Editor_RestoreSceneJSON(state, state.activeScene, Undo_Unpack(entry.json))
			state.sceneVersion[state.activeScene] = entry.version
			state.selectedNode = Editor_NodeAtPath(state, entry.selected)
		}
		if entry.file != "" do undo_file_restored(state, entry.file, Undo_Unpack(entry.fileText), entry.kind == .Scene)
		if entry.kind == .File {
			Editor_Log(state, .Info, "%s: %s (%s)", verb, entry.label, entry.file)
		} else {
			Editor_Log(state, .Info, "%s: %s", verb, entry.label)
		}
		return true
	}
	return false
}

// undo_file_restored: what follows a file undo / redo wrote. A component's
// instances are rebuilt in the open scenes (the active one too unless it was
// just restored with the file), and its open document is unsaved unless it
// matches the file.
@(private = "file")
undo_file_restored :: proc(state: ^EditorState, rel, text: string, sceneRestored: bool) {
	ResourceInspector_FileChanged(rel)
	if Asset_KindOf(rel) == .CustomNode {
		// A type's file: its nodes follow, and its open document.
		Editor_RefreshCustomNodes(state, rel, state.activeScene if sceneRestored else nil)
		for doc in state.componentDocs {
			if doc == nil || doc.filePath != rel do continue
			Editor_RevertCustomNodeDoc(state, doc)
			Editor_SetSceneBaseline(state, doc)
		}
		return
	}
	if Asset_KindOf(rel) != .Component do return
	e.Component_ForgetPrepared()
	if sceneRestored {
		Editor_RefreshComponentInstances(state, rel, state.activeScene)
	} else {
		sel := Editor_SaveSelection(state)
		Editor_RefreshComponentInstances(state, rel)
		Editor_RestoreSelection(state, sel)
	}
	for doc in state.componentDocs {
		if doc == nil || doc.filePath != rel do continue
		kids := e.GetChildrenView(doc.manager, doc.rootNode)
		same := len(kids) > 0 && e.Component_StampFormat(e.Node_SerializeToJSON(kids[0], doc.manager, context.temp_allocator), context.temp_allocator) == text
		state.savedVersion[doc] = state.sceneVersion[doc] if same else -1
		state.modifiedCacheFrames = 0
		state.modifiedCountFrames = 0
	}
}

// Editor_RestoreSceneJSON rebuilds a scene's nodes from JSON, in place.
Editor_RestoreSceneJSON :: proc(state: ^EditorState, scene: ^e.Scene, json: string) {
	ctx := &state.game.gameContext
	e.Scene_Unload(scene, ctx)
	e.Scene_InstantiateFromJSON(scene, transmute([]u8)json, ctx)
	e.ProcessNodeQueues(scene.manager, ctx)
	e.Node_SetGlobalPositions(scene.manager, scene.rootNode)
	scene.isLoaded = true
}

// Editor_NodePath is the child-index path from the root ("" for none/root).
Editor_NodePath :: proc(state: ^EditorState, node: ^e.Node) -> string {
	if node == nil || state.activeScene == nil || node == state.activeScene.rootNode do return ""
	mgr := state.activeScene.manager
	parts := make([dynamic]string, context.temp_allocator)
	n := node
	for n != nil && n != state.activeScene.rootNode {
		parent := e.GetParent(mgr, n)
		if parent == nil do return ""
		children := e.GetChildren(mgr, parent)
		idx := 0
		for c, i in children {
			if c == n {idx = i; break}
		}
		delete(children)
		inject_at(&parts, 0, fmt.tprint(idx))
		n = parent
	}
	return strings.join(parts[:], "/")
}

Editor_NodeAtPath :: proc(state: ^EditorState, path: string) -> ^e.Node {
	if path == "" || state.activeScene == nil do return nil
	mgr := state.activeScene.manager
	n := state.activeScene.rootNode
	for part in strings.split(path, "/", context.temp_allocator) {
		idx, _ := strconv.parse_int(part)
		children := e.GetChildren(mgr, n)
		defer delete(children)
		if idx < 0 || idx >= len(children) do return nil
		n = children[idx]
	}
	return n
}

// --- naming / placement ------------------------------------------------------------

// Editor_UniqueChildName returns `base`, or base2, base3... so siblings
// never share a name (node paths and scripts address nodes by name).
Editor_UniqueChildName :: proc(state: ^EditorState, parent: ^e.Node, base: string, exclude: ^e.Node = nil) -> string {
	clean := strings.trim_right(base, "0123456789")
	if clean == "" do clean = base
	children := e.GetChildren(state.activeScene.manager, parent)
	defer delete(children)
	// Nodes still queued for addition are children too.
	taken :: proc(children: [dynamic]^e.Node, name: string, exclude: ^e.Node) -> bool {
		for c in children {
			if c != exclude && c.name == name do return true
		}
		return false
	}
	if !taken(children, base, exclude) do return base
	for i := 2; ; i += 1 {
		name := fmt.tprintf("%s%d", clean, i)
		if !taken(children, name, exclude) do return name
	}
}

// Editor_InsertionParent: new nodes go under the selected node (or root).
Editor_InsertionParent :: proc(state: ^EditorState) -> ^e.Node {
	if state.selectedNode != nil && state.activeScene != nil do return state.selectedNode
	return state.activeScene.rootNode if state.activeScene != nil else nil
}

// Editor_WorldToLocal converts a world position into `parent`'s space
// (inverse of the parent's position, rotation and scale).
Editor_WorldToLocal :: proc(parent: ^e.Node, world: [2]f32) -> [2]f32 {
	if parent == nil do return world
	local := world - parent.globalPosition
	if parent.globalRotation != 0 {
		r := -parent.globalRotation * math.PI / 180
		c, s := math.cos(r), math.sin(r)
		local = {local.x * c - local.y * s, local.x * s + local.y * c}
	}
	sx := parent.globalScale.x if parent.globalScale.x != 0 else 1
	sy := parent.globalScale.y if parent.globalScale.y != 0 else 1
	return {local.x / sx, local.y / sy}
}

// --- operations -------------------------------------------------------------------------

// Editor_CreateNode adds a working node of `typeName` under the insertion
// parent, at the viewport centre, and selects it.
Editor_CreateNode :: proc(state: ^EditorState, typeName: string, displayName: string = "") -> ^e.Node {
	if state.activeScene == nil do return nil
	Editor_RecordUndo(state, fmt.tprintf("Add %s", typeName))
	parent := Editor_InsertionParent(state)
	node := e.Node_CreateByTypeName(state.activeScene, typeName, parent)
	if node == nil do return nil
	node.gameContext = &state.game.gameContext

	base, _ := strings.remove_all(displayName if displayName != "" else typeName, " ", context.temp_allocator)
	node.name = strings.clone(Editor_UniqueChildName(state, parent, base, node), node.allocator)
	node.position = Editor_WorldToLocal(parent, state.cameraPos)
	if state.snapGrid && state.gridSize > 0 {
		node.position = snap_vec(node.position, state.gridSize)
	}
	// A Screen Layer sits at its anchor (its position is an offset from it).
	if node.typeId == e.ScreenLayerNode do node.position = {}
	give_default_shape(node)

	e.ProcessNodeQueues(state.activeScene.manager, &state.game.gameContext)
	e.Node_SetGlobalPositions(state.activeScene.manager, state.activeScene.rootNode)
	state.selectedNode = node
	return node
}

@(private = "file")
snap_vec :: proc(v: [2]f32, step: f32) -> [2]f32 {
	return {f32(int(v.x / step + (0.5 if v.x >= 0 else -0.5))) * step, f32(int(v.y / step + (0.5 if v.y >= 0 else -0.5))) * step}
}

// Physics nodes without a shape do nothing; start them with a sensible one.
@(private = "file")
give_default_shape :: proc(node: ^e.Node) {
	shapes: ^[dynamic]e.PhysicsShape
	size: [2]f32 = {64, 64}
	sensor := false
	switch node.typeId {
	case e.DynamicBodyNode: shapes = &(cast(^e.DynamicBodyNode)node).shapes
	case e.StaticBodyNode: shapes = &(cast(^e.StaticBodyNode)node).shapes; size = {256, 32}
	case e.KinematicBodyNode: shapes = &(cast(^e.KinematicBodyNode)node).shapes; size = {128, 32}
	case e.AreaNode: shapes = &(cast(^e.AreaNode)node).shapes; size = {128, 128}; sensor = true
	}
	if shapes == nil || len(shapes) > 0 do return
	shape: e.PhysicsShape
	e.PhysicsShape_InitDefault(&shape, .Box)
	shape.size = size
	shape.isSensor = sensor
	append(shapes, shape)
}

// Editor_DuplicateNode deep-copies a node (all properties, resources,
// script values and children) next to the original.
Editor_DuplicateNode :: proc(state: ^EditorState, node: ^e.Node) -> ^e.Node {
	if node == nil || state.activeScene == nil || node == state.activeScene.rootNode do return nil
	Editor_RecordUndo(state, fmt.tprintf("Duplicate %s", node.name))
	mgr := state.activeScene.manager
	parent := e.GetParent(mgr, node)
	json := e.Node_SerializeToJSON(node, mgr, context.temp_allocator)
	copy := e.Scene_InstantiateNodeFromJSON(state.activeScene, transmute([]u8)json, parent, &state.game.gameContext)
	if copy == nil do return nil
	copy.name = strings.clone(Editor_UniqueChildName(state, parent, node.name, copy), copy.allocator)
	offset := state.gridSize if state.gridSize > 0 else 16
	copy.position += {offset, offset}
	e.ProcessNodeQueues(mgr, &state.game.gameContext)
	e.Node_ForgetCopiedUids(mgr, copy) // (a new node, not the original: #77)
	e.Node_SetGlobalPositions(mgr, state.activeScene.rootNode)
	state.selectedNode = copy
	return copy
}

Editor_DeleteNode :: proc(state: ^EditorState, node: ^e.Node) -> bool {
	if node == nil || state.activeScene == nil do return false
	if node == state.activeScene.rootNode {
		Editor_Log(state, .Warn, "Cannot delete the root node")
		return false
	}
	Editor_RecordUndo(state, fmt.tprintf("Delete %s", node.name))
	if state.selectedNode == node do state.selectedNode = nil
	e.RemoveNode(state.activeScene.manager, node)
	e.ProcessNodeQueues(state.activeScene.manager, &state.game.gameContext)
	return true
}

// Editor_ReparentNode moves a node under a new parent, keeping its world
// position.
Editor_ReparentNode :: proc(state: ^EditorState, node, newParent: ^e.Node) -> bool {
	if node == nil || newParent == nil || node == newParent || state.activeScene == nil do return false
	// Nodes can be added into an instance (saved as overrides), but the
	// component's own nodes keep their place.
	if Editor_NodeLocked(state, node) {
		Editor_Log(state, .Warn, "'%s' belongs to a component: delete it here or move it in the component", node.name)
		return false
	}
	mgr := state.activeScene.manager
	// No cycles: newParent must not be inside node's subtree.
	for p := newParent; p != nil; p = e.GetParent(mgr, p) {
		if p == node do return false
	}
	old := e.GetParent(mgr, node)
	if old == newParent do return false
	Editor_RecordUndo(state, fmt.tprintf("Move %s", node.name))
	snap := NodeRefs_Capture(state) // scripts / node properties pointing into it
	world := node.globalPosition
	if old != nil do e.RemoveChild(mgr, old, node)
	e.AddChild(mgr, newParent, node)
	node.position = Editor_WorldToLocal(newParent, world)
	node.name = strings.clone(Editor_UniqueChildName(state, newParent, node.name, node), node.allocator)
	e.Node_SetGlobalPositions(mgr, state.activeScene.rootNode)
	NodeRefs_AfterChange(state, snap)
	return true
}

// --- components (prefabs) ------------------------------------------------------------------

Editor_ComponentsDir :: proc(state: ^EditorState) -> string {
	p, _ := filepath.join({state.projectPath, "components"}, context.temp_allocator)
	return p
}

// Component_SafeName: a component name as a file name on every platform
// (/ \ : * ? " < > | and control characters become _, no leading or
// trailing spaces or dots).
Component_SafeName :: proc(name: string) -> string {
	b := make([]u8, len(name), context.temp_allocator)
	for i in 0 ..< len(name) {
		ch := name[i]
		switch ch {
		case '/', '\\', ':', '*', '?', '"', '<', '>', '|': ch = '_'
		case: if ch < 0x20 do ch = '_'
		}
		b[i] = ch
	}
	out := strings.trim(string(b), " .")
	return out if out != "" else "Component"
}

// Component_FreePath: components/<name>.component.json, or <name>_2, _3...
// when taken (project-relative, temp allocated).
Component_FreePath :: proc(state: ^EditorState, name: string) -> string {
	base := Component_SafeName(name)
	for i := 1; ; i += 1 {
		stem := base if i == 1 else fmt.tprintf("%s_%d", base, i)
		rel := fmt.tprintf("components/%s.component.json", stem)
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		if !os.exists(full) do return rel
	}
}

// Editor_SaveComponent writes a node subtree to components/<name>.component.json
// (name "" = the node's name) and links the node to it. An instance is
// saved with its overrides baked in (Save as New Component).
Editor_SaveComponent :: proc(state: ^EditorState, node: ^e.Node, name: string = "") -> (string, bool) {
	Lua_MarkProjectTypesDirty() // generated Lua types follow the project
	if node == nil || state.activeScene == nil do return "", false
	mgr := state.activeScene.manager
	_ = os.make_directory_all(Editor_ComponentsDir(state))
	// Never replaces an existing component: a free name (Enemy_2...) (#73).
	rel := Component_FreePath(state, name if name != "" else node.name)
	if Editor_FormatBlocksSave(state, rel) do return "", false // (from a newer Rayzr: #326)
	path, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	// The file holds the full subtree (not a link to itself).
	json := e.Component_InstanceJSON(node, mgr, context.temp_allocator)
	Editor_InvalidateProjectFiles() // the asset lists rescan
	if os.write_entire_file(path, transmute([]u8)json) != nil {
		Editor_Log(state, .Error, "Failed to save component to %s", path)
		return path, false
	}
	// The node becomes a linked instance of the component it was saved as.
	Editor_RecordUndo(state, "Save as component")
	sel := Editor_SaveSelection(state) // (the node is rebuilt as an instance: #74)
	node.componentPath = strings.clone(asset_rel_editor(state, path), node.allocator)
	node.componentBase = ""
	node.uid = "" // (its uid is the component root's now, in the file)
	e.Scene_RevertComponentOverrides(state.activeScene, node, &state.game.gameContext)
	Editor_RestoreSelection(state, sel)
	Editor_Log(state, .Info, "Saved component %s (this node is now linked to it)", path)
	return path, true
}

// Editor_ApplyInstanceToComponent writes an instance (with its overrides,
// added and removed children) back to its component file and updates every
// instance.
Editor_ApplyInstanceToComponent :: proc(state: ^EditorState, inst: ^e.Node) -> bool {
	if inst == nil || inst.componentPath == "" || state.activeScene == nil do return false
	rel := strings.clone(inst.componentPath, context.temp_allocator)
	if Editor_FormatBlocksSave(state, rel) do return false // (from a newer Rayzr: #326)
	json := e.Component_InstanceJSON(inst, state.activeScene.manager, context.temp_allocator)
	disk, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	// One undo step for the scene and the file (#76), taken before the file
	// changes.
	Editor_RecordUndo(state, "Apply to component", rel)
	Editor_InvalidateProjectFiles() // the asset lists rescan
	if os.write_entire_file(disk, transmute([]u8)json) != nil {
		Editor_Log(state, .Error, "Failed to write %s", disk)
		return false
	}
	// Every instance of the file is rebuilt (this one too): the selection is
	// kept as paths, not pointers to freed nodes (#74).
	sel := Editor_SaveSelection(state)
	defer Editor_RestoreSelection(state, sel)
	inst.componentBase = ""
	e.Scene_RevertComponentOverrides(state.activeScene, inst, &state.game.gameContext)
	n := Editor_RefreshComponentInstances(state, rel)
	Editor_Log(state, .Info, "Applied changes to %s (%d instance(s) updated)", rel, n)
	return true
}

// Editor_RevertOverride drops one overridden value of a node in an instance
// (`key` as Node_ComponentOverrides lists it): it follows the component
// file again (#84).
Editor_RevertOverride :: proc(state: ^EditorState, node: ^e.Node, key: string) -> bool {
	if state.activeScene == nil || node == nil do return false
	Editor_RecordUndo(state, fmt.tprintf("Revert %s", key))
	sel := Editor_SaveSelection(state) // (the instance is rebuilt: #74)
	defer Editor_RestoreSelection(state, sel)
	return e.Scene_RevertComponentOverride(state.activeScene, node, key, &state.game.gameContext) != nil
}

// Editor_ApplyOverride writes one overridden value of a node to the
// component file of the instance holding the override, and updates every
// instance (#84).
Editor_ApplyOverride :: proc(state: ^EditorState, node: ^e.Node, key: string) -> bool {
	if state.activeScene == nil || node == nil do return false
	ctx := &state.game.gameContext
	rel, json := e.Component_ApplyOverrideJSON(state.activeScene, node, key, ctx, context.temp_allocator)
	if rel == "" || Editor_FormatBlocksSave(state, rel) do return false // (from a newer Rayzr: #326)
	disk, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	// One undo step for the scene and the file, taken before the file
	// changes (#76).
	Editor_RecordUndo(state, fmt.tprintf("Apply %s to component", key), rel)
	Editor_InvalidateProjectFiles() // the asset lists rescan
	if os.write_entire_file(disk, transmute([]u8)json) != nil {
		Editor_Log(state, .Error, "Failed to write %s", disk)
		return false
	}
	sel := Editor_SaveSelection(state) // (instances are rebuilt: #74)
	defer Editor_RestoreSelection(state, sel)
	// This instance drops the override (the file has the value now); the
	// others follow the file unless they override it themselves.
	e.Scene_RevertComponentOverride(state.activeScene, node, key, ctx)
	n := Editor_RefreshComponentInstances(state, rel)
	Editor_Log(state, .Info, "Applied %s to %s (%d instance(s) updated)", key, rel, n)
	return true
}

// Editor_InstantiateComponentFile adds a *linked* instance of a component
// file (project-relative path) at a world position.
Editor_InstantiateComponentFile :: proc(state: ^EditorState, rel: string, worldPos: [2]f32) -> ^e.Node {
	if state.activeScene == nil do return nil
	// A component can't contain itself, directly or through the components
	// it contains (A -> B -> A) (#75).
	if Editor_IsComponentDoc(state, state.activeScene) {
		doc := state.activeScene.filePath
		if doc == rel || e.Component_Contains(&state.game.gameContext, rel, doc) {
			Editor_Log(state, .Warn, "%s can't go inside %s: it would contain itself", filepath.base(rel), filepath.base(doc))
			return nil
		}
	}
	Editor_RecordUndo(state, fmt.tprintf("Instantiate %s", rel))
	parent := Editor_InsertionParent(state)
	if root := e.Node_ComponentRoot(state.activeScene.manager, parent); root != nil do parent = e.GetParent(state.activeScene.manager, root)
	node := e.Scene_InstantiateComponent(state.activeScene, rel, parent, &state.game.gameContext)
	if node == nil {
		Editor_Log(state, .Error, "Component %s could not be instantiated", rel)
		return nil
	}
	base := filepath.stem(filepath.stem(rel))
	node.name = strings.clone(Editor_UniqueChildName(state, parent, base, node), node.allocator)
	node.position = Editor_WorldToLocal(parent, worldPos)
	e.ProcessNodeQueues(state.activeScene.manager, &state.game.gameContext)
	e.Node_SetGlobalPositions(state.activeScene.manager, state.activeScene.rootNode)
	state.selectedNode = node
	Editor_Log(state, .Info, "Added linked instance of %s", rel)
	return node
}

// Editor_NodeLocked: nodes inside a linked component instance (below its
// root) come from the component file and can't be edited in the scene.
Editor_NodeLocked :: proc(state: ^EditorState, node: ^e.Node) -> bool {
	if node == nil || state.activeScene == nil do return false
	root := e.Node_ComponentRoot(state.activeScene.manager, node)
	return root != nil && root != node
}
