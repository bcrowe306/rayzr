package editor

import "core:fmt"
import "core:math"
import "core:slice"
import e "../engine"
import imgui "lib/imgui"
import rl "vendor:raylib"

// ============================================================================
// Viewport tools:
//   - Rulers along the top and left edge (world units, adaptive ticks, the
//     mouse position marked). Drag from a ruler to add a guide; drag a guide
//     to move it, back onto a ruler to remove it. Guides are saved with the
//     scene (Scene.guides).
//   - Smart snapping: a moved selection's edges / centre snap to other
//     nodes' edges / centres and to guides (magenta lines show the match).
//   - Pivot editing: Alt + drag the move handle moves the node's pivot; the
//     texture, children, line points and collision shapes stay in place.
//   - Per-node viewport lock and editor-only hide (Node.editorLocked /
//     editorHidden, children included).
//   - Show All Colliders: every body's, LDtk level's and tile map's
//     collision shapes, even when the project hides physics debug drawing.
// ============================================================================

RULER_SIZE :: 18
GUIDE_GRAB :: 4 // px either side of a guide line
SMART_SNAP_PX :: 7

Guide_Drag :: struct {
	active:   bool,
	vertical: bool,
	index:    int, // the dragged guide; -1: a new one from a ruler
	pos:      f32,
}

guideDrag: Guide_Drag

Smart_Snap :: struct {
	targets:      [2][dynamic]f32, // candidate lines per axis (world)
	selMin:       [2]f32,          // the moved bounds at drag start
	selMax:       [2]f32,
	line:         [2]f32,          // the matched lines, drawn while dragging
	has:          [2]bool,
}

smartSnap: Smart_Snap

// pivotDrag: the move handle is moving the pivot (Alt held at drag start).
pivotDrag: bool

// --- lock / hide -----------------------------------------------------------------------

// Editor_ViewLocked: the node or an ancestor is locked in the viewport.
Editor_ViewLocked :: proc(state: ^EditorState, node: ^e.Node) -> bool {
	if state.activeScene == nil do return false
	for n := node; n != nil; n = e.GetParent(state.activeScene.manager, n) {
		if n.editorLocked do return true
	}
	return false
}

// Editor_ViewHidden: the node or an ancestor is hidden in the editor.
Editor_ViewHidden :: proc(state: ^EditorState, node: ^e.Node) -> bool {
	if state.activeScene == nil do return false
	for n := node; n != nil; n = e.GetParent(state.activeScene.manager, n) {
		if n.editorHidden do return true
	}
	return false
}

Editor_ToggleViewLock :: proc(state: ^EditorState) {
	roots := Editor_SelectionRoots(state)
	if len(roots) == 0 do return
	Editor_RecordUndo(state, "Toggle lock")
	on := !roots[0].editorLocked
	for n in roots do n.editorLocked = on
}

Editor_ToggleViewHidden :: proc(state: ^EditorState) {
	roots := Editor_SelectionRoots(state)
	if len(roots) == 0 do return
	Editor_RecordUndo(state, "Toggle hidden in editor")
	on := !roots[0].editorHidden
	for n in roots do n.editorHidden = on
}

// --- rulers and guides -------------------------------------------------------------------

// ruler_step: world units between labelled ticks (1, 2 or 5 x 10^n), at
// least ~70 px apart on screen.
ruler_step :: proc(zoom: f32) -> f32 {
	want := 70 / max(zoom, 0.0001)
	p := math.pow(10, math.floor(math.log10(want)))
	for m in ([]f32{1, 2, 5, 10}) do if p * m >= want do return p * m
	return p * 10
}

@(private = "file")
on_ruler :: proc(state: ^EditorState, p: [2]f32) -> (over: bool, vertical: bool) {
	if !state.showRulers do return false, false
	vp, vs := state.viewportPos, state.viewportSize
	if p.x < vp.x || p.y < vp.y || p.x > vp.x + vs.x || p.y > vp.y + vs.y do return false, false
	if p.y < vp.y + RULER_SIZE do return true, false // top ruler: horizontal guides
	if p.x < vp.x + RULER_SIZE do return true, true  // left ruler: vertical guides
	return false, false
}

