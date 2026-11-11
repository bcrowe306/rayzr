package engine

import "core:mem"

import "core:hash"

import b2 "vendor:box2d"
import rl "vendor:raylib"

PhysicsShapeType :: enum {
	Circle,
	Capsule,
	Box,
	RoundedBox,
	Polygon,
	Segment,
	Chain,
}

PhysicsShape :: struct {
	shapeId: b2.ShapeId,
	chainId: b2.ChainId,
	type: PhysicsShapeType `gui:"true"`,
	offset: [2]f32 `gui:"true" min:"-500" max:"500"`,
	rotation: f32 `gui:"true" min:"0" max:"360"`,

	// Dimensions
	radius: f32 `gui:"true" min:"1" max:"500"`,
	size: [2]f32 `gui:"true" min:"1" max:"1000"`, // Width and Height (Box / Capsule)
	cornerRadius: f32 `gui:"true" min:"0" max:"100"`,
	point1: [2]f32 `gui:"true" min:"-500" max:"500"`,
	point2: [2]f32 `gui:"true" min:"-500" max:"500"`,
	vertices: [b2.MAX_POLYGON_VERTICES][2]f32,
	vertexCount: int `gui:"true" min:"3" max:"8"`,
	chainPoints: [dynamic][2]f32,
	isLoop: bool `gui:"true"`,

	// Material & Mass
	density: f32 `gui:"true" min:"0" max:"100"`,
	friction: f32 `gui:"true" min:"0" max:"2"`,
	restitution: f32 `gui:"true" min:"0" max:"1"`,
	rollingResistance: f32 `gui:"true" min:"0" max:"1"`,
	tangentSpeed: f32 `gui:"true" min:"-500" max:"500"`,

	// Events & Sensor
	isSensor: bool `gui:"true"`,
	enableSensorEvents: bool `gui:"true"`,
	enableContactEvents: bool `gui:"true"`,
	enableHitEvents: bool `gui:"true"`,
	enablePreSolveEvents: bool `gui:"true"`,

	// Collision Filtering (Layers)
	categoryLayers: CollisionLayerSet `gui:"true"`,
	maskLayers: CollisionLayerSet `gui:"true"`,
	groupIndex: int `gui:"true" min:"-100" max:"100"`,

	// Hash of the parameters last pushed to Box2D (0 = never): the sync
	// skips unchanged shapes instead of resetting them every frame.
	syncedHash: u64,
}

// physics_shape_hash: hash of everything PhysicsShape_SyncToBox2D applies.
@(private = "file")
physics_shape_hash :: proc(shape: ^PhysicsShape, scale: [2]f32 = {1, 1}) -> u64 {
	Params :: struct {
		scale: [2]f32,
		vertexCount: int,
		vertices: [b2.MAX_POLYGON_VERTICES][2]f32,
		chainLen: int,
		isLoop: bool,
		type: PhysicsShapeType,
		offset: [2]f32,
		rotation, radius: f32,
		size: [2]f32,
		cornerRadius: f32,
		point1, point2: [2]f32,
		density, friction, restitution, rollingResistance, tangentSpeed: f32,
		isSensor, sensorEv, contactEv, hitEv, preSolveEv: bool,
		category, mask: u64,
		group: int,
	}
	sc := scale
	if sc.x == 0 && sc.y == 0 do sc = {1, 1}
	p := Params{
		sc, shape.vertexCount, shape.vertices, len(shape.chainPoints), shape.isLoop,
		shape.type, shape.offset, shape.rotation, shape.radius, shape.size, shape.cornerRadius,
		shape.point1, shape.point2, shape.density, shape.friction, shape.restitution, shape.rollingResistance, shape.tangentSpeed,
		shape.isSensor, shape.enableSensorEvents, shape.enableContactEvents, shape.enableHitEvents, shape.enablePreSolveEvents,
		CollisionLayerSet_ToBits(shape.categoryLayers), CollisionLayerSet_ToBits(shape.maskLayers), shape.groupIndex,
	}
	h := hash.fnv64a(mem.ptr_to_bytes(&p))
	if len(shape.chainPoints) > 0 do h ~= hash.fnv64a(mem.slice_to_bytes(shape.chainPoints[:]))
	return h if h != 0 else 1
}

