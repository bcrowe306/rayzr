-- The cell under the mouse, outlined, and the hero's path as dots; a
-- click there walks (Dungeon:clicked). It draws in the world (the node is
-- at 0, 0), over the floor and under the walls.

---@class Cursor : ScriptInstanceBase
local Cursor = {}

function Cursor:ready()
    self.walk = Scene.find_node("Walk") ---@type TileMapNode
    self.agent = Scene.find_node("Agent") ---@type NavigationAgentNode
    self.dungeon = Scene.find_node("Dungeon"):get_script()
end

function Cursor:update(dt)
    local wx, wy = Camera.screen_to_world(Input.get_mouse_position())
    self.cx, self.cy = self.walk:tilemap_cell_at(wx, wy)
    if Input.is_mouse_button_pressed("LEFT") then self.dungeon:clicked(self.cx, self.cy) end
end

function Cursor:on_draw()
    -- (The editor draws it too, before ready() has run: nothing to show yet.)
    if not self.agent then return end
    if self.cx then
        local pts = self.walk:tilemap_cell_outline(self.cx, self.cy)
        local open = self.walk:tilemap_get_tile(self.cx, self.cy) >= 0 or self.dungeon:what_at(self.cx, self.cy)
        Vector.begin_path()
        Vector.move_to(pts[1][1], pts[1][2])
        for i = 2, #pts do Vector.line_to(pts[i][1], pts[i][2]) end
        Vector.close_path()
        Vector.fill_color(open and "#ffffff30" or "#ff404030")
        Vector.fill()
        Vector.stroke_color(open and "#ffffffb0" or "#ff6060b0")
        Vector.stroke_width(2)
        Vector.stroke()
    end
    -- The path still to walk.
    local path = self.agent:nav_get_path()
    if path then
        Vector.fill_color("#ffd54aa0")
        for _, p in ipairs(path) do
            Vector.begin_path()
            Vector.circle(p[1], p[2], 5)
            Vector.fill()
        end
    end
end

return Cursor
