package engine

import "core:math"
import "core:testing"
import lua "lua54"
import b2 "vendor:box2d"

// The physics additions (engine/docs/physics_scripting.md): the fixed step,
// contact details, exceptions, queries, forces, shapes, test moves, the
// mover's floors / steps / platforms, area overrides.

@(private = "file")
pp_game :: proc(name: string) -> (^Game, ^Scene, ^GameContext) {
	game := new(Game)
	InitializeGame(game)
	scene := game->createScene(name, true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	return game, scene, &game.gameContext
}

@(private = "file")
pp_run :: proc(t: ^testing.T, L: ^lua.State, code: cstring, loc := #caller_location) {
	if lua.L_dostring(L, code) != 0 {
		testing.expectf(t, false, "Lua: %s", lua.tostring(L, -1), loc = loc)
		lua.pop(L, 1)
	}
}

@(private = "file")
pp_num :: proc(L: ^lua.State, name: cstring) -> f64 {
	lua.getglobal(L, name)
	defer lua.pop(L, 1)
	return f64(lua.tonumber(L, -1))
}

@(private = "file")
pp_bool :: proc(L: ^lua.State, name: cstring) -> bool {
	lua.getglobal(L, name)
	defer lua.pop(L, 1)
	return bool(lua.toboolean(L, -1))
}

@(private = "file")
pp_static :: proc(scene: ^Scene, ctx: ^GameContext, name: string, pos, size: [2]f32) -> ^StaticBodyNode {
	sb := StaticBodyNode_Create(scene, name)
	sb.position = pos
	sb.gameContext = ctx
	StaticBodyNode_AddShape(sb, MakeBoxPhysicsShape(size.x, size.y), ctx)
	return sb
}

@(private = "file")
pp_dynamic :: proc(scene: ^Scene, ctx: ^GameContext, name: string, pos: [2]f32, size: f32 = 20) -> ^DynamicBodyNode {
	db := DynamicBodyNode_Create(scene, name)
	db.position = pos
	db.gameContext = ctx
	DynamicBodyNode_AddShape(db, MakeBoxPhysicsShape(size, size), ctx)
	return db
}

// Fixed 60 Hz steps whatever the frame rate, on_physics_update before each,
// bodies drawn between their last two steps; 0 = one step per frame.
@(test)
test_physics_fixed_step :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("pp_ticks.lua", `
local T = {}
function T:ready() ticks = 0; tick_dt = 0 end
function T:on_physics_update(dt) ticks = ticks + 1; tick_dt = dt end
return T
`)
	game, scene, ctx := pp_game("fixed_step")
	defer game->terminate()
	pw := &game.physicsWorld
	testing.expect_value(t, pw.physicsFps, 60)
	counter := Node_CreateByTypeName(scene, "Node")
	counter.gameContext = ctx
	Script_AttachToNode(counter, "pp_ticks.lua", nil, &game.scriptManager)
	ball := pp_dynamic(scene, ctx, "Ball", {0, 0})
	ProcessNodeQueues(scene.manager, ctx)
	L := game.scriptManager.L

	game->run(1.0 / 60) // (ready, one step)
	start := pp_num(L, "ticks")
	for _ in 0 ..< 2 do game->run(1.0 / 120)
	testing.expectf(t, pp_num(L, "ticks") - start == 1, "two 1/120 s frames: one step (%v)", pp_num(L, "ticks") - start)
	game->run(1.0 / 30)
	testing.expectf(t, pp_num(L, "ticks") - start == 3, "a 1/30 s frame: two steps (%v)", pp_num(L, "ticks") - start)
	testing.expectf(t, abs(pp_num(L, "tick_dt") - 1.0 / 60) < 1e-6, "each step 1/60 s (%v)", pp_num(L, "tick_dt"))

	// Half a step into the next: drawn halfway between its last two steps.
	for _ in 0 ..< 20 do game->run(1.0 / 60)
	game->run(1.0 / 120)
	ip := ball.interp
	mid := (ip.prevPos + ip.curPos) / 2
	testing.expectf(t, ip.step == pw.stepIndex && ip.curPos.y > ip.prevPos.y, "falling: two states (%v -> %v)", ip.prevPos, ip.curPos)
	testing.expectf(t, abs(ball.globalPosition.y - mid.y) < 0.01, "drawn halfway (%v; %v)", ball.globalPosition.y, mid.y)

	// fps 0: one step of the frame's time.
	pp_run(t, L, `Physics.set_fps(0); fps = Physics.get_fps()`)
	before := pp_num(L, "ticks")
	game->run(1.0 / 30)
	testing.expect(t, pp_num(L, "fps") == 0 && pp_num(L, "ticks") - before == 1, "fps 0: one step a frame")
	testing.expectf(t, abs(pp_num(L, "tick_dt") - 1.0 / 30) < 1e-6, "with the frame's time (%v)", pp_num(L, "tick_dt"))
	testing.expect(t, abs(ball.globalPosition.y - f32(b2.Body_GetPosition(ball.bodyId).y)) < 0.01, "drawn where it is")
}

