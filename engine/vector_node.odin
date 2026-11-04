package engine

import "core:math"
import rl "vendor:raylib"

// ============================================================================
// VectorShapeNode: draws vector shapes - crisp at any zoom, tessellated once
// per scale bucket and cached (vector_mesh.odin). Phase 14 M0: built-in
// preset shapes (a star, a ring, a badge, a procedural character used by
// the benchmark); vector assets (SVG import, symbols) come in M2 / M3.
// ============================================================================

Vector_Preset :: enum u8 {
	Star,
	Ring,
	Badge,
	Character,
	Gradients,
}

VectorShapeNode :: struct {
	using node:  Node,
	file:        string `gui:"true"`, // an .svg (project-relative); "" = the preset
	group:       string `gui:"true"`, // a symbol: one named group of the file ("a/b": nested); "" = all of it
	frame:       int `gui:"true" min:"-1"`, // part swapping: only this child group of `group` (-1 = all)
	preset:      Vector_Preset `gui:"true"`,
	fillColor:   rl.Color `gui:"true"`,
	strokeColor: rl.Color `gui:"true"`,
	strokeWidth: f32 `gui:"true" min:"0" max:"64"`,
	tint:        rl.Color `gui:"true"`,
	brightness:  f32 `gui:"true" min:"-1" max:"1"`, // -1 black ... 0 ... 1 white (Flash's brightness)
	colorAdd:    rl.Color `gui:"true"`, // added to the colours (Flash's advanced colour offset; alpha ignored)
	trimStart:   f32 `gui:"true" min:"0" max:"1"`, // trim paths: the part of each path drawn (0..1 of its length)
	trimEnd:     f32 `gui:"true" min:"0" max:"1"`,
	trimOffset:  f32 `gui:"true" min:"-1" max:"1"`, // moves the drawn part along (wraps round)
	trimEach:    bool `gui:"true"`, // trim every subpath on its own (a ring's circles together), not one after another
	morphTo:     string `gui:"true"`, // shape tween: another group of the file to morph towards
	morph:       f32 `gui:"true" min:"0" max:"1"`, // 0: this group ... 1: morphTo
	lineScale:   Vector_Line_Scale `gui:"true"`, // outlines scale with the node, or keep their width
	// Filters (vector_filters.odin; Flash's): drawn through a texture made when they change.
	shadowColor:  rl.Color `gui:"true"`, // a drop shadow (alpha 0: none)
	shadowOffset: [2]f32 `gui:"true" min:"-64" max:"64"`,
	shadowBlur:   f32 `gui:"true" min:"0" max:"64"`,
	glowColor:    rl.Color `gui:"true"`, // an outer glow (alpha 0: none)
	glowSize:     f32 `gui:"true" min:"0" max:"64"`,
	glowStrength: f32 `gui:"true" min:"0" max:"8"`,
	outlineColor: rl.Color `gui:"true"`, // an outline round the whole drawing (alpha 0: none)
	outlineWidth: f32 `gui:"true" min:"0" max:"32"`,
	blur:         f32 `gui:"true" min:"0" max:"64"`, // blurs the drawing itself (px on screen)
	saturation:   f32 `gui:"true" min:"0" max:"3"`, // 0 grey, 1 as drawn, 2 vivid
	contrast:     f32 `gui:"true" min:"0" max:"3"`,
	hue:          f32 `gui:"true" min:"-180" max:"180"`, // degrees round the colour wheel
	// Skinning and warp (vector_skin.odin): bend with a Skeleton's bones; squash / stretch.
	skinBones:    string `gui:"true"`, // a Skeleton ancestor's bones it bends with ("a, b"; "*" = all; "" = none)
	skinSmooth:   f32 `gui:"true" min:"0" max:"200"`, // px round each joint where neighbouring bones blend (0: rigid parts)
	warpTopLeft:     [2]f32 `gui:"true" min:"-500" max:"500"`, // corner offsets of a four-corner warp (px)
	warpTopRight:    [2]f32 `gui:"true" min:"-500" max:"500"`,
	warpBottomLeft:  [2]f32 `gui:"true" min:"-500" max:"500"`,
	warpBottomRight: [2]f32 `gui:"true" min:"-500" max:"500"`,
	// Collision from the art (vector_collider.odin): a shape on the body above it (or its own static body).
	collider:         Vector_Collider `gui:"true"`, // None, Solid (convex pieces), Outline (edge loops: terrain)
	colliderDetail:   f32 `gui:"true" min:"0.1" max:"16"`, // how closely it follows the art (its units; bigger: fewer corners)
	colliderFriction: f32 `gui:"true" min:"0" max:"2"`,
	colliderBounce:   f32 `gui:"true" min:"0" max:"1"`,
	colliderDensity:  f32 `gui:"true" min:"0" max:"100"`,
	collision:    Vector_Collision,
	// Carving (vector_cut): its own copy of the shapes, cut.
	carved:       [dynamic]Vector_Shape,
	carving:      bool,
	carveVersion: int,
	carveOffset:  [2]f32,
	skinning:     Vector_Skin,
	filter:       Vector_Filter_State,
	shapes:      [dynamic]Vector_Shape,
	cache:       Vector_Cache,
	built:       struct {preset: Vector_Preset, fill, stroke: rl.Color, width: f32, ok: bool, version: int},
	res:         ^Vector_Resource, // the file's (shared)
	loadedPath:  string,
	fx:          [dynamic]Vector_Shape, // trimmed / morphed shapes (only while those are used)
	fxCache:     Vector_Cache,
	fxKey:       Vector_Fx_Key,
}

