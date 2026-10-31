# Settings

The **Settings** dialog holds both your own editor preferences and the
open project's settings. **General** and **Code Editor** are yours: UI
scale, grid, autosave, shortcuts, theme, code editor options - saved for
you on this computer. **Project** is the game's: name, startup scene,
physics, input actions, window and resolution, audio, export, global
scripts and accessibility defaults - saved in the project's
`project.json`. **Plugins** turns editor plugins on and off.

![The Settings dialog](../images/editor_settings.png)

## When to use it

- Pick the scene Play starts with, name the game, set its window size and
  virtual resolution, or set up pixel-perfect scaling.
- Define input actions (`jump`, `fire`) and their keys, mouse buttons and
  gamepad buttons, so scripts never name keys.
- Name collision layers, set gravity, choose the default scene transition.
- Set up exports: platforms, presets, icon, signing.
- Change a shortcut, the theme, the UI scale or the code editor's behaviour.
- To change how one texture or sound loads, use its import settings in the
  [Assets](assets.md) Preview panel instead; to play and export, see
  [Playtesting](playtesting.md).

## What's in it

### Opening and closing

| Way in | Opens on |
|---|---|
| **File > Settings...** or Cmd+, (Ctrl+,) | **General** |
| The gear in the toolbar, or the project name at the left of the toolbar | **Project** |
| **Project Settings...** in the command palette (Cmd+Shift+P (Ctrl+Shift+P) or F1) | **Project** |

The dialog edits copies. **Save** writes `project.json` and your editor
settings and applies both (gravity, input actions, resolution, volumes,
global scripts... take effect in the editor at once). **Cancel** - or Esc,
when you aren't recording a shortcut or a key - throws the changes away,
including a theme you were previewing. Changes made to `project.json`
outside the editor are picked up each time the dialog opens. The project's
folder is shown next to the title.

### General > Basic

| Option | What it does |
|---|---|
| **UI Scale** | The size of the whole editor UI, 0.75x to 2x. |
| **Grid Size** | The viewport grid and snap step, in pixels. |
| **Snap to Grid** | Moving snaps to the grid (also **View > Snap to Grid**, Shift+S). |
| **Show Grid** | Draws the grid in the viewport (also **View > Show Grid**, Shift+G). |
| **Autosave** | Saves modified scenes and scripts every 1-30 minutes; **Off** at 0 (and never while simulating). |
| **Ask Before Quitting** | Asks about unsaved scenes and scripts when you quit. |
| **Check for Updates** | At startup, looks for a newer Rayzr Editor release and shows it in the status bar. |
| **Bottom Panel Follows Selection** | Selecting an AnimationPlayer, particle emitter, LDtk level, State Machine or Tile Map shows its tab in the bottom panel; selecting something else goes back to the tab you had. |
| **Aseprite** | The Aseprite program **Edit in Aseprite** opens. Empty: found where Aseprite installs (Steam too). |

### General > Keymap

Every editor command with its shortcuts, in one table (**Command**,
**Shortcut**, buttons).

| Control | What it does |
|---|---|
| **Filter commands or keys** | Keeps the rows whose command or shortcut contains the text. |
| Pen | Records a new shortcut: press it (Esc cancels). It replaces the command's first shortcut. |
| **x** | Removes the command's shortcuts. |
| Arrow | Resets the command to its default shortcuts. |
| Warning triangle | The shortcut is also bound to another command (hover to see which). |

The same table drives the menus, the command palette and **Help > Keyboard
Shortcuts** (Cmd+Shift+K (Ctrl+Shift+K)), so a changed shortcut shows
everywhere.

### General > Theme

- **Presets**: **Default**, **Dark**, **Mid-day**, **Light**.
- **Current**: the theme's name (*Custom* once you change a colour).
- A colour picker for each theme colour: **App Background**, **Panels**,
  **Inputs & Cards**, **Hover**, **Pressed**, **Text**, **Labels**,
  **Hints**, **Accent**, **Success**, **Warning**, **Danger**, **Code
  Background**.

Changes preview at once; **Save** keeps them, **Cancel** puts the saved
theme back.

