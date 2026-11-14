package engine

import "core:fmt"
import "core:log"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:time"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// Play in Viewport (the editor's Game view): the real game, launched by the
// editor as for Play (--editor-link), but its window is hidden and every
// frame goes to the editor through shared memory instead of the screen.
// The editor sends the keyboard and the mouse back over the link ("in"
// lines: platform_input.odin), so the game plays inside the editor while
// every Play tool (Game tab, breakpoints, Pause / Step, Remote) works as is.
//
//   --embed <name> --embed-size <w>x<h>   open the editor's block, a window
//                                         of that size (in points)
//   embed-size <w> <h>                    the Game view changed size
//   embed-mute 0|1                        the Game view's mute button
//   in <events>                           input (In_ApplyEvents)
//   -> @rayzr:stats {"fps", "ms", "nodes", "w", "h"}   twice a second (ms: a
//                                         frame's update + draw, w h: the window)
//
// The frame isn't drawn on the hidden window (a hidden window's pixels are
// undefined on some drivers) but into a texture the window's size in points
// (Embed_BeginDraw / Embed_EndDraw around the runner's last pass), and read
// back from there.
//
// The block: a header, then EMBED_SLOTS frames of up to EMBED_MAX_W x
// EMBED_MAX_H RGBA pixels each (bottom row first, as OpenGL reads them).
// The game fills the next slot, then publishes its number; the editor
// shows the newest whole one (a slot whose seq changed while it read is
// dropped).
// ============================================================================

EMBED_MAGIC :: u32(0x52_5A_46_42) // "RZFB"
EMBED_VERSION :: u32(1)
EMBED_SLOTS :: 3
EMBED_MAX_W :: 3840
EMBED_MAX_H :: 2160
EMBED_SLOT_BYTES :: EMBED_MAX_W * EMBED_MAX_H * 4
EMBED_HEADER_BYTES :: 256
EMBED_BYTES :: EMBED_HEADER_BYTES + EMBED_SLOTS * EMBED_SLOT_BYTES

Embed_Slot :: struct {
	seq:    u64, // the frame it holds (0: being written)
	width:  u32, // pixels
	height: u32,
}

Embed_Header :: struct {
	magic:     u32,
	version:   u32,
	slotBytes: u64,
	latest:    u64, // the newest whole frame's seq (0: none yet)
	slots:     [EMBED_SLOTS]Embed_Slot,
}
#assert(size_of(Embed_Header) <= EMBED_HEADER_BYTES)

Embed_State :: struct {
	enabled:   bool,
	shm:       Shared_Memory,
	seq:       u64,
	size:      [2]i32, // the window, in points (asked by the editor)
	resize:    bool,   // apply `size` at the next frame
	statsAt:   f64,
	frames:    int,  // since the last stats line
	frameMs:   f64, // work (update + draw), not the wait for the next frame
	frameStart: time.Tick,
	pbo:       [2]u32, // async readback (embed_gl.odin)
	pboSize:   [2][2]i32,
	pboFence:  [2]rawptr,
	pboFrame:  int,
	target:    rl.RenderTexture2D, // the frame, drawn off screen (Embed_BeginDraw)
}

embed: Embed_State

Embed_Header_Of :: proc(shm: ^Shared_Memory) -> ^Embed_Header {
	return cast(^Embed_Header)shm.data
}

Embed_SlotPixels :: proc(shm: ^Shared_Memory, slot: int) -> [^]u8 {
	return shm.data[EMBED_HEADER_BYTES + slot * EMBED_SLOT_BYTES:]
}

// Embed_InitBlock: a new block's header (the editor, after Shm_Create).
Embed_InitBlock :: proc(shm: ^Shared_Memory) {
	h := Embed_Header_Of(shm)
	h^ = {}
	h.magic = EMBED_MAGIC
	h.version = EMBED_VERSION
	h.slotBytes = EMBED_SLOT_BYTES
}

// Embed_ParseSize reads "1280x720" (false: not a size).
Embed_ParseSize :: proc(s: string) -> ([2]i32, bool) {
	i := strings.index_byte(s, 'x')
	if i < 0 do return {}, false
	w, ok1 := strconv.parse_int(s[:i])
	h, ok2 := strconv.parse_int(s[i + 1:])
	if !ok1 || !ok2 || w < 1 || h < 1 do return {}, false
	return Embed_ClampSize({i32(w), i32(h)}), true
}

// Embed_ClampSize keeps a size the block can hold.
Embed_ClampSize :: proc(s: [2]i32) -> [2]i32 {
	return {clamp(s.x, 16, EMBED_MAX_W), clamp(s.y, 16, EMBED_MAX_H)}
}

// Embed_Open maps the editor's block (before the window opens).
Embed_Open :: proc(name: string, size: [2]i32) -> bool {
	shm, ok := Shm_Open(name, EMBED_BYTES)
	if !ok {
		log.errorf("--embed %s: can't open the editor's frame buffer", name)
		return false
	}
	if h := Embed_Header_Of(&shm); h.magic != EMBED_MAGIC || h.version != EMBED_VERSION {
		log.errorf("--embed %s: not a Rayzr frame buffer (or another version)", name)
		Shm_Close(&shm)
		return false
	}
	embed = {enabled = true, shm = shm, size = size}
	In_SetRemote(true)
	Embed_KeepAwake()
	return true
}

Embed_Enabled :: proc() -> bool {return embed.enabled}

