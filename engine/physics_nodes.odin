package engine

import "core:strings"
import "core:math"
import b2 "vendor:box2d"
import rl "vendor:raylib"

// ============================================================================
// 1. StaticBodyNode (StaticBody)
// ============================================================================
StaticBodyNode :: struct {
	using node: Node,
	bodyId: b2.BodyId,
	shapes: [dynamic]PhysicsShape,
	debugColor: rl.Color `gui:"true"`,
	// One way: bodies pass through from below and land on top (the
	// node's rotation turns "top"); e.g. jump-through platforms.
	oneWay: bool `gui:"true"`,
	oneWayApplied: bool,
	lastSyncedPos: [2]f32,
	lastSyncedRot: f32,
	onCollisionStarted: EventSubject, // "collision_started"(other node)
	onCollisionEnded: EventSubject,   // "collision_ended"(other node)
}

StaticBody :: StaticBodyNode

StaticBodyNode_Create :: proc(scene: ^Scene, name: string = "StaticBody", parent: ^Node = nil) -> ^StaticBodyNode {
	sb := CreateNode(scene.manager, StaticBodyNode)
	sb.name = strings.clone(name, sb.allocator) // owned: callers pass temp strings too
	sb.position = {640, 620}
	sb.debugColor = rl.Color{74, 222, 128, 255} // Green
	sb.shapes = make([dynamic]PhysicsShape, sb.allocator)
	sb.update = StaticBodyNode_Update
	sb.render = StaticBodyNode_Render
	sb.onDestroy = StaticBodyNode_Destroy
	InitializeSubject(&sb.onCollisionStarted, "collision_started", sb)
	InitializeSubject(&sb.onCollisionEnded, "collision_ended", sb)
	scene->addNode(sb, parent)
	return sb
}

// Physics_EnsureGlobalTransform initializes globalPosition, globalScale, and
// globalRotation from the node's parent chain when Node_SetGlobalPositions
// has not run yet (e.g. during scene setup or before the first frame).
Physics_EnsureGlobalTransform :: proc(node: ^Node) {
	if node == nil do return
	chain := make([dynamic]^Node, context.temp_allocator)
	for n := node; n != nil; n = n.parent do append(&chain, n)
	pos, scl, rot := [2]f32{0, 0}, [2]f32{1, 1}, f32(0)
	#reverse for n in chain {
		nScale := n.scale if n.scale != {} else [2]f32{1, 1}
		pos = pos + rotate_vec(n.position * scl, rot)
		scl *= nScale
		rot += n.rotation
	}
	node.globalPosition = pos
	node.globalScale = scl
	node.globalRotation = rot
}

StaticBodyNode_EnsureBody :: proc(sb: ^StaticBodyNode, gameContext: ^GameContext) {
	if b2.Body_IsValid(sb.bodyId) do return
	if gameContext == nil || gameContext.game == nil do return
	worldId := gameContext.game.physicsWorld.worldId
	if !b2.World_IsValid(worldId) do return

	Physics_EnsureGlobalTransform(sb)

	def := b2.DefaultBodyDef()
	def.type = .staticBody
	def.position = sb.globalPosition
	def.rotation = DegreesToRot(sb.globalRotation)
	def.userData = cast(rawptr)(cast(^Node)sb)
	sb.bodyId = b2.CreateBody(worldId, def)
	sb.lastSyncedPos = sb.globalPosition
	sb.lastSyncedRot = sb.globalRotation

	for &shape in sb.shapes {
		PhysicsShape_AttachToBody(&shape, sb.bodyId, cast(rawptr)(cast(^Node)sb), sb.globalScale)
	}
}

StaticBodyNode_AddShape :: proc(sb: ^StaticBodyNode, shape: PhysicsShape, gameContext: ^GameContext = nil) -> ^PhysicsShape {
	shape := shape
	if sb.oneWay do shape.enablePreSolveEvents = true
	if gameContext != nil {
		StaticBodyNode_EnsureBody(sb, gameContext)
	}
	append(&sb.shapes, shape)
	ptr := &sb.shapes[len(sb.shapes) - 1]
	if b2.Body_IsValid(sb.bodyId) {
		PhysicsShape_AttachToBody(ptr, sb.bodyId, cast(rawptr)(cast(^Node)sb), sb.globalScale)
	}
	return ptr
}

StaticBodyNode_RemoveShape :: proc(sb: ^StaticBodyNode, index: int) {
	if index < 0 || index >= len(sb.shapes) do return
	PhysicsShape_Destroy(&sb.shapes[index])
	ordered_remove(&sb.shapes, index)
}

StaticBodyNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	sb := cast(^StaticBodyNode)node
	if !sb.enabled {
		if b2.Body_IsValid(sb.bodyId) && b2.Body_IsEnabled(sb.bodyId) {
			b2.Body_Disable(sb.bodyId)
		}
		return
	}

	StaticBodyNode_EnsureBody(sb, gameContext)
	if !b2.Body_IsValid(sb.bodyId) do return
	if !b2.Body_IsEnabled(sb.bodyId) {
		b2.Body_Enable(sb.bodyId)
	}

	// Follow the node's world transform (moved directly, by a script, or by
	// a moving parent).
	moved := b2.Distance(sb.globalPosition, sb.lastSyncedPos) > 0.01 || abs(sb.globalRotation - sb.lastSyncedRot) > 0.01
	if moved {
		b2.Body_SetTransform(sb.bodyId, sb.globalPosition, DegreesToRot(sb.globalRotation))
		sb.lastSyncedPos = sb.globalPosition
		sb.lastSyncedRot = sb.globalRotation
	}
	if sb.oneWay != sb.oneWayApplied || (sb.oneWay && moved) {
		// Pre-solve events on its shapes; "top" turns with the node.
		for &shape in sb.shapes do shape.enablePreSolveEvents = sb.oneWay
		worldId := gameContext.game.physicsWorld.worldId if gameContext != nil && gameContext.game != nil else b2.WorldId{}
		Physics_SetOneWay(sb, sb.oneWay, rotate_vec({0, -1}, sb.globalRotation), worldId)
		sb.oneWayApplied = sb.oneWay
	}

	for &shape in sb.shapes {
		PhysicsShape_SyncToBox2D(&shape, sb.bodyId, cast(rawptr)node, sb.globalScale)
	}
}

StaticBodyNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	sb := cast(^StaticBodyNode)node
	if gameContext != nil && gameContext.game != nil && !gameContext.game.physicsWorld.drawPhysicsDebug {
		return
	}
	for &shape in sb.shapes {
		PhysicsShape_DrawDebug(&shape, sb.globalPosition, sb.globalRotation, sb.debugColor, sb.globalScale)
	}
}

StaticBodyNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	sb := cast(^StaticBodyNode)node
	Physics_SetOneWay(sb, false)
	if gameContext != nil && gameContext.game != nil {
		PhysicsWorld_ClearNodeContacts(&gameContext.game.physicsWorld, node)
	}
	DestroySubject(&sb.onCollisionStarted)
	DestroySubject(&sb.onCollisionEnded)
	if b2.Body_IsValid(sb.bodyId) {
		b2.DestroyBody(sb.bodyId)
		sb.bodyId = b2.nullBodyId
	}
}

// ============================================================================
// 2. DynamicBodyNode (DynamicBody)
// ============================================================================
DynamicBodyNode :: struct {
	using node: Node,
	bodyId: b2.BodyId,
	shapes: [dynamic]PhysicsShape,
	linearVelocity: [2]f32 `gui:"true" min:"-1000" max:"1000"`,
	angularVelocity: f32 `gui:"true" min:"-360" max:"360"`,
	linearDamping: f32 `gui:"true" min:"0" max:"20"`,
	angularDamping: f32 `gui:"true" min:"0" max:"20"`,
	gravityScale: f32 `gui:"true" min:"-5" max:"5"`,
	sleepThreshold: f32 `gui:"true" min:"0" max:"100"`,
	enableSleep: bool `gui:"true"`,
	isAwake: bool `gui:"true"`,
	fixedRotation: bool `gui:"true"`,
	isBullet: bool `gui:"true"`,
	allowFastRotation: bool `gui:"true"`,
	debugColor: rl.Color `gui:"true"`,
	lastSyncedPos: [2]f32,
	lastSyncedRot: f32,
	lastSyncedVel: [2]f32,
	lastSyncedAngVel: f32,
	syncedParams:     [5]f32, // damping, angular damping, gravity scale, sleep threshold, sleep enabled
	paramsSynced:     bool,
	onCollisionStarted: EventSubject, // "collision_started"(other node)
	onCollisionEnded: EventSubject,   // "collision_ended"(other node)
}

DynamicBody :: DynamicBodyNode

DynamicBodyNode_Create :: proc(scene: ^Scene, name: string = "DynamicBody", parent: ^Node = nil) -> ^DynamicBodyNode {
	db := CreateNode(scene.manager, DynamicBodyNode)
	db.name = strings.clone(name, db.allocator) // owned: callers pass temp strings too
	db.position = {640, 200}
	db.linearVelocity = {0, 0}
	db.angularVelocity = 0
	db.linearDamping = 0.05
	db.angularDamping = 0.05
	db.gravityScale = 1.0
	db.sleepThreshold = 1.5
	db.enableSleep = true
	db.isAwake = true
	db.fixedRotation = false
	db.isBullet = false
	db.allowFastRotation = false
	db.debugColor = rl.Color{96, 165, 250, 255} // Blue
	db.shapes = make([dynamic]PhysicsShape, db.allocator)
	db.update = DynamicBodyNode_Update
	db.render = DynamicBodyNode_Render
	db.onDestroy = DynamicBodyNode_Destroy
	InitializeSubject(&db.onCollisionStarted, "collision_started", db)
	InitializeSubject(&db.onCollisionEnded, "collision_ended", db)
	scene->addNode(db, parent)
	return db
}

