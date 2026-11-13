package editor

import "core:strings"
import imgui "lib/imgui"
import rl "vendor:raylib"

// ============================================================================
// Viewport labels: the names on camera frames, the Expand frame, camera
// limits, Advanced Cameras and LDtk entities. Drawn over the scene in the
// editor's font at one size on screen (not in the world: they don't grow
// when zoomed in), only while the toolbar's Labels toggle is on
// (GlobalSettings.viewportLabels), and faint under the mouse so they never
// hide what's being edited.
//
// The world pass (Viewport_RenderOffscreen) queues them; Viewport_DrawLabels
// draws them after the scene's image.
// ============================================================================

Label_Place :: enum u8 {
	Above, // its bottom-left at the point (over a frame's top-left corner)
	Below, // its top-left at the point (under a frame's bottom-left corner)
	Inside, // its top-left at the point, a little in (inside a frame)
}

Viewport_LabelItem :: struct {
	world: [2]f32,
	text:  string, // (temp)
	col:   rl.Color,
	place: Label_Place,
	badge: bool, // on a dark pill with a coloured border (else text on a faint shadow)
	span:  f32,  // (world) how far the thing named goes down from the point: its label stays in view while it does
}

@(private = "file")
viewportLabels: [dynamic]Viewport_LabelItem

// Viewport_Label: a label at a world point, this frame.
Viewport_Label :: proc(world: [2]f32, text: string, col: rl.Color, place := Label_Place.Above, badge := false, span: f32 = 0) {
	if !GlobalSettings.viewportLabels || text == "" do return
	append(&viewportLabels, Viewport_LabelItem{world, strings.clone(text, context.temp_allocator), col, place, badge, span})
}

@(private = "file")
labelsDrawn: int

// Viewport_LabelCount: the labels drawn last frame (drives).
Viewport_LabelCount :: proc() -> int {return labelsDrawn}

@(private = "file")
LABEL_PAD :: [2]f32{5, 2}

// Viewport_DrawLabels: the queued labels over the viewport image, then the
// queue is emptied.
Viewport_DrawLabels :: proc(state: ^EditorState) {
	labelsDrawn = len(viewportLabels)
	defer clear(&viewportLabels)
	if len(viewportLabels) == 0 do return
	dl := imgui.GetWindowDrawList()
	if dl == nil do return
	mn, mx := state.viewportPos, state.viewportPos + state.viewportSize
	// (Inside the rulers: they're drawn over the scene.)
	inner := mn + ({RULER_SIZE, RULER_SIZE} if state.showRulers else {0, 0})
	imgui.DrawList_PushClipRect(dl, mn, mx, true)
	defer imgui.DrawList_PopClipRect(dl)
	mouse := imgui.GetIO().MousePos
	for &l in viewportLabels {
		text := strings.clone_to_cstring(l.text, context.temp_allocator)
		size := imgui.CalcTextSize(text)
		box := size + LABEL_PAD * 2
		p := Viewport_WorldToScreen(state, l.world)
		switch l.place {
		case .Above:  p.y -= box.y
		case .Below:  p.y += 2
		case .Inside: p += {3, 3}
		}
		// Kept on screen along x (a frame wider than the view still shows its
		// name), and below the top while what it names goes on down the view.
		p.x = clamp(p.x, inner.x, max(inner.x, mx.x - box.x))
		if p.y < inner.y && Viewport_WorldToScreen(state, l.world).y + l.span * state.cameraZoom > inner.y + box.y * 2 do p.y = inner.y
		if p.y + box.y < mn.y || p.y > mx.y || p.x > mx.x do continue
		// Under the mouse: faint, so the node behind can be seen and picked.
		fade: f32 = 1
		if mouse.x >= p.x && mouse.x <= p.x + box.x && mouse.y >= p.y && mouse.y <= p.y + box.y do fade = 0.2
		alpha :: proc(a: u8, f: f32) -> u32 {return u32(f32(a) * f)}
		c := l.col
		if l.badge {
			imgui.DrawList_AddRectFilled(dl, p, p + box, col32(18, 22, 30, alpha(225, fade)), 3)
			imgui.DrawList_AddRect(dl, p, p + box, col32(u32(c.r), u32(c.g), u32(c.b), alpha(c.a, fade)), 3)
			imgui.DrawList_AddText(dl, p + LABEL_PAD, col32(240, 243, 248, alpha(255, fade)), text)
		} else {
			imgui.DrawList_AddText(dl, p + LABEL_PAD + {1, 1}, col32(0, 0, 0, alpha(160, fade)), text)
			imgui.DrawList_AddText(dl, p + LABEL_PAD, col32(u32(c.r), u32(c.g), u32(c.b), alpha(max(c.a, 200), fade)), text)
		}
	}
}
