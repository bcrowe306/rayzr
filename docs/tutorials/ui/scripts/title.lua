-- The title screen: Play starts the game, Quit closes it. The title pulses
-- with a tween; a Text node's Auto rendering keeps it sharp while it is
-- scaled.

---@class Title : ScriptInstanceBase
local Title = {}

function Title:ready()
    local title = self.node:get_node("Title")
    Tween.to(title, "scale", {1.1, 1.1}, 0.8, "in_out_sine", {loops = -1, yoyo = true})
    local play = self.node:get_node("Play") ---@type UIButtonNode
    play:connect("clicked", function()
        Scene.change_scene("scenes/main.scene.json", { transition = "fade", duration = 0.3 })
    end)
    self.node:get_node("Quit"):connect("clicked", function() Engine.quit() end)
    -- Play has the focus from the start: Enter plays, Down and Enter quit.
    play:ui_focus()
end

return Title
