# Vector art

Rayzr draws vector shapes - fills, outlines, curves - crisp at any zoom and
anti-aliased, for Flash-style characters, UI and procedural art. This is
Phase 14 of the roadmap ([TODO_NOW.md](../../TODO_NOW.md)); it is being built
in milestones:

| Milestone | What | Status |
|---|---|---|
| M0 | The renderer: tessellation, anti-aliasing, cached GPU meshes, the Vector Shape node with built-in shapes; proven in the game, the editor and the web | **done** |
| M1 | Shapes in full: fill rules and self-intersections (Clipper2), gradients, dashes, opacity, clip paths; drawing from Lua (`on_draw` + the `Vector` module) | **done** |
| M2 | Vector assets: SVG import (Inkscape, Illustrator, Affinity, Figma), assets shared and reloaded on save, the editor's workflow, picking, culling, background tessellation | **done** |
| M3 | Characters: symbols and instances, part swapping, lip-sync, timeline keys | **done** |
| M5 | Shape tweens and trim paths, filters and line scaling, vector skinning on skeletons and warps | **done** |
| M6 | Boolean path operations, carving, collision from shapes, path queries | **done** |
| M4 | Drawing tools in the editor | |
| M7 | Crisp text, Adobe Animate import, a sample character | |

## Vector art from SVG files

Draw in **Inkscape, Illustrator, Affinity Designer or Figma**, export an
SVG into the project (or drop it on the editor), and drag it from Assets
into the viewport: a Vector Shape draws it, centred on its position, crisp
at any zoom.

