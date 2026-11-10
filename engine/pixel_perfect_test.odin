package engine

import "core:strings"
import "core:testing"
import rl "vendor:raylib"

// Pixel-perfect: integer scaling fits by a whole number, pixel snap puts the
// camera (with the leftover fraction recorded) and sprites on whole pixels,
// the smooth camera's margin shifts the camera, the settings round-trip.
@(test)
test_pixel_perfect :: proc(t: ^testing.T) {
	defer Render_SetPixelSettings({})
	defer renderPixel.margin = 0

	// Integer scaling: 320x180 in 1000x700 -> 3x (960x540), centred.
	Render_SetPixelSettings({integerScaling = true})
	testing.expect_value(t, Pixel_FitRect(320, 180, 1000, 700), rl.Rectangle{20, 80, 960, 540})
	// Smaller than the frame: still fits (not 0x).
	testing.expect_value(t, Pixel_FitRect(320, 180, 160, 90), rl.Rectangle{0, 0, 160, 90})
	Render_SetPixelSettings({})
	testing.expect_value(t, Pixel_FitRect(320, 180, 1000, 700), rl.Rectangle{0, 68.75 - 0.75, 1000, 562.5}) // fractional without it

	// Pixel snap: target to whole pixels at the zoom, the rest kept.
	Render_SetPixelSettings({snap = true, smooth = true})
	testing.expect(t, renderPixel.smooth, "smooth needs snap: on")
	cam := rl.Camera2D{offset = {160, 90}, target = {10.3, 20.75}, zoom = 2}
	Pixel_SnapCamera(&cam)
	testing.expect_value(t, cam.target, [2]f32{10.5, 21})          // 20.6 -> 21 px, 41.5 -> 42 px (/2)
	testing.expect(t, abs(renderPixel.frac.x - (-0.4)) < 0.001 && abs(renderPixel.frac.y - (-0.5)) < 0.001, "the leftover fraction")
	// The smooth camera's world texture: the offset moves by the margin.
	renderPixel.margin = PIXEL_MARGIN
	cam2 := rl.Camera2D{offset = {160, 90}, target = {0, 0}, zoom = 1}
	Pixel_SnapCamera(&cam2)
	testing.expect_value(t, cam2.offset, [2]f32{161, 91})
	renderPixel.margin = 0
	// Sprites: the top-left corner on a whole pixel; rotated ones untouched.
	testing.expect_value(t, Pixel_SnapSprite({10.4, 5.6}, {8, 8}, 0), [2]f32{10, 6})
	testing.expect_value(t, Pixel_SnapSprite({10.4, 5.6}, {8, 8}, 30), [2]f32{10.4, 5.6})
	Render_SetPixelSettings({smooth = true})
	testing.expect(t, !renderPixel.smooth, "smooth without snap: off")

	// The project settings: read, written, applied.
	cfg, ok := Project_ParseConfig(transmute([]u8)string(`{"name": "x", "initial_scene": "a.scene.json", "video": {"integer_scaling": true, "pixel_snap": true, "smooth_camera": true}}`))
	defer ProjectConfig_Destroy(&cfg)
	testing.expect(t, ok && cfg.integerScaling && cfg.pixelSnap && cfg.smoothCamera, "read")
	json := Project_SerializeToJSON(&cfg)
	defer delete(json)
	testing.expect(t, strings.contains(json, `"integer_scaling": true, "pixel_snap": true, "smooth_camera": true`), json)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	Game_LoadProjectConfig(game, &cfg, activate = false)
	testing.expect(t, renderPixel.integerScaling && renderPixel.snap && renderPixel.smooth, "applied")
}