Vector_Line_Scale :: enum u8 {
	Scale,    // outlines get thicker / thinner with the node's scale
	Constant, // outlines keep their width (Flash's line scaling "None")
}

Vector_Fx_Key :: struct {
	res:                    ^Vector_Resource,
	version, part, target:  int,
	start, end, offset, t:  f32,
	lineK:                  f32,
	carve:                  int,
	each:                   bool,
	built:                  bool,
}

// The main thread's tessellation scratch (worker threads get their own in M2).
@(private = "file")
vectorTess: Vector_Tess

VectorShapeNode_Create :: proc(scene: ^Scene, name: string = "VectorShape", parent: ^Node = nil) -> ^VectorShapeNode {
	v := CreateNode(scene.manager, VectorShapeNode)
	v.name = clone_name(name, v.allocator)
	v.preset = .Star
	v.fillColor = {255, 196, 64, 255}
	v.strokeColor = {40, 24, 8, 255}
	v.strokeWidth = 4
	v.tint = rl.WHITE
	v.frame = -1
	v.trimEnd = 1
	v.shadowOffset = {6, 6}
	v.shadowBlur = 6
	v.glowSize = 8
	v.glowStrength = 1.5
	v.outlineWidth = 3
	v.saturation = 1
	v.contrast = 1
	v.skinSmooth = 24
	v.colliderDetail = 1
	v.colliderFriction = 0.6
	v.colliderBounce = 0.1
	v.colliderDensity = 1
	v.update = VectorShapeNode_Update
	// (Meshes are rebuilt on zoom: the heap, not the node's arena.)
	v.shapes = make([dynamic]Vector_Shape, Engine_HeapAllocator())
	v.fx = make([dynamic]Vector_Shape, Engine_HeapAllocator())
	v.render = VectorShapeNode_Render
	v.onDestroy = proc(n: ^Node, ctx: ^GameContext) {
		v := cast(^VectorShapeNode)n
		vector_shapes_free(&v.shapes)
		delete(v.shapes)
		Vector_Cache_Destroy(&v.cache)
		vector_shapes_free(&v.fx)
		delete(v.fx)
		Vector_Cache_Destroy(&v.fxCache)
		Vector_FilterRelease(v)
		Vector_Skin_Destroy(&v.skinning)
		Vector_Collision_Destroy(&v.collision)
		VectorShapeNode_ResetCuts(v)
		delete(v.carved)
		ResourceManager_ReleaseVector(v.res)
		v.res = nil
		delete(v.loadedPath, Engine_HeapAllocator())
	}
	scene->addNode(v, parent)
	return v
}

@(private = "file")
clone_name :: proc(name: string, allocator := context.allocator) -> string {
	b := make([]u8, len(name), allocator)
	copy(b, name)
	return string(b)
}

@(private = "file")
vector_shapes_free :: proc(shapes: ^[dynamic]Vector_Shape) {
	for &s in shapes do Vector_Path_Destroy(&s.path)
	clear(shapes)
}

// VectorShapeNode_Build (re)makes the shapes from the properties.
VectorShapeNode_Build :: proc(v: ^VectorShapeNode) {
	context.allocator = Engine_HeapAllocator()
	vector_shapes_free(&v.shapes)
	fill := [4]u8{v.fillColor.r, v.fillColor.g, v.fillColor.b, v.fillColor.a}
	line := [4]u8{v.strokeColor.r, v.strokeColor.g, v.strokeColor.b, v.strokeColor.a}
	Vector_PresetShapes(v.preset, fill, line, v.strokeWidth, &v.shapes)
	v.built = {v.preset, v.fillColor, v.strokeColor, v.strokeWidth, true, v.built.version + 1}
	v.cache.dirty = true
}

// VectorShapeNode_Asset: the node's file (loaded / reloaded when `file`
// changed); nil when it has none or it can't be read.
VectorShapeNode_Asset :: proc(v: ^VectorShapeNode) -> ^Vector_Resource {
	if v.file == v.loadedPath do return v.res
	ResourceManager_ReleaseVector(v.res)
	v.res = nil
	delete(v.loadedPath, Engine_HeapAllocator())
	v.loadedPath = clone_name(v.file, Engine_HeapAllocator())
	if v.file == "" || v.gameContext == nil || v.gameContext.game == nil do return nil
	rm := &v.gameContext.game.resourceManager
	v.res = ResourceManager_LoadVector(rm, Project_ResolveAssetPath(v.gameContext, v.file))
	return v.res
}