### Code Editor

Options for the [Code tab](../../editor/CODE_EDITOR.md):

| Option | What it does |
|---|---|
| **Font Size** | 9 to 32. |
| **Tab Width** | 1 to 8 columns. |
| **Indent With Spaces** | For files that don't have an indentation style yet. |
| **Auto-Close Brackets** | Inserts closing brackets and quotes, steps over them, wraps selections. |
| **Rainbow Brackets** | Colours brackets by how deeply they are nested. |
| **Indent Guides** | Vertical lines at each indentation level; the block around the caret is brighter. |
| **Sticky Scroll** | The first lines of the blocks you are scrolled into stay at the top. |
| **Breadcrumbs** | File > function > blocks around the caret, above the code. |
| **Inlay Hints** | Parameter names before the arguments of engine API and file functions (Ctrl+Alt+H toggles). |
| **Colour Swatches** | A swatch before `{r, g, b[, a]}` colour tables; click it for a colour picker. |
| **Soft Wrap** | Wraps long lines at the Code area's width (Alt+Z toggles). |
| **Show Whitespace** | **None**, **In Selections** or **All**. |
| **Format On Save** | Runs the language server's formatter before saving. |
| **Language Server** | Completion, diagnostics and navigation from lua-language-server (restart the editor to apply). |
| **Server Path** | Where lua-language-server is (empty: the default location). |

### Project > General

**Project**

| Option | What it does |
|---|---|
| **Name** | The game's name (also its save-data folder name and the default executable name). |
| **Version** | The game's version. |
| **Language** | The starting language for texts from the `locale/` tables (empty: the first one). Scripts: `Locale.set`. |
| **Startup Scene** | The scene **Play** (F5) and the exported game start with. **Use Current** picks the scene you are editing (and adds it to the scene list). |
| **Icon** | A PNG for the game window and the exported app (512x512 or 1024x1024 works best). |

**Scene Transitions** (closed at first)

| Option | What it does |
|---|---|
| **Default** | How `Scene.change_scene(name)` changes scenes when the script gives no options: **None (change at once)** or a transition (fade, wipe, circle, ...). |
| **Duration** | Seconds: each half of a cover transition (fade, wipe, circle), the whole of the others. |
| **Easing** | The easing curve. |

See [scene flow](../../engine/docs/scene_flow.md).

**Physics**

| Option | What it does |
|---|---|
| **Gravity** | x, y in pixels per second squared. **Zero-G** sets (0, 0); **Earth (0, 980)** sets (0, 980). |
| **Show Colliders** | The running game draws collision shapes, joints and areas (on by default). The editor's viewport shows them either way. The same switch is in the toolbar and **Game > Show Colliders in Game**. |

**Developer Console** (closed at first): the in-game console that opens with
` - commands, Lua, a perf overlay, debug drawing, pause and step (see
[Console](../lua/Console.md)).

| Option | What it does |
|---|---|
| **In Release Builds** | Release exports have the console too. Debug builds and Play always have it. |
| **Key** | The key that opens and closes it: ` (backquote), F1, F2, F12, Tab or Backslash. |

**Collision Layers** (closed at first): names for layers 1-16. Bodies'
layer lists show them, and scripts use them:
`body:set_collision_layer("Player")`.

**Scenes**: the scenes included in the game and in exported packages, with
*(startup)* by the startup scene. The **x** removes a scene from the list
(not from disk); **Add <scene>** adds the scene you are editing when it
isn't listed. New scenes made in the editor are added for you.

### Project > Input

Named actions and what triggers them. Scripts ask for actions, not keys:
`Input.is_action_down("jump")`. A project with no actions starts from the
built-in ones.

- **The action list** (left): click an action to edit it; right-click >
  **Remove action**. Type a name in **new_action** and press Enter or
  **+** to add one.
- **Prompts**: the pad whose button images are shown next to each binding
  - **Xbox**, **PlayStation**, **Switch** or **Steam Deck**. Games get the
  same images from `Input.glyph(action)`.
