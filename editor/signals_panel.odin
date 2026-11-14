package editor

import "core:fmt"
import "core:os"
import "core:strings"
import buf "../odin_editor/buffer"
import syn "../odin_editor/syntax"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Signals (Godot-style) in the Inspector.
//
// Every event a node raises is listed with its connections. "Connect"
// picks a target node and a method name; the connection is saved on the
// source node (engine/signals.odin) and the code editor writes the handler
// into the target's script:
//
//   ---Signal: Clock.timeout - The timer's duration elapsed
//   ---@param source Node
//   function Listener:on_clock_timeout(_, source)
//   end
//
// Disconnecting removes the connection and the generated handler (asking
// first if it contains code). A target without a script gets a new one.
// ============================================================================

@(private = "file")
Signal_Dialog :: struct {
	open:     bool,
	source:   ^e.Node,
	signal:   string,
	target:   ^e.Node,
	method:   [128]u8,
	filter:   [64]u8,
}

@(private = "file")
dlg: Signal_Dialog

@(private = "file")
Remove_Prompt :: struct {
	open:   bool,
	script: string,
	method: string,
}

@(private = "file")
removePrompt: Remove_Prompt

// --- script code helpers -----------------------------------------------------------

// Script_ClassName: the module table name (`return Name` at the end).
Script_ClassName :: proc(text: string) -> string {
	lines := strings.split_lines(text, context.temp_allocator)
	#reverse for l in lines {
		t := strings.trim_space(l)
		if strings.has_prefix(t, "return ") {
			name := strings.trim_space(t[7:])
			ok := len(name) > 0
			for ch in name do if !((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_') do ok = false
			if ok do return name
			return ""
		}
	}
	return ""
}

@(private = "file")
method_header_match :: proc(line, cls, method: string) -> bool {
	t := strings.trim_space(line)
	if !strings.has_prefix(t, "function ") do return false
	rest := strings.trim_space(t[9:])
	for sep in ([]string{":", "."}) {
		head := fmt.tprintf("%s%s%s", cls, sep, method)
		if strings.has_prefix(rest, head) {
			after := strings.trim_left_space(rest[len(head):])
			if strings.has_prefix(after, "(") do return true
		}
	}
	return false
}

// Script_FindMethod locates `function Cls:method(...) ... end` in a buffer:
// first/last line, and whether the body is empty (blank/comments only).
Script_FindMethod :: proc(b: ^buf.Buffer, cls, method: string) -> (first, last: int, emptyBody, found: bool) {
	n := buf.buffer_line_count(b)
	for ln in 0 ..< n {
		if !method_header_match(buf.buffer_line_str(b, ln), cls, method) do continue
		// Match the block with Lua keyword depth (strings/comments skipped).
		depth := 0
		state := syn.LINE_STATE_NORMAL
		for k in ln ..< n {
			line := buf.buffer_line_str(b, k)
			tokens, next := syn.tokenize_lua_line(line, state, context.temp_allocator)
			state = next
			for t in tokens {
				if t.kind != .Keyword do continue
				switch line[t.start:t.end] {
				case "function", "if", "do", "repeat": depth += 1
				case "end", "until": depth -= 1
				}
			}
			if depth <= 0 do return ln, k, body_is_empty(b, ln, k), true
		}
		return ln, n - 1, false, true
	}
	return
}

@(private = "file")
body_is_empty :: proc(b: ^buf.Buffer, first, last: int) -> bool {
	for k in first + 1 ..< last {
		t := strings.trim_space(buf.buffer_line_str(b, k))
		if t != "" && !strings.has_prefix(t, "--") do return false
	}
	return true
}

// signal_doc_lines: the comment block written above a generated handler.
@(private = "file")
signal_handler_text :: proc(cls, method, sourceName, signal, param, doc: string, ptype := "") -> string {
	sb := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&sb, "---Signal: %s.%s", sourceName, signal)
	if doc != "" do fmt.sbprintf(&sb, " - %s", doc)
	strings.write_byte(&sb, '\n')
	if param != "" do fmt.sbprintf(&sb, "---@param %s %s\n", param, e.Signal_LuaType(ptype))
	strings.write_string(&sb, "---@param source Node\n")
	fmt.sbprintf(&sb, "function %s:%s(%s, source)\n", cls, method, param if param != "" else "_")
	strings.write_string(&sb, "end\n")
	return strings.to_string(sb)
}

