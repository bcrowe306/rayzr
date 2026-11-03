# Editor tour

A map of the editor window: what each part is for and where to read more.
The numbers on each screenshot match the list below it. (The screenshots are
taken by the editor's own test drives, so they show this version.)

## The window

![The editor window](../images/editor_overview.png)

Panels dock wherever you drag them. **View > Workspaces** switches between
layouts - *Default*, *Level Design* (a big viewport), *Scripting* (the Code
tab in the middle), *Animation* (a tall timeline) and any you save; pick
*Default* to get the standard layout back. The
[editor manual](../../editor/README.md) describes every panel in depth.

## The toolbar

![The toolbar](../images/editor_toolbar.png)

| Shortcut | Action |
|---|---|
| **Q / W / E / R / T** | Select, move, rotate, scale, pan |
| **F5 / F6** | Play the project / play the current scene |
| **F7** | Simulate the scene inside the editor |
| **Shift+F5** | Stop |
| **Cmd+S** | Save the scene (Ctrl on Windows and Linux) |
| **Cmd+Shift+P** | The command palette: every action, searchable |
| **F1** | This manual's page for the panel with focus (Help > Help for <panel>) |

**Help > Keyboard Shortcuts** (Cmd+Shift+K) lists every shortcut, and
**Settings** lets you change them.

## Selecting and editing nodes

![A selected node](../images/editor_selection.png)

A scene is a tree of **nodes**. Selecting one - in the viewport or the
Scene panel - shows it in the **Inspector**:

- **Transform**: position, rotation, scale and origin, plus draw order
  (layer, Z index, Y-sort).
- **The node's own properties**: a sprite's texture, a camera's follow
  mode, a body's collision shapes... hover any of them for its help.
- **Script**: attach a Lua script; its declared properties appear here.
- **Signals**: connect the node's events (a timer's `timeout`, an area's
  `body_entered`) to script methods.

Every property is documented in the [node reference](../../docs/generated/nodes.json).

## Adding nodes

![The Add Node dialog](../images/editor_add_node.png)

**Cmd+A** (or **+** in the Scene panel) opens **Add Node**: type to search,
pick a node, **Create**. It is added under the selected node.

Every node type has its own icon, in Add Node, the Scene panel and the
Inspector. Empty places say what to do: an empty scene in the tree and the
viewport, an empty Console.

## Tabs and modes

- **Game / Level** (top left) switch between the scene editor and the
  [level editor](../../engine/docs/level_editor.md) for LDtk projects.
- **Scene tabs** above the viewport hold each open scene; each keeps its
  own camera, selection and undo history.
- The **Code** tab edits Lua scripts with completion, hover docs, go to
  definition, rename and a debugger ([Code tab](../../editor/CODE_EDITOR.md)).
- The bottom panel has the **Console**, **Animation** timeline,
  **Particles**, **State machine** graph, **Mixer**, **Profiler**, project
  **Search** and the live **Game** tree while the game runs.
