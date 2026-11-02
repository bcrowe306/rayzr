package engine

import "core:encoding/json"
import os "osx"
import "core:path/filepath"
import "core:strings"
import "core:testing"

FORMAT_FIXTURES :: "tests/formats"

@(private = "file")
fixture :: proc(t: ^testing.T, name: string) -> []u8 {
	path, _ := filepath.join({FORMAT_FIXTURES, name}, context.temp_allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	testing.expectf(t, err == nil, "fixture %s", name)
	return data
}

// starts_with_format: written text carries the current format of `kind`.
@(private = "file")
has_current_format :: proc(text: string, kind: Format_Kind) -> bool {
	val, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None do return false
	obj, _ := val.(json.Object)
	return obj != nil && Format_Of(obj) == FORMAT_CURRENT[kind]
}

// #326: every kind's fixtures (format 0 = 0.x files, and each format since)
// load, and what is written carries the current format.
@(test)
test_format_fixtures_load :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	defer Component_ClearCaches()
	AssetManager_SetProjectDir(&game.assetManager, FORMAT_FIXTURES)
	for f in ([]string{"f0", "f1"}) {
		// Scene.
		scene := game->createScene(strings.concatenate({"fmt_scene_", f}, context.temp_allocator), false)
		testing.expect(t, Scene_InstantiateFromJSON(scene, fixture(t, strings.concatenate({"scene.", f, ".scene.json"}, context.temp_allocator)), &game.gameContext), "scene loads")
		ProcessNodeQueues(scene.manager, &game.gameContext)
		hero := Scene_FindNodeByName(scene, "Hero")
		testing.expectf(t, hero != nil && hero.position == {12, 34} && !scene.formatNewer, "scene %s: Hero", f)
		testing.expectf(t, has_current_format(Scene_SerializeToJSON(scene, context.temp_allocator), .Scene), "scene %s: saved as the current format", f)

		// Component: an instance of it has no stray "format" override.
		comp := strings.concatenate({"component.", f, ".component.json"}, context.temp_allocator)
		inst := Scene_InstantiateComponent(scene, comp, nil, &game.gameContext)
		testing.expectf(t, inst != nil && !inst.componentMissing, "component %s loads", f)
		if inst != nil {
			ProcessNodeQueues(scene.manager, &game.gameContext)
			saved := Scene_SerializeToJSON(scene, context.temp_allocator)
			testing.expectf(t, !strings.contains(saved, `"overrides"`), "component %s: no overrides (the format key isn't one): %s", f, saved)
			testing.expectf(t, has_current_format(Component_FileJSON(inst, scene.manager, context.temp_allocator), .Component), "component %s: written as the current format", f)
		}

		// Custom node type.
		ct, problem := CustomNode_Parse("fixture.node.json", string(fixture(t, strings.concatenate({"customnode.", f, ".node.json"}, context.temp_allocator))))
		testing.expectf(t, ct != nil, "custom node %s: %s", f, problem)
		if ct != nil do testing.expect_value(t, ct.description, "a fixture")
		testing.expect(t, has_current_format(CustomNode_DefinitionJSON({name = "Fixture", base = "Node"}, context.temp_allocator), .CustomNode), "custom node written as the current format")

		// Resource.
		res, rok := Resource_ParseText("fixture.resource.json", string(fixture(t, strings.concatenate({"resource.", f, ".resource.json"}, context.temp_allocator))), quiet = true)
		testing.expectf(t, rok && res.script == "scripts/weapon.lua" && res.raw["damage"] == "3" && "format" not_in res.raw && !res.newer, "resource %s", f)
		testing.expect(t, has_current_format(Resource_FileText("scripts/weapon.lua", nil, nil, nil, context.temp_allocator), .Resource), "resource written as the current format")

		// Project.
		cfg, pok := Project_ParseConfig(fixture(t, strings.concatenate({"project.", f, ".json"}, context.temp_allocator)), context.temp_allocator)
		testing.expectf(t, pok && cfg.name == "Fixture" && cfg.initialScene == "main" && !cfg.formatNewer, "project %s", f)
		testing.expect(t, has_current_format(Project_SerializeToJSON(&cfg, context.temp_allocator), .Project), "project written as the current format")

		// Import settings.
		imp: Asset_Import
		Asset_ImportParse(string(fixture(t, strings.concatenate({"import.", f, ".import.json"}, context.temp_allocator))), &imp, context.temp_allocator)
		testing.expectf(t, imp.found && imp.filter == .Bilinear && imp.mipmaps && !imp.formatNewer, "import %s", f)
		testing.expect(t, has_current_format(Asset_ImportToJSON(imp, context.temp_allocator), .Import), "import written as the current format")
		testing.expect_value(t, Asset_ImportToJSON({}, context.temp_allocator), "{}\n") // (all defaults: no file, no key)

		// Tileset terrains.
		ts, terr := Terrains_Parse(fixture(t, strings.concatenate({"tileset.", f, ".tileset.json"}, context.temp_allocator)), context.temp_allocator)
		testing.expectf(t, terr == "" && len(ts.terrains) == 1 && ts.terrains[0].name == "Grass" && ts.terrains[0].kind == .Blob, "tileset %s: %s", f, terr)
		testing.expect(t, has_current_format(Terrains_Serialize(&ts, context.temp_allocator), .Tileset), "tileset written as the current format")

		// Level generator graph.
		g, gerr := Gen_GraphParse(fixture(t, strings.concatenate({"levelgen.", f, ".levelgen.json"}, context.temp_allocator)), context.temp_allocator)
		testing.expectf(t, gerr == "" && g.size == {16, 8} && g.seed == 7, "levelgen %s: %s", f, gerr)
		testing.expect(t, has_current_format(Gen_GraphSerialize(&g, context.temp_allocator), .LevelGen), "levelgen written as the current format")
	}
}

