package engine

import "core:testing"

// #358: --frames N alone ends the run after N frames. #362: a capture
// (--screenshot / --dump-scene) is of frame N, not of max(25, N).
@(test)
test_runner_frames :: proc(t: ^testing.T) {
	opts := Engine_ParseRunArgs({"game", "--frames", "120", "--hidden"})
	testing.expect(t, !Runner_FramesOver(opts, 119), "runs its frames")
	testing.expect(t, Runner_FramesOver(opts, 120), "--frames alone: over after N")
	testing.expect(t, !Runner_FramesOver(Engine_ParseRunArgs({"game"}), 100000), "no --frames: runs on")
	testing.expect(t, !Runner_FramesOver(Engine_ParseRunArgs({"game", "--frames", "10", "--bench", "100"}), 10), "a benchmark counts its own")

	testing.expect_value(t, Runner_CaptureFrame(Engine_ParseRunArgs({"game", "--frames", "6", "--dump-scene", "d.json"})), 6)
	testing.expect_value(t, Runner_CaptureFrame(Engine_ParseRunArgs({"game", "--frames", "90", "--screenshot", "s.png"})), 90)
	testing.expect_value(t, Runner_CaptureFrame(Engine_ParseRunArgs({"game", "--screenshot", "s.png"})), 30)
}
