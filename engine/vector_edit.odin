package engine

import "core:fmt"
import "core:math"
import "core:math/linalg"
import os "osx"
import "core:time"
import "core:mem"
import "core:strings"
import vmem "core:mem/virtual"

// ============================================================================
// Editing a vector document (#267, the editor's drawing tools): shapes added
// and removed with the groups' ranges kept right, paths made of cubic
// segments (quadratics converted) so every anchor has two handles, segments
// split, and the resource told its document changed (meshes made again;
// background jobs finished first, as they read the document).
// ============================================================================

// Vector_EditAllocator: what the document's own arrays grow from (its arena).
Vector_EditAllocator :: proc(doc: ^Vector_Doc) -> mem.Allocator {return vmem.arena_allocator(&doc.arena)}

// Vector_ResourceEditBegin waits for the background tessellations reading
// the resource's document; call before changing it.
Vector_ResourceEditBegin :: proc(r: ^Vector_Resource) {
	for r != nil && r.pending > 0 {
		Vector_JobPump()
		if r.pending > 0 do time.sleep(time.Millisecond)
	}
}

// Vector_ResourceEdited: the document changed in memory - its parts' shape
// lists and bounds are made again and every mesh is rebuilt.
Vector_ResourceEdited :: proc(r: ^Vector_Resource) {
	if r == nil do return
	context.allocator = Vector_EditAllocator(&r.doc)
	vector_doc_visible(&r.doc)
	r.doc.drawn = Vector_ShapesBounds(Vector_DocShapes(&r.doc, -1))
	r.version += 1
	for &c in r.caches do c.cache.dirty = true
}

// Vector_ResourceSaved: the file was just written from the document - it
// isn't read back (the document already is what the file says).
Vector_ResourceSaved :: proc(r: ^Vector_Resource) {
	if info, err := os.stat(r.path, context.temp_allocator); err == nil do r.modTime = info.modification_time
}

// Vector_DocInsertShape puts a shape at the end of `group` (-1: the
// document's end) - or at `at` within it (its first shape: drawn under the
// rest) - keeping every group's range right; its index.
Vector_DocInsertShape :: proc(doc: ^Vector_Doc, shape: Vector_Shape, group := -1, at := -1) -> int {
	context.allocator = Vector_EditAllocator(doc)
	lo, hi := 0, len(doc.shapes)
	if group >= 0 && group < len(doc.groups) do lo, hi = doc.groups[group].first, doc.groups[group].first + doc.groups[group].count
	at := clamp(at, lo, hi) if at >= 0 else hi
	inject_at(&doc.shapes, at, shape)
	for &g, gi in doc.groups {
		if vector_group_within(doc, group, gi) do g.count += 1 // (the group and its ancestors grow)
		else if g.first >= at do g.first += 1
	}
	return at
}

// Vector_DocRemoveShape takes shape `i` out, keeping the groups' ranges right.
Vector_DocRemoveShape :: proc(doc: ^Vector_Doc, i: int) {
	if i < 0 || i >= len(doc.shapes) do return
	ordered_remove(&doc.shapes, i)
	for &g in doc.groups {
		if i >= g.first && i < g.first + g.count do g.count -= 1
		else if g.first > i do g.first -= 1
	}
}

// Vector_DocShapeGroup: the innermost group a shape is in (-1: none).
Vector_DocShapeGroup :: proc(doc: ^Vector_Doc, i: int) -> int {
	best, size := -1, max(int)
	for g, gi in doc.groups do if i >= g.first && i < g.first + g.count && g.count < size {best, size = gi, g.count}
	return best
}

// vector_group_within: `g` is `inner` or one of its ancestors.
@(private = "file")
vector_group_within :: proc(doc: ^Vector_Doc, inner, g: int) -> bool {
	for k := inner; k >= 0; k = doc.groups[k].parent do if k == g do return true
	return false
}

// Vector_PathToCubics turns quadratic segments into the same cubics (and
// lines stay lines): what the node editor works on.
Vector_PathToCubics :: proc(p: ^Vector_Path) {
	k := 0
	last: [2]f32
	for i := 0; i < len(p.cmds); i += 1 {
		#partial switch p.cmds[i] {
		case .Move, .Line:
			last = p.pts[k]
			k += 1
		case .Quad:
			c, b := p.pts[k], p.pts[k + 1]
			p.cmds[i] = .Cubic
			p.pts[k] = last + (c - last) * (2.0 / 3.0)
			inject_at(&p.pts, k + 1, b + (c - b) * (2.0 / 3.0))
			last = b
			k += 3
		case .Cubic:
			last = p.pts[k + 2]
			k += 3
		}
	}
}

