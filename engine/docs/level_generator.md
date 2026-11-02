# Procedural levels (level generator)

A **generator** builds a level from a graph of nodes, in the style of the
Gaea add-on for Godot: some nodes make a grid of values (noise, random
fill, shapes), others change it (threshold, cave smoothing, blur, combine),
and the **tile output** turns values into tiles and writes them into a
TileMap. The same generator and **seed** always give the same level, on
every platform - so a seed is a level you can share, replay or test.

So far (#142): the generator file, the nodes (terrain, caves, rooms and
corridors, walkers), placing entities, TileMap and LDtk output, your own
nodes (Lua or Odin), the **Level Generator** node that makes levels in
the game, the Lua module and the **Level Generator** window in the editor.

## In the editor

**Assets > + > New Level Generator** creates `levels/new_level.levelgen.json`
(a cave) and opens it in the **Level Generator** window; double-click any
`.levelgen.json` to open it. The window docks like any panel.

- **The canvas** shows the nodes, each with a thumbnail of its grid (a
  tile output shows its tiles in colours; a red border: the node can't be
  computed - its error is in the side panel). Drag a node by its title;
  drag from a node's **output** (the green dot on its right) onto another's
  **input** (a dot on its left) to connect them - a link that would make a
  loop is refused; right-click an input to disconnect it. Right-click the
  canvas to add a node; right-click a node to duplicate it, delete it or
  use it as the output. Delete removes the selected node. The wheel pans,
  Ctrl/Cmd+wheel zooms, F frames everything.
- **The side panel**: the level's **size**, **seed** (the dice picks a new
  one) and **output**; the selected node's parameters and, for a tile
  output, its **Tileset** (the picture its tile numbers count in; the grid
  button takes the tileset and tile size of the TileMap selected in the
  scene), its **Layer**, and its **rules** (a range and tiles: `3, 4` picks
  one of them per cell - or **Pick** them from the tileset: click tiles to
  add or remove them; the rule shows them as small pictures); a large
  **preview** of the selected node (or the output). A tile output with a
  tileset previews with its real tiles.
- **The toolbar**: **Save** (Ctrl/Cmd+S), **Undo** / **Redo**
  (Ctrl/Cmd+Z, Ctrl/Cmd+Shift+Z: every change), and **Apply to TileMap**,
  which writes the level into the TileMap selected in the scene - baked
  into the scene to paint over by hand; the scene's undo takes it back.

Closing the window with unsaved changes asks first.

The previews are made on a worker thread after each change, so the window
stays responsive while you drag a value: only the nodes the change reaches
are computed again (the rest are kept from the last time). Script files are
read when the generator opens, when a node's script is picked, and on
**Reload**. Levels up to 1024 x 1024 cells are previewed.

## Speed

A generator is computed node by node, each node once: the heavy nodes
(cellular automaton, blur, dilate / erode, noise, random fill) share their
rows among a few worker threads on big enough grids, and work on flat rows
- the automaton on bytes with a border of cells all round, blur as two
sliding sums (any radius costs the same), noise from a precomputed lattice.
A 256 x 256 cave with noise, blur and scatter takes about 1.5 ms in an
optimized build (`scripts/bench.sh engine`, `bench_level_gen`).

Builds without optimization (`task editor:build`, `task run`) are about 8x
slower at this kind of work: to play-test, use **`task editor:run:fast`**
(the editor and the Play game built with `-o:speed`), as exported games and
packaged editors are.

## A cave level

```json
{"size": [64, 40], "seed": 7, "nodes": [
  {"id": 1, "type": "random_fill", "params": {"density": 0.48}},
  {"id": 2, "type": "cellular", "inputs": {"in": 1}, "params": {"iterations": 5}},
  {"id": 3, "type": "border", "params": {"width": 1}},
  {"id": 4, "type": "combine", "inputs": {"a": 2, "b": 3}, "params": {"op": "max"}},
  {"id": 5, "type": "tile_output", "inputs": {"in": 4},
   "rules": [{"min": 0.5, "max": 1, "tiles": [12, 13, 14]}]}
]}
```

Random fill scatters walls; the cellular automaton smooths them into cave
walls and open rooms; the border closes the edges; the tile output puts one
of tiles 12-14 (picked at random, the same for a seed) on every wall cell.
Save it as `levels/caves.levelgen.json` and generate from a script:

