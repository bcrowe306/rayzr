-- An island: a Hex (pointy) map. Click a hex and the explorer walks there
-- hex by hex (a path round the water, trees and rocks); D / A / E / Q / C /
-- Z take one step right, left, up-right, up-left, down-right, down-left.
-- Pick every flower.
--
-- Maps: Ground (land and water), Objects (trees, rocks, flowers; Y Sort,
-- so the explorer walks behind trees) and Walk - an invisible map of the
-- hexes that can be walked on, made here from the other two (paths are
-- found in it: on a hex map they step to the six neighbours).
--
-- The game (Game, scripts/game.lua): every hex walked into is a step, and
-- an island has a step limit. Every flower picked clears it - the next
-- island (saved as reached; the steps taken are its best if they're the
-- fewest yet), or the result screen after the last; out of steps with a
-- flower left is game over.

---@class Island : ScriptInstanceBase
local Island = {}

Island.properties = {
    island     = { type = "int", default = 1, min = 1, label = "Island" },          -- this scene's place in Game.LEVELS
    step_limit = { type = "int", default = 30, min = 1, label = "Step Limit" },     -- steps to pick every flower in
}

local WATER = 7                                   -- in textures/hex_tiles.png
local FLOWERS = { [8] = true, [9] = true, [10] = true } -- in textures/hex_objects.png (the rest block)

-- One step: the hex's six sides clockwise from the right (map:tilemap_neighbors' order).
local STEP_KEYS = { "step_e", "step_se", "step_sw", "step_w", "step_nw", "step_ne" }

function Island:ready()
    self.ground = Scene.find_node("Ground") ---@type TileMapNode
    self.objects = Scene.find_node("Objects") ---@type TileMapNode
    self.walk = Scene.find_node("Walk") ---@type TileMapNode
    self.unit = Scene.find_node("Explorer"):get_script()
    self.counter = Scene.find_node("Flowers")
    self.steps_text = Scene.find_node("Steps")
    self.message = Scene.find_node("Message")
    self.run = Game:ensure_run(self.island)
    self.picked, self.total, self.steps = 0, 0, 0
    self.done = false -- cleared (or out of steps): the island takes no more input
    for y = 0, 40 do
        for x = 0, 40 do
            local g, o = self.ground:tilemap_get_tile(x, y), self.objects:tilemap_get_tile(x, y)
            if FLOWERS[o] then self.total = self.total + 1 end
            local open = g >= 0 and g ~= WATER and (o < 0 or FLOWERS[o])
            self.walk:tilemap_set_tile(x, y, open and 0 or -1)
        end
    end
    Scene.find_node("IslandText").text = string.format("Island %d / %d", self.island, #Game.LEVELS)
    self:count()
end

function Island:count()
    self.counter.text = "Flowers " .. self.picked .. " / " .. self.total
    local left = self.step_limit - self.steps
    self.steps_text.text = "Steps " .. self.steps .. " / " .. self.step_limit
    self.steps_text:set_property("color", left <= 3 and "#ff6b5bff" or "#ffffffff")
end

-- walkable: a hex the explorer can stand on.
function Island:walkable(cx, cy)
    return self.walk:tilemap_get_tile(cx, cy) >= 0
end

-- arrived: the explorer stepped onto a hex - a step; a flower there is picked.
function Island:arrived(cx, cy)
    if self.done then return end
    self.steps = self.steps + 1
    if FLOWERS[self.objects:tilemap_get_tile(cx, cy)] then
        self.objects:tilemap_set_tile(cx, cy, -1)
        self.picked = self.picked + 1
    end
    self:count()
    if self.picked == self.total then
        local last = self.island >= #Game.LEVELS
        self:finish(last and "Every flower on every island!" or "Every flower picked!", 1.2, function()
            Game:add_score(self.steps)
            Game:level_done(self.island, self.steps)
        end)
    elseif self.steps >= self.step_limit then
        self:finish("Out of steps!", 1.5, function() Game:finish(false) end)
    end
end

-- finish: the island is over - the explorer stops; `after` runs `delay` seconds later.
function Island:finish(message, delay, after)
    self.done = true
    self.unit:stop()
    self.message.text = message
    self.after, self.after_time = after, delay
end

function Island:update(dt)
    if self.after then
        self.after_time = self.after_time - dt
        if self.after_time <= 0 then
            local after = self.after
            self.after = nil
            after()
        end
        return
    end
    -- The mouse: the hex under it; a click walks there.
    local wx, wy = Camera.screen_to_world(Input.get_mouse_position())
    self.cx, self.cy = self.walk:tilemap_cell_at(wx, wy)
    if self.done then return end
    if Input.is_mouse_button_pressed("LEFT") and self:walkable(self.cx, self.cy) then
        self.unit:go_to(self.cx, self.cy)
    end
    -- The keys: one step to a side.
    if not self.unit:busy() then
        local ux, uy = self.unit:cell()
        local sides = self.walk:tilemap_neighbors(ux, uy)
        for i, action in ipairs(STEP_KEYS) do
            if Input.is_action_pressed(action) and self:walkable(sides[i][1], sides[i][2]) then
                self.unit:go_to(sides[i][1], sides[i][2])
            end
        end
    end
end

-- on_draw: the hex under the mouse and the path still to walk - its steps
-- past the limit in red (this node is at 0, 0: its space is the world's).
function Island:on_draw()
    if self.cx and not self.done then
        local pts = self.walk:tilemap_cell_outline(self.cx, self.cy)
        Vector.begin_path()
        Vector.move_to(pts[1][1], pts[1][2])
        for i = 2, #pts do Vector.line_to(pts[i][1], pts[i][2]) end
        Vector.close_path()
        local ok = self:walkable(self.cx, self.cy)
        Vector.fill_color(ok and "#ffffff38" or "#ff404030")
        Vector.fill()
        Vector.stroke_color(ok and "#ffffffd0" or "#ff6060c0")
        Vector.stroke_width(2)
        Vector.stroke()
    end
    local left = self.step_limit - self.steps
    for i, p in ipairs(self.unit.path or {}) do
        Vector.begin_path()
        Vector.circle(p[1], p[2], 4)
        Vector.fill_color(i <= left and "#ffe066d0" or "#ff5040e0")
        Vector.fill()
    end
end

return Island
