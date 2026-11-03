package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"
import e "../engine"

// ============================================================================
// Playtesting: run the project (or just the scene being edited) as a
// separate game process.
//
// Play always runs what is in the editor:
//   1. every modified scene is saved first (the game reads scene files);
//   2. the game is this platform's prebuilt runner (the one export ships;
//      no compiler needed). In a source checkout it's the engine's game
//      build instead, rebuilt first (`odin build .`, asynchronously, with
//      progress in the console) when an engine source is newer - so engine
//      changes are never silently ignored either;
//   3. the game starts with `--project <dir>` (+ `--scene <file>` for Play
//      Current Scene); its stdout/stderr stream into the editor console.
// ============================================================================

// Editor_GameBinary: the game Play runs (temp) - RAYZR_GAME_BIN (drives running
// beside another run use their own build), else in a source checkout the
// engine's game build (bin/rayzr), else this platform's
// prebuilt runner ("" = none).
Editor_GameBinary :: proc() -> string {
	if v := os.get_env("RAYZR_GAME_BIN", context.temp_allocator); v != "" do return v
	if Resources_InCheckout() do return Resource_Path("bin", "rayzr.exe" when ODIN_OS == .Windows else "rayzr")
	return Editor_FindRunner(e.native_export_target())
}
// The game build's sources (in a source checkout).
GAME_SOURCE_DIRS :: [?]string{".", "engine", "asteroids"}

Play_Mode :: enum {
	Project,      // the project's initial scene
	CurrentScene, // the scene open in the editor
}

// Editor_PlayRequest plays the project, or a scene (`scene`, else the one
// being edited) for .CurrentScene.
Editor_PlayRequest :: proc(state: ^EditorState, mode: Play_Mode, scene := "") {
	if state.gameProcessRunning {
		Editor_StopGameProcess(state)
	}
	if state.buildRunning {
		Editor_Log(state, .Warn, "Build already in progress...")
		return
	}

	// Plugins may stop it (validation: before_play returning false, reason).
	target := (scene if scene != "" else state.activeScenePath) if mode == .CurrentScene else state.projectConfig.initialScene
	if ok, reason := PluginEvents_Emit(state, "before_play", target); !ok {
		Editor_Log(state, .Warn, "Play cancelled: %s", reason)
		return
	}

	// 1. Save every modified scene so the game sees the editor's state.
	saved := Editor_SaveAllScenes(state)
	if saved > 0 {
		Editor_Log(state, .Info, "Saved %d modified scene(s) before playing", saved)
	}

	state.pendingPlayMode = mode
	delete(state.pendingPlayScene)
	state.pendingPlayScene = strings.clone(scene if scene != "" else state.activeScenePath) if mode == .CurrentScene else ""
	delete(state.lastPlayPackage)
	state.lastPlayPackage = ""

	// 2. Rebuild the game binary if sources changed since it was built.
	if reason, stale := Editor_GameBinaryIsStale(); stale && !state.skipGameBuild {
		Editor_Log(state, .Info, "Building game (%s)...", reason)
		if !Editor_StartGameBuild(state) {
			Editor_Log(state, .Error, "Could not start the build; launching the existing binary")
			Editor_LaunchGame(state)
		}
		return
	}
	Editor_LaunchGame(state)
}

// Editor_GameBinaryIsStale reports whether the game binary is missing or
// older than any .odin source it is built from.
// (Only in a source checkout: an installed editor plays its runner as is.)
Editor_GameBinaryIsStale :: proc() -> (reason: string, stale: bool) {
	if !Resources_InCheckout() do return "", false
	binInfo, err := os.stat(Editor_GameBinary(), context.temp_allocator)
	if err != nil do return "binary missing", true
	binTime := binInfo.modification_time
	for dir in GAME_SOURCE_DIRS {
		h, oerr := os.open(Resource_Path(dir))
		if oerr != nil do continue
		infos, _ := os.read_dir(h, -1, context.temp_allocator)
		os.close(h)
		for fi in infos {
			if fi.type == .Directory || !strings.has_suffix(fi.name, ".odin") || strings.has_suffix(fi.name, "_test.odin") do continue
			if time.diff(binTime, fi.modification_time) > 0 {
				return fmt.tprintf("%s changed", fi.name), true
			}
		}
	}
	return "", false
}

Editor_StartGameBuild :: proc(state: ^EditorState) -> bool {
	_ = os.make_directory(Resource_Path("bin"))
	return Editor_StartBuild(state, {"odin", "build", ".", strings.concatenate({"-out:", Editor_GameBinary()}, context.temp_allocator)}, .Game)
}