- **Each binding**: its prompt image, the device (**None**, **Key**,
  **Mouse**, **Gamepad Button**, **Gamepad Axis**), the key or button, and
  **x** to remove it. A gamepad axis also has **+** (the positive
  direction) and a dead zone (**dz**).
- **Press a Key**: the next key you press becomes a binding (Esc cancels).
- **Add Binding**: adds a binding (Space) to change by hand.

An action takes up to 4 bindings. Guides: [gamepads](../../engine/docs/gamepads.md),
[input rebinding](../../engine/docs/input_rebinding.md).

### Project > Video

| Option | What it does |
|---|---|
| **Window Title** | The game window's title. |
| **Window Size** | The window's size in pixels. |
| **Virtual Resolution** | The resolution the game is designed for; it is scaled to the window, or to the screen when fullscreen. The viewport's camera frame shows it. |
| **Screen Fill** | For a window whose shape differs: **Keep (bars)** shows exactly the virtual resolution with black bars; **Expand (no bars)** keeps the scale and shows more of the world on the longer side (UI on a Screen Layer stays at the screen's edges). |
| **Target FPS** | 30 to 240. |
| **Fullscreen** | Covers the whole screen at its own resolution. Scripts: `Engine.set_fullscreen(true)`. |
| **Sharp Pixels** | Scales the game nearest-neighbour: crisp pixel art (off: smooth). |
| **Integer Scaling** | Scales by a whole number (2x, 3x...) with bars around: every game pixel the same size. |
| **Pixel Snap** | The camera and sprites sit on whole game pixels: no shimmering. |
| **Smooth Camera** | With Pixel Snap: keeps the camera's sub-pixel motion when scaling up, so slow pans glide; UI layers stay put. |
| **VSync** | Waits for the display's refresh. |
| **Resizable Window** | The player can resize the window. |
| **Anti-aliasing (MSAA 4x)** | Smooths the edges of shapes. |
| **High-DPI** | Renders at the display's native pixel density. |

Guide: [pixel-perfect rendering](../../engine/docs/pixel_perfect.md).

### Project > Audio

**Master Volume**, **Music** and **Sound Effects**, 0-100%. Music and
sound nodes play at their own volume times these. Buses and effects are in
the [Mixer tab](tab-mixer.md).

### Project > Export

| Option | What it does |
|---|---|
| **Executable Name** | The exported program's name (default: the project name without spaces). |
| **Output Folder** | Where exports go (default: `<project>_standalone` next to the project). **Browse...** picks a folder. |
| **Targets** | Without presets: **macos**, **windows**, **linux**, **web** - one export each. |
| **Runners** | Whether each platform's prebuilt game runner is *ready*, *missing*, or (this computer's platform) *built on export*. Hover for where runners live. |
| **Compress Package** | Compresses `game.rayzr`. |
| **Include UI Font** | Ships the UI font with the game. |
| **macOS Bundle ID** | With a macOS export: the app's bundle identifier. |
| **Signing Identity** | With a macOS export: the codesign identity. Empty is ad-hoc (runs on this Mac); a Developer ID is needed to distribute and notarize. |
| **Notary Profile** | With a macOS export and a Developer ID: the keychain profile (`xcrun notarytool store-credentials`); the app is then notarized and stapled after export. |

**Presets** give each platform (or a demo or debug build) its own
settings. **Use Presets** turns the ticked targets into presets. Then:

- The preset list - click one to edit it. **Add Preset** (pick a
  platform), **Duplicate**, **Remove**.
