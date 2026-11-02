-- The title screen: New game, Continue (the autosave), Load (a save slot)
-- and Settings (text speed, auto delay, volumes - kept in the save data and
-- used by the story scene).

---@class Title : ScriptInstanceBase
local Title = {}

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

    local cont = Scene.find_node("Continue")
    if not Save.has("autosave") then
        cont.text = "Continue (no save yet)"
        cont:set_property("text_color", { 150, 150, 160, 255 })
    end
    local n = 0
    for _ in pairs(Save.get("endings", {})) do n = n + 1 end
    Scene.find_node("Endings").text = n > 0 and ("Endings found: " .. n .. " / 3") or ""

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

function Title:show_settings(open)
    self.settings_open = open
    Scene.find_node("SettingsPanel"):set_property("enabled", open)
    Scene.find_node("Menu"):set_property("enabled", not open)
    if not open then Save.flush() end
end

function Title:update(dt)
    if self.settings_open and Input.is_action_pressed("cancel") then self:show_settings(false) end
end

return Title
