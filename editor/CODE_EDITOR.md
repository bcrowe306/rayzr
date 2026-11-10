# Code editor (the Code tab)

The editor's Code tab edits Lua scripts (and shaders) with Zed-style
editing, `lua-language-server` support and engine-aware extras. This page
lists everything it does and every shortcut; the Lua API itself is in
[`engine/SCRIPTING.md`](../engine/SCRIPTING.md).

On macOS **Cmd** is the primary modifier (Ctrl on Windows / Linux); the
tables write Cmd. Every command is also in the command palette
(Cmd+Shift+P) and can be rebound in Settings > General > Keymap.

Source: `editor/code_editor.odin` (input, drawing), `code_commands.odin`
(commands), `code_editor_lsp.odin` (completion, hover, LSP), `code_*.odin`
(features), on the `odin_editor` packages (`buffer`, `syntax`, `lsp`).
Drives (UI tests) in `tests/drive/code_*.drive`, `lua_*.drive`.

## Opening scripts

Double-click a script in Assets, the edit button beside a node's script in
the Inspector, *Open Script* in the scene tree's menu, or double-click a
console message with `file.lua:LINE`. *New Script* opens a dialog with
templates (see SCRIPTING.md). Cmd+P goes to a file; Cmd+Shift+T reopens the
last closed tab; Cmd+W closes one.

## Tabs

- **Preview tabs**: a file reached by navigating - go to definition,
  symbol and search results, references, peek - opens as a preview (dim
  title, eye icon) that the next preview replaces, so jumping around
  doesn't pile up tabs. Editing it, double-clicking its tab or *Keep Open*
  in its menu makes it a normal tab; opening the file yourself does too.
- **Pinned tabs** (tab menu > *Pin Tab*) sit first with a pin, have no
  close button, and are skipped by Close Others / to the Right / Saved /
  All (Cmd+W still closes one).

## Files changed on disk, local history

- A script changed outside the editor (another editor, git) **reloads by
  itself** when you have no unsaved edits - as one undoable edit. With
  unsaved edits a bar over the code asks: **Reload** (the disk version;
  your edits stay in Undo) or **Keep Mine** (saving writes them over it).
- **Local history**: every save keeps a copy in
  `<project>/.rayzr/history/<script>/` (the 30 newest; `.rayzr` is never
  packaged into games). Tab menu > *Local History...* (or the palette)
  lists them by date with a preview; **Restore** puts one in the buffer -
  undoable, not saved until you save.

## Editing

