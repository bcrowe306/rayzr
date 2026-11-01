# Assets

The **Assets** panel lists every file of the open project: scenes,
components, custom nodes, scripts, resources, textures, Aseprite files,
vector art, audio, LDtk levels, level generators, shaders and exported
packages. From here you open scenes, drag art and sounds into the viewport,
import new files and keep the project's folders tidy. The **Preview** panel
next to it shows the selected asset - an image, a sound, an animation, a
scene or a script - and holds the asset's **import settings**.

![The Assets panel](../images/editor_assets.png)

## When to use it

- Open a scene (double-click it) or start a new one (**+** on the
  **Scenes** row, or Cmd+N (Ctrl+N)).
- Put things in a scene: drag a texture, sound, component, custom node,
  Aseprite file, SVG or LDtk level into the [viewport](viewport.md); drag a
  script or shader onto a node.
- Bring files into the project: drop them on the editor window, or use
  **+ > Import Assets...**. To look through files on your computer first,
  use the [Files tab](tab-files.md).
- Set how a texture or sound loads (filtering, QOI, atlas, gain, bus) in the
  Preview panel's import settings.
- Rename, move or delete files without breaking the scenes and scripts that
  use them, and find what uses a file (**Find Usages**).
- To find text inside scripts and scenes, use the [Search tab](tab-search.md)
  instead; to jump to any file by name, use **Go to File** (Cmd+P (Ctrl+P)).

## What's in it

### The header

| Control | What it does |
|---|---|
| **Folders view** (folder tree icon) | Switches between the by-type sections (off) and the project's real folders (on). |
| **Thumbnail grid** (grid icon) | Switches between a list and a grid of tiles. Images, Aseprite files and SVGs show a thumbnail; other files a large icon. |
| **+** | The add menu: import files or create new assets (below). |
| **Search assets** | Keeps only the files whose path contains the text (any case). In the Folders view the matches are shown as one flat list. |

At the bottom of the list, *Drop files or folders here to import* is a
reminder that the panel takes files from Finder / Explorer.

### The + menu

| Item | What it does |
|---|---|
| **Import Assets...** | The system file dialog, several files at once (images, audio, Lua, scenes, components, LDtk, shaders, Aseprite, and any type a plugin imports). It opens in the folder you last imported from. |
| **Import Folder...** | Imports every supported file in a folder, keeping its layout. |
| **New Scene** | Creates `scenes/new_scene.scene.json` (or `new_scene_2`, ...) with a camera, adds it to the project and opens it. |
| **New Script...** | A new Lua script from a template. |
| **New Resource...** | A data asset of a resource class (a script with a `resource` marker). See [resources](../../engine/docs/resources.md). |
| **New Component...** | A reusable piece of a scene, built from scratch: pick its root node, then add to it. See [components](../../engine/docs/components.md). |
| **New Custom Node...** | A node type of your own (a base type, a script and default values), listed in Add Node. See [custom nodes](../../engine/docs/custom_nodes.md). |
| **New Shader** | A new fragment shader file in `shaders/`. |
| **New Level Generator** | A procedural level graph that writes into a Tile Map. See [level generator](../../engine/docs/level_generator.md). |

### By-type sections

Each section is a folder row with a count; click it to fold or unfold it.
Sections hide while a search matches nothing in them.

| Section | Lists | Row button / right-click on the row |
|---|---|---|
| **Scenes** | `scenes/*.scene.json` | **+** New scene; **New Scene**, **Import Scenes...** |
| **Components** | `components/*.component.json` | **New Component...**, **Import Components...** |
| **Custom Nodes** | `*.node.json` anywhere | **+** New custom node type; **New Custom Node...** |
| **Scripts** | `scripts/*.lua` | **+** New script; **New Script...**, **Import Scripts...** |
| **Resources** | `resources/*.resource.json` | **+** New resource; **New Resource...**, **New Resource Class...** |
| **Textures** | `textures/` png, jpg, jpeg, bmp, tga | **Import Textures...** |
| **Aseprite** | `.aseprite` / `.ase` anywhere | |
| **Vector Art** | `.svg` anywhere | |
| **Audio** | `audio/` wav, ogg, mp3 | **Import Audio...** |
| **Levels** | `.ldtk` anywhere | **Import LDtk Project...** |
| **Level Generators** | `.levelgen.json` anywhere | |
| **Shaders** | `.fs`, `.glsl`, `.frag` anywhere | |
| **Packages** | exported `.rayzr` files next to the project folder (closed at first) | |

