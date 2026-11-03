package engine

import "core:c"
import "core:fmt"
import "core:log"
import "core:math/rand"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:thread"
import lua "lua54"

// ============================================================================
// LevelGeneratorNode (#142, phase 4): generates a level from a generator
// file (.levelgen.json, level_gen.odin) into a TileMap in the game - when
// the scene starts, from a script (generate()) or a signal to `generate`.
//
// - `tilemap`: the map it fills, as a path from this node; empty: its first
//   TileMap child, else its parent when that is a TileMap.
// - `seed` (0: the generator's), or `randomSeed`: a new one each time;
//   `lastSeed` is the one used (show it, save it to replay the level).
//   With randomSeed, a level the generator refuses (a Check node: too little
//   open, in pieces) is tried again with other seeds, `attempts` in all.
// - Parameters of the generator's nodes can be set on the node (the
//   Inspector's Level Parameters, set_level_param from Lua): one generator
//   file, many levels - a harder cave on level 3, a bigger dungeon.
// - `background`: generated on a worker thread while the game runs (a big
//   level doesn't freeze a loading screen); the tiles and entities go in
//   when it is done, at the start of a frame. The web build generates at
//   once.
// - Events: "generated" (the seed) when the level is in, "generation_failed"
//   (why); the event bus gets "level_generated" (the map's name) too.
// - Progress (#171): `progress`, 0..1 - the generator's nodes computed (a
//   seed tried again counts on: Gen_Progress) - and "generation_progress"
//   (the fraction) when it moves by 1% or more (at most once a frame), 0 at
//   the start and 1 when the level is in, for a loading bar. The worker
//   writes the fraction (atomic); the main thread reads it in update and
//   emits.
// - `rebakeNavigation`: the scene's Navigation Regions are baked again once
//   the level is in (tiles, colliders, components, entities), before
//   "generated" - agents find paths through the new map at once.
// - `chunked` (#171): an endless level, made a chunk (chunkSize cells
//   square) at a time around a camera (`cameraPath`, else the scene's) -
//   those within `chunkRadius` chunks of the camera's are kept in, those
//   more than chunkRadius + 1 away go (tiles, colliders, components and
//   entities). Each chunk is the level's cells there (level_gen_chunks.odin:
//   chunk-safe nodes leave no seams) and always the same for a seed. They
//   generate on worker threads, nearest first, and go in at the start of a
//   frame; with `background` off the first ones (around the camera) go in
//   at once. Events "chunk_generated" / "chunk_unloaded" (the chunk: a Vec2
//   of its x, y); "generated" once the first chunks are all in; `progress`:
//   the chunks around the camera that are in (it drops as the camera moves
//   on to new ground). The map is endless (TileMapNode.unbounded).
//
// The parameters are saved as "level_generator": {"params": [{"node",
// "name", "value"}]} next to the reflected properties.
// ============================================================================

// A generator node's parameter set on the LevelGeneratorNode.
Gen_Param_Override :: struct {
	node:  int,    // the generator node's id
	name:  string, // its parameter (node arena)
	value: f64,
}

LevelGeneratorNode :: struct {
	using node: Node,
	generator:       string `gui:"true"`,
	tilemap:         string `gui:"true"`,
	seed:            int `gui:"true" min:"0" max:"1073741824"`,
	randomSeed:      bool `gui:"true"`,
	generateOnReady: bool `gui:"true"`,
	background:      bool `gui:"true"`,
	attempts:        int `gui:"true" min:"1" max:"100"`,
	rebakeNavigation: bool `gui:"true"`,
	// Chunked (#171): an endless level around a camera.
	chunked:         bool `gui:"true"`,
	chunkSize:       int `gui:"true" min:"4" max:"256"`, // cells
	chunkRadius:     int `gui:"true" min:"0" max:"16"`,  // chunks kept in around the camera's
	cameraPath:      string `gui:"true"`,                // the node it follows ("": the scene's camera)
	params:          [dynamic]Gen_Param_Override, // (node arena)
	// Runtime.
	lastSeed:        int `gui:"true" save:"false"`,
	progress:        f32 `gui:"true" save:"false"`, // 0..1: the generation's (1: the level is in)
	progressSent:    f32, // the last "generation_progress" emitted
	loadedChunks:    int `gui:"true" save:"false"`, // chunked: the chunks in now
	started:         bool, // the first update ran (generateOnReady)
	job:             ^Gen_Job, // a background generation in flight (heap)
	world:           ^Gen_Chunk_World, // chunked: the chunks (heap)
	onGenerated:     EventSubject, // "generated" (the seed)
	onFailed:        EventSubject, // "generation_failed" (why)
	onProgress:      EventSubject, // "generation_progress" (0..1)
	onChunkGenerated: EventSubject, // "chunk_generated" (the chunk: x, y)
	onChunkUnloaded: EventSubject, // "chunk_unloaded" (the chunk: x, y)
}

// A chunked generator's chunks: the generator (read by the workers, so
// never changed while it runs), what is in and what is being made.
Gen_Chunk_World :: struct {
	graph:     Gen_Graph, // (heap)
	seed:      u64,
	size:      int, // cells per chunk side
	apron:     int, // Gen_ChunkInfo's
	unsafe:    int, // nodes that aren't chunk-safe (warned once)
	chunks:    map[[2]int]Gen_Chunk, // in (heap)
	jobs:      [dynamic]^Gen_Chunk_Job, // being made (heap)
	center:    [2]int, // the camera's chunk
	done:      bool, // "generated" sent (the first chunks all in)
	navDirty:  bool, // chunks came or went since the regions were baked
	maps:      [dynamic][2]u32, // the maps made endless (the main one, layers'), as (slot, generation)
}

