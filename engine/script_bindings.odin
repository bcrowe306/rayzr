package engine

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:log"
import "core:math"
import "core:slice"
import os "osx"
import "core:reflect"
import "core:strings"
import "core:time"
import "core:encoding/uuid"
import lua "lua54"
import rl "vendor:raylib"
import b2 "vendor:box2d"

// ============================================================================
// Lua Engine API Bindings (Node, Input, Audio, Physics, Camera, Scene, Log, Engine)
// ============================================================================

NodeUserData :: struct {
	node:   ^Node,
	nodeId: uuid.Identifier,
	// The fast way back to the node (Node_FromSlot); the id is the truth
	// (a node rebuilt with the same id, e.g. a reloaded scene, is found again).
	slot, gen: u32,
}

// push_node_meta pushes the "Engine.Node" metatable (by a registry index
// kept in the script manager: no lookup by name).
push_node_meta :: proc(L: ^lua.State) {
	mgr := Script_Manager(L)
	if mgr == nil {
		lua.L_getmetatable(L, "Engine.Node")
		return
	}
	if mgr.nodeMetaRef == 0 {
		lua.L_getmetatable(L, "Engine.Node")
		if lua.isnil(L, -1) do return // (not registered yet)
		mgr.nodeMetaRef = lua.L_ref(L, lua.REGISTRYINDEX)
	}
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(mgr.nodeMetaRef))
}

push_node_userdata :: proc(L: ^lua.State, node: ^Node) {
	if node == nil || !Node_IsAlive(node) {
		lua.pushnil(L)
		return
	}
	ud := cast(^NodeUserData)lua.newuserdatauv(L, size_of(NodeUserData), 0)
	ud.node = node
	ud.nodeId = node.id
	ud.slot, ud.gen = Node_SlotOf(node)

	push_node_meta(L)
	lua.setmetatable(L, -2)
}

// to_node_userdata resolves a Lua node reference through the live-node
// registry by id, so references to destroyed nodes yield (nil, false)
// instead of reading freed memory.
to_node_userdata :: proc(L: ^lua.State, idx: c.int) -> (^Node, bool) {
	// (luaL_testudata, with the metatable by registry index.)
	ud := cast(^NodeUserData)lua.touserdata(L, idx)
	if ud == nil || lua.getmetatable(L, idx) == 0 do return nil, false
	push_node_meta(L)
	isNode := lua.rawequal(L, -1, -2)
	lua.pop(L, 2)
	if !isNode do return nil, false
	if n := Node_FromSlot(ud.slot, ud.gen); n != nil && n.id == ud.nodeId do return n, true
	node := Node_FromId(ud.nodeId)
	if node == nil do return nil, false
	ud.slot, ud.gen = Node_SlotOf(node) // (found again by id)
	return node, true
}

get_script_manager :: proc(L: ^lua.State) -> ^ScriptManager {
	return Script_Manager(L)
}

// ----------------------------------------------------------------------------
// Node Core & Hierarchy Bindings
// ----------------------------------------------------------------------------

@(private="file")
lua_node_get_type :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushstring(L, "Unknown")
		return 1
	}
	// A custom node type: its own name (get_base_type: the built-in one).
	name := Node_ClassName(node) if node.customType != "" && !node.customMissing else script_base_type_name(node)
	lua.pushstring(L, strings.clone_to_cstring(name, context.temp_allocator))
	return 1
}

// get_base_type(): the node's built-in type, also for custom node types.
lua_node_get_base_type :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushstring(L, "Unknown")
		return 1
	}
	lua.pushstring(L, strings.clone_to_cstring(script_base_type_name(node), context.temp_allocator))
	return 1
}

// is(type): the node's custom type, its built-in type, or "Node".
lua_node_is :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	name := lua.tostring(L, 2)
	lua.pushboolean(L, b32(ok && name != nil && (Node_Is(node, string(name)) || string(name) == script_base_type_name(node))))
	return 1
}

// script_base_type_name: the node's built-in type name (the registry's, as
// in scene files and Add Node).
@(private = "file")
script_base_type_name :: proc(node: ^Node) -> string {
	return Node_TypeName(node)
}

@(private="file")
lua_node_get_name :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushnil(L)
		return 1
	}
	nameC := strings.clone_to_cstring(node.name, context.temp_allocator)
	lua.pushstring(L, nameC)
	return 1
}

@(private="file")
lua_node_set_name :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	nameC := lua.tostring(L, 2)
	if nameC != nil {
		node.name = strings.clone(string(nameC), node.allocator)
	}
	return 0
}

@(private="file")
lua_node_get_position :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	lua.pushnumber(L, lua.Number(node.position.x))
	lua.pushnumber(L, lua.Number(node.position.y))
	return 2
}

@(private="file")
lua_node_set_position :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	x, y := arg_xy(L, 2) // two numbers or a vector
	node.position = {x, y}
	return 0
}

@(private="file")
lua_node_translate :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	dx, dy := arg_xy(L, 2) // two numbers or a vector
	node.position.x += dx
	node.position.y += dy
	return 0
}

@(private="file")
lua_node_get_rotation :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushnumber(L, 0)
		return 1
	}
	lua.pushnumber(L, lua.Number(node.rotation))
	return 1
}

@(private="file")
lua_node_set_rotation :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	rot := f32(lua.tonumber(L, 2))
	node.rotation = rot
	return 0
}

@(private="file")
lua_node_rotate :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	dRot := f32(lua.tonumber(L, 2))
	node.rotation += dRot
	return 0
}

@(private="file")
lua_node_get_scale :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushnumber(L, 1)
		lua.pushnumber(L, 1)
		return 2
	}
	lua.pushnumber(L, lua.Number(node.scale.x))
	lua.pushnumber(L, lua.Number(node.scale.y))
	return 2
}

@(private="file")
lua_node_set_scale :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	sx, sy := arg_xy(L, 2) // two numbers or a vector
	if lua.gettop(L) == 2 && lua.type(L, 2) == .NUMBER {
		sy = sx // (one number: uniform)
	}
	node.scale = {sx, sy}
	return 0
}

// node:get_node(path): a node by path relative to this one ("Gun",
// "../Player", "." self); nil if missing.
@(private="file")
lua_node_get_node :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.gameContext == nil || node.gameContext.scene == nil || lua.type(L, 2) != .STRING {
		lua.pushnil(L)
		return 1
	}
	path := string(lua.tostring(L, 2))
	found := Node_ResolvePath(node.gameContext.scene.manager, node, path)
	if found == nil do script_warn_once(L, path, "get_node: no node at \"%s\" from %s", path, node.name)
	push_node_userdata(L, found)
	return 1
}

// node:set_texture(path): a TextureNode shows another image (project path).
@(private="file")
lua_node_set_texture :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || (node.typeId != TextureNode && node.typeId != AtlasSpriteNode) || lua.type(L, 2) != .STRING {
		lua.pushboolean(L, false)
		return 1
	}
	tn := cast(^TextureNode)node
	rm := Node_ResourceManager(node)
	ctx := node.gameContext
	// (A node made this frame - Scene.create_node - joins the game at the
	// end of the frame: the script's game has what it needs.)
	if rm == nil || ctx == nil {
		if sm := get_script_manager(L); sm != nil && sm.game != nil {
			rm = &sm.game.resourceManager
			ctx = &sm.game.gameContext
		}
	}
	path := string(lua.tostring(L, 2))
	if Viewport_IsPath(path) && node.typeId == TextureNode {
		// A Viewport's picture ("viewport:<name>"; viewport_node.odin).
		TextureNode_SetTexture(tn, nil)
		tn.filePath = strings.clone(path, tn.allocator)
		if _, v := Viewport_TextureByPath(ctx, path); v != nil do tn.size = v.size
		lua.pushboolean(L, true)
		return 1
	}
	if rm == nil {
		lua.pushboolean(L, false)
		return 1
	}
	tex, loaded := rm.loadTexture(rm, Project_ResolveAssetPath(ctx, path))
	if loaded && tex != nil {
		if node.typeId == AtlasSpriteNode {
			an := cast(^AtlasSpriteNode)node
			AtlasSpriteNode_SetTexture(an, tex)
			an.filePath = strings.clone(path, an.allocator)
		} else {
			TextureNode_SetTexture(tn, tex)
			tn.filePath = strings.clone(path, tn.allocator)
			tn.size = Texture_Size(tex)
		}
	}
	lua.pushboolean(L, b32(loaded))
	return 1
}

@(private="file")
lua_node_get_global_position :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	lua.pushnumber(L, lua.Number(node.globalPosition.x))
	lua.pushnumber(L, lua.Number(node.globalPosition.y))
	return 2
}

@(private="file")
lua_node_get_global_rotation :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushnumber(L, 0)
		return 1
	}
	lua.pushnumber(L, lua.Number(node.globalRotation))
	return 1
}

@(private="file")
lua_node_is_enabled :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushboolean(L, false)
		return 1
	}
	lua.pushboolean(L, b32(node.enabled))
	return 1
}

@(private="file")
lua_node_set_enabled :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	enabled := lua.toboolean(L, 2)
	node.enabled = bool(enabled)
	return 0
}

@(private="file")
lua_node_is_visible :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushboolean(L, false)
		return 1
	}
	lua.pushboolean(L, b32(node.renderable))
	return 1
}

@(private="file")
lua_node_set_visible :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	visible := lua.toboolean(L, 2)
	node.renderable = bool(visible)
	return 0
}

@(private="file")
lua_node_get_component :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.componentPath == "" {
		lua.pushnil(L)
		return 1
	}
	nameC := strings.clone_to_cstring(node.componentPath, context.temp_allocator)
	lua.pushstring(L, nameC)
	return 1
}

@(private="file")
lua_node_get_instance_root :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.gameContext == nil || node.gameContext.scene == nil || node.gameContext.scene.manager == nil {
		lua.pushnil(L)
		return 1
	}
	root := Node_ComponentRoot(node.gameContext.scene.manager, node)
	push_node_userdata(L, root)
	return 1
}

@(private="file")
lua_node_get_parent :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.gameContext == nil || node.gameContext.scene == nil {
		lua.pushnil(L)
		return 1
	}
	parent := GetParent(node.gameContext.scene.manager, node)
	push_node_userdata(L, parent)
	return 1
}

@(private="file")
lua_node_get_children :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.gameContext == nil || node.gameContext.scene == nil {
		lua.newtable(L)
		return 1
	}
	children := GetChildren(node.gameContext.scene.manager, node)
	defer delete(children)

	lua.createtable(L, c.int(len(children)), 0)
	for child, i in children {
		push_node_userdata(L, child)
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

@(private="file")
lua_node_get_child :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.gameContext == nil || node.gameContext.scene == nil {
		lua.pushnil(L)
		return 1
	}
	nameC := lua.tostring(L, 2)
	if nameC == nil {
		lua.pushnil(L)
		return 1
	}
	targetName := string(nameC)
	children := GetChildren(node.gameContext.scene.manager, node)
	defer delete(children)

	for child in children {
		if child.name == targetName {
			push_node_userdata(L, child)
			return 1
		}
	}
	lua.pushnil(L)
	return 1
}

@(private="file")
lua_node_add_child :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	parent, okP := to_node_userdata(L, 1)
	child, okC := to_node_userdata(L, 2)
	if okP && okC && parent.gameContext != nil && parent.gameContext.scene != nil {
		SceneAddChild(parent.gameContext.scene, parent, child)
	}
	return 0
}

@(private="file")
lua_node_remove_child :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	parent, okP := to_node_userdata(L, 1)
	child, okC := to_node_userdata(L, 2)
	if okP && okC && parent.gameContext != nil && parent.gameContext.scene != nil {
		SceneRemoveChild(parent.gameContext.scene, parent, child)
	}
	return 0
}

@(private="file")
lua_node_destroy :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if ok && node.gameContext != nil && node.gameContext.scene != nil {
		SceneRemoveNode(node.gameContext.scene, node)
	}
	return 0
}

// ----------------------------------------------------------------------------
// Physics: DynamicBodyNode Methods
// ----------------------------------------------------------------------------

@(private="file")
lua_node_apply_force :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	fx, fy := arg_xy(L, 2) // two numbers or a vector

	if node.typeId == DynamicBodyNode {
		dynBody := cast(^DynamicBodyNode)node
		if dynBody.bodyId.index1 != 0 {
			DynamicBodyNode_ApplyForce(dynBody, [2]f32{fx, fy})
		}
	}
	return 0
}

@(private="file")
lua_node_apply_impulse :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	ix, iy := arg_xy(L, 2) // two numbers or a vector

	if node.typeId == DynamicBodyNode {
		dynBody := cast(^DynamicBodyNode)node
		if dynBody.bodyId.index1 != 0 {
			DynamicBodyNode_ApplyImpulse(dynBody, [2]f32{ix, iy})
		}
	}
	return 0
}

// node:get_mass(): a dynamic body's mass (density x area in px^2; #219), 0
// when it has no body yet.
@(private="file")
lua_node_get_mass :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	mass: f32
	if ok && node.typeId == DynamicBodyNode {
		if id := (cast(^DynamicBodyNode)node).bodyId; b2.Body_IsValid(id) do mass = b2.Body_GetMass(id)
	}
	lua.pushnumber(L, lua.Number(mass))
	return 1
}

@(private="file")
lua_node_get_linear_velocity :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	if node.typeId == DynamicBodyNode {
		dynBody := cast(^DynamicBodyNode)node
		vel := b2.Body_GetLinearVelocity(dynBody.bodyId) if dynBody.bodyId.index1 != 0 && b2.Body_IsValid(dynBody.bodyId) else dynBody.linearVelocity
		lua.pushnumber(L, lua.Number(vel.x))
		lua.pushnumber(L, lua.Number(vel.y))
		return 2
	} else if node.typeId == KinematicBodyNode {
		kb := cast(^KinematicBodyNode)node
		vel := b2.Body_GetLinearVelocity(kb.bodyId) if kb.bodyId.index1 != 0 && b2.Body_IsValid(kb.bodyId) else kb.linearVelocity
		lua.pushnumber(L, lua.Number(vel.x))
		lua.pushnumber(L, lua.Number(vel.y))
		return 2
	} else if node.typeId == CharacterMoverNode {
		cm := cast(^CharacterMoverNode)node
		lua.pushnumber(L, lua.Number(cm.velocity.x))
		lua.pushnumber(L, lua.Number(cm.velocity.y))
		return 2
	}
	lua.pushnumber(L, 0)
	lua.pushnumber(L, 0)
	return 2
}

@(private="file")
lua_node_set_linear_velocity :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	vx, vy := arg_xy(L, 2) // two numbers or a vector
	if node.typeId == DynamicBodyNode {
		dynBody := cast(^DynamicBodyNode)node
		dynBody.linearVelocity = {vx, vy}
		dynBody.lastSyncedVel = {vx, vy}
		if dynBody.bodyId.index1 != 0 && b2.Body_IsValid(dynBody.bodyId) {
			b2.Body_SetLinearVelocity(dynBody.bodyId, [2]f32{vx, vy})
			b2.Body_SetAwake(dynBody.bodyId, true)
		}
	} else if node.typeId == KinematicBodyNode {
		kb := cast(^KinematicBodyNode)node
		kb.linearVelocity = {vx, vy}
		kb.lastSyncedVel = {vx, vy}
		if kb.bodyId.index1 != 0 && b2.Body_IsValid(kb.bodyId) {
			b2.Body_SetLinearVelocity(kb.bodyId, [2]f32{vx, vy})
		}
	} else if node.typeId == CharacterMoverNode {
		cm := cast(^CharacterMoverNode)node
		cm.velocity = {vx, vy}
	}
	return 0
}

@(private="file")
lua_node_get_angular_velocity :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushnumber(L, 0)
		return 1
	}
	if node.typeId == DynamicBodyNode {
		dynBody := cast(^DynamicBodyNode)node
		w := math.to_degrees(b2.Body_GetAngularVelocity(dynBody.bodyId)) if dynBody.bodyId.index1 != 0 && b2.Body_IsValid(dynBody.bodyId) else dynBody.angularVelocity
		lua.pushnumber(L, lua.Number(w))
		return 1
	} else if node.typeId == KinematicBodyNode {
		kb := cast(^KinematicBodyNode)node
		w := math.to_degrees(b2.Body_GetAngularVelocity(kb.bodyId)) if kb.bodyId.index1 != 0 && b2.Body_IsValid(kb.bodyId) else kb.angularVelocity
		lua.pushnumber(L, lua.Number(w))
		return 1
	}
	lua.pushnumber(L, 0)
	return 1
}

@(private="file")
lua_node_set_angular_velocity :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	w := f32(lua.tonumber(L, 2))
	if node.typeId == DynamicBodyNode {
		dynBody := cast(^DynamicBodyNode)node
		dynBody.angularVelocity = w
		dynBody.lastSyncedAngVel = w
		if dynBody.bodyId.index1 != 0 && b2.Body_IsValid(dynBody.bodyId) {
			b2.Body_SetAngularVelocity(dynBody.bodyId, math.to_radians(w))
			b2.Body_SetAwake(dynBody.bodyId, true)
		}
	} else if node.typeId == KinematicBodyNode {
		kb := cast(^KinematicBodyNode)node
		kb.angularVelocity = w
		kb.lastSyncedAngVel = w
		if kb.bodyId.index1 != 0 && b2.Body_IsValid(kb.bodyId) {
			b2.Body_SetAngularVelocity(kb.bodyId, math.to_radians(w))
		}
	}
	return 0
}

@(private="file")
lua_node_get_gravity_scale :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushnumber(L, 1)
		return 1
	}
	if node.typeId == DynamicBodyNode {
		db := cast(^DynamicBodyNode)node
		lua.pushnumber(L, lua.Number(db.gravityScale))
		return 1
	} else if node.typeId == CharacterMoverNode {
		cm := cast(^CharacterMoverNode)node
		lua.pushnumber(L, lua.Number(cm.gravityScale))
		return 1
	}
	lua.pushnumber(L, 1)
	return 1
}

@(private="file")
lua_node_set_gravity_scale :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	scale := f32(lua.tonumber(L, 2))
	if node.typeId == DynamicBodyNode {
		db := cast(^DynamicBodyNode)node
		db.gravityScale = scale
		if b2.Body_IsValid(db.bodyId) {
			b2.Body_SetGravityScale(db.bodyId, scale)
		}
	} else if node.typeId == CharacterMoverNode {
		cm := cast(^CharacterMoverNode)node
		cm.gravityScale = scale
	}
	return 0
}

@(private="file")
lua_node_is_fixed_rotation :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushboolean(L, false)
		return 1
	}
	if node.typeId == DynamicBodyNode {
		db := cast(^DynamicBodyNode)node
		lua.pushboolean(L, b32(db.fixedRotation))
		return 1
	}
	lua.pushboolean(L, false)
	return 1
}

@(private="file")
lua_node_set_fixed_rotation :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	fixed := lua.toboolean(L, 2)
	if node.typeId == DynamicBodyNode {
		db := cast(^DynamicBodyNode)node
		db.fixedRotation = bool(fixed)
		if b2.Body_IsValid(db.bodyId) {
			b2.Body_SetFixedRotation(db.bodyId, bool(fixed))
		}
	}
	return 0
}

@(private="file")
lua_node_set_linear_damping :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	damping := f32(lua.tonumber(L, 2))
	if node.typeId == DynamicBodyNode {
		db := cast(^DynamicBodyNode)node
		db.linearDamping = damping
		if b2.Body_IsValid(db.bodyId) {
			b2.Body_SetLinearDamping(db.bodyId, damping)
		}
	}
	return 0
}

@(private="file")
lua_node_set_angular_damping :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	damping := f32(lua.tonumber(L, 2))
	if node.typeId == DynamicBodyNode {
		db := cast(^DynamicBodyNode)node
		db.angularDamping = damping
		if b2.Body_IsValid(db.bodyId) {
			b2.Body_SetAngularDamping(db.bodyId, damping)
		}
	}
	return 0
}

@(private="file")
lua_node_is_awake :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushboolean(L, false)
		return 1
	}
	if node.typeId == DynamicBodyNode {
		db := cast(^DynamicBodyNode)node
		if b2.Body_IsValid(db.bodyId) {
			lua.pushboolean(L, b32(b2.Body_IsAwake(db.bodyId)))
			return 1
		}
	}
	lua.pushboolean(L, false)
	return 1
}

@(private="file")
lua_node_set_awake :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	awake := lua.toboolean(L, 2)
	if node.typeId == DynamicBodyNode {
		db := cast(^DynamicBodyNode)node
		if b2.Body_IsValid(db.bodyId) {
			b2.Body_SetAwake(db.bodyId, bool(awake))
		}
	}
	return 0
}

// ----------------------------------------------------------------------------
// Physics: CharacterMoverNode Methods
// ----------------------------------------------------------------------------

@(private="file")
lua_node_character_move :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CharacterMoverNode do return 0
	dirX := f32(lua.tonumber(L, 2))
	jump := lua.toboolean(L, 3)

	cm := cast(^CharacterMoverNode)node
	cm.targetSpeedX = dirX * cm.maxSpeed
	if jump && cm.isGrounded {
		cm.velocity.y = -cm.jumpSpeed
		cm.isGrounded = false
	}
	return 0
}

@(private="file")
lua_node_character_is_grounded :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CharacterMoverNode {
		lua.pushboolean(L, false)
		return 1
	}
	cm := cast(^CharacterMoverNode)node
	lua.pushboolean(L, b32(cm.isGrounded))
	return 1
}

@(private="file")
lua_node_character_get_velocity :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CharacterMoverNode {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	cm := cast(^CharacterMoverNode)node
	lua.pushnumber(L, lua.Number(cm.velocity.x))
	lua.pushnumber(L, lua.Number(cm.velocity.y))
	return 2
}

@(private="file")
lua_node_character_set_velocity :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CharacterMoverNode do return 0
	vx, vy := arg_xy(L, 2) // two numbers or a vector
	cm := cast(^CharacterMoverNode)node
	cm.velocity = {vx, vy}
	return 0
}

@(private="file")
lua_node_character_set_speed :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CharacterMoverNode do return 0
	spd := f32(lua.tonumber(L, 2))
	cm := cast(^CharacterMoverNode)node
	cm.maxSpeed = spd
	return 0
}

@(private="file")
lua_node_character_set_jump_speed :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CharacterMoverNode do return 0
	jspd := f32(lua.tonumber(L, 2))
	cm := cast(^CharacterMoverNode)node
	cm.jumpSpeed = jspd
	return 0
}

@(private="file")
lua_node_character_get_player_index :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CharacterMoverNode {
		lua.pushinteger(L, 0)
		return 1
	}
	cm := cast(^CharacterMoverNode)node
	lua.pushinteger(L, lua.Integer(cm.playerIndex))
	return 1
}

@(private="file")
lua_node_character_set_player_index :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CharacterMoverNode do return 0
	idx := int(lua.tointeger(L, 2))
	cm := cast(^CharacterMoverNode)node
	cm.playerIndex = clamp(idx, 0, MAX_PLAYERS)
	return 0
}

@(private="file")
mover_arg :: proc(L: ^lua.State) -> ^CharacterMoverNode {
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CharacterMoverNode do return nil
	return cast(^CharacterMoverNode)node
}

