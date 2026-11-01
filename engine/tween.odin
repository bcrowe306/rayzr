package engine

import "base:runtime"
import "core:c"
import "core:log"
import "core:math"
import "core:strings"
import lua "lua54"

// ============================================================================
// Tweens: animate a node property to a value over time with an easing curve.
//
//   Tween.to(node, "position", {400, 200}, 0.5, "out_back")
//   Tween.to(node, "rotation", 90, 1.0, "in_out_sine", {delay = 0.2, loops = -1, yoyo = true})
//   Tween.to(node, "tintColor", {1, 0, 0, 1}, 0.2)            -- colours 0..1
//   Tween.to(node, "shader:amount", 0, 0.3, "out_quad")       -- a material parameter
//   Tween.to(node, "position", {0, 0}, 1, "linear", {on_complete = function(node) ... end})
//
// Any reflected property works (position, scale, rotation, colours, any
// numeric node property), plus "shader:<uniform>". A tween starts from the
// property's value when its delay ends; a node's tweens end with it.
// Easing curves are shared with animation track keys.
// ============================================================================

Ease :: enum u8 {
	Linear,
	In_Sine, Out_Sine, In_Out_Sine,
	In_Quad, Out_Quad, In_Out_Quad,
	In_Cubic, Out_Cubic, In_Out_Cubic,
	In_Quart, Out_Quart, In_Out_Quart,
	In_Expo, Out_Expo, In_Out_Expo,
	In_Back, Out_Back, In_Out_Back,
	In_Elastic, Out_Elastic, In_Out_Elastic,
	In_Bounce, Out_Bounce, In_Out_Bounce,
	Constant, // hold the value until the next key (animation tracks)
}

// Ease_Name: "out_quad" style names (Lua and saved files).
Ease_Name :: proc(e: Ease) -> string {
	return fmt_ease(e)
}

@(private = "file")
fmt_ease :: proc(e: Ease) -> string {
	names := [Ease]string{
		.Linear = "linear", .In_Sine = "in_sine", .Out_Sine = "out_sine", .In_Out_Sine = "in_out_sine",
		.In_Quad = "in_quad", .Out_Quad = "out_quad", .In_Out_Quad = "in_out_quad",
		.In_Cubic = "in_cubic", .Out_Cubic = "out_cubic", .In_Out_Cubic = "in_out_cubic",
		.In_Quart = "in_quart", .Out_Quart = "out_quart", .In_Out_Quart = "in_out_quart",
		.In_Expo = "in_expo", .Out_Expo = "out_expo", .In_Out_Expo = "in_out_expo",
		.In_Back = "in_back", .Out_Back = "out_back", .In_Out_Back = "in_out_back",
		.In_Elastic = "in_elastic", .Out_Elastic = "out_elastic", .In_Out_Elastic = "in_out_elastic",
		.In_Bounce = "in_bounce", .Out_Bounce = "out_bounce", .In_Out_Bounce = "in_out_bounce",
		.Constant = "constant",
	}
	return names[e]
}

Ease_Parse :: proc(s: string) -> (Ease, bool) {
	for e in Ease do if fmt_ease(e) == s do return e, true
	return .Linear, false
}

@(private = "file")
bounce_out :: proc(t: f32) -> f32 {
	n1 :: 7.5625
	d1 :: 2.75
	switch {
	case t < 1 / d1:   return n1 * t * t
	case t < 2 / d1:   u := t - 1.5 / d1; return n1 * u * u + 0.75
	case t < 2.5 / d1: u := t - 2.25 / d1; return n1 * u * u + 0.9375
	}
	u := t - 2.625 / d1
	return n1 * u * u + 0.984375
}