// code_doc_for_script opens a script in the code editor (focusing it when
// asked) and returns its document.
code_doc_for_script :: proc(state: ^EditorState, rel: string, focus: bool) -> ^Code_Doc {
	cm := &GlobalCode
	active, sel, foc := cm.active, cm.selectRequest, cm.focusRequest
	if !Editor_OpenScript(state, rel) do return nil
	doc := cm.docs[cm.active]
	if !focus do cm.active, cm.selectRequest, cm.focusRequest = active, sel, foc
	return doc
}

// Code_AddSignalHandler writes a handler method into a script (unless it
// exists), shows it in the code editor and saves (if the file had no
// other unsaved edits).
Code_AddSignalHandler :: proc(state: ^EditorState, scriptRel, method, sourceName, signal, param, docText: string, ptype := "") -> bool {
	doc := code_doc_for_script(state, scriptRel, true)
	if doc == nil do return false
	b := &doc.buffer
	wasDirty := doc.buffer.version != doc.savedVersion
	text := buf.buffer_to_string(b, context.temp_allocator)
	cls := Script_ClassName(text)
	if cls == "" {
		Editor_Log(state, .Warn, "%s doesn't end with `return <Module>`; add %s yourself", scriptRel, method)
		return false
	}
	if first, _, _, found := Script_FindMethod(b, cls, method); found {
		Editor_OpenScript(state, scriptRel, first + 1, 4)
		return true
	}
	// Before the final `return Cls`.
	insertLine := buf.buffer_line_count(b)
	for ln := buf.buffer_line_count(b) - 1; ln >= 0; ln -= 1 {
		if strings.trim_space(buf.buffer_line_str(b, ln)) == fmt.tprintf("return %s", cls) {
			insertLine = ln
			break
		}
	}
	code := signal_handler_text(cls, method, sourceName, signal, param, docText, ptype)
	prefix := ""
	if insertLine > 0 && strings.trim_space(buf.buffer_line_str(b, insertLine - 1)) != "" do prefix = "\n"
	group := buf.buffer_next_group(b)
	buf.buffer_insert_text(b, {insertLine, 0}, strings.concatenate({prefix, code, "\n"}, context.temp_allocator), group)
	// Caret inside the new function.
	headerLine := insertLine + (1 if prefix != "" else 0) + strings.count(code, "\n") - 2
	indent := "\t" if doc.useTabs else "    "
	buf.buffer_insert_text(b, {headerLine + 1, 0}, strings.concatenate({indent, "\n"}, context.temp_allocator), group)
	code_set_single_cursor(b, {headerLine + 1, len(indent)}, false)
	doc.scrollToCursor = true
	if !wasDirty do Code_SaveDoc(state, doc)
	Editor_Log(state, .Info, "Added %s:%s to %s", cls, method, scriptRel)
	return true
}

// Code_AddAnimationMethod writes an animation callback method into a script (unless it
// exists), shows it in the code editor, and saves if the file had no other unsaved edits.
Code_AddAnimationMethod :: proc(state: ^EditorState, scriptRel, method: string) -> bool {
	doc := code_doc_for_script(state, scriptRel, true)
	if doc == nil do return false
	b := &doc.buffer
	wasDirty := doc.buffer.version != doc.savedVersion
	text := buf.buffer_to_string(b, context.temp_allocator)
	cls := Script_ClassName(text)
	if cls == "" {
		Editor_Log(state, .Warn, "%s doesn't end with `return <Module>`; add %s yourself", scriptRel, method)
		return false
	}
	if first, _, _, found := Script_FindMethod(b, cls, method); found {
		Editor_OpenScript(state, scriptRel, first + 1, 4)
		return true
	}
	insertLine := buf.buffer_line_count(b)
	for ln := buf.buffer_line_count(b) - 1; ln >= 0; ln -= 1 {
		if strings.trim_space(buf.buffer_line_str(b, ln)) == fmt.tprintf("return %s", cls) {
			insertLine = ln
			break
		}
	}
	indent := "\t" if doc.useTabs else "    "
	code := fmt.tprintf("function %s:%s(arg)\n%s-- Called by animation event\nend\n", cls, method, indent)
	prefix := ""
	if insertLine > 0 && strings.trim_space(buf.buffer_line_str(b, insertLine - 1)) != "" do prefix = "\n"
	group := buf.buffer_next_group(b)
	buf.buffer_insert_text(b, {insertLine, 0}, strings.concatenate({prefix, code, "\n"}, context.temp_allocator), group)
	code_set_single_cursor(b, {insertLine + (1 if prefix != "" else 0) + 1, len(indent)}, false)
	doc.scrollToCursor = true
	if !wasDirty do Code_SaveDoc(state, doc)
	Editor_Log(state, .Info, "Added %s:%s to %s", cls, method, scriptRel)
	return true
}

