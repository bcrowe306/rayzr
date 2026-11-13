package engine

import "core:math"
import b2 "vendor:box2d"
import rl "vendor:raylib"

PhysicsJointType :: enum {
	Distance,
	Filter,
	Motor,
	Mouse,
	Prismatic,
	Revolute,
	Weld,
	Wheel,
}

// 1. Distance Joint
DistanceJoint :: struct {
	jointId: b2.JointId,
	bodyIdA: b2.BodyId,
	bodyIdB: b2.BodyId,
	localAnchorA: [2]f32 `gui:"true" min:"-500" max:"500"`,
	localAnchorB: [2]f32 `gui:"true" min:"-500" max:"500"`,
	length: f32 `gui:"true" min:"1" max:"1000"`,
	enableSpring: bool `gui:"true"`,
	hertz: f32 `gui:"true" min:"0" max:"60"`,
	dampingRatio: f32 `gui:"true" min:"0" max:"10"`,
	enableLimit: bool `gui:"true"`,
	minLength: f32 `gui:"true" min:"0" max:"1000"`,
	maxLength: f32 `gui:"true" min:"1" max:"1000"`,
	enableMotor: bool `gui:"true"`,
	maxMotorForce: f32 `gui:"true" min:"0" max:"100000000"`, // pixel-scale bodies are heavy (mass ~ area in px²)
	motorSpeed: f32 `gui:"true" min:"-500" max:"500"`,
	collideConnected: bool `gui:"true"`,
}

DistanceJoint_Init :: proc(j: ^DistanceJoint) {
	def := b2.DefaultDistanceJointDef()
	j.localAnchorA = def.localAnchorA
	j.localAnchorB = def.localAnchorB
	j.length = 100.0
	j.enableSpring = def.enableSpring
	j.hertz = 4.0
	j.dampingRatio = 0.5
	j.enableLimit = def.enableLimit
	j.minLength = 20.0
	j.maxLength = 200.0
	j.enableMotor = def.enableMotor
	j.maxMotorForce = def.maxMotorForce
	j.motorSpeed = def.motorSpeed
	j.collideConnected = def.collideConnected
}

DistanceJoint_Create :: proc(j: ^DistanceJoint, worldId: b2.WorldId, bodyA, bodyB: b2.BodyId) {
	if !b2.World_IsValid(worldId) || !b2.Body_IsValid(bodyA) || !b2.Body_IsValid(bodyB) do return
	if b2.Joint_IsValid(j.jointId) do b2.DestroyJoint(j.jointId)

	j.bodyIdA = bodyA
	j.bodyIdB = bodyB

	def := b2.DefaultDistanceJointDef()
	def.bodyIdA = bodyA
	def.bodyIdB = bodyB
	def.localAnchorA = j.localAnchorA
	def.localAnchorB = j.localAnchorB
	def.length = j.length
	def.enableSpring = j.enableSpring
	def.hertz = j.hertz
	def.dampingRatio = j.dampingRatio
	def.enableLimit = j.enableLimit
	def.minLength = j.minLength
	def.maxLength = j.maxLength
	def.enableMotor = j.enableMotor
	def.maxMotorForce = j.maxMotorForce
	def.motorSpeed = j.motorSpeed
	def.collideConnected = j.collideConnected
	j.jointId = b2.CreateDistanceJoint(worldId, def)
}

DistanceJoint_Sync :: proc(j: ^DistanceJoint) {
	if !b2.Joint_IsValid(j.jointId) do return
	b2.Joint_SetLocalAnchorA(j.jointId, j.localAnchorA)
	b2.Joint_SetLocalAnchorB(j.jointId, j.localAnchorB)
	b2.Joint_SetCollideConnected(j.jointId, j.collideConnected)
	b2.DistanceJoint_SetLength(j.jointId, j.length)
	b2.DistanceJoint_EnableSpring(j.jointId, j.enableSpring)
	b2.DistanceJoint_SetSpringHertz(j.jointId, j.hertz)
	b2.DistanceJoint_SetSpringDampingRatio(j.jointId, j.dampingRatio)
	b2.DistanceJoint_EnableLimit(j.jointId, j.enableLimit)
	b2.DistanceJoint_SetLengthRange(j.jointId, j.minLength, j.maxLength)
	b2.DistanceJoint_EnableMotor(j.jointId, j.enableMotor)
	b2.DistanceJoint_SetMaxMotorForce(j.jointId, j.maxMotorForce)
	b2.DistanceJoint_SetMotorSpeed(j.jointId, j.motorSpeed)
}

