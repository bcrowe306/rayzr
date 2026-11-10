package editor

import "core:fmt"
import "core:strings"
import e "../engine"
import buf "../odin_editor/buffer"
import lsp "../odin_editor/lsp"
import imgui "lib/imgui"

// ============================================================================
// Code actions (Cmd+. or the lightbulb in the gutter): fixes for the caret.
//
//   engine   a node path / name that isn't in the scene (get_node,
//            find_node, get_child): pick one of the scene's nodes; an input
//            action the project doesn't have (Input.is_action_*): add it to
//            Project Settings > Input
//   server   lua-language-server's quick fixes for the diagnostics there
//
// The menu opens at the caret with the engine fixes at once; the server's
// follow when they arrive. Enter / click applies one.
// ============================================================================

@(private = "file")
Engine_Fix :: struct {
	title:  string, // temp-free: owned by acts
	kind:   enum {NodePath, AddAction},
	from, to: buf.Position, // the string literal's contents
	value:  string,         // the literal (node path / action name)
}

@(private = "file")
acts: struct {
	open:     bool,
	waiting:  bool,
	seq:      int,
	fixes:    [dynamic]Engine_Fix,
	selected: int,
	picking:  bool, // the node picker for a NodePath fix
	pickFix:  int,
	filter:   [64]u8,
	anchor:   [2]f32,
}

@(private = "file")
acts_clear :: proc() {
	for f in acts.fixes {
		delete(f.title)
		delete(f.value)
	}
	clear(&acts.fixes)
}

Code_ActionsShutdown :: proc() {
	acts_clear()
	delete(acts.fixes)
}

// code_literal_at: the string literal around p and the call before it.
@(private = "file")
code_literal_at :: proc(b: ^buf.Buffer, p: buf.Position) -> (lit: string, from, to: int, before: string, ok: bool) {
	line := buf.buffer_line_str(b, p.line)
	open := -1
	for i := min(p.col, len(line)) - 1; i >= 0; i -= 1 do if line[i] == '"' || line[i] == '\'' {open = i; break}
	if open < 0 do return
	close := strings.index_byte(line[open + 1:], line[open])
	if close < 0 || open + 1 + close < p.col do return
	return line[open + 1:open + 1 + close], open + 1, open + 1 + close, strings.trim_right_space(line[:open]), true
}

// code_engine_fixes: the engine's fixes at the caret.
@(private = "file")
code_engine_fixes :: proc(state: ^EditorState, doc: ^Code_Doc) {
	acts_clear()
	b := &doc.buffer
	p := b.cursors[len(b.cursors) - 1].pos
	lit, from, to, before, ok := code_literal_at(b, p)
	if !ok do return
	switch {
	case strings.has_suffix(before, "get_node(") || strings.has_suffix(before, "find_node(") || strings.has_suffix(before, "get_child("):
		if state.activeScene == nil do return
		found := e.Scene_FindNodeByName(state.activeScene, lit) != nil
		if !found {
			if owner := code_script_owner(state, doc); owner != nil do found = e.Node_ResolvePath(state.activeScene.manager, owner, lit) != nil
		}
		if !found {
			append(&acts.fixes, Engine_Fix{fmt.aprintf("No node \"%s\" in this scene - pick one...", lit), .NodePath, {p.line, from}, {p.line, to}, strings.clone(lit)})
		}
	case strings.has_suffix(before, "is_action_pressed(") || strings.has_suffix(before, "is_action_down(") || strings.has_suffix(before, "is_action_released(") || strings.has_suffix(before, "get_action_strength("):
		if lit == "" || code_project_has_action(state, lit) do return
		append(&acts.fixes, Engine_Fix{fmt.aprintf("Add input action \"%s\" to Project Settings", lit), .AddAction, {p.line, from}, {p.line, to}, strings.clone(lit)})
	}
}

@(private = "file")
code_project_has_action :: proc(state: ^EditorState, name: string) -> bool {
	if len(state.projectConfig.actions) == 0 {
		defaults := e.Input_DefaultActionConfigs(context.temp_allocator)
		for a in defaults do if a.name == name do return true
		return false
	}
	for a in state.projectConfig.actions do if a.name == name do return true
	return false
}