// VectorShapeNode_Size: the drawn size (an asset's document box; presets:
// {} - they draw around the position).
VectorShapeNode_Size :: proc(v: ^VectorShapeNode) -> [2]f32 {
	if r := VectorShapeNode_Asset(v); r != nil {
		_, _, size, _ := VectorShapeNode_Part(v, r)
		return size
	}
	return {}
}

// VectorShapeNode_Part: what the node draws of its file - (the part: -1
// the whole document or a group index; the box its origin is in: the
// group's, so swapping frames never moves it). ok = false: a group or frame
// that doesn't exist (nothing drawn).
VectorShapeNode_Part :: proc(v: ^VectorShapeNode, r: ^Vector_Resource) -> (part: int, boxMin, boxSize: [2]f32, ok: bool) {
	g := Vector_ResourceGroup(r, v.group)
	if g == -2 do return -1, {}, {}, false
	boxMin, boxSize = Vector_PartBox(r, g)
	part = g
	if v.frame >= 0 {
		kids := Vector_GroupChildren(r, g)
		if v.frame >= len(kids) do return -1, boxMin, boxSize, false
		part = kids[v.frame]
	}
	return part, boxMin, boxSize, true
}

// VectorShapeNode_Frames: the names of the frames `frame` picks from (the
// group's child groups).
VectorShapeNode_Frames :: proc(v: ^VectorShapeNode, allocator := context.temp_allocator) -> []string {
	r := VectorShapeNode_Asset(v)
	if r == nil do return nil
	g := Vector_ResourceGroup(r, v.group)
	if g == -2 do return nil
	out := make([dynamic]string, allocator)
	for k in Vector_GroupChildren(r, g) do append(&out, r.doc.groups[k].name)
	return out[:]
}

// VectorShapeNode_Swap shows the frame of that name (part swapping);
// false when the group has no such frame.
VectorShapeNode_Swap :: proc(v: ^VectorShapeNode, name: string) -> bool {
	for f, i in VectorShapeNode_Frames(v) do if f == name {
		v.frame = i
		return true
	}
	return false
}

// vector_color_effect: the tint (multiply) and offset (add, 0..1) after
// brightness: Flash's colour effects.
vector_color_effect :: proc(v: ^VectorShapeNode) -> (mul: rl.Color, add: [4]f32) {
	mul = v.tint
	add = {f32(v.colorAdd.r) / 255, f32(v.colorAdd.g) / 255, f32(v.colorAdd.b) / 255, 0}
	b := clamp(v.brightness, -1, 1)
	if b > 0 {
		k := 1 - b
		mul = {u8(f32(mul.r) * k), u8(f32(mul.g) * k), u8(f32(mul.b) * k), mul.a}
		add += {b, b, b, 0}
	} else if b < 0 {
		k := 1 + b
		mul = {u8(f32(mul.r) * k), u8(f32(mul.g) * k), u8(f32(mul.b) * k), mul.a}
	}
	return
}

// VectorShapeNode_FxActive: whether trim paths or a shape tween change
// what it draws (then it tessellates its own copy when they change).
VectorShapeNode_FxActive :: proc(v: ^VectorShapeNode) -> bool {
	// (Skinned: its own mesh, which carries its weights.)
	return v.trimStart > 0 || v.trimEnd < 1 || (v.morph > 0 && v.morphTo != "") || v.lineScale == .Constant || v.carving || VectorShapeNode_SkinTarget(v) != nil
}

// VectorShapeNode_SkinTarget: the Skeleton it bends with - the nearest
// Skeleton ancestor, when skinBones names bones (nil: not skinned).
VectorShapeNode_SkinTarget :: proc(v: ^VectorShapeNode) -> ^SkeletonNode {
	if v.skinBones == "" do return nil
	return VectorShapeNode_Skeleton(v)
}

// VectorShapeNode_Skeleton: its nearest Skeleton ancestor (nil: none).
VectorShapeNode_Skeleton :: proc(v: ^VectorShapeNode) -> ^SkeletonNode {
	for p := v.parent; p != nil; p = p.parent {
		if p.typeId == SkeletonNode do return cast(^SkeletonNode)p
	}
	return nil
}

// VectorShapeNode_Warped: whether a warp corner moved.
VectorShapeNode_Warped :: proc(v: ^VectorShapeNode) -> bool {
	return v.warpTopLeft != {} || v.warpTopRight != {} || v.warpBottomLeft != {} || v.warpBottomRight != {}
}

// VectorShapeNode_Deformed: whether it's drawn bent (skinned or warped).
VectorShapeNode_Deformed :: proc(v: ^VectorShapeNode) -> bool {
	return VectorShapeNode_Warped(v) || VectorShapeNode_SkinTarget(v) != nil
}

