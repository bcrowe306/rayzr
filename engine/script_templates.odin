package engine

// ============================================================================
// New-script templates: the editor's New Script dialog lists these (plus the
// platformer in character_templates.odin). $NAME$ / $CLASS$ are replaced
// with the file and class names. Each is a working starting point with its
// settings as Inspector properties.
// ============================================================================

Script_Template :: struct {
	id:          string,
	label:       string,
	description: string,
	text:        string,
	suits:       []typeid, // node types it is meant for (first pick for them; empty = any)
}

@(private = "file")
script_templates := [?]Script_Template{
	{"empty", "Empty", "ready() and update(dt) with one property.", SCRIPT_TEMPLATE_EMPTY, nil},
	{"resource", "Resource Class", "A data asset type: its properties are edited per resource file (Assets > Resources), its methods called by any script holding one. on_load runs once per table.", SCRIPT_TEMPLATE_RESOURCE, nil},
	{"platformer", "Platformer Character", "Run, jump (coyote time, jump buffer), wall slide - for a CharacterMover.", CHARACTER_PLATFORMER_TEMPLATE, {CharacterMoverNode}},
	{"top_down", "Top-Down Character", "Eight-way movement with acceleration and friction - for a CharacterMover.", SCRIPT_TEMPLATE_TOP_DOWN, {CharacterMoverNode}},
	{"enemy_patrol", "Enemy Patrol", "Walks back and forth, waits at the ends, chases a target that comes close.", SCRIPT_TEMPLATE_ENEMY_PATROL, nil},
	{"ui_menu", "UI Menu", "Start / options / back buttons: starts a scene, shows and hides a panel.", SCRIPT_TEMPLATE_UI_MENU, nil},
	{"pickup", "Pickup", "Bobs in place; a body with the collector tag picks it up (sound, shrink, gone) - for an AreaNode.", SCRIPT_TEMPLATE_PICKUP, {AreaNode}},
	{"door_trigger", "Door / Trigger", "When a tagged body enters: opens a door node or changes scene - for an AreaNode.", SCRIPT_TEMPLATE_DOOR_TRIGGER, {AreaNode}},
	{"accessibility_menu", "Accessibility Menu", "Builds the player's accessibility options - UI scale, colour filter, subtitles, captions, subtitle size and backdrop, screen shake - applied at once and saved for the player. For a UI Container.", SCRIPT_TEMPLATE_ACCESSIBILITY_MENU, nil},
	{"controls_menu", "Controls Menu (rebinding)", "Builds a row per input action - click one, press a key or button to rebind it; Reset to defaults. Saved for the player - for a UI Container.", SCRIPT_TEMPLATE_CONTROLS_MENU, {UIContainerNode}},
}

Script_Templates :: proc() -> []Script_Template {return script_templates[:]}

// Script_TemplateFor: the template a new script on this node type starts
// from ("empty" when none suits it).
Script_TemplateFor :: proc(t: typeid) -> string {
	for tp in Script_Templates() {
		for s in tp.suits do if s == t do return tp.id
	}
	return "empty"
}

Script_TemplateById :: proc(id: string) -> (Script_Template, bool) {
	for tp in Script_Templates() do if tp.id == id do return tp, true
	return {}, false
}

SCRIPT_TEMPLATE_RESOURCE :: `-- $NAME$: a resource class. Make resources of it with Assets > Resources > +.
---@class $CLASS$ : ResourceBase
local $CLASS$ = {}

-- Marks this script as a resource class. local_copy = true gives each
-- component instance its own copy (health, inventory); false shares one
-- table everywhere (item stats, settings).
$CLASS$.resource = { local_copy = false }

-- Edited in the Inspector, per resource file.
$CLASS$.properties = {
    value = { type = "float", default = 1.0, label = "Value" },
}

-- Once per table, after its properties are set.
function $CLASS$:on_load()
end

-- Methods: any script holding this resource can call them.
function $CLASS$:describe()
    return "value " .. self.value
end

return $CLASS$
`

SCRIPT_TEMPLATE_EMPTY :: `-- $NAME$
---@class $CLASS$ : ScriptInstanceBase
local $CLASS$ = {}

-- Exported properties appear in the Inspector.
$CLASS$.properties = {
    speed = { type = "float", default = 100.0, label = "Speed" },
}

function $CLASS$:ready()
end

---@param dt number
function $CLASS$:update(dt)
end

return $CLASS$
`

