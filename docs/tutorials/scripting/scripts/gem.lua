-- The gem: spins, hops to a new place when its HopTimer runs out, and is
-- caught when the player touches it or you click it. Catching it raises
-- the custom event "caught" (the score listens to it).

---@class Gem : ScriptInstanceBase
local Gem = {}

Gem.properties = {
    --- Points for catching it.
    points = { type = "int", default = 10, min = 1, max = 100, label = "Points" },
    --- How close the player (or a click) has to come, in pixels.
    reach = { type = "float", default = 48, min = 8, max = 200, label = "Reach" },
    --- How fast it spins, in degrees per second.
    spin = { type = "float", default = 90, label = "Spin" },
    --- The node that catches it by touching it.
    player = { type = "node", label = "Player" },
}

function Gem:ready()
    -- Without a Player set in the Inspector, look it up by name.
    if not self.player then self.player = Scene.find_node("Player") end
    self.timer = self.node:get_child("HopTimer") ---@type TimerNode
end

---@param dt number
function Gem:update(dt)
    self.node:rotate(self.spin * dt)

    -- Touched by the player?
    if self.player and self.player.position:distance(self.node.position) < self.reach then
        self:catch()
    end

    -- Clicked? (Mouse positions are on the screen: turn them into world ones.)
    if Input.is_mouse_button_pressed("LEFT") then
        local mx, my = Camera.screen_to_world(Input.get_mouse_position())
        if Vec2(mx, my):distance(self.node.position) < self.reach then
            self:catch()
        end
    end
end

function Gem:catch()
    print("Caught! +" .. self.points)
    self.node:emit("caught", self.points)
    self:hop()
end

-- Moves the gem somewhere else on the screen and restarts the countdown.
function Gem:hop()
    local w, h = Engine.get_virtual_size()
    -- A new place out of the player's reach (else it's caught again at once).
    local x, y
    for _ = 1, 20 do
        x, y = math.random(64, w - 64), math.random(64, h - 64)
        if not self.player or self.player.position:distance(Vec2(x, y)) > self.reach * 2 then break end
    end
    self.node:set_position(x, y)
    if self.timer then self.timer:timer_start() end
end

---Signal: HopTimer.timeout - The timer's duration elapsed
function Gem:on_hop_timer_timeout()
    self:hop()
end

return Gem
