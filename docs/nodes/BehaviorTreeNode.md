## What it's for

A Behavior Tree decides what a character does: patrol, chase, attack,
flee, look for cover. It is a tree of small pieces. **Composites** choose
which children run and in what order. **Decorators** change a child's
answer. **Leaves** do the work: move somewhere, play an animation, check a
value, or run a Lua script.

Each tick (each frame by default), the tree runs from its root. Every node
answers **Success**, **Failure** or **Running** (not done yet, carry on
next tick). It works like [Beehave](https://github.com/bitbrain/beehave)
for Godot, and supports the same nodes.

## When to use it

- **Enemy and NPC AI** with priorities: flee when hurt, else attack when
  close, else chase when seen, else patrol.
- **Sequences of steps** that can fail part way: walk to the door, open
  it, go through.
- **Not** for a character's animation states (idle, run, jump): use a
  [State Machine](StateMachineNode.md). A tree can drive a State Machine
  with its State Machine leaves.
- **Not** for long-range planning with many possible actions: that is
  GOAP's job.

## Using it

1. Select the character and **Add Node** (Ctrl+A) > *Behavior Tree*. It
   acts for its parent, the **Actor**.
2. The **Behavior Tree** tab opens in the bottom panel. Click **Add Root
   Selector**, or right-click the canvas.
3. Right-click a node to:
   - **Add Child**: pick a composite, decorator, action or condition.
     Your own Lua leaves are listed too.
   - **Wrap In**: put a decorator or composite around the node.
   - **Change To**: make it another kind of node.
   - **Move Left / Right**, or **Delete**.
4. Drag a node onto a sibling to take its place, or onto another
   composite to become its last child.
5. Click a node to edit it in the side panel. The settings shown depend
   on its kind. "$key" in a value reads the blackboard.
6. The **Blackboard** page holds the tree's starting values.
7. Play the scene, or Simulate. The tab lights each node with its last
   answer: running yellow, success green, failure red. In Play, select the
   tree in the scene tree to watch the running game.

## How it works

**Composites** run their children left to right.

| Composite | Answer |
|---|---|
| Sequence | Success when every child succeeds. It stops at the first failure. A Running child is resumed next tick. |
| Sequence Star | A Sequence that retries the child that failed, instead of starting over. |
| Sequence Reactive | A Sequence that starts from the first child every tick, so earlier conditions are checked again. |
| Selector | The first child that succeeds. Children that failed aren't tried again while a later one runs. |
| Selector Reactive | A Selector that starts from the first child every tick, so a higher-priority branch takes over as soon as it can. |
| Sequence Random / Selector Random | A shuffled order, new each run. Weights make some children come first more often, and **Seed** makes the order repeatable. |
| Simple Parallel | Runs its first child (the primary) and its second together. Its answer is the primary's. |

**Decorators** have one child.

| Decorator | What it does |
|---|---|
| Inverter | Swaps Success and Failure. |
| Always Succeed / Always Fail | Succeeds or fails whatever the child answers. |
| Until Fail | Runs the child until it fails. |
| Repeater | Runs the child N times. |
| Limiter | Lets the child run for at most N ticks. |
| Time Limiter | Lets the child run for at most this many seconds. |
| Cooldown | After the child ends, fails until this many seconds have passed. |
| Delayer | Waits before running the child. |

**Leaves**:

- **Wait**: a number of seconds, plus an optional random extra.
- **Move To**: a node, or a position on the blackboard. It uses the
  actor's [Navigation Agent](NavigationAgentNode.md) if it has one, and
  otherwise moves straight at **Speed**.
- **Play Animation**: plays an animation, and can wait until it ends.
- **Set Property**: sets a property of a node.
- **Call Method**: calls a method of a node's script. It answers with what
  the method returns.
- **Emit Signal** and **Wait For Signal** (with a timeout).
- **Blackboard Set / Erase / Has / Compare**: **Global** uses the global
  blackboard.
- **State Machine Set / Trigger / In State**: drive the actor's
  [State Machine](StateMachineNode.md).
- **Subtree**: runs another Behavior Tree node. Set that one to
  **Manual**.
- **Log**: writes a message to the log.

**Running**:

- A node's `before_run` runs when it starts, and its `after_run` when it
  answers Success or Failure.
- When a composite moves on, or the tree is interrupted, the running
  branch is interrupted: each running node's `interrupt` runs.
- **Active** off interrupts the tree.
- **Tick Rate** ticks every N frames. Timers still see the whole time.
- **Manual** ticks only when a script calls `bt_tick()`.

**Blackboards**:

- Each tree has its own blackboard.
- **Blackboard From** shares another tree's blackboard.
- The global blackboard (`Blackboard` in Lua) is shared by every tree.
- Values are true / false, numbers, `x, y` vectors or text. A node is kept
  as its path.

## Lua leaves

A script becomes a leaf when its class says what kind it is. It then
appears in the tab's **Add Child** menu. Its properties are edited in the
side panel, and each leaf has its own instance of the script.

```lua
---@class SeePlayer
local SeePlayer = {}
SeePlayer.behavior = "condition" -- or "action"
SeePlayer.properties = {
    range = { type = "float", default = 200 },
}

-- Every tick while it runs: "success", "failure" or "running"
-- (true / false work too; nothing is success).
function SeePlayer:tick(actor, blackboard, dt)
    local player = Scene.find_node("Player")
    if player == nil then return "failure" end
    if actor.position:distance(player.position) > self.range then return "failure" end
    blackboard:set("target", player)
    return "success"
end

-- Optional: before_run, after_run and interrupt get (actor, blackboard).
return SeePlayer
```

`self.tree` is the Behavior Tree node and `self.actor` its actor.

## Signals

| Signal | When | Value |
|---|---|---|
| `tree_enabled` | **Active** turned on | none |
| `tree_disabled` | **Active** turned off; the tree was interrupted | none |

## Scripts

- `tree:bt_tick(dt)` runs a tree once (**Manual** trees), and returns
  `"success"`, `"failure"` or `"running"`.
- `tree:bt_interrupt()` and `tree:bt_status()`.
- `tree:bt_get(key)`, `bt_set(key, value)`, `bt_has(key)` and
  `bt_erase(key)` read and change the blackboard. Pass `true` as the last
  argument for the global blackboard.
- `tree:bt_blackboard()` returns the blackboard as an object with `get`,
  `set`, `has`, `erase` and `keys`. `Blackboard:get("alarm")` reads the
  global one.
- `tree:bt_running_action()` and `tree:bt_last_condition()` say what's
  running and the last condition checked.

## Example

A guard that flees when hurt, attacks when close and patrols otherwise:

```
Selector Reactive
├── Sequence
│   ├── Blackboard Compare   hp < 20
│   └── Move To              Target Key: safe_spot
├── Sequence
│   ├── SeePlayer            (a Lua condition, Range 120)
│   ├── Cooldown 1s
│   │   └── Call Method      attack
│   └── Wait 0.3s
└── Sequence Star
    ├── Move To              ../../WaypointA
    ├── Wait 1-2s
    ├── Move To              ../../WaypointB
    └── Wait 1-2s
```

The guard's own script keeps its health on the blackboard:

```lua
function Guard:on_hit(damage)
    self.hp = self.hp - damage
    self.node:get_node("Brain"):bt_set("hp", self.hp)
end
```