// character_move_and_slide([dt]) -> collided: moves by the velocity, sliding
// along surfaces (Godot's move_and_slide). The node switches to Script mode.
@(private="file")
lua_node_character_move_and_slide :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cm := mover_arg(L)
	if cm == nil {
		lua.pushboolean(L, false)
		return 1
	}
	cm.controlMode = .Script
	dt := f32(lua.tonumber(L, 2)) if lua.type(L, 2) == .NUMBER else cm.frameDelta
	ctx := cm.gameContext
	lua.pushboolean(L, b32(CharacterMoverNode_MoveAndSlide(cm, ctx, dt)))
	return 1
}

@(private="file")
lua_node_character_contact :: proc(L: ^lua.State, which: int) -> c.int {
	cm := mover_arg(L)
	v := false
	if cm != nil {
		switch which {
		case 0: v = cm.isOnFloor
		case 1: v = cm.isOnWall
		case 2: v = cm.isOnCeiling
		}
	}
	lua.pushboolean(L, b32(v))
	return 1
}

@(private="file")
lua_node_character_is_on_floor :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	return lua_node_character_contact(L, 0)
}

@(private="file")
lua_node_character_is_on_wall :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	return lua_node_character_contact(L, 1)
}

@(private="file")
lua_node_character_is_on_ceiling :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	return lua_node_character_contact(L, 2)
}

@(private="file")
push_vec :: proc(L: ^lua.State, v: [2]f32) -> c.int {
	lua.pushnumber(L, lua.Number(v.x))
	lua.pushnumber(L, lua.Number(v.y))
	return 2
}

@(private="file")
lua_node_character_get_floor_normal :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cm := mover_arg(L)
	return push_vec(L, cm.floorNormal if cm != nil else {})
}

@(private="file")
lua_node_character_get_wall_normal :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cm := mover_arg(L)
	return push_vec(L, cm.wallNormal if cm != nil else {})
}

@(private="file")
lua_node_character_get_last_motion :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cm := mover_arg(L)
	return push_vec(L, cm.lastMotion if cm != nil else {})
}

@(private="file")
lua_node_character_get_gravity :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cm := mover_arg(L)
	return push_vec(L, CharacterMoverNode_Gravity(cm, cm.gameContext) if cm != nil else {})
}

@(private="file")
lua_node_character_set_gravity_scale :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if cm := mover_arg(L); cm != nil do cm.gravityScale = f32(lua.tonumber(L, 2))
	return 0
}

// character_set_control_mode("script" | "builtin")
@(private="file")
lua_node_character_set_control_mode :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if cm := mover_arg(L); cm != nil && lua.type(L, 2) == .STRING {
		cm.controlMode = .BuiltIn if string(lua.tostring(L, 2)) == "builtin" else .Script
	}
	return 0
}

// ----------------------------------------------------------------------------
// Physics: AreaNode (Sensors)
// ----------------------------------------------------------------------------

@(private="file")
lua_node_area_is_overlapping :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AreaNode {
		lua.pushboolean(L, false)
		return 1
	}
	area := cast(^AreaNode)node
	lua.pushboolean(L, b32(area.hasOverlaps))
	return 1
}

@(private="file")
lua_node_area_get_overlap_count :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AreaNode {
		lua.pushinteger(L, 0)
		return 1
	}
	area := cast(^AreaNode)node
	lua.pushinteger(L, lua.Integer(area.overlapCount))
	return 1
}

@(private="file")
lua_node_area_get_overlapping_nodes :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AreaNode {
		lua.newtable(L)
		return 1
	}
	area := cast(^AreaNode)node
	lua.createtable(L, c.int(len(area.overlappingNodes)), 0)
	for other, i in area.overlappingNodes {
		push_node_userdata(L, other)
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

@(private="file")
lua_node_area_set_monitoring :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AreaNode do return 0
	AreaNode_SetMonitoring(cast(^AreaNode)node, bool(lua.toboolean(L, 2)))
	return 0
}

@(private="file")
lua_node_area_is_monitoring :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AreaNode {
		lua.pushboolean(L, false)
		return 1
	}
	lua.pushboolean(L, b32(AreaNode_IsMonitoring(cast(^AreaNode)node)))
	return 1
}

// ----------------------------------------------------------------------------
// Physics: RaycastNode
// ----------------------------------------------------------------------------

@(private="file")
lua_node_raycast_cast :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	sm := get_script_manager(L)
	if !ok || node.typeId != RaycastNode || sm == nil || sm.game == nil do return 0
	rc := cast(^RaycastNode)node
	RaycastNode_CastNow(rc, sm.game.physicsWorld.worldId)
	return 0
}

@(private="file")
lua_node_raycast_is_colliding :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != RaycastNode {
		lua.pushboolean(L, false)
		return 1
	}
	rc := cast(^RaycastNode)node
	lua.pushboolean(L, b32(rc.isColliding))
	return 1
}

@(private="file")
lua_node_raycast_get_hit_point :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != RaycastNode {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	rc := cast(^RaycastNode)node
	lua.pushnumber(L, lua.Number(rc.hitPoint.x))
	lua.pushnumber(L, lua.Number(rc.hitPoint.y))
	return 2
}

@(private="file")
lua_node_raycast_get_hit_normal :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != RaycastNode {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	rc := cast(^RaycastNode)node
	lua.pushnumber(L, lua.Number(rc.hitNormal.x))
	lua.pushnumber(L, lua.Number(rc.hitNormal.y))
	return 2
}

@(private="file")
lua_node_raycast_get_hit_fraction :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != RaycastNode {
		lua.pushnumber(L, 1)
		return 1
	}
	rc := cast(^RaycastNode)node
	lua.pushnumber(L, lua.Number(rc.hitFraction))
	return 1
}

@(private="file")
lua_node_raycast_get_hit_node :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != RaycastNode {
		lua.pushnil(L)
		return 1
	}
	rc := cast(^RaycastNode)node
	push_node_userdata(L, rc.hitNode)
	return 1
}

@(private="file")
lua_node_raycast_set_direction :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != RaycastNode do return 0
	dx, dy := arg_xy(L, 2) // two numbers or a vector
	rc := cast(^RaycastNode)node
	rc.direction = {dx, dy}
	return 0
}

@(private="file")
lua_node_raycast_set_length :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != RaycastNode do return 0
	lenVal := f32(lua.tonumber(L, 2))
	rc := cast(^RaycastNode)node
	rc.length = lenVal
	return 0
}

@(private="file")
lua_node_raycast_set_monitoring :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != RaycastNode do return 0
	RaycastNode_SetMonitoring(cast(^RaycastNode)node, bool(lua.toboolean(L, 2)))
	return 0
}

@(private="file")
lua_node_raycast_is_monitoring :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != RaycastNode {
		lua.pushboolean(L, false)
		return 1
	}
	lua.pushboolean(L, b32(RaycastNode_IsMonitoring(cast(^RaycastNode)node)))
	return 1
}

// ----------------------------------------------------------------------------
// Particle Emitter Methods
// ----------------------------------------------------------------------------

@(private="file")
lua_node_particle_start :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != ParticleEmitterNode do return 0
	pen := cast(^ParticleEmitterNode)node
	ParticleEmitterNode_Start(pen)
	return 0
}

@(private="file")
lua_node_particle_stop :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != ParticleEmitterNode do return 0
	pen := cast(^ParticleEmitterNode)node
	ParticleEmitterNode_Stop(pen)
	return 0
}

@(private="file")
lua_node_particle_is_emitting :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != ParticleEmitterNode {
		lua.pushboolean(L, false)
		return 1
	}
	pen := cast(^ParticleEmitterNode)node
	lua.pushboolean(L, b32(pen.emitter.emitting))
	return 1
}

@(private="file")
lua_node_particle_set_amount :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != ParticleEmitterNode do return 0
	amount := int(lua.tointeger(L, 2))
	pen := cast(^ParticleEmitterNode)node
	pen.emitter.amount = amount
	return 0
}

@(private="file")
lua_node_particle_set_lifetime :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != ParticleEmitterNode do return 0
	lifetime := f32(lua.tonumber(L, 2))
	pen := cast(^ParticleEmitterNode)node
	pen.emitter.lifetime = lifetime
	return 0
}

// particle_emit(n): n particles now (a burst on demand; #128).
@(private="file")
lua_node_particle_emit :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != ParticleEmitterNode do return 0
	ParticleEmitterNode_EmitBurst(cast(^ParticleEmitterNode)node, int(lua.L_optinteger(L, 2, 1)))
	return 0
}

// particle_restart(): clears the particles and starts again.
@(private="file")
lua_node_particle_restart :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != ParticleEmitterNode do return 0
	ParticleEmitter_Restart(&(cast(^ParticleEmitterNode)node).emitter)
	return 0
}

// particle_apply_preset(name) -> boolean: a preset look (fire, smoke, sparks,
// rain, snow, explosion, magic); false for an unknown name.
@(private="file")
lua_node_particle_apply_preset :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	preset, known := ParticlePreset_Parse(string(lua.L_checkstring(L, 2)))
	if !ok || node.typeId != ParticleEmitterNode || !known {
		lua.pushboolean(L, false)
		return 1
	}
	ParticleEmitter_ApplyPreset(&(cast(^ParticleEmitterNode)node).emitter, preset)
	lua.pushboolean(L, true)
	return 1
}

// particle_get_alive_count() -> integer
@(private="file")
lua_node_particle_get_alive_count :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != ParticleEmitterNode do return 0
	n := 0
	for p in (cast(^ParticleEmitterNode)node).emitter.particles do if p.alive do n += 1
	lua.pushinteger(L, lua.Integer(n))
	return 1
}

// particle_set_texture(path): the particles' texture ("" or nil: none; #126).
@(private="file")
lua_node_particle_set_texture :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != ParticleEmitterNode do return 0
	path := string(lua.tostring(L, 2)) if lua.isstring(L, 2) else ""
	ParticleEmitterNode_SetTexture(cast(^ParticleEmitterNode)node, path)
	return 0
}

// particle_get_last_hit -> x, y, nx, ny, node: where the last particle hit
// a body (nil when none has yet; #123).
@(private="file")
lua_node_particle_get_last_hit :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != ParticleEmitterNode do return 0
	em := &(cast(^ParticleEmitterNode)node).emitter
	if em.lastHitNormal == {} {
		lua.pushnil(L)
		return 1
	}
	lua.pushnumber(L, lua.Number(em.lastHitPoint.x))
	lua.pushnumber(L, lua.Number(em.lastHitPoint.y))
	lua.pushnumber(L, lua.Number(em.lastHitNormal.x))
	lua.pushnumber(L, lua.Number(em.lastHitNormal.y))
	if em.lastHitNode != nil && Node_IsAlive(em.lastHitNode) do push_node_userdata(L, em.lastHitNode)
	else do lua.pushnil(L)
	return 5
}


@(private="file")
lua_node_atlas_set_region :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AtlasSpriteNode do return 0
	x := f32(lua.tonumber(L, 2))
	y := f32(lua.tonumber(L, 3))
	w := f32(lua.tonumber(L, 4))
	h := f32(lua.tonumber(L, 5))
	an := cast(^AtlasSpriteNode)node
	AtlasSpriteNode_SetRegion(an, {x, y, w, h})
	return 0
}

@(private="file")
lua_node_atlas_get_region :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AtlasSpriteNode {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 4
	}
	an := cast(^AtlasSpriteNode)node
	lua.pushnumber(L, lua.Number(an.region.x))
	lua.pushnumber(L, lua.Number(an.region.y))
	lua.pushnumber(L, lua.Number(an.region.width))
	lua.pushnumber(L, lua.Number(an.region.height))
	return 4
}

// ----------------------------------------------------------------------------
// TextureNode Methods
// ----------------------------------------------------------------------------

@(private="file")
lua_node_texture_get_size :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || (node.typeId != TextureNode && node.typeId != AtlasSpriteNode) {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	_, size := texture_node_fields(node)
	lua.pushnumber(L, lua.Number(size.x))
	lua.pushnumber(L, lua.Number(size.y))
	return 2
}

// texture_node_fields: a TextureNode's or AtlasSprite's path and drawn size
// - each read from its own struct (#221: they used to share a cast).
@(private="file")
texture_node_fields :: proc(node: ^Node) -> (path: string, size: [2]f32) {
	if node.typeId == TextureNode {
		tn := cast(^TextureNode)node
		return tn.filePath, tn.size
	}
	if node.typeId == AtlasSpriteNode {
		an := cast(^AtlasSpriteNode)node
		return an.filePath, an.size
	}
	return
}

@(private="file")
lua_node_texture_set_origin :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || (node.typeId != TextureNode && node.typeId != AtlasSpriteNode) do return 0
	ox, oy := arg_xy(L, 2) // two numbers or a vector
	_, size := texture_node_fields(node)
	Node_SetOriginPx(node, {ox, oy}, size) // pixels -> the node's origin
	return 0
}

@(private="file")
lua_node_texture_get_path :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || (node.typeId != TextureNode && node.typeId != AtlasSpriteNode) {
		lua.pushstring(L, "")
		return 1
	}
	path, _ := texture_node_fields(node)
	pathC := strings.clone_to_cstring(path, context.temp_allocator)
	lua.pushstring(L, pathC)
	return 1
}

// ----------------------------------------------------------------------------
// AnimationPlayerNode Methods
// ----------------------------------------------------------------------------

@(private="file")
lua_node_animation_play :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AnimationPlayerNode do return 0
	apn := cast(^AnimationPlayerNode)node
	// animation_play([name [, blend_seconds]]): blend crossfades property tracks.
	name := string(lua.tostring(L, 2)) if lua.type(L, 2) == .STRING else ""
	blend := f32(lua.tonumber(L, 3)) if lua.type(L, 3) == .NUMBER else 0
	if name != "" {
		// (#222) An unknown name changes nothing; the animation already
		// playing keeps going (paused: resumes) - safe to call every frame.
		index := -1
		for a, i in apn.animations do if a.name == name {index = i; break}
		if index < 0 {
			log.warnf("animation_play: no animation '%s' on %s", name, apn.name)
			return 0
		}
		if index == apn.animationIndex && apn.playing {
			if !apn.ticker.running do AnimationPlayerNode_Resume(apn)
			return 0
		}
	}
	AnimationPlayerNode_Play(apn, name, blend)
	return 0
}

@(private="file")
lua_node_animation_stop :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AnimationPlayerNode do return 0
	apn := cast(^AnimationPlayerNode)node
	AnimationPlayerNode_Stop(apn)
	return 0
}

@(private="file")
lua_node_animation_pause :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AnimationPlayerNode do return 0
	apn := cast(^AnimationPlayerNode)node
	AnimationPlayerNode_Pause(apn)
	return 0
}

@(private="file")
lua_node_animation_resume :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AnimationPlayerNode do return 0
	apn := cast(^AnimationPlayerNode)node
	AnimationPlayerNode_Resume(apn)
	return 0
}

@(private="file")
lua_node_animation_reset :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AnimationPlayerNode do return 0
	apn := cast(^AnimationPlayerNode)node
	AnimationPlayerNode_Reset(apn)
	return 0
}

@(private="file")
lua_node_animation_set_fps :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AnimationPlayerNode do return 0
	fps := f32(lua.tonumber(L, 2))
	apn := cast(^AnimationPlayerNode)node
	AnimationPlayerNode_SetFPS(apn, fps)
	return 0
}

@(private="file")
lua_node_animation_get_current :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AnimationPlayerNode {
		lua.pushstring(L, "")
		return 1
	}
	apn := cast(^AnimationPlayerNode)node
	nameStr := AnimationPlayerNode_GetAnimationName(apn)
	nameC := strings.clone_to_cstring(nameStr, context.temp_allocator)
	lua.pushstring(L, nameC)
	return 1
}

// ----------------------------------------------------------------------------
// VectorShapeNode Methods (vector_node.odin: part swapping)
// ----------------------------------------------------------------------------

@(private="file")
lua_node_vector_swap :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != VectorShapeNode || lua.type(L, 2) != .STRING {
		lua.pushboolean(L, false)
		return 1
	}
	lua.pushboolean(L, b32(VectorShapeNode_Swap(cast(^VectorShapeNode)node, string(lua.tostring(L, 2)))))
	return 1
}

@(private="file")
lua_node_vector_frames :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	lua.newtable(L)
	if !ok || node.typeId != VectorShapeNode do return 1
	for f, i in VectorShapeNode_Frames(cast(^VectorShapeNode)node) {
		lua.pushstring(L, strings.clone_to_cstring(f, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

@(private="file")
lua_node_lipsync_play :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != LipSyncNode {lua.pushboolean(L, false); return 1}
	l := cast(^LipSyncNode)node
	sound := string(lua.tostring(L, 2)) if lua.type(L, 2) == .STRING else l.sound
	lua.pushboolean(L, b32(LipSyncNode_Play(l, sound)))
	return 1
}

@(private="file")
lua_node_lipsync_stop :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if ok && node.typeId == LipSyncNode do LipSyncNode_Stop(cast(^LipSyncNode)node)
	return 0
}

@(private="file")
lua_node_lipsync_is_playing :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	lua.pushboolean(L, b32(ok && node.typeId == LipSyncNode && (cast(^LipSyncNode)node).playing))
	return 1
}

// ----------------------------------------------------------------------------
// TimerNode Methods
// ----------------------------------------------------------------------------

@(private="file")
lua_node_timer_start :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != TimerNode do return 0
	timer := cast(^TimerNode)node
	TimerNode_Start(timer)
	return 0
}

@(private="file")
lua_node_timer_stop :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != TimerNode do return 0
	timer := cast(^TimerNode)node
	timer.running = false
	return 0
}

@(private="file")
lua_node_timer_is_running :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != TimerNode {
		lua.pushboolean(L, false)
		return 1
	}
	timer := cast(^TimerNode)node
	lua.pushboolean(L, b32(timer.running))
	return 1
}

@(private="file")
lua_node_timer_get_elapsed :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != TimerNode {
		lua.pushnumber(L, 0)
		return 1
	}
	timer := cast(^TimerNode)node
	lua.pushnumber(L, lua.Number(time.duration_seconds(timer.elapsed)))
	return 1
}

@(private="file")
lua_node_timer_set_duration :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != TimerNode do return 0
	sec := f32(lua.tonumber(L, 2))
	timer := cast(^TimerNode)node
	if timer.setDuration != nil {
		timer->setDuration(sec)
	}
	return 0
}

@(private="file")
lua_node_timer_set_loop :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != TimerNode do return 0
	loop := lua.toboolean(L, 2)
	timer := cast(^TimerNode)node
	timer.loop = bool(loop)
	return 0
}

// ----------------------------------------------------------------------------
// Sound & Music Node Methods
// ----------------------------------------------------------------------------

@(private="file")
lua_node_sound_play :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != SoundNode do return 0
	soundNode := cast(^SoundNode)node
	SoundNode_Play(soundNode)
	return 0
}

// node:sound_play_index(i): sound i of its list (1 = the first), whatever
// the play mode (#204).
@(private="file")
lua_node_sound_play_index :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != SoundNode do return 0
	SoundNode_PlayIndex(cast(^SoundNode)node, int(lua.L_checkinteger(L, 2)) - 1)
	return 0
}

// node:sound_count(): how many sounds it has.
@(private="file")
lua_node_sound_count :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	n := len((cast(^SoundNode)node).sounds) if ok && node.typeId == SoundNode else 0
	lua.pushinteger(L, lua.Integer(n))
	return 1
}

// node:sound_last(): the sound played last (1 = the first; 0: none yet).
@(private="file")
lua_node_sound_last :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	i := (cast(^SoundNode)node).lastIndex + 1 if ok && node.typeId == SoundNode else 0
	lua.pushinteger(L, lua.Integer(i))
	return 1
}

@(private="file")
lua_node_sound_stop :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != SoundNode do return 0
	soundNode := cast(^SoundNode)node
	SoundNode_Stop(soundNode)
	return 0
}

@(private="file")
lua_node_sound_pause :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != SoundNode do return 0
	soundNode := cast(^SoundNode)node
	SoundNode_Pause(soundNode)
	return 0
}

@(private="file")
lua_node_sound_resume :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != SoundNode do return 0
	soundNode := cast(^SoundNode)node
	SoundNode_Resume(soundNode)
	return 0
}

@(private="file")
lua_node_music_play :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != MusicNode do return 0
	musicNode := cast(^MusicNode)node
	MusicNode_Play(musicNode)
	return 0
}

@(private="file")
lua_node_music_stop :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != MusicNode do return 0
	musicNode := cast(^MusicNode)node
	MusicNode_Stop(musicNode)
	return 0
}

@(private="file")
lua_node_music_pause :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != MusicNode do return 0
	musicNode := cast(^MusicNode)node
	MusicNode_Pause(musicNode)
	return 0
}

@(private="file")
lua_node_music_resume :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != MusicNode do return 0
	musicNode := cast(^MusicNode)node
	MusicNode_Resume(musicNode)
	return 0
}

// ----------------------------------------------------------------------------
// LDtk Node Methods
// ----------------------------------------------------------------------------

@(private="file")
lua_node_ldtk_get_level_identifier :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != LdtkLevelNode {
		lua.pushstring(L, "")
		return 1
	}
	ldtkNode := cast(^LdtkLevelNode)node
	idC := strings.clone_to_cstring(ldtkNode.levelIdentifier, context.temp_allocator)
	lua.pushstring(L, idC)
	return 1
}

// ----------------------------------------------------------------------------
// Camera Node Methods (when invoked on CameraNode userdata)
// ----------------------------------------------------------------------------

@(private="file")
lua_node_camera_set_zoom :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CameraNode do return 0
	zoom := f32(lua.tonumber(L, 2))
	CameraNode_SetZoom(cast(^CameraNode)node, zoom)
	return 0
}

@(private="file")
lua_node_camera_get_zoom :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CameraNode {
		lua.pushnumber(L, 1)
		return 1
	}
	cam := cast(^CameraNode)node
	lua.pushnumber(L, lua.Number(cam.targetZoom))
	return 1
}

@(private="file")
lua_node_camera_set_target :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	target, _ := to_node_userdata(L, 2)
	if !ok || node.typeId != CameraNode do return 0
	CameraNode_SetTarget(cast(^CameraNode)node, target)
	return 0
}

// --- camera targets (node methods take the camera at 1; Camera.* use the
// scene's current camera, args shifted by one) ---

// camera_target_opts reads { weight = n | weight_x, weight_y, radius,
// offset_x, offset_y, priority } at idx (absent = defaults).
@(private="file")
camera_target_opts :: proc(L: ^lua.State, node: ^Node, idx: c.int) -> CameraTarget {
	t := CameraTarget{node = node, position = node.globalPosition, influence = {1, 1}, radius = 50, enabled = true, prevPosition = node.globalPosition}
	if lua.type(L, idx) != .TABLE do return t
	num :: proc(L: ^lua.State, idx: c.int, key: cstring, def: f32) -> f32 {
		lua.getfield(L, idx, key)
		defer lua.pop(L, 1)
		return f32(lua.tonumber(L, -1)) if lua.type(L, -1) == .NUMBER else def
	}
	w := num(L, idx, "weight", 1)
	t.influence = {num(L, idx, "weight_x", w), num(L, idx, "weight_y", w)}
	t.radius = num(L, idx, "radius", 50)
	t.offset = {num(L, idx, "offset_x", 0), num(L, idx, "offset_y", 0)}
	t.priority = int(num(L, idx, "priority", 0))
	return t
}

