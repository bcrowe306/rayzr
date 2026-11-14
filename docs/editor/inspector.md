# Inspector

The Inspector edits the selected node: its name, its transform and draw
order, its type's own settings, its tags, material, script and signals.
Every edit can be undone, every value has a reset button when it differs
from the default, and hovering any property tells you what it does and how
a script reaches it.

![The Inspector](../images/editor_inspector.png)

## When to use it

- Change a node's position, rotation, scale, origin or draw order exactly.
- Set a node type's settings: a sprite's texture, a timer's duration, a
  body's collision shapes, a camera's follow target...
- Attach a script and set its properties per node (the **Properties**
  tab).
- Connect a node's events (signals) to script methods.
- Edit several nodes at once.
- To pick and arrange nodes, use the [Scene panel](scene-tree.md); to
  move them by eye, the [viewport](viewport.md).

## What's in it

### Header

| Control | What it does |
|---|---|
| **Icon and name** | Type a new name and press Enter. Scripts that use the old name are offered an update. |
| **Power** button | Enable or disable the node. A disabled node doesn't update or collide. |
| **Eye** button | Show or hide the node. |
| **?** button | The node type's documentation. Shift+F1 |
| **Type** (under the name) | The node's type, for example `TimerNode`. A custom type shows as `Hurtbox (AreaNode)`. |

The power and eye buttons apply to every selected node. The scene root has
only its name.

### Banners

