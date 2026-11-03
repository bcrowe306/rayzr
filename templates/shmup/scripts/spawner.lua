-- A stage's enemies: Count of them come in from the right, one every
-- Interval seconds; every Shooter Every-th is a shooter (0: none). Spread 0
-- flies them all down the middle, 1 sweeps them up and down the screen (the
-- same pattern every game - use math.random for surprises). When every one
-- is gone - shot down or flown past - the stage is clear: Game goes on to
-- the next stage (the result screen after the last).

---@class Spawner : ScriptInstanceBase
local Spawner = {}

Spawner.properties = {
    stage         = { type = "int", default = 1, min = 1, label = "Stage" },           -- this scene's place in Game.LEVELS
    count         = { type = "int", default = 6, min = 1, label = "Enemies" },
    interval      = { type = "float", default = 0.8, label = "Interval" },             -- s between enemies
    shooter_every = { type = "int", default = 0, min = 0, label = "Shooter Every" },
    spread        = { type = "float", default = 1, min = 0, max = 1, label = "Spread" },
}

function Spawner:ready()
    self.timer = 1.5
    self.n = 0
    self.clear = nil
    self.shots = Scene.find_node("Shots")
    self.player = Scene.find_node("Player"):get_script()
    self.hud = Scene.find_node("HUD"):get_script()
end

---@param dt number
function Spawner:update(dt)
    if not self.player:alive() then return end
    if self.clear then
        self.clear = self.clear - dt
        if self.clear <= 0 then
            self.clear = 1e9
            Game:level_done(self.stage)
        end
        return
    end
    if self.n >= self.count then
        -- All out: clear once the last one is gone.
        if #Scene.find_by_tag("enemy") == 0 then
            self.clear = 1.5
            self.hud:message(self.stage < #Game.LEVELS and "Stage clear!" or "All clear!")
        end
        return
    end
    self.timer = self.timer - dt
    if self.timer > 0 then return end
    local w, h = Engine.get_virtual_size()
    self.n = self.n + 1
    local y = h / 2 + math.sin(self.n * 1.9) * (h / 2 - 28) * self.spread
    local shooter = self.shooter_every > 0 and self.n % self.shooter_every == 0
    Scene.instantiate("components/" .. (shooter and "shooter" or "drifter") .. ".component.json", self.shots, w + 16, y)
    self.timer = self.interval
end

return Spawner
