package engine

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// Pixel-perfect rendering (project Video settings; docs/pixel_perfect.md).
//
// - Integer scaling: the frame is scaled to the window by a whole number
//   (bars around it) - every game pixel is the same size on screen.
// - Pixel snap: the camera and the sprites sit on whole game pixels (no
//   shimmering, no uneven pixels on scaled or moving sprites).
// - Smooth camera (with pixel snap): the world is drawn snapped into a
//   texture one pixel larger on every side; the final upscale moves it by
//   the camera's leftover fraction of a pixel, at screen resolution - slow
//   pans glide instead of stepping a whole game pixel at a time. UI layers
//   (those the camera doesn't draw) go to the frame on top, unshifted.
//   While the camera follows a node, the shift leaves out that node's own
//   rounding: the node it is locked on stays still (#409).
// - Fit (no integer scaling) with Sharp Pixels: the frame is scaled up with
//   the sharp-bilinear shader - every game pixel the same size to within a
//   screen pixel (soft only on its edges), no uneven columns (#409).
// - Per node (#409): Texture Filter (Inherit / Sharp / Smooth) and Snap to
//   Pixels (Inherit / On / Off) override the textures' import filter and
//   the project's pixel snap; Text Pixels (Native / Pixel) draws text and UI
//   crisp at the window's resolution over the scaled frame, or inside it.
// ============================================================================

// Pixel_Filter: a node's texture filter (Inherit: its textures' import setting).
Pixel_Filter :: enum u8 {
	Inherit,
	Sharp,  // nearest-neighbour (pixel art)
	Smooth, // bilinear
}

// Pixel_Snap: a node's snapping to whole pixels (Inherit: the project's Pixel Snap).
Pixel_Snap :: enum u8 {
	Inherit,
	On,
	Off,
}

// Pixel_Text: where a text / UI node is drawn when the frame is scaled up.
Pixel_Text :: enum u8 {
	Default, // UI nodes Native, world text (TextNode) Pixel
	Native,  // at the window's resolution, over the scaled frame (crisp)
	Pixel,   // inside the virtual resolution, scaled with the game's pixels
}

Pixel_FilterName :: proc(f: Pixel_Filter) -> string {
	switch f {
	case .Sharp: return "sharp"
	case .Smooth: return "smooth"
	case .Inherit:
	}
	return "inherit"
}
Pixel_FilterParse :: proc(s: string) -> Pixel_Filter {
	switch s {
	case "sharp": return .Sharp
	case "smooth": return .Smooth
	}
	return .Inherit
}
Pixel_SnapName :: proc(m: Pixel_Snap) -> string {
	switch m {
	case .On: return "on"
	case .Off: return "off"
	case .Inherit:
	}
	return "inherit"
}
Pixel_SnapParse :: proc(s: string) -> Pixel_Snap {
	switch s {
	case "on": return .On
	case "off": return .Off
	}
	return .Inherit
}
Pixel_TextName :: proc(m: Pixel_Text) -> string {
	switch m {
	case .Native: return "native"
	case .Pixel: return "pixel"
	case .Default:
	}
	return "default"
}
Pixel_TextParse :: proc(s: string) -> Pixel_Text {
	switch s {
	case "native": return .Native
	case "pixel": return .Pixel
	}
	return .Default
}

Render_Pixel_Settings :: struct {
	integerScaling: bool,
	snap:           bool,
	smooth:         bool, // needs snap
}

renderPixel: struct {
	using settings: Render_Pixel_Settings,
	frac:     [2]f32, // the camera's leftover (game px) after snapping, this frame
	margin:   f32,    // 1 while the world draws into worldTarget (the camera's offset)
	world:    rl.RenderTexture2D, // the smooth camera's world (virtual size + 2)
	usedWorld: bool,              // the world went to `world` this frame (the runner composites it)
	node:     ^Node,              // the node drawing now (render_bucket): its overrides
	worldSnap: bool,              // snap to whole world units, not the target's pixels (the editor's zoomed viewport: game pixels)
	native:   Pixel_NativeState,  // Native text / UI this frame (pixel_native.odin)
}