// Ease_Apply maps progress t (0..1) through an easing curve.
Ease_Apply :: proc(e: Ease, t_in: f32) -> f32 {
	t := clamp(t_in, 0, 1)
	PI :: math.PI
	c1 :: 1.70158
	c2 :: c1 * 1.525
	c3 :: c1 + 1
	switch e {
	case .Linear:       return t
	case .Constant:     return 0 if t < 1 else 1
	case .In_Sine:      return 1 - math.cos(t * PI / 2)
	case .Out_Sine:     return math.sin(t * PI / 2)
	case .In_Out_Sine:  return -(math.cos(PI * t) - 1) / 2
	case .In_Quad:      return t * t
	case .Out_Quad:     return 1 - (1 - t) * (1 - t)
	case .In_Out_Quad:  return 2 * t * t if t < 0.5 else 1 - math.pow(-2 * t + 2, 2) / 2
	case .In_Cubic:     return t * t * t
	case .Out_Cubic:    return 1 - math.pow(1 - t, 3)
	case .In_Out_Cubic: return 4 * t * t * t if t < 0.5 else 1 - math.pow(-2 * t + 2, 3) / 2
	case .In_Quart:     return t * t * t * t
	case .Out_Quart:    return 1 - math.pow(1 - t, 4)
	case .In_Out_Quart: return 8 * t * t * t * t if t < 0.5 else 1 - math.pow(-2 * t + 2, 4) / 2
	case .In_Expo:      return 0 if t == 0 else math.pow(2, 10 * t - 10)
	case .Out_Expo:     return 1 if t == 1 else 1 - math.pow(2, -10 * t)
	case .In_Out_Expo:
		if t == 0 || t == 1 do return t
		return math.pow(2, 20 * t - 10) / 2 if t < 0.5 else (2 - math.pow(2, -20 * t + 10)) / 2
	case .In_Back:      return c3 * t * t * t - c1 * t * t
	case .Out_Back:     return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
	case .In_Out_Back:
		if t < 0.5 do return (math.pow(2 * t, 2) * ((c2 + 1) * 2 * t - c2)) / 2
		return (math.pow(2 * t - 2, 2) * ((c2 + 1) * (t * 2 - 2) + c2) + 2) / 2
	case .In_Elastic:
		if t == 0 || t == 1 do return t
		return -math.pow(2, 10 * t - 10) * math.sin((t * 10 - 10.75) * (2 * PI / 3))
	case .Out_Elastic:
		if t == 0 || t == 1 do return t
		return math.pow(2, -10 * t) * math.sin((t * 10 - 0.75) * (2 * PI / 3)) + 1
	case .In_Out_Elastic:
		if t == 0 || t == 1 do return t
		c5 :: (2 * PI) / 4.5
		if t < 0.5 do return -(math.pow(2, 20 * t - 10) * math.sin((20 * t - 11.125) * c5)) / 2
		return (math.pow(2, -20 * t + 10) * math.sin((20 * t - 11.125) * c5)) / 2 + 1
	case .In_Bounce:     return 1 - bounce_out(1 - t)
	case .Out_Bounce:    return bounce_out(t)
	case .In_Out_Bounce: return (1 - bounce_out(1 - 2 * t)) / 2 if t < 0.5 else (1 + bounce_out(2 * t - 1)) / 2
	}
	return t
}

Tween :: struct {
	id:         int,
	node:       ^Node,
	property:   string,
	from, to:   [4]f32,
	started:    bool,
	duration:   f32,
	elapsed:    f32,
	delay:      f32,
	ease:       Ease,
	loops:      int,  // remaining extra runs (-1 = forever)
	yoyo:       bool, // every other run goes back
	reversed:   bool,
	onComplete: c.int, // Lua registry ref (0 = none)
}

Tween_State :: struct {
	tweens: [dynamic]Tween,
	nextId: int,
}

// tween_read / tween_write: the property's value as 4 floats.
@(private = "file")
tween_read :: proc(node: ^Node, property: string) -> (v: [4]f32, ok: bool) {
	if strings.has_prefix(property, "shader:") {
		val, _, found := Material_GetParam(node, property[7:])
		return val, found
	}
	p, found := Track_FindProperty(node, property)
	if !found do return {}, false
	return Property_GetTrackValue(p)
}

@(private = "file")
tween_write :: proc(node: ^Node, property: string, v: [4]f32) {
	if strings.has_prefix(property, "shader:") {
		Material_SetParam(node, property[7:], v)
		return
	}
	if p, found := Track_FindProperty(node, property); found do Property_SetTrackValue(p, v)
}

// Tween_PropertyIsColor: colour properties take 0..255 values internally.
Tween_PropertyIsColor :: proc(node: ^Node, property: string) -> bool {
	if strings.has_prefix(property, "shader:") do return false
	p, found := Track_FindProperty(node, property)
	return found && p.kind == .Color
}

// Tween_To starts a tween; returns its id (0 if the property doesn't exist).
Tween_To :: proc(ts: ^Tween_State, node: ^Node, property: string, to: [4]f32, duration: f32, ease: Ease = .Out_Quad, delay: f32 = 0, loops := 0, yoyo := false, onComplete: c.int = 0) -> int {
	// Tweens are made from Lua callbacks too: always the heap.
	context.allocator = Engine_HeapAllocator()
	if node == nil do return 0
	if _, ok := tween_read(node, property); !ok && !strings.has_prefix(property, "shader:") do return 0
	ts.nextId += 1
	append(&ts.tweens, Tween{
		id = ts.nextId, node = node, property = strings.clone(property),
		to = to, duration = max(duration, 0), delay = max(delay, 0), ease = ease,
		loops = loops, yoyo = yoyo, onComplete = onComplete,
	})
	return ts.nextId
}

