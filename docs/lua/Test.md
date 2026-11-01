## Use it for

- **Testing that your game still works**: a test loads a scene, plays it - `Test.press("jump")`, `Test.step(20)` - and checks the result with `Test.expect`. Run them from the editor's [Tests tab](../editor/tab-tests.md).
- **Input like a player's**:
  - `press` taps an action and `hold` / `release` keep it down. They use the action's own key, so project actions work as in the game.
  - `press_key` presses a key itself.
  - `click` and `move_mouse` drive the mouse, in game units.
- **Waiting for something**: `Test.step(n)` runs n frames. `Test.wait_until(fn, frames)` runs until `fn()` is true and returns whether it happened in time.
- **Replaying a recording**: `Test.replay("recording_1")` plays back input recorded in Play with the toolbar's **Record** button, from the scene it started in.
- **Checks**:
  - `expect`, `expect_eq` and `expect_near` record a failure and go on.
  - `require` and `fail` stop the test.
  - `skip` stops it without failing.

## Example

A file `tests/player_test.lua`. Each `function test_<name>()` is one test.

```lua
local function player() return Scene.find_node("Player") end

function test_jump_leaves_the_ground()
    Test.load_scene("level1")
    local _, y = player():get_global_position()
    Test.press("jump")
    Test.step(15)
    local _, y2 = player():get_global_position()
    Test.expect(y2 < y - 20, "the player is in the air")
end

function test_coin_counts()
    Test.load_scene("level1")
    Test.hold("move_right")
    local got = Test.wait_until(function() return GameState.coins > 0 end, 300)
    Test.release("move_right")
    Test.require(got, "walked into the first coin within 5 seconds")
    Test.expect_eq(GameState.coins, 1, "one coin")
end

function test_replay_level_one()
    Test.replay("recording_1") -- recorded in Play: finishing level 1
    Test.expect_eq(Scene.get_name(), "level2", "reached level 2")
end
```

## Notes

- **Every test starts fresh**: the project's first scene loaded again, no keys down, the time scale at 1, and the same random seed (`math.random` gives the same numbers each run). Global scripts and their tables (`GameState`) are not reset - set what a test depends on at its start.
- **Input is simulated**: the real keyboard, mouse and pads are ignored while tests run. `press` releases the action after 2 frames by default; the game sees it as pressed on the next frame, so `Test.step` after it.
- **Time is a fixed 1/60 s a frame** and runs as fast as the computer can, so `Test.step(60)` is one second of game time.
- **A test fails** on a failed check, a Lua error (the message shows the traceback), or after `Test.timeout` frames: a minute of game time unless the test sets another limit.
- **Files**: tests go in `tests/`, in files named `*_test.lua`, as `function test_<name>()` at the start of a line. `local` functions in them are helpers, not tests. Each file has its own globals, so two files can both define `player()`.
- Outside a test, `Test.is_running()` is false and the other calls are errors. Use `Test.is_running()` in game scripts to skip an intro or a splash screen while tested.
- `Test.expect` returns whether it passed, so `if not Test.expect(...) then return end` stops early without failing twice.
