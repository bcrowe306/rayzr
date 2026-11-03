package editor

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"
import rl "vendor:raylib"

// ============================================================================
// Drawing vector art in the viewport (#267): an edit mode on a Vector Shape -
// double-click it (or Inspector > Edit Art); the rest of the scene is dimmed
// and the Vector toolbar shows. Edits go into the SVG the node draws
// (engine/vector_svg_write.odin), saved after each one (Ctrl+Z undoes it).
//
//   Select (V)  click a shape to select it, drag to move it, Delete removes it
//   Node   (A)  a shape's anchors and handles: drag them (a handle bends
//               the curve; its partner follows - Alt: only this one);
//               double-click a segment: an anchor there; Alt+click an
//               anchor: removed; right-click: Smooth / Corner / Symmetric
//   Pen    (P)  click: a corner, click-drag: a smooth anchor; click the
//               first anchor to close (closed shapes get the fill colour);
//               Enter / Esc / double-click ends an open path
//   Esc / Done  leaves the mode
//
// A file the importer couldn't read all of (text, images, filters...) asks
// first: edit a copy (<name>_edit.svg) or overwrite it (what it can't draw
// is dropped). The first save of a file keeps <file>.bak. A Vector Shape
// with no file gets art/<node name>.svg with the first pen click.
// ============================================================================

Vector_Tool :: enum {
	Select,
	Node,
	Pen,
}

@(private = "file")
Vd_Drag :: enum {
	None,
	Shape,
	Anchor,
	In,
	Out,
	Pen,
}

@(private = "file")
vd: struct {
	active:   bool,
	node:     ^e.VectorShapeNode,
	tool:     Vector_Tool,
	shape:    int, // selected shape (-1)
	anchor:   int, // selected anchor of it (-1)
	drag:     Vd_Drag,
	last:     [2]f32, // the mouse (document units) at the drag's previous frame
	moved:    bool,   // the drag changed the document (saved when it ends)
	offset:   [2]f32, // document -> node, frozen while dragging
	penShape: int,    // the path the pen is drawing (-1)
	penOut:   [2]f32, // the pen's last anchor's out-handle (offset)
	fill:     [4]u8,
	stroke:   [4]u8,
	width:    f32,
	backedUp: map[string]bool, // files whose .bak was written this session
	askFor:   ^e.VectorShapeNode, // the lossy-file question is open for it
	menu:     int, // the anchor the right-click menu is for
}

VectorDraw_IsActive :: proc(state: ^EditorState) -> bool {
	if !vd.active do return false
	if vd.node == nil || state.selectedNode != &vd.node.node || !e.Node_IsAlive(&vd.node.node) {
		vectordraw_exit(state)
		return false
	}
	return true
}

VectorDraw_Node :: proc() -> ^e.VectorShapeNode {return vd.node if vd.active else nil}

// VectorDraw_Enter starts editing a Vector Shape's art (asks first for a
// file it would lose parts of).
VectorDraw_Enter :: proc(state: ^EditorState, v: ^e.VectorShapeNode) {
	if v == nil do return
	if r := e.VectorShapeNode_Asset(v); r != nil && len(r.doc.warnings) > 0 && !vectordraw_is_ours(r) {
		vd.askFor = v
		return
	}
	vectordraw_start(state, v)
}

@(private = "file")
vectordraw_start :: proc(state: ^EditorState, v: ^e.VectorShapeNode) {
	if vd.fill == {} do vd.fill, vd.stroke, vd.width = {255, 255, 255, 255}, {20, 20, 20, 255}, 2
	vd.active, vd.node, vd.shape, vd.anchor, vd.drag, vd.penShape = true, v, -1, -1, .None, -1
	if vd.backedUp == nil do vd.backedUp = make(map[string]bool)
	Editor_Log(state, .Info, "Drawing in %s: V select, A nodes, P pen; Esc when done", v.name)
}

VectorDraw_Exit :: proc(state: ^EditorState) {vectordraw_exit(state)}

@(private = "file")
vectordraw_exit :: proc(state: ^EditorState) {
	if vd.active && vd.node != nil && e.Node_IsAlive(&vd.node.node) do pen_finish(state)
	vd.active, vd.node, vd.drag, vd.penShape = false, nil, .None, -1
}

@(private = "file")
vectordraw_is_ours :: proc(r: ^e.Vector_Resource) -> bool {
	data, err := os.read_entire_file(r.path, context.temp_allocator)
	return err == nil && strings.contains(string(data), e.VECTOR_SVG_MARK)
}

// --- coordinates -------------------------------------------------------------

@(private = "file")
vd_offset :: proc(v: ^e.VectorShapeNode) -> [2]f32 {
	r := e.VectorShapeNode_Asset(v)
	if r == nil do return {}
	_, boxMin, boxSize, ok := e.VectorShapeNode_Part(v, r)
	if !ok do return {}
	return -boxMin - e.Node_OriginPx(v, boxSize)
}

@(private = "file")
doc_to_world :: proc(v: ^e.VectorShapeNode, d: [2]f32) -> [2]f32 {
	l := (d + vd.offset) * v.globalScale
	a := v.globalRotation * math.RAD_PER_DEG
	c, s := math.cos(a), math.sin(a)
	return v.globalPosition + {l.x * c - l.y * s, l.x * s + l.y * c}
}

