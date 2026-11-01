package engine

import "core:c"
import "core:fmt"
import os "osx"
import "core:path/filepath"
import "core:strings"
import lua "lua54"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// Viewport (#279): draws a view into a texture of its own - minimaps,
// split-screen, picture-in-picture, in-world screens, portals.
//
//   World:    the running scene through the viewport's Camera child (its
//             follow target, zoom, limits) - or, with none, around the
//             viewport. Only world layers; never Screen Layers.
//   Children: only the viewport's own children, as a world of their own
//             (they still update with the game; just their drawing goes
//             into the texture, and nowhere else).
//
// The picture renders at Render Size and is drawn (Display) stretched to
// Size. Other things use it by the path "viewport:<name>": a Sprite's
// texture, a material's texture parameter, node:get_texture() in Lua.
// It's stored the right way up (a second copy of the render), so shaders
// and saved PNGs see it as drawn.
//
// Viewports render before the frame (RunScene; the editor's view too, for
// a live preview), deepest first so a viewport inside another is ready.
// ============================================================================

Viewport_Mode :: enum u8 {
	World,    // the scene through its Camera child
	Children, // its own children only
}

Viewport_Update :: enum u8 {
	Every_Frame,  // redrawn every frame
	When_Visible, // skipped while hidden or (displayed) off screen
	Once,         // drawn once; node:refresh() redraws it
}

ViewportNode :: struct {
	using node:   Node,
	mode:         Viewport_Mode `gui:"true"`,
	size:         [2]f32 `gui:"true" min:"1" max:"8192"`, // drawn at this size (Display)
	renderSize:   [2]f32 `gui:"true" min:"0" max:"8192"`, // rendered at this many pixels ({0, 0}: Size)
	updateMode:   Viewport_Update `gui:"true"`,
	display:      bool `gui:"true"`,      // draws its picture where it stands
	coversScreen: bool `gui:"true"`,      // World: the main view isn't drawn (split-screen)
	pixelated:    bool `gui:"true"`,      // scaled nearest-neighbour (pixel art)
	background:   rl.Color `gui:"true"`,  // {} = the scene's background (World) / clear (Children)
	target:       rl.RenderTexture2D,    // where it renders (upside down)
	output:       rl.RenderTexture2D,    // the picture, the right way up
	dirty:        bool,                  // Once: render again
	rendered:     bool,                  // has a picture
}

ViewportNode_Create :: proc(scene: ^Scene, name: string = "Viewport", parent: ^Node = nil) -> ^ViewportNode {
	v := CreateNode(scene.manager, ViewportNode)
	ViewportNode_Init(v)
	v.name = strings.clone(name, v.allocator)
	scene->addNode(v, parent)
	return v
}

ViewportNode_Init :: proc(v: ^ViewportNode) {
	v.size = {320, 180}
	v.display = true
	v.pivot = {0, 0}
	v.render = ViewportNode_Render
	v.onDestroy = ViewportNode_Destroy
}

ViewportNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	v := cast(^ViewportNode)node
	viewport_unload(v)
}

@(private = "file")
viewport_unload :: proc(v: ^ViewportNode) {
	if v.target.id != 0 do rl.UnloadRenderTexture(v.target)
	if v.output.id != 0 do rl.UnloadRenderTexture(v.output)
	v.target, v.output = {}, {}
	v.rendered = false
}

// ViewportNode_RenderSize: the texture's size in pixels.
ViewportNode_RenderSize :: proc(v: ^ViewportNode) -> [2]i32 {
	s := v.renderSize if v.renderSize.x >= 1 && v.renderSize.y >= 1 else v.size
	return {max(i32(s.x + 0.5), 1), max(i32(s.y + 0.5), 1)}
}

// ViewportNode_Texture: the picture (id 0: none yet).
ViewportNode_Texture :: proc(v: ^ViewportNode) -> rl.Texture2D {
	if v == nil || !v.rendered do return {}
	return v.output.texture
}

// ViewportNode_Refresh: a Once viewport renders again next frame.
ViewportNode_Refresh :: proc(v: ^ViewportNode) {v.dirty = true}

// ViewportNode_Camera: its Camera child (nil: none).
ViewportNode_Camera :: proc(v: ^ViewportNode) -> ^CameraNode {
	if v.gameContext == nil || v.gameContext.scene == nil || v.gameContext.scene.manager == nil do return nil
	for c in GetChildrenView(v.gameContext.scene.manager, v) do if c != nil && c.typeId == CameraNode && c.enabled do return cast(^CameraNode)c
	return nil
}

