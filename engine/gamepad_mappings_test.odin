package engine

import os "osx"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import lua "lua54"

// Gamepad mappings (gamepad_mappings.odin) and Controller Setup
// (gamepad_setup.odin): lines, the fallbacks, the files, the setup steps
// fed raw snapshots, and the Lua API without a controller.

@(private = "file")
LIC_GUID :: "050000004c69632050726f20436f6e00"

@(private = "file")
LIC_LINUX :: "050000004c69632050726f20436f6e00,Nintendo Switch Controller,a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b12,leftshoulder:b4,leftstick:b10,lefttrigger:b6,leftx:a0,lefty:a1,misc1:b13,rightshoulder:b5,rightstick:b11,righttrigger:b7,rightx:a2,righty:a3,start:b9,x:b2,y:b3,platform:Linux,"

@(private = "file")
has_field :: proc(line, field: string) -> bool {
	return strings.contains(line, strings.concatenate({",", field, ","}, context.temp_allocator))
}

@(test)
test_gamepad_mapping_lines :: proc(t: ^testing.T) {
	p, ok := Gamepad_ParseLine(LIC_LINUX)
	testing.expect(t, ok, "a mapping line parses")
	testing.expect_value(t, p.guid, LIC_GUID)
	testing.expect_value(t, p.name, "Nintendo Switch Controller")
	testing.expect_value(t, p.platform, "Linux")
	testing.expect_value(t, len(p.fields), 22)
	_, isMap := Gamepad_ParseLine("# a comment")
	testing.expect(t, !isMap, "comments aren't lines")
	_, isMap = Gamepad_ParseLine("xyz,Not a guid,a:b0,")
	testing.expect(t, !isMap, "a bad GUID isn't a line")

	l := Gamepad_BuildLine(strings.to_upper(LIC_GUID, context.temp_allocator), "Pad, with comma", {"a:b0", "leftx:a0"}, "Mac OS X")
	testing.expect_value(t, l, LIC_GUID + ",Pad  with comma,a:b0,leftx:a0,platform:Mac OS X,")

	for c in ([]struct {f: string, kind: u8, i: int}{{"a:b3", 'b', 3}, {"lefttrigger:+a2", 'a', 2}, {"lefty:a1~", 'a', 1}, {"dpup:h0.1", 'h', 0}, {"x:b12", 'b', 12}}) {
		ref, rok := Gamepad_FieldInput(c.f)
		testing.expectf(t, rok && ref.kind == c.kind && ref.index == c.i, "%s -> %v", c.f, ref)
	}
	// Fields past the controller's counts go (GLFW drops the whole mapping otherwise).
	fit := Gamepad_FitFields(p.fields[:], 4, 12, 1)
	for f in fit do testing.expectf(t, f != "guide:b12" && f != "misc1:b13", "%s is past 12 buttons", f)
	testing.expect_value(t, len(fit), 20)
	fit = Gamepad_FitFields(p.fields[:], 2, 20, 0)
	for f in fit do testing.expectf(t, !strings.has_prefix(f, "dp") && f != "rightx:a2", "%s doesn't fit 2 axes, no hat", f)

	// The generic layout follows the counts.
	g := Gamepad_GenericMapping(LIC_GUID, "Odd Pad", 2, 6, 0)
	testing.expect(t, has_field(g, "a:b0") && has_field(g, "rightshoulder:b5") && !has_field(g, "lefttrigger:b6"), g)
	testing.expect(t, has_field(g, "lefty:a1") && !has_field(g, "rightx:a2") && !strings.contains(g, "dpup"), g)
	g = Gamepad_GenericMapping(LIC_GUID, "Full Pad", 4, 13, 1)
	testing.expect(t, has_field(g, "guide:b12") && has_field(g, "righty:a3") && has_field(g, "dpleft:h0.8"), g)
	testing.expect(t, strings.has_suffix(g, "platform:" + GAMEPAD_PLATFORM + ","), g)
}

