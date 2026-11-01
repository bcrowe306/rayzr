package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:sys/posix"
import "core:time"
import "core:unicode/utf8"
import e "../engine"
import buf "../odin_editor/buffer"
import lsp "../odin_editor/lsp"
import syn "../odin_editor/syntax"
import imgui "lib/imgui"

// ============================================================================
// Code editor: Lua scripts open in a "Code" tab docked next to the Viewport.
//
// Text editing reuses odin_editor's host-agnostic packages (buffer: text,
// cursors, undo; syntax: the Lua highlighter; lsp: the language server
// client). This file draws the text with ImGui and maps ImGui input onto
// buffer commands; code_editor_lsp.odin talks to lua-language-server for
// completion, signature help, hover, diagnostics and go-to-definition,
// with the engine's API definitions (engine/definitions) as its library.
//
// Open a script from anywhere with Editor_OpenScript(state, path, line).
// Saving (Ctrl/Cmd+S) writes the file; the running scripts hot-reload.
// ============================================================================

CODE_WINDOW :: "Code###CodeEditorWindow"
// Tab stops come from Settings > Code Editor (code_tab_width()).
CODE_FONT_SIZE :: 14

// CODE_BG: the code area background (a theme colour, theme.odin).

Code_Doc :: struct {
	path:          string, // absolute
	rel:           string, // shown in tabs (project-relative when inside the project)
	uri:           string,
	buffer:        buf.Buffer,
	lang:          syn.Language,
	isLua:         bool,
	useTabs:       bool,
	savedVersion:  int,
	diskTime:      time.Time,
	// LSP: last buffer version sent (didOpen/didChange).
	lspOpen:       bool,
	sentVersion:   int,
	// Tokenizer state at the start of each line, valid for statesVersion.
	lineStates:    [dynamic]int,
	statesVersion: int,
	tokens:        Token_Cache, // per-line tokens (code_token_cache.odin)
	maxCols:       int, // widest line (columns), for widthVersion
	widthVersion:  int,
	widthValid:    bool,
	scrollToCursor: bool,
	structure:     Code_Structure, // brackets / blocks (code_structure.odin)
	selStack:      [dynamic][2]buf.Position, // expand selection history (shrink pops)
	cursorHistory: [dynamic][]buf.Cursor,    // cursor sets before additions (Cmd+U)
	display:       Code_Display,             // rows on screen (code_display.odin)
	folds:         [dynamic]int,             // folded block start lines (code_fold.odin)
	foldText:      map[int]u64,              // ... their first line's text (to follow edits)
	foldsVersion:  int,
	foldsTextVersion: int,
	symCache:      Code_Sym_Cache, // whole-file uses of the caret word (code_minimap.odin)
	scrollToTop:   bool, // scroll the caret's line to the top (under the pinned lines)
	preview:       bool, // a preview tab: replaced by the next preview until edited / kept
	pinned:        bool, // a pinned tab: first, no close button, skipped by bulk closes
	diskConflict:  bool, // changed on disk while edited here (the banner asks)
	git:           Code_Git,       // changes since the last commit (code_git.odin)
	inlayCache:    Code_Inlay_Cache, // parameter-name hints per line (code_inlay.odin)
}

Code_Completion :: struct {
	open:      bool,
	waiting:   bool, // a request is in flight
	seq:       int,  // client.completion_seq when it was sent
	anchor:    buf.Position, // start of the word being completed
	selected:  int,
	filtered:  [dynamic]int, // indices into client.last_completion
	filteredSeq: int,        // the client.completion_seq `filtered` was built from
	scrollTo:  bool,
	// While the server is still loading the workspace it answers with empty
	// lists; those requests are retried for a while.
	retries:   int,
	retryAt:   time.Tick,
	retryPending: bool,
}

Code_LSP_State :: enum {
	Off,
	Starting,
	Ready,
	Failed,
}

Code_Editor :: struct {
	docs:          [dynamic]^Code_Doc,
	active:        int,
	selectRequest: int, // tab to select next frame (-1 = none)
	focusRequest:  bool,
	focused:       bool, // the text area had keyboard focus last frame
	windowFocused: bool, // any part of the Code window (tabs, find bar) had focus
	closePrompt:   int,  // doc waiting for Save / Don't Save (-1 = none)
	closeRequest:  int,  // tab to close at the end of the frame (-1 = none)
	closeOthers:   int,  // close every tab but this one (-2 = all, -1 = none)
	closeMode:     enum {Others, Right, Saved}, // with closeOthers: which tabs go
	columnFrom:    [2]f32, // Alt-drag column selection: where it started (screen)
	stickyH:       f32,    // height of the pinned block headers this frame (code_sticky.odin)
	bulbMin, bulbMax: [2]f32, // the gutter lightbulb's rect (last frame; zero = none)
	lastDiskCheck: time.Tick,
	cursorMoved:   time.Tick, // caret blink restarts on movement
	// Layout of the last drawn frame (screen space).
	charW, lineH:  f32,
	textOrigin:    [2]f32, // screen position of line 0, column 0
	areaMin, areaMax: [2]f32,
	popupMin, popupMax: [2]f32, // completion popup (clicks there don't hit the text)

	// Language server.
	client:        lsp.Client,
	lspState:      Code_LSP_State,
	lspMessage:    string,
	lspReadyAt:    time.Tick,
	completion:    Code_Completion,
	sigOpen:       bool,
	sigWaiting:    bool,
	sigSeq:        int,
	hoverPos:      buf.Position,
	hoverSince:    time.Tick,
	hoverValid:    bool, // mouse is over text at hoverPos
	hoverSent:     bool,
	hoverSeq:      int,
	defWaiting:    bool,
	defSeq:        int,
	refsWaiting:   bool,
	refsSeq:       int,
	editsWaiting:  bool,
	editsSeq:      int,
	formatDoc:     ^Code_Doc,
	saveAfterFormat: ^Code_Doc, // format-on-save: save when the format edits arrive

	find:          Code_Find,
	fontSize:      f32, // 0 = CODE_FONT_SIZE
	closedFiles:   [dynamic]string, // for Reopen Closed Tab
	renameOpen:    bool,
	renameBuf:     [128]u8,
	renamePos:     buf.Position,
	renameDoc:     ^Code_Doc,
	// Remaining tab stops of the last accepted snippet (code_editor_lsp.odin).
	snippetStops:  [dynamic]Snippet_Pending,
	snippetLine:   int,
	resolveIndex:  int, // completion item whose documentation was requested
	resolveSeq:    int,
}

GlobalCode := Code_Editor{selectRequest = -1, closePrompt = -1, closeRequest = -1, closeOthers = -1}

// --- documents ---------------------------------------------------------------------

// code_abs_path resolves a project-relative path ("scripts/x.lua").
code_abs_path :: proc(state: ^EditorState, path: string) -> string {
	if filepath.is_abs(path) {
		p, _ := filepath.clean(path, context.temp_allocator)
		return p
	}
	p, _ := filepath.join({state.projectPath, path}, context.temp_allocator)
	if !os.exists(p) && os.exists(path) {
		cwd := os.get_working_directory(context.temp_allocator) or_else ""
		p, _ = filepath.join({cwd, path}, context.temp_allocator)
	}
	return p
}

code_rel_path :: proc(state: ^EditorState, abs: string) -> string {
	// macOS: /tmp, /var and /etc are links into /private; tools (the
	// language server) may report either form.
	canon :: proc(p: string) -> string {
		when ODIN_OS == .Darwin {
			if strings.has_prefix(p, "/private/") do return p[len("/private"):]
		}
		return p
	}
	root := canon(strings.trim_suffix(state.projectPath, "/"))
	a := canon(abs)
	if root != "" && strings.has_prefix(a, root) && len(a) > len(root) && a[len(root)] == '/' {
		return a[len(root) + 1:]
	}
	return filepath.base(abs)
}

code_file_mtime :: proc(path: string) -> time.Time {
	info, err := os.stat(path, context.temp_allocator)
	if err != nil do return {}
	return info.modification_time
}

// Editor_OpenScript opens a script (project-relative or absolute) in the
// Code tab, focusing it, and moves the caret to `line`/`col` (0-based) if
// given. Opening an already open file just switches to its tab.
Editor_OpenScript :: proc(state: ^EditorState, path: string, line := -1, col := 0, preview := false) -> bool {
	cm := &GlobalCode
	abs := code_abs_path(state, path)
	// The same file through a symlink (the language server reports
	// /private/tmp/... for /tmp/... on macOS): use the project's spelling.
	if real, realProj := code_real_path(abs), code_real_path(state.projectPath); realProj != "" && strings.has_prefix(real, strings.concatenate({strings.trim_suffix(realProj, "/"), "/"}, context.temp_allocator)) {
		abs = strings.concatenate({strings.trim_suffix(state.projectPath, "/"), real[len(strings.trim_suffix(realProj, "/")):]}, context.temp_allocator)
	}
	idx := -1
	for d, i in cm.docs do if d.path == abs do idx = i
	if idx >= 0 && !preview do cm.docs[idx].preview = false // opened for real: keep it
	if idx < 0 && preview {
		// A preview replaces the previous one (unless it was edited).
		for d, i in cm.docs {
			if d.preview && !code_doc_dirty(d) {
				code_close_doc(i)
				if cm.active >= len(cm.docs) do cm.active = len(cm.docs) - 1
				break
			}
		}
	}
	if idx < 0 {
		doc := new(Code_Doc)
		doc.buffer = buf.buffer_init()
		if !buf.buffer_load_file(&doc.buffer, abs) {
			buf.buffer_destroy(&doc.buffer)
			free(doc)
			Editor_Log(state, .Error, "Could not open %s", path)
			return false
		}
		doc.buffer.track_changes = false
		doc.path = strings.clone(abs)
		doc.rel = strings.clone(code_rel_path(state, abs))
		doc.uri = lsp.file_uri(abs)
		doc.lang = syn.language_for_path(abs)
		doc.isLua = doc.lang.name == "lua"
		doc.savedVersion = doc.buffer.version
		doc.diskTime = code_file_mtime(abs)
		code_git_load(doc) // the committed version, for the git gutter
		// Keep the file's indentation style (Settings decide for new files).
		doc.useTabs = !GlobalSettings.insertSpaces
		for i in 0 ..< buf.buffer_line_count(&doc.buffer) {
			l := buf.buffer_line_str(&doc.buffer, i)
			if strings.has_prefix(l, "\t") {doc.useTabs = true; break}
			if strings.has_prefix(l, "  ") {doc.useTabs = false; break}
		}
		doc.preview = preview
		append(&cm.docs, doc)
		idx = len(cm.docs) - 1
	}
	doc := cm.docs[idx]
	if line >= 0 {
		b := &doc.buffer
		p := buf.buffer_clamp_position(b, {line, col})
		code_set_single_cursor(b, p, false)
		doc.scrollToCursor = true
	}
	cm.active = idx
	cm.selectRequest = idx
	cm.focusRequest = true
	return true
}

// Code_IsOpen reports whether a file is open in the code editor.
Code_IsOpen :: proc(state: ^EditorState, path: string) -> bool {
	abs := code_abs_path(state, path)
	for d in GlobalCode.docs do if d.path == abs do return true
	return false
}

// Code_DocText: a document's full text (temp).
Code_DocText :: proc(doc: ^Code_Doc) -> string {
	return buf.buffer_to_string(&doc.buffer, context.temp_allocator)
}

// Code_IsDirty: an open file with unsaved changes.
Code_IsDirty :: proc(state: ^EditorState, path: string) -> bool {
	abs := code_abs_path(state, path)
	for d in GlobalCode.docs do if d.path == abs do return code_doc_dirty(d)
	return false
}

// Code_HasFocus: the text area owns the keyboard (editor shortcuts stay off).
Code_HasFocus :: proc() -> bool {
	return GlobalCode.focused
}

// Code_WindowFocused: the Code window (text, tabs or find bar) has focus;
// code shortcuts apply.
Code_WindowFocused :: proc() -> bool {
	return len(GlobalCode.docs) > 0 && (GlobalCode.focused || GlobalCode.windowFocused)
}

code_doc_dirty :: proc(doc: ^Code_Doc) -> bool {
	return doc.buffer.version != doc.savedVersion
}

// Code_DirtyCount counts open files with unsaved changes.
Code_DirtyCount :: proc() -> int {
	n := 0
	for d in GlobalCode.docs do if code_doc_dirty(d) do n += 1
	return n
}

Code_SaveDoc :: proc(state: ^EditorState, doc: ^Code_Doc) -> bool {
	CodeRuntime_Clear(doc.rel) // its runtime problems were about the old text
	if !buf.buffer_save_file(&doc.buffer, doc.path) {
		Editor_Log(state, .Error, "Could not save %s", doc.rel)
		return false
	}
	doc.savedVersion = doc.buffer.version
	doc.diskTime = code_file_mtime(doc.path)
	doc.diskConflict = false
	code_git_load(doc) // HEAD may have moved
	Code_HistorySave(state, doc) // local history (code_history.odin)
	code_lsp_did_save(doc)
	Editor_Log(state, .Info, "Saved %s", doc.rel)
	// A custom node type's file: its nodes in the open documents follow.
	if Asset_KindOf(doc.rel) == .CustomNode {
		if n := Editor_RefreshCustomNodes(state, doc.rel); n > 0 do Editor_Log(state, .Info, "%d node(s) of the type updated", n)
	}
	// Running scripts (Simulate) pick the change up right away.
	if n := e.ScriptManager_CheckForChanges(&state.game.scriptManager, force = true); n > 0 {
		Editor_Log(state, .Info, "Reloaded %d changed script(s)", n)
	}
	return true
}

