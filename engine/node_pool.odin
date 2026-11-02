package engine

import "base:runtime"
import "core:c"
import "core:strings"
import b2 "vendor:box2d"
import lua "lua54"

// ============================================================================
// Node pools: reuse instances of a component instead of creating and
// freeing them (bullets, sparks, coins, enemies of a wave).
//
//   Pool_Get(scene, "components/bullet.component.json")  the scene's pool
//   Pool_Take(pool, parent, pos)  a parked instance (or a new one)
//   Pool_Return(pool, node)       park it again
//
// - A parked node stays in the tree, disabled (no update, no drawing) with
//   its physics bodies disabled; taking it re-enables it, moves it (its
//   bodies teleported, velocities zeroed) and puts it under the parent.
// - Removing a pooled node (node:destroy(), a Visibility
//   Notifier's Remove Parent, RemoveNode) returns it to its pool instead.
//   If its parent is removed, it goes with it (the pool forgets it).
// - Scripts: on_spawn() runs on the root's script before its first update
//   after every take (after ready() the first time); on_despawn() when it
//   is returned. Reset per-life state there.
// - A pool lives as long as its scene is loaded (Pools_Destroy on unload);
//   `max` caps the instances (0 = no cap; Pool_Take returns nil at it).
//
// Memory: a pool is a small heap struct with one free list of node
// pointers; the nodes themselves live in the scene's node arenas as usual,
// created once, then reused - no parsing, no allocation per spawn.
// ============================================================================

Node_Pool :: struct {
	component: string,          // project-relative component file (heap)
	free:      [dynamic]^Node,  // parked instances (LIFO: the most recently used is warm)
	active:    int,             // taken and not returned
	created:   int,             // instances made (never more than max)
	max:       int,             // 0 = no cap
	allocator: runtime.Allocator, // what made it (Lua calls run on the default heap): frees with it
}

// Pool_Get: the scene's pool for a component (made on first use).
Pool_Get :: proc(scene: ^Scene, component: string, max := 0) -> ^Node_Pool {
	if scene == nil || component == "" do return nil
	for p in scene.pools do if p.component == component {
		if max > 0 do p.max = max
		return p
	}
	p := new(Node_Pool)
	p.allocator = context.allocator
	p.component = strings.clone(component)
	p.free = make([dynamic]^Node, p.allocator)
	p.max = max
	append(&scene.pools, p)
	return p
}

// Pool_Prewarm makes instances up front (parked), up to `count` in total.
Pool_Prewarm :: proc(scene: ^Scene, pool: ^Node_Pool, count: int, ctx: ^GameContext) {
	for pool.created < count && (pool.max == 0 || pool.created < pool.max) {
		n := pool_make(scene, pool, scene.rootNode, ctx)
		if n == nil do return
		pool_park(scene.manager, pool, n, ctx, call = false)
	}
}

@(private = "file")
pool_make :: proc(scene: ^Scene, pool: ^Node_Pool, parent: ^Node, ctx: ^GameContext) -> ^Node {
	n := Scene_InstantiateComponent(scene, pool.component, parent, ctx)
	if n == nil do return nil
	n.pool = pool
	n.transient = true // runtime instances: never saved with the scene
	pool.created += 1
	return n
}

