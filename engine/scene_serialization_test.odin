package engine

import "core:fmt"
import os "osx"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import lua "lua54"
import rl "vendor:raylib"
import b2 "vendor:box2d"

// ============================================================================
// Scene save/load round trips, node factory, scene registry
// ============================================================================

@(private = "file")
reload_scene :: proc(game: ^Game, json_text: string, name: string) -> ^Scene {
	s := game->createScene(name, false)
	Scene_InstantiateFromJSON(s, transmute([]u8)json_text, &game.gameContext)
	ProcessNodeQueues(s.manager, &game.gameContext)
	return s
}

@(private = "file")
count_type :: proc(scene: ^Scene, t: typeid) -> int {
	n := 0
	for node in scene.manager.nodes {
		if node != nil && node.typeId == t do n += 1
	}
	return n
}

@(test)
test_node_factory_creates_every_registered_type :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("factory", true)
	for info in NODE_TYPES {
		n := Node_CreateByTypeName(scene, info.name)
		testing.expectf(t, n != nil, "%s created", info.name)
		if n == nil do continue
		testing.expectf(t, n.typeId == info.type, "%s has typeid %v (got %v)", info.name, info.type, n.typeId)
		testing.expectf(t, Node_TypeName(n) == info.name, "%s round-trips its type name", info.name)
		testing.expectf(t, GetParent(scene.manager, n) == scene.rootNode, "%s is a child of the root", info.name)
	}
	ProcessNodeQueues(scene.manager, &game.gameContext)
	// Under an explicit parent, exactly one parent relationship.
	parent := Node_CreateByTypeName(scene, "Node")
	child := Node_CreateByTypeName(scene, "TimerNode", parent) // TimerNode_Create adds to the root itself
	testing.expect(t, GetParent(scene.manager, child) == parent, "re-parented under the requested parent")
	rels := 0
	for list in ([][dynamic]^Node{scene.manager.nodes, scene.manager.addition}) {
		for n in list do if n != nil do for c in GetChildrenView(scene.manager, n) do if c == child do rels += 1
	}
	testing.expect_value(t, rels, 1)
	_, aliasOk := Node_TypeInfoByName("dynamic_body")
	testing.expect(t, aliasOk, "legacy alias resolves")
}

@(test)
test_every_node_type_round_trips :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("rt_src", true)

	// One node of each type with non-default values.
	for info in NODE_TYPES {
		n := Node_CreateByTypeName(scene, info.name)
		if n != nil do n.pixelFilter, n.pixelSnap, n.pixelText = .Smooth, .Off, .Native // (#409's overrides round-trip too)
		n.name = strings.clone(fmt.tprintf("My %s \"quoted\"", info.name), n.allocator)
		n.position = {12.5, -40.25}
		n.scale = {0.455, 2}
		n.rotation = 33.3
		n.layer = .Layer3
		for p in Node_CollectProperties(n) {
			if p.runtime do continue
			#partial switch p.kind {
			case .Float: Property_SetFloat(p, 0.75)
			case .Bool: (^bool)(p.ptr)^ = true
			case .Vec2: (^[2]f32)(p.ptr)^ = {3, 4}
			case .Color: (^rl.Color)(p.ptr)^ = {10, 20, 30, 40}
			case .String: Property_SetString(n, p, "hello \"world\"\n")
			}
		}
	}
	tm := cast(^TimerNode)Scene_FindNodeByType(scene, TimerNode)
	tm->setDuration(2.5)
	tm.loop = true
	db := cast(^DynamicBodyNode)Scene_FindNodeByType(scene, DynamicBodyNode)
	shape: PhysicsShape
	PhysicsShape_InitDefault(&shape, .Circle)
	shape.radius = 21
	shape.friction = 0.6
	append(&db.shapes, shape)
	ProcessNodeQueues(scene.manager, &game.gameContext)

	first := Scene_SerializeToJSON(scene, context.temp_allocator)
	copy1 := reload_scene(game, first, "rt_copy1")
	second := Scene_SerializeToJSON(copy1, context.temp_allocator)
	// The copy is saved under its own scene name; compare everything else.
	second, _ = strings.replace(second, "\"rt_copy1\"", "\"rt_src\"", 1, context.temp_allocator)
	testing.expect(t, first == second, "load -> save reproduces the file exactly")
	if first != second {
		_ = os.write_entire_file("rt_first.json", transmute([]u8)first)
		_ = os.write_entire_file("rt_second.json", transmute([]u8)second)
	}

	for info in NODE_TYPES {
		if info.type == Node do continue
		testing.expectf(t, count_type(copy1, info.type) >= 1, "%s survives the round trip", info.name)
	}
	tm2 := cast(^TimerNode)Scene_FindNodeByType(copy1, TimerNode)
	testing.expect(t, tm2 != nil && tm2.loop && abs(f32(tm2.duration) / 1e9 - 2.5) < 0.001, "timer duration/loop kept")
	db2 := cast(^DynamicBodyNode)Scene_FindNodeByType(copy1, DynamicBodyNode)
	testing.expect(t, db2 != nil && len(db2.shapes) == 1 && db2.shapes[0].type == .Circle && db2.shapes[0].radius == 21, "physics shape kept")
	testing.expect(t, db2 != nil && db2.gravityScale == 0.75, "reflected property kept")
	lbl := cast(^UILabelNode)Scene_FindNodeByType(copy1, UILabelNode)
	testing.expect(t, lbl != nil && lbl.text == "hello \"world\"\n", "string property with quotes/newline kept")
	testing.expect_value(t, count_type(copy1, CameraNode), 1)
}

