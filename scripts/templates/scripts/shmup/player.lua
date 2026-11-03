-- The player's ship: flies around the screen, shoots (fire held: a shot
-- every Fire Rate seconds), loses a life when hit (then blinks for a moment).
-- The lives are the run's (Game.run: they carry on to the next stage); the
-- last one ends the game - the result screen. Input actions: move_*, fire
-- (Space / J).

---@class Player : ScriptInstanceBase
local Player = {}

Player.properties = {
    speed     = { type = "float", default = 110, label = "Speed" },          -- px/s
    fire_rate = { type = "float", default = 0.16, label = "Fire Rate" },     -- s between shots
    lives     = { type = "int", default = 3, label = "Lives" },              -- played on its own (F6): the lives it starts with
    radius    = { type = "float", default = 7, label = "Hit Radius" },       -- px
}

local BULLET = "components/player_bullet.component.json"
local EXPLOSION = "components/explosion.component.json"

function Player:ready()
    local stage = Scene.find_node("Spawner"):get_script().stage
    self.run = Game:ensure_run(stage, self.lives)
    self.lives = self.run.lives
    self.cooldown = 0
    self.safe = 1.0 -- invulnerable time left
    self.shots = Scene.find_node("Shots")
    self.hud = Scene.find_node("HUD"):get_script()
    self.sprite = self.node:get_child("Sprite")
    self.hud:set_lives(self.lives)
    self.hud:refresh()
    Pool.prewarm(BULLET, 24)
end

---@param dt number
function Player:update(dt)
    if self.lives <= 0 then
        -- Game over: a moment to see it, then the result screen.
        self.over = self.over - dt
        if self.over <= 0 then
            self.over = 1e9
            Game:lose_life()
        end
        return
    end
    local x, y = self.node:get_position()
    local mx, my = Input.get_vector()
    local w, h = Engine.get_virtual_size()
    x = math.max(12, math.min(w - 12, x + mx * self.speed * dt))
    y = math.max(16, math.min(h - 12, y + my * self.speed * dt))
    self.node:set_position(x, y)

    self.cooldown = self.cooldown - dt
    if Input.is_action_down("fire") and self.cooldown <= 0 then
        self.cooldown = self.fire_rate
        Pool.take(BULLET, self.shots, x + 12, y)
    end

    self.safe = math.max(0, self.safe - dt)
    self.sprite:set_visible(self.safe <= 0 or math.floor(self.safe * 12) % 2 == 0)
end

-- hit: an enemy or an enemy bullet touched us.
function Player:hit()
    if self.safe > 0 or self.lives <= 0 then return end
    self.lives = self.lives - 1
    if self.lives > 0 then self.run.lives = self.lives end -- (the last one: Game.lose_life, after the pause)
    self.hud:set_lives(self.lives)
    local x, y = self.node:get_position()
    Scene.instantiate(EXPLOSION, self.shots, x, y)
    Camera.shake(4, 0.3)
    if self.lives <= 0 then
        self.sprite:set_visible(false)
        self.hud:message("Game over")
        self.over = 1.5
    else
        self.safe = 1.5
    end
end

function Player:alive() return self.lives > 0 end

return Player
