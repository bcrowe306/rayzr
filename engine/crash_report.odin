package engine

import "base:intrinsics"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:log"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"
import os "osx"
import lua "lua54"

// ============================================================================
// Crash reports (TODO E.1). The editor and the runner install a handler at
// startup (Crash_Install); a crash - an Odin panic / failed assertion /
// runtime check, a signal (SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT,
// SIGTRAP) or a Windows exception - writes `crash-<time>-<pid>.txt` to the
// crash folder (Crash_SetDir):
//
//   Rayzr Editor crash report
//   version:  0.1.0-dev.240
//   platform: macOS arm64
//   time:     1793000000 (unix)
//   reason:   SIGSEGV (invalid memory access)
//   stack:    ...frames (symbol names; Windows: exe+offset)
//   recent:   the last log lines / actions (Crash_Note)
//
// The report is written from preformatted static memory (no allocation in a
// signal handler). The editor offers pending reports on its next start (a
// prefilled GitHub issue, editor/crash_reports.odin); games read theirs
// with the Crash Lua module (Crash.pending / dismiss / note).
// Platform parts: crash_report_posix.odin, _windows.odin, _js.odin (none).
// ============================================================================

CRASH_NOTES :: 48     // recent lines kept
CRASH_NOTE_LEN :: 240 // bytes per line (longer: cut)
CRASH_KEEP :: 20      // reports kept in the folder (oldest removed)

// Where a report is written (a platform file handle; CRASH_STDERR: stderr).
Crash_File :: distinct uintptr
CRASH_STDERR :: Crash_File(~uintptr(0))

@(private)
crash: struct {
	installed: bool,
	written:   bool, // a report was written (a panic, then its trap: one report)
	file:      Crash_File, // the report being written
	inStack:   bool, // walking the stack (a fault there: crash_stack_failed)
	header:    [512]u8,
	headerLen: int,
	path:      [1024]u8, // the report file (NUL-terminated); "" = stderr only
	pathLen:   int,
	notes:     [CRASH_NOTES][CRASH_NOTE_LEN]u8,
	noteLens:  [CRASH_NOTES]int,
	noteNext:  int,
	dir:       string,
}

// Crash_Install starts catching crashes for `app` ("Rayzr Editor", the game's
// name); reports go to `dir` ("": stderr until Crash_SetDir). Also set
// context.assertion_failure_proc = Crash_AssertionFailure in main.
Crash_Install :: proc(app: string, dir := "") {
	h := fmt.bprintf(crash.header[:], "%s crash report\nversion:  %s\nplatform: %s %s\n", app, RAYZR_RELEASE, crash_os_name(), ODIN_ARCH_STRING)
	crash.headerLen = len(h)
	if dir != "" do Crash_SetDir(dir)
	if !crash.installed {
		crash.installed = true
		crash_install_platform()
	}
}

// Crash_SetDir: where reports go (created); the report's file name is fixed
// now (crash-<start time>-<pid>.txt: one crash per process).
Crash_SetDir :: proc(dir: string) {
	_ = os.make_directory_all(dir)
	delete(crash.dir, Engine_HeapAllocator())
	crash.dir = strings.clone(dir, Engine_HeapAllocator())
	name := fmt.tprintf("crash-%d-%d.txt", time.to_unix_seconds(time.now()), crash_pid_platform())
	p, _ := filepath.join({dir, name}, context.temp_allocator)
	n := min(len(p), len(crash.path) - 1)
	copy(crash.path[:], p[:n])
	crash.path[n] = 0
	crash.pathLen = n
	crash_set_path_platform()
	crash_prune(dir)
}

// Crash_Dir: the crash folder ("" if not set).
Crash_Dir :: proc() -> string {return crash.dir}

// Crash_Note keeps a line for the next report (the last CRASH_NOTES).
Crash_Note :: proc "contextless" (text: string) {
	i := crash.noteNext % CRASH_NOTES
	n := min(len(text), CRASH_NOTE_LEN)
	for k in 0 ..< n {
		b := text[k]
		crash.notes[i][k] = ' ' if b == '\n' || b == '\r' else b
	}
	crash.noteLens[i] = n
	crash.noteNext += 1
}

