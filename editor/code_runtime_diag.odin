package editor

import "core:fmt"
import "core:strconv"
import "core:strings"
import buf "../odin_editor/buffer"
import lsp "../odin_editor/lsp"

// ============================================================================
// Runtime diagnostics: script errors and warnings from Simulate (the engine's
// Script_Problem) and from the game's output (Play) - "scripts/x.lua:12:
// message" - become diagnostics on that line in the Code tab, next to the
// language server's (red errors, yellow warnings, the message on hover).
// Cleared when the game / simulation starts again, and a script's when it
// is edited (they are about lines of the old text, #403) or saved.
// ============================================================================

Runtime_Diag :: struct {
	script:  string, // project-relative ("scripts/x.lua")
	line:    int,    // 0-based
	message: string,
	warning: bool,
	count:   int,
}

@(private = "file")
runtimeDiags: [dynamic]Runtime_Diag

MAX_RUNTIME_DIAGS :: 200

// CodeRuntime_Report takes a line of script output; true when it named a
// script line (and was recorded).
CodeRuntime_Report :: proc(text: string, warning := false) -> bool {
	// "...scripts/x.lua:12: message" (the first "<path>.lua:<digits>").
	i := -1
	for off := 0; off < len(text); {
		j := strings.index(text[off:], ".lua:")
		if j < 0 do break
		at := off + j
		if at + 5 < len(text) && text[at + 5] >= '0' && text[at + 5] <= '9' {i = at; break}
		off = at + 5
	}
	if i < 0 do return false
	start := i
	for start > 0 && !strings.contains_rune(" \t'\"[(", rune(text[start - 1])) do start -= 1
	script := strings.trim_prefix(text[start:i + 4], "@")
	rest := text[i + 5:]
	n := 0
	for n < len(rest) && rest[n] >= '0' && rest[n] <= '9' do n += 1
	if n == 0 do return false
	line, _ := strconv.parse_int(rest[:n])
	msg := strings.trim_space(strings.trim_prefix(rest[n:], ":"))
	if nl := strings.index_byte(msg, '\n'); nl >= 0 do msg = msg[:nl] // not the traceback
	for &d in runtimeDiags {
		if d.script == script && d.line == line - 1 && d.message == msg {
			d.count += 1
			return true
		}
	}
	if len(runtimeDiags) >= MAX_RUNTIME_DIAGS do return true
	append(&runtimeDiags, Runtime_Diag{strings.clone(script), max(line - 1, 0), strings.clone(msg), warning, 1})
	return true
}

// CodeRuntime_Clear forgets the problems (of one script, or all).
CodeRuntime_Clear :: proc(script := "") {
	for i := len(runtimeDiags) - 1; i >= 0; i -= 1 {
		d := runtimeDiags[i]
		if script != "" && d.script != script do continue
		delete(d.script)
		delete(d.message)
		ordered_remove(&runtimeDiags, i)
	}
}

// CodeRuntime_Count: problems recorded (drives).
CodeRuntime_Count :: proc() -> int {return len(runtimeDiags)}

// code_runtime_diagnostics: a document's runtime problems as diagnostics.
code_runtime_diagnostics :: proc(doc: ^Code_Doc) -> []lsp.Diagnostic {
	out := make([dynamic]lsp.Diagnostic, context.temp_allocator)
	for d in runtimeDiags {
		if !strings.has_suffix(doc.path, d.script) && doc.rel != d.script do continue
		text := ""
		if d.line < buf.buffer_line_count(&doc.buffer) do text = buf.buffer_line_str(&doc.buffer, d.line)
		first := len(text) - len(strings.trim_left_space(text))
		msg := d.message
		if d.count > 1 do msg = fmt.tprintf("%s (%d times)", msg, d.count)
		append(&out, lsp.Diagnostic{
			range    = {start = {line = d.line, character = first}, end = {line = d.line, character = max(len(text), first + 1)}},
			severity = 2 if d.warning else 1,
			message  = strings.concatenate({"Runtime: " if !d.warning else "Runtime warning: ", msg}, context.temp_allocator),
			source   = "game",
		})
	}
	return out[:]
}

// code_runtime_follow_edits: an edited script's runtime problems go - their
// lines were the old text's (until the next run reports them again).
code_runtime_follow_edits :: proc() {
	for doc in GlobalCode.docs {
		if doc.runtimeVersion == doc.buffer.version do continue
		doc.runtimeVersion = doc.buffer.version
		if len(runtimeDiags) > 0 do CodeRuntime_Clear(doc.rel)
	}
}