// Code_SaveAll saves every modified file.
Code_SaveAll :: proc(state: ^EditorState) -> int {
	n := 0
	for d in GlobalCode.docs do if code_doc_dirty(d) && Code_SaveDoc(state, d) do n += 1
	return n
}

code_close_doc :: proc(idx: int) {
	cm := &GlobalCode
	if idx < 0 || idx >= len(cm.docs) do return
	doc := cm.docs[idx]
	append(&cm.closedFiles, strings.clone(doc.path))
	if cm.renameDoc == doc do cm.renameDoc = nil
	if cm.formatDoc == doc do cm.formatDoc = nil
	if cm.saveAfterFormat == doc do cm.saveAfterFormat = nil
	code_lsp_did_close(doc)
	buf.buffer_destroy(&doc.buffer)
	delete(doc.lineStates)
	Token_CacheDestroy(&doc.tokens)
	code_structure_destroy(&doc.structure)
	delete(doc.selStack)
	code_cursor_history_destroy(doc)
	code_display_destroy(&doc.display)
	delete(doc.folds)
	delete(doc.foldText)
	code_sym_cache_destroy(&doc.symCache)
	code_git_destroy(doc)
	code_inlay_cache_destroy(&doc.inlayCache)
	delete(doc.path)
	delete(doc.rel)
	delete(doc.uri)
	free(doc)
	ordered_remove(&cm.docs, idx)
	if cm.active >= len(cm.docs) do cm.active = len(cm.docs) - 1
	if cm.active > idx do cm.active -= 1
	cm.completion.open = false
	cm.sigOpen = false
	if len(cm.docs) == 0 do cm.focused = false
}

// code_request_close closes a tab at the end of the frame (the document
// may still be in use), asking first when it has unsaved changes.
code_request_close :: proc(idx: int) {
	if idx < 0 || idx >= len(GlobalCode.docs) do return
	if code_doc_dirty(GlobalCode.docs[idx]) {
		GlobalCode.closePrompt = idx
	} else {
		GlobalCode.closeRequest = idx
	}
}

Code_Shutdown :: proc() {
	cm := &GlobalCode
	for len(cm.docs) > 0 do code_close_doc(len(cm.docs) - 1)
	delete(cm.docs)
	delete(cm.completion.filtered)
	for f in cm.closedFiles do delete(f)
	delete(cm.closedFiles)
	delete(cm.snippetStops)
	Code_ClipboardShutdown()
	Code_NavShutdown()
	Code_SearchShutdown()
	Code_PeekShutdown()
	Code_ActionsShutdown()
	Code_RenamePreviewShutdown()
	Code_HistoryShutdown()
	Code_InlayShutdown()
	StateGraph_Shutdown()
	BehaviorTree_Shutdown()
	code_find_destroy()
	code_lsp_shutdown()
}

// code_check_disk reloads files changed on disk (unless edited here).
code_check_disk :: proc(state: ^EditorState) {
	cm := &GlobalCode
	if time.tick_since(cm.lastDiskCheck) < time.Second do return
	cm.lastDiskCheck = time.tick_now()
	for doc in cm.docs {
		mt := code_file_mtime(doc.path)
		if mt == doc.diskTime || mt == {} do continue
		doc.diskTime = mt
		if code_doc_dirty(doc) {
			doc.diskConflict = true // ask: Reload / Keep Mine (code_history.odin)
			continue
		}
		data, err := os.read_entire_file(doc.path, context.temp_allocator)
		if err != nil do continue
		if string(data) == buf.buffer_to_string(&doc.buffer, context.temp_allocator) do continue
		code_replace_text(doc, string(data)) // one undoable edit
		doc.savedVersion = doc.buffer.version
	}
}

// --- text geometry -----------------------------------------------------------------

// code_visual_col: byte column -> screen column (tabs expand, one cell per rune).
code_visual_col :: proc(line: string, byteCol: int) -> int {
	v := 0
	i := 0
	for i < len(line) && i < byteCol {
		r, w := utf8.decode_rune_in_string(line[i:])
		if r == '\t' do v = (v / code_tab_width() + 1) * code_tab_width()
		else do v += 1
		i += max(w, 1)
	}
	return v
}

// code_byte_col: screen column -> nearest byte column.
code_byte_col :: proc(line: string, visual: int) -> int {
	v := 0
	i := 0
	for i < len(line) {
		r, w := utf8.decode_rune_in_string(line[i:])
		next := (v / code_tab_width() + 1) * code_tab_width() if r == '\t' else v + 1
		if visual < next {
			// Closer to the start or the end of this cell?
			return i if visual - v <= (next - v) / 2 else i + max(w, 1)
		}
		v = next
		i += max(w, 1)
	}
	return len(line)
}

// LSP positions count UTF-16 code units.
code_u16_col :: proc(line: string, byteCol: int) -> int {
	n := 0
	for r, i in line {
		if i >= byteCol do break
		n += 2 if r > 0xFFFF else 1
	}
	return n
}

code_byte_from_u16 :: proc(line: string, u16Col: int) -> int {
	n := 0
	for r, i in line {
		if n >= u16Col do return i
		n += 2 if r > 0xFFFF else 1
	}
	return len(line)
}

code_set_single_cursor :: proc(b: ^buf.Buffer, p: buf.Position, extend: bool) {
	if len(b.cursors) == 0 do append(&b.cursors, buf.Cursor{})
	resize(&b.cursors, 1)
	c := &b.cursors[0]
	if extend {
		if !c.sel.active do c.sel = {anchor = c.pos, active = true}
	} else {
		c.sel.active = false
	}
	c.pos = p
	c.has_goal = false
}

code_is_ident_byte :: proc(ch: u8) -> bool {
	return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_'
}

// code_word_start: start of the identifier ending at `p`.
code_word_start :: proc(b: ^buf.Buffer, p: buf.Position) -> buf.Position {
	line := buf.buffer_line_str(b, p.line)
	col := min(p.col, len(line))
	for col > 0 && code_is_ident_byte(line[col - 1]) do col -= 1
	return {p.line, col}
}

// code_selected_text returns the primary selection ("" if none).
code_selected_text :: proc(b: ^buf.Buffer, allocator := context.temp_allocator) -> string {
	start, end, ok := buf.selection_range(b.cursors[0])
	if !ok do return ""
	sb := strings.builder_make(allocator)
	for ln in start.line ..= end.line {
		line := buf.buffer_line_str(b, ln)
		from := start.col if ln == start.line else 0
		to := end.col if ln == end.line else len(line)
		strings.write_string(&sb, line[min(from, len(line)):min(to, len(line))])
		if ln != end.line do strings.write_byte(&sb, '\n')
	}
	return strings.to_string(sb)
}

// --- rendering ---------------------------------------------------------------------

// code_syntax: a syntax colour, darker on light themes.
code_syntax :: proc(v: imgui.Vec4) -> u32 {
	c := v
	if UI_THEME_LIGHT do c = {v.x * 0.58, v.y * 0.58, v.z * 0.58, v.w}
	return col_u32(c)
}

code_token_color :: proc(k: syn.TokenKind) -> u32 {
	switch k {
	case .Keyword:     return code_syntax({0.78, 0.55, 0.95, 1})
	case .String:      return code_syntax({0.60, 0.82, 0.52, 1})
	case .Number:      return code_syntax({0.96, 0.66, 0.42, 1})
	case .Comment:     return code_syntax({0.42, 0.47, 0.55, 1})
	case .Function:    return code_syntax({0.42, 0.68, 1.00, 1})
	case .Builtin:     return code_syntax({0.35, 0.82, 0.86, 1})
	case .Constant:    return code_syntax({0.96, 0.55, 0.45, 1})
	case .Property:    return code_syntax({0.90, 0.78, 0.55, 1})
	case .Type:        return code_syntax({0.95, 0.80, 0.40, 1})
	case .Operator, .Punctuation: return code_syntax({0.65, 0.70, 0.78, 1})
	case .Directive, .Attribute:  return code_syntax({0.78, 0.55, 0.95, 1})
	case .Identifier, .Default:   return code_syntax(UI_TEXT)
	}
	return code_syntax(UI_TEXT)
}

// code_draw_inlay draws a hint chip at column v; returns the column after.
code_draw_inlay :: proc(dl: ^imgui.DrawList, x0, y: f32, v: int, h: Code_Inlay, doc: ^Code_Doc = nil, line := 0) -> int {
	cm := &GlobalCode
	if h.swatch do return code_draw_swatch(dl, x0, y, v, h, doc, line)
	w := code_inlay_width(h)
	x := x0 + f32(v) * cm.charW
	imgui.DrawList_AddRectFilled(dl, {x, y}, {x + f32(w - 1) * cm.charW + 2, y + code_font_size()}, col_u32(ui_line(0.06)), 3)
	code_draw_text(dl, x0 + 1, y, v, h.label, col_u32(UI_TEXT_FAINT))
	return v + w
}

// code_draw_inline_values: "name = value" for each local the line uses
// (once each), after the line, faint.
code_draw_inline_values :: proc(dl: ^imgui.DrawList, x, y: f32, text: string, tokens: []syn.Token, locals: [][3]string) {
	s := code_inline_values_text(text, tokens, locals)
	if s == "" do return
	label := strings.clone_to_cstring(s, context.temp_allocator)
	w := imgui.CalcTextSize(label).x
	imgui.DrawList_AddRectFilled(dl, {x - 4, y - 1}, {x + w + 4, y + code_font_size() + 1}, col_u32({0.96, 0.72, 0.30, 0.10}), 3)
	imgui.DrawList_AddText(dl, {x, y}, col_u32({0.96, 0.78, 0.45, 0.85}), label)
}

// code_inline_values_text: "a = 1, b = 2" for the locals a line uses.
code_inline_values_text :: proc(text: string, tokens: []syn.Token, locals: [][3]string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	seen := make([dynamic]string, context.temp_allocator)
	for t in tokens {
		if t.kind != .Identifier && t.kind != .Builtin do continue
		name := text[t.start:t.end]
		if t.start > 0 && (text[t.start - 1] == '.' || text[t.start - 1] == ':') do continue // a field
		dup := false
		for s in seen do if s == name do dup = true
		if dup do continue
		for l in locals {
			if l[0] != name do continue
			v := l[1]
			if len(v) > 40 do v = fmt.tprintf("%s…", v[:38])
			fmt.sbprintf(&sb, "%s%s = %s", ", " if strings.builder_len(sb) > 0 else "", name, v)
			append(&seen, name)
			break
		}
		if strings.builder_len(sb) > 120 do break
	}
	return strings.to_string(sb)
}

RAINBOW := [3]imgui.Vec4{{0.98, 0.82, 0.30, 1}, {0.85, 0.50, 0.95, 1}, {0.35, 0.72, 1.00, 1}}

// code_draw_marked draws text[from:to] in color, with any bracket in marks
// (this line's, code_structure.odin) in its depth's rainbow colour
// (unmatched ones red). Returns the column after it.
code_draw_marked :: proc(dl: ^imgui.DrawList, x0, y: f32, vcol: int, text: string, from, to: int, color: u32, marks: []Code_Bracket_Mark) -> int {
	v := vcol
	at := from
	for m in marks {
		if m.pos.col < from || m.pos.col >= to do continue
		if m.pos.col > at do v = code_draw_text(dl, x0, y, v, text[at:m.pos.col], color)
		col := code_syntax(RAINBOW[m.depth % len(RAINBOW)]) if m.matched else col_u32(UI_DANGER)
		v = code_draw_text(dl, x0, y, v, text[m.pos.col:m.pos.col + 1], col)
		at = m.pos.col + 1
	}
	if at < to do v = code_draw_text(dl, x0, y, v, text[at:to], color)
	return v
}

// code_line_indent: a line's indentation in columns (tabs to tab stops).
code_line_indent :: proc(line: string, tab: int) -> int {
	v := 0
	for ch in transmute([]u8)line {
		switch ch {
		case ' ': v += 1
		case '\t': v = (v / max(tab, 1) + 1) * max(tab, 1)
		case: return v
		}
	}
	return v
}

