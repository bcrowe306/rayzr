# Writing editor plugins

Plugins add commands, panels and automation to the editor in Lua. The design
and the full API list are in [plugins.md](plugins.md); completion and hover
docs for everything here come from `.rayzr/definitions/editor_api.lua`
(written once the project has a `plugins/` folder).

## Your first plugin

**Tools > New Plugin...** asks for a name and writes
`plugins/<id>/plugin.json` and `plugins/<id>/main.lua` - a command (Tools >
Say Hello), a panel docked next to the Inspector and an event - then starts
it and opens `main.lua`. Saving the file reloads the plugin: edit, save, try.

**Settings > Plugins** lists every plugin with its state, its log (`print`,
`Editor.log`) and its last error. Reload, turn it off or open its folder there.

```
plugins/my_plugin/
  plugin.json     name, version, description, main, permissions
  main.lua        runs when the plugin starts; require() loads from this folder
```

User plugins (every project) go in `~/.config/rayzr_editor/plugins/<id>/`
(Settings > Plugins > User Plugins Folder).

## Rules of thumb

- **Scene changes go inside `Editor.edit(label, fn)`**: one undo step. Changes
  outside it work but can't be undone.
- **An error stops only your plugin** (shown in Settings > Plugins and the
  console); fix and save to restart it.
- **A panel's `draw` runs every frame**: cache what's expensive (walking the
  scene, reading files) and redo it on an event or a button. A panel whose
  `draw` takes over 4 ms is noted once in its plugin's **Log** (Settings >
  Plugins).
- **Dialogs are async**: `Editor.prompt`, `Editor.confirm`,
  `Editor.pick_file`, `Editor.run` and `Editor.http` call you back later.
  Capture what you need (`local nodes = Editor.selection()`) before asking.
- **Files**: `Editor.fs` reads and writes inside the project (relative
  paths) and your plugin's folder only. `io` and `os.execute` don't exist.
- **Processes and network** need `"process"` / `"network"` in `permissions`;
  the trust prompt lists them.
- The engine's Node API works on the **scene being edited**: `Scene.find_node`,
  `node.position`, `node:get_children()`, `node:get_type()`...

## Examples

Each one is a working plugin in [plugin_examples/](plugin_examples/): copy
the folder into your project's `plugins/`. (`tests/drive/plugin_examples.drive`
runs them.)

### Align and distribute - [align_tools](plugin_examples/align_tools/main.lua)

Commands in a submenu (`menu = "Tools/Align"`) with shortcuts, greyed out
unless enough nodes are selected (`enabled`), kept off while typing code
(`scope = "scene"`); each move is one `Editor.edit`.

```lua
Editor.add_command{
    id = "left", label = "Align Left", menu = "Tools/Align", scope = "scene",
    shortcut = "Primary+Alt+Left", enabled = two_or_more,
    run = function()
        local x = min_of(Editor.selection(), "x")
        move("Align left", function(n) return x, n.position.y end)
    end,
}
```

### Batch rename - [batch_rename](plugin_examples/batch_rename/main.lua)

`Editor.prompt` with a default; the edit happens in its callback (the
selection was captured first).

```lua
Editor.prompt("Rename " .. #nodes .. " nodes", "{name}_#", function(pattern)
    if not pattern then return end -- cancelled
    Editor.edit("Batch rename", function()
        for i, n in ipairs(nodes) do n.name = pattern:gsub("#", tostring(i)) end
    end)
end)
```

### Level stats panel - [level_stats](plugin_examples/level_stats/main.lua)

A docked panel with a table; the counts are cached and redone on
`scene_saved` or Refresh.

```lua
Editor.add_panel{
    id = "stats", title = "Level Stats", dock = "right",
    draw = function(ui)
        ui.text("Nodes: " .. stats.total)
        if ui.button("Refresh") then count() end
        if ui.begin_table("types", 2) then
            for _, row in ipairs(stats.types) do
                ui.next_cell() ui.text(row[1])
                ui.next_cell() ui.text(tostring(row[2]))
            end
            ui.end_table()
        end
    end,
}
```

### Export and zip - [export_zip](plugin_examples/export_zip/main.lua)

An `after_export` hook that runs the system's `zip` (`"permissions":
["process"]`), and a toggle command (`checked`). `before_play` works the same
way and can cancel Play: return `false, "reason"`.

```lua
Editor.on("after_export", function(preset, dir)
    Editor.run("zip", {"-r", "-q", dir .. ".zip", dir}, function(ok, output, code)
        if ok and code == 0 then Editor.notify("zipped " .. preset) end
    end)
end)
```

## Inspectors, overlays, importers

`Editor.add_inspector` adds a section to the Inspector for one node type,
`Editor.add_overlay` draws over the viewport with draggable handles,
`Editor.add_importer` teaches the importer a new file type - see
[plugins.md](plugins.md#d-inspectors-viewport-importers).
`tests/drive/fixtures/plugins/extend_zz` uses all three.

## Testing a plugin

Drives (`tests/drive/*.drive`) run plugin commands by id, read a plugin's
state and log, and click panel widgets:

```
command plugin.align_tools.top
expect plugin:align_tools.state == running
expect plugin:align_tools.log contains hello
click @panel:plugin.level_stats.stats:Refresh
```
