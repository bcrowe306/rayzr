-- Sokoban: push every crate onto a target. The board is built from the
-- level text below (TextureNodes made at runtime), moves slide with a
-- tween, every move can be undone. Each level has a move limit: run out
-- before it's solved and the game is over. Finish a level to go to the next
-- (Game: unlocked and its fewest moves saved; the result screen after the
-- last). The level played is the run's (Game.run.level); Start Level when
-- the scene is played on its own (F6).
--
-- Level text: # wall, . target, $ crate, * crate on a target, @ you,
-- + you on a target, spaces are floor (only the inside gets a floor tile).
-- Add a level: copy one, change it - keep it solvable!

---@class Puzzle : ScriptInstanceBase
local Puzzle = {}

Puzzle.properties = {
    start_level = { type = "int", default = 1, min = 1, label = "Start Level" },
    tile        = { type = "float", default = 64, label = "Tile Size" },        -- px
    slide_time  = { type = "float", default = 0.08, label = "Slide Time" },     -- s per step
    repeat_time = { type = "float", default = 0.16, label = "Key Repeat" },     -- s between steps when held
}

local LEVELS = {
--$LEVELS$
}

-- Each level's move limit (make_templates.py: twice its shortest solution and 6 more).
local LIMITS = { --$LIMITS$ }

local DIRS = { move_up = { 0, -1 }, move_down = { 0, 1 }, move_left = { -1, 0 }, move_right = { 1, 0 } }

function Puzzle:ready()
    self.hold, self.held = 0, nil
    self.run = Game:ensure_run(self.start_level)
    self:load(self.run.level)
end

-- key: a grid cell's table key.
local function key(c, r) return c .. "," .. r end

-- sprite: a TextureNode on the board at a cell.
function Puzzle:sprite(name, tex, c, r, z)
    local n = Scene.create("TextureNode", self.node)
    n.name = name
    n:set_texture("textures/" .. tex .. ".png")
    n:set_property("z_index", z)
    n:set_position(self:pos(c, r))
    return n
end

function Puzzle:pos(c, r)
    return self.ox + (c - 1) * self.tile, self.oy + (r - 1) * self.tile
end

