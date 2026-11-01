package editor

import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Top Toolbar Subsystem: Pure Icon Buttons with Rich Hover Tooltips
// ============================================================================

Toolbar_Render :: proc(state: ^EditorState, width, height, posY: f32) {
	imgui.SetNextWindowPos(imgui.Vec2{0, posY})
	imgui.SetNextWindowSize(imgui.Vec2{width, height})
	flags: imgui.WindowFlags = {.NoTitleBar, .NoResize, .NoMove, .NoScrollbar, .NoSavedSettings, .NoDocking, .NoScrollWithMouse}

	imgui.PushStyleVarImVec2(.WindowPadding, {10, (height - 30) * 0.5})
	imgui.PushStyleVarImVec2(.ItemSpacing, {2, 0})
	imgui.PushStyleColorImVec4(.WindowBg, UI_BG_APP)
	defer {
		imgui.PopStyleColor()
		imgui.PopStyleVar(2)
	}
	defer imgui.End()
	if !imgui.Begin("Toolbar###FixedToolbarWindow", nil, flags) do return
	Drive_Window("toolbar") // (annotated docs screenshots)
	// The Level tab has its own tools (Play stays).
	if LevelEditor_Active() {
		LevelEditor_Toolbar(state, width, Toolbar_PlayControls)
		return
	}

	// 1. Breadcrumb: project › scene
	imgui.PushStyleColorImVec4(.Button, {0, 0, 0, 0})
	imgui.PushStyleColorImVec4(.ButtonHovered, UI_BG_HOVER)
	imgui.PushStyleVarImVec2(.FramePadding, {8, 6})
	projName := state.projectConfig.name if state.projectConfig.name != "" else filepath.base(state.projectPath)
	imgui.PushFont(GlobalFonts.semibold)
	if imgui.Button(fmt.ctprintf("%s  %s##crumb_project", ICON_FA_FOLDER, projName)) do ProjectSettingsDialog_Open(state)
	imgui.PopFont()
	Drive_Item("toolbar.project")
	UI_Tooltip(fmt.tprintf("%s - click for project settings", state.projectPath))
	imgui.SameLine(0, 0)
	imgui.AlignTextToFramePadding()
	UI_DimText("/")
	imgui.SameLine(0, 0)
	sceneLabel := Asset_DisplayName(state.activeScenePath) if state.activeScenePath != "" else "untitled"
	modified := Editor_ModifiedSceneCountCached(state) > 0
	imgui.Button(fmt.ctprintf("%s%s##crumb_scene", sceneLabel, "  " + ICON_FA_CIRCLE if modified else ""))
	Drive_Item("toolbar.scene")
	UI_Tooltip("Unsaved changes" if modified else "Active scene")
	imgui.PopStyleVar()
	imgui.PopStyleColor(2)

	UI_VerticalDivider()

	// 2. Tools
	tool :: proc(state: ^EditorState, mode: ToolMode, icon, id, tip: string) {
		if UI_IconButton(icon, id, tip, state.toolMode == mode) do state.toolMode = mode
		imgui.SameLine()
	}
	tool(state, .Select, ICON_FA_ARROW_POINTER, "toolbar.select", "Select (Q)")
	tool(state, .Translate, ICON_FA_ARROWS_UP_DOWN_LEFT_RIGHT, "toolbar.move", "Move (W)")
	tool(state, .Rotate, ICON_FA_ROTATE, "toolbar.rotate", "Rotate (E)")
	tool(state, .Scale, ICON_FA_EXPAND, "toolbar.scale", "Scale (R)")
	tool(state, .Pan, ICON_FA_HAND, "toolbar.pan", "Pan (T, or middle mouse)")

	UI_VerticalDivider()
	canUndo := len(state.undoStack) > 0
	canRedo := len(state.redoStack) > 0
	if !canUndo do imgui.BeginDisabled(true)
	if UI_IconButton(ICON_FA_ROTATE_LEFT, "toolbar.undo", "Undo (Ctrl+Z)") do Editor_Undo(state)
	if !canUndo do imgui.EndDisabled()
	imgui.SameLine()
	if !canRedo do imgui.BeginDisabled(true)
	if UI_IconButton(ICON_FA_ROTATE_RIGHT, "toolbar.redo", "Redo (Ctrl+Shift+Z)") do Editor_Redo(state)
	if !canRedo do imgui.EndDisabled()

	Toolbar_PlayControls(state, width)
	rightW := TOOLBAR_RIGHT_W

	// 4. View toggles and file actions, right-aligned.
	imgui.SameLine()
	// (At a fixed place - it doesn't move with the Play group's width; only
	// a window too narrow for both pushes it.)
	imgui.SetCursorPosX(max(imgui.GetCursorPosX() + UI_SPACE, width - rightW - 10))
	toggle :: proc(v: ^bool, icon, id, tip: string) {
		if UI_IconButton(icon, id, tip, v^) do v^ = !v^
		imgui.SameLine()
	}
	toggle(&state.snapGrid, ICON_FA_MAGNET, "toolbar.snap", "Snap to grid")
	imgui.SetNextItemWidth(56)
	imgui.PushStyleVarImVec2(.FramePadding, {6, 6})
	imgui.DragFloat("##GridStep", &state.gridSize, 1.0, 4.0, 256.0, "%.0f px")
	imgui.PopStyleVar()
	Drive_Item("toolbar.grid-size")
	UI_Tooltip("Grid size")
	imgui.SameLine()
	toggle(&state.showGrid, ICON_FA_BORDER_ALL, "toolbar.grid", "Show grid")
	toggle(&state.showBounds, ICON_FA_EYE, "toolbar.bounds", "Show bounds & colliders")
	toggle(&state.showCameraBounds, ICON_FA_VIDEO, "toolbar.camera", "Show camera frames")
	Toolbar_PreviewShape(state) // (Expand: the screen shape shown, #202)
	toggle(&viewportLighting, ICON_FA_SUN, "toolbar.lighting", "Preview lighting (lights, the scene's ambient) and post effects")
	UI_VerticalDivider()
	if UI_IconButton(ICON_FA_EXPAND, "toolbar.fit", "Fit the scene to the view (Home)") do Viewport_FitScene(state)
	imgui.SameLine()
	imgui.SetNextItemWidth(76)
	imgui.PushStyleVarImVec2(.FramePadding, {6, 7})
	if imgui.BeginCombo("##zoom", fmt.ctprintf("%.0f%%", state.cameraZoom * 100)) {
		for z in ([]f32{0.25, 0.5, 1, 2, 4}) {
			if imgui.Selectable(fmt.ctprintf("%.0f%%", z * 100), abs(state.cameraZoom - z) < 0.001) do state.cameraZoom = z
			Drive_Item(fmt.tprintf("pick:%.0f%%", z * 100))
		}
		imgui.Separator()
		if imgui.Selectable("Fit Scene") do Viewport_FitScene(state)
		Drive_Item("pick:Fit Scene")
		if imgui.Selectable("Fit Game View") do Viewport_FitGameView(state)
		Drive_Item("pick:Fit Game View")
		if imgui.Selectable("Fit Selection") do Viewport_FitSelection(state)
		Drive_Item("pick:Fit Selection")
		imgui.EndCombo()
	}
	imgui.PopStyleVar()
	Drive_Item("toolbar.zoom")
	UI_Tooltip("Zoom")
	imgui.SameLine()
	UI_VerticalDivider()
	if UI_IconButton(ICON_FA_FLOPPY_DISK, "toolbar.save", "Save scene (Ctrl+S)", tint = UI_WARNING if modified else {}) do Toolbar_SaveScene(state)
	imgui.SameLine()
	if UI_IconButton(ICON_FA_BOX_ARCHIVE, "toolbar.export", "Export .rayzr package") do Toolbar_ExportRayzr(state)
	imgui.SameLine()
	if UI_IconButton(ICON_FA_GEAR, "toolbar.settings", "Project settings") do ProjectSettingsDialog_Open(state)
}