PIXEL_MARGIN :: 1

// Pixel_SetWorldSnap (the editor): snap to whole world units - the game's
// pixels - however far the viewport is zoomed in.
Pixel_SetWorldSnap :: proc(on: bool) {renderPixel.worldSnap = on}

// Render_SetPixelSettings applies the project's settings (Game_LoadProjectConfig).
Render_SetPixelSettings :: proc(s: Render_Pixel_Settings) {
	renderPixel.settings = s
	renderPixel.smooth = s.smooth && s.snap
}

// Pixel_SnapCamera puts a camera's target on a whole game pixel (at its
// zoom) and records what was left over for the smooth camera.
// `follow`: the position of the node the camera is locked on (snapped
// itself) - the smooth camera's shift leaves out that node's own rounding,
// so it stays still on screen while the world steps with it (#409: else it
// went back and forth by up to a game pixel every few frames).
Pixel_SnapCamera :: proc(cam: ^rl.Camera2D, follow: Maybe([2]f32) = nil) {
	cam.offset += renderPixel.margin
	if !renderPixel.snap do return
	z := cam.zoom if cam.zoom > 0.0001 else 1
	px := cam.target * z
	snapped := [2]f32{math.round(px.x), math.round(px.y)}
	renderPixel.frac = px - snapped
	if p, ok := follow.?; ok {
		fp := p * z
		renderPixel.frac -= fp - {math.round(fp.x), math.round(fp.y)}
		renderPixel.frac = {clamp(renderPixel.frac.x, -PIXEL_MARGIN, PIXEL_MARGIN), clamp(renderPixel.frac.y, -PIXEL_MARGIN, PIXEL_MARGIN)}
	}
	cam.target = snapped / z
	cam.offset = {math.round(cam.offset.x), math.round(cam.offset.y)}
}

// Pixel_Snaps: whether what draws now snaps to whole pixels - the drawing
// node's Snap to Pixels, else the project's Pixel Snap.
Pixel_Snaps :: #force_inline proc() -> bool {
	if n := renderPixel.node; n != nil {
		switch n.pixelSnap {
		case .On: return true
		case .Off: return false
		case .Inherit:
		}
	}
	return renderPixel.snap
}

// Pixel_SnapPoint: a point on whole pixels of the render target (through
// the current transform - the camera's zoom, a viewport's, a Screen
// Layer's); unchanged under a rotated transform.
Pixel_SnapPoint :: proc(p: [2]f32) -> [2]f32 {
	if !rl.IsWindowReady() || renderPixel.worldSnap do return {math.round(p.x), math.round(p.y)}
	m := rlgl.GetMatrixModelview()
	return Pixel_SnapPointIn(p, m)
}

// PIXEL_TIE_BIAS: a snapped texture is moved this much (target px) down and
// right. A sprite scaled by a fraction (1.5x) has texel edges exactly on
// pixel centres; the quad's two triangles rounded those ties differently -
// columns that changed from row to row (#409). Too small to move anything
// else by a pixel.
PIXEL_TIE_BIAS :: 1.0 / 128

// Pixel_SnapTexture: the top-left of a snapped texture draw (Pixel_SnapPoint
// and the tie bias).
Pixel_SnapTexture :: proc(p: [2]f32) -> [2]f32 {
	m := rlgl.GetMatrixModelview() if rl.IsWindowReady() && !renderPixel.worldSnap else rl.Matrix(1)
	q := Pixel_SnapPointIn(p, m)
	if m[1, 0] != 0 || m[0, 1] != 0 || abs(m[0, 0]) < 0.0001 || abs(m[1, 1]) < 0.0001 do return q
	return q + {PIXEL_TIE_BIAS / m[0, 0], PIXEL_TIE_BIAS / m[1, 1]}
}

