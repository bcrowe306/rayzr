# Physics scripting

This guide covers the physics tools scripts reach for every day. Each section
says what a feature is for, then shows a short example.

- [The fixed physics step](#the-fixed-physics-step): the same game at any
  frame rate, and `on_physics_update`.
- [Contact details](#contact-details): where and how hard two bodies hit.
- [Queries](#queries): raycasts that return every hit, shape casts, and
  checking what's inside a circle, a box or a point.
- [Collision exceptions](#collision-exceptions): two particular nodes stop
  colliding.
- [Forces, torque and mass](#forces-torque-and-mass): pushes at a point,
  spin, a set mass.
- [Changing shapes while the game runs](#changing-shapes-while-the-game-runs):
  crouch hitboxes, icy boots.
- [Test moves](#test-moves): "would this move hit something?".
- [Character Mover: floors, steps and platforms](#character-mover-floors-steps-and-platforms):
  slope limit, floor snap, stop on slope, step height, platform velocity.
- [Coyote time and jump buffering](#coyote-time-and-jump-buffering).
- [Area gravity and damping](#area-gravity-and-damping): water, wind,
  zero-g, planets.

Units are pixels and seconds throughout: positions in px, velocities in px/s,
gravity in px/s². Bodies are heavy at pixel scale, because mass is density
× area in px². A 32 × 32 box weighs 1024, so forces and impulses need big
numbers. Multiplying by `get_mass()` keeps them readable:
`apply_impulse(0, -body:get_mass() * 300)` changes the body's speed by
300 px/s.

## The fixed physics step

The physics world steps a fixed number of times per second, 60 by default.
A frame runs as many steps as its time holds: none, one, or a few. Bodies
are drawn between their last two steps, so motion stays smooth on a 144 Hz
display. On a 30 fps machine, two steps happen each frame. Either way, the
game plays the same: jumps reach the same height, and a ball bounces the
same way.

Set the rate in **Project Settings > Physics > Physics FPS**. 0 steps once
per frame with the frame's time, as Rayzr did before 1.2. Use 0 only if a
game relied on that behaviour. From a script:

```lua
Physics.set_fps(120)        -- a fast game: steadier collisions, more work
local fps = Physics.get_fps()
```

**`on_physics_update(dt)`** runs before every step, with the step's time.
Do the work that has to match the physics there: setting velocities,
applying forces, moving Character Movers. Keep `update(dt)` for everything
else, such as animation, UI and input that only reads. Use `update` to
notice a press and `on_physics_update` to act on it:

```lua
function Ship:update(dt)
    if Input.is_action_pressed("boost") then self.boost = true end
end

function Ship:on_physics_update(dt)
    local thrust = Input.get_axis("down", "up") * 3000
    self.node:apply_force(0, -thrust * self.node:get_mass() / 100)
    if self.boost then
        self.node:apply_impulse(0, -self.node:get_mass() * 200)
        self.boost = false
    end
end
```

Script-controlled Character Movers move in `on_physics_update` the same
way:

```lua
function Player:on_physics_update(dt)
    local m = self.node
    local vx, vy = m:character_get_velocity()
    vx = Input.get_axis("move_left", "move_right") * 220
    vy = vy + 980 * dt
    m:character_set_velocity(vx, vy)
    m:character_move_and_slide(dt)
end
```

A mover moved in `update(dt)` still works: it moves once per frame and is
drawn where it is, with no smoothing between steps. To draw your own things
between steps, `Physics.get_interpolation()` says how far the frame is
between the last two steps (0 to 1).

## Contact details

`on_collision_started` gets a second argument with how the contact began:

| Field | |
|---|---|
| `point` / `point_x`, `point_y` | Where they touched (world px). |
| `normal` / `normal_x`, `normal_y` | Points away from the other body: the way the contact pushes this one. Landing on a floor gives (0, -1). |
| `speed` | How fast they came together (px/s): impact damage, bounce sounds, breaking glass. |
| `velocity` | This body's velocity relative to the other's at the contact. |

```lua
function Crate:on_collision_started(other, contact)
    -- Louder for harder hits; no sound for gentle touches.
    if contact.speed > 80 then
        Audio.play_sound("sounds/thud.wav", math.min(contact.speed / 600, 1))
    end
    -- Stomped from above: the other body hit our top.
    if contact.normal_y > 0.7 and other:has_tag("player") then
        self.node:destroy()
    end
end
```

Handlers connected with `node:connect("collision_started", fn)` get it as
the third argument, `fn(other, node, contact)`. `collision_ended` has no
contact.

## Queries

Every query takes an optional last argument: the layers to hit, or an
options table.

```lua
{ layers = { "Enemies", "World" }, exclude = { self.node, self.shield }, sensors = false }
```

`layers` alone decides what a query hits: a collider on one of those layers
is found whatever its own mask says. (A wall whose mask leaves out the
player still shows up in `Physics.raycast(..., "World")`.) With no layers, a
query hits colliders on every layer. Before Rayzr 1.3, a collider whose mask
left out Layer1 was missed by every query.

| Function | Returns | Use it for |
|---|---|---|
| `Physics.raycast(x1, y1, x2, y2, opts)` | The closest hit, or nil | Line of sight, ledge checks, hitscan. |
| `Physics.raycast_all(x1, y1, x2, y2, opts)` | Every hit, nearest first | Piercing shots, lasers through glass. |
| `Physics.cast_shape(shape, x1, y1, x2, y2, opts)` | The first hit, or nil | Thick bullets, sword swings, "does the player fit through here?". |
| `Physics.overlap_circle(x, y, r, opts)` | Nodes inside | Explosions, auras, enemies in range. |
| `Physics.overlap_box(x, y, w, h, [rot], opts)` | Nodes inside | Melee hitboxes, selection boxes, checking a spawn spot. |
| `Physics.overlap_point(x, y, opts)` | Nodes there | What's under the mouse. |

A hit has `node`, `point`, `normal` and `fraction` (0 to 1 along the ray or
sweep). A cast's shape is a table: `{type = "circle", radius = 6}`,
`{type = "box", width = 20, height = 10, rotation = 0}` or
`{type = "capsule", radius = 6, height = 24}`.

An explosion that pushes everything within 120 px, harder near the
centre:

```lua
function Bomb:explode()
    local x, y = self.node:get_global_position()
    for _, n in ipairs(Physics.overlap_circle(x, y, 120, { exclude = self.node })) do
        if n.apply_impulse_at then -- a Dynamic Body
            local nx, ny = n:get_global_position()
            local dx, dy = nx - x, ny - y
            local d = math.max(math.sqrt(dx * dx + dy * dy), 1)
            local push = n:get_mass() * 500 * (1 - d / 120)
            n:apply_impulse_at(dx / d * push, dy / d * push, nx, ny)
        end
        n:emit("damaged", 30)
    end
    self.node:destroy()
end
```

A laser that pierces up to three enemies:

```lua
local hits = Physics.raycast_all(x, y, x + 600 * dir, y, { layers = "Enemies" })
for i = 1, math.min(#hits, 3) do hits[i].node:emit("damaged", 10) end
```

## Collision exceptions

Collision layers and masks decide which groups collide. An exception stops
two particular nodes colliding, while each keeps colliding with everything
else. Typical uses are a bullet that ignores the gun that fired it, a thrown
item that passes through its thrower for a moment, or a ghost that walks
through one door.

```lua
local bullet = Scene.instantiate("components/bullet.component.json", nil, x, y)
bullet:add_collision_exception(self.node)
-- (later, if needed) bullet:remove_collision_exception(self.node)
-- bullet:has_collision_exception(self.node) -> true / false
```

Exceptions also apply to Character Movers' movement and to `body_test_move`.
They end when either node is destroyed.

## Forces, torque and mass

On a Dynamic Body:

| Method | |
|---|---|
| `apply_force(fx, fy)` / `apply_impulse(ix, iy)` | At the centre of mass: no spin. |
| `apply_force_at(fx, fy, px, py)` / `apply_impulse_at(ix, iy, px, py)` | At a world point: off-centre pushes also spin it. |
| `apply_torque(t)` / `apply_angular_impulse(i)` | A turning force / an instant spin (positive is clockwise on screen). |
| `get_velocity_at(px, py)` | The velocity of the body at a point, spin included. |
| `set_mass(m)` / `get_mass()` | Set a mass whatever the size: a heavy anvil, a light balloon. |
| `get_center_of_mass()` | The point it turns about. |

A bullet hit that knocks a crate spinning:

```lua
function Bullet:on_collision_started(other, contact)
    if other.apply_impulse_at then
        local m = other:get_mass()
        other:apply_impulse_at(-contact.normal_x * m * 200, -contact.normal_y * m * 200, contact.point_x, contact.point_y)
    end
    self.node:destroy()
end
```

## Changing shapes while the game runs

`shape_count()`, `shape_get(i)` and `shape_set(i, settings)` work on any
node with collision shapes: bodies, Character Movers and Areas. Shapes
count from 1, and `shape_set` changes only the keys you give. The keys are
`radius`, `width`, `height`, `rotation`, `offset`, `density`, `friction`,
`restitution` and `sensor`.

```lua
-- Crouching: a lower hitbox.
self.node:shape_set(1, { height = 20, offset = Vec2(0, 6) })
-- Ice boots: no grip.
self.node:shape_set(1, { friction = 0 })
-- A pickup that grows.
self.node:shape_set(1, { radius = self.node:shape_get(1).radius + 4 })
```

The change reaches the physics world on the body's next update.

## Test moves

These answer "would this move hit something?" without moving anything:

- `body:body_test_move(dx, dy)` sweeps a body's shapes and returns the
  first hit (node, point, normal, fraction) or nil.
- `body:body_move_and_collide(dx, dy)` moves a Kinematic or Dynamic Body
  until it would touch something, and returns what it stopped against.
  It's useful for projectiles, sliding blocks and grid movement.
- `mover:character_test_move(dx, dy)` returns `blocked, fraction` for a
  Character Mover.

An enemy that turns around at walls and at ledges:

```lua
function Walker:on_physics_update(dt)
    local m = self.node
    local x, y = m:get_global_position()
    local wall = m:character_test_move(8 * self.dir, 0)
    local ground = Physics.raycast(x + 16 * self.dir, y, x + 16 * self.dir, y + 40, { exclude = m })
    if wall or not ground then self.dir = -self.dir end
    m:character_set_velocity(60 * self.dir, 200)
    m:character_move_and_slide(dt)
end
```

Standing up only when there's room:

```lua
if self.crouching and not self.node:character_test_move(0, -16) then
    self.node:shape_set(1, { height = 28, offset = Vec2(0, 0) })
    self.crouching = false
end
```

## Character Mover: floors, steps and platforms

New Inspector settings on the Character Mover:

| Setting | Default | |
|---|---|---|
| **Floor Max Angle** | 60° | The steepest slope it stands on. Steeper surfaces are walls: it slides down them and can't jump off them. |
| **Floor Snap Length** | 0 (off) | Keeps it on the floor walking down slopes and small steps, instead of hopping off. Try 8-16 px. |
| **Stop On Slope** | off | Standing still on a slope, it doesn't slide down. |
| **Step Height** | 0 (off) | Walks up steps this high without jumping: stairs, curbs, uneven tiles. Try about half its height. |
| **Coyote Time** / **Jump Buffer Time** | 0 (off) | See below. |

**Platform velocity.** `character_get_platform_velocity()` gives the velocity
of the floor it stands on, measured where it stands. The mover already
rides moving platforms; add this when jumping off so the jump keeps the
platform's momentum:

```lua
if jump then
    local px, py = m:character_get_platform_velocity()
    m:character_set_velocity(vx + px, -jump_speed + math.min(py, 0))
end
```

## Coyote time and jump buffering

Two small timings make a platformer feel fair:

- **Coyote time** lets a jump still work a moment after the character walks
  off a ledge.
- **Jump buffering** makes a jump pressed a moment before landing happen
  when the character lands.

The built-in movement has both as Inspector settings, **Coyote Time** and
**Jump Buffer Time**. 0.1 s each is a common start.

A script-controlled mover can do the same:

```lua
function Player:update(dt)
    if Input.is_action_pressed("jump") then self.jump_buffer = 0.1 end
end

function Player:on_physics_update(dt)
    local m = self.node
    local vx, vy = m:character_get_velocity()
    self.jump_buffer = math.max((self.jump_buffer or 0) - dt, 0)
    if self.jump_buffer > 0 and m:character_was_on_floor(0.1) and not self.jumped then
        vy = -360
        self.jump_buffer = 0
        self.jumped = true
    end
    if m:character_is_on_floor() then self.jumped = false end
    m:character_set_velocity(Input.get_axis("move_left", "move_right") * 220, vy + 980 * dt)
    m:character_move_and_slide(dt)
end
```

`character_was_on_floor(seconds)` is true on a floor, or within that many
seconds after leaving one. `character_get_time_since_floor()` gives the time
itself.

## Area gravity and damping

An Area can change gravity and damping for the bodies inside it. Dynamic
Bodies feel it as a force; Character Movers use the area's gravity instead
of the world's. **Monitoring** must be on, as it is by default.

| Setting | |
|---|---|
| **Gravity Mode** | Off; **Add** adds Gravity to the world's (wind, currents); **Replace** uses only Gravity (water, low gravity, zero-g, upside-down rooms). |
| **Gravity** | The area's gravity (px/s²). |
| **Gravity Point** / **Gravity Strength** | Pull towards the area's centre instead (a planet, a black hole; a negative strength pushes away). |
| **Damping Override**, **Linear Damping**, **Angular Damping** | Slow bodies inside (water, mud, thick air). |
| **Priority** | Higher priority areas apply first. A Replace stops lower ones: a bubble of air inside a pool of water. |

Some setups:

- **Water:** Gravity Mode Replace, Gravity (0, 150), Damping Override with
  Linear Damping 3. Things sink slowly and drift.
- **Wind tunnel:** Gravity Mode Add, Gravity (400, 0).
- **Zero-g room:** Gravity Mode Replace, Gravity (0, 0).
- **Planet:** a circle Area with Gravity Mode Replace, Gravity Point on and
  Gravity Strength 600.

Areas can be changed while the game runs, for example a fan that turns on:

```lua
fan:set_property("gravity_mode", "Add")
fan:set_property("gravity", 0, -500)
```

## Older projects

Projects made before Rayzr 1.2 open with the fixed step at 60 Hz. Most
games behave as they did, but more evenly. A game tuned around per-frame
steps, such as one that moves bodies in `update(dt)` and depends on the
exact frame timing, can set **Physics FPS** to 0 to keep the old behaviour.
Scenes saved by 1.2 also store the new Character Mover and Area settings
with their defaults, which change nothing.

See also: [Character Mover](../../docs/nodes/CharacterMoverNode.md),
[Area](../../docs/nodes/AreaNode.md),
[Dynamic Body](../../docs/nodes/DynamicBodyNode.md),
[Joints and carrying objects](carrying_objects.md),
[the Physics module](../../docs/lua/Physics.md) and the
[physics tutorial](../../docs/tutorials/physics.md).
