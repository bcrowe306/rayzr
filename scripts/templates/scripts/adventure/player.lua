-- The player: platformer movement for a CharacterMover (Control Mode
-- "Script"), the sprite's animations, dying and finishing the level.
--
-- Movement is the engine's platformer template (Inspector: Add Script >
-- Character > Platformer): run with acceleration, jump with coyote time,
-- jump buffering and a shorter jump when the button is let go early.
-- Input actions (Project Settings > Input): move_left, move_right, jump.

---@class Player : ScriptInstanceBase
local Player = {}

Player.properties = {
    speed         = { type = "float", default = 110, label = "Run Speed" },      -- px/s
    acceleration  = { type = "float", default = 900, label = "Acceleration" },   -- px/s^2
    friction      = { type = "float", default = 1200, label = "Friction" },      -- px/s^2 without input
    air_control   = { type = "float", default = 0.7, label = "Air Control" },
    jump_velocity = { type = "float", default = 290, label = "Jump Velocity" },  -- px/s up
    jump_cut      = { type = "float", default = 0.45, label = "Jump Cut" },      -- let go early: keep this much
    coyote_time   = { type = "float", default = 0.1, label = "Coyote Time" },    -- s after leaving a ledge
    jump_buffer   = { type = "float", default = 0.1, label = "Jump Buffer" },    -- s before landing
    bounce        = { type = "float", default = 220, label = "Stomp Bounce" },   -- px/s up after a stomp
    fall_limit    = { type = "float", default = 400, label = "Fall Limit" },     -- y below which you fall out
}

local function move_toward(v, target, delta)
    if v < target then return math.min(v + delta, target) end
    return math.max(v - delta, target)
end

function Player:ready()
    self.sprite = self.node:get_child("Sprite")
    self.coyote, self.buffered = 0, 0
    self.facing = 1
    self.state = "playing" -- "dead", "won"
    self.timer = 0
end

-- play: the sprite's animation (only when it changes - play restarts it).
function Player:play(name)
    if self.sprite:animation_get_current() ~= name then self.sprite:animation_play(name) end
end

---@param dt number
function Player:update(dt)
    local node = self.node
    if self.state ~= "playing" then
        -- Dead or done: wait, then restart / go on (goal.lua decides where).
        self.timer = self.timer - dt
        local vx, vy = node:character_get_velocity()
        local _, gy = node:character_get_gravity()
        if self.state == "dead" then node:translate(0, vy * dt); node:character_set_velocity(0, vy + gy * dt) end
        if self.timer <= 0 then
            if self.state == "dead" then Scene.reload() else self.on_done() end
            self.timer = 1e9
        end
        return
    end

    local vx, vy = node:character_get_velocity()
    local on_floor = node:character_is_on_floor()
    local _, gy = node:character_get_gravity()
    vy = math.min(vy + gy * dt, 500)

    if on_floor then self.coyote = self.coyote_time else self.coyote = self.coyote - dt end
    if Input.is_action_pressed("jump") then self.buffered = self.jump_buffer else self.buffered = self.buffered - dt end
    if self.buffered > 0 and self.coyote > 0 then
        vy = -self.jump_velocity
        self.coyote, self.buffered = 0, 0
    end
    if Input.is_action_released("jump") and vy < 0 then vy = vy * self.jump_cut end

    local dir = Input.get_axis("move_left", "move_right")
    local control = on_floor and 1 or self.air_control
    if dir ~= 0 then
        vx = move_toward(vx, dir * self.speed, self.acceleration * control * dt)
        self.facing = dir > 0 and 1 or -1
    else
        vx = move_toward(vx, 0, self.friction * control * dt)
    end
    node:character_set_velocity(vx, vy)
    node:character_move_and_slide()
    if node:character_is_on_ceiling() then
        local cvx, cvy = node:character_get_velocity()
        if cvy < 0 then node:character_set_velocity(cvx, 0) end
    end

    -- Animation: in the air, running, standing; face the way we go.
    if not node:character_is_on_floor() then self:play("jump")
    elseif math.abs(vx) > 10 then self:play("run")
    else self:play("idle") end
    local sx, sy = self.sprite:get_scale()
    self.sprite:set_scale(self.facing * math.abs(sx), sy)

    local _, y = node:get_position()
    if y > self.fall_limit then self:die() end
end

-- die: spikes, an enemy, a fall. The scene restarts a moment later.
function Player:die()
    if self.state ~= "playing" then return end
    self.state, self.timer = "dead", 1.0
    self:play("jump")
    self.node:character_set_velocity(0, -180)
    Crash.note("player died")
    Scene.find_node("HUD"):get_script():message("Ouch!")
end

-- stomped: an enemy was jumped on - bounce off it.
function Player:stomped()
    local vx = self.node:character_get_velocity()
    self.node:character_set_velocity(vx, -self.bounce)
end

-- falling: moving down (an enemy hit from above is stomped, else it hurts).
function Player:falling()
    local _, vy = self.node:character_get_velocity()
    return vy > 0
end

-- win: reached the door. on_done runs after a short pause.
function Player:win(on_done)
    if self.state ~= "playing" then return end
    self.state, self.timer, self.on_done = "won", 1.5, on_done
    self.node:character_set_velocity(0, 0)
    self:play("idle")
end

return Player
