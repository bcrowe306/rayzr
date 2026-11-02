# Skeletal animation (Spine, DragonBones)

Characters made of parts - a torso, arms, a head - moved by **bones**
instead of drawn frame by frame: smooth motion at any frame rate, small
textures, animations that blend into each other, and code can turn a bone
(aim an arm at the mouse). The engine has its own runtime and reads the
exports of the two common tools directly:

| Tool | Export | Next to it |
|---|---|---|
| **Spine** (3.8 - 4.2) | `hero.json` | `hero.atlas` + its page image(s) |
| **DragonBones** (5.x) | `hero_ske.json` | `hero_tex.json` + its image |

Keep the export in your project (e.g. `characters/hero/`); re-export from
the tool and the game picks up the new version.

## Quick start

1. Copy the export into the project.
2. **Add Node > Animation & Effects > Skeleton**.
3. Inspector > **Skeleton > File**: pick the `.json` (the list shows Spine
   exports with an .atlas next to them and DragonBones `_ske.json` files).
4. **Animation**: pick one - the viewport shows it. **Preview** plays it
   (or drag the time slider to scrub).

The game plays the **Animation** when the scene starts (**Autoplay**),
looping if **Loop** is on.

## Inspector

| | |
|---|---|
| **File** / **Atlas** | The export, and its atlas when it isn't next to it with the usual name. |
| **Armature** | DragonBones: which armature (empty = the first). |
| **Animation**, **Loop**, **Autoplay**, **Speed** | What plays. |
| **Mix Time** | Seconds to crossfade from one animation to the next (0.1-0.25 feels natural). |
| **Skin** | An attachment set (outfits, weapons) - Spine skins, DragonBones skins. |
| **Tint** | Multiplies every part's colour (hit flashes, ghosts). |
| **Show Bones** | Draws the bones - also in the game, for debugging. |
| **Preview** | Play / pause and scrub in the viewport (editing only). |
| **Bones** | Every bone, indented by hierarchy. Hover one: it lights up in the viewport. The link button adds a **Bone Attachment** following it. |

## Vector art on a skeleton

A skeleton doesn't need images: export just the bones (a Spine `.json`
with no atlas is listed too) and put Vector Shapes under the Skeleton.
A part that should stay rigid goes under a **Bone Attachment**; a part
that should **bend** with the bones (a sleeve, a tail) uses the Vector
Shape's *Bend with* - see
[vector skinning](vector.md#bending-with-bones-vector-skinning).

## Bone Attachments

A **Bone Attachment** node under a Skeleton follows one of its bones - put
anything under it: a sword sprite in the hand, a particle trail on a foot,
a light on a lantern, an Area on a fist for hits. **Follow Rotation** /
**Follow Scale** choose whether it turns / scales with the bone.

```
Hero (Skeleton)
├── hand_attach (Bone Attachment: bone "hand")
│   └── Sword (Sprite)
└── foot_attach (Bone Attachment: bone "foot_l")
    └── Dust (Particles)
```

## Scripting

```lua
local hero = self.node --[[@as SkeletonNode]]

hero:skeleton_play("run")                 -- loop, crossfade over Mix Time
hero:skeleton_play("attack", false, 0.1)  -- once, 0.1 s crossfade
hero:skeleton_stop()
hero:skeleton_is_playing()
hero:skeleton_set_skin("armored")
hero:skeleton_animations()                -- { "attack", "idle", "run" }
hero:skeleton_skins() / hero:skeleton_bones()
hero:skeleton_get_duration("attack")          -- seconds

local muzzle = hero:skeleton_bone_position("gun_tip")  -- Vec2 in the world
local angle = hero:skeleton_bone_rotation("arm")        -- degrees

-- Aim: the bone's rotation overrides the animation (nil gives it back).
hero:skeleton_set_bone_rotation("arm", aim_degrees)
hero:skeleton_set_bone_rotation("arm", nil)

hero:connect("skeleton_event", function(name)       -- the animation's events
    if name == "footstep" then Audio.play_sound("audio/step.wav") end
end)
hero:connect("animation_finished", function(name)
    if name == "attack" then hero:skeleton_play("idle") end
end)
```

## Tutorial: a character that runs, jumps and aims

```lua
---@class Player : ScriptInstanceBase
local Player = {}

function Player:ready()
    self.skel = self.node:get_node("Body") --[[@as SkeletonNode]]
    self.state = ""
end

function Player:set_anim(name, loop)
    if self.state ~= name then
        self.state = name
        self.skel:skeleton_play(name, loop)
    end
end

function Player:update(dt)
    local mover = self.node --[[@as CharacterMoverNode]]
    if not mover:character_is_on_floor() then self:set_anim("jump", false)
    elseif math.abs(mover.velocity.x) > 10 then self:set_anim("run", true)
    else self:set_anim("idle", true) end

    -- The arm follows the mouse.
    local mx, my = Camera.screen_to_world(Input.get_mouse_position())
    local shoulder = self.skel:skeleton_bone_position("shoulder")
    if shoulder then
        local deg = math.deg(math.atan(my - shoulder.y, mx - shoulder.x))
        self.skel:skeleton_set_bone_rotation("arm", deg)
    end
end

return Player
```

## What's supported

| | Spine | DragonBones |
|---|---|---|
| Bones (rotation, translation, scale, shear, inherit modes) | yes | yes (skew) |
| Region attachments / images (trimmed sub-textures) | yes | yes |
| Meshes, weighted meshes, linked meshes | yes | yes (weighted via bind poses) |
| Skins | yes | yes |
| IK (1 and 2 bones) | yes | yes (chain 0 / 1) |
| Timelines: rotate, translate, scale, shear | yes | rotate, translate, scale |
| Slot attachment / colour, draw order | yes | display, colour (no z-order) |
| Events | yes | yes |
| Curves: linear, stepped, Bezier | yes (one curve per key) | yes |
| Path / transform / physics constraints, clipping, deform (FFD) | no | no |

## How it works / performance

- A file is loaded **once** and shared by every node showing it (counted;
  freed with the last node). The data lives in one arena.
- Each node keeps a small pose (per bone: local values + a 2x3 world
  matrix). Per frame: setup pose, the animation (and the crossfaded
  previous one) applied, IK, world matrices - parents before children in
  one pass.
- Drawing: one textured quad per region, textured triangles per mesh
  (weighted vertices summed from their bones), batched by raylib per atlas
  page. The node's own transform is a single matrix, so moving / flipping
  a character costs nothing extra.
- Culling uses the bones' extent (with a margin for the art).

## Limits

- Spine Bezier keys: one curve shapes all channels of a key (the first
  channel's).
- No physics constraints (Spine 4.2) - bake them in Spine.
