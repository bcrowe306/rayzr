-- The game's title (tests/mods): from data/config.json, which a mod may replace.
---@class Title
local Title = {}

function Title:ready()
    local cfg = Project.read_json("data/config.json") or {}
    self.node.text = cfg.title or "?"
    Mods.emit("title_ready", self.node) -- a hook the game offers mods
end

return Title
