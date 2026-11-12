package engine

import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Players and gamepads (TODO E.4): up to four players, each with a gamepad.
// Player 1 is the keyboard + mouse and the pad `gamepadIndex` (what every
// action query without a player reads); players 2-4 read only their pads,
// with the same bindings (built-in and project actions). By default player
// N has pad N-1 - the slot the OS gave the controller, so the first pad
// plugged in is player 1's, the second player 2's - and
// Input_SetPlayerPad reassigns them (a "press A to join" screen).
//
// Hot-plug: pads are polled every frame; a change raises
// on_gamepad_connected(player, name) / on_gamepad_disconnected(player) on
// every script (Input_DispatchPadEvents).
//
// Simulated pads (tests, the runner's --input-script): a simulated pad
// replaces the real one in the same slot - connected, its name, buttons
// and axes as set.
// ============================================================================

MAX_PLAYERS :: 4
MAX_PADS :: 4

Input_Player :: struct {
	pad:    i32,                        // the gamepad (-1: none); player 1: gamepadIndex
	states: [InputAction]ActionState,   // players 2-4 (player 1: InputSystem.states)
	named:  [dynamic]ActionState,       // players 2-4, by InputSystem.named index
}

Sim_Pad :: struct {
	active:    bool, // simulated (replaces the real pad)
	connected: bool,
	name:      string, // owned
	buttons:   [rl.GamepadButton]bool,
	axes:      [rl.GamepadAxis]f32,
}

Pad_Event :: struct {
	player:    int, // 1-based
	connected: bool,
	name:      string, // temp
}

// Input_Pads: the gamepad side of the input system (InputSystem.pads).
Input_Pads :: struct {
	players:   [MAX_PLAYERS]Input_Player,
	sim:       [MAX_PADS]Sim_Pad,
	connected: [MAX_PADS]bool, // last frame's (hot-plug)
	polled:    bool,
	events:    [dynamic]Pad_Event, // this frame's
	prevDown:  [MAX_PADS][rl.GamepadButton]bool, // simulated presses (last device)
	rumble:    [MAX_PADS]Rumble_State,
}

Input_PadsInit :: proc(input: ^InputSystem) {
	for &p, i in input.pads.players do p.pad = i32(i)
}

Input_PadsDestroy :: proc(input: ^InputSystem) {
	for &p in input.pads.players {
		delete(p.named)
		p.named = nil
	}
	for &s in input.pads.sim {
		delete(s.name)
		s = {}
	}
	delete(input.pads.events)
	input.pads.events = nil
	Rumble_Shutdown(input)
	Pad_SetupCancel()
	Gamepad_MappingsShutdown()
}

// --- pads (real or simulated) -------------------------------------------------

Input_PadConnected :: proc(input: ^InputSystem, pad: i32) -> bool {
	if pad < 0 || pad >= MAX_PADS do return false
	if s := &input.pads.sim[pad]; s.active do return s.connected
	return rl.IsWindowReady() && rl.IsGamepadAvailable(pad)
}

Input_PadName :: proc(input: ^InputSystem, pad: i32) -> string {
	if !Input_PadConnected(input, pad) do return ""
	if s := &input.pads.sim[pad]; s.active do return s.name
	return string(rl.GetGamepadName(pad))
}

Input_PadButtonDown :: proc(input: ^InputSystem, pad: i32, b: rl.GamepadButton) -> bool {
	if !Input_PadConnected(input, pad) do return false
	if s := &input.pads.sim[pad]; s.active do return s.buttons[b]
	if input.padsBlocked do return false
	return rl.IsGamepadButtonDown(pad, b)
}

Input_PadAxis :: proc(input: ^InputSystem, pad: i32, a: rl.GamepadAxis) -> f32 {
	if !Input_PadConnected(input, pad) do return 0
	if s := &input.pads.sim[pad]; s.active do return s.axes[a]
	if input.padsBlocked do return 0
	return rl.GetGamepadAxisMovement(pad, a)
}

// Input_SimulatePad connects (or disconnects) a simulated pad in a slot.
Input_SimulatePad :: proc(input: ^InputSystem, pad: i32, connected: bool, name := "Simulated Gamepad") {
	if pad < 0 || pad >= MAX_PADS do return
	s := &input.pads.sim[pad]
	s.active = true
	s.connected = connected
	if connected {
		delete(s.name)
		s.name = strings.clone(name)
	} else {
		s.buttons = {}
		s.axes = {}
	}
}

