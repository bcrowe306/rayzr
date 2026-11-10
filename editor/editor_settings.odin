package editor

import "core:encoding/ini"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Editor settings (per user, not per project): ~/.config/rayzr_editor/
// settings.ini - general options, code editor, theme, recent projects,
// keymap, one [section] each. Edited in Settings > General / Code Editor.
// An older settings.json is read once and replaced. Test drives use a file
// inside the drive's project copy so they never touch the user's.
// ============================================================================

// Show_Whitespace: dots / arrows for spaces and tabs in the Code tab.
Show_Whitespace :: enum {
	None,
	Selection, // inside selections (Zed's default)
	All,
}

Editor_Settings :: struct {
	// General > Basic
	uiScale:          f32,  // ImGui font scale
	autosaveMinutes:  int,  // 0 = off
	gridSize:         f32,
	snapToGrid:       bool,
	showGrid:         bool,
	confirmQuit:      bool,
	showWelcome:      bool, // the Welcome window at startup
	checkUpdates:     bool, // look for a newer release at startup (update_check.odin)
	showTabBars:      bool, // View > Show Tab Bars: every docked window keeps its tab
	autoBottomPanel:  bool, // the bottom panel shows the selected node's tool tab
	hiddenBottomTabs: bit_set[BottomTab], // View > Bottom Panel: tabs left out (#194)
	previewShape:     int, // the screen shape the Expand camera frame is shown for (PREVIEW_SHAPES, #202)
	previewAutoplay:  bool, // File Browser / Assets: play a sound or animation when selected (#203)
	previewLoop:      bool, // ... and loop it
	previewVolume:    f32,  // ... at this volume
	window:           Window_State, // the editor window as it was left (window_state.odin, #265)
	// Code Editor
	codeFontSize:     f32,
	tabWidth:         int,
	insertSpaces:     bool, // for files without an indentation style yet
	autoClosePairs:   bool,
	rainbowBrackets:  bool, // brackets coloured by depth (Code tab)
	indentGuides:     bool, // vertical lines at each indent level
	softWrap:         bool, // long lines wrap at the Code area's width
	stickyScroll:     bool, // block headers stay at the top while scrolling
	breadcrumbs:      bool, // file > function > blocks bar above the code
	inlayHints:       bool, // parameter names before call arguments
	colorSwatches:    bool, // a swatch before {r, g, b[, a]} colour tables
	showWhitespace:   Show_Whitespace,
	formatOnSave:     bool,
	lspEnabled:       bool,
	luaServerPath:    string, // "" = lua-language-server/ in the engine checkout
	asepritePath:     string, // the Aseprite program ("" = found: aseprite_editor.odin)
	registryUrl:      string, // the plugin / template registry's index ("" = the official one: registry.odin)
	// General > Keymap: action id -> chords (replaces the defaults)
	keymap:           map[string][3]Chord,
	// File > Open Recent (absolute project paths, most recent first)
	recentProjects:   [dynamic]string,
	// The editor's colours (theme.odin)
	theme:            Theme,
	// Folders used last (dialogs open there): imports, exports, projects.
	lastImportDir:    string,
	lastExportDir:    string,
	lastProjectDir:   string,
	// LDtk projects' custom commands: project iid -> allowed / blocked
	ldtkTrust:        map[string]bool,
	pluginTrust:      map[string]bool, // project folder -> its plugins allowed (true) / blocked (plugins.odin)
	pluginsOff:       map[string]bool, // plugin folders turned off in Settings > Plugins
	// File Browser (file_browser.odin): open, its folder, bookmarked and
	// recent folders (absolute, most recent first) - the same in every project.
	fileBrowserOpen:      bool,
	fileBrowserDir:       string,
	fileBrowserBookmarks: [dynamic]string,
	fileBrowserRecent:    [dynamic]string,
}

