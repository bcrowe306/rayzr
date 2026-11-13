package editor

import "core:fmt"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"
import rl "vendor:raylib"

// ============================================================================
// Advanced cameras in the editor (engine/docs/advanced_camera.md): node
// pickers for the target / path / limits in the Inspector, and in the
// viewport each camera's frame (where it would look now, at its zoom), the
// dead zone (Framed) and the limits.
// ============================================================================

// inspector_adv_camera: pickers (drop a node from the Scene panel too) and
// Make Active / Shake while simulating.
inspector_adv_camera :: proc(state: ^EditorState, c: ^e.AdvancedCameraNode) {
	if !UI_SectionHeader("Targets") do return
	if !UI_BeginProps("##advcam") do return
	adv_pick(state, c, "Follow Target", "insp.advcam.follow", &c.followTarget, nil)
	if c.followMode == .Group {
		UI_PropLabel("Add To Group")
		imgui.SetNextItemWidth(field_width())
		if imgui.BeginCombo("##advcam_group", "Add a node...") {
			adv_walk(state, c, nil, state.activeScene.rootNode, 0, proc(state: ^EditorState, c: ^e.AdvancedCameraNode, n: ^e.Node) {
				Editor_RecordUndo(state, "Camera group target")
				p := e.Node_RelativePath(state.activeScene.manager, c, n)
				c.followTargets = strings.clone(p if c.followTargets == "" else fmt.tprintf("%s, %s", c.followTargets, p), c.allocator)
			})
			imgui.EndCombo()
		}
		Drive_Item("insp.advcam.group")
	}
	if c.followMode == .Path do adv_pick(state, c, "Follow Path", "insp.advcam.path", &c.followPath, e.PathNode)
	if c.limitMode == .Node do adv_pick(state, c, "Limit Node", "insp.advcam.limit", &c.limitNode, nil)
	UI_EndProps()
	if state.isSimulating {
		if UI_Button(fmt.tprintf("%s  Make Active", ICON_FA_VIDEO), "insp.advcam.activate") {
			e.AdvCam_MakeActive(c, state.activeScene.manager)
		}
		UI_Tooltip("Raise its priority above the others: the host camera blends to it")
		imgui.SameLine()
		if UI_Button(fmt.tprintf("%s  Shake", ICON_FA_BOLT), "insp.advcam.shake") do e.AdvCam_AddTrauma(c, 0.6)
		UI_Tooltip("Add 0.6 trauma (try the shake settings)")
	} else {
		UI_DimText("The viewport shows its frame (where it would look now). In Simulate / the game the scene's camera shows the active one.")
	}
}

@(private = "file")
adv_set :: proc(state: ^EditorState, c: ^e.AdvancedCameraNode, field: ^string, n: ^e.Node) {
	Editor_RecordUndo(state, "Camera target")
	field^ = strings.clone(e.Node_RelativePath(state.activeScene.manager, c, n), c.allocator) if n != nil else ""
}

@(private = "file") advPickField: ^string // (the open combo's field and type, for its callback)
@(private = "file") advPickType: typeid

// adv_pick: a node combo writing a path string field.
@(private = "file")
adv_pick :: proc(state: ^EditorState, c: ^e.AdvancedCameraNode, label, id: string, field: ^string, only: typeid) {
	m := state.activeScene.manager
	UI_PropLabel(label)
	cur: ^e.Node
	if field^ != "" do cur = e.Node_ResolvePath(m, c, field^)
	preview := "None"
	if cur != nil do preview = cur.name
	else if field^ != "" do preview = fmt.tprintf("missing: %s", field^)
	imgui.SetNextItemWidth(field_width())
	if imgui.BeginCombo(fmt.ctprintf("##%s", id), strings.clone_to_cstring(preview, context.temp_allocator)) {
		if imgui.Selectable("None", cur == nil) do adv_set(state, c, field, nil)
		advPickField, advPickType = field, only
		adv_walk(state, c, cur, state.activeScene.rootNode, 0, proc(state: ^EditorState, c: ^e.AdvancedCameraNode, n: ^e.Node) {
			if advPickType != nil && n.typeId != advPickType {
				Editor_Log(state, .Warn, "%s is not a %v", n.name, advPickType)
				return
			}
			adv_set(state, c, advPickField, n)
		})
		imgui.EndCombo()
	}
	Drive_Item(id)
	if imgui.BeginDragDropTarget() {
		if payload := imgui.AcceptDragDropPayload("RAYZR_NODE"); payload != nil {
			n := (^^e.Node)(payload.Data)^
			if e.Node_IsAlive(n) && n != c && (only == nil || n.typeId == only) do adv_set(state, c, field, n)
		}
		imgui.EndDragDropTarget()
	}
	UI_Tooltip("Pick a node, or drop one from the Scene panel here")
}

@(private = "file")
adv_walk :: proc(state: ^EditorState, c: ^e.AdvancedCameraNode, cur, n: ^e.Node, depth: int, pick: proc(state: ^EditorState, c: ^e.AdvancedCameraNode, n: ^e.Node)) {
	for ch in e.GetChildrenView(state.activeScene.manager, n) {
		if ch == nil || ch.transient do continue
		if ch != c {
			label := fmt.ctprintf("%*s%s  %s##advpick_%p", depth * 2, "", Editor_NodeIcon(ch), ch.name, ch)
			if imgui.Selectable(label, ch == cur) do pick(state, c, ch)
			Drive_Item(fmt.tprintf("pick:%s", ch.name))
		}
		adv_walk(state, c, cur, ch, depth + 1, pick)
	}
}

// Viewport_DrawAdvancedCameras: each camera's frame (violet; brighter when
// selected or active), the dead zone and the limits of the selected one.
Viewport_DrawAdvancedCameras :: proc(state: ^EditorState) {
	if state.activeScene == nil do return
	ctx := &state.game.gameContext
	px := 1 / state.cameraZoom
	for n in state.activeScene.manager.advCameras {
		if Editor_ViewHidden(state, n) do continue
		c := cast(^e.AdvancedCameraNode)n
		sel := n == state.selectedNode
		center, zoom := c.lookAt, c.curZoom
		limits, hasLimits := c.limitCur, c.hasLimit
		if !state.isSimulating || !c.started do center, zoom, limits, hasLimits = e.AdvCam_Preview(c, ctx)
		view := e.AdvCam_ViewSize(ctx, zoom)
		r := rl.Rectangle{center.x - view.x / 2, center.y - view.y / 2, view.x, view.y}
		a: u8 = 230 if sel || c.active else 90
		col := rl.Color{167, 139, 250, a}
		rl.DrawRectangleLinesEx(r, (2.5 if c.active else 1.5) * px, col)
		rl.DrawCircleLinesV(center, 6 * px, col)
		if !c.enabled do continue
		Viewport_Label({r.x, r.y}, fmt.tprintf("%s  p%d%s", c.name, c.priority, " (active)" if c.active else ""), col, .Inside)
		if !sel do continue
		if c.followMode == .Framed {
			dz := view * c.deadZone
			rl.DrawRectangleLinesEx({center.x - dz.x / 2, center.y - dz.y / 2, dz.x, dz.y}, px, {167, 139, 250, 160})
		}
		if hasLimits {
			l := limits
			rl.DrawRectangleLinesEx({l[0], l[1], l[2] - l[0], l[3] - l[1]}, 2 * px, {244, 114, 182, 200})
		}
	}
}
