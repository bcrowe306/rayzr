package engine

import vmem "core:mem/virtual"
import "core:log"
import "core:strings"
import b2 "vendor:box2d"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

SceneSetupProc :: proc(scene: ^Scene, gameContext: ^GameContext)
SceneUpdateProc :: proc(scene: ^Scene, gameContext: ^GameContext, deltaTime: f32)
SceneLifecycleProc :: proc(scene: ^Scene, gameContext: ^GameContext)

Scene :: struct {
	manager: ^NodeManager,
	name: string,
	filePath: string,   // project-relative scene file ("scenes/main.scene.json"), "" for code scenes
	sourceJson: string, // scene file contents; rebuilt from on every (re)load
	drawBounds: bool,
	// Clear colour while this scene runs (alpha 0 = the game's default).
	backgroundColor: rl.Color,
	ambient: rl.Color, // light map base colour when the scene uses lighting ({} = white)
	// Editor guide lines (saved with the scene; the game ignores them).
	guides:     [SCENE_MAX_GUIDES]Scene_Guide,
	guideCount: int,
	rootNode: ^Node,
	camera: ^CameraNode,
	setup: SceneSetupProc,
	update: SceneUpdateProc,
	onEnter: SceneLifecycleProc,
	onExit: SceneLifecycleProc,
	addNode: proc(scene: ^Scene, node: ^Node, parent: ^Node = nil),
	removeNode: proc(scene: ^Scene, node: ^Node),
	addChild: proc(scene: ^Scene, parent, child: ^Node),
	removeChild: proc(scene: ^Scene, parent, child: ^Node),
	isLoaded: bool,
	pools: [dynamic]^Node_Pool, // node pools (node_pool.odin), freed on unload
}

SCENE_MAX_GUIDES :: 64

Scene_Guide :: struct {
	vertical: bool, // a vertical line at x = pos (else horizontal at y = pos)
	pos:      f32,
}

// Render_HideEditorHidden: the editor's viewport skips nodes marked
// editorHidden (and their children); the game never sets it.
Render_HideEditorHidden: bool

// Render_EditorView: the editor's viewport is drawing - placeholders for
// nodes with nothing to show yet (a Nine Slice without an image) are drawn
// there and not in the game (#221).
Render_EditorView: bool

CreateNodeScene :: proc(scene: ^Scene, $T: typeid, addToScene: bool = false) -> (node: ^T) {
	allocator := vmem.arena_allocator(&scene.manager.arena)
	node = new(T, allocator)
	(cast(^Node)node).typeId = T
	InitializeNode(cast(^Node)node)
	if addToScene do SceneAddNode(scene, node)
	return node
}

SceneAddNode :: proc(scene: ^Scene, node: ^Node, parent: ^Node = nil) {
	_, err := append(&scene.manager.addition, node)
	if err != nil {
		log.error("Error queueing node for addition. ", err)
		return
	}
	node.inTree = true
	if parent == nil && scene.rootNode != node {
		AddChild(scene.manager, scene.rootNode, node)
	} else if parent != nil {
		AddChild(scene.manager, parent, node)
	}
}

SceneRemoveNode :: proc(scene: ^Scene, node: ^Node) {
	RemoveNode(scene.manager, node)
}

SceneAddChild :: proc(scene: ^Scene, parent, child: ^Node) {
	AddChild(scene.manager, parent, child)
}

SceneRemoveChild :: proc(scene: ^Scene, parent, child: ^Node) {
	RemoveChild(scene.manager, parent, child)
}

// CreateScene registers a new scene under `name` (cloned). A scene with the
// same name is replaced: it is terminated and any current/next pointer to it
// is cleared, so nothing keeps pointing at the destroyed scene.
CreateScene :: proc(manager: ^SceneManager, name: string, next_scene: bool, setup: SceneSetupProc = nil) -> ^Scene {
	allocator := manager.allocator if manager.allocator.procedure != nil else context.allocator
	if existing, exists := manager.scenes[name]; exists && existing != nil {
		if manager.currentScene == existing do manager.currentScene = nil
		if manager.nextScene == existing do manager.nextScene = nil
		TerminateScene(existing)
	}

	newScene := new(Scene, allocator)
	ownedName := strings.clone(name, allocator)
	newScene.name = ownedName
	newScene.setup = setup
	manager.scenes[ownedName] = newScene

	InitializeScene(newScene)
	if next_scene do manager.nextScene = newScene
	return newScene
}

