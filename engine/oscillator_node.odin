package engine

import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:strings"
import lua "lua54"

// ============================================================================
// Oscillator: a wave that drives numeric properties of other nodes - moving
// platforms, bobbing pickups, flickering lights, pulsing effects.
//
// Each mapping names a node (a path from the oscillator, ".." its parent)
// and a property: a number ("rotation", "energy"), one component of one
// ("position.x", "color.a") or a whole vector / colour ("scale", "color").
// The wave's value (0..1) picks a point between the mapping's Min and Max;
// Value Offset is added, and a Relative mapping adds it all to the value
// the property had when the oscillator started. Phase shifts a mapping
// along the cycle (degrees), so several can move out of step.
//
// Start captures the targets' values; Stop puts them back and rewinds.
// Pause holds them where they are; Resume carries on from the same phase.
// It runs on game time: the time scale, and the game's pause (Pause Mode).
// ============================================================================

Osc_Wave :: enum u8 {
	Sine,
	Triangle,
	Square,       // high for Pulse Width of the cycle
	Saw,          // rises, drops
	Reverse_Saw,  // drops, rises
	Random,       // a new random value each cycle (held)
	Smooth_Noise, // glides to a new random value each cycle
	Curve,        // the curve drawn in the Inspector
}

Osc_Rate_Unit :: enum u8 {
	Hertz,   // cycles a second
	Seconds, // seconds a cycle
}

Osc_Apply :: enum u8 {
	Relative, // added to the property's value at Start
	Absolute, // the property is set to it
}

Osc_State :: enum u8 {
	Stopped,
	Running,
	Paused,
}

Osc_Mapping :: struct {
	target:    string,  // a node path from the oscillator ("..": its parent)
	property:  string,  // "position.x", "scale", "color.a", "shader:<param>"
	min, max:  [4]f32,  // per component (colours 0..255)
	mode:      Osc_Apply,
	phase:     f32,     // degrees along the cycle
	offset:    [4]f32,  // added to the value
	// runtime: the value at Start (restored by Stop)
	base:      [4]f32,
	hasBase:   bool,
}

OscillatorNode :: struct {
	using node: Node,
	wave:       Osc_Wave `gui:"true"`,
	rateUnit:   Osc_Rate_Unit `gui:"true"`,
	rate:       f32 `gui:"true" min:"0" max:"1000"`,       // Hertz: cycles a second; Seconds: a cycle's length
	pulseWidth: f32 `gui:"true" min:"0.01" max:"0.99"`,    // Square: the high part of the cycle
	seed:       int `gui:"true" min:"0" max:"999999"`,      // Random / Smooth Noise (0: different each run)
	autostart:  bool `gui:"true"`,
	loops:      int `gui:"true" min:"0" max:"100000"`,      // cycles before it finishes (0: forever)
	curve:      ParticleCurve,                              // Curve: the wave (t 0..1, value 0..1)
	mappings:   [dynamic]Osc_Mapping,
	onCycle:    EventSubject,
	onFinished: EventSubject,
	state:      Osc_State,
	cycles:     f64,  // cycles run since Start (the phase)
	runSeed:    u32,
	preview:    bool, // run by the editor (its values aren't saved)
}

OscillatorNode_Create :: proc(scene: ^Scene, name: string = "Oscillator", parent: ^Node = nil) -> ^OscillatorNode {
	o := CreateNode(scene.manager, OscillatorNode)
	OscillatorNode_Init(o)
	o.name = strings.clone(name, o.allocator)
	scene->addNode(o, parent)
	return o
}

