package engine

import "base:runtime"
import "core:mem"

import "core:math/rand"
import "core:crypto"
import "core:math"
import "core:fmt"
import "core:encoding/json"
import "core:slice"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import ui "../ui"
import b2 "vendor:box2d"

MAX_COLOR_STOPS :: 8

ColorStop :: struct {
	position: f32, // 0.0 to 1.0 along particle lifetime
	color: rl.Color,
}

ColorRamp :: struct {
	stops: [MAX_COLOR_STOPS]ColorStop,
	count: int,
}

ColorRamp_Init :: proc(ramp: ^ColorRamp) {
	ramp.count = 3
	ramp.stops[0] = {position = 0.0, color = rl.Color{255, 230, 100, 255}} // Warm Yellow-White at spawn
	ramp.stops[1] = {position = 0.5, color = rl.Color{230, 50, 40, 255}}   // Fiery Red at mid-life
	ramp.stops[2] = {position = 1.0, color = rl.Color{40, 40, 40, 0}}      // Fade to transparent at death
}

ColorRamp_Evaluate :: proc(ramp: ^ColorRamp, t: f32) -> rl.Color {
	if ramp.count == 0 do return rl.WHITE
	if ramp.count == 1 do return ramp.stops[0].color

	clampedT := math.clamp(t, 0.0, 1.0)
	if clampedT <= ramp.stops[0].position do return ramp.stops[0].color
	if clampedT >= ramp.stops[ramp.count - 1].position do return ramp.stops[ramp.count - 1].color

	for i in 0..<(ramp.count - 1) {
		p0 := ramp.stops[i].position
		p1 := ramp.stops[i + 1].position
		if clampedT >= p0 && clampedT <= p1 {
			diff := p1 - p0
			localT := (clampedT - p0) / diff if diff > 0.0001 else 0.0
			r := u8(math.clamp(math.lerp(f32(ramp.stops[i].color.r), f32(ramp.stops[i + 1].color.r), localT), 0, 255))
			g := u8(math.clamp(math.lerp(f32(ramp.stops[i].color.g), f32(ramp.stops[i + 1].color.g), localT), 0, 255))
			b := u8(math.clamp(math.lerp(f32(ramp.stops[i].color.b), f32(ramp.stops[i + 1].color.b), localT), 0, 255))
			a := u8(math.clamp(math.lerp(f32(ramp.stops[i].color.a), f32(ramp.stops[i + 1].color.a), localT), 0, 255))
			return rl.Color{r, g, b, a}
		}
	}
	return ramp.stops[ramp.count - 1].color
}

ColorRamp_Sort :: proc(ramp: ^ColorRamp, trackingIdx: ^int = nil) {
	targetStop := ColorStop{}
	if trackingIdx != nil && trackingIdx^ >= 0 && trackingIdx^ < ramp.count {
		targetStop = ramp.stops[trackingIdx^]
	}
	for i in 1..<ramp.count {
		key := ramp.stops[i]
		j := i - 1
		for j >= 0 && ramp.stops[j].position > key.position {
			ramp.stops[j + 1] = ramp.stops[j]
			j -= 1
		}
		ramp.stops[j + 1] = key
	}
	if trackingIdx != nil {
		for i in 0..<ramp.count {
			if ramp.stops[i].position == targetStop.position && ramp.stops[i].color == targetStop.color {
				trackingIdx^ = i
				break
			}
		}
	}
}

ColorRamp_AddStop :: proc(ramp: ^ColorRamp, pos: f32, color: rl.Color) -> int {
	if ramp.count >= MAX_COLOR_STOPS do return -1
	idx := ramp.count
	ramp.stops[idx] = {position = math.clamp(pos, 0.0, 1.0), color = color}
	ramp.count += 1
	selected := idx
	ColorRamp_Sort(ramp, &selected)
	return selected
}

ColorRamp_RemoveStop :: proc(ramp: ^ColorRamp, index: int) -> bool {
	if ramp.count <= 2 || index < 0 || index >= ramp.count do return false
	for i in index..<(ramp.count - 1) {
		ramp.stops[i] = ramp.stops[i + 1]
	}
	ramp.count -= 1
	return true
}

ParticleShape :: enum {
	Circle,
	Ellipse,
	Rectangle,
	Pixel,
	Line,
	Texture,
	Custom,
}

// How particles are blended over what's behind them (#126).
ParticleBlend :: enum {
	Alpha,         // ordinary transparency
	Additive,      // light adds up: fire, glow, sparks, magic
	Multiply,      // darkens: shadows, soot
	Premultiplied, // textures with premultiplied alpha
}

// Which frame of a sprite sheet a particle shows (#126).
ParticleFrameMode :: enum {
	OverLifetime, // the frames once, from birth to death
	Speed,        // frameSpeed frames per second (or the file's timing), looping or once
	Random,       // one frame per particle, picked at birth
}

// Where a textured particle's frames come from (#401).
ParticleFrameSource :: enum {
	Grid,     // the texture cut into sheetColumns x sheetRows
	Slices,   // the texture's slicing preset (its import settings: Sprite Slicer's Save Preset)
	Regions,  // rectangles of the texture (an atlas's sprites; the Sprite Slicer's picked cells)
	Aseprite, // an Aseprite texture's tag (frameTag; "" = every frame): its direction and timing
}

// The most frames a frame list holds (Regions, Aseprite; GPU uniforms, #401).
MAX_PARTICLE_FRAMES :: 64

// Regions of the texture (Frame Source: Regions), in its pixels; saved as
// "particle_regions" (scene_serialization.odin).
Particle_Regions :: struct {
	rects: [MAX_PARTICLE_FRAMES]rl.Rectangle,
	count: int,
}

// Particle_Frames: the frames as drawn (#401), worked out from the frame
// source before each draw (ParticleEmitter_ResolveFrames): a grid of cells
// (`first` + i, `cols` across from `origin` every `step`, `cell` big) or a
// list of rectangles - in the GPU texture's pixels (an atlased texture's
// region offset in) - and, timed, each frame's end (seconds, cumulative).
Particle_Frames :: struct {
	count:   int, // 0 / 1: the whole texture
	list:    bool,
	origin:  [2]f32,
	step:    [2]f32,
	cell:    [2]f32,
	cols:    int,
	first:   int,
	rects:   [MAX_PARTICLE_FRAMES]rl.Rectangle,
	timed:   bool,
	ends:    [MAX_PARTICLE_FRAMES]f32,
	texSize: [2]f32, // the GPU texture's size (uv = px / texSize)
	ownerSet: bool,  // (runtime) the owner resolved them for this draw (slices, regions, Aseprite)
}

// What ParticleEmitter_ResolveFrames reads besides the emitter (the node:
// its texture's atlas region, slicing preset and Aseprite file).
Particle_Frame_Input :: struct {
	texSize: [2]f32,        // the GPU texture
	region:  rl.Rectangle,  // an atlased texture's rectangle in it (0 = all of it)
	slice:   Asset_Slice,   // Slices
	ase:     ^Ase_Document, // Aseprite
	aseCols: int,           //   its sheet's frames per row
	tag:     string,        //   "" = every frame
}

// Where particles are born (#127). Rectangle is the spread box (half sizes
// `spread`); Line runs along the emitter's x (half length spread.x).
ParticleEmissionShape :: enum {
	Rectangle,
	Point,
	Circle,        // a filled disc (emissionRadius)
	Ring,          // between emissionInnerRadius and emissionRadius
	Line,
	RectangleEdge, // the spread box's outline
}

// A value over a particle's life (#127): points (t 0..1, value), linear in
// between; none = off.
MAX_CURVE_POINTS :: 8

// Trails (#130): a particle's recent path, a point each trailSegment
// pixels it moves, drawn as a ribbon behind it that thins and fades.
MAX_TRAIL_POINTS :: 32

Particle_Trail :: struct {
	points: [MAX_TRAIL_POINTS][2]f32, // a ring, in the particles' space
	count:  u8,
	head:   u8, // the newest point
}

ParticleCurve :: struct {
	points: [MAX_CURVE_POINTS][2]f32,
	count:  int,
}

// ParticleCurve_Sample: the value at t (0..1); `none` when the curve is off.
ParticleCurve_Sample :: proc(c: ^ParticleCurve, t: f32, none: f32 = 1) -> f32 {
	if c.count == 0 do return none
	if t <= c.points[0].x do return c.points[0].y
	for i in 1 ..< c.count {
		a, b := c.points[i - 1], c.points[i]
		if t <= b.x {
			span := b.x - a.x
			return a.y + (b.y - a.y) * ((t - a.x) / span if span > 0 else 0)
		}
	}
	return c.points[c.count - 1].y
}

// ParticleCurve_FromJSON reads [[t, v], ...] (sorted by t, at most
// MAX_CURVE_POINTS; the scene key and the curve editor's text).
ParticleCurve_FromJSON :: proc(c: ^ParticleCurve, arr: json.Array) {
	c.count = 0
	for v in arr {
		pt, ok := v.(json.Array)
		if !ok || len(pt) < 2 || c.count >= MAX_CURVE_POINTS do continue
		num :: proc(v: json.Value) -> f32 {
			#partial switch x in v {
			case json.Integer: return f32(x)
			case json.Float:   return f32(x)
			}
			return 0
		}
		c.points[c.count] = {num(pt[0]), num(pt[1])}
		c.count += 1
	}
	slice.sort_by(c.points[:c.count], proc(a, b: [2]f32) -> bool {return a.x < b.x})
}

