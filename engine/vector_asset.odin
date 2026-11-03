package engine

import "core:log"
import os "osx"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

// ============================================================================
// Vector assets (Phase 14 V.4 / V.5): an SVG file loaded once per path
// (counted) and reloaded when it changes (ResourceManager_CheckForChanges:
// saving in Inkscape / Illustrator / Affinity shows up in the editor and in
// a running game). Its tessellations are shared by every node drawing it -
// one cached mesh per scale bucket, the most recent few kept - so a hundred
// copies of a character cost one tessellation and a hundred draw calls of
// the same GPU mesh.
// ============================================================================

VECTOR_BUCKETS_KEPT :: 3

Vector_Resource :: struct {
	path:    string,
	doc:     Vector_Doc,
	refs:    int,
	version: int, // +1 per reload
	modTime: time.Time,
	caches:  [dynamic]Vector_Resource_Cache, // per part, up to VECTOR_BUCKETS_KEPT buckets each
	frame:   u64, // a draw counter (which bucket was used last)
	owner:   ^ResourceManager,
	pending: int, // background tessellations running (vector_jobs.odin)
	waiting: [dynamic][2]f32, // (part, bucket) queued for a worker
}

// A part: the whole document (-1) or one of its groups (a symbol, a swap
// frame) - its shapes, drawn in document coordinates.
Vector_Resource_Cache :: struct {
	cache:    Vector_Cache,
	part:     int,
	used:     u64, // r.frame when last drawn
	version:  int,
}

// Vector_PartShapes: a part's shapes (-1: all of them).
Vector_PartShapes :: proc(r: ^Vector_Resource, part: int) -> []Vector_Shape {return Vector_DocShapes(&r.doc, part)}

// Vector_IsPath: a vector asset's path (.svg).
Vector_IsPath :: proc(path: string) -> bool {
	lower := strings.to_lower(path, context.temp_allocator)
	return strings.has_suffix(lower, ".svg")
}

// ResourceManager_LoadVector: the file's resource (a reference taken); nil
// when it can't be read or isn't an SVG (the reasons are logged).
ResourceManager_LoadVector :: proc(rm: ^ResourceManager, path: string) -> ^Vector_Resource {
	if rm.vectors != nil {
		if r, ok := rm.vectors[path]; ok {
			r.refs += 1
			return r
		}
	}
	data, found := vector_bytes(rm, path)
	if !found {
		log.errorf("Vector file not found: %s", path)
		return nil
	}
	defer delete(data, Engine_HeapAllocator())
	r := new(Vector_Resource, Engine_HeapAllocator())
	if !Vector_LoadSVG(string(data), &r.doc) {
		log.errorf("Can't read the SVG %s: %s", path, strings.join(r.doc.warnings[:], "; ", context.temp_allocator))
		Vector_Doc_Destroy(&r.doc)
		free(r, Engine_HeapAllocator())
		return nil
	}
	for w in r.doc.warnings do log.warnf("%s: %s", path, w)
	if imp := Asset_ImportGet(rm, path); imp.vectorScale > 0 do Vector_DocScale(&r.doc, imp.vectorScale)
	r.path = strings.clone(path, Engine_HeapAllocator())
	r.refs = 1
	r.owner = rm
	if info, err := os.stat(path, context.temp_allocator); err == nil do r.modTime = info.modification_time
	if rm.vectors == nil do rm.vectors = make(map[string]^Vector_Resource, allocator = Engine_HeapAllocator())
	rm.vectors[r.path] = r
	return r
}

// ResourceManager_ReleaseVector drops a reference (the last frees it).
ResourceManager_ReleaseVector :: proc(r: ^Vector_Resource) {
	if r == nil do return
	r.refs -= 1
	if r.refs > 0 do return
	if r.owner != nil && r.owner.vectors != nil do delete_key(&r.owner.vectors, r.path)
	vector_resource_free(r)
}

@(private = "file")
vector_resource_free :: proc(r: ^Vector_Resource) {
	context.allocator = Engine_HeapAllocator()
	for &c in r.caches do Vector_Cache_Destroy(&c.cache)
	delete(r.caches)
	delete(r.waiting)
	Vector_Doc_Destroy(&r.doc)
	delete(r.path)
	free(r)
}