// A chunk that is in: what it put in the scene (removed when it goes), as
// (slot, generation) handles - a script may have removed some already.
Gen_Chunk :: struct {
	nodes:  [dynamic][2]u32, // colliders, components, entities (heap)
	failed: bool, // the generator refused it (empty; not tried again)
}

// A chunk being made on a worker thread (it reads the world's graph only).
Gen_Chunk_Job :: struct {
	coord:  [2]int,
	graph:  ^Gen_Graph,
	seed:   u64,
	size, apron: int,
	result: Gen_Result, // (heap)
	err:    string,     // (heap)
	thread: ^thread.Thread,
}

// A background generation: the worker owns `graph` and fills `result` /
// `err`; the main thread applies it once the thread is done.
Gen_Job :: struct {
	graph:  Gen_Graph, // (heap)
	seed:   u64, // (the seed of the level made)
	attempts: int,
	progress: Gen_Progress, // (the worker writes, the main thread reads its value)
	result: Gen_Result, // (heap)
	err:    string,     // (heap)
	thread: ^thread.Thread,
}

LevelGeneratorNode_Create :: proc(scene: ^Scene, name: string = "LevelGenerator", parent: ^Node = nil) -> ^LevelGeneratorNode {
	lg := CreateNode(scene.manager, LevelGeneratorNode)
	lg.name = strings.clone(name, lg.allocator)
	lg.generateOnReady = true
	lg.attempts = 10
	lg.chunkSize = 32
	lg.chunkRadius = 2
	lg.params = make([dynamic]Gen_Param_Override, lg.allocator)
	lg.update = LevelGeneratorNode_Update
	lg.onDestroy = LevelGeneratorNode_Destroy
	InitializeSubject(&lg.onGenerated, "generated", lg)
	InitializeSubject(&lg.onFailed, "generation_failed", lg)
	InitializeSubject(&lg.onProgress, "generation_progress", lg)
	InitializeSubject(&lg.onChunkGenerated, "chunk_generated", lg)
	InitializeSubject(&lg.onChunkUnloaded, "chunk_unloaded", lg)
	scene->addNode(lg, parent)
	return lg
}

LevelGeneratorNode_Destroy :: proc(node: ^Node, ctx: ^GameContext) {
	lg := cast(^LevelGeneratorNode)node
	if lg.job != nil do gen_job_free(lg.job) // (waits for the worker)
	lg.job = nil
	levelgen_chunks_stop(lg, nil, ctx, false) // (the scene's nodes go with it)
	DestroySubject(&lg.onGenerated)
	DestroySubject(&lg.onFailed)
	DestroySubject(&lg.onProgress)
	DestroySubject(&lg.onChunkGenerated)
	DestroySubject(&lg.onChunkUnloaded)
}

// The first update generates (generateOnReady: before the first frame is
// drawn, every node of the scene in); later ones pick up a finished
// background generation.
LevelGeneratorNode_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	lg := cast(^LevelGeneratorNode)node
	if !lg.started {
		lg.started = true
		if lg.generateOnReady && lg.generator != "" do LevelGeneratorNode_Generate(lg, ctx)
	}
	if lg.world != nil do levelgen_chunks_update(lg, ctx)
	if lg.job == nil do return
	levelgen_progress(lg, f32(Gen_ProgressValue(&lg.job.progress)), ctx)
	when ODIN_OS != .JS do if !thread.is_done(lg.job.thread) do return
	sync.atomic_thread_fence(.Acquire)
	j := lg.job
	lg.job = nil
	defer gen_job_free(j)
	if j.err != "" {
		levelgen_progress(lg, f32(Gen_ProgressValue(&j.progress)), ctx) // (where it stopped)
		levelgen_failed(lg, j.err, ctx)
		return
	}
	levelgen_apply(lg, &j.result, j.seed, ctx)
}

// LevelGeneratorNode_Generate makes a level (seed 0: the node's seed, a
// random one with randomSeed, else the generator's). In the background it
// starts the worker and returns true; the level goes in later ("generated").
// False, why: it couldn't (no generator or map, a bad file, a generation
// already running) - "generation_failed" was emitted too. `scene`: the
// one it is in (default: the context's - the editor passes its own).
LevelGeneratorNode_Generate :: proc(lg: ^LevelGeneratorNode, ctx: ^GameContext, seed := 0, scene: ^Scene = nil) -> (ok: bool, why: string) {
	if lg.job != nil do return false, "already generating"
	if lg.chunked do return levelgen_chunks_start(lg, ctx, seed, scene)
	if lg.world != nil do levelgen_chunks_stop(lg, scene if scene != nil else levelgen_scene(ctx), ctx, true) // (no longer chunked)
	if lg.generator == "" do return levelgen_failed(lg, "pick its generator (a .levelgen.json)", ctx), "pick its generator (a .levelgen.json)"
	tm := LevelGeneratorNode_Target(lg, ctx, scene)
	if tm == nil do return levelgen_failed(lg, "no TileMap to fill (set Tile Map, or add one as a child)", ctx), "no TileMap to fill (set Tile Map, or add one as a child)"
	s := seed
	if s == 0 do s = lg.seed
	if s == 0 && lg.randomSeed do s = 1 + int(rand.int31_max(1 << 30))
	a := Engine_HeapAllocator() if lg.background else context.temp_allocator
	g, err := Gen_LoadFile(ctx, lg.generator, a)
	if err != "" do return levelgen_failed(lg, err, ctx), err
	g.layout, g.stagger = tm.layout, tm.stagger // (terrains on the map's grid)
	for p in lg.params do if n := Gen_FindNode(&g, p.node); n != nil do Gen_SetParam(n, p.name, p.value)
	used := u64(s) if s != 0 else g.seed
	// Other seeds only when it picks them (not a seed asked for).
	attempts := clamp(lg.attempts, 1, 100) if seed == 0 && lg.seed == 0 && lg.randomSeed else 1
	lg.progress, lg.progressSent = 0, 0
	lg.onProgress->notify(lg, f64(0), ctx)
	when ODIN_OS != .JS {
		if lg.background {
			j := new(Gen_Job, Engine_HeapAllocator())
			j.graph, j.seed, j.attempts = g, used, attempts
			j.thread = thread.create(gen_job_run)
			j.thread.data = j
			lg.job = j
			thread.start(j.thread)
			return true, ""
		}
	}
	defer Gen_GraphDestroy(&g)
	progress: Gen_Progress
	r, made, gerr := levelgen_generate(&g, used, attempts, context.temp_allocator, &progress)
	used = made
	if gerr != "" {
		lg.progress = f32(Gen_ProgressValue(&progress)) // (where it stopped)
		return levelgen_failed(lg, gerr, ctx), gerr
	}
	if aerr := levelgen_apply(lg, &r, used, ctx, scene); aerr != "" do return false, aerr
	return true, ""
}

