-- tests/drive/export_mods.drive: writes to the mod's save folder (what the drive checks).
local safe = io == nil and os.execute == nil and package == nil
Mods.fs.write("save:ran.txt", "ran " .. Mods.self.id .. (safe and " sandboxed" or " UNSAFE"))
