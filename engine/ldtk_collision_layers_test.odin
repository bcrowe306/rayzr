package engine

import "core:encoding/json"
import os "osx"
import "core:strings"
import "core:testing"
import lua "lua54"

// #405: collision layers and mask per IntGrid value, the level's as the
// default. Level A's Collisions (LDTK_WORLDS_PROJECT):
//   row 0: wall wall platform platform
//   row 1: water water 0 wall
// Walls use the level's layers (Layer2), water its own (Layer3); platforms
// build nothing. Falling boxes see only what their mask names.
@(test)
test_ldtk_collision_layers_per_value :: proc(t: ^testing.T) {
	_ = os.make_directory_all("test_ldtk_layers_zz")
	defer os.remove_all("test_ldtk_layers_zz")
	_ = os.write_entire_file("test_ldtk_layers_zz/game.ldtk", transmute([]u8)string(LDTK_WORLDS_PROJECT))
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("ldtk_layers", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	ln := cast(^LdtkLevelNode)Node_CreateByTypeName(scene, "LdtkLevelNode")
	ln.gameContext = &game.gameContext
	ln.spawnEntities = false
	testing.expect(t, ln.categoryLayers == DEFAULT_COLLISION_CATEGORIES && ln.maskLayers == DEFAULT_COLLISION_MASK, "a new level's default layers are the physics defaults")
	ln.categoryLayers = {.Layer2}
	LdtkLevelNode_SetCollisionRule(ln, {layer = "Collisions", value = 1, type = .Solid, friction = 0.5})
	LdtkLevelNode_SetCollisionRule(ln, {layer = "Collisions", value = 3, type = .Solid, friction = 0.5, customLayers = true, categoryLayers = {.Layer3}, maskLayers = DEFAULT_COLLISION_MASK})
	LdtkLevelNode_SetProject(ln, "test_ldtk_layers_zz/game.ldtk", "A")
	game->run(0.016)
	game->run(0.016)

	wallCat, _ := LdtkLevelNode_RuleLayers(ln, LdtkLevelNode_CollisionRule(ln, "Collisions", 1))
	waterCat, _ := LdtkLevelNode_RuleLayers(ln, LdtkLevelNode_CollisionRule(ln, "Collisions", 3))
	testing.expect(t, wallCat == {.Layer2} && waterCat == {.Layer3}, "walls inherit the level's layers, water has its own")

	drop :: proc(scene: ^Scene, game: ^Game, name: string, x: f32, mask: CollisionLayerSet) -> ^DynamicBodyNode {
		b := DynamicBodyNode_Create(scene, name)
		b.position = {x, -30}
		b.globalPosition = b.position
		b.gameContext = &game.gameContext
		shape := MakeBoxPhysicsShape(8, 8, {0, 0}, 0)
		shape.maskLayers = mask
		DynamicBodyNode_AddShape(b, shape, &game.gameContext)
		return b
	}
	onWalls := drop(scene, game, "WallsOnly", 8, {.Layer2})  // stops on the wall at row 0
	onWater := drop(scene, game, "WaterOnly", 24, {.Layer3}) // through the wall, onto the water at row 1
	onNone := drop(scene, game, "Neither", 56, {.Layer1})    // through everything
	for _ in 0 ..< 60 do game->run(0.016)
	testing.expectf(t, onWalls.position.y < 0 && onWalls.position.y > -12, "mask Layer2 lands on the wall (y=%v)", onWalls.position.y)
	testing.expectf(t, onWater.position.y > 4 && onWater.position.y < 16, "mask Layer3 passes the wall and lands on the water (y=%v)", onWater.position.y)
	testing.expectf(t, onNone.position.y > 40, "mask Layer1 falls through the level (y=%v)", onNone.position.y)

	// Lua: the values' layers and mask (1-16).
	ScriptVFS_RegisterEmbedded("ldtk_layers_probe_zz.lua", `
local P = {}
function P:ready()
    local v = self.node:ldtk_get_int_grid_values("Collisions")
    layers_probe = v[1].layers[1] .. "|" .. v[3].layers[1] .. "|" .. #v[3].mask
end
return P
`)
	Script_AttachToNode(ln, "ldtk_layers_probe_zz.lua", nil, &game.scriptManager)
	game->run(0.016)
	L := game.scriptManager.L
	lua.getglobal(L, "layers_probe")
	testing.expect_value(t, string(lua.tostring(L, -1)), "2|3|16")
	lua.pop(L, 1)

	// Saved with the scene: the value's own layers; read back.
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(text, `"layers": ["Layer3"]`), "own layers saved: %s", text)
	testing.expect(t, strings.count(text, `"layers": [`) == 1, "values on the default save no layers")
	scene2 := game->createScene("ldtk_layers2", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	Scene_InstantiateFromJSON(scene2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(scene2.manager, &game.gameContext)
	back: ^LdtkLevelNode
	for n in scene2.manager.nodes do if n != nil && n.typeId == LdtkLevelNode do back = cast(^LdtkLevelNode)n
	testing.expect(t, back != nil, "level read back")
	if back == nil do return
	testing.expect(t, back.categoryLayers == {.Layer2}, "the level's layers read back")
	water := LdtkLevelNode_CollisionRule(back, "Collisions", 3)
	wall := LdtkLevelNode_CollisionRule(back, "Collisions", 1)
	testing.expect(t, water.customLayers && water.categoryLayers == {.Layer3} && water.maskLayers == DEFAULT_COLLISION_MASK, "water's own layers read back")
	testing.expect(t, !wall.customLayers, "walls still use the default")
}

// Scenes saved before #405: rules without layers use the level's, and a
// level without layer properties gets the physics defaults (Layer1, all).
@(test)
test_ldtk_collision_layers_old_scene :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("ldtk_layers_old", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	ln := cast(^LdtkLevelNode)Node_CreateByTypeName(scene, "LdtkLevelNode")
	cfg, err := json.parse_string(`{"collision": [{"layer": "Collisions", "value": 1, "type": "solid", "friction": 0.5, "restitution": 0.2}]}`, allocator = context.temp_allocator)
	testing.expect(t, err == nil, "parses")
	Ldtk_ReadNodeConfig(ln, cfg.(json.Object), json.Object{}, "")
	rule := LdtkLevelNode_CollisionRule(ln, "Collisions", 1)
	testing.expect(t, rule.type == .Solid && !rule.customLayers, "an old rule uses the level's layers")
	cat, mask := LdtkLevelNode_RuleLayers(ln, rule)
	testing.expect(t, cat == DEFAULT_COLLISION_CATEGORIES && mask == DEFAULT_COLLISION_MASK, "on Layer1, colliding with everything (as before)")
	// The legacy (rule-less) setup too.
	clear(&ln.collisionRules)
	legacy := LdtkLevelNode_CollisionRule(ln, "Collisions", 1)
	testing.expect(t, legacy.type == .Solid && !legacy.customLayers, "legacy solid values use the level's layers")
}

// TileMapNode: its colliders are on its collision layers and mask (#405).
@(test)
test_tilemap_collision_layers :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("tilemap_layers", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	tm := cast(^TileMapNode)Node_CreateByTypeName(scene, "TileMapNode")
	testing.expect(t, tm.categoryLayers == DEFAULT_COLLISION_CATEGORIES && tm.maskLayers == DEFAULT_COLLISION_MASK, "defaults: Layer1, all")
	tm.tileSize = {16, 16}
	tm.mapSize = {4, 2}
	TileMapNode_Layout(tm)
	for x in 0 ..< 4 do TileMapNode_Set(tm, x, 1, 0)
	tm.solid = true
	tm.categoryLayers = {.Layer4}
	tm.maskLayers = {.Layer1, .Layer2}
	tm.gameContext = &game.gameContext
	TileMapNode_BuildColliders(tm, &game.gameContext)
	testing.expect(t, tm.staticBody != nil && len(tm.staticBody.shapes) > 0, "colliders built")
	if tm.staticBody == nil do return
	for s in tm.staticBody.shapes {
		testing.expect(t, s.categoryLayers == {.Layer4} && s.maskLayers == {.Layer1, .Layer2}, "shape on the map's layers and mask")
	}
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(text, "Layer4"), "layers saved: %s", text)
}