@(private = "file")
world_to_doc :: proc(v: ^e.VectorShapeNode, w: [2]f32) -> [2]f32 {
	d := w - v.globalPosition
	a := -v.globalRotation * math.RAD_PER_DEG
	c, s := math.cos(a), math.sin(a)
	l := [2]f32{d.x * c - d.y * s, d.x * s + d.y * c}
	sc := v.globalScale
	if sc.x == 0 do sc.x = 1
	if sc.y == 0 do sc.y = 1
	return l / sc - vd.offset
}

@(private = "file")
doc_to_screen :: proc(state: ^EditorState, v: ^e.VectorShapeNode, d: [2]f32) -> [2]f32 {
	return Viewport_WorldToScreen(state, doc_to_world(v, d))
}

// Screen pixels in document units (for hit distances).
@(private = "file")
doc_per_px :: proc(state: ^EditorState, v: ^e.VectorShapeNode) -> f32 {
	s := max(abs(v.globalScale.x), abs(v.globalScale.y), 0.0001) * max(state.cameraZoom, 0.0001)
	return 1 / s
}

// --- the dimmed scene (world space, after the scene draws) --------------------

// Viewport_DrawVectorEditFocus dims everything but the node being drawn in.
Viewport_DrawVectorEditFocus :: proc(state: ^EditorState, view: rl.Rectangle) {
	if !VectorDraw_IsActive(state) do return
	rl.DrawRectangleRec(view, {16, 18, 24, 150})
	if state.game != nil do e.VectorShapeNode_Render(&vd.node.node, &state.game.gameContext, 0)
}

// --- the viewport ------------------------------------------------------------

// Viewport_VectorDraw: the edit mode's tools (owns the mouse while active).
Viewport_VectorDraw :: proc(state: ^EditorState, dl: ^imgui.DrawList, mouseScreen, mouseWorld: [2]f32) -> bool {
	vectordraw_ask(state)
	if !VectorDraw_IsActive(state) do return false
	v := vd.node
	io := imgui.GetIO()
	if vd.drag == .None do vd.offset = vd_offset(v)
	mouse := world_to_doc(v, mouseWorld)
	tol := 6 * doc_per_px(state, v)
	vectordraw_toolbar(state)
	r := e.VectorShapeNode_Asset(v)
	if r != nil {
		if vd.shape >= len(r.doc.shapes) do vd.shape, vd.anchor = -1, -1
		if vd.penShape >= len(r.doc.shapes) do vd.penShape = -1
	}

	// Keys.
	if !io.WantTextInput && (state.viewportHovered || imgui.IsWindowFocused()) {
		if imgui.IsKeyPressed(.V, false) do vectordraw_set_tool(state, .Select)
		if imgui.IsKeyPressed(.A, false) && !io.KeyCtrl && !io.KeySuper do vectordraw_set_tool(state, .Node)
		if imgui.IsKeyPressed(.P, false) do vectordraw_set_tool(state, .Pen)
		if imgui.IsKeyPressed(.Escape, false) || imgui.IsKeyPressed(.Enter, false) {
			if vd.penShape >= 0 do pen_finish(state)
			else if imgui.IsKeyPressed(.Escape, false) {vectordraw_exit(state); return true}
		}
		if (imgui.IsKeyPressed(.Delete, false) || imgui.IsKeyPressed(.Backspace, false)) && r != nil && vd.shape >= 0 && vd.penShape < 0 {
			if vd.tool == .Node && vd.anchor >= 0 do anchor_delete(state, r, vd.shape, vd.anchor)
			else {
				edit_begin(r)
				e.Vector_DocRemoveShape(&r.doc, vd.shape)
				vd.shape, vd.anchor = -1, -1
				edit_commit(state, r, "Delete shape")
			}
		}
	}

	// Every shape faintly; the selected one bright, with its anchors in Node mode.
	if r != nil {
		for &s, i in r.doc.shapes do draw_path_outline(state, dl, v, &s.path, col_u32(UI_ACCENT if i == vd.shape else ui_line(0.35)), 2 if i == vd.shape else 1)
	}
	Drive_ItemRect("vd.canvas", state.viewportPos, state.viewportPos + state.viewportSize, inWindow = true)

	switch vd.tool {
	case .Select: tool_select(state, dl, r, mouse, tol)
	case .Node:   tool_node(state, dl, r, mouse, tol)
	case .Pen:    tool_pen(state, dl, r, mouse, tol)
	}
	anchor_menu(state, r)
	return true
}

@(private = "file")
vectordraw_set_tool :: proc(state: ^EditorState, t: Vector_Tool) {
	if vd.tool == .Pen && t != .Pen do pen_finish(state)
	vd.tool = t
}

