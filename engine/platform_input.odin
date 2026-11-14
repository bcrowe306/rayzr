package engine

import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Platform input: the keyboard, the mouse and window focus as the game reads
// them. Normally straight from raylib. In the editor's Game view (Play in
// Viewport, embed.odin) the game's window is hidden and never has the focus,
// so the editor sends the keys and the mouse over the editor link instead
// ("in" lines, In_ApplyEvents) and these read that.
//
// Engine code reads input through these (In_IsKeyDown, In_GetMousePosition,
// ...), never rl.* directly, so both work the same.
// ============================================================================

IN_KEYS :: 400 // (raylib's key codes are below 350)
IN_BUTTONS :: 7 // rl.MouseButton
IN_QUEUE :: 32

Platform_Input :: struct {
	remote:     bool, // the editor sends the input (the Game view)
	keyDown:    [IN_KEYS]bool,
	keyPressed: [IN_KEYS]bool, // this frame (cleared by In_BeginFrame)
	keyRelease: [IN_KEYS]bool,
	keyRepeat:  [IN_KEYS]bool,
	keyQueue:   [IN_QUEUE]rl.KeyboardKey, // GetKeyPressed's order
	keyQueueN:  int,
	keyQueueAt: int,
	charQueue:  [IN_QUEUE]rune,
	charQueueN: int,
	charQueueAt: int,
	mouse:      [2]f32, // the window point under the mouse
	mousePrev:  [2]f32,
	btnDown:    [IN_BUTTONS]bool,
	btnPressed: [IN_BUTTONS]bool,
	btnRelease: [IN_BUTTONS]bool,
	wheel:      [2]f32,
	focused:    bool,
	// rl.SetMouseOffset / SetMouseScale (the runner's letterbox), applied
	// to the editor's mouse like raylib applies them to its own.
	offset:     [2]f32,
	scale:      [2]f32,
}

platformInput := Platform_Input{scale = {1, 1}}

// In_SetRemote: from now on the input comes from the editor (or not).
In_SetRemote :: proc(on: bool) {
	platformInput = Platform_Input{scale = platformInput.scale, offset = platformInput.offset}
	platformInput.remote = on
}

In_IsRemote :: proc() -> bool {return platformInput.remote}

// In_BeginFrame clears last frame's presses and releases (the editor's
// input: raylib clears its own when it polls).
In_BeginFrame :: proc() {
	p := &platformInput
	if !p.remote do return
	p.keyPressed = {}
	p.keyRelease = {}
	p.keyRepeat = {}
	p.keyQueueN, p.keyQueueAt = 0, 0
	p.charQueueN, p.charQueueAt = 0, 0
	p.btnPressed = {}
	p.btnRelease = {}
	p.wheel = {}
	p.mousePrev = p.mouse
}

// In_ApplyEvents applies an "in" line's events, in order:
//   k<code>+ / k<code>- / k<code>r   a key down / up / repeat
//   c<codepoint>                     a typed character
//   m<x>,<y>                         the mouse moved (window points)
//   b<button>+ / b<button>-          a mouse button down / up
//   w<dx>,<dy>                       the wheel
//   f1 / f0                          the game gained / lost the focus
//   r                                everything up (the editor took the input back)
In_ApplyEvents :: proc(text: string) {
	p := &platformInput
	rest := text
	for tok in strings.fields_iterator(&rest) {
		if len(tok) < 1 do continue
		body := tok[1:]
		switch tok[0] {
		case 'k':
			if len(body) < 2 do continue
			code, ok := strconv.parse_int(body[:len(body) - 1])
			if !ok || code <= 0 || code >= IN_KEYS do continue
			switch body[len(body) - 1] {
			case '+':
				if !p.keyDown[code] {
					p.keyPressed[code] = true
					if p.keyQueueN < IN_QUEUE {
						p.keyQueue[p.keyQueueN] = rl.KeyboardKey(code)
						p.keyQueueN += 1
					}
				}
				p.keyDown[code] = true
			case '-':
				if p.keyDown[code] do p.keyRelease[code] = true
				p.keyDown[code] = false
			case 'r':
				p.keyRepeat[code] = true
			}
		case 'c':
			cp, ok := strconv.parse_int(body)
			if ok && cp > 0 && p.charQueueN < IN_QUEUE {
				p.charQueue[p.charQueueN] = rune(cp)
				p.charQueueN += 1
			}
		case 'm':
			if v, ok := in_parse_vec(body); ok do p.mouse = v
		case 'b':
			if len(body) < 2 do continue
			b, ok := strconv.parse_int(body[:len(body) - 1])
			if !ok || b < 0 || b >= IN_BUTTONS do continue
			if body[len(body) - 1] == '+' {
				if !p.btnDown[b] do p.btnPressed[b] = true
				p.btnDown[b] = true
			} else {
				if p.btnDown[b] do p.btnRelease[b] = true
				p.btnDown[b] = false
			}
		case 'w':
			if v, ok := in_parse_vec(body); ok do p.wheel += v
		case 'f':
			p.focused = body == "1"
		case 'r':
			for &d, k in p.keyDown do if d {
				p.keyRelease[k] = true
				d = false
			}
			for &d, b in p.btnDown do if d {
				p.btnRelease[b] = true
				d = false
			}
		}
	}
}

