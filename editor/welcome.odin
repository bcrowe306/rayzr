package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import imgui "lib/imgui"
import rl "vendor:raylib"

// ============================================================================
// Welcome window (at startup unless turned off; Help > Welcome): recent
// projects, a new project from a template (project_templates.odin), Open
// Project, and a few pointers for a first session.
// ============================================================================

// The logo at the top (editor/assets/icon.png).
@(private = "file")
WELCOME_LOGO :: #load("assets/icon.png")

@(private = "file")
welcome: struct {
	logo:      rl.Texture2D,
	open:      bool,
	shown:     bool, // opened at startup already
	template:  string,                      // the chosen entry's name ("" = the first)
	previews:  map[string]^rl.Texture2D,    // preview.png per template folder (heap: the draw list keeps the address)
	nameBuf:   [128]u8,
	whereBuf:  [512]u8,
}

Welcome_Open :: proc(state: ^EditorState) {
	welcome.open = true
	if welcome.nameBuf[0] == 0 do copy(welcome.nameBuf[:len(welcome.nameBuf) - 1], "My Game")
	if welcome.whereBuf[0] == 0 {
		parent := filepath.dir(strings.trim_suffix(state.projectPath, "/"), context.temp_allocator)
		if abs, err := filepath.abs(parent, context.temp_allocator); err == nil do parent = abs
		parent = Editor_StartDir(.Projects, parent) // where the last project was made / opened
		copy(welcome.whereBuf[:len(welcome.whereBuf) - 1], parent)
	}
}

Welcome_IsOpen :: proc() -> bool {return welcome.open}

