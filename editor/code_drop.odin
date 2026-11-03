package editor

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import "core:time"
import buf "../odin_editor/buffer"
import e "../engine"
import imgui "lib/imgui"
import rl "vendor:raylib"

// ============================================================================
// Dragging assets and nodes into a script.
//
// Drop an asset from the Assets panel onto the code: inserts its path as a
// string ("textures/ship.png"). Hold Cmd/Ctrl while dropping to declare it
// as an exported asset property instead:
//
//   ship = { type = "texture", default = "textures/ship.png" },
//
// which the Inspector edits with an asset picker. Dropping a node from the
// scene tree inserts `self.node:get_node("<relative path>")` (relative to a
// node that uses this script), or `Scene.find_node("Name")`. Dropping an
// Inspector property's name inserts `<node>:get_property("<path>")` - with
// Shift, `<node>:set_property("<path>", <its current value>)`.
// ============================================================================

// Script_AssetKind: the script property type for an asset path.
Script_AssetKind :: proc(rel: string) -> string {
	switch Asset_KindOf(rel) {
	case .Texture, .Aseprite: return "texture" // (an Aseprite path is an image too: its first frame)
	case .Audio:     return "audio"
	case .Scene:     return "scene"
	case .Script:    return "script"
	case .Component: return "component"
	case .Level:     return "level"
	case .Shader, .Vector, .Generator, .CustomNode: return "file"
	case .Resource:  return "resource"
	case .Package, .Other:
	}
	if strings.has_suffix(strings.to_lower(rel, context.temp_allocator), ".ldtk") do return "level"
	return "file"
}

// Script_AssetFiles lists project files matching an asset property type.
Script_AssetFiles :: proc(state: ^EditorState, kind: string) -> []string {
	switch kind {
	case "texture":   return Editor_ListProjectFiles(state, "", TEXTURE_EXTS)
	case "audio":     return Editor_ListProjectFiles(state, "", AUDIO_EXTS)
	case "scene":     return Editor_ListProjectFiles(state, "", {".scene.json"})
	case "script":    return Editor_ListProjectFiles(state, "", {".lua"})
	case "component": return Editor_ListProjectFiles(state, "", {".component.json"})
	case "level":     return Editor_ListProjectFiles(state, "", {".ldtk"})
	case "resource":  return Editor_ListProjectFiles(state, "resources", {e.RESOURCE_EXT})
	}
	return Editor_ListProjectFiles(state, "", {".png", ".jpg", ".wav", ".ogg", ".mp3", ".json", ".lua", ".ldtk"})
}



