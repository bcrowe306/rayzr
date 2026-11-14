package engine

import "core:strings"
import "core:testing"
import b2 "vendor:box2d"
import lua "lua54"

// Tile map physics (tilemap_colliders.odin): merged boxes in sections,
// per-tile shapes and materials, one-way and trigger tiles, the exact tile
// a contact hit, section-only rebuilds, Outline chains.

@(private = "file")
tp_setup :: proc(collision: string = "") -> (^Game, ^Scene, ^TileMapNode) {
	game := new(Game)
	InitializeGame(game)
	scene := game->createScene("tp", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	tm := cast(^TileMapNode)Node_CreateByTypeName(scene, "TileMapNode")
	tm.name = "Ground"
	tm.gameContext = &game.gameContext
	tm.tileSize = {16, 16}
	tm.mapSize = {40, 12}
	tm.solid = true
	TileMapNode_Layout(tm)
	a := Engine_HeapAllocator()
	ts := new(Tile_Terrains, a)
	ts^, _ = Terrains_Parse(transmute([]u8)(collision if collision != "" else `{"terrains": []}`), a)
	tm.sidecar = ts
	return game, scene, tm
}

@(private = "file")
tp_ball :: proc(scene: ^Scene, name: string, pos: [2]f32, radius: f32 = 6) -> ^DynamicBodyNode {
	ball := DynamicBodyNode_Create(scene, name)
	ball.position = pos
	clear(&ball.shapes)
	c: PhysicsShape
	PhysicsShape_InitDefault(&c, .Circle)
	c.radius = radius
	c.restitution = 0
	DynamicBodyNode_AddShape(ball, c)
	return ball
}

@(private = "file")
tp_lua :: proc(t: ^testing.T, game: ^Game, src: string) -> bool {
	L := game.scriptManager.L
	if lua.L_dostring(L, strings.clone_to_cstring(src, context.temp_allocator)) != 0 {
		testing.expectf(t, false, "Lua: %s", string(lua.tostring(L, -1)))
		lua.pop(L, 1)
		return false
	}
	return true
}

@(private = "file")
tp_global :: proc(game: ^Game, name: string) -> string {
	L := game.scriptManager.L
	lua.getglobal(L, strings.clone_to_cstring(name, context.temp_allocator))
	defer lua.pop(L, 1)
	return strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
}

@(test)
test_tile_collision_file_round_trip :: proc(t: ^testing.T) {
	src := `{"terrains": [], "collision": [[3, {"shape": "slope_up_right", "friction": 0.1}],
		[5, {"shape": "custom", "points": [[0, 1], [0.5, 0], [1, 1]], "bounce": 0.9}],
		[7, {"shape": "full", "trigger": true}], [8, {"shape": "one_way"}]]}`
	ts, err := Terrains_Parse(transmute([]u8)string(src), context.temp_allocator)
	testing.expect_value(t, err, "")
	c := TileCollision_Get(&ts, 3)
	testing.expect(t, c.shape == .Slope_Up_Right && c.friction == 0.1 && c.bounce == -1, "a slope with its friction")
	c = TileCollision_Get(&ts, 5)
	testing.expect(t, c.shape == .Custom && c.count == 3 && c.points[1] == {0.5, 0} && c.bounce == 0.9, "a custom polygon")
	testing.expect(t, TileCollision_Get(&ts, 7).trigger, "a trigger")
	testing.expect(t, TileCollision_Get(&ts, 9) == TILE_COLLISION_DEFAULT, "unset: full")
	TileCollision_Set(&ts, 3, TILE_COLLISION_DEFAULT)
	text := Terrains_Serialize(&ts, context.temp_allocator)
	testing.expect(t, !strings.contains(text, "slope_up_right"), "back to full: no entry")
	ts2, _ := Terrains_Parse(transmute([]u8)text, context.temp_allocator)
	c = TileCollision_Get(&ts2, 5)
	testing.expect(t, c.shape == .Custom && c.count == 3 && c.points[2] == {1, 1}, "the polygon kept")
	testing.expect(t, TileCollision_Get(&ts2, 8).shape == .One_Way && TileCollision_Get(&ts2, 7).trigger, "one-way and trigger kept")
	testing.expect_value(t, len(TileCollision_Polygon(TileCollision_Get(&ts2, 7))), 4)
	testing.expect_value(t, len(TileCollision_Polygon(Tile_Collision{shape = .None})), 0)
}

@(test)
test_tile_colliders_merge_and_sections :: proc(t: ^testing.T) {
	game, scene, tm := tp_setup(`{"terrains": [], "collision": [[2, {"shape": "full", "friction": 0.05}]]}`)
	defer game->terminate()
	// A 3-high floor 40 wide: sections are 16 wide - three boxes (16, 16, 8).
	for y in 9 ..< 12 do for x in 0 ..< 40 do TileMapNode_Set(tm, x, y, 1)
	game->run(1.0 / 60) // (ready: the colliders)
	body := tm.staticBody
	if body == nil || body.tileColliders == nil {
		testing.fail_now(t, "no collider body")
	}
	testing.expect_value(t, len(body.shapes), 3)
	// Ice (its own friction) in the middle of the first section: boxes split by material.
	for x in 4 ..< 8 do TileMapNode_Set(tm, x, 9, 2)
	TileMapNode_BuildColliders(tm, &game.gameContext)
	ice := 0
	for s in body.shapes do if s.friction == 0.05 do ice += 1
	testing.expect_value(t, ice, 1)
	testing.expect(t, len(body.shapes) > 3, "the first section split")

	// An edit rebuilds only its section: the others keep their shapes.
	ids := make(map[b2.ShapeId]bool, allocator = context.temp_allocator)
	for s, i in body.shapes do if body.tileColliders.cells[i].section.x != 0 do ids[s.shapeId] = true
	TileMapNode_EditTile(tm, {2, 10}, -1)
	game->run(1.0 / 60)
	kept := 0
	for s, i in body.shapes do if body.tileColliders.cells[i].section.x != 0 && s.shapeId in ids do kept += 1
	testing.expect_value(t, kept, len(ids))
	testing.expect(t, tm.staticBody == body, "the same body")
	// The hole really is a hole: no shape covers cell (2, 10).
	for c in body.tileColliders.cells do testing.expect(t, !(c.lo.x <= 2 && c.hi.x > 2 && c.lo.y <= 10 && c.hi.y > 10), "nothing over the dug cell")
}

@(test)
test_tile_colliders_slope_one_way_and_hits :: proc(t: ^testing.T) {
	game, scene, tm := tp_setup(`{"terrains": [], "collision": [[3, {"shape": "slope_up_left"}], [4, {"shape": "one_way"}], [5, {"shape": "none"}]]}`)
	defer game->terminate()
	for x in 0 ..< 40 do TileMapNode_Set(tm, x, 11, 1)
	TileMapNode_Set(tm, 10, 10, 3) // (a 45 degree slope down to the right)
	for x in 20 ..< 26 do TileMapNode_Set(tm, x, 6, 4) // a one-way platform
	TileMapNode_Set(tm, 30, 10, 5) // (a tile with no collision)
	game->run(1.0 / 60) // (ready: the colliders)
	solid, oneWay, triggers := TileColliders_ShapeCount(tm.staticBody)
	testing.expect(t, oneWay == 1 && triggers == 0, "one one-way box (child body)")
	testing.expect_value(t, solid, 4) // three floor sections + the slope

	testing.expect(t, tp_lua(t, game, `
hits = {}
Scene.find_node("Ground"):connect("tile_hit", function(h) hits[#hits + 1] = h.other.name .. "@" .. h.x .. "," .. h.y end)`), "connect")
	// Dropped on the slope: slides off to the right.
	slider := tp_ball(scene, "Slider", {10 * 16 + 8, 10 * 16 - 20})
	// Dropped on the merged floor over cell 33 (and on the collision-less tile 30).
	lander := tp_ball(scene, "Lander", {33 * 16 + 8, 8 * 16})
	ghost := tp_ball(scene, "Ghost", {30 * 16 + 8, 9 * 16})
	// Thrown up from below the one-way platform: lands on top.
	jumper := tp_ball(scene, "Jumper", {22 * 16 + 8, 10 * 16 + 2})
	ProcessNodeQueues(scene.manager, &game.gameContext)
	game->run(1.0 / 60)
	b2.Body_SetLinearVelocity(jumper.bodyId, {0, -330})
	for _ in 0 ..< 150 do game->run(1.0 / 60)
	testing.expectf(t, slider.globalPosition.x > 11 * 16, "slid down the slope (x %v)", slider.globalPosition.x)
	testing.expectf(t, jumper.globalPosition.y < 6 * 16 && jumper.globalPosition.y > 5 * 16 - 8, "on the one-way platform (y %v)", jumper.globalPosition.y)
	testing.expectf(t, ghost.globalPosition.y > 10 * 16 && ghost.globalPosition.y < 11 * 16, "through the no-collision tile onto the floor (y %v)", ghost.globalPosition.y)
	testing.expect(t, tp_lua(t, game, `probe = table.concat(hits, " ")`), "join")
	hits := tp_global(game, "probe")
	testing.expectf(t, strings.contains(hits, "Lander@33,11"), "the exact tile under a merged box: %s", hits)
	testing.expectf(t, strings.contains(hits, "Slider@10,10"), "the slope tile: %s", hits)
	testing.expectf(t, strings.contains(hits, "Jumper@22,6") || strings.contains(hits, "Jumper@23,6"), "the one-way tile it landed on: %s", hits)
}

@(test)
test_tile_colliders_triggers :: proc(t: ^testing.T) {
	game, scene, tm := tp_setup(`{"terrains": [], "collision": [[6, {"shape": "full", "trigger": true}], [7, {"shape": "full", "trigger": true}]]}`)
	defer game->terminate()
	for x in 0 ..< 40 do TileMapNode_Set(tm, x, 11, 1)
	TileMapNode_Set(tm, 5, 10, 6) // water on the floor
	TileMapNode_Set(tm, 5, 9, 6)
	game->run(1.0 / 60) // (ready: the colliders)
	_, _, triggers := TileColliders_ShapeCount(tm.staticBody)
	testing.expect_value(t, triggers, 2)
	testing.expect(t, tp_lua(t, game, `
log = {}
local map = Scene.find_node("Ground")
map:connect("tile_entered", function(e) log[#log + 1] = "in " .. e.x .. "," .. e.y .. " " .. e.tile end)
map:connect("tile_exited", function(e) log[#log + 1] = "out " .. e.x .. "," .. e.y end)`), "connect")
	diver := tp_ball(scene, "Diver", {5 * 16 + 8, 6 * 16})
	ProcessNodeQueues(scene.manager, &game.gameContext)
	for _ in 0 ..< 120 do game->run(1.0 / 60)
	testing.expectf(t, diver.globalPosition.y > 10 * 16, "fell through the water onto the floor (y %v)", diver.globalPosition.y)
	testing.expect(t, tp_lua(t, game, `probe = table.concat(log, "; ")`), "join")
	got := tp_global(game, "probe")
	testing.expectf(t, strings.contains(got, "in 5,9 6") && strings.contains(got, "out 5,9") && strings.contains(got, "in 5,10 6"), "entered and left the top, in the bottom: %s", got)
	testing.expectf(t, !strings.contains(got, "out 5,10"), "still in the bottom cell: %s", got)

	// Another water tile there (rebuilt under it): no new events.
	TileMapNode_EditTile(tm, {5, 10}, 7)
	for _ in 0 ..< 5 do game->run(1.0 / 60)
	testing.expect(t, tp_lua(t, game, `probe = table.concat(log, "; ")`), "join")
	testing.expect_value(t, tp_global(game, "probe"), got)
	// Drained (no trigger now): it has left.
	TileMapNode_EditTile(tm, {5, 10}, -1)
	for _ in 0 ..< 5 do game->run(1.0 / 60)
	testing.expect(t, tp_lua(t, game, `probe = table.concat(log, "; ")`), "join")
	testing.expectf(t, strings.has_suffix(tp_global(game, "probe"), "out 5,10"), "left when drained: %s", tp_global(game, "probe"))
}

@(test)
test_tile_colliders_outline :: proc(t: ^testing.T) {
	game, scene, tm := tp_setup()
	defer game->terminate()
	tm.colliderShape = .Outline
	// A frame with a hole: an outer loop and a hole loop.
	for y in 2 ..< 7 do for x in 2 ..< 8 do if !(x >= 4 && x < 6 && y >= 4 && y < 5) do TileMapNode_Set(tm, x, y, 1)
	// And a floor across sections: one loop.
	for x in 0 ..< 40 do TileMapNode_Set(tm, x, 11, 1)
	// A bump on it.
	TileMapNode_Set(tm, 20, 10, 1)
	game->run(1.0 / 60) // (ready: the colliders)
	body := tm.staticBody
	chains, polys := 0, 0
	for s in body.shapes {
		if s.type == .Chain do chains += 1
		else do polys += 1
	}
	testing.expect_value(t, chains, 3)
	testing.expect_value(t, polys, 0)
	for s in body.shapes do if s.type == .Chain do testing.expect(t, b2.Chain_IsValid(s.chainId), "a Box2D chain")
	// The floor's loop is 4 corners (+ the bump of cell 20: 8).
	most := 0
	for s in body.shapes do if s.type == .Chain do most = max(most, len(s.chainPoints))
	testing.expect_value(t, most, 8)
	// A ball rolls along the floor across the section seams (no snag) and rests on it.
	roller := tp_ball(scene, "Roller", {13 * 16, 11 * 16 - 6})
	ProcessNodeQueues(scene.manager, &game.gameContext)
	game->run(1.0 / 60)
	b2.Body_SetLinearVelocity(roller.bodyId, {200, 0})
	for _ in 0 ..< 60 do game->run(1.0 / 60)
	p := roller.globalPosition
	testing.expectf(t, p.x > 17 * 16 && p.y < 11 * 16 && p.y > 10 * 16, "rolled across the section seam at x 256, on the floor (%v)", p)
	// An edit: the chains made again (the same body).
	TileMapNode_EditTile(tm, {30, 11}, -1)
	game->run(1.0 / 60)
	testing.expect(t, tm.staticBody == body, "the same body")
	chains = 0
	for s in body.shapes do if s.type == .Chain do chains += 1
	testing.expect_value(t, chains, 4) // (the floor split in two)
}

@(test)
test_tile_collision_lua :: proc(t: ^testing.T) {
	game, scene, tm := tp_setup(`{"terrains": [], "collision": [[6, {"shape": "full", "trigger": true}]]}`)
	defer game->terminate()
	for x in 0 ..< 40 do TileMapNode_Set(tm, x, 11, 1)
	TileMapNode_Set(tm, 5, 10, 6)
	game->run(1.0 / 60)
	diver := tp_ball(scene, "Diver", {5 * 16 + 8, 10 * 16 + 8})
	ProcessNodeQueues(scene.manager, &game.gameContext)
	for _ in 0 ..< 10 do game->run(1.0 / 60)
	_ = diver
	testing.expect(t, tp_lua(t, game, `
local map = Scene.find_node("Ground")
local c = map:tilemap_tile_collision(6)
local inside = map:tilemap_trigger_cells(Scene.find_node("Diver"))
local ok1 = map:tilemap_set_tile_collision(1, {friction = 0.02, shape = "slope_up_right"})
local bad = map:tilemap_set_tile_collision(1, {shape = "wobbly"})
local ok2 = map:tilemap_set_tile_collision(2, {points = {{0, 1}, {0.5, 0}, {1, 1}}})
local c1, c2 = map:tilemap_tile_collision(1), map:tilemap_tile_collision(2)
probe = string.format("%s %s %d %d,%d | %s %s %s %.2f %s %d", c.shape, tostring(c.trigger), #inside, inside[1].x, inside[1].y,
	tostring(ok1), tostring(bad), c1.shape, c1.friction, c2.shape, #c2.points)`), "Lua ran")
	testing.expect_value(t, tp_global(game, "probe"), "full true 1 5,10 | true false slope_up_right 0.02 custom 3")
	// The colliders follow: the floor is slopes now, with the ice friction.
	n := 0
	for s in tm.staticBody.shapes do if s.type == .Polygon && s.friction > 0.019 && s.friction < 0.021 do n += 1
	testing.expect_value(t, n, 40)
}
