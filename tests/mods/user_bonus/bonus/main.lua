-- A mod with a level of its own (mod.json "scenes"): the game's main scene leads to it.
Mods.on("scene_ready", function(name)
    if name == "main" then Scene.change_scene("bonus") end
end)
