-- The Game view's drive (game_view.drive): what the game read from the
-- keyboard and mouse the editor sent it, as script values the Game tab shows.

---@class GvInput : ScriptInstanceBase
local GvInput = {}

GvInput.properties = {
    right_presses = { type = "int", default = 0 },
    right_down = { type = "int", default = 0 },
    clicks = { type = "int", default = 0 },
    mouse_x = { type = "float", default = -1 },
    mouse_y = { type = "float", default = -1 },
}

function GvInput:update(dt)
    if Input.is_key_pressed("RIGHT") then self.right_presses = self.right_presses + 1 end
    self.right_down = Input.is_key_down("RIGHT") and 1 or 0
    if Input.is_mouse_button_pressed("LEFT") then
        self.clicks = self.clicks + 1
        self.mouse_x, self.mouse_y = Input.get_mouse_position()
    end
end

return GvInput
