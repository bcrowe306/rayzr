package engine

import "core:strings"
import b2 "vendor:box2d"
import rl "vendor:raylib"


ParticleEmitterNode :: struct {
	using node: Node,
	emitter: ParticleEmitter `gui:"true"`,
	onParticleHit: EventSubject, // "particle_hit"(node): a particle hit a body (collision on)
	onFinished: EventSubject,    // "finished": a one-shot / stopped emitter's last particle died (#128)
	// The particles' texture (shape Texture; #126): saved as
	// "particle_texture" (not "texture": old files' texture on any node
	// becomes a child sprite).
	texturePath: string,
	texture:     ^Texture,
	// An Aseprite texture (#401): its file (Frame Source Aseprite: the tag's
	// frames from its sheet) and the tag ("" = every frame).
	ase:         ^Ase_Resource,
	frameTag:    string `gui:"true"`,
	// Sub-emitter (#130): another Particle Emitter (a path from this node,
	// e.g. "Sparks" for a child) that emits subEmitterAmount particles where
	// each of this one's particles dies, hits a body, or both. Give it
	// Emitting off (only these bursts) and Local Space off (they stay where
	// they were born). CPU particles only: GPU ones don't report deaths.
	subEmitter:       string `gui:"true"`,
	subEmitterOn:     ParticleSubEmitterTrigger `gui:"true"`,
	subEmitterAmount: int `gui:"true" min:"1" max:"200"`,
	subEvents:        [dynamic][2]f32, // (runtime) this frame's deaths / hits, world points
}

ParticleSubEmitterTrigger :: enum {
	Death, // a particle's lifetime ended
	Hit,   // a particle hit a body (collision on)
	Both,
}

// The most sub-emitter bursts one emitter queues in a frame.
@(private = "file")
SUB_EVENTS_MAX :: 256

@(private = "file")
sub_event :: proc(pen: ^ParticleEmitterNode, at: [2]f32, hit: bool) {
	if pen.subEmitter == "" || len(pen.subEvents) >= SUB_EVENTS_MAX do return
	if pen.subEmitterOn != .Both && (pen.subEmitterOn == .Hit) != hit do return
	if pen.subEvents == nil do pen.subEvents = make([dynamic][2]f32, pen.allocator)
	append(&pen.subEvents, at)
}

// ParticleEmitterNode_SubEmitter: the emitter its sub-emitter path names
// (nil: none, not an emitter, or itself).
ParticleEmitterNode_SubEmitter :: proc(pen: ^ParticleEmitterNode) -> ^ParticleEmitterNode {
	if pen.subEmitter == "" do return nil
	n := Node_ResolvePath(nil, pen, pen.subEmitter)
	if n == nil || n == pen || n.typeId != ParticleEmitterNode || n.removing do return nil
	return cast(^ParticleEmitterNode)n
}

// ParticleEmitterNode_SetTexture uses a project texture for the particles
// ("" = none); the previous one is released.
ParticleEmitterNode_SetTexture :: proc(pen: ^ParticleEmitterNode, path: string) {
	rm := Node_ResourceManager(pen)
	if pen.texture != nil && rm != nil do ResourceManager_ReleaseTexture(rm, pen.texture)
	if pen.ase != nil do ResourceManager_ReleaseAseprite(pen.ase)
	pen.texture, pen.emitter.texture, pen.ase = nil, nil, nil
	pen.texturePath = strings.clone(path, pen.allocator)
	if path == "" || rm == nil || !rl.IsWindowReady() do return
	full := Project_ResolveAssetPath(pen.gameContext, path)
	if tex, ok := rm.loadTexture(rm, full); ok && tex != nil {
		pen.texture = tex
		pen.emitter.texture = &tex.texture
	}
	if Ase_IsPath(path) do pen.ase = ResourceManager_LoadAseprite(rm, full)
}

// ParticleEmitterNode_ResolveFrames works out the emitter's frames for this
// draw (#401): its texture's atlas region (exported games), slicing preset,
// or Aseprite tag - whose sheet the particles are then drawn from.
ParticleEmitterNode_ResolveFrames :: proc(pen: ^ParticleEmitterNode) {
	em := &pen.emitter
	fi: Particle_Frame_Input
	if pen.texture != nil {
		em.texture = &pen.texture.texture
		fi.texSize = {f32(pen.texture.texture.width), f32(pen.texture.texture.height)}
		fi.region = pen.texture.region
	}
	switch em.frameSource {
	case .Grid, .Regions:
	case .Slices:
		if pen.texture != nil do fi.slice = Asset_ImportGet(Node_ResourceManager(pen), pen.texture.filePath).slice
	case .Aseprite:
		if pen.ase != nil && pen.ase.doc != nil {
			fi.ase, fi.tag, fi.region = pen.ase.doc, pen.frameTag, {}
			fi.aseCols = Ase_SheetColumns(len(pen.ase.doc.frames))
			if sheet := Ase_ResourceSheet(pen.ase, "", ""); sheet != nil {
				em.texture = &sheet.texture
				fi.texSize = {f32(sheet.texture.width), f32(sheet.texture.height)}
			}
		}
	}
	ParticleEmitter_ResolveFrames(em, fi)
	em.frames.ownerSet = true
}