// LevelGeneratorNode_Target: the TileMap it fills.
LevelGeneratorNode_Target :: proc(lg: ^LevelGeneratorNode, ctx: ^GameContext = nil, scene: ^Scene = nil) -> ^TileMapNode {
	sc := scene if scene != nil else levelgen_scene(ctx if ctx != nil else lg.gameContext)
	if sc == nil do return nil
	if lg.tilemap != "" {
		n := Node_ResolvePath(sc.manager, lg, lg.tilemap)
		return cast(^TileMapNode)n if n != nil && n.typeId == TileMapNode else nil
	}
	for ch in GetChildrenTemp(sc.manager, lg) do if ch != nil && !ch.removing && ch.typeId == TileMapNode do return cast(^TileMapNode)ch
	if p := GetParent(sc.manager, lg); p != nil && p.typeId == TileMapNode do return cast(^TileMapNode)p
	return nil
}

// LevelGeneratorNode_Generating: a background generation is running
// (chunked: chunks are being made).
LevelGeneratorNode_Generating :: proc(lg: ^LevelGeneratorNode) -> bool {
	return lg.job != nil || (lg.world != nil && len(lg.world.jobs) > 0)
}

// LevelGeneratorNode_SetParam sets a parameter of the generator's node `id`
// for this node's levels (the next generation).
LevelGeneratorNode_SetParam :: proc(lg: ^LevelGeneratorNode, id: int, name: string, value: f64) {
	for &p in lg.params do if p.node == id && p.name == name {
		p.value = value
		return
	}
	append(&lg.params, Gen_Param_Override{id, strings.clone(name, lg.allocator), value})
}

// LevelGeneratorNode_Param: a parameter set on the node (ok false: not set,
// the generator's own applies).
LevelGeneratorNode_Param :: proc(lg: ^LevelGeneratorNode, id: int, name: string) -> (value: f64, ok: bool) {
	for p in lg.params do if p.node == id && p.name == name do return p.value, true
	return 0, false
}

// LevelGeneratorNode_ClearParam drops one (name "": every one of node id;
// id 0: all).
LevelGeneratorNode_ClearParam :: proc(lg: ^LevelGeneratorNode, id := 0, name := "") {
	#reverse for p, i in lg.params {
		if (id == 0 || p.node == id) && (name == "" || p.name == name) {
			delete(p.name, lg.allocator)
			ordered_remove(&lg.params, i)
		}
	}
}

@(private = "file")
levelgen_scene :: proc(ctx: ^GameContext) -> ^Scene {
	if ctx == nil do return nil
	if ctx.scene != nil do return ctx.scene
	return ctx.game.sceneManager.currentScene if ctx.game != nil else nil
}

@(private = "file")
levelgen_failed :: proc(lg: ^LevelGeneratorNode, why: string, ctx: ^GameContext) -> bool {
	log.warnf("%s: %s", lg.name, why)
	lg.onFailed->notify(lg, why, ctx)
	return false
}

@(private = "file")
levelgen_apply :: proc(lg: ^LevelGeneratorNode, r: ^Gen_Result, seed: u64, ctx: ^GameContext, scene: ^Scene = nil) -> string {
	tm := LevelGeneratorNode_Target(lg, ctx, scene)
	if tm == nil {
		levelgen_failed(lg, "its TileMap is gone", ctx)
		return "its TileMap is gone"
	}
	sc := scene if scene != nil else levelgen_scene(ctx)
	if err := Gen_ApplyResult(r, tm, ctx, sc); err != "" {
		levelgen_failed(lg, err, ctx)
		return err
	}
	lg.lastSeed = int(seed)
	if lg.rebakeNavigation do LevelGeneratorNode_RebakeNavigation(sc, ctx)
	levelgen_progress(lg, 1, ctx)
	lg.onGenerated->notify(lg, int(seed), ctx)
	if ctx != nil && ctx.game != nil do EventBus_Publish(&ctx.game.events, "level_generated", tm.name, tm)
	return ""
}

