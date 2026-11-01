package editor

import "core:c"
import "core:fmt"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Editor actions: every command with its default shortcut(s), in one table.
//
// The same table drives keyboard dispatch (Actions_Dispatch), the menus
// (labels + shortcut text), the command palette (palette.odin) and the
// Keyboard Shortcuts window, so a shortcut shown anywhere always works.
// Code-editor bindings follow Zed's defaults (macOS: Cmd = "Primary").
// ============================================================================

Mod :: enum {
	Primary, // Cmd on macOS, Ctrl elsewhere
	Shift,
	Alt,
	Ctrl, // the physical Control key (distinct from Primary on macOS)
}
Mods :: bit_set[Mod]

Chord :: struct {
	key:  imgui.Key,
	mods: Mods,
}

Action_Scope :: enum {
	Global, // always (unless a text field is being edited)
	Scene,  // scene editing: viewport / tree / inspector, not while typing code
	Code,   // the code editor has focus
}

Editor_Action :: struct {
	id:       string,
	category: string,
	label:    string,
	chords:   [3]Chord,
	scope:    Action_Scope,
	run:      proc(state: ^EditorState),
	enabled:  proc(state: ^EditorState) -> bool, // nil = always
	checked:  proc(state: ^EditorState) -> bool, // nil = not a toggle
	repeat:   bool, // fires on key repeat
	// A plugin's command (plugin_api.odin): its Lua callbacks as registry
	// references (NOREF: none), and where it goes in the menus ("Tools/Align").
	plugin:     ^Plugin,
	menu:       string,
	refRun:     c.int,
	refEnabled: c.int,
	refChecked: c.int,
}

P :: Mods{.Primary}
PS :: Mods{.Primary, .Shift}
PA :: Mods{.Primary, .Alt}
CT :: Mods{.Ctrl}
// Expand / shrink selection: Ctrl+Shift+Right / Left on macOS (Zed), Alt+Shift
// elsewhere (Ctrl+Shift+arrows select words there).
EXPAND_MODS :: Mods{.Ctrl, .Shift} when ODIN_OS == .Darwin else Mods{.Alt, .Shift}
SH :: Mods{.Shift}
AL :: Mods{.Alt}

@(private = "file")
ch :: proc(key: imgui.Key, mods: Mods = {}) -> Chord {
	return {key, mods}
}

@(private = "file")
k :: proc(cs: ..Chord) -> (out: [3]Chord) {
	for c, i in cs do if i < 3 do out[i] = c
	return
}

@(private = "file")
has_scene :: proc(s: ^EditorState) -> bool {return s.activeScene != nil}
@(private = "file")
can_modify :: proc(s: ^EditorState) -> bool {
	return s.activeScene != nil && s.selectedNode != nil && s.selectedNode != s.activeScene.rootNode
}
@(private = "file")
has_selection :: proc(s: ^EditorState) -> bool {return s.selectedNode != nil}
@(private = "file")
has_code :: proc(s: ^EditorState) -> bool {return len(GlobalCode.docs) > 0}

GlobalActions: [dynamic]Editor_Action
@(private = "file")
recentActions: [dynamic]string

@(private = "file")
add :: proc(a: Editor_Action) {
	append(&GlobalActions, a)
}

