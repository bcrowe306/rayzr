## What it's for

A Light Occluder blocks light without being a physics body: a wall painted
in the background, a pillar, a tree's canopy, a closed door's frame. Lights
with **Shadows** on cast its shadow; nothing collides with it. The whole
picture: [Lighting](../../engine/docs/lighting.md).

## When to use it

- **Art that should cast a shadow but isn't solid**: background walls,
  foliage, furniture the player walks behind.
- **A sprite's silhouette**: right-click a Sprite or Atlas Sprite in the
  Scene panel > **Make Light Occluder from Sprite** traces its opaque
  pixels into an occluder child.
- **Shadows only for some lights**: its **Layers** - it blocks only the
  lights on one of them.
- **Not** for things that should also collide: a physics body casts
  shadows by itself (its **Casts Shadows**).

## Using it

1. **Add Node** > *Light Occluder*. It starts with a 64-pixel box.
2. In the Inspector's **Shapes** section, change the shape (box, circle,
   capsule, polygon, segment...) or add more; **Edit in Viewport** drags
   their handles, like collision shapes.
3. **Layers**: the light layers whose lights it blocks (all by default;
   Project Settings > Light Layers names them).

The viewport draws occluders in violet, brighter when selected.

## How it works

- Each shape's outline casts a shadow away from every light with Shadows
  on that shares one of its layers, as a body's shapes do.
- A light whose **Ignore Parent Bodies** is on isn't blocked by an occluder
  it sits under.
- Traced occluders are convex polygons of up to 8 corners each (several for
  a complex outline), simplified to about a 64th of the sprite.
- Scripts read and set its layers with `occluder_get_layers()` /
  `occluder_set_layers({"World"})`; its shapes with the node's shape
  methods.

## Example

A door that blocks the light while closed and lets it through when opened.
The script is on the occluder.

```lua
---@class DoorShadow : ScriptInstanceBase
local DoorShadow = {}

function DoorShadow:set_open(open)
    -- Disabled nodes cast no shadow.
    self.node:set_enabled(not open)
end

return DoorShadow
```