// 2. Filter Joint
FilterJoint :: struct {
	jointId: b2.JointId,
	bodyIdA: b2.BodyId,
	bodyIdB: b2.BodyId,
}

FilterJoint_Create :: proc(j: ^FilterJoint, worldId: b2.WorldId, bodyA, bodyB: b2.BodyId) {
	if !b2.World_IsValid(worldId) || !b2.Body_IsValid(bodyA) || !b2.Body_IsValid(bodyB) do return
	if b2.Joint_IsValid(j.jointId) do b2.DestroyJoint(j.jointId)
	j.bodyIdA = bodyA
	j.bodyIdB = bodyB
	def := b2.DefaultFilterJointDef()
	def.bodyIdA = bodyA
	def.bodyIdB = bodyB
	j.jointId = b2.CreateFilterJoint(worldId, def)
}

// 3. Motor Joint
MotorJoint :: struct {
	jointId: b2.JointId,
	bodyIdA: b2.BodyId,
	bodyIdB: b2.BodyId,
	linearOffset: [2]f32 `gui:"true" min:"-500" max:"500"`,
	angularOffset: f32 `gui:"true" min:"0" max:"360"`,
	maxForce: f32 `gui:"true" min:"0" max:"100000000"`, // pixel-scale bodies are heavy (mass ~ area in px²)
	maxTorque: f32 `gui:"true" min:"0" max:"100000000"`, // pixel-scale bodies are heavy (mass ~ area in px²)
	correctionFactor: f32 `gui:"true" min:"0" max:"1"`,
	collideConnected: bool `gui:"true"`,
}

MotorJoint_Init :: proc(j: ^MotorJoint) {
	def := b2.DefaultMotorJointDef()
	j.linearOffset = def.linearOffset
	j.angularOffset = math.to_degrees(def.angularOffset)
	j.maxForce = 500.0
	j.maxTorque = 500.0
	j.correctionFactor = def.correctionFactor
	j.collideConnected = def.collideConnected
}

MotorJoint_Create :: proc(j: ^MotorJoint, worldId: b2.WorldId, bodyA, bodyB: b2.BodyId) {
	if !b2.World_IsValid(worldId) || !b2.Body_IsValid(bodyA) || !b2.Body_IsValid(bodyB) do return
	if b2.Joint_IsValid(j.jointId) do b2.DestroyJoint(j.jointId)
	j.bodyIdA = bodyA
	j.bodyIdB = bodyB
	def := b2.DefaultMotorJointDef()
	def.bodyIdA = bodyA
	def.bodyIdB = bodyB
	def.linearOffset = j.linearOffset
	def.angularOffset = math.to_radians(j.angularOffset)
	def.maxForce = j.maxForce
	def.maxTorque = j.maxTorque
	def.correctionFactor = j.correctionFactor
	def.collideConnected = j.collideConnected
	j.jointId = b2.CreateMotorJoint(worldId, def)
}

MotorJoint_Sync :: proc(j: ^MotorJoint) {
	if !b2.Joint_IsValid(j.jointId) do return
	b2.Joint_SetCollideConnected(j.jointId, j.collideConnected)
	b2.MotorJoint_SetLinearOffset(j.jointId, j.linearOffset)
	b2.MotorJoint_SetAngularOffset(j.jointId, math.to_radians(j.angularOffset))
	b2.MotorJoint_SetMaxForce(j.jointId, j.maxForce)
	b2.MotorJoint_SetMaxTorque(j.jointId, j.maxTorque)
	b2.MotorJoint_SetCorrectionFactor(j.jointId, j.correctionFactor)
}

