package engine

import "core:encoding/json"
import "core:strings"
import "core:testing"
import rl "vendor:raylib"

// #401: particle frames from a grid range, a slicing preset, regions (an
// atlased texture's offset in), an Aseprite tag (direction, timing); loop /
// once, a random start, random flips and the pivot; saving.

@(test)
test_particle_frames_slices :: proc(t: ^testing.T) {
	emitter: ParticleEmitter
	ParticleEmitter_Init(&emitter)
	defer ParticleEmitter_Destroy(&emitter)

	// Grid with a range: cells 2.. of 4 x 2, three of them.
	emitter.sheetColumns, emitter.sheetRows = 4, 2
	emitter.frameFirst, emitter.frameCount = 2, 3
	ParticleEmitter_ResolveFrames(&emitter, {texSize = {64, 32}})
	testing.expect_value(t, emitter.frames.count, 3)
	testing.expect_value(t, Particle_FrameRect(&emitter.frames, 0), rl.Rectangle{32, 0, 16, 16})
	testing.expect_value(t, Particle_FrameRect(&emitter.frames, 2), rl.Rectangle{0, 16, 16, 16}) // (wraps to the next row)

	// The slicing preset by cell size: 10 px cells, margin 1, spacing 2.
	emitter.frameSource = .Slices
	emitter.frameFirst, emitter.frameCount = 0, 0
	ParticleEmitter_ResolveFrames(&emitter, {texSize = {38, 14}, slice = {cellSize = {10, 10}, margin = {1, 1}, spacing = {2, 2}}})
	testing.expect_value(t, emitter.frames.count, 3) // 3 x 1 fit
	testing.expect_value(t, Particle_FrameRect(&emitter.frames, 1), rl.Rectangle{13, 1, 10, 10})
	// By the grid (2 x 2 of a 64 px sheet), from cell 1.
	emitter.frameFirst = 1
	ParticleEmitter_ResolveFrames(&emitter, {texSize = {64, 64}, slice = {grid = {2, 2}}})
	testing.expect_value(t, emitter.frames.count, 3)
	testing.expect_value(t, Particle_FrameRect(&emitter.frames, 0), rl.Rectangle{32, 0, 32, 32})
	// No preset: the whole texture.
	ParticleEmitter_ResolveFrames(&emitter, {texSize = {64, 64}})
	testing.expect_value(t, emitter.frames.count, 1)
}

@(test)
test_particle_frames_regions_atlas :: proc(t: ^testing.T) {
	emitter: ParticleEmitter
	ParticleEmitter_Init(&emitter)
	defer ParticleEmitter_Destroy(&emitter)
	emitter.localSpace = false
	emitter.frameSource = .Regions
	emitter.regions.rects[0] = {0, 0, 8, 8}
	emitter.regions.rects[1] = {8, 0, 8, 16}
	emitter.regions.count = 2
	emitter.frameMode = .Random

	// An atlased texture (exported games): its region in a 256 px page.
	tex := rl.Texture2D{id = 1, width = 256, height = 256}
	emitter.texture = &tex
	ParticleEmitter_ResolveFrames(&emitter, {texSize = {256, 256}, region = {128, 64, 16, 16}})
	testing.expect_value(t, emitter.frames.count, 2)
	p := Particle{shape = .Texture, size = {8, 8}, scale = {1, 1}, alive = true, frameSeed = 1} // frame 1
	q := Particle_QuadOf(&emitter, p)
	testing.expect_value(t, q.uv, [4]f32{136.0 / 256, 64.0 / 256, 144.0 / 256, 80.0 / 256})

	// A whole atlased texture (Grid 1 x 1) is its region, not the page.
	emitter.frameSource = .Grid
	ParticleEmitter_ResolveFrames(&emitter, {texSize = {256, 256}, region = {128, 64, 16, 16}})
	q = Particle_QuadOf(&emitter, p)
	testing.expect_value(t, q.uv, [4]f32{0.5, 0.25, 144.0 / 256, 80.0 / 256})
	emitter.texture = nil

	// Saved regions read back (empty ones skipped).
	rg: Particle_Regions
	v, err := json.parse_string(`[[1, 2, 3, 4], [0, 0, 0, 5], [5.5, 6, 7, 8]]`, allocator = context.temp_allocator)
	testing.expect_value(t, err, json.Error.None)
	ParticleRegions_FromJSON(&rg, v.(json.Array))
	testing.expect_value(t, rg.count, 2)
	testing.expect_value(t, rg.rects[1], rl.Rectangle{5.5, 6, 7, 8})
}