OscillatorNode_Init :: proc(o: ^OscillatorNode) {
	InitializeSubject(&o.onCycle, "cycle", o)       // a cycle ended (cycles so far)
	InitializeSubject(&o.onFinished, "finished", o) // Loops cycles ran
	o.rate = 1
	o.pulseWidth = 0.5
	o.autostart = true
	o.renderable = false
	o.curve.points[0], o.curve.points[1], o.curve.points[2] = {0, 0}, {0.5, 1}, {1, 0}
	o.curve.count = 3
	o.mappings = make([dynamic]Osc_Mapping, o.allocator)
	o.update = OscillatorNode_Update
	o.ready = OscillatorNode_Ready
	o.onDestroy = OscillatorNode_Destroy
}

OscillatorNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	o := cast(^OscillatorNode)node
	DestroySubject(&o.onCycle)
	DestroySubject(&o.onFinished)
	for &m in o.mappings {
		delete(m.target, o.allocator)
		delete(m.property, o.allocator)
	}
	delete(o.mappings)
}

OscillatorNode_Ready :: proc(node: ^Node, gameContext: ^GameContext) {
	o := cast(^OscillatorNode)node
	if o.autostart && o.state == .Stopped do OscillatorNode_Start(o)
}

// OscillatorNode_AddMapping: a new mapping (Relative, 0..1); its index.
OscillatorNode_AddMapping :: proc(o: ^OscillatorNode, target, property: string, lo: [4]f32 = {}, hi: [4]f32 = {}, mode := Osc_Apply.Relative) -> int {
	append(&o.mappings, Osc_Mapping{
		target = strings.clone(target, o.allocator),
		property = strings.clone(property, o.allocator),
		min = lo,
		max = hi,
		mode = mode,
	})
	return len(o.mappings) - 1
}

OscillatorNode_RemoveMapping :: proc(o: ^OscillatorNode, index: int) {
	if index < 0 || index >= len(o.mappings) do return
	m := &o.mappings[index]
	if m.hasBase do osc_restore(o, m)
	delete(m.target, o.allocator)
	delete(m.property, o.allocator)
	ordered_remove(&o.mappings, index)
}

// OscillatorNode_Hz: cycles a second.
OscillatorNode_Hz :: proc(o: ^OscillatorNode) -> f32 {
	if o.rateUnit == .Seconds do return 1 / o.rate if o.rate > 0 else 0
	return max(o.rate, 0)
}

// OscillatorNode_Start: captures the targets and runs from the start of
// the cycle (again, when running). A finished oscillator keeps the values
// it captured before, so a Relative mapping doesn't drift.
OscillatorNode_Start :: proc(o: ^OscillatorNode) {
	for &m in o.mappings do if !m.hasBase do osc_capture(o, &m)
	o.cycles = 0
	o.runSeed = u32(o.seed) if o.seed != 0 else rand.uint32() | 1
	o.state = .Running
	OscillatorNode_Apply(o)
}

// OscillatorNode_Stop: the targets back as they were, the phase rewound.
OscillatorNode_Stop :: proc(o: ^OscillatorNode) {
	for &m in o.mappings do if m.hasBase do osc_restore(o, &m)
	o.cycles = 0
	o.state = .Stopped
}

// OscillatorNode_ReleaseMapping: a mapping's target back as it was (before
// its target or property changes); it captures again when next applied.
OscillatorNode_ReleaseMapping :: proc(o: ^OscillatorNode, index: int) {
	if index < 0 || index >= len(o.mappings) do return
	if o.mappings[index].hasBase do osc_restore(o, &o.mappings[index])
}

// Oscillator_PreviewsHold: hold = true puts the targets of the scene's
// editor-previewed oscillators back as they were (saving, an undo step);
// false applies them again. True when there were some.
Oscillator_PreviewsHold :: proc(scene: ^Scene, hold: bool) -> bool {
	if scene == nil || scene.manager == nil do return false
	any := false
	for n in scene.manager.nodes {
		if n == nil || n.typeId != OscillatorNode do continue
		o := cast(^OscillatorNode)n
		if !o.preview || o.state == .Stopped do continue
		any = true
		if !hold {
			OscillatorNode_Apply(o)
			continue
		}
		#reverse for &m in o.mappings {
			if !m.hasBase do continue
			if target := osc_target(o, &m); target != nil do Osc_WriteProperty(target, m.property, m.base)
		}
	}
	return any
}

