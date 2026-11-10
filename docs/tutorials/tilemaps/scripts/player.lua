-- The player: a Character Mover (Control Mode "Script") that walks in eight
-- directions with WASD or the arrows. It reads the Path map under its feet
-- (faster on the stone walkway) and opens the door in the Walls map with E.

---@class Player : ScriptInstanceBase
---@field path_map TileMapNode
---@field walls TileMapNode
local Player = {}

-- The door's tile in textures/dungeon.png (tiles count left to right, then
-- top to bottom, from 0).
local DOOR = 45

Player.properties = {
    --- Walking speed on the dirt, in pixels per second.
    speed = { type = "float", default = 60, min = 0, max = 300, label = "Speed" },
    --- Walking speed on the stone path.
    path_speed = { type = "float", default = 100, min = 0, max = 300, label = "Path Speed" },
    --- The Tile Map with the stone path.
    path_map = { type = "node", label = "Path Map" },
    --- The Tile Map with the walls and the door (Solid on).
    walls = { type = "node", label = "Walls Map" },
}

function Player:ready()
    self.path_map = self.path_map or Scene.find_node("Path")
    self.walls = self.walls or Scene.find_node("Walls")
    self.hint = Scene.find_node("Hint") ---@type TextNode
    self.sprite = self.node:get_child("Sprite")
end

---@param dt number
function Player:update(dt)
    local node = self.node
    -- The cell under the player's feet (the same grid in every map here).
    local cx, cy = self.path_map:tilemap_cell_at(node:get_global_position())
    local on_path = self.path_map:tilemap_get_tile(cx, cy) ~= -1

    local x, y = Input.get_vector("move_left", "move_right", "move_up", "move_down")
    local speed = on_path and self.path_speed or self.speed
    node:character_set_velocity(x * speed, y * speed)
    node:character_move_and_slide()
    if x ~= 0 then self.sprite:set_scale(x < 0 and -1 or 1, 1) end

    -- The door: the tile right of the player in the Walls map.
    if self.walls:tilemap_get_tile(cx + 1, cy) == DOOR then
        self.hint.text = "E: open the door"
        if Input.is_action_pressed("interact") then
            -- Erasing the tile also removes its collider (at the end of the frame).
            self.walls:tilemap_set_tile(cx + 1, cy, -1)
            self.hint.text = "The door is open"
        end
    elseif self.hint.text == "E: open the door" then
        self.hint.text = ""
    end
end

return Player