InitializeScene :: proc(scene: ^Scene) {
	scene.manager = new(NodeManager)
	NodeManager_Init(scene.manager)
	scene.rootNode = CreateNode(scene.manager, Node)
	scene.rootNode.name = "root"
	scene.rootNode.isReady = true
	scene.camera = nil
	SceneAddNode(scene, scene.rootNode)
	scene.isLoaded = false

	// Methods
	scene.addNode = SceneAddNode
	scene.removeNode = SceneRemoveNode
	scene.addChild = SceneAddChild
	scene.removeChild = SceneRemoveChild
}

// Unload all nodes in the scene, calling onDestroy on each, reclaiming node memory,
// and resetting state so the scene can be reloaded fresh.
Scene_Unload :: proc(scene: ^Scene, gameContext: ^GameContext = nil) {
	if scene == nil || scene.manager == nil do return

	if gameContext != nil {
		for node in scene.manager.nodes {
			if node != nil {
				node.gameContext = gameContext
				Node_NotifyEvent(node, .Exited_Tree, nil, gameContext)
			}
		}
	}

	scene.camera = nil

	Pools_Destroy(scene)
	NodeManager_Terminate(scene.manager)
	NodeManager_Init(scene.manager)

	scene.rootNode = CreateNode(scene.manager, Node)
	scene.rootNode.name = "root"
	scene.rootNode.isReady = true
	SceneAddNode(scene, scene.rootNode)
	ProcessNodeQueues(scene.manager, gameContext)

	scene.isLoaded = false
}

// Loads the scene: calls setup to create all initial nodes, registers them into
// the node manager, computes global positions, and then calls ready on all initial nodes.
Scene_Load :: proc(scene: ^Scene, gameContext: ^GameContext) {
	if scene == nil do return
	if gameContext != nil {
		gameContext.scene = scene
	}
	if scene.manager == nil {
		InitializeScene(scene)
	} else if scene.isLoaded {
		Scene_Unload(scene, gameContext)
	}

	// 1. Run setup callback to construct all initial scene nodes
	if scene.setup != nil {
		scene->setup(gameContext)
	}

	// 2. Process node queues so all initial nodes are present in manager.nodes
	ProcessNodeQueues(scene.manager, gameContext)

	// 3. Propagate initial global positions
	Node_SetGlobalPositions(scene.manager, scene.rootNode)

	// 4. Now that ALL other initial scene nodes are present, call ready on all nodes!
	Scene_CallReady(scene, scene.rootNode, gameContext)

	scene.isLoaded = true
}

// Recursively calls ready on all unready nodes in the hierarchy.
// Each node has ready called exactly once.
Scene_CallReady :: proc(scene: ^Scene, node: ^Node, gameContext: ^GameContext) {
	if node == nil || !node.enabled do return

	if gameContext != nil {
		node.gameContext = gameContext
	}

	if !node.isReady {
		node.isReady = true
		if node.ready != nil {
			node->ready(gameContext)
		}
		if node.scriptInstance != nil {
			sm := gameContext.scriptManager if gameContext != nil else nil
			ScriptInstance_CallReady(cast(^ScriptInstance)node.scriptInstance, sm)
		}
	}

	for child in GetChildrenTemp(scene.manager, node) {
		Scene_CallReady(scene, child, gameContext)
	}
}

// Scene_JsonSetup is the setup proc of data-driven scenes: it rebuilds the
// scene from its stored JSON each time the scene is loaded, so leaving and
// re-entering a scene restores it instead of leaving it empty.
Scene_JsonSetup :: proc(scene: ^Scene, gameContext: ^GameContext) {
	if scene.sourceJson == "" do return
	Scene_InstantiateFromJSON(scene, transmute([]u8)scene.sourceJson, gameContext)
}

TerminateScene :: proc(scene: ^Scene) {
	if scene == nil do return
	Pools_Destroy(scene)
	if scene.manager != nil {
		NodeManager_Terminate(scene.manager)
		free(scene.manager)
		scene.manager = nil
	}
	scene.rootNode = nil
	scene.camera = nil
	scene.isLoaded = false
}