@(private = "file")
tween_release :: proc(t: ^Tween, L: ^lua.State) {
	delete(t.property, Engine_HeapAllocator())
	if t.onComplete != 0 && L != nil do lua.L_unref(L, lua.REGISTRYINDEX, t.onComplete)
	t.onComplete = 0
}

Tween_Cancel :: proc(ts: ^Tween_State, id: int, L: ^lua.State = nil) -> bool {
	for &t, i in ts.tweens {
		if t.id == id {
			tween_release(&t, L)
			ordered_remove(&ts.tweens, i)
			return true
		}
	}
	return false
}

// Tween_CancelNode cancels a node's tweens (all of them, or one property's).
Tween_CancelNode :: proc(ts: ^Tween_State, node: ^Node, property := "", L: ^lua.State = nil) -> int {
	n := 0
	for i := len(ts.tweens) - 1; i >= 0; i -= 1 {
		t := &ts.tweens[i]
		if t.node == node && (property == "" || t.property == property) {
			tween_release(t, L)
			ordered_remove(&ts.tweens, i)
			n += 1
		}
	}
	return n
}

Tween_IsRunning :: proc(ts: ^Tween_State, id: int) -> bool {
	for t in ts.tweens do if t.id == id do return true
	return false
}

// Tween_Update advances every tween; finished ones call their on_complete.
Tween_Update :: proc(ts: ^Tween_State, dt: f32, sm: ^ScriptManager) {
	if ts == nil || len(ts.tweens) == 0 do return
	L := sm.L if sm != nil else nil
	completed := make([dynamic]Tween, context.temp_allocator)
	for i := 0; i < len(ts.tweens); {
		t := &ts.tweens[i]
		if !Node_IsAlive(t.node) {
			tween_release(t, L)
			ordered_remove(&ts.tweens, i)
			continue
		}
		if t.node.pausedNow {
			i += 1 // paused with its node
			continue
		}
		if t.delay > 0 {
			t.delay -= dt
			if t.delay > 0 {
				i += 1
				continue
			}
		}
		if !t.started {
			t.from, _ = tween_read(t.node, t.property)
			t.started = true
		}
		t.elapsed += dt
		p := t.elapsed / t.duration if t.duration > 0 else 1
		k := Ease_Apply(t.ease, p)
		a, b := t.from, t.to
		if t.reversed do a, b = b, a
		tween_write(t.node, t.property, a + (b - a) * k)
		if p < 1 {
			i += 1
			continue
		}
		if t.loops != 0 {
			if t.loops > 0 do t.loops -= 1
			t.elapsed = 0
			if t.yoyo do t.reversed = !t.reversed
			i += 1
			continue
		}
		append(&completed, t^)
		ordered_remove(&ts.tweens, i)
	}
	// Callbacks after the list is consistent (they may start new tweens).
	for &t in completed {
		if t.onComplete != 0 && L != nil && Node_IsAlive(t.node) {
			lua.pushcfunction(L, lua_traceback_error_handler)
			eh := lua.gettop(L)
			lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(t.onComplete))
			push_node_userdata(L, t.node)
			if lua.pcall(L, 1, 0, eh) != 0 {
				log.errorf("[Tween] on_complete: %s", lua.tostring(L, -1))
				lua.pop(L, 1)
			}
			lua.pop(L, 1)
		}
		tween_release(&t, L)
	}
}

Tween_Destroy :: proc(ts: ^Tween_State, L: ^lua.State = nil) {
	for &t in ts.tweens do tween_release(&t, L)
	delete(ts.tweens)
	ts.tweens = nil
}

// --- Lua: the Tween module ----------------------------------------------------------

@(private = "file")
tween_state :: proc(L: ^lua.State) -> (^Tween_State, ^ScriptManager) {
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil do return nil, sm
	return &sm.game.tweens, sm
}