- For the selected preset: **Name**, **Platform**, **Executable Name**,
  **Output Folder** (default: a folder named after the preset inside the
  output folder), **Version**, **Icon** (None = the project's), **Window
  Title**, **Window Size** (0 x 0 = the project's), **Fullscreen**
  (**Project setting**, **On** or **Off**), **Include** and **Exclude**
  (file patterns, one per line - `*.psd`, `raw/`, `levels/test_*`; empty
  Include = everything), **Debug** (the debug runner: debug info, a
  console window on Windows).
- **Save and Export This Preset** saves the settings and exports that one
  preset.

**Save and Export** (or **Save and Export All** with several presets) at
the bottom saves the settings and exports everything. See
[Playtesting](playtesting.md) for what an export writes, and
[web export](../../engine/docs/web_export.md).

### Project > Globals

Global scripts: each is loaded once, before any scene. The table it
returns is a Lua global with the given **Name** in every script, kept
across scene changes; its `ready(self)` runs when the game starts and
`update(self, dt)` every frame.

- Each row: **Name**, **Script** and **x** to remove it. A name that isn't
  a valid Lua name, or that another global already has, is flagged in red.
- **Add Global** adds a row with the first script that isn't global yet.
- Or right-click a script in [Assets](assets.md) > **Make Global**.

### Project > Accessibility

The defaults every player starts with; players change their own in the
game (see the Accessibility Menu script template and
[accessibility](../../engine/docs/accessibility.md)).

| Option | What it does |
|---|---|
| **UI Scale** | 0.5x to 3x; top-level UI grows around the screen corner, edge or centre it is nearest to. |
| **Colour Filter** | **Off**, **Protanopia**, **Deuteranopia**, **Tritanopia**: corrects the picture for that colour vision deficiency. (**View > Colour Vision** previews how players with it see the scene.) |
| **Filter Strength** | 0 to 1. |
| **Subtitles** | Spoken lines on the subtitle track. |
| **Sound Captions** | Sounds' captions on the subtitle track (a Sound or Music node's Caption). |
| **Subtitle Size** | 0.5x to 3x. |
| **Subtitle Backdrop** | The opacity behind subtitles, 0 to 1. |
| **Screen Shake** | Scales every camera shake (0 = none, up to 2x). |

### Plugins

Changes here apply at once (no Save needed).

- **This project's plugins**: allowed, blocked or not yet allowed, with
  **Allow** / **Block**.
- **Rescan** finds plugins again after you add or remove a plugin folder.
- **User Plugins Folder** opens the folder for plugins that run in every
  project.
- The list: each plugin with a mark (running, off, failed). For the
  selected one: name, version, whether it is a project or user plugin,
  its folder, description and permissions (*runs programs*, *uses the
  network*), its state, **Enabled**, **Reload** (stop and start it), **Open
  Folder** and its **Log**.

### Where settings are kept

- Editor settings: `~/.config/rayzr_editor/settings.ini` (shortcuts,
  theme, recent projects and the folders you last imported from, exported
  to and opened projects from are there too).
- Project settings: `project.json` in the project folder.

## Walkthrough

Set up a pixel-art platformer: the start scene, crisp scaling and a jump
action.

1. Open the scene the game should start in, then the toolbar's gear: the
   dialog opens on **Project > General**.
2. Type the game's **Name**. Next to **Startup Scene** press **Use
   Current**.
3. Under **Physics**, press **Earth (0, 980)**.
4. Open **Collision Layers** and name layer 1 `World`, layer 2 `Player`.
5. Go to **Video**. Set **Virtual Resolution** to 320 x 180 and **Window
   Size** to 1280 x 720. Tick **Sharp Pixels**, **Integer Scaling** and
   **Pixel Snap**.
6. Go to **Input**. Type `jump` in the box under the list and press Enter.
   Press **Press a Key** and then Space. Press **Add Binding**, set its
   device to **Gamepad Button** and pick the bottom face button.
7. Press **Save**. In a script, `Input.is_action_pressed("jump")` now
   answers to Space and the pad.
8. Press F5: the game opens at 1280 x 720, each game pixel a crisp 4x4
   square.

## Tips

- Settings are drafts until **Save**. If a change seems to do nothing,
  check that you saved rather than pressed Esc.
- **Set as Startup Scene** on a scene in [Assets](assets.md) does the same
  as **Startup Scene** here, without opening the dialog.
- **Show Colliders** is also a toolbar button that switches a running game
  at once.
- Record a shortcut, then look for the warning triangle: a shortcut shared
  with another command only runs one of them.
- Related pages: [Playtesting](playtesting.md),
  [Toolbar and menus](toolbar-menus.md), [Mixer tab](tab-mixer.md),
  [Code tab](../../editor/CODE_EDITOR.md),
  [pixel-perfect guide](../../engine/docs/pixel_perfect.md).
