# Lua 5.4 Scripting Subsystem

The **Rayzr** features a fast, memory-safe, embeddable Lua 5.4 scripting architecture. Game designers and developers can write high-level gameplay logic, enemy AI, scripted cutscenes, and reactive behaviors directly in Lua, attached directly to engine nodes with zero friction.

---

> [!IMPORTANT]
> ### Engine Development Standard: Mandatory Lua Bindings, Documentation & LSP Integration
> Going forward, **any functionality, node type, subsystem, or gameplay feature added to the engine MUST include**:
> 1. **Lua Bindings**: Full adjacent Lua bindings implemented in [`engine/script_bindings.odin`](script_bindings.odin).
> 2. **LSP Integration**: Complete EmmyLua / LuaCATS type definitions and documentation annotations in [`engine/definitions/engine_api.lua`](definitions/engine_api.lua) and checked by a `.luarc.json` like the one below.
> 3. **Documentation**: Clear architectural guidance, lifecycle details, and API reference updated here in [`engine/SCRIPTING.md`](SCRIPTING.md).
> 4. **Automated Verification**: End-to-end unit tests in [`engine/script_test.odin`](script_test.odin) with `mem.Tracking_Allocator` asserting zero memory leaks and zero bad frees.

---

## Table of Contents
1. [Architecture & Lifecycle](#architecture--lifecycle)
2. [Script Format & Exported Properties](#script-format--exported-properties)
3. [Events](#events)
4. [Hot Reload](#hot-reload)
5. [Editing Scripts in the Editor](#editing-scripts-in-the-editor)
6. [Language Server (LSP) & EmmyLua Support](#language-server-lsp--emmylua-support)
7. [Engine Lua API Reference](#engine-lua-api-reference)
   - [Node Methods](#1-node-methods-selfnode)
   - [Engine Module](#2-engine-module-engine)
   - [Input Module](#3-input-module-input)
   - [Audio Module](#4-audio-module-audio)
   - [Camera Module](#5-camera-module-camera)
   - [Physics Module](#6-physics-module-physics)
   - [Scene Module](#7-scene-module-scene)
   - [Log Module](#8-log-module-log--print)
   - [Project Module](#9-project-module-project)
   - [Vector Module](#10-vector-module-vector)
8. [Release Packaging & Virtual File System (VFS)](#release-packaging--virtual-file-system-vfs)
9. [Demo Game Integration](#demo-game-integration)

---

## Architecture & Lifecycle

### Node-Attached Scripts
Scripts can be attached to any existing `Node` subclass (e.g. `TextureNode`, `DynamicBodyNode`, `CameraNode`, `CharacterMoverNode`) or instantiated via the dedicated `ScriptNode` type:

```odin
// Attach script to an existing node
inst := e.Script_AttachToNode(node, "assets/scripts/orbiting_drone.lua", overrides, &game.scriptManager)

// Or create a dedicated ScriptNode in a scene
scriptNode := e.ScriptNode_Create(scene, "assets/scripts/orbiting_drone.lua", "ReconDrone")
```

In the editor: drag a script from Assets onto a node in the scene tree (or
onto it in the viewport), pick it in the Inspector's Script section, or
right-click the script > *Attach to Selected Node*. Dropping onto a node
that has a script replaces it (undo puts it back).

### Script Execution Lifecycle
Each attached script has a private instance table (`self`) with `self.node` pointing to the underlying engine node. The engine dispatches the following lifecycle callbacks:

| Callback | Signature | Description |
|---|---|---|
| `ready` | `function M:ready(self)` | Invoked once when the node enters the active scene and becomes ready. |
| `update` | `function M:update(self, dt)` | Invoked each frame with delta time in seconds. |
| `on_draw` | `function M:on_draw(self)` | Invoked when the node draws (its layer / Z index / Y-sort order): draw vector shapes with the [`Vector` module](#10-vector-module-vector) in the node's local space. |
| `on_destroy` | `function M:on_destroy(self)` | Invoked just before the node or script instance is destroyed. |

```lua
local Drone = {}

Drone.properties = {
    speed = { type = "float", default = 120.0, min = 0.0, max = 500.0, label = "Speed" }
}

function Drone:ready()
    Log.info("Drone ready:", self.node:get_name())
end

function Drone:update(dt)
    self.node:translate(self.speed * dt, 0.0)
end

function Drone:on_destroy()
    Log.info("Drone destroyed")
end

return Drone
```

---

## Script Format & Exported Properties

Scripts declare exposed properties in a `properties` table. These properties are automatically parsed by the engine at load time, allowing the visual scene editor and inspector to render custom UI controls with min/max bounds and reactive editing.

### Supported Property Types
- `texture`, `audio`, `scene`, `script`, `component`, `level`, `file`:
  an **asset reference** (a project-relative path string). The Inspector
  shows an asset picker; e.g. `self.node:set_texture(self.skin)`,
  `Audio.play_sound(self.hit_sound)`. Dropping an asset onto the code with
  Cmd/Ctrl held adds one of these to the `properties` table.
- `node`: a **node reference** - `target = { type = "node" }`. The
  Inspector shows a node picker (or drop a node from the scene tree on it);
  it is saved as a path from the script's node (`"../Player"`), so it keeps
  working when the subtree moves or is instanced, and `self.target` is the
  node itself (resolved just before `ready()`; nil, with a warning, when it
  points at nothing). Dropping a node into the code's `properties` table
  adds one, set to that node when you save the script.
- `resource`: a **resource** - `weapon = { type = "resource", class = "scripts/weapon.lua" }`.
  Saved as a `.resource.json` path; `self.weapon` is the resource's table
  (its values and its class's methods), set just before `ready()` - the
  shared one, or this component instance's own copy with `local_copy`.
  The picker lists the files of `class` - its path, or its class name
  (`class = "Weapon"` for `scripts/weapon.lua`). Lists: `{ type = "array", of = "resource" }`.
  The Inspector's **Properties** tab adds these (and every other type) with
  a dialog: no typing the table by hand.
  See [Resources](#resources).
- `enum`: one of `values` - `mode = { type = "enum", values = {"Idle", "Run"}, default = "Idle" }`;
  a combo in the Inspector, the chosen string in Lua (typed as the union).
- `range`: a number between `min` and `max` edited with a slider (any
  `float` / `int` with `slider = true` too).
- `array`: a list - `speeds = { type = "array", of = "float", default = {1, 2} }`;
  `of` is `string` (default), `float`, `int`, `bool`, `color`, `vector2`,
  `node` or an asset kind (`texture`...). The Inspector edits one row per
  item (+ / remove); Lua gets a table.
- `curve`: points `{{t, v}, ...}` edited in a small graph (drag points,
  double-click to add, right-click to remove); `Curve.sample(self.ease, t)`.
- `gradient`: stops `{{t, r, g, b, a}, ...}` edited on a bar (drag, click
  for the colour, double-click to add, right-click to remove);
  `local r, g, b, a = Gradient.sample(self.tint, t)`.
- Any property: `group = "Movement"` puts it under that header in the
  Inspector; `tooltip = "..."` is its help (hover / help pane). Without
  one, a `---` comment right above the property is its help (and its doc
  in completion):

  ```lua
  MyScript.properties = {
      --- How fast it runs, in pixels per second.
      speed = { type = "float", default = 240 },
  }
  ```
- `float` / `number`: 32-bit floating point number. Supports `min` and `max`.
- `int` / `integer`: 64-bit integer. Supports `min` and `max`.
- `string`: Text string.
- `bool` / `boolean`: Boolean toggle.
- `color`: RGBA color array `{ r, g, b, a }` with values `0.0` - `1.0` or `0` - `255`.
- `vector2` / `vec2`: 2D vector `{ x, y }`.

### Example Declaration
```lua
local Enemy = {}

Enemy.properties = {
    moveSpeed     = { type = "float",   default = 175.0, min = 10.0, max = 600.0, label = "Movement Speed" },
    maxHealth     = { type = "int",     default = 100, min = 1, max = 1000, label = "Max Health" },
    enemyTag      = { type = "string",  default = "Scout", label = "Enemy Tag" },
    canAggro      = { type = "bool",    default = true, label = "Aggressive AI" },
    shieldTint    = { type = "color",   default = { 0.2, 0.6, 1.0, 1.0 }, label = "Shield Glow" },
    spawnOffset   = { type = "vector2", default = { 0.0, -25.0 }, label = "Spawn Offset" },
}

return Enemy
```

---

## Properties as fields

A node's Inspector properties read and write as fields - the same as
`get_property` / `set_property`, which keep working:

```lua
self.node.position = Vec2(100, 200)
self.node.rotation = self.node.rotation + 90 * dt
local cam = Scene.find_node("MainCamera")
cam.followMode = "SingleTarget"            -- enums by name
self.node.name = "Boss"                    -- name renames
```

Fields complete per node class with their type and help. Paths with a dot
(`emitter.amount`) and script fields (`script.health`) stay with
`get_property` / `set_property`; an unknown field is an error when set
(and a warning, once, when read).

## Global scripts

A global script (an autoload) holds state or helpers every script shares: a
score, the player's inventory, a sound manager. Add one in **Project Settings
> Globals** (a name and a script) or right-click a script in Assets > **Make
Global** (named after the file: `game_state.lua` -> `GameState`); global
scripts show a globe in Assets. project.json lists them:

```json
"globals": [{"name": "GameState", "script": "scripts/game_state.lua"}]
```

The table the script returns becomes the Lua global `GameState` - the same
table in every script and across scene changes. Like a node script it may
define `ready(self)` (once, when the game starts, before any scene's nodes;
in the editor when Simulate starts) and `update(self, dt)` (every frame, not
while the game is paused). It has no `self.node`.

```lua
-- scripts/game_state.lua
local GameState = {score = 0}
function GameState:ready() self.score = Save.get("best", 0) end
function GameState:add(points) self.score = self.score + points end
return GameState

-- any other script
GameState:add(10)
Log.info("score", GameState.score)
```

`GameState` completes in every script with the script's own fields and
methods (the generated types declare it as `require` of its file).

## Resources

A resource is a data asset of a Lua class: the class script declares
`properties` and methods, and each `resources/<name>.resource.json` holds one
set of values, edited in the Inspector. The full guide (shared tables vs one
per component instance, hot reload, a tutorial) is
[docs/resources.md](docs/resources.md).

```lua
-- scripts/weapon.lua: a class (the `resource` marker makes it one)
---@class Weapon : ResourceBase
local Weapon = {}
Weapon.resource = { local_copy = false }
Weapon.properties = { damage = { type = "int", default = 10 } }
function Weapon:on_load() end               -- once per table, after its values
function Weapon:damage_at(d) return math.max(1, self.damage - d * 0.05) end
return Weapon

-- any script
Player.properties = { weapon = { type = "resource", class = "scripts/weapon.lua" } }
local hit = self.weapon:damage_at(40)
local sword = Resource.load("resources/sword.resource.json")  -- the shared table
local mine = Resource.new("resources/sword.resource.json")    -- a fresh one, owned by this instance
local copy = sword:duplicate()                                -- its current state, copied
```

Changes made at runtime are never written back to the file.

## Script inheritance

A script can build on another: `extends` names the base script. What it
doesn't define comes from the base (methods, and properties - an entry
without a `type` only changes the base's default); `Class.super` calls the
base's version. Its own `ready` / `update` replace the base's. Saving the
base updates the scripts built on it. The Inspector's **Extend** button (on
a script) makes one for the selected node. The full guide is
[docs/custom_nodes.md](docs/custom_nodes.md#script-inheritance).

```lua
---@class BossHurtbox : Hurtbox
local BossHurtbox = {}
BossHurtbox.extends = "scripts/hurtbox.lua"
BossHurtbox.properties = { max_health = { default = 50 } }   -- another default
function BossHurtbox:take_damage(amount, attack)
    BossHurtbox.super.take_damage(self, amount * 0.5, attack)  -- the base's, halved
end
return BossHurtbox
```

## Custom node types

Your own node types (a Hurtbox: an Area, its script, a box), made in the
editor (Assets > Custom Nodes, Add Node > Create Custom Node, Save as Custom
Node) and listed in Add Node. In scripts:

```lua
other:get_type()       -- "Hurtbox" (a custom type's name; else the built-in one)
other:get_base_type()  -- "AreaNode"
other:is("Hurtbox")    -- its custom type (and those it's built on), its built-in type, or "Node"
local h = Scene.create("Hurtbox", self.node, 0, -8)          -- with its values and script
for _, h in ipairs(Scene.find_nodes_of_type("Hurtbox")) do h:get_script():heal(1) end
```

The full guide: [docs/custom_nodes.md](docs/custom_nodes.md).

## Vectors

`Vec2`, `Vec3` and `Vec4` are value types with operators:

```lua
local v = Vec2(3, 4)
local w = (v + Vec2.ONE) * 2 - Vec2(1, 0)    -- + - * / with a vector or a number
print(v:length(), v:normalized(), v:dot(w), v:distance(w), v:lerp(w, 0.5))
print(Vec2.RIGHT:rotated(90), v:angle())    -- degrees (y is down)
local x, y = v:unpack()
self.node:set_position(v)                   -- setters taking x, y take a vector too
local p = self.node:get_property("position") -- vector properties come back as Vec2
```

Constants `Vec2.ZERO`, `ONE`, `UP`, `DOWN`, `LEFT`, `RIGHT`. A vector still
answers `v[1]` / `v[2]`, so code written for `{x, y}` arrays keeps working;
exported `vector2` script properties are Vec2 too.

## Completion of project names

String arguments complete from the project: input actions
(`Input.is_action_pressed`), scenes, textures, sounds, components, node
names and tags, animation names (`animation_play`), state machine
parameters, triggers and states (`sm_set`, `sm_trigger`, `sm_transition`), save keys the scripts use
(`Save.get`), locale keys and languages (`tr`, `Locale.set`), collision
layers, LDtk levels / layers / entities, and every keyboard key
(`Input.is_key_pressed("F5")` - any raylib key name works, plus RETURN,
ESC, SHIFT, CTRL, ALT and "0"-"9").

## Events

Every node raises named events (`EventSubject`s on the Odin side). A script
receives the events of **its own node** as methods called `on_<event>`, and
can subscribe to **any node's** events with `node:connect`.

Event names complete in the Code tab: `timer:connect("` offers a timer's
events (`timeout`, `tick`) plus the tree events, a button's `clicked`, and
so on per node class; `connect` and `emit` also offer the project's custom
events - the names its scripts `emit` (`self.node:emit("jumped")`) - and
`function MyScript:on_` completes the `on_<event>` methods.

| Event | Raised by | Value |
|---|---|---|
| `entered_tree` / `exited_tree` | every node | - |
| `child_added` / `child_removed` | every node | the child `Node` |
| `parent_added` / `parent_removed` | every node | the parent `Node` |
| `timeout` | TimerNode (duration elapsed) | - |
| `tick` | TimerNode (each frame while running) | elapsed seconds |
| `body_entered` / `body_exited` | AreaNode | the other `Node` (`nil` if it was destroyed) |
| `collision_started` / `collision_ended` | Static/Dynamic bodies, CharacterMover | the other `Node` |
| `hit_started` / `hit_ended` | RaycastNode | the `Node` hit |
| `animation_finished` | FrameAnimationNode, AnimationPlayerNode (non-looping) | animation name |
| `animation_event` | AnimationPlayerNode (a Method key fired; see docs/animation_editing.md) | method name |
| `finished` | SoundNode, MusicNode | - |
| `clicked`, `value_changed`, `submitted`, `selected`, `row_selected`, `sorted`, `item_clicked` | UI widgets | widget-specific |
| `level_loaded` / `entity_spawned` | LdtkLevelNode | level identifier / spawned `Node` |

```lua
---@class Door : ScriptInstanceBase
local Door = {}

-- Events of this script's own node (an AreaNode here).
function Door:on_body_entered(other)
    if other:get_name() == "Player" then self.node:emit("opened") end
end

function Door:ready()
    -- Any node's events; returns an id for disconnect.
    local timer = Scene.find_node("DoorTimer")
    self.timerConn = timer:connect("timeout", function(value, source)
        Log.info("timer fired on", source:get_name())
    end)
end

return Door
```

- `node:emit(name, value)` raises a custom event (`on_<name>` on the node's
  script plus every `connect`ed handler).
- `on_<event>` methods are only called once the script is ready (after `ready`).
- Connections are released automatically when the connecting script or the
  source node is destroyed, so handlers never run against freed nodes; a
  `Node` value whose node is gone becomes `nil`. `node:disconnect(id)` removes
  one early.
- The editor doesn't dispatch events to scripts while editing; they run in
  *Simulate* and in the game.

### Global events (Events)

Events that belong to no node go through the **event bus**: any script
emits, any script connects, without a reference to each other (gameplay ->
HUD, a level -> the game flow).

```lua
-- Anywhere: the HUD
self.conn = Events.connect("score_changed", function(score, source) self:show(score) end)
-- Anywhere else: a coin
Events.emit("score_changed", GameState.score)
```

- `Events.connect(event, fn [, scope])` / `Events.once(...)` -> id,
  `Events.disconnect(id)`; handlers get `(value, source)` - the value as
  emitted (tables too), and the emitting script's node (or the node passed
  to `emit`).
- `Events.emit(event [, value [, source]])` delivers now (handlers may emit
  in turn); `Events.emit_deferred(...)` at the end of the frame.
- Connections end with the connecting script's node (or the `scope` node);
  a global script's last for the game. `Events.listener_count(event)`.
- Engine code uses the same bus (`EventBus_Subscribe` / `EventBus_Publish`
  on `game.events`).

Guide with a tutorial: [`docs/events.md`](docs/events.md).

### Connections made in the editor (signals)

The Inspector's **Signals** section connects an event of a node to a method
of another node's script, like Godot's signals. The editor writes the
handler into the target script:

```lua
---Signal: Timer.timeout - The timer's duration elapsed
---@param source Node
function Spawner:on_timer_timeout(_, source)
end
```

and saves the connection on the *source* node:

```json
"connections": [{"signal": "timeout", "target": "../Spawner", "method": "on_timer_timeout"}]
```

`target` is a path relative to the source (`.`, `..`, `../Spawner`,
`Gun/Muzzle`), so connections inside components keep working in every
instance. When the event fires, the engine calls
`Target:method(value, source)` after the source's own `on_<event>`.
Disconnecting in the Inspector removes both the connection and the
generated handler (it asks first if the handler contains code).

---

## Input actions

Scripts ask for **actions**, not keys. Actions are defined per project in
**Settings > Project > Input** (saved in `project.json` under `"input"`):
each has a name and up to four bindings (keys, mouse buttons, gamepad
buttons or gamepad axes). The built-in names (`move_up`, `move_down`,
`move_left`, `move_right`, `jump`, `fire`, `secondary`, `boost`, `interact`,
`pause`, `confirm`, `cancel`, `custom1`..`custom4`) can be rebound, and any
other name adds an action:

```lua
if Input.is_action_pressed("dash") then self:dash() end
local x = Input.get_axis("move_left", "move_right")
local vx, vy = Input.get_vector()   -- move_left/right/up/down by default
```

## Simulate and Lua state

*Simulate* (F7) runs scripts in the editor's Lua state. Starting it
snapshots the Lua globals; stopping it restores them and re-runs every
module, so module-level variables start fresh and nothing a simulation did
leaks into the next run or into the saved scene.

## Debugging

**Lua console.** The **Lua** line under the editor's Console runs Lua in
the game while it plays (sent over the editor link) or in the editor's Lua
state during Simulate. An expression prints its value(s) - nodes as
`Node "Player" (CharacterMoverNode)`, vectors as `Vec2(3, 6)`, tables
shallow - and a statement runs:

```lua
Scene.find_node("PlayerShip").position     -- = Vec2(640, 360)
GameState.score = 100                      -- = ok
Scene.find_node("Boss"):get_script().health
```

Errors come back in red. Up / Down walk the history. While editing (no
Simulate, no Play) the line is disabled.

**Errors in the Code tab.** Script errors while the game runs (Play) or in
Simulate - a failing `ready` / `update` / event handler, a syntax error on
hot reload - show as red squiggles on their line in the Code tab (hover
for the message; repeated ones say how many times), next to the language
server's. Some calls warn (yellow) once per call site: `get_node` finding
nothing ("get_node: no node at "Gun" from Player") and `get_property` with
an unknown path. They clear when the game or simulation starts again, or
when you save that script. A game built without the editor writes them to
its log.

Set breakpoints by clicking line numbers in the editor's Code tab, then
Play: the game stops in the script at a breakpoint, with the call stack
and locals in the Game tab, and steps with F8 (continue), F10 (over), F11
(into) and Shift+F11 (out).

- **Conditional breakpoints**: right-click a line number to give its
  breakpoint a condition (a Lua expression - `self.health <= 0`,
  `i == 10`); it stops only when the condition is true, seeing the line's
  locals, upvalues (`self`, module locals) and globals. A condition that
  errors stops too and says why. Conditional breakpoints are amber; hover
  for the condition.
- **Watch**: expressions in the Game tab's Watch column are evaluated in
  the selected frame at every stop (and when you pick another frame).
- While paused, the Console's **Lua** line evaluates in the paused frame
  (its locals are visible; assigning to a local doesn't change it).

The engine side is `engine/lua_debugger.odin`
(a line hook installed only while there are breakpoints or a step pending,
so scripts run at full speed otherwise).

## Hot Reload

Saving a `.lua` file reloads it in the running game (development builds) and
in the editor's *Simulate* mode. The module table is updated in place, so
running instances keep their state (`self.*` fields and property values) and
immediately run the new functions. Newly declared properties appear with
their defaults; removed ones disappear. If the new file has a syntax or
runtime error, the error is logged and the previous code keeps running.
Files are checked twice a second (`ScriptManager_CheckForChanges`); exported
`.rayzr` games don't hot-reload.

---

## Editing Scripts in the Editor

Scripts open in a **Code** tab next to the Viewport:

- double-click a script in *Assets* (or right-click → *Edit Script*),
- the edit button next to the script in the *Inspector*,
- *Open Script* in a node's context menu in the scene tree,
- double-click a console message containing `file.lua:LINE`,
- *New Script* (Inspector, scene tree) or the **+** on the *Scripts* folder:
  a dialog with the file name and a template, then creates and opens the
  script (`---@class Name : ScriptInstanceBase`). Templates (a preview shows
  each; the one made for the node's type is picked first):

  | Template | For | What it does |
  |---|---|---|
  | Empty | any | `ready` / `update` and one property |
  | Platformer Character | CharacterMover | run, jump (coyote time, buffer, variable height), wall slide |
  | Top-Down Character | CharacterMover | eight-way movement (`move_left/right/up/down`), acceleration, friction, facing |
  | Enemy Patrol | any | walks back and forth (or up and down), waits at the ends, chases a `target` node within range (`spotted` / `lost` events) |
  | UI Menu | a UI root | Start (changes to a `scene` property, with a transition), Options shows a panel, Back hides it - buttons are `node` properties |
  | Pickup | AreaNode | bobs; a body with the collector tag picks it up: sound, `collected` event on the body with its value, shrinks and frees itself |
  | Door / Trigger | AreaNode | a tagged body slides a door node open (closes when everyone left) or changes scene; `triggered` event, once option |

**Snippets**: type a snippet's name at the start of a statement and press
**Tab** - it expands with the script's class and the line's indentation,
and Tab then moves through its placeholders (Esc stops). With the
completion list open, Tab still expands it (the list shows
`Tab: <name> snippet`); Enter picks the list's item.

| Name | Expands to |
|---|---|
| `ready` | `function Cls:ready() ... end` |
| `update` | `---@param dt number` + `function Cls:update(dt) ... end` |
| `connect` | `self.node:connect("timeout", function(value, source) ... end)` |
| `properties` | `Cls.properties = { speed = { type = "float", default = 100 }, }` |
| `tween` | `Tween.to(self.node, "position", {0, 0}, 0.5, "out_quad")` |
| `on` | `function Cls:on_body_entered(other) ... end` |
| `method` | `function Cls:name() ... end` |

The editor uses `lua-language-server` (built in `lua-language-server/`) with
the engine definitions as its library: completion for every engine module and
`self.node` method, signature help, hover documentation, diagnostics
(squiggles, gutter markers, counts in the status line) and go to definition
(F12 or Ctrl/Cmd-click). Ctrl/Cmd+S saves (and hot-reloads), Ctrl+Space
completes, Ctrl/Cmd+/ toggles comments, Ctrl/Cmd+W closes the tab.

Annotate the module table with `---@class Name : ScriptInstanceBase` so the
language server knows `self.node`, the property table and the `on_*`
callbacks.

---

## Language Server (LSP) & EmmyLua Support

The engine provides full IntelliSense, autocomplete, parameter hints, and type diagnostics for `lua-language-server` (VS Code, Neovim, Helix, Sublime Text).

Every API function in the definitions has a description and a one-line
`Example:` - shown when you hover it or pick it in completion. **F1** on a
name in the Code tab opens **Help > Scripting Reference** (this guide, by
section, searchable) with the function's API entry on top and the section
about it (`Audio.play_sound` -> the Audio module)
(`lua_api_docs_test.odin` keeps it that way: a new binding needs both).

- **Stubs definition file**: [`engine/definitions/engine_api.lua`](definitions/engine_api.lua)
- **Root configuration**: `.luarc.json` (per user, not committed), for example:

```json
{
  "$schema": "https://raw.githubusercontent.com/LuaLS/vscode-lua/master/setting/schema.json",
  "runtime": { "version": "Lua 5.4" },
  "workspace": {
    "library": ["engine/definitions"],
    "checkThirdParty": false
  },
  "diagnostics": {
    "globals": ["Engine", "Input", "Audio", "Camera", "Physics", "Scene", "Log"]
  }
}
```

---

The definitions are checked against what the engine registers
(`test_lua_definitions_match_bindings`): a binding added without a
declaration - or a declaration without a binding - fails the engine tests.

### Typed nodes

The definitions have a class per node type (`CameraNode`, `TextureNode`,
`CharacterMoverNode`, ...): each has the `Node` methods plus its own
(`camera_*`, `texture_*`, `character_*`...), so completion only offers what
the node can do. The editor's generated `project_types.lua` makes
`Scene.find_node("Player")` and `node:get_child("Gun")` return the type of
the node with that name in your scenes, and gives a script's `self.node`
the type of the nodes it is attached to, and `self.node:get_node("` completes
the paths from that node in its scenes (`"Gun"`, `"../MainCamera"`), each
returning that node's type. Elsewhere (a node from
`get_children()`, a script not attached yet) the type is `Node`; say what it
is with an annotation:

```lua
---@type CharacterMoverNode
local body = self.node:get_node("Body")

---@class Enemy : ScriptInstanceBase
---@field node DynamicBodyNode
local Enemy = {}
```

## Engine Lua API Reference

### 1. Node Methods (`self.node`)

#### Identity & Hierarchy
| Method | Parameters | Return | Description |
|---|---|---|---|
| `get_type()` | - | `string` | Returns concrete type (e.g. `"TextureNode"`, `"CameraNode"`, `"DynamicBodyNode"`); a custom node type's own name (`"Hurtbox"`). |
| `get_base_type()` | - | `string` | The built-in type, also for a custom node type (`"AreaNode"`). |
| `is(typeName)` | `typeName: string` | `boolean` | Its custom type (and the types it's built on), its built-in type, or `"Node"`. |
| `get_name()` | - | `string` | Returns node display name. |
| `set_name(name)` | `name: string` | - | Renames node. |
| `is_enabled()` | - | `boolean` | Checks if node receives updates. |
| `set_enabled(enabled)` | `enabled: boolean` | - | Enables/disables node updates. |
| `is_visible()` | - | `boolean` | Checks if node is rendered. |
| `set_visible(visible)` | `visible: boolean` | - | Enables/disables node rendering. |
| `get_parent()` | - | `Node?` | Gets parent node in scene hierarchy. |
| `get_children()` | - | `Node[]` | Gets array of child nodes. |
| `get_child(name)` | `name: string` | `Node?` | Finds child node by name. |
| `add_child(child)` | `child: Node` | - | Reparents node as child. |
| `remove_child(child)` | `child: Node` | - | Detaches child node. |
| `destroy()` | - | - | Queues node for scene removal. |
| `add_tag(tag)` / `remove_tag(tag)` | `string` | `boolean` | Tags (groups), also set in the Inspector's **Tags** section and saved with the scene. |
| `has_tag(tag)` | `string` | `boolean` | |
| `get_tags()` | - | `string[]` | |

`Scene.find_by_tag("enemy")` returns every node with the tag, in tree order:

```lua
for _, enemy in ipairs(Scene.find_by_tag("enemy")) do
    enemy:set_enabled(false)
end
```

#### Lookup & textures
| Method | Parameters | Return | Description |
|---|---|---|---|
| `get_node(path)` | `string` | `Node?` | A node by path relative to this one (`"Gun"`, `"../Player"`, `"."`). Dragging a node from the scene tree onto a script inserts this call, typed (`---@type CharacterMoverNode` or `--[[@as ...]]`). |
| `set_texture(path)` | `string` | `boolean` | Shows another image on a TextureNode (e.g. a `texture` property). |

#### Transforms
| Method | Parameters | Return | Description |
|---|---|---|---|
| `get_position()` | - | `x, y` | Gets local (x, y) coordinates. |
| `set_position(x, y)` | `x, y: number` | - | Sets local (x, y) coordinates. |
| `translate(dx, dy)` | `dx, dy: number` | - | Moves node by delta offset. |
| `get_rotation()` | - | `degrees` | Gets local rotation in degrees. |
| `set_rotation(deg)` | `deg: number` | - | Sets local rotation in degrees. |
| `rotate(dDeg)` | `dDeg: number` | - | Rotates node by delta degrees. |
| `get_scale()` | - | `sx, sy` | Gets local scale factors. |
| `set_scale(sx, [sy])` | `sx, sy` | - | Sets local scale factors. |
| `get_global_position()`| - | `x, y` | Computes world-space position. |
| `get_global_rotation()`| - | `degrees` | Computes world-space rotation. |

#### DynamicBodyNode (Box2D Physics)
| Method | Parameters | Return | Description |
|---|---|---|---|
| `apply_force(fx, fy)` | `fx, fy: number` | - | Applies a force this step (mass x px/s^2). |
| `apply_impulse(ix, iy)`| `ix, iy: number` | - | Changes the velocity by impulse / mass (px/s). |
| `get_mass()` | - | `number` | Density x area in px^2 (a 64x64 box at density 1 = 4096): `apply_impulse(0, -node:get_mass() * 300)` is 300 px/s up. |
| `get_linear_velocity()`| - | `vx, vy` | Gets physics linear velocity. |
| `set_linear_velocity(vx, vy)`| `vx, vy` | - | Directly sets physics linear velocity. |
| `get_angular_velocity()`| - | `deg/s` | Gets angular velocity in degrees per second. |
| `set_angular_velocity(w)`| `w: number` | - | Sets angular velocity in degrees per second. |
| `get_gravity_scale()` | - | `number` | Gets gravity scale multiplier. |
| `set_gravity_scale(scale)` | `scale: number` | - | Sets gravity scale multiplier. |
| `is_fixed_rotation()` | - | `boolean` | Checks if rotation is locked. |
| `set_fixed_rotation(fixed)` | `fixed: boolean` | - | Locks or unlocks rotation. |
| `set_linear_damping(damping)` | `damping: number` | - | Sets linear drag coefficient. |
| `set_angular_damping(damping)` | `damping: number` | - | Sets angular drag coefficient. |
| `is_awake()` | - | `boolean` | Checks if body is actively simulating. |
| `set_awake(awake)` | `awake: boolean` | - | Wakes body up or puts to sleep. |

#### Materials (any node)

A node's **material** (Inspector > Material) is a shader, a blend mode and
the shader's parameters, applied when the node draws. Shaders: built-in
(`builtin:flash`, `builtin:outline`, `builtin:dissolve`, `builtin:grayscale`,
`builtin:wave`) or a project fragment shader (`.fs`, GLSL 330: Assets **+** >
New Shader). Every `uniform` of the shader is a parameter; hints after `//`
(`color`, `range 0 1`, `default 0.5`) shape the Inspector; `time` is set
automatically. Saving a shader reloads it.

```lua
function Enemy:on_hit()
    self.node:set_shader("builtin:flash")
    self.node:set_shader_param("flash_color", {1, 1, 1, 1})
    self.node:set_shader_param("amount", 1.0)
end

function Enemy:update(dt)
    local a = self.node:get_shader_param("amount")
    if a and a > 0 then self.node:set_shader_param("amount", math.max(0, a - dt * 4)) end
end
```

| Method | Parameters | Return | Description |
|---|---|---|---|
| `set_shader(shader)` | `"builtin:..."`, a `.fs` path, or `nil` | - | Sets / removes the shader. |
| `set_shader_param(name, ...)` | number(s), `{r,g,b,a}`, or a texture path | - | Sets a uniform. |
| `get_shader_param(name)` | `name` | up to 4 numbers / path | Current value (or the shader's default). |
| `set_blend_mode(mode)` | `"alpha"`, `"additive"`, `"multiply"`, `"add_colors"`, `"subtract_colors"`, `"premultiplied"` | - | Blending. |

#### Tweens (`Tween`)

Animate a property to a value over time with an easing curve - any
reflected property (`position`, `scale`, `rotation`, `tint`, ...), or a
material parameter (`"shader:amount"`). Colours are `{r, g, b[, a]}` in
0..1. A tween starts from the property's value when its delay ends, and ends
with its node.

```lua
Tween.to(self.node, "position", {400, 200}, 0.5, "out_back")
Tween.to(self.node, "scale", {1.2, 1.2}, 0.15, "out_quad", {loops = -1, yoyo = true})
Tween.to(self.node, "tint", {1, 1, 1, 0}, 0.3, "linear", {
    delay = 1.0,
    on_complete = function(node) node:destroy() end,
})
local id = Tween.to(self.node, "shader:amount", 0, 0.25, "out_quad")
Tween.cancel(id)                  -- or Tween.cancel_all(self.node [, "position"])
local k = Tween.ease("in_out_sine", t)   -- 0..1 -> eased 0..1
```

Easing names: `linear`, `constant`, and `in_` / `out_` / `in_out_` + `sine`,
`quad`, `cubic`, `quart`, `expo`, `back`, `elastic`, `bounce`. Animation
track keys use the same curves (Animation tab: right-click a key > Easing).

#### Animation events & crossfade

An AnimationPlayer's timeline can hold **event tracks** next to its property
tracks (Animation tab > Add Track > Events):

- **Call Script Methods** - each key names a method; when the playhead
  reaches the key's frame the target node's script runs `self:<method>(frame)`.
- **Play Sounds** - each key names an audio file, played on that frame at
  the SFX bus volume.

```lua
function Player:on_footstep(frame)   -- keyed on a "walk" method track
    self.node:emit("footstep")
end

self.node:animation_play("run", 0.15)  -- crossfade from the current pose over 0.15 s
```

Crossfading blends the previous animation's property tracks into the new
one's (frames switch immediately).

#### Save data (`Save`)

Persistent key/value data for progress, settings and high scores: plain Lua
values (booleans, numbers, strings, and tables of those) saved as JSON in
the player's user-data folder - macOS `~/Library/Application Support/<game>/`,
Windows `%APPDATA%\<game>\`, Linux `~/.local/share/<game>/` (`<game>` is the
project name). The file is read on first use and written by `Save.flush()`
and when the game quits.

```lua
local best = Save.get("best_score", 0)
if score > best then Save.set("best_score", score) end

local settings = Save.get("settings", {music = 0.8, fullscreen = false})
settings.music = 0.5            -- tables are stored by reference
Save.set("settings", settings)
Save.flush()                    -- write now (e.g. at a checkpoint)

Save.slot("slot_2")             -- another file (slot_2.json); "save" by default
for _, key in ipairs(Save.keys()) do Log.info(key) end
```

| Function | Description |
|---|---|
| `Save.set(key, value)` | Stores a value (`nil` removes the key). |
| `Save.get(key [, default])` | The value, or `default` when unset. |
| `Save.has(key)` / `Save.delete(key)` | Test / remove a key. |
| `Save.keys()` | Sorted list of keys. |
| `Save.clear()` | Removes every key. |
| `Save.flush()` | Writes the file now; returns `true` on success. |
| `Save.slot([name])` | Switches save file (writing the current one first); returns the current slot. |
| `Save.path()` | The current save file's path. |

Functions and nodes can't be saved (they're written as `null`). A damaged
file is ignored (logged) and the game starts with empty data. The runner's
`--user-data <dir>` puts save files in another folder (portable builds,
tests); in the editor, **Game > Save Data** opens the folder or deletes the
save files.

#### Scene flow: transitions, preloading, pausing

```lua
Scene.change_scene("level2", {transition = "circle", duration = 0.5})  -- or "fade", "wipe_left", ...
Scene.change_scene("level2", {transition = "slide_left", easing = "out_cubic"}) -- both scenes on screen
Scene.register_transition("swirl", "shaders/swirl.fs")  -- your own (a shader)
Scene.preload("level3")                       -- load its assets a little each frame
if Scene.preload_progress("level3") >= 1 then ... end

Engine.set_paused(true)                        -- pause the game (physics too)
pauseMenu:set_pause_mode("always")             -- ... but keep the menu running
self.node:set_paused(true)                     -- pause just this node and its children
```

During a transition the scene switches once its assets are loaded (the
screen stays covered until then). Besides the cover transitions (fade,
wipe_*, circle) there are crossfade, dissolve, pixelate, slide_* and push_*,
which show the old scene's last frame with the new scene, and shader
transitions of your own; options for easing, the uncover half and pausing
meanwhile; events `transition_started` / `_midpoint` / `_finished` on the
global bus; a project-wide default (Project Settings). Guide:
[`docs/scene_flow.md`](docs/scene_flow.md). Preloading loads textures, sounds, music
and fonts - also those of the components the scene uses - within about 4
ms a frame, and hands them to the scene when it loads. Paused nodes skip
`update` (scripts, animations, timers, particles, tweens) and their
physics bodies are disabled; set **Pause Mode** and **Paused** in the
Inspector too.

#### Text, dialogue and localization

**TextNode** draws text in the world: a project font (`.ttf` / `.otf` at
any size, or a `.fnt` BMFont), **Rendering** (Auto stays sharp when scaled,
rotated or zoomed), text along a **Path** node, wrapping (**Max Width**),
alignment, **Rich Text** markup, a **Localized** key and a
typewriter (**Reveal Speed** characters per second; event `revealed`).

```text
[color=#ff8800]orange[/color]  [color=red]  [size=40]big[/size]
[wave]wavy[/wave]  [shake]shaky[/shake]  [[ for a literal [
```

```lua
self.node:set_text("[color=yellow]+100[/color]")    -- restarts the typewriter
local box = Scene.find_node("DialogueBox")
box:dialogue_show({
    {speaker = "Ada", text = "Welcome to the [wave]station[/wave]."},
    "Follow me.",
})
function Player:on_finished() ... end               -- (connect the box's "finished")
```

**Localization**: CSV tables in `locale/` - `key,en,fr,...` (several files
merge; edits are picked up while running):

```lua
Locale.set("fr")
self.title:set_text(tr("menu.start"))
print(tr("greeting", {name = player_name}))  -- "Bonjour, {name} !"
```

TextNodes and dialogue boxes marked **Localized** treat their text as keys.
The project's starting language is Project Settings > General > Language.

#### Visual extras

**Nine Slice Sprite** stretches a texture to **Size** keeping its borders
(**Margins LT / RB** in texture pixels) - panels and buttons.
**Parallax Background** moves with the camera at **Factor** (0 = fixed on
screen, 1 = with the world), repeating on X / Y and drifting at **Scroll
Speed**. **Line** draws a polyline (width, colour, closed, rounded joints);
**Trail**, as a child of a moving node, leaves a fading, tapering ribbon.
**Post Effect** applies its Material shader to the whole screen
(`builtin:vignette`, `builtin:crt`, `builtin:pixelate`,
`builtin:chromatic`, or a project shader; several chain in tree order; a
`resolution` uniform is set automatically).

```lua
local laser = Scene.find_node("Laser")
laser:line_set_points({ {0, 0}, {200, 0} })     -- local to the node
laser:line_add_point(200, 40)
laser:line_clear()
Scene.find_node("Trail"):trail_clear()          -- after a teleport
Scene.find_node("Crt"):set_enabled(false)       -- turn an effect off
```

#### Navigation (A* on tile maps, LDtk levels and Navigation Regions)

Navigation Regions bake a grid from static bodies, solid tile maps and LDtk
Solid cells (`nav_rebake`, `nav_set_blocked` for doors); Navigation Agents
walk their parent to a target (`nav_set_target`, `nav_stop`,
`nav_is_finished`, `nav_get_path`, `nav_distance_left`; events
`navigation_finished`, `target_unreachable`). `{radius = r}` keeps paths
clear of walls. Guide with tutorials: [`docs/navigation.md`](docs/navigation.md).

```lua
local level = Scene.find_node("Level")          -- a TileMap or LDtk level node
local x, y = self.node:get_position()
local path = level:nav_find_path(x, y, target_x, target_y, {radius = 12})   -- nil: no way
if path then
    self.path, self.next = path, 2               -- path[1] is the start
end
-- Navigation.find_path(level, x1, y1, x2, y2, {diagonal = false, smooth = false})
-- level:nav_is_walkable(x, y)
```

TileMaps: painted tiles are walls when the map is **solid**, else the
painted tiles are the floor (`walkable_painted` overrides). LDtk levels:
IntGrid cells whose collision rule is **Solid** are walls, on the finest
such layer's grid (the current level). Paths move in 8 directions without
cutting corners and are straightened where the line of sight is clear.
Grids are cached and rebuilt when the map changes. A search over a
256x256 grid takes about 4 ms (`bench_navigation`), so cache paths
rather than re-pathing every frame.

#### Physics: joints, one-way platforms, collision layers

- **Joint** nodes connect two bodies (Body A defaults to the joint's
  parent): revolute (hinge), distance, prismatic (slider), weld, wheel or
  motor, with motors, springs and limits. The joint is made when both
  bodies exist; parameters apply live:
  ```lua
  local hinge = self.node:get_child("Hinge")
  hinge:set_property("joint.revolute.enableMotor", true)
  hinge:set_property("joint.revolute.motorSpeed", 4)   -- radians/s
  ```
  Bodies are pixel-scale (a 40 px box has a mass of 1600), so motor torques
  are large: new joints default to 5,000,000.
- **One Way** on a StaticBody: bodies pass through from below and land on
  top ("top" turns with the node). LDtk one-way colliders use the same.
- **Collision layers** can be named in Project Settings > Physics; shapes
  list them by name, and scripts use them:
  ```lua
  self.node:set_collision_layer("Player")
  self.node:set_collision_mask("World", "Enemies", "Pickups")
  print(Physics.layer_name(2))   --> "Enemies"
  ```
- `node:set_property(path, value)` / `node:get_property(path)` read and
  write any Inspector property by its path (the paths complete per node
  class with their type and help, `get_property` returns the property's
  type and `set_property` checks the value; engine_api.lua's generated
  block, kept in step with the engine by test_lua_node_properties_definitions) - the help pane's `path = "..."`
  (hover the property; or drag its name into the script). Every node has
  `position`, `rotation`, `scale`, `layer`, `pauseMode`, `paused` and
  `enabled`; nodes that draw an image or a box also `origin` (a fraction of
  their size: `{0.5, 0.5}` the centre, `{0.5, 1}` the bottom centre); an
  AnimationPlayer also `fps` and `defaultAnimation`.
- **Another node's script**: `"script.<name>"` reads / writes a field of
  the node's script, live (`enemy:set_property("script.health", 50)`), and
  `node:get_script()` returns that script's `self` - its fields and methods:

  `get_script()` is typed: for a node name that runs a script in the
  project's scenes, `Scene.find_node("Enemy"):get_script()` has that
  script's class, so its exported fields and methods complete.

  ```lua
  local enemy = Scene.find_node("Enemy")
  enemy:get_script():take_damage(10)    -- call a method of its script
  local hp = enemy:get_script().health  -- or read any field it keeps
  ```

  `get_script()` is `nil` (and `get_property("script.x")` returns `nil`)
  when the node has no script; `set_property("script.x", ...)` on one is an
  error.

#### Draw order (zIndex, ySort)

Every node has `zIndex` (draw order within its layer, added to the
parent's), `ySort` (draw its children by Y: top-down / isometric depth) and
`ySortOffset` (added to its Y when its parent sorts) - as properties:
`node.zIndex = 10`, `world:set_property("ySort", true)`. Guide with a
tutorial: [`docs/draw_order.md`](docs/draw_order.md).

#### The audio mixer (Audio, buses)

Every sound and music plays into a bus (Master, Music, SFX and the
project's own, made in the **Mixer** tab): `Audio.set_bus_volume / mute /
solo / pan`, `Audio.get_buses`, `Audio.bus_peak`, `Audio.set_effect(bus,
effect, param, value)`, `Audio.set_effect_enabled`; `Audio.play_sound(path,
volume, pitch, bus)` and `Audio.play_music(path, loop, bus)`; Sound / Music
nodes have a `bus` property. Without a bus named, a sound plays into its
import settings' bus (else SFX / Music), at its import gain
([`docs/import_settings.md`](docs/import_settings.md)). Effects: EQ,
low-pass, high-pass, compressor, limiter, delay, reverb, distortion. Guide:
[`docs/audio_mixer.md`](docs/audio_mixer.md).

#### Skeletal animation (Spine, DragonBones)

Skeleton nodes play Spine / DragonBones exports: `skeleton_play(name,
loop, mix)`, `skeleton_stop`, `skeleton_set_skin`, `skeleton_animations`,
`skeleton_bone_position(name)` (world), `skeleton_set_bone_rotation(name,
deg | nil)` (aim); events `skeleton_event`(name), `animation_finished`.
Bone Attachment children follow a bone. Guide:
[`docs/skeletal_animation.md`](docs/skeletal_animation.md).

```lua
local hero = self.node:get_node("Body")
hero:skeleton_play("run")
hero:connect("skeleton_event", function(name) if name == "footstep" then Audio.play_sound("audio/step.wav") end end)
```

#### Accessibility and subtitles

`Accessibility.get(key)` / `set(key, value)` / `get_all()` / `save()` /
`reset()` - UI scale, colour filter, subtitles, captions, subtitle size and
backdrop, screen shake; saved for the player. `Subtitles.show(text,
{speaker, duration, caption, color})` / `hide(id)` / `clear()` / `count()`.
Dialogue nodes in Subtitles mode put their lines (with `voice` sounds) on
the track; Sound / Music nodes have a `caption`. Guide:
[`docs/accessibility.md`](docs/accessibility.md).

```lua
Accessibility.set("screen_shake", 0)
Subtitles.show("[engine sputters]", { caption = true })
box:dialogue_show({ { speaker = "Ada", text = "Hold on!", voice = "audio/vo/ada_hold.wav" } })
```

#### Player rebinding (Input)

`Input.listen(action, {on_done = ...})` captures the next key / button /
stick for an action (conflicts cleared, swapped or allowed), `Input.set_binding`,
`Input.get_bindings`, `Input.binding_text`, `Input.reset_bindings`,
`Input.get_actions`, `Input.last_device`; saved for the player and loaded at
start. UI menus work with a gamepad (D-pad / stick, A). The **Controls
Menu** script template builds a rebinding menu. `Scene.create_node` now
creates any node type. Guide: [`docs/input_rebinding.md`](docs/input_rebinding.md).

#### Changing scenes

`Scene.change_scene(name [, {transition, duration, color, loading, min_time}])`
- behind a fade / wipe / iris, or through a **loading screen** scene
(`loading = "loading"`) whose scripts read `Scene.loading_progress()` and
`Scene.loading_target()`. `Scene.preload(name)` / `Scene.preload_progress(name)`
load ahead. Textures decode on worker threads. Guide with a loading-screen
tutorial: [`docs/scene_flow.md`](docs/scene_flow.md).

#### Paths (PathNode, PathFollowNode)

A PathNode is a Bézier curve (`path_length`, `path_point_at(d)` -> world
position and direction, `path_closest_offset`, `path_add_point` / `path_set_point` /
`path_get_point` / `path_remove_point` / `path_clear`); a PathFollowNode child
travels along it (`progress`, `speed`, `loop` Stop / Loop / PingPong,
`rotate`, `sideOffset`; `follow_ratio`, `follow_set_ratio`, `follow_restart`;
events `path_finished`, `path_looped`). A CharacterMover rides whatever
floor it stands on when that floor moves. Guide:
[`docs/paths.md`](docs/paths.md).

#### Object pooling (Pool)

`Pool.take(component [, parent [, x, y]])` instead of `Scene.instantiate`
reuses parked instances; `node:destroy()` on a pooled node returns it.
Pooled roots' scripts get `on_spawn()` (every take, before the next update)
and `on_despawn()`. Also `Pool.prewarm`, `Pool.set_max`, `Pool.release`,
`Pool.stats`. Guide and tutorial: [`docs/pooling.md`](docs/pooling.md).

#### Procedural levels (LevelGen)

A generator file (`.levelgen.json`) is a graph of nodes - noise, random
fill, cellular caves, thresholds, combines - whose tile output writes a
level into a TileMap: `LevelGen.generate("levels/caves.levelgen.json",
tilemap, seed)`; `LevelGen.values(...)` returns the grid to place things on.
The same seed gives the same level. Guide:
[`docs/level_generator.md`](docs/level_generator.md).

#### Spawning (SpawnerNode)

A **Spawner** spawns components where it is - its world position, rotation
and flip, plus offsets - from its list: Single, All, Random (weighted),
Sequential (loop / ping-pong / stop) or Shuffle. Put it on a player and
`self.node:get_node("Muzzle"):spawn()` fires from the hand (the bullet goes
under the scene's root, so it doesn't follow). Also `spawn_at`,
`spawn_reset`, `spawn_alive_count`, `spawn_entries`, `spawn_add`; Auto
Spawn, cooldown, chance, max alive, total limit, spread, speed, pooling;
events `spawned`, `limit_reached`, `list_finished`; a signal can call its
`spawn` with no script. Node reference: Spawner.

Setting up what it spawns: values set on a spawned root right after
`spawn()` (script, built-in, resource and node properties) are seen by its
`ready()`. For every spawn - Auto Spawn, signals and pools included -
`spawner:set_spawn_callback(function(node, info, spawner) ... end)` runs
before the node's `ready()`, with `info.component` and `info.index` (the
list entry, from 1); `spawner:spawn_info(node)` gives the same for a live
spawned root (e.g. in a `spawned` handler).

```lua
for _, bullet in ipairs(self.node:get_node("Hand/Muzzle"):spawn()) do
    bullet:get_script().speed = 400
end
spawner:set_spawn_callback(function(enemy, info)
    enemy:get_script().weapon = weapons[info.index]
end)
```

#### Generated levels (LevelGeneratorNode)

A **Level Generator** node makes a level from a `.levelgen.json` into its
TileMap (a child, its parent or the **Tile Map** path) when the scene
starts: `generate([seed])` for another, `set_level_param(node_id, name,
value)` to change a generator node's parameter for this node's levels,
`level_param`, `clear_level_params`, `is_generating` (with **Background**
on). Events `generated` (the seed) and `generation_failed` (why); a signal
can call its `generate` with no script. Guide:
[`docs/level_generator.md`](docs/level_generator.md).

#### Visibility (VisibilityNotifierNode)

A child rectangle that knows whether the camera sees it: events
`screen_entered` / `screen_exited` (or `on_screen_entered` /
`on_screen_exited` on its script), `node.onScreen`, and an **action** on its
parent off screen (`Pause_Parent`, `Disable_Parent`, `Remove_Parent`).
Guide with examples: [`docs/visibility.md`](docs/visibility.md).

#### State machines (StateMachineNode)

A **StateMachine** node holds named states and arrows between them - for
**gameplay** (AI, player modes, doors, menus) as much as animation. Full
guide with tutorials (platformer with input buffering, enemy AI, combo
chain) and pitfalls: [`docs/state_machine.md`](docs/state_machine.md).

- **States** can play an animation on an AnimationPlayer (a sibling or
  child unless one is picked) - or none: a **gameplay state** whose logic is
  in its script callbacks. A state can run a **child state machine** while
  it is current (it starts when the state is entered and stops when it is
  left). **Allow Retrigger** lets a state go to itself (re-entered: on_exit,
  on_enter and the animation again).
- **Arrows** say which changes are possible, from a state (or *Any state*)
  to another, with a crossfade `blend`, and a **mode**:
  - **Manual** (the default for new arrows): only a script takes it, with
    `sm_transition(state)`.
  - **Automatic**: the machine takes it on its update when its conditions
    hold (no conditions = at once). Checked in order, at most one change per
    update.

  Arrows from scenes saved before modes existed load as Automatic.
- **Conditions**: a parameter `is true` / `is false` / `==` / `!=` / `>` /
  `<` a value, a **trigger** is set, the state's animation `finished`,
  `after` N seconds in the state, or **`script says`**: a method of the
  machine's script (else its parent's) that returns true. Rows are ANDed; an
  **`or`** row starts another group.
- **Parameters** are typed values scripts set (`bool`, `int`, `float`).
  **Triggers** are one-shot events, separate from parameters: `sm_trigger`
  sets one; the first Automatic arrow it opens uses it up; otherwise it is
  cleared after the machine's next update - or, with a **buffer** (seconds,
  per trigger), once it has waited that long (input buffering: a jump
  pressed just before landing). Triggers never take Manual arrows.
- **Guards** (on a state) refuse changes: **Leave After** N seconds, **Any
  State Interrupts** off, **Can leave when** / **Can enter when** condition
  lists, and the script guards `can_exit_<state>(next)` /
  `can_enter_<state>(previous)` returning false. They apply to Automatic
  arrows and `sm_transition`; `sm_transition(state, {force = true})` skips
  them.
- **Script callbacks** (on the machine's script, then its parent's, when
  defined), in this order: entering runs `on_enter_<state>(previous)`
  first, then the child machine starts and the animation plays;
  `on_update_<state>(dt)` runs every update while the state is current
  (also on the update it was entered); leaving stops the child machine,
  then `on_exit_<state>(next)` runs last (`next` is `""` on `sm_stop`). The
  editor's generated types list these for every state in the project, so
  the code editor completes `function Cls:on_enter_` with the names.
- The machine keeps the **last 32 changes** (`sm_history()`); the editor's
  State Machine tab shows them live, in Simulate and in the running game,
  with **Ways out** (each arrow from the current state, every condition's
  result and what blocks it) and pending triggers, and can **break on
  entering** a state.

Build it in the **State Machine** tab of the bottom panel: **Graph**,
**Parameters & Triggers**, **Settings** (the Inspector shows a summary).
A player feeding the machine, and an enemy deciding for itself:

```lua
function Player:update(dt)
    local sm = self.node:get_child("StateMachine")
    local vx, vy = self.node:character_get_velocity()
    sm:sm_set("speed", math.abs(vx))                           -- parameters: how things are
    sm:sm_set("on_floor", self.node:character_is_on_floor())
    if Input.is_action_pressed("jump") then sm:sm_trigger("jump") end  -- a trigger: what just happened
end

function Player:on_enter_jump(previous) self.node:get_child("JumpSound"):sound_play() end
function Player:can_enter_dash(previous) return self.stamina > 20 end  -- a guard

function Enemy:on_update_patrol(dt)
    if self:sees_player() then
        local ok, why = self.brain:sm_transition("chase")      -- along a Manual arrow
        if not ok then Log.info(why) end                       -- e.g. "patrol: leave after 1s (0.40s so far)"
    end
end

function Enemy:stun() self.brain:sm_transition("stunned", { force = true }) end
```

| Method | Arguments | Returns | Description |
|---|---|---|---|
| `sm_set(name, value)` | number or boolean | - | Sets a parameter (converted to its type; added as a float when missing). |
| `sm_get(name)` | `name` | boolean / integer / number / nil | A parameter's value, typed; nil when missing. |
| `sm_trigger(name)` | `name` | boolean | Sets a trigger (drives Automatic arrows). False and a warning (once) for an unknown name. |
| `sm_trigger_pending(name)` | `name` | boolean | The trigger is set and not used up yet. |
| `sm_clear_trigger(name)` | `name` | - | Un-sets a trigger (forget a buffered press). |
| `sm_transition(state [, {force, blend}])` | state name | boolean, reason | Goes there now along an arrow (Manual or Automatic) from the current state or Any state: guards and the arrow's conditions checked (when it has any); `force = true` skips both. `reason` says why not. |
| `sm_can_transition(state [, {force}])` | state name | boolean, reason | Whether `sm_transition` would work now, without changing anything. |
| `sm_state()` / `sm_previous()` | - | string | Current / previous state. |
| `sm_time()` | - | number | Seconds in the current state. |
| `sm_history()` | - | table | The last changes, oldest first: `{from, to, time, why}` (`why`: `start`, `manual`, `forced`, `transition N`). |
| `sm_start([state])` / `sm_stop()` | - | - | Start (initial state by default; pending triggers cleared) / stop (runs the current state's `on_exit_` with `""`). |

`sm_request` and `sm_travel` were removed: use `sm_transition(state)` and
`sm_transition(state, {force = true})` (see *Moving from sm_request /
sm_travel* in the guide). The machine emits `state_changed`(state) for
signal connections. Saved in the scene as `"state_machine": {"initial",
"player", "autostart", "params": [[name, value, "float"|"int"|"bool"]],
"triggers": [[name, buffer]], "states": [{"name", "animation", "child",
"pos", "retrigger", "min_time", "interruptible", "leave_when",
"enter_when"}], "transitions": [{"from", "to", "mode": "manual"|"auto",
"blend", "when": [["call", "sees_player"], ["or"], ["true", "alarm"]]}]}`.

#### Lighting (LightNode, scene ambient)

Add **Light** nodes (point, or spot: the node's rotation is the direction)
and set the scene's **Ambient** (Inspector with nothing selected, or
`Scene.set_ambient`) to darken what the lights don't reach. Lights with
*shadows* on are blocked by physics shapes (static/dynamic bodies,
character movers, LDtk and tile map colliders).

```lua
Scene.set_ambient(0.1, 0.1, 0.18)          -- night
local lamp = Scene.find_node("Lamp")
lamp:light_set_color(1, 0.8, 0.5)
lamp:light_set_energy(1.5 + math.sin(t * 20) * 0.2)   -- flicker
```

| Method | Parameters | Return | Description |
|---|---|---|---|
| `light_set_color(r, g, b)` | 0..1 | - | Light colour. |
| `light_set_energy(e)` / `light_get_energy()` | `number` | `number` | Brightness. |
| `light_set_radius(r)` | world units | - | Reach. |
| `Scene.set_ambient(r, g, b [, a])` / `Scene.get_ambient()` | 0..1 | r, g, b, a | Unlit colour of the scene. |

#### CharacterMoverNode

A CharacterMover has two **control modes** (Inspector: *Control Mode*):

- **Script** (Godot's `CharacterBody2D` style): the script owns the velocity
  and calls `character_move_and_slide()` every frame. **New Script** on a
  CharacterMover picks a documented **platformer template** (gravity, run
  with acceleration/friction, jump with coyote time, buffering and variable
  height, optional wall slide/jump, `jumped`/`landed` events) and switches
  the node to Script mode; delete what you don't need.
- **BuiltIn**: the node moves itself from its own settings (max speed,
  acceleration, jump speed, gravity scale, optional keyboard input);
  `character_move(dirX, jump)` steers it.

```lua
function Player:update(dt)
    local vx, vy = self.node:character_get_velocity()
    local gx, gy = self.node:character_get_gravity()
    vy = vy + gy * dt
    if Input.is_action_pressed("jump") and self.node:character_is_on_floor() then vy = -420 end
    vx = Input.get_axis("move_left", "move_right") * 240
    self.node:character_set_velocity(vx, vy)
    self.node:character_move_and_slide()
end
```

| Method | Parameters | Return | Description |
|---|---|---|---|
| `character_move_and_slide([dt])` | `dt: number` (default: frame delta) | `boolean` collided | Moves by the velocity and slides along surfaces; updates floor/wall/ceiling. Switches to Script mode. |
| `character_get_velocity()` | - | `vx, vy` | Velocity in px/s (+y down). |
| `character_set_velocity(vx, vy)` | `vx, vy: number` | - | Sets the velocity. |
| `character_get_gravity()` | - | `gx, gy` | World gravity x the node's gravity scale. |
| `character_set_gravity_scale(scale)` | `scale: number` | - | Gravity multiplier. |
| `character_is_on_floor()` / `character_is_on_wall()` / `character_is_on_ceiling()` | - | `boolean` | Contact state from the last move. |
| `character_get_floor_normal()` / `character_get_wall_normal()` | - | `nx, ny` | Normal of the floor / wall touched. |
| `character_get_last_motion()` | - | `dx, dy` | How far the last move went. |
| `character_set_control_mode(mode)` | `"script"` / `"builtin"` | - | Switches control mode. |
| `character_move(dirX, jump)` | `dirX: number, jump: bool` | - | BuiltIn mode: steer (dirX x max speed) and jump if grounded. |
| `character_is_grounded()` | - | `boolean` | Same as `character_is_on_floor()`. |
| `character_set_speed(speed)` / `character_set_jump_speed(speed)` | `number` | - | BuiltIn mode: max run speed / jump speed. |

#### AreaNode (Sensors)
| Method | Parameters | Return | Description |
|---|---|---|---|
| `area_is_overlapping()` | - | `boolean` | Checks if any bodies are inside sensor area. |
| `area_get_overlap_count()` | - | `integer` | Count of currently overlapping bodies. |
| `area_get_overlapping_nodes()` | - | `Node[]` | Array of currently overlapping nodes. |

#### RaycastNode
| Method | Parameters | Return | Description |
|---|---|---|---|
| `raycast_cast()` | - | - | Executes immediate ray query. |
| `raycast_is_colliding()` | - | `boolean` | Checks if ray hit an obstacle. |
| `raycast_get_hit_point()` | - | `x, y` | World hit point coordinates. |
| `raycast_get_hit_normal()` | - | `nx, ny` | Hit surface normal vector. |
| `raycast_get_hit_fraction()` | - | `number` | 0.0 to 1.0 fraction along ray. |
| `raycast_get_hit_node()` | - | `Node?` | Node attached to struck body. |
| `raycast_set_direction(dx, dy)` | `dx, dy: number` | - | Sets local cast direction vector. |
| `raycast_set_length(length)` | `length: number` | - | Sets ray length in pixels. |

#### ParticleEmitterNode
| Method | Parameters | Return | Description |
|---|---|---|---|
| `particle_start()` | - | - | Starts emitting particles. |
| `particle_stop()` | - | - | Stops emitting particles. |
| `particle_is_emitting()` | - | `boolean` | Checks if emission is active. |
| `particle_set_amount(count)` | `count: integer` | - | Sets max particles in pool. |
| `particle_set_lifetime(sec)` | `sec: number` | - | Sets particle lifespan in seconds. |

#### TextureNode
| Method | Parameters | Return | Description |
|---|---|---|---|
| `texture_get_size()` | - | `w, h` | Returns raw pixel dimensions. |
| `texture_set_origin(ox, oy)` | `ox, oy: number` | - | Sets rotation/scaling pivot offset. |
| `texture_get_path()` | - | `string` | File path of loaded texture. |

#### AnimationPlayerNode
| Method | Parameters | Return | Description |
|---|---|---|---|
| `animation_play([name [, blend]])` | `name?: string, blend?: number` | - | Starts or switches animation; `blend` crossfades from the current pose over that many seconds. |
| `animation_stop()` | - | - | Stops animation and freezes frame. |
| `animation_pause()` | - | - | Pauses animation playback. |
| `animation_resume()` | - | - | Resumes paused animation. |
| `animation_reset()` | - | - | Resets track to initial frame. |
| `animation_set_fps(fps)` | `fps: number` | - | Sets frames per second speed. |
| `animation_get_current()` | - | `string` | Gets name of active animation. |

#### TimerNode
| Method | Parameters | Return | Description |
|---|---|---|---|
| `timer_start()` | - | - | Starts/restarts timer from zero. |
| `timer_stop()` | - | - | Halts timer. |
| `timer_is_running()` | - | `boolean` | Checks if timer is active. |
| `timer_get_elapsed()` | - | `number` | Seconds elapsed since start. |
| `timer_set_duration(sec)` | `sec: number` | - | Sets countdown target duration. |
| `timer_set_loop(loop)` | `loop: boolean` | - | Enables automatic restart. |

#### SoundNode & MusicNode
| Method | Parameters | Return | Description |
|---|---|---|---|
| `sound_play()` / `sound_stop()` | - | - | Plays / stops sound effect. |
| `sound_pause()` / `sound_resume()` | - | - | Pauses / resumes sound effect. |
| `sound_play_index(i)` | `i` integer (1 = the first) | - | Plays one sound of its list, whatever the Play Mode (variation and delay apply). |
| `sound_count()` / `sound_last()` | - | integer | How many sounds it has / the one played last (0: none yet). |
| `music_play()` / `music_stop()` | - | - | Plays / stops music stream. |
| `music_pause()` / `music_resume()` | - | - | Pauses / resumes music stream. |

#### CameraNode (Node-invoked)
| Method | Parameters | Return | Description |
|---|---|---|---|
| `camera_set_zoom(zoom)` / `camera_get_zoom()` | `zoom: number` | `number` | Sets / gets camera zoom. |
| `camera_set_target(targetNode)` | `node: Node?` | - | Follows target node smoothly. |
| `camera_add_target(node, [opts])` | `opts: {weight, weight_x, weight_y, radius, offset_x, offset_y, priority}` | - | Adds a node to the group the camera frames (weighted centre; Auto Zoom fits them). |
| `camera_remove_target(node)` / `camera_clear_targets()` | `node: Node` | - | Removes one / stops following. |
| `camera_get_target()` / `camera_get_targets()` | - | `Node?` / `Node[]` | The followed node / every followed node. |
| `camera_set_target_position(x, y)` | `x, y: number` | - | Sets fixed target coordinates. |
| `camera_shake(trauma, [duration])` | `trauma, dur` | - | Triggers screen shake. |
| `camera_stop_shake()` / `camera_is_shaking()`| - | `boolean` | Controls / queries shake state. |
| `camera_set_limits(l, r, t, b)` | `l, r, t, b` | - | Sets viewport boundary limits. |
| `camera_clear_limits()` | - | - | Removes boundary limits. |

#### LDtk Node
| Method | Parameters | Return | Description |
|---|---|---|---|
| `ldtk_get_level_identifier()` | - | `string` | Active LDtk level identifier. |
| `ldtk_get_levels()` | - | `string[]` | All level identifiers in the project. |
| `ldtk_load_level(identifier)` | `string` | `boolean` | Switches level (rebuilds colliders and entities). |
| `ldtk_get_level_size()` | - | `number, number` | Level width and height in pixels. |
| `ldtk_get_level_field(name)` | `string` | `any` | A level custom field (arrays → tables, points → `{cx, cy}`). |
| `ldtk_get_entities([identifier])` | `string?` | `table[]` | Entities (`identifier, iid, x, y, width, height, tags, fields`). |
| `ldtk_get_entity_node(iid)` | `string` | `Node?` | The node spawned for an entity. |
| `ldtk_get_int_grid(layer, x, y)` | `string, number, number` | `integer` | IntGrid value at a world position (0 = empty). |

See `engine/LDTK.md` for the full LDtk integration.

---

### 2. Engine Module (`Engine`)

```lua
local fps = Engine.get_fps()
local dt = Engine.get_delta_time()
local elapsed = Engine.get_time()
local screen_w, screen_h = Engine.get_window_size()
local virtual_w, virtual_h = Engine.get_virtual_size()
Engine.set_fullscreen(not Engine.is_fullscreen())   -- e.g. an options menu toggle
```

---

### 3. Input Module (`Input`)

```lua
-- Check mapped actions
if Input.is_action_pressed("fire") then
    self:fire_laser()
end

if Input.is_action_down("boost") then
    self.speed = 350.0
end

-- 2D direction vectors (-1.0 to 1.0)
local move_x, move_y = Input.get_vector("move_left", "move_right", "move_up", "move_down")
self.node:translate(move_x * self.speed * dt, move_y * self.speed * dt)

-- Raw keyboard / mouse queries
if Input.is_key_pressed("SPACE") then ... end
if Input.is_mouse_button_pressed("LEFT") then ... end
local mouse_x, mouse_y = Input.get_mouse_position()
local wheel = Input.get_mouse_wheel_move()
```

---

### 4. Audio Module (`Audio`)

```lua
Audio.play_sound("assets/audio/laser.wav")
Audio.play_music("assets/audio/theme.ogg", true)
Audio.pause_music("assets/audio/theme.ogg")
Audio.resume_music("assets/audio/theme.ogg")
Audio.set_music_volume("assets/audio/theme.ogg", 0.5)
Audio.stop_music("assets/audio/theme.ogg")
Audio.set_master_volume(0.8)

-- One-shots overlap (4 voices per sound); optional volume and pitch.
Audio.play_sound("audio/hit.wav", 0.8, 1.2)
Audio.play_sound_at("audio/boom.wav", x, y)   -- distance + pan from the listener
Audio.set_listener(self.node)                  -- default: the current camera

-- Buses (also in Project Settings > Audio) and effects on the whole mix.
Audio.set_bus_volume("music", 0.4)             -- "master" | "music" | "sfx"
Audio.set_lowpass(800)                         -- muffled (0 = off)
Audio.set_reverb(0.35, 0.7)                    -- mix, room size (0 = off)

-- MusicNodes: fades and crossfades.
Audio.crossfade(Scene.find_node("CalmTheme"), Scene.find_node("BossTheme"), 2.0)
Scene.find_node("BossTheme"):music_fade(0, 1.5, true) -- fade out and stop
```

SoundNodes have **Voices** (how many times they can play over themselves;
1 restarts the sound) and **Positional** with **Min / Max Distance**: the
sound follows the node and the listener while it plays. The low-pass and
reverb process the whole mix (raylib's per-stream processors carry no
state per bus).

---

### 5. Camera Module (`Camera`)

```lua
-- Global operations on the active scene's main camera.
-- Usually no script is needed to follow the player: pick the camera's
-- Follow Target in the Inspector (saved with the scene).
Camera.set_target(self.node)

-- Frame several nodes (e.g. two players): weighted centre, and with the
-- camera's Auto Zoom on, zoomed to keep them all in view.
Camera.add_target(player1)
Camera.add_target(player2, { weight = 1, radius = 80 })
Camera.remove_target(player2)
Camera.clear_targets()
Camera.set_zoom(1.8)
Camera.shake(6, 0.3)   -- px; no arguments = the camera's Shake Preset

local wx, wy = Camera.screen_to_world(mouse_x, mouse_y)
local sx, sy = Camera.world_to_screen(player_x, player_y)
local cx, cy, cw, ch = Camera.get_visible_world_bounds()
```

**Advanced cameras** (virtual cameras the scene's camera hosts, blending
between them by priority; follow modes, LDtk level limits, trauma shake):

```lua
Camera.add_trauma(0.4)                       -- shake the active advanced camera (stacks to 1)
local cam = Camera.get_active()              -- nil when the scene has none
Scene.find_node("BossCam"):make_active()     -- priority above the others: the host blends to it
cam:add_trauma(0.2); cam:snap(); cam:is_active()
cam:connect("became_active", function() end) -- also "became_inactive"
```

Guide with tutorials: [`docs/advanced_camera.md`](docs/advanced_camera.md).

---

### 6. Physics Module (`Physics`)

```lua
Physics.set_gravity(0.0, 500.0)
local gx, gy = Physics.get_gravity()
Physics.set_paused(false)
Physics.set_debug_draw(false)   -- hide colliders / joints / areas (Project Settings > Physics: Show Colliders)

-- Cast ray across world coordinates
local hit = Physics.raycast(100.0, 100.0, 100.0, 600.0)
if hit then
    Log.info("Struck obstacle at:", hit.point_x, hit.point_y, "Normal:", hit.normal_x, hit.normal_y)
    if hit.node then
        Log.info("Struck node:", hit.node:get_name())
    end
end
```

---

### 7. Scene Module (`Scene`)

```lua
local player = Scene.find_node("SpaceShip")
local sceneName = Scene.get_name()
local allNodes = Scene.get_nodes()

-- Dynamically instantiate and parent new nodes at runtime
local sprite = Scene.create_node("TextureNode", "SpawnedExplosion", self.node)
sprite:set_position(0.0, 0.0)

-- Spawn a saved component (a .component.json) under a parent, at a position.
-- The result is typed as the component's root node (completion knows each
-- component file), or nil with a Console warning if the file is missing.
local rock = Scene.instantiate("components/AsteroidLarge.component.json", self.node:get_parent(), self.node.position)
rock:apply_impulse(Vec2(0, -200 * rock:get_mass()))  -- 200 px/s up

-- A node of a built-in or custom node type (its values and script), under
-- a parent, at a position; and a scene's nodes of a type.
local hurtbox = Scene.create("Hurtbox", self.node, 0, -8)
local all = Scene.find_nodes_of_type("Hurtbox")

-- Remove a node (and its children) at the end of the frame.
rock:queue_free()          -- same as rock:destroy()

-- Scene transitions
Scene.change_scene("battle_arena")
Scene.change_scene(self.next_level)   -- or its file (a `scene` property): "scenes/level_2.scene.json"
Scene.reload()
```

---

### 8. Log Module (`Log` / `print`)

```lua
Log.info("Player spawned at coordinates:", x, y)
Log.warn("Shield depleted!")
Log.error("Missing expected target node")
print("Standard Lua print works as Log.info")
```

Arguments are joined with tabs, each converted as `tostring` does (numbers,
booleans, `nil`, tables, nodes). The lines appear in the editor's
**Console**: from the game started with Play (its output, `[Lua]`,
`[Lua WARN]`, `[Lua ERROR]`; warnings and errors are coloured) and from
Simulate in Editor. A standalone game writes them to its standard output.

---

---

### 9. Project Module (`Project`)

The `Project` global table allows scripts, editor tools, and runtime launchers to inspect, load, serialize, and package portable `.rayzr` game archives directly from Lua:

```lua
-- Load a complete project from loose directory or .rayzr file
local success = Project.load("assets/demo_project.rayzr")

-- Check if an asset exists in mounted .rayzr or project directory
if Project.has_file("assets/scripts/enemy.lua") then
    local content = Project.read_file("assets/scripts/enemy.lua")
end

-- Serialize currently active scene to JSON string
local sceneJson = Project.serialize_scene()

-- Export loose directory to standalone compressed .rayzr package
Project.export_rayzr("my_project", "exports/release_game.rayzr")
```

### 10. Vector Module (`Vector`)

Draws vector shapes - crisp at any zoom, anti-aliased - from a script's
`on_draw()`, in the node's local space (its position, rotation and scale
apply). It works like an HTML canvas: build a path, then `fill()` or
`stroke()` it with the current style. What a node draws is tessellated once
and reused while the drawing stays the same, so static art costs nothing per
frame; drawing that changes every frame is re-tessellated (fine for
hundreds of curves). The [vector art guide](docs/vector.md) explains how.

```lua
local Gauge = {}
Gauge.properties = { value = { type = "range", min = 0, max = 1, default = 0.6 } }

function Gauge:on_draw()
    -- The track and the filled part, as arcs with round caps.
    Vector.line_cap("round")
    Vector.stroke_width(12)
    Vector.stroke_color("#37474f")
    Vector.begin_path()
    Vector.arc(0, 0, 40, 135, 405)
    Vector.stroke()
    Vector.stroke_paint(Vector.linear_gradient(-40, 0, 40, 0, { {0, "#66bb6a"}, {1, "#ef5350"} }))
    Vector.begin_path()
    Vector.arc(0, 0, 40, 135, 135 + 270 * self.value)
    Vector.stroke()
end

return Gauge
```

| Group | Functions |
|---|---|
| Paths | `begin_path`, `move_to`, `line_to`, `quad_to`, `cubic_to`, `arc`, `close_path`, `rect`, `circle`, `ellipse` |
| Drawing | `fill`, `stroke`, `clip` (until `restore`) |
| Style | `fill_color`, `stroke_color`, `fill_paint`, `stroke_paint`, `stroke_width`, `line_join`, `line_cap`, `miter_limit`, `dash`, `fill_rule`, `opacity` |
| Gradients | `linear_gradient(x0, y0, x1, y1, stops, spread)`, `radial_gradient(cx, cy, r, stops, spread)` - stops `{ {0, "#fff"}, {1, {0, 0, 1, 1}} }` |
| Transform | `save`, `restore`, `translate`, `rotate` (degrees), `scale` |

Colours are `"#rrggbb[aa]"`, `{r, g, b[, a]}` (0..1) or `r, g, b[, a]`.
Calling `Vector` outside `on_draw` is an error.

## Release Packaging & Virtual File System (VFS)

The engine features a transparent Virtual File System (**ScriptVFS**) that prioritizes embedded script bytecode in release builds while falling back to disk files during live development.

### Compile-Time Asset Embedding
Use Odin's `#load` compile-time directive to embed Lua scripts directly into the release executable:

```odin
// Register embedded script in game setup
e.ScriptVFS_RegisterEmbedded("assets/scripts/orbiting_drone.lua", #load("../assets/scripts/orbiting_drone.lua", string))
```

### Lua `require()` Support
The VFS registers a custom searcher in Lua's `package.searchers`. When a script calls:
```lua
local Helper = require("utils.math_helper")
```
The VFS automatically resolves the module from embedded memory or disk search paths (`assets/scripts/`, `scripts/`, `./`).

---

## Demo Game Integration

An autonomous Recon Drone behavior is integrated into the Asteroids demo game ([`asteroids/game.odin`](../asteroids/game.odin)) using [`assets/scripts/orbiting_drone.lua`](../assets/scripts/orbiting_drone.lua):

1. **Embedded at compile-time**:
   ```odin
   e.ScriptVFS_RegisterEmbedded("assets/scripts/orbiting_drone.lua", #load("../assets/scripts/orbiting_drone.lua", string))
   ```
2. **Spawned in the main game scene**:
   ```odin
   droneNode := e.TextureNode_Create(scene, &game.resourceManager, "assets/graphics/Space Pack/Ships/Ship_2.png")
   droneNode.name = "ReconDrone"
   droneNode.origin = {droneNode.size.x * 0.5, droneNode.size.y * 0.5}
   e.Script_AttachToNode(droneNode, "assets/scripts/orbiting_drone.lua", nil, &game.scriptManager)
   ```
3. **Smooth runtime execution**: The drone calculates its elliptical orbital trajectory around the scene center, aligns its rotation along its velocity tangent, and dynamically pulses its scale using the Lua scripting API.
