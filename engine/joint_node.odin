package engine

import "core:c"
import "core:strings"
import lua "lua54"
import b2 "vendor:box2d"
import rl "vendor:raylib"

// ============================================================================
// JointNode: a Box2D joint between two body nodes (static, dynamic or
// character mover) placed in the scene. Body A / Body B are paths from the
// joint ("" for Body A = the joint's parent). The joint is created once
// both bodies exist and follows its parameters (`joint.<type>.*`, edited in
// the Inspector, saved as properties, settable from Lua with
// node:set_property). Destroying either body destroys the joint; it's made
// again if the bodies come back.
//
// Scripts can change the bodies while the game runs (joint_set_bodies): a
// body given as a node is held by that node itself, not its path - spawned
// objects often share a name - and only for this run (not saved).
// ============================================================================

JointNode :: struct {
	using node: Node,
	joint:    PhysicsJoint `gui:"true"`,
	bodyA:    string, // path from this node ("" = parent)
	bodyB:    string,
	debugColor: rl.Color `gui:"true"`,
	synced:   PhysicsJoint, // the parameters last given to Box2D
	// Bodies set from a script as nodes (joint_set_bodies): used instead of
	// the path while set. Runtime only.
	liveA, liveB: JointLiveBody,
}

// JointLiveBody: a body node held by its live slot (nil once it's gone).
JointLiveBody :: struct {
	set:       bool,
	slot, gen: u32,
}

JointNode_Create :: proc(scene: ^Scene, name: string = "Joint", parent: ^Node = nil) -> ^JointNode {
	j := CreateNode(scene.manager, JointNode)
	j.name = strings.clone(name, j.allocator) // owned: callers pass temp strings too
	PhysicsJoint_Init(&j.joint, .Revolute)
	// Motors strong enough for pixel-scale bodies (a 40 px box weighs 1600).
	j.joint.revolute.maxMotorTorque = 5e6
	j.joint.wheel.maxMotorTorque = 5e6
	j.joint.prismatic.maxMotorForce = 1e5
	j.joint.distance.maxMotorForce = 1e5
	j.joint.motor.maxForce = 1e5
	j.joint.motor.maxTorque = 5e6
	j.debugColor = {250, 204, 21, 255}
	j.update = JointNode_Update
	j.render = JointNode_Render
	j.onDestroy = JointNode_Destroy
	scene->addNode(j, parent)
	return j
}

JointNode_SetBodies :: proc(j: ^JointNode, a, b: string) {
	j.bodyA = strings.clone(a, j.allocator)
	j.bodyB = strings.clone(b, j.allocator)
	j.liveA, j.liveB = {}, {}
	PhysicsJoint_Destroy(&j.joint) // made again with the new bodies
}

// JointBodyArg: one body for JointNode_SetBody - a node (held by the node
// itself), a path from the joint, or nothing (Body A: the parent; Body B:
// none, so the joint lets go).
JointBodyArg :: union {^Node, string}

// JointNode_SetBody sets Body A (`b` false) or Body B while the game runs;
// the joint is made again with it on the next update.
JointNode_SetBody :: proc(j: ^JointNode, b: bool, body: JointBodyArg) {
	live := &j.liveB if b else &j.liveA
	path := &j.bodyB if b else &j.bodyA
	live^ = {}
	switch v in body {
	case ^Node:
		slot, gen := Node_SlotOf(v)
		live^ = {set = true, slot = slot, gen = gen}
		path^ = ""
	case string:
		path^ = strings.clone(v, j.allocator)
	case nil:
		path^ = ""
	}
	PhysicsJoint_Destroy(&j.joint)
}

@(private = "file")
joint_manager :: proc(j: ^JointNode, ctx: ^GameContext) -> ^NodeManager {
	gc := ctx if ctx != nil else j.gameContext
	if gc == nil || gc.scene == nil do return nil
	return gc.scene.manager
}

// JointNode_Bodies: the nodes the joint connects (nil when missing).
JointNode_Bodies :: proc(j: ^JointNode, mgr: ^NodeManager) -> (a, b: ^Node) {
	if mgr == nil do return nil, nil
	if j.liveA.set do a = Node_FromSlot(j.liveA.slot, j.liveA.gen)
	else do a = GetParent(mgr, j) if j.bodyA == "" else Node_ResolvePath(mgr, j, j.bodyA)
	if j.liveB.set do b = Node_FromSlot(j.liveB.slot, j.liveB.gen)
	else if j.bodyB != "" do b = Node_ResolvePath(mgr, j, j.bodyB)
	return
}

// JointNode_IsActive: the Box2D joint exists.
JointNode_IsActive :: proc(j: ^JointNode) -> bool {
	return b2.Joint_IsValid(PhysicsJoint_GetId(&j.joint))
}

JointNode_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	j := cast(^JointNode)node
	// A new type: the old type's joint goes (made again below) (#219).
	if j.joint.type != j.synced.type {
		PhysicsJoint_Destroy(&j.joint)
		j.synced.type = j.joint.type
	}
	if JointNode_IsActive(j) {
		// Parameters edited live (Inspector, scripts): apply and wake the
		// bodies (a resting body sleeps and wouldn't react).
		if j.joint != j.synced {
			PhysicsJoint_Sync(&j.joint)
			id := PhysicsJoint_GetId(&j.joint)
			b2.Body_SetAwake(b2.Joint_GetBodyA(id), true)
			b2.Body_SetAwake(b2.Joint_GetBodyB(id), true)
			j.synced = j.joint
		}
		return
	}
	gc := ctx if ctx != nil else j.gameContext
	if gc == nil || gc.game == nil do return
	a, b := JointNode_Bodies(j, joint_manager(j, ctx))
	ba, bb := Physics_BodyOf(a), Physics_BodyOf(b)
	if a == b || !b2.Body_IsValid(ba) || !b2.Body_IsValid(bb) do return
	PhysicsJoint_Create(&j.joint, gc.game.physicsWorld.worldId, ba, bb)
	j.synced = j.joint
}

