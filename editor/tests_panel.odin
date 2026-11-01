package editor

import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// The Tests tab (#284): the project's tests (tests/*_test.lua, each
// test_<name>() function), run in the game runner (--test, hidden, a save
// folder of its own) - all, a file's, or one. Results arrive as
// "@rayzr:test" lines; a failure's line opens in the Code tab.
//
// Also the Play toolbar's Record button (Toolbar_RecordButton): the
// player's input saved to tests/recordings/ for Test.replay.
// ============================================================================

Test_Status :: enum u8 {Unknown, Queued, Running, Passed, Failed, Skipped}

Test_Failure :: struct {
	line:    int,
	message: string, // (heap)
}

Test_Row :: struct {
	file, name: string, // (heap)
	status:     Test_Status,
	failures:   [dynamic]Test_Failure,
	frames:     int,
	ms:         f64,
	skipNote:   string, // (heap)
}

@(private = "file")
testsPanel: struct {
	rows:      [dynamic]Test_Row,
	scanned:   bool,
	running:   bool,
	process:   os.Process,
	output:    ^os.File,
	lineBuf:   [dynamic]u8,
	summary:   string, // (heap) the last run's
	filter:    [128]u8,
	selected:  int, // row whose failures show (-1: none)
	recording: bool,
}

TestsPanel_Shutdown :: proc() {
	tests_clear_rows()
	delete(testsPanel.rows)
	delete(testsPanel.lineBuf)
	delete(testsPanel.summary)
	if testsPanel.output != nil do os.close(testsPanel.output)
	testsPanel = {}
}

@(private = "file")
tests_clear_rows :: proc() {
	for &r in testsPanel.rows {
		delete(r.file)
		delete(r.name)
		delete(r.skipNote)
		for f in r.failures do delete(f.message)
		delete(r.failures)
	}
	clear(&testsPanel.rows)
}

// tests_scan lists the project's tests (keeping the results of those still there).
@(private = "file")
tests_scan :: proc(state: ^EditorState) {
	old := testsPanel.rows
	testsPanel.rows = make([dynamic]Test_Row)
	for rel in Editor_ListProjectFiles(state, "tests", {".lua"}) {
		if !strings.has_suffix(rel, "_test.lua") do continue
		path, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		data, err := os.read_entire_file(path, context.temp_allocator)
		if err != nil do continue
		for n in e.Tests_FunctionNames(string(data)) {
			row := Test_Row{file = strings.clone(rel), name = strings.clone(n)}
			for &o in old do if o.file == rel && o.name == n {
				row.status, row.frames, row.ms = o.status, o.frames, o.ms
				row.failures, o.failures = o.failures, nil
				row.skipNote, o.skipNote = o.skipNote, ""
				break
			}
			append(&testsPanel.rows, row)
		}
	}
	for &o in old {
		delete(o.file)
		delete(o.name)
		delete(o.skipNote)
		for f in o.failures do delete(f.message)
		delete(o.failures)
	}
	delete(old)
	testsPanel.scanned = true
}

@(private = "file")
tests_row :: proc(file, name: string) -> ^Test_Row {
	for &r in testsPanel.rows do if r.file == file && r.name == name do return &r
	return nil
}

// TestsPanel_Run runs the tests whose "file:name" contains filter ("" all).
TestsPanel_Run :: proc(state: ^EditorState, filter: string) {
	if testsPanel.running do return
	tests_scan(state)
	exe := Editor_GameBinary()
	if exe == "" || !os.exists(exe) {
		Editor_Log(state, .Error, "No runner to run the tests with (scripts/build_runners.sh builds one)")
		return
	}
	if _, stale := Editor_GameBinaryIsStale(); stale do Editor_Log(state, .Warn, "Tests: the game binary is older than the engine sources (Play rebuilds it)")
	Editor_SaveAllScenes(state)
	Code_SaveAll(state) // (the tests and scripts as edited)
	for &r in testsPanel.rows {
		full := fmt.tprintf("%s:%s", r.file, r.name)
		if filter != "" && !strings.contains(full, filter) do continue
		r.status = .Queued
		for f in r.failures do delete(f.message)
		clear(&r.failures)
	}
	// A save folder of their own: tests never touch the player's saves.
	base := state.userDataDir if state.userDataDir != "" else os.get_env("TMPDIR", context.temp_allocator)
	if base == "" do base = "/tmp"
	userData, _ := filepath.join({base, "rayzr_tests"}, context.temp_allocator)
	_ = os.remove_all(userData)
	cmd := make([dynamic]string, context.temp_allocator)
	append(&cmd, exe, "--project", state.projectPath, "--hidden", "--user-data", userData, "--test", filter if filter != "" else "*")
	r, w, perr := os.pipe()
	if perr != nil {
		Editor_Log(state, .Error, "Tests: %v", perr)
		return
	}
	desc := os.Process_Desc{command = cmd[:], stdout = w, stderr = w}
	p, err := os.process_start(desc)
	os.close(w)
	if err != nil {
		os.close(r)
		Editor_Log(state, .Error, "Tests: could not start the runner: %v", err)
		return
	}
	testsPanel.process, testsPanel.output, testsPanel.running = p, r, true
	delete(testsPanel.summary)
	testsPanel.summary = strings.clone("Running...")
	Editor_Log(state, .Info, "Running tests%s", fmt.tprintf(" matching %q", filter) if filter != "" else "")
}

