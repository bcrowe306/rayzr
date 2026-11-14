package engine

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Lighting's other nodes and helpers (lighting.odin):
//
//   LightOccluderNode  shapes that block light without being physics
//                      bodies (painted walls, pillars, foliage), on light
//                      layers.
//   EnvironmentNode    the scene's look: ambient, Overbright (lights up to
//                      2x the art), Bloom, a half-resolution light map. The
//                      first enabled one in the scene applies; without one,
//                      the scene's Settings (ambient) do.
//
// Plus light layer names, light presets (Torch, Lamp, Flashlight, Sun,
// Neon), the shadows the editor shows for Tile Maps / LDtk levels before
// their colliders exist, and the brightness at a point (Lighting.brightness_at).
// ============================================================================

// --- Light Occluder --------------------------------------------------------------------

LightOccluderNode :: struct {
	using node: Node,
	shapes: [dynamic]PhysicsShape, // (box, circle, polygon... edited like collision shapes)
	layers: LightLayerSet `gui:"true"`, // the lights it blocks: theirs and its share one
}

LightOccluderNode_Create :: proc(scene: ^Scene, name: string = "LightOccluder", parent: ^Node = nil) -> ^LightOccluderNode {
	o := CreateNode(scene.manager, LightOccluderNode)
	o.name = strings.clone(name, o.allocator)
	o.shapes = make([dynamic]PhysicsShape, o.allocator)
	o.layers = ALL_LIGHT_LAYERS
	append(&o.shapes, MakeBoxPhysicsShape(64, 64, {0, 0}, 0))
	o.onDestroy = LightOccluderNode_Destroy
	scene->addNode(o, parent)
	return o
}

LightOccluderNode_Destroy :: proc(node: ^Node, ctx: ^GameContext) {
	o := cast(^LightOccluderNode)node
	for &s in o.shapes do PhysicsShape_Destroy(&s)
	clear(&o.shapes)
}

// --- Environment -----------------------------------------------------------------------

EnvironmentNode :: struct {
	using node: Node,
	ambient:        rl.Color `gui:"true"`,          // the unlit areas' colour (white: unlit scene)
	overbright:     bool `gui:"true"`,              // lights reach up to 2x the art's brightness
	bloom:          bool `gui:"true"`,              // bright areas glow past their edges
	bloomThreshold: f32 `gui:"true" min:"0" max:"1"`, // how bright a pixel must be to glow
	bloomStrength:  f32 `gui:"true" min:"0" max:"4"`, // how much glow
	bloomRadius:    f32 `gui:"true" min:"1" max:"64"`, // how far it spreads (px)
	halfResolution: bool `gui:"true"`,              // the light map at half size (faster, softer)
}

EnvironmentNode_Create :: proc(scene: ^Scene, name: string = "Environment", parent: ^Node = nil) -> ^EnvironmentNode {
	e := CreateNode(scene.manager, EnvironmentNode)
	e.name = strings.clone(name, e.allocator)
	e.ambient = {255, 255, 255, 255}
	e.bloomThreshold = 0.8
	e.bloomStrength = 1
	e.bloomRadius = 12
	scene->addNode(e, parent)
	return e
}

// Scene_Environment: the scene's Environment (the first enabled one, in
// tree order; nil: none).
Scene_Environment :: proc(scene: ^Scene) -> ^EnvironmentNode {
	if scene == nil || scene.manager == nil do return nil
	for n in scene.manager.nodes {
		if n != nil && n.typeId == EnvironmentNode && n.enabled && n.inTree do return cast(^EnvironmentNode)n
	}
	return nil
}

// Scene_Ambient: the ambient light now - the Environment's, else the
// scene's own (white when unset).
Scene_Ambient :: proc(scene: ^Scene) -> rl.Color {
	if env := Scene_Environment(scene); env != nil do return env.ambient
	if scene == nil || scene.ambient == {} do return {255, 255, 255, 255}
	return scene.ambient
}