// LevelGeneratorNode_RebakeNavigation bakes the scene's Navigation Regions
// again (after a level went in: its tiles, colliders and spawned nodes in
// place - the queues are processed and the positions composed first).
// Returns how many it baked.
LevelGeneratorNode_RebakeNavigation :: proc(sc: ^Scene, ctx: ^GameContext) -> int {
	if sc == nil || sc.manager == nil do return 0
	c: GameContext
	if ctx != nil {
		ProcessNodeQueues(sc.manager, ctx)
		c = ctx^
	}
	c.scene = sc // (the regions read this scene's nodes)
	Node_SetGlobalPositions(sc.manager, sc.rootNode)
	baked := 0
	for n in sc.manager.navRegions {
		if n == nil || !n.enabled || n.removing do continue
		NavRegion_Bake(cast(^NavigationRegionNode)n, &c)
		baked += 1
	}
	return baked
}

// levelgen_progress: the progress now; "generation_progress" when it moved
// by 1% or more since the last one emitted, or reached 1.
@(private = "file")
levelgen_progress :: proc(lg: ^LevelGeneratorNode, value: f32, ctx: ^GameContext) {
	v := clamp(value, lg.progress, 1) // (it only grows)
	lg.progress = v
	if v - lg.progressSent >= 0.01 || (v >= 1 && lg.progressSent < 1) {
		lg.progressSent = v
		lg.onProgress->notify(lg, f64(v), ctx)
	}
}

// levelgen_generate: the level for a seed; one the generator refuses is
// tried again with the next seeds (each made from the last), `attempts` in
// all. The seed of the level made; the last error when none was.
// `progress`: follows it (each attempt Gen_ProgressAttempt).
@(private = "file")
levelgen_generate :: proc(g: ^Gen_Graph, seed: u64, attempts: int, allocator := context.allocator, progress: ^Gen_Progress = nil) -> (r: Gen_Result, used: u64, err: string) {
	used = seed
	needed := Gen_NeededNodes(g) if progress != nil else 0
	for i in 0 ..< max(attempts, 1) {
		if progress != nil do Gen_ProgressAttempt(progress, needed, i == max(attempts, 1) - 1)
		r, err = Gen_Generate(g, used, allocator, progress)
		if err == "" do return
		used = 1 + gen_mix(used, u64(i) + 0xa77e) % (1 << 30)
	}
	if attempts > 1 do err = fmt.tprintf("%s (%d seeds tried)", err, attempts)
	return
}

// gen_job_run (worker): the graph -> tiles and entities. Touches only its job.
@(private = "file")
gen_job_run :: proc(t: ^thread.Thread) {
	context.allocator = Engine_HeapAllocator()
	j := cast(^Gen_Job)t.data
	r, used, err := levelgen_generate(&j.graph, j.seed, j.attempts, Engine_HeapAllocator(), &j.progress)
	j.seed = used
	if err != "" do j.err = strings.clone(err, Engine_HeapAllocator())
	else do j.result = r
	free_all(context.temp_allocator)
	sync.atomic_thread_fence(.Release)
}

@(private = "file")
gen_job_free :: proc(j: ^Gen_Job) {
	a := Engine_HeapAllocator()
	when ODIN_OS != .JS do if j.thread != nil do thread.destroy(j.thread) // (joins)
	Gen_ResultDestroy(&j.result, a)
	Gen_GraphDestroy(&j.graph)
	delete(j.err, a)
	free(j, a)
}

// --- chunked (#171) --------------------------------------------------------------------

// GEN_CHUNKS_PER_FRAME: finished chunks put in per frame at most (each is
// well under a millisecond; a burst waits for the next frames).
GEN_CHUNKS_PER_FRAME :: 4

// levelgen_chunks_start: a chunked level - the generator read once (the
// workers share it), the maps made endless and emptied, the chunks around
// the camera made: at once with `background` off (or on the web), else on
// worker threads from the next update.
@(private = "file")
levelgen_chunks_start :: proc(lg: ^LevelGeneratorNode, ctx: ^GameContext, seed: int, scene: ^Scene) -> (ok: bool, why: string) {
	if lg.generator == "" do return levelgen_failed(lg, "pick its generator (a .levelgen.json)", ctx), "pick its generator (a .levelgen.json)"
	sc := scene if scene != nil else levelgen_scene(ctx)
	tm := LevelGeneratorNode_Target(lg, ctx, scene)
	if tm == nil || sc == nil do return levelgen_failed(lg, "no TileMap to fill (set Tile Map, or add one as a child)", ctx), "no TileMap to fill (set Tile Map, or add one as a child)"
	s := seed
	if s == 0 do s = lg.seed
	if s == 0 && lg.randomSeed do s = 1 + int(rand.int31_max(1 << 30))
	g, err := Gen_LoadFile(ctx, lg.generator, Engine_HeapAllocator())
	if err != "" do return levelgen_failed(lg, err, ctx), err
	g.layout, g.stagger = tm.layout, tm.stagger
	for p in lg.params do if n := Gen_FindNode(&g, p.node); n != nil do Gen_SetParam(n, p.name, p.value)
	levelgen_chunks_stop(lg, sc, ctx, true) // (the last level's chunks go)
	a := Engine_HeapAllocator()
	w := new(Gen_Chunk_World, a)
	w.graph = g
	w.seed = u64(s) if s != 0 else g.seed
	w.size = clamp(lg.chunkSize, 4, 256)
	info := Gen_ChunkInfo(&w.graph, context.temp_allocator)
	w.apron, w.unsafe = info.apron, len(info.unsafe)
	if w.unsafe > 0 do log.warnf("%s: %d node(s) of %s aren't chunk-safe - each chunk makes its own, with seams (the Level Generator window marks them)", lg.name, w.unsafe, lg.generator)
	w.chunks = make(map[[2]int]Gen_Chunk, a)
	w.jobs = make([dynamic]^Gen_Chunk_Job, a)
	w.maps = make([dynamic][2]u32, a)
	lg.world = w
	lg.lastSeed = int(w.seed)
	lg.progress, lg.progressSent = 0, 0
	lg.onProgress->notify(lg, f64(0), ctx)
	// The maps it fills: endless and empty; what the last level placed goes.
	levelgen_endless(w, tm, sc)
	for &n in w.graph.nodes do for name in Gen_OutputMaps(&n) do if m := Gen_LayerTileMap(tm, name); m != nil do levelgen_endless(w, m, sc)
	Node_SetGlobalPositions(sc.manager, sc.rootNode) // (the camera's place now)
	w.center = levelgen_chunk_center(lg, w, tm, sc)
	sync_ := !lg.background
	when ODIN_OS == .JS do sync_ = true
	if sync_ {
		for c in levelgen_wanted(w.center, clamp(lg.chunkRadius, 0, 16)) {
			r, gerr := Gen_GenerateChunk(&w.graph, w.seed, c, w.size, w.apron, context.temp_allocator)
			levelgen_chunk_in(lg, w, c, &r, gerr, tm, sc, ctx)
		}
		levelgen_chunks_progress(lg, w, ctx, sc)
	}
	return true, ""
}