Every section's right-click menu also has **Paste** (an asset you copied)
and **Reveal in Finder** (**Show in Folder** on Windows and Linux).

Scenes and components are shown without their `.scene.json` /
`.component.json` endings. Marks on a row:

- A dot after a scene or script: it has unsaved changes.
- The active scene is drawn in the accent colour.
- A globe and a name after a script: it is a **global script**
  (Project Settings > Globals) - every script can use it by that name.
- **×3** after a component: how many instances the open scenes use.
- Files you just imported are tinted for two seconds.

Hover a row for its path and what dragging or double-clicking it does.

### Folders view

The project folder is at the top; each folder opens and closes with a
click, with its files below it. Import settings files (`*.import.json`) are
hidden.

- **Drag** a file or a folder onto a folder to move it there. A selection
  of several files moves together.
- **Right-click a folder**: **New Folder** (then type its name), **Paste
  Here**, **Rename...**, **Find Usages**, **Delete...** (the folder and
  everything in it) and **Reveal in Finder**. The project folder itself
  only has New Folder, Paste Here and Reveal.

Moving or renaming updates every reference: scenes and components
(including open ones with unsaved edits, and their undo history), scripts
and `project.json` (startup scene, scene list, icon, import settings).
Open scripts that move are reopened at their new path; a script open in
the Code tab with unsaved edits must be saved before it can move.

### Selecting assets

| Input | What it does |
|---|---|
| Click | Selects one asset; the Preview panel shows it. A resource also opens in the [Inspector](inspector.md). |
| Cmd+click (Ctrl+click) | Adds or removes one asset. |
| Shift+click | Selects a range. |
| Up / Down (and Left / Right in the grid) | The next or previous asset, with the panel focused. Shift extends the selection. |
| Click empty space | Clears the selection. |
| Delete or Backspace | Asks to delete the selected asset(s). |
| Double-click | Opens it (below). |

### Double-click

| Asset | Double-click |
|---|---|
| Scene | Opens it in a scene tab. |
| Component | Adds an instance at the centre of the view. |
| Custom node | Adds one at the centre of the view. |
| Script, shader | Opens it in the Code tab. |
| LDtk level | Adds an LDtk Level node at the centre of the view. |
| Aseprite file | Opens it in Aseprite (Settings > General > Basic > **Aseprite**). |
| SVG | Opens it in your vector app. |
| Level generator | Opens the Level Generator window. |

### Dragging into the viewport

| Asset | Dropped on the viewport |
|---|---|
| Texture | A new [Texture node](../nodes/TextureNode.md) where it lands. |
| Audio | A new [Sound node](../nodes/SoundNode.md) with the sound. |
| Component | An instance of the component. |
| Custom node | A node of that type. |
| Aseprite file | An [Aseprite node](../nodes/AsepriteNode.md) playing its first tag. |
| SVG | A new [Vector Shape](../nodes/VectorShapeNode.md); dropped onto an existing Vector Shape, that node draws the file instead. |
| LDtk level | An [LDtk Level node](../nodes/LdtkLevelNode.md). |
| Script | Attached to the node under the mouse (else the selected node). |
| Shader | Applied to the node under the mouse (else the selected node). |
| Level generator | Opens the Level Generator window. |

Several selected assets drop together, a little apart from each other.

### Right-click an asset

The first items depend on the type; the rest are on every asset.

