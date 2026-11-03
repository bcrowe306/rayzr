-- The player: moves with the arrow keys or WASD (the built-in move_left,
-- move_right, move_up and move_down actions: Project Settings > Input).

---@class Player : ScriptInstanceBase
local Player = {}

Player.properties = {
    --- How fast the player moves, in pixels per second.
    speed = { type = "float", default = 300, min = 0, max = 1000, label = "Speed" },
}

function Player:ready()
    print("Player ready at", self.node:get_position())
end

---@param dt number
function Player:update(dt)
    -- -1 to 1 on each axis: left/right and up/down.
    local x, y = Input.get_vector("move_left", "move_right", "move_up", "move_down")
    self.node:translate(x * self.speed * dt, y * self.speed * dt)

    -- Stay on the screen.
    local w, h = Engine.get_virtual_size()
    local px, py = self.node:get_position()
    self.node:set_position(math.max(32, math.min(w - 32, px)), math.max(32, math.min(h - 32, py)))
end

return Player