// code_draw_text draws `text` starting at screen column `vcol`; tabs advance
// to the next tab stop. Returns the column after the text.
code_draw_text :: proc(dl: ^imgui.DrawList, x0, y: f32, vcol: int, text: string, color: u32) -> int {
	cm := &GlobalCode
	font := code_font()
	v := vcol
	segStart := 0
	flush :: proc(dl: ^imgui.DrawList, font: ^imgui.Font, x0, y, charW: f32, v: int, s: string, color: u32) {
		if len(s) == 0 do return
		cs := strings.clone_to_cstring(s, context.temp_allocator)
		imgui.DrawList_AddTextImFontPtr(dl, font, code_font_size(), {x0 + f32(v) * charW, y}, color, cs)
	}
	segV := v
	for i := 0; i < len(text); {
		r, w := utf8.decode_rune_in_string(text[i:])
		if r == '\t' {
			flush(dl, font, x0, y, cm.charW, segV, text[segStart:i], color)
			v = (v / code_tab_width() + 1) * code_tab_width()
			segStart = i + 1
			segV = v
		} else {
			v += 1
		}
		i += max(w, 1)
	}
	flush(dl, font, x0, y, cm.charW, segV, text[segStart:], color)
	return v
}

code_tab_width :: proc() -> int {
	return clamp(GlobalSettings.tabWidth, 1, 16)
}

code_font :: proc() -> ^imgui.Font {
	return GlobalFonts.mono if GlobalFonts.mono != nil else GlobalFonts.regular
}

// code_update_line_states re-runs the tokenizer's line states after edits.
code_update_line_states :: proc(doc: ^Code_Doc) {
	b := &doc.buffer
	n := buf.buffer_line_count(b)
	if doc.statesVersion == b.version && len(doc.lineStates) == n do return
	// Unchanged lines (also shifted ones) come from the token cache.
	start := Token_CacheTimeStart(&doc.tokens)
	resize(&doc.lineStates, n)
	state := syn.LINE_STATE_NORMAL
	for i in 0 ..< n {
		doc.lineStates[i] = state
		_, state = Token_CacheGet(&doc.tokens, doc.lang, buf.buffer_line_str(b, i), state, b.version)
	}
	doc.statesVersion = b.version
	Token_CachePrune(&doc.tokens, n, b.version)
	Token_CacheTimeEnd(&doc.tokens, start)
}

Code_Render :: proc(state: ^EditorState) {
	cm := &GlobalCode
	code_lsp_update(state)
	Code_PeekUpdate(state)
	code_commands_update(state)
	code_check_disk(state)
	if len(cm.docs) == 0 {
		cm.focused = false
		cm.windowFocused = false
		return
	}
	if cm.focusRequest do imgui.SetWindowFocusStr(CODE_WINDOW)
	// First use: a tab next to the Viewport.
	if state.viewportDockId != 0 do imgui.SetNextWindowDockID(state.viewportDockId, .FirstUseEver)
	imgui.PushStyleVarImVec2(.WindowPadding, {0, 0})
	visible := imgui.Begin(CODE_WINDOW, nil, {.NoScrollbar, .NoScrollWithMouse})
	imgui.PopStyleVar()
	cm.windowFocused = imgui.IsWindowFocused(imgui.FocusedFlags_RootAndChildWindows)
	focusedNow := false
	if visible {
		code_tabs(state)
		if cm.active >= 0 && cm.active < len(cm.docs) {
			code_find_bar(state, cm.docs[cm.active])
			focusedNow = code_text_area(state, cm.docs[cm.active])
			code_status_line(state, cm.docs[cm.active])
		}
	}
	imgui.End()
	Code_NavTrack() // back / forward history (code_nav.odin)
	cm.focused = focusedNow
	if !focusedNow {
		cm.completion.open = false
		cm.sigOpen = false
	}
	if focusedNow && cm.active >= 0 && cm.active < len(cm.docs) {
		code_completion_popup(state, cm.docs[cm.active])
		code_signature_popup(cm.docs[cm.active])
	}
	code_close_prompt(state)
	code_rename_popup(state)
	Code_RenamePreviewRender(state)
	Code_HistoryRender(state)
	if cm.closeRequest >= 0 {
		code_close_doc(cm.closeRequest)
		cm.closeRequest = -1
	}
	if cm.closeOthers != -1 {
		keep := cm.docs[cm.closeOthers] if cm.closeOthers >= 0 && cm.closeOthers < len(cm.docs) else nil
		anchor := cm.closeOthers
		for i := len(cm.docs) - 1; i >= 0; i -= 1 {
			d := cm.docs[i]
			if d == keep && cm.closeMode != .Saved do continue
			if d.pinned do continue // pinned tabs stay
			if cm.closeMode == .Right && i <= anchor do continue
			if cm.closeMode == .Saved && code_doc_dirty(d) do continue
			if code_doc_dirty(d) {
				Editor_Log(state, .Warn, "%s has unsaved changes; not closed", d.rel)
				continue
			}
			code_close_doc(i)
		}
		cm.closeOthers = -1
		cm.closeMode = .Others
	}
}

code_tabs :: proc(state: ^EditorState) {
	cm := &GlobalCode
	imgui.PushStyleVarImVec2(.FramePadding, {10, 6})
	defer imgui.PopStyleVar()
	if !imgui.BeginTabBar("##code_tabs", {.Reorderable, .FittingPolicyScroll}) do return
	closeIdx := -1
	for doc, i in cm.docs {
		open := true
		flags: imgui.TabItemFlags = {}
		if code_doc_dirty(doc) {
			flags += {.UnsavedDocument}
			doc.preview = false // edited: a preview becomes a real tab
		}
		if cm.selectRequest == i do flags += {.SetSelected}
		if doc.pinned do flags += {.Leading} // first, not reorderable
		icon := ICON_FA_THUMBTACK if doc.pinned else (ICON_FA_EYE if doc.preview else ICON_FA_FILE_CODE)
		label := fmt.ctprintf("%s  %s###codetab_%s", icon, filepath.base(doc.rel), doc.path)
		if doc.preview do imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
		tabOpen := imgui.BeginTabItem(label, nil if doc.pinned else &open, flags)
		if doc.preview do imgui.PopStyleColor()
		if imgui.IsItemHovered() && imgui.IsMouseDoubleClicked(.Left) do doc.preview = false // keep it
		if tabOpen {
			if cm.selectRequest < 0 && cm.active != i {
				cm.active = i
				cm.completion.open = false
				cm.sigOpen = false
			}
			imgui.EndTabItem()
		}
		Drive_Item(fmt.tprintf("code.tab:%s", doc.rel))
		UI_Tooltip(doc.path)
		if imgui.BeginPopupContextItem(fmt.ctprintf("##tabctx%d", i)) {
			if imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
			if imgui.MenuItem(fmt.ctprintf("%s  Save", ICON_FA_FLOPPY_DISK), nil, false, code_doc_dirty(doc)) do Code_SaveDoc(state, doc)
			if imgui.MenuItem(fmt.ctprintf("%s  Save As...", ICON_FA_FLOPPY_DISK)) {
				cm.selectRequest = i
				cm.active = i
				Prompt_Open(.SaveScriptAs, doc.rel)
			}
			imgui.Separator()
			if imgui.MenuItem(fmt.ctprintf("%s  Local History...", ICON_FA_ROTATE_LEFT)) {
				cm.selectRequest = i
				cm.active = i
				Code_CmdLocalHistory(state)
			}
			Drive_Item("ctx:local-history")
			if imgui.MenuItem(fmt.ctprintf("%s  Find Usages of This Script", ICON_FA_MAGNIFYING_GLASS)) do Asset_ShowUsages(state, doc.rel, false)
			Drive_Item("ctx:script-usages")
			imgui.Separator()
			if imgui.MenuItem(fmt.ctprintf("%s  Close", ICON_FA_XMARK), "Cmd+W") do closeIdx = i
			Drive_Item("ctx:close-tab")
			if imgui.MenuItem(fmt.ctprintf("%s  %s", ICON_FA_THUMBTACK, "Unpin Tab" if doc.pinned else "Pin Tab")) {
				doc.pinned = !doc.pinned
				doc.preview = false
			}
			Drive_Item("ctx:pin-tab")
			if doc.preview {
				if imgui.MenuItem("Keep Open") do doc.preview = false
				Drive_Item("ctx:keep-tab")
			}
			if imgui.MenuItem("Close Others", nil, false, len(cm.docs) > 1) do cm.closeOthers = i
			Drive_Item("ctx:close-others")
			if imgui.MenuItem("Close to the Right", nil, false, i < len(cm.docs) - 1) {cm.closeOthers = i; cm.closeMode = .Right}
			Drive_Item("ctx:close-right")
			if imgui.MenuItem("Close Saved") {cm.closeOthers = -2; cm.closeMode = .Saved}
			Drive_Item("ctx:close-saved")
			if imgui.MenuItem("Close All") do cm.closeOthers = -2
			imgui.Separator()
			if imgui.MenuItem(fmt.ctprintf("%s  Copy Path", ICON_FA_LINK)) do imgui.SetClipboardText(strings.clone_to_cstring(doc.rel, context.temp_allocator))
			if imgui.MenuItem(fmt.ctprintf("%s  Copy Absolute Path", ICON_FA_LINK)) do imgui.SetClipboardText(strings.clone_to_cstring(doc.path, context.temp_allocator))
			if imgui.MenuItem(fmt.ctprintf("%s  Reveal in Assets", ICON_FA_FOLDER_OPEN)) do Asset_Reveal(state, doc.rel)
			Drive_Item("ctx:tab-reveal-asset")
			if imgui.MenuItem(fmt.ctprintf("%s  Reveal in Finder", ICON_FA_FOLDER_OPEN)) do Editor_OpenExternally(state, filepath.dir(doc.path, context.temp_allocator))
			imgui.EndPopup()
		}
		if !open do closeIdx = i
	}
	cm.selectRequest = -1
	imgui.EndTabBar()
	if closeIdx >= 0 do code_request_close(closeIdx)
}

code_status_line :: proc(state: ^EditorState, doc: ^Code_Doc) {
	cm := &GlobalCode
	b := &doc.buffer
	c := b.cursors[0]
	imgui.SetCursorPosX(UI_SPACE)
	imgui.SetCursorPosY(imgui.GetCursorPosY() + 3)
	if UI_IconButton(ICON_FA_FLOPPY_DISK, "code.save", "Save (Ctrl/Cmd+S)", size = 22, tint = UI_ACCENT if code_doc_dirty(doc) else {}) {
		Code_SaveDoc(state, doc)
	}
	imgui.SameLine(0, UI_SPACE)
	imgui.AlignTextToFramePadding()
	line := buf.buffer_line_str(b, c.pos.line)
	UI_DimText(fmt.tprintf("Ln %d, Col %d", c.pos.line + 1, code_visual_col(line, c.pos.col) + 1))
	imgui.SameLine(0, UI_SPACE * 2)
	UI_DimText("Lua" if doc.isLua else doc.lang.name)
	errs, warns := code_diagnostic_counts(doc)
	imgui.SameLine(0, UI_SPACE * 2)
	imgui.PushStyleColorImVec4(.Text, UI_DANGER if errs > 0 else UI_TEXT_DIM)
	imgui.TextUnformatted(fmt.ctprintf("%s %d", ICON_FA_CIRCLE_XMARK, errs))
	imgui.PopStyleColor()
	imgui.SameLine(0, UI_SPACE)
	imgui.PushStyleColorImVec4(.Text, UI_WARNING if warns > 0 else UI_TEXT_DIM)
	imgui.TextUnformatted(fmt.ctprintf("%s %d", ICON_FA_TRIANGLE_EXCLAMATION, warns))
	imgui.PopStyleColor()
	imgui.SameLine(0, UI_SPACE * 2)
	status := ""
	col := UI_TEXT_DIM
	switch cm.lspState {
	case .Off:      status = "Language server off"
	case .Starting: status = "Starting lua-language-server…"
	case .Ready:    status = "lua-language-server"; col = UI_SUCCESS
	case .Failed:   status = cm.lspMessage if cm.lspMessage != "" else "Language server unavailable"; col = UI_WARNING
	}
	if !doc.isLua do status = ""
	imgui.PushStyleColorImVec4(.Text, col)
	imgui.TextUnformatted(fmt.ctprintf("%s %s", ICON_FA_CIRCLE if cm.lspState == .Ready else "", status))
	imgui.PopStyleColor()
}

CODE_STATUS_HEIGHT :: 30.0

