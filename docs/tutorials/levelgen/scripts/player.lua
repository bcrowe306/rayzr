-- The player: a Character Mover (Control Mode "Script") that walks in eight
-- directions with WASD or the arrows. The level script puts it on the
-- cave's start point each time a cave is made.

---@class Player : ScriptInstanceBase
local Player = {}

Player.properties = {
    --- Walking speed, in pixels per second.
    speed = { type = "float", default = 110, min = 0, max = 400, label = "Speed" },
}

function Player:ready()
    self.sprite = self.node:get_child("Sprite")
end

---@param dt number
function Player:update(dt)
    local x, y = Input.get_vector("move_left", "move_right", "move_up", "move_down")
    self.node:character_set_velocity(x * self.speed, y * self.speed)
    self.node:character_move_and_slide()
    if x ~= 0 then self.sprite:set_scale(x < 0 and -1 or 1, 1) end
end

return Player
