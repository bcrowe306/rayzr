# Rayzr - Game Editor

A standalone GUI game engine editor built in Odin with **Dear ImGui** (docking branch) and **Raylib**.

---

## 1. Architecture Overview

The editor is organized as an independent package (`editor/`) that imports and manipulates the core engine (`engine/`) as a library:

- **Standalone Package**: Resides in `editor/` with independent state, assets, and bindings.
- **Dear ImGui Docking**: Full multi-window dockspace via `imgui.DockSpaceOverViewport` and docking layout persistence (`imgui.ini`).
- **Embedded Raylib Viewport**: Raylib offscreen rendering via `rl.RenderTexture2D` embedded into Dear ImGui via `imgui.Image` with inverted UVs (`{0, 1}` to `{1, 0}`).
- **Two-Way Data Serialization**: Projects and scenes load from and serialize to portable JSON (`.scene.json`, `.project.json`) and portable binary packages (`.rayzr`).
- **Live Scripting Integration**: Automatic reflection of Lua script properties on nodes with interactive editing.

---

## 2. Editor Layout

This file is the overview; the editor manual has a page per part of the
editor - what it is for, when to use it, every control, a screenshot and a
short walkthrough. The [editor tour](../docs/editor/tour.md) maps the window. In the
editor, **F1** opens the page of the panel with focus, **Help > Help for
<panel>** the last one's, a bottom tab's right-click menu its **Help**, and
**Help > Editor Manual** the list (`editor/panel_help.odin`).

| Area | Pages |
|---|---|
| The main window | [Toolbar and menus](../docs/editor/toolbar-menus.md), [Scene tree](../docs/editor/scene-tree.md), [Inspector](../docs/editor/inspector.md), [Viewport](../docs/editor/viewport.md), [Vector edit mode](../docs/editor/vector-edit.md), [Assets](../docs/editor/assets.md), [Settings](../docs/editor/settings.md), [Playtesting](../docs/editor/playtesting.md) |
| The root tabs | [Code tab](../docs/editor/code.md) (full reference: [CODE_EDITOR.md](CODE_EDITOR.md)), [Level tab](../docs/editor/level.md) |
| Bottom tabs | [Console](../docs/editor/tab-console.md), [Profiler](../docs/editor/tab-profiler.md), [Game](../docs/editor/tab-game.md), [Animation](../docs/editor/tab-animation.md), [Particles](../docs/editor/tab-particles.md), [LDtk](../docs/editor/tab-ldtk.md), [Tile Map](../docs/editor/tab-tilemap.md), [State Machine](../docs/editor/tab-stategraph.md), [Behavior Tree](../docs/editor/tab-behaviortree.md), [GOAP](../docs/editor/tab-goap.md), [Mixer](../docs/editor/tab-mixer.md), [Library](../docs/editor/tab-library.md), [Search](../docs/editor/tab-search.md), [Files](../docs/editor/tab-files.md), [Tests](../docs/editor/tab-tests.md) |
| Tool windows | [Level Generator](../docs/editor/level-generator.md), [Terrain Tiles](../docs/editor/terrain-tiles.md), [Tile Animation](../docs/editor/tile-animation.md), [Sprite Sheet Slicer](../docs/editor/sprite-slicer.md), [Atlas Region Editor](../docs/editor/atlas-region.md), [Generate Normal Map](../docs/editor/normal-map.md) |

The rest of this file covers features across the editor; where a page
covers a part in full, its section here only links it.

---

## 3. Tools & Shortcuts

Every command lives in one action table (`actions.odin`) that drives the
keyboard, the menus, the **command palette** (Cmd+Shift+P) and
**Help > Keyboard Shortcuts** (Cmd+Shift+K), so any shortcut shown is the one
that works. On macOS "Cmd" is the Command key; elsewhere it is Ctrl.

| Shortcut | Action |
| :--- | :--- |
| **Cmd+Shift+P** | Command palette (any action, fuzzy search, recent first) |
| **F1** | The editor manual's page for the panel with focus |
| **Cmd+P** | Go to file (scenes, scripts, components, assets; `>` for commands, `:` for a line) |
| **Q / W / E / R / T** | Select / Move / Rotate / Scale / Pan tool (gizmos work in world space and snap to the grid) |
| **Middle mouse / wheel** | Pan / zoom around the cursor (Cmd+= / Cmd+- / Cmd+0 too) |
| **F / Shift+F** | Centre the view on the selection / fit it (zoom too) |
| **Alt + drag the move handle** | Move the pivot (what the node shows stays in place) |
| **Cmd+L / Cmd+Shift+H** | Lock in viewport / hide in editor |
| **Cmd+Shift+R** | Rulers & guides (drag from a ruler to add a guide) |
| **Cmd+A** | Add Node (under the selected node) |
| **Cmd/Shift+click, drag a box** | Multi-select (tree and viewport); the gizmo moves the whole selection |
| **Cmd+C / X / V, Cmd+D, Del** | Copy / cut / paste / duplicate / delete the selection |
| **Arrows (Shift: grid step)** | Nudge the selection |
| **F2** | Rename the selected node |
| **Cmd+Shift+A, Esc** | Select all / deselect |
| **Edit > Align** | Align edges or centres, distribute |
| **Cmd+Z / Cmd+Shift+Z** | Undo / redo (every edit) |
| **Cmd+S / Cmd+Shift+S / Cmd+Alt+S** | Save scene / Save As... / save all scenes and scripts |
| **Cmd+N** | New scene (added to the project) |
| **F5 / F6 / F7 / Shift+F5** | Play project / play the current scene / simulate in editor / stop |
| **F9 / Shift+F9 / Cmd+Shift+F5** | Pause or resume the game / step one frame / restart it |
| **Cmd+1 / Cmd+2 / Cmd+J** | Focus Viewport / Code / Console |
| **Cmd+Q** | Quit (asks about unsaved scenes and scripts) |

Scene tree: drag a node onto another to re-parent it (onto empty space = root), onto the top / bottom edge of a row to place it before / after; right-click for actions (Copy / Move to Scene puts the selection into another scene at the same world position - pasting into another scene does that too). Renaming or moving a node keeps scripts pointing at it: node-reference properties update, and `self.node:get_node("...")` paths, `self.node:get_child("...")` and `Scene.find_node("...")` that pointed at it are offered for update (open scripts are edited in place - one undo - others on disk). Rows mark nodes with a script (the blue script icon beside the eye: hover for its file, click to open it), locked and hidden-in-editor ones.
Filter the tree by name, `#tag` or `t:type` (`t:sprite`, `type:CameraNode`); terms combine.
Tags (groups) are edited in the Inspector's **Tags** section (type one and press Enter, or pick one used in the scene; click a tag to remove it); scripts use `has_tag` / `Scene.find_by_tag`, and the generated Lua types list the project's tags (`NodeTag`).
Assets: drag textures, audio, components or scripts into the viewport.