// code_text_area draws the text and handles its input; returns whether it
// has keyboard focus.
code_text_area :: proc(state: ^EditorState, doc: ^Code_Doc) -> bool {
	cm := &GlobalCode
	b := &doc.buffer
	font := code_font()
	cm.lineH = code_font_size() + 5
	cm.charW = imgui.Font_CalcTextSizeA(font, code_font_size(), max(f32), 0, "M").x
	code_update_line_states(doc)

	avail := imgui.GetContentRegionAvail()
	lineCount := buf.buffer_line_count(b)
	digits := len(fmt.tprint(lineCount))
	gutterW := f32(max(digits, 3) + 2) * cm.charW + 14

	Code_DiskBanner(state, doc) // changed on disk while edited
	if doc.diskConflict do avail.y -= 32 + imgui.GetStyle().ItemSpacing.y
	if GlobalSettings.breadcrumbs {
		Code_Breadcrumbs(state, doc) // file > function > blocks (code_sticky.odin)
		avail.y -= CODE_CRUMBS_H + imgui.GetStyle().ItemSpacing.y
	}
	imgui.PushStyleColorImVec4(.ChildBg, CODE_BG)
	if cm.focusRequest {
		imgui.SetNextWindowFocus()
		cm.focusRequest = false
	}
	imgui.BeginChild("##code_area", {avail.x, max(avail.y - CODE_STATUS_HEIGHT, 50)}, {}, {.HorizontalScrollbar, .NoMove})
	imgui.PopStyleColor()
	defer imgui.EndChild()

	winPos := imgui.GetWindowPos()
	winSize := imgui.GetWindowSize()
	// The wheel over an overlay scrolls the overlay, not the code.
	@(static) lastScroll: [2]f32
	defer lastScroll = {imgui.GetScrollX(), imgui.GetScrollY()}
	if Code_OverlayHovered() && imgui.GetIO().MouseWheel != 0 {
		imgui.SetScrollX(lastScroll.x)
		imgui.SetScrollY(lastScroll.y)
	}
	if GlobalSettings.softWrap && imgui.GetScrollX() != 0 do imgui.SetScrollX(0) // wrapped: nothing to the right
	scrollX := imgui.GetScrollX()
	scrollY := imgui.GetScrollY()
	pad := f32(6)

	// Content size (for the scrollbars): the widest line, once per edit.
	if !doc.widthValid || doc.widthVersion != b.version {
		doc.maxCols = 0
		for i in 0 ..< lineCount {
			l := buf.buffer_line_str(b, i)
			doc.maxCols = max(doc.maxCols, code_visual_col(l, len(l)))
		}
		doc.widthVersion = b.version
		doc.widthValid = true
	}
	maxCols := doc.maxCols
	imgui.SetCursorPos({0, 0})
	rowCount := len(code_display(doc).rows)
	contentW := gutterW + f32(maxCols + 4) * cm.charW if !GlobalSettings.softWrap else winSize.x - 4 // soft wrap: no horizontal scroll
	imgui.Dummy({contentW, f32(rowCount) * cm.lineH + winSize.y * 0.5})

	// Input catcher covering the visible area.
	imgui.SetCursorPos({scrollX, scrollY})
	imgui.InvisibleButton("##code_input", {max(winSize.x, 1), max(winSize.y, 1)}, {.MouseButtonLeft})
	Drive_Item("code.area")
	hovered := imgui.IsItemHovered()
	active := imgui.IsItemActive()
	focused := imgui.IsWindowFocused()
	code_drop_target(state, doc, {imgui.GetIO().MousePos.x, imgui.GetIO().MousePos.y})
	Code_NodeDropMenu(state, doc) // a node dropped onto a method: its events
	Debug_ConditionPopup()        // right-click in the gutter: a breakpoint condition
	Code_ClipboardPicker(state, doc) // Cmd+Shift+V
	Code_GutterMenu(state, doc)      // right-click a line number
	Code_PeekRender(state)           // peek definition / references
	Code_ActionsRender(state, doc)   // Cmd+. fixes
	Code_SwatchPicker(doc)           // a clicked colour swatch
	// Right-click: the text menu - in the gutter, a breakpoint condition instead.
	if hovered && imgui.IsMouseReleased(.Right) && imgui.GetIO().MousePos.x >= winPos.x + gutterW {
		Code_ContextOpen(state, doc, code_pos_at(b, {imgui.GetIO().MousePos.x, imgui.GetIO().MousePos.y}))
		imgui.OpenPopup("##code_ctx")
	}
	if imgui.BeginPopup("##code_ctx") {
		code_text_context_menu(state, doc)
		imgui.EndPopup()
	}

	cm.textOrigin = {winPos.x + gutterW + pad - scrollX, winPos.y + pad - scrollY}
	cm.areaMin = {winPos.x, winPos.y}
	cm.areaMax = {winPos.x + winSize.x, winPos.y + winSize.y}

	io := imgui.GetIO()
	mouse := [2]f32{io.MousePos.x, io.MousePos.y}
	inPopup := cm.completion.open && point_in_rect(mouse, cm.popupMin, cm.popupMax)
	overBulb := cm.bulbMax.x > 0 && point_in_rect(mouse, cm.bulbMin, cm.bulbMax)
	overOverlay := Code_OverlayHovered() || Code_OverviewHovered(winPos, winSize) || Code_StickyHovered(winPos, winSize) || overBulb // boxes / strip / pinned lines / lightbulb: no clicks through

	// Mouse: click places the caret (Shift extends), double-click selects a
	// word, triple-click the line, drag selects.
	if hovered && !inPopup && !overOverlay {
		imgui.SetMouseCursor(.TextInput)
		if imgui.IsMouseClicked(.Left) {
			p := code_pos_at(b, mouse)
			clicks := imgui.GetMouseClickedCount(.Left)
			switch {
			case clicks == 2:
				code_set_single_cursor(b, p, false)
				buf.cursor_select_word(b, &b.cursors[0])
			case clicks >= 3:
				code_set_single_cursor(b, p, false)
				buf.cursor_select_line(b, &b.cursors[0])
			case io.KeyAlt:
				// Alt-click adds a cursor (or removes one already there);
				// Alt-drag from here makes a column selection.
				code_cursor_history_push(doc)
				cm.columnFrom = mouse
				removed := false
				if len(b.cursors) > 1 {
					for c, i in b.cursors {
						if c.pos == p {ordered_remove(&b.cursors, i); removed = true; break}
					}
				}
				if !removed do append(&b.cursors, buf.Cursor{pos = p})
			case:
				code_set_single_cursor(b, p, io.KeyShift)
			}
			cm.completion.open = false
			cm.sigOpen = false
			cm.cursorMoved = time.tick_now()
			// Cmd+click: a node path (get_node / find_node / get_child) selects
			// the node; anything else goes to its definition.
			if code_primary_down() && clicks == 1 && !Code_GotoNode(state, doc, p) do code_lsp_goto_definition(doc)
		}
	}
	if active && imgui.IsMouseDragging(.Left) && imgui.GetMouseClickedCount(.Left) <= 1 && !io.KeyAlt {
		p := code_pos_at(b, mouse)
		code_set_single_cursor(b, p, true)
		doc.scrollToCursor = true
	}
	if active && imgui.IsMouseDragging(.Left, 4) && io.KeyAlt {
		code_column_select(doc, cm.columnFrom, mouse) // box selection (code_multicursor.odin)
	}

	if focused do code_handle_keys(state, doc)

	// Hover (diagnostics + LSP hover) after the mouse rests on text.
	code_hover(doc, hovered && !inPopup && !active, mouse)

	if doc.scrollToCursor {
		doc.scrollToCursor = false
		c := code_primary(b).pos
		y := f32(code_row_of(doc, c)) * cm.lineH
		pinned := cm.stickyH if GlobalSettings.stickyScroll else 0
		if doc.scrollToTop {
			// A pinned line / breadcrumb was clicked: its line just below the pins.
			doc.scrollToTop = false
			imgui.SetScrollY(max(y - f32(len(code_sticky_lines(doc, c.line))) * cm.lineH, 0))
		} else if y < scrollY + pinned do imgui.SetScrollY(max(y - pinned, 0))
		else if y + cm.lineH * 2 > scrollY + winSize.y do imgui.SetScrollY(y + cm.lineH * 2 - winSize.y)
		x := code_screen_pos(b, c).x - cm.textOrigin.x
		textW := winSize.x - gutterW - pad * 2
		if GlobalSettings.softWrap {
		} else if x < scrollX {
			imgui.SetScrollX(max(x - cm.charW * 4, 0))
		} else if x > scrollX + textW - cm.charW * 2 {
			imgui.SetScrollX(x - textW + cm.charW * 6)
		}
	}

	code_draw(doc, winPos, winSize, gutterW, focused)
	return focused
}

// code_real_path: a path with its symlinks resolved ("" when it doesn't exist).
code_real_path :: proc(path: string) -> string {
	when ODIN_OS == .Windows {
		return path
	} else {
		out: [4096]u8
		r := posix.realpath(strings.clone_to_cstring(path, context.temp_allocator), &out[0])
		if r == nil do return ""
		return strings.clone(string(r), context.temp_allocator)
	}
}

// code_state: the editor state (drawing code that has none passed in).
code_state :: proc() -> ^EditorState {return &GlobalEditor}

// code_doc_of: the open doc owning a buffer.
code_doc_of :: proc(b: ^buf.Buffer) -> ^Code_Doc {
	for d in GlobalCode.docs do if &d.buffer == b do return d
	return nil
}

// code_pos_at maps a screen position to a buffer position (through the
// display map: folds, soft wrap).
code_pos_at :: proc(b: ^buf.Buffer, screen: [2]f32) -> buf.Position {
	cm := &GlobalCode
	doc := code_doc_of(b)
	vcol := int((screen.x - cm.textOrigin.x) / cm.charW + 0.5)
	if doc == nil {
		line := clamp(int((screen.y - cm.textOrigin.y) / cm.lineH), 0, buf.buffer_line_count(b) - 1)
		return {line, code_byte_col(buf.buffer_line_str(b, line), max(vcol, 0))}
	}
	d := code_display(doc)
	r := int((screen.y - cm.textOrigin.y) / cm.lineH)
	if screen.y < cm.textOrigin.y do r = 0
	r = clamp(r, 0, len(d.rows) - 1)
	row := d.rows[r]
	return {row.line, code_row_col(buf.buffer_line_str(b, row.line), row, max(vcol, 0), code_inlays(doc, row.line))}
}

// code_screen_pos: top-left of the cell at a buffer position.
code_screen_pos :: proc(b: ^buf.Buffer, p: buf.Position) -> [2]f32 {
	cm := &GlobalCode
	line := buf.buffer_line_str(b, p.line)
	doc := code_doc_of(b)
	if doc == nil do return {cm.textOrigin.x + f32(code_visual_col(line, p.col)) * cm.charW, cm.textOrigin.y + f32(p.line) * cm.lineH}
	d := code_display(doc)
	r := code_row_of(doc, p)
	row := d.rows[r]
	x := code_row_x(line, row, p.col, code_inlays(doc, p.line)) if row.line == p.line else code_visual_col(buf.buffer_line_str(b, row.line), len(buf.buffer_line_str(b, row.line)))
	return {cm.textOrigin.x + f32(x) * cm.charW, cm.textOrigin.y + f32(r) * cm.lineH}
}