// Crash_Notes: the kept lines, oldest first (temp).
Crash_Notes :: proc(allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, allocator)
	count := min(crash.noteNext, CRASH_NOTES)
	for k in 0 ..< count {
		i := (crash.noteNext - count + k) % CRASH_NOTES
		append(&out, strings.clone(string(crash.notes[i][:crash.noteLens[i]]), allocator))
	}
	return out[:]
}

// Crash_AssertionFailure: context.assertion_failure_proc - panic(),
// assert() and failed runtime checks write a report, then fail as usual.
Crash_AssertionFailure :: proc(prefix, message: string, loc := #caller_location) -> ! {
	reason: [1024]u8
	r := fmt.bprintf(reason[:], "%s: %s (%s(%d:%d) %s)", prefix, message, loc.file_path, loc.line, loc.column, loc.procedure) if message != "" else fmt.bprintf(reason[:], "%s (%s(%d:%d) %s)", prefix, loc.file_path, loc.line, loc.column, loc.procedure)
	crash_write_report(r)
	runtime.default_assertion_failure_proc(prefix, message, loc)
}

// Crash_Logger wraps a logger: every line is also kept (Crash_Note).
Crash_Logger :: proc(next: log.Logger) -> log.Logger {
	@(static) inner: log.Logger
	inner = next
	return log.Logger{
		procedure = proc(data: rawptr, level: log.Level, text: string, options: log.Options, location := #caller_location) {
			Crash_Note(fmt.tprintf("[%v] %s", level, text))
			if inner.procedure != nil do inner.procedure(inner.data, level, text, options, location)
		},
		lowest_level = next.lowest_level,
		options = next.options,
	}
}

// Crash_TestCrash crashes on purpose (--crash-test panic | segv | abort):
// tests of the whole path.
Crash_TestCrash :: proc(kind: string) {
	Crash_Note(fmt.tprintf("crash test: %s", kind))
	switch kind {
	case "panic":
		panic("crash test")
	case "segv":
		// (A volatile store through a runtime address: not optimised away.)
		intrinsics.volatile_store((^int)(crash_bad_address), 1)
	case "abort":
		crash_abort_platform()
	}
}

@(private = "file")
crash_bad_address: uintptr = 8

// --- the report -------------------------------------------------------------

// crash_write_report writes the report for `reason` (no allocation: also
// from a signal handler). Once per process.
@(private)
crash_write_report :: proc "contextless" (reason: string) {
	if crash.written do return
	crash.written = true
	f := crash_open_platform()
	crash.file = f
	w :: proc "contextless" (f: Crash_File, s: string) {crash_write_platform(f, s)}
	w(f, string(crash.header[:crash.headerLen]))
	num: [24]u8
	w(f, "time:     ")
	w(f, crash_itoa(num[:], crash_unix_time_platform()))
	w(f, " (unix)\nreason:   ")
	w(f, reason)
	w(f, "\n\nstack:\n")
	crash.inStack = true
	crash_stack_platform(f)
	crash.inStack = false
	crash_write_tail(f)
}

// crash_stack_failed: a fault while walking the stack (a frame the
// unwinder can't read): the rest of the report is still written.
@(private)
crash_stack_failed :: proc "contextless" () -> bool {
	if !crash.inStack do return false
	crash.inStack = false
	crash_write_platform(crash.file, "  (the stack walk stopped here)\n")
	crash_write_tail(crash.file)
	return true
}

@(private = "file")
crash_write_tail :: proc "contextless" (f: Crash_File) {
	w :: proc "contextless" (f: Crash_File, s: string) {crash_write_platform(f, s)}
	w(f, "\nrecent:\n")
	count := min(crash.noteNext, CRASH_NOTES)
	for k in 0 ..< count {
		i := (crash.noteNext - count + k) % CRASH_NOTES
		w(f, "  ")
		w(f, string(crash.notes[i][:crash.noteLens[i]]))
		w(f, "\n")
	}
	crash_close_platform(f)
	// Where it went (the console / the editor's Play output).
	if crash.pathLen > 0 {
		crash_write_platform(Crash_File(CRASH_STDERR), "\nCrash report: ")
		crash_write_platform(Crash_File(CRASH_STDERR), string(crash.path[:crash.pathLen]))
		crash_write_platform(Crash_File(CRASH_STDERR), "\n")
	}
}

