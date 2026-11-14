## Use it for

- **Finding nodes**: `get_node("Body/Gun")` follows a path from this node (`..` is the parent), `get_child(name)` looks only at direct children, and `get_parent()` / `get_children()` walk the tree. `Scene.find_node(name)` and `Scene.find_by_tag(tag)` search the whole scene.
- **Moving**: `set_position`, `translate`, `set_rotation`, `rotate` and `set_scale` work relative to the parent, in px and degrees. `get_global_position()` and `get_global_rotation()` give where it ends up in the world.
- **Showing and hiding**: `set_visible(false)` hides the node and its children (they keep updating; UI widgets in it take no clicks or keys). `set_enabled(false)` switches off the node and its children - no update, no drawing, no physics. `set_paused` and `set_pause_mode` decide what stops when the game pauses.
- **Hit feedback**: `flash("#ffffff", 0.1)` tints a sprite (or animation, tile map, text) a colour that fades back; `blink(1.0)` blinks the node and its children on and off (invulnerability); `squash(0.25, 0.3)` stretches the node tall and thin and springs it back - a negative amount squashes it flat first (a landing).
- **Tags and types**: `add_tag("enemy")` and `has_tag` group nodes without a common parent. `is("AreaNode")` checks a node's type - a custom type, its built-in type, or `"Node"`.
- **Events**: `emit("died", value)` calls the node script's `on_died` and every handler added with `connect`. `connect` returns an id for `disconnect`. Declare your own signals in the Inspector (Signals > **Add Signal**), in the node's [custom type](../../engine/docs/custom_nodes.md#signals), or with a `---@signal died` line in its script; `get_signals()` lists a node's signals and `has_signal(name)` checks for one.
- **Talking to another script**: `get_script()` returns that node's `self` - read its fields and call its methods (`enemy:get_script():take_damage(1)`).
- **Removing**: `destroy()` removes the node and its children at the end of the frame. `add_child` moves a node under another, `remove_child` detaches one without destroying it.

## Example

An enemy that walks back and forth, turns its shield on while the player is near, and frees itself when its health runs out - the script is on the enemy's root node, with a [Texture](../nodes/TextureNode.md) child named `Sprite` and a child named `Shield`.

```lua
---@class Patrol : ScriptInstanceBase
---@signal health_changed(health: integer) Took damage
---@signal died
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
        self.node:destroy()
    end
end

return Patrol
```

## Notes

- `get_position`, `set_position`, rotation and scale are local - relative to the parent. Compare nodes with different parents by `get_global_position()`. It is worked out before and after each frame's updates, so right after `set_position` it still has the old value.
- `ready()` runs once, after every node of the scene exists, parents before children - `get_node` finds the children, but their own `ready()` hasn't run yet. A node added later gets its `ready()` before the next update; a disabled one waits until it is enabled.
- `destroy()` waits for the end of the frame: the node stays until the end of the frame, so it is safe to call from its own `update`. Meanwhile the lookups no longer return it: `Scene.find_node`, `Scene.find_by_tag`, `Scene.find_by_uid`, `Scene.get_nodes`, `get_children`, `get_child` and `get_node` skip a node waiting to be removed (a node being removed still sees its own children). A pooled node goes back to its pool instead. A reference to a removed node stays safe - its getters return defaults and `get_name()` returns nil.
- `set_visible(false)` hides the node and its whole subtree - nothing in it draws, lights in it don't light, and UI widgets in it take no clicks or keys - but everything keeps updating (scripts, timers, animations, physics). To stop a branch altogether, use `set_enabled(false)`. `is_visible()` reads the node's own flag: it's true for a child of a hidden node. (Before #388 a hidden node's children still drew; see [API stability](../../engine/SCRIPTING.md#api-stability).)
- Emitting a name the node doesn't declare still works, but warns once per call site in the editor, Play from the editor and debug builds (release exports stay silent). Declare it on the node or in the script: `---@signal health_changed(health: number) Health went up or down` (the value's name and type, then a description).
- An `emit` value can be a boolean, number, string, node or table - a table arrives as the same table, not a copy. A handler added with `connect` gets `(value, source)`.