PhysicsShape_InitDefault :: proc(shape: ^PhysicsShape, type: PhysicsShapeType = .Box) {
	shape.shapeId = b2.nullShapeId
	shape.chainId = b2.nullChainId
	shape.type = type
	shape.offset = {0, 0}
	shape.rotation = 0
	shape.radius = 20
	shape.size = {40, 40}
	shape.cornerRadius = 4
	shape.point1 = {-25, 0}
	shape.point2 = {25, 0}
	shape.vertexCount = 4
	shape.vertices[0] = {-20, -20}
	shape.vertices[1] = {20, -20}
	shape.vertices[2] = {20, 20}
	shape.vertices[3] = {-20, 20}
	shape.isLoop = false

	shape.density = 1.0
	shape.friction = 0.6
	shape.restitution = 0.2
	shape.rollingResistance = 0.0
	shape.tangentSpeed = 0.0

	shape.isSensor = false
	shape.enableSensorEvents = true
	shape.enableContactEvents = true
	shape.enableHitEvents = false
	shape.enablePreSolveEvents = false

	shape.categoryLayers = DEFAULT_COLLISION_CATEGORIES
	shape.maskLayers = DEFAULT_COLLISION_MASK
	shape.groupIndex = 0
}

PhysicsShape_BuildDef :: proc(shape: ^PhysicsShape, userData: rawptr = nil) -> b2.ShapeDef {
	def := b2.DefaultShapeDef()
	def.userData = userData
	def.density = shape.density
	def.material.friction = shape.friction
	def.material.restitution = shape.restitution
	def.material.rollingResistance = shape.rollingResistance
	def.material.tangentSpeed = shape.tangentSpeed
	def.isSensor = shape.isSensor
	def.enableSensorEvents = shape.enableSensorEvents
	def.enableContactEvents = shape.enableContactEvents
	def.enableHitEvents = true // (always: collision_started's contact speed, physics_queries.odin)
	def.enablePreSolveEvents = shape.enablePreSolveEvents
	def.filter = b2.Filter{
		categoryBits = CollisionLayerSet_ToBits(shape.categoryLayers),
		maskBits     = CollisionLayerSet_ToBits(shape.maskLayers),
		groupIndex   = i32(shape.groupIndex),
	}
	return def
}

// PhysicsShape_Scaled: the shape's geometry with a node's scale applied.
// Shapes are authored in the node's local units; the body gets them scaled
// by the node's world scale. Boxes, segments, polygons and chains scale per
// axis; a circle takes the larger axis; a capsule its radius from x and its
// length from y; a mirrored scale (one negative axis) mirrors the rotation.
// The result's chainPoints live in the temp allocator.
PhysicsShape_Scaled :: proc(shape: ^PhysicsShape, scale: [2]f32) -> PhysicsShape {
	g := shape^
	sc := scale
	if sc.x == 0 && sc.y == 0 do sc = {1, 1}
	ax, ay := abs(sc.x), abs(sc.y)
	g.offset = shape.offset * sc
	g.size = shape.size * [2]f32{ax, ay}
	g.cornerRadius = shape.cornerRadius * min(ax, ay)
	if sc.x * sc.y < 0 do g.rotation = -shape.rotation
	#partial switch shape.type {
	case .Circle:  g.radius = shape.radius * max(ax, ay)
	case .Capsule: g.radius = shape.radius * ax
	case:          g.radius = shape.radius * max(ax, ay)
	}
	g.point1 = shape.point1 * sc
	g.point2 = shape.point2 * sc
	for i in 0 ..< clamp(shape.vertexCount, 0, int(b2.MAX_POLYGON_VERTICES)) do g.vertices[i] = shape.vertices[i] * sc
	g.chainPoints = nil
	if len(shape.chainPoints) > 0 {
		g.chainPoints = make([dynamic][2]f32, len(shape.chainPoints), context.temp_allocator)
		for p, i in shape.chainPoints do g.chainPoints[i] = p * sc
	}
	return g
}

