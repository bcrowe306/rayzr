package engine

import "base:runtime"
import "core:c"
import "core:math"
import "core:slice"
import lua "lua54"
import b2 "vendor:box2d"

// ============================================================================
// Physics queries and body helpers for scripts (the physics guide:
// engine/docs/physics_scripting.md):
// - contact details with collision_started (point, normal, impact speed);
// - Physics.cast_shape / overlap_circle / overlap_box / overlap_point /
//   raycast_all, and options for every query (layers, exclude, sensors);
// - collision exceptions between two nodes;
// - forces at a point, torque, angular impulses, mass;
// - a body's shapes read and changed while the game runs;
// - test moves (would this move hit something?).
// ============================================================================

// --- Contact details -------------------------------------------------------

// Collision_Contact: how a contact began, for the body it's delivered to.
Collision_Contact :: struct {
	valid:    bool,
	point:    [2]f32, // world px
	normal:   [2]f32, // points away from the other body (the way it pushes this one)
	velocity: [2]f32, // this body's velocity relative to the other's at the point
	speed:    f32,    // how fast they came together along the normal (px/s, >= 0)
}

// collisionContact: the contact of the collision_started being delivered.
collisionContact: Collision_Contact

// Physics_ContactOf: the contact as body A and as body B see it.
Physics_ContactOf :: proc(sa, sb: b2.ShapeId, m: b2.Manifold, hitSpeed: f32 = 0) -> (forA, forB: Collision_Contact) {
	if !b2.Shape_IsValid(sa) || !b2.Shape_IsValid(sb) do return
	p: [2]f32
	speed := hitSpeed
	n := max(int(m.pointCount), 0)
	for i in 0 ..< n {
		p += m.points[i].point
		speed = max(speed, -m.points[i].normalVelocity)
	}
	if n > 0 do p /= f32(n)
	ba, bb := b2.Shape_GetBody(sa), b2.Shape_GetBody(sb)
	va := b2.Body_GetWorldPointVelocity(ba, p)
	vb := b2.Body_GetWorldPointVelocity(bb, p)
	if speed <= 0 do speed = max(0, b2.Dot(va - vb, m.normal)) // (after the step: a resting touch is ~0)
	forA = {valid = true, point = p, normal = -m.normal, velocity = va - vb, speed = speed}
	forB = {valid = true, point = p, normal = m.normal, velocity = vb - va, speed = speed}
	return
}

// Lua_PushContact pushes a contact table (nil when there's none).
Lua_PushContact :: proc(L: ^lua.State, ct: Collision_Contact) {
	if !ct.valid {
		lua.pushnil(L)
		return
	}
	lua.newtable(L)
	push_xy_fields(L, "point", ct.point)
	push_xy_fields(L, "normal", ct.normal)
	Lua_PushVec2(L, ct.velocity)
	lua.setfield(L, -2, "velocity")
	lua.pushnumber(L, lua.Number(ct.speed))
	lua.setfield(L, -2, "speed")
}

// push_xy_fields: t[name] (a Vec2), t[name_x], t[name_y].
@(private = "file")
push_xy_fields :: proc(L: ^lua.State, name: cstring, v: [2]f32) {
	Lua_PushVec2(L, v)
	lua.setfield(L, -2, name)
	x, y: cstring = "point_x", "point_y"
	if name == "normal" do x, y = "normal_x", "normal_y"
	lua.pushnumber(L, lua.Number(v.x))
	lua.setfield(L, -2, x)
	lua.pushnumber(L, lua.Number(v.y))
	lua.setfield(L, -2, y)
}

// --- Collision exceptions ---------------------------------------------------

@(private = "file")
pair_key :: proc "contextless" (a, b: ^Node) -> [2]rawptr {
	ra, rb := cast(rawptr)a, cast(rawptr)b
	return {ra, rb} if uintptr(ra) <= uintptr(rb) else {rb, ra}
}

// Physics_Excepted: a and b were told not to collide (add_collision_exception).
Physics_Excepted :: proc(pw: ^PhysicsWorld, a, b: ^Node) -> bool {
	if pw == nil || len(pw.exceptions) == 0 || a == nil || b == nil do return false
	return pair_key(a, b) in pw.exceptions
}

// Physics_CustomFilter: Box2D asks before two shapes start colliding.
Physics_CustomFilter :: proc "c" (sa, sb: b2.ShapeId, ctx: rawptr) -> bool {
	context = runtime.default_context()
	pw := cast(^PhysicsWorld)ctx
	if pw == nil || len(pw.exceptions) == 0 do return true
	na := cast(^Node)b2.Body_GetUserData(b2.Shape_GetBody(sa))
	nb := cast(^Node)b2.Body_GetUserData(b2.Shape_GetBody(sb))
	if na == nil || nb == nil do return true
	return pair_key(na, nb) not_in pw.exceptions
}

