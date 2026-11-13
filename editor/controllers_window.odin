package editor

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"
import rl "vendor:raylib"

// ============================================================================
// Tools > Controllers (gamepad_mappings.odin, gamepad_setup.odin): the
// controllers connected to this computer - their name, GUID and where their
// mapping comes from (the database, the project, a guess) - their raw
// buttons, axes and hats live, what the game sees through the mapping, and
// Controller Setup ("press A", "press B", ...) to map one. A mapping made
// here is saved in the project's gamecontrollerdb.txt (next to
// project.json), which exported games ship with.
// ============================================================================

@(private = "file")
controllers: struct {
	open:     bool,
	focus:    bool,
	selected: i32, // joystick id (0-based; -1 none)
	status:   string, // (static or temp-cloned into statusBuf)
	statusOk: bool,
}

Controllers_Open :: proc(state: ^EditorState) {
	controllers.open = true
	controllers.focus = true
	controllers.selected = -1
}

// Controllers_ProjectFile: the project's gamecontrollerdb.txt.
Controllers_ProjectFile :: proc(state: ^EditorState) -> string {
	p, _ := filepath.join({state.projectPath, e.GAMEPAD_DB_FILE}, context.temp_allocator)
	return p
}

@(private = "file")
controllers_status :: proc(ok: bool, text: string) {
	controllers.status = text
	controllers.statusOk = ok
}

Controllers_Render :: proc(state: ^EditorState) {
	e.Gamepad_MappingsFrame() // (the editor's mappings, and fallbacks for new controllers)
	if !controllers.open {
		if e.padSetup.active do e.Pad_SetupCancel()
		return
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	imgui.SetNextWindowSize({820, 560}, .Appearing)
	if controllers.focus {
		imgui.SetNextWindowFocus()
		controllers.focus = false
	}
	defer imgui.End()
	if !imgui.Begin(fmt.ctprintf("%s  Controllers###ControllersWindow", ICON_FA_GAMEPAD), &controllers.open, {.NoCollapse, .NoDocking}) do return
	Drive_Window("controllers")
	PanelHelp_Mark("controllers")

	// The list.
	ids := make([dynamic]i32, context.temp_allocator)
	for jid in 0 ..< i32(e.JOY_MAX) do if e.joy_present(jid) do append(&ids, jid)
	if controllers.selected >= 0 && !e.joy_present(controllers.selected) do controllers.selected = -1
	if controllers.selected < 0 && len(ids) > 0 do controllers.selected = ids[0]

	h := imgui.GetContentRegionAvail().y
	if imgui.BeginChild("##ctl-list", {240, h}, {.Borders}, {}) {
		if len(ids) == 0 {
			imgui.TextWrapped("%s", "No controllers connected. Plug one in or pair it over Bluetooth; it shows up here.")
		}
		for jid in ids {
			src := e.Gamepad_SourceOf(jid)
			label := fmt.ctprintf("%s##ctl%d", e.joy_name(jid), jid)
			if imgui.Selectable(label, controllers.selected == jid) {
				if e.padSetup.active && e.padSetup.jid != jid do e.Pad_SetupCancel()
				controllers.selected = jid
				controllers.status = ""
			}
			Drive_Item(fmt.tprintf("controllers.pad:%d", jid + 1))
			imgui.SameLine()
			imgui.TextColored(source_color(src), "%s", strings.clone_to_cstring(source_label(src), context.temp_allocator))
		}
	}
	imgui.EndChild()
	imgui.SameLine()
	if imgui.BeginChild("##ctl-detail", {0, h}, {}, {}) {
		if controllers.selected >= 0 do controllers_detail(state, controllers.selected)
	}
	imgui.EndChild()
}

// wrap_line: a mapping line that wraps (a space after each comma; shown only - Copy Mapping copies the real one).
@(private = "file")
wrap_line :: proc(line: string) -> string {
	s, _ := strings.replace_all(line, ",", ", ", context.temp_allocator)
	return s
}

@(private = "file")
source_label :: proc(src: e.Pad_MapSource) -> string {
	switch src {
	case .None:           return "not mapped"
	case .Builtin:        return "built in"
	case .Bundled:        return "database"
	case .Project:        return "project"
	case .Player:         return "player"
	case .Environment:    return "environment"
	case .Other_Platform: return "other platform"
	case .Generic:        return "guessed"
	case .Setup, .Script: return "this session"
	}
	return ""
}

@(private = "file")
source_color :: proc(src: e.Pad_MapSource) -> imgui.Vec4 {
	#partial switch src {
	case .None:                      return {0.95, 0.45, 0.45, 1}
	case .Generic, .Other_Platform:  return UI_WARNING
	case .Project, .Player, .Setup:  return UI_SUCCESS
	}
	return UI_TEXT_DIM
}