@(private = "file")
draw_guide_line :: proc(state: ^EditorState, dl: ^imgui.DrawList, vertical: bool, pos: f32, col: u32) {
	vp, vs := state.viewportPos, state.viewportSize
	s := Viewport_WorldToScreen(state, {pos, pos})
	if vertical {
		if s.x < vp.x || s.x > vp.x + vs.x do return
		imgui.DrawList_AddLine(dl, {s.x, vp.y}, {s.x, vp.y + vs.y}, col, 1)
	} else {
		if s.y < vp.y || s.y > vp.y + vs.y do return
		imgui.DrawList_AddLine(dl, {vp.x, s.y}, {vp.x + vs.x, s.y}, col, 1)
	}
}

// ruler_text draws a ruler number at whole pixels in the ruler font at its
// own size (scaled small text was blurry); vertical: rotated to read
// upwards, ending at `pos`.
@(private = "file")
ruler_text :: proc(dl: ^imgui.DrawList, pos: [2]f32, col: u32, text: cstring, vertical: bool) {
	font := GlobalFonts.ruler if GlobalFonts.ruler != nil else GlobalFonts.small
	size := font.FontSize if font != nil else 11
	p := [2]f32{math.round(pos.x), math.round(pos.y)}
	start := dl.VtxBuffer.Size
	imgui.DrawList_AddTextImFontPtr(dl, font, size, p, col, text)
	if !vertical do return
	// Rotate the new glyphs -90 degrees about p: (x, y) -> (p.x + (y - p.y), p.y - (x - p.x)).
	verts := ([^]imgui.DrawVert)(dl.VtxBuffer.Data)
	for k in start ..< dl.VtxBuffer.Size {
		v := &verts[k]
		dx, dy := v.pos.x - p.x, v.pos.y - p.y
		v.pos = {p.x + dy, p.y - dx}
	}
}

@(private = "file")
draw_rulers :: proc(state: ^EditorState, dl: ^imgui.DrawList, mouseScreen: [2]f32) {
	vp, vs := state.viewportPos, state.viewportSize
	R :: f32(RULER_SIZE)
	bg := col_u32({UI_BG_APP.x, UI_BG_APP.y, UI_BG_APP.z, 0.94})
	tickCol := col_u32(UI_TEXT_FAINT)
	textCol := col_u32(UI_TEXT_DIM)
	edge := col_u32(ui_line(0.12))
	imgui.DrawList_AddRectFilled(dl, {vp.x, vp.y}, {vp.x + vs.x, vp.y + R}, bg)
	imgui.DrawList_AddRectFilled(dl, {vp.x, vp.y + R}, {vp.x + R, vp.y + vs.y}, bg)
	imgui.DrawList_AddLine(dl, {vp.x + R, vp.y + R}, {vp.x + vs.x, vp.y + R}, edge)
	imgui.DrawList_AddLine(dl, {vp.x + R, vp.y + R}, {vp.x + R, vp.y + vs.y}, edge)

	step := ruler_step(state.cameraZoom)
	lead := step / math.pow(10, math.floor(math.log10(step)))
	minor := step / (4 if lead == 2 else 5)
	label :: proc(v: f32) -> cstring {
		if abs(v - math.round(v)) < 0.001 do return fmt.ctprintf("%d", int(math.round(v)))
		return fmt.ctprintf("%.1f", v)
	}

	// Top: x, the number right of its tick.
	x0 := Viewport_ScreenToWorld(state, {vp.x + R, 0}).x
	x1 := Viewport_ScreenToWorld(state, {vp.x + vs.x, 0}).x
	for i := int(math.floor(x0 / minor)); f32(i) * minor <= x1; i += 1 {
		x := f32(i) * minor
		s := math.round(Viewport_WorldToScreen(state, {x, 0}).x) + 0.5
		if s < vp.x + R do continue
		major := abs(x / step - math.round(x / step)) < 0.001
		h := R * (0.5 if major else 0.22)
		imgui.DrawList_AddLine(dl, {s, vp.y + R - h}, {s, vp.y + R}, tickCol)
		if major do ruler_text(dl, {s + 3, vp.y + 2}, textCol, label(x), false)
	}
	// Left: y, the number above its tick, reading upwards.
	y0 := Viewport_ScreenToWorld(state, {0, vp.y + R}).y
	y1 := Viewport_ScreenToWorld(state, {0, vp.y + vs.y}).y
	for i := int(math.floor(y0 / minor)); f32(i) * minor <= y1; i += 1 {
		y := f32(i) * minor
		s := math.round(Viewport_WorldToScreen(state, {0, y}).y) + 0.5
		if s < vp.y + R do continue
		major := abs(y / step - math.round(y / step)) < 0.001
		h := R * (0.5 if major else 0.22)
		imgui.DrawList_AddLine(dl, {vp.x + R - h, s}, {vp.x + R, s}, tickCol)
		if major do ruler_text(dl, {vp.x + 2, s - 3}, textCol, label(y), true)
	}
	// The mouse position.
	if mouseScreen.x > vp.x + R && mouseScreen.x < vp.x + vs.x && mouseScreen.y > vp.y && mouseScreen.y < vp.y + vs.y {
		accent := col_u32(UI_ACCENT)
		imgui.DrawList_AddLine(dl, {mouseScreen.x, vp.y}, {mouseScreen.x, vp.y + R}, accent)
		imgui.DrawList_AddLine(dl, {vp.x, mouseScreen.y}, {vp.x + R, mouseScreen.y}, accent)
	}
	// Corner.
	imgui.DrawList_AddRectFilled(dl, {vp.x, vp.y}, {vp.x + R, vp.y + R}, col_u32(UI_BG_APP))
	imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, 11, {vp.x + 3, vp.y + 3}, textCol, ICON_FA_RULER_COMBINED)
}

