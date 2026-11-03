package editor

import "base:runtime"
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
	Rect,
	Ellipse,
	Polygon,
	Star,
	Pencil,
	Brush,
	Bucket,
	Eyedropper,
	Gradient,
}

@(private = "file")
Vd_Drag :: enum {
	None,
	Shape,
	Anchor,
	In,
	Out,
	Pen,
	Draw, // dragging out a shape tool's shape
	Freehand, // the Pencil / Brush collecting samples
	Box,      // the Select tool's selection box
	GradA,    // the Gradient tool's handles: a linear gradient's start / a radial's centre
	GradB,    //   its end / its radius
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
	def:      e.Vector_Style, // new shapes' style (the toolbar's swatches and width; the Inspector's Fill / Stroke with nothing selected)
	styleDirty: bool,         // the Inspector changed the selected shape's style (saved when the edit ends)
	backedUp: map[string]bool, // files whose .bak was written this session
	askFor:   ^e.VectorShapeNode, // the lossy-file question is open for it
	menu:     int, // the anchor the right-click menu is for
	start:    [2]f32, // a shape tool's drag start (document units)
	radius:   f32,    // Rectangle: corner radius
	sides:    i32,    // Polygon
	points:   i32,    // Star
	inner:    f32,    // Star: inner radius (fraction)
	smooth:   f32,    // Pencil / Brush: 0 (every wiggle) .. 100 (few, smooth curves)
	brush:    f32,    // Brush: width (document units)
	samples:  [dynamic][2]f32, // the freehand stroke so far (document units)
	widths:   [dynamic]f32,    // the Brush's width at each sample
	lastTime: f64,
	// The editor's allocator: tools grow the document from its arena
	// (context.allocator switched), but undo entries and logs outlive it.
	alloc:    runtime.Allocator,
	layer:    int,           // the layer (top-level group) new shapes go into (-1: as the node shows)
	locked:   map[int]bool,  // layers that can't be picked (editor only)
	snapped:  [2]f32,        // the anchor the last snap went to (shown), when snappedOn
	snappedOn: bool,
	sel:      [dynamic]int, // the selected shapes (vd.shape among them); one = vd.shape alone
	askSymbol: bool,        // the Convert to Symbol dialog is open
	symbolBuf: [64]u8,
	lastOffset: [2]f32, // the symbol's offset last frame (keep_symbol_in_place)
	offsetKnown: bool,
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
	if vd.def.miterLimit == 0 do vd.def = e.Vector_Style{fill = true, fillColor = {255, 255, 255, 255}, stroke = true, strokeColor = {20, 20, 20, 255}, strokeWidth = 2, join = .Round, cap = .Round, miterLimit = 4, opacity = 1}
	if vd.sides == 0 do vd.sides, vd.points, vd.inner, vd.smooth, vd.brush = 5, 5, 0.5, 50, 12
	vd.active, vd.node, vd.shape, vd.anchor, vd.drag, vd.penShape = true, v, -1, -1, .None, -1
	vd.alloc = context.allocator
	vd.offsetKnown = false
	vd.layer = -1
	if vd.locked == nil do vd.locked = make(map[int]bool)
	clear(&vd.locked)
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

// vd_snap: a point snapped (Ctrl held: not) - to another shape's anchor
// within a few pixels, else (the viewport's snap on) to the grid and the
// guides; `skip` is a shape whose anchors don't count (the one being edited).
@(private = "file")
vd_snap :: proc(state: ^EditorState, r: ^e.Vector_Resource, q: [2]f32, skip := -1) -> [2]f32 {
	vd.snappedOn = false
	if imgui.GetIO().KeyCtrl || imgui.GetIO().KeySuper do return q
	v := vd.node
	px := doc_per_px(state, v)
	if r != nil {
		best := 8 * px
		hit: [2]f32
		found := false
		for &s, i in r.doc.shapes {
			if i == skip || shape_locked(r, i) do continue
			for a in e.Vector_PathAnchors(&s.path) {
				if d := linalg.distance(s.path.pts[a.pt], q); d < best do best, hit, found = d, s.path.pts[a.pt], true
			}
		}
		if found {
			vd.snapped, vd.snappedOn = hit, true
			return hit
		}
	}
	if !state.snapGrid do return q
	w := doc_to_world(v, q)
	if state.gridSize > 0 do w = {math.round(w.x / state.gridSize) * state.gridSize, math.round(w.y / state.gridSize) * state.gridSize}
	if scene := state.activeScene; scene != nil {
		wq := doc_to_world(v, q)
		reach := 8 / max(state.cameraZoom, 0.0001)
		for g in scene.guides[:scene.guideCount] {
			if g.vertical && abs(wq.x - g.pos) < reach do w.x = g.pos
			if !g.vertical && abs(wq.y - g.pos) < reach do w.y = g.pos
		}
	}
	return world_to_doc(v, w)
}

// shape_locked: the shape is in a hidden or locked layer (not picked).
@(private = "file")
shape_locked :: proc(r: ^e.Vector_Resource, i: int) -> bool {
	if lo, hi := vd_scope(r); i < lo || i >= hi do return true // (editing one symbol: only its shapes)
	for g, gi in r.doc.groups {
		if g.parent != -1 || i < g.first || i >= g.first + g.count do continue
		return g.hidden || vd.locked[gi]
	}
	return false
}

// vd_scope: the shapes being edited [lo, hi) - the symbol the node shows
// (edit in place), else the whole file.
@(private = "file")
vd_scope :: proc(r: ^e.Vector_Resource) -> (lo, hi: int) {
	if g := e.Vector_ResourceGroup(r, vd.node.group); g >= 0 do return r.doc.groups[g].first, r.doc.groups[g].first + r.doc.groups[g].count
	return 0, len(r.doc.shapes)
}

// vd_selection: the selected shapes (vd.shape and the rest of vd.sel).
@(private = "file")
vd_selection :: proc(r: ^e.Vector_Resource) -> []int {
	if r == nil || vd.shape < 0 || vd.shape >= len(r.doc.shapes) do return nil
	inSel := false
	for i in vd.sel do if i == vd.shape do inSel = true
	if !inSel {
		clear(&vd.sel)
		append(&vd.sel, vd.shape)
	}
	out := make([dynamic]int, context.temp_allocator)
	for i in vd.sel do if i >= 0 && i < len(r.doc.shapes) do append(&out, i)
	return out[:]
}

@(private = "file")
vd_select_only :: proc(i: int) {
	if vd.sel == nil do vd.sel = make([dynamic]int, vd.alloc)
	clear(&vd.sel)
	vd.shape, vd.anchor = i, -1
	if i >= 0 do append(&vd.sel, i)
}

// vd_target_group: where new shapes go - the chosen layer, else the symbol
// the node shows (-1: the document).
@(private = "file")
vd_target_group :: proc(r: ^e.Vector_Resource) -> int {
	if vd.layer >= 0 && vd.layer < len(r.doc.groups) do return vd.layer
	if g := e.Vector_ResourceGroup(r, vd.node.group); g >= 0 do return g
	return -1
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
	convert_dialog(state)
	keep_symbol_in_place(state)
	v := vd.node
	io := imgui.GetIO()
	vd.offset = vd_offset(v) // (kept in place above: the mapping follows it)
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
		if imgui.IsKeyPressed(.R, false) do vectordraw_set_tool(state, .Rect)
		if imgui.IsKeyPressed(.O, false) do vectordraw_set_tool(state, .Ellipse)
		if imgui.IsKeyPressed(.Y, false) do vectordraw_set_tool(state, .Pencil)
		if imgui.IsKeyPressed(.B, false) do vectordraw_set_tool(state, .Brush)
		if imgui.IsKeyPressed(.K, false) do vectordraw_set_tool(state, .Bucket)
		if imgui.IsKeyPressed(.I, false) do vectordraw_set_tool(state, .Eyedropper)
		if imgui.IsKeyPressed(.F, false) do vectordraw_set_tool(state, .Gradient)
		if imgui.IsKeyPressed(.F8, false) && len(vd_selection(r)) > 0 do convert_open(r)
		if imgui.IsKeyPressed(.Escape, false) || imgui.IsKeyPressed(.Enter, false) {
			if vd.penShape >= 0 do pen_finish(state)
			else if imgui.IsKeyPressed(.Escape, false) {vectordraw_exit(state); return true}
		}
		// Draw order: Ctrl+] forward, Ctrl+[ back (within the shape's group).
		if r != nil && vd.shape >= 0 && vd.penShape < 0 && (io.KeyCtrl || io.KeySuper) {
			dir := 0
			if imgui.IsKeyPressed(.RightBracket, false) do dir = 1
			if imgui.IsKeyPressed(.LeftBracket, false) do dir = -1
			if dir != 0 {
				edit_begin(r)
				if j := e.Vector_DocMoveShape(&r.doc, vd.shape, dir); j != vd.shape {
					vd.shape, vd.anchor = j, -1
					edit_commit(state, r, "Bring forward" if dir > 0 else "Send backward")
				}
			}
		}
		if (imgui.IsKeyPressed(.Delete, false) || imgui.IsKeyPressed(.Backspace, false)) && r != nil && vd.shape >= 0 && vd.penShape < 0 {
			if vd.tool == .Node && vd.anchor >= 0 do anchor_delete(state, r, vd.shape, vd.anchor)
			else {
				edit_begin(r)
				sel := vd_selection(r)
				// (Highest first: the indices below stay right.)
				for k := len(sel) - 1; k >= 0; k -= 1 {
					top := k
					for j in 0 ..< k do if sel[j] > sel[top] do top = j
					sel[k], sel[top] = sel[top], sel[k]
				}
				for k := len(sel) - 1; k >= 0; k -= 1 do e.Vector_DocRemoveShape(&r.doc, sel[k])
				vd_select_only(-1)
				edit_commit(state, r, "Delete shapes")
			}
		}
	}

	// Every shape faintly; the selected one bright, with its anchors in Node mode.
	if r != nil {
		lo, hi := vd_scope(r)
		sel := vd_selection(r)
		for &s, i in r.doc.shapes[lo:hi] {
			k := lo + i
			on := false
			for x in sel do if x == k do on = true
			draw_path_outline(state, dl, v, &s.path, col_u32(UI_ACCENT if on else ui_line(0.35)), 2 if on else 1)
		}
	}
	Drive_ItemRect("vd.canvas", state.viewportPos, state.viewportPos + state.viewportSize, inWindow = true)

	switch vd.tool {
	case .Select: tool_select(state, dl, r, mouse, tol)
	case .Node:   tool_node(state, dl, r, mouse, tol)
	case .Pen:    tool_pen(state, dl, r, mouse, tol)
	case .Rect, .Ellipse, .Polygon, .Star: tool_shape(state, dl, r, mouse, tol)
	case .Pencil, .Brush: tool_freehand(state, dl, r, mouse, tol)
	case .Bucket: tool_bucket(state, r, mouse, tol)
	case .Eyedropper: tool_eyedropper(state, r, mouse, tol)
	case .Gradient: tool_gradient(state, dl, r, mouse, tol)
	}
	anchor_menu(state, r)
	// Where the last snap went (an anchor): a ring there while dragging.
	if vd.snappedOn && (vd.drag != .None || vd.tool == .Pen) {
		at := doc_to_screen(state, v, vd.snapped)
		imgui.DrawList_AddCircle(dl, at, 7, col_u32(UI_WARNING), 0, 2)
	}
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
	tools := [12]struct {t: Vector_Tool, icon, id, tip: string}{
		{.Select, ICON_FA_ARROW_POINTER, "vd.tool:select", "Select (V): click a shape, drag to move it"},
		{.Node, ICON_FA_BEZIER_CURVE, "vd.tool:node", "Nodes (A): drag anchors and handles; double-click a segment to add one"},
		{.Pen, ICON_FA_PEN, "vd.tool:pen", "Pen (P): click for corners, drag for curves; click the first point to close"},
		{.Rect, ICON_FA_SQUARE, "vd.tool:rect", "Rectangle (R): drag one out (Shift: a square, Alt: from the centre); its corner radius is beside the colours"},
		{.Ellipse, ICON_FA_CIRCLE, "vd.tool:ellipse", "Ellipse (O): drag one out (Shift: a circle, Alt: from the centre)"},
		{.Polygon, ICON_FA_DRAW_POLYGON, "vd.tool:polygon", "Polygon: drag one out (its number of sides is beside the colours)"},
		{.Star, ICON_FA_STAR, "vd.tool:star", "Star: drag one out (its points and inner radius are beside the colours)"},
		{.Pencil, ICON_FA_PENCIL, "vd.tool:pencil", "Pencil (Y): draw a line freehand (smoothed: the slider beside the colours)"},
		{.Brush, ICON_FA_PAINTBRUSH, "vd.tool:brush", "Brush (B): paint a filled stroke - thinner when you move fast"},
		{.Bucket, ICON_FA_FILL_DRIP, "vd.tool:bucket", "Paint Bucket (K): click a shape to fill it, or a gap lines close in to fill it"},
		{.Eyedropper, ICON_FA_EYE_DROPPER, "vd.tool:eyedropper", "Eyedropper (I): click a shape to copy its fill and line to the selected shape (or to new shapes); Alt+click: the colour on screen (Shift: as the line colour)"},
		{.Gradient, ICON_FA_DROPLET, "vd.tool:gradient", "Gradient (F): drag the selected shape's gradient ends (a radial one: its centre and radius)"},
	}
	for t, i in tools {
		if i > 0 do imgui.SameLine(0, 4)
		if UI_IconButton(t.icon, t.id, t.tip, vd.tool == t.t, 28) do vectordraw_set_tool(state, t.t)
	}
	// (Second row: the colours, the tool's settings, the actions.)
	colour :: proc(label, id: cstring, c: ^[4]u8, tip: string) {
		f := [4]f32{f32(c[0]) / 255, f32(c[1]) / 255, f32(c[2]) / 255, f32(c[3]) / 255}
		if imgui.ColorEdit4(label, &f, {.NoInputs, .AlphaBar}) do c^ = {u8(f[0] * 255 + 0.5), u8(f[1] * 255 + 0.5), u8(f[2] * 255 + 0.5), u8(f[3] * 255 + 0.5)}
		Drive_Item(string(id))
		UI_Tooltip(tip)
	}
	colour("##vdfill", "vd.def.fillColor", &vd.def.fillColor, "Fill colour of new closed shapes")
	imgui.SameLine(0, 4)
	colour("##vdstroke", "vd.def.strokeColor", &vd.def.strokeColor, "Line colour of new shapes")
	imgui.SameLine(0, 4)
	imgui.SetNextItemWidth(60)
	imgui.DragFloat("##vdwidth", &vd.def.strokeWidth, 0.1, 0, 64, "%.1f px")
	Drive_Item("vd.def.strokeWidth")
	UI_Tooltip("Line width of new shapes")
	// The shape tool's settings.
	#partial switch vd.tool {
	case .Rect:
		imgui.SameLine(0, 8)
		imgui.SetNextItemWidth(70)
		imgui.DragFloat("##vdradius", &vd.radius, 0.5, 0, 500, "r %.0f")
		Drive_Item("vd.radius")
		UI_Tooltip("Corner radius of new rectangles")
	case .Polygon:
		imgui.SameLine(0, 8)
		imgui.SetNextItemWidth(70)
		imgui.DragInt("##vdsides", &vd.sides, 0.1, 3, 32, "%d sides")
		Drive_Item("vd.sides")
	case .Pencil, .Brush:
		if vd.tool == .Brush {
			imgui.SameLine(0, 8)
			imgui.SetNextItemWidth(70)
			imgui.DragFloat("##vdbrush", &vd.brush, 0.2, 1, 200, "size %.0f")
			Drive_Item("vd.brush")
			UI_Tooltip("Brush width (moving fast paints thinner)")
		}
		imgui.SameLine(0, 8)
		imgui.SetNextItemWidth(90)
		imgui.SliderFloat("##vdsmooth", &vd.smooth, 0, 100, "smooth %.0f")
		Drive_Item("vd.smooth")
		UI_Tooltip("0: every wiggle (more anchors); higher: fewer, smoother curves")
	case .Star:
		imgui.SameLine(0, 8)
		imgui.SetNextItemWidth(70)
		imgui.DragInt("##vdpoints", &vd.points, 0.1, 3, 32, "%d points")
		Drive_Item("vd.points")
		imgui.SameLine(0, 4)
		imgui.SetNextItemWidth(70)
		imgui.DragFloat("##vdinner", &vd.inner, 0.01, 0.05, 0.95, "inner %.2f")
		Drive_Item("vd.inner")
		UI_Tooltip("Inner corners' radius, a fraction of the outer")
	}
	imgui.SameLine(0, 12)
	r := e.VectorShapeNode_Asset(vd.node)
	if n := len(vd_selection(r)); n > 0 {
		imgui.SameLine(0, 8)
		if UI_Button(fmt.tprintf("%s  To Symbol", ICON_FA_CUBE), "vd.convert") do convert_open(r)
		UI_Tooltip(fmt.tprintf("Convert to Symbol (F8): the %d selected shape(s) become a named group of the file, and a Vector Shape showing it goes where they are", n))
	}
	// Editing one symbol: where (file > symbol).
	if vd.node.group != "" {
		imgui.SameLine(0, 12)
		UI_DimText(fmt.tprintf("%s  >  %s", filepath.base(vd.node.file), vd.node.group))
		Drive_Item("vd.breadcrumb")
	}
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

