local DriveDiagAZz = {}

function DriveDiagAZz:ready()
    self.count = DriveDiagMissingZz + 1
end

function DriveDiagAZz:update()
    self.jump = Input.is_action_pressed("drive_diag_jump_zz")
end

---@param b DriveDiagBZz
function DriveDiagAZz:poke(b)
    b:helper_zz()
end

return DriveDiagAZz
