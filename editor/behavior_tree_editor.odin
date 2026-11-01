package editor

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import imgui "lib/imgui"
import e "../engine"

// ============================================================================
// The Behavior Tree tab: the selected Behavior Tree node's tree, top-down
// (laid out automatically), with its settings in a side panel and its
// blackboard on a second page. Right-click a node to add children, wrap it
// in a decorator, change its kind, move or delete it; drag a node onto
// another to move it there (onto a sibling: that place). While the scene
// runs (Simulate, or Play through the link) each node lights up with its
// answer: running yellow, success green, failure red (as Beehave does).
// ============================================================================

BTG_BOX :: [2]f32{176, 56}
BTG_GAP :: [2]f32{22, 46}

BTG_Page :: enum {Tree, Blackboard}

@(private = "file")
btg: struct {
	node:     ^e.BehaviorTreeNode,
	zoom:     f32,
	pan:      [2]f32,
	sel:      int,
	frame:    bool,
	drag:     int,      // the node being dragged (-1: none)
	dragFrom: [2]f32,
	dragMoved: bool,
	ctxNode:  int,
	scripts:  [dynamic]BTG_Script,
	scanned:  time.Tick,
	framedCount: int,   // the node count and canvas size framed last
	framedSize:  [2]f32,
}

BTG_Script :: struct {
	path:      string,
	condition: bool,
}

// btgRemote: the game's last answer to "bt <path>" (Play).
@(private = "file")
btgRemote: struct {
	asked:   time.Tick,
	got:     bool,
	path:    string,
	ticks:   u64,
	status:  e.BT_Status,
	micros:  f32,
	nodes:   [dynamic][2]int, // status, ticks ago
	bb:      [dynamic][2]string,
}

behaviorTreeFocused: bool
behaviorTreePageRequest: Maybe(BTG_Page)

BTG_STATUS_COL := [e.BT_Status]imgui.Vec4{
	.None    = {0, 0, 0, 0},
	.Success = {0.10, 0.62, 0.34, 1}, // (Beehave's #07783a, lifted for the dark canvas)
	.Failure = {0.78, 0.16, 0.20, 1}, // #82010b
	.Running = {0.86, 0.68, 0.10, 1}, // #c29c06
}

BTG_CATEGORY_COL := [e.BT_Category]imgui.Vec4{
	.Composite = {0.36, 0.55, 1.00, 1},
	.Decorator = {0.70, 0.48, 0.98, 1},
	.Action    = {0.30, 0.81, 0.55, 1},
	.Condition = {0.96, 0.72, 0.30, 1},
}

BTG_CATEGORY_ICON := [e.BT_Category]string{
	.Composite = ICON_FA_SITEMAP,
	.Decorator = ICON_FA_FILTER,
	.Action    = ICON_FA_BOLT,
	.Condition = ICON_FA_CIRCLE_QUESTION,
}

@(private = "file")
btg_reset :: proc(t: ^e.BehaviorTreeNode) {
	btg.node = t
	btg.zoom = 1
	btg.pan = {}
	btg.sel = 0 if len(t.nodes) > 0 else -1
	btg.drag = -1
	btg.frame = true
}

// BehaviorTreeTab_Selected: the selected tree node (drives).
BehaviorTreeTab_Selected :: proc() -> int {return btg.sel}

// BehaviorTree_Render draws the tab.
BehaviorTree_Render :: proc(state: ^EditorState) {
	sel := state.selectedNode
	if sel == nil || sel.typeId != e.BehaviorTreeNode {
		imgui.Dummy({0, 8})
		UI_DimText("   Select a Behavior Tree node to edit its tree.")
		return
	}
	t := cast(^e.BehaviorTreeNode)sel
	if btg.node != t do btg_reset(t)
	if btg.sel >= len(t.nodes) do btg.sel = len(t.nodes) - 1
	behaviorTreeFocused = imgui.IsWindowFocused(imgui.FocusedFlags_RootAndChildWindows)
	if btg.zoom == 0 do btg.zoom = 1
	req, hasReq := behaviorTreePageRequest.?
	behaviorTreePageRequest = nil
	if !imgui.BeginTabBar("##btg_pages", {}) do return
	defer imgui.EndTabBar()
	page :: proc(label: cstring, id: string, p, req: BTG_Page, hasReq: bool) -> bool {
		open := imgui.BeginTabItem(label, nil, {.SetSelected} if hasReq && req == p else {})
		Drive_Item(id)
		return open
	}
	if page(fmt.ctprintf("%s  Tree###btg_tree", ICON_FA_SITEMAP), "btg.page:tree", .Tree, req, hasReq) {
		avail := imgui.GetContentRegionAvail()
		panelW: f32 = 330
		if imgui.BeginChild("##btg_canvas", {max(avail.x - panelW - 8, 200), avail.y}, {.Borders}, {.NoScrollbar, .NoScrollWithMouse}) {
			btg_canvas(state, t)
		}
		imgui.EndChild()
		imgui.SameLine()
		if imgui.BeginChild("##btg_side", {0, avail.y}, {}, {}) do btg_side_panel(state, t)
		imgui.EndChild()
		imgui.EndTabItem()
	}
	if page(fmt.ctprintf("%s  Blackboard (%d)###btg_bb", ICON_FA_LAYER_GROUP, len(t.bbInit)), "btg.page:blackboard", .Blackboard, req, hasReq) {
		if imgui.BeginChild("##btg_bb_page", {0, 0}, {}, {}) do btg_blackboard_page(state, t)
		imgui.EndChild()
		imgui.EndTabItem()
	}
}