// 4. Mouse Joint
MouseJoint :: struct {
	jointId: b2.JointId,
	bodyIdA: b2.BodyId,
	bodyIdB: b2.BodyId,
	target: [2]f32 `gui:"true" min:"0" max:"1280"`,
	hertz: f32 `gui:"true" min:"0.1" max:"60"`,
	dampingRatio: f32 `gui:"true" min:"0" max:"10"`,
	maxForce: f32 `gui:"true" min:"0" max:"50000"`,
	collideConnected: bool `gui:"true"`,
}

MouseJoint_Init :: proc(j: ^MouseJoint) {
	def := b2.DefaultMouseJointDef()
	j.target = def.target
	j.hertz = def.hertz
	j.dampingRatio = def.dampingRatio
	j.maxForce = 1000.0
	j.collideConnected = def.collideConnected
}

MouseJoint_Create :: proc(j: ^MouseJoint, worldId: b2.WorldId, bodyA, bodyB: b2.BodyId) {
	if !b2.World_IsValid(worldId) || !b2.Body_IsValid(bodyA) || !b2.Body_IsValid(bodyB) do return
	if b2.Joint_IsValid(j.jointId) do b2.DestroyJoint(j.jointId)
	j.bodyIdA = bodyA
	j.bodyIdB = bodyB
	def := b2.DefaultMouseJointDef()
	def.bodyIdA = bodyA
	def.bodyIdB = bodyB
	def.target = j.target
	def.hertz = j.hertz
	def.dampingRatio = j.dampingRatio
	def.maxForce = j.maxForce
	def.collideConnected = j.collideConnected
	j.jointId = b2.CreateMouseJoint(worldId, def)
}

MouseJoint_Sync :: proc(j: ^MouseJoint) {
	if !b2.Joint_IsValid(j.jointId) do return
	b2.Joint_SetCollideConnected(j.jointId, j.collideConnected)
	b2.MouseJoint_SetTarget(j.jointId, j.target)
	b2.MouseJoint_SetSpringHertz(j.jointId, j.hertz)
	b2.MouseJoint_SetSpringDampingRatio(j.jointId, j.dampingRatio)
	b2.MouseJoint_SetMaxForce(j.jointId, j.maxForce)
}

// 5. Prismatic Joint
PrismaticJoint :: struct {
	jointId: b2.JointId,
	bodyIdA: b2.BodyId,
	bodyIdB: b2.BodyId,
	localAnchorA: [2]f32 `gui:"true" min:"-500" max:"500"`,
	localAnchorB: [2]f32 `gui:"true" min:"-500" max:"500"`,
	localAxisA: [2]f32 `gui:"true" min:"-1" max:"1"`,
	referenceAngle: f32 `gui:"true" min:"0" max:"360"`,
	targetTranslation: f32 `gui:"true" min:"-500" max:"500"`,
	enableSpring: bool `gui:"true"`,
	hertz: f32 `gui:"true" min:"0" max:"60"`,
	dampingRatio: f32 `gui:"true" min:"0" max:"10"`,
	enableLimit: bool `gui:"true"`,
	lowerTranslation: f32 `gui:"true" min:"-500" max:"500"`,
	upperTranslation: f32 `gui:"true" min:"-500" max:"500"`,
	enableMotor: bool `gui:"true"`,
	maxMotorForce: f32 `gui:"true" min:"0" max:"100000000"`, // pixel-scale bodies are heavy (mass ~ area in px²)
	motorSpeed: f32 `gui:"true" min:"-500" max:"500"`,
	collideConnected: bool `gui:"true"`,
}

PrismaticJoint_Init :: proc(j: ^PrismaticJoint) {
	def := b2.DefaultPrismaticJointDef()
	j.localAnchorA = def.localAnchorA
	j.localAnchorB = def.localAnchorB
	j.localAxisA = def.localAxisA
	j.referenceAngle = math.to_degrees(def.referenceAngle)
	j.targetTranslation = def.targetTranslation
	j.enableSpring = def.enableSpring
	j.hertz = 4.0
	j.dampingRatio = 0.5
	j.enableLimit = def.enableLimit
	j.lowerTranslation = -100.0
	j.upperTranslation = 100.0
	j.enableMotor = def.enableMotor
	j.maxMotorForce = def.maxMotorForce
	j.motorSpeed = def.motorSpeed
	j.collideConnected = def.collideConnected
}