// ParticleRegions_FromJSON reads [[x, y, w, h], ...] (at most
// MAX_PARTICLE_FRAMES; empty rectangles skipped).
ParticleRegions_FromJSON :: proc(rg: ^Particle_Regions, arr: json.Array) {
	rg.count = 0
	for v in arr {
		r, ok := v.(json.Array)
		if !ok || len(r) < 4 || rg.count >= MAX_PARTICLE_FRAMES do continue
		num :: proc(v: json.Value) -> f32 {
			#partial switch x in v {
			case json.Integer: return f32(x)
			case json.Float:   return f32(x)
			}
			return 0
		}
		rect := rl.Rectangle{num(r[0]), num(r[1]), num(r[2]), num(r[3])}
		if rect.width <= 0 || rect.height <= 0 do continue
		rg.rects[rg.count] = rect
		rg.count += 1
	}
}

// What a particle does when it hits the physics world (#123).
ParticleCollisionMode :: enum {
	Bounce, // reflected (elasticity), slowed along the surface (friction)
	Stop,   // rests where it hit
	Kill,   // dies
}

ParticleEmitter :: struct {
	amount: int `gui:"true" min:"1" max:"5000"`,
	lifetime: f32 `gui:"true" min:".01" max:"5"`,
	lifetimeVariance: f32 `gui:"true" min:"0" max:"1"`, // each particle's lifetime within lifetime x (1 +- this)
	position: [2]f32 `gui:"true" min:"0" max:"1280" save:"false"`,
	burst: f32 `gui:"true" min:"0" max:"1"`,
	size: [2]f32 `gui:"true" min:".01" max:"100"`,
	sizeVariance: f32 `gui:"true" min:"0" max:"1"`, // 0-1
	sizeSpread: f32 `gui:"true" min:"0" max:"50"`,
	scaleStart: [2]f32 `gui:"true" min:"0" max:"1"`,
	scaleEnd: [2]f32 `gui:"true" min:"0" max:"1"`,
	rotation: f32 `gui:"true" min:"0" max:"359"`,
	rotationVariance: f32 `gui:"true" min:"0" max:"1"`, // 0-1
	rotationSpread: f32 `gui:"true" min:"0" max:"359"`,
	torque: f32 `gui:"true" min:"-2000" max:"2000"`,
	torqueVariance: f32 `gui:"true" min:"0" max:"1"`, // 0-1
	torqueSpread: f32 `gui:"true" min:"0" max:"2000"`,
	torqueAcceleration: f32 `gui:"true" min:"-2000" max:"2000"`,
	useColorRamp: bool `gui:"true"`,    // colour over lifetime from colorRamp (else particleColor -> colorEnd)
	colorRamp: ColorRamp,              // saved as "color_ramp" (scene_serialization.odin)
	particleColor: rl.Color `gui:"true"`,
	colorEnd: rl.Color `gui:"true"`,
	colorVariance: f32 `gui:"true" min:"0" max:"1"`,
	spread: [2]f32 `gui:"true" min:"0" max:"1280"`,
	velocity: f32 `gui:"true" min:"0" max:"2000"`,
	velocityVariance: f32 `gui:"true" min:"0" max:"1"`, // 0-1
	velocitySpread: f32 `gui:"true" min:"0" max:"2000"`,
	velocityScale: f32 `gui:"true" min:"0" max:"10"`,
	acceleration: f32 `gui:"true" min:"-2000" max:"2000"`,
	angle: f32 `gui:"true" min:"0" max:"359"`,
	angleVariance: f32 `gui:"true" min:"0" max:"1"`, // 0-1
	angleSpread: f32 `gui:"true" min:"0" max:"360"`,
	gravityDirection: [2]f32 `gui:"true" min:"-1" max:"1"`,
	gravityVelocity: f32 `gui:"true" min:"-2000" max:"2000"`,
	wind: [2]f32 `gui:"true" min:"-1000" max:"1000"`,
	// Collision with the physics world (static / kinematic / dynamic bodies,
	// tile maps, LDtk solids; not trigger areas), on the layers in
	// collisionLayers (#123).
	collisionEnabled: bool `gui:"true"`,
	collisionMode: ParticleCollisionMode `gui:"true"`,
	collisionLayers: CollisionLayerSet `gui:"true"`,
	elasticity: f32 `gui:"true" min:"0" max:"1"`,
	friction: f32 `gui:"true" min:"0" max:"1"`,
	// The last hit (world point, surface normal, the node hit) and who is
	// told about each hit (the node: its particle_hit event).
	lastHitPoint, lastHitNormal: [2]f32,
	lastHitNode: ^Node,
	onHit: proc(emitter: ^ParticleEmitter, hit: ^Node, user: rawptr),
	onHitUser: rawptr,
	shape: ParticleShape `gui:"true" min:"0" max:"2000"`,
	emitting: bool `gui:"true"`,
	continuous: bool `gui:"true"`,
	// Particles live in the emitter's space and move, turn and scale with
	// it (an exhaust, an aura), or stay in the world where they were
	// emitted (smoke left behind). Local by default, also for scenes saved
	// before the option (#124).
	localSpace: bool `gui:"true"`,
	// Look (#126): the blend mode; the texture (shape Texture) as a sprite
	// sheet of columns x rows frames; particles turned to face where they
	// move (rain, sparks, arrows; rotation adds to it).
	blendMode: ParticleBlend `gui:"true"`,
	sheetColumns: int `gui:"true" min:"1" max:"64"`,
	sheetRows: int `gui:"true" min:"1" max:"64"`,
	frameMode: ParticleFrameMode `gui:"true"`,
	frameSpeed: f32 `gui:"true" min:"0" max:"60"`,
	alignToVelocity: bool `gui:"true"`,
	// Frames (#401): where they come from, which of them (Grid / Slices:
	// frameCount from frameFirst, 0 = to the end), looping or once (Speed),
	// a random start frame per particle, the Aseprite file's frame
	// durations; the image's pivot (0..1: the point on the particle's
	// position it turns around) and random flips per particle.
	frameSource: ParticleFrameSource `gui:"true"`,
	frameFirst: int `gui:"true" min:"0" max:"4096"`,
	frameCount: int `gui:"true" min:"0" max:"4096"`,
	frameLoop: bool `gui:"true"`,
	frameRandomStart: bool `gui:"true"`,
	frameFileTiming: bool `gui:"true"`,
	texturePivot: [2]f32 `gui:"true" min:"0" max:"1"`,
	randomFlipX: bool `gui:"true"`,
	randomFlipY: bool `gui:"true"`,
	regions: Particle_Regions,
	frames: Particle_Frames, // (runtime)
	// Trails (#130; CPU particles): trailLength points (0 = off), one each
	// trailSegment pixels; trailWidth is the ribbon's width at the particle
	// (1 = the particle's size). `trails` parallels `particles` (only
	// allocated when on).
	trailLength:  int `gui:"true" min:"0" max:"32"`,
	trailSegment: f32 `gui:"true" min:"1" max:"64"`,
	trailWidth:   f32 `gui:"true" min:"0" max:"4"`,
	trails:       [dynamic]Particle_Trail,
	// Emission and motion (#127).
	emissionShape: ParticleEmissionShape `gui:"true"`,
	emissionRadius: f32 `gui:"true" min:"0" max:"1000"`,
	emissionInnerRadius: f32 `gui:"true" min:"0" max:"1000"`,
	emitAlongNormal: bool `gui:"true"`, // out of the shape (circle / ring: away from the centre; edges: outward)
	radialVelocity: f32 `gui:"true" min:"-1000" max:"1000"`, // px/s away from the emitter (negative: towards)
	orbitVelocity: f32 `gui:"true" min:"-720" max:"720"`,    // degrees/s around the emitter
	damping: f32 `gui:"true" min:"0" max:"20"`,              // velocity lost per second (drag)
	// Over lifetime (#127; none: off): size (replaces Scale Start -> End),
	// alpha (multiplies the colour's) and speed (multiplies the movement).
	sizeCurve, alphaCurve, speedCurve: ParticleCurve,
	// Control (#128): start as if it had run a lifetime already (smoke
	// already there); the same pattern every start (seed 0: random); what
	// the view culling tests - Auto: the live particles' bounds, else
	// visibilityRect around the emitter (in its space).
	// GPU mode (#129): particles animated by the shader from their spawn
	// records - 100k+ at almost no CPU cost; no collision, custom shapes or
	// speed curve.
	gpu: bool `gui:"true"`,
	gpuData: ^Particle_GPU, // (runtime: records, clock, GL buffers)
	gpuApplied: bool,       // (runtime: the mode the particles are in)
	// (runtime) gravity and wind in the particles' space, worked out once per
	// step rather than per particle.
	stepGravity, stepWind: [2]f32,
	stepForces: bool,
	// (runtime) the live particles' extent from the last step, in their
	// space: Auto visibility without another pass.
	extentMin, extentMax: [2]f32,
	extentSize: f32,
	extentAny: bool,
	prewarm: bool `gui:"true"`,
	seed: int `gui:"true" min:"0" max:"100000"`,
	autoVisibility: bool `gui:"true"`,
	visibilityRect: rl.Rectangle `gui:"true"`,
	// (runtime) how many live, prewarm done, the seeded generator, a
	// one-shot's finished event.
	aliveCount:  int,
	prewarmed:   bool,
	rngState:    rand.Default_Random_State,
	onFinished:  proc(emitter: ^ParticleEmitter, user: rawptr),
	// A particle's lifetime ended, where it was (world; sub-emitters, #130).
	onDeath:     proc(emitter: ^ParticleEmitter, at: [2]f32, user: rawptr),
	// The owner's global rotation (degrees) and scale, set each update:
	// emission follows them; local particles are drawn through them.
	originRotation: f32,
	originScale: [2]f32,
	start: proc(emitter: ^ParticleEmitter),
	stop: proc(emitter: ^ParticleEmitter),
	lifetimer: f32,
	// Ring buffer of particles, grown on demand to about twice `amount`
	// (allocated from `allocator`: the owning node's arena).
	particles: [dynamic]Particle,
	allocator: mem.Allocator,
	timer: f32,
	head: int,
	count: int,
	emittedInCycle: int,
	cycleStarted: bool,
	texture: ^rl.Texture2D,
	customShapeProc: proc(p: ^Particle, deltaTime: f32),
}