// ----------------------------------------------------------------------------
// Layout: each node over its children; a subtree as wide as its children.
// ----------------------------------------------------------------------------

@(private = "file")
btg_layout :: proc(t: ^e.BehaviorTreeNode) -> [][2]f32 {
	pos := make([][2]f32, len(t.nodes), context.temp_allocator)
	if len(t.nodes) == 0 do return pos
	widths := make([]f32, len(t.nodes), context.temp_allocator)
	width :: proc(t: ^e.BehaviorTreeNode, i: int, widths: []f32) -> f32 {
		w: f32 = 0
		for c, k in t.nodes[i].children {
			if k > 0 do w += BTG_GAP.x
			w += width(t, c, widths)
		}
		widths[i] = max(w, BTG_BOX.x)
		return widths[i]
	}
	width(t, 0, widths)
	place_node :: proc(t: ^e.BehaviorTreeNode, i: int, left, y: f32, widths: []f32, pos: [][2]f32) {
		pos[i] = {left + (widths[i] - BTG_BOX.x) * 0.5, y}
		kids: f32 = 0
		for c, k in t.nodes[i].children {
			if k > 0 do kids += BTG_GAP.x
			kids += widths[c]
		}
		x := left + (widths[i] - kids) * 0.5
		for c in t.nodes[i].children {
			place_node(t, c, x, y + BTG_BOX.y + BTG_GAP.y, widths, pos)
			x += widths[c] + BTG_GAP.x
		}
	}
	place_node(t, 0, 0, 0, widths, pos)
	return pos
}

@(private = "file")
btg_to_screen :: proc(origin, w: [2]f32) -> [2]f32 {return origin + btg.pan + w * btg.zoom}

@(private = "file")
btg_to_world :: proc(origin, s: [2]f32) -> [2]f32 {return (s - origin - btg.pan) / btg.zoom}

// ----------------------------------------------------------------------------
// Live status: the editor's own nodes in Simulate, the game's in Play.
// ----------------------------------------------------------------------------

@(private = "file")
btg_path :: proc(state: ^EditorState, t: ^e.BehaviorTreeNode) -> string {
	return e.Node_RelativePath(state.activeScene.manager, state.activeScene.rootNode, t)
}

// btg_live: a node's answer and how many ticks ago it ran (live: false when
// nothing runs).
@(private = "file")
btg_live :: proc(state: ^EditorState, t: ^e.BehaviorTreeNode, i: int) -> (status: e.BT_Status, ago: int, live: bool) {
	if RemoteGame_Connected() && state.gameProcessRunning {
		if !btgRemote.got || btgRemote.path != btg_path(state, t) || i >= len(btgRemote.nodes) do return .None, 0, true
		return e.BT_Status(btgRemote.nodes[i][0]), btgRemote.nodes[i][1], true
	}
	if !state.isSimulating do return .None, 0, false
	n := &t.nodes[i]
	if n.rt.tick == 0 do return .None, 0, true
	return n.rt.status, int(t.ticks - n.rt.tick), true
}

@(private = "file")
btg_poll :: proc(state: ^EditorState, t: ^e.BehaviorTreeNode) {
	if !(RemoteGame_Connected() && state.gameProcessRunning) do return
	if time.duration_milliseconds(time.tick_since(btgRemote.asked)) > 250 {
		btgRemote.asked = time.tick_now()
		RemoteGame_Send(fmt.tprintf("bt %s", btg_path(state, t)))
	}
}

// BehaviorTree_RemoteReply: the game's "@rayzr:bt" answer.
BehaviorTree_RemoteReply :: proc(text: string) {
	v, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None do return
	o, ok := v.(json.Object)
	if !ok do return
	path, _ := o["path"].(json.String)
	delete(btgRemote.path)
	btgRemote.path = strings.clone(path)
	clear(&btgRemote.nodes)
	for &kv in btgRemote.bb {
		delete(kv[0])
		delete(kv[1])
	}
	clear(&btgRemote.bb)
	if _, missing := o["missing"]; missing {
		btgRemote.got = false
		return
	}
	btgRemote.got = true
	num :: proc(v: json.Value) -> f64 {
		#partial switch x in v {
		case json.Integer: return f64(x)
		case json.Float:   return f64(x)
		}
		return 0
	}
	btgRemote.ticks = u64(num(o["ticks"]))
	btgRemote.status = e.BT_Status(int(num(o["status"])))
	btgRemote.micros = f32(num(o["micros"]))
	if list, lok := o["nodes"].(json.Array); lok {
		for it in list {
			pair, pok := it.(json.Array)
			if !pok || len(pair) < 2 do continue
			append(&btgRemote.nodes, [2]int{int(num(pair[0])), int(num(pair[1]))})
		}
	}
	if bb, bok := o["blackboard"].(json.Object); bok {
		for k, val in bb {
			s, _ := val.(json.String)
			append(&btgRemote.bb, [2]string{strings.clone(k), strings.clone(s)})
		}
	}
}

// ----------------------------------------------------------------------------
// The canvas.
// ----------------------------------------------------------------------------