SCRIPT_TEMPLATE_TOP_DOWN :: `-- $NAME$: top-down (eight-way) movement for a CharacterMover.
--
-- Input actions (Project Settings > Input): move_left, move_right, move_up,
-- move_down. The node moves by script with no gravity and slides along
-- walls (character_move_and_slide).
---@class $CLASS$ : ScriptInstanceBase
local $CLASS$ = {}

$CLASS$.properties = {
    --- Top speed in pixels per second.
    speed        = { type = "float", default = 220.0, min = 0, group = "Movement" },
    --- How quickly it reaches the top speed (px/s^2).
    acceleration = { type = "float", default = 1600.0, min = 0, group = "Movement" },
    --- How quickly it stops without input (px/s^2).
    friction     = { type = "float", default = 2000.0, min = 0, group = "Movement" },
    --- Mirror the node to face where it moves.
    flip         = { type = "bool", default = true, group = "Look" },
}

-- step: move value toward target by at most delta.
local function step(value, target, delta)
    if value < target then return math.min(value + delta, target) end
    return math.max(value - delta, target)
end

function $CLASS$:ready()
    self.node:character_set_control_mode("script")
    self.node:character_set_gravity_scale(0)
    self.facing = 1
end

---@param dt number
function $CLASS$:update(dt)
    local node = self.node
    local x, y = Input.get_vector("move_left", "move_right", "move_up", "move_down")
    local vx, vy = node:character_get_velocity()
    local rate = (x ~= 0 or y ~= 0) and self.acceleration or self.friction
    vx = step(vx, x * self.speed, rate * dt)
    vy = step(vy, y * self.speed, rate * dt)
    node:character_set_velocity(vx, vy)
    node:character_move_and_slide(dt)

    if self.flip and x ~= 0 and (x > 0) ~= (self.facing > 0) then
        self.facing = x > 0 and 1 or -1
        local sx, sy = node:get_scale()
        node:set_scale(math.abs(sx) * self.facing, sy)
    end
end

return $CLASS$
`

SCRIPT_TEMPLATE_ENEMY_PATROL :: `-- $NAME$: walks back and forth, waits at the ends, chases a target
-- that comes within range and goes back to patrolling when it gets away.
--
-- Events it raises: "spotted" (the target came close), "lost" (it got away).
---@class $CLASS$ : ScriptInstanceBase
local $CLASS$ = {}

$CLASS$.properties = {
    --- Walking speed in pixels per second.
    speed       = { type = "float", default = 80.0, min = 0, group = "Patrol" },
    --- How far it walks from where it starts (pixels).
    distance    = { type = "float", default = 160.0, min = 0, group = "Patrol" },
    --- Patrol up and down instead of left and right.
    vertical    = { type = "bool", default = false, group = "Patrol" },
    --- Seconds it waits at each end.
    wait_time   = { type = "float", default = 0.6, min = 0, group = "Patrol" },
    --- What it chases (e.g. the player). Leave empty to only patrol.
    target      = { type = "node", group = "Chase" },
    --- It chases the target inside this distance (pixels).
    chase_range = { type = "float", default = 140.0, min = 0, group = "Chase" },
    --- Chasing speed in pixels per second.
    chase_speed = { type = "float", default = 130.0, min = 0, group = "Chase" },
}

function $CLASS$:ready()
    self.start = self.node.position
    self.dir = 1      -- 1 forward, -1 back
    self.wait = 0     -- seconds left waiting at an end
    self.chasing = false
end

-- face: mirror the node toward a horizontal direction.
function $CLASS$:face(dx)
    if dx == 0 then return end
    local sx, sy = self.node:get_scale()
    self.node:set_scale(math.abs(sx) * (dx > 0 and 1 or -1), sy)
end

---@param dt number
function $CLASS$:update(dt)
    local pos = self.node.position

    -- Chase the target while it is close.
    local target = self.target
    if target then
        local near = pos:distance(target.position) <= self.chase_range
        if near ~= self.chasing then
            self.chasing = near
            self.node:emit(near and "spotted" or "lost", target)
        end
        if near then
            local to = (target.position - pos):normalized()
            self.node.position = pos + to * (self.chase_speed * dt)
            self:face(to.x)
            return
        end
    end

    -- Patrol between start and start + distance.
    if self.wait > 0 then
        self.wait = self.wait - dt
        return
    end
    local axis = self.vertical and Vec2(0, 1) or Vec2(1, 0)
    local along = (pos - self.start):dot(axis)
    along = along + self.dir * self.speed * dt
    if along >= self.distance or along <= 0 then
        along = math.max(0, math.min(along, self.distance))
        self.dir = -self.dir
        self.wait = self.wait_time
    end
    local across = pos - self.start - axis * ((pos - self.start):dot(axis))
    self.node.position = self.start + across + axis * along
    if not self.vertical then self:face(self.dir) end
end

return $CLASS$
`