// crash_own_frame: a frame of the crash handling itself (left out of the stack).
@(private)
crash_own_frame :: proc "contextless" (sym: string) -> bool {
	has :: proc "contextless" (s, sub: string) -> bool {
		if len(sub) > len(s) do return false
		for i in 0 ..= len(s) - len(sub) do if s[i:i + len(sub)] == sub do return true
		return false
	}
	return has(sym, "crash_") || has(sym, "Crash_AssertionFailure") || has(sym, "_sigtramp") || has(sym, "default_assertion") || sym == "runtime::panic"
}

@(private)
crash_itoa :: proc "contextless" (buf: []u8, v: i64) -> string {
	n := v
	neg := n < 0
	if neg do n = -n
	i := len(buf)
	for {
		i -= 1
		buf[i] = u8('0' + n % 10)
		n /= 10
		if n == 0 || i == 1 do break
	}
	if neg {
		i -= 1
		buf[i] = '-'
	}
	return string(buf[i:])
}

@(private)
crash_hex :: proc "contextless" (buf: []u8, v: uintptr) -> string {
	DIGITS := "0123456789abcdef"
	i := len(buf)
	n := v
	for {
		i -= 1
		buf[i] = DIGITS[n & 0xf]
		n >>= 4
		if n == 0 || i == 2 do break
	}
	i -= 2
	buf[i] = '0'
	buf[i + 1] = 'x'
	return string(buf[i:])
}

@(private = "file")
crash_os_name :: proc() -> string {
	#partial switch ODIN_OS {
	case .Darwin: return "macOS"
	case .Windows: return "Windows"
	case .Linux: return "Linux"
	case .JS: return "Web"
	}
	return ODIN_OS_STRING
}

// --- reading reports ----------------------------------------------------------

Crash_Report :: struct {
	path: string,
	text: string,
}

// Crash_Pending: the reports in `dir` not yet seen (oldest first; temp).
Crash_Pending :: proc(dir: string, allocator := context.temp_allocator) -> []Crash_Report {
	out := make([dynamic]Crash_Report, allocator)
	if dir == "" do return out[:]
	infos, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil do return out[:]
	slice.sort_by(infos, proc(a, b: os.File_Info) -> bool {return a.name < b.name})
	for fi in infos {
		if fi.type == .Directory || !strings.has_prefix(fi.name, "crash-") || !strings.has_suffix(fi.name, ".txt") do continue
		p, _ := filepath.join({dir, fi.name}, allocator)
		data, rerr := os.read_entire_file(p, allocator)
		if rerr != nil do continue
		append(&out, Crash_Report{p, string(data)})
	}
	return out[:]
}

// Crash_MarkSeen keeps a report but stops offering it (.txt -> .seen).
Crash_MarkSeen :: proc(path: string) -> bool {
	if !strings.has_suffix(path, ".txt") do return false
	seen := strings.concatenate({strings.trim_suffix(path, ".txt"), ".seen"}, context.temp_allocator)
	return os.rename(path, seen) == nil
}

// crash_prune keeps the newest CRASH_KEEP reports.
@(private = "file")
crash_prune :: proc(dir: string) {
	infos, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil do return
	names := make([dynamic]string, context.temp_allocator)
	for fi in infos do if strings.has_prefix(fi.name, "crash-") do append(&names, fi.name)
	if len(names) <= CRASH_KEEP do return
	slice.sort(names[:])
	for name in names[:len(names) - CRASH_KEEP] {
		p, _ := filepath.join({dir, name}, context.temp_allocator)
		_ = os.remove(p)
	}
}

