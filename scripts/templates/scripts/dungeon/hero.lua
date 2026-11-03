-- The hero: a Character Mover with a Navigation Agent under it. Click a
-- cell: the agent walks there round the walls. WASD / arrows / a gamepad
-- walk along the grid's axes (W: up-right, D: down-right, S: down-left,
-- A: up-left - two at once go straight up, right, down or left). The
-- sprite faces where it goes (8 directions) and runs while moving. A hole
-- in the floor: he falls in (fall; the dungeon decides what happens).

---@class Hero : ScriptInstanceBase
local Hero = {}

Hero.properties = {
    speed = { type = "float", default = 150, label = "Speed" }, -- px/s on the keys
}

-- Facing rows in textures/hero.png, from east clockwise in 45 degree steps.
local ROW_OF_ANGLE = { 1, 2, 3, 4, 5, 6, 7, 0 } -- E SE S SW W NW N NE

function Hero:ready()
    self.agent = self.node:get_child("Agent") ---@type NavigationAgentNode
    self.sprite = self.node:get_child("Sprite") ---@type AnimationPlayerNode
    self.walk = Scene.find_node("Walk") ---@type TileMapNode
    self.facing = 2 -- (south-east)
    self.moving = false
end

-- cell: the cell the hero stands in.
function Hero:cell()
    local x, y = self.node:get_global_position()
    return self.walk:tilemap_cell_at(x, y)
end

-- walk_to: path to a cell's centre; `arrived` is called there.
function Hero:walk_to(cx, cy, arrived)
    local x, y = self.walk:tilemap_cell_position(cx, cy)
    self.agent:nav_set_target(x, y)
    self.arrived = arrived
    self.pathing = true
end

-- stop: stands still (out of time, out of the room).
function Hero:stop()
    self.stopped = true
    self.agent:nav_stop()
    self.pathing, self.arrived = false, nil
    self.sprite:animation_play("idle_" .. self.facing)
end

-- fall: into a hole - he sinks and shrinks out of sight.
function Hero:fall()
    self:stop()
    self.falling = 0
end

function Hero:update(dt)
    if self.falling then
        self.falling = math.min(1, self.falling + dt * 1.5)
        local k = 1 - self.falling
        self.sprite:set_scale(k, k)
        self.sprite:set_position(0, 24 * self.falling)
        return
    end
    if self.stopped then return end
    -- The keys: along the diamond grid's axes.
    local ix = (Input.is_action_down("move_right") and 1 or 0) - (Input.is_action_down("move_left") and 1 or 0)
    local iy = (Input.is_action_down("move_down") and 1 or 0) - (Input.is_action_down("move_up") and 1 or 0)
    local vx, vy = 0, 0
    if ix ~= 0 or iy ~= 0 then
        if self.pathing then
            self.agent:nav_stop()
            self.pathing, self.arrived = false, nil
        end
        -- Grid x is down-right (2:1), grid y down-left.
        local gx, gy = ix, iy
        vx, vy = (gx - gy), (gx + gy) * 0.5
        local len = math.sqrt(vx * vx + vy * vy)
        vx, vy = vx / len * self.speed, vy / len * self.speed
        self.node:character_set_velocity(vx, vy)
        self.node:character_move_and_slide()
    elseif self.pathing then
        local v = self.node.velocity -- (the agent moves the hero)
        vx, vy = v.x, v.y
        if self.agent:nav_is_finished() then
            self.pathing = false
            local done = self.arrived
            self.arrived = nil
            if done then done() end
        end
    end
    -- Face and run where it goes.
    local moving = vx * vx + vy * vy > 4
    if moving then
        local a = math.atan(vy, vx)
        self.facing = ROW_OF_ANGLE[(math.floor(a / (math.pi / 4) + 0.5) % 8) + 1]
    end
    local anim = (moving and "run_" or "idle_") .. self.facing
    if anim ~= self.anim then
        self.anim = anim
        self.sprite:animation_play(anim)
    end
end

return Hero
