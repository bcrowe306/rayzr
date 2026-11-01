package editor

import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import e "../engine"

// ============================================================================
// Editor Core State & Data Types
// ============================================================================

ToolMode :: enum {
	Select = 0,
	Translate,
	Rotate,
	Scale,
	Pan,
}

GizmoHandle :: enum {
	None = 0,
	TranslateX,
	TranslateY,
	TranslateCenter,
	RotateRing,
	ScaleCorner,
	ScaleX,
	ScaleY,
}

BottomTab :: enum {
	Console = 0,
	Output,
	Profiler,
	Animation,
	Game,
	Particles,
	Ldtk,
	Search, // find in files (code_search.odin)
	StateGraph, // state machine graph (state_machine_graph.odin)
	Mixer,      // audio mixer console (mixer_panel.odin)
	TileMap,    // tile map painting: settings, tools, tiles (tilemap_editor.odin)
	Files,      // the File Browser: the computer's files, previewed and loaded (file_browser.odin)
	Tests,      // the project's tests: run, results, failures (tests_panel.odin)
	BehaviorTree, // a Behavior Tree node's tree (behavior_tree_editor.odin)
}

ViewportTab :: enum {
	SceneViewport = 0,
	ComponentViewport,
}

Build_Kind :: enum {
	Game,       // the game binary for Play (launches it)
	Standalone, // the runner for an exported standalone game
	Notarize,   // notarizing an exported macOS app
}

Drag_Start :: struct {
	node:       ^e.Node,
	startPos:   [2]f32, // world
	startRot:   f32,
	startScale: [2]f32,
}

LogLevel :: enum {
	Info = 0,
	Warn,
	Error,
}

LogEntry :: struct {
	time:    string,
	level:   LogLevel,
	message: string,
}

PreviewPanelTab :: enum {
	Texture,
	Audio,
	Animation,
	Scene,
	Script,
}

EditorState :: struct {
	// Project & Game
	game:              ^e.Game,
	projectConfig:     e.ProjectConfig,
	userDataDir:        string, // --user-data: where save data goes ("" = the player's folder)
	webExportDir:       string, // the last Web export (Game > Open Web Export in Browser)
	projectPath:       string,
	projectLoaded:     bool,
	activeScenePath:   string,
	activeScene:       ^e.Scene,
	selectedNode:      ^e.Node,
	selectedAssetPath: string,
	selectedAssetPaths: [dynamic]string,
	assetAnchorPath:    string,

	// Separate Game Process Management (see playtest.odin)
	gameProcess:        os.Process,
	gameProcessRunning: bool,
	showProjectSettings: bool,
	pendingPlayMode:    Play_Mode,
	pendingPlayScene:   string,
	lastPlayedScene:    string, // what Restart plays again ("" = the project)
	lastPlayPackage:    string, // an exported .rayzr played last (Restart replays it)
	hasPlayed:          bool,
	gameOutput:         ^os.File,
	gameLineBuf:        [dynamic]u8,
	buildProcess:       os.Process,
	buildOutput:        ^os.File,
	buildLineBuf:       [dynamic]u8,
	buildRunning:       bool,
	buildKind:          Build_Kind, // what to do when the build succeeds
	exportDir:          string,     // standalone export folder (owned)
	exportOnly:         int,        // the preset being exported (-1 = all), for after the runner build
	buildStarted:       time.Tick,
	skipGameBuild:      bool,             // --no-build: never rebuild before Play
	extraGameArgs:      [dynamic]string,  // appended to the game command line (tests)

	// Saved state of each open scene; a scene is modified when it differs.
	sceneBaselines:     map[^e.Scene]string, // presence = the scene has a file state ("" values)
	// Edit versions (scene_edit_ops.odin): every recorded edit bumps the
	// scene's version; a scene is modified when it differs from the saved one.
	sceneVersion:       map[^e.Scene]int,
	savedVersion:       map[^e.Scene]int,
	nextVersion:        int,
	componentDocs:      map[^e.Scene]bool, // open component (prefab) documents
	sceneViews:         map[^e.Scene][3]f32, // remembered camera x, y, zoom per document
	modifiedCacheScene:  ^e.Scene,
	modifiedCacheValue:  bool,
	modifiedCacheFrames: int,
	modifiedCountValue:  int,
	modifiedCountFrames: int,
	quitRequested:      bool, // asks about unsaved work (QuitPrompt_Render)
	quitConfirmed:      bool, // leave the main loop
	pendingProject:     string, // reopen the editor on this project after quitting
	undoStack:          [dynamic]Undo_Entry,
	redoStack:          [dynamic]Undo_Entry,
	undoGeneration:     int, // undo / redo restores so far (auto-key skips their changes)
	// The Inspector shows the selected resource asset (inspector_resource.odin)
	// while this is set and the node selection hasn't changed since.
	inspectResource:     bool,
	inspectResourceNode: ^e.Node,

	// Tools & Viewport
	toolMode:         ToolMode,
	activeHandle:     GizmoHandle,
	viewportTab:      ViewportTab,
	bottomTab:        BottomTab,
	cameraPos:        [2]f32,
	cameraZoom:       f32,
	renderTexture:    rl.RenderTexture2D,
	viewportSize:     [2]f32,
	viewportPos:      [2]f32, // Screen position of viewport image in ImGui window
	viewportHovered:  bool,
	viewportFocused:  bool,
	viewportDockId:   u32, // dock node of the Viewport (the Code tab joins it)
	// Multi-selection (selectedNode is the primary; see scene_selection.odin).
	selection:        [dynamic]^e.Node,
	boxSelecting:     bool,
	boxStart:         [2]f32,
	dragOthers:       [dynamic]Drag_Start,

	// Dragging / Gizmo interaction
	isDraggingGizmo:  bool,
	dragStartMouse:   [2]f32,
	dragStartPos:     [2]f32,
	dragStartRot:     f32,
	dragStartScale:   [2]f32,

	// Simulation
	isSimulating:     bool,
	isPaused:         bool,
	snapshotJson:     string, // Serialized scene JSON before simulation started

	// Snapping & Overlays
	snapGrid:         bool,
	gridSize:         f32,
	snapRotation:     bool,
	showInspectorHelp: bool, // the Inspector's help pane (View menu)
	showRulers:       bool, // rulers and guides (viewport_tools.odin)
	smartSnap:        bool, // snap moves to other nodes' edges / centres and guides
	showAllColliders: bool, // every collision shape, even with physics debug drawing off
	rotationSnapStep: f32,
	showBounds:       bool,
	showGrid:         bool,
	showCameraBounds: bool,

	// Console & Logs
	logs:             [dynamic]LogEntry,
	consoleFilter:    [64]u8,
	consoleAutoScroll: bool,

	// Reusable Components / Prefabs

	// Status info
	statusText:       string,
	fpsHistory:       [60]f32,
	fpsIdx:           int,

	// Preview Panel State
	previewTab:            PreviewPanelTab,
	previewAutoSwitch:     bool,

	// Texture Preview State
	previewTexture:        rl.Texture,
	previewTextureLoaded:  bool,
	previewTexturePath:    string,
	previewTextureZoom:    f32,
	previewTextureFit:     bool,

	// Audio Preview State
	previewSound:          rl.Sound,
	previewSoundLoaded:    bool,
	previewSoundPath:      string,
	previewAudioPlaying:   bool,
	previewAudioTimer:     f32,
	previewAudioDuration:  f32,

	// Animation Preview State
	previewAnimFrames:     [dynamic]rl.Texture,
	previewAnimDurations:  [dynamic]f32, // each frame's time (Aseprite / GIF files; else the FPS)
	previewAnimPaths:      [dynamic]string,
	previewAnimPlaying:    bool,
	previewAnimIndex:      int,
	previewAnimTimer:      f32,
	previewAnimFPS:        f32,
	previewAnimLoadedPath: string,

	// Selected Scene/Script Preview overrides
	previewScenePath:      string,
	previewScriptPath:     string,
}

