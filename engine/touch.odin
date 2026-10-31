package engine

import "core:c"
import "core:math"
import lua "lua54"
import rl "vendor:raylib"

// ============================================================================
// Touch input (#276): the fingers on a touch screen - the web export on
// phones and tablets (desktop windows get none: the OS turns touches into
// the mouse there).
//
// - Points: each finger's id and position (game units, like the mouse),
//   pressed / released on the frame it went down / up.
// - Touch as mouse (project setting, on by default): the first finger is
//   the left mouse button - taps click buttons, drags drag sliders, games
//   reading the mouse work as they are.
// - On-screen controls (touch_controls.odin): a finger that lands on a
//   Touch Joystick or Touch Button is that control's - it presses the
//   control's input actions and isn't the mouse or a gesture.
// - Gestures, from the other fingers: tap, double tap, long press, swipe,
//   and pinch / two-finger drag. Lua: Input.get_tap() ... and on_tap(x, y)
//   ... on scripts.
//
// Tests drive simulated fingers (Input_SimulateTouch; the runner's
// --input-script "touch1 x y down|move|up|tap").
// ============================================================================

TOUCH_MAX :: 10

TOUCH_TAP_SLOP :: f32(14)    // a tap / long press moves less than this (game px)
TOUCH_TAP_TIME :: f32(0.3)   // a tap is shorter (s)
TOUCH_DOUBLE_TIME :: f32(0.35) // between the taps of a double tap (s)
TOUCH_DOUBLE_DIST :: f32(40)
TOUCH_LONG_TIME :: f32(0.5)  // a long press holds this long (s)
TOUCH_SWIPE_DIST :: f32(60)  // a swipe goes at least this far...
TOUCH_SWIPE_TIME :: f32(0.6) // ...in at most this long

Touch_Point :: struct {
	id:        i32,
	pos:       [2]f32, // now (game units)
	start:     [2]f32, // where it went down
	startTime: f32,
	down, pressed, released: bool, // (released: up this frame, then it goes)
	moved:     bool,  // went past TOUCH_TAP_SLOP
	multi:     bool,  // was part of a pinch
	longDone:  bool,  // its long press fired
	claim:     ^Node, // the on-screen control it belongs to (nil: free)
}

Touch_Gestures :: struct {
	tap, doubleTap, longPress: Maybe([2]f32), // this frame, where
	swipe:      Maybe([3]f32),                // this frame: direction x, y (unit) and speed (px/s)
	pinchScale: f32,                          // this frame's zoom (1: none)
	pinchPan:   [2]f32,                       // this frame's two-finger move
	pinching:   bool,
}

Touch_Sim :: struct {
	id:   i32,
	pos:  [2]f32,
	down: bool,
}

Input_Touch :: struct {
	points:      [TOUCH_MAX]Touch_Point,
	count:       int,
	gestures:    Touch_Gestures,
	lastTap:     [2]f32,
	lastTapTime: f32,
	clock:       f32,
	everTouched: bool, // a finger touched the screen (on-screen controls show)
	asMouse:     bool, // the first free finger is the mouse (project setting)
	// Simulated fingers (tests, the runner's input scripts): used instead of
	// the screen once one is set.
	sim:         [TOUCH_MAX]Touch_Sim,
	simCount:    int,
	useSim:      bool,
	// The on-screen controls' input actions this frame: name -> strength
	// (keys: the controls' own strings, for this frame).
	actions:     map[string]f32,
	// The pinch's two fingers last frame.
	pinchIds:    [2]i32,
	prevA, prevB: [2]f32,
}

// touch_mouse_game: the game whose touch mouse the input bindings read (the
// running one).
touch_mouse_game: ^Game

// Touch_Mouse: the finger acting as the mouse (Game.touchMouse).
Touch_Mouse :: struct {
	active:                   bool,
	pos:                      [2]f32,
	down, pressed, released:  bool,
}

// Input_SimulateTouch puts a simulated finger down (or moves it), or lifts it.
Input_SimulateTouch :: proc(input: ^InputSystem, id: i32, pos: [2]f32, down: bool) {
	t := &input.touch
	t.useSim = true
	for i in 0 ..< t.simCount do if t.sim[i].id == id {
		t.sim[i] = {id, pos, down}
		return
	}
	if t.simCount < TOUCH_MAX {
		t.sim[t.simCount] = {id, pos, down}
		t.simCount += 1
	}
}

