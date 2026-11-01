package engine

import "core:strings"
import "core:testing"
import lua "lua54"
import rl "vendor:raylib"

// #252: Lua API bugs found while documenting the bindings - type names,
// set_scale with a vector, animation_reset, calls taking two points as
// vectors, create_node adding bodies once, simulated key presses,
// set_binding refusing bad / full slots, bus names in any case, a black
// ambient, raycasts filtered by layers, camera conversions in the game's
// frame, sm_start with an unknown state, Locale.set, nav blocks kept when a
// region changes size.
@(test)
test_lua_api_252 :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("lua252", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	ctx := &game.gameContext
	L := game.scriptManager.L
	run :: proc(t: ^testing.T, L: ^lua.State, code: cstring, loc := #caller_location) {
		if lua.L_dostring(L, code) != 0 {
			testing.fail_now(t, strings.clone(string(lua.tostring(L, -1)), context.temp_allocator), loc)
		}
	}
	gs :: proc(L: ^lua.State, n: cstring) -> string {
		lua.getglobal(L, n)
		defer lua.pop(L, 1)
		return strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
	}

	// get_type / get_base_type: every built-in type by its own name.
	atlas := Node_CreateByTypeName(scene, "AtlasSpriteNode")
	atlas.name = strings.clone("Atlas", atlas.allocator)
	label := Node_CreateByTypeName(scene, "UILabelNode")
	label.name = strings.clone("Label", label.allocator)
	ProcessNodeQueues(scene.manager, ctx)
	run(t, L, `a = Scene.find_node("Atlas"):get_type(); b = Scene.find_node("Label"):get_base_type()
		c = tostring(Scene.find_node("Label"):is("UILabelNode"))`)
	testing.expect_value(t, gs(L, "a"), "AtlasSpriteNode")
	testing.expect_value(t, gs(L, "b"), "UILabelNode")
	testing.expect_value(t, gs(L, "c"), "true")

	// set_scale: a vector keeps both axes; one number is uniform.
	run(t, L, `Scene.find_node("Atlas"):set_scale(Vec2(2, 3))`)
	testing.expect_value(t, atlas.scale, [2]f32{2, 3})
	run(t, L, `Scene.find_node("Atlas"):set_scale(4)`)
	testing.expect_value(t, atlas.scale, [2]f32{4, 4})
	run(t, L, `Scene.find_node("Atlas"):set_scale(5, 6)`)
	testing.expect_value(t, atlas.scale, [2]f32{5, 6})

	// animation_reset: back to the first frame.
	apn := cast(^AnimationPlayerNode)Node_CreateByTypeName(scene, "AnimationPlayerNode")
	apn.name = strings.clone("Anim", apn.allocator)
	apn.gameContext = ctx
	apn.fps = 10
	walk := AnimationPlayerNode_AddFrameAnimation(apn, nil, "walk", nil)
	walk.startFrame, walk.endFrame, walk.loop = 2, 9, true
	ProcessNodeQueues(scene.manager, ctx)
	AnimationPlayerNode_Play(apn, "walk")
	AnimationPlayerNode_Update(apn, ctx, 0.35)
	testing.expect(t, apn.currentFrame > 2, "walking")
	run(t, L, `Scene.find_node("Anim"):animation_reset()`)
	testing.expect_value(t, apn.currentFrame, 2)
	testing.expect_value(t, apn.time, 0)

	// Camera limits from two vectors (and from four numbers).
	cam := CameraNode_Create(scene, "Cam")
	cam.gameContext = ctx
	ProcessNodeQueues(scene.manager, ctx)
	scene.camera = cam
	run(t, L, `Camera.set_limits(Vec2(-10, 500), Vec2(-20, 400))`)
	testing.expect(t, cam.hasLimits && cam.leftLimit == -10 && cam.rightLimit == 500 && cam.topLimit == -20 && cam.bottomLimit == 400, "global limits from vectors")
	run(t, L, `Scene.find_node("Cam"):camera_set_limits(Vec2(1, 2), Vec2(3, 4))`)
	testing.expect(t, cam.leftLimit == 1 && cam.rightLimit == 2 && cam.topLimit == 3 && cam.bottomLimit == 4, "node limits from vectors")
	run(t, L, `Scene.find_node("Cam"):camera_set_limits(5, 6, 7, 8)`)
	testing.expect(t, cam.leftLimit == 5 && cam.rightLimit == 6 && cam.topLimit == 7 && cam.bottomLimit == 8, "node limits from numbers")

	// Camera conversions use the game's frame: its centre is the camera.
	CameraNode_ClearLimits(cam)
	game.virtualSize = {640, 360}
	cam.position, cam.currentPosition = {1000, 1000}, {1000, 1000}
	run(t, L, `wx, wy = Camera.screen_to_world(320, 180); bx, by, bw, bh = Camera.get_visible_world_bounds()`)
	testing.expect_value(t, gs(L, "wx"), "1000.0")
	testing.expect_value(t, gs(L, "wy"), "1000.0")
	testing.expect_value(t, gs(L, "bw"), "640.0")
	game.virtualSize = {1280, 720}

	// create_node: a body is in the tree once.
	run(t, L, `body = Scene.create_node("DynamicBodyNode", "Crate")`)
	ProcessNodeQueues(scene.manager, ctx)
	crates := 0
	for n in scene.manager.nodes do if n != nil && n.name == "Crate" do crates += 1
	testing.expect_value(t, crates, 1)
	kids := 0
	for c in GetChildrenView(scene.manager, scene.rootNode) do if c.name == "Crate" do kids += 1
	testing.expect_value(t, kids, 1)

	// Simulated keys: pressed on the update they go down, released on the one they go up.
	Input_SetSimulatedKey(&game.input, .SPACE, true)
	InputSystem_Update(&game.input, 1.0 / 60)
	run(t, L, `p1 = tostring(Input.is_key_pressed("SPACE")); d1 = tostring(Input.is_key_down("SPACE"))`)
	InputSystem_Update(&game.input, 1.0 / 60)
	run(t, L, `p2 = tostring(Input.is_key_pressed("SPACE"))`)
	Input_SetSimulatedKey(&game.input, .SPACE, false)
	InputSystem_Update(&game.input, 1.0 / 60)
	run(t, L, `r3 = tostring(Input.is_key_released("SPACE"))`)
	testing.expect(t, gs(L, "p1") == "true" && gs(L, "d1") == "true", "pressed and down")
	testing.expect_value(t, gs(L, "p2"), "false")
	testing.expect_value(t, gs(L, "r3"), "true")
	Input_ClearSimulatedInputs(&game.input)
	game.input.useSimulatedInput = false

	// set_binding: a bad spec or a full action changes nothing and says so.
	game.input.rebind.autoSave = false
	jump := Input_MappingOf(&game.input, "jump")
	testing.expect(t, jump != nil && jump.bindingCount > 0, "jump has bindings")
	before := jump^
	run(t, L, `bad = tostring(Input.set_binding("jump", 1, {key = "NOT_A_KEY"}))`)
	testing.expect_value(t, gs(L, "bad"), "false")
	testing.expect(t, jump.bindingCount == before.bindingCount && jump.bindings[0] == before.bindings[0], "slot 1 kept")
	fkeys := [?]rl.KeyboardKey{.F1, .F2, .F3, .F4, .F5, .F6, .F7, .F8}
	for i in 0 ..< MAX_BINDINGS_PER_ACTION do jump.bindings[i] = {deviceType = .KeyboardKey, key = fkeys[i]}
	jump.bindingCount = MAX_BINDINGS_PER_ACTION
	testing.expect_value(t, jump.bindingCount, MAX_BINDINGS_PER_ACTION)
	run(t, L, `full = tostring(Input.set_binding("jump", 0, {button = "RIGHT_FACE_DOWN"}))`)
	testing.expect_value(t, gs(L, "full"), "false")
	run(t, L, `removed = tostring(Input.set_binding("jump", 1, nil))`)
	testing.expect(t, gs(L, "removed") == "true" && jump.bindingCount == MAX_BINDINGS_PER_ACTION - 1, "nil removes the slot")

	// Bus names in any case go to the project's volumes, clamped.
	run(t, L, `Audio.set_bus_volume("Music", 3); Audio.set_bus_volume("SFX", 0.25)`)
	testing.expect_value(t, game.musicVolume, 1)
	testing.expect_value(t, game.sfxVolume, 0.25)

	// A black, transparent ambient reads back black.
	run(t, L, `Scene.set_ambient(0, 0, 0, 0); ar, ag, ab = Scene.get_ambient()`)
	testing.expect(t, gs(L, "ar") == "0.0" && gs(L, "ag") == "0.0" && gs(L, "ab") == "0.0", "black")
	testing.expect(t, Scene_HasLighting(scene), "a dark scene is lit")

	// Raycasts: two vectors, and only the layers asked for.
	wall := StaticBodyNode_Create(scene, "Wall")
	wall.position = {300, 0}
	wall.gameContext = ctx
	StaticBodyNode_AddShape(wall, MakeBoxPhysicsShape(20, 200), ctx)
	ProcessNodeQueues(scene.manager, ctx)
	game->run(1.0 / 60)
	run(t, L, `
local h = Physics.raycast(Vec2(0, 0), Vec2(600, 0)); hit_vec = h and h.node:get_name() or "none"
local n = Physics.raycast(0, 0, 600, 0); hit_num = n and string.format("%.0f", n.point_x) or "none"
hit_l1 = Physics.raycast(Vec2(0, 0), Vec2(600, 0), 1) and "hit" or "none"
hit_l2 = Physics.raycast(Vec2(0, 0), Vec2(600, 0), 2) and "hit" or "none"
hit_l2n = Physics.raycast(0, 0, 600, 0, {2, 3}) and "hit" or "none"`)
	testing.expect_value(t, gs(L, "hit_vec"), "Wall")
	testing.expect_value(t, gs(L, "hit_num"), "290")
	testing.expect_value(t, gs(L, "hit_l1"), "hit")
	testing.expect_value(t, gs(L, "hit_l2"), "none")
	testing.expect_value(t, gs(L, "hit_l2n"), "none")

	// sm_start with an unknown state: false, nothing started (#252: fail + warn); none: the initial one.
	sm := cast(^StateMachineNode)Node_CreateByTypeName(scene, "StateMachineNode")
	sm.name = strings.clone("SM", sm.allocator)
	sm.gameContext = ctx
	StateMachine_AddState(sm, "idle")
	StateMachine_AddState(sm, "run")
	sm.initial = strings.clone("run", sm.allocator)
	ProcessNodeQueues(scene.manager, ctx)
	run(t, L, `local m = Scene.find_node("SM"); ok = tostring(m:sm_start("nope"))
		ok2 = tostring(m:sm_start()); st2 = m:sm_state()`)
	testing.expect_value(t, gs(L, "ok"), "false")
	testing.expect_value(t, gs(L, "ok2"), "true") // (after the unknown one: nothing had started)
	testing.expect_value(t, gs(L, "st2"), "run")

	// Nav: a script block stays where it was when the region grows.
	region := NavigationRegionNode_Create(scene, "Nav")
	region.size, region.cellSize = {160, 160}, 16
	region.usePhysics, region.useTileMaps, region.useLdtk = false, false, false
	region.gameContext = ctx
	ProcessNodeQueues(scene.manager, ctx)
	NavRegion_SetBlocked(region, {32, 32}, {48, 48}, true)
	testing.expect_value(t, region.blocked[2 * region.cells.x + 2], 2)
	region.size = {320, 320}
	NavRegion_Bake(region, ctx)
	testing.expect_value(t, region.cells, [2]int{20, 20})
	testing.expect_value(t, region.blocked[2 * region.cells.x + 2], 2)
	region.cellSize = 8
	NavRegion_Bake(region, ctx)
	blocked := 0
	for v in region.blocked do if v == 2 do blocked += 1
	testing.expect_value(t, blocked, 4) // (one 16 px cell = four 8 px ones)
	testing.expect_value(t, region.blocked[4 * region.cells.x + 4], 2)

	free_all(context.temp_allocator)
}
