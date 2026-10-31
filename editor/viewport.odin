package editor

import "core:c"
import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Viewport Subsystem: GitKraken-Style 2D Canvas, Camera & Transform Gizmos
// ============================================================================

col32 :: #force_inline proc(r, g, b: u32, a: u32 = 255) -> u32 {
	return (r & 0xFF) | ((g & 0xFF) << 8) | ((b & 0xFF) << 16) | ((a & 0xFF) << 24)
}

// Convert from Editor 2D World space to ImGui Screen space within the Viewport
Viewport_WorldToScreen :: proc(state: ^EditorState, worldPos: [2]f32) -> [2]f32 {
	halfView := state.viewportSize * 0.5
	offset := (worldPos - state.cameraPos) * state.cameraZoom
	return state.viewportPos + halfView + offset
}

// Convert from ImGui Screen space to Editor 2D World space
Viewport_ScreenToWorld :: proc(state: ^EditorState, screenPos: [2]f32) -> [2]f32 {
	halfView := state.viewportSize * 0.5
	offset := (screenPos - state.viewportPos - halfView) / state.cameraZoom
	return state.cameraPos + offset
}

// Check if a point is inside a circle
point_in_circle :: proc(p, center: [2]f32, radius: f32) -> bool {
	dx := p.x - center.x
	dy := p.y - center.y
	return (dx * dx + dy * dy) <= (radius * radius)
}

// Check if a point is inside an axis-aligned box
point_in_rect :: proc(p, min, max: [2]f32) -> bool {
	return p.x >= min.x && p.x <= max.x && p.y >= min.y && p.y <= max.y
}

// Lighting preview in the viewport (toolbar sun).
viewportLighting := true

// Viewport_DrawLights: a marker for every light (they're invisible
// otherwise) and the radius / cone of the selected ones.
Viewport_DrawLights :: proc(state: ^EditorState) {
	if state.activeScene == nil do return
	z := state.cameraZoom
	for n in state.activeScene.manager.nodes {
		if n == nil || n.typeId != e.LightNode || !n.enabled do continue
		l := cast(^e.LightNode)n
		c := l.globalPosition
		col := l.color
		col.a = 255
		rl.DrawCircleV(c, 6 / z, col)
		rl.DrawCircleLinesV(c, 9 / z, rl.Color{255, 255, 255, 200})
		if !Editor_IsSelected(state, n) && n != state.selectedNode do continue
		r := l.radius * max(abs(l.globalScale.x), abs(l.globalScale.y))
		ring := col
		ring.a = 160
		if l.kind == .Spot {
			a0 := l.globalRotation - l.spread
			a1 := l.globalRotation + l.spread
			rl.DrawCircleSectorLines(c, r, a0, a1, 32, ring)
		} else {
			rl.DrawCircleLinesV(c, r, ring)
		}
	}
}

// Frame the viewport was last drawn (dropped files land in it only if visible).
viewportShownFrame: i32

Viewport_UpdateAndRender :: proc(state: ^EditorState) {
	imgui.PushStyleVarImVec2(imgui.StyleVar.WindowPadding, imgui.Vec2{0, 0})
	defer imgui.PopStyleVar()

	viewportFlags: imgui.WindowFlags = {.NoScrollbar, .NoScrollWithMouse}
	viewportOpen := imgui.Begin("Viewport###ViewportWindow", nil, viewportFlags)
	Drive_Window("viewport") // (annotated docs screenshots)
	Dock_Remember(.Center)
	if viewportOpen {
		driveNoScroll = true // the wheel zooms here: drives never "scroll" it
		defer driveNoScroll = false
		SceneTabs_Draw(state) // open scenes as tabs (scene_tabs.odin)
		// Available region for rendering
		avail := imgui.GetContentRegionAvail()
		reqW := i32(math.max(f32(64.0), avail.x))
		reqH := i32(math.max(f32(64.0), avail.y))

		// Resize render texture if viewport size changed
		if state.renderTexture.id == 0 ||
		   state.renderTexture.texture.width != reqW ||
		   state.renderTexture.texture.height != reqH {
			if state.renderTexture.id != 0 {
				rl.UnloadRenderTexture(state.renderTexture)
			}
			state.renderTexture = rl.LoadRenderTexture(reqW, reqH)
			state.viewportSize = {f32(reqW), f32(reqH)}
		}

		viewportShownFrame = imgui.GetFrameCount()
		cursorScreen := imgui.GetCursorScreenPos()
		state.viewportPos = {cursorScreen.x, cursorScreen.y}
		state.viewportSize = {f32(reqW), f32(reqH)}

		// Render the Raylib scene into renderTexture
		Viewport_RenderOffscreen(state)

		// Post effects (PostEffectNodes), previewed with lighting.
		@(static) shown: rl.Texture2D
		shown = state.renderTexture.texture
		if viewportLighting && state.activeScene != nil {
			if effects := e.Scene_PostEffects(state.activeScene); len(effects) > 0 {
				shown = e.Post_Process(effects, shown, &state.game.gameContext)
			}
		}

		// Colour vision preview (View menu): simulated.
		if viewportVision != .None do shown = e.Colorblind_Process(shown, viewportVision, 1, true)

		// Render texture image into ImGui
		imgui.Image(
			transmute(imgui.TextureID)&shown,
			imgui.Vec2{f32(reqW), f32(reqH)},
			imgui.Vec2{0, 1},
			imgui.Vec2{1, 0},
			imgui.Vec4{1, 1, 1, 1},
			imgui.Vec4{0, 0, 0, 0},
		)

		Drive_Item("viewport")
		{
			io := imgui.GetIO()
			AssetBrowser_HandleViewportDrop(state, Viewport_ScreenToWorld(state, {io.MousePos.x, io.MousePos.y}))
		}
		state.viewportHovered = imgui.IsItemHovered()
		state.viewportFocused = imgui.IsWindowFocused()
		// Overlay buttons over the image take the mouse from the viewport.
		if ShapeEdit_Overlay(state) do state.viewportHovered = false
		state.viewportDockId = imgui.GetWindowDockID()

		// Interactive Gizmo overlays & mouse controls
		Viewport_HandleInputAndGizmos(state)
		// An empty scene: a hint in the middle.
		if state.activeScene != nil && state.activeScene.rootNode != nil && len(e.GetChildrenView(state.activeScene.manager, state.activeScene.rootNode)) == 0 {
			msg := fmt.ctprintf("%s  Empty scene: Cmd+A adds a node, or drop images, components and levels here", ICON_FA_WAND_MAGIC_SPARKLES)
			w := imgui.CalcTextSize(msg).x
			c := state.viewportPos + state.viewportSize * 0.5
			imgui.DrawList_AddText(imgui.GetWindowDrawList(), {c.x - w * 0.5, c.y - 8}, col_u32(UI_TEXT_DIM), msg)
		}
	}
	imgui.End()
}

