-- Plays the story in story.lua: one step at a time, lines in the Dialogue
-- box, choices as buttons above it, the background and characters as
-- pictures. Also: auto and skip, the backlog, save slots and an autosave.
--
-- Keys: Space / Enter / click go on. A toggles auto, hold Ctrl to skip
-- lines you have read, L (or the mouse wheel up) opens the backlog, F5 /
-- F9 quick save / load, Esc closes a panel. The buttons under the box do
-- the same.

---@class VisualNovel : ScriptInstanceBase
local VN = {}

VN.properties = {
    start = { type = "string", default = "start", label = "First chapter" },
}

local PLACES = { left = 300, center = 640, right = 980 }
local HISTORY = 100 -- lines kept for the backlog (and saved)

function VN:ready()
    local story = Scene.find_node("Story"):get_script()
    self.chapters, self.cast = story.chapters, story.characters
    self.box = Scene.find_node("Dialogue") ---@type DialogueNode
    self.flags, self.on_stage, self.history = {}, {}, {}
    self.read = Save.get("read", {}) -- "chapter:step" of every line seen (skip passes those)
    self.box:connect("chosen", function(i) self:chosen(i) end)
    self.box:connect("finished", function() self:finished() end)
    self.auto, self.skipping = false, false
    self:apply_settings()
    -- The buttons under the box and the backlog's Close.
    local buttons = { AutoButton = "on_auto", SkipButton = "on_skip", LogButton = "on_log", SaveButton = "on_save",
                      LoadButton = "on_load", TitleButton = "on_title", LogClose = "on_log_close" }
    for name, method in pairs(buttons) do
        Scene.find_node(name):connect("clicked", function() self[method](self) end)
    end

    self:open_log(false)

    -- The title screen's Load (or Continue) left a save to start from.
    local slot = Save.get("load_slot", nil)
    Save.delete("load_slot")
    local data = slot and Save.get(slot, nil)
    if data then self:load(data) else self:go(self.start) end
end

-- apply_settings: the title screen's (none saved: the Dialogue box's own).
function VN:apply_settings()
    local s = Save.get("settings", {})
    if s.text_speed then self.box:set_property("reveal_speed", s.text_speed) end
    self.box:dialogue_set_auto(self.auto, s.auto_delay)
end

-- Steps ------------------------------------------------------------------------

function VN:go(chapter)
    assert(self.chapters[chapter], "story.lua: no chapter '" .. tostring(chapter) .. "'")
    self.chapter, self.step = chapter, 0
    self:next()
end

-- next: runs steps until one shows a line (or a choice, or the end).
function VN:next()
    while true do
        self.step = self.step + 1
        local s = self.chapters[self.chapter][self.step]
        assert(s ~= nil, "story.lua: chapter '" .. self.chapter .. "' ran out - end it with a jump, a choice or the_end")
        if self:run(s) then return end
    end
end

function VN:run(s)
    if type(s) == "string" then
        self:say(nil, s)
        return true
    end
    if s.bg then
        self.bg_name = s.bg
        Scene.find_node("Background"):set_texture("textures/bg_" .. s.bg .. ".png")
    end
    if s.show then
        local c = self.on_stage[s.show] or { at = "center", pose = "idle" }
        c.at, c.pose = s.at or c.at, s.pose or c.pose
        self.on_stage[s.show] = c
        self:draw_stage()
    end
    if s.hide then
        self.on_stage[s.hide] = nil
        self:draw_stage()
    end
    if s.set then self.flags[s.set] = s.value == nil and true or s.value end
    if s.jump and (s.when == nil or self.flags[s.when]) then
        self.chapter, self.step = s.jump, 0
        assert(self.chapters[s.jump], "story.lua: no chapter '" .. s.jump .. "'")
    end
    if s.choice then
        self.options = {}
        local labels = {}
        for _, o in ipairs(s.options) do
            if o.need == nil or self.flags[o.need] then
                table.insert(self.options, o)
                table.insert(labels, o[1])
            end
        end
        self:say(nil, s.choice, labels)
        return true
    end
    if s.the_end then
        self:the_end(s.the_end)
        return true
    end
    if s[1] then -- { "ada", "Hello!", pose = "cheer" }
        if s.pose and self.on_stage[s[1]] then
            self.on_stage[s[1]].pose = s.pose
        end
        self:say(s[1], s[2])
        return true
    end
    return false