// Actions_Init fills the action table (once).
Actions_Init :: proc() {
	if len(GlobalActions) > 0 do return
	// --- Global ---
	add({id = "palette.commands", category = "View", label = "Command Palette", chords = k(ch(.P, PS), ch(.F1)), scope = .Global, run = proc(s: ^EditorState) {Palette_Open(.Commands)}})
	add({id = "palette.files", category = "View", label = "Go to File", chords = k(ch(.P, P)), scope = .Global, run = proc(s: ^EditorState) {Palette_Open(.Files)}})
	add({id = "file.save", category = "File", label = "Save", chords = k(ch(.S, P)), scope = .Global, run = proc(s: ^EditorState) {
		if LevelEditor_Active() do LevelEditor_Save(s) // the Level tab saves its .ldtk
		else do Editor_SaveActive(s)
	}})
	add({id = "file.save_as", category = "File", label = "Save As...", chords = k(ch(.S, PS)), scope = .Global, run = Editor_SaveAsActive})
	add({id = "file.revert", category = "File", label = "Revert Scene", scope = .Global, run = Editor_RevertScene, enabled = proc(s: ^EditorState) -> bool {return s.activeScene != nil && Editor_SceneIsModified(s, s.activeScene)}})
	add({id = "file.new_project", category = "File", label = "New Project...", scope = .Global, run = proc(s: ^EditorState) {Prompt_Open(.NewProject, "../my_game")}})
	add({id = "file.open_project", category = "File", label = "Open Project...", chords = k(ch(.O, PS)), scope = .Global, run = Editor_OpenProjectDialog})
	add({id = "file.save_all", category = "File", label = "Save All (Scenes and Scripts)", chords = k(ch(.S, PA)), scope = .Global, run = proc(s: ^EditorState) {
		n := Editor_SaveAllScenes(s)
		m := Code_SaveAll(s)
		Editor_Log(s, .Info, "Saved %d scene(s) and %d script(s)", n, m)
	}})
	add({id = "file.settings", category = "File", label = "Settings...", chords = k(ch(.Comma, P)), scope = .Global, run = proc(s: ^EditorState) {Settings_Open(s, .General)}})
	add({id = "file.project_settings", category = "File", label = "Project Settings...", scope = .Global, run = ProjectSettingsDialog_Open})
	add({id = "file.export", category = "File", label = "Export .rayzr Package...", scope = .Global, run = Toolbar_ExportRayzr})
	add({id = "file.open_web_export", category = "File", label = "Open Web Export in Browser", scope = .Global, run = Editor_OpenWebExport, enabled = proc(s: ^EditorState) -> bool {return s.webExportDir != ""}})
	add({id = "file.export_standalone", category = "File", label = "Export Standalone Game...", scope = .Global, run = proc(s: ^EditorState) {Editor_ExportStandalone(s)}, enabled = proc(s: ^EditorState) -> bool {return !s.buildRunning}})
	add({id = "file.quit", category = "File", label = "Quit", chords = k(ch(.Q, P)), scope = .Global, run = proc(s: ^EditorState) {Editor_RequestQuit(s)}})
	add({id = "game.play", category = "Game", label = "Play Project", chords = k(ch(.F5)), scope = .Global, run = proc(s: ^EditorState) {Editor_PlayGameProcess(s, .Project)}, enabled = proc(s: ^EditorState) -> bool {return !s.gameProcessRunning && !s.buildRunning}})
	add({id = "game.play_scene", category = "Game", label = "Play Current Scene", chords = k(ch(.F6)), scope = .Global, run = proc(s: ^EditorState) {Editor_PlayGameProcess(s, .CurrentScene)}, enabled = proc(s: ^EditorState) -> bool {return !s.gameProcessRunning && !s.buildRunning}})
	add({id = "game.stop", category = "Game", label = "Stop Game", chords = k(ch(.F5, SH)), scope = .Global, run = Editor_StopGameProcess, enabled = proc(s: ^EditorState) -> bool {return s.gameProcessRunning}})
	add({id = "game.pause", category = "Game", label = "Pause Game", chords = k(ch(.F9)), scope = .Global, run = Editor_TogglePause, enabled = proc(s: ^EditorState) -> bool {return s.gameProcessRunning && RemoteGame_Connected() && !Debug_IsStopped()}, checked = proc(s: ^EditorState) -> bool {return s.gameProcessRunning && RemoteGame_Paused()}})
	add({id = "game.step", category = "Game", label = "Step One Frame", chords = k(ch(.F9, SH)), scope = .Global, run = Editor_StepGame, enabled = proc(s: ^EditorState) -> bool {return s.gameProcessRunning && RemoteGame_Connected() && !Debug_IsStopped()}})
	add({id = "game.restart", category = "Game", label = "Restart Game", chords = k(ch(.F5, PS)), scope = .Global, run = Editor_RestartGame, enabled = proc(s: ^EditorState) -> bool {return !s.buildRunning && (s.gameProcessRunning || s.hasPlayed)}})
	add({id = "game.colliders", category = "Game", label = "Show Colliders in Game", scope = .Global, run = Editor_ToggleGameColliders, checked = proc(s: ^EditorState) -> bool {return s.projectConfig.debugDraw}})
	add({id = "game.simulate", category = "Game", label = "Simulate in Editor", chords = k(ch(.F7)), scope = .Global, run = proc(s: ^EditorState) {
		if s.isSimulating do Toolbar_StopSimulation(s)
		else do Toolbar_StartSimulation(s)
	}, checked = proc(s: ^EditorState) -> bool {return s.isSimulating}})
	add({id = "game.save_folder", category = "Game", label = "Open Save Data Folder", scope = .Global, run = Editor_OpenSaveDataFolder})
	add({id = "game.delete_save", category = "Game", label = "Delete Save Data", scope = .Global, run = Editor_DeleteSaveData})
	add({id = "view.viewport", category = "View", label = "Focus Viewport", chords = k(ch(._1, P)), scope = .Global, run = proc(s: ^EditorState) {imgui.SetWindowFocusStr("Viewport###ViewportWindow")}})
	add({id = "view.code", category = "View", label = "Focus Code Editor", chords = k(ch(._2, P)), scope = .Global, run = proc(s: ^EditorState) {GlobalCode.focusRequest = true}, enabled = has_code})
	add({id = "view.console", category = "View", label = "Focus Console", chords = k(ch(.J, P)), scope = .Global, run = proc(s: ^EditorState) {imgui.SetWindowFocusStr("Console###BottomPanelWindow")}})
	add({id = "debug.continue", category = "Debug", label = "Continue", chords = k(ch(.F8)), scope = .Global, run = proc(s: ^EditorState) {Debug_Command("continue")}, enabled = proc(s: ^EditorState) -> bool {return Debug_IsStopped()}})
	add({id = "debug.step_over", category = "Debug", label = "Step Over", chords = k(ch(.F10)), scope = .Global, run = proc(s: ^EditorState) {Debug_Command("step-over")}, enabled = proc(s: ^EditorState) -> bool {return Debug_IsStopped()}})
	add({id = "debug.step_in", category = "Debug", label = "Step Into", chords = k(ch(.F11)), scope = .Global, run = proc(s: ^EditorState) {Debug_Command("step-in")}, enabled = proc(s: ^EditorState) -> bool {return Debug_IsStopped()}})
	add({id = "debug.step_out", category = "Debug", label = "Step Out", chords = k(ch(.F11, SH)), scope = .Global, run = proc(s: ^EditorState) {Debug_Command("step-out")}, enabled = proc(s: ^EditorState) -> bool {return Debug_IsStopped()}})
	add({id = "help.welcome", category = "Help", label = "Welcome", scope = .Global, run = Welcome_Open})
	add({id = "help.reference", category = "Help", label = "Scripting Reference", scope = .Global, run = proc(s: ^EditorState) {ScriptReference_Open()}})
	add({id = "help.node_reference", category = "Help", label = "Node Reference", scope = .Global, run = proc(s: ^EditorState) {NodeReference_Open(INDEX_PAGE)}})
	add({id = "help.editor_manual", category = "Help", label = "Editor Manual", scope = .Global, run = proc(s: ^EditorState) {NodeReference_OpenEditor("")}})
	add({id = "node.docs", category = "Help", label = "Documentation for the Selected Node", chords = k(ch(.F1, SH)), scope = .Scene, run = proc(s: ^EditorState) {NodeReference_Open(e.Node_TypeName(s.selectedNode))}, enabled = proc(s: ^EditorState) -> bool {return s.selectedNode != nil}})
	add({id = "help.level_reference", category = "Help", label = "Level Editor Reference", scope = .Global, run = proc(s: ^EditorState) {LevelRef_Open("overview")}})
	add({id = "help.level_shortcuts", category = "Help", label = "Level Editor Shortcuts", scope = .Global, run = proc(s: ^EditorState) {LevelRef_Open("shortcuts")}})
	add({id = "help.report_bug", category = "Help", label = "Report a Bug...", scope = .Global, run = proc(s: ^EditorState) {CrashReports_ReportBug(s)}})
	add({id = "help.crash_folder", category = "Help", label = "Open Crash Reports Folder", scope = .Global, run = proc(s: ^EditorState) {CrashReports_OpenFolder(s)}})
	add({id = "help.shortcuts", category = "Help", label = "Keyboard Shortcuts", chords = k(ch(.K, PS)), scope = .Global, run = proc(s: ^EditorState) {showShortcutsWindow = true}})

	// --- Scene editing ---
	add({id = "edit.undo", category = "Edit", label = "Undo", chords = k(ch(.Z, P)), scope = .Scene, run = proc(s: ^EditorState) {
		if LevelEditor_Active() do level_undo(s)
		else do Editor_Undo(s)
	}, enabled = proc(s: ^EditorState) -> bool {return LevelEditor_Active() ? GlobalLevel.doc != nil && len(GlobalLevel.doc.undo) > 0 : len(s.undoStack) > 0}, repeat = true})
	add({id = "edit.redo", category = "Edit", label = "Redo", chords = k(ch(.Z, PS), ch(.Y, P)), scope = .Scene, run = proc(s: ^EditorState) {
		if LevelEditor_Active() do level_redo(s)
		else do Editor_Redo(s)
	}, enabled = proc(s: ^EditorState) -> bool {return LevelEditor_Active() ? GlobalLevel.doc != nil && len(GlobalLevel.doc.redo) > 0 : len(s.redoStack) > 0}, repeat = true})
	add({id = "view.tab_game", category = "View", label = "Game Tab", chords = k(ch(._1, PS)), scope = .Global, run = proc(s: ^EditorState) {GlobalLevel.tab = .Game}, checked = proc(s: ^EditorState) -> bool {return !LevelEditor_Active()}})
	add({id = "view.tab_level", category = "View", label = "Level Tab (LDtk level editor)", chords = k(ch(._2, PS)), scope = .Global, run = proc(s: ^EditorState) {GlobalLevel.tab = .Level}, checked = proc(s: ^EditorState) -> bool {return LevelEditor_Active()}})
	add({id = "scene.new", category = "File", label = "New Scene", chords = k(ch(.N, P)), scope = .Scene, run = Toolbar_NewScene})
	add({id = "scene.save", category = "File", label = "Save Scene", scope = .Scene, run = Toolbar_SaveScene, enabled = has_scene})
	add({id = "node.add", category = "Edit", label = "Add Node...", chords = k(ch(.A, P)), scope = .Scene, run = proc(s: ^EditorState) {AddNodeDialog_Open()}, enabled = has_scene})
	add({id = "node.copy", category = "Edit", label = "Copy", chords = k(ch(.C, P)), scope = .Scene, run = Editor_CopySelection, enabled = can_modify})
	add({id = "node.cut", category = "Edit", label = "Cut", chords = k(ch(.X, P)), scope = .Scene, run = Editor_CutSelection, enabled = can_modify})
	add({id = "node.paste", category = "Edit", label = "Paste", chords = k(ch(.V, P)), scope = .Scene, run = Editor_PasteNodes, enabled = proc(s: ^EditorState) -> bool {return s.activeScene != nil && Editor_HasClipboardNodes()}})
	add({id = "node.duplicate", category = "Edit", label = "Duplicate", chords = k(ch(.D, P)), scope = .Scene, run = SceneHierarchy_DuplicateSelected, enabled = can_modify})
	add({id = "node.delete", category = "Edit", label = "Delete", chords = k(ch(.Delete), ch(.Backspace)), scope = .Scene, run = SceneHierarchy_DeleteSelected, enabled = can_modify})
	add({id = "node.lock", category = "Edit", label = "Lock in Viewport", chords = k(ch(.L, P)), scope = .Scene, run = Editor_ToggleViewLock, enabled = can_modify, checked = proc(s: ^EditorState) -> bool {return s.selectedNode != nil && s.selectedNode.editorLocked}})
	add({id = "node.editor_hide", category = "Edit", label = "Hide in Editor", chords = k(ch(.H, PS)), scope = .Scene, run = Editor_ToggleViewHidden, enabled = can_modify, checked = proc(s: ^EditorState) -> bool {return s.selectedNode != nil && s.selectedNode.editorHidden}})
	add({id = "node.rename", category = "Edit", label = "Rename Node", chords = k(ch(.F2)), scope = .Scene, run = Editor_BeginRename, enabled = can_modify})
	add({id = "node.select_all", category = "Edit", label = "Select All Nodes", chords = k(ch(.A, PS)), scope = .Scene, run = Editor_SelectAllNodes, enabled = has_scene})
	add({id = "node.deselect", category = "Edit", label = "Deselect", chords = k(ch(.Escape)), scope = .Scene, run = proc(s: ^EditorState) {
		// Esc first leaves collision-shape editing, then deselects.
		if ShapeEdit_IsActive(s) do ShapeEdit_SetActive(s, false)
		else do Editor_ClearSelection(s)
	}, enabled = has_selection})
	add({id = "node.nudge_left", category = "Edit", label = "Nudge Left", chords = k(ch(.LeftArrow), ch(.LeftArrow, SH)), scope = .Scene, run = proc(s: ^EditorState) {Editor_NudgeSelection(s, {-1, 0})}, enabled = can_modify, repeat = true})
	add({id = "node.nudge_right", category = "Edit", label = "Nudge Right", chords = k(ch(.RightArrow), ch(.RightArrow, SH)), scope = .Scene, run = proc(s: ^EditorState) {Editor_NudgeSelection(s, {1, 0})}, enabled = can_modify, repeat = true})
	add({id = "node.nudge_up", category = "Edit", label = "Nudge Up", chords = k(ch(.UpArrow), ch(.UpArrow, SH)), scope = .Scene, run = proc(s: ^EditorState) {Editor_NudgeSelection(s, {0, -1})}, enabled = can_modify, repeat = true})
	add({id = "node.nudge_down", category = "Edit", label = "Nudge Down", chords = k(ch(.DownArrow), ch(.DownArrow, SH)), scope = .Scene, run = proc(s: ^EditorState) {Editor_NudgeSelection(s, {0, 1})}, enabled = can_modify, repeat = true})
	add({id = "align.left", category = "Align", label = "Align Left Edges", scope = .Scene, run = proc(s: ^EditorState) {Editor_Align(s, .Left)}, enabled = Editor_HasMultiSelection})
	add({id = "align.center_x", category = "Align", label = "Align Horizontal Centers", scope = .Scene, run = proc(s: ^EditorState) {Editor_Align(s, .CenterX)}, enabled = Editor_HasMultiSelection})
	add({id = "align.right", category = "Align", label = "Align Right Edges", scope = .Scene, run = proc(s: ^EditorState) {Editor_Align(s, .Right)}, enabled = Editor_HasMultiSelection})
	add({id = "align.top", category = "Align", label = "Align Top Edges", scope = .Scene, run = proc(s: ^EditorState) {Editor_Align(s, .Top)}, enabled = Editor_HasMultiSelection})
	add({id = "align.center_y", category = "Align", label = "Align Vertical Centers", scope = .Scene, run = proc(s: ^EditorState) {Editor_Align(s, .CenterY)}, enabled = Editor_HasMultiSelection})
	add({id = "align.bottom", category = "Align", label = "Align Bottom Edges", scope = .Scene, run = proc(s: ^EditorState) {Editor_Align(s, .Bottom)}, enabled = Editor_HasMultiSelection})
	add({id = "align.distribute_x", category = "Align", label = "Distribute Horizontally", scope = .Scene, run = proc(s: ^EditorState) {Editor_Align(s, .DistributeX)}, enabled = proc(s: ^EditorState) -> bool {return len(s.selection) >= 3}})
	add({id = "align.distribute_y", category = "Align", label = "Distribute Vertically", scope = .Scene, run = proc(s: ^EditorState) {Editor_Align(s, .DistributeY)}, enabled = proc(s: ^EditorState) -> bool {return len(s.selection) >= 3}})
	add({id = "tool.select", category = "Tools", label = "Select Tool", chords = k(ch(.Q)), scope = .Scene, run = proc(s: ^EditorState) {s.toolMode = .Select}, checked = proc(s: ^EditorState) -> bool {return s.toolMode == .Select}})
	add({id = "tool.move", category = "Tools", label = "Move Tool", chords = k(ch(.W)), scope = .Scene, run = proc(s: ^EditorState) {s.toolMode = .Translate}, checked = proc(s: ^EditorState) -> bool {return s.toolMode == .Translate}})
	add({id = "tool.rotate", category = "Tools", label = "Rotate Tool", chords = k(ch(.E)), scope = .Scene, run = proc(s: ^EditorState) {s.toolMode = .Rotate}, checked = proc(s: ^EditorState) -> bool {return s.toolMode == .Rotate}})
	add({id = "tool.scale", category = "Tools", label = "Scale Tool", chords = k(ch(.R)), scope = .Scene, run = proc(s: ^EditorState) {s.toolMode = .Scale}, checked = proc(s: ^EditorState) -> bool {return s.toolMode == .Scale}})
	add({id = "tool.sprite_slicer", category = "Tools", label = "Sprite Sheet Slicer...", scope = .Global, run = proc(s: ^EditorState) {Slicer_Open(s, "")}})
	add({id = "tool.pan", category = "Tools", label = "Pan Tool", chords = k(ch(.T)), scope = .Scene, run = proc(s: ^EditorState) {s.toolMode = .Pan}, checked = proc(s: ^EditorState) -> bool {return s.toolMode == .Pan}})
	add({id = "view.frame", category = "View", label = "Frame Selection", chords = k(ch(.F)), scope = .Scene, run = proc(s: ^EditorState) {s.cameraPos = s.selectedNode.globalPosition}, enabled = has_selection})
	add({id = "view.reset_zoom", category = "View", label = "Reset Zoom (100%)", chords = k(ch(._0, P)), scope = .Scene, run = proc(s: ^EditorState) {s.cameraZoom = 1}})
	add({id = "view.fit_scene", category = "View", label = "Fit Scene to View", chords = k(ch(.Home)), scope = .Scene, run = Viewport_FitScene})
	add({id = "view.fit_game", category = "View", label = "Fit Game View", chords = k(ch(.Home, SH)), scope = .Scene, run = Viewport_FitGameView})
	add({id = "view.fit_selection", category = "View", label = "Fit Selection", chords = k(ch(.F, SH)), scope = .Scene, run = Viewport_FitSelection, enabled = has_selection})
	add({id = "view.zoom_in", category = "View", label = "Zoom In", chords = k(ch(.Equal, P)), scope = .Scene, run = proc(s: ^EditorState) {s.cameraZoom = min(s.cameraZoom * 1.25, 10)}, repeat = true})
	add({id = "view.zoom_out", category = "View", label = "Zoom Out", chords = k(ch(.Minus, P)), scope = .Scene, run = proc(s: ^EditorState) {s.cameraZoom = max(s.cameraZoom / 1.25, 0.1)}, repeat = true})
	add({id = "view.grid", category = "View", label = "Show Grid", chords = k(ch(.G, SH)), scope = .Scene, run = proc(s: ^EditorState) {s.showGrid = !s.showGrid}, checked = proc(s: ^EditorState) -> bool {return s.showGrid}})
	add({id = "view.bounds", category = "View", label = "Show Bounds & Colliders", scope = .Scene, run = proc(s: ^EditorState) {s.showBounds = !s.showBounds}, checked = proc(s: ^EditorState) -> bool {return s.showBounds}})
	add({id = "view.camera_frames", category = "View", label = "Show Camera Frames", scope = .Scene, run = proc(s: ^EditorState) {s.showCameraBounds = !s.showCameraBounds}, checked = proc(s: ^EditorState) -> bool {return s.showCameraBounds}})
	add({id = "view.rulers", category = "View", label = "Rulers & Guides", chords = k(ch(.R, PS)), scope = .Scene, run = proc(s: ^EditorState) {s.showRulers = !s.showRulers}, checked = proc(s: ^EditorState) -> bool {return s.showRulers}})
	add({id = "view.clear_guides", category = "View", label = "Clear Guides", scope = .Scene, run = Editor_ClearGuides, enabled = proc(s: ^EditorState) -> bool {return s.activeScene != nil && s.activeScene.guideCount > 0}})
	add({id = "view.smart_snap", category = "View", label = "Smart Snapping", scope = .Scene, run = proc(s: ^EditorState) {s.smartSnap = !s.smartSnap}, checked = proc(s: ^EditorState) -> bool {return s.smartSnap}})
	add({id = "view.colliders", category = "View", label = "Show All Colliders", scope = .Scene, run = proc(s: ^EditorState) {s.showAllColliders = !s.showAllColliders}, checked = proc(s: ^EditorState) -> bool {return s.showAllColliders}})
	add({id = "view.file_browser", category = "View", label = "File Browser", chords = k(ch(.B, PS)), run = proc(s: ^EditorState) {FileBrowser_Toggle()}, checked = proc(s: ^EditorState) -> bool {return FileBrowser_IsOpen()}})
	add({id = "view.inspector_help", category = "View", label = "Inspector Help", run = proc(s: ^EditorState) {s.showInspectorHelp = !s.showInspectorHelp}, checked = proc(s: ^EditorState) -> bool {return s.showInspectorHelp}})
	add({id = "view.tab_bars", category = "View", label = "Show Tab Bars", run = proc(s: ^EditorState) {
		GlobalSettings.showTabBars = !GlobalSettings.showTabBars
		if !GlobalSettings.showTabBars do Dock_ApplyTabBars(editorDockspaceID, false) // single windows hide theirs again
		Editor_SaveSettings()
	}, checked = proc(s: ^EditorState) -> bool {return GlobalSettings.showTabBars}})
	// Scene tabs (scene_tabs.odin).
	add({id = "scene.close_tab", category = "Scene", label = "Close Scene Tab", chords = k(ch(.W, P)), scope = .Scene, run = proc(s: ^EditorState) {SceneTabs_RequestClose(s, s.activeScene)}, enabled = proc(s: ^EditorState) -> bool {return len(SceneTabs_Open()) > 1}})
	add({id = "scene.next_tab", category = "Scene", label = "Next Scene Tab", chords = k(ch(.PageDown, CT), ch(.Tab, CT), ch(.RightArrow, PA)), scope = .Scene, run = proc(s: ^EditorState) {SceneTabs_Cycle(s, 1)}})
	add({id = "scene.prev_tab", category = "Scene", label = "Previous Scene Tab", chords = k(ch(.PageUp, CT), ch(.Tab, Mods{.Ctrl, .Shift}), ch(.LeftArrow, PA)), scope = .Scene, run = proc(s: ^EditorState) {SceneTabs_Cycle(s, -1)}})
	// Colour vision preview: the viewport as seen with a colour vision deficiency (simulated).
	add({id = "view.vision_protanopia", category = "View", label = "Colour Vision: Protanopia", scope = .Scene, run = proc(s: ^EditorState) {viewport_set_vision(.Protanopia)}, checked = proc(s: ^EditorState) -> bool {return viewportVision == .Protanopia}})
	add({id = "view.vision_deuteranopia", category = "View", label = "Colour Vision: Deuteranopia", scope = .Scene, run = proc(s: ^EditorState) {viewport_set_vision(.Deuteranopia)}, checked = proc(s: ^EditorState) -> bool {return viewportVision == .Deuteranopia}})
	add({id = "view.vision_tritanopia", category = "View", label = "Colour Vision: Tritanopia", scope = .Scene, run = proc(s: ^EditorState) {viewport_set_vision(.Tritanopia)}, checked = proc(s: ^EditorState) -> bool {return viewportVision == .Tritanopia}})
	add({id = "view.snap_grid", category = "View", label = "Snap to Grid", chords = k(ch(.S, SH)), scope = .Scene, run = proc(s: ^EditorState) {s.snapGrid = !s.snapGrid}, checked = proc(s: ^EditorState) -> bool {return s.snapGrid}})
	add({id = "view.snap_rotation", category = "View", label = "Snap Rotation", scope = .Scene, run = proc(s: ^EditorState) {s.snapRotation = !s.snapRotation}, checked = proc(s: ^EditorState) -> bool {return s.snapRotation}})

	// --- Code editor (Zed defaults) ---
	add({id = "code.reference", category = "Code", label = "Scripting Reference for Symbol", chords = k(ch(.F1)), scope = .Code, run = Code_CmdReference})
	add({id = "code.clipboard_history", category = "Code", label = "Paste from Clipboard History", chords = k(ch(.V, PS)), scope = .Code, run = Code_CmdClipboardHistory})
	add({id = "code.copy_path", category = "Code", label = "Copy Path", scope = .Code, run = proc(s: ^EditorState) {Code_CmdCopyPath(s, .Relative)}})
	add({id = "code.copy_absolute_path", category = "Code", label = "Copy Absolute Path", scope = .Code, run = proc(s: ^EditorState) {Code_CmdCopyPath(s, .Absolute)}})
	add({id = "code.copy_location", category = "Code", label = "Copy Location (path:line)", scope = .Code, run = proc(s: ^EditorState) {Code_CmdCopyPath(s, .Location)}})
	add({id = "code.copy_markdown", category = "Code", label = "Copy as Markdown", scope = .Code, run = Code_CmdCopyMarkdown})
	add({id = "code.wrap_if", category = "Code", label = "Wrap in if ... end", scope = .Code, run = proc(s: ^EditorState) {Code_CmdWrap(s, .If)}})
	add({id = "code.wrap_do", category = "Code", label = "Wrap in do ... end", scope = .Code, run = proc(s: ^EditorState) {Code_CmdWrap(s, .Do)}})
	add({id = "code.wrap_function", category = "Code", label = "Wrap in local function ... end", scope = .Code, run = proc(s: ^EditorState) {Code_CmdWrap(s, .Function)}})
	add({id = "code.expand_selection", category = "Code", label = "Expand Selection", chords = k(ch(.RightArrow, EXPAND_MODS)), scope = .Code, run = Code_CmdExpandSelection, repeat = true})
	add({id = "code.shrink_selection", category = "Code", label = "Shrink Selection", chords = k(ch(.LeftArrow, EXPAND_MODS)), scope = .Code, run = Code_CmdShrinkSelection, repeat = true})
	add({id = "code.skip_occurrence", category = "Code", label = "Skip Occurrence (Select Next Instead)", chords = k(ch(.D, PA)), scope = .Code, run = Code_CmdSkipOccurrence})
	add({id = "code.cursors_line_ends", category = "Code", label = "Add Cursors to Line Ends", chords = k(ch(.I, Mods{.Alt, .Shift})), scope = .Code, run = Code_CmdCursorsAtLineEnds})
	add({id = "code.undo_cursor", category = "Code", label = "Undo Cursor", chords = k(ch(.U, P)), scope = .Code, run = Code_CmdUndoCursor})
	add({id = "code.select_inside", category = "Code", label = "Select Inside Brackets / Quotes", chords = k(ch(.M, Mods{.Primary, .Shift})), scope = .Code, run = Code_CmdSelectInside})
	add({id = "code.matching_bracket", category = "Code", label = "Go to Matching Bracket", chords = k(ch(.Backslash, PS)), scope = .Code, run = Code_CmdMatchingBracket})
	add({id = "code.fold", category = "Code", label = "Fold", chords = k(ch(.LeftBracket, PA)), scope = .Code, run = Code_CmdFold})
	add({id = "code.unfold", category = "Code", label = "Unfold", chords = k(ch(.RightBracket, PA)), scope = .Code, run = Code_CmdUnfold})
	add({id = "code.fold_all", category = "Code", label = "Fold All", chords = k(ch(.LeftBracket, Mods{.Primary, .Alt, .Shift})), scope = .Code, run = Code_CmdFoldAll})
	add({id = "code.unfold_all", category = "Code", label = "Unfold All", chords = k(ch(.RightBracket, Mods{.Primary, .Alt, .Shift})), scope = .Code, run = Code_CmdUnfoldAll})
	add({id = "code.soft_wrap", category = "Code", label = "Toggle Soft Wrap", chords = k(ch(.Z, AL)), scope = .Code, run = Code_CmdToggleSoftWrap})
	add({id = "code.inlay_hints", category = "Code", label = "Toggle Inlay Hints", chords = k(ch(.H, Mods{.Ctrl, .Alt})), scope = .Code, run = proc(s: ^EditorState) {GlobalSettings.inlayHints = !GlobalSettings.inlayHints; _ = Editor_SaveSettings()}})
	add({id = "code.nav_back", category = "Code", label = "Go Back", chords = k(ch(.Minus, CT)), scope = .Code, run = Code_CmdNavBack})
	add({id = "code.nav_forward", category = "Code", label = "Go Forward", chords = k(ch(.Minus, Mods{.Ctrl, .Shift})), scope = .Code, run = Code_CmdNavForward})
	add({id = "code.next_diagnostic", category = "Code", label = "Next Problem", chords = k(ch(.F8)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdNextDiagnostic(s, 1)}, enabled = proc(s: ^EditorState) -> bool {return !Debug_IsStopped()}})
	add({id = "code.prev_diagnostic", category = "Code", label = "Previous Problem", chords = k(ch(.F8, SH)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdNextDiagnostic(s, -1)}, enabled = proc(s: ^EditorState) -> bool {return !Debug_IsStopped()}})
	add({id = "code.next_change", category = "Code", label = "Next Change", chords = k(ch(.F8, AL)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdNextChange(s, 1)}})
	add({id = "code.prev_change", category = "Code", label = "Previous Change", chords = k(ch(.F8, Mods{.Alt, .Shift})), scope = .Code, run = proc(s: ^EditorState) {Code_CmdNextChange(s, -1)}})
	add({id = "code.outline", category = "Code", label = "Go to Symbol in File...", chords = k(ch(.O, PS)), scope = .Code, run = Code_CmdOutline})
	add({id = "code.workspace_symbols", category = "Code", label = "Go to Symbol in Project...", chords = k(ch(.T, P)), scope = .Global, run = Code_CmdWorkspaceSymbols})
	add({id = "code.find_in_files", category = "Code", label = "Find in Files", chords = k(ch(.F, PS)), scope = .Global, run = Code_CmdFindInFiles})
	add({id = "code.peek_definition", category = "Code", label = "Peek Definition", chords = k(ch(.F12, AL)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdPeek(s, false)}})
	add({id = "code.peek_references", category = "Code", label = "Peek References", chords = k(ch(.F12, Mods{.Alt, .Shift})), scope = .Code, run = proc(s: ^EditorState) {Code_CmdPeek(s, true)}})
	add({id = "code.code_actions", category = "Code", label = "Code Actions (Quick Fix)", chords = k(ch(.Period, P)), scope = .Code, run = Code_CmdCodeActions})
	add({id = "code.extract_local", category = "Code", label = "Extract Local Variable", chords = k(ch(.V, PA)), scope = .Code, run = Code_CmdExtractLocal})
	add({id = "code.extract_method", category = "Code", label = "Extract Method", chords = k(ch(.M, PA)), scope = .Code, run = Code_CmdExtractMethod})
	add({id = "code.inline_variable", category = "Code", label = "Inline Variable", chords = k(ch(.N, PA)), scope = .Code, run = Code_CmdInlineVariable})
	add({id = "code.toggle_property_access", category = "Code", label = "Toggle get_property / Field Access", scope = .Code, run = Code_CmdTogglePropertyAccess})
	add({id = "code.toggle_vec2", category = "Code", label = "Toggle {x, y} / Vec2(x, y)", scope = .Code, run = Code_CmdToggleVec2})
	add({id = "code.local_history", category = "Code", label = "Local History...", scope = .Code, run = Code_CmdLocalHistory})
	add({id = "code.show_in_inspector", category = "Code", label = "Show in Inspector", scope = .Code, run = Code_CmdShowInInspector})
	add({id = "code.save", category = "Code", label = "Save File", scope = .Code, run = Code_CmdSave})
	add({id = "code.close", category = "Code", label = "Close Tab", chords = k(ch(.W, P)), scope = .Code, run = Code_CmdClose})
	add({id = "code.reopen", category = "Code", label = "Reopen Closed Tab", chords = k(ch(.T, PS)), scope = .Code, run = Code_CmdReopen})
	add({id = "code.next_tab", category = "Code", label = "Next Tab", chords = k(ch(.Tab, CT), ch(.RightBracket, PS)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdCycleTab(1)}})
	add({id = "code.prev_tab", category = "Code", label = "Previous Tab", chords = k(ch(.Tab, Mods{.Ctrl, .Shift}), ch(.LeftBracket, PS)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdCycleTab(-1)}})
	add({id = "code.undo", category = "Code", label = "Undo", chords = k(ch(.Z, P)), scope = .Code, run = Code_CmdUndo, repeat = true})
	add({id = "code.redo", category = "Code", label = "Redo", chords = k(ch(.Z, PS), ch(.Y, P)), scope = .Code, run = Code_CmdRedo, repeat = true})
	add({id = "code.cut", category = "Code", label = "Cut", chords = k(ch(.X, P)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdCopy(true)}})
	add({id = "code.copy", category = "Code", label = "Copy", chords = k(ch(.C, P)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdCopy(false)}})
	add({id = "code.paste", category = "Code", label = "Paste", chords = k(ch(.V, P)), scope = .Code, run = Code_CmdPaste, repeat = true})
	add({id = "code.select_all", category = "Code", label = "Select All", chords = k(ch(.A, P)), scope = .Code, run = Code_CmdSelectAll})
	add({id = "code.select_line", category = "Code", label = "Select Line", chords = k(ch(.L, P)), scope = .Code, run = Code_CmdSelectLine, repeat = true})
	add({id = "code.comment", category = "Code", label = "Toggle Comment", chords = k(ch(.Slash, P)), scope = .Code, run = Code_CmdToggleComment})
	add({id = "code.indent", category = "Code", label = "Indent", chords = k(ch(.RightBracket, P)), scope = .Code, run = Code_CmdIndent, repeat = true})
	add({id = "code.outdent", category = "Code", label = "Outdent", chords = k(ch(.LeftBracket, P)), scope = .Code, run = Code_CmdOutdent, repeat = true})
	add({id = "code.move_up", category = "Code", label = "Move Line Up", chords = k(ch(.UpArrow, AL)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdMoveLines(s, -1)}, repeat = true})
	add({id = "code.move_down", category = "Code", label = "Move Line Down", chords = k(ch(.DownArrow, AL)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdMoveLines(s, 1)}, repeat = true})
	add({id = "code.duplicate_down", category = "Code", label = "Duplicate Line Down", chords = k(ch(.D, PS), ch(.DownArrow, Mods{.Alt, .Shift})), scope = .Code, run = proc(s: ^EditorState) {Code_CmdDuplicate(s, true)}, repeat = true})
	add({id = "code.duplicate_up", category = "Code", label = "Duplicate Line Up", chords = k(ch(.UpArrow, Mods{.Alt, .Shift})), scope = .Code, run = proc(s: ^EditorState) {Code_CmdDuplicate(s, false)}, repeat = true})
	add({id = "code.delete_line", category = "Code", label = "Delete Line", chords = k(ch(.K, PS)), scope = .Code, run = Code_CmdDeleteLine, repeat = true})
	add({id = "code.newline_below", category = "Code", label = "Insert Line Below", chords = k(ch(.Enter, P)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdInsertLine(s, false)}, repeat = true})
	add({id = "code.newline_above", category = "Code", label = "Insert Line Above", chords = k(ch(.Enter, PS)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdInsertLine(s, true)}, repeat = true})
	add({id = "code.join_lines", category = "Code", label = "Join Lines", chords = k(ch(.J, CT)), scope = .Code, run = Code_CmdJoinLines, repeat = true})
	add({id = "code.delete_to_line_start", category = "Code", label = "Delete to Line Start", chords = k(ch(.Backspace, P)), scope = .Code, run = Code_CmdDeleteToLineStart, repeat = true})
	add({id = "code.select_next", category = "Code", label = "Select Next Occurrence", chords = k(ch(.D, P)), scope = .Code, run = Code_CmdSelectNextOccurrence, repeat = true})
	add({id = "code.select_all_occurrences", category = "Code", label = "Select All Occurrences", chords = k(ch(.L, PS)), scope = .Code, run = Code_CmdSelectAllOccurrences})
	add({id = "code.cursor_above", category = "Code", label = "Add Cursor Above", chords = k(ch(.UpArrow, PA)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdAddCursor(s, -1)}, repeat = true})
	add({id = "code.cursor_below", category = "Code", label = "Add Cursor Below", chords = k(ch(.DownArrow, PA)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdAddCursor(s, 1)}, repeat = true})
	add({id = "code.find", category = "Code", label = "Find", chords = k(ch(.F, P)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdFind(s, false)}})
	add({id = "code.replace", category = "Code", label = "Find and Replace", chords = k(ch(.F, PA), ch(.H, P)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdFind(s, true)}})
	add({id = "code.find_next", category = "Code", label = "Find Next", chords = k(ch(.G, P), ch(.F3)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdFindStep(s, 1)}, repeat = true})
	add({id = "code.find_prev", category = "Code", label = "Find Previous", chords = k(ch(.G, PS), ch(.F3, SH)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdFindStep(s, -1)}, repeat = true})
	add({id = "code.goto_line", category = "Code", label = "Go to Line...", chords = k(ch(.G, CT)), scope = .Code, run = proc(s: ^EditorState) {Palette_Open(.GotoLine)}})
	add({id = "code.complete", category = "Code", label = "Show Completions", chords = k(ch(.Space, CT)), scope = .Code, run = Code_CmdComplete})
	add({id = "code.signature", category = "Code", label = "Show Signature Help", chords = k(ch(.Space, Mods{.Primary, .Shift})), scope = .Code, run = Code_CmdSignature})
	add({id = "code.definition", category = "Code", label = "Go to Definition", chords = k(ch(.F12)), scope = .Code, run = Code_CmdDefinition})
	add({id = "code.references", category = "Code", label = "Find All References", chords = k(ch(.F12, SH)), scope = .Code, run = Code_CmdReferences})
	add({id = "code.rename", category = "Code", label = "Rename Symbol", chords = k(ch(.F2)), scope = .Code, run = Code_CmdRename})
	add({id = "code.format", category = "Code", label = "Format Document", chords = k(ch(.I, PS), ch(.F, Mods{.Alt, .Shift})), scope = .Code, run = Code_CmdFormat})
	add({id = "code.font_bigger", category = "Code", label = "Increase Font Size", chords = k(ch(.Equal, P)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdFontSize(s, 1)}, repeat = true})
	add({id = "code.font_smaller", category = "Code", label = "Decrease Font Size", chords = k(ch(.Minus, P)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdFontSize(s, -1)}, repeat = true})
	add({id = "code.font_reset", category = "Code", label = "Reset Font Size", chords = k(ch(._0, P)), scope = .Code, run = proc(s: ^EditorState) {Code_CmdFontSize(s, 0)}})
	add({id = "tool.new_plugin", category = "Tools", label = "New Plugin...", scope = .Global, run = proc(s: ^EditorState) {Prompt_Open(.NewPlugin, "My Plugin")}})
	add({id = "code.new_script", category = "Code", label = "New Script", scope = .Global, run = proc(s: ^EditorState) {NewScriptDialog_Open(s)}})
	add({id = "nodes.new_component", category = "Scene", label = "New Component", scope = .Global, run = proc(s: ^EditorState) {NewComponentDialog_Open(s)}})
	add({id = "nodes.new_custom_node", category = "Scene", label = "New Custom Node Type", scope = .Global, run = proc(s: ^EditorState) {CustomNodeDialog_Open(s)}})
}

