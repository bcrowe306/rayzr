package engine

import "core:c"
import "core:fmt"
import "core:strings"
import lua "lua54"
import rl "vendor:raylib"

// ============================================================================
// Lighting's Lua API (lighting.odin, lighting_nodes.odin; documented in
// engine/definitions/engine_api.lua):
//
//   light:light_get_<setting>() / light:light_set_<setting>(value)   every Light setting
//   light:light_fade(energy, seconds [, on_done])                    Tween underneath
//   light:light_apply_preset(name)                                   Torch, Lamp, Flashlight, Sun, Neon
//   env:env_get_<setting>() / env:env_set_<setting>(value)           every Environment setting
//   env:env_fade_ambient(color, seconds [, on_done])
//   occluder:occluder_get_layers() / occluder:occluder_set_layers(layers)
//   node:set_emission(color [, strength]) / node:get_emission() -> color, strength
//   node:set_ignore_lighting(on) / node:get_ignore_lighting()
//   node:set_lit_layers(layers) / node:get_lit_layers()
//   Lighting.brightness_at(x, y | pos [, layers]) -> brightness, color
//   Lighting.get_lights() / Lighting.set_enabled(on) / Lighting.is_enabled()
//   Scene.get_environment() / Scene.create_light(preset [, parent])
//
// Layers are a list of light layer names ({"World", "Player"}), one name,
// "LayerN", or a number mask (bit 0 = Layer1); getters return the names.
// ============================================================================

// Each setting a getter / setter is made for: the Lua name and the
// Inspector's.
@(private = "file")
Lt_Setting :: struct {
	lua, prop: string,
}

@(private = "file")
LIGHT_SETTINGS := [?]Lt_Setting{
	{"kind", "kind"}, {"color", "color"}, {"energy", "energy"}, {"radius", "radius"}, {"falloff", "falloff"},
	{"spread", "spread"}, {"texture", "texture"}, {"layers", "layers"}, {"shadows", "shadows"},
	{"softness", "softness"}, {"shadow_strength", "shadowStrength"}, {"ignore_parent_bodies", "ignoreParentBodies"},
	{"height", "height"}, {"elevation", "elevation"}, {"shadow_length", "shadowLength"},
	{"flicker", "flicker"}, {"flicker_speed", "flickerSpeed"}, {"pulse", "pulse"}, {"pulse_speed", "pulseSpeed"},
}

@(private = "file")
ENV_SETTINGS := [?]Lt_Setting{
	{"ambient", "ambient"}, {"overbright", "overbright"}, {"bloom", "bloom"}, {"bloom_threshold", "bloomThreshold"},
	{"bloom_strength", "bloomStrength"}, {"bloom_radius", "bloomRadius"}, {"half_resolution", "halfResolution"},
}

// The 4 light methods from before keep their own bindings (script_bindings.odin).
@(private = "file")
LIGHT_KEPT := [?]string{"light_set_color", "light_set_energy", "light_get_energy", "light_set_radius"}

@(private = "file")
lt_up :: #force_inline proc "contextless" (i: c.int) -> c.int {return lua.REGISTRYINDEX - i}

