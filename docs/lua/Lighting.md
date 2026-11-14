## Use it for

- **Stealth and light-based gameplay**: `Lighting.brightness_at(x, y)` (or a Vec2) says how lit a point is - 0 dark, 1 fully lit, up to 2 with Overbright - with shadows counted. Pass light layers to count only some lights. It returns the light's colour too.
- **Every light at once**: `Lighting.get_lights()` lists the scene's enabled lights - dim them all for a blackout, or find the nearest.
- **Comparing lit and unlit**: `Lighting.set_enabled(false)` shows the scene as drawn (no ambient, lights, emission or bloom); `Lighting.is_enabled()` reads it back.
- **Lights from scripts**: every Light setting has a getter and setter on the light (`light:light_set_softness(8)`, `light:light_get_layers()`), plus `light:light_fade(energy, seconds[, on_done])` and `light:light_apply_preset("Torch")`. `Scene.create_light("Torch", parent)` makes one from a preset.
- **The scene's look**: `Scene.get_environment()` returns the Environment node - `env:env_set_bloom(true)`, `env:env_fade_ambient("#101024", 3)` for dusk. `Scene.set_ambient` sets its ambient when there is one.
- **Glow and layers on any node**: `node:set_emission(color, strength)`, `node:set_ignore_lighting(true)`, `node:set_lit_layers({"Player"})`.

The guide: [Lighting](../../engine/docs/lighting.md).

## Example

A guard that only notices the player outside the shadows, a flickering torch the player can blow out, and night falling when the level starts. The script is on the guard; the scene has an Environment, a Light named `Torch` and the player tagged `player`.

```lua
---@class Guard : ScriptInstanceBase
local Guard = {}

function Guard:ready()
    -- Night falls over 8 seconds.
    local env = Scene.get_environment()
    if env then env:env_fade_ambient("#141428", 8) end
    self.torch = Scene.find_node("Torch")
    self.player = Scene.find_by_tag("player")[1]
end

function Guard:update(dt)
    if not self.player then return end
    local x, y = self.player:get_global_position()
    -- Seen only where it's lit (shadows count).
    if Lighting.brightness_at(x, y) > 0.35 then
        Log.info("The guard spots you!")
    end
end

-- Called by the player's "blow out" action.
function Guard:blow_out_torch()
    if not self.torch then return end
    self.torch:light_set_flicker(0.8)
    self.torch:light_fade(0, 0.6, function(light) light:set_enabled(false) end)
end

return Guard
```
