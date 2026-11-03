-- The HUD: the run's score (Game.run), the best score (saved: Game.progress),
-- the stage, the lives, messages.

---@class Hud : ScriptInstanceBase
local Hud = {}

function Hud:ready()
    self.stage = Scene.find_node("Spawner"):get_script().stage
    self.node:get_child("Stage").text = string.format("Stage %d / %d", self.stage, #Game.LEVELS)
end

function Hud:refresh()
    local run = Game.run
    self.node:get_child("Score").text = string.format("Score %d", run.score)
    self.node:get_child("High").text = string.format("Best %d", math.max(Game.progress.best, run.score))
end

function Hud:add_score(n)
    Game:add_score(n)
    self:refresh()
end

function Hud:set_lives(n)
    self.node:get_child("Lives").text = string.format("Lives %d", math.max(n, 0))
end

---@param text string
function Hud:message(text)
    self.node:get_child("Message").text = text
end

return Hud