DynamicBodyNode_EnsureBody :: proc(db: ^DynamicBodyNode, gameContext: ^GameContext) {
	if b2.Body_IsValid(db.bodyId) do return
	if gameContext == nil || gameContext.game == nil do return
	worldId := gameContext.game.physicsWorld.worldId
	if !b2.World_IsValid(worldId) do return

	Physics_EnsureGlobalTransform(db)

	def := b2.DefaultBodyDef()
	def.type = .dynamicBody
	def.position = db.globalPosition
	def.rotation = DegreesToRot(db.globalRotation)
	def.linearVelocity = db.linearVelocity
	def.angularVelocity = math.to_radians(db.angularVelocity)
	def.linearDamping = db.linearDamping
	def.angularDamping = db.angularDamping
	def.gravityScale = db.gravityScale
	def.sleepThreshold = db.sleepThreshold
	def.enableSleep = db.enableSleep
	def.isAwake = db.isAwake
	def.fixedRotation = db.fixedRotation
	def.isBullet = db.isBullet
	def.allowFastRotation = db.allowFastRotation
	def.userData = cast(rawptr)(cast(^Node)db)

	db.bodyId = b2.CreateBody(worldId, def)
	db.paramsSynced = false
	db.lastSyncedPos = db.globalPosition
	db.lastSyncedRot = db.globalRotation
	db.lastSyncedVel = db.linearVelocity
	db.lastSyncedAngVel = db.angularVelocity

	for &shape in db.shapes {
		PhysicsShape_AttachToBody(&shape, db.bodyId, cast(rawptr)(cast(^Node)db), db.globalScale)
	}
}

DynamicBodyNode_AddShape :: proc(db: ^DynamicBodyNode, shape: PhysicsShape, gameContext: ^GameContext = nil) -> ^PhysicsShape {
	if gameContext != nil {
		DynamicBodyNode_EnsureBody(db, gameContext)
	}
	append(&db.shapes, shape)
	ptr := &db.shapes[len(db.shapes) - 1]
	if b2.Body_IsValid(db.bodyId) {
		PhysicsShape_AttachToBody(ptr, db.bodyId, cast(rawptr)(cast(^Node)db), db.globalScale)
	}
	return ptr
}

DynamicBodyNode_RemoveShape :: proc(db: ^DynamicBodyNode, index: int) {
	if index < 0 || index >= len(db.shapes) do return
	PhysicsShape_Destroy(&db.shapes[index])
	ordered_remove(&db.shapes, index)
}

DynamicBodyNode_ApplyForce :: proc(db: ^DynamicBodyNode, force: [2]f32) {
	if b2.Body_IsValid(db.bodyId) {
		b2.Body_ApplyForceToCenter(db.bodyId, force, true)
	}
}

DynamicBodyNode_ApplyImpulse :: proc(db: ^DynamicBodyNode, impulse: [2]f32) {
	if b2.Body_IsValid(db.bodyId) {
		b2.Body_ApplyLinearImpulseToCenter(db.bodyId, impulse, true)
	}
}

DynamicBodyNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	db := cast(^DynamicBodyNode)node
	if !db.enabled {
		if b2.Body_IsValid(db.bodyId) && b2.Body_IsEnabled(db.bodyId) {
			b2.Body_Disable(db.bodyId)
		}
		return
	}

	DynamicBodyNode_EnsureBody(db, gameContext)
	if !b2.Body_IsValid(db.bodyId) do return
	if !b2.Body_IsEnabled(db.bodyId) {
		b2.Body_Enable(db.bodyId)
	}

	// If user manually moved node position/rotation via Inspector slider, teleport Box2D body
	if b2.Distance(db.globalPosition, db.lastSyncedPos) > 0.5 || abs(db.globalRotation - db.lastSyncedRot) > 0.5 {
		b2.Body_SetTransform(db.bodyId, db.globalPosition, DegreesToRot(db.globalRotation))
		b2.Body_SetAwake(db.bodyId, true)
	}

	// If user manually edited velocity in Inspector, apply it to Box2D body
	if b2.Distance(db.linearVelocity, db.lastSyncedVel) > 0.5 {
		b2.Body_SetLinearVelocity(db.bodyId, db.linearVelocity)
		b2.Body_SetAwake(db.bodyId, true)
	}
	if abs(db.angularVelocity - db.lastSyncedAngVel) > 0.5 {
		b2.Body_SetAngularVelocity(db.bodyId, math.to_radians(db.angularVelocity))
		b2.Body_SetAwake(db.bodyId, true)
	}

	// Sync dynamic parameters (only when they changed).
	params := [5]f32{db.linearDamping, db.angularDamping, db.gravityScale, db.sleepThreshold, 1 if db.enableSleep else 0}
	if !db.paramsSynced || params != db.syncedParams {
		b2.Body_SetLinearDamping(db.bodyId, db.linearDamping)
		b2.Body_SetAngularDamping(db.bodyId, db.angularDamping)
		b2.Body_SetGravityScale(db.bodyId, db.gravityScale)
		b2.Body_SetSleepThreshold(db.bodyId, db.sleepThreshold)
		b2.Body_EnableSleep(db.bodyId, db.enableSleep)
		db.syncedParams = params
		db.paramsSynced = true
	}
	if b2.Body_IsFixedRotation(db.bodyId) != db.fixedRotation {
		b2.Body_SetFixedRotation(db.bodyId, db.fixedRotation)
	}
	if b2.Body_IsBullet(db.bodyId) != db.isBullet {
		b2.Body_SetBullet(db.bodyId, db.isBullet)
	}

	for &shape in db.shapes {
		PhysicsShape_SyncToBox2D(&shape, db.bodyId, cast(rawptr)node, db.globalScale)
	}

	// Read back simulated state from Box2D (world space -> parent space)
	Physics_SetWorldTransform(db, b2.Body_GetPosition(db.bodyId), RotToDegrees(b2.Body_GetRotation(db.bodyId)))
	db.linearVelocity = b2.Body_GetLinearVelocity(db.bodyId)
	db.angularVelocity = math.to_degrees(b2.Body_GetAngularVelocity(db.bodyId))
	db.isAwake = b2.Body_IsAwake(db.bodyId)

	db.lastSyncedPos = db.globalPosition
	db.lastSyncedRot = db.globalRotation
	db.lastSyncedVel = db.linearVelocity
	db.lastSyncedAngVel = db.angularVelocity
}

DynamicBodyNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	db := cast(^DynamicBodyNode)node
	if gameContext != nil && gameContext.game != nil && !gameContext.game.physicsWorld.drawPhysicsDebug {
		return
	}
	for &shape in db.shapes {
		PhysicsShape_DrawDebug(&shape, db.globalPosition, db.globalRotation, db.debugColor, db.globalScale)
	}
}

DynamicBodyNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	db := cast(^DynamicBodyNode)node
	if gameContext != nil && gameContext.game != nil {
		PhysicsWorld_ClearNodeContacts(&gameContext.game.physicsWorld, node)
	}
	DestroySubject(&db.onCollisionStarted)
	DestroySubject(&db.onCollisionEnded)
	if b2.Body_IsValid(db.bodyId) {
		b2.DestroyBody(db.bodyId)
		db.bodyId = b2.nullBodyId
	}
}

// ============================================================================
// 2b. KinematicBodyNode (KinematicBody - velocity/script/path-driven body)
// ============================================================================
KinematicBodyNode :: struct {
	using node: Node,
	bodyId: b2.BodyId,
	shapes: [dynamic]PhysicsShape,
	linearVelocity: [2]f32 `gui:"true" min:"-1000" max:"1000"`,
	angularVelocity: f32 `gui:"true" min:"-360" max:"360"`,
	oneWay: bool `gui:"true"`,
	oneWayApplied: bool,
	debugColor: rl.Color `gui:"true"`,
	lastSyncedPos: [2]f32,
	lastSyncedRot: f32,
	lastSyncedVel: [2]f32,
	lastSyncedAngVel: f32,
	targetTransformActive: bool,
	onCollisionStarted: EventSubject, // "collision_started"(other node)
	onCollisionEnded: EventSubject,   // "collision_ended"(other node)
}

KinematicBody :: KinematicBodyNode

KinematicBodyNode_Create :: proc(scene: ^Scene, name: string = "KinematicBody", parent: ^Node = nil) -> ^KinematicBodyNode {
	kb := CreateNode(scene.manager, KinematicBodyNode)
	kb.name = strings.clone(name, kb.allocator)
	kb.position = {640, 420}
	kb.linearVelocity = {0, 0}
	kb.angularVelocity = 0
	kb.debugColor = rl.Color{56, 189, 248, 255} // Sky Blue / Cyan
	kb.shapes = make([dynamic]PhysicsShape, kb.allocator)
	kb.update = KinematicBodyNode_Update
	kb.render = KinematicBodyNode_Render
	kb.onDestroy = KinematicBodyNode_Destroy
	InitializeSubject(&kb.onCollisionStarted, "collision_started", kb)
	InitializeSubject(&kb.onCollisionEnded, "collision_ended", kb)
	scene->addNode(kb, parent)
	return kb
}

