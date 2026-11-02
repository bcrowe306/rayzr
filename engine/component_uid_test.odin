package engine

import os "osx"
import "core:encoding/json"
import "core:strings"
import "core:testing"

// #77: stable node ids (uid) in component files; instance overrides refer
// to uid paths, so renaming a node in the file or giving siblings the same
// name doesn't move or drop overrides. Files and scenes without uids keep
// loading by name.

@(private = "file")
UID_DIR :: "test_component_uid"
@(private = "file")
UID_FILE :: UID_DIR + "/components/crate.component.json"
@(private = "file")
UID_REL :: "components/crate.component.json"

@(private = "file")
uid_game :: proc(component: string) -> ^Game {
	_ = os.make_directory_all(UID_DIR + "/components")
	_ = os.write_entire_file(UID_FILE, transmute([]u8)component)
	game := new(Game)
	InitializeGame(game)
	AssetManager_SetProjectDir(&game.assetManager, UID_DIR)
	return game
}

@(private = "file")
uid_load :: proc(game: ^Game, text, name: string) -> ^Scene {
	s := game->createScene(name, false)
	Scene_InstantiateFromJSON(s, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s.manager, &game.gameContext)
	return s
}

// The children of the instance named `inst`.
@(private = "file")
uid_kids :: proc(scene: ^Scene, inst: string) -> []^Node {
	root := Scene_FindNodeByName(scene, inst)
	if root == nil do return nil
	return GetChildrenView(scene.manager, root)
}

@(private = "file")
uid_instance_scene :: proc(game: ^Game, name: string) -> (^Scene, ^Node) {
	scene := game->createScene(name, false)
	inst := Scene_InstantiateComponent(scene, UID_REL, nil, &game.gameContext)
	if inst != nil do inst.name = strings.clone("CrateA", inst.allocator)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	return scene, inst
}

@(test)
test_component_uid_rename_keeps_override :: proc(t: ^testing.T) {
	defer os.remove_all(UID_DIR)
	game := uid_game(`{"type": "Node", "name": "Crate", "uid": "r00t0000", "children": [{"type": "Node", "name": "Lid", "uid": "l1d00000", "position": [0, -10]}]}`)
	defer game->terminate()
	defer Component_ClearCaches()
	scene, inst := uid_instance_scene(game, "uid_rename")
	if inst == nil do testing.fail_now(t, "instance")
	testing.expect_value(t, uid_kids(scene, "CrateA")[0].uid, "l1d00000")
	uid_kids(scene, "CrateA")[0].position = {0, -42}
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(saved, `"l1d00000": {"position"`), "the override refers to the uid: %s", saved)
	testing.expect(t, !strings.contains(saved, `"Lid"`), "not the name")
	testing.expect(t, inst.uid != "" && inst.uid != "r00t0000", "the scene's instance has a uid of its own (#328), not the file's root")

	// The component renames its child: the instance keeps its override.
	_ = os.write_entire_file(UID_FILE, transmute([]u8)string(`{"type": "Node", "name": "Crate", "uid": "r00t0000", "children": [{"type": "Node", "name": "Hatch", "uid": "l1d00000", "position": [0, -10]}]}`))
	again := uid_load(game, saved, "uid_rename_2")
	kids := uid_kids(again, "CrateA")
	testing.expect(t, len(kids) == 1 && kids[0].name == "Hatch" && kids[0].position == {0, -42}, "renamed child keeps the override")
}

