# Pixel-perfect rendering

Pixel-art games draw at a small **virtual resolution** (320 x 180, 426 x 240,
640 x 360...) that is scaled up to the window. Project Settings > **Video** >
**Pixel Art** controls how that looks:

| Setting | What it does | Use it when |
|---|---|---|
| **Scaling** | **Integer**: scaled by a whole number (2x, 3x, 4x...) with bars around the frame - every game pixel exactly the same size. **Fit**: scaled to fill the window; with Sharp Pixels through a sharp-bilinear filter (below). | Integer for perfectly even pixels; Fit to fill the screen. |
| **Sharp Pixels** | Scales the frame without blurring its pixels: nearest-neighbour at whole scales, sharp-bilinear at fractional ones. Off: smooth. | Always for pixel art. |
| **Pixel Snap** | The camera, sprites, tiles, particles and text sit on whole game pixels. | Moving or scaled sprites shimmer, or their pixels look uneven. |
| **Smooth Camera** | (With Pixel Snap.) Keeps the camera's sub-pixel motion when scaling up, so pans glide instead of stepping one game pixel at a time. The node the camera follows stays still. | A smoothly moving camera in a low-resolution game. |

Each drawn node can override them in the Inspector's **Pixels** section
([below](#per-node-settings)), and text and UI can draw crisp at the
window's resolution instead of in the game's pixels ([Native and
Pixel text](#native-and-pixel-text)).

They apply to the running game (Play, exported builds, the web runner). The
editor's viewport also snaps and filters each node as the game does, so what
you place is what you get.

## Screen fill

A window or screen whose shape differs from the virtual resolution (a
640 x 380 game in a 16:9 window, fullscreen on a 16:10 laptop) is filled
by Project Settings > Video > **Screen Fill**:

- **Expand** (new projects): the same scale, and the frame grows to the
  screen's shape - the camera shows more of the world on the longer side,
  no bars. The virtual resolution is the least the player sees. With
  Integer Scaling the scale is a whole number and the frame grows by whole
  game pixels (a border of a few screen pixels at most).
- **Keep** (projects made before this setting): exactly the virtual
  resolution, scaled to fit, with black bars where the shapes differ.

With Expand, scripts that place things at the screen's edges read the
frame's size each time (`Engine.get_virtual_size()` - it can change when the
window is resized or goes fullscreen) rather than assuming the virtual
resolution.

In the editor, the camera frame is the virtual resolution; with Expand, the
toolbar's screen-shape picker (16:9, 4:3, 21:9, phone...) outlines the
grown frame (dashed) and places edge-anchored Screen Layers on it.

## Recipes

**Classic crisp pixel art** (most games):

- Virtual Resolution `320 x 180` (or `640 x 360`), Sharp Pixels, Integer
  Scaling, Pixel Snap, Smooth Camera.
- On a 1920 x 1080 screen that's exactly 6x; on 1280 x 720, 4x; on
  1366 x 768, 4x with bars (1280 x 720 of picture).

**Pixel art that fills the screen**:

- Scaling **Fit**, Sharp Pixels, Pixel Snap, Smooth Camera: no bars; at
  3.125x every game pixel is 3.125 screen pixels wide, its edge column
  blended (sharp-bilinear) - crisp, and no 3-and-4 columns.

**Hi-res art** (painted, vector): leave all four off.

## Why each one matters

**Uneven pixels.** 320 pixels stretched to 1000 is 3.125x: a game pixel can't
be 3.125 screen pixels, so nearest-neighbour gives some columns 3 and some
4 - and as things move, the wide columns move through them. Integer
Scaling picks 3x (960 px) and puts 20 px bars on each side instead. Fit
with Sharp Pixels scales through a **sharp-bilinear** filter: each game
pixel is a flat square 3.125 screen pixels wide, and only the screen pixel
its edge falls in is blended with its neighbour - no uneven columns, no
blur. (Whole scales copy nearest-neighbour, as before.)

**Shimmering.** A sprite at x = 10.4 draws between two pixels; as it moves,
its texels fall on different screen pixels from frame to frame and the
sprite seems to wobble. Pixel Snap rounds where each sprite's top-left
corner lands (rotated sprites aren't snapped) and the camera's position -
on the pixels of what it draws into, so under a zoomed camera too. Tiles
(TileMap, LDtk levels), particles and text are snapped the same way.

**Scaled sprites.** A sprite scaled by a fraction (1.5x) has some texel
edges exactly on pixel centres; snapped draws move by 1/128 of a pixel so
the two triangles of the sprite round them the same way (before, its
columns could change from one row to the next).

**Choppy camera.** With the camera snapped too, a slow pan moves the whole
world one game pixel - 4 screen pixels at 4x - at a time. Smooth Camera
draws the world snapped into its own texture (one pixel larger on each
side) and shifts that texture by the leftover fraction when scaling it up:
at 4x the world can move one screen pixel at a time, while every sprite
still sits on the game's pixel grid. Layers the camera doesn't draw (the
UI, usually Layer 8) are drawn on top, not shifted.

**The followed node.** A node the camera follows is snapped to the game's
pixels like everything else, but the camera isn't - so it would drift
across its pixel and jump back, up to a game pixel every few frames. While
the camera follows a snapped node, the shift leaves out that node's own
rounding: it stays still on screen and the world steps a game pixel at a
time with it while the camera is locked on. Pans, the camera catching up
(smoothing), shake and zoom still glide. Set the followed node's **Snap to
Pixels** to Off (or follow an unsnapped parent) to have the world always
glide instead.

## Per-node settings

The Inspector's **Pixels** section, on every drawn node (Texture Sprite,
Atlas Sprite, Aseprite, Frame Animation, TileMap, LDtk Level, Particle
Emitter, Text, UI, vector shapes):

| Setting | Values | Default |
|---|---|---|
| **Texture Filter** | **Inherit** (each texture's import setting, in Assets), **Sharp** (nearest-neighbour), **Smooth** (bilinear) | Inherit |
| **Snap to Pixels** | **Inherit** (the project's Pixel Snap), **On**, **Off** | Inherit |
| **Text Pixels** (text and UI) | **Default**, **Native**, **Pixel** | Default: UI nodes Native, Text nodes Pixel |

Use them for a painted background in a pixel game (Smooth, Snap Off), a
pixel-art sprite in a hi-res game (Sharp, Snap On), or a node that should
move sub-pixel. A Texture Filter other than Inherit costs a flush of the
draw batch before and after the node.

## Native and Pixel text

Text drawn into a 320 x 180 frame is 320 x 180 text: scaled up 4x, a 10 px
font is blocky and soft. Text and UI nodes pick where they draw when the
frame is scaled up:

- **Native** (UI nodes by default: labels, buttons, sliders...): kept out
  of the frame and drawn after it is on the window, at the window's
  resolution, in the same place and scaled by the same amount - text from
  the font's distance field, sharp. World-layer ones move with the camera
  (and the smooth camera's shift). They draw over the whole frame, in their
  order among Native nodes - a Native node can't be behind a sprite.
- **Pixel** (Text nodes by default): drawn into the frame, in the game's
  pixels - right for pixel fonts and text that belongs to the art.

Native has no effect when the frame isn't scaled up (a virtual resolution
the size of the window), inside a Viewport's picture, during a scene
transition (its pictures are of the frame) and in the editor. UI that clips
its contents (list and tree views) stays Pixel by default: their clipping
doesn't follow the scale.

## Scripting

These are project settings, not script calls. Scripts that place things by
hand can keep positions whole themselves:

```lua
-- A damage number that floats up smoothly but draws on whole pixels.
function DamageNumber:update(dt)
    self.y = self.y - 20 * dt
    self.node.position = {math.floor(self.start_x + 0.5), math.floor(self.y + 0.5)}
end
```

## Saved as

```json
"window": {"virtual_width": 320, "virtual_height": 180, ...},
"video": {"sharp_scaling": true, "integer_scaling": true, "pixel_snap": true, "smooth_camera": true, ...}
```

`integer_scaling` false is Scaling **Fit**. A node's overrides are saved
only when set (absent: Inherit / Default), so older scenes load unchanged:

```json
{"type": "TextureNode", "name": "Backdrop", "texture_filter": "smooth", "pixel_snap": "off", ...}
{"type": "UILabelNode", "name": "Score", "text_pixels": "pixel", ...}
```

## Performance

- Integer Scaling and Pixel Snap cost nothing measurable (a rounding per
  sprite draw and per camera). Fit's sharp-bilinear filter is one shader
  on the final copy.
- Native nodes draw after the frame, grouped by transform (one batch flush
  per change of camera or layer).
- Smooth Camera draws the world into a second render texture (virtual size
  + 2 px) and composites two textures at the end instead of one - one extra
  full-screen textured quad. Post effects apply to the world texture (not
  the UI layers) in this mode.

## Notes

- The mouse still reads in game units (scaled and offset for the bars).
- Lighting's light map is composited inside the world texture, so it moves
  with the world.
- Pixel text is snapped (its origin and each glyph); use pixel fonts at
  their native size for crisp Pixel text, or Native for smooth fonts.
