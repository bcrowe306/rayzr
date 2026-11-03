-- A lift: a Kinematic Platform that goes up and down. It moves exactly as
-- told and carries the player standing on it.

---@class Lift : ScriptInstanceBase
local Lift = {}

Lift.properties = {
    --- Pixels per second.
    speed = { type = "float", default = 90, label = "Speed" },
    --- Seconds each way.
    period = { type = "float", default = 2, min = 0.1, label = "Period" },
}

function Lift:ready()
    self.time = 0
end

---@param dt number
function Lift:update(dt)
    self.time = self.time + dt
    local up = math.floor(self.time / self.period) % 2 == 0
    self.node:set_linear_velocity(0, up and -self.speed or self.speed)
end

return Lift
