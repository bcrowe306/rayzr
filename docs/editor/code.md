# Code tab

The **Code** tab edits your game's Lua scripts (and shaders) inside the
editor, with completion, hover help, errors and go to definition from
`lua-language-server`, and extras that know your project: node names,
asset paths and engine functions. It opens next to the Viewport the first
time you open a script. This page is an overview; every command and
shortcut is in the [full reference](../../editor/CODE_EDITOR.md).

![The Code tab](../images/editor_code.png)

## When to use it

- **Writing and fixing scripts**: a node's behaviour, a global script, a
  test in `tests/`.
- **Finding your way round the code**: go to a function's definition, see
  where something is used, rename it everywhere.
- **Debugging**: breakpoints in the gutter, then step through a game started
  with Play (see [Playtesting](playtesting.md)).
- **Looking up the API**: hover an engine function for its description, or
  press **F1** on it for the Scripting Reference.
- For a node's exported values, use the [Inspector](inspector.md);
  scripts' `properties` show up there.

## Opening it

The Code tab exists while a script is open. Open one by:

- double-clicking a `.lua` (or shader) file in [Assets](assets.md);
- the code button beside a node's script in the Inspector (**Edit script**),
  or **New Script...** there for a new one;
- right-click a node in the [Scene panel](scene-tree.md) > **Open Script**;
- double-clicking a Console message with `file.lua:LINE`, or a failure in
  the [Tests tab](tab-tests.md);
- **Cmd+P** (Go to File) and typing the script's name.

**Cmd+2** focuses the Code tab again, **Cmd+1** the Viewport.

### New Script

**New Script...** (the Inspector, the scene tree's menu, the **+** in
Assets, the command palette) opens a dialog: the file name under
`scripts/` (a taken name gets `_2`) and a template, with a preview of the
script it writes. The templates: **Empty**, **Resource Class**,
**Platformer Character**, **Top-Down Character**, **Enemy Patrol**, **UI
Menu**, **Pickup**, **Door / Trigger**, **Accessibility Menu** and
**Controls Menu (rebinding)**. Opened from a node, the script is named
after the node and attached to it, and the template made for its type is
picked first and starred. Up / Down pick a template, Enter (or a
double-click) creates it.

## What's in it

On macOS the shortcuts use **Cmd**; on Windows and Linux read **Ctrl**.
Where the table says **Ctrl**, it means the Control key on every system.

### Tab strip

One tab per open file. A dot marks unsaved changes. A file reached by
jumping (go to definition, search results) opens as a **preview** tab: dim,
with an eye, replaced by the next preview until you edit it or double-click
its tab. Drag tabs to reorder them.

Right-click a tab: **Save**, **Save As...**, **Local History...**, **Find
Usages of This Script**, **Close**, **Pin Tab** / **Unpin Tab**, **Keep
Open** (a preview), **Close Others**, **Close to the Right**, **Close
Saved**, **Close All**, **Copy Path**, **Copy Absolute Path**, **Reveal in
Assets**, **Reveal in Finder**. Tabs with unsaved changes are never closed
by the bulk closes.

### Breadcrumbs

A bar above the code: the file, then the function and blocks around the
caret (`PlayerShip:update › if ...`). Click one to go to its first line.
While you scroll inside a block, its first lines stay pinned at the top
(sticky scroll). Both can be turned off in Settings > Code Editor.

### Gutter

- **Line numbers**. Click one to add or remove a **breakpoint**. Right-click
  it: **Add Breakpoint** / **Remove Breakpoint**, **Add Condition...** /
  **Edit Condition...**, **Run to Here** (while paused), **Select Line**,
  **Copy Location**.
- **Fold arrows** (when the mouse is over the gutter): fold a function,
  `if`, loop or table to one line; the **… N lines** chip unfolds it.