// Viewport_Guides draws the rulers, guides and smart-snap lines over the
// viewport image and handles guide dragging; true while it owns the mouse
// (no picking or gizmo underneath).
Viewport_Guides :: proc(state: ^EditorState, dl: ^imgui.DrawList, mouseScreen, mouseWorld: [2]f32) -> bool {
	scene := state.activeScene
	owns := false
	guideCol := col32(0, 206, 201, 200)

	if scene != nil {
		for g, i in scene.guides[:scene.guideCount] {
			if guideDrag.active && guideDrag.index == i do continue
			draw_guide_line(state, dl, g.vertical, g.pos, guideCol)
		}
	}
	// Smart-snap matches while moving.
	if state.isDraggingGizmo {
		snapCol := col32(255, 64, 160, 230)
		if smartSnap.has[0] do draw_guide_line(state, dl, true, smartSnap.line[0], snapCol)
		if smartSnap.has[1] do draw_guide_line(state, dl, false, smartSnap.line[1], snapCol)
	}

	idle := !guideDrag.active && !state.isDraggingGizmo && !state.boxSelecting && state.toolMode != .Pan
	// Grab a guide.
	if scene != nil && idle && state.viewportHovered && state.activeHandle == .None {
		for g, i in scene.guides[:scene.guideCount] {
			s := Viewport_WorldToScreen(state, {g.pos, g.pos})
			d := abs(mouseScreen.x - s.x) if g.vertical else abs(mouseScreen.y - s.y)
			if d > GUIDE_GRAB do continue
			imgui.SetMouseCursor(.ResizeEW if g.vertical else .ResizeNS)
			owns = true
			if imgui.IsMouseClicked(.Left) {
				Editor_RecordUndo(state, "Move guide")
				guideDrag = {true, g.vertical, i, g.pos}
			}
			break
		}
	}
	if state.showRulers {
		draw_rulers(state, dl, mouseScreen)
		Drive_ItemRect("viewport.ruler.top", state.viewportPos + {RULER_SIZE, 0}, state.viewportPos + {state.viewportSize.x, RULER_SIZE})
		Drive_ItemRect("viewport.ruler.left", state.viewportPos + {0, RULER_SIZE}, state.viewportPos + {RULER_SIZE, state.viewportSize.y})
		if over, vertical := on_ruler(state, mouseScreen); over && idle && state.viewportHovered {
			owns = true
			if imgui.IsMouseClicked(.Left) && scene != nil && scene.guideCount < e.SCENE_MAX_GUIDES {
				guideDrag = {true, vertical, -1, 0}
			}
		}
	}

	if guideDrag.active && scene != nil {
		owns = true
		pos := mouseWorld.x if guideDrag.vertical else mouseWorld.y
		if state.snapGrid && state.gridSize > 0 {
			pos = math.round(pos / state.gridSize) * state.gridSize
		} else {
			pos = math.round(pos)
		}
		guideDrag.pos = pos
		vp, vs := state.viewportPos, state.viewportSize
		inside := mouseScreen.x >= vp.x && mouseScreen.y >= vp.y && mouseScreen.x <= vp.x + vs.x && mouseScreen.y <= vp.y + vs.y
		onRuler, _ := on_ruler(state, mouseScreen)
		drop := onRuler || !inside
		if guideDrag.index >= 0 && guideDrag.index < scene.guideCount do scene.guides[guideDrag.index].pos = pos
		draw_guide_line(state, dl, guideDrag.vertical, pos, col32(0, 206, 201, 90) if drop else col32(0, 230, 225, 255))
		imgui.SetMouseCursor(.ResizeEW if guideDrag.vertical else .ResizeNS)
		imgui.SetTooltip("%s", fmt.ctprintf("Release to remove" if drop else "%s = %v", "x" if guideDrag.vertical else "y", pos))
		if !imgui.IsMouseDown(.Left) {
			if guideDrag.index >= 0 {
				if drop do guide_remove(scene, guideDrag.index)
			} else if !drop {
				Editor_RecordUndo(state, "Add guide")
				scene.guides[scene.guideCount] = {guideDrag.vertical, pos}
				scene.guideCount += 1
			}
			guideDrag = {}
		}
	}
	return owns
}