DEFAULT_EDITOR_SETTINGS :: Editor_Settings{
	uiScale         = 1,
	autosaveMinutes = 0,
	gridSize        = 32,
	snapToGrid      = true,
	showGrid        = true,
	confirmQuit     = true,
	showWelcome     = true,
	checkUpdates    = true,
	autoBottomPanel = true,
	previewAutoplay = true,
	previewLoop = true,
	previewVolume = 0.8,
	codeFontSize    = CODE_FONT_SIZE,
	tabWidth        = 4,
	insertSpaces    = true,
	autoClosePairs  = true,
	rainbowBrackets = true,
	indentGuides    = true,
	showWhitespace  = .Selection,
	stickyScroll    = true,
	breadcrumbs     = true,
	inlayHints      = true,
	colorSwatches   = true,
	formatOnSave    = false,
	lspEnabled      = true,
}

Editor_DefaultSettings :: proc() -> Editor_Settings {
	s := DEFAULT_EDITOR_SETTINGS
	s.theme = Theme_PresetColors(.Default)
	s.theme.name = strings.clone(s.theme.name)
	return s
}

GlobalSettings := DEFAULT_EDITOR_SETTINGS
settingsPath: string

Editor_Settings_Clone :: proc(s: ^Editor_Settings) -> Editor_Settings {
	c := s^
	c.luaServerPath = strings.clone(s.luaServerPath)
	c.asepritePath = strings.clone(s.asepritePath)
	c.registryUrl = strings.clone(s.registryUrl)
	c.keymap = make(map[string][3]Chord)
	for k, v in s.keymap do c.keymap[strings.clone(k)] = v
	c.recentProjects = make([dynamic]string)
	for r in s.recentProjects do append(&c.recentProjects, strings.clone(r))
	c.theme.name = strings.clone(s.theme.name)
	c.lastImportDir = strings.clone(s.lastImportDir)
	c.lastExportDir = strings.clone(s.lastExportDir)
	c.lastProjectDir = strings.clone(s.lastProjectDir)
	c.ldtkTrust = make(map[string]bool)
	for k, v in s.ldtkTrust do c.ldtkTrust[strings.clone(k)] = v
	c.pluginTrust = make(map[string]bool)
	for k, v in s.pluginTrust do c.pluginTrust[strings.clone(k)] = v
	c.pluginsOff = make(map[string]bool)
	for k, v in s.pluginsOff do c.pluginsOff[strings.clone(k)] = v
	c.fileBrowserDir = strings.clone(s.fileBrowserDir)
	c.fileBrowserBookmarks = make([dynamic]string)
	for b in s.fileBrowserBookmarks do append(&c.fileBrowserBookmarks, strings.clone(b))
	c.fileBrowserRecent = make([dynamic]string)
	for r in s.fileBrowserRecent do append(&c.fileBrowserRecent, strings.clone(r))
	return c
}

Editor_Settings_Destroy :: proc(s: ^Editor_Settings) {
	delete(s.luaServerPath)
	delete(s.asepritePath)
	delete(s.registryUrl)
	for k in s.keymap do delete(k)
	delete(s.keymap)
	s.keymap = nil
	for r in s.recentProjects do delete(r)
	delete(s.recentProjects)
	s.recentProjects = nil
	s.luaServerPath = ""
	s.asepritePath = ""
	s.registryUrl = ""
	delete(s.theme.name)
	s.theme.name = ""
	delete(s.lastImportDir)
	delete(s.lastExportDir)
	delete(s.lastProjectDir)
	s.lastImportDir, s.lastExportDir, s.lastProjectDir = "", "", ""
	for k in s.ldtkTrust do delete(k)
	delete(s.ldtkTrust)
	s.ldtkTrust = nil
	for k in s.pluginTrust do delete(k)
	delete(s.pluginTrust)
	s.pluginTrust = nil
	for k in s.pluginsOff do delete(k)
	delete(s.pluginsOff)
	s.pluginsOff = nil
	delete(s.fileBrowserDir)
	s.fileBrowserDir = ""
	for b in s.fileBrowserBookmarks do delete(b)
	delete(s.fileBrowserBookmarks)
	s.fileBrowserBookmarks = nil
	for r in s.fileBrowserRecent do delete(r)
	delete(s.fileBrowserRecent)
	s.fileBrowserRecent = nil
}