KinematicBodyNode_EnsureBody :: proc(kb: ^KinematicBodyNode, gameContext: ^GameContext) {
	if b2.Body_IsValid(kb.bodyId) do return
	if gameContext == nil || gameContext.game == nil do return
	worldId := gameContext.game.physicsWorld.worldId
	if !b2.World_IsValid(worldId) do return

	Physics_EnsureGlobalTransform(kb)

	def := b2.DefaultBodyDef()
	def.type = .kinematicBody
	def.position = kb.globalPosition
	def.rotation = DegreesToRot(kb.globalRotation)
	def.linearVelocity = kb.linearVelocity
	def.angularVelocity = math.to_radians(kb.angularVelocity)
	def.enableSleep = false
	def.isAwake = true
	def.userData = cast(rawptr)(cast(^Node)kb)

	kb.bodyId = b2.CreateBody(worldId, def)
	kb.lastSyncedPos = kb.globalPosition
	kb.lastSyncedRot = kb.globalRotation
	kb.lastSyncedVel = kb.linearVelocity
	kb.lastSyncedAngVel = kb.angularVelocity

	for &shape in kb.shapes {
		if kb.oneWay do shape.enablePreSolveEvents = true
		PhysicsShape_AttachToBody(&shape, kb.bodyId, cast(rawptr)(cast(^Node)kb), kb.globalScale)
	}
}

KinematicBodyNode_AddShape :: proc(kb: ^KinematicBodyNode, shape: PhysicsShape, gameContext: ^GameContext = nil) -> ^PhysicsShape {
	shape := shape
	if kb.oneWay do shape.enablePreSolveEvents = true
	if gameContext != nil {
		KinematicBodyNode_EnsureBody(kb, gameContext)
	}
	append(&kb.shapes, shape)
	ptr := &kb.shapes[len(kb.shapes) - 1]
	if b2.Body_IsValid(kb.bodyId) {
		PhysicsShape_AttachToBody(ptr, kb.bodyId, cast(rawptr)(cast(^Node)kb), kb.globalScale)
	}
	return ptr
}

KinematicBodyNode_RemoveShape :: proc(kb: ^KinematicBodyNode, index: int) {
	if index < 0 || index >= len(kb.shapes) do return
	PhysicsShape_Destroy(&kb.shapes[index])
	ordered_remove(&kb.shapes, index)
}

KinematicBodyNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	kb := cast(^KinematicBodyNode)node
	if !kb.enabled {
		if b2.Body_IsValid(kb.bodyId) && b2.Body_IsEnabled(kb.bodyId) {
			b2.Body_Disable(kb.bodyId)
		}
		return
	}

	KinematicBodyNode_EnsureBody(kb, gameContext)
	if !b2.Body_IsValid(kb.bodyId) do return
	if !b2.Body_IsEnabled(kb.bodyId) {
		b2.Body_Enable(kb.bodyId)
	}

	movedExternally := b2.Distance(kb.globalPosition, kb.lastSyncedPos) > 0.01 || abs(kb.globalRotation - kb.lastSyncedRot) > 0.01
	if movedExternally {
		if deltaTime > 0.00001 && b2.Distance(kb.globalPosition, kb.lastSyncedPos) <= 256.0 {
			b2.Body_SetTargetTransform(kb.bodyId, b2.Transform{p = kb.globalPosition, q = DegreesToRot(kb.globalRotation)}, deltaTime)
			kb.targetTransformActive = true
		} else {
			b2.Body_SetTransform(kb.bodyId, kb.globalPosition, DegreesToRot(kb.globalRotation))
			kb.targetTransformActive = false
		}
		kb.lastSyncedPos = kb.globalPosition
		kb.lastSyncedRot = kb.globalRotation
	} else {
		if kb.targetTransformActive {
			b2.Body_SetTransform(kb.bodyId, kb.globalPosition, DegreesToRot(kb.globalRotation))
			b2.Body_SetLinearVelocity(kb.bodyId, kb.linearVelocity)
			b2.Body_SetAngularVelocity(kb.bodyId, math.to_radians(kb.angularVelocity))
			kb.targetTransformActive = false
		} else {
			if b2.Distance(kb.linearVelocity, kb.lastSyncedVel) > 0.01 {
				b2.Body_SetLinearVelocity(kb.bodyId, kb.linearVelocity)
			}
			if abs(kb.angularVelocity - kb.lastSyncedAngVel) > 0.01 {
				b2.Body_SetAngularVelocity(kb.bodyId, math.to_radians(kb.angularVelocity))
			}
			Physics_SetWorldTransform(kb, b2.Body_GetPosition(kb.bodyId), RotToDegrees(b2.Body_GetRotation(kb.bodyId)))
			kb.linearVelocity = b2.Body_GetLinearVelocity(kb.bodyId)
			kb.angularVelocity = math.to_degrees(b2.Body_GetAngularVelocity(kb.bodyId))
			kb.lastSyncedPos = kb.globalPosition
			kb.lastSyncedRot = kb.globalRotation
			kb.lastSyncedVel = kb.linearVelocity
			kb.lastSyncedAngVel = kb.angularVelocity
		}
	}

	if kb.oneWay != kb.oneWayApplied || (kb.oneWay && (movedExternally || abs(kb.angularVelocity) > 0.01)) {
		for &shape in kb.shapes do shape.enablePreSolveEvents = kb.oneWay
		worldId := gameContext.game.physicsWorld.worldId if gameContext != nil && gameContext.game != nil else b2.WorldId{}
		Physics_SetOneWay(kb, kb.oneWay, rotate_vec({0, -1}, kb.globalRotation), worldId)
		kb.oneWayApplied = kb.oneWay
	}

	for &shape in kb.shapes {
		PhysicsShape_SyncToBox2D(&shape, kb.bodyId, cast(rawptr)node, kb.globalScale)
	}
}

KinematicBodyNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	kb := cast(^KinematicBodyNode)node
	if gameContext != nil && gameContext.game != nil && !gameContext.game.physicsWorld.drawPhysicsDebug {
		return
	}
	for &shape in kb.shapes {
		PhysicsShape_DrawDebug(&shape, kb.globalPosition, kb.globalRotation, kb.debugColor, kb.globalScale)
	}
}

KinematicBodyNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	kb := cast(^KinematicBodyNode)node
	Physics_SetOneWay(kb, false)
	if gameContext != nil && gameContext.game != nil {
		PhysicsWorld_ClearNodeContacts(&gameContext.game.physicsWorld, node)
	}
	DestroySubject(&kb.onCollisionStarted)
	DestroySubject(&kb.onCollisionEnded)
	if b2.Body_IsValid(kb.bodyId) {
		b2.DestroyBody(kb.bodyId)
		kb.bodyId = b2.nullBodyId
	}
}

// ============================================================================
// 3. CharacterMoverNode (CharacterMover - Box2D v3 Capsule Character Mover)
// ============================================================================
MAX_MOVER_PLANES :: 16

CharacterMoverNode :: struct {
	using node: Node,
	bodyId: b2.BodyId, // Optional kinematic proxy body so dynamic bodies & sensors also see the character
	shapes: [dynamic]PhysicsShape,
	radius: f32 `gui:"true" min:"2" max:"200"`,
	height: f32 `gui:"true" min:"2" max:"400"`,
	velocity: [2]f32 `gui:"true" min:"-1000" max:"1000" save:"false"`,
	targetSpeedX: f32 `gui:"true" min:"-600" max:"600" save:"false"`,
	maxSpeed: f32 `gui:"true" min:"10" max:"1000"`,
	acceleration: f32 `gui:"true" min:"10" max:"5000"`,
	jumpSpeed: f32 `gui:"true" min:"10" max:"1200"`,
	gravityScale: f32 `gui:"true" min:"0" max:"5"`,
	pushLimit: f32 `gui:"true" min:"0" max:"1000"`,
	clipVelocity: bool `gui:"true"`,
	enableKeyboardInput: bool `gui:"true"`,
	playerIndex: int `gui:"true" min:"0" max:"4"`,
	isGrounded: bool `gui:"true" save:"false"`,
	categoryLayers: CollisionLayerSet `gui:"true"`,
	maskLayers: CollisionLayerSet `gui:"true"`,
	debugColor: rl.Color `gui:"true"`,
	// Built-in: the node moves itself (maxSpeed, acceleration, jumpSpeed,
	// gravity, optional keyboard input). Script: like Godot's CharacterBody2D,
	// the script sets the velocity and calls character_move_and_slide().
	controlMode: CharacterMoverMode `gui:"true"`,
	isOnFloor: bool `save:"false"`,
	isOnWall: bool `save:"false"`,
	isOnCeiling: bool `save:"false"`,
	floorNormal: [2]f32 `save:"false"`,
	wallNormal: [2]f32 `save:"false"`,
	lastMotion: [2]f32 `save:"false"`,
	// Moving platforms: the node it stands on and where that was last frame;
	// the mover is carried by how far its floor moved (path followers,
	// animated or scripted bodies).
	floorNode:    ^Node,
	floorLastPos: [2]f32,
	floorShape:   b2.ShapeId, // (while gathering planes)
	floorPoint:   [2]f32 `save:"false"`, // where it touches its floor (world px)
	floorPointNext: [2]f32 `save:"false"`, // (while gathering planes)
	frameDelta: f32 `save:"false"`, // delta of the current frame (move_and_slide's default)
	collisionPlanes: [MAX_MOVER_PLANES]b2.CollisionPlane,
	planeCount: int,
	onCollisionStarted: EventSubject, // "collision_started"(other node)
	onCollisionEnded: EventSubject,   // "collision_ended"(other node)
}

