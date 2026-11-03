# Puzzle (Sokoban)

Push every crate onto a target. Crates can only be pushed, one at a time.
Three levels, each with a move limit (undo gives moves back): run out
before it's solved and the game is over. Solve the third to win. A title
screen, a settings screen (the volume), a pause menu and a result screen
come with it, and your progress is saved: the furthest level reached (the
title's **Level** starts there) and each level's fewest moves.

| Play | |
|---|---|
| Move | Arrows, WASD, gamepad stick / D-pad (hold to keep going) |
| Undo | Z, U, Backspace, gamepad B |
| Restart the level | R, gamepad Y |
| Pause | Esc, P, gamepad Start (the II button on a touch screen) |
| Menus | Up / down to pick, Enter or Space to choose, left / right to change a value; or click / tap a choice |

## What's where

| | |
|---|---|
| `scripts/puzzle.lua` | The game itself: the levels (as text at the top) and their move limits, building the board, moving, pushing, undo, solved / out of moves |
| `scenes/title.scene.json` | The title screen: Play, the start Level, Settings (Volume), Quit |
| `scenes/puzzle.scene.json` | The Board node (the script; its *Start Level*: the level when the scene is played on its own), the texts, the pause menu |
| `scenes/result.scene.json` | After a win or a game over: the moves, the fewest moves, Play again / Retry, the title |
| `scripts/game.lua` | The global `Game` (Project Settings > Globals): the levels, the run, the save data (`settings`, `progress` in `save.json`) |
| `scripts/menu.lua` | Every menu: Text nodes tagged `item` are the choices; its **Kind** says what they do |
| `textures/` | Kenney's Sokoban pack (CC0) |

## Make it yours

- **New levels**: add one to `LEVELS` in `puzzle.lua` - `#` wall, `.`
  target, `$` crate, `*` crate on a target, `@` you, `+` you on a target.
  Make sure it can be solved (the template's levels were checked by a
  solver: `scripts/templates/make_templates.py` in the engine repository),
  give it a move limit in `LIMITS` and one more entry in `Game.LEVELS`
  (`game.lua`: every level is the puzzle scene).
- **Different look**: swap the images in `textures/` (64x64), or change
  *Tile Size* on the Board.
- **Keys / buttons**: Project Settings > Input (move_*, undo, restart).