@(private = "file")
btg_summary :: proc(n: ^e.BT_Node) -> string {
	info := e.BT_KINDS[n.kind]
	#partial switch n.kind {
	case .Wait:
		return fmt.tprintf("%gs", n.number) if n.number2 == 0 else fmt.tprintf("%g-%gs", n.number, n.number + n.number2)
	case .Repeater:      return fmt.tprintf("x%d", int(n.number))
	case .Limiter:       return fmt.tprintf("%d ticks", int(n.number))
	case .Time_Limiter, .Cooldown, .Delayer: return fmt.tprintf("%gs", n.number)
	case .Simple_Parallel: return "delay mode" if n.flag else ""
	case .Script:        return filepath.base(n.script) if n.script != "" else "(no script)"
	case .Blackboard_Compare: return fmt.tprintf("%s%s %s %s", "G:" if n.global else "", n.key, e.BT_COMPARE_TEXT[n.op], n.value)
	case .Blackboard_Set: return fmt.tprintf("%s%s = %s", "G:" if n.global else "", n.key, n.value)
	case .Blackboard_Has, .Blackboard_Erase: return fmt.tprintf("%s%s", "G:" if n.global else "", n.key)
	case .Move_To:       return n.target if n.target != "" else (fmt.tprintf("$%s", n.key) if n.key != "" else "(no target)")
	case .Subtree:       return n.target if n.target != "" else "(no tree)"
	case .Log:           return n.value
	case .Set_Property:  return fmt.tprintf("%s = %s", n.key, n.value)
	}
	if .Key in info.fields do return n.key
	return ""
}

