# Publishing a plugin or template

Anyone can list a plugin or a project template in the
[Registry](registry.md), where every Rayzr user can find and install it.
You keep the code in your own GitHub repository and publish a release; the
registry only lists it.

## What you need

- Your plugin or template in its own **GitHub repository**, public, with a
  `README.md` (shown in the Registry once installed) and a `LICENSE`.
- A **release** with a zip of it attached.
- A **pull request** to
  [bcrowe306/rayzr-registry](https://github.com/bcrowe306/rayzr-registry)
  adding an entry to its `index.json`.

## 1. Make it

**A plugin** is a folder with a `plugin.json` and its Lua files: start one
with **Tools > New Plugin...** ([Plugins](plugins.md), and
[Writing editor plugins](../../editor/docs/plugin_guide.md)). In
`plugin.json`:

- `"version"`: the version you're publishing (`"1.0.0"`).
- `"editor"`: the oldest Rayzr Editor it works with (`">=1.1.0"`).
- `"permissions"`: only what it needs - `"process"` (it runs programs with
  `Editor.run`) and `"network"` (`Editor.http`). Users see these before
  they install it.

**A template** is a project folder with a `template.json` beside its
`project.json`:

```json
{
  "name": "Tower Defense",
  "description": "Waves of enemies, towers to place, upgrades and a shop.",
  "icon": "map",
  "order": 50
}
```

and a `preview.png` (16:9, about 320 by 180) for its card in **Welcome >
New Project**. `icon` is one of `person-running`, `dungeon`,
`jet-fighter`, `puzzle-piece`, `rocket`, `gamepad`, `book`, `map`,
`bezier-curve`. The editor copies everything else into the new project
(not `template.json`, `preview.png`, `.rayzr/` or `.luarc.json`).

## 2. Zip it and publish a release

Zip the folder so that `plugin.json` (or `template.json`) is at the top of
the zip, or inside one folder at the top (GitHub's own "Source code" zips
work too: that folder is left out when installing). Only plain and deflate
compression, no encryption - what every zip tool writes by default.

```bash
cd my_plugin && zip -r ../my_plugin-1.0.0.zip . -x '.*'
```

Create a GitHub release (tag `v1.0.0`) and attach the zip. Then take its
SHA-256:

```bash
shasum -a 256 my_plugin-1.0.0.zip
```

(`sha256sum` on Linux, `Get-FileHash` in PowerShell.) Never change a
release's zip after listing it: the SHA-256 would no longer match, and the
Registry refuses to install it. Publish a new version instead.

## 3. Add it to the index

Fork [rayzr-registry](https://github.com/bcrowe306/rayzr-registry) and add
your entry to the `entries` in `index.json`:

```json
{
  "id": "level_notes",
  "kind": "plugin",
  "name": "Level Notes",
  "author": "Your Name",
  "description": "Notes on each level, in a panel next to the Inspector.",
  "version": "1.0.0",
  "url": "https://github.com/you/level-notes/releases/download/v1.0.0/level_notes-1.0.0.zip",
  "sha256": "9f2c...64 hex digits...",
  "rayzr": ">=1.1.0",
  "license": "MIT",
  "repo": "you/level-notes",
  "homepage": "https://you.example/level-notes",
  "screenshot": "https://raw.githubusercontent.com/you/level-notes/main/screenshot.png",
  "tags": ["levels", "notes"],
  "permissions": []
}
```

| Field | |
|---|---|
| `id` | Its folder name when installed: lower-case letters, digits, `_` and `-`. Unique in the index; for a plugin, use the folder name your `plugin.json` is in. |
| `kind` | `"plugin"` or `"template"`. |
| `name`, `author`, `description` | What the Registry shows. |
| `version` | The release's version. The Registry offers an update when this is newer than the one installed. |
| `url` | The release's zip. |
| `sha256` | The zip's SHA-256 (step 2). |
| `rayzr` | The oldest editor it works with. Older editors show it greyed out. |
| `license` | Its license (an SPDX name: `MIT`, `Apache-2.0`, `CC0-1.0`). |
| `repo` | `owner/name` on GitHub: its source, linked from the Registry. |
| `homepage` | Optional: a page of its own (else the repository's). |
| `screenshot` | Optional: an image url (PNG or JPEG, about 960 by 540). |
| `tags` | Optional: words people may search for. |
| `permissions` | A plugin's: the same list as its `plugin.json`. A plugin asking for more than this list isn't installed. |

Check it first with the Rayzr repository's checker, which fetches your
zip and checks it as the editor will:

```bash
python3 -I scripts/registry/check_index.py index.json --download
```

Open a pull request. A check validates the entry (the fields, a zip at the
url whose SHA-256 matches, the manifest inside), and a maintainer reads
the plugin's code before merging. Once merged it's in everyone's Registry
(they fetch the index every hour, or on **Refresh**).

## Updating it

Publish a new release with a new zip, then open a pull request changing
your entry's `version`, `url` and `sha256` (and `rayzr` if it now needs a
newer editor). People who installed it see **Update to ...**.

## Testing your entry first

Point the editor at a local index before you open the pull request:

1. Put a copy of `index.json` with your entry next to your zip. `url` and
   `screenshot` may be file names next to the index (`"url":
   "level_notes-1.0.0.zip"`).
2. **Settings > General > Registry Index**: the path to that `index.json`.
3. **Tools > Registry**, **Refresh**, and install it. The Console says
   what's wrong if it isn't installed.
4. Clear **Registry Index** afterwards to go back to the official list.
