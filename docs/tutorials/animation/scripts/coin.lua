-- A coin: a Trigger Area with an Animation Player child named Sprite. Its
-- "bob" animation (a position track) plays by itself (Autoplay); touching
-- the player plays "collect" (scale and position tracks), and the coin is
-- removed when that animation finishes.

---@class Coin : ScriptInstanceBase
local Coin = {}

function Coin:ready()
    self.sprite = self.node:get_node("Sprite") ---@type AnimationPlayerNode
    self.sprite:connect("animation_finished", function(name)
        if name == "collect" then self.node:destroy() end
    end)
end

---@param body Node?
function Coin:on_body_entered(body)
    if self.taken or body == nil or not body:has_tag("player") then return end
    self.taken = true
    -- Crossfade the bob's position into the collect animation over 0.1 s.
    self.sprite:animation_play("collect", 0.1)
end

return Coin
