#+build darwin, linux
package engine

import "core:c"
import "core:sys/posix"

// Crash reports on macOS / Linux (crash_report.odin): signal handlers on
// their own stack (a stack overflow still reports), backtrace() frames.
// A signal's report also has the faulting instruction (pc, from the signal's
// context: the unwinder can't walk out of a call through a bad pointer) and
// the address it touched; Linux names the executable's own frames from its
// symbol table (crash_report_elf.odin: dladdr only sees exported names).

// Frames: the unwinder (the unwind tables - Odin code has no frame
// pointers, so backtrace() stops at the first frame), names from dladdr.
when ODIN_OS == .Darwin {
	foreign import libc_bt "system:System"
	foreign import libunwind_bt "system:System"
} else {
	foreign import libc_bt "system:c"
	foreign import libunwind_bt "system:gcc_s"
}

@(private = "file")
Dl_info :: struct {
	dli_fname: cstring,
	dli_fbase: rawptr,
	dli_sname: cstring,
	dli_saddr: rawptr,
}

@(default_calling_convention = "c")
foreign libc_bt {
	dladdr :: proc(addr: rawptr, info: ^Dl_info) -> c.int ---
}

@(default_calling_convention = "c")
foreign libunwind_bt {
	_Unwind_Backtrace :: proc(cb: proc "c" (ctx: rawptr, arg: rawptr) -> c.int, arg: rawptr) -> c.int ---
	_Unwind_GetIP :: proc(ctx: rawptr) -> uintptr ---
}

@(private = "file")
CRASH_SIGNALS := [?]posix.Signal{.SIGSEGV, .SIGBUS, .SIGILL, .SIGFPE, .SIGABRT, .SIGTRAP}

@(private = "file")
altStack: [64 * 1024]u8

when ODIN_OS == .Darwin {
	foreign import libc_mach "system:System"

	@(default_calling_convention = "c")
	foreign libc_mach {
		mach_task_self_: u32
		task_set_exception_ports :: proc(task: u32, mask: u32, port: u32, behavior: i32, flavor: i32) -> i32 ---
	}
}

@(private)
crash_install_platform :: proc() {
	when ODIN_OS == .Darwin {
		// A Mach exception port inherited from the parent (a launcher, an
		// IDE, a tool's process tree) can take hardware faults before they
		// become signals - the faulting thread then hangs. Faults go to the
		// signal handlers below instead.
		EXC_MASK_BAD_ACCESS :: 1 << 1
		EXC_MASK_BAD_INSTRUCTION :: 1 << 2
		EXC_MASK_ARITHMETIC :: 1 << 3
		EXC_MASK_BREAKPOINT :: 1 << 6
		EXCEPTION_DEFAULT :: 1
		THREAD_STATE_NONE :: 5 when ODIN_ARCH == .arm64 else 13
		_ = task_set_exception_ports(mach_task_self_, EXC_MASK_BAD_ACCESS | EXC_MASK_BAD_INSTRUCTION | EXC_MASK_ARITHMETIC | EXC_MASK_BREAKPOINT, 0, EXCEPTION_DEFAULT, THREAD_STATE_NONE)
	}
	ss := posix.stack_t{ss_sp = raw_data(altStack[:]), ss_size = len(altStack)}
	_ = posix.sigaltstack(&ss, nil)
	act: posix.sigaction_t
	act.sa_sigaction = crash_signal
	act.sa_flags = {.ONSTACK, .SA_NODEFER, .SIGINFO} // (a fault inside the handler comes back here: crash_stack_failed)
	posix.sigemptyset(&act.sa_mask)
	for s in CRASH_SIGNALS do posix.sigaction(s, &act, nil)
}

// The signal's context: the faulting pc, and the return address (arm64:
// lr; x86-64: the word at sp, used only when pc is outside every module -
// a call through a bad pointer). Offsets into ucontext_t / mcontext.
@(private = "file")
sigCtx: struct {
	have:   bool,
	pc, ret: uintptr,
}

