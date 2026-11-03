package engine

import "core:c"
import "core:fmt"
import "core:log"
import "core:math/rand"
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
	params:          [dynamic]Gen_Param_Override, // (node arena)
	// Runtime.
	lastSeed:        int `gui:"true" save:"false"`,
	progress:        f32 `gui:"true" save:"false"`, // 0..1: the generation's (1: the level is in)
	progressSent:    f32, // the last "generation_progress" emitted
	started:         bool, // the first update ran (generateOnReady)
	job:             ^Gen_Job, // a background generation in flight (heap)
	onGenerated:     EventSubject, // "generated" (the seed)
	onFailed:        EventSubject, // "generation_failed" (why)
	onProgress:      EventSubject, // "generation_progress" (0..1)
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
	lg.params = make([dynamic]Gen_Param_Override, lg.allocator)
	lg.update = LevelGeneratorNode_Update
	lg.onDestroy = LevelGeneratorNode_Destroy
	InitializeSubject(&lg.onGenerated, "generated", lg)
	InitializeSubject(&lg.onFailed, "generation_failed", lg)
	InitializeSubject(&lg.onProgress, "generation_progress", lg)
	scene->addNode(lg, parent)
	return lg
}

LevelGeneratorNode_Destroy :: proc(node: ^Node, ctx: ^GameContext) {
	lg := cast(^LevelGeneratorNode)node
	if lg.job != nil do gen_job_free(lg.job) // (waits for the worker)
	lg.job = nil
	DestroySubject(&lg.onGenerated)
	DestroySubject(&lg.onFailed)
	DestroySubject(&lg.onProgress)
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

// LevelGeneratorNode_Generating: a background generation is running.
LevelGeneratorNode_Generating :: proc(lg: ^LevelGeneratorNode) -> bool {return lg.job != nil}

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

// --- Lua ------------------------------------------------------------------------------
// generator:generate([seed]) -> ok, why (background: true when started)
// generator:is_generating() -> bool
// generator:set_level_param(node_id, name, value) / generator:level_param(node_id, name) -> number|nil
// generator:clear_level_params([node_id [, name]])

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
}