// Render Raylib offscreen framebuffer
Viewport_RenderOffscreen :: proc(state: ^EditorState) {
	if state.renderTexture.id == 0 do return

	cam := rl.Camera2D{
		offset   = {state.viewportSize.x * 0.5, state.viewportSize.y * 0.5},
		target   = {state.cameraPos.x, state.cameraPos.y},
		rotation = 0.0,
		zoom     = state.cameraZoom,
	}

	// Update first (simulation, transforms): the light map is rendered into
	// its own texture before the viewport's texture is bound.
	ctx := &state.game.gameContext
	lit := false
	if state.activeScene != nil && state.activeScene.rootNode != nil {
		e.ProcessNodeQueues(state.activeScene.manager, ctx)
		Editor_SyncGameFrame(state) // the project's frame (#202)
		state.activeScene.manager.screen = Editor_ScreenMapping(state) // Screen Layers over the camera frame (#175)
		e.Node_SetGlobalPositions(state.activeScene.manager, state.activeScene.rootNode)
		Ldtk_EditorSync(state)
		if state.isSimulating && !state.isPaused {
			dt := rl.GetFrameTime()
			e.PhysicsWorld_Step(&state.game.physicsWorld, dt, ctx)
			e.Scene_UpdateNodeHirearchy(state.activeScene, state.activeScene.rootNode, ctx, dt)
			e.Tween_Update(&state.game.tweens, dt, &state.game.scriptManager)
			e.Node_SetGlobalPositions(state.activeScene.manager, state.activeScene.rootNode)
			e.Visibility_Update(state.activeScene, ctx) // (the game camera's view, not the editor's)
			e.EventBus_Flush(&state.game.events) // Events.emit_deferred
		} else if !state.isSimulating {
			ParticlePreview_Tick(state, rl.GetFrameTime()) // emitters animate while editing
		}
		if viewportLighting do lit = e.Lighting_Prepare(state.activeScene, cam, i32(state.viewportSize.x), i32(state.viewportSize.y))
		e.TileCache_Prepare(state.activeScene, e.Camera2D_ViewRect(cam, state.viewportSize.x, state.viewportSize.y), ctx)
		e.Vector_FiltersPrepare(state.activeScene, cam.zoom) // (filtered vector art: textures made before the frame)
		e.Viewports_Render(state.activeScene, ctx, placed = !state.isSimulating) // Viewport nodes' pictures: a live preview (viewport_node.odin)
	}

	rl.BeginTextureMode(state.renderTexture)
	// Dark neutral editor canvas background (matches GitKraken child bg #171A21)
	clear := rl.Color{23, 26, 33, 255}
	if state.activeScene != nil && state.activeScene.backgroundColor.a > 0 do clear = state.activeScene.backgroundColor
	rl.ClearBackground(clear)

	rl.BeginMode2D(cam)

	// Draw adaptive editor grid and origin axes
	if state.showGrid {
		Viewport_DrawRaylibGrid(state)
	}

	// Active scene rendering
	if state.activeScene != nil && state.activeScene.rootNode != nil {
		// One traversal for all layers (not one walk per layer).
		e.Render_HideEditorHidden = true // nodes hidden in the editor
		e.Render_EditorView = true       // (and placeholders)
		e.Scene_RenderAllLayers(state.activeScene, ctx, 0.0, e.Camera2D_ViewRect(cam, state.viewportSize.x, state.viewportSize.y))
		e.Render_HideEditorHidden = false
		e.Render_EditorView = false
		if lit {
			// Lights multiply over the scene (screen space), before editor overlays.
			rl.EndMode2D()
			e.Lighting_Composite()
			rl.BeginMode2D(cam)
		}
		Viewport_DrawLights(state)
		Viewport_DrawNotifiers(state)
		if sp := state.selectedNode; sp != nil && sp.typeId == e.SpawnerNode && !Editor_ViewHidden(state, sp) do e.SpawnerNode_DrawBounds(sp, &state.game.gameContext, 0) // (spawn point, facing, spread)
		Viewport_DrawPaths(state)
		Viewport_DrawOnionSkin(state) // (the selected AnimationPlayer's neighbouring frames)
		Viewport_DrawNavigation(state)
		Viewport_DrawAdvancedCameras(state)

		// Draw bounding boxes / physics colliders (when enabled or node selected)
		Viewport_DrawSceneBounds(state)
		Viewport_DrawAllColliders(state)
		Viewport_DrawLdtkEntities(state)
		Viewport_DrawCameraFollow(state)
	}

	// Draw Camera bounds (frustum, viewport boundary, limits, deadzones)
	if state.showCameraBounds {
		Viewport_DrawCameraBounds(state)
	}

	rl.EndMode2D()
	e.Render_MakeOpaque(f32(state.renderTexture.texture.width), f32(state.renderTexture.texture.height)) // (shown blended: soft edges kept their dark rim)
	rl.EndTextureMode()
}

// Adaptive grid rendering with major axes
Viewport_DrawRaylibGrid :: proc(state: ^EditorState) {
	step := state.gridSize
	if step <= 0 do step = 32.0

	halfView := (state.viewportSize * 0.5) / state.cameraZoom
	minX := state.cameraPos.x - halfView.x
	maxX := state.cameraPos.x + halfView.x
	minY := state.cameraPos.y - halfView.y
	maxY := state.cameraPos.y + halfView.y

	startGridX := math.floor(minX / step) * step
	endGridX := math.ceil(maxX / step) * step
	startGridY := math.floor(minY / step) * step
	endGridY := math.ceil(maxY / step) * step

	gridColor := rl.Color{35, 40, 52, 180}
	majorGridColor := rl.Color{48, 56, 72, 220}

	// Vertical grid lines
	for x := startGridX; x <= endGridX; x += step {
		col := gridColor
		if int(x) % int(step * 5) == 0 do col = majorGridColor
		rl.DrawLineV({x, minY}, {x, maxY}, col)
	}

	// Horizontal grid lines
	for y := startGridY; y <= endGridY; y += step {
		col := gridColor
		if int(y) % int(step * 5) == 0 do col = majorGridColor
		rl.DrawLineV({minX, y}, {maxX, y}, col)
	}

	// World Origin axes: X (Coral Red), Y (Mint Green)
	rl.DrawLineEx({minX, 0}, {maxX, 0}, 2.0 / state.cameraZoom, rl.Color{235, 77, 75, 220})
	rl.DrawLineEx({0, minY}, {0, maxY}, 2.0 / state.cameraZoom, rl.Color{0, 184, 148, 220})
}

