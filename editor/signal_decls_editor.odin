package editor

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Declared signals in the editor (engine/signal_decls.odin): the Signals
// section lists them with the built-in events - connected the same way -
// and adds, edits and removes the node's own.
//
//   Add Signal         the dialog: name, the value's name and type, a description
//   a node's own       edit (rename) and delete; a rename or delete that
//                      reaches connections or scripts shows a preview first
//   its type's         locked here: "Edit the type" opens the type's document,
//                      where they are the type's own (renamed there, every
//                      scene's nodes of the type follow, saved at once)
//   its script's       ---@signal lines: open the script at the line
//   Emit               while simulating: raise it now (with a value)
//
// Names its script emits that nothing declares are listed with Declare.
// ============================================================================

// --- the Add / Edit Signal dialog ---------------------------------------------------------

@(private = "file")
Decl_Dialog :: struct {
	open:    bool,
	node:    ^e.Node,
	editing: string, // (heap) the signal being edited; "" = a new one
	name:    [65]u8,
	param:   [65]u8,
	desc:    [256]u8,
	typeIdx: i32,
	focus:   bool,
}

@(private = "file")
ddlg: Decl_Dialog

@(private = "file")
buf_str :: proc(b: []u8) -> string {return strings.trim_space(string(cstring(raw_data(b))))}

@(private = "file")
buf_set :: proc(b: []u8, s: string) {
	for &c in b do c = 0
	copy(b[:len(b) - 1], s)
}

// Signals_OpenDeclDialog: Add Signal (editing "") or Edit Signal on a node;
// `preset`: a name to start a new one with (Declare).
Signals_OpenDeclDialog :: proc(state: ^EditorState, node: ^e.Node, editing := "", preset := "", presetValue := false) {
	if ddlg.editing != "" do delete(ddlg.editing)
	ddlg = {}
	ddlg.open = true
	ddlg.focus = true
	ddlg.node = node
	if editing != "" {
		ddlg.editing = strings.clone(editing)
		if i := e.Node_FindOwnSignal(node, editing); i >= 0 {
			s := node.signals[i]
			buf_set(ddlg.name[:], s.name)
			buf_set(ddlg.param[:], s.param)
			buf_set(ddlg.desc[:], s.description)
			for t, k in e.SIGNAL_TYPES do if t == s.type do ddlg.typeIdx = i32(k)
		}
	} else {
		buf_set(ddlg.name[:], preset)
		buf_set(ddlg.param[:], "value" if presetValue else "")
	}
}

@(private = "file")
decl_from_dialog :: proc() -> e.Signal_Decl {
	t := e.SIGNAL_TYPES[ddlg.typeIdx] if ddlg.typeIdx >= 0 && int(ddlg.typeIdx) < len(e.SIGNAL_TYPES) else "any"
	return {
		name        = buf_str(ddlg.name[:]),
		param       = buf_str(ddlg.param[:]),
		type        = "" if t == "any" else t,
		description = buf_str(ddlg.desc[:]),
	}
}

// Signal_DeclProblem: why a signal can't be declared on a node ("" = it can).
Signal_DeclProblem :: proc(node: ^e.Node, d: e.Signal_Decl, editing := "") -> string {
	if ok, problem := e.Signal_IsValidName(d.name); !ok do return problem
	if !e.Signal_IsValidParam(d.param) do return "the value's name: letters, digits and _ (it can't start with a digit)"
	if d.name == editing do return ""
	if e.Node_IsBuiltinEvent(node, d.name) do return fmt.tprintf("%s already raises %s (a built-in event)", node.name, d.name)
	if e.Node_HasSignal(node, d.name) do return fmt.tprintf("%s already has a signal %s", node.name, d.name)
	return ""
}

