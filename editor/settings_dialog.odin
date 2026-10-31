package editor

import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:reflect"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Settings (Cmd+,): one dialog with top-level tabs
//
//   General      Basic (UI scale, grid, autosave, quit), Keymap (every action)
//   Code Editor  font, tabs, auto-pairs, format on save, language server
//   Project      General (name, startup scene, scenes, physics), Input
//                (named actions -> bindings), Video, Audio, Export
//
// Editor settings and the project's project.json are edited as drafts:
// Save writes and applies both; Cancel discards them.
// ============================================================================

Settings_Tab :: enum {
	General,
	Code,
	Project,
	Plugins,
}

@(private = "file")
Settings_State :: struct {
	tab:        Settings_Tab,
	selectTab:  bool,
	generalPage: int, // 0 Basic, 1 Keymap, 2 Theme
	projectPage: int, // 0 General, 1 Input, 2 Video, 3 Audio, 4 Export
	pluginSel:   int, // Plugins: the selected plugin
	editor:     Editor_Settings,
	project:    e.ProjectConfig,
	open:       bool,
	// Keymap
	keyFilter:  [64]u8,
	recording:  string, // action id waiting for a chord ("" = none)
	// Input
	action:     int,
	newAction:  [64]u8,
	listening:  bool, // capturing a key for the selected action
	pickDevice: e.InputDeviceType,
	pickFilter: [32]u8,
	promptFamily: int, // the pad whose button prompts are shown (PROMPT_FAMILIES)
}

@(private = "file")
PROMPT_FAMILIES := [?]string{"xbox", "playstation", "switch", "steamdeck"}

// The button prompts shown next to bindings (engine input_glyphs.odin),
// loaded once.
@(private = "file")
promptTextures: map[string]rl.Texture2D

@(private = "file")
prompt_icon :: proc(b: e.InputBinding, size: f32) {
	family := "keyboard" if b.deviceType == .KeyboardKey || b.deviceType == .MouseButton else PROMPT_FAMILIES[clamp(st.promptFamily, 0, len(PROMPT_FAMILIES) - 1)]
	path := e.Binding_Glyph(b, family)
	tex, ok := promptTextures[path]
	if !ok && path != "" {
		if img, found := e.Prompt_Image(path); found {
			tex = rl.LoadTextureFromImage(img)
			rl.SetTextureFilter(tex, .BILINEAR)
			rl.UnloadImage(img)
		}
		if promptTextures == nil do promptTextures = make(map[string]rl.Texture2D)
		promptTextures[strings.clone(path)] = tex
	}
	if tex.id == 0 {
		imgui.Dummy({size, size})
		return
	}
	imgui.Image(transmute(imgui.TextureID)&promptTextures[path], {size, size})
	Drive_Item(fmt.tprintf("settings.prompt:%s", path))
	UI_Tooltip(path)
}

@(private = "file")
st: Settings_State

Settings_Open :: proc(state: ^EditorState, tab: Settings_Tab = .General) {
	state.showProjectSettings = true
	if st.open {
		Editor_Settings_Destroy(&st.editor)
		e.ProjectConfig_Destroy(&st.project)
		delete(st.recording)
	}
	st.recording = ""
	st.editor = Editor_Settings_Clone(&GlobalSettings)
	st.project = e.ProjectConfig_Clone(&state.projectConfig)
	// Pick up edits made outside the editor.
	projPath, _ := filepath.join({state.projectPath, "project.json"}, context.temp_allocator)
	if pBytes, err := os.read_entire_file(projPath, context.temp_allocator); err == nil {
		if cfg, parsed := e.Project_ParseConfig(pBytes, context.allocator); parsed {
			e.ProjectConfig_Destroy(&st.project)
			st.project = cfg
		}
	}
	// Show the built-in actions with their default bindings to start from.
	if len(st.project.actions) == 0 {
		e.Input_ActionConfigs_Destroy(&st.project.actions)
		st.project.actions = e.Input_DefaultActionConfigs()
	}
	st.tab = tab
	st.selectTab = true
	st.open = true
	st.action = 0
	st.listening = false
}

// ProjectSettingsDialog_Open opens Settings on the Project tab.
ProjectSettingsDialog_Open :: proc(state: ^EditorState) {
	Settings_Open(state, .Project)
}

@(private = "file")
text_field :: proc(id: string, s: ^string, hint: cstring = "") {
	buf: [256]u8
	copy(buf[:len(buf) - 1], s^)
	imgui.SetNextItemWidth(-1)
	if imgui.InputTextWithHint(fmt.ctprintf("##%s", id), hint, cstring(raw_data(buf[:])), len(buf), {}) {
		delete(s^)
		s^ = strings.clone(string(cstring(raw_data(buf[:]))))
	}
	Drive_Item(id)
}

// folder_field: a folder path with Browse... (a system folder dialog that
// opens in the export folder used last).
@(private = "file")
browseTarget: ^string

@(private = "file")
folder_field :: proc(state: ^EditorState, id: string, s: ^string, hint: string) {
	buf: [512]u8
	copy(buf[:len(buf) - 1], s^)
	imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x - 90)
	if imgui.InputTextWithHint(fmt.ctprintf("##%s", id), strings.clone_to_cstring(hint, context.temp_allocator), cstring(raw_data(buf[:])), len(buf), {}) {
		delete(s^)
		s^ = strings.clone(string(cstring(raw_data(buf[:]))))
	}
	Drive_Item(id)
	imgui.SameLine(0, 4)
	if UI_Button("Browse...", fmt.tprintf("%s.browse", id), {86, 0}) {
		browseTarget = s
		start := Editor_StartDir(.Export, s^ if os.is_dir(s^) else filepath.dir(strings.trim_suffix(state.projectPath, "/"), context.temp_allocator))
		NativeDialog_Open(state, {title = "Output Folder", folders = true, start = start}, proc(state: ^EditorState, paths: []string) {
			if browseTarget == nil do return
			delete(browseTarget^)
			browseTarget^ = strings.clone(paths[0])
			browseTarget = nil
			Editor_RememberDir(.Export, paths[0], true)
		})
	}
}

@(private = "file")
check :: proc(id, label: string, v: ^bool, tip := "") {
	UI_PropLabel(label)
	imgui.Checkbox(fmt.ctprintf("##%s", id), v)
	Drive_Item(id)
	if tip != "" do UI_Tooltip(tip)
}

@(private = "file")
nav :: proc(id: string, items: []string, cur: ^int) {
	for name, i in items {
		if imgui.Selectable(fmt.ctprintf("%s##nav_%s_%d", name, id, i), cur^ == i, {}, {0, 28}) do cur^ = i
		Drive_Item(fmt.tprintf("settings.page:%s", name))
	}
}