| Asset | Items |
|---|---|
| Scene | **Open**, **Play This Scene**, **Set as Startup Scene** |
| Component | **Edit Component**, **New Component...**, **Select All Instances**, **Add to Scene**, **Add as Child of Selected** |
| Custom node | **Add to Scene**, **Add as Child of Selected**, **Edit Script**, **Edit Type** (its defaults as a node), **Edit Definition** (the `.node.json` as text), **New Type Based on This...**, **Change Base Type...** |
| Script | **Edit Script**, **Attach to Selected Node**, **Make Global** / **Remove Global** |
| Texture | **Add Sprite to Scene**, **Use on Selected Sprite**, **Slice Sprite Sheet...**, **Generate Normal Map...** (a normal map from the sprite's shape and brightness, for lighting), **Use as Tileset of Selected Tile Map** |
| Audio | **Add Sound to Scene**, **Add Music to Scene**, **Use on Selected Sound/Music** |
| LDtk level | **Edit in Level Tab**, **Add Level to Scene**, **Open in LDtk**, **Use on Selected Level** |
| Aseprite file | **Add Sprite to Scene**, **Use on Selected Aseprite Node**, **Use as Tileset of Selected Tile Map**, **Edit in Aseprite** |
| SVG | **Add Vector Shape to Scene**, **Use on Selected Vector Shape**, **Edit in Vector App** |
| Resource | **Edit Class Script**, **New Resource of This Class...** |
| Shader | **Edit Shader**, **Use on Selected Node** |
| Level generator | **Open in Level Generator** |
| Other files | **Open With Default App** |

On every asset:

| Item | What it does |
|---|---|
| **Copy** | Remembers the asset (and puts its path on the clipboard) for **Paste Here**. |
| **Paste Here** | A copy of the copied asset in this asset's folder. |
| **Duplicate** | A copy next to it: `ship_copy.png`, `ship_copy_2.png`, ... |
| **Rename...** | A new name; references follow, as for a move. |
| **Find Usages** | Opens the **Usages** window: every scene, component, script or project setting that names the file, with a count. Double-click a row to open that file. |
| **Delete...** | Asks first, then deletes the file from disk (its import settings too). Scenes, scripts or components that used it will show it as missing. There is no undo. |
| **Copy Path** | The project-relative path, for scripts. |
| **Reveal in Finder** / **Show in Folder** | Opens the file's folder. |

With several assets selected, the menu acts on all of them: **Add All to
Scene**, **Duplicate**, **Delete...**, **Copy Paths** (one per line) and
**Reveal in Finder**.

A **Packages** row's menu: **Run Game From Package** (plays the exported
`.rayzr`, see [Playtesting](playtesting.md)), **Reveal in Finder**, **Copy
Path** and **Delete Package**.

### Importing

Files and folders dropped on the editor window from Finder / Explorer are
imported. Dropped on the viewport, the textures, sounds, components, LDtk
levels, Aseprite files and SVGs among them are also added to the scene
where they land.

Each file goes to the folder for its type, and a dropped folder keeps its
layout below that (`Pack/Effects/spark.png` -> `textures/Pack/Effects/spark.png`):