PrismaticJoint_Create :: proc(j: ^PrismaticJoint, worldId: b2.WorldId, bodyA, bodyB: b2.BodyId) {
	if !b2.World_IsValid(worldId) || !b2.Body_IsValid(bodyA) || !b2.Body_IsValid(bodyB) do return
	if b2.Joint_IsValid(j.jointId) do b2.DestroyJoint(j.jointId)
	j.bodyIdA = bodyA
	j.bodyIdB = bodyB
	def := b2.DefaultPrismaticJointDef()
	def.bodyIdA = bodyA
	def.bodyIdB = bodyB
	def.localAnchorA = j.localAnchorA
	def.localAnchorB = j.localAnchorB
	def.localAxisA = b2.Normalize(j.localAxisA) if b2.LengthSquared(j.localAxisA) > 0.0001 else {1, 0}
	def.referenceAngle = math.to_radians(j.referenceAngle)
	def.targetTranslation = j.targetTranslation
	def.enableSpring = j.enableSpring
	def.hertz = j.hertz
	def.dampingRatio = j.dampingRatio
	def.enableLimit = j.enableLimit
	def.lowerTranslation = j.lowerTranslation
	def.upperTranslation = j.upperTranslation
	def.enableMotor = j.enableMotor
	def.maxMotorForce = j.maxMotorForce
	def.motorSpeed = j.motorSpeed
	def.collideConnected = j.collideConnected
	j.jointId = b2.CreatePrismaticJoint(worldId, def)
}

PrismaticJoint_Sync :: proc(j: ^PrismaticJoint) {
	if !b2.Joint_IsValid(j.jointId) do return
	b2.Joint_SetLocalAnchorA(j.jointId, j.localAnchorA)
	b2.Joint_SetLocalAnchorB(j.jointId, j.localAnchorB)
	axis := b2.Normalize(j.localAxisA) if b2.LengthSquared(j.localAxisA) > 0.0001 else b2.Vec2{1, 0}
	b2.Joint_SetLocalAxisA(j.jointId, axis)
	b2.Joint_SetReferenceAngle(j.jointId, math.to_radians(j.referenceAngle))
	b2.Joint_SetCollideConnected(j.jointId, j.collideConnected)
	b2.PrismaticJoint_EnableSpring(j.jointId, j.enableSpring)
	b2.PrismaticJoint_SetSpringHertz(j.jointId, j.hertz)
	b2.PrismaticJoint_SetSpringDampingRatio(j.jointId, j.dampingRatio)
	b2.PrismaticJoint_SetTargetTranslation(j.jointId, j.targetTranslation)
	b2.PrismaticJoint_EnableLimit(j.jointId, j.enableLimit)
	b2.PrismaticJoint_SetLimits(j.jointId, j.lowerTranslation, j.upperTranslation)
	b2.PrismaticJoint_EnableMotor(j.jointId, j.enableMotor)
	b2.PrismaticJoint_SetMaxMotorForce(j.jointId, j.maxMotorForce)
	b2.PrismaticJoint_SetMotorSpeed(j.jointId, j.motorSpeed)
}

// 6. Revolute Joint
RevoluteJoint :: struct {
	jointId: b2.JointId,
	bodyIdA: b2.BodyId,
	bodyIdB: b2.BodyId,
	localAnchorA: [2]f32 `gui:"true" min:"-500" max:"500"`,
	localAnchorB: [2]f32 `gui:"true" min:"-500" max:"500"`,
	referenceAngle: f32 `gui:"true" min:"0" max:"360"`,
	targetAngle: f32 `gui:"true" min:"-360" max:"360"`,
	enableSpring: bool `gui:"true"`,
	hertz: f32 `gui:"true" min:"0" max:"60"`,
	dampingRatio: f32 `gui:"true" min:"0" max:"10"`,
	enableLimit: bool `gui:"true"`,
	lowerAngle: f32 `gui:"true" min:"-360" max:"360"`,
	upperAngle: f32 `gui:"true" min:"-360" max:"360"`,
	enableMotor: bool `gui:"true"`,
	maxMotorTorque: f32 `gui:"true" min:"0" max:"100000000"`, // pixel-scale bodies are heavy (mass ~ area in px²)
	motorSpeed: f32 `gui:"true" min:"-50" max:"50"`,
	collideConnected: bool `gui:"true"`,
}

