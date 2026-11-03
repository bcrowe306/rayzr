# Writing documentation

The documentation at [rayzr.app/docs](https://rayzr.app/docs/) is built
from this repository on every release and every merge to `main`, so it
always matches the code. Most of it you edit as Markdown; the reference is
generated.

## Where pages come from

| Source | Becomes |
|---|---|
| `docs/*.md` | Getting started, the editor tour, these pages |
| `engine/docs/*.md` | The engine guides (one per feature, each with a tutorial) |
| `editor/README.md`, `editor/CODE_EDITOR.md`, `editor/docs/*.md` | The editor manual, Code tab and plugin guides |
| `engine/SCRIPTING.md` | The scripting guide |
| `engine/definitions/engine_api.lua` | **Generated**: the Lua API reference (descriptions and `Example:` lines) |
| `editor/definitions/editor_api.lua` | **Generated**: the editor plugin API |
| `engine/node_registry.odin`, the Add Node catalog, `engine/property_docs.odin` | **Generated**: the node reference, via `docs/generated/nodes.json` |
| `docs/nodes/<NodeType>.md` | Extra text and examples on that node's reference page |
| `templates/*/README.md` | The templates page |

`docs/site.json` is the navigation: sections and the pages in them. A new
guide must be listed there - CI fails otherwise.

## Node pages

Every node type has a page: on the site's node reference, and in the
editor's **Node Reference** window. It opens from a node's menu in the
hierarchy (**Documentation**), the **?** button in the Inspector header,
**Shift+F1** on the selected node, and **Help > Node Reference**.

Both build the page the same way. The generated parts come from the code:
the description and category from the Add Node catalog, the properties table
from the node's Inspector properties and `engine/property_docs.odin`, and
the Lua methods from `engine/definitions/engine_api.lua`. The hand-written
part is `docs/nodes/<NodeType>.md`, which the editor embeds when it's built.
Write it with these sections, leaving out the ones that don't apply:

| Section | What goes in it |
|---|---|
| `## What it's for` | One paragraph: what the node does in a game. |
| `## When to use it` | The situations it's for, and which node to use instead for nearby ones, linked by their file name (`KinematicBodyNode.md`). |
| `## Using it` | The editor steps: adding it, its shapes or assets, the Inspector settings that matter. |
| `## How it works` | Behaviour beyond the properties table: order of events, limits, performance. |
| `## Signals` | Each event it raises, when, and its value (`body_entered`: the body). |
| `## Example` | A complete script using it, ready to paste. |
| `## Screenshot` | The image `../images/node_<NodeType>.png`, taken by a drive (below). |

Don't repeat the properties table or the Lua method list: they're added
under the hand-written part. Link other nodes as `<NodeType>.md` in the same
folder; the editor and the site both turn that into the node's page.

Node screenshots come from `tests/drive/docs_nodes_<category>.drive`. Each
`screenshot node_<NodeType>` line becomes `docs/images/node_<NodeType>.png`
(see "Screenshots with callouts" below). The installed editor ships
`docs/images/`, so the screenshots show in the Node Reference too.

## Tutorials

A tutorial builds one small project step by step (`docs/tutorials/`, the
site's **Tutorials** section). Each has three parts that stay in step:

| Part | Where |
|---|---|
| The page | `docs/tutorials/<name>.md`, listed in `docs/site.json` |
| The finished project | `docs/tutorials/<name>/`: a real project (`project.json`, scenes, scripts, a few small CC0 assets) |
| Its drive | `tests/drive/tutorial_<name>.drive`: performs the steps in a copy of the finished project (`# drive: project docs/tutorials/<name>`) and takes the page's screenshots |

- **Screenshots**: `screenshot tutorial-<name>_<step>` lines;
  `scripts/docs/screenshots.sh tutorial_<name>` copies them to
  `docs/images/tutorial-<name>_<step>.png`. A page showing an image that
  isn't there fails the checks below.
- **The download**: the page links the project folder,
  `[Download the finished project](<name>/)`. On GitHub that opens the
  folder; the site exporter zips the folder's committed files into
  `downloads/tutorials-<name>.zip` and links that instead.
- **It plays**: `tests/tutorials/runtime_tests.json` runs each finished
  project in the runner with scripted input and checks the result (CI:
  `scripts/templates/test_templates.py --suite tests/tutorials/runtime_tests.json`).

Write in the same voice as [Your first game](../getting-started/first-game.md):
numbered steps for what to do in the editor, the whole script for each
file, and only the editor labels, menus and API names that exist.

## Checks (CI)

`python3 scripts/docs/check_docs.py` runs on every pull request. It fails
when:

- `docs/generated/nodes.json` is out of date (regenerate it with
  `bin/editor --dump-docs docs/generated/nodes.json` or `task docs:nodes`);
- a node type has no Add Node description, or a property has no help line;
- a guide in `engine/docs/` or `editor/docs/` isn't in `docs/site.json`;
- a page links to a file that doesn't exist, or an image is missing (a
  tutorial's screenshot too);
- a Lua API function has no description.

`odin test editor` also checks that the
[Keyboard Shortcuts](../editor/keyboard-shortcuts.md) page lists every
editor command with its default shortcuts: after changing the action table
(`editor/actions.odin`), run
`bin/editor --dump-shortcuts docs/editor/keyboard-shortcuts.md`.

The website then builds the pages and checks every link between them.

## Screenshots with callouts

Screenshots come from editor test drives, so they stay current:

1. Write or extend a drive in `tests/drive/docs_*.drive`. Before a
   `screenshot <name>` line, add `annotate <target> <label>` lines - a
   target is a drive item (`@toolbar.play`, `@hier:Player`), a panel
   (`@window:inspector`, `@window:viewport`, `@window:scene`, `@window:assets`,
   `@window:console`, `@window:toolbar`, `@window:statusbar`,
   `@window:preview`, `@window:code`, the Level tab's `@window:level-canvas`,
   `@window:level-levels`, `@window:level-layers` and `@window:level-panel`,
   and the `@window:welcome`, `@window:shortcuts` and `@window:noderef`
   windows; `Drive_Window` in the editor's code registers more) or a node
   (`@node:Player`). A target can't contain spaces.
2. Run `scripts/docs/screenshots.sh` (needs a display). It copies the shots
   and their `.annotations.json` into `docs/images/`.
3. Use the image in a page on a line of its own:
   `![The toolbar](../images/editor_toolbar.png)`. The site draws a numbered
   marker on each callout and lists the labels under the image.

## Preview the site locally

```sh
python3 scripts/docs/export_site.py --out build/docs_bundle   # this checkout's docs
# then, in a checkout of github.com/bcrowe306/rayzr_website:
ENGINE_DIR=../rayzr npm run sync && npm run dev
```