@(private="file")
camera_arg :: proc(L: ^lua.State, isModule: bool) -> (^CameraNode, c.int) {
	if isModule do return get_current_camera(L), 1
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CameraNode do return nil, 2
	return cast(^CameraNode)node, 2
}

@(private="file")
camera_add_target_impl :: proc(L: ^lua.State, isModule: bool) -> c.int {
	cam, a := camera_arg(L, isModule)
	target, ok := to_node_userdata(L, a)
	if cam != nil && ok do CameraNode_AddTarget(cam, camera_target_opts(L, target, a + 1))
	return 0
}

@(private="file")
camera_remove_target_impl :: proc(L: ^lua.State, isModule: bool) -> c.int {
	cam, a := camera_arg(L, isModule)
	target, ok := to_node_userdata(L, a)
	if cam != nil && ok do CameraNode_RemoveTarget(cam, target)
	return 0
}

@(private="file")
camera_clear_targets_impl :: proc(L: ^lua.State, isModule: bool) -> c.int {
	if cam, _ := camera_arg(L, isModule); cam != nil {
		CameraNode_ClearTargets(cam)
		cam.followTarget = ""
	}
	return 0
}

@(private="file")
camera_get_target_impl :: proc(L: ^lua.State, isModule: bool) -> c.int {
	cam, _ := camera_arg(L, isModule)
	push_node_userdata(L, cam.target if cam != nil else nil)
	return 1
}

@(private="file")
camera_get_targets_impl :: proc(L: ^lua.State, isModule: bool) -> c.int {
	cam, _ := camera_arg(L, isModule)
	lua.newtable(L)
	if cam == nil do return 1
	n := 0
	if cam.followMode != .MultiTarget && cam.target != nil {
		push_node_userdata(L, cam.target)
		lua.rawseti(L, -2, 1)
		return 1
	}
	for t in cam.targets {
		if t.node == nil || !Node_IsAlive(t.node) do continue
		n += 1
		push_node_userdata(L, t.node)
		lua.rawseti(L, -2, lua.Integer(n))
	}
	return 1
}

@(private="file")
lua_node_camera_add_target :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); return camera_add_target_impl(L, false)}
@(private="file")
lua_node_camera_remove_target :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); return camera_remove_target_impl(L, false)}
@(private="file")
lua_node_camera_clear_targets :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); return camera_clear_targets_impl(L, false)}
@(private="file")
lua_node_camera_get_target :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); return camera_get_target_impl(L, false)}
@(private="file")
lua_node_camera_get_targets :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); return camera_get_targets_impl(L, false)}
@(private="file")
lua_camera_add_target :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); return camera_add_target_impl(L, true)}
@(private="file")
lua_camera_remove_target :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); return camera_remove_target_impl(L, true)}
@(private="file")
lua_camera_clear_targets :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); return camera_clear_targets_impl(L, true)}
@(private="file")
lua_camera_get_target :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); return camera_get_target_impl(L, true)}
@(private="file")
lua_camera_get_targets :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); return camera_get_targets_impl(L, true)}

// --- materials ---

// node:set_shader(path | nil): "builtin:flash" or a project .fs file.
@(private="file")
lua_node_set_shader :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	path := string(lua.tostring(L, 2)) if lua.type(L, 2) == .STRING else ""
	Material_SetShader(node, path)
	return 0
}

// node:set_shader_param(name, x [, y, z, w]) / (name, {r, g, b, a}) /
// (name, "textures/noise.png")
@(private="file")
lua_node_set_shader_param :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || lua.type(L, 2) != .STRING do return 0
	name := strings.clone(string(lua.tostring(L, 2)), context.temp_allocator)
	v: [4]f32
	#partial switch lua.type(L, 3) {
	case .STRING:
		Material_SetParam(node, name, {}, string(lua.tostring(L, 3)))
		return 0
	case .TABLE:
		for i in 0 ..< 4 {
			lua.rawgeti(L, 3, lua.Integer(i + 1))
			v[i] = f32(lua.tonumber(L, -1))
			lua.pop(L, 1)
		}
	case:
		for i in 0 ..< 4 do v[i] = f32(lua.tonumber(L, c.int(3 + i)))
	}
	Material_SetParam(node, name, v)
	return 0
}

// node:get_shader_param(name) -> x, y, z, w (or the texture path)
@(private="file")
lua_node_get_shader_param :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || lua.type(L, 2) != .STRING {
		lua.pushnil(L)
		return 1
	}
	v, tex, found := Material_GetParam(node, string(lua.tostring(L, 2)))
	if !found {
		lua.pushnil(L)
		return 1
	}
	if tex != "" {
		lua.pushstring(L, strings.clone_to_cstring(tex, context.temp_allocator))
		return 1
	}
	for i in 0 ..< 4 do lua.pushnumber(L, lua.Number(v[i]))
	return 4
}

// node:set_blend_mode("alpha" | "additive" | "multiply" | "add_colors" |
// "subtract_colors" | "premultiplied")
@(private="file")
lua_node_set_blend_mode :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	Node_EnsureMaterial(node).blend = Material_BlendParse(string(lua.tostring(L, 2)) if lua.type(L, 2) == .STRING else "alpha")
	return 0
}

@(private="file")
lua_node_camera_set_target_position :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CameraNode do return 0
	tx, ty := arg_xy(L, 2) // two numbers or a vector
	CameraNode_SetTargetPosition(cast(^CameraNode)node, {tx, ty})
	return 0
}

@(private="file")
lua_node_camera_shake :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CameraNode do return 0
	// (Pixels; nil = the node's Shake Preset, #215.)
	strength := f32(lua.tonumber(L, 2)) if !lua.isnoneornil(L, 2) else -1
	dur := f32(lua.tonumber(L, 3)) if !lua.isnoneornil(L, 3) else -1
	CameraNode_PlayShake(cast(^CameraNode)node, strength, dur)
	return 0
}

@(private="file")
lua_node_camera_stop_shake :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CameraNode do return 0
	CameraNode_StopShake(cast(^CameraNode)node)
	return 0
}

@(private="file")
lua_node_camera_is_shaking :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CameraNode {
		lua.pushboolean(L, false)
		return 1
	}
	lua.pushboolean(L, b32(CameraNode_IsShaking(cast(^CameraNode)node)))
	return 1
}

@(private="file")
lua_node_camera_set_limits :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CameraNode do return 0
	l, r, next := arg_xy_next(L, 2) // two numbers or a vector
	t, b := arg_xy(L, next) // two numbers or a vector
	CameraNode_SetLimits(cast(^CameraNode)node, l, r, t, b)
	return 0
}

@(private="file")
lua_node_camera_clear_limits :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CameraNode do return 0
	CameraNode_ClearLimits(cast(^CameraNode)node)
	return 0
}

// ----------------------------------------------------------------------------
// Global Camera Table (Engine.Camera)
// ----------------------------------------------------------------------------

// camera_view_size: the frame the game draws at (the project's virtual
// resolution; Expand: grown to the window's shape).
@(private="file")
camera_view_size :: proc(L: ^lua.State) -> [2]f32 {
	sm := get_script_manager(L)
	if sm != nil && sm.game != nil && sm.game.virtualSize.x > 0 do return sm.game.virtualSize
	return {1280, 720}
}

@(private="file")
get_current_camera :: proc(L: ^lua.State) -> ^CameraNode {
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || sm.game.sceneManager.currentScene == nil do return nil
	return sm.game.sceneManager.currentScene.camera
}

@(private="file")
lua_camera_get_target_position :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cam := get_current_camera(L)
	if cam == nil {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	lua.pushnumber(L, lua.Number(cam.targetPosition.x))
	lua.pushnumber(L, lua.Number(cam.targetPosition.y))
	return 2
}

@(private="file")
lua_camera_set_target_position :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cam := get_current_camera(L)
	if cam == nil do return 0
	x, y := arg_xy(L, 1) // two numbers or a vector
	CameraNode_SetTargetPosition(cam, {x, y})
	return 0
}

@(private="file")
lua_camera_set_target :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cam := get_current_camera(L)
	target, _ := to_node_userdata(L, 1)
	if cam != nil {
		CameraNode_SetTarget(cam, target)
	}
	return 0
}

@(private="file")
lua_camera_get_zoom :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cam := get_current_camera(L)
	if cam == nil {
		lua.pushnumber(L, 1)
		return 1
	}
	lua.pushnumber(L, lua.Number(cam.targetZoom))
	return 1
}

@(private="file")
lua_camera_set_zoom :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cam := get_current_camera(L)
	if cam != nil {
		zoom := f32(lua.tonumber(L, 1))
		CameraNode_SetZoom(cam, zoom)
	}
	return 0
}

@(private="file")
lua_camera_get_offset :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cam := get_current_camera(L)
	if cam == nil {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	lua.pushnumber(L, lua.Number(cam.offset.x))
	lua.pushnumber(L, lua.Number(cam.offset.y))
	return 2
}

@(private="file")
lua_camera_set_offset :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cam := get_current_camera(L)
	if cam != nil {
		ox, oy := arg_xy(L, 1) // two numbers or a vector
		CameraNode_SetOffset(cam, {ox, oy})
	}
	return 0
}

@(private="file")
lua_camera_get_rotation :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cam := get_current_camera(L)
	if cam == nil {
		lua.pushnumber(L, 0)
		return 1
	}
	lua.pushnumber(L, lua.Number(cam.rotation))
	return 1
}

@(private="file")
lua_camera_set_rotation :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cam := get_current_camera(L)
	if cam != nil {
		deg := f32(lua.tonumber(L, 1))
		CameraNode_SetRotation(cam, deg)
	}
	return 0
}

@(private="file")
lua_camera_shake :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cam := get_current_camera(L)
	if cam != nil {
		strength := f32(lua.tonumber(L, 1)) if !lua.isnoneornil(L, 1) else -1
		dur := f32(lua.tonumber(L, 2)) if !lua.isnoneornil(L, 2) else -1
		CameraNode_PlayShake(cam, strength, dur)
	}
	return 0
}

@(private="file")
lua_camera_stop_shake :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cam := get_current_camera(L)
	if cam != nil {
		CameraNode_StopShake(cam)
	}
	return 0
}

@(private="file")
lua_camera_is_shaking :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cam := get_current_camera(L)
	if cam == nil {
		lua.pushboolean(L, false)
		return 1
	}
	lua.pushboolean(L, b32(CameraNode_IsShaking(cam)))
	return 1
}

@(private="file")
lua_camera_set_limits :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cam := get_current_camera(L)
	if cam != nil {
		l, r, next := arg_xy_next(L, 1) // two numbers or a vector
		t, b := arg_xy(L, next) // two numbers or a vector
		CameraNode_SetLimits(cam, l, r, t, b)
	}
	return 0
}

@(private="file")
lua_camera_clear_limits :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cam := get_current_camera(L)
	if cam != nil {
		CameraNode_ClearLimits(cam)
	}
	return 0
}

@(private="file")
lua_camera_screen_to_world :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cam := get_current_camera(L)
	sx, sy := arg_xy(L, 1) // two numbers or a vector
	if cam == nil {
		lua.pushnumber(L, lua.Number(sx))
		lua.pushnumber(L, lua.Number(sy))
		return 2
	}
	vs := camera_view_size(L)
	wPos := CameraNode_ScreenToWorld(cam, {sx, sy}, vs.x, vs.y)
	lua.pushnumber(L, lua.Number(wPos.x))
	lua.pushnumber(L, lua.Number(wPos.y))
	return 2
}

@(private="file")
lua_camera_world_to_screen :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cam := get_current_camera(L)
	wx, wy := arg_xy(L, 1) // two numbers or a vector
	if cam == nil {
		lua.pushnumber(L, lua.Number(wx))
		lua.pushnumber(L, lua.Number(wy))
		return 2
	}
	vs := camera_view_size(L)
	sPos := CameraNode_WorldToScreen(cam, {wx, wy}, vs.x, vs.y)
	lua.pushnumber(L, lua.Number(sPos.x))
	lua.pushnumber(L, lua.Number(sPos.y))
	return 2
}

@(private="file")
lua_camera_get_visible_world_bounds :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cam := get_current_camera(L)
	vs := camera_view_size(L)
	if cam == nil {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		lua.pushnumber(L, lua.Number(vs.x))
		lua.pushnumber(L, lua.Number(vs.y))
		return 4
	}
	bounds := CameraNode_GetVisibleWorldBounds(cam, vs.x, vs.y)
	lua.pushnumber(L, lua.Number(bounds.x))
	lua.pushnumber(L, lua.Number(bounds.y))
	lua.pushnumber(L, lua.Number(bounds.width))
	lua.pushnumber(L, lua.Number(bounds.height))
	return 4
}

// ----------------------------------------------------------------------------
// Global Physics Table (Engine.Physics)
// ----------------------------------------------------------------------------

WorldRaycastQuery :: struct {
	hit:      bool,
	point:    [2]f32,
	normal:   [2]f32,
	fraction: f32,
	hitNode:  ^Node,
}

@(private="file")
world_raycast_callback :: proc "c" (shapeId: b2.ShapeId, point: b2.Vec2, normal: b2.Vec2, fraction: f32, ctx: rawptr) -> f32 {
	if ctx == nil || !b2.Shape_IsValid(shapeId) do return 1.0
	res := cast(^WorldRaycastQuery)ctx
	if b2.Shape_IsSensor(shapeId) do return -1.0

	bodyId := b2.Shape_GetBody(shapeId)
	hitNode: ^Node = nil
	if b2.Body_IsValid(bodyId) {
		hitNode = cast(^Node)b2.Body_GetUserData(bodyId)
	}

	res.hit = true
	res.point = point
	res.normal = normal
	res.fraction = fraction
	res.hitNode = hitNode
	return fraction
}

@(private="file")
lua_physics_get_gravity :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	lua.pushnumber(L, lua.Number(sm.game.physicsWorld.gravity.x))
	lua.pushnumber(L, lua.Number(sm.game.physicsWorld.gravity.y))
	return 2
}

@(private="file")
lua_physics_set_gravity :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil do return 0
	gx, gy := arg_xy(L, 1) // two numbers or a vector
	sm.game.physicsWorld.gravity = {gx, gy}
	PhysicsWorld_SyncSettings(&sm.game.physicsWorld)
	return 0
}

// Physics.set_debug_draw(on) / get_debug_draw(): colliders, joints and
// areas drawn while the game runs (project setting physics.debug_draw).
@(private="file")
lua_physics_set_debug_draw :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil do return 0
	sm.game.physicsWorld.drawPhysicsDebug = bool(lua.toboolean(L, 1))
	return 0
}

@(private="file")
lua_physics_get_debug_draw :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	lua.pushboolean(L, b32(sm != nil && sm.game != nil && sm.game.physicsWorld.drawPhysicsDebug))
	return 1
}

@(private="file")
lua_physics_is_paused :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil {
		lua.pushboolean(L, false)
		return 1
	}
	lua.pushboolean(L, b32(sm.game.physicsWorld.paused))
	return 1
}

@(private="file")
lua_physics_set_paused :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil do return 0
	paused := lua.toboolean(L, 1)
	sm.game.physicsWorld.paused = bool(paused)
	return 0
}

@(private="file")
lua_physics_raycast :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || !b2.World_IsValid(sm.game.physicsWorld.worldId) {
		lua.pushnil(L)
		return 1
	}

	startX, startY, next := arg_xy_next(L, 1) // two numbers or a vector
	endX, endY, after := arg_xy_next(L, next) // two numbers or a vector

	origin := [2]f32{startX, startY}
	translation := [2]f32{endX - startX, endY - startY}

	query := WorldRaycastQuery{hit = false, fraction = 1.0}
	// (Optional layers after the points: only shapes on them are hit.)
	filter := b2.DefaultQueryFilter()
	if after <= lua.gettop(L) && !lua.isnil(L, after) {
		set, valid := layers_arg(L, after)
		if !valid do lua.L_error(L, "unknown collision layer (names from Project Settings > Physics, or 1-16)")
		filter.maskBits = CollisionLayerSet_ToBits(set)
	}
	_ = b2.World_CastRay(sm.game.physicsWorld.worldId, origin, translation, filter, world_raycast_callback, &query)

	if !query.hit {
		lua.pushnil(L)
		return 1
	}

	lua.newtable(L)
	lua.pushboolean(L, true)
	lua.setfield(L, -2, "hit")
	lua.pushnumber(L, lua.Number(query.point.x))
	lua.setfield(L, -2, "point_x")
	lua.pushnumber(L, lua.Number(query.point.y))
	lua.setfield(L, -2, "point_y")
	lua.pushnumber(L, lua.Number(query.normal.x))
	lua.setfield(L, -2, "normal_x")
	lua.pushnumber(L, lua.Number(query.normal.y))
	lua.setfield(L, -2, "normal_y")
	lua.pushnumber(L, lua.Number(query.fraction))
	lua.setfield(L, -2, "fraction")
	if query.hitNode != nil {
		push_node_userdata(L, query.hitNode)
		lua.setfield(L, -2, "node")
	}
	return 1
}

// ----------------------------------------------------------------------------
// Global Engine Table (Engine)
// ----------------------------------------------------------------------------

@(private="file")
lua_engine_get_fps :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	fps := rl.GetFPS() if rl.IsWindowReady() else 60
	lua.pushnumber(L, lua.Number(fps))
	return 1
}

@(private="file")
lua_engine_get_delta_time :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	dt := rl.GetFrameTime() if rl.IsWindowReady() else 0.01667
	lua.pushnumber(L, lua.Number(dt))
	return 1
}

@(private="file")
lua_engine_get_time :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	t := rl.GetTime() if rl.IsWindowReady() else 0
	lua.pushnumber(L, lua.Number(t))
	return 1
}

@(private="file")
lua_engine_get_window_size :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	w := rl.GetScreenWidth() if rl.IsWindowReady() else 1280
	h := rl.GetScreenHeight() if rl.IsWindowReady() else 720
	lua.pushnumber(L, lua.Number(w))
	lua.pushnumber(L, lua.Number(h))
	return 2
}

@(private="file")
lua_engine_get_virtual_size :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	vw: f32 = 1280
	vh: f32 = 720
	if sm != nil && sm.game != nil && sm.game.virtualSize.x > 0 {
		vw = sm.game.virtualSize.x
		vh = sm.game.virtualSize.y
	}
	lua.pushnumber(L, lua.Number(vw))
	lua.pushnumber(L, lua.Number(vh))
	return 2
}

// ----------------------------------------------------------------------------
// Input Bindings (Engine.Input)
// ----------------------------------------------------------------------------

// sm_keyboard_blocked: the developer console has the keyboard.
@(private="file")
sm_keyboard_blocked :: proc(L: ^lua.State) -> bool {
	sm := get_script_manager(L)
	return sm != nil && sm.game != nil && sm.game.input.keyboardBlocked
}

// parse_keyboard_key: any raylib key name ("Z", "F5", "KP_1", "LEFT_ALT"),
// plus a few short forms (RETURN, ESC, SHIFT, CTRL, ALT, 0-9).
parse_keyboard_key :: proc(name: string) -> (rl.KeyboardKey, bool) {
	upper := strings.to_upper(name, context.temp_allocator)
	switch upper {
	case "RETURN": return .ENTER, true
	case "ESC": return .ESCAPE, true
	case "SHIFT": return .LEFT_SHIFT, true
	case "CTRL", "CONTROL": return .LEFT_CONTROL, true
	case "ALT": return .LEFT_ALT, true
	case "0": return .ZERO, true
	case "1": return .ONE, true
	case "2": return .TWO, true
	case "3": return .THREE, true
	case "4": return .FOUR, true
	case "5": return .FIVE, true
	case "6": return .SIX, true
	case "7": return .SEVEN, true
	case "8": return .EIGHT, true
	case "9": return .NINE, true
	}
	if k, ok := reflect.enum_from_name(rl.KeyboardKey, upper); ok && k != .KEY_NULL do return k, true
	return .KEY_NULL, false
}

@(private="file")
parse_mouse_button :: proc(name: string) -> (rl.MouseButton, bool) {
	upper := strings.to_upper(name, context.temp_allocator)
	switch upper {
	case "LEFT", "0": return .LEFT, true
	case "RIGHT", "1": return .RIGHT, true
	case "MIDDLE", "2": return .MIDDLE, true
	case "SIDE", "3": return .SIDE, true
	case "EXTRA", "4": return .EXTRA, true
	case "FORWARD", "5": return .FORWARD, true
	case "BACK", "6": return .BACK, true
	}
	return .LEFT, false
}

@(private="file")
lua_input_is_action_pressed :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	actStr := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if actStr == nil || sm == nil || sm.game == nil {
		lua.pushboolean(L, false)
		return 1
	}
	st, _ := Input_PlayerActionState(&sm.game.input, string(actStr), lua_player_arg(L, 2))
	lua.pushboolean(L, b32(st.pressed))
	return 1
}

@(private="file")
lua_input_is_action_down :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	actStr := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if actStr == nil || sm == nil || sm.game == nil {
		lua.pushboolean(L, false)
		return 1
	}
	st, _ := Input_PlayerActionState(&sm.game.input, string(actStr), lua_player_arg(L, 2))
	lua.pushboolean(L, b32(st.down))
	return 1
}

@(private="file")
lua_input_is_action_released :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	actStr := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if actStr == nil || sm == nil || sm.game == nil {
		lua.pushboolean(L, false)
		return 1
	}
	st, _ := Input_PlayerActionState(&sm.game.input, string(actStr), lua_player_arg(L, 2))
	lua.pushboolean(L, b32(st.released))
	return 1
}

@(private="file")
lua_input_get_axis :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	negStr := lua.tostring(L, 1)
	posStr := lua.tostring(L, 2)
	sm := get_script_manager(L)
	if negStr == nil || posStr == nil || sm == nil || sm.game == nil {
		lua.pushnumber(L, 0)
		return 1
	}
	player := lua_player_arg(L, 3)
	neg, _ := Input_PlayerActionState(&sm.game.input, string(negStr), player)
	pos, _ := Input_PlayerActionState(&sm.game.input, string(posStr), player)
	lua.pushnumber(L, lua.Number(pos.value - neg.value))
	return 1
}

@(private="file")
lua_input_get_vector :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	// (left, right, up, down[, player]) or (player): the names are optional.
	names := [4]string{"move_left", "move_right", "move_up", "move_down"}
	player := 1
	ni := 0
	for i in c.int(1) ..= lua.gettop(L) {
		#partial switch lua.type(L, i) {
		case .NUMBER: player = int(lua.tointeger(L, i))
		case .STRING: if ni < 4 {names[ni] = string(lua.tostring(L, i)); ni += 1}
		case: ni += 1 // (nil: the default)
		}
	}

	inp := &sm.game.input
	l, _ := Input_PlayerActionState(inp, names[0], player)
	r, _ := Input_PlayerActionState(inp, names[1], player)
	u, _ := Input_PlayerActionState(inp, names[2], player)
	d, _ := Input_PlayerActionState(inp, names[3], player)
	vec := [2]f32{r.value - l.value, d.value - u.value}
	if l2 := vec.x * vec.x + vec.y * vec.y; l2 > 1 {
		inv := 1 / math.sqrt(l2)
		vec *= inv
	}
	lua.pushnumber(L, lua.Number(vec.x))
	lua.pushnumber(L, lua.Number(vec.y))
	return 2
}

