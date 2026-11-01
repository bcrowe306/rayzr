package editor

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import imgui "lib/imgui"
import e "../engine"

// ============================================================================
// The GOAP tab (after crashkonijn/GOAP's Graph Viewer): each goal a row,
// left to right - the goal, then the actions that can meet its conditions,
// then theirs. A box shows its cost, its target and its conditions (a dot:
// green when met - or, editing, when some action can meet it; red when not)
// and its effects. While the scene runs (Simulate, or Play through the
// link) the plan is outlined blue, the running action green, disabled
// actions orange, and the links along the plan turn cyan. The side panel
// edits the selected goal or action; Keys & Sensors lists the agent's keys
// (with their live values) and sensors.
// ============================================================================

GOAPG_W   :: f32(220)
GOAPG_ROW :: f32(17)
GOAPG_GAP :: [2]f32{70, 18}

GOAPG_PLAN    := imgui.Vec4{0.00, 0.62, 1.00, 1} // #009dff
GOAPG_RUNNING := imgui.Vec4{0.10, 0.56, 0.09, 1} // #1A9018 (a little brighter on the dark canvas)
GOAPG_OFF     := imgui.Vec4{1.00, 0.24, 0.00, 1} // #ff3c00
GOAPG_LINK    := imgui.Vec4{0.00, 1.00, 1.00, 1} // cyan
GOAPG_MET     := imgui.Vec4{0.20, 0.80, 0.30, 1}
GOAPG_UNMET   := imgui.Vec4{0.85, 0.15, 0.15, 1}

GoapG_Page :: enum {Graph, Keys}

@(private = "file")
GoapG_Box :: struct {
	goal:   bool,
	index:  int,
	parent: int,    // box index (-1: a goal row)
	cond:   int,    // the parent's condition row it meets
	depth:  int,
	pos:    [2]f32,
	h:      f32,
}

@(private = "file")
gg: struct {
	node:     ^e.GoapNode,
	zoom:     f32,
	pan:      [2]f32,
	selGoal:  int,
	selAction: int,
	frame:    bool,
	framed:   int,
	ctxBox:   int,
	scripts:  [dynamic][2]string, // path, kind
	scanned:  time.Tick,
}

// ggRemote: the game's last answer to "goap <path>" (Play).
@(private = "file")
ggRemote: struct {
	asked:   time.Tick,
	got:     bool,
	path:    string,
	goal:    int,
	action:  int,
	state:   int,
	plan:    [dynamic]int,
	costs:   [dynamic]f32,
	enabled: [dynamic]bool,
	goalCosts: [dynamic]f32,
	values:  [dynamic][4]f32, // world: value, age; target: valid, x, y, age
}

goapGraphFocused: bool
goapPageRequest: Maybe(GoapG_Page)

@(private = "file")
gg_reset :: proc(g: ^e.GoapNode) {
	gg.node = g
	gg.zoom = 1
	gg.pan = {}
	gg.selGoal, gg.selAction = (0 if len(g.goals) > 0 else -1), -1
	gg.frame = true
}

// GoapTab_Render draws the tab.
GoapTab_Render :: proc(state: ^EditorState) {
	sel := state.selectedNode
	if sel == nil || sel.typeId != e.GoapNode {
		imgui.Dummy({0, 8})
		UI_DimText("   Select a GOAP node to edit its goals, actions, keys and sensors.")
		return
	}
	g := cast(^e.GoapNode)sel
	if gg.node != g do gg_reset(g)
	if gg.selGoal >= len(g.goals) do gg.selGoal = -1
	if gg.selAction >= len(g.actions) do gg.selAction = -1
	goapGraphFocused = imgui.IsWindowFocused(imgui.FocusedFlags_RootAndChildWindows)
	gg_poll(state, g)
	req, hasReq := goapPageRequest.?
	goapPageRequest = nil
	if !imgui.BeginTabBar("##gg_pages", {}) do return
	defer imgui.EndTabBar()
	page :: proc(label: cstring, id: string, p, req: GoapG_Page, hasReq: bool) -> bool {
		open := imgui.BeginTabItem(label, nil, {.SetSelected} if hasReq && req == p else {})
		Drive_Item(id)
		return open
	}
	if page(fmt.ctprintf("%s  Goals & Actions###gg_graph", ICON_FA_BULLSEYE), "gg.page:graph", .Graph, req, hasReq) {
		avail := imgui.GetContentRegionAvail()
		panelW: f32 = 340
		if imgui.BeginChild("##gg_canvas", {max(avail.x - panelW - 8, 200), avail.y}, {.Borders}, {.NoScrollbar, .NoScrollWithMouse}) do gg_canvas(state, g)
		imgui.EndChild()
		imgui.SameLine()
		if imgui.BeginChild("##gg_side", {0, avail.y}, {}, {}) do gg_side_panel(state, g)
		imgui.EndChild()
		imgui.EndTabItem()
	}
	if page(fmt.ctprintf("%s  Keys & Sensors (%d / %d)###gg_keys", ICON_FA_LAYER_GROUP, len(g.keys), len(g.sensors)), "gg.page:keys", .Keys, req, hasReq) {
		if imgui.BeginChild("##gg_keys_page", {0, 0}, {}, {}) do gg_keys_page(state, g)
		imgui.EndChild()
		imgui.EndTabItem()
	}
}

// ----------------------------------------------------------------------------
// Live data: the editor's node in Simulate, the game's in Play.
// ----------------------------------------------------------------------------

@(private = "file")
gg_remote_on :: proc(state: ^EditorState) -> bool {return RemoteGame_Connected() && state.gameProcessRunning}

@(private = "file")
gg_live :: proc(state: ^EditorState) -> bool {return state.isSimulating || gg_remote_on(state)}

@(private = "file")
gg_path :: proc(state: ^EditorState, g: ^e.GoapNode) -> string {
	return e.Node_RelativePath(state.activeScene.manager, state.activeScene.rootNode, g)
}

@(private = "file")
gg_poll :: proc(state: ^EditorState, g: ^e.GoapNode) {
	if !gg_remote_on(state) do return
	if time.duration_milliseconds(time.tick_since(ggRemote.asked)) > 250 {
		ggRemote.asked = time.tick_now()
		RemoteGame_Send(fmt.tprintf("goap %s", gg_path(state, g)))
	}
}

@(private = "file")
gg_remote_ok :: proc(state: ^EditorState, g: ^e.GoapNode) -> bool {
	return gg_remote_on(state) && ggRemote.got && ggRemote.path == gg_path(state, g)
}

@(private = "file")
gg_cur_goal :: proc(state: ^EditorState, g: ^e.GoapNode) -> int {
	if gg_remote_on(state) do return ggRemote.goal if gg_remote_ok(state, g) else -1
	return g.goal if state.isSimulating else -1
}

