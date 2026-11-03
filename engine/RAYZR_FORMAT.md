# Rayzr Package Format Specification (`.rayzr`) & JSON Project Architecture

The **Rayzr package** format (`.rayzr`; before the rename: `.ore`, magic `ORE1` - still read) is a high-performance, single-file container and serialization standard designed for data-driven game development. It decouples game design from compiled Odin source code, allowing complete games, scenes, physics configurations, node graphs, assets, and Lua scripts to be declared in portable files and manipulated via visual GUI editors.

---

## 1. Architectural Overview

```
Development Mode (Loose Files)           Export / Distribution Mode (.rayzr)
┌─────────────────────────────────┐      ┌─────────────────────────────────┐
│ my_game/                        │      │ release_game.rayzr              │
│  ├── project.json               │ ───► │  ├── [RYZ1 Header: 32 bytes]      │
│  ├── scenes/                    │ Pack │  ├── [Contiguous Compressed     │
│  │    ├── main.scene.json       │      │  │    Payloads: Textures, Audio,│
│  │    └── level2.scene.json     │      │  │    JSON, Lua Scripts]        │
│  └── assets/                    │      │  └── [Table of Contents (TOC)   │
│       ├── textures/hero.png     │      │       Offsets, Sizes, CRC32]    │
│       ├── audio/bgm.ogg         │      └─────────────────────────────────┘
│       └── scripts/player.lua    │
└─────────────────────────────────┘
```

The engine provides seamless **dual-mode resolution**:
1. **Loose Directory Mode (Git-Friendly Development)**: The engine reads loose files directly from disk (`project.json`, `scenes/*.scene.json`, loose PNG/WAV/Lua files). Fast iteration without re-packaging.
2. **Packaged Container Mode (`.rayzr` Release)**: All assets, scenes, and project configurations are compressed into a single binary archive. Can be embedded directly into release game binaries with `#load` or loaded from disk as a standalone portable package.

---

## 2. Binary Container Specification (`RYZ1`)

The `.rayzr` file format uses an append-friendly layout where data payloads precede the Table of Contents (TOC), allowing high-throughput streaming and memory mapping:

```
+-------------------------------------------------------------+
| Header (32 bytes)                                           |
|   magic: [4]u8 ('R', 'Y', 'Z', '1')                          |
|   version: u32 (1)                                          |
|   fileCount: u32                                            |
|   tocOffset: u64                                            |
|   tocSize: u64                                              |
|   flags: u32 (reserved)                                     |
+-------------------------------------------------------------+
| Data Payloads (Variable length, contiguous)                 |
|   File 0: [Raw / Zlib-compressed byte slice]                |
|   File 1: [Raw / Zlib-compressed byte slice]                |
|   ...                                                       |
+-------------------------------------------------------------+
| Table of Contents (TOC at tocOffset)                        |
|   For each entry:                                           |
|     pathLen: u16                                            |
|     path: [pathLen]u8 (UTF-8, normalized relative path)     |
|     dataOffset: u64                                         |
|     compressedSize: u64                                     |
|     uncompressedSize: u64                                   |
|     compression: u8 (0 = Store, 1 = Deflate)                |
|     crc32: u32 (IEEE 802.3 CRC32 checksum)                  |
+-------------------------------------------------------------+
```

### Compression Strategy
- Individual files with uncompressed length $\le 64$ bytes or where compressed length $\ge$ uncompressed length are stored uncompressed (`Store`).
- Large files (scripts, scenes, JSON, raw textures, waveforms) are compressed using standard `zlib.deflate` (`Deflate`).
- Compressed payloads are decompressed on-demand with `zlib.uncompress` directly into target buffers.

---

## 3. Project Configuration Schema (`project.json`)

The root configuration defines window settings, physics parameters, and registered scenes:

```json
{
  "name": "My Galactic Game",
  "version": "1.0.0",
  "initial_scene": "scenes/main.scene.json",
  "window": {
    "title": "My Galactic Adventure",
    "width": 1280,
    "height": 720,
    "virtual_width": 1280.0,
    "virtual_height": 720.0,
    "target_fps": 60
  },
  "physics": {
    "gravity": [0.0, 980.0]
  },
  "scenes": [
    "scenes/main.scene.json",
    "scenes/credits.scene.json"
  ]
}
```

---

## 4. Scene Graph Schema (`*.scene.json`)