@(private = "file")
btg_canvas :: proc(state: ^EditorState, t: ^e.BehaviorTreeNode) {
	dl := imgui.GetWindowDrawList()
	origin := imgui.GetCursorScreenPos()
	size := imgui.GetContentRegionAvail()
	io := imgui.GetIO()
	mouse := [2]f32{io.MousePos.x, io.MousePos.y}
	hovered := imgui.IsWindowHovered()
	imgui.DrawList_AddRectFilled(dl, origin, origin + size, col_u32(CODE_BG))
	Drive_ItemRect("btg.canvas", origin, origin + size, inWindow = true)
	btg_poll(state, t)
	pos := btg_layout(t)
	// Frame the tree: first show, F, nodes added or removed, the panel resized.
	if len(t.nodes) != btg.framedCount || abs(size.x - btg.framedSize.x) > 30 || abs(size.y - btg.framedSize.y) > 30 do btg.frame = true
	if len(t.nodes) > 0 && ((btg.frame && size.x > 120 && size.y > 80) || (hovered && imgui.IsKeyPressed(.F) && !io.WantTextInput)) {
		btg.frame = false
		btg.framedCount, btg.framedSize = len(t.nodes), size
		mn, mx := pos[0], pos[0] + BTG_BOX
		for p in pos {
			mn = {min(mn.x, p.x), min(mn.y, p.y)}
			mx = {max(mx.x, p.x + BTG_BOX.x), max(mx.y, p.y + BTG_BOX.y)}
		}
		ext := mx - mn + {48, 40}
		btg.zoom = clamp(min(size.x / ext.x, size.y / ext.y), 0.3, 1.0)
		btg.pan = {(size.x - (mx.x - mn.x) * btg.zoom) * 0.5 - mn.x * btg.zoom, 16 - mn.y * btg.zoom}
	}
	if hovered && (io.MouseWheel != 0 || io.MouseWheelH != 0) {
		if io.KeyCtrl || io.KeySuper {
			before := btg_to_world(origin, mouse)
			btg.zoom = clamp(btg.zoom * (1 + io.MouseWheel * 0.1), 0.3, 2.5)
			btg.pan += mouse - btg_to_screen(origin, before)
		} else if io.KeyShift {
			btg.pan.x += io.MouseWheel * 30
		} else {
			btg.pan += {io.MouseWheelH * 30, io.MouseWheel * 30}
		}
	}
	if hovered && imgui.IsMouseDragging(.Middle) do btg.pan += {io.MouseDelta.x, io.MouseDelta.y}

	// Links: parent's bottom to child's top (lit with the child's answer).
	for &n, i in t.nodes {
		if len(n.children) == 0 do continue
		from := btg_to_screen(origin, pos[i] + {BTG_BOX.x * 0.5, BTG_BOX.y})
		midY := from.y + BTG_GAP.y * 0.5 * btg.zoom
		for c in n.children {
			to := btg_to_screen(origin, pos[c] + {BTG_BOX.x * 0.5, 0})
			col := ui_line(0.25)
			thick: f32 = 1.5
			if s, ago, live := btg_live(state, t, c); live && s != .None && ago <= 1 {
				col = BTG_STATUS_COL[s]
				thick = 2.5
			}
			imgui.DrawList_AddLine(dl, from, {from.x, midY}, col_u32(col), thick)
			imgui.DrawList_AddLine(dl, {from.x, midY}, {to.x, midY}, col_u32(col), thick)
			imgui.DrawList_AddLine(dl, {to.x, midY}, to, col_u32(col), thick)
			if s, ago, live := btg_live(state, t, c); live && s == .Running && ago <= 1 {
				// A dot running down the link.
				f := f32(math.mod(time.duration_seconds(time.tick_since(time.Tick{})) * 1.5, 1.0))
				p := [2]f32{to.x, midY + (to.y - midY) * f}
				imgui.DrawList_AddCircleFilled(dl, p, 3.5, col_u32(col))
			}
		}
	}

	// Boxes.
	hoverNode := -1
	for &n, i in t.nodes {
		mn := btg_to_screen(origin, pos[i])
		mx := mn + BTG_BOX * btg.zoom
		if hovered && point_in_rect(mouse, mn, mx) do hoverNode = i
		info := e.BT_KINDS[n.kind]
		cat := info.category
		if n.kind == .Script {
			for s in btg.scripts do if s.path == n.script && s.condition do cat = .Condition
		}
		fill := UI_BG_RAISED
		status, ago, live := btg_live(state, t, i)
		if live && status != .None {
			fade := clamp(1 - f32(ago) / 30, 0.25, 1)
			c := BTG_STATUS_COL[status]
			fill = {c.x * 0.35 * fade + fill.x * (1 - 0.35 * fade), c.y * 0.35 * fade + fill.y * (1 - 0.35 * fade), c.z * 0.35 * fade + fill.z * (1 - 0.35 * fade), 1}
		}
		imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32(fill), 7)
		imgui.DrawList_AddRectFilled(dl, mn, {mn.x + 4 * btg.zoom, mx.y}, col_u32(BTG_CATEGORY_COL[cat]), 7)
		border := ui_line(0.18)
		thick: f32 = 1
		if live && status != .None && ago <= 1 {
			border = BTG_STATUS_COL[status]
			thick = 2
		}
		if btg.sel == i {
			border = UI_ACCENT
			thick = 2
		}
		imgui.DrawList_AddRect(dl, mn, mx, col_u32(border), 7, {}, thick)
		pad := [2]f32{12, 7} * btg.zoom
		title := fmt.ctprintf("%s  %s", BTG_CATEGORY_ICON[cat], e.BT_NodeName(&n))
		imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.semibold, imgui.GetFontSize() * btg.zoom, mn + pad, col_u32(UI_TEXT), title)
		if btg.zoom > 0.55 {
			sub := btg_summary(&n)
			if n.name != "" do sub = fmt.tprintf("%s  %s", info.name, sub)
			if live && status != .None do sub = fmt.tprintf("%s  · %s", sub, e.BT_STATUS_TEXT[status])
			imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, 12 * btg.zoom, {mn.x + pad.x, mx.y - pad.y - 13 * btg.zoom}, col_u32(UI_TEXT_DIM), strings.clone_to_cstring(sub, context.temp_allocator))
		}
		Drive_ItemRect(fmt.tprintf("btg.node:%d", i), mn, mx, inWindow = true)
	}

	// Mouse: select, drag a node onto another to move it there.
	if hovered && (imgui.IsMouseClicked(.Left) || imgui.IsMouseClicked(.Right)) do imgui.SetWindowFocus()
	if hovered && imgui.IsMouseClicked(.Left) {
		btg.sel = hoverNode
		btg.drag = hoverNode
		btg.dragFrom = mouse
		btg.dragMoved = false
	}
	if btg.drag >= 0 && imgui.IsMouseDown(.Left) {
		d := mouse - btg.dragFrom
		if d.x * d.x + d.y * d.y > 36 do btg.dragMoved = true
		if btg.dragMoved {
			imgui.DrawList_AddLine(dl, btg_to_screen(origin, pos[btg.drag] + BTG_BOX * 0.5), mouse, col_u32(UI_ACCENT), 2)
			if hoverNode >= 0 && hoverNode != btg.drag {
				mn := btg_to_screen(origin, pos[hoverNode])
				imgui.DrawList_AddRect(dl, mn - {3, 3}, mn + BTG_BOX * btg.zoom + {3, 3}, col_u32(UI_ACCENT), 9, {}, 2)
			}
		}
	}
	if btg.drag >= 0 && imgui.IsMouseReleased(.Left) {
		if btg.dragMoved && hoverNode >= 0 && hoverNode != btg.drag do btg_drop(state, t, btg.drag, hoverNode)
		btg.drag = -1
	}
	if btg.sel >= 0 && (imgui.IsWindowFocused() || hovered) && !io.WantTextInput && !Code_HasFocus() && (imgui.IsKeyPressed(.Delete) || imgui.IsKeyPressed(.Backspace)) {
		Editor_RecordUndo(state, "Delete behavior tree node")
		e.BT_RemoveNode(t, btg.sel)
		btg.sel = -1
	}
	if hovered && imgui.IsMouseClicked(.Right) {
		btg.ctxNode = hoverNode
		if hoverNode >= 0 do btg.sel = hoverNode
		imgui.OpenPopup("##btg_ctx")
	}
	if imgui.BeginPopup("##btg_ctx") {
		btg_context_menu(state, t)
		imgui.EndPopup()
	}
	if len(t.nodes) == 0 {
		imgui.SetCursorScreenPos(origin + {16, 12})
		UI_DimText("An empty tree. Right-click to add its root - usually a Selector or a Sequence.")
		imgui.SetCursorScreenPos(origin + {16, 38})
		if UI_Button(fmt.tprintf("%s  Add Root Selector", ICON_FA_PLUS), "btg.add-root") {
			Editor_RecordUndo(state, "Add behavior tree root")
			btg.sel = e.BT_AddNode(t, -1, .Selector)
		}
	}
	// The tick time while live.
	if _, _, live := btg_live(state, t, 0); live && len(t.nodes) > 0 {
		micros := btgRemote.micros if RemoteGame_Connected() && state.gameProcessRunning else t.tickMicros
		ticks := btgRemote.ticks if RemoteGame_Connected() && state.gameProcessRunning else t.ticks
		imgui.DrawList_AddText(dl, origin + {8, size.y - 20}, col_u32(UI_TEXT_DIM), fmt.ctprintf("tick %d · %.0f µs", ticks, micros))
	}
}

