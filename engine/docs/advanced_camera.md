# Advanced camera: virtual cameras, blending, limits, trauma shake

The basic **Camera 2D** node follows one target with smoothing, dead
zones, rooms and shake presets - enough for many games, and it stays as it
is. The **Advanced Camera** adds what [Phantom Camera] (Godot) and
Cinemachine (Unity) are known for:

- **Virtual cameras.** Put as many Advanced Cameras in a scene as you like -
  one following the player, one framing a boss arena, one riding a rail
  for a cutscene. The scene's camera (the **host**) shows the one with the
  highest **Priority** and *blends* (eases) to another when it takes over.
- **Follow modes**: Glued, Simple (offset, damping, look-ahead), Group
  (frame several targets, auto-zoom), Path (ride a Path node), Framed
  (move only when the target leaves a dead zone).
- **Limits**: a rectangle, a node's bounds, or **the LDtk level the target
  is in** - when the player walks through a door into a linked neighbour
  level, the limits glide over to the new room.
- **Trauma shake** (from [trauma-gd]): hits add trauma, trauma decays, the
  shake grows with trauma², from smooth noise. Small hits are subtle, big
  ones stack into a big shake.

[Phantom Camera]: https://github.com/ramokz/phantom-camera
[trauma-gd]: https://github.com/filipbasara/trauma-gd

## Quick start

1. **Add Node > Core & 2D > Advanced Camera**.
2. In the Inspector's **Targets** section pick **Follow Target** (or drop the
   player from the Scene panel onto it).
3. Press Play. If the scene has no Camera 2D, one is added for the game as
   the host (it isn't saved); if it has one, that camera shows the advanced
   cameras whenever there are any.

In the editor each advanced camera draws its **frame** (violet): where it
would look right now at its zoom, with its name and priority. Selected,
it also shows its **dead zone** (Framed) and its **limits** (pink).

## Inspector

| Property | |
|---|---|
| **Priority** | The highest enabled one is shown (a tie: the one added last). |
| **Follow Mode** | None, Glued, Simple, Group, Path, Framed (below). |
| **Follow Target** | The node it follows. The picker writes a path (`../Player`); a bare name (`Player`) also works (the first node with that name). |
| **Follow Targets** | Group: more nodes, comma separated (**Add To Group** picks them). |
| **Follow Path** | Path: the Path node to ride. |
| **Follow Offset** | Added to the target's position. |
| **Damping** | Smoothing time (s). 0 locks on; 0.15-0.4 feels smooth. |
| **Axis Lock** | Don't follow on X, Y or both. |
| **Lookahead** | Seconds of the target's velocity to look ahead (a runner sees what's coming). |
| **Dead Zone** | Framed: fraction of the view the target roams freely in. |
| **Zoom** | 2 = twice as close. |
| **Auto Zoom** (+ Min / Max / Margin) | Group: zoom so every target fits. |
| **Limit Mode** | None, Rect, Node, Ldtk Level. |
| **Limit Rect** | left, top, right, bottom (world px). |
| **Limit Node** | A TileMap, LDtk level node (all its loaded levels), Navigation Region or StaticBody (its first shape). |
| **Limit Margin** | Shrinks (+) or grows (-) the limits. |
| **Limit Blend** | Seconds to glide to new limits (a new LDtk level). 0 = at once. |
| **Blend Time** / **Blend Ease** | How the host moves to this camera when it becomes active. |
| **Snap To Pixel** | Whole-pixel positions (pixel art; see [pixel_perfect.md](pixel_perfect.md)). |
| **Shake Intensity** / **Shake Rotation** | Offset (px) / rotation (degrees) at trauma 1. |
| **Shake Decay** | Trauma lost per second. |
| **Shake Frequency** | Noise speed: 8-15 is a jolt, 2-4 a sway. |
| **Trauma Exponent** | Shake = trauma ^ exponent. 2 (default) or 3. |

While simulating, **Make Active** raises its priority above the others and
**Shake** adds 0.6 trauma - handy for tuning.

The camera's own **Rotation** is blended too (a tilted cutscene shot).

### Follow modes

| Mode | |
|---|---|
| **None** | Stays where it's placed (a fixed shot of a room). |
| **Glued** | Exactly on the target (+ offset). No damping. |
| **Simple** | Target + offset + look-ahead, smoothed by Damping. |
| **Group** | The centre of all targets' bounds; Auto Zoom fits them. Co-op, a boss and the player. |
| **Path** | The point on the Path closest to the target (a corridor, a rail that keeps the camera on a track while the player wanders). |
| **Framed** | Moves only when the target leaves the dead zone, just enough to keep it at the edge. Platformers. |

With no target found it stays where it is.

## Scripting

