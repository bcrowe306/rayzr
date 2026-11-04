package engine

import "core:os"
import "core:testing"
import lua "lua54"

@(private = "file")
ARM_RIG :: `{
"skeleton": {"spine": "4.2.22"},
"bones": [
	{"name": "root"},
	{"name": "upper", "parent": "root", "length": 100},
	{"name": "lower", "parent": "upper", "x": 100, "length": 100}
],
"slots": [], "skins": [{"name": "default", "attachments": {}}],
"animations": {"bent": {"bones": {"upper": {"rotate": [{"time": 0, "value": 20}]}, "lower": {"rotate": [{"time": 0, "value": -80}]}}}}
}`

@(private = "file")
LIMB_SVG :: `<svg xmlns="http://www.w3.org/2000/svg" width="200" height="40" viewBox="0 0 200 40">
<rect x="2" y="2" width="196" height="36" rx="18" fill="#f4b183" stroke="#5b3a29" stroke-width="3"/></svg>`

@(private = "file")
close2 :: proc(a, b: [2]f32, eps: f32 = 0.05) -> bool {return abs(a.x - b.x) < eps && abs(a.y - b.y) < eps}

// Vector skinning (V.10): affine maths, weights by distance to bones (rigid
// and smooth joints, at most four), the pose's matrices matching the bones,
// re-binding only when something changed; the node under a Skeleton (bind
// through its transform, bounds, filters off), the warp.
@(test)
test_vector_skinning :: proc(t: ^testing.T) {
	m := Vector_AffineTRS({10, 20}, 30, {2, 3})
	inv, ok := Vector_AffineInverse(m)
	testing.expect(t, ok, "invertible")
	p := Vector_AffineApply(Vector_AffineMul(inv, m), {7, -4})
	testing.expectf(t, close2(p, {7, -4}, 1e-3), "inverse round trip (%v)", p)

	d, dok := Skeleton_LoadSpine(ARM_RIG, "", nil, nil)
	testing.expect(t, dok && d != nil, "the rig loads without an atlas")
	if d == nil do return
	defer Skeleton_DataDestroy(d, nil)
	bones := make([dynamic]int, context.temp_allocator)
	Vector_SkinBoneList(d, "lower, nope, upper, lower", &bones)
	testing.expect(t, len(bones) == 2 && bones[0] == 2 && bones[1] == 1, "names in order, unknown and repeated skipped")
	Vector_SkinBoneList(d, "*", &bones)
	testing.expect_value(t, len(bones), 3)

	// A mesh along the bones: mid upper, the joint, near the joint, mid lower.
	c: Vector_Cache
	defer Vector_Cache_Destroy(&c)
	append(&c.mesh.verts, [2]f32{50, 0}, [2]f32{100, 0}, [2]f32{90, 10}, [2]f32{150, 0})
	s: Vector_Skin
	defer Vector_Skin_Destroy(&s)
	testing.expect(t, Vector_SkinBind(&s, d, &c, "upper, lower", 0, VECTOR_AFFINE_IDENTITY), "first bind")
	testing.expect(t, s.weights[0] == {1, 0, 0, 0} && s.ids[0][0] == 0, "mid upper: the upper bone alone")
	testing.expect(t, s.weights[2] == {1, 0, 0, 0} && s.ids[2][0] == 0, "smooth 0: rigid near the joint")
	testing.expect(t, s.weights[3] == {1, 0, 0, 0} && s.ids[3][0] == 1, "mid lower: the lower bone")
	testing.expect(t, !Vector_SkinBind(&s, d, &c, "upper, lower", 0, VECTOR_AFFINE_IDENTITY), "nothing changed: no re-bind")
	testing.expect(t, Vector_SkinBind(&s, d, &c, "upper, lower", 40, VECTOR_AFFINE_IDENTITY), "smoothing changed: re-bind")
	w := s.weights[2]
	testing.expectf(t, w[0] > 0.5 && w[0] < 1 && w[1] > 0 && abs(w[0] + w[1] - 1) < 1e-4, "smooth: both bones near the joint (%v)", w)
	testing.expect(t, s.weights[0] == {1, 0, 0, 0}, "far from the joint: still one bone")

	// Rest pose: no change; bent: vertices follow their bones.
	pose: Skeleton_Pose
	Skeleton_PoseInit(&pose, d)
	defer Skeleton_PoseDestroy(&pose)
	Skeleton_UpdateWorld(&pose, d, {0, 0})
	def := Vector_Deform{bones = Vector_SkinPose(&s, &pose)}
	for v, i in c.mesh.verts {
		q := Vector_DeformPoint(&def, v, s.ids[i], s.weights[i])
		testing.expectf(t, close2(q, v), "setup pose: vertex %d stays (%v)", i, q)
	}
	Skeleton_Apply(&pose, d, Skeleton_AnimationIndex(d, "bent"), 0)
	Skeleton_UpdateWorld(&pose, d, {0, 0})
	def.bones = Vector_SkinPose(&s, &pose)
	q := Vector_DeformPoint(&def, c.mesh.verts[3], s.ids[3], s.weights[3])
	want := Skeleton_LocalToWorld(pose.bones[2], {50, 0})
	testing.expectf(t, close2(q, want), "mid lower follows the lower bone (%v vs %v)", q, want)
	q = Vector_DeformPoint(&def, c.mesh.verts[0], s.ids[0], s.weights[0])
	testing.expectf(t, close2(q, Skeleton_LocalToWorld(pose.bones[1], {50, 0})), "mid upper follows the upper bone (%v)", q)

	// Through a bind transform (the mesh 100 px left of the skeleton's space).
	clear(&c.mesh.verts)
	append(&c.mesh.verts, [2]f32{50, 0})
	c.stats.tessellations += 1
	bind := Vector_AffineTRS({100, 0}, 0, {1, 1})
	testing.expect(t, Vector_SkinBind(&s, d, &c, "upper, lower", 0, bind), "new mesh: re-bind")
	testing.expect(t, s.ids[0][0] == 1, "x 50 in the mesh = x 150 in the skeleton: the lower bone")
	def.bones = Vector_SkinPose(&s, &pose)
	q = Vector_DeformPoint(&def, {50, 0}, s.ids[0], s.weights[0])
	want = Skeleton_LocalToWorld(pose.bones[2], {50, 0}) - {100, 0}
	testing.expectf(t, close2(q, want), "bent, in mesh space (%v vs %v)", q, want)

	// The warp: corners move by their offsets, bilinear between.
	wd := Vector_Deform{box = {0, 0, 100, 50}, warp = {{-10, -5}, {}, {}, {20, 0}}}
	testing.expect(t, close2(Vector_DeformPoint(&wd, {0, 0}), {-10, -5}), "top left moved")
	testing.expect(t, close2(Vector_DeformPoint(&wd, {100, 0}), {100, 0}), "top right stays")
	testing.expect(t, close2(Vector_DeformPoint(&wd, {100, 50}), {120, 50}), "bottom right moved")
	testing.expect(t, close2(Vector_DeformPoint(&wd, {50, 25}), {50 + 2.5, 25 - 1.25}), "the middle: a quarter of each")

	// --- the node -----------------------------------------------------------------------------
	dir :: "test_vector_skin_zz"
	_ = os.make_directory_all(dir)
	defer os.remove_all(dir)
	_ = os.write_entire_file(dir + "/arm.json", transmute([]u8)string(ARM_RIG))
	_ = os.write_entire_file(dir + "/limb.svg", transmute([]u8)string(LIMB_SVG))
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, dir)
	game.resourceManager.projectDir = game.assetManager.projectDir
	scene := game->createScene("vskin", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	sn := cast(^SkeletonNode)Node_CreateByTypeName(scene, "SkeletonNode")
	sn.file = "arm.json"
	sn.animation = "bent"
	v := cast(^VectorShapeNode)Node_CreateByTypeName(scene, "VectorShapeNode", sn)
	v.file = "limb.svg"
	v.position = {100, 0} // (centred: the tube's middle line on the bones)
	testing.expect(t, VectorShapeNode_SkinTarget(v) == nil && !VectorShapeNode_Deformed(v), "no bones named: not skinned")
	v.skinBones = "upper, lower"
	v.skinSmooth = 30
	testing.expect(t, VectorShapeNode_SkinTarget(v) == sn && VectorShapeNode_FxActive(v), "skinned: its own mesh")
	v.shadowColor = {0, 0, 0, 255}
	testing.expect(t, !Vector_FiltersActive(v), "filters skip bent art")
	v.shadowColor = {}
	ProcessNodeQueues(scene.manager, &game.gameContext)
	for _ in 0 ..< 3 do game->run(1.0 / 60)
	testing.expect(t, sn.data != nil, "the skeleton loaded")
	cache, offset, mok := VectorShapeNode_Mesh(v, 1)
	testing.expect(t, mok && len(cache.mesh.verts) > 0, "tessellated")
	if !mok do return
	testing.expectf(t, close2(offset, {-100, -20}), "centred (%v)", offset)
	nd, bent := VectorShapeNode_Deform(v, cache, offset)
	testing.expect(t, bent && len(nd.bones) == 2 && len(v.skinning.ids) == len(cache.mesh.verts), "bound: weights per vertex")
	testing.expect(t, cache.skinIds != nil, "weights handed to the mesh")
	// The tube's right end (doc 198, 20) follows the lower bone's tip.
	best := -1
	for vv, i in cache.mesh.verts do if best < 0 || abs(vv.x - 198) + abs(vv.y - 20) < abs(cache.mesh.verts[best].x - 198) + abs(cache.mesh.verts[best].y - 20) do best = i
	tipMesh := cache.mesh.verts[best]
	tipNow := Vector_DeformPoint(&nd, tipMesh, v.skinning.ids[best], v.skinning.weights[best]) + offset + v.position
	tipWant := Skeleton_LocalToWorld(sn.pose.bones[2], tipMesh + offset + v.position - {100, 0})
	testing.expectf(t, close2(tipNow, tipWant, 0.5), "the end follows the lower bone (%v vs %v)", tipNow, tipWant)
	lb, lok := VectorShapeNode_LocalBounds(v)
	testing.expectf(t, lok && lb[3] > 60, "bounds grow with the bend (%v)", lb)
	// Picking follows the bend: the lower half where it's drawn, not at rest.
	midBent := Skeleton_LocalToWorld(sn.pose.bones[2], {50, 0}) + sn.globalPosition
	testing.expectf(t, VectorShapeNode_HitTest(v, midBent), "picked where the bent part is drawn (%v)", midBent)
	testing.expect(t, !VectorShapeNode_HitTest(v, sn.globalPosition + {150, 0}), "not where it was at rest")
	_, again := VectorShapeNode_Deform(v, cache, offset)
	testing.expect(t, again && v.skinning.key.tessellations == cache.stats.tessellations, "posing again: same binding")

	// Lua: bones and warp corners set as properties, a warp corner tweened.
	v.name = "Limb"
	L := game.scriptManager.L
	if lua.L_dostring(L, `
local limb = Scene.find_node("Limb")
limb.skinBones = "*"
limb.warpTopLeft = Vec2(-20, 30)
limb.warpTopRight = {20, 30}
Tween.to(limb, "warpTopLeft", Vec2(0, 0), 0.1, "linear")
`) != 0 {
		testing.fail_now(t, string(lua.tostring(L, -1)))
	}
	testing.expect_value(t, v.skinBones, "*")
	testing.expectf(t, v.warpTopRight == {20, 30}, "a table sets a corner (%v)", v.warpTopRight)
	for _ in 0 ..< 12 do game->run(1.0 / 60)
	testing.expectf(t, close2(v.warpTopLeft, {0, 0}, 0.01), "the corner tweened back (%v)", v.warpTopLeft)
}