@(private = "file")
decl_dialog_render :: proc(state: ^EditorState) {
	if ddlg.open {
		imgui.OpenPopup("Signal###SignalDecl")
		ddlg.open = false
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if !imgui.BeginPopupModal("Signal###SignalDecl", nil, {.NoTitleBar, .AlwaysAutoResize}) do return
	W :: f32(420)
	defer imgui.EndPopup()
	node := ddlg.node
	if !e.Node_IsAlive(node) || state.activeScene == nil {
		imgui.CloseCurrentPopup()
		return
	}
	UI_PanelTitle(ICON_FA_BOLT, fmt.tprintf("%s signal on %s", "Edit" if ddlg.editing != "" else "Add a", node.name))
	imgui.Dummy({0, 4})
	UI_DimText("Name")
	imgui.SetNextItemWidth(W)
	if ddlg.focus {
		imgui.SetKeyboardFocusHere()
		ddlg.focus = false
	}
	imgui.InputTextWithHint("##sd_name", "health_changed", cstring(raw_data(ddlg.name[:])), len(ddlg.name), {})
	Drive_Item("signal-decl.name")
	UI_Tooltip("What emit and connect use: lowercase, digits and _ (health_changed)")
	UI_DimText("Value")
	imgui.SetNextItemWidth(W * 0.6)
	imgui.InputTextWithHint("##sd_param", "none", cstring(raw_data(ddlg.param[:])), len(ddlg.param), {})
	Drive_Item("signal-decl.param")
	UI_Tooltip("The value's name (handlers get it first, then the source node); empty for a signal with no value")
	imgui.SameLine()
	imgui.SetNextItemWidth(W * 0.4 - imgui.GetStyle().ItemSpacing.x)
	if imgui.BeginCombo("##sd_type", strings.clone_to_cstring(e.SIGNAL_TYPES[ddlg.typeIdx], context.temp_allocator), {}) {
		for t, k in e.SIGNAL_TYPES {
			if imgui.Selectable(strings.clone_to_cstring(t, context.temp_allocator), ddlg.typeIdx == i32(k)) do ddlg.typeIdx = i32(k)
			Drive_Item(fmt.tprintf("signal-decl.type:%s", t))
		}
		imgui.EndCombo()
	}
	Drive_Item("signal-decl.type")
	UI_Tooltip("The value's type: the code editor checks handlers with it")
	UI_DimText("Description")
	imgui.SetNextItemWidth(W)
	imgui.InputTextWithHint("##sd_desc", "Health went up or down", cstring(raw_data(ddlg.desc[:])), len(ddlg.desc), {})
	Drive_Item("signal-decl.description")
	d := decl_from_dialog()
	problem := Signal_DeclProblem(node, d, ddlg.editing)
	imgui.Dummy({0, 2})
	if problem != "" && d.name != "" {
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.PushTextWrapPos(imgui.GetCursorPosX() + W)
		imgui.TextWrapped("%s", strings.clone_to_cstring(problem, context.temp_allocator))
		imgui.PopTextWrapPos()
		imgui.PopStyleColor()
	} else if d.name != "" {
		UI_DimText(fmt.tprintf("self.node:emit(\"%s\"%s)", d.name, fmt.tprintf(", %s", d.param) if d.param != "" else ""))
	}
	imgui.Dummy({0, 4})
	imgui.BeginDisabled(problem != "")
	ok := UI_PrimaryButton("Save" if ddlg.editing != "" else "Add", "signal-decl.ok", {110, 0}) || (problem == "" && imgui.IsKeyPressed(.Enter, false))
	imgui.EndDisabled()
	imgui.SameLine()
	if UI_Button("Cancel", "signal-decl.cancel", {110, 0}) || imgui.IsKeyPressed(.Escape, false) {
		imgui.CloseCurrentPopup()
		return
	}
	if ok && problem == "" {
		imgui.CloseCurrentPopup()
		if ddlg.editing == "" {
			Editor_RecordUndo(state, fmt.tprintf("Add signal %s", d.name))
			e.Node_AddSignal(node, d)
			Lua_MarkProjectTypesDirty()
			Editor_Log(state, .Info, "%s has a signal %s now: self.node:emit(\"%s\"%s)", node.name, d.name, d.name, ", value" if d.param != "" else "")
		} else if d.name == ddlg.editing {
			Editor_RecordUndo(state, fmt.tprintf("Edit signal %s", d.name))
			e.Node_SetSignal(node, ddlg.editing, d)
			Lua_MarkProjectTypesDirty()
		} else {
			Signals_BeginChange(state, node, ddlg.editing, d, false)
		}
	}
}

// --- rename and delete --------------------------------------------------------------------

@(private = "file")
Change_File :: struct {
	rel:   string, // (heap)
	count: int,
}

@(private = "file")
Script_Hit :: struct {
	rel:     string, // (heap)
	line:    int,    // 0-based
	text:    string, // (heap) the line as it is
	checked: bool,
}

@(private = "file")
Signal_Change :: struct {
	open:      bool,
	remove:    bool,
	node:      ^e.Node,
	old:       string,         // (heap)
	decl:      e.Signal_Decl,  // (heap) the new declaration (rename)
	typeRel:   string,         // (heap) a type's signal (its document); "" = the node's own
	family:    [dynamic]string, // (heap) the type and the types built on it
	local:     int,            // connections in open documents
	files:     [dynamic]Change_File,
	hits:      [dynamic]Script_Hit,
}

@(private = "file")
chg: Signal_Change

@(private = "file")
chg_clear :: proc() {
	delete(chg.old)
	e.Signal_DeclDelete(chg.decl)
	delete(chg.typeRel)
	for f in chg.family do delete(f)
	delete(chg.family)
	for f in chg.files do delete(f.rel)
	delete(chg.files)
	for h in chg.hits {delete(h.rel); delete(h.text)}
	delete(chg.hits)
	chg = {}
}

// signal_type_doc: the node is the type being edited in its own document
// (its signals are the type's).
signal_type_doc :: proc(state: ^EditorState, node: ^e.Node) -> bool {
	return node != nil && state.activeScene != nil && node.customType != "" && Editor_IsCustomNodeDoc(state, state.activeScene) && node.customType == state.activeScene.filePath
}

// Signals_BeginChange: rename (decl) or delete (remove) the node's own
// signal `old` - at once when nothing else uses it, else the preview.
Signals_BeginChange :: proc(state: ^EditorState, node: ^e.Node, old: string, decl: e.Signal_Decl, remove: bool) {
	chg_clear()
	chg.node = node
	chg.remove = remove
	chg.old = strings.clone(old)
	chg.decl = e.Signal_DeclClone(decl)
	ctx := &state.game.gameContext
	if signal_type_doc(state, node) {
		chg.typeRel = strings.clone(node.customType)
		append(&chg.family, strings.clone(node.customType))
		if t, _ := e.CustomNode_Get(ctx, node.customType); t != nil {
			name := strings.clone(t.name, context.temp_allocator)
			for x in e.CustomNodes_All(ctx) do if x.path != node.customType && e.CustomNode_Inherits(x, name, ctx) do append(&chg.family, strings.clone(x.path))
		}
	}
	// Connections in the open documents.
	for n in signal_change_nodes(state) do for c in n.signalConnections do if c.signal == old && c.node == nil do chg.local += 1
	// Other files (a type's signal: every scene and component with nodes of it).
	if chg.typeRel != "" {
		open := signal_open_files(state)
		for f in Editor_ListProjectFiles(state, "", {".scene.json", ".component.json"}) {
			if slice.contains(open, f) do continue
			if n := signal_conns_in_file(state, f, chg.family[:], old); n > 0 do append(&chg.files, Change_File{strings.clone(f), n})
		}
	}
	// Scripts using the name.
	for rel in Editor_ListProjectFiles(state, "", {".lua"}) {
		if strings.has_prefix(rel, ".") do continue
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		data, err := os.read_entire_file(full, context.temp_allocator)
		if err != nil || !strings.contains(string(data), old) do continue
		for line, i in strings.split_lines(string(data), context.temp_allocator) {
			if signal_line_uses(line, old) {
				global := strings.contains(line, "Events.") // (a global event of the same name)
				append(&chg.hits, Script_Hit{strings.clone(rel), i, strings.clone(strings.trim_space(line)), !global})
			}
		}
	}
	if chg.local == 0 && len(chg.files) == 0 && len(chg.hits) == 0 {
		signal_change_apply(state)
		chg_clear()
		return
	}
	chg.open = true
}

// signal_change_nodes: the nodes whose connections a change reaches - the
// node (its own signal), or every node of the type's family in the open
// documents.
@(private = "file")
signal_change_nodes :: proc(state: ^EditorState) -> []^e.Node {
	out := make([dynamic]^e.Node, context.temp_allocator)
	if chg.typeRel == "" {
		if e.Node_IsAlive(chg.node) do append(&out, chg.node)
		return out[:]
	}
	for _, s in state.game.sceneManager.scenes {
		if s == nil || !s.isLoaded || s.manager == nil do continue
		for n in s.manager.nodes do if n != nil && !n.removing && slice.contains(chg.family[:], n.customType) do append(&out, n)
	}
	return out[:]
}

@(private = "file")
signal_open_files :: proc(state: ^EditorState) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	for _, s in state.game.sceneManager.scenes do if s != nil && s.isLoaded && s.filePath != "" do append(&out, s.filePath)
	return out[:]
}