@(private = "file")
crash_signal_context :: proc "contextless" (uc: rawptr) {
	sigCtx = {}
	if uc == nil do return
	at :: proc "contextless" (p: rawptr, off: int) -> uintptr {return (^uintptr)(uintptr(p) + uintptr(off))^}
	when ODIN_OS == .Linux && ODIN_ARCH == .amd64 {
		// (uc_mcontext.gregs at 40; REG_RIP 16, REG_RSP 15)
		sigCtx.pc = at(uc, 40 + 16 * 8)
		sp := at(uc, 40 + 15 * 8)
		if sp != 0 && sp & 7 == 0 do sigCtx.ret = (^uintptr)(sp)^
		sigCtx.have = true
	} else when ODIN_OS == .Linux && ODIN_ARCH == .arm64 {
		// (uc_mcontext at 176: fault_address, regs[31], sp, pc)
		sigCtx.pc = at(uc, 176 + 8 + 32 * 8)
		sigCtx.ret = at(uc, 176 + 8 + 30 * 8)
		sigCtx.have = true
	} else when ODIN_OS == .Darwin {
		mc := rawptr(at(uc, 48)) // (uc_mcontext: a pointer)
		if mc == nil do return
		when ODIN_ARCH == .arm64 {
			// (__es: 16 bytes, then __ss: x[29], fp, lr, sp, pc)
			sigCtx.pc = at(mc, 16 + 32 * 8)
			sigCtx.ret = at(mc, 16 + 30 * 8)
			sigCtx.have = true
		} else when ODIN_ARCH == .amd64 {
			// (__es: 16 bytes, then __ss: rax.. rsp (7) .. rip (16))
			sigCtx.pc = at(mc, 16 + 16 * 8)
			sp := at(mc, 16 + 7 * 8)
			if sp != 0 && sp & 7 == 0 do sigCtx.ret = (^uintptr)(sp)^
			sigCtx.have = true
		}
	}
}

@(private = "file")
crash_signal :: proc "c" (sig: posix.Signal, info: ^posix.siginfo_t, uc: rawptr) {
	crash_signal_context(uc)
	if info != nil && (sig == .SIGSEGV || sig == .SIGBUS) {
		buf: [24]u8
		d := "address:  "
		h := crash_hex(buf[:], uintptr(info.si_addr))
		n := 0
		for s in ([]string{d, h, " (the memory it touched)\n"}) {
			for i in 0 ..< len(s) do if n < len(crash.detail) {crash.detail[n] = s[i]; n += 1}
		}
		crash.detailLen = n
	}
	name := "signal"
	#partial switch sig {
	case .SIGSEGV: name = "SIGSEGV (invalid memory access)"
	case .SIGBUS:  name = "SIGBUS (invalid memory access)"
	case .SIGILL:  name = "SIGILL (illegal instruction: an Odin runtime check - bounds, type assertion - or a trap)"
	case .SIGFPE:  name = "SIGFPE (arithmetic error: division by zero?)"
	case .SIGABRT: name = "SIGABRT (aborted)"
	case .SIGTRAP: name = "SIGTRAP (trap: an Odin runtime check - bounds, type assertion - or a panic)"
	}
	if !crash_stack_failed() do crash_write_report(name)
	// The default action now, unblocked: the OS reports / dumps as usual.
	dfl: posix.sigaction_t
	dfl.sa_handler = auto_cast posix.SIG_DFL
	posix.sigemptyset(&dfl.sa_mask)
	posix.sigaction(sig, &dfl, nil)
	set: posix.sigset_t
	posix.sigemptyset(&set)
	posix.sigaddset(&set, sig)
	posix.pthread_sigmask(.UNBLOCK, &set, nil)
	posix.raise(sig)
	posix._exit(128 + c.int(sig)) // (if it's still running)
}

@(private)
crash_set_path_platform :: proc() {}

@(private)
crash_open_platform :: proc "contextless" () -> Crash_File {
	if crash.pathLen == 0 do return CRASH_STDERR
	fd := posix.open(cstring(raw_data(crash.path[:])), {.WRONLY, .CREAT, .TRUNC}, {.IRUSR, .IWUSR, .IRGRP, .IROTH})
	return CRASH_STDERR if fd < 0 else Crash_File(uintptr(fd))
}

@(private)
crash_fd :: proc "contextless" (f: Crash_File) -> posix.FD {
	return posix.STDERR_FILENO if f == CRASH_STDERR else posix.FD(f)
}

@(private)
crash_write_platform :: proc "contextless" (f: Crash_File, s: string) {
	if len(s) == 0 do return
	_ = posix.write(crash_fd(f), raw_data(s), uint(len(s)))
}

@(private)
crash_close_platform :: proc "contextless" (f: Crash_File) {
	if f != CRASH_STDERR do posix.close(crash_fd(f))
}

CRASH_FRAMES :: 64

@(private = "file")
Stack_Walk :: struct {
	ips: [CRASH_FRAMES]uintptr,
	n:   int,
}

@(private = "file")
walkBuf: Stack_Walk

@(private = "file")
elfSyms: [CRASH_FRAMES + 2]Crash_Elf_Sym

