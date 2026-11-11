# Picking up and throwing objects

A character that grabs a crate, carries it around and throws it: the crate
stays a real physics body the whole time, so while it's carried it still
bumps into walls, floors and other bodies instead of passing through them,
and once thrown it flies, bounces and lands on its own.

The way to do it is one **Joint** of type **Mouse** on the player. A Mouse
joint pulls a body towards a target point with a spring and a force limit.
Each frame the script moves the target to where the player's hands are, and
the joint drags the object there. If something is in the way, the object
stops against it, because the joint can only pull so hard.

The joint's bodies are set from the script with `joint_set_bodies`, so it
works with any object: ones placed in the level and ones spawned while the
game runs.

## Setting up the player

1. The player is a **Character Mover** (or any physics body).
2. Select it and **Add Node > Joint**, named **Grab**. It becomes a child of
   the player, and **Body A** is the player (its parent).
3. In the Inspector set **Type** to **Mouse**. Leave **Body B** as *None*:
   with no Body B the joint isn't made, so nothing is held yet.
4. Add a **Trigger Area** under the player, named **Reach**, with a shape
   a little bigger than the player. It finds what's close enough to pick up.

Make the throwable objects **Dynamic Bodies** and give them a tag, such as
`throwable` (Inspector > Tags), so the script can tell them from other
bodies. They can come from anywhere: the level, a component
spawned with `Scene.instantiate`, a Spawner or a Pool.

## The script

On the player:

```lua
---@class Carrier : ScriptInstanceBase
local Carrier = {}

Carrier.properties = {
    hold_x      = { type = "float", default = 28,  label = "Hold Offset X" },
    hold_y      = { type = "float", default = -24, label = "Hold Offset Y" },
    throw_speed = { type = "float", default = 550, label = "Throw Speed" },
    throw_up    = { type = "float", default = 250, label = "Throw Lift" },
}

function Carrier:ready()
    self.grab  = self.node:get_node("Grab")  ---@type JointNode
    self.reach = self.node:get_node("Reach") ---@type AreaNode
    self.held = nil
    self.facing = 1
end

-- Where the held object should be: in front of the player, at hand height.
function Carrier:hold_point()
    local x, y = self.node:get_global_position()
    return x + self.hold_x * self.facing, y + self.hold_y
end

function Carrier:pick_up(body)
    -- Put the target on the object first: the joint holds the object by the
    -- point where the target is when the joint is made.
    local x, y = body:get_global_position()
    self.grab:set_property("joint.mouse.target", x, y)
    -- Bodies are heavy at pixel scale: pull with many times the weight.
    self.grab:set_property("joint.mouse.max_force", body:get_mass() * 1000 * 30)
    self.grab:set_property("joint.mouse.hertz", 8)
    self.grab:set_property("joint.mouse.damping_ratio", 1)
    body:set_fixed_rotation(true) -- carried upright (optional)
    self.grab:joint_set_bodies(nil, body) -- Body A: the player; Body B: this
    self.held = body
end

function Carrier:release()
    self.grab:joint_set_bodies(nil, nil) -- no Body B: the joint lets go
    local body = self.held
    self.held = nil
    if body then body:set_fixed_rotation(false) end
    return body
end

function Carrier:throw()
    local body = self:release()
    if body then
        body:set_linear_velocity(self.throw_speed * self.facing, -self.throw_up)
    end
end

-- The nearest throwable in reach (nil when none).
function Carrier:nearest_throwable()
    local best, bestD = nil, math.huge
    local px, py = self.node:get_global_position()
    for _, n in ipairs(self.reach:area_get_overlapping_nodes()) do
        if n:has_tag("throwable") then
            local x, y = n:get_global_position()
            local d = (x - px) ^ 2 + (y - py) ^ 2
            if d < bestD then best, bestD = n, d end
        end
    end
    return best
end

function Carrier:update(dt)
    local vx = self.node:character_get_velocity()
    if vx > 1 then self.facing = 1 elseif vx < -1 then self.facing = -1 end

    -- Destroyed while held (it fell in lava, a script removed it).
    if self.held and not self.grab:joint_is_active() then self.held = nil end

    if self.held then
        self.grab:set_property("joint.mouse.target", self:hold_point())
        if Input.is_action_pressed("throw") then self:throw()
        elseif Input.is_action_pressed("interact") then self:release() end -- put it down
    elseif Input.is_action_pressed("interact") then
        local body = self:nearest_throwable()
        if body then self:pick_up(body) end
    end
end

return Carrier
```

