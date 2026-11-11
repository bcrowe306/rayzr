package engine

import lua "lua54"
import b2 "vendor:box2d"

// ============================================================================
// The fixed physics step. The world steps at a fixed rate (Project Settings >
// Physics > Physics FPS, 60 by default; 0 = once per frame with the frame's
// time, as before 1.2), as many steps as the frame's time holds. Scripts'
// on_physics_update(dt) and the Character Mover's built-in movement run once
// before each step, with that step's time. Bodies are drawn between their
// last two steps (interpolated), so motion stays smooth on any display rate.
// The same game behaves the same at 30, 60 or 144 frames a second.
// ============================================================================

PHYSICS_MAX_STEPS_PER_FRAME :: 8 // (a slow frame drops the rest: no spiral)

// Physics_Interp: a body node's last two physics states, drawn between.
Physics_Interp :: struct {
	prevPos, curPos: [2]f32,
	prevRot, curRot: f32, // degrees
	step:  u64,  // the step that set cur
	valid: bool,
}

// Physics_Fixed: the world steps at a fixed rate (and bodies interpolate).
Physics_Fixed :: proc(pw: ^PhysicsWorld) -> bool {
	return pw != nil && pw.physicsFps > 0
}

// Physics_StepTime: the time of one step (the frame's time when not fixed).
Physics_StepTime :: proc(pw: ^PhysicsWorld) -> f32 {
	return 1 / f32(pw.physicsFps) if pw.physicsFps > 0 else pw.stepDt
}

// Physics_Advance runs this frame's physics: the fixed steps its time holds
// (with on_physics_update and the movers' built-in movement before each),
// or one step of the frame's time when not fixed.
Physics_Advance :: proc(game: ^Game, dt: f32) {
	pw := &game.physicsWorld
	if pw.paused || dt <= 0 {
		pw.stepsThisFrame = 0
		return
	}
	if !Physics_Fixed(pw) {
		pw.stepDt = dt
		pw.alpha = 1
		physics_run_step(game, dt)
		pw.stepsThisFrame = 1
		return
	}
	h := 1 / f32(pw.physicsFps)
	pw.stepDt = h
	pw.accumulator += dt
	n := 0
	for pw.accumulator >= h - 1e-5 && n < PHYSICS_MAX_STEPS_PER_FRAME {
		pw.accumulator -= h
		physics_run_step(game, h)
		n += 1
	}
	if pw.accumulator >= h do pw.accumulator = 0 // (too far behind: let it go)
	if pw.accumulator < 0 do pw.accumulator = 0
	pw.stepsThisFrame = n
	pw.alpha = clamp(pw.accumulator / h, 0, 1)
}

@(private = "file")
physics_run_step :: proc(game: ^Game, h: f32) {
	pw := &game.physicsWorld
	ctx := &game.gameContext
	pw.stepIndex += 1
	pw.inStep = true
	defer pw.inStep = false
	if s := game.sceneManager.currentScene; s != nil && s.isLoaded && s.manager != nil && s.rootNode != nil {
		physics_tick_tree(s, s.rootNode, ctx, h, game.treePaused, .Pausable)
		Area_ApplyOverrides(s, ctx, h)
	}
	PhysicsWorld_Step(pw, h, ctx)
}

// physics_tick_tree: the per-step work of each running node (as the frame
// update skips paused and disabled subtrees).
@(private = "file")
physics_tick_tree :: proc(scene: ^Scene, node: ^Node, ctx: ^GameContext, h: f32, parentPaused: bool, parentMode: Pause_Mode) {
	if node == nil || !node.enabled do return
	mode := node.pauseMode if node.pauseMode != .Inherit else parentMode
	paused := node.paused || (mode == .Pausable && parentPaused)
	if !paused && node.isReady {
		if node.typeId == CharacterMoverNode && Physics_Fixed(&ctx.game.physicsWorld) {
			CharacterMover_PhysicsTick(cast(^CharacterMoverNode)node, ctx, h)
		}
		if node.scriptInstance != nil do ScriptInstance_CallPhysicsUpdate(cast(^ScriptInstance)node.scriptInstance, h, ctx.scriptManager)
	}
	for child in GetChildrenTemp(scene.manager, node) {
		if !Node_IsAlive(child) do continue
		physics_tick_tree(scene, child, ctx, h, paused, mode)
	}
}

