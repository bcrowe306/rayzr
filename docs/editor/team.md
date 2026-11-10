# Working in a team

Rayzr projects are folders of text files, so they work with git (or any
version control). Scenes, components and custom node types are JSON, written
so that a change makes a small diff: each node has a stable `uid` that stays
through renames and moves, and saving the same scene always writes the same
text.

## When to use it

- Several people edit one project and merge their work.
- You keep a project in git and want readable diffs of scene changes.
- You generate scenes with a script, or edit them by hand, and then open them
  in the editor.

## Small diffs

The editor writes a scene the same way every time:

- the keys in a fixed order, numbers to at most 4 decimals, one value per
  line where it helps a diff;
- every node with a `uid`: a reference to a node (a signal connection, a
  component override) names its `uid`, not its path, so moving or renaming a
  node changes only that node's lines;
- values left at their default aren't written for most fields.

A file the editor didn't write (by hand, or made by a script) is in a
different layout. The first time someone saves it in the editor the whole
file changes, and in a team that's a merge conflict waiting to happen. Format
such files first:

### Format Scene Files

**Tools > Format Scene Files** rewrites every scene (`*.scene.json`) and
component (`*.component.json`) file of the project as the editor saves it.
Nothing changes in the game: only the layout, and a `uid` for each node that
didn't have one.

- Files open in a scene tab are left alone; they're written in the same
  layout when you save them.
- A file the rewrite would lose something of is left as it is, with a
  warning in the Console naming the value, e.g. an old key the editor no
  longer reads, or a file from a newer Rayzr.
- A node given a uid by formatting gets one made from the file's path and the
  node's place in the tree, so formatting the same file twice gives the same
  text.

From a terminal (scripts, CI, a git hook), the editor does the same:

```sh
"Rayzr Editor" --fmt scenes/ components/      # rewrite them
"Rayzr Editor" --fmt --check .                # exit 1 if a file isn't formatted
```

On macOS the editor binary is
`/Applications/Rayzr Editor.app/Contents/MacOS/editor`. `--fmt` takes files
and folders: folders are searched for scene and component files (hidden
folders such as `.rayzr` are skipped). It finds each file's project from the
`project.json` above it.

## Tips

- Format a project once before you start sharing it, and commit that change
  on its own.
- Generating scenes with a script? Run `--fmt` on its output (Rayzr's own
  templates do: `scripts/templates/make_templates.py`).
- A `--fmt --check` step in CI keeps hand-edited files formatted.

## Related

- [Toolbar and menus](toolbar-menus.md) (the Tools menu)
- [Components](../../engine/docs/components.md) (overrides refer to nodes by uid)
