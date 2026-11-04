package engine

import "core:hash"
import "core:math"
import "core:strings"

// ============================================================================
// Vector skinning (Phase 14 V.10): a Vector Shape under a Skeleton bends
// with its bones - limbs that curve smoothly at the elbow instead of two
// rigid pieces meeting at a joint - and a four-corner warp (a free-form
// deformer) squashes and stretches any Vector Shape.
//
// Binding: in the skeleton's setup pose, every vertex of the node's own
// tessellated mesh gets up to four bones, weighted by how close it is to
// each bone (a segment from its joint to its tip): the nearest bone, plus
// any other within skinSmooth px of it, fading out (smoothstep) - so 0 makes
// rigid parts and 40 bends a limb round a soft elbow. Weights ride in the
// mesh's spare attributes (bone ids in the normal, weights in the tangent).
//
// Each frame: per bound bone a matrix (mesh space) = bind^-1 * world_now *
// world_setup^-1 * bind, uploaded as uniforms; the vector shader's skinned
// variant (vector_mesh.odin) blends them per vertex. The mesh is never
// re-tessellated or re-uploaded for a pose: a posed character costs a few
// dozen uniforms. Bound bones: up to VECTOR_SKIN_MAX_BONES per node.
// ============================================================================

VECTOR_SKIN_MAX_BONES :: 64
VECTOR_SKIN_EDGE :: 10 // the longest triangle edge in a skinned mesh (its units)

// Vector_Affine: a 2D affine transform - x' = a x + b y + tx,
// y' = c x + d y + ty ({a, b, c, d, tx, ty}, like a bone's world matrix).
Vector_Affine :: [6]f32

VECTOR_AFFINE_IDENTITY :: Vector_Affine{1, 0, 0, 1, 0, 0}

// Vector_AffineMul: m * n (n applied first).
Vector_AffineMul :: proc(m, n: Vector_Affine) -> Vector_Affine {
	return {
		m[0] * n[0] + m[1] * n[2], m[0] * n[1] + m[1] * n[3],
		m[2] * n[0] + m[3] * n[2], m[2] * n[1] + m[3] * n[3],
		m[0] * n[4] + m[1] * n[5] + m[4], m[2] * n[4] + m[3] * n[5] + m[5],
	}
}

Vector_AffineInverse :: proc(m: Vector_Affine) -> (Vector_Affine, bool) {
	det := m[0] * m[3] - m[1] * m[2]
	if abs(det) < 1e-12 do return VECTOR_AFFINE_IDENTITY, false
	k := 1 / det
	return {m[3] * k, -m[1] * k, -m[2] * k, m[0] * k, (m[1] * m[5] - m[3] * m[4]) * k, (m[2] * m[4] - m[0] * m[5]) * k}, true
}

Vector_AffineApply :: proc(m: Vector_Affine, p: [2]f32) -> [2]f32 {
	return {m[0] * p.x + m[1] * p.y + m[4], m[2] * p.x + m[3] * p.y + m[5]}
}

// Vector_AffineTRS: translate * rotate (degrees) * scale - a node's local
// transform.
Vector_AffineTRS :: proc(pos: [2]f32, rotation: f32, scale: [2]f32) -> Vector_Affine {
	r := rotation * math.RAD_PER_DEG
	c, s := math.cos(r), math.sin(r)
	return {c * scale.x, -s * scale.y, s * scale.x, c * scale.y, pos.x, pos.y}
}

vector_bone_affine :: proc(b: Skel_BonePose) -> Vector_Affine {return {b.a, b.b, b.c, b.d, b.wx, b.wy}}

// Vector_Deform: how a mesh is bent when drawn (Vector_Cache_Draw).
Vector_Deform :: struct {
	bones: []Vector_Affine, // per skin bone, in mesh space (empty: not skinned)
	warp:  [4][2]f32,       // corner offsets: top left, top right, bottom left, bottom right
	box:   [4]f32,          // the warp's box in mesh space: x, y, w, h (w 0: no warp)
}

