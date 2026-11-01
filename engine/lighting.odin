package engine

import "core:strings"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// 2D lighting.
//
// LightNode: a point light or a spot cone (rotation = direction) with a
// colour, energy, radius and falloff, optionally casting shadows from the
// scene's physics shapes (StaticBody / DynamicBody / CharacterMover,
// sensors excluded - so LDtk and tile map colliders cast shadows too).
//
// When a scene has lights (or a non-white ambient), a light map is built
// each frame: cleared to the scene's ambient colour, each light added on
// top (its shadows cut out of its own contribution), then multiplied over
// the world layers. UI layers aren't lit.
//
// Order: Lighting_Prepare (before the frame's drawing target is set up:
// it renders into its own render texture), the scene's world layers, then
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
	shadows: bool `gui:"true"`,
	height:    f32 `gui:"true" min:"0" max:"2000"`, // above the ground (px): low lights rake across normal maps, high ones light flat (#274)
	elevation: f32 `gui:"true" min:"1" max:"90"`,   // Directional: the sun's angle above the ground (degrees)
	shadowLength: f32 `gui:"true" min:"0" max:"4000"`, // Directional: how far shadows reach (px; 0 = no end)
}

LightNode_Create :: proc(scene: ^Scene, name: string = "Light", parent: ^Node = nil) -> ^LightNode {
	l := CreateNode(scene.manager, LightNode)
	l.name = strings.clone(name, l.allocator) // owned: callers pass temp strings too
	l.color = {255, 236, 200, 255}
	l.energy = 1
	l.radius = 256
	l.falloff = 2
	l.spread = 35
	l.shadows = true
	l.height = 64
	l.elevation = 45
	l.shadowLength = 120
	scene->addNode(l, parent)
	return l
}

