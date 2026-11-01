## What it's for

A Texture Sprite draws one image in the world: a ship, a tree, a crate, a
background picture. It's the plain sprite: one texture, drawn at its own
size, around its origin.

## When to use it

- **A still image**: props, characters that don't animate, pickups, a
  background picture.
- **Swapping the whole image** from a script (a damaged ship, a lit lamp):
  `set_texture`.
- **Showing a [Viewport](ViewportNode.md)'s picture** (an in-world screen,
  a security monitor): pick `viewport:<name>` in **Texture**.
- **Not** for one cell of a sprite sheet or atlas: use an
  [Atlas Sprite](AtlasSpriteNode.md).
- **Not** for animation: use an [Animation Player](AnimationPlayerNode.md),
  a [Frame Animator](FrameAnimationNode.md) or an
  [Aseprite Sprite](AsepriteNode.md).
- **Not** for a panel or button that stretches: use a
  [Nine Slice Sprite](NineSliceNode.md). For a repeating background, use a
  [Parallax Background](ParallaxNode.md). For SVG art, use a
  [Vector Shape](VectorShapeNode.md).

## Using it

1. Drag an image from Assets into the viewport. This makes a Texture Sprite
   where you drop it. Or use **Add Node** (Ctrl+A) > *Texture Sprite*, or
   right-click an image in Assets > **Add Sprite to Scene**.
2. Pick the image in the Inspector's **Sprite** section > **Texture** (it
   lists the files under `textures/`). The section shows the image's
   **Size** and a preview. To change the image of the selected sprite,
   right-click another image in Assets > **Use on Selected Sprite**.
3. Move, rotate and scale it with the viewport tools or the **Transform**
   section. **Origin** (in Transform) is the point of the image that sits at
   the node's position.
4. **Tint** (the Node tab's **Properties** section) colours it or fades it.
5. **Layer** and **Z Index** (in Transform) decide what it draws over. See
   [Draw order](../../engine/docs/draw_order.md).

## How it works

- It draws the whole image at the image's size in pixels, times the node's
  scale. There is no separate size setting: scale the node to make it
  bigger or smaller.
- **Origin** is a fraction of the image: (0.5, 0.5), the centre, is the
  default; (0.5, 1) is the bottom centre (feet). The sprite rotates and
  scales around it. `texture_set_origin(x, y)` sets it in pixels of the
  image instead.
- A negative scale mirrors the image around its origin. Flip a character
  with a scale of (-1, 1).
- **Tint** multiplies the image's colours. White leaves it unchanged; a
  lower alpha fades it.
- Filtering (sharp or smooth pixels) is a setting of the image, not of the
  node: select the image in Assets and pick the filter under **Import** in
  the Preview panel (Point by default, for crisp pixel art; Bilinear or
  Trilinear for smooth scaling). See
  [Import settings](../../engine/docs/import_settings.md). With **Atlas** on
  there, the image is packed into a sprite atlas when you export, so many
  sprites draw in one batch ([Sprite atlases](../../engine/docs/atlas.md)).
- With no image picked, it draws nothing.
- New sprites are on Layer1 with Z index 0.

## Example

A ship that faces the way it moves and changes its image when damaged.
The script is on the ship; the sprite is its child named `Sprite`.

```lua
---@class Ship : ScriptInstanceBase
local Ship = {}

Ship.properties = {
    damaged_skin = { type = "texture", default = "textures/Spaceship_2.png", label = "Damaged Skin" },
}

function Ship:ready()
    self.sprite = self.node:get_node("Sprite") ---@type TextureNode
end

function Ship:update(dt)
    local dir = Input.get_axis("move_left", "move_right")
    if dir ~= 0 then
        -- Mirror the image around its origin to face left or right.
        self.sprite:set_scale(dir < 0 and -1 or 1, 1)
    end
end

function Ship:take_damage()
    self.sprite:set_texture(self.damaged_skin) -- false if it can't be loaded
    self.sprite:set_property("tint", "#ff9090")
end

return Ship
```

`texture_get_size()` returns the image's width and height in pixels, and
`texture_get_path()` the path it was loaded from.

## Screenshot

![A Texture Sprite in the editor](../images/node_TextureNode.png)