// Default chords of every action (for "Reset" in the keymap editor).
actionDefaults: map[string][3]Chord

// Actions_ApplyKeymap installs user chords (missing ids keep their defaults).
Actions_ApplyKeymap :: proc(keymap: map[string][3]Chord) {
	if actionDefaults == nil {
		actionDefaults = make(map[string][3]Chord)
		for a in GlobalActions do actionDefaults[a.id] = a.chords
	}
	for &a in GlobalActions {
		if c, ok := keymap[a.id]; ok do a.chords = c
		else do a.chords = actionDefaults[a.id]
	}
}

// Action_Conflicts: other actions bound to `c` in an overlapping scope.
Action_Conflicts :: proc(self: ^Editor_Action, c: Chord) -> string {
	if c.key == .None do return ""
	for &a in GlobalActions {
		if &a == self do continue
		overlap := a.scope == self.scope || a.scope == .Global || self.scope == .Global
		if !overlap do continue
		for o in a.chords do if o == c do return a.label
	}
	return ""
}

Action_Find :: proc(id: string) -> ^Editor_Action {
	for &a in GlobalActions do if a.id == id do return &a
	return nil
}

Action_Enabled :: proc(state: ^EditorState, a: ^Editor_Action) -> bool {
	if a.plugin != nil do return PluginAPI_ActionEnabled(state, a)
	return a.enabled == nil || a.enabled(state)
}

