# Modding

An exported Rayzr game can let its players add **mods**: folders of files
that replace or add to the game's (textures, sounds, scenes, data), and,
when you allow it, Lua scripts. Mod scripts run sandboxed. This page is for
both sides: the developer deciding what mods may do, and the player (or
modder) installing and writing them.

Mods work in desktop exports (macOS, Windows, Linux). The web and Android
runners don't look for mods: players can't reach their files there.

## For developers

### Turning mods on

**Project Settings > Export > Mods** (`project.json` `"export": {"mods": ...}`):

| Setting | What mods may do |
|---|---|
| **Off** (`"off"`, the default) | Nothing: the game never looks for mods. |
| **Assets only** (`"assets"`) | Replace the game's files and add new ones: images, sounds, music, fonts, scenes, components, JSON data. A mod's `.lua` files are ignored. |
| **Assets + scripts** (`"scripts"`) | The same, and the mods' Lua runs: a `main.lua`, hooks, and any `.lua` the mod adds or replaces. |

The setting goes into the exported `game.rayzr`. Editor **Play** never
loads mods, so your own play-testing isn't affected by mods you installed.

### What a mod can reach

- **Files**: any path in your project except `project.json`. A mod's
  `textures/coin.png` replaces yours wherever it's used (sprites, the
  atlas, Aseprite files, normal maps); `Project.read_file` /
  `Project.read_json` read the mod's copy too. If two mods have the same
  file, the one loaded later wins.
- **Lua** (with scripts on): your game's API - `Scene`, `Node` methods,
  `Events`, `Input`, `Save`, `Audio`, `Tween` and the rest - and the
  globals your scripts define. Not: `io`, `os` (only `os.clock`, `time`,
  `date`, `difftime`), `debug`, `package`, `dofile`, `loadfile`,
  `Console.execute`, `Project.load` / `export_rayzr`, `Test`. `load` takes
  text only; `require` loads only the mod's own files.
- **CPU**: each mod has an instruction budget - 20 million Lua
  instructions a frame, 200 million while its `main.lua` runs. A mod that
  goes over (an endless loop) is stopped and the game goes on.
- **Errors**: a mod with a bad `mod.json`, a missing dependency, an error
  in its `main.lua` or in a hook is set aside with a warning in the log;
  the game goes on without it.

Anything your scripts put in `_G` is reachable by mods: keep helpers that
write files or call `os` as locals if you allow scripts.

### Offering hooks

Mods listen with `Mods.on(name, fn)`. Built in:

| Hook | Values | When |
|---|---|---|
| `mods_loaded` | - | Every mod's `main.lua` ran, before the first scene starts. |
| `scene_ready` | the scene's name | A scene started (its nodes are ready). |
| `update` | `dt` | Every frame, before the game's own update. |

Every [event-bus](../../docs/lua/Events.md) event reaches `Mods.on` too
(`Events.emit("score_changed", 10)`), and your scripts can offer hooks of
their own with `Mods.emit`:

```lua
-- In the game's shop script: mods may add items to the table.
local items = Project.read_json("data/shop.json")
Mods.emit("shop_items", items)
```

### A mods menu

`Mods.list()` has everything a menu needs; changes apply on the next
launch. A minimal menu script for a VBox node in a menu scene:

```lua
---@class ModsMenu : ScriptInstanceBase
local ModsMenu = {}

function ModsMenu:ready()
    if Mods.mode() == "off" then self.node.visible = false return end
    for _, mod in ipairs(Mods.list()) do
        local row = Scene.create("UICheckboxNode", self.node)
        row.label = mod.name .. " " .. mod.version .. (mod.error and ("  (" .. mod.error .. ")") or "")
        row.checked = mod.enabled
        row:connect("value_changed", function(on)
            Mods.set_enabled(mod.id, on)
            Scene.find_node("RestartNote").visible = Mods.restart_needed()
        end)
    end
    Scene.find_node("Where").text = "Put mods in " .. Mods.folders()[1]
end

return ModsMenu
```

See [Mods](../../docs/lua/Mods.md) for every function.

### Testing your game with mods