### Welcome and new projects

*Page: [toolbar-menus](../docs/editor/toolbar-menus.md).*

The **Welcome** window opens at startup (untick *Show at startup* to stop
it; **Help > Welcome** brings it back): recent projects, **Open
Project...**, a few first steps, and **New Project** from a template:

| Template | |
|---|---|
| **Empty** | A scene with a camera |
| **Menu** | A title screen whose Play button opens the game scene |
| **Platformer** | Run, jump (coyote time, jump buffer), coins, spikes, an enemy to stomp, a door; parallax, a HUD |
| **Top-down RPG** | Eight-way movement, a sword, slimes, a wizard with dialogue, a chest, a key, a locked door; hearts |
| **Shoot 'em up** | Waves of enemies, pooled bullets, explosions, lives, a saved best score |
| **Puzzle (Sokoban)** | Levels typed as text, undo, restart, a move counter |

The game templates are small, complete games with pixel art (Kenney, CC0)
and a README saying what's where and what to change first. **Samples** are
bigger projects to explore: *Platformer Adventure* (title screen, two
levels, saved progress, a pause menu) and *Asteroids* (the demo). The
templates are built by `scripts/templates/make_templates.py` and played by
`scripts/templates/test_templates.py` (CI). Every node type has its own icon
(Add Node, scene tree, Inspector), and empty places say what to do (an empty
scene in the tree and viewport, the console).

### Workspaces

*Page: [toolbar-menus](../docs/editor/toolbar-menus.md).*

The bottom panel (Console, Game, Animation, ...) starts 100 px tall in
the Default layout - drag its edge, or pick a workspace with a taller one.
**View > Workspaces** switches the panel layout: **Default**, **Level
Design** (a larger viewport), **Scripting** (the Code tab in the middle,
in front), **Animation** (a tall bottom panel on the Animation tab) - or a
layout of your own: arrange the panels, **Save Workspace As...**, and pick
it from the same menu later (saved in `~/.config/rayzr_editor/workspaces/`;
**Delete Workspace** removes one). **Reset Layout** returns to Default.

The bottom panel **follows the selection**: selecting an AnimationPlayer
shows the Animation tab, a particle emitter Particles, an LDtk level LDtk;
selecting something else goes back to the tab you had (a tab you pick by
hand stays). Turn it off in Settings > General > Basic (**Bottom Panel
Follows Selection**; `auto_bottom_panel` in settings.ini).

**View > Bottom Panel** lists the bottom panel's tabs with a check by the
ones shown: click one to hide or show it (saved for you in settings.ini,
`hidden_bottom_tabs`; at least one stays). A hidden tab comes back when the
selection or a command needs it (an AnimationPlayer selected, Find in
Files).

A docked window alone in its space hides its tab (the panels have their own
headers), so after closing a window docked next to another, the one left
loses its tab. **View > Show Tab Bars** gives every docked window its tab
(to see what is docked where, drag a window out or re-dock it); turn it off
for the clean look again. Saved in settings.ini (`show_tab_bars`).

### File menu

See [Toolbar and menus](../docs/editor/toolbar-menus.md#file-menu).

### Settings (Cmd+,)

Every tab and setting: [Settings](../docs/editor/settings.md).

### Inspector

*Page: [inspector](../docs/editor/inspector.md).*

**Node / Properties**: a node's Inspector has two tabs. **Node** is its own
settings (Transform, its type's properties, Script, Signals...).
**Properties** is yours - its script's properties, set per node: **Add
Property** opens a dialog with every option (name, type - number, integer,
boolean, text, resource, node, choice, range, vector, colour, assets, list,
curve, gradient -, default, min / max / slider, label, help, group, a list's
element type, a resource's class picked from the project's resource classes
and its copies), previews the Lua line and writes it into the script's
`properties` table. A node without a script gets one made for it. Right-click
a property's name: **Edit Property** (the same dialog; a rename moves each
node's value, and nodes still at the old default take the new one) or
**Remove Property** (it shows the script lines that use `self.<name>` and the
nodes with a value; undo brings it back). The script is shared: the dialog
says how many nodes use it.

**Origin** (Transform, for nodes that draw an image or a box: textures,
animations, AnimationPlayers, nine-slices, text): the point of the image
that sits at the node's position and that it rotates and scales around - a
fraction of its size, so **0.5, 0.5** is the centre (the default and what
the reset button restores), **0, 0** the top-left, **0.5, 1** the bottom
centre. **Presets** sets a corner, an edge's middle or the centre; Alt-drag
in the viewport moves it while the image stays. Scripts:
`node:set_property("origin", 0.5, 1)`. Scenes saved before keep their look
(older AnimationPlayers stay drawn from their top-left, `origin: 0, 0`).

**Draw order** (Transform): **Layer**, **Z Index** (within the layer,
added to the parent's: higher on top), **Y Sort Children** (draw the
children by Y - top-down / isometric depth) and, under a Y-sorted parent,
**Y Sort Offset** (the line it sorts by, drawn dashed in the viewport while
selected). Viewport clicks pick what is drawn on top. Guide:
[`engine/docs/draw_order.md`](../engine/docs/draw_order.md).

X/Y fields have a link toggle (linked: changing one scales the other by
the same ratio). Every field has a reset button when its value differs from
the default (the node type's default, a script property's declared default).
Particle emitters open the **Particles** tab (bottom panel): Emission, Shape,
Motion, Size & Rotation, Color (gradient over the particle's life with
draggable stops, plus a red/green/blue/alpha plot whose alpha points you
drag) and Collision. Every particle emitter runs in the viewport while you
edit (not only in Simulate), so a changed setting shows at once; the tab's
play / pause button pauses or resumes that preview for all emitters, and
Restart starts the emission over.

With several nodes selected, the Inspector shows the primary one under a
"N nodes selected" banner and only the properties they all have; values
that differ show **—**, and an edit (or reset) applies to every selected
node - for X/Y pairs only the axis you changed, so differing positions keep
their other coordinate. Enable / visible toggles apply to all; the other
sections (script, material, signals) edit the primary node.

Hover any property (its label or field) for help: a tooltip with what it
does, its type, range and default, and its script path. The **help pane**
at the bottom of the Inspector keeps the last hovered property's help, or
describes the selected node type; its `path = "..."` line is what
`get_property` / `set_property` take (the copy button copies it) - a
script's exported properties are `script.<name>`. **View > Inspector Help**
hides it.

**Drag a node from the Scene tree into a script** to insert a reference to
it, typed for the language server (its class, so its own methods
complete). On an empty line it becomes a declaration:

```lua
---@type CharacterMoverNode
local player = self.node:get_node("../Player")
```

Dropped onto a method's line (`function Enemy:on_hit(...)`) it offers the
node's events instead: the one you pick is connected in `ready()` (made if
missing) to call that method -
`<node>:connect("body_entered", function(other, source) self:on_hit(other, source) end)`.
Dropped into an assignment (`self.body = `) the `---@type` line goes above
it; anywhere else (an argument) it gets an inline cast,
`self.node:get_node("../Player") --[[@as CharacterMoverNode]]`. Plain
`Node`s get no annotation.

**Drag project names into a script**: an input action from the chips in
the Preview panel's Script tab inserts `Input.is_action_pressed("jump")`
(Shift: `is_action_down`); the hand next to the Animation tab's picker
inserts `<player>:animation_play("walk")`; an event from the Inspector's
**Signals** section inserts `<node>:connect("timeout", function(value,
source) ... end)` with the cursor in the handler; an asset dropped with **Alt**
inserts code that uses it - a sound `Audio.play_sound(...)`, a scene
`Scene.change_scene(...)`, a texture `self.node:set_texture(...)` (plain:
its path; Cmd: an exported property).

**Cmd+click a node path** in a script - the string in `self.node:get_node("...")`,
`get_child("...")` or `Scene.find_node("...")` - to select that node (and
centre the view on it); Cmd+click anything else goes to its definition. A
script tab's right-click menu has **Find Usages of This Script** (the
scenes and components that use it).