ProjectSettingsDialog_Render :: proc(state: ^EditorState) {
	if state.showProjectSettings && !imgui.IsPopupOpen("Settings###SettingsWindow") {
		imgui.OpenPopup("Settings###SettingsWindow")
	}
	io := imgui.GetIO()
	imgui.SetNextWindowSize({940, 640}, .Appearing)
	imgui.SetNextWindowPos({io.DisplaySize.x * 0.5, io.DisplaySize.y * 0.5}, .Appearing, {0.5, 0.5})
	imgui.PushStyleVarImVec2(.WindowPadding, {18, 16})
	defer imgui.PopStyleVar()
	if !imgui.BeginPopupModal("Settings###SettingsWindow", &state.showProjectSettings, {.NoTitleBar}) do return

	UI_PanelTitle(ICON_FA_GEAR, "Settings")
	imgui.SameLine(0, UI_SPACE)
	UI_DimText(state.projectPath)
	imgui.Dummy({0, 4})

	bodyH := imgui.GetContentRegionAvail().y - 46
	if imgui.BeginTabBar("##settings_tabs", {}) {
		tab :: proc(label: cstring, id: string, t: Settings_Tab) -> bool {
			flags: imgui.TabItemFlags = {}
			if st.selectTab && st.tab == t do flags += {.SetSelected}
			open := imgui.BeginTabItem(label, nil, flags)
			Drive_Item(id)
			// While a tab is being selected, the previously open tab still
			// reports open this frame: don't let it overwrite the request.
			if open && !st.selectTab do st.tab = t
			return open
		}
		if tab(fmt.ctprintf("%s  General###st_general", ICON_FA_GEAR), "settings.tab:general", .General) {
			settings_general(state, bodyH - 40)
			imgui.EndTabItem()
		}
		if tab(fmt.ctprintf("%s  Code Editor###st_code", ICON_FA_CODE), "settings.tab:code", .Code) {
			settings_code(state, bodyH - 40)
			imgui.EndTabItem()
		}
		if tab(fmt.ctprintf("%s  Project###st_project", ICON_FA_FOLDER), "settings.tab:project", .Project) {
			settings_project(state, bodyH - 40)
			imgui.EndTabItem()
		}
		if tab(fmt.ctprintf("%s  Plugins###st_plugins", ICON_FA_CODE), "settings.tab:plugins", .Plugins) {
			settings_plugins(state, bodyH - 40)
			imgui.EndTabItem()
		}
		st.selectTab = false
		imgui.EndTabBar()
	}

	imgui.SetCursorPosY(imgui.GetWindowHeight() - 16 - 32)
	imgui.SetCursorPosX(imgui.GetWindowWidth() - 18 - 120 - 96 - UI_SPACE)
	if UI_Button("Cancel", "settings.cancel", {96, 32}) || (imgui.IsKeyPressed(.Escape) && st.recording == "" && !st.listening) {
		state.showProjectSettings = false
		Theme_Apply(GlobalSettings.theme) // drop a previewed theme
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine(0, UI_SPACE)
	if UI_PrimaryButton("Save", "settings.save", {120, 32}) do settings_save(state)
	imgui.EndPopup()
}

@(private = "file")
settings_save :: proc(state: ^EditorState) {
	Lua_MarkProjectTypesDirty() // generated Lua types follow the project
	d := &st.project
	if !e.Project_SaveConfigToFile(state.projectPath, d) {
		Editor_Log(state, .Error, "Failed to write %s/project.json", state.projectPath)
		return
	}
	e.ProjectConfig_Destroy(&state.projectConfig)
	state.projectConfig = e.ProjectConfig_Clone(d)
	e.Physics_SetLayerNames(state.projectConfig.collisionLayers[:])
	state.game.physicsWorld.gravity = d.gravity
	e.Transition_SetDefault(state.game, d.transition, d.transitionDuration, d.transitionEasing)
	if d.virtualWidth > 0 do state.game.virtualSize = {d.virtualWidth, d.virtualHeight}
	if d.virtualWidth > 0 do state.game.designSize = {d.virtualWidth, d.virtualHeight}
	state.game.fill = d.fill
	state.game.musicVolume = d.musicVolume
	state.game.sfxVolume = d.sfxVolume
	e.Input_ApplyActionConfigs(&state.game.input, d.actions[:])
	state.game.input.touch.asMouse = d.touchAsMouse
	e.Access_SetDefaults(e.ProjectConfig_Accessibility(d)) // (Simulate uses the project's accessibility defaults)
	Editor_ReloadGlobals(state)

	Editor_Settings_Destroy(&GlobalSettings)
	GlobalSettings = Editor_Settings_Clone(&st.editor)
	Editor_ApplySettings(state)
	if !Editor_SaveSettings() do Editor_Log(state, .Warn, "Could not write editor settings to %s", settingsPath)

	Editor_Log(state, .Info, "Saved settings (startup scene %s)", d.initialScene)
	state.showProjectSettings = false
	imgui.CloseCurrentPopup()
}

// --- General -----------------------------------------------------------------------

@(private = "file")
settings_general :: proc(state: ^EditorState, h: f32) {
	if imgui.BeginChild("##gen_nav", {170, h}, {}, {}) do nav("general", {"Basic", "Keymap", "Theme"}, &st.generalPage)
	imgui.EndChild()
	imgui.SameLine(0, UI_SPACE * 2)
	if imgui.BeginChild("##gen_body", {0, h}, {}, {}) {
		s := &st.editor
		switch st.generalPage {
		case 0:
			if UI_BeginProps("##basic") {
				UI_PropLabel("UI Scale")
				imgui.SliderFloat("##uiscale", &s.uiScale, 0.75, 2, "%.2fx")
				Drive_Item("settings.ui-scale")
				UI_PropLabel("Grid Size")
				imgui.DragFloat("##grid", &s.gridSize, 1, 1, 512, "%.0f px")
				Drive_Item("settings.grid-size")
				check("settings.snap", "Snap to Grid", &s.snapToGrid)
				check("settings.show-grid", "Show Grid", &s.showGrid)
				UI_PropLabel("Autosave")
				mins := c.int(s.autosaveMinutes)
				if imgui.SliderInt("##autosave", &mins, 0, 30, "%d min" if mins > 0 else "Off") do s.autosaveMinutes = int(mins)
				Drive_Item("settings.autosave")
				UI_Tooltip("Save modified scenes and scripts every N minutes (0 = off)")
				check("settings.confirm-quit", "Ask Before Quitting", &s.confirmQuit, "Ask about unsaved scenes and scripts when quitting")
				check("settings.check-updates", "Check for Updates", &s.checkUpdates, "At startup, look for a newer Rayzr Editor release (GitHub) and show it in the status bar")
				check("settings.auto-bottom-panel", "Bottom Panel Follows Selection", &s.autoBottomPanel, "Selecting an AnimationPlayer, particle emitter, LDtk level, Tile Map or State Machine shows its tab in the bottom panel; selecting something else goes back to the tab you had")
				UI_PropLabel("Aseprite")
				text_field("settings.aseprite-path", &s.asepritePath, strings.clone_to_cstring(Aseprite_DefaultPath(), context.temp_allocator))
				UI_Tooltip("The Aseprite program Edit in Aseprite opens (empty: found where Aseprite installs; Steam too)")
				UI_EndProps()
			}
		case 1:
			settings_keymap(state)
		case 2:
			Theme_Editor(&s.theme) // previews live; Cancel restores the saved theme
		}
	}
	imgui.EndChild()
}

// imgui_key_chord: the chord pressed this frame (any non-modifier key).
@(private = "file")
imgui_key_chord :: proc() -> (Chord, bool) {
	for k in imgui.Key.Tab ..= imgui.Key.F12 {
		#partial switch k {
		case .LeftCtrl, .RightCtrl, .LeftShift, .RightShift, .LeftAlt, .RightAlt, .LeftSuper, .RightSuper: continue
		}
		if !imgui.IsKeyPressed(k, false) do continue
		mods: Mods
		if Keys_Primary() do mods += {.Primary}
		when ODIN_OS == .Darwin {
			if Keys_PhysicalCtrl() do mods += {.Ctrl}
		}
		if imgui.IsKeyDown(.LeftShift) || imgui.IsKeyDown(.RightShift) do mods += {.Shift}
		if imgui.IsKeyDown(.LeftAlt) || imgui.IsKeyDown(.RightAlt) do mods += {.Alt}
		return {k, mods}, true
	}
	return {}, false
}