@(private = "file")
in_parse_vec :: proc(s: string) -> ([2]f32, bool) {
	i := strings.index_byte(s, ',')
	if i < 0 do return {}, false
	x, ok1 := strconv.parse_f32(s[:i])
	y, ok2 := strconv.parse_f32(s[i + 1:])
	return {x, y}, ok1 && ok2
}

@(private = "file")
in_key :: proc(k: rl.KeyboardKey) -> int {
	c := int(k)
	return c if c > 0 && c < IN_KEYS else 0
}

In_IsKeyDown :: proc(k: rl.KeyboardKey) -> bool {
	if !platformInput.remote do return rl.IsKeyDown(k)
	c := in_key(k)
	return c > 0 && platformInput.keyDown[c]
}

In_IsKeyUp :: proc(k: rl.KeyboardKey) -> bool {return !In_IsKeyDown(k)}

In_IsKeyPressed :: proc(k: rl.KeyboardKey) -> bool {
	if !platformInput.remote do return rl.IsKeyPressed(k)
	c := in_key(k)
	return c > 0 && platformInput.keyPressed[c]
}

In_IsKeyPressedRepeat :: proc(k: rl.KeyboardKey) -> bool {
	if !platformInput.remote do return rl.IsKeyPressedRepeat(k)
	c := in_key(k)
	return c > 0 && platformInput.keyRepeat[c]
}

In_IsKeyReleased :: proc(k: rl.KeyboardKey) -> bool {
	if !platformInput.remote do return rl.IsKeyReleased(k)
	c := in_key(k)
	return c > 0 && platformInput.keyRelease[c]
}

// In_GetKeyPressed: the next key pressed this frame (.KEY_NULL: none left).
In_GetKeyPressed :: proc() -> rl.KeyboardKey {
	p := &platformInput
	if !p.remote do return rl.GetKeyPressed()
	if p.keyQueueAt >= p.keyQueueN do return .KEY_NULL
	p.keyQueueAt += 1
	return p.keyQueue[p.keyQueueAt - 1]
}

// In_GetCharPressed: the next character typed this frame (0: none left).
In_GetCharPressed :: proc() -> rune {
	p := &platformInput
	if !p.remote do return rl.GetCharPressed()
	if p.charQueueAt >= p.charQueueN do return 0
	p.charQueueAt += 1
	return p.charQueue[p.charQueueAt - 1]
}

In_GetMousePosition :: proc() -> rl.Vector2 {
	p := &platformInput
	if !p.remote do return rl.GetMousePosition()
	return (p.mouse + p.offset) * p.scale
}

In_GetMouseDelta :: proc() -> rl.Vector2 {
	if !platformInput.remote do return rl.GetMouseDelta()
	return platformInput.mouse - platformInput.mousePrev
}

@(private = "file")
in_btn :: proc(b: rl.MouseButton) -> int {
	c := int(b)
	return c if c >= 0 && c < IN_BUTTONS else -1
}

In_IsMouseButtonDown :: proc(b: rl.MouseButton) -> bool {
	if !platformInput.remote do return rl.IsMouseButtonDown(b)
	c := in_btn(b)
	return c >= 0 && platformInput.btnDown[c]
}

In_IsMouseButtonUp :: proc(b: rl.MouseButton) -> bool {return !In_IsMouseButtonDown(b)}

In_IsMouseButtonPressed :: proc(b: rl.MouseButton) -> bool {
	if !platformInput.remote do return rl.IsMouseButtonPressed(b)
	c := in_btn(b)
	return c >= 0 && platformInput.btnPressed[c]
}

In_IsMouseButtonReleased :: proc(b: rl.MouseButton) -> bool {
	if !platformInput.remote do return rl.IsMouseButtonReleased(b)
	c := in_btn(b)
	return c >= 0 && platformInput.btnRelease[c]
}

// In_GetMouseWheelMove: the wheel's larger axis, like raylib's.
In_GetMouseWheelMove :: proc() -> f32 {
	if !platformInput.remote do return rl.GetMouseWheelMove()
	w := platformInput.wheel
	return w.x if abs(w.x) > abs(w.y) else w.y
}

In_GetMouseWheelMoveV :: proc() -> rl.Vector2 {
	if !platformInput.remote do return rl.GetMouseWheelMoveV()
	return platformInput.wheel
}

In_SetMouseOffset :: proc(x, y: i32) {
	platformInput.offset = {f32(x), f32(y)}
	rl.SetMouseOffset(x, y)
}

In_SetMouseScale :: proc(x, y: f32) {
	platformInput.scale = {x, y}
	rl.SetMouseScale(x, y)
}

In_IsWindowFocused :: proc() -> bool {
	if !platformInput.remote do return rl.IsWindowFocused()
	return platformInput.focused
}
