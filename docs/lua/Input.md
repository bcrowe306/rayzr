## Use it for

- **Moving and acting**: read the project's actions (Project Settings > Input) with `get_vector` / `get_axis` for movement and `is_action_pressed` / `is_action_down` / `is_action_released` for buttons. Actions work with the keyboard and gamepads alike, so prefer them to raw keys.
- **Debug keys and mouse aiming**: `is_key_pressed("F5")` for developer shortcuts, `get_mouse_position` with `Camera.screen_to_world` to aim or click in the world.
- **Button prompts**: `glyph` gives the image for an action on the device the player uses now (a key, or A / Cross on a pad); `binding_text` gives it as text ("Space / A").
- **A controls menu**: list `get_actions`, start a "press a key..." prompt with `listen`, and offer `reset_bindings`. Changes are saved for the player.
- **Local co-op**: pass a player number (1-4) to the action functions, and use `player_count`, `gamepads` and `set_player_gamepad` for a "press A to join" screen.
- **Rumble**: `vibrate` a player's gamepad on hits and explosions.
- **Controllers that aren't recognised**: `open_controller_setup` shows the built-in Controller Setup screen (press each button; saved for the player). Build your own with `mapping_begin` / `mapping_state` / `mapping_finish`.
- **Flight sticks, wheels, arcade panels**: `get_joysticks`, `get_joystick_button`, `get_joystick_axis` and `get_joystick_hat` read any controller's raw inputs.
- **Touch screens** (the web export on phones and tablets): `get_touches` lists the fingers. Gestures come as `get_tap`, `get_double_tap`, `get_long_press`, `get_swipe` and `get_pinch`, or as methods on any script: `on_tap(x, y)`, `on_double_tap(x, y)`, `on_long_press(x, y)`, `on_swipe(dx, dy, speed)` and `on_pinch(scale, dx, dy)`. On-screen [Touch Joystick](../nodes/TouchJoystickNode.md) and [Touch Button](../nodes/TouchButtonNode.md) nodes press actions, so action-based games need no changes.

## Example

A top-down ship that moves with the move_* actions, fires with **fire** (with a short rumble) and shows the fire button's prompt on a child [Texture](../nodes/TextureNode.md) named *Prompt*. The script is on the ship.

```lua
---@class Ship : ScriptInstanceBase
local Ship = {}

Ship.properties = {
    speed = { type = "float", default = 200, label = "Speed" }, -- px/s
}

function Ship:ready()
    self.prompt = self.node:get_node("Prompt") ---@type TextureNode
    self.device = nil
end

function Ship:update(dt)
    -- Move: get_vector is capped at length 1, so diagonals aren't faster.
    local dx, dy = Input.get_vector("move_left", "move_right", "move_up", "move_down")
    local x, y = self.node:get_position()
    self.node:set_position(x + dx * self.speed * dt, y + dy * self.speed * dt)

    if Input.is_action_pressed("fire") then
        Log.info("pew")
        Input.vibrate(0.3, 0.6, 0.1)
    end

    -- Swap the prompt when the player picks up the other device.
    local device = Input.get_device()
    if device ~= self.device then
        self.device = device
        local image = Input.get_glyph("fire")
        if image then self.prompt:set_texture(image) end
    end
end

return Ship
```

## Notes

- **Pressed and released are for one frame.** Read them in `update`, every frame; a check that only runs now and then can miss them.
- **The mouse is in game-screen pixels** (the virtual resolution, before the camera). Pass it to `Camera.screen_to_world` for world coordinates. Mouse buttons read false while a UI widget has the mouse, so a click on a button isn't also a shot.
- **Unknown names don't error**: a misspelled action or key just reads false (or 0). If nothing happens, check the name against Project Settings > Input.
- **Touch as mouse** (Project Settings > Input, on by default): the first finger is also the left mouse button, so taps click buttons and `is_mouse_button_pressed` / `get_mouse_position` work on phones. A finger on an on-screen control isn't the mouse and makes no gestures. `is_touch_device()` turns true at the first touch, for "Tap to start" instead of "Press Space".
- **A controller whose buttons do nothing** has no mapping. Rayzr ships a controller database and guesses a standard layout for unknown ones, so this is rare. Fix it with Controller Setup (`open_controller_setup`, or Tools > Controllers in the editor). See [Gamepads](../../engine/docs/gamepads.md#controllers-that-arent-recognised).
- **Players**: player 1 is the keyboard, the mouse and the first gamepad; players 2-4 each get the next gamepad. Scripts get `on_gamepad_connected(player, name)` and `on_gamepad_disconnected(player)`.
- More in [Input rebinding](../../engine/docs/input_rebinding.md) and [Gamepads](../../engine/docs/gamepads.md).
