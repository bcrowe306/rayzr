package engine

import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Particle presets (#130): a starting look for an emitter - fire, smoke,
// sparks, rain, snow, an explosion, magic. Applying one sets the emitter's
// look and motion (everything else back to a common base first, so presets
// don't pile up); its texture, when it has one, stays. The Particles tab's
// Preset menu and Lua's particle_apply_preset use it.
//
// Sheet presets (#401: Leaves, Debris, Smoke Puff, Sparkle) also set the
// texture: cells of PARTICLE_SHEET (Kenney's CC0 Particle Pack and Foliage
// Sprites, assets/kenney/particles/particles.png - 8 x 3 cells of 64 px),
// which the editor copies into the project when one is applied.
// ============================================================================

// Where the sheet presets' texture goes in a project.
PARTICLE_SHEET :: "textures/particles/kenney_particles.png"
PARTICLE_SHEET_CELL :: 64
PARTICLE_SHEET_COLUMNS :: 8

ParticlePreset :: enum {
	Fire,
	Smoke,
	Sparks,
	Rain,
	Snow,
	Explosion,
	Magic,
	// Sheet presets (#401).
	Leaves,
	Debris,
	SmokePuff,
	Sparkle,
}

// ParticlePreset_UsesSheet: the preset's particles are PARTICLE_SHEET's cells.
ParticlePreset_UsesSheet :: proc(p: ParticlePreset) -> bool {
	#partial switch p {
	case .Leaves, .Debris, .SmokePuff, .Sparkle: return true
	}
	return false
}

ParticlePreset_Name :: proc(p: ParticlePreset) -> string {
	switch p {
	case .Fire:      return "Fire"
	case .Smoke:     return "Smoke"
	case .Sparks:    return "Sparks"
	case .Rain:      return "Rain"
	case .Snow:      return "Snow"
	case .Explosion: return "Explosion"
	case .Magic:     return "Magic"
	case .Leaves:    return "Leaves"
	case .Debris:    return "Debris"
	case .SmokePuff: return "Smoke Puff"
	case .Sparkle:   return "Sparkle"
	}
	return ""
}

ParticlePreset_Parse :: proc(name: string) -> (ParticlePreset, bool) {
	// (Spaces and underscores don't count: "smoke_puff", "SmokePuff".)
	squash :: proc(s: string) -> string {
		out, _ := strings.remove_all(s, " ", context.temp_allocator)
		out, _ = strings.remove_all(out, "_", context.temp_allocator)
		return out
	}
	for p in ParticlePreset do if strings.equal_fold(squash(ParticlePreset_Name(p)), squash(name)) do return p, true
	return .Fire, false
}

// sheet_cells: the emitter's frames are PARTICLE_SHEET cells first..last
// (Frame Source Regions).
@(private = "file")
sheet_cells :: proc(e: ^ParticleEmitter, first, last: int) {
	e.shape, e.frameSource = .Texture, .Regions
	e.regions.count = 0
	for k in first ..= last {
		c := f32(PARTICLE_SHEET_CELL)
		e.regions.rects[e.regions.count] = {f32(k % PARTICLE_SHEET_COLUMNS) * c, f32(k / PARTICLE_SHEET_COLUMNS) * c, c, c}
		e.regions.count += 1
	}
}

@(private = "file")
set_ramp :: proc(e: ^ParticleEmitter, stops: ..ColorStop) {
	e.useColorRamp = true
	e.colorRamp.count = 0
	for s in stops do ColorRamp_AddStop(&e.colorRamp, s.position, s.color)
}

@(private = "file")
set_curve :: proc(c: ^ParticleCurve, points: ..[2]f32) {
	c.count = 0
	for p in points {
		if c.count >= MAX_CURVE_POINTS do break
		c.points[c.count] = p
		c.count += 1
	}
}

// preset_base: the settings every preset starts from (the look and the
// motion; not the texture, collision layers, visibility or GPU mode).
@(private = "file")
preset_base :: proc(e: ^ParticleEmitter) {
	e.burst = 0
	e.continuous = true
	e.emitting = true
	e.lifetimeVariance = 0.2
	e.size, e.sizeVariance, e.sizeSpread = {6, 6}, 0, 0
	e.scaleStart, e.scaleEnd = {1, 1}, {1, 1}
	e.rotation, e.rotationVariance, e.rotationSpread = 0, 0, 0
	e.torque, e.torqueVariance, e.torqueSpread, e.torqueAcceleration = 0, 0, 0, 0
	e.particleColor, e.colorEnd, e.colorVariance = rl.WHITE, rl.WHITE, 0
	e.spread = {0, 0}
	e.velocity, e.velocityVariance, e.velocitySpread, e.velocityScale, e.acceleration = 0, 1, 0, 1, 0
	e.angle, e.angleVariance, e.angleSpread = -90, 1, 0
	e.gravityDirection, e.gravityVelocity, e.wind = {0, 1}, 0, {0, 0}
	e.collisionEnabled = false
	if e.shape != .Texture do e.shape = .Circle
	e.blendMode = .Alpha
	e.alignToVelocity = false
	e.emissionShape, e.emissionRadius, e.emissionInnerRadius, e.emitAlongNormal = .Point, 0, 0, false
	e.radialVelocity, e.orbitVelocity, e.damping = 0, 0, 0
	e.sizeCurve.count, e.alphaCurve.count, e.speedCurve.count = 0, 0, 0
	e.localSpace = true
	e.trailLength, e.trailSegment, e.trailWidth = 0, 6, 1
	e.frameLoop, e.frameRandomStart = true, false
	e.texturePivot, e.randomFlipX, e.randomFlipY = {0.5, 0.5}, false, false
}