CharacterMoverMode :: enum {
	BuiltIn, // moves itself each frame
	Script,  // moves only when the script calls character_move_and_slide()
}

CharacterMover :: CharacterMoverNode

CharacterMoverNode_Create :: proc(scene: ^Scene, name: string = "CharacterMover", parent: ^Node = nil) -> ^CharacterMoverNode {
	cm := CreateNode(scene.manager, CharacterMoverNode)
	cm.name = strings.clone(name, cm.allocator) // owned: callers pass temp strings too
	cm.position = {540, 300}
	cm.radius = 14.0
	cm.height = 28.0
	cm.velocity = {0, 0}
	cm.targetSpeedX = 0
	cm.maxSpeed = 240.0
	cm.acceleration = 1200.0
	cm.jumpSpeed = 320.0
	cm.gravityScale = 1.0
	cm.pushLimit = 500.0
	cm.clipVelocity = true

	// Check if the scene already has an input-enabled player mover.
	// If so, default this new mover to disabled input and playerIndex 0 (NPC/Enemy/Secondary).
	// (Slots of removed nodes are nil: issue #50.)
	is_player :: proc(n, self: ^Node) -> bool {
		if n == nil || n == self || n.typeId != typeid_of(CharacterMoverNode) do return false
		other := cast(^CharacterMoverNode)n
		return other.enableKeyboardInput && other.playerIndex > 0
	}
	hasPlayer := false
	if scene != nil && scene.manager != nil {
		for n in scene.manager.nodes do if is_player(n, &cm.node) {hasPlayer = true; break}
		if !hasPlayer do for n in scene.manager.addition do if is_player(n, &cm.node) {hasPlayer = true; break}
	}
	if hasPlayer {
		cm.enableKeyboardInput = false
		cm.playerIndex = 0
	} else {
		cm.enableKeyboardInput = true
		cm.playerIndex = 1
	}

	cm.isGrounded = false
	cm.categoryLayers = {CollisionLayer.Layer1}
	cm.maskLayers = DEFAULT_COLLISION_MASK
	cm.debugColor = rl.Color{250, 204, 21, 255} // Yellow/Gold
	cm.shapes = make([dynamic]PhysicsShape, cm.allocator)

	// Add default capsule shape representation
	capShape := MakeCapsulePhysicsShape(cm.radius, cm.height)
	append(&cm.shapes, capShape)

	cm.update = CharacterMoverNode_Update
	cm.render = CharacterMoverNode_Render
	cm.onDestroy = CharacterMoverNode_Destroy
	InitializeSubject(&cm.onCollisionStarted, "collision_started", cm)
	InitializeSubject(&cm.onCollisionEnded, "collision_ended", cm)
	scene->addNode(cm, parent)
	return cm
}

// CharacterMoverNode_ShapeWorldCapsule converts any PhysicsShape on a
// CharacterMoverNode into a world-space Box2D capsule for World_CollideMover
// and World_CastMover.
CharacterMoverNode_ShapeWorldCapsule :: proc(cm: ^CharacterMoverNode, s: ^PhysicsShape) -> b2.Capsule {
	r := max(cm.radius, 1.0)
	halfLen := max(cm.height, 0.0) * 0.5
	offset: [2]f32 = {0, 0}
	axis: [2]f32 = {0, 1}

	if s != nil {
		offset = s.offset
		switch s.type {
		case .Circle:
			r = max(s.radius, 1.0)
			halfLen = 0
		case .Capsule:
			r = max(s.radius, 1.0)
			halfLen = max(s.size[1], 0.0) * 0.5
		case .Box, .RoundedBox:
			w := max(s.size[0], 2.0)
			h := max(s.size[1], 2.0)
			if h >= w {
				r = w * 0.5
				halfLen = (h - w) * 0.5
				axis = {0, 1}
			} else {
				r = h * 0.5
				halfLen = (w - h) * 0.5
				axis = {1, 0}
			}
		case .Segment:
			mid := (s.point1 + s.point2) * 0.5
			offset += mid
			diff := s.point2 - s.point1
			segLen := math.sqrt(diff.x * diff.x + diff.y * diff.y)
			r = max(s.radius, 2.0)
			halfLen = segLen * 0.5
			if segLen > 0.001 {
				axis = diff / segLen
			}
		case .Polygon, .Chain:
			if s.vertexCount > 0 {
				minPt := s.vertices[0]
				maxPt := s.vertices[0]
				for i in 1..<min(s.vertexCount, len(s.vertices)) {
					v := s.vertices[i]
					if v.x < minPt.x do minPt.x = v.x
					if v.y < minPt.y do minPt.y = v.y
					if v.x > maxPt.x do maxPt.x = v.x
					if v.y > maxPt.y do maxPt.y = v.y
				}
				offset += (minPt + maxPt) * 0.5
				w := max(maxPt.x - minPt.x, 2.0)
				h := max(maxPt.y - minPt.y, 2.0)
				if h >= w {
					r = w * 0.5
					halfLen = (h - w) * 0.5
					axis = {0, 1}
				} else {
					r = h * 0.5
					halfLen = (w - h) * 0.5
					axis = {1, 0}
				}
			}
		}
	}

	worldPos := cm.globalPosition
	worldRot := cm.globalRotation
	sc := cm.globalScale
	if sc.x == 0 && sc.y == 0 {
		worldPos = cm.position
		worldRot = cm.rotation
		sc = cm.scale if cm.scale != {} else [2]f32{1, 1}
	}

	if abs(axis.y) >= abs(axis.x) {
		r *= abs(sc.x)
		halfLen *= abs(sc.y)
	} else {
		r *= abs(sc.y)
		halfLen *= abs(sc.x)
	}
	offset *= sc
	rot := DegreesToRot(worldRot)
	dir := b2.RotateVector(rot, b2.Vec2{axis.x * halfLen, axis.y * halfLen})
	center := worldPos + b2.RotateVector(rot, offset)
	return b2.Capsule{
		center1 = center - dir,
		center2 = center + dir,
		radius  = max(r, 1.0),
	}
}

CharacterMoverNode_GetWorldCapsule :: proc(cm: ^CharacterMoverNode) -> b2.Capsule {
	if len(cm.shapes) > 0 {
		cap := CharacterMoverNode_ShapeWorldCapsule(cm, &cm.shapes[0])
		cm.radius = cap.radius
		segDiff := cap.center2 - cap.center1
		cm.height = math.sqrt(segDiff.x * segDiff.x + segDiff.y * segDiff.y)
		return cap
	}
	return CharacterMoverNode_ShapeWorldCapsule(cm, nil)
}

@(private = "file")
Mover_Cast :: struct {
	self:        b2.BodyId,
	mover:       b2.ShapeProxy,
	translation: [2]f32,
	fraction:    f32,
}

// character_mover_cast: how far (0..1) a capsule moves along `translation`
// before a solid shape - Box2D's World_CastMover step for step (each
// shape cast with canEncroach; shapes it starts inside ignored), but past
// sensors (it stopped at Areas, #173) and the mover's own proxy body.
character_mover_cast :: proc(worldId: b2.WorldId, capsule: b2.Capsule, translation: [2]f32, filter: b2.QueryFilter, self: b2.BodyId) -> f32 {
	pts := [2]b2.Vec2{capsule.center1, capsule.center2}
	mc := Mover_Cast{self = self, mover = b2.MakeProxy(pts[:], capsule.radius), translation = translation, fraction = 1}
	r := capsule.radius
	lo := [2]f32{min(capsule.center1.x, capsule.center2.x) - r, min(capsule.center1.y, capsule.center2.y) - r}
	hi := [2]f32{max(capsule.center1.x, capsule.center2.x) + r, max(capsule.center1.y, capsule.center2.y) + r}
	box := b2.AABB{lowerBound = {min(lo.x, lo.x + translation.x), min(lo.y, lo.y + translation.y)}, upperBound = {max(hi.x, hi.x + translation.x), max(hi.y, hi.y + translation.y)}}
	callback :: proc "c" (shapeId: b2.ShapeId, ctx: rawptr) -> bool {
		mc := cast(^Mover_Cast)ctx
		if b2.Shape_IsSensor(shapeId) do return true // (a trigger: no obstacle)
		body := b2.Shape_GetBody(shapeId)
		if b2.Body_IsValid(mc.self) && body == mc.self do return true
		// A one-way platform stops only a move into it from its open side.
		if side, oneWay := Physics_OneWaySide(shapeId); oneWay && mc.translation.x * side.x + mc.translation.y * side.y >= 0 do return true
		proxy, ok := shape_proxy(shapeId)
		if !ok do return true
		out := b2.ShapeCast({
			proxyA = proxy, transformA = b2.Body_GetTransform(body),
			proxyB = mc.mover, transformB = b2.Transform{q = b2.Rot{c = 1}},
			translationB = mc.translation, maxFraction = mc.fraction, canEncroach = true,
		})
		if out.fraction == 0 do return true // (overlapping at the start: ignored, as the mover cast does)
		if out.hit && out.fraction < mc.fraction do mc.fraction = out.fraction
		return true
	}
	_ = b2.World_OverlapAABB(worldId, box, filter, callback, &mc)
	return mc.fraction
}