// Pool_Take: a parked instance (else a new one, unless at max) under
// `parent` (nil: the scene root) at `pos` (local to the parent).
Pool_Take :: proc(scene: ^Scene, pool: ^Node_Pool, parent: ^Node, pos: [2]f32, ctx: ^GameContext) -> ^Node {
	if scene == nil || pool == nil do return nil
	parent := parent if parent != nil else scene.rootNode
	n: ^Node
	for len(pool.free) > 0 {
		c := pop(&pool.free)
		if Node_IsAlive(c) && !c.removing && c.pool == pool {n = c; break}
	}
	if n == nil {
		if pool.max > 0 && pool.created >= pool.max do return nil
		n = pool_make(scene, pool, parent, ctx)
		if n == nil do return nil
	} else {
		if GetParent(scene.manager, n) != parent {
			AddChild(scene.manager, parent, n)
		}
		// Reused instance: reload local resource copies and re-resolve resource properties (#82).
		sm := ctx.scriptManager if ctx != nil else nil
		if sm != nil {
			Resource_ReloadScope(sm, Resource_ScopeOf(n), n)
		}
	}
	n.position = pos
	n.enabled = true
	pool.active += 1
	// Its world transform now (bodies are placed there), then the bodies.
	Node_SetGlobalPositions(scene.manager, n, parent.globalPosition, parent.globalScale, parent.globalRotation)
	pool_bodies(scene.manager, n, true)
	n.poolSpawn = true // on_spawn before its next update (scene.odin)
	return n
}

// Pool_Return parks a taken instance (on_despawn first). RemoveNode calls
// it for pooled nodes.
Pool_Return :: proc(m: ^NodeManager, node: ^Node, ctx: ^GameContext) -> bool {
	if node == nil || node.pool == nil || !node.enabled do return false
	pool := node.pool
	pool.active = max(pool.active - 1, 0)
	pool_park(m, pool, node, ctx, call = true)
	return true
}

@(private = "file")
pool_park :: proc(m: ^NodeManager, pool: ^Node_Pool, n: ^Node, ctx: ^GameContext, call: bool) {
	if call && n.isReady && ctx != nil && ctx.scriptManager != nil do Script_CallMethod(ctx.scriptManager, n, "on_despawn", nil, quiet = true)
	if !Node_IsAlive(n) || n.removing do return
	if ctx != nil && ctx.game != nil do Tween_CancelNode(&ctx.game.tweens, n)
	n.enabled = false
	n.poolSpawn = false
	pool_bodies(m, n, false)
	append(&pool.free, n)
}

// pool_bodies enables / disables the physics bodies of a subtree (a
// disabled node doesn't update, so its body wouldn't be switched off);
// enabling also zeroes velocities and teleports to the node.
@(private = "file")
pool_bodies :: proc(m: ^NodeManager, n: ^Node, on: bool) {
	if body := Physics_BodyOf(n); b2.Body_IsValid(body) {
		if on {
			b2.Body_SetTransform(body, n.globalPosition, DegreesToRot(n.globalRotation))
			b2.Body_SetLinearVelocity(body, {0, 0})
			b2.Body_SetAngularVelocity(body, 0)
			if n.typeId == DynamicBodyNode {
				db := cast(^DynamicBodyNode)n
				db.linearVelocity, db.lastSyncedVel = {}, {}
				db.angularVelocity, db.lastSyncedAngVel = 0, 0
				db.lastSyncedPos, db.lastSyncedRot = db.globalPosition, db.globalRotation
			} else if n.typeId == KinematicBodyNode {
				kb := cast(^KinematicBodyNode)n
				kb.linearVelocity, kb.lastSyncedVel = {}, {}
				kb.angularVelocity, kb.lastSyncedAngVel = 0, 0
				kb.lastSyncedPos, kb.lastSyncedRot = kb.globalPosition, kb.globalRotation
				kb.targetTransformActive = false
			}
			if !n.bodyPaused do b2.Body_Enable(body)
		} else {
			b2.Body_Disable(body)
		}
	}
	for c in GetChildrenView(m, n) do pool_bodies(m, c, on)
}

// Pool_Forget: a pooled node is really being freed (its parent was
// removed, the scene unloads): drop it from its pool.
Pool_Forget :: proc(node: ^Node) {
	pool := node.pool
	if pool == nil do return
	node.pool = nil
	for f, i in pool.free do if f == node {
		unordered_remove(&pool.free, i)
		pool.created -= 1
		return
	}
	pool.active = max(pool.active - 1, 0)
	pool.created -= 1
}