RevoluteJoint_Init :: proc(j: ^RevoluteJoint) {
	def := b2.DefaultRevoluteJointDef()
	j.localAnchorA = def.localAnchorA
	j.localAnchorB = def.localAnchorB
	j.referenceAngle = math.to_degrees(def.referenceAngle)
	j.targetAngle = math.to_degrees(def.targetAngle)
	j.enableSpring = def.enableSpring
	j.hertz = 4.0
	j.dampingRatio = 0.5
	j.enableLimit = def.enableLimit
	j.lowerAngle = -45.0
	j.upperAngle = 45.0
	j.enableMotor = def.enableMotor
	j.maxMotorTorque = 500.0
	j.motorSpeed = def.motorSpeed
	j.collideConnected = def.collideConnected
}

RevoluteJoint_Create :: proc(j: ^RevoluteJoint, worldId: b2.WorldId, bodyA, bodyB: b2.BodyId) {
	if !b2.World_IsValid(worldId) || !b2.Body_IsValid(bodyA) || !b2.Body_IsValid(bodyB) do return
	if b2.Joint_IsValid(j.jointId) do b2.DestroyJoint(j.jointId)
	j.bodyIdA = bodyA
	j.bodyIdB = bodyB
	def := b2.DefaultRevoluteJointDef()
	def.bodyIdA = bodyA
	def.bodyIdB = bodyB
	def.localAnchorA = j.localAnchorA
	def.localAnchorB = j.localAnchorB
	def.referenceAngle = math.to_radians(j.referenceAngle)
	def.targetAngle = math.to_radians(j.targetAngle)
	def.enableSpring = j.enableSpring
	def.hertz = j.hertz
	def.dampingRatio = j.dampingRatio
	def.enableLimit = j.enableLimit
	def.lowerAngle = math.to_radians(j.lowerAngle)
	def.upperAngle = math.to_radians(j.upperAngle)
	def.enableMotor = j.enableMotor
	def.maxMotorTorque = j.maxMotorTorque
	def.motorSpeed = j.motorSpeed
	def.collideConnected = j.collideConnected
	j.jointId = b2.CreateRevoluteJoint(worldId, def)
}

RevoluteJoint_Sync :: proc(j: ^RevoluteJoint) {
	if !b2.Joint_IsValid(j.jointId) do return
	b2.Joint_SetLocalAnchorA(j.jointId, j.localAnchorA)
	b2.Joint_SetLocalAnchorB(j.jointId, j.localAnchorB)
	b2.Joint_SetReferenceAngle(j.jointId, math.to_radians(j.referenceAngle))
	b2.Joint_SetCollideConnected(j.jointId, j.collideConnected)
	b2.RevoluteJoint_EnableSpring(j.jointId, j.enableSpring)
	b2.RevoluteJoint_SetSpringHertz(j.jointId, j.hertz)
	b2.RevoluteJoint_SetSpringDampingRatio(j.jointId, j.dampingRatio)
	b2.RevoluteJoint_SetTargetAngle(j.jointId, math.to_radians(j.targetAngle))
	b2.RevoluteJoint_EnableLimit(j.jointId, j.enableLimit)
	b2.RevoluteJoint_SetLimits(j.jointId, math.to_radians(j.lowerAngle), math.to_radians(j.upperAngle))
	b2.RevoluteJoint_EnableMotor(j.jointId, j.enableMotor)
	b2.RevoluteJoint_SetMaxMotorTorque(j.jointId, j.maxMotorTorque)
	b2.RevoluteJoint_SetMotorSpeed(j.jointId, j.motorSpeed)
}

// 7. Weld Joint
WeldJoint :: struct {
	jointId: b2.JointId,
	bodyIdA: b2.BodyId,
	bodyIdB: b2.BodyId,
	localAnchorA: [2]f32 `gui:"true" min:"-500" max:"500"`,
	localAnchorB: [2]f32 `gui:"true" min:"-500" max:"500"`,
	referenceAngle: f32 `gui:"true" min:"0" max:"360"`,
	linearHertz: f32 `gui:"true" min:"0" max:"60"`,
	angularHertz: f32 `gui:"true" min:"0" max:"60"`,
	linearDampingRatio: f32 `gui:"true" min:"0" max:"10"`,
	angularDampingRatio: f32 `gui:"true" min:"0" max:"10"`,
	collideConnected: bool `gui:"true"`,
}

