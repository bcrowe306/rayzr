-- The HurtboxZz type's script with signals (tests/drive/custom_signals.drive):
-- one declared here, one emitted but declared nowhere.
---@class HurtboxZz : ScriptInstanceBase
---@signal struck_hard(force: number) Hit very hard
local HurtboxZz = {}
HurtboxZz.properties = {
    max_health = { type = "float", default = 10 },
    armor = { type = "float", default = 0 },
}
function HurtboxZz:ready() self.health = self.max_health end
function HurtboxZz:take_damage(amount) self.health = self.health - amount end
function HurtboxZz:explode() self.node:emit("boomed") end
return HurtboxZz