```lua
function Level:ready()
    local ok, why = LevelGen.generate("levels/caves.levelgen.json", self.node:get_node("Ground"), Save.get("seed", 7))
    if not ok then Log.error(why) end
end
```

The TileMap (with a tileset, **Solid** on for colliders) takes the
generator's size and its cells become the tiles; its colliders are rebuilt.

## Terrain (a side view)

```json
{"size": [120, 40], "seed": 3, "nodes": [
  {"id": 1, "type": "gradient", "params": {"direction": "vertical"}},
  {"id": 2, "type": "noise", "params": {"scale": 18, "octaves": 4}},
  {"id": 3, "type": "remap", "inputs": {"in": 2}, "params": {"to_min": -0.25, "to_max": 0.25}},
  {"id": 4, "type": "combine", "inputs": {"a": 1, "b": 3}, "params": {"op": "add"}},
  {"id": 5, "type": "tile_output", "inputs": {"in": 4}, "rules": [
     {"min": 0.55, "max": 0.62, "tile": 1},
     {"min": 0.62, "max": 9, "tile": 2}]}
]}
```

A top-to-bottom ramp plus noise makes rolling ground: values from 0.55 get
grass (tile 1) and deeper ones dirt (tile 2); above stays empty.

## The file

| Key | |
|---|---|
| `size` | `[width, height]` in cells (1-4096). |
| `seed` | The default seed (scripts can pass another). |
| `output` | The id of the node whose result is the level (default: the last tile output). |
| `nodes` | Each with an `id` (a positive number), its `type`, `inputs` (port -> id of the node it reads), `params` (missing ones take their defaults), and for the tile output `rules`; `pos` is where the editor draws it. |

Every port carries a grid of numbers the size of the level - usually 0
(empty / low) to 1 (solid / high). An input that isn't connected reads 0
everywhere. A node may feed any number of others (computed once); a cycle
is an error.

## Nodes

**Generators**

| Type | Parameters | |
|---|---|---|
| `constant` | `value` (1) | The same value everywhere. |
| `noise` | `scale` (16), `octaves` (3), `persistence` (0.5), `seed` (0) | Smooth value noise (fBm), 0..1. |
| `random_fill` | `density` (0.45), `seed` (0) | Each cell 1 with that chance, else 0. |
| `gradient` | `direction`: `horizontal` (0 left .. 1 right), `vertical` (0 top .. 1 bottom), `radial` (1 centre .. 0 corners) | A ramp. |
| `border` | `width` (1) | 1 within that many cells of the edge. |
| `rect` | `x`, `y`, `w`, `h` (8), `value` (1) | A filled rectangle. |
| `rooms` | `min_size` (4), `max_size` (10), `corridor` (1), `seed` (0) | A dungeon: the level split in two again and again (BSP), a room in each part, corridors joining every split - every room reachable. 1 = floor (invert it for walls). |
| `walker` | `steps` (400), `walkers` (1), `brush` (1), `seed` (0) | Random walks from the centre ("drunkard's walk"): winding tunnels and caverns. 1 = walked. |
| `lines` | `count` (6), `min_length` (6), `max_length` (20), `thickness` (1), `direction`: `horizontal`, `vertical`, `both` (each line one or the other; default), `any` (any angle), `seed` (0) | Random lines: platforms, ledges, walls, cracks. Each fits inside the level (one longer than it is clipped). |
| `rectangles` | `count` (5), `min_size` (4), `max_size` (12), `thickness` (1), `filled` (false), `seed` (0) | Random rectangles, outlines `thickness` cells wide or filled: rooms, ruins, crates. Each side's length is picked in the range. |
| `circles` | `count` (5), `min_radius` (3), `max_radius` (8), `thickness` (1), `filled` (false), `seed` (0) | Random rings or discs: craters, arenas, pools. A cell is in when its centre is within radius + 0.5 of the circle's. |

The shape nodes draw 1 on the shape and 0 elsewhere (overlapping shapes
merge). Mix them with the rest: `combine` (max) adds ledges to a cave,
(subtract) cuts rooms out of rock; `dilate` thickens them afterwards.

**Modifiers** (input `in`, or `a` and `b`)

