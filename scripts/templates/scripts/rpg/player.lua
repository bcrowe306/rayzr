-- The hero: moves in eight directions (a CharacterMover in "Script" mode,
-- no gravity: project.json's gravity is 0), swings a sword, talks to /
-- opens what's nearby, takes damage with a short knockback. Its hearts are
-- its life: losing the last one is game over (Game.finish).
-- Input actions: move_*, attack (Space / J), interact (E / K).

---@class Player : ScriptInstanceBase
local Player = {}

Player.properties = {
    speed      = { type = "float", default = 70, label = "Speed" },        -- px/s
    max_hp     = { type = "int", default = 3, label = "Hearts" },
    reach      = { type = "float", default = 20, label = "Interact Reach" }, -- px
    sword_time = { type = "float", default = 0.18, label = "Swing Time" },  -- s
}

function Player:ready()
    self.hp = self.max_hp
    self.facing = Vec2(1, 0)
    self.swing = 0        -- swing time left
    self.hurt_time = 0    -- invulnerable time left
    self.knock = Vec2(0, 0)
    self.has_key = false
    self.dead = false
    self.sprite = self.node:get_child("Sprite")
    self.sword = self.node:get_child("Sword")
    self.sword:set_visible(false)
    self.dialogue = Scene.find_node("Dialogue")
    self.hud = Scene.find_node("HUD"):get_script()
    self.hud:set_hearts(self.hp, self.max_hp)
end

-- nearest: the closest "interactable" in reach (or nil).
function Player:nearest()
    local x, y = self.node:get_position()
    local best, best_d = nil, self.reach
    for _, n in ipairs(Scene.find_by_tag("interactable")) do
        local nx, ny = n:get_position()
        local d = Vec2(nx - x, ny - y):length()
        local s = n:get_script()
        if d < best_d and s and (not s.can_interact or s:can_interact(self)) then best, best_d = n, d end
    end
    return best
end

---@param dt number
function Player:update(dt)
    local node = self.node
    if self.dead or self.frozen then
        node:character_set_velocity(0, 0)
        if not self.dead then return end
        self.timer = self.timer - dt
        if self.timer <= 0 then Game:finish(false); self.timer = 1e9 end
        return
    end
    self.hurt_time = math.max(0, self.hurt_time - dt)
    -- Blink while invulnerable.
    self.sprite:set_visible(self.hurt_time <= 0 or math.floor(self.hurt_time * 12) % 2 == 0)

    local talking = self.dialogue:dialogue_is_open()
    local x, y = 0, 0
    if not talking then x, y = Input.get_vector() end
    if x ~= 0 or y ~= 0 then self.facing = Vec2(x, y):normalized() end
    local v = Vec2(x, y) * self.speed + self.knock
    self.knock = self.knock * math.max(0, 1 - 10 * dt)
    node:character_set_velocity(v.x, v.y)
    node:character_move_and_slide()
    if self.facing.x ~= 0 then
        local sx, sy = self.sprite:get_scale()
        self.sprite:set_scale(self.facing.x < 0 and -math.abs(sx) or math.abs(sx), sy)
    end

    -- Talk / open: the nearest interactable (the HUD shows what E does).
    local near = not talking and self:nearest() or nil
    self.hud:hint(near and ("E: " .. near:get_script():hint(self)) or "")
    if near and Input.is_action_pressed("interact") then near:get_script():interact(self) end

    -- Sword: a short swing in front; slimes in reach get hit.
    if not talking and self.swing <= 0 and Input.is_action_pressed("attack") then
        self.swing = self.sword_time
        local tip = self.facing * 12
        self.sword:set_position(tip.x, tip.y - 2)
        self.sword:set_rotation(math.deg(math.atan(self.facing.y, self.facing.x)) + 45)
        self.sword:set_visible(true)
        local px, py = node:get_position()
        for _, e in ipairs(Scene.find_by_tag("enemy")) do
            local ex, ey = e:get_position()
            if Vec2(ex - (px + tip.x), ey - (py + tip.y)):length() < 14 then e:get_script():hit(self.facing) end
        end
    end
    if self.swing > 0 then
        self.swing = self.swing - dt
        if self.swing <= 0 then self.sword:set_visible(false) end
    end
end

-- freeze: stops (at the stairs).
function Player:freeze()
    self.frozen = true
    self.hud:hint("")
end

-- hurt: a slime touched us (from: where it was). Knocked back, a heart less.
function Player:hurt(fx, fy)
    if self.hurt_time > 0 or self.dead or self.frozen then return end
    self.hp = self.hp - 1
    self.hud:set_hearts(self.hp, self.max_hp)
    local x, y = self.node:get_position()
    local away = Vec2(x - fx, y - fy)
    if away:length() > 0 then self.knock = away:normalized() * 160 end
    self.hurt_time = 1.0
    if self.hp <= 0 then
        self.dead, self.timer = true, 1.2
        self.hud:message("You were defeated...")
    end
end

-- heal: a potion.
function Player:heal(n)
    self.hp = math.min(self.max_hp, self.hp + n)
    self.hud:set_hearts(self.hp, self.max_hp)
end

function Player:give_key()
    self.has_key = true
    self.hud:set_key(true)
end

return Player
