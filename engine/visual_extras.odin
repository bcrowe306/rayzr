package engine

import "core:math"
import "core:strings"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// Visual extras:
//   NineSliceNode  - a texture stretched to any size keeping its borders
//   ParallaxNode   - a background that moves with the camera at a factor,
//                    optionally repeating (and scrolling by itself)
//   LineNode       - a polyline (local points), width, colour, closed
//   TrailNode      - a fading, tapering ribbon behind a moving node
//   PostEffectNode - its Material shader applied to the whole screen
// ============================================================================

// texture_for: (re)load a node's texture when its path changed.
@(private = "file")
texture_for :: proc(node: ^Node, path: string, loaded: ^string, tex: ^^Texture) {
	if path == loaded^ do return
	rm := Node_ResourceManager(node)
	if tex^ != nil && rm != nil do ResourceManager_ReleaseTexture(rm, tex^)
	tex^ = nil
	loaded^ = strings.clone(path, node.allocator)
	if path == "" || rm == nil || !rl.IsWindowReady() do return
	if t, ok := rm.loadTexture(rm, Project_ResolveAssetPath(node.gameContext, path)); ok do tex^ = t
}

@(private = "file")
release_texture :: proc(node: ^Node, tex: ^^Texture) {
	if tex^ != nil {
		if rm := Node_ResourceManager(node); rm != nil do ResourceManager_ReleaseTexture(rm, tex^)
		tex^ = nil
	}
}

// --- NineSliceNode ------------------------------------------------------------------

NineSliceNode :: struct {
	using node:  Node,
	shininess: f32 `gui:"true" min:"0" max:"1"`, // lit: a glint from lights (#274; its image's _s.png too)
	texturePath: string `gui:"true"`,
	size:        [2]f32 `gui:"true" min:"1" max:"4000"`,
	marginsLT:   [2]f32 `gui:"true" min:"0" max:"512"`, // left, top border (texture pixels)
	marginsRB:   [2]f32 `gui:"true" min:"0" max:"512"`, // right, bottom
	tint:        rl.Color `gui:"true"`,
	texture:     ^Texture,
	loadedPath:  string,
}

NineSliceNode_Create :: proc(scene: ^Scene, name: string = "NineSlice", parent: ^Node = nil) -> ^NineSliceNode {
	n := CreateNode(scene.manager, NineSliceNode)
	n.name = strings.clone(name, n.allocator) // owned: callers pass temp strings too
	n.size = {200, 100}
	n.marginsLT = {16, 16}
	n.marginsRB = {16, 16}
	n.tint = rl.WHITE
	n.render = NineSliceNode_Render
	n.onDestroy = proc(node: ^Node, ctx: ^GameContext) {
		n := cast(^NineSliceNode)node
		release_texture(n, &n.texture)
	}
	scene->addNode(n, parent)
	return n
}

NineSliceNode_Render :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	n := cast(^NineSliceNode)node
	texture_for(n, n.texturePath, &n.loadedPath, &n.texture)
	size := n.size * n.globalScale
	origin := size * n.pivot // the origin (node_origin.odin)
	if n.texture == nil {
		// No texture yet: in the editor, a faint box where it goes.
		if Render_EditorView && rl.IsWindowReady() do rl.DrawRectanglePro({n.globalPosition.x, n.globalPosition.y, size.x, size.y}, origin, n.globalRotation, {n.tint.r, n.tint.g, n.tint.b, 60})
		return
	}
	t := n.texture.texture
	info := rl.NPatchInfo{
		source = Texture_Full(n.texture), // (its rectangle on an atlas page)
		left = i32(n.marginsLT.x), top = i32(n.marginsLT.y), right = i32(n.marginsRB.x), bottom = i32(n.marginsRB.y),
		layout = .NINE_PATCH,
	}
	Lit_DrawNPatch(t, info, {n.globalPosition.x, n.globalPosition.y, size.x, size.y}, origin, n.globalRotation, n.tint)
}

// --- ParallaxNode --------------------------------------------------------------------

