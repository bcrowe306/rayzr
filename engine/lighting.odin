package engine

import "core:log"
import "core:math"
import "core:strings"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// 2D lighting (the guide: engine/docs/lighting.md).
//
// LightNode: a point light, a spot cone (rotation = direction) or the sun,
// with a colour, energy, radius and falloff, a light texture ("cookie"),
// flicker / pulse, and shadows from the scene's physics bodies (Casts
// Shadows on) and Light Occluders - hard or soft (Softness), as dark as
// its Shadow Strength. Light layers: a light lights the nodes, and is
// blocked by the occluders, that share one of its layers.
//
// When a scene has lights (or a non-white ambient), a light map is built
// each frame (Lighting_Prepare): cleared to the ambient (the scene's
// Environment node, else its Settings), each light added on top - its
// shadows from a mask drawn for it (blurred when soft) - then multiplied
// over the world layers (Lighting_Composite). UI layers aren't lit.
//
// Per-node lighting (Lit By layers, Ignore Lighting) comes from an info
// buffer drawn like the normal pass (lighting_passes.odin), only when some
// node or light uses it; emission (glow) from an emission buffer added
// after the multiply. An Environment with Overbright stores the map at half
// (lights reach 2x the art's brightness); Half Resolution builds the map at
// half the size.
//
// Order: Lighting_Prepare (before the frame's drawing target is set up:
// it renders into its own render textures), the scene's world layers, then
// Lighting_Composite in screen space.
// ============================================================================

Light_Kind :: enum {
	Point,
	Spot,
	Directional, // the sun: one direction (its rotation) over everything, no radius
}

LightNode :: struct {
	using node: Node,
	kind:    Light_Kind `gui:"true"`,
	color:   rl.Color `gui:"true"`,
	energy:  f32 `gui:"true" min:"0" max:"8"`,
	radius:  f32 `gui:"true" min:"1" max:"4000"`,
	falloff: f32 `gui:"true" min:"0.1" max:"8"`,  // 1 linear, 2 smooth, higher = tighter
	spread:  f32 `gui:"true" min:"1" max:"180"`,  // spot: half-angle of the cone (degrees)
	texture: string `gui:"true"`,                 // light texture (cookie): an image, or builtin:ring / window / blinds / noise; "" none
	layers:  LightLayerSet `gui:"true"`,          // the light layers it lights (and is blocked on)
	shadows: bool `gui:"true"`,
	softness:       f32 `gui:"true" min:"0" max:"64"`, // shadow edge blur (px); 0 = hard
	shadowStrength: f32 `gui:"true" min:"0" max:"1"`,  // how dark its shadows are
	ignoreParentBodies: bool `gui:"true"`,             // the bodies it sits in (its ancestors) cast no shadow for it
	height:    f32 `gui:"true" min:"0" max:"2000"`, // above the ground (px): low lights rake across normal maps, high ones light flat (#274)
	elevation: f32 `gui:"true" min:"1" max:"90"`,   // Directional: the sun's angle above the ground (degrees)
	shadowLength: f32 `gui:"true" min:"0" max:"4000"`, // Directional: how far shadows reach (px; 0 = no end)
	flicker:      f32 `gui:"true" min:"0" max:"1"`,  // random dips in brightness (0 off .. 1 to black)
	flickerSpeed: f32 `gui:"true" min:"0" max:"30"`, // how fast (changes a second)
	pulse:        f32 `gui:"true" min:"0" max:"1"`,  // a steady rise and fall (0 off .. 1 full)
	pulseSpeed:   f32 `gui:"true" min:"0" max:"10"`, // cycles a second
	// (runtime: the loaded light texture)
	cookie:    rl.Texture2D,
	cookieRes: ^Texture, // (a project image's: released when it changes)
	cookieFor: string, // the path it was loaded for (heap)
}

// Light defaults (LightNode_Create; a file without "softness" is from before
// soft shadows: hard - read_node).
LIGHT_DEFAULT_SOFTNESS :: 6

LightNode_Create :: proc(scene: ^Scene, name: string = "Light", parent: ^Node = nil) -> ^LightNode {
	l := CreateNode(scene.manager, LightNode)
	l.name = strings.clone(name, l.allocator) // owned: callers pass temp strings too
	LightNode_Defaults(l)
	l.onDestroy = LightNode_Destroy
	scene->addNode(l, parent)
	return l
}

// LightNode_Defaults: a new light's settings (a warm point light).
LightNode_Defaults :: proc(l: ^LightNode) {
	l.kind = .Point
	l.color = {255, 236, 200, 255}
	l.energy = 1
	l.radius = 256
	l.falloff = 2
	l.spread = 35
	l.layers = ALL_LIGHT_LAYERS
	l.shadows = true
	l.softness = LIGHT_DEFAULT_SOFTNESS
	l.shadowStrength = 1
	l.ignoreParentBodies = true
	l.height = 64
	l.elevation = 45
	l.shadowLength = 120
	l.flicker = 0
	l.flickerSpeed = 10
	l.pulse = 0
	l.pulseSpeed = 1
}