// Toolbar_PlayControls: Play / Play Scene, or Pause / Step / Restart / Stop
// while the game runs (shared by the Game and Level toolbars).
// The right-aligned group's width (the Play group never reaches into it).
TOOLBAR_RIGHT_W :: f32(7 * 32 + 64 + 3 * 18 + 32 + 80)

Toolbar_PlayControls :: proc(state: ^EditorState, width: f32) {
	rightLimit := width - TOOLBAR_RIGHT_W - 10 - UI_SPACE * 3
	// 3. Play controls, centred (but never over the tools on the left):
	// Play / Play Scene; while the game runs Pause (Resume), Step, Restart
	// and Stop; while building, Stop cancels the build.
	// (Centred on its width last frame, ending before the right-aligned
	// group, which stays put when the game starts and stops.)
	@(static) playW: f32 = 6 * 32 + 110
	imgui.SameLine()
	x := min((width - playW) * 0.5, rightLimit - playW)
	imgui.SetCursorPosX(max(imgui.GetCursorPosX() + UI_SPACE * 3, x))
	startX := imgui.GetCursorPosX()
	defer {
		imgui.SameLine(0, 0)
		playW = imgui.GetCursorPosX() - startX
	}
	switch {
	case state.buildRunning:
		if UI_IconButton(ICON_FA_STOP, "toolbar.stop", "Cancel the build", tint = UI_DANGER) do _ = os.process_kill(state.buildProcess)
	case state.gameProcessRunning:
		linked := RemoteGame_Connected() && !Debug_IsStopped()
		paused := RemoteGame_Paused()
		if !linked do imgui.BeginDisabled(true)
		if paused {
			if UI_IconButton(ICON_FA_PLAY, "toolbar.pause", "Resume (F9)", true, tint = UI_SUCCESS) do Editor_TogglePause(state)
		} else {
			if UI_IconButton(ICON_FA_PAUSE, "toolbar.pause", "Pause (F9)") do Editor_TogglePause(state)
		}
		imgui.SameLine()
		if UI_IconButton(ICON_FA_FORWARD_STEP, "toolbar.step", "Step one frame (Shift+F9) - pauses the game") do Editor_StepGame(state)
		if !linked do imgui.EndDisabled()
		imgui.SameLine()
		if UI_IconButton(ICON_FA_ROTATE_RIGHT, "toolbar.restart", "Restart (Cmd+Shift+F5) - saves, rebuilds if needed, plays the same again") do Editor_RestartGame(state)
		imgui.SameLine()
		if UI_IconButton(ICON_FA_STOP, "toolbar.stop", "Stop (Shift+F5)", tint = UI_DANGER) do Editor_StopGameProcess(state)
		imgui.SameLine()
		Toolbar_RecordButton(state) // input for a test to replay (tests_panel.odin)
	case:
		if UI_IconButton(ICON_FA_PLAY, "toolbar.play", "Play project (F5) - saves changes, rebuilds if code changed", tint = UI_SUCCESS) {
			Editor_PlayGameProcess(state, .Project)
		}
		imgui.SameLine()
		if UI_IconButton(ICON_FA_CIRCLE_PLAY, "toolbar.play-scene", "Play this scene (F6)", tint = UI_SUCCESS) {
			Editor_PlayGameProcess(state, .CurrentScene)
		}
	}
	// Show Colliders in the game (Project Settings > Physics); also switches
	// a running game.
	if !state.buildRunning {
		imgui.SameLine()
		colliders := state.projectConfig.debugDraw
		if UI_IconButton(ICON_FA_VECTOR_SQUARE, "toolbar.colliders", "Colliders are drawn in the game - click to hide them" if colliders else "Colliders are hidden in the game - click to show them", colliders) {
			Editor_ToggleGameColliders(state)
		}
	}
	imgui.SameLine(0, UI_SPACE)
	imgui.AlignTextToFramePadding()
	switch {
	case state.buildRunning:
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextUnformatted(fmt.ctprintf("%s  Building...", ICON_FA_HAMMER))
		imgui.PopStyleColor()
	// (While the game runs: an icon, its word in the tooltip - the controls
	// with Record leave no room for words before the right-aligned group.)
	case state.gameProcessRunning && Debug_IsStopped():
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextUnformatted(ICON_FA_PAUSE)
		imgui.PopStyleColor()
		UI_Tooltip("Stopped at a breakpoint")
	case state.gameProcessRunning && RemoteGame_Paused():
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextUnformatted(ICON_FA_PAUSE)
		imgui.PopStyleColor()
		UI_Tooltip("Paused")
	case state.gameProcessRunning:
		imgui.PushStyleColorImVec4(.Text, UI_SUCCESS)
		imgui.TextUnformatted(ICON_FA_CIRCLE)
		imgui.PopStyleColor()
		UI_Tooltip("Running")
	}
	Drive_Item("toolbar.status")

}