@(test)
test_particle_frames_aseprite :: proc(t: ^testing.T) {
	emitter: ParticleEmitter
	ParticleEmitter_Init(&emitter)
	defer ParticleEmitter_Destroy(&emitter)
	emitter.frameSource = .Aseprite
	// Five 8 x 8 frames (sheet: 3 a row), 100 ms each but frame 2 is 300.
	doc := Ase_Document{width = 8, height = 8}
	doc.frames = make([dynamic]Ase_Frame, context.temp_allocator)
	for d in ([]int{100, 100, 300, 100, 100}) do append(&doc.frames, Ase_Frame{duration = d})
	doc.tags = make([dynamic]Ase_Tag, context.temp_allocator)
	append(&doc.tags, Ase_Tag{name = "spin", from = 1, to = 3, direction = .Ping_Pong})
	append(&doc.tags, Ase_Tag{name = "back", from = 1, to = 3, direction = .Reverse})
	cols := Ase_SheetColumns(len(doc.frames))
	testing.expect_value(t, cols, 3)

	// Every frame, the file's timing (0.7 s): Speed, 0.45 s in = frame 2.
	ParticleEmitter_ResolveFrames(&emitter, {ase = &doc, aseCols = cols})
	testing.expect_value(t, emitter.frames.count, 5)
	testing.expect(t, emitter.frames.timed, "timed")
	testing.expect_value(t, Particle_FrameRect(&emitter.frames, 4), rl.Rectangle{8, 8, 8, 8})
	emitter.frameMode = .Speed
	p := Particle{age = 0.45, lifetime = 1}
	testing.expect_value(t, Particle_Frame(&emitter, p), 2)
	p.age = 0.75 // past the end: loops to frame 0
	testing.expect_value(t, Particle_Frame(&emitter, p), 0)
	emitter.frameLoop = false
	testing.expect_value(t, Particle_Frame(&emitter, p), 4) // once: stays on the last
	emitter.frameLoop = true
	// Over Lifetime: the frames' shares of the life (frame 2: 0.2 .. 0.5 of 0.7 s).
	emitter.frameMode = .OverLifetime
	p.agePercent = 0.5
	testing.expect_value(t, Particle_Frame(&emitter, p), 2)

	// Ping-pong 1..3: 1 2 3 2; reverse: 3 2 1.
	ParticleEmitter_ResolveFrames(&emitter, {ase = &doc, aseCols = cols, tag = "spin"})
	testing.expect_value(t, emitter.frames.count, 4)
	testing.expect_value(t, Particle_FrameRect(&emitter.frames, 3), Particle_FrameRect(&emitter.frames, 1)) // (frame 2 again)
	testing.expect_value(t, Particle_FrameRect(&emitter.frames, 2), rl.Rectangle{0, 8, 8, 8})               // frame 3
	ParticleEmitter_ResolveFrames(&emitter, {ase = &doc, aseCols = cols, tag = "back"})
	testing.expect_value(t, emitter.frames.count, 3)
	testing.expect_value(t, Particle_FrameRect(&emitter.frames, 0), rl.Rectangle{0, 8, 8, 8})
	// Timing off: even shares at Frame Speed.
	emitter.frameFileTiming = false
	ParticleEmitter_ResolveFrames(&emitter, {ase = &doc, aseCols = cols, tag = "back"})
	testing.expect(t, !emitter.frames.timed, "not timed")
	// No file: the whole texture.
	ParticleEmitter_ResolveFrames(&emitter, {})
	testing.expect_value(t, emitter.frames.count, 1)
}

@(test)
test_particle_frames_loop_start_flip_pivot :: proc(t: ^testing.T) {
	emitter: ParticleEmitter
	ParticleEmitter_Init(&emitter)
	defer ParticleEmitter_Destroy(&emitter)
	emitter.localSpace = false
	emitter.sheetColumns, emitter.sheetRows = 4, 1
	ParticleEmitter_ResolveFrames(&emitter, {texSize = {64, 16}})
	emitter.frameMode = .Speed
	emitter.frameSpeed = 10
	p := Particle{age = 0.55, agePercent = 0.5, lifetime = 1} // 5 frames in
	testing.expect_value(t, Particle_Frame(&emitter, p), 1)   // looping over 4
	emitter.frameLoop = false
	testing.expect_value(t, Particle_Frame(&emitter, p), 3) // once: the last
	emitter.frameLoop = true

	// A random start (seed bits 10+): 3 << 10 starts on frame 3.
	emitter.frameRandomStart = true
	p.frameSeed = 3 << 10
	p.age = 0.05
	testing.expect_value(t, Particle_Frame(&emitter, p), 3)
	p.age = 0.15
	testing.expect_value(t, Particle_Frame(&emitter, p), 0) // (then on, wrapping)
	emitter.frameMode = .OverLifetime
	p.agePercent = 0.3 // frame 1 + 3
	testing.expect_value(t, Particle_Frame(&emitter, p), 0)
	emitter.frameRandomStart = false

	// Flips (seed bits 8, 9) swap the frame's uv; the pivot follows.
	tex := rl.Texture2D{id = 1, width = 64, height = 16}
	emitter.texture = &tex
	emitter.sheetColumns = 1
	ParticleEmitter_ResolveFrames(&emitter, {})
	emitter.randomFlipX, emitter.randomFlipY = true, true
	emitter.texturePivot = {0.25, 1}
	q := Particle{shape = .Texture, size = {8, 8}, scale = {1, 1}, alive = true, frameSeed = 1 << 8}
	quad := Particle_QuadOf(&emitter, q)
	testing.expect_value(t, quad.uv, [4]f32{1, 0, 0, 1}) // X only
	testing.expect_value(t, quad.pivot, [2]f32{0.75, 1})
	q.frameSeed = 3 << 8
	quad = Particle_QuadOf(&emitter, q)
	testing.expect_value(t, quad.uv, [4]f32{1, 1, 0, 0})
	testing.expect_value(t, quad.pivot, [2]f32{0.75, 0})
	q.frameSeed = 0
	quad = Particle_QuadOf(&emitter, q)
	testing.expect_value(t, quad.uv, [4]f32{0, 0, 1, 1})
	testing.expect_value(t, quad.pivot, [2]f32{0.25, 1})
	testing.expect_value(t, quad.center, [2]f32{0, 0}) // (the particle's position: the pivot is drawn there)
	emitter.texture = nil
}