OscillatorNode_Pause :: proc(o: ^OscillatorNode) {
	if o.state == .Running do o.state = .Paused
}

OscillatorNode_Resume :: proc(o: ^OscillatorNode) {
	if o.state == .Paused do o.state = .Running
}

OscillatorNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	o := cast(^OscillatorNode)node
	OscillatorNode_Advance(o, deltaTime, gameContext)
}

// OscillatorNode_Advance moves the phase on by dt seconds and writes the
// targets ("cycle" at each cycle, "finished" after Loops).
OscillatorNode_Advance :: proc(o: ^OscillatorNode, dt: f32, ctx: ^GameContext = nil) {
	if o.state != .Running do return
	before := o.cycles
	o.cycles += f64(dt) * f64(OscillatorNode_Hz(o))
	done := o.loops > 0 && o.cycles >= f64(o.loops)
	if done do o.cycles = f64(o.loops)
	OscillatorNode_Apply(o)
	ctx := ctx if ctx != nil else o.gameContext
	for k := int(before) + 1; k <= int(o.cycles); k += 1 {
		o.onCycle->notify(o, k, ctx)
	}
	if done {
		o.state = .Stopped // the values stay; their bases are kept for the next Start
		o.onFinished->notify(o, nil, ctx)
	}
}

// OscillatorNode_Wave: the wave's value (0..1) at a phase (cycles).
OscillatorNode_Wave :: proc(o: ^OscillatorNode, t: f64) -> f32 {
	f := f32(t - math.floor(t))
	switch o.wave {
	case .Sine:        return 0.5 + 0.5 * math.sin(f * math.TAU)
	case .Triangle:    return 2 * f if f < 0.5 else 2 - 2 * f
	case .Square:      return 1 if f < o.pulseWidth else 0
	case .Saw:         return f
	case .Reverse_Saw: return 1 - f
	case .Random:      return osc_hash(o.runSeed, u32(i64(math.floor(t))))
	case .Smooth_Noise:
		k := u32(i64(math.floor(t)))
		a, b := osc_hash(o.runSeed, k), osc_hash(o.runSeed, k + 1)
		s := f * f * (3 - 2 * f)
		return a + (b - a) * s
	case .Curve:       return ParticleCurve_Sample(&o.curve, f, 0)
	}
	return 0
}

// OscillatorNode_MappingValue: what a mapping writes at the current phase
// (its base added for Relative ones). `width`: the components it covers.
OscillatorNode_MappingValue :: proc(o: ^OscillatorNode, m: ^Osc_Mapping) -> [4]f32 {
	w := OscillatorNode_Wave(o, o.cycles + f64(m.phase) / 360)
	v := m.min + (m.max - m.min) * w + m.offset
	if m.mode == .Relative do v += m.base
	return v
}

// OscillatorNode_Apply writes every mapping's value into its target.
OscillatorNode_Apply :: proc(o: ^OscillatorNode) {
	for &m in o.mappings {
		if !m.hasBase do osc_capture(o, &m)
		if !m.hasBase do continue
		target := osc_target(o, &m)
		if target == nil do continue
		Osc_WriteProperty(target, m.property, OscillatorNode_MappingValue(o, &m))
	}
}

@(private = "file")
osc_target :: proc(o: ^OscillatorNode, m: ^Osc_Mapping) -> ^Node {
	mgr: ^NodeManager
	for cur := cast(^Node)o; cur != nil && mgr == nil; cur = cur.parent {
		if cur.gameContext != nil && cur.gameContext.scene != nil do mgr = cur.gameContext.scene.manager
	}
	if mgr == nil do return nil
	if m.target == "" || m.target == "." do return o
	return Node_ResolvePath(mgr, o, m.target)
}