end

function VN:say(who, text, choices)
    local key = self.chapter .. ":" .. self.step
    if self.skipping and not self.read[key] then self:set_skip(false) end -- (skip stops at new lines)
    self.read[key] = true
    self.speaker = who
    self:draw_stage()
    local name = who and self.cast[who] and self.cast[who].name or nil
    self:remember(name or "", text)
    self.box:dialogue_show({ { speaker = name, text = text, choices = choices } })
    if not choices then self:autosave() end
end

function VN:chosen(i)
    local o = self.options[i]
    self:remember("", "> " .. o[1])
    if o.set then self.flags[o.set] = true end
    self.after_choice = o[2] -- (the box closes next: finished goes there)
end

function VN:finished()
    if self.ended then return end
    if self.after_choice then
        local to = self.after_choice
        self.after_choice = nil
        self:go(to)
    else
        self:next()
    end
end

function VN:the_end(name)
    self.ended = true
    local found = Save.get("endings", {})
    found[name] = true
    Save.set("endings", found)
    Save.delete("autosave")
    Save.flush()
    local banner = Scene.find_node("Ending")
    banner.text = "The End\n[size=32]" .. name .. "[/size]"
    banner:set_visible(true)
    self.box:dialogue_close()
end

-- The stage: background and characters --------------------------------------

-- draw_stage: Left / Center / Right show who stands there; whoever isn't
-- speaking is dimmed a little.
function VN:draw_stage()
    for place, x in pairs(PLACES) do
        local slot = Scene.find_node("Slot" .. place:sub(1, 1):upper() .. place:sub(2))
        local who
        for key, c in pairs(self.on_stage) do
            if c.at == place then who = key end
        end
        slot:set_visible(who ~= nil)
        if who then
            local c = self.on_stage[who]
            slot:set_texture("textures/" .. who .. "_" .. c.pose .. ".png")
            local lit = self.speaker == nil or self.speaker == who
            slot:set_property("tint", lit and { 255, 255, 255, 255 } or { 170, 170, 185, 255 })
            local _, y = slot:get_position()
            slot:set_position(x, y)
        end
    end
end

-- Backlog ----------------------------------------------------------------------

function VN:remember(name, text)
    table.insert(self.history, { name, text })
    if #self.history > HISTORY then table.remove(self.history, 1) end
end

function VN:open_log(open)
    self.log_open = open
    self.log_scroll = 0
    Scene.find_node("Log"):set_property("enabled", open) -- (enabled: the whole panel, buttons too)
    if open then self:draw_log() end
end

function VN:draw_log()
    local lines = {}
    local last = #self.history - self.log_scroll
    for i = math.max(1, last - 11), last do
        local h = self.history[i]
        if h[1] ~= "" then
            table.insert(lines, "[color=#facc15]" .. h[1] .. "[/color]  " .. h[2])
        else
            table.insert(lines, h[2])
        end
    end
    Scene.find_node("LogText").text = table.concat(lines, "\n")
end

-- Auto / skip -------------------------------------------------------------------

function VN:set_auto(on)
    self.auto = on
    self:apply_settings()
    Scene.find_node("AutoButton").text = on and "Auto: on" or "Auto"
end

function VN:set_skip(on)
    self.skipping = on
    self.box:dialogue_set_skip(on)
    Scene.find_node("SkipButton").text = on and "Skip: on" or "Skip"
end

-- Saving -------------------------------------------------------------------------

local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

