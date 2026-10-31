## Use it for

- **Finding nodes**: `get_node("Body/Gun")` follows a path from this node (`..` is the parent), `get_child(name)` looks only at direct children, and `get_parent()` / `get_children()` walk the tree. `Scene.find_node(name)` and `Scene.find_by_tag(tag)` search the whole scene.
- **Moving**: `set_position`, `translate`, `set_rotation`, `rotate` and `set_scale` work relative to the parent, in px and degrees. `get_global_position()` and `get_global_rotation()` give where it ends up in the world.
- **Showing and hiding**: `set_visible(false)` stops the node drawing itself. `set_enabled(false)` switches off the node and its children - no update, no drawing, no physics. `set_paused` and `set_pause_mode` decide what stops when the game pauses.
- **Hit feedback**: `flash("#ffffff", 0.1)` tints a sprite (or animation, tile map, text) a colour that fades back; `blink(1.0)` blinks the node and its children on and off (invulnerability); `squash(0.25, 0.3)` stretches the node tall and thin and springs it back - a negative amount squashes it flat first (a landing).
- **Tags and types**: `add_tag("enemy")` and `has_tag` group nodes without a common parent. `is("AreaNode")` checks a node's type - a custom type, its built-in type, or `"Node"`.
- **Events**: `emit("died", value)` calls the node script's `on_died` and every handler added with `connect`. `connect` returns an id for `disconnect`.
- **Talking to another script**: `get_script()` returns that node's `self` - read its fields and call its methods (`enemy:get_script():take_damage(1)`).
- **Removing**: `queue_free()` (or `destroy()`) removes the node and its children at the end of the frame. `add_child` moves a node under another, `remove_child` detaches one without destroying it.

## Example

An enemy that walks back and forth, turns its shield on while the player is near, and frees itself when its health runs out - the script is on the enemy's root node, with a [Texture](../nodes/TextureNode.md) child named `Sprite` and a child named `Shield`.

```lua
---@class Patrol : ScriptInstanceBase
local Patrol = {}

function Patrol:ready()
    self.speed = 60   -- px per second
    self.range = 80   -- px either side of where it starts
    self.dir = 1
    self.health = 3
    self.start_x = self.node:get_position()
    self.sprite = self.node:get_node("Sprite")
    self.shield = self.node:get_node("Shield")
    self.player = Scene.find_node("Player")
    self.node:add_tag("enemy")
    self.shield:set_visible(false)
end

function Patrol:update(dt)
    self.node:translate(self.speed * self.dir * dt, 0)
    local x = self.node:get_position()
    if math.abs(x - self.start_x) >= self.range then
        self.dir = -self.dir
        self.sprite:set_scale(self.dir, 1) -- face the way it walks
    end
    -- World positions: the player and the enemy have different parents.
    if self.player then
        local px, py = self.player:get_global_position()
        local ex, ey = self.node:get_global_position()
        local dx, dy = px - ex, py - ey
        self.shield:set_visible(dx * dx + dy * dy < 48 * 48)
    end
end

-- Other scripts call it: enemy:get_script():take_damage(1)
function Patrol:take_damage(amount)
    if self.shield:is_visible() then return end
    self.health = self.health - amount
    self.node:emit("health_changed", self.health)
    if self.health <= 0 then
        self.node:emit("died")
        self.node:queue_free()
    end
end

return Patrol
```

## Notes

- `get_position`, `set_position`, rotation and scale are local - relative to the parent. Compare nodes with different parents by `get_global_position()`. It is worked out before and after each frame's updates, so right after `set_position` it still has the old value.
- `ready()` runs once, after every node of the scene exists, parents before children - `get_node` finds the children, but their own `ready()` hasn't run yet. A node added later gets its `ready()` before the next update; a disabled one waits until it is enabled.
- `queue_free()` and `destroy()` are the same: the node stays until the end of the frame, so it is safe to call from its own `update`. A pooled node goes back to its pool instead. A reference to a removed node stays safe - its getters return defaults and `get_name()` returns nil.
- `set_visible(false)` hides only the node's own drawing - its children still draw, and it keeps updating. To hide a whole branch, use `set_enabled(false)`.
- An `emit` value can be a boolean, number, string or node; a table arrives as nil. A handler added with `connect` gets `(value, source)`.
