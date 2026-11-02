# Level Editor
<!-- topic: overview -->

The **Level** tab edits LDtk projects (`.ldtk`, with `.ldtkl` files for
external levels) in place. The file stays an LDtk project: it still opens
in LDtk, and the game's LDtk Level nodes read it and reload when you save.

- **Levels** (left): the world's levels.
- **Layers** (right): the active level's layers and the active layer's
  palette.
- **Canvas** (middle): paint and place things in the active level.
- **Bottom panel**: World, Level, Tilesets, Entities, Enums, Layers, Rules
  and Project tabs.

Hover anything and press **F1** to open its page here. The **?** buttons do
the same.

## Canvas
<!-- topic: canvas -->

The canvas shows the active world. The active level is drawn on top, and the
other levels are dimmed. Click another level to make it active.

| | |
|---|---|
| Pan | Middle drag, or Space + drag |
| Zoom | Mouse wheel (around the mouse); the zoom box in the toolbar |
| Fit the level | Home, or the expand button in the toolbar |
| Grid | G, or the grid button in the toolbar |
| IntGrid colours over auto tiles | the eye button in the toolbar |

The bottom line shows the level, the layer, the cell under the mouse and its
IntGrid value.

# Tools

## Brush
<!-- topic: tool.brush -->

**B**. Paints on the active layer:

- **IntGrid**: the picked value. The right button erases.
- **Tiles**: the picked tiles as a stamp. Flip it with **X** and **Y**.
- **Entities**: places the picked entity on the grid. Hold **Shift** to
  place it off the grid.

**Shift** + drag paints a rectangle instead (as with the Rectangle tool).
Each stroke is one undo step. Auto tiles follow every painted cell.

## Rectangle
<!-- topic: tool.rect -->

**R**. Drag a rectangle and release to fill it with the picked value or
tiles. The tiles repeat across the rectangle. Drag with the right button to
erase the rectangle instead.

## Erase
<!-- topic: tool.erase -->

**E**. Erases the IntGrid value or tiles under the mouse. With the other
tools, the right button erases too.

## Fill
<!-- topic: tool.fill -->

**F**. Fills the connected area of equal cells (the same IntGrid value, or
the same top tile) with the picked value or tiles. The right button fills
that area with nothing (erases it).

## Pick
<!-- topic: tool.pick -->

**I**. Picks the IntGrid value, or the tile (with its flips), under the
mouse, then switches back to the Brush.

## Select
<!-- topic: tool.select, selection -->

