# LDtk (Level Designer Toolkit) Integration Guide

Levels are designed in [LDtk](https://ldtk.io) (the app is vendored in `ldtk/`)
and loaded by the engine with `LdtkLevelNode`. The node draws the level (or a
whole world) with LDtk's parallax, builds Box2D colliders and trigger areas
from IntGrid values, spawns entities as engine nodes (optionally as
components), links entities through their EntityRef fields, exposes every
part of the project to Lua, and reloads when the `.ldtk` file is saved.

Levels can be edited in LDtk or in the editor's **Level** tab, which saves
the same file (`engine/docs/level_editor.md`, `engine/ldtk_doc*.odin`).
Animated tiles: a tile whose custom data has `anim=<ids>` (and `fps=<n>`)
lines cycles through those tiles in the game.

Implementation:
- `engine/ldtk.odin` - project data: worlds, levels, layers, entities, fields
  and references, definitions (layers with IntGrid value names, entities with
  field defs, enums, tilesets with custom data and enum tags).
- `engine/ldtk_level_node.odin` - the scene node: world mode, collision rules,
  entity mappings, link rules, rendering, the node's saved configuration.
- `engine/ldtk_bindings.odin` - the Lua API.
- `editor/ldtk_panel.odin` - the editor's **LDtk** tab.

Tests: `test_ldtk_worlds_enums_collision_mapping_links_lua` (`engine/ldtk_test.odin`),
`test_ldtk_external_levels_fields_spawning_and_lua` (`engine/script_events_test.odin`),
and the `ldtk` editor drive (`tests/drive/ldtk.drive`).

---

## 1. What is supported

| LDtk feature | Support |
|---|---|
| Project file (`.ldtk`), external levels (`.ldtkl`) | ✅ |
| **Multiple worlds** ("worlds" array) and world layouts | ✅ pick the world and level; **world mode** loads every level of the world at its world position |
| Tile, AutoLayer, IntGrid (auto tiles) layers | ✅ drawn in LDtk's order, with flips, opacity, layer offsets |
| Layer visibility | ✅ LDtk's in the game (scripts can toggle it); the editor can hide/solo layers for viewing |
| **Parallax** (factor + scaling) | ✅ LDtk's formula, around the game camera (and the editor camera while editing) |
| IntGrid value **identifiers and colours** | ✅ names in the editor and Lua; values drawn in their colours on request |
| **Collision per IntGrid value** | ✅ None / Solid / One-way / Trigger, friction and restitution per value |
| Level background colour and image | ✅ |
| Entities: position, size, pivot, tags, smart colour, tile | ✅ |
| **Entity → component mapping** | ✅ Auto (by name), a chosen component, a plain Node, or not spawned |
| **Field instances** (entities and levels), arrays of all of them | ✅ fields set script properties of the same name; all fields readable in Lua |
| **Enums** (local and external): values, colours, tiles | ✅ enum fields, tileset **enum tags** |
| **EntityRef** fields (also across levels/worlds) | ✅ resolved to nodes; link rules (signal / parenting); Lua helpers both ways |
| Tileset custom data | ✅ |
| Neighbours | ✅ |
| Packaged games (`.rayzr`) | ✅ the project, levels and images load through the asset manager |
| Live reload | ✅ saving in LDtk rebuilds the level in the editor and in development builds |

---

## 2. In the editor

Import the project (Assets **+** > Import, or drop the `.ldtk` file on the
Assets panel - its tileset images come along). Double-click it under
**Levels** (or drag it into the viewport) to add an `LdtkLevelNode`. The
Inspector picks the project, world and level and toggles world mode; its
**Layers, Entities, Collision...** button opens the **LDtk** tab of the
bottom panel:

| Page | What it does |
|---|---|
| Header | world and level pickers, **world mode**, parallax preview (layers move with the editor camera), IntGrid overlay, fit level, reload, open in LDtk |
| **Layers** | every layer, read-only (LDtk owns the data): type, grid, size, parallax, opacity, content. The eye hides a layer in the editor only (saved with the scene, ignored by the game); solo shows one layer; hovering outlines it in the viewport; the selected IntGrid layer's value legend |
| **Entities** | entity definitions with their count and what they spawn as. **Spawn as**: Auto (`components/<Identifier>.component.json` if it exists, else a Node), a component, a plain Node, or Don't spawn. **Create Component...** writes `components/<Entity>.component.json` and `scripts/<entity>.lua` with a property per field. The field table shows which fields reach a script property. The instances table: click one to frame and highlight it |
| **Collision** | per IntGrid layer and value: None / Solid / One-way / Trigger, friction, bounce; "show colliders while simulating" |
| **Links** | each EntityRef field: rules (connect a signal / parent target to source / parent source to target) and every reference in the level (click to frame the source) |
| **Level Fields** | each level field's value in each loaded level (enum values in their colours) |
| **Enums** | each enum's values (colour, tile) and what uses it (entity fields, level fields, tileset tags) |
| **World** | the world's layout as a mini-map: click a level to open it (world mode: to frame it); neighbours |

The viewport shows entity placements and their references (arrows) while
editing. Colliders, triggers and spawned entities are created when the level
is *ready* (Simulate / Play) and are never saved into the scene.

Node properties (Inspector): `enablePhysics`, `spawnEntities`, `parallax`,
`drawBackground`, `drawEntityTiles`, `tintColor`, `drawDebugColliders`,
`drawDebugEntities`.

---

## 3. Collision rules

Each IntGrid value has a rule (Collision page, or `LdtkLevelNode_SetCollisionRule`):

| Type | Builds |
|---|---|
| None | nothing |
| Solid | boxes on the `<Level>_Colliders` StaticBody |
| One-way | boxes on `<Level>_OneWay`: solid for bodies coming from above, passable from below (platforms) |
| Trigger | an AreaNode `<Layer>_<value name>` raising `body_entered` / `body_exited` |

Neighbouring cells with the same rule merge into a few large boxes (rows,
then equal rows stacked). Without any rule the legacy settings apply: the
`Collisions` layer's value `1` is solid (`collisionLayer` / `solidValues`,
kept for older scenes); the first edit in the Collision page turns them into
rules.