// Code_LightbulbAt: the caret's line has something to fix (diagnostics or
// an engine fix) - the gutter shows a lightbulb.
Code_LightbulbAt :: proc(state: ^EditorState, doc: ^Code_Doc, line: int) -> bool {
	b := &doc.buffer
	if b.cursors[len(b.cursors) - 1].pos.line != line do return false
	for d in code_diagnostics(doc) do if d.range.start.line <= line && d.range.end.line >= line do return true
	p := b.cursors[len(b.cursors) - 1].pos
	lit, _, _, before, ok := code_literal_at(b, p)
	if !ok do return false
	if strings.has_suffix(before, "is_action_pressed(") || strings.has_suffix(before, "is_action_down(") || strings.has_suffix(before, "is_action_released(") {
		return lit != "" && !code_project_has_action(state, lit)
	}
	if (strings.has_suffix(before, "find_node(") || strings.has_suffix(before, "get_node(")) && state.activeScene != nil {
		if e.Scene_FindNodeByName(state.activeScene, lit) != nil do return false
		owner := code_script_owner(state, doc)
		return owner == nil || e.Node_ResolvePath(state.activeScene.manager, owner, lit) == nil
	}
	return false
}

// Code_CmdCodeActions (Cmd+.).
Code_CmdCodeActions :: proc(state: ^EditorState) {
	cm := &GlobalCode
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	p := b.cursors[len(b.cursors) - 1].pos
	code_engine_fixes(state, doc)
	acts.waiting = false
	if cm.lspState == .Ready && doc.isLua {
		code_lsp_sync(doc)
		diags := make([dynamic]lsp.Diagnostic, context.temp_allocator)
		// The server's own (not the game's runtime problems: code_runtime_diag.odin).
		for d in code_diagnostics(doc) do if d.source != "game" && d.range.start.line <= p.line && d.range.end.line >= p.line do append(&diags, d)
		col := code_u16_col(buf.buffer_line_str(b, p.line), p.col)
		acts.seq = cm.client.code_action_seq
		lsp.client_request_code_action(&cm.client, doc.uri, lsp.Range{start = {p.line, col}, end = {p.line, col}}, diags[:])
		acts.waiting = true
	}
	sp := code_screen_pos(b, p)
	acts.anchor = {sp.x, sp.y + cm.lineH + 2}
	acts.selected = 0
	acts.picking = false
	acts.open = true
}

