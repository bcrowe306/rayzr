package engine

import "core:strings"

// ============================================================================
// Script templates for CharacterMoverNode.
//
// The editor writes CHARACTER_PLATFORMER_TEMPLATE when you create a new
// script on a CharacterMover (and switches the node to Script mode), like
// Godot's "Basic Movement" template for CharacterBody2D. $NAME$ / $CLASS$
// are replaced with the file and class names.
// ============================================================================

CHARACTER_PLATFORMER_TEMPLATE :: `-- $NAME$: platformer movement for a CharacterMover.
--
-- The script owns the movement (the node's Control Mode is "Script"): every
-- frame it works out the velocity - gravity, running, jumping - then calls
-- character_move_and_slide(), which moves the capsule by that velocity,
-- slides it along whatever it touches and updates the floor / wall / ceiling
-- state. Delete what you don't need; tune the properties in the Inspector.
--
-- CharacterMover API (on self.node):
--   character_move_and_slide([dt]) -> collided   Move by the velocity and slide along surfaces
--   character_get_velocity() -> vx, vy           Pixels per second (+y is down)
--   character_set_velocity(vx, vy)
--   character_get_gravity() -> gx, gy            World gravity x the node's gravity scale
--   character_set_gravity_scale(scale)
--   character_is_on_floor() -> bool              Set by the last move_and_slide
--   character_is_on_wall() -> bool
--   character_is_on_ceiling() -> bool
--   character_get_floor_normal() -> nx, ny       Slope under the feet (0, -1 on flat ground)
--   character_get_wall_normal() -> nx, ny        Points away from the wall
--   character_get_last_motion() -> dx, dy        How far the last move_and_slide moved
--   character_set_control_mode("script" | "builtin")
--
-- Input actions (Project Settings > Input): move_left, move_right, jump.
-- Events this script raises (connect them in the Signals panel or with
-- node:connect): "jumped", "landed".

---@class $CLASS$ : ScriptInstanceBase
---@signal jumped Left the ground (a jump, a coyote jump or an air jump)
---@signal landed Touched the floor again
local $CLASS$ = {}

-- Exported properties appear in the Inspector.
$CLASS$.properties = {
    speed          = { type = "float", default = 240.0, label = "Run Speed" },        -- px/s
    acceleration   = { type = "float", default = 1800.0, label = "Acceleration" },    -- px/s^2 toward the run speed
    friction       = { type = "float", default = 2400.0, label = "Friction" },        -- px/s^2 back to 0 without input
    air_control    = { type = "float", default = 0.6, label = "Air Control" },        -- acceleration multiplier in the air
    jump_velocity  = { type = "float", default = 420.0, label = "Jump Velocity" },    -- px/s upwards
    jump_cut       = { type = "float", default = 0.5, label = "Jump Cut" },           -- releasing jump early keeps this much of the rise
    coyote_time    = { type = "float", default = 0.1, label = "Coyote Time" },        -- s: can still jump just after leaving a ledge
    jump_buffer    = { type = "float", default = 0.1, label = "Jump Buffer" },        -- s: a jump pressed just before landing still counts
    max_fall_speed = { type = "float", default = 900.0, label = "Max Fall Speed" },   -- px/s
    wall_slide     = { type = "bool", default = false, label = "Wall Slide & Jump" },
    wall_slide_speed = { type = "float", default = 120.0, label = "Wall Slide Speed" },
}

-- move_toward: step value toward target by at most delta.
local function move_toward(value, target, delta)
    if value < target then return math.min(value + delta, target) end
    return math.max(value - delta, target)
end

function $CLASS$:ready()
    self.coyote = 0       -- time left to jump after leaving the floor
    self.buffered = 0     -- time left on a jump pressed in the air
    self.was_on_floor = false
    self.facing = 1       -- 1 right, -1 left (e.g. to flip a sprite)
end

---@param dt number
function $CLASS$:update(dt)
    local node = self.node
    local vx, vy = node:character_get_velocity()
    local on_floor = node:character_is_on_floor()

    -- Gravity. It is added on the floor too: move_and_slide removes the part
    -- pushing into the ground, which keeps the floor contact (and slopes) stable.
    local gx, gy = node:character_get_gravity()
    vx = vx + gx * dt
    vy = math.min(vy + gy * dt, self.max_fall_speed)

    -- Wall slide: falling while pressed against a wall slows the fall.
    local on_wall = self.wall_slide and node:character_is_on_wall() and not on_floor
    if on_wall and vy > self.wall_slide_speed then
        vy = self.wall_slide_speed
    end

    -- Jump, with coyote time (just left a ledge) and buffering (pressed just
    -- before landing). Releasing the button early cuts the jump short.
    if on_floor then self.coyote = self.coyote_time else self.coyote = self.coyote - dt end
    if Input.is_action_pressed("jump") then self.buffered = self.jump_buffer else self.buffered = self.buffered - dt end
    if self.buffered > 0 then
        if self.coyote > 0 then
            vy = -self.jump_velocity
            self.coyote, self.buffered = 0, 0
            node:emit("jumped")
        elseif on_wall then
            -- Wall jump: up and away from the wall.
            local nx = node:character_get_wall_normal()
            vx, vy = nx * self.speed, -self.jump_velocity
            self.buffered = 0
            node:emit("jumped")
        end
    end
    if Input.is_action_released("jump") and vy < 0 then
        vy = vy * self.jump_cut
    end

    -- Run: accelerate toward the input direction, slow down without input.
    local dir = Input.get_axis("move_left", "move_right")
    local control = on_floor and 1.0 or self.air_control
    if dir ~= 0 then
        vx = move_toward(vx, dir * self.speed, self.acceleration * control * dt)
        self.facing = dir > 0 and 1 or -1
    else
        vx = move_toward(vx, 0, self.friction * control * dt)
    end

    node:character_set_velocity(vx, vy)
    node:character_move_and_slide()

    -- Landing (the floor state comes from the move above).
    local landed = node:character_is_on_floor()
    if landed and not self.was_on_floor then
        node:emit("landed")
    end
    self.was_on_floor = landed

    -- Hit the ceiling: stop rising (move_and_slide already clipped the velocity).
    if node:character_is_on_ceiling() then
        local cvx, cvy = node:character_get_velocity()
        if cvy < 0 then node:character_set_velocity(cvx, 0) end
    end
end

return $CLASS$
`

// CharacterTemplate_Fill replaces $NAME$ and $CLASS$ in a template.
CharacterTemplate_Fill :: proc(template, name, class: string, allocator := context.allocator) -> string {
	a, _ := strings.replace_all(template, "$CLASS$", class, context.temp_allocator)
	b, _ := strings.replace_all(a, "$NAME$", name, allocator)
	return b
}
