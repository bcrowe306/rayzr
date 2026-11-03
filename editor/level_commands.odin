package editor

import "core:fmt"
import "core:os"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Level editor: LDtk's custom commands (CommandRunner) - the project's
// commands run in the project's folder after loading, before / after saving,
// or by hand (Cmd+R). The first time, the editor asks whether to trust the
// project's commands (remembered per project in the editor settings).
// Output streams into the Command window; a failing command keeps it open.
// ============================================================================

LDTK_COMMAND_WHEN := [?]string{"Manual", "AfterLoad", "BeforeSave", "AfterSave"}
LDTK_COMMAND_WHEN_LABELS := [?]string{"Run manually (" + CMD + "+R)", "Run after loading", "Run before saving", "Run after saving"}

Level_Command_Then :: enum u8 {
	None,
	Save, // the save waiting for its BeforeSave commands
}

@(private = "file")
lc: struct {
	queue:     [dynamic]string,
	then:      Level_Command_Then,
	process:   os.Process,
	running:   bool,
	out:       ^os.File,
	lineBuf:   [dynamic]u8,
	output:    [dynamic]string,
	open:      bool,
	keepOpen:  bool, // a command failed / was killed
	trustReq:  bool,
	pendWhen:  string,
	pendThen:  Level_Command_Then,
}

LevelCommands_Shutdown :: proc() {
	if lc.running do _ = os.process_kill(lc.process)
	if lc.out != nil do os.close(lc.out)
	for q in lc.queue do delete(q)
	delete(lc.queue)
	delete(lc.lineBuf)
	for o in lc.output do delete(o)
	delete(lc.output)
	delete(lc.pendWhen)
	lc = {}
	// (the editor settings outlive everything else; their trust map is freed here)
	for k in GlobalSettings.ldtkTrust do delete(k)
	delete(GlobalSettings.ldtkTrust)
	GlobalSettings.ldtkTrust = nil
}

LevelCommands_Busy :: proc() -> bool {return lc.running || len(lc.queue) > 0}

// LevelCommands_Run queues the project's commands of a trigger ("Manual",
// "AfterLoad", "BeforeSave", "AfterSave"); `then` runs after them (or right
// away when there are none / the project isn't trusted).
LevelCommands_Run :: proc(state: ^EditorState, when_: string, then: Level_Command_Then = .None) {
	doc := GlobalLevel.doc
	if doc == nil do return
	cmds := make([dynamic]string, context.temp_allocator)
	for c in e.LdtkJson_Arr(doc.root, "customCommands") {
		if e.LdtkJson_Str(c, "when", "Manual") == when_ && strings.trim_space(e.LdtkJson_Str(c, "command")) != "" do append(&cmds, e.LdtkJson_Str(c, "command"))
	}
	if len(cmds) == 0 {
		if when_ == "Manual" do Editor_Log(state, .Info, "This project has no manual command (Project tab > Custom commands)")
		command_then(state, then)
		return
	}
	iid := e.LdtkJson_Str(doc.root, "iid")
	trusted, known := GlobalSettings.ldtkTrust[iid]
	if !known {
		delete(lc.pendWhen)
		lc.pendWhen = strings.clone(when_)
		lc.pendThen = then
		lc.trustReq = true
		return
	}
	if !trusted {
		command_then(state, then)
		return
	}
	for c in cmds do append(&lc.queue, strings.clone(c))
	lc.then = then
	lc.open = true
	lc.keepOpen = false
}

@(private = "file")
command_then :: proc(state: ^EditorState, then: Level_Command_Then) {
	switch then {
	case .None:
	case .Save: LevelEditor_SaveNow(state)
	}
}

// LevelCommands_ParseArgs: CommandRunner.parseCommandToArray (spaces split,
// "quotes" group, \" inside quotes).
LevelCommands_ParseArgs :: proc(s: string, allocator := context.temp_allocator) -> []string {
	args := make([dynamic]string, allocator)
	b := strings.builder_make(context.temp_allocator)
	inQuotes, escaped, lastSpace := false, false, true
	for c in s {
		if c == ' ' && !inQuotes {
			if !lastSpace {
				append(&args, strings.clone(strings.to_string(b), allocator))
				strings.builder_reset(&b)
			}
			lastSpace = true
			continue
		}
		lastSpace = false
		if c == '"' {
			if !escaped do inQuotes = !inQuotes
			else {
				strings.write_rune(&b, c)
				escaped = false
			}
			continue
		}
		if c == '\\' && inQuotes && !escaped {
			escaped = true
			continue
		}
		if escaped {
			strings.write_byte(&b, '\\')
			escaped = false
		}
		strings.write_rune(&b, c)
	}
	if !lastSpace do append(&args, strings.clone(strings.trim_space(strings.to_string(b)), allocator))
	return args[:]
}

@(private = "file")
print_line :: proc(line: string) {
	append(&lc.output, strings.clone(line))
	for len(lc.output) > 500 {
		delete(lc.output[0])
		ordered_remove(&lc.output, 0)
	}
}