@(private="file")
lua_input_is_key_down :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	keyStr := lua.tostring(L, 1)
	if keyStr == nil {
		lua.pushboolean(L, false)
		return 1
	}
	key, ok := parse_keyboard_key(string(keyStr))
	if !ok {
		lua.pushboolean(L, false)
		return 1
	}
	sm := get_script_manager(L)
	if sm != nil && sm.game != nil && sm.game.input.useSimulatedInput {
		isDown := sm.game.input.simulatedKeysDown[key]
		lua.pushboolean(L, b32(isDown))
		return 1
	}
	isDown := rl.IsWindowReady() && !sm_keyboard_blocked(L) && rl.IsKeyDown(key)
	lua.pushboolean(L, b32(isDown))
	return 1
}

@(private="file")
lua_input_is_key_pressed :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	keyStr := lua.tostring(L, 1)
	if keyStr == nil {
		lua.pushboolean(L, false)
		return 1
	}
	key, ok := parse_keyboard_key(string(keyStr))
	if !ok {
		lua.pushboolean(L, false)
		return 1
	}
	if sm := get_script_manager(L); sm != nil && sm.game != nil && sm.game.input.useSimulatedInput {
		lua.pushboolean(L, b32(Input_SimulatedKeyPressed(&sm.game.input, key)))
		return 1
	}
	isPressed := rl.IsWindowReady() && !sm_keyboard_blocked(L) && rl.IsKeyPressed(key)
	lua.pushboolean(L, b32(isPressed))
	return 1
}

@(private="file")
lua_input_is_key_released :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	keyStr := lua.tostring(L, 1)
	if keyStr == nil {
		lua.pushboolean(L, false)
		return 1
	}
	key, ok := parse_keyboard_key(string(keyStr))
	if !ok {
		lua.pushboolean(L, false)
		return 1
	}
	if sm := get_script_manager(L); sm != nil && sm.game != nil && sm.game.input.useSimulatedInput {
		lua.pushboolean(L, b32(Input_SimulatedKeyReleased(&sm.game.input, key)))
		return 1
	}
	isRel := rl.IsWindowReady() && !sm_keyboard_blocked(L) && rl.IsKeyReleased(key)
	lua.pushboolean(L, b32(isRel))
	return 1
}

// ui_has_mouse: a UI widget has the mouse (Game_UIHasMouse).
@(private="file")
ui_has_mouse :: proc(L: ^lua.State) -> bool {
	sm := get_script_manager(L)
	return sm != nil && Game_UIHasMouse(sm.game)
}

// test_mouse: what stands in for the mouse - the test mouse (the runner's
// --input-script, tests) or a finger (touch as mouse) - the left button
// only; ok = false: the real mouse.
@(private="file")
test_mouse :: proc(L: ^lua.State) -> (Touch_Mouse, bool) {
	sm := get_script_manager(L)
	if sm == nil do return {}, false
	return Game_Pointer(sm.game)
}

@(private="file")
lua_input_is_mouse_button_pressed :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	btnStr := lua.tostring(L, 1)
	btn, ok := parse_mouse_button(string(btnStr) if btnStr != nil else "LEFT")
	if !ok {
		lua.pushboolean(L, false)
		return 1
	}
	isPressed := rl.IsWindowReady() && rl.IsMouseButtonPressed(btn) && !ui_has_mouse(L) // (not a click on UI, #228)
	if m, ok := test_mouse(L); ok do isPressed = btn == .LEFT && m.pressed && !ui_has_mouse(L)
	lua.pushboolean(L, b32(isPressed))
	return 1
}

@(private="file")
lua_input_is_mouse_button_down :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	btnStr := lua.tostring(L, 1)
	btn, ok := parse_mouse_button(string(btnStr) if btnStr != nil else "LEFT")
	if !ok {
		lua.pushboolean(L, false)
		return 1
	}
	isDown := rl.IsWindowReady() && rl.IsMouseButtonDown(btn) && !ui_has_mouse(L) // (not a click on UI, #228)
	if m, ok := test_mouse(L); ok do isDown = btn == .LEFT && m.down && !ui_has_mouse(L)
	lua.pushboolean(L, b32(isDown))
	return 1
}

@(private="file")
lua_input_is_mouse_button_released :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	btnStr := lua.tostring(L, 1)
	btn, ok := parse_mouse_button(string(btnStr) if btnStr != nil else "LEFT")
	if !ok {
		lua.pushboolean(L, false)
		return 1
	}
	isRel := rl.IsWindowReady() && rl.IsMouseButtonReleased(btn) && !ui_has_mouse(L) // (not a click on UI, #228)
	if m, ok := test_mouse(L); ok do isRel = btn == .LEFT && m.released && !ui_has_mouse(L)
	lua.pushboolean(L, b32(isRel))
	return 1
}

@(private="file")
lua_input_get_mouse_position :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if m, ok := test_mouse(L); ok {
		lua.pushnumber(L, lua.Number(m.pos.x))
		lua.pushnumber(L, lua.Number(m.pos.y))
		return 2
	}
	if rl.IsWindowReady() {
		mPos := rl.GetMousePosition()
		lua.pushnumber(L, lua.Number(mPos.x))
		lua.pushnumber(L, lua.Number(mPos.y))
		return 2
	}
	lua.pushnumber(L, 0)
	lua.pushnumber(L, 0)
	return 2
}

@(private="file")
lua_input_get_mouse_wheel_move :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	move := rl.GetMouseWheelMove() if rl.IsWindowReady() else 0
	lua.pushnumber(L, lua.Number(move))
	return 1
}

// ----------------------------------------------------------------------------
// Audio Bindings (Engine.Audio)
// ----------------------------------------------------------------------------

@(private="file")
lua_audio_play_sound :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	pathC := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if pathC == nil || sm == nil || sm.game == nil do return 0

	path := Project_ResolveAssetPath(&sm.game.gameContext, string(pathC)) // (project-relative)
	if rl.IsAudioDeviceReady() {
		sound, ok := sm.game.resourceManager->loadAudioSound(path)
		if ok && sound != nil {
			// Audio.play_sound(path [, volume [, pitch [, bus = "SFX"]]]): one-shots overlap.
			vol := f32(lua.tonumber(L, 2)) if lua.gettop(L) >= 2 else 1
			pitch := f32(lua.tonumber(L, 3)) if lua.gettop(L) >= 3 else 1
			bus := Mixer_BusIndex(string(lua.tostring(L, 4))) if lua.type(L, 4) == .STRING else Audio_BusFor(&sm.game.resourceManager, path, "SFX")
			if Audio_Ready() do Mixer_PlaySound(sound.pcm, bus if bus >= 0 else 0, vol, 0, pitch, owner = sound)
		}
	}
	return 0
}

// Audio.play_sound_at(path, x, y [, volume]): a one-shot heard from where it
// happens (distance and pan from the listener).
@(private="file")
lua_audio_play_sound_at :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	pathC := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if pathC == nil || sm == nil || sm.game == nil || !rl.IsAudioDeviceReady() do return 0
	sound, ok := sm.game.resourceManager->loadAudioSound(Project_ResolveAssetPath(&sm.game.gameContext, string(pathC)))
	if !ok || sound == nil do return 0
	pos := [2]f32{f32(lua.tonumber(L, 2)), f32(lua.tonumber(L, 3))}
	vol := f32(lua.tonumber(L, 4)) if lua.gettop(L) >= 4 else 1
	pan: f32 = 0.5
	if listener, has := Audio_ListenerPosition(&sm.game.gameContext); has {
		v, p := Audio_Spatialize(pos, listener, 100, 900, 450)
		vol *= v
		pan = p
	}
	sfx := Audio_BusFor(&sm.game.resourceManager, sound.filePath, "SFX")
	if Audio_Ready() do Mixer_PlaySound(sound.pcm, sfx, vol, Audio_RaylibPanToMixer(pan), 1, owner = sound)
	return 0
}

@(private="file")
bus_arg :: proc(L: ^lua.State, idx: c.int) -> (Audio_Bus, bool) {
	s := lua.tostring(L, idx)
	if s == nil do return .Master, false
	switch strings.to_lower(string(s), context.temp_allocator) {
	case "master": return .Master, true
	case "music":  return .Music, true
	case "sfx":    return .Sfx, true
	}
	return .Master, false
}

// Audio.set_bus_volume(bus, v): any mixer bus by name ("master", "music",
// "sfx" as before); master / music / sfx also update the project volumes.
@(private="file")
lua_audio_set_bus_volume :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || lua.type(L, 1) != .STRING do return 0
	v := f32(lua.tonumber(L, 2))
	if bus, ok := bus_arg(L, 1); ok {
		Game_SetBusVolume(sm.game, bus, v)
		return 0
	}
	Mixer_Init()
	if i := Mixer_BusIndex(string(lua.tostring(L, 1))); i >= 0 do Mixer_SetBusVolume(i, max(v, 0))
	return 0
}

@(private="file")
lua_audio_get_bus_volume :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	v: f32 = 1
	if lua.type(L, 1) == .STRING {
		Mixer_Init()
		i := Mixer_BusIndex(string(lua.tostring(L, 1)))
		if i < 0 && string(lua.tostring(L, 1)) == "sfx" do i = Mixer_BusIndex("SFX")
		for b in Mixer_Buses() do if b.index == i do v = b.volume
	}
	lua.pushnumber(L, lua.Number(v))
	return 1
}

@(private="file")
lua_bus_index :: proc(L: ^lua.State, idx: c.int) -> int {
	if lua.type(L, idx) != .STRING do return -1
	Mixer_Init()
	return Mixer_BusIndex(string(lua.tostring(L, idx)))
}

// Audio.set_bus_mute(bus, on) / set_bus_solo(bus, on) / set_bus_pan(bus, -1..1)
@(private="file")
lua_audio_set_bus_mute :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	Mixer_SetBusMute(lua_bus_index(L, 1), bool(lua.toboolean(L, 2)))
	return 0
}

@(private="file")
lua_audio_set_bus_solo :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	Mixer_SetBusSolo(lua_bus_index(L, 1), bool(lua.toboolean(L, 2)))
	return 0
}

@(private="file")
lua_audio_set_bus_pan :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	Mixer_SetBusPan(lua_bus_index(L, 1), f32(lua.tonumber(L, 2)))
	return 0
}

// Audio.get_buses() -> {"Master", "Music", "SFX", ...}
@(private="file")
lua_audio_get_buses :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	Mixer_Init()
	buses := Mixer_Buses()
	lua.createtable(L, c.int(len(buses)), 0)
	for b, i in buses {
		lua.pushstring(L, strings.clone_to_cstring(b.name, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

// Audio.bus_peak(bus) -> left, right (0..1+, post-fader, decaying): in-game meters.
@(private="file")
lua_audio_bus_peak :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	i := lua_bus_index(L, 1)
	pk: [2]f32
	for b in Mixer_Buses() do if b.index == i do pk = b.peak
	lua.pushnumber(L, lua.Number(pk[0]))
	lua.pushnumber(L, lua.Number(pk[1]))
	return 2
}

// lua_effect_slot: an effect on a bus by 1-based index or by type name
// (the first of that type).
@(private="file")
lua_effect_slot :: proc(L: ^lua.State, bus: int, idx: c.int) -> int {
	if bus < 0 do return -1
	if lua.type(L, idx) == .NUMBER do return int(lua.tointeger(L, idx)) - 1
	if lua.type(L, idx) != .STRING do return -1
	t, ok := Effect_ParseType(string(lua.tostring(L, idx)))
	if !ok do return -1
	for b in Mixer_Buses() do if b.index == bus {
		for e, k in b.effects do if e.type == t do return k
	}
	return -1
}

// Audio.set_effect(bus, effect, param, value): e.g. ("Music", "lowpass", "cutoff", 800)
@(private="file")
lua_audio_set_effect :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	bus := lua_bus_index(L, 1)
	e := Mixer_EffectRef(bus, lua_effect_slot(L, bus, 2))
	if e == nil || lua.type(L, 3) != .STRING {
		lua.pushboolean(L, false)
		return 1
	}
	pi := Mixer_EffectParamIndex(e.type, string(lua.tostring(L, 3)))
	if pi < 0 {
		lua.pushboolean(L, false)
		return 1
	}
	d := MIXER_EFFECT_PARAMS[e.type][pi]
	e.params[pi] = clamp(f32(lua.tonumber(L, 4)), d.min, d.max)
	lua.pushboolean(L, true)
	return 1
}

// Audio.set_effect_enabled(bus, effect, on)
@(private="file")
lua_audio_set_effect_enabled :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	bus := lua_bus_index(L, 1)
	Mixer_SetEffectEnabled(bus, lua_effect_slot(L, bus, 2), bool(lua.toboolean(L, 3)))
	return 0
}

// Audio.set_lowpass(hz): a low-pass on the whole mix (0 = off).
@(private="file")
lua_audio_set_lowpass :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	Audio_SetLowpass(f32(lua.tonumber(L, 1)))
	return 0
}

// Audio.set_reverb(mix [, size]): reverb on the whole mix (mix 0 = off).
@(private="file")
lua_audio_set_reverb :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	Audio_SetReverb(f32(lua.tonumber(L, 1)), f32(lua.tonumber(L, 2)) if lua.gettop(L) >= 2 else 0.5)
	return 0
}

// Audio.set_listener(node | nil): where positional sounds are heard from.
@(private="file")
lua_audio_set_listener :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	Audio_SetListener(node if ok else nil)
	return 0
}

// Audio.crossfade(fromMusicNode, toMusicNode, seconds)
@(private="file")
lua_audio_crossfade :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	from, fok := to_node_userdata(L, 1)
	to, tok := to_node_userdata(L, 2)
	a := cast(^MusicNode)from if fok && from.typeId == MusicNode else nil
	b := cast(^MusicNode)to if tok && to.typeId == MusicNode else nil
	MusicNode_Crossfade(a, b, f32(lua.tonumber(L, 3)))
	return 0
}

// node:music_fade(volume, seconds [, stop_at_end])
@(private="file")
lua_node_music_fade :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != MusicNode do return 0
	MusicNode_FadeTo(cast(^MusicNode)node, f32(lua.tonumber(L, 2)), f32(lua.tonumber(L, 3)), bool(lua.toboolean(L, 4)))
	return 0
}

// lua_music: a music resource by path - the loaded one (no new reference),
// else loaded once (kept for later calls).
@(private="file")
lua_music :: proc(L: ^lua.State) -> (^AudioMusic, ^ScriptManager) {
	pathC := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if pathC == nil || sm == nil || sm.game == nil || !rl.IsAudioDeviceReady() do return nil, sm
	rm := &sm.game.resourceManager
	path := Project_ResolveAssetPath(&sm.game.gameContext, string(pathC))
	for i in 0 ..< rm.musicCount do if rm.audioMusic[i].filePath == path || rm.audioMusic[i].filePath == string(pathC) do return &rm.audioMusic[i], sm
	m, ok := rm->loadAudioMusic(path)
	return m if ok else nil, sm
}

// Audio.play_music(path [, loop = true [, bus = "Music"]])
@(private="file")
lua_audio_play_music :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	m, _ := lua_music(L)
	if m == nil || !Audio_Ready() do return 0
	loop := lua.type(L, 2) != .BOOLEAN || bool(lua.toboolean(L, 2))
	sm := get_script_manager(L)
	bus := Mixer_BusIndex(string(lua.tostring(L, 3))) if lua.type(L, 3) == .STRING else Audio_BusFor(&sm.game.resourceManager if sm != nil && sm.game != nil else nil, m.filePath, "Music")
	Mixer_StopVoice(m.voice)
	m.voice = Mixer_PlayMusic(m.music, bus if bus >= 0 else 0, m.gain if m.gain > 0 else 1, loop, owner = m)
	return 0
}

@(private="file")
lua_audio_stop_music :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if m, _ := lua_music(L); m != nil {
		Mixer_StopVoice(m.voice)
		m.voice = {}
	}
	return 0
}

@(private="file")
lua_audio_pause_music :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if m, _ := lua_music(L); m != nil do Mixer_SetVoicePaused(m.voice, true)
	return 0
}

@(private="file")
lua_audio_resume_music :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if m, _ := lua_music(L); m != nil do Mixer_SetVoicePaused(m.voice, false)
	return 0
}

@(private="file")
lua_audio_is_music_playing :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	m, _ := lua_music(L)
	lua.pushboolean(L, b32(m != nil && Mixer_VoicePlaying(m.voice)))
	return 1
}

@(private="file")
lua_audio_set_music_volume :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if m, _ := lua_music(L); m != nil do Mixer_SetVoice(m.voice, max(f32(lua.tonumber(L, 2)), 0), 0, 1)
	return 0
}

@(private="file")
lua_audio_set_master_volume :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm != nil && sm.game != nil do Game_SetBusVolume(sm.game, .Master, f32(lua.tonumber(L, 1)))
	return 0
}

// ----------------------------------------------------------------------------
// Scene Bindings (Engine.Scene)
// ----------------------------------------------------------------------------

// Scene.set_ambient(r, g, b [, a]) (0..1): the light map's base colour.
@(private="file")
lua_scene_set_ambient :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || sm.game.sceneManager.currentScene == nil do return 0
	a := f32(lua.tonumber(L, 4)) if lua.type(L, 4) == .NUMBER else 1
	ch :: proc(v: f32) -> u8 {return u8(clamp(v, 0, 1) * 255 + 0.5)}
	amb := rl.Color{ch(f32(lua.tonumber(L, 1))), ch(f32(lua.tonumber(L, 2))), ch(f32(lua.tonumber(L, 3))), ch(a)}
	if amb == {} do amb.a = 1 // ({} means "not set": white)
	sm.game.sceneManager.currentScene.ambient = amb
	return 0
}

@(private="file")
lua_scene_get_ambient :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	c := rl.Color{255, 255, 255, 255}
	if sm != nil && sm.game != nil && sm.game.sceneManager.currentScene != nil && sm.game.sceneManager.currentScene.ambient != {} {
		c = sm.game.sceneManager.currentScene.ambient
	}
	for v in ([4]u8{c.r, c.g, c.b, c.a}) do lua.pushnumber(L, lua.Number(f32(v) / 255))
	return 4
}

@(private="file")
light_arg :: proc(L: ^lua.State) -> ^LightNode {
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != LightNode do return nil
	return cast(^LightNode)node
}

// light:light_set_color(r, g, b) (0..1)
@(private="file")
lua_light_set_color :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if l := light_arg(L); l != nil {
		ch :: proc(v: f32) -> u8 {return u8(clamp(v, 0, 1) * 255 + 0.5)}
		l.color = {ch(f32(lua.tonumber(L, 2))), ch(f32(lua.tonumber(L, 3))), ch(f32(lua.tonumber(L, 4))), 255}
	}
	return 0
}

@(private="file")
lua_light_set_energy :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if l := light_arg(L); l != nil do l.energy = max(f32(lua.tonumber(L, 2)), 0)
	return 0
}

@(private="file")
lua_light_set_radius :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if l := light_arg(L); l != nil do l.radius = max(f32(lua.tonumber(L, 2)), 0)
	return 0
}

@(private="file")
lua_light_get_energy :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	l := light_arg(L)
	lua.pushnumber(L, lua.Number(l.energy if l != nil else 0))
	return 1
}

// --- StateMachineNode: sm_set / sm_get / sm_trigger / sm_trigger_pending / sm_clear_trigger /
// sm_transition / sm_can_transition / sm_state / sm_previous / sm_time / sm_history / sm_start / sm_stop
// (the guide: engine/docs/state_machine.md)

@(private="file")
sm_arg :: proc(L: ^lua.State) -> ^StateMachineNode {
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != StateMachineNode do return nil
	return cast(^StateMachineNode)node
}

@(private="file")
sm_ctx :: proc(L: ^lua.State) -> ^GameContext {
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil do return nil
	return &sm.game.gameContext
}

// machine:sm_set(param, value) (number or boolean)
@(private="file")
lua_sm_set :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := sm_arg(L)
	name := lua.tostring(L, 2)
	if sm == nil || name == nil do return 0
	v: f32
	if lua.type(L, 3) == .BOOLEAN do v = 1 if lua.toboolean(L, 3) else 0
	else do v = f32(lua.tonumber(L, 3))
	StateMachine_SetParam(sm, string(name), v)
	return 0
}

// machine:sm_get(param) -> boolean (bool parameters) / integer (int) / number (float); nil when there's none
@(private="file")
lua_sm_get :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := sm_arg(L)
	name := lua.tostring(L, 2)
	if sm == nil || name == nil {lua.pushnil(L); return 1}
	i := StateMachine_FindParam(sm, string(name))
	if i < 0 {lua.pushnil(L); return 1}
	p := sm.params[i]
	switch p.type {
	case .Bool:  lua.pushboolean(L, b32(p.value != 0))
	case .Int:   lua.pushinteger(L, lua.Integer(p.value))
	case .Float: lua.pushnumber(L, lua.Number(p.value))
	}
	return 1
}

// machine:sm_trigger(name) -> bool: sets a trigger (false + a warning: no such trigger)
@(private="file")
lua_sm_trigger :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := sm_arg(L)
	name := lua.tostring(L, 2)
	lua.pushboolean(L, b32(sm != nil && name != nil && StateMachine_FireTrigger(sm, string(name))))
	return 1
}

// machine:sm_trigger_pending(name) -> bool: set and not used up yet
@(private="file")
lua_sm_trigger_pending :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := sm_arg(L)
	name := lua.tostring(L, 2)
	lua.pushboolean(L, b32(sm != nil && name != nil && StateMachine_TriggerPending(sm, string(name))))
	return 1
}

// machine:sm_clear_trigger(name): un-sets a trigger
@(private="file")
lua_sm_clear_trigger :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := sm_arg(L)
	name := lua.tostring(L, 2)
	if sm != nil && name != nil do StateMachine_ClearTrigger(sm, string(name))
	return 0
}

// sm_transition_opts: {force = bool, blend = seconds} (the optional table at idx).
@(private="file")
sm_transition_opts :: proc(L: ^lua.State, idx: c.int) -> (force: bool, blend: f32) {
	blend = -1
	if lua.type(L, idx) != .TABLE do return
	lua.getfield(L, idx, "force")
	force = bool(lua.toboolean(L, -1))
	lua.pop(L, 1)
	lua.getfield(L, idx, "blend")
	if lua.type(L, -1) == .NUMBER do blend = f32(lua.tonumber(L, -1))
	lua.pop(L, 1)
	return
}

// sm_push_result: true, or false + why (for the state the call asked for).
@(private="file")
sm_push_result :: proc(L: ^lua.State, sm: ^StateMachineNode, block: SM_Block, from, to: string, secs: f32) -> c.int {
	lua.pushboolean(L, b32(block == .None))
	if block == .None do lua.pushnil(L)
	else do lua.pushstring(L, strings.clone_to_cstring(StateMachine_BlockText(sm, block, from, to, secs), context.temp_allocator))
	return 2
}

// machine:sm_transition(state [, {force = true, blend = s}]) -> ok, reason
@(private="file")
lua_sm_transition :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := sm_arg(L)
	name := lua.tostring(L, 2)
	if sm == nil || name == nil {
		lua.pushboolean(L, false)
		lua.pushstring(L, "sm_transition needs a state machine and a state name")
		return 2
	}
	force, blend := sm_transition_opts(L, 3)
	from := StateMachine_CurrentName(sm)
	secs := sm.timeInState
	return sm_push_result(L, sm, StateMachine_Transition(sm, string(name), force, blend, sm_ctx(L)), from, string(name), secs)
}