@(private = "file")
snake_ident :: proc(s: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	prevLower := false
	for ch in s {
		switch {
		case ch >= 'A' && ch <= 'Z':
			if prevLower do strings.write_byte(&sb, '_')
			strings.write_rune(&sb, ch + 32)
			prevLower = false
		case (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9'):
			if strings.builder_len(sb) == 0 && ch >= '0' && ch <= '9' do strings.write_byte(&sb, '_')
			strings.write_rune(&sb, ch)
			prevLower = true
		case:
			if strings.builder_len(sb) > 0 do strings.write_byte(&sb, '_')
			prevLower = false
		}
	}
	return strings.trim_right(strings.to_string(sb), "_")
}

// Code_DropAsset inserts an asset reference at `pos` (or, as a property,
// into the script's properties table).
Code_DropAsset :: proc(doc: ^Code_Doc, rel: string, pos: buf.Position, asProperty: bool) {
	b := &doc.buffer
	group := buf.buffer_next_group(b)
	if !asProperty {
		text := fmt.tprintf("%q", rel)
		// Already inside a string: just the path.
		line := buf.buffer_line_str(b, pos.line)
		if pos.col > 0 && pos.col < len(line) && (line[pos.col - 1] == '"' || line[pos.col - 1] == '\'') do text = rel
		end := buf.buffer_insert_text(b, pos, text, group)
		code_set_single_cursor(b, end, false)
		doc.scrollToCursor = true
		return
	}
	kind := Script_AssetKind(rel)
	text := buf.buffer_to_string(b, context.temp_allocator)
	cls := Script_ClassName(text)
	base := snake_ident(filepath.stem(filepath.stem(rel)))
	if base == "" do base = kind
	name := base
	for i := 2; strings.contains(text, fmt.tprintf("    %s = {{", name)) || strings.contains(text, fmt.tprintf("\t%s = {{", name)); i += 1 {
		name = fmt.tprintf("%s_%d", base, i)
	}
	indent := "\t" if doc.useTabs else "    "
	entry := fmt.tprintf("%s%s = {{ type = %q, default = %q }},\n", indent, name, kind, rel)
	// After `Cls.properties = {`.
	header := fmt.tprintf("%s.properties = {{", cls) if cls != "" else ".properties = {"
	for ln in 0 ..< buf.buffer_line_count(b) {
		l := strings.trim_space(buf.buffer_line_str(b, ln))
		if cls != "" && strings.has_prefix(l, header) || cls == "" && strings.contains(l, header) {
			end := buf.buffer_insert_text(b, {ln + 1, 0}, entry, group)
			code_set_single_cursor(b, {ln + 1, len(indent)}, false)
			b.cursors[0].sel = {anchor = {ln + 1, len(indent)}, active = true}
			b.cursors[0].pos = {ln + 1, len(indent) + len(name)}
			_ = end
			doc.scrollToCursor = true
			return
		}
	}
	// No properties table yet: create one after `local Cls = {}`.
	if cls == "" do return
	for ln in 0 ..< buf.buffer_line_count(b) {
		if strings.trim_space(buf.buffer_line_str(b, ln)) == fmt.tprintf("local %s = {{}}", cls) {
			block := fmt.tprintf("\n%s.properties = {{\n%s}}\n", cls, entry)
			buf.buffer_insert_text(b, {ln + 1, 0}, block, group)
			code_set_single_cursor(b, {ln + 3, len(indent)}, false)
			doc.scrollToCursor = true
			return
		}
	}
}

// Code_DropNode inserts a reference to a scene node, typed for the language
// server with the node's class (`---@type CharacterMoverNode`):
//   - on an empty line: a local declaration with the annotation above it;
//   - into an assignment (`local mover = |`, `self.body = |`): the
//     annotation goes above that line (unless one is there already);
//   - anywhere else (an argument...): an inline cast, `--[[@as Type]]`.
// Plain Nodes get no annotation (get_node returns Node already).
Code_DropNode :: proc(state: ^EditorState, doc: ^Code_Doc, node: ^e.Node, pos: buf.Position) {
	if state.activeScene == nil || node == nil do return
	if code_in_properties_table(&doc.buffer, pos.line) {
		code_add_node_property(state, doc, node, pos)
		return
	}
	expr := code_node_ref(state, doc, node, false)
	class := e.Node_TypeName(node)
	b := &doc.buffer
	if class == "Node" || pos.line >= buf.buffer_line_count(b) {
		code_insert(doc, pos, expr)
		return
	}
	// A copy: the buffer's line memory moves as text is inserted.
	line := strings.clone(buf.buffer_line_str(b, pos.line), context.temp_allocator)
	indent := line[:len(line) - len(strings.trim_left_space(line))]
	group := buf.buffer_next_group(b)
	end: buf.Position
	switch {
	case strings.trim_space(line) == "":
		name := snake_ident(node.name)
		if name == "" || code_lua_keyword(name) do name = "node"
		ind := code_blank_line_indent(b, pos.line)
		text := fmt.tprintf("%s---@type %s\n%slocal %s = %s", ind, class, ind, name, expr)
		// Replace the blank line's own whitespace with the computed indent.
		if len(line) > 0 do buf.buffer_delete_range(b, {pos.line, 0}, {pos.line, len(line)}, group)
		end = buf.buffer_insert_text(b, {pos.line, 0}, text, group)
	case code_is_assignment(line[:min(pos.col, len(line))]):
		pre := line[:min(pos.col, len(line))]
		if strings.has_suffix(pre, "=") do expr = strings.concatenate({" ", expr}, context.temp_allocator)
		end = buf.buffer_insert_text(b, pos, expr, group)
		above := strings.trim_space(buf.buffer_line_str(b, pos.line - 1)) if pos.line > 0 else ""
		if !strings.has_prefix(above, "---@type") {
			buf.buffer_insert_text(b, {pos.line, 0}, fmt.tprintf("%s---@type %s\n", indent, class), group)
			end.line += 1
		}
	case:
		end = buf.buffer_insert_text(b, pos, fmt.tprintf("%s --[[@as %s]]", expr, class), group)
	}
	code_set_single_cursor(b, end, false)
	doc.scrollToCursor = true
}

// code_blank_line_indent: the indent for code on a blank line - the
// previous non-blank line's, one level deeper after a block opener
// (`function ...)`, `then`, `do`, `repeat`, `{`).
@(private = "file")
code_blank_line_indent :: proc(b: ^buf.Buffer, line: int) -> string {
	for l := line - 1; l >= 0; l -= 1 {
		prev := strings.clone(buf.buffer_line_str(b, l), context.temp_allocator)
		t := strings.trim_space(prev)
		if t == "" do continue
		ind := prev[:len(prev) - len(strings.trim_left_space(prev))]
		unit := "\t" if strings.has_prefix(ind, "\t") else "    "
		opens := strings.has_suffix(t, "then") || strings.has_suffix(t, " do") || t == "do" || t == "repeat" || strings.has_suffix(t, "{") || t == "else" ||
			(strings.contains(t, "function") && strings.has_suffix(t, ")"))
		return strings.concatenate({ind, unit}, context.temp_allocator) if opens else ind
	}
	return ""
}

// code_in_properties_table: the line is inside `Cls.properties = { ... }`.
@(private = "file")
code_in_properties_table :: proc(b: ^buf.Buffer, line: int) -> bool {
	for l := line; l >= 0; l -= 1 {
		t := strings.trim_space(buf.buffer_line_str(b, l))
		if strings.contains(t, ".properties = {") || strings.contains(t, ".properties={") do return !strings.has_suffix(t, "}") || l == line
		if l < line && (t == "}" || strings.has_prefix(t, "function ") || strings.has_prefix(t, "local ")) do return false
	}
	return false
}

// A node property dropped into a script's properties table: set to that
// node once the script reloads with it.
@(private = "file")
pendingNodeProp: struct {
	owner:      ^e.Node,
	name, path: string,
	since:      time.Tick,
}

// code_add_node_property adds `<name> = { type = "node" },` on the line
// after the drop and remembers which node it should point at.
@(private = "file")
code_add_node_property :: proc(state: ^EditorState, doc: ^Code_Doc, node: ^e.Node, pos: buf.Position) {
	b := &doc.buffer
	name := snake_ident(node.name)
	if name == "" || code_lua_keyword(name) do name = "target"
	text := buf.buffer_to_string(b, context.temp_allocator)
	for i := 2; strings.contains(text, fmt.tprintf(" %s = {{", name)); i += 1 do name = fmt.tprintf("%s_%d", snake_ident(node.name), i)
	line := strings.clone(buf.buffer_line_str(b, pos.line), context.temp_allocator)
	indent := line[:len(line) - len(strings.trim_left_space(line))]
	at := pos.line + 1
	unit := "\t" if doc.useTabs else "    "
	if strings.contains(line, ".properties") do indent = strings.concatenate({indent, unit}, context.temp_allocator)
	if strings.trim_space(line) == "}" { // the closing brace: before it
		at = pos.line
		indent = strings.concatenate({indent, unit}, context.temp_allocator)
	}
	entry := fmt.tprintf("%s%s = {{ type = \"node\" }}, -- %s\n", indent, name, node.name)
	end := buf.buffer_insert_text(b, {at, 0}, entry, buf.buffer_next_group(b))
	code_set_single_cursor(b, {end.line - 1, len(indent) + len(name)}, false)
	doc.scrollToCursor = true
	if owner := code_script_owner(state, doc); owner != nil {
		delete(pendingNodeProp.name)
		delete(pendingNodeProp.path)
		pendingNodeProp = {owner, strings.clone(name), strings.clone(e.Node_RelativePath(state.activeScene.manager, owner, node)), time.tick_now()}
		Editor_Log(state, .Info, "Added the node property %s: save the script to set it to %s", name, node.name)
	}
}

// Code_ApplyPendingNodeProp (each frame): once the script has the dropped
// node property (saved, reloaded), point it at the node.
Code_ApplyPendingNodeProp :: proc(state: ^EditorState) {
	p := &pendingNodeProp
	if p.owner == nil do return
	if !e.Node_IsAlive(p.owner) || p.owner.scriptInstance == nil || time.tick_since(p.since) > 10 * time.Minute {
		p.owner = nil
		return
	}
	inst := cast(^e.ScriptInstance)p.owner.scriptInstance
	if _, has := inst.properties[p.name]; !has do return
	Editor_RecordUndo(state, fmt.tprintf("Set %s", p.name))
	e.ScriptInstance_SetProperty(inst, p.name, {type = .String, valString = p.path}, &state.game.scriptManager)
	p.owner = nil
}

// code_script_owner: a node that runs this script (the selection if it
// does, else the first in the scene).
code_script_owner :: proc(state: ^EditorState, doc: ^Code_Doc) -> ^e.Node {
	if state.activeScene == nil do return nil
	usesScript :: proc(state: ^EditorState, n: ^e.Node, doc: ^Code_Doc) -> bool {
		if n == nil || n.scriptInstance == nil do return false
		rel := asset_rel_editor(state, (cast(^e.ScriptInstance)n.scriptInstance).modulePath)
		return strings.has_suffix(doc.path, rel)
	}
	if usesScript(state, state.selectedNode, doc) do return state.selectedNode
	for n in state.activeScene.manager.nodes do if usesScript(state, n, doc) do return n
	return nil
}

// Code_GotoNode: Cmd+click on the string of a get_node / get_child /
// find_node call selects that node (true when the click was on one).
Code_GotoNode :: proc(state: ^EditorState, doc: ^Code_Doc, p: buf.Position) -> bool {
	if state.activeScene == nil || p.line >= buf.buffer_line_count(&doc.buffer) do return false
	line := buf.buffer_line_str(&doc.buffer, p.line)
	// The string literal around the click.
	open := -1
	for i := min(p.col, len(line)) - 1; i >= 0; i -= 1 do if line[i] == '"' || line[i] == '\'' {open = i; break}
	if open < 0 do return false
	close := strings.index_byte(line[open + 1:], line[open])
	if close < 0 || open + 1 + close < p.col do return false
	lit := line[open + 1:open + 1 + close]
	before := strings.trim_right_space(line[:open])
	mgr := state.activeScene.manager
	target: ^e.Node
	switch {
	case strings.has_suffix(before, "get_node("):
		owner := code_script_owner(state, doc)
		if owner == nil do return false
		target = e.Node_ResolvePath(mgr, owner, lit)
	case strings.has_suffix(before, "get_child("):
		owner := code_script_owner(state, doc)
		if owner == nil do return false
		for c in e.GetChildrenView(mgr, owner) do if c != nil && c.name == lit {target = c; break}
	case strings.has_suffix(before, "find_node("):
		target = e.Scene_FindNodeByName(state.activeScene, lit)
	case:
		return false
	}
	if target == nil {
		Editor_Log(state, .Warn, "No node at \"%s\" in this scene", lit)
		return true
	}
	Editor_SelectNode(state, target, false)
	state.cameraPos = target.globalPosition
	return true
}

// code_is_assignment: the line so far is a statement assigning a value
// (`local x =`, `self.body =`), the drop being its right-hand side.
@(private = "file")
code_is_assignment :: proc(pre: string) -> bool {
	t := strings.trim_space(pre)
	if !strings.has_suffix(t, "=") do return false
	t = strings.trim_right_space(t[:len(t) - 1])
	if len(t) == 0 do return false
	switch t[len(t) - 1] {
	case '=', '~', '<', '>': return false // ==, ~=, <=, >=
	}
	// Left side: `local a`, `a.b`, `self.c` - names, dots and brackets only.
	t = strings.trim_prefix(t, "local ")
	for ch in t do if !(ch == '_' || ch == '.' || ch == ':' || ch == '[' || ch == ']' || ch == '"' || ch == ' ' || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')) do return false
	return true
}

@(private = "file")
code_lua_keyword :: proc(s: string) -> bool {
	switch s {
	case "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while", "self":
		return true
	}
	return false
}

// Code_DropProperty inserts a property read - or, `set`, a write of its
// current value.
Code_DropProperty :: proc(state: ^EditorState, doc: ^Code_Doc, node: ^e.Node, path, value: string, set: bool, pos: buf.Position) {
	if state.activeScene == nil || node == nil do return
	ref := code_node_ref(state, doc, node, true)
	text := fmt.tprintf("%s:set_property(%q, %s)", ref, path, value) if set else fmt.tprintf("%s:get_property(%q)", ref, path)
	code_insert(doc, pos, text)
}

// code_insert_block inserts text whose later lines take the drop line's
// indentation (+1 level for an empty middle line, where the cursor goes).
@(private = "file")
code_insert_block :: proc(doc: ^Code_Doc, pos: buf.Position, text: string) {
	if !strings.contains(text, "\n") {
		code_insert(doc, pos, text)
		return
	}
	b := &doc.buffer
	line := strings.clone(buf.buffer_line_str(b, pos.line), context.temp_allocator)
	indent := line[:len(line) - len(strings.trim_left_space(line))]
	pos := pos
	if strings.trim_space(line) == "" {
		// An empty line: the indent of the code around it.
		indent = code_blank_line_indent(b, pos.line)
		if len(line) > 0 do buf.buffer_delete_range(b, {pos.line, 0}, {pos.line, len(line)}, buf.buffer_next_group(b))
		buf.buffer_insert_text(b, {pos.line, 0}, indent, buf.buffer_next_group(b))
		pos = {pos.line, len(indent)}
	}
	unit := "\t" if doc.useTabs else "    "
	lines := strings.split(text, "\n", context.temp_allocator)
	sb := strings.builder_make(context.temp_allocator)
	body := -1
	for l, i in lines {
		if i > 0 {
			strings.write_byte(&sb, '\n')
			strings.write_string(&sb, indent)
			if l == "" {strings.write_string(&sb, unit); body = i}
		}
		strings.write_string(&sb, l)
	}
	buf.buffer_insert_text(b, pos, strings.to_string(sb), buf.buffer_next_group(b))
	if body >= 0 do code_set_single_cursor(b, {pos.line + body, len(indent) + len(unit)}, false)
	doc.scrollToCursor = true
}

@(private = "file")
code_insert :: proc(doc: ^Code_Doc, pos: buf.Position, text: string) {
	b := &doc.buffer
	end := buf.buffer_insert_text(b, pos, text, buf.buffer_next_group(b))
	code_set_single_cursor(b, end, false)
	doc.scrollToCursor = true
}

// code_node_ref: Lua for a node seen from this script: `self.node:get_node(
// "<relative path>")` from a node that runs it (`self.node` for that node
// itself when `selfOk`), else `Scene.find_node("Name")`.
@(private = "file")
code_node_ref :: proc(state: ^EditorState, doc: ^Code_Doc, node: ^e.Node, selfOk: bool) -> string {
	mgr := state.activeScene.manager
	// A node that runs this script: the selection if it does, else any.
	owner: ^e.Node
	usesScript :: proc(state: ^EditorState, n: ^e.Node, doc: ^Code_Doc) -> bool {
		if n == nil || n.scriptInstance == nil do return false
		rel := asset_rel_editor(state, (cast(^e.ScriptInstance)n.scriptInstance).modulePath)
		return strings.has_suffix(doc.path, rel)
	}
	if usesScript(state, state.selectedNode, doc) do owner = state.selectedNode
	if owner == nil {
		for n in mgr.nodes do if usesScript(state, n, doc) {owner = n; break}
	}
	if owner != nil && owner == node && selfOk do return "self.node"
	if owner != nil do return fmt.tprintf("self.node:get_node(%q)", e.Node_RelativePath(mgr, owner, node))
	return fmt.tprintf("Scene.find_node(%q)", node.name)
}

// --- Dragging project names into a script (input actions, animations) -------

CODE_ITEM_PAYLOAD :: "RAYZR_CODE_ITEM"

Code_Item_Kind :: enum {
	Action,    // an input action: Input.is_action_pressed (Shift: is_action_down)
	Animation, // an AnimationPlayer's animation: animation_play
	Event,     // a node's event (Signals panel): a connect with its handler
}

Code_Item_Payload :: struct {
	kind: Code_Item_Kind,
	node: ^e.Node, // the AnimationPlayer (animations)
	name: [128]u8,
	nlen: int,
}

// code_item_drag makes the item just drawn a drag source of a project name.
code_item_drag :: proc(kind: Code_Item_Kind, name: string, node: ^e.Node = nil, textItem := false) {
	if imgui.IsItemHovered() do imgui.SetMouseCursor(.Hand)
	if !imgui.BeginDragDropSource({.SourceAllowNullID} if textItem else {}) do return
	pl := Code_Item_Payload{kind = kind, node = node}
	pl.nlen = copy(pl.name[:], name)
	imgui.SetDragDropPayload(CODE_ITEM_PAYLOAD, &pl, size_of(Code_Item_Payload))
	imgui.TextUnformatted(fmt.ctprintf("%s  %s", ICON_FA_CODE, name))
	UI_DimText("Drop in a script · Shift: held, not just pressed" if kind == .Action else "Drop in a script")
	imgui.EndDragDropSource()
}

// code_item_text: the Lua a dropped project name becomes.
code_item_text :: proc(state: ^EditorState, doc: ^Code_Doc, it: ^Code_Item_Payload, shift: bool) -> string {
	name := string(it.name[:it.nlen])
	switch it.kind {
	case .Action:
		return fmt.tprintf("Input.%s(%q)", "is_action_down" if shift else "is_action_pressed", name)
	case .Animation:
		if !e.Node_IsAlive(it.node) || state.activeScene == nil do return fmt.tprintf("animation_play(%q)", name)
		return fmt.tprintf("%s:animation_play(%q)", code_node_ref(state, doc, it.node, true), name)
	case .Event:
		ref := "self.node"
		if e.Node_IsAlive(it.node) && state.activeScene != nil do ref = code_node_ref(state, doc, it.node, true)
		param, _ := e.Event_Describe(name)
		return fmt.tprintf("%s:connect(%q, function(%s, source)\n\nend)", ref, name, param if param != "" else "value")
	}
	return ""
}

// code_asset_use: the Lua that uses an asset (Alt + drop): play a sound,
// change to a scene, show a texture on this script's node ("" = none).
code_asset_use :: proc(state: ^EditorState, doc: ^Code_Doc, rel: string) -> string {
	switch Asset_KindOf(rel) {
	case .Audio:   return fmt.tprintf("Audio.play_sound(%q)", rel)
	case .Scene:   return fmt.tprintf("Scene.change_scene(%q)", Asset_DisplayName(rel))
	case .Texture: return fmt.tprintf("self.node:set_texture(%q)", rel)
	case .Resource: return fmt.tprintf("Resource.load(%q)", rel)
	case .CustomNode:
		if t, _ := e.CustomNode_Get(&state.game.gameContext, rel); t != nil do return fmt.tprintf("Scene.create(%q, self.node)", t.name)
	case .Generator: return fmt.tprintf("LevelGen.generate(%q, self.node)", rel)
	case .Component, .Script, .Level, .Shader, .Package, .Aseprite, .Vector, .Other:
	}
	return ""
}

// --- Dragging an Inspector property's name ----------------------------------

PROP_PAYLOAD :: "RAYZR_PROP"

Prop_Payload :: struct {
	node:  ^e.Node,
	path:  [128]u8,
	plen:  int,
	value: [256]u8,
	vlen:  int,
}

// prop_label: a property row's label (as UI_PropLabel) that can be dragged
// into a script. The drag source starts inside the label's table cell: past
// it, hit tests clip to the next column.
prop_label :: proc(label: string, node: ^e.Node, path, value: string) {
	imgui.TableNextRow()
	// Shown from the code (Show in Inspector): the row lights up for a moment.
	if Inspector_FlashActive(node, path) {
		imgui.TableSetBgColor(.RowBg0, col_u32(ui_accent(0.25)))
		if !inspFlash.scrolled {
			imgui.SetScrollHereY(0.4)
			inspFlash.scrolled = true
		}
	}
	imgui.TableNextColumn()
	imgui.AlignTextToFramePadding()
	// An overridden value of an instance node: a bar and the component
	// colour (right-click: Revert / Apply, #84).
	overridden := Inspector_IsOverridden(node, path)
	if overridden {
		p := imgui.GetCursorScreenPos()
		imgui.DrawList_AddRectFilled(imgui.GetWindowDrawList(), {p.x, p.y + 3}, {p.x + 3, p.y + imgui.GetFrameHeight() - 3}, col_u32(UI_COMPONENT), 1)
		imgui.SetCursorScreenPos({p.x + 8, p.y})
	}
	imgui.PushStyleColorImVec4(.Text, UI_COMPONENT if overridden else UI_TEXT_DIM)
	imgui.TextUnformatted(strings.clone_to_cstring(label, context.temp_allocator))
	imgui.PopStyleColor()
	if path != "" do Drive_Item(fmt.tprintf("insp.proplabel:%s", path))
	if overridden do Drive_Item(fmt.tprintf("insp.overridden:%s", path))
	prop_label_drag(node, path, value)
	prop_label_menu(node, path)
	Inspector_KeyButton(node, path) // (while an animation is edited, #179)
	imgui.TableNextColumn()
	imgui.SetNextItemWidth(-1)
}

// --- Inspector <-> code ----------------------------------------------------------------

// inspFlash: the Inspector row a code jump points at (Show in Inspector).
inspFlash: struct {
	node:     ^e.Node,
	path:     [128]u8,
	pathLen:  int,
	until:    time.Tick,
	scrolled: bool,
}

// Inspector_Flash lights a property row of a node (selects the node).
Inspector_Flash :: proc(state: ^EditorState, node: ^e.Node, path: string) {
	Editor_SelectNode(state, node, false)
	// (the tab its row is in: a script property's is Properties, #208)
	inspectorTabRequest = .Properties if strings.has_prefix(path, "script.") else .Node
	inspFlash.node = node
	inspFlash.pathLen = copy(inspFlash.path[:], path)
	inspFlash.until = time.tick_add(time.tick_now(), 1500 * time.Millisecond)
	inspFlash.scrolled = false
}

Inspector_FlashActive :: proc(node: ^e.Node, path: string) -> bool {
	return inspFlash.node == node && node != nil && string(inspFlash.path[:inspFlash.pathLen]) == path && time.tick_diff(time.tick_now(), inspFlash.until) > 0
}

// prop_label_menu: right-click a property's name: Find in Script (script
// properties), Copy Path.
@(private = "file")
prop_label_menu :: proc(node: ^e.Node, path: string) {
	if node == nil || path == "" do return
	if !imgui.BeginPopupContextItem(fmt.ctprintf("##propctx_%s", path)) do return
	defer imgui.EndPopup()
	state := code_state()
	exposed_menu(state, node, path) // (a component document: #85)
	if Inspector_IsOverridden(node, path) {
		if imgui.MenuItem(fmt.ctprintf("%s  Revert to Component", ICON_FA_ROTATE_LEFT)) do inspector_queue_override(node, path, false)
		Drive_Item("ctx:revert-override")
		UI_Tooltip("Drop this override: the value follows the component file again")
		if imgui.MenuItem(fmt.ctprintf("%s  Apply to Component", ICON_FA_FLOPPY_DISK)) do inspector_queue_override(node, path, true)
		Drive_Item("ctx:apply-override")
		UI_Tooltip("Write this value to the component file (every instance without its own override gets it)")
		imgui.Separator()
	}
	if strings.has_prefix(path, "script.") && node.scriptInstance != nil {
		Inspector_PropertyMenu(state, node, path[len("script."):]) // Edit / Remove (#208)
		if imgui.MenuItem(fmt.ctprintf("%s  Find in Script", ICON_FA_CODE)) {
			Code_FindScriptProperty(state, (cast(^e.ScriptInstance)node.scriptInstance).modulePath, path[len("script."):])
		}
		Drive_Item("ctx:find-in-script")
	}
	if imgui.MenuItem(fmt.ctprintf("%s  Copy Path", ICON_FA_LINK)) do imgui.SetClipboardText(strings.clone_to_cstring(path, context.temp_allocator))
}

// Code_FindScriptProperty opens a script at a property's declaration in
// its properties table (else its first self.<name>), the name selected.
Code_FindScriptProperty :: proc(state: ^EditorState, script, name: string) {
	if !Editor_OpenScript(state, script) do return
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	target := buf.Position{-1, 0}
	fallback := buf.Position{-1, 0}
	for ln in 0 ..< buf.buffer_line_count(b) {
		l := buf.buffer_line_str(b, ln)
		t := strings.trim_left(l, " \t")
		if strings.has_prefix(t, name) && strings.has_prefix(strings.trim_left(t[len(name):], " "), "=") {
			target = {ln, len(l) - len(t)}
			break
		}
		if fallback.line < 0 {
			if i := strings.index(l, fmt.tprintf("self.%s", name)); i >= 0 do fallback = {ln, i + 5}
		}
	}
	if target.line < 0 do target = fallback
	if target.line < 0 do return
	code_set_single_cursor(b, target, false)
	b.cursors[0].sel = {anchor = target, active = true}
	b.cursors[0].pos = {target.line, target.col + len(name)}
	doc.scrollToCursor = true
	GlobalCode.focusRequest = true
}

// Code_CmdShowInInspector: the property under the caret - self.<script
// property>, self.node.<field>, get_property / set_property("path") on
// self.node - selected and lit in the Inspector on the script's node.
Code_CmdShowInInspector :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	owner := code_script_owner(state, doc)
	if owner == nil {
		Editor_Log(state, .Info, "No node in this scene runs %s", doc.rel)
		return
	}
	b := &doc.buffer
	p := b.cursors[len(b.cursors) - 1].pos
	line := buf.buffer_line_str(b, p.line)
	// The property path string around the caret (get_property / set_property).
	if lit, _, _, before, ok := code_literal_around(line, p.col); ok && (strings.has_suffix(before, "get_property(") || strings.has_suffix(before, "set_property(")) {
		Inspector_Flash(state, owner, lit)
		return
	}
	s, en := min(p.col, len(line)), min(p.col, len(line))
	for s > 0 && code_is_ident_byte(line[s - 1]) do s -= 1
	for en < len(line) && code_is_ident_byte(line[en]) do en += 1
	name := line[s:en]
	if name == "" do return
	switch {
	case strings.has_suffix(line[:s], "self.node."):
		Inspector_Flash(state, owner, name)
	case strings.has_suffix(line[:s], "self."):
		if props, ok := e.Script_InspectProperties(doc.rel, &state.game.scriptManager); ok {
			for pr in props do if pr.name == name {
				Inspector_Flash(state, owner, fmt.tprintf("script.%s", name))
				return
			}
		}
		Editor_Log(state, .Info, "%s is not an exported property of %s", name, doc.rel)
	case:
		Editor_Log(state, .Info, "Put the caret on self.<property>, self.node.<field> or a get_property path")
	}
}

// code_literal_around: the string literal around col and the text before it.
code_literal_around :: proc(line: string, col: int) -> (lit: string, from, to: int, before: string, ok: bool) {
	open := -1
	for i := min(col, len(line)) - 1; i >= 0; i -= 1 do if line[i] == '"' || line[i] == '\'' {open = i; break}
	if open < 0 do return
	close := strings.index_byte(line[open + 1:], line[open])
	if close < 0 || open + 1 + close < col do return
	return line[open + 1:open + 1 + close], open + 1, open + 1 + close, strings.trim_right_space(line[:open]), true
}

@(private = "file")
prop_label_drag :: proc(node: ^e.Node, path, value: string) {
	if node == nil || path == "" do return
	if imgui.IsItemHovered() do imgui.SetMouseCursor(.Hand)
	if !imgui.BeginDragDropSource({.SourceAllowNullID}) do return
	pl: Prop_Payload
	pl.node = node
	pl.plen = copy(pl.path[:], path)
	pl.vlen = copy(pl.value[:], value)
	imgui.SetDragDropPayload(PROP_PAYLOAD, &pl, size_of(Prop_Payload))
	imgui.TextUnformatted(fmt.ctprintf("%s  %s", ICON_FA_CODE, path))
	UI_DimText("Drop in a script: get_property · Shift: set_property")
	imgui.EndDragDropSource()
}

// prop_lua_value: a property's current value as Lua (for set_property).
prop_lua_value :: proc(p: e.Node_Property) -> string {
	switch p.kind {
	case .Float: return fmt.tprintf("%v", e.Property_GetFloat(p))
	case .Int:   return fmt.tprintf("%v", e.Property_GetInt(p))
	case .Bool:  return "true" if (^bool)(p.ptr)^ else "false"
	case .Vec2:
		v := (^[2]f32)(p.ptr)^
		return fmt.tprintf("%v, %v", v.x, v.y)
	case .Color:
		col := (^rl.Color)(p.ptr)^
		f :: proc(v: u8) -> f32 {return f32(int(f32(v) / 255 * 1000 + 0.5)) / 1000}
		return fmt.tprintf("{{%v, %v, %v, %v}}", f(col.r), f(col.g), f(col.b), f(col.a))
	case .Enum:
		names := e.Property_EnumNames(p)
		i := e.Property_GetEnumIndex(p)
		return fmt.tprintf("%q", names[i] if i >= 0 && i < len(names) else "")
	case .String: return fmt.tprintf("%q", (^string)(p.ptr)^)
	case .String_List:
		quoted := make([dynamic]string, context.temp_allocator)
		for it in e.Property_GetList(p) do append(&quoted, fmt.tprintf("%q", it))
		return fmt.tprintf("{{%s}}", strings.join(quoted[:], ", ", context.temp_allocator))
	case .Bit_Set:
	}
	return "nil"
}

// script_lua_value: a script property's value as Lua.
script_lua_value :: proc(v: e.ScriptValue) -> string {
	switch v.type {
	case .Float:   return fmt.tprintf("%v", v.valFloat)
	case .Int:     return fmt.tprintf("%v", v.valInt)
	case .Boolean: return "true" if v.valBool else "false"
	case .String:  return fmt.tprintf("%q", v.valString)
	case .Vector2: return fmt.tprintf("{{%v, %v}}", v.valVec2.x, v.valVec2.y)
	case .Color:   return fmt.tprintf("{{%v, %v, %v, %v}}", v.valColor.r, v.valColor.g, v.valColor.b, v.valColor.a)
	}
	return "nil"
}

// code_drop_target makes the text area accept assets and nodes; call right
// after the text area's input item.
code_drop_target :: proc(state: ^EditorState, doc: ^Code_Doc, mouse: [2]f32) {
	if !imgui.BeginDragDropTarget() do return
	defer imgui.EndDragDropTarget()
	cm := &GlobalCode
	b := &doc.buffer
	pos := code_pos_at(b, mouse)
	preview :: proc(b: ^buf.Buffer, pos: buf.Position) {
		cm := &GlobalCode
		p := code_screen_pos(b, pos)
		dl := imgui.GetForegroundDrawList()
		imgui.DrawList_AddRectFilled(dl, {p.x - 1, p.y}, {p.x + 2, p.y + cm.lineH}, col_u32(UI_WARNING))
	}
	if payload := imgui.AcceptDragDropPayload(ASSET_PAYLOAD, {.AcceptBeforeDelivery, .AcceptNoDrawDefaultRect}); payload != nil {
		preview(b, pos)
		io := imgui.GetIO()
		asProp := io.KeyCtrl || io.KeySuper
		p := (^Asset_Payload)(payload.Data)
		rel := strings.clone(string(p.path[:p.len]), context.temp_allocator)
		use := code_asset_use(state, doc, rel)
		switch {
		case asProp:                imgui.SetTooltip("Add as an exported property")
		case io.KeyAlt && use != "": imgui.SetTooltip("%s", strings.clone_to_cstring(use, context.temp_allocator))
		case use != "":             imgui.SetTooltip("The path · " + CMD + ": an exported property · Alt: %s", strings.clone_to_cstring(use, context.temp_allocator))
		}
		if payload.Delivery {
			if io.KeyAlt && use != "" && !asProp do code_insert(doc, pos, use)
			else do Code_DropAsset(doc, rel, pos, asProp)
			cm.focusRequest = true
		}
	}
	if payload := imgui.AcceptDragDropPayload(CODE_ITEM_PAYLOAD, {.AcceptBeforeDelivery, .AcceptNoDrawDefaultRect}); payload != nil {
		preview(b, pos)
		it := (^Code_Item_Payload)(payload.Data)
		text := code_item_text(state, doc, it, imgui.GetIO().KeyShift)
		imgui.SetTooltip("%s", strings.clone_to_cstring(text, context.temp_allocator))
		if payload.Delivery {
			if text != "" do code_insert_block(doc, pos, text)
			cm.focusRequest = true
		}
	}
	if payload := imgui.AcceptDragDropPayload(PROP_PAYLOAD, {.AcceptBeforeDelivery, .AcceptNoDrawDefaultRect}); payload != nil {
		preview(b, pos)
		set := imgui.GetIO().KeyShift
		imgui.SetTooltip(set ? "set_property (release Shift: get)" : "get_property (Shift: set)")
		if payload.Delivery {
			p := (^Prop_Payload)(payload.Data)
			path := strings.clone(string(p.path[:p.plen]), context.temp_allocator)
			value := strings.clone(string(p.value[:p.vlen]), context.temp_allocator)
			if e.Node_IsAlive(p.node) do Code_DropProperty(state, doc, p.node, path, value, set, pos)
			cm.focusRequest = true
		}
	}
	if payload := imgui.AcceptDragDropPayload("RAYZR_NODE", {.AcceptBeforeDelivery, .AcceptNoDrawDefaultRect}); payload != nil {
		preview(b, pos)
		cls, method := code_method_at(b, pos.line)
		if method != "" do imgui.SetTooltip("Connect one of its events to %s:%s()", strings.clone_to_cstring(cls, context.temp_allocator), strings.clone_to_cstring(method, context.temp_allocator))
		if payload.Delivery {
			n := (^^e.Node)(payload.Data)^
			if e.Node_IsAlive(n) {
				if method != "" {
					// Onto a method: pick one of the node's events (menu below).
					delete(nodeDropMenu.cls)
					delete(nodeDropMenu.method)
					nodeDropMenu = {node = n, cls = strings.clone(cls), method = strings.clone(method), open = true}
					return // no focus request: focusing the code window would close the menu
				} else {
					Code_DropNode(state, doc, n, pos)
				}
			}
			cm.focusRequest = true
		}
	}
}

// A node dropped onto a method: the menu of its events to connect.
@(private = "file")
nodeDropMenu: struct {
	node:        ^e.Node,
	cls, method: string,
	open:        bool,
}

// code_method_at: the class and method a `function Cls:method(` line
// defines ("" when it isn't one).
code_method_at :: proc(b: ^buf.Buffer, line: int) -> (cls, method: string) {
	if line >= buf.buffer_line_count(b) do return
	l := strings.trim_space(buf.buffer_line_str(b, line))
	if !strings.has_prefix(l, "function ") do return
	sig := l[len("function "):]
	colon := strings.index_byte(sig, ':')
	paren := strings.index_byte(sig, '(')
	if colon <= 0 || paren <= colon + 1 do return
	return sig[:colon], sig[colon + 1:paren]
}

// Code_NodeDropMenu shows the event menu after a node was dropped onto a
// method (call each frame while the code area is drawn).
Code_NodeDropMenu :: proc(state: ^EditorState, doc: ^Code_Doc) {
	m := &nodeDropMenu
	if m.open {
		imgui.OpenPopup("##node_drop_events")
		m.open = false
	}
	if !imgui.BeginPopup("##node_drop_events") do return
	defer imgui.EndPopup()
	if !e.Node_IsAlive(m.node) {
		imgui.CloseCurrentPopup()
		return
	}
	UI_DimText(fmt.tprintf("Connect %s's event to %s:%s()", m.node.name, m.cls, m.method))
	imgui.Separator()
	for ev in e.Node_EventNames(m.node) {
		label := fmt.tprintf("%s  %s", ICON_FA_BOLT, ev.name)
		if imgui.MenuItem(strings.clone_to_cstring(label, context.temp_allocator)) {
			code_connect_in_ready(state, doc, m.node, ev.name, m.cls, m.method)
			imgui.CloseCurrentPopup()
		}
		Drive_Item(fmt.tprintf("node-drop.event:%s", ev.name))
		if ev.doc != "" do UI_Tooltip(ev.doc)
	}
}

// code_connect_in_ready adds `<node>:connect("ev", function(v, source)
// self:method(v, source) end)` to Cls:ready() (made when missing).
@(private = "file")
code_connect_in_ready :: proc(state: ^EditorState, doc: ^Code_Doc, node: ^e.Node, event, cls, method: string) {
	b := &doc.buffer
	param, _ := e.Event_Describe(event)
	if param == "" do param = "value"
	ref := code_node_ref(state, doc, node, true)
	unit := "\t" if doc.useTabs else "    "
	stmt := fmt.tprintf("%s%s:connect(%q, function(%s, source) self:%s(%s, source) end)\n", unit, ref, event, param, method, param)
	group := buf.buffer_next_group(b)
	header := fmt.tprintf("function %s:ready()", cls)
	for ln in 0 ..< buf.buffer_line_count(b) {
		if strings.has_prefix(strings.trim_space(buf.buffer_line_str(b, ln)), header) {
			buf.buffer_insert_text(b, {ln + 1, 0}, stmt, group)
			code_set_single_cursor(b, {ln + 1, len(stmt) - 1}, false)
			doc.scrollToCursor = true
			return
		}
	}
	// No ready(): one before the method.
	for ln in 0 ..< buf.buffer_line_count(b) {
		c, m := code_method_at(b, ln)
		if c == cls && m == method {
			block := fmt.tprintf("%s\n%send\n\n", header, stmt)
			buf.buffer_insert_text(b, {ln, 0}, block, group)
			code_set_single_cursor(b, {ln + 1, len(stmt) - 1}, false)
			doc.scrollToCursor = true
			return
		}
	}
}
