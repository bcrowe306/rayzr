-- The HUD (layer 8: fixed on screen): the coin count and messages.

---@class Hud : ScriptInstanceBase
local Hud = {}

function Hud:ready()
    self.coins = 0
    self.total = #Scene.find_by_tag("coin")
    self.label = self.node:get_child("Coins")
    self.msg = self.node:get_child("Message")
    self:refresh()
end

function Hud:refresh()
    self.label.text = string.format("Coins %d / %d", self.coins, self.total)
end

function Hud:add_coin()
    self.coins = self.coins + 1
    self:refresh()
end

---@param text string
function Hud:message(text)
    self.msg.text = text
end

return Hud
