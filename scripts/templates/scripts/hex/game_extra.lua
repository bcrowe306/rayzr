-- Hex Island's lines (make_templates.py puts them in game.lua, in place
-- of the common ones): steps.

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
