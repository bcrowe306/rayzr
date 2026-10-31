## Use it for

- **Pausing**: `set_paused(true)` stops nodes with pause mode "pausable" (the default) and physics; nodes set to "always" keep running, so a pause menu still works. `is_paused` tells you where you are.
- **Fullscreen**: `set_fullscreen` / `is_fullscreen` for an options menu or a hotkey.
- **Timing**: `get_time` for effects that follow the clock (a bob, a blink), `get_fps` for a debug readout. In `update(dt)` use the `dt` you are given; `get_delta_time` is for code outside `update`.
- **Screen sizes**: `get_virtual_size` is the size the game draws at (Project Settings > Video) - use it to place things on screen. `get_window_size` is the real window in screen pixels.
- **Game feel**: `set_time_scale(0.5)` runs the whole game at half speed; `set_time_scale(0.3, "enemy")` slows only the nodes tagged *enemy* (and their children). `hit_stop(0.08)` freezes the game - or only some tags - for a moment of real time on a heavy hit, and `slow_motion(0.25, 1.2)` eases down to a quarter speed and back. UI nodes, cameras and nodes set to "always" keep real time.

## Example

A debug HUD that shows the frame rate, pauses with **pause** and toggles fullscreen with F11. The script is on a [Text](../nodes/TextNode.md) node under a [Screen Layer](../nodes/ScreenLayerNode.md), set to keep running while paused.

```lua
---@class DebugHud : ScriptInstanceBase
local DebugHud = {}

function DebugHud:ready()
    -- Keep this script running while the game is paused.
    self.node:set_pause_mode("always")
    local _, vh = Engine.get_virtual_size()
    self.node:set_position(8, vh - 24)
end

function DebugHud:update(dt)
    if Input.is_action_pressed("pause") then
        Engine.set_paused(not Engine.is_paused())
    end
    if Input.is_key_pressed("F11") then
        Engine.set_fullscreen(not Engine.is_fullscreen())
    end

    local text = "FPS: " .. Engine.get_fps()
    if Engine.is_paused() then text = text .. "  (paused)" end
    self.node.text = text
end

return DebugHud
```

## Notes

- **A paused node gets no `update`.** The script that unpauses must be on a node with pause mode "always" (`node:set_pause_mode("always")`, or the Inspector), or it can never unpause.
- **Fullscreen is applied on the next frame**, as a borderless window the size of the screen. The game is scaled to fit; `get_virtual_size` stays the same unless Screen Fill is *Expand*.
- `get_time` keeps counting while the game is paused.
- **Time scale reaches everything game-side**: physics, animations, tweens and every script's `dt`. Hit-stop and slow motion count down in real time, so they end on time whatever the scale. A tag's scale multiplies the game's, and a frozen tag's bodies stop too.