// Pixel_SnapPointIn: Pixel_SnapPoint through the transform m.
Pixel_SnapPointIn :: proc(p: [2]f32, m: rl.Matrix) -> [2]f32 {
	sx, sy := m[0, 0], m[1, 1]
	if m[1, 0] != 0 || m[0, 1] != 0 || abs(sx) < 0.0001 || abs(sy) < 0.0001 do return p
	t := [2]f32{m[0, 3], m[1, 3]}
	q := p * {sx, sy} + t
	return ([2]f32{math.round(q.x), math.round(q.y)} - t) / {sx, sy}
}

// Pixel_SnapSprite moves a sprite's draw position so its top-left corner is
// on a whole pixel (unrotated sprites; `o` = the origin in drawn pixels).
// Whole pixels of the render target, not of the world: right under a
// zoomed camera too (#409).
Pixel_SnapSprite :: #force_inline proc(pos, o: [2]f32, rotation: f32) -> [2]f32 {
	if rotation != 0 || !Pixel_Snaps() do return pos
	tl := pos - o
	return pos + Pixel_SnapPoint(tl) - tl
}

// Screen_Fill: what fills a window (or screen) whose shape differs from the
// game's virtual resolution (#174).
Screen_Fill :: enum u8 {
	Keep,   // the virtual resolution as it is, scaled to fit: bars where the shapes differ
	Expand, // the same scale, the frame grown to the window's shape: more world on the longer side, no bars
}

Screen_Fill_Name :: proc(f: Screen_Fill) -> string {return "expand" if f == .Expand else "keep"}
Screen_Fill_Parse :: proc(s: string) -> Screen_Fill {return .Expand if s == "expand" else .Keep}

// Screen_FillSize: the frame size for a design (virtual) resolution on a
// screen. Keep: the design size. Expand: scaled as Keep scales it (the
// smaller of the two ratios; a whole number with integer scaling), then
// grown on the longer side to the screen's shape - at least the design
// size, so what the design shows is always shown.
Screen_FillSize :: proc(design, screen: [2]f32, fill: Screen_Fill, integer := false) -> [2]f32 {
	if fill == .Keep || design.x <= 0 || design.y <= 0 || screen.x <= 0 || screen.y <= 0 do return design
	s := min(screen.x / design.x, screen.y / design.y)
	if integer && s >= 1 do s = math.floor(s)
	if integer {
		return {max(design.x, math.floor(screen.x / s)), max(design.y, math.floor(screen.y / s))}
	}
	return {max(design.x, math.ceil(screen.x / s - 0.01)), max(design.y, math.ceil(screen.y / s - 0.01))}
}

// Pixel_FitRect: the frame (w x h) scaled into the screen, centred - by a
// whole number with integer scaling (at least 1).
Pixel_FitRect :: proc(w, h, screenW, screenH: f32) -> rl.Rectangle {
	if w <= 0 || h <= 0 || screenW <= 0 || screenH <= 0 do return {0, 0, max(w, 1), max(h, 1)}
	s := min(screenW / w, screenH / h)
	if renderPixel.integerScaling && s >= 1 do s = math.floor(s)
	dw, dh := w * s, h * s
	return {f32(int((screenW - dw) * 0.5)), f32(int((screenH - dh) * 0.5)), dw, dh}
}

// Pixel_WorldTarget: the smooth camera's world texture for a w x h frame.
Pixel_WorldTarget :: proc(w, h: i32) -> ^rl.RenderTexture2D {
	ww, wh := w + 2 * PIXEL_MARGIN, h + 2 * PIXEL_MARGIN
	t := &renderPixel.world
	if t.id == 0 || t.texture.width != ww || t.texture.height != wh {
		if t.id != 0 do rl.UnloadRenderTexture(t^)
		t^ = rl.LoadRenderTexture(ww, wh)
		rl.SetTextureFilter(t.texture, .POINT)
	}
	return t
}

// Pixel_Release frees the world texture (window closing).
Pixel_Release :: proc() {
	if renderPixel.world.id != 0 do rl.UnloadRenderTexture(renderPixel.world)
	renderPixel.world = {}
	Pixel_ShutdownShaders()
	Pixel_NativeRelease()
}

