package engine

import "core:math"
import rl "vendor:raylib"

// ============================================================================
// Make Occluder from Sprite (the editor; lighting_nodes.odin): a sprite's
// silhouette as light-occluder shapes. The image's opaque pixels (alpha at
// least half) are traced into outlines - one per island, holes filled -
// simplified, then cut into convex polygons of at most 8 corners (the
// vector colliders' decomposition: vector_collider.odin), in the node's
// space (as the sprite is drawn: size, origin).
// ============================================================================

// Image_AlphaOutlines: the outer outlines of an image region's opaque
// islands, in region pixels (corners of pixels; counter-clockwise).
Image_AlphaOutlines :: proc(img: rl.Image, region: rl.Rectangle, threshold: u8 = 128, allocator := context.temp_allocator) -> [dynamic][dynamic][2]f32 {
	out := make([dynamic][dynamic][2]f32, allocator)
	copy := rl.ImageCopy(img)
	defer rl.UnloadImage(copy)
	rl.ImageFormat(&copy, .UNCOMPRESSED_R8G8B8A8)
	px := ([^]rl.Color)(copy.data)
	x0, y0 := int(region.x), int(region.y)
	w, h := int(region.width), int(region.height)
	if w <= 0 || h <= 0 do return out
	solid :: proc(px: [^]rl.Color, iw, ih, x0, y0, w, h, x, y: int, thr: u8) -> bool {
		if x < 0 || y < 0 || x >= w || y >= h do return false
		X, Y := x0 + x, y0 + y
		if X < 0 || Y < 0 || X >= iw || Y >= ih do return false
		return px[Y * iw + X].a >= thr
	}
	iw, ih := int(copy.width), int(copy.height)
	// Each opaque pixel's sides facing transparency, as directed edges with
	// the opaque side on the left (outer outlines run counter-clockwise in
	// screen space... clockwise on screen with y down).
	Edge :: struct {a, b: [2]int}
	edges := make([dynamic]Edge, context.temp_allocator)
	for y in 0 ..< h do for x in 0 ..< w {
		if !solid(px, iw, ih, x0, y0, w, h, x, y, threshold) do continue
		if !solid(px, iw, ih, x0, y0, w, h, x, y - 1, threshold) do append(&edges, Edge{{x, y}, {x + 1, y}})
		if !solid(px, iw, ih, x0, y0, w, h, x + 1, y, threshold) do append(&edges, Edge{{x + 1, y}, {x + 1, y + 1}})
		if !solid(px, iw, ih, x0, y0, w, h, x, y + 1, threshold) do append(&edges, Edge{{x + 1, y + 1}, {x, y + 1}})
		if !solid(px, iw, ih, x0, y0, w, h, x - 1, y, threshold) do append(&edges, Edge{{x, y + 1}, {x, y}})
	}
	// Chain them into loops.
	key :: proc(p: [2]int) -> i64 {return i64(p.x) << 32 | i64(u32(p.y))}
	from := make(map[i64][dynamic]int, allocator = context.temp_allocator)
	for e, i in edges {
		k := key(e.a)
		list := from[k]
		if list == nil do list = make([dynamic]int, context.temp_allocator)
		append(&list, i)
		from[k] = list
	}
	used := make([]bool, len(edges), context.temp_allocator)
	for start in 0 ..< len(edges) {
		if used[start] do continue
		loop := make([dynamic][2]f32, allocator)
		cur := start
		for {
			used[cur] = true
			e := edges[cur]
			append(&loop, [2]f32{f32(e.a.x), f32(e.a.y)})
			next := -1
			for cand in from[key(e.b)] do if !used[cand] {
				next = cand
				break
			}
			if next < 0 do break
			cur = next
		}
		// Straight runs: only the corners.
		pruned := make([dynamic][2]f32, allocator)
		n := len(loop)
		for i in 0 ..< n {
			p, q, r := loop[(i + n - 1) % n], loop[i], loop[(i + 1) % n]
			if (q.x - p.x) * (r.y - q.y) - (q.y - p.y) * (r.x - q.x) != 0 do append(&pruned, q)
		}
		delete(loop)
		// Outer outlines only (holes run the other way: filled).
		area: f32 = 0
		m := len(pruned)
		for i in 0 ..< m {
			a, b := pruned[i], pruned[(i + 1) % m]
			area += a.x * b.y - b.x * a.y
		}
		if m >= 3 && area > 0 do append(&out, pruned)
		else do delete(pruned)
	}
	return out
}

// Occluder_ShapesFromImage: an image region's silhouette as convex polygon
// shapes in node space - the region drawn `size` big with its top-left at
// -origin. Islands smaller than minArea (region pixels) are left out.
Occluder_ShapesFromImage :: proc(img: rl.Image, region: rl.Rectangle, size, origin: [2]f32, out: ^[dynamic]PhysicsShape, minArea: f32 = 16) -> int {
	outlines := Image_AlphaOutlines(img, region)
	if len(outlines) == 0 do return 0
	sx := size.x / max(region.width, 1)
	sy := size.y / max(region.height, 1)
	polys: Vector_Polys
	polys.pts = make([dynamic][2]f32, context.temp_allocator)
	polys.rings = make([dynamic]Vector_Ring, context.temp_allocator)
	for o in outlines {
		area: f32 = 0
		for i in 0 ..< len(o) {
			a, b := o[i], o[(i + 1) % len(o)]
			area += a.x * b.y - b.x * a.y
		}
		if abs(area) * 0.5 < minArea do continue
		append(&polys.rings, Vector_Ring{first = len(polys.pts), count = len(o), parent = -1})
		for p in o do append(&polys.pts, [2]f32{p.x * sx - origin.x, p.y * sy - origin.y})
	}
	if len(polys.rings) == 0 do return 0
	// Simplified to about a 64th of the sprite (at least a pixel).
	tol := max(math.max(size.x, size.y) / 64, max(sx, sy))
	simple: Vector_Polys
	simple.pts = make([dynamic][2]f32, context.temp_allocator)
	simple.rings = make([dynamic]Vector_Ring, context.temp_allocator)
	if !Vector_PolysSimplify(&polys, tol, &simple) do simple = polys
	pieces := make([dynamic][2]f32, context.temp_allocator)
	counts := make([dynamic]int, context.temp_allocator)
	Vector_ConvexDecompose(&simple, 8, &pieces, &counts)
	at := 0
	made := 0
	for n in counts {
		if n >= 3 {
			append(out, MakePolygonPhysicsShape(pieces[at:at + n]))
			made += 1
		}
		at += n
	}
	return made
}