@(private = "file")
LIGHT_SHADER :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;
uniform float falloff;
uniform float spread;   // cos of the cone half-angle (-1 = point light)
uniform float sun;      // 1: a directional light (sunDir), the quad covers the view
uniform vec2 rot;       // the light's rotation (cos, sin)
uniform float radius;
uniform float height;
uniform vec3 sunDir;    // towards the sun
uniform float useNormals;
uniform sampler2D normalMap; // the normal pass (normal_maps.odin): xy, specular, normal-mapped
uniform vec2 screenSize;
void main() {
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
    float lit = 1.0;
    float spec = 0.0;
    if (useNormals > 0.5) {
        vec4 nm = texture(normalMap, gl_FragCoord.xy / screenSize);
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
    finalColor = vec4(fragColor.rgb * a * fragColor.a * (lit + spec), 1.0);
}
`

@(private = "file")
lighting: struct {
	shader:     rl.Shader,
	shaderOk:   bool,
	locFalloff: i32,
	locSpread:  i32,
	loc:        struct {sun, rot, radius, height, sunDir, useNormals, normalMap, screenSize: i32},
	lightMap:   rl.RenderTexture2D,
	normals:    rl.RenderTexture2D, // the normal pass (normal_maps.odin)
	scratch:    rl.RenderTexture2D, // one light at a time (with its shadows)
	size:       [2]i32,
	ready:      bool, // a light map was prepared this frame
}

// Scene_HasLighting: lights, or an ambient that isn't white.
Scene_HasLighting :: proc(scene: ^Scene) -> bool {
	if scene == nil || scene.manager == nil do return false
	if scene.ambient != {} && scene.ambient != {255, 255, 255, 255} do return true
	for n in scene.manager.nodes do if n != nil && n.typeId == LightNode && n.enabled do return true
	return false
}

@(private = "file")
ensure_targets :: proc(w, h: i32) -> bool {
	if !rl.IsWindowReady() || w <= 0 || h <= 0 do return false
	if !lighting.shaderOk {
		lighting.shader = rl.LoadShaderFromMemory(nil, Shader_Port(LIGHT_SHADER))
		if !rl.IsShaderValid(lighting.shader) do return false
		lighting.locFalloff = rl.GetShaderLocation(lighting.shader, "falloff")
		lighting.locSpread = rl.GetShaderLocation(lighting.shader, "spread")
		sh := lighting.shader
		lighting.loc = {rl.GetShaderLocation(sh, "sun"), rl.GetShaderLocation(sh, "rot"), rl.GetShaderLocation(sh, "radius"), rl.GetShaderLocation(sh, "height"), rl.GetShaderLocation(sh, "sunDir"), rl.GetShaderLocation(sh, "useNormals"), rl.GetShaderLocation(sh, "normalMap"), rl.GetShaderLocation(sh, "screenSize")}
		lighting.shaderOk = true
	}
	if lighting.size != {w, h} {
		if lighting.lightMap.id != 0 {
			rl.UnloadRenderTexture(lighting.lightMap)
			rl.UnloadRenderTexture(lighting.scratch)
			rl.UnloadRenderTexture(lighting.normals)
		}
		lighting.lightMap = rl.LoadRenderTexture(w, h)
		lighting.scratch = rl.LoadRenderTexture(w, h)
		lighting.normals = rl.LoadRenderTexture(w, h)
		lighting.size = {w, h}
	}
	return true
}

// Lighting_Unload releases the light map and shader.
Lighting_Unload :: proc() {
	if !rl.IsWindowReady() do return
	if lighting.lightMap.id != 0 {
		rl.UnloadRenderTexture(lighting.lightMap)
		rl.UnloadRenderTexture(lighting.scratch)
		rl.UnloadRenderTexture(lighting.normals)
	}
	if lighting.shaderOk do rl.UnloadShader(lighting.shader)
	lighting = {}
}

// occluder_polygons: world-space outlines of the shapes that cast shadows.
@(private = "file")
occluder_polygons :: proc(scene: ^Scene) -> [dynamic][dynamic][2]f32 {
	out := make([dynamic][dynamic][2]f32, context.temp_allocator)
	for n in scene.manager.nodes {
		if n == nil || !n.enabled do continue
		shapes: []PhysicsShape
		switch n.typeId {
		case StaticBodyNode:     shapes = (cast(^StaticBodyNode)n).shapes[:]
		case DynamicBodyNode:    shapes = (cast(^DynamicBodyNode)n).shapes[:]
		case KinematicBodyNode:  shapes = (cast(^KinematicBodyNode)n).shapes[:]
		case CharacterMoverNode: shapes = (cast(^CharacterMoverNode)n).shapes[:]
		}
		for &s in shapes {
			if s.isSensor do continue
			g := PhysicsShape_Scaled(&s, n.globalScale)
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
			if len(poly) >= 2 do append(&out, poly)
		}
	}
	return out
}

// Lighting_Prepare renders the light map for a camera on a w x h target.
// Call before the frame's own render target is bound (it renders into its
// own textures). Returns false when the scene has no lighting.
Lighting_Prepare :: proc(scene: ^Scene, cam: rl.Camera2D, w, h: i32) -> bool {
	lighting.ready = false
	if !Scene_HasLighting(scene) || !ensure_targets(w, h) do return false
	ambient := scene.ambient if scene.ambient != {} else rl.Color{255, 255, 255, 255}
	view := Camera2D_ViewRect(cam, f32(w), f32(h))
	occluders: [dynamic][dynamic][2]f32
	haveOccluders := false

	rl.BeginTextureMode(lighting.lightMap)
	rl.ClearBackground(ambient)
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
			screen: [RenderLayer][dynamic]^Node
			buckets := Scene_CollectRenderables(scene, &screen)
			layers := ~bit_set[RenderLayer]{}
			if scene.camera != nil && scene.camera.targetLayers != {} do layers = scene.camera.targetLayers
			Render_SetView(view)
			Scene_RenderLayers(scene, buckets, scene.rootNode.gameContext if scene.rootNode != nil else nil, layers)
			Render_ClearView()
			Lit_EndPass()
			useNormals = 1
		}
		rl.EndMode2D()
		rl.EndTextureMode()
	}

	for n in scene.manager.nodes {
		if n == nil || n.typeId != LightNode || !n.enabled do continue
		l := cast(^LightNode)n
		r := l.radius * max(abs(l.globalScale.x), abs(l.globalScale.y))
		if (r <= 0 && l.kind != .Directional) || l.energy <= 0 do continue
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

		// The light on its own target, shadows cut out, then added to the map.
		Prof_Begin("lighting.light")
		rl.BeginTextureMode(lighting.scratch)
		rl.ClearBackground(rl.BLACK)
		rl.BeginMode2D(cam)
		rl.BeginShaderMode(lighting.shader)
		falloff := max(l.falloff, 0.1)
		spread: f32 = -1
		if l.kind == .Spot do spread = math.cos(math.to_radians(clamp(l.spread, 1, 180)))
		rl.SetShaderValue(lighting.shader, lighting.locFalloff, &falloff, .FLOAT)
		rl.SetShaderValue(lighting.shader, lighting.locSpread, &spread, .FLOAT)
		{
			sh := lighting.shader
			isSun: f32 = 1 if l.kind == .Directional else 0
			ra := math.to_radians(l.globalRotation)
			rot := [2]f32{math.cos(ra), math.sin(ra)}
			rad := r
			hgt := l.height * max(abs(l.globalScale.x), abs(l.globalScale.y))
			un := useNormals
			sz := [2]f32{f32(w), f32(h)}
			rl.SetShaderValue(sh, lighting.loc.sun, &isSun, .FLOAT)
			rl.SetShaderValue(sh, lighting.loc.rot, &rot, .VEC2)
			rl.SetShaderValue(sh, lighting.loc.radius, &rad, .FLOAT)
			rl.SetShaderValue(sh, lighting.loc.height, &hgt, .FLOAT)
			rl.SetShaderValue(sh, lighting.loc.sunDir, &sunDir, .VEC3)
			rl.SetShaderValue(sh, lighting.loc.useNormals, &un, .FLOAT)
			rl.SetShaderValue(sh, lighting.loc.screenSize, &sz, .VEC2)
			rl.SetShaderValueTexture(sh, lighting.loc.normalMap, lighting.normals.texture)
		}
		col := l.color
		e := clamp(l.energy, 0, 8)
		col = {u8(min(f32(col.r) * e, 255)), u8(min(f32(col.g) * e, 255)), u8(min(f32(col.b) * e, 255)), 255}
		// A textured quad (default white texture) so the shader gets UVs.
		tex := rl.Texture2D{id = rlgl.GetTextureIdDefault(), width = 1, height = 1, mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
		if l.kind == .Directional do rl.DrawTexturePro(tex, {0, 0, 1, 1}, view, {0, 0}, 0, col) // (over the whole view)
		else do rl.DrawTexturePro(tex, {0, 0, 1, 1}, {c.x, c.y, r * 2, r * 2}, {r, r}, l.globalRotation, col)
		rl.EndShaderMode()
		Prof_End()
		if l.shadows {
			if !haveOccluders {
				Prof_Scope("lighting.occluders")
				occluders = occluder_polygons(scene)
				haveOccluders = true
			}
			Prof_Begin("lighting.shadows")
			// Each shadow quad is drawn once, culling off (either winding).
			// A closed polygon casts from the edges facing the light only:
			// whatever is behind it is behind the first edge a ray from the
			// light crosses, which faces the light (half the edges, and the
			// polygon itself is covered by them).
			rlgl.DrawRenderBatchActive()
			rlgl.DisableBackfaceCulling()
			far := r * 4
			if l.kind == .Directional do far = sunFar
			for poly in occluders {
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
					rl.DrawTriangle(a, a2, b2, rl.BLACK)
					rl.DrawTriangle(a, b2, b, rl.BLACK)
				}
			}
			rlgl.DrawRenderBatchActive() // (drawn with culling off)
			rlgl.EnableBackfaceCulling()
			Prof_End()
		}
		Prof_Begin("lighting.accumulate")
		rl.EndMode2D()
		rl.EndTextureMode()

		rl.BeginTextureMode(lighting.lightMap)
		rl.BeginBlendMode(.ADDITIVE)
		st := lighting.scratch.texture
		rl.DrawTextureRec(st, {0, 0, f32(st.width), -f32(st.height)}, {0, 0}, rl.WHITE)
		rl.EndBlendMode()
		rl.EndTextureMode()
		Prof_End()
	}
	lighting.ready = true
	Render_RestoreFrameTarget() // post effects: back to the frame's target
	return true
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
// (screen space, the same w x h as Lighting_Prepare).
Lighting_Composite :: proc() {
	if !lighting.ready do return
	t := lighting.lightMap.texture
	rl.BeginBlendMode(.MULTIPLIED)
	m := renderPixel.margin // (inside the smooth camera's world texture)
	rl.DrawTextureRec(t, {0, 0, f32(t.width), -f32(t.height)}, {m, m}, rl.WHITE)
	rl.EndBlendMode()
	lighting.ready = false
}

// Lighting_LightMapTexture: the last light map (tests, debugging).
Lighting_LightMapTexture :: proc() -> rl.Texture2D {
	return lighting.lightMap.texture
}

LightNode_KindName :: proc(k: Light_Kind) -> string {
	switch k {
	case .Spot: return "spot"
	case .Directional: return "directional"
	case .Point:
	}
	return "point"
}