@(private = "file")
settings_keymap :: proc(state: ^EditorState) {
	s := &st.editor
	imgui.SetNextItemWidth(-1)
	imgui.InputTextWithHint("##km_filter", "Filter commands or keys", cstring(raw_data(st.keyFilter[:])), len(st.keyFilter), {})
	Drive_Item("settings.keymap-filter")
	q := strings.to_lower(string(cstring(raw_data(st.keyFilter[:]))), context.temp_allocator)
	if st.recording != "" {
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextUnformatted("Press the new shortcut (Esc cancels)...")
		imgui.PopStyleColor()
		if imgui.IsKeyPressed(.Escape, false) {
			delete(st.recording)
			st.recording = ""
		} else if chord, ok := imgui_key_chord(); ok {
			chords := s.keymap[st.recording] if st.recording in s.keymap else actionDefaults[st.recording]
			chords[0] = chord
			if s.keymap == nil do s.keymap = make(map[string][3]Chord)
			if st.recording not_in s.keymap do s.keymap[strings.clone(st.recording)] = chords
			else do s.keymap[st.recording] = chords
			delete(st.recording)
			st.recording = ""
		}
	}
	if !imgui.BeginTable("##keymap", 3, imgui.TableFlags_SizingStretchProp | imgui.TableFlags_RowBg | imgui.TableFlags_ScrollY) do return
	imgui.TableSetupColumn("Command", {.WidthStretch}, 0.5)
	imgui.TableSetupColumn("Shortcut", {.WidthStretch}, 0.32)
	imgui.TableSetupColumn("", {.WidthFixed}, 96)
	imgui.TableHeadersRow()
	for &a in GlobalActions {
		chords := s.keymap[a.id] if a.id in s.keymap else actionDefaults[a.id]
		name := fmt.tprintf("%s: %s", a.category, a.label)
		keys := strings.builder_make(context.temp_allocator)
		for ch in chords {
			if ch.key == .None do continue
			if strings.builder_len(keys) > 0 do strings.write_string(&keys, "  /  ")
			strings.write_string(&keys, Chord_Text(ch))
		}
		keyText := strings.to_string(keys)
		if q != "" && !strings.contains(strings.to_lower(name, context.temp_allocator), q) && !strings.contains(strings.to_lower(keyText, context.temp_allocator), q) do continue
		imgui.TableNextRow()
		imgui.TableNextColumn()
		imgui.AlignTextToFramePadding()
		imgui.TextUnformatted(strings.clone_to_cstring(name, context.temp_allocator))
		imgui.TableNextColumn()
		imgui.AlignTextToFramePadding()
		recording := st.recording == a.id
		imgui.PushStyleColorImVec4(.Text, UI_WARNING if recording else UI_ACCENT)
		imgui.TextUnformatted(strings.clone_to_cstring(keyText if !recording else "...", context.temp_allocator))
		imgui.PopStyleColor()
		if conflict := Action_Conflicts(&a, chords[0]); conflict != "" {
			imgui.SameLine()
			imgui.PushStyleColorImVec4(.Text, UI_WARNING)
			imgui.TextUnformatted(ICON_FA_TRIANGLE_EXCLAMATION)
			imgui.PopStyleColor()
			UI_Tooltip(fmt.tprintf("Also bound to %s", conflict))
		}
		imgui.TableNextColumn()
		imgui.PushID(strings.clone_to_cstring(a.id, context.temp_allocator))
		if UI_IconButton(ICON_FA_PEN, fmt.tprintf("settings.key-record:%s", a.id), "Record a new shortcut", recording, 26) {
			delete(st.recording)
			st.recording = strings.clone(a.id)
		}
		imgui.SameLine(0, 2)
		if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("settings.key-clear:%s", a.id), "Remove the shortcuts", size = 26) {
			if a.id not_in s.keymap do s.keymap[strings.clone(a.id)] = {}
			else do s.keymap[a.id] = {}
		}
		imgui.SameLine(0, 2)
		if UI_IconButton(ICON_FA_ROTATE_LEFT, fmt.tprintf("settings.key-reset:%s", a.id), "Reset to default", size = 26) {
			if k, _ := delete_key(&s.keymap, a.id); k != "" do delete(k)
		}
		imgui.PopID()
	}
	imgui.EndTable()
}

// --- Code editor -------------------------------------------------------------------

@(private = "file")
settings_code :: proc(state: ^EditorState, h: f32) {
	if !imgui.BeginChild("##code_body", {0, h}, {}, {}) {
		imgui.EndChild()
		return
	}
	defer imgui.EndChild()
	s := &st.editor
	if !UI_BeginProps("##codeprops") do return
	UI_PropLabel("Font Size")
	imgui.SliderFloat("##codefont", &s.codeFontSize, 9, 32, "%.0f")
	Drive_Item("settings.code-font")
	UI_PropLabel("Tab Width")
	tw := c.int(s.tabWidth)
	if imgui.SliderInt("##tabw", &tw, 1, 8) do s.tabWidth = int(tw)
	Drive_Item("settings.tab-width")
	check("settings.insert-spaces", "Indent With Spaces", &s.insertSpaces, "For files that don't have an indentation style yet")
	check("settings.auto-pairs", "Auto-Close Brackets", &s.autoClosePairs, "Insert closing brackets and quotes, step over them, wrap selections")
	check("settings.rainbow-brackets", "Rainbow Brackets", &s.rainbowBrackets, "Colour brackets by how deeply they are nested")
	check("settings.indent-guides", "Indent Guides", &s.indentGuides, "Vertical lines at each indentation level; the block around the caret is brighter")
	check("settings.sticky-scroll", "Sticky Scroll", &s.stickyScroll, "The first lines of the blocks you are scrolled into stay at the top")
	check("settings.breadcrumbs", "Breadcrumbs", &s.breadcrumbs, "File > function > blocks around the caret, above the code")
	check("settings.inlay-hints", "Inlay Hints", &s.inlayHints, "Parameter names before the arguments of engine API and file functions (Ctrl+Alt+H toggles)")
	check("settings.color-swatches", "Colour Swatches", &s.colorSwatches, "A swatch before {r, g, b[, a]} colour tables; click it for a colour picker")
	check("settings.soft-wrap", "Soft Wrap", &s.softWrap, "Wrap long lines at the Code area's width (Alt+Z toggles)")
	UI_PropLabel("Show Whitespace")
	ws := c.int(s.showWhitespace)
	imgui.SetNextItemWidth(-1)
	if imgui.Combo("##showws", &ws, "None\x00In Selections\x00All\x00\x00") do s.showWhitespace = Show_Whitespace(ws)
	Drive_Item("settings.show-whitespace")
	check("settings.format-on-save", "Format On Save", &s.formatOnSave, "Run the language server's formatter before saving")
	check("settings.lsp", "Language Server", &s.lspEnabled, "Completion, diagnostics and navigation from lua-language-server (restart the editor to apply)")
	UI_PropLabel("Server Path")
	text_field("settings.lsp-path", &s.luaServerPath, "lua-language-server/bin/lua-language-server")
	UI_EndProps()
}

// --- Project -----------------------------------------------------------------------

@(private = "file")
settings_project :: proc(state: ^EditorState, h: f32) {
	if imgui.BeginChild("##proj_nav", {170, h}, {}, {}) do nav("project", {"General", "Input", "Video", "Audio", "Export", "Globals", "Accessibility"}, &st.projectPage)
	imgui.EndChild()
	imgui.SameLine(0, UI_SPACE * 2)
	if imgui.BeginChild("##proj_body", {0, h}, {}, {}) {
		switch st.projectPage {
		case 0: project_general(state)
		case 1: project_input(state)
		case 2: project_video(state)
		case 3: project_audio(state)
		case 4: project_export(state)
		case 5: project_globals(state)
		case 6: project_accessibility(state)
		}
	}
	imgui.EndChild()
}

// project_globals: global scripts (autoloads) - a name and a script each.
@(private = "file")
project_globals :: proc(state: ^EditorState) {
	d := &st.project
	UI_SectionHeader("Global Scripts")
	UI_DimText("Each script is loaded once, before any scene. The table it returns is a Lua global")
	UI_DimText("with this name in every script, kept across scene changes. Its ready(self) runs")
	UI_DimText("when the game starts and update(self, dt) every frame.")
	imgui.Dummy({0, 4})
	scripts := Editor_ListProjectFiles(state, "", {".lua"})
	remove := -1
	if len(d.globals) > 0 && imgui.BeginTable("##globals", 3, imgui.TableFlags_SizingStretchProp) {
		imgui.TableSetupColumn("Name", {.WidthStretch}, 1)
		imgui.TableSetupColumn("Script", {.WidthStretch}, 1.6)
		imgui.TableSetupColumn("", {.WidthFixed}, 30)
		imgui.TableHeadersRow()
		for &g, i in d.globals {
			imgui.PushIDInt(c.int(i))
			imgui.TableNextRow()
			imgui.TableNextColumn()
			text_field(fmt.tprintf("settings.global-name:%d", i), &g.name, "Name")
			problem := ""
			if !e.Globals_ValidName(g.name) do problem = "Not a valid Lua name (letters, digits, _)"
			for o, j in d.globals do if j < i && o.name == g.name do problem = "Another global has this name"
			if problem != "" {
				imgui.TextColored(UI_DANGER, fmt.ctprintf("%s  %s", ICON_FA_TRIANGLE_EXCLAMATION, problem))
				Drive_Item(fmt.tprintf("settings.global-problem:%d", i))
			}
			imgui.TableNextColumn()
			imgui.SetNextItemWidth(-1)
			if path, ok := asset_picker(fmt.tprintf("settings.global-script:%d", i), g.script, scripts, allowNone = false); ok {
				delete(g.script)
				g.script = strings.clone(path)
			}
			imgui.TableNextColumn()
			if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("settings.global-remove:%d", i), "Remove", size = 24) do remove = i
			imgui.PopID()
		}
		imgui.EndTable()
	}
	if remove >= 0 {
		delete(d.globals[remove].name)
		delete(d.globals[remove].script)
		ordered_remove(&d.globals, remove)
	}
	if UI_Button(fmt.tprintf("%s  Add Global", ICON_FA_PLUS), "settings.global-add") {
		script := scripts[0] if len(scripts) > 0 else ""
		for sc in scripts do if e.Globals_NameOf(d.globals[:], sc) == "" {script = sc; break}
		append(&d.globals, e.Global_Script{strings.clone(Globals_DefaultName(script) if script != "" else "Global"), strings.clone(script)})
	}
	UI_Tooltip("Or right-click a script in the Assets panel > Make Global")
}