Scenes define the active camera, debug boundaries, and hierarchical node graphs. Node types and properties map directly to engine structures:

```json
{
  "name": "MainScene",
  "draw_bounds": false,
  "camera": {
    "target_position": [640.0, 360.0],
    "zoom": 1.0
  },
  "root": {
    "type": "Node",
    "name": "RootNode",
    "children": [
      {
        "type": "StaticBodyNode",
        "name": "GroundPlatform",
        "position": [640.0, 680.0],
        "scale": [1.0, 1.0],
        "rotation": 0.0,
        "enabled": true,
        "visible": true,
        "layer": 0,
        "physics": {
          "shape": {
            "type": "box",
            "size": [1280.0, 40.0],
            "density": 0.0,
            "friction": 0.8,
            "restitution": 0.0
          }
        }
      },
      {
        "type": "DynamicBodyNode",
        "name": "PlayerCrate",
        "position": [640.0, 150.0],
        "scale": [1.0, 1.0],
        "rotation": 0.0,
        "enabled": true,
        "visible": true,
        "layer": 1,
        "physics": {
          "gravity_scale": 1.0,
          "fixed_rotation": false,
          "linear_damping": 0.05,
          "angular_damping": 0.1,
          "shape": {
            "type": "box",
            "size": [48.0, 48.0],
            "density": 1.5,
            "friction": 0.5,
            "restitution": 0.2
          }
        },
        "script": {
          "path": "assets/scripts/crate_physics.lua",
          "properties": {
            "bounciness": 1.2,
            "can_shatter": true
          }
        }
      },
      {
        "type": "TextureNode",
        "name": "HeroSprite",
        "position": [400.0, 300.0],
        "texture_path": "assets/textures/hero.png",
        "pivot": [0.5, 1.0]
      }
    ]
  }
}
```

---

## 5. Supported Node Types in JSON

| Node Type | Key Properties | Physics Support |
|---|---|---|
| `Node` | Basic transform (`position`, `scale`, `rotation`, `enabled`, `visible`, `layer`) | Hierarchy transform |
| `TextureNode` | `texture_path`, `pivot` (the origin: a fraction of the image, `[0.5, 0.5]` = centre; also on animations, AnimationPlayers, nine-slices, text). An older pixel `origin` is still read. | Sprite rendering |
| `DynamicBodyNode` | `physics.gravity_scale`, `physics.fixed_rotation`, `physics.shape` | Box2D dynamic body |
| `StaticBodyNode` | `physics.shape` | Box2D static geometry |
| `CharacterMoverNode` | `character.speed`, `character.jump_speed`, `character.radius`, `character.height` | Kinematic character controller |
| `AreaNode` | `area.shape` | Overlap & trigger sensor |
| `RaycastNode` | `raycast.direction`, `raycast.length` | Geometric raycaster |
| `ParticleEmitterNode` | `particles.amount`, `particles.lifetime`, `particles.emitting` | Particle simulation |
| `TimerNode` | `timer.duration`, `timer.auto_start`, `timer.loop` | Frame-independent timer |
| `CameraNode` | `camera.zoom`, `camera.target_position` | 2D camera controls |

---

## 5b. Level Generator Schema (`*.levelgen.json`)

