-- Pip's Walk's lines (make_templates.py puts them in game.lua, in place
-- of the common ones): times.

-- The title's line under the name: each stage's best time.
function Game:best_text()
    local parts = {}
    for i = 1, #Game.LEVELS do
        local t = self.progress.level_best["level" .. i]
        parts[#parts + 1] = i .. ": " .. (t and string.format("%.1f s", t) or "-")
    end
    return "Best times  " .. table.concat(parts, "   ")
end

---@class GameGlobal
---@field lose_reason? string What ended the run (stage.lua sets it)

-- The result screen's line: a won game's time, or what ended it (stage.lua
-- sets Game.lose_reason).
---@param r table Game.result
function Game:result_text(r)
    if r.won then return string.format("%.1f s in all", r.score) end
    return (self.lose_reason or "Game over") .. " on stage " .. r.level
end