@(private = "file")
osc_capture :: proc(o: ^OscillatorNode, m: ^Osc_Mapping) {
	target := osc_target(o, m)
	if target == nil do return
	v, ok := Osc_ReadProperty(target, m.property)
	if !ok do return
	m.base, m.hasBase = v, true
}

@(private = "file")
osc_restore :: proc(o: ^OscillatorNode, m: ^Osc_Mapping) {
	if target := osc_target(o, m); target != nil do Osc_WriteProperty(target, m.property, m.base)
	m.hasBase = false
}

// osc_hash: a repeatable random number in 0..1 for (seed, n).
@(private = "file")
osc_hash :: proc(seed, n: u32) -> f32 {
	x := seed * 0x9E3779B9 ~ n * 0x85EBCA6B
	x ~= x >> 16
	x *= 0x7FEB352D
	x ~= x >> 15
	x *= 0x846CA68B
	x ~= x >> 16
	return f32(x >> 8) / f32(1 << 24)
}

// ----------------------------------------------------------------------------
// Properties by name, with components: "position.x", "color.a"
// ----------------------------------------------------------------------------

// Osc_SplitComponent: "position.x" -> "position", 0. A name with no
// component (or one that is itself a property, "emitter.amount") gives -1.
Osc_SplitComponent :: proc(node: ^Node, property: string) -> (name: string, comp: int) {
	if _, found := Track_FindProperty(node, property); found do return property, -1
	dot := strings.last_index_byte(property, '.')
	if dot < 0 do return property, -1
	switch property[dot + 1:] {
	case "x", "r": return property[:dot], 0
	case "y", "g": return property[:dot], 1
	case "b":      return property[:dot], 2
	case "a":      return property[:dot], 3
	}
	return property, -1
}

// Osc_PropertyWidth: how many numbers a property (or component) holds;
// 0: not something an oscillator can drive.
Osc_PropertyWidth :: proc(node: ^Node, property: string) -> int {
	if strings.has_prefix(property, "shader:") {
		_, _, found := Material_GetParam(node, property[7:])
		return 4 if found else 0
	}
	name, comp := Osc_SplitComponent(node, property)
	p, found := Track_FindProperty(node, name)
	if !found do return 0
	width := 0
	#partial switch p.kind {
	case .Float, .Int: width = 1
	case .Vec2:        width = 2
	case .Color:       width = 4
	}
	if comp >= 0 do return 1 if comp < width else 0
	return width
}

// Osc_ReadProperty: a property's value; a component is in [0].
Osc_ReadProperty :: proc(node: ^Node, property: string) -> (v: [4]f32, ok: bool) {
	if strings.has_prefix(property, "shader:") {
		val, _, found := Material_GetParam(node, property[7:])
		return val, found
	}
	if Osc_PropertyWidth(node, property) == 0 do return {}, false
	name, comp := Osc_SplitComponent(node, property)
	p, _ := Track_FindProperty(node, name)
	all := Property_GetTrackValue(p) or_return
	if comp >= 0 do return {all[comp], 0, 0, 0}, true
	return all, true
}

// Osc_WriteProperty: sets a property (a component from [0]).
Osc_WriteProperty :: proc(node: ^Node, property: string, v: [4]f32) {
	if strings.has_prefix(property, "shader:") {
		Material_SetParam(node, property[7:], v)
		return
	}
	if Osc_PropertyWidth(node, property) == 0 do return
	name, comp := Osc_SplitComponent(node, property)
	p, _ := Track_FindProperty(node, name)
	if comp < 0 {
		Property_SetTrackValue(p, v)
		return
	}
	all, _ := Property_GetTrackValue(p)
	all[comp] = v[0]
	Property_SetTrackValue(p, all)
}

// ----------------------------------------------------------------------------
// Saved with the scene: "oscillator": {"curve": [[t, v], ...], "mappings":
// [{"target", "property", "min", "max", "mode", "phase", "offset"}]}.
// min / max / offset: a number, or a list for a vector or colour.
// ----------------------------------------------------------------------------