@(test)
test_script_property_values_are_saved :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("script_rt", true)
	n := Node_CreateByTypeName(scene, "Node")
	n.gameContext = &game.gameContext
	overrides := make(map[string]ScriptValue, context.temp_allocator)
	overrides["orbit_radius"] = ScriptValue{type = .Float, valFloat = 321}
	inst := Script_AttachToNode(n, "assets/scripts/orbiting_drone.lua", overrides, &game.scriptManager)
	testing.expect(t, inst != nil, "script attached")
	if inst == nil do return
	// Edit a property the way the inspector does.
	v := inst.properties["rotation_speed"]
	v.valFloat = 9.5
	ScriptInstance_SetProperty(inst, "rotation_speed", v, &game.scriptManager)
	ProcessNodeQueues(scene.manager, &game.gameContext)

	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, "\"orbit_radius\": 321"), "override saved")
	testing.expect(t, strings.contains(text, "\"rotation_speed\": 9.5"), "inspector edit saved")

	copy1 := reload_scene(game, text, "script_rt_copy")
	found: ^Node
	for node in copy1.manager.nodes {
		if node != nil && node.scriptInstance != nil do found = node
	}
	testing.expect(t, found != nil, "scripted node reloaded")
	if found != nil {
		ci := cast(^ScriptInstance)found.scriptInstance
		testing.expect_value(t, ci.properties["rotation_speed"].valFloat, f32(9.5))
		testing.expect_value(t, ci.properties["orbit_radius"].valFloat, f32(321))
	}
}

@(private = "file")
write_project :: proc(dir: string, scenes: []string, initial: string) {
	_ = os.make_directory_all(filepath.join({dir, "scenes"}, context.temp_allocator) or_else "")
	sb := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&sb, `{{"name": "t", "initial_scene": "%s", "physics": {{"gravity": [0, 0]}}, "scenes": [`, initial)
	for s, i in scenes {
		if i > 0 do strings.write_string(&sb, ", ")
		fmt.sbprintf(&sb, `"%s"`, s)
	}
	strings.write_string(&sb, "]}")
	_ = os.write_entire_file(filepath.join({dir, "project.json"}, context.temp_allocator) or_else "", transmute([]u8)strings.to_string(sb))
}

@(private = "file")
write_scene :: proc(dir, rel, name, nodeName: string) {
	text := fmt.tprintf(`{{"name": "%s", "root": {{"type": "Node", "name": "root", "children": [{{"type": "Node", "name": "%s", "position": [1, 2]}}]}}}}`, name, nodeName)
	_ = os.write_entire_file(filepath.join({dir, rel}, context.temp_allocator) or_else "", transmute([]u8)text)
}

@(test)
test_duplicate_scene_names_do_not_shadow_the_initial_scene :: proc(t: ^testing.T) {
	dir := "test_dup_scene_project"
	defer os.remove_all(dir)
	write_project(dir, {"scenes/main.scene.json", "scenes/arena.scene.json"}, "scenes/main.scene.json")
	// Both files claim the same scene name (the bug that made Play run the
	// wrong scene).
	write_scene(dir, "scenes/main.scene.json", "battle_arena", "EditedInMain")
	write_scene(dir, "scenes/arena.scene.json", "battle_arena", "ArenaNode")

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	testing.expect(t, game->loadProject(dir), "project loads")
	cur := game.sceneManager.currentScene
	testing.expect(t, cur != nil && cur.filePath == "scenes/main.scene.json", "the initial scene is the main file")
	testing.expect(t, cur != nil && Scene_FindNodeByName(cur, "EditedInMain") != nil, "with the main file's content")
	testing.expect_value(t, len(game.sceneManager.scenes), 2)
	testing.expect(t, Game_FindSceneByFile(game, "scenes/arena.scene.json") != nil, "the other file is registered too")
}

@(test)
test_json_scene_is_rebuilt_when_re_entered :: proc(t: ^testing.T) {
	dir := "test_reenter_project"
	defer os.remove_all(dir)
	write_project(dir, {"scenes/a.scene.json", "scenes/b.scene.json"}, "scenes/a.scene.json")
	write_scene(dir, "scenes/a.scene.json", "a", "NodeA")
	write_scene(dir, "scenes/b.scene.json", "b", "NodeB")

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	testing.expect(t, game->loadProject(dir), "project loads")
	testing.expect(t, Scene_FindNodeByName(game.sceneManager.currentScene, "NodeA") != nil, "A built on start")
	ChangeScene_ByName(&game.sceneManager, "b")
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	testing.expect(t, Scene_FindNodeByName(game.sceneManager.currentScene, "NodeB") != nil, "B built on entry")
	ChangeScene_ByName(&game.sceneManager, "a")
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	testing.expect(t, Scene_FindNodeByName(game.sceneManager.currentScene, "NodeA") != nil, "A rebuilt on re-entry (was empty before)")
}

@(test)
test_legacy_scene_file_loads_without_duplicate_cameras :: proc(t: ^testing.T) {
	legacy := `{
  "name": "legacy",
  "camera": {"target_position": [100, 50], "zoom": 1.5},
  "root": {"type": "Node", "name": "root", "children": [
    {"type": "CameraNode", "name": "MainCamera"},
    {"type": "DynamicBodyNode", "name": "Crate", "physics": {"gravity_scale": 0.25, "shape": {"type": "box", "size": [64, 32], "friction": 0.4}}},
    {"type": "ParticleEmitterNode", "name": "Fx", "particles": {"amount": 42, "lifetime": 3.5}},
    {"type": "TimerNode", "name": "T", "timer": {"duration": 4, "loop": true}}
  ]}
}`
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	s := reload_scene(game, legacy, "legacy")
	testing.expect_value(t, count_type(s, CameraNode), 1)
	crate := cast(^DynamicBodyNode)Scene_FindNodeByName(s, "Crate")
	testing.expect(t, crate != nil && crate.gravityScale == 0.25 && len(crate.shapes) == 1 && crate.shapes[0].size == {64, 32}, "legacy physics block")
	fx := cast(^ParticleEmitterNode)Scene_FindNodeByName(s, "Fx")
	testing.expect(t, fx != nil && fx.emitter.amount == 42, "legacy particles block")
	// Saving and loading again keeps exactly one camera.
	again := reload_scene(game, Scene_SerializeToJSON(s, context.temp_allocator), "legacy2")
	testing.expect_value(t, count_type(again, CameraNode), 1)
	fx2 := cast(^ParticleEmitterNode)Scene_FindNodeByName(again, "Fx")
	testing.expect(t, fx2 != nil && fx2.emitter.amount == 42 && fx2.emitter.lifetime == 3.5, "particle settings survive a save")
}