// VectorShapeNode_Deform: how its mesh (cache, drawn with offset) is bent
// now - the warp over its box, the skin from its Skeleton's pose (bound /
// re-bound when needed); ok = false: drawn as it is.
VectorShapeNode_Deform :: proc(v: ^VectorShapeNode, cache: ^Vector_Cache, offset: [2]f32) -> (d: Vector_Deform, ok: bool) {
	if VectorShapeNode_Warped(v) {
		vector_node_warp(v, &cache.mesh, &d)
		ok = d.box[2] > 0 && d.box[3] > 0
	}
	sn := VectorShapeNode_SkinTarget(v)
	if sn == nil || sn.data == nil || len(sn.pose.bones) != len(sn.data.bones) || len(cache.mesh.verts) == 0 do return d, ok
	// Mesh space -> the skeleton's space: the local transforms up to it.
	bind := Vector_AffineTRS(offset, 0, {1, 1})
	for n: ^Node = v; n != nil && n != sn; n = n.parent {
		bind = Vector_AffineMul(Vector_AffineTRS(n.position, n.rotation, n.scale), bind)
	}
	if Vector_SkinBind(&v.skinning, sn.data, cache, v.skinBones, v.skinSmooth, bind, VectorShapeNode_Warped(v)) {


		Vector_Cache_SetSkin(cache, v.skinning.ids[:], v.skinning.weights[:])
	}
	if len(v.skinning.bones) == 0 do return d, ok
	d.bones = Vector_SkinPose(&v.skinning, &sn.pose)

	return d, true
}

// vector_fx_build remakes the trimmed / morphed shapes when anything they
// depend on changed; false when there's nothing to draw.
@(private = "file")
vector_fx_build :: proc(v: ^VectorShapeNode, r: ^Vector_Resource, part: int) {
	base := v.shapes[:]
	target := -2
	key := Vector_Fx_Key{res = r, version = v.built.version, part = part, target = -2, start = v.trimStart, end = v.trimEnd, offset = v.trimOffset, each = v.trimEach, built = true, lineK = 1}
	if v.lineScale == .Constant {
		// (Quantised: re-tessellated when the scale changes by a percent.)
		sc := max(abs(v.globalScale.x), abs(v.globalScale.y), 1e-3)
		key.lineK = 1 / (math.round(sc * 100) / 100 if sc >= 0.01 else sc)
	}
	key.carve = v.carveVersion
	if r != nil {
		base = Vector_PartShapes(r, part)
		key.version = r.version
		if v.morph > 0 && v.morphTo != "" do target = Vector_ResourceGroup(r, v.morphTo)
		if target != -2 {
			key.target = target
			key.t = clamp(v.morph, 0, 1)
		}
	}
	if v.carving do base = v.carved[:] // (cut: its own copy)
	if key == v.fxKey do return
	v.fxKey = key
	context.allocator = Engine_HeapAllocator()
	vector_shapes_free(&v.fx)
	src := base
	if target != -2 {
		morphed := make([dynamic]Vector_Shape, context.temp_allocator)
		{
			context.allocator = context.temp_allocator
			Vector_ShapesMorph(base, Vector_PartShapes(r, target), key.t, &morphed)
		}
		src = morphed[:]
	}
	for &sh in src {
		out := sh
		Vector_Path_Init(&out.path)
		Vector_PathTrim(&sh.path, v.trimStart, v.trimEnd, v.trimOffset, &out.path, v.trimEach)
		out.style.strokeWidth *= key.lineK
		append(&v.fx, out)
	}
	v.fxCache.dirty = true
}

// VectorShapeNode_FxShapes: the trimmed / morphed shapes it draws (built
// when out of date).
VectorShapeNode_FxShapes :: proc(v: ^VectorShapeNode) -> []Vector_Shape {
	if r := VectorShapeNode_Asset(v); r != nil {
		part, _, _, ok := VectorShapeNode_Part(v, r)
		if !ok do return nil
		vector_fx_build(v, r, part)
	} else {
		if !v.built.ok do VectorShapeNode_Build(v)
		vector_fx_build(v, nil, -1)
	}
	return v.fx[:]
}