@(private = "file")
scene_listed :: proc(d: ^e.ProjectConfig, path: string) -> bool {
	for s in d.scenes do if s == path do return true
	return false
}

@(private = "file")
ensure_scene_listed :: proc(d: ^e.ProjectConfig, path: string) {
	if !scene_listed(d, path) do append(&d.scenes, strings.clone(path))
}

@(private = "file")
project_general :: proc(state: ^EditorState) {
	d := &st.project
	if UI_SectionHeader("Project") && UI_BeginProps("##general") {
		UI_PropLabel("Name")
		text_field("settings.name", &d.name)
		UI_PropLabel("Version")
		text_field("settings.version", &d.version)
		UI_PropLabel("Language")
		text_field("settings.language", &d.language, "the first in locale/*.csv")
		UI_Tooltip("Starting language for texts from the locale/ tables (scripts: Locale.set)")
		UI_PropLabel("Startup Scene")
		avail := imgui.GetContentRegionAvail().x
		imgui.SetNextItemWidth(avail - 110)
		if imgui.BeginCombo("##startup", strings.clone_to_cstring(d.initialScene if d.initialScene != "" else "None", context.temp_allocator)) {
			for sc in d.scenes {
				if imgui.Selectable(strings.clone_to_cstring(sc, context.temp_allocator), sc == d.initialScene) {
					delete(d.initialScene)
					d.initialScene = strings.clone(sc)
				}
				Drive_Item(fmt.tprintf("pick:%s", sc))
			}
			imgui.EndCombo()
		}
		Drive_Item("settings.startup")
		imgui.SameLine(0, 6)
		if UI_Button("Use Current", "settings.use-current", {104, 0}) && state.activeScenePath != "" {
			delete(d.initialScene)
			d.initialScene = strings.clone(state.activeScenePath)
			ensure_scene_listed(d, state.activeScenePath)
		}
		UI_PropLabel("Icon")
		imgui.SetNextItemWidth(-1)
		if path, ok := asset_picker("settings.icon", d.icon, Editor_ListProjectFiles(state, "", {".png"})); ok {
			delete(d.icon)
			d.icon = strings.clone(path)
		}
		UI_Tooltip("PNG used as the game window's icon and the exported app's (512x512 or 1024x1024 works best)")
		UI_EndProps()
	}
	if UI_SectionHeader("Scene Transitions", false) && UI_BeginProps("##transitions") {
		// The default for Scene.change_scene(name) without options (and the
		// options a script leaves out).
		UI_PropLabel("Default")
		imgui.SetNextItemWidth(-1)
		current := d.transition if d.transition != "" else "none"
		if imgui.BeginCombo("##transition", strings.clone_to_cstring(current == "none" ? "None (change at once)" : current, context.temp_allocator)) {
			names := make([dynamic]string, context.temp_allocator)
			append(&names, "none")
			for k in e.Transition_Kind do if k != .Shader do append(&names, e.TRANSITION_NAMES[k])
			for n in names {
				label := "None (change at once)" if n == "none" else n
				if imgui.Selectable(strings.clone_to_cstring(label, context.temp_allocator), n == current) {
					delete(d.transition)
					d.transition = strings.clone(n) if n != "none" else ""
				}
				Drive_Item(fmt.tprintf("pick:%s", n))
			}
			imgui.EndCombo()
		}
		Drive_Item("settings.transition")
		UI_Tooltip("How Scene.change_scene(name) changes scenes when the script gives no options (a shader file's path works too: type it in project.json)")
		imgui.BeginDisabled(d.transition == "")
		UI_PropLabel("Duration")
		if d.transitionDuration <= 0 do d.transitionDuration = 0.4
		imgui.DragFloat("##transition_duration", &d.transitionDuration, 0.01, 0.05, 5, "%.2f s")
		Drive_Item("settings.transition-duration")
		UI_Tooltip("Seconds: each half of a cover transition (fade, wipe, circle), the whole of the others")
		UI_PropLabel("Easing")
		imgui.SetNextItemWidth(-1)
		easing := d.transitionEasing if d.transitionEasing != "" else "in_out_sine"
		if imgui.BeginCombo("##transition_easing", strings.clone_to_cstring(easing, context.temp_allocator)) {
			for ez in e.Ease do if ez != .Constant {
				n := e.Ease_Name(ez)
				if imgui.Selectable(strings.clone_to_cstring(n, context.temp_allocator), n == easing) {
					delete(d.transitionEasing)
					d.transitionEasing = strings.clone(n)
				}
			}
			imgui.EndCombo()
		}
		imgui.EndDisabled()
		UI_EndProps()
	}
	if UI_SectionHeader("Physics") && UI_BeginProps("##physics") {
		UI_PropLabel("Gravity")
		imgui.DragFloat2("##gravity", &d.gravity, 1, -5000, 5000, "%.0f")
		Drive_Item("settings.gravity")
		UI_PropLabel("")
		if UI_Button("Zero-G", "settings.zero-g") do d.gravity = {0, 0}
		imgui.SameLine()
		if UI_Button("Earth (0, 980)", "settings.earth-g") do d.gravity = {0, 980}
		UI_PropLabel("Show Colliders")
		imgui.Checkbox("##debug_draw", &d.debugDraw)
		Drive_Item("settings.debug-draw")
		UI_Tooltip("Draw collision shapes, joints and areas while the game runs (debugging). The editor's viewport shows them either way; scripts: Physics.set_debug_draw(false)")
		UI_EndProps()
	}
	if UI_SectionHeader("Developer Console", false) && UI_BeginProps("##console") {
		UI_PropLabel("In Release Builds")
		imgui.Checkbox("##console_release", &d.consoleInRelease)
		Drive_Item("settings.console-release")
		UI_Tooltip("The in-game developer console (commands, Lua, perf overlay, debug drawing, pause and step) is always in debug builds and the editor's Play. On: release exports have it too")
		UI_PropLabel("Key")
		imgui.SetNextItemWidth(-1)
		keys := [?]string{"GRAVE", "F1", "F2", "F12", "TAB", "BACKSLASH"}
		cur := d.consoleKey if d.consoleKey != "" else "GRAVE"
		if imgui.BeginCombo("##console_key", fmt.ctprintf("%s", "` (backquote)" if cur == "GRAVE" else cur)) {
			for k in keys {
				if imgui.Selectable(fmt.ctprintf("%s", "` (backquote)" if k == "GRAVE" else k), k == cur) {
					if d.consoleKey != "" do delete(d.consoleKey)
					d.consoleKey = strings.clone(k) if k != "GRAVE" else ""
				}
			}
			imgui.EndCombo()
		}
		Drive_Item("settings.console-key")
		UI_Tooltip("The key that opens and closes the console")
		UI_EndProps()
	}
	if UI_SectionHeader("Collision Layers", false) && UI_BeginProps("##layers") {
		// Names for the 16 collision layers (shown in body shapes' layer lists;
		// scripts use them: body:set_collision_layer("Player")).
		for i in 0 ..< 16 {
			UI_PropLabel(fmt.tprintf("Layer %d", i + 1))
			text_field(fmt.tprintf("settings.layer:%d", i + 1), &d.collisionLayers[i], "unnamed")
		}
		UI_EndProps()
	}
	if UI_SectionHeader("Scenes") {
		UI_DimText("Scenes included in the game (and in exported packages).")
		remove := -1
		for sc, i in d.scenes {
			imgui.PushIDInt(c.int(i))
			imgui.AlignTextToFramePadding()
			imgui.TextUnformatted(fmt.ctprintf("%s  %s%s", ICON_FA_CLAPPERBOARD, sc, "   (startup)" if sc == d.initialScene else ""))
			imgui.SameLine(imgui.GetWindowContentRegionMax().x - 28)
			if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("settings.remove:%s", sc), "Remove from project", size = 24) do remove = i
			imgui.PopID()
		}
		if remove >= 0 {
			delete(d.scenes[remove])
			ordered_remove(&d.scenes, remove)
		}
		if state.activeScenePath != "" && !scene_listed(d, state.activeScenePath) {
			if UI_Button(fmt.tprintf("%s  Add %s", ICON_FA_PLUS, state.activeScenePath), "settings.add-current") {
				ensure_scene_listed(d, state.activeScenePath)
			}
		}
	}
}