WeldJoint_Init :: proc(j: ^WeldJoint) {
	def := b2.DefaultWeldJointDef()
	j.localAnchorA = def.localAnchorA
	j.localAnchorB = def.localAnchorB
	j.referenceAngle = math.to_degrees(def.referenceAngle)
	j.linearHertz = def.linearHertz
	j.angularHertz = def.angularHertz
	j.linearDampingRatio = def.linearDampingRatio
	j.angularDampingRatio = def.angularDampingRatio
	j.collideConnected = def.collideConnected
}

WeldJoint_Create :: proc(j: ^WeldJoint, worldId: b2.WorldId, bodyA, bodyB: b2.BodyId) {
	if !b2.World_IsValid(worldId) || !b2.Body_IsValid(bodyA) || !b2.Body_IsValid(bodyB) do return
	if b2.Joint_IsValid(j.jointId) do b2.DestroyJoint(j.jointId)
	j.bodyIdA = bodyA
	j.bodyIdB = bodyB
	def := b2.DefaultWeldJointDef()
	def.bodyIdA = bodyA
	def.bodyIdB = bodyB
	def.localAnchorA = j.localAnchorA
	def.localAnchorB = j.localAnchorB
	def.referenceAngle = math.to_radians(j.referenceAngle)
	def.linearHertz = j.linearHertz
	def.angularHertz = j.angularHertz
	def.linearDampingRatio = j.linearDampingRatio
	def.angularDampingRatio = j.angularDampingRatio
	def.collideConnected = j.collideConnected
	j.jointId = b2.CreateWeldJoint(worldId, def)
}

WeldJoint_Sync :: proc(j: ^WeldJoint) {
	if !b2.Joint_IsValid(j.jointId) do return
	b2.Joint_SetLocalAnchorA(j.jointId, j.localAnchorA)
	b2.Joint_SetLocalAnchorB(j.jointId, j.localAnchorB)
	b2.Joint_SetReferenceAngle(j.jointId, math.to_radians(j.referenceAngle))
	b2.Joint_SetCollideConnected(j.jointId, j.collideConnected)
	b2.WeldJoint_SetLinearHertz(j.jointId, j.linearHertz)
	b2.WeldJoint_SetAngularHertz(j.jointId, j.angularHertz)
	b2.WeldJoint_SetLinearDampingRatio(j.jointId, j.linearDampingRatio)
	b2.WeldJoint_SetAngularDampingRatio(j.jointId, j.angularDampingRatio)
}

// 8. Wheel Joint
WheelJoint :: struct {
	jointId: b2.JointId,
	bodyIdA: b2.BodyId,
	bodyIdB: b2.BodyId,
	localAnchorA: [2]f32 `gui:"true" min:"-500" max:"500"`,
	localAnchorB: [2]f32 `gui:"true" min:"-500" max:"500"`,
	localAxisA: [2]f32 `gui:"true" min:"-1" max:"1"`,
	enableSpring: bool `gui:"true"`,
	hertz: f32 `gui:"true" min:"0" max:"60"`,
	dampingRatio: f32 `gui:"true" min:"0" max:"10"`,
	enableLimit: bool `gui:"true"`,
	lowerTranslation: f32 `gui:"true" min:"-500" max:"500"`,
	upperTranslation: f32 `gui:"true" min:"-500" max:"500"`,
	enableMotor: bool `gui:"true"`,
	maxMotorTorque: f32 `gui:"true" min:"0" max:"100000000"`, // pixel-scale bodies are heavy (mass ~ area in px²)
	motorSpeed: f32 `gui:"true" min:"-50" max:"50"`,
	collideConnected: bool `gui:"true"`,
}