Run the exported game with a mods folder of your own and a scratch
user-data folder:

```bash
./MyGame --mods ~/my_test_mods --user-data /tmp/mygame_test
```

`--no-mods` plays the game as shipped. The log (start the game from a
terminal) lists the mods loaded and why any weren't.

## For players and modders

### Installing a mod

Put the mod's folder in one of these (make the `mods` folder if it isn't there):

- `mods/` next to the game: beside `MyGame.exe` (Windows), the `MyGame`
  binary or `.AppDir` (Linux), or `MyGame.app` (macOS);
- `mods/` in the game's user-data folder (where its saves are): macOS
  `~/Library/Application Support/<game>/mods`, Windows
  `%APPDATA%\<game>\mods`, Linux `~/.local/share/<game>/mods`.

A mod in the user-data folder wins over one with the same id next to the
game (handy for a newer version).

### Turning mods off and ordering them

The game's mods menu, if it has one, or `mods.json` in the user-data
folder:

```json
{
  "disabled": ["hard_mode"],
  "order": ["core_lib", "big_coins"]
}
```

`order` loads those mods first, in that order; the others follow by their
`load_order`, then by id. A mod always loads after the mods it depends on.
Changes apply when the game starts.

### Writing a mod

A mod is a folder with a `mod.json`:

```json
{
  "id": "big_coins",
  "name": "Big Coins",
  "version": "1.0.0",
  "description": "Coins twice the size, worth twice as much.",
  "author": "you",
  "game": ">=1.2.0",
  "load_order": 0,
  "dependencies": ["core_lib", "other_mod>=2.0.0"],
  "scenes": ["scenes/coin_room.scene.json"],
  "main": "main.lua"
}
```

| Field | Meaning |
|---|---|
| `id` | Its name in `mods.json` and for dependencies (default: the folder's name). |
| `name`, `version`, `description`, `author` | Shown in the game's mods menu. |
| `game` | The oldest game version it works with; an older game doesn't load it. |
| `load_order` | Lower loads first (default 0); later mods win when files clash. |
| `dependencies` | Mods that must be installed and loaded first (`id`, or `id>=version`). |
| `scenes` | New scene files to register, so `Scene.change_scene("coin_room")` finds them. |
| `main` | The script that runs once at start (default `main.lua`; scripts mode only). |

Everything else in the folder mirrors the game's files: `big_coins/textures/coin.png`
replaces the game's `textures/coin.png`; a path the game doesn't have is a
new file (a new texture for your new scene).

### Mod scripts

When the game allows scripts, `main.lua` runs once, before the first
scene. Use the hooks to change the game as it plays:

```lua
-- big_coins/main.lua
Mods.on("scene_ready", function(scene)
    for _, coin in ipairs(Scene.find_by_tag("coin")) do
        coin.scale = coin.scale * 2
    end
end)

Mods.on("coin_collected", function(value) -- an event the game emits
    Log.info("big coin!", value)
end)
```

Inside a mod, `Mods.self` is the mod (`id`, `name`, `version`, `folder`),
and `Mods.fs` reads its files and keeps its own data:

```lua
local defaults = Mods.fs.read("defaults.json")               -- the mod's folder (read only)
local saved = Mods.fs.read("save:settings.json") or defaults  -- <user data>/mod_data/big_coins/
Mods.fs.write("save:settings.json", saved)
```

`require("util.math")` loads the mod's `util/math.lua`. A `.lua` file the
mod puts at one of the game's script paths replaces that script, and runs
in the mod's sandbox like the rest of its code.

## Notes

- Mods load once, when the game starts; `Mods.set_enabled` and
  `Mods.set_order` write `mods.json` for the next launch
  (`Mods.restart_needed()` says when one is waiting).
- A stopped or failed mod's hooks don't run again. Files it provides stay
  in use for the rest of the run.
- Mods can't replace `project.json`, read outside their folder (no
  absolute paths, no `..`), or write anywhere but their own save folder.
- Related: [Export](../../docs/editor/export.md), [Save](../../docs/lua/Save.md),
  [Events](events.md).