ParallaxNode :: struct {
	using node:  Node,
	texturePath: string `gui:"true"`,
	factor:      [2]f32 `gui:"true" min:"0" max:"2"`, // 1 = moves with the world, 0 = fixed on screen
	repeatX:     bool `gui:"true"`,
	repeatY:     bool `gui:"true"`,
	scrollSpeed: [2]f32 `gui:"true" min:"-1000" max:"1000"`, // drifts by itself (px/s; clouds)
	tint:        rl.Color `gui:"true"`,
	scroll:      [2]f32,
	texture:     ^Texture,
	loadedPath:  string,
}

ParallaxNode_Create :: proc(scene: ^Scene, name: string = "Parallax", parent: ^Node = nil) -> ^ParallaxNode {
	p := CreateNode(scene.manager, ParallaxNode)
	p.name = strings.clone(name, p.allocator) // owned: callers pass temp strings too
	p.factor = {0.5, 0.5}
	p.repeatX = true
	p.tint = rl.WHITE
	p.layer = .Layer1 // backgrounds
	p.update = proc(node: ^Node, ctx: ^GameContext, dt: f32) {
		p := cast(^ParallaxNode)node
		p.scroll += p.scrollSpeed * dt
	}
	p.render = ParallaxNode_Render
	p.onDestroy = proc(node: ^Node, ctx: ^GameContext) {
		p := cast(^ParallaxNode)node
		release_texture(p, &p.texture)
	}
	scene->addNode(p, parent)
	return p
}

// ParallaxNode_Offset: how far the layer is shifted for a camera centre.
ParallaxNode_Offset :: proc(p: ^ParallaxNode, camera: [2]f32) -> [2]f32 {
	return camera * (1 - p.factor) + p.scroll
}

ParallaxNode_Render :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	p := cast(^ParallaxNode)node
	texture_for(p, p.texturePath, &p.loadedPath, &p.texture)
	if p.texture == nil || !rl.IsWindowReady() do return
	t := p.texture.texture
	ts := Texture_Size(p.texture)
	src := Texture_Full(p.texture) // (tiles are drawn one by one: an atlas page works too)
	view := renderView.rect if renderView.active else rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
	cam := [2]f32{view.x + view.width * 0.5, view.y + view.height * 0.5}
	scale := [2]f32{abs(p.globalScale.x), abs(p.globalScale.y)}
	w, h := ts.x * scale.x, ts.y * scale.y
	if w <= 0 || h <= 0 do return
	origin := p.globalPosition + ParallaxNode_Offset(p, cam)
	x0, x1, y0, y1 := 0, 1, 0, 1
	if p.repeatX {
		x0 = int(math.floor((view.x - origin.x) / w))
		x1 = int(math.floor((view.x + view.width - origin.x) / w)) + 1
	}
	if p.repeatY {
		y0 = int(math.floor((view.y - origin.y) / h))
		y1 = int(math.floor((view.y + view.height - origin.y) / h)) + 1
	}
	if (x1 - x0) * (y1 - y0) > 4096 do return // absurdly small tiles
	for y in y0 ..< y1 do for x in x0 ..< x1 {
		rl.DrawTexturePro(t, src, {origin.x + f32(x) * w, origin.y + f32(y) * h, w, h}, {0, 0}, 0, p.tint)
	}
}

// --- LineNode ---------------------------------------------------------------------

LineNode :: struct {
	using node: Node,
	points:     [dynamic][2]f32, // local to the node
	width:      f32 `gui:"true" min:"0.5" max:"100"`,
	color:      rl.Color `gui:"true"`,
	closed:     bool `gui:"true"`,
	rounded:    bool `gui:"true"`, // round joints and caps
}

LineNode_Create :: proc(scene: ^Scene, name: string = "Line", parent: ^Node = nil) -> ^LineNode {
	l := CreateNode(scene.manager, LineNode)
	l.name = strings.clone(name, l.allocator) // owned: callers pass temp strings too
	l.points = make([dynamic][2]f32, l.allocator)
	append(&l.points, [2]f32{-60, 0}, [2]f32{60, 0})
	l.width = 4
	l.color = rl.WHITE
	l.rounded = true
	l.render = LineNode_Render
	scene->addNode(l, parent)
	return l
}