@(private = "file")
vectordraw_toolbar :: proc(state: ^EditorState) {
	imgui.SetCursorScreenPos(state.viewportPos + {10, 10})
	imgui.BeginGroup()
	tools := [3]struct {t: Vector_Tool, icon, id, tip: string}{
		{.Select, ICON_FA_ARROW_POINTER, "vd.tool:select", "Select (V): click a shape, drag to move it"},
		{.Node, ICON_FA_BEZIER_CURVE, "vd.tool:node", "Nodes (A): drag anchors and handles; double-click a segment to add one"},
		{.Pen, ICON_FA_PEN, "vd.tool:pen", "Pen (P): click for corners, drag for curves; click the first point to close"},
	}
	for t, i in tools {
		if i > 0 do imgui.SameLine(0, 4)
		if UI_IconButton(t.icon, t.id, t.tip, vd.tool == t.t, 28) do vectordraw_set_tool(state, t.t)
	}
	imgui.SameLine(0, 12)
	colour :: proc(label, id: cstring, c: ^[4]u8, tip: string) {
		f := [4]f32{f32(c[0]) / 255, f32(c[1]) / 255, f32(c[2]) / 255, f32(c[3]) / 255}
		if imgui.ColorEdit4(label, &f, {.NoInputs, .AlphaBar}) do c^ = {u8(f[0] * 255 + 0.5), u8(f[1] * 255 + 0.5), u8(f[2] * 255 + 0.5), u8(f[3] * 255 + 0.5)}
		Drive_Item(string(id))
		UI_Tooltip(tip)
	}
	colour("##vdfill", "vd.fill", &vd.fill, "Fill colour of new closed shapes")
	imgui.SameLine(0, 4)
	colour("##vdstroke", "vd.stroke", &vd.stroke, "Line colour of new shapes")
	imgui.SameLine(0, 4)
	imgui.SetNextItemWidth(60)
	imgui.DragFloat("##vdwidth", &vd.width, 0.1, 0, 64, "%.1f px")
	Drive_Item("vd.width")
	UI_Tooltip("Line width of new shapes")
	imgui.SameLine(0, 12)
	if UI_Button(fmt.tprintf("%s  Done", ICON_FA_CHECK), "vd.done") do vectordraw_exit(state)
	UI_Tooltip("Stop drawing (Esc)")
	imgui.EndGroup()
}

// --- editing and saving ---------------------------------------------------------

@(private = "file")
edit_begin :: proc(r: ^e.Vector_Resource) {e.Vector_ResourceEditBegin(r)}

// edit_commit: the document changed - rebuilt and saved to its file.
@(private = "file")
edit_commit :: proc(state: ^EditorState, r: ^e.Vector_Resource, label: string) {
	e.Vector_ResourceEdited(r)
	vectordraw_save(state, r, label)
}

@(private = "file")
vectordraw_save :: proc(state: ^EditorState, r: ^e.Vector_Resource, label: string) {
	v := vd.node
	rel := v.file
	if rel == "" do return
	full := r.path
	if rel not_in vd.backedUp && os.is_file(full) {
		bak := strings.concatenate({full, ".bak"}, context.temp_allocator)
		if !os.is_file(bak) do _ = os.copy_file(bak, full)
		vd.backedUp[strings.clone(rel)] = true
	}
	Editor_RecordFileUndo(state, rel, label)
	// (Import settings may scale the art: the file keeps its own units.)
	scale: f32 = 1
	if imp := e.Asset_ImportGet(&state.game.resourceManager, full); imp.vectorScale > 0 do scale = imp.vectorScale
	if scale != 1 do e.Vector_DocScale(&r.doc, 1 / scale)
	text := e.Vector_Doc_ToSVG(&r.doc, context.temp_allocator)
	if scale != 1 do e.Vector_DocScale(&r.doc, scale)
	if err := os.write_entire_file(full, transmute([]u8)text); err != nil {
		Editor_Log(state, .Error, "Could not save %s: %v", rel, err)
		return
	}
	e.Vector_ResourceSaved(r)
	Editor_InvalidateProjectFiles()
}

// vectordraw_new_file: an empty Vector Shape's art/<name>.svg (made at the
// first pen click), loaded.
@(private = "file")
vectordraw_new_file :: proc(state: ^EditorState, v: ^e.VectorShapeNode) -> ^e.Vector_Resource {
	base := strings.to_lower(strings.trim_space(v.name), context.temp_allocator)
	if base == "" do base = "vector"
	rel := fmt.tprintf("art/%s.svg", base)
	for n := 2; project_file_exists(state, rel); n += 1 do rel = fmt.tprintf("art/%s_%d.svg", base, n)
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	_ = os.make_directory_all(filepath.dir(full, context.temp_allocator))
	SIZE :: 512
	text := fmt.tprintf("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\">\n%s\n</svg>\n", SIZE, SIZE, SIZE, SIZE, e.VECTOR_SVG_MARK)
	if os.write_entire_file(full, transmute([]u8)text) != nil {
		Editor_Log(state, .Error, "Could not create %s", rel)
		return nil
	}
	Editor_RecordUndo(state, "Draw new vector art")
	v.file = strings.clone(rel, v.allocator)
	Editor_InvalidateProjectFiles()
	vd.backedUp[strings.clone(rel)] = true // (new: nothing to back up)
	Editor_Log(state, .Info, "Drawing into %s", rel)
	r := e.VectorShapeNode_Asset(v)
	vd.offset = vd_offset(v)
	return r
}

@(private = "file")
project_file_exists :: proc(state: ^EditorState, rel: string) -> bool {
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	return os.exists(full)
}

// --- Select --------------------------------------------------------------------

