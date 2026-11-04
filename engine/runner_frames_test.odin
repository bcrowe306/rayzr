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

// #331: an opaque frame gets its alpha in the copy to the window (no
// full-screen pass of its own) unless post effects or the colour-blind
// filter read it first; frames not meant to be opaque get neither.
@(test)
test_runner_opaque_frame :: proc(t: ^testing.T) {
	pass, inCopy := Runner_OpaqueFrame(false, 255, 0, false)
	testing.expect(t, !pass && inCopy, "plain: in the copy")
	pass, inCopy = Runner_OpaqueFrame(false, 255, 2, false)
	testing.expect(t, pass && !inCopy, "post effects: a pass first")
	pass, inCopy = Runner_OpaqueFrame(false, 255, 0, true)
	testing.expect(t, pass && !inCopy, "colour-blind filter: a pass first")
	pass, inCopy = Runner_OpaqueFrame(true, 255, 0, false)
	testing.expect(t, !pass && !inCopy, "smooth camera: neither")
	pass, inCopy = Runner_OpaqueFrame(false, 128, 0, false)
	testing.expect(t, !pass && !inCopy, "see-through clear colour: neither")
}
