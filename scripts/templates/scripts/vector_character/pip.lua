-- Pip: walks with A / D or the arrows, talks with T, blinks now and then.
--
-- The art is one SVG cut into Vector Shapes (one per part) under a Skeleton
-- (Rig): each part bends with its bones, so playing the rig's animations
-- (idle, walk, talk) moves the whole character. Turning round is the rig's
-- scale.x (-1 faces left). Talking plays the voice through the Lip Sync
-- node, which swaps the Mouth's frame to the cue under the voice's playback
-- time. Blinking swaps the Eyes' frame.

---@class Pip : ScriptInstanceBase
local Pip = {}

Pip.properties = {
    speed = { type = "float", default = 150, label = "Walk Speed" }, -- px/s
    min_x = { type = "float", default = 120, label = "Left Edge" },
    max_x = { type = "float", default = 1160, label = "Right Edge" },
    voice = { type = "string", default = "audio/pip_mumble.wav", label = "Voice" },
}

function Pip:ready()
    self.rig = self.node:get_node("Rig") ---@type SkeletonNode
    self.eyes = self.node:get_node("Rig/Eyes") ---@type VectorShapeNode
    self.lips = self.node:get_node("LipSync") ---@type LipSyncNode
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

function Pip:update(dt)
    local dir = Input.get_axis("move_left", "move_right")
    if math.abs(dir) > 0.1 then
        local p = self.node.position
        local x = math.max(self.min_x, math.min(self.max_x, p.x + dir * self.speed * dt))
        self.node.position = Vec2(x, p.y)
        self.rig.scale = Vec2(dir < 0 and -1 or 1, 1)
        self:play("walk")
    elseif self.lips:lipsync_is_playing() then
        self:play("talk")
    else
        self:play("idle")
    end

    if Input.is_action_pressed("talk") then self:talk() end

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
