package engine

import "core:strings"
import "core:testing"

// #284: the project's tests run headless - tests/game_tests/project has
// passing tests (input, holds, wait_until, load_scene, replay), failing
// ones (expect, a Lua error, a timeout) and a skipped one.
@(test)
test_game_tests_runner :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	testing.expect(t, game->loadProject("tests/game_tests/project"), "fixture loaded")
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	Tests_Start(game, "*")
	defer Tests_Shutdown(game)
	testing.expect_value(t, len(gameTests.cases), 10)
	frames := 0
	for frames < 5000 {
		Tests_BeforeFrame(game)
		game->run(1.0 / 60)
		frames += 1
		if !Tests_AfterFrame(game) do break
		free_all(context.temp_allocator)
	}
	testing.expect(t, gameTests.phase == .Finished, "every test ran")
	testing.expect_value(t, gameTests.passed, 6)
	testing.expect_value(t, gameTests.failed, 3)
	testing.expect_value(t, gameTests.skippedCount, 1)
	testing.expect_value(t, Tests_ExitCode(), 1)

	// The test functions a file defines (not local ones, not in strings).
	names := Tests_FunctionNames("function test_a()\nlocal function test_b() end\n  function test_c ()\nx = function test_d() end\n")
	testing.expect(t, len(names) == 2 && names[0] == "test_a" && names[1] == "test_c", strings.join(names[:], ",", context.temp_allocator))

	// A recording's text is an input script Test.replay reads.
	Recorder_Start(game)
	testing.expect(t, inputRecorder.on, "recording")
	text := strings.clone(strings.to_string(inputRecorder.sb), context.temp_allocator)
	Recorder_Discard()
	events, why := Runner_LoadInputScript(strings.concatenate({text, "3 SPACE down\n4 mouse 10.0 20.0 down\n5 pad1 LEFT_X 0.500\n"}, context.temp_allocator), context.temp_allocator)
	testing.expect(t, why == "" && len(events) == 3, why)
	free_all(context.temp_allocator)
}
