-- The player: a Character Mover (Control Mode "Script") that runs with
-- A / D or the arrows and jumps with Space. It has health: spikes call
-- hurt(), which tells the HUD with the "health_changed" event.

---@class Player : ScriptInstanceBase
local Player = {}

Player.properties = {
    --- Running speed, in pixels per second.
    speed = { type = "float", default = 100, min = 0, max = 400, label = "Speed" },
    --- Upward speed of a jump, in pixels per second.
    jump_speed = { type = "float", default = 290, min = 0, max = 1000, label = "Jump Speed" },
    --- Health at the start.
    max_health = { type = "int", default = 100, min = 1, max = 1000, label = "Max Health" },
}

function Player:ready()
    self.sprite = self.node:get_node("Sprite") ---@type AnimationPlayerNode
    self.health = self.max_health
    self.safe = 0 -- seconds left without damage after a hit
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

    if not node:character_is_on_floor() then self.sprite:animation_play("jump")
    elseif vx ~= 0 then self.sprite:animation_play("run")
    else self.sprite:animation_play("idle") end
    if vx ~= 0 then self.sprite:set_scale(vx < 0 and -1 or 1, 1) end

    -- Blink while safe after a hit.
    if self.safe > 0 then
        self.safe = self.safe - dt
        self.sprite:set_visible(self.safe <= 0 or math.floor(self.safe * 10) % 2 == 0)
    end
end

-- hurt: lose health (spikes.lua calls it), bounce up, restart at 0.
---@param amount number
function Player:hurt(amount)
    if self.safe > 0 then return end
    self.health = math.max(0, self.health - amount)
    self.safe = 1
    Events.emit("health_changed", self.health)
    local vx = self.node:character_get_velocity()
    self.node:character_set_velocity(vx, -220)
    if self.health == 0 then Scene.reload() end
end

return Player