**V**, or hold **Alt** with any tool (LDtk's selection).

| | |
|---|---|
| Click | select the entity or cell under the mouse; the layer becomes active |
| **Shift** + click | add to the selection, or remove from it |
| **Shift** + drag on empty space | rectangle selection, over every visible layer |
| Drag the selection | move it: cells by whole cells, entities snapped to the grid (**Shift**: free) |
| **Cmd+Alt** + drag | copy the selection instead of moving it |
| Arrow keys | move the selection by one cell |
| **Delete** | delete what is selected |
| **Cmd+A** / **Cmd+Shift+A** | select everything in the active layer / in every layer |
| **Cmd+C**, **Cmd+X**, **Cmd+V** | copy / cut / paste (pasted under the mouse) |
| **Cmd+D** | duplicate the selection, one cell to the right |
| **Esc** | clear the selection |
| The corner handle | resize a single resizable entity |

Selected cells move or copy together across layers when their grids line
up. Cells that land outside their layer are dropped, and the cells they land
on are replaced. Moving an entity to another Entities layer is in the
**Level** tab, under **Layer**.

## Move levels
<!-- topic: tool.movelevel -->

**M**. Drag levels around the world. In GridVania worlds they snap to the
world grid, and elsewhere to the default grid. In linear layouts, positions
come from the order in the Levels panel.

# Panels

## Levels panel
<!-- topic: panel.levels -->

The active world's levels. Click one to open it, and double-click to frame
it. The filter box keeps only the levels whose name contains its text.

**+** adds a level: click where it goes in the canvas. A preview follows
the mouse, pushed out of the levels it would overlap: green means free,
red means no room. In linear layouts the preview marks where the level is
inserted. Esc or a right click cancels. **Shift**+click on **+** adds it
right next to the active level instead.

The bin deletes the active level (not a world's last level). Right-click a
level for more: open, frame, rename, duplicate, move up / down, delete.

## Layers panel
<!-- topic: panel.layers -->

The active level's layers, top first, shown as *Type: Name*.

- Click a layer to make it active.
- Drag a layer by its **grip** to put it in another order. That changes
  every level.
- The **eye** hides a layer. This is LDtk's per-level visibility, and it is
  saved.
- **+** opens **New Layer**. The sliders button opens the **Layers** tab.

Right-click a layer for more: settings, rules, hide / show, move up / down,
duplicate, delete.

Under the list is the active layer's **palette**.

## New layer
<!-- topic: layer.new -->

| | |
|---|---|
| **Type** | **IntGrid**: values per cell (collisions, terrain types); with a tileset, its rules draw tiles. **Entities**: placed objects with fields. **Tiles**: tiles painted by hand. **Auto**: tiles drawn by rules that read an IntGrid layer. |
| **Identifier** | Its name (letters, digits, _). |
| **Grid size** | Cell size in pixels. |
| **Tileset** | The tileset its tiles come from. |
| **Rules read** | Auto layers: the IntGrid layer their rules look at. |

New layers go on top of every level.

## IntGrid palette
<!-- topic: palette.intgrid -->

The layer's values. Click one, or press **1-9**, then paint. The value's
colour shows in the canvas. Values are added and named in the **Layers**
tab. Right-click a value to edit it.

## Tile palette
<!-- topic: palette.tiles -->

The layer's tileset. Click a tile, or drag over several to make a stamp.
**X** / **Y** flip what you paint. The zoom slider scales the tileset.

The picked tiles are also used by:

- **Rules**: the tiles button, and terrains;
- **Tilesets**: animating a tile;
- **Entities**: an entity's tile.

## Stamp and Random modes
<!-- topic: tile.modes -->

The dice button switches modes (**Shift+R**):

- **Stamp**: the picked tiles are painted as a block, keeping their places
  in the tileset (any shape: holes stay empty). Rectangles and fills repeat
  the block.
- **Random**: each painted cell gets one of the picked tiles at random.
  This is useful for grass, floors and rubble. Rectangles and fills pick a
  random tile per cell.

## Tile stacking
<!-- topic: tile.stacking -->

The layers button (**Shift+T**) toggles stacking. With stacking on:

- a painted tile goes on top of the tiles already in the cell, so you can
  put decorations over a floor;
- painting the same tile again moves it back to the top;
- an **opaque** tile (no transparent pixel) still replaces the stack;
- erasing removes only the top tile.

## Saved tile groups
<!-- topic: tile.saved -->

Pick several tiles, then click the bookmark button (or press **Shift+S**).
From then on, clicking any tile of that group picks the whole group, in its
mode (Stamp or Random). **Alt** + click picks just the one tile. Saved groups
are outlined in the palette. Right-click the palette to forget a group.
Groups are stored in the tileset (LDtk's saved selections).

## Tileset per level
<!-- topic: layer.tileset.override -->

Right-click a layer, then choose **Tileset in this level**, to draw that
layer with another tileset in the active level only. Examples: a winter
version of a level, or a different palette. The tiles keep their ids, so
the other tileset should have the same layout. **The layer's own** goes back
to the layer's tileset.

## Entity palette
<!-- topic: palette.entities -->

The project's entities. Pick one, then click in the level with the Brush.
Use the **Select** tool to move entities, and **Delete** to remove them.
Right-click an entity to edit its definition.

A selected resizable entity shows handles (LDtk's resize tool): on its left
and right sides when it resizes horizontally, top and bottom when it
resizes vertically, and every side and corner when both. Dragging a handle
snaps to the grid (hold **Shift** for free sizes). The entity grows around
its pivot; its position only moves when you drag the side its pivot is on.
Its definition's minimum / maximum sizes and aspect ratio apply.

## Auto-layer rules (palette)
<!-- topic: palette.auto -->

The layer's rule groups. A check box turns an **optional** group on or off
for this level. **Re-run rules** regenerates this level's auto tiles. An
Auto layer has no cells of its own: paint the IntGrid layer it reads.

# Bottom panel

## World tab
<!-- topic: tab.world -->

| | |
|---|---|
| **Multiple worlds** | Lets a project have several worlds. See *Worlds*. |
| **Name** | The world's identifier (only with multiple worlds). |
| **Layout** | **Free**: levels anywhere. **GridVania**: levels on the world grid. **Linear horizontal / vertical**: in a row or column, in the order of the Levels panel. |
| **World grid** | GridVania's grid cell size. Levels move and resize in these steps. |
| **New level size** | The size of levels added to this world. |
| **Map** | Every level of the world. Click one to open it. |

## Worlds
<!-- topic: worlds -->

A project can hold several worlds, each with its own levels, layout and
grid. This is LDtk's *MultiWorlds* option. Turn on **Multiple worlds** in
the World tab, or click **+ World**. The levels and world settings then
move into a list of worlds in the file.

- **+ World** adds a world with one level and opens it.
- Click a world in the list to open it. The Levels panel also has a world
  picker.
- Right-click a world to open, rename or delete it. Deleting a world
  deletes its levels too; undo brings them back. The last world can't be
  deleted.
- **Multiple worlds** turns off again only when one world is left.

Level names can include the world's name: put `%world` in the project's
level name pattern.

## Resizing levels
<!-- topic: level.resize -->

Handles sit around the active level's edges and corners. Drag one to
resize the level. Changes snap to the active layer's grid; in a GridVania
world they snap to the world grid. A preview shows the new size, in red
while it is smaller than one cell.

Dragging the left or top edge moves the level in the world: cells and
entities keep their world positions. When an edge moves by part of a
cell, the remainder goes into the layer's offset (as in LDtk). Entities
that end up outside the level are deleted, unless their definition allows
**out of bounds**. A message gives the count, and undo brings them back.

The Level tab's **Size** field resizes from the top-left corner.

## Level background image
<!-- topic: level.bg -->

Under the background colour, the Level tab picks an **image** from the
project. It is drawn behind the level's layers.

- **Image position**: **Not scaled**; **Fit inside** (the whole image,
  keeping its aspect ratio); **Cover level** (fills the level, keeping its
  aspect ratio; the rest is cropped); **Cover (dirty scaling)** (stretched
  to the level); **Repeat** (tiled).
- **Image pivot**: which part stays visible when the image is cropped, and
  where a smaller image sits.
- **Remove image** clears it.

The file gets the image's placement in `__bgPos` (top-left, scale and crop
rectangle), so games can draw it the way the editor does.

## Level tab
<!-- topic: tab.level -->

The active level's identifier (or **Auto**: named from the project's level
name pattern), position, size (Enter applies), depth, background colour
and image, and its level fields. With an entity
selected, it shows the entity instead: position, size, layer, iid and
fields.

## Tilesets tab
<!-- topic: tab.tilesets -->

**Add from an image...** makes a tileset from an image of the project. The
list groups tilesets by their first tag, and has a filter box. Right-click a
tileset to copy, cut, paste after, duplicate, move, reload its image or
delete it. Deleting a used tileset asks first: layers, entities, Tile
fields and enum / IntGrid icons using it lose it. LDtk's embedded icon
atlas is listed as *[embedded]*; it is kept but can't be drawn here.

The form has the **identifier**, the **image**, the **tile size**,
**spacing / padding**, **tags** and the **tag enum** (see *Tileset images*
and *Tile tags*). Below it is the tile grid: click a tile to edit its
**custom data** (dots mark tiles that have some; green ones are animated),
its **animation** and its **tags**.

## Tileset images
<!-- topic: tileset.image -->

- **Image**: pick another image of the project, or **reload** the file.
  The editor also reloads it when it changes on disk. When the image's
  size changes, painted tiles, rules, saved tile groups, tags and custom
  data keep their place in the image: their tile ids are remapped, as in
  LDtk. A smaller image can lose tiles; when it is smaller by exactly its
  padding, the padding is reduced instead.
- **Tile size**: changing it remaps the tile ids the same way (a bigger
  size can lose tiles; undo brings them back).
- **Spacing / padding**: the pixels between tiles and around the image.

## Tile tags
<!-- topic: tileset.tags -->

A tileset can tag its tiles with the values of one enum: its **tag enum**.
Games read the tags (for example "water", "damage"), and a tile can have
several. Click a value above the tile grid, then click tiles to tag or
untag them; coloured bars show each tile's tags. The hand button goes back
to picking tiles. Changing the tag enum forgets the tags (it asks first).

## Animated tiles
<!-- topic: tile.animation -->

Pick the frames in a tileset palette (in order: left to right, top to
bottom). In the Tilesets tab, click the first frame, then **Animate with
picked tiles**, and set **fps**. Wherever the first frame is painted or
placed by a rule, it animates in the editors and in the game.

The animation is stored in the tile's custom data:

```
anim=40,41,42,43
fps=6
```

## Entities tab
<!-- topic: tab.entities -->

On the left is the list of entity definitions. Right-click one to place,
duplicate, reorder or delete it. In a narrow panel, the definition's
**Settings** and **Fields** are two tabs; in a wide one they sit side by
side.

| Setting | |
|---|---|
| Identifier, Doc, Tags | Its name, a description, and comma-separated tags. Layers can require or exclude tags, and references can allow them. |
| Size, Resizable X / Y | Its default size, and whether instances can be resized with the corner handle. |
| Keep aspect, Min / Max width / height | Limits for resizing. |
| Pivot | The point placed on the grid. |
| Colour | Its colour in the editor. A field can override it (smart colour). |
| Render | Rectangle, Ellipse, Tile or Cross. |
| Tile, Tile mode | Its picture (**Use picked tile**), and how the picture fills the box: Cover, Fit inside, Repeat, Stretch, Full size (cropped / uncropped), 9-slice (with borders). |
| Tile / Fill / Line opacity, Hollow | How it looks. A hollow entity is selected by its outline only. |
| Show name | Its name above it in the canvas. |
| Max count, Limit, When reached | At most N per layer, per level or per world. Placing one more moves the last one, discards the oldest, or is prevented. |
| Table of contents | List its instances in the project's `toc`, for games. |
| Out of bounds | Instances may stand outside their level. |

## Field definitions
<!-- topic: fields.defs -->

Pick a field in the list (right-click it to duplicate, reorder or delete
it), or add one by picking a type and clicking **Add field**.

| Setting | |
|---|---|
| Identifier, Doc | Its name (a script property with this name gets the value) and a description. |
| Type | Converts the field and its values: String to Multilines and back, FilePath to String and back, Int to Float, Bool to Int, Float to Int (truncate / round), and any field to an array. |
| Min / Max values | Array length limits. |
| Nullable | Whether it can be empty. |
| Default | The value new instances use. |
| Min / Max | Number limits. |
| Regex | String values must match it, written `/pattern/flags`. |
| File types | Accepted extensions for FilePath fields. |
| Language | Multilines syntax (used for LDtk's highlighting). |
| Tileset | Tile fields: where the tiles come from. |
| Can point at, Other levels, Symmetrical, Auto chain | Rules for references. |
| Smart colour | A Color or Enum field gives the entity its colour. |
| Display, Position, Link style, Display colour, Display scale, Always show, In world view, Cut long values, Prefix / Suffix | How the canvas shows it (see *Field display in the canvas*). |
| Table of contents, Searchable | Its value in `toc` entries; searchable values. |

## Fields
<!-- topic: fields -->

Values that each entity (or level) carries for the game. Edit them in the
**Level** tab: the selected entity's fields, or the level's.

| Type | Edited with |
|---|---|
| Int, Float | a number (kept within the definition's min / max) |
| Bool | a check box |
| String | one line; it must match the definition's regex, if there is one |
| Multilines | a text box |
| Color | a colour picker |
| Enum | a list of the enum's values |
| Point | "cx,cy", or the crosshair: click a cell in the level |
| FilePath | a path, or the folder button: a project file of an accepted type |
| EntityRef | the crosshair: click the entity in the level (it may be in another level); the arrow button goes to it; the broken-link button disconnects it |
| Tile | **Use picked tile**: the tiles picked in a tileset palette |

- **Arrays**: **+** adds a value (for points and references, you then
  click in the level, and **Shift** keeps adding). Each value has move up,
  move down and remove buttons.
- **Defaults**: a value that is still the definition's default is dimmed.
  Right-click > **Reset to default** brings the default back. **Clear**
  empties a nullable field.
- **Errors** show in red: a required value missing, a reference to an entity
  that no longer exists or isn't allowed, a string that doesn't match the
  regex, a file of the wrong type.
- **Symmetrical references** (a definition option): pointing A at B makes B
  point at A, and clearing it removes both links.
- **Disconnecting a reference**: the broken-link button (or right-click >
  **Clear**) for a single reference, the remove button for an array value.
  Deleting an entity also removes the references to it from its level;
  references from other levels show as lost until you disconnect them.

In the game, an entity's fields set the script properties with the same
names.

## Field display in the canvas
<!-- topic: fields.display -->

Each field definition decides how the canvas shows it (**Display** in the
Entities tab):

| Display | |
|---|---|
| Hidden | not shown |
| Value only / Name and value | text above, at the centre of, or beneath the entity |
| Array count (with / without label) | how many values |
| Entity tile | an enum's icon or a tile field becomes the entity's picture |
| Points / Path / Loop / Star | the points, joined as a path, a closed loop, or lines from the entity |
| Radius (px / grid) | a circle of that radius |
| Reference link (pivots / centres) | an arrow to the referenced entity, in the chosen link style |

Fields still at their default (or empty arrays) are only shown when
**Always show** is on. Errors are always shown, in red.

New reference fields start as **Reference link (centres)**. Whatever a
reference field's Display, the selected entity's links show: the arrows
from it and the arrows to it. Links to entities in other levels aren't
drawn.

## Enums tab
<!-- topic: tab.enums -->

Enumerations are lists of named values, used by Enum fields, tileset tags
and rule biomes.

- **Add enum** adds one. **Import** brings in enums from a file (see
  *External enums*).
- Right-click an enum to copy, cut, paste after, duplicate, move or delete
  it. Deleting an enum also deletes the fields that use it (it asks first).
  The list groups enums by their first tag.
- **Identifier**, **tags**, and **icons from**: the tileset each value's
  icon comes from. Changing it clears the icons.
- Values: a colour (used for smart colours), an icon (click the picture),
  and a name. Renaming a value updates the fields that use it, the
  tilesets' enum tags and the rule biomes. Right-click a value to move it,
  clear its icon or remove it. Removing a used value asks first; those
  fields become empty.

## External enums
<!-- topic: enums.external -->

**Import** reads enums from a file of the project and keeps them linked to
it. Supported files:

| File | Format |
|---|---|
| Text (`.txt`) | One enum per line: `Name: A, B, C` (or `;` or spaces) |
| JSON (`.json`) | `{"Name": ["A", "B"]}` or `{"Name": "A, B"}` |
| Haxe (`.hx`) | Simple enums: `enum Name { A; B; }` (enums with parameters are skipped) |
| CastleDB (`.cdb`) | Sheets with a unique identifier column; a colour column gives colours |

External enums can't be renamed or edited by hand; they follow their file.
The list shows each file with buttons to **sync** it (reload) or **remove**
its enums. "(changed)" means the file changed since the last sync, and
"(missing)" means it's gone. Opening the project syncs changed files.

Syncing adds new enums and values and removes the ones the file no longer
has. When removed values are used by fields, a dialog asks what each one
becomes: removed (the fields become empty), or renamed to one of the new
values (the fields keep their choice). Values follow the file's order.

## Layers tab
<!-- topic: tab.layers -->

The layer list on the left, and the picked layer's settings on the right.
Right-click a layer to copy, cut, paste after, duplicate, move, bake, move
its entities, or delete it. Right-click the empty part of the list to paste
at the bottom. Duplicates and pasted layers get new uids (their rules
too), a free name and empty content.

| | |
|---|---|
| **Identifier**, **Documentation** | The name (unique), and a note shown in tooltips. |
| **UI colour** | Marks the layer in lists. |
| **Grid size** | Cells keep their coordinates when it changes; entities are scaled. Auto layers reading this layer follow. An Auto layer's grid is its source's. |
| **Guide grid**, **Opacity**, **Inactive opacity**, **Hide in list**, ... | See *Layer display*. |
| **Offset** | Moves the whole layer by some pixels. |
| **Parallax** | See *Parallax*. |
| **Filter tags** | Tags grouping layers (kept for LDtk). |

Per type:

- **IntGrid**: the values (see *IntGrid values*). Also the auto-layer
  **tileset** its own rules use, the **biome field** (a level Enum field
  rule groups can test), and **tiles removed by** (a Tiles layer: where it
  has a tile, the auto tiles are left out).
- **Auto layer**: **Rules read** (its IntGrid source; the grid follows),
  the tileset, the biome field and tiles removed by.
- **Entities**: **required / excluded tags** decide which entities can go
  in it. **Move entities...** moves all of them, one kind, or one tag to
  another Entities layer in every level. The target layer's tags must
  accept them.
- **Tiles**: the tileset (the layer takes its grid; a warning shows when
  the grids aren't multiples) and the **tile pivot** (where tiles bigger
  than a cell sit).

## Layer display
<!-- topic: layers.display -->

- **Guide grid**: extra lines every W / H pixels while the layer is active,
  for rooms or screens (0: none).
- **Opacity**: always applied. **Inactive opacity**: applied while another
  layer is active (0 hides it).
- **Hide in list**: the Layers panel leaves the layer out unless it is
  active. It is still drawn.
- **Hide fields when inactive**: entity names and field labels show only
  while the layer is active.
- **Selectable when inactive**: when off, the Select tool and Alt only pick
  this layer's content while it is active.
- **Render in world view**, **Async render**: LDtk options, kept in the
  file.

## Parallax
<!-- topic: layers.parallax -->

A parallax factor makes a layer move slower (positive, far away) or faster
(negative, close) than the camera. 0 means none and 1 fixes it to the
screen. With **parallax scaling**, far layers are also drawn smaller so
they still fit the level, and Y follows X.

The canvas shows parallax on the active level's other layers as you pan.
The active layer stays in place so painting lands where you click.
Clicks on the other layers follow the parallax.

## IntGrid values
<!-- topic: layers.values -->

Each value has a colour, a number and an identifier.

- **Icons from** picks a tileset; then click a value's picture button to
  pick its icon tile. The palette shows icons instead of colours.
- **Add group** adds a group. Right-click a group's header to rename it,
  colour it, move it or delete it; its values go back to *Ungrouped*. The
  palette lists values by group.
- Right-click a value to move it up or down, move it to a group, clear its
  icon, or remove it. Removing a painted value asks first, because its
  cells are cleared.

## Baking
<!-- topic: layers.bake -->

**Bake...** (an Auto layer's or IntGrid layer's menu, or the Layers tab)
flattens its generated tiles into a new Tiles layer, `<name>_baked`,
placed after it. Tiles are stacked as LDtk stacks them. Choose what
happens to the original: deleted, emptied (IntGrid layers lose their
values), or kept. A layer that an Auto layer reads can't be baked.

## Rules tab
<!-- topic: tab.rules, rules -->

Auto-layer rules draw tiles from an IntGrid layer's values. An IntGrid
layer with a tileset has rules of its own; an Auto layer reads another
IntGrid layer's values.

The tab has three columns: the layers that have rules, that layer's
groups and rules, and the editor for the picked rule.

**Groups** run from the top down, and their rules run top to bottom. The
check box turns a group on or off, and the arrow folds it. Badges show
whether the group is optional, made by the Assistant, or limited to a
biome. Right-click a group to:

- rename it;
- duplicate and remap it (see below);
- copy it (**Paste** sits next to the add buttons);
- make it optional or global;
- set its colour, or use the picked tile as its icon;
- limit it to a biome;
- set the out-of-bounds value of all its rules;
- move or delete it.

Assistant groups open in the Assistant on a double-click. **Advanced mode**
turns one into plain rules.

**Rules**: each row shows the rule's pattern, its tiles and its options.
Click a row to edit it. Right-click a row to:

- edit it;
- show the cells it matches;
- enable or disable it;
- duplicate it, copy it, or paste after it;
- insert a rule before or after it;
- move it (past the group's edge, it moves into the next group);
- delete it.

**The rule editor**:

- **Pattern**: pick a value above the grid. **G1**, **G2**... stand for
  any value of an IntGrid value group, and **\*** for any value at all.
  Left click requires it, right click forbids it, and middle click clears
  the cell. The yellow cell is the one that gets the tile. **Size**: odd
  numbers, up to 9.
- **Tiles**: individual tiles (one at random per match) or rectangles
  (stamps placed as a block, around the **pivot**). **Use picked tiles**
  replaces them with the palette's selection; **Add picked** adds to
  them. Right-click a tile to remove it.
- **Out of bounds**: what cells outside the level count as.
- **Break on match**: later rules don't paint the cells this rule painted.
- **Flip X / Y**: also match the pattern mirrored; the tiles flip too.
- **Chance**: the percentage of matching cells that get tiles.
- **Opacity** of the tiles.
- Modulo, checker, Perlin noise and offsets have their own sections.

The eye in the rule's header shows the cells it matches in the canvas
(green). Changing a rule redraws every level.

## Rule groups: duplicate and remap
<!-- topic: rules.groups, rules.remap -->

**Duplicate and remap** copies a group. Each IntGrid value it uses can
become another value, and its tiles can move by whole cells in the
tileset. For example, "0, 4" uses the tiles four rows lower: another
terrain drawn in the same layout. Use it to reuse one set of wall rules
for every material.

**Biome**: when the layer has a biome field (Layers tab), a group can
require some of that enum's values in the level's field: any of them
(OR) or all of them (AND).

**Optional** groups are off by default. You turn them on per level with
the check box in the Layers panel.

## Modulo and checker
<!-- topic: rules.modulo -->

**Modulo X, Y** matches only every Nth column / row. **Offset X, Y**
shifts which columns / rows are picked. **Checker** shifts every other
row (horizontal) or column (vertical) by half the modulo, which gives a
checkerboard.

## Perlin noise
<!-- topic: rules.perlin -->

Matches only where a noise is positive, which gives natural-looking
patches (grass, cracks). **Seed** picks another noise. A smaller
**scale** gives bigger patches; more **octaves** give rougher edges.

## Tile offsets
<!-- topic: rules.offsets -->

**Tile offset X, Y** moves the placed tiles by that many pixels.
**Random X / Y min, max** adds a random shift per cell, which breaks up
repeated patterns. The offsets don't change which cells match.

## The Rules Assistant
<!-- topic: rules.wizard -->

The Assistant writes a group of wall rules. It is LDtk's rules wizard.

1. Click **Assistant** in the Rules tab.
2. Name the group, pick the IntGrid **value** the walls draw over, and
   what the edges are **next to**: anything else, or one specific value
   (walls next to water, say).
3. Click a shape in the grid: a single cell, walls, corners, turns, T
   crossings, diagonals, the full centre...
4. Pick its tile(s) in the Layers panel's tileset, then click **Use picked
   tiles**. With several tiles, one is picked at random. Right-click a
   shape to clear it.
5. Click **Create rules**.

Shapes left empty use a mirrored shape when there is one: give **Wall N**
tiles, and **Wall S** uses them flipped. The group remembers its tiles.
Double-click it, or pick **Edit with the Assistant** from its menu, to
change them and **Update rules**.

## Terrains
<!-- topic: rules.terrain -->

Pick a 3x3 block of tiles in the palette: corners, edges and the middle.
Then click **3x3** next to **Empty group**. It adds nine rules that draw
the block over the picked value: edges where the neighbours are empty, and
the middle inside.

## Project tab
<!-- topic: tab.project -->

Project settings on the left and the **level fields** on the right. The
sections are *File*, *Names*, *Defaults*, *Advanced* and *Description*.

## Project files
<!-- topic: project.file -->

- **File extension**: `.ldtk` or `.json`. The project file is renamed; the
  content is the same.
- **Backup on save**: before each save, the files as they were on disk (the
  project and its level files) are copied to
  `<backups>/<project iid>_<date>_<time>/`. **Backups kept** (3-50) limits
  how many stay; the oldest go first. **Backup folder** is relative to the
  project (default: `<project name>/backups`). **Back up now** makes one
  immediately.
- **Minify JSON**: the file is one line. It's smaller, but harder to read
  or merge.
- **External level files**: each level goes in its own `.ldtkl` file, in a
  folder named like the project. This is good for big projects and version
  control. Turning it off brings the levels back into the project file;
  the `.ldtkl` files are removed on save.

## Exports
<!-- topic: project.exports -->

Exports run after each save (and with **Export now**). Their files go in
the `<project name>` folder next to the project file. Turning an export off
removes its folder on the next save.

- **Images**: PNGs in `<project name>/png`.
  - *One PNG per layer*: the tiles of each Tiles layer and auto layer.
    IntGrid layers also get a tiny map with one pixel per cell in the
    value's colour (`-int`).
  - *One PNG per level*: the layers merged.
  - *One PNG per layer and per level*: both.

  **File names** use `%level_name`, `%level_idx`, `%layer_name`,
  `%layer_idx` and `%world`. **Export backgrounds** adds each level's
  colour and image (`<level>_bg.png`, and under merged images).
- **Simplified export**: for each level, `<project name>/simplified/<level>/`
  gets:
  - `data.json`: the level's name, position, size, colour, neighbours and
    fields, the layer images, and its entities (grouped by name, with their
    fields);
  - a PNG per layer, `_composite.png` and `_bg.png`;
  - a CSV per IntGrid layer.

  Simple engines can read it without an LDtk importer.
- **Tiled export**: a `.tmx` map per level of the first world and a
  `.world` file, in `<project name>/tiled`. IntGrid layers become coloured
  tilesets; stacked auto tiles take several layers; entities become objects
  with their fields as properties. Tiled has one grid per map, so layers
  with another grid size are left out. The log lists what couldn't be
  exported.

## Custom commands
<!-- topic: project.commands -->

Commands the project runs in its folder. Each one runs **manually**
(**Run manual** or **Cmd+R**), **after loading**, **before saving** (the
save waits for it), or **after saving**. Use quotes to group arguments:
`python "tools/export levels.py" --fast`.

Before running a project's commands the first time, the editor shows them
and asks: **Allow**, **Block** or Cancel. The choice is remembered for that
project (in the editor settings); **Reset trust** asks again. Output shows
in the Command window, with **Kill** to stop a command. The window stays
open when a command fails.

## Identifiers
<!-- topic: project.names -->

**Identifier style** controls how identifiers are written:

- *Capitalize*: `My_identifier_1`, the default.
- *Uppercase*: `MY_IDENTIFIER_1`.
- *Lowercase*: `my_identifier_1`.
- *Free*: letters are kept as typed.

Changing it converts every identifier of the project: enums and their
values, layers, entities, tilesets, worlds and levels. It asks first, and
undo brings the old names back. Characters other than letters, digits and
`_` always become `_`.

**Level names**: the pattern for levels' automatic identifiers:

- `%idx` / `%idx1`: the level's index in its world (from 0 / from 1);
- `%world`: the world's name;
- `%depth` (or `%d`): its world depth;
- `%x` / `%y`: its position (Free and GridVania layouts);
- `%gx` / `%gy`: its GridVania cell.

Levels whose **Auto** box is ticked (Level tab) are renamed with it when
they move, are resized from the left / top, or are added. Untick Auto to
name a level yourself (renaming it unticks it too).

## Defaults
<!-- topic: project.defaults -->

The grid of new layers, the size and pivot of new entities, the workspace
colour around the levels, and the background colour of levels that don't
set their own (those levels follow when it changes).

## Advanced flags
<!-- topic: project.flags -->

LDtk's advanced options, mostly for compatibility:

- **Multi-worlds**: several worlds (see *Worlds*).
- **Prefix level file names with their index**: `0000-Level_0.ldtkl`, ...
  Files are renamed on the next save.
- **Export the old IntGrid format**: also writes `"intGrid": [{coordId,
  v}]`, for importers older than LDtk 0.8.
- **Use the "Multilines" type name**: multi-line text fields are typed
  `Multilines` instead of `String`.
- **Export the old table of contents**: the table of contents also lists
  entities' data in the old format.

# Saving

## Saving and the file format
<!-- topic: saving -->

**Cmd+S** saves the `.ldtk`, plus the `.ldtkl` files of external levels
that changed. The JSON is laid out the way LDtk writes it. Fields this editor
doesn't know about are kept, and a file saved without changes is identical
to the one LDtk wrote.

## Undo
<!-- topic: undo -->

**Cmd+Z** / **Cmd+Shift+Z**. Each stroke, move or edit is one step, and the
editor keeps the last 100.

## Keyboard shortcuts
<!-- topic: shortcuts -->

| Key | |
|---|---|
| B R E F I V M | Brush, Rectangle, Erase, Fill, Pick, Select, Move levels |
| Alt (held) | Select with any tool |
| 1-9 | IntGrid value |
| X / Y | Flip the stamp |
| Shift+R | Stamp / Random tile mode |
| Shift+T | Tile stacking |
| Shift+S | Save the picked tiles as a group |
| Shift + drag | Rectangle with the Brush / Erase |
| G | Grid |
| Shift+A | Single layer mode (the other layers faded) |
| Alt+R | Draw auto-layer tiles on / off |
| Shift+H | Details (level names, entity labels, field shapes) on / off |
| Shift+E | Select empty spaces too |
| Tab | Zen mode: the canvas alone |
| Shift+W | Fit the whole world |
| Alt+arrows | The neighbouring level |
| PageUp / PageDown | The next world depth up / down |
| Shift+PageUp / PageDown | Move the level one depth up / down |
| P L U T C | Project, Layers, Enums, Tilesets, Level tabs |
| Cmd+K / Cmd+F | Search (levels, layers, entities, definitions) |
| Cmd+R | Run the manual custom commands |
| Home | Fit the level |
| Delete | Delete the selection |
| Arrows | Move the selection |
| Cmd+A / Cmd+Shift+A | Select all (layer / every layer) |
| Cmd+C / X / V / D | Copy, cut, paste, duplicate |
| Esc | Clear the selection |
| Cmd+S | Save |
| Cmd+Z / Cmd+Shift+Z | Undo / redo |
| F1 | This reference, at the hovered item |
| Cmd+Shift+1 / 2 | Game tab / Level tab |

## Search
<!-- topic: search, palette -->

**Cmd+K** (or **Cmd+F**) opens the search. Type part of a name to find:

- levels (by name or iid);
- the active level's layers;
- entities in any level (by name, iid, or a text / enum field value);
- entity, layer and enum definitions (enums also by value), tilesets and
  rule groups.

Use the arrows and **Enter**, or click a result. Levels open, entities are
selected and framed, and definitions open in their tab.

The lists (Levels panel, Layers, Entities, Enums and Tilesets tabs) have a
filter box: only the items whose name contains its text stay.

## View modes
<!-- topic: view -->

The toolbar buttons and keys next to the grid button:

- **Single layer mode** (Shift+A): the active level's other layers are
  faded.
- **Auto-layer tiles** (Alt+R): off shows the IntGrid values instead of
  the tiles their rules generate.
- **Details** (Shift+H): level names, entity names, field labels and field
  shapes (points, paths, radii, references).
- **Zen mode** (Tab): only the canvas. Press Tab again to bring the panels
  back.
- **Select empty spaces** (Shift+E): rectangle selections also take empty
  cells, so moving them clears where they land.

## Navigation and world depths
<!-- topic: navigation -->

**Alt+arrows** open the nearest level in that direction. Levels have a
*world depth* (the Level tab's Depth): levels at another depth than the
active one are drawn darker. **PageUp / PageDown** go to the nearest level
one depth up or down, and **Shift+PageUp / PageDown** move the active level
there. **Shift+W** frames the whole world.

## Files changed on disk
<!-- topic: files -->

The editor watches the files the project uses:

- When a tileset image changes, it is reloaded. Its size, cells and
  opaque-tile data update, and auto tiles are regenerated.
- When a level background image changes, it is reloaded.
- When an external enum file changes, it is synced (it asks when used
  values would go).
- When another program changes the project file, the editor asks:
  **Reload** (unsaved changes are lost) or **Keep mine** (the next save
  overwrites it).