// Physics_SetException: a and b stop (or start again) colliding. Their
// current contact goes at once.
Physics_SetException :: proc(pw: ^PhysicsWorld, a, b: ^Node, on: bool) {
	if pw == nil || a == nil || b == nil || a == b do return
	k := pair_key(a, b)
	if on {
		if k in pw.exceptions do return
		pw.exceptions[k] = true
	} else {
		if k not_in pw.exceptions do return
		delete_key(&pw.exceptions, k)
	}
	// (The filter is asked when a contact begins: refilter a's shapes.)
	refilter :: proc(n: ^Node) {
		body := Physics_BodyOf(n)
		if !b2.Body_IsValid(body) || !b2.Body_IsEnabled(body) do return
		b2.Body_Disable(body)
		b2.Body_Enable(body)
	}
	refilter(a)
}

// Physics_ForgetNode: a destroyed node's exceptions go.
Physics_ForgetNode :: proc(pw: ^PhysicsWorld, n: ^Node) {
	if pw == nil || len(pw.exceptions) == 0 do return
	raw := cast(rawptr)n
	gone := make([dynamic][2]rawptr, context.temp_allocator)
	for k in pw.exceptions do if k[0] == raw || k[1] == raw do append(&gone, k)
	for k in gone do delete_key(&pw.exceptions, k)
}

// --- Query options ------------------------------------------------------------

// Physics_QueryFilterAll: a Lua query is on every layer, so the layers it
// names alone pick what it hits. (Box2D's default query category is bit 0:
// a shape whose mask left out Layer1 was never found.)
Physics_QueryFilterAll :: proc() -> b2.QueryFilter {
	return {categoryBits = ~u64(0), maskBits = ~u64(0)}
}

Query_Options :: struct {
	filter:  b2.QueryFilter,
	exclude: [dynamic]^Node, // (temp)
	sensors: bool,           // areas are hit too
}

// query_options reads the optional last argument of a query: nothing, the
// layers (names, numbers or a list, as Physics.raycast always took), or a
// table {layers = ..., exclude = {node, ...} or node, sensors = bool}.
query_options :: proc(L: ^lua.State, idx: c.int) -> (q: Query_Options, ok: bool) {
	q.filter = Physics_QueryFilterAll()
	q.exclude = make([dynamic]^Node, context.temp_allocator)
	ok = true
	if idx > lua.gettop(L) || lua.isnil(L, idx) do return
	if lua.type(L, idx) == .TABLE && is_options_table(L, idx) {
		lua.getfield(L, idx, "layers")
		if !lua.isnil(L, -1) {
			set, valid := layers_arg(L, lua.gettop(L))
			if !valid do ok = false
			q.filter.maskBits = CollisionLayerSet_ToBits(set)
		}
		lua.pop(L, 1)
		lua.getfield(L, idx, "exclude")
		if n, isNode := to_node_userdata(L, -1); isNode {
			append(&q.exclude, n)
		} else if lua.type(L, -1) == .TABLE {
			t := lua.gettop(L)
			for k in 1 ..= c.int(lua.rawlen(L, t)) {
				lua.rawgeti(L, t, lua.Integer(k))
				if n2, isNode2 := to_node_userdata(L, -1); isNode2 do append(&q.exclude, n2)
				lua.pop(L, 1)
			}
		}
		lua.pop(L, 1)
		lua.getfield(L, idx, "sensors")
		q.sensors = bool(lua.toboolean(L, -1))
		lua.pop(L, 1)
		return
	}
	set, valid := layers_arg(L, idx)
	if !valid do ok = false
	q.filter.maskBits = CollisionLayerSet_ToBits(set)
	return
}

@(private = "file")
is_options_table :: proc(L: ^lua.State, idx: c.int) -> bool {
	for key in ([3]cstring{"layers", "exclude", "sensors"}) {
		lua.getfield(L, idx, key)
		has := !lua.isnil(L, -1)
		lua.pop(L, 1)
		if has do return true
	}
	return false
}

@(private = "file")
query_rejects :: proc(q: ^Query_Options, shapeId: b2.ShapeId) -> (node: ^Node, reject: bool) {
	if !q.sensors && b2.Shape_IsSensor(shapeId) do return nil, true
	node = cast(^Node)b2.Body_GetUserData(b2.Shape_GetBody(shapeId))
	for e in q.exclude do if e == node do return node, true
	return node, false
}

query_error :: proc(L: ^lua.State) {
	lua.L_error(L, "unknown collision layer (names from Project Settings > General > Collision Layers, or 1-16)")
}

// --- Hits ---------------------------------------------------------------------

