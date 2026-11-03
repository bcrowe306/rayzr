-- Game: a global script (Project Settings > Globals, named Game), so every
-- scene reaches it as `Game`. It runs the game from screen to screen - the
-- title, the levels, the result - and owns the save data (the saving
-- tutorial's pattern), in the player's user-data folder, save.json:
--   settings   the player's settings: volume
--   progress   unlocked (the furthest level reached), best (the best score)
-- Both are live tables from Save.get: change a field and it's saved; flush()
-- writes the file now (the web has no "on quit": saves are written as they
-- happen).

---@class GameGlobal
local Game = {}

-- This game (make_templates.py writes it): its levels, in order; the lives a
-- run starts with; what the score counts; whether a lower result is better;
-- what a level is called.
Game.LEVELS = { "scenes/island1.scene.json", "scenes/island2.scene.json", "scenes/island3.scene.json" }
Game.LIVES = nil
Game.SCORE_NAME = "Steps"
Game.LOWER_IS_BETTER = true
Game.LEVEL_WORD = "Island"

local DEFAULT_SETTINGS = { volume = 0.8 }
local DEFAULT_PROGRESS = { unlocked = 1, best = 0, level_best = {} }

-- Fills in what a table is missing (a save from an older version, or none).
local function defaults(t, d)
    for key, value in pairs(d) do
        if t[key] == nil then t[key] = type(value) == "table" and {} or value end
    end
    return t
end

function Game:ready()
    self.settings = defaults(Save.get("settings", {}), DEFAULT_SETTINGS)
    Save.set("settings", self.settings)
    self.progress = defaults(Save.get("progress", {}), DEFAULT_PROGRESS)
    Save.set("progress", self.progress)
    self.run = nil    -- the game being played: level, score, lives
    self.result = nil -- what the result screen shows
    self:apply_settings()
end

-- Puts the settings into effect.
function Game:apply_settings()
    Audio.set_bus_volume("master", self.settings.volume)
end

-- set_volume: 0..1, kept and used at once (written by flush()).
---@param v number
function Game:set_volume(v)
    self.settings.volume = math.max(0, math.min(1, math.floor(v * 10 + 0.5) / 10))
    self:apply_settings()
end

-- The title's line under the name: the best score (the fewest moves a level).
function Game:best_text()
    if Game.LOWER_IS_BETTER then
        local parts = {}
        for i = 1, #Game.LEVELS do
            parts[#parts + 1] = i .. ": " .. (self.progress.level_best["level" .. i] or "-")
        end
        return "Fewest moves  " .. table.concat(parts, "   ")
    end
    return string.format("Best %d", self.progress.best)
end

-- The result screen's line: the run's score.
---@param r table Game.result
function Game:result_text(r)
    if Game.LOWER_IS_BETTER then
        return r.won and string.format("%d moves in all", r.score) or ("Out of moves on " .. Game.LEVEL_WORD:lower() .. " " .. r.level)
    end
    return string.format("%s %d", Game.SCORE_NAME, r.score)
end

-- Writes save.json now.
function Game:flush()
    Save.flush()
end

-- The scene of level n.
---@param n integer
function Game:level_scene(n)
    return Game.LEVELS[n]
end

-- new_run: a new game from level n (1: the start; the title can start at
-- any level reached before).
---@param n integer?
function Game:new_run(n)
    n = math.max(1, math.min(n or 1, self.progress.unlocked, #Game.LEVELS))
    self.run = { level = n, score = 0, lives = Game.LIVES }
    self:go(self:level_scene(n))
end

-- ensure_run: a level played straight from the editor (F6) or a test has no
-- run yet: one starting at that level, with these lives.
---@param n integer
---@param lives integer?
function Game:ensure_run(n, lives)
    if not self.run then self.run = { level = n, score = 0, lives = lives or Game.LIVES } end
    return self.run
end

---@param scene string
function Game:go(scene)
    Scene.change_scene(scene, { transition = "fade", duration = 0.3 })
end

-- add_score: points scored in the run (the HUD shows run.score).
---@param n number
function Game:add_score(n)
    if self.run then self.run.score = self.run.score + n end
end

-- level_done: level n is finished - the next one is unlocked (and saved),
-- then it's played; after the last, the game is won. `value` is the level's
-- own result for its best (Lower Is Better: the fewest moves).
---@param n integer
---@param value number?
function Game:level_done(n, value)
    local run = self:ensure_run(n)
    local p = self.progress
    if value then
        local key = "level" .. n
        local old = p.level_best[key]
        if old == nil or (Game.LOWER_IS_BETTER and value < old) or (not Game.LOWER_IS_BETTER and value > old) then
            p.level_best[key] = value
        end
    end
    if n < #Game.LEVELS then
        p.unlocked = math.max(p.unlocked, n + 1)
        run.level = n + 1
        self:flush()
        self:go(self:level_scene(n + 1))
    else
        self:finish(true)
    end
end

-- lose_life: true while lives are left (the level starts again); at none
-- the game is over.
function Game:lose_life()
    local run = self:ensure_run(1)
    run.lives = run.lives - 1
    if run.lives > 0 then return true end
    self:finish(false)
    return false
end

-- finish: the game won or lost - the best score is kept, the result screen shows.
---@param won boolean
function Game:finish(won)
    local run = self.run or { level = 1, score = 0 }
    local p = self.progress
    local best = false
    if not Game.LOWER_IS_BETTER and run.score > p.best then
        p.best, best = run.score, true
    end
    if won then p.wins = (p.wins or 0) + 1 end
    self.result = { won = won, score = run.score, level = run.level, new_best = best }
    self:flush()
    self:go("scenes/result.scene.json")
end

-- Hex Island's lines (make_templates.py adds them to game.lua): steps.

-- The title's line under the name: each island's fewest steps.
function Game:best_text()
    local parts = {}
    for i = 1, #Game.LEVELS do
        parts[#parts + 1] = i .. ": " .. (self.progress.level_best["level" .. i] or "-")
    end
    return "Fewest steps  " .. table.concat(parts, "   ")
end

-- The result screen's line: the steps a won game took, or where they ran out.
---@param r table Game.result
function Game:result_text(r)
    return r.won and string.format("%d steps in all", r.score) or ("Out of steps on island " .. r.level)
end

return Game
