# Level editor (the Level tab)

The editor has two root tabs under the toolbar: **Game** (scenes, nodes,
scripts) and **Level**, a level editor for LDtk projects. Levels are edited
in place: the file stays an LDtk project (`.ldtk`, with `.ldtkl` files for
external levels), so it still opens in [LDtk](https://ldtk.io), and the
game's LDtk Level nodes read it. When you save, the Game tab's levels reload
it (so does a running game with script hot reload on).

What it edits, the way LDtk does:

| | |
|---|---|
| **Worlds and levels** | add, delete, rename, move (drag in the canvas; GridVania snaps to the world grid), resize, depth, background colour, level fields |
| **IntGrid layers** | brush, rectangle, fill, erase, pick; values with names and colours |
| **Auto layers** | LDtk's rule engine: rule groups (optional ones per level, biomes), patterns up to 9x9, random tiles, stamps, flips, chance, Perlin, modulo / checker, offsets, break on match, "killed by" layers. The tiles are the ones LDtk would generate. |
| **Tiles layers** | stamps of one or more tiles picked in the tileset, X / Y flips, stacking |
| **Entities** | place, move, resize, delete; field values (Int, Float, Bool, String, Multilines, Color, Enum, Point, FilePath) |
| **Definitions** (bottom tabs) | layers (order, grid, opacity, offset, tileset, auto source), IntGrid values, entities (size, colour, pivot, resizing, tile, fields), enums, tilesets, level fields |
| **Terrains** | rules for a 3x3 terrain block from one click |
| **Per-tile data** | custom data text, enum tags, **animated tiles** |

The engine side is `engine/ldtk_doc*.odin` (see [Engine API](#engine-api)).

## Opening a project

- Click the **Level** tab (Cmd+Shift+2; Cmd+Shift+1 goes back to Game).
  Without a file it lists the project's `.ldtk` files and has **New LDtk
  Project...** (a level with an IntGrid "Collisions" layer and an
  "Entities" layer, ready to paint).
- Or in Assets, right-click a `.ldtk` > **Edit in Level Tab**; or select an
  LDtk Level node and click **Edit in Level Tab** in the Inspector (or the
  map button in the LDtk bottom tab): it opens at that node's level.

## The Level tab

```
 toolbar:  file | Brush Rect Erase Fill Pick Select MoveLevels | Undo Redo |  Play  | grid  IntGrid  fit  zoom  Save
 ┌──────────┬───────────────────────────────────────┬────────────┐
 │ Levels   │               canvas                  │ Layers     │
 │          │                                       │            │
 │          ├───────────────────────────────────────┤ palette of │
 │          │ World Level Tilesets Entities Enums   │ the active │
 │          │ Layers Rules Project   (bottom panel) │ layer      │
 └──────────┴───────────────────────────────────────┴────────────┘
```

The panels dock like the Game tab's: drag their edges to resize them,
drag a panel's tab to move it.

- **Levels** (left): the active world's levels (a combo picks the world in
  multi-world projects); **+** adds a level where you click next in the
  canvas (Esc cancels; **Shift+click** the **+**: right of the active one,
  in a free spot), the bin deletes it. Double-click frames a level.
- **Layers** (right): the active level's layers, top first, as
  *Type: Name*. Drag a layer by its grip to put it in another order (in
  every level); the eye hides it (LDtk's per-level visibility, saved).
  **+** opens **New Layer** (type, identifier, grid size, tileset, the
  IntGrid layer an auto layer reads); the sliders button opens the Layers
  tab. Under the list: the palette of the active layer - IntGrid values,
  the tileset, entities, or the rule groups of an auto layer (optional
  groups have a check box per level; **Re-run rules** regenerates the
  level's auto tiles).
- **Canvas**: the active world, the active level on top and the others
  dimmed. Click another level to make it active. Middle drag or
  Space + drag pans, the wheel zooms around the mouse. The bottom line shows
  the cell and IntGrid value under the mouse.
- **Bottom panel**:
  - **World**: the layout (Free, GridVania, linear), the world grid, and a
    map of the levels (click one to open it).
  - **Level**: the level's identifier, position, size (Enter applies),
    depth, background and fields; with an entity selected (it switches to
    this tab), the entity's position, size, iid and fields.
  - **Tilesets**, **Entities**, **Enums**: those definitions (tilesets also
    have per-tile custom data, animations and enum tags).
  - **Layers**: each layer's settings and IntGrid values.
  - **Rules**: the auto-layer rules of IntGrid and Auto layers, terrains.
  - **Project**: defaults (grid, new level / entity size), background
    colours, level name pattern, JSON options, level fields.

### Tools and keys

| Tool | Key | IntGrid / Tiles | Entities |
|---|---|---|---|
| Brush | B | paint (right button erases) | place the picked entity (Shift: off the grid) |
| Rectangle | R | drag a rectangle (right button: erase it) | |
| Erase | E | erase | |
| Fill | F | fill the connected area of equal cells | |
| Pick | I | pick the value / tile under the mouse | |
| Select | V | select cells (see *Selection*) | select entities; the corner handle resizes resizable ones |
| Move levels | M | drag levels in the world | |

Also: **1-9** pick an IntGrid value, **X** / **Y** flip the stamp, **G**
grid, **Home** fit, **Cmd+S** saves, **Cmd+Z** / **Cmd+Shift+Z** undo /
redo. Every stroke, move and edit is one undo step (100 steps).

### Tiles

- **Stamp** / **Random** mode (the dice button, **Shift+R**): paint the
  picked tiles as a block, or one of them at random per cell.
- **Stacking** (**Shift+T**): tiles go on top of the cell's tiles instead
  of replacing them (opaque tiles still replace them). Erasing removes the
  top one.
- **Saved groups** (the bookmark button, **Shift+S**): clicking any tile of
  a saved group picks the whole group again; **Alt** + click picks one tile.
- **Shift** + drag with the Brush or Erase draws a rectangle.
- Right-click a layer, then choose **Tileset in this level**, to draw it
  with another tileset in this level only.

### Selection

Like LDtk's Selection tool: use the **Select** tool (V), or hold **Alt**
with any tool.

- Click an entity or a cell to select it. Its layer becomes active, and the
  palette picks its value or tile.
- **Shift** + click adds to the selection or removes from it. **Shift** +
  drag from empty space selects a rectangle, over every visible layer.
- Drag the selection to move it. Cells move by whole cells across all their
  layers; entities snap to the grid (hold **Shift** to move entities
  freely). **Cmd+Alt** + drag copies the selection instead.
- Arrow keys move the selection one cell. **Delete** removes it, **Esc**
  clears it.
- **Cmd+A** selects everything in the layer, **Cmd+Shift+A** everything in
  the level.
- **Cmd+C** / **Cmd+X** / **Cmd+V** copy, cut and paste (it pastes under the
  mouse, into the layers with the same definitions). **Cmd+D** duplicates
  one cell to the right.

A selected entity's **Layer** in the Level tab moves it to another Entities
layer.

### Levels and worlds

- Drag the handles around the active level's edges and corners to resize
  it (snapped to the layer's grid, or to the world grid in GridVania). The
  left and top edges move the level; its content keeps its place.
- Level tab > **Image**: a background image behind the layers - not
  scaled, fit inside, cover, stretched or repeated, with a pivot.
- World tab > **Multiple worlds** / **+ World**: several worlds in one
  project (LDtk's MultiWorlds), each with its own levels, layout, grid and
  new level size. Right-click a world to rename or delete it; the Levels
  panel picks the world.

### Layer definitions

Bottom panel > **Layers**: right-click a layer to copy / cut / paste /
duplicate / reorder / bake / move its entities / delete it. Its form
covers all of LDtk's layer options: documentation, UI colour, grid (cells
keep their coordinates), guide grid, opacity and inactive opacity, offset,
parallax (shown in the canvas), hide in list, hide fields / selectable
when inactive, filter tags; IntGrid values with groups, order and icons;
the auto-layer tileset, biome field and "tiles removed by" layer; Entities
layers' required / excluded tags; Tiles layers' tile pivot.

### Enums and project options

Bottom panel > **Enums**: copy / paste / duplicate / reorder / delete
enums; rename values (fields follow), colours, icons, tags; **Import**
external enums from `.txt`, `.json`, `.hx` or `.cdb` files and sync them
when they change (used values that disappear can be renamed to new ones).
**Project**: file extension, backups on save, minify, external level files,
identifier style (converts every identifier), level name pattern,
defaults, LDtk's advanced flags, a description; **exports** after each
save (PNGs per layer / per level, the simplified format, Tiled maps) and
**custom commands** (manual - Cmd+R -, after loading, before / after saving;
asked once per project before they run).

### Tilesets

Bottom panel > **Tilesets**: copy / paste / duplicate / reorder / delete
tilesets (references are cleared); identifier, image (change / reload; tile
ids remapped when its size changes, as in LDtk), tile size (remapped),
spacing, padding, tags; per tile: custom data, animation, and enum tags
painted over the tile grid.

### Search, view modes, navigation

**Cmd+K** searches levels, layers, entities (also by field value) and
definitions; the lists have filter boxes. Shift+A single layer mode, Alt+R
auto-layer tiles on / off, Shift+H details, Tab zen mode, Shift+E select
empty spaces; Alt+arrows open the neighbouring level; PageUp / PageDown move
between world depths (Shift: move the level). Images, external enum files
and the project file are watched for changes made by other programs.

### Context menus and help

Right-click levels, layers and palette items for their actions: rename,
duplicate, reorder, delete, settings, rules, select all of a value or
entity. Every button and field has a tooltip. Hover anything and press
**F1** (or click a **?**) to open **Help > Level Editor Reference** at that
topic.

## Tutorial: a cave with auto-tiled walls

1. **Level** tab > **New LDtk Project...** > `levels/cave.ldtk` > Create.
2. Copy a tileset image (16x16 tiles, e.g. a 3x3 wall block somewhere in
   it) into the project. Bottom panel > **Tilesets** > *Add from a project
   image*.
3. **Layers** tab: select **Collisions** and set its **Tileset**. The
   Layers panel now shows the tileset under the values.
4. In the Layers panel drag over the 3x3 wall block (corners, edges and the
   middle), then in the **Rules** tab click **3x3** next to **Empty
   group**: nine rules in a group "Terrain 1". (Or click **Assistant** and
   give each wall shape its tile: see *Auto-layer rules*.)
5. Pick value **1 walls** and paint: the walls draw
   themselves - edges where the neighbours are empty, the middle inside.
   Erase with the right button and they follow.
6. **Cmd+S**. Back in the **Game** tab, drop `levels/cave.ldtk` in the
   scene (or Add Level from its menu) and Play: the IntGrid's collisions
   come from the same file (LDtk tab > Collision: *walls* = Solid).

## Tutorial: entities with fields

1. Bottom panel > **Entities** > **Add entity**, call it `Chest`, size
   16x16, a colour, pivot bottom-centre. **Use picked tile** takes the tile
   picked in a Tiles layer's palette as its picture.
2. Under **Fields**: pick *Int* and **Add field** (`int`, rename it in LDtk
   or keep it), then an *Enum* field after adding an enum (**Enums** tab:
   `Rarity` with `Common`, `Rare`).
3. Select the **Entities** layer, pick **Chest** in the palette, click in
   the level to place chests. **V** to move them; the **Level** tab edits
   the selected chest's fields.
4. In the game, entity fields set script properties of the same name (see
   `engine/LDTK.md`, *Entities*).

## Tutorial: animated water

1. In a Tiles layer's palette, pick the frames of the water animation in
   order (drag over them: left to right, top to bottom).
2. Bottom panel > **Tilesets** > your tileset: click the first frame in the
   tile grid, then **Animate with picked tiles**; set **fps**.
3. Paint the first frame (or let a rule place it): it animates in the
   canvas, in the Game tab's viewport and in the game.

The animation is stored in the tile's LDtk custom data, one key per line:

```
anim=40,41,42,43
fps=6
```

You can type the same in LDtk's tileset custom data. Other lines of the
custom data are yours (scripts read them with
`node:ldtk_get_tile(layer, x, y).custom_data`).

## Auto-layer rules

Bottom panel > **Rules** > an IntGrid layer with a tileset, or an Auto layer
(the **Layers** tab sets the tileset, and the IntGrid layer an auto layer's
rules read under **Rules read**):

Three columns: the layers with rules, the layer's groups and rules, and
the picked rule's editor.

- **Assistant** (LDtk's rules wizard): name, value, what the edges are
  next to; click a wall shape (single, walls, corners, turns, T
  crossings, diagonals, full) and **Use picked tiles** for it; shapes
  left empty reuse a mirrored one. **Create rules** writes a group the
  Assistant can reopen (double-click it) and update.
- **Empty group**, **3x3** (terrain from a picked 3x3 block), **Paste** (a
  copied group).
- **+ Rule** in a group: a 3x3 rule placing the picked tile where the
  centre has the picked value.
- Rule editor: the pattern (pick a value above it, **\*** = any; left
  click requires, right forbids, middle clears; size up to 9); tiles
  (individual or stamps with a pivot; **Use picked tiles** / **Add
  picked**; right-click a tile to remove it); out of bounds; break on
  match; flip X / Y; chance; opacity; modulo X / Y with offsets and
  checker; Perlin noise (seed, scale, octaves); tile offsets and random
  offsets; active. The eye in its header shows the cells it matches in
  the canvas.
- Right-click a rule: edit, show matching cells, enable / disable,
  duplicate, copy, paste after, insert before / after, move up / down
  (across groups), delete.
- Right-click a group: rename, Assistant / advanced mode, duplicate and
  remap (values to other values, tiles moved by cells in the tileset),
  copy, optional / global, colour, icon from the picked tile, biome (the
  layer's biome field: any / all of the values), out of bounds for all
  rules, move, delete.

Rules run in order (groups top to bottom, rules top to bottom); the canvas
updates the auto tiles around every painted cell, and changing a rule
regenerates every level.

## What is saved

The `.ldtk` (and changed `.ldtkl`) files, in LDtk's own JSON layout:
fields this editor doesn't know about are kept, nothing is reordered, and a
file saved without changes is byte for byte the file LDtk wrote. The cached
fields games read (`__cWid`, `__tilesetRelPath`, `__grid`, `__worldX`,
`__neighbours`, `toc`, ...) are kept up to date. Renaming a level renames
its external file (the old one is removed on save).

## Engine API

`engine/ldtk_doc.odin` (document, undo, save), `ldtk_rules.odin` (rule
engine), `ldtk_doc_edit.odin` (entities, fields, levels),
`ldtk_doc_defs.odin` (definitions), `ldtk_tiles.odin` (per-tile data,
animations, terrains), `ldtk_json.odin` (the JSON tree and LDtk's
formatter). Tools and tests can use it without the editor:

```odin
doc, ok := e.Ldtk_Doc_Load("levels/cave.ldtk")
defer e.Ldtk_Doc_Destroy(doc)

li, layer := 0, 0                       // level, layer instance
e.Ldtk_Doc_BeginCells(doc, li, layer, "Paint")
if e.Ldtk_Doc_SetIntGrid(doc, li, layer, 4, 7, 1) {
	e.Ldtk_Doc_ApplyRules(doc, li, layer, 4, 7, 4, 7) // auto tiles around the cell
}
e.Ldtk_Doc_EndCells(doc)                // one undo step

e.Ldtk_Doc_Checkpoint(doc, li, "Add chest")   // undo step for a level edit
chest := e.Ldtk_Doc_AddEntity(doc, li, entitiesLayer, chestDefUid, {64, 112})
e.Ldtk_Doc_SetFieldValue(doc, e.LdtkJson_Arr(chest, "fieldInstances")[0], "25")

e.Ldtk_Doc_Save(doc)
```

| | |
|---|---|
| `Ldtk_Doc_Load` / `LoadFromMemory` / `New` / `Save` / `Serialize` / `Destroy` | files (external levels included) |
| `levels[i].layers[j]`: `intGrid`, `gridTiles`, `autoTiles`, `obj` (the JSON) | typed cells; everything else is in the JSON tree (`LdtkJson_Get` / `Set*`) |
| `Ldtk_Doc_ResizeLevelBounds` (any edge, like LDtk's applyNewBounds), `ResizeLevel` | resizing |
| `Ldtk_Doc_SetLevelBg`, `SetLevelBgPos`, `SetLevelBgPivot`, `LevelBg`; `Ldtk_LevelBgInfo`, `Ldtk_BgPos`, `Ldtk_ImageSize` | background images (`__bgPos`) |
| `Ldtk_Doc_SetLayerGrid`, `DuplicateLayerDef`, `LayerDefText` / `PasteLayerDef`, `BakeLayer`, `LayerIsSource`, `MoveIntGridValue`, `AddIntGridGroup` / `RemoveIntGridGroup` / `SetIntGridGroup` / `MoveIntGridGroup` / `SetIntGridValueGroup`, `SetIntGridValueTile`, `MoveEntitiesBetweenLayers` | layer definitions |
| `Ldtk_Doc_RenameEnum`, `RenameEnumValue`, `RemoveEnumValue`, `RemoveEnum`, `MoveEnum` / `MoveEnumValue`, `SetEnumValueColor` / `SetEnumValueTile` / `SetEnumIconTileset` / `SetEnumTags`, `EnumText` / `PasteEnum` / `DuplicateEnum`, `EnumUsed` / `EnumValueUsed` | enums |
| `Ldtk_ParseExternalEnums`, `Ldtk_Doc_ExternalEnumDiff` / `ApplyEnumSync` (`Ldtk_EnumSync`), `ExternalEnumSources`, `RemoveExternalEnumSource`, `Ldtk_Md5Hex` | external enums |
| `Ldtk_Doc_SetExternalLevels`, `LevelFileRel`, `FixLevelFiles`, `SetIdentifierStyle` / `IdentifierStyle` / `CleanIdentifier`, `SetProjectFlag` (`LDTK_PROJECT_FLAGS`), `Backup` / `BackupDir` | project options |
| `Ldtk_Doc_RunExports`, `ExportImages`, `ExportSimplified` / `SimplifiedJson`, `ExportTiled`; `RenderLayer`, `RenderIntGridMap`, `RenderLevelBg` (CPU images); `PngFileName`, `ExternalDir` | exports |
| `Ldtk_Doc_SetTilesetImage` (`Ldtk_TilesetImageResult`), `SetTilesetGrid`, `SetTilesetSpacing`, `RenameTileset`, `RemoveTileset`, `TilesetText` / `PasteTileset` / `DuplicateTileset`, `MoveTileset`, `SetTilesetTags`, `SetTilesetTagEnum`, `TilesetHasTags`, `TilesetCWid` | tileset definitions |
| `Ldtk_Doc_ReloadTilesetImage`; `Ldtk_Doc_SelectRect(..., includeEmpty)` | file watching, select empty spaces |
| `Ldtk_Doc_SetMultiWorlds`, `AddWorld`, `RenameWorld`, `RemoveWorld`, `WorldInt` / `WorldStr` / `SetWorldInt`, `WorldName`; `SetFlag` / `HasFlag` | worlds and project flags |
| `Ldtk_Doc_SetIntGrid`, `SetTile`, `TilesAt`, `GetIntGrid` | cells |
| `Ldtk_Doc_ApplyRules` (an area), `ApplyRulesLayer`, `ApplyRulesFull` | auto tiles |
| `Ldtk_Doc_BeginCells` / `EndCells`, `Checkpoint` (level or project), `CheckpointOnce` (live edits), `Undo` / `Redo` | undo |
| `Ldtk_Doc_AddEntity`, `MoveEntity`, `ResizeEntity`, `RemoveEntity`, `EntityAt`, `EntityRect`, `SetFieldValue`, `FieldText` | entities and fields |
| `Ldtk_Doc_AddLevel`, `RemoveLevel`, `RenameLevel`, `MoveLevel`, `ResizeLevel`, `SetLevelDepth`, `SetLevelBgColor`, `LevelAt`, `FreeLevelSpot`, `UpdateNeighbours`, `UpdateToc` | levels |
| `Ldtk_Doc_AddLayerDef`, `RemoveLayerDef`, `MoveLayerDef`, `RenameLayerDef`, `LayerDefChanged`, `AddIntGridValue`, `RemoveIntGridValue` | layers |
| `Ldtk_Doc_AddEntityDef`, `EntityDefChanged`, `SetEntityTile`, `RemoveEntityDef`, `AddFieldDef`, `RemoveFieldDef`, `AddEnum`, `AddEnumValue`, `AddTileset` | definitions |
| `Ldtk_Doc_AddRuleGroup`, `AddRule`, `SetRuleCell`, `RemoveRule`, `RulesChanged`, `AddTerrainRules` | rules |
| `Ldtk_Doc_FindRuleGroup`, `RenameRuleGroup`, `MoveRuleGroup`, `RemoveRuleGroup`, `SetRuleGroupOptional` / `Color` / `Icon` / `Biome` / `OutOfBounds`, `DuplicateRuleGroup` (remap), `InsertRule`, `DuplicateRule`, `MoveRule`, `RuleText` / `RuleGroupText` / `PasteRule` / `PasteRuleGroup`, `RuleMatchCells` | editing rules |
| `Ldtk_Doc_RulesWizardApply`, `RulesWizardImport`; `Ldtk_WizardSetup`, `Ldtk_WallFragment` | the Rules Assistant |
| `Ldtk_Doc_SetTileCustomData`, `SetTileAnimation`, `TileAnimation`, `SetTileTag`, `TileHasTag`; `Ldtk_ParseTileAnim` | per-tile data |

Memory: the JSON tree lives in the document's arena (freed with it), the
typed definition caches in two arenas used in turn, cell data and undo
entries on the heap.

## Performance

Measured on an M-series Mac (optimised build):

| Project | Rules on every level | Painting a cell | Saving (serialising) |
|---|---|---|---|
| LDtk's GridVania world sample: 26 000 auto tiles, 86 000 cells | 25 ms | 0.14 ms | 19 ms (2.3 MB) |
| LDtk's platformer sample | 5 ms | 0.3 ms | 4 ms |
| A 2 400-rule stress test | 12 ms | 3.5 ms | 6 ms |

Painting re-runs the rules only around the changed cells (a 9x9 margin,
LDtk's largest pattern); a count of IntGrid values per 10x10 area skips
rules that can't match, as LDtk does.

## Fidelity and limits

- The rule engine follows LDtk 1.5. Files whose auto tiles were generated by
  older LDtk versions (random tiles of flipped matches changed in 1.3.3,
  irrelevant rules are skipped since 1.5) get today's tiles when their
  layers are repainted - LDtk would do the same.
- Animated tiles are this engine's convention (custom data); LDtk shows the
  first frame.

## Tests

`engine/ldtk_doc_test.odin`: byte-exact round trips of LDtk's samples, auto
tiles regenerated equal to LDtk's (stamps, optional rules, biomes, flips),
toc / neighbours equal to LDtk's, incremental rules equal to a full run,
undo / redo, external levels, a project built from scratch (read back by
the runtime loader), per-tile data / animations / terrains, rules editing
and the Assistant, resizing / background images / worlds. Drives:
`tests/drive/level_*.drive`.
