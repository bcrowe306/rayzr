## Use it for

- **Shared tuning data**: weapon stats, enemy types, items, dialogue lines as `.resource.json` files of a Lua class. `Resource.load(path)` returns the shared table - the same one for every script that loads it.
- **A copy of its own**: `Resource.new(path)` loads a fresh table from the file for this component instance - a health pool or an inventory each enemy changes without touching the others.
- **A copy as it is now**: `res:duplicate()` copies a resource with its current values (an upgraded weapon kept per turret).
- **One node's own variant, or one with no file**: a `type = "resource"` property can hold a file with this node's own values on top, or a resource embedded in the scene - set up in the Inspector (the field's **+**). Scripts get a table either way. See [Resources](../../engine/docs/resources.md).
- **Picking one by path at runtime**: a loot table naming files, a level choosing its enemy set - when a `type = "resource"` property (picked in the Inspector) doesn't fit.

## Example

A turret that fires with the stats of a shared weapon resource and, when upgraded, gets its own faster copy - the script is on the turret's root; `resources/blaster.resource.json` is a resource of a class with `damage` and `cooldown` properties.

```lua
---@class Turret : ScriptInstanceBase
local Turret = {}

function Turret:ready()
    -- The shared table: every turret reads the same tuning.
    self.weapon = Resource.load("resources/blaster.resource.json")
    self.cooldown = 0
end

---@param dt number
function Turret:update(dt)
    if not self.weapon then return end   -- a warning said what's wrong
    self.cooldown = self.cooldown - dt
    if self.cooldown <= 0 then
        self.cooldown = self.weapon.cooldown
        Log.info("bang for " .. self.weapon.damage)
    end
end

-- A power-up calls this: only this turret gets faster.
function Turret:upgrade()
    if not self.weapon then return end
    if not self.upgraded then
        self.weapon = Resource.new(self.weapon.resource_path)
        self.upgraded = true
    end
    self.weapon.cooldown = self.weapon.cooldown * 0.5
end

return Turret
```

## Notes

- Never change a shared table from `Resource.load` for one object: every user sees the change. Use `Resource.new` or `duplicate()` for per-object values.
- Changes made at runtime are never written to the file. Saving the file in the editor re-applies its values to every live table.
- Both return nil when the file is missing or its script isn't a resource class (`MyClass.resource = { ... }`); a warning says which.
- `on_load(self)` runs once per table after its values are set - for `Resource.new` too, but not for `duplicate()`. Copies are released with the component instance that made them.
- Making classes and resource files in the editor: [Resources](../../engine/docs/resources.md).
