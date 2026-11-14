#+build windows
package engine

import "core:strings"
import win "core:sys/windows"

// (shared_memory.odin) A pagefile-backed named file mapping.
shm_map :: proc(name: string, size: int, create: bool) -> (shm: Shared_Memory, ok: bool) {
	wname := win.utf8_to_wstring(name, context.temp_allocator)
	h: win.HANDLE
	if create {
		h = win.CreateFileMappingW(win.INVALID_HANDLE_VALUE, nil, win.PAGE_READWRITE, win.DWORD(u64(size) >> 32), win.DWORD(u64(size) & 0xffff_ffff), wname)
	} else {
		h = win.OpenFileMappingW(win.FILE_MAP_ALL_ACCESS, false, wname)
	}
	if h == nil do return
	p := win.MapViewOfFile(h, win.FILE_MAP_ALL_ACCESS, 0, 0, uint(size))
	if p == nil {
		win.CloseHandle(h)
		return
	}
	return Shared_Memory{data = cast([^]u8)p, size = size, name = strings.clone(name), owner = create, handle = rawptr(h)}, true
}

shm_unmap :: proc(shm: ^Shared_Memory) {
	if shm.data != nil do win.UnmapViewOfFile(shm.data)
	if shm.handle != nil do win.CloseHandle(win.HANDLE(shm.handle))
}
