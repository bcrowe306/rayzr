# Components

A component (a prefab) is a node tree saved in its own file,
`components/<Name>.component.json`: an enemy, a pickup, a door, a bullet.
You build it once and place it many times. A scene doesn't copy the tree:
it keeps a **linked instance**, which stores the link, the instance's own
name and transform, and what this instance changes (its **overrides**).
When the component file changes, every instance follows it, except for the
values that instance overrides.

## The short version

- **Make one:** right-click a node in the hierarchy > **Save as
  Component**. The node and its children go to `components/`, and the node
  becomes an instance of the new file.
- **Place it:** drag the file from Assets into the viewport, or
  double-click it.
- **Change all of them:** **Edit Component** opens the file as its own
  document. Save it (Ctrl+S) and every instance in the open scenes updates.
- **Change one:** select a node inside an instance and edit it. The change
  is saved as an override on that instance; its label in the Inspector is
  marked. Right-click the label to **Revert to Component** or **Apply to
  Component**.
- **Surface the settings that matter:** in the component document,
  right-click a property > **Expose on Instances**. Instances show it on
  their root.
- **Spawn from Lua:** `Scene.instantiate("components/Slime.component.json",
  parent, x, y, { speed = 80 })`, or `Pool.take(...)` for things you make
  and drop often.

## Creating a component

- **Save as Component** (the hierarchy's right-click menu, or the
  **Component** section at the bottom of the Inspector) writes the selected
  node and everything below it to `components/<node name>.component.json`.
  It never overwrites a file: if the name is taken, it picks a free one
  (`Slime_2`).
- **Save as Component Named...** asks for the name first.
- From then on the node is a linked instance of the file. Its children come
  from the file; the scene keeps only the link.
- Every node in the file gets a **uid** when the file is written. It's how
  instances refer to the node, so renaming or moving the node inside the
  component doesn't lose the overrides instances made to it.
- **New Component...** makes one from scratch (Assets **+**, the
  Components section's or a component's right-click menu, or the command
  palette): a **Name** and a **Root node** type - a Kinematic Body for an
  enemy, an Area for a pickup, a plain Node to group. **Create** writes
  `components/<name>.component.json` (a taken name gets the next free one,
  `Enemy_2`) and opens it in its own tab to build.

## Placing instances