// Editor_StartBuild runs a build command in the background; its output
// streams into the console and `kind` decides what happens on success.
Editor_StartBuild :: proc(state: ^EditorState, command: []string, kind: Build_Kind) -> bool {
	if state.buildRunning do return false
	r, w, perr := os.pipe()
	if perr != nil do return false
	desc := os.Process_Desc{
		command = command,
		stdout  = w,
		stderr  = w,
		// (Builds only happen in a source checkout: its sources and scripts.)
		working_dir = editorResources.root if Resources_InCheckout() else "",
	}
	p, err := os.process_start(desc)
	os.close(w)
	if err != nil {
		os.close(r)
		return false
	}
	state.buildProcess = p
	state.buildOutput = r
	state.buildRunning = true
	state.buildKind = kind
	state.buildStarted = time.tick_now()
	return true
}

// Editor_UpdatePlaytest runs once per frame: streams build/game output into
// the console, finishes builds, and notices the game exiting.
Editor_UpdatePlaytest :: proc(state: ^EditorState) {
	if state.buildRunning {
		drain_pipe(state, &state.buildOutput, &state.buildLineBuf, "build")
		pstate, err := os.process_wait(state.buildProcess, 0)
		if err != .Timeout {
			drain_pipe(state, &state.buildOutput, &state.buildLineBuf, "build")
			if state.buildOutput != nil {
				os.close(state.buildOutput)
				state.buildOutput = nil
			}
			state.buildRunning = false
			secs := time.duration_seconds(time.tick_since(state.buildStarted))
			if err == nil && pstate.exit_code == 0 {
				Editor_Log(state, .Info, "Build succeeded in %.1fs", secs)
				switch state.buildKind {
				case .Game:       Editor_LaunchGame(state)
				case .Standalone: Editor_ExportStandalone(state, afterBuild = true, only = state.exportOnly) // the runner exists now
				case .Notarize:   Editor_Log(state, .Info, "Notarized and stapled: the app is ready to distribute")
				}
			} else {
				Editor_Log(state, .Error, "Build failed (exit %d) - see errors above; not launching", pstate.exit_code)
			}
		}
	}

	// Engine.quit() in Simulate stops the run, not the editor (the game is
	// the editor's own); elsewhere (the Lua line while editing) it's dropped.
	if state.game != nil && state.game.shouldQuit {
		state.game.shouldQuit = false
		if state.isSimulating {
			Editor_Log(state, .Info, "Engine.quit(): stopping the simulation (in the editor it ends the run, not the editor)")
			Toolbar_StopSimulation(state)
		}
	}

	if state.gameOutput != nil {
		drain_pipe(state, &state.gameOutput, &state.gameLineBuf, "game")
	}
	Editor_CheckGameProcess(state)
	RemoteGame_Update(state)
}

Editor_LaunchGame :: proc(state: ^EditorState) {
	exePath := Editor_GameBinary()
	if exePath == "" || !os.exists(exePath) {
		Editor_Log(state, .Error, "No %s runner to play the game with: it ships in runners/%s/ next to the editor (scripts/build_runners.sh builds one)", e.export_target_name(e.native_export_target()), e.export_target_name(e.native_export_target()))
		return
	}
	CodeRuntime_Clear() // the last run's script problems
	cmd := make([dynamic]string, context.temp_allocator)
	append(&cmd, exePath, "--project", state.projectPath, "--editor-link")
	if state.userDataDir != "" do append(&cmd, "--user-data", state.userDataDir)
	if slice.contains(os.args, "--hidden") do append(&cmd, "--hidden") // (a background test drive: the game hidden too)
	if state.pendingPlayScene != "" {
		append(&cmd, "--scene", state.pendingPlayScene)
	}
	for extra in state.extraGameArgs {
		append(&cmd, extra)
	}

	r, w, perr := os.pipe()
	// The game's stdin: the editor link's commands (remote_game.odin).
	inR, inW, ierr := os.pipe()
	desc := os.Process_Desc{command = cmd[:]}
	if perr == nil {
		desc.stdout = w
		desc.stderr = w
	}
	if ierr == nil do desc.stdin = inR
	procHandle, err := os.process_start(desc)
	if perr == nil do os.close(w)
	if ierr == nil do os.close(inR)
	if err != nil {
		if perr == nil do os.close(r)
		if ierr == nil do os.close(inW)
		Editor_Log(state, .Error, "Failed to launch game process: %v", err)
		return
	}
	if perr == nil do state.gameOutput = r
	if ierr == nil do RemoteGame_Attach(inW)

	state.gameProcess = procHandle
	state.gameProcessRunning = true
	delete(state.lastPlayedScene)
	state.lastPlayedScene = strings.clone(state.pendingPlayScene)
	state.hasPlayed = true
	what := state.pendingPlayScene if state.pendingPlayScene != "" else fmt.tprintf("project (initial scene %s)", state.projectConfig.initialScene)
	Editor_Log(state, .Info, "Playing %s - PID %d", what, procHandle.pid)
}