// polygon_of: the Box2D polygon of a (scaled) Box / RoundedBox / Polygon.
@(private = "file")
polygon_of :: proc(g: ^PhysicsShape) -> b2.Polygon {
	rot := DegreesToRot(g.rotation)
	hw := max(g.size[0] * 0.5, 0.5)
	hh := max(g.size[1] * 0.5, 0.5)
	#partial switch g.type {
	case .RoundedBox:
		return b2.MakeOffsetRoundedBox(hw, hh, g.offset, rot, max(g.cornerRadius, 0.0))
	case .Polygon:
		count := clamp(g.vertexCount, 3, int(b2.MAX_POLYGON_VERTICES))
		hull := b2.ComputeHull(g.vertices[:count])
		if b2.ValidateHull(hull) do return b2.MakeOffsetPolygon(hull, g.offset, rot)
	}
	return b2.MakeOffsetBox(hw, hh, g.offset, rot)
}

@(private = "file")
capsule_of :: proc(g: ^PhysicsShape) -> b2.Capsule {
	halfLen := max(g.size[1] * 0.5, 0.5)
	dir := b2.RotateVector(DegreesToRot(g.rotation), b2.Vec2{0, halfLen})
	return b2.Capsule{center1 = g.offset - dir, center2 = g.offset + dir, radius = max(g.radius, 0.5)}
}

@(private = "file")
segment_of :: proc(g: ^PhysicsShape) -> b2.Segment {
	rot := DegreesToRot(g.rotation)
	return b2.Segment{point1 = g.offset + b2.RotateVector(rot, g.point1), point2 = g.offset + b2.RotateVector(rot, g.point2)}
}

PhysicsShape_AttachToBody :: proc(shape: ^PhysicsShape, bodyId: b2.BodyId, userData: rawptr = nil, scale: [2]f32 = {1, 1}) {
	if !b2.Body_IsValid(bodyId) do return

	// Keep the authored chain points (PhysicsShape_Destroy frees them).
	points := shape.chainPoints
	shape.chainPoints = nil
	PhysicsShape_Destroy(shape)
	shape.chainPoints = points

	def := PhysicsShape_BuildDef(shape, userData)
	shape.syncedHash = physics_shape_hash(shape, scale) // built from these values
	g := PhysicsShape_Scaled(shape, scale)

	switch shape.type {
	case .Circle:
		shape.shapeId = b2.CreateCircleShape(bodyId, def, b2.Circle{center = g.offset, radius = max(g.radius, 0.5)})
	case .Capsule:
		shape.shapeId = b2.CreateCapsuleShape(bodyId, def, capsule_of(&g))
	case .Box, .RoundedBox, .Polygon:
		shape.shapeId = b2.CreatePolygonShape(bodyId, def, polygon_of(&g))
	case .Segment:
		shape.shapeId = b2.CreateSegmentShape(bodyId, def, segment_of(&g))
	case .Chain:
		if len(g.chainPoints) >= 4 {
			// Chain points are in shape space: apply the offset and rotation.
			rot := DegreesToRot(g.rotation)
			for &p in g.chainPoints do p = g.offset + b2.RotateVector(rot, p)
			cdef := b2.DefaultChainDef()
			cdef.userData = userData
			cdef.points = raw_data(g.chainPoints)
			cdef.count = i32(len(g.chainPoints))
			cdef.isLoop = shape.isLoop
			cdef.enableSensorEvents = shape.enableSensorEvents
			cdef.filter = def.filter
			shape.chainId = b2.CreateChain(bodyId, cdef)
		} else {
			// Fallback to segment if fewer than 4 chain points
			shape.shapeId = b2.CreateSegmentShape(bodyId, def, segment_of(&g))
		}
	}
}