// TestsPanel_Update (every frame): the runner's output.
TestsPanel_Update :: proc(state: ^EditorState) {
	if !testsPanel.running do return
	f := testsPanel.output
	ended := false
	for f != nil {
		has, err := os.pipe_has_data(f)
		if err != nil || !has do break
		chunk: [4096]u8
		n, rerr := os.read(f, chunk[:])
		if n <= 0 || rerr != nil {
			ended = true
			break
		}
		append(&testsPanel.lineBuf, ..chunk[:n])
	}
	for {
		idx := -1
		for b, i in testsPanel.lineBuf do if b == '\n' {idx = i; break}
		if idx < 0 do break
		line := strings.clone(strings.trim_right_space(string(testsPanel.lineBuf[:idx])), context.temp_allocator)
		remove_range(&testsPanel.lineBuf, 0, idx + 1)
		tests_line(state, line)
	}
	if ended {
		os.close(testsPanel.output)
		testsPanel.output = nil
		_, _ = os.process_wait(testsPanel.process)
		// (process_wait released it)
		testsPanel.running = false
		clear(&testsPanel.lineBuf)
		for &r in testsPanel.rows do if r.status == .Queued || r.status == .Running do r.status = .Unknown
		if testsPanel.summary == "Running..." {
			delete(testsPanel.summary)
			testsPanel.summary = strings.clone("The runner stopped before the tests finished (see the Console)")
		}
	}
}

@(private = "file")
tests_line :: proc(state: ^EditorState, line: string) {
	kind := ""
	if strings.has_prefix(line, "@rayzr:test ") do kind = "test"
	else if strings.has_prefix(line, "@rayzr:tests ") do kind = "tests"
	else {
		// The game's own log lines: errors and warnings to the Console.
		lower := strings.to_lower(line, context.temp_allocator)
		if strings.contains(lower, "error") do Editor_Log(state, .Error, "[tests] %s", line)
		else if strings.contains(lower, "warn") do Editor_Log(state, .Warn, "[tests] %s", line)
		return
	}
	text := line[strings.index_byte(line, ' ') + 1:]
	v, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None do return
	o, ok := v.(json.Object)
	if !ok do return
	str :: proc(o: json.Object, k: string) -> string {return o[k].(json.String) or_else ""}
	num :: proc(o: json.Object, k: string) -> f64 {
		#partial switch n in o[k] {
		case json.Integer: return f64(n)
		case json.Float: return f64(n)
		}
		return 0
	}
	event := str(o, "event")
	if kind == "tests" {
		delete(testsPanel.summary)
		switch event {
		case "none": testsPanel.summary = strings.clone("No tests: add tests/<something>_test.lua with test_<name>() functions")
		case "done":
			testsPanel.summary = strings.clone(fmt.tprintf("%d passed, %d failed, %d skipped (%.0f ms)", int(num(o, "passed")), int(num(o, "failed")), int(num(o, "skipped")), num(o, "ms")))
			Editor_Log(state, .Error if num(o, "failed") > 0 else .Info, "Tests: %s", testsPanel.summary)
		case: testsPanel.summary = strings.clone(event)
		}
		return
	}
	file, name := str(o, "file"), str(o, "name")
	r := tests_row(file, name)
	if r == nil {
		// (A file that didn't load shows as its own row.)
		append(&testsPanel.rows, Test_Row{file = strings.clone(file), name = strings.clone(name)})
		r = &testsPanel.rows[len(testsPanel.rows) - 1]
	}
	switch event {
	case "start": r.status = .Running
	case "fail":
		append(&r.failures, Test_Failure{int(num(o, "line")), strings.clone(str(o, "message"))})
		Editor_Log(state, .Error, "%s:%d: %s: %s", file, int(num(o, "line")), name, str(o, "message"))
	case "skipped":
		delete(r.skipNote)
		r.skipNote = strings.clone(str(o, "message"))
	case "end":
		r.frames, r.ms = int(num(o, "frames")), num(o, "ms")
		if o["skipped"].(json.Boolean) or_else false do r.status = .Skipped
		else if o["passed"].(json.Boolean) or_else false do r.status = .Passed
		else do r.status = .Failed
	}
}