// keep_symbol_in_place: drawing into a symbol (or undoing that) can change
// its box, where its origin sits - the art would jump under the mouse. Each
// frame the node being drawn in moves by as much the other way.
@(private = "file")
keep_symbol_in_place :: proc(state: ^EditorState) {
	v := vd.node
	if v == nil || v.group == "" || state.activeScene == nil do return
	off := vd_offset(v)
	if !vd.offsetKnown {
		vd.lastOffset, vd.offsetKnown = off, true
		return
	}
	d := vd.lastOffset - off
	if d.x * d.x + d.y * d.y < 1e-6 do return
	// (Where the art's point at the new origin was drawn: the new position.)
	a := v.globalRotation * math.RAD_PER_DEG
	c, s := math.cos(a), math.sin(a)
	l := d * v.globalScale
	world := v.globalPosition + {l.x * c - l.y * s, l.x * s + l.y * c}
	par := e.GetParent(state.activeScene.manager, &v.node)
	v.position = Editor_WorldToLocal(par, world) if par != nil else world
	e.Node_SetGlobalPositions(state.activeScene.manager, state.activeScene.rootNode)
	state.nextVersion += 1 // (the scene changed: saved with it)
	state.sceneVersion[state.activeScene] = state.nextVersion
	vd.lastOffset = off
}