@(private = "file")
gg_cur_action :: proc(state: ^EditorState, g: ^e.GoapNode) -> int {
	if gg_remote_on(state) do return ggRemote.action if gg_remote_ok(state, g) else -1
	return g.action if state.isSimulating else -1
}

@(private = "file")
gg_plan :: proc(state: ^EditorState, g: ^e.GoapNode) -> []int {
	if gg_remote_on(state) do return ggRemote.plan[:] if gg_remote_ok(state, g) else nil
	return g.plan[:] if state.isSimulating else nil
}

// gg_value: a world key's live value (ok: false when not live / unknown).
@(private = "file")
gg_value :: proc(state: ^EditorState, g: ^e.GoapNode, key: string) -> (int, bool) {
	if gg_remote_on(state) {
		i := e.Goap_FindKey(g, key)
		if !gg_remote_ok(state, g) || i < 0 || i >= len(ggRemote.values) do return 0, false
		return int(ggRemote.values[i][0]), true
	}
	if !state.isSimulating do return 0, false
	return e.Goap_GetValue(g, key)
}

@(private = "file")
gg_action_cost :: proc(state: ^EditorState, g: ^e.GoapNode, i: int) -> f32 {
	if gg_remote_ok(state, g) && i < len(ggRemote.costs) do return ggRemote.costs[i]
	if state.isSimulating do return g.actions[i].lastCost
	return g.actions[i].baseCost
}

@(private = "file")
gg_goal_cost :: proc(state: ^EditorState, g: ^e.GoapNode, i: int) -> f32 {
	if gg_remote_ok(state, g) && i < len(ggRemote.goalCosts) do return ggRemote.goalCosts[i]
	if state.isSimulating do return e.Goap_GoalCost(g, i)
	return g.goals[i].baseCost
}

@(private = "file")
gg_enabled :: proc(state: ^EditorState, g: ^e.GoapNode, i: int) -> bool {
	if gg_remote_ok(state, g) && i < len(ggRemote.enabled) do return ggRemote.enabled[i]
	if state.isSimulating do return e.Goap_ActionEnabled(g, i)
	return true
}

// Goap_RemoteReply: the game's "@rayzr:goap" answer.
Goap_RemoteReply :: proc(text: string) {
	v, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None do return
	o, ok := v.(json.Object)
	if !ok do return
	path, _ := o["path"].(json.String)
	delete(ggRemote.path)
	ggRemote.path = strings.clone(path)
	clear(&ggRemote.plan)
	clear(&ggRemote.costs)
	clear(&ggRemote.enabled)
	clear(&ggRemote.goalCosts)
	clear(&ggRemote.values)
	if _, missing := o["missing"]; missing {
		ggRemote.got = false
		return
	}
	ggRemote.got = true
	num :: proc(v: json.Value) -> f32 {
		#partial switch x in v {
		case json.Integer: return f32(x)
		case json.Float:   return f32(x)
		case json.Boolean: return 1 if x else 0
		}
		return 0
	}
	ggRemote.goal = int(num(o["goal"]))
	ggRemote.action = int(num(o["action"]))
	ggRemote.state = int(num(o["state"]))
	if l, lok := o["plan"].(json.Array); lok do for x in l do append(&ggRemote.plan, int(num(x)))
	if l, lok := o["action_costs"].(json.Array); lok {
		for x in l {
			pair, pok := x.(json.Array)
			if !pok || len(pair) < 2 do continue
			append(&ggRemote.costs, num(pair[0]))
			append(&ggRemote.enabled, num(pair[1]) != 0)
		}
	}
	if l, lok := o["goal_costs"].(json.Array); lok do for x in l do append(&ggRemote.goalCosts, num(x))
	if l, lok := o["keys"].(json.Array); lok {
		for x in l {
			arr, aok := x.(json.Array)
			if !aok do continue
			row: [4]f32
			for k in 0 ..< min(len(arr), 4) do row[k] = num(arr[k])
			append(&ggRemote.values, row)
		}
	}
}

// ----------------------------------------------------------------------------
// Layout: a row per goal, left to right; an action under each condition it
// can meet (not twice on one path; at most 6 deep). Actions no goal reaches
// go in a last row.
// ----------------------------------------------------------------------------

@(private = "file")
gg_box_h :: proc(g: ^e.GoapNode, goal: bool, i: int, live: bool) -> f32 {
	h: f32 = 30
	conds := len(g.goals[i].conditions) if goal else len(g.actions[i].conditions)
	if !goal && g.actions[i].target != "" do h += GOAPG_ROW
	if conds > 0 do h += GOAPG_ROW * f32(conds + 1)
	if !goal && len(g.actions[i].effects) > 0 && !live do h += GOAPG_ROW * f32(len(g.actions[i].effects) + 1)
	return h + 6
}

@(private = "file")
gg_layout :: proc(g: ^e.GoapNode, live: bool) -> [dynamic]GoapG_Box {
	boxes := make([dynamic]GoapG_Box, context.temp_allocator)
	reached := make([]bool, len(g.actions), context.temp_allocator)
	y: f32 = 0
	onPath :: proc(boxes: []GoapG_Box, b: int, action: int) -> bool {
		for p := b; p >= 0; p = boxes[p].parent do if !boxes[p].goal && boxes[p].index == action do return true
		return false
	}
	// place: a box and its children; returns the bottom it used.
	place :: proc(g: ^e.GoapNode, boxes: ^[dynamic]GoapG_Box, reached: []bool, goal: bool, index, parent, cond, depth: int, top: f32, live: bool) -> f32 {
		h := gg_box_h(g, goal, index, live)
		append(boxes, GoapG_Box{goal = goal, index = index, parent = parent, cond = cond, depth = depth, pos = {f32(depth) * (GOAPG_W + GOAPG_GAP.x), top}, h = h})
		me := len(boxes) - 1
		if !goal do reached[index] = true
		bottom := top + h
		if depth >= 6 || len(boxes) > 400 do return bottom
		conds := g.goals[index].conditions[:] if goal else g.actions[index].conditions[:]
		childTop := top
		any := false
		for c, ci in conds {
			for &a, ai in g.actions {
				if onPath(boxes[:], me, ai) do continue
				meets := false
				for ef in a.effects do if e.Goap_Satisfies(ef, c) do meets = true
				if !meets do continue
				b := place(g, boxes, reached, false, ai, me, ci, depth + 1, childTop, live)
				childTop = b + GOAPG_GAP.y
				any = true
			}
		}
		if any do bottom = max(bottom, childTop - GOAPG_GAP.y)
		return bottom
	}
	for _, gi in g.goals {
		y = place(g, &boxes, reached, true, gi, -1, -1, 0, y, live) + GOAPG_GAP.y * 2.5
	}
	// Actions no goal reaches (still editable).
	x: f32 = 0
	for r, ai in reached {
		if r do continue
		append(&boxes, GoapG_Box{goal = false, index = ai, parent = -1, cond = -1, depth = 0, pos = {x, y}, h = gg_box_h(g, false, ai, live)})
		x += GOAPG_W + GOAPG_GAP.y
	}
	return boxes
}