// Tween.to(node, property, value, duration [, ease [, opts]]) -> id
@(private = "file")
lua_tween_to :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ts, _ := tween_state(L)
	node, ok := to_node_userdata(L, 1)
	if ts == nil || !ok || lua.type(L, 2) != .STRING {
		lua.pushinteger(L, 0)
		return 1
	}
	property := strings.clone(string(lua.tostring(L, 2)), context.temp_allocator)
	v: [4]f32
	if lua.type(L, 3) == .TABLE {
		lua.getfield(L, 3, "x")
		isVec := lua.type(L, -1) == .NUMBER
		lua.pop(L, 1)
		if isVec {
			// A Vec2 (x / y fields; v[1] only through __index, which rawgeti skips).
			v.x, v.y = arg_xy(L, 3)
		} else {
			for i in 0 ..< 4 {
				lua.rawgeti(L, 3, lua.Integer(i + 1))
				v[i] = f32(lua.tonumber(L, -1))
				lua.pop(L, 1)
			}
		}
	} else {
		v[0] = f32(lua.tonumber(L, 3))
	}
	if Tween_PropertyIsColor(node, property) {
		if lua.type(L, 3) == .TABLE {
			lua.rawgeti(L, 3, 4)
			hasAlpha := lua.type(L, -1) == .NUMBER
			lua.pop(L, 1)
			if !hasAlpha do v[3] = 1
		}
		v *= 255
	}
	duration := f32(lua.tonumber(L, 4))
	ease := Ease.Out_Quad
	if lua.type(L, 5) == .STRING {
		e, found := Ease_Parse(string(lua.tostring(L, 5)))
		if !found {
			Script_Problem(.Warning, "Tween.to: unknown ease '%s' (no tween)", string(lua.tostring(L, 5)))
			lua.pushinteger(L, 0)
			return 1
		}
		ease = e
	}
	delay: f32 = 0
	loops := 0
	yoyo := false
	ref: c.int = 0
	if lua.type(L, 6) == .TABLE {
		lua.getfield(L, 6, "delay")
		if lua.type(L, -1) == .NUMBER do delay = f32(lua.tonumber(L, -1))
		lua.pop(L, 1)
		lua.getfield(L, 6, "loops")
		if lua.type(L, -1) == .NUMBER do loops = int(lua.tointeger(L, -1))
		lua.pop(L, 1)
		lua.getfield(L, 6, "yoyo")
		yoyo = bool(lua.toboolean(L, -1))
		lua.pop(L, 1)
		lua.getfield(L, 6, "on_complete")
		if lua.type(L, -1) == .FUNCTION do ref = lua.L_ref(L, lua.REGISTRYINDEX)
		else do lua.pop(L, 1)
	}
	id := Tween_To(ts, node, property, v, duration, ease, delay, loops, yoyo, ref)
	if id == 0 do Script_Problem(.Warning, "Tween.to: %s has no animatable property '%s' (no tween)", node.name, property)
	if id == 0 && ref != 0 do lua.L_unref(L, lua.REGISTRYINDEX, ref)
	lua.pushinteger(L, lua.Integer(id))
	return 1
}

@(private = "file")
lua_tween_cancel :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ts, sm := tween_state(L)
	if ts != nil do lua.pushboolean(L, b32(Tween_Cancel(ts, int(lua.tointeger(L, 1)), sm.L)))
	else do lua.pushboolean(L, false)
	return 1
}

// Tween.cancel_all(node [, property]) -> count
@(private = "file")
lua_tween_cancel_all :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ts, sm := tween_state(L)
	node, ok := to_node_userdata(L, 1)
	n := 0
	if ts != nil && ok {
		prop := string(lua.tostring(L, 2)) if lua.type(L, 2) == .STRING else ""
		n = Tween_CancelNode(ts, node, prop, sm.L)
	}
	lua.pushinteger(L, lua.Integer(n))
	return 1
}

@(private = "file")
lua_tween_is_running :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ts, _ := tween_state(L)
	lua.pushboolean(L, b32(ts != nil && Tween_IsRunning(ts, int(lua.tointeger(L, 1)))))
	return 1
}

// Tween.ease(name, t) -> eased t (for scripts' own animation).
@(private = "file")
lua_tween_ease :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	e, found := Ease_Parse(string(lua.tostring(L, 1)) if lua.type(L, 1) == .STRING else "linear")
	if !found {
		Script_Problem(.Warning, "Tween.ease: unknown ease '%s'", string(lua.tostring(L, 1)))
		lua.pushnil(L)
		return 1
	}
	lua.pushnumber(L, lua.Number(Ease_Apply(e, f32(lua.tonumber(L, 2)))))
	return 1
}

// Script_RegisterTweenModule creates the global Tween table.
Script_RegisterTweenModule :: proc(L: ^lua.State) {
	lua.newtable(L)
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "to", lua_tween_to)
	reg(L, "cancel", lua_tween_cancel)
	reg(L, "cancel_all", lua_tween_cancel_all)
	reg(L, "is_running", lua_tween_is_running)
	reg(L, "ease", lua_tween_ease)
	lua.setglobal(L, "Tween")
}