@(test)
test_gamepad_mapping_fallbacks :: proc(t: ^testing.T) {
	defer Gamepad_MappingsShutdown()
	// The bundled database has the Lic Pro Controller for Linux only: rewritten for here.
	Gamepad_ConfigureMappings("", true, false)
	line, src := Gamepad_ResolveFallback(LIC_GUID, "Lic Pro Controller", 4, 20, 1)
	testing.expect_value(t, src, Pad_MapSource.Other_Platform)
	testing.expect(t, strings.has_prefix(line, LIC_GUID + ",Lic Pro Controller,"), line)
	testing.expect(t, has_field(line, "a:b0") && has_field(line, "dpup:h0.1") && has_field(line, "misc1:b13"), line)
	testing.expect(t, strings.has_suffix(line, "platform:" + GAMEPAD_PLATFORM + ","), line)

	// The project's line comes before the database's; the bus-swapped GUID counts.
	proj := "# ours\n" + "030000004c69632050726f20436f6e00,Lic Pro (USB),a:b1,b:b0,platform:Linux,\n"
	Gamepad_ConfigureMappings(proj, true, false)
	usb := "030000004c69632050726f20436f6e00"
	line, src = Gamepad_ResolveFallback(usb, "", 4, 20, 1)
	testing.expect_value(t, src, Pad_MapSource.Other_Platform)
	testing.expect(t, strings.has_prefix(line, "030000004c69632050726f20436f6e00,Lic Pro (USB),a:b1,b:b0,"), line)
	swapped := "050000004c69632050726f20436f6e00"
	line, src = Gamepad_ResolveFallback(swapped, "Lic", 4, 20, 1)
	testing.expect(t, strings.contains(line, ",Lic,a:b0,"), "the exact GUID (bundled) wins over the swapped one (project)")

	// Unknown: the generic layout - or nothing when the project turned it off.
	unknown := "03000000deadbeef0000000000000000"
	line, src = Gamepad_ResolveFallback(unknown, "Mystery Pad", 4, 12, 1)
	testing.expect_value(t, src, Pad_MapSource.Generic)
	testing.expect(t, has_field(line, "a:b0") && has_field(line, "dpup:h0.1"), line)
	Gamepad_ConfigureMappings("", false, false)
	line, src = Gamepad_ResolveFallback(unknown, "Mystery Pad", 4, 12, 1)
	testing.expect(t, line == "" && src == .None, "fallback off: no mapping")
	testing.expect(t, !Gamepad_FallbackEnabled(), "fallback off")

	// Applying records it (and where it came from).
	testing.expect(t, Gamepad_ApplyMapping(Gamepad_GenericMapping(unknown, "Mystery Pad", 4, 12, 1), .Generic), "applied")
	m, has := Gamepad_MappingOf(strings.to_upper(unknown, context.temp_allocator))
	testing.expect(t, has && m.source == .Generic && strings.has_prefix(m.line, unknown), "recorded")
	testing.expect(t, !Gamepad_ApplyMapping("nonsense", .Script), "not a line")
}

@(test)
test_gamepad_mapping_files :: proc(t: ^testing.T) {
	dir, _ := filepath.join({Engine_TempDir(), "rayzr_padmap_test"}, context.temp_allocator)
	_ = os.remove_all(dir)
	defer os.remove_all(dir)
	path, _ := filepath.join({dir, "sub", GAMEPAD_DB_FILE}, context.temp_allocator)
	other := "03000000111111111111111111111111,Other,a:b0,platform:" + GAMEPAD_PLATFORM + ","
	testing.expect(t, Gamepad_SaveMappingFile(path, other), "saved (folder made)")
	testing.expect(t, Gamepad_SaveMappingFile(path, LIC_LINUX), "saved")
	testing.expect(t, Gamepad_FileHasMapping(path, LIC_GUID), "has it (for this platform)")
	// Saving it again replaces it.
	testing.expect(t, Gamepad_SaveMappingFile(path, strings.concatenate({LIC_GUID, ",Lic,a:b3,"}, context.temp_allocator)), "saved again")
	data, _ := os.read_entire_file(path, context.temp_allocator)
	text := string(data)
	testing.expectf(t, strings.count(text, LIC_GUID) == 1 && strings.contains(text, ",Lic,a:b3,platform:"), "replaced: %s", text)
	testing.expect(t, strings.contains(text, "Other,a:b0"), "the other line stays")
	testing.expect(t, Gamepad_RemoveMappingFile(path, LIC_GUID), "removed")
	testing.expect(t, !Gamepad_FileHasMapping(path, LIC_GUID), "gone")
	testing.expect(t, !Gamepad_RemoveMappingFile(path, LIC_GUID), "nothing to remove")
	testing.expect(t, Gamepad_FileHasMapping(path, "03000000111111111111111111111111"), "the other line stays")
	testing.expect(t, !Gamepad_SaveMappingFile(path, "not a line"), "not a line")
}

