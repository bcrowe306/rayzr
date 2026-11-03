-- A coin: a Trigger Area. Touching it is worth 10 points: it tells the HUD
-- with the "coin_collected" event and goes.

---@class Coin : ScriptInstanceBase
local Coin = {}

---@param body Node?
function Coin:on_body_entered(body)
    if body == nil or not body:has_tag("player") then return end
    Events.emit("coin_collected", 10)
    self.node:destroy()
end

return Coin
