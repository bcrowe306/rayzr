-- The score: listens to the gem's "caught" event and shows the total.

---@class Score : ScriptInstanceBase
local Score = {}

function Score:ready()
    self.score = 0
    local gem = Scene.find_node("Gem")
    if gem then
        gem:connect("caught", function(points)
            self.score = self.score + points
            self:refresh()
        end)
    end
    self:refresh()
end

function Score:refresh()
    self.node.text = "Score: " .. self.score
end

return Score