// Scene_SetAmbient: the Environment's ambient when there is one, else the
// scene's (Scene.set_ambient).
Scene_SetAmbient :: proc(scene: ^Scene, c: rl.Color) {
	if scene == nil do return
	if env := Scene_Environment(scene); env != nil {
		env.ambient = c
		return
	}
	scene.ambient = c
}

// --- Light layer names -----------------------------------------------------------------

lightLayerNames: [8]string

Lighting_SetLayerNames :: proc(names: []string) {
	for &n in lightLayerNames {
		if n != "" do delete(n, Engine_HeapAllocator())
		n = ""
	}
	for name, i in names {
		if i >= 8 do break
		lightLayerNames[i] = strings.clone(strings.trim_space(name), Engine_HeapAllocator())
	}
}

// LightLayer_DisplayName: "Player (2)" or "Layer 2".
LightLayer_DisplayName :: proc(l: Light_Layer, allocator := context.temp_allocator) -> string {
	i := int(l)
	if lightLayerNames[i] != "" do return fmt.aprintf("%s (%d)", lightLayerNames[i], i + 1, allocator = allocator)
	return fmt.aprintf("Layer %d", i + 1, allocator = allocator)
}

// LightLayer_Parse: a project light layer name, "LayerN" / "N" (1-8).
LightLayer_Parse :: proc(s: string) -> (Light_Layer, bool) {
	for name, i in lightLayerNames do if name != "" && strings.equal_fold(name, s) do return Light_Layer(i), true
	digits := strings.trim_prefix(strings.trim_prefix(s, "Layer"), "layer")
	n := 0
	if len(digits) == 0 do return .Layer1, false
	for ch in digits {
		if ch < '0' || ch > '9' do return .Layer1, false
		n = n * 10 + int(ch - '0')
	}
	if n < 1 || n > 8 do return .Layer1, false
	return Light_Layer(n - 1), true
}

// LightLayer_Name: the name scripts get back ("World", else "Layer3").
LightLayer_Name :: proc(l: Light_Layer) -> string {
	if n := lightLayerNames[int(l)]; n != "" do return n
	return fmt.tprintf("Layer%d", int(l) + 1)
}

// --- Presets ---------------------------------------------------------------------------

LIGHT_PRESETS :: [?]string{"Torch", "Lamp", "Flashlight", "Sun", "Neon"}

// Light_ApplyPreset sets a light up as a preset (false: no such preset).
Light_ApplyPreset :: proc(l: ^LightNode, preset: string) -> bool {
	switch strings.to_lower(preset, context.temp_allocator) {
	case "torch":
		LightNode_Defaults(l)
		l.color = {255, 168, 88, 255}
		l.energy = 1.3
		l.radius = 220
		l.softness = 8
		l.flicker = 0.35
		l.flickerSpeed = 9
	case "lamp":
		LightNode_Defaults(l)
		l.color = {255, 236, 200, 255}
		l.energy = 1.1
		l.radius = 320
		l.falloff = 1.6
		l.softness = 10
	case "flashlight":
		LightNode_Defaults(l)
		l.kind = .Spot
		l.color = {236, 244, 255, 255}
		l.energy = 1.4
		l.radius = 420
		l.spread = 22
		l.texture = "builtin:ring"
		l.softness = 4
	case "sun":
		LightNode_Defaults(l)
		l.kind = .Directional
		l.color = {255, 244, 214, 255}
		l.energy = 0.9
		l.elevation = 40
		l.shadowLength = 160
		l.rotation = 35
	case "neon":
		LightNode_Defaults(l)
		l.color = {255, 64, 200, 255}
		l.energy = 1.5
		l.radius = 180
		l.falloff = 1.2
		l.shadows = false
		l.pulse = 0.35
		l.pulseSpeed = 0.8
	case:
		return false
	}
	return true
}

// Scene_CreateLight: a light set up as a preset ("" a plain light), named
// after it (Scene.create_light).
Scene_CreateLight :: proc(scene: ^Scene, preset: string, parent: ^Node = nil) -> ^LightNode {
	name := "Light"
	for p in LIGHT_PRESETS do if strings.equal_fold(p, preset) do name = p
	l := LightNode_Create(scene, name, parent)
	if preset != "" && !Light_ApplyPreset(l, preset) do return l
	return l
}

