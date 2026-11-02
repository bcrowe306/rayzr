# Paths and path followers

A **Path** is a curve drawn in the viewport: points joined by straight lines
or smooth Bézier curves. A **Path Follow** node placed under it travels
along the curve, and whatever is under the follower travels with it. Use
them for:

- moving platforms and elevators,
- enemy patrol routes, flying formations,
- rails, conveyor carts, roller coasters,
- projectiles on curved trajectories,
- camera tracks (an Advanced Camera can follow a path - see the camera
  guide).

## In the editor

**Add Node > Animation & Effects > Path**. Select it:

| In the viewport | |
|---|---|
| Drag a **square** | Move a point. |
| Drag a **dot** | Bend the curve (a point's two handles mirror each other; hold **Alt** to move one alone). |
| **Double-click** the curve | Add a point there (the curve keeps its shape). |
| **Alt+click** a point | Remove it. |
| **Ctrl/Cmd+click** empty space | Add a point at the end. |

The Inspector lists the points: their position, the **curve button**
(sharp corner ↔ smooth, which adds handles along the neighbours) and their
handles. **Closed** joins the last point back to the first; **Line Width**
draws the path in the game (rails, ropes - 0 keeps it invisible; the
editor always shows it); **Bake Interval** is how finely the curve is
measured (smaller = closer to the true curve).

Then **Add Node > Path Follow** with the path selected. Its Inspector:

| | |
|---|---|
| **Progress** | Distance along the path in pixels. Change it in the editor to preview where it starts. |
| **Speed** | Pixels per second it moves by itself (negative = backwards, 0 = only scripts move it). |
| **Loop** | At the end: **Stop** (fires `path_finished`), **Loop** (back to the start / round a closed path), **Ping Pong** (turns back; fires `path_looped`). |
| **Rotate** | Face the direction of travel. |
| **Side Offset** | Pixels to the right of the travel direction (lanes, a formation's slots). |

While editing, followers sit at their progress; in Simulate and Play they
move.

## Tutorial: a moving platform

```
Path              (points across the gap, Loop: closed? no)
└── PathFollow    speed 80, loop: Ping Pong, rotate: off
    └── Platform  (StaticBody, position 0, 0, a box shape)
        └── Sprite
```

1. Add a **Path**, drag its two points to the two ends of the platform's
   trip (add a point in the middle and pull its handles for an arc).
2. Add a **Path Follow** under it: Speed 80, Loop **Ping Pong**, Rotate off.
3. Add a **StaticBody** under the follower and set its **Position to 0, 0**
   (new bodies start elsewhere), give it a box shape and a sprite.
4. Play. A **CharacterMover** standing on the platform rides with it: the
   mover remembers the floor it stands on and moves by as much as that floor
   moved since the last frame - this works for any moved body (paths,
   animations, scripts).

## Tutorial: a patrol route

```
Route             (Path, closed, around the room)
└── Walker        (PathFollow, speed 60, Loop, rotate off)
    └── Guard     (an enemy: sprite, area, guard.lua)
```

Stop and resume it from the guard's script:

```lua
---@class Guard : ScriptInstanceBase
local Guard = {}

function Guard:ready()
    self.walker = self.node:get_parent()          -- the PathFollow
    self.speed = self.walker.speed
end

function Guard:on_sees_player()
    self.walker.speed = 0                          -- stop and look
end

function Guard:on_lost_player()
    self.walker.speed = self.speed                 -- carry on
end

return Guard
```

## Scripting

Followers are plain properties (`progress`, `speed`, `loop`, `rotate`,
`sideOffset`) plus:

```lua
local cart = self.node:get_node("Track/Cart")       -- a PathFollow
cart:follow_set_ratio(0.5)                          -- jump to the middle
print(cart:follow_get_ratio())                          -- 0..1
cart:follow_restart()                               -- back to the start (after path_finished)
cart:connect("path_finished", function() self:arrived() end)

-- Animate progress yourself (speed 0): an elevator called to a floor.
Tween.to(cart, "progress", 240, 1.5, "in_out_sine")
```

Paths themselves:

```lua
local route = self.node:get_node("Route")
local len = route:path_get_length()
local pos, dir = route:path_point_at(len * 0.25)    -- world position, direction
local d = route:path_closest_offset(player.position) -- distance along the path

-- Build one from code (local to the path).
route:path_clear()
route:path_add_point(Vec2(0, 0))
route:path_add_point(Vec2(200, -80), Vec2(-60, 0), Vec2(60, 0)) -- with handles
route:path_add_point(Vec2(400, 0))
```

| Method | Returns |
|---|---|
| `path:path_get_length()` | number |
| `path:path_point_at(distance)` | Vec2 world position, Vec2 direction |
| `path:path_closest_offset(x, y \| Vec2)` | distance along the path |
| `path:path_point_count()` | integer |
| `path:path_get_point(i)` | pos, handle_in, handle_out (local, 1-based) |
| `path:path_set_point(i, pos [, in, out])` / `path:path_add_point(pos [, in, out])` / `path:path_remove_point(i)` / `path:path_clear()` | - |
| `follow:follow_get_ratio()` / `follow:follow_set_ratio(r)` / `follow:follow_restart()` | |

Events: `path_finished` (Stop mode reached the end), `path_looped` (wrapped
or turned).

## Saved as

```json
{"type": "PathNode", "points": [[0, 0, 0, 0, 50, -60], [200, 0, -50, -60, 0, 0]],
 "properties": {"closed": false, "bakeInterval": 6, "lineWidth": 0, ...}}
{"type": "PathFollowNode", "properties": {"progress": 0, "speed": 80, "loop": "PingPong", "rotate": false, "sideOffset": 0}}
```

Each point is `[x, y, in x, in y, out x, out y]` (handles are offsets from
the point).

## Performance

The curve is turned into a polyline (a point every Bake Interval pixels)
the first time it's needed after an edit, kept in two flat arrays
(positions and running lengths), and redone only when the points change.
Moving a follower is a binary search in those lengths plus a lerp - a
hundred followers on one path cost next to nothing.

## Notes

- A follower must be a **direct child** of the path.
- Physics bodies under a follower are teleported each frame (the body
  follows its node); characters ride them, but dynamic bodies resting on a
  moving StaticBody aren't pushed along.