@(test)
test_demo_scenes_reach_a_fixed_point :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, "assets/demo_project")
	for rel in ([]string{"scenes/main.scene.json", "scenes/battle_arena.scene.json"}) {
		path := filepath.join({"assets/demo_project", rel}, context.temp_allocator) or_else ""
		data, err := os.read_entire_file(path, context.temp_allocator)
		if err != nil do continue
		a := reload_scene(game, string(data), "demo_a")
		first := Scene_SerializeToJSON(a, context.temp_allocator)
		b := reload_scene(game, first, "demo_a")
		second := Scene_SerializeToJSON(b, context.temp_allocator)
		testing.expectf(t, first == second, "%s: save is stable after one load/save", rel)
		testing.expectf(t, count_type(b, CameraNode) <= 1, "%s: at most one camera after a save", rel)
	}
}

@(test)
test_script_set_property_with_map_key_string :: proc(t: ^testing.T) {
	// Regression: passing the map's own key string as `name` (what every
	// inspector does while iterating the properties) used to free the key
	// before re-inserting it, corrupting the property name.
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("setprop", true)
	n := Node_CreateByTypeName(scene, "Node")
	n.gameContext = &game.gameContext
	inst := Script_AttachToNode(n, "assets/scripts/orbiting_drone.lua", nil, &game.scriptManager)
	testing.expect(t, inst != nil, "attached")
	if inst == nil do return
	for name, val in inst.properties {
		if name != "orbit_radius" do continue
		v := val
		v.valFloat = 77
		ScriptInstance_SetProperty(inst, name, v, &game.scriptManager)
		break
	}
	testing.expect_value(t, inst.properties["orbit_radius"].valFloat, f32(77))
	for k in inst.properties {
		testing.expectf(t, len(k) > 0 && k[0] >= 'a' && k[0] <= 'z', "property key intact: %q", k)
	}
}

@(test)
test_children_inherit_parent_rotation_and_scale :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("xf", true)
	ship := Node_CreateByTypeName(scene, "Node")
	ship.position = {100, 100}
	thruster := Node_CreateByTypeName(scene, "Node", ship)
	thruster.position = {0, 20} // 20 px "behind" the ship
	ProcessNodeQueues(scene.manager, &game.gameContext)

	ship.rotation = 90
	ship.scale = {2, 2}
	Node_SetGlobalPositions(scene.manager, scene.rootNode)
	g := thruster.globalPosition
	testing.expectf(t, abs(g.x - 60) < 0.01 && abs(g.y - 100) < 0.01, "child orbits and scales with parent, got %v", g)
	testing.expect_value(t, thruster.globalRotation, f32(90))
	testing.expect_value(t, thruster.globalScale, [2]f32{2, 2})
	// Round trip world <-> parent space.
	back := Node_WorldToParent(scene.manager, thruster, g)
	testing.expectf(t, abs(back.x) < 0.01 && abs(back.y - 20) < 0.01, "world->local inverts, got %v", back)
}

@(test)
test_physics_bodies_follow_the_hierarchy :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	game.physicsWorld.gravity = {0, 0}
	scene := game->createScene("phys_tree", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	platform := Node_CreateByTypeName(scene, "Node")
	platform.position = {500, 300}
	wall := cast(^StaticBodyNode)Node_CreateByTypeName(scene, "StaticBodyNode", platform)
	wall.position = {20, 0}
	shape: PhysicsShape
	PhysicsShape_InitDefault(&shape, .Box)
	shape.size = {10, 10}
	append(&wall.shapes, shape)
	crate := cast(^DynamicBodyNode)Node_CreateByTypeName(scene, "DynamicBodyNode", platform)
	crate.position = {-50, 0}
	append(&crate.shapes, shape)
	game->run(1.0 / 60)

	testing.expectf(t, b2_pos(wall.bodyId) == [2]f32{520, 300}, "static body at its world position, got %v", b2_pos(wall.bodyId))
	// The crate stays put in local space (no gravity) and its body is in world space.
	testing.expectf(t, abs(crate.position.x + 50) < 0.5, "dynamic body local position kept, got %v", crate.position)
	testing.expectf(t, abs(b2_pos(crate.bodyId).x - 450) < 0.5, "dynamic body world position, got %v", b2_pos(crate.bodyId))
	// Moving the parent moves the static body.
	platform.position = {600, 300}
	game->run(1.0 / 60)
	testing.expectf(t, abs(b2_pos(wall.bodyId).x - 620) < 0.01, "static body follows its parent, got %v", b2_pos(wall.bodyId))
}

@(private = "file")
b2_pos :: proc(id: b2.BodyId) -> [2]f32 {
	return b2.Body_GetPosition(id)
}