// Vector_DeformPoint: one point through the warp, then the skin (the CPU
// version of the skinned shader: the immediate path, bounds, tests).
Vector_DeformPoint :: proc(d: ^Vector_Deform, p: [2]f32, ids: [4]u8 = {}, weights: [4]f32 = {}) -> [2]f32 {
	q := p
	if d.box[2] > 0 && d.box[3] > 0 {
		u := [2]f32{(p.x - d.box[0]) / d.box[2], (p.y - d.box[1]) / d.box[3]}
		top := d.warp[0] + (d.warp[1] - d.warp[0]) * u.x
		bot := d.warp[2] + (d.warp[3] - d.warp[2]) * u.x
		q += top + (bot - top) * u.y
	}
	if len(d.bones) == 0 || weights == {} do return q
	out: [2]f32
	for k in 0 ..< 4 {
		if weights[k] <= 0 do continue
		out += Vector_AffineApply(d.bones[min(int(ids[k]), len(d.bones) - 1)], q) * weights[k]
	}
	return out
}

Vector_Skin_Key :: struct {
	data:          ^Skeleton_Data,
	cache:         ^Vector_Cache,
	tessellations: int,
	bucket:        f32,
	bones:         u64, // hash of the bone list
	smooth:        f32,
	bind:          Vector_Affine,
	warped:        bool, // (a warp bends rigid parts too: split everywhere)
}

// Vector_Skin: one node's binding to a skeleton.
Vector_Skin :: struct {
	key:      Vector_Skin_Key,
	valid:    bool,
	bones:    [dynamic]int,           // skin bone i = the skeleton's bone bones[i]
	setupInv: [dynamic]Vector_Affine, // their setup-pose world transforms, inverted
	ids:      [dynamic][4]u8,         // per mesh vertex: skin bones
	weights:  [dynamic][4]f32,
	bind:     Vector_Affine,          // mesh space -> skeleton space
	bindInv:  Vector_Affine,
	mats:     [dynamic]Vector_Affine, // this pose, in mesh space
}

Vector_Skin_Destroy :: proc(s: ^Vector_Skin) {
	delete(s.bones)
	delete(s.setupInv)
	delete(s.ids)
	delete(s.weights)
	delete(s.mats)
	s^ = {}
}

// Vector_SkinBoneList: the skeleton's bones a list names ("a, b, c"; "*" =
// all; unknown names skipped), at most VECTOR_SKIN_MAX_BONES.
Vector_SkinBoneList :: proc(d: ^Skeleton_Data, list: string, out: ^[dynamic]int) {
	clear(out)
	if d == nil do return
	if strings.trim_space(list) == "*" {
		for i in 0 ..< min(len(d.bones), VECTOR_SKIN_MAX_BONES) do append(out, i)
		return
	}
	rest := list
	for part in strings.split_iterator(&rest, ",") {
		name := strings.trim_space(part)
		if name == "" do continue
		bi := Skeleton_BoneIndex(d, name)
		if bi < 0 do continue
		dup := false
		for b in out do if b == bi {dup = true; break}
		if !dup && len(out) < VECTOR_SKIN_MAX_BONES do append(out, bi)
	}
}