// signal_conns_in_file: connections of `signal` on nodes of the family in a
// scene / component file.
@(private = "file")
signal_conns_in_file :: proc(state: ^EditorState, rel: string, family: []string, signal: string) -> int {
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	data, err := os.read_entire_file(full, context.temp_allocator)
	if err != nil || !strings.contains(string(data), signal) do return 0
	val, perr := json.parse(data, allocator = context.temp_allocator)
	if perr != .None do return 0
	count := 0
	walk :: proc(v: json.Value, family: []string, signal: string, count: ^int) {
		obj, isObj := v.(json.Object)
		if !isObj do return
		if t, has := obj[e.CUSTOM_NODE_KEY].(json.String); has && slice.contains(family, string(t)) {
			if conns, ok := obj["connections"].(json.Array); ok do for c in conns {
				if co, isObj := c.(json.Object); isObj && string(co["signal"].(json.String) or_else "") == signal do count^ += 1
			}
		}
		if kids, has := obj["children"].(json.Array); has do for k in kids do walk(k, family, signal, count)
		if root, has := obj["root"]; has do walk(root, family, signal, count)
	}
	walk(val, family, signal, &count)
	return count
}

// signal_line_uses: a script line using signal `name` - emit / connect of
// it, its on_<name> handler, its ---@signal line.
@(private = "file")
signal_line_uses :: proc(line, name: string) -> bool {
	for call in ([]string{"emit(", "connect("}) {
		for q in ([]string{"\"", "'"}) {
			if strings.contains(line, fmt.tprintf("%s%s%s%s", call, q, name, q)) do return true
		}
	}
	if handler_index(line, name) >= 0 do return true
	if d, ok := e.Script_ParseSignalLine(line); ok && d.name == name do return true
	return false
}

