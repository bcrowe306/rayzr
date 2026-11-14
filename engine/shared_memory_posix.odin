#+build darwin, linux
package engine

import "core:strings"
import "core:sys/posix"

// (shared_memory.odin) POSIX shared memory: shm_open + mmap.
shm_map :: proc(name: string, size: int, create: bool) -> (shm: Shared_Memory, ok: bool) {
	when !SHM_SUPPORTED {
		return
	} else {
		cname := strings.clone_to_cstring(name, context.temp_allocator)
		fd: posix.FD
		when ODIN_OS == .Darwin {
			if create {
				posix.shm_unlink(cname) // (a stale one from a crashed editor)
				fd = posix.shm_open(cname, {.CREAT, .EXCL, .RDWR}, posix.mode_t{.IRUSR, .IWUSR})
			} else do fd = posix.shm_open(cname, {.RDWR})
		} else {
			if create {
				posix.shm_unlink(cname)
				fd = posix.shm_open(cname, {.CREAT, .EXCL, .RDWR}, posix.mode_t{.IRUSR, .IWUSR})
			} else do fd = posix.shm_open(cname, {.RDWR}, posix.mode_t{})
		}
		if fd < 0 do return
		defer posix.close(fd)
		if create && posix.ftruncate(fd, posix.off_t(size)) != .OK {
			posix.shm_unlink(cname)
			return
		}
		p := posix.mmap(nil, uint(size), {.READ, .WRITE}, {.SHARED}, fd, 0)
		if p == posix.MAP_FAILED {
			if create do posix.shm_unlink(cname)
			return
		}
		return Shared_Memory{data = cast([^]u8)p, size = size, name = strings.clone(name), owner = create}, true
	}
}

shm_unmap :: proc(shm: ^Shared_Memory) {
	when SHM_SUPPORTED {
		if shm.data != nil do posix.munmap(shm.data, uint(shm.size))
		if shm.owner && shm.name != "" do posix.shm_unlink(strings.clone_to_cstring(shm.name, context.temp_allocator))
	}
}
