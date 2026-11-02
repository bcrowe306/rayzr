# Project compatibility

From 1.0 on, a project made with one Rayzr 1.x release opens in every later
1.x release. This page says what that covers and what happens to files from
older and newer versions.

## Use it for

- **Upgrading Rayzr**: open your project in the new editor and keep working.
  Nothing has to be converted first.
- **Teams on different versions**: know what happens when someone on an
  older editor opens a file saved by a newer one.
- **Reviewing changes**: saved files are stable, so version control shows
  only what you changed.

## What is versioned

Every file the editor saves in a project carries a `"format"` number: an
integer for that kind of file, not the Rayzr version.

| File | Format key |
|---|---|
| Scenes (`*.scene.json`) | `"format"`, the first key |
| Components (`*.component.json`) | `"format"`, beside the root node's keys |
| Custom node types (`*.node.json`) | `"format"` |
| Resources (`*.resource.json`) | `"format"` |
| `project.json`, including export presets | `"format"` |
| Import settings (`<asset>.import.json`) | `"format"`, when the file exists |
| Tileset terrains and tile animations (`<image>.tileset.json`) | `"format"` |
| Level generator graphs (`*.levelgen.json`) | `"format"` |
| Exported games (`.rayzr`) | the package header's version |

Files written by other tools are left as they are: LDtk projects, Aseprite
files, SVGs, Spine and DragonBones files, images and audio.

## Older files

A file from an older Rayzr is upgraded in memory when it loads, and written
in the current format the next time it is saved. Files you never open stay
as they were. Exported games upgrade their files as they load, too.

Files from before formats existed (0.x releases) count as format 0, and
they are guaranteed to open. That includes the older shapes the engine still
reads, such as physics, camera and particle blocks from early scenes and
pixel origins.

## Newer files

A file saved by a newer Rayzr loads with what this version understands, and
a warning is logged. The editor opens it **read-only**: a banner over the
Scene panel says so, and Save leaves the file alone, so whatever the newer
version added isn't lost. **Save As** writes a copy in this version's format.

The same applies to files the editor would otherwise write without opening
them: applying an override to a component, re-saving the users of a custom
node type, import settings, `project.json`, terrains and level graphs.

A runner refuses a `.rayzr` package exported by a newer version and names
the package version it needs.

## Stable saves

Scenes save keys in a fixed order and numbers with fixed precision, and
every node keeps its `uid`. Loading a scene and saving it without changes
writes the same text again, so a diff shows only real edits.

## For engine contributors

`engine/file_format.odin` holds each kind's current format
(`FORMAT_CURRENT`) and its migration chain (`FORMAT_MIGRATIONS`). Each
migration step turns format N into N + 1, taking the parsed JSON and
returning JSON.

To change a file's shape:

1. Raise the kind's format.
2. Add the step that converts older files.
3. Add a fixture of the old format in `tests/formats/`. The
   `engine/file_format_test.odin` tests load every fixture.
4. Note the change here.
