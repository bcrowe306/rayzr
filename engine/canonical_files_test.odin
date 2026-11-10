package engine

import os "osx"
import "core:path/filepath"
import "core:strings"
import "core:testing"

// ============================================================================
// Canonical scene files (#293): canonical_files.odin
// ============================================================================

@(private = "file")
CANON_SCENE :: `{"name": "canon", "root": {"type": "Node", "name": "root", "children": [
 {"type": "TextNode", "name": "Label", "position": [12.5, -3], "z_index": 0,
  "properties": {"text": "hi", "fontSize": 20}},
 {"type": "Node", "name": "Group", "children": [{"type": "Node", "name": "Inner"}]}]}}`

@(test)
test_canonical_format_is_stable_and_lossless :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	a, why := Canonical_Format(game, "scenes/canon.scene.json", transmute([]u8)string(CANON_SCENE), context.temp_allocator)
	testing.expectf(t, why == "", "formatted (%s)", why)
	// The same file formats the same way (uids from its path, not random)...
	b, _ := Canonical_Format(game, "scenes/canon.scene.json", transmute([]u8)string(CANON_SCENE), context.temp_allocator)
	testing.expect(t, a == b, "the same text twice")
	// ...and a formatted file is left as it is.
	c, _ := Canonical_Format(game, "scenes/canon.scene.json", transmute([]u8)a, context.temp_allocator)
	testing.expect(t, a == c, "formatting is stable")
	testing.expect(t, strings.contains(a, `"uid": "`), "every node gets a uid")
	testing.expect_value(t, strings.count(a, `"uid": "`), 4)
	testing.expect_value(t, Canonical_Lossless(transmute([]u8)string(CANON_SCENE), transmute([]u8)a), "")
	// Another path: other uids.
	d, _ := Canonical_Format(game, "scenes/other.scene.json", transmute([]u8)string(CANON_SCENE), context.temp_allocator)
	testing.expect(t, d != a, "the uids come from the file's path")
	// The editor's current scene is left alone.
	testing.expect(t, game.sceneManager.currentScene == nil, "no current scene set")
}

@(test)
test_canonical_format_refuses_losing_something :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	// A key the loader doesn't know would be dropped: left as it is.
	_, why := Canonical_Format(game, "scenes/x.scene.json", transmute([]u8)string(`{"name": "x", "root": {"type": "Node", "name": "root", "mystery": 3}}`), context.temp_allocator)
	testing.expectf(t, strings.contains(why, "mystery"), "refused: %s", why)
	// A default dropped is fine (the editor doesn't write it).
	testing.expect_value(t, Canonical_Lossless(transmute([]u8)string(`{"a": 0, "b": [1.00001, 2]}`), transmute([]u8)string(`{"b": [1, 2]}`)), "")
	testing.expect(t, Canonical_Lossless(transmute([]u8)string(`{"b": [1.5]}`), transmute([]u8)string(`{"b": [1]}`)) != "", "a changed number")
	// A newer format isn't touched (#326).
	_, newer := Canonical_Format(game, "scenes/x.scene.json", transmute([]u8)string(`{"format": 999, "name": "x", "root": {"type": "Node", "name": "root"}}`), context.temp_allocator)
	testing.expectf(t, strings.contains(newer, "newer"), "newer: %s", newer)
	_, other := Canonical_Format(game, "scripts/x.lua", nil, context.temp_allocator)
	testing.expect(t, other != "", "not a scene or component")
}

@(private = "file")
canon_collect :: proc(dir: string, out: ^[dynamic]string) {
	h, err := os.open(dir)
	if err != nil do return
	fis, _ := os.read_dir(h, -1, context.temp_allocator)
	os.close(h)
	for fi in fis {
		p, _ := filepath.join({dir, fi.name}, context.temp_allocator)
		if os.is_dir(p) {
			if !strings.has_prefix(fi.name, ".") do canon_collect(p, out)
		} else if Canonical_KindOf(fi.name) != .Unknown {
			append(out, strings.clone(p, context.temp_allocator))
		}
	}
}

// The templates and tutorials are kept canonical (make_templates.py runs
// `editor --fmt`; tutorials: run it after editing one by hand).
@(test)
test_repo_scene_files_are_canonical :: proc(t: ^testing.T) {
	files := make([dynamic]string, context.temp_allocator)
	for root in ([]string{"templates", "docs/tutorials"}) do canon_collect(root, &files)
	testing.expect(t, len(files) > 20, "found the templates' and tutorials' files")
	for path in files {
		data, err := os.read_entire_file(path, context.temp_allocator)
		if err != nil do continue
		abs, _ := filepath.abs(path, context.temp_allocator)
		proj := Canonical_ProjectOf(abs)
		if proj == "" do continue
		game := new(Game)
		InitializeGame(game)
		AssetManager_SetProjectDir(&game.assetManager, proj)
		out, why := Canonical_Format(game, abs[len(proj) + 1:], data, context.temp_allocator)
		testing.expectf(t, why == "" && out == string(data), "%s is canonical (editor --fmt %s) %s", path, path, why)
		game->terminate()
	}
}

// A path resolved on Windows (backslashes, a drive) is saved project-
// relative with / - it was saved absolute (#293: found by the Windows run).
@(test)
test_asset_rel_windows_paths :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, `D:\a\rayzr\templates\adventure`)
	n := Node{}
	n.gameContext = &game.gameContext
	testing.expect_value(t, asset_rel(&n, `D:\a\rayzr\templates\adventure\textures\tiles.png`), "textures/tiles.png")
	testing.expect_value(t, asset_rel(&n, `D:/a/rayzr/templates/adventure/textures/tiles.png`), "textures/tiles.png")
	testing.expect_value(t, asset_rel(&n, "textures/tiles.png"), "textures/tiles.png")
	testing.expect_value(t, asset_rel(&n, `D:\elsewhere\x.png`), `D:\elsewhere\x.png`)
}