// imgui_to_raylib_key maps the key just pressed in the editor to a raylib
// key (for "Press a key" capture of game bindings).
@(private = "file")
imgui_to_raylib_key :: proc(k: imgui.Key) -> (rl.KeyboardKey, bool) {
	if k >= .A && k <= .Z do return rl.KeyboardKey(int(rl.KeyboardKey.A) + int(k) - int(imgui.Key.A)), true
	if k >= ._0 && k <= ._9 do return rl.KeyboardKey(int(rl.KeyboardKey.ZERO) + int(k) - int(imgui.Key._0)), true
	if k >= .F1 && k <= .F12 do return rl.KeyboardKey(int(rl.KeyboardKey.F1) + int(k) - int(imgui.Key.F1)), true
	#partial switch k {
	case .Space: return .SPACE, true
	case .Enter: return .ENTER, true
	case .Escape: return .ESCAPE, true
	case .Tab: return .TAB, true
	case .Backspace: return .BACKSPACE, true
	case .UpArrow: return .UP, true
	case .DownArrow: return .DOWN, true
	case .LeftArrow: return .LEFT, true
	case .RightArrow: return .RIGHT, true
	case .LeftShift: return .LEFT_SHIFT, true
	case .RightShift: return .RIGHT_SHIFT, true
	case .LeftCtrl: return .LEFT_CONTROL, true
	case .RightCtrl: return .RIGHT_CONTROL, true
	case .LeftAlt: return .LEFT_ALT, true
	case .RightAlt: return .RIGHT_ALT, true
	}
	return .KEY_NULL, false
}

@(private = "file")
enum_combo :: proc($T: typeid, id: string, b: ^e.InputBinding) {
	cur := ""
	switch b.deviceType {
	case .KeyboardKey: cur, _ = reflect.enum_name_from_value(b.key)
	case .MouseButton: cur, _ = reflect.enum_name_from_value(b.mouseButton)
	case .GamepadButton: cur, _ = reflect.enum_name_from_value(b.gamepadButton)
	case .GamepadAxis: cur, _ = reflect.enum_name_from_value(b.gamepadAxis)
	case .None:
	}
	imgui.SetNextItemWidth(170)
	if imgui.BeginCombo(fmt.ctprintf("##%s", id), strings.clone_to_cstring(cur, context.temp_allocator), {.HeightLarge}) {
		for f in reflect.enum_fields_zipped(T) {
			if f.name == "KEY_NULL" do continue
			if imgui.Selectable(strings.clone_to_cstring(f.name, context.temp_allocator), f.name == cur) {
				switch b.deviceType {
				case .KeyboardKey: b.key = rl.KeyboardKey(f.value)
				case .MouseButton: b.mouseButton = rl.MouseButton(f.value)
				case .GamepadButton: b.gamepadButton = rl.GamepadButton(f.value)
				case .GamepadAxis: b.gamepadAxis = rl.GamepadAxis(f.value)
				case .None:
				}
			}
			Drive_Item(fmt.tprintf("pick:%s", f.name))
		}
		imgui.EndCombo()
	}
	Drive_Item(id)
}

@(private = "file")
project_input :: proc(state: ^EditorState) {
	d := &st.project
	UI_DimText("Scripts ask for actions, not keys: Input.is_action_down(\"jump\").")
	// (Not in a property table here: a plain checkbox.)
	imgui.Checkbox("Touch as Mouse##settings.touch-as-mouse", &d.touchAsMouse)
	Drive_Item("settings.touch-as-mouse")
	UI_Tooltip("On touch screens (the web export on phones and tablets) the first finger is the left mouse button: taps click, drags drag. Off: games read the fingers themselves (Input.get_touches). On-screen controls take their own fingers either way")
	imgui.Dummy({0, 4})
	h := imgui.GetContentRegionAvail().y
	// Action list.
	if imgui.BeginChild("##actions", {200, h}, {.Borders}, {}) {
		remove := -1
		for a, i in d.actions {
			if imgui.Selectable(fmt.ctprintf("%s##act%d", a.name, i), st.action == i) {
				st.action = i
				st.listening = false
			}
			Drive_Item(fmt.tprintf("settings.action:%s", a.name))
			if imgui.BeginPopupContextItem(fmt.ctprintf("##actctx%d", i)) {
				if imgui.MenuItem(fmt.ctprintf("%s  Remove action", ICON_FA_TRASH)) do remove = i
				imgui.EndPopup()
			}
		}
		if remove >= 0 {
			delete(d.actions[remove].name)
			delete(d.actions[remove].bindings)
			ordered_remove(&d.actions, remove)
			st.action = clamp(st.action, 0, max(len(d.actions) - 1, 0))
		}
		imgui.Separator()
		imgui.SetNextItemWidth(-28)
		enter := imgui.InputTextWithHint("##newaction", "new_action", cstring(raw_data(st.newAction[:])), len(st.newAction), {.EnterReturnsTrue})
		Drive_Item("settings.new-action")
		imgui.SameLine(0, 2)
		add := UI_IconButton(ICON_FA_PLUS, "settings.add-action", "Add action", size = 24)
		name := strings.trim_space(string(cstring(raw_data(st.newAction[:]))))
		if (enter || add) && name != "" {
			exists := false
			for a in d.actions do if strings.equal_fold(a.name, name) do exists = true
			if !exists {
				append(&d.actions, e.Input_Action_Config{name = strings.clone(name), bindings = make([dynamic]e.InputBinding)})
				st.action = len(d.actions) - 1
			}
			st.newAction = {}
		}
	}
	imgui.EndChild()
	imgui.SameLine(0, UI_SPACE)
	if imgui.BeginChild("##bindings", {0, h}, {}, {}) {
		if st.action >= 0 && st.action < len(d.actions) {
			a := &d.actions[st.action]
			UI_PanelTitle(ICON_FA_BOLT, a.name)
			imgui.Dummy({0, 4})
			imgui.AlignTextToFramePadding()
			UI_DimText("Prompts")
			imgui.SameLine(0, 6)
			imgui.SetNextItemWidth(140)
			if idx, changed := UI_Combo("settings.prompt-family", st.promptFamily, []string{"Xbox", "PlayStation", "Switch", "Steam Deck"}); changed do st.promptFamily = idx
			UI_Tooltip("The button images games get from Input.glyph(action) - for this pad (and the keyboard)")
			imgui.Dummy({0, 4})
			remove := -1
			for &b, bi in a.bindings {
				imgui.PushIDInt(c.int(bi))
				prompt_icon(b, 26)
				imgui.SameLine(0, 6)
				names := []string{"None", "Key", "Mouse", "Gamepad Button", "Gamepad Axis"}
				imgui.SetNextItemWidth(140)
				if idx, changed := UI_Combo(fmt.tprintf("settings.binding-device:%d", bi), int(b.deviceType), names); changed {
					b = {deviceType = e.InputDeviceType(idx), axisDeadzone = 0.25}
				}
				imgui.SameLine(0, 4)
				switch b.deviceType {
				case .KeyboardKey: enum_combo(rl.KeyboardKey, fmt.tprintf("settings.binding:%d", bi), &b)
				case .MouseButton: enum_combo(rl.MouseButton, fmt.tprintf("settings.binding:%d", bi), &b)
				case .GamepadButton: enum_combo(rl.GamepadButton, fmt.tprintf("settings.binding:%d", bi), &b)
				case .GamepadAxis:
					enum_combo(rl.GamepadAxis, fmt.tprintf("settings.binding:%d", bi), &b)
					imgui.SameLine(0, 4)
					imgui.Checkbox("+##pos", &b.axisPositive)
					UI_Tooltip("Positive direction of the axis")
					imgui.SameLine(0, 4)
					imgui.SetNextItemWidth(80)
					imgui.SliderFloat("##dz", &b.axisDeadzone, 0.05, 0.95, "dz %.2f")
				case .None:
				}
				imgui.SameLine(0, 4)
				if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("settings.remove-binding:%d", bi), "Remove binding", size = 26) do remove = bi
				imgui.PopID()
			}
			if remove >= 0 do ordered_remove(&a.bindings, remove)
			imgui.Dummy({0, 4})
			if len(a.bindings) < e.MAX_BINDINGS_PER_ACTION {
				if st.listening {
					imgui.PushStyleColorImVec4(.Text, UI_WARNING)
					imgui.TextUnformatted("Press a key (Esc cancels)...")
					imgui.PopStyleColor()
					for k in imgui.Key.Tab ..= imgui.Key.F12 {
						if !imgui.IsKeyPressed(k, false) do continue
						if k == .Escape {
							st.listening = false
							break
						}
						if rk, ok := imgui_to_raylib_key(k); ok {
							append(&a.bindings, e.InputBinding{deviceType = .KeyboardKey, key = rk})
							st.listening = false
							break
						}
					}
				} else {
					if UI_Button(fmt.tprintf("%s  Press a Key", ICON_FA_PLUS), "settings.listen-key") do st.listening = true
					imgui.SameLine()
					if UI_Button(fmt.tprintf("%s  Add Binding", ICON_FA_PLUS), "settings.add-binding") {
						append(&a.bindings, e.InputBinding{deviceType = .KeyboardKey, key = .SPACE, axisDeadzone = 0.25})
					}
				}
			} else {
				UI_DimText(fmt.tprintf("At most %d bindings per action.", e.MAX_BINDINGS_PER_ACTION))
			}
		} else {
			UI_DimText("Add an action on the left.")
		}
	}
	imgui.EndChild()
}

