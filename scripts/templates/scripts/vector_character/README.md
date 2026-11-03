# Vector Character

Pip, a cartoon character drawn as vector art and moved by bones, in a
small, complete game: **Pip's Walk**. Walk him through three short stages
to the flag before the clock runs out. Jump the thorn bushes, walk under
the bees when they fly up: touching either is game over, and so is the
clock reaching 0. On the way Pip stops to talk to his little brother Pep,
each of them lip-synced to his own voice (the clock waits). A title
screen, a settings screen (the volume), a pause menu and a result screen
come with it, and your progress is saved: the furthest stage reached (the
title's **Stage** starts there) and each stage's best time.

Pip breathes when he stands still, walks, jumps, talks with his mouth
following the voice, and blinks now and then. Everything is one SVG file
cut into parts: crisp at any zoom, and small.

| Play | |
|---|---|
| Walk | A / D or the arrows (a gamepad's stick or d-pad; the joystick on a touch screen) |
| Jump | W, Space, Up (a gamepad's bottom button; the A button) |
| Talk | T (a gamepad's left button; the T button). Enter, Space or T skips a line of a chat |
| Pause | Esc, P, gamepad Start (the II button on a touch screen) |
| Menus | Up / down to pick, Enter or Space to choose, left / right to change a value; or click / tap a choice |

## What's where

| | |
|---|---|
| `scenes/title.scene.json` | The title screen: Play, the start Stage, Settings (Volume), Quit; each stage's best time |
| `scenes/stage1`, `stage2`, `stage3` | The stages: **Pip** (the script) holding **Rig**, a Skeleton with a Vector Shape per part, and **LipSync**; **Pep** (the same parts, tinted, his own **PepLipSync**); the thorns and bees (tagged `hazard`); the **Goal** flag; the backdrop; the HUD; the pause menu. **Stage**'s *Time Limit* is the stage's clock, *Pip Says* / *Pep Says* their lines |
| `scenes/result.scene.json` | After a win or a game over: the time, the best times, Play again / Retry, the title |
| `art/pip.svg` | The character: one named group per part (`arm_back`, `leg_back`, `leg_front`, `body`, `head`, `eyes`, `mouth`, `arm_front`). `eyes` and `mouth` are swap sets: their child groups are the frames |
| `art/backdrop.svg`, `thorns.svg`, `bee.svg`, `flag.svg` | The sky, the hills and the path (copies side by side make a stage); the hazards; the goal |
| `rigs/pip.json` | The bones and their animations (`idle`, `walk`, `talk`, `jump`): a Spine export with bones only, no images |
| `audio/pip_mumble.wav` + `.tsv`, `pep_mumble` | The voices and their mouth cues (Rhubarb Lip Sync's format: a time and a mouth shape per line) |
| `scripts/pip.lua` | Walking, jumping, turning round, talking and blinking |
| `scripts/stage.lua` | The clock, the hazards, the chat with Pep, the flag |
| `scripts/hazard.lua` | A hazard's box; a bee's bobbing |
| `scripts/game.lua` | The global `Game` (Project Settings > Globals): the stages in order, the run, the save data (`settings`, `progress` in `save.json`); its last lines are this game's (the title's and the result's text) |
| `scripts/menu.lua` | Every menu: Text nodes tagged `item` are the choices; its **Kind** says what they do |

## How it works

Each part is a **Vector Shape** showing one group of `pip.svg` (its
**Symbol**). The parts sit under the **Skeleton**, placed over the bones as
they stand in the rig's setup pose. Each part's **Bend with** (Inspector >
Vector) names the bones it follows: the body follows `torso`, the head, eyes
and mouth follow `head`, and an arm follows its upper and lower arm bones.
**Skin Smooth** 0 keeps the body rigid; on the arms and legs a little
smoothing bends them round the elbow and knee.

The **Lip Sync** node plays the voice and reads the cues beside it (same
name, `.tsv`). While the voice plays it sets the Mouth's **Frame** to the
cue's shape: `X` (rest), `A` (M, B, P), `B`, `C`, `D`, `E`, `F`. Blinking
swaps the Eyes between `open` and `closed` the same way, from the script.

The step-by-step tutorial "Drawing and animating a vector character" in the
documentation builds Pip from scratch.

## Make it yours

- **Redraw Pip**: select a part and press **Edit Art** in the Inspector (or
  double-click it), or open `art/pip.svg` in Inkscape, Illustrator or
  Affinity. Keep the group names: the parts and the frames find their art
  by name. Saving updates the game.
- **Your own voice**: record a line, run it through
  [Rhubarb Lip Sync](https://github.com/DanielSWolf/rhubarb-lip-sync)
  (`rhubarb -f tsv line.wav -o line.tsv`), put both in `audio/` and set the
  script's **Voice** property to the `.wav`.
- **Change a stage**: move the thorns, the bees, Pep and the Goal in the
  editor; duplicate a Backdrop for a longer walk and raise Pip's *Right
  Edge* and the Camera's right limit. A bee's *Bob* and *Period* set its
  flight.
- **A fourth stage**: duplicate `stage3.scene.json` (Assets > right-click >
  Duplicate), change it, set its Stage's *Stage* to 4 and add it to
  `Game.LEVELS` at the top of `game.lua`.
- **New moves**: the rig is Spine's JSON. Add an animation in Spine (bones
  only) and play it with `skeleton_play("wave")`, or aim a bone from a
  script with `skeleton_set_bone_rotation`.
- **More characters**: duplicate **Pip** and tint its parts (the Vector
  Shape's **Tint** and **Brightness**), as Pep is: they share the art and
  its meshes.
- **Start over**: Game > Save Data > Delete Save Files.
