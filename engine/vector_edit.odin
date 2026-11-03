package engine

import "core:math"
import "core:math/linalg"
import os "osx"
import "core:time"
import "core:mem"
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
// document's end), keeping every group's range right; its index.
Vector_DocInsertShape :: proc(doc: ^Vector_Doc, shape: Vector_Shape, group := -1) -> int {
	context.allocator = Vector_EditAllocator(doc)
	at := len(doc.shapes)
	if group >= 0 && group < len(doc.groups) do at = doc.groups[group].first + doc.groups[group].count
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
