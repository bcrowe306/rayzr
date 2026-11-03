#+build js
package engine

import "base:runtime"
import "core:c"
import "core:mem"
import "core:strings"

// The web's allocators (see platform.odin): emscripten's malloc. Odin's
// own wasm allocator would grow memory behind emscripten's back (its views
// of the heap would go stale) and runtime.heap_allocator doesn't exist on
// js.

@(private = "file")
@(default_calling_convention = "c")
foreign {
	calloc :: proc(n, size: c.size_t) -> rawptr ---
	free :: proc(p: rawptr) ---
	realloc :: proc(p: rawptr, size: c.size_t) -> rawptr ---
	aligned_alloc :: proc(alignment, size: c.size_t) -> rawptr ---
}

// Web_AllocatorProc: malloc's blocks are 8-byte aligned on wasm32; stricter
// alignments use aligned_alloc (their resizes copy).
Web_AllocatorProc :: proc(data: rawptr, mode: runtime.Allocator_Mode, size, alignment: int, old: rawptr, oldSize: int, loc := #caller_location) -> ([]byte, runtime.Allocator_Error) {
	switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		p := calloc(1, c.size_t(max(size, 1))) if alignment <= 8 else aligned_alloc(c.size_t(alignment), c.size_t(mem.align_forward_int(max(size, 1), alignment)))
		if p == nil do return nil, .Out_Of_Memory
		if alignment > 8 && mode == .Alloc do mem.zero(p, size)
		return mem.byte_slice(p, size), nil
	case .Free:
		free(old)
		return nil, nil
	case .Resize, .Resize_Non_Zeroed:
		if old == nil do return Web_AllocatorProc(data, .Alloc, size, alignment, nil, 0, loc)
		if alignment <= 8 {
			p := realloc(old, c.size_t(max(size, 1)))
			if p == nil do return nil, .Out_Of_Memory
			if size > oldSize && mode == .Resize do mem.zero(rawptr(uintptr(p) + uintptr(oldSize)), size - oldSize)
			return mem.byte_slice(p, size), nil
		}
		n, err := Web_AllocatorProc(data, .Alloc, size, alignment, nil, 0, loc)
		if err != nil do return nil, err
		mem.copy(raw_data(n), old, min(size, oldSize))
		free(old)
		return n, nil
	case .Free_All:
		return nil, .Mode_Not_Implemented
	case .Query_Features:
		set := (^runtime.Allocator_Mode_Set)(old)
		if set != nil do set^ = {.Alloc, .Alloc_Non_Zeroed, .Free, .Resize, .Resize_Non_Zeroed, .Query_Features}
		return nil, nil
	case .Query_Info:
		return nil, .Mode_Not_Implemented
	}
	return nil, nil
}

Engine_HeapAllocator :: proc() -> runtime.Allocator {return {procedure = Web_AllocatorProc}}

// Engine_CoreCount: the processor's cores (1 on the web: no worker threads).
Engine_CoreCount :: proc() -> int {return 1}

// Engine_TempDir: the virtual file system's /tmp (platform.odin on desktop).
Engine_TempDir :: proc() -> string {return "/tmp"}

@(private = "file")
webTemp: runtime.Arena

@(private = "file")
webTempReady: bool

Engine_DefaultContext :: proc "contextless" () -> runtime.Context {
	ctx := runtime.default_context()
	ctx.allocator = {procedure = Web_AllocatorProc}
	context = ctx
	if !webTempReady {
		webTempReady = true
		_ = runtime.arena_init(&webTemp, 4 * mem.Megabyte, ctx.allocator)
	}
	ctx.temp_allocator = runtime.arena_allocator(&webTemp)
	return ctx
}

// Shader_Port: GLSL 330 for WebGL 2 (GLSL ES 300) - the same language
// with a different version line and precisions.
Shader_Port :: proc(src: cstring) -> cstring {
	text := string(src)
	if !strings.has_prefix(text, "#version 330") do return src
	rest := text[len("#version 330"):]
	if i := strings.index_byte(rest, '\n'); i >= 0 do rest = rest[i + 1:] // (drops "core" etc.)
	return strings.clone_to_cstring(strings.concatenate({"#version 300 es\nprecision highp float;\nprecision highp int;\n", rest}, context.temp_allocator), context.temp_allocator)
}

// Window_CanOpenGL (gl_window_check.odin): the page's WebGL canvas - always.
Window_CanOpenGL :: proc(msaa := false) -> (ok: bool, reason: string) {return true, ""}