// Vector_Anchor: one point of a path the node editor shows - its index in
// pts, and its handles' (-1: none: the segment there is a line, or it's an
// end of an open path).
Vector_Anchor :: struct {
	pt:       int,
	in_, out: int, // pts indices of the handles (cubic control points)
	cmd:      int, // the command that ends at it
	sub:      int, // its subpath (0, 1, ...)
	closes:   bool, // its subpath is closed and this is its first anchor
}

// Vector_PathAnchors lists a path's anchors (after Vector_PathToCubics). A
// closed subpath's last segment that comes back to its start: that point is
// one anchor (the start), with the last segment's handle as its "in".
Vector_PathAnchors :: proc(p: ^Vector_Path, allocator := context.temp_allocator) -> []Vector_Anchor {
	out := make([dynamic]Vector_Anchor, allocator)
	k, sub, start := 0, -1, -1
	for c, ci in p.cmds {
		switch c {
		case .Move:
			sub += 1
			start = len(out)
			append(&out, Vector_Anchor{pt = k, in_ = -1, out = -1, cmd = ci, sub = sub})
			k += 1
		case .Line:
			append(&out, Vector_Anchor{pt = k, in_ = -1, out = -1, cmd = ci, sub = sub})
			k += 1
		case .Quad:
			append(&out, Vector_Anchor{pt = k + 1, in_ = -1, out = -1, cmd = ci, sub = sub})
			k += 2
		case .Cubic:
			if n := len(out); n > 0 do out[n - 1].out = k
			append(&out, Vector_Anchor{pt = k + 2, in_ = k + 1, out = -1, cmd = ci, sub = sub})
			k += 3
		case .Close:
			if start < 0 || start >= len(out) do continue
			out[start].closes = true
			// A last point on top of the start: one anchor, its in-handle the start's.
			n := len(out)
			if n - 1 > start && linalg.distance(p.pts[out[n - 1].pt], p.pts[out[start].pt]) < 1e-3 {
				out[start].in_ = out[n - 1].in_
				pop(&out)
			}
		}
	}
	return out[:]
}

// Vector_PathSplit: a point on segment `cmd` (a line or a cubic) at t
// (de Casteljau: the curve keeps its shape); the new anchor's pts index.
Vector_PathSplit :: proc(p: ^Vector_Path, cmd: int, t: f32) -> int {
	k := 0
	for i in 0 ..< cmd {
		switch p.cmds[i] {
		case .Move, .Line: k += 1
		case .Quad:        k += 2
		case .Cubic:       k += 3
		case .Close:
		}
	}
	prev := p.pts[k - 1] if k > 0 else p.pts[0]
	#partial switch p.cmds[cmd] {
	case .Line:
		b := p.pts[k]
		inject_at(&p.cmds, cmd, Vector_Cmd.Line)
		inject_at(&p.pts, k, prev + (b - prev) * t)
		return k
	case .Cubic:
		a, c1, c2, b := prev, p.pts[k], p.pts[k + 1], p.pts[k + 2]
		ab, bc, cd := linalg.lerp(a, c1, t), linalg.lerp(c1, c2, t), linalg.lerp(c2, b, t)
		abc, bcd := linalg.lerp(ab, bc, t), linalg.lerp(bc, cd, t)
		mid := linalg.lerp(abc, bcd, t)
		p.pts[k], p.pts[k + 1] = ab, abc
		inject_at(&p.pts, k + 2, mid, bcd, cd)
		// (pts: ab abc mid | bcd cd b)
		p.pts[k + 3], p.pts[k + 4] = bcd, cd
		inject_at(&p.cmds, cmd + 1, Vector_Cmd.Cubic)
		return k + 2
	}
	return -1
}

// Vector_SegmentNearest: the segment of `p` nearest to `q` (a line or a
// cubic command index, -1 none), the t on it and the distance.
Vector_SegmentNearest :: proc(p: ^Vector_Path, q: [2]f32) -> (cmd: int, t: f32, dist: f32) {
	cmd, dist = -1, max(f32)
	k := 0
	last, start: [2]f32
	for c, ci in p.cmds {
		switch c {
		case .Move:
			last, start = p.pts[k], p.pts[k]
			k += 1
		case .Line:
			b := p.pts[k]
			tt, d := seg_dist(last, b, q)
			if d < dist do cmd, t, dist = ci, tt, d
			last = b
			k += 1
		case .Quad:
			last = p.pts[k + 1]
			k += 2
		case .Cubic:
			a, c1, c2, b := last, p.pts[k], p.pts[k + 1], p.pts[k + 2]
			STEPS :: 24
			prevPt := a
			for s in 1 ..= STEPS {
				u := f32(s) / STEPS
				pt := cubic_at(a, c1, c2, b, u)
				tt, d := seg_dist(prevPt, pt, q)
				if d < dist do cmd, t, dist = ci, (f32(s - 1) + tt) / STEPS, d
				prevPt = pt
			}
			last = b
			k += 3
		case .Close:
			last = start
		}
	}
	return
}