WheelJoint_Init :: proc(j: ^WheelJoint) {
	def := b2.DefaultWheelJointDef()
	j.localAnchorA = def.localAnchorA
	j.localAnchorB = def.localAnchorB
	j.localAxisA = def.localAxisA
	j.enableSpring = def.enableSpring
	j.hertz = def.hertz
	j.dampingRatio = def.dampingRatio
	j.enableLimit = def.enableLimit
	j.lowerTranslation = -50.0
	j.upperTranslation = 50.0
	j.enableMotor = def.enableMotor
	j.maxMotorTorque = 500.0
	j.motorSpeed = def.motorSpeed
	j.collideConnected = def.collideConnected
}

WheelJoint_Create :: proc(j: ^WheelJoint, worldId: b2.WorldId, bodyA, bodyB: b2.BodyId) {
	if !b2.World_IsValid(worldId) || !b2.Body_IsValid(bodyA) || !b2.Body_IsValid(bodyB) do return
	if b2.Joint_IsValid(j.jointId) do b2.DestroyJoint(j.jointId)
	j.bodyIdA = bodyA
	j.bodyIdB = bodyB
	def := b2.DefaultWheelJointDef()
	def.bodyIdA = bodyA
	def.bodyIdB = bodyB
	def.localAnchorA = j.localAnchorA
	def.localAnchorB = j.localAnchorB
	def.localAxisA = b2.Normalize(j.localAxisA) if b2.LengthSquared(j.localAxisA) > 0.0001 else {0, 1}
	def.enableSpring = j.enableSpring
	def.hertz = j.hertz
	def.dampingRatio = j.dampingRatio
	def.enableLimit = j.enableLimit
	def.lowerTranslation = j.lowerTranslation
	def.upperTranslation = j.upperTranslation
	def.enableMotor = j.enableMotor
	def.maxMotorTorque = j.maxMotorTorque
	def.motorSpeed = j.motorSpeed
	def.collideConnected = j.collideConnected
	j.jointId = b2.CreateWheelJoint(worldId, def)
}

WheelJoint_Sync :: proc(j: ^WheelJoint) {
	if !b2.Joint_IsValid(j.jointId) do return
	b2.Joint_SetLocalAnchorA(j.jointId, j.localAnchorA)
	b2.Joint_SetLocalAnchorB(j.jointId, j.localAnchorB)
	axis := b2.Normalize(j.localAxisA) if b2.LengthSquared(j.localAxisA) > 0.0001 else b2.Vec2{0, 1}
	b2.Joint_SetLocalAxisA(j.jointId, axis)
	b2.Joint_SetCollideConnected(j.jointId, j.collideConnected)
	b2.WheelJoint_EnableSpring(j.jointId, j.enableSpring)
	b2.WheelJoint_SetSpringHertz(j.jointId, j.hertz)
	b2.WheelJoint_SetSpringDampingRatio(j.jointId, j.dampingRatio)
	b2.WheelJoint_EnableLimit(j.jointId, j.enableLimit)
	b2.WheelJoint_SetLimits(j.jointId, j.lowerTranslation, j.upperTranslation)
	b2.WheelJoint_EnableMotor(j.jointId, j.enableMotor)
	b2.WheelJoint_SetMaxMotorTorque(j.jointId, j.maxMotorTorque)
	b2.WheelJoint_SetMotorSpeed(j.jointId, j.motorSpeed)
}

// Unified Joint Wrapper for Inspector & Scene use
PhysicsJoint :: struct {
	type: PhysicsJointType `gui:"true"`,
	// Each type's parameters (reflected: "joint.revolute.motorSpeed", ...).
	distance: DistanceJoint `gui:"true"`,
	filter: FilterJoint,
	motor: MotorJoint `gui:"true"`,
	mouse: MouseJoint `gui:"true"`,
	prismatic: PrismaticJoint `gui:"true"`,
	revolute: RevoluteJoint `gui:"true"`,
	weld: WeldJoint `gui:"true"`,
	wheel: WheelJoint `gui:"true"`,
}

PhysicsJoint_Init :: proc(pj: ^PhysicsJoint, type: PhysicsJointType = .Distance) {
	pj.type = type
	DistanceJoint_Init(&pj.distance)
	MotorJoint_Init(&pj.motor)
	MouseJoint_Init(&pj.mouse)
	PrismaticJoint_Init(&pj.prismatic)
	RevoluteJoint_Init(&pj.revolute)
	WeldJoint_Init(&pj.weld)
	WheelJoint_Init(&pj.wheel)
}