// Pools_Destroy frees a scene's pools (their nodes are freed with the
// scene's node manager).
Pools_Destroy :: proc(scene: ^Scene) {
	if len(scene.pools) == 0 do return
	if scene.manager != nil do for n in scene.manager.nodes do if n != nil do n.pool = nil
	for p in scene.pools {
		a := p.allocator
		delete(p.free)
		delete(p.component, a)
		free(p, a)
	}
	delete(scene.pools)
	scene.pools = nil
}

// --- Lua: Pool ---------------------------------------------------------------------
// Pool.take(component [, parent [, x, y]]) -> node | nil
// Pool.release(node) -> bool        (node:destroy() does the same for pooled nodes)
// Pool.prewarm(component, count)
// Pool.set_max(component, max)      (0 = no cap)
// Pool.stats(component) -> active, parked, created
// Functions keyed by the component path: no pool objects for scripts to hold.

@(private = "file")
pool_lua_scene :: proc(L: ^lua.State) -> (^Scene, ^ScriptManager) {
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil do return nil, sm
	return sm.game.sceneManager.currentScene, sm
}

@(private = "file")
lua_pool_take :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	scene, sm := pool_lua_scene(L)
	if scene == nil || lua.type(L, 1) != .STRING {
		lua.pushnil(L)
		return 1
	}
	pool := Pool_Get(scene, string(lua.tostring(L, 1)))
	parent, _ := to_node_userdata(L, 2)
	pos: [2]f32
	if !lua.isnoneornil(L, 3) do pos.x, pos.y = arg_xy(L, 3)
	n := Pool_Take(scene, pool, parent, pos, &sm.game.gameContext)
	if n == nil {
		if pool.max == 0 || pool.created < pool.max {
			lua.L_where(L, 1)
			where_ := strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
			lua.pop(L, 1)
			Script_Problem(.Warning, "%sPool.take: no component \"%s\"", where_, pool.component)
		}
		lua.pushnil(L)
		return 1
	}
	push_node_userdata(L, n)
	return 1
}

@(private = "file")
lua_pool_release :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	scene, sm := pool_lua_scene(L)
	n, ok := to_node_userdata(L, 1)
	lua.pushboolean(L, b32(ok && scene != nil && Pool_Return(scene.manager, n, &sm.game.gameContext)))
	return 1
}

@(private = "file")
lua_pool_prewarm :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	scene, sm := pool_lua_scene(L)
	if scene == nil || lua.type(L, 1) != .STRING do return 0
	Pool_Prewarm(scene, Pool_Get(scene, string(lua.tostring(L, 1))), int(lua.tointeger(L, 2)), &sm.game.gameContext)
	return 0
}

@(private = "file")
lua_pool_set_max :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	scene, _ := pool_lua_scene(L)
	if scene == nil || lua.type(L, 1) != .STRING do return 0
	Pool_Get(scene, string(lua.tostring(L, 1))).max = max(int(lua.tointeger(L, 2)), 0)
	return 0
}

@(private = "file")
lua_pool_stats :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	scene, _ := pool_lua_scene(L)
	a, f, c: int
	if scene != nil && lua.type(L, 1) == .STRING {
		path := string(lua.tostring(L, 1))
		for p in scene.pools do if p.component == path {a, f, c = p.active, len(p.free), p.created}
	}
	lua.pushinteger(L, lua.Integer(a))
	lua.pushinteger(L, lua.Integer(f))
	lua.pushinteger(L, lua.Integer(c))
	return 3
}

// Script_RegisterPoolModule creates the global Pool table.
Script_RegisterPoolModule :: proc(L: ^lua.State) {
	lua.newtable(L)
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "take", lua_pool_take)
	reg(L, "release", lua_pool_release)
	reg(L, "prewarm", lua_pool_prewarm)
	reg(L, "set_max", lua_pool_set_max)
	reg(L, "stats", lua_pool_stats)
	lua.setglobal(L, "Pool")
}