PARTICLE_MAX :: 20000

// ParticleEmitter_Reserve grows the particle ring to `n` slots (keeps the
// live particles).
ParticleEmitter_Reserve :: proc(emitter: ^ParticleEmitter, n: int) {
	if len(emitter.particles) >= n do return
	if emitter.particles == nil {
		alloc := emitter.allocator if emitter.allocator.procedure != nil else context.allocator
		emitter.particles = make([dynamic]Particle, n, n, alloc)
		return
	}
	resize(&emitter.particles, n)
}

// ParticleEmitter_Destroy frees the particles (only needed when the
// emitter isn't owned by a node, whose arena frees them).
ParticleEmitter_Destroy :: proc(emitter: ^ParticleEmitter) {
	if emitter.particles != nil && emitter.allocator.procedure == nil do delete(emitter.particles)
	if emitter.trails != nil && emitter.allocator.procedure == nil do delete(emitter.trails)
	emitter.particles, emitter.trails = nil, nil
	if g := emitter.gpuData; g != nil {
		ParticleGPU_Release(emitter)
		if emitter.allocator.procedure == nil {
			delete(g.records)
			free(g)
		}
		emitter.gpuData = nil
	}
}

ParticleEmitter_Start :: proc(emitter: ^ParticleEmitter) {
	if emitter.seed != 0 do emitter.rngState = rand.create(u64(emitter.seed)) // (the same pattern every start)
	emitter.prewarmed = false
	emitter.emitting = true
	emitter.cycleStarted = false
	emitter.lifetimer = 0
	emitter.timer = 0
	emitter.emittedInCycle = 0
}

ParticleEmitter_Stop :: proc(emitter: ^ParticleEmitter) {
	emitter.emitting = false
	emitter.cycleStarted = false
}

ParticleEmitter_Init :: proc(emitter: ^ParticleEmitter) {
	emitter.amount = 1
	emitter.lifetime = 2
	emitter.burst = 0
	emitter.size = {5, 5}
	emitter.useColorRamp = true
	ColorRamp_Init(&emitter.colorRamp)
	emitter.particleColor = rl.WHITE
	emitter.colorEnd = rl.WHITE
	emitter.colorVariance = 0
	emitter.velocity = 100
	emitter.scaleStart = 1
	emitter.scaleEnd = 1
	emitter.velocityScale = 1
	emitter.gravityDirection = {0, 1}
	emitter.gravityVelocity = 200
	emitter.wind = {0, 0}
	emitter.collisionEnabled = false
	emitter.collisionMode = .Bounce
	emitter.collisionLayers = DEFAULT_COLLISION_MASK
	emitter.elasticity = 0.7
	emitter.friction = 0.1
	emitter.emitting = true
	emitter.continuous = true
	emitter.localSpace = true
	emitter.originScale = {1, 1}
	emitter.sheetColumns = 1
	emitter.sheetRows = 1
	emitter.frameSpeed = 12
	emitter.frameLoop = true
	emitter.frameFileTiming = true
	emitter.texturePivot = {0.5, 0.5}
	emitter.emissionRadius = 32
	emitter.trailSegment = 6
	emitter.trailWidth = 1
	emitter.autoVisibility = true
	emitter.visibilityRect = {-128, -128, 256, 256}
	emitter.start = ParticleEmitter_Start
	emitter.stop = ParticleEmitter_Stop
	emitter.lifetimer = 0
	emitter.timer = 0
	emitter.head = 0
	emitter.count = 0
	emitter.emittedInCycle = 0
	emitter.cycleStarted = false
}


Particle :: struct {
	position: [2]f32,
	scaleStart: [2]f32,
	scaleEnd: [2]f32,
	scale: [2]f32,
	rotation: f32,
	torque: f32,
	torqueAcceleration: f32,
	velocity: [2]f32,
	acceleration: [2]f32,
	lifetime: f32,
	age: f32,
	agePercent: f32,
	size: [2]f32,
	colorStart: rl.Color,
	colorEnd: rl.Color,
	colorJitter: [3]f32,
	color: rl.Color,
	alive: bool,
	frameSeed: u32, // a random number per particle (its sheet frame: Random)
	shape: ParticleShape,
	texture: ^rl.Texture2D,
	customShapeProc: proc(p: ^Particle, deltaTime: f32),
}

// Particles use a fast generator seeded once from the OS (they need
// variety, not unpredictability; the OS generator cost per number).
@(private = "file")
particleRandom: struct {
	state:  rand.Default_Random_State,
	seeded: bool,
}

@(private = "file")
particle_rng :: proc() -> runtime.Random_Generator {
	if !particleRandom.seeded {
		seed: [8]u8
		crypto.rand_bytes(seed[:])
		particleRandom.state = rand.create((^u64)(&seed[0])^)
		particleRandom.seeded = true
	}
	return runtime.default_random_generator(&particleRandom.state)
}

@(private = "file")
safe_float32_range :: proc(a, b: f32) -> f32 {
	low := min(a, b)
	high := max(a, b)
	if low >= high do return low
	return rand.float32_range(low, high)
}

ParticleEmitter_Emit :: proc(emitter: ^ParticleEmitter) {
	// (Picked first, set at this scope: a context change inside a block is
	// undone when the block ends.)
	gen := particle_rng()
	if emitter.seed != 0 {
		if emitter.rngState == {} do emitter.rngState = rand.create(u64(emitter.seed))
		gen = runtime.default_random_generator(&emitter.rngState)
	}
	context.random_generator = gen

	// GPU mode (#129): the particle is made here as on the CPU, then kept as
	// a spawn record the shader animates.
	scratch: Particle
	p := &scratch
	if !emitter.gpu {
		ParticleEmitter_Reserve(emitter, clamp(emitter.amount * 2 + 4, 16, PARTICLE_MAX))
		if len(emitter.particles) == 0 do return
		emitter.head %= len(emitter.particles)
		p = &emitter.particles[emitter.head]
		if emitter.head < len(emitter.trails) do emitter.trails[emitter.head].count = 0
		emitter.head = (emitter.head + 1) % len(emitter.particles)
	}

	// Position: an offset in the emitter's space (the spread box). Local
	// particles keep it; world ones go through the owner's transform.
	offset, normal := particle_emission_point(emitter)
	p.position = offset if emitter.localSpace else particle_to_world(emitter, offset)
	p.shape = emitter.shape

	// Size
	sizeSpread := math.abs(emitter.sizeSpread * emitter.sizeVariance)
	p.size = {
		emitter.size[0] + safe_float32_range(-sizeSpread, sizeSpread),
		emitter.size[1] + safe_float32_range(-sizeSpread, sizeSpread),
	}

	// Scale (as it starts: drawn right away, before its first update)
	p.scaleStart = emitter.scaleStart
	p.scaleEnd = emitter.scaleEnd
	p.scale = p.scaleStart
	if emitter.sizeCurve.count > 0 {
		c := ParticleCurve_Sample(&emitter.sizeCurve, 0)
		p.scale = {c, c}
	}

	// Rotation
	rotationSpread := math.abs(emitter.rotationSpread * emitter.rotationVariance)
	p.rotation = emitter.rotation + safe_float32_range(-rotationSpread, rotationSpread)

	// Angle (world particles: turned with the owner)
	baseSpread := math.abs(emitter.angleSpread * emitter.angleVariance)
	baseAngle := emitter.angle
	if emitter.emitAlongNormal && normal != {} do baseAngle = math.to_degrees(math.atan2(normal.y, normal.x))
	angle := baseAngle + safe_float32_range(-baseSpread, baseSpread)
	if !emitter.localSpace {
		angle += emitter.originRotation
		p.rotation += emitter.originRotation
	}
	angle_rad := math.to_radians(angle)

	// Torque
	torqueSpread := math.abs(emitter.torqueSpread * emitter.torqueVariance)
	p.torque = emitter.torque + safe_float32_range(-torqueSpread, torqueSpread)
	p.torqueAcceleration = emitter.torqueAcceleration

	// Velocity
	velSpread := math.abs(emitter.velocitySpread * emitter.velocityVariance)
	velocity := emitter.velocity + safe_float32_range(-velSpread, velSpread)
	p.velocity = {math.cos(angle_rad) * velocity, math.sin(angle_rad) * velocity}

	// Texture (drawn with the emitter's: a particle doesn't keep a pointer
	// that a texture change would leave dangling)
	p.frameSeed = rand.uint32()

	p.acceleration = {math.cos(angle_rad) * emitter.acceleration, math.sin(angle_rad) * emitter.acceleration}
	if !emitter.localSpace {
		// (Sizes and speeds scaled with the owner; local ones when drawn.)
		sc := particle_scale(emitter)
		p.size *= {abs(sc.x), abs(sc.y)}
		uniform := (abs(sc.x) + abs(sc.y)) * 0.5
		p.velocity *= uniform
		p.acceleration *= uniform
	}
	lv := math.clamp(emitter.lifetimeVariance, 0, 1)
	p.lifetime = max(emitter.lifetime * (1 + safe_float32_range(-lv, lv)), 0.01)
	p.age = 0
	p.agePercent = 0

	// Color Jitter
	cVar := math.abs(emitter.colorVariance)
	if cVar > 0 {
		p.colorJitter = {
			safe_float32_range(-cVar, cVar) * 255,
			safe_float32_range(-cVar, cVar) * 255,
			safe_float32_range(-cVar, cVar) * 255,
		}
	} else {
		p.colorJitter = {0, 0, 0}
	}

	// Colors
	if emitter.useColorRamp {
		baseColor := ColorRamp_Evaluate(&emitter.colorRamp, 0.0)
		r := u8(math.clamp(f32(baseColor.r) + p.colorJitter.x, 0, 255))
		g := u8(math.clamp(f32(baseColor.g) + p.colorJitter.y, 0, 255))
		b := u8(math.clamp(f32(baseColor.b) + p.colorJitter.z, 0, 255))
		p.color = {r, g, b, baseColor.a}
	} else {
		startColor := emitter.particleColor
		endColor := emitter.colorEnd
		if emitter.colorVariance > 0 {
			startColor.r = u8(math.clamp(f32(startColor.r) + p.colorJitter.x, 0, 255))
			startColor.g = u8(math.clamp(f32(startColor.g) + p.colorJitter.y, 0, 255))
			startColor.b = u8(math.clamp(f32(startColor.b) + p.colorJitter.z, 0, 255))
			endColor.r = u8(math.clamp(f32(endColor.r) + p.colorJitter.x, 0, 255))
			endColor.g = u8(math.clamp(f32(endColor.g) + p.colorJitter.y, 0, 255))
			endColor.b = u8(math.clamp(f32(endColor.b) + p.colorJitter.z, 0, 255))
		}
		p.colorStart = startColor
		p.colorEnd = endColor
		p.color = startColor
	}

	p.alive = true
	if emitter.gpu do ParticleGPU_Push(emitter, scratch)
}

