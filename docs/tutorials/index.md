# Tutorials

Each tutorial builds one small project step by step, teaching one part of
Rayzr on the way. They start from an empty project and end with a game you
can play; each one links a download of its finished project, so you can
compare your work or start from the end.

| Tutorial | You build | You learn |
|---|---|---|
| [Lua scripting basics](scripting.md) | Gem Catcher: move the player, catch a hopping gem, keep score | Attaching scripts, `ready` / `update`, Inspector properties, input, moving nodes, events and signals, finding nodes, timers, the Console, hot reload, errors |
| [Physics and collisions](physics.md) | Crate Yard: a character runs and jumps among falling crates, a lift and coins | Static, dynamic and kinematic bodies, collision shapes, layers and masks, gravity, a Character Mover, Trigger Areas, raycasts, debug drawing, collision events |
| [Tile maps and terrains](tilemaps.md) | Dungeon Room: walls, pillars, a stone walkway, a dripping gargoyle and a door that opens | Tile Maps and tilesets, painting / erasing / filling, maps as layers, Solid colliders, terrains (auto-tiling), animated tiles, the Components layer, reading and writing tiles from Lua |
| [The level generator](levelgen.md) | Crystal Cave: a new cave every time, coins on its floor, R digs another | The Level Generator window, noise / threshold / cave smoothing, previews, tile outputs with a terrain, playable levels (Connect Regions, Check), entity outputs, the Level Generator node, fixed and random seeds, generating from Lua |

New to the editor? Start with [Your first game](../getting-started/first-game.md):
it plays and changes a template in ten minutes. The
[editor tour](../editor/tour.md) names every part of the window.

## Opening a finished project

Unzip the download, then in the editor choose **File > Open Project...**
and pick the unzipped folder (the one with `project.json`). Press **F5** to
play it.