@(test)
test_resources_are_released_with_their_nodes :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("res", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	rm := &game.resourceManager
	path := "assets/demo_project/textures/Asteroid_1.png"

	a := cast(^TextureNode)Node_CreateByTypeName(scene, "TextureNode")
	b := cast(^TextureNode)Node_CreateByTypeName(scene, "TextureNode")
	a.gameContext, b.gameContext = &game.gameContext, &game.gameContext
	ta, _ := rm.loadTexture(rm, path)
	tb, _ := rm.loadTexture(rm, path)
	TextureNode_SetTexture(a, ta)
	TextureNode_SetTexture(b, tb)
	testing.expect(t, ta == tb && ta.refCount == 2, "shared texture, two references")
	ProcessNodeQueues(scene.manager, &game.gameContext)

	RemoveNode(scene.manager, a)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect_value(t, len(rm.textures), 1)
	RemoveNode(scene.manager, b)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect_value(t, len(rm.textures), 0)

	// Sound slots are reused after release.
	s1, ok1 := rm.loadAudioSound(rm, "assets/demo_project/audio/cannon-gunshot-1.wav")
	testing.expect(t, ok1, "sound loaded")
	ResourceManager_ReleaseSound(rm, s1)
	testing.expect_value(t, s1.filePath, "")
	s2, _ := rm.loadAudioSound(rm, "assets/demo_project/audio/cannon-gunshot-1.wav")
	testing.expect(t, s1 == s2 && rm.audioCount == 1, "released slot reused")
}

@(test)
test_animation_player_round_trips :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("anim", true)
	apn := cast(^AnimationPlayerNode)Node_CreateByTypeName(scene, "AnimationPlayerNode")
	apn.gameContext = &game.gameContext
	rm := &game.resourceManager
	AnimationPlayerNode_AddFrameAnimation(apn, rm, "thrust", {"assets/demo_project/textures/exhaust/Exhaust_1_1_005.png", "assets/demo_project/textures/exhaust/Exhaust_1_1_006.png"}, true)
	AnimationPlayerNode_AddSheetAnimation(apn, rm, "explode", "assets/demo_project/textures/Asteroid_1.png", {4, 2}, 0, 7, false)
	AnimationPlayerNode_SetAnimationByName(apn, "explode")
	AnimationPlayerNode_SetFPS(apn, 24)
	apn.autoplay = true
	ProcessNodeQueues(scene.manager, &game.gameContext)

	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"name": "thrust"`) && strings.contains(text, `"grid": [4, 2]`), "animations saved")
	copy1 := reload_scene(game, text, "anim_copy")
	apn2 := cast(^AnimationPlayerNode)Scene_FindNodeByType(copy1, AnimationPlayerNode)
	testing.expect(t, apn2 != nil && len(apn2.animations) == 2, "two animations reloaded")
	if apn2 == nil do return
	testing.expect_value(t, AnimationPlayerNode_GetAnimationName(apn2), "explode")
	testing.expect_value(t, apn2.ticker.framesPerSecond, f32(24))
	testing.expect(t, apn2.autoplay, "autoplay kept")
	fa := cast(^FrameAnimation)apn2.animations[0]
	testing.expect_value(t, len(fa.frames), 2)
	second := Scene_SerializeToJSON(copy1, context.temp_allocator)
	second, _ = strings.replace(second, "\"anim_copy\"", "\"anim\"", 1, context.temp_allocator)
	testing.expect(t, text == second, "animation player round trip is exact")

	// Non-looping animations raise animation_finished once.
	finished := 0
	apn2.onFinished->subscribe(proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {(^int)(ud)^ += 1}, &finished)
	AnimationPlayerNode_Start(apn2)
	for _ in 0 ..< 20 do AnimationPlayerNode_AdvanceFrame(apn2)
	testing.expect_value(t, finished, 1)
}

@(test)
test_component_instances_are_links :: proc(t: ^testing.T) {
	dir :: "test_component_project"
	defer os.remove_all(dir)
	_ = os.make_directory_all(dir + "/components")
	write :: proc(dir: string, body: string) {
		_ = os.write_entire_file(test_component_file, transmute([]u8)body)
	}
	write(dir, `{"type": "Node", "name": "Turret", "children": [{"type": "TimerNode", "name": "Reload", "timer": {"duration": 2}}]}`)

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, dir)
	scene := game->createScene("prefabs", true)
	a := Scene_InstantiateComponent(scene, "components/turret.component.json", nil, &game.gameContext)
	testing.expect(t, a != nil && a.componentPath == "components/turret.component.json", "linked instance")
	if a == nil do return
	a.position = {100, 50}
	a.name = strings.clone("TurretA", a.allocator)
	ProcessNodeQueues(scene.manager, &game.gameContext)

	// Saved as a link (no children in the scene file).
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"component": "components/turret.component.json"`), "link saved")
	testing.expect(t, !strings.contains(text, "Reload"), "instance subtree not copied into the scene")

	// Reload builds the subtree from the component file.
	copy1 := reload_scene(game, text, "prefabs2")
	ta := Scene_FindNodeByName(copy1, "TurretA")
	testing.expect(t, ta != nil && ta.position == {100, 50}, "instance transform kept")
	testing.expect(t, Scene_FindNodeByName(copy1, "Reload") != nil, "subtree from the component")

	// Edit the component file: refreshing updates the instance.
	write(dir, `{"type": "Node", "name": "Turret", "children": [{"type": "TimerNode", "name": "Reload"}, {"type": "Node", "name": "Barrel"}]}`)
	n := Scene_RefreshComponentInstances(copy1, "components/turret.component.json", &game.gameContext)
	testing.expect_value(t, n, 1)
	ta = Scene_FindNodeByName(copy1, "TurretA")
	testing.expect(t, ta != nil && ta.position == {100, 50}, "transform survives refresh")
	testing.expect(t, Scene_FindNodeByName(copy1, "Barrel") != nil, "new component content appears")

	// Unlink: becomes ordinary nodes, saved in full.
	Node_UnlinkComponent(ta)
	text2 := Scene_SerializeToJSON(copy1, context.temp_allocator)
	testing.expect(t, strings.contains(text2, "Barrel") && !strings.contains(text2, `"component"`), "unlinked instance saved in full")
}