@(private = "file")
source_help :: proc(src: e.Pad_MapSource) -> string {
	switch src {
	case .None:           return "No mapping: the game sees no buttons. Set it up below."
	case .Builtin:        return "Known to GLFW (raylib's input library)."
	case .Bundled:        return "Found in the controller database Rayzr ships (SDL_GameControllerDB)."
	case .Project:        return "From this project's gamecontrollerdb.txt (exported with the game)."
	case .Player:         return "From the player's own gamecontrollerdb.txt."
	case .Environment:    return "From SDL_GAMECONTROLLERCONFIG."
	case .Other_Platform: return "The database only knows it on another platform: that layout is used here. Check the buttons, and set it up if any are wrong."
	case .Generic:        return "Unknown controller: a standard layout was guessed. Check the buttons, and set it up if any are wrong."
	case .Setup, .Script: return "Set up in this session, not saved."
	}
	return ""
}

@(private = "file")
controllers_detail :: proc(state: ^EditorState, jid: i32) {
	name := e.joy_name(jid)
	guid := strings.to_lower(e.joy_guid(jid), context.temp_allocator)
	src := e.Gamepad_SourceOf(jid)
	imgui.TextUnformatted(strings.clone_to_cstring(name, context.temp_allocator))
	UI_DimText(fmt.tprintf("Joystick %d   GUID %s", jid + 1, guid))
	imgui.PushStyleColorImVec4(.Text, source_color(src))
	imgui.TextWrapped("%s", strings.clone_to_cstring(source_help(src), context.temp_allocator))
	imgui.PopStyleColor()

	if e.padSetup.active && e.padSetup.jid == jid {
		controllers_setup(state)
		return
	}

	imgui.Dummy({0, 4})
	if UI_Button(fmt.tprintf("%s  Set Up...", ICON_FA_GAMEPAD), "controllers.setup") {
		controllers.status = ""
		e.Pad_SetupBegin(jid)
	}
	UI_Tooltip("Press each button the window asks for. The mapping is saved in this project's gamecontrollerdb.txt and ships with the game")
	path := Controllers_ProjectFile(state)
	m, has := e.Gamepad_MappingOf(guid)
	inProject := e.Gamepad_FileHasMapping(path, guid)
	if has && m.line != "" && !inProject {
		imgui.SameLine()
		if UI_Button("Save to Project", "controllers.save") {
			ok := e.Gamepad_SaveMappingFile(path, m.line)
			if ok do e.Gamepad_ApplyMapping(m.line, .Project)
			controllers_status(ok, "Saved in gamecontrollerdb.txt." if ok else "Couldn't write gamecontrollerdb.txt.")
		}
		UI_Tooltip("Keep this mapping in the project's gamecontrollerdb.txt, so the game uses it on every computer")
	}
	if inProject {
		imgui.SameLine()
		if UI_Button("Remove from Project", "controllers.remove") {
			ok := e.Gamepad_RemoveMappingFile(path, guid)
			controllers_status(ok, "Removed from gamecontrollerdb.txt (used until the editor restarts)." if ok else "Couldn't write gamecontrollerdb.txt.")
		}
		UI_Tooltip("Take this controller's line out of the project's gamecontrollerdb.txt")
	}
	if has && m.line != "" {
		imgui.SameLine()
		if UI_Button(fmt.tprintf("%s  Copy Mapping", ICON_FA_LINK), "controllers.copy") {
			imgui.SetClipboardText(strings.clone_to_cstring(m.line, context.temp_allocator))
			controllers_status(true, "Mapping line copied.")
		}
		UI_Tooltip("The SDL mapping line - share it, or add it to SDL_GameControllerDB for everyone")
	}
	if controllers.status != "" do imgui.TextColored(UI_SUCCESS if controllers.statusOk else UI_WARNING, "%s", strings.clone_to_cstring(controllers.status, context.temp_allocator))

	imgui.SeparatorText("Raw inputs")
	controllers_raw(jid)
	if src != .None && jid < 4 {
		imgui.SeparatorText("What the game sees")
		controllers_mapped(jid)
	}
	if has && m.line != "" {
		imgui.SeparatorText("Mapping")
		imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
		imgui.TextWrapped("%s", strings.clone_to_cstring(wrap_line(m.line), context.temp_allocator))
		imgui.PopStyleColor()
	}
}

