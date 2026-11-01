package engine

import "core:fmt"
import os "osx"
import "core:path/filepath"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

// ============================================================================
// Recording a player's input in Play (#284): the editor's Record button
// sends "record-start" / "record-stop <file>" over the editor link. Every
// frame the keys, the mouse (left button, in game units), gamepads and
// fingers that changed are written in the runner's input-script format
// (Runner_LoadInputScript), frames counted from the start, with the scene
// it began in - Test.replay plays it back.
// ============================================================================

Input_Recorder :: struct {
	on:       bool,
	frame:    int,
	sb:       strings.Builder,
	mouse:    [2]f32,
	mouseDown: bool,
	pads:     [4]bool, // connected (written once)
	axes:     [4][6]f32,
	touches:  map[i32][2]f32, // fingers down (id: position)
}

inputRecorder: Input_Recorder

Recorder_Start :: proc(game: ^Game) {
	Recorder_Discard()
	context.allocator = Engine_HeapAllocator()
	inputRecorder.on = true
	inputRecorder.sb = strings.builder_make()
	inputRecorder.touches = make(map[i32][2]f32)
	scene := ""
	if s := game.sceneManager.currentScene; s != nil do scene = s.filePath
	fmt.sbprintf(&inputRecorder.sb, "# Recorded in Play %v (Test.replay plays it back)\n", time.now())
	if scene != "" do fmt.sbprintf(&inputRecorder.sb, "# scene %s\n", scene)
	if rl.IsWindowReady() {
		inputRecorder.mouse = rl.GetMousePosition()
		inputRecorder.mouseDown = rl.IsMouseButtonDown(.LEFT)
	}
}

Recorder_Discard :: proc() {
	if inputRecorder.sb.buf != nil do strings.builder_destroy(&inputRecorder.sb)
	delete(inputRecorder.touches)
	inputRecorder = {}
}

// Recorder_Stop writes the recording (project-relative or absolute path).
Recorder_Stop :: proc(game: ^Game, path: string) -> (written: string, ok: bool) {
	if !inputRecorder.on do return "", false
	full := path
	if !filepath.is_abs(path) do full, _ = filepath.join({game.assetManager.projectDir, path}, context.temp_allocator)
	_ = os.make_directory_all(filepath.dir(full, context.temp_allocator))
	ok = os.write_entire_file(full, transmute([]u8)strings.to_string(inputRecorder.sb)) == nil
	Recorder_Discard()
	return full, ok
}

// Recorder_Frame (the runner, every frame while recording): what changed.
Recorder_Frame :: proc(game: ^Game) {
	if !inputRecorder.on || !rl.IsWindowReady() do return
	r := &inputRecorder
	f := r.frame
	r.frame += 1
	sb := &r.sb
	// Keys.
	for k in 32 ..< 349 {
		key := rl.KeyboardKey(k)
		if rl.IsKeyPressed(key) do fmt.sbprintf(sb, "%d %v down\n", f, key)
		if rl.IsKeyReleased(key) do fmt.sbprintf(sb, "%d %v up\n", f, key)
	}
	// The mouse (game units: the runner maps it).
	m := rl.GetMousePosition()
	down := rl.IsMouseButtonDown(.LEFT)
	if down != r.mouseDown {
		fmt.sbprintf(sb, "%d mouse %.1f %.1f %s\n", f, m.x, m.y, "down" if down else "up")
	} else if abs(m.x - r.mouse.x) >= 0.5 || abs(m.y - r.mouse.y) >= 0.5 {
		fmt.sbprintf(sb, "%d mouse %.1f %.1f move\n", f, m.x, m.y)
	}
	r.mouse, r.mouseDown = m, down
	// Gamepads.
	for p in 0 ..< 4 {
		pad := i32(p)
		avail := rl.IsGamepadAvailable(pad)
		if avail != r.pads[p] {
			if avail do fmt.sbprintf(sb, "%d pad%d connect %s\n", f, p + 1, string(rl.GetGamepadName(pad)))
			else do fmt.sbprintf(sb, "%d pad%d disconnect\n", f, p + 1)
			r.pads[p] = avail
		}
		if !avail do continue
		for b in rl.GamepadButton {
			if b == .UNKNOWN do continue
			if rl.IsGamepadButtonPressed(pad, b) do fmt.sbprintf(sb, "%d pad%d %v down\n", f, p + 1, b)
			if rl.IsGamepadButtonReleased(pad, b) do fmt.sbprintf(sb, "%d pad%d %v up\n", f, p + 1, b)
		}
		for a in rl.GamepadAxis {
			v := rl.GetGamepadAxisMovement(pad, a)
			if abs(v - r.axes[p][int(a)]) >= 0.02 {
				fmt.sbprintf(sb, "%d pad%d %v %.3f\n", f, p + 1, a, v)
				r.axes[p][int(a)] = v
			}
		}
	}
	// Fingers (touchN, by the order they landed: ids 1..10).
	seen := make(map[i32]bool, allocator = context.temp_allocator)
	for i in 0 ..< rl.GetTouchPointCount() {
		id := rl.GetTouchPointId(i)
		slot := (id % 10) + 1
		pos := Touch_ScreenToGame(game, rl.GetTouchPosition(i))
		seen[slot] = true
		if prev, was := r.touches[slot]; !was {
			fmt.sbprintf(sb, "%d touch%d %.1f %.1f down\n", f, slot, pos.x, pos.y)
		} else if abs(pos.x - prev.x) >= 0.5 || abs(pos.y - prev.y) >= 0.5 {
			fmt.sbprintf(sb, "%d touch%d %.1f %.1f move\n", f, slot, pos.x, pos.y)
		}
		r.touches[slot] = pos
	}
	lifted := make([dynamic]i32, context.temp_allocator)
	for slot, pos in r.touches do if slot not_in seen {
		fmt.sbprintf(sb, "%d touch%d %.1f %.1f up\n", f, slot, pos.x, pos.y)
		append(&lifted, slot)
	}
	for slot in lifted do delete_key(&r.touches, slot)
}