// VectorShapeNode_Mesh: the mesh it draws at a screen-pixel size (made /
// updated as needed) and the offset its origin needs; ok = false: nothing.
VectorShapeNode_Mesh :: proc(v: ^VectorShapeNode, pixel: f32) -> (cache: ^Vector_Cache, offset: [2]f32, ok: bool) {
	context.allocator = Engine_HeapAllocator()
	if r := VectorShapeNode_Asset(v); r != nil {
		part, boxMin, boxSize, found := VectorShapeNode_Part(v, r)
		if !found do return nil, {}, false
		if VectorShapeNode_FxActive(v) {
			vector_fx_build(v, r, part)
			Vector_Cache_Ensure(&v.fxCache, &vectorTess, v.fx[:], pixel)
			cache = &v.fxCache
		} else {
			// (A new zoom: drawn from the nearest mesh while a worker makes the new one.)
			cache = Vector_ResourceMesh(r, &vectorTess, pixel, background = true, part = part)
		}
		// The origin (a fraction of the part's box) sits at the position.
		return cache, -boxMin - Node_OriginPx(v, boxSize), true
	}
	if !v.built.ok || v.built.preset != v.preset || v.built.fill != v.fillColor || v.built.stroke != v.strokeColor || v.built.width != v.strokeWidth {
		VectorShapeNode_Build(v)
	}
	if VectorShapeNode_FxActive(v) {
		vector_fx_build(v, nil, -1)
		Vector_Cache_Ensure(&v.fxCache, &vectorTess, v.fx[:], pixel)
		return &v.fxCache, {}, true
	}
	Vector_Cache_Ensure(&v.cache, &vectorTess, v.shapes[:], pixel)
	return &v.cache, {}, true
}

VectorShapeNode_Render :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	v := cast(^VectorShapeNode)node
	if !rl.IsWindowReady() do return
	// The collider over the art, with the physics debug view.
	defer if v.collider != .None && ctx != nil && ctx.game != nil && ctx.game.physicsWorld.drawPhysicsDebug do VectorShapeNode_DrawCollider(v)
	// Filters: the texture the prepare pass made (vector_filters.odin).
	if Vector_FiltersActive(v) && Vector_FilterDraw(v) do return
	cache, offset, ok := VectorShapeNode_Mesh(v, Vector_ScreenPixel(v.globalScale))
	if !ok do return
	mul, add := vector_color_effect(v)
	// (Saturation / contrast / hue in the mesh's shader: bent art has no
	// filter texture - #389 - and a texture not made yet draws this way too.)
	adjust := [3]f32{v.saturation, v.contrast, v.hue}
	if VectorShapeNode_Deformed(v) {
		if d, bent := VectorShapeNode_Deform(v, cache, offset); bent {
			Vector_Cache_Draw(cache, v.globalPosition, v.globalRotation, v.globalScale, mul, offset, add, &d, adjust)
			return
		}
	}
	Vector_Cache_Draw(cache, v.globalPosition, v.globalRotation, v.globalScale, mul, offset, add, adjust = adjust)
}

// vector_node_warp: the warp's corners and box (mesh space) - an asset
// part's box (stable across frames and swaps), else the mesh's.
@(private = "file")
vector_node_warp :: proc(v: ^VectorShapeNode, mesh: ^Vector_Mesh, d: ^Vector_Deform) {
	box := mesh.bounds
	if r := VectorShapeNode_Asset(v); r != nil {
		if _, bmin, bsize, found := VectorShapeNode_Part(v, r); found do box = {bmin.x, bmin.y, bmin.x + bsize.x, bmin.y + bsize.y}
	}
	d.box = {box[0], box[1], box[2] - box[0], box[3] - box[1]}
	d.warp = {v.warpTopLeft, v.warpTopRight, v.warpBottomLeft, v.warpBottomRight}
}

// vector_deformed_bounds: a box (mesh space) through a deform - its
// corners widened by the warp, then through every bone (generous).
@(private = "file")
vector_deformed_bounds :: proc(d: ^Vector_Deform, b: [4]f32) -> [4]f32 {
	pad: f32 = 0
	for w in d.warp do pad = max(pad, abs(w.x), abs(w.y))
	b := [4]f32{b[0] - pad, b[1] - pad, b[2] + pad, b[3] + pad}
	if len(d.bones) == 0 do return b
	out := [4]f32{max(f32), max(f32), -max(f32), -max(f32)}
	for m in d.bones {
		for c in ([4][2]f32{{b[0], b[1]}, {b[2], b[1]}, {b[0], b[3]}, {b[2], b[3]}}) {
			p := Vector_AffineApply(m, c)
			out = {min(out[0], p.x), min(out[1], p.y), max(out[2], p.x), max(out[3], p.y)}
		}
	}
	return out
}

// VectorShapeNode_LocalBounds: what the node draws in its own space (before
// position / rotation / scale), ok = false when it hasn't drawn yet.
VectorShapeNode_LocalBounds :: proc(v: ^VectorShapeNode) -> (b: [4]f32, ok: bool) {
	if r := VectorShapeNode_Asset(v); r != nil {
		part, boxMin, boxSize, ok := VectorShapeNode_Part(v, r)
		if !ok do return {}, false
		off := -boxMin - Node_OriginPx(v, boxSize)
		d := r.doc.drawn if part < 0 else Vector_ShapesBounds(Vector_PartShapes(r, part))
		if VectorShapeNode_FxActive(v) && len(v.fx) > 0 do d = Vector_ShapesBounds(v.fx[:])
		if d == {} do return {}, false
		if VectorShapeNode_Deformed(v) do d = vector_node_bent_bounds(v, d)
		return {d[0] + off.x, d[1] + off.y, d[2] + off.x, d[3] + off.y}, true
	}
	c := &v.fxCache if VectorShapeNode_FxActive(v) else &v.cache
	if len(c.mesh.verts) == 0 do return {}, false
	if VectorShapeNode_Deformed(v) do return vector_node_bent_bounds(v, c.mesh.bounds), true
	return c.mesh.bounds, true
}

