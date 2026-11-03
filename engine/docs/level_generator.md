# Procedural levels (level generator)

A **generator** builds a level from a graph of nodes, in the style of the
Gaea add-on for Godot: some nodes make a grid of values (noise, random
fill, shapes), others change it (threshold, cave smoothing, blur, combine),
and the **tile output** turns values into tiles and writes them into a
TileMap. The same generator and **seed** always give the same level, on
every platform - so a seed is a level you can share, replay or test.

So far (#142, #171): the generator file, the nodes (terrain, caves, rooms
and corridors, walkers, Wave Function Collapse), placing entities, TileMap, component-layer and
LDtk output, your own nodes (Lua or Odin), the **Level Generator** node
that makes levels in the game (with progress for a loading bar and
navigation baked again), the Lua module and the **Level Generator** window
in the editor.

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
  canvas to add a node; right-click a node to copy, duplicate or delete it,
  frame it or use it as the output. The wheel pans, Ctrl/Cmd+wheel zooms,
  F frames everything.
- **Searching for a node**: the add menu opens with a search field. Type
  part of a node's name to filter every type (built-in, Lua Script and
  types registered from Odin); **Enter** adds the first match.
- **Several nodes**: Shift+click or Cmd/Ctrl+click adds a node to the
  selection or takes it out, and dragging a box on the empty canvas selects
  the nodes it touches (Shift: adds them). Ctrl/Cmd+A selects every node.
  Dragging one selected node moves them all; Delete removes them.
- **Copy and paste**: Ctrl/Cmd+C copies the selected nodes, with the links
  between them; links to nodes you didn't copy are dropped. Ctrl/Cmd+V
  pastes them at the mouse, with new ids, into this generator or another
  one you open. The copy is also on the system clipboard (as JSON), so it
  pastes in a later editor session too. Ctrl/Cmd+D duplicates the
  selection beside itself without touching the clipboard.
