## What it's for

A Light brightens the scene around it: a torch, a lamp, a glowing crystal, a
flashlight cone, the sun. Lights only show when the scene is darker than
its art: set the ambient (an [Environment](EnvironmentNode.md) node, or the
scene's Settings) to a dark colour, then add lights to bring places back.
Lights cast soft or hard shadows from physics bodies and
[Light Occluders](LightOccluderNode.md). The whole picture:
[Lighting](../../engine/docs/lighting.md).

## When to use it

- **Night, caves, interiors**: a dark ambient with torches and lamps.
- **A flashlight or a searchlight**: a **Spot** light, aimed by the node's
  rotation.
- **Shadows behind walls and crates**: **Shadows** on; the walls are
  physics bodies.
- **Daylight and long shadows**: a **Directional** light, the sun, lights
  everything from one direction.
- **Art with depth**: give sprites and tilesets normal maps (see Normal maps
  below) and the light shades their bumps and edges as it moves.
- **Glowing things in the dark** are emission, not lights: a node's
  **Emission** (Inspector > Lighting) or an `<image>_e.png` map. For lights
  brighter than the art, turn on an [Environment](EnvironmentNode.md)'s
  **Overbright** (and **Bloom**).
- **Not** for tinting the whole screen: set the ambient alone (no lights),
  or use a [Post Effect](PostEffectNode.md).

## Using it

1. Darken the scene: add an [Environment](EnvironmentNode.md) and set its
   **Ambient**, or in the Scene panel's **Settings** tab set **Ambient** (or
   pick a preset: *Dusk*, *Night*, *Dark*; *Day (unlit)* turns it off).
   White means unlit: the scene is drawn as it is.
2. **Add Node** (Cmd+A / Ctrl+A) > *Light* - a warm point light with a
   256-pixel radius - or a preset: *Torch* (flickers), *Lamp*,
   *Flashlight* (a spot with a ring texture), *Sun*, *Neon* (pulses).
3. In the Node tab's **Properties** section:
   - **Kind**: *Point* shines all round, *Spot* shines in a cone, and
     *Directional* is the sun, one direction over the whole view.
   - **Color**, **Energy** (brightness), **Radius** (pixels), and
     **Falloff** (how it fades to the edge).
   - **Spread**: a spot's half-angle, in degrees.
   - **Texture**: a light texture shaping the light - a project image or a
     built-in one (ring, window, blinds, noise).
   - **Layers**: the light layers it lights (Project Settings > Light
     Layers names them; a node's **Lit By** decides which light it).
   - **Shadows**, **Softness** (edge blur, 0 = hard), **Shadow Strength**
     (how dark) and **Ignore Parent Bodies** (the bodies it sits in don't
     block it).
   - **Flicker** / **Pulse** and their speeds: a flame or a neon sign
     without a script.
   - **Height**: how far above the ground it is, for normal maps.
   - A sun's **Elevation** (degrees above the ground) and **Shadow Length**.
4. For a spot light or the sun, rotate the node to aim it: at rotation 0
   it points right (a sun at rotation 0 shines from the left).
5. Selected, the light shows its radius (or its cone) in the viewport. The
   toolbar's sun button switches the lighting preview on and off.

## How it works

- The scene is drawn first. Then a light map is built: it starts as the
  ambient colour and each light adds its colour on top. The light map
  multiplies what was drawn. Where it reaches white, you see the art as
  drawn; it never gets brighter than that.
- Lights light the layers the scene's camera draws (Layer1 to Layer7 by
  default). Layer8 and anything under a
  [Screen Layer](ScreenLayerNode.md) (the HUD) is never darkened.
- **Energy** multiplies the colour (0 to 8); each channel stops at full
  brightness. Overlapping lights add up.
- **Falloff** 1 fades evenly to the edge, 2 (the default) fades smoothly,
  higher values keep the light tight around its centre.
- The radius grows with the node's larger scale axis.
- **Shadows**: shapes of Static, Dynamic and Kinematic bodies and Character
  Movers with **Casts Shadows** on block the light, except sensors (trigger
  areas), and so do [Light Occluders](LightOccluderNode.md) on its layers.
  The colliders a [Tile Map](TileMapNode.md) or an
  [LDtk level](LdtkLevelNode.md) builds cast shadows too (the editor shows
  them before the game runs). Each light's shadows only darken that light's
  own contribution. **Softness** blurs their edges; lights from before soft
  shadows load hard.
- A light whose circle is outside the view is skipped. Each visible light is
  one extra pass, so dozens of large shadowed lights cost more than a few.
- A **Directional** light has no position or radius: it adds its colour
  over the whole view. Its shadows run parallel, away from the sun, for
  **Shadow Length** pixels (0: to the edge of the view).
- Scripts set the ambient with `Scene.set_ambient(r, g, b)` (0 to 1; the
  Environment's when there is one) and read it with `Scene.get_ambient()`.
  Every setting has `light_get_<setting>` / `light_set_<setting>`; see also
  `light_fade`, `light_apply_preset` and the [Lighting](../lua/Lighting.md)
  module.

## Normal maps

Normal-mapped art is shaded by each light's direction, so a ball looks
round and a brick wall shows its mortar.

- **A normal map for an image** is `<image>_n.png` next to it, for example
  `hero.png` and `hero_n.png`. It's found by itself. In Assets, the
  image's import settings can point at another file (**Normal**), turn it
  off (*None*), or flip the green channel for DirectX-style maps (**Green
  Down**).
- **No normal map?** Right-click the image in Assets > **Generate Normal
  Map...**. It builds one from the sprite's outline (a bevel) and its
  brightness (painted detail), with a preview lit by a light that follows
  the mouse. **Save** writes `<image>_n.png`.
- **Shininess** (0 to 1, on sprites, animations, nine slices, tile maps and
  LDtk levels) adds a glint where a light hits. A specular map,
  `<image>_s.png` (white is shiny), sets it per pixel.
- **Height** decides the light's angle: a low light rakes across the
  bumps and a high one lights them evenly. A sun's **Elevation** does the
  same.
- **What's shaded**: sprites (Texture, Atlas, Aseprite), animation frames,
  nine slices, tile maps and LDtk tiles. Art without a normal map is lit
  exactly as before, and so is text, vector art and particles.
- **The cost**: when the project has normal maps and the scene is lit,
  the world's sprites are drawn once more into a normal buffer, which the
  lights read. Scenes without lights pay nothing. In exported games,
  normal-mapped images keep their own textures (they aren't packed into
  the sprite atlas).

## Example

A torch that flickers, and a cave that gets dark when the player enters.
The first script is on the Light.

```lua
---@class Torch : ScriptInstanceBase
local Torch = {}

Torch.properties = {
    energy = { type = "float", default = 1.2, label = "Energy" },
    flicker = { type = "float", default = 0.25, label = "Flicker" },
}

function Torch:ready()
    self.node:light_set_color(1.0, 0.75, 0.4)
    self.wait = 0
end

function Torch:update(dt)
    self.wait = self.wait - dt
    if self.wait > 0 then return end
    self.wait = 0.05 + math.random() * 0.1
    self.node:light_set_energy(self.energy + (math.random() - 0.5) * self.flicker)
end

return Torch
```

On a Trigger Area at the cave's entrance:

```lua
function CaveEntrance:on_body_entered(body)
    if body ~= nil and body:get_name() == "Player" then
        Scene.set_ambient(0.08, 0.08, 0.12)
    end
end
```

`light_get_energy()` reads the energy back and `light_set_radius(r)` changes
the reach.

## Screenshot

![A point light over a sprite, with the scene's ambient at Night](../images/node_LightNode.png)
