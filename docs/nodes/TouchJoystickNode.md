## What it's for

A Touch Joystick is an on-screen thumbstick for touch screens: phones and
tablets playing the web export. The thumb's push presses input actions, by
default `move_left`, `move_right`, `move_up` and `move_down`, with the
push's strength. So a game that reads actions works on a phone with no
script changes.

## When to use it

- **Moving on a phone**: a platformer's run, a top-down hero, a ship.
- **Aiming**: read `touch_get_vector()` for a second stick that aims.
- **Not** for tapping on things in the world: with **Touch as Mouse** on,
  taps already click (see [Input](../lua/Input.md)).

## Using it

1. Add a [Screen Layer](ScreenLayerNode.md) anchored **Bottom Left**,
   then **Add Node** (Cmd+A / Ctrl+A) > *Touch Joystick* under it.
2. Move it up and right from the corner, for example (130, -130), so the
   thumb reaches it.
3. In the Node tab's **Properties** set **Radius** (a full push),
   **Knob Radius**, the four actions and the colours.
4. Turn on **Floating** to have the joystick appear where the thumb lands
   anywhere in **Area**, a rectangle centred on the node. The editor
   outlines the area.

## How it works

- A finger that lands on the joystick (or in its area when floating)
  belongs to it until it lifts: it isn't the mouse and makes no gestures,
  and other fingers keep working, for example a jump button.
- The push is the thumb's distance from the middle divided by **Radius**,
  up to 1. Pushes under **Deadzone** count as none. Each direction's
  action gets its share: pushing up-right half-way presses `move_right`
  and `move_up` at about 0.35 each. `Input.get_vector` and
  `Input.get_axis` read them as they read a gamepad stick.
- The actions can be built-in ones or project actions (Project Settings >
  Input). Leave one empty to skip that direction.
- **Shown once touched**: it draws only after the device has been touched,
  so keyboard and gamepad players never see it. **Always Show** shows it
  from the start; the editor always shows it.

## Scripts

`stick:touch_get_vector()` returns this frame's push as x, y (-1..1).
`stick:touch_is_down()` says whether a thumb is on it.

## Example

```lua
-- Aim with a second joystick named "Aim" (its actions left empty).
local x, y = Scene.find_node("Aim"):touch_get_vector()
if x ~= 0 or y ~= 0 then self.node:set_rotation(math.deg(math.atan(y, x))) end
```
