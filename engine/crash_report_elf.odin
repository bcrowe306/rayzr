#+build darwin, linux
package engine

import "core:c"
import "core:sys/posix"

// Crash report frame names from an ELF file's symbol table (#392): Linux's
// dladdr only sees exported (dynamic) symbols, and the runner's / editor's
// own procedures aren't exported, so their frames had only an offset
// (runner+0xdab25). The executable's .symtab (kept: the builds aren't
// stripped) names them. From a signal handler: no allocation - pread into
// static buffers, one pass over the symbols for every frame. (Built on macOS
// too: a test reads an Android .so with it.)

CRASH_SYM_LEN :: 160

Crash_Elf_Sym :: struct {
	found:   bool,
	value:   u64, // the symbol's start (file address)
	offset:  u64, // the address's offset into it
	nameOff: u32, // in the string table
	name:    [CRASH_SYM_LEN]u8,
	nameLen: int,
}

@(private = "file")
elfBuf: [16 * 1024]u8

@(private = "file")
elf_u16 :: proc "contextless" (b: []u8, at: int) -> u64 {return u64(b[at]) | u64(b[at + 1]) << 8}
@(private = "file")
elf_u32 :: proc "contextless" (b: []u8, at: int) -> u64 {return elf_u16(b, at) | elf_u16(b, at + 2) << 16}
@(private = "file")
elf_u64 :: proc "contextless" (b: []u8, at: int) -> u64 {return elf_u32(b, at) | elf_u32(b, at + 4) << 32}

@(private = "file")
elf_read :: proc "contextless" (fd: posix.FD, buf: []u8, off: u64) -> bool {
	got := 0
	for got < len(buf) {
		rem: int = len(buf) - got
		n := posix.pread(fd, raw_data(buf[got:]), c.size_t(rem), posix.off_t(off + u64(got)))
		if n <= 0 do return false
		got += int(n)
	}
	return true
}

// crash_elf_symbols names `addrs` (run-time addresses in the module loaded
// at `base`) from the ELF file `fd`: out[i] is the function symbol holding
// addrs[i] (found = false: none). false: not a 64-bit little-endian ELF, or
// it has no symbol table (stripped).
crash_elf_symbols :: proc "contextless" (fd: posix.FD, base: uintptr, addrs: []uintptr, out: []Crash_Elf_Sym) -> bool {
	n := min(len(addrs), len(out))
	for i in 0 ..< n do out[i] = {}
	hdr := elfBuf[:64]
	if !elf_read(fd, hdr, 0) do return false
	if hdr[0] != 0x7f || hdr[1] != 'E' || hdr[2] != 'L' || hdr[3] != 'F' || hdr[4] != 2 || hdr[5] != 1 do return false
	etype := elf_u16(hdr, 16)
	shoff := elf_u64(hdr, 40)
	shentsize := elf_u16(hdr, 58)
	shnum := elf_u16(hdr, 60)
	if shentsize < 64 || shnum == 0 do return false
	// The symbol table and its strings.
	symOff, symSize, symEnt, strOff, strSize: u64
	link: u64 = ~u64(0)
	for s in 0 ..< shnum {
		sh := elfBuf[:64]
		if !elf_read(fd, sh, shoff + s * shentsize) do return false
		if elf_u32(sh, 4) == 2 { // SHT_SYMTAB
			symOff, symSize, symEnt, link = elf_u64(sh, 24), elf_u64(sh, 32), elf_u64(sh, 56), elf_u32(sh, 40)
			break
		}
	}
	if symSize == 0 || symEnt < 24 || link >= shnum do return false
	{
		sh := elfBuf[:64]
		if !elf_read(fd, sh, shoff + link * shentsize) do return false
		strOff, strSize = elf_u64(sh, 24), elf_u64(sh, 32)
	}
	// (A position-independent file's symbols are relative to its load base;
	// an ET_EXEC one's are the addresses.)
	bias := u64(base) if etype == 3 else 0
	// One pass: the closest function symbol at or below each address that
	// holds it (its size; a size-less one only when nothing else does).
	count := symSize / symEnt
	per := u64(len(elfBuf)) / symEnt
	for first: u64 = 0; first < count; first += per {
		k := min(per, count - first)
		chunk := elfBuf[:k * symEnt]
		if !elf_read(fd, chunk, symOff + first * symEnt) do return false
		for j in 0 ..< k {
			at := int(j * symEnt)
			info := chunk[at + 4]
			if info & 0xf != 2 do continue // STT_FUNC
			value := elf_u64(chunk, at + 8)
			size := elf_u64(chunk, at + 16)
			if value == 0 do continue
			for i in 0 ..< n {
				if u64(addrs[i]) < bias do continue
				a := u64(addrs[i]) - bias
				if a < value || (size > 0 && a >= value + size) do continue
				if size == 0 && (out[i].found || a - value >= 64 * 1024) do continue // (a size-less one: near it only)
				if out[i].found && out[i].value > value do continue
				out[i].found, out[i].value, out[i].offset, out[i].nameOff = true, value, a - value, u32(elf_u32(chunk, at))
			}
		}
	}
	// The names.
	for i in 0 ..< n do if out[i].found {
		o := u64(out[i].nameOff)
		if o >= strSize {
			out[i].found = false
			continue
		}
		want := int(min(u64(CRASH_SYM_LEN), strSize - o))
		got := posix.pread(fd, raw_data(out[i].name[:]), c.size_t(want), posix.off_t(strOff + o))
		l := 0
		for l < int(got) && out[i].name[l] != 0 do l += 1
		out[i].nameLen = l
		if l == 0 do out[i].found = false
	}
	return true
}
