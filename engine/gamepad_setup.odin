package engine

import "core:fmt"
import "core:strings"

// ============================================================================
// Controller Setup: "press A", "press B", ... on one controller's raw inputs
// (gamepad_glfw.odin), making its mapping line (gamepad_mappings.odin). The
// editor's Tools > Controllers, the built-in game screen
// (gamepad_setup_screen.odin) and Input.mapping_* (custom screens) all run
// this one.
//
// Each step takes the first input that moves from rest: a button, a hat
// direction, or an axis (a trigger resting at -1 is a whole axis; one
// resting at 0 is half of one, "+a2"; a stick pushed the wrong way is an
// inverted axis, "a1~"). Then everything has to go back to rest before the
// next step. An input already used is refused (a trigger moved at a stick
// step: its axis is the trigger's). Steps can be skipped (the
// controller has no such button) or gone back to.
// ============================================================================

Pad_SetupKind :: enum u8 {Button, Axis}

Pad_SetupStep :: struct {
	field: string, // the mapping's name ("a", "leftx")
	label: string, // what to do
	kind:  Pad_SetupKind,
}

PAD_SETUP_STEPS := [?]Pad_SetupStep {
	{"a", "Press A (the bottom face button)", .Button},
	{"b", "Press B (the right face button)", .Button},
	{"x", "Press X (the left face button)", .Button},
	{"y", "Press Y (the top face button)", .Button},
	{"dpup", "Press up on the d-pad", .Button},
	{"dpdown", "Press down on the d-pad", .Button},
	{"dpleft", "Press left on the d-pad", .Button},
	{"dpright", "Press right on the d-pad", .Button},
	{"leftshoulder", "Press the left bumper (L1 / L)", .Button},
	{"rightshoulder", "Press the right bumper (R1 / R)", .Button},
	{"lefttrigger", "Pull the left trigger (L2 / ZL)", .Button},
	{"righttrigger", "Pull the right trigger (R2 / ZR)", .Button},
	{"back", "Press Back (Select / Share / Minus)", .Button},
	{"start", "Press Start (Menu / Options / Plus)", .Button},
	{"guide", "Press the Home / Guide button", .Button},
	{"leftstick", "Press the left stick in (L3)", .Button},
	{"rightstick", "Press the right stick in (R3)", .Button},
	{"leftx", "Move the left stick right", .Axis},
	{"lefty", "Move the left stick down", .Axis},
	{"rightx", "Move the right stick right", .Axis},
	{"righty", "Move the right stick down", .Axis},
}

PAD_SETUP_PRESS :: 0.6 // how far from rest an axis has to move to count
PAD_SETUP_REST :: 0.3  // ... and back to count as released

Pad_Setup :: struct {
	active:      bool,
	done:        bool, // every step answered or skipped
	jid:         i32,
	guid, name:  string, // (heap)
	step:        int,
	results:     [len(PAD_SETUP_STEPS)]string, // (heap) the input per step; "" skipped / not yet
	rest:        [dynamic]f32, // (heap) the axes at rest
	waitRelease: bool,
	message:     string, // (static) why the last input was refused
}

padSetup: Pad_Setup

// Pad_SetupBegin: setup for joystick jid (0-based). Its axes now are rest -
// sticks centred, triggers let go.
Pad_SetupBegin :: proc(jid: i32) -> bool {
	if !joy_present(jid) do return false
	return Pad_SetupBeginWith(jid, joy_guid(jid), joy_name(jid), joy_axes(jid))
}

// Pad_SetupBeginWith: setup for a controller described directly (tests).
Pad_SetupBeginWith :: proc(jid: i32, guid, name: string, restAxes: []f32) -> bool {
	Pad_SetupCancel()
	heap := Engine_HeapAllocator()
	padSetup.active = true
	padSetup.jid = jid
	padSetup.guid = strings.to_lower(guid, heap)
	padSetup.name = strings.clone(name, heap)
	padSetup.rest = make([dynamic]f32, len(restAxes), heap)
	copy(padSetup.rest[:], restAxes)
	padSetup.waitRelease = true // (whatever is held now)
	return true
}

Pad_SetupCancel :: proc() {
	heap := Engine_HeapAllocator()
	delete(padSetup.guid, heap)
	delete(padSetup.name, heap)
	for r in padSetup.results do delete(r, heap)
	delete(padSetup.rest)
	padSetup = {}
}

// Pad_SetupFrame (each frame while active): the controller's inputs now.
// false when it disconnected (setup ends).
Pad_SetupFrame :: proc() -> bool {
	if !padSetup.active do return false
	when !JOY_RAW {
		return true
	} else {
		if !joy_present(padSetup.jid) || !strings.equal_fold(joy_guid(padSetup.jid), padSetup.guid) {
			Pad_SetupCancel()
			return false
		}
		Pad_SetupFeed(joy_buttons(padSetup.jid), joy_axes(padSetup.jid), joy_hats(padSetup.jid))
		return true
	}
}