@(private = "file")
vectordraw_save :: proc(state: ^EditorState, r: ^e.Vector_Resource, label: string) {
	context.allocator = vd.alloc // (not the document's arena: undo keeps these)
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
	io := imgui.GetIO()
	if vd_clicked() {
		hit := shape_at(r, mouse, tol)
		sel := vd_selection(r)
		inSel := false
		for x in sel do if x == hit do inSel = true
		switch {
		case hit >= 0 && io.KeyShift:
			// Shift: added to / taken from the selection.
			if inSel {
				for x, k in vd.sel do if x == hit {ordered_remove(&vd.sel, k); break}
				vd.shape = vd.sel[len(vd.sel) - 1] if len(vd.sel) > 0 else -1
			} else {
				append(&vd.sel, hit)
				vd.shape = hit
			}
			vd.anchor = -1
		case hit >= 0:
			if !inSel do vd_select_only(hit)
			else do vd.shape = hit
			vd.drag, vd.last, vd.moved = .Shape, mouse, false
			edit_begin(r)
		case:
			// Empty space: a selection box.
			if !io.KeyShift do vd_select_only(-1)
			vd.drag, vd.start = .Box, mouse
		}
	}
	switch vd.drag {
	case .Shape:
		if imgui.IsMouseDown(.Left) {
			if d := mouse - vd.last; d != {} {
				for i in vd_selection(r) do e.Vector_PathMove(&r.doc.shapes[i].path, d)
				e.Vector_ResourceEdited(r)
				vd.moved = true
			}
			vd.last = mouse
		} else {
			if vd.moved do vectordraw_save(state, r, "Move shapes")
			vd.drag = .None
		}
	case .Box:
		a, b := doc_to_screen(state, vd.node, vd.start), doc_to_screen(state, vd.node, mouse)
		imgui.DrawList_AddRectFilled(dl, {min(a.x, b.x), min(a.y, b.y)}, {max(a.x, b.x), max(a.y, b.y)}, col_u32(ui_accent(0.12)))
		imgui.DrawList_AddRect(dl, {min(a.x, b.x), min(a.y, b.y)}, {max(a.x, b.x), max(a.y, b.y)}, col_u32(UI_ACCENT))
		if !imgui.IsMouseDown(.Left) {
			// Shapes wholly inside the box.
			lo, hi := [2]f32{min(vd.start.x, mouse.x), min(vd.start.y, mouse.y)}, [2]f32{max(vd.start.x, mouse.x), max(vd.start.y, mouse.y)}
			for i in 0 ..< len(r.doc.shapes) {
				if shape_locked(r, i) do continue
				bb := e.Vector_ShapesBounds(r.doc.shapes[i:i + 1], false)
				if bb[0] >= lo.x && bb[1] >= lo.y && bb[2] <= hi.x && bb[3] <= hi.y {
					if vd.sel == nil do vd.sel = make([dynamic]int, vd.alloc)
					append(&vd.sel, i)
					vd.shape = i
				}
			}
			vd.drag = .None
		}
	case .None, .Anchor, .In, .Out, .Pen, .Draw, .Freehand, .GradA, .GradB:
	}
}

