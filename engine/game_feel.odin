package engine

import "core:c"
import "core:math"
import "core:strings"
import lua "lua54"
import rl "vendor:raylib"

// ============================================================================
// Game feel (#287): the "juice" helpers.
//
// - Time scale: Engine.set_time_scale(0.5) slows the whole game (physics,
//   animation, tweens, scripts' dt); set_time_scale(0.5, "enemy") only the
//   nodes tagged enemy and their children (their bodies' physics isn't
//   scaled; at 0 they're frozen). Scales multiply.
// - Hit-stop: Engine.hit_stop(0.08) freezes the game for 80 ms;
//   hit_stop(0.08, {"enemy", "player"}) only those tags. UI nodes, the
//   camera (its shake goes on) and Always nodes keep real time.
// - Slow motion: Engine.slow_motion(0.3, 1.5, "quad_out") eases down to 0.3,
//   holds, and eases back up, over 1.5 s of real time.
// - node:flash(color, seconds): the node drawn in a colour (white on a hit),
//   fading out. node:blink(seconds, rate): visible / hidden in turn.
//   node:squash(amount, seconds): a stretch that springs back.
// - Camera.kick(dx, dy): a nudge that springs back (a recoil, a hit's
//   direction), on top of the camera's shake.
//
// Durations here run in real time (a flash shows through a hit-stop).
// ============================================================================

Node_Fx :: struct {
	flashColor:   rl.Color,
	flashTime:    f32, // left
	flashDur:     f32,
	blinkTime:    f32, // left
	blinkRate:    f32, // changes per second
	blinkHidden:  bool,
	squashTime:   f32, // gone
	squashDur:    f32,
	squashAmount: f32,
}

// The effects in progress, by node (few at a time; render and transform
// look here only while it isn't empty).
nodeFx: map[^Node]Node_Fx

@(private = "file")
cameraKick: struct {
	offset, vel: [2]f32,
}

Game_Feel :: struct {
	timeScale:   f32,                // the whole game's (1)
	tagScales:   map[string]f32,     // by tag
	hitStop:     f32,                // real seconds left of a whole-game hit-stop
	hitStopTags: [dynamic]string,    // a tagged hit-stop's tags (owned)
	hitStopTagT: f32,                // ...its real seconds left
	slowmo:      struct {scale, dur, t: f32, ease: Ease, on: bool},
	rawDelta:    f32,                // this frame's real dt (nodes that keep real time)
}

// GameFeel_Scale: the whole game's time scale now.
GameFeel_Scale :: proc(game: ^Game) -> f32 {
	f := &game.feel
	s := f.timeScale if f.timeScale > 0 || f.timeScale == 0 else 1
	if f.hitStop > 0 do return 0
	if f.slowmo.on do s *= slowmo_factor(f)
	return s
}

@(private = "file")
slowmo_factor :: proc(f: ^Game_Feel) -> f32 {
	sm := f.slowmo
	if sm.dur <= 0 do return 1
	ramp := min(0.25, sm.dur * 0.25)
	k: f32 = 1
	if sm.t < ramp do k = Ease_Apply(sm.ease, sm.t / ramp)
	else if sm.t > sm.dur - ramp do k = Ease_Apply(sm.ease, max(sm.dur - sm.t, 0) / ramp)
	return 1 + (sm.scale - 1) * k
}

// GameFeel_Frame: this frame's scaled dt (GameRun) - and the effects'
// clocks, in real time.
GameFeel_Frame :: proc(game: ^Game, raw: f32) -> f32 {
	f := &game.feel
	f.rawDelta = raw
	if f.hitStop > 0 do f.hitStop = max(f.hitStop - raw, 0)
	if f.hitStopTagT > 0 {
		f.hitStopTagT -= raw
		if f.hitStopTagT <= 0 {
			for t in f.hitStopTags do delete(t, Engine_HeapAllocator())
			clear(&f.hitStopTags)
			f.hitStopTagT = 0
		}
	}
	if f.slowmo.on {
		f.slowmo.t += raw
		if f.slowmo.t >= f.slowmo.dur do f.slowmo.on = false
	}
	fx_update(raw)
	return raw * GameFeel_Scale(game)
}

// Node_TimeScale: a node's own scale from its tags (1: none set).
Node_TimeScale :: proc(game: ^Game, n: ^Node) -> f32 {
	f := &game.feel
	if (len(f.tagScales) == 0 && f.hitStopTagT <= 0) || len(n.tags) == 0 do return 1
	s: f32 = 1
	for tag in n.tags {
		if v, ok := f.tagScales[tag]; ok do s *= v
		if f.hitStopTagT > 0 do for h in f.hitStopTags do if h == tag do s = 0
	}
	return s
}

