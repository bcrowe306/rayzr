-- A script mod (tests/mods): hooks, and what its sandbox lets it see.
local safe = io == nil and os.execute == nil and package == nil and debug == nil
Mods.on("scene_ready", function(name)
    Scene.find_node("Status").text = "hello " .. name .. (safe and " sandboxed" or " UNSAFE")
end)
Mods.on("title_ready", function(title)
    title.text = title.text .. "!"
end)
