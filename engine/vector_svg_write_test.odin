package engine

import "core:math"
import os "osx"
import "core:path/filepath"
import "core:strings"
import "core:testing"

// #267: every fixture SVG, read, written and read again, gives the same
// shapes (paths, styles, clips), groups and document size - and writing the
// second one gives the same text.
@(test)
test_vector_svg_round_trip :: proc(t: ^testing.T) {
	h, err := os.open("tests/vector/svg")
	if !testing.expect(t, err == nil, "the fixtures") do return
	files, _ := os.read_dir(h, -1, context.temp_allocator)
	os.close(h)
	checked := 0
	for f in files {
		if !strings.has_suffix(f.name, ".svg") do continue
		path, _ := filepath.join({"tests/vector/svg", f.name}, context.temp_allocator)
		text, _ := os.read_entire_file(path, context.temp_allocator)
		a, b: Vector_Doc
		defer Vector_Doc_Destroy(&a)
		defer Vector_Doc_Destroy(&b)
		if !testing.expectf(t, Vector_LoadSVG(string(text), &a), "%s loads", f.name) do continue
		out := Vector_Doc_ToSVG(&a, context.temp_allocator)
		if !testing.expectf(t, Vector_LoadSVG(out, &b), "%s: what was written loads", f.name) do continue
		testing.expectf(t, strings.contains(out, VECTOR_SVG_MARK), "%s: marked", f.name)
		testing.expectf(t, len(a.shapes) == len(b.shapes) && len(a.groups) == len(b.groups), "%s: %d/%d shapes, %d/%d groups", f.name, len(a.shapes), len(b.shapes), len(a.groups), len(b.groups))
		testing.expectf(t, close2(a.size, b.size), "%s: size %v / %v", f.name, a.size, b.size)
		if len(a.shapes) == len(b.shapes) {
			for i in 0 ..< len(a.shapes) {
				sa, sb := &a.shapes[i], &b.shapes[i]
				same := len(sa.path.cmds) == len(sb.path.cmds) && len(sa.path.pts) == len(sb.path.pts)
				if same do for k in 0 ..< len(sa.path.pts) do if !close2(sa.path.pts[k], sb.path.pts[k]) do same = false
				x, y := sa.style, sb.style
				same = same && x.fill == y.fill && x.stroke == y.stroke && (!x.fill || x.fillRule == y.fillRule) && (!x.stroke || (x.join == y.join && x.cap == y.cap)) && x.fillPaint.kind == y.fillPaint.kind && x.strokePaint.kind == y.strokePaint.kind && x.dash.count == y.dash.count && (sa.clip == nil) == (sb.clip == nil)
				same = same && (!x.fill || x.fillPaint.kind != .Solid || colors_close(x.fillColor, y.fillColor)) && (!x.stroke || (colors_close(x.strokeColor, y.strokeColor) || x.strokePaint.kind != .Solid) && abs(x.strokeWidth - y.strokeWidth) < 0.01)
				if !same {
					testing.expectf(t, false, "%s: shape %d differs after writing", f.name, i)
					break
				}
			}
		}
		for g, i in a.groups {
			if i >= len(b.groups) do break
			gb := b.groups[i]
			testing.expectf(t, g.parent == gb.parent && g.first == gb.first && g.count == gb.count && g.hidden == gb.hidden, "%s: group %d (%s)", f.name, i, g.name)
		}
		testing.expectf(t, Vector_Doc_ToSVG(&b, context.temp_allocator) == out, "%s: writing again changes nothing", f.name)
		checked += 1
	}
	testing.expect(t, checked >= 8, "the fixtures were checked")
}

@(private = "file")
close2 :: proc(a, b: [2]f32) -> bool {return abs(a.x - b.x) < 0.01 && abs(a.y - b.y) < 0.01}

@(private = "file")
colors_close :: proc(a, b: [4]u8) -> bool {
	for i in 0 ..< 4 do if math.abs(int(a[i]) - int(b[i])) > 1 do return false
	return true
}