// ScriptInstance_CallPhysicsUpdate: the script's on_physics_update(dt), if it
// has one (looked up once).
ScriptInstance_CallPhysicsUpdate :: proc(inst: ^ScriptInstance, h: f32, sm: ^ScriptManager) {
	if inst == nil || !inst.isReady || inst.physicsState == 1 do return
	mgr := sm if sm != nil else inst.scriptManager
	if mgr == nil || !mgr.isReady || mgr.L == nil do return
	L := mgr.L
	lua.pushcfunction(L, lua_traceback_error_handler)
	errHandler := lua.gettop(L)
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef))
	lua.getfield(L, -1, "on_physics_update")
	if lua.type(L, -1) != .FUNCTION {
		inst.physicsState = 1
		lua.pop(L, 3)
		return
	}
	inst.physicsState = 2
	lua.pushvalue(L, -2)
	lua.pushnumber(L, lua.Number(h))
	prev := mgr.currentInstance
	mgr.currentInstance = inst
	if lua.pcall(L, 2, 0, errHandler) != 0 {
		Script_Problem(.Error, "[ScriptInstance] Error in on_physics_update() for '%s': %s", inst.modulePath, lua.tostring(L, -1))
		lua.pop(L, 1)
	}
	mgr.currentInstance = prev
	lua.pop(L, 2) // self, errHandler
}

// Physics_RecordMoves: after a step, the bodies Box2D moved get their new
// state (the previous one kept to draw between).
Physics_RecordMoves :: proc(pw: ^PhysicsWorld) {
	if !Physics_Fixed(pw) do return
	ev := b2.World_GetBodyEvents(pw.worldId)
	for i in 0 ..< ev.moveCount {
		m := ev.moveEvents[i]
		n := cast(^Node)m.userData
		if n == nil || !Node_IsAlive(n) do continue
		ip: ^Physics_Interp
		switch n.typeId {
		case DynamicBodyNode: ip = &(cast(^DynamicBodyNode)n).interp
		case KinematicBodyNode: ip = &(cast(^KinematicBodyNode)n).interp
		}
		if ip == nil do continue
		Physics_InterpPush(ip, pw, m.transform.p, RotToDegrees(m.transform.q))
	}
}

// Physics_InterpPush: a new physics state (the old one becomes the previous).
Physics_InterpPush :: proc(ip: ^Physics_Interp, pw: ^PhysicsWorld, pos: [2]f32, rot: f32) {
	if ip.valid {
		ip.prevPos, ip.prevRot = ip.curPos, ip.curRot
	} else {
		ip.prevPos, ip.prevRot = pos, rot
	}
	ip.curPos, ip.curRot = pos, rot
	ip.step = pw.stepIndex
	ip.valid = true
}

// Physics_InterpReset: no motion to draw between (a teleport, a new body).
Physics_InterpReset :: proc(ip: ^Physics_Interp, pw: ^PhysicsWorld, pos: [2]f32, rot: f32) {
	ip^ = {prevPos = pos, curPos = pos, prevRot = rot, curRot = rot, step = pw.stepIndex, valid = true}
}

// Physics_InterpAt: where to draw the body now (between its last two steps;
// at its last state when it didn't move in the latest step).
Physics_InterpAt :: proc(ip: ^Physics_Interp, pw: ^PhysicsWorld) -> (pos: [2]f32, rot: f32) {
	if ip.step != pw.stepIndex do return ip.curPos, ip.curRot
	a := pw.alpha
	pos = ip.prevPos + (ip.curPos - ip.prevPos) * a
	d := ip.curRot - ip.prevRot
	for d > 180 do d -= 360
	for d < -180 do d += 360
	rot = ip.prevRot + d * a
	return
}

// physics_world_of: the physics world of a context (nil without a game).
physics_world_of :: proc(ctx: ^GameContext) -> ^PhysicsWorld {
	if ctx == nil || ctx.game == nil do return nil
	return &ctx.game.physicsWorld
}