@(test)
test_gamepad_setup_steps :: proc(t: ^testing.T) {
	defer Gamepad_MappingsShutdown()
	defer Pad_SetupCancel()
	// 6 axes: two sticks, two triggers resting at -1; 14 buttons; a hat.
	rest := []f32{0, 0, 0, 0, -1, -1}
	testing.expect(t, Pad_SetupBeginWith(3, LIC_GUID, "Test Pad", rest), "begun")
	axes := make([]f32, 6, context.temp_allocator)
	buttons := make([]u8, 14, context.temp_allocator)
	hats := make([]u8, 1, context.temp_allocator)
	idle :: proc(axes: []f32, buttons: []u8, hats: []u8, rest: []f32) {
		copy(axes, rest)
		for &b in buttons do b = 0
		for &h in hats do h = 0
		Pad_SetupFeed(buttons, axes, hats)
	}
	press :: proc(axes: []f32, buttons: []u8, hats: []u8, rest: []f32, b := -1, h: u8 = 0, axis := -1, v: f32 = 0) {
		idle(axes, buttons, hats, rest) // (released first)
		if b >= 0 do buttons[b] = 1
		hats[0] = h
		if axis >= 0 do axes[axis] = v
		Pad_SetupFeed(buttons, axes, hats)
	}
	idle(axes, buttons, hats, rest)
	press(axes, buttons, hats, rest, b = 1) // A
	press(axes, buttons, hats, rest, b = 0) // B
	press(axes, buttons, hats, rest, b = 1) // X: already A's - refused
	testing.expect_value(t, padSetup.step, 2)
	testing.expect(t, padSetup.message != "", "refused, says which step has it")
	press(axes, buttons, hats, rest, b = 3) // X
	press(axes, buttons, hats, rest, b = 2) // Y
	press(axes, buttons, hats, rest, h = 1) // up
	press(axes, buttons, hats, rest, h = 4) // down
	press(axes, buttons, hats, rest, h = 8) // left
	press(axes, buttons, hats, rest, h = 2) // right
	press(axes, buttons, hats, rest, b = 4) // L1
	press(axes, buttons, hats, rest, b = 5) // R1
	press(axes, buttons, hats, rest, axis = 4, v = 1) // L2: a whole axis
	press(axes, buttons, hats, rest, axis = 5, v = 0.9) // R2
	press(axes, buttons, hats, rest, b = 8) // back
	press(axes, buttons, hats, rest, b = 9) // start
	Pad_SetupSkip() // guide: none
	press(axes, buttons, hats, rest, b = 10) // L3
	Pad_SetupBack() // L3 again
	testing.expect_value(t, PAD_SETUP_STEPS[padSetup.step].field, "leftstick")
	press(axes, buttons, hats, rest, b = 10) // L3
	press(axes, buttons, hats, rest, b = 11) // R3
	press(axes, buttons, hats, rest, axis = 0, v = 0.9) // left x
	press(axes, buttons, hats, rest, axis = 1, v = -0.9) // left y: pushed down reads -1 here - inverted
	press(axes, buttons, hats, rest, axis = 4, v = 1) // right x: the left trigger moved - its axis is taken
	testing.expect_value(t, PAD_SETUP_STEPS[padSetup.step].field, "rightx")
	testing.expect_value(t, padSetup.message, PAD_SETUP_STEPS[10].label)
	press(axes, buttons, hats, rest, axis = 2, v = 1) // right x
	testing.expect(t, !padSetup.done, "one to go")
	press(axes, buttons, hats, rest, axis = 3, v = 1) // right y
	testing.expect(t, padSetup.done, "done")

	m := Pad_SetupMapping()
	for f in ([]string{"a:b1", "b:b0", "x:b3", "y:b2", "dpup:h0.1", "dpdown:h0.4", "dpleft:h0.8", "dpright:h0.2", "leftshoulder:b4", "rightshoulder:b5", "lefttrigger:a4", "righttrigger:a5", "back:b8", "start:b9", "leftstick:b10", "rightstick:b11", "leftx:a0", "lefty:a1~", "rightx:a2", "righty:a3"}) {
		testing.expectf(t, has_field(m, f), "%s in %s", f, m)
	}
	testing.expect(t, !strings.contains(m, "guide:"), "guide skipped")

	dir, _ := filepath.join({Engine_TempDir(), "rayzr_padsetup_test"}, context.temp_allocator)
	_ = os.remove_all(dir)
	defer os.remove_all(dir)
	path, _ := filepath.join({dir, GAMEPAD_DB_FILE}, context.temp_allocator)
	line, saved := Pad_SetupFinish(path, .Player)
	testing.expect(t, saved && line == m, "saved")
	testing.expect(t, !padSetup.active, "setup over")
	testing.expect(t, Gamepad_FileHasMapping(path, LIC_GUID), "in the file")
	rec, has := Gamepad_MappingOf(LIC_GUID)
	testing.expect(t, has && rec.source == .Player, "in use")

	// Half axes: a trigger resting at 0 is "+a"; nothing set -> nothing finished.
	testing.expect(t, Pad_SetupBeginWith(0, LIC_GUID, "Half", []f32{0, 0, 0}), "begun")
	idle(axes[:3], buttons, hats, []f32{0, 0, 0})
	for _ in 0 ..< 10 do Pad_SetupSkip() // to the left trigger
	press(axes[:3], buttons, hats, []f32{0, 0, 0}, axis = 2, v = 1)
	testing.expect(t, has_field(Pad_SetupMapping(), "lefttrigger:+a2"), Pad_SetupMapping())
	press(axes[:3], buttons, hats, []f32{0, 0, 0}, axis = 2, v = -1)
	testing.expect(t, has_field(Pad_SetupMapping(), "righttrigger:-a2"), "the other half is another input")
	Pad_SetupCancel()
	// A stick resting off centre (-0.85, as a Lic Pro Controller's does) still maps.
	off := []f32{-0.85, 0, 0}
	testing.expect(t, Pad_SetupBeginWith(0, LIC_GUID, "Off centre", off), "begun")
	idle(axes[:3], buttons, hats, off)
	for _ in 0 ..< 17 do Pad_SetupSkip() // to left x
	press(axes[:3], buttons, hats, off, axis = 0, v = 0.9)
	testing.expect(t, has_field(Pad_SetupMapping(), "leftx:a0"), Pad_SetupMapping())
	Pad_SetupCancel()
	testing.expect(t, Pad_SetupBeginWith(0, LIC_GUID, "Empty", nil), "begun")
	line, saved = Pad_SetupFinish(path)
	testing.expect(t, line == "" && !saved && !padSetup.active, "nothing set: nothing done")
}