SCRIPT_TEMPLATE_UI_MENU :: `-- $NAME$: a menu - Start loads a scene, Options shows a panel, Back
-- hides it. Point the properties at your UI Button nodes (drop them from
-- the scene tree onto the property); leave any of them empty.
---@class $CLASS$ : ScriptInstanceBase
local $CLASS$ = {}

$CLASS$.properties = {
    --- The scene Start opens.
    start_scene    = { type = "scene", group = "Start" },
    --- The button that starts the game.
    start_button   = { type = "node", group = "Start" },
    --- The button that shows the options panel.
    options_button = { type = "node", group = "Options" },
    --- The options panel (hidden until Options is pressed).
    options_panel  = { type = "node", group = "Options" },
    --- The button that hides the options panel again.
    back_button    = { type = "node", group = "Options" },
    --- Scene transition ("none" switches at once).
    transition     = { type = "enum", values = {"fade", "wipe_left", "wipe_right", "wipe_up", "wipe_down", "circle", "none"}, default = "fade" },
}

function $CLASS$:ready()
    if self.options_panel then self.options_panel:set_visible(false) end
    if self.start_button then
        self.start_button:connect("clicked", function() self:start() end)
    end
    if self.options_button then
        self.options_button:connect("clicked", function() self:show_options(true) end)
    end
    if self.back_button then
        self.back_button:connect("clicked", function() self:show_options(false) end)
    end
end

function $CLASS$:start()
    if self.start_scene == "" then
        Log.warn("$NAME$: set Start Scene in the Inspector")
        return
    end
    Scene.change_scene(self.start_scene, self.transition ~= "none" and {transition = self.transition} or nil)
end

---@param show boolean
function $CLASS$:show_options(show)
    if self.options_panel then self.options_panel:set_visible(show) end
end

return $CLASS$
`

SCRIPT_TEMPLATE_PICKUP :: `-- $NAME$: a collectible for an AreaNode. It bobs in place; when a body
-- with the collector tag enters, it plays a sound, raises "collected" on
-- that body (connect it, or give the body's script on_collected) and
-- shrinks away.
---@class $CLASS$ : ScriptInstanceBase
local $CLASS$ = {}

$CLASS$.properties = {
    --- Only bodies with this tag pick it up ("" = any body).
    collector_tag = { type = "string", default = "player" },
    --- What it is worth (sent with "collected").
    value         = { type = "int", default = 1 },
    --- Played when it is picked up.
    sound         = { type = "audio" },
    --- Bobbing height in pixels (0 = still).
    bob_height    = { type = "float", default = 4.0, min = 0, group = "Look" },
    --- Bobs per second.
    bob_speed     = { type = "float", default = 1.5, min = 0, group = "Look" },
}

function $CLASS$:ready()
    self.base = self.node.position
    self.time = 0
    self.taken = false
end

---@param dt number
function $CLASS$:update(dt)
    if self.taken or self.bob_height == 0 then return end
    self.time = self.time + dt
    self.node.position = self.base + Vec2(0, math.sin(self.time * self.bob_speed * math.pi * 2) * self.bob_height)
end

---@param other Node?
function $CLASS$:on_body_entered(other)
    if self.taken or not other then return end
    if self.collector_tag ~= "" and not other:has_tag(self.collector_tag) then return end
    self.taken = true
    if self.sound ~= "" then Audio.play_sound(self.sound) end
    other:emit("collected", self.value)
    Tween.to(self.node, "scale", {0, 0}, 0.2, "in_back", {
        on_complete = function(node) node:destroy() end,
    })
end

return $CLASS$
`