PhysicsJoint_GetId :: proc(pj: ^PhysicsJoint) -> b2.JointId {
	switch pj.type {
	case .Distance:  return pj.distance.jointId
	case .Filter:    return pj.filter.jointId
	case .Motor:     return pj.motor.jointId
	case .Mouse:     return pj.mouse.jointId
	case .Prismatic: return pj.prismatic.jointId
	case .Revolute:  return pj.revolute.jointId
	case .Weld:      return pj.weld.jointId
	case .Wheel:     return pj.wheel.jointId
	}
	return b2.nullJointId
}

PhysicsJoint_Create :: proc(pj: ^PhysicsJoint, worldId: b2.WorldId, bodyA, bodyB: b2.BodyId) {
	switch pj.type {
	case .Distance:  DistanceJoint_Create(&pj.distance, worldId, bodyA, bodyB)
	case .Filter:    FilterJoint_Create(&pj.filter, worldId, bodyA, bodyB)
	case .Motor:     MotorJoint_Create(&pj.motor, worldId, bodyA, bodyB)
	case .Mouse:     MouseJoint_Create(&pj.mouse, worldId, bodyA, bodyB)
	case .Prismatic: PrismaticJoint_Create(&pj.prismatic, worldId, bodyA, bodyB)
	case .Revolute:  RevoluteJoint_Create(&pj.revolute, worldId, bodyA, bodyB)
	case .Weld:      WeldJoint_Create(&pj.weld, worldId, bodyA, bodyB)
	case .Wheel:     WheelJoint_Create(&pj.wheel, worldId, bodyA, bodyB)
	}
}

PhysicsJoint_Sync :: proc(pj: ^PhysicsJoint) {
	switch pj.type {
	case .Distance:  DistanceJoint_Sync(&pj.distance)
	case .Filter:    // no tunable params
	case .Motor:     MotorJoint_Sync(&pj.motor)
	case .Mouse:     MouseJoint_Sync(&pj.mouse)
	case .Prismatic: PrismaticJoint_Sync(&pj.prismatic)
	case .Revolute:  RevoluteJoint_Sync(&pj.revolute)
	case .Weld:      WeldJoint_Sync(&pj.weld)
	case .Wheel:     WheelJoint_Sync(&pj.wheel)
	}
}

// PhysicsJoint_Destroy destroys its joint - of any type, so one made
// before the type changed goes too (#219).
PhysicsJoint_Destroy :: proc(pj: ^PhysicsJoint) {
	for id in ([?]b2.JointId{pj.distance.jointId, pj.filter.jointId, pj.motor.jointId, pj.mouse.jointId, pj.prismatic.jointId, pj.revolute.jointId, pj.weld.jointId, pj.wheel.jointId}) {
		if b2.Joint_IsValid(id) do b2.DestroyJoint(id)
	}
	pj.distance.jointId  = b2.nullJointId
	pj.filter.jointId    = b2.nullJointId
	pj.motor.jointId     = b2.nullJointId
	pj.mouse.jointId     = b2.nullJointId
	pj.prismatic.jointId = b2.nullJointId
	pj.revolute.jointId  = b2.nullJointId
	pj.weld.jointId      = b2.nullJointId
	pj.wheel.jointId     = b2.nullJointId
}

PhysicsJoint_DrawDebug :: proc(pj: ^PhysicsJoint, color := rl.GOLD) {
	id := PhysicsJoint_GetId(pj)
	if !b2.Joint_IsValid(id) do return

	bodyA := b2.Joint_GetBodyA(id)
	bodyB := b2.Joint_GetBodyB(id)
	if !b2.Body_IsValid(bodyA) || !b2.Body_IsValid(bodyB) do return

	pA := b2.Body_GetWorldPoint(bodyA, b2.Joint_GetLocalAnchorA(id))
	pB := b2.Body_GetWorldPoint(bodyB, b2.Joint_GetLocalAnchorB(id))

	px := Debug_PixelSize()
	rl.DrawLineEx(pA, pB, 2 * px, color)
	rl.DrawCircleV(pA, 4 * px, color)
	rl.DrawCircleV(pB, 4 * px, color)
}