Input_SimulatePadButton :: proc(input: ^InputSystem, pad: i32, b: rl.GamepadButton, down: bool) {
	if pad < 0 || pad >= MAX_PADS do return
	if !input.pads.sim[pad].active do Input_SimulatePad(input, pad, true)
	input.pads.sim[pad].buttons[b] = down
}

Input_SimulatePadAxis :: proc(input: ^InputSystem, pad: i32, a: rl.GamepadAxis, value: f32) {
	if pad < 0 || pad >= MAX_PADS do return
	if !input.pads.sim[pad].active do Input_SimulatePad(input, pad, true)
	input.pads.sim[pad].axes[a] = clamp(value, -1, 1)
}

// Input_StopSimulatingPad gives a slot back to the real pad.
Input_StopSimulatingPad :: proc(input: ^InputSystem, pad: i32) {
	if pad < 0 || pad >= MAX_PADS do return
	delete(input.pads.sim[pad].name)
	input.pads.sim[pad] = {}
}

// --- players -------------------------------------------------------------------

// Input_PlayerPad: a player's gamepad (player: 1-based; -1: none).
Input_PlayerPad :: proc(input: ^InputSystem, player: int) -> i32 {
	if player < 1 || player > MAX_PLAYERS do return -1
	if player == 1 do return input.gamepadIndex
	return input.pads.players[player - 1].pad
}

// Input_SetPlayerPad gives a player a gamepad (-1: none). A player that had
// it gets the player's old pad (a swap), so two players never share one.
Input_SetPlayerPad :: proc(input: ^InputSystem, player: int, pad: i32) {
	if player < 1 || player > MAX_PLAYERS || pad < -1 || pad >= MAX_PADS do return
	old := Input_PlayerPad(input, player)
	if pad >= 0 do for other in 1 ..= MAX_PLAYERS {
		if other != player && Input_PlayerPad(input, other) == pad do set_pad(input, other, old)
	}
	set_pad(input, player, pad)
	set_pad :: proc(input: ^InputSystem, player: int, pad: i32) {
		if player == 1 do input.gamepadIndex = pad
		input.pads.players[player - 1].pad = pad
	}
}

// Input_PlayerOfPad: the player a gamepad belongs to (0: nobody).
Input_PlayerOfPad :: proc(input: ^InputSystem, pad: i32) -> int {
	if pad < 0 do return 0
	for p in 1 ..= MAX_PLAYERS do if Input_PlayerPad(input, p) == pad do return p
	return 0
}

// Input_PlayerConnected: the player's gamepad is there (player 1 always has
// the keyboard, so this is about the pad).
Input_PlayerConnected :: proc(input: ^InputSystem, player: int) -> bool {
	return Input_PadConnected(input, Input_PlayerPad(input, player))
}

// Input_PlayerActionState: an action's state for a player (1-based; player
// 1 = the usual states).
Input_PlayerActionState :: proc(input: ^InputSystem, name: string, player: int) -> (ActionState, bool) {
	if input == nil do return {}, false
	if player <= 1 || player > MAX_PLAYERS do return Input_ActionStateByName(input, name)
	p := &input.pads.players[player - 1]
	for &n, i in input.named do if strings.equal_fold(n.name, name) {
		return p.named[i] if i < len(p.named) else {}, true
	}
	if a, ok := Builtin_ActionByName(name); ok do return p.states[a], true
	return {}, false
}

