-- The player: a Character Mover (Control Mode "Script") that runs with
-- A / D or the arrows and jumps with Space (the built-in move_left,
-- move_right and jump actions).

---@class Player : ScriptInstanceBase
local Player = {}

Player.properties = {
    --- Running speed, in pixels per second.
    speed = { type = "float", default = 260, min = 0, max = 1000, label = "Speed" },
    --- Upward speed of a jump, in pixels per second.
    jump_speed = { type = "float", default = 560, min = 0, max = 2000, label = "Jump Speed" },
}

---@param dt number
function Player:update(dt)
    local node = self.node
    local vx, vy = node:character_get_velocity()
    -- Gravity: the project's (Project Settings > Physics) x this node's Gravity Scale.
    local _, gy = node:character_get_gravity()
    vy = vy + gy * dt

    vx = Input.get_axis("move_left", "move_right") * self.speed
    if Input.is_action_pressed("jump") and node:character_is_on_floor() then
        vy = -self.jump_speed
    end

    node:character_set_velocity(vx, vy)
    node:character_move_and_slide()
end

return Player