@(private = "file")
gg_to_screen :: proc(origin, w: [2]f32) -> [2]f32 {return origin + gg.pan + w * gg.zoom}

@(private = "file")
gg_in_plan :: proc(state: ^EditorState, g: ^e.GoapNode, boxes: []GoapG_Box, b: int) -> bool {
	box := boxes[b]
	if box.goal do return box.index == gg_cur_goal(state, g) && box.index >= 0
	plan := gg_plan(state, g)
	if box.parent < 0 || box.depth > len(plan) do return false
	if plan[len(plan) - box.depth] != box.index do return false
	return gg_in_plan(state, g, boxes, box.parent)
}

@(private = "file")
gg_canvas :: proc(state: ^EditorState, g: ^e.GoapNode) {
	dl := imgui.GetWindowDrawList()
	origin := imgui.GetCursorScreenPos()
	size := imgui.GetContentRegionAvail()
	io := imgui.GetIO()
	mouse := [2]f32{io.MousePos.x, io.MousePos.y}
	hovered := imgui.IsWindowHovered()
	live := gg_live(state)
	imgui.DrawList_AddRectFilled(dl, origin, origin + size, col_u32(CODE_BG))
	Drive_ItemRect("gg.canvas", origin, origin + size, inWindow = true)
	// Grid.
	step := 32 * gg.zoom
	for x := origin.x + f32(int(gg.pan.x) % int(max(step, 1))); x < origin.x + size.x; x += step do imgui.DrawList_AddLine(dl, {x, origin.y}, {x, origin.y + size.y}, col_u32(ui_line(0.03)))
	for y := origin.y + f32(int(gg.pan.y) % int(max(step, 1))); y < origin.y + size.y; y += step do imgui.DrawList_AddLine(dl, {origin.x, y}, {origin.x + size.x, y}, col_u32(ui_line(0.03)))
	boxes := gg_layout(g, live)
	if len(boxes) != gg.framed do gg.frame = true
	if len(boxes) > 0 && ((gg.frame && size.x > 120 && size.y > 80) || (hovered && imgui.IsKeyPressed(.F) && !io.WantTextInput)) {
		gg.frame = false
		gg.framed = len(boxes)
		mx: [2]f32
		for b in boxes do mx = {max(mx.x, b.pos.x + GOAPG_W), max(mx.y, b.pos.y + b.h)}
		gg.zoom = clamp(min(size.x / (mx.x + 40), size.y / (mx.y + 40)), 0.35, 1.0)
		gg.pan = {16, 16}
	}
	if hovered && (io.MouseWheel != 0 || io.MouseWheelH != 0) {
		if io.KeyCtrl || io.KeySuper {
			before := (mouse - origin - gg.pan) / gg.zoom
			gg.zoom = clamp(gg.zoom * (1 + io.MouseWheel * 0.1), 0.35, 2)
			gg.pan += mouse - gg_to_screen(origin, before)
		} else if io.KeyShift {
			gg.pan.x += io.MouseWheel * 30
		} else {
			gg.pan += {io.MouseWheelH * 30, io.MouseWheel * 30}
		}
	}
	if hovered && (imgui.IsMouseDragging(.Middle) || (imgui.IsMouseDragging(.Left) && imgui.IsKeyDown(.Space))) do gg.pan += {io.MouseDelta.x, io.MouseDelta.y}
	z := gg.zoom
	curAction := gg_cur_action(state, g)

	// Links: from the parent's condition row to the child (cyan on the plan).
	for b, bi in boxes {
		if b.parent < 0 do continue
		p := boxes[b.parent]
		from := gg_to_screen(origin, p.pos + {GOAPG_W, 30 + (GOAPG_ROW if !p.goal && g.actions[p.index].target != "" else 0) + GOAPG_ROW * (f32(b.cond) + 1.5)})
		to := gg_to_screen(origin, b.pos + {0, 15})
		col := GOAPG_LINK if live && gg_in_plan(state, g, boxes[:], bi) else ui_line(0.35)
		imgui.DrawList_AddBezierCubic(dl, from, from + {40 * z, 0}, to - {40 * z, 0}, to, col_u32(col), 2)
	}
	// Boxes.
	hoverBox := -1
	for b, bi in boxes {
		mn := gg_to_screen(origin, b.pos)
		mx := mn + [2]f32{GOAPG_W, b.h} * z
		if hovered && point_in_rect(mouse, mn, mx) do hoverBox = bi
		imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32(UI_BG_RAISED), 5)
		border := ui_line(0.2)
		thick: f32 = 1
		if live {
			if !b.goal && !gg_enabled(state, g, b.index) {border, thick = GOAPG_OFF, 2}
			if gg_in_plan(state, g, boxes[:], bi) {border, thick = GOAPG_PLAN, 2}
			if !b.goal && b.index == curAction && gg_in_plan(state, g, boxes[:], bi) {border, thick = GOAPG_RUNNING, 2}
		}
		if (b.goal && gg.selGoal == b.index) || (!b.goal && gg.selAction == b.index) do border, thick = UI_ACCENT, 2
		imgui.DrawList_AddRect(dl, mn, mx, col_u32(border), 5, {}, thick)
		fs := imgui.GetFontSize() * z
		small := 12 * z
		pad := [2]f32{10, 7} * z
		name := g.goals[b.index].name if b.goal else g.actions[b.index].name
		icon := ICON_FA_BULLSEYE if b.goal else ICON_FA_BOLT
		imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.semibold, fs, mn + pad, col_u32(UI_TEXT), fmt.ctprintf("%s  %s", icon, name))
		cost := gg_goal_cost(state, g, b.index) if b.goal else gg_action_cost(state, g, b.index)
		costText := fmt.ctprintf("Cost: %.2f" if live else "Cost: %g", cost)
		imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, small, {mx.x - 70 * z, mn.y + pad.y + 2 * z}, col_u32(UI_TEXT_DIM), costText)
		y := mn.y + 30 * z
		dot :: proc(dl: ^imgui.DrawList, p: [2]f32, col: imgui.Vec4, z: f32) {imgui.DrawList_AddCircleFilled(dl, p + {5 * z, 8 * z}, 4.5 * z, col_u32(col))}
		if !b.goal {
			a := &g.actions[b.index]
			if a.target != "" {
				col := imgui.Vec4{1, 1, 1, 0.8}
				text := fmt.tprintf("Target: %s", a.target)
				if live {
					known := false
					if gg_remote_ok(state, g) {
						if ki := e.Goap_FindKey(g, a.target); ki >= 0 && ki < len(ggRemote.values) {
							r := ggRemote.values[ki]
							known = r[0] != 0
							if known do text = fmt.tprintf("Target: (%.0f, %.0f)", r[1], r[2])
						}
					} else if t, ok := e.Goap_GetTarget(g, a.target); ok && t.valid {
						known = true
						text = fmt.tprintf("Target: (%.0f, %.0f)", t.pos.x, t.pos.y)
					}
					if !known do text = "Target: null"
					col = GOAPG_MET if known || !a.requiresTarget else GOAPG_UNMET
				}
				dot(dl, {mn.x + pad.x, y}, col, z)
				imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, small, {mn.x + pad.x + 14 * z, y + 2 * z}, col_u32(UI_TEXT), strings.clone_to_cstring(text, context.temp_allocator))
				y += GOAPG_ROW * z
			}
		}
		conds := g.goals[b.index].conditions[:] if b.goal else g.actions[b.index].conditions[:]
		if len(conds) > 0 {
			imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, small, {mn.x + pad.x, y + 2 * z}, col_u32(UI_TEXT_DIM), "Conditions")
			y += GOAPG_ROW * z
			for c in conds {
				text := e.Goap_ConditionText(c)
				col: imgui.Vec4
				if live {
					v, known := gg_value(state, g, c.key)
					ref := 0
					if c.refKey != "" do ref, _ = gg_value(state, g, c.refKey)
					col = GOAPG_MET if known && e.Goap_Met(c, v, ref) else GOAPG_UNMET
					text = fmt.tprintf("%s (%s)", text, fmt.tprintf("%d", v) if known else "-")
				} else {
					col = GOAPG_UNMET
					for &a in g.actions do for ef in a.effects do if e.Goap_Satisfies(ef, c) do col = GOAPG_MET
				}
				dot(dl, {mn.x + pad.x, y}, col, z)
				imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, small, {mn.x + pad.x + 14 * z, y + 2 * z}, col_u32(UI_TEXT), strings.clone_to_cstring(text, context.temp_allocator))
				y += GOAPG_ROW * z
			}
		}
		if !b.goal && !live && len(g.actions[b.index].effects) > 0 {
			imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, small, {mn.x + pad.x, y + 2 * z}, col_u32(UI_TEXT_DIM), "Effects")
			y += GOAPG_ROW * z
			for ef in g.actions[b.index].effects {
				imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, small, {mn.x + pad.x + 14 * z, y + 2 * z}, col_u32(UI_TEXT), fmt.ctprintf("%s%s", ef.key, "++" if ef.increase else "--"))
				y += GOAPG_ROW * z
			}
		}
		Drive_ItemRect(fmt.tprintf("gg.%s:%s", "goal" if b.goal else "action", name), mn, mx, inWindow = true)
	}

	if hovered && (imgui.IsMouseClicked(.Left) || imgui.IsMouseClicked(.Right)) do imgui.SetWindowFocus()
	if hovered && imgui.IsMouseClicked(.Left) && !imgui.IsKeyDown(.Space) {
		gg.selGoal, gg.selAction = -1, -1
		if hoverBox >= 0 {
			if boxes[hoverBox].goal do gg.selGoal = boxes[hoverBox].index
			else do gg.selAction = boxes[hoverBox].index
		}
	}
	if hovered && imgui.IsMouseClicked(.Right) {
		gg.ctxBox = hoverBox
		if hoverBox >= 0 {
			gg.selGoal, gg.selAction = -1, -1
			if boxes[hoverBox].goal do gg.selGoal = boxes[hoverBox].index
			else do gg.selAction = boxes[hoverBox].index
		}
		imgui.OpenPopup("##gg_ctx")
	}
	if imgui.BeginPopup("##gg_ctx") {
		if imgui.MenuItem(fmt.ctprintf("%s  Add Goal", ICON_FA_BULLSEYE)) do gg_add_goal(state, g)
		Drive_Item("gg.ctx.add-goal")
		if imgui.MenuItem(fmt.ctprintf("%s  Add Action", ICON_FA_BOLT)) do gg_add_action(state, g)
		Drive_Item("gg.ctx.add-action")
		if gg.selGoal >= 0 || gg.selAction >= 0 {
			imgui.Separator()
			if imgui.MenuItem(fmt.ctprintf("%s  Delete", ICON_FA_TRASH), "Del") do gg_delete(state, g)
			Drive_Item("gg.ctx.delete")
		}
		imgui.EndPopup()
	}
	if (imgui.IsWindowFocused() || hovered) && !io.WantTextInput && !Code_HasFocus() && (imgui.IsKeyPressed(.Delete) || imgui.IsKeyPressed(.Backspace)) do gg_delete(state, g)
	// Toolbar.
	imgui.SetCursorScreenPos(origin + {8, size.y - 30})
	if UI_Button(fmt.tprintf("%s  Goal", ICON_FA_PLUS), "gg.add-goal") do gg_add_goal(state, g)
	UI_Tooltip("Add a goal")
	imgui.SameLine()
	if UI_Button(fmt.tprintf("%s  Action", ICON_FA_PLUS), "gg.add-action") do gg_add_action(state, g)
	UI_Tooltip("Add an action")
	if len(g.goals) == 0 && len(g.actions) == 0 {
		imgui.SetCursorScreenPos(origin + {16, 12})
		UI_DimText("No goals or actions yet: add a goal (what the agent wants) and actions (what it can do).")
	}
}