// Vector_MeshSubdivide splits a mesh's triangles until no edge is longer
// than maxEdge - tessellation makes long thin triangles (earcut fans across
// a fill, fringes and strokes along straight sides) that would stretch
// across a bend. Edges are split where shared (red-green refinement: a
// triangle splits by how many of its edges are marked), so there are no
// T-junctions to crack open. Attributes are interpolated. rigid (optional):
// triangles wholly on one bone aren't split for their own sake - a single
// bone moves them as a whole (affine), so splitting would only add
// triangles (software GL pays per triangle, #331).
Vector_MeshSubdivide :: proc(m: ^Vector_Mesh, maxEdge: f32, rigid: ^Vector_Skin_Rigid = nil) {
	if maxEdge <= 0 || len(m.idx) == 0 do return
	lim := maxEdge * maxEdge
	len2 :: proc(m: ^Vector_Mesh, a, b: u32) -> f32 {
		d := m.verts[a] - m.verts[b]
		return d.x * d.x + d.y * d.y
	}
	ekey :: proc(a, b: u32) -> u64 {return u64(min(a, b)) << 32 | u64(max(a, b))}
	for _ in 0 ..< 12 {
		mids := make(map[u64]u32, allocator = context.temp_allocator)
		ntri := len(m.idx) / 3
		for t in 0 ..< ntri {
			if rigid != nil && vector_tri_rigid(rigid, m.verts[m.idx[t * 3]], m.verts[m.idx[t * 3 + 1]], m.verts[m.idx[t * 3 + 2]]) do continue
			for k in 0 ..< 3 {
				a, b := m.idx[t * 3 + k], m.idx[t * 3 + (k + 1) % 3]
				if len2(m, a, b) <= lim do continue
				key := ekey(a, b)
				if key in mids do continue
				mids[key] = u32(len(m.verts))
				append(&m.verts, (m.verts[a] + m.verts[b]) * 0.5)
				ca, cb := m.cols[a], m.cols[b]
				append(&m.cols, [4]u8{u8((u32(ca.r) + u32(cb.r)) / 2), u8((u32(ca.g) + u32(cb.g)) / 2), u8((u32(ca.b) + u32(cb.b)) / 2), u8((u32(ca.a) + u32(cb.a)) / 2)})
				append(&m.gc, (m.gc[a] + m.gc[b]) * 0.5)
				append(&m.gi, m.gi[a])
			}
		}
		if len(mids) == 0 do return
		out := make([dynamic]u32, 0, len(m.idx) * 2, context.temp_allocator)
		for t in 0 ..< ntri {
			v := [3]u32{m.idx[t * 3], m.idx[t * 3 + 1], m.idx[t * 3 + 2]}
			mid: [3]u32 // mid[k]: the midpoint of edge v[k] -> v[k + 1] (0: none)
			n := 0
			for k in 0 ..< 3 {
				if i, ok := mids[ekey(v[k], v[(k + 1) % 3])]; ok {mid[k] = i + 1; n += 1}
			}
			switch n {
			case 0:
				append(&out, v[0], v[1], v[2])
			case 1:
				for k in 0 ..< 3 do if mid[k] != 0 {
					a, b, c, mm := v[k], v[(k + 1) % 3], v[(k + 2) % 3], mid[k] - 1
					append(&out, a, mm, c, mm, b, c)
				}
			case 2:
				// The unmarked edge is v[k] -> v[k + 1]; split the other two.
				for k in 0 ..< 3 do if mid[k] == 0 {
					a, b, c := v[k], v[(k + 1) % 3], v[(k + 2) % 3]
					m1, m2 := mid[(k + 1) % 3] - 1, mid[(k + 2) % 3] - 1 // (b -> c, c -> a)
					append(&out, a, b, m1, a, m1, m2, m1, c, m2)
				}
			case 3:
				m0, m1, m2 := mid[0] - 1, mid[1] - 1, mid[2] - 1
				append(&out, v[0], m0, m2, m0, v[1], m1, m2, m1, v[2], m0, m1, m2)
			}
		}
		clear(&m.idx)
		append(&m.idx, ..out[:])
	}
}

// Vector_Skin_Rigid: what decides whether a triangle bends (the bones'
// segments in the skeleton's space, mesh space -> that space, the joints'
// smoothing).
Vector_Skin_Rigid :: struct {
	segs:   [][2][2]f32,
	bind:   Vector_Affine,
	smooth: f32,
}

// vector_tri_rigid: whether every point of a triangle (mesh space) gets one
// bone alone - the nearest bone at its centre is nearer than every other by
// more than the smoothing everywhere in it (distances move at most as far
// as the point does: the centre's, give or take the triangle's radius).
vector_tri_rigid :: proc(r: ^Vector_Skin_Rigid, a, b, c: [2]f32) -> bool {
	if len(r.segs) == 1 do return true
	pa, pb, pc := Vector_AffineApply(r.bind, a), Vector_AffineApply(r.bind, b), Vector_AffineApply(r.bind, c)
	ctr := (pa + pb + pc) / 3
	rad: f32 = 0
	for p in ([3][2]f32{pa, pb, pc}) {
		d := p - ctr
		rad = max(rad, math.sqrt(d.x * d.x + d.y * d.y))
	}
	near, dmin := -1, max(f32)
	for seg, i in r.segs {
		if d := seg_dist(ctr, seg[0], seg[1]); d < dmin {near, dmin = i, d}
	}
	for seg, i in r.segs {
		if i == near do continue
		if seg_dist(ctr, seg[0], seg[1]) - dmin - 2 * rad <= max(r.smooth, 0) + 1e-3 do return false
	}
	return true
}