// Code_RemoveSignalHandler deletes a generated handler (and its comment
// block). With `force` false, a handler that contains code asks first.
Code_RemoveSignalHandler :: proc(state: ^EditorState, scriptRel, method: string, force := false) -> bool {
	full := scriptRel
	abs, _ := strings.replace_all(full, "\\", "/", context.temp_allocator)
	if !Code_IsOpen(state, scriptRel) {
		path := abs if strings.has_prefix(abs, "/") else fmt.tprintf("%s/%s", state.projectPath, abs)
		if !os.exists(path) do return false
	}
	doc := code_doc_for_script(state, scriptRel, false)
	if doc == nil do return false
	b := &doc.buffer
	cls := Script_ClassName(buf.buffer_to_string(b, context.temp_allocator))
	first, last, empty, found := Script_FindMethod(b, cls, method)
	if !found do return false
	if !empty && !force {
		removePrompt = {open = true, script = strings.clone(scriptRel), method = strings.clone(method)}
		return false
	}
	wasDirty := doc.buffer.version != doc.savedVersion
	// Include the comment block above and one blank line.
	from := first
	for from > 0 && strings.has_prefix(strings.trim_space(buf.buffer_line_str(b, from - 1)), "---") do from -= 1
	to := last + 1
	if to < buf.buffer_line_count(b) && strings.trim_space(buf.buffer_line_str(b, to)) == "" do to += 1
	else if from > 0 && strings.trim_space(buf.buffer_line_str(b, from - 1)) == "" do from -= 1
	group := buf.buffer_next_group(b)
	end := buf.Position{to, 0} if to < buf.buffer_line_count(b) else buf.buffer_end_position(b)
	buf.buffer_delete_range(b, {from, 0}, end, group)
	for &c in b.cursors do c.pos = buf.buffer_clamp_position(b, c.pos)
	if !wasDirty do Code_SaveDoc(state, doc)
	Editor_Log(state, .Info, "Removed %s:%s from %s", cls, method, scriptRel)
	return true
}

// --- inspector section -------------------------------------------------------------

node_script_rel :: proc(state: ^EditorState, n: ^e.Node) -> string {
	if n == nil || n.scriptInstance == nil do return ""
	return asset_rel_editor(state, (cast(^e.ScriptInstance)n.scriptInstance).modulePath)
}

// method_used_elsewhere: does another connection in the scene call the
// same method on the same target?
@(private = "file")
method_used_elsewhere :: proc(state: ^EditorState, target: ^e.Node, method: string) -> bool {
	mgr := state.activeScene.manager
	for n in mgr.nodes {
		if n == nil do continue
		for c in n.signalConnections {
			if c.method == method && e.Node_ResolvePath(mgr, n, c.target) == target do return true
		}
	}
	return false
}