// drain_pipe moves whatever the process wrote into console lines.
@(private = "file")
drain_pipe :: proc(state: ^EditorState, f: ^^os.File, lineBuf: ^[dynamic]u8, source: string) {
	if f^ == nil do return
	for {
		has, err := os.pipe_has_data(f^)
		if err != nil || !has do break
		chunk: [4096]u8
		n, rerr := os.read(f^, chunk[:])
		if n <= 0 || rerr != nil {
			os.close(f^)
			f^ = nil
			break
		}
		append(lineBuf, ..chunk[:n])
	}
	// Emit complete lines.
	for {
		idx := -1
		for b, i in lineBuf {
			if b == '\n' {idx = i; break}
		}
		if idx < 0 do break
		line := strings.trim_right_space(string(lineBuf[:idx]))
		if source == "game" && RemoteGame_HandleLine(state, line) {
			remove_range(lineBuf, 0, idx + 1)
			continue
		}
		if line != "" {
			level := LogLevel.Info
			lower := strings.to_lower(line, context.temp_allocator)
			if strings.contains(lower, "error") do level = .Error
			else if strings.contains(lower, "warn") do level = .Warn
			Editor_Log(state, level, "[%s] %s", source, line)
			// A script problem: a squiggle on its line in the Code tab.
			if source == "game" && level != .Info do CodeRuntime_Report(line, level == .Warn)
		}
		remove_range(lineBuf, 0, idx + 1)
	}
	if f^ == nil && len(lineBuf) > 0 {
		Editor_Log(state, .Info, "[%s] %s", source, string(lineBuf[:]))
		clear(lineBuf)
	}
}

// ============================================================================
// Scene documents: open, modified tracking, save, save all.
// ============================================================================

// Editor_SetSceneBaseline marks the scene's current edit version as saved
// (after loading/saving). Modified = edited since (change tracking: no
// re-serializing; undoing back to the saved version is unmodified again).
Editor_SetSceneBaseline :: proc(state: ^EditorState, scene: ^e.Scene) {
	if scene == nil do return
	if old, ok := state.sceneBaselines[scene]; ok do delete(old)
	state.modifiedCacheFrames = 0
	state.modifiedCountFrames = 0
	state.sceneBaselines[scene] = ""
	state.savedVersion[scene] = state.sceneVersion[scene]
}

Editor_SceneIsModified :: proc(state: ^EditorState, scene: ^e.Scene) -> bool {
	if scene == nil || !scene.isLoaded do return false
	if _, ok := state.sceneBaselines[scene]; !ok do return true // never saved (new scene)
	return state.sceneVersion[scene] != state.savedVersion[scene]
}

// Editor_OpenScene makes a project scene file the active scene, loading it
// for editing the first time (later switches keep unsaved edits in memory).
Editor_OpenScene :: proc(state: ^EditorState, relPath: string) -> bool {
	game := state.game
	scene := e.Game_FindSceneByFile(game, relPath)
	if scene == nil {
		scene = e.Game_RegisterSceneFile(game, relPath)
	}
	if scene == nil {
		Editor_Log(state, .Error, "Scene file not found: %s", relPath)
		return false
	}
	if !scene.isLoaded {
		e.Scene_LoadForEditing(scene, &game.gameContext)
		Editor_SetSceneBaseline(state, scene)
	}
	Editor_SwitchView(state, scene)
	state.activeScene = scene
	game.sceneManager.currentScene = scene
	game.gameContext.scene = scene
	if state.activeScenePath != relPath {
		delete(state.activeScenePath)
		state.activeScenePath = strings.clone(relPath)
	}
	state.selectedNode = SceneTabs_SelectionFor(state, scene) // (what was selected when it was left)
	Editor_Log(state, .Info, "Opened scene %s", relPath)
	return true
}

