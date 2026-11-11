package engine

import "core:c"
import "core:math"
import b2 "vendor:box2d"

PhysicsWorld :: struct {
	worldId: b2.WorldId,
	gravity: [2]f32 `gui:"true" min:"-2000" max:"2000"`,
	subStepCount: int `gui:"true" min:"1" max:"16"`,
	lengthUnitsPerMeter: f32 `gui:"true" min:"1" max:"200"`,
	restitutionThreshold: f32 `gui:"true" min:"0" max:"500"`,
	hitEventThreshold: f32 `gui:"true" min:"0" max:"500"`,
	contactHertz: f32 `gui:"true" min:"1" max:"240"`,
	contactDampingRatio: f32 `gui:"true" min:"0" max:"20"`,
	maxContactPushSpeed: f32 `gui:"true" min:"0" max:"1000"`,
	maximumLinearSpeed: f32 `gui:"true" min:"10" max:"10000"`,
	enableSleep: bool `gui:"true"`,
	enableContinuous: bool `gui:"true"`,
	enableWarmStarting: bool `gui:"true"`,
	drawPhysicsDebug: bool `gui:"true"`,
	paused: bool `gui:"true"`,
	contactCounts: map[[2]rawptr]int,
	// The fixed step (physics_step.odin): steps per second (0: one per frame).
	physicsFps:     int `gui:"true" min:"0" max:"240"`,
	accumulator:    f32,
	alpha:          f32, // how far the frame is between the last two steps (0..1)
	stepDt:         f32, // the last step's time
	stepIndex:      u64, // steps so far
	stepsThisFrame: int,
	inStep:         bool, // running a step's work (on_physics_update, movers)
	// Collision exceptions (physics_queries.odin): node pairs that don't collide.
	exceptions:     map[[2]rawptr]bool,
}

PhysicsWorld_Init :: proc(pw: ^PhysicsWorld) {
	pw.lengthUnitsPerMeter = 32.0
	b2.SetLengthUnitsPerMeter(pw.lengthUnitsPerMeter)

	def := b2.DefaultWorldDef()
	def.gravity = {0.0, 300.0}
	pw.gravity = def.gravity
	pw.subStepCount = 4
	pw.restitutionThreshold = def.restitutionThreshold
	pw.hitEventThreshold = def.hitEventThreshold
	pw.contactHertz = def.contactHertz
	pw.contactDampingRatio = def.contactDampingRatio
	pw.maxContactPushSpeed = def.maxContactPushSpeed
	pw.maximumLinearSpeed = def.maximumLinearSpeed
	pw.enableSleep = def.enableSleep
	pw.enableContinuous = def.enableContinuous
	pw.enableWarmStarting = true
	pw.drawPhysicsDebug = true
	pw.paused = false
	pw.physicsFps = 60

	pw.worldId = b2.CreateWorld(def)
	b2.World_SetCustomFilterCallback(pw.worldId, Physics_CustomFilter, pw)
}

PhysicsWorld_SyncSettings :: proc(pw: ^PhysicsWorld) {
	if !b2.World_IsValid(pw.worldId) do return

	if pw.lengthUnitsPerMeter > 0.01 {
		b2.SetLengthUnitsPerMeter(pw.lengthUnitsPerMeter)
	}
	b2.World_SetGravity(pw.worldId, pw.gravity)
	b2.World_SetRestitutionThreshold(pw.worldId, pw.restitutionThreshold)
	b2.World_SetHitEventThreshold(pw.worldId, pw.hitEventThreshold)
	b2.World_SetContactTuning(pw.worldId, pw.contactHertz, pw.contactDampingRatio, pw.maxContactPushSpeed)
	b2.World_SetMaximumLinearSpeed(pw.worldId, pw.maximumLinearSpeed)
	b2.World_EnableSleeping(pw.worldId, pw.enableSleep)
	b2.World_EnableContinuous(pw.worldId, pw.enableContinuous)
	b2.World_EnableWarmStarting(pw.worldId, pw.enableWarmStarting)
}