**Drag a property's name into a script** (the Code tab) to insert a read:
`self.node:get_property("rotation")`. Hold **Shift** when dropping for a
write with the current value: `self.node:set_property("rotation", 45)`.
The node is `self.node` when it runs that script, `self.node:get_node(
"<relative path>")` for another node of the scene (or `Scene.find_node`). The help text lives in
`engine/property_docs.odin` (`test_property_docs` fails when a property has
none).

### Context menus

Every asset, folder, scene-tree node, code tab, the code text and console
lines have a right-click menu with all their actions — for nodes: add child
or component, cut/copy/paste/paste as child, duplicate, rename, delete, move
up/down/to root, select children, enable/show, frame, script actions and
component actions; for assets: open/add/use on the selection, copy/paste,
duplicate, rename, delete, copy path, reveal; for scripts also **Make
Global** / **Remove Global** (a global script shows a globe and its global
name in Assets). LDtk projects (`.ldtk`) are
listed under **Levels** (double-click or drag to add a level).

### Asset folders, grid and usages

*Page: [assets](../docs/editor/assets.md).*

**Browsing**: with the Assets panel focused, the arrow keys select the next
or previous asset (Up / Down; Left / Right too in the grid; Shift extends).
The Preview panel follows: with **Autoplay** a sound plays, and an Aseprite
file or an animated GIF plays in its Animation tab (each frame's own time).
Autoplay, Loop and the volume are the File Browser's too.

The buttons left of **+** switch Assets between the by-type sections and the
project's real **folders** (a tree, the project folder at the top), and
between a list and a **grid** of thumbnails. In the folders view, drag an
asset or folder onto a folder to move it; right-click a folder for **New
Folder**, **Rename**, **Find Usages**, **Delete** (with what it contains)
and **Paste Here**. Moving or renaming updates every reference - in scenes
and components (also the ones open with unsaved edits, and their undo
history), scripts and `project.json` (startup scene, scene list, icon,
import settings); open scripts that move are reopened. **Find Usages** (on
any asset's menu) lists the files that reference it; double-click one to
open it.

**Import settings** are in the preview panel. Textures: **Filter** (Point
keeps pixel art crisp; Bilinear / Trilinear smooth scaled images), **Wrap**
(Repeat / Clamp), **Mipmaps**, **Export** (Keep, or QOI for faster loading),
**Atlas** (packed into a sprite atlas on export - see
[`engine/docs/atlas.md`](../engine/docs/atlas.md))
and the slicing preset (saved from the Sprite Sheet Slicer's **Save
Preset**). Audio: **Gain** and the default **Bus**. They're saved next to
the asset (`hero.png.import.json` - hidden in Assets, moved and copied
with it) and applied at once in the editor and when the game loads the
asset. Guide: [`engine/docs/import_settings.md`](../engine/docs/import_settings.md).

### Importing assets

*Page: [assets](../docs/editor/assets.md).*

The **+** at the top right of Assets imports with the system file dialog
(**Import Assets...**, multi-select, or **Import Folder...**) and creates
scenes and scripts; each folder's right-click menu has an Import item
filtered to its file types. Files and folders dragged in from Finder /
Explorer import too — onto the viewport, they are also added to the scene
where they land.

Each file goes to the folder for its type — `textures/` (png, jpg, bmp,
tga), `audio/` (wav, ogg, mp3), `scripts/` (lua), `scenes/`,
`components/`, `levels/` (ldtk) — and a folder keeps its layout below that
(`Pack/Effects/spark.png` -> `textures/Pack/Effects/spark.png`). Contents
are checked (images must decode, audio must have a WAV/Ogg/MP3 header,
JSON must parse), so an unsupported or broken file fails on its own and the
rest still import; failures are listed in the **Import Results** window and
the console. A file already in the project (same contents) is skipped; a
different file with a taken name is imported as `name_2.ext`. An LDtk
project brings its external levels and the tileset/background images it
references (into `textures/`, with the paths in the level rewritten).
Fonts (ttf, otf, fnt) are copied to `fonts/` as they are. To look at files
before importing them, use the **File Browser**.

### File Browser

See [Files tab](../docs/editor/tab-files.md).

### Level Generator

See [Level Generator](../docs/editor/level-generator.md) (the window) and [`engine/docs/level_generator.md`](../engine/docs/level_generator.md) (the nodes).

### Scene tabs

*Page: [viewport](../docs/editor/viewport.md).*

Every scene you open (from Assets, the palette, Edit Component, ...) gets a
tab above the viewport; component documents show a cubes icon.

| | |
|---|---|
| Click a tab | Switch to it. Each tab keeps its own camera, selection and undo history. |
| Drag a tab | Reorder. The arrow at the left lists every tab. |
| Dot on a tab | Unsaved changes (the tooltip shows the file). |
| **x**, middle-click, **Cmd+W** | Close it - with unsaved changes it asks: **Save**, **Don't Save**, **Cancel**. Closing unloads the scene (and frees its undo history); opening it again loads the file. The last tab can't be closed. |
| **Cmd+Alt+Right / Left**, **Ctrl+PageDown / PageUp**, **Ctrl+Tab** | Next / previous tab. |
| Right-click a tab | Close, Close Others (ones with unsaved changes stay), Copy Path. |

Switching is off while simulating. The open tabs and the active one are
remembered per project (`.rayzr/open_scenes.json`) and come back when you
open it again.

### Viewport

Navigation, tools, gizmos, overlays, drops and the context menu: [Viewport](../docs/editor/viewport.md); drawing vector art: [Vector edit mode](../docs/editor/vector-edit.md).

### Signals

The Inspector's **Signals** section and the Scene panel's Signals view: [Inspector](../docs/editor/inspector.md), [Scene tree](../docs/editor/scene-tree.md).

### Sprite Sheet Slicer

*Page: [sprite-slicer](../docs/editor/sprite-slicer.md).*

**Tools > Sprite Sheet Slicer...** (also a texture's right-click menu and the
AnimationPlayer Inspector) cuts a sheet into cells. **Slice by** *Cell
Grid*: **Columns** / **Rows** share the sheet (the cell size follows, maybe
fractional); *Cell Size*: cells exactly that many whole pixels, as many as
fit (the columns and rows follow; leftover pixels at the right and bottom
are unused - padding, a short last row, a credit strip). **Margin** and
**Spacing** apply to both. Click cells to pick them
(drag across to add several, Shift+click for a range; the numbers are the
play order), name the animation and **Add Animation**, or **One Animation
per Row**. **Create Animation Player** adds a new node with the animations
at the chosen FPS - or **Add to <name>** when an AnimationPlayer is
selected. The selection previews as it plays. Animations keep the picked
cells (`"cells"` in the scene; margin / spacing editable in the Inspector).
Zoom the sheet with **-** / **+**, the zoom field, **Fit** (the whole sheet,
the default) or **1:1**, or Cmd+wheel (Ctrl+wheel) around the mouse; the
wheel scrolls (Shift: sideways) and middle-drag pans when zoomed in.

### Animation timeline

*Page: [tab-animation](../docs/editor/tab-animation.md).*

The bottom panel's **Animation** tab edits the selected AnimationPlayer's
animations; the Inspector shows only the player's own settings - Current,
**Default** (`defaultAnimation`), **FPS** (`fps`), Preview, Reverse,
Autoplay - with their script paths. Next to the animation picker: **+** adds
an empty animation, its **▾** makes one from a folder of frames or a sprite
sheet (or opens the slicer), the **pen** renames
it (names are unique; the default animation and the states of a State
Machine driving this player follow the new name), **Duplicate** copies it
(frames, range, settings and tracks) right after itself as `<name>_copy`,
and the **trash** deletes it (Cmd+Z brings it back).

A negative **scale** mirrors what the player draws (and a TextureNode or
FrameAnimationNode) around its **origin**, in the game and the viewport,
whose selection box follows: with the origin at the centre a character
flips in place.

**Frames**: the strip shows every frame of the animation; the ones it plays
(its **range**) are under the blue band in the header - drag the band's
handles, type **from / to** under the Frames label, or right-click a frame:
*Start / End the Range Here*; frames outside it are dimmed. Click frames to
select them (Shift: a run, Cmd: add / remove), then **Copy**, **Paste**
(after the selection, else at the end) or **Delete** with the buttons left
of the header, the right-click menu, or Cmd+C / Cmd+V / Delete while the
panel has focus (they act on frames there, not on scene nodes). Images
paste into frame animations, sprite-sheet cells into animations of the same
sheet. Drag frames to reorder; drop textures on **+** to add some. The
toolbar: **Loop**, **Reverse** (this animation plays last to first; the
player's own Reverse flips them all), the animation's **FPS** (the rate it plays at -
the player's, dimmed, until you change it; right-click goes back to the
player's, set in the Inspector) and the **star**: the animation selected -
when the scene loads (also the Inspector's **Default**); it plays then
with the Inspector's **Autoplay**.
At the right of the timeline (when the panel is wide enough) a **preview**
plays the animation by itself - its range, FPS and direction, looping;
pause it to see the frame the timeline is on. Then play/stop preview in the
viewport (Stop puts the scene back), and
keyframed **property tracks**: **Add Track** picks the player or a child and
a property (position, rotation, scale, colours, any numeric property); the
yellow dot keys the current value at the playhead; right-click a key to
delete it. Tracks are grouped under their node's row (click it to fold
them; folded, its keys show as dots).
**Keys**: click a key to select it (Shift / Cmd: add or remove), or drag a
box from an empty spot; drag the selection along the timeline (keys snap to
frames; hold Shift to place them anywhere; a key dropped on another
replaces it). Cmd+C / Cmd+V paste the copied keys at the playhead (onto
their own tracks, or the selected track when they came from one), Cmd+D
duplicates them one frame after the last, Delete removes them (also the
buttons left of the header). Keys are timed in seconds: the toolbar shows
the playhead's time, the **clock** at the ruler switches it between frames
and seconds, and Cmd / Ctrl + wheel (or the wheel over the ruler) zooms -
the **%** button resets it. Drag the ruler to move the playhead.
**Key inspector**: while keys are selected, the right of the timeline edits
them - the (first) key's **Frame** and **Time** (the others keep their
spacing), the **Value** with the property's own widget (number, vector,
colour, checkbox, an enum's names, a texture picker for a sprite's
texture), the **Easing** to the next key (or **bezier**: handles, edited
below it as time / value offsets per component). Several keys get the same
value or easing.
**Keys from the Inspector**: select another node (a child, the parent) and
the tab keeps the player (a **pin** chip shows it; click it to select the
player, **×** to stop). A **diamond** at the end of each animatable
property's name in the Inspector keys its current value at the playhead
(hollow: no track yet, outlined: a track, filled: a key here); right-click
it for the previous / next key or to remove the key. **Auto-key** (the red
dot by Stop) keys every change you make to the selected nodes - typed in
the Inspector or dragged in the viewport - at the playhead; scrubbing,
playback and undo don't record.
**Graph**: the **chart** button at the ruler swaps the track rows for the
value graph (like After Effects' value graph): each number, vector and
colour track's curve over the same frames and playhead - vectors and
colours split into components (click one in the list to hide or show it).
Keys are points: drag one in time (snapped to frames; Shift: free) and
value. Bezier keys show their handles (right-click a key: **Bezier
Handles**, **Flatten Handles**, **Linear**, **Delete Key**); drag a handle
to shape the curve - the pair stays in line, Alt breaks it. The wheel moves
the values up and down, Alt + wheel zooms them, **Frame All** (F) fits them.
**Event tracks** say what each key does next to it on the timeline ("emit
12", "stop", "spawn Explosion", "disable", `on_hit(3)`, a sound's name).
**Add Track > Events > Emit Particles** lists the scene's particle emitters
(pick one); its keys **Restart** the emitter, **Emit a burst** of N
particles, **Start** or **Stop** it. The **sliders** button on a particles,
spawn or enable track (or clicking one of its keys) opens its settings at
the right: the target (particles: the scene's emitters only) and every key
with its frame (click to go there), what it does, and delete.
Right-click a key for its **Easing** to the next key (linear, sine, quad,
cubic, quart, expo, back, elastic, bounce, constant; hover one to see its
curve) or to delete it. Eased keys show a dot. Scripts can animate any
property at runtime with `Tween.to` (see `engine/SCRIPTING.md`).
**Add Track > Events** adds a **Call Script Methods** track (the key's
method runs on the target's script on that frame; type the name in the key
field) or a **Play Sounds** track (pick an audio file per key). Event keys
are drawn as squares (methods) or circles (sounds); hover one for its method or sound. Scripts
crossfade between animations with `node:animation_play(name, blend)`.

Polishing (guide: [`engine/docs/animation_editing.md`](../engine/docs/animation_editing.md)):
right-click a key > **Edit Curve...** draws your own curve to the next key
(drag two handles, or a preset: Ease In / Out / In Out, Back Out,
Anticipate, Snap); the row shows the curves between keys. A method key can
pass an **argument** and pick its method from the target script's list; the
player also emits `animation_event`. The **onion skin** button (right-click
for frames before / after and opacity) ghosts the neighbouring frames in the
viewport.

### State machines

*Page: [tab-stategraph](../docs/editor/tab-stategraph.md).*

Guide with tutorials: [`engine/docs/state_machine.md`](../engine/docs/state_machine.md).

Add a **State Machine** (Animation & Effects) next to an AnimationPlayer
and edit it in the **State Machine tab** (bottom panel; it follows a
selected State Machine). The Inspector shows only a summary and **Edit in
State Machine Tab**. The tab has three sub-tabs:

**Graph** - states as boxes (a flag marks the initial one, a film its
animation, otherwise *gameplay*; a child machine is named), the **Any
state** box, arrows labelled with their conditions (`speed > 10`, `jump!`
for a trigger, `sees_player()`, `a | b` for or-groups). **Manual** arrows
(only a script's `sm_transition` takes them - the default for new arrows)
are drawn dashed, **Automatic** ones (taken when their conditions hold)
solid; a two-way pair curves apart.

- Right-click empty space: **Add State** (a gameplay state) or **Add State
  for Animation**; right-click a state: Set as Initial, Break on Enter,
  **Add Script Callbacks** (writes `on_enter_` / `on_update_` / `on_exit_`
  into the machine's or its parent's script), **Add Guard Callbacks**
  (`can_exit_<state>(next)` / `can_enter_<state>(previous)` returning
  true), Delete. Every state in the project is also in the generated types
  (`.rayzr/definitions/project_types.lua`), so typing
  `function Cls:on_update_` completes the state names.
- Drag a box to move it (positions are saved); drag a box's **dot** onto
  another box for an arrow; Delete removes the selection. The wheel (or the
  middle button) pans, Shift+wheel sideways, **Cmd/Ctrl+wheel zooms**, F
  frames everything.
- The **side panel** edits the selection: a state's name, animation or
  none, **child machine**, Initial, **Allow Retrigger** (it may go to
  itself), Break on Enter, its **guards** - **Leave After** (seconds before
  it can be left), **Any State Interrupts** (off: Any-state arrows don't
  fire while in it), **Can leave when** / **Can enter when** (condition
  rows; empty = any time) - and its script callbacks; an arrow's from / to,
  **Mode** (Manual / Automatic), blend and conditions (including *script
  says* and *or*). A guarded state shows a **lock**.
- **Live**: in Simulate *and* while the game plays (Play: the running
  game's machine, polled over the editor link) the current state is lit
  (with a bar for its time), the arrow that fired flashes, and the side
  panel lists **Ways out** (each arrow out of the current state - *fires*,
  *waiting for speed > 10*, *manual: a script calls sm_transition(...)*,
  or *blocked: attack: leave after 0.4s (0.12s so far)*; a selected arrow
  marks each condition green / red), the **history** of changes and the
  **pending triggers**.
- **Break on Enter** (a state's menu or side panel; a red dot): entering
  that state pauses Simulate, or the running game (its toolbar shows
  Paused; Resume / Step as usual). Kept by the editor (not saved in the
  scene) and sent to every game Play starts.

**Parameters & Triggers** - typed parameters (bool / int / float) with
their starting values, and triggers (one-shot events, separate from
parameters) with an optional **buffer** time; live values and pending
triggers while running.

**Settings** - the **Animation Player** (Auto finds a sibling or child),
**Initial State** and **Autostart**.

Scripts: `sm_set`, `sm_trigger`, `sm_transition(state [, {force = true}])`,
`on_enter_<state>` / `on_update_<state>` / `on_exit_<state>` (see the
guide and `engine/SCRIPTING.md`).

### Materials & shaders

Every drawable node has a **Material** section (collapsed until used): a
shader - built-in Flash, Outline, Dissolve, Grayscale, Wave, or a project
`.fs` file - a blend mode (alpha, additive, multiply, ...) and the shader's
parameters, generated from its `uniform`s (sliders, colour pickers, texture
pickers; the reset arrow returns one to the shader's default). **New
Shader...** (here or Assets **+**) writes a documented template; drop a
shader from Assets on a node to apply it; saving a shader reloads it in the
viewport. Lua: `node:set_shader`, `set_shader_param`, `set_blend_mode`.

### Lighting

Add a **Light** (point or spot cone; colour, energy, radius, falloff,
shadows) and darken the scene with **Ambient** - in the Scene panel's
**Settings** tab (presets: Dusk, Night, Dark). Lights
cast shadows from physics shapes. The toolbar's sun toggles the lighting
preview in the viewport; selected lights show their radius or cone.

### Save data

Scripts persist progress with the `Save` module (`Save.set`, `Save.get`,
`Save.flush`; see `engine/SCRIPTING.md`), stored as JSON in the platform
user-data folder under the project's name. **Game > Save Data > Open
Folder** shows it; **Delete Save Files** removes them so the next run
starts fresh.

### Text & dialogue

**Text** (Graphics & Rendering) places text in the scene: pick a project
font in the **Font** section (`.ttf`, `.otf`, `.fnt`; none = the engine
font), size, colour, wrapping width, alignment, rich text, localization
key, SDF and typewriter speed. **Dialogue Box** (UI) is a box scripts fill
with lines (`dialogue_show`). Localization tables are `locale/*.csv`; the
starting language is set in Project Settings > General.

### Visual extras

**Nine Slice Sprite**, **Parallax Background**, **Line** and **Post Effect**
(Graphics & Rendering) and **Trail** (Animation & Effects) nodes. A Line's
points are edited in the Inspector's **Points** section (**Add Point**, the
x removes one). Post effects show in the viewport while the lighting
preview (toolbar) is on; pick the shader in the **Material** section.

### Navigation

**Navigation Region** (Add Node > Physics & Collision): a rectangle baked
into cells - selected, the viewport shows the blocked ones red; **Bake** in
the Inspector rebuilds them. **Navigation Agent** under a character walks
it to targets; in Simulate its path is drawn green. Guide:
[`engine/docs/navigation.md`](../engine/docs/navigation.md).

### Skeletons (Spine, DragonBones)

**Skeleton** (Add Node > Animation & Effects): pick a Spine `.json` (with
its .atlas) or a DragonBones `_ske.json` in the Inspector, then the
animation and skin; **Preview** plays / scrubs it in the viewport. The
**Bones** list highlights a bone on hover; its link button adds a **Bone
Attachment** that follows it. Guide:
[`engine/docs/skeletal_animation.md`](../engine/docs/skeletal_animation.md).

### Accessibility

**Project Settings > Project > Accessibility**: the players' defaults (UI
scale, colour filter, subtitles, captions, subtitle size / backdrop, screen
shake). **View > Colour Vision** previews the viewport as players with
protanopia, deuteranopia or tritanopia see it. The **Accessibility Menu**
script template (on a UI Container) builds an in-game options menu. Sound
and Music nodes have a **Caption**; Dialogue nodes a **Mode** (Box or
Subtitles). Guide: [`engine/docs/accessibility.md`](../engine/docs/accessibility.md).

### Advanced cameras

**Advanced Camera** (Add Node > Core & 2D): a virtual camera. The viewport
draws each one's frame (violet - where it would look now, at its zoom,
with its priority); selected, its dead zone and limits (pink). The
Inspector's **Targets** section picks the follow target, group members,
path and limit node (or drop a node from the Scene panel). In Simulate,
**Make Active** and **Shake** try it out. Guide:
[`engine/docs/advanced_camera.md`](../engine/docs/advanced_camera.md).

### Mixer

The bus console: [Mixer tab](../docs/editor/tab-mixer.md); guide:
[`engine/docs/audio_mixer.md`](../engine/docs/audio_mixer.md).

A Sound Effect or Music node's **Audio** section in the Inspector has a
**Preview** button: Play / Stop hears its sound through its bus at its
volume and pitch (not positioned), without changing the node; it stops when
you select something else.
A Sound Effect holds a **list of sounds** (Add Sound, or drop audio from
Assets; drag a row's number to reorder) and a **Play Mode** (Single, All,
Sequential, Sequential Reversed, Random by weight, Shuffle), with random
volume / pitch / pan / delay per play and a cooldown - see
[`engine/docs/audio_mixer.md`](../engine/docs/audio_mixer.md); the Preview
plays by them.

### Controls menus (player rebinding)

New Script on a **UI Container** offers the **Controls Menu (rebinding)**
template: a row per input action with its key, click to rebind (saved for
the player), Reset to defaults. Menus also work with a gamepad (D-pad /
stick moves the focus, A presses). Guide:
[`engine/docs/input_rebinding.md`](../engine/docs/input_rebinding.md).

### Paths

Select a **Path**: drag its points (squares) and Bézier handles (dots; Alt
moves one alone), double-click the curve to add a point, Alt+click to
remove one, Ctrl/Cmd+click to add at the end. The Inspector lists the
points with a sharp / smooth toggle. **Path Follow** children preview at
their **Progress** while editing and travel in Simulate / Play. Guide:
[`engine/docs/paths.md`](../engine/docs/paths.md).

### Profiler: pools

See [Profiler tab](../docs/editor/tab-profiler.md).

### Visibility notifiers

**Add Node > Visibility Notifier** under a node: a yellow rectangle in the
viewport (brighter in Simulate while the game camera sees it) with
**Size**, **Margin** and an **Action** on the parent off screen (pause,
disable, remove). Events `screen_entered` / `screen_exited` in the Signals
panel. Guide: [`engine/docs/visibility.md`](../engine/docs/visibility.md).

### Physics: joints, one-way, layers

Add a **Joint** (Physics & Collision) and pick **Body A** / **Body B** in
the Inspector (static, dynamic or character bodies; A defaults to the
parent); choose its **Type** - only that type's parameters are shown. The
viewport draws a line between the anchors. A StaticBody's **One Way** makes
a jump-through platform. **Project Settings > Physics > Collision Layers**
names the 16 layers; shapes' layer lists show the names.

### Camera follow

Select a Camera and pick its **Follow Target** in the Inspector (or drop a
node from the Scene panel on the field, or right-click any node: *Camera
Follows This*). It is saved with the scene as a path relative to the camera
(`"follow": "../Player"`), so the game follows that node with no script -
including a node that only appears later (e.g. spawned from an LDtk level).
The camera's own offset, smoothing, look-ahead, margins and limits apply.
Lua: `Camera.set_target(node)`, and for groups `Camera.add_target(node,
{weight, radius})` / `remove_target` / `clear_targets`.

### Collision shapes

Physics bodies (Static, Dynamic, Area, CharacterMover) list their shapes in
the Inspector (**Collision Shapes**: type, size, material, filtering).
**Edit Shapes** - the button at the top left of the viewport, or *Edit in
Viewport* in the Inspector - replaces the transform gizmo with handles on
the selected body's shapes:

- the centre moves a shape, the orange knob rotates it;
- box edges and corners resize it (the opposite side stays put; **Shift**
  resizes around the centre); circles and capsules have radius / length handles;
- polygon, chain and segment points drag; click a **+** between two points
  to add one, right-click a point to remove it. Polygons must be convex:
  a non-convex one turns red (it collides as its outline).

Grid snapping applies (rotation snaps to 15°); every drag is one undo step;
**Esc** leaves shape editing (a second Esc deselects). Changing a shape's
type keeps its footprint. Shapes are in the node's local units: they scale
with the node (and its parents), like everything else drawn by it.

### Tile maps

See [Tile Map tab](../docs/editor/tab-tilemap.md), [Terrain Tiles](../docs/editor/terrain-tiles.md) and [Tile Animation](../docs/editor/tile-animation.md).

### LDtk levels

See [LDtk tab](../docs/editor/tab-ldtk.md) and [Level tab](../docs/editor/level.md).

### Playtesting

*Page: [playtesting](../docs/editor/playtesting.md).*

Play always runs what is in the editor. It saves every modified scene, rebuilds the game
binary (`bin/rayzr`) if any engine/game source changed, then starts the game with
`--project <dir>` (plus `--scene <file>` for F6). The game's output streams into the
Console. **Game → Simulate in Editor** runs the scene inside the editor and restores it when stopped.
The **Lua** line under the Console evaluates Lua there - in the simulation, or in the running
game - showing an expression's value (`Scene.find_node("PlayerShip").position`) or running a
statement (`GameState.score = 100`); Up / Down recall earlier lines. Breakpoints: click a line
number; right-click it for a condition (amber marker); the Game tab's debugger shows the call
stack, locals and a **Watch** column evaluated at every stop.

While the game runs, the toolbar's play controls become **Pause** /
**Resume** (F9), **Step** one frame (Shift+F9; pauses first), **Restart**
(Cmd+Shift+F5: stops and plays the same thing again - the project, the same
scene, or the same exported package - saving and rebuilding first like
Play) and **Stop** (Shift+F5); next to them the game's state - Running,
Paused or Breakpoint (the status bar shows it too). While the game is
building, Stop cancels the build. The same commands are in the **Game**
menu; Restart there also replays the last run after it was stopped. The
**Show Colliders** button next to them (also Game > Show Colliders in Game)
switches whether the game draws collision shapes, joints and areas - the
project setting, saved in project.json, and at once in a running game.

**Debugging Lua**: click a line number in the Code tab to set a breakpoint
(a red dot; click again to remove it) and Play. When a script reaches it,
the game pauses there: the script opens at the line (marked), and the Game
tab shows the call stack (click a frame for its locals) and the locals -
tables one level deep, nodes as `Type(Name)`. **Continue** (F8), **Step
Over** (F10), **Step Into** (F11), **Step Out** (Shift+F11). Breakpoints can
be added or removed while the game runs. (Debugging works in the game
started with Play, not in Simulate in Editor.)

While the game runs, the editor is linked to it (`--editor-link`).

**Remote view.** The Scene panel gets a **Local / Remote** switch:
**Remote** shows the running game's scene tree (refreshed twice a second;
re-read only when it changed) - filter it, toggle a node's **enabled** (power)
and **visible** (eye), right-click for **Apply to Scene**, **Remove from
Game**, **Copy Path**. The crosshair button **picks**: click a node in the
game window and it is selected here. The selected node is outlined (amber)
in the game. The Inspector shows its live properties with the usual
widgets - drag numbers and vectors, tick check boxes, pick colours and enum
values (double-click a number to type it) - each change goes to the game at
once; its script's exported values too (`script.speed`). **Apply to Scene**
copies the node's current values (transform and properties, not script
values) into the edited scene's node with the same path - undoable - to
keep what you tuned while playing. **Local** goes back to the edited scene;
stopping the game does too.

The bottom panel's **Game** tab shows the same tree and properties side by
side, with **Pause** / **Resume** / **Step** (one frame of 1/60 s; paused,
the game is still drawn). Saving a scene while the game runs reloads it
there (the current scene restarts with the saved version); edited scripts
and images reload by themselves, in the game and in the editor.

### Aseprite files

`.aseprite` / `.ase` files are assets as they are: an *Aseprite* section in
Assets (first-frame thumbnails); drag one into the viewport for an *Aseprite
Sprite* playing its first tag; the Inspector's Aseprite section picks the tag,
previews it, toggles layers, picks a pivot slice and opens the file in
Aseprite (Settings > General > Aseprite: the program). Saving in Aseprite
updates the editor at once. A TileMap can take its map from a tilemap layer.
Details: [engine/docs/aseprite.md](../engine/docs/aseprite.md).

### Crash and bug reports

If the editor crashes, the next start shows **Rayzr Editor Crashed** with the
report (reason, stack, the last log lines and actions): **Report on GitHub**
opens a prefilled issue in the browser (nothing is sent until you submit it),
or Copy / Open Folder / Dismiss. **Help > Report a Bug...** opens a new issue
with the version, platform and console tail; **Help > Open Crash Reports
Folder**. A game crashing during Play prints its report's path in the
Console. Details: [engine/docs/crash_reports.md](../engine/docs/crash_reports.md).

### Code tab (Lua scripts)

*Page: [code](../docs/editor/code.md).*

**Full reference: [`CODE_EDITOR.md`](CODE_EDITOR.md)** - every editing
feature and shortcut of the Code tab.

Drag a script from Assets onto a scene-tree row to attach it (replacing the node's script; the
row is outlined while you hover). Scripts open in a **Code** tab next to the Viewport: double-click a script in Assets, use the
edit button beside a node's script in the Inspector, *Open Script* in the scene tree's context
menu, or double-click a console message with `file.lua:LINE`. *New Script* (Inspector, scene
tree, the **+** on the Scripts folder, the command palette) opens a dialog: the file name and a
template - Empty, Platformer or Top-Down Character, Enemy Patrol, UI Menu, Pickup, Door /
Trigger - with a preview; templates made for the node's type are starred and picked first.
**F1** on an API name opens the **Scripting Reference** window (also Help > Scripting Reference):
`engine/SCRIPTING.md` by section with search, rendered as markdown (headings, **bold**, `code`,
code blocks, lists, tables - `markdown_view.odin` on libcmark; Lua code blocks and inline code
syntax-highlighted in the Code tab's colours), the function's signature,
description, example and parameters in a card on top. The window has its own background,
border and shadow. Snippets: `ready`, `update`, `connect`, `properties`, `tween`, `on`, `method` + **Tab** expand
(placeholders follow with Tab; see `engine/SCRIPTING.md`). Completion, signature help, hover,
diagnostics and go to definition (F12 / Ctrl-click) come from `lua-language-server` with the
engine API definitions (`engine/definitions`). Hover docs, signature help and the selected
completion's docs show in boxes that stay inside the Code area, wrap, and scroll with the
mouse wheel when long (move the mouse onto a hover box to scroll it). **Ctrl/Cmd+S** saves and hot-reloads the
script in a running Simulate session; Ctrl+Space completes; Ctrl/Cmd+/ comments; Ctrl/Cmd+W
closes the tab. Zed-style editing: auto-closing brackets and quotes,
find/replace (Cmd+F / Cmd+Alt+F, Cmd+G), multi-cursor (Cmd+D, Cmd+Shift+L,
Cmd+Alt+Up/Down, Alt+click), line operations (Opt+Up/Down, Cmd+Shift+D/K,
Cmd+Enter, Cmd+/, Cmd+]/[), go to line (Ctrl+G), rename (F2), format
(Cmd+Shift+I), references (Shift+F12) and snippet tab stops. Drag an asset
onto the code to insert its path, or hold Cmd to add it as an exported asset
property. Text editing uses the `odin_editor` packages (`buffer`, `syntax`, `lsp`); see
`code_editor.odin` and `code_editor_lsp.odin`.

**Lua tooling files.** The editor writes the engine API definitions to
`<project>/.rayzr/definitions/` (compiled into the editor, refreshed when it
updates) and a `.luarc.json` pointing at them, so lua-language-server - in
the Code tab or in VS Code / any LuaLS editor opening the project folder -
knows every engine type. A hand-written `.luarc.json` is left alone. Hidden
files and folders (`.rayzr/`, `.luarc.json`, ...) are never packaged into
games. The language server is looked up next to the editor, then in the
engine checkout (or set its path in Settings > Code Editor).

**Project types.** Next to the engine API the editor generates
`.rayzr/definitions/project_types.lua` from the project: `InputAction` (the
input actions - a misspelled action is an error and names complete inside
the quotes), `SceneName`, `NodeName`, `ScenePath`/`TexturePath`/`AudioPath`/
`ComponentPath`/`LevelPath`/`ScriptPath`, LDtk entity/level/layer/enum names,
and a class per script with its exported properties (`self.orbit_radius` is
a number). It is rewritten half a second after saves, imports, renames and
settings changes, and the language server is told.


**File > Export Standalone Game** (or Project Settings > Export > **Save and
Export**) writes, for each target platform, `<output>/<platform>/` with the
game runner renamed to the executable name, `game.rayzr` and the UI font: a
folder you can ship.

**Web**: a preset (or target) with platform **web** exports a static site
- the prebuilt web runner (`runners/web/`: index.html, index.js,
index.wasm, odin.js), `game.rayzr`, the font and the icon as favicon, the
page titled with the window title. **File > Export > Open Web Export in
Browser** serves it on `http://127.0.0.1:8765/` and opens it. Building the
web runner (once, with emscripten): `scripts/build_web_runner.sh`. Guide:
[`engine/docs/web_export.md`](../engine/docs/web_export.md).

**Export presets** (Project Settings > Export > **Use Presets**) give each
export its own settings: platform, executable name, output folder (default
`<output>/<preset name>`), version, icon, window title / size, fullscreen,
**Include** / **Exclude** file patterns (one per line: `audio/` a folder,
`*.psd` a file name anywhere, `levels/*.ldtk` a path), and **Debug** (the
debug runner: debug info, a console on Windows). Add several per platform
(a demo, a debug build); **Save and Export This Preset** exports one, **Save
and Export All** every preset. The packaged `project.json` carries the
preset's overrides. Presets are saved in `project.json` under
`"export": {"presets": [...]}`. The runner is **prebuilt** - no compiler is needed to
export: runners are looked up in `runners/<platform>/` next to the editor
(or `bin/runners/` in a source checkout). `scripts/build_runners.sh` builds
the current platform's; run it on each platform you ship for and copy its
`runners/<platform>/` folder next to the editor. The Export page shows which
runners are ready; without one for this platform the editor builds it once
(needs `odin`). The project's **Icon** (Project > General, a PNG) becomes
the game window's icon.

**macOS** exports are an app bundle, `<output>/macos/<Name>.app`:
`Info.plist` (name, version, bundle ID - Export > macOS Bundle ID, default
`com.rayzr.<name>`), the runner in `Contents/MacOS`, its libraries (Lua) in
`Contents/Frameworks`, and `game.rayzr`, the font and `AppIcon.icns` (made
from the project icon) in `Contents/Resources`. The app is signed with
`codesign` - ad-hoc by default (runs on this Mac), or with the **Signing
Identity** you set (a Developer ID to distribute; `none` skips signing).
With a **Notary Profile** (`xcrun notarytool store-credentials`) and a
Developer ID, the app is then notarized and stapled in the background
(progress in the console). The runner is universal (arm64 + x86_64) when
`scripts/build_runners.sh` finds the x86_64 builds of raylib, Box2D and
Lua; otherwise it's built for the Mac's own architecture.

**Windows** exports are a folder with `<Name>.exe`, `lua54.dll`, `game.rayzr`
and the font. Release runners have no console window
(`-subsystem:windows`). The exe gets the project icon (16-256 px) and
version info (product name, description, version from Project > General) -
written with the Win32 resource API, so this happens when exporting on
Windows; exports made elsewhere keep the runner's own.

**Linux** exports are an AppDir, `<output>/linux/<Name>.AppDir` (`AppRun`,
`<Name>.desktop`, the icon, `usr/bin/` with the runner, `game.rayzr` and the
font); on Linux with `appimagetool` on `PATH` it's also packed into
`<Name>-<arch>.AppImage`.

The engine's open gaps and everything fixed in this pass are listed in [`engine/GAPS.md`](../engine/GAPS.md).

---

## 4. Reusable Components & Prefabs

- **Definition**: Components are reusable node subtree templates stored as JSON snippets.
- **Built-in Catalog**: Physics Dynamic Box, Static Barrier, Orbiting Drone (Lua scripted), Sensor Trigger Zone, Particle FX.
- **Custom Prefabs**: right-click a node → **Save as Component** writes the subtree to `components/<Name>.component.json` and links the node to it.
- **New Component** (Assets **+**, right-click the Components section or a component, or the command palette) makes one from scratch: a name and its root node's type (a Kinematic Body for an enemy, an Area for a pickup...); it opens in its own tab to build. A taken name gets the next free one (`Enemy_2`).
- **Instantiation**: double-click a component in Assets (or drag it into the viewport). Instances are **links**: the scene stores `"component": "<file>"` plus **overrides** — values changed on the instance or any of its children, and children added to or deleted from it — so editing the component file updates every instance except what it overrides. The Inspector lists a node's overrides with **Revert**.
- **Changing a component**: edit an instance in the scene (add or delete children, change values) and choose **Apply Changes to Component** (right-click the instance) to write it to the component file and update every instance, or **Save as New Component** to make a new one from it. You can also open the component itself (*Edit Component*) and use **Save** / **Save As** there. *Unlink* turns an instance into plain nodes.

---

## 5. Build and Run Commands

The editor links the system **libcmark** (`vendor:commonmark`, for the
Scripting Reference's markdown): `brew install cmark` on macOS,
`apt install libcmark-dev` on Debian/Ubuntu. The game runner doesn't need it.

```bash
# Check editor package type-checking
task editor:check
# or: odin check editor

# Build editor binary to bin/editor
task editor:build
# or: odin build editor -out:bin/editor

# Run interactive editor
task editor
# or: odin run editor

# Run complete engine test suite
task test

# Operate the editor through injected input (see TEST_DRIVE.md)
task editor:drive

# Memory diagnostics: the heap through Odin's tracking allocator; every 600
# frames the live bytes, the allocation sites that grew and the temp arena
# (editor/mem_track.odin)
odin build editor -out:bin/editor_mem -define:RAYZR_MEM_TRACK=true -debug
```

Temp memory (`fmt.tprintf`, `context.temp_allocator`) lives for one frame:
the editor and the game free it after drawing. Keep an owned copy of
anything that must outlive the frame (node constructors copy their name and
text into the node's arena).