@(private = "file")
project_video :: proc(state: ^EditorState) {
	d := &st.project
	if !UI_BeginProps("##video") do return
	UI_PropLabel("Window Title")
	text_field("settings.title", &d.windowTitle)
	UI_PropLabel("Window Size")
	size := [2]c.int{c.int(d.windowWidth), c.int(d.windowHeight)}
	if imgui.DragInt2("##winsize", &size, 1, 160, 7680, "%d px") do d.windowWidth, d.windowHeight = int(size.x), int(size.y)
	Drive_Item("settings.window-size")
	UI_PropLabel("Virtual Resolution")
	vres := [2]f32{d.virtualWidth, d.virtualHeight}
	if imgui.DragFloat2("##vres", &vres, 1, 160, 7680, "%.0f") do d.virtualWidth, d.virtualHeight = vres.x, vres.y
	Drive_Item("settings.virtual-res")
	UI_Tooltip("The resolution the game is designed for; it is scaled to the window or the screen (fullscreen) - see Screen Fill for a window of another shape")
	UI_PropLabel("Screen Fill")
	if idx, changed := UI_Combo("settings.fill", int(d.fill), []string{"Keep (bars)", "Expand (no bars)"}); changed do d.fill = e.Screen_Fill(idx)
	UI_Tooltip("A window or screen whose shape differs from the virtual resolution. Expand: the same scale, more of the world on the longer side, no bars (UI on a Screen Layer stays at the screen's edges). Keep: exactly the virtual resolution, black bars where the shapes differ")
	UI_PropLabel("Target FPS")
	fps := c.int(d.targetFPS)
	if imgui.SliderInt("##fps", &fps, 30, 240) do d.targetFPS = int(fps)
	Drive_Item("settings.fps")
	check("settings.fullscreen", "Fullscreen", &d.fullscreen, "Cover the whole screen at its own resolution (the game is scaled to it). Scripts: Engine.set_fullscreen(true)")
	check("settings.sharp-scaling", "Sharp Pixels", &d.sharpScaling, "Scale the game to the window nearest-neighbour - crisp pixel art; off: smooth")
	check("settings.integer-scaling", "Integer Scaling", &d.integerScaling, "Scale by a whole number (2x, 3x...) with bars around: every game pixel the same size on screen")
	check("settings.pixel-snap", "Pixel Snap", &d.pixelSnap, "The camera and sprites sit on whole game pixels: no shimmering or uneven pixels")
	if !d.pixelSnap do imgui.BeginDisabled()
	check("settings.smooth-camera", "Smooth Camera", &d.smoothCamera, "With Pixel Snap: keep the camera's sub-pixel motion when scaling up (slow pans glide instead of stepping a game pixel at a time); UI layers stay put")
	if !d.pixelSnap do imgui.EndDisabled()
	check("settings.vsync", "VSync", &d.vsync)
	check("settings.resizable", "Resizable Window", &d.resizable)
	check("settings.msaa", "Anti-aliasing (MSAA 4x)", &d.msaa)
	check("settings.high-dpi", "High-DPI", &d.highDPI, "Render at the display's native pixel density")
	UI_EndProps()
}

@(private = "file")
project_audio :: proc(state: ^EditorState) {
	d := &st.project
	if !UI_BeginProps("##audio") do return
	vol :: proc(id, label: string, v: ^f32) {
		UI_PropLabel(label)
		pct := v^ * 100
		if imgui.SliderFloat(fmt.ctprintf("##%s", id), &pct, 0, 100, "%.0f%%") do v^ = pct / 100
		Drive_Item(id)
	}
	vol("settings.master-volume", "Master Volume", &d.masterVolume)
	vol("settings.music-volume", "Music", &d.musicVolume)
	vol("settings.sfx-volume", "Sound Effects", &d.sfxVolume)
	UI_PropLabel("")
	UI_DimText("Music and sound nodes play at their own volume times these.")
	UI_EndProps()
}

// project_accessibility: the players' default accessibility settings
// (each player changes their own in the game: Accessibility.set / the
// Accessibility Menu template).
@(private = "file")
project_accessibility :: proc(state: ^EditorState) {
	d := &st.project
	a := e.ProjectConfig_Accessibility(d)
	before := a
	if !UI_BeginProps("##access") do return
	UI_PropLabel("UI Scale")
	imgui.SliderFloat("##acc_ui", &a.uiScale, 0.5, 3, "%.2fx")
	Drive_Item("settings.acc-ui-scale")
	UI_Tooltip("Top-level UI elements grow around the screen corner / edge / centre they're nearest to")
	UI_PropLabel("Colour Filter")
	cb := i32(a.colorblind)
	if imgui.Combo("##acc_cb", &cb, "Off\x00Protanopia\x00Deuteranopia\x00Tritanopia\x00\x00") do a.colorblind = e.Colorblind_Mode(cb)
	Drive_Item("settings.acc-colorblind")
	UI_Tooltip("Corrects the picture for players with that colour vision deficiency (View > Colour Vision previews how they see the scene)")
	UI_PropLabel("Filter Strength")
	imgui.SliderFloat("##acc_cbs", &a.colorblindStrength, 0, 1, "%.2f")
	check("settings.acc-subtitles", "Subtitles", &a.subtitles, "Spoken lines on the subtitle track (dialogue in Subtitles mode, Subtitles.show)")
	check("settings.acc-captions", "Sound Captions", &a.captions, "Sounds' captions on the subtitle track (a Sound / Music node's Caption)")
	UI_PropLabel("Subtitle Size")
	imgui.SliderFloat("##acc_ss", &a.subtitleScale, 0.5, 3, "%.2fx")
	UI_PropLabel("Subtitle Backdrop")
	imgui.SliderFloat("##acc_sb", &a.subtitleBackground, 0, 1, "%.2f")
	UI_PropLabel("Screen Shake")
	imgui.SliderFloat("##acc_shake", &a.screenShake, 0, 2, "%.2fx")
	Drive_Item("settings.acc-shake")
	UI_Tooltip("Scales every camera shake and trauma (0 = no shake)")
	UI_EndProps()
	imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
	imgui.TextWrapped("The defaults every player starts with. Players change theirs in the game - see the Accessibility Menu script template.")
	imgui.PopStyleColor()
	if a != before do e.ProjectConfig_SetAccessibility(d, a)
}