RunScene :: proc(scene: ^Scene, gameContext: ^GameContext, deltaTime: f32) {
	if scene == nil || scene.manager == nil {
		return
	}

	if !scene.isLoaded {
		Scene_Load(scene, gameContext)
	}

	if gameContext != nil {
		gameContext.camera = scene.camera
	}

	nodeManager := scene.manager
	nodeManager.screen = Screen_MappingForGame(gameContext) // Screen Layers: the frame (#175)

	// Process Node Queues (any spawned or removed nodes)
	Prof_Begin("scene.queues+ready")
	ProcessNodeQueues(nodeManager, gameContext)

	// Ensure any newly added nodes have their ready proc called before update
	Scene_CallReady(scene, scene.rootNode, gameContext)
	Prof_End()

	frozen := gameContext != nil && gameContext.game != nil && gameContext.game.frozen
	if scene.update != nil && !frozen {
		scene->update(gameContext, deltaTime)
	}

	if scene.rootNode == nil {
		return
	}

	// Propagate initial global positions before hierarchy update
	Prof_Begin("transforms")
	Node_SetGlobalPositions(nodeManager, scene.rootNode)
	Prof_End()

	if !frozen {
		// Update active dropdown popup first so it can capture clicks before underlying widgets
		UI_UpdateActiveDropdownOverlay(gameContext)

		// Update UI keyboard navigation and focus state
		UI_UpdateFocusNavigation(scene, gameContext)

		// Update hierarchy (calls update on each node)
		Prof_Begin("scene.update")
		Scene_UpdateNodeHirearchy(scene, scene.rootNode, gameContext, deltaTime)
		Prof_End()
		Prof_Begin("tweens")
		if gameContext != nil && gameContext.game != nil do Tween_Update(&gameContext.game.tweens, deltaTime, &gameContext.game.scriptManager)
		Prof_End()
	}

	// Update global positions after node updates & container layout
	Prof_Begin("transforms")
	Node_SetGlobalPositions(nodeManager, scene.rootNode)
	Prof_End()
	Prof_Begin("visibility+subtitles")
	if !frozen do Visibility_Update(scene, gameContext) // on / off screen (visibility_notifier.odin)
	if !frozen do Subtitles_Update(deltaTime)           // (subtitles.odin)
	Prof_End()

	// One traversal buckets renderable nodes by layer (hierarchy order is
	// kept within a layer) instead of walking the whole tree per layer.
	Prof_Begin("render.collect")
	screenBuckets: [RenderLayer][dynamic]^Node
	buckets := Scene_CollectRenderables(scene, &screenBuckets)
	Prof_End()
	renderStats = {}
	// Lighting: the light map is built before the world layers draw and
	// multiplied over them after the last one.
	lightVW, lightVH: f32 = 1280, 720
	if gameContext != nil && gameContext.game != nil && gameContext.game.virtualSize.x > 0 {
		lightVW, lightVH = gameContext.game.virtualSize.x, gameContext.game.virtualSize.y
	}
	lastWorld := -1
	// Filtered vector art: its textures, made before any layer draws (vector_filters.odin).
	if rl.IsWindowReady() {
		zoom: f32 = 1
		if scene.camera != nil && scene.camera.enabled && scene.camera.isCurrent do zoom = CameraNode_GetCamera2D(scene.camera, lightVW, lightVH).zoom
		Prof_Scope("vector.filters")
		Vector_FiltersPrepare(scene, zoom)
	}
	// Viewports (viewport_node.odin): their pictures, before the frame draws
	// them (and before the frame's own tile chunks).
	mainView: Maybe(rl.Rectangle)
	if scene.camera != nil && scene.camera.enabled && scene.camera.isCurrent do mainView = Camera2D_ViewRect(CameraNode_GetCamera2D(scene.camera, lightVW, lightVH), lightVW, lightVH)
	if rl.IsWindowReady() {
		Prof_Scope("viewports")
		Viewports_Render(scene, gameContext, mainView, &buckets)
	}
	covered := Viewports_CoverScreen(scene) // (split-screen: the main view's world isn't seen)
	if scene.camera != nil && scene.camera.enabled && scene.camera.isCurrent && rl.IsWindowReady() {
		// Cached tile chunks in view (built before any layer draws).
		Prof_Begin("tilecache.prepare")
		TileCache_Prepare(scene, Camera2D_ViewRect(CameraNode_GetCamera2D(scene.camera, lightVW, lightVH), lightVW, lightVH), gameContext)
		Prof_End()
		for l in RenderLayer do if l in scene.camera.targetLayers do lastWorld = int(l)
		if lastWorld >= 0 {
			Prof_Scope("lighting.prepare")
			Lighting_Prepare(scene, CameraNode_GetCamera2D(scene.camera, lightVW, lightVH), i32(lightVW), i32(lightVH))
		}
	}
	// Smooth camera (pixel_perfect.odin): the world layers go to a texture a
	// pixel larger on every side, the others to the frame (on top).
	frame := Render_FrameTarget()
	smooth := renderPixel.smooth && frame != nil && rl.IsWindowReady()
	renderPixel.usedWorld = false
	inWorld := false
	for layer in RenderLayer {
		isWorldLayer := scene.camera != nil && scene.camera.enabled && scene.camera.isCurrent && (layer in scene.camera.targetLayers)
		if smooth && isWorldLayer != inWorld {
			rl.EndTextureMode()
			if isWorldLayer {
				w := Pixel_WorldTarget(frame.texture.width, frame.texture.height)
				Render_SetFrameTarget(w) // mid-frame passes come back to it
				rl.BeginTextureMode(w^)
				if !renderPixel.usedWorld {
					rl.ClearBackground(Game_ClearColor(gameContext.game) if gameContext != nil && gameContext.game != nil else rl.BLACK)
					renderPixel.usedWorld = true
				}
				renderPixel.margin = PIXEL_MARGIN
			} else {
				Render_SetFrameTarget(frame)
				rl.BeginTextureMode(frame^)
				renderPixel.margin = 0
			}
			inWorld = isWorldLayer
		}
		if isWorldLayer && rl.IsWindowReady() {
			vw: f32 = 1280
			vh: f32 = 720
			if gameContext != nil && gameContext.game != nil && gameContext.game.virtualSize.x > 0 {
				vw = gameContext.game.virtualSize.x
				vh = gameContext.game.virtualSize.y
			}
			CameraNode_Begin(scene.camera, vw, vh)
			Render_SetView(Camera2D_ViewRect(CameraNode_GetCamera2D(scene.camera, vw, vh), vw, vh))
		}

		if len(buckets[layer]) > 0 && !(covered && isWorldLayer) {
			Prof_Scope("render.layer")
			// Smooth camera: the layers over the world go into a transparent
			// frame, composited later. Plain alpha blending would square the
			// alpha of anti-aliased edges there (washed-out UI text): keep the
			// alpha as drawn (the frame holds premultiplied colour).
			over := smooth && !isWorldLayer
			if over {
				rlgl.SetBlendFactorsSeparate(rlgl.SRC_ALPHA, rlgl.ONE_MINUS_SRC_ALPHA, rlgl.ONE, rlgl.ONE_MINUS_SRC_ALPHA, rlgl.FUNC_ADD, rlgl.FUNC_ADD)
				rl.BeginBlendMode(.CUSTOM_SEPARATE)
			}
			render_bucket(scene, buckets[layer][:], gameContext, deltaTime)
			if over do rl.EndBlendMode()
		}

		if isWorldLayer && rl.IsWindowReady() {
			Render_ClearView()
			CameraNode_End()
		}
		if int(layer) == lastWorld {
			Prof_Scope("lighting.composite")
			Lighting_Composite()
		}
	}
	if inWorld {
		rl.EndTextureMode()
		Render_SetFrameTarget(frame)
		rl.BeginTextureMode(frame^)
		renderPixel.margin = 0
	}
	// Screen Layers: over the world, in screen space (no camera, no culling).
	for layer in RenderLayer do if len(screenBuckets[layer]) > 0 do render_bucket(scene, screenBuckets[layer][:], gameContext, deltaTime)

	// Render any active UI popups/dropdowns on top of all layers
	UI_RenderActiveDropdownOverlay(gameContext)
	if gameContext != nil && gameContext.game != nil do EditorLink_DrawOverlay(gameContext.game) // (the editor's highlighted node)
	if gameContext != nil && gameContext.game != nil do Console_DrawWorld(gameContext.game) // (the developer console's debug drawing)
	Subtitles_Render(gameContext) // the subtitle track over everything (subtitles.odin)
}

