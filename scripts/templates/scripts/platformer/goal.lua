-- The door at the end: reaching it finishes the level - its coins go to the
-- score, and Game goes on to the next level (saved as unlocked), or to the
-- result screen after the last. Next Level (a scene) goes there instead.

---@class Goal : ScriptInstanceBase
local Goal = {}

Goal.properties = {
    next_level = { type = "scene", default = "", label = "Next Level" },
}

---@param other Node?
function Goal:on_body_entered(other)
    if not other or not other:has_tag("player") then return end
    local hud = Scene.find_node("HUD"):get_script()
    hud:message("Level complete!")
    local next_level = self.next_level
    other:get_script():win(function()
        Game:add_score(hud.coins)
        if next_level ~= nil and next_level ~= "" then
            Game:go(next_level)
        else
            Game:level_done(hud.level, hud.coins)
        end
    end)
end

return Goal