// Lighting_RegisterNodeMethods adds the lighting methods to the node
// methods table on top of the stack.
Lighting_RegisterNodeMethods :: proc(L: ^lua.State) {
	add :: proc(L: ^lua.State, name, typeName, prop: string, get: bool) {
		for k in LIGHT_KEPT do if k == name do return
		lua.pushstring(L, strings.clone_to_cstring(typeName, context.temp_allocator))
		lua.pushstring(L, strings.clone_to_cstring(prop, context.temp_allocator))
		lua.pushstring(L, strings.clone_to_cstring(name, context.temp_allocator))
		lua.pushcclosure(L, lua_lt_get if get else lua_lt_set, 3)
		lua.setfield(L, -2, strings.clone_to_cstring(name, context.temp_allocator))
	}
	for s in LIGHT_SETTINGS {
		add(L, fmt.tprintf("light_get_%s", s.lua), "LightNode", s.prop, true)
		add(L, fmt.tprintf("light_set_%s", s.lua), "LightNode", s.prop, false)
	}
	for s in ENV_SETTINGS {
		add(L, fmt.tprintf("env_get_%s", s.lua), "EnvironmentNode", s.prop, true)
		add(L, fmt.tprintf("env_set_%s", s.lua), "EnvironmentNode", s.prop, false)
	}
	add(L, "occluder_get_layers", "LightOccluderNode", "layers", true)
	add(L, "occluder_set_layers", "LightOccluderNode", "layers", false)
	// Every drawn node.
	add(L, "get_lit_layers", "", "litLayers", true)
	add(L, "set_lit_layers", "", "litLayers", false)
	add(L, "get_ignore_lighting", "", "ignoreLighting", true)
	add(L, "set_ignore_lighting", "", "ignoreLighting", false)
	reg :: proc(L: ^lua.State, name: cstring, f: lua.CFunction) {
		lua.pushcfunction(L, f)
		lua.setfield(L, -2, name)
	}
	reg(L, "set_emission", lua_node_set_emission)
	reg(L, "get_emission", lua_node_get_emission)
	reg(L, "light_fade", lua_light_fade)
	reg(L, "light_apply_preset", lua_light_apply_preset)
	reg(L, "env_fade_ambient", lua_env_fade_ambient)
}

// Lighting_RegisterModule: the global Lighting table.
Lighting_RegisterModule :: proc(L: ^lua.State) {
	lua.newtable(L)
	lua.pushcfunction(L, lua_lighting_brightness_at)
	lua.setfield(L, -2, "brightness_at")
	lua.pushcfunction(L, lua_lighting_get_lights)
	lua.setfield(L, -2, "get_lights")
	lua.pushcfunction(L, lua_lighting_set_enabled)
	lua.setfield(L, -2, "set_enabled")
	lua.pushcfunction(L, lua_lighting_is_enabled)
	lua.setfield(L, -2, "is_enabled")
	lua.setglobal(L, "Lighting")
}

// Lighting_RegisterSceneFunctions adds get_environment / create_light to the
// Scene table on top of the stack.
Lighting_RegisterSceneFunctions :: proc(L: ^lua.State) {
	lua.pushcfunction(L, lua_scene_get_environment)
	lua.setfield(L, -2, "get_environment")
	lua.pushcfunction(L, lua_scene_create_light)
	lua.setfield(L, -2, "create_light")
}

// lt_node: argument 1 when it's of the closure's type ("" any node);
// warns once per call site otherwise.
@(private = "file")
lt_node :: proc(L: ^lua.State, typeName, fn: string) -> ^Node {
	n, ok := to_node_userdata(L, 1)
	if !ok || n == nil {
		Script_Problem(.Warning, "%s: called on something that isn't a node", fn)
		return nil
	}
	if typeName != "" && Node_TypeName(n) != typeName {
		script_warn_once(L, fn, "%s: %s is a %s, not a %s", fn, n.name, Node_TypeName(n), typeName)
		return nil
	}
	return n
}

@(private = "file")
lua_lt_get :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	typeName := string(lua.tostring(L, lt_up(1)))
	prop := string(lua.tostring(L, lt_up(2)))
	fn := string(lua.tostring(L, lt_up(3)))
	n := lt_node(L, typeName, fn)
	if n == nil {
		lua.pushnil(L)
		return 1
	}
	p, found := Node_FindProperty(n, prop)
	if !found {
		lua.pushnil(L)
		return 1
	}
	#partial switch p.kind {
	case .Float: lua.pushnumber(L, lua.Number(Property_GetFloat(p)))
	case .Int:   lua.pushinteger(L, lua.Integer(Property_GetInt(p)))
	case .Bool:  lua.pushboolean(L, b32((^bool)(p.ptr)^))
	case .String: lua.pushstring(L, strings.clone_to_cstring((^string)(p.ptr)^, context.temp_allocator))
	case .Color: lt_push_color(L, (^rl.Color)(p.ptr)^)
	case .Enum:
		names := Property_EnumNames(p)
		i := Property_GetEnumIndex(p)
		lua.pushstring(L, strings.clone_to_cstring(strings.to_lower(names[i] if i < len(names) else "", context.temp_allocator), context.temp_allocator))
	case .Bit_Set:
		Lighting_PushLayers(L, (^LightLayerSet)(p.ptr)^)
	case:
		lua.pushnil(L)
	}
	return 1
}