// levelgen_endless: a map the chunks fill - endless, emptied, without the
// nodes the last level placed on it.
@(private = "file")
levelgen_endless :: proc(w: ^Gen_Chunk_World, m: ^TileMapNode, sc: ^Scene) {
	for h in w.maps do if Node_FromSlot(h[0], h[1]) == m do return
	slot, gen := Node_SlotOf(m)
	append(&w.maps, [2]u32{slot, gen})
	m.unbounded = true
	TileMapNode_Reset(m)
	TileMapNode_Changed(m)
	if m.staticBody != nil && Node_IsAlive(m.staticBody) do RemoveNode(sc.manager, m.staticBody)
	m.staticBody = nil
	for c in GetChildrenTemp(sc.manager, m) do if c != nil && !c.removing && Node_HasTag(c, GEN_ENTITY_TAG) do RemoveNode(sc.manager, c)
}

// levelgen_chunks_stop: the chunked level ends - workers joined, and with
// `removeNodes` its chunks' nodes taken out of the scene (not while the
// scene itself goes).
@(private = "file")
levelgen_chunks_stop :: proc(lg: ^LevelGeneratorNode, sc: ^Scene, ctx: ^GameContext, removeNodes: bool) {
	w := lg.world
	if w == nil do return
	for j in w.jobs do gen_chunk_job_free(j) // (waits for each)
	delete(w.jobs)
	for _, &ch in w.chunks {
		if removeNodes && sc != nil do for h in ch.nodes do if n := Node_FromSlot(h[0], h[1]); n != nil && !n.removing do RemoveNode(sc.manager, n)
		delete(ch.nodes)
	}
	delete(w.chunks)
	if removeNodes do for h in w.maps do if m := Node_FromSlot(h[0], h[1]); m != nil do (cast(^TileMapNode)m).unbounded = false
	delete(w.maps)
	Gen_GraphDestroy(&w.graph)
	free(w, Engine_HeapAllocator())
	lg.world = nil
	lg.loadedChunks = 0
}

// levelgen_chunks_update (each frame): finished chunks in, far ones out,
// missing ones started - nearest first.
@(private = "file")
levelgen_chunks_update :: proc(lg: ^LevelGeneratorNode, ctx: ^GameContext) {
	w := lg.world
	sc := levelgen_scene(ctx)
	tm := LevelGeneratorNode_Target(lg, ctx)
	if tm == nil || sc == nil do return
	w.center = levelgen_chunk_center(lg, w, tm, sc)
	r := clamp(lg.chunkRadius, 0, 16)
	applied := 0
	for i := 0; i < len(w.jobs); {
		j := w.jobs[i]
		when ODIN_OS != .JS {
			if !thread.is_done(j.thread) {
				i += 1
				continue
			}
		}
		if applied >= GEN_CHUNKS_PER_FRAME do break
		sync.atomic_thread_fence(.Acquire)
		ordered_remove(&w.jobs, i)
		if levelgen_cheb(j.coord, w.center) <= r + 1 { // (still near: else dropped)
			levelgen_chunk_in(lg, w, j.coord, &j.result, j.err, tm, sc, ctx)
			applied += 1
		}
		gen_chunk_job_free(j)
	}
	gone := make([dynamic][2]int, context.temp_allocator)
	for c in w.chunks do if levelgen_cheb(c, w.center) > r + 1 do append(&gone, c)
	for c in gone do levelgen_chunk_out(lg, w, c, sc, ctx)
	most := clamp(Engine_CoreCount() / 2, 1, 4)
	for c in levelgen_wanted(w.center, r) {
		if len(w.jobs) >= most do break
		if c in w.chunks do continue
		running := false
		for j in w.jobs do if j.coord == c do running = true
		if running do continue
		when ODIN_OS == .JS {
			// (No threads: one chunk a frame, here.)
			res, gerr := Gen_GenerateChunk(&w.graph, w.seed, c, w.size, w.apron, context.temp_allocator)
			levelgen_chunk_in(lg, w, c, &res, gerr, tm, sc, ctx)
			break
		} else {
			a := Engine_HeapAllocator()
			j := new(Gen_Chunk_Job, a)
			j.coord, j.graph, j.seed, j.size, j.apron = c, &w.graph, w.seed, w.size, w.apron
			j.thread = thread.create(gen_chunk_job_run)
			j.thread.data = j
			append(&w.jobs, j)
			thread.start(j.thread)
		}
	}
	levelgen_chunks_progress(lg, w, ctx, sc)
}

