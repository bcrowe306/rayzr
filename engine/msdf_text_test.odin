package engine

import os "osx"
import "core:testing"

// #270: the TrueType reader (cmap, metrics, simple and composite glyphs),
// MSDF fields (inside / outside right, corners kept), Auto rendering.
@(test)
test_msdf_text :: proc(t: ^testing.T) {
	data, err := os.read_entire_file("engine/Open_Sans/static/OpenSans-Regular.ttf", context.allocator)
	defer delete(data)
	testing.expect(t, err == nil, "the engine font")
	font, ok := Ttf_Open(data)
	testing.expect(t, ok && font.unitsPerEm > 0 && font.ascent > 0 && font.descent < 0, "opened")

	// cmap and metrics.
	gA := Ttf_GlyphIndex(&font, 'A')
	testing.expect(t, gA > 0 && Ttf_GlyphIndex(&font, 0x10FFFF) == 0, "glyph indices")
	advA, _ := Ttf_Advance(&font, gA)
	advI, _ := Ttf_Advance(&font, Ttf_GlyphIndex(&font, 'i'))
	testing.expect(t, advA > advI && advI > 0, "advances")
	// Contours: 'O' has two (outer, hole); 'é' is a composite (e + accent).
	testing.expect_value(t, len(Ttf_GlyphContours(&font, Ttf_GlyphIndex(&font, 'O'))), 2)
	testing.expect(t, len(Ttf_GlyphContours(&font, Ttf_GlyphIndex(&font, 'é'))) >= 3, "a composite glyph's parts")
	testing.expect_value(t, len(Ttf_GlyphContours(&font, Ttf_GlyphIndex(&font, ' '))), 0)

	// Fields: inside > 0.5, outside < 0.5 (the median of r, g, b; alpha the true distance).
	at :: proc(g: Msdf_Glyph, fx, fy: f32) -> (med, a: f32) {
		x, y := int(fx * f32(g.w)), int(fy * f32(g.h))
		i := (y * g.w + x) * 4
		r, gg, b := f32(g.pixels[i]) / 255, f32(g.pixels[i + 1]) / 255, f32(g.pixels[i + 2]) / 255
		return max(min(r, gg), min(max(r, gg), b)), f32(g.pixels[i + 3]) / 255
	}
	I := Msdf_GenerateGlyph(&font, 'I')
	testing.expect(t, I.w > 0 && I.h > 0, "a field")
	m, a := at(I, 0.5, 0.5)
	testing.expectf(t, m > 0.5 && a > 0.5, "the middle of I is inside (%v, %v)", m, a)
	m, a = at(I, 0.02, 0.02)
	testing.expectf(t, m < 0.5 && a < 0.5, "its corner outside (%v, %v)", m, a)
	O := Msdf_GenerateGlyph(&font, 'O')
	m, _ = at(O, 0.5, 0.5)
	testing.expectf(t, m < 0.5, "the hole of O is outside (%v)", m)
	space := Msdf_GenerateGlyph(&font, ' ')
	testing.expect(t, space.w == 0 && space.advance > 0, "a space: no field, an advance")
	// A sharp corner keeps different channels (that's what MSDF is for): A's apex area.
	A := Msdf_GenerateGlyph(&font, 'A')
	differs := false
	for y in 0 ..< A.h do for x in 0 ..< A.w {
		i := (y * A.w + x) * 4
		if abs(int(A.pixels[i]) - int(A.pixels[i + 1])) > 40 do differs = true
	}
	testing.expect(t, differs, "channels differ near corners")

	// Not a glyf font: no MSDF (the text falls back).
	_, bad := Ttf_Open([]u8{0, 1, 0, 0, 0, 0})
	testing.expect(t, !bad, "rejected")

	// Auto: sharp when scaled or rotated, the bitmap at 1:1; Sharp / Bitmap fixed.
	testing.expect(t, Text_DrawsSharp(.Auto, 3, 0) && Text_DrawsSharp(.Auto, 1, 10) && !Text_DrawsSharp(.Auto, 1, 0), "auto")
	testing.expect(t, Text_DrawsSharp(.Sharp, 1, 0) && !Text_DrawsSharp(.Bitmap, 4, 30), "fixed modes")
	free_all(context.temp_allocator)
}