// PhysicsShape_SyncToBox2D pushes changed parameters (and the node's
// current scale) to Box2D; unchanged shapes are skipped.
PhysicsShape_SyncToBox2D :: proc(shape: ^PhysicsShape, bodyId: b2.BodyId, userData: rawptr = nil, scale: [2]f32 = {1, 1}) {
	if b2.Shape_IsValid(shape.shapeId) || b2.Chain_IsValid(shape.chainId) {
		h := physics_shape_hash(shape, scale)
		if h == shape.syncedHash do return
		// A different kind of geometry, or a chain: recreate.
		kindOk := true
		if b2.Shape_IsValid(shape.shapeId) {
			#partial switch b2.Shape_GetType(shape.shapeId) {
			case .circleShape:  kindOk = shape.type == .Circle
			case .capsuleShape: kindOk = shape.type == .Capsule
			case .polygonShape: kindOk = shape.type == .Box || shape.type == .RoundedBox || shape.type == .Polygon
			case .segmentShape: kindOk = shape.type == .Segment
			}
			if b2.Shape_IsSensor(shape.shapeId) != shape.isSensor do kindOk = false
		}
		if !kindOk || shape.type == .Chain || b2.Chain_IsValid(shape.chainId) {
			PhysicsShape_AttachToBody(shape, bodyId, userData, scale)
			return
		}
		shape.syncedHash = h
		b2.Shape_SetDensity(shape.shapeId, shape.density, true)
		b2.Shape_SetFriction(shape.shapeId, shape.friction)
		b2.Shape_SetRestitution(shape.shapeId, shape.restitution)
		b2.Shape_SetFilter(shape.shapeId, b2.Filter{
			categoryBits = CollisionLayerSet_ToBits(shape.categoryLayers),
			maskBits     = CollisionLayerSet_ToBits(shape.maskLayers),
			groupIndex   = i32(shape.groupIndex),
		})
		b2.Shape_EnableSensorEvents(shape.shapeId, shape.enableSensorEvents)
		b2.Shape_EnableContactEvents(shape.shapeId, shape.enableContactEvents)
		b2.Shape_EnableHitEvents(shape.shapeId, true)
		b2.Shape_EnablePreSolveEvents(shape.shapeId, shape.enablePreSolveEvents)

		g := PhysicsShape_Scaled(shape, scale)
		#partial switch shape.type {
		case .Circle:
			b2.Shape_SetCircle(shape.shapeId, b2.Circle{center = g.offset, radius = max(g.radius, 0.5)})
		case .Capsule:
			b2.Shape_SetCapsule(shape.shapeId, capsule_of(&g))
		case .Box, .RoundedBox, .Polygon:
			b2.Shape_SetPolygon(shape.shapeId, polygon_of(&g))
		case .Segment:
			b2.Shape_SetSegment(shape.shapeId, segment_of(&g))
		}
		// New geometry (e.g. a scaled node): recompute the body's mass.
		b2.Body_ApplyMassFromShapes(b2.Shape_GetBody(shape.shapeId))
	} else if b2.Body_IsValid(bodyId) {
		PhysicsShape_AttachToBody(shape, bodyId, userData, scale)
	}
}

PhysicsShape_Destroy :: proc(shape: ^PhysicsShape) {
	if b2.Shape_IsValid(shape.shapeId) {
		b2.DestroyShape(shape.shapeId, true)
		shape.shapeId = b2.nullShapeId
	}
	if b2.Chain_IsValid(shape.chainId) {
		b2.DestroyChain(shape.chainId)
		shape.chainId = b2.nullChainId
	}
	if shape.chainPoints != nil {
		delete(shape.chainPoints)
		shape.chainPoints = nil
	}
}

