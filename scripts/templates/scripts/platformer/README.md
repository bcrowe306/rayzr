# Platformer

A small, complete platformer game: run and jump through two levels to the
door at the end of each, collect coins, avoid spikes and stomp the
enemies. You have three lives for the whole game; lose them all and it's
game over. A title screen, a settings screen (the volume), a pause menu
and a result screen come with it, and your progress is saved: the
furthest level reached (the title's **Level** starts there) and the best
coin count.

| Play | |
|---|---|
| Move | A / D, arrows, gamepad stick / D-pad |
| Jump | Space, W, Up, gamepad A (hold for a higher jump) |
| Pause | Esc, P, gamepad Start (the II button on a touch screen) |
| Menus | Up / down to pick, Enter or Space to choose, left / right to change a value; or click / tap a choice |

## What's where

| | |
|---|---|
| `scenes/title.scene.json` | The title screen: Play, the start Level, Settings (Volume), Quit |
| `scenes/level1.scene.json`, `level2.scene.json` | The levels: the tile maps (Level is solid, Decor isn't), coins, spikes, enemies, the door, the player, the camera, the HUD, the pause menu |
| `scenes/result.scene.json` | After a win or a game over: the coins, the best, Play again / Retry, the title |
| `scripts/game.lua` | The global `Game` (Project Settings > Globals): the levels in order, the run (level, coins, lives), the save data (`settings`, `progress` in `save.json`) |
| `scripts/menu.lua` | Every menu: Text nodes tagged `item` are the choices; its **Kind** says what they do |
| `scripts/player.lua` | Movement (coyote time, jump buffer, jump cut), animations, dying (a life) and winning - tune it in the Inspector |
| `scripts/enemy.lua`, `enemy_hitbox.lua` | Walks, turns at walls and ledges; stomped from above, hurts otherwise |
| `scripts/coin.lua`, `hazard.lua`, `goal.lua`, `hud.lua` | Pickups, spikes, the door (the next level, or the result after the last), the coin count, level, lives and messages |
| `components/` | Starter physics components to drag into a level: a crate that falls and gets pushed, a static platform, a trigger zone (an area that reports what enters it) |
| `textures/` | Kenney's Pixel Platformer (CC0) |

## Make it yours

- **Paint a level**: select *Level* (solid) or *Decor* and use the tile
  brush in the viewport (Inspector > Tile Map).
- **More of something**: duplicate a coin, a spike or an enemy (Cmd/Ctrl+D)
  and move it.
- **A third level**: duplicate `level2.scene.json` (Assets > right-click >
  Duplicate), change it, set its HUD's *Level* to 3 and add it to
  `Game.LEVELS` at the top of `game.lua`.
- **Lives**: `Game.LIVES` in `game.lua`; the HUD's *Lives* is what a level
  played on its own (F6) starts with.
- **Feel**: the player's properties (speed, jump velocity, coyote time...).
- **Start over**: Game > Save Data > Delete Save Files.

The game runs at 320x180, scaled up in whole steps (Project Settings >
Video): crisp pixels at any window size.