@(private = "file")
tool_select :: proc(state: ^EditorState, dl: ^imgui.DrawList, r: ^e.Vector_Resource, mouse: [2]f32, tol: f32) {
	if r == nil || !state.viewportHovered && vd.drag == .None do return
	if imgui.IsMouseClicked(.Left) {
		vd.shape = shape_at(r, mouse, tol)
		vd.anchor = -1
		if vd.shape >= 0 {
			vd.drag, vd.last, vd.moved = .Shape, mouse, false
			edit_begin(r)
		}
	}
	if vd.drag == .Shape {
		if imgui.IsMouseDown(.Left) {
			if d := mouse - vd.last; d != {} {
				e.Vector_PathMove(&r.doc.shapes[vd.shape].path, d)
				e.Vector_ResourceEdited(r)
				vd.moved = true
			}
			vd.last = mouse
		} else {
			if vd.moved do vectordraw_save(state, r, "Move shape")
			vd.drag = .None
		}
	}
}

// shape_at: the topmost shape under a document point (its fill, or near its line).
@(private = "file")
shape_at :: proc(r: ^e.Vector_Resource, q: [2]f32, tol: f32) -> int {
	for i := len(r.doc.shapes) - 1; i >= 0; i -= 1 {
		s := &r.doc.shapes[i]
		if s.style.fill && path_contains(&s.path, q) do return i
		_, _, d := e.Vector_SegmentNearest(&s.path, q)
		if d <= tol + (s.style.strokeWidth * 0.5 if s.style.stroke else 0) do return i
	}
	return -1
}

// path_contains: even-odd point-in-path over the path flattened.
@(private = "file")
path_contains :: proc(p: ^e.Vector_Path, q: [2]f32) -> bool {
	pts := flatten(p)
	inside := false
	for poly in pts {
		n := len(poly)
		for i, j := 0, n - 1; i < n; j, i = i, i + 1 {
			a, b := poly[i], poly[j]
			if (a.y > q.y) != (b.y > q.y) && q.x < (b.x - a.x) * (q.y - a.y) / (b.y - a.y) + a.x do inside = !inside
		}
	}
	return inside
}

// flatten: a path as polylines, one per subpath (curves sampled).
@(private = "file")
flatten :: proc(p: ^e.Vector_Path) -> [][][2]f32 {
	out := make([dynamic][][2]f32, context.temp_allocator)
	cur := make([dynamic][2]f32, context.temp_allocator)
	k := 0
	last: [2]f32
	flush :: proc(out: ^[dynamic][][2]f32, cur: ^[dynamic][2]f32) {
		if len(cur) > 1 do append(out, cur[:])
		cur^ = make([dynamic][2]f32, context.temp_allocator)
	}
	for c in p.cmds {
		switch c {
		case .Move:
			flush(&out, &cur)
			last = p.pts[k]; k += 1
			append(&cur, last)
		case .Line:
			last = p.pts[k]; k += 1
			append(&cur, last)
		case .Quad:
			a, c1, b := last, p.pts[k], p.pts[k + 1]
			for s in 1 ..= 12 {
				t := f32(s) / 12
				append(&cur, a * (1 - t) * (1 - t) + c1 * 2 * (1 - t) * t + b * t * t)
			}
			last = b; k += 2
		case .Cubic:
			a, c1, c2, b := last, p.pts[k], p.pts[k + 1], p.pts[k + 2]
			for s in 1 ..= 16 {
				t := f32(s) / 16
				u := 1 - t
				append(&cur, a * (u * u * u) + c1 * (3 * u * u * t) + c2 * (3 * u * t * t) + b * (t * t * t))
			}
			last = b; k += 3
		case .Close:
		}
	}
	flush(&out, &cur)
	return out[:]
}

@(private = "file")
draw_path_outline :: proc(state: ^EditorState, dl: ^imgui.DrawList, v: ^e.VectorShapeNode, p: ^e.Vector_Path, col: u32, thick: f32) {
	for poly in flatten(p) {
		for i in 1 ..< len(poly) do imgui.DrawList_AddLine(dl, doc_to_screen(state, v, poly[i - 1]), doc_to_screen(state, v, poly[i]), col, thick)
	}
}

// --- Node ------------------------------------------------------------------------