LightNode_Destroy :: proc(node: ^Node, ctx: ^GameContext) {
	l := cast(^LightNode)node
	light_release_cookie(l)
	if l.cookieFor != "" do delete(l.cookieFor)
	l.cookieFor = ""
	l.cookie = {}
}

// Light_Energy: the light's energy now, with its flicker and pulse.
Light_Energy :: proc(l: ^LightNode, t: f64) -> f32 {
	e := max(l.energy, 0)
	if l.pulse > 0 && l.pulseSpeed > 0 {
		e *= 1 - clamp(l.pulse, 0, 1) * 0.5 * (1 - f32(math.cos(t * f64(l.pulseSpeed) * math.TAU)))
	}
	if l.flicker > 0 && l.flickerSpeed > 0 {
		seed := f64(uintptr(l) % 997) * 7.31
		e *= 1 - clamp(l.flicker, 0, 1) * light_noise(t * f64(l.flickerSpeed) + seed)
	}
	return e
}

// light_noise: smooth value noise in 0..1 (the flicker's dips).
@(private = "file")
light_noise :: proc(x: f64) -> f32 {
	hash :: proc(i: i64) -> f32 {
		h := u32(i * 374761393 + 668265263)
		h = (h ~ (h >> 13)) * 1274126177
		return f32(h & 0xffff) / 65535
	}
	i := i64(math.floor(x))
	f := f32(x - math.floor(x))
	f = f * f * (3 - 2 * f)
	a, b := hash(i), hash(i + 1)
	v := a + (b - a) * f
	return v * v // (mostly bright, the odd deep dip)
}

@(private = "file")
LIGHT_SHADER :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;
uniform sampler2D texture0;  // the light texture (white without one)
uniform float falloff;
uniform float spread;   // cos of the cone half-angle (-1 = point light)
uniform float sun;      // 1: a directional light (sunDir), the quad covers the view
uniform vec2 rot;       // the light's rotation (cos, sin)
uniform float radius;
uniform float height;
uniform vec3 sunDir;    // towards the sun
uniform float useNormals;
uniform sampler2D normalMap; // the normal pass (normal_maps.odin): xy, specular, normal-mapped
uniform vec2 screenSize;     // the light map's size: buffers are read at gl_FragCoord / it
uniform float useShadow;
uniform sampler2D shadowMap; // this light's shadows (r: 1 = in shadow)
uniform float shadowStrength;
uniform float useInfo;
uniform sampler2D infoMap;   // lighting_passes.odin: r = the pixel's lit-by layers
uniform float lightMask;     // this light's layers (0..255)
uniform float useCookie;
void main() {
    vec2 suv = gl_FragCoord.xy / screenSize;
    if (useInfo > 0.5) {
        int pm = int(texture(infoMap, suv).r * 255.0 + 0.5);
        if ((pm & int(lightMask + 0.5)) == 0) discard;
    }
    float a = 1.0;
    vec3 L = sunDir;
    if (sun < 0.5) {
        vec2 d = fragTexCoord * 2.0 - 1.0;   // -1..1 across the light's square
        float r = length(d);
        if (r > 1.0) discard;
        a = pow(1.0 - r, falloff);
        if (spread > -1.0) {
            // The cone points along +x of the quad (rotated by the light).
            float c = r > 0.0001 ? d.x / r : 1.0;
            a *= smoothstep(spread, mix(spread, 1.0, 0.15), c);
        }
        vec2 w = vec2(rot.x * d.x - rot.y * d.y, rot.y * d.x + rot.x * d.y) * radius; // light -> pixel, world
        L = normalize(vec3(-w, max(height, 0.001)));
    }
    vec3 cookie = vec3(1.0);
    if (useCookie > 0.5) cookie = texture(texture0, fragTexCoord).rgb;
    if (useShadow > 0.5) a *= 1.0 - shadowStrength * texture(shadowMap, suv).r;
    float lit = 1.0;
    float spec = 0.0;
    if (useNormals > 0.5) {
        vec4 nm = texture(normalMap, suv);
        vec3 N = vec3(0.0, 0.0, 1.0);
        if (nm.a > 0.5) {
            vec2 nxy = nm.rg * 2.0 - 1.0;
            N = vec3(nxy, sqrt(max(0.0, 1.0 - dot(nxy, nxy))));
            lit = max(dot(N, L), 0.0);
        }
        if (nm.b > 0.004) {
            vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
            spec = nm.b * pow(max(dot(N, H), 0.0), 32.0) * 2.0;
        }
    }
    finalColor = vec4(fragColor.rgb * cookie * a * fragColor.a * (lit + spec), 1.0);
}
`

// The soft shadows' blur (separable, 9 taps; `dir` = one tap's step).
@(private = "file")
BLUR_SHADER :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;
uniform sampler2D texture0;
uniform vec2 dir;
void main() {
    float w[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);
    vec4 s = texture(texture0, fragTexCoord) * w[0];
    for (int i = 1; i < 5; i++) {
        s += texture(texture0, fragTexCoord + dir * float(i)) * w[i];
        s += texture(texture0, fragTexCoord - dir * float(i)) * w[i];
    }
    finalColor = vec4(s.rgb, 1.0);
}
`

