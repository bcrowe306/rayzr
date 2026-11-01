# Playtesting

Playtesting runs your game while you work on it. **Play** starts the real
game in its own window - from the startup scene, or from the scene you are
editing - and links it to the editor, so you can pause it, step it a frame
at a time, look at and change its nodes live, and run Lua in it.
**Simulate** runs the open scene inside the editor's viewport instead, and
puts it back when you stop. **Export** turns the project into a package or
a standalone game you can hand to players.

![Play controls in the toolbar](../images/editor_playtesting.png)

## When to use it

- Try the whole game from its start: **Play Project** (F5).
- Try just the level you are building: **Play Current Scene** (F6).
- Watch physics, scripts and animations run without leaving the editor:
  **Simulate in Editor** (F7).
- Find out why something goes wrong: pause, step frame by frame, inspect
  live values in the [Game tab](tab-game.md), evaluate Lua in the
  [Console](tab-console.md), or set breakpoints in the
  [Code tab](../../editor/CODE_EDITOR.md).
- Tune a value while playing, then keep it: change it live and **Apply to
  Scene**.
- Ship or share a build: **File > Export**.

## What's in it

### Play controls

The play controls sit in the middle of the toolbar. What they show depends
on the game's state:

| State | Buttons |
|---|---|
| Not running | **Play project** (F5), **Play this scene** (F6) |
| Building | **Stop** - cancels the build; *Building...* |
| Running | **Pause** / **Resume** (F9), **Step** (Shift+F9), **Restart** (Cmd+Shift+F5 (Ctrl+Shift+F5)), **Stop** (Shift+F5) |

Next to them:

- **Show Colliders** (the square icon) - whether the running game draws
  collision shapes, joints and areas. It is the project setting (saved in
  `project.json`) and switches a running game at once.
- The game's state: **Running**, **Paused** or **Breakpoint**. The status
  bar shows it too, with the game's process id.

### The Game menu

| Item | Shortcut | What it does |
|---|---|---|
| **Play Project** | F5 | Plays from the startup scene (Project Settings > General). |
| **Play Current Scene** | F6 | Plays the scene you are editing. |
| **Pause** | F9 | Pauses or resumes the running game. |
| **Step One Frame** | Shift+F9 | Runs one frame (pausing first). |
| **Restart** | Cmd+Shift+F5 (Ctrl+Shift+F5) | Stops and plays the same thing again - the project, the same scene, or the same package - saving and rebuilding first like Play. After the game was stopped, it replays the last run. |
| **Stop** | Shift+F5 | Ends the game. |
| **Show Colliders in Game** | | The Show Colliders switch above. |
| **Simulate in Editor** | F7 | Starts or stops Simulate (ticked while on). |
| **Save Data > Open Folder** | | Opens the folder the game's `Save` data goes in. |
| **Save Data > Delete Save Files** | | Deletes the game's save files (`*.json` there) so the next run starts fresh. |

A scene's right-click menu in [Assets](assets.md) also has **Play This
Scene**.

### What Play does

1. Saves every modified scene (the game reads scene files). Scripts you
   haven't saved are not saved for you.
2. Starts the game - this platform's game runner (the one export uses). In
   a source checkout of the engine it is the engine's game build instead,
   rebuilt first when an engine source file changed; the build's output
   streams into the Console, and Stop cancels it.
3. Runs it with your project (and, for F6, the scene) and links it to the
   editor. The game's output appears in the [Console](tab-console.md),
   marked `[game]`; lines with "error" or "warn" are shown as errors or
   warnings, and script errors are underlined in the Code tab.

While the game runs:

- **Saving a scene** reloads it in the game (the current scene restarts
  with the saved version).
- **Edited scripts and images** reload by themselves.
- **Breakpoints** set in the Code tab stop the game on their line; the
  [Game tab](tab-game.md) shows the call stack, locals and watches.

Plugins can stop Play from starting (the console says why).

### The remote view

Once the game is linked:

- The **Scene panel** gets a **Local / Remote** switch. **Remote** shows
  the running game's scene tree (refreshed twice a second): filter it,
  switch a node's **enabled** (power) and **visible** (eye), pick nodes,
  and right-click for **Apply to Scene**, **Remove from Game** and **Copy
  Path**. The crosshair button **picks**: click a node in the game window
  and it is selected here.
- The **Inspector** shows the selected game node's live properties, *Live
  in the game*: drag numbers and vectors, tick check boxes, pick colours
  and enum values, type text and press Enter - each change goes to the
  game at once.
- The selected node is outlined in the game window.
- **Apply to Scene** copies the node's current values (transform and
  properties, not script values) into the node with the same path in the
  edited scene - undoable. The game must be running the scene you have
  open.