// btg_drop: node `from` dropped onto `onto`: a sibling takes its place,
// anything else gets it as its last child.
@(private = "file")
btg_drop :: proc(state: ^EditorState, t: ^e.BehaviorTreeNode, from, onto: int) {
	if from == 0 do return
	Editor_RecordUndo(state, "Move behavior tree node")
	parent := t.nodes[from].parent
	if t.nodes[onto].parent == parent && parent >= 0 {
		at := 0
		for c, k in t.nodes[parent].children do if c == onto do at = k
		e.BT_MoveNode(t, from, parent, at)
		return
	}
	if e.BT_IsLeaf(t.nodes[onto].kind) || !e.BT_MoveNode(t, from, onto, -1) {
		Editor_Log(state, .Warn, "%s can't take another child", e.BT_NodeName(&t.nodes[onto]))
	}
}

@(private = "file")
btg_kind_menu :: proc(state: ^EditorState, label: string, cats: bit_set[e.BT_Category]) -> (kind: e.BT_Kind, script: string, picked: bool) {
	for cat in e.BT_Category {
		if cat not_in cats do continue
		open := imgui.BeginMenu(fmt.ctprintf("%s  %vs", BTG_CATEGORY_ICON[cat], cat))
		Drive_Item(fmt.tprintf("btg.cat:%v", cat))
		if !open do continue
		for k in e.BT_Kind {
			info := e.BT_KINDS[k]
			if info.category != cat || k == .Script do continue
			if imgui.MenuItem(strings.clone_to_cstring(info.name, context.temp_allocator)) do kind, picked = k, true
			Drive_Item(fmt.tprintf("pick:%s", info.name))
			if imgui.IsItemHovered() do imgui.SetTooltip("%s", strings.clone_to_cstring(info.doc, context.temp_allocator))
		}
		if cat == .Action || cat == .Condition {
			btg_scan_scripts(state)
			any := false
			for s in btg.scripts {
				if s.condition != (cat == .Condition) do continue
				if !any do imgui.Separator()
				any = true
				if imgui.MenuItem(fmt.ctprintf("%s  %s", ICON_FA_CODE, filepath.stem(s.path))) do kind, script, picked = .Script, s.path, true
				Drive_Item(fmt.tprintf("pick:%s", s.path))
			}
			if cat == .Action {
				imgui.Separator()
				if imgui.MenuItem(fmt.ctprintf("%s  Script (pick a file)", ICON_FA_CODE)) do kind, picked = .Script, true
				Drive_Item("pick:Script")
			}
		}
		imgui.EndMenu()
	}
	return
}

@(private = "file")
btg_context_menu :: proc(state: ^EditorState, t: ^e.BehaviorTreeNode) {
	i := btg.ctxNode
	if i < 0 || i >= len(t.nodes) {
		if len(t.nodes) == 0 {
			UI_DimText("Add the root")
			if k, s, ok := btg_kind_menu(state, "Root", {.Composite, .Decorator, .Action, .Condition}); ok {
				Editor_RecordUndo(state, "Add behavior tree root")
				btg.sel = e.BT_AddNode(t, -1, k)
				if s != "" do e.BT_SetString(t, &t.nodes[btg.sel].script, s)
			}
		} else {
			UI_DimText("Right-click a node to add to it")
		}
		return
	}
	n := &t.nodes[i]
	max := e.BT_MaxChildren(n.kind)
	canAdd := max < 0 || len(n.children) < max
	imgui.BeginDisabled(!canAdd)
	addOpen := imgui.BeginMenu(fmt.ctprintf("%s  Add Child", ICON_FA_PLUS))
	Drive_Item("btg.ctx.add")
	if addOpen {
		if k, s, ok := btg_kind_menu(state, "Child", {.Composite, .Decorator, .Action, .Condition}); ok {
			Editor_RecordUndo(state, "Add behavior tree node")
			c := e.BT_AddNode(t, i, k)
			if c >= 0 {
				if s != "" do e.BT_SetString(t, &t.nodes[c].script, s)
				btg.sel = c
			}
		}
		imgui.EndMenu()
	}
	imgui.EndDisabled()
	wrapOpen := imgui.BeginMenu(fmt.ctprintf("%s  Wrap In", ICON_FA_LAYER_GROUP))
	Drive_Item("btg.ctx.wrap")
	if wrapOpen {
		if k, _, ok := btg_kind_menu(state, "Wrap", {.Decorator, .Composite}); ok {
			Editor_RecordUndo(state, "Wrap behavior tree node")
			btg.sel = e.BT_WrapNode(t, i, k)
		}
		imgui.EndMenu()
	}
	changeOpen := imgui.BeginMenu(fmt.ctprintf("%s  Change To", ICON_FA_ROTATE))
	Drive_Item("btg.ctx.change")
	if changeOpen {
		cats: bit_set[e.BT_Category] = {.Action, .Condition} if e.BT_IsLeaf(n.kind) else {.Composite, .Decorator}
		if k, s, ok := btg_kind_menu(state, "Change", cats); ok {
			Editor_RecordUndo(state, "Change behavior tree node")
			e.BT_SetKind(t, i, k)
			if s != "" do e.BT_SetString(t, &t.nodes[i].script, s)
		}
		imgui.EndMenu()
	}
	p := n.parent
	if p >= 0 {
		k := 0
		for c, j in t.nodes[p].children do if c == i do k = j
		if imgui.MenuItem(fmt.ctprintf("%s  Move Left", ICON_FA_ARROW_LEFT), nil, false, k > 0) {
			Editor_RecordUndo(state, "Move behavior tree node")
			e.BT_MoveNode(t, i, p, k - 1)
		}
		if imgui.MenuItem(fmt.ctprintf("%s  Move Right", ICON_FA_ARROW_RIGHT), nil, false, k < len(t.nodes[p].children) - 1) {
			Editor_RecordUndo(state, "Move behavior tree node")
			e.BT_MoveNode(t, i, p, k + 2)
		}
	}
	imgui.Separator()
	if imgui.MenuItem(fmt.ctprintf("%s  Delete", ICON_FA_TRASH), "Del") {
		Editor_RecordUndo(state, "Delete behavior tree node")
		e.BT_RemoveNode(t, i)
		btg.sel = -1
	}
	Drive_Item("btg.ctx.delete")
}