// #409: snapping through the render target's transform, the followed node
// left out of the smooth camera's shift, per-node overrides, sharp scaling,
// Native text placement and the node settings saved.
@(test)
test_pixel_render_409 :: proc(t: ^testing.T) {
	defer Render_SetPixelSettings({})
	defer renderPixel.node = nil

	// Snapping on the target's pixels: at zoom 2 (camera at 0, offset 160)
	// a world x of 10.3 is 180.6 target px -> 181 -> 10.5 world.
	m := rl.Matrix{2, 0, 0, 160, 0, 2, 0, 90, 0, 0, 1, 0, 0, 0, 0, 1}
	testing.expect_value(t, Pixel_SnapPointIn({10.3, 5.1}, m), [2]f32{10.5, 5})
	// Identity: whole world pixels. Rotated transforms: left alone.
	testing.expect_value(t, Pixel_SnapPointIn({10.4, 5.6}, rl.Matrix(1)), [2]f32{10, 6})
	rot := rl.Matrix{0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
	testing.expect_value(t, Pixel_SnapPointIn({10.4, 5.6}, rot), [2]f32{10.4, 5.6})

	// The followed node stays still: the shift leaves out its own rounding.
	Render_SetPixelSettings({snap = true, smooth = true})
	cam := rl.Camera2D{offset = {160, 90}, target = {100.4, 50}, zoom = 1}
	Pixel_SnapCamera(&cam, [2]f32{100.4, 50})
	testing.expect_value(t, cam.target, [2]f32{100, 50})
	testing.expect(t, abs(renderPixel.frac.x) < 0.001, "locked on: no shift (the world steps with it)")
	// The camera lagging 0.3 behind a node at 100.6 (drawn at 101): the
	// shift puts the node where it really is on screen.
	cam = {offset = {160, 90}, target = {100.3, 50}, zoom = 1}
	Pixel_SnapCamera(&cam, [2]f32{100.6, 50})
	// camera 100 + 0.3, node 101 - 0.4: shown at 101 - 100 - frac = 100.6 - 100.3
	testing.expect(t, abs((101 - 100 - renderPixel.frac.x) - (100.6 - 100.3)) < 0.001, "the node where it is")
	cam = {offset = {160, 90}, target = {100.3, 50}, zoom = 1}
	Pixel_SnapCamera(&cam)
	testing.expect(t, abs(renderPixel.frac.x - 0.3) < 0.001, "no follow: the camera's own fraction")

	// Per node: Snap to Pixels over the project's; Inherit follows it.
	n := new(Node)
	defer free(n)
	Pixel_BeginNode(n)
	testing.expect(t, Pixel_Snaps(), "inherit: the project's snap (on)")
	n.pixelSnap = .Off
	testing.expect(t, !Pixel_Snaps(), "off")
	testing.expect_value(t, Pixel_SnapSprite({10.4, 5.6}, {8, 8}, 0), [2]f32{10.4, 5.6})
	Render_SetPixelSettings({})
	n.pixelSnap = .On
	testing.expect(t, Pixel_Snaps(), "on without the project's snap")
	n.pixelFilter = .Smooth
	f, over := Pixel_NodeFilter()
	testing.expect(t, over && f == .BILINEAR, "smooth filter")
	Pixel_EndNode()
	testing.expect(t, renderPixel.node == nil, "after the node")
	_, over = Pixel_NodeFilter()
	testing.expect(t, !over, "no node: inherit")

	// Sharp scaling: whole scales copy nearest-neighbour; fractional ones not.
	testing.expect(t, Pixel_IsWholeScale({0, 0, 1280, 720}, 320, 180), "4x")
	testing.expect(t, !Pixel_IsWholeScale({0, 0, 1000, 562.5}, 320, 180), "3.125x")
	testing.expect(t, Pixel_IsWholeScale({0, 0, 160, 90}, 320, 180), "smaller")

	// The smooth camera's world: moved by its margin and the leftover fraction.
	testing.expect_value(t, Pixel_WorldRect({20, 80, 960, 540}, 320, 180, 322, 182, {0.5, -0.25}), rl.Rectangle{20 - 1.5 * 3, 80 - 0.75 * 3, 966, 546})

	// Native text: kept only when the frame is shown bigger than it is.
	testing.expect(t, Pixel_NativeWanted({0, 0, 1280, 720}, 320, 180), "scaled up")
	testing.expect(t, !Pixel_NativeWanted({0, 0, 1280, 720}, 1280, 720), "1:1")
	// Where: a point the frame's transform put at (10, 20) lands at
	// dest + 4 x (10, 20); in the world texture, less the margin and fraction.
	tm := rl.Matrix{1, 0, 0, 10, 0, 1, 0, 20, 0, 0, 1, 0, 0, 0, 0, 1}
	w := Pixel_NativeTransform(tm, {0, 0, 1280, 720}, 320, 180, false, {})
	testing.expect_value(t, [2]f32{w[0, 3], w[1, 3]}, [2]f32{40, 80})
	testing.expect_value(t, w[0, 0], f32(4))
	w = Pixel_NativeTransform(tm, {0, 0, 1280, 720}, 320, 180, true, {0.25, 0})
	testing.expect_value(t, [2]f32{w[0, 3], w[1, 3]}, [2]f32{40 - 5, 80 - 4})
	// Defaults: UI nodes Native, text Pixel; the setting wins.
	ui := new(Node)
	defer free(ui)
	ui.isUI = true
	testing.expect(t, Pixel_IsNative(ui), "UI: Native")
	testing.expect(t, !Pixel_IsNative(n), "text / world: Pixel")
	ui.pixelText = .Pixel
	n.pixelText = .Native
	testing.expect(t, !Pixel_IsNative(ui) && Pixel_IsNative(n), "set")

	// Saved names round-trip; defaults are the old files' (absent) values.
	for f in Pixel_Filter do testing.expect_value(t, Pixel_FilterParse(Pixel_FilterName(f)), f)
	for s in Pixel_Snap do testing.expect_value(t, Pixel_SnapParse(Pixel_SnapName(s)), s)
	for x in Pixel_Text do testing.expect_value(t, Pixel_TextParse(Pixel_TextName(x)), x)
	testing.expect_value(t, Pixel_FilterParse(""), Pixel_Filter.Inherit)
}