// Vector_ReleaseAll frees a resource manager's vector files (its shutdown).
Vector_ReleaseAll :: proc(rm: ^ResourceManager) {
	for _, r in rm.vectors do vector_resource_free(r)
	delete(rm.vectors)
	rm.vectors = nil
}

// Vector_ResourceCount: files loaded now (tests).
Vector_ResourceCount :: proc(rm: ^ResourceManager) -> int {return len(rm.vectors)}

@(private = "file")
vector_bytes :: proc(rm: ^ResourceManager, path: string) -> ([]u8, bool) {
	if os.is_file(path) {
		data, err := os.read_entire_file(path, Engine_HeapAllocator())
		return data, err == nil
	}
	if rm != nil {
		if b, ok := resource_bytes(rm, path); ok {
			defer delete(b)
			c := make([]u8, len(b), Engine_HeapAllocator())
			copy(c, b)
			return c, true
		}
	}
	return nil, false
}

// Vector_CheckForChanges reloads the files changed on disk; the number reloaded.
Vector_CheckForChanges :: proc(rm: ^ResourceManager) -> int {
	n := 0
	for _, r in rm.vectors {
		if r.modTime == {} || r.pending > 0 do continue // (jobs read the document: next check)
		info, err := os.stat(r.path, context.temp_allocator)
		if err != nil || time.diff(r.modTime, info.modification_time) <= 0 do continue
		data, rerr := os.read_entire_file(r.path, context.temp_allocator)
		if rerr != nil do continue
		doc: Vector_Doc
		if !Vector_LoadSVG(string(data), &doc) {
			Vector_Doc_Destroy(&doc) // (half-written: next time)
			continue
		}
		if imp := Asset_ImportGet(rm, r.path); imp.vectorScale > 0 do Vector_DocScale(&doc, imp.vectorScale)
		Vector_Doc_Destroy(&r.doc)
		r.doc = doc
		r.modTime = info.modification_time
		r.version += 1
		for &c in r.caches do c.cache.dirty = true
		log.infof("Reloaded %s", r.path)
		n += 1
	}
	return n
}

// Vector_ResourceMesh: a part's cached mesh (part -1: the whole document)
// for drawing at a screen-pixel size. A bucket not cached yet: with
// `background`, the part's nearest cached bucket is drawn meanwhile and a
// worker tessellates the new one (vector_jobs.odin); otherwise (or when
// nothing is cached) it is tessellated now. A part keeps its
// VECTOR_BUCKETS_KEPT most recently used buckets.
Vector_ResourceMesh :: proc(r: ^Vector_Resource, t: ^Vector_Tess, pixel: f32, background := false, part := -1) -> ^Vector_Cache {
	context.allocator = Engine_HeapAllocator()
	// (Finished background meshes, once a frame - also where the game loop
	// doesn't run: the editor's viewport.)
	@(static) lastPump: f64 = -1
	if now := rl.GetTime(); now != lastPump {
		lastPump = now
		Vector_JobPump()
	}
	if r.caches == nil do r.caches = make([dynamic]Vector_Resource_Cache)
	r.frame += 1
	b := Vector_PixelBucket(pixel)
	slot := -1
	for &c, i in r.caches do if c.part == part && c.cache.bucket == b && c.version == r.version {slot = i; break}
	if slot < 0 && background {
		// The part's nearest bucket that is ready (current version, a mesh).
		near := -1
		best := max(f32)
		for c, i in r.caches {
			if c.part != part || c.version != r.version || c.cache.dirty || len(c.cache.mesh.idx) == 0 do continue
			d := abs(c.cache.bucket / b - 1) if c.cache.bucket > b else abs(b / c.cache.bucket - 1)
			if d < best {best = d; near = i}
		}
		if near >= 0 {
			queued := false
			for w in r.waiting do if int(w[0]) == part && w[1] == b do queued = true
			if !queued {
				if r.waiting == nil do r.waiting = make([dynamic][2]f32)
				append(&r.waiting, [2]f32{f32(part), b})
				vector_job_submit(r, b, part)
			}
			c := &r.caches[near]
			c.used = r.frame
			Vector_Cache_Ensure(&c.cache, t, Vector_PartShapes(r, part), c.cache.bucket) // (uploads it if needed)
			return &c.cache
		}
	}
	if slot < 0 do slot = vector_part_slot(r, part)
	c := &r.caches[slot]
	if c.version != r.version {c.cache.dirty = true; c.version = r.version}
	c.used = r.frame
	Vector_Cache_Ensure(&c.cache, t, Vector_PartShapes(r, part), b)
	return &c.cache
}

