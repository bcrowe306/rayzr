-- The game: click the gem (or press Space) to mine gems, spend them on a
-- better pick. Everything worth keeping is in Game.data - the table from
-- Save.get - so it is saved when the game quits; an autosave writes it
-- every few seconds too, and Menu writes it before going back.

---@class Clicker : ScriptInstanceBase
local Clicker = {}

Clicker.properties = {
    --- Seconds between autosaves.
    autosave_every = { type = "float", default = 10, min = 1, max = 300, label = "Autosave Every" },
}

function Clicker:ready()
    -- Played straight from the editor (F6), no slot was picked: the last one.
    if Game.data == nil then Game:continue_game(Game.slot) end
    if Game.data == nil then Game:new_game(Game.slot) end
    self.data = Game.data

    self.gem = Scene.find_node("Gem")
    self.gems = self.node:get_node("Gems") ---@type UILabelNode
    self.level = self.node:get_node("Level") ---@type UILabelNode
    self.upgrade = self.node:get_node("Upgrade") ---@type UIButtonNode
    self.status = self.node:get_node("Status") ---@type UILabelNode
    self.upgrade:connect("clicked", function() self:buy_upgrade() end)
    self.node:get_node("TopRight/Menu"):connect("clicked", function()
        Save.flush()
        Game.data = nil
        Scene.change_scene("scenes/title.scene.json")
    end)
    self.since_save = 0
    self:refresh()
end

---@param dt number
function Clicker:update(dt)
    local data = self.data
    data.play_time = data.play_time + dt

    -- A click on the gem, or Space, mines it.
    local mined = Input.is_key_pressed("SPACE")
    if Input.is_mouse_button_pressed("LEFT") then
        local mx, my = Camera.screen_to_world(Input.get_mouse_position())
        if Vec2(mx, my):distance(self.gem.position) < 64 then mined = true end
    end
    if mined then self:mine() end

    -- Autosave: a crash, or a closed browser tab, loses a few seconds at most.
    self.since_save = self.since_save + dt
    if self.since_save >= self.autosave_every then
        self.since_save = 0
        Save.flush()
        self.status:set_text("Saved")
    end
end

function Clicker:mine()
    local data = self.data
    data.gems = data.gems + data.level
    data.total = data.total + data.level
    -- Something to unlock: a trophy at 100 gems mined.
    if data.total >= 100 and not data.unlocked.hundred then
        data.unlocked.hundred = true
        self.status:set_text("Trophy: 100 gems mined!")
    end
    self:refresh()
end

function Clicker:buy_upgrade()
    local data = self.data
    local cost = 10 * data.level
    if data.gems < cost then
        self.status:set_text("Not enough gems")
        return
    end
    data.gems = data.gems - cost
    data.level = data.level + 1
    self:refresh()
end

function Clicker:refresh()
    local data = self.data
    self.gems:set_text("Gems: " .. data.gems)
    self.level:set_text("Pick level " .. data.level .. " (+" .. data.level .. " a click)")
    self.upgrade:set_text("Upgrade: " .. 10 * data.level .. " gems")
end

return Clicker