// --- the owner's transform (#124) ----------------------------------------------------

particle_scale :: proc(emitter: ^ParticleEmitter) -> [2]f32 {
	return emitter.originScale if emitter.originScale != {} else {1, 1}
}

particle_rotate :: proc(v: [2]f32, deg: f32) -> [2]f32 {
	if deg == 0 do return v
	r := math.to_radians(deg)
	c, s := math.cos(r), math.sin(r)
	return {v.x * c - v.y * s, v.x * s + v.y * c}
}

// particle_to_world: a point in the emitter's space -> the world.
particle_to_world :: proc(emitter: ^ParticleEmitter, local: [2]f32) -> [2]f32 {
	return emitter.position + particle_rotate(local * particle_scale(emitter), emitter.originRotation)
}

// particle_to_local: a world point -> the emitter's space.
particle_to_local :: proc(emitter: ^ParticleEmitter, world: [2]f32) -> [2]f32 {
	sc := particle_scale(emitter)
	v := particle_rotate(world - emitter.position, -emitter.originRotation)
	return {v.x / (sc.x if sc.x != 0 else 1), v.y / (sc.y if sc.y != 0 else 1)}
}

@(private = "file")
particle_dir_to_world :: proc(emitter: ^ParticleEmitter, v: [2]f32) -> [2]f32 {
	return particle_rotate(v * particle_scale(emitter), emitter.originRotation)
}

@(private = "file")
particle_dir_to_local :: proc(emitter: ^ParticleEmitter, v: [2]f32) -> [2]f32 {
	sc := particle_scale(emitter)
	w := particle_rotate(v, -emitter.originRotation)
	return {w.x / (sc.x if sc.x != 0 else 1), w.y / (sc.y if sc.y != 0 else 1)}
}

// particle_forces: gravity and wind (world directions) in the particles'
// space - for local particles, turned back and unscaled, so "down" stays
// down on screen whatever the owner's rotation.
particle_forces :: proc(emitter: ^ParticleEmitter) -> (gravity, wind: [2]f32) {
	grav_len_sq := emitter.gravityDirection.x * emitter.gravityDirection.x + emitter.gravityDirection.y * emitter.gravityDirection.y
	if grav_len_sq > 0.0001 do gravity = emitter.gravityDirection / math.sqrt(grav_len_sq) * emitter.gravityVelocity
	wind = emitter.wind
	if emitter.localSpace {
		gravity = particle_dir_to_local(emitter, gravity)
		wind = particle_dir_to_local(emitter, wind)
	}
	return
}

Particle_Update_Index :: proc(emitter: ^ParticleEmitter, index: int, deltaTime: f32) {
	Particle_Update_Particle(emitter, &emitter.particles[index], deltaTime)
}

// Particle_Update_Particle moves a particle and ages it: forces (gravity,
// wind, its acceleration), damping, radial / orbit motion around the
// emitter, speed / size / alpha over life, colour.
Particle_Update_Particle :: proc(emitter: ^ParticleEmitter, particle: ^Particle, deltaTime: f32) {
	if !particle.alive do return
	p := particle
	gravity, wind := emitter.stepGravity, emitter.stepWind
	if !emitter.stepForces do gravity, wind = particle_forces(emitter)
	p.velocity += gravity * deltaTime
	p.velocity += wind * deltaTime
	p.velocity += p.acceleration * deltaTime
	if emitter.damping > 0 do p.velocity *= math.exp(-emitter.damping * deltaTime)
	p.torque += p.torqueAcceleration * deltaTime
	p.rotation += p.torque * deltaTime
	t := math.clamp(p.age / p.lifetime, 0, 1) if p.lifetime > 0 else 1
	speed := ParticleCurve_Sample(&emitter.speedCurve, t)
	p.position += p.velocity * deltaTime * emitter.velocityScale * speed
	// Around the emitter (its origin in its own space; local particles: 0, 0).
	if emitter.radialVelocity != 0 || emitter.orbitVelocity != 0 {
		center := [2]f32{} if emitter.localSpace else emitter.position
		d := p.position - center
		if emitter.orbitVelocity != 0 do d = particle_rotate(d, emitter.orbitVelocity * deltaTime * speed)
		if emitter.radialVelocity != 0 {
			l := math.sqrt(d.x * d.x + d.y * d.y)
			if l > 0.0001 do d += d / l * emitter.radialVelocity * deltaTime * speed
		}
		p.position = center + d
	}
	p.age += deltaTime
	p.agePercent = math.clamp(p.age / p.lifetime, 0, 1)

	if emitter.sizeCurve.count > 0 {
		c := ParticleCurve_Sample(&emitter.sizeCurve, p.agePercent)
		p.scale = {c, c}
	} else {
		p.scale = {math.lerp(p.scaleStart[0], p.scaleEnd[0], p.agePercent), math.lerp(p.scaleStart[1], p.scaleEnd[1], p.agePercent)}
	}

	// Color update over lifespan
	if emitter.useColorRamp {
		baseColor := ColorRamp_Evaluate(&emitter.colorRamp, p.agePercent)
		r := u8(math.clamp(f32(baseColor.r) + p.colorJitter.x, 0, 255))
		g := u8(math.clamp(f32(baseColor.g) + p.colorJitter.y, 0, 255))
		b := u8(math.clamp(f32(baseColor.b) + p.colorJitter.z, 0, 255))
		p.color = {r, g, b, baseColor.a}
	} else {
		k := p.agePercent
		r := u8(math.clamp(math.lerp(f32(p.colorStart.r), f32(p.colorEnd.r), k), 0, 255))
		g := u8(math.clamp(math.lerp(f32(p.colorStart.g), f32(p.colorEnd.g), k), 0, 255))
		b := u8(math.clamp(math.lerp(f32(p.colorStart.b), f32(p.colorEnd.b), k), 0, 255))
		a := u8(math.clamp(math.lerp(f32(p.colorStart.a), f32(p.colorEnd.a), k), 0, 255))
		p.color = {r, g, b, a}
	}
	if emitter.alphaCurve.count > 0 {
		p.color.a = u8(math.clamp(f32(p.color.a) * ParticleCurve_Sample(&emitter.alphaCurve, p.agePercent), 0, 255))
	}

	if p.age >= p.lifetime {
		p.alive = false
		p.agePercent = 1.0
		if emitter.onDeath != nil do emitter.onDeath(emitter, particle_to_world(emitter, p.position) if emitter.localSpace else p.position, emitter.onHitUser)
	}
}

