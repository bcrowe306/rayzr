package editor

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:c/libc"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Play-in-editor link: the game started with Play runs with --editor-link
// (engine/editor_link.odin). The editor writes commands to its stdin and
// reads "@rayzr:" replies from its output.
//
// The running game's scene tree shows in the Scene panel's Remote view
// (Local / Remote switch while the game runs) and in the bottom panel's
// Game tab: refreshed twice a second (only re-read when it changed),
// filter, enabled / visible toggles, Remove, Pick (click a node in the game
// window), and the selected node outlined in the game. Its live properties
// show in the Inspector (Remote view) and the Game tab with typed widgets -
// drags, checkboxes, colours, enum lists - changes go to the game at once;
// Apply to Scene copies the node's current values into the edited scene
// (undoable). Pause / Resume / Step. Saving a scene while the game runs
// reloads it there; scripts and images reload by themselves.
// ============================================================================

Remote_Row :: struct {
	depth:    int,
	name:     string,
	type:     string,
	path:     string,
	enabled:  bool,
	visible:  bool,
	children: bool,
}

Remote_Prop :: struct {
	name, value, kind, extra: string, // kind: float int bool vec2 color color01 enum bit_set string ro
}

@(private = "file")
remote: struct {
	input:      ^os.File, // the game's stdin (write end)
	rows:       [dynamic]Remote_Row,
	scene:      string,
	hash:       string, // the tree's hash (unchanged trees aren't re-sent)
	frame:      int,
	frozen:     bool,
	paused:     bool,
	selected:   string,
	highlighted: string,
	props:      [dynamic]Remote_Prop,
	edit:       map[string][128]u8,
	dragging:   string, // the property being dragged (live values don't fight it)
	sentAt:     time.Tick,
	treeAt:     time.Tick,
	nodeAt:     time.Tick,
	steps:      int, // "@rayzr:stepped" replies (drives)
	reloads:    int, // "@rayzr:reloaded" replies
	debugDraw:  string, // the last "@rayzr:debug-draw" reply (drives)
	connected:  bool,
	picking:    bool,
	collapsed:  map[string]bool,
	filter:     [64]u8,
}

// The Scene panel / Inspector show the running game (Remote) instead of
// the edited scene.
remoteView: bool

// RemoteGame_Attach: the game was launched; `input` is its stdin.
RemoteGame_Attach :: proc(input: ^os.File) {
	RemoteGame_Detach()
	remote.input = input
	// A write after the game quit must fail, not kill the editor (SIGPIPE).
	when ODIN_OS != .Windows {
		libc.signal(13 /* SIGPIPE */, auto_cast libc.SIG_IGN)
	}
}

RemoteGame_Detach :: proc() {
	Debug_Reset()
	if remote.input != nil do os.close(remote.input)
	remote.input = nil
	remote.connected = false
	remote.paused = false
	remote.frozen = false
	remote.picking = false
	remoteView = false
	remote_clear_rows()
	remote_clear_props()
	delete(remote.hash)
	remote.hash = ""
	delete(remote.highlighted)
	remote.highlighted = ""
}

RemoteGame_Connected :: proc() -> bool {return remote.input != nil && remote.connected}

RemoteGame_Paused :: proc() -> bool {return remote.paused}

// RemoteGame_Send writes one command line to the game.
RemoteGame_Send :: proc(line: string) -> bool {
	if remote.input == nil do return false
	data := strings.concatenate({line, "\n"}, context.temp_allocator)
	if _, err := os.write(remote.input, transmute([]u8)data); err != nil {
		RemoteGame_Detach()
		return false
	}
	return true
}

@(private = "file")
remote_clear_rows :: proc() {
	for r in remote.rows {
		delete(r.name)
		delete(r.type)
		delete(r.path)
	}
	clear(&remote.rows)
}

@(private = "file")
remote_clear_props :: proc() {
	for p in remote.props {
		delete(p.name)
		delete(p.value)
		delete(p.kind)
		delete(p.extra)
	}
	clear(&remote.props)
}