@(private = "file")
gg_add_goal :: proc(state: ^EditorState, g: ^e.GoapNode) {
	Editor_RecordUndo(state, "Add GOAP goal")
	gg.selGoal = e.Goap_AddGoal(g, fmt.tprintf("Goal%d", len(g.goals) + 1))
	gg.selAction = -1
}

@(private = "file")
gg_add_action :: proc(state: ^EditorState, g: ^e.GoapNode) {
	Editor_RecordUndo(state, "Add GOAP action")
	gg.selAction = e.Goap_AddAction(g, fmt.tprintf("Action%d", len(g.actions) + 1))
	gg.selGoal = -1
}

@(private = "file")
gg_delete :: proc(state: ^EditorState, g: ^e.GoapNode) {
	if gg.selGoal >= 0 && gg.selGoal < len(g.goals) {
		Editor_RecordUndo(state, "Delete GOAP goal")
		e.GoapNode_Stop(g)
		e.Goap_FreeGoal(g, &g.goals[gg.selGoal])
		ordered_remove(&g.goals, gg.selGoal)
		clear(&g.requested)
		gg.selGoal = -1
	} else if gg.selAction >= 0 && gg.selAction < len(g.actions) {
		Editor_RecordUndo(state, "Delete GOAP action")
		e.GoapNode_Stop(g)
		e.Goap_FreeAction(g, &g.actions[gg.selAction])
		ordered_remove(&g.actions, gg.selAction)
		gg.selAction = -1
	}
}

// ----------------------------------------------------------------------------
// The side panel.
// ----------------------------------------------------------------------------

