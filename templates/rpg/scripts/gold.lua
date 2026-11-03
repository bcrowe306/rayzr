-- Gold: walking over it picks it up - the run's score (Game.add_score; the
-- HUD shows it, the most gold in a game is saved).

---@class Gold : ScriptInstanceBase
local Gold = {}

Gold.properties = {
    value = { type = "int", default = 5, min = 1, label = "Value" },
}

---@param other Node?
function Gold:on_body_entered(other)
    if self.taken or not other or not other:has_tag("player") then return end
    self.taken = true
    Game:add_score(self.value)
    Scene.find_node("HUD"):get_script():refresh()
    self.node:destroy()
end

return Gold