// Action_Checked: a toggle action's state (false for the others).
Action_Checked :: proc(state: ^EditorState, a: ^Editor_Action) -> bool {
	if a.plugin != nil do return PluginAPI_ActionChecked(state, a)
	return a.checked != nil && a.checked(state)
}

// Action_Run runs an action (if enabled) and remembers it for the palette.
Action_Run :: proc(state: ^EditorState, a: ^Editor_Action) -> bool {
	if a == nil || !Action_Enabled(state, a) do return false
	e.Crash_Note(fmt.tprintf("action %s", a.id)) // (a crash report's recent lines)
	for id, i in recentActions {
		if id == a.id {ordered_remove(&recentActions, i); break}
	}
	inject_at(&recentActions, 0, a.id)
	if len(recentActions) > 12 do pop(&recentActions)
	if a.plugin != nil do PluginAPI_ActionRun(state, a)
	else do a.run(state)
	return true
}

Action_RecentRank :: proc(id: string) -> int {
	for r, i in recentActions do if r == id do return i
	return -1
}

// Chord_Text: "Cmd+Shift+P" (macOS) / "Ctrl+Shift+P".
Chord_Text :: proc(c: Chord, allocator := context.temp_allocator) -> string {
	if c.key == .None do return ""
	sb := strings.builder_make(allocator)
	if .Ctrl in c.mods do strings.write_string(&sb, "Ctrl+")
	if .Primary in c.mods do strings.write_string(&sb, "Cmd+" if ODIN_OS == .Darwin else "Ctrl+")
	if .Alt in c.mods do strings.write_string(&sb, "Opt+" if ODIN_OS == .Darwin else "Alt+")
	if .Shift in c.mods do strings.write_string(&sb, "Shift+")
	strings.write_string(&sb, key_text(c.key))
	return strings.to_string(sb)
}