// #331: binding splits only what bends - triangles wholly on one bone stay
// whole (one bone moves them affinely: the same picture, fewer triangles),
// a single bone splits nothing, a warp still splits everywhere.
@(test)
test_vector_skin_subdivides_what_bends :: proc(t: ^testing.T) {
	d, dok := Skeleton_LoadSpine(ARM_RIG, "", nil, nil)
	testing.expect(t, dok && d != nil, "the rig loads")
	if d == nil do return
	defer Skeleton_DataDestroy(d, nil)
	// A strip along both bones (0..200 x -10..10): two triangles far from
	// the joint at x 100 on each side, two across it.
	strip :: proc(c: ^Vector_Cache) {
		Vector_Mesh_Clear(&c.mesh)
		xs := [?]f32{0, 40, 80, 120, 160, 200}
		for x in xs {
			append(&c.mesh.verts, [2]f32{x, -10}, [2]f32{x, 10})
			append(&c.mesh.cols, [4]u8{255, 255, 255, 255}, [4]u8{255, 255, 255, 255})
			append(&c.mesh.gc, [2]f32{}, [2]f32{})
			append(&c.mesh.gi, [2]f32{}, [2]f32{})
		}
		for i in 0 ..< len(xs) - 1 {
			a := u32(i * 2)
			append(&c.mesh.idx, a, a + 1, a + 2, a + 1, a + 3, a + 2)
		}
		c.mesh.bounds = {0, -10, 200, 10}
		c.stats.tessellations += 1
	}
	c: Vector_Cache
	defer Vector_Cache_Destroy(&c)
	s: Vector_Skin
	defer Vector_Skin_Destroy(&s)
	strip(&c)
	before := len(c.mesh.idx) / 3
	testing.expect(t, Vector_SkinBind(&s, d, &c, "upper", 12, VECTOR_AFFINE_IDENTITY), "bound to one bone")
	testing.expect_value(t, len(c.mesh.idx) / 3, before) // (one bone: nothing to bend at)

	strip(&c)
	testing.expect(t, Vector_SkinBind(&s, d, &c, "upper, lower", 12, VECTOR_AFFINE_IDENTITY), "bound to two")
	bent := len(c.mesh.idx) / 3
	testing.expect(t, bent > before, "split round the joint")
	// The end pieces (x 0..40, 160..200) stay (nearly) whole: split at most
	// where they meet a piece that bends.
	ends :: proc(m: ^Vector_Mesh) -> int {
		n := 0
		for i := 0; i < len(m.idx); i += 3 {
			a, b, c := m.verts[m.idx[i]].x, m.verts[m.idx[i + 1]].x, m.verts[m.idx[i + 2]].x
			if max(a, b, c) <= 40 || min(a, b, c) >= 160 do n += 1
		}
		return n
	}
	rigidEnds := ends(&c.mesh)
	testing.expectf(t, rigidEnds <= 8, "the ends stay whole (%d triangles)", rigidEnds)
	// Every vertex of a rigid piece has its bone alone.
	for v, i in c.mesh.verts do if v.x <= 40 || v.x >= 160 {
		testing.expectf(t, s.weights[i] == {1, 0, 0, 0}, "vertex %v: one bone (%v)", v, s.weights[i])
	}

	strip(&c)
	testing.expect(t, Vector_SkinBind(&s, d, &c, "upper, lower", 12, VECTOR_AFFINE_IDENTITY, warped = true), "warped")
	testing.expect(t, len(c.mesh.idx) / 3 > bent, "a warp bends rigid parts too: split everywhere")
	testing.expectf(t, ends(&c.mesh) > rigidEnds * 4, "warped: the ends split too (%d)", ends(&c.mesh))
}

