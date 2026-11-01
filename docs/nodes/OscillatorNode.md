## What it's for

An Oscillator is a wave that drives numbers on other nodes: a platform's
position, a pickup's scale, a light's energy, a sprite's alpha. One
oscillator can drive several properties at once, each over its own range.
It saves keyframing anything that just goes back and forth.

## When to use it

- **Moving platforms**: a Sine on `position.x` or `position.y`.
- **Bobbing and pulsing**: a pickup's `position.y` and `scale` together.
- **Flicker**: Smooth Noise on a light's energy or a sprite's `color.a`.
- **Blinking**: a Square on `color.a`, with a short Pulse Width.
- **A row of things in a wave**: one oscillator, a mapping per node, each
  with a different **Phase**.
- **Not** for motion with keys and easing, or for changing several things
  at set times: use an [Animation Player](AnimationPlayerNode.md).
- **Not** for following a route: use a [Path Follow](PathFollowNode.md).

## Using it

1. **Add Node** (Ctrl+A) > *Oscillator*. Add it under the node it moves
   (a child's mappings point at `..`, its parent) or anywhere else.
2. Pick a **Wave** and a **Rate**. **Rate Unit** says whether Rate is in
   Hertz (cycles a second) or Seconds (the length of one cycle).
3. In **Mappings**, click **Add Mapping**. A new mapping bobs its parent
   up and down: node `..`, property `position.y`, -16 to 16.
4. For each mapping, set:
   - **Node**: pick it, or drop it from the scene tree.
   - **Property**: a number (`rotation`), one component (`position.x`,
     `scale.y`, `color.a`) or a whole vector or colour (`scale`, `color`).
     The list shows the node's number properties.
   - **Mode**: *Relative* (the default) adds the value to what the
     property was when the oscillator started, so a platform moves around
     where you placed it. *Absolute* sets the property to the value.
   - **Min** and **Max**: the value at the bottom and the top of the wave.
     Colours are 0-255 for each channel.
   - **Phase**: shifts this mapping along the cycle, in degrees. 180 is
     half a cycle out of step.
   - **Value Offset**: added to the value.
5. Click **Preview** to see it move in the editor. **Stop Preview** puts
   the targets back. Saving or an undo step while it previews keeps the
   real values, never the previewed ones.
6. **Autostart** (on by default) starts it with the scene. **Loops** stops
   it after that many cycles (0 runs forever).

## How it works

- The wave's value goes from 0 to 1 each cycle, and picks a point between
  Min and Max.
  - **Sine** starts in the middle and rises.
  - **Triangle** rises for half the cycle and falls for the other half.
  - **Square** is high for **Pulse Width** of the cycle, then low.
  - **Saw** rises and drops; **Reverse Saw** drops and rises.
  - **Random** holds a new random value for each cycle.
  - **Smooth Noise** glides from one random value to the next.
  - **Curve** is the curve you draw in the **Wave** section: time 0-1
    across, value 0-1 up.
- **Seed** makes Random and Smooth Noise give the same values every run.
  0 is different each run.
- **Start** remembers each target's value, then runs from the start of the
  cycle. **Stop** puts the values back and rewinds. **Pause** holds the
  values where they are. **Resume** carries on from the same point in the
  cycle.
- After **Loops** cycles it stops with its targets at their last values
  and emits `finished`. The next Start uses the values it remembered
  before, so a Relative mapping doesn't drift.
- It runs on game time: the game's time scale, slow motion and hit-stop
  change its speed, and it stops when the game pauses, unless its
  **Pause Mode** says otherwise.
- Several mappings can drive the same node, or the same property. They are
  applied in order.
- Renaming or moving a target node in the editor keeps the mapping pointed
  at it.

## Signals

| Signal | When | Value |
|---|---|---|
| `cycle` | A cycle ended | the cycles run since Start |
| `finished` | **Loops** cycles ran | none |

## Scripts

- `osc:oscillator_start()`, `oscillator_stop()`, `oscillator_pause()` and
  `oscillator_resume()`.
- `local state, cycles = osc:oscillator_state()` returns `"stopped"`,
  `"running"` or `"paused"`, and the cycles since Start. 2.25 is a quarter
  of the way into the third cycle.
- `osc:oscillator_add_mapping("../Door", "position.y", 0, -64)` adds a
  mapping. Pass `true` as a fifth argument for Absolute. For a whole
  vector or colour, give tables: `{0.5, 0.5}, {1.5, 1.5}`. A property can
  also be a material parameter, `"shader:<name>"`.
- `osc:oscillator_clear_mappings()` removes them all and puts their
  targets back.
- Its settings are properties like any node's:
  `osc:set_property("rate", 2)`.

## Example

A platform that only moves while the player stands on a switch. The
platform has a child Oscillator named `Move` with **Autostart** off and a
mapping `..` / `position.x` from 0 to 160.

```lua
---@class Switch : ScriptInstanceBase
local Switch = {}

function Switch:ready()
    self.move = Scene.find_node("Move") ---@type OscillatorNode
end

function Switch:on_body_entered(body)
    if body == nil or body:get_name() ~= "Player" then return end
    local state = self.move:oscillator_state()
    if state == "paused" then
        self.move:oscillator_resume()
    elseif state == "stopped" then
        self.move:oscillator_start()
    end
end

function Switch:on_body_exited(body)
    if body ~= nil and body:get_name() == "Player" then
        self.move:oscillator_pause() -- it carries on from here next time
    end
end

return Switch
```
