## What it's for

A Touch Button is an on-screen button for touch screens: phones and
tablets playing the web export. While a finger is on it, it presses an
input action such as `jump` or `fire`, so a game that reads actions works
on a phone with no script changes.

## When to use it

- **Actions on a phone**: jump, attack, fire, interact, pause.
- **With a [Touch Joystick](TouchJoystickNode.md)**: move with the left
  thumb, act with the right.
- **Not** for menus: with **Touch as Mouse** on, a tap clicks a
  [UI Button](UIButtonNode.md).

## Using it

1. Add a [Screen Layer](ScreenLayerNode.md) anchored **Bottom Right**,
   then **Add Node** (Cmd+A / Ctrl+A) > *Touch Button* under it, at for example
   (-110, -110).
2. In the Node tab's **Properties** set **Action** (an input action's
   name), **Label**, **Radius** and the colours.

## How it works

- A finger that lands on the button belongs to it until it lifts. While
  it's down the action is down, pressed on the first frame and released
  when the finger lifts, as with a key. The finger isn't the mouse and
  makes no gestures.
- The action can be built-in (`jump`, `fire`, `interact`, `pause`...) or a
  project action (Project Settings > Input). Several, comma-separated,
  are pressed together: `interact, confirm` talks to someone and moves
  their dialogue on.
- **Shown once touched**: it draws only after the device has been touched.
  **Always Show** shows it from the start; the editor always shows it.

## Scripts

`button:touch_is_down()` says whether a finger is on it.

## Example

The platformer template's jump button: a Touch Button with **Action**
`jump` and **Label** `A` under a Screen Layer anchored bottom right.
`Input.is_action_pressed("jump")` in the player's script needs no change.