// --- Editor shadows: Tile Maps and LDtk before their colliders exist --------------------

@(private = "file")
Editor_Shadow_Cache :: struct {
	shapes: [dynamic]PhysicsShape,
	at:     f64,
}

@(private = "file")
editorShadows: map[^Node]Editor_Shadow_Cache

// Lighting_EditorColliders: the outlines a Tile Map (Solid) or an LDtk
// level (Physics) will build colliders from, while it hasn't (the editor;
// in the game the colliders are bodies). Rebuilt at most 4 times a second.
Lighting_EditorColliders :: proc(n: ^Node, out: ^[dynamic]Occluder) {
	built := false
	switch n.typeId {
	case TileMapNode:
		tm := cast(^TileMapNode)n
		if !tm.solid || tm.unbounded do return
		built = tm.staticBody != nil
	case LdtkLevelNode:
		ln := cast(^LdtkLevelNode)n
		if !ln.enablePhysics do return
		built = ln.staticBody != nil
	case:
		return
	}
	if built do return
	if editorShadows == nil do editorShadows = make(map[^Node]Editor_Shadow_Cache, allocator = Engine_HeapAllocator())
	c := &editorShadows[n]
	now := rl.GetTime()
	if c.shapes == nil || now - c.at > 0.25 || now < c.at {
		if c.shapes == nil do c.shapes = make([dynamic]PhysicsShape, Engine_HeapAllocator())
		clear(&c.shapes)
		if n.typeId == TileMapNode do TileMapNode_ColliderShapes(cast(^TileMapNode)n, &c.shapes)
		else do LdtkLevelNode_SolidShapes(cast(^LdtkLevelNode)n, &c.shapes)
		c.at = now
	}
	for &s in c.shapes {
		if poly := Shape_Outline(n, &s); len(poly) >= 2 do append(out, Occluder{poly, n, ALL_LIGHT_LAYERS})
	}
}

// Lighting_ForgetEditorShadows drops the cache (a scene closed).
Lighting_ForgetEditorShadows :: proc() {
	for _, c in editorShadows do delete(c.shapes)
	delete(editorShadows)
	editorShadows = nil
}

// LdtkLevelNode_SolidShapes: the boxes the level's solid and one-way
// collision rules will build (level pixels, as the colliders are).
LdtkLevelNode_SolidShapes :: proc(ln: ^LdtkLevelNode, out: ^[dynamic]PhysicsShape) {
	for lvl in ln.activeLevels {
		off := LdtkLevelNode_LevelOffset(ln, lvl)
		for &layer in lvl.layers {
			if layer.type != .IntGrid && layer.type != .AutoLayer do continue
			if len(layer.intGrid) == 0 || layer.cWid <= 0 || layer.cHei <= 0 do continue
			keys := make([]int, layer.cWid * layer.cHei, context.temp_allocator)
			solid := make(map[int]bool, allocator = context.temp_allocator)
			any := false
			for v, i in layer.intGrid {
				if i >= len(keys) do break
				s, seen := solid[v]
				if !seen {
					rule := LdtkLevelNode_CollisionRule(ln, layer.identifier, v)
					s = rule.type == .Solid || rule.type == .OneWay
					solid[v] = s
				}
				keys[i] = 0 if s else -1
				if s do any = true
			}
			if !any do continue
			g := f32(layer.gridSize)
			for r in ldtk_merge_cells(keys, layer.cWid, layer.cHei) {
				size := [2]f32{f32(r.x1 - r.x0) * g, f32(r.y1 - r.y0) * g}
				center := off + layer.offset + [2]f32{f32(r.x0) * g, f32(r.y0) * g} + size * 0.5
				append(out, MakeBoxPhysicsShape(size.x, size.y, center, 0))
			}
		}
	}
}