@(private = "file")
controllers_raw :: proc(jid: i32) {
	buttons := e.joy_buttons(jid)
	axes := e.joy_axes(jid)
	hats := e.joy_hats(jid)
	dl := imgui.GetWindowDrawList()
	// Buttons: a row of numbered boxes, lit while down.
	S :: f32(22)
	p := imgui.GetCursorScreenPos()
	perRow := max(1, int((imgui.GetContentRegionAvail().x + 4) / (S + 4)))
	for b, i in buttons {
		x := p.x + f32(i % perRow) * (S + 4)
		y := p.y + f32(i / perRow) * (S + 4)
		col := UI_ACCENT if b != 0 else ui_line(0.08)
		imgui.DrawList_AddRectFilled(dl, {x, y}, {x + S, y + S}, col_u32(col), 3)
		imgui.DrawList_AddText(dl, {x + 4, y + 4}, col_u32({1, 1, 1, 0.9 if b != 0 else 0.5}), fmt.ctprintf("%d", i))
	}
	rows := (len(buttons) + perRow - 1) / perRow
	imgui.Dummy({0, f32(rows) * (S + 4)})
	for a, i in axes {
		imgui.ProgressBar((a + 1) * 0.5, {220, 14}, fmt.ctprintf("axis %d  %+.2f", i, a))
	}
	for h, i in hats {
		dirs := make([dynamic]string, context.temp_allocator)
		if h & 1 != 0 do append(&dirs, "up")
		if h & 2 != 0 do append(&dirs, "right")
		if h & 4 != 0 do append(&dirs, "down")
		if h & 8 != 0 do append(&dirs, "left")
		UI_DimText(fmt.tprintf("hat %d: %s", i, strings.join(dirs[:], " + ", context.temp_allocator) if len(dirs) > 0 else "centred"))
	}
	if len(buttons) == 0 && len(axes) == 0 && len(hats) == 0 do UI_DimText("No inputs reported.")
}

@(private = "file")
controllers_mapped :: proc(jid: i32) {
	NAMES :: [?]struct {b: rl.GamepadButton, n: string} {
		{.RIGHT_FACE_DOWN, "A"}, {.RIGHT_FACE_RIGHT, "B"}, {.RIGHT_FACE_LEFT, "X"}, {.RIGHT_FACE_UP, "Y"},
		{.LEFT_FACE_UP, "Up"}, {.LEFT_FACE_DOWN, "Down"}, {.LEFT_FACE_LEFT, "Left"}, {.LEFT_FACE_RIGHT, "Right"},
		{.LEFT_TRIGGER_1, "LB"}, {.RIGHT_TRIGGER_1, "RB"}, {.LEFT_TRIGGER_2, "LT"}, {.RIGHT_TRIGGER_2, "RT"},
		{.MIDDLE_LEFT, "Back"}, {.MIDDLE_RIGHT, "Start"}, {.MIDDLE, "Home"}, {.LEFT_THUMB, "L3"}, {.RIGHT_THUMB, "R3"},
	}
	names := NAMES
	for it, i in names {
		if i > 0 && i % 9 != 0 do imgui.SameLine()
		down := rl.IsGamepadButtonDown(jid, it.b)
		imgui.PushStyleColorImVec4(.Button, UI_ACCENT if down else ui_line(0.06))
		imgui.Button(fmt.ctprintf("%s##m%d", it.n, i), {44, 0})
		imgui.PopStyleColor()
	}
	sticks := [6]cstring{"left x", "left y", "right x", "right y", "left trigger", "right trigger"}
	for n, i in sticks {
		v := rl.GetGamepadAxisMovement(jid, rl.GamepadAxis(i))
		imgui.ProgressBar((v + 1) * 0.5, {220, 14}, fmt.ctprintf("%s  %+.2f", n, v))
	}
}

