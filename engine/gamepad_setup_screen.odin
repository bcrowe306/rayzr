package engine

import "core:fmt"
import rl "vendor:raylib"

// ============================================================================
// The built-in Controller Setup screen (Input.open_controller_setup): a
// game opens it from its options menu, the player presses each button it
// asks for, and the mapping is saved in the player's own
// gamecontrollerdb.txt (gamepad_mappings.odin) - used at once and in every
// later run of the game.
//
// While it is open the game is paused and gets no keys or pad input. Keys:
// Tab skips a step, Backspace goes back, Left / Right picks another
// controller, Esc closes without saving. With no keyboard, the controller
// alone gets through it (a missing button: wait 5 seconds and it's skipped).
// ============================================================================

PAD_SCREEN_AUTO_SKIP :: 5.0 // seconds on one step before it's skipped
PAD_SCREEN_SAVED_FOR :: 1.5 // "Saved" shows this long

padScreen: struct {
	open:         bool,
	frozenBefore: bool,
	wanted:       i32, // the joystick asked for (-1: pick one)
	stepTime:     f32,
	lastStep:     int,
	closing:      f32, // > 0: showing the result, then closing
	result:       string, // (static)
	closed:       bool, // closed this frame (Input.is_controller_setup_open's edge)
}

// Gamepad_OpenSetupScreen: the screen, for joystick jid (0-based; -1 picks
// the first controller without a proper mapping, else the first one).
Gamepad_OpenSetupScreen :: proc(game: ^Game, jid: i32 = -1) -> bool {
	if game == nil || !JOY_RAW do return false
	if !padScreen.open {
		padScreen.frozenBefore = game.frozen
		if rl.IsWindowReady() do rl.SetExitKey(.KEY_NULL) // (Esc closes the screen, not the game)
	}
	padScreen.open = true
	padScreen.wanted = jid
	padScreen.closing = 0
	padScreen.result = ""
	Pad_SetupCancel()
	return true
}

Gamepad_CloseSetupScreen :: proc(game: ^Game) {
	if !padScreen.open do return
	Pad_SetupCancel()
	padScreen.open = false
	padScreen.closed = true
	if rl.IsWindowReady() do rl.SetExitKey(.ESCAPE) // (raylib's default: the game's)
	if game != nil {
		game.frozen = padScreen.frozenBefore
		game.input.keyboardBlocked = false
		game.input.padsBlocked = false
	}
}

// pad_screen_pick: the joystick to set up (-1: none connected).
@(private = "file")
pad_screen_pick :: proc(wanted: i32) -> i32 {
	if wanted >= 0 do return wanted if joy_present(wanted) else -1
	first: i32 = -1
	for jid in 0 ..< i32(JOY_MAX) do if joy_present(jid) {
		if first < 0 do first = jid
		src := Gamepad_SourceOf(jid)
		if src == .None || src == .Generic do return jid
	}
	return first
}

// pad_screen_cycle: the next connected joystick after jid (dir +1 / -1).
@(private = "file")
pad_screen_cycle :: proc(jid: i32, dir: i32) -> i32 {
	for k in 1 ..= i32(JOY_MAX) {
		j := ((jid + dir * k) % JOY_MAX + JOY_MAX) % JOY_MAX
		if joy_present(j) do return j
	}
	return jid
}

