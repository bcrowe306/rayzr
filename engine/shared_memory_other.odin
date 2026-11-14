#+build !darwin
#+build !linux
#+build !windows
package engine

// (shared_memory.odin) None here (the web).
shm_map :: proc(name: string, size: int, create: bool) -> (shm: Shared_Memory, ok: bool) {return}
shm_unmap :: proc(shm: ^Shared_Memory) {}
