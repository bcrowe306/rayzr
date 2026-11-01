-- Jumps 10 px up per press; dash moves right while held; counts frames.
local Player = {}
function Player:ready() self.jumps = 0; self.frames = 0 end
function Player:update(dt)
    self.frames = self.frames + 1
    local x, y = self.node:get_position()
    if Input.is_action_pressed("jump") then
        self.jumps = self.jumps + 1
        y = y - 10
    end
    if Input.is_action_down("dash") then x = x + 2 end
    self.node:set_position(x, y)
end
return Player