@(private)
crash_stack_platform :: proc "contextless" (f: Crash_File) {
	// The frames first (the unwinder), then their names, then the lines.
	walk := &walkBuf
	walk.n = 0
	_Unwind_Backtrace(proc "c" (ctx: rawptr, arg: rawptr) -> c.int {
		walk := (^Stack_Walk)(arg)
		ip := _Unwind_GetIP(ctx)
		if ip == 0 || walk.n >= CRASH_FRAMES do return 5 // (_URC_END_OF_STACK)
		walk.ips[walk.n] = ip
		walk.n += 1
		return 0
	}, walk)
	// [0]: the signal's pc, [1]: its return address, then the frames.
	addrs: [CRASH_FRAMES + 2]uintptr
	if sigCtx.have do addrs[0], addrs[1] = sigCtx.pc, sigCtx.ret
	for i in 0 ..< walk.n do addrs[2 + i] = walk.ips[i]
	all := addrs[:2 + walk.n]
	when ODIN_OS == .Linux {
		// The executable's own procedures: from its symbol table.
		self: Dl_info
		if dladdr(rawptr(crash_stack_platform), &self) != 0 {
			fd := posix.open("/proc/self/exe", {})
			if fd >= 0 {
				_ = crash_elf_symbols(fd, uintptr(self.dli_fbase), all, elfSyms[:])
				posix.close(fd)
			}
			for &s, i in elfSyms[:len(all)] {
				// (Only addresses in the executable: another module's offsets differ.)
				mod: Dl_info
				if s.found && (dladdr(rawptr(all[i]), &mod) == 0 || mod.dli_fbase != self.dli_fbase) do s.found = false
			}
		}
	}
	if sigCtx.have {
		crash_frame_line(f, "pc", sigCtx.pc, &elfSyms[0])
		// (The return address: arm64's lr always; x86-64's top of stack
		// only when pc is outside every module - a jump through a bad pointer.)
		info: Dl_info
		lost := dladdr(rawptr(sigCtx.pc), &info) == 0
		if sigCtx.ret != 0 && (ODIN_ARCH == .arm64 || lost) do crash_frame_line(f, "lr" when ODIN_ARCH == .arm64 else "ret", sigCtx.ret, &elfSyms[1])
	}
	skipping := true
	n := 0
	for i in 0 ..< walk.n {
		ip := walk.ips[i]
		// (The report's own frames at the top: the stack starts at the crash.)
		if skipping {
			name := crash_frame_name(ip, &elfSyms[2 + i])
			if name != "" && crash_own_frame(name) do continue
			skipping = false
		}
		buf: [24]u8
		crash_frame_line(f, crash_itoa(buf[:], i64(n)), ip, &elfSyms[2 + i])
		n += 1
	}
}

// crash_module_base: where the module holding p is loaded (0: unknown).
@(private)
crash_module_base :: proc "contextless" (p: rawptr) -> uintptr {
	info: Dl_info
	return uintptr(info.dli_fbase) if dladdr(p, &info) != 0 else 0
}

// crash_frame_name: a frame's symbol name ("": unknown).
@(private = "file")
crash_frame_name :: proc "contextless" (ip: uintptr, elf: ^Crash_Elf_Sym) -> string {
	info: Dl_info
	if dladdr(rawptr(ip), &info) != 0 && info.dli_sname != nil do return string(info.dli_sname)
	if elf.found do return string(elf.name[:elf.nameLen])
	return ""
}

// crash_frame_line writes "  <label>  0x...  name + off  (module+0x...)".
@(private = "file")
crash_frame_line :: proc "contextless" (w: Crash_File, label: string, ip: uintptr, elf: ^Crash_Elf_Sym) {
	buf: [24]u8
	crash_write_platform(w, "  ")
	crash_write_platform(w, label)
	crash_write_platform(w, "  ")
	crash_write_platform(w, crash_hex(buf[:], ip))
	info: Dl_info
	named := dladdr(rawptr(ip), &info) != 0
	if named && info.dli_sname != nil && !elf.found {
		crash_write_platform(w, "  ")
		crash_write_platform(w, string(info.dli_sname))
		crash_write_platform(w, " + ")
		crash_write_platform(w, crash_itoa(buf[:], i64(ip - uintptr(info.dli_saddr))))
	} else if elf.found {
		// (A closer, non-exported symbol than dladdr's - or the only name.)
		crash_write_platform(w, "  ")
		crash_write_platform(w, string(elf.name[:elf.nameLen]))
		crash_write_platform(w, " + ")
		crash_write_platform(w, crash_itoa(buf[:], i64(elf.offset)))
	}
	if named && info.dli_fname != nil {
		// (The module and the offset in it: addr2line / atos with the debug build.)
		name := string(info.dli_fname)
		for i := len(name) - 1; i >= 0; i -= 1 do if name[i] == '/' {
			name = name[i + 1:]
			break
		}
		crash_write_platform(w, "  (")
		crash_write_platform(w, name)
		crash_write_platform(w, "+")
		crash_write_platform(w, crash_hex(buf[:], ip - uintptr(info.dli_fbase)))
		crash_write_platform(w, ")")
	} else if !named {
		crash_write_platform(w, "  (in no module)")
	}
	crash_write_platform(w, "\n")
}

@(private)
crash_unix_time_platform :: proc "contextless" () -> i64 {
	return i64(posix.time(nil))
}

@(private)
crash_pid_platform :: proc() -> int {
	return int(posix.getpid())
}

@(private)
crash_abort_platform :: proc() {
	posix.abort()
}
