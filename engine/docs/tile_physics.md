# Tile map collision

A [Tile Map](../../docs/nodes/TileMapNode.md) with **Solid** on blocks
bodies with its painted tiles. This guide covers how its colliders are
built, each tile's own shape (slopes, halves, one-way platforms, polygons),
friction and bounce per tile, trigger tiles, and finding out exactly which
tile a body hit.

## How the colliders are built

When the scene starts (or Simulate), the map makes a static body child,
`<Name>_Colliders`. It isn't saved, and it isn't there while you edit.

- **Collider Shape: Boxes** (the default): the painted tiles are covered by
  the fewest boxes that fit, in sections of 16 x 16 cells. Tiles with a
  different friction or bounce get boxes of their own.
- **Collider Shape: Outline**: edge chains are traced around the solid
  tiles instead. Bodies slide along a whole floor or wall without catching
  on the seams between boxes, so use it for fast characters and rolling
  balls. It's for square grids (other grids use boxes).

When a script changes a tile (`tilemap_set_tile`, `tilemap_damage`...),
the colliders follow at the end of the frame. With Boxes, only the
sections the change touched are rebuilt, so digging through a big map
stays cheap. With Outline the chains are traced again. Either way the body
stays the same node, so anything standing on the map keeps standing.

Isometric maps use one slanted shape per run of tiles. Staggered and hex
maps use one shape per cell, the cell's own outline.

## Each tile's shape: the Collision page

Open the Tile Map tab and pick the **Collision** page. Click tiles on the
right (Shift or Cmd adds more), then set them on the left:

| Shape | |
|---|---|
| Full | The whole cell (every tile you haven't set). |
| None | No collision: decoration, background. |
| Half (top / bottom / left / right) | Half the cell. |
| Slope up right / up left (45°) | A ramp across one tile. |
| Ceiling right / left (45°) | The same ramps, upside down. |
| Slope ... low / high (22.5°) | A gentle ramp over two tiles: the low one, then the high one. |
| One-way platform | Solid from above only: jump up through it, land on it. |
| Custom polygon | A shape you draw on the zoomed tile: click to add a corner, drag one to move it, right-click to remove one. It must be convex, with up to 8 corners. |

Each tile can also have:

- **Friction** of its own: ice is 0.02, mud is 1.5. Leave it off to use
  the map's **Friction** (0.6 by default).
- **Bounce** of its own: a trampoline is 0.9. Leave it off to use the
  map's **Bounce**.
- **Trigger**: the tile detects bodies instead of blocking them (water,
  spikes, ladders). See below.

The tiles on the right show their shapes: green is solid, yellow is a
one-way top, blue is a trigger, and a dot means a friction or bounce of the
tile's own. It's all saved at once in the tileset's `.tileset.json`, so
every map using that tileset shares it.

Slopes, halves and polygons are for square grids. Other grids treat them
as full cells.

## Trigger tiles

A trigger tile has no collision. Instead, when a body goes into it the map
sends `tile_entered`, and when the body leaves it sends `tile_exited`.

```lua
local Player = {}

function Player:ready()
    local map = Scene.find_node("Level")
    map:connect("tile_entered", function(e)
        if e.other == self.node and map:tilemap_tile_data(e.tile, "kind") == "water" then
            self.swimming = true
        end
    end)
    map:connect("tile_exited", function(e)
        if e.other == self.node and #map:tilemap_trigger_cells(self.node) == 0 then
            self.swimming = false
        end
    end)
end

return Player
```

Each event's value is a table: `{x, y, tile, other}`. A body in two water
cells gets two `tile_entered` events; `map:tilemap_trigger_cells(body)`
lists the cells it is in now. If a script changes a trigger tile while a
body is in it, the body gets `tile_exited`. If the new tile is a trigger
too, the body stays in and gets no new event.

## Which tile was hit

`tile_hit` comes every time a body's shape starts touching one of the
map's collider shapes. It names the exact tile, even under a merged box or
an outline:

```lua
map:connect("tile_hit", function(h)
    -- h.x, h.y: the cell; h.tile; h.other: the body; h.point, h.normal
    if h.other.name == "Bullet" then map:tilemap_damage(h.x, h.y, 1) end
end)
```

A body sliding along one merged box only starts touching it once, so
`tile_hit` reports its first tile. For every step a character takes, use
its own collisions instead.

A **Character Mover** moves by sweeping its shape, not by physics
contacts, so it sends no `tile_hit`. Use its collision results:
`map:tilemap_cell_hit(contact)` gives the cell from a contact.

## Changing collision from a script

| Call | |
|---|---|
| `map:tilemap_tile_collision(tile)` | A tile's collision: `{shape, friction, bounce, trigger, points}` (no friction / bounce: the map's). |
| `map:tilemap_set_tile_collision(tile, t)` | Change it while the game runs, on this map only (not saved). The fields you leave out keep their value. `friction = false` goes back to the map's. |
| `map:tilemap_trigger_cells(body)` | The trigger cells a body is in now. |

```lua
-- Freeze the lake: water becomes slippery ice you can walk on.
map:tilemap_set_tile_collision(WATER, {trigger = false, shape = "full", friction = 0.02})
```

## Endless levels and LDtk

A chunked [Level Generator](level_generator.md) level gets the same
colliders per chunk. A chunk edited by a script rebuilds only the sections
that changed.

[LDtk levels](../LDTK.md) build their colliders from IntGrid collision
rules, with merged boxes, one-way bodies and trigger areas. When the rules
change and the level is rebuilt, its collider bodies are refilled in place
rather than replaced.
