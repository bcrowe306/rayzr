package editor

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Scene tabs: every scene (and component document) you open gets a tab
// above the viewport - click to switch, drag to reorder, the dot marks
// unsaved changes, x / middle-click / Cmd+W closes (asking to save first),
// Ctrl+Tab / Ctrl+Shift+Tab cycle. Each tab keeps its own camera (sceneViews),
// undo history (entries are per scene) and selection. A closed scene is
// unloaded (its undo entries freed); the open tabs and the active one come
// back when the project opens (<project>/.rayzr/open_scenes.json).
// ============================================================================

@(private = "file")
tabs: struct {
	open:       [dynamic]^e.Scene,
	selection:  map[^e.Scene]string, // child-index path of the selected node when it was left
	lastActive: ^e.Scene,
	closing:    ^e.Scene,            // waiting for the save prompt
	restored:   bool,
}

SCENE_TABS_FILE :: ".rayzr/open_scenes.json"

// SceneTabs_Open: the open documents in tab order.
SceneTabs_Open :: proc() -> []^e.Scene {return tabs.open[:]}

// scene_tabs_track keeps the list in step with the active document (opened
// from Assets, the palette, ...) and remembers selections across switches.
@(private = "file")
scene_tabs_track :: proc(state: ^EditorState) {
	// Documents that went away (scene unloaded elsewhere).
	for i := len(tabs.open) - 1; i >= 0; i -= 1 {
		s := tabs.open[i]
		if !s.isLoaded do ordered_remove(&tabs.open, i)
	}
	active := state.activeScene
	if active == nil do return
	found := false
	for s in tabs.open do if s == active {found = true; break}
	if !found && active.isLoaded && active.filePath != "" {
		append(&tabs.open, active)
		SceneTabs_Save(state)
	}
}

// SceneTabs_RememberSelection keeps the active document's selection (it is
// being left).
SceneTabs_RememberSelection :: proc(state: ^EditorState) {
	if state.activeScene == nil do return
	if old, ok := tabs.selection[state.activeScene]; ok do delete(old)
	tabs.selection[state.activeScene] = Editor_NodePath(state, state.selectedNode) // (heap: owned here)
}

// SceneTabs_SelectionFor: the node selected in a document when it was left
// (nil if none) - the document must be the active one.
SceneTabs_SelectionFor :: proc(state: ^EditorState, scene: ^e.Scene) -> ^e.Node {
	if path, ok := tabs.selection[scene]; ok && path != "" do return Editor_NodeAtPath(state, path)
	return nil
}

// SceneTabs_Activate switches to an open document, keeping the selection
// of the one left.
SceneTabs_Activate :: proc(state: ^EditorState, scene: ^e.Scene) {
	if scene == nil || scene == state.activeScene do return
	if state.isSimulating {
		Editor_Log(state, .Warn, "Stop simulating to switch scenes")
		return
	}
	if Editor_IsComponentDoc(state, scene) do Editor_OpenComponent(state, scene.filePath)
	else do Editor_OpenScene(state, scene.filePath)
	if path, ok := tabs.selection[scene]; ok do state.selectedNode = Editor_NodeAtPath(state, path)
	// (lastActive stays: next frame the tab bar sees the switch and selects the tab)
}

// SceneTabs_Cycle moves to the next (+1) / previous (-1) tab.
SceneTabs_Cycle :: proc(state: ^EditorState, dir: int) {
	n := len(tabs.open)
	if n < 2 do return
	cur := 0
	for s, i in tabs.open do if s == state.activeScene do cur = i
	SceneTabs_Activate(state, tabs.open[(cur + dir + n) % n])
}

// SceneTabs_RequestClose closes a tab, asking to save unsaved changes first.
SceneTabs_RequestClose :: proc(state: ^EditorState, scene: ^e.Scene) {
	if scene == nil || len(tabs.open) < 2 do return
	if state.isSimulating {
		Editor_Log(state, .Warn, "Stop simulating to close scenes")
		return
	}
	if Editor_SceneIsModified(state, scene) && scene.filePath != "" {
		tabs.closing = scene
		return
	}
	scene_tabs_close(state, scene)
}