@(private = "file")
cubic_at :: proc(a, b, c, d: [2]f32, t: f32) -> [2]f32 {
	u := 1 - t
	return a * (u * u * u) + b * (3 * u * u * t) + c * (3 * u * t * t) + d * (t * t * t)
}

@(private = "file")
seg_dist :: proc(a, b, q: [2]f32) -> (t, d: f32) {
	ab := b - a
	l := linalg.dot(ab, ab)
	t = clamp(linalg.dot(q - a, ab) / l, 0, 1) if l > 0 else 0
	return t, linalg.distance(a + ab * t, q)
}

// Vector_PathMove moves every point of a path.
Vector_PathMove :: proc(p: ^Vector_Path, d: [2]f32) {
	for &pt in p.pts do pt += d
}

_ :: math.PI

// --- layers (the document's top-level groups) and draw order ---------------------------

// Vector_DocAddGroup: a new empty group at the end of `parent` (-1: a
// top-level group - a layer); its index.
Vector_DocAddGroup :: proc(doc: ^Vector_Doc, name: string, parent := -1) -> int {
	context.allocator = Vector_EditAllocator(doc)
	at := len(doc.shapes)
	if parent >= 0 && parent < len(doc.groups) do at = doc.groups[parent].first + doc.groups[parent].count
	append(&doc.groups, Vector_Group{name = strings.clone(name), parent = parent, first = at})
	return len(doc.groups) - 1
}

// Vector_DocLayers: the top-level groups, in drawing order (back first).
Vector_DocLayers :: proc(doc: ^Vector_Doc, allocator := context.temp_allocator) -> []int {
	out := make([dynamic]int, allocator)
	for g, i in doc.groups do if g.parent == -1 do append(&out, i)
	// (By where their shapes start; empty ones by when they were made.)
	for i in 1 ..< len(out) {
		for j := i; j > 0 && doc.groups[out[j]].first < doc.groups[out[j - 1]].first; j -= 1 do out[j], out[j - 1] = out[j - 1], out[j]
	}
	return out[:]
}

// Vector_DocMoveLayer swaps a top-level group with the next one up (+1,
// drawn later) or down (-1) - their shapes and groups move together; false
// when there is none that way.
Vector_DocMoveLayer :: proc(doc: ^Vector_Doc, g, dir: int) -> bool {
	if g < 0 || g >= len(doc.groups) || doc.groups[g].parent != -1 do return false
	// The neighbour: the top-level group whose range is right after / before.
	other := -1
	for o, i in doc.groups {
		if o.parent != -1 || i == g do continue
		if dir > 0 && o.first == doc.groups[g].first + doc.groups[g].count && o.count > 0 do other = i
		if dir < 0 && o.first + o.count == doc.groups[g].first && o.count > 0 do other = i
	}
	if other < 0 || doc.groups[g].count == 0 do return false
	lo, hi := g, other
	if dir < 0 do lo, hi = other, g
	a, b := doc.groups[lo], doc.groups[hi] // a's range, then b's: becomes b's, then a's
	context.allocator = Vector_EditAllocator(doc)
	moved := make([]Vector_Shape, a.count + b.count, context.temp_allocator)
	copy(moved, doc.shapes[b.first:b.first + b.count])
	copy(moved[b.count:], doc.shapes[a.first:a.first + a.count])
	copy(doc.shapes[a.first:], moved)
	for &x, i in doc.groups {
		if vector_group_in(doc, i, lo) do x.first += b.count
		else if vector_group_in(doc, i, hi) do x.first -= a.count
	}
	return true
}

// vector_group_in: `g` is `top` or inside it.
@(private = "file")
vector_group_in :: proc(doc: ^Vector_Doc, g, top: int) -> bool {
	for k := g; k >= 0; k = doc.groups[k].parent do if k == top do return true
	return false
}

// Vector_DocMoveShape moves shape `i` one step up (+1: drawn later) or down
// within its group (not past a child group); its new index (i: it can't).
Vector_DocMoveShape :: proc(doc: ^Vector_Doc, i, dir: int) -> int {
	j := i + (1 if dir > 0 else -1)
	if i < 0 || j < 0 || j >= len(doc.shapes) do return i
	if Vector_DocShapeGroup(doc, i) != Vector_DocShapeGroup(doc, j) do return i
	doc.shapes[i], doc.shapes[j] = doc.shapes[j], doc.shapes[i]
	return j
}

// --- symbols ---------------------------------------------------------------------------