@(private = "file")
test_component_file :: "test_component_project/components/turret.component.json"

@(test)
test_component_child_overrides :: proc(t: ^testing.T) {
	dir :: "test_component_overrides"
	file :: dir + "/components/ship.component.json"
	defer os.remove_all(dir)
	_ = os.make_directory_all(dir + "/components")
	// Hand-written component: few keys (defaults must not become overrides).
	_ = os.write_entire_file(file, transmute([]u8)string(`{"type": "Node", "name": "Ship", "children": [{"type": "Node", "name": "Thruster", "position": [0, 20], "children": [{"type": "TimerNode", "name": "Flame", "timer": {"duration": 1}}]}, {"type": "Node", "name": "Gun"}]}`))

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	defer Component_ClearCaches()
	AssetManager_SetProjectDir(&game.assetManager, dir)
	scene := game->createScene("ov", true)
	a := Scene_InstantiateComponent(scene, "components/ship.component.json", nil, &game.gameContext)
	if a == nil do testing.fail_now(t, "no instance")
	a.name = strings.clone("ShipA", a.allocator)
	ProcessNodeQueues(scene.manager, &game.gameContext)

	// Unchanged instance: no overrides.
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, !strings.contains(text, `"overrides"`), "an unchanged instance has no overrides")

	// Change two children.
	thruster := Scene_FindNodeByName(scene, "Thruster")
	flame := Scene_FindNodeByName(scene, "Flame")
	thruster.position = {5, 40}
	flame.enabled = false
	text = Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"Thruster": {"position": [5, 40]}`), "child override saved")
	testing.expect(t, strings.contains(text, `"Thruster/Flame": {"enabled": false}`), "grandchild override saved")
	testing.expect(t, !strings.contains(text, `"Gun"`), "unchanged children aren't saved")
	over := Node_ComponentOverrides(scene.manager, thruster)
	testing.expect(t, len(over) == 1 && over[0] == "position", "override keys reported")

	// Reload: overrides applied on top of the component.
	copy1 := reload_scene(game, text, "ov2")
	th2 := Scene_FindNodeByName(copy1, "Thruster")
	fl2 := Scene_FindNodeByName(copy1, "Flame")
	testing.expect(t, th2 != nil && th2.position == {5, 40}, "child override restored")
	testing.expect(t, fl2 != nil && !fl2.enabled, "grandchild override restored")

	// The component changes: non-overridden values follow, overrides stay.
	_ = os.write_entire_file(file, transmute([]u8)string(`{"type": "Node", "name": "Ship", "children": [{"type": "Node", "name": "Thruster", "position": [0, 30], "scale": [2, 2], "children": [{"type": "TimerNode", "name": "Flame", "timer": {"duration": 1}}]}, {"type": "Node", "name": "Gun", "position": [9, 9]}]}`))
	Scene_RefreshComponentInstances(copy1, "components/ship.component.json", &game.gameContext)
	th2 = Scene_FindNodeByName(copy1, "Thruster")
	gun := Scene_FindNodeByName(copy1, "Gun")
	testing.expect(t, th2 != nil && th2.position == {5, 40} && th2.scale == {2, 2}, "override kept, new component value applied")
	testing.expect(t, gun != nil && gun.position == {9, 9}, "untouched child follows the component")

	// Revert the child's overrides.
	Scene_RevertComponentOverrides(copy1, th2, &game.gameContext)
	th2 = Scene_FindNodeByName(copy1, "Thruster")
	testing.expect(t, th2 != nil && th2.position == {0, 30}, "reverted to the component value")
	fl2 = Scene_FindNodeByName(copy1, "Flame")
	testing.expect(t, fl2 != nil && !fl2.enabled, "other overrides survive a single revert")
}

@(test)
test_physics_sync_applies_only_changes :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("phys_sync", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	crate := cast(^DynamicBodyNode)Node_CreateByTypeName(scene, "DynamicBodyNode")
	shape: PhysicsShape
	PhysicsShape_InitDefault(&shape, .Box)
	shape.friction = 0.3
	append(&crate.shapes, shape)
	game->run(1.0 / 60)
	s := &crate.shapes[0]
	testing.expect(t, b2.Shape_IsValid(s.shapeId), "shape created")
	h := s.syncedHash
	testing.expect(t, h != 0, "synced hash recorded")
	game->run(1.0 / 60)
	testing.expect_value(t, s.syncedHash, h) // unchanged: not re-applied
	// An edit (inspector / script) reaches Box2D on the next frame.
	s.friction = 0.9
	crate.gravityScale = 0.25
	game->run(1.0 / 60)
	testing.expect(t, abs(b2.Shape_GetFriction(s.shapeId) - 0.9) < 0.001, "friction applied")
	testing.expect(t, abs(b2.Body_GetGravityScale(crate.bodyId) - 0.25) < 0.001, "gravity scale applied")
	testing.expect(t, s.syncedHash != h, "hash updated")
}

@(test)
test_particle_emitter_grows_past_1000 :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("particles", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	pen := cast(^ParticleEmitterNode)Node_CreateByTypeName(scene, "ParticleEmitterNode")
	pen.emitter.amount = 3000
	pen.emitter.burst = 1 // all at once
	pen.emitter.lifetime = 5
	game->run(1.0 / 60)
	alive := 0
	for i in 0 ..< len(pen.emitter.particles) do if pen.emitter.particles[i].alive do alive += 1
	testing.expectf(t, alive == 3000, "3000 particles alive, got %d (capacity %d)", alive, len(pen.emitter.particles))
	// Small emitters stay small.
	small := cast(^ParticleEmitterNode)Node_CreateByTypeName(scene, "ParticleEmitterNode")
	small.emitter.amount = 5
	game->run(1.0 / 60)
	testing.expectf(t, len(small.emitter.particles) <= 16, "a 5-particle emitter keeps a small ring, got %d", len(small.emitter.particles))
}

@(test)
test_animation_property_tracks :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("tracks", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	apn := cast(^AnimationPlayerNode)Node_CreateByTypeName(scene, "AnimationPlayerNode")
	apn.name = "Player"
	apn.gameContext = &game.gameContext
	sprite := Node_CreateByTypeName(scene, "TextureNode", apn)
	sprite.name = "Sprite"
	anim := AnimationPlayerNode_AddFrameAnimation(apn, nil, "spin", nil)
	rot := Animation_AddTrack(apn, anim, ".", "rotation")
	Track_SetKey(rot, 10, {90, 0, 0, 0})
	Track_SetKey(rot, 0, {0, 0, 0, 0})
	pos := Animation_AddTrack(apn, anim, "Sprite", "position")
	Track_SetKey(pos, 0, {0, 0, 0, 0})
	Track_SetKey(pos, 4, {40, -20, 0, 0})
	testing.expect_value(t, len(rot.keys), 2)
	testing.expect_value(t, rot.keys[0].time, 0) // sorted
	testing.expect_value(t, Animation_Length(anim, apn), 121) // (10 s at 12 fps)

	AnimationPlayerNode_ApplyTracks(apn, 5)
	testing.expect(t, abs(apn.rotation - 45) < 0.01, "rotation interpolated")
	testing.expect(t, sprite.position == {40, -20}, "child position clamps after the last key")
	AnimationPlayerNode_ApplyTracks(apn, 2)
	testing.expect(t, sprite.position == {20, -10}, "child position interpolated")

	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(text, `"tracks": [{"target": ".", "property": "rotation", "units": "seconds", "keys": [{"t": 0}, {"t": 10, "v": [90, 0, 0, 0]}]}`), "tracks saved: %s", text)
	copy1 := reload_scene(game, text, "tracks2")
	p2 := cast(^AnimationPlayerNode)Scene_FindNodeByName(copy1, "Player")
	testing.expect(t, p2 != nil, "player reloaded")
	a2 := AnimationPlayerNode_GetAnimation(p2)
	testing.expect(t, a2 != nil && len(a2.tracks) == 2 && len(a2.tracks[0].keys) == 2, "tracks reloaded")
	testing.expect(t, Track_RemoveKey(&a2.tracks[0], 10) && len(a2.tracks[0].keys) == 1, "key removed")
}

@(test)
test_tilemap_paint_fill_save_and_colliders :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("tiles", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	tm := cast(^TileMapNode)Node_CreateByTypeName(scene, "TileMapNode")
	tm.name = "Map"
	tm.mapSize = {6, 4}
	tm.tileSize = {16, 16}
	testing.expect(t, TileMapNode_Set(tm, 1, 1, 3), "paint")
	testing.expect(t, !TileMapNode_Set(tm, 1, 1, 3), "same tile: no change")
	testing.expect_value(t, TileMapNode_Fill(tm, 0, 3, 7), 23) // everything empty around
	testing.expect_value(t, TileMapNode_Get(tm, 1, 1), 3)
	TileMapNode_Set(tm, 5, 0, -1)
	// Resizing keeps the overlapping cells.
	tm.mapSize = {8, 4}
	TileMapNode_Layout(tm)
	testing.expect_value(t, TileMapNode_Get(tm, 1, 1), 3)
	testing.expect_value(t, TileMapNode_Get(tm, 7, 0), -1)
	testing.expect(t, TileMapNode_CellAt(tm, {20, 40}) == [2]int{1, 2}, "cell under a point")

	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"data": [[5, 7], [3, -1], [1, 7], [1, 3], [4, 7]`), "run-length data")
	copy1 := reload_scene(game, text, "tiles2")
	m2 := cast(^TileMapNode)Scene_FindNodeByName(copy1, "Map")
	if m2 != nil do testing.expectf(t, TileMapNode_Get(m2, 1, 1) == 3 && TileMapNode_Get(m2, 6, 0) == -1 && m2.mapSize == {8, 4}, "tiles reloaded: size %v (1,1)=%d (6,0)=%d (0,0)=%d", m2.mapSize, TileMapNode_Get(m2, 1, 1), TileMapNode_Get(m2, 6, 0), TileMapNode_Get(m2, 0, 0))
	else do testing.fail_now(t, "no map")

	// Colliders: one box per horizontal run.
	TileMapNode_BuildColliders(tm, &game.gameContext)
	testing.expect(t, tm.staticBody != nil && tm.staticBody.transient, "transient collider body")
	testing.expect(t, len(tm.staticBody.shapes) >= 4, "merged runs")

	// Shrinking the map keeps its tiles; growing it back shows them again
	// (also one cell at a time, like dragging the field).
	for w := 7; w >= 1; w -= 1 {tm.mapSize = {w, 4}; TileMapNode_Layout(tm)}
	for h := 3; h >= 1; h -= 1 {tm.mapSize = {1, h}; TileMapNode_Layout(tm)}
	testing.expect_value(t, TileMapNode_Get(tm, 1, 1), 3)
	tm.mapSize = {8, 4}
	TileMapNode_Layout(tm)
	testing.expect(t, TileMapNode_Get(tm, 1, 1) == 3 && TileMapNode_Get(tm, 4, 3) == 7, "all back after shrinking and growing")

	// Tiles outside the map: above-left (negative cells) and beyond the right edge.
	testing.expect(t, TileMapNode_Set(tm, -3, -2, 9), "paint above-left of the map")
	testing.expect(t, TileMapNode_Set(tm, 12, 1, 4), "paint right of the map")
	testing.expect(t, TileMapNode_Get(tm, -3, -2) == 9 && TileMapNode_Get(tm, 12, 1) == 4 && TileMapNode_Get(tm, 1, 1) == 3, "kept, with the map's tiles")
	testing.expect(t, !TileMapNode_Set(tm, -40, 0, -1), "erasing empty space outside: nothing to do")
	// A fill inside the map stays inside it.
	TileMapNode_Set(tm, 2, 2, -1)
	testing.expect_value(t, TileMapNode_Fill(tm, 2, 2, 5), 1)
	testing.expect_value(t, TileMapNode_Get(tm, 9, 2), -1)
	// Saved with the data's own area; reloaded in place.
	text = Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"data_origin": [-3, -2]`), "the data area is saved")
	copy2 := reload_scene(game, text, "tiles3")
	m3 := cast(^TileMapNode)Scene_FindNodeByName(copy2, "Map")
	if m3 == nil do testing.fail_now(t, "no map")
	testing.expectf(t, TileMapNode_Get(m3, -3, -2) == 9 && TileMapNode_Get(m3, 12, 1) == 4 && TileMapNode_Get(m3, 1, 1) == 3 && m3.mapSize == {8, 4}, "outside tiles reloaded (%d, %d, %d)", TileMapNode_Get(m3, -3, -2), TileMapNode_Get(m3, 12, 1), TileMapNode_Get(m3, 1, 1))
	// Outside tiles are solid too.
	TileMapNode_BuildColliders(tm, &game.gameContext)
	hasFar := false
	for s in tm.staticBody.shapes do if s.offset.x > 8 * 16 do hasFar = true
	testing.expect(t, hasFar, "a collider for the tile right of the map")
}

// Components painted on a tile map: one per cell, a 2 x 2 one over its
// footprint (replacing what it covers), off-grid placement, erase, flood
// fill, saved as linked instances and found again after a reload, Lua.
@(test)
test_tilemap_components :: proc(t: ^testing.T) {
	dir :: "test_tilemap_components_zz"
	defer os.remove_all(dir)
	_ = os.make_directory_all(dir + "/components")
	// A coin (a 20 px circle: one cell) and a crate (a 64 px box: 2 x 2 on 32 px tiles).
	_ = os.write_entire_file(dir + "/components/coin.component.json", transmute([]u8)string(`{"type": "AreaNode", "name": "Coin", "physics": {"shape": {"type": "circle", "radius": 10}}}`))
	_ = os.write_entire_file(dir + "/components/crate.component.json", transmute([]u8)string(`{"type": "StaticBodyNode", "name": "Crate", "physics": {"shape": {"type": "box", "size": [64, 64]}}}`))
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, dir)
	scene := game->createScene("tcomp", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	tm := cast(^TileMapNode)Node_CreateByTypeName(scene, "TileMapNode")
	tm.name = "Map"
	tm.gameContext = &game.gameContext
	tm.mapSize = {8, 6}
	tm.tileSize = {32, 32}
	ProcessNodeQueues(scene.manager, &game.gameContext)
	COIN :: "components/coin.component.json"
	CRATE :: "components/crate.component.json"

	coin := TileMapNode_PlaceComponent(tm, {1, 1}, COIN)
	testing.expect(t, coin != nil && coin.componentPath == COIN && coin.parent == tm, "a linked instance under the map")
	if coin == nil do return
	testing.expectf(t, coin.position == {48, 48}, "at the cell's centre (%v)", coin.position)
	testing.expect_value(t, coin.name, "coin_1_1")
	testing.expect(t, TileMapNode_ComponentAt(tm, {1, 1}) == coin && TileMapNode_ComponentAt(tm, {2, 1}) == nil, "one cell")
	// The same cell again: replaced (one per cell).
	coin2 := TileMapNode_PlaceComponent(tm, {1, 1}, COIN)
	testing.expect(t, len(TileMapNode_Components(tm)) == 1 && TileMapNode_ComponentAt(tm, {1, 1}) == coin2, "one per cell")
	// A crate on (2, 1): 2 x 2 from there; then one on (1, 1) covers the coin.
	crate := TileMapNode_PlaceComponent(tm, {2, 1}, CRATE)
	testing.expect(t, TileMapNode_ComponentFootprint(tm, CRATE) == {2, 2}, "measured: 2 x 2")
	testing.expectf(t, crate != nil && crate.position == {96, 64}, "centred on its footprint (%v)", crate.position if crate != nil else [2]f32{})
	for c in ([][2]int{{2, 1}, {3, 1}, {2, 2}, {3, 2}}) do testing.expectf(t, TileMapNode_ComponentAt(tm, c) == crate, "the crate covers %v", c)
	crate2 := TileMapNode_PlaceComponent(tm, {1, 1}, CRATE)
	testing.expect(t, len(TileMapNode_Components(tm)) == 1 && TileMapNode_ComponentAt(tm, {2, 2}) == crate2, "the coin and the overlapping crate replaced")
	// At the map's edge: kept inside.
	edge := TileMapNode_PlaceComponent(tm, {7, 5}, CRATE)
	testing.expect(t, edge != nil && TileMapNode_ComponentAt(tm, {6, 4}) == edge, "clamped inside the map")
	// Off the grid: where asked, covering the nearest footprint.
	off := TileMapNode_PlaceComponent(tm, {5, 0}, COIN, true, {170, 20})
	testing.expect(t, off != nil && off.position == {170, 20} && TileMapNode_ComponentAt(tm, {5, 0}) == off, "off-grid coin")
	// Erase.
	testing.expect(t, TileMapNode_RemoveComponentAt(tm, {2, 2}) && TileMapNode_ComponentAt(tm, {1, 1}) == nil, "erased the whole crate")
	testing.expect(t, !TileMapNode_RemoveComponentAt(tm, {0, 5}), "nothing there")
	// Flood fill: the empty cells (48 - the edge crate's 4 - the off-grid coin's 1).
	n := TileMapNode_FillComponents(tm, {0, 0}, COIN)
	testing.expect_value(t, n, 43)
	testing.expect_value(t, len(TileMapNode_Components(tm)), 45)

	// Saved as linked instances; the layer is found again after a reload.
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"component": "components/coin.component.json"`), "saved linked")
	copy1 := reload_scene(game, text, "tcomp2")
	m2 := cast(^TileMapNode)Scene_FindNodeByName(copy1, "Map")
	if m2 == nil do testing.fail_now(t, "no map")
	m2.gameContext = &game.gameContext
	game.gameContext.scene = copy1
	Node_SetGlobalPositions(copy1.manager, copy1.rootNode)
	testing.expect_value(t, len(TileMapNode_Components(m2)), 45)
	testing.expect(t, TileMapNode_ComponentAt(m2, {6, 4}) != nil && TileMapNode_ComponentAt(m2, {6, 4}).componentPath == CRATE, "the crate's footprint after a reload")
	game.gameContext.scene = scene

	// Lua.
	L := game.scriptManager.L
	if lua.L_dostring(L, `
local m = Scene.find_node("Map")
m:tilemap_clear_component(0, 0)
empty = m:tilemap_component_at(0, 0) == nil
local c = m:tilemap_set_component(0, 0, "components/crate.component.json")
placed = c ~= nil and m:tilemap_component_at(1, 1) ~= nil
`) != 0 {
		testing.fail_now(t, string(lua.tostring(L, -1)))
	}
	getb :: proc(L: ^lua.State, n: cstring) -> bool {lua.getglobal(L, n); defer lua.pop(L, 1); return bool(lua.toboolean(L, -1))}
	testing.expect(t, getb(L, "empty") && getb(L, "placed"), "Lua: clear, at, set")
}