@(private = "file")
tool_node :: proc(state: ^EditorState, dl: ^imgui.DrawList, r: ^e.Vector_Resource, mouse: [2]f32, tol: f32) {
	if r == nil do return
	v := vd.node
	io := imgui.GetIO()
	// What's under the mouse: an anchor / handle of the selected shape.
	hoverA, hoverKind := -1, Vd_Drag.None
	if vd.shape >= 0 {
		p := &r.doc.shapes[vd.shape].path
		{
			context.allocator = e.Vector_EditAllocator(&r.doc)
			if has_quads(p) {
				edit_begin(r)
				e.Vector_PathToCubics(p)
			}
		}
		anchors := e.Vector_PathAnchors(p)
		best := tol * 1.5
		accent := col_u32(UI_ACCENT)
		for a, i in anchors {
			at := doc_to_screen(state, v, p.pts[a.pt])
			for h, k in ([2]int{a.in_, a.out}) {
				if h < 0 || (i != vd.anchor && linalg.distance(p.pts[h], p.pts[a.pt]) < 1e-3) do continue
				hs := doc_to_screen(state, v, p.pts[h])
				imgui.DrawList_AddLine(dl, at, hs, col_u32(ui_line(0.5)), 1)
				imgui.DrawList_AddCircleFilled(dl, hs, 4, col_u32({1, 1, 1, 1}))
				imgui.DrawList_AddCircle(dl, hs, 4, accent)
				Drive_ItemRect(fmt.tprintf("vd.%s:%d", "in" if k == 0 else "out", i), hs - {5, 5}, hs + {5, 5}, inWindow = true)
				if d := linalg.distance(p.pts[h], mouse); d < best do best, hoverA, hoverKind = d, i, .In if k == 0 else .Out
			}
		}
		for a, i in anchors {
			at := doc_to_screen(state, v, p.pts[a.pt])
			imgui.DrawList_AddRectFilled(dl, at - 4.5, at + 4.5, accent if i == vd.anchor else col_u32({1, 1, 1, 1}))
			imgui.DrawList_AddRect(dl, at - 4.5, at + 4.5, accent)
			Drive_ItemRect(fmt.tprintf("vd.anchor:%d", i), at - {6, 6}, at + {6, 6}, inWindow = true)
			if d := linalg.distance(p.pts[a.pt], mouse); d < best do best, hoverA, hoverKind = d, i, .Anchor
		}
		// Each segment's middle (drives double-click there).
		for c, ci in p.cmds {
			if c != .Line && c != .Cubic do continue
			mid := segment_mid(p, ci)
			s := doc_to_screen(state, v, mid)
			Drive_ItemRect(fmt.tprintf("vd.seg:%d", ci), s - {4, 4}, s + {4, 4}, inWindow = true)
		}
	}
	if hoverKind != .None do imgui.SetMouseCursor(.Hand)
	if !state.viewportHovered && vd.drag == .None do return

	if imgui.IsMouseClicked(.Right) && hoverKind == .Anchor {
		vd.anchor, vd.menu = hoverA, hoverA
		imgui.OpenPopup("##vd_anchor_menu")
	}
	if imgui.IsMouseDoubleClicked(.Left) && vd.shape >= 0 && hoverKind == .None {
		p := &r.doc.shapes[vd.shape].path
		if cmd, t, d := e.Vector_SegmentNearest(p, mouse); cmd >= 0 && d <= tol * 1.5 {
			edit_begin(r)
			{
				context.allocator = e.Vector_EditAllocator(&r.doc)
				e.Vector_PathSplit(p, cmd, t)
			}
			edit_commit(state, r, "Add anchor")
			return
		}
	}
	if imgui.IsMouseClicked(.Left) {
		switch {
		case hoverKind == .Anchor && io.KeyAlt:
			anchor_delete(state, r, vd.shape, hoverA)
		case hoverKind != .None:
			vd.anchor, vd.drag, vd.last, vd.moved = hoverA, hoverKind, mouse, false
			edit_begin(r)
		case:
			vd.shape = shape_at(r, mouse, tol)
			vd.anchor = -1
		}
	}
	if vd.drag == .Anchor || vd.drag == .In || vd.drag == .Out {
		if imgui.IsMouseDown(.Left) && vd.shape >= 0 {
			if d := mouse - vd.last; d != {} {
				p := &r.doc.shapes[vd.shape].path
				anchors := e.Vector_PathAnchors(p)
				if vd.anchor < len(anchors) {
					a := anchors[vd.anchor]
					switch vd.drag {
					case .Anchor:
						p.pts[a.pt] += d
						if a.in_ >= 0 do p.pts[a.in_] += d
						if a.out >= 0 do p.pts[a.out] += d
						move_closing_point(p, a, d)
					case .In, .Out:
						h, other := a.in_, a.out
						if vd.drag == .Out do h, other = a.out, a.in_
						if h >= 0 {
							p.pts[h] += d
							// Its partner turns with it (smooth), unless Alt (corner).
							if other >= 0 && !io.KeyAlt {
								dir := p.pts[h] - p.pts[a.pt]
								if l := linalg.length(dir); l > 1e-4 {
									keep := linalg.distance(p.pts[other], p.pts[a.pt])
									if keep < 1e-4 do keep = l
									p.pts[other] = p.pts[a.pt] - dir / l * keep
								}
							}
						}
					case .None, .Shape, .Pen:
					}
					e.Vector_ResourceEdited(r)
					vd.moved = true
				}
			}
			vd.last = mouse
		} else {
			if vd.moved do vectordraw_save(state, r, "Edit anchor")
			vd.drag = .None
		}
	}
}

// move_closing_point: a closed subpath drawn back to its start has that
// point twice: dragging the start moves both.
@(private = "file")
move_closing_point :: proc(p: ^e.Vector_Path, a: e.Vector_Anchor, d: [2]f32) {
	if !a.closes do return
	// The last point of the subpath, before its Close.
	k, sub := 0, -1
	lastPt := -1
	for c in p.cmds {
		switch c {
		case .Move:  sub += 1; if sub == a.sub do lastPt = k; k += 1
		case .Line:  if sub == a.sub do lastPt = k; k += 1
		case .Quad:  if sub == a.sub do lastPt = k + 1; k += 2
		case .Cubic: if sub == a.sub do lastPt = k + 2; k += 3
		case .Close:
		}
	}
	if lastPt >= 0 && lastPt != a.pt && linalg.distance(p.pts[lastPt], p.pts[a.pt] - d) < 1e-3 do p.pts[lastPt] += d
}