// Scene_UpdateNodeHirearchy updates a subtree (ready() first time, update,
// scripts), skipping paused nodes: a node's own `paused` flag pauses its
// subtree, the game's pause (Engine.set_paused) pauses everything, and
// nodes with pauseMode Always keep running through either.
Scene_UpdateNodeHirearchy :: proc(scene: ^Scene, node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	gamePaused := gameContext != nil && gameContext.game != nil && gameContext.game.treePaused
	if !gamePaused && gameContext != nil && node == scene.rootNode do Globals_Update(gameContext.scriptManager, deltaTime)
	update_tree(scene, node, gameContext, deltaTime, gamePaused, .Pausable)
}

@(private = "file")
update_tree :: proc(scene: ^Scene, node: ^Node, gameContext: ^GameContext, deltaTime: f32, parentPaused: bool, parentMode: Pause_Mode) {
	if node == nil do return
	if !node.enabled {
		Physics_NodeDisabled(node) // (no update, so its body / joint stop here; #219)
		return
	}
	mode := node.pauseMode if node.pauseMode != .Inherit else parentMode
	paused := node.paused || (mode == .Pausable && parentPaused)
	node.pausedNow = paused
	// Game feel (game_feel.odin): this node's dt - real time for UI, cameras
	// and Always nodes; else the game's scaled dt times its tags' scale
	// (passed on to its children). A tag scale of 0 freezes its body too.
	deltaTime := deltaTime
	frozen := false
	if game := gameContext.game if gameContext != nil else nil; game != nil {
		if GameFeel_KeepsRealTime(node, mode) {
			deltaTime = game.feel.rawDelta
		} else if s := Node_TimeScale(game, node); s != 1 {
			deltaTime *= s
			frozen = s == 0
		}
	}
	if (paused || frozen) != node.bodyPaused {
		// Freeze / release its physics body with it.
		if body := Physics_BodyOf(node); b2.Body_IsValid(body) {
			if paused || frozen do b2.Body_Disable(body)
			else do b2.Body_Enable(body)
		}
		node.bodyPaused = paused || frozen
	}

	if gameContext != nil {
		node.gameContext = gameContext
	}

	if !node.isReady {
		node.isReady = true
		if node.ready != nil do node->ready(gameContext)
		if node.scriptInstance != nil {
			sm := gameContext.scriptManager if gameContext != nil else nil
			ScriptInstance_CallReady(cast(^ScriptInstance)node.scriptInstance, sm)
		}
	}

	if node.poolSpawn {
		// Taken from its pool: reset per-life state (node_pool.odin).
		node.poolSpawn = false
		if gameContext != nil do Script_CallMethod(gameContext.scriptManager, node, "on_spawn", nil, quiet = true)
	}

	// Copy: updates may add or remove children while we iterate.
	children := GetChildrenTemp(scene.manager, node)

	if !paused {
		if node.isUI do uiInputNode = node // (UI_GetMousePos reads in its UI-scale space)
		if node.update != nil do node->update(gameContext, deltaTime)
		if node.scriptInstance != nil {
			sm := gameContext.scriptManager if gameContext != nil else nil
			ScriptInstance_CallUpdate(cast(^ScriptInstance)node.scriptInstance, deltaTime, sm)
		}
		uiInputNode = nil
	}

	for child in children {
		update_tree(scene, child, gameContext, deltaTime, paused, mode)
	}
}

