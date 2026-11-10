package engine

import "core:testing"
import lua "lua54"
import rl "vendor:raylib"

// #130: presets give an emitter a whole look, replacing the last one's.

@(test)
test_particle_presets :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("presets", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	pen := ParticleEmitterNode_Create(scene, "Fx")
	pen.gameContext = &game.gameContext
	ProcessNodeQueues(scene.manager, &game.gameContext)
	em := &pen.emitter

	// Every preset emits.
	for p in ParticlePreset {
		ParticleEmitter_ApplyPreset(em, p)
		for _ in 0 ..< 30 do game->run(1.0 / 60)
		testing.expectf(t, em.aliveCount > 0, "%v emits", p)
	}

	// Explosion is one burst; Fire after it is continuous again and keeps no
	// explosion damping (presets don't pile up).
	ParticleEmitter_ApplyPreset(em, .Explosion)
	testing.expect(t, !em.continuous && em.burst == 1, "explosion bursts once")
	ParticleEmitter_ApplyPreset(em, .Fire)
	testing.expect(t, em.continuous && em.burst == 0, "fire is continuous")
	testing.expect_value(t, em.damping, f32(0))
	testing.expect_value(t, em.blendMode, ParticleBlend.Additive)

	// A texture stays.
	em.shape = .Texture
	ParticleEmitter_ApplyPreset(em, .Smoke)
	testing.expect_value(t, em.shape, ParticleShape.Texture)

	// Lua, any case; unknown names are refused.
	L := game.scriptManager.L
	_ = lua.L_dostring(L, `fx = Scene.find_node("Fx"); ok1 = fx:particle_apply_preset("Snow"); ok2 = fx:particle_apply_preset("lava")`)
	lua.getglobal(L, "ok1")
	testing.expect(t, bool(lua.toboolean(L, -1)), "snow applied")
	lua.getglobal(L, "ok2")
	testing.expect(t, !bool(lua.toboolean(L, -1)), "lava refused")
	lua.pop(L, 2)
	testing.expect_value(t, em.wind, [2]f32{15, 0})

	_, known := ParticlePreset_Parse("EXPLOSION")
	testing.expect(t, known, "names parse in any case")
}

// #401: sheet presets use cells of the particle sheet (the node's texture).
@(test)
test_particle_sheet_presets :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("sheet", false)
	pen := ParticleEmitterNode_Create(scene, "Leaves")
	pen.gameContext = &game.gameContext
	ProcessNodeQueues(scene.manager, &game.gameContext)
	em := &pen.emitter
	ParticleEmitterNode_ApplyPreset(pen, .Leaves)
	testing.expect_value(t, pen.texturePath, PARTICLE_SHEET)
	testing.expect_value(t, em.shape, ParticleShape.Texture)
	testing.expect_value(t, em.frameSource, ParticleFrameSource.Regions)
	testing.expect_value(t, em.frameMode, ParticleFrameMode.Random)
	testing.expect_value(t, em.regions.count, 8)
	ParticleEmitterNode_ApplyPreset(pen, .Sparkle)
	testing.expect_value(t, em.regions.count, 6)
	testing.expect_value(t, em.regions.rects[0], rl.Rectangle{0, 128, 64, 64}) // (row 2)
	testing.expect(t, em.frameRandomStart, "sparkle: random start")
	// Fire after it: the sheet stays (a texture stays), its look doesn't pile up.
	ParticleEmitterNode_ApplyPreset(pen, .Fire)
	testing.expect_value(t, pen.texturePath, PARTICLE_SHEET)
	testing.expect(t, !em.frameRandomStart && !em.randomFlipX, "look reset")
	p, known := ParticlePreset_Parse("smoke_puff")
	testing.expect(t, known && p == .SmokePuff, "smoke_puff")
	p, known = ParticlePreset_Parse("Smoke Puff")
	testing.expect(t, known && p == .SmokePuff, "Smoke Puff")
	testing.expect(t, !ParticlePreset_UsesSheet(.Fire) && ParticlePreset_UsesSheet(.Debris), "uses sheet")
}