@(private = "file")
has_quads :: proc(p: ^e.Vector_Path) -> bool {
	for c in p.cmds do if c == .Quad do return true
	return false
}

@(private = "file")
segment_mid :: proc(p: ^e.Vector_Path, cmd: int) -> [2]f32 {
	k := 0
	for i in 0 ..< cmd {
		switch p.cmds[i] {
		case .Move, .Line: k += 1
		case .Quad:        k += 2
		case .Cubic:       k += 3
		case .Close:
		}
	}
	a := p.pts[k - 1] if k > 0 else p.pts[0]
	if p.cmds[cmd] == .Line do return (a + p.pts[k]) * 0.5
	return a * 0.125 + p.pts[k] * 0.375 + p.pts[k + 1] * 0.375 + p.pts[k + 2] * 0.125
}

// anchor_delete removes an anchor (its segment; a subpath's first anchor
// passes the start to the next one). A shape left with one point goes.
@(private = "file")
anchor_delete :: proc(state: ^EditorState, r: ^e.Vector_Resource, shape, ai: int) {
	if shape < 0 do return
	p := &r.doc.shapes[shape].path
	anchors := e.Vector_PathAnchors(p)
	if ai < 0 || ai >= len(anchors) do return
	a := anchors[ai]
	edit_begin(r)
	k := 0
	for i in 0 ..< a.cmd {
		switch p.cmds[i] {
		case .Move, .Line: k += 1
		case .Quad:        k += 2
		case .Cubic:       k += 3
		case .Close:
		}
	}
	switch p.cmds[a.cmd] {
	case .Move:
		// The next segment's end becomes the start.
		if a.cmd + 1 < len(p.cmds) && p.cmds[a.cmd + 1] != .Move && p.cmds[a.cmd + 1] != .Close {
			next := p.cmds[a.cmd + 1]
			drop := 1 if next == .Line else (3 if next == .Cubic else 2)
			remove_range(&p.pts, k, k + drop)
			ordered_remove(&p.cmds, a.cmd + 1)
		}
	case .Line:
		ordered_remove(&p.pts, k)
		ordered_remove(&p.cmds, a.cmd)
	case .Quad:
		remove_range(&p.pts, k, k + 2)
		ordered_remove(&p.cmds, a.cmd)
	case .Cubic:
		remove_range(&p.pts, k, k + 3)
		ordered_remove(&p.cmds, a.cmd)
	case .Close:
	}
	vd.anchor = -1
	if len(p.pts) < 2 {
		e.Vector_DocRemoveShape(&r.doc, shape)
		vd.shape = -1
	}
	edit_commit(state, r, "Delete anchor")
}

// anchor_menu: right-click on an anchor - its kind.
@(private = "file")
anchor_menu :: proc(state: ^EditorState, r: ^e.Vector_Resource) {
	if !imgui.BeginPopup("##vd_anchor_menu") do return
	defer imgui.EndPopup()
	if r == nil || vd.shape < 0 do return
	p := &r.doc.shapes[vd.shape].path
	anchors := e.Vector_PathAnchors(p)
	if vd.menu < 0 || vd.menu >= len(anchors) do return
	a := anchors[vd.menu]
	kind := -1
	if imgui.MenuItem("Smooth") do kind = 0
	Drive_Item("ctx:vd-smooth")
	if imgui.MenuItem("Symmetric") do kind = 1
	Drive_Item("ctx:vd-symmetric")
	if imgui.MenuItem("Corner") do kind = 2
	Drive_Item("ctx:vd-corner")
	if kind < 0 do return
	edit_begin(r)
	at := p.pts[a.pt]
	switch kind {
	case 0, 1:
		if a.in_ >= 0 && a.out >= 0 {
			dir := (p.pts[a.out] - at) - (p.pts[a.in_] - at)
			if linalg.length(dir) < 1e-4 do dir = {1, 0}
			dir = linalg.normalize(dir)
			li, lo := linalg.distance(p.pts[a.in_], at), linalg.distance(p.pts[a.out], at)
			if kind == 1 || li < 1e-3 || lo < 1e-3 do li, lo = max((li + lo) * 0.5, 10), max((li + lo) * 0.5, 10)
			p.pts[a.in_], p.pts[a.out] = at - dir * li, at + dir * lo
		}
	case 2:
		if a.in_ >= 0 do p.pts[a.in_] = at
		if a.out >= 0 do p.pts[a.out] = at
	}
	edit_commit(state, r, "Anchor kind")
}

// --- Pen -------------------------------------------------------------------------