// Node_Bounds returns a node's world-space outline (4 corners, rotated
// around its pivot) as drawn by the engine. Nodes without a visual extent
// (plain nodes, timers, sounds, ...) get a small handle square sized in
// screen pixels so they can still be clicked.
Node_Bounds :: proc(state: ^EditorState, node: ^e.Node) -> (corners: [4][2]f32, isHandle: bool) {
	pos := node.globalPosition
	scl := node.globalScale
	lo, hi: [2]f32
	have := false

	// Nodes with an origin: their drawn rectangle around it (text scales
	// uniformly by x). A negative scale mirrors it, as the game does.
	if e.Node_HasOrigin(node) {
		size := e.Node_OriginSize(node, &state.game.gameContext)
		if size.x > 0 && size.y > 0 {
			s := scl if node.typeId != e.TextNode else [2]f32{scl.x, scl.x}
			o := e.Node_OriginPx(node, size)
			lo, hi, have = -o * s, (size - o) * s, true
		}
	}
	switch node.typeId {
	case e.VectorShapeNode:
		// (Assets: the origin rectangle above; presets: what they drew.)
		if !have {
			if b, ok := e.VectorShapeNode_LocalBounds(cast(^e.VectorShapeNode)node); ok {
				lo, hi, have = [2]f32{b[0], b[1]} * scl, [2]f32{b[2], b[3]} * scl, true
			}
		}
	case e.LineNode:
		l := cast(^e.LineNode)node
		for p, i in l.points {
			q := p * scl
			if i == 0 do lo, hi, have = q, q, true
			lo = {min(lo.x, q.x), min(lo.y, q.y)}
			hi = {max(hi.x, q.x), max(hi.y, q.y)}
		}
		pad := l.width * 0.5 * max(abs(scl.x), abs(scl.y))
		lo -= pad
		hi += pad
	case e.LdtkLevelNode:
		// The active levels (in world mode, the whole world).
		ln := cast(^e.LdtkLevelNode)node
		for lvl in ln.activeLevels {
			o := e.LdtkLevelNode_LevelOffset(ln, lvl) * scl
			p := o + [2]f32{f32(lvl.pxWid), f32(lvl.pxHei)} * scl
			if !have do lo, hi, have = o, p, true
			lo = {min(lo.x, o.x), min(lo.y, o.y)}
			hi = {max(hi.x, p.x), max(hi.y, p.y)}
		}
	case e.TileMapNode:
		// The map and anything painted beyond it (#220).
		tm := cast(^e.TileMapNode)node
		if tm.tileSize.x > 0 && tm.tileSize.y > 0 {
			clo, chi := e.TileMapNode_Extent(tm)
			clo = {min(clo.x, 0), min(clo.y, 0)}
			chi = {max(chi.x, tm.mapSize.x), max(chi.y, tm.mapSize.y)}
			if chi.x > clo.x && chi.y > clo.y {
				r := e.TileMapNode_MapLocalBounds(tm, clo, chi) // (any grid; tall tiles' tops)
				lo, hi, have = [2]f32{r.x, r.y} * scl, [2]f32{r.x + r.width, r.y + r.height} * scl, true
			}
		}
	case e.NavigationRegionNode:
		lo, hi, have = {0, 0}, (cast(^e.NavigationRegionNode)node).size * {abs(scl.x), abs(scl.y)}, true
	case e.PathNode:
		pn := cast(^e.PathNode)node
		e.PathNode_Bake(pn)
		for p, i in pn.baked {
			q := p * scl
			if i == 0 do lo, hi, have = q, q, true
			lo = {min(lo.x, q.x), min(lo.y, q.y)}
			hi = {max(hi.x, q.x), max(hi.y, q.y)}
		}
		lo -= 4 / state.cameraZoom
		hi += 4 / state.cameraZoom
	case e.VisibilityNotifierNode:
		v := cast(^e.VisibilityNotifierNode)node
		lo, hi, have = -v.size * 0.5 * {abs(scl.x), abs(scl.y)}, v.size * 0.5 * {abs(scl.x), abs(scl.y)}, true
	case e.SpawnerNode:
		r := 10 / state.cameraZoom // (a small marker to pick)
		lo, hi, have = {-r, -r}, {r, r}, true
	case e.StaticBodyNode, e.DynamicBodyNode, e.KinematicBodyNode, e.CharacterMoverNode, e.AreaNode:
		// Every shape (rotated, any type), scaled with the node.
		if shapes := node_shapes_editor(node); shapes != nil && len(shapes) > 0 {
			lo, hi, have = ShapeEdit_LocalBounds(node, shapes[:])
		} else if node.typeId == e.CharacterMoverNode {
			cm := cast(^e.CharacterMoverNode)node
			lo, hi, have = {-cm.radius, -cm.height * 0.5 - cm.radius}, {cm.radius, cm.height * 0.5 + cm.radius}, true
		}
	}
	if node.isUI {
		ui := cast(^e.UIElement)node
		if ui.size.x > 0 && ui.size.y > 0 {
			// UI elements are laid out from their top-left corner.
			lo, hi, have = {0, 0}, ui.size, true
		}
	}
	if !have {
		h := 9 / state.cameraZoom
		lo, hi, isHandle = {-h, -h}, {h, h}, true
	}
	rad := (0 if isHandle || node.isUI else node.globalRotation) * math.PI / 180
	cs, sn := math.cos(rad), math.sin(rad)
	local := [4][2]f32{{lo.x, lo.y}, {hi.x, lo.y}, {hi.x, hi.y}, {lo.x, hi.y}}
	for p, i in local {
		corners[i] = pos + {p.x * cs - p.y * sn, p.x * sn + p.y * cs}
	}
	return
}

