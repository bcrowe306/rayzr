-- A Behavior Tree leaf (tests/behavior_tree): writes its message to the Log.
---@class Shout
local Shout = {}
Shout.behavior = "action"
Shout.properties = {
    message = { type = "string", default = "hi" },
}

function Shout:tick(actor, blackboard, dt)
    local log = Scene.find_node("Log")
    log.text = log.text .. self.message .. ":" .. actor:get_name() .. " "
    blackboard:set("shouted", (blackboard:get("shouted", 0)) + 1)
    return "success"
end

return Shout