Inspector_Signals :: proc(state: ^EditorState, node: ^e.Node) {
	if !UI_SectionHeader("Signals") do return
	mgr := state.activeScene.manager
	typeDoc := signal_type_doc(state, node)
	signals := e.Node_Signals(node, typeDoc)
	ownScript := ""
	if rel := node_script_rel(state, node); rel != "" {
		path := fmt.tprintf("%s/%s", state.projectPath, rel)
		if data, err := os.read_entire_file(path, context.temp_allocator); err == nil do ownScript = string(data)
	}
	imgui.PushStyleVarImVec2(.ItemSpacing, {6, 3})
	defer imgui.PopStyleVar()
	for ev in signals {
		imgui.PushID(strings.clone_to_cstring(ev.name, context.temp_allocator))
		imgui.AlignTextToFramePadding()
		// The name and value clipped short of the buttons on the right.
		right := imgui.GetContentRegionMax().x
		rowStart := imgui.GetCursorScreenPos()
		textRight := imgui.GetWindowPos().x + right - 28 - Signals_RowsWidth(state, ev) - 4
		imgui.PushClipRect(rowStart, {max(textRight, rowStart.x + 40), rowStart.y + 30}, true)
		// Built-in: a bolt; declared: where it comes from.
		icon, tint := ICON_FA_BOLT, UI_WARNING
		switch ev.origin {
		case .Builtin:
		case .Node:   icon, tint = ICON_FA_BOLT, UI_ACCENT
		case .Type:   icon, tint = ICON_FA_PUZZLE_PIECE, UI_ACCENT
		case .Script: icon, tint = ICON_FA_FILE_CODE, UI_ACCENT
		}
		imgui.PushStyleColorImVec4(.Text, tint)
		imgui.TextUnformatted(strings.clone_to_cstring(icon, context.temp_allocator))
		imgui.PopStyleColor()
		imgui.SameLine(0, 6)
		imgui.TextUnformatted(strings.clone_to_cstring(ev.name, context.temp_allocator))
		Drive_Item(fmt.tprintf("insp.signal-event:%s", ev.name))
		// Into a script: a connect with its handler (a declared one's: an emit).
		code_item_drag(.Event if ev.origin == .Builtin else .Signal, ev.name, node, textItem = true)
		if ev.param != "" {
			imgui.SameLine(0, 4)
			UI_DimText(fmt.tprintf("(%s: %s)", ev.param, ev.type) if ev.type != "" else fmt.tprintf("(%s)", ev.param))
		}
		tip := ev.description
		switch ev.origin {
		case .Builtin:
		case .Node:   tip = fmt.tprintf("%s\n\nDeclared on this node", tip) if tip != "" else "Declared on this node"
		case .Type:   tip = fmt.tprintf("%s\n\nThe %s type's signal", tip, Editor_CustomTypeName(state, ev.from)) if tip != "" else fmt.tprintf("The %s type's signal", Editor_CustomTypeName(state, ev.from))
		case .Script: tip = fmt.tprintf("%s\n\nDeclared in %s", tip, asset_rel_editor(state, ev.from)) if tip != "" else fmt.tprintf("Declared in %s", asset_rel_editor(state, ev.from))
		}
		if tip != "" do UI_Tooltip(tip)
		imgui.PopClipRect()
		imgui.SameLine(right - 26)
		if UI_IconButton(ICON_FA_PLUS, fmt.tprintf("insp.signal-connect:%s", ev.name), "Connect to a script method...", size = 24) {
			Signals_OpenConnectDialog(state, node, ev.name)
		}
		if Signals_RowButtons(state, node, ev, right - 28) {
			imgui.PopID()
			return // (the list changed)
		}
		// The node's own on_<event> handler (implicit, always called).
		own := fmt.tprintf("on_%s", ev.name)
		if ownScript != "" && strings.contains(ownScript, fmt.tprintf(":%s(", own)) {
			imgui.Indent(22)
			UI_DimText(fmt.tprintf("self:%s()", own))
			imgui.Unindent(22)
		}
		for c in node.signalConnections {
			if c.signal != ev.name do continue
			imgui.Indent(22)
			target := e.Node_ResolvePath(mgr, node, c.target)
			label := fmt.tprintf("%s  %s :: %s", ICON_FA_LINK, target.name if target != nil else fmt.tprintf("%s (missing)", c.target), c.method)
			imgui.PushStyleColorImVec4(.Text, UI_ACCENT if target != nil else UI_DANGER)
			imgui.AlignTextToFramePadding()
			// Clip the label short of the two buttons on the right.
			rowStart := imgui.GetCursorScreenPos()
			clipW := imgui.GetContentRegionAvail().x - 58
			imgui.PushClipRect(rowStart, {rowStart.x + max(clipW, 20), rowStart.y + 30}, true)
			imgui.TextUnformatted(strings.clone_to_cstring(label, context.temp_allocator))
			imgui.PopClipRect()
			imgui.PopStyleColor()
			Drive_Item(fmt.tprintf("insp.signal:%s:%s", ev.name, c.method))
			UI_Tooltip(fmt.tprintf("%s -> %s:%s(value, source)", ev.name, c.target, c.method))
			imgui.SameLine(imgui.GetContentRegionMax().x - 52)
			if UI_IconButton(ICON_FA_CODE, fmt.tprintf("insp.signal-open:%s:%s", ev.name, c.method), "Open the handler", size = 24) && target != nil {
				Signals_OpenHandler(state, target, c.method)
			}
			imgui.SameLine(0, 2)
			if UI_IconButton(ICON_FA_LINK_SLASH, fmt.tprintf("insp.signal-disconnect:%s:%s", ev.name, c.method), "Disconnect (removes the generated handler)", size = 24) {
				Signals_Disconnect(state, node, c.signal, c.target, c.method)
				imgui.Unindent(22)
				imgui.PopID()
				return // the connection list changed
			}
			imgui.Unindent(22)
		}
		imgui.PopID()
	}
	// Emitted by its script, declared nowhere: Declare.
	for u in Signals_Undeclared(node, ownScript) {
		name := u.name
		imgui.PushID(strings.clone_to_cstring(name, context.temp_allocator))
		imgui.AlignTextToFramePadding()
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextUnformatted(ICON_FA_TRIANGLE_EXCLAMATION)
		imgui.PopStyleColor()
		imgui.SameLine(0, 6)
		UI_DimText(name)
		UI_Tooltip(fmt.tprintf("Its script emits %s, but no signal declares it (it warns when emitted): declare it to connect it here", name))
		imgui.SameLine(imgui.GetContentRegionMax().x - 72)
		if UI_Button("Declare", fmt.tprintf("insp.signal-declare:%s", name), {72, 0}) do Signals_OpenDeclDialog(state, node, preset = name, presetValue = u.hasValue)
		imgui.PopID()
	}
	imgui.Dummy({0, 2})
	if UI_Button(fmt.tprintf("%s  Add Signal", ICON_FA_PLUS), "insp.signal-add", {-1, 0}) do Signals_OpenDeclDialog(state, node)
	UI_Tooltip("Declare a signal of this node: connect it here, raise it with self.node:emit(\"name\", value)" if !typeDoc else "Declare a signal of the type: every node of it has it")
}

