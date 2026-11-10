-- The title screen: New game, Continue (the autosave), Load (a save slot),
-- Settings (text speed, auto delay, volumes - kept in the save data and
-- used by the story scene) and Quit; the endings found so far.

---@class Title : ScriptInstanceBase
local Title = {}

Title.properties = {
    endings = { type = "int", default = 3, min = 1, label = "Endings" }, -- how many the story has
}

local STORY = "scenes/story.scene.json"

function Title:ready()
    local c = function(name, fn) Scene.find_node(name):connect("clicked", fn) end
    c("NewGame", function()
        Save.delete("autosave")
        Scene.change_scene(STORY, { transition = "fade", duration = 0.5 })
    end)
    c("Continue", function()
        if not Save.has("autosave") then return end
        Save.set("load_slot", "autosave")
        Scene.change_scene(STORY, { transition = "fade", duration = 0.5 })
    end)
    c("Load", function() Scene.find_node("Slots"):get_script():show("load") end)
    c("Settings", function() self:show_settings(true) end)
    c("SettingsClose", function() self:show_settings(false) end)
    c("Quit", function()
        -- (The web can't quit: a page closes itself only when its tab does.)
        if not Engine.quit() then Scene.find_node("Quit").text = "Close the tab to quit" end
    end)

    local cont = Scene.find_node("Continue")
    if not Save.has("autosave") then
        cont.text = "Continue (no save yet)"
        cont:set_property("text_color", { 0.59, 0.59, 0.63, 1 })
    end
    -- The keys and a gamepad: up / down move between the buttons, Enter (A)
    -- presses one - from Continue when there's a save, else New game.
    local first = Scene.find_node(Save.has("autosave") and "Continue" or "NewGame")
    ---@cast first UIButtonNode
    first:ui_focus()
    self:show_endings()

    -- Settings: the sliders show the saved values; a change is saved and used.
    local s = Save.get("settings", {})
    self.sliders = {
        TextSpeed = { key = "text_speed", default = 40 },
        AutoDelay = { key = "auto_delay", default = 1.2 },
        MusicVolume = { key = "music", default = 1, bus = "music" },
        SoundVolume = { key = "sfx", default = 1, bus = "sfx" },
    }
    for name, sl in pairs(self.sliders) do
        local node = Scene.find_node(name)
        local v = s[sl.key] or sl.default
        node:set_property("value", v)
        if sl.bus then Audio.set_bus_volume(sl.bus, v) end
        node:connect("value_changed", function(value)
            local all = Save.get("settings", {})
            all[sl.key] = value
            Save.set("settings", all)
            if sl.bus then Audio.set_bus_volume(sl.bus, value) end
        end)
    end
    self:show_settings(false)
end

-- show_endings: the endings found (vn.lua keeps them), a bad one marked.
function Title:show_endings()
    local names = {}
    for name, kind in pairs(Save.get("endings", {})) do
        names[#names + 1] = kind == "bad" and (name .. " (bad)") or name
    end
    table.sort(names)
    Scene.find_node("Endings").text = #names > 0
        and string.format("Endings found: %d / %d\n%s", #names, self.endings, table.concat(names, "   "))
        or ""
end

function Title:show_settings(open)
    local was_open = self.settings_open
    self.settings_open = open
    Scene.find_node("SettingsPanel"):set_property("enabled", open)
    Scene.find_node("Menu"):set_property("enabled", not open)
    if open then Scene.find_node("TextSpeed"):ui_focus() end
    if not open then
        Save.flush()
        if was_open then Scene.find_node("Settings"):ui_focus() end -- (back where it was)
    end
end

-- The buttons the keys / a gamepad reach: the focused one is lit.
local BUTTONS = { "NewGame", "Continue", "Load", "Settings", "Quit", "SettingsClose" }
local NORMAL, LIT = { 0.06, 0.07, 0.11, 0.9 }, { 0.36, 0.55, 1, 0.78 }

function Title:update(dt)
    if self.settings_open and Input.is_action_pressed("cancel") then self:show_settings(false) end
    for _, name in ipairs(BUTTONS) do
        local b = Scene.find_node(name)
        b:set_property("normal_color", b:ui_has_focus() and LIT or NORMAL)
    end
end

return Title
