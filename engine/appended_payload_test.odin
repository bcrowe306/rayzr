package engine

import "core:encoding/json"
import os "osx"
import "core:path/filepath"
import "core:strings"
import "core:testing"

// #292: a runner with game.rayzr and the font appended finds its game and
// font in itself; a plain one finds nothing appended.
@(test)
test_appended_payload :: proc(t: ^testing.T) {
	dir := "test_appended_payload"
	_ = os.make_directory_all(dir)
	defer os.remove_all(dir)
	pkgPath, _ := filepath.join({dir, "game.rayzr"}, context.temp_allocator)
	testing.expect(t, RayzrPackage_CreateFromDirectory("templates/puzzle", pkgPath), "a package")
	pkg, _ := os.read_entire_file(pkgPath, context.temp_allocator)
	FAKE_RUNNER :: "#!runner bytes - any executable"
	FONT :: "font bytes"
	exe, _ := filepath.join({dir, "Puzzle"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(exe, Appended_Build(transmute([]u8)string(FAKE_RUNNER), pkg, transmute([]u8)string(FONT), context.temp_allocator)) == nil, "written")
	os.remove(pkgPath) // (only the one inside the exe is left)

	foot, ok := Appended_Find(exe)
	testing.expect(t, ok && foot.packageOffset == len(FAKE_RUNNER) && foot.packageSize == u64(len(pkg)) && foot.fontSize == len(FONT), "the footer")
	found := Engine_FindBundledProject(exe, context.temp_allocator)
	testing.expect_value(t, found, strings.concatenate({exe, APPENDED_PACKAGE_SUFFIX}, context.temp_allocator))
	testing.expect(t, Is_PackagePath(found), "a package path")
	p, pok := RayzrPackage_Open(found, context.temp_allocator)
	testing.expect(t, pok, "the package opens from the exe")
	if pok {
		cfg, cok := RayzrPackage_ReadFile(p, "project.json", context.temp_allocator)
		testing.expect(t, cok && strings.contains(string(cfg), "\"name\""), "project.json read from it")
		RayzrPackage_Close(p)
	}
	font := Appended_ExtractFont(exe, context.temp_allocator)
	data, _ := os.read_entire_file(font, context.temp_allocator)
	testing.expect(t, font != "" && string(data) == FONT, "the font written out")
	_ = os.remove(font)

	plain, _ := filepath.join({dir, "plain"}, context.temp_allocator)
	_ = os.write_entire_file(plain, transmute([]u8)string(FAKE_RUNNER))
	_, pok2 := Appended_Find(plain)
	testing.expect(t, !pok2 && Appended_ExtractFont(plain, context.temp_allocator) == "", "a plain runner has nothing appended")
}

// #292: a preset's Single File off is saved as "single_file": false (on is
// the default and writes nothing).
@(test)
test_export_preset_single_file :: proc(t: ^testing.T) {
	val, _ := json.parse_string(`{"presets": [{"name": "Win", "target": "windows", "single_file": false}, {"name": "Linux", "target": "linux"}]}`, allocator = context.temp_allocator)
	x: Export_Settings
	Export_PresetsParse(val.(json.Object), &x, context.temp_allocator)
	testing.expect(t, len(x.presets) == 2 && x.presets[0].separateFiles && !x.presets[1].separateFiles, "parsed")
	sb := strings.builder_make(context.temp_allocator)
	Export_PresetsWrite(&sb, &x)
	text := strings.to_string(sb)
	testing.expect(t, strings.count(text, `"single_file": false`) == 1, "written for the folder preset only")
}