// RemoteGame_HandleLine takes a line of game output; true when it was a
// link reply (not shown in the console).
RemoteGame_HandleLine :: proc(state: ^EditorState, line: string) -> bool {
	if !strings.has_prefix(line, "@rayzr:") do return false
	msg := line[len("@rayzr:"):]
	kind, rest := msg, ""
	if i := strings.index_byte(msg, ' '); i >= 0 do kind, rest = msg[:i], msg[i + 1:]
	switch kind {
	case "hello":
		remote.connected = true
		Debug_SendAll() // breakpoints set before Play
		StateGraph_SendBreaks(state) // state machine break on enter
	case "stopped", "locals", "running", "watch": Debug_HandleReply(state, kind, rest)
	case "paused": remote.paused = true
	case "resumed": remote.paused = false
	case "stepped": remote.steps += 1
	case "reloaded":
		remote.reloads += 1
		Editor_Log(state, .Info, "Reloaded in the running game: %s", rest)
	case "tree": remote_parse_tree(rest)
	case "tree-same": remote_parse_status(rest)
	case "node": remote_parse_node(rest)
	case "picked":
		remote.picking = false
		if rest != "" {
			RemoteGame_Select(rest)
			remoteView = true
			Editor_Log(state, .Info, "Picked %s in the game", rest)
		} else {
			Editor_Log(state, .Info, "Nothing drawn there")
		}
	case "removed":
		parts := strings.fields(rest, context.temp_allocator)
		if len(parts) == 2 && parts[1] == "true" {
			Editor_Log(state, .Info, "Removed %s from the running game", parts[0])
			if parts[0] == remote.selected do RemoteGame_Select("")
		}
	case "debug-draw":
		delete(remote.debugDraw)
		remote.debugDraw = strings.clone(rest)
	case "eval": LuaConsole_Reply(state, rest)
	case "sm": StateGraph_RemoteReply(rest)
	case "bt": BehaviorTree_RemoteReply(rest)
	case "mixer-peaks": MixerPanel_RemoteReply(rest)
	case "sm-break":
		remote.paused = true
		Editor_Log(state, .Info, "Game paused: a state machine entered a break-on-enter state %s", rest)
	case "recorded": TestsPanel_Recorded(state, rest) // (the Record button: tests_panel.odin)
	case "recording":
	case "set":
	}
	return true
}

@(private = "file")
remote_parse_status :: proc(text: string) {
	v, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None do return
	obj, ok := v.(json.Object)
	if !ok do return
	remote.connected = true
	#partial switch f in obj["frame"] {
	case json.Integer: remote.frame = int(f)
	case json.Float: remote.frame = int(f)
	}
	remote.frozen = bool(obj["frozen"].(json.Boolean) or_else false)
	remote.paused = bool(obj["paused"].(json.Boolean) or_else false)
}

@(private = "file")
remote_parse_tree :: proc(text: string) {
	v, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None do return
	obj, ok := v.(json.Object)
	if !ok do return
	remote_parse_status(text)
	delete(remote.scene)
	remote.scene = strings.clone(string(obj["scene"].(json.String) or_else ""))
	delete(remote.hash)
	remote.hash = strings.clone(string(obj["hash"].(json.String) or_else ""))
	remote_clear_rows()
	walk :: proc(v: json.Value, depth: int, parentPath: string) {
		o, isObj := v.(json.Object)
		if !isObj do return
		name := string(o["name"].(json.String) or_else "?")
		path := "" if depth == 0 else (name if parentPath == "" else strings.concatenate({parentPath, "/", name}, context.temp_allocator))
		kids, hasKids := o["children"].(json.Array)
		append(&remote.rows, Remote_Row{
			depth = depth, name = strings.clone(name), type = strings.clone(string(o["type"].(json.String) or_else "")),
			path = strings.clone(path), enabled = bool(o["enabled"].(json.Boolean) or_else true),
			visible = bool(o["visible"].(json.Boolean) or_else true), children = hasKids && len(kids) > 0,
		})
		if hasKids do for k in kids do walk(k, depth + 1, path)
	}
	walk(obj["root"], 0, "")
}

@(private = "file")
remote_parse_node :: proc(text: string) {
	v, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None do return
	obj, _ := v.(json.Object)
	if string(obj["path"].(json.String) or_else "") != remote.selected do return
	remote_clear_props()
	if props, ok := obj["props"].(json.Array); ok {
		for pv in props {
			arr, isArr := pv.(json.Array)
			if !isArr || len(arr) < 2 do continue
			str :: proc(a: json.Array, i: int) -> string {return strings.clone(string(a[i].(json.String) or_else "")) if i < len(a) else strings.clone("string" if i == 2 else "")}
			append(&remote.props, Remote_Prop{str(arr, 0), str(arr, 1), str(arr, 2), str(arr, 3)})
		}
	}
}

