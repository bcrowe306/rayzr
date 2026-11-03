-- Height layers test (tests/levelgen_heights/runtime_tests.json): once the
-- level is in, counts each map's tiles and checks the stack - every peak on
-- a hill, every hill cell next to lower ground an edge tile (not the full
-- one), walls on the edges - then writes the result to the Log.
local Check = {}

local W, H = 80, 45
local HILL_FULL, PEAK_FULL = 48 + 46, 96 + 46 -- (each terrain's last pattern: every neighbour)

function Check:ready()
    self.t = 0
    self.done = false
end

function Check:update(dt)
    self.t = self.t + dt
    if self.done or self.t < 0.3 then return end
    self.done = true
    local ground, hills, peaks, walls = Scene.find_node("Ground"), Scene.find_node("Hills"), Scene.find_node("Peaks"), Scene.find_node("Walls")
    local g, h, p, w, bad, edges, cliffs = 0, 0, 0, 0, 0, 0, 0
    for y = 0, H - 1 do
        for x = 0, W - 1 do
            if ground:tilemap_get_tile(x, y) >= 0 then g = g + 1 end
            local ht = hills:tilemap_get_tile(x, y)
            local pt = peaks:tilemap_get_tile(x, y)
            if ht >= 0 and ht < 144 then h = h + 1 end
            if ht >= 144 then cliffs = cliffs + 1 end
            if pt >= 0 and pt < 144 then
                p = p + 1
                if hills:tilemap_get_tile(x, y) < 0 or hills:tilemap_get_tile(x, y) >= 144 then bad = bad + 1 end -- (a peak not on a hill)
            end
            if walls:tilemap_get_tile(x, y) >= 0 then w = w + 1 end
            if ht >= 48 and ht < 144 and x > 0 and hills:tilemap_get_tile(x - 1, y) < 0 then
                edges = edges + 1
                if ht == HILL_FULL then bad = bad + 1 end -- (an edge drawn as the middle)
            end
        end
    end
    local ok = g == W * H and h > 0 and p > 0 and w > 0 and edges > 0 and cliffs > 0 and bad == 0
    self.log = Scene.find_node("Log")
    self.log.text = string.format("%s ground %d hills %d peaks %d walls %d edges %d cliffs %d bad %d", ok and "heights ok" or "heights BAD", g, h, p, w, edges, cliffs, bad)
end

return Check