Query_Hit :: struct {
	node:     ^Node,
	point:    [2]f32,
	normal:   [2]f32,
	fraction: f32,
}

@(private = "file")
Cast_Query :: struct {
	ctx:     runtime.Context,
	opts:    ^Query_Options,
	all:     bool,
	hits:    [dynamic]Query_Hit, // (temp)
	closest: Query_Hit,
	hit:     bool,
}

@(private = "file")
cast_callback :: proc "c" (shapeId: b2.ShapeId, point, normal: b2.Vec2, fraction: f32, ctx: rawptr) -> f32 {
	q := cast(^Cast_Query)ctx
	context = q.ctx
	node, reject := query_rejects(q.opts, shapeId)
	if reject do return -1
	h := Query_Hit{node = node, point = point, normal = normal, fraction = fraction}
	if q.all {
		append(&q.hits, h)
		return 1 // (every hit along the way)
	}
	q.closest = h
	q.hit = true
	return fraction // (only closer ones from now)
}

Lua_PushHit :: proc(L: ^lua.State, h: Query_Hit) {
	lua.newtable(L)
	lua.pushboolean(L, true)
	lua.setfield(L, -2, "hit")
	push_xy_fields(L, "point", h.point)
	push_xy_fields(L, "normal", h.normal)
	lua.pushnumber(L, lua.Number(h.fraction))
	lua.setfield(L, -2, "fraction")
	if h.node != nil && Node_IsAlive(h.node) {
		push_node_userdata(L, h.node)
		lua.setfield(L, -2, "node")
	}
}

@(private = "file")
world_of :: proc(L: ^lua.State) -> (b2.WorldId, ^PhysicsWorld, bool) {
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || !b2.World_IsValid(sm.game.physicsWorld.worldId) do return {}, nil, false
	return sm.game.physicsWorld.worldId, &sm.game.physicsWorld, true
}

// Physics.raycast(x1, y1, x2, y2, [options]) -> the closest hit or nil
@(private = "file")
lua_physics_raycast :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	return raycast(L, false)
}

// Physics.raycast_all(x1, y1, x2, y2, [options]) -> every hit, nearest first
@(private = "file")
lua_physics_raycast_all :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	return raycast(L, true)
}

@(private = "file")
raycast :: proc(L: ^lua.State, all: bool) -> c.int {
	world, _, ok := world_of(L)
	if !ok {
		if all do lua.newtable(L)
		else do lua.pushnil(L)
		return 1
	}
	x1, y1, next := arg_xy_next(L, 1)
	x2, y2, after := arg_xy_next(L, next)
	opts, valid := query_options(L, after)
	if !valid do query_error(L)
	q := Cast_Query{ctx = context, opts = &opts, all = all, hits = make([dynamic]Query_Hit, context.temp_allocator)}
	_ = b2.World_CastRay(world, {x1, y1}, {x2 - x1, y2 - y1}, opts.filter, cast_callback, &q)
	return push_hits(L, &q)
}

@(private = "file")
push_hits :: proc(L: ^lua.State, q: ^Cast_Query) -> c.int {
	if q.all {
		slice.sort_by(q.hits[:], proc(a, b: Query_Hit) -> bool {return a.fraction < b.fraction})
		lua.createtable(L, c.int(len(q.hits)), 0)
		for h, i in q.hits {
			Lua_PushHit(L, h)
			lua.rawseti(L, -2, lua.Integer(i + 1))
		}
		return 1
	}
	if !q.hit {
		lua.pushnil(L)
		return 1
	}
	Lua_PushHit(L, q.closest)
	return 1
}

// shape_arg reads a query shape: {type = "circle", radius = r} /
// {type = "box", width = w, height = h, rotation = deg} /
// {type = "capsule", radius = r, height = h} - centred on (x, y).
@(private = "file")
shape_arg :: proc(L: ^lua.State, idx: c.int, center: [2]f32) -> (b2.ShapeProxy, bool) {
	if lua.type(L, idx) != .TABLE do return {}, false
	num :: proc(L: ^lua.State, idx: c.int, key: cstring, def: f32) -> f32 {
		lua.getfield(L, idx, key)
		defer lua.pop(L, 1)
		return f32(lua.tonumber(L, -1)) if lua.isnumber(L, -1) else def
	}
	lua.getfield(L, idx, "type")
	kind := string(lua.tostring(L, -1)) if lua.isstring(L, -1) else "circle"
	lua.pop(L, 1)
	switch kind {
	case "circle":
		p := [1]b2.Vec2{center}
		return b2.MakeProxy(p[:], max(num(L, idx, "radius", 8), 0.1)), true
	case "box", "rect":
		w, h := num(L, idx, "width", 16) / 2, num(L, idx, "height", 16) / 2
		rot := DegreesToRot(num(L, idx, "rotation", 0))
		corners := [4]b2.Vec2{{-w, -h}, {w, -h}, {w, h}, {-w, h}}
		for &v in corners do v = center + b2.RotateVector(rot, v)
		return b2.MakeProxy(corners[:], 0), true
	case "capsule":
		r := max(num(L, idx, "radius", 8), 0.1)
		half := max(num(L, idx, "height", 32) / 2 - r, 0)
		p := [2]b2.Vec2{center + {0, -half}, center + {0, half}}
		return b2.MakeProxy(p[:], r), true
	}
	return {}, false
}