// Signals_OpenHandler opens a connection's method in the target's script.
Signals_OpenHandler :: proc(state: ^EditorState, target: ^e.Node, method: string) -> bool {
	if target == nil do return false
	rel := node_script_rel(state, target)
	if rel == "" do return false
	doc := code_doc_for_script(state, rel, true)
	if doc == nil do return false
	cls := Script_ClassName(buf.buffer_to_string(&doc.buffer, context.temp_allocator))
	if first, _, _, found := Script_FindMethod(&doc.buffer, cls, method); found do return Editor_OpenScript(state, rel, first + 1, 4)
	return Editor_OpenScript(state, rel)
}

Signals_Disconnect :: proc(state: ^EditorState, node: ^e.Node, signal, target, method: string) {
	mgr := state.activeScene.manager
	t := e.Node_ResolvePath(mgr, node, target)
	sig := strings.clone(signal, context.temp_allocator)
	tp := strings.clone(target, context.temp_allocator)
	m := strings.clone(method, context.temp_allocator)
	Editor_RecordUndo(state, fmt.tprintf("Disconnect %s", sig))
	e.Node_RemoveConnection(node, sig, tp, m)
	if t != nil && !method_used_elsewhere(state, t, m) {
		if rel := node_script_rel(state, t); rel != "" do Code_RemoveSignalHandler(state, rel, m)
	}
	Editor_Log(state, .Info, "Disconnected %s.%s from %s", node.name, sig, m)
}

