# Isometric Dungeon

A small, complete game on an isometric grid: escape three rooms against
the clock. In each, find the key in the chest, then open the door - on to
the next room, and out after the third. Mind the holes in the floor: a
fall costs a life (three for the whole game), and the clock running out
is game over. The hero walks behind the pillars and the walls. A title
screen, a settings screen (the volume), a pause menu and a result screen
come with it, and your progress is saved: the furthest room reached (the
title's **Room** starts there) and the most time to spare.

| Play | |
|---|---|
| Walk | Click / tap a cell (the hero finds the way round the walls and holes), or WASD / arrows / gamepad |
| Open | Click the chest or the door, or press E (Enter, Space, gamepad A) next to it |
| Pause | Esc, P, gamepad Start (the II button on a touch screen) |
| Menus | Up / down to pick, Enter or Space to choose, left / right to change a value; or click / tap a choice |

WASD walk along the grid: W up-right, D down-right, S down-left, A
up-left. Two keys at once go straight up, right, down or left.

## What's where

| | |
|---|---|
| `scenes/title.scene.json` | The title screen: Play, the start Room, Settings (Volume), Quit |
| `scenes/room1`, `room2`, `room3` | The rooms: **Floor**; under **World** (Y Sort), **Walls** and **Props** (Y Sort, Solid) and the **Hero**; **Walk**, an invisible map of the walkable cells; **Cursor**; the HUD; the pause menu. **Dungeon**'s *Time Limit* is the room's clock |
| `scenes/result.scene.json` | After a win or a game over: the time to spare, the best, Play again / Retry, the title |
| `scripts/game.lua` | The global `Game` (Project Settings > Globals): the rooms in order, the run (room, time to spare, lives), the save data (`settings`, `progress` in `save.json`) |
| `scripts/menu.lua` | Every menu: Text nodes tagged `item` are the choices; its **Kind** says what they do |
| `scripts/dungeon.lua` | Builds Walk from the other maps, handles clicks, the chest and the door, the holes and the clock |
| `scripts/hero.lua` | Walking: the keys along the grid's axes, clicks through the Navigation Agent; facing 8 ways; falling |
| `scripts/cursor.lua` | Outlines the cell under the mouse and draws the path still to walk |
| `textures/` | Kenney's Isometric Miniature Dungeon (CC0), cut into a tile sheet and the hero's frames |

## How the depth works

The maps are **Isometric** with 128 x 64 cells. The tiles are 128 x 144,
taller than their cells, so walls and pillars stand on their cells; **Tile
Offset** 0, 10 puts the floor's slab under its diamond. **World** has
**Y Sort** on, and so do **Walls** and **Props**: their rows sort with the
hero by the cells' feet. **Y Sort Offset** moves that line. Walls use -56
(a back wall is behind whoever stands in its cell). Props use -24 (a
pillar hides the hero when he's behind it, not when he's in front).

## Make it yours

- **Change a room**: paint the Floor, Walls and Props maps in the
  editor (the Tile Map tab). Walk is rebuilt from them when the scene
  starts. Wall pieces sit on a cell's edge: tile 9 the upper-left one, 10
  the upper-right one, 14 the back corner; a door is 17 in the
  upper-left wall, 18 in the upper-right one. Erase a Floor cell for a hole.
- **A fourth room**: duplicate `room3.scene.json` (Assets > right-click >
  Duplicate), change it, set its Dungeon's *Room* to 4 and add it to
  `Game.LEVELS` at the top of `game.lua`.
- **More time, more lives**: the Dungeon's *Time Limit*; `Game.LIVES` in
  `game.lua`.
- **Bigger rooms**: paint further out. Walk covers up to 40 x 40 cells
  (`build_walk` in `dungeon.lua`).
- **Things to use**: `Dungeon:what_at` names what's in a cell (the chest,
  the door); `Dungeon:use` does it.
- **Faster hero**: the Hero's **Speed** (keys) and the Agent's **Speed**
  (clicks).
- **Start over**: Game > Save Data > Delete Save Files.