// Crash_IssueURL: a GitHub "new issue" page with the title and body filled
// in (the body cut to fit a URL: browsers / GitHub take about 8 KB).
Crash_IssueURL :: proc(repo, title, body: string, label := "", allocator := context.temp_allocator) -> string {
	MAX_BODY :: 6000 // encoded bytes
	sb := strings.builder_make(allocator)
	fmt.sbprintf(&sb, "https://github.com/%s/issues/new?title=", repo)
	url_encode(&sb, title)
	if label != "" {
		strings.write_string(&sb, "&labels=")
		url_encode(&sb, label)
	}
	strings.write_string(&sb, "&body=")
	enc := strings.builder_make(context.temp_allocator)
	url_encode(&enc, body)
	text := strings.to_string(enc)
	if len(text) > MAX_BODY {
		cut := MAX_BODY // (not inside a %XX)
		if text[cut - 1] == '%' do cut -= 1
		else if text[cut - 2] == '%' do cut -= 2
		strings.write_string(&sb, text[:cut])
		url_encode(&sb, "\n\n(cut: the full report is in the crash folder)")
	} else {
		strings.write_string(&sb, text)
	}
	return strings.to_string(sb)
}

@(private = "file")
url_encode :: proc(sb: ^strings.Builder, s: string) {
	HEX := "0123456789ABCDEF"
	for i in 0 ..< len(s) {
		b := s[i]
		switch b {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '-', '_', '.', '~':
			strings.write_byte(sb, b)
		case:
			strings.write_byte(sb, '%')
			strings.write_byte(sb, HEX[b >> 4])
			strings.write_byte(sb, HEX[b & 0xf])
		}
	}
}

// --- Lua: the Crash module ------------------------------------------------------

// Crash.pending() -> {{path =, text =}, ...}: reports from earlier runs.
// crash_script_dir: the game's crash folder as scripts see it - none in
// the editor (Simulate), whose crash folder is the editor's own.
@(private = "file")
crash_script_dir :: proc(L: ^lua.State) -> string {
	if sm := get_script_manager(L); sm != nil && sm.game != nil && sm.game.inEditor do return ""
	return crash.dir
}

@(private = "file")
lua_crash_pending :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	reports := Crash_Pending(crash_script_dir(L)) if crash_script_dir(L) != "" else nil
	lua.createtable(L, c.int(len(reports)), 0)
	for r, i in reports {
		lua.createtable(L, 0, 2)
		lua.pushstring(L, strings.clone_to_cstring(r.path, context.temp_allocator))
		lua.setfield(L, -2, "path")
		lua.pushlstring(L, cstring(raw_data(r.text)) if len(r.text) > 0 else "", c.size_t(len(r.text)))
		lua.setfield(L, -2, "text")
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

// Crash.dismiss(path) -> ok: a report is handled (not offered again).
@(private = "file")
lua_crash_dismiss :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	p := string(lua.L_checkstring(L, 1))
	// (Only reports in the crash folder.)
	dir, _ := filepath.clean(crash_script_dir(L), context.temp_allocator)
	ok := crash_script_dir(L) != "" && filepath.dir(p, context.temp_allocator) == dir && Crash_MarkSeen(p)
	lua.pushboolean(L, b32(ok))
	return 1
}

// Crash.note(text): a line for a crash report (what the game was doing).
@(private = "file")
lua_crash_note :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	Crash_Note(fmt.tprintf("[lua] %s", lua.L_checkstring(L, 1)))
	return 0
}

// Crash.dir() -> the crash folder
@(private = "file")
lua_crash_dir :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	lua.pushstring(L, strings.clone_to_cstring(crash_script_dir(L), context.temp_allocator))
	return 1
}

// Script_RegisterCrashModule creates the global Crash table.
Script_RegisterCrashModule :: proc(L: ^lua.State) {
	lua.newtable(L)
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "pending", lua_crash_pending)
	reg(L, "dismiss", lua_crash_dismiss)
	reg(L, "note", lua_crash_note)
	reg(L, "dir", lua_crash_dir)
	lua.setglobal(L, "Crash")
}