| Files | Folder |
|---|---|
| png, jpg, jpeg, bmp, tga | `textures/` |
| wav, ogg, mp3 | `audio/` |
| lua | `scripts/` |
| `.scene.json` | `scenes/` (and added to the project's scene list) |
| `.component.json` | `components/` |
| ldtk, `.levelgen.json` | `levels/` |
| fs, glsl, frag | `shaders/` |
| aseprite, ase | `sprites/` |
| svg | `vectors/` |
| `.resource.json` | `resources/` |
| `.node.json` | `nodes/` |
| ttf, otf, fnt | `fonts/` (copied as they are) |

- Contents are checked: images must decode, audio must have a WAV, Ogg or
  MP3 header, JSON must parse. A broken or unsupported file fails on its
  own; the rest still import.
- A file already in the project with the same contents is skipped. A
  different file with a taken name comes in beside it as `name_2.ext`.
- An LDtk project brings its external levels and the tileset and background
  images it uses (into `textures/`, with the level's paths rewritten).
- The console lists what was imported. When something fails, the **Import
  Results** window opens: each file with its new path, *already in the
  project*, or why it failed (failures first).
- The imported files are selected and highlighted, and their sections open.

### The Preview panel

The header shows the selected asset (or node) and five buttons that pick
what is shown: **Texture**, **Audio**, **Animation**, **Scene** and
**Script**. Selecting an asset switches to the right one.

**Texture** (images and SVGs):

| Control | What it does |
|---|---|
| Texture list | Picks another `.png` from `textures/`. |
| Size badge | Width x height in pixels. |
| **Zoom** | 0.25x to 4x. |
| **Fit** | Fits the image to the panel instead. |
| Image | On a checkerboard (to see transparency); hover for the pixel under the mouse. |

Import settings of a texture (saved next to it as `<file>.import.json`,
applied at once in the editor and when the game loads it - see
[import settings](../../engine/docs/import_settings.md)):

| Setting | What it does |
|---|---|
| **Filter** | **Point** (default) keeps pixel art crisp; **Bilinear** / **Trilinear** smooth scaled images (Trilinear uses mipmaps). |
| **Wrap** | **Repeat** tiles past the edges (parallax, shaders); **Clamp** stretches the edge pixels. |
| **Mipmaps** | Smaller copies for drawing the texture far smaller than its size. |
| **Export: Keep / QOI** | How export stores it: as it is, or re-encoded as QOI (loads faster, usually a bigger file). |
| **Atlas** | Packed into a sprite atlas on export, so sprites on one atlas page draw in one batch. See [atlas](../../engine/docs/atlas.md). |
| **Normal** | The normal map lights shade it by: *Auto (_n)* uses `<image>_n.png` next to it, *None* turns it off, or pick another image. See [Light](../nodes/LightNode.md#normal-maps). |
| **Green Down** | The normal map's green channel points down (DirectX style); off for OpenGL style, which most 2D tools make. |
| **Slice** | Shown when the sheet has a slicing preset (saved with **Save Preset** in the Sprite Sheet Slicer); the **x** forgets it. |

An SVG shows its own two settings instead: **Scale** (document units to
pixels for every Vector Shape that draws it) and **Origin** (**Centre**,
**Top left** or **Bottom centre** - the origin new Vector Shapes of the
file get). See [vector art](../../engine/docs/vector.md).

**Audio** (wav, ogg, mp3):

| Control | What it does |
|---|---|
| Sound list | Picks another sound. |
| **Play** / **Stop** | Plays the sound; the bar shows the time. |
| Autoplay (circle-play icon) | Plays a sound or animation as soon as it is selected - handy with the arrow keys. |
| Loop (repeat icon) | Plays again from the start. |
| Volume | The preview volume (only the preview). |
| **Gain** | Import setting: -24 to +12 dB, wherever the sound plays. |
| Bus | Import setting: the [mixer](tab-mixer.md) bus it plays into when the node or script names none (**Default bus**: SFX for sounds, Music for music). |

Autoplay, Loop and the volume are shared with the Files tab and remembered.

**Animation**: an Aseprite file or an animated GIF plays here when
selected, each frame for its own time. The controls: first frame, previous,
play / pause, next, last; a **FPS** speed (for frame sequences without
their own timing); **Loop**; and a strip of every frame - click one to show
it. With a scene open the list above also offers the scene's first
[Frame Animation node](../nodes/FrameAnimationNode.md).

**Scene**: the scene open in the viewport - its node count, camera
position and zoom, gravity, and a table of every node (name, type, layer,
position, scale, script).

**Script** (a selected `.lua`): the project's input actions as buttons you
can drag into the script, the script's exported properties (default,
range, Inspector label), every scene and component that uses it (**Select
Node** selects a node in the open scene) and its source.

## Walkthrough

Bring in a sprite sheet and a sound, place them, and tidy the folder.

1. Drag `hero.png` and `jump.wav` from Finder / Explorer onto the
   **Assets** panel. The console says *Imported 2 asset(s)*; they land in
   `textures/` and `audio/`, selected and highlighted.
2. Click `hero.png`. The Preview panel shows it. It is pixel art, so leave
   **Filter** on **Point**.
3. Right-click `hero.png` > **Slice Sprite Sheet...**, set the grid and
   press **Save Preset**. The preview now shows **Slice 8 x 4**.
4. Drag `hero.png` into the viewport: a Texture node named `hero` appears
   where you drop it.
5. Click `jump.wav` and press **Play** to hear it. It is too loud: drag
   **Gain** to -6 dB.
6. Turn on the **Folders view**. Right-click `textures` > **New Folder**,
   name it `characters`, and drag `hero.png` onto it. The console reports
   how many references in how many files were updated - the scene still
   shows the sprite.
7. Right-click `hero.png` > **Find Usages**: the scene you dropped it in is
   listed. Press Cmd+S (Ctrl+S) to save the scene.

## Tips

- Turn on Autoplay and walk a folder of sounds or Aseprite files with the
  Up / Down keys to audition them quickly.
- Delete removes files from disk, not to the bin, and cannot be undone.
  Use **Find Usages** first.
- **Set as Startup Scene** on a scene is the quick way to change what Play
  (F5) runs - the same as **Startup Scene** in [Settings](settings.md).
- **Make Global** on a script adds it to Project Settings > **Globals**
  under a name taken from the file.
- More: [Inspector](inspector.md), [Viewport](viewport.md),
  [Scene tree](scene-tree.md), [Files tab](tab-files.md),
  [import settings guide](../../engine/docs/import_settings.md),
  [Aseprite files](../../engine/docs/aseprite.md).