@(private = "file")
gg_text :: proc(state: ^EditorState, g: ^e.GoapNode, id: string, s: ^string, hint: cstring = "", w: f32 = -1) {
	buf: [256]u8
	copy(buf[:len(buf) - 1], s^)
	imgui.SetNextItemWidth(w)
	if imgui.InputTextWithHint(fmt.ctprintf("##%s", id), hint, cstring(raw_data(buf[:])), len(buf), {}) {
		e.Goap_SetString(g, s, string(cstring(raw_data(buf[:]))))
	}
	undo_on_activate(state, "Edit GOAP")
	Drive_Item(id)
}

// gg_key_combo: one of the agent's keys (targets: target keys only).
@(private = "file")
gg_key_combo :: proc(state: ^EditorState, g: ^e.GoapNode, id: string, s: ^string, targets: bool, allowNone := false, w: f32 = -1) {
	imgui.SetNextItemWidth(w)
	shown := s^ if s^ != "" else "(none)"
	if imgui.BeginCombo(fmt.ctprintf("##%s", id), strings.clone_to_cstring(shown, context.temp_allocator)) {
		if allowNone && imgui.Selectable("(none)", s^ == "") {
			Editor_RecordUndo(state, "Edit GOAP")
			e.Goap_SetString(g, s, "")
		}
		for k in g.keys {
			if k.target != targets do continue
			if imgui.Selectable(strings.clone_to_cstring(k.name, context.temp_allocator), k.name == s^) {
				Editor_RecordUndo(state, "Edit GOAP")
				e.Goap_SetString(g, s, k.name)
			}
			Drive_Item(fmt.tprintf("pick:%s", k.name))
		}
		imgui.EndCombo()
	}
	Drive_Item(id)
}

@(private = "file")
gg_conditions :: proc(state: ^EditorState, g: ^e.GoapNode, id: string, list: ^[dynamic]e.Goap_Condition) {
	remove := -1
	for &c, i in list {
		imgui.PushIDInt(i32(i))
		w := imgui.GetContentRegionAvail().x
		gg_key_combo(state, g, fmt.tprintf("%s.key:%d", id, i), &c.key, false, w = w * 0.4)
		imgui.SameLine(0, 4)
		cmp := i32(c.cmp)
		imgui.SetNextItemWidth(w * 0.17)
		if imgui.Combo("##cmp", &cmp, ">=\x00>\x00<=\x00<\x00") {
			Editor_RecordUndo(state, "Edit GOAP condition")
			c.cmp = e.Goap_Compare(cmp)
		}
		imgui.SameLine(0, 4)
		if c.refKey != "" {
			gg_key_combo(state, g, fmt.tprintf("%s.ref:%d", id, i), &c.refKey, false, allowNone = true, w = w * 0.3)
		} else {
			amt := i32(c.amount)
			imgui.SetNextItemWidth(w * 0.3)
			if imgui.InputInt("##amt", &amt, 0) do c.amount = int(amt)
			undo_on_activate(state, "Edit GOAP condition")
			Drive_Item(fmt.tprintf("%s.amount:%d", id, i))
			if imgui.BeginPopupContextItem("##amtctx") {
				if imgui.MenuItem("Compare With a Key") {
					Editor_RecordUndo(state, "Edit GOAP condition")
					for k in g.keys do if !k.target {e.Goap_SetString(g, &c.refKey, k.name); break}
				}
				imgui.EndPopup()
			}
			UI_Tooltip("A whole number (right-click: compare with another key's value)")
		}
		imgui.SameLine(0, 4)
		if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("%s.remove:%d", id, i), "Remove", size = 22) do remove = i
		imgui.PopID()
	}
	if remove >= 0 {
		Editor_RecordUndo(state, "Remove GOAP condition")
		delete(list[remove].key, g.allocator)
		delete(list[remove].refKey, g.allocator)
		ordered_remove(list, remove)
	}
	if UI_Button(fmt.tprintf("%s  Condition", ICON_FA_PLUS), fmt.tprintf("%s.add", id)) {
		Editor_RecordUndo(state, "Add GOAP condition")
		key := ""
		for k in g.keys do if !k.target {key = k.name; break}
		e.Goap_AddCondition(g, list, key, .Greater_Equal, 1)
	}
}

@(private = "file")
gg_scan_scripts :: proc(state: ^EditorState) {
	if gg.scanned != {} && time.duration_seconds(time.tick_since(gg.scanned)) < 3 do return
	gg.scanned = time.tick_now()
	for s in gg.scripts {
		delete(s[0])
		delete(s[1])
	}
	clear(&gg.scripts)
	for rel in Editor_ListProjectFiles(state, "", {".lua"}) {
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		data, err := os.read_entire_file(full, context.temp_allocator)
		if err != nil do continue
		if kind := Goap_ScriptMarker(string(data)); kind != "" do append(&gg.scripts, [2]string{strings.clone(rel), strings.clone(kind)})
	}
}

// Goap_ScriptMarker: "action" / "sensor" / "goal" when Lua text marks its
// table a GOAP script (`X.goap = "action"`), else "".
Goap_ScriptMarker :: proc(text: string) -> string {
	text := text
	for line in strings.split_lines_iterator(&text) {
		l := strings.trim_space(line)
		i := strings.index(l, ".goap")
		if i <= 0 do continue
		rest := strings.trim_left_space(l[i + len(".goap"):])
		if !strings.has_prefix(rest, "=") do continue
		rest = strings.trim_space(rest[1:])
		for k in ([]string{"action", "sensor", "goal"}) {
			if strings.has_prefix(rest, fmt.tprintf("\"%s\"", k)) || strings.has_prefix(rest, fmt.tprintf("'%s'", k)) do return k
		}
	}
	return ""
}

@(private = "file")
gg_script_field :: proc(state: ^EditorState, g: ^e.GoapNode, id: string, s: ^string, kind: string) {
	gg_scan_scripts(state)
	files := make([dynamic]string, context.temp_allocator)
	for x in gg.scripts do if x[1] == kind do append(&files, x[0])
	imgui.SetNextItemWidth(-1)
	if path, ok := asset_picker(id, s^, files[:]); ok {
		Editor_RecordUndo(state, "Edit GOAP")
		e.Goap_SetString(g, s, path)
	}
}

// ggProps: the action / sensor whose Lua values the props editor sets.
@(private = "file")
ggProps: ^map[string]e.ScriptValue

@(private = "file")
ggPropsNode: ^e.GoapNode