@(private = "file")
project_export :: proc(state: ^EditorState) {
	d := &st.project
	x := &d.export
	if UI_BeginProps("##export") {
		UI_PropLabel("Executable Name")
		text_field("settings.export-name", &x.executableName, strings.clone_to_cstring(export_default_name(d), context.temp_allocator))
		UI_PropLabel("Output Folder")
		folder_field(state, "settings.export-dir", &x.outputDir, fmt.tprintf("%s_standalone", strings.trim_suffix(state.projectPath, "/")))
		if len(x.presets) == 0 {
			UI_PropLabel("Targets")
			for t in e.Export_Target {
				on := t in x.targets
				label := fmt.ctprintf("%s##tgt%v", e.export_target_name(t), t)
				if imgui.Checkbox(label, &on) {
					if on do x.targets += {t}
					else do x.targets -= {t}
				}
				Drive_Item(fmt.tprintf("settings.target:%s", e.export_target_name(t)))
				imgui.SameLine()
			}
			imgui.NewLine()
		}
		UI_PropLabel("Runners")
		{
			sb := strings.builder_make(context.temp_allocator)
			for t in e.Export_Target {
				if strings.builder_len(sb) > 0 do strings.write_string(&sb, "   ")
				found := Editor_FindRunner(t) != ""
				fmt.sbprintf(&sb, "%s %s", e.export_target_name(t), "ready" if found else ("built on export" if t == e.native_export_target() else "missing"))
			}
			UI_DimText(strings.to_string(sb))
			Drive_Item("settings.runners")
			UI_Tooltip("Prebuilt game runners (runners/<platform>/ next to the editor, or bin/runners/). Build one per platform with scripts/build_runners.sh")
		}
		check("settings.compress", "Compress Package", &x.compress)
		check("settings.include-font", "Include UI Font", &x.includeFont)
		hasMac := false
		for &p in e.Export_EffectivePresets(x) do if p.target == .MacOS do hasMac = true
		if hasMac {
			exeName := x.executableName if x.executableName != "" else export_default_name(d)
			UI_PropLabel("macOS Bundle ID")
			text_field("settings.bundle-id", &x.bundleId, strings.clone_to_cstring(Export_BundleId(d, exeName), context.temp_allocator))
			UI_PropLabel("Signing Identity")
			text_field("settings.mac-sign", &x.macSign, "ad-hoc (or \"Developer ID Application: ...\", or none)")
			UI_Tooltip("codesign identity for the .app. Ad-hoc runs on this Mac; a Developer ID is needed to distribute (and to notarize)")
			UI_PropLabel("Notary Profile")
			text_field("settings.mac-notary", &x.macNotaryProfile, "keychain profile (xcrun notarytool store-credentials)")
			UI_Tooltip("With a Developer ID identity: the app is notarized and stapled after export")
		}
		UI_EndProps()
	}
	export_presets_section(state)
	imgui.Spacing()
	if UI_PrimaryButton(fmt.tprintf("%s  Save and Export%s", ICON_FA_FLOPPY_DISK, " All" if len(x.presets) > 1 else ""), "settings.export-now") {
		settings_save(state)
		Editor_ExportStandalone(state)
	}
}

@(private = "file")
presetSel: int

@(private = "file")
export_presets_section :: proc(state: ^EditorState) {
	d := &st.project
	x := &d.export
	imgui.SeparatorText("Presets")
	platforms := []string{"macos", "windows", "linux", "web"}
	if len(x.presets) == 0 {
		UI_DimText("One export per target above. Presets give each platform (or a demo / debug build) its own settings.")
		if UI_Button(fmt.tprintf("%s  Use Presets", ICON_FA_PLUS), "settings.preset-convert") {
			for &p in e.Export_EffectivePresets(x) do append(&x.presets, e.Export_Preset{name = strings.clone(p.name), target = p.target})
			presetSel = 0
		}
		return
	}
	presetSel = clamp(presetSel, 0, len(x.presets) - 1)
	// The list.
	for &p, i in x.presets {
		label := fmt.ctprintf("%s  (%s%s)##preset%d", p.name, e.export_target_name(p.target), ", debug" if p.debug else "", i)
		if imgui.Selectable(label, presetSel == i) do presetSel = i
		Drive_Item(fmt.tprintf("settings.preset:%s", p.name))
	}
	if imgui.BeginCombo("##addpreset", fmt.ctprintf("%s  Add Preset", ICON_FA_PLUS), {.NoArrowButton}) {
		for name, k in platforms {
			if imgui.Selectable(strings.clone_to_cstring(name, context.temp_allocator)) {
				n := name
				for j := 2; ; j += 1 {
					taken := false
					for q in x.presets do if q.name == n do taken = true
					if !taken do break
					n = fmt.tprintf("%s %d", name, j)
				}
				append(&x.presets, e.Export_Preset{name = strings.clone(n), target = e.Export_Target(k)})
				presetSel = len(x.presets) - 1
			}
			Drive_Item(fmt.tprintf("pick:%s", name))
		}
		imgui.EndCombo()
	}
	Drive_Item("settings.preset-add")
	imgui.SameLine()
	if UI_Button(fmt.tprintf("%s  Duplicate", ICON_FA_COPY), "settings.preset-dup") {
		c := e.Export_Preset_Clone(&x.presets[presetSel])
		delete(c.name)
		c.name = strings.clone(fmt.tprintf("%s copy", x.presets[presetSel].name))
		append(&x.presets, c)
		presetSel = len(x.presets) - 1
	}
	imgui.SameLine()
	if UI_Button(fmt.tprintf("%s  Remove", ICON_FA_TRASH), "settings.preset-remove") {
		e.Export_Preset_Destroy(&x.presets[presetSel])
		ordered_remove(&x.presets, presetSel)
		if len(x.presets) == 0 do return
		presetSel = clamp(presetSel, 0, len(x.presets) - 1)
	}

	// The selected preset.
	p := &x.presets[presetSel]
	imgui.PushIDInt(i32(presetSel))
	defer imgui.PopID()
	if !UI_BeginProps("##preset") do return
	defer UI_EndProps()
	UI_PropLabel("Name")
	text_field("settings.preset-name", &p.name)
	UI_PropLabel("Platform")
	imgui.SetNextItemWidth(-1)
	if k, changed := UI_Combo("settings.preset-platform", int(p.target), platforms); changed do p.target = e.Export_Target(k)
	exeDefault := x.executableName if x.executableName != "" else export_default_name(d)
	UI_PropLabel("Executable Name")
	text_field("settings.preset-exe", &p.executableName, strings.clone_to_cstring(exeDefault, context.temp_allocator))
	outDefault := fmt.tprintf("%s/%s", x.outputDir if x.outputDir != "" else fmt.tprintf("%s_standalone", strings.trim_suffix(state.projectPath, "/")), export_safe_name(p.name))
	UI_PropLabel("Output Folder")
	folder_field(state, "settings.preset-dir", &p.outputDir, outDefault)
	UI_PropLabel("Version")
	text_field("settings.preset-version", &p.version, strings.clone_to_cstring(fmt.tprintf("project: %s", d.version), context.temp_allocator))
	UI_PropLabel("Icon")
	imgui.SetNextItemWidth(-1)
	if path, ok := asset_picker("settings.preset-icon", p.icon, Editor_ListProjectFiles(state, "", {".png"})); ok {
		delete(p.icon)
		p.icon = strings.clone(path)
	}
	UI_Tooltip("None = the project's icon")
	UI_PropLabel("Window Title")
	text_field("settings.preset-title", &p.windowTitle, strings.clone_to_cstring(fmt.tprintf("project: %s", d.windowTitle), context.temp_allocator))
	UI_PropLabel("Window Size")
	size := [2]i32{i32(p.windowWidth), i32(p.windowHeight)}
	imgui.SetNextItemWidth(-1)
	if imgui.DragInt2("##presetsize", &size, 1, 0, 8192, "%d") {
		p.windowWidth, p.windowHeight = int(max(size.x, 0)), int(max(size.y, 0))
	}
	Drive_Item("settings.preset-size")
	UI_Tooltip("0 x 0 = the project's window size")
	UI_PropLabel("Fullscreen")
	imgui.SetNextItemWidth(-1)
	if k, changed := UI_Combo("settings.preset-fullscreen", int(p.fullscreen), {"Project setting", "On", "Off"}); changed do p.fullscreen = e.Export_Toggle(k)
	UI_PropLabel("Include")
	pattern_list("settings.preset-include", &p.include, "everything (or one pattern per line: scenes, textures/*.png)")
	UI_PropLabel("Exclude")
	pattern_list("settings.preset-exclude", &p.exclude, "one pattern per line: *.psd, raw/, levels/test_*")
	UI_PropLabel("Debug")
	imgui.Checkbox("##presetdebug", &p.debug)
	Drive_Item("settings.preset-debug")
	UI_Tooltip("Use the debug runner (debug info; a console window on Windows)")
	UI_PropLabel("")
	if UI_Button(fmt.tprintf("%s  Save and Export This Preset", ICON_FA_BOX_ARCHIVE), "settings.export-preset") {
		settings_save(state)
		Editor_ExportStandalone(state, only = presetSel)
	}
}

