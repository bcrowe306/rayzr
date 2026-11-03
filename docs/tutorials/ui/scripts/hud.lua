-- The HUD: a Screen Layer (anchored top left) with the health bar, and a
-- second Screen Layer (top right) with the score. It listens to the
-- player's and the coins' events and shows them.

---@class Hud : ScriptInstanceBase
local Hud = {}

function Hud:ready()
    self.score = 0
    self.bar = self.node:get_node("HealthBar") ---@type UIProgressBarNode
    self.label = self.node:get_node("TopRight/Score") ---@type UILabelNode
    Events.connect("coin_collected", function(points)
        self.score = self.score + points
        self.label:set_text("Score: " .. self.score)
    end)
    Events.connect("health_changed", function(health)
        self.bar:set_property("value", health)
        -- Red when it's low.
        self.bar:set_property("fill_color", health <= 25 and "#e53e3eff" or "#10b981ff")
    end)
end

return Hud