// Welcome_Render: call every frame (opens itself once at startup).
Welcome_Render :: proc(state: ^EditorState) {
	if !welcome.shown {
		welcome.shown = true
		// (Not when launched on a project: New / Open / a recent project
		// relaunch the editor with --project, and go straight to it - #265.)
		if GlobalSettings.showWelcome && !GlobalDrive.enabled && !slice.contains(os.args, "--project") do Welcome_Open(state)
	}
	if !welcome.open do return
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	imgui.SetNextWindowSize({860, 620}, .Appearing)
	// Its own surface (lighter than the panels: two steps on dark themes)
	// and an accent edge, so it
	// stands out above the editor.
	surface := UI_BG_RAISED if UI_THEME_LIGHT else UI_BG_HOVER
	imgui.PushStyleColorImVec4(.WindowBg, surface)
	imgui.PushStyleColorImVec4(.TitleBg, surface)
	imgui.PushStyleColorImVec4(.TitleBgActive, surface)
	imgui.PushStyleColorImVec4(.Border, ui_accent(0.45))
	imgui.PushStyleVar(.WindowBorderSize, 1)
	imgui.PushStyleVar(.WindowRounding, 10)
	defer imgui.End()
	visible := imgui.Begin("Welcome###WelcomeWindow", &welcome.open, {.NoCollapse, .NoDocking})
	imgui.PopStyleVar(2)
	imgui.PopStyleColor(4)
	if !visible do return
	Drive_Window("welcome") // (annotated docs screenshots)
	PanelHelp_Mark("welcome")
	// Cards and inputs one step brighter than the window.
	imgui.PushStyleColorImVec4(.FrameBg, UI_BG_PANEL if UI_THEME_LIGHT else UI_BG_ACTIVE)
	imgui.PushStyleColorImVec4(.Button, UI_BG_PANEL if UI_THEME_LIGHT else UI_BG_ACTIVE)
	defer imgui.PopStyleColor(2)

	// The logo, then the title and the project.
	if welcome.logo.id == 0 {
		img := rl.LoadImageFromMemory(".png", raw_data(WELCOME_LOGO), i32(len(WELCOME_LOGO)))
		if img.data != nil {
			rl.ImageResize(&img, 128, 128) // (shown at 48: mipless, so shrink once)
			welcome.logo = rl.LoadTextureFromImage(img)
			rl.SetTextureFilter(welcome.logo, .BILINEAR)
			rl.UnloadImage(img)
		}
	}
	if welcome.logo.id != 0 {
		imgui.Image(transmute(imgui.TextureID)&welcome.logo, {48, 48})
		Drive_Item("welcome.logo")
		imgui.SameLine(0, 12)
	}
	imgui.BeginGroup()
	imgui.Dummy({0, 2})
	imgui.PushFont(GlobalFonts.semibold)
	imgui.TextUnformatted("Welcome to the Rayzr editor")
	imgui.PopFont()
	UI_DimText(fmt.tprintf("Editing %s", state.projectConfig.name if state.projectConfig.name != "" else state.projectPath))
	imgui.EndGroup()
	imgui.Dummy({0, 6})

	// --- left: recent projects and pointers ---
	if imgui.BeginChild("##welcome_left", {300, -40}, {}, {}) {
		UI_SectionHeader("Recent Projects")
		if len(GlobalSettings.recentProjects) == 0 do UI_DimText("None yet.")
		for r in GlobalSettings.recentProjects {
			if imgui.Selectable(fmt.ctprintf("%s  %s##wr_%s", ICON_FA_FOLDER, filepath.base(r), r), false, {}, {0, 24}) {
				Editor_SwitchProject(state, r)
			}
			Drive_Item(fmt.tprintf("welcome.recent:%s", filepath.base(r)))
			UI_Tooltip(r)
		}
		imgui.Dummy({0, 4})
		if UI_Button(fmt.tprintf("%s  Open Project...", ICON_FA_FOLDER_OPEN), "welcome.open", {-1, 0}) {
			welcome.open = false
			Editor_OpenProjectDialog(state)
		}
		imgui.Dummy({0, 8})
		UI_SectionHeader("First Steps")
		imgui.PushTextWrapPos(0)
		tip :: proc(icon, text: string) {
			imgui.PushStyleColorImVec4(.Text, UI_ACCENT)
			imgui.TextUnformatted(strings.clone_to_cstring(icon, context.temp_allocator))
			imgui.PopStyleColor()
			imgui.SameLine(26)
			imgui.TextWrapped("%s", strings.clone_to_cstring(text, context.temp_allocator))
		}
		tip(ICON_FA_PLUS, CMD + "+A adds a node; drag images from Assets into the viewport for sprites.")
		tip(ICON_FA_CODE, "Attach a Lua script in the Inspector; saving reloads it, even while playing.")
		tip(ICON_FA_PLAY, "F5 plays the game; the Game tab shows its live scene tree.")
		tip(ICON_FA_MAGNIFYING_GLASS, CMD + "+P finds files and commands; hover a property for help.")
		imgui.PopTextWrapPos()
	}
	imgui.EndChild()
	imgui.SameLine()

	// --- right: new project ---
	if imgui.BeginChild("##welcome_new", {0, -40}, {.Borders}, {}) {
		UI_SectionHeader("New Project")
		entries := Templates_List()
		chosen := entries[0]
		for e in entries do if e.name == welcome.template do chosen = e
		// (Templates scroll; the form below stays.)
		if imgui.BeginChild("##welcome_templates", {0, -150 - imgui.GetFrameHeightWithSpacing()}, {}, {}) {
			lastSample := false
			for e in entries {
				if e.sample && !lastSample {
					imgui.Dummy({0, 4})
					UI_DimText("Samples - complete projects to explore")
				}
				lastSample = e.sample
				welcome_card(e, e.name == chosen.name)
			}
		}
		imgui.EndChild()
		if UI_Button(fmt.tprintf("%s  Browse More Templates...", ICON_FA_PUZZLE_PIECE), "welcome.registry", {-1, 0}) do Registry_Open(state, 2)
		UI_Tooltip("Community templates from the registry (Tools > Registry): installed ones show up here")
		imgui.Dummy({0, 6})
		if UI_BeginProps("##newproj") {
			UI_PropLabel("Name")
			imgui.InputText("##wname", cstring(raw_data(welcome.nameBuf[:])), len(welcome.nameBuf))
			Drive_Item("welcome.name")
			UI_PropLabel("Location")
			imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x - 90)
			imgui.InputText("##wwhere", cstring(raw_data(welcome.whereBuf[:])), len(welcome.whereBuf))
			Drive_Item("welcome.where")
			imgui.SameLine(0, 4)
			if UI_Button("Browse...", "welcome.where.browse", {86, 0}) {
				start := strings.clone(string(cstring(raw_data(welcome.whereBuf[:]))), context.temp_allocator)
				NativeDialog_Open(state, {title = "New Project Location", folders = true, start = start}, proc(state: ^EditorState, paths: []string) {
					welcome.whereBuf = {}
					copy(welcome.whereBuf[:len(welcome.whereBuf) - 1], paths[0])
				})
			}
			UI_EndProps()
		}
		name := strings.trim_space(string(cstring(raw_data(welcome.nameBuf[:]))))
		location := strings.trim_space(string(cstring(raw_data(welcome.whereBuf[:]))))
		folder, _ := strings.replace_all(name, " ", "_", context.temp_allocator)
		dir, _ := filepath.join({location, folder}, context.temp_allocator)
		UI_DimText(dir)
		if UI_PrimaryButton(fmt.tprintf("%s  Create Project", ICON_FA_PLUS), "welcome.create", {-1, 0}) && name != "" {
			if Project_CreateFromEntry(dir, name, chosen) {
				Editor_Log(state, .Info, "Created %s project %s", chosen.name, dir)
				welcome.open = false
				Editor_SwitchProject(state, strings.clone(dir, context.temp_allocator))
			} else {
				Editor_Log(state, .Error, "Could not create a project in %s (is there one already?)", dir)
			}
		}
	}
	imgui.EndChild()

	if imgui.Checkbox("Show at startup", &GlobalSettings.showWelcome) do _ = Editor_SaveSettings()
	imgui.SameLine(imgui.GetWindowWidth() - 120)
	if UI_Button("Close", "welcome.close", {100, 0}) do welcome.open = false
}