// scene_tabs_close unloads a document and drops everything kept for it.
@(private = "file")
scene_tabs_close :: proc(state: ^EditorState, scene: ^e.Scene) {
	idx := -1
	for s, i in tabs.open do if s == scene do idx = i
	if idx < 0 do return
	if scene == state.activeScene {
		// Its neighbour first (the one after, else before).
		next := tabs.open[idx + 1] if idx + 1 < len(tabs.open) else tabs.open[idx - 1]
		SceneTabs_Activate(state, next)
	}
	ordered_remove(&tabs.open, idx)
	// Its undo / redo entries. A step that also wrote a file (Apply to
	// Component) keeps undoing the file.
	for stack in ([]^[dynamic]Undo_Entry{&state.undoStack, &state.redoStack}) {
		for i := len(stack) - 1; i >= 0; i -= 1 {
			if stack[i].scene != scene do continue
			if stack[i].file != "" {
				Undo_Release(stack[i].json)
				stack[i].json = nil
				stack[i].kind = .File
				stack[i].scene = nil
				continue
			}
			Undo_EntryDestroy(&stack[i])
			ordered_remove(stack, i)
		}
	}
	name := scene.filePath
	delete_key(&state.sceneViews, scene)
	delete_key(&state.sceneVersion, scene)
	delete_key(&state.savedVersion, scene)
	if b, ok := state.sceneBaselines[scene]; ok {
		delete(b)
		delete_key(&state.sceneBaselines, scene)
	}
	delete_key(&state.componentDocs, scene)
	if p, ok := tabs.selection[scene]; ok {
		delete(p)
		delete_key(&tabs.selection, scene)
	}
	e.Scene_Unload(scene, &state.game.gameContext) // (reopening loads the file again)
	Editor_Log(state, .Info, "Closed %s", name)
	SceneTabs_Save(state)
}

// SceneTabs_Draw draws the tab bar at the top of the viewport window (and
// the save prompt of a tab being closed).
SceneTabs_Draw :: proc(state: ^EditorState) {
	scene_tabs_track(state)
	if len(tabs.open) == 0 && ImagePreview_Count() == 0 do return
	switched := state.activeScene != tabs.lastActive
	flags: imgui.TabBarFlags = {.Reorderable, .FittingPolicyScroll, .TabListPopupButton}
	if imgui.BeginTabBar("##scene_tabs", flags) {
		closeReq: ^e.Scene
		pick: ^e.Scene
		sceneShown := false
		for s in tabs.open {
			label := scene_tab_label(state, s)
			tf: imgui.TabItemFlags
			if Editor_SceneIsModified(state, s) do tf += {.UnsavedDocument}
			if switched && s == state.activeScene do tf += {.SetSelected}
			open := true
			canClose := len(tabs.open) > 1
			visible := imgui.BeginTabItem(fmt.ctprintf("%s###scenetab_%p", label, s), &open if canClose else nil, tf)
			Drive_Item(fmt.tprintf("scenetab:%s", s.filePath))
			if imgui.IsItemHovered() {
				imgui.SetTooltip(fmt.ctprintf("%s%s", s.filePath, " (unsaved changes)" if Editor_SceneIsModified(state, s) else ""))
				if imgui.IsMouseClicked(.Middle) do closeReq = s
			}
			if imgui.BeginPopupContextItem(fmt.ctprintf("##scenetab_ctx_%p", s)) {
				if imgui.MenuItem("Close", CMD + "+W", false, canClose) do closeReq = s
				Drive_Item("ctx:scenetab-close")
				if imgui.MenuItem("Close Others", nil, false, canClose) {
					for o in tabs.open do if o != s && !Editor_SceneIsModified(state, o) do defer_close(o)
				}
				Drive_Item("ctx:scenetab-close-others")
				imgui.Separator()
				if imgui.MenuItem("Copy Path") do imgui.SetClipboardText(fmt.ctprintf("%s", s.filePath))
				imgui.EndPopup()
			}
			if visible {
				sceneShown = true
				if !switched && s != state.activeScene do pick = s
				imgui.EndTabItem()
			}
			if !open do closeReq = s
		}
		// Image previews (#399): their tabs after the scenes'.
		ImagePreview_TabItems(state, sceneShown, switched)
		imgui.EndTabBar()
		ImagePreview_EndFrame()
		if pick != nil do SceneTabs_Activate(state, pick)
		if closeReq != nil do SceneTabs_RequestClose(state, closeReq)
	}
	if switched do SceneTabs_Save(state) // (the active tab is remembered too)
	tabs.lastActive = state.activeScene
	// "Close Others" (unsaved ones stay open).
	for len(pendingClose) > 0 {
		s := pop(&pendingClose)
		scene_tabs_close(state, s)
	}
	scene_tabs_prompt(state)
}

@(private = "file")
pendingClose: [dynamic]^e.Scene

@(private = "file")
defer_close :: proc(s: ^e.Scene) {append(&pendingClose, s)}