A procedural level generator (#142, #171): a graph of nodes whose output is
a level. Each node makes or changes a grid of numbers the size of the level
(0 = empty / low, 1 = solid / high); outputs turn grids into tiles,
components or entities. The guide is [`docs/level_generator.md`](docs/level_generator.md);
this is the file's full shape. Code: `Gen_GraphParse` / `Gen_GraphSerialize`
(`engine/level_gen.odin`).

```json
{
  "format": 1,
  "size": [64, 40],
  "seed": 7,
  "output": 5,
  "nodes": [
    {"id": 1, "type": "random_fill", "params": {"density": 0.48}, "pos": [40, 60]},
    {"id": 2, "type": "cellular", "inputs": {"in": 1}, "params": {"iterations": 5}},
    {"id": 5, "type": "tile_output", "inputs": {"in": 2},
     "params": {"empty": -1, "tile_w": 16, "tile_h": 16},
     "rules": [{"min": 0.5, "max": 1, "tiles": [12, 13, 14]}],
     "tileset": "textures/cave.png"}
  ],
  "frames": [{"title": "Caves", "pos": [20, 20], "size": [420, 260], "color": [0.35, 0.55, 0.85, 1]}]
}
```

### Top level

| Key | Type | Required | |
|---|---|---|---|
| `format` | integer | no | The file format (currently 1; a file without it is format 0, read the same). Newer than the reader: read as well as possible, the editor opens it read-only. |
| `size` | `[w, h]` | no | The level in cells, 1-4096 each (default `[32, 24]`). |
| `seed` | integer | no | The default seed (0 when missing). A seed passed when generating replaces it. |
| `output` | integer | no | The id of the node whose result is the level (its tiles fill the main TileMap). Missing or 0: the last `tile_output` that writes tiles, else the last `tile_output`, else the last node. |
| `nodes` | array | no | The nodes (below), in any order. |
| `frames` | array | no | The editor's comment frames (#171, part 1). Generation ignores them. Written only when there are any. |

### A node

| Key | Type | | |
|---|---|---|---|
| `id` | integer > 0 | required | Unique in the file; links and `output` name nodes by it. |
| `type` | string | required | A built-in type (below) or the name of a type registered from Odin (`Gen_RegisterNode`). An unknown type fails the whole file. |
| `inputs` | object | optional | Port name -> the id of the node it reads. A port not listed reads zeros. A cycle is an error when generating. |
| `params` | object | optional | Parameter name -> value. A number; `true` / `false` for toggles (also 1 / 0); a choice parameter by name (`"op": "max"`; its index also works). Missing parameters take their defaults; unknown ones are ignored. Writers write every parameter (except a `tile_output`'s `writes` when it is `tiles`). |
| `pos` | `[x, y]` | optional | Where the editor draws it (canvas units); not written when `[0, 0]`. |
| `rules`, `patterns`, `tileset`, `layer` | | `tile_output` | Below. |
| `component` | string | `entity_output` | The `.component.json` it places. |
| `script` | string | `script` | The `.lua` file (returning `function(ctx)`). |

### Node types and parameters

Defaults in brackets; choices list their names (the first is the default).
`seed` parameters are added to the graph's seed (each node's own seed also
mixes in its id).

| Type | Inputs | Parameters |
|---|---|---|
| `constant` | | `value` (1) |
| `noise` | | `type`: `value` / `perlin` / `simplex` (#171, part 2), `scale` (16), `octaves` (3, 1-8), `persistence` (0.5), `seed` (0) |
| `random_fill` | | `density` (0.45), `seed` (0) |
| `gradient` | | `direction`: `horizontal` / `vertical` / `radial` |
| `border` | | `width` (1) |
| `rect` | | `x` (0), `y` (0), `w` (8), `h` (8), `value` (1) |
| `rooms` | | `min_size` (4), `max_size` (10), `corridor` (1), `seed` (0) |
| `walker` | | `steps` (400), `walkers` (1), `brush` (1), `seed` (0) |
| `lines` | | `count` (6), `min_length` (6), `max_length` (20), `thickness` (1), `direction`: `horizontal` / `vertical` / `both` / `any` (default `both`), `seed` (0) |
| `rectangles` | | `count` (5), `min_size` (4), `max_size` (12), `thickness` (1), `filled` (false), `seed` (0) |
| `circles` | | `count` (5), `min_radius` (3), `max_radius` (8), `thickness` (1), `filled` (false), `seed` (0) |
| `threshold` | `in` | `value` (0.5), `invert` (false) |
| `invert` | `in` | |
| `remap` | `in` | `from_min` (0), `from_max` (1), `to_min` (0), `to_max` (1) |
| `blur` | `in` | `radius` (1) |
| `cellular` | `in` | `iterations` (4), `birth` (5), `survive` (4), `edge_solid` (true) |
| `dilate`, `erode` | `in` | `iterations` (1) |
| `combine` | `a`, `b` | `op`: `add` / `subtract` / `multiply` / `min` / `max` / `mask` / `average` |
| `scatter` | `in` | `chance` (0.05), `spacing` (4), `seed` (0) |
| `poisson_scatter` | `mask` | `radius` (4, 1-256), `attempts` (30, 1-100), `seed` (0) (#171, part 2) |
| `surface` | `in` | `side`: `top` / `bottom` / `any` |
| `flood_fill` | `in` | `x` (-1), `y` (-1), `open`: `low` / `high`, `diagonal` (false) |
| `regions` | `in` | `mode`: `keep_largest` / `remove_small`, `min_size` (20), `open`, `diagonal` |
| `connect_regions` | `in` | `width` (1), `min_size` (0), `open`, `diagonal` |
| `path` | `in` | `placement`: `left_right` / `top_bottom` / `farthest` / `custom`, `start_x`, `start_y`, `end_x`, `end_y` (0), `width` (1), `open`, `output`: `level` / `path` / `start` / `end` |
| `check` | `in` | `min_open` (0.25), `connected` (true), `open`, `diagonal` |
| `script` | `a`, `b` | `p1`..`p4` (0), `seed` (0); and `script` |
| *(registered)* | as registered | as registered |
| `tile_output` | `in` | `empty` (-1), `tile_w` (16), `tile_h` (16), `writes`: `tiles` / `components` (#171, part 3) |
| `entity_output` | `in` | `max` (0 = every point); and `component` |

### Tile output

| Key | | |
|---|---|---|
| `rules` | array | Each `{"min", "max", "tiles", "terrain", "component"}`: a cell whose value is in `min`..`max` (defaults 0..1) takes the first rule that holds it. `tiles`: tile indices, one picked per cell by the seed (`"tile": n` is read as a one-tile list). `terrain` (optional): a terrain of the output's tileset instead of tiles - auto-tiled by neighbours. `component` (optional, #171): the `.component.json` the cell gets when the output writes components. Writers write `min`, `max` and `tiles` always, the others when set. |
| `patterns` | array | Optional; applied after the rules. Each `{"min", "max", "chance", "cells", "tiles"}`: `cells` are the 3 x 3 around a cell, row by row (`1` in `min`..`max`, `-1` not, `0` any; the middle is the cell), `chance` 0..1 (default 1), defaults `min` 0.5, `max` 1. Written only when there are any. |
| `tileset` | string | Optional: the image its tile numbers count in (the editor's palette and previews; its terrains come from `<image>.tileset.json`). |
| `layer` | string | Optional: the TileMap it fills, by name, next to the main one (its sibling, else its child). Missing: the main TileMap. |

`params.writes` picks what it writes (#171, part 3):

- `tiles` (the default, not written): tile indices into the map's cells.
- `components`: components painted on the **component layer** of the map
  (`layer` names which; missing: the main one) - each cell the first rule
  with a `component` whose range holds its value, the rule's tiles unused.
  A component bigger than a cell covers its footprint (centred on the
  cell, kept inside the map); cells an earlier one covers are skipped, and
  instances already under a footprint are replaced. The map's tiles stay.
  What a generation paints is tagged `levelgen` and replaced by the next.
  Such an output is never the default `output`.

### Frames

Each `{"title", "pos", "size", "color"}`: the title (string), the top-left
and size in canvas units (`size` at least 40 x 40; default 300 x 200) and
the colour `[r, g, b, a]` 0-1 (three values: alpha 1; default
`[0.35, 0.55, 0.85, 1]`). Moving a frame in the editor moves the nodes whose
middles are inside it.

### Compatibility

Format 1 since #326. The keys added later - `frames`, `noise.type`,
`poisson_scatter`, `params.writes` and a rule's `component` - are optional
and additive: a file without them reads as before, so they didn't change
the format number. Graphs that use none of them save exactly as before. An
older Rayzr reads a newer graph without them: it ignores frames and the
`writes` parameter, and fails on a node type it doesn't know.

---

## 6. Engine API Usage in Odin

```odin
// 1. Load project directly from loose folder during development
game->loadProject("my_project_folder")

// 2. Export folder into standalone .rayzr container package
game.exportRayzr("my_project_folder", "exports/game.rayzr")

// 3. Load project directly from .rayzr container package
game->loadProject("exports/game.rayzr")

// 4. Serialize active scene to JSON string (for editor save operations)
jsonString := e.Scene_SerializeToJSON(activeScene)
```

---

## 7. Engine API Usage in Lua

```lua
-- Load a complete project (.rayzr or directory)
Project.load("assets/demo_project.rayzr")

-- Read arbitrary asset file from mounted .rayzr archive or disk
local scriptSource = Project.read_file("assets/scripts/orbiting_drone.lua")

-- Check file existence
if Project.has_file("scenes/bonus.scene.json") then
    -- File exists
end

-- Serialize current scene to JSON
local jsonStr = Project.serialize_scene()

-- Pack loose project directory into .rayzr package
Project.export_rayzr("assets/demo_project", "assets/demo_project.rayzr")
```
