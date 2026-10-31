## Use it for

- **Following something from a script**: `Camera.set_target(node)` follows one node; `Camera.set_target(nil)` stops. A **Follow Target** picked in the Inspector needs no script at all.
- **Framing several nodes**: `Camera.add_target` / `remove_target` build a group the camera centres on - with **Auto Zoom** on, it zooms out to keep them all on screen (co-op, a boss fight). `clear_targets` drops them all.
- **Cutscenes and points of interest**: `Camera.set_target_position(x, y)` sends it to a world point, `set_zoom` and `set_rotation` ease it there when the camera's smoothing is on.
- **Hits and explosions**: `Camera.shake(strength, duration)` plays the camera's **Shake Preset**; with [Advanced Cameras](../nodes/AdvancedCameraNode.md), `Camera.add_trauma` stacks shake hit after hit.
- **A punch**: `Camera.kick(x, y)` knocks the view a few pixels that way and springs it back - the recoil of a shot or the push of a hit, without shaking.
- **Rooms and level edges**: `Camera.set_limits(left, right, top, bottom)` keeps the view inside a rectangle of the world; `clear_limits` lets it roam.
- **Mouse aiming and on-screen markers**: `screen_to_world` turns the mouse position into a world point, `world_to_screen` the other way; `get_visible_world_bounds` is the part of the world on screen.

## Example

A boss arena: when the player walks into it, the camera frames the boss too, stays inside the arena and shakes - the script is on an [Area](../nodes/AreaNode.md) covering the arena.

```lua
---@class BossArena : ScriptInstanceBase
local BossArena = {}

function BossArena:ready()
    self.started = false
end

---@param other Node?
function BossArena:on_body_entered(other)
    if self.started or not other or not other:has_tag("player") then return end
    self.started = true
    local boss = Scene.find_node("Boss")
    if boss then
        -- The player (the follow target) joins the group too.
        Camera.add_target(boss, {weight = 2, radius = 120})
    end
    Camera.set_limits(0, 1920, 0, 1080) -- the arena, in world px
    Camera.shake(8, 0.5)
end

---@param other Node?
function BossArena:on_body_exited(other)
    if not other or not other:has_tag("player") then return end
    local boss = Scene.find_node("Boss")
    if boss then Camera.remove_target(boss) end
    Camera.clear_limits()
    self.started = false
end

return BossArena
```

## Notes

- Every function works on the scene's current [Camera 2D](../nodes/CameraNode.md) (**Is Current**). With no camera they do nothing, and the getters return defaults (zoom 1, position 0, 0).
- `get_zoom` is the zoom the camera is easing to; `get_rotation` is the rotation right now. `set_zoom` is kept between the camera's **Min Zoom** and **Max Zoom**.
- The offset (`set_offset`) is in world px and moves the point the camera looks at - `Camera.set_offset(0, -40)` shows more above the player.
- `add_trauma` and `get_active` are for [Advanced Cameras](../nodes/AdvancedCameraNode.md); without one, `add_trauma` does nothing and `get_active` returns nil.
- A camera node's own methods (`cam:camera_shake()` and the rest) do the same on one particular camera.