// GameFeel_KeepsRealTime: UI, cameras and Always nodes aren't slowed or stopped.
GameFeel_KeepsRealTime :: proc(n: ^Node, mode: Pause_Mode) -> bool {
	return n.isUI || n.typeId == CameraNode || mode == .Always
}

GameFeel_SetTimeScale :: proc(game: ^Game, scale: f32, tag := "") {
	f := &game.feel
	s := max(scale, 0)
	if tag == "" {
		f.timeScale = s
		return
	}
	if f.tagScales == nil do f.tagScales = make(map[string]f32, allocator = Engine_HeapAllocator())
	if s == 1 {
		if key, _, ok := map_entry_key(f.tagScales, tag); ok {
			delete_key(&f.tagScales, tag)
			delete(key, Engine_HeapAllocator())
		}
		return
	}
	if tag in f.tagScales do f.tagScales[tag] = s
	else do f.tagScales[strings.clone(tag, Engine_HeapAllocator())] = s
}

@(private = "file")
map_entry_key :: proc(m: map[string]f32, key: string) -> (string, f32, bool) {
	for k, v in m do if k == key do return k, v, true
	return "", 0, false
}

GameFeel_TimeScale :: proc(game: ^Game, tag := "") -> f32 {
	if tag == "" do return game.feel.timeScale
	return game.feel.tagScales[tag] or_else 1
}

GameFeel_HitStop :: proc(game: ^Game, seconds: f32, tags: []string = nil) {
	f := &game.feel
	if len(tags) == 0 {
		f.hitStop = max(f.hitStop, seconds)
		return
	}
	for t in f.hitStopTags do delete(t, Engine_HeapAllocator())
	clear(&f.hitStopTags)
	if f.hitStopTags.allocator.procedure == nil do f.hitStopTags = make([dynamic]string, Engine_HeapAllocator())
	for t in tags do append(&f.hitStopTags, strings.clone(t, Engine_HeapAllocator()))
	f.hitStopTagT = max(f.hitStopTagT, seconds)
}

GameFeel_SlowMotion :: proc(game: ^Game, scale, seconds: f32, ease: Ease = .Out_Quad) {
	game.feel.slowmo = {scale = max(scale, 0), dur = max(seconds, 0.01), t = 0, ease = ease, on = true}
}

GameFeel_Destroy :: proc(game: ^Game) {
	f := &game.feel
	for k in f.tagScales do delete(k, Engine_HeapAllocator())
	delete(f.tagScales)
	for t in f.hitStopTags do delete(t, Engine_HeapAllocator())
	delete(f.hitStopTags)
	f^ = {}
	delete(nodeFx)
	nodeFx = nil
	cameraKick = {}
}

// --- per-node effects -------------------------------------------------------------

@(private = "file")
fx_of :: proc(n: ^Node) -> ^Node_Fx {
	if nodeFx == nil do nodeFx = make(map[^Node]Node_Fx, allocator = Engine_HeapAllocator())
	if n not_in nodeFx do nodeFx[n] = {}
	return &nodeFx[n]
}

Node_Flash :: proc(n: ^Node, color: rl.Color = rl.WHITE, seconds: f32 = 0.1) {
	fx := fx_of(n)
	fx.flashColor, fx.flashTime, fx.flashDur = color, max(seconds, 0.01), max(seconds, 0.01)
}

Node_Blink :: proc(n: ^Node, seconds: f32 = 1, rate: f32 = 12) {
	fx := fx_of(n)
	fx.blinkTime, fx.blinkRate = max(seconds, 0), max(rate, 0.5)
	fx.blinkHidden = seconds > 0
}

Node_Squash :: proc(n: ^Node, amount: f32 = 0.25, seconds: f32 = 0.3) {
	fx := fx_of(n)
	fx.squashAmount, fx.squashDur, fx.squashTime = amount, max(seconds, 0.01), 0
}