// machine:sm_can_transition(state [, {force = true}]) -> ok, reason (changes nothing)
@(private="file")
lua_sm_can_transition :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := sm_arg(L)
	name := lua.tostring(L, 2)
	if sm == nil || name == nil {
		lua.pushboolean(L, false)
		lua.pushstring(L, "sm_can_transition needs a state machine and a state name")
		return 2
	}
	force, _ := sm_transition_opts(L, 3)
	block, _ := StateMachine_CanTransition(sm, string(name), force)
	return sm_push_result(L, sm, block, StateMachine_CurrentName(sm), string(name), sm.timeInState)
}

@(private="file")
lua_sm_state :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := sm_arg(L)
	lua.pushstring(L, strings.clone_to_cstring(StateMachine_CurrentName(sm) if sm != nil else "", context.temp_allocator))
	return 1
}

@(private="file")
lua_sm_previous :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := sm_arg(L)
	lua.pushstring(L, strings.clone_to_cstring(StateMachine_PreviousName(sm) if sm != nil else "", context.temp_allocator))
	return 1
}

// sm:sm_history() -> {{from=, to=, time=, why=}, ...} oldest first.
@(private="file")
lua_sm_history :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := sm_arg(L)
	lua.newtable(L)
	if sm == nil do return 1
	for h, i in StateMachine_History(sm) {
		lua.newtable(L)
		lua.pushstring(L, strings.clone_to_cstring(h.from, context.temp_allocator)); lua.setfield(L, -2, "from")
		lua.pushstring(L, strings.clone_to_cstring(h.to, context.temp_allocator)); lua.setfield(L, -2, "to")
		lua.pushnumber(L, lua.Number(h.time)); lua.setfield(L, -2, "time")
		lua.pushstring(L, strings.clone_to_cstring(h.why, context.temp_allocator)); lua.setfield(L, -2, "why")
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

@(private="file")
lua_sm_time :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := sm_arg(L)
	lua.pushnumber(L, lua.Number(sm.timeInState if sm != nil else 0))
	return 1
}

// machine:sm_start([state])
@(private="file")
lua_sm_start :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := sm_arg(L)
	if sm == nil do return 0
	name := lua.tostring(L, 2) if lua.gettop(L) >= 2 else nil
	if name != nil && StateMachine_FindState(sm, string(name)) < 0 {
		log.warnf("sm_start: no state '%s' on %s (starting in the initial state)", string(name), sm.name)
	}
	StateMachine_Start(sm, string(name) if name != nil else "", sm_ctx(L))
	return 0
}

@(private="file")
lua_sm_stop :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if sm := sm_arg(L); sm != nil do StateMachine_Stop(sm)
	return 0
}

// --- node.<property>: property-style access -------------------------------------

// node.key: a method, else `name`, else the property at that path (as
// get_property: vectors as Vec2, "script.<name>" a script field).
@(private="file")
lua_node_index :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	push_node_meta(L)
	lua.pushvalue(L, 2)
	lua.rawget(L, -2)
	if !lua.isnil(L, -1) do return 1 // a method
	lua.pop(L, 2)
	if lua.type(L, 2) != .STRING {lua.pushnil(L); return 1}
	if string(lua.tostring(L, 2)) == "name" {
		node, ok := to_node_userdata(L, 1)
		if !ok {lua.pushnil(L); return 1}
		lua.pushstring(L, strings.clone_to_cstring(node.name, context.temp_allocator))
		return 1
	}
	return lua_node_get_property(L) // (node, path)
}

// node.key = value: `name` renames, anything else sets the property (as
// set_property; an unknown one is an error).
@(private="file")
lua_node_newindex :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if lua.type(L, 2) == .STRING && string(lua.tostring(L, 2)) == "name" {
		node, ok := to_node_userdata(L, 1)
		if ok && lua.type(L, 3) == .STRING do node.name = strings.clone(string(lua.tostring(L, 3)), node.allocator)
		return 0
	}
	return lua_node_set_property(L) // (node, path, value)
}

// --- node:set_property / get_property: any Inspector property by path -------
//
// "script.<name>" is a field of the node's script (its exported properties,
// or any other value the script keeps in `self`): read and written live.

// script_field: "script.health" -> "health".
@(private="file")
script_field :: proc(path: string) -> (string, bool) {
	if !strings.has_prefix(path, "script.") do return "", false
	return path[len("script."):], true
}

// push_script_self pushes the node's script instance (its `self` table).
@(private="file")
push_script_self :: proc(L: ^lua.State, node: ^Node) -> bool {
	if node == nil || node.scriptInstance == nil do return false
	inst := cast(^ScriptInstance)node.scriptInstance
	if inst.registryRef == 0 do return false
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef))
	return true
}

// node:get_script(): the node's script instance - the `self` its script
// sees (fields and methods) - or nil.
@(private="file")
lua_node_get_script :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || !push_script_self(L, node) do lua.pushnil(L)
	return 1
}


// node:set_property(path, value...): numbers, booleans, {x, y} / x, y,
// {r, g, b[, a]} colours (0..1), enum names, strings.
@(private="file")
lua_node_set_property :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	name := lua.tostring(L, 2)
	if !ok || name == nil do return 0
	if field, isScript := script_field(string(name)); isScript {
		if !push_script_self(L, node) {
			lua.L_error(L, "set_property: %s has no script", strings.clone_to_cstring(node.name, context.temp_allocator))
			return 0
		}
		// self[field] = value (x, y given separately become {x, y}).
		if lua.gettop(L) >= 4 && lua.type(L, 3) == .NUMBER && lua.type(L, 4) == .NUMBER {
			lua.createtable(L, 2, 0)
			lua.pushvalue(L, 3); lua.rawseti(L, -2, 1)
			lua.pushvalue(L, 4); lua.rawseti(L, -2, 2)
		} else {
			lua.pushvalue(L, 3)
		}
		lua.setfield(L, -2, strings.clone_to_cstring(field, context.temp_allocator))
		lua.pop(L, 1)
		return 0
	}
	p, found := Node_FindProperty(node, string(name))
	if !found {
		lua.L_error(L, "set_property: %s has no property '%s'", strings.clone_to_cstring(node.name, context.temp_allocator), name)
		return 0
	}
	num :: proc(L: ^lua.State, i: c.int) -> f32 {return f32(lua.tonumber(L, i))}
	tbl :: proc(L: ^lua.State, k: lua.Integer) -> f32 {
		lua.rawgeti(L, 3, k)
		defer lua.pop(L, 1)
		return f32(lua.tonumber(L, -1))
	}
	switch p.kind {
	case .Float: Property_SetFloat(p, num(L, 3))
	case .Int:   Property_SetInt(p, i64(lua.tointeger(L, 3)))
	case .Bool:  (^bool)(p.ptr)^ = bool(lua.toboolean(L, 3))
	case .Vec2:
		x, y := arg_xy(L, 3) // x, y or a vector ({x =, y =} / {x, y})
		(^[2]f32)(p.ptr)^ = {x, y}
	case .Color:
		ch :: proc(v: f32) -> u8 {return u8(clamp(v, 0, 1) * 255 + 0.5)}
		if lua.type(L, 3) == .TABLE {
			a: f32 = 1
			lua.rawgeti(L, 3, 4)
			if lua.type(L, -1) == .NUMBER do a = f32(lua.tonumber(L, -1))
			lua.pop(L, 1)
			(^rl.Color)(p.ptr)^ = {ch(tbl(L, 1)), ch(tbl(L, 2)), ch(tbl(L, 3)), ch(a)}
		} else if lua.type(L, 3) == .STRING {
			// "#rrggbb" / "#rrggbbaa", as in scene files.
			if c, ok := Color_FromHex(string(lua.tostring(L, 3))); ok do (^rl.Color)(p.ptr)^ = c
		}
	case .Enum:
		if s := lua.tostring(L, 3); s != nil {
			for n, i in Property_EnumNames(p) do if strings.equal_fold(n, string(s)) do Property_SetEnumIndex(p, i)
		}
	case .Bit_Set:
	case .String:
		if s := lua.tostring(L, 3); s != nil do Property_SetString(node, p, string(s))
	case .String_List: Property_SetList(node, p, Lua_ToStringList(L, 3)) // a table of lines (#227)
	}
	Node_PropertyChanged(node, p.name)
	return 0
}

// node:get_property(path) -> value (vectors and colours as tables)
@(private="file")
lua_node_get_property :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	name := lua.tostring(L, 2)
	if !ok || name == nil {lua.pushnil(L); return 1}
	if field, isScript := script_field(string(name)); isScript {
		if !push_script_self(L, node) {lua.pushnil(L); return 1}
		lua.getfield(L, -1, strings.clone_to_cstring(field, context.temp_allocator))
		lua.remove(L, -2) // self
		return 1
	}
	p, found := Node_FindProperty(node, string(name))
	if !found {
		script_warn_once(L, string(name), "get_property: %s has no property \"%s\"", node.name, string(name))
		lua.pushnil(L)
		return 1
	}
	switch p.kind {
	case .Float: lua.pushnumber(L, lua.Number(Property_GetFloat(p)))
	case .Int:   lua.pushinteger(L, lua.Integer(Property_GetInt(p)))
	case .Bool:  lua.pushboolean(L, b32((^bool)(p.ptr)^))
	case .Vec2:
		Lua_PushVec2(L, (^[2]f32)(p.ptr)^) // a Vec2 (v.x / v[1])
	case .Color:
		col := (^rl.Color)(p.ptr)^
		lua.createtable(L, 4, 0)
		for v, i in ([4]u8{col.r, col.g, col.b, col.a}) {
			lua.pushnumber(L, lua.Number(f32(v) / 255))
			lua.rawseti(L, -2, lua.Integer(i + 1))
		}
	case .Enum:
		names := Property_EnumNames(p)
		i := Property_GetEnumIndex(p)
		lua.pushstring(L, strings.clone_to_cstring(names[i] if i < len(names) else "", context.temp_allocator))
	case .Bit_Set: lua.pushnil(L)
	case .String: lua.pushstring(L, strings.clone_to_cstring((^string)(p.ptr)^, context.temp_allocator))
	case .String_List: Lua_PushStringList(L, Property_GetList(p))
	}
	return 1
}

// --- collision layers by name -------------------------------------------------

@(private="file")
layers_arg :: proc(L: ^lua.State, from: c.int) -> (set: CollisionLayerSet, ok: bool) {
	ok = true
	add :: proc(L: ^lua.State, i: c.int, set: ^CollisionLayerSet) -> bool {
		if lua.type(L, i) == .NUMBER {
			n := int(lua.tointeger(L, i))
			if n < 1 || n > 16 do return false
			set^ += {CollisionLayer(n - 1)}
			return true
		}
		s := lua.tostring(L, i)
		if s == nil do return false
		l, found := CollisionLayer_Parse(string(s))
		if found do set^ += {l}
		return found
	}
	for i in from ..= lua.gettop(L) {
		if lua.type(L, i) == .TABLE {
			n := c.int(lua.rawlen(L, i))
			for k in 1 ..= n {
				lua.rawgeti(L, i, lua.Integer(k))
				if !add(L, lua.gettop(L), &set) do ok = false
				lua.pop(L, 1)
			}
		} else if !add(L, i, &set) {
			ok = false
		}
	}
	return
}

@(private="file")
set_layers :: proc(L: ^lua.State, mask: bool) -> c.int {
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	set, valid := layers_arg(L, 2)
	if !valid do lua.L_error(L, "unknown collision layer (names from Project Settings > Physics, or 1-16)")
	if node.typeId == CharacterMoverNode {
		cm := cast(^CharacterMoverNode)node
		if mask do cm.maskLayers = set
		else do cm.categoryLayers = set
	} else if node.typeId == RaycastNode {
		rc := cast(^RaycastNode)node
		if mask do rc.maskLayers = set
		else do rc.categoryLayers = set
	}
	for &s in Physics_BodyShapes(node) {
		if mask do s.maskLayers = set
		else do s.categoryLayers = set
	}
	return 0
}

// body:set_collision_layer("Player"[, ...]): the layers its shapes are on.
@(private="file")
lua_node_set_collision_layer :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	return set_layers(L, false)
}

// body:set_collision_mask("World", "Enemies"[, ...]): the layers it collides with.
@(private="file")
lua_node_set_collision_mask :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	return set_layers(L, true)
}

// Physics.layer_name(n) -> the project's name for layer n (1-16), or "".
@(private="file")
lua_physics_layer_name :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	n := int(lua.tointeger(L, 1))
	lua.pushstring(L, strings.clone_to_cstring(collisionLayerNames[n - 1] if n >= 1 && n <= 16 else "", context.temp_allocator))
	return 1
}

// --- Navigation -------------------------------------------------------------------

@(private="file")
nav_opts :: proc(L: ^lua.State, idx: c.int) -> Nav_Options {
	o := Nav_DefaultOptions()
	if lua.type(L, idx) != .TABLE do return o
	lua.getfield(L, idx, "diagonal")
	if lua.type(L, -1) == .BOOLEAN do o.diagonal = bool(lua.toboolean(L, -1))
	lua.pop(L, 1)
	lua.getfield(L, idx, "smooth")
	if lua.type(L, -1) == .BOOLEAN do o.smooth = bool(lua.toboolean(L, -1))
	lua.pop(L, 1)
	lua.getfield(L, idx, "walkable_painted")
	if lua.type(L, -1) == .BOOLEAN do o.walkablePainted = bool(lua.toboolean(L, -1))
	lua.pop(L, 1)
	lua.getfield(L, idx, "radius")
	if lua.type(L, -1) == .NUMBER do o.radius = f32(lua.tonumber(L, -1))
	lua.pop(L, 1)
	return o
}

// find_path(map, x1, y1, x2, y2 [, opts]) at stack index `mapIdx`.
@(private="file")
nav_find :: proc(L: ^lua.State, mapIdx: c.int) -> c.int {
	node, ok := to_node_userdata(L, mapIdx)
	if !ok {lua.pushnil(L); return 1}
	opts := nav_opts(L, mapIdx + 5)
	g := Nav_GridFor(node, opts)
	from := [2]f32{f32(lua.tonumber(L, mapIdx + 1)), f32(lua.tonumber(L, mapIdx + 2))}
	to := [2]f32{f32(lua.tonumber(L, mapIdx + 3)), f32(lua.tonumber(L, mapIdx + 4))}
	path := Nav_FindPath(g, from, to, opts)
	if path == nil {lua.pushnil(L); return 1}
	lua.createtable(L, c.int(len(path)), 0)
	for p, i in path {
		lua.createtable(L, 2, 0)
		lua.pushnumber(L, lua.Number(p.x)); lua.rawseti(L, -2, 1)
		lua.pushnumber(L, lua.Number(p.y)); lua.rawseti(L, -2, 2)
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

// map:nav_find_path(x1, y1, x2, y2 [, {diagonal, smooth, walkable_painted}])
// -> { {x, y}, ... } or nil (TileMap / LDtk level nodes)
@(private="file")
lua_node_nav_find_path :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	return nav_find(L, 1)
}

// Navigation.find_path(map, x1, y1, x2, y2 [, opts])
@(private="file")
lua_navigation_find_path :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	return nav_find(L, 1)
}

// map:nav_is_walkable(x, y) -> bool
@(private="file")
lua_node_nav_is_walkable :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	walk := false
	if ok {
		opts := nav_opts(L, 4)
		if g := Nav_GridFor(node, opts); g != nil {
			rc := opts.radius / max(min(g.cell.x, g.cell.y), 0.0001)
			if rc > 0 do Nav_Clearance(g)
			walk = Nav_Walkable(g, Nav_CellAt(g, {f32(lua.tonumber(L, 2)), f32(lua.tonumber(L, 3))}), rc)
		}
	}
	lua.pushboolean(L, b32(walk))
	return 1
}

// --- Text, dialogue, localization ------------------------------------------------

// node:set_text(text): a TextNode (restarts its typewriter), UI label,
// button or text input (raises its value_changed).
@(private="file")
lua_node_set_text :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	s := lua.tostring(L, 2)
	if !ok || s == nil do return 0
	switch node.typeId {
	case TextNode:     TextNode_SetText(cast(^TextNode)node, string(s))
	case UILabelNode:  (cast(^UILabelNode)node).text = strings.clone(string(s), node.allocator)
	case UIButtonNode: (cast(^UIButtonNode)node).text = strings.clone(string(s), node.allocator)
	case UITextInputNode: UITextInputNode_SetText(cast(^UITextInputNode)node, string(s), node.gameContext)
	}
	return 0
}

@(private="file")
lua_node_get_text :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	text := ""
	if ok {
		switch node.typeId {
		case TextNode:     text = (cast(^TextNode)node).text
		case UILabelNode:  text = (cast(^UILabelNode)node).text
		case UIButtonNode: text = (cast(^UIButtonNode)node).text
		case UITextInputNode: text = UITextInputNode_GetText(cast(^UITextInputNode)node)
		}
	}
	lua.pushstring(L, strings.clone_to_cstring(text, context.temp_allocator))
	return 1
}

// text:text_restart(): types the text out again.
@(private="file")
lua_node_text_restart :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if ok && node.typeId == TextNode {
		t := cast(^TextNode)node
		t.revealed = 0
		t.revealDone = false
	}
	return 0
}

@(private="file")
dialogue_arg :: proc(L: ^lua.State) -> ^DialogueNode {
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != DialogueNode do return nil
	return cast(^DialogueNode)node
}

// box:dialogue_show({ {speaker = "Ada", text = "..."}, "plain line", ... })
// or box:dialogue_show(text [, speaker])
@(private="file")
lua_node_dialogue_show :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	d := dialogue_arg(L)
	if d == nil do return 0
	lines := make([dynamic]Dialogue_Line, context.temp_allocator)
	str :: proc(L: ^lua.State, idx: c.int) -> string {
		s := lua.tostring(L, idx)
		return strings.clone(string(s), context.temp_allocator) if s != nil else ""
	}
	if lua.type(L, 2) == .TABLE {
		n := c.int(lua.rawlen(L, 2))
		for i in 1 ..= n {
			lua.rawgeti(L, 2, lua.Integer(i))
			if lua.type(L, -1) == .TABLE {
				lua.getfield(L, -1, "speaker")
				speaker := str(L, -1)
				lua.pop(L, 1)
				lua.getfield(L, -1, "text")
				text := str(L, -1)
				lua.pop(L, 1)
				lua.getfield(L, -1, "voice")
				voice := str(L, -1)
				lua.pop(L, 1)
				choices := make([dynamic]string, context.temp_allocator)
				lua.getfield(L, -1, "choices")
				if lua.type(L, -1) == .TABLE {
					for j in 1 ..= c.int(lua.rawlen(L, -1)) {
						lua.rawgeti(L, -1, lua.Integer(j))
						append(&choices, str(L, -1))
						lua.pop(L, 1)
					}
				}
				lua.pop(L, 1)
				append(&lines, Dialogue_Line{speaker, text, voice, choices[:]})
			} else {
				append(&lines, Dialogue_Line{"", str(L, -1), "", nil})
			}
			lua.pop(L, 1)
		}
	} else {
		append(&lines, Dialogue_Line{str(L, 3) if lua.gettop(L) >= 3 else "", str(L, 2), "", nil})
	}
	DialogueNode_Show(d, lines[:])
	return 0
}

@(private="file")
lua_node_dialogue_next :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if d := dialogue_arg(L); d != nil do DialogueNode_Advance(d, sm_game_ctx(L))
	return 0
}

@(private="file")
lua_node_dialogue_close :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if d := dialogue_arg(L); d != nil do DialogueNode_Close(d, sm_game_ctx(L))
	return 0
}

@(private="file")
lua_node_dialogue_is_open :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	d := dialogue_arg(L)
	lua.pushboolean(L, b32(d != nil && DialogueNode_IsOpen(d)))
	return 1
}

// box:dialogue_choose(i): takes choice i (1-based) of the shown line.
@(private="file")
lua_node_dialogue_choose :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	d := dialogue_arg(L)
	lua.pushboolean(L, b32(d != nil && DialogueNode_Choose(d, int(lua.L_checkinteger(L, 2)) - 1, sm_game_ctx(L))))
	return 1
}

@(private="file")
lua_node_dialogue_has_choices :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	d := dialogue_arg(L)
	lua.pushboolean(L, b32(d != nil && DialogueNode_HasChoices(d) && d.lineDone))
	return 1
}

// box:dialogue_set_auto(on [, delay]) / box:dialogue_set_skip(on)
@(private="file")
lua_node_dialogue_set_auto :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if d := dialogue_arg(L); d != nil {
		d.autoAdvance = bool(lua.toboolean(L, 2))
		if lua.isnumber(L, 3) do d.autoDelay = max(f32(lua.tonumber(L, 3)), 0)
	}
	return 0
}

@(private="file")
lua_node_dialogue_set_skip :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if d := dialogue_arg(L); d != nil do d.skip = bool(lua.toboolean(L, 2))
	return 0
}

@(private="file")
sm_game_ctx :: proc(L: ^lua.State) -> ^GameContext {
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil do return nil
	return &sm.game.gameContext
}

// tr(key [, {name = value, ...}]) -> the text in the current language.
@(private="file")
lua_tr :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	key := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if key == nil {lua.pushstring(L, ""); return 1}
	args := make(map[string]string, context.temp_allocator)
	if lua.type(L, 2) == .TABLE {
		lua.pushnil(L)
		for lua.next(L, 2) != 0 {
			if lua.type(L, -2) == .STRING {
				k := strings.clone(string(lua.tostring(L, -2)), context.temp_allocator)
				// tostring() without converting the key in place.
				lua.pushvalue(L, -1)
				v := lua.L_tostring(L, -1) // pushes the string
				args[k] = strings.clone(string(v), context.temp_allocator)
				lua.pop(L, 2)
			}
			lua.pop(L, 1)
		}
	}
	game := sm.game if sm != nil else nil
	lua.pushstring(L, strings.clone_to_cstring(Locale_Get(game, string(key), args), context.temp_allocator))
	return 1
}

@(private="file")
lua_locale_set :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	// Locale.set(lang) -> ok: false (and nothing changes) for a language the
	// project has no table for.
	s := lua.tostring(L, 1)
	if s == nil {
		lua.pushboolean(L, false)
		return 1
	}
	sm := get_script_manager(L)
	if sm != nil && sm.game != nil {
		langs := Locale_Languages(sm.game)
		if len(langs) > 0 && !slice.contains(langs, string(s)) {
			log.warnf("Locale.set: no language '%s' (the project has %v)", string(s), langs)
			lua.pushboolean(L, false)
			return 1
		}
	}
	Locale_SetLanguage(string(s))
	lua.pushboolean(L, true)
	return 1
}

@(private="file")
lua_locale_get :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm != nil && sm.game != nil do Locale_Languages(sm.game) // loads the tables
	lua.pushstring(L, strings.clone_to_cstring(Locale_Language(), context.temp_allocator))
	return 1
}