// ViewportNode_Rect: where it's drawn (its layer's space).
ViewportNode_Rect :: proc(v: ^ViewportNode) -> rl.Rectangle {
	size := v.size * v.globalScale
	origin := Node_OriginPx(v, v.size) * v.globalScale
	return rect_aabb(v.globalPosition, {abs(size.x), abs(size.y)}, {abs(origin.x), abs(origin.y)}, v.globalRotation)
}

ViewportNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	v := cast(^ViewportNode)node
	if !v.display || !rl.IsWindowReady() || viewportRendering == v do return
	tex := ViewportNode_Texture(v)
	defer if Render_EditorView do rl.DrawRectangleLinesEx(ViewportNode_Rect(v), 1, {125, 211, 252, 200}) // (the editor: its frame)
	if tex.id == 0 do return
	rl.SetTextureFilter(tex, .POINT if v.pixelated else .BILINEAR)
	origin := Node_OriginPx(v, v.size)
	Texture_DrawScaled(tex, {0, 0, f32(tex.width), f32(tex.height)}, v.globalPosition, v.size, v.globalScale, origin, v.globalRotation, rl.WHITE)
}

// ----------------------------------------------------------------------------
// Finding a viewport by its path ("viewport:<name>")
// ----------------------------------------------------------------------------

VIEWPORT_PREFIX :: "viewport:"

Viewport_IsPath :: proc(path: string) -> bool {return strings.has_prefix(path, VIEWPORT_PREFIX)}

Viewport_Path :: proc(v: ^ViewportNode, allocator := context.temp_allocator) -> string {
	return strings.concatenate({VIEWPORT_PREFIX, v.name}, allocator)
}

// Viewport_Find: the viewport a "viewport:<name>" path names, in the scene.
Viewport_Find :: proc(scene: ^Scene, path: string) -> ^ViewportNode {
	if scene == nil || scene.manager == nil || !Viewport_IsPath(path) do return nil
	name := path[len(VIEWPORT_PREFIX):]
	for n in scene.manager.nodes do if n != nil && n.typeId == ViewportNode && n.name == name do return cast(^ViewportNode)n
	return nil
}

// Viewport_TextureByPath: the picture of the viewport a path names.
Viewport_TextureByPath :: proc(ctx: ^GameContext, path: string) -> (rl.Texture2D, ^ViewportNode) {
	if ctx == nil do return {}, nil
	scene := ctx.scene
	if scene == nil && ctx.game != nil do scene = ctx.game.sceneManager.currentScene
	v := Viewport_Find(scene, path)
	return ViewportNode_Texture(v), v
}

// ----------------------------------------------------------------------------
// Rendering
// ----------------------------------------------------------------------------

@(private)
viewportRendering: ^ViewportNode // (the one being rendered: it doesn't draw itself)
@(private = "file")
viewportPlaced: bool // (the editor: cameras where they're placed)

// Viewports_CoverScreen: a World viewport covers the screen (split-screen):
// the main view's world layers needn't be drawn.
Viewports_CoverScreen :: proc(scene: ^Scene) -> bool {
	if scene == nil || scene.manager == nil do return false
	for n in scene.manager.nodes do if n != nil && n.typeId == ViewportNode && n.enabled {
		v := cast(^ViewportNode)n
		if v.mode == .World && v.coversScreen do return true
	}
	return false
}

// Viewports_Render renders the scene's viewports (before the frame's own
// drawing; with the frame's render target bound, which it binds again).
// `view`: the main view (When Visible), `world`: this frame's world layers
// (nil: collected here).
// `placed`: the editor, not simulating - cameras where they're placed.
Viewports_Render :: proc(scene: ^Scene, ctx: ^GameContext, view: Maybe(rl.Rectangle) = nil, world: ^[RenderLayer][dynamic]^Node = nil, placed := false) {
	viewportPlaced = placed
	if scene == nil || scene.manager == nil || !rl.IsWindowReady() do return
	list := make([dynamic]^ViewportNode, context.temp_allocator)
	for n in scene.manager.nodes do if n != nil && n.typeId == ViewportNode && Node_EnabledInTree(n) {
		v := cast(^ViewportNode)n
		if viewport_wants_render(v, view) do append(&list, v)
	}
	if len(list) == 0 do return
	// Deepest first: a viewport inside another is ready when that one draws.
	Sort_Stable(list[:], proc(a, b: ^ViewportNode) -> bool {return viewport_depth(a) > viewport_depth(b)})
	worldBuckets: [RenderLayer][dynamic]^Node
	collected := false
	for v in list {
		if v.mode == .World && world == nil && !collected {
			screen: [RenderLayer][dynamic]^Node // (Screen Layers: not in a viewport)
			worldBuckets, collected = Scene_CollectRenderables(scene, &screen), true
		}
		viewport_render_one(scene, ctx, v, world if world != nil else &worldBuckets)
	}
	if f := Render_FrameTarget(); f != nil do rl.BeginTextureMode(f^)
	else do rl.EndTextureMode()
}