// RemoteGame_Select selects a node of the running game ("" = none) and
// outlines it there.
RemoteGame_Select :: proc(path: string) {
	if remote.selected == path do return
	delete(remote.selected)
	remote.selected = strings.clone(path)
	remote.nodeAt = {}
	clear(&remote.edit)
	remote_clear_props()
}

// RemoteGame_Update polls the game (call every frame).
RemoteGame_Update :: proc(state: ^EditorState) {
	if !state.gameProcessRunning {
		if remote.input != nil do RemoteGame_Detach()
		return
	}
	if remote.input == nil || Debug_IsStopped() do return // paused in a script: it only reads debugger commands
	if time.tick_since(remote.treeAt) > 500 * time.Millisecond {
		remote.treeAt = time.tick_now()
		RemoteGame_Send(fmt.tprintf("tree %s", remote.hash) if remote.hash != "" else "tree")
	}
	if remote.selected != "" && time.tick_since(remote.nodeAt) > 250 * time.Millisecond {
		remote.nodeAt = time.tick_now()
		RemoteGame_Send(fmt.tprintf("inspect %s", remote.selected))
	}
	// The outline follows the selection (in the Remote view / Game tab).
	want := remote.selected if remote.connected else ""
	if want != remote.highlighted {
		RemoteGame_Send(fmt.tprintf("highlight %s", want))
		delete(remote.highlighted)
		remote.highlighted = strings.clone(want)
	}
}

// RemoteGame_Query answers the drive queries remote-*.
RemoteGame_Query :: proc(q: string) -> (string, bool) {
	switch q {
	case "remote-connected": return "true" if RemoteGame_Connected() else "false", true
	case "remote-paused": return "true" if remote.paused else "false", true
	case "remote-frame": return fmt.tprint(remote.frame), true
	case "remote-steps": return fmt.tprint(remote.steps), true
	case "remote-reloads": return fmt.tprint(remote.reloads), true
	case "remote-nodes": return fmt.tprint(len(remote.rows)), true
	case "remote-selected": return remote.selected, true
	case "remote-view": return "true" if remoteView else "false", true
	case "remote-names":
		names := make([dynamic]string, context.temp_allocator)
		for r in remote.rows do append(&names, r.name)
		return strings.join(names[:], ",", context.temp_allocator), true
	}
	if q == "remote-debug-draw" do return remote.debugDraw, true
	if strings.has_prefix(q, "remote-prop:") {
		for p in remote.props do if p.name == q[len("remote-prop:"):] do return p.value, true
		return "<none>", true
	}
	return "", false
}

// --- shared views ------------------------------------------------------------------------