// #326: a format bump runs its migration step on older files only.
@(test)
test_format_migration_chain :: proc(t: ^testing.T) {
	rename :: proc(obj: ^json.Object) {
		if v, has := obj["name"]; has {
			obj["title"] = v
			delete_key(obj, "name")
		}
	}
	saved, savedSteps := FORMAT_CURRENT[.Project], FORMAT_MIGRATIONS[.Project]
	defer {FORMAT_CURRENT[.Project], FORMAT_MIGRATIONS[.Project] = saved, savedSteps}
	FORMAT_CURRENT[.Project] = 2
	FORMAT_MIGRATIONS[.Project] = {nil, rename} // 0 -> 1 nothing, 1 -> 2 renames

	Case :: struct {text, want: string}
	for c in ([]Case{{`{"format": 1, "name": "a"}`, "title"}, {`{"name": "a"}`, "title"}, {`{"format": 2, "name": "a"}`, "name"}}) {
		text, want := c.text, c.want
		val, _ := json.parse_string(text, allocator = context.temp_allocator)
		obj := val.(json.Object)
		version, newer := Format_Migrate(.Project, &obj)
		testing.expectf(t, !newer && want in obj && "format" not_in obj, "%s (format %d): has %s", text, version, want)
	}
	val, _ := json.parse_string(`{"format": 3, "name": "a"}`, allocator = context.temp_allocator)
	obj := val.(json.Object)
	_, newer := Format_Migrate(.Project, &obj)
	testing.expect(t, newer && "name" in obj, "a newer file is left as it is")
}

// #326: files from a newer Rayzr load as well as possible, flagged, and the
// engine doesn't save over them.
@(test)
test_format_newer_files :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("fmt_newer", false)
	testing.expect(t, Scene_InstantiateFromJSON(scene, transmute([]u8)string(`{"format": 99, "name": "n", "future": {"x": 1}, "root": {"type": "Node", "name": "root", "children": [{"type": "Node", "name": "Kept"}]}}`), &game.gameContext), "loads")
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect(t, scene.formatNewer && Scene_FindNodeByName(scene, "Kept") != nil, "flagged, read as well as possible")
	testing.expect(t, Format_IsNewer(.Component, Format_OfText(transmute([]u8)string(`{"format": 5, "type": "Node"}`))), "a component's format is read from its text")

	dir := "/tmp/rayzr_format_newer_test"
	os.make_directory_all(dir)
	defer os.remove_all(dir)
	proj, _ := filepath.join({dir, "project.json"}, context.temp_allocator)
	NEWER :: `{"format": 99, "name": "From the future"}`
	_ = os.write_entire_file(proj, transmute([]u8)string(NEWER))
	cfg, ok := Project_ParseConfig(transmute([]u8)string(NEWER), context.temp_allocator)
	testing.expect(t, ok && cfg.formatNewer && cfg.name == "From the future", "project read and flagged")
	cfg.formatNewer = false // (even unflagged: the file on disk decides)
	testing.expect(t, !Project_SaveConfigToFile(dir, &cfg), "not saved over")
	disk, _ := os.read_entire_file(proj, context.temp_allocator)
	testing.expect_value(t, string(disk), NEWER)

	img, _ := filepath.join({dir, "hero.png"}, context.temp_allocator)
	side := strings.concatenate({img, IMPORT_SUFFIX}, context.temp_allocator)
	_ = os.write_entire_file(side, transmute([]u8)string(`{"format": 99, "filter": "bilinear"}`))
	testing.expect(t, !Asset_ImportSave(&game.resourceManager, img, {mipmaps = true}), "import settings not saved over")
	testing.expect(t, Format_FileIsNewer(.Import, side) && !Format_FileIsNewer(.Import, "/tmp/rayzr_format_missing.json"), "missing files aren't newer")
}
