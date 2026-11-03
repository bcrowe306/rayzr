-- The door at the end of a level: its Next Level is where it leads - the
-- route. Reaching it adds the level's coins to the score, then goes there
-- (unlocked and saved: the title's Level can start there). A door with no
-- Next Level (or the title) is the end: the game is won.

---@class Goal : ScriptInstanceBase
local Goal = {}

Goal.properties = {
    next_level = { type = "scene", default = "", label = "Next Level" },
}

-- The place of a scene in Game.LEVELS (nil: not a level).
local function level_number(scene)
    for i, s in ipairs(Game.LEVELS) do
        if s == scene then return i end
    end
end

---@param other Node?
function Goal:on_body_entered(other)
    if not other or not other:has_tag("player") then return end
    local hud = Scene.find_node("HUD"):get_script()
    local n = level_number(self.next_level)
    hud:message(n and "Level complete!" or "You made it!")
    other:get_script():win(function()
        Game:add_score(hud.coins)
        if not n then
            Game:finish(true)
            return
        end
        -- The route: the next level is reached - unlocked, saved, played.
        local run = Game:ensure_run(hud.level)
        run.level = n
        Game.progress.unlocked = math.max(Game.progress.unlocked, n)
        Game:flush()
        Game:go(Game:level_scene(n))
    end)
end

return Goal