// Physics.cast_shape(shape, x1, y1, x2, y2, [options]) -> the first hit or nil
@(private = "file")
lua_physics_cast_shape :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	world, _, ok := world_of(L)
	if !ok {
		lua.pushnil(L)
		return 1
	}
	x1, y1, next := arg_xy_next(L, 2)
	x2, y2, after := arg_xy_next(L, next)
	proxy, isShape := shape_arg(L, 1, {x1, y1})
	if !isShape {
		Script_Problem(.Warning, "Physics.cast_shape: the shape must be a table like {type = \"circle\", radius = 8} (circle, box or capsule)")
		lua.pushnil(L)
		return 1
	}
	opts, valid := query_options(L, after)
	if !valid do query_error(L)
	q := Cast_Query{ctx = context, opts = &opts, hits = make([dynamic]Query_Hit, context.temp_allocator)}
	_ = b2.World_CastShape(world, proxy, {x2 - x1, y2 - y1}, opts.filter, cast_callback, &q)
	return push_hits(L, &q)
}

// --- Overlaps -----------------------------------------------------------------

@(private = "file")
Overlap_Query :: struct {
	ctx:   runtime.Context,
	opts:  ^Query_Options,
	nodes: [dynamic]^Node, // (temp; each once)
	point: [2]f32,
	exact: bool, // (a point: test the shape itself)
}

@(private = "file")
overlap_callback :: proc "c" (shapeId: b2.ShapeId, ctx: rawptr) -> bool {
	q := cast(^Overlap_Query)ctx
	context = q.ctx
	node, reject := query_rejects(q.opts, shapeId)
	if reject || node == nil || !Node_IsAlive(node) do return true
	if q.exact && !b2.Shape_TestPoint(shapeId, q.point) do return true
	for n in q.nodes do if n == node do return true
	append(&q.nodes, node)
	return true
}

@(private = "file")
push_nodes_list :: proc(L: ^lua.State, nodes: []^Node) -> c.int {
	lua.createtable(L, c.int(len(nodes)), 0)
	for n, i in nodes {
		push_node_userdata(L, n)
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

@(private = "file")
overlap_proxy :: proc(L: ^lua.State, proxy: b2.ShapeProxy, optsIdx: c.int) -> c.int {
	world, _, ok := world_of(L)
	if !ok {
		lua.newtable(L)
		return 1
	}
	opts, valid := query_options(L, optsIdx)
	if !valid do query_error(L)
	q := Overlap_Query{ctx = context, opts = &opts, nodes = make([dynamic]^Node, context.temp_allocator)}
	_ = b2.World_OverlapShape(world, proxy, opts.filter, overlap_callback, &q)
	return push_nodes_list(L, q.nodes[:])
}

// Physics.overlap_circle(x, y, radius, [options]) -> the nodes inside
@(private = "file")
lua_physics_overlap_circle :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	x, y, next := arg_xy_next(L, 1)
	r := max(f32(lua.tonumber(L, next)), 0.1)
	p := [1]b2.Vec2{{x, y}}
	return overlap_proxy(L, b2.MakeProxy(p[:], r), next + 1)
}

// Physics.overlap_box(x, y, width, height, [rotation], [options]) -> the nodes inside
@(private = "file")
lua_physics_overlap_box :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	x, y, next := arg_xy_next(L, 1)
	w, h := f32(lua.tonumber(L, next)) / 2, f32(lua.tonumber(L, next + 1)) / 2
	optsIdx := next + 2
	rotDeg: f32
	if lua.type(L, optsIdx) == .NUMBER {
		rotDeg = f32(lua.tonumber(L, optsIdx))
		optsIdx += 1
	}
	rot := DegreesToRot(rotDeg)
	corners := [4]b2.Vec2{{-w, -h}, {w, -h}, {w, h}, {-w, h}}
	for &v in corners do v = [2]f32{x, y} + b2.RotateVector(rot, v)
	return overlap_proxy(L, b2.MakeProxy(corners[:], 0), optsIdx)
}