ParticleEmitterNode_Init :: proc(pen: ^ParticleEmitterNode) {
	InitializeNode(pen)
	pen.update = ParticleEmitterNode_Update
	pen.render = ParticleEmitterNode_Render
	pen.onDestroy = ParticleEmitterNode_Destroy
	pen.resource = &pen.emitter
	InitializeSubject(&pen.onParticleHit, "particle_hit", pen)
	InitializeSubject(&pen.onFinished, "finished", pen)
	pen.emitter.onFinished = proc(emitter: ^ParticleEmitter, user: rawptr) {
		pen := cast(^ParticleEmitterNode)user
		pen.onFinished->notify(pen, nil, pen.gameContext)
	}
	pen.emitter.onHitUser = pen
	pen.emitter.onHit = proc(emitter: ^ParticleEmitter, hit: ^Node, user: rawptr) {
		pen := cast(^ParticleEmitterNode)user
		sub_event(pen, emitter.lastHitPoint, true)
		pen.onParticleHit->notify(pen, hit, pen.gameContext)
	}
	pen.emitter.onDeath = proc(emitter: ^ParticleEmitter, at: [2]f32, user: rawptr) {
		sub_event(cast(^ParticleEmitterNode)user, at, false)
	}
	pen.subEmitterAmount = 8

	ParticleEmitter_Init(&pen.emitter)
	pen.emitter.allocator = pen.allocator
	pen.emitter.amount = 100
	pen.emitter.lifetime = 2
	pen.emitter.burst = 0.5
	pen.emitter.size = {5, 5}
	pen.emitter.position = pen.position
	pen.emitter.useColorRamp = true
	pen.emitter.emitting = true
	pen.emitter.continuous = true
}

ParticleEmitterNode_Create :: proc(scene: ^Scene, name: string = "Particle Emitter") -> ^ParticleEmitterNode {
	pen := CreateNode(scene.manager, ParticleEmitterNode)
	ParticleEmitterNode_Init(pen)
	if name != "" {
		pen.name = strings.clone(name, pen.allocator) // owned: callers pass temp strings too
	}
	scene->addNode(pen)
	return pen
}

ParticleEmitterNode_Start :: proc(pen: ^ParticleEmitterNode) {
	if pen.emitter.start != nil {
		pen.emitter->start()
	} else {
		ParticleEmitter_Start(&pen.emitter)
	}
}

ParticleEmitterNode_Stop :: proc(pen: ^ParticleEmitterNode) {
	if pen.emitter.stop != nil {
		pen.emitter->stop()
	} else {
		ParticleEmitter_Stop(&pen.emitter)
	}
}

ParticleEmitterNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	pen := cast(^ParticleEmitterNode)node
	if !pen.enabled do return

	// The node's global transform: emission follows it; local particles are
	// drawn through it (#124).
	pen.emitter.position = pen.globalPosition
	pen.emitter.originRotation = pen.globalRotation
	pen.emitter.originScale = pen.globalScale

	world := gameContext.game.physicsWorld.worldId if gameContext != nil && gameContext.game != nil else b2.WorldId{}
	ParticleEmitter_Update(&pen.emitter, deltaTime, world)

	// This frame's deaths and hits: the sub-emitter's bursts.
	if len(pen.subEvents) > 0 {
		if sub := ParticleEmitterNode_SubEmitter(pen); sub != nil {
			for at in pen.subEvents do ParticleEmitter_EmitAt(&sub.emitter, at, pen.subEmitterAmount)
		}
		clear(&pen.subEvents)
	}
}

// ParticleEmitterNode_EmitBurst: n particles now, from where the node is (#128).
ParticleEmitterNode_EmitBurst :: proc(pen: ^ParticleEmitterNode, n: int) {
	pen.emitter.position, pen.emitter.originRotation, pen.emitter.originScale = pen.globalPosition, pen.globalRotation, pen.globalScale
	ParticleEmitter_EmitBurst(&pen.emitter, n)
	pen.emitter.aliveCount = 0
	for p in pen.emitter.particles do if p.alive do pen.emitter.aliveCount += 1
}

ParticleEmitterNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	pen := cast(^ParticleEmitterNode)node
	DestroySubject(&pen.onParticleHit)
	DestroySubject(&pen.onFinished)
	ParticleGPU_Release(&pen.emitter)
	if pen.texture != nil {
		if rm := Node_ResourceManager(pen); rm != nil do ResourceManager_ReleaseTexture(rm, pen.texture)
		pen.texture, pen.emitter.texture = nil, nil
	}
	if pen.ase != nil do ResourceManager_ReleaseAseprite(pen.ase)
	pen.ase = nil
}

ParticleEmitterNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	pen := cast(^ParticleEmitterNode)node
	if !pen.renderable do return

	pen.emitter.position, pen.emitter.originRotation, pen.emitter.originScale = pen.globalPosition, pen.globalRotation, pen.globalScale
	ParticleEmitterNode_ResolveFrames(pen)
	ParticleEmitter_Render(&pen.emitter, deltaTime)
}
