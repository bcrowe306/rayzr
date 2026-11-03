-- The player: a Character Mover (Control Mode "Script") that runs with
-- A / D or the arrows and jumps with Space. It doesn't pick animations
-- itself: it tells the State Machine how fast it goes and whether it is on
-- the floor, and the machine's arrows choose idle, run or jump.

---@class Player : ScriptInstanceBase
local Player = {}

Player.properties = {
    --- Running speed, in pixels per second.
    speed = { type = "float", default = 90, min = 0, max = 400, label = "Speed" },
    --- Upward speed of a jump, in pixels per second.
    jump_speed = { type = "float", default = 280, min = 0, max = 1000, label = "Jump Speed" },
}

function Player:ready()
    self.sprite = self.node:get_node("Sprite") ---@type AnimationPlayerNode
    self.machine = self.node:get_node("StateMachine") ---@type StateMachineNode
    self.info = Scene.find_node("Info") ---@type TextNode
end

---@param dt number
function Player:update(dt)
    local node = self.node
    local vx, vy = node:character_get_velocity()
    local _, gy = node:character_get_gravity()
    vy = vy + gy * dt

    vx = Input.get_axis("move_left", "move_right") * self.speed
    if Input.is_action_pressed("jump") and node:character_is_on_floor() then
        vy = -self.jump_speed
    end
    node:character_set_velocity(vx, vy)
    node:character_move_and_slide()

    -- What the machine's conditions compare.
    self.machine:sm_set("speed", math.abs(vx))
    self.machine:sm_set("on_floor", node:character_is_on_floor())

    -- Face the way we run: a negative x scale mirrors the sprite.
    if vx ~= 0 then self.sprite:set_scale(vx < 0 and -1 or 1, 1) end

    self.info.text = "State: " .. self.machine:sm_state()
end

return Player
