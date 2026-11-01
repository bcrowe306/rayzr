package engine

import os "osx"
import "core:path/filepath"
import "core:testing"
import lua "lua54"
import rl "vendor:raylib"

@(private = "file")
half_width :: proc(r: rune, size: f32, data: rawptr) -> f32 {return size * 0.5}

@(test)
test_text_layout :: proc(t: ^testing.T) {
	base := Text_Style{rl.WHITE, 10, {}}
	// "aaaa bbbb" at 5 px a character, wrapped at 30: two lines.
	glyphs, size := Text_Layout("aaaa bbbb", base, 30, 0, 1, false, half_width, nil)
	testing.expect_value(t, len(glyphs), 9)
	testing.expect(t, glyphs[5].r == 'b' && glyphs[5].pos == {0, 10}, "second word on the next line")
	testing.expect_value(t, size, [2]f32{20, 20})
	// Centred: the shorter line moves right.
	glyphs, _ = Text_Layout("aaaa\nbb", base, 0, 1, 1, false, half_width, nil)
	testing.expect_value(t, glyphs[4].pos.x, 5)
	// A word longer than the line breaks inside it.
	glyphs, _ = Text_Layout("abcdefgh", base, 20, 0, 1, false, half_width, nil)
	testing.expect(t, glyphs[4].pos == {0, 10}, "long word split")

	// Rich text: colours, sizes, effects nest and pop; unknown tags stay; [[ is [.
	glyphs, _ = Text_Layout("a[color=#ff0000]b[size=20][wave]c[/wave]d[/size]e[/color]f [x] [[g", base, 0, 0, 1, true, half_width, nil)
	text := make([dynamic]rune, context.temp_allocator)
	for g in glyphs do append(&text, g.r)
	testing.expect_value(t, string(runes_to_string(text[:])), "abcdef [x] [g")
	testing.expect(t, glyphs[1].color == {255, 0, 0, 255} && glyphs[0].color == rl.WHITE, "colour")
	testing.expect(t, glyphs[2].size == 20 && .Wave in glyphs[2].effects, "size + wave")
	testing.expect(t, glyphs[3].size == 20 && .Wave not_in glyphs[3].effects, "wave closed")
	testing.expect(t, glyphs[4].size == 10 && glyphs[4].color == {255, 0, 0, 255} && glyphs[5].color == rl.WHITE, "unwound")
	testing.expect_value(t, Text_PlainLength("[color=red]hi[/color] there", true), 8)
	testing.expect_value(t, Text_PlainLength("[color=red]hi", false), 13)
}

@(private = "file")
runes_to_string :: proc(rs: []rune) -> string {
	b := make([dynamic]u8, context.temp_allocator)
	for r in rs {
		buf: [4]u8
		n := 0
		switch {
		case r < 0x80: buf[0] = u8(r); n = 1
		case r < 0x800: buf[0] = u8(0xC0 | (r >> 6)); buf[1] = u8(0x80 | (r & 0x3F)); n = 2
		case: buf[0] = u8(0xE0 | (r >> 12)); buf[1] = u8(0x80 | ((r >> 6) & 0x3F)); buf[2] = u8(0x80 | (r & 0x3F)); n = 3
		}
		append(&b, ..buf[:n])
	}
	return string(b[:])
}