SCRIPT_TEMPLATE_DOOR_TRIGGER :: `-- $NAME$: a trigger for an AreaNode. When a body with the tag enters it
-- slides a door node open (and closed again when everyone has left), or
-- changes scene when Target Scene is set. Raises "triggered" with the body.
---@class $CLASS$ : ScriptInstanceBase
local $CLASS$ = {}

$CLASS$.properties = {
    --- Only bodies with this tag trigger it ("" = any body).
    trigger_tag  = { type = "string", default = "player" },
    --- Trigger once only.
    once         = { type = "bool", default = false },
    --- The door node to move. Leave empty for a scene change only.
    door         = { type = "node", group = "Door" },
    --- How far the door moves when it opens (pixels).
    open_offset  = { type = "vector2", default = {0, -96}, group = "Door" },
    --- Seconds the door takes to open or close.
    open_time    = { type = "float", default = 0.4, min = 0, group = "Door" },
    --- Close again when nothing tagged is inside.
    auto_close   = { type = "bool", default = true, group = "Door" },
    --- Change to this scene when triggered (empty = stay).
    target_scene = { type = "scene", group = "Scene Change" },
}

function $CLASS$:ready()
    self.inside = 0
    self.used = false
    if self.door then self.closed_at = self.door.position end
end

---@param body Node?
function $CLASS$:counts(body)
    return body ~= nil and (self.trigger_tag == "" or body:has_tag(self.trigger_tag))
end

---@param open boolean
function $CLASS$:move_door(open)
    if not self.door then return end
    local p = self.closed_at
    if open then p = p + Vec2(self.open_offset[1], self.open_offset[2]) end
    Tween.to(self.door, "position", {p.x, p.y}, self.open_time, "out_quad")
end

---@param other Node?
function $CLASS$:on_body_entered(other)
    if not self:counts(other) or (self.once and self.used) then return end
    self.inside = self.inside + 1
    if self.inside > 1 then return end
    self.used = true
    self.node:emit("triggered", other)
    if self.target_scene ~= "" then
        Scene.change_scene(self.target_scene)
        return
    end
    self:move_door(true)
end

---@param other Node?
function $CLASS$:on_body_exited(other)
    if other ~= nil and not self:counts(other) then return end -- nil: it was destroyed
    self.inside = math.max(0, self.inside - 1)
    if self.inside == 0 and self.auto_close and not self.once then self:move_door(false) end
end

return $CLASS$
`

SCRIPT_TEMPLATE_CONTROLS_MENU :: `-- $NAME$: a controls menu. Put it on a UI Container (vertical layout):
-- it adds a row per input action (Project Settings > Input) - the action's
-- name and a button showing its keys; click the button, then press the key
-- or gamepad button to use (Escape cancels). Changes are saved for the
-- player and loaded when the game starts. Gamepad: the D-pad moves between
-- rows, A rebinds.
---@class $CLASS$ : ScriptInstanceBase
local $CLASS$ = {}

$CLASS$.properties = {
    --- Which binding the buttons change: keyboard / mouse, gamepad, or the first one.
    device       = { type = "enum", values = {"keyboard", "gamepad", "any"}, default = "keyboard" },
    --- Actions to leave out (comma separated, e.g. "pause, confirm, cancel").
    hide         = { type = "string", default = "confirm, cancel" },
    --- Width of the action name column (px).
    label_width  = { type = "float", default = 180 },
    --- Width of the key buttons (px).
    button_width = { type = "float", default = 220 },
}

local function pretty(name)
    local s = name:gsub("_", " ")
    return (s:gsub("^%l", string.upper))
end

function $CLASS$:ready()
    self.buttons = {}
    local hidden = {}
    for word in string.gmatch(self.hide, "[^,%s]+") do hidden[word] = true end
    for _, action in ipairs(Input.get_actions()) do
        if not hidden[action] then self:add_row(action) end
    end
    local reset = Scene.create_node("UIButtonNode", "ResetControls", self.node) --[[@as UIButtonNode]]
    reset.text = "Reset to defaults"
    reset.size = Vec2(self.label_width + self.button_width, 36)
    reset:connect("clicked", function()
        Input.reset_bindings()
        self:refresh()
    end)
end

function $CLASS$:add_row(action)
    local row = Scene.create_node("UIContainerNode", action .. "_row", self.node) --[[@as UIContainerNode]]
    row:set_property("direction", "Horizontal")
    row.size = Vec2(self.label_width + self.button_width + 8, 40)
    local label = Scene.create_node("UILabelNode", action .. "_label", row) --[[@as UILabelNode]]
    label.text = pretty(action)
    label.size = Vec2(self.label_width, 36)
    local button = Scene.create_node("UIButtonNode", action .. "_keys", row) --[[@as UIButtonNode]]
    button.size = Vec2(self.button_width, 36)
    button:connect("clicked", function() self:rebind(action) end)
    self.buttons[action] = button
    self:show(action)
end

-- The slot the buttons change: keyboard -> the first keyboard / mouse
-- binding, gamepad -> the first gamepad one (0 = "same device kind").
function $CLASS$:show(action)
    local text = "-"
    for _, b in ipairs(Input.get_bindings(action)) do
        local pad = (b.device == "button" or b.device == "axis")
        if self.device == "any" or (self.device == "gamepad") == pad then
            text = b.text
            break
        end
    end
    self.buttons[action].text = text
end

function $CLASS$:refresh()
    for action in pairs(self.buttons) do self:show(action) end
end

function $CLASS$:rebind(action)
    if Input.is_listening() then return end
    local button = self.buttons[action]
    button.text = "Press a key..."
    Input.listen(action, {
        device = self.device,
        -- on_done(result, text): "bound" or "cancelled"; another action
        -- may have lost that key, so refresh them all.
        on_done = function() self:refresh() end,
    })
end

return $CLASS$
`

