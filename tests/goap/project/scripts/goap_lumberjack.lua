-- The lumberjack (tests/goap): logs what its GOAP agent does.
---@class Jack : ScriptInstanceBase
local Jack = {}

function Jack:ready()
    self.log = Scene.find_node("Log")
    local agent = self.node:get_node("GOAP")
    agent:connect("action_started", function(name) self.log.text = self.log.text .. name .. " " end)
    agent:connect("goal_completed", function(name) self.log.text = self.log.text .. "done:" .. name end)
end

return Jack