LineNode_WorldPoint :: proc(l: ^LineNode, i: int) -> [2]f32 {
	return l.globalPosition + rotate_vec(l.points[i] * l.globalScale, l.globalRotation)
}

LineNode_Render :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	l := cast(^LineNode)node
	if len(l.points) < 2 || !rl.IsWindowReady() do return
	w := l.width * max(abs(l.globalScale.x), abs(l.globalScale.y))
	n := len(l.points)
	segs := n if l.closed else n - 1
	for i in 0 ..< segs {
		a, b := LineNode_WorldPoint(l, i), LineNode_WorldPoint(l, (i + 1) % n)
		rl.DrawLineEx(a, b, w, l.color)
	}
	if l.rounded {
		for i in 0 ..< n do rl.DrawCircleV(LineNode_WorldPoint(l, i), w * 0.5, l.color)
	}
}

// --- TrailNode --------------------------------------------------------------------

Trail_Point :: struct {
	pos: [2]f32,
	age: f32,
}

TrailNode :: struct {
	using node:  Node,
	lifetime:    f32 `gui:"true" min:"0.05" max:"10"`, // seconds a point lasts
	width:       f32 `gui:"true" min:"0.5" max:"200"`,
	color:       rl.Color `gui:"true"`,
	endColor:    rl.Color `gui:"true"`, // at the tail (fades to it)
	minDistance: f32 `gui:"true" min:"0.5" max:"100"`, // between recorded points
	emitting:    bool `gui:"true"`,
	trail:       [dynamic]Trail_Point,
}

TRAIL_MAX_POINTS :: 512

TrailNode_Create :: proc(scene: ^Scene, name: string = "Trail", parent: ^Node = nil) -> ^TrailNode {
	t := CreateNode(scene.manager, TrailNode)
	t.name = strings.clone(name, t.allocator) // owned: callers pass temp strings too
	t.lifetime = 0.5
	t.width = 12
	t.color = {255, 255, 255, 220}
	t.endColor = {255, 255, 255, 0}
	t.minDistance = 4
	t.emitting = true
	t.trail = make([dynamic]Trail_Point, t.allocator)
	t.update = TrailNode_Update
	t.render = TrailNode_Render
	scene->addNode(t, parent)
	return t
}

TrailNode_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	t := cast(^TrailNode)node
	for &p in t.trail do p.age += dt
	// Expired points leave from the tail (the oldest first).
	cut := 0
	for cut < len(t.trail) && t.trail[cut].age >= t.lifetime do cut += 1
	if cut > 0 do remove_range(&t.trail, 0, cut)
	if !t.emitting do return
	pos := t.globalPosition
	if n := len(t.trail); n == 0 || linalg_distance(t.trail[n - 1].pos, pos) >= t.minDistance {
		append(&t.trail, Trail_Point{pos, 0})
		if len(t.trail) > TRAIL_MAX_POINTS do ordered_remove(&t.trail, 0)
	}
}

@(private = "file")
linalg_distance :: proc(a, b: [2]f32) -> f32 {
	d := a - b
	return math.sqrt(d.x * d.x + d.y * d.y)
}

// TrailNode_Clear forgets the trail (after a teleport).
TrailNode_Clear :: proc(t: ^TrailNode) {clear(&t.trail)}