// handler_index: where `:on_<name>(` / `.on_<name>(` starts in a line (-1).
@(private = "file")
handler_index :: proc(line, name: string) -> int {
	h := fmt.tprintf("on_%s(", name)
	from := 0
	for {
		i := strings.index(line[from:], h)
		if i < 0 do return -1
		i += from
		if i > 0 && (line[i - 1] == ':' || line[i - 1] == '.') do return i
		from = i + 1
	}
}

// signal_line_renamed: a script line with `old` renamed to `new`.
@(private = "file")
signal_line_renamed :: proc(line, old, new: string) -> string {
	out := line
	for call in ([]string{"emit(", "connect("}) {
		for q in ([]string{"\"", "'"}) {
			out, _ = strings.replace_all(out, fmt.tprintf("%s%s%s%s", call, q, old, q), fmt.tprintf("%s%s%s%s", call, q, new, q), context.temp_allocator)
		}
	}
	for {
		i := handler_index(out, old)
		if i < 0 do break
		out = fmt.tprintf("%son_%s(%s", out[:i], new, out[i + len("on_") + len(old) + 1:])
	}
	if d, ok := e.Script_ParseSignalLine(out); ok && d.name == old {
		at := strings.index(out, "---@signal")
		rest := out[at + len("---@signal"):]
		j := strings.index(rest, old)
		out = fmt.tprintf("%s%s%s", out[:at + len("---@signal") + j], new, rest[j + len(old):])
	}
	return out
}

