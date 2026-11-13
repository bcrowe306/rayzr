package engine

import "core:c"
import "core:math"
import "core:math/rand"
import "core:strings"
import lua "lua54"
import rl "vendor:raylib"

// ============================================================================
// SpawnerNode: spawns components (.component.json) into the scene - one,
// all, a random (weighted) pick, the next in order, or a shuffle bag of its
// list - where it is: a spawned root starts at the spawner's world position
// (+ offsets), rotation and scale. The spawner is an ordinary child, so it
// follows its parent: on a player it fires from the player's hand.
//
// - Where the spawned nodes go: the scene's root (default: a fireball
//   doesn't follow the player once fired), the spawner's parent, the
//   spawner itself, or a node path.
// - Spawning: spawn() from Lua / Odin, a signal connection to the method
//   `spawn` (the Inspector's Signals: no script needed), or by itself every
//   `interval` seconds (+ random `intervalJitter`) after `startDelay`.
//   `count` per spawn (a burst), `chance` of each happening, `cooldown`
//   between spawns, `maxAlive` spawned at once and `totalLimit` ever (0 = no
//   cap). `spread` (degrees) and `jitter` (px) randomise the direction and
//   place; `speed` sets a dynamic / kinematic body root's velocity along
//   the spawner's facing.
// - `usePool`: instances come from the scene's pool for the component
//   (node_pool.odin) and go back to it when destroyed.
// - Events: "spawned" (the new root), "limit_reached" (totalLimit hit),
//   "list_finished" (Sequential with Stop: the last entry was spawned).
//
// The list is saved as "spawner": {"entries": [{"component", "weight",
// "count", "offset"}]} next to the reflected properties.
// ============================================================================

Spawn_Mode :: enum u8 {
	Single,     // the first entry (or the one asked for)
	All,        // every entry
	Random,     // one, picked by weight
	Sequential, // the next one each time
	Shuffle,    // random, every entry once before any repeats
}

Spawn_Sequence_End :: enum u8 {
	Loop,      // back to the first
	Ping_Pong, // back down the list, then up again
	Stop,      // no more spawns (spawn_reset() starts again)
}

Spawn_Parent :: enum u8 {
	Scene_Root,     // stays where it was spawned
	Spawner_Parent, // moves with what the spawner is on
	Spawner,        // moves with the spawner
	Node_Path,      // the node at parentPath (from the spawner)
}

Spawn_Entry :: struct {
	component: string, // project path (node arena)
	weight:    f32,    // Random: how likely (relative)
	count:     int,    // spawned each time this entry is picked
	offset:    [2]f32, // local to the spawner, added to its offset
}

SpawnerNode :: struct {
	using node: Node,
	mode:            Spawn_Mode `gui:"true"`,
	sequenceEnd:     Spawn_Sequence_End `gui:"true"`,
	count:           int `gui:"true" min:"1" max:"100"`,
	parentMode:      Spawn_Parent `gui:"true"`,
	parentPath:      string `gui:"true"`,
	offset:          [2]f32 `gui:"true" min:"-4096" max:"4096"`,
	inheritRotation: bool `gui:"true"`,
	inheritScale:    bool `gui:"true"`,
	spread:          f32 `gui:"true" min:"0" max:"360"`,
	jitter:          [2]f32 `gui:"true" min:"0" max:"4096"`,
	speed:           f32 `gui:"true" min:"0" max:"10000"`,
	autoSpawn:       bool `gui:"true"`,
	startDelay:      f32 `gui:"true" min:"0" max:"3600"`,
	interval:        f32 `gui:"true" min:"0" max:"3600"`,
	intervalJitter:  f32 `gui:"true" min:"0" max:"3600"`,
	cooldown:        f32 `gui:"true" min:"0" max:"3600"`,
	chance:          f32 `gui:"true" min:"0" max:"1"`,
	maxAlive:        int `gui:"true" min:"0" max:"10000"`,
	totalLimit:      int `gui:"true" min:"0" max:"100000"`,
	usePool:         bool `gui:"true"`,
	entries:         [dynamic]Spawn_Entry, // (node arena)
	// Runtime.
	spawnedTotal:    int `gui:"true" save:"false"`, // spawned so far (spawn_reset() zeroes it)
	next:            int,    // Sequential: the next entry
	step:            int,    // Sequential Ping_Pong: +1 / -1
	finished:        bool,   // Sequential Stop: the list is done
	bag:             [dynamic]int, // Shuffle: the entries left this round (heap)
	timer:           f32,    // seconds to the next automatic spawn
	cooldownLeft:    f32,
	alive:           [dynamic][3]u32, // the spawned roots' live slots and their entry (heap; Node_SlotOf, 0-based index)
	callbackRef:     i32,    // set_spawn_callback's function (Lua registry; 0 = none) - #231
	started:         bool,
	onSpawned:       EventSubject, // "spawned" (the new root)
	onLimit:         EventSubject, // "limit_reached"
	onFinished:      EventSubject, // "list_finished"
}

