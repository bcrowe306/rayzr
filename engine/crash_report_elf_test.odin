#+build linux
package engine

import "core:strings"
import "core:sys/posix"
import "core:testing"

// #392: Linux names the executable's own (not exported) procedures from its
// symbol table - this test binary's, here.
@(test)
test_crash_elf_symbols :: proc(t: ^testing.T) {
	fd := posix.open("/proc/self/exe", {})
	testing.expect(t, fd >= 0, "the executable opens")
	if fd < 0 do return
	defer posix.close(fd)
	// (The load base: 0 for a non-PIE executable, whose symbols are addresses.)
	base := crash_module_base(rawptr(test_crash_elf_symbols))
	here := uintptr(rawptr(test_crash_elf_symbols))
	addrs := []uintptr{here, here + 4, 3}
	out: [3]Crash_Elf_Sym
	testing.expect(t, crash_elf_symbols(fd, base, addrs, out[:]), "a symbol table")
	testing.expectf(t, out[0].found && strings.contains(string(out[0].name[:out[0].nameLen]), "test_crash_elf_symbols"), "named: %q", string(out[0].name[:out[0].nameLen]))
	testing.expect_value(t, out[0].offset, 0)
	testing.expect(t, out[1].found && out[1].offset == 4, "inside the procedure: its offset")
	testing.expect(t, !out[2].found, "an address in no procedure")
}
