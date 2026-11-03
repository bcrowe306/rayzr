package engine

import "core:math/linalg"
import "core:testing"

// #267: the node editor's path operations and shape insertion keep the
// drawing and the groups right.
@(test)
test_vector_edit_paths :: proc(t: ^testing.T) {
	SVG :: `<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><g id="a"><path d="M0 0 Q50 0 50 50 L0 50 Z"/><g id="b"><path d="M10 10 L20 10"/></g></g><path d="M0 90 C10 80 20 80 30 90"/></svg>`
	doc: Vector_Doc
	defer Vector_Doc_Destroy(&doc)
	testing.expect(t, Vector_LoadSVG(SVG, &doc), "loads")
	testing.expect_value(t, len(doc.shapes), 3)

	// Quadratic -> cubic: the same curve (its midpoint stays).
	p := &doc.shapes[0].path
	{
		context.allocator = Vector_EditAllocator(&doc)
		Vector_PathToCubics(p)
	}
	testing.expect(t, p.cmds[1] == .Cubic, "the quad is a cubic")
	anchors := Vector_PathAnchors(p)
	testing.expectf(t, len(anchors) == 3 && anchors[0].closes && anchors[1].in_ >= 0 && anchors[0].out >= 0, "anchors: %v", anchors)

	// Splitting a cubic keeps its shape: the new anchor is on the old curve.
	c := &doc.shapes[2].path
	before := c.pts[:]
	a0, c1, c2, b := [2]f32{0, 90}, before[1], before[2], before[3]
	{
		context.allocator = Vector_EditAllocator(&doc)
		k := Vector_PathSplit(c, 1, 0.5)
		want := a0 * 0.125 + c1 * 0.375 + c2 * 0.375 + b * 0.125
		testing.expectf(t, linalg.distance(c.pts[k], want) < 1e-3 && len(c.cmds) == 3, "split at the curve: %v / %v", c.pts[k], want)
	}
	cmd, _, d := Vector_SegmentNearest(c, {15, 82.5})
	testing.expect(t, cmd >= 1 && d < 1, "the nearest segment")

	// Inserting into group b grows b and a; the shape after them moves on.
	shape: Vector_Shape
	{
		context.allocator = Vector_EditAllocator(&doc)
		Vector_Path_Init(&shape.path)
		Vector_MoveTo(&shape.path, {1, 1})
		Vector_LineTo(&shape.path, {2, 2})
	}
	gb := -1
	for g, i in doc.groups do if g.name == "b" do gb = i
	at := Vector_DocInsertShape(&doc, shape, gb)
	ga := doc.groups[doc.groups[gb].parent]
	testing.expectf(t, at == 2 && doc.groups[gb].count == 2 && ga.count == 3, "insert: at %d, b %v, a %v", at, doc.groups[gb], ga)
	testing.expect_value(t, Vector_DocShapeGroup(&doc, at), gb)
	Vector_DocRemoveShape(&doc, at)
	testing.expect(t, doc.groups[gb].count == 1 && doc.groups[doc.groups[gb].parent].count == 2 && len(doc.shapes) == 3, "removed again")
}

// #267 part 4: layers (top-level groups) reorder with their shapes and
// child groups; shapes step forward / back within their group only.
@(test)
test_vector_edit_layers :: proc(t: ^testing.T) {
	SVG :: `<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><g id="back"><path d="M0 0 L1 0"/><g id="inner"><path d="M1 1 L2 1"/></g></g><g id="front"><path d="M5 5 L6 5"/><path d="M7 7 L8 7"/></g></svg>`
	doc: Vector_Doc
	defer Vector_Doc_Destroy(&doc)
	testing.expect(t, Vector_LoadSVG(SVG, &doc), "loads")
	find :: proc(doc: ^Vector_Doc, name: string) -> int {
		for g, i in doc.groups do if g.name == name do return i
		return -1
	}
	back, inner, front := find(&doc, "back"), find(&doc, "inner"), find(&doc, "front")
	layers := Vector_DocLayers(&doc)
	testing.expect(t, len(layers) == 2 && layers[0] == back && layers[1] == front, "two layers, back first")
	testing.expect(t, Vector_DocMoveLayer(&doc, back, 1), "back moves up")
	testing.expectf(t, doc.groups[front].first == 0 && doc.groups[back].first == 2 && doc.groups[inner].first == 3, "ranges follow: %v", doc.groups[:])
	testing.expect(t, doc.shapes[0].path.pts[0] == {5, 5} && doc.shapes[3].path.pts[0] == {1, 1}, "shapes follow")
	testing.expect(t, !Vector_DocMoveLayer(&doc, back, 1), "nothing above")
	// Draw order: the two front shapes swap; not across into another group.
	testing.expect_value(t, Vector_DocMoveShape(&doc, 0, 1), 1)
	testing.expect(t, doc.shapes[0].path.pts[0] == {7, 7}, "swapped")
	testing.expect_value(t, Vector_DocMoveShape(&doc, 1, 1), 1) // (the next is in 'back')
	added := Vector_DocAddGroup(&doc, "new")
	testing.expect(t, doc.groups[added].parent == -1 && doc.groups[added].count == 0 && len(Vector_DocLayers(&doc)) == 3, "a new layer")
	at := Vector_DocInsertShape(&doc, doc.shapes[0], added)
	testing.expect(t, at == len(doc.shapes) - 1 && doc.groups[added].count == 1, "a shape into it")
}
