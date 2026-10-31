package editor

import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import "winres"

// ============================================================================
// Standalone export: each export preset (Project Settings > Export; one per
// selected platform when there are none) writes a folder with a prebuilt
// runner (renamed to the game), game.rayzr and the UI font - no compiler
// needed. Runners come with the editor in runners/<platform>/ (next to the
// editor, or bin/runners/ in a source checkout; scripts/build_runners.sh
// builds the current platform's, release and debug). Without one for this
// platform the editor builds it once (needs `odin`) and then exports.
//
// A preset's folder (<output>/<preset name> unless it sets one):
//   Windows  <Name>.exe (+ the runner's libraries), game.rayzr, fonts/
//   macOS    <Name>.app                (export_macos.odin)
//   Linux    <Name>.AppDir             (+ <Name>-<arch>.AppImage with appimagetool)
//
// The packaged project.json carries the preset's overrides (version, icon,
// window), and only the files the preset includes go into game.rayzr.
// Windows: the exe gets the icon and version info (written with the Win32
// resource API, so when exporting on Windows); release runners have no
// console window.
// ============================================================================

RUNNER_FONT :: "OpenSans-Regular.ttf"

runner_file_name :: proc(t: e.Export_Target, debug := false) -> string {
	if t == .Web do return "index.wasm" // (one web runner: index.html / .js / .wasm + odin.js)
	if t == .Android do return "libmain.so" // (NativeActivity's library; export_android.odin)
	base := "runner-debug" if debug else "runner"
	return strings.concatenate({base, ".exe"}, context.temp_allocator) if t == .Windows else base
}

// Editor_RunnersDirs: where prebuilt runners are looked for, in order.
Editor_RunnersDirs :: proc() -> []string {
	out := make([dynamic]string, context.temp_allocator)
	exeDir := filepath.dir(os.args[0], context.temp_allocator)
	if !filepath.is_abs(exeDir) {
		if abs, err := os.get_absolute_path(exeDir, context.temp_allocator); err == nil do exeDir = abs
	}
	add :: proc(out: ^[dynamic]string, parts: ..string) {
		p, _ := filepath.join(parts, context.temp_allocator)
		for q in out do if q == p do return
		append(out, p)
	}
	add(&out, Resources_RunnersDir())                                   // this editor's (resources.odin)
	add(&out, exeDir, "runners")                                        // shipped editor
	add(&out, filepath.dir(exeDir, context.temp_allocator), "runners") // macOS .app: Contents/MacOS/..
	add(&out, exeDir, "bin", "runners")                                 // editor binary at the repo root
	if cwd, err := os.get_working_directory(context.temp_allocator); err == nil do add(&out, cwd, "bin", "runners")
	return out[:]
}

// Editor_FindRunner: the prebuilt runner for a platform ("" = none).
Editor_FindRunner :: proc(t: e.Export_Target, debug := false) -> string {
	for dir in Editor_RunnersDirs() {
		p, _ := filepath.join({dir, e.export_target_name(t), runner_file_name(t, debug)}, context.temp_allocator)
		if os.is_file(p) do return p
	}
	return ""
}

// runner_libraries: the shared libraries shipped with a runner (the other
// files in its folder, not the runners themselves).
runner_libraries :: proc(runner: string) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	infos, err := os.read_all_directory_by_path(filepath.dir(runner, context.temp_allocator), context.temp_allocator)
	if err != nil do return out[:]
	for f in infos {
		if f.type != .Regular || strings.has_prefix(f.name, ".") || strings.has_prefix(f.name, "runner") do continue
		append(&out, f.fullpath)
	}
	return out[:]
}

NOTICES_FILE :: "THIRD_PARTY_NOTICES.txt"

// runner_notices: the third-party notices shipped with the runners (or the
// checkout's licenses/) - "" when missing.
runner_notices :: proc(runner: string) -> string {
	p, _ := filepath.join({filepath.dir(filepath.dir(runner, context.temp_allocator), context.temp_allocator), NOTICES_FILE}, context.temp_allocator)
	if os.is_file(p) do return p
	if dev := Resource_Path("licenses", NOTICES_FILE); os.is_file(dev) do return dev
	return ""
}