@(private = "file")
viewport_depth :: proc(v: ^ViewportNode) -> int {
	d := 0
	for p := v.parent; p != nil; p = p.parent do d += 1
	return d
}

@(private = "file")
viewport_wants_render :: proc(v: ^ViewportNode, view: Maybe(rl.Rectangle)) -> bool {
	switch v.updateMode {
	case .Every_Frame: return true
	case .Once: return !v.rendered || v.dirty
	case .When_Visible:
		if !v.rendered do return true
		if !v.renderable do return false
		if !v.display do return true // (used elsewhere: a sprite, a material)
		if r, ok := view.?; ok && !Viewport_InScreenLayer(v) do return rl.CheckCollisionRecs(r, ViewportNode_Rect(v))
		return true
	}
	return true
}

// Viewport_InScreenLayer: under a Screen Layer (drawn in screen space).
Viewport_InScreenLayer :: proc(n: ^Node) -> bool {
	for p := n.parent; p != nil; p = p.parent do if p.typeId == ScreenLayerNode do return true
	return false
}

// Node_EnabledInTree: the node and every parent are enabled.
Node_EnabledInTree :: proc(n: ^Node) -> bool {
	for p := n; p != nil; p = p.parent do if !p.enabled do return false
	return true
}

// ViewportNode_Camera2D: the view it renders - its Camera child's (in the
// editor: where the camera is placed), else around the viewport.
ViewportNode_Camera2D :: proc(v: ^ViewportNode, ctx: ^GameContext) -> rl.Camera2D {
	rs := ViewportNode_RenderSize(v)
	w, h := f32(rs.x), f32(rs.y)
	cam := ViewportNode_Camera(v)
	if cam == nil {
		if v.mode == .Children {
			// Its children where they stand relative to it, at their size.
			sx := v.globalScale.x if v.globalScale.x != 0 else 1
			return {offset = Node_OriginPx(v, v.size) * (w / v.size.x if v.size.x > 0 else 1), target = v.globalPosition, rotation = -v.globalRotation, zoom = (w / max(v.size.x, 1)) / sx}
		}
		r := ViewportNode_Rect(v)
		return {offset = {w * 0.5, h * 0.5}, target = {r.x + r.width * 0.5, r.y + r.height * 0.5}, zoom = 1}
	}
	offset := cam.screenOffset if cam.customScreenOffset else [2]f32{w * 0.5, h * 0.5}
	if viewportPlaced || cam.currentZoom <= 0 do return {offset = offset, target = cam.globalPosition, zoom = max(cam.targetZoom, 0.01)}
	return {
		offset   = offset,
		target   = cam.currentPosition + cam.currentOffset + cam.shakeOffset * access.screenShake,
		rotation = cam.currentRotation + cam.shakeRotation * access.screenShake,
		zoom     = max(0.001, cam.currentZoom + cam.shakeZoom),
	}
}

