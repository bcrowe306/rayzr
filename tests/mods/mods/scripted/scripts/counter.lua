-- Replaces the game's counter: runs in the mod's sandbox.
local Counter = {}

function Counter:ready() self.frames = 0 end

function Counter:update(dt)
    self.frames = self.frames + 1
    self.node.text = "mod " .. self.frames .. (io == nil and " sandboxed" or " UNSAFE")
end

return Counter
