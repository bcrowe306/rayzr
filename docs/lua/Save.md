## Use it for

- **High scores and records**: `Save.get(key, default)` reads a value with
  a fallback for the first run; `Save.set` stores the new one.
- **Progress**: unlocked levels, collected items, the last checkpoint -
  keep them in a table under one key. Tables you got from `Save.get` are
  live, so changing them changes the save data too.
- **Writing at the right moment**: data is written when the game quits;
  call `Save.flush` at checkpoints or level ends so a crash loses nothing.
- **Several save files**: `Save.slot("slot_2")` switches to another file
  (writing the current one first) for a "pick a save" menu; `Save.get_path()`
  shows where it lives.
- **Starting over**: `Save.delete` removes one key, `Save.clear` every key;
  `Save.has` and `Save.keys` look at what's there.

## Example

A level's goal: when the player reaches it, it records the best time,
unlocks the next level, writes the save file and moves on. The script is on
an [Area](../nodes/AreaNode.md) at the end of the level.

```lua
---@class Goal : ScriptInstanceBase
local Goal = {}

Goal.properties = {
    level = { type = "int", default = 1 },
    next_scene = { type = "string", default = "level_2" },
}

function Goal:ready()
    self.started = Engine.get_time()
    self.done = false
end

---@param other Node?
function Goal:on_body_entered(other)
    if self.done or not other or not other:has_tag("player") then return end
    self.done = true

    local time = Engine.get_time() - self.started
    local key = "best_time_" .. self.level
    if time < Save.get(key, math.huge) then
        Save.set(key, time)
        Log.info("New record:", time)
    end

    local progress = Save.get("progress", { unlocked = 1 })
    progress.unlocked = math.max(progress.unlocked, self.level + 1)
    Save.set("progress", progress)

    if not Save.flush() then Log.warn("could not write", Save.get_path()) end
    Scene.change_scene(self.next_scene)
end

return Goal
```

## Notes

- Values are plain data: booleans, numbers, strings and tables of those.
  Functions and nodes can't be saved (they're written as null, with a
  warning). Keys must be strings.
- The file is JSON in the player's user-data folder: macOS
  `~/Library/Application Support/<game>/`, Windows `%APPDATA%\<game>\`,
  Linux `~/.local/share/<game>/`. The default slot is `save.json`.
- It's read the first time you use `Save`, and written by `Save.flush` and
  when the game quits. Writes go to a temporary file first, so a crash
  mid-write keeps the old save.
- `Save.slot(name)` returns the slot in use after the call, not the one
  before.
- The player's accessibility settings and input bindings are saved
  separately (see [Accessibility](Accessibility.md) and
  [Input](Input.md)).