@(test)
test_gamepad_mapping_lua :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	L := game.scriptManager.L
	code: cstring = `
		js = #Input.get_joysticks()
		btn = Input.get_joystick_button(1, 0)
		axis = Input.get_joystick_axis(1, 0)
		hat = Input.get_joystick_hat(1, 0)
		local m, src = Input.get_gamepad_mapping(1)
		map_nil = m == nil
		map_src = src
		bad = Input.set_gamepad_mapping("nonsense")
		good = Input.set_gamepad_mapping("03000000deadbeef0000000000000000,Lua Pad,a:b0,b:b1,")
		begun = Input.mapping_begin(1)
		local st = Input.mapping_state()
		st_active = st.active
		st_total = st.total
		finished = Input.mapping_finish() == nil
		open_state = Input.is_controller_setup_open()
	`
	if lua.L_dostring(L, code) != 0 {
		testing.expectf(t, false, "Lua: %s", lua.tostring(L, -1))
		lua.pop(L, 1)
		return
	}
	num :: proc(L: ^lua.State, n: cstring) -> f64 {lua.getglobal(L, n); defer lua.pop(L, 1); return f64(lua.tonumber(L, -1))}
	boolean :: proc(L: ^lua.State, n: cstring) -> bool {lua.getglobal(L, n); defer lua.pop(L, 1); return bool(lua.toboolean(L, -1))}
	// (No controllers in a test: nothing connected, nothing to set up.)
	testing.expect_value(t, num(L, "js"), 0)
	testing.expect(t, !boolean(L, "btn") && num(L, "axis") == 0 && num(L, "hat") == 0, "nothing pressed")
	testing.expect(t, boolean(L, "map_nil"), "no mapping")
	testing.expect(t, !boolean(L, "bad"), "a bad line is refused")
	testing.expect(t, boolean(L, "good"), "a line is taken")
	m, has := Gamepad_MappingOf("03000000deadbeef0000000000000000")
	testing.expect(t, has && m.source == .Script, "in use (not saved)")
	testing.expect(t, !boolean(L, "begun") && !boolean(L, "st_active") && num(L, "st_total") == f64(len(PAD_SETUP_STEPS)), "no joystick 1: no setup")
	testing.expect(t, boolean(L, "finished") && !boolean(L, "open_state"), "nothing to finish, screen closed")
}