// --- Brightness at a point (Lighting.brightness_at) ------------------------------------

// Lighting_BrightnessAt: how lit a point is now - the ambient plus every
// light on `layers` that reaches it (shadows included; normal maps and
// light textures left out). colour 0..1 per channel (up to 2 with
// Overbright), brightness = its luminance.
Lighting_BrightnessAt :: proc(scene: ^Scene, p: [2]f32, layers := ALL_LIGHT_LAYERS) -> (color: [3]f32, brightness: f32) {
	if scene == nil || scene.manager == nil do return {1, 1, 1}, 1
	if !Scene_HasLighting(scene) do return {1, 1, 1}, 1
	amb := Scene_Ambient(scene)
	color = {f32(amb.r), f32(amb.g), f32(amb.b)} / 255
	env := Scene_Environment(scene)
	top: f32 = 2 if env != nil && env.overbright else 1
	occluders: [dynamic]Occluder
	have := false
	t := rl.GetTime()
	for n in scene.manager.nodes {
		if n == nil || n.typeId != LightNode || !n.enabled || !Node_VisibleInTree(n) do continue
		l := cast(^LightNode)n
		if l.layers & layers == {} do continue
		e := clamp(Light_Energy(l, t), 0, 8)
		if e <= 0 do continue
		a: f32 = 1
		c := l.globalPosition
		from: [2]f32 // where shadows are tested from
		if l.kind == .Directional {
			ra := math.to_radians(l.globalRotation)
			dir := [2]f32{math.cos(ra), math.sin(ra)}
			reach := l.shadowLength if l.shadowLength > 0 else 100000
			from = p - dir * reach
		} else {
			r := l.radius * max(abs(l.globalScale.x), abs(l.globalScale.y))
			d := p - c
			dist := math.sqrt(d.x * d.x + d.y * d.y)
			if r <= 0 || dist >= r do continue
			a = math.pow(1 - dist / r, max(l.falloff, 0.1))
			if l.kind == .Spot && dist > 0.0001 {
				ra := math.to_radians(l.globalRotation)
				cosA := (d.x * math.cos(ra) + d.y * math.sin(ra)) / dist
				sp := math.cos(math.to_radians(clamp(l.spread, 1, 180)))
				hi := sp + (1 - sp) * 0.15
				tt := clamp((cosA - sp) / max(hi - sp, 0.0001), 0, 1)
				a *= tt * tt * (3 - 2 * tt)
			}
			from = c
		}
		if a <= 0 do continue
		if l.shadows && l.shadowStrength > 0 {
			if !have {
				occluders = Lighting_Occluders(scene)
				have = true
			}
			for &o in occluders {
				if !Light_BlockedBy(l, &o) do continue
				if segment_crosses_poly(from, p, o.points[:]) {
					a *= 1 - clamp(l.shadowStrength, 0, 1)
					break
				}
			}
		}
		lc := [3]f32{f32(l.color.r), f32(l.color.g), f32(l.color.b)} / 255
		color += lc * e * a
	}
	color = {min(color.x, top), min(color.y, top), min(color.z, top)}
	brightness = 0.299 * color.x + 0.587 * color.y + 0.114 * color.z
	return
}

// segment_crosses_poly: the segment a-b crosses one of the outline's edges
// (a 2-point outline is a single segment).
@(private = "file")
segment_crosses_poly :: proc(a, b: [2]f32, poly: [][2]f32) -> bool {
	n := len(poly)
	for i in 0 ..< n {
		if n == 2 && i == 1 do break
		if segments_cross(a, b, poly[i], poly[(i + 1) % n]) do return true
	}
	return false
}

@(private = "file")
segments_cross :: proc(p1, p2, q1, q2: [2]f32) -> bool {
	cross :: proc(o, a, b: [2]f32) -> f32 {return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)}
	d1 := cross(q1, q2, p1)
	d2 := cross(q1, q2, p2)
	d3 := cross(p1, p2, q1)
	d4 := cross(p1, p2, q2)
	return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0))
}