-- snapshot: everything needed to come back to the current line (copies: a
-- saved table stays as it was).
function VN:snapshot()
    local last = self.history[#self.history]
    return copy({
        chapter = self.chapter, step = self.step, flags = self.flags, stage = self.on_stage, bg = self.bg_name,
        history = self.history, preview = last and last[2] or "",
    })
end

function VN:autosave()
    Save.set("autosave", self:snapshot())
    Save.set("read", self.read)
end

-- toast: a short note in the corner ("Saved").
function VN:toast(text)
    Scene.find_node("Toast").text = text
    self.toast_time = 1.5
end

function VN:load(data)
    data = copy(data)
    self.flags, self.history, self.on_stage = data.flags or {}, data.history or {}, data.stage or {}
    if data.bg then self:run({ bg = data.bg }) end
    if #self.history > 0 then table.remove(self.history) end -- (the line is said again)
    self.ended, self.after_choice = false, nil
    Scene.find_node("Ending"):set_visible(false)
    self.chapter, self.step = data.chapter, data.step - 1
    self:next()
end

-- Input ---------------------------------------------------------------------------

function VN:update(dt)
    if self.toast_time then
        self.toast_time = self.toast_time - dt
        if self.toast_time <= 0 then
            self.toast_time = nil
            Scene.find_node("Toast").text = ""
        end
    end
    local slots = Scene.find_node("Slots"):get_script()
    if self.ended then
        if Input.is_action_pressed("confirm") or Input.is_mouse_button_pressed("LEFT") then
            Scene.change_scene("scenes/title.scene.json", { transition = "fade", duration = 0.5 })
        end
        return
    end
    if self.log_open then
        local wheel = Input.get_mouse_wheel_move()
        if wheel ~= 0 or Input.is_action_pressed("move_up") or Input.is_action_pressed("move_down") then
            local up = wheel > 0 or Input.is_action_pressed("move_up")
            self.log_scroll = math.max(0, math.min(#self.history - 1, self.log_scroll + (up and 1 or -1)))
            self:draw_log()
        end
        if Input.is_action_pressed("cancel") or Input.is_action_pressed("log") then self:open_log(false) end
        self.box:set_property("paused", true)
        return
    end
    if slots.open then
        self.box:set_property("paused", true)
        return
    end
    self.box:set_property("paused", false)
    if Input.is_action_pressed("quick_save") then
        Save.set("quicksave", self:snapshot())
        Save.flush()
        self:toast("Quick saved")
    end
    if Input.is_action_pressed("quick_load") then
        if Save.has("quicksave") then
            self:load(Save.get("quicksave"))
            self:toast("Quick loaded")
        else
            self:toast("No quick save yet (F5)")
        end
    end
    if Input.is_action_pressed("auto") then self:set_auto(not self.auto) end
    if Input.is_action_pressed("log") or Input.get_mouse_wheel_move() > 0 then self:open_log(true) end
    -- Hold to skip (the Skip button toggles it).
    if Input.is_action_pressed("skip") then self:set_skip(true) end
    if Input.is_action_released("skip") then self:set_skip(false) end
    -- A click anywhere but the buttons goes on (the box takes the choices'
    -- clicks itself: not on the frame after one was up).
    if Input.is_mouse_button_pressed("LEFT") and not self.choices_up then self.box:dialogue_next() end
    self.choices_up = self.box:dialogue_has_choices()
end

-- The buttons under the box.
function VN:on_auto() self:set_auto(not self.auto) end
function VN:on_skip() self:set_skip(not self.skipping) end
function VN:on_log() self:open_log(true) end
function VN:on_save() Scene.find_node("Slots"):get_script():show("save") end
function VN:on_load() Scene.find_node("Slots"):get_script():show("load") end
function VN:on_title() Scene.change_scene("scenes/title.scene.json", { transition = "fade", duration = 0.4 }) end
function VN:on_log_close() self:open_log(false) end

return VN
