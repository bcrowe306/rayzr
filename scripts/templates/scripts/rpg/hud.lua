-- The HUD (layer 7, fixed on screen): hearts, the key, the floor, the
-- gold, a hint for what E does, and messages. It also starts the run
-- (Game.ensure_run) when this floor is played on its own - from the editor
-- (F6).

---@class Hud : ScriptInstanceBase
local Hud = {}

Hud.properties = {
    level = { type = "int", default = 1, min = 1, label = "Floor" },  -- this scene's place in Game.LEVELS
}

function Hud:ready()
    self.run = Game:ensure_run(self.level)
    self.msg_timer = 0
    self.node:get_child("FloorText").text = string.format("Floor %d / %d", self.level, #Game.LEVELS)
    self:refresh()
end

-- refresh: the gold (the run's score).
function Hud:refresh()
    self.node:get_child("Gold").text = string.format("Gold %d", self.run.score)
end

function Hud:set_hearts(hp, max)
    for i = 1, max do
        local h = self.node:get_child("Heart" .. i)
        if h then
            local want = i <= hp and "full" or "empty"
            if h:animation_get_current() ~= want then h:animation_play(want) end
        end
    end
end

function Hud:set_key(has)
    self.node:get_child("Key").text = has and "Key" or ""
end

function Hud:hint(text)
    local h = self.node:get_child("Hint")
    if h.text ~= text then h.text = text end
end

-- message: big text in the middle (seconds: then it goes; nil: it stays).
function Hud:message(text, seconds)
    self.node:get_child("Message").text = text
    self.msg_timer = seconds or 0
end

function Hud:update(dt)
    if self.msg_timer > 0 then
        self.msg_timer = self.msg_timer - dt
        if self.msg_timer <= 0 then self.node:get_child("Message").text = "" end
    end
end

return Hud