// vector_part_slot: a fresh cache slot for a part - a new one, or its least
// recently used when it has VECTOR_BUCKETS_KEPT already.
@(private = "file")
vector_part_slot :: proc(r: ^Vector_Resource, part: int) -> int {
	n, oldest, slot := 0, max(u64), -1
	for c, i in r.caches do if c.part == part {
		n += 1
		if c.used < oldest {oldest = c.used; slot = i}
	}
	if n < VECTOR_BUCKETS_KEPT {
		append(&r.caches, Vector_Resource_Cache{part = part})
		return len(r.caches) - 1
	}
	Vector_Cache_Destroy(&r.caches[slot].cache)
	r.caches[slot] = {part = part}
	return slot
}

// Vector_ResourceGroup: a group's index by name ("" -> -1, the whole
// document; "a/b": b inside a); -2 when there's none of that name.
Vector_ResourceGroup :: proc(r: ^Vector_Resource, name: string) -> int {
	if name == "" do return -1
	if name == "." do return -1
	parts := strings.split(name, "/", context.temp_allocator)
	parent := -1
	found := -2
	for p in parts {
		found = -2
		for g, i in r.doc.groups do if g.parent == parent && g.name == p {found = i; break}
		if found == -2 && len(parts) == 1 {
			// (A bare name matches a group anywhere.)
			for g, i in r.doc.groups do if g.name == p {found = i; break}
		}
		if found == -2 do return -2
		parent = found
	}
	return found
}

// Vector_GroupPath: the path naming a group from the top ("head/mouth"),
// what Vector_ResourceGroup finds it by ("" for -1).
Vector_GroupPath :: proc(r: ^Vector_Resource, group: int, allocator := context.temp_allocator) -> string {
	names := make([dynamic]string, context.temp_allocator)
	for g := group; g >= 0 && g < len(r.doc.groups); g = r.doc.groups[g].parent do inject_at(&names, 0, r.doc.groups[g].name)
	return strings.join(names[:], "/", allocator)
}

// Vector_GroupLoose: how many of a group's shapes are in none of its child
// groups (exploding it into parts leaves those out).
Vector_GroupLoose :: proc(r: ^Vector_Resource, group: int) -> int {
	total := len(r.doc.shapes) if group < 0 else r.doc.groups[group].count
	for k in Vector_GroupChildren(r, group) do total -= r.doc.groups[k].count
	return total
}

// Vector_GroupChildren: a group's direct child groups (-1: the top level).
Vector_GroupChildren :: proc(r: ^Vector_Resource, group: int, allocator := context.temp_allocator) -> []int {
	out := make([dynamic]int, allocator)
	for g, i in r.doc.groups do if g.parent == group do append(&out, i)
	return out[:]
}

// Vector_PartBox: a part's box in document coordinates - its shapes'
// points (the whole document: its box).
Vector_PartBox :: proc(r: ^Vector_Resource, part: int) -> (min, size: [2]f32) {
	if part < 0 do return r.doc.min, r.doc.size
	// (Every frame's shapes, hidden ones too: the box doesn't change with the frame shown.)
	g := r.doc.groups[part]
	b := Vector_ShapesBounds(r.doc.shapes[g.first:g.first + g.count], false)
	return {b[0], b[1]}, {b[2] - b[0], b[3] - b[1]}
}

// Vector_ResourceBounds: the document's box (its origin rectangle).
Vector_ResourceBounds :: proc(r: ^Vector_Resource) -> (min, size: [2]f32) {return r.doc.min, r.doc.size}