// collision_started's contact (point, normal, speed); exceptions stop a pair colliding.
@(test)
test_physics_contact_and_exceptions :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("pp_contact.lua", `
local B = {}
function B:on_collision_started(other, contact)
	if hit_name then return end -- (the first landing, not the bounces)
	hit_name = other:get_name()
	c_ny = contact.normal_y; c_py = contact.point_y; c_speed = contact.speed
end
return B
`)
	game, scene, ctx := pp_game("contacts")
	defer game->terminate()
	ground := pp_static(scene, ctx, "Ground", {0, 200}, {800, 20}) // top at 190
	ball := pp_dynamic(scene, ctx, "Ball", {0, 0})
	Script_AttachToNode(ball, "pp_contact.lua", nil, &game.scriptManager)
	ghost := pp_dynamic(scene, ctx, "Ghost", {200, 0})
	ProcessNodeQueues(scene.manager, ctx)
	L := game.scriptManager.L
	push_node_userdata(L, ghost)
	lua.setglobal(L, "ghost")
	push_node_userdata(L, ground)
	lua.setglobal(L, "ground")
	pp_run(t, L, `ok = ghost:add_collision_exception(ground); has = ghost:has_collision_exception(ground)`)
	testing.expect(t, pp_bool(L, "ok") && pp_bool(L, "has"), "exception added")
	for _ in 0 ..< 120 do game->run(1.0 / 60)

	lua.getglobal(L, "hit_name")
	testing.expectf(t, bool(lua.isstring(L, -1)) && string(lua.tostring(L, -1)) == "Ground", "the ball hit the ground")
	lua.pop(L, 1)
	testing.expectf(t, abs(pp_num(L, "c_ny") + 1) < 0.01, "the normal points up, away from the ground (%v)", pp_num(L, "c_ny"))
	testing.expectf(t, abs(pp_num(L, "c_py") - 190) < 3, "touching the ground's top (%v)", pp_num(L, "c_py"))
	testing.expectf(t, pp_num(L, "c_speed") > 100, "it landed fast (%v px/s)", pp_num(L, "c_speed"))
	testing.expectf(t, ghost.globalPosition.y > 250, "the ghost fell through the ground (y %v)", ghost.globalPosition.y)
	testing.expectf(t, ball.globalPosition.y < 190, "the ball rests on it (y %v)", ball.globalPosition.y)

	pp_run(t, L, `ghost:remove_collision_exception(ground); has = ghost:has_collision_exception(ground)`)
	testing.expect(t, !pp_bool(L, "has"), "exception removed")
}

// raycast_all, exclude, overlap_circle / box / point, cast_shape.
@(test)
test_physics_queries :: proc(t: ^testing.T) {
	game, scene, ctx := pp_game("queries")
	defer game->terminate()
	game.physicsWorld.gravity = {}
	pp_static(scene, ctx, "A", {100, 0}, {20, 20})
	pp_static(scene, ctx, "B", {200, 0}, {20, 20})
	ProcessNodeQueues(scene.manager, ctx)
	game->run(1.0 / 60)
	L := game.scriptManager.L
	pp_run(t, L, `
		local hits = Physics.raycast_all(0, 0, 300, 0)
		n_hits = #hits
		first = hits[1] and hits[1].node:get_name() or ""
		second = hits[2] and hits[2].node:get_name() or ""
		local a = Scene.find_node("A")
		local h = Physics.raycast(0, 0, 300, 0, { exclude = a })
		excl = h and h.node:get_name() or ""
		n_circle = #Physics.overlap_circle(100, 0, 15)
		n_box = #Physics.overlap_box(150, 0, 300, 10)
		n_point_b = #Physics.overlap_point(200, 0)
		n_point_gap = #Physics.overlap_point(150, 0)
		local c = Physics.cast_shape({ type = "circle", radius = 5 }, 100, -60, 100, 60)
		cast_name = c and c.node:get_name() or ""
		cast_ny = c and c.normal_y or 0
		cast_y = c and c.point_y or 0
	`)
	testing.expect_value(t, pp_num(L, "n_hits"), 2)
	lua.getglobal(L, "first"); lua.getglobal(L, "second"); lua.getglobal(L, "excl"); lua.getglobal(L, "cast_name")
	testing.expect(t, string(lua.tostring(L, -4)) == "A" && string(lua.tostring(L, -3)) == "B", "nearest first")
	testing.expect(t, string(lua.tostring(L, -2)) == "B", "A excluded: B")
	testing.expect(t, string(lua.tostring(L, -1)) == "A", "the cast circle hits A")
	lua.pop(L, 4)
	testing.expect_value(t, pp_num(L, "n_circle"), 1)
	testing.expect_value(t, pp_num(L, "n_box"), 2)
	testing.expect_value(t, pp_num(L, "n_point_b"), 1)
	testing.expect_value(t, pp_num(L, "n_point_gap"), 0)
	testing.expectf(t, abs(pp_num(L, "cast_ny") + 1) < 0.01 && abs(pp_num(L, "cast_y") + 10) < 1, "hit A's top (normal y %v, y %v)", pp_num(L, "cast_ny"), pp_num(L, "cast_y"))
}