// Pixel_DrawWorld (runner): the smooth camera's world into dest (the frame's
// place on screen), moved by the leftover fraction, clipped to dest.
// Sharp: nearest-neighbour at whole scales, sharp-bilinear otherwise (a
// fractional shift at a fractional scale gave uneven columns, #409).
Pixel_DrawWorld :: proc(tex: rl.Texture2D, dest: rl.Rectangle, vw, vh: f32, sharp := true) {
	d := Pixel_WorldRect(dest, vw, vh, f32(tex.width), f32(tex.height), renderPixel.frac)
	rl.BeginScissorMode(i32(dest.x), i32(dest.y), i32(dest.width), i32(dest.height))
	shaded := sharp && !Pixel_IsWholeScale(d, f32(tex.width), f32(tex.height)) && Pixel_SharpBegin(tex, f32(tex.width), f32(tex.height), d)
	if !shaded do rl.SetTextureFilter(tex, .POINT if sharp else .BILINEAR)
	rl.DrawTexturePro(tex, {0, 0, f32(tex.width), -f32(tex.height)}, d, {0, 0}, 0, rl.WHITE)
	if shaded do Pixel_SharpEnd(tex)
	rl.EndScissorMode()
}

// Pixel_WorldRect: where the smooth camera's world texture (texW x texH: the
// frame plus the margin) lands for the frame at dest, moved by frac.
Pixel_WorldRect :: proc(dest: rl.Rectangle, vw, vh, texW, texH: f32, frac: [2]f32) -> rl.Rectangle {
	sx, sy := dest.width / vw, dest.height / vh
	m := f32(PIXEL_MARGIN)
	return {dest.x - (m + frac.x) * sx, dest.y - (m + frac.y) * sy, texW * sx, texH * sy}
}

// --- per-node texture filter -----------------------------------------------

// The textures whose filter the drawing node changed (put back after it).
@(private = "file")
pixelChanged: struct {
	tex: [8]rl.Texture2D,
	n:   int,
}

// The filter each texture was given on import (Texture_ApplyImport; others:
// raylib's nearest-neighbour).
@(private = "file")
pixelBaseFilter: map[u32]rl.TextureFilter

// Pixel_RecordFilter: a texture's own filter (its import setting).
Pixel_RecordFilter :: proc(id: u32, f: rl.TextureFilter) {
	if pixelBaseFilter == nil do pixelBaseFilter = make(map[u32]rl.TextureFilter, allocator = Engine_HeapAllocator())
	pixelBaseFilter[id] = f
}

// Pixel_NodeFilter: the filter the drawing node asks for (false: Inherit).
Pixel_NodeFilter :: #force_inline proc() -> (rl.TextureFilter, bool) {
	n := renderPixel.node
	if n == nil || n.pixelFilter == .Inherit do return .POINT, false
	return .POINT if n.pixelFilter == .Sharp else .BILINEAR, true
}

// Pixel_UseTexture: before the drawing node draws `tex` - its Texture
// Filter, until the node is done (Pixel_EndNode). Free with Inherit.
Pixel_UseTexture :: proc(tex: rl.Texture2D) {
	f, over := Pixel_NodeFilter()
	if !over || tex.id == 0 || !rl.IsWindowReady() do return
	for i in 0 ..< pixelChanged.n do if pixelChanged.tex[i].id == tex.id do return
	if pixelChanged.n == len(pixelChanged.tex) do return
	if pixelBaseFilter[tex.id] == f do return
	rlgl.DrawRenderBatchActive() // (what's queued with it keeps its filter)
	rl.SetTextureFilter(tex, f)
	pixelChanged.tex[pixelChanged.n] = tex
	pixelChanged.n += 1
}

// Pixel_BeginNode / Pixel_EndNode (render_bucket): the node whose overrides
// apply; its textures' filters back as they were after it.
Pixel_BeginNode :: #force_inline proc(n: ^Node) {renderPixel.node = n}
Pixel_EndNode :: proc() {
	renderPixel.node = nil
	if pixelChanged.n == 0 do return
	rlgl.DrawRenderBatchActive()
	for i in 0 ..< pixelChanged.n {
		t := pixelChanged.tex[i]
		rl.SetTextureFilter(t, pixelBaseFilter[t.id] if t.id in pixelBaseFilter else .POINT)
	}
	pixelChanged.n = 0
}