// Pad_SetupFeed: one snapshot of the raw inputs.
Pad_SetupFeed :: proc(buttons: []u8, axes: []f32, hats: []u8) {
	s := &padSetup
	if !s.active || s.done do return
	rest :: proc(i: int) -> f32 {return padSetup.rest[i] if i < len(padSetup.rest) else 0}
	if s.waitRelease {
		for b in buttons do if b != 0 do return
		for h in hats do if h != 0 do return
		for a, i in axes do if abs(a - rest(i)) > PAD_SETUP_REST do return
		s.waitRelease = false
		return
	}
	step := PAD_SETUP_STEPS[s.step]
	input := ""
	switch step.kind {
	case .Button:
		for b, i in buttons do if b != 0 {
			input = fmt.tprintf("b%d", i)
			break
		}
		if input == "" do for h, i in hats do if h != 0 {
			for bit in ([4]u8{1, 2, 4, 8}) do if h & bit != 0 {
				input = fmt.tprintf("h%d.%d", i, bit)
				break
			}
			break
		}
		if input == "" do for a, i in axes {
			d := a - rest(i)
			if abs(d) <= PAD_SETUP_PRESS do continue
			if rest(i) < -0.5 do input = fmt.tprintf("a%d", i)       // a trigger's whole axis
			else if rest(i) > 0.5 do input = fmt.tprintf("a%d~", i)  // ... upside down
			else do input = fmt.tprintf("%sa%d", "+" if d > 0 else "-", i)
			break
		}
	case .Axis:
		for a, i in axes {
			d := a - rest(i)
			if abs(d) <= PAD_SETUP_PRESS do continue // (a stick that rests off centre still counts: some controllers' do)
			input = fmt.tprintf("a%d", i) if d > 0 else fmt.tprintf("a%d~", i)
			break
		}
	}
	if input == "" do return
	s.waitRelease = true
	if used := pad_setup_used(input); used >= 0 {
		s.message = PAD_SETUP_STEPS[used].label
		return
	}
	s.message = ""
	s.results[s.step] = strings.clone(input, Engine_HeapAllocator())
	pad_setup_next()
}

// pad_setup_used: the step that already took this input (-1: none). Half
// axes ("+a2" / "-a2") are different inputs; whole ones take both halves.
@(private = "file")
pad_setup_used :: proc(input: string) -> int {
	ref, _ := Gamepad_FieldInput(fmt.tprintf("x:%s", input))
	half := input[0] == '+' || input[0] == '-'
	for r, i in padSetup.results {
		if r == "" || i == padSetup.step do continue
		q, ok := Gamepad_FieldInput(fmt.tprintf("x:%s", r))
		if !ok || q != ref do continue
		if ref.kind == 'h' && r != input do continue // another direction of the hat
		if half && (r[0] == '+' || r[0] == '-') && r[0] != input[0] do continue
		return i
	}
	return -1
}

@(private = "file")
pad_setup_next :: proc() {
	padSetup.step += 1
	if padSetup.step >= len(PAD_SETUP_STEPS) {
		padSetup.step = len(PAD_SETUP_STEPS) - 1
		padSetup.done = true
	}
}

// Pad_SetupSkip: this step has no input (the controller has no such button).
Pad_SetupSkip :: proc() {
	if !padSetup.active || padSetup.done do return
	delete(padSetup.results[padSetup.step], Engine_HeapAllocator())
	padSetup.results[padSetup.step] = ""
	padSetup.message = ""
	pad_setup_next()
	padSetup.waitRelease = true
}

// Pad_SetupBack: the previous step again (after the last: the last).
Pad_SetupBack :: proc() {
	if !padSetup.active do return
	if padSetup.done {
		padSetup.done = false
	} else if padSetup.step > 0 {
		padSetup.step -= 1
	}
	delete(padSetup.results[padSetup.step], Engine_HeapAllocator())
	padSetup.results[padSetup.step] = ""
	padSetup.message = ""
	padSetup.waitRelease = true
}

// Pad_SetupMapping: the mapping line so far (temp).
Pad_SetupMapping :: proc(allocator := context.temp_allocator) -> string {
	fields := make([dynamic]string, context.temp_allocator)
	for r, i in padSetup.results do if r != "" {
		append(&fields, fmt.tprintf("%s:%s", PAD_SETUP_STEPS[i].field, r))
	}
	return Gamepad_BuildLine(padSetup.guid, padSetup.name, fields[:], GAMEPAD_PLATFORM, allocator)
}

// Pad_SetupFinish: the mapping in use now, and saved into `path` (a
// gamecontrollerdb.txt; "" = not saved). Setup ends. "" (and nothing done)
// when not a single input was set.
Pad_SetupFinish :: proc(path := "", source := Pad_MapSource.Setup, allocator := context.temp_allocator) -> (line: string, saved: bool) {
	if !padSetup.active do return "", false
	any := false
	for r in padSetup.results do if r != "" do any = true
	if !any {
		Pad_SetupCancel()
		return "", false
	}
	line = Pad_SetupMapping(allocator)
	Gamepad_ApplyMapping(line, source)
	if path != "" do saved = Gamepad_SaveMappingFile(path, line)
	Pad_SetupCancel()
	return
}