SpawnerNode_Create :: proc(scene: ^Scene, name: string = "Spawner", parent: ^Node = nil) -> ^SpawnerNode {
	s := CreateNode(scene.manager, SpawnerNode)
	s.name = strings.clone(name, s.allocator)
	s.count = 1
	s.inheritRotation = true
	s.interval = 1
	s.chance = 1
	s.step = 1
	s.entries = make([dynamic]Spawn_Entry, s.allocator)
	s.bag = make([dynamic]int, Engine_HeapAllocator())
	s.alive = make([dynamic][3]u32, Engine_HeapAllocator())
	s.renderable = true // (the editor draws its marker; nothing in the game)
	s.update = SpawnerNode_Update
	s.drawBounds = SpawnerNode_DrawBounds
	s.onDestroy = SpawnerNode_Destroy
	InitializeSubject(&s.onSpawned, "spawned", s)
	InitializeSubject(&s.onLimit, "limit_reached", s)
	InitializeSubject(&s.onFinished, "list_finished", s)
	scene->addNode(s, parent)
	return s
}

SpawnerNode_Destroy :: proc(node: ^Node, ctx: ^GameContext) {
	s := cast(^SpawnerNode)node
	DestroySubject(&s.onSpawned)
	DestroySubject(&s.onLimit)
	DestroySubject(&s.onFinished)
	delete(s.bag)
	delete(s.alive)
	if s.callbackRef != 0 && ctx != nil && ctx.scriptManager != nil && ctx.scriptManager.L != nil {
		lua.L_unref(ctx.scriptManager.L, lua.REGISTRYINDEX, s.callbackRef)
		s.callbackRef = 0
	}
}

// SpawnerNode_SpawnInfo: which list entry (0-based) a node it spawned and
// that's still alive came from (#231).
SpawnerNode_SpawnInfo :: proc(s: ^SpawnerNode, n: ^Node) -> (index: int, ok: bool) {
	slot, gen := Node_SlotOf(n)
	SpawnerNode_AliveCount(s) // (drops the gone)
	for a in s.alive do if a[0] == slot && a[1] == gen && slot != 0 do return int(a[2]), true
	return -1, false
}

// SpawnerNode_AddEntry appends a component to the list.
SpawnerNode_AddEntry :: proc(s: ^SpawnerNode, component: string, weight: f32 = 1, count := 1, offset := [2]f32{}) {
	append(&s.entries, Spawn_Entry{strings.clone(component, s.allocator), weight, max(count, 1), offset})
	clear(&s.bag)
}

// SpawnerNode_RemoveEntry drops the entry at i (0-based).
SpawnerNode_RemoveEntry :: proc(s: ^SpawnerNode, i: int) {
	if i < 0 || i >= len(s.entries) do return
	delete(s.entries[i].component, s.allocator)
	ordered_remove(&s.entries, i)
	clear(&s.bag)
	if s.next >= len(s.entries) do s.next = 0
}

// SpawnerNode_Reset starts the list, the limits and the timer again.
SpawnerNode_Reset :: proc(s: ^SpawnerNode) {
	s.spawnedTotal = 0
	s.next = 0
	s.step = 1
	s.finished = false
	s.cooldownLeft = 0
	s.started = false
	clear(&s.bag)
}

// SpawnerNode_AliveCount: how many of what it spawned are still in the
// scene (pooled ones: until they go back to their pool).
SpawnerNode_AliveCount :: proc(s: ^SpawnerNode) -> int {
	for i := len(s.alive) - 1; i >= 0; i -= 1 {
		n := Node_FromSlot(s.alive[i][0], s.alive[i][1])
		if n == nil || n.removing || (n.pool != nil && !n.enabled) do unordered_remove(&s.alive, i)
	}
	return len(s.alive)
}

