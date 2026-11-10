package engine

import "core:strings"
import "core:testing"
import rl "vendor:raylib"

// #126: the particle texture is saved (as "particle_texture"), blend modes,
// sprite-sheet frames over life / at a speed / random, align to velocity.

@(test)
test_particle_sheet_frames :: proc(t: ^testing.T) {
	emitter: ParticleEmitter
	ParticleEmitter_Init(&emitter)
	defer ParticleEmitter_Destroy(&emitter)
	emitter.sheetColumns, emitter.sheetRows = 2, 2
	ParticleEmitter_ResolveFrames(&emitter, {texSize = {64, 64}})
	p := Particle{age = 0.5, agePercent = 0.5, lifetime = 1, frameSeed = 7}

	emitter.frameMode = .OverLifetime
	testing.expect_value(t, Particle_Frame(&emitter, p), 2) // halfway through 4 frames
	p.agePercent = 1
	testing.expect_value(t, Particle_Frame(&emitter, p), 3) // (the last at death, not past it)
	emitter.frameMode = .Speed
	emitter.frameSpeed = 12
	testing.expect_value(t, Particle_Frame(&emitter, p), 2) // 6 frames in, looping over 4
	emitter.frameMode = .Random
	testing.expect_value(t, Particle_Frame(&emitter, p), 3) // 7 % 4, fixed per particle
	emitter.sheetColumns, emitter.sheetRows = 1, 1
	ParticleEmitter_ResolveFrames(&emitter, {texSize = {64, 64}})
	testing.expect_value(t, Particle_Frame(&emitter, p), 0)

	// The frame's part of the texture.
	tex := rl.Texture2D{id = 1, width = 64, height = 64}
	emitter.texture = &tex
	emitter.localSpace = false
	emitter.sheetColumns, emitter.sheetRows = 2, 2
	ParticleEmitter_ResolveFrames(&emitter, {})
	emitter.frameMode = .OverLifetime
	p.shape, p.size, p.scale, p.alive = .Texture, {8, 8}, {1, 1}, true
	p.agePercent = 0.99 // frame 3: bottom right
	q := Particle_QuadOf(&emitter, p)
	testing.expect_value(t, q.texture, Particle_Quad_Texture.Texture)
	testing.expect_value(t, q.uv, [4]f32{0.5, 0.5, 1, 1})
	emitter.texture = nil
}

@(test)
test_particle_align_to_velocity :: proc(t: ^testing.T) {
	emitter: ParticleEmitter
	ParticleEmitter_Init(&emitter)
	defer ParticleEmitter_Destroy(&emitter)
	emitter.localSpace = false
	p := Particle{shape = .Rectangle, size = {8, 2}, scale = {1, 1}, velocity = {0, 50}, rotation = 10, alive = true}
	testing.expect_value(t, Particle_QuadOf(&emitter, p).rotation, 10) // off: its own rotation
	emitter.alignToVelocity = true
	emitter.rotation = 5 // (an offset on top)
	testing.expect_value(t, Particle_QuadOf(&emitter, p).rotation, 95) // moving down: 90
}

@(test)
test_particle_look_saving :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("look", false)
	pen := ParticleEmitterNode_Create(scene, "Sparks")
	pen.gameContext = &game.gameContext
	ParticleEmitterNode_SetTexture(pen, "textures/spark.png") // (headless: the path only)
	pen.emitter.blendMode = .Additive
	pen.emitter.sheetColumns, pen.emitter.sheetRows = 4, 2
	pen.emitter.frameMode = .Random
	pen.emitter.alignToVelocity = true
	ProcessNodeQueues(scene.manager, &game.gameContext)
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(saved, `"particle_texture": "textures/spark.png"`), "the texture: %s", saved)
	// (Not "texture": that key on any node loads as a child sprite - #97.)
	testing.expect(t, !strings.contains(saved, `"texture": "textures/spark.png"`), "not as \"texture\"")

	again := game->createScene("look2", false)
	testing.expect(t, Scene_InstantiateFromJSON(again, transmute([]u8)saved, &game.gameContext), "loads")
	ProcessNodeQueues(again.manager, &game.gameContext)
	re := cast(^ParticleEmitterNode)Scene_FindNodeByName(again, "Sparks")
	testing.expect(t, re != nil, "found")
	if re == nil do return
	testing.expect_value(t, re.texturePath, "textures/spark.png")
	testing.expect_value(t, re.emitter.blendMode, ParticleBlend.Additive)
	testing.expect_value(t, re.emitter.sheetColumns, 4)
	testing.expect_value(t, re.emitter.sheetRows, 2)
	testing.expect_value(t, re.emitter.frameMode, ParticleFrameMode.Random)
	testing.expect(t, re.emitter.alignToVelocity, "align")
	testing.expect_value(t, len(GetChildrenView(again.manager, re)), 0) // no stray sprite
}