code_draw :: proc(doc: ^Code_Doc, winPos, winSize: imgui.Vec2, gutterW: f32, focused: bool) {
	cm := &GlobalCode
	b := &doc.buffer
	code_update_line_states(doc) // keys may have edited the text this frame
	code_folds_follow(doc)       // folds stay on their lines through edits
	dl := imgui.GetWindowDrawList()
	lineCount := buf.buffer_line_count(b)
	// Rows on screen (code_display.odin: folds and soft wrap).
	disp := code_display(doc)
	firstRow := clamp(int((winPos.y - cm.textOrigin.y) / cm.lineH), 0, len(disp.rows) - 1)
	lastRow := min(firstRow + int(winSize.y / cm.lineH) + 2, len(disp.rows) - 1)
	first := disp.rows[firstRow].line
	last := disp.rows[lastRow].line
	c := code_primary(b)^
	_, _, hasSel := buf.selection_range(c)
	textX := cm.textOrigin.x
	findAll: []Code_Match
	if cm.find.open do findAll = code_find_all(doc)[:]
	findMatches := make([dynamic]Code_Match, context.temp_allocator)
	for m in findAll do if m.start.line >= first && m.start.line <= last do append(&findMatches, m)
	textY := (cm.lineH - code_font_size()) * 0.5

	diags := code_diagnostics(doc)

	// Structure for rainbow brackets, bracket matching, indent guides
	// (code_structure.odin: computed once per edit).
	st := code_structure(doc)
	mi := code_marks_from(st, first)
	tab := code_tab_width()
	activeLevel, activeFrom, activeTo := -1, 0, -1
	if GlobalSettings.indentGuides {
		if bl, ok := code_block_at(doc, c.pos.line); ok && bl.end > bl.start + 1 {
			activeLevel = code_line_indent(buf.buffer_line_str(b, bl.start), tab) / max(tab, 1)
			activeFrom, activeTo = bl.start + 1, bl.end - 1
		}
	}
	blankIndent, blankFor := 0, -1 // indentation of the next code line (blank lines)
	symRanges := code_symbol_occurrences(doc, first, last) if !hasSel else nil // same word as the caret's
	// Inline values while the debugger is paused in this file: lines of the
	// paused function up to the paused line.
	inlineFn: Code_Block
	inlineStop := -1
	inlineLocals: [][3]string
	if file, line, locals, ok := Debug_InlineInfo(); ok && file == doc.rel {
		for bl in code_blocks_around(doc, line - 1) do if bl.kind == .Function do inlineFn = bl
		inlineStop, inlineLocals = line - 1, locals
	}
	showWs := GlobalSettings.showWhitespace

	lastMarkLine := -1
	lineMarks: []Code_Bracket_Mark
	for r in firstRow ..= lastRow {
		row := disp.rows[r]
		ln := row.line
		y := cm.textOrigin.y + f32(r) * cm.lineH
		text := buf.buffer_line_str(b, ln)
		rowEnd := row.to if row.to < len(text) else len(text)
		lastRowOfLine := r + 1 >= len(disp.rows) || disp.rows[r + 1].line != ln
		hints := code_inlays(doc, ln) // parameter-name hints (code_inlay.odin)
		// x of a byte column on this row.
		xof :: proc(textX: f32, text: string, row: Display_Row, col: int, hints: []Code_Inlay) -> f32 {
			return textX + f32(code_row_x(text, row, col, hints)) * GlobalCode.charW
		}
		// This line's bracket marks.
		if ln != lastMarkLine {
			for mi < len(st.marks) && st.marks[mi].pos.line < ln do mi += 1
			lm := mi
			for k := mi; k < len(st.marks) && st.marks[k].pos.line == ln; k += 1 do lm = k + 1
			lineMarks = st.marks[mi:lm] if GlobalSettings.rainbowBrackets else nil
			lastMarkLine = ln
		}

		// Indent guides: a line per indentation level (blank lines take the
		// next code line's); the caret's block is brighter.
		if GlobalSettings.indentGuides && tab > 0 && row.from == 0 {
			ind := 0
			if strings.trim_space(text) == "" {
				if blankFor < ln {
					blankIndent, blankFor = 0, ln
					for k in ln + 1 ..< min(lineCount, ln + 200) {
						t := buf.buffer_line_str(b, k)
						if strings.trim_space(t) != "" {blankIndent, blankFor = code_line_indent(t, tab), k - 1; break}
					}
				}
				ind = blankIndent
			} else {
				ind = code_line_indent(text, tab)
			}
			for lv in 0 ..< ind / tab {
				x := textX + f32(lv * tab) * cm.charW + 1
				bright := lv == activeLevel && ln >= activeFrom && ln <= activeTo
				imgui.DrawList_AddLine(dl, {x, y}, {x, y + cm.lineH}, col_u32(ui_line(0.16 if bright else 0.06)))
			}
		}

		// Current line / selection backgrounds.
		if !hasSel && ln == c.pos.line && focused {
			imgui.DrawList_AddRectFilled(dl, {winPos.x, y}, {winPos.x + winSize.x, y + cm.lineH}, col_u32(ui_line(0.035)))
		}
		// Find matches and the caret word's other occurrences.
		hl :: proc(dl: ^imgui.DrawList, textX, y: f32, text: string, row: Display_Row, rowEnd: int, s, e: int, color: u32, hints: []Code_Inlay) {
			s, e := max(s, row.from), min(e, rowEnd)
			if e <= s && !(s == e && s == row.from) do return
			x0 := textX + f32(code_row_x(text, row, s, hints)) * GlobalCode.charW
			x1 := textX + f32(code_row_x(text, row, e, hints)) * GlobalCode.charW
			imgui.DrawList_AddRectFilled(dl, {x0, y + 1}, {max(x1, x0 + GlobalCode.charW), y + GlobalCode.lineH - 1}, color, 2)
		}
		for m in findMatches {
			if m.start.line != ln do continue
			hl(dl, textX, y, text, row, rowEnd, m.start.col, m.end.col, col_u32({0.961, 0.722, 0.298, 0.28}), hints)
		}
		for sr in symRanges {
			if sr.line != ln do continue
			hl(dl, textX, y, text, row, rowEnd, sr.from, sr.to, col_u32(ui_line(0.10)), hints)
		}
		for cur in b.cursors {
			selStart, selEnd, curSel := buf.selection_range(cur)
			if !curSel || ln < selStart.line || ln > selEnd.line do continue
			s := selStart.col if ln == selStart.line else 0
			e := selEnd.col if ln == selEnd.line else len(text)
			s, e = max(s, row.from), min(e, rowEnd)
			if e < s do continue
			x0 := xof(textX, text, row, s, hints)
			x1 := xof(textX, text, row, e, hints)
			if ln != selEnd.line && lastRowOfLine && e == len(text) do x1 += cm.charW // the newline
			if x1 > x0 || (ln != selEnd.line && lastRowOfLine) {
				imgui.DrawList_AddRectFilled(dl, {x0, y}, {max(x1, x0 + 1), y + cm.lineH}, col_u32(ui_accent(0.30)))
			}
		}

		// Syntax-colored text (this row's part of the line).
		tokens, _ := Token_CacheGet(&doc.tokens, doc.lang, text, doc.lineStates[ln], b.version)
		v := row.indent
		at := row.from
		hi := 0
		for hi < len(hints) && hints[hi].col < row.from do hi += 1
		// seg draws text[s:e] in color with the hints that sit inside it.
		seg :: proc(dl: ^imgui.DrawList, x0, y: f32, v: int, text: string, s, e: int, color: u32, marks: []Code_Bracket_Mark, hints: []Code_Inlay, hi: ^int, doc: ^Code_Doc, ln: int) -> int {
			v, pos := v, s
			for hi^ < len(hints) && hints[hi^].col < e {
				h := hints[hi^]
				if h.col > pos do v = code_draw_marked(dl, x0, y, v, text, pos, h.col, color, marks)
				v = code_draw_inlay(dl, x0, y, v, h, doc, ln)
				pos = max(pos, h.col)
				hi^ += 1
			}
			if pos < e do v = code_draw_marked(dl, x0, y, v, text, pos, e, color, marks)
			return v
		}
		for t in tokens {
			ts, te := max(t.start, row.from), min(t.end, rowEnd)
			if te <= ts do continue
			if ts > at do v = seg(dl, textX, y + textY, v, text, at, ts, col_u32(UI_TEXT), lineMarks, hints, &hi, doc, ln)
			v = seg(dl, textX, y + textY, v, text, ts, te, code_token_color(t.kind), lineMarks, hints, &hi, doc, ln)
			at = te
		}
		if at < rowEnd do v = seg(dl, textX, y + textY, v, text, at, rowEnd, col_u32(UI_TEXT), lineMarks, hints, &hi, doc, ln)
		for hi < len(hints) && hints[hi].col <= rowEnd && lastRowOfLine {
			v = code_draw_inlay(dl, textX, y + textY, v, hints[hi], doc, ln)
			hi += 1
		}

		// Whitespace: dots for spaces, arrows for tabs (in selections, or all).
		if showWs != .None {
			for i in row.from ..< rowEnd {
				ch := text[i]
				if ch != ' ' && ch != '\t' do continue
				if showWs == .Selection && !code_in_selection(b, {ln, i}) do continue
				x := xof(textX, text, row, i, hints)
				cy := y + cm.lineH * 0.5
				if ch == ' ' {
					imgui.DrawList_AddCircleFilled(dl, {x + cm.charW * 0.5, cy}, 1.2, col_u32(ui_line(0.22)))
				} else {
					imgui.DrawList_AddLine(dl, {x + 2, cy}, {x + cm.charW * f32(tab) - 3, cy}, col_u32(ui_line(0.22)))
				}
			}
		}
		// While paused here: the values of the locals this line uses (code_debug).
		if lastRowOfLine && inlineFn.end > 0 && ln >= inlineFn.start && ln <= inlineStop {
			code_draw_inline_values(dl, xof(textX, text, row, len(text), hints) + cm.charW * 2, y + textY, text, tokens, inlineLocals)
		}
		// A folded block: a chip after its first line (click to unfold).
		if lastRowOfLine {
			if end, folded := code_fold_end(doc, ln); folded {
				x := xof(textX, text, row, len(text), hints) + cm.charW
				label := fmt.ctprintf(" … %d lines ", end - ln - 1)
				w := imgui.CalcTextSize(label).x
				mn, mx := [2]f32{x, y + 2}, [2]f32{x + w, y + cm.lineH - 2}
				imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32(ui_line(0.10)), 4)
				imgui.DrawList_AddText(dl, {x, y + (cm.lineH - imgui.GetFontSize()) * 0.5}, col_u32(UI_TEXT_DIM), label)
				Drive_ItemRect(fmt.tprintf("code.fold-chip:%d", ln + 1), mn, mx, inWindow = true)
				io := imgui.GetIO()
				if imgui.IsWindowHovered(imgui.HoveredFlags_AllowWhenBlockedByActiveItem) && point_in_rect({io.MousePos.x, io.MousePos.y}, mn, mx) {
					imgui.SetMouseCursor(.Hand)
					if imgui.IsMouseClicked(.Left) do code_fold_toggle(doc, ln)
				}
			}
		}
	}

	// The bracket pair at the caret.
	if !hasSel {
		if br, ok := code_bracket_at(doc, c.pos); ok {
			for q in ([2]buf.Position{br.open, br.close}) {
				qr := code_row_of(doc, q)
				if qr < firstRow || qr > lastRow || disp.rows[qr].line != q.line do continue
				p := code_screen_pos(b, q)
				imgui.DrawList_AddRect(dl, {p.x - 0.5, p.y + 1}, {p.x + cm.charW + 0.5, p.y + cm.lineH - 1}, col_u32(ui_line(0.45)), 2)
			}
		}
	}

	// Diagnostic squiggles (per row they cover).
	for d in diags {
		sl := d.range.start.line
		el := d.range.end.line
		if el < first || sl > last || sl >= lineCount do continue
		color := code_severity_color(d.severity)
		for ln in max(sl, first) ..= min(el, last, lineCount - 1) {
			text := buf.buffer_line_str(b, ln)
			from := code_byte_from_u16(text, d.range.start.character) if ln == sl else 0
			to := code_byte_from_u16(text, d.range.end.character) if ln == el else len(text)
			for r := code_row_of(doc, {ln, from}); r <= lastRow && r < len(disp.rows) && disp.rows[r].line == ln; r += 1 {
				row := disp.rows[r]
				s, e := max(from, row.from), min(to, row.to)
				if e < s || (s == e && from != to && s == row.to && row.to < len(text)) do continue
				vf := code_row_x(text, row, s, code_inlays(doc, ln))
				vt := code_row_x(text, row, e, code_inlays(doc, ln))
				if vt <= vf do vt = vf + 1
				y := cm.textOrigin.y + f32(r + 1) * cm.lineH - 2
				code_squiggle(dl, textX + f32(vf) * cm.charW, textX + f32(vt) * cm.charW, y, color, d.unnecessary)
				if row.to >= to do break
			}
		}
	}

	// Overview strip at the right (code_minimap.odin).
	{
		views := make([dynamic]Code_Diag_View, context.temp_allocator)
		for d in diags do append(&views, Code_Diag_View{d.range.start.line, code_severity_color(d.severity)})
		code_overview(nil, doc, winPos, winSize, findAll, views[:])
	}

	// Carets (blink while idle).
	if len(b.cursors) > 0 {
		cp := code_screen_pos(b, b.cursors[0].pos)
		Drive_ItemRect("code.caret", {cp.x, cp.y}, {cp.x + cm.charW, cp.y + cm.lineH}, inWindow = true)
	}
	if focused {
		blink := time.duration_seconds(time.tick_since(cm.cursorMoved))
		if blink < 0.6 || int(blink * 1.8) % 2 == 0 {
			for cur in b.cursors {
				p := code_screen_pos(b, cur.pos)
				imgui.DrawList_AddRectFilled(dl, {p.x, p.y + 1}, {p.x + 2, p.y + cm.lineH - 1}, col_u32(UI_ACCENT))
			}
		}
	}

	// Gutter (fixed while scrolling horizontally): line numbers + markers.
	imgui.DrawList_AddRectFilled(dl, {winPos.x, winPos.y}, {winPos.x + gutterW, winPos.y + winSize.y}, col_u32(CODE_BG))
	worst := make(map[int]int, 16, context.temp_allocator)
	for d in diags {
		sev := d.severity if d.severity > 0 else 1
		if old, ok := worst[d.range.start.line]; !ok || sev < old do worst[d.range.start.line] = sev
	}
	font := code_font()
	gutterMouse := [2]f32{imgui.GetIO().MousePos.x, imgui.GetIO().MousePos.y}
	prevBulbMin, prevBulbMax := cm.bulbMin, cm.bulbMax
	cm.bulbMin, cm.bulbMax = {}, {}
	for r in firstRow ..= lastRow {
		row := disp.rows[r]
		ln := row.line
		rowMin := [2]f32{winPos.x, cm.textOrigin.y + f32(r) * cm.lineH}
		rowMax := [2]f32{winPos.x + gutterW, rowMin.y + cm.lineH}
		y := rowMin.y + textY
		if row.from > 0 {
			// A wrapped line's continuation row: a small hook, no number.
			hx, hy := winPos.x + gutterW - 24, rowMin.y + cm.lineH * 0.3
			imgui.DrawList_AddLine(dl, {hx, hy}, {hx, hy + cm.lineH * 0.35}, col_u32(UI_TEXT_FAINT))
			imgui.DrawList_AddLine(dl, {hx, hy + cm.lineH * 0.35}, {hx + 6, hy + cm.lineH * 0.35}, col_u32(UI_TEXT_FAINT))
			continue
		}
		num := fmt.ctprintf("%d", ln + 1)
		w := imgui.Font_CalcTextSizeA(font, code_font_size(), max(f32), 0, num).x
		color := col_u32(UI_TEXT_DIM if ln == c.pos.line else UI_TEXT_FAINT)
		imgui.DrawList_AddTextImFontPtr(dl, font, code_font_size(), {winPos.x + gutterW - 18 - w, y}, color, num)
		// A lightbulb on the caret's line when there is something to fix (Cmd+.).
		if ln == c.pos.line && Code_LightbulbAt(code_state(), doc, ln) {
			bx := winPos.x + 2
			imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.regular, code_font_size() - 2, {bx, y}, col_u32(UI_WARNING), ICON_FA_LIGHTBULB)
			bmx := [2]f32{bx + 14, rowMax.y}
			Drive_ItemRect("code.lightbulb", rowMin, bmx, inWindow = true)
			cm.bulbMin, cm.bulbMax = rowMin, bmx // clicks here are the bulb's, not the gutter's / text's
			if point_in_rect(gutterMouse, rowMin, bmx) && imgui.IsWindowHovered(imgui.HoveredFlags_AllowWhenBlockedByActiveItem) {
				UI_Tooltip("Code actions (Cmd+.)")
				if imgui.IsMouseClicked(.Left) do Code_CmdCodeActions(code_state())
			}
		}
		// Changes since the last commit (code_git.odin): a bar at the gutter's edge.
		if gc, changed := code_git_change_at(doc, ln); changed {
			gx := winPos.x + gutterW - 3
			if gc == CHANGE_DELETED {
				imgui.DrawList_AddTriangleFilled(dl, {gx - 2, rowMin.y - 3}, {gx - 2, rowMin.y + 3}, {gx + 3, rowMin.y}, col_u32(gc))
			} else {
				imgui.DrawList_AddRectFilled(dl, {gx, rowMin.y}, {gx + 3, rowMax.y}, col_u32(gc))
			}
		}
		// Fold arrow (code_fold.odin): shown on hover or when folded.
		code_gutter_fold(doc, ln, {winPos.x + gutterW - 14, rowMin.y}, cm.lineH, gutterMouse, point_in_rect(gutterMouse, {winPos.x, winPos.y}, {winPos.x + gutterW, winPos.y + winSize.y}))
		// Breakpoints (click the gutter) and where the game is paused.
		Drive_ItemRect(fmt.tprintf("code.gutter:%d", ln + 1), rowMin, rowMax, inWindow = true)
		numArea := [2]f32{winPos.x + gutterW - 16, rowMax.y} // the fold arrow's column is its own
		if doc.isLua && imgui.IsWindowHovered(imgui.HoveredFlags_AllowWhenBlockedByActiveItem) && point_in_rect(gutterMouse, rowMin, numArea) && !(prevBulbMax.x > 0 && point_in_rect(gutterMouse, prevBulbMin, prevBulbMax)) {
			if imgui.IsMouseClicked(.Left) do Debug_ToggleBreakpoint(doc.rel, ln + 1)
			if imgui.IsMouseClicked(.Right) do Code_GutterMenuOpen(ln + 1) // breakpoint / condition / run to here
			if cond := Debug_Condition(doc.rel, ln + 1); cond != "" do UI_Tooltip(fmt.tprintf("Stops when: %s (right-click to edit)", cond))
		}
		if Debug_HasBreakpoint(doc.rel, ln + 1) {
			conditional := Debug_Condition(doc.rel, ln + 1) != ""
			center := [2]f32{winPos.x + 9, y + code_font_size() * 0.5}
			imgui.DrawList_AddCircleFilled(dl, center, 5, col_u32({0.96, 0.62, 0.22, 1} if conditional else {0.92, 0.30, 0.29, 1}))
			if conditional do imgui.DrawList_AddRectFilled(dl, center - {2.5, 0.75}, center + {2.5, 0.75}, col_u32({0.10, 0.08, 0.06, 1})) // "=" mark
		}
		if Debug_CurrentLine(doc.rel) == ln + 1 {
			imgui.DrawList_AddRectFilled(dl, {winPos.x + gutterW, rowMin.y}, {winPos.x + winSize.x, rowMax.y}, col_u32({0.96, 0.72, 0.30, 0.16}))
			imgui.DrawList_AddTriangleFilled(dl, {winPos.x + 3, y + 2}, {winPos.x + 3, y + code_font_size() - 2}, {winPos.x + 13, y + code_font_size() * 0.5}, col_u32(UI_WARNING))
		}
		if sev, ok := worst[ln]; ok {
			imgui.DrawList_AddCircleFilled(dl, {winPos.x + 8, y + code_font_size() * 0.5}, 3.5, code_severity_color(sev))
		}
	}
	// Pinned block headers (sticky scroll) over the top.
	cm.stickyH = 0
	code_draw_sticky(doc, winPos, winSize, gutterW, firstRow)
}