SpawnerNode_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	s := cast(^SpawnerNode)node
	if s.cooldownLeft > 0 do s.cooldownLeft = max(s.cooldownLeft - dt, 0)
	if !s.autoSpawn do return
	if !s.started {
		s.started = true
		s.timer = s.startDelay
	}
	s.timer -= dt
	if s.timer > 0 do return
	SpawnerNode_Spawn(s, ctx)
	s.timer += max(s.interval + rand.float32() * s.intervalJitter, 0.01)
	if s.timer <= 0 do s.timer = max(s.interval, 0.01) // (a long frame: don't burst)
}

// SpawnerNode_Spawn spawns as the mode says (`index` >= 0: that entry,
// whatever the mode). Returns the roots spawned (temp), none when held back
// (cooldown, limits, chance, nothing in the list).
SpawnerNode_Spawn :: proc(s: ^SpawnerNode, ctx: ^GameContext, index := -1) -> []^Node {
	out := make([dynamic]^Node, context.temp_allocator)
	if len(s.entries) == 0 || s.cooldownLeft > 0 || s.removing do return out[:]
	if index < 0 && s.mode == .Sequential && s.finished do return out[:]
	if s.chance < 1 && rand.float32() >= s.chance do return out[:]
	picks := make([dynamic]int, context.temp_allocator)
	for _ in 0 ..< max(s.count, 1) {
		if index >= 0 {
			if index < len(s.entries) do append(&picks, index)
			continue
		}
		switch s.mode {
		case .Single: append(&picks, 0)
		case .All: for i in 0 ..< len(s.entries) do append(&picks, i)
		case .Random: append(&picks, spawner_pick_weighted(s))
		case .Sequential:
			if s.finished do break
			append(&picks, s.next)
			spawner_advance(s)
		case .Shuffle:
			if len(s.bag) == 0 {
				for i in 0 ..< len(s.entries) do append(&s.bag, i)
				rand.shuffle(s.bag[:])
			}
			append(&picks, pop(&s.bag))
		}
	}
	for i in picks {
		en := s.entries[i]
		for _ in 0 ..< max(en.count, 1) {
			if s.maxAlive > 0 && SpawnerNode_AliveCount(s) >= s.maxAlive do break
			if s.totalLimit > 0 && s.spawnedTotal >= s.totalLimit {
				s.onLimit->notify(s, nil, ctx)
				return out[:]
			}
			if n := spawner_spawn_one(s, en, i, ctx); n != nil {
				append(&out, n)
				s.spawnedTotal += 1
			}
		}
	}
	if len(out) > 0 do s.cooldownLeft = s.cooldown
	if s.mode == .Sequential && s.finished && index < 0 && len(out) > 0 do s.onFinished->notify(s, nil, ctx)
	if s.totalLimit > 0 && s.spawnedTotal >= s.totalLimit && len(out) > 0 do s.onLimit->notify(s, nil, ctx)
	return out[:]
}

@(private = "file")
spawner_pick_weighted :: proc(s: ^SpawnerNode) -> int {
	total: f32 = 0
	for en in s.entries do total += max(en.weight, 0)
	if total <= 0 do return rand.int_max(len(s.entries))
	r := rand.float32() * total
	for en, i in s.entries {
		r -= max(en.weight, 0)
		if r < 0 do return i
	}
	return len(s.entries) - 1
}

// spawner_advance moves Sequential's `next` past the entry just used.
@(private = "file")
spawner_advance :: proc(s: ^SpawnerNode) {
	n := len(s.entries)
	switch s.sequenceEnd {
	case .Loop:
		s.next = (s.next + 1) % n
	case .Ping_Pong:
		if n == 1 do return
		if s.next + s.step < 0 || s.next + s.step >= n do s.step = -s.step
		s.next += s.step
	case .Stop:
		s.next += 1
		if s.next >= n {
			s.next = n - 1
			s.finished = true
		}
	}
}

// spawner_world: a node's world transform from its parent chain (up to date
// even before this frame's transforms ran - spawning in ready()).
@(private = "file")
spawner_world :: proc(m: ^NodeManager, node: ^Node) -> (pos: [2]f32, scl: [2]f32, rot: f32) {
	chain := make([dynamic]^Node, context.temp_allocator)
	for n := node; n != nil; n = GetParent(m, n) do append(&chain, n)
	scl = {1, 1}
	#reverse for n in chain {
		pos = pos + rotate_vec(n.position * scl, rot)
		scl *= n.scale
		rot += n.rotation
	}
	return
}

