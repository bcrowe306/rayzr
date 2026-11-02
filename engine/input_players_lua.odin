package engine

import "core:c"
import "core:strings"
import lua "lua54"

// ============================================================================
// Lua: players and gamepads (input_players.odin). Players are 1..4 (no
// player argument: player 1); gamepads are numbered 1..4 too.
//
//   Input.is_action_down("jump", 2)            -- player 2's pad
//   Input.get_vector(2)                         -- player 2's move_* actions
//   Input.vibrate(0.5, 1.0, 0.3, 2)             -- low, high motor, seconds, player
//   Input.glyph("jump")                         -- "prompts:xbox/xbox_button_a"
//   Input.device()                              -- "keyboard", "xbox", ...
//   function Game:on_gamepad_connected(player, name) ... end
// ============================================================================

// lua_player_arg: an optional player number at idx (default 1).
lua_player_arg :: proc(L: ^lua.State, idx: c.int) -> int {
	if lua.type(L, idx) != .NUMBER do return 1
	return clamp(int(lua.tointeger(L, idx)), 1, MAX_PLAYERS)
}

@(private = "file")
lua_input_vibrate :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	input := lua_input(L)
	low := f32(lua.tonumber(L, 1))
	high := f32(lua.tonumber(L, 2)) if lua.type(L, 2) == .NUMBER else low
	seconds := f32(lua.tonumber(L, 3)) if lua.type(L, 3) == .NUMBER else 0.2
	lua.pushboolean(L, b32(input != nil && Input_Vibrate(input, lua_player_arg(L, 4), low, high, seconds)))
	return 1
}

@(private = "file")
lua_input_stop_vibration :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if input := lua_input(L); input != nil do Input_StopVibration(input, lua_player_arg(L, 1))
	return 0
}

@(private = "file")
lua_input_get_vibration :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	input := lua_input(L)
	low, high: f32
	if input != nil do low, high = Input_Rumble(input, Input_PlayerPad(input, lua_player_arg(L, 1)))
	lua.pushnumber(L, lua.Number(low))
	lua.pushnumber(L, lua.Number(high))
	return 2
}

@(private = "file")
lua_input_glyph :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	input := lua_input(L)
	if input == nil || lua.type(L, 1) != .STRING {
		lua.pushnil(L)
		return 1
	}
	device := string(lua.tostring(L, 3)) if lua.type(L, 3) == .STRING else ""
	p := Input_Glyph(input, string(lua.tostring(L, 1)), lua_player_arg(L, 2), device)
	if p == "" do lua.pushnil(L)
	else do lua.pushstring(L, strings.clone_to_cstring(p, context.temp_allocator))
	return 1
}

@(private = "file")
lua_input_device :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	input := lua_input(L)
	d := Input_PlayerDevice(input, lua_player_arg(L, 1)) if input != nil else "keyboard"
	lua.pushstring(L, strings.clone_to_cstring(d, context.temp_allocator))
	return 1
}

@(private = "file")
lua_input_is_gamepad_connected :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	input := lua_input(L)
	lua.pushboolean(L, b32(input != nil && Input_PlayerConnected(input, lua_player_arg(L, 1))))
	return 1
}

@(private = "file")
lua_input_gamepad_name :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	input := lua_input(L)
	name := Input_PadName(input, Input_PlayerPad(input, lua_player_arg(L, 1))) if input != nil else ""
	if name == "" do lua.pushnil(L)
	else do lua.pushstring(L, strings.clone_to_cstring(name, context.temp_allocator))
	return 1
}

@(private = "file")
lua_input_get_player_gamepad :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	input := lua_input(L)
	pad := Input_PlayerPad(input, lua_player_arg(L, 1)) if input != nil else -1
	if pad < 0 do lua.pushnil(L)
	else do lua.pushinteger(L, lua.Integer(pad + 1))
	return 1
}

@(private = "file")
lua_input_set_player_gamepad :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	input := lua_input(L)
	if input == nil do return 0
	pad: i32 = -1
	if lua.type(L, 2) == .NUMBER do pad = i32(lua.tointeger(L, 2)) - 1
	Input_SetPlayerPad(input, lua_player_arg(L, 1), pad)
	return 0
}