- **N nodes selected**: several nodes are selected (see
  [Multi-select](#multi-select)).
- **Component instance** (purple): the node comes from a component file.
  Your changes are saved as overrides on this instance. **Edit Component**
  opens the file; **Revert** drops the overrides (listed in orange);
  **Unlink** turns the instance into ordinary nodes. A red message means
  the component file can't be loaded.

### Node and Properties tabs

- **Node**: the node's own settings - everything below.
- **Properties (N)**: your properties, from the node's script. **Add
  Property** opens a dialog: name, type (number, integer, boolean, text,
  resource, node, choice, range, vector, colour, assets, list, curve,
  gradient), default, **Range** (min, max and a **Slider** toggle), label,
  help and group. A **choice** takes its **Values**; a **list** picks what
  it is a list **Of**; a **resource** picks its **Class** from the
  project's resource classes and how instances share it (**Copies**). It
  previews the Lua line and writes it into the script's `properties` table.
  A node without a script gets one made for it. The script is shared: the
  dialog says how many nodes use it.

Right-click a property's name in the Properties tab for **Edit Property...**
(the same dialog; a rename keeps each node's value, and nodes still at the
old default take the new one) and **Remove Property...** (it shows the
script lines that use `self.<name>` and the nodes with a value; undo brings
it back).

### Instance

On a component instance's root: the properties the component exposes.
Editing one edits that node inside the instance. In the component's own
document, right-click a property's name and pick **Expose on Instances**
(**Stop Exposing** undoes it); the root's **Exposed on Instances** section lists and removes them.

### Transform

Not shown for the scene root.

| Field | What it does |
|---|---|
| **Position** | X and Y, relative to the parent. |
| **Origin** | Nodes that draw an image or a box only. The point of the image at the node's position, as a fraction of its size: **0.5, 0.5** is the centre (the default, and what the reset button restores), **0, 0** the top-left, **0.5, 1** the bottom centre. It is also the point the node rotates and scales around. Hover for the value in pixels. **Presets** picks a corner, an edge's middle or the centre. Alt-drag the move handle in the [viewport](viewport.md) to move it while the image stays put. Scripts: `node:set_property("origin", 0.5, 1)`. |
| **Rotation** | Degrees. |
| **Scale** | X and Y. Linked by default: changing one scales the other by the same ratio. |
| **Layer** | Layer 1 (back) to Layer 8 (UI). |
| **Z Index** | Draw order within the layer, added to the parent's. Higher draws on top. |
| **Y Sort Children** | Draw the children by their Y (lower on screen = in front), for top-down and isometric depth. |
| **Y Sort Offset** | Only under a Y-sorted parent. Moves the line it sorts by (drawn dashed in the viewport while selected). |
| **Pause Mode** | **Inherit**, **Pausable** (stops when the game or its parent pauses), **Always** (keeps running - pause menus). |
| **Paused** | Pauses this node and its children while the game runs. |

X / Y pairs have a **link** button: linked, editing one changes the other
by the same ratio.

### The node type's sections

What comes next depends on the node's type. Some examples:

| Section | Node types | What's in it |
|---|---|---|
| **Sprite** | Texture | The texture (picked from the project) and its size and preview. |
| **Atlas Sprite** | Atlas Sprite | The texture and **Edit Region...**. |
| **Animation** | Frame animations | The frames. |
| **Audio** | Sound, Music | The sounds or the track. |
| **Timer** | Timer | Duration, Auto Start, Loop. |
| **LDtk Level** | LDtk Level | The level; **Edit in Level Tab** (the [Level tab](level.md)), **Open in LDtk**. |
| **Vector** | Vector Shape | The SVG **File** (the pen button opens it in your vector app); **Edit Art** / **Done Drawing** ([vector edit mode](vector-edit.md): while drawing, the file's layers and the fill / stroke of the selected shape show here); **Symbol**, **Frame**, **Morph to**; **Explode into Parts**, **Make Animated Symbol**. Under a Skeleton: **Bend with**. |
| **Collision Shapes** | Static, Dynamic, Area, Character Mover | Each shape's type and size; **Add Shape**, a bin to remove one, **Edit in Viewport**. |
| **Follow** | Camera | **Follow Target**: pick a node, or drop one from the Scene panel. |
| **Animation Player** | Animation Player | The **Current** animation, a **Play** / **Stop** preview, the list of animations, **Slice a Sprite Sheet...**. **Open Animation Timeline** opens the bottom panel's Animation tab. |
| **Points** | Path, Line | The points; **Add Point**, smooth / sharp corners, remove. |
| **Spawn List** | Spawner | Components, weights, counts; **Spawn Now** while simulating. |
| **Navigation** | Navigation Region | **Bake**. |
| **Joint Bodies** | Joint | The two bodies it connects. |
| **Font**, **Texture** | Text, Dialogue; Nine-Slice, Parallax | The font or texture file. |

Particle emitters get **Open Particle Editor** (the bottom panel's
Particles tab). Each node type's page in the
[node reference](../nodes/Node.md) lists its settings.

### Properties

The rest of the type's settings, generated from the engine, so every
setting has a widget: numbers, checkboxes, colours, choices, node and asset
pickers, collision layers. Settings that don't apply in the node's current
mode are hidden (a Character Mover in Script mode hides its movement
settings).

**Runtime State** (closed by default) shows values the node works out
while running. They are read-only and not saved.

### Pixels

On every drawn node (closed unless something is set): how it looks in a
pixel-art game. **Texture Filter** (Inherit: each texture's import setting;
Sharp: nearest-neighbour; Smooth: bilinear) and **Snap to Pixels**
(Inherit: the project's Pixel Snap; On; Off). Text and UI nodes add **Text
Pixels**: **Native** draws crisp at the window's resolution over the scaled
game (UI's default), **Pixel** in the game's own pixels (Text's default).
See the [pixel-perfect guide](../../engine/docs/pixel_perfect.md#per-node-settings).

### Tags, Material, Script, Signals

- **Tags**: type a tag and press Enter, or pick one used in the scene from
  the list. Click a tag to remove it. Scripts use `has_tag` and
  `Scene.find_by_tag`; the Scene panel filters with `#tag`. The project's
  generated Lua types list every tag in use (`NodeTag`), so tag names
  complete in scripts.
- **Material**: the node's **Shader** and **Blend** mode. A shader's texture
  parameter takes a project image, or `viewport:<name>` for a
  [Viewport](../nodes/ViewportNode.md)'s picture.
- **Script**: without one, pick a script from `scripts/` or **New
  Script...**. With one: the **Module** picker, **Edit** (open it),
  **Extend** (a new script built on this one, attached instead, the node's
  values kept), **Detach**, and a button to its properties in the
  Properties tab.
- **Signals**: every event the node sends (`timeout`, `body_entered`,
  `clicked`...), with what it passes. **+** connects one to a method on
  any node's script: the handler is written into the script (a script is
  made if the target has none). Each connection shows its target and
  method, with buttons to **open the handler** and **disconnect** (it
  removes the generated handler, asking first if you added code). A
  `self:on_<event>()` line means the node's own script handles it: a
  method named `on_<event>` in the node's script is called for that event
  with no connection. Connections are saved with this node only - a
  [custom node type](../../engine/docs/custom_nodes.md#handling-a-types-events)
  doesn't carry them; its script's `on_<event>` methods do.
  **Add Signal** declares one of the node's own (see [Your own
  signals](#your-own-signals)): it is listed and connected like the
  built-in ones.
- **Component**: **Save as Component** saves this node and its children
  in `components/`.

Plugins can add their own sections.

### Your own signals

Any node can have signals of its own, next to the events its type sends: a
player's `health_changed`, a door's `opened`. **Add Signal** at the end of
the Signals section asks for:

- **Name**: what `emit` and `connect` use - lowercase, digits and `_`
  (`health_changed`). A name the node already has is refused.
- **Value**: the name of what it passes (`health`) and its type (`number`,
  `integer`, `string`, `boolean`, `node`, `table`, `Vec2` or `any`); leave
  the name empty for a signal with no value. Generated handlers are typed
  with it, so the code editor checks them.
- **Description**: shown when you hover it, and in the code editor.

Raise it from a script with `self.node:emit("health_changed", self.health)`.
It reaches the node script's `on_health_changed`, the connections made
here and every `connect` handler, with `(value, source)`.

Each signal's row shows where it comes from:

| Icon | From | Buttons |
|---|---|---|
| Bolt (orange) | The node's type (`timeout`, `clicked`) | **+** connect |
| Bolt (blue) | Declared on this node, saved with the scene | **Edit**, **Delete**, **+** |
| Puzzle piece | Its [custom node type](../../engine/docs/custom_nodes.md#signals): every node of the type has it | **Lock**: opens the type to change it |
| File | A `---@signal` line in its script | Opens the script at the line |

- **Edit** changes the value, the description or the name. Renaming a
  signal that is connected or used in scripts first shows what changes: the
  connections (they follow the new name) and every script line that emits,
  connects or handles it (`on_<name>`), each with a checkbox. Lines with
  `Events.` are global events of the same name, unchecked to start.
- **Delete** lists the connections it removes. Scripts that still emit it
  are listed and left alone; an emit of it then warns.
- A name the node's script emits that nothing declares is listed with a
  warning and **Declare**, which opens the dialog with it filled in.
- While you **Simulate**, each signal has a **play** button: it emits the
  signal now (with a value you type when it has one) to test its
  connections.

Declared in a script instead, a signal comes with every node that runs the
script (and every script that `extends` it):

```lua
---@signal health_changed(health: number) Health went up or down
---@signal died
```

### Reset buttons

A reset arrow appears after a field whenever its value differs from the
default - the node type's default, or a script property's declared
default. Click it to go back.

### Multi-select

Select several nodes (Cmd+click in the tree or viewport, or drag a box).
The Inspector shows the primary node under a banner, with only the
properties they all have. A value that differs shows **—**. Editing a
field (or resetting it) changes every selected node; for X / Y pairs only
the axis you changed, so different positions keep their other coordinate.
The enable and visible buttons and tags apply to all; the script,
material and signals sections edit the primary node only.

### Help

Hover any property's name or field for a tooltip: what it does, its type,
range and default, and `path = "..."` - what `get_property` and
`set_property` take. The **help pane** at the bottom keeps the last
hovered property's help (with a **copy** button for the path), or
describes the selected node type. Turn it off with **View > Inspector
Help**. A script's own properties have paths like `script.speed`.

### Property menu

Right-click a property's name:

- **Copy Path** - the `get_property` path.
- **Find in Script** - script properties: open the script at its
  declaration.
- **Edit Property... / Remove Property...** - script properties.
- **Revert to Component / Apply to Component** - a value changed on a
  component instance (its name is coloured).

While you edit an animation, a diamond after a property's name keys it:
click to add a key at the playhead, right-click for the previous / next
key or to remove one.

### Drag into a script

- **A property's name** into a script in the Code tab inserts a read:
  `self.node:get_property("rotation")`. Hold **Shift** when you drop for a
  write with the current value: `self.node:set_property("rotation", 45)`.
  The node is `self.node` when the script is its own, otherwise a
  `self.node:get_node("<relative path>")` path to it (or `Scene.find_node`).
- **An event** from the Signals section inserts
  `<node>:connect("timeout", function(value, source) ... end)` with the
  cursor in the handler. **One of your own signals** inserts its emit
  instead: `self.node:emit("health_changed", health)`.
- **A node** from the Scene panel inserts a reference typed for the
  language server (its class, so its own methods complete). On an empty
  line it becomes a declaration:

```lua
---@type CharacterMoverNode
local player = self.node:get_node("../Player")
```

Dropped into an assignment (`self.body = `), the `---@type` line goes
above it; anywhere else (an argument) it gets an inline cast,
`self.node:get_node("../Player") --[[@as CharacterMoverNode]]`. Plain
`Node`s get no annotation. Dropped inside the script's `properties` table,
it adds a node property instead. Dropped onto a method's line
(`function Enemy:on_hit(...)`), it offers the node's events: the one you
pick is connected in `ready()` (made if missing) to call that method.

- **An input action** from the chips in the Preview panel's **Script** view
  ([Assets](assets.md#the-preview-panel)) inserts
  `Input.is_action_pressed("jump")` (Shift: `is_action_down`).
- **An animation**: the hand next to the [Animation tab](tab-animation.md)'s
  picker inserts `<player>:animation_play("walk")`.
- **An asset** from Assets inserts its path; with **Cmd** held it becomes
  an exported asset property; with **Alt** held, code that uses it: a
  sound `Audio.play_sound(...)`, a scene `Scene.change_scene(...)`, a
  texture `self.node:set_texture(...)`.

In a script, **Cmd+click** a node path - the string in
`self.node:get_node("...")`, `get_child("...")` or `Scene.find_node("...")` -
to select that node and centre the view on it; Cmd+click anything else goes
to its definition.

## Walkthrough

Make a timer that spawns enemies:

1. Add a **Timer** node and name it `SpawnTimer` in the Inspector's name
   field.
2. In the **Timer** section set **Duration** to `2` and tick **Loop** and
   **Auto Start**.
3. Hover **Duration**: the help pane shows what it does and
   `path = "duration"`.
4. Open the **Signals** section. Next to `timeout`, click **+**.
5. In the dialog pick the node that should spawn (say `Spawner`), type the
   method name `spawn_enemy` and click **Connect**. The handler is written
   into Spawner's script.
6. Select Spawner, open the **Properties** tab and click **Add
   Property**. Name it `max_enemies`, type integer, default `10`. The line
   appears in the script's `properties` table.
7. Set `max_enemies` to `5` on this node. The reset arrow appears; click it
   to go back to `10`.
8. Drag the **Duration** name from the timer's Inspector into the script,
   holding Shift, to get `set_property("duration", 2)`.

## Tips

- An edit to a component instance is an override; right-click the
  property to **Apply to Component** for every instance.
- Scale fields start linked; position fields start unlinked.
- Scenes saved before **Origin** existed keep their look: older Animation
  Players load with their origin at the top-left (**0, 0**).
- In the viewport, clicking picks the node drawn on top, so the draw order
  fields also decide what a click selects.
- With nothing selected (or the scene root), **Scene Settings...** opens
  the Scene panel's Settings tab.
- While the game runs, pick **Remote** in the Scene panel: the Inspector
  then shows and changes the running game's node.
- More: [Scene panel](scene-tree.md), [viewport](viewport.md),
  [TimerNode](../nodes/TimerNode.md),
  [draw order](../../engine/docs/draw_order.md),
  [components](../../engine/docs/components.md),
  [events](../../engine/docs/events.md),
  [scripting](../../engine/SCRIPTING.md).