Add the `interact` and `throw` actions in **Project Settings > Input**.

## Tuning it

| Setting | What it changes |
|---|---|
| `joint.mouse.max_force` | How hard the object is pulled. Too low and it sags or drops when carried; too high and it shoves other bodies aside (and can push through thin colliders). Start around 30 × `get_mass()` × 1000 and adjust. |
| `joint.mouse.hertz` | How stiff the pull is: 3-5 is a loose, swinging carry; 8-15 keeps the object close to the hands. |
| `joint.mouse.damping_ratio` | 1 stops it overshooting the hold point; lower values let it wobble. |
| Hold offset | Keep the hold point clear of the player's own collider, or the player and the object push against each other. |
| Throw velocity | `set_linear_velocity` sets the speed directly in px/s, whatever the object weighs. For "heavy things fly less", use `apply_impulse` instead (the same push makes light objects faster). |

A heavy object that should slow the player down: read the held object's
`get_mass()` in the movement code and lower the player's speed.

## The player and the held object

**Collide Connected** (off by default) controls whether the two bodies a
joint connects collide with each other. With it off, the held object
doesn't collide with the player's body. The Character Mover sweeps its own
shape when it moves, though, so a held object in its path can still block
it. If the player stutters while carrying something, move the hold point
out of the way, or take the player's layer out of the object's mask while
it's held (`set_collision_mask`) and put it back when it's thrown.

## Spawned objects

Nothing special is needed. `joint_set_bodies` takes the node itself, not its
name or path, so ten spawned crates all named "Crate" are fine. The joint
holds the one it was given. If that node is destroyed, the joint goes too,
and `joint_get_bodies` gives `nil` for Body B.

```lua
local crate = Scene.instantiate("components/crate.component.json", nil, x, y)
crate:add_tag("throwable")
```

Bodies set with `joint_set_bodies` last for the run; they aren't saved with
the scene. To keep a joint's bodies, set them in the Inspector.

## Without a joint

For a stiffer carry with no spring, skip the joint and set the object's
velocity towards the hold point each frame. It still collides with walls,
because it's still a body moved by the physics world:

```lua
local hx, hy = self:hold_point()
local x, y = self.held:get_global_position()
self.held:set_linear_velocity((hx - x) * 15, (hy - y) * 15) -- 15: how firmly it follows
```

Turn its gravity off while held (`set_gravity_scale(0)`) and back on when
it's thrown. Unlike the Mouse joint, nothing limits the force here: a carried
object pushes anything out of its way.

## Scripting reference

| Method | |
|---|---|
| `joint:joint_set_bodies(a, b)` | Sets Body A and Body B while the game runs. Each is a physics body node, a path from the joint (as the Inspector saves), or `nil`: for A, the joint's parent; for B, none, and the joint lets go. Returns false (and changes nothing) for anything else. The joint is made again with the new bodies on the next frame. |
| `joint:joint_get_bodies()` | The two body nodes, or `nil` for one that's missing or destroyed. |
| `joint:joint_is_active()` | Whether the joint exists in the physics world: it's enabled and both bodies were found. |
| `joint:set_property("joint.mouse.target", x, y)` | The world point a Mouse joint pulls towards (px). Also `max_force`, `hertz`, `damping_ratio`. |

The same methods work for every joint type: chain spawned links with
Revolute joints, tie a Distance joint (a rope) to whatever a grappling hook
hits, weld a sticky bomb to the body it lands on.

See also the [Joint](../../docs/nodes/JointNode.md) and
[Dynamic Body](../../docs/nodes/DynamicBodyNode.md) node pages and the
[physics tutorial](../../docs/tutorials/physics.md).