@(private = "file")
point_in_quad :: proc(p: [2]f32, q: [4][2]f32) -> bool {
	sign := 0
	for i in 0 ..< 4 {
		a, b := q[i], q[(i + 1) % 4]
		cross := (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
		s := 1 if cross > 0 else (-1 if cross < 0 else 0)
		if s == 0 do continue
		if sign == 0 do sign = s
		else if s != sign do return false
	}
	return true
}

// Draw bounds and collision shapes for scene nodes
Viewport_DrawSceneBounds :: proc(state: ^EditorState) {
	if state.activeScene == nil || state.activeScene.manager == nil do return
	for node in state.activeScene.manager.nodes {
		if node == nil || node == state.activeScene.rootNode || node.typeId == e.CameraNode do continue
		isSelected := node == state.selectedNode || Editor_IsSelected(state, node)
		if !state.showBounds && !isSelected do continue
		if Editor_ViewHidden(state, node) do continue
		q, isHandle := Node_Bounds(state, node)
		col := rl.Color{92, 141, 255, 255} if isSelected else rl.Color{140, 150, 170, 90}
		th := (2.0 if isSelected else 1.0) / state.cameraZoom
		for i in 0 ..< 4 {
			rl.DrawLineEx(q[i], q[(i + 1) % 4], th, col)
		}
		if isSelected && !isHandle {
			// Corner ticks read better than a heavy box.
			for c in q do rl.DrawCircleV(c, 3 / state.cameraZoom, col)
		}
	}
}

// Viewport_DrawNavigation: regions (outline; cells while selected) and,
// in Simulate, each agent's path.
Viewport_DrawNavigation :: proc(state: ^EditorState) {
	if state.activeScene == nil do return
	m := state.activeScene.manager
	for n in m.navRegions {
		if Editor_ViewHidden(state, n) do continue
		r := cast(^e.NavigationRegionNode)n
		sel := n == state.selectedNode
		if sel && !r.baked do e.NavRegion_Bake(r, &state.game.gameContext)
		e.NavRegion_Draw(r, sel)
	}
	if !state.isSimulating do return
	for n in m.navAgents {
		a := cast(^e.NavigationAgentNode)n
		if !a.hasTarget do continue
		p := e.NavAgent_Position(a, m)
		for i in a.pathIndex ..< len(a.path) {
			rl.DrawLineEx(p, a.path[i], 2 / state.cameraZoom, {52, 211, 153, 220})
			p = a.path[i]
		}
		rl.DrawCircleV(a.target, 4 / state.cameraZoom, {52, 211, 153, 255})
	}
}

// Viewport_DrawNotifiers: each visibility notifier's rectangle (yellow; in
// Simulate brighter while the game camera sees it).
Viewport_DrawNotifiers :: proc(state: ^EditorState) {
	if state.activeScene == nil do return
	for n in state.activeScene.manager.notifiers {
		if Editor_ViewHidden(state, n) do continue
		v := cast(^e.VisibilityNotifierNode)n
		r := e.VisibilityNotifierNode_Rect(v)
		a: u8 = 220 if (state.isSimulating && v.onScreen) || n == state.selectedNode else 110
		rl.DrawRectangleRec(r, {250, 204, 21, a / 8})
		rl.DrawRectangleLinesEx(r, 1.5 / state.cameraZoom, {250, 204, 21, a})
	}
}

// Viewport_DrawCameraFollow: a dashed line from a selected camera to the
// node it follows.
Viewport_DrawCameraFollow :: proc(state: ^EditorState) {
	if state.activeScene == nil do return
	for n in state.selection {
		if !e.Node_IsAlive(n) || n.typeId != e.CameraNode do continue
		cam := cast(^e.CameraNode)n
		if cam.followTarget == "" do continue
		tgt := e.Node_ResolvePath(state.activeScene.manager, cam, cam.followTarget)
		if tgt == nil do continue
		a, b := cam.globalPosition, tgt.globalPosition
		d := b - a
		l := math.sqrt(d.x * d.x + d.y * d.y)
		if l < 1 do continue
		dir := d / l
		dash := 10 / state.cameraZoom
		col := rl.Color{250, 204, 21, 220}
		// Integer steps (a float accumulator can stall on long lines), capped.
		count := min(int(l / (dash * 2)) + 1, 400)
		step := l / f32(count)
		for i in 0 ..< count {
			t := f32(i) * step
			rl.DrawLineEx(a + dir * t, a + dir * min(t + step * 0.5, l), 1.5 / state.cameraZoom, col)
		}
		rl.DrawCircleLinesV(b, 12 / state.cameraZoom, col)
	}
}

// Editor_ScreenMapping: where the game shows its frame - the scene camera's
// view (as its frame is drawn: Viewport_DrawCameraBounds), or the default
// viewport without a camera. Screen Layers are placed in it (#175).
Editor_ScreenMapping :: proc(state: ^EditorState) -> e.Screen_Mapping {
	// The game's frame (#202): the virtual resolution, grown for Expand -
	// not cam.viewportSize (the game's runtime cache, unset in the editor).
	frame := Editor_GameFrameSize(state)
	vW, vH := frame.x, frame.y
	cam := Editor_SceneCamera(state)
	if cam == nil do return {scale = 1, size = {vW, vH}}
	zoom: f32 = 1.0
	if cam.currentZoom > 0 do zoom = cam.currentZoom
	else if cam.targetZoom > 0 do zoom = cam.targetZoom
	else if cam.zoom > 0 do zoom = cam.zoom
	if zoom <= 0.001 do zoom = 1.0
	center := e.CameraNode_ViewCenter(cam)
	if state.isSimulating do center = cam.currentPosition
	return {origin = center - [2]f32{vW, vH} * 0.5 / zoom, scale = 1 / zoom, size = {vW, vH}}
}

// Draw camera viewport boundaries, frustum framing brackets, center reticle, and limits
Viewport_DrawCameraBounds :: proc(state: ^EditorState) {
	if state.activeScene == nil do return

	// 1. Gather all cameras in scene to visualize
	primaryCam: ^e.CameraNode = state.activeScene.camera
	allCameras := make([dynamic]^e.CameraNode, context.temp_allocator)

	if state.activeScene.manager != nil {
		for n in state.activeScene.manager.nodes {
			if n != nil && n.typeId == typeid_of(e.CameraNode) {
				cam := cast(^e.CameraNode)n
				append(&allCameras, cam)
				if primaryCam == nil && cam.isCurrent {
					primaryCam = cam
				}
			}
		}
	}

	// If no camera found in scene, fallback to project virtual resolution centered at (vW*0.5, vH*0.5)
	if len(allCameras) == 0 {
		d := Editor_DesignSize(state)
		draw_camera_frustum(state, nil, "Default Viewport", d * 0.5, d.x, d.y, 1.0, true)
		draw_expand_frame(state, d * 0.5, 1)
		return
	}

	// 2. Render each camera (draw non-selected / secondary first, then primary / selected on top)
	for cam in allCameras {
		isSelected := (state.selectedNode != nil && state.selectedNode == &cam.node)
		isPrimary := (cam == primaryCam || cam.isCurrent)

		// The design frame (#202: the virtual resolution, not the camera's
		// runtime cache).
		d := Editor_DesignSize(state)
		vW, vH := d.x, d.y
		label := cam.name
		// A Viewport's camera: its picture's size (viewport_node.odin).
		if cam.parent != nil && cam.parent.typeId == e.ViewportNode {
			rs := e.ViewportNode_RenderSize(cast(^e.ViewportNode)cam.parent)
			vW, vH = f32(rs.x), f32(rs.y)
			label = fmt.tprintf("%s (Viewport %s)", cam.name, cam.parent.name)
			isPrimary = false
		}

		zoom: f32 = 1.0
		if cam.currentZoom > 0 do zoom = cam.currentZoom
		else if cam.targetZoom > 0 do zoom = cam.targetZoom
		else if cam.zoom > 0 do zoom = cam.zoom
		if zoom <= 0.001 do zoom = 1.0

		// Same rule the game uses at start (engine CameraNode_ViewCenter);
		// while simulating, the live camera position.
		center := e.CameraNode_ViewCenter(cam)
		if state.isSimulating do center = cam.currentPosition

		draw_camera_frustum(state, cam, label, center, vW, vH, zoom, isPrimary || isSelected)
		if isPrimary do draw_expand_frame(state, center, zoom)
	}
}

// draw_expand_frame: with the Expand fill mode, the frame on the preview
// screen shape (dashed) around the design frame (#202).
@(private = "file")
draw_expand_frame :: proc(state: ^EditorState, center: [2]f32, zoom: f32) {
	if state.projectConfig.fill != .Expand do return
	size := Editor_GameFrameSize(state) / zoom
	r := rl.Rectangle{center.x - size.x * 0.5, center.y - size.y * 0.5, size.x, size.y}
	col := rl.Color{255, 195, 18, 150}
	th := 1.5 / state.cameraZoom
	dash, gap := 10 / state.cameraZoom, 6 / state.cameraZoom
	line :: proc(a, b: [2]f32, dash, gap, th: f32, col: rl.Color) {
		d := b - a
		l := math.sqrt(d.x * d.x + d.y * d.y)
		if l <= 0 do return
		u := d / l
		for t: f32 = 0; t < l; t += dash + gap do rl.DrawLineEx(a + u * t, a + u * min(t + dash, l), th, col)
	}
	tl, tr := [2]f32{r.x, r.y}, [2]f32{r.x + r.width, r.y}
	bl, br := [2]f32{r.x, r.y + r.height}, [2]f32{r.x + r.width, r.y + r.height}
	line(tl, tr, dash, gap, th, col)
	line(tr, br, dash, gap, th, col)
	line(br, bl, dash, gap, th, col)
	line(bl, tl, dash, gap, th, col)
	fontSize := i32(math.clamp(11.0 / state.cameraZoom, 8.0, 32.0))
	rl.DrawText(fmt.ctprintf("Expand on %s: %.0fx%.0f", PREVIEW_SHAPES[Editor_PreviewShape()].name, size.x * zoom, size.y * zoom), i32(r.x + 4 / state.cameraZoom), i32(r.y + r.height + 3 / state.cameraZoom), fontSize, col)
}

@(private="file")
draw_camera_frustum :: proc(
	state: ^EditorState,
	cam: ^e.CameraNode,
	name: string,
	center: [2]f32,
	vW, vH: f32,
	zoom: f32,
	isActive: bool,
) {
	worldW := vW / zoom
	worldH := vH / zoom

	rect := rl.Rectangle{
		x = center.x - worldW * 0.5,
		y = center.y - worldH * 0.5,
		width = worldW,
		height = worldH,
	}

	th := (isActive ? 2.0 : 1.0) / state.cameraZoom
	borderColor := isActive ? rl.Color{255, 195, 18, 220} : rl.Color{130, 145, 170, 140}
	bracketColor := isActive ? rl.Color{255, 230, 80, 255} : rl.Color{160, 175, 200, 180}
	fillColor := isActive ? rl.Color{255, 195, 18, 10} : rl.Color{0, 0, 0, 0}

	// 1. Subtle translucent interior fill
	if fillColor.a > 0 {
		rl.DrawRectangleRec(rect, fillColor)
	}

	// 2. Full camera bounding rectangle
	rl.DrawRectangleLinesEx(rect, th, borderColor)

	// 3. Viewfinder corner brackets (accentuating safe frame)
	bracketLen := min(36.0, min(worldW, worldH) * 0.15)
	bTh := th * 1.5

	// Top-Left
	rl.DrawLineEx({rect.x, rect.y}, {rect.x + bracketLen, rect.y}, bTh, bracketColor)
	rl.DrawLineEx({rect.x, rect.y}, {rect.x, rect.y + bracketLen}, bTh, bracketColor)

	// Top-Right
	rl.DrawLineEx({rect.x + rect.width, rect.y}, {rect.x + rect.width - bracketLen, rect.y}, bTh, bracketColor)
	rl.DrawLineEx({rect.x + rect.width, rect.y}, {rect.x + rect.width, rect.y + bracketLen}, bTh, bracketColor)

	// Bottom-Left
	rl.DrawLineEx({rect.x, rect.y + rect.height}, {rect.x + bracketLen, rect.y + rect.height}, bTh, bracketColor)
	rl.DrawLineEx({rect.x, rect.y + rect.height}, {rect.x, rect.y + rect.height - bracketLen}, bTh, bracketColor)

	// Bottom-Right
	rl.DrawLineEx({rect.x + rect.width, rect.y + rect.height}, {rect.x + rect.width - bracketLen, rect.y + rect.height}, bTh, bracketColor)
	rl.DrawLineEx({rect.x + rect.width, rect.y + rect.height}, {rect.x + rect.width, rect.y + rect.height - bracketLen}, bTh, bracketColor)

	// 4. Center crosshair & reticle
	crSize := 14.0 / state.cameraZoom
	rl.DrawCircleLines(i32(center.x), i32(center.y), 5.0 / state.cameraZoom, borderColor)
	rl.DrawLineEx({center.x - crSize, center.y}, {center.x + crSize, center.y}, th * 0.75, borderColor)
	rl.DrawLineEx({center.x, center.y - crSize}, {center.x, center.y + crSize}, th * 0.75, borderColor)

	// 5. Header label badge pill at top-left
	badgeW: f32 = 230.0 / state.cameraZoom
	badgeH: f32 = 18.0 / state.cameraZoom
	badgeRect := rl.Rectangle{rect.x, rect.y - badgeH, badgeW, badgeH}
	rl.DrawRectangleRec(badgeRect, rl.Color{18, 22, 30, 220})
	rl.DrawRectangleLinesEx(badgeRect, 1.0 / state.cameraZoom, borderColor)

	fontSize := i32(math.clamp(11.0 / state.cameraZoom, 8.0, 32.0))
	labelStr := fmt.ctprintf("%s (%.0fx%.0f | %.2fx)", name, vW, vH, zoom)
	rl.DrawText(labelStr, i32(rect.x + 4.0 / state.cameraZoom), i32(rect.y - badgeH + 3.0 / state.cameraZoom), fontSize, rl.Color{240, 243, 248, 255})

	// 6. Camera Limits (if enabled on node)
	if cam != nil && cam.hasLimits {
		limW := cam.rightLimit - cam.leftLimit
		limH := cam.bottomLimit - cam.topLimit
		if limW > 0 && limH > 0 {
			limRect := rl.Rectangle{cam.leftLimit, cam.topLimit, limW, limH}
			limColor := rl.Color{235, 77, 75, 200}
			rl.DrawRectangleLinesEx(limRect, th * 1.2, limColor)

			limBadgeW: f32 = 100.0 / state.cameraZoom
			limBadgeH: f32 = 16.0 / state.cameraZoom
			rl.DrawRectangleRec(rl.Rectangle{limRect.x, limRect.y - limBadgeH, limBadgeW, limBadgeH}, rl.Color{30, 15, 15, 220})
			rl.DrawRectangleLinesEx(rl.Rectangle{limRect.x, limRect.y - limBadgeH, limBadgeW, limBadgeH}, 1.0 / state.cameraZoom, limColor)
			rl.DrawText("Camera Limits", i32(limRect.x + 4.0 / state.cameraZoom), i32(limRect.y - limBadgeH + 2.0 / state.cameraZoom), fontSize, rl.Color{255, 120, 120, 255})
		}
	}

	// 7. Deadzones / Margins (if enabled on node)
	if cam != nil && (cam.useHMargins || cam.useVMargins) {
		hM := cam.leftMargin if cam.useHMargins else 0.0
		vM := cam.topMargin if cam.useVMargins else 0.0
		dzW := worldW * (1.0 - hM * 2.0)
		dzH := worldH * (1.0 - vM * 2.0)
		if dzW > 0 && dzH > 0 {
			dzRect := rl.Rectangle{
				x = center.x - dzW * 0.5,
			y = center.y - dzH * 0.5,
				width = dzW,
				height = dzH,
			}
			rl.DrawRectangleLinesEx(dzRect, th * 0.8, rl.Color{255, 255, 255, 110})
		}
	}
}

// Handle panning, zooming, node picking, and transform gizmos
Viewport_HandleInputAndGizmos :: proc(state: ^EditorState) {
	io := imgui.GetIO()
	mouseScreen := [2]f32{io.MousePos.x, io.MousePos.y}
	mouseWorld := Viewport_ScreenToWorld(state, mouseScreen)

	drawList := imgui.GetWindowDrawList()
	if drawList == nil do return

	if state.viewportHovered || state.isDraggingGizmo {
		// 1. Zooming with Mouse Wheel
		if io.MouseWheel != 0 {
			zoomDelta := io.MouseWheel * 0.12 * state.cameraZoom
			newZoom := math.clamp(state.cameraZoom + zoomDelta, f32(0.1), f32(10.0))

			beforeZoomWorld := Viewport_ScreenToWorld(state, mouseScreen)
			state.cameraZoom = newZoom
			afterZoomWorld := Viewport_ScreenToWorld(state, mouseScreen)
			state.cameraPos += (beforeZoomWorld - afterZoomWorld)
		}

		// 2. Camera Panning (Middle Mouse Button OR Pan Tool Mode with Left Button)
		isPanning := imgui.IsMouseDown(.Middle) || (state.toolMode == .Pan && imgui.IsMouseDown(.Left))
		if isPanning {
			deltaScreen := [2]f32{io.MouseDelta.x, io.MouseDelta.y}
			state.cameraPos -= deltaScreen / state.cameraZoom
		}
	}

	// Tile painting owns the mouse while a tile tool is active.
	if Viewport_TilePaint(state, drawList, mouseScreen, mouseWorld) do return

	// Collision-shape handles (replace the gizmo while editing shapes).
	shapeOwnsMouse := Viewport_ShapeEdit(state, drawList, mouseScreen, mouseWorld)
	// A selected path's points and handles.
	if !shapeOwnsMouse && Viewport_PathEdit(state, drawList, mouseScreen, mouseWorld) {
		state.activeHandle = .None
		state.isDraggingGizmo = false
		return
	}

	// Plugin overlays (plugin_extend.odin): a handle under / held by the mouse owns it.
	if !shapeOwnsMouse && PluginOverlays_Render(state, drawList, mouseWorld) {
		state.activeHandle = .None
		state.isDraggingGizmo = false
		return
	}

	// Rulers and guides (and their mouse handling).
	guidesOwn := shapeOwnsMouse ? false : Viewport_Guides(state, drawList, mouseScreen, mouseWorld)

	// The Y-sort line of a selected node its parent sorts (y + ySortOffset).
	if sel := state.selectedNode; sel != nil && state.activeScene != nil {
		if parent := e.GetParent(state.activeScene.manager, sel); parent != nil && parent.ySort {
			q, _ := Node_Bounds(state, sel)
			y := sel.globalPosition.y + sel.ySortOffset
			x0 := min(q[0].x, q[1].x, q[2].x, q[3].x) - 16
			x1 := max(q[0].x, q[1].x, q[2].x, q[3].x) + 16
			a := Viewport_WorldToScreen(state, {x0, y})
			b := Viewport_WorldToScreen(state, {x1, y})
			for x := a.x; x < b.x; x += 8 do imgui.DrawList_AddLine(drawList, {x, a.y}, {min(x + 4, b.x), a.y}, col_u32(UI_WARNING), 1.5)
			imgui.DrawList_AddText(drawList, {b.x + 4, a.y - 8}, col_u32(UI_WARNING), "y sort")
		}
	}

	// 3. Transform Gizmos for Selected Node (not for nodes locked in the viewport)
	if state.selectedNode != nil && !ShapeEdit_IsActive(state) && !guidesOwn && !Editor_ViewLocked(state, state.selectedNode) {
		Viewport_RenderAndInteractGizmo(state, drawList, mouseScreen, mouseWorld)
	} else {
		state.activeHandle = .None
		state.isDraggingGizmo = false
	}

	// 4. Node Picking (Left click when not dragging a gizmo and not panning).
	// Shift/Cmd/Ctrl-click adds to the selection; dragging on empty space
	// with the Select tool draws a selection box.
	additive := io.KeyShift || io.KeyCtrl || io.KeySuper
	if state.viewportHovered && imgui.IsMouseClicked(.Left) && !state.isDraggingGizmo && !shapeOwnsMouse && !guidesOwn && state.toolMode != .Pan {
		if state.activeHandle == .None {
			picked := Viewport_PickNode(state, mouseWorld)
			if picked != nil || !additive do Editor_SelectNode(state, picked, additive)
			if picked != nil {
				PreviewPanel_OnNodeSelected(state, picked)
			} else if state.toolMode == .Select {
				state.boxSelecting = true
				state.boxStart = mouseWorld
			}
		}
	}
	if state.boxSelecting {
		a := Viewport_WorldToScreen(state, state.boxStart)
		imgui.DrawList_AddRectFilled(drawList, {min(a.x, mouseScreen.x), min(a.y, mouseScreen.y)}, {max(a.x, mouseScreen.x), max(a.y, mouseScreen.y)}, col_u32(UI_ACCENT_SOFT))
		imgui.DrawList_AddRect(drawList, {min(a.x, mouseScreen.x), min(a.y, mouseScreen.y)}, {max(a.x, mouseScreen.x), max(a.y, mouseScreen.y)}, col_u32(UI_ACCENT))
		if !imgui.IsMouseDown(.Left) {
			state.boxSelecting = false
			mn := [2]f32{min(state.boxStart.x, mouseWorld.x), min(state.boxStart.y, mouseWorld.y)}
			mx := [2]f32{max(state.boxStart.x, mouseWorld.x), max(state.boxStart.y, mouseWorld.y)}
			if mx.x - mn.x > 2 / state.cameraZoom || mx.y - mn.y > 2 / state.cameraZoom {
				Viewport_BoxSelect(state, mn, mx, additive)
			}
		}
	}
}

// Viewport_BoxSelect selects every visible node whose bounds intersect the box.
Viewport_BoxSelect :: proc(state: ^EditorState, mn, mx: [2]f32, additive: bool) {
	if state.activeScene == nil do return
	if !additive do Editor_ClearSelection(state)
	for node in state.activeScene.manager.nodes {
		if node == nil || node == state.activeScene.rootNode || !node.enabled || !node.renderable || node.transient do continue
		if Editor_NodeLocked(state, node) || Editor_ViewLocked(state, node) || Editor_ViewHidden(state, node) do continue
		q, _ := Node_Bounds(state, node)
		bmn, bmx := q[0], q[0]
		for p in q {
			bmn = {min(bmn.x, p.x), min(bmn.y, p.y)}
			bmx = {max(bmx.x, p.x), max(bmx.y, p.y)}
		}
		if bmx.x < mn.x || bmn.x > mx.x || bmx.y < mn.y || bmn.y > mx.y do continue
		if !Editor_IsSelected(state, node) {
			append(&state.selection, node)
			state.selectedNode = node
		}
	}
}

// Interactive Transform Gizmo (Translate, Rotate, Scale)
Viewport_RenderAndInteractGizmo :: proc(state: ^EditorState, drawList: ^imgui.DrawList, mouseScreen, mouseWorld: [2]f32) {
	node := state.selectedNode
	if node == nil do return

	// Gizmos work in world space; edits are converted back to the node's
	// parent space (children of moved/rotated parents behave correctly).
	nodeWorld := node.globalPosition
	nodeScreen := Viewport_WorldToScreen(state, nodeWorld)
	mgr := state.activeScene.manager

	gizmoLen: f32 = 80.0
	handleRadius: f32 = 8.0
	centerBoxSize: f32 = 14.0

	// GitKraken palette colors
	colRed := col32(235, 77, 75, 240)    // Coral Red
	colGreen := col32(0, 184, 148, 240)  // Mint Green
	colBlue := col32(9, 132, 227, 240)   // Bright Blue
	colTeal := col32(0, 206, 201, 255)   // Signature Teal
	colWhite := col32(230, 235, 240, 220)

	xEnd := nodeScreen + [2]f32{gizmoLen, 0}
	yEnd := nodeScreen + [2]f32{0, -gizmoLen}

	if !state.isDraggingGizmo {
		state.activeHandle = .None

		#partial switch state.toolMode {
		case .Translate:
			if point_in_rect(mouseScreen, nodeScreen - centerBoxSize * 0.5, nodeScreen + centerBoxSize * 0.5) {
				state.activeHandle = .TranslateCenter
			} else if point_in_circle(mouseScreen, xEnd, handleRadius + 4.0) {
				state.activeHandle = .TranslateX
			} else if point_in_circle(mouseScreen, yEnd, handleRadius + 4.0) {
				state.activeHandle = .TranslateY
			}

		case .Rotate:
			dist := math.sqrt(math.pow(mouseScreen.x - nodeScreen.x, 2) + math.pow(mouseScreen.y - nodeScreen.y, 2))
			if math.abs(dist - gizmoLen) <= handleRadius + 4.0 {
				state.activeHandle = .RotateRing
			}

		case .Scale:
			cornerPos := nodeScreen + [2]f32{gizmoLen * 0.7, -gizmoLen * 0.7}
			if point_in_circle(mouseScreen, cornerPos, handleRadius + 4.0) {
				state.activeHandle = .ScaleCorner
			} else if point_in_circle(mouseScreen, xEnd, handleRadius + 4.0) {
				state.activeHandle = .ScaleX
			} else if point_in_circle(mouseScreen, yEnd, handleRadius + 4.0) {
				state.activeHandle = .ScaleY
			}
		}

		if state.activeHandle != .None && imgui.IsMouseClicked(.Left) && state.viewportHovered {
			Editor_RecordUndo(state, "Transform")
			state.isDraggingGizmo = true
			state.dragStartMouse = mouseWorld
			state.dragStartPos = node.globalPosition // world space
			state.dragStartRot = node.rotation
			state.dragStartScale = node.scale
			// Alt + the move handle: moves the pivot, not the node.
			pivotDrag = state.activeHandle == .TranslateCenter && imgui.GetIO().KeyAlt
			// Other selected nodes move/rotate/scale along.
			clear(&state.dragOthers)
			if !pivotDrag {
				for other in Editor_SelectionRoots(state) {
					if other == node || Editor_ViewLocked(state, other) do continue
					append(&state.dragOthers, Drag_Start{other, other.globalPosition, other.rotation, other.scale})
				}
			}
			SmartSnap_Begin(state, pivotDrag)
		}
	}

	if state.isDraggingGizmo {
		if imgui.IsMouseDown(.Left) {
			deltaWorld := mouseWorld - state.dragStartMouse

			#partial switch state.activeHandle {
			case .TranslateCenter:
				// Snap in world space, so snapped nodes line up with the grid.
				newWorld := state.dragStartPos + deltaWorld
				snapped := SmartSnap_Apply(state, state.dragStartPos, &newWorld, {true, true})
				if state.snapGrid && state.gridSize > 0 {
					if !snapped.x do newWorld.x = math.round(newWorld.x / state.gridSize) * state.gridSize
					if !snapped.y do newWorld.y = math.round(newWorld.y / state.gridSize) * state.gridSize
				}
				if pivotDrag {
					Pivot_MoveTo(state, node, newWorld)
				} else {
					node.position = e.Node_WorldToParent(mgr, node, newWorld)
				}

			case .TranslateX:
				newWorld := [2]f32{state.dragStartPos.x + deltaWorld.x, state.dragStartPos.y}
				snapped := SmartSnap_Apply(state, state.dragStartPos, &newWorld, {true, false})
				if state.snapGrid && state.gridSize > 0 && !snapped.x {
					newWorld.x = math.round(newWorld.x / state.gridSize) * state.gridSize
				}
				node.position = e.Node_WorldToParent(mgr, node, newWorld)

			case .TranslateY:
				newWorld := [2]f32{state.dragStartPos.x, state.dragStartPos.y + deltaWorld.y}
				snapped := SmartSnap_Apply(state, state.dragStartPos, &newWorld, {false, true})
				if state.snapGrid && state.gridSize > 0 && !snapped.y {
					newWorld.y = math.round(newWorld.y / state.gridSize) * state.gridSize
				}
				node.position = e.Node_WorldToParent(mgr, node, newWorld)

			case .RotateRing:
				vStart := state.dragStartMouse - nodeWorld
				vCurrent := mouseWorld - nodeWorld
				angleStart := math.atan2(vStart.y, vStart.x) * (180.0 / math.PI)
				angleCurrent := math.atan2(vCurrent.y, vCurrent.x) * (180.0 / math.PI)
				deltaAngle := angleCurrent - angleStart

				newRot := state.dragStartRot + deltaAngle
				if state.snapRotation && state.rotationSnapStep > 0 {
					newRot = math.round(newRot / state.rotationSnapStep) * state.rotationSnapStep
				}
				node.rotation = newRot

			case .ScaleCorner:
				ratio := 1.0 + (deltaWorld.x - deltaWorld.y) * 0.01
				node.scale = state.dragStartScale * math.max(f32(0.01), ratio)

			case .ScaleX:
				ratioX := 1.0 + deltaWorld.x * 0.01
				node.scale.x = state.dragStartScale.x * math.max(f32(0.01), ratioX)

			case .ScaleY:
				ratioY := 1.0 - deltaWorld.y * 0.01
				node.scale.y = state.dragStartScale.y * math.max(f32(0.01), ratioY)

			case .None:
			}

			// Apply the primary node's change to the rest of the selection.
			for d in state.dragOthers {
				if !e.Node_IsAlive(d.node) do continue
				#partial switch state.activeHandle {
				case .TranslateCenter, .TranslateX, .TranslateY:
					primaryWorld := e.Node_ParentToWorld(mgr, node, node.position)
					d.node.position = e.Node_WorldToParent(mgr, d.node, d.startPos + (primaryWorld - state.dragStartPos))
				case .RotateRing:
					d.node.rotation = d.startRot + (node.rotation - state.dragStartRot)
				case .ScaleCorner, .ScaleX, .ScaleY:
					ratio := [2]f32{node.scale.x / max(state.dragStartScale.x, 0.0001), node.scale.y / max(state.dragStartScale.y, 0.0001)}
					d.node.scale = d.startScale * ratio
				}
			}

			imgui.BeginTooltip()
			#partial switch state.activeHandle {
			case .TranslateCenter, .TranslateX, .TranslateY:
				imgui.Text(fmt.ctprintf("%s: (%.1f, %.1f)", "Pivot" if pivotDrag else "Position", node.position.x, node.position.y))
			case .RotateRing:
				imgui.Text(fmt.ctprintf("Rotation: %.1f deg", node.rotation))
			case .ScaleCorner, .ScaleX, .ScaleY:
				imgui.Text(fmt.ctprintf("Scale: (%.2f, %.2f)", node.scale.x, node.scale.y))
			case .None:
			}
			imgui.EndTooltip()

		} else {
			state.isDraggingGizmo = false
			state.activeHandle = .None
			pivotDrag = false
			smartSnap.has = {}
		}
	}

	#partial switch state.toolMode {
	case .Select:
		imgui.DrawList_AddCircle(drawList, imgui.Vec2{nodeScreen.x, nodeScreen.y}, 14.0, colTeal, 32, 2.0)

	case .Pan:

	case .Translate:
		// Center Box (Free XY Translation)
		cBoxCol := (state.activeHandle == .TranslateCenter) ? colTeal : colWhite
		imgui.DrawList_AddRectFilled(
			drawList,
			imgui.Vec2{nodeScreen.x - centerBoxSize * 0.5, nodeScreen.y - centerBoxSize * 0.5},
			imgui.Vec2{nodeScreen.x + centerBoxSize * 0.5, nodeScreen.y + centerBoxSize * 0.5},
			cBoxCol,
			3.0,
			{},
		)

		// X Axis (Coral Red Arrow)
		colX := (state.activeHandle == .TranslateX) ? colTeal : colRed
		imgui.DrawList_AddLine(drawList, imgui.Vec2{nodeScreen.x, nodeScreen.y}, imgui.Vec2{xEnd.x, xEnd.y}, colX, 3.0)
		imgui.DrawList_AddTriangleFilled(
			drawList,
			imgui.Vec2{xEnd.x + 10.0, xEnd.y},
			imgui.Vec2{xEnd.x, xEnd.y - 6.0},
			imgui.Vec2{xEnd.x, xEnd.y + 6.0},
			colX,
		)

		// Y Axis (Mint Green Arrow)
		colY := (state.activeHandle == .TranslateY) ? colTeal : colGreen
		imgui.DrawList_AddLine(drawList, imgui.Vec2{nodeScreen.x, nodeScreen.y}, imgui.Vec2{yEnd.x, yEnd.y}, colY, 3.0)
		imgui.DrawList_AddTriangleFilled(
			drawList,
			imgui.Vec2{yEnd.x, yEnd.y - 10.0},
			imgui.Vec2{yEnd.x - 6.0, yEnd.y},
			imgui.Vec2{yEnd.x + 6.0, yEnd.y},
			colY,
		)

	case .Rotate:
		colRot := (state.activeHandle == .RotateRing) ? colTeal : colBlue
		imgui.DrawList_AddCircle(drawList, imgui.Vec2{nodeScreen.x, nodeScreen.y}, gizmoLen, colRot, 48, 2.5)

		rad := node.rotation * (math.PI / 180.0)
		rotIndicator := nodeScreen + [2]f32{math.cos(rad) * gizmoLen, math.sin(rad) * gizmoLen}
		imgui.DrawList_AddLine(drawList, imgui.Vec2{nodeScreen.x, nodeScreen.y}, imgui.Vec2{rotIndicator.x, rotIndicator.y}, colTeal, 2.0)
		imgui.DrawList_AddCircleFilled(drawList, imgui.Vec2{rotIndicator.x, rotIndicator.y}, 6.0, colTeal, 16)

	case .Scale:
		cornerPos := nodeScreen + [2]f32{gizmoLen * 0.7, -gizmoLen * 0.7}
		colCorner := (state.activeHandle == .ScaleCorner) ? colTeal : colWhite
		imgui.DrawList_AddCircleFilled(drawList, imgui.Vec2{cornerPos.x, cornerPos.y}, handleRadius, colCorner, 16)
		imgui.DrawList_AddLine(drawList, imgui.Vec2{nodeScreen.x, nodeScreen.y}, imgui.Vec2{cornerPos.x, cornerPos.y}, colWhite, 1.5)

		colX := (state.activeHandle == .ScaleX) ? colTeal : colRed
		imgui.DrawList_AddLine(drawList, imgui.Vec2{nodeScreen.x, nodeScreen.y}, imgui.Vec2{xEnd.x, xEnd.y}, colX, 2.5)
		imgui.DrawList_AddRectFilled(
			drawList,
			imgui.Vec2{xEnd.x - 6.0, xEnd.y - 6.0},
			imgui.Vec2{xEnd.x + 6.0, xEnd.y + 6.0},
			colX,
			2.0,
			{},
		)

		colY := (state.activeHandle == .ScaleY) ? colTeal : colGreen
		imgui.DrawList_AddLine(drawList, imgui.Vec2{nodeScreen.x, nodeScreen.y}, imgui.Vec2{yEnd.x, yEnd.y}, colY, 2.5)
		imgui.DrawList_AddRectFilled(
			drawList,
			imgui.Vec2{yEnd.x - 6.0, yEnd.y - 6.0},
			imgui.Vec2{yEnd.x + 6.0, yEnd.y + 6.0},
			colY,
			2.0,
			{},
		)
	}
}

