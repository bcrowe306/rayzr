-- A room of the dungeon: which cells can be walked on, what a click does,
-- the chest and the door, the holes and the clock. The maps are isometric
-- (diamond cells): Floor, then Walls and Props (Y Sort on, so the hero
-- walks behind them), and Walk - an invisible map of the cells the hero may
-- stand on, made here from the others (the hero's Navigation Agent finds
-- its paths in it).
--
-- The game (Game, scripts/game.lua): the chest's key opens the door - the
-- next room (saved as reached), or the result screen after the last; the
-- seconds left are added to the score. A hole in the floor (a cell with
-- no Floor tile - off the edge too) costs a life
-- (the room starts again; none left: game over); the clock running out
-- ends the game.

---@class Dungeon : ScriptInstanceBase
local Dungeon = {}

Dungeon.properties = {
    room       = { type = "int", default = 1, min = 1, label = "Room" },          -- this scene's place in Game.LEVELS
    time_limit = { type = "float", default = 60, min = 1, label = "Time Limit" }, -- seconds to get out
}

-- Tile numbers in textures/dungeon.png (8 a row).
local CHEST_CLOSED = { [32] = true, [33] = true, [34] = true, [35] = true }
local CHEST_OPEN_OF = 4                                              -- closed + 4 = open
local DOOR_CLOSED = { [16] = true, [17] = true, [18] = true, [19] = true }
local DOOR_OPEN_OF = 4

function Dungeon:ready()
    self.floor = Scene.find_node("Floor") ---@type TileMapNode
    self.walls = Scene.find_node("Walls") ---@type TileMapNode
    self.props = Scene.find_node("Props") ---@type TileMapNode
    self.walk = Scene.find_node("Walk") ---@type TileMapNode
    self.hero = Scene.find_node("Hero"):get_script()
    self.message = Scene.find_node("Message")
    self.hint = Scene.find_node("Hint")
    self.time_text = Scene.find_node("Time")
    self.run = Game:ensure_run(self.room)
    self.time_left = self.time_limit
    self.done = false -- out (or lost): the room takes no more input
    Scene.find_node("RoomText").text = string.format("Room %d / %d", self.room, #Game.LEVELS)
    Scene.find_node("Lives").text = string.format("Lives %d", self.run.lives)
    self:build_walk()
    self:show_time()
end

-- build_walk: the floor's cells without a wall or a prop on them (a
-- dungeon up to 40 x 40 cells).
function Dungeon:build_walk()
    for y = 0, 40 do
        for x = 0, 40 do
            local open = self.floor:tilemap_get_tile(x, y) >= 0
                and self.walls:tilemap_get_tile(x, y) < 0
                and self.props:tilemap_get_tile(x, y) < 0
            self.walk:tilemap_set_tile(x, y, open and 0 or -1)
        end
    end
end

-- what_at: the chest or door in a cell (nil: neither).
function Dungeon:what_at(cx, cy)
    if CHEST_CLOSED[self.props:tilemap_get_tile(cx, cy)] then return "chest" end
    if DOOR_CLOSED[self.walls:tilemap_get_tile(cx, cy)] then return "door" end
    return nil
end

-- next_to: a thing in a cell next to (cx, cy), and its cell.
function Dungeon:next_to(cx, cy)
    for _, c in ipairs(self.walls:tilemap_neighbors(cx, cy)) do
        local what = self:what_at(c[1], c[2])
        if what then return what, c[1], c[2] end
    end
    return nil
end

-- clicked: walk to a floor cell; a chest or the door: walk next to it, then use it.
function Dungeon:clicked(cx, cy)
    if self.done then return end
    local what = self:what_at(cx, cy)
    if what then
        -- The open neighbour nearest the hero.
        local hx, hy = self.hero:cell()
        local best, bd
        for _, c in ipairs(self.walk:tilemap_neighbors(cx, cy)) do
            if self.walk:tilemap_get_tile(c[1], c[2]) >= 0 then
                local d = (c[1] - hx) ^ 2 + (c[2] - hy) ^ 2
                if not bd or d < bd then best, bd = c, d end
            end
        end
        if best then self.hero:walk_to(best[1], best[2], function() self:use(what, cx, cy) end) end
    elseif self.walk:tilemap_get_tile(cx, cy) >= 0 then
        self.hero:walk_to(cx, cy)
    end
end

-- use: open the chest (the key), open the door (with the key: out).
function Dungeon:use(what, cx, cy)
    if self.done then return end
    if what == "chest" then
        local t = self.props:tilemap_get_tile(cx, cy)
        self.props:tilemap_set_tile(cx, cy, t + CHEST_OPEN_OF)
        self.has_key = true
        self:say("You found a key!")
        Scene.find_node("KeyIcon").text = "Key: yes"
    elseif what == "door" then
        if not self.has_key then
            self:say("Locked. There must be a key somewhere...")
            return
        end
        local t = self.walls:tilemap_get_tile(cx, cy)
        self.walls:tilemap_set_tile(cx, cy, t + DOOR_OPEN_OF)
        local last = self.room >= #Game.LEVELS
        self:say(last and "The door opens. You escaped!" or "The door opens...", 1e9)
        Game:add_score(math.ceil(self.time_left))
        -- A moment to see it, then the next room (or the result).
        self:finish(1.2, function() Game:level_done(self.room) end)
    end
end

-- finish: the room is over; `after` runs `delay` seconds later.
function Dungeon:finish(delay, after)
    self.done = true
    self.hint.text = ""
    self.after, self.after_time = after, delay
end

function Dungeon:say(text, time)
    self.message.text = text
    self.message_time = time or 2.5
end

function Dungeon:show_time()
    local t = math.max(0, math.ceil(self.time_left))
    self.time_text.text = string.format("Time %d", t)
    self.time_text:set_property("color", t <= 10 and "#ff6b5bff" or "#e9dcc2ff")
end

function Dungeon:update(dt)
    if self.message_time then
        self.message_time = self.message_time - dt
        if self.message_time <= 0 then
            self.message.text = ""
            self.message_time = nil
        end
    end
    if self.after then
        self.after_time = self.after_time - dt
        if self.after_time <= 0 then
            local after = self.after
            self.after = nil
            after()
        end
        return
    end
    if self.done then return end
    -- The clock.
    self.time_left = self.time_left - dt
    self:show_time()
    if self.time_left <= 0 then
        self.hero:stop()
        self:say("Out of time!", 1e9)
        self:finish(1.5, function() Game:finish(false) end)
        return
    end
    local hx, hy = self.hero:cell()
    -- A hole (no floor): the hero falls - a life; the room starts again (none left: game over).
    if self.floor:tilemap_get_tile(hx, hy) < 0 then
        self.hero:fall()
        self:say("Aaargh!", 1e9)
        self:finish(1.2, function()
            if Game:lose_life() then Scene.reload() end
        end)
        return
    end
    -- E next to the chest or the door uses it.
    local what, cx, cy = self:next_to(hx, hy)
    self.hint.text = what and ("E: open the " .. what) or ""
    if what and Input.is_action_pressed("interact") then self:use(what, cx, cy) end
end

return Dungeon