// fx_update: the effects' time (real seconds); finished ones and those of
// freed nodes go.
@(private = "file")
fx_update :: proc(dt: f32) {
	// The camera's kick springs back.
	if cameraKick.offset != {} || cameraKick.vel != {} {
		K :: f32(220) // stiffness
		D :: f32(22)  // damping
		cameraKick.vel += (-cameraKick.offset * K - cameraKick.vel * D) * dt
		cameraKick.offset += cameraKick.vel * dt
		if abs(cameraKick.offset.x) + abs(cameraKick.offset.y) < 0.05 && abs(cameraKick.vel.x) + abs(cameraKick.vel.y) < 0.5 do cameraKick = {}
	}
	if len(nodeFx) == 0 do return
	done := make([dynamic]^Node, context.temp_allocator)
	for n, &fx in nodeFx {
		if !Node_IsAlive(n) {
			append(&done, n)
			continue
		}
		if fx.flashTime > 0 do fx.flashTime = max(fx.flashTime - dt, 0)
		if fx.blinkTime > 0 {
			before := int(fx.blinkTime * fx.blinkRate)
			fx.blinkTime = max(fx.blinkTime - dt, 0)
			if int(fx.blinkTime * fx.blinkRate) != before do fx.blinkHidden = !fx.blinkHidden
			if fx.blinkTime <= 0 do fx.blinkHidden = false
		}
		if fx.squashDur > 0 {
			fx.squashTime += dt
			if fx.squashTime >= fx.squashDur do fx.squashDur = 0
		}
		if fx.flashTime <= 0 && fx.blinkTime <= 0 && fx.squashDur <= 0 do append(&done, n)
	}
	for n in done do delete_key(&nodeFx, n)
}

// Fx_ScaleOf: a node's squash right now (its scale times this).
Fx_ScaleOf :: proc(n: ^Node) -> [2]f32 {
	fx, ok := nodeFx[n]
	if !ok || fx.squashDur <= 0 do return {1, 1}
	t := fx.squashTime / fx.squashDur
	k := fx.squashAmount * (1 - t) * (1 - t) * math.cos(t * math.PI * 2.5)
	return {1 - k * 0.5, 1 + k}
}

Camera_Kick :: proc(d: [2]f32) {
	cameraKick.vel += d * 18
}

// Camera_KickOffset: the kick's offset now (added to the camera's target).
Camera_KickOffset :: proc() -> [2]f32 {return cameraKick.offset}

// --- flash: the node drawn in a colour -------------------------------------------------