Signals_OpenConnectDialog :: proc(state: ^EditorState, node: ^e.Node, signal: string) {
	dlg = {}
	dlg.open = true
	dlg.source = node
	dlg.signal = strings.clone(signal)
	// Default target: the nearest node (self, then ancestors) with a script.
	mgr := state.activeScene.manager
	for n := node; n != nil; n = e.GetParent(mgr, n) {
		if n.scriptInstance != nil {dlg.target = n; break}
	}
	if dlg.target == nil do dlg.target = node
	copy(dlg.method[:len(dlg.method) - 1], e.Signal_HandlerName(node.name, signal))
}

// signals_builtin_method: a node's own method a signal can call with no
// script (a spawner's spawn, a level generator's generate); "" none.
@(private = "file")
signals_builtin_method :: proc(target: ^e.Node) -> string {
	if target == nil || target.scriptInstance != nil do return ""
	if target.typeId == e.SpawnerNode do return "spawn"
	if target.typeId == e.LevelGeneratorNode do return "generate"
	return ""
}

// Signals_Connect makes the connection and writes the handler.
Signals_Connect :: proc(state: ^EditorState, source: ^e.Node, signal: string, target: ^e.Node, method: string) -> bool {
	if source == nil || target == nil || method == "" do return false
	mgr := state.activeScene.manager
	Editor_RecordUndo(state, fmt.tprintf("Connect %s", signal))
	if own := signals_builtin_method(target); own != "" && method == own {
		// The node's own method (spawn, generate): no script, no handler.
		if !e.Node_AddConnection(source, signal, e.Node_RelativePath(mgr, source, target), method) {
			Editor_Log(state, .Info, "%s.%s is already connected to %s", source.name, signal, method)
		}
		Editor_Log(state, .Info, "Connected %s.%s to %s:%s", source.name, signal, target.name, own)
		return true
	}
	if target.scriptInstance == nil {
		rel := Editor_NewScriptForNode(state, target, "platformer" if target.typeId == e.CharacterMoverNode else "empty")
		if rel == "" do return false
		target.gameContext = &state.game.gameContext
		if e.Script_AttachToNode(target, rel, nil, &state.game.scriptManager) == nil {
			Editor_Log(state, .Error, "Could not attach %s to %s", rel, target.name)
			return false
		}
	}
	path := e.Node_RelativePath(mgr, source, target)
	if !e.Node_AddConnection(source, signal, path, method) {
		Editor_Log(state, .Info, "%s.%s is already connected to %s", source.name, signal, method)
	}
	param, docText, ptype := e.Node_DescribeSignal(source, signal)
	Code_AddSignalHandler(state, node_script_rel(state, target), method, source.name, signal, param, docText, ptype)
	Editor_Log(state, .Info, "Connected %s.%s to %s:%s", source.name, signal, target.name, method)
	return true
}