@(test)
test_particle_frames_saving :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("frames", false)
	pen := ParticleEmitterNode_Create(scene, "Leaves")
	pen.gameContext = &game.gameContext
	// (Before #401: the defaults an old scene loads with.)
	testing.expect(t, pen.emitter.frameLoop && pen.emitter.frameFileTiming, "defaults")
	testing.expect_value(t, pen.emitter.texturePivot, [2]f32{0.5, 0.5})
	testing.expect_value(t, pen.emitter.frameSource, ParticleFrameSource.Grid)

	ParticleEmitterNode_SetTexture(pen, "textures/leaves.png") // (headless: the path only)
	em := &pen.emitter
	em.frameSource = .Regions
	em.regions.rects[0], em.regions.rects[1], em.regions.count = {0, 0, 16, 16}, {16, 0, 16, 8}, 2
	em.frameFirst, em.frameCount = 1, 2
	em.frameLoop, em.frameRandomStart, em.frameFileTiming = false, true, false
	em.texturePivot = {0.5, 1}
	em.randomFlipX, em.randomFlipY = true, true
	pen.frameTag = "fall"
	ProcessNodeQueues(scene.manager, &game.gameContext)
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(saved, `"particle_regions": [[0, 0, 16, 16], [16, 0, 16, 8]]`), "regions: %s", saved)

	again := game->createScene("frames2", false)
	testing.expect(t, Scene_InstantiateFromJSON(again, transmute([]u8)saved, &game.gameContext), "loads")
	ProcessNodeQueues(again.manager, &game.gameContext)
	re := cast(^ParticleEmitterNode)Scene_FindNodeByName(again, "Leaves")
	testing.expect(t, re != nil, "found")
	if re == nil do return
	r := &re.emitter
	testing.expect_value(t, r.frameSource, ParticleFrameSource.Regions)
	testing.expect_value(t, r.regions.count, 2)
	testing.expect_value(t, r.regions.rects[1], rl.Rectangle{16, 0, 16, 8})
	testing.expect_value(t, r.frameFirst, 1)
	testing.expect_value(t, r.frameCount, 2)
	testing.expect(t, !r.frameLoop && r.frameRandomStart && !r.frameFileTiming, "frame flags")
	testing.expect_value(t, r.texturePivot, [2]f32{0.5, 1})
	testing.expect(t, r.randomFlipX && r.randomFlipY, "flips")
	testing.expect_value(t, re.frameTag, "fall")

	// A scene saved before #401 (no frame keys) keeps the old look.
	old := game->createScene("frames3", false)
	testing.expect(t, Scene_InstantiateFromJSON(old, transmute([]u8)string(`{"name": "old", "root": {"type": "Node", "name": "root", "children": [{"type": "ParticleEmitterNode", "name": "Old", "properties": {"emitter.sheetColumns": 2, "emitter.frameMode": "Speed"}}]}}`), &game.gameContext), "old loads")
	ProcessNodeQueues(old.manager, &game.gameContext)
	o := cast(^ParticleEmitterNode)Scene_FindNodeByName(old, "Old")
	testing.expect(t, o != nil, "old found")
	if o == nil do return
	testing.expect_value(t, o.emitter.frameSource, ParticleFrameSource.Grid)
	testing.expect(t, o.emitter.frameLoop, "Speed still loops")
	testing.expect_value(t, o.emitter.texturePivot, [2]f32{0.5, 0.5})
	testing.expect_value(t, o.emitter.regions.count, 0)
}