Oscillator_WriteJSON :: proc(w: ^Json_Writer, o: ^OscillatorNode, first: ^bool) {
	Json_Key(w, "oscillator", first)
	strings.write_string(&w.sb, "{\"curve\": [")
	for i in 0 ..< o.curve.count {
		if i > 0 do strings.write_string(&w.sb, ", ")
		Json_Vec2(w, o.curve.points[i])
	}
	strings.write_string(&w.sb, "], \"mappings\": [")
	for &m, i in o.mappings {
		if i > 0 do strings.write_string(&w.sb, ", ")
		strings.write_string(&w.sb, "{\"target\": ")
		Json_String(w, m.target)
		strings.write_string(&w.sb, ", \"property\": ")
		Json_String(w, m.property)
		strings.write_string(&w.sb, ", \"min\": ")
		osc_write_value(w, m.min)
		strings.write_string(&w.sb, ", \"max\": ")
		osc_write_value(w, m.max)
		fmt.sbprintf(&w.sb, ", \"mode\": \"%v\", \"phase\": ", m.mode)
		Json_Float(w, m.phase)
		strings.write_string(&w.sb, ", \"offset\": ")
		osc_write_value(w, m.offset)
		strings.write_byte(&w.sb, '}')
	}
	strings.write_string(&w.sb, "]}")
}

// osc_write_value: a number, or a list up to the last non-zero component.
@(private = "file")
osc_write_value :: proc(w: ^Json_Writer, v: [4]f32) {
	n := 1
	for i in 1 ..< 4 do if v[i] != 0 do n = i + 1
	if n == 1 {
		Json_Float(w, v[0])
		return
	}
	strings.write_byte(&w.sb, '[')
	for i in 0 ..< n {
		if i > 0 do strings.write_string(&w.sb, ", ")
		Json_Float(w, v[i])
	}
	strings.write_byte(&w.sb, ']')
}

Oscillator_ReadJSON :: proc(o: ^OscillatorNode, obj: json.Object) {
	if arr, ok := obj["curve"].(json.Array); ok do ParticleCurve_FromJSON(&o.curve, arr)
	list, ok := obj["mappings"].(json.Array)
	if !ok do return
	for len(o.mappings) > 0 do OscillatorNode_RemoveMapping(o, len(o.mappings) - 1)
	for v in list {
		mo, mok := v.(json.Object)
		if !mok do continue
		str :: proc(o: json.Object, key: string, def := "") -> string {return o[key].(json.String) or_else def}
		mode := Osc_Apply.Absolute if str(mo, "mode") == "Absolute" else Osc_Apply.Relative
		i := OscillatorNode_AddMapping(o, str(mo, "target", ".."), str(mo, "property"), osc_read_value(mo["min"]), osc_read_value(mo["max"]), mode)
		o.mappings[i].phase, _ = json_number(mo["phase"])
		o.mappings[i].offset = osc_read_value(mo["offset"])
	}
}

// Oscillator_ReadJSON_Text: the same from the "oscillator" object's text.
Oscillator_ReadJSON_Text :: proc(o: ^OscillatorNode, text: string) -> bool {
	v, err := json.parse_string(text, allocator = context.temp_allocator)
	obj, ok := v.(json.Object)
	if err != nil || !ok do return false
	Oscillator_ReadJSON(o, obj)
	return true
}

@(private = "file")
osc_read_value :: proc(v: json.Value) -> (out: [4]f32) {
	if arr, ok := v.(json.Array); ok {
		for x, i in arr do if i < 4 do out[i], _ = json_number(x)
		return
	}
	out[0], _ = json_number(v)
	return
}

// ----------------------------------------------------------------------------
// Lua: oscillator_start / stop / pause / resume / state, add_mapping
// ----------------------------------------------------------------------------