@(private = "file")
gg_script_props :: proc(state: ^EditorState, g: ^e.GoapNode, script: string, props: ^map[string]e.ScriptValue, prefix: string) {
	if script == "" do return
	mod, ok := e.ScriptManager_LoadModule(script, &state.game.scriptManager)
	if !ok || mod == nil do return
	ggProps, ggPropsNode = props, g
	target := Script_PropsTarget{
		mod = mod, modulePath = script, values = props, owner = nil, idPrefix = prefix, data = state,
		set = proc(state: ^EditorState, pt: ^Script_PropsTarget, name: string, val: e.ScriptValue) {
			g, props := ggPropsNode, ggProps
			if !e.Node_IsAlive(g) || props == nil do return
			if props^ == nil do props^ = make(map[string]e.ScriptValue, g.allocator)
			v := val
			if v.valString != "" do v.valString = strings.clone(v.valString, g.allocator)
			for k, old in props^ do if k == name {
				if old.valString != "" do delete(old.valString, g.allocator)
				props^[k] = v
				return
			}
			props^[strings.clone(name, g.allocator)] = v
		},
		record_undo = proc(state: ^EditorState, pt: ^Script_PropsTarget, label: string) {Editor_RecordUndo(state, label)},
	}
	script_props_editor(state, &target)
}

@(private = "file")
gg_side_panel :: proc(state: ^EditorState, g: ^e.GoapNode) {
	if gg.selGoal < 0 && gg.selAction < 0 {
		gg_agent_summary(state, g)
		return
	}
	if gg.selGoal >= 0 {
		goal := &g.goals[gg.selGoal]
		imgui.PushFont(GlobalFonts.semibold)
		imgui.TextUnformatted(fmt.ctprintf("%s  Goal", ICON_FA_BULLSEYE))
		imgui.PopFont()
		UI_DimTextWrapped("What the agent wants: its conditions met. Of the goals requested, the one reached cheapest (its cost plus the actions') wins.")
		if !UI_BeginProps("##gg_goal") do return
		UI_PropLabel("Name")
		gg_text(state, g, "gg.name", &goal.name)
		UI_PropLabel("Cost")
		imgui.SetNextItemWidth(-1)
		imgui.DragFloat("##gg.cost", &goal.baseCost, 0.1, 0, 100000, "%.2f")
		undo_on_activate(state, "Edit GOAP goal")
		UI_Tooltip("Its priority: cheaper wins (a Lua goal's get_cost replaces it)")
		UI_PropLabel("Script")
		gg_script_field(state, g, "gg.goal-script", &goal.script, "goal")
		UI_EndProps()
		UI_DimText("Conditions")
		gg_conditions(state, g, "gg.goal-cond", &goal.conditions)
		return
	}
	a := &g.actions[gg.selAction]
	imgui.PushFont(GlobalFonts.semibold)
	imgui.TextUnformatted(fmt.ctprintf("%s  Action", ICON_FA_BOLT))
	imgui.PopFont()
	if !UI_BeginProps("##gg_action") do return
	UI_PropLabel("Name")
	gg_text(state, g, "gg.name", &a.name)
	UI_PropLabel("Does")
	kind := i32(a.kind)
	imgui.SetNextItemWidth(-1)
	if imgui.Combo("##gg.kind", &kind, "Script\x00Behavior Tree\x00Wait\x00Call Method\x00Play Animation\x00") {
		Editor_RecordUndo(state, "Edit GOAP action")
		a.kind = e.Goap_Action_Kind(kind)
	}
	Drive_Item("gg.kind")
	UI_Tooltip("Script: a Lua action (`X.goap = \"action\"`). Behavior Tree: runs one (Manual) until it answers. Wait: Seconds. Call Method: a method of the actor's script (its answer: \"continue\", \"completed\", \"stop\", true / false). Play Animation: until it ends")
	switch a.kind {
	case .Script:
		UI_PropLabel("Script")
		gg_script_field(state, g, "gg.action-script", &a.script, "action")
	case .Behavior_Tree:
		UI_PropLabel("Tree")
		if path, changed := node_ref_field(state, g, "gg.tree", a.node); changed {
			Editor_RecordUndo(state, "Edit GOAP action")
			e.Goap_SetString(g, &a.node, path)
		}
	case .Wait:
		UI_PropLabel("Seconds")
		imgui.SetNextItemWidth(-1)
		imgui.DragFloat("##gg.secs", &a.seconds, 0.05, 0, 3600, "%.2f")
		undo_on_activate(state, "Edit GOAP action")
	case .Call_Method:
		UI_PropLabel("Method")
		gg_text(state, g, "gg.method", &a.method, "on the actor's script")
	case .Play_Animation:
		UI_PropLabel("Player")
		if path, changed := node_ref_field(state, g, "gg.player", a.node); changed {
			Editor_RecordUndo(state, "Edit GOAP action")
			e.Goap_SetString(g, &a.node, path)
		}
		UI_PropLabel("Animation")
		gg_text(state, g, "gg.anim", &a.method)
	}
	UI_PropLabel("Cost")
	imgui.SetNextItemWidth(-1)
	imgui.DragFloat("##gg.acost", &a.baseCost, 0.1, 0, 100000, "%.2f")
	undo_on_activate(state, "Edit GOAP action")
	UI_PropLabel("Target")
	gg_key_combo(state, g, "gg.target", &a.target, true, allowNone = true)
	UI_Tooltip("A target key it goes to first (Navigation Agent, else straight at Move Speed)")
	if a.target != "" {
		UI_PropLabel("In Range")
		imgui.SetNextItemWidth(-1)
		imgui.DragFloat("##gg.stop", &a.stoppingDistance, 0.5, 0, 10000, "%.0f px")
		undo_on_activate(state, "Edit GOAP action")
		UI_PropLabel("Requires Target")
		if imgui.Checkbox("##gg.req", &a.requiresTarget) do Editor_RecordUndo(state, "Edit GOAP action")
		UI_PropLabel("Move Mode")
		mm := i32(a.moveMode)
		imgui.SetNextItemWidth(-1)
		if imgui.Combo("##gg.move", &mm, "Move Before Performing\x00Perform While Moving\x00") {
			Editor_RecordUndo(state, "Edit GOAP action")
			a.moveMode = e.Goap_Move_Mode(mm)
		}
	}
	UI_PropLabel("Check Conditions")
	if imgui.Checkbox("##gg.validate", &a.validateConditions) do Editor_RecordUndo(state, "Edit GOAP action")
	UI_Tooltip("Stop while running when its conditions stop being met")
	if a.kind == .Script do gg_script_props(state, g, a.script, &a.props, "gg.prop")
	UI_EndProps()
	UI_DimText("Conditions")
	gg_conditions(state, g, "gg.action-cond", &a.conditions)
	imgui.Dummy({0, 4})
	UI_DimText("Effects")
	remove := -1
	for &ef, i in a.effects {
		imgui.PushIDInt(i32(i))
		w := imgui.GetContentRegionAvail().x
		gg_key_combo(state, g, fmt.tprintf("gg.effect.key:%d", i), &ef.key, false, w = w * 0.5)
		imgui.SameLine(0, 4)
		dir := i32(0 if ef.increase else 1)
		imgui.SetNextItemWidth(w * 0.35)
		if imgui.Combo("##dir", &dir, "Increase\x00Decrease\x00") {
			Editor_RecordUndo(state, "Edit GOAP effect")
			ef.increase = dir == 0
		}
		imgui.SameLine(0, 4)
		if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("gg.effect.remove:%d", i), "Remove", size = 22) do remove = i
		imgui.PopID()
	}
	if remove >= 0 {
		Editor_RecordUndo(state, "Remove GOAP effect")
		delete(a.effects[remove].key, g.allocator)
		ordered_remove(&a.effects, remove)
	}
	if UI_Button(fmt.tprintf("%s  Effect", ICON_FA_PLUS), "gg.effect.add") {
		Editor_RecordUndo(state, "Add GOAP effect")
		key := ""
		for k in g.keys do if !k.target {key = k.name; break}
		e.Goap_AddEffect(g, a, key, true)
	}
	UI_Tooltip("What it moves: the planner links it to conditions on the key (> / >= want Increase, < / <= Decrease). On a key no sensor fills, completing it adds or takes 1")
}