// particle_emission_point: a birth point in the emitter's space (its
// emission shape) and the shape's outward normal there ({} = none).
@(private = "file")
particle_emission_point :: proc(emitter: ^ParticleEmitter) -> (point, normal: [2]f32) {
	sx, sy := math.abs(emitter.spread[0]), math.abs(emitter.spread[1])
	switch emitter.emissionShape {
	case .Rectangle:
		point = {safe_float32_range(-sx, sx), safe_float32_range(-sy, sy)}
	case .Point:
	case .Circle, .Ring:
		outer := math.abs(emitter.emissionRadius)
		inner := math.clamp(math.abs(emitter.emissionInnerRadius), 0, outer) if emitter.emissionShape == .Ring else 0
		a := rand.float32_range(0, math.TAU)
		// (Uniform over the area: the radius from the square root.)
		r := math.sqrt(safe_float32_range(inner * inner, outer * outer))
		normal = {math.cos(a), math.sin(a)}
		point = normal * r
	case .Line:
		point = {safe_float32_range(-sx, sx), 0}
		normal = {0, -1}
	case .RectangleEdge:
		// An edge picked by its length, then a point along it.
		w, h := 2 * sx, 2 * sy
		k := rand.float32_range(0, max(2 * (w + h), 0.0001))
		switch {
		case k < w:         point, normal = {-sx + k, -sy}, {0, -1}
		case k < w + h:     point, normal = {sx, -sy + (k - w)}, {1, 0}
		case k < 2 * w + h: point, normal = {sx - (k - w - h), sy}, {0, 1}
		case:               point, normal = {-sx, sy - (k - 2 * w - h)}, {-1, 0}
		}
	}
	return
}

Particle_Update :: proc{Particle_Update_Index, Particle_Update_Particle}

ParticleEmitter_DrawColorRampGui :: proc(emitter: ^ParticleEmitter, x: f32, nextY: ^f32, width: f32, selectedStop: ^int, draggingStop: ^bool, view: rl.Rectangle) {
	ramp := &emitter.colorRamp

	ui.GuiToggleSwitch({x, nextY^, width, 22}, "Enable Color Ramp (Gradient)", &emitter.useColorRamp)
	nextY^ += 26

	if !emitter.useColorRamp do return

	// Convert fixed stops array to dynamic array for GuiGradientEditor
	stopsDyn := make([dynamic]ui.ColorStop, context.temp_allocator)
	for i in 0..<ramp.count {
		append(&stopsDyn, ui.ColorStop{position = ramp.stops[i].position, color = ramp.stops[i].color})
	}

	gradRect := rl.Rectangle{x, nextY^, width, 120}
	changed := ui.GuiGradientEditor(gradRect, &stopsDyn, selectedStop, draggingStop, true)
	nextY^ += 130

	if changed {
		ramp.count = min(len(stopsDyn), MAX_COLOR_STOPS)
		for i in 0..<ramp.count {
			ramp.stops[i] = ColorStop{position = stopsDyn[i].position, color = stopsDyn[i].color}
		}
		ColorRamp_Sort(ramp, selectedStop)
	}

	// Selected Stop Controls (Color Picker, Alpha, Position, Add/Del)
	if selectedStop^ < 0 do selectedStop^ = 0
	if selectedStop^ >= ramp.count do selectedStop^ = ramp.count - 1

	ctrlY := nextY^
	DrawEngineText(fmt.ctprintf("Stop %d / %d", selectedStop^ + 1, ramp.count), x, ctrlY, 14, rl.WHITE)

	posVal := ramp.stops[selectedStop^].position
	sliderW := width - 180
	ui.GuiSlider({x + 70, ctrlY, sliderW, 18}, "", fmt.ctprintf("%.2f", posVal), &posVal, 0.0, 1.0)
	if posVal != ramp.stops[selectedStop^].position {
		ramp.stops[selectedStop^].position = posVal
		ColorRamp_Sort(ramp, selectedStop)
	}

	btnX := x + 70 + sliderW + 10
	if ramp.count < MAX_COLOR_STOPS {
		if ui.GuiButton({btnX, ctrlY, 40, 18}, "Add") {
			midT: f32 = 0.5
			idx := ColorRamp_AddStop(ramp, midT, ColorRamp_Evaluate(ramp, midT))
			if idx >= 0 do selectedStop^ = idx
		}
	}
	if ramp.count > 2 {
		if ui.GuiButton({btnX + 45, ctrlY, 40, 18}, "Del") {
			ColorRamp_RemoveStop(ramp, selectedStop^)
			if selectedStop^ >= ramp.count do selectedStop^ = ramp.count - 1
		}
	}

	ctrlY += 24
	c := &ramp.stops[selectedStop^].color
	alpha := f32(c.a) / 255.0
	pickerW := width - 70
	ui.GuiColorPicker({x + 70, ctrlY, pickerW, 55}, "Stop Color", c)
	ctrlY += 60
	ui.GuiColorBarAlpha({x + 70, ctrlY, pickerW, 18}, "Stop Alpha", &alpha)
	c.a = u8(math.round(alpha * 255.0))

	nextY^ = ctrlY + 26
}

// ParticleEmitter_Update emits and moves the particles; with collision on,
// they collide with `world`'s shapes (none: no collision).
ParticleEmitter_Update :: proc(emitter: ^ParticleEmitter, deltaTime: f32, world := b2.WorldId{}) {
	// Switched between CPU and GPU: the particles of the other mode go.
	if emitter.gpu != emitter.gpuApplied {
		for &p in emitter.particles do p.alive = false
		ParticleGPU_Clear(emitter)
		if !emitter.gpu do ParticleGPU_Release(emitter)
		emitter.gpuApplied = emitter.gpu
		emitter.cycleStarted = false // (a new cycle now, not after the old one's lifetime)
	}
	// Prewarm: a lifetime run at once (30 steps a second) before the first frame.
	if emitter.prewarm && !emitter.prewarmed && emitter.emitting {
		emitter.prewarmed = true
		steps := int(max(emitter.lifetime, 0) * 30)
		for _ in 0 ..< steps do particle_step(emitter, 1.0 / 30, world)
	}
	emitter.prewarmed = true
	before := emitter.aliveCount
	particle_step(emitter, deltaTime, world)
	n := 0
	if emitter.gpu do n = ParticleGPU_AliveCount(emitter)
	else do for &p in emitter.particles do if p.alive do n += 1
	emitter.aliveCount = n
	// A one-shot (or stopped) emitter's last particle died.
	if before > 0 && n == 0 && !emitter.emitting && emitter.onFinished != nil do emitter.onFinished(emitter, emitter.onHitUser)
}

// ParticleEmitter_EmitBurst emits n particles now (hits, explosions),
// whether it's emitting or not.
ParticleEmitter_EmitBurst :: proc(emitter: ^ParticleEmitter, n: int) {
	for _ in 0 ..< max(n, 0) do ParticleEmitter_Emit(emitter)
}

// ParticleEmitter_EmitAt emits n particles from a world point instead of
// the emitter's position (a sub-emitter's burst where a particle died or
// hit; #130). Its emission shape, angle and speeds still apply.
ParticleEmitter_EmitAt :: proc(emitter: ^ParticleEmitter, at: [2]f32, n: int) {
	if n <= 0 do return
	if !emitter.localSpace {
		// World particles: born around the point.
		saved := emitter.position
		emitter.position = at
		ParticleEmitter_EmitBurst(emitter, n)
		emitter.position = saved
		return
	}
	// Local particles: born at the point's offset in the emitter's space
	// (they move with the emitter after). Local GPU ones: at the emitter.
	if emitter.gpu {
		ParticleEmitter_EmitBurst(emitter, n)
		return
	}
	offset := particle_to_local(emitter, at)
	for _ in 0 ..< n {
		ParticleEmitter_Emit(emitter)
		if len(emitter.particles) == 0 do return
		i := (emitter.head - 1 + len(emitter.particles)) % len(emitter.particles)
		emitter.particles[i].position += offset
	}
}

// ParticleEmitter_Restart clears the particles and starts again (a seeded
// emitter repeats its pattern).
ParticleEmitter_Restart :: proc(emitter: ^ParticleEmitter) {
	for &p in emitter.particles do p.alive = false
	ParticleGPU_Clear(emitter)
	emitter.aliveCount = 0
	ParticleEmitter_Start(emitter)
}

// ParticleEmitter_VisibleBounds: the world rectangle the view culling tests.
ParticleEmitter_VisibleBounds :: proc(emitter: ^ParticleEmitter) -> rl.Rectangle {
	r := emitter.visibilityRect
	if emitter.autoVisibility {
		// (The last step's extent - centres, then the largest particle
		// around them: a circle's quad is twice its size, rotated corners
		// reach ~0.75 of the quad.)
		if !emitter.extentAny do return {emitter.position.x, emitter.position.y, 0, 0}
		pad := emitter.extentSize * 1.5
		lo, hi := emitter.extentMin - pad, emitter.extentMax + pad
		if !emitter.localSpace do return {lo.x, lo.y, hi.x - lo.x, hi.y - lo.y}
		r = {lo.x, lo.y, hi.x - lo.x, hi.y - lo.y} // (in its space: through the transform below)
	}
	pts := [4][2]f32{{r.x, r.y}, {r.x + r.width, r.y}, {r.x + r.width, r.y + r.height}, {r.x, r.y + r.height}}
	mn, mx := [2]f32{max(f32), max(f32)}, [2]f32{min(f32), min(f32)}
	for pt in pts {
		w := particle_to_world(emitter, pt)
		mn = {min(mn.x, w.x), min(mn.y, w.y)}
		mx = {max(mx.x, w.x), max(mx.y, w.y)}
	}
	return {mn.x, mn.y, mx.x - mn.x, mx.y - mn.y}
}

