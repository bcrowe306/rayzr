# Resources

## What they are, and why

A **resource** is a data asset with behaviour: the stats of a sword, the
health of an enemy, a dialogue line, the settings of a difficulty level.
Its **class** is a Lua script that declares the values (its `properties`)
and the functions that work on them (its methods). Each **resource file**
is one set of those values, edited in the Inspector and saved in
`resources/`. Any script that holds a resource reads its values and calls
its methods.

```text
scripts/weapon.lua              the class: properties (damage, cooldown, icon) + methods (damage_at)
resources/sword.resource.json   damage 25, cooldown 0.4, icon sword.png
resources/axe.resource.json     damage 40, cooldown 0.9, icon axe.png
```

Use one when several things share the same kind of data, or when designers
should tune numbers without touching code or scenes: item and weapon stats,
enemy types, loot tables, upgrade trees, character health and stamina,
level settings. They are Rayzr's equivalent of Godot's custom Resources and
Unity's ScriptableObjects.

## The short version

1. **Assets > Resources > + > New Resource Class...** makes a class from the
   template. Give it properties and methods:

   ```lua
   ---@class Weapon : ResourceBase
   local Weapon = {}
   Weapon.resource = { local_copy = false }   -- the marker: this script is a resource class
   Weapon.properties = {
       damage   = { type = "int", default = 10, min = 0 },
       cooldown = { type = "float", default = 0.5 },
       icon     = { type = "texture" },
   }
   function Weapon:damage_at(distance)
       return math.max(1, self.damage - distance * 0.05)
   end
   return Weapon
   ```

2. **Assets > Resources > + (New Resource)**, pick the class, name it
   `sword`. Select it in Assets: the Inspector edits its values.
3. Give the node a resource property: select it, Inspector **Properties**
   tab > **Add Property**, name `weapon`, type **Resource**, class
   `scripts/weapon.lua` (the list has your resource classes) - or write the
   entry yourself, as below. Then pick `sword` in its row:

   ```lua
   Player.properties = {
       weapon = { type = "resource", class = "scripts/weapon.lua" },
   }
   function Player:fire(target)
       local hit = self.weapon:damage_at(self.node.position:distance(target.position))
       target:get_script():hurt(hit)
   end
   ```

## Classes

A class is a script whose table has the `resource` marker. Only marked
scripts are classes. A script without the marker can't be used as a
resource, and New Resource doesn't list it.

```lua
MyClass.resource = { local_copy = false }   -- or true (see "Shared or one per instance")
```

- **`properties`** are declared exactly like a node script's (every type of
  [the scripting guide](../SCRIPTING.md#supported-property-types): numbers
  with min / max / slider, strings, enums, colours, vectors, asset paths,
  arrays, curves, gradients, groups and tooltips, `---` help comments).
  A resource has no node, so `node` properties don't apply (a warning says
  so). Resources inside resources aren't supported yet: a `resource`
  property on a class stays `nil` (use `Resource.load` in `on_load`).
- **Methods** are ordinary functions on the table (`function Weapon:damage_at(d)`).
- **`on_load(self)`** runs once per table, after its values are set and
  before the first script that receives it runs `ready()`. Set up runtime
  state there (`self.current = self.max`). It's the only callback:
  resources don't `update`. Something that ticks belongs in a node or
  global script.

## Resource files

`resources/sword.resource.json`:

```json
{
  "type": "resource",
  "script": "scripts/weapon.lua",
  "properties": {
    "damage": 25
  }
}
```

The file keeps only the values that **differ from the class's defaults**, so
changing a default in the class reaches every resource that doesn't set it.
Values for properties the class no longer declares are kept (the Inspector
lists them), so renaming a property doesn't silently lose data. Files go in
`resources/` (importing a `.resource.json` puts it there). Renaming or
moving one updates every scene, component and script that references it,
and Find Usages lists them.

## In the editor

- **Assets > Resources** lists them (a gold gem). **+** or right-click >
  **New Resource...** asks for a name and a class. When there's no class
  yet it offers **New Resource Class...** (the Resource Class template).
- **Select a resource** and the Inspector edits it: its class (click to
  open the script), whether it's shared or one per instance, and its
  properties with the same controls as a node script's. Selecting a node
  goes back to the node.
- **Saving is automatic:** an edit is written when you let go of the field
  (a drag or typing writes once at the end; a checkbox, a pick or a reset
  at once). The Console says `Saved resources/...`.
- **Undo / redo** (Ctrl+Z / Ctrl+Shift+Z) include resource edits, in the
  same history as scene edits. Edits during Simulate are undoable too: they
  are saved to the file, not rolled back when the simulation stops.