TestsPanel_Render :: proc(state: ^EditorState) {
	if !testsPanel.scanned do tests_scan(state)
	busy := testsPanel.running // (once per frame: a click mid-frame starts a run)
	if busy do imgui.BeginDisabled(true)
	if UI_Button(fmt.tprintf("%s  Run All", ICON_FA_PLAY), "tests.run-all") do TestsPanel_Run(state, "")
	UI_Tooltip("Runs every test in tests/*_test.lua in the game runner (hidden; its own save folder)")
	imgui.SameLine()
	failed := 0
	for r in testsPanel.rows do if r.status == .Failed do failed += 1
	if failed == 0 do imgui.BeginDisabled(true)
	if UI_Button(fmt.tprintf("%s  Run Failed", ICON_FA_ROTATE), "tests.run-failed") {
		// (One run per failed test's name: the runner takes one filter.)
		for r in testsPanel.rows do if r.status == .Failed {
			TestsPanel_Run(state, fmt.tprintf("%s:%s", r.file, r.name))
			break
		}
	}
	if failed == 0 do imgui.EndDisabled()
	UI_Tooltip("Runs the first failed test again")
	if busy do imgui.EndDisabled()
	imgui.SameLine()
	if UI_IconButton(ICON_FA_ROTATE, "tests.rescan", "Find the tests again (after adding a file or a test)") do tests_scan(state)
	imgui.SameLine()
	imgui.SetNextItemWidth(200)
	imgui.InputTextWithHint("##tests_filter", "Filter tests", cstring(&testsPanel.filter[0]), len(testsPanel.filter))
	Drive_Item("tests.filter")
	imgui.SameLine()
	imgui.AlignTextToFramePadding()
	UI_DimText(testsPanel.summary if testsPanel.summary != "" else fmt.tprintf("%d tests - tests/*_test.lua, test_<name>() functions (Help: Test)", len(testsPanel.rows)))
	imgui.Separator()
	filter := strings.to_lower(string(cstring(&testsPanel.filter[0])), context.temp_allocator)
	if imgui.BeginChild("##tests_list", {0, 0}, {}, {}) {
		lastFile := ""
		for &r, i in testsPanel.rows {
			if filter != "" && !strings.contains(strings.to_lower(fmt.tprintf("%s %s", r.file, r.name), context.temp_allocator), filter) do continue
			imgui.PushIDInt(c.int(i))
			if r.file != lastFile {
				lastFile = r.file
				imgui.AlignTextToFramePadding()
				imgui.TextUnformatted(fmt.ctprintf("%s  %s", ICON_FA_FILE_CODE, r.file))
				imgui.SameLine()
				if busy do imgui.BeginDisabled(true)
				if UI_IconButton(ICON_FA_PLAY, fmt.tprintf("tests.run-file:%s", r.file), "Run this file's tests", size = 22) do TestsPanel_Run(state, fmt.tprintf("%s:", r.file))
				if busy do imgui.EndDisabled()
			}
			imgui.Indent(20)
			icon, col := tests_status_look(r.status)
			imgui.TextColored(col, fmt.ctprintf("%s", icon))
			imgui.SameLine()
			if busy do imgui.BeginDisabled(true)
			if UI_IconButton(ICON_FA_PLAY, fmt.tprintf("tests.run:%s", r.name), "Run this test", size = 20) do TestsPanel_Run(state, fmt.tprintf("%s:%s", r.file, r.name))
			if busy do imgui.EndDisabled()
			imgui.SameLine()
			if imgui.Selectable(fmt.ctprintf("%s##row", r.name), testsPanel.selected == i, {.AllowDoubleClick}) {
				testsPanel.selected = i
				if imgui.IsMouseDoubleClicked(.Left) do Editor_OpenScript(state, r.file, tests_def_line(state, &r) - 1)
			}
			Drive_Item(fmt.tprintf("tests.row:%s", r.name))
			if r.status == .Passed || r.status == .Failed {
				imgui.SameLine()
				UI_DimText(fmt.tprintf("%d frames, %.1f ms", r.frames, r.ms))
			}
			if r.status == .Skipped && r.skipNote != "" {
				imgui.SameLine()
				UI_DimText(fmt.tprintf("skipped: %s", r.skipNote))
			}
			// Failures: double-click opens the line.
			for f, k in r.failures {
				imgui.PushIDInt(c.int(1000 + k))
				imgui.Indent(28)
				first := f.message
				if nl := strings.index_byte(first, '\n'); nl >= 0 && testsPanel.selected != i do first = first[:nl]
				lbl := fmt.ctprintf("line %d: %s", f.line, first) if f.line > 0 else fmt.ctprintf("%s", first)
				imgui.PushStyleColor(.Text, imgui.ColorConvertFloat4ToU32({0.97, 0.45, 0.45, 1}))
				if imgui.Selectable(lbl, false, {.AllowDoubleClick}) {
					testsPanel.selected = i
					if imgui.IsMouseDoubleClicked(.Left) && f.line > 0 do Editor_OpenScript(state, r.file, f.line - 1)
				}
				imgui.PopStyleColor()
				Drive_Item(fmt.tprintf("tests.failure:%s:%d", r.name, k))
				UI_Tooltip("Double-click: open the line in the Code tab")
				imgui.Unindent(28)
				imgui.PopID()
			}
			imgui.Unindent(20)
			imgui.PopID()
		}
		if len(testsPanel.rows) == 0 {
			UI_DimTextWrapped("No tests yet. Add a file tests/player_test.lua with functions named test_<something>(): Test.press(\"jump\"), Test.step(20), Test.expect(...). Help > Lua API > Test has the rest.")
		}
	}
	imgui.EndChild()
}