TrailNode_Render :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	t := cast(^TrailNode)node
	n := len(t.trail)
	if n < 2 || !rl.IsWindowReady() do return
	// A strip: each point has two vertices across the direction of travel;
	// width and colour follow the point's age (head: full, tail: thin and endColor).
	lerp_col :: proc(a, b: rl.Color, k: f32) -> rl.Color {
		return {u8(f32(a.r) + (f32(b.r) - f32(a.r)) * k), u8(f32(a.g) + (f32(b.g) - f32(a.g)) * k), u8(f32(a.b) + (f32(b.b) - f32(a.b)) * k), u8(f32(a.a) + (f32(b.a) - f32(a.a)) * k)}
	}
	side :: proc(trail: []Trail_Point, i: int) -> [2]f32 {
		a := trail[max(i - 1, 0)].pos
		b := trail[min(i + 1, len(trail) - 1)].pos
		d := b - a
		l := math.sqrt(d.x * d.x + d.y * d.y)
		if l < 0.0001 do return {0, 0}
		return {-d.y / l, d.x / l}
	}
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	rlgl.Begin(rlgl.TRIANGLES)
	for i in 0 ..< n - 1 {
		p0, p1 := t.trail[i], t.trail[i + 1]
		k0, k1 := clamp(p0.age / t.lifetime, 0, 1), clamp(p1.age / t.lifetime, 0, 1)
		w0, w1 := t.width * 0.5 * (1 - k0), t.width * 0.5 * (1 - k1)
		s0, s1 := side(t.trail[:], i), side(t.trail[:], i + 1)
		c0, c1 := lerp_col(t.color, t.endColor, k0), lerp_col(t.color, t.endColor, k1)
		a, b := p0.pos + s0 * w0, p0.pos - s0 * w0
		c, d := p1.pos + s1 * w1, p1.pos - s1 * w1
		vtx :: proc(p: [2]f32, col: rl.Color) {
			rlgl.Color4ub(col.r, col.g, col.b, col.a)
			rlgl.TexCoord2f(0, 0)
			rlgl.Vertex2f(p.x, p.y)
		}
		// Both windings (the strip may face either way).
		vtx(a, c0); vtx(b, c0); vtx(c, c1)
		vtx(b, c0); vtx(d, c1); vtx(c, c1)
		vtx(a, c0); vtx(c, c1); vtx(b, c0)
		vtx(b, c0); vtx(c, c1); vtx(d, c1)
	}
	rlgl.End()
	rlgl.SetTexture(0)
}

// --- PostEffectNode ------------------------------------------------------------------

// PostEffectNode: its Material (shader + parameters) is applied to the
// whole screen after the scene draws (several chain in tree order). The
// built-in vignette / crt / pixelate / chromatic shaders are made for it.
PostEffectNode :: struct {
	using node: Node,
}

PostEffectNode_Create :: proc(scene: ^Scene, name: string = "PostEffect", parent: ^Node = nil) -> ^PostEffectNode {
	p := CreateNode(scene.manager, PostEffectNode)
	p.name = strings.clone(name, p.allocator) // owned: callers pass temp strings too
	Material_SetShader(p, "builtin:vignette")
	scene->addNode(p, parent)
	return p
}

// Scene_PostEffects: the enabled post effects with a shader, in tree order.
Scene_PostEffects :: proc(scene: ^Scene) -> []^Node {
	out := make([dynamic]^Node, context.temp_allocator)
	if scene == nil || scene.manager == nil do return out[:]
	walk :: proc(m: ^NodeManager, n: ^Node, out: ^[dynamic]^Node) {
		if n == nil || !n.enabled do return
		if n.typeId == PostEffectNode && n.material != nil && n.material.shader != "" do append(out, n)
		for c in GetChildrenView(m, n) do walk(m, c, out)
	}
	walk(scene.manager, scene.rootNode, &out)
	return out[:]
}

@(private = "file")
post: struct {
	targets: [2]rl.RenderTexture2D,
	size:    [2]i32,
}

// Post_EnsureTargets: the two render textures effects ping-pong between.
Post_EnsureTargets :: proc(w, h: i32) -> bool {
	if w <= 0 || h <= 0 || !rl.IsWindowReady() do return false
	if post.size != {w, h} {
		for t in post.targets do if t.id != 0 do rl.UnloadRenderTexture(t)
		for &t in post.targets {
			t = rl.LoadRenderTexture(w, h)
			rl.SetTextureFilter(t.texture, .BILINEAR)
		}
		post.size = {w, h}
	}
	return true
}