// PhysicsShape_DrawDebug draws a shape of a body at bodyPos / bodyRotDeg,
// scaled like its collider.
PhysicsShape_DrawDebug :: proc(shape: ^PhysicsShape, bodyPos: [2]f32, bodyRotDeg: f32, color: rl.Color, scale: [2]f32 = {1, 1}) {
	if !rl.IsWindowReady() do return
	g := PhysicsShape_Scaled(shape, scale)
	bodyRot := DegreesToRot(bodyRotDeg)
	shapeRot := DegreesToRot(bodyRotDeg + g.rotation)
	worldCenter := bodyPos + b2.RotateVector(bodyRot, g.offset)

	fillColor := rl.Color{color.r, color.g, color.b, 55}

	switch g.type {
	case .Circle:
		rl.DrawCircleV(worldCenter, g.radius, fillColor)
		rl.DrawCircleLinesV(worldCenter, g.radius, color)
		dir := b2.RotateVector(shapeRot, b2.Vec2{g.radius, 0})
		rl.DrawLineV(worldCenter, worldCenter + dir, color)

	case .Capsule:
		halfLen := g.size[1] * 0.5
		dir := b2.RotateVector(shapeRot, b2.Vec2{0, halfLen})
		p1 := worldCenter - dir
		p2 := worldCenter + dir
		rl.DrawCircleV(p1, g.radius, fillColor)
		rl.DrawCircleV(p2, g.radius, fillColor)
		rl.DrawCircleLinesV(p1, g.radius, color)
		rl.DrawCircleLinesV(p2, g.radius, color)
		rl.DrawLineEx(p1, p2, g.radius * 2.0, fillColor)
		perp := b2.RotateVector(shapeRot, b2.Vec2{g.radius, 0})
		rl.DrawLineV(p1 + perp, p2 + perp, color)
		rl.DrawLineV(p1 - perp, p2 - perp, color)

	case .Box, .RoundedBox:
		w := g.size[0]
		h := g.size[1]
		rect := rl.Rectangle{worldCenter.x, worldCenter.y, w, h}
		rl.DrawRectanglePro(rect, {w * 0.5, h * 0.5}, bodyRotDeg + g.rotation, fillColor)
		hw := w * 0.5
		hh := h * 0.5
		c0 := worldCenter + b2.RotateVector(shapeRot, {-hw, -hh})
		c1 := worldCenter + b2.RotateVector(shapeRot, {hw, -hh})
		c2 := worldCenter + b2.RotateVector(shapeRot, {hw, hh})
		c3 := worldCenter + b2.RotateVector(shapeRot, {-hw, hh})
		rl.DrawLineV(c0, c1, color)
		rl.DrawLineV(c1, c2, color)
		rl.DrawLineV(c2, c3, color)
		rl.DrawLineV(c3, c0, color)

	case .Polygon:
		count := clamp(g.vertexCount, 3, int(b2.MAX_POLYGON_VERTICES))
		for i in 0..<count {
			next := (i + 1) % count
			v0 := worldCenter + b2.RotateVector(shapeRot, g.vertices[i])
			v1 := worldCenter + b2.RotateVector(shapeRot, g.vertices[next])
			rl.DrawLineV(v0, v1, color)
		}

	case .Segment:
		p1 := worldCenter + b2.RotateVector(shapeRot, g.point1)
		p2 := worldCenter + b2.RotateVector(shapeRot, g.point2)
		rl.DrawLineEx(p1, p2, 2.0, color)

	case .Chain:
		n := len(g.chainPoints)
		if n >= 2 {
			for i in 0..<(n - 1) {
				p1 := worldCenter + b2.RotateVector(shapeRot, g.chainPoints[i])
				p2 := worldCenter + b2.RotateVector(shapeRot, g.chainPoints[i + 1])
				rl.DrawLineEx(p1, p2, 2.0, color)
			}
			if g.isLoop {
				p1 := worldCenter + b2.RotateVector(shapeRot, g.chainPoints[n - 1])
				p2 := worldCenter + b2.RotateVector(shapeRot, g.chainPoints[0])
				rl.DrawLineEx(p1, p2, 2.0, color)
			}
		}
	}
}

// Helper Constructors
MakeCirclePhysicsShape :: proc(radius: f32, offset: [2]f32 = {0, 0}) -> PhysicsShape {
	s: PhysicsShape
	PhysicsShape_InitDefault(&s, .Circle)
	s.radius = radius
	s.offset = offset
	return s
}

MakeBoxPhysicsShape :: proc(width, height: f32, offset: [2]f32 = {0, 0}, rotation: f32 = 0) -> PhysicsShape {
	s: PhysicsShape
	PhysicsShape_InitDefault(&s, .Box)
	s.size = {width, height}
	s.offset = offset
	s.rotation = rotation
	return s
}

MakeCapsulePhysicsShape :: proc(radius, height: f32, offset: [2]f32 = {0, 0}) -> PhysicsShape {
	s: PhysicsShape
	PhysicsShape_InitDefault(&s, .Capsule)
	s.radius = radius
	s.size = {radius * 2, height}
	s.offset = offset
	return s
}

// MakePolygonPhysicsShape: a convex polygon (up to 8 points, in the body's
// space).
MakePolygonPhysicsShape :: proc(points: [][2]f32) -> PhysicsShape {
	s: PhysicsShape
	PhysicsShape_InitDefault(&s, .Polygon)
	n := min(len(points), int(b2.MAX_POLYGON_VERTICES))
	for i in 0 ..< n do s.vertices[i] = points[i]
	s.vertexCount = n
	return s
}

MakeSegmentPhysicsShape :: proc(p1, p2: [2]f32) -> PhysicsShape {
	s: PhysicsShape
	PhysicsShape_InitDefault(&s, .Segment)
	s.point1 = p1
	s.point2 = p2
	return s
}