// particle_step: one simulation step (emission, motion, collision).
@(private = "file")
particle_step :: proc(emitter: ^ParticleEmitter, deltaTime: f32, world: b2.WorldId) {
	if emitter.emitting {
		targetAmount := max(emitter.amount, 0)
		cycleDuration := max(emitter.lifetime, 0.0001)
		burstVal := math.clamp(emitter.burst, 0.0, 1.0)
		emissionDuration := cycleDuration * (1.0 - burstVal)
		interval := emissionDuration / f32(targetAmount) if targetAmount > 0 else 0.0

		// Lifecycle start or loop (when continuous and lifetimer reaches lifetime)
		if !emitter.cycleStarted || (emitter.continuous && emitter.lifetimer >= emitter.lifetime) {
			emitter.lifetimer = 0
			emitter.timer = interval
			emitter.emittedInCycle = 0
			emitter.cycleStarted = true
		}

		emitter.lifetimer += deltaTime

		if emitter.emittedInCycle < targetAmount {
			if burstVal >= 1.0 || emissionDuration <= 0.0001 {
				for emitter.emittedInCycle < targetAmount {
					ParticleEmitter_Emit(emitter)
					emitter.emittedInCycle += 1
				}
			} else if interval > 0 { // (bounded by the target count: GPU emitters reach 1e-5 s intervals)
				emitter.timer += deltaTime
				for emitter.timer >= interval && emitter.emittedInCycle < targetAmount {
					ParticleEmitter_Emit(emitter)
					emitter.emittedInCycle += 1
					emitter.timer -= interval
				}
			}
		}
		emitter.count = emitter.emittedInCycle

		if !emitter.continuous && emitter.lifetimer >= emitter.lifetime {
			emitter.emitting = false
			emitter.cycleStarted = false
		}
	}

	// GPU mode: the shader moves them; only its clock runs here.
	if emitter.gpu {
		ParticleGPU_Advance(emitter, deltaTime)
		return
	}
	collide := emitter.collisionEnabled && b2.World_IsValid(world)
	emitter.stepGravity, emitter.stepWind = particle_forces(emitter)
	emitter.stepForces = true
	defer emitter.stepForces = false
	mn, mx := [2]f32{max(f32), max(f32)}, [2]f32{min(f32), min(f32)}
	big: f32 = 0
	trails := emitter.trailLength > 0
	if trails && len(emitter.trails) != len(emitter.particles) {
		if emitter.trails == nil {
			alloc := emitter.allocator if emitter.allocator.procedure != nil else context.allocator
			emitter.trails = make([dynamic]Particle_Trail, alloc)
		}
		resize(&emitter.trails, len(emitter.particles))
	}
	// (The trail reaches back up to its length: kept in view with the particles.)
	if trails do big = f32(min(emitter.trailLength, MAX_TRAIL_POINTS)) * max(emitter.trailSegment, 1)
	for i in 0..<len(emitter.particles) {
		if !emitter.particles[i].alive do continue
		prev := emitter.particles[i].position
		Particle_Update(emitter, i, deltaTime)
		if collide && emitter.particles[i].alive do particle_collide(emitter, &emitter.particles[i], prev, world)
		p := &emitter.particles[i]
		if !p.alive do continue
		if trails do particle_trail_record(emitter, &emitter.trails[i], p.position)
		mn, mx = {min(mn.x, p.position.x), min(mn.y, p.position.y)}, {max(mx.x, p.position.x), max(mx.y, p.position.y)}
		big = max(big, max(p.size.x * abs(p.scale.x), p.size.y * abs(p.scale.y)))
	}
	emitter.extentMin, emitter.extentMax, emitter.extentSize, emitter.extentAny = mn, mx, big, mn.x <= mx.x
}

// particle_trail_record: a new trail point once the particle is
// trailSegment from the newest one (the first: where it is).
@(private = "file")
particle_trail_record :: proc(emitter: ^ParticleEmitter, t: ^Particle_Trail, pos: [2]f32) {
	if t.count > 0 {
		d := pos - t.points[t.head]
		seg := max(emitter.trailSegment, 1)
		if d.x * d.x + d.y * d.y < seg * seg do return
	}
	t.head = u8((int(t.head) + 1) % MAX_TRAIL_POINTS) if t.count > 0 else 0
	t.points[t.head] = pos
	t.count = u8(min(int(t.count) + 1, min(max(emitter.trailLength, 1), MAX_TRAIL_POINTS)))
}

@(private = "file")
Particle_Ray_Hit :: struct {
	hit:      bool,
	point:    [2]f32,
	normal:   [2]f32,
	fraction: f32,
	shape:    b2.ShapeId,
}

// particle_ray_callback: the closest solid shape along the move (trigger
// areas - sensors - don't stop particles).
@(private = "file")
particle_ray_callback :: proc "c" (shapeId: b2.ShapeId, point: b2.Vec2, normal: b2.Vec2, fraction: f32, ctx: rawptr) -> f32 {
	if b2.Shape_IsSensor(shapeId) do return -1
	r := cast(^Particle_Ray_Hit)ctx
	r^ = {true, point, normal, fraction, shapeId}
	return fraction
}

// particle_collide: the particle moved from `prev`; if a solid shape was in
// the way, it bounces off it, stops on it or dies there (collisionMode).
// The whole move is cast, so fast particles don't pass through thin walls.
@(private = "file")
particle_collide :: proc(emitter: ^ParticleEmitter, p: ^Particle, prevIn: [2]f32, world: b2.WorldId) {
	// (Local particles: cast in the world, the result brought back.)
	prev, pos, vel := prevIn, p.position, p.velocity
	if emitter.localSpace {
		prev, pos, vel = particle_to_world(emitter, prevIn), particle_to_world(emitter, p.position), particle_dir_to_world(emitter, p.velocity)
	}
	defer if p.alive {
		p.position = particle_to_local(emitter, pos) if emitter.localSpace else pos
		p.velocity = particle_dir_to_local(emitter, vel) if emitter.localSpace else vel
	}
	move := pos - prev
	if move.x * move.x + move.y * move.y < 1e-6 do return
	hit: Particle_Ray_Hit
	filter := b2.QueryFilter{categoryBits = ~u64(0), maskBits = CollisionLayerSet_ToBits(emitter.collisionLayers)}
	_ = b2.World_CastRay(world, prev, move, filter, particle_ray_callback, &hit)
	if !hit.hit do return
	n := hit.normal
	switch emitter.collisionMode {
	case .Kill:
		p.alive = false
	case .Stop:
		pos = hit.point + n * 0.01
		vel = {}
		p.acceleration = {}
	case .Bounce:
		pos = hit.point + n * 0.01
		vn := vel.x * n.x + vel.y * n.y
		if vn < 0 {
			tangent := vel - n * vn
			vel = tangent * (1 - math.clamp(emitter.friction, 0, 1)) - n * vn * math.clamp(emitter.elasticity, 0, 1)
		}
	}
	hitNode: ^Node
	if body := b2.Shape_GetBody(hit.shape); b2.Body_IsValid(body) do hitNode = cast(^Node)b2.Body_GetUserData(body)
	emitter.lastHitPoint, emitter.lastHitNormal, emitter.lastHitNode = hit.point, n, hitNode
	if emitter.onHit != nil do emitter.onHit(emitter, hitNode, emitter.onHitUser)
}

// --- drawing (#125) --------------------------------------------------------------------
// Every live particle of an emitter is one textured quad written straight
// into rlgl's batch: circles and ellipses from a small anti-aliased circle
// texture, rectangles / pixels / lines from the default white texel,
// textured particles from their texture - one draw per texture, not a
// raylib call (and for circles a triangle fan) per particle. Written in
// chunks, each after making room in the batch (rlgl drops vertices past its
// buffer instead of flushing).

@(private = "file")
PARTICLE_CHUNK :: 1024

@(private = "file")
particleCircleTex: rl.Texture2D

// particle_circle_texture: a white disc, anti-aliased edge, alpha outside.
particle_circle_texture :: proc() -> u32 {
	if particleCircleTex.id != 0 do return particleCircleTex.id
	N :: 64
	// Transparent white, not BLANK (transparent black): the filtering blends
	// the edge with its neighbours, and black ones made a dark rim.
	img := rl.GenImageColor(N, N, {255, 255, 255, 0})
	defer rl.UnloadImage(img)
	r := f32(N) * 0.5
	for y in 0 ..< N do for x in 0 ..< N {
		d := math.sqrt((f32(x) + 0.5 - r) * (f32(x) + 0.5 - r) + (f32(y) + 0.5 - r) * (f32(y) + 0.5 - r))
		a := math.clamp(r - d, 0, 1)
		if a > 0 do rl.ImageDrawPixel(&img, i32(x), i32(y), {255, 255, 255, u8(a * 255)})
	}
	particleCircleTex = rl.LoadTextureFromImage(img)
	rl.SetTextureFilter(particleCircleTex, .BILINEAR)
	Pixel_RecordFilter(particleCircleTex.id, .BILINEAR)
	return particleCircleTex.id
}