@(private = "file")
key_text :: proc(k: imgui.Key) -> string {
	#partial switch k {
	case .Enter: return "Enter"
	case .Escape: return "Esc"
	case .Tab: return "Tab"
	case .Space: return "Space"
	case .Backspace: return "Backspace"
	case .Delete: return "Del"
	case .UpArrow: return "Up"
	case .DownArrow: return "Down"
	case .LeftArrow: return "Left"
	case .RightArrow: return "Right"
	case .Slash: return "/"
	case .Comma: return ","
	case .Equal: return "="
	case .Minus: return "-"
	case .LeftBracket: return "["
	case .RightBracket: return "]"
	}
	if k >= .A && k <= .Z do return fmt.tprintf("%c", 'A' + rune(int(k) - int(imgui.Key.A)))
	if k >= ._0 && k <= ._9 do return fmt.tprintf("%c", '0' + rune(int(k) - int(imgui.Key._0)))
	if k >= .F1 && k <= .F12 do return fmt.tprintf("F%d", int(k) - int(imgui.Key.F1) + 1)
	return fmt.tprint(k)
}

// Action_ShortcutText: the first chord ("" if none), for menus.
Action_ShortcutText :: proc(a: ^Editor_Action) -> string {
	return Chord_Text(a.chords[0])
}