// RemoteTree_Render: the running game's tree (filter, toggles, context menu).
RemoteTree_Render :: proc(state: ^EditorState, id: string) {
	imgui.SetNextItemWidth(-32)
	imgui.InputTextWithHint(fmt.ctprintf("##rfilter_%s", id), fmt.ctprintf("%s  Filter", ICON_FA_MAGNIFYING_GLASS), cstring(raw_data(remote.filter[:])), len(remote.filter))
	imgui.SameLine()
	if UI_IconButton(ICON_FA_CROSSHAIRS, fmt.tprintf("remote.pick:%s", id), "Pick: click a node in the game window" if !remote.picking else "Picking - click in the game window (click again to cancel)", remote.picking, 26) {
		remote.picking = !remote.picking
		RemoteGame_Send("pick" if remote.picking else "pick off")
	}
	filter := strings.to_lower(string(cstring(raw_data(remote.filter[:]))), context.temp_allocator)
	// With a filter: matching rows and their ancestors.
	show: []bool
	if filter != "" {
		show = make([]bool, len(remote.rows), context.temp_allocator)
		for r, i in remote.rows {
			if !strings.contains(strings.to_lower(r.name, context.temp_allocator), filter) && !strings.contains(strings.to_lower(r.type, context.temp_allocator), filter) do continue
			show[i] = true
			d := r.depth
			for j := i - 1; j >= 0 && d > 0; j -= 1 do if remote.rows[j].depth < d {
				show[j] = true
				d = remote.rows[j].depth
			}
		}
	}
	if imgui.BeginChild(fmt.ctprintf("##remote_tree_%s", id), {0, 0}, {}, {}) {
		hideBelow := -1
		for r, i in remote.rows {
			if show != nil && !show[i] do continue
			if hideBelow >= 0 && show == nil {
				if r.depth > hideBelow do continue
				hideBelow = -1
			}
			if r.depth == 0 do continue // the root
			imgui.PushIDInt(i32(i))
			imgui.Indent(f32(r.depth - 1) * 14)
			closed := remote.collapsed[r.path]
			arrow := (ICON_FA_CARET_RIGHT if closed else ICON_FA_CARET_DOWN) if r.children else " "
			col := UI_TEXT if r.enabled && r.visible else UI_TEXT_FAINT
			imgui.PushStyleColorImVec4(.Text, col)
			w := imgui.GetContentRegionAvail().x - 60 // (room for the two toggles)
			if imgui.Selectable(fmt.ctprintf("%s  %s###r_%s", arrow, r.name, r.path), remote.selected == r.path, {}, {w, 0}) {
				if r.children && imgui.GetIO().MousePos.x < imgui.GetItemRectMin().x + 18 {
					remote.collapsed[strings.clone(r.path)] = !closed
				} else {
					RemoteGame_Select(r.path)
				}
			}
			imgui.PopStyleColor()
			Drive_Item(fmt.tprintf("remote.node:%s", r.path))
			if imgui.IsItemHovered() do imgui.SetTooltip(fmt.ctprintf("%s  (%s)", r.path, r.type))
			if imgui.BeginPopupContextItem("##rctx") {
				RemoteGame_Select(r.path)
				if imgui.MenuItem(fmt.ctprintf("%s  Apply to Scene", ICON_FA_FILE_IMPORT)) do RemoteGame_ApplyToScene(state)
				Drive_Item("ctx:remote-apply")
				if imgui.MenuItem(fmt.ctprintf("%s  Remove from Game", ICON_FA_TRASH)) do RemoteGame_Send(fmt.tprintf("remove %s", r.path))
				Drive_Item("ctx:remote-remove")
				if imgui.MenuItem(fmt.ctprintf("%s  Copy Path", ICON_FA_COPY)) do imgui.SetClipboardText(fmt.ctprintf("%s", r.path))
				imgui.EndPopup()
			}
			// Enabled / visible toggles.
			imgui.SameLine(0, 4)
			if UI_IconButton(ICON_FA_POWER_OFF, fmt.tprintf("remote.enabled:%s", r.path), "Enabled (updates)", r.enabled, 22) {
				RemoteGame_Send(fmt.tprintf("set %s enabled %t", r.path, !r.enabled))
				remote.rows[i].enabled = !r.enabled // (until the next tree arrives)
				remote.treeAt, remote.nodeAt = {}, {}
			}
			imgui.SameLine()
			if UI_IconButton(ICON_FA_EYE if r.visible else ICON_FA_EYE_SLASH, fmt.tprintf("remote.visible:%s", r.path), "Visible (drawn)", r.visible, 22) {
				RemoteGame_Send(fmt.tprintf("set %s visible %t", r.path, !r.visible))
				remote.rows[i].visible = !r.visible
				remote.treeAt, remote.nodeAt = {}, {}
			}
			imgui.Unindent(f32(r.depth - 1) * 14)
			imgui.PopID()
			if r.children && closed do hideBelow = r.depth
		}
	}
	imgui.EndChild()
}

// RemoteProps_Render: the selected node's live properties, typed.
RemoteProps_Render :: proc(state: ^EditorState) {
	if remote.selected == "" {
		UI_DimText("Select a node of the running game to see its live properties.")
		return
	}
	if UI_Button(fmt.tprintf("%s  Apply to Scene", ICON_FA_FILE_IMPORT), "remote.apply") do RemoteGame_ApplyToScene(state)
	UI_Tooltip("Copy this node's current values into the edited scene (the node with the same path; undoable)")
	if !UI_BeginProps("##rprops") do return
	defer UI_EndProps()
	for p in remote.props {
		UI_PropLabel(pretty_name(p.name))
		imgui.SetNextItemWidth(-1)
		remote_prop_widget(state, p)
		Drive_Item(fmt.tprintf("remote.prop:%s", p.name))
	}
}

@(private = "file")
remote_send :: proc(name, value: string, final := true) {
	// While dragging: at most 20 times a second; the last value always goes.
	if !final && time.tick_since(remote.sentAt) < 50 * time.Millisecond do return
	remote.sentAt = time.tick_now()
	RemoteGame_Send(fmt.tprintf("set %s %s %s", remote.selected, name, value))
	if final do remote.nodeAt = {}
	if name == "enabled" || name == "visible" {
		for &r in remote.rows do if r.path == remote.selected {
			if name == "enabled" do r.enabled = value == "true"
			else do r.visible = value == "true"
		}
		remote.treeAt = {}
	}
}

