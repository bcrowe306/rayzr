-- The title screen: Play starts the game. The title pulses with a tween;
-- a Text node's Auto rendering keeps it sharp while it is scaled.

---@class Title : ScriptInstanceBase
local Title = {}

function Title:ready()
    local title = self.node:get_node("Title")
    Tween.to(title, "scale", {1.1, 1.1}, 0.8, "in_out_sine", {loops = -1, yoyo = true})
    self.node:get_node("Play"):connect("clicked", function()
        Scene.change_scene("scenes/main.scene.json", { transition = "fade", duration = 0.3 })
    end)
end

return Title