JointNode_Render :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	j := cast(^JointNode)node
	if !rl.IsWindowReady() do return
	if ctx != nil && ctx.game != nil && !ctx.game.physicsWorld.drawPhysicsDebug do return
	if JointNode_IsActive(j) {
		PhysicsJoint_DrawDebug(&j.joint, j.debugColor)
		return
	}
	// Not running (the editor): a line between the bodies' anchors.
	a, b := JointNode_Bodies(j, joint_manager(j, ctx))
	if a == nil || b == nil do return
	pa := a.globalPosition + rotate_vec(joint_anchor(&j.joint, true), a.globalRotation)
	pb := b.globalPosition + rotate_vec(joint_anchor(&j.joint, false), b.globalRotation)
	px := Debug_PixelSize()
	rl.DrawLineEx(pa, pb, 2 * px, j.debugColor)
	rl.DrawCircleV(pa, 4 * px, j.debugColor)
	rl.DrawCircleV(pb, 4 * px, j.debugColor)
}

// joint_anchor: the local anchor on body A or B for the joint's type.
@(private = "file")
joint_anchor :: proc(pj: ^PhysicsJoint, a: bool) -> [2]f32 {
	switch pj.type {
	case .Distance:  return pj.distance.localAnchorA if a else pj.distance.localAnchorB
	case .Prismatic: return pj.prismatic.localAnchorA if a else pj.prismatic.localAnchorB
	case .Revolute:  return pj.revolute.localAnchorA if a else pj.revolute.localAnchorB
	case .Weld:      return pj.weld.localAnchorA if a else pj.weld.localAnchorB
	case .Wheel:     return pj.wheel.localAnchorA if a else pj.wheel.localAnchorB
	case .Filter, .Motor, .Mouse:
	}
	return {}
}

JointNode_Destroy :: proc(node: ^Node, ctx: ^GameContext) {
	j := cast(^JointNode)node
	PhysicsJoint_Destroy(&j.joint)
}

// JointType_FieldName: the `joint.<name>.` prefix of a type's parameters.
JointType_FieldName :: proc(t: PhysicsJointType) -> string {
	switch t {
	case .Distance:  return "distance"
	case .Filter:    return "filter"
	case .Motor:     return "motor"
	case .Mouse:     return "mouse"
	case .Prismatic: return "prismatic"
	case .Revolute:  return "revolute"
	case .Weld:      return "weld"
	case .Wheel:     return "wheel"
	}
	return ""
}

// ----------------------------------------------------------------------------
// Lua: joint_set_bodies / joint_get_bodies / joint_is_active
// ----------------------------------------------------------------------------

@(private = "file")
lua_joint :: proc(L: ^lua.State, fn: string) -> ^JointNode {
	n, ok := to_node_userdata(L, 1)
	if !ok || n.typeId != JointNode {
		Script_Problem(.Warning, "%s: called on %s, not a Joint", fn, n.name if ok && n != nil else "something that isn't a node")
		return nil
	}
	return cast(^JointNode)n
}

// joint_set_bodies(a, b): each a body node, a path from the joint, or nil
// (Body A: the parent; Body B: none - the joint lets go). False (nothing
// changes) for anything else.
@(private = "file")
lua_joint_set_bodies :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	j := lua_joint(L, "joint_set_bodies")
	if j == nil {
		lua.pushboolean(L, false)
		return 1
	}
	args: [2]JointBodyArg
	for i in 0 ..< 2 {
		idx := c.int(2 + i)
		#partial switch lua.type(L, idx) {
		case .NONE, .NIL:
		case .STRING:
			args[i] = string(lua.tostring(L, idx))
		case:
			n, ok := to_node_userdata(L, idx)
			if !ok || n == nil || !b2_is_body_node(n) {
				what := n.name if ok && n != nil else string(lua.typename(L, lua.type(L, idx)))
				Script_Problem(.Warning, "joint_set_bodies: body %s must be a physics body node, a path or nil (got %s; nothing changed)", "A" if i == 0 else "B", what)
				lua.pushboolean(L, false)
				return 1
			}
			args[i] = n
		}
	}
	JointNode_SetBody(j, false, args[0])
	JointNode_SetBody(j, true, args[1])
	lua.pushboolean(L, true)
	return 1
}

// joint_get_bodies(): the two body nodes (nil when missing).
@(private = "file")
lua_joint_get_bodies :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	j := lua_joint(L, "joint_get_bodies")
	a, b: ^Node
	if j != nil do a, b = JointNode_Bodies(j, joint_manager(j, nil))
	for n in ([2]^Node{a, b}) {
		if n != nil do push_node_userdata(L, n)
		else do lua.pushnil(L)
	}
	return 2
}

// joint_is_active(): the Box2D joint exists (both bodies found).
@(private = "file")
lua_joint_is_active :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	j := lua_joint(L, "joint_is_active")
	lua.pushboolean(L, b32(j != nil && JointNode_IsActive(j)))
	return 1
}

// Script_RegisterJointBindings: the node methods (on the node method table).
Script_RegisterJointBindings :: proc(L: ^lua.State) {
	lua.pushcfunction(L, lua_joint_set_bodies)
	lua.setfield(L, -2, "joint_set_bodies")
	lua.pushcfunction(L, lua_joint_get_bodies)
	lua.setfield(L, -2, "joint_get_bodies")
	lua.pushcfunction(L, lua_joint_is_active)
	lua.setfield(L, -2, "joint_is_active")
}
