-- Counts frames (tests/mods): the "scripted" mod replaces this file.
---@class Counter
local Counter = {}

function Counter:ready() self.frames = 0 end

function Counter:update(dt)
    self.frames = self.frames + 1
    self.node.text = "game " .. self.frames
end

return Counter