Scene_RenderNodeHirearchy :: proc(scene: ^Scene, node: ^Node, gameContext: ^GameContext, deltaTime: f32, layer: RenderLayer) {
	if node == nil || !node.enabled do return
	children := GetChildrenView(scene.manager, node)
	if node.renderable && node.layer == layer {
		if node.render != nil do node->render(gameContext, deltaTime)
		if node.scriptInstance != nil do Script_DrawNode(node, gameContext)

		if scene.drawBounds && node.drawBounds != nil do node->drawBounds(gameContext, deltaTime)
	}

	for child in children {
		Scene_RenderNodeHirearchy(scene, child, gameContext, deltaTime, layer)
	}
}

Scene_FindNodeByName :: proc(scene: ^Scene, name: string) -> ^Node {
	if scene == nil || scene.manager == nil do return nil
	for node in scene.manager.nodes {
		if node != nil && node.name == name do return node
	}
	for node in scene.manager.addition {
		if node != nil && node.name == name do return node
	}
	return nil
}

// Scene_FindNodeByType returns the first node of the given concrete type.
Scene_FindNodeByType :: proc(scene: ^Scene, t: typeid) -> ^Node {
	if scene == nil || scene.manager == nil do return nil
	for node in scene.manager.nodes {
		if node != nil && node.typeId == t do return node
	}
	for node in scene.manager.addition {
		if node != nil && node.typeId == t do return node
	}
	return nil
}

