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

## 2. The editor manual

This file is the overview; the editor manual has a page per part of the
editor - what it is for, when to use it, every control, a screenshot and a
short walkthrough. The [editor tour](../docs/editor/tour.md) maps the window. In the
editor, **F1** opens the page of the panel with focus, **Help > Help for
<panel>** the last one's, a bottom tab's right-click menu its **Help**, the
Settings dialog's **?** its page, and **Help > Editor Manual** the list
(`editor/panel_help.odin`).

| Area | Pages |
|---|---|
| Getting started | [Welcome window and workspaces](../docs/editor/welcome.md), [Editor tour](../docs/editor/tour.md) |
| The main window | [Toolbar and menus](../docs/editor/toolbar-menus.md), [Command palette](../docs/editor/command-palette.md), [Keyboard Shortcuts](../docs/editor/keyboard-shortcuts.md), [Scene tree](../docs/editor/scene-tree.md), [Inspector](../docs/editor/inspector.md), [Viewport](../docs/editor/viewport.md), [Vector edit mode](../docs/editor/vector-edit.md), [Assets](../docs/editor/assets.md), [Settings](../docs/editor/settings.md), [Playtesting](../docs/editor/playtesting.md), [Export](../docs/editor/export.md) |
| The root tabs | [Code tab](../docs/editor/code.md) (full reference: [CODE_EDITOR.md](CODE_EDITOR.md)), [Level tab](../docs/editor/level.md) |
| Bottom tabs | [Console](../docs/editor/tab-console.md), [Profiler](../docs/editor/tab-profiler.md), [Game](../docs/editor/tab-game.md), [Animation](../docs/editor/tab-animation.md), [Particles](../docs/editor/tab-particles.md), [LDtk](../docs/editor/tab-ldtk.md), [Tile Map](../docs/editor/tab-tilemap.md), [State Machine](../docs/editor/tab-stategraph.md), [Behavior Tree](../docs/editor/tab-behaviortree.md), [GOAP](../docs/editor/tab-goap.md), [Mixer](../docs/editor/tab-mixer.md), [Library](../docs/editor/tab-library.md), [Search](../docs/editor/tab-search.md), [Files](../docs/editor/tab-files.md), [Tests](../docs/editor/tab-tests.md) |
| Tool windows | [Level Generator](../docs/editor/level-generator.md), [Terrain Tiles](../docs/editor/terrain-tiles.md), [Tile Animation](../docs/editor/tile-animation.md), [Sprite Sheet Slicer](../docs/editor/sprite-slicer.md), [Atlas Region Editor](../docs/editor/atlas-region.md), [Generate Normal Map](../docs/editor/normal-map.md), [Node Reference](../docs/editor/node-reference.md) |
| Extending the editor | [Plugins](../docs/editor/plugins.md) (writing them: [plugin guide](docs/plugin_guide.md)) |

Every command, its shortcut and where it works is on
[Keyboard Shortcuts](../docs/editor/keyboard-shortcuts.md), generated from
the one action table (`actions.odin`) that drives the keys, the menus and
the command palette.

---

## 3. Features and their guides

What the nodes and engine features do, and how to set them up in the
editor, is in their guides and node pages:

| Feature | Where |
|---|---|
| Materials and shaders | [Scripting guide: Materials](../engine/SCRIPTING.md), [Post Effect](../docs/nodes/PostEffectNode.md) |
| Lighting | [Light](../docs/nodes/LightNode.md) |
| Draw order | [`engine/docs/draw_order.md`](../engine/docs/draw_order.md) |
| Save data | [Saving and loading](../docs/tutorials/saving.md) |
| Text, dialogue, localization | [Text](../docs/nodes/TextNode.md), [Dialogue](../docs/nodes/DialogueNode.md) |
| Nine-slice, parallax, lines, trails | [Nine Slice](../docs/nodes/NineSliceNode.md), [Parallax](../docs/nodes/ParallaxNode.md), [Line](../docs/nodes/LineNode.md), [Trail](../docs/nodes/TrailNode.md) |
| Navigation | [`engine/docs/navigation.md`](../engine/docs/navigation.md) |
| Skeletons (Spine, DragonBones) | [`engine/docs/skeletal_animation.md`](../engine/docs/skeletal_animation.md) |
| Accessibility | [`engine/docs/accessibility.md`](../engine/docs/accessibility.md) |
| Advanced cameras, camera follow | [`engine/docs/advanced_camera.md`](../engine/docs/advanced_camera.md), [Camera](../docs/nodes/CameraNode.md) |
| Audio buses, sound effects | [`engine/docs/audio_mixer.md`](../engine/docs/audio_mixer.md), [Sound Effect](../docs/nodes/SoundNode.md), [Mixer tab](../docs/editor/tab-mixer.md) |
| Controls menus (player rebinding) | [`engine/docs/input_rebinding.md`](../engine/docs/input_rebinding.md) |
| Paths | [`engine/docs/paths.md`](../engine/docs/paths.md) |
| Visibility notifiers | [`engine/docs/visibility.md`](../engine/docs/visibility.md) |
| Joints, one-way platforms, collision layers | [Joint](../docs/nodes/JointNode.md), [Static Body](../docs/nodes/StaticBodyNode.md), [Settings](../docs/editor/settings.md) |
| Collision shapes | [Viewport: editing collision shapes](../docs/editor/viewport.md) |
| Aseprite files | [`engine/docs/aseprite.md`](../engine/docs/aseprite.md) |
| Crash and bug reports | [`engine/docs/crash_reports.md`](../engine/docs/crash_reports.md) |
| Import settings | [`engine/docs/import_settings.md`](../engine/docs/import_settings.md) |
| Components (prefabs) | [`engine/docs/components.md`](../engine/docs/components.md) |
| Web and Android export | [`engine/docs/web_export.md`](../engine/docs/web_export.md), [`engine/docs/android_export.md`](../engine/docs/android_export.md) |

The engine's open gaps and everything fixed so far are listed in [`engine/GAPS.md`](../engine/GAPS.md).

---

## 4. Build and Run Commands

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

# Regenerate the Keyboard Shortcuts page's list from the action table
bin/editor --dump-shortcuts docs/editor/keyboard-shortcuts.md

# Memory diagnostics: the heap through Odin's tracking allocator; every 600
# frames the live bytes, the allocation sites that grew and the temp arena
# (editor/mem_track.odin)
odin build editor -out:bin/editor_mem -define:RAYZR_MEM_TRACK=true -debug
```

The project templates (`templates/`) are built by
`scripts/templates/make_templates.py` and played by
`scripts/templates/test_templates.py` (CI).

Temp memory (`fmt.tprintf`, `context.temp_allocator`) lives for one frame:
the editor and the game free it after drawing. Keep an owned copy of
anything that must outlive the frame (node constructors copy their name and
text into the node's arena).