@(private="file")
lua_locale_languages :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	langs: []string
	if sm != nil && sm.game != nil do langs = Locale_Languages(sm.game)
	lua.createtable(L, c.int(len(langs)), 0)
	for l, i in langs {
		lua.pushstring(L, strings.clone_to_cstring(l, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

// --- Line and trail -----------------------------------------------------------------

// line:line_set_points({ {x, y}, ... }) (local to the node)
@(private="file")
lua_node_line_set_points :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != LineNode || lua.type(L, 2) != .TABLE do return 0
	ln := cast(^LineNode)node
	clear(&ln.points)
	n := c.int(lua.rawlen(L, 2))
	for i in 1 ..= n {
		lua.rawgeti(L, 2, lua.Integer(i))
		lua.rawgeti(L, -1, 1)
		x := f32(lua.tonumber(L, -1))
		lua.rawgeti(L, -2, 2)
		y := f32(lua.tonumber(L, -1))
		lua.pop(L, 3)
		append(&ln.points, [2]f32{x, y})
	}
	return 0
}

// line:line_add_point(x, y)
@(private="file")
lua_node_line_add_point :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if ok && node.typeId == LineNode do append(&(cast(^LineNode)node).points, [2]f32{f32(lua.tonumber(L, 2)), f32(lua.tonumber(L, 3))})
	return 0
}

// line:line_clear() / trail:trail_clear()
@(private="file")
lua_node_line_clear :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	if node.typeId == LineNode do clear(&(cast(^LineNode)node).points)
	if node.typeId == TrailNode do TrailNode_Clear(cast(^TrailNode)node)
	return 0
}

@(private="file")
lua_scene_find_node :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	nameC := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if nameC == nil || sm == nil || sm.game == nil || sm.game.sceneManager.currentScene == nil {
		lua.pushnil(L)
		return 1
	}
	targetNode := Scene_FindNodeByName(sm.game.sceneManager.currentScene, string(nameC))
	push_node_userdata(L, targetNode)
	return 1
}

@(private="file")
lua_scene_get_name :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || sm.game.sceneManager.currentScene == nil {
		lua.pushstring(L, "")
		return 1
	}
	nameC := strings.clone_to_cstring(sm.game.sceneManager.currentScene.name, context.temp_allocator)
	lua.pushstring(L, nameC)
	return 1
}

// scene_transition_options reads Scene.change_scene's options table:
// transition, duration, easing, color ({r, g, b[, a]} 0..1 or "#rrggbb"),
// transition_in / duration_in / easing_in (the uncover half), pause. What
// isn't given comes from the project's default transition.
@(private="file")
scene_transition_options :: proc(L: ^lua.State, idx: c.int, game: ^Game) -> Transition_Spec {
	spec := game.defaultTransition if game.hasDefaultTransition else TRANSITION_DEFAULT
	str :: proc(L: ^lua.State, idx: c.int, key: cstring) -> (string, bool) {
		lua.getfield(L, idx, key)
		defer lua.pop(L, 1)
		if lua.type(L, -1) != .STRING do return "", false
		return strings.clone(string(lua.tostring(L, -1)), context.temp_allocator), true
	}
	num :: proc(L: ^lua.State, idx: c.int, key: cstring) -> (f32, bool) {
		lua.getfield(L, idx, key)
		defer lua.pop(L, 1)
		if lua.type(L, -1) != .NUMBER do return 0, false
		return f32(lua.tonumber(L, -1)), true
	}
	kind :: proc(L: ^lua.State, game: ^Game, name: string) -> (Transition_Kind, string) {
		k, shader, ok := Transition_Parse(game, name)
		if !ok {
			lua.L_where(L, 1)
			where_ := strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
			lua.pop(L, 1)
			Script_Problem(.Warning, "%sScene.change_scene: no transition %q (a fade instead)", where_, name)
		}
		return k, shader
	}
	ease :: proc(L: ^lua.State, name: string, fallback: Ease) -> Ease {
		if e, ok := Ease_Parse(name); ok do return e
		Script_Problem(.Warning, "Scene.change_scene: no easing %q", name)
		return fallback
	}
	if name, ok := str(L, idx, "transition"); ok do spec.kind, spec.shader = kind(L, game, name)
	if d, ok := num(L, idx, "duration"); ok do spec.duration = d
	if e, ok := str(L, idx, "easing"); ok do spec.ease = ease(L, e, spec.ease)
	if name, ok := str(L, idx, "transition_in"); ok {
		spec.hasIn = true
		spec.inKind, _ = kind(L, game, name)
	}
	if d, ok := num(L, idx, "duration_in"); ok {
		spec.hasIn = true
		spec.inDuration = d
	}
	if e, ok := str(L, idx, "easing_in"); ok {
		spec.hasIn = true
		spec.inEase = ease(L, e, spec.ease)
	}
	if spec.hasIn {
		// What the uncover half doesn't say: as the cover half.
		if _, ok := str(L, idx, "transition_in"); !ok do spec.inKind = spec.kind
		if _, ok := num(L, idx, "duration_in"); !ok do spec.inDuration = spec.duration
		if _, ok := str(L, idx, "easing_in"); !ok do spec.inEase = spec.ease
	}
	lua.getfield(L, idx, "color")
	#partial switch lua.type(L, -1) {
	case .TABLE:
		ch :: proc(L: ^lua.State, k: lua.Integer, fallback: u8) -> u8 {
			lua.rawgeti(L, -1, k)
			defer lua.pop(L, 1)
			if lua.type(L, -1) != .NUMBER do return fallback
			return u8(clamp(f32(lua.tonumber(L, -1)), 0, 1) * 255)
		}
		spec.color = {ch(L, 1, 0), ch(L, 2, 0), ch(L, 3, 0), ch(L, 4, 255)}
	case .STRING:
		spec.color = Ldtk_ParseHexColor(string(lua.tostring(L, -1)), spec.color) // "#rrggbb" / "#rrggbbaa"
	}
	lua.pop(L, 1)
	lua.getfield(L, idx, "pause")
	if lua.type(L, -1) == .BOOLEAN do spec.pause = bool(lua.toboolean(L, -1))
	lua.pop(L, 1)
	return spec
}

// Scene.register_transition(name, shader): a shader transition by name.
@(private="file")
lua_scene_register_transition :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || lua.type(L, 1) != .STRING || lua.type(L, 2) != .STRING {
		lua.L_error(L, "usage: Scene.register_transition(name, \"shaders/my_transition.fs\")")
		return 0
	}
	Transition_Register(sm.game, string(lua.tostring(L, 1)), string(lua.tostring(L, 2)))
	return 0
}

@(private="file")
lua_scene_change_scene :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	nameC := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if nameC == nil || sm == nil || sm.game == nil do return 0
	// Scene.change_scene(name [, {transition = "fade"|"crossfade"|"slide_left"|.., duration = 0.4, easing, color, transition_in, ..., pause, loading, min_time}])
	// A scene name, or its file ("scenes/level_2.scene.json", e.g. a scene property).
	scene, ok := sm.game.sceneManager.scenes[string(nameC)]
	if !ok {
		if s := Game_FindSceneByFile(sm.game, string(nameC)); s != nil do scene, ok = s, true
	}
	if !ok {
		Script_Problem(.Error, "Scene.change_scene: no scene %q (a scene name, or a scene file listed in the project)", string(nameC))
		return 0
	}
	if lua.type(L, 2) == .TABLE {
		spec := scene_transition_options(L, 2, sm.game)
		// loading = "<scene>": through a loading screen (min_time seconds at least).
		lua.getfield(L, 2, "loading")
		if lua.type(L, -1) == .STRING {
			name := strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
			lua.pop(L, 1)
			screen, sok := sm.game.sceneManager.scenes[name]
			if !sok {
				if s := Game_FindSceneByFile(sm.game, name); s != nil do screen, sok = s, true
			}
			if !sok {
				Script_Problem(.Error, "Scene.change_scene: no loading scene %q", name)
				Game_ChangeSceneSpec(sm.game, scene, spec)
				return 0
			}
			lua.getfield(L, 2, "min_time")
			minTime := f32(lua.tonumber(L, -1)) if lua.type(L, -1) == .NUMBER else 0.5
			lua.pop(L, 1)
			spec.duration = max(spec.duration, 0.01)
			Game_ChangeSceneViaSpec(sm.game, scene, screen, spec, minTime)
			return 0
		}
		lua.pop(L, 1)
		Game_ChangeSceneSpec(sm.game, scene, spec)
		return 0
	}
	// No options: the project's default transition (Project Settings), if any.
	if sm.game.hasDefaultTransition {
		Game_ChangeSceneSpec(sm.game, scene, sm.game.defaultTransition)
		return 0
	}
	ChangeScene_ByPtr(&sm.game.sceneManager, scene)
	return 0
}

// Scene.loading_progress() -> 0..1: the scene behind the loading screen.
@(private="file")
lua_scene_loading_progress :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	lua.pushnumber(L, lua.Number(Scene_LoadingProgress(sm.game) if sm != nil && sm.game != nil else 1))
	return 1
}

// Scene.loading_target() -> name | nil: the scene the loading screen waits for.
@(private="file")
lua_scene_loading_target :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || !sm.game.loading.active || sm.game.loading.target == nil {
		lua.pushnil(L)
		return 1
	}
	lua.pushstring(L, strings.clone_to_cstring(sm.game.loading.target.name, context.temp_allocator))
	return 1
}

// scene_by_name_or_file: a scene by name, or by its file
// ("scenes/level_2.scene.json"), as change_scene takes them.
@(private="file")
scene_by_name_or_file :: proc(game: ^Game, name: string) -> ^Scene {
	if s, ok := game.sceneManager.scenes[name]; ok do return s
	return Game_FindSceneByFile(game, name)
}

// Scene.preload(name): load its assets in the background (a little each frame).
@(private="file")
lua_scene_preload :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	nameC := lua.tostring(L, 1)
	if nameC == nil || sm == nil || sm.game == nil do return 0
	if scene := scene_by_name_or_file(sm.game, string(nameC)); scene != nil do Scene_PreloadBegin(sm.game, scene)
	else do Script_Problem(.Error, "Scene.preload: no scene %q (a scene name, or a scene file listed in the project)", string(nameC))
	return 0
}

// Scene.preload_progress(name) -> 0..1
@(private="file")
lua_scene_preload_progress :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	nameC := lua.tostring(L, 1)
	v: f32
	if nameC != nil && sm != nil && sm.game != nil {
		if scene := scene_by_name_or_file(sm.game, string(nameC)); scene != nil do v = Scene_PreloadProgress(sm.game, scene)
	}
	lua.pushnumber(L, lua.Number(v))
	return 1
}

@(private="file")
lua_scene_is_transitioning :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	lua.pushboolean(L, b32(sm != nil && sm.game != nil && sm.game.transition.active))
	return 1
}

// Engine.set_paused(bool): pausable nodes and physics stop; "always" nodes run.
// Engine.set_fullscreen(on) / is_fullscreen(): the game window covering the
// monitor (the frame scales to it) or back to the project's window size.
@(private="file")
lua_engine_set_fullscreen :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm != nil && sm.game != nil do sm.game.fullscreenRequest = bool(lua.toboolean(L, 1))
	return 0
}

@(private="file")
lua_engine_is_fullscreen :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	on := false
	if sm != nil && sm.game != nil do on = sm.game.fullscreenRequest.? or_else sm.game.fullscreen
	lua.pushboolean(L, b32(on))
	return 1
}

@(private="file")
lua_engine_set_paused :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm != nil && sm.game != nil do Game_SetPaused(sm.game, bool(lua.toboolean(L, 1)))
	return 0
}

@(private="file")
lua_engine_is_paused :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	lua.pushboolean(L, b32(sm != nil && sm.game != nil && sm.game.treePaused))
	return 1
}

// node:set_paused(bool): pauses this node and its children (unless "always").
@(private="file")
lua_node_set_paused :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if node, ok := to_node_userdata(L, 1); ok do node.paused = bool(lua.toboolean(L, 2))
	return 0
}

// node:is_paused() -> paused this frame (by itself, a parent or the game)
@(private="file")
lua_node_is_paused :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	lua.pushboolean(L, b32(ok && (node.paused || node.pausedNow)))
	return 1
}

// node:set_pause_mode("inherit" | "pausable" | "always")
@(private="file")
lua_node_set_pause_mode :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if s := lua.tostring(L, 2); ok && s != nil do node.pauseMode = Pause_ModeParse(string(s))
	return 0
}

@(private="file")
lua_scene_reload :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm != nil && sm.game != nil && sm.game.sceneManager.currentScene != nil {
		// (The project's default transition, as change_scene without options.)
		if sm.game.hasDefaultTransition do Game_ChangeSceneSpec(sm.game, sm.game.sceneManager.currentScene, sm.game.defaultTransition)
		else do ChangeScene_ByName(&sm.game.sceneManager, sm.game.sceneManager.currentScene.name)
	}
	return 0
}

@(private="file")
lua_scene_get_nodes :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || sm.game.sceneManager.currentScene == nil || sm.game.sceneManager.currentScene.manager == nil {
		lua.newtable(L)
		return 1
	}
	mgr := sm.game.sceneManager.currentScene.manager
	lua.createtable(L, c.int(len(mgr.nodes)), 0)
	idx := 1
	for node in mgr.nodes {
		if node != nil {
			push_node_userdata(L, node)
			lua.rawseti(L, -2, lua.Integer(idx))
			idx += 1
		}
	}
	return 1
}

@(private="file")
apply_script_props_from_lua :: proc(L: ^lua.State, node: ^Node, tableIdx: c.int, sm: ^ScriptManager) {
	if node == nil || node.scriptInstance == nil || lua.type(L, tableIdx) != .TABLE do return
	inst := cast(^ScriptInstance)node.scriptInstance
	tIdx := lua.absindex(L, tableIdx)

	lua.pushnil(L)
	for lua.next(L, tIdx) != 0 {
		// Key is at -2, value is at -1
		if lua.type(L, -2) == .STRING {
			key := string(lua.tostring(L, -2))
			val: ScriptValue
			val.type = .Float
			#partial switch lua.type(L, -1) {
			case .BOOLEAN:
				val = ScriptValue{type = .Boolean, valBool = bool(lua.toboolean(L, -1))}
			case .NUMBER:
				if lua.isinteger(L, -1) {
					val = ScriptValue{type = .Int, valInt = i64(lua.tointeger(L, -1))}
				} else {
					val = ScriptValue{type = .Float, valFloat = f32(lua.tonumber(L, -1))}
				}
			case .STRING:
				val = ScriptValue{type = .String, valString = string(lua.tostring(L, -1))}
			case .TABLE:
				decl := script_prop_decl(inst, key, sm)
				assetKind := decl.assetKind if decl != nil else ""
				if Script_IsJsonKind(assetKind) {
					jsonText := lua_to_json(L, -1)
					val = ScriptValue{type = .String, valString = jsonText}
				} else if decl != nil && (decl.type == .Color || decl.type == .Vector2) {
					// Check Color or Vector2 based on decl
					if decl.type == .Vector2 {
						vx, vy := arg_xy(L, -1)
						val = ScriptValue{type = .Vector2, valVec2 = {vx, vy}}
					} else {
						// Color
						cVal: [4]f32 = {1, 1, 1, 1}
						for i in 0 ..< 4 {
							lua.rawgeti(L, -1, lua.Integer(i + 1))
							if lua.type(L, -1) == .NUMBER do cVal[i] = f32(lua.tonumber(L, -1))
							lua.pop(L, 1)
						}
						val = ScriptValue{type = .Color, valColor = cVal}
					}
				} else {
					// Fallback: check length or keys
					lua.rawgeti(L, -1, 1)
					has1 := !lua.isnil(L, -1)
					lua.pop(L, 1)
					if has1 {
						// Array table: if 4 elements maybe color, if 2 elements maybe vec2, else JSON
						lenT := lua.rawlen(L, -1)
						if lenT == 2 {
							vx, vy := arg_xy(L, -1)
							val = ScriptValue{type = .Vector2, valVec2 = {vx, vy}}
						} else {
							jsonText := lua_to_json(L, -1)
							val = ScriptValue{type = .String, valString = jsonText}
						}
					} else {
						// Maybe a Vec2 or dictionary table
						vx, vy := arg_xy(L, -1)
						val = ScriptValue{type = .Vector2, valVec2 = {vx, vy}}
					}
				}
			}
			decl := script_prop_decl(inst, key, sm)
			if decl != nil {
				if decl.type == .Int && val.type == .Float do val = {type = .Int, valInt = i64(math.round(val.valFloat))}
				if decl.type == .Float && val.type == .Int do val = {type = .Float, valFloat = f32(val.valInt)}
			}
			ScriptInstance_SetProperty(inst, key, val, sm)
		}
		lua.pop(L, 1) // pop value, keep key for lua.next
	}
}

// Scene.instantiate(component, parent?, pos?, props?): a component instance at
// runtime (added to the parent, else the scene's root; pos is
// local to the parent - two numbers or a vector; props is an optional table of
// property values applied before ready()). Returns its root node.
@(private="file")
lua_scene_instantiate :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || sm.game.sceneManager.currentScene == nil || lua.type(L, 1) != .STRING {
		lua.pushnil(L)
		return 1
	}
	scene := sm.game.sceneManager.currentScene
	path := string(lua.tostring(L, 1))
	parent, _ := to_node_userdata(L, 2)
	root := Scene_InstantiateComponent(scene, path, parent, &sm.game.gameContext)
	if root == nil {
		lua.L_where(L, 1)
		where_ := strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
		lua.pop(L, 1)
		Script_Problem(.Warning, "%sScene.instantiate: no component \"%s\"", where_, path)
		lua.pushnil(L)
		return 1
	}

	propsIdx: c.int = 0
	if !lua.isnoneornil(L, 3) {
		if lua.type(L, 3) == .NUMBER && lua.type(L, 4) == .NUMBER {
			root.position = {f32(lua.tonumber(L, 3)), f32(lua.tonumber(L, 4))}
			if lua.type(L, 5) == .TABLE do propsIdx = 5
		} else if lua.type(L, 3) == .TABLE {
			// Check if arg 3 is Vec2 / position, or props table
			// A Vec2 has metatable with __name == "Vec2" or has "x" / "y" fields
			isPos := false
			lua.getfield(L, 3, "x")
			if lua.type(L, -1) == .NUMBER do isPos = true
			lua.pop(L, 1)
			if !isPos {
				lua.rawgeti(L, 3, 1)
				if lua.type(L, -1) == .NUMBER {
					lua.rawgeti(L, 3, 2)
					if lua.type(L, -1) == .NUMBER && lua.rawlen(L, 3) == 2 do isPos = true
					lua.pop(L, 1)
				}
				lua.pop(L, 1)
			}
			if isPos {
				x, y := arg_xy(L, 3)
				root.position = {x, y}
				if lua.type(L, 4) == .TABLE do propsIdx = 4
			} else {
				propsIdx = 3
			}
		}
	}

	if propsIdx != 0 {
		apply_script_props_from_lua(L, root, propsIdx, sm)
	}

	push_node_userdata(L, root)
	return 1
}

@(private="file")
// Scene.create(type, parent?, x?, y?): a new node of a built-in or custom
// type (its defaults), under parent (the scene's root), at x, y.
lua_scene_create :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || sm.game.sceneManager.currentScene == nil || lua.type(L, 1) != .STRING {
		lua.pushnil(L)
		return 1
	}
	scene := sm.game.sceneManager.currentScene
	ctx := &sm.game.gameContext
	typeName := strings.clone(string(lua.tostring(L, 1)), context.temp_allocator)
	parent, _ := to_node_userdata(L, 2)
	node: ^Node
	if t := CustomNode_FindByName(ctx, typeName); t != nil {
		node = Scene_CreateCustomNode(scene, t, parent, ctx)
	} else if _, known := Node_TypeInfoByName(typeName); known || typeName == "Node" {
		node = Node_CreateByTypeName(scene, typeName, parent)
		if node != nil do node.gameContext = ctx
	} else {
		lua.L_where(L, 1)
		where_ := strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
		lua.pop(L, 1)
		Script_Problem(.Warning, "%sScene.create: no node type \"%s\"", where_, typeName)
	}
	if node == nil {
		lua.pushnil(L)
		return 1
	}
	if lua.type(L, 3) == .NUMBER || lua.type(L, 3) == .TABLE || lua.type(L, 3) == .USERDATA {
		x, y := arg_xy(L, 3)
		node.position = {x, y}
	}
	push_node_userdata(L, node)
	return 1
}

// Scene.find_nodes_of_type(type): the current scene's nodes of a type
// (custom or built-in; node:is), in tree order.
lua_scene_find_nodes_of_type :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	name := lua.tostring(L, 1)
	if name == nil || sm == nil || sm.game == nil || sm.game.sceneManager.currentScene == nil {
		lua.newtable(L)
		return 1
	}
	nodes := Scene_FindNodesOfType(sm.game.sceneManager.currentScene, string(name))
	lua.createtable(L, c.int(len(nodes)), 0)
	for n, i in nodes {
		push_node_userdata(L, n)
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

lua_scene_create_node :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || sm.game.sceneManager.currentScene == nil {
		lua.pushnil(L)
		return 1
	}
	scene := sm.game.sceneManager.currentScene
	typeStrC := lua.tostring(L, 1)
	nameC := lua.tostring(L, 2)
	parent, pOk := to_node_userdata(L, 3)

	typeStr := string(typeStrC) if typeStrC != nil else "Node"
	nodeName := string(nameC) if nameC != nil else ""

	createdNode: ^Node = nil
	added := false // (the *_Create helpers add the node themselves)
	switch strings.to_lower(typeStr, context.temp_allocator) {
	case "texturenode", "texture", "sprite":
		tn := CreateNode(scene.manager, TextureNode)
		TextureNode_Init(tn)
		if nodeName != "" do tn.name = strings.clone(nodeName, tn.allocator)
		createdNode = tn
	case "scriptnode", "script":
		sn := CreateNode(scene.manager, ScriptNode)
		ScriptNode_Init(sn)
		if nodeName != "" do sn.name = strings.clone(nodeName, sn.allocator)
		createdNode = sn
	case "cameranode", "camera":
		cn := CreateNode(scene.manager, CameraNode)
		CameraNode_Init(cn)
		if nodeName != "" do cn.name = strings.clone(nodeName, cn.allocator)
		createdNode = cn
	case "particleemitternode", "particle", "particles":
		pn := CreateNode(scene.manager, ParticleEmitterNode)
		ParticleEmitterNode_Init(pn)
		if nodeName != "" do pn.name = strings.clone(nodeName, pn.allocator)
		createdNode = pn
	case "timernode", "timer":
		tm := CreateNode(scene.manager, TimerNode)
		TimerNode_Init(tm)
		if nodeName != "" do tm.name = strings.clone(nodeName, tm.allocator)
		createdNode = tm
	case "dynamicbodynode", "dynamicbody", "dynamic_body":
		db := DynamicBodyNode_Create(scene, nodeName, parent)
		createdNode, added = db, true
	case "staticbodynode", "staticbody", "static_body":
		sb := StaticBodyNode_Create(scene, nodeName, parent)
		createdNode, added = sb, true
	case "kinematicbodynode", "kinematicbody", "kinematic_body":
		kb := KinematicBodyNode_Create(scene, nodeName, parent)
		createdNode, added = kb, true
	case "charactermovernode", "charactermover", "character_mover":
		cm := CharacterMoverNode_Create(scene, nodeName, parent)
		createdNode, added = cm, true
	case "areanode", "area":
		ar := AreaNode_Create(scene, nodeName, parent)
		createdNode, added = ar, true
	case "raycastnode", "raycast":
		rc := RaycastNode_Create(scene, nodeName, parent)
		createdNode, added = rc, true
	case:
		// Any other registered type (UI widgets, paths, lights, ...; names
		// and search aliases as in Add Node), placed by the registry.
		if t := CustomNode_FindByName(&sm.game.gameContext, typeStr); t != nil {
			n := Scene_CreateCustomNode(scene, t, parent, &sm.game.gameContext)
			if n != nil && nodeName != "" do n.name = strings.clone(nodeName, n.allocator)
			if n == nil do lua.pushnil(L)
			else do push_node_userdata(L, n)
			return 1
		}
		if _, known := Node_TypeInfoByName(typeStr); known {
			n := Node_CreateByTypeName(scene, typeStr, parent)
			if n == nil {
				lua.pushnil(L)
				return 1
			}
			if nodeName != "" do n.name = strings.clone(nodeName, n.allocator)
			n.gameContext = &sm.game.gameContext
			push_node_userdata(L, n)
			return 1
		}
		if !strings.equal_fold(typeStr, "node") {
			log.warnf("Scene.create_node: unknown node type '%s' (made a plain Node)", typeStr)
		}
		nd := CreateNode(scene.manager, Node)
		if nodeName != "" do nd.name = strings.clone(nodeName, nd.allocator)
		createdNode = nd
	}

	if createdNode != nil {
		if !added do SceneAddNode(scene, createdNode, parent)
		push_node_userdata(L, createdNode)
		return 1
	}

	lua.pushnil(L)
	return 1
}