Post_Target :: proc(i: int) -> ^rl.RenderTexture2D {return &post.targets[i]}

Post_Unload :: proc() {
	if rl.IsWindowReady() do for t in post.targets do if t.id != 0 do rl.UnloadRenderTexture(t)
	post = {}
}

// Post_Apply draws `src` through the effects: all but the last into the
// ping-pong targets, the last to whatever target is bound when it returns
// (the caller binds it). Returns the texture to draw with the last effect.
Post_Apply :: proc(effects: []^Node, src: rl.Texture2D, ctx: ^GameContext) -> rl.Texture2D {
	cur := src
	for e, i in effects[:max(len(effects) - 1, 0)] {
		dst := &post.targets[1] if cur.id == post.targets[0].texture.id else &post.targets[0]
		rl.BeginTextureMode(dst^)
		rl.ClearBackground({0, 0, 0, 0})
		Post_DrawWith(e, cur, ctx)
		rl.EndTextureMode()
		cur = dst.texture
	}
	return cur
}

// Post_Process runs the whole chain into the ping-pong targets (sized like
// src) and returns the result (the editor's viewport).
Post_Process :: proc(effects: []^Node, src: rl.Texture2D, ctx: ^GameContext) -> rl.Texture2D {
	if len(effects) == 0 || !Post_EnsureTargets(src.width, src.height) do return src
	cur := Post_Apply(effects, src, ctx)
	dst := &post.targets[1] if cur.id == post.targets[0].texture.id else &post.targets[0]
	rl.BeginTextureMode(dst^)
	rl.ClearBackground({0, 0, 0, 0})
	Post_DrawWith(effects[len(effects) - 1], cur, ctx)
	rl.EndTextureMode()
	return dst.texture
}

// Post_DrawWith draws a frame texture (flipped: render textures are upside
// down) to the current target through an effect's material.
Post_DrawWith :: proc(effect: ^Node, tex: rl.Texture2D, ctx: ^GameContext) {
	w, h := f32(tex.width), f32(tex.height)
	active := effect != nil && Material_Begin(effect, ctx)
	rl.DrawTextureRec(tex, {0, 0, w, -h}, {0, 0}, rl.WHITE)
	if active do Material_End(effect)
}

// --- the frame's render target (post effects) ---------------------------------------
// Passes that render into their own textures mid-frame (light map, tile
// chunks) put this target back when done: render textures don't nest.

@(private = "file")
frameTarget: ^rl.RenderTexture2D

Render_SetFrameTarget :: proc(t: ^rl.RenderTexture2D) {frameTarget = t}

Render_FrameTarget :: proc() -> ^rl.RenderTexture2D {return frameTarget}

Render_RestoreFrameTarget :: proc() {
	if frameTarget != nil do rl.BeginTextureMode(frameTarget^)
}

// Render_MakeOpaque sets the alpha of the render texture being drawn to 1,
// its colours untouched. Alpha blending (SRC_ALPHA, ONE_MINUS_SRC_ALPHA on
// all four channels) lowers the texture's own alpha under soft edges
// (anti-aliased circles, sprites' edges): shown with blending over something
// dark (the editor's panel, the runner's black letterbox), they got a dark
// rim. For frames meant to be opaque, before EndTextureMode.
Render_MakeOpaque :: proc(width, height: f32) {
	rlgl.DrawRenderBatchActive()
	rlgl.SetBlendFactorsSeparate(rlgl.ZERO, rlgl.ONE, rlgl.ONE, rlgl.ZERO, rlgl.FUNC_ADD, rlgl.FUNC_ADD)
	rl.BeginBlendMode(.CUSTOM_SEPARATE)
	rlgl.PushMatrix()
	rlgl.LoadIdentity() // (the texture's own pixels: not through a camera)
	rl.DrawRectangleRec({0, 0, width, height}, rl.WHITE)
	rlgl.PopMatrix()
	rl.EndBlendMode()
}
