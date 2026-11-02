# Gamepads and local multiplayer

Up to four players, each with a controller; controllers plugged in and out
while the game runs; rumble; and button prompts that match the controller in
the player's hands (Space on a keyboard, A on an Xbox pad, Cross on a
PlayStation one, B on a Switch).

| | |
|---|---|
| Players | 1-4. Player 1 is the keyboard + mouse **and** the first gamepad; players 2-4 each have a gamepad. The same actions (Project Settings > Input) work for every player: `Input.is_action_down("jump", 2)` |
| Assignment | Player N has the Nth gamepad the OS lists, so the first pad plugged in is player 1's, the second player 2's. A pad nobody has goes to the first player without a connected pad. `Input.set_player_gamepad(player, pad)` reassigns (swapping, so two players never share one) |
| Hot-plug | Every script gets `on_gamepad_connected(player, name)` / `on_gamepad_disconnected(player)` |
| Rumble | `Input.vibrate(low, high, seconds[, player])` - the heavy and light motors, 0-1 each |
| Prompts | `Input.get_glyph(action[, player])` - an image path for the action's button on the player's device; any image takes it |
| Devices | `Input.get_device([player])`: `"keyboard"`, `"xbox"`, `"playstation"`, `"switch"`, `"steamdeck"`, `"generic"` or `"none"` - from the controller's name |

## Tutorial: two-player co-op

1. Make the player character a component (or a scene node with a script)
   with a `player` property:

```lua
---@class Hero : ScriptInstanceBase
local Hero = {}
Hero.properties = {
    player = { type = "int", default = 1, label = "Player" },
}

function Hero:update(dt)
    local p = self.player
    local x = Input.get_axis("move_left", "move_right", p)
    self.node:character_move(x, Input.is_action_pressed("jump", p))
    if Input.is_action_pressed("fire", p) then
        self:shoot()
        Input.vibrate(0.2, 0.6, 0.1, p) -- a kick in this player's hands
    end
end

return Hero
```

2. Put two of them in the level, `player` 1 and 2. Player 1 plays on the
   keyboard or the first controller, player 2 on the second.
3. Spawn player 2 only when there is a second controller - a "game" node
   that every script can't miss:

```lua
local Game = {}

function Game:ready()
    if Input.get_player_count() >= 2 then self:spawn(2) end
end

function Game:on_gamepad_connected(player, name)
    if player >= 2 then self:spawn(player) end
    Scene.find_node("Toast").text = "Player " .. player .. " joined (" .. name .. ")"
end

function Game:on_gamepad_disconnected(player)
    Engine.set_paused(true) -- "reconnect controller 2"
end

return Game
```

## Button prompts

`Input.get_glyph("jump")` is the image of the button the player presses for
`jump` now: the first binding for their device. Player 1 switches between
keyboard and controller prompts with what they touched last; other players
always get their pad's.

```lua
-- A "Press [A] to jump" hint that follows the device.
function Hint:update(dt)
    local g = Input.get_glyph("jump")
    if g ~= self.shown then
        self.node:get_node("Icon"):set_texture(g)
        self.shown = g
    end
end
```

The paths look like `prompts:xbox/xbox_button_a` - Kenney's
[Input Prompts](https://kenney.nl/assets/input-prompts) (CC0), built into
the engine: keyboard and mouse, Xbox, PlayStation, Switch and Steam Deck
(other pads get the Xbox images: raylib maps every pad to that layout).
Any of the pack's images can be used directly, e.g.
`prompts:playstation/playstation_dpad_up` or `prompts:keyboard/mouse_scroll`
(names: the pack's sheets in `engine/prompts/*.xml`).
`Input.get_glyph(action, player, "switch")` asks for one device's prompt.

Positions, not letters: raylib's `RIGHT_FACE_DOWN` is the bottom face button
on every pad - A on Xbox, Cross on PlayStation, B on Switch - and the
prompts follow.

Project Settings > Input shows each binding's prompt (pick the pad in
*Prompts*).

## Rumble

`Input.vibrate(low, high, seconds, player)`: `low` is the heavy (left)
motor, `high` the light (right) one. A new call replaces the one playing;
it stops after its seconds, with `Input.stop_vibration(player)`, or when the
pad is unplugged. `Input.get_vibration(player)` is what's playing.

raylib has no rumble on desktop (GLFW has no force feedback), so the engine
has a small native layer per platform:

| Platform | How | Limits |
|---|---|---|
| Windows | XInput | XInput pads (Xbox, and most others through Steam Input); a DualShock / DualSense without Steam Input doesn't rumble |
| Linux | evdev force feedback (`FF_RUMBLE`) on the pad's `/dev/input/event*` | Needs read-write access to the device (desktop sessions give it to the logged-in user) and a driver with force feedback |
| macOS | GameController + CoreHaptics | Controllers with haptics (Xbox, DualShock 4, DualSense, Switch Pro; macOS 11+); one motor: the stronger strength |
| Web | the browser's Gamepad API (raylib) | Browsers that have `vibrationActuator` |

## Testing with simulated controllers

The runner's `--input-script` plugs in simulated pads (they replace the real
pad in that slot):

```
# frame  pad   event
5        pad2  connect DualSense Wireless Controller
10       pad2  RIGHT_FACE_DOWN tap 3
12       pad2  LEFT_X -1
30       pad2  disconnect
```

`scripts/templates/test_templates.py --suite tests/gamepads/runtime_tests.json`
plays the engine's own gamepad tests this way (CI runs it). Engine code:
`Input_SimulatePad`, `Input_SimulatePadButton`, `Input_SimulatePadAxis`.

## How it works

- `engine/input_players.odin`: players, pads (real or simulated), hot-plug
  polling, devices from names. Player 1's states are the input system's
  usual ones; players 2-4 evaluate the same bindings on their pads only.
- `engine/input_rumble*.odin`: the rumble record and the per-OS layers.
- `engine/input_glyphs.odin`: which prompt for a binding and device; the
  sheets are embedded (about 220 KB), cut when an image is first used.
- `engine/input_players_lua.odin`: the Lua functions and the hot-plug events.

**Why not SDL?** raylib can run on SDL (which has rumble, a controller
database and hot-plug built in). We tried it first: Odin's `vendor:raylib`
links its own prebuilt raylib (GLFW), with no way to point it at another
build, so switching would mean forking the raylib bindings for the engine,
the editor and the UI libraries, and building raylib + SDL for every
platform in CI. The native layer is about 300 lines for the one thing GLFW
lacks (rumble); the rest (several pads, hot-plug, names, mappings) GLFW
already does.