// Input_UpdatePlayers (InputSystem_Update): hot-plug events, the last
// device, players 2-4's action states, rumble timers.
Input_UpdatePlayers :: proc(input: ^InputSystem, deltaTime: f32) {
	pads := &input.pads
	input.pads.players[0].pad = input.gamepadIndex
	// Hot-plug (the first poll only records what is there). Events are this
	// frame's (their names are temp): taken after the update.
	clear(&pads.events)
	Gamepad_MappingsFrame() // (mappings for controllers that just connected: gamepad_mappings.odin)
	if padSetup.active && !padScreen.open do Pad_SetupFrame() // (a script's Input.mapping_begin)
	for pad in 0 ..< i32(MAX_PADS) {
		now := Input_PadConnected(input, pad)
		if pads.polled && now != pads.connected[pad] {
			player := Input_PlayerOfPad(input, pad)
			if player == 0 && now {
				// A pad nobody has: the first player without a connected pad.
				for p in 1 ..= MAX_PLAYERS do if !Input_PlayerConnected(input, p) {
					Input_SetPlayerPad(input, p, pad)
					player = p
					break
				}
			}
			if !now do Rumble_Stop(input, pad)
			if now && player == 1 do input.rebind.lastDevice = .Gamepad // (prompts)
			if player > 0 {
				append(&pads.events, Pad_Event{player = player, connected = now, name = strings.clone(Input_PadName(input, pad), context.temp_allocator)})
			}
		}
		pads.connected[pad] = now
	}
	pads.polled = true

	// The last device: simulated pad presses count too (Input_RebindUpdate
	// sees the real ones).
	if pad := input.gamepadIndex; pad >= 0 && pad < MAX_PADS && pads.sim[pad].active {
		for b in rl.GamepadButton {
			down := pads.sim[pad].buttons[b]
			if down && !pads.prevDown[pad][b] do input.rebind.lastDevice = .Gamepad
			pads.prevDown[pad][b] = down
		}
	}
	if input.useSimulatedInput && input.simulatedKeysDown != nil {
		for _, down in input.simulatedKeysDown do if down {input.rebind.lastDevice = .Keyboard_Mouse; break}
	}

	// Players 2-4: their pads only.
	for pi in 1 ..< MAX_PLAYERS {
		p := &pads.players[pi]
		if len(p.named) != len(input.named) do resize(&p.named, len(input.named))
		connected := Input_PadConnected(input, p.pad)
		for action in InputAction {
			m := &input.mappings[action]
			p.states[action] = step_state(input, p.states[action], m, p.pad, connected, deltaTime)
		}
		for &n, i in input.named do p.named[i] = step_state(input, p.named[i], &n.mapping, p.pad, connected, deltaTime)
	}
	Rumble_Update(input, deltaTime)

	step_state :: proc(input: ^InputSystem, prev: ActionState, m: ^ActionMapping, pad: i32, connected: bool, dt: f32) -> ActionState {
		down := false
		strength: f32 = 0
		if connected do for i in 0 ..< m.bindingCount {
			d, s := Input_EvaluateBindingFor(input, m.bindings[i], pad, false)
			if d {
				down = true
				strength = max(strength, s)
			}
		}
		return {
			pressed      = down && !prev.down,
			down         = down,
			released     = !down && prev.down,
			value        = strength if down else 0,
			durationHeld = (prev.durationHeld + dt) if down else 0,
		}
	}
}

// Input_TakePadEvents: this frame's hot-plug events (temp; once).
Input_TakePadEvents :: proc(input: ^InputSystem) -> []Pad_Event {
	if len(input.pads.events) == 0 do return nil
	out := make([]Pad_Event, len(input.pads.events), context.temp_allocator)
	copy(out, input.pads.events[:])
	clear(&input.pads.events)
	return out
}

// --- devices -------------------------------------------------------------------

// Pad_Family: the kind of controller from its name - "xbox", "playstation",
// "switch", "steamdeck" or "generic" (button prompts).
Pad_Family :: proc(name: string) -> string {
	n := strings.to_lower(name, context.temp_allocator)
	has :: proc(n: string, words: ..string) -> bool {
		for w in words do if strings.contains(n, w) do return true
		return false
	}
	switch {
	case has(n, "xbox", "xinput", "x-box", "microsoft"): return "xbox"
	case has(n, "playstation", "dualshock", "dualsense", "ps3", "ps4", "ps5", "sony", "wireless controller"): return "playstation"
	case has(n, "nintendo", "switch", "pro controller", "joy-con", "joycon"): return "switch"
	case has(n, "steam"): return "steamdeck"
	}
	return "generic"
}

// Input_PlayerDevice: what a player uses now - "keyboard" (player 1, last
// used the keyboard or mouse, or has no pad), a pad family, or "none".
Input_PlayerDevice :: proc(input: ^InputSystem, player: int) -> string {
	if player < 1 || player > MAX_PLAYERS do return "none"
	pad := Input_PlayerPad(input, player)
	connected := Input_PadConnected(input, pad)
	if player == 1 && (!connected || input.rebind.lastDevice == .Keyboard_Mouse) do return "keyboard"
	if !connected do return "none"
	return Pad_Family(Input_PadName(input, pad))
}