- **Problems**: errors and warnings from the language server and from the
  last Simulate or Play, also as squiggles under the code (see
  [Problems](#problems)).
- **Changes** since the last git commit: green (added), blue (changed), red
  (removed).
- A **lightbulb** on a line with a quick fix (**Cmd+.**).

At the right edge, the **overview strip** shows the whole file: problems,
find matches, breakpoints, changes and the visible part. Click it to scroll
there.

### Find bar

**Cmd+F** opens it over the code:

| Control | What it does |
|---|---|
| **Find** field | The text. **Enter**: next match, **Shift+Enter**: previous. |
| **Aa** / **ab** / **.\*** | Match case, whole word, regular expression. |
| Count | `3 of 12`, **No results** or **Invalid regex**. |
| Up / down arrows | Previous / next match (also **Cmd+G** / **Cmd+Shift+G**, **F3** / **Shift+F3**). |
| Swap arrows | Show the **Replace** row: **Replace** (this match) and **Replace All**. |
| **X** | Close (**Esc**). |

**Cmd+Alt+F** (or **Cmd+H**) opens it with Replace. **Cmd+Shift+F**
searches every script in the bottom panel's [Search tab](tab-search.md).

### Status line

Under the code: a **Save** button (highlighted while there are unsaved
changes), the caret's **Ln** and **Col**, the language, the error and
warning counts, and the language server's state (`lua-language-server` in
green when it's ready).

### The context menu

Right-click in the code. First come entries for what's under the mouse:

- a string naming a node: **Select ... in the Scene Tree**;
- a string naming a project file: **Reveal in Assets** (and **Open ...** for
  a script or shader);
- a symbol: **Go to Definition**, **Peek Definition**, **Find All
  References**, **Rename Symbol**, **Scripting Reference for Symbol**,
  **Show in Inspector**;
- a selection: **Copy as Markdown** and **Wrap In** (`if ... end`,
  `do ... end`, `local function ... end`).

Then **Cut**, **Copy**, **Paste**, **Paste from Clipboard History**; the
**Selection**, **Go To**, **Lines** and **Refactor** submenus; **Format
Document**; **Find**, **Find and Replace**, **Find in Files**; **Copy
Path**, **Copy Location (path:line)**. Each entry shows its shortcut;
entries that need the language server are greyed out until it's ready.

### Most-used shortcuts

| Shortcut | Command |
|---|---|
| Cmd+S | Save the file |
| Cmd+Z / Cmd+Shift+Z | Undo / redo |
| Cmd+/ | Toggle comment |
| Cmd+] / Cmd+[ | Indent / outdent |
| Alt+Up / Alt+Down | Move line up / down |
| Cmd+Shift+D | Duplicate line down |
| Cmd+Shift+K | Delete line |
| Cmd+D | Select next occurrence (another cursor) |
| Cmd+Shift+L | Select all occurrences |
| Cmd+Alt+Up / Cmd+Alt+Down | Add cursor above / below |
| Ctrl+Space | Show completions |
| Cmd+Shift+Space | Show signature help |
| F12 (or Cmd+click) / Shift+F12 | Go to definition / find all references |
| Alt+F12 | Peek definition |
| F2 | Rename symbol |
| **F1** | **Scripting Reference** for the symbol under the caret (elsewhere F1 opens the focused panel's manual page; **Help > Help for Code Tab** opens this page) |
| Cmd+. | Code actions (quick fix) |
| Cmd+Shift+I | Format document |
| Cmd+Shift+O / Cmd+T | Go to symbol in file / in project |
| Ctrl+G | Go to line |
| Ctrl+- / Ctrl+Shift+- | Go back / forward |
| F8 / Shift+F8 | Next / previous problem (while paused in the debugger F8 is Continue) |
| Cmd+Alt+[ / Cmd+Alt+] | Fold / unfold |
| Alt+Z | Toggle soft wrap |
| Cmd+Shift+V | Paste from clipboard history |
| Cmd+W / Cmd+Shift+T | Close tab / reopen closed tab |
| Ctrl+Tab / Ctrl+Shift+Tab | Next / previous tab |
| Cmd+= / Cmd+- / Cmd+0 | Bigger / smaller / reset font size |

Every command is also in the command palette (**Cmd+Shift+P**) and can be
rebound in Settings > General > Keymap.

**Cmd+S** writes the file, and scripts running in Simulate (or the game
started with Play) reload it.

### Snippets

Type `ready`, `update`, `connect`, `properties`, `tween`, `on` or `method`
at the start of a statement and press **Tab**: it expands, and Tab moves
through its placeholders. See the
[scripting guide](../../engine/SCRIPTING.md).

### Scripting Reference

**F1** on an engine name (or **Help > Scripting Reference**) opens the
**Scripting Reference** window: `engine/SCRIPTING.md` by section, with a
**Search** box, rendered with its headings, tables and highlighted Lua.
Opened on a symbol, a card on top shows the function's signature,
description, example and parameters, and the section that covers it is
shown below.

## Problems

The language server checks every script as you type: red for errors,
yellow for warnings, blue for information, and a faint underline for hints
(unused locals, code that never runs, a value that may be nil). Hints and
information aren't counted in the status line. Hover a squiggle for the
message and its check's name, e.g. `(undefined-field)`; **Cmd+.** offers
the server's fixes, including turning that check off for the line or the
file.

**Fixed problems clear without saving.** A fix in another script (a method
you added, a typo you corrected) clears the warnings it caused in this one
about a second after you stop typing - the server checks the other scripts
again after every change. So do changes to the project types (a new input
action, node, scene or exported property). Problems from the last Simulate
or Play are about the text that ran: they go when you edit that script, and
come back on the next run if they're still there.

**How strict it is** is a project setting, **Project Settings > General >
Scripting > Lua Checks**, written into the project's `.luarc.json` (so VS
Code checks the same way):

| Preset | What it reports |
|---|---|
| **Relaxed** (default) | lua-language-server's checks, but a value that may be nil (`need-check-nil`: `get_parent()`, `find_node()`, `get_script()`...) is a hint, not a warning, and trailing spaces and lowercase globals (a test file's `test_*` functions) aren't reported. |
| **Standard** | lua-language-server's defaults, without the trailing-space hints. |
| **Strict** | lua-language-server's defaults, with unused and redefined locals and lowercase globals as warnings. |

Style checks (`codestyle-check`, `spell-check`, `name-style-check`) are off
in all three. For one line or file, a comment does it:
`---@diagnostic disable-next-line: need-check-nil`, or
`---@diagnostic disable: lowercase-global` at the top. A value the editor
can't type - a node from `get_children()`, a name built at run time - is a
plain `Node`; tell the server what it is with `---@cast node UIButtonNode`
(or `---@type` on a local), and give an exported node property its type with
`---@field map TileMapNode` on the script's class.

## Files the editor writes for Lua

**Lua tooling files.** The editor writes the engine API definitions to
`<project>/.rayzr/definitions/` (refreshed when the editor's copy changes)
and a `.luarc.json` pointing at them. So `lua-language-server` knows every
engine type, in the Code tab and in VS Code or any LuaLS editor opening the
project folder. It has the project's [Lua Checks](#problems) preset. A
`.luarc.json` you wrote yourself (one that doesn't point at
`.rayzr/definitions`) is left alone. Hidden
files and folders (`.rayzr/`, `.luarc.json`) are never packaged into games.
The language server comes with the editor; Settings > Code Editor can
point at another one.

**Project types.** Next to them the editor writes
`.rayzr/definitions/project_types.lua` from your project: `InputAction`
(a misspelled action is an error, and names complete inside the quotes),
`SceneName`, `NodeName`, `NodeTag`, `ScenePath` / `TexturePath` /
`AudioPath` / `ComponentPath` / `LevelPath` / `ScriptPath`, animation,
state machine, save and locale names, LDtk entity / level / layer / enum
names (`LdtkEntityName`, `LdtkLevelName`, `LdtkLayerName`, `LdtkEnumName`),
a class per script with its exported properties (so `self.speed` is a
number; a `---@field` the script declares itself wins), and
`Scene.create("TextureNode")` / `Scene.find_nodes_of_type` returning that
type's class. It is rewritten half a second after saves, imports, renames
and settings changes, and the language server takes the new version at once.

## Walkthrough

Make the ship turn faster and check the change:

1. In Assets, double-click `scripts/player_ship.lua`. The Code tab opens
   next to the Viewport.
2. Press **Cmd+Shift+O**, type `update` and press Enter: the caret jumps to
   the function, and the breadcrumbs show `PlayerShip:update`.
3. Press **Cmd+F**, type `rotation_speed`. Press Enter to step through the
   matches, then **Esc**.
4. Put the caret on an engine call such as `Input` and press **F1**: the
   Scripting Reference opens at it. Close it.
5. Type `self.node:` on a new line inside `update`: the completion list
   shows the node's methods. Press **Esc**, then **Cmd+Z** to take it back.
6. Click the line number of a line in `update` to add a breakpoint, and
   click it again to remove it.
7. Press **Cmd+S**. The tab's dot goes; press **F5** to play the game with
   the saved script.

## Tips

- Play saves modified scenes, not scripts: press **Cmd+S** (or **Cmd+Alt+S**,
  Save All) before **F5**. Running tests saves both.
- A script changed outside the editor reloads by itself when you have no
  unsaved edits; otherwise a bar asks **Reload** or **Keep Mine**.
- Every save keeps a copy: tab menu > **Local History...** restores one.
- Drag a node from the Scene panel, an asset, an Inspector property or
  event, an input action or an animation into a script to insert code that
  uses it: see [Inspector > Drag into a script](inspector.md#drag-into-a-script).
- Full reference (every command, the language server, refactoring,
  debugging): [Code editor](../../editor/CODE_EDITOR.md). Related:
  [Node in Lua](../lua/Node.md), [Playtesting](playtesting.md),
  [Tests tab](tab-tests.md).