// Particles_Shutdown frees the shared drawing texture (engine shutdown).
// The runner closes the window first: no GL context to free it in then
// (Mesa crashes on it) - it went with the context.
Particles_Shutdown :: proc() {
	if particleCircleTex.id != 0 && rl.IsWindowReady() do rl.UnloadTexture(particleCircleTex)
	particleCircleTex = {}
}

@(private = "file")
Particle_Batch :: struct {
	tex:  u32,
	n:    int,
	open: bool,
}

@(private = "file")
batch_use :: proc(b: ^Particle_Batch, tex: u32) {
	if b.open && b.tex == tex && b.n < PARTICLE_CHUNK do return
	batch_close(b)
	Pixel_UseTexture({id = tex}) // (the emitter node's Texture Filter, #409)
	rlgl.CheckRenderBatchLimit(4 * PARTICLE_CHUNK)
	rlgl.SetTexture(tex)
	rlgl.Begin(rlgl.QUADS)
	b^ = {tex = tex, open = true}
}

@(private = "file")
batch_close :: proc(b: ^Particle_Batch) {
	if !b.open do return
	rlgl.End()
	rlgl.SetTexture(0)
	b.open = false
}

// batch_quad: a w x h quad centred on c, turned by rotDeg, the texture's
// uv rectangle (u0, v0) - (u1, v1) on it.
@(private = "file")
batch_quad :: proc(b: ^Particle_Batch, c: [2]f32, w, h, rotDeg: f32, col: rl.Color, uv := [4]f32{0, 0, 1, 1}, pivot := [2]f32{0.5, 0.5}) {
	hw, hh := w * 0.5, h * 0.5
	ax, ay := [2]f32{hw, 0}, [2]f32{0, hh}
	if rotDeg != 0 {
		r := math.to_radians(rotDeg)
		cs, sn := math.cos(r), math.sin(r)
		ax, ay = {hw * cs, hw * sn}, {-hh * sn, hh * cs}
	}
	c := c
	if pivot != {0.5, 0.5} do c += ax * (1 - 2 * pivot.x) + ay * (1 - 2 * pivot.y) // (the pivot on c)
	tl, bl, br, tr := c - ax - ay, c - ax + ay, c + ax + ay, c + ax - ay
	rlgl.Color4ub(col.r, col.g, col.b, col.a)
	rlgl.TexCoord2f(uv[0], uv[1]); rlgl.Vertex2f(tl.x, tl.y)
	rlgl.TexCoord2f(uv[0], uv[3]); rlgl.Vertex2f(bl.x, bl.y)
	rlgl.TexCoord2f(uv[2], uv[3]); rlgl.Vertex2f(br.x, br.y)
	rlgl.TexCoord2f(uv[2], uv[1]); rlgl.Vertex2f(tr.x, tr.y)
	b.n += 1
}

// What a particle is drawn with.
Particle_Quad_Texture :: enum {
	None,    // not drawn (no texture) or drawn by its own proc (Custom)
	White,   // the default white texel
	Circle,  // the anti-aliased disc
	Texture, // its own texture
}

// particle_trail_draw: the ribbon from the particle back through its
// trail's points, thinning to nothing and fading at the oldest.
@(private = "file")
particle_trail_draw :: proc(emitter: ^ParticleEmitter, b: ^Particle_Batch, white: u32, p: Particle, t: ^Particle_Trail) {
	q := Particle_QuadOf(emitter, p)
	pts: [MAX_TRAIL_POINTS + 1][2]f32
	pts[0] = q.center
	n := 1
	for k in 0 ..< int(t.count) {
		pt := t.points[(int(t.head) - k + MAX_TRAIL_POINTS) % MAX_TRAIL_POINTS]
		pts[n] = particle_to_world(emitter, pt) if emitter.localSpace else pt
		n += 1
	}
	if n < 2 do return
	width := emitter.trailWidth * max(min(q.size.x, q.size.y), 1)
	if p.shape == .Line do width = emitter.trailWidth * max(q.size.y, 1)
	edge :: proc(pts: [][2]f32, k: int, w: f32) -> (l, r: [2]f32) {
		d := pts[max(k - 1, 0)] - pts[min(k + 1, len(pts) - 1)]
		ln := math.sqrt(d.x * d.x + d.y * d.y)
		nrm := [2]f32{-d.y, d.x} / ln * w * 0.5 if ln > 0.0001 else [2]f32{}
		return pts[k] + nrm, pts[k] - nrm
	}
	for k in 0 ..< n - 1 {
		f0, f1 := 1 - f32(k) / f32(n - 1), 1 - f32(k + 1) / f32(n - 1)
		l0, r0 := edge(pts[:n], k, width * f0)
		l1, r1 := edge(pts[:n], k + 1, width * f1)
		c0, c1 := q.color, q.color
		c0.a, c1.a = u8(f32(q.color.a) * f0), u8(f32(q.color.a) * f1)
		batch_use(b, white)
		// (Front-facing: raylib culls the other winding.)
		a, bb, c, dd := l0, r0, r1, l1
		ca, cb, cc, cd := c0, c0, c1, c1
		if (bb.x - a.x) * (c.y - a.y) - (bb.y - a.y) * (c.x - a.x) > 0 do a, bb, c, dd, ca, cb, cc, cd = r0, l0, l1, r1, c0, c0, c1, c1
		rlgl.TexCoord2f(0, 0)
		rlgl.Color4ub(ca.r, ca.g, ca.b, ca.a); rlgl.Vertex2f(a.x, a.y)
		rlgl.Color4ub(cb.r, cb.g, cb.b, cb.a); rlgl.Vertex2f(bb.x, bb.y)
		rlgl.Color4ub(cc.r, cc.g, cc.b, cc.a); rlgl.Vertex2f(c.x, c.y)
		rlgl.Color4ub(cd.r, cd.g, cd.b, cd.a); rlgl.Vertex2f(dd.x, dd.y)
		b.n += 1
	}
}

// Particle_Quad: one particle as drawn - a w x h quad centred on `center`,
// turned by `rotation` degrees, in world terms.
Particle_Quad :: struct {
	center:   [2]f32,
	size:     [2]f32,
	rotation: f32,
	color:    rl.Color,
	texture:  Particle_Quad_Texture,
	uv:       [4]f32, // u0, v0, u1, v1 (a sprite sheet's frame; flipped: swapped)
	pivot:    [2]f32, // the point of the quad (0..1) on `center` (Texture Pivot, #401)
}

// --- frames (#401) ---------------------------------------------------------------------

// ParticleEmitter_ResolveFrames works out the frames to draw from the frame
// source (the node calls it before each draw with its texture's details;
// an emitter on its own: the grid over its texture).
ParticleEmitter_ResolveFrames :: proc(emitter: ^ParticleEmitter, input: Particle_Frame_Input) {
	f := &emitter.frames
	f.count, f.list, f.timed, f.first, f.cols = 1, false, false, 0, 1
	f.texSize = input.texSize
	if f.texSize == {} && emitter.texture != nil do f.texSize = {f32(emitter.texture.width), f32(emitter.texture.height)}
	off := [2]f32{input.region.x, input.region.y}
	size := [2]f32{input.region.width, input.region.height} if input.region.width > 0 else f.texSize
	f.origin, f.step, f.cell = off, size, size
	// A range of a grid's `total` cells.
	ranged :: proc(emitter: ^ParticleEmitter, total: int) -> (first, count: int) {
		first = clamp(emitter.frameFirst, 0, max(total - 1, 0))
		count = total - first
		if emitter.frameCount > 0 do count = min(count, emitter.frameCount)
		return first, max(count, 1)
	}
	switch emitter.frameSource {
	case .Grid:
		cols, rows := max(emitter.sheetColumns, 1), max(emitter.sheetRows, 1)
		f.cell = size / {f32(cols), f32(rows)}
		f.step, f.cols = f.cell, cols
		f.first, f.count = ranged(emitter, cols * rows)
	case .Slices:
		s := input.slice
		if s.cellSize.x > 0 && s.cellSize.y > 0 {
			fit := SpriteSheet_FitGrid(size, s.margin, s.spacing, s.cellSize)
			f.cell = {f32(s.cellSize.x), f32(s.cellSize.y)}
			f.cols = max(fit.x, 1)
			f.first, f.count = ranged(emitter, max(fit.x * fit.y, 1))
		} else if s.grid.x > 0 && s.grid.y > 0 {
			r := SpriteSheet_CellRect(size, s.grid, s.margin, s.spacing, 0)
			f.cell = {r.width, r.height}
			f.cols = s.grid.x
			f.first, f.count = ranged(emitter, s.grid.x * s.grid.y)
		} else {
			return // (no preset: the whole texture)
		}
		f.origin = off + {f32(s.margin.x), f32(s.margin.y)}
		f.step = f.cell + {f32(s.spacing.x), f32(s.spacing.y)}
	case .Regions:
		if emitter.regions.count == 0 do return
		f.list, f.count = true, emitter.regions.count
		for i in 0 ..< f.count {
			r := emitter.regions.rects[i]
			f.rects[i] = {r.x + off.x, r.y + off.y, r.width, r.height}
		}
	case .Aseprite:
		doc := input.ase
		if doc == nil || len(doc.frames) == 0 do return
		// The tag's frames in its direction (ping-pong: there and back,
		// the ends once), as a list of the sheet's cells.
		from, to, dir := 0, len(doc.frames) - 1, Ase_Direction.Forward
		if input.tag != "" {
			if t := Ase_FindTag(doc, input.tag); t != nil do from, to, dir = clamp(t.from, 0, len(doc.frames) - 1), clamp(t.to, 0, len(doc.frames) - 1), t.direction
		}
		seq: [MAX_PARTICLE_FRAMES]int
		n := 0
		add :: proc(seq: ^[MAX_PARTICLE_FRAMES]int, n: ^int, k: int) {
			if n^ < MAX_PARTICLE_FRAMES {seq[n^] = k; n^ += 1}
		}
		fwd, rev := dir == .Forward || dir == .Ping_Pong, dir == .Reverse || dir == .Ping_Pong_Reverse
		if fwd do for k in from ..= to do add(&seq, &n, k)
		if rev do for k := to; k >= from; k -= 1 do add(&seq, &n, k)
		if dir == .Ping_Pong do for k := to - 1; k > from; k -= 1 do add(&seq, &n, k)
		if dir == .Ping_Pong_Reverse do for k in from + 1 ..< to do add(&seq, &n, k)
		cols := max(input.aseCols, 1)
		w, h := f32(doc.width), f32(doc.height)
		f.list, f.count = true, max(n, 1)
		end: f32 = 0
		for i in 0 ..< n {
			k := seq[i]
			f.rects[i] = {f32(k % cols) * w, f32(k / cols) * h, w, h}
			end += f32(max(doc.frames[k].duration, 1)) / 1000
			f.ends[i] = end
		}
		f.timed = emitter.frameFileTiming && n > 1
	}
}

