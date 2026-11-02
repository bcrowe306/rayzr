# Object pooling

## What it is, and why

A shooter fires 10 bullets a second; each one lives for a second, then
leaves the screen. Without pooling, every shot **creates** a node tree from
its component file (read the JSON, allocate the nodes, attach the script,
create the physics body) and every despawn **frees** all of it again. That
work - and the memory churn - happens hundreds of times a minute.

A **pool** keeps the instances instead of freeing them. When a bullet is
done it is **parked**: disabled (no updates, not drawn, its physics body
switched off) but kept. The next shot **takes** a parked bullet, moves it to
the gun and switches it back on. After the first few shots, firing creates
nothing and frees nothing.

Pool anything that comes and goes often: bullets, shell casings, sparks and
hit effects, coins and pickups, floating damage numbers, enemies of a wave.
Don't bother for things made once (the player, the level).

## The short version

```lua
local BULLET = "components/Bullet.component.json"

function Gun:fire()
    -- Instead of Scene.instantiate(BULLET, parent, x, y):
    local b = Pool.take(BULLET, self.node:get_parent(), self.node.position)
    if b then b:get_script():launch(self.aim) end
end

-- And when the bullet is done, exactly as before:
function Bullet:on_hit(other)
    self.node:destroy()        -- a pooled node goes back to its pool
end
```

That's all that changes in most games: `Pool.take` instead of
`Scene.instantiate`. `destroy()` on a pooled node returns it
to its pool instead of freeing it (so does a Visibility Notifier set to
**Remove Parent**).

## Tutorial: pooled bullets with a clean reset

### 1. The bullet component

```
Bullet (DynamicBody, scripts/bullet.lua)       components/Bullet.component.json
├── Sprite
├── Trail
└── VisibilityNotifier    size 16 x 16, action: Remove Parent
```

The notifier returns the bullet to the pool when it flies off screen - no
code needed for that.

### 2. Reset per-life state in `on_spawn`

A reused bullet still has the state of its last life (how long it flew, a
"hit" flag, a trail full of old points). Pooled nodes get two extra script
callbacks:

| Callback | When |
|---|---|
| `on_spawn()` | Every time it is taken from the pool - before its next update (after `ready()` the first time). |
| `on_despawn()` | When it goes back to the pool. |

`ready()` still runs **once** (the first time); put one-time setup there and
per-life setup in `on_spawn`:

```lua
---@class Bullet : ScriptInstanceBase
local Bullet = {}

Bullet.properties = {
    speed = { type = "float", default = 600 },
    lifetime = { type = "float", default = 2.0 },
}

function Bullet:ready()
    -- Once per instance: look things up.
    self.trail = self.node:get_node("Trail")
end

function Bullet:on_spawn()
    -- Every life: reset.
    self.age = 0
    self.hit = false
    self.trail:trail_clear()          -- no streak from where it was parked
end

function Bullet:launch(direction)
    self.node:set_property("linearVelocity", direction:normalized() * self.speed)
end

function Bullet:update(dt)
    self.age = self.age + dt
    if self.age > self.lifetime then self.node:destroy() end
end

function Bullet:on_collision_started(other)
    if self.hit then return end
    self.hit = true
    if other:has_tag("enemy") then other:get_script():damage(1) end
    self.node:destroy()
end

function Bullet:on_despawn()
    -- Optional: stop sounds, release references, ...
end

return Bullet
```

Taking a bullet already zeroes its velocity and puts its body where the
node is, so `launch` only needs to set the new velocity.

### 3. Prewarm (optional)

The first takes still create instances. To avoid a hitch the first time the
player fires, make them when the level starts:

```lua
function Gun:ready()
    Pool.prewarm("components/Bullet.component.json", 32)
end
```

### 4. Cap it (optional)

```lua
Pool.set_max("components/Spark.component.json", 200)
```

At the cap `Pool.take` returns `nil` - skip the effect that frame (a missing
spark is better than a frame drop):

```lua
local s = Pool.take("components/Spark.component.json", nil, hit_pos)
if s then s:get_script():burst(normal) end
```

### 5. Watch it

The **Profiler** tab lists each pool while the scene runs:
`Pool Bullet.component.json  12 taken · 20 parked · 32 made`. If *made*
keeps growing, something takes without returning (a bullet that never
calls `destroy()`).

## API

| Function | Returns | |
|---|---|---|
| `Pool.take(component [, parent [, x, y]])` | node or nil | A parked instance, else a new one (nil at the max). Under `parent` (else the scene root) at x, y (local; or a Vec2). |
| `Pool.release(node)` | boolean | Return a taken instance (= `node:destroy()` on it). |
| `Pool.prewarm(component, count)` | - | Make instances up front (parked) - `count` in total. |
| `Pool.set_max(component, max)` | - | Cap the instances (0 = no cap). |
| `Pool.stats(component)` | active, parked, created | Counts. |

The functions take the component path: there is no pool object to keep
around or to outlive its scene.

## Rules worth knowing

- **Pools belong to the scene.** Changing scene frees them (and their
  nodes); the next scene starts with empty pools.
- **A parked node is still in the tree** (disabled). `Scene.find_node` can
  find it; check `node.enabled` if that matters.
- **If its parent is removed, a pooled node is freed with it** (the pool
  forgets it). Taking it again makes a new one. Put bullets under a
  long-lived node (the level, a "Projectiles" node), not under the gun of an
  enemy that dies.
- **Pooled instances are runtime-only**: they're never saved with the scene.
- Tweens running on a node are cancelled when it is returned.
- Signals connected with `connect` from another script stay connected
  across lives - connect them once (in `ready`), not in `on_spawn`.

## How it works (engine)

`engine/node_pool.odin`. A pool is a small struct with a free list of node
pointers (LIFO, so the most recently used - warm in the cache - comes back
first); the nodes live in the scene's node arenas as usual. `RemoveNode` on
a node that came from a pool returns it instead of queueing it for
removal; a pooled node removed with its parent is dropped from its pool
before it is freed, so a pool never holds a freed node. Pools are freed when
their scene unloads. From Odin:

```odin
pool := Pool_Get(scene, "components/Bullet.component.json", max = 256)
Pool_Prewarm(scene, pool, 32, &game.gameContext)
b := Pool_Take(scene, pool, parent, {x, y}, &game.gameContext)
RemoveNode(scene.manager, b) // back to the pool
```
