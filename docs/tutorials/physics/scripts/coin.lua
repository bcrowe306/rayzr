-- A coin: a Trigger Area. Its shape's Mask Layers hold only "Player", so
-- crates rolling through don't collect it.

---@class Coin : ScriptInstanceBase
local Coin = {}

-- body_entered: a body started overlapping the area.
---@param body Node?
function Coin:on_body_entered(body)
    if body == nil or not body:has_tag("player") then return end
    Events.emit("coin_collected", 1)
    self.node:destroy()
end

return Coin
