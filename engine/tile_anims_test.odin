package engine

import "core:strings"
import "core:testing"

// #275: animated tiles - the sidecar's "animations" (read, written back
// with the terrains), the frame at a time (each frame's own duration), the
// desync offset per cell, a TileMap taking them, the game's clock.
@(test)
test_tile_animations :: proc(t: ^testing.T) {
	src := `{"terrains": [{"name": "Grass", "kind": "blob", "tiles": [[255, 3]]}],
		"animations": [{"frames": [[12, 100], [13, 100], [14, 300]]}, {"frames": [[20, 250], [21, 250]], "desync": true}]}`
	ts, err := Terrains_Parse(transmute([]u8)string(src), context.temp_allocator)
	testing.expectf(t, err == "", "parse: %s", err)
	testing.expect_value(t, len(ts.terrains), 1)
	testing.expect_value(t, len(ts.animations), 2)
	water := &ts.animations[0]
	testing.expect(t, water.frames[2] == 14 && abs(water.durations[2] - 0.3) < 1e-6, "frames and durations")
	testing.expect(t, ts.animations[1].desync, "desync")
	testing.expect_value(t, Terrains_AnimationOf(&ts, 20), 1)
	testing.expect_value(t, Terrains_AnimationOf(&ts, 13), -1) // (only the first frame starts one)

	// Written back: terrains and animations.
	again, err2 := Terrains_Parse(transmute([]u8)Terrains_Serialize(&ts, context.temp_allocator), context.temp_allocator)
	testing.expect(t, err2 == "" && len(again.terrains) == 1 && len(again.animations) == 2, "round trip")
	testing.expect(t, again.animations[0].frames[2] == 14 && abs(again.animations[0].durations[2] - 0.3) < 1e-6 && again.animations[1].desync, "same")

	// The frame at a time: 0.1 s, 0.1 s, 0.3 s, then again.
	at :: proc(a: ^Tile_Anim, s: f64) -> i32 {return Tile_AnimFrame(a, s, {0, 0})}
	testing.expect_value(t, at(water, 0.05), 12)
	testing.expect_value(t, at(water, 0.15), 13)
	testing.expect_value(t, at(water, 0.25), 14)
	testing.expect_value(t, at(water, 0.45), 14)
	testing.expect_value(t, at(water, 0.55), 12) // (0.5 s a loop)
	testing.expect_value(t, at(water, 100.05), 12)
	// Desync: cells start at different points (some neighbours differ).
	grass := &ts.animations[1]
	differ := 0
	for x in 0 ..< 8 do if Tile_AnimFrame(grass, 0, {x, 0}) != Tile_AnimFrame(grass, 0, {x + 1, 0}) do differ += 1
	testing.expect(t, differ > 0, "desynced neighbours")
	testing.expect_value(t, Tile_AnimFrame(water, 0.15, {3, 4}), 13) // (in step without it)

	// A TileMap takes them (by their first tile); the game's clock runs them.
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("anims", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	tm := TileMapNode_Create(scene, "Map")
	TileMapNode_SetAnimations(tm, ts.animations[:])
	testing.expect(t, 12 in tm.anims && 20 in tm.anims && len(tm.anims) == 2, "on the map")
	testing.expect(t, !game.clockRunning, "no clock before a frame")
	for _ in 0 ..< 30 do game->run(1.0 / 60)
	testing.expect(t, game.clockRunning && abs(game.clock - 0.5) < 1e-4, "the clock: the steps' sum")
	TileMapNode_SetAnimations(tm, {})
	testing.expect_value(t, len(tm.anims), 0)
	_ = strings.clone
	free_all(context.temp_allocator)
}