// Scene_RenderAllLayers draws every layer in order from one traversal, with
// whatever 2D camera is active (the editor viewport's), culled to `view`
// when given. The game uses RunScene, which also switches to the scene
// camera per world layer.
Scene_RenderAllLayers :: proc(scene: ^Scene, gameContext: ^GameContext, deltaTime: f32, view: Maybe(rl.Rectangle) = nil) {
	screen: [RenderLayer][dynamic]^Node
	buckets := Scene_CollectRenderables(scene, &screen)
	renderStats = {}
	if v, ok := view.?; ok do Render_SetView(v)
	defer Render_ClearView()
	for layer in RenderLayer do render_bucket(scene, buckets[layer][:], gameContext, deltaTime)
	// Screen Layers last (on top); placed by the scene's screen mapping.
	for layer in RenderLayer do render_bucket(scene, screen[layer][:], gameContext, deltaTime)
}

// render_bucket draws one layer's nodes, skipping those outside the view.
@(private = "file")
render_bucket :: proc(scene: ^Scene, nodes: []^Node, gameContext: ^GameContext, deltaTime: f32) {
	Prof_Begin("render.cull+order")
	visible := make([dynamic]^Node, 0, len(nodes), context.temp_allocator)
	for node in nodes {
		if renderView.active {
			if r, ok := Node_RenderBounds(node); ok && !Render_IsVisible(r) {
				renderStats.culled += 1
				continue
			}
		}
		append(&visible, node)
	}
	// Sprites sharing a texture drawn together (same picture: batching.odin).
	order := Render_BatchOrder(visible[:])
	Prof_End()
	Prof_Scope("render.draw")
	for node in order {
		// Game feel: blinked out, or drawn in a flash colour (game_feel.odin).
		draw, flashing := true, false
		if len(nodeFx) > 0 do draw, flashing = Fx_BeginDraw(node, node.material == nil)
		if !draw do continue
		defer if flashing do Fx_EndDraw()
		renderStats.drawn += 1
		withMaterial := node.material != nil && Material_Begin(node, gameContext)
		scaled := node.isUI && access.uiScale != 1 && UI_BeginScaled(node) // (accessibility UI scale)
		if node.render != nil do node->render(gameContext, deltaTime)
		if node.scriptInstance != nil do Script_DrawNode(node, gameContext) // (on_draw: vector_canvas.odin)
		if scaled do UI_EndScaled()
		if withMaterial do Material_End(node)
		if scene.drawBounds && node.drawBounds != nil do node->drawBounds(gameContext, deltaTime)
	}
}

// Scene_CollectRenderables walks the enabled hierarchy once and returns the
// renderable nodes of each layer in draw order (temp-allocated): tree
// order, then Y-sorted subtrees (a ySort node's children by Y, each with
// its subtree), then zIndex (stable). The sorts run on 16-byte items and
// only where a ySort node / a zIndex is used.
Scene_CollectRenderables :: proc(scene: ^Scene, screen: ^[RenderLayer][dynamic]^Node = nil) -> (buckets: [RenderLayer][dynamic]^Node) {
	collect, onScreen: Render_Collect
	for &l in collect.items do l = make([dynamic]Render_Item, context.temp_allocator)
	for &l in onScreen.items do l = make([dynamic]Render_Item, context.temp_allocator)
	// (Screen Layers' subtrees apart: drawn after the world, in screen space - #175.)
	if screen != nil do collect.screen = &onScreen
	if scene != nil && scene.manager != nil do render_walk(&collect, scene.manager, scene.rootNode, 0, 0)
	buckets = render_buckets(&collect)
	if screen != nil do screen^ = render_buckets(&onScreen)
	return
}

// Scene_CollectSubtree: the drawables of a node's subtree (not the node),
// as Scene_CollectRenderables (a Children viewport's picture).
Scene_CollectSubtree :: proc(scene: ^Scene, root: ^Node) -> (buckets: [RenderLayer][dynamic]^Node) {
	collect: Render_Collect
	for &l in collect.items do l = make([dynamic]Render_Item, context.temp_allocator)
	if scene != nil && scene.manager != nil && root != nil {
		for child in GetChildrenView(scene.manager, root) do render_walk(&collect, scene.manager, child, 0, 0)
	}
	return render_buckets(&collect)
}