- Drag a component from Assets into the viewport, or double-click it (at
  the view's centre). Its right-click menu also has **Add to Scene** and
  **Add as Child of Selected**.
- Each instance gets a unique name (`Slime`, `Slime2`...).
- In the hierarchy, an instance's root is drawn in the component colour
  (purple), and the nodes inside it are lighter.
- Assets shows how many instances of each component the open scenes and
  documents use (`×3`). **Select All Instances** (its right-click menu, or
  an instance's menu in the hierarchy) selects every one in the active
  scene.
- A component can't be placed inside itself, directly or through the
  components it contains: the editor refuses and says why.

## Editing the component

**Edit Component** (the instance banner in the Inspector, an instance's
menu in the hierarchy, or the file's menu in Assets) opens the file as a
document of its own, in a tab next to the scenes. When opened from a node
inside an instance, that node is selected in the document.

- Edit it as a scene: add, remove, rename and reorder nodes, attach
  scripts, change any property.
- **Save** (Ctrl+S) writes the file and refreshes every instance in the
  open documents: scenes and other components that nest it. The selection
  is kept.
- **Undo** after saving puts the file back and refreshes the instances
  again.
- **Save As** (Cmd+Shift+S) writes the document as a new component under
  the name you type (`<name>_copy` is offered; a taken name gets the next
  free one) and opens it. The file you opened stays as it was saved.

## Instances and overrides

Edit a node inside an instance as you would any node. What you change is
saved as an **override** on that instance:

- **Values**: a node's transform, properties, visibility, its script's
  properties.
- **Children added** to a node of the instance, and component **children
  removed** from it.
- **Order**: Move Up / Move Down, or dragging within the same parent.
  Nodes inside an instance can't move to another parent.

Everything you don't change keeps following the file. Renaming a node
inside an instance isn't an override: names come from the file.

### Seeing what's overridden

- The Inspector's banner on an instance node lists its overrides.
- Each overridden value has its label drawn in the component colour, with
  a bar beside it.

### Undoing or keeping an override

- Right-click an overridden value's label:
  - **Revert to Component** drops that one override.
  - **Apply to Component** writes that one value to the component file,
    and every instance without its own override gets it.
- **Revert** (the banner, or **Revert Overrides** / **Revert This Node** in
  the hierarchy) drops all of a node's overrides, or the whole instance's on
  its root.
- **Apply Changes to Component** (the hierarchy) writes the whole instance
  to the file: its values, its added and removed children, its order.
- **Save as New Component...** writes the instance as a new file, a
  starting point for a variant.
- **Unlink** turns the instance into ordinary nodes. The scene then saves
  them in full.

Undo covers all of these. When one writes a component file, a single
step puts both the file and the scene back.

## Exposed properties

Most instances only need a few settings: a speed, a colour, a team. Expose
them on the component and they show on every instance's root, without
digging into its children.

1. Open the component (**Edit Component**).
2. Select the node that has the property: the root or any child, even one
   inside a nested component.
3. Right-click the property's label > **Expose on Instances**. This works
   for node properties, script properties and the transform.
4. Select the root: its **Exposed on Instances** section lists them. Give
   each a label (empty uses the property's name), or remove it with **×**.
5. Save.

An instance's root now has an **Instance** section with those values.
Editing one edits that node of the instance, which is an ordinary override:
marked, reverted and applied like any other. To stop exposing a value,
right-click its label in the component again > **Stop Exposing**.

## Nesting

A component can contain instances of other components: a ship with a
turret component, a level chunk with coins. Nested instances follow their
own files, and every level can override them:

- The turret file changes: every turret in every ship follows it.
- The ship's file overrides the turret's rotation: every ship has that
  rotation.
- One ship in a scene overrides it again: only that ship.

The outermost level wins for a value it sets. Editing a node of a nested
instance from a scene saves the override on the outermost instance, with a
path through the nested ones (see [Nested instances](#nested-instances)).

## Spawning from Lua

```lua
-- A new instance, under a parent, at a position, with values for its
-- root's script (applied before ready() runs).
local slime = Scene.instantiate("components/Slime.component.json",
    self.node:get_parent(), 120, 64, { speed = 80, health = 5 })

-- Is a node an instance, and which one?
local path = slime:get_component()              -- "components/Slime.component.json"
local root = some_child:get_instance_root()    -- the instance it belongs to
```

- `Scene.instantiate(component, parent, x, y, values)`: the position is
  local to `parent` (two numbers or a `Vec2`). `values` set the root
  script's properties; leave out what you don't need (`Scene.instantiate(path)`
  adds one at the root's origin).
- Things you make and drop all the time (bullets, sparks, coins) should come
  from a **pool**: `Pool.take(component, parent, x, y)` reuses parked
  instances, and `node:destroy()` returns one. See
  [Object pooling](pooling.md).
- Each instance can have its own copy of a resource (health, inventory):
  see [Resources](resources.md), "Shared or one per instance".
- Instances placed in the editor and instances spawned from Lua are the
  same thing: overrides, exposed values and hot reload work the same way.

## Missing files and loops

- **A component file that's missing or broken** (deleted, renamed outside
  the editor, invalid JSON): its instances load as placeholders. A
  placeholder keeps the instance's link and overrides exactly as they were,
  so saving the scene doesn't lose them, and the Inspector says what's
  wrong. Fix or restore the file and reopen the scene.
- **A component that would contain itself** (A inside A, or A > B > A)
  isn't built at that point; the rest loads.

## Hot reload

- A running game (Play in the editor or a project folder, not a `.rayzr`
  package) checks the component files its instances use twice a second.
  When one changes, or a file it nests changes, each instance of it in the
  loaded scenes is rebuilt in place. The outermost instance holding it is
  the one rebuilt. Its overrides, transform and place among its parent's
  children are kept.
- The overrides are diffed against the component JSON the instance was
  built from (kept only until the rebuild), so values the instance never
  changed follow the new file.
- A rebuilt instance is made of new nodes: its scripts start again
  (`ready()`), and a script holding one of its old nodes holds a removed
  node. Look the nodes up again (`get_node`, `Scene.find_node`).
- The editor refreshes the instances in its own documents when it saves a
  component; this check is for the running game.

## Tutorial: an enemy with an exposed speed and its own health

A slime that patrols left and right. Every slime has its own health; the
level designer tunes each one's speed from its root.

1. **The script.** Right-click the Scripts folder in Assets > **New
   Script...**, named `slime`:

   ```lua
   ---@class Slime : ScriptInstanceBase
   local Slime = {}

   Slime.properties = {
       speed  = { type = "float", default = 40, label = "Speed" },   -- px/s
       health = { type = "int", default = 3, label = "Health" },     -- hits
       range  = { type = "float", default = 48, label = "Patrol Range" },
   }

   function Slime:ready()
       self.hp = self.health        -- each instance counts its own hits
       self.start_x = self.node:get_position()
       self.dir = 1
   end

   ---@param dt number
   function Slime:update(dt)
       local x, y = self.node:get_position()
       x = x + self.speed * self.dir * dt
       if math.abs(x - self.start_x) > self.range then self.dir = -self.dir end
       self.node:set_position(x, y)
   end

   function Slime:hit(damage)
       self.hp = self.hp - (damage or 1)
       if self.hp <= 0 then self.node:destroy() end
   end

   return Slime
   ```

2. **The node tree.** Add a **Texture Sprite** node named `Slime` with
   your slime sprite, attach `scripts/slime.lua`, and give it the children
   it needs (an Area for its hitbox, a small sprite for a shadow).
3. **Make it a component.** Right-click `Slime` in the hierarchy > **Save
   as Component**. You now have `components/Slime.component.json`, and the
   node is its first instance.
4. **Expose the speed.** **Edit Component**. With the root selected,
   right-click **Speed** in the script's properties > **Expose on
   Instances**. Do the same for **Health**. Save, and go back to the scene
   tab.
5. **Place a few.** Drag `Slime` from Assets into the viewport three times.
   Each one shows **Speed** and **Health** in its **Instance** section.
6. **Tune one.** Select the second slime and set its Speed to 90. The value
   is marked as an override; the others keep 40. Play: one fast slime, two
   slow ones, and each takes its own three hits.
7. **Change them all.** Decide every slime should take 4 hits: right-click
   Health on any slime > **Apply to Component** after setting it to 4, or
   change it in the component document. Every slime without its own Health
   override follows.
8. **Spawn more from a script**, for example a spawner that sends a tough
   one every tenth time:

   ```lua
   local tough = self.n % 10 == 0
   Scene.instantiate("components/Slime.component.json", self.node, x, y,
       { speed = tough and 25 or 40, health = tough and 10 or 3 })
   ```

9. **Iterate while playing.** With the game running, open the component,
   swap the sprite and save. The running game rebuilds its slimes with the
   new sprite and keeps each one's overrides (see
   [Hot reload](#hot-reload)).

For a health that's a shared stat block (a `Health` resource with max and
regen) with one copy per slime, see the tutorial in
[Resources](resources.md).

## File format

### Component file

The file is a node object, the same as a node in a scene file, with a
`"uid"` on every node:

```json
{
  "type": "TextureNode",
  "name": "Ship",
  "uid": "q8v0d2ma",
  "texture": "textures/ship.png",
  "children": [
    {"type": "ParticleEmitterNode", "name": "Thruster", "uid": "k3j9x0ab",
     "children": [{"type": "Node", "name": "Flame", "uid": "p0q9zz11"}]},
    {"type": "Node", "name": "Cannon", "uid": "7c1lz4ee",
     "component": "components/Cannon.component.json"}
  ]
}
```

- **`uid`**: 8 base-36 characters (`0-9a-z`), unique in the file. It
  identifies the node for instance overrides. It doesn't change when the
  node is renamed or moved, and siblings with the same name have different
  uids.
- Uids are given when the file is written: saving the component document,
  Save as Component, and Apply Changes to Component. Nodes that already have
  one keep it. A node without one, or with a uid another node of the file
  already has, gets a new one.
- A nested instance (a node with `"component"`) has a uid in this file too.
  The nodes inside it have uids in *its* file. The nested link's
  `"overrides"` follow the same rules as an instance in a scene (below).
- A copied or duplicated node is a new node: it has no uid until its file
  is written. A node that is cut and pasted keeps its uid.

### Exposed properties

The root can list a few properties of the component's nodes that every
instance shows on its root (speed, colour, team):

```json
"exposed": [
  {"uid": "k3j9x0ab", "property": "emitter.amount", "label": "Thrust"},
  {"uid": "7c1lz4ee/p0q9zz11", "property": "script.team", "label": ""}
]
```

- **`uid`**: the node, by its uid in this file (`"."` is the root). A node
  inside a nested instance is named by a path of uids through the nested
  link.
- **`property`**: a node key (`position`, `rotation`, `scale`, `origin`), a
  reflected property (`emitter.amount`), or `script.<name>` for a script
  property.
- **`label`**: what instances show. When it's empty, they show the
  property's name, after the node's name for a child.
- The list belongs to the file. An instance never saves it, and Apply and
  Save as Component keep it. In the editor: [Exposed properties](#exposed-properties).

### Instance in a scene

```json
{"type": "TextureNode", "name": "Ship2", "position": [300, 200],
 "component": "components/Ship.component.json",
 "overrides": {".":                 {"script": {"properties": {"speed": 300}}},
               "k3j9x0ab":          {"properties": {"emitter.amount": 40}},
               "k3j9x0ab/p0q9zz11": {"visible": false},
               "$removed":          ["7c1lz4ee"],
               "$added":            {".": [{"type": "Node", "name": "Shield"}]},
               "$order":            {".": ["+Shield", "k3j9x0ab"]}}}
```

- The instance root stores its name, transform, `enabled`, `visible`,
  `layer` (and tags, connections) directly. An instance in a scene has no
  `uid` of its own.
- **`overrides`** keys are paths from the instance root: `"."` is the root,
  and each segment is a node's **uid**. Each value holds what differs from
  the component file. `properties` and a script's `properties` merge key by
  key, other keys replace the value, and `null` removes a key.
- **`$removed`**: paths of component nodes deleted from this instance.
- **`$added`**: nodes added to this instance, in full, under the path of
  their parent. They are scene data, not nodes of the component, so they
  are saved without uids.
- **`$order`**: a parent's children in this instance's order, by path of
  the parent. It is only saved where the order isn't the natural one (the
  component's children in the component's order, then the added nodes).
  Component children are listed by segment (uid), added nodes by `+` and
  their name. Children it doesn't list (added to the component since) come
  after, in the component's order. Instances that didn't reorder follow the
  component's order when it changes. In the editor, Move Up / Move Down and
  dragging within the same parent work inside an instance; Revert on the
  parent drops its order.
- Renaming a child inside an instance isn't an override; the name comes
  from the component file.
- **Apply to Component** on one value writes it into the file of the
  outermost instance holding the override. For a node inside a nested
  instance, it goes into the nested link's `overrides` in that file; the
  nested component's own file is unchanged.

### Nested instances

Paths cross nested instances. A component A nesting B (uid `bina0000`),
which nests C (uid `cinb0000`), and an instance of A overriding a node of
C (uid `1eaf0000`):

```json
"overrides": {"bina0000/cinb0000/1eaf0000": {"position": [5, 5]}}
```

Each level (B's link to C, A's link to B, the instance of A) keeps its own
entry for the node, and they merge per node: the outermost level wins for
a value it sets, and values no level sets follow C. So changing C, B or A
reaches every instance except where an outer level overrides that value.

- An instance's overrides live on the outermost instance whose component
  contains the node. An instance *added* to another instance is saved in
  `$added` as a link with its own `overrides`.
- Saving a component updates its instances in every open document: scenes,
  and component documents that nest it.
- If a nested component's file is missing, entries for nodes inside it are
  kept in that nested link's `overrides`, so they come back with the file.
- Older scenes stored a nested instance's changes as one whole
  `"overrides"` object on the nested node (`{"bina0000": {"overrides":
  {...}}}`). These still load (applied on top of the nested levels) and are
  saved per node from then on.

### Older files (no uids)

Component files and scenes saved before uids keep loading unchanged:

- A path segment matches a child by uid first, then by **name**. A scene
  whose overrides use names (`"Thruster/Flame"`) applies them as before.
- A component file without uids gets them the next time it's written (any
  of the three ways above). Files aren't rewritten in bulk.
- A scene switches its override keys to uids the next time it's saved after
  its component file has uids. Until then, a name-keyed override follows
  the node's name, as it always did.

## How it works

- A component is prepared (read, parsed, defaults filled in, nested
  components expanded) once per path. Instances are built from that copy
  until the component file or any file it nests changes (size or time), or
  the editor writes a component. A copy made from files modified in the
  last 2 seconds is prepared again next time. A file written twice in the
  same file time with the same size can't be told apart otherwise, which
  happens with coarse file times, for example on Windows.
- In the editor, each instance remembers the component JSON it was built
  from, so its overrides stay right when the file changes before the
  instance is refreshed. A game doesn't keep that copy (about 2 KB per
  instance of a 12-node component); saving there diffs against the file.
- Numbers: `bench_components` in `scripts/bench.sh`; baselines in
  `engine/GAPS.md`.

## Limits

- Nodes inside an instance can change order but not parent.
- There are no **variants** yet (a component that inherits another and
  changes a few values). *Save as New Component...* makes a separate copy.
  For a single node, a [custom node type](custom_nodes.md) built on another
  type does this: its values on top of its parent's, linked.
- Instances can't be **edited in place** as the component (changing the
  file from the scene, with the other instances updating live); edit the
  component document, or Apply from an instance.
