# Hex Island

A small, complete game on a hex grid: three little islands, each with a
handful of flowers to pick. Walk round the water, the trees and the
rocks; picking every flower clears an island and takes you to the next.
Every hex you walk into is a step, and each island has a step limit (the
shortest walk to every flower, and a few to spare): run out with a flower
left and the game is over. A title screen, a settings screen (the volume),
a pause menu and a result screen come with it, and your progress is
saved: the furthest island reached (the title's **Island** starts there)
and each island's fewest steps.

| Play | |
|---|---|
| Walk | Click / tap a hex: the explorer finds the way there, hex by hex (the dots of the path past your last step are red) |
| One step | D right, A left, E up-right, Q up-left, C down-right, Z down-left (arrows: right / left) |
| Pause | Esc, P, gamepad Start (the II button on a touch screen) |
| Menus | Up / down to pick, Enter or Space to choose, left / right to change a value; or click / tap a choice |

## What's where

| | |
|---|---|
| `scenes/title.scene.json` | The title screen: Play, the start Island, Settings (Volume), Quit; each island's fewest steps |
| `scenes/island1`, `island2`, `island3` | The islands: **Ground** (Hex Pointy: land and water), under **World** (Y Sort) **Objects** (trees, rocks, flowers) and the **Explorer**; **Walk**, an invisible map of the hexes that can be walked on; the HUD; the pause menu. **Island**'s *Step Limit* is the island's steps |
| `scenes/result.scene.json` | After a win or a game over: the steps taken, the fewest, Play again / Retry, the title |
| `scripts/game.lua` | The global `Game` (Project Settings > Globals): the islands in order, the run (island, steps), the save data (`settings`, `progress` in `save.json`); its last lines are this game's (the title's and the result's text) |
| `scripts/menu.lua` | Every menu: Text nodes tagged `item` are the choices; its **Kind** says what they do |
| `scripts/island.lua` | Builds Walk, turns clicks and keys into walks, counts the steps, picks the flowers, clears the island (or runs out), outlines the hex under the mouse and draws the path |
| `scripts/explorer.lua` | Finds the path (`nav_find_path` in Walk) and walks it centre to centre |
| `textures/` | Kenney's Hexagon Tiles (CC0): the land tiles, the things on them, the alien |

## How it works

The maps' **Grid** is **Hex (pointy)** with 65 x 66 cells, odd rows
shifted. The tiles are 65 x 89, a hexagon on a slab: **Tile Offset** 0, 23
puts the slab under the hexagon. The objects stand on the hex's middle
(offset 0, -25). On a hex map, `tilemap_neighbors` gives the six sides
clockwise from the right, and paths step through them.

## Make it yours

- **Reshape an island**: paint Ground and Objects in the editor (the Tile
  Map tab). Walk is rebuilt from them when the scene starts. Tile 7 of
  Ground is water. Check the Island's *Step Limit* still leaves room to
  pick every flower.
- **A fourth island**: duplicate `island3.scene.json` (Assets >
  right-click > Duplicate), change it, set its Island's *Island* to 4 and
  add it to `Game.LEVELS` at the top of `game.lua`.
- **Other things to pick**: `FLOWERS` in `island.lua` lists the Objects
  tiles that are picked up. The others block.
- **Turns**: `Explorer:go_to` gets the whole path. Walk only the first N
  steps of it for a move range.
- **Start over**: Game > Save Data > Delete Save Files.