// Editor_SaveSceneDocument writes one scene to its file.
Editor_SaveSceneDocument :: proc(state: ^EditorState, scene: ^e.Scene) -> bool {
	if scene == nil || scene.filePath == "" do return false
	if Editor_FormatBlocksSave(state, scene.filePath) do return false // (from a newer Rayzr: #326)
	if Editor_IsComponentDoc(state, scene) do return Editor_SaveComponentDoc(state, scene)
	jsonStr := e.Scene_SerializeToJSON(scene)
	defer delete(jsonStr)
	diskPath, _ := filepath.join({state.projectPath, scene.filePath}, context.temp_allocator)
	_ = os.make_directory_all(filepath.dir(diskPath, context.temp_allocator))
	Editor_InvalidateProjectFiles() // the asset lists rescan
	if os.write_entire_file(diskPath, transmute([]u8)jsonStr) != nil {
		Editor_Log(state, .Error, "Failed to write scene file: %s", diskPath)
		return false
	}
	// The scene's stored source becomes the saved file, so the game and any
	// reload see the same thing.
	scene.sourceJson = strings.clone(jsonStr, state.game.sceneManager.allocator)
	Editor_SetSceneBaseline(state, scene)
	// The running game picks the saved scene up (restarting it if current).
	if RemoteGame_Connected() do RemoteGame_Send(fmt.tprintf("reload-scene %s", scene.filePath))
	Editor_Log(state, .Info, "Saved %s", scene.filePath)
	_, _ = PluginEvents_Emit(state, "scene_saved", scene.filePath) // (plugin_events.odin)
	return true
}

// Editor_SaveAllScenes saves every loaded scene with unsaved changes.
Editor_SaveAllScenes :: proc(state: ^EditorState) -> int {
	n := 0
	for _, scene in state.game.sceneManager.scenes {
		if scene != nil && scene.filePath != "" && Editor_SceneIsModified(state, scene) {
			if Editor_SaveSceneDocument(state, scene) do n += 1
		}
	}
	return n
}

Editor_ModifiedSceneCount :: proc(state: ^EditorState) -> int {
	n := 0
	for _, scene in state.game.sceneManager.scenes {
		if scene != nil && scene.filePath != "" && Editor_SceneIsModified(state, scene) do n += 1
	}
	return n
}

// Editor_NewScene creates scenes/<name>.scene.json (unique), adds it to
// project.json and opens it.
Editor_NewScene :: proc(state: ^EditorState, baseName: string = "new_scene") -> bool {
	rel := ""
	for i := 0; ; i += 1 {
		name := baseName if i == 0 else fmt.tprintf("%s_%d", baseName, i + 1)
		rel = fmt.tprintf("scenes/%s.scene.json", name)
		disk, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		if !os.exists(disk) && e.Game_FindSceneByFile(state.game, rel) == nil do break
	}
	stem := filepath.stem(filepath.stem(rel))
	contents := fmt.tprintf(`{{"name": "%s", "root": {{"type": "Node", "name": "root", "children": [{{"type": "CameraNode", "name": "Camera", "position": [%v, %v]}}]}}}}`,
		stem, state.projectConfig.virtualWidth * 0.5, state.projectConfig.virtualHeight * 0.5)
	disk, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	_ = os.make_directory_all(filepath.dir(disk, context.temp_allocator))
	Editor_InvalidateProjectFiles() // the asset lists rescan
	if os.write_entire_file(disk, transmute([]u8)contents) != nil {
		Editor_Log(state, .Error, "Could not create %s", disk)
		return false
	}
	append(&state.projectConfig.scenes, strings.clone(rel))
	e.Project_SaveConfigToFile(state.projectPath, &state.projectConfig)
	return Editor_OpenScene(state, rel)
}

// (Version checks are cheap; the Cached variants remain for callers.)
Editor_SceneIsModifiedCached :: proc(state: ^EditorState, scene: ^e.Scene) -> bool {
	return Editor_SceneIsModified(state, scene)
}

Editor_ModifiedSceneCountCached :: proc(state: ^EditorState) -> int {
	return Editor_ModifiedSceneCount(state)
}

// Editor_SwitchView remembers the camera of the current document and
// restores the one of `next` (first visit: keep the current view).
Editor_SwitchView :: proc(state: ^EditorState, next: ^e.Scene) {
	if state.activeScene != nil && state.activeScene != next {
		state.sceneViews[state.activeScene] = {state.cameraPos.x, state.cameraPos.y, state.cameraZoom}
		SceneTabs_RememberSelection(state) // (each tab keeps its selection)
	}
	if v, ok := state.sceneViews[next]; ok {
		state.cameraPos = {v[0], v[1]}
		state.cameraZoom = v[2]
	}
}