// Editor_SettingsPath: where settings live (drives: inside the project copy).
// Editor_MigrateLegacyConfig moves the editor's per-user folder from its
// name before the rename (~/.config/ore_editor: settings, recent projects,
// workspaces, plugins, crash reports) to ~/.config/rayzr_editor - once.
// Not in test drives or with --user-data (they never touch the real one).
Editor_MigrateLegacyConfig :: proc() {
	for a in os.args do if a == "--drive" || a == "--user-data" || a == "--test-e2e" do return
	home, err := os.user_home_dir(context.temp_allocator)
	if err != nil do return
	old, _ := filepath.join({home, ".config", "ore_editor"}, context.temp_allocator)
	new_, _ := filepath.join({home, ".config", "rayzr_editor"}, context.temp_allocator)
	e.Legacy_MigrateDir(old, new_)
}

Editor_SettingsFilePath :: proc(state: ^EditorState) -> string {
	if GlobalDrive.enabled {
		p, _ := filepath.join({state.projectPath, ".editor_settings.ini"}, context.allocator)
		return p
	}
	home, err := os.user_home_dir(context.temp_allocator)
	if err != nil do return strings.clone(".editor_settings.ini")
	p, _ := filepath.join({home, ".config", "rayzr_editor", "settings.ini"}, context.allocator)
	return p
}

// --- chords as text ----------------------------------------------------------------

// Chord_Parse reads Chord_Text's format ("Cmd+Shift+P", "Ctrl+G", "F5").
Chord_Parse :: proc(text: string) -> (c: Chord, ok: bool) {
	parts := strings.split(text, "+", context.temp_allocator)
	if len(parts) == 0 do return
	for p, i in parts {
		if i < len(parts) - 1 {
			switch strings.to_lower(p, context.temp_allocator) {
			case "cmd", "primary": c.mods += {.Primary}
			case "ctrl":
				when ODIN_OS == .Darwin do c.mods += {.Ctrl}
				else do c.mods += {.Primary}
			case "shift": c.mods += {.Shift}
			case "alt", "opt": c.mods += {.Alt}
			case: return {}, false
			}
			continue
		}
		key := p
		if key == "" && strings.has_suffix(text, "++") do key = "+"
		for k in imgui.Key.Tab ..= imgui.Key.F12 {
			if strings.equal_fold(Chord_Text({k, {}}), key) {
				c.key = k
				return c, true
			}
		}
	}
	return {}, false
}

// --- load / save -------------------------------------------------------------------

Editor_LoadSettings :: proc(state: ^EditorState) {
	if settingsPath != "" do delete(settingsPath)
	settingsPath = Editor_SettingsFilePath(state)
	Editor_Settings_Destroy(&GlobalSettings)
	GlobalSettings = Editor_DefaultSettings()
	if data, err := os.read_entire_file(settingsPath, context.temp_allocator); err == nil {
		settings_from_ini(string(data))
	} else {
		// An older settings.json next to it: read once, saved as .ini below.
		jsonPath := strings.concatenate({strings.trim_suffix(settingsPath, ".ini"), ".json"}, context.temp_allocator)
		if jdata, jerr := os.read_entire_file(jsonPath, context.temp_allocator); jerr == nil do settings_from_json(jdata)
	}
	Editor_ApplySettings(state)
	Editor_AddRecentProject(state.projectPath)
	_ = Editor_SaveSettings()
}

