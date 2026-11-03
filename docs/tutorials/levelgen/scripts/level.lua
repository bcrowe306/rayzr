-- The level: on the Level Generator node. Each time a cave is in it puts
-- the player on the start point and counts the coins; R makes a new cave
-- (Random Seed is on, so each one is different).

---@class Level : ScriptInstanceBase
local Level = {}

function Level:ready()
    self.player = Scene.find_node("Player")
    self.info = Scene.find_node("Info") ---@type TextNode
    self.coins = Scene.find_node("Coins") ---@type TextNode
    self.caves = 0
    self.got = 0
    Events.connect("coin_collected", function(value)
        self.got = self.got + value
        self:show_coins()
    end)
end

-- generation_progress: 0 to 1 while a cave is made.
---@param p number
function Level:on_generation_progress(p)
    self.info.text = string.format("Digging... %d%%", math.floor(p * 100))
end

-- generated: the cave is in (tiles, colliders, coins, the start point).
---@param seed integer
function Level:on_generated(seed)
    self.caves = self.caves + 1
    self.info.text = string.format("Cave %d - seed %d - R: a new cave", self.caves, seed)
    -- (The last cave's coins and start point are gone already: queued for
    -- removal, find_by_tag no longer finds them.)
    self:start_cave()
end

-- start_cave: the player on the start point, the coins counted.
function Level:start_cave()
    local start = Scene.find_by_tag("start")[1]
    if start then
        -- (The player sits at the scene's root: its position is a world one.)
        self.player:set_position(start:get_global_position())
    end
    self.got = 0
    self.total = #Scene.find_by_tag("coin")
    self:show_coins()
end

-- generation_failed: no playable cave in Attempts tries.
---@param why string
function Level:on_generation_failed(why)
    self.info.text = "No cave: " .. why
end

function Level:show_coins()
    self.coins.text = string.format("Coins: %d / %d", self.got, self.total or 0)
end

---@param dt number
function Level:update(dt)
    if Input.is_key_pressed("R") and not self.node:levelgen_is_generating() then
        self.node:levelgen_generate() -- no seed: a new random one
    end
end

return Level
