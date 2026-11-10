-- A menu made of Text nodes: this node's children tagged "item" are the
-- choices, top to bottom; each one's name says what it does. Up / down picks
-- (keys, D-pad, stick), Confirm (Enter, Space, A) chooses, left / right
-- change a value (the Volume, the start Level), Cancel (Esc) goes back. A
-- click or a tap on a choice picks and chooses it (a value steps on).
--
-- Kind: "title" (Play, Level, Settings, Quit), "settings" (Volume, Back),
-- "pause" (Resume, Restart, Title - the pause action opens and closes it; it
-- runs while the game is paused: Pause Mode Always) or "result" (Again,
-- Title: after a win or a game over).

---@class Menu : ScriptInstanceBase
local Menu = {}

Menu.properties = {
    kind        = { type = "enum", values = { "title", "settings", "pause", "result" }, default = "title", label = "Kind" },
    item_width  = { type = "float", default = 140, label = "Item Width" },  -- the clickable size of a choice
    item_height = { type = "float", default = 16, label = "Item Height" },
    selected    = { type = "color", default = "#c0392bff", label = "Selected Color" },
}

local TITLE = "scenes/title.scene.json"

function Menu:ready()
    self.items = {}
    for _, child in ipairs(self.node:get_children()) do
        if child:has_tag("item") then
            table.insert(self.items, { node = child, name = child.name, label = child:get_property("text"), color = child:get_property("color") })
        end
    end
    self.index = 1
    self.open = false
    if self.kind == "title" then
        self.level = Game.progress.unlocked
        local best = self.node:get_child("Best")
        if best then best.text = Game:best_text() end
        self:show(true)
    elseif self.kind == "result" then
        local r = Game.result or { won = false, score = 0, level = 1 }
        self.node:get_child("Heading").text = r.won and "You win!" or "Game over"
        self.node:get_child("Score").text = Game:result_text(r)
        self.node:get_child("Best").text = r.new_best and "New best!" or Game:best_text()
        self:item("Again").label = r.won and "Play again" or ("Retry " .. Game.LEVEL_WORD:lower() .. " " .. r.level)
        self:show(true)
    else
        self:show(false)
    end
end

-- item: the choice named `name`.
function Menu:item(name)
    for _, it in ipairs(self.items) do if it.name == name then return it end end
end

-- show: opens / closes the menu (the pause menu pauses the game).
---@param open boolean
function Menu:show(open)
    self.open = open
    self.node:set_visible(open) -- (its children with it: a hidden node hides its subtree)
    if self.kind == "pause" then Engine.set_paused(open) end
    self.index = 1
    self.wait = open and 1 or 0 -- (the key that opened it isn't also a choice)
    self:refresh()
end

-- The value a choice shows after its label: the volume, the start level.
function Menu:value(name)
    if name == "Volume" then return string.format("%d%%", math.floor(Game.settings.volume * 100 + 0.5)) end
    if name == "Level" then return tostring(self.level) end
end

function Menu:refresh()
    for i, it in ipairs(self.items) do
        local on = i == self.index
        local v = self:value(it.name)
        local text = on and ("> " .. it.label .. " <") or it.label
        if v then text = it.label .. "  " .. (on and ("< " .. v .. " >") or v) end -- (Volume  < 80% >)
        it.node.text = text
        it.node:set_property("color", on and self.selected or it.color)
    end
end

-- step: left / right on a value choice.
---@param d integer -1 or 1
function Menu:step(d)
    local name = self.items[self.index].name
    if name == "Volume" then
        Game:set_volume(Game.settings.volume + d * 0.1)
    elseif name == "Level" then
        self.level = (self.level - 1 + d) % Game.progress.unlocked + 1
    else
        return
    end
    self:refresh()
end

-- choose: the selected choice does its thing.
function Menu:choose()
    local name = self.items[self.index].name
    if name == "Volume" or name == "Level" then
        self:step(1) -- (a click on a value steps it on)
    elseif name == "Play" then
        Game:new_run(self.level)
    elseif name == "Settings" then
        self:show(false)
        Scene.find_node("SettingsMenu"):get_script():show(true)
    elseif name == "Quit" then
        -- (The web can't quit: a page closes itself only when its tab does.)
        if not Engine.quit() then self.items[self.index].label = "Close the tab to quit"; self:refresh() end
    elseif name == "Back" then
        self:back()
    elseif name == "Resume" then
        self:show(false)
    elseif name == "Restart" then
        self:show(false)
        Scene.reload()
    elseif name == "Title" then
        if self.kind == "pause" then self:show(false) end
        Game.run = nil
        Game:go(TITLE)
    elseif name == "Again" then
        local r = Game.result or { won = true, level = 1 }
        Game:new_run(r.won and 1 or r.level)
    end
end

-- back: Cancel - settings return to the title menu (saved), pause resumes.
function Menu:back()
    if self.kind == "settings" then
        Game:flush()
        self:show(false)
        Scene.find_node("Menu"):get_script():show(true)
    elseif self.kind == "pause" then
        self:show(false)
    end
end

---@param dt number
function Menu:update(dt)
    if self.kind == "pause" and not self.open then
        if Input.is_action_pressed("pause") then self:show(true) end
        return
    end
    if not self.open then return end
    if self.wait > 0 then self.wait = self.wait - 1 return end
    local n = #self.items
    if Input.is_action_pressed("move_down") then self.index = self.index % n + 1; self:refresh() end
    if Input.is_action_pressed("move_up") then self.index = (self.index - 2) % n + 1; self:refresh() end
    if Input.is_action_pressed("move_left") then self:step(-1) end
    if Input.is_action_pressed("move_right") then self:step(1) end
    if Input.is_action_pressed("confirm") then self:choose() return end
    if Input.is_action_pressed("pause") then self:back() return end
    -- A click / tap on a choice.
    if Input.is_mouse_button_pressed("LEFT") then
        local mx, my = Input.get_mouse_position()
        for i, it in ipairs(self.items) do
            local x, y = it.node:get_position()
            if math.abs(mx - x) <= self.item_width / 2 and math.abs(my - y) <= self.item_height / 2 then
                self.index = i
                self:refresh()
                self:choose()
                return
            end
        end
    end
end

return Menu
