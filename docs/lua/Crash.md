## Use it for

- **Hearing about crashes from players**: at startup, `Crash.pending()` returns the reports from earlier runs. Show them, send them to your own server, or ask the player to paste them to you - then `Crash.dismiss` each one so it isn't offered again.
- **Knowing what led up to a crash**: `Crash.note("entered level 3")` at milestones adds a line to the report's recent list, next to the last log lines.
- **Pointing players at the files**: `Crash.dir()` is the folder the reports are in ("" in the editor's Simulate, which has no game crash folder; `pending` is empty there).

## Example

A title screen that logs any pending crash reports, then dismisses them, and notes which scene the player starts. The script is on the title screen's root node.

```lua
---@class TitleScreen : ScriptInstanceBase
local TitleScreen = {}

function TitleScreen:ready()
    local reports = Crash.pending()
    if #reports > 0 then
        Log.warn(#reports .. " crash report(s) in " .. Crash.dir())
        for _, report in ipairs(reports) do
            -- Send report.text to your own server here, or show it to the player.
            Log.info(report.text)
            Crash.dismiss(report.path)
        end
    end
    Crash.note("title screen")
end

function TitleScreen:update(dt)
    if Input.is_action_pressed("confirm") then
        Crash.note("starting level 1")
        Scene.change_scene("scenes/level1.scene.json")
    end
end

return TitleScreen
```

## Notes

- **Nothing is sent anywhere by itself.** What happens to a report is up to your game.
- **Lua errors are not crashes**: the script stops, the error is logged, and the game keeps running. It shows up in a later report's recent lines.
- **Notes are cheap** (a fixed ring of the last 48 lines), but call them at milestones, not every frame.
- Dismissed reports stay in the folder, renamed `.seen`; the newest 20 reports are kept. The web build writes no reports. More in [Crash reports](../../engine/docs/crash_reports.md).