// Forces at points, torque, mass; shapes changed from Lua; test moves.
@(test)
test_physics_forces_shapes_moves :: proc(t: ^testing.T) {
	game, scene, ctx := pp_game("forces")
	defer game->terminate()
	game.physicsWorld.gravity = {}
	box := pp_dynamic(scene, ctx, "Box", {0, 0})
	wall := pp_static(scene, ctx, "Wall", {200, 0}, {20, 200}) // left side at 190
	_ = wall
	kin := KinematicBodyNode_Create(scene, "Kin")
	kin.position = {0, 100}
	kin.gameContext = ctx
	KinematicBodyNode_AddShape(kin, MakeBoxPhysicsShape(20, 20), ctx)
	ProcessNodeQueues(scene.manager, ctx)
	game->run(1.0 / 60)
	L := game.scriptManager.L
	pp_run(t, L, `
		local b = Scene.find_node("Box")
		b:set_mass(10)
		mass = b:get_mass()
		b:apply_impulse_at(0, 500, 10, 0) -- (down, at its right edge: it turns)
		local sh = b:shape_get(1)
		w0 = sh.width; count = b:shape_count()
		ok = b:shape_set(1, { friction = 0.1, width = 40 })
		w1 = b:shape_get(1).width
		bad = b:shape_set(5, { friction = 0 })
	`)
	testing.expectf(t, abs(pp_num(L, "mass") - 10) < 0.01, "set_mass (%v)", pp_num(L, "mass"))
	testing.expect(t, pp_num(L, "w0") == 20 && pp_num(L, "w1") == 40 && pp_num(L, "count") == 1, "shape_get / shape_set")
	testing.expect(t, pp_bool(L, "ok") && !pp_bool(L, "bad"), "no shape 5")
	game->run(1.0 / 60)
	testing.expectf(t, abs(b2.Body_GetAngularVelocity(box.bodyId)) > 0.1, "the impulse off-centre spins it (%v)", b2.Body_GetAngularVelocity(box.bodyId))
	testing.expectf(t, abs(b2.Shape_GetFriction(box.shapes[0].shapeId) - 0.1) < 1e-4, "Box2D has the new friction")

	pp_run(t, L, `
		local k = Scene.find_node("Kin")
		local hit = k:body_test_move(300, 0)
		test_hit = hit ~= nil and hit.node:get_name() == "Wall"
		local free = k:body_test_move(0, 50)
		test_free = free == nil
		local mc = k:body_move_and_collide(300, 0)
		moved_hit = mc ~= nil
	`)
	testing.expect(t, pp_bool(L, "test_hit") && pp_bool(L, "test_free"), "body_test_move")
	testing.expect(t, pp_bool(L, "moved_hit"), "body_move_and_collide hit the wall")
	testing.expectf(t, kin.globalPosition.x > 170 && kin.globalPosition.x < 181, "stopped against the wall (x %v)", kin.globalPosition.x)
}

