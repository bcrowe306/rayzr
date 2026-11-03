-- Spikes: a Trigger Area that hurts the player.

---@class Spikes : ScriptInstanceBase
local Spikes = {}

---@param body Node?
function Spikes:on_body_entered(body)
    if body == nil or not body:has_tag("player") then return end
    body:get_script():hurt(25)
end

return Spikes