@(test)
test_component_instances_add_and_remove_children :: proc(t: ^testing.T) {
	dir :: "test_component_structure"
	file :: dir + "/components/ship.component.json"
	defer os.remove_all(dir)
	_ = os.make_directory_all(dir + "/components")
	_ = os.write_entire_file(file, transmute([]u8)string(`{"type": "Node", "name": "Ship", "children": [{"type": "Node", "name": "Thruster"}, {"type": "Node", "name": "Gun"}]}`))
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, dir)
	scene := game->createScene("struct", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	a := Scene_InstantiateComponent(scene, "components/ship.component.json", nil, &game.gameContext)
	ProcessNodeQueues(scene.manager, &game.gameContext)

	// Add a child under Thruster, remove Gun.
	thruster := Scene_FindNodeByName(scene, "Thruster")
	shield := Node_CreateByTypeName(scene, "Node", thruster)
	shield.name = "Shield"
	shield.position = {3, 4}
	RemoveNode(scene.manager, Scene_FindNodeByName(scene, "Gun"))
	ProcessNodeQueues(scene.manager, &game.gameContext)
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"$added": {"Thruster": [{`), "added child saved")
	testing.expect(t, strings.contains(text, `"$removed": ["Gun"]`), "removed child saved")
	over := Node_ComponentOverrides(scene.manager, thruster)
	testing.expect(t, len(over) == 1 && over[0] == "+1 child(ren)", "structure override reported")

	copy1 := reload_scene(game, text, "struct2")
	testing.expect(t, Scene_FindNodeByName(copy1, "Shield") != nil, "added child restored")
	testing.expect(t, Scene_FindNodeByName(copy1, "Gun") == nil, "removed child stays removed")

	// The component gains a child: it still appears; structure overrides stay.
	_ = os.write_entire_file(file, transmute([]u8)string(`{"type": "Node", "name": "Ship", "children": [{"type": "Node", "name": "Thruster"}, {"type": "Node", "name": "Gun"}, {"type": "Node", "name": "Radar"}]}`))
	Scene_RefreshComponentInstances(copy1, "components/ship.component.json", &game.gameContext)
	testing.expect(t, Scene_FindNodeByName(copy1, "Radar") != nil && Scene_FindNodeByName(copy1, "Shield") != nil && Scene_FindNodeByName(copy1, "Gun") == nil, "component change merged")

	// Apply the instance to the component file.
	inst := Scene_FindNodeByName(copy1, "Ship")
	full := Component_InstanceJSON(inst, copy1.manager, context.temp_allocator)
	testing.expect(t, strings.contains(full, `"Shield"`) && !strings.contains(full, `"Gun"`) && !strings.contains(full, `"overrides"`), "instance baked to a component")
	_ = a
}

// A component's own tags and pause mode come with every instance (the
// instance JSON only replaces them when it sets its own).
@(test)
test_component_instances_keep_their_tags :: proc(t: ^testing.T) {
	dir :: "test_component_tags_project"
	defer os.remove_all(dir)
	_ = os.make_directory_all(dir + "/components")
	_ = os.write_entire_file(dir + "/components/enemy.component.json", transmute([]u8)string(`{"type": "Node", "name": "Enemy", "tags": ["enemy", "flying"], "pause_mode": "always"}`))
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, dir)
	scene := game->createScene("tags", true)
	a := Scene_InstantiateComponent(scene, "components/enemy.component.json", nil, &game.gameContext)
	testing.expect(t, a != nil, "instance")
	if a == nil do return
	testing.expect(t, Node_HasTag(a, "enemy") && Node_HasTag(a, "flying"), "the component's tags")
	testing.expect_value(t, a.pauseMode, Pause_Mode.Always)
	// An instance that sets its own tags replaces them.
	b := Scene_InstantiateNodeFromJSON(scene, transmute([]u8)string(`{"name": "Boss", "component": "components/enemy.component.json", "tags": ["boss"]}`), nil, &game.gameContext)
	testing.expect(t, b != nil && Node_HasTag(b, "boss") && !Node_HasTag(b, "enemy"), "the instance's own tags")
}