code_squiggle :: proc(dl: ^imgui.DrawList, x0, x1, y: f32, color: u32, faint: bool) {
	if faint {
		imgui.DrawList_AddLine(dl, {x0, y + 1}, {x1, y + 1}, color & 0x80FFFFFF, 1)
		return
	}
	step := f32(3)
	x := x0
	up := true
	for x < x1 {
		nx := min(x + step, x1)
		imgui.DrawList_AddLine(dl, {x, y + (0 if up else 2)}, {nx, y + (2 if up else 0)}, color, 1.2)
		x = nx
		up = !up
	}
}

code_severity_color :: proc(sev: int) -> u32 {
	switch sev {
	case 2: return col_u32(UI_WARNING)
	case 3: return col_u32(UI_ACCENT)
	case 4: return col_u32(UI_TEXT_FAINT)
	}
	return col_u32(UI_DANGER)
}

// --- keyboard ----------------------------------------------------------------------
// Commands (save, undo, clipboard, find, multi-cursor, ...) are actions in
// actions.odin, dispatched before this runs; this handles caret movement,
// editing keys and typed text (with auto-closing pairs).

code_primary_down :: proc() -> bool {
	return imgui.IsKeyDown(.LeftCtrl) || imgui.IsKeyDown(.RightCtrl) || imgui.IsKeyDown(.LeftSuper) || imgui.IsKeyDown(.RightSuper)
}

code_pressed :: proc(k: imgui.Key) -> bool {
	return imgui.IsKeyPressed(k, true)
}

// code_merge_cursors sorts cursors and drops ones at the same position.
code_merge_cursors :: proc(b: ^buf.Buffer) {
	if len(b.cursors) <= 1 do return
	primary := b.cursors[len(b.cursors) - 1].pos
	slice.sort_by(b.cursors[:], proc(x, y: buf.Cursor) -> bool {return buf.position_less(x.pos, y.pos)})
	out := 0
	for i in 0 ..< len(b.cursors) {
		if out > 0 && b.cursors[out - 1].pos == b.cursors[i].pos do continue
		b.cursors[out] = b.cursors[i]
		out += 1
	}
	resize(&b.cursors, out)
	// Keep the most recent cursor last (it's the "primary" for scrolling).
	for c, i in b.cursors {
		if c.pos == primary {
			b.cursors[i], b.cursors[len(b.cursors) - 1] = b.cursors[len(b.cursors) - 1], b.cursors[i]
			break
		}
	}
}

// code_primary: the cursor that drives scrolling / status (last added).
code_primary :: proc(b: ^buf.Buffer) -> ^buf.Cursor {
	return &b.cursors[len(b.cursors) - 1]
}

code_handle_keys :: proc(state: ^EditorState, doc: ^Code_Doc) {
	cm := &GlobalCode
	b := &doc.buffer
	io := imgui.GetIO()
	shift := io.KeyShift
	alt := imgui.IsKeyDown(.LeftAlt) || imgui.IsKeyDown(.RightAlt)
	primary := code_primary_down()
	ctrl := Keys_PhysicalCtrl()
	cmd := Keys_Primary() // Cmd on macOS (ImGui swaps Cmd/Ctrl there)
	// macOS: Alt moves by word, Cmd to line/document ends. Elsewhere Ctrl
	// moves by word.
	wordMod := alt if ODIN_OS == .Darwin else ctrl
	lineMod := cmd if ODIN_OS == .Darwin else false
	versionBefore := b.version
	moved := false
	comp := &cm.completion

	// Completion popup navigation takes priority.
	if comp.open && len(comp.filtered) > 0 {
		switch {
		case code_pressed(.DownArrow) && !alt && !primary:
			comp.selected = (comp.selected + 1) % len(comp.filtered); comp.scrollTo = true; return
		case code_pressed(.UpArrow) && !alt && !primary:
			comp.selected = (comp.selected - 1 + len(comp.filtered)) % len(comp.filtered); comp.scrollTo = true; return
		case code_pressed(.PageDown):
			comp.selected = min(comp.selected + 8, len(comp.filtered) - 1); comp.scrollTo = true; return
		case code_pressed(.PageUp):
			comp.selected = max(comp.selected - 8, 0); comp.scrollTo = true; return
		case imgui.IsKeyPressed(.Tab, false) && !primary && !shift && Code_ExpandSnippet(doc):
			return // a snippet's name: Tab expands it (Enter still picks the item)
		case (imgui.IsKeyPressed(.Enter, false) || imgui.IsKeyPressed(.KeypadEnter, false) || imgui.IsKeyPressed(.Tab, false)) && !primary:
			code_accept_completion(doc)
			return
		}
	}
	if imgui.IsKeyPressed(.Escape, false) {
		code_snippet_clear()
		switch {
		case comp.open || cm.sigOpen:
			comp.open = false
			cm.sigOpen = false
		case cm.find.open:
			cm.find.open = false
		case len(b.cursors) > 1:
			p := code_primary(b).pos
			code_set_single_cursor(b, p, false)
		case:
			code_set_single_cursor(b, b.cursors[0].pos, false)
		}
		return
	}

	// Plain movement / editing keys (modified chords are actions).
	{
		switch {
		case code_pressed(.LeftArrow) && !(alt && primary) && !code_expand_chord(ctrl, alt, shift):
			if !shift && !wordMod && !lineMod && code_collapse_selections(b, true) {
			} else if lineMod {
				for &cur in b.cursors do code_smart_home(b, &cur, shift)
			} else if wordMod {
				for &cur in b.cursors do buf.cursor_move_word_left(b, &cur, shift)
			} else {
				for &cur in b.cursors do buf.cursor_move_left(b, &cur, shift)
			}
			moved = true
		case code_pressed(.RightArrow) && !(alt && primary) && !code_expand_chord(ctrl, alt, shift):
			if !shift && !wordMod && !lineMod && code_collapse_selections(b, false) {
			} else if lineMod {
				for &cur in b.cursors do buf.cursor_move_line_end(b, &cur, shift)
			} else if wordMod {
				for &cur in b.cursors do buf.cursor_move_word_right(b, &cur, shift)
			} else {
				for &cur in b.cursors do buf.cursor_move_right(b, &cur, shift)
			}
			moved = true
		case code_pressed(.UpArrow) && !alt:
			if lineMod do for &cur in b.cursors do buf.cursor_move_doc_start(b, &cur, shift)
			else do for &cur in b.cursors do code_display_move(doc, &cur, -1, shift) // rows: folds, wrap
			moved = true
		case code_pressed(.DownArrow) && !alt:
			if lineMod do for &cur in b.cursors do buf.cursor_move_doc_end(b, &cur, shift)
			else do for &cur in b.cursors do code_display_move(doc, &cur, 1, shift)
			moved = true
		case code_pressed(.Home):
			if primary do for &cur in b.cursors do buf.cursor_move_doc_start(b, &cur, shift)
			else do for &cur in b.cursors do code_smart_home(b, &cur, shift)
			moved = true
		case code_pressed(.End):
			if primary do for &cur in b.cursors do buf.cursor_move_doc_end(b, &cur, shift)
			else do for &cur in b.cursors do buf.cursor_move_line_end(b, &cur, shift)
			moved = true
		case code_pressed(.PageUp), code_pressed(.PageDown):
			lines := max(int((cm.areaMax.y - cm.areaMin.y) / cm.lineH) - 2, 1)
			if imgui.IsKeyDown(.PageUp) do lines = -lines
			for &cur in b.cursors do code_display_move(doc, &cur, lines, shift)
			moved = true
		case code_pressed(.Backspace) && !primary:
			if !wordMod && GlobalSettings.autoClosePairs && code_delete_pair(b) {
			} else {
				buf.buffer_backspace(b, wordMod)
			}
			moved = true
		case code_pressed(.Delete):
			buf.buffer_delete_forward(b, wordMod)
			moved = true
		case (code_pressed(.Enter) || code_pressed(.KeypadEnter)) && !primary:
			code_newline(doc)
			moved = true
		case code_pressed(.Tab) && !ctrl && !primary && !shift && Code_SnippetNext(doc):
		case code_pressed(.Tab) && !ctrl && !primary && !shift && Code_ExpandSnippet(doc):
		case code_pressed(.Tab) && !ctrl && !primary:
			if shift do buf.buffer_outdent(b)
			else do buf.buffer_indent(b, doc.useTabs)
			moved = true
		}
	}

	// Typed characters.
	typed := ""
	if !primary || alt {
		q := io.InputQueueCharacters
		if q.Size > 0 {
			sb := strings.builder_make(context.temp_allocator)
			chars := ([^]imgui.Wchar)(q.Data)[:q.Size]
			for c in chars {
				r := rune(c)
				if r < 32 || r == 127 do continue
				strings.write_rune(&sb, r)
			}
			typed = strings.to_string(sb)
		}
	}
	if typed != "" {
		if len(typed) == 1 && GlobalSettings.autoClosePairs && code_auto_pair(doc, typed[0]) {
		} else {
			buf.buffer_type_text(b, typed)
		}
		moved = true
	}

	if moved {
		code_merge_cursors(b)
		cm.cursorMoved = time.tick_now()
		doc.scrollToCursor = true
	}
	code_after_edit(doc, typed, b.version != versionBefore)
}