// btg_scan_scripts: the project's leaf scripts (`X.behavior = "action"`),
// looked for again every few seconds.
@(private = "file")
btg_scan_scripts :: proc(state: ^EditorState) {
	if btg.scanned != {} && time.duration_seconds(time.tick_since(btg.scanned)) < 3 do return
	btg.scanned = time.tick_now()
	for s in btg.scripts do delete(s.path)
	clear(&btg.scripts)
	for rel in Editor_ListProjectFiles(state, "", {".lua"}) {
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		data, err := os.read_entire_file(full, context.temp_allocator)
		if err != nil do continue
		if kind := BehaviorTree_LeafMarker(string(data)); kind != "" {
			append(&btg.scripts, BTG_Script{strings.clone(rel), kind == "condition"})
		}
	}
}

// BehaviorTree_LeafMarker: "action" / "condition" when Lua text marks its
// table a leaf (`X.behavior = "action"`), else "".
BehaviorTree_LeafMarker :: proc(text: string) -> string {
	text := text
	for line in strings.split_lines_iterator(&text) {
		l := strings.trim_space(line)
		i := strings.index(l, ".behavior")
		if i <= 0 do continue
		ident := true
		for r in l[:i] do if !(r == '_' || (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9')) do ident = false
		if !ident do continue
		rest := strings.trim_left_space(l[i + len(".behavior"):])
		if !strings.has_prefix(rest, "=") do continue
		rest = strings.trim_space(rest[1:])
		if strings.has_prefix(rest, "\"action\"") || strings.has_prefix(rest, "'action'") do return "action"
		if strings.has_prefix(rest, "\"condition\"") || strings.has_prefix(rest, "'condition'") do return "condition"
	}
	return ""
}

// ----------------------------------------------------------------------------
// The side panel: the selected node's settings.
// ----------------------------------------------------------------------------

@(private = "file")
btg_text :: proc(state: ^EditorState, t: ^e.BehaviorTreeNode, id: string, s: ^string, hint: cstring = "") {
	buf: [256]u8
	copy(buf[:len(buf) - 1], s^)
	imgui.SetNextItemWidth(-1)
	if imgui.InputTextWithHint(fmt.ctprintf("##%s", id), hint, cstring(raw_data(buf[:])), len(buf), {}) {
		e.BT_SetString(t, s, string(cstring(raw_data(buf[:]))))
	}
	undo_on_activate(state, "Edit behavior tree node")
	Drive_Item(id)
}

// btgProps: the leaf whose script values the props editor sets.
@(private = "file")
btgProps: struct {
	tree:  ^e.BehaviorTreeNode,
	index: int,
}

@(private = "file")
btg_side_panel :: proc(state: ^EditorState, t: ^e.BehaviorTreeNode) {
	if btg.sel < 0 || btg.sel >= len(t.nodes) {
		UI_DimTextWrapped("Click a node to edit it. Right-click a node to add children, wrap it in a decorator, change it or delete it; drag a node onto another to move it there. F frames the tree.")
		if status := t.status; status != .None do UI_DimText(fmt.tprintf("Last answer: %s", e.BT_STATUS_TEXT[status]))
		return
	}
	i := btg.sel
	n := &t.nodes[i]
	info := e.BT_KINDS[n.kind]
	imgui.PushFont(GlobalFonts.semibold)
	imgui.TextUnformatted(fmt.ctprintf("%s  %s", BTG_CATEGORY_ICON[info.category], info.name))
	imgui.PopFont()
	UI_DimTextWrapped(info.doc)
	if !UI_BeginProps("##btg_props") do return
	defer UI_EndProps()
	UI_PropLabel("Name")
	btg_text(state, t, "btg.name", &n.name, strings.clone_to_cstring(info.name, context.temp_allocator))
	if p := n.parent; p >= 0 && t.nodes[p].weights && (t.nodes[p].kind == .Sequence_Random || t.nodes[p].kind == .Selector_Random) {
		UI_PropLabel("Weight")
		imgui.SetNextItemWidth(-1)
		imgui.DragFloat("##btg.weight", &n.weight, 0.2, 1, 100, "%.0f")
		undo_on_activate(state, "Behavior tree weight")
		UI_Tooltip("How likely this child comes early in the shuffled order (1-100)")
	}
	num :: proc(state: ^EditorState, label, id: string, v: ^f32, whole: bool) {
		UI_PropLabel(label)
		imgui.SetNextItemWidth(-1)
		if whole {
			x := i32(v^)
			if imgui.DragInt(fmt.ctprintf("##%s", id), &x, 0.2, 0, 100000) do v^ = f32(max(x, 0))
		} else {
			imgui.DragFloat(fmt.ctprintf("##%s", id), v, 0.05, 0, 100000, "%.2f")
		}
		undo_on_activate(state, "Edit behavior tree node")
		Drive_Item(id)
	}
	whole := n.kind == .Repeater || n.kind == .Limiter || n.kind == .Simple_Parallel
	if .Number in info.fields do num(state, info.number, "btg.number", &n.number, whole)
	if .Number2 in info.fields do num(state, info.number2, "btg.number2", &n.number2, false)
	if .Flag in info.fields {
		UI_PropLabel(info.flag)
		if imgui.Checkbox("##btg.flag", &n.flag) do Editor_RecordUndo(state, "Edit behavior tree node")
		Drive_Item("btg.flag")
	}
	if .Flag2 in info.fields {
		UI_PropLabel(info.flag2)
		if imgui.Checkbox("##btg.flag2", &n.flag2) do Editor_RecordUndo(state, "Edit behavior tree node")
	}
	if .Seed in info.fields {
		UI_PropLabel("Seed")
		s := i32(n.seed)
		imgui.SetNextItemWidth(-1)
		if imgui.InputInt("##btg.seed", &s) do n.seed = int(max(s, 0))
		undo_on_activate(state, "Edit behavior tree node")
		UI_Tooltip("The same seed: the same shuffles every run (0: different each run)")
	}
	if .Weights in info.fields {
		UI_PropLabel("Weights")
		if imgui.Checkbox("##btg.weights", &n.weights) do Editor_RecordUndo(state, "Edit behavior tree node")
		UI_Tooltip("Its children get a Weight (1-100): heavier ones tend to come first")
	}
	if .Target in info.fields {
		UI_PropLabel(info.target)
		if path, changed := node_ref_field(state, t, "btg.target", n.target); changed {
			Editor_RecordUndo(state, "Edit behavior tree node")
			e.BT_SetString(t, &n.target, path)
		}
	}
	if .Key in info.fields {
		UI_PropLabel(info.key)
		btg_text(state, t, "btg.key", &n.key)
	}
	if .Op in info.fields {
		UI_PropLabel("Compare")
		op := i32(n.op)
		imgui.SetNextItemWidth(-1)
		if imgui.Combo("##btg.op", &op, "==\x00!=\x00>\x00<\x00>=\x00<=\x00") {
			Editor_RecordUndo(state, "Edit behavior tree node")
			n.op = e.BT_Compare(op)
		}
	}
	if .Value in info.fields {
		UI_PropLabel(info.value)
		btg_text(state, t, "btg.value", &n.value, "a value, or $key")
		UI_Tooltip("true / false, a number, \"x, y\", text; \"$key\" reads the blackboard")
	}
	if .Global in info.fields {
		UI_PropLabel("Global")
		if imgui.Checkbox("##btg.global", &n.global) do Editor_RecordUndo(state, "Edit behavior tree node")
		UI_Tooltip("Use the global blackboard (shared by every tree) instead of this tree's")
	}
	if .Script in info.fields {
		UI_PropLabel("Script")
		btg_scan_scripts(state)
		files := make([dynamic]string, context.temp_allocator)
		for s in btg.scripts do append(&files, s.path)
		imgui.SetNextItemWidth(-1)
		if path, ok := asset_picker("btg.script", n.script, files[:]); ok {
			Editor_RecordUndo(state, "Edit behavior tree node")
			e.BT_SetString(t, &n.script, path)
		}
		if n.script != "" {
			if mod, ok := e.ScriptManager_LoadModule(n.script, &state.game.scriptManager); ok && mod != nil {
				btgProps = {t, i}
				target := Script_PropsTarget{
					mod         = mod,
					modulePath  = n.script,
					values      = &n.props,
					owner       = nil,
					idPrefix    = "btg.prop",
					data        = state,
					set         = proc(state: ^EditorState, pt: ^Script_PropsTarget, name: string, val: e.ScriptValue) {
						t, i := btgProps.tree, btgProps.index
						if !e.Node_IsAlive(t) || i >= len(t.nodes) do return
						n := &t.nodes[i]
						if n.props == nil do n.props = make(map[string]e.ScriptValue, t.allocator)
						v := val
						if v.valString != "" do v.valString = strings.clone(v.valString, t.allocator)
						for k, old in n.props do if k == name {
							if old.valString != "" do delete(old.valString, t.allocator)
							n.props[k] = v
							return
						}
						n.props[strings.clone(name, t.allocator)] = v
					},
					record_undo = proc(state: ^EditorState, pt: ^Script_PropsTarget, label: string) {Editor_RecordUndo(state, label)},
				}
				script_props_editor(state, &target)
			}
		}
	}
	if status, ago, live := btg_live(state, t, i); live {
		UI_PropLabel("Live")
		UI_DimText(fmt.tprintf("%s (%d ticks ago)", e.BT_STATUS_TEXT[status], ago) if status != .None else "not run yet")
	}
}

// ----------------------------------------------------------------------------
// The Blackboard page: its starting values, and the live ones.
// ----------------------------------------------------------------------------

@(private = "file")
btg_blackboard_page :: proc(state: ^EditorState, t: ^e.BehaviorTreeNode) {
	UI_DimTextWrapped("Starting values of this tree's blackboard (true / false, numbers, \"x, y\", text). Leaves and scripts read and change them while it runs; a tree with Blackboard From uses that tree's instead.")
	remove := -1
	for &entry, k in t.bbInit {
		imgui.PushIDInt(i32(k))
		w := (imgui.GetContentRegionAvail().x - 36) * 0.5
		imgui.SetNextItemWidth(w)
		btg_entry(state, t, "btg.bb.key", &entry.key, w)
		imgui.SameLine()
		btg_entry(state, t, "btg.bb.value", &entry.value, w)
		imgui.SameLine()
		if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("btg.bb.remove:%d", k), "Remove", size = 24) do remove = k
		imgui.PopID()
	}
	if remove >= 0 {
		Editor_RecordUndo(state, "Remove blackboard value")
		delete(t.bbInit[remove].key, t.allocator)
		delete(t.bbInit[remove].value, t.allocator)
		ordered_remove(&t.bbInit, remove)
	}
	if UI_Button(fmt.tprintf("%s  Add Value", ICON_FA_PLUS), "btg.bb.add") {
		Editor_RecordUndo(state, "Add blackboard value")
		append(&t.bbInit, e.BT_BB_Entry{strings.clone(fmt.tprintf("key%d", len(t.bbInit) + 1), t.allocator), strings.clone("0", t.allocator)})
	}
	imgui.Dummy({0, 8})
	if RemoteGame_Connected() && state.gameProcessRunning {
		btg_poll(state, t)
		UI_DimText("Live (the game):")
		for kv in btgRemote.bb do imgui.TextUnformatted(fmt.ctprintf("%s = %s", kv[0], kv[1]))
	} else if state.isSimulating {
		UI_DimText("Live (Simulate):")
		bb := e.BehaviorTree_Blackboard(t)
		for k, v in bb^ do imgui.TextUnformatted(fmt.ctprintf("%s = %s", k, e.BB_Text(v)))
		if len(e.btGlobal) > 0 {
			UI_DimText("Global:")
			for k, v in e.btGlobal do imgui.TextUnformatted(fmt.ctprintf("%s = %s", k, e.BB_Text(v)))
		}
	}
}

@(private = "file")
btg_entry :: proc(state: ^EditorState, t: ^e.BehaviorTreeNode, id: string, s: ^string, w: f32) {
	buf: [256]u8
	copy(buf[:len(buf) - 1], s^)
	imgui.SetNextItemWidth(w)
	if imgui.InputText(fmt.ctprintf("##%s", id), cstring(raw_data(buf[:])), len(buf), {}) {
		e.BT_SetString(t, s, string(cstring(raw_data(buf[:]))))
	}
	undo_on_activate(state, "Edit blackboard value")
	Drive_Item(id)
}

inspector_behavior_tree :: proc(state: ^EditorState, t: ^e.BehaviorTreeNode) {
	if UI_SectionHeader("Tree") {
		if UI_BeginProps("##btinsp") {
			UI_PropLabel("Nodes")
			UI_DimText(fmt.tprintf("%d", len(t.nodes)) if len(t.nodes) > 0 else "empty")
			Drive_Item("insp.bt.count")
			if state.isSimulating && t.status != .None {
				UI_PropLabel("Answer")
				imgui.TextColored(BTG_STATUS_COL[t.status], "%s", fmt.ctprintf("%s  (%d ticks)", e.BT_STATUS_TEXT[t.status], t.ticks))
				if t.runningAction >= 0 && t.runningAction < len(t.nodes) {
					UI_PropLabel("Running")
					UI_DimText(e.BT_NodeName(&t.nodes[t.runningAction]))
				}
			}
			UI_EndProps()
		}
		if UI_Button(fmt.tprintf("%s  Edit in Behavior Tree Tab", ICON_FA_SITEMAP), "insp.bt.edit", {-1, 0}) do bottomTabRequest = .BehaviorTree
		UI_Tooltip("The tree and its blackboard are edited in the Behavior Tree tab of the bottom panel")
	}
}

// BehaviorTree_Query: drive queries - bt-tree: the selected tree as
// "Selector(Wait,Inverter(Log))"; bt-live: its nodes' live answers.
BehaviorTree_Query :: proc(state: ^EditorState, q: string) -> (string, bool) {
	sel := state.selectedNode
	if sel == nil || sel.typeId != e.BehaviorTreeNode do return "", true
	t := cast(^e.BehaviorTreeNode)sel
	sb := strings.builder_make(context.temp_allocator)
	switch q {
	case "bt-tree":
		write :: proc(sb: ^strings.Builder, t: ^e.BehaviorTreeNode, i: int) {
			strings.write_string(sb, e.BT_NodeName(&t.nodes[i]))
			if len(t.nodes[i].children) == 0 do return
			strings.write_byte(sb, '(')
			for c, k in t.nodes[i].children {
				if k > 0 do strings.write_byte(sb, ',')
				write(sb, t, c)
			}
			strings.write_byte(sb, ')')
		}
		if len(t.nodes) > 0 do write(&sb, t, 0)
	case "bt-view":
		strings.write_string(&sb, fmt.tprintf("zoom=%.2f pan=%.0f,%.0f", btg.zoom, btg.pan.x, btg.pan.y))
	case "bt-live":
		for _, i in t.nodes {
			s, _, _ := btg_live(state, t, i)
			if i > 0 do strings.write_byte(&sb, ',')
			strings.write_string(&sb, e.BT_STATUS_TEXT[s])
		}
	}
	return strings.to_string(sb), true
}

BehaviorTree_Shutdown :: proc() {
	for s in btg.scripts do delete(s.path)
	delete(btg.scripts)
	delete(btgRemote.path)
	delete(btgRemote.nodes)
	for kv in btgRemote.bb {
		delete(kv[0])
		delete(kv[1])
	}
	delete(btgRemote.bb)
}