// Physics.overlap_point(x, y, [options]) -> the nodes whose shapes hold the point
@(private = "file")
lua_physics_overlap_point :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	world, _, ok := world_of(L)
	if !ok {
		lua.newtable(L)
		return 1
	}
	x, y, next := arg_xy_next(L, 1)
	opts, valid := query_options(L, next)
	if !valid do query_error(L)
	q := Overlap_Query{ctx = context, opts = &opts, nodes = make([dynamic]^Node, context.temp_allocator), point = {x, y}, exact = true}
	box := b2.AABB{lowerBound = {x - 0.5, y - 0.5}, upperBound = {x + 0.5, y + 0.5}}
	_ = b2.World_OverlapAABB(world, box, opts.filter, overlap_callback, &q)
	return push_nodes_list(L, q.nodes[:])
}

// --- Collision exceptions (Lua) ---------------------------------------------------

@(private = "file")
two_nodes :: proc(L: ^lua.State, fn: string) -> (a, b: ^Node, pw: ^PhysicsWorld, ok: bool) {
	na, okA := to_node_userdata(L, 1)
	nb, okB := to_node_userdata(L, 2)
	_, w, hasWorld := world_of(L)
	if !okA || !okB || na == nil || nb == nil || !hasWorld {
		Script_Problem(.Warning, "%s: needs another node (got %s)", fn, string(lua.typename(L, lua.type(L, 2))))
		return
	}
	return na, nb, w, true
}

// node:add_collision_exception(other): the two stop colliding with each other.
@(private = "file")
lua_add_collision_exception :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	a, b, pw, ok := two_nodes(L, "add_collision_exception")
	if ok do Physics_SetException(pw, a, b, true)
	lua.pushboolean(L, b32(ok))
	return 1
}

// node:remove_collision_exception(other): they collide again.
@(private = "file")
lua_remove_collision_exception :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	a, b, pw, ok := two_nodes(L, "remove_collision_exception")
	if ok do Physics_SetException(pw, a, b, false)
	lua.pushboolean(L, b32(ok))
	return 1
}

// node:has_collision_exception(other)
@(private = "file")
lua_has_collision_exception :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	a, b, pw, ok := two_nodes(L, "has_collision_exception")
	lua.pushboolean(L, b32(ok && Physics_Excepted(pw, a, b)))
	return 1
}

// --- Forces and mass (Dynamic Body) ---------------------------------------------

@(private = "file")
dyn_body :: proc(L: ^lua.State, fn: string) -> (^DynamicBodyNode, bool) {
	n, ok := to_node_userdata(L, 1)
	if !ok || n.typeId != DynamicBodyNode {
		Script_Problem(.Warning, "%s: called on %s, not a Dynamic Body", fn, n.name if ok && n != nil else "something that isn't a node")
		return nil, false
	}
	db := cast(^DynamicBodyNode)n
	DynamicBodyNode_EnsureBody(db, db.gameContext)
	return db, b2.Body_IsValid(db.bodyId)
}

// apply_force_at(fx, fy, px, py): a force at a world point (it spins the body
// if the point isn't its centre of mass).
@(private = "file")
lua_apply_force_at :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	db, ok := dyn_body(L, "apply_force_at")
	if !ok do return 0
	fx, fy, next := arg_xy_next(L, 2)
	px, py, _ := arg_xy_next(L, next)
	b2.Body_ApplyForce(db.bodyId, {fx, fy}, {px, py}, true)
	return 0
}

// apply_impulse_at(ix, iy, px, py): an instant push at a world point.
@(private = "file")
lua_apply_impulse_at :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	db, ok := dyn_body(L, "apply_impulse_at")
	if !ok do return 0
	ix, iy, next := arg_xy_next(L, 2)
	px, py, _ := arg_xy_next(L, next)
	b2.Body_ApplyLinearImpulse(db.bodyId, {ix, iy}, {px, py}, true)
	return 0
}

// apply_torque(t): a turning force this step (+ clockwise on screen).
@(private = "file")
lua_apply_torque :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	db, ok := dyn_body(L, "apply_torque")
	if !ok do return 0
	b2.Body_ApplyTorque(db.bodyId, f32(lua.tonumber(L, 2)), true)
	return 0
}

// apply_angular_impulse(i): an instant spin.
@(private = "file")
lua_apply_angular_impulse :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	db, ok := dyn_body(L, "apply_angular_impulse")
	if !ok do return 0
	b2.Body_ApplyAngularImpulse(db.bodyId, f32(lua.tonumber(L, 2)), true)
	return 0
}

// get_velocity_at(px, py): the body's velocity at a world point (px/s).
@(private = "file")
lua_get_velocity_at :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	n, ok := to_node_userdata(L, 1)
	body := Physics_BodyOf(n) if ok else {}
	px, py, _ := arg_xy_next(L, 2)
	v := b2.Body_GetWorldPointVelocity(body, {px, py}) if b2.Body_IsValid(body) else [2]f32{}
	lua.pushnumber(L, lua.Number(v.x))
	lua.pushnumber(L, lua.Number(v.y))
	return 2
}