@(private = "file")
spawner_parent :: proc(s: ^SpawnerNode, scene: ^Scene) -> ^Node {
	switch s.parentMode {
	case .Scene_Root: return scene.rootNode
	case .Spawner_Parent:
		if p := GetParent(scene.manager, s); p != nil do return p
	case .Spawner: return s
	case .Node_Path:
		if s.parentPath != "" do if p := Node_ResolvePath(scene.manager, s, s.parentPath); p != nil do return p
	}
	return scene.rootNode
}

@(private = "file")
spawner_spawn_one :: proc(s: ^SpawnerNode, en: Spawn_Entry, entry: int, ctx: ^GameContext) -> ^Node {
	scene := spawner_scene(ctx)
	if scene == nil || en.component == "" do return nil
	parent := spawner_parent(s, scene)

	// Where: the spawner's world transform, its offsets (local to it, so
	// they turn and flip with it), the random jitter and spread.
	wp, ws, wr := spawner_world(scene.manager, s)
	local := s.offset + en.offset
	if s.jitter != {} do local += {(rand.float32() * 2 - 1) * s.jitter.x, (rand.float32() * 2 - 1) * s.jitter.y}
	pos := wp + rotate_vec(local * ws, wr)
	rot := wr if s.inheritRotation else 0
	if s.spread > 0 do rot += (rand.float32() - 0.5) * s.spread
	scl := ws if s.inheritScale else [2]f32{1, 1}

	n: ^Node
	if s.usePool {
		n = Pool_Take(scene, Pool_Get(scene, en.component), parent, {}, ctx)
	} else {
		n = Scene_InstantiateComponent(scene, en.component, parent, ctx)
	}
	if n == nil do return nil
	// World -> the parent's space.
	pp, ps, pr := spawner_world(scene.manager, parent)
	safe := [2]f32{ps.x if ps.x != 0 else 1, ps.y if ps.y != 0 else 1}
	n.position = rotate_vec(pos - pp, -pr) / safe
	n.rotation = rot - pr
	n.scale = n.scale * scl / safe
	Node_SetGlobalPositions(scene.manager, n, pp, ps, pr) // (bodies are placed from it)

	// Velocity along the facing (flipped with a negative x scale).
	if s.speed > 0 {
		facing := f32(1) if ws.x >= 0 else -1
		r := math.to_radians(rot)
		v := [2]f32{math.cos(r), math.sin(r)} * facing * s.speed
		if n.typeId == DynamicBodyNode do (cast(^DynamicBodyNode)n).linearVelocity = v
		else if n.typeId == KinematicBodyNode do (cast(^KinematicBodyNode)n).linearVelocity = v
	}
	slot, gen := Node_SlotOf(n)
	if slot != 0 do append(&s.alive, [3]u32{slot, gen, u32(entry)})
	// Placed, before its ready() / on_spawn (its next update): the spawn
	// callback, then the signal - both can set it up (#231).
	spawner_call_back(s, n, entry, ctx)
	s.onSpawned->notify(s, n, ctx)
	return n
}

// push_spawn_info pushes {component = path, index = 1-based entry}.
@(private = "file")
push_spawn_info :: proc(L: ^lua.State, s: ^SpawnerNode, entry: int) {
	lua.createtable(L, 0, 2)
	comp := s.entries[entry].component if entry >= 0 && entry < len(s.entries) else ""
	lua.pushstring(L, strings.clone_to_cstring(comp, context.temp_allocator))
	lua.setfield(L, -2, "component")
	lua.pushinteger(L, lua.Integer(entry + 1))
	lua.setfield(L, -2, "index")
}

// spawner_call_back: set_spawn_callback's function(node, info, spawner).
@(private = "file")
spawner_call_back :: proc(s: ^SpawnerNode, n: ^Node, entry: int, ctx: ^GameContext) {
	if s.callbackRef == 0 || ctx == nil || ctx.scriptManager == nil || ctx.scriptManager.L == nil do return
	L := ctx.scriptManager.L
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(s.callbackRef))
	if lua.type(L, -1) != .FUNCTION {
		lua.pop(L, 1)
		return
	}
	push_node_userdata(L, n)
	push_spawn_info(L, s, entry)
	push_node_userdata(L, s)
	if lua.pcall(L, 3, 0, 0) != 0 {
		Script_Problem(.Error, "[Spawner] %s: spawn callback: %s", s.name, lua.tostring(L, -1))
		lua.pop(L, 1)
	}
}