// LevelCommands_Update starts queued commands and streams their output
// (once per frame).
LevelCommands_Update :: proc(state: ^EditorState) {
	doc := GlobalLevel.doc
	if lc.running {
		// output
		if lc.out != nil {
			for {
				has, err := os.pipe_has_data(lc.out)
				if err != nil || !has do break
				chunk: [4096]u8
				n, rerr := os.read(lc.out, chunk[:])
				if n <= 0 || rerr != nil {
					os.close(lc.out)
					lc.out = nil
					break
				}
				append(&lc.lineBuf, ..chunk[:n])
			}
			for {
				idx := -1
				for c, i in lc.lineBuf do if c == '\n' {
					idx = i
					break
				}
				if idx < 0 do break
				print_line(strings.trim_right_space(string(lc.lineBuf[:idx])))
				remove_range(&lc.lineBuf, 0, idx + 1)
			}
		}
		st, err := os.process_wait(lc.process, 0)
		if err == nil && st.exited {
			if len(lc.lineBuf) > 0 {
				print_line(string(lc.lineBuf[:]))
				clear(&lc.lineBuf)
			}
			if lc.out != nil {
				os.close(lc.out)
				lc.out = nil
			}
			lc.running = false
			print_line(fmt.tprintf("-- exit code %d", st.exit_code))
			if st.exit_code != 0 {
				lc.keepOpen = true
				Editor_Log(state, .Warn, "A custom command failed (exit code %d)", st.exit_code)
			}
		}
		return
	}
	if len(lc.queue) > 0 && doc != nil {
		cmd := pop_front(&lc.queue)
		defer delete(cmd)
		args := LevelCommands_ParseArgs(cmd)
		print_line(fmt.tprintf("$ %s", cmd))
		if len(args) == 0 do return
		r, w, perr := os.pipe()
		desc := os.Process_Desc{command = args, working_dir = doc.dir}
		if perr == nil {
			desc.stdout = w
			desc.stderr = w
		}
		p, err := os.process_start(desc)
		if perr == nil do os.close(w)
		if err != nil {
			if perr == nil do os.close(r)
			print_line(fmt.tprintf("-- could not start: %v", err))
			lc.keepOpen = true
			return
		}
		lc.process = p
		lc.running = true
		lc.out = perr == nil ? r : nil
		return
	}
	// all done: what waited for them
	if lc.then != .None {
		then := lc.then
		lc.then = .None
		command_then(state, then)
	}
	if lc.open && !lc.keepOpen do lc.open = false
}

LevelCommands_Window :: proc(state: ^EditorState) {
	doc := GlobalLevel.doc
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	if lc.trustReq {
		lc.trustReq = false
		imgui.OpenPopup("Custom Commands###LevelTrust")
	}
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if imgui.BeginPopupModal("Custom Commands###LevelTrust", nil, {.AlwaysAutoResize}) {
		UI_DimText("This project runs commands on your computer:")
		for c in e.LdtkJson_Arr(doc.root, "customCommands") {
			imgui.BulletText("%s", fmt.ctprintf("%s  (%s)", e.LdtkJson_Str(c, "command"), e.LdtkJson_Str(c, "when", "Manual")))
		}
		UI_DimText("Only allow them if you trust where the project comes from.")
		UI_DimText("(Your choice is remembered; the Project tab can reset it.)")
		iid := strings.clone(e.LdtkJson_Str(doc.root, "iid"))
		allow := UI_PrimaryButton("Allow", "trust.allow")
		level_tip("Run this project's commands (now and later)", "project.commands")
		imgui.SameLine()
		block := UI_Button("Block", "trust.block")
		level_tip("Never run this project's commands", "project.commands")
		imgui.SameLine()
		cancel := UI_Button("Cancel", "trust.cancel")
		level_tip("Not now (asks again next time)", "project.commands")
		if allow {
			GlobalSettings.ldtkTrust[iid] = true
			Editor_SaveSettings()
			imgui.CloseCurrentPopup()
			LevelCommands_Run(state, lc.pendWhen, lc.pendThen)
		} else if block {
			GlobalSettings.ldtkTrust[iid] = false
			Editor_SaveSettings()
			imgui.CloseCurrentPopup()
			command_then(state, lc.pendThen)
		} else {
			if cancel || imgui.IsKeyPressed(.Escape) {
				delete(iid)
				imgui.CloseCurrentPopup()
				command_then(state, lc.pendThen)
			} else do delete(iid)
		}
		imgui.EndPopup()
	}
	if !lc.open do return
	imgui.SetNextWindowSize({560, 300}, .FirstUseEver)
	imgui.SetNextWindowPos(center, .FirstUseEver, {0.5, 0.5})
	defer imgui.End()
	if !imgui.Begin(fmt.ctprintf("%s  Command###LevelCommand", ICON_FA_TERMINAL), &lc.open, {.NoCollapse, .NoDocking}) do return
	Drive_Item("command.window")
	if lc.running {
		if UI_Button(fmt.tprintf("%s  Kill", ICON_FA_XMARK), "command.kill") {
			_ = os.process_kill(lc.process)
			print_line("-- sent kill signal")
			lc.keepOpen = true
		}
		level_tip("Stop the running command", "project.commands")
		imgui.SameLine()
		UI_DimText("running...")
	} else {
		if UI_Button("Close", "command.close") do lc.open = false
		level_tip("Close the output", "project.commands")
	}
	imgui.Separator()
	if imgui.BeginChild("##cmdout", {0, 0}, {}, {}) {
		for line in lc.output do imgui.TextUnformatted(fmt.ctprintf("%s", line))
		if lc.running do imgui.SetScrollHereY(1)
	}
	imgui.EndChild()
}

// LevelCommands_Output: the runner's output (drive checks).
LevelCommands_Output :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	for l in lc.output {
		strings.write_string(&b, l)
		strings.write_byte(&b, '\n')
	}
	return strings.to_string(b)
}