// levelgen_chunks_progress: `progress` - the chunks around the camera that
// are in - and, once they all are: the navigation baked again (if asked and
// chunks changed), "generated" the first time.
@(private = "file")
levelgen_chunks_progress :: proc(lg: ^LevelGeneratorNode, w: ^Gen_Chunk_World, ctx: ^GameContext, sc: ^Scene) {
	r := clamp(lg.chunkRadius, 0, 16)
	wanted := (2 * r + 1) * (2 * r + 1)
	have := 0
	for y in -r ..= r do for x in -r ..= r do if w.center + {x, y} in w.chunks do have += 1
	v := f32(have) / f32(wanted)
	lg.progress = v
	if abs(v - lg.progressSent) >= 0.01 || (v >= 1 && lg.progressSent < 1) {
		lg.progressSent = v
		lg.onProgress->notify(lg, f64(v), ctx)
	}
	if have < wanted do return
	if w.navDirty && lg.rebakeNavigation do LevelGeneratorNode_RebakeNavigation(sc, ctx)
	w.navDirty = false
	if w.done do return
	w.done = true
	lg.onGenerated->notify(lg, int(w.seed), ctx)
	if ctx != nil && ctx.game != nil {
		if tm := LevelGeneratorNode_Target(lg, ctx, sc); tm != nil do EventBus_Publish(&ctx.game.events, "level_generated", tm.name, tm)
	}
}

// levelgen_chunk_in puts a made chunk in: its tiles (the main map and the
// layers'), its colliders, components and entities - each a node it keeps
// to take out when the chunk goes. A chunk the generator refused stays
// empty (and isn't tried again while it is near).
@(private = "file")
levelgen_chunk_in :: proc(lg: ^LevelGeneratorNode, w: ^Gen_Chunk_World, c: [2]int, r: ^Gen_Result, err: string, tm: ^TileMapNode, sc: ^Scene, ctx: ^GameContext) {
	if err != "" {
		w.chunks[c] = Gen_Chunk{failed = true}
		lg.loadedChunks = len(w.chunks)
		levelgen_failed(lg, fmt.tprintf("chunk %d, %d: %s", c.x, c.y, err), ctx)
		return
	}
	ch := Gen_Chunk{nodes = make([dynamic][2]u32, Engine_HeapAllocator())}
	keep :: proc(ch: ^Gen_Chunk, n: ^Node) {
		if n == nil do return
		slot, gen := Node_SlotOf(n)
		append(&ch.nodes, [2]u32{slot, gen})
	}
	origin := c * w.size
	size := [2]int{w.size, w.size}
	fill :: proc(w: ^Gen_Chunk_World, m: ^TileMapNode, c, origin, size: [2]int, tiles: []i32, ch: ^Gen_Chunk, ctx: ^GameContext) {
		levelgen_fit(w, m, c)
		TileMapNode_SetBlock(m, origin, size, tiles)
		if m.solid && m.isReady && ctx != nil do keep(ch, TileMapNode_BuildCollidersIn(m, origin, origin + size, ctx))
	}
	if r.tiles != nil do fill(w, tm, c, origin, size, r.tiles, &ch, ctx)
	for ly in r.layers {
		m := Gen_LayerTileMap(tm, ly.name)
		if m == nil do continue
		levelgen_endless(w, m, sc) // (a layer map added since: endless too)
		fill(w, m, c, origin, size, ly.tiles, &ch, ctx)
	}
	// Components, by map (cells inside the chunk).
	if len(r.components) > 0 {
		Group :: struct {target: ^TileMapNode, items: [dynamic]Tile_Component_Place}
		groups := make([dynamic]Group, context.temp_allocator)
		for pc in r.components {
			target := tm if pc.layer == "" else Gen_LayerTileMap(tm, pc.layer)
			if target == nil do continue
			gi := -1
			for gr, i in groups do if gr.target == target do gi = i
			if gi < 0 {
				append(&groups, Group{target, make([dynamic]Tile_Component_Place, context.temp_allocator)})
				gi = len(groups) - 1
			}
			append(&groups[gi].items, Tile_Component_Place{pc.component, origin + pc.cell})
		}
		for gr in groups {
			placed, _ := TileMapNode_PlaceComponents(gr.target, gr.items[:], sc, ctx, {origin.x, origin.y, origin.x + size.x, origin.y + size.y})
			for n in placed {
				Node_AddTag(n, GEN_ENTITY_TAG)
				keep(&ch, n)
			}
		}
	}
	for en in r.entities {
		n := Scene_InstantiateComponent(sc, en.component, tm, ctx)
		if n == nil do continue
		n.position = TileMapNode_CellLocalCenter(tm, origin + en.cell)
		Node_AddTag(n, GEN_ENTITY_TAG)
		keep(&ch, n)
	}
	w.chunks[c] = ch
	w.navDirty = true
	lg.loadedChunks = len(w.chunks)
	lg.onChunkGenerated->notify(lg, [2]f32{f32(c.x), f32(c.y)}, ctx)
}