- **Saving reloads it**: keep the SVG open in your vector app; every save
  updates the editor and a running game. Double-click the asset (or the
  Inspector's edit button) to open it in the system's vector app.
- **One file, many nodes**: every node drawing a file shares its loaded
  document and its tessellated meshes - 100 copies cost one tessellation.
- **The Inspector's Vector section** shows the file, its size, how many
  shapes and groups it has, and anything the importer couldn't use.
- **Import settings** (Preview panel, saved in `<file>.import.json`):
  *Scale* (document units to pixels: 0.5 for art drawn at twice the size
  you need) and the *Origin* new Vector Shapes of the file get (centre, top
  left, bottom centre - each node's Origin row can still change it).
- **Picking** in the viewport follows the shape, not its box: clicking a
  hole or empty corner selects what's behind.

### What the importer reads

| | |
|---|---|
| Elements | `path` (every command, arcs too), `rect` (rounded), `circle`, `ellipse`, `line`, `polyline`, `polygon`, `g`, `use` / `symbol`, nested `svg` |
| Styles | presentation attributes, `style=""`, `<style>` blocks (tag, `.class` and `#id` selectors), inheritance |
| Paint | colours (hex, `rgb()`, `hsl()`, named), `none`, `currentColor`, linear and radial gradients (`gradientUnits`, `gradientTransform`, `spreadMethod`, stops inherited through `href`), opacity / fill-opacity / stroke-opacity |
| Strokes | width, joins, caps, miter limit, dash array and offset |
| Other | `fill-rule`, `clip-path` (on shapes and groups), transforms (`matrix`, `translate`, `scale`, `rotate`, `skewX`, `skewY`), units (px, pt, mm, cm, in, %), `display` / `visibility` |
| Groups | kept by name (Inkscape layer labels, Illustrator `data-name`, ids) for symbols and part swapping |

Not read (a warning each in the Inspector and the console): **text**
(convert it to outlines), embedded images, filters, masks, patterns,
markers, and a radial gradient's separate focal point.

### Exporting from your tool

| Tool | How |
|---|---|
| Inkscape | *Save As > Inkscape SVG* or *Plain SVG*; *Path > Object to Path* on text first. Layers become named groups. |
| Illustrator | *Export As > SVG*: Styling *Internal CSS* or *Presentation Attributes* (both read); Font *Convert to Outlines*; Images *Link* (they're skipped anyway). |
| Affinity Designer | *Export > SVG*: "Flatten transforms" off is fine; rasterise nothing; text as curves. |
| Figma | *Export > SVG* on a frame; "Outline text" on. Clip content (frames) is kept. |

## Drawing in the editor

Draw vector art without leaving Rayzr: select a Vector Shape and
**double-click** it in the viewport, or press **Edit Art** in the
Inspector. The rest of the scene dims and the Vector toolbar appears at
the top of the viewport. Every change is saved into the SVG straight away,
and **Ctrl+Z** undoes it. Press **Esc** or **Done** to finish.

| Tool | Key | What it does |
|---|---|---|
| **Select** | V | Click a shape to select it, and drag to move it. **Delete** removes it. |
| **Nodes** | A | Shows a shape's anchors and their Bézier handles. Drag an anchor to move it with its handles. Drag a handle to bend the curve: the opposite handle turns with it, or hold **Alt** to move just this one. **Double-click** a segment to add an anchor there without changing the shape. **Alt+click** an anchor to remove it. **Right-click** an anchor to make it **Smooth**, **Symmetric** or **Corner**. |
| **Pen** | P | Click to place a corner; click and drag to place a smooth anchor with its handles. Click the first anchor to close the shape, which then gets the fill colour. **Enter**, **Esc** or a double-click ends an open path. |
| **Rectangle** | R | Drag one out. **Shift** makes a square and **Alt** draws from the centre. The toolbar sets the corner radius. |
| **Ellipse** | O | Drag one out. **Shift** makes a circle and **Alt** draws from the centre. |
| **Polygon** | | Drag one out. The toolbar sets the number of sides. |
| **Star** | | Drag one out. The toolbar sets the number of points and the inner radius. |
| **Pencil** | Y | Draw a line freehand. When you let go it becomes a few smooth curves; the toolbar's **smooth** slider goes from 0 (every wiggle kept) to 100 (fewest, smoothest curves). |
| **Brush** | B | Paint a filled stroke in the fill colour. It gets thinner when you move fast and tapers at both ends, like Flash's brush. The toolbar sets its **size** and smoothing. |
| **Paint Bucket** | K | Click inside a filled shape to give it the fill colour. Click a gap that lines close in (crossing pencil strokes, an unfilled outline) to fill it with a new shape under the lines. Gaps that are still open don't fill. |

Shapes become ordinary paths: edit their corners with the node tool.

The toolbar's two colour swatches and the width field set the fill, line
colour and line width of new shapes.

- **Starting from nothing**: a Vector Shape with no file creates
  `art/<node name>.svg` the first time you click with the pen.
- **What's saved**: clean SVG that Inkscape, Illustrator and Affinity open
  again. It has your groups (symbols and swap frames) and gradients, with
  the file's transforms applied to the coordinates. The first save of a file
  keeps the original as `<file>.svg.bak`.
- **Files with parts Rayzr can't draw** (text, images, filters; see the
  Inspector's warnings): **Edit Art** asks first. **Edit a Copy** writes
  `<name>_edit.svg` and points the node at it, so the original stays as it
  was. **Overwrite** edits the file itself, dropping those parts.
- Drawing into a symbol (a Vector Shape that shows one group) adds the new
  shapes to that group.

## Characters: symbols, part swapping and lip-sync

Build a character the way Flash animators did: draw it in layers (or
groups) in your vector app, then animate the layers as parts.

### Symbols

Every named group of an SVG - an Inkscape layer (its label), an
Illustrator or Affinity layer or group (its name), any `<g id="...">` - is a
**symbol**: a Vector Shape's **Symbol** (`group`) draws only that group.
Nested groups are named by path, `head/mouth`; a bare name finds the group
anywhere. One file can hold a whole character, or a sheet of props.

- **Instances**: any number of nodes can draw the same symbol, each with
  its own transform, **tint** (multiply), **brightness** (-1 black ... 1
  white) and **colour offset** (`colorAdd`: added to every colour - a hit
  flash). The meshes are shared: one tessellation per symbol per zoom.
- **Editing the symbol updates every instance**: save the SVG.
- **A symbol with its own timeline** is a component: make a component
  (prefab) of a node tree drawing parts, give it an Animation Player, and
  instance it - each instance plays (or holds) its own animation.

### Explode into Parts

The Inspector's **Explode into Parts** replaces a Vector Shape with a Node
in its place (same name, transform and children) holding a Vector Shape
per child group - the layers of a whole file, or the groups inside a
symbol - each with its pivot at the part's centre, where it was drawn.
Move, rotate and key the parts; reparent them to build a hierarchy (the arm
under the body). Shapes that sit outside any child group are left out (a
warning says how many): group them in the vector app. Undo puts the
original back.

### Part swapping

A symbol whose child groups are alternatives - mouth shapes, hands, eyes
open / closed - shows one at a time with **Frame**: the child group's
index (-1 shows them all). The Inspector lists the frames by name. The
box the node's origin sits in is the symbol's (all frames together), so
swapping never makes the part jump.

```lua
local mouth = self.node:get_node("Mouth")
mouth:vector_swap("O")              -- by name; false when there's none
print(#mouth:vector_frames())       -- the frame names, in order
mouth.frame = 2                     -- by index
```

On the animation timeline, `frame` is an ordinary property: key it and
the keys **hold** until the next one (new `frame` keys use the Constant
ease), so swaps step instead of tweening. Brightness, colour offset, tint,
position, rotation, scale and draw order (`zIndex`) key and tween with the
usual eases and curves; hold keys and "on twos" are Constant keys.

### Lip-sync

A **Lip Sync** node moves a mouth with a voice. Run the recording through
[Rhubarb Lip Sync](https://github.com/DanielSWolf/rhubarb-lip-sync) (free,
MIT) and save its output (TSV, or JSON with `-f json`) beside the sound
with the same name (`hello.wav` -> `hello.tsv` / `hello.json`), or point
**cues** at it.

- **mouth**: the mouth's path from the Lip Sync node (default `../Mouth`) -
  a Vector Shape whose symbol's child groups are the mouth shapes.
- Name the shapes after Rhubarb's: `A` (M B P), `B` (most consonants),
  `C` (E), `D` (A), `E` (O), `F` (U W), and optionally `G` (F V), `H` (L),
  `X` (rest). Missing ones fall back as Rhubarb's do (G -> B, H -> C,
  X -> A). Other names (a Preston Blair chart): **mapping**
  `A=MBP,B=etc,C=E,D=AI,E=O,F=U,X=rest`.
- **sound** + **autoplay**, or from Lua `node:lipsync_play("voice/hello.wav")`,
  `lipsync_stop()`, `lipsync_is_playing()`; `finished` fires at the end and
  the mouth rests.
- **Dialogue**: set a Dialogue node's **lipSync** to the Lip Sync node's
  path and every line with a voice moves the mouth, timed by the voice's
  playback position (no drift); closing or skipping the line rests it.

## Path effects: shape tweens and trim paths

### Shape tweens

Flash's shape tweens: a Vector Shape drawing a group morphs into another
group of the same file. Pick it in the Inspector's **Morph to** (or set
`morphTo`), then key **morph** from 0 (the group) to 1 (the target) on the
timeline, or tween it from Lua:

```lua
local blob = self.node:get_node("Blob")
blob.morphTo = "star"
Tween.to(blob, "morph", 1, 0.6, "in_out_sine")
```

- Shapes pair up in order (the first shape of one with the first of the
  other); extra shapes shrink to their centres and fade out (or grow and
  fade in).
- Paths are compared as curves: missing segments are made by splitting the
  longest ones, closed outlines are turned the same way and started at the
  closest points (an automatic shape hint), so a circle becomes a star
  without twisting.
- Colours, outline widths, opacity and gradients blend - a solid colour into
  a gradient too; a missing fill or outline fades in.
- Morphing tessellates the node's own copy whenever the value changes
  (0.2-1 ms for a detailed part): fine for a few at a time; hold it at 0 or 1
  and it costs nothing extra.

For the best results draw both shapes with the same number of points, in
the same order, from the same starting corner.

### Trim paths

**trimStart** / **trimEnd** (0..1 of each path's length) draw part of every
path, and **trimOffset** moves that part along, wrapping round - keyed, they
draw lines on, make progress rings and running dashes. Paths are trimmed one
after another (the whole drawing as one line); **trimEach** trims every
subpath on its own (both circles of a ring at once). Filled shapes fill
what's left of their outline. It works on presets too.

```lua
-- Draw a signature on over a second.
local sig = self.node:get_node("Signature")
sig.trimEnd = 0
Tween.to(sig, "trim_end", 1, 1.0)
```

## Filters and line scaling

### Filters

Flash's per-instance filters, set on any Vector Shape in the Inspector (or
from Lua, or keyed on the timeline):

| Filter | Properties |
|---|---|
| Drop shadow | **shadowColor** (alpha 0: off), **shadowOffset**, **shadowBlur** |
| Glow | **glowColor** (alpha 0: off), **glowSize**, **glowStrength** |
| Outline | **outlineColor** (alpha 0: off), **outlineWidth** - one line round the whole drawing (cel-shading, a selected character) |
| Blur | **blur** - the art itself |
| Colour | **saturation** (0 grey, 1 as drawn), **contrast**, **hue** (degrees) |

Sizes are screen pixels. They combine: shadow, glow and outline are drawn
behind the art, the colour filter applies to the art.

```lua
-- Highlight the character under the mouse; grey it out when it's dead.
local hero = self.node:get_node("Hero")
hero.glow_color = "#ffd23f"
hero.glowSize = 12
hero.saturation = 0
```

How it works (`engine/vector_filters.odin`): a filtered shape is drawn at
screen resolution into a texture with room round it, blurred / tinted /
adjusted by shader passes into the node's own texture, and that is drawn as
one quad (rotated and flipped with the node). The texture is remade only
when something it shows changes - the art, the zoom, the node's scale, a
filter setting or the colour effects - so an idle filtered character costs
one textured quad, and moving or rotating it costs nothing extra. Animating
a filter value or the scale remakes the texture each frame (a few shader
passes: fine for a handful of characters). Textures are at most 2048 px a
side (bigger art gets a coarser texture).

### Line scaling

**lineScale** is Flash's line scaling: *Scale* (the default) thickens
outlines as the node grows; *Constant* keeps their width whatever the node's
scale - a character scaled up 2x keeps 4 px outlines. Constant re-tessellates
the node's own copy when its scale changes by more than a percent.

## Bending with bones: vector skinning

Put a Vector Shape under a [Skeleton](skeletal_animation.md) and it can
**bend with the skeleton's bones** - a sleeve that curves round the elbow
instead of two rigid pieces meeting at a joint, a tail that swishes, a
belly that squashes.

1. Rig the bones in Spine (or DragonBones) and export the `.json` - **bones
   only is fine**: no images, no atlas. Draw the art in your vector app.
2. Add a **Skeleton** with that file, and a **Vector Shape** with the SVG
   as its child. Place the art over the bones as they stand in the setup
   pose (the skeleton's rest pose - clear its Animation to see it).
3. In the Inspector's Vector section, **Bend with**: pick the bones
   (*All bones*, or tick the ones this part follows).
4. **Skin Smooth** sets how far round each joint (px) neighbouring bones
   blend: 0 makes rigid parts (each point follows its nearest bone), 30-60
   bends a limb round a soft elbow.

Then anything that moves the bones moves the art: the skeleton's
animations and crossfades, **IK** constraints, and scripts
(`skeleton_set_bone_rotation` to aim an arm).

```lua
-- A tentacle that follows the mouse with IK, skinned smoothly.
local rig = self.node:get_node("Tentacle")   -- a Skeleton
local art = rig:get_node("Art")              -- its Vector Shape
art.skinBones = "*"
art.skinSmooth = 50
```

How it works (`engine/vector_skin.odin`): the art is bound once, in the
skeleton's setup pose - every vertex of its tessellated mesh gets up to
four bones, weighted by its distance to each bone (from its joint to its
tip); long triangles are split first so bends have vertices to bend at.
The weights ride in the mesh; each frame only the bones' matrices go to
the GPU and the vector shader blends them per vertex - posing never
re-tessellates or re-uploads. 100 skinned limbs animating cost 1.3 ms a
frame (`scenes/bench_skin.scene.json`). It's re-bound when the bones, the
smoothing, the part's place on the skeleton or its tessellation (a new
zoom) change. Up to 64 bones per Vector Shape.

### Squash and stretch: the four-corner warp

Any Vector Shape (with a skeleton or not) can be warped by moving its four
corners: **warpTopLeft**, **warpTopRight**, **warpBottomLeft**,
**warpBottomRight** (px). The art stretches between them, like a free-form
deformer: key them for a squash on landing, a lean, a taper. The warp
happens in the vertex shader too (on the shared mesh: no copy).

```lua
-- Squash on landing and spring back.
local body = self.node:get_node("Body")
body.warpTopLeft = Vec2(-20, 30)
body.warpTopRight = Vec2(20, 30)
Tween.to(body, "warp_top_left", Vec2(0, 0), 0.25, "out_back")
Tween.to(body, "warp_top_right", Vec2(0, 0), 0.25, "out_back")
```

## Collision from the art

Give a Vector Shape a **Collider** and the art is solid: physics bodies
hit exactly what's drawn (fills and outlines, holes left open).

| Collider | What it makes | Use it for |
|---|---|---|
| **Solid** | convex pieces (at most 8 corners each) | anything: crates, props, characters - dynamic bodies too |
| **Outline** | edge loops round the outline (Box2D chains) | terrain and walls: bodies slide along it without catching on seams |

- **Where it goes**: on the nearest Static Body, Dynamic Body or Area above
  the Vector Shape (its collision events, mass and layers are that body's),
  or on a static body of its own when there's none - so a Vector Shape on
  its own is already ground. Under an Area it becomes a sensor.
- **Collider Detail** (its units) is how closely it follows the art:
  bigger means fewer corners and faster physics. **Collider Friction**,
  **Bounce** and **Density** set the material.
- It's remade when the art changes - a new file, a frame, a morph, a cut -
  not every frame; moving the node only moves the body.
- With the physics debug view on (Project Settings > Physics, or
  `Physics.set_debug_draw(true)`) the pieces / loops are drawn over the art,
  in the editor too.

```
Crate (Dynamic Body)
└── Art (Vector Shape: crate.svg, Collider Solid)   -- the crate's shape is its drawing
```

### Carving: destructible art

`vector_cut` removes a circle, `vector_cut_polygon` any shape, from the
art - each shape keeps its paint (a gradient fill stays a gradient, a
stroke stays its colour) - and the collider follows on the next frame:
worms-style terrain, bites out of a cookie, bullet holes.

```lua
-- A bomb blows a crater where it lands.
function Bomb:on_collision_started(other)
    local ground = Scene.find_node("Terrain")
    ground:vector_cut(self.node.position, 48)
    self.node:destroy()
end
```

`vector_reset()` brings the art back. Each cut re-tessellates the node's own
copy of its shapes (curves become short lines where cut).

### Path queries

The art's paths, one after another, can be measured like a Path:
`vector_length()`, `vector_point_at(d)` (a point and direction),
`vector_closest(pos)` and `vector_contains(pos)`. A **Path Follow** under a
Vector Shape rides its outline - draw a race track or a patrol route in
your vector app.

```lua
-- Move along an SVG path at 120 px/s.
function Car:update(dt)
    self.d = (self.d or 0) + 120 * dt
    local pos, dir = self.track:vector_point_at(self.d % self.track:vector_length())
    self.node.position = pos
    self.node.rotation = math.deg(math.atan(dir.y, dir.x))
end
```

### Path operations (from Odin)

`engine/vector_ops.odin`: boolean union / subtract / intersect / exclude
of shapes or polygons (`Vector_ShapesBoolean`, `Vector_PolysBoolean`),
offsets (grow / shrink), outline stroke to fill (`Vector_StrokeOutline`),
simplify, flatten, the covered area of a drawing (`Vector_ShapesArea`:
fill rules, strokes, clip paths), cutting a drawing (`Vector_ShapesCut`),
convex decomposition - all on Clipper2, also in the web build. The Boolean
buttons in the editor come with M4's drawing tools.

## Using it with presets

A Vector Shape without a file draws its **Preset**: a star, a ring (a shape
with a hole), a badge, a detailed cartoon character, or a gradients and
dashes sampler. **Fill Color**, **Stroke Color** and **Stroke Width**
style it; **Tint** multiplies everything (fade it with the alpha). Scale it,
rotate it, zoom the camera in: it stays sharp.

```lua
-- A star that pulses: only its transform changes, so it costs nothing to redraw.
local Pulse = {}

function Pulse:ready()
    self.t = 0
end

function Pulse:update(dt)
    self.t = self.t + dt
    local s = 1 + 0.1 * math.sin(self.t * 4)
    self.node.scale = Vec2(s, s)
end

return Pulse
```

## Drawing from Lua

A script that defines `on_draw()` draws with the `Vector` module in its
node's local space, in the node's draw order - see the
[scripting guide](../SCRIPTING.md#10-vector-module-vector) for every function.

```lua
-- A clock face with a gradient, ticks and a hand that follows a property.
local Clock = {}
Clock.properties = { hour = { type = "float", default = 3 } }

function Clock:on_draw()
    Vector.begin_path()
    Vector.circle(0, 0, 60)
    Vector.fill_paint(Vector.radial_gradient(-20, -20, 90, { {0, "#ffffff"}, {1, "#b0bec5"} }))
    Vector.fill()
    for i = 0, 11 do
        Vector.save()
        Vector.rotate(i * 30)
        Vector.begin_path()
        Vector.move_to(0, -52); Vector.line_to(0, -44)
        Vector.stroke_width(3)
        Vector.stroke()
        Vector.restore()
    end
    Vector.save()
    Vector.rotate(self.hour * 30)
    Vector.begin_path()
    Vector.move_to(0, 6); Vector.line_to(0, -36)
    Vector.line_cap("round")
    Vector.stroke_width(5)
    Vector.stroke()
    Vector.restore()
end

return Clock
```

The drawing is tessellated once and reused while it stays the same (the
engine hashes what was drawn); changing `hour` re-tessellates it on the next
frame.

## Paints, dashes and clips

- **Gradients**: linear (two points) and radial (centre, radius), up to 16
  colour stops, spread *pad*, *reflect* or *repeat*, and a gradient
  transform (Flash's gradient transform tool, SVG's `gradientTransform`).
  They are computed per pixel by the vector shader - smooth on huge shapes,
  still one draw call per mesh.
- **Dashes**: on / off lengths and an offset; each dash gets the stroke's
  joins, caps and anti-aliasing.
- **Opacity**: per shape, on top of the colours' alpha.
- **Fill rules**: non-zero and even-odd, exact for self-intersecting and
  overlapping outlines (Clipper2 normalizes them; single convex outlines
  skip it).
- **Clip paths**: a shape (fill and stroke) cut to a region with its own fill
  rule - `Vector.clip()` from Lua.

## How it works

1. **Paths** (`engine/vector_path.odin`): move, line, quadratic and cubic
   curves, close. Shapes are a path plus a style (fill colour and rule;
   stroke colour, width, joins, caps, miter limit).
2. **Flattening**: curves become line segments within a quarter of a screen
   pixel (Wang's formula picks the segment count).
3. **Tessellation** (`engine/vector_tess.odin`): fills are normalized by
   the fill rule with Clipper2 (`engine/clipper`: self-intersections,
   overlaps, holes) and triangulated with earcut (`engine/vector_earcut.odin`);
   strokes become strips with miter / round / bevel joins and butt / round /
   square caps; clipped shapes go through Clipper2's intersection.
4. **Anti-aliasing without MSAA**: every edge gets a one-pixel strip that
   fades to transparent (fills are inset half a pixel so they keep their
   size); strokes thinner than a pixel are drawn a pixel wide and fainter.
5. **Caching** (`engine/vector_mesh.odin`): the mesh is made for a *scale
   bucket* - the screen-pixel size rounded to a power of two. Moving,
   rotating and scaling within the bucket only changes the transform;
   zooming past it re-tessellates, so curves stay smooth at 10x and meshes
   stay small when zoomed out.
6. **Drawing**: the mesh is uploaded once as vertex buffers and drawn with a
   matrix (one draw call per 65535 vertices). It goes through raylib, so it
   works in the game, the editor's viewport, render textures, post effects
   and the web (WebGL 2).

## Performance (M0 measurements)

On an Apple M-series Mac, optimized build:

| | |
|---|---|
| Tessellating the benchmark character (198 shapes, ~300 curves) | 0.16 ms (zoomed out) to 0.57 ms (zoomed in 4x); 6,000-16,000 triangles |
| 100 of those characters spinning, cached GPU meshes | **1.7 ms per frame** (~580 fps) |
| 100 nodes drawing four imported SVGs (25 each), spinning | **0.86 ms per frame** (~1160 fps): each file tessellated once, shared |
| The same, sent through raylib's batch every frame | 56 ms per frame (18 fps) - why meshes are cached on the GPU |

`RAYZR_VECTOR_MODE=immediate` switches to the batch path (for comparison).

**Zooming**: an asset keeps up to three scale buckets cached. A new zoom
draws the nearest one (slightly soft for a frame or two) while a worker
thread tessellates the new bucket, so zooming across dozens of different
characters doesn't hitch; the web build tessellates at once (no threads).
Repeated copies share one GPU mesh (one draw call each) rather than
hardware instancing - fast enough for hundreds per frame.
The benchmark: `tests/vector/project`, scene `scenes/bench.scene.json`
(`runner tests/vector/project --scene scenes/bench.scene.json --bench 300`).

## Tests

- `engine/vector_test.odin`: flattening accuracy, earcut (areas, holes,
  concave and degenerate input, the hashed path for big polygons), fill
  coverage (a ring's hole stays empty), strokes (width, joins, caps,
  hairlines), the cache's buckets, the node; leak-checked.
- `tests/vector/runtime_tests.json`: the runner renders the test scenes and
  the screenshots are compared with `tests/vector/expected/` (both drawing
  paths, a 6x zoom, gradients / dashes / opacity, Lua drawing with a clip),
  and the benchmark scene runs.
- `engine/vector_svg_test.odin`: the SVG importer (path grammar, arcs,
  colours, transforms, units, CSS, gradients, clips, groups, warnings) on
  fixtures shaped like Inkscape / Illustrator / Affinity / Figma exports
  (`tests/vector/svg`), assets (sharing, reloads, bounds, hit tests),
  import settings, background tessellation, symbols and part swapping
  (paths, frames, the stable box, colour effects), lip-sync (TSV / JSON
  cues, mappings and fallbacks, a Lip Sync node and a Dialogue line moving
  a mouth), held `frame` keys.
- `tests/drive/vector_shape.drive`: the editor - Add Node, editing the
  preset and stroke, the viewport zoomed in, saving.
- `tests/drive/vector_svg.drive`: SVG assets - thumbnails, dropping into
  the viewport and onto a Vector Shape (undo), warnings, a reload on save,
  saving the scene.
- `engine/vector_morph_test.odin`: trim lengths (mid-segment cuts, offsets
  wrapping, subpaths in turn or each), morphs (ends, alignment of reversed
  outlines, missing subpaths), style blends (gradients, solid to gradient,
  strokes fading in), the node rebuilding only when values change.
- `tests/drive/vector_fx.drive`: the Morph to picker, morph and trim edits,
  undo, saving.
- `scenes/fx.scene.json` (golden): a circle-to-star strip, trimmed
  squiggles (offset wrapping), presets drawn on, a gradient morph.
- `test_vector_line_scale_filters` (`engine/vector_morph_test.odin`):
  constant line width (rebuilt only when the scale changes), filters
  switching on, nothing prepared without a window.
- `engine/vector_skin_test.odin`: weights (rigid and smooth joints, the
  nearest bones), the pose's matrices matching the bones, binding through
  the node's place on the skeleton, re-binding only when needed, picking
  the bent art, the warp; leak-checked.
- `tests/drive/vector_skin.drive`: a bones-only rig in the Skeleton's file
  list, the Bend with picker (bones toggled, all bones, undo), saving.
- `scenes/skin.scene.json` (golden, both drawing paths): a limb at rest,
  bent rigid and smooth, flipped and rotated; warps.
- `engine/vector_ops_test.odin`: booleans, offsets (mitred / round),
  stroke outlines (caps, dashes, closed), fill rules, clip paths,
  simplifying, flattening, cutting with paints kept, convex pieces, the
  measured polylines; collision - a ball on Solid and Outline ground, a crate
  shaped by its art on its Dynamic Body, a Lua crater it falls into, a
  ring's pieces round its hole, re-made only when needed, path queries and
  a Path Follow on the outline, the Lua methods.
- `tests/drive/vector_collider.drive`: the Collider setting and overlay,
  detail, undo, saving, a ball landing in Simulate.
- `scenes/collide.scene.json` (golden): carved hills, a star, a crate,
  balls settling, a rider on a ring.
- `tests/drive/vector_filters.drive`: saturation, blur and hue edited in
  the Inspector and drawn in the viewport, undo, saving.
- `scenes/filters.scene.json` (golden): each filter alone, a flipped
  rotated instance with two filters, constant vs scaled line width, all
  filters combined.
- `tests/drive/vector_symbols.drive`: the Symbol and Frame pickers (undo),
  Explode into Parts and its undo.
- `scenes/symbols.scene.json` (golden): symbols alone, brightness, a
  colour offset, swaps from Lua, a mouth's nine frames.
- `scripts/web/test_project.sh tests/vector/project out.png`: the same scene
  in the web runner (headless Chrome).

## Limits (until the next milestones)

- Stroke ends with butt caps have no anti-aliasing fringe on the end edge.
- A clip inside a clip replaces it (no intersection of nested clips yet);
  no soft (alpha) masks yet.
- Filters apply to one Vector Shape: an exploded character's parts each get
  their own (a shadow per part, not one for the whole character). Bent
  (skinned or warped) art skips its filters.
- Skinning binds by distance to the bones (no painted weights yet); outlines
  bend with the art, so a strongly bent stroke gets a little thinner on the
  inside of the bend.
- Radial gradients have no separate focal point yet (Flash's focal ratio,
  SVG's fx / fy).
- The immediate drawing path (`RAYZR_VECTOR_MODE=immediate`) evaluates
  gradients per vertex (an approximation); the default GPU path is exact.
- SVG text, images, filters, masks, patterns and markers aren't imported
  (see above); group opacity is applied to each shape (overlapping shapes
  in a half-transparent group show through each other).
- The Paint Bucket doesn't close small gaps between lines yet (Flash's gap
  size); snapping and layers in the drawing tools come next (#267).
- Hidden layers (`display:none`) aren't imported, so keep swap frames
  visible in the file; a whole-file instance draws every frame at once
  (explode it, or pick the symbol).