@(private = "file")
guide_remove :: proc(scene: ^e.Scene, index: int) {
	for i in index ..< scene.guideCount - 1 do scene.guides[i] = scene.guides[i + 1]
	scene.guideCount -= 1
}

Editor_ClearGuides :: proc(state: ^EditorState) {
	if state.activeScene == nil || state.activeScene.guideCount == 0 do return
	Editor_RecordUndo(state, "Clear guides")
	state.activeScene.guideCount = 0
}

// --- smart snapping ------------------------------------------------------------------------

// SmartSnap_Begin collects the lines a drag can snap to: the edges and
// centres of the other visible nodes (for a pivot drag also the node's own)
// and the guides.
SmartSnap_Begin :: proc(state: ^EditorState, pivot: bool) {
	for &t in smartSnap.targets do clear(&t)
	smartSnap.has = {}
	scene := state.activeScene
	if !state.smartSnap || scene == nil do return
	mgr := scene.manager
	roots := Editor_SelectionRoots(state)
	moving :: proc(mgr: ^e.NodeManager, n: ^e.Node, roots: []^e.Node) -> bool {
		for p := n; p != nil; p = e.GetParent(mgr, p) do if slice.contains(roots, p) do return true
		return false
	}
	if pivot && state.selectedNode != nil {
		p := state.selectedNode.globalPosition
		smartSnap.selMin, smartSnap.selMax = p, p
	} else {
		first := true
		for n in roots {
			q, _ := Node_Bounds(state, n)
			mn, mx := q[0], q[0]
			for c in q {
				mn = {min(mn.x, c.x), min(mn.y, c.y)}
				mx = {max(mx.x, c.x), max(mx.y, c.y)}
			}
			if first {
				smartSnap.selMin, smartSnap.selMax = mn, mx
				first = false
			} else {
				smartSnap.selMin = {min(smartSnap.selMin.x, mn.x), min(smartSnap.selMin.y, mn.y)}
				smartSnap.selMax = {max(smartSnap.selMax.x, mx.x), max(smartSnap.selMax.y, mx.y)}
			}
		}
	}
	for n in mgr.nodes {
		if n == nil || n == scene.rootNode || n.transient || !n.enabled || !e.Node_VisibleInTree(n) || n.typeId == e.CameraNode do continue
		if Editor_ViewHidden(state, n) do continue
		if !(pivot && n == state.selectedNode) && moving(mgr, n, roots) do continue
		q, isHandle := Node_Bounds(state, n)
		if isHandle {
			for a in 0 ..< 2 do append(&smartSnap.targets[a], n.globalPosition[a])
			continue
		}
		mn, mx := q[0], q[0]
		for p in q {
			mn = {min(mn.x, p.x), min(mn.y, p.y)}
			mx = {max(mx.x, p.x), max(mx.y, p.y)}
		}
		for a in 0 ..< 2 do append(&smartSnap.targets[a], mn[a], (mn[a] + mx[a]) * 0.5, mx[a])
	}
	for g in scene.guides[:scene.guideCount] do append(&smartSnap.targets[0 if g.vertical else 1], g.pos)
}

