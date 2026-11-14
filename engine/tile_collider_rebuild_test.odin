package engine

import "core:testing"

// A solid map's colliders after a script erases a tile: what stood on it
// keeps standing (the colliders are built again, not lost).
@(test)
test_tile_collider_rebuild_keeps_ground :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("tcr", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	ctx := &game.gameContext
	tm := cast(^TileMapNode)Node_CreateByTypeName(scene, "TileMapNode")
	tm.name = "Ground"
	tm.gameContext = ctx
	tm.position = {100, 200}
	tm.tileSize = {16, 16}
	tm.mapSize = {20, 4}
	tm.solid = true
	TileMapNode_Layout(tm)
	for x in 0 ..< 20 do TileMapNode_Set(tm, x, 2, 1)
	box := DynamicBodyNode_Create(scene, "Box")
	box.position = {100 + 5 * 16 + 8, 200 + 16} // (on cell 5's middle)
	clear(&box.shapes)
	DynamicBodyNode_AddShape(box, MakeBoxPhysicsShape(12, 12, {0, 0}, 0))
	ProcessNodeQueues(scene.manager, ctx)
	for _ in 0 ..< 90 do game->run(1.0 / 60)
	rest := box.globalPosition.y
	testing.expectf(t, rest > 200 && rest < 200 + 2 * 16, "the box rests on the ground (y %v)", rest)
	// A script erases a far tile: the colliders are built again.
	L := game.scriptManager.L
	_ = L
	body := tm.staticBody
	TileMapNode_EditTile(tm, {15, 2}, -1)
	for _ in 0 ..< 60 do game->run(1.0 / 60)
	testing.expect(t, tm.staticBody == body && len(body.shapes) == 2, "the same body, two runs of ground now")
	testing.expectf(t, abs(box.globalPosition.y - rest) < 2, "still standing (y %v -> %v)", rest, box.globalPosition.y)
	// Its own tile erased: it falls.
	TileMapNode_EditTile(tm, {5, 2}, -1)
	for _ in 0 ..< 60 do game->run(1.0 / 60)
	testing.expectf(t, box.globalPosition.y > rest + 16, "falls through the hole (y %v)", box.globalPosition.y)
}
