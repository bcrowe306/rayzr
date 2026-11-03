-- Game: a global script (Project Settings > Project > Globals, named Game),
-- so every scene reaches it as `Game`. It owns the save data, in the
-- player's user-data folder:
--   settings.json         the player's settings: volume, fullscreen, last slot
--   slot_1.json ... 3     one saved game each, under the key "game"

---@class GameGlobal
local Game = {}

--- The save data's own version: raise it when the data changes shape, and
--- teach migrate() the step from the version before.
Game.SAVE_VERSION = 2
--- How many save slots the title screen offers.
Game.SLOTS = 3

local DEFAULT_SETTINGS = { volume = 0.8, fullscreen = false, last_slot = 1 }

-- A new game's data.
local function fresh_game()
    return { version = Game.SAVE_VERSION, gems = 0, total = 0, level = 1, unlocked = {}, play_time = 0 }
end

-- Brings a game saved by an older version up to date, one step at a time.
local function migrate(data)
    local version = data.version or 1
    if version < 2 then
        -- Version 1 called the gems "score" and had no pick levels or trophies.
        data.gems = data.score or 0
        data.total = data.gems
        data.score = nil
        data.level = 1
        data.unlocked = {}
        data.play_time = data.play_time or 0
    end
    -- (The next change: if version < 3 then ... end)
    data.version = Game.SAVE_VERSION
    return data
end

function Game:ready()
    -- The settings have a file of their own: they belong to the player, not
    -- to one saved game.
    Save.slot("settings")
    self.settings = Save.get("settings", {})
    for key, value in pairs(DEFAULT_SETTINGS) do
        if self.settings[key] == nil then self.settings[key] = value end
    end
    self.slot = self.settings.last_slot
    self.data = nil -- the game being played: a table from Save.get
    self:apply_settings()
end

-- Puts the settings into effect.
function Game:apply_settings()
    Audio.set_bus_volume("master", self.settings.volume)
    if Engine.is_fullscreen() ~= self.settings.fullscreen then
        Engine.set_fullscreen(self.settings.fullscreen)
    end
end

-- Writes settings.json, then goes back to the slot that was in use.
function Game:save_settings()
    local current = Save.slot()
    Save.slot("settings")
    Save.set("settings", self.settings)
    Save.flush()
    Save.slot(current)
end

-- Switches to save slot n (slot_<n>.json) and returns its game: nil when
-- the slot is empty.
---@param n integer
---@return table?
function Game:open_slot(n)
    self.slot = n
    Save.slot("slot_" .. n)
    local data = Save.get("game")
    if data == nil then return nil end
    return migrate(data)
end

-- Starts a new game in slot n, over whatever was there.
---@param n integer
function Game:new_game(n)
    self:remember_slot(n)
    self:open_slot(n)
    self.data = fresh_game()
    Save.set("game", self.data)
    Save.flush()
end

-- Carries on the game saved in slot n.
---@param n integer
function Game:continue_game(n)
    self:remember_slot(n)
    self.data = self:open_slot(n)
end

-- Empties slot n.
---@param n integer
function Game:delete_slot(n)
    self:open_slot(n)
    Save.delete("game")
    Save.flush()
    self.data = nil
end

-- The title screen starts at the slot played last.
---@param n integer
function Game:remember_slot(n)
    self.settings.last_slot = n
    self:save_settings()
end

return Game