| Shortcut | Command |
|---|---|
| Cmd+X / Cmd+C / Cmd+V | Cut / copy / paste (see Clipboard) |
| Cmd+Z / Cmd+Shift+Z | Undo / redo |
| Cmd+/ | Toggle comment |
| Cmd+] / Cmd+[ | Indent / outdent |
| Alt+Up / Alt+Down | Move line(s) |
| Cmd+Shift+D, Alt+Shift+Down / Alt+Shift+Up | Duplicate line down / up |
| Cmd+Shift+K | Delete line |
| Enter | New line, indented like this one (one level more after `function ...)`, `then`, `do`, `{`, `(`, `repeat`, `else`) |
| Cmd+Enter / Cmd+Shift+Enter | Insert line below (indented like Enter) / above (this line's indentation) |
| Ctrl+J | Join lines |
| Cmd+Backspace | Delete to line start |
| Tab | Snippet expansion / next snippet placeholder / indent |

Brackets and quotes close themselves; typing a closer steps over it; a
selection typed over with a bracket is wrapped.

## Clipboard

- **Cut / copy with nothing selected** takes the whole line(s). Pasting
  such a copy inserts it as whole line(s) above the cursor's line - wherever
  the cursor is in that line - like Zed and VS Code.
- **Several cursors**: when the clipboard has as many lines as there are
  cursors, each cursor gets its own line.
- **Paste re-indents**: multi-line text pasted at the start of a line (only
  indentation before the cursor) is re-indented to that line's indentation,
  keeping its own relative indentation.
- **Clipboard history** (Cmd+Shift+V): the last 20 copies and cuts; Up /
  Down / Enter (or click) pastes one, Esc closes.
- **Copy Path / Copy Absolute Path / Copy Location** (`scripts/x.lua:12`)
  in the command palette and the context menus.

## Context menus

**Right-click in the code** moves the caret to the click (unless it is
inside a selection) and opens the menu. First comes what is under the click:

- a **string naming a node** (`find_node("Player")`, a `get_node` path from
  the script's node, any node name of the open scene): *Select in the Scene
  Tree*;
- a **string naming a project file** (`"textures/ship.png"`): *Reveal in
  Assets*, and *Open* for scripts and shaders;
- a **symbol**: Go to Definition, Find All References, Rename Symbol,
  Scripting Reference (F1);
- a **selection**: Copy as Markdown (a fenced `lua` block) and **Wrap In** -
  `if condition then ... end` (the condition selected, type to replace it),
  `do ... end`, `local function name() ... end`; the lines are indented.

Then Cut / Copy / Paste / Paste from History, the **Selection**, **Go To**,
**Lines** and **Refactor** submenus, Format Document, Find / Replace, and
Copy Path / Copy Location. Every entry shows its shortcut; entries the
language server provides are disabled until it is ready. Esc closes a menu.

**Right-click a line number**: Add / Remove Breakpoint, Add / Edit
Condition..., **Run to Here** (while paused: continues to that line with a
temporary breakpoint), Select Line, Copy Location.

**Right-click a tab**: Save, Save As..., Find Usages of This Script, Close,
Close Others, Close to the Right, Close Saved, Close All, Copy Path, Copy
Absolute Path, Reveal in Assets, Reveal in Finder. Tabs with unsaved changes
are never closed by the bulk closes.

## Selection

| Shortcut (macOS / Windows, Linux) | Command |
|---|---|
| Cmd+A | Select all |
| Cmd+L | Select line (again: the next line too) |
| Ctrl+Shift+Right / Alt+Shift+Right | **Expand selection** to the next enclosing unit |
| Ctrl+Shift+Left / Alt+Shift+Left | **Shrink selection** back one step |

Expand selection grows through the code's structure (Zed's "select larger
syntax node"): the word -> a call (`find_node("Player")`) -> a string's
contents -> the string -> inside brackets -> the brackets -> the line ->
the body of the enclosing `function` / `if` / `for` / `while` / `do` /
`repeat` block or `{ }` table -> the whole block -> the next block out ->
the file. The structure comes from `code_structure.odin`: bracket pairs and
blocks outside strings and comments, computed once per edit only when a
feature needs it.

## Multi-cursor

| Shortcut | Command |
|---|---|
| Cmd+D | Select the next occurrence |
| Cmd+Shift+L | Select all occurrences |
| Cmd+Alt+D | **Skip occurrence**: select the next one instead of this one |
| Cmd+Alt+Up / Down | Add a cursor above / below |
| Shift+Alt+I | **A cursor at the end of every selected line** |
| Cmd+U | **Undo cursor**: back to the cursors before the last added |
| Cmd+Shift+M | **Select inside** the quotes / brackets around the caret (again: the next pair out) |
| Alt+click | Add a cursor (on one: remove it) |
| Alt+drag | **Column (box) selection**: a cursor per line, the same columns |

## Brackets and indentation

- The **bracket pair at the caret** is outlined. **Cmd+Shift+\\** jumps to
  the matching bracket; away from a bracket, to the closer of the brackets
  around the caret.
- **Rainbow brackets**: brackets are coloured by nesting depth (gold,
  violet, blue, repeating); an unmatched bracket is red.
- **Indent guides**: a thin line at each indentation level (blank lines
  take the next code line's); the guide of the block around the caret is
  brighter.
- Both are in Settings > Code Editor (`rainbow_brackets`, `indent_guides`
  in settings.ini).

## Display

- **Other uses of the caret's word** get a faint background (identifiers
  only, not strings or comments).
- **Visible whitespace**: dots for spaces and lines for tabs - inside
  selections by default (Settings > Code Editor > Show Whitespace: None /
  In Selections / All).
- **Soft wrap** (Alt+Z, or Settings > Code Editor): long lines wrap at the
  Code area's width at a space, continuation rows indented like the line
  and marked in the gutter; Up / Down move by screen row. There is no
  horizontal scrolling while it is on.

## Inlay hints

Parameter names appear before call arguments - `Audio.play_sound(path:
"hit.wav", volume: 0.5)`, `self.node:set_rotation(degrees: angle)` - for
the engine API (from `engine/definitions/engine_api.lua`, compiled into the
editor) and for the functions the file defines. A hint is left out when the
argument already says it (`x` for `x`, `self.speed` for `speed`). Hints are
inline: the text after them moves right, and clicks and carets skip them.
**Ctrl+Alt+H** (or Settings > Code Editor > Inlay Hints) turns them off.
They are computed per line when first shown and cached until the next edit.

## Code and the Inspector

- **Show in Inspector** (the context menu on a symbol, or the palette): on
  `self.<exported property>`, `self.node.<field>` or a `get_property` /
  `set_property("path")` string, the node that runs the script is selected
  and that property's Inspector row lights up (scrolled into view).
- **Find in Script** (right-click a script property's name in the
  Inspector): the script opens at the property's declaration in its
  `properties` table, the name selected. *Copy Path* copies the property's
  path (`script.speed`, `rotation`).
- Dragging a property's name into a script inserts a `get_property` /
  `set_property` (Shift) call (see SCRIPTING.md).

## Colours and images

- **Colour swatches**: a small swatch sits before colour tables -
  `{r, g, b}` / `{r, g, b, a}` with 0..1 values (one written with a dot),
  or 0..255 values after a key saying colour (`color`, `colour`, `tint`,
  `rgb`); `{1, 2, 3}` gets none. **Click** it for a colour picker: the table
  is rewritten as you pick, in its own style (0..1 or 0..255, 3 or 4
  values), as undoable edits. Settings > Code Editor > Colour Swatches.
- **Image preview**: hovering a string that names an image of the project
  (`"textures/ship.png"`) shows the image and its size.

## Breadcrumbs and sticky scroll

- **Breadcrumbs** (a bar above the code): the file › the function › the
  blocks around the caret (`PlayerShip:update › if self.cooldown_timer > 0
  then`). Click one to go to its first line.
- **Sticky scroll**: while the top of the view is inside a block, the
  first lines of up to 3 enclosing blocks stay pinned at the top with
  their line numbers (and a shadow under them). Click one to go there.
- Both can be turned off in Settings > Code Editor.

## Overview strip and git gutter

- **Overview strip** (right edge, beside the scrollbar - the minimap): the
  whole file at a glance - errors and warnings, find matches, uses of the
  caret's word, breakpoints, changes since the last commit, the caret, and
  the visible part. Click or drag in it to scroll there.
- **Git gutter**: lines added (green bar), modified (blue bar) and removed
  (red triangle) since the last commit, at the gutter's right edge. The
  committed text is read with `git show HEAD:<file>` on a worker thread
  when the script opens and when it is saved; the comparison (a Myers line
  diff) runs once per edit after typing pauses. Files outside git or not
  committed show nothing.

## Folding

A `function` / `if` / `for` / `while` / `repeat` / `do` ... `end` block, a
`{ }` table spanning lines or a run of comment lines folds to its first and
last line, with a **… N lines** chip after the first (click it to unfold).

| Shortcut | Command |
|---|---|
| (gutter arrow) | Fold / unfold - the arrow shows when the mouse is over the gutter, and always on a folded line |
| Cmd+Alt+[ / Cmd+Alt+] | Fold the innermost block around the caret / unfold |
| Cmd+Alt+Shift+[ / ] | Fold all functions, tables and comment runs / unfold all |

Up / Down step over a fold; a caret inside a block that gets folded moves
to its first line. Folds stay with their block through edits above them
and disappear when the block does.

The display (rows on screen: folds and wrapped lines) comes from
`code_display.odin`, rebuilt only when the text, the wrap width or the
folds change; drawing touches only the visible rows.

## Navigation

| Shortcut | Command |
|---|---|
| Cmd+Shift+O | **Go to symbol in file** (outline): functions, script properties, top-level locals |
| Cmd+T | **Go to symbol in project**: the functions of every script |
| Cmd+P | Go to file |
| Ctrl+- / Ctrl+Shift+- | **Go back / forward** through the places the caret jumped from |
| F8 / Shift+F8 | Next / previous **problem** (error or warning; wraps around) |
| Alt+F8 / Alt+Shift+F8 | Next / previous **change** since the last commit (git gutter) |
| Cmd+Shift+\\ | Matching bracket |
| Ctrl+G | Go to line |

Back / forward remember a place whenever the caret moves more than 10
lines or to another file - go to definition, references, go to line,
breadcrumbs, sticky lines, problems, search results all come back with
Ctrl+-. While the debugger is paused F8 is Continue (the problem commands
step aside: a disabled command never takes another's shortcut).

## Find

| Shortcut | Command |
|---|---|
| Cmd+F / Cmd+Alt+F | Find / find and replace |
| Cmd+G / Cmd+Shift+G (F3 / Shift+F3) | Next / previous match |
| Ctrl+G | Go to line |
| Cmd+Shift+F | **Find in files** (the bottom panel's Search tab) |

**Find in files** searches the project's scripts and shaders (`.lua`,
`.fs`, `.vs`, `.glsl`; open files as edited, not as saved) with Match Case
(Aa), Whole Word (ab) and Regex (.\*), started with the selection when
there is one. Matches are listed by file with their line, the match
highlighted; click one to open it there. **Replace All** (not with regex)
changes open files as undoable edits and writes the others, then searches
again. Up to 2000 matches are listed.

## Language server

**Peek definition** (Alt+F12) and **peek references** (Alt+Shift+F12) show
the target's code in a box under the caret line - syntax coloured, its line
marked - without leaving the file; references list on the left (Up / Down
pick). Enter or a double-click opens it, Esc or a click outside closes.

Completion (Ctrl+Space, as you type), signature help (Cmd+Shift+Space),
hover, diagnostics (squiggles, gutter, status line), go to definition (F12
/ Cmd+click), find references (Shift+F12), rename (F2), format
(Cmd+Shift+I). Engine names complete from the generated project types
(SCRIPTING.md > Completion of project names). F1 opens the Scripting
Reference at the symbol.

Diagnostics stay current (#403): the generated `project_types.lua` is kept
open in the server and each rewrite sent as a didChange
(`Code_LspPushLibraryFile` - lua-language-server 3.x ignores
`workspace/didChangeWatchedFiles`, and its own watcher can skip a rewritten
file as "already loaded"), and `diagnostics.workspaceEvent` is `OnChange`,
so a change to any script or to the types re-checks the others a second
later. Runtime problems clear when their script is edited. The diagnostics
presets (Project Settings > Lua Checks) are `LUA_CHECKS_SETTINGS` in
`lua_project.odin`, written to `.luarc.json` and sent as the server's
settings. `scripts/luals_check.sh` (CI) runs `lua-language-server --check`
over the templates, tutorials and demo project after `editor --lua-setup`
and fails on any warning.

**Rename** (F2): type the new name; the **Rename Preview** lists every
change by file - each line before (red) and after (green) - and nothing
changes until **Apply** (Enter); Cancel (Esc) drops them. Applied changes
are one undo step per file.

## Code actions

**Cmd+.** (or the **lightbulb** in the gutter, shown on the caret's line
when there is something to fix) lists fixes for the caret:

- a node name / path in `find_node` / `get_node` / `get_child` that isn't in
  the open scene: *pick one* - a filtered list of the scene's nodes (paths
  from the script's node for `get_node`) replaces the string;
- an input action in `Input.is_action_pressed` / `_down` / `_released`
  that the project doesn't have: *add it* to Project Settings > Input
  (then give it keys there);
- lua-language-server's quick fixes for the diagnostics on the line.

Up / Down / Enter or a click applies one; Esc closes.

## Refactoring

| Shortcut | Command |
|---|---|
| Cmd+Alt+V | **Extract local**: the selected expression becomes `local value = ...` above the statement |
| Cmd+Alt+M | **Extract method**: the selected lines become `function Cls:new_method()` after the current function, `self:new_method()` in their place |
| Cmd+Alt+N | **Inline variable**: on a `local x = expr` line, `expr` replaces `x` at its uses (to the end of its block or until `x` is reassigned) and the line goes |
| (Refactor menu) | **Toggle property access**: `node:get_property("p")` <-> `node.p`, `node:set_property("p", v)` <-> `node.p = v` |
| (Refactor menu) | **Toggle Vec2**: `{x, y}` <-> `Vec2(x, y)` around the caret |
| (Wrap In menu) | `if ... then` / `do` / `local function` around the selected lines |

Extract leaves a cursor on each copy of the new name, both selected: type
the real name once. Everything is one undo step. Rename (F2) is in
Language server.

## Debugging

Click a line number for a breakpoint; right-click it for a condition. The
Game tab shows the call stack, locals and watches; F8 / F10 / F11 /
Shift+F11 continue and step. See SCRIPTING.md > Debugging.

**Inline values**: while paused, each line of the paused function (up to
the paused line) shows the current values of the locals it uses after its
end - `dt = 0.0167, self = {vx = 0, ...}` - from the selected stack frame;
they go when the game runs on.

## Speed and memory

Everything derived from the text is computed once per edit and only when
something needs it: tokens per line (cached), the structure (brackets,
blocks), the display map (folds, wrap), inlay hints per shown line, the git
diff (after typing pauses), whole-file word uses. Drawing touches only the
rows on screen. Per-document caches are freed when the tab closes, the
rest at exit.

To check for leaks: `EDITOR_DEFINES=-define:RAYZR_MEM_TRACK=true
scripts/editor_drive.sh code_soak_mem` - 40 rounds of editing, folding,
wrapping, find, clipboard and menus; the log
(`editor_screenshots/drive/code_soak_mem/editor.log`) reports the live heap
every 600 frames (flat after warm-up) and what is left at exit.