// Viewport_PickNode returns the top-most visible node under a world point:
// the one drawn last (layer, z index, Y sort, tree order); nodes that draw
// nothing (handles) rank under the drawn ones of their layer.
Viewport_PickNode :: proc(state: ^EditorState, worldPos: [2]f32) -> ^e.Node {
	if state.activeScene == nil || state.activeScene.manager == nil do return nil
	drawRank := make(map[^e.Node]int, 64, context.temp_allocator)
	for b in e.Scene_CollectRenderables(state.activeScene) do for n, i in b do drawRank[n] = i + 1
	best, level: ^e.Node
	bestLayer, bestRank := -1, -1
	for node in state.activeScene.manager.nodes {
		if node == nil || node == state.activeScene.rootNode || !node.enabled || !node.renderable do continue
		if Editor_ViewLocked(state, node) || Editor_ViewHidden(state, node) do continue
		q, _ := Node_Bounds(state, node)
		if !point_in_quad(worldPos, q) do continue
		// Vector shapes: on the shape itself, not just its box.
		if node.typeId == e.VectorShapeNode && !e.VectorShapeNode_HitTest(cast(^e.VectorShapeNode)node, worldPos) do continue
		// A level covers everything: picked only when nothing else is there.
		if node.typeId == e.LdtkLevelNode {
			if level == nil do level = node
			continue
		}
		rank := drawRank[node] or_else 0
		if int(node.layer) > bestLayer || (int(node.layer) == bestLayer && rank >= bestRank) {
			best, bestLayer, bestRank = node, int(node.layer), rank
		}
	}
	if best == nil do best = level
	// Clicking inside a component instance selects the instance.
	if best != nil && Editor_NodeLocked(state, best) {
		best = e.Node_ComponentRoot(state.activeScene.manager, best)
	}
	return best
}