// tests_def_line: where test_<name> is defined (1-based; 1 if not found).
@(private = "file")
tests_def_line :: proc(state: ^EditorState, r: ^Test_Row) -> int {
	path, _ := filepath.join({state.projectPath, r.file}, context.temp_allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil do return 1
	for line, i in strings.split_lines(string(data), context.temp_allocator) {
		if strings.contains(line, fmt.tprintf("function %s", r.name)) do return i + 1
	}
	return 1
}

@(private = "file")
tests_status_look :: proc(s: Test_Status) -> (string, [4]f32) {
	switch s {
	case .Unknown: return ICON_FA_CIRCLE, {0.5, 0.5, 0.55, 1}
	case .Queued: return ICON_FA_CIRCLE, {0.6, 0.65, 0.75, 1}
	case .Running: return ICON_FA_CIRCLE_DOT, {0.49, 0.83, 0.99, 1}
	case .Passed: return ICON_FA_CIRCLE_CHECK, {0.53, 0.87, 0.45, 1}
	case .Failed: return ICON_FA_XMARK, {0.97, 0.45, 0.45, 1}
	case .Skipped: return ICON_FA_FORWARD, {0.98, 0.8, 0.08, 1}
	}
	return ICON_FA_CIRCLE, {1, 1, 1, 1}
}

// ----------------------------------------------------------------------------
// Recording in Play
// ----------------------------------------------------------------------------

// Toolbar_RecordButton: while the game runs, records the player's input
// to tests/recordings/ (Test.replay plays it back).
Toolbar_RecordButton :: proc(state: ^EditorState) {
	if !state.gameProcessRunning {
		testsPanel.recording = false
		return
	}
	if !RemoteGame_Connected() do imgui.BeginDisabled(true)
	if testsPanel.recording {
		if UI_IconButton(ICON_FA_STOP, "toolbar.record", "Stop recording: saves tests/recordings/recording_N.txt - Test.replay(\"recording_N\") plays it back", true, tint = UI_DANGER) {
			RemoteGame_Send(fmt.tprintf("record-stop %s", tests_next_recording(state)))
			testsPanel.recording = false
		}
	} else {
		if UI_IconButton(ICON_FA_CIRCLE, "toolbar.record", "Record your input (keys, mouse, gamepads, touch) for a test to replay", tint = UI_DANGER) {
			RemoteGame_Send("record-start")
			testsPanel.recording = true
		}
	}
	if !RemoteGame_Connected() do imgui.EndDisabled()
}

@(private = "file")
tests_next_recording :: proc(state: ^EditorState) -> string {
	for n in 1 ..< 1000 {
		rel := fmt.tprintf("tests/recordings/recording_%d.txt", n)
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		if !os.exists(full) do return rel
	}
	return "tests/recordings/recording.txt"
}

// TestsPanel_Recorded: the game wrote a recording ("@rayzr:recorded {...}").
TestsPanel_Recorded :: proc(state: ^EditorState, text: string) {
	v, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None do return
	o, _ := v.(json.Object)
	path := o["path"].(json.String) or_else ""
	if !(o["ok"].(json.Boolean) or_else false) {
		Editor_Log(state, .Error, "Recording not saved (%s)", path)
		return
	}
	name := strings.trim_suffix(filepath.base(path), ".txt")
	Editor_Log(state, .Info, "Recorded %s - in a test: Test.replay(\"%s\")", path, name)
	Editor_InvalidateProjectFiles()
}