SCRIPT_TEMPLATE_ACCESSIBILITY_MENU :: `-- $NAME$: an accessibility options menu. Put it on a UI Container (vertical
-- layout): it adds a row per setting, applied at once (the UI grows, the
-- colour filter changes, ...) and saved for the player when the menu goes
-- away (or press Save). Gamepad: the D-pad moves between rows.
---@class $CLASS$ : ScriptInstanceBase
local $CLASS$ = {}

$CLASS$.properties = {
    --- Width of the rows (px).
    width = { type = "float", default = 420 },
    --- Show the colour-blind filter's Simulate switch (for testing your game, not for players).
    show_simulate = { type = "bool", default = false },
}

local FILTERS = { "none", "protanopia", "deuteranopia", "tritanopia" }
local FILTER_NAMES = { none = "Off", protanopia = "Protanopia (red)", deuteranopia = "Deuteranopia (green)", tritanopia = "Tritanopia (blue)" }

function $CLASS$:ready()
    self.rows = {}
    self:slider("UI scale", "ui_scale", 0.75, 2)
    self:filter_button()
    self:slider("Filter strength", "colorblind_strength", 0, 1)
    if self.show_simulate then self:checkbox("Simulate (testing)", "colorblind_simulate") end
    self:checkbox("Subtitles", "subtitles")
    self:checkbox("Sound captions", "captions")
    self:slider("Subtitle size", "subtitle_scale", 0.75, 2)
    self:slider("Subtitle backdrop", "subtitle_background", 0, 1)
    self:slider("Screen shake", "screen_shake", 0, 1)
    local save = Scene.create_node("UIButtonNode", "SaveAccessibility", self.node) --[[@as UIButtonNode]]
    save.text = "Save"
    save.size = Vec2(self.width, 36)
    save:connect("clicked", function() Accessibility.save() end)
    local reset = Scene.create_node("UIButtonNode", "ResetAccessibility", self.node) --[[@as UIButtonNode]]
    reset.text = "Reset to defaults"
    reset.size = Vec2(self.width, 36)
    reset:connect("clicked", function()
        Accessibility.reset()
        self:refresh()
    end)
end

-- Every row shows the current value again (after Reset).
function $CLASS$:refresh()
    for key, row in pairs(self.rows) do row() end
end

function $CLASS$:slider(label, key, min, max)
    local s = Scene.create_node("UISliderNode", key .. "_slider", self.node) --[[@as UISliderNode]]
    s.label = label
    s.minValue, s.maxValue = min, max
    s.value = Accessibility.get(key)
    s.defaultValue = s.value
    s.size = Vec2(self.width, 36)
    self.rows[key] = function() s.value = Accessibility.get(key) end
    s:connect("value_changed", function(v) Accessibility.set(key, v) end)
end

function $CLASS$:checkbox(label, key)
    local cb = Scene.create_node("UICheckboxNode", key .. "_check", self.node) --[[@as UICheckboxNode]]
    cb.label = label
    cb.checked = Accessibility.get(key)
    cb.size = Vec2(self.width, 32)
    self.rows[key] = function() cb.checked = Accessibility.get(key) end
    cb:connect("value_changed", function(v) Accessibility.set(key, v) end)
end

function $CLASS$:filter_button()
    local b = Scene.create_node("UIButtonNode", "colorblind_button", self.node) --[[@as UIButtonNode]]
    b.size = Vec2(self.width, 36)
    local function show() b.text = "Colour filter: " .. FILTER_NAMES[Accessibility.get("colorblind")] end
    show()
    self.rows.colorblind = show
    b:connect("clicked", function()
        local cur = Accessibility.get("colorblind")
        local next = FILTERS[1]
        for i, f in ipairs(FILTERS) do
            if f == cur then next = FILTERS[i % #FILTERS + 1] end
        end
        Accessibility.set("colorblind", next)
        show()
    end)
end

function $CLASS$:on_destroy()
    Accessibility.save()
end

return $CLASS$
`
