-- The title screen: pick a save slot, then Continue it, start a New Game in
-- it or Delete it. Settings opens the settings screen; Quit closes the game.

---@class Title : ScriptInstanceBase
local Title = {}

function Title:ready()
    local menu = self.node
    self.slot_button = menu:get_node("Slot") ---@type UIButtonNode
    self.summary = menu:get_node("Summary") ---@type UILabelNode
    self.continue = menu:get_node("Continue") ---@type UIButtonNode
    self.new_game = menu:get_node("NewGame") ---@type UIButtonNode
    self.delete = menu:get_node("Delete") ---@type UIButtonNode

    -- The slot button goes 1, 2, 3, 1...
    self.slot_button:connect("clicked", function() self:show(Game.slot % Game.SLOTS + 1) end)
    self.continue:connect("clicked", function()
        Game:continue_game(Game.slot)
        self:play()
    end)
    self.new_game:connect("clicked", function()
        Game:new_game(Game.slot)
        self:play()
    end)
    self.delete:connect("clicked", function() self:delete_slot() end)
    menu:get_node("Settings"):connect("clicked", function()
        Scene.change_scene("scenes/settings.scene.json")
    end)
    menu:get_node("Quit"):connect("clicked", function() Engine.quit() end)
    self:show(Game.slot)
end

-- Shows slot n: what's saved in it, and Continue / Delete only when there is something.
---@param n integer
function Title:show(n)
    local data = Game:open_slot(n)
    self.confirm = false
    self.slot_button:set_text("Slot " .. n)
    self.delete:set_text("Delete")
    if data then
        self.summary:set_text(string.format("Slot %d: %d gems, pick level %d", n, data.gems, data.level))
    else
        self.summary:set_text(string.format("Slot %d: empty", n))
    end
    self.continue:set_enabled(data ~= nil)
    self.delete:set_enabled(data ~= nil)
    if data then self.continue:ui_focus() else self.new_game:ui_focus() end
end

-- Delete asks first: the first click only changes its text.
function Title:delete_slot()
    if not self.confirm then
        self.confirm = true
        self.delete:set_text("Really delete?")
        return
    end
    Game:delete_slot(Game.slot)
    self:show(Game.slot)
end

function Title:play()
    Scene.change_scene("scenes/main.scene.json", { transition = "fade", duration = 0.3 })
end

return Title
