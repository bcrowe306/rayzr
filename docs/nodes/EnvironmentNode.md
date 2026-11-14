## What it's for

The Environment sets the scene's look: the **ambient** light where no light
reaches, **Overbright** lights, **Bloom**, and the light map's resolution.
Because it's a node, it can be animated, scripted, swapped or put in a
component. The whole picture: [Lighting](../../engine/docs/lighting.md).

## When to use it

- **A dark scene for lights to light**: set its **Ambient** to a night or
  cave colour.
- **Day and night**: key its **Ambient** in the Animation tab, drive it
  with an [Oscillator](OscillatorNode.md), or fade it from a script.
- **Glow**: **Bloom** makes bright lights and glowing art (emission) bleed
  light around them; **Overbright** lets lights go brighter than the art.
- **Many lights, big screens**: **Half Resolution** builds the light map at
  half size.

## Using it

1. **Add Node** > *Environment*. It starts neutral: a white ambient (the
   scene as drawn), no bloom.
2. Set **Ambient** to a dark colour; add [Lights](LightNode.md).
3. Turn on **Overbright** and **Bloom** to taste: **Threshold** (how bright
   a pixel must be to glow), **Strength**, **Radius** (px).

## How it works

- The first enabled Environment in the scene applies; without one, the
  scene's **Settings** tab ambient does (the Settings tab points to the
  Environment when there is one).
- **Overbright** stores the light map at half and shows it doubled: a light
  with Energy above 1 overexposes the art, up to twice as bright.
- **Bloom** runs first in the post chain, before the scene's
  [Post Effects](PostEffectNode.md): the frame's bright parts, blurred,
  added back.
- `Scene.get_environment()` returns it; every setting has
  `env_get_<setting>` / `env_set_<setting>`, and `env_fade_ambient(color,
  seconds)` fades the ambient. `Scene.set_ambient` sets its ambient.

## Example

A day-night cycle: the ambient fades between day and night every minute.
The script is on the Environment.

```lua
---@class DayNight : ScriptInstanceBase
local DayNight = {}

function DayNight:ready()
    self.night = false
    self:turn()
end

function DayNight:turn()
    self.night = not self.night
    local target = self.night and "#1c1c38" or "#ffffff"
    self.node:env_fade_ambient(target, 30, function() self:turn() end)
end

return DayNight
```