// Vector_DocMakeGroup moves shapes into a new group named `name` inside
// `parent` (-1: top level) - a symbol - in their drawing order, after the
// parent's other shapes; the group's index.
Vector_DocMakeGroup :: proc(doc: ^Vector_Doc, indices: []int, name: string, parent := -1) -> int {
	order := make([dynamic]int, 0, len(indices), context.temp_allocator)
	for i in indices do if i >= 0 && i < len(doc.shapes) do append(&order, i)
	for i in 1 ..< len(order) {
		for j := i; j > 0 && order[j] < order[j - 1]; j -= 1 do order[j], order[j - 1] = order[j - 1], order[j]
	}
	moved := make([dynamic]Vector_Shape, 0, len(order), context.temp_allocator)
	for i in order do append(&moved, doc.shapes[i])
	for k := len(order) - 1; k >= 0; k -= 1 do Vector_DocRemoveShape(doc, order[k])
	g := Vector_DocAddGroup(doc, name, parent)
	for s in moved do Vector_DocInsertShape(doc, s, g)
	return g
}

// Vector_DocGroupNameFree: `base`, or base 2, base 3... - a name no group has.
Vector_DocGroupNameFree :: proc(doc: ^Vector_Doc, base: string, allocator := context.temp_allocator) -> string {
	taken :: proc(doc: ^Vector_Doc, n: string) -> bool {
		for g in doc.groups do if g.name == n do return true
		return false
	}
	if !taken(doc, base) do return strings.clone(base, allocator)
	for i := 2; ; i += 1 {
		n := fmt.tprintf("%s %d", base, i)
		if !taken(doc, n) do return strings.clone(n, allocator)
	}
}

// Vector_DocDuplicateGroup copies a group - its shapes and the groups in it
// - as a new group named `name` beside it (same parent, after the parent's
// other shapes); the copy's index.
Vector_DocDuplicateGroup :: proc(doc: ^Vector_Doc, g: int, name: string) -> int {
	if g < 0 || g >= len(doc.groups) do return -1
	context.allocator = Vector_EditAllocator(doc)
	src := doc.groups[g]
	// The groups inside it (parents before children: they're read in order).
	inside := make([dynamic]int, context.temp_allocator)
	for x, i in doc.groups do if i != g && vector_group_in(doc, i, g) do append(&inside, i)
	mapping := make(map[int]int, allocator = context.temp_allocator)
	mapping[g] = Vector_DocAddGroup(doc, name, src.parent)
	for i in inside do mapping[i] = Vector_DocAddGroup(doc, doc.groups[i].name, mapping[doc.groups[i].parent])
	for i in inside do doc.groups[mapping[i]].hidden = doc.groups[i].hidden
	// The shapes, each into its innermost group's copy (in order: ranges come out right).
	shapes := make([dynamic]Vector_Shape, 0, src.count, context.temp_allocator)
	owners := make([dynamic]int, 0, src.count, context.temp_allocator)
	for k in src.first ..< src.first + src.count {
		append(&shapes, Vector_ShapeCopy(&doc.shapes[k]))
		append(&owners, Vector_DocShapeGroup(doc, k))
	}
	for s, k in shapes do Vector_DocInsertShape(doc, s, mapping[owners[k]] if owners[k] in mapping else mapping[g])
	return mapping[g]
}

// Vector_ShapeCopy: a shape with its own path (the document's arena).
Vector_ShapeCopy :: proc(s: ^Vector_Shape) -> Vector_Shape {
	out := s^
	out.path.cmds = make([dynamic]Vector_Cmd, len(s.path.cmds))
	out.path.pts = make([dynamic][2]f32, len(s.path.pts))
	copy(out.path.cmds[:], s.path.cmds[:])
	copy(out.path.pts[:], s.path.pts[:])
	return out
}

// Vector_DocRemoveGroup takes a group out with its shapes and the groups in it.
Vector_DocRemoveGroup :: proc(doc: ^Vector_Doc, g: int) {
	if g < 0 || g >= len(doc.groups) do return
	context.allocator = Vector_EditAllocator(doc)
	src := doc.groups[g]
	for k := src.first + src.count - 1; k >= src.first; k -= 1 do Vector_DocRemoveShape(doc, k)
	gone := make([]bool, len(doc.groups), context.temp_allocator)
	for _, i in doc.groups do gone[i] = vector_group_in(doc, i, g)
	newIndex := make([]int, len(doc.groups), context.temp_allocator)
	n := 0
	for i in 0 ..< len(doc.groups) {
		newIndex[i] = -1 if gone[i] else n
		if !gone[i] do n += 1
	}
	kept := make([dynamic]Vector_Group, 0, n)
	for x, i in doc.groups {
		if gone[i] do continue
		y := x
		if y.parent >= 0 do y.parent = newIndex[y.parent]
		append(&kept, y)
	}
	doc.groups = kept
}