// Steps, platform velocity, time since the floor, floor snap, test moves.
@(test)
test_physics_mover_extras :: proc(t: ^testing.T) {
	game, scene, ctx := pp_game("mover_extras")
	defer game->terminate()
	pp_static(scene, ctx, "Floor", {0, 200}, {2000, 20})   // top at 190
	pp_static(scene, ctx, "Step", {200, 178}, {100, 24})   // a step 24 px high, from x 150 (top at 166)
	mover :: proc(scene: ^Scene, ctx: ^GameContext, name: string, x: f32) -> ^CharacterMoverNode {
		cm := CharacterMoverNode_Create(scene, name)
		cm.enableKeyboardInput = false
		cm.position = {x, 150}
		cm.gameContext = ctx
		return cm
	}
	stepper := mover(scene, ctx, "Stepper", 0)
	stepper.stepHeight = 28
	stepper.targetSpeedX = 120
	blocked := mover(scene, ctx, "Blocked", 0)
	blocked.targetSpeedX = 120
	blocked.categoryLayers = {.Layer2} // (the two movers don't meet)
	blocked.maskLayers = {.Layer1}
	stepper.categoryLayers = {.Layer3}
	stepper.maskLayers = {.Layer1}
	ProcessNodeQueues(scene.manager, ctx)
	for _ in 0 ..< 120 do game->run(1.0 / 60)
	testing.expectf(t, stepper.globalPosition.x > 170, "Step Height: up onto the step (x %v)", stepper.globalPosition.x)
	testing.expectf(t, blocked.globalPosition.x < 150, "no Step Height: stopped at it (x %v)", blocked.globalPosition.x)
	testing.expect(t, stepper.isOnFloor, "on the step")

	// Platform velocity: standing on a moving kinematic platform.
	plat := KinematicBodyNode_Create(scene, "Platform")
	plat.position = {1000, 100}
	plat.gameContext = ctx
	plat.linearVelocity = {60, 0}
	KinematicBodyNode_AddShape(plat, MakeBoxPhysicsShape(200, 10), ctx) // top at 95
	rider := mover(scene, ctx, "Rider", 1000)
	rider.position = {1000, 60}
	ProcessNodeQueues(scene.manager, ctx)
	for _ in 0 ..< 90 do game->run(1.0 / 60)
	L := game.scriptManager.L
	pp_run(t, L, `
		local r = Scene.find_node("Rider")
		pvx = r:character_get_platform_velocity()
		since = r:character_get_time_since_floor()
		was = r:character_was_on_floor(0.1)
		blocked_down, frac = r:character_test_move(0, 100)
	`)
	testing.expectf(t, abs(pp_num(L, "pvx") - 60) < 1, "platform velocity 60 (%v)", pp_num(L, "pvx"))
	testing.expectf(t, rider.globalPosition.x > 1050, "carried along (x %v)", rider.globalPosition.x)
	testing.expect(t, pp_num(L, "since") == 0 && pp_bool(L, "was"), "on a floor now")
	testing.expectf(t, pp_bool(L, "blocked_down") && pp_num(L, "frac") < 0.2, "the platform is right below (%v)", pp_num(L, "frac"))

	// Floor snap: walking off the step's far edge (24 px down), it stays on a floor.
	snapper := mover(scene, ctx, "Snapper", 200)
	snapper.position = {200, 120}
	snapper.floorSnapLength = 30
	snapper.targetSpeedX = 200
	snapper.categoryLayers = {.Layer4}
	snapper.maskLayers = {.Layer1}
	ProcessNodeQueues(scene.manager, ctx)
	for _ in 0 ..< 30 do game->run(1.0 / 60)
	airborne := 0
	for _ in 0 ..< 40 {
		game->run(1.0 / 60)
		if !snapper.isOnFloor do airborne += 1
	}
	testing.expectf(t, snapper.globalPosition.x > 260, "walked off the step (x %v)", snapper.globalPosition.x)
	testing.expectf(t, airborne == 0, "Floor Snap: never in the air (%d frames)", airborne)
}

// Area overrides: Replace gravity lifts bodies and movers; damping slows them.
@(test)
test_physics_area_overrides :: proc(t: ^testing.T) {
	game, scene, ctx := pp_game("area_overrides")
	defer game->terminate()
	area := AreaNode_Create(scene, "AntiGrav")
	area.position = {0, 0}
	area.gameContext = ctx
	AreaNode_AddShape(area, MakeBoxPhysicsShape(400, 400), ctx)
	area.gravityMode = .Replace
	area.gravity = {0, -300}
	ball := pp_dynamic(scene, ctx, "Ball", {0, 0})
	cm := CharacterMoverNode_Create(scene, "Floater")
	cm.enableKeyboardInput = false
	cm.position = {100, 0}
	cm.gameContext = ctx
	water := AreaNode_Create(scene, "Water")
	water.position = {1000, 0}
	water.gameContext = ctx
	AreaNode_AddShape(water, MakeBoxPhysicsShape(400, 2000), ctx)
	water.dampingOverride = true
	water.linearDamping = 5
	sinker := pp_dynamic(scene, ctx, "Sinker", {1000, -100})
	faller := pp_dynamic(scene, ctx, "Faller", {3000, -100})
	ProcessNodeQueues(scene.manager, ctx)
	for _ in 0 ..< 30 do game->run(1.0 / 60)
	testing.expectf(t, ball.globalPosition.y < -5, "Replace gravity lifts the ball (y %v)", ball.globalPosition.y)
	testing.expectf(t, cm.globalPosition.y < -5, "and the Character Mover (y %v)", cm.globalPosition.y)
	vs := b2.Body_GetLinearVelocity(sinker.bodyId).y
	vf := b2.Body_GetLinearVelocity(faller.bodyId).y
	testing.expectf(t, vs < vf * 0.6, "water damping slows the sinker (%v vs %v)", vs, vf)
	_ = math.PI
}