Action_AllShortcutsText :: proc(a: ^Editor_Action) -> string {
	sb := strings.builder_make(context.temp_allocator)
	for c in a.chords {
		if c.key == .None do continue
		if strings.builder_len(sb) > 0 do strings.write_string(&sb, "  /  ")
		strings.write_string(&sb, Chord_Text(c))
	}
	return strings.to_string(sb)
}

// Dear ImGui swaps Cmd and Ctrl on macOS (io.ConfigMacOSXBehaviors): its
// Ctrl keys report Cmd, its Super keys the physical Control key.
Keys_Primary :: proc() -> bool {
	return imgui.IsKeyDown(.LeftCtrl) || imgui.IsKeyDown(.RightCtrl)
}

Keys_PhysicalCtrl :: proc() -> bool {
	when ODIN_OS == .Darwin {
		return imgui.IsKeyDown(.LeftSuper) || imgui.IsKeyDown(.RightSuper)
	} else {
		return imgui.IsKeyDown(.LeftCtrl) || imgui.IsKeyDown(.RightCtrl)
	}
}

// chord_pressed: is `c` pressed this frame? Primary chords also accept the
// physical Ctrl key on macOS (scripts and muscle memory use Ctrl+S);
// a Ctrl chord bound to the same key wins (chord_specificity).
@(private = "file")
chord_pressed :: proc(c: Chord, repeat: bool) -> bool {
	if c.key == .None || !imgui.IsKeyPressed(c.key, repeat) do return false
	cmd := Keys_Primary()
	pctl := Keys_PhysicalCtrl()
	shift := imgui.IsKeyDown(.LeftShift) || imgui.IsKeyDown(.RightShift)
	alt := imgui.IsKeyDown(.LeftAlt) || imgui.IsKeyDown(.RightAlt)
	if (.Shift in c.mods) != shift do return false
	if (.Alt in c.mods) != alt do return false
	switch {
	case .Primary in c.mods && .Ctrl in c.mods:
		return cmd && pctl
	case .Primary in c.mods:
		return cmd || pctl
	case .Ctrl in c.mods:
		when ODIN_OS == .Darwin do return pctl && !cmd
		else do return pctl
	}
	return !cmd && !pctl
}