// shape_proxy: a shape's distance proxy in its body's frame.
@(private = "file")
shape_proxy :: proc "contextless" (shapeId: b2.ShapeId) -> (b2.ShapeProxy, bool) {
	#partial switch b2.Shape_GetType(shapeId) {
	case .circleShape:
		c := b2.Shape_GetCircle(shapeId)
		p := [1]b2.Vec2{c.center}
		return b2.MakeProxy(p[:], c.radius), true
	case .capsuleShape:
		c := b2.Shape_GetCapsule(shapeId)
		p := [2]b2.Vec2{c.center1, c.center2}
		return b2.MakeProxy(p[:], c.radius), true
	case .segmentShape:
		sg := b2.Shape_GetSegment(shapeId)
		p := [2]b2.Vec2{sg.point1, sg.point2}
		return b2.MakeProxy(p[:], 0), true
	case .chainSegmentShape:
		cs := b2.Shape_GetChainSegment(shapeId)
		p := [2]b2.Vec2{cs.segment.point1, cs.segment.point2}
		return b2.MakeProxy(p[:], 0), true
	case .polygonShape:
		poly := b2.Shape_GetPolygon(shapeId)
		return b2.MakeProxy(poly.vertices[:poly.count], poly.radius), true
	}
	return {}, false
}

CharacterMover_PlaneResultCallback :: proc "c" (shapeId: b2.ShapeId, planeResult: ^b2.PlaneResult, ctx: rawptr) -> bool {
	if planeResult == nil || !planeResult.hit || ctx == nil {
		return true
	}
	cm := cast(^CharacterMoverNode)ctx

	// Ignore self kinematic proxy body if present
	if b2.Shape_IsValid(shapeId) && b2.Body_IsValid(cm.bodyId) {
		if b2.Shape_GetBody(shapeId) == cm.bodyId {
			return true
		}
	}
	// Ignore sensors in mover plane solver
	if b2.Shape_IsValid(shapeId) && b2.Shape_IsSensor(shapeId) {
		return true
	}
	// A one-way platform (#219) holds the mover only from its open side
	// (the plane pushes that way) and not while it moves out through it.
	if side, oneWay := Physics_OneWaySide(shapeId); oneWay {
		n := planeResult.plane.normal
		if n.x * side.x + n.y * side.y <= 0.5 do return true
		if cm.velocity.x * side.x + cm.velocity.y * side.y > 0 do return true
	}

	if cm.planeCount < MAX_MOVER_PLANES {
		pushLim := cm.pushLimit if cm.pushLimit > 0 else max(f32)
		cm.collisionPlanes[cm.planeCount] = b2.CollisionPlane{
			plane        = planeResult.plane,
			pushLimit    = pushLim,
			push         = 0,
			clipVelocity = cm.clipVelocity,
		}
		cm.planeCount += 1
		if planeResult.plane.normal.y < -0.5 { // a floor (normals point up: -y)
			cm.floorShape = shapeId
			cm.floorPointNext = b2.Body_GetWorldPoint(b2.Shape_GetBody(shapeId), planeResult.point) // (given on the shape's body)
		}
	}
	return true
}

CharacterMoverNode_EnsureProxyBody :: proc(cm: ^CharacterMoverNode, worldId: b2.WorldId) {
	if b2.Body_IsValid(cm.bodyId) || !b2.World_IsValid(worldId) do return

	Physics_EnsureGlobalTransform(cm)

	def := b2.DefaultBodyDef()
	def.type = .kinematicBody
	def.position = cm.globalPosition
	def.rotation = DegreesToRot(cm.globalRotation)
	def.userData = cast(rawptr)(cast(^Node)cm)
	cm.bodyId = b2.CreateBody(worldId, def)

	for &shape in cm.shapes {
		shape.categoryLayers = cm.categoryLayers
		shape.maskLayers = cm.maskLayers
		PhysicsShape_AttachToBody(&shape, cm.bodyId, cast(rawptr)(cast(^Node)cm), cm.globalScale)
	}
}

CharacterMoverNode_AddShape :: proc(cm: ^CharacterMoverNode, shape: PhysicsShape, gameContext: ^GameContext = nil) -> ^PhysicsShape {
	append(&cm.shapes, shape)
	ptr := &cm.shapes[len(cm.shapes) - 1]
	if b2.Body_IsValid(cm.bodyId) {
		PhysicsShape_AttachToBody(ptr, cm.bodyId, cast(rawptr)(cast(^Node)cm), cm.globalScale)
	}
	return ptr
}

CharacterMoverNode_RemoveShape :: proc(cm: ^CharacterMoverNode, index: int) {
	if index < 0 || index >= len(cm.shapes) do return
	PhysicsShape_Destroy(&cm.shapes[index])
	ordered_remove(&cm.shapes, index)
}

CharacterMoverNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	cm := cast(^CharacterMoverNode)node
	if !cm.enabled {
		if b2.Body_IsValid(cm.bodyId) && b2.Body_IsEnabled(cm.bodyId) {
			b2.Body_Disable(cm.bodyId)
		}
		return
	}
	if deltaTime <= 0.00001 do return
	if gameContext == nil || gameContext.game == nil do return

	pw := &gameContext.game.physicsWorld
	if !b2.World_IsValid(pw.worldId) || pw.paused do return

	CharacterMoverNode_EnsureProxyBody(cm, pw.worldId)
	if b2.Body_IsValid(cm.bodyId) && !b2.Body_IsEnabled(cm.bodyId) {
		b2.Body_Enable(cm.bodyId)
	}

	cm.frameDelta = deltaTime
	// Script mode: the script moves the node (character_move_and_slide).
	if cm.controlMode == .Script do return

	// If a script is attached and no player is assigned, the script controls this node (e.g. enemy/AI);
	// do not process built-in player keyboard actions.
	if cm.node.scriptInstance != nil && cm.playerIndex == 0 do return

	// Query Logical Actions via the Two-Tier Input System (MoveLeft, MoveRight, Jump)
	desiredVX := cm.targetSpeedX
	if cm.enableKeyboardInput && cm.playerIndex > 0 && cm.playerIndex <= MAX_PLAYERS {
		moveAxis := GetPlayerActionAxis(gameContext, .MoveLeft, .MoveRight, cm.playerIndex)
		if moveAxis != 0.0 {
			desiredVX = moveAxis * cm.maxSpeed
		}
		if IsPlayerActionPressed(gameContext, .Jump, cm.playerIndex) && cm.isGrounded {
			cm.velocity.y = -cm.jumpSpeed
			cm.isGrounded = false
		}
	}

	// Horizontal acceleration toward desiredVX
	diffX := desiredVX - cm.velocity.x
	maxDeltaV := cm.acceleration * deltaTime
	if abs(diffX) <= maxDeltaV {
		cm.velocity.x = desiredVX
	} else {
		cm.velocity.x += math.copy_sign(maxDeltaV, diffX)
	}

	// Apply world gravity
	cm.velocity += pw.gravity * cm.gravityScale * deltaTime

	CharacterMoverNode_MoveAndSlide(cm, gameContext, deltaTime)
}

// CharacterMoverNode_Gravity: the world's gravity scaled by gravityScale.
CharacterMoverNode_Gravity :: proc(cm: ^CharacterMoverNode, gameContext: ^GameContext) -> [2]f32 {
	if gameContext == nil || gameContext.game == nil do return {}
	return gameContext.game.physicsWorld.gravity * cm.gravityScale
}