-- load: builds level n (1-based).
function Puzzle:load(n)
    n = math.max(1, math.min(n, #LEVELS))
    self.level = n
    self.limit = LIMITS[n]
    for _, child in ipairs(self.node:get_children()) do child:destroy() end
    self.walls, self.goals, self.crates, self.history = {}, {}, {}, {}
    self.moves, self.done, self.lost = 0, false, false
    local rows = LEVELS[n]
    local w, h = 0, #rows
    for _, row in ipairs(rows) do w = math.max(w, #row) end
    -- Centred on the screen.
    local sw, sh = Engine.get_virtual_size()
    self.ox = (sw - (w - 1) * self.tile) / 2
    self.oy = (sh - (h - 1) * self.tile) / 2 + 16
    local start
    for r = 1, h do
        for c = 1, #rows[r] do
            local ch = rows[r]:sub(c, c)
            if ch == "#" then self.walls[key(c, r)] = true end
            if ch == "." or ch == "*" or ch == "+" then self.goals[key(c, r)] = true end
            if ch == "@" or ch == "+" then start = { c, r } end
        end
    end
    -- Floor: the cells reachable from the start (the inside of the walls).
    local inside, todo = {}, { start }
    while #todo > 0 do
        local c, r = table.unpack(table.remove(todo))
        local k = key(c, r)
        if not inside[k] and not self.walls[k] and r >= 1 and r <= h and c >= 1 and c <= w then
            inside[k] = true
            table.insert(todo, { c + 1, r }); table.insert(todo, { c - 1, r })
            table.insert(todo, { c, r + 1 }); table.insert(todo, { c, r - 1 })
        end
    end
    for r = 1, h do
        for c = 1, #rows[r] do
            local k, ch = key(c, r), rows[r]:sub(c, c)
            if inside[k] then self:sprite("Floor", "ground", c, r, 0) end
            if self.walls[k] then self:sprite("Wall", "wall", c, r, 1) end
            if self.goals[k] then self:sprite("Goal", "goal", c, r, 1) end
            if ch == "$" or ch == "*" then
                self.crates[k] = self:sprite("Crate", "crate", c, r, 2)
            end
        end
    end
    self.pc, self.pr = start[1], start[2]
    self.player = self:sprite("Player", "player", self.pc, self.pr, 3)
    self:refresh()
end

function Puzzle:refresh()
    Scene.find_node("Level").text = "Level " .. self.level .. " / " .. #LEVELS
    Scene.find_node("Moves").text = "Moves " .. self.moves .. " / " .. self.limit
    local on = 0
    for k, crate in pairs(self.crates) do
        local on_goal = self.goals[k] == true
        crate:set_texture(on_goal and "textures/crate_on_goal.png" or "textures/crate.png")
        if on_goal then on = on + 1 end
    end
    local total = 0
    for _ in pairs(self.crates) do total = total + 1 end
    if on == total and not self.done then
        self.done, self.next_in = true, 1.0
        Scene.find_node("Message").text = self.level == #LEVELS and "All levels done!" or "Solved!"
    elseif not self.done and self.moves >= self.limit then
        -- Out of moves: the game is over (a moment to see it first).
        self.done, self.lost, self.next_in = true, true, 1.5
        Scene.find_node("Message").text = "Out of moves!"
    elseif not self.done then
        Scene.find_node("Message").text = ""
    end
end

function Puzzle:slide(node, c, r)
    local x, y = self:pos(c, r)
    Tween.cancel_all(node, "position")
    Tween.to(node, "position", Vec2(x, y), self.slide_time, "out_quad")
end

-- step: one move (dc, dr); pushes a crate if it can. True if it moved.
function Puzzle:step(dc, dr)
    local nc, nr = self.pc + dc, self.pr + dr
    local k = key(nc, nr)
    if self.walls[k] then return false end
    local pushed = nil
    if self.crates[k] then
        local bk = key(nc + dc, nr + dr)
        if self.walls[bk] or self.crates[bk] then return false end
        pushed = { from = k, to = bk }
        local crate = self.crates[k]
        self.crates[k], self.crates[bk] = nil, crate
        self:slide(crate, nc + dc, nr + dr)
    end
    table.insert(self.history, { pc = self.pc, pr = self.pr, pushed = pushed })
    self.pc, self.pr = nc, nr
    self:slide(self.player, nc, nr)
    if dc ~= 0 then
        local sx, sy = self.player:get_scale()
        self.player:set_scale(dc < 0 and -math.abs(sx) or math.abs(sx), sy)
    end
    self.moves = self.moves + 1
    self:refresh()
    return true
end

function Puzzle:undo()
    local last = table.remove(self.history)
    if not last then return end
    if last.pushed then
        local crate = self.crates[last.pushed.to]
        self.crates[last.pushed.to], self.crates[last.pushed.from] = nil, crate
        local c, r = last.pushed.from:match("(%-?%d+),(%-?%d+)")
        self:slide(crate, tonumber(c), tonumber(r))
    end
    self.pc, self.pr = last.pc, last.pr
    self:slide(self.player, self.pc, self.pr)
    self.moves = self.moves - 1
    self:refresh()
end

---@param dt number
function Puzzle:update(dt)
    if self.done then
        self.next_in = self.next_in - dt
        if self.next_in <= 0 then
            self.next_in = 1e9
            if self.lost then
                Game:finish(false)
            else
                Game:add_score(self.moves)
                Game:level_done(self.level, self.moves) -- (the next level: this scene again)
            end
        end
        return
    end
    if Input.is_action_pressed("restart") then self:load(self.level) return end
    if Input.is_action_pressed("undo") then self:undo() end
    -- A step per press; held, a step every Key Repeat seconds.
    for action, d in pairs(DIRS) do
        if Input.is_action_pressed(action) then
            self.held, self.hold = action, self.repeat_time * 2
            self:step(d[1], d[2])
            return
        end
    end
    if self.held and Input.is_action_down(self.held) then
        self.hold = self.hold - dt
        if self.hold <= 0 then
            self.hold = self.repeat_time
            local d = DIRS[self.held]
            self:step(d[1], d[2])
        end
    else
        self.held = nil
    end
end

return Puzzle
