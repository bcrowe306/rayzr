# Top-down RPG

A small, complete dungeon crawl over two floors: talk to the wizard,
fight the slimes, pick up gold, take each floor's key from its chest,
unlock the door and take the stairs - down to floor 2, then out. Your
three hearts are your life: lose them all and it's game over. A title
screen, a settings screen (the volume), a pause menu and a result screen
come with it, and your progress is saved: the furthest floor reached (the
title's **Floor** starts there) and the most gold.

| Play | |
|---|---|
| Move | WASD, arrows, gamepad stick / D-pad |
| Sword | Space, J, gamepad X |
| Talk / open | E, K, gamepad A (also goes on in a dialogue) |
| Pause | Esc, P, gamepad Start (the II button on a touch screen) |
| Menus | Up / down to pick, Enter or E to choose, left / right to change a value; or click / tap a choice |

## What's where

| | |
|---|---|
| `scenes/title.scene.json` | The title screen: Play, the start Floor, Settings (Volume), Quit |
| `scenes/floor1.scene.json`, `floor2.scene.json` | The floors: Floor and Walls (solid) tile maps, the wizard, slimes, potions, gold, the chest, the locked door, the stairs, the player, camera, HUD, dialogue box, pause menu |
| `scenes/result.scene.json` | After a win or a game over: the gold, the best, Play again / Retry, the title |
| `scripts/game.lua` | The global `Game` (Project Settings > Globals): the floors in order, the run (floor, gold), the save data (`settings`, `progress` in `save.json`) |
| `scripts/menu.lua` | Every menu: Text nodes tagged `item` are the choices; its **Kind** says what they do |
| `scripts/player.lua` | Eight-way movement, the sword, interacting, hearts and knockback; the last heart lost ends the game |
| `scripts/slime.lua` | Chases the player when close, hurts on touch, two hits to beat |
| `scripts/npc.lua`, `chest.lua`, `locked_door.lua` | Interactables: anything tagged `interactable` with `hint()` / `interact()` |
| `scripts/potion.lua`, `gold.lua`, `exit.lua`, `hud.lua` | A heal, the run's gold, the stairs (the next floor, or the result after the last), the HUD |
| `textures/` | Kenney's Tiny Dungeon (CC0); hearts and gold from Pixel Platformer |

## Make it yours

- **Paint rooms**: the *Walls* map is solid, *Floor* isn't (tile brush in
  the viewport).
- **A third floor**: duplicate `floor2.scene.json` (Assets > right-click >
  Duplicate), change it, set its HUD's *Floor* to 3 and add it to
  `Game.LEVELS` at the top of `game.lua`.
- **New interactables**: tag a node `interactable` and give its script
  `hint(player)` (what the E prompt says) and `interact(player)`.
- **More dialogue**: edit the lines in `npc.lua` (or give each NPC its own).
- **Tougher slimes**: their Speed / Sight / Hits in the Inspector.
- **Richer gold**: a pile's *Value*.
- **Start over**: Game > Save Data > Delete Save Files.
