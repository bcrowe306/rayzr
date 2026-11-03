-- The settings screen: a volume slider and a fullscreen checkbox. Changes
-- apply at once; Back writes them to settings.json.

---@class Settings : ScriptInstanceBase
local Settings = {}

function Settings:ready()
    local settings = Game.settings
    local volume = self.node:get_node("Volume") ---@type UISliderNode
    local fullscreen = self.node:get_node("Fullscreen") ---@type UICheckboxNode
    -- Show the saved values (setting them from a script raises no value_changed).
    volume:set_property("value", settings.volume)
    fullscreen:set_property("checked", settings.fullscreen)

    volume:connect("value_changed", function(value)
        settings.volume = value
        Game:apply_settings()
    end)
    fullscreen:connect("value_changed", function(on)
        settings.fullscreen = on
        Game:apply_settings()
    end)
    self.node:get_node("Back"):connect("clicked", function()
        Game:save_settings()
        Scene.change_scene("scenes/title.scene.json")
    end)
    volume:ui_focus()
end

return Settings
