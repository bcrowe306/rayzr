# Custom node types

Your own node types, listed in **Add Node** like the built-in ones. A
custom node type is a **built-in base type**, a **script** and **default
values**: a *Hurtbox* is an Area with `hurtbox.lua` and a 32×32 box. Every
Hurtbox you place starts with those values, runs that script, says
`"Hurtbox"` when a script asks its type, and follows the type when you
change it later.

## The short version

1. **Make a type.** Assets > **Custom Nodes** > **+** (or **+** > New Custom
   Node..., the command palette, Add Node's **Create Custom Node...**, or a
   configured node's right-click > **Save as Custom Node...**). Give it a
   name, a base type and a script.
2. **Place it.** Add Node lists it under its category; or drag it from
   Assets into the viewport; or `Scene.create("Hurtbox", parent, x, y)`.
3. **Change it.** Right-click it > **Edit Type**: its default values as a
   node. Save, and every Hurtbox that didn't change a value gets the new one.
4. **Give one of them more.** Its script's **Extend** button: a new script
   built on the type's, attached to that node only.

## Custom node types or components?

| | Custom node type | Component |
|---|---|---|
| What it is | One node: a base type + a script + values | A tree of nodes |
| Added from | Add Node (and Assets) | Assets |
| Per node | Its own values (a shape, a property) | Overrides of any node in it |
| Scripts see | `get_type() == "Hurtbox"`, `is("Hurtbox")` | an instance of a file |
| Good for | Building blocks: Hurtbox, Hitbox, Pickup, Interactable | Whole things: an enemy, a chest, a room |

They work together: an *Enemy* component can hold a *Hurtbox* node.

## Making a type

The **New Custom Node** dialog:

- **Name**: what Add Node, the hierarchy and `get_type()` show. A Lua
  identifier (letters, digits, `_`), not a built-in type's name.
- **Based on**: a built-in type (Area, Sprite, Character Mover...) or one of
  your types (see [Types built on types](#types-built-on-types)).
- **Script**: a new one from a template suited to the base (an Area gets
  the trigger template, a Character Mover the platformer one), a new one
  built on the parent type's script, a script you have, or none.
- **Category, icon, colour, description**: how Add Node shows it (grouped by
  category, under "your project") and the hierarchy colours it.

A physics base (Area, Static / Kinematic / Dynamic Body) starts with a
32×32 box: without a shape it would do nothing.

**Save as Custom Node...** (a node's right-click in the hierarchy) makes a
type from a node you've set up: its base type, the values that differ from
that type's defaults, and its script. The node becomes one of the new type.

The dialog writes `nodes/<Name>.node.json` and the script, and opens the
script.

## Placing them

- **Add Node** (Cmd+A): your types first, under their categories.
- **Assets > Custom Nodes**: double-click (at the view's centre), drag into
  the viewport, or right-click > Add to Scene / Add as Child of Selected.
- **Lua**: `Scene.create("Hurtbox", parent, x, y)` - with its values and
  script, `ready()` called as usual. `Scene.create("Hurtbox")` works
  too.
- **LDtk**: an entity can spawn as a type - see [LDtk entities](#ldtk-entities).

In the hierarchy a custom node has its type's icon and colour; the
Inspector says **Hurtbox (AreaNode)**. The hierarchy's filter finds them by
type: `t:hurtbox`.

## Linked values

A node of a type saves only **what it changes**:

```json
{"type": "AreaNode", "name": "Hurtbox2", "node_type": "nodes/Hurtbox.node.json",
 "position": [120, 64], "scale": [1, 1], "rotation": 0,
 "script": {"properties": {"armor": 3}}}
```

Everything else comes from the type. So when you change the type - its
shape, a default - every node of it that didn't change that value follows;
one with its own shape keeps it. Name and transform are always the node's
own.

- **Changing a value on one node**: just edit it in the Inspector. It's that
  node's from now on.
- **Script values** follow key by key: a node that changed `armor` still
  follows the type's `max_health`.
- **A missing type file**: the node loads as its base type (`"type"` is
  always saved) with a warning, and is saved back as it was.
- **Inside a component**: a custom node in a component file is linked to
  its type; the component's instances override it as usual.

## Editing a type

Right-click the type in Assets > **Edit Type** (or a node of it in the
hierarchy > **Edit the Hurtbox Type**): a tab with one node of the type.
Edit it like any node - the shape in the viewport, values in the Inspector -
and save. The type's file gets its new defaults, and its nodes in every
open scene update (each keeps what it changed). Undo puts the file and the
nodes back.

**Edit Definition** opens the `.node.json` as text (its name, icon,
category, description). Saving it in the Code tab updates the nodes too.

### Changing the base type

Right-click the type > **Change Base Type...** (an Area that should be a
Static Body after all). Before anything changes you see:

- what of its values doesn't carry over (an Area's `monitoring` on a body);
- the types built on it (their base changes too);
- the scenes and components with nodes of it, and how many.

**Convert** rewrites the type and those files: each node keeps what it
changed that the new base has. Open scenes with unsaved changes must be
saved first; each file written can be undone.

## Types built on types

Base a new type on one of yours (the dialog's **Based on**, or the type's
right-click > **New Type Based on This...**): a *BossHurtbox* built on
*Hurtbox*.

- Its base type is the parent's.
- Its values go on top of the parent's: a change to Hurtbox reaches
  BossHurtbox nodes too (unless BossHurtbox changes that value).
- Its script is the parent's unless it has its own - usually one that
  [extends](#script-inheritance) the parent's script.
- Its nodes are both: `is("BossHurtbox")` and `is("Hurtbox")`.

```json
{"name": "BossHurtbox", "inherits": "nodes/Hurtbox.node.json", "script": "scripts/boss_hurtbox.lua",
 "defaults": {"script": {"properties": {"max_health": 50}}}}
```

## Script inheritance

A script can build on another one:

```lua
---@class BossHurtbox : Hurtbox
local BossHurtbox = {}
BossHurtbox.extends = "scripts/hurtbox.lua"

BossHurtbox.properties = {
    max_health = { default = 50 },                  -- the base's property, another default
    enrage_at = { type = "float", default = 10 },  -- its own
}

function BossHurtbox:take_damage(amount, attack_number)
    BossHurtbox.super.take_damage(self, amount * 0.5, attack_number) -- the base's, halved
    if self.health <= self.enrage_at then self.node:emit("enraged") end
end

return BossHurtbox
```

- **Methods**: what the script doesn't define comes from its base (and its
  base's base). `Class.super` is the base's table: call
  `Class.super.method(self, ...)`. (Name the class, not `self.super`: in a
  base that also calls its super, `self.super` would loop.)
- **`ready` / `update`**: the script's own replace the base's. Call the
  base's from them when you want it.
- **Properties**: the base's, then the script's. An entry without a `type`
  changes only what it gives (another default, keeping the label and range).
- **Hot reload**: saving the base updates every script built on it.
- **A loop or a missing base**: a warning, and the script runs without
  inheritance.

The Inspector's **Extend** button (next to Edit on a script) makes such a
script for the selected node and attaches it, keeping the node's values.
A node whose script extends a type's script counts as that type
(`is("Hurtbox")`).

## Lua

| | |
|---|---|
| `node:get_type()` | `"Hurtbox"` for a custom node; the built-in type otherwise |
| `node:get_base_type()` | the built-in type: `"AreaNode"` |
| `node:is(type)` | its custom type (and the types it's built on), its built-in type, or `"Node"` |
| `Scene.create(type, parent?, x?, y?)` | a new node of a custom or built-in type |
| `Scene.find_nodes_of_type(type)` | the current scene's nodes of a type, in tree order |

The editor's generated Lua types know your types: `Scene.create("Hurtbox")`
returns a `HurtboxNode` (a class on `AreaNode`) whose `get_script()` is the
type's script class, and the type's script's `self.node` is a
`HurtboxNode`. (The node class is `<Name>Node` because the script usually
has the class `<Name>`.)

## LDtk entities

In the Level panel's **Entities** page an entity can spawn as a custom
node type:

- **Spawn as > Custom Node Type**, then pick the type.
- **Auto also spawns the custom node type named like the entity** (off by
  default): an entity on Auto with no component of its name spawns as your
  type of that name - a `Door` entity as your `Door` type.

LDtk fields set the type's script properties of the same name, as for
components.

## Tutorial: hurtboxes and hitboxes

A **Hurtbox** takes damage; a **Hitbox** deals it. Both are Areas.

**1. A Health resource** (`scripts/health.lua`): which health a hurtbox
starts with is data you pick in the Inspector.

```lua
---@class Health : ResourceBase
local Health = {}
Health.resource = { local_copy = false }
Health.properties = { max = { type = "float", default = 10 } }
function Health:on_load() self.current = self.max end
return Health
```

Assets > Resources > **+** > a resource of it: `resources/health.resource.json`.

**2. The Hurtbox type.** New Custom Node: name *Hurtbox*, based on *Trigger
Area*, a new script, category *Combat*, the heart icon. Replace the script
with:

```lua
---@class Hurtbox : ScriptInstanceBase
local Hurtbox = {}
Hurtbox.properties = {
    health = { type = "resource", class = "scripts/health.lua" },
    invulnerable = { type = "bool", default = false },
}

function Hurtbox:ready()
    -- Its own copy: every node using the file would share one table (a
    -- resource is shared, or one per component instance - not per node).
    self.health = self.health:duplicate()
    self.last_attack = nil
end

-- Called by a Hitbox. One hit per attack (a swing overlapping for several
-- frames hurts once).
function Hurtbox:take_damage(amount, attack_number)
    if self.invulnerable or attack_number == self.last_attack then return end
    self.last_attack = attack_number
    self.health.current = math.max(self.health.current - amount, 0)
    self.node:emit("damaged", amount)
    if self.health.current == 0 then self.node:emit("died") end
end

return Hurtbox
```

Edit Type: set its **Health** to `resources/health.resource.json`, resize
its box if you like, save.

**3. The Hitbox type.** New Custom Node: *Hitbox*, a Trigger Area, the
crosshairs icon:

```lua
---@class Hitbox : ScriptInstanceBase
local Hitbox = {}
Hitbox.properties = {
    damage = { type = "float", default = 1 },
}

function Hitbox:ready() self.attack = 0 end

-- A new swing: everything it touches can be hurt again.
function Hitbox:swing() self.attack = self.attack + 1 end

function Hitbox:on_body_entered(other) -- (also for Areas)
    if other:is("Hurtbox") then
        other:get_script():take_damage(self.damage, self.attack)
    end
end

return Hitbox
```

**4. Use them.** Add a Hurtbox under your player and enemies (Add Node >
Combat), a Hitbox under the sword. The owner reacts to its hurtbox:

```lua
function Enemy:ready()
    self.node:get_child("Hurtbox"):connect("died", function() self.node:destroy() end)
end
```

A boss takes half damage: right-click Hurtbox in Assets > **New Type Based
on This...** > *BossHurtbox*, and give its script the `take_damage` from
[Script inheritance](#script-inheritance).

## The file

`nodes/<Name>.node.json` (any folder works):

| Key | |
|---|---|
| `name` | The type's name |
| `base` | Its built-in type (`AreaNode`...); without `inherits` |
| `inherits` | Its parent type's `.node.json` (instead of `base`) |
| `script` | Its script (project-relative; none: the parent's, or no script) |
| `icon`, `color`, `category`, `description` | How the editor shows it |
| `defaults` | Node values as a scene writes them, on top of the base type's (or parent type's) and the script's defaults |

In scenes a node of the type is its base type plus `"node_type"` and what it
changes (see [Linked values](#linked-values)).

## Limits

- A type is one node: no children (make a component for a node tree; it can
  contain custom nodes).
- One script per node: give one node more with an [extended
  script](#script-inheritance).
- Type files changed outside the editor while it runs are picked up when
  they're added or removed; a file edited in place outside the editor is
  read again when the editor next reloads the types (save it from the Code
  tab to update open scenes at once).
