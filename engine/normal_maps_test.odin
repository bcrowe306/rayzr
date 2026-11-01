package engine

import os "osx"
import "core:testing"
import rl "vendor:raylib"

// #274: finding an image's normal map (_n next to it, the import setting,
// "none"), the lit image (normal xy, specular, the image's alpha), the
// generator (a bevel's normals point outward), node shininess.
@(test)
test_normal_maps :: proc(t: ^testing.T) {
	dir :: "test_normal_maps"
	_ = os.make_directory_all(dir + "/textures")
	defer os.remove_all(dir)
	rm := ResourceManager{projectDir = dir}
	defer Asset_ImportsReset()
	white := rl.GenImageColor(8, 8, rl.WHITE)
	defer rl.UnloadImage(white)
	_ = rl.ExportImage(white, dir + "/textures/hero.png")
	_ = rl.ExportImage(white, dir + "/textures/plain.png")
	_ = rl.ExportImage(white, dir + "/textures/hero_n.png")
	_ = rl.ExportImage(white, dir + "/textures/other_normals.png")

	p, _ := Lit_NormalPathFor(&rm, dir + "/textures/hero.png")
	testing.expect_value(t, p, dir + "/textures/hero_n.png")
	p, _ = Lit_NormalPathFor(&rm, dir + "/textures/plain.png")
	testing.expect_value(t, p, "")
	p, _ = Lit_NormalPathFor(&rm, dir + "/textures/hero_n.png")
	testing.expect_value(t, p, "") // (a normal map has none)
	// The import setting: another file; "none".
	_ = os.write_entire_file(dir + "/textures/plain.png.import.json", transmute([]u8)string(`{"normal_map": "textures/other_normals.png", "normal_green_down": true}`))
	_ = os.write_entire_file(dir + "/textures/hero.png.import.json", transmute([]u8)string(`{"normal_map": "none"}`))
	Asset_ImportsReset()
	gd: bool
	p, gd = Lit_NormalPathFor(&rm, dir + "/textures/plain.png")
	testing.expect(t, p == dir + "/textures/other_normals.png" && gd, "the import setting's file, green down")
	p, _ = Lit_NormalPathFor(&rm, dir + "/textures/hero.png")
	testing.expect_value(t, p, "")
	testing.expect(t, Lit_SpecularPathFor(&rm, dir + "/textures/hero.png") == "", "no _s")

	// The lit image: normal rg, specular in b, the image's alpha.
	diffuse := rl.GenImageColor(4, 4, {10, 20, 30, 77})
	normal := rl.GenImageColor(4, 4, {200, 50, 255, 255})
	spec := rl.GenImageColor(4, 4, {99, 0, 0, 255})
	defer {rl.UnloadImage(diffuse); rl.UnloadImage(normal); rl.UnloadImage(spec)}
	img := Lit_BuildImage(diffuse, normal, spec)
	px := ([^]u8)(img.data)
	testing.expect(t, px[0] == 200 && px[1] == 50 && px[2] == 99 && px[3] == 77, "rg normal, b specular, a the image's")
	rl.UnloadImage(img)
	img = Lit_BuildImage(diffuse, normal, nil)
	px = ([^]u8)(img.data)
	testing.expect_value(t, px[2], 0)
	rl.UnloadImage(img)

	// The generator: a filled circle's bevel - left edge points left, top edge up (green up).
	ball := rl.GenImageColor(32, 32, {0, 0, 0, 0})
	rl.ImageDrawCircle(&ball, 16, 16, 12, rl.WHITE)
	defer rl.UnloadImage(ball)
	n := Normal_Generate(ball, {strength = 4, softness = 6, shape = true})
	defer rl.UnloadImage(n)
	np := ([^]u8)(n.data)
	at :: proc(px: [^]u8, x, y: int) -> [4]u8 {i := (y * 32 + x) * 4; return {px[i], px[i + 1], px[i + 2], px[i + 3]}}
	left, top, mid := at(np, 5, 16), at(np, 16, 5), at(np, 16, 16)
	testing.expectf(t, left.r < 100, "left edge points left: %v", left)
	testing.expectf(t, top.g > 156, "top edge points up (green up): %v", top)
	testing.expectf(t, abs(int(mid.r) - 128) < 8 && abs(int(mid.g) - 128) < 8, "the middle faces out: %v", mid)
	testing.expect_value(t, at(np, 0, 0).a, 0) // (the image's alpha)

	// Lights' new settings; shininess on texture-drawn nodes.
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("nm", true)
	l := LightNode_Create(scene)
	testing.expect(t, l.height == 64 && l.elevation == 45, "light defaults")
	testing.expect_value(t, LightNode_KindName(.Directional), "directional")
	tn := cast(^TextureNode)Node_CreateByTypeName(scene, "TextureNode")
	tn.shininess = 0.5
	testing.expect_value(t, Node_Shininess(tn), 0.5)
	testing.expect(t, Lit_NodeDrawn(tn) && !Lit_NodeDrawn(l), "texture-drawn nodes only")
}