@(private = "file")
lua_osc :: proc(L: ^lua.State) -> ^OscillatorNode {
	n, ok := to_node_userdata(L, 1)
	if !ok || n.typeId != OscillatorNode do return nil
	return cast(^OscillatorNode)n
}

@(private = "file")
lua_osc_start :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if o := lua_osc(L); o != nil do OscillatorNode_Start(o)
	return 0
}

@(private = "file")
lua_osc_stop :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if o := lua_osc(L); o != nil do OscillatorNode_Stop(o)
	return 0
}

@(private = "file")
lua_osc_pause :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if o := lua_osc(L); o != nil do OscillatorNode_Pause(o)
	return 0
}

@(private = "file")
lua_osc_resume :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if o := lua_osc(L); o != nil do OscillatorNode_Resume(o)
	return 0
}

// oscillator_state(): "stopped", "running" or "paused"; and the phase (cycles).
@(private = "file")
lua_osc_state :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	o := lua_osc(L)
	if o == nil {
		lua.pushnil(L)
		return 1
	}
	switch o.state {
	case .Stopped: lua.pushstring(L, "stopped")
	case .Running: lua.pushstring(L, "running")
	case .Paused:  lua.pushstring(L, "paused")
	}
	lua.pushnumber(L, lua.Number(o.cycles))
	return 2
}

// oscillator_add_mapping(target, property, min, max [, absolute]): its
// number (1-based). min / max: a number, or a table {x, y} / {r, g, b, a}.
@(private = "file")
lua_osc_add_mapping :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	o := lua_osc(L)
	if o == nil {
		lua.pushnil(L)
		return 1
	}
	target := string(lua.L_checkstring(L, 2))
	property := string(lua.L_checkstring(L, 3))
	lo, hi := lua_osc_value(L, 4), lua_osc_value(L, 5)
	mode := Osc_Apply.Absolute if lua.toboolean(L, 6) else Osc_Apply.Relative
	i := OscillatorNode_AddMapping(o, target, property, lo, hi, mode)
	if o.state != .Stopped do osc_capture(o, &o.mappings[i])
	lua.pushinteger(L, lua.Integer(i + 1))
	return 1
}

@(private = "file")
lua_osc_value :: proc(L: ^lua.State, idx: c.int) -> (v: [4]f32) {
	if lua.istable(L, idx) {
		for i in 0 ..< 4 {
			lua.rawgeti(L, idx, lua.Integer(i + 1))
			v[i] = f32(lua.tonumber(L, -1))
			lua.pop(L, 1)
		}
		return
	}
	v[0] = f32(lua.L_optnumber(L, idx, 0))
	return
}

// oscillator_clear_mappings(): every mapping removed (targets restored).
@(private = "file")
lua_osc_clear :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if o := lua_osc(L); o != nil do for len(o.mappings) > 0 do OscillatorNode_RemoveMapping(o, len(o.mappings) - 1)
	return 0
}

// Script_RegisterOscillatorBindings: the node methods (on the node method table).
Script_RegisterOscillatorBindings :: proc(L: ^lua.State) {
	lua.pushcfunction(L, lua_osc_start)
	lua.setfield(L, -2, "oscillator_start")
	lua.pushcfunction(L, lua_osc_stop)
	lua.setfield(L, -2, "oscillator_stop")
	lua.pushcfunction(L, lua_osc_pause)
	lua.setfield(L, -2, "oscillator_pause")
	lua.pushcfunction(L, lua_osc_resume)
	lua.setfield(L, -2, "oscillator_resume")
	lua.pushcfunction(L, lua_osc_state)
	lua.setfield(L, -2, "oscillator_state")
	lua.pushcfunction(L, lua_osc_add_mapping)
	lua.setfield(L, -2, "oscillator_add_mapping")
	lua.pushcfunction(L, lua_osc_clear)
	lua.setfield(L, -2, "oscillator_clear_mappings")
}