- A script's **resource property** shows a picker of the resource files of
  its `class`; a resource dropped from Assets onto it is assigned, **Open**
  shows it, and **+** makes a new one, gives the node its own values or
  embeds one (see "A node's own values, or a resource with no file"). Right-click a resource > **Edit Class Script** /
  **New Resource of This Class...**.
- **In the Code tab:** Alt+drop a resource for `Resource.load("...")`;
  Cmd/Ctrl+drop it into a `properties` table to add a resource property.
  `Resource.load("` completes the project's resource files, and the result
  (and a property with a `class`) completes the class's fields and methods.

## Using them from scripts

```lua
-- A property (picked in the Inspector): the resource's table before ready().
Enemy.properties = {
    stats = { type = "resource", class = "scripts/enemy_stats.lua" },
    loot  = { type = "array", of = "resource", class = "scripts/item.lua" },
}

-- By path.
local sword = Resource.load("resources/sword.resource.json")   -- the shared one
local clip  = Resource.new("resources/clip.resource.json")     -- a fresh one, mine
local copy  = sword:duplicate()                                -- a copy of it as it is now

sword.resource_path   -- "resources/sword.resource.json"
```

- `class` on a property is optional. It filters the picker, and at runtime
  a file of another class gives `nil` and a warning.
- A missing file, or a script that isn't a resource class, gives `nil` and
  a warning (in the Console, and as a squiggle while playing).
- **Changes made at runtime are never written to the file.** Setting
  `sword.damage = 99` in a script changes the table, not the asset. Use
  [`Save`](../SCRIPTING.md) for what the player keeps.

### Shared or one per instance

By default a resource is **shared**: every script that uses
`sword.resource.json` gets the same table, so a change one script makes is
seen by all of them. That's right for data that doesn't change while
playing (item stats, settings), and it costs one table.

Some data belongs to each owner: every enemy has its own health. Mark the
class `local_copy = true` and each **component instance** gets its own copy:

```lua
Health.resource = { local_copy = true }
```

- Two `Enemy` instances (placed in the scene, made with `Scene.instantiate`,
  painted on a tile map, from an LDtk level) each have their own `Health`.
- Inside one `Enemy`, every script that references the same file shares its
  copy: the root's script damages it, a child `HealthBar` shows it.
- A node that isn't inside a component instance shares the copy of its
  scene.
- A copy is loaded fresh from the file (its values, then `on_load`), not
  copied from another table.
- A copy is released when its component instance is destroyed.

A property can override the class: `local_copy = false` forces the shared
table, `local_copy = true` asks for a copy. `Resource.new(path)` always
makes a fresh table owned by the calling script's instance, and
`res:duplicate()` copies a table's current state (its tables too; other
resources it holds stay shared) without calling `on_load`.

### A node's own values, or a resource with no file

A resource property doesn't have to name a file as it is. In the
Inspector, the field's **+** offers:

- **Own Values for This Node**: the node gets its own copy of the file,
  and the values you change in the foldout under the field are this
  node's. They're marked `*` and **Reset** returns one to the file's
  value. The other values keep following the file, so a balance pass on
  `bow.resource.json` still reaches this node's bow, except for the
  damage you gave it. The scene stores only the changes:
  `"weapon": {"path": "resources/bow.resource.json", "properties": {"damage": 40}}`.
- **New Embedded &lt;Class&gt;** / **Embed a Copy (no file)**: the
  resource lives in the scene (or component) with its values, edited in
  the foldout: `"weapon": {"class": "scripts/weapon.lua", "properties": {...}}`.
  It's always this node's own. **Save as File...** turns it into a
  `.resource.json` later.
- **New &lt;Class&gt; File...**: a new file of the property's class,
  assigned at once.

The field also takes a `.resource.json` **dropped from Assets**: one of
another class is outlined in red with the reason. **Open** (the arrow)
shows the file in the Inspector, or an embedded resource's class script.

Scripts see the same thing either way: a table with the values, the
class's methods, `on_load` run once. An embedded one has no
`resource_path`.

### Resources inside resources

A resource class can have resource properties of its own:

```lua
Weapon.properties = {
    damage = { type = "int", default = 10 },
    ammo   = { type = "resource", class = "scripts/ammo.lua" },
}
```

The nested one loads like a node's: shared unless its class (or the
property) says `local_copy`, then a copy owned with the outer resource. It
can be embedded or have its own values too, edited in the outer
resource's Inspector the same way. A resource that contains itself,
directly or further down, is stopped there: that property stays `nil`,
with a warning. (Lists of resources, `of = "resource"`, take files only.)

### Hot reload