@(private="file")
lua_scene_get_draw_bounds :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || sm.game.sceneManager.currentScene == nil {
		lua.pushboolean(L, false)
		return 1
	}
	lua.pushboolean(L, b32(sm.game.sceneManager.currentScene.drawBounds))
	return 1
}

@(private="file")
lua_scene_set_draw_bounds :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm != nil && sm.game != nil && sm.game.sceneManager.currentScene != nil {
		draw := lua.toboolean(L, 1)
		sm.game.sceneManager.currentScene.drawBounds = bool(draw)
	}
	return 0
}

// ----------------------------------------------------------------------------
// Log Bindings (Engine.Log & print)
// ----------------------------------------------------------------------------

// Script logs (Log.info / warn / error, print) go to `scriptLogSink` when
// set (the editor's Console), else to the logger the game had when
// scripting started - the bindings run with Engine_DefaultContext(),
// whose logger discards everything.
Script_LogSink :: #type proc(level: log.Level, text: string)
scriptLogSink: Script_LogSink
scriptLogger: runtime.Logger

// Script_Problem reports an error or warning about a script - a failing
// callback, a bad call - with its "path.lua:line:" when known: to the sink
// (the editor: Console and Code tab diagnostics), else the game's log.
Script_Problem :: proc(level: log.Level, format: string, args: ..any) {
	text := fmt.tprintf(format, ..args)
	Console_Log(level, text) // (the developer console, when on)
	if scriptLogSink != nil {
		scriptLogSink(level, text)
		return
	}
	if scriptLogger.procedure != nil do context.logger = scriptLogger
	if level >= .Error do log.errorf("%s", text)
	else do log.warnf("%s", text)
}

// script_warn_once: a warning about a call site, once per site + subject
// (a script calling get_node every frame warns once).
@(private="file")
script_warn_once :: proc(L: ^lua.State, subject: string, format: string, args: ..any) {
	@(static) warned: map[string]bool
	lua.L_where(L, 1)
	where_ := strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
	lua.pop(L, 1)
	key := strings.concatenate({where_, subject}, context.temp_allocator)
	if key in warned || len(warned) > 1000 do return
	if warned == nil do warned = make(map[string]bool, Engine_HeapAllocator()) // (lives for the process)
	warned[strings.clone(key, Engine_HeapAllocator())] = true
	Script_Problem(.Warning, "%s%s", where_, fmt.tprintf(format, ..args))
}

// script_log_args joins the call's arguments with tabs, each converted as
// Lua's tostring does (nil, booleans, tables and nodes included).
@(private="file")
script_log_args :: proc(L: ^lua.State) -> string {
	nargs := lua.gettop(L)
	sb := strings.builder_make(context.temp_allocator)
	for i in 1 ..= nargs {
		n: c.size_t
		str := lua.L_tostring(L, c.int(i), &n) // pushes the string
		if str != nil do strings.write_string(&sb, string(str)[:n])
		lua.pop(L, 1)
		if i < nargs do strings.write_string(&sb, "\t")
	}
	return strings.to_string(sb)
}

@(private="file")
script_log :: proc(level: log.Level, text: string) {
	Console_Log(level, text) // (the developer console, when on)
	if scriptLogSink != nil {
		scriptLogSink(level, text)
		return
	}
	if scriptLogger.procedure == nil do return
	context.logger = scriptLogger
	switch level {
	case .Debug, .Info:     log.infof("[Lua] %s", text)
	case .Warning:          log.warnf("[Lua WARN] %s", text)
	case .Error, .Fatal:    log.errorf("[Lua ERROR] %s", text)
	}
}

@(private="file")
lua_log_info :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	script_log(.Info, script_log_args(L))
	return 0
}

@(private="file")
lua_log_warn :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	script_log(.Warning, script_log_args(L))
	return 0
}

@(private="file")
lua_log_error :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	script_log(.Error, script_log_args(L))
	return 0
}

// ----------------------------------------------------------------------------
// Global Project Table (Engine.Project)
// ----------------------------------------------------------------------------

@(private="file")
lua_project_load :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	pathC := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if pathC == nil || sm == nil || sm.game == nil {
		lua.pushboolean(L, false)
		return 1
	}
	ok := sm.game->loadProject(string(pathC))
	lua.pushboolean(L, b32(ok))
	return 1
}

@(private="file")
lua_project_export_rayzr :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	dirC := lua.tostring(L, 1)
	outC := lua.tostring(L, 2)
	sm := get_script_manager(L)
	if dirC == nil || outC == nil || sm == nil || sm.game == nil {
		lua.pushboolean(L, false)
		return 1
	}
	ok := sm.game.exportRayzr(string(dirC), string(outC))
	lua.pushboolean(L, b32(ok))
	return 1
}

@(private="file")
lua_project_serialize_scene :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || sm.game.sceneManager.currentScene == nil {
		lua.pushstring(L, "{}")
		return 1
	}
	jsonStr := Scene_SerializeToJSON(sm.game.sceneManager.currentScene, context.temp_allocator)
	jsonC := strings.clone_to_cstring(jsonStr, context.temp_allocator)
	lua.pushstring(L, jsonC)
	return 1
}

@(private="file")
lua_project_read_file :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	pathC := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if pathC == nil || sm == nil || sm.game == nil {
		lua.pushnil(L)
		return 1
	}
	txt, ok := AssetManager_ReadFileString(&sm.game.assetManager, string(pathC), context.temp_allocator)
	if !ok {
		lua.pushnil(L)
		return 1
	}
	txtC := strings.clone_to_cstring(txt, context.temp_allocator)
	lua.pushstring(L, txtC)
	return 1
}

@(private="file")
lua_project_has_file :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	pathC := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if pathC == nil || sm == nil || sm.game == nil {
		lua.pushboolean(L, false)
		return 1
	}
	if sm.game.assetManager.package_ != nil {
		lua.pushboolean(L, b32(RayzrPackage_HasFile(sm.game.assetManager.package_, string(pathC))))
		return 1
	}
	resolved := AssetManager_ResolveDiskPath(&sm.game.assetManager, string(pathC), context.temp_allocator)
	lua.pushboolean(L, b32(os.exists(resolved) || os.exists(string(pathC))))
	return 1
}

// Registration of all Metatables and Global Tables
// ----------------------------------------------------------------------------