// Viewport_DrawLdtkEntities shows LDtk entity placements in edit mode (they
// are only spawned when the game runs) and their EntityRef links as arrows.
Viewport_DrawLdtkEntities :: proc(state: ^EditorState) {
	if state.isSimulating || state.activeScene == nil || state.activeScene.manager == nil do return
	focus := Ldtk_FocusHighlight()
	z := state.cameraZoom
	for node in state.activeScene.manager.nodes {
		if node == nil || node.typeId != e.LdtkLevelNode || !node.enabled do continue
		ln := cast(^e.LdtkLevelNode)node
		if ln.level == nil || ln.project == nil do continue
		pos := ln.globalPosition
		scale := ln.globalScale
		center_of :: proc(ln: ^e.LdtkLevelNode, lvl: ^e.LdtkLevel, ent: ^e.LdtkEntityInstance) -> [2]f32 {
			c := ent.px + ent.size * ([2]f32{0.5, 0.5} - ent.pivot)
			return ln.globalPosition + (e.LdtkLevelNode_LevelOffset(ln, lvl) + c) * ln.globalScale
		}
		for lvl in ln.activeLevels {
			off := e.LdtkLevelNode_LevelOffset(ln, lvl)
			for &layer in lvl.layers {
				if !e.LdtkLevelNode_LayerVisible(ln, &layer) do continue
				for &ent in layer.entities {
					p := ent.px + off
					r := rl.Rectangle{pos.x + (p.x - ent.size.x * ent.pivot.x) * scale.x, pos.y + (p.y - ent.size.y * ent.pivot.y) * scale.y, ent.size.x * scale.x, ent.size.y * scale.y}
					col := ent.smartColor
					col.a = 200
					focused := focus != "" && ent.iid == focus
					rl.DrawRectangleLinesEx(r, (3.5 if focused else 1.5) / z, rl.Color{255, 255, 255, 255} if focused else col)
					fontSize := i32(math.clamp(11.0 / z, 6.0, 48.0))
					rl.DrawText(strings.clone_to_cstring(ent.identifier, context.temp_allocator), i32(r.x), i32(r.y - f32(fontSize) - 2 / z), fontSize, col)
					// Links: an arrow to each referenced entity that's shown.
					from := center_of(ln, lvl, &ent)
					for ref in e.Ldtk_EntityRefs(&ent) {
						tgt, tlvl := e.Ldtk_FindEntity(ln.project, ref.ref.entityIid)
						if tgt == nil do continue
						found := false
						for al in ln.activeLevels do if al == tlvl do found = true
						if !found do continue
						to := center_of(ln, tlvl, tgt)
						lc := col
						lc.a = 170
						rl.DrawLineEx(from, to, 1.5 / z, lc)
						d := to - from
						l := math.sqrt(d.x * d.x + d.y * d.y)
						if l < 1 do continue
						dir := d / l
						tip := to - dir * (min(tgt.size.x, tgt.size.y) * 0.5 * scale.x)
						side := [2]f32{-dir.y, dir.x}
						h := 7 / z
						rl.DrawTriangle(tip, tip - dir * h * 1.6 - side * h, tip - dir * h * 1.6 + side * h, lc)
						rl.DrawTriangle(tip, tip - dir * h * 1.6 + side * h, tip - dir * h * 1.6 - side * h, lc)
					}
				}
			}
		}
	}
}