// vector_node_bent_bounds: drawn bounds (mesh space) under the warp and
// the skin's last pose.
@(private = "file")
vector_node_bent_bounds :: proc(v: ^VectorShapeNode, b: [4]f32) -> [4]f32 {
	d: Vector_Deform
	if VectorShapeNode_Warped(v) do d.warp = {v.warpTopLeft, v.warpTopRight, v.warpBottomLeft, v.warpBottomRight}
	if VectorShapeNode_SkinTarget(v) != nil && v.skinning.valid do d.bones = v.skinning.mats[:]
	return vector_deformed_bounds(&d, b)
}

// VectorShapeNode_HitTest: whether a world point is on the drawn shape
// (its triangles, not its box: picking in the editor).
VectorShapeNode_HitTest :: proc(v: ^VectorShapeNode, world: [2]f32) -> bool {
	// The point in the node's (mesh's) space.
	d := world - v.globalPosition
	r := -v.globalRotation * math.RAD_PER_DEG
	c, s := math.cos(r), math.sin(r)
	q := [2]f32{d.x * c - d.y * s, d.x * s + d.y * c}
	if abs(v.globalScale.x) < 1e-6 || abs(v.globalScale.y) < 1e-6 do return false
	q /= v.globalScale
	mesh: ^Vector_Mesh
	if res := VectorShapeNode_Asset(v); res != nil {
		part, boxMin, boxSize, ok := VectorShapeNode_Part(v, res)
		if !ok do return false
		q += boxMin + Node_OriginPx(v, boxSize)
		if VectorShapeNode_FxActive(v) do mesh = &v.fxCache.mesh
		else do for &rc in res.caches do if rc.part == part && len(rc.cache.mesh.idx) > 0 {mesh = &rc.cache.mesh; break}
	} else {
		mesh = &v.cache.mesh if !VectorShapeNode_FxActive(v) else &v.fxCache.mesh
	}
	if mesh == nil || len(mesh.idx) == 0 do return false
	// Bent art: the triangles as drawn (the warp, the skin's last pose).
	bent: Vector_Deform
	deformed := VectorShapeNode_Deformed(v)
	skinned := false
	if deformed {
		if VectorShapeNode_Warped(v) do vector_node_warp(v, mesh, &bent)
		if VectorShapeNode_SkinTarget(v) != nil && v.skinning.valid && len(v.skinning.ids) == len(mesh.verts) {
			bent.bones = v.skinning.mats[:]
			skinned = true
		}
	}
	vert :: proc(m: ^Vector_Mesh, i: u32, d: ^Vector_Deform, deformed, skinned: bool, s: ^Vector_Skin) -> [2]f32 {
		if !deformed do return m.verts[i]
		return Vector_DeformPoint(d, m.verts[i], s.ids[i] if skinned else {}, s.weights[i] if skinned else {})
	}
	for i := 0; i < len(mesh.idx); i += 3 {
		a := vert(mesh, mesh.idx[i], &bent, deformed, skinned, &v.skinning)
		b := vert(mesh, mesh.idx[i + 1], &bent, deformed, skinned, &v.skinning)
		cc := vert(mesh, mesh.idx[i + 2], &bent, deformed, skinned, &v.skinning)
		d1 := (q.x - b.x) * (a.y - b.y) - (a.x - b.x) * (q.y - b.y)
		d2 := (q.x - cc.x) * (b.y - cc.y) - (b.x - cc.x) * (q.y - cc.y)
		d3 := (q.x - a.x) * (cc.y - a.y) - (cc.x - a.x) * (q.y - a.y)
		if !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0)) do return true
	}
	return false
}

// Vector_ShutdownScratch frees the main thread's tessellation buffers
// (engine shutdown; leak checks).
Vector_ShutdownScratch :: proc() {
	Vector_Tess_Destroy(&vectorTess)
}

// --- presets ------------------------------------------------------------------------