// --- sharp-bilinear scaling -------------------------------------------------

// Each game pixel stays a flat square; only the screen pixels on its edges
// blend (by how much of them it covers): crisp at any scale, no uneven
// columns. `opaque`: the frame's alpha set to 1 on the way (#331).
@(private = "file")
SHARP_BILINEAR_FS :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform vec2 texSize;
uniform vec2 scale;
uniform float opaque;
out vec4 finalColor;
void main() {
    vec2 texel = fragTexCoord * texSize;
    vec2 base = floor(texel);
    vec2 d = fract(texel) - 0.5;
    vec2 region = 0.5 - 0.5 / max(scale, vec2(1.0));
    vec2 f = (d - clamp(d, -region, region)) * max(scale, vec2(1.0)) + 0.5;
    vec4 c = texture(texture0, (base + f) / texSize) * colDiffuse * fragColor;
    finalColor = opaque > 0.5 ? vec4(c.rgb, 1.0) : c;
}
`

@(private = "file")
sharpShader: struct {
	shader: rl.Shader,
	loaded, ok: bool,
	locSize, locScale, locOpaque: i32,
}

// Pixel_IsWholeScale: dest shows tex at a whole-number scale (or smaller).
Pixel_IsWholeScale :: proc(dest: rl.Rectangle, texW, texH: f32) -> bool {
	sx, sy := dest.width / max(texW, 1), dest.height / max(texH, 1)
	return (sx <= 1 || sx == math.floor(sx)) && (sy <= 1 || sy == math.floor(sy))
}

// Pixel_SharpBegin: the next texture draw (one quad) scaled up sharp-bilinear
// - `tex` from texW x texH texels to dest. False (nothing changed) when the
// shader can't load. The texture samples bilinearly meanwhile.
Pixel_SharpBegin :: proc(tex: rl.Texture2D, texW, texH: f32, dest: rl.Rectangle, opaque := false) -> bool {
	if !sharpShader.loaded {
		sharpShader.loaded = true
		sharpShader.shader = rl.LoadShaderFromMemory(nil, Shader_Port(SHARP_BILINEAR_FS))
		sharpShader.ok = rl.IsShaderValid(sharpShader.shader)
		if sharpShader.ok {
			sharpShader.locSize = rl.GetShaderLocation(sharpShader.shader, "texSize")
			sharpShader.locScale = rl.GetShaderLocation(sharpShader.shader, "scale")
			sharpShader.locOpaque = rl.GetShaderLocation(sharpShader.shader, "opaque")
		}
	}
	if !sharpShader.ok do return false
	rlgl.DrawRenderBatchActive()
	rl.SetTextureFilter(tex, .BILINEAR)
	rl.BeginShaderMode(sharpShader.shader)
	size := [2]f32{f32(tex.width), f32(tex.height)}
	scale := [2]f32{dest.width / max(texW, 1), dest.height / max(texH, 1)}
	op: f32 = 1 if opaque else 0
	rl.SetShaderValue(sharpShader.shader, sharpShader.locSize, &size, .VEC2)
	rl.SetShaderValue(sharpShader.shader, sharpShader.locScale, &scale, .VEC2)
	rl.SetShaderValue(sharpShader.shader, sharpShader.locOpaque, &op, .FLOAT)
	return true
}

// Pixel_SharpEnd: after Pixel_SharpBegin's draw (the texture back to nearest).
Pixel_SharpEnd :: proc(tex: rl.Texture2D) {
	rl.EndShaderMode()
	rlgl.DrawRenderBatchActive()
	rl.SetTextureFilter(tex, .POINT)
}

// Pixel_ShutdownShaders frees the sharp-bilinear shader (window closing).
Pixel_ShutdownShaders :: proc() {
	if sharpShader.ok && rl.IsWindowReady() do rl.UnloadShader(sharpShader.shader)
	sharpShader = {}
}
