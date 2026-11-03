-- The pause menu: a Screen Layer (anchored at the centre, Pause Mode
-- Always) with a UI Container of two buttons. Esc (the built-in "pause"
-- action: Esc, P or the gamepad's Start) opens and closes it.

---@class PauseMenu : ScriptInstanceBase
local PauseMenu = {}

function PauseMenu:ready()
    self.menu = self.node:get_node("Menu") ---@type UIContainerNode
    self.menu:get_node("Resume"):connect("clicked", function() self:show(false) end)
    self.menu:get_node("Quit"):connect("clicked", function()
        Engine.set_paused(false)
        Scene.change_scene("scenes/title.scene.json")
    end)
    self:show(false)
end

function PauseMenu:update(dt)
    if Input.is_action_pressed("pause") then
        self:show(not Engine.is_paused())
    end
end

---@param open boolean
function PauseMenu:show(open)
    Engine.set_paused(open)
    -- Disabled, the menu neither draws nor takes clicks.
    self.menu:set_enabled(open)
end

return PauseMenu