// shape_at: the topmost shape under a document point (its fill, or near its line).
@(private = "file")
shape_at :: proc(r: ^e.Vector_Resource, q: [2]f32, tol: f32) -> int {
	for i := len(r.doc.shapes) - 1; i >= 0; i -= 1 {
		if shape_locked(r, i) do continue
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
	if (imgui.IsMouseDoubleClicked(.Left) && !imgui.IsAnyItemHovered()) && vd.shape >= 0 && hoverKind == .None {
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
	if vd_clicked() {
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
						d = vd_snap(state, r, mouse, vd.shape) - p.pts[a.pt]
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
					case .None, .Shape, .Pen, .Draw, .Freehand, .GradA, .GradB, .Box:
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
	if (imgui.IsMouseDoubleClicked(.Left) && !imgui.IsAnyItemHovered()) && vd.penShape >= 0 {
		pen_finish(state)
		return
	}
	if vd_clicked() {
		if res == nil {
			res = vectordraw_new_file(state, v)
			if res == nil do return
			mouse := world_to_doc(v, Viewport_ScreenToWorld(state, mouse_screen()))
			pen_add(state, res, vd_snap(state, res, mouse), tol)
			vd.start = mouse
			return
		}
		pen_add(state, res, vd_snap(state, res, mouse, vd.penShape), tol)
		vd.start = mouse // (the press, unsnapped: a drag from here pulls handles)
	}
	if vd.drag == .Pen && res != nil {
		if imgui.IsMouseDown(.Left) {
			// Dragging pulls the anchor's handles: out to the mouse, in mirrored.
			p := &res.doc.shapes[vd.penShape].path
			n := len(p.pts)
			at := p.pts[n - 1]
			out := mouse - at
			if linalg.distance(mouse, vd.start) > tol * 0.5 {
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

// vd_clicked: a left click on the canvas (not on the toolbar over it).
@(private = "file")
vd_clicked :: proc() -> bool {return imgui.IsMouseClicked(.Left) && !imgui.IsAnyItemHovered()}

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
		s.style = vd.def
		s.style.fill = false // (filled when it's closed)
		s.style.stroke = vd.def.stroke && vd.def.strokeWidth > 0
		vd.penShape = e.Vector_DocInsertShape(&r.doc, s, vd_target_group(r))
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
		r.doc.shapes[vd.penShape].style.fill = vd.def.fill
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

// --- Rectangle, Ellipse, Polygon, Star ------------------------------------------------

// tool_shape: drag out a shape (Shift: square / circle / regular, Alt: from
// the centre); it is an ordinary path from then on.
@(private = "file")
tool_shape :: proc(state: ^EditorState, dl: ^imgui.DrawList, r: ^e.Vector_Resource, mouse: [2]f32, tol: f32) {
	v := vd.node
	res := r
	if !state.viewportHovered && vd.drag == .None do return
	imgui.SetMouseCursor(.Arrow)
	io := imgui.GetIO()
	if vd_clicked() {
		q := mouse
		if res == nil {
			res = vectordraw_new_file(state, v)
			if res == nil do return
			q = world_to_doc(v, Viewport_ScreenToWorld(state, mouse_screen()))
		}
		edit_begin(res)
		context.allocator = e.Vector_EditAllocator(&res.doc)
		s: e.Vector_Shape
		e.Vector_Path_Init(&s.path)
		s.style = vd.def
		s.style.stroke = vd.def.stroke && vd.def.strokeWidth > 0
		vd.shape = e.Vector_DocInsertShape(&res.doc, s, vd_target_group(res))
		vd.anchor, vd.drag, vd.start = -1, .Draw, vd_snap(state, res, q, vd.shape)
		return
	}
	if vd.drag != .Draw || res == nil || vd.shape < 0 || vd.shape >= len(res.doc.shapes) do return
	a, b := vd.start, vd_snap(state, res, mouse, vd.shape)
	if io.KeyShift {
		// Square / circle / a regular polygon: the larger side both ways.
		d := b - a
		m := max(abs(d.x), abs(d.y))
		b = a + {m if d.x >= 0 else -m, m if d.y >= 0 else -m}
	}
	if io.KeyAlt do a = a - (b - a) // (from the centre)
	lo, hi := [2]f32{min(a.x, b.x), min(a.y, b.y)}, [2]f32{max(a.x, b.x), max(a.y, b.y)}
	p := &res.doc.shapes[vd.shape].path
	e.Vector_Path_Clear(p)
	centre, radii := (lo + hi) * 0.5, (hi - lo) * 0.5
	#partial switch vd.tool {
	case .Rect:    e.Vector_RoundRect(p, lo, hi, vd.radius)
	case .Ellipse: e.Vector_Ellipse(p, centre, radii)
	case .Polygon: e.Vector_Polygon(p, centre, radii, int(vd.sides))
	case .Star:    e.Vector_Polygon(p, centre, radii, int(vd.points), clamp(vd.inner, 0.05, 0.95))
	}
	e.Vector_ResourceEdited(res)
	if !imgui.IsMouseDown(.Left) {
		vd.drag = .None
		if hi.x - lo.x < tol && hi.y - lo.y < tol {
			// A click, not a drag: nothing drawn.
			e.Vector_DocRemoveShape(&res.doc, vd.shape)
			vd.shape = -1
			e.Vector_ResourceEdited(res)
			return
		}
		vectordraw_save(state, res, "Draw shape")
	}
}

// --- Pencil, Brush -------------------------------------------------------------------

// tool_freehand: drag to draw; on release the samples are fitted to curves
// (the smoothing slider sets the error) - a line (Pencil) or a filled
// outline whose width follows the speed (Brush).
@(private = "file")
tool_freehand :: proc(state: ^EditorState, dl: ^imgui.DrawList, r: ^e.Vector_Resource, mouse: [2]f32, tol: f32) {
	v := vd.node
	if vd.samples == nil {
		vd.samples = make([dynamic][2]f32)
		vd.widths = make([dynamic]f32)
	}
	// The stroke so far, as drawn.
	if vd.drag == .Freehand && len(vd.samples) > 1 {
		col := col_u32({f32(vd.def.strokeColor.r) / 255, f32(vd.def.strokeColor.g) / 255, f32(vd.def.strokeColor.b) / 255, 1}) if vd.tool == .Pencil else col_u32({f32(vd.def.fillColor.r) / 255, f32(vd.def.fillColor.g) / 255, f32(vd.def.fillColor.b) / 255, 1})
		scale := 1 / doc_per_px(state, v)
		for i in 1 ..< len(vd.samples) {
			w := vd.def.strokeWidth * scale if vd.tool == .Pencil else vd.widths[i] * scale
			imgui.DrawList_AddLine(dl, doc_to_screen(state, v, vd.samples[i - 1]), doc_to_screen(state, v, vd.samples[i]), col, max(w, 1))
		}
	}
	if !state.viewportHovered && vd.drag == .None do return
	imgui.SetMouseCursor(.Arrow)
	now := imgui.GetTime()
	if vd_clicked() {
		clear(&vd.samples)
		clear(&vd.widths)
		append(&vd.samples, mouse)
		append(&vd.widths, vd.brush)
		vd.drag, vd.lastTime = .Freehand, now
		return
	}
	if vd.drag != .Freehand do return
	if imgui.IsMouseDown(.Left) {
		last := vd.samples[len(vd.samples) - 1]
		if d := linalg.distance(mouse, last); d > tol * 0.4 {
			// Faster (screen pixels a second): thinner, down to a third.
			dt := max(f32(now - vd.lastTime), 1.0 / 240)
			speed := d / doc_per_px(state, v) / dt
			w := vd.brush * clamp(1.2 - speed / 2500, 0.35, 1)
			if n := len(vd.widths); n > 0 do w = vd.widths[n - 1] * 0.6 + w * 0.4 // (eased: no jumps)
			append(&vd.samples, mouse)
			append(&vd.widths, w)
			vd.lastTime = now
		}
		return
	}
	// Released: fit and keep it.
	vd.drag = .None
	if len(vd.samples) < 2 && vd.tool == .Pencil do return
	res := r
	if res == nil {
		res = vectordraw_new_file(state, v)
		if res == nil do return
	}
	err := (0.3 + vd.smooth / 100 * 7.7) * doc_per_px(state, v)
	edit_begin(res)
	context.allocator = e.Vector_EditAllocator(&res.doc)
	s: e.Vector_Shape
	e.Vector_Path_Init(&s.path)
	if vd.tool == .Pencil {
		e.Vector_FitCurve(vd.samples[:], err, &s.path)
		s.style = vd.def
		s.style.fill, s.style.stroke = false, true
		s.style.strokeWidth = max(vd.def.strokeWidth, 0.5)
	} else {
		// The ends taper a little (as a brush lifts).
		n := len(vd.widths)
		for i in 0 ..< min(3, n) {
			f := 0.55 + 0.15 * f32(i)
			vd.widths[i] *= f
			vd.widths[n - 1 - i] *= f
		}
		e.Vector_BrushOutline(vd.samples[:], vd.widths[:], err, &s.path)
		s.style = vd.def
		s.style.fill, s.style.stroke = true, false
		if !vd.def.fill do s.style.fillColor, s.style.fillPaint = vd.def.strokeColor, {} // (no fill set: the line colour)
	}
	vd.shape = e.Vector_DocInsertShape(&res.doc, s, vd_target_group(res))
	edit_commit(state, res, "Pencil" if vd.tool == .Pencil else "Brush")
}

// --- Paint Bucket --------------------------------------------------------------------

// tool_bucket: a click inside a filled shape gives it the fill colour; in a
// gap that lines close in, a new filled shape under them.
@(private = "file")
tool_bucket :: proc(state: ^EditorState, r: ^e.Vector_Resource, mouse: [2]f32, tol: f32) {
	if r == nil || !state.viewportHovered || !vd_clicked() do return
	edit_begin(r)
	for i := len(r.doc.shapes) - 1; i >= 0; i -= 1 {
		s := &r.doc.shapes[i]
		if s.style.fill && path_contains(&s.path, mouse) {
			s.style.fill, s.style.fillColor, s.style.fillPaint = true, vd.def.fillColor, vd.def.fillPaint
			vd.shape = i
			edit_commit(state, r, "Paint Bucket")
			return
		}
	}
	shapes := e.Vector_DocShapes(&r.doc, e.Vector_ResourceGroup(r, vd.node.group))
	context.allocator = e.Vector_EditAllocator(&r.doc)
	s: e.Vector_Shape
	e.Vector_Path_Init(&s.path)
	if !e.Vector_EnclosedArea(shapes, mouse, 0.25 * doc_per_px(state, vd.node), &s.path) {
		context.allocator = vd.alloc
		Editor_Log(state, .Info, "Paint Bucket: that area isn't closed in (draw lines round it, or click inside a shape)")
		return
	}
	s.style = vd.def
	s.style.fill, s.style.stroke, s.style.fillRule = true, false, .EvenOdd
	group := vd_target_group(r)
	// (Under the lines: the group's first shape.)
	first := r.doc.groups[group].first if group >= 0 else 0
	vd.shape = e.Vector_DocInsertShape(&r.doc, s, group, first)
	edit_commit(state, r, "Paint Bucket")
}

// --- Eyedropper -----------------------------------------------------------------------

// tool_eyedropper: a click on a shape copies its style to the selected
// shape (or, picked from the selected shape itself or with none, to new
// shapes); Alt+click takes the colour on screen as the fill (Shift: the line).
@(private = "file")
tool_eyedropper :: proc(state: ^EditorState, r: ^e.Vector_Resource, mouse: [2]f32, tol: f32) {
	if !state.viewportHovered || !vd_clicked() do return
	io := imgui.GetIO()
	to := -1
	if r != nil && vd.shape >= 0 && vd.shape < len(r.doc.shapes) do to = vd.shape
	style := vd.def if to < 0 else r.doc.shapes[to].style
	if io.KeyAlt {
		c := screen_colour(state, mouse_screen())
		if io.KeyShift do style.stroke, style.strokeColor, style.strokePaint = true, c, {}
		else do style.fill, style.fillColor, style.fillPaint = true, c, {}
	} else {
		if r == nil do return
		src := shape_at(r, mouse, tol)
		if src < 0 do return
		if src == to do to = -1 // (from the selected shape itself: for new shapes)
		style = r.doc.shapes[src].style
	}
	if to < 0 {
		vd.def = style
		Editor_Log(state, .Info, "New shapes take that style")
		return
	}
	edit_begin(r)
	r.doc.shapes[to].style = style
	edit_commit(state, r, "Eyedropper")
}

// screen_colour: the viewport's pixel under a screen point.
@(private = "file")
screen_colour :: proc(state: ^EditorState, at: [2]f32) -> [4]u8 {
	img := rl.LoadImageFromTexture(state.renderTexture.texture)
	defer rl.UnloadImage(img)
	x := i32(at.x - state.viewportPos.x)
	y := i32(at.y - state.viewportPos.y)
	if x < 0 || y < 0 || x >= img.width || y >= img.height do return {0, 0, 0, 255}
	c := rl.GetImageColor(img, x, img.height - 1 - y) // (render textures are upside down)
	return {c.r, c.g, c.b, 255}
}

// --- Gradient -------------------------------------------------------------------------

// The paint the Gradient tool works on: the selected shape's fill gradient,
// else its line's.
@(private = "file")
grad_paint :: proc(r: ^e.Vector_Resource) -> ^e.Vector_Paint {
	if r == nil || vd.shape < 0 || vd.shape >= len(r.doc.shapes) do return nil
	st := &r.doc.shapes[vd.shape].style
	if st.fill && st.fillPaint.kind != .Solid do return &st.fillPaint
	if st.stroke && st.strokePaint.kind != .Solid do return &st.strokePaint
	return nil
}

@(private = "file")
xf_of :: proc(p: ^e.Vector_Paint) -> [6]f32 {return p.transform if p.transform != {} else {1, 0, 0, 1, 0, 0}}

@(private = "file")
xf_apply :: proc(t: [6]f32, q: [2]f32) -> [2]f32 {return {t[0] * q.x + t[2] * q.y + t[4], t[1] * q.x + t[3] * q.y + t[5]}}

@(private = "file")
xf_inverse :: proc(t: [6]f32, q: [2]f32) -> [2]f32 {
	det := t[0] * t[3] - t[1] * t[2]
	if abs(det) < 1e-9 do return q
	x, y := q.x - t[4], q.y - t[5]
	return {(t[3] * x - t[2] * y) / det, (-t[1] * x + t[0] * y) / det}
}

// tool_gradient: the selected shape's gradient ends as handles - drag them
// (a click elsewhere selects another shape).
@(private = "file")
tool_gradient :: proc(state: ^EditorState, dl: ^imgui.DrawList, r: ^e.Vector_Resource, mouse: [2]f32, tol: f32) {
	if r == nil do return
	v := vd.node
	p := grad_paint(r)
	a, b: [2]f32
	if p != nil {
		t := xf_of(p)
		if p.kind == .Linear do a, b = xf_apply(t, p.p0), xf_apply(t, p.p1)
		else do a, b = xf_apply(t, p.center), xf_apply(t, p.center + {p.radius, 0})
		sa, sb := doc_to_screen(state, v, a), doc_to_screen(state, v, b)
		imgui.DrawList_AddLine(dl, sa, sb, col_u32(UI_ACCENT), 1.5)
		if p.kind == .Radial do imgui.DrawList_AddCircle(dl, sa, linalg.distance(sa, sb), col_u32(ui_line(0.6)), 64, 1)
		for h, k in ([2][2]f32{sa, sb}) {
			imgui.DrawList_AddCircleFilled(dl, h, 6, col_u32({1, 1, 1, 1}))
			imgui.DrawList_AddCircle(dl, h, 6, col_u32(UI_ACCENT), 0, 2)
			Drive_ItemRect(fmt.tprintf("vd.grad:%d", k), h - {7, 7}, h + {7, 7}, inWindow = true)
		}
	}
	if !state.viewportHovered && vd.drag == .None do return
	if vd_clicked() {
		switch {
		case p != nil && linalg.distance(mouse, a) <= tol * 1.5: vd.drag = .GradA
		case p != nil && linalg.distance(mouse, b) <= tol * 1.5: vd.drag = .GradB
		case:
			vd.shape, vd.anchor = shape_at(r, mouse, tol), -1
			if vd.shape >= 0 && grad_paint(r) == nil do Editor_Log(state, .Info, "Gradient: give the shape a gradient first (Inspector > Fill > Linear / Radial gradient)")
			return
		}
		vd.moved = false
		edit_begin(r)
	}
	if (vd.drag == .GradA || vd.drag == .GradB) && p != nil {
		if imgui.IsMouseDown(.Left) {
			q := xf_inverse(xf_of(p), vd_snap(state, r, mouse, vd.shape))
			if p.kind == .Linear {
				if vd.drag == .GradA do p.p0 = q
				else do p.p1 = q
			} else {
				if vd.drag == .GradA do p.center = q
				else do p.radius = max(linalg.distance(q, p.center), 0.5)
			}
			e.Vector_ResourceEdited(r)
			vd.moved = true
		} else {
			if vd.moved do vectordraw_save(state, r, "Gradient")
			vd.drag = .None
		}
	}
}

// --- layers (the Inspector, while drawing) -----------------------------------------------

// VectorDraw_LayersUI: the file's layers (top-level groups) - which one new
// shapes go into, shown / hidden, locked, renamed, reordered, added - and
// the selected shape's draw order.
VectorDraw_LayersUI :: proc(state: ^EditorState, v: ^e.VectorShapeNode) {
	if !VectorDraw_IsActive(state) || vd.node != v do return
	r := e.VectorShapeNode_Asset(v)
	layers: []int
	if r != nil do layers = e.Vector_DocLayers(&r.doc)
	imgui.TextUnformatted("Layers")
	imgui.SameLine()
	if UI_IconButton(ICON_FA_PLUS, "vd.layer.add", "A new layer on top (new shapes go into it)", false, 22) {
		if r == nil do r = vectordraw_new_file(state, v) // (nothing drawn yet: the file first)
		if r == nil do return
		edit_begin(r)
		vd.layer = e.Vector_DocAddGroup(&r.doc, fmt.tprintf("Layer %d", len(layers) + 1))
		edit_commit(state, r, "Add layer")
		layers = e.Vector_DocLayers(&r.doc)
	}
	if r == nil || len(layers) == 0 {
		UI_DimText("No layers: shapes go straight into the file.")
		return
	}
	// Top first (drawn last), as layer lists show them.
	for k := len(layers) - 1; k >= 0; k -= 1 {
		gi := layers[k]
		g := &r.doc.groups[gi]
		imgui.PushIDInt(i32(gi))
		defer imgui.PopID()
		if imgui.RadioButton("##target", vd.layer == gi) do vd.layer = gi
		Drive_Item(fmt.tprintf("vd.layer.target:%d", gi))
		UI_Tooltip("New shapes go into this layer")
		imgui.SameLine(0, 4)
		if UI_IconButton(ICON_FA_EYE_SLASH if g.hidden else ICON_FA_EYE, fmt.tprintf("vd.layer.hide:%d", gi), "Show / hide (hidden layers are saved hidden)", false, 22) {
			edit_begin(r)
			g.hidden = !g.hidden
			edit_commit(state, r, "Hide layer")
		}
		imgui.SameLine(0, 2)
		if UI_IconButton(ICON_FA_LOCK if vd.locked[gi] else ICON_FA_LOCK_OPEN, fmt.tprintf("vd.layer.lock:%d", gi), "Lock: its shapes can't be picked (while drawing)", vd.locked[gi], 22) do vd.locked[gi] = !vd.locked[gi]
		imgui.SameLine(0, 4)
		buf: [64]u8
		copy(buf[:63], g.name)
		imgui.SetNextItemWidth(max(imgui.GetContentRegionAvail().x - 56, 60))
		if imgui.InputText("##name", cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue}) {
			name := strings.trim_space(string(cstring(raw_data(buf[:]))))
			if name != "" && name != g.name {
				edit_begin(r)
				g.name = strings.clone(name, e.Vector_EditAllocator(&r.doc))
				edit_commit(state, r, "Rename layer")
			}
		}
		Drive_Item(fmt.tprintf("vd.layer.name:%d", gi))
		imgui.SameLine(0, 2)
		if UI_IconButton(ICON_FA_ARROW_UP, fmt.tprintf("vd.layer.up:%d", gi), "Move up (drawn over the next)", false, 22) {
			edit_begin(r)
			if e.Vector_DocMoveLayer(&r.doc, gi, 1) do edit_commit(state, r, "Move layer")
		}
		imgui.SameLine(0, 2)
		if UI_IconButton(ICON_FA_ARROW_DOWN, fmt.tprintf("vd.layer.down:%d", gi), "Move down", false, 22) {
			edit_begin(r)
			if e.Vector_DocMoveLayer(&r.doc, gi, -1) do edit_commit(state, r, "Move layer")
		}
	}
	if vd.shape >= 0 {
		if UI_Button(fmt.tprintf("%s  Forward", ICON_FA_ARROW_UP), "vd.forward") do vd_move_shape(state, r, 1)
		UI_Tooltip("Draw the selected shape over the next one (Ctrl+])")
		imgui.SameLine()
		if UI_Button(fmt.tprintf("%s  Backward", ICON_FA_ARROW_DOWN), "vd.backward") do vd_move_shape(state, r, -1)
		UI_Tooltip("Draw it under the one before (Ctrl+[)")
	}
}

// VectorDraw_StyleUI: Fill / Stroke / Shape and the swatches - for the
// selected shape, else for new shapes. It edits a copy and puts it in once
// the background jobs reading the document are done; saved when the edit ends.
VectorDraw_StyleUI :: proc(state: ^EditorState, v: ^e.VectorShapeNode) {
	if !VectorDraw_IsActive(state) || vd.node != v do return
	r := e.VectorShapeNode_Asset(v)
	editing := r != nil && vd.shape >= 0 && vd.shape < len(r.doc.shapes)
	imgui.Spacing()
	UI_DimText(fmt.tprintf("Style of shape %d", vd.shape) if editing else "Style of new shapes (select a shape to change its own)")
	Drive_Item("vd.style.for")
	st := r.doc.shapes[vd.shape].style if editing else vd.def
	bounds := [4]f32{0, 0, 100, 100}
	if editing do bounds = e.Vector_ShapesBounds(r.doc.shapes[vd.shape:vd.shape + 1], false)
	else if r != nil do bounds = {r.doc.min.x, r.doc.min.y, r.doc.min.x + r.doc.size.x, r.doc.min.y + r.doc.size.y}
	changed := VectorStyle_Edit(state, &st, bounds)
	used: [][4]u8
	if r != nil do used = VectorStyle_UsedColours(&r.doc)
	changed |= VectorStyle_Swatches(state, &st, used)
	if changed {
		if editing {
			edit_begin(r)
			r.doc.shapes[vd.shape].style = st
			e.Vector_ResourceEdited(r)
			vd.styleDirty = true
		} else {
			vd.def = st
		}
	}
	if vd.styleDirty && !imgui.IsAnyItemActive() {
		vd.styleDirty = false
		if r != nil do vectordraw_save(state, r, "Style")
	}
}

@(private = "file")
vd_move_shape :: proc(state: ^EditorState, r: ^e.Vector_Resource, dir: int) {
	edit_begin(r)
	if j := e.Vector_DocMoveShape(&r.doc, vd.shape, dir); j != vd.shape {
		vd.shape, vd.anchor = j, -1
		edit_commit(state, r, "Bring forward" if dir > 0 else "Send backward")
	}
}

// --- Convert to Symbol ----------------------------------------------------------------

@(private = "file")
convert_open :: proc(r: ^e.Vector_Resource) {
	if r == nil do return
	vd.askSymbol = true
	vd.symbolBuf = {}
	copy(vd.symbolBuf[:63], e.Vector_DocGroupNameFree(&r.doc, "Symbol"))
}

// convert_dialog: the symbol's name; OK makes the group and its instance.
@(private = "file")
convert_dialog :: proc(state: ^EditorState) {
	if !vd.askSymbol do return
	if !imgui.IsPopupOpen("Convert to Symbol###vd_convert") do imgui.OpenPopup("Convert to Symbol###vd_convert")
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Always, {0.5, 0.5})
	if !imgui.BeginPopupModal("Convert to Symbol###vd_convert", nil, {.AlwaysAutoResize}) do return
	defer imgui.EndPopup()
	imgui.TextUnformatted("Name")
	if imgui.IsWindowAppearing() do imgui.SetKeyboardFocusHere()
	imgui.SetNextItemWidth(260)
	enter := imgui.InputText("##vdsymname", cstring(raw_data(vd.symbolBuf[:])), len(vd.symbolBuf), {.EnterReturnsTrue, .AutoSelectAll})
	Drive_Item("vd.convert.name")
	if enter || UI_PrimaryButton("Convert", "vd.convert.ok") {
		name := strings.trim_space(string(cstring(raw_data(vd.symbolBuf[:]))))
		if name != "" do convert_to_symbol(state, name)
		vd.askSymbol = false
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Cancel", "vd.convert.cancel") || imgui.IsKeyPressed(.Escape, false) {
		vd.askSymbol = false
		imgui.CloseCurrentPopup()
	}
}

// convert_to_symbol: the selected shapes into a new group (a symbol) where
// the first of them is, and a Vector Shape drawing it placed so it covers
// them exactly (the drawing node keeps drawing them too).
@(private = "file")
convert_to_symbol :: proc(state: ^EditorState, name: string) {
	v := vd.node
	r := e.VectorShapeNode_Asset(v)
	sel := vd_selection(r)
	if r == nil || len(sel) == 0 || state.activeScene == nil do return
	edit_begin(r)
	clean := e.Vector_DocGroupNameFree(&r.doc, name)
	parent := e.Vector_DocShapeGroup(&r.doc, sel[0])
	g := e.Vector_DocMakeGroup(&r.doc, sel, clean, parent)
	vd_select_only(-1)
	edit_commit(state, r, "Convert to Symbol")
	// The instance: same parent, rotation and scale; its own origin box.
	Editor_RecordUndo(state, fmt.tprintf("Convert to Symbol %s", clean))
	mgr := state.activeScene.manager
	scene := state.activeScene
	par := e.GetParent(mgr, &v.node)
	inst := cast(^e.VectorShapeNode)e.Node_CreateByTypeName(scene, "VectorShapeNode", par)
	if inst == nil do return
	inst.name = strings.clone(Editor_UniqueChildName(state, par, clean), inst.allocator)
	inst.file = strings.clone(v.file, inst.allocator)
	inst.group = strings.clone(e.Vector_GroupPath(r, g), inst.allocator)
	inst.gameContext = v.gameContext
	inst.rotation, inst.scale = v.rotation, v.scale
	e.ProcessNodeQueues(mgr, &state.game.gameContext)
	boxMin, boxSize := e.Vector_PartBox(r, g)
	offB := -boxMin - e.Node_OriginPx(inst, boxSize)
	// Where the original draws the box's origin point, the instance's position goes.
	world := doc_to_world(v, -offB)
	inst.position = Editor_WorldToLocal(par, world) if par != nil else world
	e.Node_SetGlobalPositions(mgr, scene.rootNode)
	Editor_Log(state, .Info, "Made symbol %s and placed %s", clean, inst.name)
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
	case "vd.layer":  return fmt.tprint(vd.layer), true
	case "vd.selected": return fmt.tprint(len(vd_selection(r))), true
	case "vd.scope":
		if r == nil do return "0", true
		lo, hi := vd_scope(r)
		return fmt.tprint(hi - lo), true
	case "vd.groups": return fmt.tprint(len(r.doc.groups) if r != nil else 0), true
	case "vd.stops":
		if p := grad_paint(r); p != nil do return fmt.tprint(p.stopCount), true
		return "0", true
	case "vd.grad":
		if p := grad_paint(r); p != nil do return fmt.tprintf("%.0f,%.0f", p.p1.x, p.p1.y) if p.kind == .Linear else fmt.tprintf("r%.0f", p.radius), true
		return "", true
	case "vd.layers":
		if r == nil do return "", true
		sb := strings.builder_make(context.temp_allocator)
		for gi, k in e.Vector_DocLayers(&r.doc) {
			if k > 0 do strings.write_string(&sb, ",")
			fmt.sbprintf(&sb, "%s%s", r.doc.groups[gi].name, "(hidden)" if r.doc.groups[gi].hidden else "")
		}
		return strings.to_string(sb), true
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