// ControllerSetup_Frame (the runner, each frame after the console).
ControllerSetup_Frame :: proc(game: ^Game, dt: f32) {
	padScreen.closed = false
	if !padScreen.open do return
	game.frozen = true
	game.input.keyboardBlocked = true
	game.input.padsBlocked = true
	Gamepad_MappingsFrame()
	if padScreen.closing > 0 {
		padScreen.closing -= dt
		if padScreen.closing <= 0 do Gamepad_CloseSetupScreen(game)
		return
	}
	if rl.IsKeyPressed(.ESCAPE) {
		Gamepad_CloseSetupScreen(game)
		return
	}
	if !padSetup.active {
		jid := pad_screen_pick(padScreen.wanted)
		if jid < 0 || !Pad_SetupBegin(jid) do return // ("connect a controller")
		padScreen.stepTime = 0
		padScreen.lastStep = 0
	}
	if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressed(.LEFT) {
		next := pad_screen_cycle(padSetup.jid, 1 if rl.IsKeyPressed(.RIGHT) else -1)
		padScreen.wanted = next
		Pad_SetupBegin(next)
		return
	}
	if rl.IsKeyPressed(.TAB) do Pad_SetupSkip()
	if rl.IsKeyPressed(.BACKSPACE) do Pad_SetupBack()
	if !Pad_SetupFrame() {
		padScreen.wanted = -1 // (it went away: the next one, if any)
		return
	}
	// A step nothing answers (no such button): skipped after a while.
	if padSetup.step != padScreen.lastStep {
		padScreen.lastStep = padSetup.step
		padScreen.stepTime = 0
	}
	if !padSetup.waitRelease do padScreen.stepTime += dt
	if padScreen.stepTime >= PAD_SCREEN_AUTO_SKIP {
		Pad_SetupSkip()
		padScreen.stepTime = 0
	}
	if padSetup.done {
		_, saved := Pad_SetupFinish(Gamepad_PlayerMappingsPath(), .Player)
		padScreen.result = "Saved. This controller is set up." if saved else "Set up for now (it couldn't be saved)."
		padScreen.closing = PAD_SCREEN_SAVED_FOR
	}
}

// ControllerSetup_Draw (the runner, over the game; under the console).
ControllerSetup_Draw :: proc(game: ^Game) {
	if !padScreen.open || !rl.IsWindowReady() do return
	sw, sh := f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())
	rl.DrawRectangleRec({0, 0, sw, sh}, {6, 8, 14, 220})
	font := rl.GetFontDefault()
	fs := clamp(sh / 28, 14, 30)
	w := min(sw - 32, fs * 28)
	h := min(sh - 32, fs * 15)
	x, y := (sw - w) * 0.5, (sh - h) * 0.5
	rl.DrawRectangleRec({x, y, w, h}, {22, 26, 38, 255})
	rl.DrawRectangleLinesEx({x, y, w, h}, 2, {125, 211, 252, 200})
	pad := fs
	text :: proc(font: rl.Font, s: cstring, x, y, size: f32, col: rl.Color) {rl.DrawTextEx(font, s, {x, y}, size, 1, col)}
	cx := x + pad
	cy := y + pad
	text(font, "Controller Setup", cx, cy, fs * 1.3, rl.WHITE)
	cy += fs * 2
	dim := rl.Color{150, 160, 180, 255}

	if padScreen.closing > 0 {
		text(font, fmt.ctprint(padScreen.result), cx, cy + fs, fs, {134, 239, 172, 255})
		return
	}
	if !padSetup.active {
		text(font, "Connect a controller.", cx, cy, fs, rl.WHITE)
		text(font, "Esc: close", cx, y + h - pad - fs * 0.8, fs * 0.8, dim)
		return
	}
	text(font, fmt.ctprintf("%s", padSetup.name), cx, cy, fs * 0.9, dim)
	cy += fs * 2
	n := len(PAD_SETUP_STEPS)
	text(font, fmt.ctprintf("Step %d of %d", padSetup.step + 1, n), cx, cy, fs * 0.8, dim)
	cy += fs * 1.4
	text(font, fmt.ctprint(PAD_SETUP_STEPS[padSetup.step].label), cx, cy, fs * 1.2, rl.WHITE)
	cy += fs * 2.2
	// Progress.
	bw := w - pad * 2
	rl.DrawRectangleRec({cx, cy, bw, fs * 0.4}, {48, 54, 70, 255})
	rl.DrawRectangleRec({cx, cy, bw * f32(padSetup.step) / f32(n), fs * 0.4}, {125, 211, 252, 255})
	cy += fs * 1.2
	if padSetup.message != "" {
		text(font, fmt.ctprintf("Already used for: %s", padSetup.message), cx, cy, fs * 0.8, {253, 224, 71, 255})
	} else if padSetup.waitRelease && padSetup.step > 0 {
		text(font, "Let go...", cx, cy, fs * 0.8, dim)
	} else if padScreen.stepTime > 1.5 {
		left := PAD_SCREEN_AUTO_SKIP - padScreen.stepTime
		text(font, fmt.ctprintf("No such button? It's skipped in %.0f s.", max(left, 0) + 0.5), cx, cy, fs * 0.8, dim)
	}
	text(font, "Tab: skip   Backspace: back   Left / Right: other controller   Esc: cancel", cx, y + h - pad - fs * 0.8, fs * 0.7, dim)
}
