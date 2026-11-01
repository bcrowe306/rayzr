package engine

import rl "vendor:raylib"
import ui "../ui"

MIN_CACHED_FONT_SIZE :: ui.MIN_CACHED_FONT_SIZE
MAX_CACHED_FONT_SIZE :: ui.MAX_CACHED_FONT_SIZE

engineGuiFont: rl.Font

BeginEngineViewportMode :: proc(camera: rl.Camera2D) {
	ui.BeginViewportMode(camera)
}

EndEngineViewportMode :: proc() {
	ui.EndViewportMode()
}

InitEngineFonts :: proc(fontPath: cstring = "engine/Open_Sans/static/OpenSans-Regular.ttf") -> rl.Font {
	engineGuiFont = ui.InitFonts(fontPath)
	return engineGuiFont
}

UnloadEngineFonts :: proc() {
	ui.UnloadFonts()
	engineGuiFont = {}
}

GetEngineFont :: proc(size: f32) -> rl.Font {
	return ui.GetFont(size)
}

DrawEngineText :: proc(text: cstring, x, y: f32, size: f32, color: rl.Color) {
	ui.DrawText(text, x, y, size, color)
}

MeasureEngineText :: proc(text: cstring, size: f32) -> [2]f32 {
	return ui.MeasureText(text, size)
}

RectangleFlipHorizontal :: proc(rect: rl.Rectangle) -> rl.Rectangle {
	return rl.Rectangle{
		x = rect.x,
		y = rect.y,
		width = -rect.width,
		height = rect.height,
	}
}

// Texture_DrawScaled draws `source` of a texture `size` px big (unscaled)
// at `pos`, scaled, rotated around `origin` (unscaled px from its top-left).
// A negative scale mirrors the image around the pivot - raylib takes the
// absolute size of the destination, so the flip goes into the source.
Texture_DrawScaled :: proc(tex: rl.Texture2D, source: rl.Rectangle, pos, size, scale, origin: [2]f32, rotation: f32, tint: rl.Color) {
	src := source
	o := origin
	if scale.x < 0 {
		src.width = -src.width
		o.x = size.x - o.x
	}
	if scale.y < 0 {
		src.height = -src.height
		o.y = size.y - o.y
	}
	s := [2]f32{abs(scale.x), abs(scale.y)}
	pos := Pixel_SnapSprite(pos, o * s, rotation) // on whole pixels with pixel snap
	Lit_Draw(tex, src, {pos.x, pos.y, size.x * s.x, size.y * s.y}, {o.x * s.x, o.y * s.y}, rotation, tint) // (the normal pass: its normal map - normal_maps.odin)
}

RectangleFlipAxis :: proc(rect: ^rl.Rectangle, x: bool, y: bool) {
	if x {
		rect.width = -rect.width
	}
	if y {
		rect.height = -rect.height
	}
}