// Scene_RenderLayers draws buckets' layers (those in `layers`) with the
// current camera and view (a viewport's pass).
Scene_RenderLayers :: proc(scene: ^Scene, buckets: [RenderLayer][dynamic]^Node, gameContext: ^GameContext, layers: bit_set[RenderLayer]) {
	for layer in RenderLayer do if layer in layers && len(buckets[layer]) > 0 do render_bucket(scene, buckets[layer][:], gameContext, 0)
}

@(private = "file")
render_buckets :: proc(collect: ^Render_Collect) -> (buckets: [RenderLayer][dynamic]^Node) {
	for &l, layer in collect.items {
		if collect.anyZ {
			for it in l do if it.z != 0 {
				Sort_Stable(l[:], proc(a, b: Render_Item) -> bool {return a.z < b.z})
				break
			}
		}
		buckets[layer] = make([dynamic]^Node, len(l), context.temp_allocator)
		for it, i in l do buckets[layer][i] = it.node
	}
	return
}

// Render_Item: a node to draw with its sort keys.
Render_Item :: struct {
	node: ^Node,
	z:    i32, // global zIndex
	y:    f32, // Y-sort key of the subtree it belongs to
}

@(private = "file")
Render_Collect :: struct {
	items:  [RenderLayer][dynamic]Render_Item,
	anyZ:   bool,
	screen: ^Render_Collect, // where Screen Layers' subtrees go (nil: with the rest)
}

@(private = "file")
node_as_tilemap :: #force_inline proc(n: ^Node) -> (^TileMapNode, bool) {
	if n.typeId != TileMapNode do return nil, false
	return cast(^TileMapNode)n, true
}

// render_walk appends a subtree's drawables; z = the parent's global
// zIndex, key = the Y-sort key the subtree's items carry.
@(private = "file")
render_walk :: proc(c: ^Render_Collect, m: ^NodeManager, node: ^Node, z: i32, key: f32) {
	if node == nil || !node.enabled do return
	if Render_HideEditorHidden && node.editorHidden do return
	if node.typeId == ViewportNode && (cast(^ViewportNode)node).mode == .Children {
		// Its children draw into its texture only (viewport_node.odin).
		if node.renderable do append(&c.items[node.layer], Render_Item{node, z + node.zIndex, key})
		if node.zIndex != 0 do c.anyZ = true
		return
	}
	if node.typeId == ScreenLayerNode && c.screen != nil {
		render_walk(c.screen, m, node, 0, 0) // (its own order: screen space)
		return
	}
	z := z + node.zIndex
	if z != 0 do c.anyZ = true
	if node.renderable && (node.render != nil || node.drawBounds != nil || Script_HasDraw(node, nil)) {
		if tm, isMap := node_as_tilemap(node); isMap {
			// A Y-sorted map: a draw per band, each keyed by its feet line
			// (sorts with the sprites of a Y-sorted parent).
			tm.bandMode = tm.ySort
			tm.bandNext = 0
			if tm.ySort {
				tm.bandLo, tm.bandHi = TileMapNode_Bands(tm)
				for b in tm.bandLo ..< tm.bandHi do append(&c.items[node.layer], Render_Item{node, z, TileMapNode_BandSortY(tm, b)})
			} else {
				append(&c.items[node.layer], Render_Item{node, z, key})
			}
		} else {
			append(&c.items[node.layer], Render_Item{node, z, key})
		}
	}
	if !node.ySort {
		for child in GetChildrenView(m, node) do render_walk(c, m, child, z, key)
		return
	}
	// Y-sort: each child's subtree keyed by the child's Y, then sorted per
	// layer (stable: a subtree keeps its order), then given back the
	// enclosing key (so an outer Y-sort moves it as one).
	start: [RenderLayer]int
	for l, layer in c.items do start[layer] = len(l)
	for child in GetChildrenView(m, node) do render_walk(c, m, child, z, child.globalPosition.y + child.ySortOffset)
	for &l, layer in c.items {
		seg := l[start[layer]:]
		if len(seg) > 1 do Sort_Stable(seg, proc(a, b: Render_Item) -> bool {return a.y < b.y})
		for &it in seg do it.y = key
	}
}
