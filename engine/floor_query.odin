package engine

import "core:c"
import "core:math"
import lua "lua54"
import b2 "vendor:box2d"

// ============================================================================
// What a body stands on: the node under a Character Mover (it already knows,
// for moving platforms) or a Dynamic Body (from its contacts), where it
// touches, the surface's normal, and on a TileMap the cell and tile there -
// for footstep sounds, ice and mud, damage floors.
//
// Lua: character_get_floor() / body_get_floor() -> a table, or nil in the air.
// ============================================================================

Floor_Info :: struct {
	node:   ^Node,
	point:  [2]f32, // world px
	normal: [2]f32, // points up out of the floor
}

// A floor: a surface whose normal points up within 60 degrees of straight up
// (the Character Mover's floors).
FLOOR_MAX_NORMAL_Y :: -0.5

// floor_owner: the node a floor belongs to - a TileMap's or LDtk level's
// colliders (a transient Static Body made for them) are the map itself.
@(private = "file")
floor_owner :: proc(n: ^Node, ctx: ^GameContext) -> ^Node {
	if n == nil || !n.transient || n.typeId != StaticBodyNode do return n
	gc := ctx if ctx != nil else n.gameContext
	if gc == nil || gc.scene == nil do return n
	if p := GetParent(gc.scene.manager, n); p != nil && (p.typeId == TileMapNode || p.typeId == LdtkLevelNode) do return p
	return n
}

// CharacterMover_Floor: the floor the mover stood on after its last move.
CharacterMover_Floor :: proc(cm: ^CharacterMoverNode) -> (Floor_Info, bool) {
	if cm == nil || !cm.isOnFloor || cm.floorNode == nil do return {}, false
	if !Node_IsAlive(cm.floorNode) || cm.floorNode.removing do return {}, false
	return {node = floor_owner(cm.floorNode, cm.gameContext), point = cm.floorPoint, normal = cm.floorNormal}, true
}

// DynamicBody_Floor: of the body's touching contacts, the one whose surface
// points most upwards (a floor: within 60 degrees of up).
DynamicBody_Floor :: proc(db: ^DynamicBodyNode) -> (Floor_Info, bool) {
	if db == nil || !b2.Body_IsValid(db.bodyId) do return {}, false
	n := b2.Body_GetContactCapacity(db.bodyId)
	if n <= 0 do return {}, false
	contacts := b2.Body_GetContactData(db.bodyId, make([]b2.ContactData, n, context.temp_allocator))
	best: Floor_Info
	found := false
	for cd in contacts {
		m := cd.manifold
		if m.pointCount <= 0 do continue
		// (The normal points from shape A to shape B: from the floor to us
		// when we're B.)
		ours := b2.Shape_GetBody(cd.shapeIdA) == db.bodyId
		up := -m.normal if ours else m.normal
		other := cd.shapeIdB if ours else cd.shapeIdA
		if up.y > FLOOR_MAX_NORMAL_Y do continue
		if found && up.y >= best.normal.y do continue // (not more upright)
		node := cast(^Node)b2.Body_GetUserData(b2.Shape_GetBody(other))
		if node == nil || !Node_IsAlive(node) || node.removing do continue
		p: [2]f32
		for i in 0 ..< m.pointCount do p += m.points[i].point
		best = {node = floor_owner(node, db.gameContext), point = p / f32(m.pointCount), normal = up}
		found = true
	}
	return best, found
}

// push_floor: the Lua table for a floor (or nil).
@(private = "file")
push_floor :: proc(L: ^lua.State, f: Floor_Info, ok: bool) -> c.int {
	if !ok {
		lua.pushnil(L)
		return 1
	}
	lua.newtable(L)
	push_node_userdata(L, f.node)
	lua.setfield(L, -2, "node")
	lua.pushnumber(L, lua.Number(f.point.x))
	lua.setfield(L, -2, "point_x")
	lua.pushnumber(L, lua.Number(f.point.y))
	lua.setfield(L, -2, "point_y")
	Lua_PushVec2(L, f.point)
	lua.setfield(L, -2, "point")
	lua.pushnumber(L, lua.Number(f.normal.x))
	lua.setfield(L, -2, "normal_x")
	lua.pushnumber(L, lua.Number(f.normal.y))
	lua.setfield(L, -2, "normal_y")
	Lua_PushVec2(L, f.normal)
	lua.setfield(L, -2, "normal")
	// The slope: 0 on flat ground (degrees).
	lua.pushnumber(L, lua.Number(math.to_degrees(math.acos(clamp(-f.normal.y, -1, 1)))))
	lua.setfield(L, -2, "angle")
	// On a TileMap: the cell just inside the floor, and its tile.
	if f.node.typeId == TileMapNode {
		tm := cast(^TileMapNode)f.node
		cell := TileMapNode_CellAt(tm, f.point - f.normal)
		lua.pushinteger(L, lua.Integer(cell.x))
		lua.setfield(L, -2, "cell_x")
		lua.pushinteger(L, lua.Integer(cell.y))
		lua.setfield(L, -2, "cell_y")
		lua.pushinteger(L, lua.Integer(TileMapNode_Get(tm, cell.x, cell.y)))
		lua.setfield(L, -2, "tile")
	}
	return 1
}

@(private = "file")
lua_character_get_floor :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	n, ok := to_node_userdata(L, 1)
	if !ok || n.typeId != CharacterMoverNode {
		Script_Problem(.Warning, "character_get_floor: called on %s, not a Character Mover", n.name if ok && n != nil else "something that isn't a node")
		lua.pushnil(L)
		return 1
	}
	f, has := CharacterMover_Floor(cast(^CharacterMoverNode)n)
	return push_floor(L, f, has)
}

@(private = "file")
lua_body_get_floor :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	n, ok := to_node_userdata(L, 1)
	if !ok || n.typeId != DynamicBodyNode {
		Script_Problem(.Warning, "body_get_floor: called on %s, not a Dynamic Body", n.name if ok && n != nil else "something that isn't a node")
		lua.pushnil(L)
		return 1
	}
	f, has := DynamicBody_Floor(cast(^DynamicBodyNode)n)
	return push_floor(L, f, has)
}

// Script_RegisterFloorBindings: the node methods (on the node method table).
Script_RegisterFloorBindings :: proc(L: ^lua.State) {
	lua.pushcfunction(L, lua_character_get_floor)
	lua.setfield(L, -2, "character_get_floor")
	lua.pushcfunction(L, lua_body_get_floor)
	lua.setfield(L, -2, "body_get_floor")
}
