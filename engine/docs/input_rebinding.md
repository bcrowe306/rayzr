# Input actions and player rebinding

Games read **actions** (`jump`, `move_left`, `pause`) instead of raw keys;
Project Settings > **Input** maps each action to keys, mouse buttons,
gamepad buttons and stick directions. Players can then change those
bindings in your game's controls menu - saved for them and loaded every
time the game starts.

## The quickest way: the Controls Menu template

1. Add a **UI Container** where the menu goes (an options screen),
   vertical layout.
2. Inspector > Script > **New Script** - the **Controls Menu (rebinding)**
   template is picked for a container. Create.
3. Run. It lists every action (except those in its **Hide** property,
   `confirm, cancel` by default) with the key it uses; clicking a key
   button shows **Press a key...** - the next key, mouse button or gamepad
   button is bound (Escape cancels). **Reset to defaults** puts back the
   project's bindings.

Its properties: **Device** (the buttons change the keyboard / mouse binding,
the gamepad one, or the first one), **Hide**, column widths. The generated
script is plain Lua - restyle or extend it.

## Gamepads in menus

UI menus work without a mouse: the **D-pad or the left stick** move the
focus between buttons (holding repeats, like the arrow keys) and **A**
presses the focused one - the same as Up/Down/Left/Right and Enter on a
keyboard.

## Building your own menu

```lua
-- One row: the action, its keys, a button to change them.
function Options:show_jump()
    self.jump_label.text = "Jump: " .. Input.get_binding_text("jump") -- "Space / A"
end

function Options:on_rebind_jump_pressed()
    self.jump_label.text = "Jump: press a key..."
    Input.listen("jump", {
        device = "keyboard",            -- or "gamepad", "any"
        on_done = function(result, text)
            -- result: "bound" or "cancelled"; text: e.g. "Left Shift"
            self:show_jump()
        end,
    })
end

function Options:update(dt)
    if Input.is_listening() then return end   -- ignore menu input meanwhile
    ...
end
```

Listening waits until every key and button is released before it starts,
so the Enter / A press that opened it isn't taken as the new binding.

### Conflicts

When the new binding is already used by another action:

| `conflicts` | |
|---|---|
| `"clear"` (default) | The other action loses it. |
| `"swap"` | The other action gets this action's old binding. |
| `"allow"` | Both keep it. |

```lua
Input.listen("dash", {conflicts = "swap"})
local users = Input.find_conflicts({key = "SPACE"})   -- {"jump"}
```

### Setting bindings directly

```lua
Input.set_binding("jump", 1, {key = "W"})                       -- slot 1
Input.set_binding("jump", 2, {button = "RIGHT_FACE_DOWN"})      -- A
Input.set_binding("move_left", 3, {axis = "LEFT_X", positive = false})
Input.set_binding("jump", 2, nil)                              -- remove slot 2
for i, b in ipairs(Input.get_bindings("jump")) do
    print(i, b.device, b.name, b.text)                          -- 1 key SPACE Space
end
Input.reset_bindings("jump")    -- or Input.reset_bindings() for all
```

Slot `0` (and `listen` without a slot) replaces the action's first binding
of the same kind of device - so a keyboard rebind keeps the gamepad
binding.

### Keyboard or gamepad prompts

```lua
function Hint:update(dt)
    local pad = Input.get_last_device() == "gamepad"
    -- The interact action: slot 1 is its key, slot 2 its gamepad button.
    self.node.text = "Press " .. Input.get_binding_text("interact", pad and 2 or 1)
end
```

## Names shown to players

| Binding | Text |
|---|---|
| `{key = "LEFT_SHIFT"}` | Left Shift |
| `{key = "KP_5"}` | Numpad 5 |
| `{mouse = "RIGHT"}` | Mouse Right |
| `{button = "RIGHT_FACE_DOWN"}` | A (B, X, Y, LB, RB, LT, RT, Start, Back, L3, R3, D-Pad Up...) |
| `{axis = "LEFT_X", positive = true}` | Left Stick Right |

## API

| Function | |
|---|---|
| `Input.get_actions()` | The project's actions, in order. |
| `Input.get_bindings(action)` | `{device, name, key / mouse / button / axis, positive, text}` per binding. |
| `Input.get_binding_text(action [, slot])` | "Space / A", or one slot's text. |
| `Input.set_binding(action, slot, binding \| nil [, conflicts])` | Set / remove a binding. |
| `Input.listen(action [, {slot, device, conflicts, cancel, on_done}])` | Capture the next press. |
| `Input.is_listening()` / `Input.cancel_listen()` | |
| `Input.reset_bindings([action])` | Back to the project's. |
| `Input.save_bindings()` | (Done automatically after each change.) |
| `Input.find_conflicts(binding)` | Actions using it. |
| `Input.get_last_device()` | `"keyboard"` or `"gamepad"`. |

## Where it's saved

`input_bindings.json` next to the save files (macOS: `~/Library/Application
Support/<game>/`, Windows: `%APPDATA%\<game>\`, Linux:
`~/.local/share/<game>/`), in the same format as the project's `"input"`
section. It's applied over the project's bindings when the game starts;
actions that were removed from the project since are skipped. In the editor
(Simulate) the project's bindings are used, not a player's file.

## Notes

- Capturing reads keys with `IsKeyPressed` (it doesn't take keys away from
  text fields or other code).
- Triggers bind as buttons (LT / RT), sticks as axis directions.