// levelgen_chunk_out takes a chunk out: its cells emptied on every map,
// the nodes it placed removed.
@(private = "file")
levelgen_chunk_out :: proc(lg: ^LevelGeneratorNode, w: ^Gen_Chunk_World, c: [2]int, sc: ^Scene, ctx: ^GameContext) {
	ch, ok := w.chunks[c]
	if !ok do return
	for h in w.maps do if m := Node_FromSlot(h[0], h[1]); m != nil do TileMapNode_SetBlock(cast(^TileMapNode)m, c * w.size, {w.size, w.size}, nil)
	for h in ch.nodes do if n := Node_FromSlot(h[0], h[1]); n != nil && !n.removing do RemoveNode(sc.manager, n)
	delete(ch.nodes)
	delete_key(&w.chunks, c)
	w.navDirty = true
	lg.loadedChunks = len(w.chunks)
	lg.onChunkUnloaded->notify(lg, [2]f32{f32(c.x), f32(c.y)}, ctx)
}

// levelgen_fit: a map's storage covers chunk c - laid out again over the
// chunks in (and c) when it doesn't, so it never grows past what is in.
@(private = "file")
levelgen_fit :: proc(w: ^Gen_Chunk_World, m: ^TileMapNode, c: [2]int) {
	lo, hi := c * w.size, (c + 1) * w.size
	slo, shi := m.dataOrigin, m.dataOrigin + m.dataSize
	if len(m.tiles) > 0 && lo.x >= slo.x && lo.y >= slo.y && hi.x <= shi.x && hi.y <= shi.y do return
	for k in w.chunks {
		lo = {min(lo.x, k.x * w.size), min(lo.y, k.y * w.size)}
		hi = {max(hi.x, (k.x + 1) * w.size), max(hi.y, (k.y + 1) * w.size)}
	}
	TileMapNode_FitStorage(m, lo, hi)
}

// levelgen_chunk_center: the chunk the camera is over (where it was when
// there is none to follow).
@(private = "file")
levelgen_chunk_center :: proc(lg: ^LevelGeneratorNode, w: ^Gen_Chunk_World, tm: ^TileMapNode, sc: ^Scene) -> [2]int {
	n: ^Node
	if lg.cameraPath != "" do n = Node_ResolvePath(sc.manager, lg, lg.cameraPath)
	else if sc.camera != nil do n = sc.camera
	if n == nil || n.removing do return w.center
	p := n.globalPosition
	if n.typeId == CameraNode {
		cam := cast(^CameraNode)n
		p = cam.currentPosition + cam.currentOffset if cam.currentPosition != {} else CameraNode_ViewCenter(cam)
	}
	return Gen_ChunkOf(TileMapNode_CellAt(tm, p), w.size)
}

// levelgen_wanted: the chunks within r of the centre, nearest first (temp).
@(private = "file")
levelgen_wanted :: proc(center: [2]int, r: int) -> [][2]int {
	out := make([dynamic][2]int, 0, (2 * r + 1) * (2 * r + 1), context.temp_allocator)
	for y in -r ..= r do for x in -r ..= r do append(&out, [2]int{x, y}) // (offsets: sorted by distance)
	slice.stable_sort_by(out[:], proc(a, b: [2]int) -> bool {return a.x * a.x + a.y * a.y < b.x * b.x + b.y * b.y})
	for &c in out do c += center
	return out[:]
}

@(private = "file")
levelgen_cheb :: proc(a, b: [2]int) -> int {return max(abs(a.x - b.x), abs(a.y - b.y))}

// gen_chunk_job_run (worker): one chunk from the shared graph (read only).
@(private = "file")
gen_chunk_job_run :: proc(t: ^thread.Thread) {
	context.allocator = Engine_HeapAllocator()
	j := cast(^Gen_Chunk_Job)t.data
	r, err := Gen_GenerateChunk(j.graph, j.seed, j.coord, j.size, j.apron, Engine_HeapAllocator())
	if err != "" do j.err = strings.clone(err, Engine_HeapAllocator())
	else do j.result = r
	free_all(context.temp_allocator)
	sync.atomic_thread_fence(.Release)
}

@(private = "file")
gen_chunk_job_free :: proc(j: ^Gen_Chunk_Job) {
	a := Engine_HeapAllocator()
	when ODIN_OS != .JS do if j.thread != nil do thread.destroy(j.thread) // (joins)
	Gen_ResultDestroy(&j.result, a)
	delete(j.err, a)
	free(j, a)
}

// LevelGeneratorNode_ChunkLoaded: chunk c is in (chunked).
LevelGeneratorNode_ChunkLoaded :: proc(lg: ^LevelGeneratorNode, c: [2]int) -> bool {
	return lg.world != nil && c in lg.world.chunks
}

// LevelGeneratorNode_LoadedChunks: the chunks in (temp; any order).
LevelGeneratorNode_LoadedChunks :: proc(lg: ^LevelGeneratorNode, allocator := context.temp_allocator) -> [][2]int {
	out := make([dynamic][2]int, allocator)
	if lg.world != nil do for c in lg.world.chunks do append(&out, c)
	return out[:]
}

// LevelGeneratorNode_ChunkAt: the chunk holding a world position (its map's
// cell there; chunked, or with its Chunk Size).
LevelGeneratorNode_ChunkAt :: proc(lg: ^LevelGeneratorNode, world: [2]f32, ctx: ^GameContext = nil) -> (c: [2]int, ok: bool) {
	tm := LevelGeneratorNode_Target(lg, ctx)
	if tm == nil do return {}, false
	size := lg.world.size if lg.world != nil else clamp(lg.chunkSize, 4, 256)
	return Gen_ChunkOf(TileMapNode_CellAt(tm, world), size), true
}

