-- Moves its node right at `speed` px/s (the camera in the pixel render tests).
local Pan = {}
Pan.properties = {
    speed = { type = "float", default = 7 },
}
function Pan:update(dt)
    local x, y = self.node:get_position()
    self.node:set_position(x + self.speed * dt, y)
end
return Pan
