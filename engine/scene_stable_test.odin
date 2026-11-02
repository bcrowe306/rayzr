package engine

import "core:encoding/json"
import os "osx"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import lua "lua54"

// #328: saved scenes are stable - a uid on every node, and saving what was
// loaded gives the same text again (small diffs under version control).
@(test)
test_scene_save_stable :: proc(t: ^testing.T) {
	projects := make([dynamic]string, context.temp_allocator)
	append(&projects, "assets/demo_project")
	if h, err := os.open("templates"); err == nil {
		dirs, _ := os.read_dir(h, -1, context.temp_allocator)
		os.close(h)
		for d in dirs {
			if d.type != .Directory do continue
			p, _ := filepath.join({"templates", d.name}, context.temp_allocator)
			append(&projects, p)
		}
	}
	checked := 0
	for root in projects {
		dir, _ := filepath.join({root, "scenes"}, context.temp_allocator)
		h, err := os.open(dir)
		if err != nil do continue
		files, _ := os.read_dir(h, -1, context.temp_allocator)
		os.close(h)
		for f in files {
			if !strings.has_suffix(f.name, ".scene.json") do continue
			path, _ := filepath.join({dir, f.name}, context.temp_allocator)
			data, rerr := os.read_entire_file(path, context.temp_allocator)
			if rerr != nil do continue
			first := scene_save_after_load(t, root, data)
			second := scene_save_after_load(t, root, transmute([]u8)first)
			testing.expectf(t, first == second, "%s: saving again changes nothing", path)
			missing := scene_nodes_without_uid(first)
			testing.expectf(t, missing == 0, "%s: %d nodes without a uid", path, missing)
			checked += 1
		}
	}
	testing.expect(t, checked >= 10, "the demo's and the templates' scenes")
}

// scene_save_after_load: `data` loaded into a fresh game, then saved.
@(private = "file")
scene_save_after_load :: proc(t: ^testing.T, projectDir: string, data: []u8) -> string {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, projectDir)
	scene := game->createScene("stable", false)
	Scene_InstantiateFromJSON(scene, data, &game.gameContext)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	return Scene_SerializeToJSON(scene, context.temp_allocator)
}

// scene_nodes_without_uid: nodes of the saved scene with no "uid" (the
// ones inside a linked instance come from its file).
@(private = "file")
scene_nodes_without_uid :: proc(text: string) -> int {
	val, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None do return -1
	obj, _ := val.(json.Object)
	root, _ := obj["root"].(json.Object)
	count :: proc(n: json.Object) -> int {
		missing := 0
		if u, _ := n["uid"].(json.String); u == "" do missing += 1
		if kids, ok := n["children"].(json.Array); ok {
			for k in kids do if ko, isObj := k.(json.Object); isObj do missing += count(ko)
		}
		return missing
	}
	return count(root)
}

// #328: every node gets a uid, kept through save / load and renames;
// Lua reads it (read-only) and finds the node by it.
@(test)
test_node_uids :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("uids", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	a := Node_CreateByTypeName(scene, "Node")
	a.name = "A"
	b := Node_CreateByTypeName(scene, "Node", a)
	b.name = "B"
	b.uid = strings.clone(a.uid if a.uid != "" else "same", b.allocator)
	a.uid = strings.clone(b.uid, a.allocator) // (a repeated uid: one is given a new one)
	ProcessNodeQueues(scene.manager, &game.gameContext)

	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, a.uid != "" && b.uid != "" && a.uid != b.uid, "unique uids given on save")
	testing.expect(t, strings.contains(text, a.uid) && strings.contains(text, b.uid), "uids saved")
	uidA, uidB := strings.clone(a.uid, context.temp_allocator), strings.clone(b.uid, context.temp_allocator)

	b.name = "Renamed"
	s2 := game->createScene("uids2", false)
	Scene_InstantiateFromJSON(s2, transmute([]u8)Scene_SerializeToJSON(scene, context.temp_allocator), &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)
	b2 := Node_FindByUid(s2.manager, s2.rootNode, uidB)
	testing.expect(t, b2 != nil && b2.name == "Renamed", "found by uid after a rename")
	testing.expect(t, Node_FindByUid(s2.manager, s2.rootNode, uidA) != nil, "A kept its uid")
	testing.expect(t, s2.rootNode.uid == scene.rootNode.uid, "the root's uid loads too")

	L := game.scriptManager.L
	lua.pushstring(L, strings.clone_to_cstring(uidB, context.temp_allocator))
	lua.setglobal(L, "want")
	ok := lua.L_dostring(L, `
local b = Scene.find_node("Renamed")
same = Scene.find_by_uid(b.uid) ~= nil and b.uid == want
missing = Scene.find_by_uid("nope") == nil
readonly = not pcall(function() b.uid = "x" end)
`)
	testing.expect(t, ok == 0, "lua ran")
	for name in ([]cstring{"same", "missing", "readonly"}) {
		lua.getglobal(L, name)
		testing.expectf(t, bool(lua.toboolean(L, -1)), "lua: %s", name)
		lua.pop(L, 1)
	}
}