@(test)
test_component_uid_duplicate_sibling_names :: proc(t: ^testing.T) {
	defer os.remove_all(UID_DIR)
	game := uid_game(`{"type": "Node", "name": "Crate", "uid": "r00t0000", "children": [{"type": "Node", "name": "Lid", "uid": "aaaaaaaa"}, {"type": "Node", "name": "Lid", "uid": "bbbbbbbb"}]}`)
	defer game->terminate()
	defer Component_ClearCaches()
	scene, inst := uid_instance_scene(game, "uid_dup")
	if inst == nil do testing.fail_now(t, "instance")
	uid_kids(scene, "CrateA")[1].position = {5, 6} // the second Lid only
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	again := uid_load(game, saved, "uid_dup_2")
	kids := uid_kids(again, "CrateA")
	if len(kids) != 2 do testing.fail_now(t, "two children")
	testing.expect_value(t, kids[0].position, [2]f32{0, 0})
	testing.expect_value(t, kids[1].position, [2]f32{5, 6})
}

@(test)
test_component_uid_old_files :: proc(t: ^testing.T) {
	defer os.remove_all(UID_DIR)
	OLD :: `{"type": "Node", "name": "Crate", "children": [{"type": "Node", "name": "Lid", "position": [0, -10]}, {"type": "Node", "name": "Handle"}]}`
	game := uid_game(OLD)
	defer game->terminate()
	defer Component_ClearCaches()
	OLD_SCENE :: `{"name": "s", "root": {"type": "Node", "name": "root", "children": [{"type": "Node", "name": "CrateA", "component": "components/crate.component.json", "overrides": {"Lid": {"position": [0, -42]}}}]}}`

	// A file and a scene without uids: loads and saves by name, unchanged.
	a := uid_load(game, OLD_SCENE, "uid_old")
	testing.expect_value(t, uid_kids(a, "CrateA")[0].position, [2]f32{0, -42})
	savedA := Scene_SerializeToJSON(a, context.temp_allocator)
	testing.expect(t, strings.contains(savedA, `"Lid": {"position"`), "still by name (the scene's own nodes get uids: #328)")

	// Writing the component gives every node a uid, unique in the file.
	inst := Scene_FindNodeByName(a, "CrateA")
	text := Component_InstanceJSON(inst, a.manager, context.temp_allocator)
	uids := uid_collect(t, text)
	testing.expect_value(t, len(uids), 3)
	seen := make(map[string]bool, allocator = context.temp_allocator)
	for u in uids {
		testing.expectf(t, len(u) == 8 && strings.trim_left(u, "0123456789abcdefghijklmnopqrstuvwxyz") == "", "uid %q: 8 base-36 characters", u)
		testing.expectf(t, u not_in seen, "uid %q is unique", u)
		seen[u] = true
	}
	_ = os.write_entire_file(UID_FILE, transmute([]u8)text)

	// The old scene still loads (name keys find the nodes), and saving it
	// switches its overrides to uids.
	b := uid_load(game, OLD_SCENE, "uid_old_2")
	kids := uid_kids(b, "CrateA")
	testing.expect_value(t, kids[0].position, [2]f32{0, -42})
	kids[1].position = {1, 2}
	savedB := Scene_SerializeToJSON(b, context.temp_allocator)
	testing.expectf(t, !strings.contains(savedB, `"Lid"`) && strings.contains(savedB, kids[1].uid), "uid keys: %s", savedB)

	// Writing it again keeps every uid (the root's too).
	again := Component_InstanceJSON(Scene_FindNodeByName(b, "CrateA"), b.manager, context.temp_allocator)
	testing.expect_value(t, strings.join(uid_collect(t, again), ",", context.temp_allocator), strings.join(uids, ",", context.temp_allocator))
}

