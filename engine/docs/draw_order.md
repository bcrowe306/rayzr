# Draw order: layers, Z index and Y-sort

What draws on top of what, from coarse to fine:

1. **Layer** (`Layer1` … `Layer8`): a higher layer always draws over a lower
   one. The camera draws the world layers it targets (1-7); `Layer8` isn't
   moved by the camera. For a HUD use a [Screen Layer](#huds-screen-layers).
2. **Z index** (an integer, default 0) inside a layer: higher draws later
   (on top). It is **relative**: a node's Z adds to its parent's, so a
   `Background` group at Z -10 keeps all its children behind.
3. **Y-sort** inside a node: with **Y Sort Children** on, its children draw
   by their Y position - lower on the screen = in front - each child
   together with its own children. This is the depth of top-down and
   isometric games: walk behind a tree, then in front of it.
4. Otherwise, the **scene tree order**: later siblings draw over earlier
   ones.

## HUDs: Screen Layers

A **Screen Layer** (Add Node > UI & Interface) draws everything under it in
**screen space**: after the world, on top of it, never moved by the camera.
Health bars, the score, a minimap frame, the pause button go under one.

- **Anchor**: the point of the screen it sits at - top left, top, top right,
  left, centre, right, bottom left, bottom, bottom right. Its position is an
  offset from that point. A score anchored **top right** at (-120, 16) stays
  120 px from the right edge however wide the screen is - with the
  [Expand](pixel_perfect.md#screen-fill) screen fill, a wider screen shows
  more world and the HUD stays at its edges.
- **One per corner**: Screen Layers can nest, and each anchors to the
  screen (not to its parent) - a `HUD` layer with a top-left health bar
  layer and a bottom-right buttons layer inside.
- Inside, order is as usual (layers, Z index, tree order); UI buttons and
  labels take the mouse in screen coordinates.
- **In the editor** it's drawn over the scene camera's frame, so you place
  the HUD where the player will see it (Home fits the game's view).

Recipe: Add Node > **Screen Layer**, set its Anchor to *Top Right*, add a UI
Label under it, move the label to (-160, 16); Play - scroll the camera, the
label stays put in the corner.

## In the editor

Select a node; the Inspector's Transform section has:

| Row | What it does |
|---|---|
| **Layer** | The drawing layer. |
| **Z Index** | Draw order within the layer (relative to the parent). |
| **Y Sort Children** | Draw this node's children by Y. |
| **Y Sort Offset** | (Shown when the parent Y-sorts.) Moves the line the node sorts by. The viewport draws it as a dashed **y sort** line while the node is selected. |

Clicking in the viewport picks what is drawn on top, so Z index and Y-sort
apply to selection too.

## Tutorial: a top-down forest

1. Add a `Node` named **World**, turn on **Y Sort Children**.
2. Put the player, the trees and the rocks under **World** (a sprite each,
   with any children - a shadow, a weapon - under them).
3. Sprites are positioned by their centre: a tree 96 px tall sorts by its
   middle, so the player passes "behind" it too early. Select the tree and
   set **Y Sort Offset** to `48` (half its height): the dashed line moves to
   its trunk's base. Do the same for the player (its feet).
4. Run: walking above a tree's base draws the player behind it, below the
   base in front. A weapon under the player moves with it (a child sorts
   with its parent).

Ground, water and paths go outside **World** (or on a lower layer) so they
never cover characters; a roof that must cover everything can go in
**World** with a large **Z Index**, or on a higher layer.

### Isometric

The same with the sorting line on the tile's bottom corner: set each
object's origin (or **Y Sort Offset**) to where it touches the ground.

### Nested sorting

A Y-sorted node inside a Y-sorted node (a **Camp** with tents inside
**World**) sorts its own children, and the whole camp moves as one item in
**World**'s order, at the camp's Y.

## Scripting

They are node properties (`get_property` / `set_property`, or as fields):

```lua
-- Draw the hit flash above everything else in its layer for a moment.
function Enemy:on_hit()
    self.node.zIndex = 100
    self.flash = 0.1
end

function Enemy:update(dt)
    if self.flash then
        self.flash = self.flash - dt
        if self.flash <= 0 then
            self.node.zIndex = 0
            self.flash = nil
        end
    end
end

-- A jump: the sprite (a child) rises, the Player node keeps its Y, so it
-- still sorts by where it stands.
function Player:update(dt)
    local h = self.jump_height or 0      -- 0 on the ground
    self.node:get_node("Sprite").position = {0, -h}
end

world:set_property("y_sort", true)
tree:set_property("y_sort_offset", 48)
```

## Saved as

```json
{"type": "Node", "name": "World", "y_sort": true, ...}
{"type": "TextureNode", "name": "Tree", "y_sort_offset": 48, ...}
{"type": "TextureNode", "name": "Sky", "z_index": -1, ...}
```

(Written only when not the default.)

## Performance

The renderer walks the tree once per frame and buckets drawables by layer
(16-byte items: the node pointer, its global Z and its Y key). Sorting is
only paid where it is used: a stable sort of each Y-sorted node's children
(their subtrees move as blocks), and a stable sort of a layer only if
something in it has a non-zero Z index. After sorting, sprites sharing a
texture are still batched together wherever that cannot change the
picture (`batching.odin`), so Y-sorting a forest of the same tree texture
keeps one draw call per run of non-overlapping trees.

## Limits

- A **TileMap** draws as one item: tall tiles (tree tops) don't interleave
  with characters. Place tall objects as nodes (or LDtk entities) under the
  Y-sorted node.
- Sorting uses the global Y of each direct child; give a child its own
  container node if its sprite moves vertically (jumps), as above.