// signal_change_apply makes the change: the declaration, the connections
// (open documents, other files), the checked script lines; a type's
// document is saved.
@(private = "file")
signal_change_apply :: proc(state: ^EditorState) {
	node := chg.node
	if !e.Node_IsAlive(node) do return
	old, new := chg.old, chg.decl.name
	Editor_RecordUndo(state, fmt.tprintf("%s signal %s", "Delete" if chg.remove else "Rename", old))
	if chg.remove do e.Node_RemoveSignal(node, old)
	else do e.Node_SetSignal(node, old, chg.decl)
	conns := 0
	for n in signal_change_nodes(state) {
		conns += e.Node_RemoveConnectionsOf(n, old) if chg.remove else e.Node_RenameConnections(n, old, new)
	}
	files := 0
	for f in chg.files {
		Editor_RecordFileUndo(state, f.rel, fmt.tprintf("%s signal %s", "Delete" if chg.remove else "Rename", old))
		if signal_edit_file(state, f.rel) do files += 1
	}
	// Scripts (a rename: the checked lines).
	scripts := 0
	if !chg.remove {
		byFile := make(map[string][dynamic]int, 8, context.temp_allocator)
		for h in chg.hits do if h.checked {
			if h.rel not_in byFile do byFile[h.rel] = make([dynamic]int, context.temp_allocator)
			append(&byFile[h.rel], h.line)
		}
		for rel, lines in byFile {
			if code_doc_dirty(state, rel) {
				Editor_Log(state, .Warn, "%s has unsaved edits: rename %s there yourself", rel, old)
				continue
			}
			full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
			data, err := os.read_entire_file(full, context.temp_allocator)
			if err != nil do continue
			all := strings.split(string(data), "\n", context.temp_allocator)
			for ln in lines do if ln < len(all) do all[ln] = signal_line_renamed(all[ln], old, new)
			Editor_RecordFileUndo(state, rel, fmt.tprintf("Rename signal %s", old))
			if os.write_entire_file(full, transmute([]u8)strings.join(all, "\n", context.temp_allocator)) == nil do scripts += 1
		}
	}
	if chg.typeRel != "" && Editor_IsCustomNodeDoc(state, state.activeScene) {
		Editor_SaveCustomNodeDoc(state, state.activeScene) // (the scenes' nodes of it follow it now)
	}
	Lua_MarkProjectTypesDirty()
	if chg.remove {
		Editor_Log(state, .Info, "Deleted the signal %s (%d connection(s) removed%s)", old, conns + count_files(), fmt.tprintf(", %d file(s)", files) if files > 0 else "")
	} else {
		Editor_Log(state, .Info, "Renamed the signal %s to %s (%d connection(s), %d file(s), %d script(s))", old, new, conns, files, scripts)
	}
}

@(private = "file")
count_files :: proc() -> int {
	n := 0
	for f in chg.files do n += f.count
	return n
}

// code_doc_dirty: a script open in the Code tab with unsaved edits.
@(private = "file")
code_doc_dirty :: proc(state: ^EditorState, rel: string) -> bool {
	for doc in GlobalCode.docs {
		if doc != nil && doc.rel == rel do return doc.buffer.version != doc.savedVersion
	}
	return false
}