PhysicsWorld_Step :: proc(pw: ^PhysicsWorld, deltaTime: f32, gameContext: ^GameContext) {
	if !b2.World_IsValid(pw.worldId) do return

	PhysicsWorld_SyncSettings(pw)

	if pw.paused || deltaTime <= 0.00001 {
		return
	}

	subSteps := c.int(max(pw.subStepCount, 1))
	b2.World_Step(pw.worldId, deltaTime, subSteps)
	Physics_RecordMoves(pw) // (the fixed step draws bodies between steps)

	// Dispatch Sensor Events (for AreaNode and sensor shapes)
	sensorEvents := b2.World_GetSensorEvents(pw.worldId)
	for i in 0..<sensorEvents.beginCount {
		ev := sensorEvents.beginEvents[i]
		if b2.Shape_IsValid(ev.sensorShapeId) && b2.Shape_IsValid(ev.visitorShapeId) {
			sensorBody := b2.Shape_GetBody(ev.sensorShapeId)
			visitorBody := b2.Shape_GetBody(ev.visitorShapeId)
			if b2.Body_IsValid(sensorBody) {
				sensorNode := cast(^Node)b2.Body_GetUserData(sensorBody)
				visitorNode := cast(^Node)b2.Body_GetUserData(visitorBody) if b2.Body_IsValid(visitorBody) else nil
				if sensorNode != nil {
					AreaNode_HandleEnter(sensorNode, visitorNode, gameContext)
				}
			}
		}
	}

	for i in 0..<sensorEvents.endCount {
		ev := sensorEvents.endEvents[i]
		if b2.Shape_IsValid(ev.sensorShapeId) {
			sensorBody := b2.Shape_GetBody(ev.sensorShapeId)
			visitorNode: ^Node = nil
			if b2.Shape_IsValid(ev.visitorShapeId) {
				visitorBody := b2.Shape_GetBody(ev.visitorShapeId)
				if b2.Body_IsValid(visitorBody) {
					visitorNode = cast(^Node)b2.Body_GetUserData(visitorBody)
				}
			}
			if b2.Body_IsValid(sensorBody) {
				sensorNode := cast(^Node)b2.Body_GetUserData(sensorBody)
				if sensorNode != nil {
					AreaNode_HandleExit(sensorNode, visitorNode, gameContext)
				}
			}
		}
	}

	// Contact begin/end -> "collision_started"/"collision_ended" on both bodies (once per body pair, even with multiple shapes).
	contactEvents := b2.World_GetContactEvents(pw.worldId)
	// (How fast new contacts came together: Box2D's hit events.)
	hitSpeeds := make(map[[2]b2.ShapeId]f32, allocator = context.temp_allocator)
	for i in 0..<contactEvents.hitCount {
		h := contactEvents.hitEvents[i]
		hitSpeeds[{h.shapeIdA, h.shapeIdB}] = h.approachSpeed
		hitSpeeds[{h.shapeIdB, h.shapeIdA}] = h.approachSpeed
	}
	for i in 0..<contactEvents.beginCount {
		ev := contactEvents.beginEvents[i]
		nodeA, nodeB := contact_nodes(ev.shapeIdA, ev.shapeIdB)
		if nodeA != nil && nodeB != nil && nodeA != nodeB {
			pair := ordered_node_pair(nodeA, nodeB)
			prev := pw.contactCounts[pair]
			pw.contactCounts[pair] = prev + 1
			if prev == 0 {
				ca, cb := Physics_ContactOf(ev.shapeIdA, ev.shapeIdB, ev.manifold, hitSpeeds[{ev.shapeIdA, ev.shapeIdB}])
				collisionContact = ca
				Node_NotifyCollision(nodeA, nodeB, true, gameContext)
				collisionContact = cb
				Node_NotifyCollision(nodeB, nodeA, true, gameContext)
				collisionContact = {}
			}
		} else {
			Node_NotifyCollision(nodeA, nodeB, true, gameContext)
			Node_NotifyCollision(nodeB, nodeA, true, gameContext)
		}
	}
	for i in 0..<contactEvents.endCount {
		ev := contactEvents.endEvents[i]
		nodeA, nodeB := contact_nodes(ev.shapeIdA, ev.shapeIdB)
		if nodeA != nil && nodeB != nil && nodeA != nodeB {
			pair := ordered_node_pair(nodeA, nodeB)
			prev := pw.contactCounts[pair]
			if prev <= 1 {
				delete_key(&pw.contactCounts, pair)
				Node_NotifyCollision(nodeA, nodeB, false, gameContext)
				Node_NotifyCollision(nodeB, nodeA, false, gameContext)
			} else {
				pw.contactCounts[pair] = prev - 1
			}
		} else {
			Node_NotifyCollision(nodeA, nodeB, false, gameContext)
			Node_NotifyCollision(nodeB, nodeA, false, gameContext)
		}
	}
}