// Editor_RecentProjectsAtStartup: the recent projects (temp), read before
// the project opens (resources.odin: the default project) - the settings
// are loaded properly later (Editor_LoadSettings).
Editor_RecentProjectsAtStartup :: proc() -> []string {
	home, err := os.user_home_dir(context.temp_allocator)
	if err != nil do return nil
	path, _ := filepath.join({home, ".config", "rayzr_editor", "settings.ini"}, context.temp_allocator)
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil do return nil
	Editor_Settings_Destroy(&GlobalSettings)
	GlobalSettings = Editor_DefaultSettings()
	settings_from_ini(string(data))
	out := make([]string, len(GlobalSettings.recentProjects), context.temp_allocator)
	for r, i in GlobalSettings.recentProjects do out[i] = strings.clone(r, context.temp_allocator)
	return out
}

@(private = "file")
settings_from_json :: proc(data: []u8) {
	err: os.Error
	if err == nil {
		val, perr := json.parse(data, allocator = context.temp_allocator)
		if obj, ok := val.(json.Object); perr == .None && ok {
			s := &GlobalSettings
			s.uiScale = jf(obj, "ui_scale", s.uiScale)
			s.autosaveMinutes = int(jf(obj, "autosave_minutes", f32(s.autosaveMinutes)))
			s.gridSize = jf(obj, "grid_size", s.gridSize)
			s.snapToGrid = jb(obj, "snap_to_grid", s.snapToGrid)
			s.showGrid = jb(obj, "show_grid", s.showGrid)
			s.confirmQuit = jb(obj, "confirm_quit", s.confirmQuit)
			s.showWelcome = jb(obj, "show_welcome", s.showWelcome)
			s.codeFontSize = jf(obj, "code_font_size", s.codeFontSize)
			s.tabWidth = int(jf(obj, "tab_width", f32(s.tabWidth)))
			s.insertSpaces = jb(obj, "insert_spaces", s.insertSpaces)
			s.autoClosePairs = jb(obj, "auto_close_pairs", s.autoClosePairs)
			s.formatOnSave = jb(obj, "format_on_save", s.formatOnSave)
			s.lspEnabled = jb(obj, "lsp_enabled", s.lspEnabled)
			if p, has := obj["lua_server_path"].(json.String); has do s.luaServerPath = strings.clone(string(p))
			if rp, has := obj["recent_projects"].(json.Array); has {
				for v in rp do if p, isStr := v.(json.String); isStr do append(&s.recentProjects, strings.clone(string(p)))
			}
			if km, has := obj["keymap"].(json.Object); has {
				s.keymap = make(map[string][3]Chord)
				for id, v in km {
					arr, isArr := v.(json.Array)
					if !isArr do continue
					chords: [3]Chord
					n := 0
					for cv in arr {
						if cs, isStr := cv.(json.String); isStr && n < 3 {
							if c, cok := Chord_Parse(string(cs)); cok {
								chords[n] = c
								n += 1
							}
						}
					}
					s.keymap[strings.clone(id)] = chords
				}
			}
		}
	}
}

