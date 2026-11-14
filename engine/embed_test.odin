package engine

import "core:fmt"
import "core:os"
import "core:testing"
import rl "vendor:raylib"

// Play in Viewport (embed.odin, platform_input.odin): the editor's input
// as the game reads it, and frames through the shared block.

@(test)
test_embed_remote_input :: proc(t: ^testing.T) {
	In_SetRemote(true)
	defer In_SetRemote(false)
	In_SetMouseScale(1, 1)
	In_SetMouseOffset(0, 0)

	// A key down: pressed this frame only, down until it's up.
	In_BeginFrame()
	In_ApplyEvents(fmt.tprintf("k%d+ k%d+ c104 c105 m10.5,20 b0+ w0,2 f1", int(rl.KeyboardKey.RIGHT), int(rl.KeyboardKey.A)))
	testing.expect(t, In_IsKeyDown(.RIGHT))
	testing.expect(t, In_IsKeyPressed(.RIGHT))
	testing.expect(t, !In_IsKeyReleased(.RIGHT))
	testing.expect_value(t, In_GetKeyPressed(), rl.KeyboardKey.RIGHT)
	testing.expect_value(t, In_GetKeyPressed(), rl.KeyboardKey.A)
	testing.expect_value(t, In_GetKeyPressed(), rl.KeyboardKey.KEY_NULL)
	testing.expect_value(t, In_GetCharPressed(), 'h')
	testing.expect_value(t, In_GetCharPressed(), 'i')
	testing.expect_value(t, In_GetCharPressed(), rune(0))
	testing.expect_value(t, In_GetMousePosition(), rl.Vector2{10.5, 20})
	testing.expect(t, In_IsMouseButtonPressed(.LEFT) && In_IsMouseButtonDown(.LEFT))
	testing.expect_value(t, In_GetMouseWheelMove(), f32(2))
	testing.expect(t, In_IsWindowFocused())

	// The next frame: still down, no longer pressed; the mouse moved.
	In_BeginFrame()
	In_ApplyEvents(fmt.tprintf("m14.5,23 k%dr", int(rl.KeyboardKey.RIGHT)))
	testing.expect(t, In_IsKeyDown(.RIGHT))
	testing.expect(t, !In_IsKeyPressed(.RIGHT))
	testing.expect(t, In_IsKeyPressedRepeat(.RIGHT))
	testing.expect(t, !In_IsMouseButtonPressed(.LEFT) && In_IsMouseButtonDown(.LEFT))
	testing.expect_value(t, In_GetMouseDelta(), rl.Vector2{4, 3})
	testing.expect_value(t, In_GetMouseWheelMove(), f32(0))

	// Down and up within one frame still counts as a press.
	In_BeginFrame()
	In_ApplyEvents(fmt.tprintf("k%d+ k%d-", int(rl.KeyboardKey.SPACE), int(rl.KeyboardKey.SPACE)))
	testing.expect(t, In_IsKeyPressed(.SPACE) && In_IsKeyReleased(.SPACE) && !In_IsKeyDown(.SPACE))

	// "r": the editor took the input back - everything up.
	In_BeginFrame()
	In_ApplyEvents("r f0")
	testing.expect(t, !In_IsKeyDown(.RIGHT) && In_IsKeyReleased(.RIGHT))
	testing.expect(t, !In_IsMouseButtonDown(.LEFT) && In_IsMouseButtonReleased(.LEFT))
	testing.expect(t, !In_IsWindowFocused())

	// The runner's letterbox applies to the editor's mouse as to raylib's.
	In_BeginFrame()
	In_SetMouseOffset(-100, 0)
	In_SetMouseScale(0.5, 0.5)
	In_ApplyEvents("m300,200")
	testing.expect_value(t, In_GetMousePosition(), rl.Vector2{100, 100})
	In_SetMouseOffset(0, 0)
	In_SetMouseScale(1, 1)

	// Junk is ignored.
	In_ApplyEvents("k k99999+ kx+ b9+ mnope w1 c-5 zz")
	testing.expect(t, !In_IsMouseButtonDown(.LEFT))
}

@(test)
test_embed_sizes_and_commands :: proc(t: ^testing.T) {
	sz, ok := Embed_ParseSize("640x360")
	testing.expect(t, ok)
	testing.expect_value(t, sz, [2]i32{640, 360})
	_, ok = Embed_ParseSize("640")
	testing.expect(t, !ok)
	sz, _ = Embed_ParseSize("9000x4")
	testing.expect_value(t, sz, [2]i32{EMBED_MAX_W, 16})

	// The Game view's link commands.
	saved := embed
	defer embed = saved
	In_SetRemote(true)
	defer In_SetRemote(false)
	testing.expect(t, Embed_Command(nil, "embed-size", "800 450"))
	testing.expect_value(t, embed.size, [2]i32{800, 450})
	testing.expect(t, embed.resize)
	testing.expect(t, Embed_Command(nil, "in", fmt.tprintf("k%d+", int(rl.KeyboardKey.W))))
	testing.expect(t, In_IsKeyDown(.W))
	testing.expect(t, !Embed_Command(nil, "pause", ""))
}

@(test)
test_embed_frames_through_shared_memory :: proc(t: ^testing.T) {
	when !SHM_SUPPORTED do return
	name := Shm_Name(os.get_pid(), 990)
	defer delete(name)
	editor, ok := Shm_Create(name, EMBED_BYTES)
	testing.expect(t, ok, "create")
	if !ok do return
	defer Shm_Close(&editor)
	Embed_InitBlock(&editor)
	_, _, _, _, any := Embed_ReadLatest(&editor, 0)
	testing.expect(t, !any, "no frame yet")

	// The game's side: the same block, opened by name.
	game, gok := Shm_Open(name, EMBED_BYTES)
	testing.expect(t, gok, "open")
	if !gok do return
	saved := embed
	defer embed = saved
	embed = {enabled = true, shm = game}
	defer Shm_Close(&embed.shm)

	px := make([]u8, 4 * 3 * 4)
	defer delete(px)
	for i in 0 ..< len(px) do px[i] = u8(i)
	embed_store(raw_data(px), 4, 3)
	got, w, h, seq, rok := Embed_ReadLatest(&editor, 0)
	testing.expect(t, rok)
	testing.expect_value(t, w, i32(4))
	testing.expect_value(t, h, i32(3))
	testing.expect_value(t, seq, u64(1))
	testing.expect_value(t, got[5], u8(5))
	testing.expect(t, Embed_StillValid(&editor, seq))
	_, _, _, _, again := Embed_ReadLatest(&editor, seq)
	testing.expect(t, !again, "nothing newer")

	// Newer frames go to the other slots; the old slot is rewritten after
	// EMBED_SLOTS frames (a reader still on it drops it).
	for _ in 0 ..< EMBED_SLOTS do embed_store(raw_data(px), 2, 2)
	testing.expect(t, !Embed_StillValid(&editor, seq))
	_, w, h, seq, _ = Embed_ReadLatest(&editor, seq)
	testing.expect_value(t, seq, u64(1 + EMBED_SLOTS))
	testing.expect_value(t, w, i32(2))
}