// Vector_PresetShapes appends a preset's shapes (centred on 0, 0; about
// 200 px across). Character is deliberately busy (hundreds of curves): the
// benchmark's stand-in for a detailed Flash-style character.
Vector_PresetShapes :: proc(preset: Vector_Preset, fill, line: [4]u8, width: f32, out: ^[dynamic]Vector_Shape) {
	// (The returned path is only valid until the next shape is added.)
	shape :: proc(out: ^[dynamic]Vector_Shape, fill: [4]u8, line: [4]u8, width: f32, join := Vector_Join.Round) -> ^Vector_Path {
		s := Vector_Shape{style = VECTOR_STYLE_DEFAULT}
		Vector_Path_Init(&s.path)
		s.style.fillColor = fill
		s.style.fill = fill.a > 0
		s.style.strokeColor = line
		s.style.strokeWidth = width
		s.style.stroke = width > 0 && line.a > 0
		s.style.join = join
		s.style.cap = .Round
		append(out, s)
		return &out[len(out) - 1].path
	}
	switch preset {
	case .Star:
		p := shape(out, fill, line, width, .Miter)
		for i in 0 ..< 10 {
			a := f32(i) * math.PI / 5 - math.PI / 2
			r: f32 = 100 if i % 2 == 0 else 42
			pt := [2]f32{math.cos(a) * r, math.sin(a) * r}
			if i == 0 do Vector_MoveTo(p, pt)
			else do Vector_LineTo(p, pt)
		}
		Vector_Close(p)
	case .Ring:
		// A hole: the inner circle drawn the other way.
		p := shape(out, fill, line, width)
		Vector_Ellipse(p, {0, 0}, {100, 100})
		ring_inner(p, 55)
	case .Badge:
		p := shape(out, fill, line, width)
		Vector_MoveTo(p, {-90, -70})
		Vector_CubicTo(p, {-30, -110}, {30, -110}, {90, -70})
		Vector_LineTo(p, {80, 30})
		Vector_CubicTo(p, {60, 80}, {20, 100}, {0, 110})
		Vector_CubicTo(p, {-20, 100}, {-60, 80}, {-80, 30})
		Vector_Close(p)
		dot := shape(out, line, {}, 0)
		Vector_Ellipse(dot, {0, -10}, {28, 28})
	case .Character:
		character(out, fill, line, width)
	case .Gradients:
		gradients(out, fill, line, width)
	}
}

@(private = "file")
ring_inner :: proc(p: ^Vector_Path, r: f32) {
	K :: 0.5522847498
	k := r * K
	Vector_MoveTo(p, {r, 0})
	Vector_CubicTo(p, {r, -k}, {k, -r}, {0, -r})
	Vector_CubicTo(p, {-k, -r}, {-r, -k}, {-r, 0})
	Vector_CubicTo(p, {-r, k}, {-k, r}, {0, r})
	Vector_CubicTo(p, {k, r}, {r, k}, {r, 0})
	Vector_Close(p)
}

// character: a cartoon figure - body, limbs as thick strokes, a head with
// eyes, mouth and a mane of curved hair strands, and spots - ~300 curves.
@(private = "file")
character :: proc(out: ^[dynamic]Vector_Shape, fill, line: [4]u8, width: f32) {
	shape :: proc(out: ^[dynamic]Vector_Shape, fill, line: [4]u8, width: f32) -> ^Vector_Path {
		s := Vector_Shape{style = VECTOR_STYLE_DEFAULT}
		Vector_Path_Init(&s.path)
		s.style.fillColor = fill
		s.style.fill = fill.a > 0
		s.style.strokeColor = line
		s.style.strokeWidth = width
		s.style.stroke = width > 0 && line.a > 0
		s.style.join = .Round
		s.style.cap = .Round
		append(out, s)
		return &out[len(out) - 1].path
	}
	skin := [4]u8{255, 214, 170, 255}
	shirt := fill
	dark := line
	w := max(width, 2)
	// Legs and arms: open strokes.
	for side in ([]f32{-1, 1}) {
		leg := shape(out, {}, dark, 14)
		Vector_MoveTo(leg, {side * 18, 40})
		Vector_CubicTo(leg, {side * 24, 70}, {side * 14, 95}, {side * 26, 120})
		arm := shape(out, {}, skin, 10)
		Vector_MoveTo(arm, {side * 34, -20})
		Vector_CubicTo(arm, {side * 60, 0}, {side * 66, 30}, {side * 54, 55})
	}
	// Body.
	body := shape(out, shirt, dark, w)
	Vector_MoveTo(body, {-36, -30})
	Vector_CubicTo(body, {-50, 10}, {-44, 45}, {-30, 55})
	Vector_CubicTo(body, {-10, 62}, {10, 62}, {30, 55})
	Vector_CubicTo(body, {44, 45}, {50, 10}, {36, -30})
	Vector_CubicTo(body, {20, -40}, {-20, -40}, {-36, -30})
	Vector_Close(body)
	// Buttons.
	for i in 0 ..< 3 do Vector_Ellipse(shape(out, dark, {}, 0), {0, -10 + f32(i) * 18}, {4, 4})
	// Head, ears.
	for side in ([]f32{-1, 1}) do Vector_Ellipse(shape(out, skin, dark, w * 0.6), {side * 44, -78}, {9, 12})
	Vector_Ellipse(shape(out, skin, dark, w), {0, -80}, {42, 46})
	// Eyes with pupils and highlights.
	for side in ([]f32{-1, 1}) {
		Vector_Ellipse(shape(out, {255, 255, 255, 255}, dark, w * 0.5), {side * 15, -86}, {10, 12})
		Vector_Ellipse(shape(out, dark, {}, 0), {side * 14, -84}, {5, 6})
		Vector_Ellipse(shape(out, {255, 255, 255, 255}, {}, 0), {side * 12, -87}, {1.6, 1.6})
	}
	// Mouth.
	mouth := shape(out, {}, dark, w * 0.6)
	Vector_MoveTo(mouth, {-14, -58})
	Vector_CubicTo(mouth, {-6, -50}, {6, -50}, {14, -58})
	// Hair: 60 curved strands (filled leaf shapes).
	hair := [4]u8{90, 50, 30, 255}
	for i in 0 ..< 60 {
		a := math.PI + f32(i) / 59 * math.PI
		base := [2]f32{math.cos(a) * 40, -84 + math.sin(a) * 44}
		tip := base + [2]f32{math.cos(a) * 26, math.sin(a) * 26 - 6}
		nrm := [2]f32{-math.sin(a), math.cos(a)} * 5
		h := shape(out, hair, {}, 0)
		Vector_MoveTo(h, base - nrm)
		Vector_QuadTo(h, (base + tip) * 0.5 - nrm * 2, tip)
		Vector_QuadTo(h, (base + tip) * 0.5 + nrm * 2, base + nrm)
		Vector_Close(h)
	}
	// Spots on the shirt: 120 small blobs.
	for i in 0 ..< 120 {
		fi := f32(i)
		x := math.sin(fi * 12.9898) * 30
		y := 5 + math.cos(fi * 78.233) * 38
		Vector_Ellipse(shape(out, {255, 255, 255, 90}, {}, 0), {x, y}, {2.5 + math.abs(math.sin(fi)) * 2, 2.5})
	}
}