@(private = "file")
gg_agent_summary :: proc(state: ^EditorState, g: ^e.GoapNode) {
	UI_DimTextWrapped("Click a goal or an action to edit it; right-click the canvas to add one. F frames the graph.")
	if !gg_live(state) do return
	imgui.Dummy({0, 6})
	if !UI_BeginProps("##gg_agent") do return
	defer UI_EndProps()
	goal, action := gg_cur_goal(state, g), gg_cur_action(state, g)
	UI_PropLabel("Goal")
	UI_DimText(g.goals[goal].name if goal >= 0 && goal < len(g.goals) else "(none)")
	Drive_Item("gg.live.goal")
	UI_PropLabel("Action")
	UI_DimText(g.actions[action].name if action >= 0 && action < len(g.actions) else "(none)")
	Drive_Item("gg.live.action")
	st := e.Goap_Agent_State(ggRemote.state) if gg_remote_on(state) else g.state
	UI_PropLabel("State")
	UI_DimText(e.GOAP_STATE_TEXT[st])
	UI_PropLabel("Plan")
	sb := strings.builder_make(context.temp_allocator)
	for a, i in gg_plan(state, g) {
		if i > 0 do strings.write_string(&sb, " → ")
		if a >= 0 && a < len(g.actions) do strings.write_string(&sb, g.actions[a].name)
	}
	UI_DimTextWrapped(strings.to_string(sb) if len(sb.buf) > 0 else "(none)")
}

// ----------------------------------------------------------------------------
// Keys & Sensors.
// ----------------------------------------------------------------------------

@(private = "file")
gg_keys_page :: proc(state: ^EditorState, g: ^e.GoapNode) {
	UI_DimTextWrapped("World keys are whole numbers (conditions and effects use them); target keys are positions actions go to. Global keys are shared by every GOAP agent. Sensors keep keys fresh; a script can set them too (goap_set_key / goap_set_target).")
	live := gg_live(state)
	remove := -1
	if imgui.BeginTable("##gg_keys", 6, imgui.TableFlags_SizingStretchProp | imgui.TableFlags_RowBg) {
		imgui.TableSetupColumn("Key", {}, 0.32)
		imgui.TableSetupColumn("Kind", {}, 0.18)
		imgui.TableSetupColumn("Global", {}, 0.1)
		imgui.TableSetupColumn("Start", {}, 0.14)
		imgui.TableSetupColumn("Live", {}, 0.2)
		imgui.TableSetupColumn("", {}, 0.06)
		imgui.TableHeadersRow()
		for &k, i in g.keys {
			imgui.PushIDInt(i32(i))
			imgui.TableNextRow()
			imgui.TableNextColumn()
			gg_text(state, g, fmt.tprintf("gg.key.name:%d", i), &k.name)
			imgui.TableNextColumn()
			kind := i32(1 if k.target else 0)
			imgui.SetNextItemWidth(-1)
			if imgui.Combo("##kind", &kind, "World\x00Target\x00") {
				Editor_RecordUndo(state, "Edit GOAP key")
				k.target = kind == 1
			}
			imgui.TableNextColumn()
			if imgui.Checkbox("##global", &k.global) do Editor_RecordUndo(state, "Edit GOAP key")
			imgui.TableNextColumn()
			if !k.target {
				v := i32(k.initial)
				imgui.SetNextItemWidth(-1)
				if imgui.InputInt("##start", &v, 0) do k.initial = int(v)
				undo_on_activate(state, "Edit GOAP key")
			}
			imgui.TableNextColumn()
			if live {
				if gg_remote_ok(state, g) && i < len(ggRemote.values) {
					r := ggRemote.values[i]
					if k.target do UI_DimText(fmt.tprintf("(%.0f, %.0f)", r[1], r[2]) if r[0] != 0 else "null")
					else do UI_DimText(fmt.tprintf("%d  · %.1fs", int(r[0]), r[1]))
				} else if state.isSimulating {
					if k.target {
						t, ok := e.Goap_GetTarget(g, k.name)
						UI_DimText(fmt.tprintf("(%.0f, %.0f)", t.pos.x, t.pos.y) if ok && t.valid else "null")
					} else {
						v, _ := e.Goap_GetValue(g, k.name)
						age := e.Goap_SensedAge(g, k.name)
						UI_DimText(fmt.tprintf("%d  · %.1fs", v, age) if age >= 0 else fmt.tprintf("%d", v))
					}
				}
				Drive_Item(fmt.tprintf("gg.key.live:%s", k.name))
			}
			imgui.TableNextColumn()
			if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("gg.key.remove:%d", i), "Remove", size = 22) do remove = i
			imgui.PopID()
		}
		imgui.EndTable()
	}
	if remove >= 0 {
		Editor_RecordUndo(state, "Remove GOAP key")
		delete(g.keys[remove].name, g.allocator)
		ordered_remove(&g.keys, remove)
	}
	if UI_Button(fmt.tprintf("%s  World Key", ICON_FA_PLUS), "gg.key.add") {
		Editor_RecordUndo(state, "Add GOAP key")
		e.Goap_AddKey(g, fmt.tprintf("Key%d", len(g.keys) + 1))
	}
	imgui.SameLine()
	if UI_Button(fmt.tprintf("%s  Target Key", ICON_FA_PLUS), "gg.key.add-target") {
		Editor_RecordUndo(state, "Add GOAP key")
		e.Goap_AddKey(g, fmt.tprintf("Target%d", len(g.keys) + 1), target = true)
	}
	imgui.Dummy({0, 10})
	UI_DimText("Sensors")
	sremove := -1
	for &s, i in g.sensors {
		imgui.PushIDInt(i32(i))
		imgui.Separator()
		ki := e.Goap_FindKey(g, s.key)
		isTarget := ki >= 0 && g.keys[ki].target
		if UI_BeginProps("##gg_sensor") {
			UI_PropLabel("Fills")
			imgui.SetNextItemWidth(-1)
			shown := s.key if s.key != "" else "(a key)"
			if imgui.BeginCombo("##skey", strings.clone_to_cstring(shown, context.temp_allocator)) {
				for k in g.keys {
					if imgui.Selectable(fmt.ctprintf("%s  (%s)", k.name, "target" if k.target else "world"), k.name == s.key) {
						Editor_RecordUndo(state, "Edit GOAP sensor")
						e.Goap_SetString(g, &s.key, k.name)
					}
					Drive_Item(fmt.tprintf("pick:%s", k.name))
				}
				imgui.EndCombo()
			}
			Drive_Item(fmt.tprintf("gg.sensor.key:%d", i))
			UI_PropLabel("From")
			kind := i32(s.kind)
			imgui.SetNextItemWidth(-1)
			if imgui.Combo("##skind", &kind, "Script\x00Method\x00Property\x00Nearest With Tag\x00Node\x00") {
				Editor_RecordUndo(state, "Edit GOAP sensor")
				s.kind = e.Goap_Sensor_Kind(kind)
			}
			Drive_Item(fmt.tprintf("gg.sensor.kind:%d", i))
			UI_Tooltip("Script: a Lua sensor (`X.goap = \"sensor\"`, sense(actor)). Method: a method of the actor's script. Property: a node's number property (a target: its position). Nearest With Tag: the nearest node with the tag (a world key: how many). Node: a node (a world key: 1 while it exists)")
			switch s.kind {
			case .Script:
				UI_PropLabel("Script")
				gg_script_field(state, g, fmt.tprintf("gg.sensor.script:%d", i), &s.script, "sensor")
			case .Method:
				UI_PropLabel("Method")
				gg_text(state, g, fmt.tprintf("gg.sensor.method:%d", i), &s.text, "returns the value")
			case .Property:
				UI_PropLabel("Node")
				if path, changed := node_ref_field(state, g, fmt.tprintf("gg.sensor.node:%d", i), s.node); changed {
					Editor_RecordUndo(state, "Edit GOAP sensor")
					e.Goap_SetString(g, &s.node, path)
				}
				if !isTarget {
					UI_PropLabel("Property")
					gg_text(state, g, fmt.tprintf("gg.sensor.prop:%d", i), &s.text, "e.g. position.x")
				}
			case .Nearest_Tag:
				UI_PropLabel("Tag")
				gg_text(state, g, fmt.tprintf("gg.sensor.tag:%d", i), &s.text)
			case .Node:
				UI_PropLabel("Node")
				if path, changed := node_ref_field(state, g, fmt.tprintf("gg.sensor.node:%d", i), s.node); changed {
					Editor_RecordUndo(state, "Edit GOAP sensor")
					e.Goap_SetString(g, &s.node, path)
				}
			}
			UI_PropLabel("When")
			tm := i32(s.timer)
			imgui.SetNextItemWidth(-1)
			if imgui.Combo("##stimer", &tm, "Every Frame\x00Once\x00Every Interval\x00") {
				Editor_RecordUndo(state, "Edit GOAP sensor")
				s.timer = e.Goap_Timer(tm)
			}
			if s.timer == .Interval {
				UI_PropLabel("Interval")
				imgui.SetNextItemWidth(-1)
				imgui.DragFloat("##sint", &s.interval, 0.05, 0, 3600, "%.2f s")
				undo_on_activate(state, "Edit GOAP sensor")
			}
			if s.kind == .Script do gg_script_props(state, g, s.script, &s.props, fmt.tprintf("gg.sensor.prop%d", i))
			UI_EndProps()
		}
		if UI_Button(fmt.tprintf("%s  Remove Sensor", ICON_FA_TRASH), fmt.tprintf("gg.sensor.remove:%d", i)) do sremove = i
		imgui.PopID()
	}
	if sremove >= 0 {
		Editor_RecordUndo(state, "Remove GOAP sensor")
		e.Goap_FreeSensor(g, &g.sensors[sremove])
		ordered_remove(&g.sensors, sremove)
	}
	if UI_Button(fmt.tprintf("%s  Sensor", ICON_FA_PLUS), "gg.sensor.add") {
		Editor_RecordUndo(state, "Add GOAP sensor")
		key := g.keys[0].name if len(g.keys) > 0 else ""
		e.Goap_AddSensor(g, key, .Node)
	}
}

