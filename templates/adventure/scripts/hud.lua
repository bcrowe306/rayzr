-- The HUD (layer 7: fixed on screen): the coin count, the level, the lives
-- and messages. It also starts the run (Game.ensure_run) when this level is
-- played on its own - from the editor (F6) - with Lives lives.

---@class Hud : ScriptInstanceBase
local Hud = {}

Hud.properties = {
    level = { type = "int", default = 1, min = 1, label = "Level" },  -- this scene's place in Game.LEVELS
    lives = { type = "int", default = 3, min = 1, label = "Lives" },  -- played on its own: the lives it starts with
}

function Hud:ready()
    self.run = Game:ensure_run(self.level, self.lives)
    self.coins = 0
    self.total = #Scene.find_by_tag("coin")
    self.label = self.node:get_child("Coins")
    self.msg = self.node:get_child("Message")
    self.node:get_child("LevelText").text = string.format("Level %d / %d", self.level, #Game.LEVELS)
    self.node:get_child("Lives").text = string.format("Lives %d", self.run.lives)
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
