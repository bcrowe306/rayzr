-- A crate: a Dynamic Physics Box. Gravity and collisions move it; it
-- reports what it bumps into.

---@class Crate : ScriptInstanceBase
local Crate = {}

function Crate:ready()
    self.bumps = 0
end

-- collision_started: it started touching another body.
---@param other Node?
function Crate:on_collision_started(other)
    if other == nil then return end
    self.bumps = self.bumps + 1
    print(self.node.name .. " bumped into " .. other.name)
end

return Crate
