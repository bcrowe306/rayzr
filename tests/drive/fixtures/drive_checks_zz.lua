---@class DriveChecksZz : ScriptInstanceBase
local DriveChecksZz = {}

function DriveChecksZz:ready()
    local parent = self.node:get_parent()
    self.name = parent:get_name()
end

return DriveChecksZz