GlobalEditor: EditorState

Editor_Init :: proc(state: ^EditorState) {
	state.game = new(e.Game)
	e.InitializeGame(state.game)
	state.game.inEditor = true // (on-screen touch controls show while editing)

	state.projectPath = ""
	if !slice.contains(os.args, "--project") do state.projectPath = strings.clone(Resources_DefaultProject()) // (resources.odin)
	for i := 0; i < len(os.args); i += 1 {
		if os.args[i] == "--project" && i + 1 < len(os.args) do state.projectPath = os.args[i + 1]
		if os.args[i] == "--no-build" do state.skipGameBuild = true
		// --user-data <dir>: save data (Save, accessibility, bindings) goes
		// there, also for the game started with Play - test drives keep the
		// player's real folders untouched.
		if os.args[i] == "--user-data" && i + 1 < len(os.args) {
			state.userDataDir = strings.clone(os.args[i + 1])
			e.Save_SetDirectory(state.userDataDir)
		}
	}
	// A project from before the rename: its .ore/ folder becomes .rayzr/.
	e.Project_MigrateLegacyDir(state.projectPath)
	state.sceneBaselines = make(map[^e.Scene]string)
	state.sceneVersion = make(map[^e.Scene]int)
	state.savedVersion = make(map[^e.Scene]int)
	state.toolMode = .Select
	state.activeHandle = .None
	state.viewportTab = .SceneViewport
	state.bottomTab = .Console
	state.cameraPos = {640.0, 360.0}
	state.cameraZoom = 1.0
	state.snapGrid = true
	state.gridSize = 32.0
	state.snapRotation = false
	state.showInspectorHelp = true
	state.showRulers = true
	state.smartSnap = true
	state.rotationSnapStep = 15.0
	state.showBounds = false
	state.showGrid = true
	state.showCameraBounds = true
	state.consoleAutoScroll = true

	state.previewTab = .Texture
	state.previewAutoSwitch = true
	state.previewTextureZoom = 1.0
	state.previewTextureFit = true
	state.previewAnimPlaying = true
	state.previewAnimFPS = 12.0
	state.previewAnimFrames = make([dynamic]rl.Texture)
	state.previewAnimPaths = make([dynamic]string)
	state.statusText = "Ready"
	state.gameProcessRunning = false
	state.showProjectSettings = false

	state.logs = make([dynamic]LogEntry)

	// Create initial render texture
	state.viewportSize = {1280, 720}
	state.renderTexture = rl.LoadRenderTexture(1280, 720)

	// Load the project for editing: scenes are registered but no gameplay
	// code runs (no ready(), no scripts) until you Play.
	if cfg, ok := e.Game_LoadProjectForEditing(state.game, state.projectPath); ok {
		state.projectConfig = cfg
		state.projectLoaded = true
		Editor_Log(state, .Info, "Loaded project: %s", state.projectPath)
		initial := cfg.initialScene
		if e.Game_FindSceneByFile(state.game, initial) == nil && len(cfg.scenes) > 0 {
			initial = cfg.scenes[0]
		}
		if !Editor_OpenScene(state, initial) {
			state.activeScene = state.game->createScene("DefaultScene", true, nil)
		}
		SceneTabs_Restore(state) // the last session's tabs (scene_tabs.odin)
	} else {
		// Fallback empty scene
		state.activeScene = state.game->createScene("DefaultScene", true, nil)
		Editor_Log(state, .Warn, "No project found at %s, initialized empty scene", state.projectPath)
	}

	// Lua event handlers only run while simulating (or in the game).
	state.game.scriptManager.suspended = true
	Editor_Log(state, .Info, "Rayzr GUI Editor initialized")
}