```lua
local cam = Scene.find_node("PlayerCam")
cam:adv_camera_add_trauma(0.3)              -- stack shake (0..1)
cam:adv_camera_make_active()                -- priority above every other camera
if cam:adv_camera_is_active() then ... end  -- the host shows it
cam:adv_camera_snap()                       -- jump to the target now (after a teleport)

Camera.add_trauma(0.5)           -- the active advanced camera
local active = Camera.get_active()

cam.priority = 10                -- any property
cam.followTarget = "Boss"
cam.zoom = 1.5

cam:connect("became_active", function() print("cut to", cam:get_name()) end)
cam:connect("became_inactive", function() end)
```

`Camera.screen_to_world` / `world_to_screen` / `get_visible_world_bounds`
use the host, so they agree with what the advanced camera shows.

## Tutorial: a room-by-room camera on LDtk levels

A Metroidvania-style world where each LDtk level is a room:

1. Add an **LDtk Level** node in **World Mode** (every level of the world
   at its world position - see the LDtk section of the editor README).
2. Add an **Advanced Camera**: Follow Target = Player, Follow Mode =
   **Simple**, Damping 0.15.
3. **Limit Mode** = **Ldtk Level**, **Limit Blend** 0.4.

The camera never shows outside the room the player is in. Walking through
a door into the next level, the limits glide over in 0.4 s - a room
transition without a script. Rooms smaller than the view are centred.

For a hard cut instead, set Limit Blend 0.

## Tutorial: a boss arena camera

```
Level
├── Player
├── PlayerCam   (Advanced Camera, priority 0, Simple, follows Player)
└── Arena
    ├── Boss
    ├── ArenaCam (Advanced Camera, priority -1, Group: Player + Boss, Auto Zoom, Limit Node: Arena/Bounds)
    └── Trigger  (Area)
```

```lua
-- arena.lua on Arena
function Arena:ready()
    self.cam = self.node:get_node("ArenaCam")
    self.node:get_node("Trigger"):connect("body_entered", function(body)
        if body:get_name() == "Player" then self.cam:adv_camera_make_active() end
    end)
end

function Arena:boss_defeated()
    self.cam.priority = -1          -- back to PlayerCam (it blends)
end
```

Give ArenaCam **Blend Time** 1.2 and **Blend Ease** In Out Sine for a
smooth move to the wide shot.

## Tutorial: hits that shake

```lua
function Player:on_hit(damage)
    Camera.add_trauma(math.min(damage / 50, 0.6))
end

function Explosion:ready()
    -- Bigger the closer it is.
    local p = Scene.find_node("Player")
    local d = (p.position - self.node.position):length()
    Camera.add_trauma(math.max(0, 1 - d / 400))
end
```

Several small hits in a row stack (up to 1) and fade out by **Shake Decay**
per second. Because the shake is trauma², a 0.2 hit barely moves the
screen while 0.8 shakes hard - the curve is what makes it feel good.

## Tutorial: a cutscene on a rail

1. Draw a **Path** along the shot.
2. Add an Advanced Camera: **Follow Mode** Path, **Follow Path** that path,
   Follow Target the character walking the scene, Damping 0.3, priority -10.
3. In the cutscene script: `cam:adv_camera_make_active()`; at the end
   `cam.priority = -10`.

## Saved as

```json
{"type": "AdvancedCameraNode", "properties": {"priority": 0, "followMode": "Simple", "followTarget": "../Player",
  "followOffset": [0, 0], "damping": 0.2, "lookahead": 0, "deadZone": [0.3, 0.3], "zoom": 1,
  "limitMode": "LdtkLevel", "limitBlend": 0.4, "blendTime": 0.8, "blendEase": "In_Out_Sine",
  "shakeIntensity": 24, "shakeRotation": 2, "shakeDecay": 1.5, "shakeFrequency": 12, "traumaExponent": 2}}
```

## How it works / performance

- Advanced cameras are kept in a short list by their scene, so the host
  picks the active one without walking the tree.
- Every camera keeps tracking even while inactive (a few vector operations
  each), so a blend starts from where the new camera really is.
- The host blends position, zoom and rotation from what it showed when the
  switch began, so switching mid-blend is smooth too.
- LDtk limits look only at the levels the LDtk node has loaded (one level,
  or in World Mode every level of the world); a target between levels
  keeps the last limits.
- Targets are found by path each frame (a bare name scans the scene's
  nodes - prefer the picker's paths in big scenes).
- The editor preview runs on a copy of the camera: editing never changes
  its runtime state.

## Limits

- One host per scene (the current Camera 2D). Split screen needs two
  hosts - not yet.
- Shake noise is the same pattern every time (deterministic per camera).
