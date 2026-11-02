package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Components (prefabs). A component file holds a node subtree; scenes keep
// *linked* instances of it (the scene stores only the instance's link, name
// and transform). "Edit Component" opens the file as its own document;
// saving it refreshes every instance in the open scenes.
// ============================================================================


Editor_IsComponentDoc :: proc(state: ^EditorState, scene: ^e.Scene) -> bool {
	return scene != nil && state.componentDocs[scene]
}

// Editor_OpenComponent opens a component file for editing, as a document
// whose root holds the component's node.
Editor_OpenComponent :: proc(state: ^EditorState, rel: string) -> bool {
	if strings.has_suffix(rel, e.CUSTOM_NODE_SUFFIX) do return Editor_OpenCustomNodeType(state, rel) // (a type's document)
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
	data, ok := e.Component_ReadFile(&state.game.gameContext, rel)
	if !ok {
		Editor_Log(state, .Error, "Component file not found: %s", rel)
		return false
	}
	// A document closed before keeps its (unloaded) scene: reuse it.
	scene := state.game.sceneManager.scenes[fmt.tprintf("component:%s", rel)]
	if scene == nil do scene = state.game->createScene(fmt.tprintf("component:%s", rel), false)
	scene.filePath = strings.clone(rel, state.game.sceneManager.allocator)
	scene.rootNode.gameContext = &state.game.gameContext
	node := e.Scene_InstantiateNodeFromJSON(scene, data, scene.rootNode, &state.game.gameContext)
	if node != nil do node.position = {0, 0}
	scene.formatNewer = e.Format_IsNewer(.Component, e.Format_OfText(data)) // (read-only: #326)
	e.ProcessNodeQueues(scene.manager, &state.game.gameContext)
	e.Node_SetGlobalPositions(scene.manager, scene.rootNode)
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
	Editor_Log(state, .Info, "Editing component %s - save to update its instances", rel)
	return true
}

// Editor_SaveComponentDoc writes a component document back to its file and
// refreshes the instances in every open scene.
Editor_SaveComponentDoc :: proc(state: ^EditorState, scene: ^e.Scene) -> bool {
	if Editor_FormatBlocksSave(state, scene.filePath) do return false // (from a newer Rayzr: #326)
	if Editor_IsCustomNodeDoc(state, scene) do return Editor_SaveCustomNodeDoc(state, scene)
	children := e.GetChildrenView(scene.manager, scene.rootNode)
	if len(children) == 0 {
		Editor_Log(state, .Error, "Component document is empty")
		return false
	}
	json := e.Component_FileJSON(children[0], scene.manager, context.temp_allocator) // (every node gets a uid: #77)
	disk, _ := filepath.join({state.projectPath, scene.filePath}, context.temp_allocator)
	// Undo puts the file (and so the instances) back (#76).
	Editor_RecordFileUndo(state, scene.filePath, fmt.tprintf("Save %s", scene.filePath))
	Editor_InvalidateProjectFiles() // the asset lists rescan
	if os.write_entire_file(disk, transmute([]u8)json) != nil {
		Editor_Log(state, .Error, "Failed to write %s", disk)
		return false
	}
	Editor_SetSceneBaseline(state, scene)
	sel := Editor_SaveSelection(state) // (Save All: the active scene may have instances)
	refreshed := Editor_RefreshComponentInstances(state, scene.filePath)
	Editor_RestoreSelection(state, sel)
	Editor_Log(state, .Info, "Saved component %s (%d instance(s) updated)", scene.filePath, refreshed)
	return true
}

// Editor_RefreshComponentInstances rebuilds the instances of a component
// file in every open document - scenes and component documents nesting it
// (#79) - except `skip`. Returns how many were rebuilt. When the active
// scene is refreshed, the caller keeps the selection (Editor_SaveSelection
// before any rebuild, #74).
Editor_RefreshComponentInstances :: proc(state: ^EditorState, rel: string, skip: ^e.Scene = nil) -> int {
	n := 0
	for _, s in state.game.sceneManager.scenes {
		if s == nil || s == skip || !s.isLoaded do continue
		n += e.Scene_RefreshComponentInstances(s, rel, &state.game.gameContext)
	}
	return n
}

// --- conveniences (#86) ---------------------------------------------------------------

// Editor_EditComponentAt opens the component of the instance holding
// `node`, with that node selected in the document (its root when the node
// was added to the instance, not part of the component).
Editor_EditComponentAt :: proc(state: ^EditorState, node: ^e.Node) -> bool {
	if state.activeScene == nil || node == nil do return false
	mgr := state.activeScene.manager
	inst := e.Node_ComponentRoot(mgr, node)
	if inst == nil || inst.componentMissing do return false
	path := strings.clone(e.Node_UidPathBelow(mgr, node, inst), context.temp_allocator)
	rel := strings.clone(inst.componentPath, context.temp_allocator)
	if !Editor_OpenComponent(state, rel) do return false
	root := Editor_ComponentDocRoot(state, state.activeScene)
	target := e.Node_FindByUidPath(state.activeScene.manager, root, path) if path != "" else nil
	Editor_SelectNode(state, target if target != nil else root)
	return true
}

// Editor_SelectAllInstances selects every instance of a component file in
// the active scene (nested ones too). Returns how many.
Editor_SelectAllInstances :: proc(state: ^EditorState, rel: string) -> int {
	if state.activeScene == nil do return 0
	Editor_SelectNode(state, nil)
	n := 0
	for node in state.activeScene.manager.nodes {
		if node == nil || node.componentPath != rel || !e.Node_IsAlive(node) do continue
		Editor_SelectNode(state, node, additive = true)
		n += 1
	}
	Editor_Log(state, .Info, "Selected %d instance(s) of %s", n, rel)
	return n
}

// Editor_ComponentInstanceCount: how many instances of a component file the
// open documents hold (nested ones too), counted a few times a second.
Editor_ComponentInstanceCount :: proc(state: ^EditorState, rel: string) -> int {
	@(static) counts: map[string]int
	@(static) counted: i32 = -1000
	now := imgui.GetFrameCount()
	if now - counted > 20 || now < counted {
		counted = now
		for k in counts do delete(k)
		clear(&counts)
		for _, s in state.game.sceneManager.scenes {
			if s == nil || !s.isLoaded || s.manager == nil do continue
			for n in s.manager.nodes {
				if n == nil || n.componentPath == "" do continue
				if n.componentPath in counts do counts[n.componentPath] += 1
				else do counts[strings.clone(n.componentPath)] = 1
			}
		}
	}
	return counts[rel]
}