**Local** goes back to the edited scene; stopping the game does too. The
[Game tab](tab-game.md) shows the same tree and properties side by side.

### Recording input for a test

While the game runs, the red **Record** button next to Stop records your
keys, mouse, gamepads and touches; press it again to save them to
`tests/recordings/recording_N.txt`. A test plays them back with
`Test.replay("recording_N")` - see the [Tests tab](tab-tests.md).

### The developer console

Press ` in the running game for the developer console. A line is a
command (`help` lists them) or else Lua run in the game: `pause` and `step`
freeze it and step frame by frame, `timescale 0.25` slows it, `perf` shows
frame times, and `physics`, `nav`, `camera` and `outlines` draw what's
otherwise invisible. Scripts add their own commands with
[Console.register](../lua/Console.md). Exported debug builds have it too.

### Simulate in Editor

**Simulate** (F7) runs the open scene in the editor's own viewport:

- It saves a snapshot of the scene, starts global scripts, then calls the
  scene's `ready` functions - like the game would.
- Physics, scripts, tweens and events run every frame.
- The status bar says *Simulating in editor*. The [Console](tab-console.md)'s
  **Lua** line evaluates in the simulation.
- F7 again stops it, and the scene goes back to the snapshot: anything
  that moved, spawned or was edited during the simulation is undone. Edits
  made while simulating aren't recorded for Undo.
- You can't switch or close scene tabs while simulating.

Pause, Step and the remote view work with Play, not with Simulate.
Debugging with breakpoints also needs Play.

### Export

| Item | What it does |
|---|---|
| **File > Export > .rayzr Package** | Asks for a folder and writes `<project>.rayzr` there - the whole project in one file (modified scenes are saved first; textures set to QOI or Atlas are converted). The toolbar's box icon does the same. |
| **File > Export > Standalone Game** | Saves everything and exports each export preset (or each ticked target) with the settings in Project Settings > **Export**: a folder per preset with the game runner, `game.rayzr` and the UI font. |
| **File > Export > Open Web Export in Browser** | Serves the last web export from a small local web server and opens it in your browser. |

What a standalone export writes, per platform:

| Platform | Folder contents |
|---|---|
| Windows | `<Name>.exe` (with the runner's libraries), `game.rayzr`, `fonts/` |
| macOS | `<Name>.app` - signed, and notarized when a Developer ID and notary profile are set |
| Linux | `<Name>.AppDir`, plus an `.AppImage` when `appimagetool` is installed |
| Web | `index.html` with the runner and `game.rayzr` |

Runners for each platform come with the editor (`runners/<platform>/`).
Settings > Project > Export shows which are ready. All settings:
[Settings](settings.md).

**Run an exported package**: exported `.rayzr` files next to the project
folder are listed under **Packages** in [Assets](assets.md); right-click
one > **Run Game From Package** plays it like Play (Restart replays it).

## Walkthrough

Find out why the player can't reach a platform, and keep the fix.

1. Open the level and press F6. The game window opens on that scene; the
   toolbar shows **Running**.
2. Press F9 while the player stands below the platform. The toolbar shows
   **Paused**.
3. In the Scene panel press **Remote**, then the crosshair, and click the
   platform in the game window. It is selected in the tree and outlined in
   the game.
4. The Inspector shows the platform's live values. Drag its **Position**
   y a little larger: the platform moves down in the game window.
5. Press F9 to resume and jump: the player now reaches it. (Shift+F9 steps
   one frame at a time if you want to watch the landing closely.)
6. Right-click the platform in the remote tree > **Apply to Scene**. The
   console says how many values were applied; the edited scene's platform
   has them (Cmd+Z (Ctrl+Z) would take them back).
7. Press Shift+F5 to stop, then Cmd+S (Ctrl+S) to save the scene. Press
   Cmd+Shift+F5 (Ctrl+Shift+F5) to check it again.

## Tips

- F5 runs the startup scene, not the one in front of you - use F6 to test
  the level you are on, and set the startup scene in
  [Settings](settings.md) or with **Set as Startup Scene** in Assets.
- Restart is the fastest loop after a change: it saves, rebuilds if
  needed and plays the same scene again.
- Save scripts before pressing Play - Play saves scenes, not scripts.
  Scripts you save while the game runs reload in it.
- **Game > Save Data > Delete Save Files** gives the next run a fresh
  start (no saved progress).
- The [Profiler tab](tab-profiler.md) shows frame times and node counts.
- More: [Game tab](tab-game.md), [Console](tab-console.md),
  [Settings](settings.md), [Toolbar and menus](toolbar-menus.md),
  [web export](../../engine/docs/web_export.md),
  [crash reports](../../engine/docs/crash_reports.md).