@(private = "file")
remote_prop_widget :: proc(state: ^EditorState, p: Remote_Prop) {
	id := fmt.ctprintf("##rp_%s", p.name)
	nums :: proc(s: string, out: []f32) -> int {
		n := 0
		for part in strings.split(s, ",", context.temp_allocator) {
			if n >= len(out) do break
			out[n], _ = strconv.parse_f32(strings.trim_space(part))
			n += 1
		}
		return n
	}
	lo, hi: f32
	ranged := false
	if parts := strings.split(p.extra, "|", context.temp_allocator); len(parts) == 2 && (p.kind == "float" || p.kind == "int") {
		lo, _ = strconv.parse_f32(parts[0])
		hi, _ = strconv.parse_f32(parts[1])
		ranged = hi > lo
	}
	active := remote.dragging == p.name
	held := remote_held()^ // the dragged value (live replies don't move it)
	switch p.kind {
	case "bool":
		b := p.value == "true"
		if imgui.Checkbox(id, &b) do remote_send(p.name, "true" if b else "false")
	case "float", "int":
		v: [1]f32
		nums(p.value, v[:])
		if active do v[0] = held[0]
		speed: f32 = (hi - lo) / 200 if ranged else 0.1
		changed := imgui.DragFloat(id, &v[0], max(speed, 0.01), lo if ranged else 0, hi if ranged else 0, "%.0f" if p.kind == "int" else "%.3f")
		remote_drag(p, changed, v[:], fmt.tprintf("%d", int(v[0])) if p.kind == "int" else fmt.tprintf("%g", v[0]))
	case "vec2":
		v: [2]f32
		nums(p.value, v[:])
		if active do v = {held[0], held[1]}
		changed := imgui.DragFloat2(id, &v, 0.5, 0, 0, "%.2f")
		remote_drag(p, changed, v[:], fmt.tprintf("%g,%g", v[0], v[1]))
	case "color", "color01":
		c: [4]f32 = {1, 1, 1, 1}
		if p.kind == "color" {
			// "#rrggbbaa"
			hex := strings.trim_prefix(p.value, "#")
			for i in 0 ..< min(len(hex) / 2, 4) {
				b, _ := strconv.parse_int(hex[i * 2:i * 2 + 2], 16)
				c[i] = f32(b) / 255
			}
		} else {
			nums(p.value, c[:])
		}
		if active do c = held
		changed := imgui.ColorEdit4(id, &c, {.AlphaBar})
		text := fmt.tprintf("#%02x%02x%02x%02x", u8(c[0] * 255 + 0.5), u8(c[1] * 255 + 0.5), u8(c[2] * 255 + 0.5), u8(c[3] * 255 + 0.5)) if p.kind == "color" else fmt.tprintf("%g,%g,%g,%g", c[0], c[1], c[2], c[3])
		remote_drag(p, changed, c[:], text)
	case "enum":
		names := strings.split(p.extra, "|", context.temp_allocator)
		if imgui.BeginCombo(id, fmt.ctprintf("%s", p.value)) {
			for n in names {
				if imgui.Selectable(fmt.ctprintf("%s", n), n == p.value) do remote_send(p.name, n)
				Drive_Item(fmt.tprintf("pick:%s", n))
			}
			imgui.EndCombo()
		}
	case "ro":
		imgui.BeginDisabled(true)
		buf: [128]u8
		copy(buf[:len(buf) - 1], p.value)
		imgui.InputText(id, cstring(raw_data(buf[:])), len(buf), {.ReadOnly})
		imgui.EndDisabled()
	case:
		// Text (strings, bit sets "A|B"): Enter sends.
		buf, editing := remote.edit[p.name]
		if !editing do copy(buf[:len(buf) - 1], p.value)
		if imgui.InputText(id, cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue}) {
			remote_send(p.name, string(cstring(raw_data(buf[:]))))
			delete_key(&remote.edit, p.name)
		} else if imgui.IsItemActive() {
			remote.edit[p.name] = buf // typing: don't overwrite with live values
		} else if editing {
			delete_key(&remote.edit, p.name)
		}
	}
	// Dragging or typing into a drag: the value the widget shows is ours.
	remote_drag :: proc(p: Remote_Prop, changed: bool, v: []f32, text: string) {
		if imgui.IsItemActive() {
			if remote.dragging != p.name {
				delete(remote.dragging)
				remote.dragging = strings.clone(p.name)
			}
			for x, i in v do remote_held()[i] = x
			if changed do remote_send(p.name, text, false)
		} else if remote.dragging == p.name {
			delete(remote.dragging)
			remote.dragging = ""
		}
		if imgui.IsItemDeactivatedAfterEdit() do remote_send(p.name, text)
	}
}

