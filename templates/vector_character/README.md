# Vector Character

Pip, a cartoon character drawn as vector art and moved by bones. He
breathes when he stands still, walks left and right, talks with his mouth
following the voice, and blinks now and then. Everything is one SVG file
cut into parts: crisp at any zoom, and small.

| Play | |
|---|---|
| Walk | A / D or the arrows (a gamepad's stick or d-pad) |
| Talk | T (a gamepad's bottom button) |

## What's where

| | |
|---|---|
| `scenes/pip.scene.json` | **Pip** (the script) holding **Rig**, a Skeleton with a Vector Shape per part, and **LipSync**; the backdrop; the help line |
| `art/pip.svg` | The character: one named group per part (`arm_back`, `leg_back`, `leg_front`, `body`, `head`, `eyes`, `mouth`, `arm_front`). `eyes` and `mouth` are swap sets: their child groups are the frames |
| `rigs/pip.json` | The bones and their animations (`idle`, `walk`, `talk`): a Spine export with bones only, no images |
| `audio/pip_mumble.wav` + `.tsv` | The voice and its mouth cues (Rhubarb Lip Sync's format: a time and a mouth shape per line) |
| `scripts/pip.lua` | Walking, turning round, talking and blinking |
| `art/backdrop.svg` | The sky, the hills and the path |

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
- **New moves**: the rig is Spine's JSON. Add an animation in Spine (bones
  only) and play it with `skeleton_play("wave")`, or aim a bone from a
  script with `skeleton_set_bone_rotation`.
- **More characters**: duplicate **Pip** and tint its parts (the Vector
  Shape's **Tint** and **Brightness**): they share the art and its meshes.