Colliders and trigger areas are on the node's `categoryLayers` /
`maskLayers` (Layer1, all by default) unless the value's rule has its own
(`customLayers`; saved as `"layers"` / `"mask"` arrays of layer names, absent
on rules using the default - #405). Tests: `engine/ldtk_collision_layers_test.odin`.

---

## 4. Entities become nodes

When `spawnEntities` is on, each entity of the loaded levels is spawned per
its mapping (Entities page / `LdtkLevelNode_SetEntityMapping`) as a child of
the level node at its position (world mode: its world position):

- The node is named after the identifier.
- **Fields → script properties**: every field whose name matches a property
  of the node's script sets it (Int/Float/Bool/String/Enum/Color directly;
  Point → a `vector2` in pixels; Int → Float when the property is a float).
  Every field stays available as `node:ldtk_field(name)` / `node:ldtk_entity().fields`.
- The level node raises `entity_spawned` (value: the node) for each, and
  `level_loaded` (the level identifier) once the spawned entities are ready.

Custom spawning in Odin (replaces the mapping):

```odin
ln.entitySpawner = proc(level: ^e.LdtkLevelNode, ent: ^e.LdtkEntityInstance, scene: ^e.Scene, ctx: ^e.GameContext) -> ^e.Node {
    switch ent.identifier {
    case "PlayerStart":
        return CreatePlayerShip(scene, level.spawnOffset + ent.px)
    }
    return e.LdtkLevelNode_DefaultSpawner(level, ent, scene, ctx)
}
```

---

## 5. Links (EntityRef fields)

After spawning, every EntityRef between two spawned entities is resolved
(in world mode also across levels). Then:

- **Link rules** (Links page / `node.linkRules`), per entity and field:
  - *Connect signal*: when the source emits `signal` (any engine event or
    `node:emit("pressed")`), `Target:method(value, source)` runs on every
    referenced entity.
  - *Parent target to source* / *Parent source to target*: reparent,
    keeping positions (a platform carrying its passengers, a key on a door).
- **Scripts** can follow links in both directions:

```lua
function Button:on_pressed()
    for _, door in ipairs(self.node:ldtk_refs("targets")) do door:emit("open") end
end

function Door:ready()
    local by = self.node:ldtk_referenced_by()        -- { {node, field}, ... }
    local key = self.node:ldtk_field("lockedWith")   -- enum value id, e.g. "KeyA"
end
```

---

## 6. Lua

On the level node (full list with types in `engine/definitions/engine_api.lua`):

| Area | Methods |
|---|---|
| Levels & worlds | `ldtk_get_level_identifier()` `ldtk_get_levels([world])` `ldtk_load_level(id)` `ldtk_get_level([id])` `ldtk_get_level_size()` `ldtk_get_level_field(name, [level])` `ldtk_get_level_fields([level])` `ldtk_get_neighbours([level])` `ldtk_level_at(x, y)` `ldtk_get_worlds()` `ldtk_get_world()` `ldtk_set_world(id, [level])` `ldtk_set_world_mode(on)` `ldtk_is_world_mode()` |
| Layers | `ldtk_get_layers([level])` `ldtk_set_layer_visible(name, on)` `ldtk_is_layer_visible(name)` |
| IntGrid & collision | `ldtk_get_int_grid(layer, x, y)` `ldtk_get_int_grid_name(layer, x, y)` `ldtk_get_int_grid_cell(layer, cx, cy, [level])` `ldtk_get_int_grid_values(layer)` `ldtk_world_to_cell(layer, x, y)` `ldtk_cell_to_world(layer, cx, cy)` `ldtk_get_collision(x, y)` `ldtk_get_triggers()` |
| Tiles & enums | `ldtk_get_tile(layer, x, y)` `ldtk_get_tile_enums(layer, x, y)` `ldtk_get_enum(name)` `ldtk_get_enums()` |
| Entities | `ldtk_get_entities([identifier])` `ldtk_get_entities_by_tag(tag)` `ldtk_get_entity(iid)` `ldtk_get_entity_node(iid)` `ldtk_get_entity_defs()` `ldtk_get_links()` |