Editor_Shutdown :: proc(state: ^EditorState) {
	e.scriptLogSink = nil // scripts may still log while the game shuts down below
	SceneTabs_Shutdown(state) // (writes the open tabs)
	LevelEditor_Shutdown()
	LevelRef_Shutdown()
	NodeReference_Shutdown()
	FileBrowser_Shutdown()
	LevelGenEditor_Shutdown()
	TerrainEditor_Shutdown()
	TileAnimEditor_Shutdown()
	TestsPanel_Shutdown()
	NormalGen_Close()
	LevelRules_Shutdown()
	LevelLayers_Shutdown()
	LevelEnums_Shutdown()
	LevelCommands_Shutdown()
	LevelExtras_Shutdown()
	LevelTilesets_Shutdown()
	WebServer_Stop()
	Code_Shutdown()
	Palette_Shutdown()
	AnimationPanel_Shutdown()
	InspectorFields_Shutdown()
	PreviewPanel_Shutdown(state)
	delete(state.selection)
	delete(state.dragOthers)
	delete(state.selectedAssetPath)
	delete(state.assetAnchorPath)
	for p in state.selectedAssetPaths do delete(p)
	delete(state.selectedAssetPaths)
	AssetActions_Shutdown()
	if state.gameProcessRunning {
		Editor_StopGameProcess(state)
	}

	e.ProjectConfig_Destroy(&state.projectConfig)

	if state.renderTexture.id != 0 {
		rl.UnloadRenderTexture(state.renderTexture)
	}

	for &log in state.logs {
		delete(log.time)
		delete(log.message)
	}
	delete(state.logs)

	if state.snapshotJson != "" {
		delete(state.snapshotJson)
	}

	if state.game != nil {
		state.game->terminate()
	}
}

Editor_CheckGameProcess :: proc(state: ^EditorState) {
	if !state.gameProcessRunning do return
	pState, err := os.process_wait(state.gameProcess, 0)
	if err == .Timeout {
		// Child is still actively running
		return
	}
	state.gameProcessRunning = false
	RemoteGame_Detach()
	Editor_Log(state, .Info, "Game process exited (exit code: %d)", pState.exit_code)
}

// Editor_PlayGameProcess toggles the game: stop if running, else Play the
// project (saving and rebuilding first as needed, see playtest.odin).
Editor_PlayGameProcess :: proc(state: ^EditorState, mode: Play_Mode = .Project) {
	if state.gameProcessRunning {
		Editor_StopGameProcess(state)
		return
	}
	Editor_PlayRequest(state, mode)
}

Editor_StopGameProcess :: proc(state: ^EditorState) {
	if !state.gameProcessRunning do return
	_ = os.process_terminate(state.gameProcess)
	time.sleep(50 * time.Millisecond)
	_, err := os.process_wait(state.gameProcess, 0)
	if err == .Timeout {
		_ = os.process_kill(state.gameProcess)
	}
	state.gameProcessRunning = false
	RemoteGame_Detach()
	Editor_Log(state, .Info, "Game process stopped.")
}

Editor_Log :: proc(state: ^EditorState, level: LogLevel, format: string, args: ..any) {
	msg := fmt.tprintf(format, ..args)
	e.Crash_Note(fmt.tprintf("[%v] %s", level, msg)) // (a crash report's recent lines)
	now := time.now()
	h, m, s := time.clock(now)
	timeStr := fmt.tprintf("%02d:%02d:%02d", h, m, s)

	append(&state.logs, LogEntry{
		time    = strings.clone(timeStr),
		level   = level,
		message = strings.clone(msg),
	})

	if len(state.logs) > 500 {
		old := pop_front(&state.logs)
		delete(old.time)
		delete(old.message)
	}
}

