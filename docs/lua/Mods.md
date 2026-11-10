## Use it for

- **A mods menu**: `Mods.list()` has every installed mod - name, version,
  whether it's running and why not (`status`, `error`). `Mods.set_enabled`
  and `Mods.set_order` save the player's choices for the next launch;
  `Mods.restart_needed()` says when one is waiting. `Mods.folders()` tells
  players where mods go.
- **Hooks for modders**: `Mods.emit("shop_items", items)` from your scripts
  lets mods change things at the moments you choose; mods listen with
  `Mods.on`. Event-bus events (`Events.emit`) reach `Mods.on` too.
- **Inside a mod**: `Mods.on("scene_ready", fn)` / `"update"` /
  `"mods_loaded"` to change the game as it plays, `Mods.fs` for the mod's
  own files and save folder, `Mods.self` for its id and version.
- **Checking for a mod**: `Mods.is_loaded("hard_mode")` to adapt the game
  to a mod you know about.

Mods only load in exported desktop games whose project allows them
(**Project Settings > Export > Mods**); otherwise the lists are empty and
`Mods.mode()` is `"off"`. The whole picture - folders, `mod.json`, the
sandbox - is in the [Modding guide](../../engine/docs/modding.md).

## Example

A mods menu: a checkbox per mod, a note when a restart is needed. The
script is on a VBox (UI layout) node in the game's options scene, with a
Label named "RestartNote" beside it.

```lua
---@class ModsMenu : ScriptInstanceBase
local ModsMenu = {}

function ModsMenu:ready()
    local note = Scene.find_node("RestartNote")
    note.visible = false
    if Mods.mode() == "off" then
        self.node.visible = false
        return
    end
    for _, mod in ipairs(Mods.list()) do
        local box = Scene.create("UICheckboxNode", self.node)
        box.label = mod.name .. " " .. mod.version .. (mod.error and ("  - " .. mod.error) or "")
        box.checked = mod.enabled
        box:connect("value_changed", function(on)
            Mods.set_enabled(mod.id, on)
            note.visible = Mods.restart_needed()
        end)
    end
end

return ModsMenu
```

And a mod's `main.lua`, using a hook the game offers:

```lua
-- The game calls Mods.emit("shop_items", items) when its shop opens.
Mods.on("shop_items", function(items)
    items[#items + 1] = {name = "Golden Shovel", price = 500, icon = "textures/golden_shovel.png"}
end)

-- Remember a setting in the mod's own save folder.
local seen = Mods.fs.read("save:seen.txt")
if not seen then
    Mods.on("scene_ready", function() Log.info(Mods.self.name .. " is installed!") end)
    Mods.fs.write("save:seen.txt", "yes")
end
```

## Notes

- `Mods.set_enabled` / `Mods.set_order` write `mods.json` in the
  user-data folder; nothing changes until the game starts again.
- `Mods.on` handlers in a mod that errors (or runs past its CPU budget)
  stop, and the mod is marked `failed` / `stopped`; the game goes on. A
  handler from your own scripts that errors is logged like any script error.
- `Mods.fs` and `Mods.self` exist only in a mod's Lua. Its paths are
  inside the mod's folder (read only) or, with `save:`, its save folder
  `<user data>/mod_data/<id>/`.
- Related: [Events](Events.md), [Save](Save.md), [Project](Project.md).