inspector_goap :: proc(state: ^EditorState, g: ^e.GoapNode) {
	if !UI_SectionHeader("Agent") do return
	if UI_BeginProps("##goapinsp") {
		UI_PropLabel("Defines")
		UI_DimText(fmt.tprintf("%d goals · %d actions · %d keys · %d sensors", len(g.goals), len(g.actions), len(g.keys), len(g.sensors)))
		Drive_Item("insp.goap.count")
		if state.isSimulating {
			UI_PropLabel("Goal")
			UI_DimText(g.goals[g.goal].name if g.goal >= 0 && g.goal < len(g.goals) else "(none)")
			UI_PropLabel("Action")
			UI_DimText(g.actions[g.action].name if g.action >= 0 && g.action < len(g.actions) else "(none)")
		}
		UI_EndProps()
	}
	if UI_Button(fmt.tprintf("%s  Edit in GOAP Tab", ICON_FA_BULLSEYE), "insp.goap.edit", {-1, 0}) do bottomTabRequest = .Goap
	UI_Tooltip("Goals, actions, keys and sensors are edited in the GOAP tab of the bottom panel")
}

// Goap_Query: drive queries - goap-graph: the selected agent's goals and
// actions; goap-live: "goal / action / plan".
Goap_Query :: proc(state: ^EditorState, q: string) -> (string, bool) {
	sel := state.selectedNode
	if sel == nil || sel.typeId != e.GoapNode do return "", true
	g := cast(^e.GoapNode)sel
	sb := strings.builder_make(context.temp_allocator)
	switch q {
	case "goap-graph":
		for goal, i in g.goals {
			if i > 0 do strings.write_string(&sb, ",")
			strings.write_string(&sb, goal.name)
		}
		strings.write_string(&sb, "|")
		for a, i in g.actions {
			if i > 0 do strings.write_string(&sb, ",")
			strings.write_string(&sb, a.name)
		}
	case "goap-live":
		goal, action := gg_cur_goal(state, g), gg_cur_action(state, g)
		strings.write_string(&sb, g.goals[goal].name if goal >= 0 && goal < len(g.goals) else "-")
		strings.write_string(&sb, " / ")
		strings.write_string(&sb, g.actions[action].name if action >= 0 && action < len(g.actions) else "-")
	}
	return strings.to_string(sb), true
}

GoapTab_Shutdown :: proc() {
	for s in gg.scripts {
		delete(s[0])
		delete(s[1])
	}
	delete(gg.scripts)
	delete(ggRemote.path)
	delete(ggRemote.plan)
	delete(ggRemote.costs)
	delete(ggRemote.enabled)
	delete(ggRemote.goalCosts)
	delete(ggRemote.values)
}