// --- Lua ------------------------------------------------------------------------------
// generator:generate([seed]) -> ok, why (background: true when started)
// generator:is_generating() -> bool
// generator:set_level_param(node_id, name, value) / generator:level_param(node_id, name) -> number|nil
// generator:clear_level_params([node_id [, name]])
// generator:levelgen_loaded_chunks() -> {Vec2, ...}   generator:levelgen_is_chunk_loaded(x, y) -> bool
// generator:levelgen_chunk_at(wx, wy) -> x, y (chunked, #171)

@(private = "file")
lua_levelgen_arg :: proc(L: ^lua.State) -> ^LevelGeneratorNode {
	n, ok := to_node_userdata(L, 1)
	if !ok || n.typeId != LevelGeneratorNode do return nil
	return cast(^LevelGeneratorNode)n
}

@(private = "file")
lua_generate :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	lg := lua_levelgen_arg(L)
	if lg == nil {
		lua.pushboolean(L, false)
		lua.pushstring(L, "not a LevelGenerator node")
		return 2
	}
	seed := int(lua.tointeger(L, 2)) if lua.type(L, 2) == .NUMBER else 0
	ok, why := LevelGeneratorNode_Generate(lg, lg.gameContext, seed)
	lua.pushboolean(L, b32(ok))
	if ok do return 1
	lua.pushstring(L, strings.clone_to_cstring(why, context.temp_allocator))
	return 2
}

@(private = "file")
lua_is_generating :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	lg := lua_levelgen_arg(L)
	lua.pushboolean(L, b32(lg != nil && LevelGeneratorNode_Generating(lg)))
	return 1
}

@(private = "file")
lua_set_level_param :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	lg := lua_levelgen_arg(L)
	if lg == nil || lua.type(L, 2) != .NUMBER || lua.type(L, 3) != .STRING do return 0
	value: f64
	#partial switch lua.type(L, 4) {
	case .NUMBER: value = f64(lua.tonumber(L, 4))
	case .BOOLEAN: value = 1 if lua.toboolean(L, 4) else 0
	case: return 0
	}
	LevelGeneratorNode_SetParam(lg, int(lua.tointeger(L, 2)), string(lua.tostring(L, 3)), value)
	return 0
}

@(private = "file")
lua_level_param :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	lg := lua_levelgen_arg(L)
	if lg != nil && lua.type(L, 2) == .NUMBER && lua.type(L, 3) == .STRING {
		if v, ok := LevelGeneratorNode_Param(lg, int(lua.tointeger(L, 2)), string(lua.tostring(L, 3))); ok {
			lua.pushnumber(L, lua.Number(v))
			return 1
		}
	}
	lua.pushnil(L)
	return 1
}

@(private = "file")
lua_clear_level_params :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if lg := lua_levelgen_arg(L); lg != nil {
		id := int(lua.tointeger(L, 2)) if lua.type(L, 2) == .NUMBER else 0
		name := strings.clone(string(lua.tostring(L, 3)), context.temp_allocator) if lua.type(L, 3) == .STRING else ""
		LevelGeneratorNode_ClearParam(lg, id, name)
	}
	return 0
}

@(private = "file")
lua_loaded_chunks :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	lg := lua_levelgen_arg(L)
	chunks := LevelGeneratorNode_LoadedChunks(lg) if lg != nil else nil
	slice.sort_by(chunks, proc(a, b: [2]int) -> bool {return a.y < b.y || (a.y == b.y && a.x < b.x)}) // (row by row)
	lua.createtable(L, c.int(len(chunks)), 0)
	for ch, i in chunks {
		Lua_PushVec2(L, {f32(ch.x), f32(ch.y)})
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

@(private = "file")
lua_is_chunk_loaded :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	lg := lua_levelgen_arg(L)
	lua.pushboolean(L, b32(lg != nil && LevelGeneratorNode_ChunkLoaded(lg, {int(lua.tointeger(L, 2)), int(lua.tointeger(L, 3))})))
	return 1
}

@(private = "file")
lua_chunk_at :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	lg := lua_levelgen_arg(L)
	if lg == nil do return 0
	ch, ok := LevelGeneratorNode_ChunkAt(lg, {f32(lua.tonumber(L, 2)), f32(lua.tonumber(L, 3))}, lg.gameContext)
	if !ok do return 0
	lua.pushinteger(L, lua.Integer(ch.x))
	lua.pushinteger(L, lua.Integer(ch.y))
	return 2
}

// Script_RegisterLevelGeneratorBindings adds the generator's methods to the
// node metatable (on the stack).
Script_RegisterLevelGeneratorBindings :: proc(L: ^lua.State) {
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "levelgen_generate", lua_generate)
	Lua_SetDeprecated(L, lua_generate, "generate", "levelgen_generate")
	reg(L, "levelgen_is_generating", lua_is_generating)
	Lua_SetDeprecated(L, lua_is_generating, "is_generating", "levelgen_is_generating")
	reg(L, "levelgen_set_param", lua_set_level_param)
	Lua_SetDeprecated(L, lua_set_level_param, "set_level_param", "levelgen_set_param")
	reg(L, "levelgen_get_param", lua_level_param)
	Lua_SetDeprecated(L, lua_level_param, "level_param", "levelgen_get_param")
	reg(L, "levelgen_clear_params", lua_clear_level_params)
	Lua_SetDeprecated(L, lua_clear_level_params, "clear_level_params", "levelgen_clear_params")
	reg(L, "levelgen_loaded_chunks", lua_loaded_chunks)
	reg(L, "levelgen_is_chunk_loaded", lua_is_chunk_loaded)
	reg(L, "levelgen_chunk_at", lua_chunk_at)
}