// gradients: paints and dashes - a radial orb, a linear sky, reflected
// stripes, a dashed ring.
@(private = "file")
gradients :: proc(out: ^[dynamic]Vector_Shape, fill, line: [4]u8, width: f32) {
	add :: proc(out: ^[dynamic]Vector_Shape) -> ^Vector_Shape {
		s := Vector_Shape{style = VECTOR_STYLE_DEFAULT}
		Vector_Path_Init(&s.path)
		append(out, s)
		return &out[len(out) - 1]
	}
	// A sky: a linear gradient top to bottom.
	sky := add(out)
	Vector_Rect(&sky.path, {-100, -100}, {100, 0})
	sky.style.fillPaint = Vector_LinearGradient({0, -100}, {0, 0}, {{0, {30, 60, 160, 255}}, {0.6, {240, 120, 80, 255}}, {1, {255, 210, 120, 255}}})
	// Stripes: a short linear gradient reflected across the band.
	band := add(out)
	Vector_Rect(&band.path, {-100, 0}, {100, 30})
	band.style.fillPaint = Vector_LinearGradient({-100, 0}, {-80, 0}, {{0, fill}, {1, line}}, .Reflect)
	// An orb: a radial gradient with an offset highlight (the gradient moved by its transform).
	orb := add(out)
	Vector_Ellipse(&orb.path, {0, -40}, {45, 45})
	orb.style.fillPaint = Vector_RadialGradient({0, 0}, 60, {{0, {255, 255, 255, 255}}, {0.35, {120, 200, 255, 255}}, {1, {10, 40, 120, 255}}})
	orb.style.fillPaint.transform = {1, 0, 0, 1, -15, -55}
	orb.style.stroke = true
	orb.style.strokeWidth = max(width, 1)
	orb.style.strokeColor = {10, 30, 80, 255}
	// A dashed ring (round caps) and a dotted line.
	ring := add(out)
	Vector_Ellipse(&ring.path, {0, 70}, {60, 25})
	ring.style.fill = false
	ring.style.stroke = true
	ring.style.strokeWidth = 6
	ring.style.strokeColor = line
	ring.style.cap = .Round
	ring.style.dash = {count = 2, values = {18, 10, 0, 0, 0, 0, 0, 0}}
	dots := add(out)
	Vector_MoveTo(&dots.path, {-90, 110}); Vector_LineTo(&dots.path, {90, 110})
	dots.style.fill = false
	dots.style.stroke = true
	dots.style.strokeWidth = 4
	dots.style.strokeColor = fill
	dots.style.dash = {count = 2, values = {8, 8, 0, 0, 0, 0, 0, 0}, offset = 4}
	// A half-transparent overlay (shape opacity).
	glass := add(out)
	Vector_Rect(&glass.path, {20, -90}, {90, -20})
	glass.style.fillColor = {255, 255, 255, 255}
	glass.style.opacity = 0.35
}
