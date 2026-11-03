-- The stairs: reaching them finishes the floor - Game goes on to the next
-- one (saved as unlocked), or to the result screen after the last.

---@class Exit : ScriptInstanceBase
local Exit = {}

function Exit:ready() self.timer = nil end

---@param other Node?
function Exit:on_body_entered(other)
    if self.timer or not other or not other:has_tag("player") then return end
    local hud = Scene.find_node("HUD"):get_script()
    hud:message(hud.level < #Game.LEVELS and "Down the stairs!" or "You escaped!")
    other:get_script():freeze()
    self.timer = 1.2
end

function Exit:update(dt)
    if not self.timer then return end
    self.timer = self.timer - dt
    if self.timer <= 0 then
        self.timer = 1e9
        Game:level_done(Scene.find_node("HUD"):get_script().level)
    end
end

return Exit