// ParticleEmitter_ApplyPreset gives the emitter a preset's look and restarts it.
ParticleEmitter_ApplyPreset :: proc(e: ^ParticleEmitter, preset: ParticlePreset) {
	if e == nil do return
	preset_base(e)
	switch preset {
	case .Fire:
		// Flames licking up from a small disc, bright where they overlap.
		e.amount, e.lifetime = 60, 1.0
		e.size, e.sizeVariance = {14, 14}, 0.4
		e.angleSpread, e.velocity, e.velocitySpread = 15, 90, 30
		e.gravityDirection, e.gravityVelocity = {0, -1}, 60
		e.emissionShape, e.emissionRadius = .Circle, 10
		e.blendMode = .Additive
		set_ramp(e, {0, {255, 240, 180, 255}}, {0.4, {255, 140, 30, 220}}, {0.75, {200, 40, 20, 120}}, {1, {60, 20, 10, 0}})
		set_curve(&e.sizeCurve, {0, 1}, {1, 0.3})
	case .Smoke:
		// Soft puffs that rise, grow and fade, left behind where they rose.
		e.amount, e.lifetime = 30, 3
		e.size, e.sizeVariance = {20, 20}, 0.3
		e.rotationSpread, e.rotationVariance = 180, 1
		e.angleSpread, e.velocity, e.velocitySpread = 20, 40, 15
		e.gravityDirection, e.gravityVelocity = {0, -1}, 10
		e.damping = 0.3
		e.emissionShape, e.emissionRadius = .Circle, 12
		e.localSpace = false
		set_ramp(e, {0, {120, 120, 120, 0}}, {0.15, {110, 110, 110, 160}}, {1, {90, 90, 90, 0}})
		set_curve(&e.sizeCurve, {0, 0.5}, {1, 2})
	case .Sparks:
		// Fast streaks thrown up and out, falling as they cool.
		e.amount, e.lifetime = 40, 0.6
		e.shape, e.size = .Line, {8, 2}
		e.alignToVelocity = true
		e.angleSpread, e.velocity, e.velocitySpread = 60, 300, 120
		e.gravityVelocity = 600
		e.damping = 0.5
		e.blendMode = .Additive
		set_ramp(e, {0, {255, 255, 220, 255}}, {0.5, {255, 180, 60, 255}}, {1, {255, 80, 0, 0}})
	case .Rain:
		// Thin drops falling across a wide line (put the emitter above the view).
		e.amount, e.lifetime = 150, 1.2
		e.shape, e.size = .Line, {14, 2}
		e.alignToVelocity = true
		e.angle, e.angleSpread = 95, 2
		e.velocity, e.velocitySpread = 700, 50
		e.emissionShape, e.spread = .Line, {640, 0}
		e.localSpace = false
		e.useColorRamp = false
		e.particleColor, e.colorEnd = {170, 190, 230, 170}, {170, 190, 230, 170}
	case .Snow:
		// Flakes drifting down and sideways over a wide line.
		e.amount, e.lifetime = 120, 6
		e.size, e.sizeVariance = {4, 4}, 0.5
		e.angle, e.angleSpread = 90, 20
		e.velocity, e.velocitySpread = 40, 15
		e.wind = {15, 0}
		e.emissionShape, e.spread = .Line, {640, 0}
		e.localSpace = false
		set_ramp(e, {0, {255, 255, 255, 0}}, {0.1, {255, 255, 255, 230}}, {0.85, {255, 255, 255, 230}}, {1, {255, 255, 255, 0}})
	case .Explosion:
		// One burst in every direction that slows, cools and turns to smoke.
		e.amount, e.lifetime, e.lifetimeVariance = 80, 0.9, 0.3
		e.burst, e.continuous = 1, false
		e.size, e.sizeVariance = {10, 10}, 0.5
		e.angle, e.angleSpread = 0, 180
		e.velocity, e.velocitySpread = 260, 140
		e.damping = 2.5
		e.blendMode = .Additive
		set_ramp(e, {0, {255, 255, 230, 255}}, {0.25, {255, 150, 40, 255}}, {0.6, {180, 40, 20, 180}}, {1, {50, 50, 50, 0}})
		set_curve(&e.sizeCurve, {0, 0.6}, {0.2, 1.2}, {1, 0.4})
	case .Magic:
		// Glowing motes circling a disc and drifting up.
		e.amount, e.lifetime = 50, 1.6
		e.size, e.sizeVariance = {6, 6}, 0.5
		e.angleSpread, e.velocity, e.velocitySpread = 180, 30, 20
		e.emissionShape, e.emissionRadius = .Circle, 24
		e.orbitVelocity = 90
		e.trailLength, e.trailSegment, e.trailWidth = 8, 4, 0.8
		e.gravityDirection, e.gravityVelocity = {0, -1}, 20
		e.blendMode = .Additive
		set_ramp(e, {0, {180, 120, 255, 0}}, {0.2, {200, 160, 255, 255}}, {0.7, {120, 220, 255, 200}}, {1, {80, 120, 255, 0}})
	case .Leaves:
		// Autumn leaves, a random one each, tumbling down and drifting
		// across a wide line (put the emitter above the view).
		sheet_cells(e, 0, 7)
		e.frameMode = .Random
		e.amount, e.lifetime = 25, 6
		e.size, e.sizeVariance, e.sizeSpread = {16, 16}, 1, 6
		e.angle, e.angleSpread = 90, 25
		e.velocity, e.velocitySpread = 35, 15
		e.gravityVelocity, e.wind = 10, {25, 0}
		e.rotationSpread, e.rotationVariance = 180, 1
		e.torqueSpread, e.torqueVariance = 120, 1
		e.emissionShape, e.spread = .Line, {320, 0}
		e.randomFlipX = true
		e.localSpace = false
		set_ramp(e, {0, {210, 200, 80, 0}}, {0.08, {230, 160, 50, 255}}, {0.85, {190, 80, 40, 255}}, {1, {140, 60, 30, 0}})
		e.colorVariance = 0.25
	case .Debris:
		// One burst of rubble thrown up, spinning, falling back.
		sheet_cells(e, 12, 15)
		e.frameMode = .Random
		e.amount, e.lifetime, e.lifetimeVariance = 24, 1.2, 0.3
		e.burst, e.continuous = 1, false
		e.size, e.sizeVariance, e.sizeSpread = {12, 12}, 1, 6
		e.angle, e.angleSpread = -90, 60
		e.velocity, e.velocitySpread = 260, 100
		e.gravityVelocity = 700
		e.rotationSpread, e.rotationVariance = 180, 1
		e.torqueSpread, e.torqueVariance = 600, 1
		e.randomFlipX, e.randomFlipY = true, true
		e.localSpace = false
		set_ramp(e, {0, {150, 120, 90, 255}}, {0.8, {120, 95, 70, 255}}, {1, {100, 80, 60, 0}})
	case .SmokePuff:
		// Puffs that open into rings as they rise and fade (the sheet's
		// four frames over each one's life).
		sheet_cells(e, 8, 11)
		e.frameMode = .OverLifetime
		e.amount, e.lifetime = 10, 1.6
		e.size, e.sizeVariance = {32, 32}, 0.3
		e.angleSpread, e.velocity, e.velocitySpread = 25, 35, 15
		e.gravityDirection, e.gravityVelocity = {0, -1}, 10
		e.damping = 0.6
		e.rotationSpread, e.rotationVariance = 180, 1
		e.randomFlipX, e.randomFlipY = true, true
		e.localSpace = false
		set_ramp(e, {0, {200, 200, 200, 0}}, {0.15, {190, 190, 190, 220}}, {1, {160, 160, 160, 0}})
		set_curve(&e.sizeCurve, {0, 0.6}, {1, 1.6})
	case .Sparkle:
		// Twinkling stars around a disc, each its own frame of the twinkle.
		sheet_cells(e, 16, 21)
		e.frameMode, e.frameSpeed, e.frameRandomStart = .Speed, 10, true
		e.amount, e.lifetime = 30, 1.2
		e.size, e.sizeVariance = {18, 18}, 0.5
		e.angleSpread, e.velocity = 180, 10
		e.emissionShape, e.emissionRadius = .Circle, 32
		e.randomFlipX = true
		e.blendMode = .Additive
		set_ramp(e, {0, {255, 230, 150, 0}}, {0.2, {255, 245, 200, 255}}, {0.8, {255, 220, 120, 230}}, {1, {255, 200, 80, 0}})
		set_curve(&e.sizeCurve, {0, 0}, {0.3, 1}, {1, 0.2})
	}
	ParticleEmitter_Restart(e)
}

// ParticleEmitterNode_ApplyPreset: a preset on the node's emitter; a sheet
// preset also sets the texture to PARTICLE_SHEET (#401; the editor copies
// it into the project first).
ParticleEmitterNode_ApplyPreset :: proc(pen: ^ParticleEmitterNode, preset: ParticlePreset) {
	if pen == nil do return
	if ParticlePreset_UsesSheet(preset) && pen.texturePath != PARTICLE_SHEET do ParticleEmitterNode_SetTexture(pen, PARTICLE_SHEET)
	ParticleEmitter_ApplyPreset(&pen.emitter, preset)
}