@(private = "file")
scene_tab_label :: proc(state: ^EditorState, s: ^e.Scene) -> string {
	base := filepath.base(s.filePath)
	base = strings.trim_suffix(strings.trim_suffix(base, ".json"), ".scene")
	base = strings.trim_suffix(base, ".component")
	base = strings.trim_suffix(base, ".node")
	icon := ICON_FA_PUZZLE_PIECE if Editor_IsCustomNodeDoc(state, s) else ICON_FA_CUBES if Editor_IsComponentDoc(state, s) else ICON_FA_FILM
	return fmt.tprintf("%s  %s", icon, base)
}

// scene_tabs_prompt: Save / Don't Save / Cancel for a tab with unsaved changes.
@(private = "file")
scene_tabs_prompt :: proc(state: ^EditorState) {
	if tabs.closing == nil do return
	imgui.OpenPopup("Unsaved Changes###SceneTabClose")
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, {}, {0.5, 0.5})
	if !imgui.BeginPopupModal("Unsaved Changes###SceneTabClose", nil, {.NoResize, .AlwaysAutoResize, .NoTitleBar}) do return
	defer imgui.EndPopup()
	s := tabs.closing
	UI_PanelTitle(ICON_FA_TRIANGLE_EXCLAMATION, fmt.tprintf("Save changes to %s?", filepath.base(s.filePath)))
	imgui.Dummy({0, 4})
	imgui.TextUnformatted("Your changes are lost if you don't save them.")
	imgui.Dummy({0, 8})
	done := false
	if UI_PrimaryButton("Save", "scenetab.save") {
		if Editor_SaveSceneDocument(state, s) do scene_tabs_close(state, s)
		done = true
	}
	imgui.SameLine()
	if UI_Button("Don't Save", "scenetab.discard") {
		scene_tabs_close(state, s)
		done = true
	}
	imgui.SameLine()
	if UI_Button("Cancel", "scenetab.cancel") || imgui.IsKeyPressed(.Escape) do done = true
	if done {
		tabs.closing = nil
		imgui.CloseCurrentPopup()
	}
}

// --- remembered tabs ---------------------------------------------------------------------

// SceneTabs_Save writes the open tabs (scene files; component documents
// aren't reopened) and the active one.
SceneTabs_Save :: proc(state: ^EditorState) {
	if state.projectPath == "" || !tabs.restored do return
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "{\"open\": [")
	n := 0
	for s in tabs.open {
		if Editor_IsComponentDoc(state, s) do continue
		fmt.sbprintf(&sb, "%s%q", ", " if n > 0 else "", s.filePath)
		n += 1
	}
	active := state.activeScene.filePath if state.activeScene != nil && !Editor_IsComponentDoc(state, state.activeScene) else ""
	fmt.sbprintf(&sb, "], \"active\": %q}}\n", active)
	path, _ := filepath.join({state.projectPath, SCENE_TABS_FILE}, context.temp_allocator)
	_ = os.make_directory_all(filepath.dir(path, context.temp_allocator))
	_ = os.write_entire_file(path, transmute([]u8)strings.to_string(sb))
}

// SceneTabs_Restore reopens the tabs of the last session (after the
// project's first scene opened); missing files are skipped.
SceneTabs_Restore :: proc(state: ^EditorState) {
	tabs.restored = true
	path, _ := filepath.join({state.projectPath, SCENE_TABS_FILE}, context.temp_allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil do return
	v, perr := json.parse(data, allocator = context.temp_allocator)
	if perr != nil do return
	o, ok := v.(json.Object)
	if !ok do return
	first := state.activeScene
	if arr, isArr := o["open"].(json.Array); isArr {
		for item in arr {
			rel, isStr := item.(json.String)
			if !isStr do continue
			disk, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
			if !os.is_file(disk) do continue
			if Editor_OpenScene(state, rel) do scene_tabs_track(state)
		}
	}
	want := first
	if a, isStr := o["active"].(json.String); isStr && a != "" {
		if s := e.Game_FindSceneByFile(state.game, a); s != nil && s.isLoaded do want = s
	}
	if want != nil && want != state.activeScene do Editor_OpenScene(state, want.filePath)
	tabs.lastActive = nil
	state.selectedNode = nil
}

// SceneTabs_Shutdown frees the tab list (editor exit).
SceneTabs_Shutdown :: proc(state: ^EditorState) {
	SceneTabs_Save(state)
	delete(tabs.open)
	for _, p in tabs.selection do delete(p)
	delete(tabs.selection)
	delete(pendingClose)
	tabs = {}
	pendingClose = nil
}