@(private = "file")
lua_lt_set :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	typeName := string(lua.tostring(L, lt_up(1)))
	prop := string(lua.tostring(L, lt_up(2)))
	fn := string(lua.tostring(L, lt_up(3)))
	n := lt_node(L, typeName, fn)
	if n == nil do return 0
	p, found := Node_FindProperty(n, prop)
	if !found do return 0
	#partial switch p.kind {
	case .Float:
		if lua.type(L, 2) != .NUMBER {
			Script_Problem(.Warning, "%s: expected a number", fn)
			return 0
		}
		v := f32(lua.tonumber(L, 2))
		if prop == "energy" || prop == "radius" do v = max(v, 0) // (no upper limit, as light_set_energy)
		else if p.has_range do v = clamp(v, p.min, max(p.max, p.min))
		Property_SetFloat(p, v)
	case .Int:
		Property_SetInt(p, i64(lua.tointeger(L, 2)))
	case .Bool:
		(^bool)(p.ptr)^ = bool(lua.toboolean(L, 2))
	case .String:
		s := ""
		if lua.type(L, 2) == .STRING do s = string(lua.tostring(L, 2))
		Property_SetString(n, p, s)
	case .Color:
		col, _, ok := Lua_ArgColor(L, 2)
		if !ok {
			Script_Problem(.Warning, "%s: expected a colour (\"#rrggbb\", {r, g, b} 0..1 or r, g, b)", fn)
			return 0
		}
		(^rl.Color)(p.ptr)^ = col
	case .Enum:
		if lua.type(L, 2) != .STRING do return 0
		want := string(lua.tostring(L, 2))
		for name, i in Property_EnumNames(p) do if strings.equal_fold(name, want) {
			Property_SetEnumIndex(p, i)
			return 0
		}
		Script_Problem(.Warning, "%s: unknown value \"%s\" (%s)", fn, want, strings.join(Property_EnumNames(p), ", ", context.temp_allocator))
	case .Bit_Set:
		set, ok := Lighting_ArgLayers(L, 2, fn)
		if ok do (^LightLayerSet)(p.ptr)^ = set
	}
	return 0
}

@(private = "file")
lt_push_color :: proc(L: ^lua.State, col: rl.Color) {
	lua.createtable(L, 4, 0)
	for v, i in ([4]u8{col.r, col.g, col.b, col.a}) {
		lua.pushnumber(L, lua.Number(f32(v) / 255))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
}

// Lighting_PushLayers: a light layer set as a list of names.
Lighting_PushLayers :: proc(L: ^lua.State, set: LightLayerSet) {
	lua.newtable(L)
	i: lua.Integer = 1
	for l in Light_Layer do if l in set {
		lua.pushstring(L, strings.clone_to_cstring(LightLayer_Name(l), context.temp_allocator))
		lua.rawseti(L, -2, i)
		i += 1
	}
}

// Lighting_ArgLayers reads light layers: a list of names, one name, or a
// number mask (bit 0 = Layer1).
Lighting_ArgLayers :: proc(L: ^lua.State, idx: c.int, fn: string) -> (set: LightLayerSet, ok: bool) {
	#partial switch lua.type(L, idx) {
	case .NUMBER:
		return transmute(LightLayerSet)u8(clamp(lua.tointeger(L, idx), 0, 255)), true
	case .STRING:
		l, found := LightLayer_Parse(string(lua.tostring(L, idx)))
		if !found {
			Script_Problem(.Warning, "%s: no light layer \"%s\" (Project Settings > Light Layers, or Layer1..Layer8)", fn, string(lua.tostring(L, idx)))
			return {}, false
		}
		return {l}, true
	case .TABLE:
		t := lua.absindex(L, idx)
		for i: lua.Integer = 1; ; i += 1 {
			lua.rawgeti(L, t, i)
			defer lua.pop(L, 1)
			if lua.type(L, -1) == .NIL do break
			l, found := LightLayer_Parse(string(lua.tostring(L, -1)))
			if !found {
				Script_Problem(.Warning, "%s: no light layer \"%s\"", fn, string(lua.tostring(L, -1)))
				return {}, false
			}
			set += {l}
		}
		return set, true
	}
	Script_Problem(.Warning, "%s: expected light layers (a list of names, a name or a number mask)", fn)
	return {}, false
}

