-- A hazard: touching it is game over (stage.lua checks). Its box is Width x
-- Height round the node (a thorn bush: above its foot). A bee bobs up and
-- down by Bob px every Period seconds: walk under it when it's up.

---@class Hazard : ScriptInstanceBase
local Hazard = {}

Hazard.properties = {
    kind   = { type = "enum", values = { "thorns", "bee" }, default = "thorns", label = "Kind" },
    width  = { type = "float", default = 76, label = "Width" },
    height = { type = "float", default = 48, label = "Height" },
    bob    = { type = "float", default = 0, label = "Bob" },       -- px up and down (0: stays put)
    period = { type = "float", default = 3, label = "Period" },    -- seconds a bob
    phase  = { type = "float", default = 0, label = "Phase" },     -- 0..1: where in its bob it starts
}

function Hazard:ready()
    local p = self.node.position
    self.x, self.y = p.x, p.y
    self.time = self.phase * self.period
end

function Hazard:update(dt)
    if self.bob == 0 then return end
    self.time = self.time + dt
    local y = self.y + self.bob * math.sin(self.time / self.period * 2 * math.pi)
    self.node.position = Vec2(self.x, y)
end

-- box: left, top, right, bottom in the world.
function Hazard:box()
    local p = self.node.position
    if self.kind == "thorns" then
        return p.x - self.width / 2, p.y - self.height, p.x + self.width / 2, p.y
    end
    return p.x - self.width / 2, p.y - self.height / 2, p.x + self.width / 2, p.y + self.height / 2
end

return Hazard
