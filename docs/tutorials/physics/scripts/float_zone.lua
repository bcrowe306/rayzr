-- A zone of low gravity: a Trigger Area that lightens the player inside it.

---@class FloatZone : ScriptInstanceBase
local FloatZone = {}

FloatZone.properties = {
    --- The player's gravity multiplier inside the zone.
    gravity_scale = { type = "float", default = 0.3, min = 0, max = 2, label = "Gravity Scale" },
}

---@param body Node?
function FloatZone:on_body_entered(body)
    if body and body:has_tag("player") then
        body:character_set_gravity_scale(self.gravity_scale)
        print("Floating")
    end
end

---@param body Node?
function FloatZone:on_body_exited(body)
    if body and body:has_tag("player") then
        body:character_set_gravity_scale(1)
        print("Landed back in normal gravity")
    end
end

return FloatZone
