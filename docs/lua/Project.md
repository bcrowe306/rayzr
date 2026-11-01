## Use it for

- **Reading your own data files**: `Project.read_file` returns a text file
  from the project - credits, a word list, dialogue lines - whether the
  game runs from the project folder or from an exported `.rayzr` package.
  `Project.read_json` reads a JSON file as Lua tables: item lists, enemy
  stats, level settings.
- **Optional content**: `Project.has_file` checks a file is there before
  you load it (a bonus level, a translated text file).
- **Debugging a scene**: `Project.serialize_scene` returns the running
  scene as JSON text, in the scene file format - log its size or print it
  to see what a script changed.
- **Tools and launchers**: `Project.load` opens a project folder or
  `.rayzr` package, and `Project.export_rayzr` packs a project folder
  into a `.rayzr` file. These are for tooling, not for gameplay scripts.

## Example

A credits screen that fills a label from `data/credits.txt`, one name per
line, and shows a fallback when the file is missing. The script is on a
[UI Label](../nodes/UILabelNode.md).

```lua
---@class Credits : ScriptInstanceBase
local Credits = {}

function Credits:ready()
    local label = self.node ---@type UILabelNode
    local path = "data/credits.txt"
    if not Project.has_file(path) then
        label.text = "Made with Rayzr"
        return
    end
    local lines = {}
    for line in Project.read_file(path):gmatch("[^\n]+") do
        lines[#lines + 1] = line
    end
    label.text = table.concat(lines, "\n")
    Log.info("credits:", #lines, "names")
end

function Credits:update(dt)
    if Input.is_key_pressed("F9") then
        Log.info("scene JSON is", #Project.serialize_scene(), "bytes")
    end
end

return Credits
```

## Notes

- `read_file` and `has_file` take project-relative paths. In an exported
  game they read from the `.rayzr` package, so files in the project ship
  with the game.
- `read_file` returns nil when the file isn't found. `read_json` returns
  nil (with a warning) when it's missing or isn't JSON; JSON numbers come
  back as floats (`5.0`, equal to `5`), `null` as nil.
- `load` and `export_rayzr` take paths on disk (relative to the working
  directory, or absolute), not project-relative ones. Loading a project
  from a running game replaces its assets and settings.
- `export_ore` is the old name of `export_rayzr`, kept for old scripts.
- Player data doesn't belong in the project: use the [Save](Save.md)
  module, which writes to the player's user-data folder.