// signal_edit_file: a scene / component file loaded, the family's
// connections of the signal renamed or removed, written again.
@(private = "file")
signal_edit_file :: proc(state: ^EditorState, rel: string) -> bool {
	if Editor_FormatBlocksSave(state, rel) do return false // (from a newer Rayzr: #326)
	ctx := &state.game.gameContext
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	data, err := os.read_entire_file(full, context.temp_allocator)
	if err != nil do return false
	scratch := new(e.Scene)
	e.InitializeScene(scratch)
	defer {
		e.TerminateScene(scratch)
		free(scratch)
	}
	isComp := strings.has_suffix(rel, ".component.json")
	root: ^e.Node
	if isComp {
		root = e.Scene_InstantiateNodeFromJSON(scratch, data, scratch.rootNode, ctx)
		if root == nil do return false
	} else if !e.Scene_InstantiateFromJSON(scratch, data, ctx) {
		return false
	}
	e.ProcessNodeQueues(scratch.manager, ctx)
	for n in scratch.manager.nodes {
		if n == nil || !slice.contains(chg.family[:], n.customType) do continue
		if chg.remove do e.Node_RemoveConnectionsOf(n, chg.old)
		else do e.Node_RenameConnections(n, chg.old, chg.decl.name)
	}
	out := e.Component_FileJSON(root, scratch.manager, context.temp_allocator) if isComp else e.Scene_SerializeToJSON(scratch, context.temp_allocator)
	return os.write_entire_file(full, transmute([]u8)out) == nil
}

@(private = "file")
change_render :: proc(state: ^EditorState) {
	if chg.open && !imgui.IsPopupOpen("Signal Change###SignalChange") do imgui.OpenPopup("Signal Change###SignalChange")
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	imgui.SetNextWindowSizeConstraints({560, 0}, {760, 640})
	if !imgui.BeginPopupModal("Signal Change###SignalChange", nil, {.NoTitleBar, .AlwaysAutoResize}) do return
	defer imgui.EndPopup()
	close :: proc() {
		imgui.CloseCurrentPopup()
		chg_clear()
	}
	if !chg.open || !e.Node_IsAlive(chg.node) {
		close()
		return
	}
	if chg.remove {
		UI_PanelTitle(ICON_FA_TRASH, fmt.tprintf("Delete the signal %s?", chg.old))
	} else {
		UI_PanelTitle(ICON_FA_PEN, fmt.tprintf("Rename %s to %s", chg.old, chg.decl.name))
	}
	imgui.Dummy({0, 4})
	verb := "removed" if chg.remove else "renamed"
	if chg.local > 0 {
		imgui.BulletText("%s", fmt.ctprintf("%d connection(s) in the open documents: %s", chg.local, verb))
		Drive_Item("signal-change.local")
	}
	for f in chg.files {
		imgui.BulletText("%s", fmt.ctprintf("%s - %d connection(s): %s (the file is saved; it can be undone)", f.rel, f.count, verb))
	}
	if chg.typeRel != "" do UI_DimText("The type is saved: every node of it follows.")
	if len(chg.hits) > 0 {
		imgui.Dummy({0, 4})
		if chg.remove {
			UI_DimText("Scripts still using it (left as they are; an emit of it warns):")
		} else {
			UI_DimText("Script lines (the checked ones are renamed; Events.* lines are global events):")
		}
		if imgui.BeginChild("##sc_hits", {600, min(f32(len(chg.hits)) * 26 + 8, 240)}, {.Borders}, {}) {
			for &h, i in chg.hits {
				imgui.PushIDInt(i32(i))
				if !chg.remove {
					imgui.Checkbox("##hit", &h.checked)
					Drive_Item(fmt.tprintf("signal-change.hit:%s:%d", filepath.base(h.rel), h.line + 1))
					imgui.SameLine()
				}
				imgui.TextUnformatted(fmt.ctprintf("%s:%d  %s", h.rel, h.line + 1, h.text))
				if imgui.IsItemClicked() do Editor_OpenScript(state, h.rel, h.line + 1, 0)
				imgui.PopID()
			}
		}
		imgui.EndChild()
	}
	imgui.Dummy({0, 6})
	if UI_PrimaryButton("Delete" if chg.remove else "Rename", "signal-change.ok", {120, 0}) {
		signal_change_apply(state)
		close()
		return
	}
	imgui.SameLine()
	if UI_Button("Cancel", "signal-change.cancel", {110, 0}) || imgui.IsKeyPressed(.Escape, false) do close()
}