// spawner_scene: the scene spawners spawn into (the running one).
@(private = "file")
spawner_scene :: proc(ctx: ^GameContext) -> ^Scene {
	if ctx == nil || ctx.game == nil do return nil
	return ctx.game.sceneManager.currentScene
}

// SpawnerNode_DrawBounds: the spawn point, the facing and the spread (debug
// bounds / the editor).
SpawnerNode_DrawBounds :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	s := cast(^SpawnerNode)node
	col := rl.Color{244, 114, 182, 220}
	p := s.globalPosition + rotate_vec(s.offset * s.globalScale, s.globalRotation)
	facing := f32(1) if s.globalScale.x >= 0 else -1
	dirAt :: proc(deg, facing: f32) -> [2]f32 {
		r := math.to_radians(deg)
		return {math.cos(r), math.sin(r)} * facing
	}
	px := Debug_PixelSize()
	rl.DrawCircleLinesV(p, 6 * px, col)
	rl.DrawLineV(s.globalPosition, p, {col.r, col.g, col.b, 90})
	rot := s.globalRotation if s.inheritRotation else 0
	rl.DrawLineEx(p, p + dirAt(rot, facing) * 28 * px, 2 * px, col)
	if s.spread > 0 {
		half := s.spread * 0.5
		rl.DrawLineV(p, p + dirAt(rot - half, facing) * 22 * px, {col.r, col.g, col.b, 140})
		rl.DrawLineV(p, p + dirAt(rot + half, facing) * 22 * px, {col.r, col.g, col.b, 140})
	}
	if s.jitter != {} {
		j := s.jitter * [2]f32{abs(s.globalScale.x), abs(s.globalScale.y)}
		rl.DrawRectangleLinesEx({p.x - j.x, p.y - j.y, j.x * 2, j.y * 2}, px, {col.r, col.g, col.b, 120})
	}
}

// --- Lua -------------------------------------------------------------------------------
// spawner:spawn([index]) -> the spawned roots (a list; empty when held back)
// spawner:spawn_at(x, y | Vec2 [, index]) -> roots, at a world position
// spawner:spawn_reset() / spawner:spawn_alive_count() -> n
// spawner:spawn_entries() -> {{component, weight, count}, ...}
// spawner:spawn_add(component [, weight [, count]]) / spawner:spawn_remove(index) / spawner:spawn_clear()

@(private = "file")
lua_spawner_arg :: proc(L: ^lua.State) -> ^SpawnerNode {
	n, ok := to_node_userdata(L, 1)
	if !ok || n.typeId != SpawnerNode do return nil
	return cast(^SpawnerNode)n
}

@(private = "file")
push_nodes :: proc(L: ^lua.State, nodes: []^Node) {
	lua.createtable(L, c.int(len(nodes)), 0)
	for n, i in nodes {
		push_node_userdata(L, n)
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
}

@(private = "file")
lua_spawn :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	s := lua_spawner_arg(L)
	if s == nil {
		lua.createtable(L, 0, 0)
		return 1
	}
	index := int(lua.tointeger(L, 2)) - 1 if lua.type(L, 2) == .NUMBER else -1
	push_nodes(L, SpawnerNode_Spawn(s, s.gameContext, index))
	return 1
}

// spawner:set_spawn_callback(function(node, info, spawner) ... end | nil)
@(private = "file")
lua_set_spawn_callback :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	s := lua_spawner_arg(L)
	if s == nil do return 0
	if s.callbackRef != 0 {
		lua.L_unref(L, lua.REGISTRYINDEX, s.callbackRef)
		s.callbackRef = 0
	}
	if lua.type(L, 2) == .FUNCTION {
		lua.pushvalue(L, 2)
		s.callbackRef = i32(lua.L_ref(L, lua.REGISTRYINDEX))
	}
	return 0
}

