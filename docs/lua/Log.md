## Use it for

- **Tracing what a script does**: `Log.info` while you build a feature ("spawned at", x, y). `print` does the same thing.
- **Things that look wrong but aren't fatal**: `Log.warn` for a missing optional node or a fallback value.
- **Real problems**: `Log.error` when something the game needs isn't there. It only logs - the script keeps running.

## Example

A coin that checks its setup when the scene starts and logs when it is collected. The script is on the coin, which has an [Area](../nodes/AreaNode.md) child named *Pickup*.

```lua
---@class Coin : ScriptInstanceBase
local Coin = {}

Coin.properties = {
    value = { type = "int", default = 1, label = "Value" },
}

function Coin:ready()
    local pickup = self.node:get_node("Pickup")
    if not pickup then
        Log.error("Coin has no Pickup child:", self.node)
        return
    end
    if self.value <= 0 then
        Log.warn("Coin value is", self.value, "- using 1")
        self.value = 1
    end
    pickup:connect("body_entered", function(other)
        Log.info("coin collected by", other, "worth", self.value)
        self.node:destroy()
    end)
end

return Coin
```

## Notes

- **Any values, any number**: each argument is turned to text the way `tostring` does (nil, booleans, tables and nodes too) and they are joined with tabs. No need for `..`.
- **Where it shows**: the editor's **Console** while you play. In an exported game it goes to the game's log, and the last lines are kept for a crash report (see [Crash](Crash.md)).
- **Don't log every frame**: a line per frame floods the Console and slows the game. Log on changes instead.