Toolbar_StartSimulation :: proc(state: ^EditorState) {
	CodeRuntime_Clear() // the last run's script problems
	if state.activeScene == nil do return

	if state.snapshotJson != "" {
		delete(state.snapshotJson)
	}
	OscPreview_Stop() // (its targets back first)
	state.snapshotJson = e.Scene_SerializeToJSON(state.activeScene)
	// Scripts run in the editor's Lua state: remember its globals so Stop
	// can put them back (and reset module-level locals).
	e.ScriptManager_SnapshotGlobals(&state.game.scriptManager)
	// Edit-mode scenes never ran ready(); start them like the game would.
	state.game.scriptManager.suspended = false
	e.Globals_Ready(&state.game.scriptManager) // global scripts start first
	StateGraph_SimulationStarted(state) // break on enter (state_machine_graph.odin)
	e.Scene_CallReady(state.activeScene, state.activeScene.rootNode, &state.game.gameContext)

	state.isSimulating = true
	state.isPaused = false
	Editor_Log(state, .Info, "Simulation started. Scene snapshot saved.")
}

Toolbar_StopSimulation :: proc(state: ^EditorState) {
	if !state.isSimulating do return

	state.isSimulating = false
	state.isPaused = false
	state.game.scriptManager.suspended = true

	// Rebuild the same scene object from the snapshot (it keeps its file and
	// registry entry, so saving still goes to the right place).
	if state.activeScene != nil && state.snapshotJson != "" {
		scene := state.activeScene
		e.Scene_Unload(scene, &state.game.gameContext)
		e.ScriptManager_RestoreGlobals(&state.game.scriptManager)
		e.Scene_InstantiateFromJSON(scene, transmute([]u8)state.snapshotJson, &state.game.gameContext)
		e.ProcessNodeQueues(scene.manager, &state.game.gameContext)
		scene.isLoaded = true
		state.selectedNode = nil
		Editor_Log(state, .Info, "Simulation stopped. Scene restored to pre-simulation snapshot.")
	}
}

