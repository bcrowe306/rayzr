package engine

import "core:fmt"

// ============================================================================
// Shared memory: a named block two processes map (the Game view's frames:
// embed.odin). The editor creates it, the game opens it by name. POSIX
// shm_open on macOS / Linux, a pagefile-backed file mapping on Windows;
// none on the web or Android (Shm_Supported false).
// ============================================================================

Shared_Memory :: struct {
	data:   [^]u8,
	size:   int,
	name:   string, // (heap)
	owner:  bool,   // created it: Shm_Close removes the name
	handle: rawptr, // (Windows: the mapping)
}

SHM_SUPPORTED :: (ODIN_OS == .Darwin || ODIN_OS == .Linux || ODIN_OS == .Windows) && ODIN_PLATFORM_SUBTARGET != .Android
// Shm_Create makes a new block of `size` bytes (zeroed) under `name`.
Shm_Create :: proc(name: string, size: int) -> (Shared_Memory, bool) {return shm_map(name, size, true)}

// Shm_Open maps a block another process made.
Shm_Open :: proc(name: string, size: int) -> (Shared_Memory, bool) {return shm_map(name, size, false)}

Shm_Close :: proc(shm: ^Shared_Memory) {
	shm_unmap(shm)
	delete(shm.name)
	shm^ = {}
}

// Shm_Name: a name for a new block, unique to this process ("/rzv<pid>_<n>";
// macOS allows 31 characters; Windows "Local\\rzv...").
Shm_Name :: proc(pid: int, n: int, allocator := context.allocator) -> string {
	when ODIN_OS == .Windows {
		return fmt.aprintf("Local\\rzv%d_%d", pid, n, allocator = allocator)
	} else {
		return fmt.aprintf("/rzv%d_%d", pid, n, allocator = allocator)
	}
}