// set_mass(mass): the body's mass (its shapes' densities are scaled to it).
@(private = "file")
lua_set_mass :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	db, ok := dyn_body(L, "set_mass")
	if !ok do return 0
	m := f32(lua.tonumber(L, 2))
	if m <= 0 {
		Script_Problem(.Warning, "set_mass: the mass must be above 0 (got %v)", m)
		return 0
	}
	md := b2.Body_GetMassData(db.bodyId)
	if md.mass > 0 do md.rotationalInertia *= m / md.mass
	md.mass = m
	b2.Body_SetMassData(db.bodyId, md)
	return 0
}

// get_center_of_mass(): the world point it turns about.
@(private = "file")
lua_get_center_of_mass :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	n, ok := to_node_userdata(L, 1)
	body := Physics_BodyOf(n) if ok else {}
	p := b2.Body_GetWorldCenterOfMass(body) if b2.Body_IsValid(body) else [2]f32{}
	lua.pushnumber(L, lua.Number(p.x))
	lua.pushnumber(L, lua.Number(p.y))
	return 2
}

// --- Shapes while the game runs ---------------------------------------------------

// Node_Shapes: a physics node's collision shapes (nil for other nodes).
Node_Shapes :: proc(n: ^Node) -> ^[dynamic]PhysicsShape {
	if n == nil do return nil
	switch n.typeId {
	case StaticBodyNode: return &(cast(^StaticBodyNode)n).shapes
	case DynamicBodyNode: return &(cast(^DynamicBodyNode)n).shapes
	case KinematicBodyNode: return &(cast(^KinematicBodyNode)n).shapes
	case CharacterMoverNode: return &(cast(^CharacterMoverNode)n).shapes
	case AreaNode: return &(cast(^AreaNode)n).shapes
	}
	return nil
}

@(private = "file")
shape_at :: proc(L: ^lua.State, fn: string) -> ^PhysicsShape {
	n, ok := to_node_userdata(L, 1)
	shapes := Node_Shapes(n) if ok else nil
	if shapes == nil {
		Script_Problem(.Warning, "%s: called on %s, which has no collision shapes", fn, n.name if ok && n != nil else "something that isn't a node")
		return nil
	}
	i := int(lua.tointeger(L, 2)) if lua.isnumber(L, 2) else 1
	if i < 1 || i > len(shapes) {
		Script_Problem(.Warning, "%s: %s has %d shape(s); no shape %d", fn, n.name, len(shapes), i)
		return nil
	}
	return &shapes[i - 1]
}

// shape_count(): how many collision shapes the node has.
@(private = "file")
lua_shape_count :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	n, ok := to_node_userdata(L, 1)
	shapes := Node_Shapes(n) if ok else nil
	lua.pushinteger(L, lua.Integer(len(shapes) if shapes != nil else 0))
	return 1
}

@(private = "file")
shape_type_name :: proc(t: PhysicsShapeType) -> cstring {
	#partial switch t {
	case .Circle: return "circle"
	case .Box: return "box"
	case .RoundedBox: return "rounded_box"
	case .Capsule: return "capsule"
	case .Polygon: return "polygon"
	case .Segment: return "segment"
	case .Chain: return "chain"
	}
	return "unknown"
}

// shape_get([i]): a table of shape i's settings (1-based; the first by default).
@(private = "file")
lua_shape_get :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	s := shape_at(L, "shape_get")
	if s == nil {
		lua.pushnil(L)
		return 1
	}
	lua.newtable(L)
	lua.pushstring(L, shape_type_name(s.type))
	lua.setfield(L, -2, "type")
	set_num :: proc(L: ^lua.State, k: cstring, v: f32) {lua.pushnumber(L, lua.Number(v)); lua.setfield(L, -2, k)}
	set_num(L, "radius", s.radius)
	set_num(L, "width", s.size.x)
	set_num(L, "height", s.size.y)
	set_num(L, "rotation", s.rotation)
	Lua_PushVec2(L, s.offset)
	lua.setfield(L, -2, "offset")
	set_num(L, "density", s.density)
	set_num(L, "friction", s.friction)
	set_num(L, "restitution", s.restitution)
	lua.pushboolean(L, b32(s.isSensor))
	lua.setfield(L, -2, "sensor")
	return 1
}