// Vector_FileImage: an SVG file rendered into an image fitting max x max px
// (asset thumbnails and previews; needs a window; the caller unloads it; no
// data when the file can't be read).
Vector_FileImage :: proc(path: string, maxSize: i32) -> rl.Image {
	if !rl.IsWindowReady() do return {}
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil do return {}
	doc: Vector_Doc
	defer Vector_Doc_Destroy(&doc)
	if !Vector_LoadSVG(string(data), &doc) do return {}
	return Vector_DocImage(&doc, maxSize)
}

// Vector_DocImage: a document rendered into an image fitting max x max px
// (transparent around it).
Vector_DocImage :: proc(doc: ^Vector_Doc, maxSize: i32) -> rl.Image {
	if !rl.IsWindowReady() || doc.size.x <= 0 || doc.size.y <= 0 do return {}
	s := f32(maxSize) / max(doc.size.x, doc.size.y)
	w, h := max(i32(doc.size.x * s + 0.5), 1), max(i32(doc.size.y * s + 0.5), 1)
	rt := rl.LoadRenderTexture(w, h)
	defer rl.UnloadRenderTexture(rt)
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	cache: Vector_Cache
	defer Vector_Cache_Destroy(&cache)
	{
		context.allocator = Engine_HeapAllocator()
		Vector_Cache_Ensure(&cache, &tess, Vector_DocShapes(doc, -1), 1 / s)
	}
	rl.BeginTextureMode(rt)
	rl.ClearBackground({0, 0, 0, 0})
	Vector_Cache_Draw(&cache, {0, 0}, 0, {s, s}, rl.WHITE, -doc.min)
	rl.EndTextureMode()
	img := rl.LoadImageFromTexture(rt.texture)
	rl.ImageFlipVertical(&img) // (render textures are upside down)
	return img
}

// Vector_PartImage: one part of a resource (a symbol; -1: all of it)
// rendered into an image fitting max x max px (the Library's previews).
Vector_PartImage :: proc(r: ^Vector_Resource, part: int, maxSize: i32) -> rl.Image {
	if !rl.IsWindowReady() || r == nil do return {}
	shapes := Vector_DocShapes(&r.doc, part)
	if len(shapes) == 0 do return {}
	b := Vector_ShapesBounds(shapes)
	size := [2]f32{b[2] - b[0], b[3] - b[1]}
	if size.x <= 0 || size.y <= 0 do return {}
	s := f32(maxSize) / max(size.x, size.y)
	w, h := max(i32(size.x * s + 0.5), 1), max(i32(size.y * s + 0.5), 1)
	rt := rl.LoadRenderTexture(w, h)
	defer rl.UnloadRenderTexture(rt)
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	cache: Vector_Cache
	defer Vector_Cache_Destroy(&cache)
	{
		context.allocator = Engine_HeapAllocator()
		Vector_Cache_Ensure(&cache, &tess, shapes, 1 / s)
	}
	rl.BeginTextureMode(rt)
	rl.ClearBackground({0, 0, 0, 0})
	Vector_Cache_Draw(&cache, {0, 0}, 0, {s, s}, rl.WHITE, {-b[0], -b[1]})
	rl.EndTextureMode()
	img := rl.LoadImageFromTexture(rt.texture)
	rl.ImageFlipVertical(&img)
	return img
}

// vector_resource_install: a finished background mesh into its part's
// bucket slot (main thread; vector_jobs.odin).
vector_resource_install :: proc(r: ^Vector_Resource, part: int, bucket: f32, mesh: ^Vector_Mesh) {
	context.allocator = Engine_HeapAllocator()
	for w, i in r.waiting do if int(w[0]) == part && w[1] == bucket {
		unordered_remove(&r.waiting, i)
		break
	}
	slot := -1
	for c, i in r.caches do if c.part == part && c.cache.bucket == bucket {slot = i; break}
	if slot < 0 do slot = vector_part_slot(r, part)
	c := &r.caches[slot]
	Vector_Cache_Destroy(&c.cache)
	c.cache = {}
	c.part = part
	c.cache.mesh = mesh^
	mesh^ = {}
	c.cache.bucket = bucket
	c.cache.stats.tessellations = 1
	c.version = r.version
	c.used = r.frame
}