// The unlit pixels (Ignore Lighting): the light map at full there.
@(private = "file")
UNLIT_SHADER :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;
uniform sampler2D infoMap;
uniform vec2 screenSize;
void main() {
    if (texture(infoMap, gl_FragCoord.xy / screenSize).g < 0.5) discard;
    finalColor = fragColor;
}
`

@(private = "file")
Light_Locs :: struct {
	falloff, spread, sun, rot, radius, height, sunDir, useNormals, normalMap, screenSize: i32,
	useShadow, shadowMap, shadowStrength, useInfo, infoMap, lightMask, useCookie: i32,
}

@(private = "file")
lighting: struct {
	shader:     rl.Shader,
	shaderOk:   bool,
	loc:        Light_Locs,
	blur:       rl.Shader,
	blurDir:    i32,
	unlit:      rl.Shader,
	unlitInfo:  i32,
	unlitSize:  i32,
	lightMap:   rl.RenderTexture2D, // (the light map's size: half with Half Resolution)
	shadow:     rl.RenderTexture2D, // one light's shadows
	shadowTmp:  rl.RenderTexture2D, // (the blur's other half)
	normals:    rl.RenderTexture2D, // the normal pass (normal_maps.odin), full size
	info:       rl.RenderTexture2D, // the info pass (lighting_passes.odin), full size
	emission:   rl.RenderTexture2D, // the emission pass (lighting_passes.odin), full size
	size:       [2]i32, // the frame's size
	mapSize:    [2]i32, // the light map's
	ready:      bool,   // a light map was prepared this frame
	overbright: bool,   // ... stored at half (composited at 2x)
	emitting:   bool,   // ... with an emission buffer to add
	builtins:   map[string]rl.Texture2D, // builtin:<name> light textures
	enabled:    bool,   // Lighting.set_enabled (on by default)
	enabledSet: bool,
}

// Lighting_SetEnabled: lights off (false) shows the scene as drawn - the
// ambient, the lights, emission, bloom (Lighting.set_enabled).
Lighting_SetEnabled :: proc(on: bool) {
	lighting.enabled = on
	lighting.enabledSet = true
}

Lighting_Enabled :: proc() -> bool {return !lighting.enabledSet || lighting.enabled}

// Scene_HasLighting: lights, or an ambient that isn't white.
Scene_HasLighting :: proc(scene: ^Scene) -> bool {
	if scene == nil || scene.manager == nil || !Lighting_Enabled() do return false
	amb := Scene_Ambient(scene)
	if amb != {255, 255, 255, 255} do return true
	for n in scene.manager.nodes do if n != nil && n.typeId == LightNode && n.enabled do return true
	return false
}

@(private = "file")
load_shader :: proc(src: cstring) -> (rl.Shader, bool) {
	sh := rl.LoadShaderFromMemory(nil, Shader_Port(src))
	return sh, rl.IsShaderValid(sh)
}

@(private = "file")
reload_target :: proc(t: ^rl.RenderTexture2D, w, h: i32) {
	if t.id != 0 do rl.UnloadRenderTexture(t^)
	t^ = rl.LoadRenderTexture(w, h)
}

@(private = "file")
ensure_targets :: proc(w, h, mw, mh: i32) -> bool {
	if !rl.IsWindowReady() || w <= 0 || h <= 0 || mw <= 0 || mh <= 0 do return false
	if !lighting.shaderOk {
		@(static) failed: bool
		if failed do return false
		ok, bok, uok: bool
		lighting.shader, ok = load_shader(LIGHT_SHADER)
		lighting.blur, bok = load_shader(BLUR_SHADER)
		lighting.unlit, uok = load_shader(UNLIT_SHADER)
		if !ok || !bok || !uok {
			log.errorf("[Lighting] a lighting shader didn't compile (light %v, blur %v, unlit %v): no lighting", ok, bok, uok)
			failed = true
			return false
		}
		sh := lighting.shader
		g :: proc(sh: rl.Shader, n: cstring) -> i32 {return rl.GetShaderLocation(sh, n)}
		lighting.loc = {
			g(sh, "falloff"), g(sh, "spread"), g(sh, "sun"), g(sh, "rot"), g(sh, "radius"), g(sh, "height"), g(sh, "sunDir"),
			g(sh, "useNormals"), g(sh, "normalMap"), g(sh, "screenSize"), g(sh, "useShadow"), g(sh, "shadowMap"),
			g(sh, "shadowStrength"), g(sh, "useInfo"), g(sh, "infoMap"), g(sh, "lightMask"), g(sh, "useCookie"),
		}
		lighting.blurDir = g(lighting.blur, "dir")
		lighting.unlitInfo = g(lighting.unlit, "infoMap")
		lighting.unlitSize = g(lighting.unlit, "screenSize")
		lighting.shaderOk = true
	}
	if lighting.size != {w, h} {
		reload_target(&lighting.normals, w, h)
		reload_target(&lighting.info, w, h)
		reload_target(&lighting.emission, w, h)
		lighting.size = {w, h}
	}
	if lighting.mapSize != {mw, mh} {
		reload_target(&lighting.lightMap, mw, mh)
		reload_target(&lighting.shadow, mw, mh)
		reload_target(&lighting.shadowTmp, mw, mh)
		rl.SetTextureFilter(lighting.lightMap.texture, .BILINEAR)
		rl.SetTextureFilter(lighting.shadow.texture, .BILINEAR)
		rl.SetTextureFilter(lighting.shadowTmp.texture, .BILINEAR)
		lighting.mapSize = {mw, mh}
	}
	return true
}

// Lighting_Unload releases the light map and shaders.
Lighting_Unload :: proc() {
	if !rl.IsWindowReady() do return
	for t in ([?]^rl.RenderTexture2D{&lighting.lightMap, &lighting.shadow, &lighting.shadowTmp, &lighting.normals, &lighting.info, &lighting.emission}) {
		if t.id != 0 do rl.UnloadRenderTexture(t^)
	}
	if lighting.shaderOk {
		rl.UnloadShader(lighting.shader)
		rl.UnloadShader(lighting.blur)
		rl.UnloadShader(lighting.unlit)
	}
	for _, t in lighting.builtins do rl.UnloadTexture(t)
	delete(lighting.builtins)
	enabled, set := lighting.enabled, lighting.enabledSet
	lighting = {}
	lighting.enabled, lighting.enabledSet = enabled, set
}

// --- Occluders ------------------------------------------------------------------------

// Occluder: a world-space outline that blocks light, and whose it is.
Occluder :: struct {
	points: [dynamic][2]f32,
	owner:  ^Node,
	layers: LightLayerSet, // the lights it blocks (bodies: all)
}

// Node_CastsShadows: a body whose shapes block light (Casts Shadows on).
Node_CastsShadows :: proc(n: ^Node) -> bool {
	switch n.typeId {
	case StaticBodyNode:     return (cast(^StaticBodyNode)n).castsShadows
	case DynamicBodyNode:    return (cast(^DynamicBodyNode)n).castsShadows
	case KinematicBodyNode:  return (cast(^KinematicBodyNode)n).castsShadows
	case CharacterMoverNode: return (cast(^CharacterMoverNode)n).castsShadows
	}
	return false
}

// Shape_Outline: a shape's outline in world space (temp-allocated).
Shape_Outline :: proc(n: ^Node, s: ^PhysicsShape) -> [dynamic][2]f32 {
	g := PhysicsShape_Scaled(s, n.globalScale)
	rot := n.globalRotation
	poly := make([dynamic][2]f32, context.temp_allocator)
	to_world :: proc(n: ^Node, g: ^PhysicsShape, rot: f32, q: [2]f32) -> [2]f32 {
		local := g.offset + rotate_vec(q, g.rotation)
		return n.globalPosition + rotate_vec(local, rot)
	}
	#partial switch g.type {
	case .Box, .RoundedBox:
		hw, hh := g.size.x * 0.5, g.size.y * 0.5
		for q in ([4][2]f32{{-hw, -hh}, {hw, -hh}, {hw, hh}, {-hw, hh}}) do append(&poly, to_world(n, &g, rot, q))
	case .Polygon:
		for v in g.vertices[:clamp(g.vertexCount, 3, len(g.vertices))] do append(&poly, to_world(n, &g, rot, v))
	case .Circle, .Capsule:
		half := g.size.y * 0.5 if g.type == .Capsule else 0
		for k in 0 ..< 12 {
			a := f32(k) / 12 * math.TAU
			c := [2]f32{math.cos(a), math.sin(a)} * g.radius
			c.y += half if c.y > 0 else -half
			append(&poly, to_world(n, &g, rot, c))
		}
	case .Segment:
		append(&poly, to_world(n, &g, rot, g.point1), to_world(n, &g, rot, g.point2))
	}
	return poly
}

// Lighting_Occluders: everything that casts shadows now - bodies with
// Casts Shadows (not sensors), Light Occluders, and in the editor (no
// physics yet) the colliders Tile Maps and LDtk levels will build.
Lighting_Occluders :: proc(scene: ^Scene) -> [dynamic]Occluder {
	out := make([dynamic]Occluder, context.temp_allocator)
	if scene == nil || scene.manager == nil do return out
	for n in scene.manager.nodes {
		if n == nil || !n.enabled do continue
		switch n.typeId {
		case StaticBodyNode, DynamicBodyNode, KinematicBodyNode, CharacterMoverNode:
			if !Node_CastsShadows(n) do continue
			for &s in Physics_BodyShapes(n) {
				if s.isSensor do continue
				if poly := Shape_Outline(n, &s); len(poly) >= 2 do append(&out, Occluder{poly, n, ALL_LIGHT_LAYERS})
			}
		case LightOccluderNode:
			o := cast(^LightOccluderNode)n
			for &s in o.shapes {
				if poly := Shape_Outline(n, &s); len(poly) >= 2 do append(&out, Occluder{poly, n, o.layers})
			}
		case TileMapNode, LdtkLevelNode:
			Lighting_EditorColliders(n, &out) // (lighting_nodes.odin)
		}
	}
	return out
}

// Node_IsAncestorOf: a is b's parent, or its parent's, ...
Node_IsAncestorOf :: proc(a, b: ^Node) -> bool {
	if a == nil || b == nil do return false
	for p := b.parent; p != nil; p = p.parent do if p == a do return true
	return false
}

// Light_BlockedBy: the occluder casts shadows for this light.
Light_BlockedBy :: proc(l: ^LightNode, o: ^Occluder) -> bool {
	if o.layers & l.layers == {} do return false
	if l.ignoreParentBodies && Node_IsAncestorOf(o.owner, l) do return false
	return true
}

// --- Light textures (cookies) ----------------------------------------------------------

LIGHT_TEXTURE_BUILTINS :: [?]string{"builtin:ring", "builtin:window", "builtin:blinds", "builtin:noise"}

// Lighting_BuiltinTexture: a built-in light texture (generated once).
Lighting_BuiltinTexture :: proc(name: string) -> (rl.Texture2D, bool) {
	if t, ok := lighting.builtins[name]; ok do return t, true
	if !rl.IsWindowReady() do return {}, false
	N :: 128
	img := rl.GenImageColor(N, N, rl.BLACK)
	px := ([^]rl.Color)(img.data)
	found := true
	for y in 0 ..< N do for x in 0 ..< N {
		u := (f32(x) + 0.5) / N * 2 - 1
		v := (f32(y) + 0.5) / N * 2 - 1
		r := math.sqrt(u * u + v * v)
		val: f32 = 0
		switch name {
		case "builtin:ring":
			// A flashlight's bright ring around a softer middle.
			val = 0.55 + 0.45 * math.exp(-((r - 0.55) * (r - 0.55)) / 0.02)
		case "builtin:window":
			// Four panes with bars between them.
			fx := abs(u) < 0.06 || abs(u) > 0.88
			fy := abs(v) < 0.06 || abs(v) > 0.88
			val = 0 if fx || fy else 1
		case "builtin:blinds":
			// Horizontal slats.
			s := math.mod(v * 6 + 6, 1)
			val = 1 if s < 0.6 else 0.08
		case "builtin:noise":
			// Dappled light through leaves.
			val = 0.35 + 0.65 * clamp(0.5 + 0.5 * math.sin(u * 9 + math.sin(v * 7) * 2) * math.sin(v * 11 + math.cos(u * 5) * 2), 0, 1)
		case:
			found = false
		}
		b := u8(clamp(val, 0, 1) * 255)
		px[y * N + x] = {b, b, b, 255}
	}
	if !found {
		rl.UnloadImage(img)
		return {}, false
	}
	t := rl.LoadTextureFromImage(img)
	rl.UnloadImage(img)
	rl.SetTextureFilter(t, .BILINEAR)
	rl.SetTextureWrap(t, .CLAMP)
	if lighting.builtins == nil do lighting.builtins = make(map[string]rl.Texture2D, allocator = Engine_HeapAllocator())
	lighting.builtins[strings.clone(name, Engine_HeapAllocator())] = t
	return t, true
}

// light_cookie: the light's texture (loaded when its path changes).
@(private = "file")
light_cookie :: proc(l: ^LightNode) -> (rl.Texture2D, bool) {
	if l.texture == "" do return {}, false
	if l.cookieFor != l.texture {
		light_release_cookie(l)
		if l.cookieFor != "" do delete(l.cookieFor)
		l.cookieFor = strings.clone(l.texture)
		l.cookie = {}
		if strings.has_prefix(l.texture, "builtin:") {
			l.cookie, _ = Lighting_BuiltinTexture(l.texture)
		} else if rm := Node_ResourceManager(l); rm != nil {
			path := l.texture
			if ctx := l.gameContext; ctx != nil do path = Project_ResolveAssetPath(ctx, l.texture)
			if t, ok := rm.loadTexture(rm, path); ok && t != nil {
				l.cookie = t.texture
				l.cookieRes = t
			}
		}
	}
	return l.cookie, l.cookie.id != 0
}

@(private = "file")
light_release_cookie :: proc(l: ^LightNode) {
	if l.cookieRes != nil {
		if rm := Node_ResourceManager(l); rm != nil do ResourceManager_ReleaseTexture(rm, l.cookieRes)
		l.cookieRes = nil
	}
}

// --- The light map ---------------------------------------------------------------------

// Lighting_Prepare renders the light map for a camera on a w x h target.
// Call before the frame's own render target is bound (it renders into its
// own textures). Returns false when the scene has no lighting.
Lighting_Prepare :: proc(scene: ^Scene, cam: rl.Camera2D, w, h: i32) -> bool {
	lighting.ready = false
	if !Scene_HasLighting(scene) do return false
	env := Scene_Environment(scene)
	half := env != nil && env.halfResolution
	mw, mh := w, h
	if half do mw, mh = max(w / 2, 1), max(h / 2, 1)
	if !ensure_targets(w, h, mw, mh) do return false
	over := env != nil && env.overbright
	lighting.overbright = over
	scale: f32 = 0.5 if over else 1 // (overbright: stored at half, shown at 2x)
	ambient := Scene_Ambient(scene)
	view := Camera2D_ViewRect(cam, f32(w), f32(h))
	// The light map's camera (half size: the same view at half the pixels).
	mcam := cam
	if half {
		mcam.zoom *= f32(mw) / f32(w)
		mcam.offset *= f32(mw) / f32(w)
	}
	t := rl.GetTime()

	rl.BeginTextureMode(lighting.lightMap)
	rl.ClearBackground(scale_color(ambient, scale))
	rl.EndTextureMode()

	// Normal maps (normal_maps.odin): the world's texture-drawn nodes into
	// the normal buffer, when the project uses them.
	useNormals: f32 = 0
	if Lit_ProjectUsesNormals(scene, Node_ResourceManager(scene.rootNode)) {
		Prof_Scope("lighting.normals")
		rl.BeginTextureMode(lighting.normals)
		rl.ClearBackground({128, 128, 0, 0}) // (flat, matte: lit as without normal maps)
		rl.BeginMode2D(cam)
		if Lit_BeginPass() {
			lighting_draw_world(scene, view)
			Lit_EndPass()
			useNormals = 1
		}
		rl.EndMode2D()
		rl.EndTextureMode()
	}

	// The info pass (lighting_passes.odin): which lights light each pixel,
	// and the unlit ones - when a node or a light uses it.
	needInfo, anyUnlit := Lighting_NeedsInfo(scene)
	useInfo: f32 = 0
	if needInfo && Value_BeginPass(.Info, &lighting.info, cam) {
		Prof_Scope("lighting.info")
		lighting_draw_world(scene, view)
		Value_EndPass()
		useInfo = 1
	}
	// The emission pass: what glows.
	lighting.emitting = false
	if Lighting_NeedsEmission(scene) && Value_BeginPass(.Emission, &lighting.emission, cam) {
		Prof_Scope("lighting.emission")
		lighting_draw_world(scene, view)
		Value_EndPass()
		lighting.emitting = true
	}

	occluders: [dynamic]Occluder
	haveOccluders := false
	texW := rl.Texture2D{id = rlgl.GetTextureIdDefault(), width = 1, height = 1, mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
	for n in scene.manager.nodes {
		if n == nil || n.typeId != LightNode || !n.enabled || !Node_VisibleInTree(n) do continue // (hidden: no light, #388)
		l := cast(^LightNode)n
		if l.layers == {} do continue
		r := l.radius * max(abs(l.globalScale.x), abs(l.globalScale.y))
		e := Light_Energy(l, t)
		if (r <= 0 && l.kind != .Directional) || e <= 0 do continue
		c := l.globalPosition
		sunDir: [3]f32
		sunFar: f32 = 0 // (a sun's shadows: how far)
		if l.kind == .Directional {
			// The sun: shadows as from a light far away against its direction.
			a := math.to_radians(l.globalRotation)
			dir := [2]f32{math.cos(a), math.sin(a)}
			el := math.to_radians(clamp(l.elevation, 1, 90))
			sunDir = {-dir.x * math.cos(el), -dir.y * math.cos(el), math.sin(el)}
			diag := math.sqrt(view.width * view.width + view.height * view.height)
			c = [2]f32{view.x + view.width * 0.5, view.y + view.height * 0.5} - dir * diag * 8
			r = diag * 16
			sunFar = l.shadowLength if l.shadowLength > 0 else diag * 4
		} else if c.x + r < view.x || c.x - r > view.x + view.width || c.y + r < view.y || c.y - r > view.y + view.height do continue

		// Its shadows: a mask (1 = in shadow), blurred when soft.
		useShadow: f32 = 0
		if l.shadows && l.shadowStrength > 0 {
			if !haveOccluders {
				Prof_Scope("lighting.occluders")
				occluders = Lighting_Occluders(scene)
				haveOccluders = true
			}
			Prof_Begin("lighting.shadows")
			far := r * 4
			if l.kind == .Directional do far = sunFar
			if light_shadow_mask(l, c, r, far, occluders[:], mcam) {
				useShadow = 1
				if l.softness > 0 {
					// The blur's reach in light-map pixels.
					px := l.softness * mcam.zoom
					light_blur_shadow(px)
				}
			}
			Prof_End()
		}

		// The light, added to the map.
		Prof_Begin("lighting.light")
		rl.BeginTextureMode(lighting.lightMap)
		rl.BeginBlendMode(.ADDITIVE)
		rl.BeginMode2D(mcam)
		sh := lighting.shader
		rl.BeginShaderMode(sh)
		{
			loc := &lighting.loc
			falloff := max(l.falloff, 0.1)
			spread: f32 = -1
			if l.kind == .Spot do spread = math.cos(math.to_radians(clamp(l.spread, 1, 180)))
			isSun: f32 = 1 if l.kind == .Directional else 0
			ra := math.to_radians(l.globalRotation)
			rot := [2]f32{math.cos(ra), math.sin(ra)}
			rad := r
			hgt := l.height * max(abs(l.globalScale.x), abs(l.globalScale.y))
			un := useNormals
			sz := [2]f32{f32(mw), f32(mh)}
			ss := clamp(l.shadowStrength, 0, 1)
			ui := useInfo
			mask := f32(transmute(u8)l.layers)
			us := useShadow
			rl.SetShaderValue(sh, loc.falloff, &falloff, .FLOAT)
			rl.SetShaderValue(sh, loc.spread, &spread, .FLOAT)
			rl.SetShaderValue(sh, loc.sun, &isSun, .FLOAT)
			rl.SetShaderValue(sh, loc.rot, &rot, .VEC2)
			rl.SetShaderValue(sh, loc.radius, &rad, .FLOAT)
			rl.SetShaderValue(sh, loc.height, &hgt, .FLOAT)
			rl.SetShaderValue(sh, loc.sunDir, &sunDir, .VEC3)
			rl.SetShaderValue(sh, loc.useNormals, &un, .FLOAT)
			rl.SetShaderValue(sh, loc.screenSize, &sz, .VEC2)
			rl.SetShaderValue(sh, loc.useShadow, &us, .FLOAT)
			rl.SetShaderValue(sh, loc.shadowStrength, &ss, .FLOAT)
			rl.SetShaderValue(sh, loc.useInfo, &ui, .FLOAT)
			rl.SetShaderValue(sh, loc.lightMask, &mask, .FLOAT)
			rl.SetShaderValueTexture(sh, loc.normalMap, lighting.normals.texture)
			rl.SetShaderValueTexture(sh, loc.shadowMap, lighting.shadow.texture)
			rl.SetShaderValueTexture(sh, loc.infoMap, lighting.info.texture)
		}
		col := l.color
		k := clamp(e, 0, 8) * scale
		col = {u8(min(f32(col.r) * k, 255)), u8(min(f32(col.g) * k, 255)), u8(min(f32(col.b) * k, 255)), 255}
		// A textured quad (the light texture, else the default white one) so
		// the shader gets UVs.
		tex := texW
		useCookie: f32 = 0
		if l.kind != .Directional {
			if ct, ok := light_cookie(l); ok {
				tex = ct
				useCookie = 1
			}
		}
		rl.SetShaderValue(sh, lighting.loc.useCookie, &useCookie, .FLOAT)
		if l.kind == .Directional do rl.DrawTexturePro(tex, {0, 0, f32(tex.width), f32(tex.height)}, view, {0, 0}, 0, col) // (over the whole view)
		else do rl.DrawTexturePro(tex, {0, 0, f32(tex.width), f32(tex.height)}, {c.x, c.y, r * 2, r * 2}, {r, r}, l.globalRotation, col)
		rl.EndShaderMode()
		rl.EndMode2D()
		rl.EndBlendMode()
		rl.EndTextureMode()
		Prof_End()
	}

	// Ignore Lighting: those pixels at full brightness.
	if useInfo > 0 && anyUnlit {
		rl.BeginTextureMode(lighting.lightMap)
		rlgl.DrawRenderBatchActive()
		rlgl.DisableColorBlend()
		rl.BeginShaderMode(lighting.unlit)
		sz := [2]f32{f32(mw), f32(mh)}
		rl.SetShaderValue(lighting.unlit, lighting.unlitSize, &sz, .VEC2)
		rl.SetShaderValueTexture(lighting.unlit, lighting.unlitInfo, lighting.info.texture)
		full := scale_color({255, 255, 255, 255}, scale)
		rl.DrawRectangle(0, 0, mw, mh, full)
		rl.EndShaderMode()
		rlgl.DrawRenderBatchActive()
		rlgl.EnableColorBlend()
		rl.EndTextureMode()
	}

	lighting.ready = true
	Render_RestoreFrameTarget() // post effects: back to the frame's target
	return true
}

// lighting_draw_world: the camera's world layers (a pass: normal, info,
// emission - the caller set it up).
@(private = "file")
lighting_draw_world :: proc(scene: ^Scene, view: rl.Rectangle) {
	screen: [RenderLayer][dynamic]^Node
	buckets := Scene_CollectRenderables(scene, &screen)
	layers := ~bit_set[RenderLayer]{}
	if scene.camera != nil && scene.camera.targetLayers != {} do layers = scene.camera.targetLayers
	Render_SetView(view)
	Scene_RenderLayers(scene, buckets, scene.rootNode.gameContext if scene.rootNode != nil else nil, layers)
	Render_ClearView()
}

@(private = "file")
scale_color :: proc(c: rl.Color, s: f32) -> rl.Color {
	return {u8(f32(c.r) * s + 0.5), u8(f32(c.g) * s + 0.5), u8(f32(c.b) * s + 0.5), 255}
}

// light_shadow_mask draws one light's shadows into the mask (false: none
// in its reach). Each edge facing the light throws a quad away from it.
@(private = "file")
light_shadow_mask :: proc(l: ^LightNode, c: [2]f32, r, far: f32, occluders: []Occluder, mcam: rl.Camera2D) -> bool {
	any := false
	rl.BeginTextureMode(lighting.shadow)
	rl.ClearBackground(rl.BLACK)
	rl.BeginMode2D(mcam)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	// A closed polygon casts from the edges facing the light only: whatever
	// is behind it is behind the first edge a ray from the light crosses,
	// which faces the light (half the edges, and the polygon itself is
	// covered by them).
	for &o in occluders {
		if !Light_BlockedBy(l, &o) do continue
		poly := o.points[:]
		n := len(poly)
		area: f32 = 0 // twice the signed area: the winding (negative scale flips it)
		inside := false // the light inside the polygon: every edge casts (all dark outside it)
		if n > 2 do for i in 0 ..< n {
			p, q := poly[i], poly[(i + 1) % n]
			area += p.x * q.y - q.x * p.y
			if (p.y > c.y) != (q.y > c.y) && c.x < p.x + (c.y - p.y) / (q.y - p.y) * (q.x - p.x) do inside = !inside
		}
		for i in 0 ..< n {
			if n == 2 && i == 1 do break
			a, b := poly[i], poly[(i + 1) % n]
			if n > 2 && !inside {
				// The light on the edge's inner side: it faces away.
				side := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
				if side * area > 0 do continue
			}
			// Edges out of the light's reach cast nothing.
			if !segment_near(c, a, b, r) do continue
			da := a - c
			db := b - c
			la := math.sqrt(da.x * da.x + da.y * da.y)
			lb := math.sqrt(db.x * db.x + db.y * db.y)
			if la < 0.001 || lb < 0.001 do continue
			a2 := a + da / la * far
			b2 := b + db / lb * far
			rl.DrawTriangle(a, a2, b2, rl.WHITE)
			rl.DrawTriangle(a, b2, b, rl.WHITE)
			any = true
		}
	}
	rlgl.DrawRenderBatchActive() // (drawn with culling off)
	rlgl.EnableBackfaceCulling()
	rl.EndMode2D()
	rl.EndTextureMode()
	return any
}

// light_blur_shadow softens the mask: a separable blur reaching ~px pixels
// (one or two rounds of it for wide ones).
@(private = "file")
light_blur_shadow :: proc(px: f32) {
	if px < 0.5 do return
	rounds := 1 if px <= 8 else 2
	step := px / 4 / f32(rounds)
	m := lighting.shadow.texture
	sz := [2]f32{f32(m.width), f32(m.height)}
	for _ in 0 ..< rounds {
		blur_pass(&lighting.shadow, &lighting.shadowTmp, {step / sz.x, 0})
		blur_pass(&lighting.shadowTmp, &lighting.shadow, {0, step / sz.y})
	}
}

@(private = "file")
blur_pass :: proc(src, dst: ^rl.RenderTexture2D, dir: [2]f32) {
	d := dir
	rl.BeginTextureMode(dst^)
	rl.ClearBackground(rl.BLACK)
	rl.BeginShaderMode(lighting.blur)
	rl.SetShaderValue(lighting.blur, lighting.blurDir, &d, .VEC2)
	t := src.texture
	// (Render textures are upside down: drawn flipped, the copy is the same way up.)
	rl.DrawTextureRec(t, {0, 0, f32(t.width), -f32(t.height)}, {0, 0}, rl.WHITE)
	rl.EndShaderMode()
	rl.EndTextureMode()
}

@(private = "file")
segment_near :: proc(c, a, b: [2]f32, r: f32) -> bool {
	ab := b - a
	l2 := ab.x * ab.x + ab.y * ab.y
	t: f32 = 0
	if l2 > 0 do t = clamp(((c - a).x * ab.x + (c - a).y * ab.y) / l2, 0, 1)
	p := a + ab * t
	d := p - c
	return d.x * d.x + d.y * d.y <= r * r
}

// Lighting_Composite multiplies the light map over what has been drawn
// (screen space, the same w x h as Lighting_Prepare; a half-size map is
// stretched), then adds what glows.
Lighting_Composite :: proc() {
	if !lighting.ready do return
	t := lighting.lightMap.texture
	m := renderPixel.margin // (inside the smooth camera's world texture)
	w, h := f32(lighting.size.x), f32(lighting.size.y)
	if lighting.overbright {
		// dst * src * 2: the map holds half the light.
		rlgl.SetBlendFactors(rlgl.DST_COLOR, rlgl.SRC_COLOR, rlgl.FUNC_ADD)
		rl.BeginBlendMode(.CUSTOM)
	} else {
		rl.BeginBlendMode(.MULTIPLIED)
	}
	rl.DrawTexturePro(t, {0, 0, f32(t.width), -f32(t.height)}, {m, m, w, h}, {0, 0}, 0, rl.WHITE)
	rl.EndBlendMode()
	if lighting.emitting {
		et := lighting.emission.texture
		rl.BeginBlendMode(.ADDITIVE)
		rl.DrawTextureRec(et, {0, 0, f32(et.width), -f32(et.height)}, {m, m}, rl.WHITE)
		rl.EndBlendMode()
	}
	lighting.ready = false
}

// Lighting_LightMapTexture: the last light map (tests, debugging).
Lighting_LightMapTexture :: proc() -> rl.Texture2D {
	return lighting.lightMap.texture
}

// Lighting_InfoTexture / Lighting_EmissionTexture: the last info and
// emission buffers (tests, debugging).
Lighting_InfoTexture :: proc() -> rl.Texture2D {return lighting.info.texture}
Lighting_EmissionTexture :: proc() -> rl.Texture2D {return lighting.emission.texture}

LightNode_KindName :: proc(k: Light_Kind) -> string {
	switch k {
	case .Spot: return "spot"
	case .Directional: return "directional"
	case .Point:
	}
	return "point"
}
