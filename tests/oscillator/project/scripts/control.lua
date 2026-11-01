-- Oscillator test game (tests/oscillator/runtime_tests.json): pause at 0.5 s,
-- resume at 1 s (the phase kept), the "cycle" signal, then Stop puts the box back.
local Ctl = {}

function Ctl:ready()
    self.t = 0
    self.step = 0
    self.osc = Scene.find_node("Osc")
    self.log = Scene.find_node("Log")
    self.osc:connect("cycle", function(cycles) self:say("cycle" .. cycles) end)
end

function Ctl:say(s)
    self.log.text = self.log.text .. s .. " "
end

function Ctl:update(dt)
    self.t = self.t + dt
    if self.step == 0 and self.t >= 0.5 then
        self.osc:oscillator_pause()
        self.step = 1
    elseif self.step == 1 and self.t >= 0.75 then
        self:say(self.osc:oscillator_state())
        self.step = 2
    elseif self.step == 2 and self.t >= 1.0 then
        self.osc:oscillator_resume()
        self.step = 3
    elseif self.step == 3 and self.t >= 1.25 then
        local state, cycles = self.osc:oscillator_state()
        self:say(state .. string.format("%.0f", cycles * 4)) -- 0.75 cycles: paused for half a second
        self.step = 4
    elseif self.step == 4 and self.t >= 2.0 then
        self.osc:oscillator_stop()
        self:say(self.osc:oscillator_state())
        self.step = 5
    end
end

return Ctl
