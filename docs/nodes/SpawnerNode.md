## The spawn list

The Inspector's **Spawn List** section holds the components it spawns
(saved in the scene as `"spawner": {"entries": [...]}`): pick each one, or
drag `.component.json` files onto the list from Assets. Each entry has a
**weight** (Random mode), a **count** (spawned each time it is picked) and
its own **offset**. The arrow moves an entry up: Sequential spawns in list
order.

| Mode | One spawn makes |
|---|---|
| Single | The first entry |
| All | Every entry |
| Random | One entry, picked by weight |
| Sequential | The next entry (then Loop, Ping Pong or Stop at the end) |
| Shuffle | A random entry - each one once before any repeats |

**Count** repeats the pick (a burst of 3 bullets: count 3).

## Where spawned nodes go

A spawned node starts at the spawner's **world** position (plus its
offsets, which turn and flip with it), rotation (**Inherit Rotation**) and
scale (**Inherit Scale**: a flipped player fires flipped bullets). The
spawner is an ordinary child, so it moves with its parent: put it in the
player's hand.

**Parent Mode** says where the nodes go: under the scene's root (the default
- a fireball doesn't follow the player once fired), the spawner's parent or
the spawner (they move with it), or the node at **Parent Path**.

**Spread** turns each one randomly (degrees), **Jitter** moves it randomly
(px), and **Speed** gives a dynamic or kinematic body root a velocity along
the facing.

## Spawning

```lua
-- A player's script: fire from the hand.
function Player:update(dt)
    if Input.is_action_pressed("fire") then
        self.node:get_node("Hand/Muzzle"):spawner_spawn()   -- the roots spawned (empty if held back)
    end
end
```

- From a script: `spawn([index])`, `spawn_at(x, y)`, `spawn_reset()`,
  `spawn_alive_count()`, `spawn_entries()`, `spawn_add(component)`.
- From a signal, no script: in the Inspector's **Signals**, connect any
  event (a timer's `timeout`, a button's `clicked`, an area's
  `body_entered`) to the spawner and pick **Spawn (no script)**.
- By itself: **Auto Spawn** every **Interval** seconds (+ **Interval
  Jitter**) after **Start Delay**.

**Cooldown** (seconds between spawns: a fire rate), **Chance**, **Max Alive**
(at most that many at once) and **Total Limit** (then `limit_reached`)
hold spawns back. **Use Pool** takes instances from the scene's
[pool](../../engine/docs/pooling.md) instead of making new ones.

Events: **`spawned`** (the new root - set it up in a handler, or see
below), **`limit_reached`**, **`list_finished`** (Sequential with Stop).

In the editor the selected spawner shows its spawn point, facing and
spread; in *Simulate* the Inspector has **Spawn Now** and the count of what
is alive.

## Setting up what it spawns

`spawn()` returns the roots it made, already placed. Their scripts' `ready()`
runs on their first update, so anything you set right after spawning is
seen in `ready()`:

- **Script properties**: `node:get_script().speed = 400`, or
  `node:set_property("script.speed", 400)`.
- **Built-in properties**: `node.position`, `node:set_property("modulate",
  ...)`, a body's velocity...
- **Resource and node properties** (`type = "resource"` / `"node"`) too: a
  value set before `ready()` stays; the one saved in the component is only
  the default.
- **Pooled spawns** (**Use Pool**): the node is reused, so set what you need
  every time; it's taken before its `on_spawn()`, which runs on its next
  update and so sees your values too.

```lua
-- A script calls spawn(): set up each root it returns.
function Player:fire()
    for _, bullet in ipairs(self.node:get_node("Hand/Muzzle"):spawner_spawn()) do
        local s = bullet:get_script()
        s.speed = 400
        s.owner = self.node
        s.attack = self.current_attack   -- a resource
    end
end
```

**Automatic spawns** (Auto Spawn, a signal's *Spawn*): give the spawner a
**spawn callback**. It runs for every spawn - by call, Auto Spawn, signal
or pool - after the node is placed and before its `ready()` / `on_spawn()`,
with `info.component` (the component's path) and `info.index` (its entry in
the list, from 1). Setting it again replaces it; `nil` clears it.

```lua
function Level:ready()
    local attacks = { Resource.load("resources/sword.resource.json"),
                      Resource.load("resources/bow.resource.json") }
    self.node:get_node("EnemySpawner"):spawner_set_callback(function(enemy, info, spawner)
        enemy:get_script().difficulty = self.difficulty
        enemy:get_script().weapon = attacks[info.index]   -- goblins (1) get a sword, archers (2) a bow
    end)
end
```

**Telling spawns apart**: the `spawned` signal passes the new root;
`spawner:spawn_info(node)` returns its `{component, index}` while it's
alive, and `node:get_component()` its component's path.

```lua
self.node:get_node("EnemySpawner"):connect("spawned", function(enemy)
    local info = self.node:get_node("EnemySpawner"):spawn_info(enemy)
    if info.component == "components/archer.component.json" then
        enemy:set_property("script.patrol_radius", 64)
    end
end)
```
