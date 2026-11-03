# Shoot 'em up

Fly right through three stages of enemy planes: shoot them down, dodge
their bullets, keep your three lives - they last the whole game. A stage
is clear when every plane in it is gone; clear the third to win, lose
your last life and it's game over. A title screen, a settings screen (the
volume), a pause menu and a result screen come with it, and your best
score and the furthest stage reached (the title's **Stage** starts there)
are saved.

| Play | |
|---|---|
| Fly | WASD, arrows, gamepad stick / D-pad |
| Fire | Space, J, gamepad A (hold) |
| Pause | Esc, P, gamepad Start (the II button on a touch screen) |
| Menus | Up / down to pick, Enter or Space to choose, left / right to change a value; or click / tap a choice |

## What's where

| | |
|---|---|
| `scenes/title.scene.json` | The title screen: Play, the start Stage, Settings (Volume), Quit |
| `scenes/stage1.scene.json` ... `stage3` | The stages: the sea (scrolls), the player, the spawner (its properties are the stage), a Shots node holding bullets / enemies / explosions, the HUD, the pause menu |
| `scenes/result.scene.json` | After a win or a game over: the score, the best, Play again / Retry, the title |
| `scripts/game.lua` | The global `Game` (Project Settings > Globals): the stages in order, the run (stage, score, lives), the save data (`settings`, `progress` in `save.json`) |
| `scripts/menu.lua` | Every menu: Text nodes tagged `item` are the choices; its **Kind** says what they do |
| `components/` | Player and enemy bullets, the two enemy kinds (drifter, shooter), the explosion - edit them like scenes |
| `scripts/player.lua` | Movement inside the screen, firing (pooled bullets), lives, blinking after a hit |
| `scripts/enemy.lua`, `spawner.lua` | Enemy movement and shooting; a stage's enemies (how many, how often, shooters, how spread out) and when it's clear |
| `scripts/bullet.lua` | Hits by distance (no physics needed for this) |
| `scripts/hud.lua` | Score, best score, the stage, lives, messages |
| `textures/` | Kenney's Pixel Shmup (CC0) |

## Make it yours

- **A harder stage**: the Spawner's properties in a stage scene - Enemies,
  Interval, Shooter Every, Spread. **A fourth stage**: duplicate
  `stage3.scene.json`, set its Spawner's *Stage* to 4 and add it to
  `Game.LEVELS` in `game.lua`.

- **A new enemy**: duplicate `components/drifter.component.json`, change
  its sprite and properties (speed, wobble, hits, shoots, points), and
  spawn it in `spawner.lua`.
- **Power-ups**: a component that moves left like an enemy, and in its
  script checks the distance to the player (see `bullet.lua`).
- **Bullets** come from a pool (`Pool.take`, `destroy()` returns them): no
  allocations while playing, however many you fire.