Toolbar_NewScene :: proc(state: ^EditorState) {
	if state.game == nil do return
	Editor_NewScene(state)
}

Toolbar_SaveScene :: proc(state: ^EditorState) {
	Lua_MarkProjectTypesDirty() // generated Lua types follow the project
	if state.activeScene == nil do return
	Editor_SaveSceneDocument(state, state.activeScene)
}

// Editor_RayzrPath: exports go next to the project folder (<dir>.rayzr).
Editor_RayzrPath :: proc(state: ^EditorState) -> string {
	clean := strings.trim_suffix(state.projectPath, "/")
	return strings.concatenate({clean, ".rayzr"}, context.temp_allocator)
}

// Toolbar_ExportRayzr asks for a folder (opening in the one used last, else
// next to the project) and writes <project>.rayzr there.
Toolbar_ExportRayzr :: proc(state: ^EditorState) {
	if GlobalDrive.enabled && len(driveDialogAnswers) == 0 {
		export_rayzr_to(state, filepath.dir(Editor_RayzrPath(state), context.temp_allocator)) // drives: next to the project
		return
	}
	start := Editor_StartDir(.Export, filepath.dir(Editor_RayzrPath(state), context.temp_allocator))
	NativeDialog_Open(state, {title = "Export .rayzr Package To", folders = true, start = start}, proc(state: ^EditorState, paths: []string) {
		Editor_RememberDir(.Export, paths[0], true)
		export_rayzr_to(state, paths[0])
	})
}

@(private = "file")
export_rayzr_to :: proc(state: ^EditorState, dir: string) {
	Editor_SaveAllScenes(state)
	defer Editor_InvalidateProjectFiles() // a package next to the project shows in Assets
	outPath, _ := filepath.join({dir, filepath.base(Editor_RayzrPath(state))}, context.temp_allocator)
	overrides := make(map[string][]u8, context.temp_allocator)
	e.Asset_ExportOverrides(state.projectPath, &overrides, allocator = context.temp_allocator) // (import settings: QOI)
	sprites, pages := e.Atlas_Build(state.projectPath, &overrides, allocator = context.temp_allocator) // (and sprite atlases)
	if sprites > 0 do Editor_Log(state, .Info, "%d texture(s) packed into %d atlas page(s)", sprites, pages)
	ok := e.RayzrPackage_CreateFromDirectory(state.projectPath, outPath, true, overrides = overrides)
	if ok {
		Editor_Log(state, .Info, "Exported portable .rayzr archive: %s", outPath)
	} else {
		Editor_Log(state, .Error, "Failed to export .rayzr package: %s", outPath)
	}
}