// --- fit to view -------------------------------------------------------------------

// Viewport_FitRect frames a world rectangle.
Viewport_FitRect :: proc(state: ^EditorState, mn, mx: [2]f32) {
	fit_bounds(state, mn, mx, 0.92)
}

@(private = "file")
fit_bounds :: proc(state: ^EditorState, mn, mx: [2]f32, margin: f32 = 0.9) {
	size := mx - mn
	if size.x <= 0 && size.y <= 0 do return
	vs := state.viewportSize
	if vs.x <= 0 || vs.y <= 0 do vs = {800, 450}
	zx := vs.x / max(size.x, 1)
	zy := vs.y / max(size.y, 1)
	state.cameraZoom = clamp(min(zx, zy) * margin, 0.1, 10)
	state.cameraPos = (mn + mx) * 0.5
}

@(private = "file")
nodes_bounds :: proc(state: ^EditorState, onlySelected: bool) -> (mn, mx: [2]f32, ok: bool) {
	if state.activeScene == nil do return
	for node in state.activeScene.manager.nodes {
		if node == nil || node == state.activeScene.rootNode || node.typeId == e.CameraNode do continue
		if onlySelected && !Editor_IsSelected(state, node) do continue
		if !onlySelected && (!node.enabled || !node.renderable) do continue
		q, _ := Node_Bounds(state, node)
		for p in q {
			if !ok {
				mn, mx, ok = p, p, true
				continue
			}
			mn = {min(mn.x, p.x), min(mn.y, p.y)}
			mx = {max(mx.x, p.x), max(mx.y, p.y)}
		}
	}
	return
}