@(private = "file")
tool_pen :: proc(state: ^EditorState, dl: ^imgui.DrawList, r: ^e.Vector_Resource, mouse: [2]f32, tol: f32) {
	v := vd.node
	res := r
	// The path being drawn: its anchors, and a rubber band to the mouse.
	if res != nil && vd.penShape >= 0 {
		p := &res.doc.shapes[vd.penShape].path
		for a, i in e.Vector_PathAnchors(p) {
			at := doc_to_screen(state, v, p.pts[a.pt])
			imgui.DrawList_AddRectFilled(dl, at - 4, at + 4, col_u32(UI_ACCENT if i == 0 else {1, 1, 1, 1}))
			Drive_ItemRect(fmt.tprintf("vd.anchor:%d", i), at - {6, 6}, at + {6, 6}, inWindow = true)
		}
		if vd.drag == .None && state.viewportHovered && len(p.pts) > 0 {
			imgui.DrawList_AddLine(dl, doc_to_screen(state, v, p.pts[len(p.pts) - 1]), doc_to_screen(state, v, mouse), col_u32(ui_line(0.6)), 1)
		}
	}
	if !state.viewportHovered && vd.drag == .None do return
	imgui.SetMouseCursor(.Arrow)
	if imgui.IsMouseDoubleClicked(.Left) && vd.penShape >= 0 {
		pen_finish(state)
		return
	}
	if imgui.IsMouseClicked(.Left) {
		if res == nil {
			res = vectordraw_new_file(state, v)
			if res == nil do return
			mouse := world_to_doc(v, Viewport_ScreenToWorld(state, mouse_screen()))
			pen_add(state, res, mouse, tol)
			return
		}
		pen_add(state, res, mouse, tol)
	}
	if vd.drag == .Pen && res != nil {
		if imgui.IsMouseDown(.Left) {
			// Dragging pulls the anchor's handles: out to the mouse, in mirrored.
			p := &res.doc.shapes[vd.penShape].path
			n := len(p.pts)
			at := p.pts[n - 1]
			out := mouse - at
			if linalg.length(out) > tol * 0.5 {
				vd.penOut = out
				if n >= 3 && p.cmds[len(p.cmds) - 1] == .Cubic do p.pts[n - 2] = at - out
				e.Vector_ResourceEdited(res)
			}
		} else {
			vd.drag = .None
			pen_tidy_last(res)
			e.Vector_ResourceEdited(res)
			vectordraw_save(state, res, "Pen")
		}
	}
}

@(private = "file")
mouse_screen :: proc() -> [2]f32 {
	m := imgui.GetIO().MousePos
	return {m.x, m.y}
}

// pen_add: a pen click - the path's first point, the next anchor, or
// (on the first anchor) closing it.
@(private = "file")
pen_add :: proc(state: ^EditorState, r: ^e.Vector_Resource, q: [2]f32, tol: f32) {
	edit_begin(r)
	context.allocator = e.Vector_EditAllocator(&r.doc)
	if vd.penShape < 0 {
		s: e.Vector_Shape
		e.Vector_Path_Init(&s.path)
		e.Vector_MoveTo(&s.path, q)
		s.style = e.Vector_Style{stroke = true, strokeColor = vd.stroke, strokeWidth = vd.width, fillColor = vd.fill, join = .Round, cap = .Round, miterLimit = 4, opacity = 1}
		s.style.stroke = vd.width > 0
		group := -1
		if g := e.Vector_ResourceGroup(r, vd.node.group); g >= 0 do group = g // (into the symbol being drawn)
		vd.penShape = e.Vector_DocInsertShape(&r.doc, s, group)
		vd.shape, vd.penOut = vd.penShape, {}
		vd.drag, vd.last = .Pen, q
		e.Vector_ResourceEdited(r)
		return
	}
	p := &r.doc.shapes[vd.penShape].path
	first := p.pts[0]
	last := p.pts[len(p.pts) - 1]
	closing := len(p.pts) > 2 && linalg.distance(q, first) <= tol * 1.5
	at := first if closing else q
	// A curve when the last anchor has an out-handle (the next drag adds the in).
	e.Vector_CubicTo(p, last + vd.penOut, at, at) // (in-handle on the anchor until dragged)
	vd.penOut = {}
	if closing {
		pen_tidy_last(r)
		append(&p.cmds, e.Vector_Cmd.Close)
		r.doc.shapes[vd.penShape].style.fill = vd.fill.a > 0
		e.Vector_ResourceEdited(r)
		vd.penShape = -1
		vectordraw_save(state, r, "Pen")
		return
	}
	vd.drag, vd.last = .Pen, q
	e.Vector_ResourceEdited(r)
}

// pen_tidy_last: a last segment with no handles is a straight line.
@(private = "file")
pen_tidy_last :: proc(r: ^e.Vector_Resource) {
	if vd.penShape < 0 do return
	p := &r.doc.shapes[vd.penShape].path
	nc, n := len(p.cmds), len(p.pts)
	if nc < 2 || p.cmds[nc - 1] != .Cubic || n < 4 do return
	prev, c1, c2, b := p.pts[n - 4], p.pts[n - 3], p.pts[n - 2], p.pts[n - 1]
	if linalg.distance(prev, c1) < 1e-3 && linalg.distance(c2, b) < 1e-3 {
		p.cmds[nc - 1] = .Line
		remove_range(&p.pts, n - 3, n - 1)
	}
}

// pen_finish ends the path being drawn (one point alone: removed).
@(private = "file")
pen_finish :: proc(state: ^EditorState) {
	if vd.penShape < 0 || vd.node == nil do return
	r := e.VectorShapeNode_Asset(vd.node)
	defer vd.penShape = -1
	if r == nil || vd.penShape >= len(r.doc.shapes) do return
	if len(r.doc.shapes[vd.penShape].path.pts) < 2 {
		edit_begin(r)
		e.Vector_DocRemoveShape(&r.doc, vd.penShape)
		vd.shape = -1
		edit_commit(state, r, "Pen")
	}
	vd.drag = .None
}