// Code_ActionsRender draws the menu / the node picker (Code window).
Code_ActionsRender :: proc(state: ^EditorState, doc: ^Code_Doc) {
	cm := &GlobalCode
	if acts.open {
		imgui.OpenPopup("##code_actions")
		acts.open = false
	}
	imgui.SetNextWindowPos(acts.anchor, .Appearing)
	if !imgui.BeginPopup("##code_actions") do return
	defer imgui.EndPopup()
	Drive_Item("code.actions")
	if imgui.IsKeyPressed(.Escape) {
		imgui.CloseCurrentPopup()
		cm.focusRequest = true
		return
	}
	if acts.picking {
		code_actions_node_picker(state, doc)
		return
	}
	serverActs := cm.client.last_code_actions[:] if !acts.waiting || cm.client.code_action_seq != acts.seq else nil
	if acts.waiting && cm.client.code_action_seq != acts.seq do acts.waiting = false
	n := len(acts.fixes) + len(serverActs)
	UI_DimText(fmt.tprintf("%s  Code actions", ICON_FA_LIGHTBULB))
	if n == 0 {
		UI_DimText("Looking for fixes..." if acts.waiting else "Nothing to fix here")
		return
	}
	if imgui.IsKeyPressed(.DownArrow) do acts.selected = (acts.selected + 1) % n
	if imgui.IsKeyPressed(.UpArrow) do acts.selected = (acts.selected + n - 1) % n
	apply := -1
	for f, i in acts.fixes {
		if imgui.Selectable(fmt.ctprintf("%s  %s##fix%d", ICON_FA_WAND_MAGIC_SPARKLES, f.title, i), acts.selected == i, {.NoAutoClosePopups}) do apply = i // (a pick may open the node picker)
		Drive_Item(fmt.tprintf("code.action:%d", i))
	}
	for a, k in serverActs {
		i := len(acts.fixes) + k
		if imgui.Selectable(fmt.ctprintf("%s  %s##lsp%d", ICON_FA_LIGHTBULB, a.title, k), acts.selected == i) do apply = i
		Drive_Item(fmt.tprintf("code.action:%d", i))
	}
	if imgui.IsKeyPressed(.Enter) || imgui.IsKeyPressed(.KeypadEnter) do apply = acts.selected
	if apply < 0 do return
	if apply < len(acts.fixes) {
		f := acts.fixes[apply]
		switch f.kind {
		case .NodePath:
			acts.picking = true
			acts.pickFix = apply
			acts.filter = {}
			return
		case .AddAction:
			cfg := &state.projectConfig
			if len(cfg.actions) == 0 {
				e.Input_ActionConfigs_Destroy(&cfg.actions)
				cfg.actions = e.Input_DefaultActionConfigs()
			}
			append(&cfg.actions, e.Input_Action_Config{name = strings.clone(f.value), bindings = make([dynamic]e.InputBinding)})
			e.Project_SaveConfigToFile(state.projectPath, cfg)
			e.Input_ApplyActionConfigs(&state.game.input, cfg.actions[:])
			Lua_MarkProjectTypesDirty()
			Editor_Log(state, .Info, "Added input action \"%s\" (give it keys in Project Settings > Input)", f.value)
		}
	} else {
		a := serverActs[apply - len(acts.fixes)]
		code_apply_edit_list(state, a.edits)
		Editor_Log(state, .Info, "Applied: %s", a.title)
	}
	imgui.CloseCurrentPopup()
	cm.focusRequest = true
}

// code_actions_node_picker: the scene's nodes (paths from the script's node
// for get_node); the pick replaces the string.
@(private = "file")
code_actions_node_picker :: proc(state: ^EditorState, doc: ^Code_Doc) {
	f := acts.fixes[acts.pickFix]
	UI_DimText(fmt.tprintf("Replace \"%s\" with:", f.value))
	if imgui.IsWindowAppearing() || acts.filter[0] == 0 do imgui.SetKeyboardFocusHere()
	imgui.SetNextItemWidth(280)
	imgui.InputTextWithHint("##node_filter", "Filter nodes", cstring(raw_data(acts.filter[:])), len(acts.filter), {})
	Drive_Item("code.action-filter")
	q := strings.to_lower(string(cstring(raw_data(acts.filter[:]))), context.temp_allocator)
	if state.activeScene == nil do return
	mgr := state.activeScene.manager
	owner := code_script_owner(state, doc)
	b := &doc.buffer
	line := buf.buffer_line_str(b, f.from.line)
	usePath := strings.has_suffix(strings.trim_right_space(line[:max(f.from.col - 1, 0)]), "get_node(") && owner != nil
	shown := 0
	for n in mgr.nodes {
		if n == nil || n == state.activeScene.rootNode || n.removing do continue
		label := e.Node_RelativePath(mgr, owner, n) if usePath else n.name
		if q != "" && !strings.contains(strings.to_lower(label, context.temp_allocator), q) do continue
		if shown >= 40 do break
		shown += 1
		if imgui.Selectable(fmt.ctprintf("%s  %s", Editor_NodeIcon(n), label)) || (shown == 1 && (imgui.IsKeyPressed(.Enter) || imgui.IsKeyPressed(.KeypadEnter))) {
			group := buf.buffer_next_group(b)
			buf.buffer_delete_range(b, f.from, f.to, group)
			buf.buffer_insert_text(b, f.from, label, group)
			code_touched(doc)
			imgui.CloseCurrentPopup()
			GlobalCode.focusRequest = true
			return
		}
		Drive_Item(fmt.tprintf("code.action-node:%s", n.name))
	}
}
