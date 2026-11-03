# Platformer Adventure (sample)

The Platformer template grown into a small game, to show how the pieces
fit: a title screen, a settings screen (the volume), two levels whose
doors route from one to the next, three lives for the whole game, a game
over, a pause menu and a result screen. Your progress is saved: the
furthest level reached (the title's **Level** starts there) and the best
coin count. Open it to see how it's done; copy what you need into your
own game.

| Play | |
|---|---|
| Move / jump | as in the Platformer template (arrows / A D, Space) |
| Pause | Esc, P, gamepad Start (the II button on a touch screen) |
| Menus | Up / down to pick, Enter or Space to choose, left / right to change a value; or click / tap a choice |

## How it fits together

| | |
|---|---|
| `scenes/title.scene.json` | The first scene (project.json's initial scene): Play, the start Level, Settings, Quit |
| `scenes/level1`, `level2` | The levels; each door's *Next Level* is the route - level 1's leads to level 2, level 2's (empty) ends the game |
| `scenes/result.scene.json` | After a win or a game over: the coins, the best, Play again / Retry, the title |
| `scripts/game.lua` | The global `Game` (Project Settings > Globals): the levels, the run (level, coins, lives), the save data (`settings`, `progress` in `save.json`) |
| `scripts/goal.lua` | The door: reaching it unlocks (and saves) its Next Level and goes there; with none, the game is won |
| `scripts/menu.lua` | Every menu: Text nodes tagged `item` are the choices; its **Kind** says what they do. The pause menu's node has *Pause Mode: Always*, so it runs while `Engine.set_paused(true)` stops the rest |
| `scripts/player.lua` | A death costs a life (`Game:lose_life`); the last one is game over |
| everything else | the Platformer template's scripts |

## Make it yours

- **Another route**: add a level to `Game.LEVELS` (the top of
  `game.lua`), set its HUD's *Level* to its number and point a door's
  *Next Level* at it - doors can skip levels or lead back.
- **Lives**: `Game.LIVES` in `game.lua`.
- **Start over**: Game > Save Data > Delete Save Files.