@(private = "file")
FLASH_FS :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform vec4 flashColor;
uniform float flashAmount;
out vec4 finalColor;
void main() {
	vec4 t = texture(texture0, fragTexCoord) * colDiffuse * fragColor;
	finalColor = vec4(mix(t.rgb, flashColor.rgb, flashAmount), t.a);
}`

@(private = "file")
flash: struct {
	shader:       rl.Shader,
	colorLoc, amountLoc: c.int,
}

// Fx_BeginDraw: a node's effects for its draw - false: don't draw it
// (blinked out). flashing: Fx_EndDraw after.
Fx_BeginDraw :: proc(n: ^Node, canShade: bool) -> (draw: bool, flashing: bool) {
	fx, ok := nodeFx[n]
	if !ok do return true, false
	if fx.blinkHidden do return false, false
	if fx.flashTime <= 0 || !canShade || !rl.IsWindowReady() do return true, false
	if flash.shader.id == 0 {
		flash.shader = rl.LoadShaderFromMemory(nil, Shader_Port(FLASH_FS))
		flash.colorLoc = rl.GetShaderLocation(flash.shader, "flashColor")
		flash.amountLoc = rl.GetShaderLocation(flash.shader, "flashAmount")
	}
	col := [4]f32{f32(fx.flashColor.r) / 255, f32(fx.flashColor.g) / 255, f32(fx.flashColor.b) / 255, 1}
	amount := clamp(fx.flashTime / fx.flashDur, 0, 1) * f32(fx.flashColor.a) / 255
	rl.SetShaderValue(flash.shader, flash.colorLoc, &col, .VEC4)
	rl.SetShaderValue(flash.shader, flash.amountLoc, &amount, .FLOAT)
	rl.BeginShaderMode(flash.shader)
	return true, true
}

Fx_EndDraw :: proc() {rl.EndShaderMode()}

// --- Lua -----------------------------------------------------------------------------------

@(private = "file")
feel_game :: proc(L: ^lua.State) -> ^Game {
	sm := get_script_manager(L)
	return sm.game if sm != nil else nil
}

@(private = "file")
lua_tags_arg :: proc(L: ^lua.State, idx: c.int) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	if lua.type(L, idx) == .STRING {
		append(&out, strings.clone(string(lua.tostring(L, idx)), context.temp_allocator))
	} else if lua.type(L, idx) == .TABLE {
		for i in 1 ..= c.int(lua.rawlen(L, idx)) {
			lua.rawgeti(L, idx, lua.Integer(i))
			if s := lua.tostring(L, -1); s != nil do append(&out, strings.clone(string(s), context.temp_allocator))
			lua.pop(L, 1)
		}
	}
	return out[:]
}

// Engine.set_time_scale(scale [, tag]) / Engine.get_time_scale([tag])
lua_engine_set_time_scale :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if g := feel_game(L); g != nil {
		tag := string(lua.tostring(L, 2)) if lua.type(L, 2) == .STRING else ""
		GameFeel_SetTimeScale(g, f32(lua.L_checknumber(L, 1)), tag)
	}
	return 0
}

lua_engine_get_time_scale :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	s: f32 = 1
	if g := feel_game(L); g != nil do s = GameFeel_TimeScale(g, string(lua.tostring(L, 1)) if lua.type(L, 1) == .STRING else "")
	lua.pushnumber(L, lua.Number(s))
	return 1
}

// Engine.hit_stop(seconds [, tags])
lua_engine_hit_stop :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if g := feel_game(L); g != nil do GameFeel_HitStop(g, f32(lua.L_checknumber(L, 1)), lua_tags_arg(L, 2))
	return 0
}

// Engine.slow_motion(scale, seconds [, ease])
lua_engine_slow_motion :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if g := feel_game(L); g != nil {
		ease: Ease = .Out_Quad
		if lua.type(L, 3) == .STRING do if e, ok := Ease_Parse(string(lua.tostring(L, 3))); ok do ease = e
		GameFeel_SlowMotion(g, f32(lua.L_checknumber(L, 1)), f32(lua.L_checknumber(L, 2)), ease)
	}
	return 0
}

// Camera.kick(dx, dy)
lua_camera_kick :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	x, y := arg_xy(L, 1)
	Camera_Kick({x, y})
	return 0
}

// lua_color_or: "#rrggbb[aa]" or {r, g, b[, a]} (0..1); else `def`.
@(private = "file")
lua_color_or :: proc(L: ^lua.State, idx: c.int, def: rl.Color) -> rl.Color {
	#partial switch lua.type(L, idx) {
	case .STRING:
		if col, ok := Color_FromHex(string(lua.tostring(L, idx))); ok do return col
	case .TABLE:
		ch :: proc(L: ^lua.State, idx: c.int, i: lua.Integer, d: f64) -> u8 {
			lua.rawgeti(L, idx, i)
			defer lua.pop(L, 1)
			v := f64(lua.tonumber(L, -1)) if lua.type(L, -1) == .NUMBER else d
			return u8(clamp(v, 0, 1) * 255 + 0.5)
		}
		return {ch(L, idx, 1, 1), ch(L, idx, 2, 1), ch(L, idx, 3, 1), ch(L, idx, 4, 1)}
	}
	return def
}

// node:flash([color [, seconds]]), node:blink([seconds [, rate]]), node:squash([amount [, seconds]])
@(private = "file")
lua_node_flash :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if n, ok := to_node_userdata(L, 1); ok {
		Node_Flash(n, lua_color_or(L, 2, rl.WHITE), f32(lua.L_optnumber(L, 3, 0.1)))
	}
	return 0
}

@(private = "file")
lua_node_blink :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if n, ok := to_node_userdata(L, 1); ok do Node_Blink(n, f32(lua.L_optnumber(L, 2, 1)), f32(lua.L_optnumber(L, 3, 12)))
	return 0
}

@(private = "file")
lua_node_squash :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if n, ok := to_node_userdata(L, 1); ok do Node_Squash(n, f32(lua.L_optnumber(L, 2, 0.25)), f32(lua.L_optnumber(L, 3, 0.3)))
	return 0
}

// Script_RegisterFeelNodeBindings adds flash / blink / squash to the node metatable (on the stack).
Script_RegisterFeelNodeBindings :: proc(L: ^lua.State) {
	lua.pushcfunction(L, lua_node_flash)
	lua.setfield(L, -2, "flash")
	lua.pushcfunction(L, lua_node_blink)
	lua.setfield(L, -2, "blink")
	lua.pushcfunction(L, lua_node_squash)
	lua.setfield(L, -2, "squash")
}

// Script_RegisterFeelEngineBindings adds the time functions to the Engine table (on the stack).
// Script_RegisterFeelCameraBindings adds Camera.kick (the Camera table on the stack).
Script_RegisterFeelCameraBindings :: proc(L: ^lua.State) {
	lua.pushcfunction(L, lua_camera_kick)
	lua.setfield(L, -2, "kick")
}

Script_RegisterFeelEngineBindings :: proc(L: ^lua.State) {
	lua.pushcfunction(L, lua_engine_set_time_scale)
	lua.setfield(L, -2, "set_time_scale")
	lua.pushcfunction(L, lua_engine_get_time_scale)
	lua.setfield(L, -2, "get_time_scale")
	lua.pushcfunction(L, lua_engine_hit_stop)
	lua.setfield(L, -2, "hit_stop")
	lua.pushcfunction(L, lua_engine_slow_motion)
	lua.setfield(L, -2, "slow_motion")
}
