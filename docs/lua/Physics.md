## Use it for

- **Line of sight and ledge checks**: `Physics.raycast(x1, y1, x2, y2)` returns the first solid thing between two world points (its node, the hit point and the surface normal), or nil when the way is clear.
- **What a body stands on**: `character_get_floor()` on a Character Mover and `body_get_floor()` on a Dynamic Body return the floor's node, contact point, normal and slope (and on a TileMap the cell and tile), or nil in the air. They're quicker than a raycast down, and they report what the body actually touches.
- **Gravity changes**: `Physics.set_gravity(gx, gy)` for low-gravity zones, upside-down rooms or a space level; `get_gravity` reads it back. It affects every body in the world.
- **Freezing the simulation**: `Physics.set_paused(true)` stops bodies while scripts keep running - a slow-motion intro, an inspect mode. To pause the whole game, use `Engine.set_paused` instead.
- **Debugging collisions**: `Physics.set_debug_draw(true)` draws colliders, joints and areas while the game runs, like the project's **Show Colliders** setting.
- **Showing layer names**: `Physics.layer_name(n)` returns the name given to collision layer *n* in Project Settings > General > Collision Layers.

## Example

A turret that only fires when it can see the player - nothing solid between them; the script is on the turret node, and F3 shows the colliders.

```lua
---@class Turret : ScriptInstanceBase
local Turret = {}

Turret.properties = {
    reload = { type = "float", default = 1.0, label = "Reload Time" }, -- seconds
}

function Turret:ready()
    self.player = Scene.find_node("Player")
    self.cooldown = 0
end

---@param dt number
function Turret:update(dt)
    if Input.is_key_pressed("F3") then
        Physics.set_debug_draw(not Physics.is_debug_draw())
    end
    if not self.player then return end
    self.cooldown = self.cooldown - dt

    local x, y = self.node:get_global_position()
    local px, py = self.player:get_global_position()
    local hit = Physics.raycast(x, y, px, py)
    -- The first thing the ray meets must be the player itself.
    if hit and hit.node == self.player and self.cooldown <= 0 then
        self.cooldown = self.reload
        Log.info("fire at", hit.point_x, hit.point_y)
    end
end

return Turret
```

## Notes

- Positions are world px and gravity is px per second squared (positive Y pulls down).
- `raycast` ignores sensors ([Areas](../nodes/AreaNode.md)) and stops at the closest solid shape. Pass layers after the points to hit only those (`Physics.raycast(from, to, "World")`); without them it hits every layer. A ray that starts inside a collider may report it - start just outside the caster's own shape. For a ray that checks every frame and raises events, use a [Raycast](../nodes/RaycastNode.md) node.
- `hit.node` is the body that was hit ([Static Body](../nodes/StaticBodyNode.md), [Dynamic Body](../nodes/DynamicBodyNode.md), [Character Mover](../nodes/CharacterMoverNode.md)...); it can be missing for shapes with no node.
- `set_paused` only stops the physics step; `Engine.set_paused` also pauses scripts and nodes.