// touch_raw: the fingers on the screen now (id, game position).
@(private = "file")
touch_raw :: proc(game: ^Game) -> (out: [TOUCH_MAX]Touch_Sim, n: int) {
	t := &game.input.touch
	if t.useSim {
		for i in 0 ..< t.simCount do if t.sim[i].down {
			out[n] = t.sim[i]
			n += 1
		}
		return
	}
	when ODIN_OS == .JS || ODIN_PLATFORM_SUBTARGET == .Android {
		if !rl.IsWindowReady() do return
		for i in 0 ..< min(int(rl.GetTouchPointCount()), TOUCH_MAX) {
			p := rl.GetTouchPosition(i32(i))
			out[n] = {rl.GetTouchPointId(i32(i)), Touch_ScreenToGame(game, p), true}
			n += 1
		}
	}
	return
}

// Touch_ScreenToGame: a window pixel in game units (as the mouse reads).
Touch_ScreenToGame :: proc(game: ^Game, p: [2]f32) -> [2]f32 {
	m := game.screenToGame
	if m.z == 0 || m.w == 0 do return p
	return {(p.x + m.x) * m.z, (p.y + m.y) * m.w}
}

// Touch_Update: this frame's fingers, claims, gestures and the touch
// mouse (GameRun, before the input actions are evaluated).
Touch_Update :: proc(game: ^Game, dt: f32) {
	t := &game.input.touch
	t.clock += dt
	t.gestures = {pinchScale = 1}
	raw, rn := touch_raw(game)

	// Lifted last frame: gone. Then this frame's: moved, new, lifted.
	k := 0
	for i in 0 ..< t.count do if !t.points[i].released {
		t.points[k] = t.points[i]
		t.points[k].pressed = false
		k += 1
	}
	t.count = k
	for i in 0 ..< t.count {
		p := &t.points[i]
		found := false
		for r in raw[:rn] do if r.id == p.id {
			found = true
			p.pos = r.pos
			d := p.pos - p.start
			if d.x * d.x + d.y * d.y > TOUCH_TAP_SLOP * TOUCH_TAP_SLOP do p.moved = true
		}
		if !found {
			p.down = false
			p.released = true
		}
	}
	for r in raw[:rn] {
		known := false
		for i in 0 ..< t.count do if t.points[i].id == r.id do known = true
		if known || t.count >= TOUCH_MAX do continue
		t.points[t.count] = {id = r.id, pos = r.pos, start = r.pos, startTime = t.clock, down = true, pressed = true}
		t.points[t.count].claim = TouchControl_Claim(game, r.pos)
		t.count += 1
		t.everTouched = true
	}
	TouchControls_Update(game) // (the controls' actions from their fingers)
	touch_gestures(t)
	touch_mouse(game)
}