// shape_set(i, {radius =, width =, height =, rotation =, offset =, density =,
// friction =, restitution =, sensor =}): change shape i (only the keys given).
@(private = "file")
lua_shape_set :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	s := shape_at(L, "shape_set")
	if s == nil || lua.type(L, 3) != .TABLE {
		if s != nil do Script_Problem(.Warning, "shape_set: the second argument must be a table of settings, e.g. {friction = 0}")
		lua.pushboolean(L, false)
		return 1
	}
	num :: proc(L: ^lua.State, k: cstring, v: ^f32, lo: f32 = -max(f32)) {
		lua.getfield(L, 3, k)
		if lua.isnumber(L, -1) do v^ = max(f32(lua.tonumber(L, -1)), lo)
		lua.pop(L, 1)
	}
	num(L, "radius", &s.radius, 0.1)
	num(L, "width", &s.size.x, 0.1)
	num(L, "height", &s.size.y, 0.1)
	num(L, "rotation", &s.rotation)
	num(L, "density", &s.density, 0)
	num(L, "friction", &s.friction, 0)
	num(L, "restitution", &s.restitution, 0)
	lua.getfield(L, 3, "offset")
	if !lua.isnil(L, -1) {ox, oy := arg_xy(L, lua.gettop(L)); s.offset = {ox, oy}}
	lua.pop(L, 1)
	lua.getfield(L, 3, "sensor")
	if !lua.isnil(L, -1) do s.isSensor = bool(lua.toboolean(L, -1))
	lua.pop(L, 1)
	// (Box2D gets it with the body's next update: PhysicsShape_SyncToBox2D.)
	lua.pushboolean(L, true)
	return 1
}

// --- Test moves -----------------------------------------------------------------------

// Physics_TestMove: would moving the node's shapes by `motion` hit something?
// The first hit along the way (its fraction of the motion) - the node itself
// and its exceptions aside.
Physics_TestMove :: proc(n: ^Node, motion: [2]f32, pw: ^PhysicsWorld) -> (Query_Hit, bool) {
	body := Physics_BodyOf(n)
	if !b2.Body_IsValid(body) || pw == nil do return {}, false
	opts := Query_Options{filter = b2.DefaultQueryFilter(), exclude = make([dynamic]^Node, context.temp_allocator)}
	append(&opts.exclude, n)
	for k in pw.exceptions {
		if k[0] == cast(rawptr)n do append(&opts.exclude, cast(^Node)k[1])
		else if k[1] == cast(rawptr)n do append(&opts.exclude, cast(^Node)k[0])
	}
	q := Cast_Query{ctx = context, opts = &opts, hits = make([dynamic]Query_Hit, context.temp_allocator)}
	shapes := make([]b2.ShapeId, b2.Body_GetShapeCount(body), context.temp_allocator)
	shapes = b2.Body_GetShapes(body, shapes)
	xf := b2.Body_GetTransform(body)
	for sid in shapes {
		if b2.Shape_IsSensor(sid) do continue
		f := b2.Shape_GetFilter(sid)
		opts.filter = {categoryBits = f.categoryBits, maskBits = f.maskBits}
		local, ok := shape_proxy(sid)
		if !ok do continue
		world: b2.ShapeProxy
		world.count = local.count
		world.radius = local.radius
		for i in 0 ..< int(local.count) do world.points[i] = b2.TransformPoint(xf, local.points[i])
		_ = b2.World_CastShape(pw.worldId, world, motion, opts.filter, cast_callback, &q)
	}
	return q.closest, q.hit
}

// body_test_move(dx, dy) -> the hit (as Physics.cast_shape) or nil: would
// moving by (dx, dy) hit something? Nothing moves.
@(private = "file")
lua_body_test_move :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	n, ok := to_node_userdata(L, 1)
	_, pw, hasWorld := world_of(L)
	if !ok || !hasWorld {
		lua.pushnil(L)
		return 1
	}
	dx, dy, _ := arg_xy_next(L, 2)
	h, hit := Physics_TestMove(n, {dx, dy}, pw)
	if !hit {
		lua.pushnil(L)
		return 1
	}
	Lua_PushHit(L, h)
	return 1
}

// body_move_and_collide(dx, dy) -> the hit or nil: moves a Kinematic or
// Dynamic Body by (dx, dy), stopping where it would first touch something.
@(private = "file")
lua_body_move_and_collide :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	n, ok := to_node_userdata(L, 1)
	_, pw, hasWorld := world_of(L)
	if !ok || !hasWorld || (n.typeId != KinematicBodyNode && n.typeId != DynamicBodyNode) {
		Script_Problem(.Warning, "body_move_and_collide: called on %s, not a Kinematic or Dynamic Body", n.name if ok && n != nil else "something that isn't a node")
		lua.pushnil(L)
		return 1
	}
	body := Physics_BodyOf(n)
	if !b2.Body_IsValid(body) {
		lua.pushnil(L)
		return 1
	}
	dx, dy, _ := arg_xy_next(L, 2)
	motion := [2]f32{dx, dy}
	h, hit := Physics_TestMove(n, motion, pw)
	frac: f32 = h.fraction if hit else 1
	// (Stop just short of the contact.)
	length := math.sqrt(motion.x * motion.x + motion.y * motion.y)
	if hit && length > 0 do frac = max(0, frac - 0.5 / length)
	pos := b2.Body_GetPosition(body) + motion * frac
	rot := b2.Body_GetRotation(body)
	b2.Body_SetTransform(body, pos, rot)
	Physics_SetWorldTransform(n, pos, RotToDegrees(rot))
	physics_moved_by_script(n, pw, pos, RotToDegrees(rot))
	if !hit {
		lua.pushnil(L)
		return 1
	}
	Lua_PushHit(L, h)
	return 1
}

