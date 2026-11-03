package engine

import "core:math"
import os "osx"
import "core:testing"
import rl "vendor:raylib"

// #357 / #363: a space has a sane advance at small sizes - the font file's
// own, rounded (raylib truncates each baked advance to whole pixels, which
// left 1 px or less). "a b" is wider than "ab" by about a space, for the
// engine font and kenney_pixel.ttf, at sizes 8-16. (The layout is shared by
// every rendering mode: Bitmap, Sharp / MSDF and Auto draw at its positions.)
@(test)
test_text_space_advance :: proc(t: ^testing.T) {
	measure :: proc(r: rune, size: f32, data: rawptr) -> f32 {return Text_MeasureRune(cast(^Text_Font)data, r, size)}
	width :: proc(f: ^Text_Font, text: string, size: f32) -> f32 {
		_, s := Text_Layout(text, {rl.WHITE, size, {}}, 0, 0, 1, false, measure, f)
		return s.x
	}

	// The engine font (Open Sans): its space ratio as InitEngineFonts reads it.
	data, err := os.read_entire_file("engine/Open_Sans/static/OpenSans-Regular.ttf", context.temp_allocator)
	testing.expectf(t, err == nil, "the engine font: %v", err)
	saved := engineSpaceRatio
	defer engineSpaceRatio = saved
	engineSpaceRatio = Text_SpaceRatio(data)
	testing.expectf(t, engineSpaceRatio > 0.15 && engineSpaceRatio < 0.25, "Open Sans: a space ~0.19 of the pixel height (%v)", engineSpaceRatio)

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, "assets/kenney")
	for path in ([]string{"", "fonts/kenney_pixel.ttf"}) {
		for size in 8 ..= 16 {
			sz := f32(size)
			f := Text_GetFont(path, sz, false, &game.gameContext)
			ratio := f.spaceRatio if path != "" else engineSpaceRatio
			testing.expectf(t, ratio > 0, "%q: the space read from the font file", path)
			want := max(math.round(ratio * sz), 1) // (kenney_pixel: 2 of its 12 px; Open Sans ~0.19)
			diff := width(f, "a b", sz) - width(f, "ab", sz)
			testing.expectf(t, abs(diff - want) < 0.01 && diff > 0.99 && abs(diff - ratio * sz) <= 0.51, "%q at %d: \"a b\" - \"ab\" = %v (a space: %v)", path, size, diff, ratio * sz)
			testing.expect_value(t, Text_MeasureRune(f, 0xA0, sz), want) // (a no-break space too)
		}
	}
}