// runner_font: the UI font shipped with runners (or the engine's copy).
runner_font :: proc(runner: string) -> string {
	p, _ := filepath.join({filepath.dir(filepath.dir(runner, context.temp_allocator), context.temp_allocator), RUNNER_FONT}, context.temp_allocator)
	if os.is_file(p) do return p
	if f := Resources_EngineFont(); os.is_file(f) do return f
	return ""
}

// export_safe_name: a preset name as a folder name.
export_safe_name :: proc(name: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	for r in strings.trim_space(name) {
		ok := (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-' || r == '_' || r == '.'
		strings.write_rune(&sb, r if ok else '_')
	}
	s := strings.to_string(sb)
	return s if s != "" else "export"
}

// Editor_ExportStandalone exports every preset (or one: `only` >= 0);
// afterBuild: called back once this platform's runner was built.
Editor_ExportStandalone :: proc(state: ^EditorState, afterBuild := false, only := -1) {
	if state.buildRunning {
		Editor_Log(state, .Warn, "A build is already running")
		return
	}
	Editor_SaveAllScenes(state)
	Code_SaveAll(state)
	cfg := &state.projectConfig
	x := &cfg.export
	clean := strings.trim_suffix(state.projectPath, "/")
	outDir := x.outputDir if x.outputDir != "" else strings.concatenate({clean, "_standalone"}, context.temp_allocator)
	presets := e.Export_EffectivePresets(x)
	if only >= 0 && only < len(presets) do presets = presets[only:only + 1]
	state.exportOnly = only

	// This platform's runner is built once when it isn't there yet.
	native := e.native_export_target()
	needsNative := false
	for &p in presets do if p.target == native && Editor_FindRunner(native) == "" do needsNative = true
	if needsNative {
		if afterBuild {
			Editor_Log(state, .Error, "The runner was built but isn't in any of: %s", strings.join(Editor_RunnersDirs(), ", ", context.temp_allocator))
			return
		}
		if !Resources_InCheckout() {
			Editor_Log(state, .Error, "No %s runner: it ships in runners/%s/ next to the editor - reinstall the editor", e.export_target_name(native), e.export_target_name(native))
			return
		}
		dst := Resource_Path("bin", "runners", e.export_target_name(native), runner_file_name(native))
		_ = os.make_directory_all(filepath.dir(dst, context.temp_allocator))
		// The script also builds the debug runner and ships the runner's
		// libraries (Lua on macOS / Windows). (Builds run in the checkout.)
		cmd := []string{"bash", "scripts/build_runners.sh"} if os.is_file(Resource_Path("scripts", "build_runners.sh")) else []string{"odin", "build", "runner", "-o:speed", strings.concatenate({"-out:", dst}, context.temp_allocator)}
		if !Editor_StartBuild(state, cmd, .Standalone) {
			Editor_Log(state, .Error, "No prebuilt %s runner, and it couldn't be built (is `odin` on PATH?)", e.export_target_name(native))
			return
		}
		Editor_Log(state, .Info, "No prebuilt %s runner: building it once (later exports reuse it)...", e.export_target_name(native))
		return // Editor_UpdatePlaytest calls back when the build succeeds
	}

	exported := 0
	for &p in presets {
		if dir, ok := export_preset(state, &p, outDir); ok {
			Editor_Log(state, .Info, "Exported %s (%s%s): %s", p.name, e.export_target_name(p.target), ", debug" if p.debug else "", dir)
			_, _ = PluginEvents_Emit(state, "after_export", p.name, dir) // (plugin_events.odin)
			exported += 1
		}
	}
	if state.exportDir != "" do delete(state.exportDir)
	state.exportDir = strings.clone(outDir)
	if exported > 0 {
		Editor_Log(state, .Info, "Standalone game ready: %s (%d preset(s))", outDir, exported)
		Editor_RememberDir(.Export, outDir, true)
	}
}

@(private = "file")
// The icon of exported games that have none: Rayzr's (editor/assets/icon.png),
// written into the project's hidden folder when exporting.
DEFAULT_ICON :: ".rayzr/default_icon.png"
@(private = "file")
DEFAULT_ICON_PNG :: #load("assets/icon.png")

@(private = "file")
export_default_icon :: proc(projectPath: string) -> bool {
	path, _ := filepath.join({projectPath, DEFAULT_ICON}, context.temp_allocator)
	_ = os.make_directory_all(filepath.dir(path, context.temp_allocator))
	return os.write_entire_file(path, DEFAULT_ICON_PNG) == nil
}

export_preset :: proc(state: ^EditorState, p: ^e.Export_Preset, outDir: string) -> (string, bool) {
	cfg := &state.projectConfig
	t := p.target
	runner := Editor_FindRunner(t, p.debug)
	if runner == "" && p.debug {
		runner = Editor_FindRunner(t)
		if runner != "" do Editor_Log(state, .Warn, "%s: no debug runner for %s, using the release one", p.name, e.export_target_name(t))
	}
	if runner == "" {
		Editor_Log(state, .Warn, "%s: no %s runner - build one on %s (scripts/build_runners.sh) and put it in runners/%s/ next to the editor", p.name, e.export_target_name(t), e.export_target_name(t), e.export_target_name(t))
		return "", false
	}
	name := p.executableName if p.executableName != "" else (cfg.export.executableName if cfg.export.executableName != "" else export_default_name(cfg))
	dir := p.outputDir
	if dir == "" do dir, _ = filepath.join({outDir, export_safe_name(p.name)}, context.temp_allocator)
	_ = os.make_directory_all(dir)

	// The preset's package: its files and its project.json.
	pc := e.Export_PresetConfig(cfg, p)
	overrides := make(map[string][]u8, context.temp_allocator)
	overrides["project.json"] = transmute([]u8)e.Project_SerializeToJSON(&pc, context.temp_allocator)
	rayzr, _ := filepath.join({dir, ".game.rayzr.tmp"}, context.temp_allocator)
	filter :: proc(path: string, data: rawptr) -> bool {return e.Export_PresetIncludes(cast(^e.Export_Preset)data, path)}
	if n := e.Asset_ExportOverrides(state.projectPath, &overrides, filter, p, context.temp_allocator); n > 0 {
		Editor_Log(state, .Info, "%s: %d texture(s) stored as QOI (import settings)", p.name, n)
	}
	if sprites, pages := e.Atlas_Build(state.projectPath, &overrides, filter, p, context.temp_allocator); sprites > 0 {
		Editor_Log(state, .Info, "%s: %d texture(s) packed into %d atlas page(s)", p.name, sprites, pages)
	}
	if !e.RayzrPackage_CreateFromDirectory(state.projectPath, rayzr, cfg.export.compress, filter, p, overrides) {
		Editor_Log(state, .Error, "Failed to package the project into %s", rayzr)
		return "", false
	}
	defer os.remove(rayzr)
	// The third-party notices the engine's licenses ask for (Lua, Box2D, ...),
	// next to what was exported.
	if notices := runner_notices(runner); notices != "" {
		dst, _ := filepath.join({dir, NOTICES_FILE}, context.temp_allocator)
		_ = os.copy_file(dst, notices)
	}

	// No icon of its own: the engine's (the app, the .exe, the AppImage, the page).
	if pc.icon == "" && export_default_icon(state.projectPath) do pc.icon = DEFAULT_ICON

	switch t {
	case .MacOS:   return Export_MacApp(state, &pc, runner, rayzr, dir, name)
	case .Linux:   return export_linux(state, &pc, runner, rayzr, dir, name)
	case .Windows: return export_windows(state, &pc, runner, rayzr, dir, name)
	case .Web:     return export_web(state, &pc, runner, rayzr, dir, name)
	case .Android: return export_android(state, &pc, runner, rayzr, dir, name)
	}
	return "", false
}

@(private = "file")
export_windows :: proc(state: ^EditorState, cfg: ^e.ProjectConfig, runner, rayzr, dir, name: string) -> (string, bool) {
	exe, _ := filepath.join({dir, strings.concatenate({name, ".exe"}, context.temp_allocator)}, context.temp_allocator)
	if err := os.copy_file(exe, runner); err != nil {
		Editor_Log(state, .Error, "Could not copy the runner to %s: %v", exe, err)
		return "", false
	}
	for lib in runner_libraries(runner) {
		dst, _ := filepath.join({dir, filepath.base(lib)}, context.temp_allocator)
		_ = os.copy_file(dst, lib)
	}
	dstRayzr, _ := filepath.join({dir, "game.rayzr"}, context.temp_allocator)
	if err := os.copy_file(dstRayzr, rayzr); err != nil {
		Editor_Log(state, .Error, "Could not write %s: %v", dstRayzr, err)
		return "", false
	}
	if cfg.export.includeFont {
		if font := runner_font(runner); font != "" {
			fonts, _ := filepath.join({dir, "fonts"}, context.temp_allocator)
			_ = os.make_directory_all(fonts)
			dst, _ := filepath.join({fonts, RUNNER_FONT}, context.temp_allocator)
			_ = os.copy_file(dst, font)
		}
	}
	windows_resources(state, cfg, exe, name)
	return strings.clone(dir, context.temp_allocator), true
}

// windows_resources writes the icon and version info into the exe.
@(private = "file")
windows_resources :: proc(state: ^EditorState, cfg: ^e.ProjectConfig, exe, name: string) {
	if !winres.AVAILABLE {
		Editor_Log(state, .Info, "%s keeps the runner's icon and version info: they're written when exporting on Windows", filepath.base(exe))
		return
	}
	icons: [][]u8
	group: []u8
	if cfg.icon != "" {
		src, _ := filepath.join({state.projectPath, cfg.icon}, context.temp_allocator)
		images := e.Icon_Images(src, {16, 24, 32, 48, 64, 128, 256}, context.temp_allocator)
		if len(images) > 0 {
			pngs := make([][]u8, len(images), context.temp_allocator)
			for im, i in images do pngs[i] = im.png
			icons = pngs
			group = e.Ico_GroupDirectory(images, 1, context.temp_allocator)
		} else {
			Editor_Log(state, .Warn, "Could not read the icon %s", cfg.icon)
		}
	}
	description := cfg.windowTitle if cfg.windowTitle != "" else cfg.name
	version := e.VersionInfo_Resource(cfg.name, description, cfg.version, name, context.temp_allocator)
	if winres.Update(exe, icons, group, version) {
		Editor_Log(state, .Info, "Wrote the icon and version %s into %s", cfg.version, filepath.base(exe))
	} else {
		Editor_Log(state, .Warn, "Could not write resources into %s", exe)
	}
}

// export_linux writes <dir>/<Name>.AppDir and, with appimagetool on PATH
// (Linux), <Name>-<arch>.AppImage next to it.
@(private = "file")
export_linux :: proc(state: ^EditorState, cfg: ^e.ProjectConfig, runner, rayzr, dir, name: string) -> (string, bool) {
	icon := ""
	if cfg.icon != "" do icon, _ = filepath.join({state.projectPath, cfg.icon}, context.temp_allocator)
	font := runner_font(runner) if cfg.export.includeFont else ""
	appDir, ok := e.Export_LinuxAppDir(dir, name, cfg, runner, runner_libraries(runner), rayzr, font, icon)
	if !ok {
		Editor_Log(state, .Error, "Could not write the AppDir in %s", dir)
		return "", false
	}
	when ODIN_OS == .Linux {
		arch := "aarch64" if ODIN_ARCH == .arm64 else "x86_64"
		image, _ := filepath.join({dir, strings.concatenate({name, "-", arch, ".AppImage"}, context.temp_allocator)}, context.temp_allocator)
		if run_tool(state, {"env", strings.concatenate({"ARCH=", arch}, context.temp_allocator), "appimagetool", appDir, image}) {
			return strings.clone(image, context.temp_allocator), true
		}
		Editor_Log(state, .Info, "No AppImage (install appimagetool); the AppDir runs with its AppRun")
	} else {
		Editor_Log(state, .Info, "Linux: %s (make an .AppImage from it with appimagetool on Linux)", filepath.base(appDir))
	}
	return appDir, true
}
