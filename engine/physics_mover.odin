package engine

import "base:runtime"
import "core:c"
import "core:math"
import lua "lua54"
import b2 "vendor:box2d"

// ============================================================================
// Character Mover helpers (physics_nodes.odin moves it): the built-in
// movement (with coyote time and jump buffering), the floor angle, step-up,
// collision exceptions, test moves, and the Lua methods for them.
// ============================================================================

// Mover_FloorCos: a surface is a floor when its normal's up part is above this.
Mover_FloorCos :: proc "contextless" (cm: ^CharacterMoverNode) -> f32 {
	a := cm.floorMaxAngle if cm.floorMaxAngle > 0 else 60
	return math.cos(math.to_radians(clamp(a, 1, 89)))
}

// Mover_IsBuiltIn: the mover moves itself (not a script's character).
Mover_IsBuiltIn :: proc(cm: ^CharacterMoverNode) -> bool {
	if cm.controlMode == .Script do return false
	// (A script with no player assigned controls it: an enemy, an NPC.)
	if cm.node.scriptInstance != nil && cm.playerIndex == 0 do return false
	return true
}

// mover_read_jump: a jump pressed this frame waits for the next move (and,
// with Jump Buffer Time, for that long before landing).
mover_read_jump :: proc(cm: ^CharacterMoverNode, ctx: ^GameContext) {
	if !cm.enableKeyboardInput || cm.playerIndex <= 0 || cm.playerIndex > MAX_PLAYERS do return
	if IsPlayerActionPressed(ctx, .Jump, cm.playerIndex) {
		cm.jumpQueued = true
		cm.jumpBufferLeft = cm.jumpBufferTime
	}
}

// CharacterMover_PhysicsTick: a fixed step's built-in movement.
CharacterMover_PhysicsTick :: proc(cm: ^CharacterMoverNode, ctx: ^GameContext, h: f32) {
	if !cm.enabled || !Mover_IsBuiltIn(cm) do return
	CharacterMover_BuiltInMove(cm, ctx, h)
}

// CharacterMover_BuiltInMove: run towards the input (or Target Speed X),
// jump, fall, move and slide.
CharacterMover_BuiltInMove :: proc(cm: ^CharacterMoverNode, ctx: ^GameContext, dt: f32) {
	if ctx == nil || ctx.game == nil || dt <= 0 do return
	desiredVX := cm.targetSpeedX
	if cm.enableKeyboardInput && cm.playerIndex > 0 && cm.playerIndex <= MAX_PLAYERS {
		moveAxis := GetPlayerActionAxis(ctx, .MoveLeft, .MoveRight, cm.playerIndex)
		if moveAxis != 0.0 do desiredVX = moveAxis * cm.maxSpeed
		// Jump: on a floor, or just after leaving one (Coyote Time).
		canJump := cm.isGrounded || (cm.coyoteTime > 0 && cm.timeSinceFloor <= cm.coyoteTime && !cm.jumpedSinceFloor)
		if (cm.jumpQueued || cm.jumpBufferLeft > 0) && canJump {
			cm.velocity.y = -cm.jumpSpeed
			cm.isGrounded = false
			cm.jumpedSinceFloor = true
			cm.jumpBufferLeft = 0
		}
		cm.jumpQueued = false
		cm.jumpBufferLeft = max(cm.jumpBufferLeft - dt, 0)
	}

	// Horizontal acceleration toward desiredVX
	diffX := desiredVX - cm.velocity.x
	maxDeltaV := cm.acceleration * dt
	if abs(diffX) <= maxDeltaV {
		cm.velocity.x = desiredVX
	} else {
		cm.velocity.x += math.copy_sign(maxDeltaV, diffX)
	}

	// Gravity (the world's, or an Area's override)
	cm.velocity += CharacterMoverNode_Gravity(cm, ctx) * dt

	CharacterMoverNode_MoveAndSlide(cm, ctx, dt)
}

// moverCastOwner: the mover whose casts are running (its collision
// exceptions are skipped).
moverCastOwner: ^CharacterMoverNode

// mover_excepted: the shape's node is one the mover doesn't collide with.
mover_excepted :: proc "contextless" (cm: ^CharacterMoverNode, shapeId: b2.ShapeId) -> bool {
	if cm == nil || cm.gameContext == nil || cm.gameContext.game == nil do return false
	pw := &cm.gameContext.game.physicsWorld
	if len(pw.exceptions) == 0 do return false
	context = runtime.default_context()
	other := cast(^Node)b2.Body_GetUserData(b2.Shape_GetBody(shapeId))
	return Physics_Excepted(pw, cm, other)
}