While the game or Simulate runs:
- **Saving a resource file** (an Inspector edit, or an edit outside the
  editor) re-applies its changed values to every live table of it. Values
  your scripts set at runtime on other fields stay, and `on_load` doesn't
  run again. A node's own values (above) stay its own.
- **Saving the class** gives every live table the new methods, and new
  properties appear with their values.

Stopping Simulate drops every resource table: the next run loads them fresh.

## Tutorial: per-enemy health with a shared stat block

1. **New Resource Class...** `health`:

   ```lua
   ---@class Health : ResourceBase
   local Health = {}
   Health.resource = { local_copy = true }      -- each enemy its own
   Health.properties = {
       max   = { type = "int", default = 100, min = 1 },
       regen = { type = "float", default = 0, label = "Regen / s" },
   }
   function Health:on_load() self.current = self.max end
   ---@return boolean dead
   function Health:damage(n)
       self.current = math.max(0, self.current - n)
       return self.current == 0
   end
   function Health:fraction() return self.current / self.max end
   return Health
   ```

2. **New Resource** of `health` named `grunt_health` (max 60) and another
   named `boss_health` (max 500, regen 2).
3. The enemy component's script:

   ```lua
   ---@class Enemy : ScriptInstanceBase
   local Enemy = {}
   Enemy.properties = {
       health = { type = "resource", class = "scripts/health.lua" },
   }
   function Enemy:update(dt)
       self.health.current = math.min(self.health.max, self.health.current + self.health.regen * dt)
   end
   function Enemy:hurt(n)
       if self.health:damage(n) then self.node:queue_free() end
   end
   return Enemy
   ```

   In the component, pick `grunt_health`. In a boss component, `boss_health`.

4. A child `HealthBar` node's script reads the same copy:

   ```lua
   HealthBar.properties = { health = { type = "resource", class = "scripts/health.lua" } }
   function HealthBar:update(dt) self.node.scale = Vec2(self.health:fraction(), 1) end
   ```

   Pick `grunt_health` there too. Inside one enemy both scripts share the
   copy; every other enemy has its own.

5. Play, and tune `max` and `regen` in the Inspector while Simulate runs:
   live enemies pick the new values up.

## How it works

For engine and editor contributors.

- **Engine** (`engine/script_resources.odin`):
  - **Class marker:** `script_parse_resource_marker` sets `ScriptModule.isResourceClass` / `resourceLocalCopy` on load and hot reload.
  - **Files:** `Resource_ReadFile` / `Resource_ParseText` read a file; `Resource_FileText` encodes one (non-defaults, undeclared keys kept, sorted).
  - **Tables:** `Resource_Load(mgr, path, scope, cached)` makes a table: `script_apply_properties` sets its values (the same code as node scripts), its metatable looks up the class and then `ResourceBase`, and `on_load` runs.
  - **Cache and scopes:** `ScriptManager.resources` holds every live table. Tables are cached per `(scope, path)` (shared = scope nil). `Resource_ScopeOf(node)` is the nearest node with a `componentPath`, else the tree root.
  - **Lifetime:** `Node_Terminate` releases a scope's copies (`Resource_ForgetScope`); `ScriptManager_RestoreGlobals` (Simulate stop) and `ScriptManager_Destroy` release everything.
  - **Resource properties:** `type = "resource"` properties are `nil` until `ScriptInstance_CallReady` resolves them (`script_resolve_resource_props`, `Script_ResolveResource`).
  - **Hot reload:** `ScriptManager_CheckForChanges` also checks resource files (`resources_check_for_changes`), and `ScriptManager_ReloadModule` refreshes a class's tables.
  - **Tests:** `script_resources_test.odin`, `script_resource_property_test.odin`.
- **Editor**:
  - **Assets:** `Asset_Kind.Resource`, the Resources section, and menus (`asset_browser.odin`, `asset_actions.odin`).
  - **New Resource:** `new_resource_dialog.odin`. Classes are found by the marker line, not by running scripts.
  - **Inspector:** `inspector_resource.odin`. It uses the shared property rows `script_props_editor` (`inspector_script_props.odin`) with `owner = nil`, and writes the file when no widget is active.
  - **Undo:** `Undo_Entry.kind = .Resource` holds the file's text before the edit (`Editor_RecordResourceUndo`, `undo_redo`, `Undo_ResourceMoved`).
  - **Types:** `lua_project_types.odin` writes `ResourcePath`, `Resource.load` / `new` overloads per file, and resource classes as `: ResourceBase`.
  - **Drives:** `resource_assets`, `resource_inspector`, `resource_types`.

## Not yet

- Loading resource files from outside the project / `.rayzr` package.
- Lists of resources (`of = "resource"`) with embedded items or own values.
