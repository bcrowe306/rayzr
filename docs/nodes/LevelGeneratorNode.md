## Making levels in the game

Pick a **Generator** (a `.levelgen.json` made in the Level Generator window)
and give the node a **TileMap** to fill: a TileMap child (the usual set-up),
its parent when that is a TileMap, or any one at the **Tile Map** path (with
several TileMap children, the first). Tile outputs with a **Layer** name fill
the TileMaps of those names next to it: give the node one TileMap child per
layer - `Ground` first, then `Walls`, `Decor`. When
the scene starts (**Generate On Ready**) it makes a level: the tiles, their
colliders, and the generator's entities (as children of the map). Call
`levelgen_generate()` again - or connect a signal to `generate`, no script needed -
for a new level.

| | |
|---|---|
| **Seed** | The same seed makes the same level (0: the generator's own seed). |
| **Random Seed** | A new level every time. **Last Seed** is the one used: show it to the player, save it, `levelgen_generate(seed)` replays it. |
| **Background** | Makes the level on a worker thread while the game keeps running (a loading screen stays smooth); `generated` fires when it is in. |
| **Attempts** | With **Random Seed**: how many seeds it tries when the generator refuses a level - a **Check** node finding too little open, or the level in pieces - before it reports `generation_failed` (10). **Last Seed** is the one that worked. |
| **Rebake Navigation** | Once the level is in, bake the scene's **Navigation Regions** again (before `generated`): agents find their way through the new map at once. |
| **Progress** | 0 to 1 while a level is made (read-only) - for a loading bar, with the `generation_progress` event (each 1% or more; 1 when the level is in). |

## Level parameters

One generator file can make many kinds of level. The Inspector's **Level
Parameters** list the generator's nodes and their values: change one and
this node uses it (the dot next to it goes back to the generator's value).
From Lua, before generating:

```lua
function Level:ready()
    local gen = self.node:get_node("Generator")
    local level = Save.get("level", 1)
    gen:levelgen_set_param(1, "density", 0.42 + level * 0.02) -- (node 1: a random fill)
    gen:connect("generated", function(seed) Log.info("level " .. seed) end)
    gen:levelgen_generate()
end
```

## A loading bar

With **Background** on, the game keeps running while the level is made:

```lua
gen:connect("generation_progress", function(p) bar.value = p * 100 end)
gen:connect("generated", function() loading.visible = false end)
gen:levelgen_generate()
```

**Generate Now** in the Inspector writes a level into the TileMap in the
editor, to see it or paint over it (undoable). Guide:
[`engine/docs/level_generator.md`](../../engine/docs/level_generator.md).
