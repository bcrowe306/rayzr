package engine

import rl "vendor:raylib"

// ============================================================================
// (embed.odin) Reading the game's frames back for the Game view without
// stalling: each frame is read into a pixel buffer object (asynchronous),
// and the one read a frame earlier - done by now - is copied to the shared
// block. One frame of delay, no wait on the GPU. Without the GL calls (an
// old driver) a plain glReadPixels.
//
// The GL functions come from raylib's own GLFW (glfwGetProcAddress), the
// library already linked.
// ============================================================================

when ODIN_OS == .Darwin {
	foreign import rl_glfw "vendor:raylib/macos/libraylib.a"
} else when ODIN_OS == .Linux && ODIN_PLATFORM_SUBTARGET != .Android {
	foreign import rl_glfw "vendor:raylib/linux/libraylib.a"
} else when ODIN_OS == .Windows {
	foreign import rl_glfw "vendor:raylib/windows/raylib.lib"
}

when SHM_SUPPORTED {
	@(default_calling_convention = "c")
	foreign rl_glfw {
		glfwGetProcAddress :: proc(name: cstring) -> rawptr ---
	}
}

@(private = "file")
GL_PIXEL_PACK_BUFFER :: 0x88EB
@(private = "file")
GL_STREAM_READ :: 0x88E1
@(private = "file")
GL_MAP_READ_BIT :: 0x0001
@(private = "file")
GL_RGBA :: 0x1908
@(private = "file")
GL_UNSIGNED_BYTE :: 0x1401
@(private = "file")
GL_PACK_ALIGNMENT :: 0x0D05
@(private = "file")
GL_SYNC_GPU_COMMANDS_COMPLETE :: 0x9117
@(private = "file")
GL_SYNC_FLUSH_COMMANDS_BIT :: 0x1
@(private = "file")
GL_WAIT_FAILED :: 0x911D
@(private = "file")
GL_TIMEOUT_EXPIRED :: 0x911B

@(private = "file")
Embed_GL :: struct {
	loaded:         bool,
	pbo:            bool, // the buffer-object calls are there
	ReadPixels:     proc "c" (x, y, w, h: i32, format, type: u32, data: rawptr),
	PixelStorei:    proc "c" (pname: u32, param: i32),
	GenBuffers:     proc "c" (n: i32, buffers: [^]u32),
	DeleteBuffers:  proc "c" (n: i32, buffers: [^]u32),
	BindBuffer:     proc "c" (target, buffer: u32),
	BufferData:     proc "c" (target: u32, size: int, data: rawptr, usage: u32),
	MapBufferRange: proc "c" (target: u32, offset, length: int, access: u32) -> rawptr,
	UnmapBuffer:    proc "c" (target: u32) -> u8,
	FenceSync:      proc "c" (condition, flags: u32) -> rawptr,
	ClientWaitSync: proc "c" (sync: rawptr, flags: u32, timeout: u64) -> u32,
	DeleteSync:     proc "c" (sync: rawptr),
}

@(private = "file")
gl: Embed_GL

@(private = "file")
embed_gl_load :: proc() -> bool {
	if gl.loaded do return gl.ReadPixels != nil
	gl.loaded = true
	when SHM_SUPPORTED {
		get :: proc(name: cstring) -> rawptr {return glfwGetProcAddress(name)}
		gl.ReadPixels = auto_cast get("glReadPixels")
		gl.PixelStorei = auto_cast get("glPixelStorei")
		gl.GenBuffers = auto_cast get("glGenBuffers")
		gl.DeleteBuffers = auto_cast get("glDeleteBuffers")
		gl.BindBuffer = auto_cast get("glBindBuffer")
		gl.BufferData = auto_cast get("glBufferData")
		gl.MapBufferRange = auto_cast get("glMapBufferRange")
		gl.UnmapBuffer = auto_cast get("glUnmapBuffer")
		gl.FenceSync = auto_cast get("glFenceSync")
		gl.ClientWaitSync = auto_cast get("glClientWaitSync")
		gl.DeleteSync = auto_cast get("glDeleteSync")
		gl.pbo = gl.GenBuffers != nil && gl.BindBuffer != nil && gl.BufferData != nil && gl.MapBufferRange != nil && gl.UnmapBuffer != nil && gl.FenceSync != nil && gl.ClientWaitSync != nil && gl.DeleteSync != nil
	}
	return gl.ReadPixels != nil
}

// embed_read_frame: this frame (w x h pixels) on its way to the editor.
embed_read_frame :: proc(w, h: i32) {
	if !embed_gl_load() do return
	gl.PixelStorei(GL_PACK_ALIGNMENT, 1)
	if !gl.pbo {
		buf := make([]u8, int(w) * int(h) * 4, context.temp_allocator)
		gl.ReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, raw_data(buf))
		embed_store(raw_data(buf), w, h)
		return
	}
	if embed.pbo[0] == 0 do gl.GenBuffers(2, &embed.pbo[0])
	cur := embed.pboFrame % 2
	prev := 1 - cur
	// This frame: read into its buffer (the GPU does it later).
	gl.BindBuffer(GL_PIXEL_PACK_BUFFER, embed.pbo[cur])
	if embed.pboSize[cur] != {w, h} {
		gl.BufferData(GL_PIXEL_PACK_BUFFER, int(w) * int(h) * 4, nil, GL_STREAM_READ)
		embed.pboSize[cur] = {w, h}
	}
	gl.ReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, nil)
	if embed.pboFence[cur] != nil do gl.DeleteSync(embed.pboFence[cur])
	embed.pboFence[cur] = gl.FenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0)
	// The frame before: done by now (waits at most 50 ms if the GPU lags).
	if f := embed.pboFence[prev]; f != nil {
		r := gl.ClientWaitSync(f, GL_SYNC_FLUSH_COMMANDS_BIT, 50_000_000)
		gl.DeleteSync(f)
		embed.pboFence[prev] = nil
		if r != GL_WAIT_FAILED && r != GL_TIMEOUT_EXPIRED {
			sz := embed.pboSize[prev]
			gl.BindBuffer(GL_PIXEL_PACK_BUFFER, embed.pbo[prev])
			if p := gl.MapBufferRange(GL_PIXEL_PACK_BUFFER, 0, int(sz.x) * int(sz.y) * 4, GL_MAP_READ_BIT); p != nil {
				embed_store(cast([^]u8)p, sz.x, sz.y)
				gl.UnmapBuffer(GL_PIXEL_PACK_BUFFER)
			}
		}
	}
	gl.BindBuffer(GL_PIXEL_PACK_BUFFER, 0)
	embed.pboFrame += 1
}

// embed_gl_release frees the pixel buffers (the window still open).
embed_gl_release :: proc() {
	if !gl.pbo || !rl.IsWindowReady() do return
	for &f in embed.pboFence do if f != nil {
		gl.DeleteSync(f)
		f = nil
	}
	if embed.pbo[0] != 0 do gl.DeleteBuffers(2, &embed.pbo[0])
	embed.pbo = {}
}