// A node copied inside an instance (same uid as the original) is saved as
// an added node without a uid, so it can't take the original's overrides.
@(test)
test_component_uid_copy_in_instance :: proc(t: ^testing.T) {
	defer os.remove_all(UID_DIR)
	game := uid_game(`{"type": "Node", "name": "Crate", "uid": "r00t0000", "children": [{"type": "Node", "name": "Lid", "uid": "l1d00000"}]}`)
	defer game->terminate()
	defer Component_ClearCaches()
	scene, inst := uid_instance_scene(game, "uid_copy")
	if inst == nil do testing.fail_now(t, "instance")
	lid := uid_kids(scene, "CrateA")[0]
	copyJson := Node_SerializeToJSON(lid, scene.manager, context.temp_allocator)
	dup := Scene_InstantiateNodeFromJSON(scene, transmute([]u8)copyJson, inst, &game.gameContext)
	dup.name = strings.clone("Lid2", dup.allocator)
	dup.position = {9, 9}
	ProcessNodeQueues(scene.manager, &game.gameContext)
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(saved, `"$added"`) && !strings.contains(saved, `"l1d00000"`), "an added node, not the original's uid: %s", saved)
	again := uid_load(game, saved, "uid_copy_2")
	kids := uid_kids(again, "CrateA")
	testing.expect(t, len(kids) == 2 && kids[0].position == {0, 0} && kids[1].position == {9, 9}, "the original is unchanged")
}

// A pasted / duplicated node is new (no uid) while its original is in the
// scene; cut and pasted, it keeps its uid.
@(test)
test_component_uid_paste :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := uid_load(game, `{"name": "d", "root": {"type": "Node", "name": "root", "children": [{"type": "Node", "name": "A", "uid": "aaaaaaaa", "children": [{"type": "Node", "name": "B", "uid": "bbbbbbbb"}]}]}}`, "uid_paste")
	a := Scene_FindNodeByName(scene, "A")
	text := Node_SerializeToJSON(a, scene.manager, context.temp_allocator)
	copy := Scene_InstantiateNodeFromJSON(scene, transmute([]u8)text, scene.rootNode, &game.gameContext)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	Node_ForgetCopiedUids(scene.manager, copy)
	testing.expect(t, copy.uid == "" && GetChildrenView(scene.manager, copy)[0].uid == "", "the copy has no uids")
	testing.expect(t, a.uid == "aaaaaaaa", "the original keeps its uid")

	RemoveNode(scene.manager, a) // cut...
	ProcessNodeQueues(scene.manager, &game.gameContext)
	pasted := Scene_InstantiateNodeFromJSON(scene, transmute([]u8)text, scene.rootNode, &game.gameContext)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	Node_ForgetCopiedUids(scene.manager, pasted)
	testing.expect(t, pasted.uid == "aaaaaaaa" && GetChildrenView(scene.manager, pasted)[0].uid == "bbbbbbbb", "...and pasted: the same nodes")
}

// Demo scenes gain uids (#328) and then don't change when loaded and saved.
@(test)
test_component_uid_demo_scenes_unchanged :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	defer Component_ClearCaches()
	AssetManager_SetProjectDir(&game.assetManager, "assets/demo_project")
	for rel, i in ([]string{"scenes/main.scene.json", "scenes/battle_arena.scene.json", "scenes/new_scene.scene.json"}) {
		data, err := os.read_entire_file(strings.concatenate({"assets/demo_project/", rel}, context.temp_allocator), context.temp_allocator)
		if err != nil do continue
		names := []string{"demo_uid_0", "demo_uid_1", "demo_uid_2"}
		first := Scene_SerializeToJSON(uid_load(game, string(data), names[i]), context.temp_allocator)
		testing.expectf(t, strings.contains(first, `"uid"`), "%s: uids", rel)
		second := Scene_SerializeToJSON(uid_load(game, first, names[i]), context.temp_allocator)
		testing.expectf(t, first == second, "%s: stable", rel)
	}
}

// The uids in a component file's text, in tree order.
@(private = "file")
uid_collect :: proc(t: ^testing.T, text: string) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	val, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	testing.expect(t, err == .None, "valid JSON")
	walk :: proc(v: json.Value, out: ^[dynamic]string) {
		o, ok := v.(json.Object)
		if !ok do return
		if u, has := o["uid"].(json.String); has do append(out, string(u))
		if kids, has := o["children"].(json.Array); has do for k in kids do walk(k, out)
	}
	walk(val, &out)
	return out[:]
}