@(private = "file")
chord_specificity :: proc(c: Chord) -> int {
	cmd := Keys_Primary()
	pctl := Keys_PhysicalCtrl()
	if .Ctrl in c.mods && pctl do return 2
	when ODIN_OS == .Darwin {
		if .Primary in c.mods && cmd do return 2
	}
	return 1
}

showShortcutsWindow := false

// Actions_Dispatch runs the action whose shortcut was pressed this frame.
// Code actions apply while the code editor (or its find bar) has focus;
// scene actions while nothing else wants the keyboard.
Actions_Dispatch :: proc(state: ^EditorState) {
	io := imgui.GetIO()
	if imgui.IsPopupOpen("", imgui.PopupFlags_AnyPopup) do return
	codeFocus := Code_WindowFocused() || Code_FindBarFocused()
	typing := io.WantTextInput && !codeFocus
	best: ^Editor_Action
	bestScore := -1
	levelMode := LevelEditor_Active()
	for &a in GlobalActions {
		// The Level tab: only global commands (it has its own keys).
		if levelMode && a.scope != .Global do continue
		if levelMode && (a.id == "view.viewport" || a.id == "view.code" || a.id == "file.save_as" || a.id == "file.revert") do continue
		// The Level Generator window has its own Save / Undo / Delete keys.
		if levelGenFocused && (a.scope == .Scene || a.id == "file.save") do continue
		switch a.scope {
		case .Global: if typing do continue
		case .Scene:
			if typing || codeFocus do continue
			// The animation timeline has its own delete / copy / paste.
			if animTimelineFocused && strings.has_prefix(a.id, "node.") do continue
			if stateGraphFocused && strings.has_prefix(a.id, "node.") do continue // the graph's own Delete / copy
			if behaviorTreeFocused && strings.has_prefix(a.id, "node.") do continue // (the Behavior Tree tab's too)
		case .Code:   if !codeFocus do continue
		}
		// While the find bar has focus, plain keys belong to its text field.
		if Code_FindBarFocused() && a.scope == .Code {
			if a.id != "code.find_next" && a.id != "code.find_prev" && a.id != "code.find" && a.id != "code.replace" && a.id != "code.save" do continue
		}
		// A disabled action doesn't shadow another on the same key (F8: next
		// diagnostic in the code, continue while the debugger is paused).
		if !Action_Enabled(state, &a) do continue
		for c in a.chords {
			if !chord_pressed(c, a.repeat) do continue
			// Code actions beat global/scene ones bound to the same chord.
			score := chord_specificity(c) * 10 + (5 if a.scope == .Code else 0)
			if score > bestScore {
				best = &a
				bestScore = score
			}
		}
	}
	if best != nil do Action_Run(state, best)
}

