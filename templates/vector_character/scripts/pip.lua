-- Pip: walks with A / D or the arrows, jumps with W / Space / Up, talks with
-- T, blinks now and then.
--
-- The art is one SVG cut into Vector Shapes (one per part) under a Skeleton
-- (Rig): each part bends with its bones, so playing the rig's animations
-- (idle, walk, talk, jump) moves the whole character. Turning round is the
-- rig's scale.x (-1 faces left). Talking plays the voice through the Lip
-- Sync node, which swaps the Mouth's frame to the cue under the voice's
-- playback time. Blinking swaps the Eyes' frame.

---@class Pip : ScriptInstanceBase
local Pip = {}

Pip.properties = {
    speed      = { type = "float", default = 220, label = "Walk Speed" }, -- px/s
    jump_speed = { type = "float", default = 950, label = "Jump Speed" }, -- px/s, up
    gravity    = { type = "float", default = 2200, label = "Gravity" },   -- px/s/s
    min_x      = { type = "float", default = 60, label = "Left Edge" },
    max_x      = { type = "float", default = 1220, label = "Right Edge" },
    voice      = { type = "string", default = "audio/pip_mumble.wav", label = "Voice" },
}

function Pip:ready()
    self.rig = self.node:get_node("Rig") ---@type SkeletonNode
    self.eyes = self.node:get_node("Rig/Eyes") ---@type VectorShapeNode
    self.lips = self.node:get_node("LipSync") ---@type LipSyncNode
    self.ground = self.node.position.y -- where his feet land
    self.vy = 0
    self.frozen = false   -- true while he stops to talk (the stage says)
    self.anim = "idle"
    self.next_blink = 1.5 -- seconds until the next blink
    self.blink_left = 0   -- seconds the eyes stay shut
end

-- play switches the rig's animation (crossfading over its Mix Time); calling
-- it every frame with the same name does nothing.
function Pip:play(name)
    if self.anim ~= name then
        self.anim = name
        self.rig:skeleton_play(name)
    end
end

function Pip:talk()
    self.lips:lipsync_play(self.voice)
end

-- in_air: off the ground (jumping).
function Pip:in_air()
    return self.node.position.y < self.ground
end

function Pip:update(dt)
    local p = self.node.position
    local dir = self.frozen and 0 or Input.get_axis("move_left", "move_right")
    local x, y = p.x, p.y
    if math.abs(dir) > 0.1 then
        x = math.max(self.min_x, math.min(self.max_x, x + dir * self.speed * dt))
        self.rig.scale = Vec2(dir < 0 and -1 or 1, 1)
    end
    -- Jumping: up at Jump Speed, pulled down by Gravity, landing on the ground.
    if not self.frozen and not self:in_air() and Input.is_action_pressed("jump") then self.vy = -self.jump_speed end
    if self.vy ~= 0 or y < self.ground then
        self.vy = self.vy + self.gravity * dt
        y = y + self.vy * dt
        if y >= self.ground then y, self.vy = self.ground, 0 end
    end
    self.node.position = Vec2(x, y)

    if y < self.ground then
        self:play("jump")
    elseif math.abs(dir) > 0.1 then
        self:play("walk")
    elseif self.lips:lipsync_is_playing() then
        self:play("talk")
    else
        self:play("idle")
    end

    if not self.frozen and Input.is_action_pressed("talk") then self:talk() end

    -- Blink: shut the eyes for a moment every few seconds.
    if self.blink_left > 0 then
        self.blink_left = self.blink_left - dt
        if self.blink_left <= 0 then self.eyes:vector_swap("open") end
    else
        self.next_blink = self.next_blink - dt
        if self.next_blink <= 0 then
            self.eyes:vector_swap("closed")
            self.blink_left = 0.12
            self.next_blink = 2 + math.random() * 3
        end
    end
end

return Pip