// node:set_emission(color [, strength]): what glows (strength 0 = none;
// default 1 when the node didn't glow).
@(private = "file")
lua_node_set_emission :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	n := lt_node(L, "", "set_emission")
	if n == nil do return 0
	col, next, ok := Lua_ArgColor(L, 2)
	if !ok {
		Script_Problem(.Warning, "set_emission: expected a colour")
		return 0
	}
	n.emission = col
	if lua.type(L, next) == .NUMBER do n.emissionStrength = max(f32(lua.tonumber(L, next)), 0)
	else if n.emissionStrength == 0 do n.emissionStrength = 1
	return 0
}

// node:get_emission() -> color, strength
@(private = "file")
lua_node_get_emission :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	n := lt_node(L, "", "get_emission")
	if n == nil {
		lua.pushnil(L)
		lua.pushnumber(L, 0)
		return 2
	}
	lt_push_color(L, n.emission)
	lua.pushnumber(L, lua.Number(n.emissionStrength))
	return 2
}

// light:light_fade(energy, seconds [, on_done(light)]) -> tween id
@(private = "file")
lua_light_fade :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	n := lt_node(L, "LightNode", "light_fade")
	sm := get_script_manager(L)
	if n == nil || sm == nil || sm.game == nil {
		lua.pushinteger(L, 0)
		return 1
	}
	to := max(f32(lua.tonumber(L, 2)), 0)
	secs := f32(lua.tonumber(L, 3))
	ref: c.int = 0
	if lua.type(L, 4) == .FUNCTION {
		lua.pushvalue(L, 4)
		ref = lua.L_ref(L, lua.REGISTRYINDEX)
	}
	id := Tween_To(&sm.game.tweens, n, "energy", {to, 0, 0, 0}, secs, .In_Out_Quad, onComplete = ref)
	lua.pushinteger(L, lua.Integer(id))
	return 1
}

// light:light_apply_preset(name) -> boolean
@(private = "file")
lua_light_apply_preset :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	n := lt_node(L, "LightNode", "light_apply_preset")
	if n == nil || lua.type(L, 2) != .STRING {
		lua.pushboolean(L, false)
		return 1
	}
	name := string(lua.tostring(L, 2))
	ok := Light_ApplyPreset(cast(^LightNode)n, name)
	if !ok do Script_Problem(.Warning, "light_apply_preset: no preset \"%s\" (Torch, Lamp, Flashlight, Sun, Neon)", name)
	lua.pushboolean(L, b32(ok))
	return 1
}

