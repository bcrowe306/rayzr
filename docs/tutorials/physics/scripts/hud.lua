-- The HUD: counts coins (the "coin_collected" event), shows how high the
-- player is above the ground (its GroundRay) and toggles the collision
-- shapes with F3.

---@class Hud : ScriptInstanceBase
local Hud = {}

function Hud:ready()
    self.coins = 0
    self.total = #Scene.find_by_tag("coin")
    self.ray = Scene.find_node("GroundRay") ---@type RaycastNode
    self.height = self.node:get_child("Height")
    self.count = self.node:get_child("Coins")
    Events.connect("coin_collected", function(value)
        self.coins = self.coins + value
        self:refresh()
    end)
    self:refresh()
end

function Hud:refresh()
    self.count.text = string.format("Coins: %d / %d", self.coins, self.total)
end

---@param dt number
function Hud:update(dt)
    if self.ray and self.ray:raycast_is_colliding() then
        local _, hy = self.ray:raycast_get_hit_point()
        local _, ry = self.ray:get_global_position()
        self.height.text = string.format("Above ground: %d px", math.floor(hy - ry))
    end
    if Input.is_key_pressed("F3") then
        Physics.set_debug_draw(not Physics.is_debug_draw())
    end
end

return Hud
