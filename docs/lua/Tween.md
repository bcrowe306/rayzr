## Use it for

- **Juice on a property**: `Tween.to(node, property, value, duration, ease)` moves position, scale, rotation, a colour (`"tint"`) or any numeric property to a value - a button that grows on hover, a door that slides open, a hit flash.
- **Looping motion**: `{loops = -1, yoyo = true}` in the options bobs a pickup or pulses a light forever; `loops = 2` plays it three times in all.
- **Doing something when it ends**: `on_complete = function(node) ... end` frees a coin after its pop, or starts the next tween in a sequence. `delay` waits before starting.
- **Interrupting**: `Tween.cancel(id)` stops one tween where it is, `Tween.cancel_all(node[, property])` stops a node's tweens; `Tween.is_running(id)` says whether one still plays.
- **Shader parameters**: `"shader:<param>"` tweens a material parameter, such as a dissolve amount.
- **Your own animation**: `Tween.ease(name, t)` maps progress 0..1 through the same curves for motion you compute yourself.

## Example

A coin that bobs while it waits and, when the player touches it, pops up, fades out and frees itself - the script is on the coin's [Area](../nodes/AreaNode.md), with a [Texture](../nodes/TextureNode.md) child named `Sprite` at 0, 0.

```lua
---@class Coin : ScriptInstanceBase
local Coin = {}

function Coin:ready()
    self.sprite = self.node:get_node("Sprite")
    -- Up 4 px and back, forever (yoyo: every other run goes back).
    self.bob = Tween.to(self.sprite, "position", {0, -4}, 0.6, "in_out_sine", {loops = -1, yoyo = true})
end

---@param other Node?
function Coin:on_body_entered(other)
    if self.taken or not other or not other:has_tag("player") then return end
    self.taken = true
    Tween.cancel(self.bob)
    local x, y = self.node:get_position()
    Tween.to(self.node, "position", {x, y - 16}, 0.3, "out_back")
    -- Fade to transparent (colours 0..1), then free the coin.
    Tween.to(self.sprite, "tint", {1, 1, 1, 0}, 0.3, "linear", {
        delay = 0.1,
        on_complete = function() self.node:destroy() end,
    })
end

return Coin
```

## Notes

- A tween starts from the property's value when its delay ends, not when you call `Tween.to`. Two tweens on the same property both run and fight - cancel the old one first (`Tween.cancel_all(node, "position")`).
- Tweens pause with their node (pausing the game, `paused`) and end when the node is destroyed; a pooled node's tweens are cancelled when it goes back to its pool.
- `Tween.to` returns 0 (and logs a warning) when the node or the property doesn't exist - check the name. An unknown ease name starts no tween either (0, with a warning); `Tween.ease` returns nil for one.
- `rotation` is in degrees, positions in px local to the parent. Pass targets as plain lists (`{x, y}`, `{r, g, b, a}`).
- `Tween.cancel` and `cancel_all` don't call `on_complete`. To animate many keys over time, use an [Animation Player](../nodes/AnimationPlayerNode.md) - its keys use the same eases.
