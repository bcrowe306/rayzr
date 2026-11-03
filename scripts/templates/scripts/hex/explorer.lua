-- The explorer: walks a path hex by hex, from centre to centre. go_to finds
-- the path in the Walk map (map:nav_find_path - on a hex map it steps to the
-- sides) and the explorer follows it, telling the island each hex it
-- reaches (each one a step).

---@class Explorer : ScriptInstanceBase
local Explorer = {}

Explorer.properties = {
    speed = { type = "float", default = 160, label = "Speed" }, -- px/s
}

function Explorer:ready()
    self.walk = Scene.find_node("Walk") ---@type TileMapNode
    self.island = Scene.find_node("Island"):get_script()
    self.path = nil
    self.sprite = self.node:get_child("Sprite")
end

function Explorer:cell()
    local x, y = self.node:get_position()
    return self.walk:tilemap_cell_at(x, y)
end

function Explorer:busy()
    return self.path ~= nil and #self.path > 0
end

-- stop: no more steps (the island is over).
function Explorer:stop()
    self.path = nil
end

function Explorer:go_to(cx, cy)
    local x, y = self.node:get_position()
    local tx, ty = self.walk:tilemap_cell_position(cx, cy)
    local path = self.walk:nav_find_path(x, y, tx, ty, { smooth = false })
    if not path then return end
    table.remove(path, 1) -- (where it stands)
    self.path = path
end

function Explorer:update(dt)
    if not self:busy() then return end
    local x, y = self.node:get_position()
    local p = self.path[1]
    local dx, dy = p[1] - x, p[2] - y
    local d = math.sqrt(dx * dx + dy * dy)
    local step = self.speed * dt
    if dx < -1 then self.sprite:set_scale(-1, 1) elseif dx > 1 then self.sprite:set_scale(1, 1) end
    if d <= step then
        self.node:set_position(p[1], p[2])
        table.remove(self.path, 1)
        self.island:arrived(self.walk:tilemap_cell_at(p[1], p[2])) -- (may stop the walk)
    else
        self.node:set_position(x + dx / d * step, y + dy / d * step)
    end
end

return Explorer