// physics_moved_by_script: a body a script placed - it isn't drawn sliding
// from where it was.
@(private = "file")
physics_moved_by_script :: proc(n: ^Node, pw: ^PhysicsWorld, pos: [2]f32, rot: f32) {
	switch n.typeId {
	case DynamicBodyNode:
		db := cast(^DynamicBodyNode)n
		Physics_InterpReset(&db.interp, pw, pos, rot)
		db.lastSyncedPos, db.lastSyncedRot = db.globalPosition, db.globalRotation
	case KinematicBodyNode:
		kb := cast(^KinematicBodyNode)n
		Physics_InterpReset(&kb.interp, pw, pos, rot)
		kb.lastSyncedPos, kb.lastSyncedRot = kb.globalPosition, kb.globalRotation
	}
}

// --- The fixed step (Lua) -------------------------------------------------------------

// Physics.get_fps(): fixed steps per second (0: one step per frame).
@(private = "file")
lua_physics_get_fps :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	_, pw, ok := world_of(L)
	lua.pushinteger(L, lua.Integer(pw.physicsFps if ok else 0))
	return 1
}

// Physics.set_fps(n): change the fixed step rate (0: one step per frame).
@(private = "file")
lua_physics_set_fps :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	_, pw, ok := world_of(L)
	if !ok do return 0
	n := int(lua.tointeger(L, 1))
	if n < 0 || n > 1000 {
		Script_Problem(.Warning, "Physics.set_fps: %d is out of range (0 for one step per frame, else 1-1000)", n)
		return 0
	}
	pw.physicsFps = n
	pw.accumulator = 0
	return 0
}

// Physics.get_interpolation(): how far this frame is between the last two
// steps (0..1) - for drawing your own things between steps.
@(private = "file")
lua_physics_get_interpolation :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	_, pw, ok := world_of(L)
	lua.pushnumber(L, lua.Number(pw.alpha if ok else 1))
	return 1
}

// --- Registration ---------------------------------------------------------------------

// Script_RegisterPhysicsModuleExtras: on the Physics table (at the top of the stack).
Script_RegisterPhysicsModuleExtras :: proc(L: ^lua.State) {
	fns := [?]struct {name: cstring, fn: lua.CFunction} {
		{"raycast", lua_physics_raycast},
		{"raycast_all", lua_physics_raycast_all},
		{"cast_shape", lua_physics_cast_shape},
		{"overlap_circle", lua_physics_overlap_circle},
		{"overlap_box", lua_physics_overlap_box},
		{"overlap_point", lua_physics_overlap_point},
		{"get_fps", lua_physics_get_fps},
		{"set_fps", lua_physics_set_fps},
		{"get_interpolation", lua_physics_get_interpolation},
	}
	for f in fns {
		lua.pushcfunction(L, f.fn)
		lua.setfield(L, -2, f.name)
	}
}

// Script_RegisterPhysicsNodeExtras: the node methods (on the node method table).
Script_RegisterPhysicsNodeExtras :: proc(L: ^lua.State) {
	fns := [?]struct {name: cstring, fn: lua.CFunction} {
		{"add_collision_exception", lua_add_collision_exception},
		{"remove_collision_exception", lua_remove_collision_exception},
		{"has_collision_exception", lua_has_collision_exception},
		{"apply_force_at", lua_apply_force_at},
		{"apply_impulse_at", lua_apply_impulse_at},
		{"apply_torque", lua_apply_torque},
		{"apply_angular_impulse", lua_apply_angular_impulse},
		{"get_velocity_at", lua_get_velocity_at},
		{"set_mass", lua_set_mass},
		{"get_center_of_mass", lua_get_center_of_mass},
		{"shape_count", lua_shape_count},
		{"shape_get", lua_shape_get},
		{"shape_set", lua_shape_set},
		{"body_test_move", lua_body_test_move},
		{"body_move_and_collide", lua_body_move_and_collide},
	}
	for f in fns {
		lua.pushcfunction(L, f.fn)
		lua.setfield(L, -2, f.name)
	}
}