@(test)
test_localization_and_text_nodes :: proc(t: ^testing.T) {
	dir, _ := filepath.join({Engine_TempDir(), "rayzr_locale_test"}, context.temp_allocator)
	_ = os.remove_all(dir)
	defer os.remove_all(dir)
	locDir, _ := filepath.join({dir, "locale"}, context.temp_allocator)
	_ = os.make_directory_all(locDir)
	write :: proc(dir, name, text: string) {
		p, _ := filepath.join({dir, name}, context.temp_allocator)
		_ = os.write_entire_file(p, transmute([]u8)text)
	}
	write(dir, "project.json", `{"name": "Loc", "language": "fr", "initial_scene": "main", "scenes": []}`)
	write(locDir, "ui.csv", "\xef\xbb\xbfkey,en,fr\ngreeting,\"Hello, {name}!\",\"Bonjour, {name} !\"\nonly_en,Just English,\n# a comment,x,y\n")
	write(locDir, "more.csv", "key,de\ngreeting,\"Hallo, {name}!\"\n")

	saveDir, _ := filepath.join({dir, "save"}, context.temp_allocator)
	Save_SetDirectory(saveDir) // (Locale.set remembers the language: not in the real save folder)
	defer Save_SetDirectory("")
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	testing.expect(t, game->loadProject(dir), "project loaded")
	scene := game->createScene("loc", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	args := make(map[string]string, context.temp_allocator)
	args["name"] = "Ada"
	testing.expect_value(t, Locale_Get(game, "greeting", args), "Bonjour, Ada !") // project language: fr
	testing.expect_value(t, Locale_Get(game, "only_en"), "Just English")        // falls back to the first language
	testing.expect_value(t, Locale_Get(game, "missing.key"), "missing.key")
	testing.expect_value(t, len(Locale_Languages(game)), 3)
	Locale_SetLanguage("de")
	testing.expect_value(t, Locale_Get(game, "greeting", args), "Hallo, Ada!")

	// Lua: tr and Locale.
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
Locale.set("en")
greet = tr("greeting", {name = "Bo"})
lang = Locale.get()
n = #Locale.languages()
`)
	testing.expect(t, ok == 0, "lua ran")
	lua.getglobal(L, "greet")
	testing.expect_value(t, string(lua.tostring(L, -1)), "Hello, Bo!")
	lua.pop(L, 1)

	// A localized TextNode shows the translation; the typewriter reveals it.
	tn := cast(^TextNode)Node_CreateByTypeName(scene, "TextNode")
	tn.name = "Title"
	tn.localized = true
	TextNode_SetText(tn, "only_en")
	testing.expect_value(t, TextNode_DisplayText(tn, &game.gameContext), "Just English")
	tn.revealSpeed = 10
	revealedEvents := 0
	tn.onRevealed->subscribe(proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &revealedEvents)
	game->run(0.5)
	testing.expectf(t, int(tn.revealed) == 5, "5 of 12 characters after 0.5 s: %v", tn.revealed)
	for _ in 0 ..< 10 do game->run(0.1)
	testing.expect(t, tn.revealDone && revealedEvents == 1, "revealed once")

	// Dialogue: lines type out, advance shows the rest then the next, closes after the last.
	dlg := cast(^DialogueNode)Node_CreateByTypeName(scene, "DialogueNode")
	dlg.name = "Box"
	ok = lua.L_dostring(L, `
local box = Scene.find_node("Box")
box:dialogue_show({ {speaker = "Ada", text = "[color=red]Hi[/color] there"}, "Second line" })
open = tostring(box:dialogue_is_open())
`)
	testing.expect(t, ok == 0, "lua dialogue")
	shown, finished := 0, 0
	dlg.onLineShown->subscribe(proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &shown)
	dlg.onFinished->subscribe(proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &finished)
	game->run(0.1) // 4 characters at 40/s
	testing.expect(t, DialogueNode_IsOpen(dlg) && !dlg.lineDone, "typing")
	DialogueNode_Advance(dlg, &game.gameContext) // rest of line 1
	testing.expect(t, dlg.lineDone && dlg.current == 0 && shown == 1, "line 1 shown")
	DialogueNode_Advance(dlg, &game.gameContext) // line 2
	testing.expect_value(t, dlg.current, 1)
	game->run(1.0)
	testing.expect(t, dlg.lineDone && shown == 2, "line 2 typed out by itself")
	DialogueNode_Advance(dlg, &game.gameContext)
	testing.expect(t, !DialogueNode_IsOpen(dlg) && finished == 1, "closed after the last line")
}