On a node spawned from an entity: `ldtk_entity()` `ldtk_level_node()`
`ldtk_field(name)` `ldtk_ref(field)` `ldtk_refs([field])` `ldtk_referenced_by([field])`.

Positions are world coordinates unless named otherwise (entity tables have
`x, y` in level pixels and `world_x, world_y`).

```lua
---@class LevelScript : ScriptInstanceBase
local LevelScript = {}

function LevelScript:on_level_loaded(identifier)
    local level = self.node:ldtk_get_level()
    Camera.set_limits(level.x, level.x + level.width, level.y, level.y + level.height)
    Audio.play_music(level.fields.music)
    for name, area in pairs(self.node:ldtk_get_triggers()) do      -- e.g. "Collisions_water"
        area:connect("body_entered", function(other) Log.info(other:get_name(), "entered", name) end)
    end
end

function LevelScript:update(dt)
    local px, py = Scene.find_node("Player"):get_position()
    if self.node:ldtk_get_int_grid_name("Collisions", px, py + 8) == "lava" then
        -- standing on lava
    end
    for _, tag in ipairs(self.node:ldtk_get_tile_enums("Ground", px, py)) do
        if tag == "Ice" then --[[ slippery ]] end
    end
    -- GridVania: walk into the next room.
    local next = self.node:ldtk_level_at(px, py)
    if next and next ~= self.node:ldtk_get_level_identifier() then self.node:ldtk_load_level(next) end
end

return LevelScript
```

---

## 7. Odin API

```odin
ln := e.LdtkLevelNode_Create(scene, "Station", "levels/station.ldtk", "Deep_Space_Station")
e.LdtkLevelNode_SetCollisionRule(ln, {layer = "Collisions", value = 1, type = .Solid, friction = 0.5})
e.LdtkLevelNode_SetCollisionRule(ln, {layer = "Collisions", value = 2, type = .OneWay})
e.LdtkLevelNode_SetCollisionRule(ln, {layer = "Collisions", value = 3, type = .Trigger})
e.LdtkLevelNode_SetEntityMapping(ln, {entity = "Door", mode = .Component, component = "components/Door.component.json"})
append(&ln.linkRules, e.LdtkLinkRule{entity = "Button", field = "targets", action = .Signal, signal = "pressed", method = "open"})
e.LdtkLevelNode_SetWorld(ln, "Overworld")
e.LdtkLevelNode_SetWorldMode(ln, true)
e.LdtkLevelNode_LoadLevel(ln, "Level_2")        // switch level (rebuilds)
e.LdtkLevelNode_Rebuild(ln)                       // after changing rules while running
e.LdtkLevelNode_BuildCollisionBodies(ln, "Collisions", {1, 2}, ctx)  // explicit setup

// Data only.
proj, ok := e.Ldtk_LoadProjectFromFile("levels/station.ldtk")
defer e.Ldtk_DestroyProject(proj)
world  := e.Ldtk_GetWorld(proj, "Overworld")
level  := e.Ldtk_GetLevelInWorld(proj, world, "Level_0")
layer  := e.Ldtk_GetLayer(level, "Collisions")
name   := e.Ldtk_GetIntGridValueDef(proj, layer, 2).identifier
gold, _ := e.Ldtk_GetEnumValue(proj, "Item", "Gold")
target, targetLevel := e.Ldtk_FindEntity(proj, iid)
refs   := e.Ldtk_EntityRefs(entity)
tags   := e.Ldtk_GetTileEnumTags(proj, tilesetUid, tileId)
off, s := e.Ldtk_ParallaxTransform(layer, cameraInLevelPixels)
```

---

## 8. Example: Asteroids level 3 (Deep Space Station)

`asteroids/ldtk_level.odin` with `assets/levels/deep_space_station.ldtk`:
station walls from the IntGrid collision layer (with bounce and camera
shake), laser hazard cells, a player start, turrets, patrol drones, asteroid
breaches and energy cores spawned from entities, and a camera limited to the
level bounds. It is reachable from the title menu (**LEVEL 3: DEEP SPACE
STATION (LDTK)**).