// Viewport_FitScene zooms to show every visible node.
Viewport_FitScene :: proc(state: ^EditorState) {
	if mn, mx, ok := nodes_bounds(state, false); ok do fit_bounds(state, mn, mx)
}

// Viewport_FitSelection zooms to the selected nodes.
Viewport_FitSelection :: proc(state: ^EditorState) {
	if mn, mx, ok := nodes_bounds(state, true); ok do fit_bounds(state, mn - 32, mx + 32)
}

// Viewport_FitGameView fits the game's frame (the current camera's view at
// the project's virtual resolution).
Viewport_FitGameView :: proc(state: ^EditorState) {
	frame := Editor_GameFrameSize(state)
	vw, vh := frame.x, frame.y
	center := [2]f32{vw * 0.5, vh * 0.5}
	if state.activeScene != nil && state.activeScene.camera != nil do center = e.CameraNode_ViewCenter(state.activeScene.camera)
	fit_bounds(state, center - {vw, vh} * 0.5, center + {vw, vh} * 0.5, 0.95)
}

// The viewport's colour vision preview (View > Colour Vision): how players
// with that deficiency see the scene (simulated, not corrected).
viewportVision: e.Colorblind_Mode

// viewport_set_vision toggles a preview (choosing the shown one turns it off).
viewport_set_vision :: proc(m: e.Colorblind_Mode) {
	viewportVision = .None if viewportVision == m else m
}