@(private = "file")
seg_dist :: proc(p, a, b: [2]f32) -> f32 {
	ab := b - a
	l2 := ab.x * ab.x + ab.y * ab.y
	t: f32 = 0
	if l2 > 1e-8 do t = clamp(((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / l2, 0, 1)
	q := a + ab * t - p
	return math.sqrt(q.x * q.x + q.y * q.y)
}

// Vector_SkinBind (re)binds a mesh to bones when anything the binding
// depends on changed; true when the weights were remade (the mesh needs
// them uploaded). bind: mesh space -> the skeleton's space.
Vector_SkinBind :: proc(s: ^Vector_Skin, d: ^Skeleton_Data, c: ^Vector_Cache, boneList: string, smooth: f32, bind: Vector_Affine, warped := false) -> bool {
	key := Vector_Skin_Key{
		data = d, cache = c, tessellations = c.stats.tessellations, bucket = c.bucket,
		bones = hash.fnv64a(transmute([]u8)boneList), smooth = smooth, bind = bind, warped = warped,
	}
	if s.valid && key == s.key do return false
	context.allocator = Engine_HeapAllocator()
	s.key = key
	s.valid = true
	s.bind = bind
	s.bindInv, _ = Vector_AffineInverse(bind)
	if s.bones == nil {
		s.bones = make([dynamic]int)
		s.setupInv = make([dynamic]Vector_Affine)
		s.ids = make([dynamic][4]u8)
		s.weights = make([dynamic][4]f32)
		s.mats = make([dynamic]Vector_Affine)
	}
	Vector_SkinBoneList(d, boneList, &s.bones)
	// The setup pose's world transforms (the skeleton's own space).
	setup: Skeleton_Pose
	Skeleton_PoseInit(&setup, d, context.temp_allocator)
	Skeleton_UpdateWorld(&setup, d, {0, 0})
	clear(&s.setupInv)
	segs := make([][2][2]f32, len(s.bones), context.temp_allocator)
	for bi, i in s.bones {
		w := setup.bones[bi]
		inv, _ := Vector_AffineInverse(vector_bone_affine(w))
		append(&s.setupInv, inv)
		segs[i] = {{w.wx, w.wy}, Skeleton_LocalToWorld(w, {max(d.bones[bi].length, 0), 0})}
	}
	m := &c.mesh
	// (Short edges: what bends must have vertices to bend at - not what one
	// bone moves whole, unless a warp bends it too. Idempotent: a re-bind of
	// the same mesh splits nothing.)
	if len(s.bones) > 0 {
		size := max(m.bounds[2] - m.bounds[0], m.bounds[3] - m.bounds[1])
		rigid := Vector_Skin_Rigid{segs = segs, bind = bind, smooth = smooth}
		Vector_MeshSubdivide(m, max(VECTOR_SKIN_EDGE, size / 64), nil if warped else &rigid)
	}
	resize(&s.ids, len(m.verts))
	resize(&s.weights, len(m.verts))
	dist := make([]f32, len(s.bones), context.temp_allocator)
	for v, vi in m.verts {
		s.ids[vi], s.weights[vi] = {}, {}
		if len(s.bones) == 0 do continue
		p := Vector_AffineApply(bind, v)
		dmin := max(f32)
		for seg, i in segs {
			dist[i] = seg_dist(p, seg[0], seg[1])
			dmin = min(dmin, dist[i])
		}
		// The four strongest: the nearest bone, then any within `smooth` of it.
		ids: [4]u8
		ws: [4]f32
		for i in 0 ..< len(s.bones) {
			w: f32
			if smooth > 0 {
				t := clamp(1 - (dist[i] - dmin) / smooth, 0, 1)
				w = t * t * (3 - 2 * t)
			} else {
				w = 1 if dist[i] <= dmin + 1e-4 else 0
			}
			if w <= 0 do continue
			// (Insert, keeping the slots sorted strongest first.)
			for k in 0 ..< 4 {
				if w > ws[k] {
					for j := 3; j > k; j -= 1 {ws[j], ids[j] = ws[j - 1], ids[j - 1]}
					ws[k], ids[k] = w, u8(i)
					break
				}
			}
		}
		sum := ws[0] + ws[1] + ws[2] + ws[3]
		if sum > 0 do ws /= sum
		s.ids[vi], s.weights[vi] = ids, ws
	}
	return true
}

// Vector_SkinPose: this frame's matrices (mesh space) from a pose.
Vector_SkinPose :: proc(s: ^Vector_Skin, pose: ^Skeleton_Pose) -> []Vector_Affine {
	clear(&s.mats)
	for bi, i in s.bones {
		if bi >= len(pose.bones) {
			append(&s.mats, VECTOR_AFFINE_IDENTITY)
			continue
		}
		m := Vector_AffineMul(vector_bone_affine(pose.bones[bi]), s.setupInv[i])
		append(&s.mats, Vector_AffineMul(s.bindInv, Vector_AffineMul(m, s.bind)))
	}
	return s.mats[:]
}