// CharacterMoverNode_MoveAndSlide moves the capsule by velocity * dt,
// sliding along whatever it touches (the velocity loses the part going into
// surfaces when clipVelocity is on), and updates the floor / wall / ceiling
// state. Returns true if it touched anything.
CharacterMoverNode_MoveAndSlide :: proc(cm: ^CharacterMoverNode, gameContext: ^GameContext, deltaTime: f32) -> bool {
	if gameContext == nil || gameContext.game == nil || deltaTime <= 0.00001 do return false
	pw := &gameContext.game.physicsWorld
	if !b2.World_IsValid(pw.worldId) || pw.paused do return false
	CharacterMoverNode_EnsureProxyBody(cm, pw.worldId)

	// Build query filter from CharacterMover's collision layers
	qFilter := b2.QueryFilter{
		categoryBits = CollisionLayerSet_ToBits(cm.categoryLayers),
		maskBits     = CollisionLayerSet_ToBits(cm.maskLayers),
	}

	// 0. Ride a moving floor: move with it by how far it moved since last frame.
	if cm.floorNode != nil {
		if Node_IsAlive(cm.floorNode) && !cm.floorNode.removing {
			carry := cm.floorNode.globalPosition - cm.floorLastPos
			if carry != {} && carry.x * carry.x + carry.y * carry.y < 256 * 256 { // (not a teleport)
				Physics_SetWorldTransform(cm, cm.globalPosition + carry, cm.globalRotation)
			}
		} else {
			cm.floorNode = nil
		}
	}

	// 1. Gather collision planes around the mover shapes using Box2D v3 World_CollideMover
	cm.planeCount = 0
	cm.floorShape = {}
	if len(cm.shapes) == 0 {
		moverCapsule := CharacterMoverNode_GetWorldCapsule(cm)
		b2.World_CollideMover(pw.worldId, moverCapsule, qFilter, CharacterMover_PlaneResultCallback, cast(rawptr)cm)
	} else {
		for &s in cm.shapes {
			if s.isSensor do continue
			cap := CharacterMoverNode_ShapeWorldCapsule(cm, &s)
			b2.World_CollideMover(pw.worldId, cap, qFilter, CharacterMover_PlaneResultCallback, cast(rawptr)cm)
		}
	}

	// 2. Solve collision planes for target translation using Box2D v3 SolvePlanes
	targetDelta := cm.velocity * deltaTime
	planesSlice := cm.collisionPlanes[:cm.planeCount]
	solverResult := b2.SolvePlanes(targetDelta, planesSlice)

	// 3. Contact state from the plane normals (screen coordinates, +Y down:
	// a floor's normal points up, y < -0.5) and velocity clipping.
	cm.isOnFloor, cm.isOnWall, cm.isOnCeiling = false, false, false
	cm.floorNormal, cm.wallNormal = {}, {}
	for i in 0..<cm.planeCount {
		n := cm.collisionPlanes[i].plane.normal
		switch {
		case n.y < -0.5:
			cm.isOnFloor = true
			cm.floorNormal = n
		case n.y > 0.5:
			cm.isOnCeiling = true
		case:
			cm.isOnWall = true
			cm.wallNormal = n
		}
	}
	cm.isGrounded = cm.isOnFloor
	// The floor it stands on now (for the carry next frame).
	cm.floorNode = nil
	if cm.isOnFloor && b2.Shape_IsValid(cm.floorShape) {
		if n := cast(^Node)b2.Body_GetUserData(b2.Shape_GetBody(cm.floorShape)); n != nil && Node_IsAlive(n) {
			cm.floorNode = n
			cm.floorLastPos = n.globalPosition
			cm.floorPoint = cm.floorPointNext
		}
	}
	if cm.planeCount > 0 && cm.clipVelocity {
		cm.velocity = b2.ClipVector(cm.velocity, planesSlice)
	}

	// 4. Cast mover along solved translation to prevent tunneling - past
	// sensors (Areas are triggers: #173) and its own proxy body.
	fraction: f32 = 1.0
	if len(cm.shapes) == 0 {
		moverCapsule := CharacterMoverNode_GetWorldCapsule(cm)
		fraction = character_mover_cast(pw.worldId, moverCapsule, solverResult.translation, qFilter, cm.bodyId)
	} else {
		for &s in cm.shapes {
			if s.isSensor do continue
			cap := CharacterMoverNode_ShapeWorldCapsule(cm, &s)
			f := character_mover_cast(pw.worldId, cap, solverResult.translation, qFilter, cm.bodyId)
			if f < fraction do fraction = f
		}
	}
	delta := solverResult.translation * fraction
	cm.lastMotion = delta
	Physics_SetWorldTransform(cm, cm.globalPosition + delta, cm.globalRotation)

	// Sync kinematic proxy body so sensors (AreaNode) and dynamic bodies interact with the mover
	if b2.Body_IsValid(cm.bodyId) {
		b2.Body_SetTargetTransform(cm.bodyId, b2.Transform{p = cm.globalPosition, q = DegreesToRot(cm.globalRotation)}, deltaTime)
		for &shape in cm.shapes {
			shape.categoryLayers = cm.categoryLayers
			shape.maskLayers = cm.maskLayers
			PhysicsShape_SyncToBox2D(&shape, cm.bodyId, cast(rawptr)(cast(^Node)cm), cm.globalScale)
		}
	}
	return cm.planeCount > 0
}

CharacterMoverNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	cm := cast(^CharacterMoverNode)node
	if gameContext != nil && gameContext.game != nil && !gameContext.game.physicsWorld.drawPhysicsDebug {
		return
	}
	if len(cm.shapes) > 0 {
		for &shape in cm.shapes {
			PhysicsShape_DrawDebug(&shape, cm.globalPosition, cm.globalRotation, cm.debugColor, cm.globalScale)
		}
		return
	}
	cap := CharacterMoverNode_GetWorldCapsule(cm)
	fillColor := rl.Color{cm.debugColor.r, cm.debugColor.g, cm.debugColor.b, 70}
	rl.DrawCircleV(cap.center1, cap.radius, fillColor)
	rl.DrawCircleV(cap.center2, cap.radius, fillColor)
	rl.DrawLineEx(cap.center1, cap.center2, cap.radius * 2.0, fillColor)
	rl.DrawCircleLinesV(cap.center1, cap.radius, cm.debugColor)
	rl.DrawCircleLinesV(cap.center2, cap.radius, cm.debugColor)
	rot := DegreesToRot(cm.rotation)
	perp := b2.RotateVector(rot, b2.Vec2{cap.radius, 0})
	rl.DrawLineV(cap.center1 + perp, cap.center2 + perp, cm.debugColor)
	rl.DrawLineV(cap.center1 - perp, cap.center2 - perp, cm.debugColor)
}

CharacterMoverNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	cm := cast(^CharacterMoverNode)node
	if gameContext != nil && gameContext.game != nil {
		PhysicsWorld_ClearNodeContacts(&gameContext.game.physicsWorld, node)
	}
	DestroySubject(&cm.onCollisionStarted)
	DestroySubject(&cm.onCollisionEnded)
	if b2.Body_IsValid(cm.bodyId) {
		b2.DestroyBody(cm.bodyId)
		cm.bodyId = b2.nullBodyId
	}
}

// ============================================================================
// 4. AreaNode (Area - Sensor that detects bodies entering and leaving)
// ============================================================================
AreaNode :: struct {
	using node: Node,
	bodyId: b2.BodyId,
	shapes: [dynamic]PhysicsShape,
	// Reports bodies entering / leaving (false: no body_entered / body_exited,
	// no overlaps - a hitbox that only others react to). It stays a shape
	// raycasts and queries can find.
	monitoring: bool `gui:"true"`,
	monitoringApplied: bool,
	overlappingNodes: [dynamic]^Node,
	overlappingCounts: [dynamic]int,
	overlapCount: int `gui:"true" min:"0" max:"100" save:"false"`,
	hasOverlaps: bool `gui:"true" save:"false"`,
	onBodyEntered: EventSubject,
	onBodyExited: EventSubject,
	debugColor: rl.Color `gui:"true"`,
	activeColor: rl.Color `gui:"true"`,
	lastSyncedPos: [2]f32,
	lastSyncedRot: f32,
}

Area :: AreaNode

AreaNode_Create :: proc(scene: ^Scene, name: string = "Area", parent: ^Node = nil) -> ^AreaNode {
	area := CreateNode(scene.manager, AreaNode)
	area.name = strings.clone(name, area.allocator) // owned: callers pass temp strings too
	area.position = {640, 460}
	area.monitoring = true
	area.debugColor = rl.Color{168, 85, 247, 255}  // Purple
	area.activeColor = rl.Color{236, 72, 153, 255} // Pink when overlapping
	area.shapes = make([dynamic]PhysicsShape, area.allocator)
	area.overlappingNodes = make([dynamic]^Node, area.allocator)
	area.overlappingCounts = make([dynamic]int, area.allocator)
	InitializeSubject(&area.onBodyEntered, "body_entered", area)
	InitializeSubject(&area.onBodyExited, "body_exited", area)
	area.update = AreaNode_Update
	area.render = AreaNode_Render
	area.onDestroy = AreaNode_Destroy
	scene->addNode(area, parent)
	return area
}

AreaNode_SetMonitoring :: proc(area: ^AreaNode, enabled: bool) {
	if area == nil do return
	area.monitoring = enabled
	area_apply_monitoring(area)
}

// area_apply_monitoring: the shapes' sensor events follow `monitoring`.
// Turned off, the overlaps are forgotten (no body_exited for them); turned
// on, the bodies already inside enter now (Box2D keeps tracking overlaps
// without events, so it won't report them).
@(private = "file")
area_apply_monitoring :: proc(area: ^AreaNode) {
	if !area.monitoring {
		clear(&area.overlappingNodes)
		clear(&area.overlappingCounts)
		area.overlapCount = 0
		area.hasOverlaps = false
	}
	for &shape in area.shapes {
		shape.enableSensorEvents = area.monitoring
		if !b2.Shape_IsValid(shape.shapeId) do continue
		b2.Shape_EnableSensorEvents(shape.shapeId, area.monitoring)
		if !area.monitoring || !area.enabled do continue
		capacity := b2.Shape_GetSensorCapacity(shape.shapeId)
		if capacity <= 0 do continue
		overlaps := make([]b2.ShapeId, capacity, context.temp_allocator)
		n := b2.Shape_GetSensorOverlaps(shape.shapeId, raw_data(overlaps), capacity)
		for visitor in overlaps[:n] {
			if !b2.Shape_IsValid(visitor) do continue
			body := b2.Shape_GetBody(visitor)
			if b2.Body_IsValid(body) do AreaNode_HandleEnter(area, cast(^Node)b2.Body_GetUserData(body), area.gameContext)
		}
	}
	area.monitoringApplied = area.monitoring
}

AreaNode_IsMonitoring :: proc(area: ^AreaNode) -> bool {
	if area == nil do return false
	return area.monitoring
}

