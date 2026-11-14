# Changing tiles in the game

Tile maps aren't fixed: scripts can dig, build, break and move tiles while
the game runs, in a level you painted or one the
[Level Generator](level_generator.md) made. The map keeps up: its colliders,
pathfinding, terrain edges and a chunked level's memory follow every change.

## The tile API

On any [Tile Map](../../docs/nodes/TileMapNode.md):

| Call | |
|---|---|
| `map:tilemap_cell_at(pos)` | The cell under a world position. |
| `map:tilemap_get_tile(x, y)` | The tile there (-1: empty). |
| `map:tilemap_set_tile(x, y, tile)` | Paint a tile (-1 erases). |
| `map:tilemap_set_terrain(x, y, name)` | Make a cell a terrain, or empty it (nil), with its neighbours' edges re-picked. |
| `map:tilemap_cell_position(x, y)` | A cell's centre in the world. |
| `map:tilemap_neighbors(x, y)` | The cells around it. |

A **Solid** map rebuilds its colliders at the end of the frame, however
many tiles changed (just the 16 x 16-cell sections they're in), and
pathfinding sees the change. Tiles' own shapes, friction and trigger tiles:
[Tile map collision](tile_physics.md).

## Terrain edges follow (Retile on Edit)

Terrains (the Tile Map tab's Terrains layer) pick each cell's tile from its
neighbours: grass gets its edges and corners by itself. With **Retile on
Edit** on (a Tile Map property, on for new maps), `tilemap_set_tile` keeps
that true: dig a hole in a grass-topped wall and the grass around it gets
its new edges. `tilemap_set_terrain` does it whatever the setting, and
paints by terrain rather than tile index.

Tile maps in scenes made before this have Retile on Edit off, so their
scripts work as before.

## Tile data

Tiles can carry values for scripts: *breakable*, *health*, *sound*,
*slippery*. Define them on the Tile Map tab's **Data** page (fields with a
type and a default), pick tiles and set their values. They're kept in the
tileset's `.tileset.json`, so every map using that tileset shares them.

| Call | |
|---|---|
| `map:tilemap_get_data(x, y, field)` | A cell's value: its own, else its tile's, else the default. |
| `map:tilemap_set_data(x, y, field, value)` | Give one cell a value of its own: a cracked block's health left. It goes when the cell's tile changes. |
| `map:tilemap_tile_data(tile, field)` | A tile's value, by tile index (a tile being carried). |

## Breaking tiles

`map:tilemap_damage(x, y, amount)` lowers a cell's **health** field. The map
sends `tile_damaged`, and at 0 the tile goes and it sends `tile_destroyed`.
Cells without a health field (or a health of 0) can't be damaged - give
unbreakable tiles no health, or check `breakable` first.

## Events

| Event | Value |
|---|---|
| `tile_changed` | `{x, y, old, new}` - every cell a script changed, the neighbours Retile on Edit re-picked too. |
| `tile_damaged` | `{x, y, tile, amount, health}` |
| `tile_destroyed` | `{x, y, tile}` |
| `tile_hit` | `{x, y, tile, other, point, normal}` - a body's shape began touching the map's colliders: the exact tile it hit. |
| `tile_entered` / `tile_exited` | `{x, y, tile, other}` - a body went into / left a trigger tile ([Tile map collision](tile_physics.md)). |

Connect them in the Signals tab or with `map:connect(...)`. A generator
filling the map, or chunks coming in and going, send no `tile_changed` (the
generator has its own events).

`tile_hit` comes each time one of a body's shapes starts touching one of
the map's collider shapes, with the exact tile even under a merged box.
A body sliding along one box only starts touching it once. For a
projectile that's its impact. Character Movers move by sweeps, not
contacts, and send none: in a body's own `collision_started(other,
contact)` (or a mover's collision), `map:tilemap_cell_hit(contact)` gives
the cell.

## Picking up and carrying tiles

`map:tilemap_tile_rect(tile)` is where a tile is in the tileset image, and
`sprite:atlas_show_tile(map, tile)` shows it on an
[Atlas Sprite](../../docs/nodes/AtlasSpriteNode.md): the tile the player
carries or throws.

For blocks that need physics of their own (pushed, thrown, bouncing), use
components on the map instead: `map:tilemap_set_component(x, y, path)` puts
a node there, `tilemap_clear_component` takes it away.

## Endless levels remember

A chunked [Level Generator](level_generator.md#endless-levels-chunks) makes
a chunk again from its seed when it comes back near the camera. What
scripts changed in it - tiles set, components placed or cleared - is
remembered and put back. The chunk's colliders follow edits too.

To keep the changes in a save:

```lua
Save.set("edits", gen:levelgen_get_edits())   -- saving
gen:levelgen_set_edits(Save.get("edits", {})) -- loading (before or after generating)
gen:levelgen_clear_edits()                    -- a fresh level
```

Generating a level with another seed starts with no edits (unless
`levelgen_set_edits` was called for it).

## Example: dig, carry and place

The player digs the tile in front of them, picks up a tile, carries it and
puts it down. A `Carried` Atlas Sprite child shows what they hold; the map
is named `Ground` and has Retile on Edit on, so the terrain edges follow.

```lua
---@class Digger : ScriptInstanceBase
local Digger = {}

function Digger:ready()
    self.map = Scene.find_node("Ground")
    self.carried_sprite = self.node:get_node("Carried")
    self.carried_sprite:set_visible(false)
    self.carried = nil
    self.facing = 1
end

function Digger:target_cell()
    local cx, cy = self.map:tilemap_cell_at(self.node:get_global_position())
    return cx + self.facing, cy
end

function Digger:update(dt)
    if Input.is_action_pressed("move_left") then self.facing = -1 end
    if Input.is_action_pressed("move_right") then self.facing = 1 end
    local x, y = self:target_cell()
    if Input.is_action_pressed("dig") then
        -- Breakable tiles crack, then break (their health in the Data page).
        if self.map:tilemap_get_data(x, y, "breakable") then
            self.map:tilemap_damage(x, y, 1)
        end
    elseif Input.is_action_pressed("interact") then
        local tile = self.map:tilemap_get_tile(x, y)
        if self.carried == nil and tile >= 0 and self.map:tilemap_get_data(x, y, "movable") then
            self.carried = tile
            self.map:tilemap_set_tile(x, y, -1)
            self.carried_sprite:atlas_show_tile(self.map, tile)
            self.carried_sprite:set_visible(true)
        elseif self.carried ~= nil and tile == -1 then
            self.map:tilemap_set_tile(x, y, self.carried)
            self.carried = nil
            self.carried_sprite:set_visible(false)
        end
    end
end

return Digger
```

And on the map, a sound for each broken tile (its `sound` field):

```lua
---@class Ground : ScriptInstanceBase
local Ground = {}

---@param hit table {x, y, tile}
function Ground:on_tile_destroyed(hit)
    local sound = self.node:tilemap_tile_data(hit.tile, "sound")
    if sound then Audio.play_sound(sound) end
end

return Ground
```