// Editor_OpenExternally opens a file with its default application (LDtk for
// .ldtk files, the OS image viewer, ...).
Editor_OpenExternally :: proc(state: ^EditorState, path: string) {
	when ODIN_OS == .Darwin {
		cmd := []string{"open", path}
	} else when ODIN_OS == .Windows {
		cmd := []string{"cmd", "/c", "start", "", path}
	} else {
		cmd := []string{"xdg-open", path}
	}
	if _, err := os.process_start({command = cmd}); err != nil {
		Editor_Log(state, .Error, "Could not open %s: %v", path, err)
	}
}

// Editor_OpenSaveDataFolder opens the folder the game's Save data goes in
// (created if needed).
Editor_OpenSaveDataFolder :: proc(state: ^EditorState) {
	dir := e.Save_UserDataDir(state.projectConfig.name)
	_ = os.make_directory_all(dir)
	Editor_OpenExternally(state, dir)
}

// Editor_DeleteSaveData removes the game's save files (*.json) so the next
// run starts fresh.
Editor_DeleteSaveData :: proc(state: ^EditorState) {
	dir := e.Save_UserDataDir(state.projectConfig.name)
	files, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		Editor_Log(state, .Info, "No save data in %s", dir)
		return
	}
	n := 0
	for f in files {
		if f.type != .Regular || !strings.has_suffix(f.name, ".json") do continue
		if os.remove(f.fullpath) == nil do n += 1
	}
	if state.game != nil && state.game.scriptManager.isReady do e.Save_Forget(state.game.scriptManager.L)
	Editor_Log(state, .Info, "Deleted %d save file(s) in %s", n, dir)
}

// Editor_RunPackage plays an exported .rayzr with the game runner.
Editor_RunPackage :: proc(state: ^EditorState, pkgPath: string) {
	if state.gameProcessRunning do return
	saved := state.projectPath
	state.projectPath = pkgPath
	delete(state.pendingPlayScene)
	state.pendingPlayScene = ""
	Editor_LaunchGame(state)
	state.projectPath = saved
	delete(state.lastPlayPackage)
	state.lastPlayPackage = strings.clone(pkgPath)
}

// Editor_RestartGame stops the game and plays the same thing again (the
// project, the same scene, or the same package) - saving and rebuilding
// first like Play. With nothing played yet, it plays the project.
Editor_RestartGame :: proc(state: ^EditorState) {
	if state.buildRunning do return
	scene := strings.clone(state.lastPlayedScene, context.temp_allocator)
	pkg := strings.clone(state.lastPlayPackage, context.temp_allocator)
	if state.gameProcessRunning do Editor_StopGameProcess(state)
	Editor_Log(state, .Info, "Restarting the game")
	switch {
	case pkg != "":   Editor_RunPackage(state, pkg)
	case scene != "": Editor_PlayRequest(state, .CurrentScene, scene)
	case:             Editor_PlayRequest(state, .Project)
	}
}

// Editor_ToggleGameColliders flips the project's Show Colliders setting
// (physics.debug_draw): saved in project.json, applied to a running game.
Editor_ToggleGameColliders :: proc(state: ^EditorState) {
	state.projectConfig.debugDraw = !state.projectConfig.debugDraw
	on := state.projectConfig.debugDraw
	if !e.Project_SaveConfigToFile(state.projectPath, &state.projectConfig) {
		Editor_Log(state, .Error, "Could not save project.json")
	}
	if RemoteGame_Connected() do RemoteGame_Send(fmt.tprintf("debug-draw %t", on))
	Editor_Log(state, .Info, "Colliders %s in the game", "shown" if on else "hidden")
}

// Editor_TogglePause pauses / resumes the running game (editor link).
Editor_TogglePause :: proc(state: ^EditorState) {
	if !RemoteGame_Connected() do return
	RemoteGame_Send("resume" if RemoteGame_Paused() else "pause")
}

// Editor_StepGame runs one frame of the paused game.
Editor_StepGame :: proc(state: ^EditorState) {
	if !RemoteGame_Connected() do return
	if !RemoteGame_Paused() do RemoteGame_Send("pause")
	RemoteGame_Send("step 1")
}