// #389: bent shapes adjust their colour in the mesh's shader - the CPU
// copy of its maths (the immediate path) greys at saturation 0, keeps the
// colour with no adjustment, and rotates the hue.
@(test)
test_vector_adjust_color :: proc(t: ^testing.T) {
	near :: proc(a, b: [3]f32) -> bool {return abs(a.x - b.x) < 0.01 && abs(a.y - b.y) < 0.01 && abs(a.z - b.z) < 0.01}
	orange := [3]f32{1, 0.6, 0.2}
	testing.expect(t, near(Vector_AdjustColor(orange, VECTOR_NO_ADJUST), orange), "no adjustment keeps the colour")
	g := Vector_AdjustColor(orange, {0, 1, 0})
	testing.expectf(t, near(g, {g.x, g.x, g.x}), "saturation 0 is grey: %v", g)
	testing.expectf(t, abs(g.x - (0.299 + 0.587 * 0.6 + 0.114 * 0.2)) < 0.01, "the grey keeps the brightness: %v", g)
	h := Vector_AdjustColor({1, 0, 0}, {1, 1, 120})
	testing.expectf(t, h.y > 0.9 && h.x < 0.1 && h.z < 0.1, "hue 120 turns red green: %v", h)
	c := Vector_AdjustColor({0.6, 0.5, 0.4}, {1, 2, 0})
	testing.expectf(t, near(c, {0.7, 0.5, 0.3}), "contrast 2 doubles the distance from mid grey: %v", c)
}