// settings_from_ini reads settings.ini (missing keys keep their defaults).
settings_from_ini :: proc(text: string) {
	m, _ := ini.load_map_from_string(text, context.temp_allocator)
	s := &GlobalSettings
	// (A missing section is a nil map: look it up first - indexing straight
	// through it crashed on a settings.ini without every section.)
	get :: proc(m: ini.Map, sec, key: string) -> (string, bool) {
		sm, has := m[sec]
		if !has || sm == nil do return "", false
		v, ok := sm[key]
		return v, ok
	}
	f :: proc(m: ini.Map, sec, key: string, d: f32) -> f32 {
		if v, ok := get(m, sec, key); ok do if x, pok := strconv.parse_f32(v); pok do return x
		return d
	}
	b :: proc(m: ini.Map, sec, key: string, d: bool) -> bool {
		if v, ok := get(m, sec, key); ok do return v == "true" || v == "1" || v == "yes"
		return d
	}
	s.uiScale = f(m, "general", "ui_scale", s.uiScale)
	s.autosaveMinutes = int(f(m, "general", "autosave_minutes", f32(s.autosaveMinutes)))
	s.gridSize = f(m, "general", "grid_size", s.gridSize)
	s.snapToGrid = b(m, "general", "snap_to_grid", s.snapToGrid)
	s.showGrid = b(m, "general", "show_grid", s.showGrid)
	s.confirmQuit = b(m, "general", "confirm_quit", s.confirmQuit)
	s.showWelcome = b(m, "general", "show_welcome", s.showWelcome)
	s.checkUpdates = b(m, "general", "check_updates", s.checkUpdates)
	s.showTabBars = b(m, "general", "show_tab_bars", s.showTabBars)
	s.autoBottomPanel = b(m, "general", "auto_bottom_panel", s.autoBottomPanel)
	if _, has := m["window"]; has {
		w := &s.window
		w.saved = true
		w.x, w.y = i32(f(m, "window", "x", 0)), i32(f(m, "window", "y", 0))
		w.w, w.h = i32(f(m, "window", "width", 1600)), i32(f(m, "window", "height", 900))
		w.maximized = b(m, "window", "maximized", false)
		w.monitor = i32(f(m, "window", "monitor", 0))
	}
	if shape, ok := get(m, "general", "preview_shape"); ok {
		for p, i in PREVIEW_SHAPES do if p.name == shape do s.previewShape = i
	}
	if pv, ok := m["preview"]; ok {
		if v, vok := pv["autoplay"]; vok do s.previewAutoplay = v == "true"
		if v, vok := pv["loop"]; vok do s.previewLoop = v == "true"
		if v, vok := pv["volume"]; vok do if x, pok := strconv.parse_f32(v); pok do s.previewVolume = clamp(x, 0, 1)
	}
	if hidden, ok := get(m, "general", "hidden_bottom_tabs"); ok {
		s.hiddenBottomTabs = {}
		for name in strings.split(hidden, ",", context.temp_allocator) {
			for t in BottomTab do if fmt.tprint(t) == strings.trim_space(name) do s.hiddenBottomTabs += {t}
		}
	}
	s.codeFontSize = f(m, "code", "font_size", s.codeFontSize)
	s.tabWidth = int(f(m, "code", "tab_width", f32(s.tabWidth)))
	s.insertSpaces = b(m, "code", "insert_spaces", s.insertSpaces)
	s.autoClosePairs = b(m, "code", "auto_close_pairs", s.autoClosePairs)
	s.rainbowBrackets = b(m, "code", "rainbow_brackets", s.rainbowBrackets)
	s.indentGuides = b(m, "code", "indent_guides", s.indentGuides)
	s.softWrap = b(m, "code", "soft_wrap", s.softWrap)
	s.stickyScroll = b(m, "code", "sticky_scroll", s.stickyScroll)
	s.breadcrumbs = b(m, "code", "breadcrumbs", s.breadcrumbs)
	s.inlayHints = b(m, "code", "inlay_hints", s.inlayHints)
	s.colorSwatches = b(m, "code", "color_swatches", s.colorSwatches)
	if v, ok := get(m, "code", "show_whitespace"); ok {
		switch v {
		case "none": s.showWhitespace = .None
		case "all": s.showWhitespace = .All
		case: s.showWhitespace = .Selection
		}
	}
	s.formatOnSave = b(m, "code", "format_on_save", s.formatOnSave)
	s.lspEnabled = b(m, "code", "lsp_enabled", s.lspEnabled)
	if v, ok := get(m, "code", "lua_server_path"); ok && v != "" do s.luaServerPath = strings.clone(v)
	// (Look the section up first: chaining through a missing one crashed.)
	if tools, has := m["tools"]; has {
		if v, ok := tools["aseprite_path"]; ok && v != "" do s.asepritePath = strings.clone(v)
		if v, ok := tools["registry_url"]; ok && v != "" do s.registryUrl = strings.clone(v)
	}
	if th, ok := m["theme"]; ok {
		if name, has := th["name"]; has && name != "" {
			delete(s.theme.name)
			s.theme.name = strings.clone(name)
		}
		for k in Theme_Color {
			if v, has := th[THEME_COLOR_INFO[k].key]; has {
				if c, cok := theme_parse_color(v); cok do s.theme.colors[k] = c
			}
		}
	}
	if pm, ok := m["paths"]; ok {
		if v := pm["import"] or_else ""; v != "" do s.lastImportDir = strings.clone(v)
		if v := pm["export"] or_else ""; v != "" do s.lastExportDir = strings.clone(v)
		if v := pm["projects"] or_else ""; v != "" do s.lastProjectDir = strings.clone(v)
	}
	if lt, ok := m["ldtk_trust"]; ok {
		for k, v in lt do s.ldtkTrust[strings.clone(k)] = v == "true"
	}
	if pt, ok := m["plugin_trust"]; ok {
		if s.pluginTrust == nil do s.pluginTrust = make(map[string]bool)
		for k, v in pt do s.pluginTrust[strings.clone(k)] = v == "true"
	}
	if po, ok := m["plugins_off"]; ok {
		if s.pluginsOff == nil do s.pluginsOff = make(map[string]bool)
		for k, v in po do if v == "true" do s.pluginsOff[strings.clone(k)] = true
	}
	if rp, ok := m["recent_projects"]; ok {
		for i in 0 ..< len(rp) {
			if v, has := rp[fmt.tprint(i)]; has && v != "" do append(&s.recentProjects, strings.clone(v))
		}
	}
	if fbm, ok := m["file_browser"]; ok {
		s.fileBrowserOpen = (fbm["open"] or_else "") == "true"
		if v := fbm["dir"] or_else ""; v != "" do s.fileBrowserDir = strings.clone(v)
	}
	if bm, ok := m["file_browser_bookmarks"]; ok {
		for i in 0 ..< len(bm) {
			if v, has := bm[fmt.tprint(i)]; has && v != "" do append(&s.fileBrowserBookmarks, strings.clone(v))
		}
	}
	if fr, ok := m["file_browser_recent"]; ok {
		for i in 0 ..< len(fr) {
			if v, has := fr[fmt.tprint(i)]; has && v != "" do append(&s.fileBrowserRecent, strings.clone(v))
		}
	}
	if km, ok := m["keymap"]; ok {
		s.keymap = make(map[string][3]Chord)
		for id, v in km {
			chords: [3]Chord
			n := 0
			for cs in strings.split(v, ",", context.temp_allocator) {
				t := strings.trim_space(cs)
				if t == "" || n >= 3 do continue
				if c, cok := Chord_Parse(t); cok {
					chords[n] = c
					n += 1
				}
			}
			s.keymap[strings.clone(id)] = chords
		}
	}
}