// welcome_card: one template / sample (icon, name, description, preview).
@(private = "file")
welcome_card :: proc(e: Template_Entry, selected: bool) {
	H :: 58
	if imgui.Selectable(fmt.ctprintf("##tmpl_%s", e.name), selected, {}, {0, H}) {
		delete(welcome.template)
		welcome.template = strings.clone(e.name)
	}
	Drive_Item(fmt.tprintf("welcome.template:%s", e.name))
	UI_Tooltip(e.description)
	mn := imgui.GetItemRectMin()
	w := imgui.GetItemRectSize().x
	dl := imgui.GetWindowDrawList()
	textRight := mn.x + w - 4
	if e.preview != "" {
		tex, ok := welcome.previews[e.preview]
		if !ok {
			tex = new(rl.Texture2D)
			tex^ = rl.LoadTexture(strings.clone_to_cstring(e.preview, context.temp_allocator))
			if tex.id != 0 do rl.SetTextureFilter(tex^, .BILINEAR)
			welcome.previews[strings.clone(e.preview)] = tex
		}
		if tex.id != 0 {
			pw: f32 = 89 // 16:9 in the card's height
			ph: f32 = H - 8
			at := imgui.Vec2{mn.x + w - pw - 4, mn.y + 4}
			imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)tex, at, at + {pw, ph})
			textRight = at.x - 6
		}
	}
	imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.regular, 22, {mn.x + 8, mn.y + 16}, col_u32(UI_ACCENT if selected else UI_TEXT_DIM), strings.clone_to_cstring(e.icon, context.temp_allocator))
	imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.semibold, 15, {mn.x + 44, mn.y + 4}, col_u32(UI_TEXT), strings.clone_to_cstring(e.name, context.temp_allocator))
	clip := imgui.Vec4{mn.x, mn.y, textRight, mn.y + H}
	imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, 12.5, {mn.x + 44, mn.y + 24}, col_u32(UI_TEXT_DIM), strings.clone_to_cstring(e.description, context.temp_allocator), nil, textRight - mn.x - 44, &clip)
}

// Welcome_Shutdown frees the preview textures.
Welcome_Shutdown :: proc() {
	for k, tex in welcome.previews {
		if tex.id != 0 do rl.UnloadTexture(tex^)
		free(tex)
		delete(k)
	}
	delete(welcome.previews)
	delete(welcome.template)
}