// mover_cast_all: how far (0..1) the mover's shapes, moved by `offset`
// first, get along `translation` before touching something.
mover_cast_all :: proc(cm: ^CharacterMoverNode, pw: ^PhysicsWorld, offset, translation: [2]f32, filter: b2.QueryFilter) -> f32 {
	shift :: proc(cap: b2.Capsule, d: [2]f32) -> b2.Capsule {
		return {center1 = cap.center1 + d, center2 = cap.center2 + d, radius = cap.radius}
	}
	if len(cm.shapes) == 0 {
		return character_mover_cast(pw.worldId, shift(CharacterMoverNode_GetWorldCapsule(cm), offset), translation, filter, cm.bodyId)
	}
	fraction: f32 = 1
	for &s in cm.shapes {
		if s.isSensor do continue
		cap := shift(CharacterMoverNode_ShapeWorldCapsule(cm, &s), offset)
		fraction = min(fraction, character_mover_cast(pw.worldId, cap, translation, filter, cm.bodyId))
	}
	return fraction
}

// mover_step_up: the move up over a step: up (Step Height), across, back
// down onto its top. ok when it lands on something.
mover_step_up :: proc(cm: ^CharacterMoverNode, pw: ^PhysicsWorld, dx: f32, filter: b2.QueryFilter) -> (delta: [2]f32, ok: bool) {
	up := [2]f32{0, -cm.stepHeight}
	fu := mover_cast_all(cm, pw, {}, up, filter)
	lift := up * fu
	if lift.y > -1 do return {}, false // (no room above)
	fa := mover_cast_all(cm, pw, lift, {dx, 0}, filter)
	across := [2]f32{dx * fa, 0}
	if abs(across.x) < 0.01 do return {}, false
	down := [2]f32{0, cm.stepHeight + 1}
	fd := mover_cast_all(cm, pw, lift + across, down, filter)
	if fd >= 1 do return {}, false // (nothing to stand on: not a step)
	return lift + across + down * fd, true
}

// --- Lua --------------------------------------------------------------------

@(private = "file")
mover_of :: proc(L: ^lua.State, fn: string) -> ^CharacterMoverNode {
	n, ok := to_node_userdata(L, 1)
	if !ok || n.typeId != CharacterMoverNode {
		Script_Problem(.Warning, "%s: called on %s, not a Character Mover", fn, n.name if ok && n != nil else "something that isn't a node")
		return nil
	}
	return cast(^CharacterMoverNode)n
}

// character_get_platform_velocity(): the velocity of what it stands on (px/s).
@(private = "file")
lua_character_get_platform_velocity :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cm := mover_of(L, "character_get_platform_velocity")
	v := cm.platformVelocity if cm != nil && cm.isOnFloor else [2]f32{}
	lua.pushnumber(L, lua.Number(v.x))
	lua.pushnumber(L, lua.Number(v.y))
	return 2
}

// character_get_time_since_floor(): seconds since it was last on a floor (0 on one).
@(private = "file")
lua_character_get_time_since_floor :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cm := mover_of(L, "character_get_time_since_floor")
	lua.pushnumber(L, lua.Number(cm.timeSinceFloor if cm != nil else 0))
	return 1
}

// character_was_on_floor(seconds): on a floor now or within the last `seconds`
// (coyote time for a script's jump).
@(private = "file")
lua_character_was_on_floor :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cm := mover_of(L, "character_was_on_floor")
	t := f32(lua.tonumber(L, 2)) if lua.isnumber(L, 2) else 0.1
	lua.pushboolean(L, b32(cm != nil && (cm.isOnFloor || cm.timeSinceFloor <= t)))
	return 1
}

// character_test_move(dx, dy) -> blocked, fraction: would moving by (dx, dy)
// hit something, and how far it would get (0..1). Nothing moves.
@(private = "file")
lua_character_test_move :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cm := mover_of(L, "character_test_move")
	if cm == nil || cm.gameContext == nil || cm.gameContext.game == nil {
		lua.pushboolean(L, false)
		lua.pushnumber(L, 1)
		return 2
	}
	pw := &cm.gameContext.game.physicsWorld
	dx, dy, _ := arg_xy_next(L, 2)
	filter := b2.QueryFilter{categoryBits = CollisionLayerSet_ToBits(cm.categoryLayers), maskBits = CollisionLayerSet_ToBits(cm.maskLayers)}
	moverCastOwner = cm
	f := mover_cast_all(cm, pw, {}, {dx, dy}, filter)
	moverCastOwner = nil
	lua.pushboolean(L, b32(f < 1))
	lua.pushnumber(L, lua.Number(f))
	return 2
}

// Script_RegisterMoverExtras: the node methods (on the node method table).
Script_RegisterMoverExtras :: proc(L: ^lua.State) {
	lua.pushcfunction(L, lua_character_get_platform_velocity)
	lua.setfield(L, -2, "character_get_platform_velocity")
	lua.pushcfunction(L, lua_character_get_time_since_floor)
	lua.setfield(L, -2, "character_get_time_since_floor")
	lua.pushcfunction(L, lua_character_was_on_floor)
	lua.setfield(L, -2, "character_was_on_floor")
	lua.pushcfunction(L, lua_character_test_move)
	lua.setfield(L, -2, "character_test_move")
}