// Signals_Render draws the Connect dialog and the remove-code prompt.
Signals_Render :: proc(state: ^EditorState) {
	if dlg.open {
		imgui.OpenPopup("Connect Signal###ConnectSignal")
		dlg.open = false
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	imgui.SetNextWindowSize({460, 0}, .Appearing)
	if imgui.BeginPopupModal("Connect Signal###ConnectSignal", nil, {.NoTitleBar}) {
		if !e.Node_IsAlive(dlg.source) || state.activeScene == nil {
			imgui.CloseCurrentPopup()
			imgui.EndPopup()
			return
		}
		mgr := state.activeScene.manager
		UI_PanelTitle(ICON_FA_BOLT, fmt.tprintf("Connect %s.%s", dlg.source.name, dlg.signal))
		imgui.Dummy({0, 4})
		UI_DimText("Call a method on this node's script:")
		imgui.SetNextItemWidth(-1)
		imgui.InputTextWithHint("##sig_filter", "Filter nodes", cstring(raw_data(dlg.filter[:])), len(dlg.filter), {})
		filter := strings.to_lower(string(cstring(raw_data(dlg.filter[:]))), context.temp_allocator)
		if imgui.BeginChild("##sig_targets", {0, 220}, {.Borders}, {}) {
			draw :: proc(state: ^EditorState, mgr: ^e.NodeManager, n: ^e.Node, depth: int, filter: string) {
				if n.transient do return
				show := filter == "" || strings.contains(strings.to_lower(n.name, context.temp_allocator), filter)
				if show {
					icon := ICON_FA_CODE if n.scriptInstance != nil else Editor_NodeIcon(n)
					label := fmt.ctprintf("%*s%s  %s%s###t%p", depth * 3, "", icon, n.name, "  (script)" if n.scriptInstance != nil else "", n)
					if imgui.Selectable(label, dlg.target == n) do dlg.target = n
					Drive_Item(fmt.tprintf("signal.target:%s", n.name))
				}
				for c in e.GetChildrenView(mgr, n) do if c != nil do draw(state, mgr, c, depth + 1, filter)
			}
			for c in e.GetChildrenView(mgr, state.activeScene.rootNode) do if c != nil do draw(state, mgr, c, 0, filter)
		}
		imgui.EndChild()
		imgui.Dummy({0, 2})
		UI_DimText("Method")
		imgui.SetNextItemWidth(-1)
		imgui.InputText("##sig_method", cstring(raw_data(dlg.method[:])), len(dlg.method), {})
		Drive_Item("signal.method")
		own := signals_builtin_method(dlg.target)
		if own == "spawn" {
			if UI_Button("Spawn (no script)", "signal.spawn", {0, 0}) {
				dlg.method = {}
				copy(dlg.method[:], "spawn")
			}
			UI_Tooltip("Call the spawner's own spawn() when the event fires")
		} else if own == "generate" {
			if UI_Button("Generate (no script)", "signal.generate", {0, 0}) {
				dlg.method = {}
				copy(dlg.method[:], "generate")
			}
			UI_Tooltip("Call the level generator's own generate() when the event fires")
		}
		if dlg.target != nil && dlg.target.scriptInstance == nil && !(own != "" && strings.trim_space(string(cstring(raw_data(dlg.method[:])))) == own) {
			imgui.PushStyleColorImVec4(.Text, UI_WARNING)
			imgui.TextWrapped("%s", fmt.ctprintf("%s has no script: a new one will be created and attached.", dlg.target.name))
			imgui.PopStyleColor()
		}
		imgui.Dummy({0, 6})
		method := strings.trim_space(string(cstring(raw_data(dlg.method[:]))))
		valid := dlg.target != nil && method != ""
		for ch in method do if !((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_') do valid = false
		if !valid do imgui.BeginDisabled()
		if UI_PrimaryButton("Connect", "signal.connect", {110, 0}) {
			Signals_Connect(state, dlg.source, dlg.signal, dlg.target, strings.clone(method, context.temp_allocator))
			imgui.CloseCurrentPopup()
		}
		if !valid do imgui.EndDisabled()
		imgui.SameLine()
		if UI_Button("Cancel", "signal.cancel", {110, 0}) || imgui.IsKeyPressed(.Escape, false) do imgui.CloseCurrentPopup()
		imgui.EndPopup()
	}

	if removePrompt.open {
		imgui.OpenPopup("Remove Handler###RemoveHandler")
		removePrompt.open = false
	}
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if imgui.BeginPopupModal("Remove Handler###RemoveHandler", nil, {.NoTitleBar, .AlwaysAutoResize}) {
		UI_PanelTitle(ICON_FA_TRIANGLE_EXCLAMATION, "Delete the handler too?")
		imgui.Dummy({0, 4})
		imgui.TextUnformatted(fmt.ctprintf("%s in %s contains code.", removePrompt.method, removePrompt.script))
		imgui.Dummy({0, 6})
		if UI_PrimaryButton("Delete Function", "signal.remove-code") {
			Code_RemoveSignalHandler(state, removePrompt.script, removePrompt.method, force = true)
			imgui.CloseCurrentPopup()
		}
		imgui.SameLine()
		if UI_Button("Keep Function", "signal.keep-code") || imgui.IsKeyPressed(.Escape, false) do imgui.CloseCurrentPopup()
		imgui.EndPopup()
	}
	Signals_DeclRender(state)
}
