## What it's for

A GOAP Agent (goal-oriented action planning) lets a character work out
**how** to reach a goal by itself. You describe:

- what it can want: **goals**;
- what it can do: **actions**, each with conditions, effects and a cost;
- what it knows about the world: **keys** and the **sensors** that fill
  them.

It picks the cheapest goal it can reach and the chain of actions that gets
there. When the world changes, it plans again. It works like
[crashkonijn's GOAP](https://github.com/crashkonijn/GOAP) for Unity.

## When to use it

- **Characters with many ways to reach a goal.** A villager who needs wood
  can buy an axe, borrow one, or punch a tree, whichever is cheapest now.
- **Survival and simulation AI**: hunger, tiredness, resources and jobs.
- **Not** for a fixed order of steps or simple priorities: a
  [Behavior Tree](BehaviorTreeNode.md) is easier to read and tune. An
  action can run a Behavior Tree, so the two work together.
- **Not** for animation states: use a [State Machine](StateMachineNode.md).

## Using it

1. Select the character and **Add Node** (Ctrl+A) > *GOAP Agent*. It acts
   for its parent.
2. The **GOAP** tab opens in the bottom panel. On the **Keys & Sensors**
   page, add:
   - **World keys**: whole numbers such as `HasAxe`, `Wood` or `Hunger`.
   - **Target keys**: positions such as `TreeSpot`.
   - **Sensors** that fill them, for example a Node sensor for `TreeSpot`.
3. On **Goals & Actions**, click **+ Goal**. Give it conditions, for
   example `Wood >= 3`, and a cost. A goal's cost is its priority: cheaper
   wins.
4. Click **+ Action** for each thing it can do. Set:
   - what it **Does**: Script, Behavior Tree, Wait, Call Method or Play
     Animation;
   - its **Cost**;
   - a **Target** to go to first;
   - its **Conditions**, for example `HasAxe >= 1`;
   - its **Effects**, for example `Wood` Increase.
5. The graph shows each goal as a row: the goal, then the actions that can
   meet its conditions, then theirs. A red dot in edit mode is a condition
   that no action can meet.
6. Play the scene, or Simulate. While it runs:
   - the plan is outlined blue and the running action green;
   - the links along the plan turn cyan;
   - each condition shows its live value;
   - disabled actions are orange.

   In Play, select the agent in the scene tree to watch the running game.

## How it works

- **Planning.** It searches back from each requested goal.
  - Each condition that isn't met now leads to the actions whose effects
    move that key the right way: `>` and `>=` need an Increase, `<` and
    `<=` a Decrease.
  - It goes on through those actions' own conditions until it reaches an
    action it can do now: its conditions are met and its target is known.
  - The cheapest path wins. The cost is the goal's cost, plus each action's
    cost, plus the distance between targets times **Distance Multiplier**.
  - Only the first action runs. When it ends, the agent plans again.
  - The planner doesn't imagine the world changing: sensors tell it how
    things are.
- **Goals.** By default every goal is requested (**Request All**). A
  script can pick them with `goap_request_goal`. A goal completes when its
  conditions are met, and the `goal_completed` signal fires.
- **Running an action.**
  - With a **Target**, the agent goes there first: with its
    [Navigation Agent](NavigationAgentNode.md) if it has one, otherwise
    straight at **Move Speed**. It stops when **In Range**.
  - **Move Mode** *Perform While Moving* runs the action on the way.
  - **Requires Target** stops the action when the target is lost.
    **Check Conditions** stops it when its conditions stop being met.
- **Re-planning.** **Resolve Interval** plans again every few seconds, but
  only while the action allows it (`continue_or_resolve`), so a cheaper
  goal can take over.
- **Effects** only guide the planner. On a key that no sensor fills,
  completing an action also adds or takes 1, which is handy for things the
  agent carries.
- **Sensors** run every frame, once, or every interval.
  - *Script*: a Lua sensor.
  - *Method*: a method of the actor's script.
  - *Property*: a node's number property; for a target key, the node's
    position.
  - *Nearest With Tag*: the nearest node with a tag; for a world key, how
    many there are.
  - *Node*: a node; for a world key, 1 while it exists.
- **Global keys** are shared by every GOAP agent, for example
  `AlarmRaised`.

## Lua actions, sensors and goals

Mark a script's class with `goap`. It then appears in the tab's pickers,
and its properties are edited there.

```lua
---@class ChopAction
local Chop = {}
Chop.goap = "action"
Chop.properties = { swings = { type = "int", default = 3 } }

function Chop:start(actor) self.left = self.swings end

-- Every frame (once in range): "continue", "continue_or_resolve",
-- "completed", "stop", or { wait = seconds, ["then"] = "completed" }.
function Chop:perform(actor, ctx)
    self.left = self.left - 1
    if self.left > 0 then return { wait = 0.4 } end
    return "completed"
end

-- Optional: is_valid(actor), before_perform(actor), finish(actor),
-- get_cost(actor, target_position).
return Chop
```

```lua
---@class HungerSensor
local Hunger = {}
Hunger.goap = "sensor"
function Hunger:sense(actor) return actor:get_property("hunger") end -- a number; a target sensor returns a node or a vector
return Hunger
```

A goal script (`X.goap = "goal"`) has `get_cost(actor)`, so its priority
can change: hungrier makes "Eat" cheaper.

Each script's `self.agent` is the GOAP node, and `self.actor` its actor.

## Signals

| Signal | When | Value |
|---|---|---|
| `goal_started` | It picked a new goal | the goal's name |
| `goal_completed` | The goal's conditions are met | the goal's name |
| `action_started` | An action began | its name |
| `action_completed` | An action completed | its name |
| `action_stopped` | An action stopped early | its name |
| `no_action_found` | Nothing it can do reaches a requested goal | none |

## Scripts

- `agent:goap_request_goal("Eat", "Wander")` sets the goals it may pick
  from.
- `agent:goap_set_key("Hunger", 80)` and `goap_get_key(key)` change and
  read world keys.
- `agent:goap_set_target("Enemy", node or position)` and
  `goap_get_target(key)` change and read target keys.
- `agent:goap_goal()`, `goap_action()`, `goap_plan()` and `goap_state()`
  say what it's doing. `goap_resolve()` plans now.
- `agent:goap_disable_action("Shoot", 2)` and `goap_enable_action(name)`
  turn an action off, for example for a cooldown, and back on.

## Example

A lumberjack:

| | Conditions | Effects | Cost | Target |
|---|---|---|---|---|
| Goal **GatherWood** | Wood >= 3 | | 1 | |
| Action **PickUpAxe** | | HasAxe Increase | 1 | AxeSpot |
| Action **ChopWood** | HasAxe >= 1 | Wood Increase | 1 | TreeSpot |
| Action **PunchTree** | | Wood Increase | 20 | TreeSpot |

Node sensors fill `AxeSpot` and `TreeSpot`. The agent walks to the axe,
then chops three times. Punching would work too, but it costs more. Take
the axe away (`goap_disable_action("PickUpAxe")`) and it punches instead.