// Input.gamepads(): the connected pads - {pad, name, device, player}.
@(private = "file")
lua_input_gamepads :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	input := lua_input(L)
	lua.newtable(L)
	if input == nil do return 1
	n: lua.Integer = 0
	for pad in 0 ..< i32(MAX_PADS) {
		if !Input_PadConnected(input, pad) do continue
		n += 1
		name := Input_PadName(input, pad)
		lua.createtable(L, 0, 4)
		lua.pushinteger(L, lua.Integer(pad + 1))
		lua.setfield(L, -2, "pad")
		lua.pushstring(L, strings.clone_to_cstring(name, context.temp_allocator))
		lua.setfield(L, -2, "name")
		lua.pushstring(L, strings.clone_to_cstring(Pad_Family(name), context.temp_allocator))
		lua.setfield(L, -2, "device")
		if p := Input_PlayerOfPad(input, pad); p > 0 {
			lua.pushinteger(L, lua.Integer(p))
			lua.setfield(L, -2, "player")
		}
		lua.rawseti(L, -2, n)
	}
	return 1
}

// Input.player_count(): player 1 plus every other player with a pad.
@(private = "file")
lua_input_player_count :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	input := lua_input(L)
	n := 1
	if input != nil do for p in 2 ..= MAX_PLAYERS do if Input_PlayerConnected(input, p) do n += 1
	lua.pushinteger(L, lua.Integer(n))
	return 1
}

// Script_RegisterPlayerBindings adds the player / gamepad functions to the
// Input table (on the stack).
Script_RegisterPlayerBindings :: proc(L: ^lua.State) {
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "vibrate", lua_input_vibrate)
	reg(L, "stop_vibration", lua_input_stop_vibration)
	reg(L, "get_vibration", lua_input_get_vibration)
	reg(L, "get_glyph", lua_input_glyph)
	Lua_SetDeprecated(L, lua_input_glyph, "glyph", "Input.get_glyph")
	reg(L, "get_device", lua_input_device)
	Lua_SetDeprecated(L, lua_input_device, "device", "Input.get_device")
	reg(L, "is_gamepad_connected", lua_input_is_gamepad_connected)
	reg(L, "get_gamepad_name", lua_input_gamepad_name)
	Lua_SetDeprecated(L, lua_input_gamepad_name, "gamepad_name", "Input.get_gamepad_name")
	reg(L, "get_player_gamepad", lua_input_get_player_gamepad)
	reg(L, "set_player_gamepad", lua_input_set_player_gamepad)
	reg(L, "get_gamepads", lua_input_gamepads)
	Lua_SetDeprecated(L, lua_input_gamepads, "gamepads", "Input.get_gamepads")
	reg(L, "get_player_count", lua_input_player_count)
	Lua_SetDeprecated(L, lua_input_player_count, "player_count", "Input.get_player_count")
}

// Input_DispatchPadEvents (each frame, after input): hot-plug events to
// every script - on_gamepad_connected(player, name) /
// on_gamepad_disconnected(player).
Input_DispatchPadEvents :: proc(input: ^InputSystem, mgr: ^ScriptManager) {
	events := Input_TakePadEvents(input)
	if len(events) == 0 || mgr == nil || mgr.L == nil || !mgr.isReady || mgr.suspended do return
	L := mgr.L
	for ev in events {
		method: cstring = "on_gamepad_connected" if ev.connected else "on_gamepad_disconnected"
		// (Snapshot: handlers may make or destroy scripts.)
		insts := make([]^ScriptInstance, len(mgr.instances), context.temp_allocator)
		copy(insts, mgr.instances[:])
		for inst in insts {
			alive := false
			for x in mgr.instances do if x == inst {alive = true; break}
			if !alive || !inst.isReady do continue
			lua.pushcfunction(L, lua_traceback_error_handler)
			errHandler := lua.gettop(L)
			lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef))
			lua.getfield(L, -1, method)
			if lua.type(L, -1) != .FUNCTION {
				lua.pop(L, 3)
				continue
			}
			lua.pushvalue(L, -2) // self
			lua.pushinteger(L, lua.Integer(ev.player))
			nargs: c.int = 2
			if ev.connected {
				lua.pushstring(L, strings.clone_to_cstring(ev.name, context.temp_allocator))
				nargs = 3
			}
			prev := mgr.currentInstance
			mgr.currentInstance = inst
			if lua.pcall(L, nargs, 0, errHandler) != 0 {
				Script_Problem(.Error, "[Script] Error in %s:%s(): %s", inst.modulePath, method, lua.tostring(L, -1))
				lua.pop(L, 1)
			}
			mgr.currentInstance = prev
			lua.pop(L, 2) // self, errHandler
		}
	}
}