@(private = "file")
touch_gestures :: proc(t: ^Input_Touch) {
	// Pinch / two-finger drag: the first two free fingers down this frame and the last.
	a, b := -1, -1
	for i in 0 ..< t.count {
		p := &t.points[i]
		if p.claim != nil || !p.down || p.pressed do continue
		if a < 0 do a = i
		else if b < 0 do b = i
	}
	if a >= 0 && b >= 0 {
		pa, pb := &t.points[a], &t.points[b]
		now := pb.pos - pa.pos
		was := t.prevB - t.prevA
		if t.pinchIds == {pa.id, pb.id} {
			dn := math.sqrt(now.x * now.x + now.y * now.y)
			dw := math.sqrt(was.x * was.x + was.y * was.y)
			if dw > 1 do t.gestures.pinchScale = dn / dw
			t.gestures.pinchPan = (pa.pos + pb.pos) * 0.5 - (t.prevA + t.prevB) * 0.5
		}
		t.gestures.pinching = true
		pa.multi, pb.multi = true, true
		t.pinchIds, t.prevA, t.prevB = {pa.id, pb.id}, pa.pos, pb.pos
	} else {
		t.pinchIds = {-1, -1}
	}
	for i in 0 ..< t.count {
		p := &t.points[i]
		if p.claim != nil || p.multi do continue
		held := t.clock - p.startTime
		if p.down && !p.moved && !p.longDone && held >= TOUCH_LONG_TIME {
			p.longDone = true
			t.gestures.longPress = p.pos
		}
		if !p.released do continue
		d := p.pos - p.start
		dist := math.sqrt(d.x * d.x + d.y * d.y)
		if !p.moved && !p.longDone && held <= TOUCH_TAP_TIME {
			t.gestures.tap = p.pos
			dd := p.pos - t.lastTap
			if t.clock - t.lastTapTime <= TOUCH_DOUBLE_TIME && dd.x * dd.x + dd.y * dd.y <= TOUCH_DOUBLE_DIST * TOUCH_DOUBLE_DIST {
				t.gestures.doubleTap = p.pos
				t.lastTapTime = -1e9 // (a third tap starts again)
			} else {
				t.lastTap, t.lastTapTime = p.pos, t.clock
			}
		} else if dist >= TOUCH_SWIPE_DIST && held <= TOUCH_SWIPE_TIME {
			t.gestures.swipe = [3]f32{d.x / dist, d.y / dist, dist / max(held, 0.001)}
		}
	}
}

// touch_mouse: the first free finger is the left mouse button.
@(private = "file")
touch_mouse :: proc(game: ^Game) {
	t := &game.input.touch
	m := &game.touchMouse
	m.pressed, m.released = false, false
	if !t.asMouse {
		m^ = {}
		return
	}
	for i in 0 ..< t.count {
		p := &t.points[i]
		if p.claim != nil do continue
		m.active = true
		m.pos = p.pos
		m.pressed = p.pressed
		m.released = p.released
		m.down = p.down
		return
	}
	// No finger: the real mouse again (a released finger was reported above).
	m.active = false
	m.down = false
}

// Game_Pointer: the mouse when something stands in for it - the test mouse
// (the runner's input scripts, tests), else a finger (touch as mouse);
// ok = false: read the real mouse.
Game_Pointer :: proc(game: ^Game) -> (p: Touch_Mouse, ok: bool) {
	if game == nil do return
	if game.uiTestInputEnabled {
		return {true, game.uiTestMousePos, game.uiTestMouseDown, game.uiTestMousePressed, game.uiTestMouseReleased}, true
	}
	if game.touchMouse.active || game.touchMouse.released do return game.touchMouse, true
	return
}

// Input_TouchActions: the on-screen controls' strength for an action (0: none).
Input_TouchAction :: proc(input: ^InputSystem, name: string) -> f32 {
	if len(input.touch.actions) == 0 do return 0
	return input.touch.actions[name] or_else 0
}

Input_TouchDestroy :: proc(input: ^InputSystem) {
	delete(input.touch.actions)
	input.touch.actions = nil
}

// --- Lua: Input.get_touches ... and on_tap ... ---------------------------------------------

// Input.get_touches() -> {{id=, x=, y=, pressed=, released=}, ...}  (free fingers and claimed ones)
lua_input_get_touches :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	lua.createtable(L, TOUCH_MAX, 0)
	if sm == nil || sm.game == nil do return 1
	t := &sm.game.input.touch
	for i in 0 ..< t.count {
		p := t.points[i]
		lua.createtable(L, 0, 6)
		lua.pushinteger(L, lua.Integer(p.id)); lua.setfield(L, -2, "id")
		lua.pushnumber(L, lua.Number(p.pos.x)); lua.setfield(L, -2, "x")
		lua.pushnumber(L, lua.Number(p.pos.y)); lua.setfield(L, -2, "y")
		lua.pushboolean(L, b32(p.pressed)); lua.setfield(L, -2, "pressed")
		lua.pushboolean(L, b32(p.released)); lua.setfield(L, -2, "released")
		lua.pushboolean(L, b32(p.claim != nil)); lua.setfield(L, -2, "control")
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

@(private = "file")
touch_of :: proc(L: ^lua.State) -> ^Input_Touch {
	sm := get_script_manager(L)
	return &sm.game.input.touch if sm != nil && sm.game != nil else nil
}

@(private = "file")
push_point :: proc(L: ^lua.State, p: Maybe([2]f32)) -> c.int {
	if v, ok := p.?; ok {
		lua.pushnumber(L, lua.Number(v.x))
		lua.pushnumber(L, lua.Number(v.y))
		return 2
	}
	lua.pushnil(L)
	return 1
}

lua_input_get_tap :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	t := touch_of(L)
	return push_point(L, t.gestures.tap if t != nil else nil)
}

