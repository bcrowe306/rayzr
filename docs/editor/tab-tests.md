# Tests tab

The **Tests** tab runs your game's own tests: Lua files in the project's
`tests/` folder that play the game - load a scene, press actions, wait -
and check what happened. Each test runs in the game runner, hidden, with
its own save folder, so your saves and the scene you're editing are never
touched. For writing tests, read [Test](../lua/Test.md).

## When to use it

- **Catching regressions**: the jump still clears the gap, the door still
  opens with the key, the score still counts, after you change a script.
- **Checking a bug stays fixed**: write a test that does what the player
  did, see it fail, fix the bug, see it pass.
- **Replaying a play session**: record yourself in Play with the toolbar's
  **Record** button, then replay it in a test and check the end state.

## What's in it

- **Run All** runs every test. **Run Failed** runs the first failed test
  again. The circular arrow finds the tests again after you add a file or
  a test (a run finds them too).
- **Filter tests** shows only tests whose file or name contains the text.
- The summary: how many passed, failed and were skipped, and how long the
  run took.
- The tests, by file: `tests/<something>_test.lua`, each
  `function test_<name>()` in it. The play button by a file runs its tests;
  the one by a test runs just that test. Each shows a circle (not run), a
  check (passed), a cross (failed) or a skip mark, and the frames and
  milliseconds it took.
- Under a failed test, its failures: the line and the message. Double-click
  one to open that line in the Code tab; double-click a test to open where
  it's defined. Select a test to see a Lua error's whole traceback.

## Recording

While the game runs (Play), the toolbar has a red **Record** button next to
Stop. Press it, play, press it again (now a square): your keys, mouse,
gamepads and touches are saved to `tests/recordings/recording_N.txt`, and
the Console says the name. In a test, `Test.replay("recording_N")` loads the
scene you started in and plays the input back, frame by frame.

## Tips

- Run the tests before you commit: a test that ran before and fails now
  points at what just broke.
- Failures also go to the Console, with the file and line.
- Tests save files as you edited them first (scenes and scripts), like Play.
- Replays are exact at 60 frames a second; a game whose logic depends on
  the real time between frames can drift a little from what you saw.