RegisterEngineLuaBindings :: proc(L: ^lua.State, sm: ^ScriptManager) {
	Script_SetManager(L, sm) // (also set by ScriptManager_Init, before any of this runs)

	// 1. "Engine.Node" Metatable
	if lua.L_newmetatable(L, "Engine.Node") != 0 {
		// Type & Identity
		lua.pushcfunction(L, lua_node_get_type)
		lua.setfield(L, -2, "get_type")
		lua.pushcfunction(L, lua_node_get_base_type)
		lua.setfield(L, -2, "get_base_type")
		lua.pushcfunction(L, lua_node_is)
		lua.setfield(L, -2, "is")
		lua.pushcfunction(L, lua_node_get_name)
		lua.setfield(L, -2, "get_name")
		lua.pushcfunction(L, lua_node_set_name)
		lua.setfield(L, -2, "set_name")

		// Transforms
		lua.pushcfunction(L, lua_node_get_position)
		lua.setfield(L, -2, "get_position")
		lua.pushcfunction(L, lua_node_set_position)
		lua.setfield(L, -2, "set_position")
		lua.pushcfunction(L, lua_node_translate)
		lua.setfield(L, -2, "translate")

		lua.pushcfunction(L, lua_node_get_rotation)
		lua.setfield(L, -2, "get_rotation")
		lua.pushcfunction(L, lua_node_set_rotation)
		lua.setfield(L, -2, "set_rotation")
		lua.pushcfunction(L, lua_node_rotate)
		lua.setfield(L, -2, "rotate")

		lua.pushcfunction(L, lua_node_get_scale)
		lua.setfield(L, -2, "get_scale")
		lua.pushcfunction(L, lua_node_set_scale)
		lua.setfield(L, -2, "set_scale")
		lua.pushcfunction(L, lua_node_set_texture)
		lua.setfield(L, -2, "set_texture")
		lua.pushcfunction(L, lua_node_get_node)
		lua.setfield(L, -2, "get_node")

		lua.pushcfunction(L, lua_node_get_global_position)
		lua.setfield(L, -2, "get_global_position")
		lua.pushcfunction(L, lua_node_get_global_rotation)
		lua.setfield(L, -2, "get_global_rotation")

		// Lifecycle & Visibility
		lua.pushcfunction(L, lua_node_is_enabled)
		lua.setfield(L, -2, "is_enabled")
		lua.pushcfunction(L, lua_node_set_enabled)
		lua.setfield(L, -2, "set_enabled")
		lua.pushcfunction(L, lua_node_is_visible)
		lua.setfield(L, -2, "is_visible")
		lua.pushcfunction(L, lua_node_set_visible)
		lua.setfield(L, -2, "set_visible")

		// Tags (node_tags.odin)
		lua.pushcfunction(L, lua_node_add_tag)
		lua.setfield(L, -2, "add_tag")
		lua.pushcfunction(L, lua_node_remove_tag)
		lua.setfield(L, -2, "remove_tag")
		lua.pushcfunction(L, lua_node_has_tag)
		lua.setfield(L, -2, "has_tag")
		lua.pushcfunction(L, lua_node_get_tags)
		lua.setfield(L, -2, "get_tags")

		// Hierarchy
		lua.pushcfunction(L, lua_node_get_component)
		lua.setfield(L, -2, "get_component")
		lua.pushcfunction(L, lua_node_get_instance_root)
		lua.setfield(L, -2, "get_instance_root")
		lua.pushcfunction(L, lua_node_get_parent)
		lua.setfield(L, -2, "get_parent")
		lua.pushcfunction(L, lua_node_get_children)
		lua.setfield(L, -2, "get_children")
		lua.pushcfunction(L, lua_node_get_child)
		lua.setfield(L, -2, "get_child")
		lua.pushcfunction(L, lua_node_add_child)
		lua.setfield(L, -2, "add_child")
		lua.pushcfunction(L, lua_node_remove_child)
		lua.setfield(L, -2, "remove_child")
		lua.pushcfunction(L, lua_node_destroy)
		lua.setfield(L, -2, "destroy")
		lua.pushcfunction(L, lua_node_destroy)
		lua.setfield(L, -2, "queue_free") // the same: removal waits for the end of the frame
		lua.pushcfunction(L, lua_node_set_shader)
		lua.setfield(L, -2, "set_shader")
		lua.pushcfunction(L, lua_node_set_shader_param)
		lua.setfield(L, -2, "set_shader_param")
		lua.pushcfunction(L, lua_node_get_shader_param)
		lua.setfield(L, -2, "get_shader_param")
		lua.pushcfunction(L, lua_node_set_blend_mode)
		lua.setfield(L, -2, "set_blend_mode")
		lua.pushcfunction(L, lua_light_set_color)
		lua.setfield(L, -2, "light_set_color")
		lua.pushcfunction(L, lua_light_set_energy)
		lua.setfield(L, -2, "light_set_energy")
		lua.pushcfunction(L, lua_light_get_energy)
		lua.setfield(L, -2, "light_get_energy")
		lua.pushcfunction(L, lua_light_set_radius)
		lua.setfield(L, -2, "light_set_radius")
		lua.pushcfunction(L, lua_node_set_property)
		lua.setfield(L, -2, "set_property")
		lua.pushcfunction(L, lua_node_get_script)
		lua.setfield(L, -2, "get_script")
		lua.pushcfunction(L, lua_node_line_set_points)
		lua.setfield(L, -2, "line_set_points")
		lua.pushcfunction(L, lua_node_line_add_point)
		lua.setfield(L, -2, "line_add_point")
		lua.pushcfunction(L, lua_node_line_clear)
		lua.setfield(L, -2, "line_clear")
		lua.pushcfunction(L, lua_node_line_clear)
		lua.setfield(L, -2, "trail_clear")
		lua.pushcfunction(L, lua_node_set_paused)
		lua.setfield(L, -2, "set_paused")
		lua.pushcfunction(L, lua_node_is_paused)
		lua.setfield(L, -2, "is_paused")
		lua.pushcfunction(L, lua_node_set_pause_mode)
		lua.setfield(L, -2, "set_pause_mode")
		lua.pushcfunction(L, lua_node_set_text)
		lua.setfield(L, -2, "set_text")
		lua.pushcfunction(L, lua_node_get_text)
		lua.setfield(L, -2, "get_text")
		lua.pushcfunction(L, lua_node_text_restart)
		lua.setfield(L, -2, "text_restart")
		lua.pushcfunction(L, lua_node_dialogue_show)
		lua.setfield(L, -2, "dialogue_show")
		lua.pushcfunction(L, lua_node_dialogue_next)
		lua.setfield(L, -2, "dialogue_next")
		lua.pushcfunction(L, lua_node_dialogue_close)
		lua.setfield(L, -2, "dialogue_close")
		lua.pushcfunction(L, lua_node_dialogue_is_open)
		lua.setfield(L, -2, "dialogue_is_open")
		lua.pushcfunction(L, lua_node_dialogue_choose)
		lua.setfield(L, -2, "dialogue_choose")
		lua.pushcfunction(L, lua_node_dialogue_has_choices)
		lua.setfield(L, -2, "dialogue_has_choices")
		lua.pushcfunction(L, lua_node_dialogue_set_auto)
		lua.setfield(L, -2, "dialogue_set_auto")
		lua.pushcfunction(L, lua_node_dialogue_set_skip)
		lua.setfield(L, -2, "dialogue_set_skip")
		lua.pushcfunction(L, lua_node_nav_find_path)
		lua.setfield(L, -2, "nav_find_path")
		lua.pushcfunction(L, lua_node_nav_is_walkable)
		lua.setfield(L, -2, "nav_is_walkable")
		Script_RegisterNavNodeBindings(L) // nav_rebake, nav_set_blocked, agents (navigation_nodes.odin)
		Script_RegisterAdvCamNodeBindings(L) // add_trauma, make_active, is_active, snap (advanced_camera.odin)
		Script_RegisterSkeletonBindings(L) // skeleton_* (skeleton_node.odin)
		Script_RegisterAsepriteBindings(L) // aseprite_* (aseprite_node.odin)
		lua.pushcfunction(L, lua_node_get_property)
		lua.setfield(L, -2, "get_property")
		lua.pushcfunction(L, lua_node_set_collision_layer)
		lua.setfield(L, -2, "set_collision_layer")
		lua.pushcfunction(L, lua_node_set_collision_mask)
		lua.setfield(L, -2, "set_collision_mask")
		lua.pushcfunction(L, lua_sm_set)
		lua.setfield(L, -2, "sm_set")
		lua.pushcfunction(L, lua_sm_get)
		lua.setfield(L, -2, "sm_get")
		lua.pushcfunction(L, lua_sm_trigger)
		lua.setfield(L, -2, "sm_trigger")
		lua.pushcfunction(L, lua_sm_trigger_pending)
		lua.setfield(L, -2, "sm_trigger_pending")
		lua.pushcfunction(L, lua_sm_clear_trigger)
		lua.setfield(L, -2, "sm_clear_trigger")
		lua.pushcfunction(L, lua_sm_transition)
		lua.setfield(L, -2, "sm_transition")
		lua.pushcfunction(L, lua_sm_can_transition)
		lua.setfield(L, -2, "sm_can_transition")
		lua.pushcfunction(L, lua_sm_state)
		lua.setfield(L, -2, "sm_state")
		lua.pushcfunction(L, lua_sm_previous)
		lua.setfield(L, -2, "sm_previous")
		lua.pushcfunction(L, lua_sm_history)
		lua.setfield(L, -2, "sm_history")
		lua.pushcfunction(L, lua_sm_time)
		lua.setfield(L, -2, "sm_time")
		lua.pushcfunction(L, lua_sm_start)
		lua.setfield(L, -2, "sm_start")
		lua.pushcfunction(L, lua_sm_stop)
		lua.setfield(L, -2, "sm_stop")
		Script_RegisterEventBindings(L) // connect / disconnect / emit
		Script_RegisterLdtkBindings(L)
		Script_RegisterPathBindings(L) // path_* / follow_* (path_node.odin)
		Script_RegisterSpawnerBindings(L) // spawn / spawn_* (spawner_node.odin)
		Script_RegisterLevelGeneratorBindings(L) // generate / *_level_param (level_generator_node.odin)
		Script_RegisterVectorColliderBindings(L) // vector_cut / vector_point_at / ... (vector_collider.odin)
		Script_RegisterTileMapComponentBindings(L) // tilemap_component_at / ... (tilemap_components.odin)
		Script_RegisterTouchControlBindings(L) // touch_get_vector / touch_is_down (touch_controls.odin)
		Script_RegisterFeelNodeBindings(L) // flash / blink / squash (game_feel.odin)
		Script_RegisterViewportBindings(L) // get_texture / refresh / save_png (viewport_node.odin)
		Script_RegisterUIListBindings(L) // ui_set_items / ui_get_items (ui_list_props.odin)

		// DynamicBodyNode Physics
		lua.pushcfunction(L, lua_node_apply_force)
		lua.setfield(L, -2, "apply_force")
		lua.pushcfunction(L, lua_node_apply_impulse)
		lua.setfield(L, -2, "apply_impulse")
		lua.pushcfunction(L, lua_node_get_mass)
		lua.setfield(L, -2, "get_mass")
		lua.pushcfunction(L, lua_node_get_linear_velocity)
		lua.setfield(L, -2, "get_linear_velocity")
		lua.pushcfunction(L, lua_node_set_linear_velocity)
		lua.setfield(L, -2, "set_linear_velocity")
		lua.pushcfunction(L, lua_node_get_angular_velocity)
		lua.setfield(L, -2, "get_angular_velocity")
		lua.pushcfunction(L, lua_node_set_angular_velocity)
		lua.setfield(L, -2, "set_angular_velocity")
		lua.pushcfunction(L, lua_node_get_gravity_scale)
		lua.setfield(L, -2, "get_gravity_scale")
		lua.pushcfunction(L, lua_node_set_gravity_scale)
		lua.setfield(L, -2, "set_gravity_scale")
		lua.pushcfunction(L, lua_node_is_fixed_rotation)
		lua.setfield(L, -2, "is_fixed_rotation")
		lua.pushcfunction(L, lua_node_set_fixed_rotation)
		lua.setfield(L, -2, "set_fixed_rotation")
		lua.pushcfunction(L, lua_node_set_linear_damping)
		lua.setfield(L, -2, "set_linear_damping")
		lua.pushcfunction(L, lua_node_set_angular_damping)
		lua.setfield(L, -2, "set_angular_damping")
		lua.pushcfunction(L, lua_node_is_awake)
		lua.setfield(L, -2, "is_awake")
		lua.pushcfunction(L, lua_node_set_awake)
		lua.setfield(L, -2, "set_awake")

		// CharacterMoverNode
		lua.pushcfunction(L, lua_node_character_move)
		lua.setfield(L, -2, "character_move")
		lua.pushcfunction(L, lua_node_character_is_grounded)
		lua.setfield(L, -2, "character_is_grounded")
		lua.pushcfunction(L, lua_node_character_get_velocity)
		lua.setfield(L, -2, "character_get_velocity")
		lua.pushcfunction(L, lua_node_character_set_velocity)
		lua.setfield(L, -2, "character_set_velocity")
		lua.pushcfunction(L, lua_node_character_set_speed)
		lua.setfield(L, -2, "character_set_speed")
		lua.pushcfunction(L, lua_node_character_set_jump_speed)
		lua.setfield(L, -2, "character_set_jump_speed")
		lua.pushcfunction(L, lua_node_character_move_and_slide)
		lua.setfield(L, -2, "character_move_and_slide")
		lua.pushcfunction(L, lua_node_character_is_on_floor)
		lua.setfield(L, -2, "character_is_on_floor")
		lua.pushcfunction(L, lua_node_character_is_on_wall)
		lua.setfield(L, -2, "character_is_on_wall")
		lua.pushcfunction(L, lua_node_character_is_on_ceiling)
		lua.setfield(L, -2, "character_is_on_ceiling")
		lua.pushcfunction(L, lua_node_character_get_floor_normal)
		lua.setfield(L, -2, "character_get_floor_normal")
		lua.pushcfunction(L, lua_node_character_get_wall_normal)
		lua.setfield(L, -2, "character_get_wall_normal")
		lua.pushcfunction(L, lua_node_character_get_last_motion)
		lua.setfield(L, -2, "character_get_last_motion")
		lua.pushcfunction(L, lua_node_character_get_gravity)
		lua.setfield(L, -2, "character_get_gravity")
		lua.pushcfunction(L, lua_node_character_set_gravity_scale)
		lua.setfield(L, -2, "character_set_gravity_scale")
		lua.pushcfunction(L, lua_node_character_set_control_mode)
		lua.setfield(L, -2, "character_set_control_mode")
		lua.pushcfunction(L, lua_node_character_get_player_index)
		lua.setfield(L, -2, "character_get_player_index")
		lua.pushcfunction(L, lua_node_character_set_player_index)
		lua.setfield(L, -2, "character_set_player_index")

		// AreaNode
		lua.pushcfunction(L, lua_node_area_is_overlapping)
		lua.setfield(L, -2, "area_is_overlapping")
		lua.pushcfunction(L, lua_node_area_get_overlap_count)
		lua.setfield(L, -2, "area_get_overlap_count")
		lua.pushcfunction(L, lua_node_area_get_overlapping_nodes)
		lua.setfield(L, -2, "area_get_overlapping_nodes")
		lua.pushcfunction(L, lua_node_area_set_monitoring)
		lua.setfield(L, -2, "area_set_monitoring")
		lua.pushcfunction(L, lua_node_area_is_monitoring)
		lua.setfield(L, -2, "area_is_monitoring")

		// RaycastNode
		lua.pushcfunction(L, lua_node_raycast_cast)
		lua.setfield(L, -2, "raycast_cast")
		lua.pushcfunction(L, lua_node_raycast_is_colliding)
		lua.setfield(L, -2, "raycast_is_colliding")
		lua.pushcfunction(L, lua_node_raycast_get_hit_point)
		lua.setfield(L, -2, "raycast_get_hit_point")
		lua.pushcfunction(L, lua_node_raycast_get_hit_normal)
		lua.setfield(L, -2, "raycast_get_hit_normal")
		lua.pushcfunction(L, lua_node_raycast_get_hit_fraction)
		lua.setfield(L, -2, "raycast_get_hit_fraction")
		lua.pushcfunction(L, lua_node_raycast_get_hit_node)
		lua.setfield(L, -2, "raycast_get_hit_node")
		lua.pushcfunction(L, lua_node_raycast_set_direction)
		lua.setfield(L, -2, "raycast_set_direction")
		lua.pushcfunction(L, lua_node_raycast_set_length)
		lua.setfield(L, -2, "raycast_set_length")
		lua.pushcfunction(L, lua_node_raycast_set_monitoring)
		lua.setfield(L, -2, "raycast_set_monitoring")
		lua.pushcfunction(L, lua_node_raycast_is_monitoring)
		lua.setfield(L, -2, "raycast_is_monitoring")

		// ParticleEmitterNode
		lua.pushcfunction(L, lua_node_particle_start)
		lua.setfield(L, -2, "particle_start")
		lua.pushcfunction(L, lua_node_particle_stop)
		lua.setfield(L, -2, "particle_stop")
		lua.pushcfunction(L, lua_node_particle_is_emitting)
		lua.setfield(L, -2, "particle_is_emitting")
		lua.pushcfunction(L, lua_node_particle_set_amount)
		lua.setfield(L, -2, "particle_set_amount")
		lua.pushcfunction(L, lua_node_particle_set_lifetime)
		lua.setfield(L, -2, "particle_set_lifetime")
		lua.pushcfunction(L, lua_node_particle_get_last_hit)
		lua.setfield(L, -2, "particle_get_last_hit")
		lua.pushcfunction(L, lua_node_particle_set_texture)
		lua.setfield(L, -2, "particle_set_texture")
		lua.pushcfunction(L, lua_node_particle_emit)
		lua.setfield(L, -2, "particle_emit")
		lua.pushcfunction(L, lua_node_particle_restart)
		lua.setfield(L, -2, "particle_restart")
		lua.pushcfunction(L, lua_node_particle_apply_preset)
		lua.setfield(L, -2, "particle_apply_preset")
		lua.pushcfunction(L, lua_node_particle_get_alive_count)
		lua.setfield(L, -2, "particle_get_alive_count")

		// TextureNode
		lua.pushcfunction(L, lua_node_texture_get_size)
		lua.setfield(L, -2, "texture_get_size")
		lua.pushcfunction(L, lua_node_atlas_set_region)
		lua.setfield(L, -2, "atlas_set_region")
		lua.pushcfunction(L, lua_node_atlas_get_region)
		lua.setfield(L, -2, "atlas_get_region")
		lua.pushcfunction(L, lua_node_texture_set_origin)
		lua.setfield(L, -2, "texture_set_origin")
		lua.pushcfunction(L, lua_node_texture_get_path)
		lua.setfield(L, -2, "texture_get_path")

		// AnimationPlayerNode
		lua.pushcfunction(L, lua_node_animation_play)
		lua.setfield(L, -2, "animation_play")
		lua.pushcfunction(L, lua_node_animation_stop)
		lua.setfield(L, -2, "animation_stop")
		lua.pushcfunction(L, lua_node_animation_pause)
		lua.setfield(L, -2, "animation_pause")
		lua.pushcfunction(L, lua_node_animation_resume)
		lua.setfield(L, -2, "animation_resume")
		lua.pushcfunction(L, lua_node_animation_reset)
		lua.setfield(L, -2, "animation_reset")
		lua.pushcfunction(L, lua_node_animation_set_fps)
		lua.setfield(L, -2, "animation_set_fps")
		lua.pushcfunction(L, lua_node_animation_get_current)
		lua.setfield(L, -2, "animation_get_current")

		// VectorShapeNode
		lua.pushcfunction(L, lua_node_vector_swap)
		lua.setfield(L, -2, "vector_swap")
		lua.pushcfunction(L, lua_node_vector_frames)
		lua.setfield(L, -2, "vector_frames")

		// LipSyncNode
		lua.pushcfunction(L, lua_node_lipsync_play)
		lua.setfield(L, -2, "lipsync_play")
		lua.pushcfunction(L, lua_node_lipsync_stop)
		lua.setfield(L, -2, "lipsync_stop")
		lua.pushcfunction(L, lua_node_lipsync_is_playing)
		lua.setfield(L, -2, "lipsync_is_playing")

		// TimerNode
		lua.pushcfunction(L, lua_node_timer_start)
		lua.setfield(L, -2, "timer_start")
		lua.pushcfunction(L, lua_node_timer_stop)
		lua.setfield(L, -2, "timer_stop")
		lua.pushcfunction(L, lua_node_timer_is_running)
		lua.setfield(L, -2, "timer_is_running")
		lua.pushcfunction(L, lua_node_timer_get_elapsed)
		lua.setfield(L, -2, "timer_get_elapsed")
		lua.pushcfunction(L, lua_node_timer_set_duration)
		lua.setfield(L, -2, "timer_set_duration")
		lua.pushcfunction(L, lua_node_timer_set_loop)
		lua.setfield(L, -2, "timer_set_loop")

		// Sound & Music Node
		lua.pushcfunction(L, lua_node_sound_play)
		lua.setfield(L, -2, "sound_play")
		lua.pushcfunction(L, lua_node_sound_stop)
		lua.setfield(L, -2, "sound_stop")
		lua.pushcfunction(L, lua_node_sound_pause)
		lua.setfield(L, -2, "sound_pause")
		lua.pushcfunction(L, lua_node_sound_resume)
		lua.setfield(L, -2, "sound_resume")
		lua.pushcfunction(L, lua_node_sound_play_index)
		lua.setfield(L, -2, "sound_play_index")
		lua.pushcfunction(L, lua_node_sound_count)
		lua.setfield(L, -2, "sound_count")
		lua.pushcfunction(L, lua_node_sound_last)
		lua.setfield(L, -2, "sound_last")

		lua.pushcfunction(L, lua_node_music_play)
		lua.setfield(L, -2, "music_play")
		lua.pushcfunction(L, lua_node_music_stop)
		lua.setfield(L, -2, "music_stop")
		lua.pushcfunction(L, lua_node_music_pause)
		lua.setfield(L, -2, "music_pause")
		lua.pushcfunction(L, lua_node_music_resume)
		lua.setfield(L, -2, "music_resume")
		lua.pushcfunction(L, lua_node_music_fade)
		lua.setfield(L, -2, "music_fade")

		// CameraNode (Invoked on node)
		lua.pushcfunction(L, lua_node_camera_set_zoom)
		lua.setfield(L, -2, "camera_set_zoom")
		lua.pushcfunction(L, lua_node_camera_get_zoom)
		lua.setfield(L, -2, "camera_get_zoom")
		lua.pushcfunction(L, lua_node_camera_set_target)
		lua.setfield(L, -2, "camera_set_target")
		lua.pushcfunction(L, lua_node_camera_add_target)
		lua.setfield(L, -2, "camera_add_target")
		lua.pushcfunction(L, lua_node_camera_remove_target)
		lua.setfield(L, -2, "camera_remove_target")
		lua.pushcfunction(L, lua_node_camera_clear_targets)
		lua.setfield(L, -2, "camera_clear_targets")
		lua.pushcfunction(L, lua_node_camera_get_target)
		lua.setfield(L, -2, "camera_get_target")
		lua.pushcfunction(L, lua_node_camera_get_targets)
		lua.setfield(L, -2, "camera_get_targets")
		lua.pushcfunction(L, lua_node_camera_set_target_position)
		lua.setfield(L, -2, "camera_set_target_position")
		lua.pushcfunction(L, lua_node_camera_shake)
		lua.setfield(L, -2, "camera_shake")
		lua.pushcfunction(L, lua_node_camera_stop_shake)
		lua.setfield(L, -2, "camera_stop_shake")
		lua.pushcfunction(L, lua_node_camera_is_shaking)
		lua.setfield(L, -2, "camera_is_shaking")
		lua.pushcfunction(L, lua_node_camera_set_limits)
		lua.setfield(L, -2, "camera_set_limits")
		lua.pushcfunction(L, lua_node_camera_clear_limits)
		lua.setfield(L, -2, "camera_clear_limits")

		// LDtk Node
		lua.pushcfunction(L, lua_node_ldtk_get_level_identifier)
		lua.setfield(L, -2, "ldtk_get_level_identifier")

		// node.method(...) (this table), else node.<property> by path:
		// `node.position = Vec2(1, 2)`, `node.rotation = node.rotation + 5`.
		lua.pushcfunction(L, lua_node_index)
		lua.setfield(L, -2, "__index")
		lua.pushcfunction(L, lua_node_newindex)
		lua.setfield(L, -2, "__newindex")
		lua.pushcfunction(L, lua_node_tostring) // lua_eval.odin
		lua.setfield(L, -2, "__tostring")
	}
	lua.pop(L, 1)

	// 2. Global "Engine" table
	lua.newtable(L)
	lua.pushcfunction(L, lua_engine_get_fps)
	lua.setfield(L, -2, "get_fps")
	lua.pushcfunction(L, lua_engine_get_delta_time)
	lua.setfield(L, -2, "get_delta_time")
	lua.pushcfunction(L, lua_engine_get_time)
	lua.setfield(L, -2, "get_time")
	lua.pushcfunction(L, lua_engine_get_window_size)
	lua.setfield(L, -2, "get_window_size")
	lua.pushcfunction(L, lua_engine_get_virtual_size)
	lua.setfield(L, -2, "get_virtual_size")
	lua.pushcfunction(L, lua_engine_set_paused)
	lua.setfield(L, -2, "set_paused")
	Script_RegisterFeelEngineBindings(L) // set_time_scale, hit_stop, slow_motion (game_feel.odin)
	lua.pushcfunction(L, lua_engine_is_paused)
	lua.setfield(L, -2, "is_paused")
	lua.pushcfunction(L, lua_engine_set_fullscreen)
	lua.setfield(L, -2, "set_fullscreen")
	lua.pushcfunction(L, lua_engine_is_fullscreen)
	lua.setfield(L, -2, "is_fullscreen")
	lua.setglobal(L, "Engine")

	// 3. Global "Input" table
	lua.newtable(L)
	lua.pushcfunction(L, lua_input_is_action_pressed)
	lua.setfield(L, -2, "is_action_pressed")
	lua.pushcfunction(L, lua_input_is_action_down)
	lua.setfield(L, -2, "is_action_down")
	lua.pushcfunction(L, lua_input_is_action_released)
	lua.setfield(L, -2, "is_action_released")
	lua.pushcfunction(L, lua_input_get_axis)
	lua.setfield(L, -2, "get_axis")
	Script_RegisterTouchBindings(L) // get_touches, get_tap ... (touch.odin)
	lua.pushcfunction(L, lua_input_get_vector)
	lua.setfield(L, -2, "get_vector")
	lua.pushcfunction(L, lua_input_is_key_pressed)
	lua.setfield(L, -2, "is_key_pressed")
	lua.pushcfunction(L, lua_input_is_key_down)
	lua.setfield(L, -2, "is_key_down")
	lua.pushcfunction(L, lua_input_is_key_released)
	lua.setfield(L, -2, "is_key_released")
	lua.pushcfunction(L, lua_input_is_mouse_button_pressed)
	lua.setfield(L, -2, "is_mouse_button_pressed")
	lua.pushcfunction(L, lua_input_is_mouse_button_down)
	lua.setfield(L, -2, "is_mouse_button_down")
	lua.pushcfunction(L, lua_input_is_mouse_button_released)
	lua.setfield(L, -2, "is_mouse_button_released")
	lua.pushcfunction(L, lua_input_get_mouse_position)
	lua.setfield(L, -2, "get_mouse_position")
	lua.pushcfunction(L, lua_input_get_mouse_wheel_move)
	lua.setfield(L, -2, "get_mouse_wheel_move")
	Script_RegisterRebindBindings(L) // get_bindings, listen, ... (input_rebind.odin)
	Script_RegisterPlayerBindings(L) // players, gamepads, vibrate, glyph (input_players_lua.odin)
	lua.setglobal(L, "Input")

	// 4. Global "Audio" table
	lua.newtable(L)
	lua.pushcfunction(L, lua_audio_play_sound)
	lua.setfield(L, -2, "play_sound")
	lua.pushcfunction(L, lua_audio_play_music)
	lua.setfield(L, -2, "play_music")
	lua.pushcfunction(L, lua_audio_stop_music)
	lua.setfield(L, -2, "stop_music")
	lua.pushcfunction(L, lua_audio_pause_music)
	lua.setfield(L, -2, "pause_music")
	lua.pushcfunction(L, lua_audio_resume_music)
	lua.setfield(L, -2, "resume_music")
	lua.pushcfunction(L, lua_audio_is_music_playing)
	lua.setfield(L, -2, "is_music_playing")
	lua.pushcfunction(L, lua_audio_play_sound_at)
	lua.setfield(L, -2, "play_sound_at")
	lua.pushcfunction(L, lua_audio_set_bus_volume)
	lua.setfield(L, -2, "set_bus_volume")
	lua.pushcfunction(L, lua_audio_get_bus_volume)
	lua.setfield(L, -2, "get_bus_volume")
	lua.pushcfunction(L, lua_audio_set_bus_mute)
	lua.setfield(L, -2, "set_bus_mute")
	lua.pushcfunction(L, lua_audio_set_bus_solo)
	lua.setfield(L, -2, "set_bus_solo")
	lua.pushcfunction(L, lua_audio_set_bus_pan)
	lua.setfield(L, -2, "set_bus_pan")
	lua.pushcfunction(L, lua_audio_get_buses)
	lua.setfield(L, -2, "get_buses")
	lua.pushcfunction(L, lua_audio_bus_peak)
	lua.setfield(L, -2, "bus_peak")
	lua.pushcfunction(L, lua_audio_set_effect)
	lua.setfield(L, -2, "set_effect")
	lua.pushcfunction(L, lua_audio_set_effect_enabled)
	lua.setfield(L, -2, "set_effect_enabled")
	lua.pushcfunction(L, lua_audio_set_lowpass)
	lua.setfield(L, -2, "set_lowpass")
	lua.pushcfunction(L, lua_audio_set_reverb)
	lua.setfield(L, -2, "set_reverb")
	lua.pushcfunction(L, lua_audio_set_listener)
	lua.setfield(L, -2, "set_listener")
	lua.pushcfunction(L, lua_audio_crossfade)
	lua.setfield(L, -2, "crossfade")
	lua.pushcfunction(L, lua_audio_set_music_volume)
	lua.setfield(L, -2, "set_music_volume")
	lua.pushcfunction(L, lua_audio_set_master_volume)
	lua.setfield(L, -2, "set_master_volume")
	lua.setglobal(L, "Audio")

	// 5. Global "Camera" table
	lua.newtable(L)
	lua.pushcfunction(L, lua_camera_get_target_position)
	lua.setfield(L, -2, "get_target_position")
	lua.pushcfunction(L, lua_camera_set_target_position)
	lua.setfield(L, -2, "set_target_position")
	lua.pushcfunction(L, lua_camera_set_target)
	lua.setfield(L, -2, "set_target")
	lua.pushcfunction(L, lua_camera_add_target)
	lua.setfield(L, -2, "add_target")
	lua.pushcfunction(L, lua_camera_remove_target)
	lua.setfield(L, -2, "remove_target")
	lua.pushcfunction(L, lua_camera_clear_targets)
	lua.setfield(L, -2, "clear_targets")
	lua.pushcfunction(L, lua_camera_get_target)
	lua.setfield(L, -2, "get_target")
	lua.pushcfunction(L, lua_camera_get_targets)
	lua.setfield(L, -2, "get_targets")
	lua.pushcfunction(L, lua_camera_get_zoom)
	lua.setfield(L, -2, "get_zoom")
	lua.pushcfunction(L, lua_camera_set_zoom)
	lua.setfield(L, -2, "set_zoom")
	lua.pushcfunction(L, lua_camera_get_offset)
	lua.setfield(L, -2, "get_offset")
	lua.pushcfunction(L, lua_camera_set_offset)
	lua.setfield(L, -2, "set_offset")
	lua.pushcfunction(L, lua_camera_get_rotation)
	lua.setfield(L, -2, "get_rotation")
	lua.pushcfunction(L, lua_camera_set_rotation)
	lua.setfield(L, -2, "set_rotation")
	lua.pushcfunction(L, lua_camera_shake)
	lua.setfield(L, -2, "shake")
	lua.pushcfunction(L, lua_camera_stop_shake)
	lua.setfield(L, -2, "stop_shake")
	lua.pushcfunction(L, lua_camera_is_shaking)
	lua.setfield(L, -2, "is_shaking")
	lua.pushcfunction(L, lua_camera_set_limits)
	lua.setfield(L, -2, "set_limits")
	lua.pushcfunction(L, lua_camera_clear_limits)
	lua.setfield(L, -2, "clear_limits")
	lua.pushcfunction(L, lua_camera_screen_to_world)
	lua.setfield(L, -2, "screen_to_world")
	lua.pushcfunction(L, lua_camera_world_to_screen)
	lua.setfield(L, -2, "world_to_screen")
	lua.pushcfunction(L, lua_camera_get_visible_world_bounds)
	lua.setfield(L, -2, "get_visible_world_bounds")
	Script_RegisterAdvCamCameraBindings(L) // add_trauma, get_active (advanced_camera.odin)
	lua.setglobal(L, "Camera")

	// 6. Global "Physics" table
	lua.newtable(L)
	lua.pushcfunction(L, lua_physics_get_gravity)
	lua.setfield(L, -2, "get_gravity")
	lua.pushcfunction(L, lua_physics_set_gravity)
	lua.setfield(L, -2, "set_gravity")
	lua.pushcfunction(L, lua_physics_set_debug_draw)
	lua.setfield(L, -2, "set_debug_draw")
	lua.pushcfunction(L, lua_physics_get_debug_draw)
	lua.setfield(L, -2, "get_debug_draw")
	lua.pushcfunction(L, lua_physics_is_paused)
	lua.setfield(L, -2, "is_paused")
	lua.pushcfunction(L, lua_physics_set_paused)
	lua.setfield(L, -2, "set_paused")
	lua.pushcfunction(L, lua_physics_raycast)
	lua.setfield(L, -2, "raycast")
	lua.pushcfunction(L, lua_physics_layer_name)
	lua.setfield(L, -2, "layer_name")
	lua.setglobal(L, "Physics")

	// 7. Global "Scene" table
	lua.newtable(L)
	lua.pushcfunction(L, lua_scene_find_node)
	lua.setfield(L, -2, "find_node")
	lua.pushcfunction(L, lua_scene_find_by_tag)
	lua.setfield(L, -2, "find_by_tag")
	lua.pushcfunction(L, lua_scene_set_ambient)
	lua.setfield(L, -2, "set_ambient")
	lua.pushcfunction(L, lua_scene_get_ambient)
	lua.setfield(L, -2, "get_ambient")
	lua.pushcfunction(L, lua_scene_get_name)
	lua.setfield(L, -2, "get_name")
	lua.pushcfunction(L, lua_scene_change_scene)
	lua.setfield(L, -2, "change_scene")
	lua.pushcfunction(L, lua_scene_preload)
	lua.setfield(L, -2, "preload")
	lua.pushcfunction(L, lua_scene_preload_progress)
	lua.setfield(L, -2, "preload_progress")
	lua.pushcfunction(L, lua_scene_loading_progress)
	lua.setfield(L, -2, "loading_progress")
	lua.pushcfunction(L, lua_scene_loading_target)
	lua.setfield(L, -2, "loading_target")
	lua.pushcfunction(L, lua_scene_is_transitioning)
	lua.setfield(L, -2, "is_transitioning")
	lua.pushcfunction(L, lua_scene_register_transition)
	lua.setfield(L, -2, "register_transition")
	lua.pushcfunction(L, lua_scene_reload)
	lua.setfield(L, -2, "reload")
	lua.pushcfunction(L, lua_scene_get_nodes)
	lua.setfield(L, -2, "get_nodes")
	lua.pushcfunction(L, lua_scene_create_node)
	lua.setfield(L, -2, "create_node")
	lua.pushcfunction(L, lua_scene_instantiate)
	lua.setfield(L, -2, "instantiate")
	lua.pushcfunction(L, lua_scene_create)
	lua.setfield(L, -2, "create")
	lua.pushcfunction(L, lua_scene_find_nodes_of_type)
	lua.setfield(L, -2, "find_nodes_of_type")
	lua.pushcfunction(L, lua_scene_get_draw_bounds)
	lua.setfield(L, -2, "get_draw_bounds")
	lua.pushcfunction(L, lua_scene_set_draw_bounds)
	lua.setfield(L, -2, "set_draw_bounds")
	lua.setglobal(L, "Scene")
	Script_RegisterTweenModule(L)
	Script_RegisterVectorModule(L)
	Script_RegisterPoolModule(L)
	Script_RegisterEventsModule(L) // global events (script_events.odin)
	Script_RegisterLevelGenModule(L) // procedural levels (level_gen.odin)
	Script_RegisterAccessibilityModules(L) // Accessibility, Subtitles (accessibility.odin)
	Script_RegisterSaveModule(L)
	Script_RegisterResourceModule(L) // Resource, ResourceBase (script_resources.odin)
	Script_RegisterCrashModule(L) // (crash_report.odin)
	lua.newtable(L)
	lua.pushcfunction(L, lua_navigation_find_path)
	lua.setfield(L, -2, "find_path")
	lua.setglobal(L, "Navigation")
	lua.pushcfunction(L, lua_tr)
	lua.setglobal(L, "tr")
	lua.newtable(L)
	lua.pushcfunction(L, lua_locale_set)
	lua.setfield(L, -2, "set")
	lua.pushcfunction(L, lua_locale_get)
	lua.setfield(L, -2, "get")
	lua.pushcfunction(L, lua_locale_languages)
	lua.setfield(L, -2, "languages")
	lua.setglobal(L, "Locale")

	// 8. Global "Log" table
	lua.newtable(L)
	lua.pushcfunction(L, lua_log_info)
	lua.setfield(L, -2, "info")
	lua.pushcfunction(L, lua_log_warn)
	lua.setfield(L, -2, "warn")
	lua.pushcfunction(L, lua_log_error)
	lua.setfield(L, -2, "error")
	lua.setglobal(L, "Log")
	Script_RegisterConsole(L) // Console (dev_console.odin)
	Script_RegisterTestModule(L) // Test (game_tests.odin)

	// 9. Global "Project" table
	lua.newtable(L)
	lua.pushcfunction(L, lua_project_load)
	lua.setfield(L, -2, "load")
	lua.pushcfunction(L, lua_project_export_rayzr)
	lua.setfield(L, -2, "export_rayzr")
	lua.pushcfunction(L, lua_project_export_rayzr)
	lua.setfield(L, -2, "export_ore") // (the name before the rename: old scripts)
	lua.pushcfunction(L, lua_project_serialize_scene)
	lua.setfield(L, -2, "serialize_scene")
	lua.pushcfunction(L, lua_project_read_file)
	lua.setfield(L, -2, "read_file")
	lua.pushcfunction(L, lua_project_has_file)
	lua.setfield(L, -2, "has_file")
	lua.setglobal(L, "Project")

	// 10. Override standard Lua "print" to use Log.info
	lua.pushcfunction(L, lua_log_info)
	lua.setglobal(L, "print")
}