| Type | Parameters | |
|---|---|---|
| `threshold` | `value` (0.5), `invert` (false) | 1 at or above the value, else 0. |
| `invert` | | 1 - value. |
| `remap` | `from_min`, `from_max` (0, 1), `to_min`, `to_max` (0, 1) | One range onto another (clamped). |
| `blur` | `radius` (1) | The average of each cell's square of neighbours. |
| `cellular` | `iterations` (4), `birth` (5), `survive` (4), `edge_solid` (true) | Cave smoothing: an empty cell with at least `birth` solid neighbours (of 8) becomes solid, a solid one with fewer than `survive` empties. |
| `dilate` / `erode` | `iterations` (1) | Grow / shrink solid areas a cell at a time. |
| `combine` | `op`: `add`, `subtract`, `multiply`, `min`, `max`, `mask` (a where b is solid), `average` | Two grids into one. |
| `scatter` | `chance` (0.05), `spacing` (4), `seed` (0) | Random points (1), at least `spacing` cells apart - on the input's solid cells when it is connected, anywhere otherwise. |
| `surface` | `side`: `top` (empty cells with solid below: ground to stand on), `bottom` (solid above: ceilings), `any` | Empty cells against the input's solid ones. |

**Your own** (see [Your own nodes](#your-own-nodes))

| Type | Parameters | |
|---|---|---|
| `script` | `p1`..`p4` (0), `seed` (0); inputs `a`, `b`; `script` (a `.lua` file) | A Lua function computes the grid. |
| *(registered)* | its own | A node type registered from Odin, by its name. |

**Output**

| Type | | |
|---|---|---|
| `tile_output` | `empty` (-1), `tile_w`, `tile_h` (16), `rules`, `tileset`, `layer` | Each cell takes the first rule whose `min`..`max` holds its value: one of its `tiles` (or `tile`), picked by the cell and the seed. Cells no rule takes get `empty` (-1: none). `tileset` (a project image) and the tile size are for picking tiles and previews; `layer` is where it goes (below). |

**Terrains.** A rule can name a **terrain** of the tile output's tileset
(`{"min": 0.5, "max": 1, "terrain": "Grass"}`; in the editor, the rule's
terrain list) instead of tiles: its cells become that terrain and each
takes the terrain's tile for its pattern of neighbours - cave walls with
proper edges and corners. Cells beyond the level count as the terrain (it
runs on past the edges). Terrains are made on the Tile Map tab (Terrains
layer) and kept next to the tileset image (`<name>.tileset.json`, read
with the generator; `Gen_LoadTerrains`).

**Pattern rules.** After its rules (and terrains), a tile output's
**pattern rules** look at the 3 x 3 cells around each cell: each of the 9 is
*any*, *in* the rule's `min`..`max`, or *not* (the middle is the cell
itself). Where they match, the cell takes one of the rule's tiles - with a
`chance` (0..1; the same cells for a seed). The first that matches wins;
beyond the level counts as in the range. In the file:

    "patterns": [{"min": 0.5, "max": 1, "cells": [0, 0, 0, 0, -1, 0, 0, 1, 0],
                  "tiles": [40, 41], "chance": 0.3}]

(cells row by row: 1 in, -1 not, 0 any - here: an empty cell with solid
below, 30% of them.) With a **layer**, a tile output of pattern rules only
decorates another TileMap: grass tufts on the ground, stalactites under
ceilings, torches on walls. In the editor: **Add Pattern Rule**, click the
pattern's cells to cycle them, **Pick** its tiles.

**Layers.** The output's tiles go into the main TileMap. Any other tile
output with a **layer** name goes into the TileMap of that name next to the
main one (a sibling, else a child) - one generator fills ground, walls and
decoration at once, each from its own tileset: e.g. a cave's rock into
`Ground`, the Surface node's cells into `Grass`. A layer whose TileMap
isn't there is reported (the others are still written).
| `entity_output` | `max` (0 = all), `component` | Its component (a `.component.json`) on every point of its input (cells >= 0.5) - `max` of them picked by the seed. A graph can have several (enemies, coins, the player's start). |

## Playable levels

Random caves leave pockets the player can't reach; these nodes make a
level you can play through. Each has an **`open`** choice - which cells are
walkable: `low` (below 0.5: caves from `cellular`, where 1 is rock; the
default) or `high` (0.5 and above: the floors of `rooms` and `walker`) - and
most a **`diagonal`** toggle (cells touching at a corner count as joined).

| Type | Parameters | |
|---|---|---|
| `flood_fill` | `x`, `y` (-1: the middle), `open`, `diagonal` | 1 on the open cells reachable from that cell (a closed one: from the nearest open cell), 0 elsewhere. A mask for spawns. |
| `regions` | `mode`: `keep_largest` / `remove_small`, `min_size` (20), `open`, `diagonal` | Fills the areas you couldn't reach: all but the biggest, or those under `min_size` cells. |
| `connect_regions` | `width` (1), `min_size` (0), `open`, `diagonal` | Joins every open area into one with the shortest corridors - the cheapest bridges between areas that join them all - never through the outer row. Areas under `min_size` cells are filled instead. |
| `path` | `placement`: `left_right`, `top_bottom`, `farthest`, `custom` (`start_x`, `start_y`, `end_x`, `end_y`), `width` (1), `open`, `output`: `level`, `path`, `start`, `end` | Guarantees a way from a start to an exit: the cheapest route - through open cells where it can, carving rock where it must. `level` gives the input with it carved; `path` the route's cells; `start` / `end` that one cell (feed an Entity Output: the player, the door). |
| `check` | `min_open` (0.25), `connected` (true), `open`, `diagonal` | Its input unchanged - or an error when less than `min_open` of the level is open, or (`connected`) the open cells are in more than one area. |

The level nodes (`regions`, `connect_regions`, `path` with `level`) give
their input back as 0 / 1 in the same sense, so they chain: `cellular` ->
`connect_regions` -> `check` -> tile output.

A **Level Generator** node with **Random Seed** tries other seeds when the
generator refuses a level (an error, e.g. from `check`) - **Attempts** in all
(10 by default); **Last Seed** is the seed of the level made. With a fixed
seed it reports the error instead.

## Placing things

Feed an **entity output** with points - a `scatter` of a `surface`, for
coins on the ground:

```json
{"id": 6, "type": "surface", "inputs": {"in": 4}},
{"id": 7, "type": "scatter", "inputs": {"in": 6}, "params": {"chance": 0.2, "spacing": 6}},
{"id": 8, "type": "entity_output", "inputs": {"in": 7}, "params": {"max": 20},
 "component": "components/coin.component.json"}
```

Generating into a TileMap places them as its children at their cells'
centres (tagged `levelgen`); generating again replaces them. Scripts get
the same placements with `LevelGen.entities`.

## Into an LDtk level

In the editor, pick an **IntGrid** layer of a level in the Level tab, then
**Apply to LDtk Layer** in the Level Generator window: the tile output's
tiles become the layer's IntGrid values (1, 2...; empty cells 0) and the
layer's auto rules draw the tiles - the LDtk way of mapping values to art.
The Level tab's undo takes it back. (Odin: `Gen_ApplyIntGrid`.)

`seed` on a node adds to the graph's seed, so two noise nodes can differ.

## Your own nodes

**In Lua**: a **Lua Script** node (add menu > Your Own) runs a `.lua` file
that returns a function of `ctx`. **New** in its side panel writes one from
a template (`levels/<generator>_<node>.gen.lua`) and opens it in the Code
tab; **Reload** reads it again after you save it.

```lua
-- levels/islands.gen.lua: islands where input a is low, 1 = land.
return function(ctx)
    for y = 0, ctx.height - 1 do
        for x = 0, ctx.width - 1 do
            local i = y * ctx.width + x + 1
            if ctx.a[i] < ctx.params.p1 and ctx.random(x, y) < 0.8 then
                ctx.out[i] = 1
            end
        end
    end
end
```

| `ctx.` | |
|---|---|
| `width`, `height` | The level's size in cells. |
| `a`, `b` | The inputs: flat arrays, row by row, from 1 (`y * width + x + 1`); zeros when not connected. |
| `out` | The grid to fill (zeros) - or return an array of your own. |
| `params` | `p1`..`p4`: the node's numbers (set in the side panel). |
| `seed`, `random(x, y)` | The node's seed; a cell's number in [0, 1), the same every time for a seed. |

Scripts run in a sandbox of their own - `math`, `string`, `table`, no files,
no game - so a level stays the same for a seed; one that runs too long (an
endless loop) is stopped and the node shows the error, with its line.

**In Odin**: register a node type at startup (your game's, or an editor
plugin's) - it shows in the add menu and files name it by its `type`:

```odin
checker :: proc(call: ^Gen_Custom_Call) -> string {
	size := max(int(Gen_Param(call.node, "size")), 1)
	for y in 0 ..< call.out.h do for x in 0 ..< call.out.w {
		call.out.v[y * call.out.w + x] = 1 if (x / size + y / size) % 2 == 0 else 0
	}
	return "" // (or why it failed)
}
Gen_RegisterNode({name = "checker", label = "Checker", inputs = {"in"},
	params = {{name = "size", default_ = 4, integer = true}}, doc = "A checkerboard"}, checker)
```

`call.inputs` are its input grids, `call.seed` its seed (`Gen_Random01(x, y,
call.seed)`). A file with a type that isn't registered doesn't load.

## In the game: the Level Generator node

Add a **Level Generator** node with a TileMap child and pick its generator:
when the scene starts it makes a level into the map (tiles, colliders,
entities). No script needed.

| Property | |
|---|---|
| Generator | The `.levelgen.json`. |
| Tile Map | The map it fills, as a path (empty: its first TileMap child, else its parent). |
| Seed / Random Seed | A fixed level, or a new one each time - **Last Seed** says which (save it to replay the level). |
| Generate On Ready | Make a level when the scene starts. |
| Background | Make it on a worker thread while the game runs; `generated` fires when it is in. |
| Attempts | With Random Seed: seeds tried when the generator refuses a level (a `check` node) before it gives up (10). |

**Level Parameters** in the Inspector: change a generator node's value for
this node only - one generator file, many levels (denser caves later on).
**Generate Now** writes a level in the editor, to see or paint over.

```lua
local gen = self.node:get_node("Generator")
gen:levelgen_set_param(1, "density", 0.5)      -- generator node 1's density, for this node
gen:connect("generated", function(seed) hud:show_seed(seed) end)
gen:levelgen_generate()                              -- a new level (or levelgen_generate(seed): that one)
```

A signal can call `generate` with no script (a "next level" button's
`clicked`). Node reference: Level Generator.

## Lua

| Function | |
|---|---|
| `LevelGen.generate(file, tilemap [, seed])` -> ok, why | Writes the level into a TileMap node - tiles and entities; `level_generated` (the map's name) is emitted on the event bus. |
| `LevelGen.values(file [, seed [, node_id]])` -> `{width, height, values}` | The grid without a tile map (row-major: `values[y * width + x + 1]`) - any node's with `node_id`. |
| `LevelGen.entities(file [, seed])` -> `{{component, x, y}, ...}` | The entity outputs' placements (cells), to spawn yourself. |

```lua
-- Put the player on the first open cell of the cave.
local g = LevelGen.values("levels/caves.levelgen.json", seed)
for y = 0, g.height - 1 do
    for x = 0, g.width - 1 do
        if g.values[y * g.width + x + 1] < 0.5 then
            player.position = Vec2((x + 0.5) * 16, (y + 0.5) * 16)
            return
        end
    end
end
```

Generate during a loading screen ([`scene_flow.md`](scene_flow.md)) for big
levels.

## From Odin

```odin
g, err := Gen_LoadFile(ctx, "levels/caves.levelgen.json")
defer Gen_GraphDestroy(&g)
Gen_ApplyTileMap(&g, tilemap, seed, ctx)               // into a TileMapNode
grid, _ := Gen_Evaluate(&g, 0, seed)                   // the output's values (any node: its id)
tiles, size, _ := Gen_Tiles(&g, 0, seed)               // tile indices (-1 = none)
r, _ := Gen_Generate(&g, seed)                         // tiles and entities, the graph computed once
text := Gen_GraphSerialize(&g)                         // back to .levelgen.json
```

Evaluating again and again (a tool, an editor) - keep a `Gen_Cache`: a node
whose settings, inputs, size, seed and script text haven't changed reuses
its grid.

```odin
cache: Gen_Cache
Gen_CacheInit(&cache)
defer Gen_CacheDestroy(&cache)
grid, _ := Gen_Evaluate(&g, id, seed, context.temp_allocator, &cache)
```

A registered node's proc may run while other evaluations do (the editor's
previews are on a worker thread): keep it free of shared state.

`GEN_KINDS` (engine/level_gen.odin) describes every built-in node type -
its inputs, parameters with defaults and help - for tools;
`Gen_NodeInfo(node)` any node's, registered ones too.