// Editor_AddRecentProject moves a project to the top of File > Open Recent.
Editor_AddRecentProject :: proc(path: string) {
	abs := path
	if !filepath.is_abs(path) {
		if cwd, err := os.get_working_directory(context.temp_allocator); err == nil do abs, _ = filepath.join({cwd, path}, context.temp_allocator)
	}
	abs, _ = filepath.clean(abs, context.temp_allocator)
	r := &GlobalSettings.recentProjects
	for p, i in r {
		if p == abs {
			delete(p)
			ordered_remove(r, i)
			break
		}
	}
	inject_at(r, 0, strings.clone(abs))
	for len(r) > 10 do delete(pop(r))
}

@(private = "file")
jf :: proc(obj: json.Object, k: string, d: f32) -> f32 {
	#partial switch v in obj[k] {
	case json.Float: return f32(v)
	case json.Integer: return f32(v)
	}
	return d
}

@(private = "file")
jb :: proc(obj: json.Object, k: string, d: bool) -> bool {
	if v, ok := obj[k].(json.Boolean); ok do return bool(v)
	return d
}

Editor_SaveSettings :: proc() -> bool {
	s := &GlobalSettings
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "; Rayzr editor settings (Settings in the editor writes this file)\n\n[general]\n")
	fmt.sbprintf(&sb, "ui_scale = %.2f\nautosave_minutes = %d\ngrid_size = %.0f\n", s.uiScale, s.autosaveMinutes, s.gridSize)
	fmt.sbprintf(&sb, "snap_to_grid = %t\nshow_grid = %t\nconfirm_quit = %t\nshow_welcome = %t\ncheck_updates = %t\n", s.snapToGrid, s.showGrid, s.confirmQuit, s.showWelcome, s.checkUpdates)
	fmt.sbprintf(&sb, "show_tab_bars = %t\nauto_bottom_panel = %t\n", s.showTabBars, s.autoBottomPanel)
	{
		names := make([dynamic]string, context.temp_allocator)
		for t in BottomTab do if t in s.hiddenBottomTabs do append(&names, fmt.tprint(t))
		fmt.sbprintf(&sb, "hidden_bottom_tabs = %s\n", strings.join(names[:], ",", context.temp_allocator))
		fmt.sbprintf(&sb, "preview_shape = %s\n", PREVIEW_SHAPES[clamp(s.previewShape, 0, len(PREVIEW_SHAPES) - 1)].name)
	}
	if w := s.window; w.saved {
		fmt.sbprintf(&sb, "\n[window]\nx = %d\ny = %d\nwidth = %d\nheight = %d\nmaximized = %t\nmonitor = %d\n", w.x, w.y, w.w, w.h, w.maximized, w.monitor)
	}
	strings.write_string(&sb, "\n[code]\n")
	fmt.sbprintf(&sb, "font_size = %.0f\ntab_width = %d\ninsert_spaces = %t\n", s.codeFontSize, s.tabWidth, s.insertSpaces)
	fmt.sbprintf(&sb, "auto_close_pairs = %t\nformat_on_save = %t\nlsp_enabled = %t\n", s.autoClosePairs, s.formatOnSave, s.lspEnabled)
	fmt.sbprintf(&sb, "rainbow_brackets = %t\nindent_guides = %t\nsoft_wrap = %t\n", s.rainbowBrackets, s.indentGuides, s.softWrap)
	fmt.sbprintf(&sb, "sticky_scroll = %t\nbreadcrumbs = %t\ninlay_hints = %t\ncolor_swatches = %t\n", s.stickyScroll, s.breadcrumbs, s.inlayHints, s.colorSwatches)
	wsNames := [Show_Whitespace]string{.None = "none", .Selection = "selection", .All = "all"}
	fmt.sbprintf(&sb, "show_whitespace = %s\n", wsNames[s.showWhitespace])
	fmt.sbprintf(&sb, "lua_server_path = %s\n", s.luaServerPath)
	strings.write_string(&sb, "\n[tools]\n")
	fmt.sbprintf(&sb, "aseprite_path = %s\n", s.asepritePath)
	fmt.sbprintf(&sb, "registry_url = %s\n", s.registryUrl)
	strings.write_string(&sb, "\n[theme]\n")
	fmt.sbprintf(&sb, "name = %s\n", s.theme.name)
	for k in Theme_Color do fmt.sbprintf(&sb, "%s = %s\n", THEME_COLOR_INFO[k].key, theme_color_text(s.theme.colors[k]))
	strings.write_string(&sb, "\n[paths]\n")
	fmt.sbprintf(&sb, "import = %s\nexport = %s\nprojects = %s\n", s.lastImportDir, s.lastExportDir, s.lastProjectDir)
	if len(s.ldtkTrust) > 0 {
		strings.write_string(&sb, "\n[ldtk_trust]\n")
		for k, v in s.ldtkTrust do fmt.sbprintf(&sb, "%s = %t\n", k, v)
	}
	if len(s.pluginTrust) > 0 {
		strings.write_string(&sb, "\n[plugin_trust]\n")
		for k, v in s.pluginTrust do fmt.sbprintf(&sb, "%s = %t\n", k, v)
	}
	if len(s.pluginsOff) > 0 {
		strings.write_string(&sb, "\n[plugins_off]\n")
		for k in s.pluginsOff do fmt.sbprintf(&sb, "%s = true\n", k)
	}
	strings.write_string(&sb, "\n[recent_projects]\n")
	for r, i in s.recentProjects do fmt.sbprintf(&sb, "%d = %s\n", i, r)
	fmt.sbprintf(&sb, "\n[preview]\nautoplay = %t\nloop = %t\nvolume = %.2f\n", s.previewAutoplay, s.previewLoop, s.previewVolume)
	strings.write_string(&sb, "\n[file_browser]\n")
	fmt.sbprintf(&sb, "open = %t\ndir = %s\n", s.fileBrowserOpen, s.fileBrowserDir)
	strings.write_string(&sb, "\n[file_browser_bookmarks]\n")
	for b, i in s.fileBrowserBookmarks do fmt.sbprintf(&sb, "%d = %s\n", i, b)
	strings.write_string(&sb, "\n[file_browser_recent]\n")
	for r, i in s.fileBrowserRecent do fmt.sbprintf(&sb, "%d = %s\n", i, r)
	strings.write_string(&sb, "\n[keymap]\n")
	ids := make([dynamic]string, context.temp_allocator)
	for id in s.keymap do append(&ids, id)
	slice.sort(ids[:])
	for id in ids {
		parts := make([dynamic]string, context.temp_allocator)
		for c in s.keymap[id] do if c.key != .None do append(&parts, Chord_Text(c))
		fmt.sbprintf(&sb, "%s = %s\n", id, strings.join(parts[:], ", ", context.temp_allocator))
	}
	_ = os.make_directory_all(filepath.dir(settingsPath, context.temp_allocator))
	return os.write_entire_file(settingsPath, transmute([]u8)strings.to_string(sb)) == nil
}