@(private = "file")
controllers_setup :: proc(state: ^EditorState) {
	if !e.Pad_SetupFrame() {
		controllers_status(false, "The controller disconnected.")
		return
	}
	s := &e.padSetup
	n := len(e.PAD_SETUP_STEPS)
	imgui.Dummy({0, 6})
	if s.done {
		imgui.TextColored(UI_SUCCESS, "All steps done.")
	} else {
		UI_DimText(fmt.tprintf("Step %d of %d", s.step + 1, n))
		imgui.SetWindowFontScale(1.4)
		imgui.TextUnformatted(strings.clone_to_cstring(e.PAD_SETUP_STEPS[s.step].label, context.temp_allocator))
		imgui.SetWindowFontScale(1)
		imgui.ProgressBar(f32(s.step) / f32(n), {-1, 6}, "")
		if s.message != "" {
			imgui.TextColored(UI_WARNING, "Already used for: %s", strings.clone_to_cstring(s.message, context.temp_allocator))
		} else if s.waitRelease && s.step > 0 {
			UI_DimText("Let go...")
		} else {
			UI_DimText("Waiting for the controller...")
		}
	}
	imgui.Dummy({0, 6})
	imgui.BeginDisabled(s.done)
	if UI_Button("Skip", "controllers.skip") do e.Pad_SetupSkip()
	imgui.EndDisabled()
	UI_Tooltip("This controller has no such button")
	imgui.SameLine()
	imgui.BeginDisabled(s.step == 0 && !s.done)
	if UI_Button("Back", "controllers.back") do e.Pad_SetupBack()
	imgui.EndDisabled()
	imgui.SameLine()
	if UI_Button("Cancel", "controllers.cancel") {
		e.Pad_SetupCancel()
		return
	}
	imgui.SameLine()
	if UI_Button(fmt.tprintf("%s  Save to Project", ICON_FA_CHECK), "controllers.finish") {
		_, saved := e.Pad_SetupFinish(Controllers_ProjectFile(state), .Project)
		controllers_status(saved, "Saved in gamecontrollerdb.txt: the game uses it from now on." if saved else "Nothing was set, so nothing was saved.")
		if saved do Editor_Log(state, .Info, "Controllers: saved a mapping in %s", e.GAMEPAD_DB_FILE)
		return
	}
	UI_Tooltip("Use the mapping now and keep it in the project's gamecontrollerdb.txt (steps not answered yet are left out)")
	imgui.SeparatorText("So far")
	imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
	imgui.TextWrapped("%s", strings.clone_to_cstring(wrap_line(e.Pad_SetupMapping()), context.temp_allocator))
	imgui.PopStyleColor()
}

// Controllers_DriveQuery (test drives): controllers.open / count / setup /
// selected (1-based; 0 none) / source (the selected one's).
Controllers_DriveQuery :: proc(state: ^EditorState, q: string) -> (string, bool) {
	switch q[len("controllers."):] {
	case "open":     return "true" if controllers.open else "false", true
	case "setup":    return "true" if e.padSetup.active else "false", true
	case "selected": return fmt.tprint(controllers.selected + 1), true
	case "source":   return source_label(e.Gamepad_SourceOf(controllers.selected)) if controllers.selected >= 0 else "", true
	case "count":
		n := 0
		for jid in 0 ..< i32(e.JOY_MAX) do if e.joy_present(jid) do n += 1
		return fmt.tprint(n), true
	}
	return "", false
}

// Controllers_Shutdown: a setup left running.
Controllers_Shutdown :: proc() {
	if e.padSetup.active do e.Pad_SetupCancel()
}
