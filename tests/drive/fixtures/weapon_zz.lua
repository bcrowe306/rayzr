-- A resource class (resources drive, #266).
local WeaponZz = {}
WeaponZz.resource = {}
WeaponZz.properties = {
    damage = { type = "int", default = 10 },
    name   = { type = "string", default = "?" },
}
return WeaponZz