Embed_Close :: proc() {
	if !embed.enabled do return
	embed_gl_release()
	if embed.target.id != 0 && rl.IsWindowReady() do rl.UnloadRenderTexture(embed.target)
	Shm_Close(&embed.shm)
	embed = {}
}

// Embed_Command: the Game view's link commands (false: not one of them).
Embed_Command :: proc(game: ^Game, cmd, rest: string) -> bool {
	switch cmd {
	case "in":
		In_ApplyEvents(rest)
	case "embed-size":
		f := strings.fields(rest, context.temp_allocator)
		if len(f) == 2 {
			w, ok1 := strconv.parse_int(f[0])
			h, ok2 := strconv.parse_int(f[1])
			if ok1 && ok2 {
				embed.size = Embed_ClampSize({i32(w), i32(h)})
				embed.resize = true
			}
		}
	case "embed-mute":
		rl.SetMasterVolume(0 if rest == "1" else 1)
	case:
		return false
	}
	return true
}

// Embed_BeginFrame resizes the window when the Game view asked.
Embed_BeginFrame :: proc() {
	if !embed.enabled do return
	embed.frameStart = time.tick_now()
	if !embed.resize do return
	embed.resize = false
	if rl.GetScreenWidth() != embed.size.x || rl.GetScreenHeight() != embed.size.y {
		rl.SetWindowSize(embed.size.x, embed.size.y)
	}
}

// Embed_BeginDraw (after BeginDrawing): the runner's last pass - the frame
// scaled to the window, the console - goes to the Game view's texture.
Embed_BeginDraw :: proc() {
	if !embed.enabled do return
	w := clamp(rl.GetScreenWidth(), 1, EMBED_MAX_W)
	h := clamp(rl.GetScreenHeight(), 1, EMBED_MAX_H)
	if embed.target.id == 0 || embed.target.texture.width != w || embed.target.texture.height != h {
		if embed.target.id != 0 do rl.UnloadRenderTexture(embed.target)
		embed.target = rl.LoadRenderTexture(w, h)
	}
	rl.BeginTextureMode(embed.target)
}

// Embed_EndDraw (before EndDrawing): sends the frame to the editor, and the
// stats line twice a second.
Embed_EndDraw :: proc(game: ^Game) {
	if !embed.enabled do return
	rlgl.DrawRenderBatchActive()
	// (Read while the texture is bound; bottom row first, as the window's.)
	embed_read_frame(embed.target.texture.width, embed.target.texture.height)
	rl.EndTextureMode()

	embed.frames += 1
	embed.frameMs += time.duration_milliseconds(time.tick_since(embed.frameStart))
	now := rl.GetTime()
	if now - embed.statsAt >= 0.5 {
		nodes := 0
		if s := game.sceneManager.currentScene; s != nil && s.manager != nil {
			for n in s.manager.nodes do if n != nil do nodes += 1
		}
		ms := embed.frameMs / f64(max(embed.frames, 1))
		fps := f64(embed.frames) / (now - embed.statsAt) if embed.statsAt > 0 else 0
		fmt.printfln(`@rayzr:stats {{"fps":%.0f,"ms":%.2f,"nodes":%d,"w":%d,"h":%d}}`, fps, ms, nodes, rl.GetScreenWidth(), rl.GetScreenHeight())
		embed.statsAt = now
		embed.frames = 0
		embed.frameMs = 0
	}
}

// embed_store: pixels (w x h RGBA, bottom row first) into the next slot.
embed_store :: proc(pixels: [^]u8, w, h: i32) {
	hdr := Embed_Header_Of(&embed.shm)
	embed.seq += 1
	slot := int(embed.seq % EMBED_SLOTS)
	s := &hdr.slots[slot]
	sync.atomic_store_explicit(&s.seq, 0, .Release)
	n := int(w) * int(h) * 4
	copy(Embed_SlotPixels(&embed.shm, slot)[:n], pixels[:n])
	s.width = u32(w)
	s.height = u32(h)
	sync.atomic_store_explicit(&s.seq, embed.seq, .Release)
	sync.atomic_store_explicit(&hdr.latest, embed.seq, .Release)
}

// Embed_ReadLatest (the editor): the newest frame, if newer than `after`.
// The pixels stay in the block: check Embed_StillValid after using them.
Embed_ReadLatest :: proc(shm: ^Shared_Memory, after: u64) -> (pixels: [^]u8, w, h: i32, seq: u64, ok: bool) {
	hdr := Embed_Header_Of(shm)
	seq = sync.atomic_load_explicit(&hdr.latest, .Acquire)
	if seq == 0 || seq == after do return
	slot := int(seq % EMBED_SLOTS)
	s := &hdr.slots[slot]
	if sync.atomic_load_explicit(&s.seq, .Acquire) != seq do return
	w, h = i32(s.width), i32(s.height)
	if w <= 0 || h <= 0 || w > EMBED_MAX_W || h > EMBED_MAX_H do return
	return Embed_SlotPixels(shm, slot), w, h, seq, true
}

// Embed_StillValid: the slot of `seq` wasn't rewritten meanwhile.
Embed_StillValid :: proc(shm: ^Shared_Memory, seq: u64) -> bool {
	hdr := Embed_Header_Of(shm)
	return sync.atomic_load_explicit(&hdr.slots[int(seq % EMBED_SLOTS)].seq, .Acquire) == seq
}