// code_collapse_selections: Left/Right with selections collapse them to
// their start/end. Returns false when nothing was selected.
code_collapse_selections :: proc(b: ^buf.Buffer, toStart: bool) -> bool {
	any := false
	for &c in b.cursors {
		if s, e_, ok := buf.selection_range(c); ok {
			c.pos = s if toStart else e_
			c.sel.active = false
			any = true
		}
	}
	return any
}

// code_smart_home: first non-blank column, or column 0 when already there.
code_smart_home :: proc(b: ^buf.Buffer, c: ^buf.Cursor, extend: bool) {
	line := buf.buffer_line_str(b, c.pos.line)
	first := 0
	for first < len(line) && (line[first] == ' ' || line[first] == '\t') do first += 1
	target := first if c.pos.col != first else 0
	if extend {
		if !c.sel.active do c.sel = {anchor = c.pos, active = true}
	} else {
		c.sel.active = false
	}
	c.pos.col = target
	c.has_goal = false
}

CODE_PAIRS := [?][2]u8{{'(', ')'}, {'[', ']'}, {'{', '}'}, {'"', '"'}, {'\'', '\''}}

// code_auto_pair handles a single typed character: wraps selections in
// brackets/quotes, inserts the closing character, or steps over a closer
// that is already there. Returns false to type the character normally.
code_auto_pair :: proc(doc: ^Code_Doc, ch: u8) -> bool {
	b := &doc.buffer
	opener, closer: u8
	isQuote := false
	for p in CODE_PAIRS {
		if ch == p[0] || ch == p[1] {
			opener, closer = p[0], p[1]
			isQuote = p[0] == p[1]
		}
	}
	if opener == 0 do return false
	group := buf.buffer_next_group(b)
	// Step over an existing closer (every cursor must sit before one).
	if ch == closer {
		all := true
		for c in b.cursors {
			line := buf.buffer_line_str(b, c.pos.line)
			if c.sel.active && c.sel.anchor != c.pos {all = false; break}
			if c.pos.col >= len(line) || line[c.pos.col] != closer {all = false; break}
		}
		if all {
			for &c in b.cursors do c.pos.col += 1
			return true
		}
		if !isQuote do return false
	}
	if ch != opener do return false
	// Wrap selections.
	anySel := false
	for c in b.cursors do if _, _, ok := buf.selection_range(c); ok do anySel = true
	if anySel {
		order := buf.buffer_sorted_cursor_indices(b)
		for i in order {
			c := &b.cursors[i]
			s, e_, ok := buf.selection_range(c^)
			if !ok do continue
			buf.buffer_insert_text(b, e_, string([]u8{closer}), group)
			buf.buffer_insert_text(b, s, string([]u8{opener}), group)
			// Keep the text selected, inside the brackets.
			e2 := e_
			if e_.line == s.line do e2.col += 1
			c.sel = {anchor = {s.line, s.col + 1}, active = true}
			c.pos = e2
		}
		return true
	}
	// Insert a pair only where it makes sense: before whitespace, a closer
	// or the end of the line; quotes not right after a word character.
	for c in b.cursors {
		line := buf.buffer_line_str(b, c.pos.line)
		if c.pos.col < len(line) {
			next := line[c.pos.col]
			if !(next == ' ' || next == '\t' || next == ')' || next == ']' || next == '}' || next == ',' || next == ';') do return false
		}
		if isQuote && c.pos.col > 0 {
			prev := line[c.pos.col - 1]
			if code_is_ident_byte(prev) || prev == opener || prev == '\\' do return false
		}
		// Not inside a string or comment.
		if doc.isLua && code_in_string_or_comment(doc, c.pos) do return false
	}
	buf.buffer_type_text(b, string([]u8{opener, closer}))
	for &c in b.cursors do c.pos.col -= 1
	return true
}

// code_in_string_or_comment: is `p` inside a string/comment token?
code_in_string_or_comment :: proc(doc: ^Code_Doc, p: buf.Position) -> bool {
	code_update_line_states(doc)
	line := buf.buffer_line_str(&doc.buffer, p.line)
	tokens, _ := Token_CacheGet(&doc.tokens, doc.lang, line, doc.lineStates[p.line] if p.line < len(doc.lineStates) else 0, doc.buffer.version)
	for t in tokens {
		if (t.kind == .String || t.kind == .Comment) && p.col > t.start && p.col < t.end do return true
		if t.kind == .Comment && p.col >= t.end && t.end == len(line) && p.col > t.start do return true
	}
	return false
}

// code_delete_pair: Backspace between an empty pair "(|)" removes both.
code_delete_pair :: proc(b: ^buf.Buffer) -> bool {
	for c in b.cursors {
		if c.sel.active && c.sel.anchor != c.pos do return false
		line := buf.buffer_line_str(b, c.pos.line)
		if c.pos.col == 0 || c.pos.col >= len(line) do return false
		ok := false
		for p in CODE_PAIRS do if line[c.pos.col - 1] == p[0] && line[c.pos.col] == p[1] do ok = true
		if !ok do return false
	}
	group := buf.buffer_next_group(b)
	order := buf.buffer_sorted_cursor_indices(b)
	for i in order {
		c := &b.cursors[i]
		buf.buffer_delete_range(b, {c.pos.line, c.pos.col - 1}, {c.pos.line, c.pos.col + 1}, group)
		c.pos.col -= 1
	}
	return true
}

// code_expand_chord: the modifiers of expand / shrink selection (an action,
// not a caret move).
code_expand_chord :: proc(ctrl, alt, shift: bool) -> bool {
	when ODIN_OS == .Darwin do return ctrl && shift && !alt
	else do return alt && shift && !ctrl
}

// code_newline: Enter keeps the indentation and indents one more level
// after a line that opens a block (then/do/function/repeat/else/{/().
code_newline :: proc(doc: ^Code_Doc) {
	b := &doc.buffer
	if len(b.cursors) > 1 {
		buf.buffer_newline(b)
		return
	}
	c := b.cursors[0].pos
	// Copies: the newline below changes the buffer the line string points into.
	line := strings.clone(buf.buffer_line_str(b, c.line), context.temp_allocator)
	before := strings.trim_space(line[:min(c.col, len(line))])
	after := strings.trim_space(line[min(c.col, len(line)):])
	buf.buffer_newline(b)
	if !doc.isLua do return
	opens := false
	// Drop a trailing comment.
	if i := strings.index(before, "--"); i >= 0 do before = strings.trim_space(before[:i])
	for kw in ([]string{"then", "do", "repeat", "else", "{", "(", "["}) {
		if strings.has_suffix(before, kw) do opens = true
	}
	if strings.has_suffix(before, ")") && (strings.has_prefix(before, "function") || strings.has_prefix(before, "local function") || strings.contains(before, "= function") || strings.contains(before, "(function")) {
		opens = true
	}
	if !opens do return
	indent := "\t" if doc.useTabs else strings.repeat(" ", code_tab_width(), context.temp_allocator)
	buf.buffer_type_text(b, indent)
	// Typing between a block opener and its "end"/"}"/")": push it down.
	if strings.has_prefix(after, "end") || strings.has_prefix(after, "}") || strings.has_prefix(after, ")") || strings.has_prefix(after, "]") {
		saved := b.cursors[0].pos
		buf.buffer_newline(b)
		buf.buffer_outdent(b) // the closer goes back to the opener's level
		code_set_single_cursor(b, saved, false)
	}
}

// --- hover -------------------------------------------------------------------------

code_hover :: proc(doc: ^Code_Doc, hovered: bool, mouse: [2]f32) {
	cm := &GlobalCode
	b := &doc.buffer
	if !hovered {
		cm.hoverValid = false
		return
	}
	p := code_pos_at(b, mouse)
	line := buf.buffer_line_str(b, p.line)
	// The mouse moved onto the hover box (to scroll it): keep it.
	keep := cm.hoverValid && Code_OverlayHovered("hover")
	if keep {
		p = cm.hoverPos
		line = buf.buffer_line_str(b, p.line)
	}
	// Only over actual text.
	endX := code_screen_pos(b, {p.line, len(line)}).x // inlay hints and wrapped rows counted
	if !keep && (mouse.x > endX || mouse.x < cm.textOrigin.x) {
		cm.hoverValid = false
		return
	}
	if !cm.hoverValid || p != cm.hoverPos {
		// Same word? keep the timer.
		if !(cm.hoverValid && p.line == cm.hoverPos.line && code_word_start(b, p) == code_word_start(b, cm.hoverPos) && code_word_start(b, p).col != p.col) {
			cm.hoverSince = time.tick_now()
			cm.hoverSent = false
		}
		cm.hoverPos = p
		cm.hoverValid = true
	}
	if time.tick_since(cm.hoverSince) < 450 * time.Millisecond do return
	if code_texture_hover(doc, p) do return // an image path: its preview (code_engine_extras.odin)

	// Diagnostics under the mouse.
	msgs := make([dynamic]lsp.Diagnostic, context.temp_allocator)
	for d in code_diagnostics(doc) {
		sl, el := d.range.start.line, d.range.end.line
		if p.line < sl || p.line > el do continue
		from := code_byte_from_u16(buf.buffer_line_str(b, sl), d.range.start.character) if p.line == sl else 0
		to := code_byte_from_u16(buf.buffer_line_str(b, el), d.range.end.character) if p.line == el else len(line)
		if to <= from do to = from + 1
		if p.col >= from && p.col <= to do append(&msgs, d)
	}
	if !cm.hoverSent && doc.isLua {
		cm.hoverSent = true
		code_lsp_request_hover(doc, p)
	}
	hover := code_lsp_hover_text()
	if len(msgs) == 0 && hover == "" do return
	// Diagnostics, then the language server's docs: a bounded, scrollable
	// box under (or over) the word, inside the Code area.
	blocks := make([dynamic]Overlay_Block, context.temp_allocator)
	for d in msgs {
		append(&blocks, Overlay_Block{fmt.tprintf("%s  %s", ICON_FA_CIRCLE_XMARK if d.severity <= 1 else ICON_FA_TRIANGLE_EXCLAMATION, d.message), false, imgui.ColorConvertU32ToFloat4(code_severity_color(d.severity))})
	}
	if hover != "" do markdown_blocks(hover, &blocks)
	ws := code_word_start(b, p)
	anchor := code_screen_pos(b, ws)
	Code_Overlay_Draw("hover", anchor, cm.lineH, blocks[:])
}

// code_markdown renders LSP markdown simply: code fences in the mono font,
// other lines as text.
code_markdown :: proc(text: string) {
	inCode := false
	lines := strings.split_lines(text, context.temp_allocator)
	blank := false
	for l in lines {
		if strings.has_prefix(strings.trim_space(l), "```") {
			inCode = !inCode
			continue
		}
		if strings.trim_space(l) == "" {
			if !blank do imgui.Dummy({0, 2})
			blank = true
			continue
		}
		if strings.trim_space(l) == "---" {
			imgui.Separator()
			continue
		}
		blank = false
		if inCode {
			imgui.PushFont(code_font())
			imgui.PushStyleColorImVec4(.Text, {0.42, 0.68, 1.00, 1})
			imgui.TextUnformatted(strings.clone_to_cstring(l, context.temp_allocator))
			imgui.PopStyleColor()
			imgui.PopFont()
		} else {
			t, _ := strings.replace_all(l, "`", "", context.temp_allocator)
			t, _ = strings.replace_all(t, "**", "", context.temp_allocator)
			t, _ = strings.replace_all(t, "\\", "", context.temp_allocator)
			imgui.TextUnformatted(strings.clone_to_cstring(t, context.temp_allocator))
		}
	}
}

// --- close prompt ------------------------------------------------------------------

code_close_prompt :: proc(state: ^EditorState) {
	cm := &GlobalCode
	if cm.closePrompt < 0 do return
	if cm.closePrompt >= len(cm.docs) {
		cm.closePrompt = -1
		return
	}
	doc := cm.docs[cm.closePrompt]
	imgui.OpenPopup("Unsaved Changes###CodeClosePrompt")
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, {}, {0.5, 0.5})
	if !imgui.BeginPopupModal("Unsaved Changes###CodeClosePrompt", nil, {.NoResize, .AlwaysAutoResize, .NoTitleBar}) do return
	UI_PanelTitle(ICON_FA_FILE_CODE, "Unsaved changes")
	imgui.Dummy({0, 4})
	imgui.TextUnformatted(fmt.ctprintf("Save changes to %s before closing?", doc.rel))
	imgui.Dummy({0, 8})
	idx := cm.closePrompt
	if UI_PrimaryButton("Save", "code.close-save", {96, 0}) {
		if Code_SaveDoc(state, doc) do code_close_doc(idx)
		cm.closePrompt = -1
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Don't Save", "code.close-discard", {96, 0}) {
		code_close_doc(idx)
		cm.closePrompt = -1
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Cancel", "code.close-cancel", {96, 0}) || imgui.IsKeyPressed(.Escape, false) {
		cm.closePrompt = -1
		imgui.CloseCurrentPopup()
	}
	imgui.EndPopup()
}

