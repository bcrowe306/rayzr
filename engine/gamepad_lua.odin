package engine

import "core:c"
import "core:strings"
import lua "lua54"

// ============================================================================
// Lua: raw joysticks, controller mappings and Controller Setup (on the Input
// table; gamepad_mappings.odin, gamepad_setup.odin). Joysticks are numbered
// from 1 (the same numbers as gamepads); their buttons, axes and hats from 0,
// as mapping lines name them ("a:b0").
//
//   for _, j in ipairs(Input.get_joysticks()) do print(j.name, j.source) end
//   Input.open_controller_setup()                 -- the built-in screen
//   Input.mapping_begin(1) ... Input.mapping_state() ... Input.mapping_finish()
// ============================================================================

// lua_joystick_arg: a joystick number (1-based) at idx -> its 0-based id; -1
// (with a warning) for anything else.
@(private = "file")
lua_joystick_arg :: proc(L: ^lua.State, idx: c.int, fn: string) -> i32 {
	if lua.type(L, idx) != .NUMBER {
		Script_Problem(.Warning, "Input.%s: the joystick number (1-%d) is missing", fn, JOY_MAX)
		return -1
	}
	n := i32(lua.tointeger(L, idx))
	if n < 1 || n > JOY_MAX {
		Script_Problem(.Warning, "Input.%s: no joystick %d (they are 1-%d)", fn, n, JOY_MAX)
		return -1
	}
	return n - 1
}

@(private = "file")
cstr :: proc(s: string) -> cstring {return strings.clone_to_cstring(s, context.temp_allocator)}

// Input.get_joysticks() -> {id, name, guid, gamepad, source, axes, buttons, hats}[]
@(private = "file")
lua_input_get_joysticks :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	lua.newtable(L)
	n: lua.Integer = 0
	for jid in 0 ..< i32(JOY_MAX) {
		if !joy_present(jid) do continue
		n += 1
		lua.createtable(L, 0, 8)
		lua.pushinteger(L, lua.Integer(jid + 1)); lua.setfield(L, -2, "id")
		lua.pushstring(L, cstr(joy_name(jid))); lua.setfield(L, -2, "name")
		lua.pushstring(L, cstr(strings.to_lower(joy_guid(jid), context.temp_allocator))); lua.setfield(L, -2, "guid")
		lua.pushboolean(L, b32(joy_is_gamepad(jid))); lua.setfield(L, -2, "gamepad")
		lua.pushstring(L, cstr(PAD_MAP_SOURCE_NAMES[Gamepad_SourceOf(jid)])); lua.setfield(L, -2, "source")
		lua.pushinteger(L, lua.Integer(len(joy_axes(jid)))); lua.setfield(L, -2, "axes")
		lua.pushinteger(L, lua.Integer(len(joy_buttons(jid)))); lua.setfield(L, -2, "buttons")
		lua.pushinteger(L, lua.Integer(len(joy_hats(jid)))); lua.setfield(L, -2, "hats")
		lua.rawseti(L, -2, n)
	}
	return 1
}

// Input.get_joystick_button(id, index) -> boolean
@(private = "file")
lua_input_get_joystick_button :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	jid := lua_joystick_arg(L, 1, "get_joystick_button")
	i := int(lua.tointeger(L, 2))
	b := joy_buttons(jid) if jid >= 0 else nil
	lua.pushboolean(L, b32(i >= 0 && i < len(b) && b[i] != 0))
	return 1
}

// Input.get_joystick_axis(id, index) -> number (-1..1)
@(private = "file")
lua_input_get_joystick_axis :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	jid := lua_joystick_arg(L, 1, "get_joystick_axis")
	i := int(lua.tointeger(L, 2))
	a := joy_axes(jid) if jid >= 0 else nil
	lua.pushnumber(L, lua.Number(a[i]) if i >= 0 && i < len(a) else 0)
	return 1
}

// Input.get_joystick_hat(id, index) -> integer (1 up, 2 right, 4 down, 8 left; added)
@(private = "file")
lua_input_get_joystick_hat :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	jid := lua_joystick_arg(L, 1, "get_joystick_hat")
	i := int(lua.tointeger(L, 2))
	h := joy_hats(jid) if jid >= 0 else nil
	lua.pushinteger(L, lua.Integer(h[i]) if i >= 0 && i < len(h) else 0)
	return 1
}

// Input.get_gamepad_mapping(id) -> line?, source
@(private = "file")
lua_input_get_gamepad_mapping :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	jid := lua_joystick_arg(L, 1, "get_gamepad_mapping")
	src := Gamepad_SourceOf(jid) if jid >= 0 else .None
	m: Pad_Mapping
	has := false
	if jid >= 0 do m, has = Gamepad_MappingOf(joy_guid(jid))
	if has && src != .None && m.line != "" do lua.pushstring(L, cstr(m.line))
	else do lua.pushnil(L)
	lua.pushstring(L, cstr(PAD_MAP_SOURCE_NAMES[src]))
	return 2
}

// Input.set_gamepad_mapping(line[, save]) -> boolean
@(private = "file")
lua_input_set_gamepad_mapping :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if lua.type(L, 1) != .STRING {
		Script_Problem(.Warning, "Input.set_gamepad_mapping: expects a mapping line (\"guid,name,a:b0,...\")")
		lua.pushboolean(L, false)
		return 1
	}
	line := string(lua.tostring(L, 1))
	save := bool(lua.toboolean(L, 2))
	if _, ok := Gamepad_ParseLine(line); !ok {
		Script_Problem(.Warning, "Input.set_gamepad_mapping: %q isn't a mapping line (a 32-character GUID, a name, then fields)", line)
		lua.pushboolean(L, false)
		return 1
	}
	ok := Gamepad_ApplyMapping(line, .Player if save else .Script)
	if ok && save do ok = Gamepad_SaveMappingFile(Gamepad_PlayerMappingsPath(), line)
	lua.pushboolean(L, b32(ok))
	return 1
}