// --- Emit (while simulating) ----------------------------------------------------------------

@(private = "file")
Emit_Popup :: struct {
	open:  bool,
	node:  ^e.Node,
	name:  string, // (heap)
	type:  string, // (heap)
	value: [128]u8,
}

@(private = "file")
emitp: Emit_Popup

// Signals_Emit raises a signal of a node now (Simulate), its value read
// from text by the signal's type.
Signals_Emit :: proc(state: ^EditorState, node: ^e.Node, name, type, text: string) {
	value: e.EventValue
	t := strings.trim_space(text)
	switch type {
	case "number":
		if f, ok := strconv.parse_f64(t); ok do value = f
	case "integer":
		if n, ok := strconv.parse_int(t); ok do value = n
	case "boolean":
		value = t == "true" || t == "1"
	case "string":
		value = strings.clone(t, context.temp_allocator)
	case "node":
		if state.activeScene != nil && t != "" do value = e.Scene_FindNodeByName(state.activeScene, t)
	case "Vec2":
		parts := strings.split(t, ",", context.temp_allocator)
		if len(parts) == 2 {
			x, _ := strconv.parse_f32(strings.trim_space(parts[0]))
			y, _ := strconv.parse_f32(strings.trim_space(parts[1]))
			value = [2]f32{x, y}
		}
	case:
		if t == "" {
		} else if n, ok := strconv.parse_int(t); ok {
			value = n
		} else if f, ok := strconv.parse_f64(t); ok {
			value = f
		} else if t == "true" || t == "false" {
			value = t == "true"
		} else {
			value = strings.clone(t, context.temp_allocator)
		}
	}
	e.Script_DispatchEvent(node, name, value, &state.game.gameContext)
	Editor_Log(state, .Info, "Emitted %s.%s(%s)", node.name, name, t)
}

@(private = "file")
emit_open :: proc(state: ^EditorState, node: ^e.Node, s: e.Signal_Info) {
	if s.param == "" {
		Signals_Emit(state, node, s.name, s.type, "")
		return
	}
	delete(emitp.name)
	delete(emitp.type)
	emitp = {open = true, node = node, name = strings.clone(s.name), type = strings.clone(s.type)}
}

@(private = "file")
emit_render :: proc(state: ^EditorState) {
	if emitp.open {
		imgui.OpenPopup("##signal_emit")
		emitp.open = false
	}
	if !imgui.BeginPopup("##signal_emit") do return
	defer imgui.EndPopup()
	if !e.Node_IsAlive(emitp.node) || !state.isSimulating {
		imgui.CloseCurrentPopup()
		return
	}
	hint := "0" if emitp.type == "number" || emitp.type == "integer" else "true / false" if emitp.type == "boolean" else "a node's name" if emitp.type == "node" else "x, y" if emitp.type == "Vec2" else "a value"
	UI_DimText(fmt.tprintf("Emit %s (%s)", emitp.name, emitp.type if emitp.type != "" else "any"))
	imgui.SetNextItemWidth(200)
	if imgui.IsWindowAppearing() do imgui.SetKeyboardFocusHere()
	enter := imgui.InputTextWithHint("##emit_value", strings.clone_to_cstring(hint, context.temp_allocator), cstring(raw_data(emitp.value[:])), len(emitp.value), {.EnterReturnsTrue})
	Drive_Item("signal-emit.value")
	imgui.SameLine()
	if UI_PrimaryButton("Emit", "signal-emit.ok") || enter {
		Signals_Emit(state, emitp.node, emitp.name, emitp.type, string(cstring(raw_data(emitp.value[:]))))
		imgui.CloseCurrentPopup()
	}
}

// Signals_DeclRender draws the signal dialogs (each frame).
Signals_DeclRender :: proc(state: ^EditorState) {
	decl_dialog_render(state)
	change_render(state)
	emit_render(state)
}