@(private = "file")
viewport_render_one :: proc(scene: ^Scene, ctx: ^GameContext, v: ^ViewportNode, world: ^[RenderLayer][dynamic]^Node) {
	rs := ViewportNode_RenderSize(v)
	if v.target.id == 0 || v.target.texture.width != rs.x || v.target.texture.height != rs.y {
		viewport_unload(v)
		v.target = rl.LoadRenderTexture(rs.x, rs.y)
		v.output = rl.LoadRenderTexture(rs.x, rs.y)
	}
	cam2d := ViewportNode_Camera2D(v, ctx)
	w, h := f32(rs.x), f32(rs.y)
	viewRect := Camera2D_ViewRect(cam2d, w, h)
	bg := v.background
	if bg == {} && v.mode == .World {
		bg = Game_ClearColor(ctx.game) if ctx != nil && ctx.game != nil else rl.BLACK
		if scene.backgroundColor.a > 0 do bg = scene.backgroundColor
	}
	// The layers: World - the camera's world layers (all without a camera);
	// Children - its subtree.
	buckets: [RenderLayer][dynamic]^Node
	layers: bit_set[RenderLayer] = ~bit_set[RenderLayer]{}
	if v.mode == .World {
		buckets = world^
		if cam := ViewportNode_Camera(v); cam != nil && cam.targetLayers != {} do layers = cam.targetLayers
		TileCache_Prepare(scene, viewRect, ctx) // (tile chunks in its view)
	} else {
		buckets = Scene_CollectSubtree(scene, v)
	}
	prev := viewportRendering
	viewportRendering = v
	defer viewportRendering = prev
	prevTarget := Render_FrameTarget()
	Render_SetFrameTarget(&v.target) // (passes in the middle of drawing come back here)
	rl.BeginTextureMode(v.target)
	rl.ClearBackground(bg)
	rl.BeginMode2D(cam2d)
	Render_SetView(viewRect)
	Scene_RenderLayers(scene, buckets, ctx, layers)
	Render_ClearView()
	rl.EndMode2D()
	rl.EndTextureMode()
	// The right way up (copied as is: blending would change soft edges).
	rl.BeginTextureMode(v.output)
	rl.ClearBackground({0, 0, 0, 0})
	rlgl.DrawRenderBatchActive()
	rlgl.DisableColorBlend()
	rl.DrawTextureRec(v.target.texture, {0, 0, w, h}, {0, 0}, rl.WHITE) // (render textures are stored bottom row first: copied unflipped, it reads top first like any texture)
	rlgl.DrawRenderBatchActive()
	rlgl.EnableColorBlend()
	rl.EndTextureMode()
	Render_SetFrameTarget(prevTarget)
	v.rendered = true
	v.dirty = false
}

// ----------------------------------------------------------------------------
// Saving the picture (Lua: node:save_png)
// ----------------------------------------------------------------------------

// ViewportNode_SavePNG writes the picture: a relative path goes in the
// game's save-data folder. false: no picture yet, or it couldn't be written.
ViewportNode_SavePNG :: proc(v: ^ViewportNode, path: string) -> bool {
	tex := ViewportNode_Texture(v)
	if tex.id == 0 do return false
	full := path
	if !filepath.is_abs(path) {
		full, _ = filepath.join({Save_GameDataDir(), path}, context.temp_allocator)
		_ = os.make_directory_all(filepath.dir(full, context.temp_allocator))
	}
	img := rl.LoadImageFromTexture(tex)
	defer rl.UnloadImage(img)
	return bool(rl.ExportImage(img, fmt.ctprintf("%s", full)))
}

// ----------------------------------------------------------------------------
// Lua: node:get_texture() / refresh() / save_png(path) on a Viewport
// ----------------------------------------------------------------------------

@(private = "file")
lua_viewport :: proc(L: ^lua.State) -> ^ViewportNode {
	n, ok := to_node_userdata(L, 1)
	if !ok || n.typeId != ViewportNode do return nil
	return cast(^ViewportNode)n
}

// get_texture: its path, "viewport:<name>" - for sprite:set_texture, a
// material's texture parameter.
@(private = "file")
lua_viewport_get_texture :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	v := lua_viewport(L)
	if v == nil {
		lua.pushnil(L)
		return 1
	}
	lua.pushstring(L, strings.clone_to_cstring(Viewport_Path(v), context.temp_allocator))
	return 1
}

@(private = "file")
lua_viewport_refresh :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if v := lua_viewport(L); v != nil do ViewportNode_Refresh(v)
	return 0
}

@(private = "file")
lua_viewport_save_png :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	v := lua_viewport(L)
	path := string(lua.L_checkstring(L, 2))
	lua.pushboolean(L, b32(v != nil && ViewportNode_SavePNG(v, path)))
	return 1
}

// Script_RegisterViewportBindings: the node methods (on the node method table).
Script_RegisterViewportBindings :: proc(L: ^lua.State) {
	lua.pushcfunction(L, lua_viewport_get_texture)
	lua.setfield(L, -2, "get_texture")
	lua.pushcfunction(L, lua_viewport_refresh)
	lua.setfield(L, -2, "refresh")
	lua.pushcfunction(L, lua_viewport_save_png)
	lua.setfield(L, -2, "save_png")
}