// Particle_Seed16: a particle's random number as the GPU has it (16 bits:
// the frame, the start frame and the flips come from it).
Particle_Seed16 :: #force_inline proc(p: Particle) -> int {return int(p.frameSeed % 65536)}

// Particle_Frame: the frame a particle shows now (0-based, of the resolved
// frames; the GPU shader's frameIndex is the same).
Particle_Frame :: proc(emitter: ^ParticleEmitter, p: Particle) -> int {
	fr := &emitter.frames
	n := fr.count
	if n <= 1 do return 0
	seed := Particle_Seed16(p)
	if emitter.frameMode == .Random do return seed % n
	start := (seed >> 10) % n if emitter.frameRandomStart else 0
	wraps := emitter.frameMode == .OverLifetime || emitter.frameLoop
	if fr.timed {
		total := fr.ends[n - 1]
		t := p.agePercent * total if emitter.frameMode == .OverLifetime else p.age
		if start > 0 do t += fr.ends[start - 1]
		t = math.mod(t, total) if wraps else min(t, total * 0.99999)
		for i in 0 ..< n do if t < fr.ends[i] do return i
		return n - 1
	}
	f := min(int(p.agePercent * f32(n)), n - 1) if emitter.frameMode == .OverLifetime else int(p.age * max(emitter.frameSpeed, 0))
	f += start
	return f % n if wraps else min(f, n - 1)
}

// Particle_FrameRect: frame i's rectangle (the GPU texture's pixels).
Particle_FrameRect :: proc(fr: ^Particle_Frames, i: int) -> rl.Rectangle {
	if fr.list do return fr.rects[clamp(i, 0, MAX_PARTICLE_FRAMES - 1)]
	cell := fr.first + i
	cols := max(fr.cols, 1)
	return {fr.origin.x + f32(cell % cols) * fr.step.x, fr.origin.y + f32(cell / cols) * fr.step.y, fr.cell.x, fr.cell.y}
}

// Particle_Flips: a particle's random flips (Random Flip X / Y; seed bits 8, 9).
Particle_Flips :: proc(emitter: ^ParticleEmitter, p: Particle) -> (x, y: bool) {
	seed := Particle_Seed16(p)
	return emitter.randomFlipX && (seed >> 8) & 1 == 1, emitter.randomFlipY && (seed >> 9) & 1 == 1
}

// Particle_QuadOf: how a live particle is drawn (local particles through
// the owner's transform, #124).
Particle_QuadOf :: proc(emitter: ^ParticleEmitter, particle: Particle) -> Particle_Quad {
	p := particle
	if emitter.alignToVelocity && (p.velocity.x != 0 || p.velocity.y != 0) {
		p.rotation = math.to_degrees(math.atan2(p.velocity.y, p.velocity.x)) + emitter.rotation
	}
	if emitter.localSpace {
		sc := particle_scale(emitter)
		p.position = particle_to_world(emitter, p.position)
		p.size *= {abs(sc.x), abs(sc.y)}
		p.rotation += emitter.originRotation
	}
	q := Particle_Quad{center = p.position, rotation = p.rotation, color = p.color, uv = {0, 0, 1, 1}, pivot = {0.5, 0.5}}
	switch p.shape {
	case .Circle:
		d := 2 * p.size[0] * p.scale[0]
		q.size, q.rotation, q.texture = {d, d}, 0, .Circle
	case .Ellipse:
		q.size, q.rotation, q.texture = {2 * p.size[0] * p.scale[0], 2 * p.size[1] * p.scale[1]}, 0, .Circle
	case .Rectangle:
		q.size, q.texture = {p.size[0] * p.scale[0], p.size[1] * p.scale[1]}, .White
	case .Pixel:
		q.center, q.size, q.rotation, q.texture = p.position + 0.5, {1, 1}, 0, .White
	case .Line:
		q.size, q.texture = {p.size[0] * p.scale[0], max(p.scale[1], 0.01)}, .White
	case .Texture:
		q.size = {p.size[0] * p.scale[0], p.size[1] * p.scale[1]}
		q.texture = .Texture if emitter.texture != nil && emitter.texture.id != 0 else .None
		// The frame's part of the texture (#401: any frame source; an
		// atlased texture's region), flipped, and the pivot.
		fr := &emitter.frames
		if fr.texSize.x > 0 && fr.texSize.y > 0 && (fr.count > 1 || fr.list || fr.cell != fr.texSize || fr.origin != {}) {
			r := Particle_FrameRect(fr, Particle_Frame(emitter, p))
			q.uv = {r.x / fr.texSize.x, r.y / fr.texSize.y, (r.x + r.width) / fr.texSize.x, (r.y + r.height) / fr.texSize.y}
		}
		q.pivot = emitter.texturePivot
		fx, fy := Particle_Flips(emitter, p)
		if fx do q.uv[0], q.uv[2], q.pivot.x = q.uv[2], q.uv[0], 1 - q.pivot.x
		if fy do q.uv[1], q.uv[3], q.pivot.y = q.uv[3], q.uv[1], 1 - q.pivot.y
	case .Custom:
		q.texture = .None
	}
	return q
}

ParticleEmitter_Render :: proc(emitter: ^ParticleEmitter, deltaTime: f32 = 0) {
	// The frames (#401): the owner's for this draw, else the grid.
	if !emitter.frames.ownerSet do ParticleEmitter_ResolveFrames(emitter, {})
	emitter.frames.ownerSet = false
	if emitter.gpu {
		ParticleGPU_Render(emitter)
		return
	}
	white := rlgl.GetTextureIdDefault()
	circle := particle_circle_texture()
	b: Particle_Batch
	blend := emitter.blendMode != .Alpha
	if blend {
		switch emitter.blendMode {
		case .Alpha:
		case .Additive:      rl.BeginBlendMode(.ADDITIVE)
		case .Multiply:      rl.BeginBlendMode(.MULTIPLIED)
		case .Premultiplied: rl.BeginBlendMode(.ALPHA_PREMULTIPLY)
		}
	}
	defer if blend do rl.EndBlendMode()
	defer batch_close(&b) // (runs first: the quads go out in the blend mode)
	// Trails first: behind the particles.
	if emitter.trailLength > 0 && len(emitter.trails) == len(emitter.particles) {
		for i in 0 ..< len(emitter.particles) {
			if emitter.particles[i].alive && emitter.trails[i].count > 0 do particle_trail_draw(emitter, &b, white, emitter.particles[i], &emitter.trails[i])
		}
	}
	snap := Pixel_Snaps() // (on whole pixels with the emitter's / project's snap, #409)
	for i in 0..<len(emitter.particles) {
		if !emitter.particles[i].alive do continue
		p := &emitter.particles[i]
		q := Particle_QuadOf(emitter, p^)
		if snap && q.rotation == 0 do q.center = Pixel_SnapPoint(q.center - q.size * 0.5) + q.size * 0.5
		switch q.texture {
		case .White:   batch_use(&b, white)
		case .Circle:  batch_use(&b, circle)
		case .Texture: batch_use(&b, emitter.texture.id)
		case .None:
			// A Custom shape draws as it likes (the batch closed around it).
			if p.shape == .Custom && p.customShapeProc != nil {
				batch_close(&b)
				c := p^
				c.position, c.rotation = q.center, q.rotation
				p.customShapeProc(&c, deltaTime)
			}
			continue
		}
		batch_quad(&b, q.center, q.size.x, q.size.y, q.rotation, q.color, q.uv, q.pivot)
	}
}