// pattern_list edits a list of patterns as lines of text.
@(private = "file")
pattern_list :: proc(id: string, list: ^[dynamic]string, hint: string) {
	@(static) buf: [2048]u8
	@(static) editing: string
	if editing != id {
		joined := strings.join(list[:], "\n", context.temp_allocator)
		buf = {}
		copy(buf[:len(buf) - 1], joined)
	}
	if imgui.InputTextMultiline(fmt.ctprintf("##%s", id), cstring(raw_data(buf[:])), len(buf), {-1, 54}) {
		for s in list do delete(s)
		clear(list)
		for line in strings.split_lines(string(cstring(raw_data(buf[:]))), context.temp_allocator) {
			if t := strings.trim_space(line); t != "" do append(list, strings.clone(t))
		}
	}
	if imgui.IsItemActivated() {
		delete(editing)
		editing = strings.clone(id)
	}
	if imgui.IsItemDeactivated() {
		delete(editing)
		editing = ""
	}
	Drive_Item(id)
	if len(list) == 0 do UI_Tooltip(hint)
}

export_default_name :: proc(d: ^e.ProjectConfig) -> string {
	n, _ := strings.remove_all(d.name, " ", context.temp_allocator)
	n, _ = strings.remove_all(n, "(", context.temp_allocator)
	n, _ = strings.remove_all(n, ")", context.temp_allocator)
	n, _ = strings.remove_all(n, ".", context.temp_allocator)
	return n if n != "" else "Game"
}

// --- Plugins (plugins.odin) - changes here apply at once -------------------------

@(private = "file")
settings_plugins :: proc(state: ^EditorState, h: f32) {
	list := Plugins_List()
	// This project's trust.
	switch v in Plugins_Trusted() {
	case bool:
		UI_DimText("This project's plugins are allowed to run." if v else "This project's plugins are blocked.")
		imgui.SameLine()
		if UI_Button("Block" if v else "Allow", "plugins.trust.toggle") do Plugins_SetTrust(state, !v)
	case:
		UI_DimText("This project's plugins haven't been allowed yet.")
		imgui.SameLine()
		if UI_Button("Allow", "plugins.trust.toggle") do Plugins_SetTrust(state, true)
	}
	imgui.SameLine()
	if UI_Button(fmt.tprintf("%s  Rescan", ICON_FA_ROTATE_RIGHT), "plugins.rescan") do Plugins_Load(state, ask = false)
	UI_Tooltip("Find plugins again (after adding or removing a plugin folder)")
	imgui.SameLine()
	if UI_Button(fmt.tprintf("%s  User Plugins Folder", ICON_FA_FOLDER_OPEN), "plugins.user-folder") {
		dir := Plugins_UserDir()
		_ = os.make_directory_all(dir)
		Editor_OpenExternally(state, dir)
	}
	UI_Tooltip("Plugins here run in every project (one folder each, with a plugin.json)")
	imgui.Spacing()
	h := h - imgui.GetFrameHeightWithSpacing() - 8
	if len(list) == 0 {
		UI_DimText("No plugins. A plugin is a folder with a plugin.json and Lua files, in the project's plugins/ folder or the user plugins folder.")
		return
	}
	st.pluginSel = clamp(st.pluginSel, 0, len(list) - 1)
	if imgui.BeginChild("##plug_list", {220, h}, {.Borders}, {}) {
		for p, i in list {
			mark := ICON_FA_CIRCLE_CHECK
			col := UI_SUCCESS
			#partial switch p.state {
			case .Off, .Untrusted: mark, col = ICON_FA_CIRCLE, UI_TEXT_FAINT
			case .Failed: mark, col = ICON_FA_CIRCLE_XMARK, UI_DANGER
			}
			imgui.TextColored(col, "%s", fmt.ctprintf("%s", mark))
			imgui.SameLine()
			if imgui.Selectable(fmt.ctprintf("%s##plug%d", p.name, i), st.pluginSel == i) do st.pluginSel = i
			Drive_Item(fmt.tprintf("plugins.item:%s", p.id))
		}
	}
	imgui.EndChild()
	imgui.SameLine(0, UI_SPACE * 2)
	if imgui.BeginChild("##plug_body", {0, h}, {}, {}) {
		p := list[st.pluginSel]
		imgui.PushFont(GlobalFonts.semibold)
		imgui.TextUnformatted(fmt.ctprintf("%s  %s", p.name, p.version))
		imgui.PopFont()
		UI_DimText(fmt.tprintf("%s plugin - %s", "Project" if p.scope == .Project else "User", p.dir))
		if p.description != "" do imgui.TextWrapped("%s", fmt.ctprintf("%s", p.description))
		if p.permissions != {} {
			perms := make([dynamic]string, context.temp_allocator)
			if .Process in p.permissions do append(&perms, "runs programs")
			if .Network in p.permissions do append(&perms, "uses the network")
			UI_DimText(fmt.tprintf("Permissions: %s", strings.join(perms[:], ", ", context.temp_allocator)))
		}
		switch p.state {
		case .Running:   imgui.TextColored(UI_SUCCESS, "Running")
		case .Off:       imgui.TextColored(UI_TEXT_FAINT, "Off")
		case .Untrusted: imgui.TextColored(UI_TEXT_FAINT, "Waiting: this project's plugins aren't allowed")
		case .Failed:    imgui.TextColored(UI_DANGER, "%s", fmt.ctprintf("Stopped: %s", p.error))
		}
		Drive_Item("plugins.state")
		on := p.state != .Off
		if imgui.Checkbox("Enabled##plug_on", &on) do Plugin_SetOff(state, p, !on)
		Drive_Item("plugins.enabled")
		imgui.SameLine()
		if UI_Button(fmt.tprintf("%s  Reload", ICON_FA_ROTATE), "plugins.reload") && p.state != .Off && p.state != .Untrusted do Plugin_Reload(state, p)
		UI_Tooltip("Stop and start it again (saving its files reloads it too)")
		imgui.SameLine()
		if UI_Button(fmt.tprintf("%s  Open Folder", ICON_FA_FOLDER_OPEN), "plugins.folder") do Editor_OpenExternally(state, p.dir)
		imgui.SeparatorText("Log")
		if imgui.BeginChild("##plug_log", {0, 0}, {.Borders}, {}) {
			for l in p.log do imgui.TextWrapped("%s", fmt.ctprintf("%s", l))
			if imgui.GetScrollY() >= imgui.GetScrollMaxY() do imgui.SetScrollHereY(1)
		}
		imgui.EndChild()
	}
	imgui.EndChild()
}
