-- Chunked level test (tests/levelgen_chunks/runtime_tests.json): the node
-- the camera follows flies up and to the left - into negative chunks - for
-- 2.5 s, then holds still while the last chunks go in. The Log counts the
-- chunk events.
local Fly = {}

function Fly:ready()
    self.t = 0
    self.came, self.went = 0, 0
    self.gen = Scene.find_node("Gen")
    self.log = Scene.find_node("Log")
    self.gen:connect("chunk_generated", function(c) self.came = self.came + 1 end)
    self.gen:connect("chunk_unloaded", function(c) self.went = self.went + 1 end)
end

function Fly:update(dt)
    self.t = self.t + dt
    if self.t < 2.5 then
        self.node.position = self.node.position + Vec2(-520, -300) * dt
    end
    local cx, cy = self.gen:levelgen_chunk_at(self.node.position.x, self.node.position.y)
    local around = 0 -- (the 5 x 5 the generator keeps in: Chunk Radius 2)
    for y = cy - 2, cy + 2 do
        for x = cx - 2, cx + 2 do
            if self.gen:levelgen_is_chunk_loaded(x, y) then around = around + 1 end
        end
    end
    self.log.text = string.format("in %d out %d loaded %d at %d %d around %d", self.came, self.went, #self.gen:levelgen_loaded_chunks(), cx, cy, around)
end

return Fly