@(private = "file")
ordered_node_pair :: proc(a, b: ^Node) -> [2]rawptr {
	ra := cast(rawptr)a
	rb := cast(rawptr)b
	if uintptr(ra) <= uintptr(rb) {
		return {ra, rb}
	}
	return {rb, ra}
}

PhysicsWorld_ClearNodeContacts :: proc(pw: ^PhysicsWorld, node: ^Node) {
	if pw != nil && node != nil do Physics_ForgetNode(pw, node) // (its collision exceptions)
	if pw == nil || node == nil || len(pw.contactCounts) == 0 do return
	raw := cast(rawptr)node
	toDelete := make([dynamic][2]rawptr, context.temp_allocator)
	for pair in pw.contactCounts {
		if pair[0] == raw || pair[1] == raw {
			append(&toDelete, pair)
		}
	}
	for pair in toDelete {
		delete_key(&pw.contactCounts, pair)
	}
}

@(private = "file")
contact_nodes :: proc(a, b: b2.ShapeId) -> (^Node, ^Node) {
	node_of :: proc(s: b2.ShapeId) -> ^Node {
		if !b2.Shape_IsValid(s) do return nil
		body := b2.Shape_GetBody(s)
		if !b2.Body_IsValid(body) do return nil
		n := cast(^Node)b2.Body_GetUserData(body)
		return n if Node_IsAlive(n) else nil
	}
	return node_of(a), node_of(b)
}

// Node_NotifyCollision raises collision_started/collision_ended on a body.
Node_NotifyCollision :: proc(node, other: ^Node, started: bool, gameContext: ^GameContext) {
	if node == nil do return
	subject: ^EventSubject
	switch node.typeId {
	case DynamicBodyNode:
		db := cast(^DynamicBodyNode)node
		subject = &db.onCollisionStarted if started else &db.onCollisionEnded
	case StaticBodyNode:
		sb := cast(^StaticBodyNode)node
		subject = &sb.onCollisionStarted if started else &sb.onCollisionEnded
	case KinematicBodyNode:
		kb := cast(^KinematicBodyNode)node
		subject = &kb.onCollisionStarted if started else &kb.onCollisionEnded
	case CharacterMoverNode:
		cm := cast(^CharacterMoverNode)node
		subject = &cm.onCollisionStarted if started else &cm.onCollisionEnded
	}
	if subject != nil do subject->notify(node, other, gameContext)
}

PhysicsWorld_Destroy :: proc(pw: ^PhysicsWorld) {
	delete(pw.contactCounts)
	pw.contactCounts = nil
	delete(pw.exceptions)
	pw.exceptions = nil
	if b2.World_IsValid(pw.worldId) {
		b2.DestroyWorld(pw.worldId)
		pw.worldId = b2.nullWorldId
	}
}

DegreesToRot :: proc(deg: f32) -> b2.Rot {
	return b2.MakeRot(math.to_radians(deg))
}

RotToDegrees :: proc(rot: b2.Rot) -> f32 {
	deg := math.to_degrees(b2.Rot_GetAngle(rot))
	for deg < 0 {
		deg += 360.0
	}
	for deg >= 360.0 {
		deg -= 360.0
	}
	return deg
}