// env:env_fade_ambient(color, seconds [, on_done(env)]) -> tween id
@(private = "file")
lua_env_fade_ambient :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	n := lt_node(L, "EnvironmentNode", "env_fade_ambient")
	sm := get_script_manager(L)
	col, next, ok := Lua_ArgColor(L, 2)
	if n == nil || sm == nil || sm.game == nil || !ok {
		if n != nil && !ok do Script_Problem(.Warning, "env_fade_ambient: expected a colour")
		lua.pushinteger(L, 0)
		return 1
	}
	secs := f32(lua.tonumber(L, next))
	ref: c.int = 0
	if lua.type(L, next + 1) == .FUNCTION {
		lua.pushvalue(L, next + 1)
		ref = lua.L_ref(L, lua.REGISTRYINDEX)
	}
	to := [4]f32{f32(col.r), f32(col.g), f32(col.b), 255}
	id := Tween_To(&sm.game.tweens, n, "ambient", to, secs, .In_Out_Quad, onComplete = ref)
	lua.pushinteger(L, lua.Integer(id))
	return 1
}

@(private = "file")
lt_scene :: proc(L: ^lua.State) -> ^Scene {
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil do return nil
	return sm.game.sceneManager.currentScene
}

// Lighting.brightness_at(x, y | pos [, layers]) -> brightness (0 dark .. 1
// full, up to 2 overbright), color {r, g, b}
@(private = "file")
lua_lighting_brightness_at :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	p: [2]f32
	next: c.int = 2
	if lua.type(L, 1) == .NUMBER {
		p = {f32(lua.tonumber(L, 1)), f32(lua.tonumber(L, 2))}
		next = 3
	} else {
		p.x, p.y = arg_xy(L, 1)
	}
	layers := ALL_LIGHT_LAYERS
	if lua.type(L, next) != .NONE && lua.type(L, next) != .NIL {
		if set, ok := Lighting_ArgLayers(L, next, "Lighting.brightness_at"); ok do layers = set
	}
	col, b := Lighting_BrightnessAt(lt_scene(L), p, layers)
	lua.pushnumber(L, lua.Number(b))
	lua.createtable(L, 3, 0)
	for v, i in col {
		lua.pushnumber(L, lua.Number(v))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 2
}

// Lighting.get_lights() -> the scene's lights (enabled ones), tree order.
@(private = "file")
lua_lighting_get_lights :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	lua.newtable(L)
	scene := lt_scene(L)
	if scene == nil || scene.manager == nil do return 1
	i: lua.Integer = 1
	// (With the ones added this frame, still queued.)
	for list in ([2][]^Node{scene.manager.nodes[:], scene.manager.addition[:]}) {
		for n in list do if n != nil && n.typeId == LightNode && n.enabled {
			push_node_userdata(L, n)
			lua.rawseti(L, -2, i)
			i += 1
		}
	}
	return 1
}

@(private = "file")
lua_lighting_set_enabled :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	Lighting_SetEnabled(bool(lua.toboolean(L, 1)))
	return 0
}

@(private = "file")
lua_lighting_is_enabled :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	lua.pushboolean(L, b32(Lighting_Enabled()))
	return 1
}

// Scene.get_environment() -> the scene's Environment node, or nil
@(private = "file")
lua_scene_get_environment :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if env := Scene_Environment(lt_scene(L)); env != nil do push_node_userdata(L, env)
	else do lua.pushnil(L)
	return 1
}

// Scene.create_light(preset [, parent]) -> a new light ("" / nil: a plain one)
@(private = "file")
lua_scene_create_light :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	scene := lt_scene(L)
	if scene == nil {
		lua.pushnil(L)
		return 1
	}
	preset := ""
	if lua.type(L, 1) == .STRING do preset = string(lua.tostring(L, 1))
	parent: ^Node
	if pn, ok := to_node_userdata(L, 2); ok do parent = pn
	if preset != "" {
		known := false
		for p in LIGHT_PRESETS do if strings.equal_fold(p, preset) do known = true
		if !known do Script_Problem(.Warning, "Scene.create_light: no preset \"%s\" (Torch, Lamp, Flashlight, Sun, Neon): a plain light", preset)
	}
	l := Scene_CreateLight(scene, preset, parent)
	push_node_userdata(L, l)
	return 1
}
