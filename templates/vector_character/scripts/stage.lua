-- A stage: walk Pip to the flag (Goal) before the clock runs out. Thorn
-- bushes and bees (nodes tagged "hazard", scripts/hazard.lua) end the game
-- at a touch. On the way Pep waits: Pip stops to talk to him (each says his
-- line, lip-synced; the clock waits; T, Enter or Space skips a line), then
-- walks on.
--
-- The game (Game, scripts/game.lua): the flag is the next stage (saved as
-- reached; the time taken is its best if it's the fastest yet), or the
-- result screen after the last; a hazard or the clock is game over.

---@class Stage : ScriptInstanceBase
local Stage = {}

Stage.properties = {
    stage      = { type = "int", default = 1, min = 1, label = "Stage" },          -- this scene's place in Game.LEVELS
    time_limit = { type = "float", default = 25, min = 1, label = "Time Limit" },  -- seconds to reach the flag
    pip_line   = { type = "string", default = "Hello!", label = "Pip Says" },
    pep_line   = { type = "string", default = "Hi, Pip!", label = "Pep Says" },
}

local PIP_HALF_WIDTH, PIP_HEIGHT = 28, 240 -- Pip's box (at the scene's scale 0.6)
local TALK_GAP = 110                        -- how close Pip walks up to Pep
local BUBBLE_UP = 270                       -- a speech line's height over the feet

function Stage:ready()
    self.pip = Scene.find_node("Pip"):get_script()
    self.pep = Scene.find_node("Pep")
    self.pep_rig = Scene.find_node("PepRig") ---@type SkeletonNode
    self.pep_lips = Scene.find_node("PepLipSync") ---@type LipSyncNode
    self.goal_x = Scene.find_node("Goal").position.x
    self.hazards = Scene.find_by_tag("hazard")
    self.message = Scene.find_node("Message")
    self.time_text = Scene.find_node("Time")
    self.pip_says, self.pep_says = Scene.find_node("PipSays"), Scene.find_node("PepSays")
    self.run = Game:ensure_run(self.stage)
    self.time_left = self.time_limit
    self.met = false   -- talked to Pep
    self.chat = nil    -- the line being said: 1 Pip's, 2 Pep's
    self.done = false  -- at the flag (or lost): the stage takes no more input
    self:show_time()
end

function Stage:show_time()
    local t = math.max(0, math.ceil(self.time_left))
    self.time_text.text = string.format("Time %d", t)
    self.time_text:set_property("color", t <= 5 and "#c0392bff" or "#24425cff")
end

-- say: line i of the chat (Pip's, then Pep's), with its voice; past the last, walk on.
function Stage:say(i)
    self.chat, self.chat_time = i, 0
    self.pip_says.text = i == 1 and self.pip_line or ""
    self.pep_says.text = i == 2 and self.pep_line or ""
    if i == 1 then
        self.pip:talk()
    elseif i == 2 then
        self.pep_lips:lipsync_play("audio/pep_mumble.wav")
        self.pep_rig:skeleton_play("talk")
    else
        self.chat = nil
        self.met = true
        self.pip.frozen = false
        self.pep_rig:skeleton_play("idle")
    end
end

-- finish: the stage is over; `after` runs `delay` seconds later.
function Stage:finish(message, delay, after)
    self.done = true
    self.pip.frozen = true
    self.message.text = message
    self.after, self.after_time = after, delay
end

function Stage:lose(message, reason)
    Game.lose_reason = reason
    self:finish(message, 1.5, function() Game:finish(false) end)
end

-- touching: a hazard Pip's box overlaps.
function Stage:touching()
    local p = self.pip.node.position
    local l, t, r, b = p.x - PIP_HALF_WIDTH, p.y - PIP_HEIGHT, p.x + PIP_HALF_WIDTH, p.y
    for _, h in ipairs(self.hazards) do
        local s = h:get_script()
        local hl, ht, hr, hb = s:box()
        if l < hr and r > hl and t < hb and b > ht then return s end
    end
end

function Stage:update(dt)
    local pp = self.pip.node.position
    self.pip_says.position = Vec2(pp.x, pp.y - BUBBLE_UP)
    self.pep_says.position = Vec2(self.pep.position.x, self.pep.position.y - BUBBLE_UP)
    if self.after then
        self.after_time = self.after_time - dt
        if self.after_time <= 0 then
            local after = self.after
            self.after = nil
            after()
        end
        return
    end
    if self.done then return end
    -- The chat: each line until its voice ends (or a key skips it).
    if self.chat then
        self.chat_time = self.chat_time + dt
        local lips = self.chat == 1 and self.pip.lips or self.pep_lips
        local over = self.chat_time > 0.3 and not lips:lipsync_is_playing()
        if over or Input.is_action_pressed("talk") or Input.is_action_pressed("confirm") then
            self:say(self.chat + 1)
        end
        return -- (the clock waits)
    end
    -- The clock.
    self.time_left = self.time_left - dt
    self:show_time()
    if self.time_left <= 0 then
        self:lose("Out of time!", "Out of time")
        return
    end
    local hit = self:touching()
    if hit then
        self:lose("Ouch!", hit.kind == "bee" and "Stung by a bee" or "Caught in the thorns")
        return
    end
    -- Pep: Pip walks up to him and they talk.
    if not self.met and pp.x >= self.pep.position.x - TALK_GAP then
        self.pip.frozen = true
        self.pip.node.position = Vec2(self.pep.position.x - TALK_GAP, pp.y)
        self.pip.rig.scale = Vec2(1, 1) -- (facing Pep)
        self:say(1)
        return
    end
    -- The flag.
    if pp.x >= self.goal_x then
        local taken = math.floor((self.time_limit - self.time_left) * 10 + 0.5) / 10
        local last = self.stage >= #Game.LEVELS
        self:finish(last and "The last flag!" or "Flag!", 1.2, function()
            Game:add_score(taken)
            Game:level_done(self.stage, taken)
        end)
    end
end

return Stage