// Editor_ApplySettings pushes settings into the editor (font scale, grid,
// code editor, keymap).
Editor_ApplySettings :: proc(state: ^EditorState) {
	s := &GlobalSettings
	io := imgui.GetIO()
	io.FontGlobalScale = clamp(s.uiScale, 0.75, 2)
	state.gridSize = max(s.gridSize, 1)
	state.snapGrid = s.snapToGrid
	state.showGrid = s.showGrid
	GlobalCode.fontSize = s.codeFontSize if s.codeFontSize != CODE_FONT_SIZE else 0
	Actions_ApplyKeymap(s.keymap)
	Theme_Apply(s.theme)
}

Remembered_Dir :: enum {
	Import,
	Export,
	Projects,
}

// Editor_RememberDir keeps the folder a file was picked in (a folder is
// kept as is) for the next dialog of that kind, in settings.ini.
Editor_RememberDir :: proc(kind: Remembered_Dir, path: string, isFolder := false) {
	if path == "" do return
	dir := path if isFolder || os.is_dir(path) else filepath.dir(path, context.temp_allocator)
	if abs, err := filepath.abs(dir, context.temp_allocator); err == nil do dir = abs
	field: ^string
	switch kind {
	case .Import: field = &GlobalSettings.lastImportDir
	case .Export: field = &GlobalSettings.lastExportDir
	case .Projects: field = &GlobalSettings.lastProjectDir
	}
	if field^ == dir do return
	delete(field^)
	field^ = strings.clone(dir)
	_ = Editor_SaveSettings()
}

// Editor_StartDir: where a dialog of that kind opens - the folder used last,
// else `fallback`.
Editor_StartDir :: proc(kind: Remembered_Dir, fallback := "") -> string {
	d: string
	switch kind {
	case .Import: d = GlobalSettings.lastImportDir
	case .Export: d = GlobalSettings.lastExportDir
	case .Projects: d = GlobalSettings.lastProjectDir
	}
	if d != "" && os.is_dir(d) do return d
	return fallback
}