- **Comment frames**: a titled, coloured box to group nodes. **Frame
  Selection** (a node's menu) or the toolbar's frame button puts one around
  the selected nodes; **Add Frame** (the canvas's menu) adds an empty one.
  Drag its title bar to move it with the nodes inside it (a node is inside
  when its middle is), and its bottom-right corner to resize it. Click its
  title bar to set the title and colour in the side panel; Delete or
  right-click > **Delete Frame** removes the frame and keeps the nodes.
- **The side panel**: the level's **size**, **seed** (the dice picks a new
  one) and **output**; the selected node's parameters, for a Wave Function
  Collapse node its sample to paint (below) and, for a tile output, its **Tileset** (the picture its tile numbers count in; the grid
  button takes the tileset and tile size of the TileMap selected in the
  scene), its **Layer**, and its **rules** (a range and tiles: `3, 4` picks
  one of them per cell - or **Pick** them from the tileset: click tiles to
  add or remove them; the rule shows them as small pictures); a large
  **preview** of the selected node (or the output). A tile output with a
  tileset previews with its real tiles. With **writes** set to
  `components`, its rules pick a component each instead of tiles (the
  preview colours each rule's cells).
- **The toolbar**: **Save** (Ctrl/Cmd+S), **Undo** / **Redo**
  (Ctrl/Cmd+Z, Ctrl/Cmd+Shift+Z: every change, including pastes and
  frames), **Copy**, **Paste** and **Frame**, and **Apply to TileMap**,
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
sliding sums (any radius costs the same), value noise from a precomputed
lattice. A 256 x 256 cave with noise, blur and scatter takes about 1.5 ms
in an optimized build (`scripts/bench.sh engine`, `bench_level_gen`). On
256 x 256 cells, 4 octaves of noise take about 0.3 ms (value), 0.5 ms
(Perlin) and 0.8 ms (Simplex); a Poisson scatter with radius 4 over the
whole level about 2 ms (it runs on one thread: each point depends on the
ones before it).

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
| `frames` | Optional: the editor's comment frames, each with a `title`, `pos` and `size` (canvas units) and `color` (`[r, g, b, a]`, 0-1). Generation ignores them. |

The full schema - every key, node type, parameter and default, and what
changed when - is in the file format reference:
[`RAYZR_FORMAT.md`, Level Generator Schema](../RAYZR_FORMAT.md#5b-level-generator-schema-levelgenjson).

Every port carries a grid of numbers the size of the level - usually 0
(empty / low) to 1 (solid / high). An input that isn't connected reads 0
everywhere. A node may feed any number of others (computed once); a cycle
is an error.

## Nodes

**Generators**

| Type | Parameters | |
|---|---|---|
| `constant` | `value` (1) | The same value everywhere. |
| `noise` | `type`: `value` (default), `perlin`, `simplex`; `scale` (16), `octaves` (3), `persistence` (0.5), `seed` (0) | Smooth noise (fBm), 0..1 - the types below. |
| `random_fill` | `density` (0.45), `seed` (0) | Each cell 1 with that chance, else 0. |
| `gradient` | `direction`: `horizontal` (0 left .. 1 right), `vertical` (0 top .. 1 bottom), `radial` (1 centre .. 0 corners) | A ramp. |
| `border` | `width` (1) | 1 within that many cells of the edge. |
| `rect` | `x`, `y`, `w`, `h` (8), `value` (1) | A filled rectangle. |
| `rooms` | `min_size` (4), `max_size` (10), `corridor` (1), `seed` (0) | A dungeon: the level split in two again and again (BSP), a room in each part, corridors joining every split - every room reachable. 1 = floor (invert it for walls). |
| `walker` | `steps` (400), `walkers` (1), `brush` (1), `seed` (0) | Random walks from the centre ("drunkard's walk"): winding tunnels and caverns. 1 = walked. |
| `lines` | `count` (6), `min_length` (6), `max_length` (20), `thickness` (1), `direction`: `horizontal`, `vertical`, `both` (each line one or the other; default), `any` (any angle), `seed` (0) | Random lines: platforms, ledges, walls, cracks. Each fits inside the level (one longer than it is clipped). |
| `rectangles` | `count` (5), `min_size` (4), `max_size` (12), `thickness` (1), `filled` (false), `seed` (0) | Random rectangles, outlines `thickness` cells wide or filled: rooms, ruins, crates. Each side's length is picked in the range. |
| `circles` | `count` (5), `min_radius` (3), `max_radius` (8), `thickness` (1), `filled` (false), `seed` (0) | Random rings or discs: craters, arenas, pools. A cell is in when its centre is within radius + 0.5 of the circle's. |
| `wfc` | `rules`: `sample` / `wang`, `wrap` (false), `attempts` (10), `seed` (0); inputs `mask`, `fixed`; `sample`, `wang` | Wave Function Collapse: **tile ids** (not 0..1 values), each tile next to only the tiles a sample you paint puts next to it. See [Wave Function Collapse](#wave-function-collapse). |

**Noise types.** `value` blends random numbers at the corners of a grid:
soft blobs, the original type (a file without `type` gets it, and the same
seed still gives the same level). `perlin` blends gradients instead:
smoother hills and caves with fewer flat patches. `simplex` is gradient
noise on a triangle grid: like Perlin with fewer grid-aligned features and
a little more contrast. All three use the same `scale`, `octaves` and
`persistence`. Perlin and Simplex depend only on a cell's position and the
seed (each octave shuffles its own table from the node's seed), never on
the level's size: a bigger level has the same noise where the two overlap.

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
| `poisson_scatter` | `radius` (4), `attempts` (30), `seed` (0); input `mask` | Evenly spaced random points (1): every two at least `radius` cells apart (centre to centre), filling the space without clumps or gaps - on the mask's solid cells when it is connected, anywhere otherwise. See Poisson scatter under [Placing things](#placing-things). |
| `surface` | `side`: `top` (empty cells with solid below: ground to stand on), `bottom` (solid above: ceilings), `any` | Empty cells against the input's solid ones. |

**Your own** (see [Your own nodes](#your-own-nodes))

| Type | Parameters | |
|---|---|---|
| `script` | `p1`..`p4` (0), `seed` (0); inputs `a`, `b`; `script` (a `.lua` file) | A Lua function computes the grid. |
| *(registered)* | its own | A node type registered from Odin, by its name. |

**Output**

| Type | | |
|---|---|---|
| `tile_output` | `empty` (-1), `tile_w`, `tile_h` (16), `writes` (`tiles`), `tile_ids` (false), `rules`, `tileset`, `layer` | Each cell takes the first rule whose `min`..`max` holds its value: one of its `tiles` (or `tile`), picked by the cell and the seed. Cells no rule takes get `empty` (-1: none). `tileset` (a project image) and the tile size are for picking tiles and previews; `layer` is where it goes (below). `writes`: `components` paints components on a map's component layer instead (below). `tile_ids`: its input already holds tiles (a `wfc` node's) - the rules are skipped. |

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

**Component layers.** A TileMap's **Components** layer (the Tile Map tab)
holds component instances on its cells - coins, crates, trees - one per
cell, a bigger one covering its footprint. A tile output with **writes**
set to `components` paints on that layer instead of writing tiles: each
rule maps a value range to a **component** (a `.component.json`), and each
cell gets the component of the first rule whose range holds its value.
The **layer** name picks the map (empty: the main one), whose tiles stay.

```json
{"id": 9, "type": "tile_output", "inputs": {"in": 6}, "params": {"writes": "components"}, "layer": "Props",
 "rules": [{"min": 0.5, "max": 1, "component": "components/crate.component.json"}]}
```

A component bigger than a cell (a 2 x 2 crate) covers its footprint,
centred on the cell and kept inside the map; cells a footprint already
covers are skipped, so a filled area gets crates side by side. Instances
painted by hand under a footprint are replaced; what a generation painted
is tagged `levelgen` and replaced by the next one. In the window: pick
**writes** in the output's parameters, then each rule's component (the
preview shows each rule's cells in a colour). An output that writes
components never becomes the default output - the main map's tiles come
from one that writes tiles. Unlike an **entity output** (a component on
points, at the cells' centres), this one follows the layer's one-per-cell
footprints, as painting by hand does.
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

## Wave Function Collapse

The other nodes make values and a tile output turns them into tiles. The
**Wave Function Collapse** node (`wfc`) makes the tiles themselves, from a
small **sample** you paint: a tile only ever sits next to a tile - to its
left, right, above or below - that it sits next to somewhere in the sample,
and tiles come about as often as they do in it. Paint a pond: water inside,
a shore of sand around it, grass outside - and the level gets ponds of all
shapes, always with a shore, never grass touching water. Roads that join,
rooms with walls round them, rivers with banks work the same way.

**In the window**: add **Wave Function Collapse** (Generators), drag its
output onto a tile output's input - the output's **tile_ids** turns on (its
rules are skipped: the cells already hold tiles) - and give the output its
**Tileset**. Select the WFC node: its side panel paints the sample with that
tileset's tiles.

- **Size**: the sample's cells across and down (8 x 8 to start, up to 64).
- **Brush**: click a tile in the tileset (or one of those **In it** already)
  to paint with it; **Eraser** paints nothing; **Fill** paints every cell
  with the brush.
- **The sample**: drag with the left button to paint, the right to erase.
  Unpainted cells teach nothing. Each stroke is one undo step.
- **Learned**: how many tiles and pairs of neighbours the rules hold; the
  previews show the result with the output's tiles as you paint.

Parameters:

| | |
|---|---|
| `wrap` | The sample's edges wrap: its right column counts as next to its left one, its bottom row next to its top - more pairs from a small sample (paint it so it tiles). |
| `attempts` | Tries before it gives up (below). |
| `seed` | Added to the graph's seed. |

Inputs, both optional: **mask** - only its solid cells (0.5 and above) are
filled, the others are -1 (empty in the output) and don't constrain their
neighbours: WFC tiles inside a cave's floor, a room, an island; **fixed** -
cells whose value is one of the sample's tiles keep it and the rest is
built around them (feed it another WFC node, or a Lua script that places a
door tile).

**Contradictions.** Sometimes the tiles placed so far leave a cell that no
tile fits. The node then starts again with the next seed, up to `attempts`
times (10), and then fails with an error (*a contradiction on every try*) -
a Level Generator with **Random Seed** goes on to other seeds, as it does
when a `check` refuses a level. Rules that can never fit (a tile with no
neighbour allowed on one side, e.g. painted only at the sample's right
edge) fail every time: paint it with neighbours on every side, turn on
`wrap`, or paint a bigger sample. The same seed always gives the same
tiles; a progress bar moves while a big one is solved.

**Wang tiles.** Instead of a sample, set `rules` to `wang` and list tiles
with the colours of their four edges - north, east, south, west, as
numbers: two tiles touch only where their touching edges have the same
colour, and each tile's **weight** is how often it is picked. In the window:
**Add Wang Tile**, then its tile number, edges and weight. A Wang set is the
same kind of rule as a sample - which tile may sit next to which - written
out by edges: the solver is the same.

```json
{"id": 4, "type": "wfc", "params": {"rules": "wang"}, "wang": [
  {"tile": 0, "edges": [0, 0, 0, 0]}, {"tile": 1, "edges": [0, 1, 0, 1]},
  {"tile": 2, "edges": [1, 0, 1, 0]}, {"tile": 3, "edges": [1, 1, 1, 1], "weight": 0.2}]}
```

(Tile 1 is a road running east-west, 2 north-south, 3 a crossing; 0 grass:
a road never stops in the grass - it runs on to the level's edge or into a
crossing.)

**Speed**: in an optimized build a 64 x 64 level takes about 2 ms and a
128 x 128 about 8 ms with a 3-tile sample (10 ms with 16 Wang tiles) - more
tiles, contradictions and retries cost more. Each cell's possible tiles are
a bitset, the next cell is the one with the fewest left (a heap), and a
change spreads to the neighbours with a stack.

## Placing things

Feed an **entity output** with points - a `scatter` of a `surface`, for
coins on the ground:

```json
{"id": 6, "type": "surface", "inputs": {"in": 4}},
{"id": 7, "type": "scatter", "inputs": {"in": 6}, "params": {"chance": 0.2, "spacing": 6}},
{"id": 8, "type": "entity_output", "inputs": {"in": 7}, "params": {"max": 20},
 "component": "components/coin.component.json"}
```

**Poisson scatter.** `scatter` keeps random points that are far enough
from those before them, so it leaves clumps and empty stretches;
`poisson_scatter` places points evenly (Bridson's Poisson-disc algorithm):
every two at least `radius` apart, and no cell farther than `2 * radius`
from a point. Trees in a forest, rocks on a field, enemies across a cave
floor:

```json
{"id": 9, "type": "poisson_scatter", "inputs": {"mask": 6}, "params": {"radius": 8}},
{"id": 10, "type": "entity_output", "inputs": {"in": 9}, "component": "components/tree.component.json"}
```

`attempts` is how many cells it tries around each point before moving on:
fewer leaves the points sparser and is quicker. A mask in separate parts
gets points in each.

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
| Rebake Navigation | Once the level is in - tiles, colliders, components, entities - bake every Navigation Region of the scene again, before `generated`: agents find paths through the new map at once. Off by default. |
| Progress | 0 to 1 while it generates (runtime, read-only; below). |
| Chunked / Chunk Size / Chunk Radius / Camera Path | An endless level made around the camera (below). |
| Loaded Chunks | Chunked: the chunks in now (runtime, read-only). |

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

**A loading bar.** `progress` goes from 0 to 1 while a level is made:
the generator's nodes computed, of those the outputs need. With Random
Seed, a seed the generator refuses is tried again and the bar carries on
from where it stopped (each attempt fills most of what is left; the last
allowed one all of it), so it only ever grows. `generation_progress` fires
with the fraction at the start (0), each time it moves by 1% or more (at
most once a frame) and with 1 when the level is in, just before
`generated`. With **Background** on the game keeps running meanwhile;
without it the level is made at once and the event fires with 0 and 1.

```lua
local gen = self.node:get_node("Generator")
local bar = self.node:get_node("Loading/Bar")
gen:connect("generation_progress", function(p) bar.value = p * 100 end)
gen:connect("generated", function() self.node:get_node("Loading").visible = false end)
gen.background = true
gen:levelgen_generate()
-- or read it each frame: bar.value = gen.progress * 100
```

**Navigation.** A Navigation Region bakes when the scene starts - before
the level exists. Turn on **Rebake Navigation** and the scene's regions are
baked again once the level is in (the TileMap's solid tiles, static bodies
among the components and entities), before `generated` - so a `generated`
handler can send agents across the new level at once. The region must
cover the map ([`navigation.md`](navigation.md)).

## Endless levels: chunks

Turn on **Chunked** and the level never ends: it is made a chunk at a time
around the camera. A chunk is **Chunk Size** x Chunk Size cells (32) of the
level - chunk (x, y) starts at cell (x, y) x Chunk Size, so negative chunks
go up and left. The chunks within **Chunk Radius** (2: a 5 x 5 square) of
the camera's chunk are kept in; a chunk more than Chunk Radius + 1 away is
taken out again - its tiles cleared, its colliders, components and
entities removed (the extra one keeps a camera wobbling over a chunk's edge
from making and dropping the same chunks). The camera is **Camera Path**
(any node, as a path from the generator: a camera, the player), else the
scene's camera; without one, chunk (0, 0).

Chunks are made on worker threads, the nearest first (a few at once), and
go in at the start of a frame - a 32 x 32 chunk's tiles and colliders take
about 0.1 ms on the main thread. With **Background** off the first chunks,
around the camera, go in at once (before the first frame: the player
doesn't fall through an empty map); later ones still come from the
workers. The web build makes one chunk a frame. In the editor, **Generate
Now** makes the chunks around the scene's camera (or Camera Path's node)
into the map, to see the start of the world.

A chunk always comes out the same for a seed, and a **chunk-safe**
generator gives every cell the value it has in one big level: no seams.
Each chunk is made with an apron of extra cells around it - what the
neighbourhood nodes need to see past its edge (blur's radius, cellular's
iterations, dilate / erode's, scatter's spacing, surface and the tile
output's one cell, added up along each path to an output) - and only the
middle is kept.

| Chunk-safe | Not chunk-safe (they look at the whole level or its edges) |
|---|---|
| constant, noise (every type), random fill, gradient (across the generator's size; past it 0 or 1), rectangle (at its cells), threshold, invert, remap, combine, blur, cellular, dilate, erode, scatter, surface, tile output, entity output | border, rooms & corridors, walker, random lines / rectangles / circles, Wave Function Collapse, Poisson scatter, flood fill, regions, connect regions, path, check, Lua Script and Odin nodes |

Nodes that aren't chunk-safe still run: in each chunk on its own, with the
chunk's own seed (each chunk a different dungeon, always the same one), so
seams show between chunks. The Inspector and the Level Generator window
warn (a mark on each such node) when a generator made in chunks has any.
In a chunk, Scatter keeps a candidate unless one within its spacing comes
before it - the same spacing as its row-by-row scan, decided from the cells
around - so its points differ from the whole level's; an entity output's
`max` counts per chunk.

Events: `chunk_generated` and `chunk_unloaded` (the chunk, a Vec2 of its
x, y) for each chunk that goes in or out; `generated` once the first chunks
are all in. `progress` is the share of the chunks around the camera that
are in: it drops when the camera reaches new ground and is back at 1 once
they are in (`generation_progress` follows). With **Rebake Navigation** the
regions are baked again each time the chunks around the camera are all in
after a change.

```lua
local gen = self.node:get_node("Generator")
gen:connect("chunk_generated", function(c) print("in", c.x, c.y) end)
gen:connect("chunk_unloaded", function(c) save_chunk_state(c.x, c.y) end)
local cx, cy = gen:levelgen_chunk_at(player.position.x, player.position.y)
if not gen:levelgen_is_chunk_loaded(cx, cy) then player.paused = true end
for _, c in ipairs(gen:levelgen_loaded_chunks()) do print(c.x, c.y) end
```

The TileMap becomes endless (cells anywhere, negative too): its storage
covers the chunks that are in and moves with them, and each chunk has its
own collider body. Tiles a script sets on such a map don't get colliders.
What a chunk placed goes when it does - remember picked-up coins yourself
(`chunk_unloaded`) if they shouldn't come back.

## Lua

| Function | |
|---|---|
| `LevelGen.generate(file, tilemap [, seed])` -> ok, why | Writes the level into a TileMap node - tiles, components and entities; `level_generated` (the map's name) is emitted on the event bus. |
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
r, _ := Gen_Generate(&g, seed)                         // tiles, components and entities, the graph computed once
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

Following a generation on another thread: give `Gen_Generate` a
`Gen_Progress` and read `Gen_ProgressValue` (0..1, any thread):

```odin
p: Gen_Progress
Gen_ProgressAttempt(&p, Gen_NeededNodes(&g), last = true)
r, _ := Gen_Generate(&g, seed, allocator, &p)          // (on the worker)
fraction := Gen_ProgressValue(&p)                      // (on the main thread, meanwhile)
```

A registered node's proc may run while other evaluations do (the editor's
previews are on a worker thread): keep it free of shared state.

`GEN_KINDS` (engine/level_gen.odin) describes every built-in node type -
its inputs, parameters with defaults and help - for tools;
`Gen_NodeInfo(node)` any node's, registered ones too.