// Actions_MenuItem draws a menu item for an action (label, shortcut,
// check mark, enabled state); returns true if it ran.
Actions_MenuItem :: proc(state: ^EditorState, id: string, label: string = "") -> bool {
	a := Action_Find(id)
	if a == nil do return false
	text := label if label != "" else a.label
	checked := Action_Checked(state, a)
	sc := Action_ShortcutText(a)
	clicked := imgui.MenuItem(strings.clone_to_cstring(text, context.temp_allocator), strings.clone_to_cstring(sc, context.temp_allocator) if sc != "" else nil, checked, Action_Enabled(state, a))
	if clicked do Action_Run(state, a)
	return clicked
}

// Shortcuts_Render: Help > Keyboard Shortcuts, generated from the table.
Shortcuts_Render :: proc(state: ^EditorState) {
	if !showShortcutsWindow do return
	imgui.SetNextWindowSize({620, 560}, .FirstUseEver)
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .FirstUseEver, {0.5, 0.5})
	if imgui.Begin("Keyboard Shortcuts###ShortcutsWindow", &showShortcutsWindow, {.NoCollapse, .NoDocking}) {
		@(static) filter: [128]u8
		imgui.SetNextItemWidth(-1)
		imgui.InputTextWithHint("##sc_filter", "Filter", cstring(raw_data(filter[:])), len(filter), {})
		q := strings.to_lower(string(cstring(raw_data(filter[:]))), context.temp_allocator)
		if imgui.BeginTable("##shortcuts", 3, imgui.TableFlags_SizingStretchProp | imgui.TableFlags_RowBg) {
			imgui.TableSetupColumn("Command", {.WidthStretch}, 0.5)
			imgui.TableSetupColumn("Shortcut", {.WidthStretch}, 0.35)
			imgui.TableSetupColumn("Where", {.WidthStretch}, 0.15)
			imgui.TableHeadersRow()
			for &a in GlobalActions {
				name := fmt.tprintf("%s: %s", a.category, a.label)
				keys := Action_AllShortcutsText(&a)
				if q != "" && !strings.contains(strings.to_lower(name, context.temp_allocator), q) && !strings.contains(strings.to_lower(keys, context.temp_allocator), q) do continue
				imgui.TableNextRow()
				imgui.TableNextColumn()
				imgui.TextUnformatted(strings.clone_to_cstring(name, context.temp_allocator))
				imgui.TableNextColumn()
				imgui.PushStyleColorImVec4(.Text, UI_ACCENT)
				imgui.TextUnformatted(strings.clone_to_cstring(keys, context.temp_allocator))
				imgui.PopStyleColor()
				imgui.TableNextColumn()
				UI_DimText(fmt.tprint(a.scope))
			}
			imgui.EndTable()
		}
	}
	imgui.End()
}