// spawner:spawn_info(node) -> {component, index} | nil
@(private = "file")
lua_spawn_info :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	s := lua_spawner_arg(L)
	n, ok := to_node_userdata(L, 2)
	if s == nil || !ok {
		lua.pushnil(L)
		return 1
	}
	entry, found := SpawnerNode_SpawnInfo(s, n)
	if found {
		push_spawn_info(L, s, entry)
	} else {
		lua.pushnil(L)
	}
	return 1
}

@(private = "file")
lua_spawn_at :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	s := lua_spawner_arg(L)
	if s == nil {
		lua.createtable(L, 0, 0)
		return 1
	}
	x, y := arg_xy(L, 2)
	idxArg: c.int = 4 if lua.type(L, 2) == .NUMBER else 3 // (after x, y - or after a Vec2)
	index := int(lua.tointeger(L, idxArg)) - 1 if lua.type(L, idxArg) == .NUMBER else -1
	// Move the spawner there for the spawn (its parent's space), then back.
	prev := s.position
	scene := spawner_scene(s.gameContext)
	parent := GetParent(scene.manager, s) if scene != nil else nil
	if parent != nil {
		pp, ps, pr := spawner_world(scene.manager, parent)
		safe := [2]f32{ps.x if ps.x != 0 else 1, ps.y if ps.y != 0 else 1}
		s.position = rotate_vec([2]f32{x, y} - pp, -pr) / safe
	} else {
		s.position = {x, y}
	}
	push_nodes(L, SpawnerNode_Spawn(s, s.gameContext, index))
	s.position = prev
	return 1
}

@(private = "file")
lua_spawn_reset :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if s := lua_spawner_arg(L); s != nil do SpawnerNode_Reset(s)
	return 0
}

@(private = "file")
lua_spawn_alive_count :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	s := lua_spawner_arg(L)
	lua.pushinteger(L, lua.Integer(SpawnerNode_AliveCount(s) if s != nil else 0))
	return 1
}

@(private = "file")
lua_spawn_entries :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	s := lua_spawner_arg(L)
	if s == nil {
		lua.createtable(L, 0, 0)
		return 1
	}
	lua.createtable(L, c.int(len(s.entries)), 0)
	for en, i in s.entries {
		lua.createtable(L, 0, 3)
		lua.pushstring(L, strings.clone_to_cstring(en.component, context.temp_allocator))
		lua.setfield(L, -2, "component")
		lua.pushnumber(L, lua.Number(en.weight))
		lua.setfield(L, -2, "weight")
		lua.pushinteger(L, lua.Integer(en.count))
		lua.setfield(L, -2, "count")
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

@(private = "file")
lua_spawn_add :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	s := lua_spawner_arg(L)
	if s == nil || lua.type(L, 2) != .STRING do return 0
	weight := f32(lua.tonumber(L, 3)) if lua.type(L, 3) == .NUMBER else 1
	count := int(lua.tointeger(L, 4)) if lua.type(L, 4) == .NUMBER else 1
	SpawnerNode_AddEntry(s, string(lua.tostring(L, 2)), weight, count)
	return 0
}

@(private = "file")
lua_spawn_remove :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if s := lua_spawner_arg(L); s != nil do SpawnerNode_RemoveEntry(s, int(lua.tointeger(L, 2)) - 1)
	return 0
}

@(private = "file")
lua_spawn_clear :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if s := lua_spawner_arg(L); s != nil do for len(s.entries) > 0 do SpawnerNode_RemoveEntry(s, len(s.entries) - 1)
	return 0
}

// Script_RegisterSpawnerBindings adds the spawn_* methods to the node
// metatable (on the stack).
Script_RegisterSpawnerBindings :: proc(L: ^lua.State) {
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "spawner_spawn", lua_spawn)
	Lua_SetDeprecated(L, lua_spawn, "spawn", "spawner_spawn")
	reg(L, "spawn_at", lua_spawn_at)
	reg(L, "spawn_reset", lua_spawn_reset)
	reg(L, "spawn_alive_count", lua_spawn_alive_count)
	reg(L, "spawn_entries", lua_spawn_entries)
	reg(L, "spawn_add", lua_spawn_add)
	reg(L, "spawn_remove", lua_spawn_remove)
	reg(L, "spawn_clear", lua_spawn_clear)
	reg(L, "spawner_set_callback", lua_set_spawn_callback)
	Lua_SetDeprecated(L, lua_set_spawn_callback, "set_spawn_callback", "spawner_set_callback")
	reg(L, "spawn_info", lua_spawn_info)
}