// --- the Signals section's rows -----------------------------------------------------------

// Signals_RowButtons: the buttons at the right of a signal's row (drawn
// right to left from `right`): the origin's, Emit while simulating.
// Returns true when the node's signals changed (stop drawing the list).
Signals_RowButtons :: proc(state: ^EditorState, node: ^e.Node, s: e.Signal_Info, right: f32) -> bool {
	x := right
	place :: proc(x: ^f32) {
		x^ -= 26
		imgui.SameLine(x^)
	}
	if state.isSimulating {
		place(&x)
		if UI_IconButton(ICON_FA_PLAY, fmt.tprintf("insp.signal-emit:%s", s.name), "Emit it now", size = 24) do emit_open(state, node, s)
	}
	switch s.origin {
	case .Builtin:
	case .Node:
		place(&x)
		if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("insp.signal-delete:%s", s.name), "Delete this signal", size = 24) {
			Signals_BeginChange(state, node, s.name, {}, true)
			return true
		}
		place(&x)
		if UI_IconButton(ICON_FA_PEN, fmt.tprintf("insp.signal-edit:%s", s.name), "Edit (rename, its value, description)", size = 24) {
			Signals_OpenDeclDialog(state, node, s.name)
		}
	case .Type:
		place(&x)
		tname := s.from
		if t, _ := e.CustomNode_Get(&state.game.gameContext, s.from); t != nil do tname = t.name
		if UI_IconButton(ICON_FA_LOCK, fmt.tprintf("insp.signal-type:%s", s.name), fmt.tprintf("The %s type's signal: edit the type to change it", tname), size = 24) {
			Editor_OpenCustomNodeType(state, s.from)
			return true
		}
	case .Script:
		place(&x)
		rel := asset_rel_editor(state, s.from)
		if UI_IconButton(ICON_FA_FILE_CODE, fmt.tprintf("insp.signal-script:%s", s.name), fmt.tprintf("Declared in %s (line %d): edit it there", rel, s.line), size = 24) {
			Editor_OpenScript(state, rel, s.line, 0)
		}
	}
	return false
}

// Signals_RowsWidth: the room a row's buttons take (besides Connect).
Signals_RowsWidth :: proc(state: ^EditorState, s: e.Signal_Info) -> f32 {
	n: f32 = 1 if state.isSimulating else 0
	switch s.origin {
	case .Builtin:
	case .Node:   n += 2
	case .Type:   n += 1
	case .Script: n += 1
	}
	return n * 26
}

// Undeclared_Emit: a name the node's script emits on its node that no
// signal declares, and whether it passes a value.
Undeclared_Emit :: struct {
	name:     string,
	hasValue: bool,
}

// Signals_Undeclared: what the node's script emits on its node undeclared (temp).
Signals_Undeclared :: proc(node: ^e.Node, script: string) -> []Undeclared_Emit {
	out := make([dynamic]Undeclared_Emit, context.temp_allocator)
	if script == "" do return out[:]
	rest := script
	outer: for {
		i := strings.index(rest, "node:emit(")
		if i < 0 do break
		rest = rest[i + len("node:emit("):]
		t := strings.trim_left_space(rest)
		if len(t) < 2 || (t[0] != '"' && t[0] != '\'') do continue
		j := strings.index_byte(t[1:], t[0])
		if j <= 0 do continue
		name := t[1:1 + j]
		if ok, _ := e.Signal_IsValidName(name); !ok do continue
		if e.Node_HasSignal(node, name) do continue
		for x in out do if x.name == name do continue outer
		after := strings.trim_left_space(t[2 + j:])
		append(&out, Undeclared_Emit{strings.clone(name, context.temp_allocator), strings.has_prefix(after, ",")})
	}
	return out[:]
}

// Editor_CustomTypeName: a custom node type's name (its path when it can't
// be loaded).
Editor_CustomTypeName :: proc(state: ^EditorState, rel: string) -> string {
	if t, _ := e.CustomNode_Get(&state.game.gameContext, rel); t != nil do return t.name
	return rel
}