// --- the lossy-file question --------------------------------------------------

@(private = "file")
vectordraw_ask :: proc(state: ^EditorState) {
	if vd.askFor == nil do return
	v := vd.askFor
	if !e.Node_IsAlive(&v.node) {vd.askFor = nil; return}
	if !imgui.IsPopupOpen("Edit vector art###vd_lossy") do imgui.OpenPopup("Edit vector art###vd_lossy")
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Always, {0.5, 0.5})
	if !imgui.BeginPopupModal("Edit vector art###vd_lossy", nil, {.AlwaysAutoResize}) do return
	defer imgui.EndPopup()
	r := e.VectorShapeNode_Asset(v)
	imgui.TextUnformatted(fmt.ctprintf("%s has parts Rayzr can't draw:", v.file))
	if r != nil do for w in r.doc.warnings[:min(len(r.doc.warnings), 6)] do UI_DimText(fmt.tprintf("  %s", w))
	imgui.TextWrapped("Saving an edit writes only what Rayzr draws. Edit a copy, or overwrite the file (a .bak is kept)?")
	if UI_PrimaryButton("Edit a Copy", "vd.lossy.copy") {
		if rel := vectordraw_copy(state, v); rel != "" {
			Editor_RecordUndo(state, "Edit a copy of the art")
			v.file = strings.clone(rel, v.allocator)
					vectordraw_start(state, v)
		}
		vd.askFor = nil
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Overwrite", "vd.lossy.overwrite") {
		vectordraw_start(state, v)
		vd.askFor = nil
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Cancel", "vd.lossy.cancel") || imgui.IsKeyPressed(.Escape, false) {
		vd.askFor = nil
		imgui.CloseCurrentPopup()
	}
}

// vectordraw_copy writes the art as <name>_edit.svg (what Rayzr draws of it).
@(private = "file")
vectordraw_copy :: proc(state: ^EditorState, v: ^e.VectorShapeNode) -> string {
	r := e.VectorShapeNode_Asset(v)
	if r == nil do return ""
	stem := strings.trim_suffix(v.file, ".svg")
	rel := fmt.tprintf("%s_edit.svg", stem)
	for n := 2; project_file_exists(state, rel); n += 1 do rel = fmt.tprintf("%s_edit_%d.svg", stem, n)
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	if os.write_entire_file(full, transmute([]u8)e.Vector_Doc_ToSVG(&r.doc, context.temp_allocator)) != nil {
		Editor_Log(state, .Error, "Could not write %s", rel)
		return ""
	}
	Editor_InvalidateProjectFiles()
	Editor_Log(state, .Info, "Editing a copy: %s", rel)
	return strings.clone(rel, context.temp_allocator)
}

// --- drives ------------------------------------------------------------------------

// VectorDraw_DriveQuery: vd.active, vd.tool, vd.shapes (the node's file's
// shape count), vd.shape (selected), vd.anchors (of the selected shape),
// vd.file, vd.cmds (the selected shape's commands: "MLCZ").
VectorDraw_DriveQuery :: proc(state: ^EditorState, q: string) -> (string, bool) {
	if !strings.has_prefix(q, "vd.") do return "", false
	r: ^e.Vector_Resource
	if vd.node != nil && e.Node_IsAlive(&vd.node.node) do r = e.VectorShapeNode_Asset(vd.node)
	switch q {
	case "vd.active": return "true" if VectorDraw_IsActive(state) else "false", true
	case "vd.asking": return "true" if vd.askFor != nil else "false", true
	case "vd.tool":   return fmt.tprint(vd.tool), true
	case "vd.file":   return vd.node.file if vd.node != nil else "", true
	case "vd.shape":  return fmt.tprint(vd.shape), true
	case "vd.shapes": return fmt.tprint(len(r.doc.shapes) if r != nil else 0), true
	case "vd.anchors":
		if r == nil || vd.shape < 0 || vd.shape >= len(r.doc.shapes) do return "0", true
		return fmt.tprint(len(e.Vector_PathAnchors(&r.doc.shapes[vd.shape].path))), true
	case "vd.cmds":
		if r == nil || vd.shape < 0 || vd.shape >= len(r.doc.shapes) do return "", true
		sb := strings.builder_make(context.temp_allocator)
		letters := "MLQCZ"
		for c in r.doc.shapes[vd.shape].path.cmds do strings.write_byte(&sb, letters[int(c)])
		return strings.to_string(sb), true
	}
	if strings.has_prefix(q, "vd.point:") {
		i, _ := strconv.parse_int(q[len("vd.point:"):])
		if r == nil || vd.shape < 0 || vd.shape >= len(r.doc.shapes) do return "", true
		p := &r.doc.shapes[vd.shape].path
		anchors := e.Vector_PathAnchors(p)
		if i < 0 || i >= len(anchors) do return "", true
		pt := p.pts[anchors[i].pt]
		return fmt.tprintf("%.0f,%.0f", pt.x, pt.y), true
	}
	return "", false
}