@(private = "file")
remote_held :: proc() -> ^[4]f32 {
	@(static) held: [4]f32
	return &held
}

// RemoteGame_ApplyToScene copies the selected node's live values into the
// edited scene's node with the same path (when the game runs that scene).
RemoteGame_ApplyToScene :: proc(state: ^EditorState) {
	if remote.selected == "" || state.activeScene == nil do return
	if remote.scene != "" && remote.scene != state.activeScene.filePath {
		Editor_Log(state, .Warn, "The game runs %s - open it to apply its values", remote.scene)
		return
	}
	n := state.activeScene.rootNode
	for part in strings.split(remote.selected, "/", context.temp_allocator) {
		next: ^e.Node
		for c in e.GetChildrenView(state.activeScene.manager, n) do if c != nil && c.name == part {next = c; break}
		n = next
		if n == nil do break
	}
	if n == nil {
		Editor_Log(state, .Warn, "%s isn't in the edited scene (made while playing?)", remote.selected)
		return
	}
	Editor_RecordUndo(state, "Apply runtime values")
	applied := 0
	for p in remote.props {
		if p.kind == "ro" || strings.has_prefix(p.name, "script.") do continue
		if e.Node_SetFromText(state.game, n, p.name, p.value) do applied += 1
	}
	state.selectedNode = n
	Editor_Log(state, .Info, "Applied %d live value(s) of %s to the scene", applied, remote.selected)
}

// GamePanel_Render: the bottom panel's Game tab.
GamePanel_Render :: proc(state: ^EditorState) {
	if !state.gameProcessRunning {
		imgui.Dummy({0, 6})
		UI_DimText("Play the game (F5) to see its live scene tree here (and in the Scene panel's Remote view): inspect and change nodes while it runs, pause and step frames.")
		return
	}
	if !RemoteGame_Connected() {
		UI_DimText("Connecting to the game...")
		return
	}
	Debug_Panel(state)
	RemoteToolbar_Render()
	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##remote_tree_box", {avail.x * 0.45, 0}, {.Borders}, {}) do RemoteTree_Render(state, "game")
	imgui.EndChild()
	imgui.SameLine()
	if imgui.BeginChild("##remote_props", {0, 0}, {.Borders}, {}) do RemoteProps_Render(state)
	imgui.EndChild()
}

// RemoteToolbar_Render: Pause / Resume, Step and the frame counter.
RemoteToolbar_Render :: proc() {
	if remote.paused {
		if UI_PrimaryButton(fmt.tprintf("%s  Resume", ICON_FA_PLAY), "remote.resume") do RemoteGame_Send("resume")
	} else {
		if UI_Button(fmt.tprintf("%s  Pause", ICON_FA_PAUSE), "remote.pause") do RemoteGame_Send("pause")
	}
	imgui.SameLine()
	if UI_Button(fmt.tprintf("%s  Step", ICON_FA_FORWARD_STEP), "remote.step") do RemoteGame_Send("step 1")
	UI_Tooltip("Run one frame (1/60 s) and pause")
	imgui.SameLine()
	UI_DimText(fmt.tprintf("frame %d  ·  %s%s", remote.frame, remote.scene, "  ·  paused" if remote.paused else ""))
}

// RemoteView_Header: the Local / Remote switch for the Scene panel (while
// the game runs); true when the Remote view is shown.
RemoteView_Header :: proc(state: ^EditorState) -> bool {
	if !RemoteGame_Connected() {
		remoteView = false
		return false
	}
	seg :: proc(label, id: string, on: bool) -> bool {
		return UI_PrimaryButton(label, id) if on else UI_Button(label, id)
	}
	if seg(fmt.tprintf("%s  Local", ICON_FA_PEN), "hier.view-local", !remoteView) do remoteView = false
	imgui.SameLine(0, 2)
	if seg(fmt.tprintf("%s  Remote", ICON_FA_GAMEPAD), "hier.view-remote", remoteView) do remoteView = true
	UI_Tooltip("The running game's scene tree: inspect and change it live")
	return remoteView
}
