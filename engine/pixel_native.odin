package engine

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// Native text and UI (#409): when the game's frame is scaled up to the
// window (a low virtual resolution), text and UI nodes set to Native - UI
// nodes by default - aren't drawn into the frame (where their text came out
// blocky and soft); they're kept with the transform they'd have drawn under
// and drawn after the frame is on the window, at its resolution, scaled by
// the same amount and in the same place (text then draws from its distance
// field: sharp). They draw over the whole frame, in their order; world-layer
// ones follow the camera, as the world on screen does.
//
// Not Native: a node drawn into a Viewport's picture, while a scene
// transition runs (its pictures are of the frame), in the editor, and
// nodes that clip with a scissor rectangle (list and tree views: raylib's
// scissor doesn't follow a transform) unless set to Native.
// ============================================================================

Pixel_NativeItem :: struct {
	node:  ^Node,
	m:     rl.Matrix, // the frame's transform it would have drawn under
	world: bool,      // drawn into the smooth camera's world texture (moved with it)
}

Pixel_NativeState :: struct {
	active: bool,                  // this frame keeps Native nodes for later (runner)
	frame:  ^rl.RenderTexture2D,   // the frame they'd have drawn into
	items:  [dynamic]Pixel_NativeItem,
}

// Pixel_NativeBegin (runner, before the frame draws): Native nodes are kept
// when the frame (vw x vh) is shown bigger than it is at dest.
Pixel_NativeBegin :: proc(frame: ^rl.RenderTexture2D, dest: rl.Rectangle, vw, vh: f32, transition: bool) {
	n := &renderPixel.native
	if n.items == nil do n.items = make([dynamic]Pixel_NativeItem, 0, 32, Engine_HeapAllocator())
	clear(&n.items)
	n.frame = frame
	n.active = Pixel_NativeWanted(dest, vw, vh) && !transition
}

// Pixel_NativeWanted: the frame is scaled up on the window (else drawing
// into it is drawing at the window's resolution already).
Pixel_NativeWanted :: proc(dest: rl.Rectangle, vw, vh: f32) -> bool {
	return vw > 0 && vh > 0 && (dest.width > vw * 1.01 || dest.height > vh * 1.01)
}

// Pixel_IsNative: whether a node draws at the window's resolution (its Text
// Pixels setting; Default: UI nodes yes, text no, clipping UI no).
Pixel_IsNative :: proc(node: ^Node) -> bool {
	switch node.pixelText {
	case .Native: return true
	case .Pixel: return false
	case .Default:
	}
	if !node.isUI do return false
	switch node.typeId {
	case UITreeViewNode, UIUnorderedListNode, UIOrderedListNode: return false // (scissor-clipped)
	}
	return true
}

// Pixel_NativeTakes (render_bucket): a Native node is kept for the window
// pass instead of drawing now - true when it was.
Pixel_NativeTakes :: proc(node: ^Node) -> bool {
	n := &renderPixel.native
	if !n.active || !rl.IsWindowReady() do return false
	t := Render_FrameTarget()
	if t == nil || (t != n.frame && t != &renderPixel.world) do return false // (a viewport's picture)
	if !Pixel_IsNative(node) do return false
	append(&n.items, Pixel_NativeItem{node = node, m = rlgl.GetMatrixModelview(), world = t == &renderPixel.world})
	return true
}

// Pixel_NativeTransform: the window transform for a node kept under m - the
// frame at dest (vw x vh game pixels), the world moved as the smooth
// camera's world is (its margin and the camera's leftover fraction).
Pixel_NativeTransform :: proc(m: rl.Matrix, dest: rl.Rectangle, vw, vh: f32, world: bool, frac: [2]f32) -> rl.Matrix {
	sx, sy := dest.width / vw, dest.height / vh
	ox, oy := dest.x, dest.y
	if world {
		ox -= (f32(PIXEL_MARGIN) + frac.x) * sx
		oy -= (f32(PIXEL_MARGIN) + frac.y) * sy
	}
	s := rl.Matrix{
		sx, 0, 0, ox,
		0, sy, 0, oy,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}
	return s * m
}

// Pixel_DrawNative (runner, on the window after the frame): the kept nodes.
Pixel_DrawNative :: proc(gameContext: ^GameContext, dest: rl.Rectangle, vw, vh: f32) {
	n := &renderPixel.native
	defer {
		clear(&n.items)
		n.active = false
	}
	if len(n.items) == 0 do return
	rlgl.DrawRenderBatchActive()
	prev := rlgl.GetMatrixModelview()
	defer {
		rlgl.DrawRenderBatchActive()
		rlgl.SetMatrixModelview(prev)
	}
	last: rl.Matrix
	have := false
	for it in n.items {
		if !Node_IsAlive(it.node) do continue
		m := Pixel_NativeTransform(it.m, dest, vw, vh, it.world, renderPixel.frac)
		if !have || m != last {
			rlgl.DrawRenderBatchActive() // (the modelview goes with the batch)
			rlgl.SetMatrixModelview(m)
			last, have = m, true
		}
		Render_DrawNode(it.node, gameContext, 0)
	}
}

// Pixel_NativeRelease frees the list (window closing).
Pixel_NativeRelease :: proc() {
	delete(renderPixel.native.items)
	renderPixel.native = {}
}