// SmartSnap_Apply moves `world` (the primary node's new position; it started
// at `start`) so the moved bounds' nearest edge / centre lands on a target
// line within a few pixels. Returns the axes that snapped.
SmartSnap_Apply :: proc(state: ^EditorState, start: [2]f32, world: ^[2]f32, axes: [2]bool) -> (snapped: [2]bool) {
	smartSnap.has = {}
	if !state.smartSnap do return
	d := world^ - start
	thr := SMART_SNAP_PX / max(state.cameraZoom, 0.0001)
	for a in 0 ..< 2 {
		if !axes[a] do continue
		lines := [3]f32{smartSnap.selMin[a] + d[a], (smartSnap.selMin[a] + smartSnap.selMax[a]) * 0.5 + d[a], smartSnap.selMax[a] + d[a]}
		best := thr
		diff: f32
		for t in smartSnap.targets[a] {
			for l in lines {
				if abs(t - l) < best {
					best = abs(t - l)
					diff = t - l
					smartSnap.line[a] = t
					snapped[a] = true
				}
			}
		}
		if snapped[a] {
			world[a] += diff
			smartSnap.has[a] = true
		}
	}
	return
}

// --- pivot ------------------------------------------------------------------------------

// Pivot_MoveTo puts a node's pivot (its position) at a world point without
// moving what it shows: children, the origin of what it draws, a line's
// points and collision shapes shift back by the same amount.
Pivot_MoveTo :: proc(state: ^EditorState, node: ^e.Node, world: [2]f32) {
	mgr := state.activeScene.manager
	delta := world - node.globalPosition
	if delta == {} do return
	// The move in the node's own (unscaled, unrotated) space.
	r := -node.globalRotation * math.RAD_PER_DEG
	c, s := math.cos(r), math.sin(r)
	local := [2]f32{delta.x * c - delta.y * s, delta.x * s + delta.y * c}
	sc := node.globalScale
	local = {local.x / (sc.x if sc.x != 0 else 1), local.y / (sc.y if sc.y != 0 else 1)}

	node.position = e.Node_WorldToParent(mgr, node, world)
	node.globalPosition = world
	for child in e.GetChildrenView(mgr, node) do if child != nil do child.position -= local

	// The origin moves with it: by the same amount, as a fraction of the
	// drawn size (node_origin.odin).
	if e.Node_HasOrigin(node) {
		if size := e.Node_OriginSize(node, &state.game.gameContext); size.x > 0 && size.y > 0 {
			e.Node_SetOriginPx(node, e.Node_OriginPx(node, size) + local, size)
		}
	}
	switch node.typeId {
	case e.LineNode:
		for &p in (cast(^e.LineNode)node).points do p -= local
	case e.PathNode:
		for &p in (cast(^e.PathNode)node).points do p.pos -= local
	}
	if shapes := node_shapes_editor(node); shapes != nil {
		for &sh in shapes^ do sh.offset -= local
	}
}

// --- colliders ------------------------------------------------------------------------------

// Viewport_DrawAllColliders: every collision shape in the scene (inside
// BeginMode2D), when View > Show All Colliders is on.
Viewport_DrawAllColliders :: proc(state: ^EditorState) {
	if !state.showAllColliders || state.activeScene == nil do return
	// The bodies draw their own shapes when physics debug drawing is on.
	if state.game.physicsWorld.drawPhysicsDebug do return
	for n in state.activeScene.manager.nodes {
		if n == nil || !n.enabled do continue
		shapes := node_shapes_editor(n)
		if shapes == nil do continue
		col := rl.Color{74, 222, 128, 220}
		switch n.typeId {
		case e.DynamicBodyNode: col = {96, 165, 250, 220}
		case e.KinematicBodyNode: col = {56, 189, 248, 220}
		case e.AreaNode: col = {250, 204, 21, 200}
		}
		for &sh in shapes^ do e.PhysicsShape_DrawDebug(&sh, n.globalPosition, n.globalRotation, col, n.globalScale)
	}
}
