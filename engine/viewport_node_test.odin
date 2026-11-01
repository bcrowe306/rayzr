package engine

import "core:strings"
import "core:testing"
import lua "lua54"

// #279: the Viewport node - defaults, its Camera child isn't the scene's,
// a Children viewport's subtree draws only into it, paths, Lua, saving.
// (The pictures themselves: tests/viewport, in the runner.)
@(test)
test_viewport_node :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("vp", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	ctx := &game.gameContext
	main := CameraNode_Create(scene, "MainCam", true)
	mini := cast(^ViewportNode)Node_CreateByTypeName(scene, "ViewportNode")
	mini.name = strings.clone("Minimap", mini.allocator)
	mini.renderSize = {160, 90}
	cam := CameraNode_Create(scene, "MiniCam", true, mini)
	screen := ViewportNode_Create(scene, "Screen")
	screen.mode = .Children
	inside := TextNode_Create(scene, "Inside", screen)
	ProcessNodeQueues(scene.manager, ctx)
	Scene_CallReady(scene, scene.rootNode, ctx)
	Node_SetGlobalPositions(scene.manager, scene.rootNode)

	testing.expect(t, mini.size == {320, 180} && mini.display && mini.updateMode == .Every_Frame, "defaults")
	testing.expect_value(t, ViewportNode_RenderSize(mini), [2]i32{160, 90})
	testing.expect_value(t, ViewportNode_RenderSize(screen), [2]i32{320, 180})
	testing.expect(t, !cam.isCurrent && scene.camera == main, "a viewport's camera isn't the scene's")
	testing.expect(t, ViewportNode_Camera(mini) == cam, "its Camera child")

	// The Children viewport draws; its children only into it.
	buckets := Scene_CollectRenderables(scene)
	inWorld :: proc(b: [RenderLayer][dynamic]^Node, n: ^Node) -> bool {
		for l in b do for x in l do if x == n do return true
		return false
	}
	testing.expect(t, inWorld(buckets, screen) && !inWorld(buckets, inside), "children not in the frame")
	testing.expect(t, inWorld(Scene_CollectSubtree(scene, screen), inside), "...but in its picture")

	// Paths.
	testing.expect_value(t, Viewport_Path(mini), "viewport:Minimap")
	testing.expect(t, Viewport_Find(scene, "viewport:Minimap") == mini && Viewport_Find(scene, "viewport:Nope") == nil, "found by path")
	r, ok := Node_RenderBounds(mini)
	testing.expect(t, ok && r.width == 320 && r.height == 180, "bounds: its rect")

	// Once: renders, then only after refresh.
	mini.updateMode = .Once
	mini.rendered = true
	ViewportNode_Refresh(mini)
	testing.expect(t, mini.dirty, "refresh")

	// Lua.
	L := game.scriptManager.L
	code: cstring = `local v = Scene.find_node("Minimap"); p = v:get_texture(); v:refresh()
		s = Scene.find_node("Inside"):get_texture()`
	if lua.L_dostring(L, code) != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	lua.getglobal(L, "p"); testing.expect_value(t, string(lua.tostring(L, -1)), "viewport:Minimap"); lua.pop(L, 1)
	lua.getglobal(L, "s"); testing.expect(t, lua.isnil(L, -1), "not a viewport: nil"); lua.pop(L, 1)

	// Saved and loaded.
	mini.coversScreen, mini.pixelated = true, true
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"ViewportNode"`), "saved")
	s2 := game->createScene("vp2", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, ctx)
	ProcessNodeQueues(s2.manager, ctx)
	m2 := cast(^ViewportNode)Scene_FindNodeByName(s2, "Minimap")
	sc2 := cast(^ViewportNode)Scene_FindNodeByName(s2, "Screen")
	testing.expect(t, m2 != nil && m2.renderSize == {160, 90} && m2.updateMode == .Once && m2.coversScreen && m2.pixelated, "loaded")
	testing.expect(t, sc2 != nil && sc2.mode == .Children, "mode loaded")
	free_all(context.temp_allocator)
}