AreaNode_EnsureBody :: proc(area: ^AreaNode, gameContext: ^GameContext) {
	if b2.Body_IsValid(area.bodyId) do return
	if gameContext == nil || gameContext.game == nil do return
	worldId := gameContext.game.physicsWorld.worldId
	if !b2.World_IsValid(worldId) do return

	Physics_EnsureGlobalTransform(area)

	def := b2.DefaultBodyDef()
	def.type = .staticBody
	def.position = area.globalPosition
	def.rotation = DegreesToRot(area.globalRotation)
	def.userData = cast(rawptr)(cast(^Node)area)
	area.bodyId = b2.CreateBody(worldId, def)
	area.lastSyncedPos = area.globalPosition
	area.lastSyncedRot = area.globalRotation

	for &shape in area.shapes {
		shape.isSensor = true
		shape.enableSensorEvents = area.monitoring
		PhysicsShape_AttachToBody(&shape, area.bodyId, cast(rawptr)(cast(^Node)area), area.globalScale)
	}
	area.monitoringApplied = area.monitoring
	if !area.enabled do b2.Body_Disable(area.bodyId)
}

AreaNode_AddShape :: proc(area: ^AreaNode, shape: PhysicsShape, gameContext: ^GameContext = nil) -> ^PhysicsShape {
	s := shape
	s.isSensor = true
	s.enableSensorEvents = area.monitoring
	if gameContext != nil {
		AreaNode_EnsureBody(area, gameContext)
	}
	append(&area.shapes, s)
	ptr := &area.shapes[len(area.shapes) - 1]
	if b2.Body_IsValid(area.bodyId) {
		PhysicsShape_AttachToBody(ptr, area.bodyId, cast(rawptr)(cast(^Node)area), area.globalScale)
	}
	return ptr
}

AreaNode_RemoveShape :: proc(area: ^AreaNode, index: int) {
	if index < 0 || index >= len(area.shapes) do return
	PhysicsShape_Destroy(&area.shapes[index])
	ordered_remove(&area.shapes, index)
}

AreaNode_HandleEnter :: proc(sensorNode: ^Node, visitorNode_in: ^Node, gameContext: ^GameContext) {
	if sensorNode == nil || !Node_IsAlive(sensorNode) || sensorNode.typeId != AreaNode do return
	visitorNode := visitorNode_in if Node_IsAlive(visitorNode_in) else nil
	// An area (or a body) destroyed this frame is only queued for removal
	// until the frame ends: it doesn't report entering any more (a coin
	// destroyed under the player was still collected).
	if sensorNode.removing || (visitorNode != nil && visitorNode.removing) do return

	area := cast(^AreaNode)sensorNode
	if !area.enabled || !area.monitoring do return

	notify := true
	if visitorNode != nil {
		alreadyPresent := false
		for n, i in area.overlappingNodes {
			if n == visitorNode {
				alreadyPresent = true
				if i < len(area.overlappingCounts) {
					area.overlappingCounts[i] += 1
				}
				notify = false
				break
			}
		}
		if !alreadyPresent {
			append(&area.overlappingNodes, visitorNode)
			append(&area.overlappingCounts, 1)
		}
	}
	area.overlapCount = len(area.overlappingNodes)
	area.hasOverlaps = area.overlapCount > 0
	if notify {
		area.onBodyEntered->notify(area, visitorNode, gameContext)
	}
}

AreaNode_HandleExit :: proc(sensorNode: ^Node, visitorNode_in: ^Node, gameContext: ^GameContext) {
	if sensorNode == nil || !Node_IsAlive(sensorNode) || sensorNode.typeId != AreaNode do return
	visitorNode := visitorNode_in if Node_IsAlive(visitorNode_in) else nil

	area := cast(^AreaNode)sensorNode
	if !area.enabled || !area.monitoring do return

	notify := false
	if visitorNode != nil {
		for n, i in area.overlappingNodes {
			if n == visitorNode {
				cnt := area.overlappingCounts[i] if i < len(area.overlappingCounts) else 1
				if cnt <= 1 {
					unordered_remove(&area.overlappingNodes, i)
					if i < len(area.overlappingCounts) {
						unordered_remove(&area.overlappingCounts, i)
					}
					notify = true
				} else if i < len(area.overlappingCounts) {
					area.overlappingCounts[i] = cnt - 1
				}
				break
			}
		}
	} else {
		notify = true
	}
	area.overlapCount = len(area.overlappingNodes)
	area.hasOverlaps = area.overlapCount > 0
	if notify {
		area.onBodyExited->notify(area, visitorNode, gameContext)
	}
}

AreaNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	area := cast(^AreaNode)node
	// Visitors destroyed while overlapping leave the list (and report exit).
	for i := len(area.overlappingNodes) - 1; i >= 0; i -= 1 {
		if !Node_IsAlive(area.overlappingNodes[i]) {
			unordered_remove(&area.overlappingNodes, i)
			if i < len(area.overlappingCounts) {
				unordered_remove(&area.overlappingCounts, i)
			}
			area.onBodyExited->notify(area, nil, gameContext)
		}
	}
	area.overlapCount = len(area.overlappingNodes)
	area.hasOverlaps = area.overlapCount > 0
	if area.monitoring != area.monitoringApplied do area_apply_monitoring(area) // (set from the Inspector or Lua)
	if !area.enabled {
		if b2.Body_IsValid(area.bodyId) && b2.Body_IsEnabled(area.bodyId) {
			b2.Body_Disable(area.bodyId)
		}
		return
	}

	AreaNode_EnsureBody(area, gameContext)
	if !b2.Body_IsValid(area.bodyId) do return
	if !b2.Body_IsEnabled(area.bodyId) {
		b2.Body_Enable(area.bodyId)
	}

	if b2.Distance(area.globalPosition, area.lastSyncedPos) > 0.01 || abs(area.globalRotation - area.lastSyncedRot) > 0.01 {
		b2.Body_SetTransform(area.bodyId, area.globalPosition, DegreesToRot(area.globalRotation))
		area.lastSyncedPos = area.globalPosition
		area.lastSyncedRot = area.globalRotation
	}

	for &shape in area.shapes {
		shape.isSensor = true
		shape.enableSensorEvents = true
		PhysicsShape_SyncToBox2D(&shape, area.bodyId, cast(rawptr)node, area.globalScale)
	}

	area.overlapCount = len(area.overlappingNodes)
	area.hasOverlaps = area.overlapCount > 0
}

AreaNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	area := cast(^AreaNode)node
	if gameContext != nil && gameContext.game != nil && !gameContext.game.physicsWorld.drawPhysicsDebug {
		return
	}
	color := area.activeColor if area.hasOverlaps else area.debugColor
	for &shape in area.shapes {
		PhysicsShape_DrawDebug(&shape, area.globalPosition, area.globalRotation, color, area.globalScale)
	}
}

AreaNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	area := cast(^AreaNode)node
	DestroySubject(&area.onBodyEntered)
	DestroySubject(&area.onBodyExited)
	if b2.Body_IsValid(area.bodyId) {
		b2.DestroyBody(area.bodyId)
		area.bodyId = b2.nullBodyId
	}
}

// ============================================================================
// 5. RaycastNode (Raycast - Casts a ray in a direction and length)
// ============================================================================
RaycastNode :: struct {
	using node: Node,
	monitoring: bool `gui:"true"`,
	direction: [2]f32 `gui:"true" min:"-1" max:"1"`,
	length: f32 `gui:"true" min:"1" max:"2000"`,
	collideWithSensors: bool `gui:"true"`,
	categoryLayers: CollisionLayerSet `gui:"true"`,
	maskLayers: CollisionLayerSet `gui:"true"`,
	isColliding: bool `gui:"true" save:"false"`,
	hitFraction: f32 `gui:"true" min:"0" max:"1" save:"false"`,
	hitPoint: [2]f32 `gui:"true" min:"0" max:"1280" save:"false"`,
	hitNormal: [2]f32 `gui:"true" min:"-1" max:"1" save:"false"`,
	hitShapeId: b2.ShapeId,
	hitNode: ^Node,
	excludeNode: ^Node,
	excludeParent: bool `gui:"true"`, // don't hit the body it's under (#219)
	rayColor: rl.Color `gui:"true"`,
	hitColor: rl.Color `gui:"true"`,
	onHitStarted: EventSubject, // "hit_started"(node): the ray started hitting a node
	onHitEnded: EventSubject,   // "hit_ended"(node): the ray stopped hitting it
}

Raycast :: RaycastNode

RaycastNode_Create :: proc(scene: ^Scene, name: string = "Raycast", parent: ^Node = nil) -> ^RaycastNode {
	rc := CreateNode(scene.manager, RaycastNode)
	rc.name = strings.clone(name, rc.allocator) // owned: callers pass temp strings too
	rc.position = {450, 260}
	rc.monitoring = true
	rc.direction = {1.0, 0.5}
	rc.length = 450.0
	rc.collideWithSensors = false
	rc.excludeParent = true
	rc.categoryLayers = DEFAULT_COLLISION_CATEGORIES
	rc.maskLayers = DEFAULT_COLLISION_MASK
	rc.rayColor = rl.Color{56, 189, 248, 255} // Cyan
	rc.hitColor = rl.Color{248, 113, 113, 255} // Red
	rc.update = RaycastNode_Update
	rc.render = RaycastNode_Render
	rc.onDestroy = RaycastNode_Destroy
	InitializeSubject(&rc.onHitStarted, "hit_started", rc)
	InitializeSubject(&rc.onHitEnded, "hit_ended", rc)
	scene->addNode(rc, parent)
	return rc
}