// Input.open_controller_setup([id]) -> boolean
@(private = "file")
lua_input_open_controller_setup :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	jid: i32 = -1
	if lua.type(L, 1) == .NUMBER do jid = lua_joystick_arg(L, 1, "open_controller_setup")
	ok := sm != nil && sm.game != nil && (lua.type(L, 1) != .NUMBER || jid >= 0) && Gamepad_OpenSetupScreen(sm.game, jid)
	lua.pushboolean(L, b32(ok))
	return 1
}

// Input.close_controller_setup()
@(private = "file")
lua_input_close_controller_setup :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if sm := get_script_manager(L); sm != nil do Gamepad_CloseSetupScreen(sm.game)
	return 0
}

// Input.is_controller_setup_open() -> boolean
@(private = "file")
lua_input_is_controller_setup_open :: proc "c" (L: ^lua.State) -> c.int {
	lua.pushboolean(L, b32(padScreen.open))
	return 1
}

// Input.mapping_begin(id) -> boolean
@(private = "file")
lua_input_mapping_begin :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	jid := lua_joystick_arg(L, 1, "mapping_begin")
	ok := jid >= 0 && !padScreen.open && Pad_SetupBegin(jid)
	if jid >= 0 && !joy_present(jid) do Script_Problem(.Warning, "Input.mapping_begin: no joystick %d is connected", jid + 1)
	lua.pushboolean(L, b32(ok))
	return 1
}

// Input.mapping_state() -> {active, done, step, total, field, label, kind, waiting, used_by, name, id, mapping}
@(private = "file")
lua_input_mapping_state :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	s := &padSetup
	lua.createtable(L, 0, 12)
	lua.pushboolean(L, b32(s.active)); lua.setfield(L, -2, "active")
	lua.pushboolean(L, b32(s.done)); lua.setfield(L, -2, "done")
	lua.pushinteger(L, lua.Integer(len(PAD_SETUP_STEPS))); lua.setfield(L, -2, "total")
	if !s.active do return 1
	st := PAD_SETUP_STEPS[s.step]
	lua.pushinteger(L, lua.Integer(s.step + 1)); lua.setfield(L, -2, "step")
	lua.pushstring(L, cstr(st.field)); lua.setfield(L, -2, "field")
	lua.pushstring(L, cstr(st.label)); lua.setfield(L, -2, "label")
	lua.pushstring(L, "axis" if st.kind == .Axis else "button"); lua.setfield(L, -2, "kind")
	lua.pushboolean(L, b32(s.waitRelease)); lua.setfield(L, -2, "waiting")
	if s.message != "" {
		lua.pushstring(L, cstr(s.message)); lua.setfield(L, -2, "used_by")
	}
	lua.pushstring(L, cstr(s.name)); lua.setfield(L, -2, "name")
	lua.pushinteger(L, lua.Integer(s.jid + 1)); lua.setfield(L, -2, "id")
	lua.pushstring(L, cstr(Pad_SetupMapping())); lua.setfield(L, -2, "mapping")
	return 1
}

@(private = "file")
lua_input_mapping_skip :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	Pad_SetupSkip()
	return 0
}

@(private = "file")
lua_input_mapping_back :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	Pad_SetupBack()
	return 0
}

@(private = "file")
lua_input_mapping_cancel :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !padScreen.open do Pad_SetupCancel()
	return 0
}

// Input.mapping_finish([save = true]) -> line?
@(private = "file")
lua_input_mapping_finish :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	save := lua.type(L, 1) == .NIL || lua.type(L, 1) == .NONE || bool(lua.toboolean(L, 1))
	if !padSetup.active || padScreen.open {
		lua.pushnil(L)
		return 1
	}
	line, _ := Pad_SetupFinish(Gamepad_PlayerMappingsPath() if save else "", .Player if save else .Setup)
	if line == "" do lua.pushnil(L)
	else do lua.pushstring(L, cstr(line))
	return 1
}

// Script_RegisterGamepadMappingBindings: the functions above, on the Input
// table (on the stack).
Script_RegisterGamepadMappingBindings :: proc(L: ^lua.State) {
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "get_joysticks", lua_input_get_joysticks)
	reg(L, "get_joystick_button", lua_input_get_joystick_button)
	reg(L, "get_joystick_axis", lua_input_get_joystick_axis)
	reg(L, "get_joystick_hat", lua_input_get_joystick_hat)
	reg(L, "get_gamepad_mapping", lua_input_get_gamepad_mapping)
	reg(L, "set_gamepad_mapping", lua_input_set_gamepad_mapping)
	reg(L, "open_controller_setup", lua_input_open_controller_setup)
	reg(L, "close_controller_setup", lua_input_close_controller_setup)
	reg(L, "is_controller_setup_open", lua_input_is_controller_setup_open)
	reg(L, "mapping_begin", lua_input_mapping_begin)
	reg(L, "mapping_state", lua_input_mapping_state)
	reg(L, "mapping_skip", lua_input_mapping_skip)
	reg(L, "mapping_back", lua_input_mapping_back)
	reg(L, "mapping_cancel", lua_input_mapping_cancel)
	reg(L, "mapping_finish", lua_input_mapping_finish)
}
