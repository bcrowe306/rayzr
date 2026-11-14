package engine

import "core:strings"
import "core:testing"
import lua "lua54"
import rl "vendor:raylib"

// The lighting round: shadows (Casts Shadows, Ignore Parent Bodies,
// occluders, strength), light layers, Ignore Lighting / emission saved,
// the Environment, presets, flicker / pulse, brightness_at, the sprite
// tracer, and the Lua API.

@(private = "file")
lr_setup :: proc() -> (^Game, ^Scene) {
	game := new(Game)
	InitializeGame(game)
	scene := game->createScene("lr", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	return game, scene
}

@(private = "file")
lr_settle :: proc(game: ^Game, scene: ^Scene) {
	ProcessNodeQueues(scene.manager, &game.gameContext)
	Node_SetGlobalPositions(scene.manager, scene.rootNode)
}

@(test)
test_lighting_round_shadows_and_brightness :: proc(t: ^testing.T) {
	game, scene := lr_setup()
	defer game->terminate()
	scene.ambient = {20, 20, 20, 255}
	l := LightNode_Create(scene, "Lamp")
	l.position = {0, 0}
	l.radius = 400
	l.softness = 0
	wall := StaticBodyNode_Create(scene, "Wall")
	wall.position = {100, 0}
	append(&wall.shapes, MakeBoxPhysicsShape(20, 200, {0, 0}, 0))
	lr_settle(game, scene)

	// In front of the wall: lit; behind it: in its shadow (the ambient).
	_, front := Lighting_BrightnessAt(scene, {50, 0})
	_, behind := Lighting_BrightnessAt(scene, {200, 0})
	testing.expectf(t, front > 0.5, "lit in front of the wall (%v)", front)
	testing.expectf(t, behind < 0.12, "dark behind it (%v)", behind)
	// Off to the side, out of the shadow.
	_, side := Lighting_BrightnessAt(scene, {0, 200})
	testing.expectf(t, side > behind + 0.1, "lit beside it (%v)", side)

	// Casts Shadows off: light passes through.
	wall.castsShadows = false
	_, through := Lighting_BrightnessAt(scene, {200, 0})
	testing.expectf(t, through > behind + 0.1, "no shadow without Casts Shadows (%v)", through)
	wall.castsShadows = true

	// Shadow Strength: half the shadow.
	l.shadowStrength = 0.5
	_, half := Lighting_BrightnessAt(scene, {200, 0})
	testing.expectf(t, half > behind && half < through, "a lighter shadow (%v)", half)
	l.shadowStrength = 1

	// Ignore Parent Bodies: a light inside a body isn't blocked by it.
	crate := StaticBodyNode_Create(scene, "Crate")
	crate.position = {0, 0}
	append(&crate.shapes, MakeBoxPhysicsShape(40, 40, {0, 0}, 0))
	lamp2 := LightNode_Create(scene, "Lantern", crate)
	lamp2.radius = 300
	l.energy = 0 // (only the lantern)
	lr_settle(game, scene)
	_, out := Lighting_BrightnessAt(scene, {0, -120})
	testing.expectf(t, out > 0.3, "the lantern lights outside its crate (%v)", out)
	lamp2.ignoreParentBodies = false
	_, blocked := Lighting_BrightnessAt(scene, {0, -120})
	testing.expectf(t, blocked < 0.12, "... and not without Ignore Parent Bodies (%v)", blocked)
	lamp2.ignoreParentBodies = true

	// Occluders and light layers: an occluder on Layer2 blocks only lights on it.
	occ := LightOccluderNode_Create(scene, "Pillar")
	occ.position = {0, 150}
	clear(&occ.shapes)
	append(&occ.shapes, MakeCircleShape_lr(30))
	occ.layers = {.Layer2}
	lamp2.radius = 900
	lr_settle(game, scene)
	_, past := Lighting_BrightnessAt(scene, {0, 250})
	testing.expectf(t, past < 0.12, "a light on every layer is blocked by a Layer2 occluder (%v)", past)
	lamp2.layers = {.Layer1}
	_, past1 := Lighting_BrightnessAt(scene, {0, 250})
	testing.expectf(t, past1 > past + 0.1, "a Layer1 light passes a Layer2 occluder (%v)", past1)
	lamp2.layers = ALL_LIGHT_LAYERS

	// brightness_at only counts the lights on the layers asked for.
	_, none := Lighting_BrightnessAt(scene, {0, -120}, {.Layer3})
	lamp2.layers = {.Layer1}
	_, onlyOther := Lighting_BrightnessAt(scene, {0, -120}, {.Layer3})
	testing.expectf(t, onlyOther < none, "lights off those layers don't count (%v < %v)", onlyOther, none)

	// The occluder list: bodies with Casts Shadows, the occluder; not the off ones.
	wall.castsShadows = false
	occs := Lighting_Occluders(scene)
	owners := make(map[^Node]bool, allocator = context.temp_allocator)
	for o in occs do owners[o.owner] = true
	testing.expect(t, !owners[wall] && owners[crate] && owners[occ], "occluders: casting bodies and occluders only")
}

@(private = "file")
MakeCircleShape_lr :: proc(r: f32) -> PhysicsShape {
	s: PhysicsShape
	PhysicsShape_InitDefault(&s, .Circle)
	s.radius = r
	return s
}

@(test)
test_lighting_round_saved :: proc(t: ^testing.T) {
	game, scene := lr_setup()
	defer game->terminate()
	l := LightNode_Create(scene, "Lamp")
	testing.expect_value(t, l.softness, f32(LIGHT_DEFAULT_SOFTNESS))
	l.layers = {.Layer2, .Layer3}
	l.texture = "builtin:ring"
	l.flicker = 0.3
	sb := StaticBodyNode_Create(scene, "Glass")
	sb.castsShadows = false
	s := Node_CreateByTypeName(scene, "TextureNode")
	s.name = "Sign"
	s.litLayers = {.Layer4}
	s.ignoreLighting = true
	s.emission = {255, 64, 0, 255}
	s.emissionStrength = 2
	env := EnvironmentNode_Create(scene, "Env")
	env.ambient = {10, 20, 30, 255}
	env.bloom = true
	occ := LightOccluderNode_Create(scene, "Occ")
	occ.layers = {.Layer5}
	lr_settle(game, scene)
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"lit_layers": 8`) && strings.contains(text, `"ignore_lighting": true`) && strings.contains(text, `"emission_strength": 2`), "node lighting saved")

	s2 := game->createScene("lr2", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &game.gameContext)
	lr_settle(game, s2)
	l2 := cast(^LightNode)Scene_FindNodeByName(s2, "Lamp")
	testing.expect(t, l2 != nil && l2.layers == {.Layer2, .Layer3} && l2.texture == "builtin:ring" && l2.flicker == 0.3 && l2.softness == LIGHT_DEFAULT_SOFTNESS, "light settings loaded")
	g2 := cast(^StaticBodyNode)Scene_FindNodeByName(s2, "Glass")
	testing.expect(t, g2 != nil && !g2.castsShadows, "Casts Shadows loaded")
	s3 := Scene_FindNodeByName(s2, "Sign")
	testing.expect(t, s3 != nil && s3.litLayers == {.Layer4} && s3.ignoreLighting && s3.emission == {255, 64, 0, 255} && s3.emissionStrength == 2, "node lighting loaded")
	e2 := Scene_Environment(s2)
	testing.expect(t, e2 != nil && e2.bloom && Scene_Ambient(s2) == {10, 20, 30, 255}, "environment loaded, its ambient used")
	o2 := cast(^LightOccluderNode)Scene_FindNodeByName(s2, "Occ")
	testing.expect(t, o2 != nil && o2.layers == {.Layer5} && len(o2.shapes) == 1, "occluder loaded")

	// A light saved before soft shadows (no "softness") keeps hard ones;
	// a body without "castsShadows" casts them.
	old := `{"name": "old", "root": {"type": "Node", "name": "Root", "children": [
		{"type": "LightNode", "name": "OldLamp", "properties": {"kind": "Point", "energy": 1, "radius": 200, "shadows": true}},
		{"type": "StaticBodyNode", "name": "OldWall", "shapes": [{"type": "Box", "size": [10, 10]}], "properties": {"oneWay": false}}]}}`
	s4 := game->createScene("lr3", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	Scene_InstantiateFromJSON(s4, transmute([]u8)old, &game.gameContext)
	lr_settle(game, s4)
	ol := cast(^LightNode)Scene_FindNodeByName(s4, "OldLamp")
	ow := cast(^StaticBodyNode)Scene_FindNodeByName(s4, "OldWall")
	testing.expect(t, ol != nil && ol.softness == 0 && ol.shadowStrength == 1 && ol.ignoreParentBodies && ol.layers == ALL_LIGHT_LAYERS, "an old light: hard shadows, defaults for the rest")
	testing.expect(t, ow != nil && ow.castsShadows, "an old body casts shadows")
	testing.expectf(t, ow.litLayers == ALL_LIGHT_LAYERS && !ow.ignoreLighting && ow.emissionStrength == 0, "an old node: lit by every layer, no glow (%v %v %v)", ow.litLayers, ow.ignoreLighting, ow.emissionStrength)
}

@(test)
test_lighting_round_environment_presets_energy :: proc(t: ^testing.T) {
	game, scene := lr_setup()
	defer game->terminate()
	testing.expect_value(t, Scene_Ambient(scene), rl.Color{255, 255, 255, 255})
	Scene_SetAmbient(scene, {1, 2, 3, 255})
	testing.expect_value(t, scene.ambient, rl.Color{1, 2, 3, 255})
	env := EnvironmentNode_Create(scene, "Env")
	lr_settle(game, scene)
	Scene_SetAmbient(scene, {9, 9, 9, 255})
	testing.expect(t, env.ambient == {9, 9, 9, 255} && scene.ambient == {1, 2, 3, 255}, "with an Environment, set_ambient sets its ambient")
	env.enabled = false
	testing.expect_value(t, Scene_Ambient(scene), rl.Color{1, 2, 3, 255})

	// Presets.
	for p in LIGHT_PRESETS {
		l := Scene_CreateLight(scene, p)
		testing.expect(t, l.name == p, "named after the preset")
	}
	torch := Scene_CreateLight(scene, "torch")
	testing.expect(t, torch.flicker > 0 && torch.color.r > torch.color.b, "a torch flickers, warm")
	testing.expect(t, !Light_ApplyPreset(torch, "Disco"), "an unknown preset")

	// Flicker and pulse stay within their range.
	torch.energy = 2
	torch.flicker = 0.5
	torch.pulse = 0.4
	torch.pulseSpeed = 1.3
	lo, hi: f32 = 100, -100
	for i in 0 ..< 400 {
		e := Light_Energy(torch, f64(i) * 0.013)
		lo, hi = min(lo, e), max(hi, e)
	}
	testing.expectf(t, lo >= 2 * 0.5 * 0.6 - 0.001 && hi <= 2.001 && hi - lo > 0.3, "flicker + pulse vary between %v and %v", lo, hi)
	torch.flicker, torch.pulse = 0, 0
	testing.expect_value(t, Light_Energy(torch, 3.7), f32(2))

	// Layer names.
	Lighting_SetLayerNames({"World", "", "Player"})
	defer Lighting_SetLayerNames({})
	ll, ok := LightLayer_Parse("player")
	testing.expect(t, ok && ll == .Layer3, "a layer by its name")
	ll, ok = LightLayer_Parse("Layer2")
	testing.expect(t, ok && ll == .Layer2, "a layer by number")
	_, ok = LightLayer_Parse("Layer9")
	testing.expect(t, !ok, "no Layer9")
	testing.expect_value(t, LightLayer_Name(.Layer1), "World")
	testing.expect_value(t, LightLayer_Name(.Layer2), "Layer2")
}

@(test)
test_lighting_round_sprite_outline :: proc(t: ^testing.T) {
	img := rl.GenImageColor(64, 64, {0, 0, 0, 0})
	defer rl.UnloadImage(img)
	rl.ImageDrawCircle(&img, 32, 32, 20, rl.WHITE)
	rl.ImageDrawRectangle(&img, 2, 2, 6, 6, rl.WHITE) // (a 36 px island: kept)
	rl.ImageDrawPixel(&img, 60, 60, rl.WHITE)         // (a pixel: left out)
	outlines := Image_AlphaOutlines(img, {0, 0, 64, 64})
	testing.expect_value(t, len(outlines), 3)
	shapes := make([dynamic]PhysicsShape, context.temp_allocator)
	// Drawn 128 px big around its middle: node space -64..64.
	n := Occluder_ShapesFromImage(img, {0, 0, 64, 64}, {128, 128}, {64, 64}, &shapes)
	testing.expect(t, n >= 2, "the circle and the square")
	lo, hi := [2]f32{1e9, 1e9}, [2]f32{-1e9, -1e9}
	for &s in shapes {
		testing.expect(t, s.type == .Polygon && s.vertexCount >= 3 && s.vertexCount <= 8, "convex polygons of at most 8 corners")
		for v in s.vertices[:s.vertexCount] {
			lo = {min(lo.x, v.x), min(lo.y, v.y)}
			hi = {max(hi.x, v.x), max(hi.y, v.y)}
		}
	}
	// The circle spans 12..52 px of 64: -40..40 in node space; the square from -60.
	testing.expectf(t, lo.x < -55 && lo.x > -62 && hi.x > 36 && hi.x < 44, "traced bounds %v .. %v", lo, hi)
}

@(test)
test_lighting_round_lua :: proc(t: ^testing.T) {
	game, scene := lr_setup()
	defer game->terminate()
	l := LightNode_Create(scene, "Lamp")
	l.radius = 300
	EnvironmentNode_Create(scene, "Env")
	sign := Node_CreateByTypeName(scene, "TextureNode")
	sign.name = "Sign"
	LightOccluderNode_Create(scene, "Occ")
	lr_settle(game, scene)
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local lamp = Scene.find_node("Lamp")
lamp:light_set_kind("spot")
lamp:light_set_softness(12)
lamp:light_set_shadow_strength(0.4)
lamp:light_set_layers({"Layer2", "Layer4"})
lamp:light_set_texture("builtin:noise")
lamp:light_set_flicker(0.25)
lamp:light_set_ignore_parent_bodies(false)
local layers = lamp:light_get_layers()
local env = Scene.get_environment()
env:env_set_bloom(true)
env:env_set_ambient("#102030")
env:env_set_bloom_threshold(5) -- (clamped to 1)
Scene.set_ambient(0.5, 0.5, 0.5)
local sign = Scene.find_node("Sign")
sign:set_emission("#ff0000", 2)
sign:set_ignore_lighting(true)
sign:set_lit_layers("Layer3")
local _, strength = sign:get_emission()
local occ = Scene.find_node("Occ")
occ:occluder_set_layers(6)
local b, col = Lighting.brightness_at(0, 0)
local torch = Scene.create_light("Torch")
probe = string.format("%s %.1f %.1f %s,%s %s %s %.1f %s %s %d %s %s %s %d", lamp:light_get_kind(), lamp:light_get_softness(),
	lamp:light_get_shadow_strength(), layers[1], layers[2], lamp:light_get_texture(), tostring(lamp:light_get_ignore_parent_bodies()),
	env:env_get_bloom_threshold(), tostring(env:env_get_bloom()), tostring(sign:get_ignore_lighting()), strength,
	sign:get_lit_layers()[1], occ:occluder_get_layers()[1], torch:get_name(), #Lighting.get_lights())
probe2 = type(b) == "number" and #col == 3
probe3 = tostring(Lighting.is_enabled())
Lighting.set_enabled(false)
probe4 = tostring(Lighting.is_enabled())
Lighting.set_enabled(true)
`) == 0
	if !ok {
		lua.getglobal(L, "probe")
		testing.expectf(t, false, "Lua failed: %s", string(lua.tostring(L, -2)))
		return
	}
	lua.getglobal(L, "probe")
	testing.expect_value(t, string(lua.tostring(L, -1)), "spot 12.0 0.4 Layer2,Layer4 builtin:noise false 1.0 true true 2 Layer3 Layer2 Torch 2")
	lua.pop(L, 1)
	lua.getglobal(L, "probe2")
	testing.expect(t, bool(lua.toboolean(L, -1)), "brightness_at: a number and a colour")
	lua.pop(L, 1)
	lua.getglobal(L, "probe3")
	testing.expect_value(t, string(lua.tostring(L, -1)), "true")
	lua.pop(L, 1)
	lua.getglobal(L, "probe4")
	testing.expect_value(t, string(lua.tostring(L, -1)), "false")
	lua.pop(L, 1)
	env := Scene_Environment(scene)
	testing.expect(t, env.ambient == {128, 128, 128, 255}, "Scene.set_ambient set the Environment's")
	testing.expect(t, l.flicker == 0.25 && l.layers == {.Layer2, .Layer4}, "light set from Lua")
}