// --- new scripts -------------------------------------------------------------------

CODE_SCRIPT_TEMPLATE :: e.SCRIPT_TEMPLATE_EMPTY // more in New Script (new_script_dialog.odin)

// Editor_NewScript creates scripts/<name>.lua from a template (unique
// name) and opens it. Returns the project-relative path.
Editor_NewScript :: proc(state: ^EditorState, baseName := "new_script", template := CODE_SCRIPT_TEMPLATE) -> string {
	Lua_MarkProjectTypesDirty() // generated Lua types follow the project
	dir, _ := filepath.join({state.projectPath, "scripts"}, context.temp_allocator)
	os.make_directory(dir)
	name := baseName
	path := ""
	for i := 1; ; i += 1 {
		if i > 1 do name = fmt.tprintf("%s_%d", baseName, i)
		path, _ = filepath.join({dir, fmt.tprintf("%s.lua", name)}, context.temp_allocator)
		if !os.exists(path) do break
	}
	cn := script_class_name(name)
	text, _ := strings.replace_all(template, "$CLASS$", cn, context.temp_allocator)
	text, _ = strings.replace_all(text, "$NAME$", name, context.temp_allocator)
	if os.write_entire_file(path, transmute([]u8)text) != nil {
		Editor_Log(state, .Error, "Could not create %s", path)
		return ""
	}
	rel := fmt.tprintf("scripts/%s.lua", name)
	Editor_Log(state, .Info, "Created %s", rel)
	// Open at the first method (ready / update) of the template.
	line := 0
	for l, i in strings.split_lines(text, context.temp_allocator) {
		if strings.has_prefix(l, "function ") {line = i + 1; break}
	}
	Editor_OpenScript(state, rel, line, 0)
	return rel
}

// script_class_name: the PascalCase class of a script file name.
script_class_name :: proc(name: string) -> string {
	cls := strings.builder_make(context.temp_allocator)
	upper := true
	for ch in name {
		if ch == '_' || ch == '-' {upper = true; continue}
		if upper && ch >= 'a' && ch <= 'z' do strings.write_rune(&cls, ch - 32)
		else do strings.write_rune(&cls, ch)
		upper = false
	}
	return strings.to_string(cls)
}

// Editor_NewScriptForNode creates a script for a node from a template (""
// = the one that suits its type, e.Script_TemplateFor), named after the
// node unless given a name. A CharacterMover with a character template is
// switched to Script mode (the script moves it with character_move_and_slide).
Editor_NewScriptForNode :: proc(state: ^EditorState, node: ^e.Node, template := "", name := "") -> string {
	// "PatrolDrone" -> patrol_drone.lua with class PatrolDrone.
	base := name if name != "" else strings.to_snake_case(node.name, context.temp_allocator)
	if base == "" do base = "new_script"
	id := template if template != "" else e.Script_TemplateFor(node.typeId)
	tp, ok := e.Script_TemplateById(id)
	if !ok do tp, _ = e.Script_TemplateById("empty")
	rel := Editor_NewScript(state, base, tp.text)
	if rel != "" && node.typeId == e.CharacterMoverNode {
		(cast(^e.CharacterMoverNode)node).controlMode = .Script
		Editor_Log(state, .Info, "%s uses the %s template; %s now moves by script", rel, tp.label, node.name)
	}
	return rel
}

// --- drive queries -----------------------------------------------------------------

// Code_DriveQuery answers "code.*" queries for test drives.
Code_DriveQuery :: proc(q: string) -> (string, bool) {
	cm := &GlobalCode
	doc: ^Code_Doc
	if cm.active >= 0 && cm.active < len(cm.docs) do doc = cm.docs[cm.active]
	if strings.has_prefix(q, "code.inline-values:") {
		// the debugger's inline values on a line (1-based), while paused
		if doc == nil do return "", true
		ln := 0
		for r in q[len("code.inline-values:"):] do if r >= '0' && r <= '9' do ln = ln * 10 + int(r - '0')
		_, _, locals, ok := Debug_InlineInfo()
		if !ok || ln < 1 || ln > buf.buffer_line_count(&doc.buffer) do return "", true
		text := buf.buffer_line_str(&doc.buffer, ln - 1)
		code_update_line_states(doc)
		tokens, _ := Token_CacheGet(&doc.tokens, doc.lang, text, doc.lineStates[ln - 1], doc.buffer.version)
		return code_inline_values_text(text, tokens, locals), true
	}
	if strings.has_prefix(q, "code.inlays:") {
		// the hints of a line (1-based): "label@col,..."
		if doc == nil do return "", true
		ln := 0
		for r in q[len("code.inlays:"):] do if r >= '0' && r <= '9' do ln = ln * 10 + int(r - '0')
		sb := strings.builder_make(context.temp_allocator)
		for h, i in code_inlays(doc, ln - 1) do fmt.sbprintf(&sb, "%s%s@%d", "," if i > 0 else "", "■" if h.swatch else h.label, h.col)
		return strings.to_string(sb), true
	}
	switch q {
	case "code.open":
		return fmt.tprint(len(cm.docs)), true
	case "code.file":
		return doc.rel if doc != nil else "", true
	case "code.text":
		return buf.buffer_to_string(&doc.buffer, context.temp_allocator) if doc != nil else "", true
	case "code.line":
		if doc == nil do return "", true
		return buf.buffer_line_str(&doc.buffer, doc.buffer.cursors[0].pos.line), true
	case "code.cursor":
		if doc == nil do return "", true
		p := doc.buffer.cursors[0].pos
		return fmt.tprintf("%d:%d", p.line + 1, p.col + 1), true
	case "code.dirty":
		return "true" if doc != nil && code_doc_dirty(doc) else "false", true
	case "code.focused":
		return "true" if cm.focused else "false", true
	case "code.lsp":
		return strings.to_lower(fmt.tprint(cm.lspState), context.temp_allocator), true
	case "code.completion":
		if !cm.completion.open || !completion_indices_valid() do return "", true
		sb := strings.builder_make(context.temp_allocator)
		for i, n in cm.completion.filtered {
			if n > 0 do strings.write_string(&sb, ",")
			strings.write_string(&sb, code_completion_label(&cm.client.last_completion[i]))
		}
		return strings.to_string(sb), true
	case "code.token-bench":
		// "full=<ms> cached=<ms> tokenized=<lines>": re-tokenizing every line
		// (as before the cache) vs. the cached line-state pass.
		doc := code_active_doc()
		if doc == nil do return "", true
		b := &doc.buffer
		t0 := time.tick_now()
		state := syn.LINE_STATE_NORMAL
		for i in 0 ..< buf.buffer_line_count(b) do _, state = doc.lang.tokenize(buf.buffer_line_str(b, i), state, context.temp_allocator)
		full := time.duration_milliseconds(time.tick_since(t0))
		doc.statesVersion = -1
		code_update_line_states(doc)
		return fmt.tprintf("full=%.2f cached=%.2f tokenized=%d lines=%d", full, doc.tokens.lastUpdateMs, doc.tokens.tokenized, buf.buffer_line_count(b)), true
	case "code.token-speedup": // full re-tokenize time / cached pass time
		doc := code_active_doc()
		if doc == nil do return "0", true
		b := &doc.buffer
		t0 := time.tick_now()
		state := syn.LINE_STATE_NORMAL
		for i in 0 ..< buf.buffer_line_count(b) do _, state = doc.lang.tokenize(buf.buffer_line_str(b, i), state, context.temp_allocator)
		full := time.duration_milliseconds(time.tick_since(t0))
		doc.statesVersion = -1
		code_update_line_states(doc)
		return fmt.tprintf("%.1f", full / max(doc.tokens.lastUpdateMs, 0.001)), true
	case "code.overlays": return Code_OverlaysInside(), true // "ok <n>" when all inside the Code area
	case "code.update-ms": // the last line-state pass after an edit
		doc := code_active_doc()
		if doc == nil do return "", true
		return fmt.tprintf("%.2f", doc.tokens.lastUpdateMs), true
	case "code.completion-doc":
		if !cm.completion.open || cm.completion.selected >= len(cm.completion.filtered) do return "", true
		return cm.client.last_completion[cm.completion.filtered[cm.completion.selected]].documentation, true
	case "code.selection":
		if doc == nil do return "", true
		b := &doc.buffer
		s, e_, ok := buf.selection_range(code_primary(b)^)
		if !ok || s.line != e_.line do return "", true
		return buf.buffer_line_str(b, s.line)[s.col:e_.col], true
	case "code.tabs":
		// open tabs in order, "(preview)" / "(pinned)" marked
		sb := strings.builder_make(context.temp_allocator)
		for d, i in cm.docs do fmt.sbprintf(&sb, "%s%s%s", "," if i > 0 else "", filepath.base(d.rel), " (pinned)" if d.pinned else (" (preview)" if d.preview else ""))
		return strings.to_string(sb), true
	case "code.folds":
		// folded block first lines, 1-based, comma-separated
		if doc == nil do return "", true
		sb := strings.builder_make(context.temp_allocator)
		sorted := slice.clone(doc.folds[:], context.temp_allocator)
		slice.sort(sorted)
		for f, i in sorted do fmt.sbprintf(&sb, "%s%d", "," if i > 0 else "", f + 1)
		return strings.to_string(sb), true
	case "code.changes":
		// "<line>:<added|modified|deleted>" (1-based), sorted
		if doc == nil do return "", true
		marks := slice.clone(Code_ChangedLines(doc), context.temp_allocator)
		slice.sort_by(marks, proc(a, b: Code_Change_Mark) -> bool {return a.line < b.line})
		sb := strings.builder_make(context.temp_allocator)
		for m, i in marks {
			kind := "added" if m.color == CHANGE_ADDED else ("modified" if m.color == CHANGE_MODIFIED else "deleted")
			fmt.sbprintf(&sb, "%s%d:%s", "," if i > 0 else "", m.line + 1, kind)
		}
		return strings.to_string(sb), true
	case "code.git": return fmt.tprint(doc.git.state) if doc != nil else "", true
	case "code.rows": return fmt.tprint(len(code_display(doc).rows)) if doc != nil else "0", true
	case "code.lines": return fmt.tprint(buf.buffer_line_count(&doc.buffer)) if doc != nil else "0", true
	case "code.symbol-highlights":
		if doc == nil do return "0", true
		return fmt.tprint(len(code_symbol_occurrences(doc, 0, buf.buffer_line_count(&doc.buffer) - 1))), true
	case "code.selection-range":
		// "<line>:<col>-<line>:<col>" (1-based lines, 0-based columns)
		if doc == nil do return "", true
		s, e_, ok := buf.selection_range(code_primary(&doc.buffer)^)
		if !ok do return "", true
		return fmt.tprintf("%d:%d-%d:%d", s.line + 1, s.col, e_.line + 1, e_.col), true
	case "code.signature":
		return code_signature_label() if cm.sigOpen else "", true
	case "code.errors":
		if doc == nil do return "0", true
		errs, _ := code_diagnostic_counts(doc)
		return fmt.tprint(errs), true
	case "code.diagnostics":
		if doc == nil do return "0", true
		return fmt.tprint(len(code_diagnostics(doc))), true
	case "code.diagnostic-messages":
		if doc == nil do return "", true
		sb := strings.builder_make(context.temp_allocator)
		for d in code_diagnostics(doc) do fmt.sbprintf(&sb, "%d: %s\n", d.range.start.line + 1, d.message)
		return strings.to_string(sb), true
	case "code.cursors":
		return fmt.tprint(len(doc.buffer.cursors)) if doc != nil else "0", true
	case "code.find":
		if doc == nil || !cm.find.open do return "", true
		matches := code_find_all(doc)
		return fmt.tprintf("%d", len(matches)), true
	case "code.font":
		return fmt.tprintf("%.0f", code_font_size()), true
	case "code.hover":
		return code_lsp_hover_text(), true
	}
	return "", false
}

// Code_ParseLocation finds a "path.lua:LINE" location in a log message
// (Lua errors and tracebacks use this form, sometimes with a leading "@").
Code_ParseLocation :: proc(msg: string) -> (path: string, line: int, ok: bool) {
	i := strings.index(msg, ".lua:")
	if i < 0 do return
	start := i
	for start > 0 {
		ch := msg[start - 1]
		if ch == ' ' || ch == '\t' || ch == '"' || ch == '\'' || ch == '[' || ch == '(' || ch == '@' do break
		start -= 1
	}
	j := i + 5
	for j < len(msg) && msg[j] >= '0' && msg[j] <= '9' {
		line = line * 10 + int(msg[j] - '0')
		j += 1
	}
	if line == 0 do return
	return msg[start:i + 4], line, true
}