RaycastNode_SetMonitoring :: proc(rc: ^RaycastNode, enabled: bool) {
	if rc == nil do return
	rc.monitoring = enabled
	if !enabled {
		rc.isColliding = false
		rc.hitFraction = 1.0
		rc.hitShapeId = b2.nullShapeId
		rc.hitNode = nil
	}
}

RaycastNode_IsMonitoring :: proc(rc: ^RaycastNode) -> bool {
	if rc == nil do return false
	return rc.monitoring
}

Raycast_Callback :: proc "c" (shapeId: b2.ShapeId, point: b2.Vec2, normal: b2.Vec2, fraction: f32, ctx: rawptr) -> f32 {
	if ctx == nil || !b2.Shape_IsValid(shapeId) do return 1.0
	rc := cast(^RaycastNode)ctx

	if !rc.collideWithSensors && b2.Shape_IsSensor(shapeId) {
		return -1.0 // Ignore sensor and continue raycast
	}

	bodyId := b2.Shape_GetBody(shapeId)
	hitNode: ^Node = nil
	if b2.Body_IsValid(bodyId) {
		hitNode = cast(^Node)b2.Body_GetUserData(bodyId)
	}
	if rc.excludeNode != nil && hitNode == rc.excludeNode {
		return -1.0 // Ignore excluded node and continue
	}

	rc.isColliding = true
	rc.hitShapeId = shapeId
	rc.hitPoint = point
	rc.hitNormal = normal
	rc.hitFraction = fraction
	rc.hitNode = hitNode

	return fraction // Clip ray to closest hit
}

RaycastNode_GetOrigin :: proc(rc: ^RaycastNode) -> [2]f32 {
	if rc == nil do return {}
	if rc.parent != nil {
		parentPos := rc.parent.globalPosition if rc.parent.globalScale != {} else rc.parent.position
		parentRot := rc.parent.globalRotation if rc.parent.globalScale != {} else rc.parent.rotation
		parentScale := rc.parent.globalScale if rc.parent.globalScale != {} else (rc.parent.scale if rc.parent.scale != {} else [2]f32{1, 1})
		return parentPos + rotate_vec(rc.position * parentScale, parentRot)
	}
	return rc.globalPosition if rc.globalScale != {} else rc.position
}

RaycastNode_GetTranslation :: proc(rc: ^RaycastNode) -> [2]f32 {
	if rc == nil do return {}
	dir := rc.direction
	if b2.LengthSquared(dir) > 0.0001 {
		dir = b2.Normalize(dir)
	} else {
		dir = {0, 1}
	}
	rot: f32 = rc.rotation
	scl: [2]f32 = rc.scale if rc.scale != {} else [2]f32{1, 1}
	if rc.parent != nil {
		parentRot := rc.parent.globalRotation if rc.parent.globalScale != {} else rc.parent.rotation
		parentScale := rc.parent.globalScale if rc.parent.globalScale != {} else (rc.parent.scale if rc.parent.scale != {} else [2]f32{1, 1})
		rot = parentRot + rc.rotation
		scl = parentScale * scl
	} else if rc.globalScale != {} {
		rot = rc.globalRotation
		scl = rc.globalScale
	}
	localVec := dir * max(rc.length, 1.0)
	return rotate_vec(localVec * scl, rot)
}

RaycastNode_CastNow :: proc(rc: ^RaycastNode, worldId: b2.WorldId) {
	rc.isColliding = false
	rc.hitFraction = 1.0
	rc.hitShapeId = b2.nullShapeId
	rc.hitNode = nil

	if !b2.World_IsValid(worldId) do return

	rc.excludeNode = nil
	if rc.excludeParent && rc.gameContext != nil && rc.gameContext.scene != nil do rc.excludeNode = GetParent(rc.gameContext.scene.manager, rc)
	origin := RaycastNode_GetOrigin(rc)
	translation := RaycastNode_GetTranslation(rc)
	rc.hitPoint = origin + translation
	rc.hitNormal = {0, 0}

	qFilter := b2.QueryFilter{
		categoryBits = CollisionLayerSet_ToBits(rc.categoryLayers),
		maskBits     = CollisionLayerSet_ToBits(rc.maskLayers),
	}

	_ = b2.World_CastRay(worldId, origin, translation, qFilter, Raycast_Callback, cast(rawptr)rc)
}

RaycastNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	rc := cast(^RaycastNode)node
	if !rc.enabled || !rc.monitoring {
		if !rc.monitoring {
			rc.isColliding = false
			rc.hitFraction = 1.0
			rc.hitShapeId = b2.nullShapeId
			rc.hitNode = nil
		}
		return
	}
	if gameContext == nil || gameContext.game == nil do return

	prevHit := rc.hitNode if rc.isColliding else nil
	RaycastNode_CastNow(rc, gameContext.game.physicsWorld.worldId)
	curHit := rc.hitNode if rc.isColliding else nil
	if prevHit != curHit {
		if prevHit != nil && Node_IsAlive(prevHit) do rc.onHitEnded->notify(rc, prevHit, gameContext)
		if curHit != nil do rc.onHitStarted->notify(rc, curHit, gameContext)
	}
}

RaycastNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	rc := cast(^RaycastNode)node
	DestroySubject(&rc.onHitStarted)
	DestroySubject(&rc.onHitEnded)
}

RaycastNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	rc := cast(^RaycastNode)node
	if gameContext != nil && gameContext.game != nil && !gameContext.game.physicsWorld.drawPhysicsDebug {
		return
	}

	origin := RaycastNode_GetOrigin(rc)
	endPt := origin + RaycastNode_GetTranslation(rc)

	rl.DrawCircleV(origin, 4.0, rc.rayColor)
	if rc.isColliding {
		rl.DrawLineEx(origin, rc.hitPoint, 2.0, rc.hitColor)
		rl.DrawLineEx(rc.hitPoint, endPt, 1.0, rl.Color{rc.rayColor.r, rc.rayColor.g, rc.rayColor.b, 80})
		rl.DrawCircleV(rc.hitPoint, 5.0, rc.hitColor)
		// Draw surface normal at hit point
		rl.DrawLineEx(rc.hitPoint, rc.hitPoint + rc.hitNormal * 20.0, 2.0, rl.YELLOW)
	} else {
		rl.DrawLineEx(origin, endPt, 2.0, rc.rayColor)
	}
}

// ============================================================================
// Scene Physics Body Activation Helpers
// ============================================================================
// Physics_NodeDisabled: a disabled node's physics stops - its body is
// disabled (its update enables it again) and a joint goes (made again) (#219).
Physics_NodeDisabled :: proc(node: ^Node) {
	if node.typeId == JointNode {
		PhysicsJoint_Destroy(&(cast(^JointNode)node).joint)
		return
	}
	Node_SetPhysicsEnabled(node, false)
}

Node_SetPhysicsEnabled :: proc(node: ^Node, enabled: bool) {
	if node == nil do return
	bodyId: b2.BodyId
	if node.onDestroy == StaticBodyNode_Destroy {
		bodyId = (cast(^StaticBodyNode)node).bodyId
	} else if node.onDestroy == DynamicBodyNode_Destroy {
		bodyId = (cast(^DynamicBodyNode)node).bodyId
	} else if node.onDestroy == KinematicBodyNode_Destroy {
		bodyId = (cast(^KinematicBodyNode)node).bodyId
	} else if node.onDestroy == CharacterMoverNode_Destroy {
		bodyId = (cast(^CharacterMoverNode)node).bodyId
	} else if node.onDestroy == AreaNode_Destroy {
		bodyId = (cast(^AreaNode)node).bodyId
	}
	if b2.Body_IsValid(bodyId) {
		if enabled && node.enabled {
			if !b2.Body_IsEnabled(bodyId) {
				b2.Body_Enable(bodyId)
			}
		} else {
			if b2.Body_IsEnabled(bodyId) {
				b2.Body_Disable(bodyId)
			}
		}
	}
}

Scene_SetPhysicsEnabled :: proc(scene: ^Scene, enabled: bool) {
	if scene == nil || scene.manager == nil do return
	for node in scene.manager.nodes {
		if node != nil {
			Node_SetPhysicsEnabled(node, enabled)
		}
	}
	for addNode in scene.manager.addition {
		if addNode != nil {
			Node_SetPhysicsEnabled(addNode, enabled)
		}
	}
}

// Physics_SetWorldTransform writes a world-space transform from Box2D back to
// a node: local position/rotation are expressed in the parent's space, so
// bodies parented under moved/rotated nodes stay where physics put them.
Physics_SetWorldTransform :: proc(node: ^Node, worldPos: [2]f32, worldRot: f32) {
	parentRot := node.globalRotation - node.rotation
	if node.gameContext != nil && node.gameContext.scene != nil && node.gameContext.scene.manager != nil {
		node.position = Node_WorldToParent(node.gameContext.scene.manager, node, worldPos)
	} else {
		node.position = worldPos - (node.globalPosition - node.position)
	}
	node.rotation = worldRot - parentRot
	node.globalPosition = worldPos
	node.globalRotation = worldRot
}