lua_input_get_double_tap :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	t := touch_of(L)
	return push_point(L, t.gestures.doubleTap if t != nil else nil)
}

lua_input_get_long_press :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	t := touch_of(L)
	return push_point(L, t.gestures.longPress if t != nil else nil)
}

lua_input_get_swipe :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	t := touch_of(L)
	s: [3]f32
	ok := false
	if t != nil do s, ok = t.gestures.swipe.?
	if !ok {
		lua.pushnil(L)
		return 1
	}
	lua.pushnumber(L, lua.Number(s.x))
	lua.pushnumber(L, lua.Number(s.y))
	lua.pushnumber(L, lua.Number(s.z))
	return 3
}

lua_input_get_pinch :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	t := touch_of(L)
	g := t.gestures if t != nil else Touch_Gestures{pinchScale = 1}
	lua.pushnumber(L, lua.Number(g.pinchScale))
	lua.pushnumber(L, lua.Number(g.pinchPan.x))
	lua.pushnumber(L, lua.Number(g.pinchPan.y))
	lua.pushboolean(L, b32(g.pinching))
	return 4
}

lua_input_is_touch_device :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	t := touch_of(L)
	lua.pushboolean(L, b32(t != nil && t.everTouched))
	return 1
}

// Script_RegisterTouchBindings adds the touch functions to the Input table (on the stack).
Script_RegisterTouchBindings :: proc(L: ^lua.State) {
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "get_touches", lua_input_get_touches)
	reg(L, "get_tap", lua_input_get_tap)
	reg(L, "get_double_tap", lua_input_get_double_tap)
	reg(L, "get_long_press", lua_input_get_long_press)
	reg(L, "get_swipe", lua_input_get_swipe)
	reg(L, "get_pinch", lua_input_get_pinch)
	reg(L, "is_touch_device", lua_input_is_touch_device)
}

// Input_DispatchTouchEvents calls the gestures' methods on every script:
// on_tap(x, y), on_double_tap(x, y), on_long_press(x, y),
// on_swipe(dx, dy, speed), on_pinch(scale, dx, dy).
Input_DispatchTouchEvents :: proc(input: ^InputSystem, mgr: ^ScriptManager) {
	g := input.touch.gestures
	if mgr == nil || mgr.L == nil || !mgr.isReady || mgr.suspended do return
	if g.tap == nil && g.doubleTap == nil && g.longPress == nil && g.swipe == nil && !g.pinching do return
	call :: proc(mgr: ^ScriptManager, method: cstring, args: []f32) {
		L := mgr.L
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
			for a in args do lua.pushnumber(L, lua.Number(a))
			prev := mgr.currentInstance
			mgr.currentInstance = inst
			if lua.pcall(L, c.int(len(args) + 1), 0, errHandler) != 0 {
				Script_Problem(.Error, "[Script] Error in %s:%s(): %s", inst.modulePath, method, lua.tostring(L, -1))
				lua.pop(L, 1)
			}
			mgr.currentInstance = prev
			lua.pop(L, 2)
		}
	}
	if p, ok := g.tap.?; ok do call(mgr, "on_tap", {p.x, p.y})
	if p, ok := g.doubleTap.?; ok do call(mgr, "on_double_tap", {p.x, p.y})
	if p, ok := g.longPress.?; ok do call(mgr, "on_long_press", {p.x, p.y})
	if s, ok := g.swipe.?; ok do call(mgr, "on_swipe", {s.x, s.y, s.z})
	if g.pinching && (g.pinchScale != 1 || g.pinchPan != {}) do call(mgr, "on_pinch", {g.pinchScale, g.pinchPan.x, g.pinchPan.y})
}
