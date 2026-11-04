package editor

import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"
import "core:time"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Multi-selection, node clipboard, nudging, alignment and rename.
//
// `state.selection` holds every selected node; `state.selectedNode` is the
// primary one (shown in the Inspector, gizmo anchor). Code that sets
// selectedNode directly still works: Editor_SyncSelection makes the
// selection follow it each frame. Additive selection: Cmd/Ctrl/Shift-click
// in the tree or viewport, or drag a box in the viewport (Select tool).
// ============================================================================

// Editor_SyncSelection drops destroyed nodes and keeps the primary
// selection inside `selection`.
Editor_SyncSelection :: proc(state: ^EditorState) {
	// (A large selection checks against a set of the scene's nodes: a scan
	// of the scene per selected node was 25M compares a frame with 5000
	// selected - #331.)
	inScene: map[^e.Node]struct{}
	if len(state.selection) > SELECTION_SET_MIN && state.activeScene != nil && state.activeScene.manager != nil {
		inScene = make(map[^e.Node]struct{}, len(state.activeScene.manager.nodes), context.temp_allocator)
		for n in state.activeScene.manager.nodes do if n != nil do inScene[n] = {}
	}
	removed := false
	for i := len(state.selection) - 1; i >= 0; i -= 1 {
		n := state.selection[i]
		there := (n in inScene) if inScene != nil else (state.activeScene != nil && node_in_scene(state, n))
		if !e.Node_IsAlive(n) || !there {
			ordered_remove(&state.selection, i)
			removed = true
		}
	}
	if removed do selection_set_invalidate()
	if state.selectedNode != nil && (!e.Node_IsAlive(state.selectedNode) || !node_in_scene(state, state.selectedNode)) {
		state.selectedNode = nil
	}
	if state.selectedNode == nil {
		clear(&state.selection)
		return
	}
	if !slice.contains(state.selection[:], state.selectedNode) {
		clear(&state.selection)
		append(&state.selection, state.selectedNode)
	}
}

node_in_scene :: proc(state: ^EditorState, n: ^e.Node) -> bool {
	if state.activeScene == nil || state.activeScene.manager == nil do return false
	return slice.contains(state.activeScene.manager.nodes[:], n)
}

Editor_IsSelected :: proc(state: ^EditorState, n: ^e.Node) -> bool {
	if n == nil do return false
	if len(state.selection) <= SELECTION_SET_MIN do return slice.contains(state.selection[:], n)
	return n in selection_set(state.selection[:])
}

// A set over a large selection (#331): Editor_IsSelected is asked per node
// per frame (the viewport's bounds, the scene tree's rows, the selection's
// roots) - a scan of the selection each time made 5000 selected nodes a
// 25M-compare frame. The set is rebuilt when the selection looks different
// (its length, storage, ends and a sample of its entries) and every frame.
SELECTION_SET_MIN :: 32

@(private = "file")
selectionSet: struct {
	set:   map[^e.Node]struct{},
	frame: u64,
	n:     int,
	data:  rawptr,
	sig:   uintptr,
}

// Editor_SelectionSignature: a cheap fingerprint of a selection (its length,
// ends and ~16 entries): caches compare it.
Editor_SelectionSignature :: proc(sel: []^e.Node) -> uintptr {
	h := uintptr(len(sel))
	if len(sel) == 0 do return h
	step := max(len(sel) / 16, 1)
	for i := 0; i < len(sel); i += step do h = (h ~ uintptr(rawptr(sel[i]))) * 0x100000001b3
	return h ~ uintptr(rawptr(sel[len(sel) - 1]))
}

@(private = "file")
selection_set :: proc(sel: []^e.Node) -> ^map[^e.Node]struct{} {
	ss := &selectionSet
	frame := FrameTiming_FrameIndex()
	sig := Editor_SelectionSignature(sel)
	if ss.set != nil && ss.frame == frame && ss.n == len(sel) && ss.data == raw_data(sel) && ss.sig == sig do return &ss.set
	if ss.set == nil do ss.set = make(map[^e.Node]struct{})
	clear(&ss.set)
	reserve(&ss.set, len(sel))
	for n in sel do ss.set[n] = {}
	ss.frame, ss.n, ss.data, ss.sig = frame, len(sel), raw_data(sel), sig
	return &ss.set
}

@(private = "file")
selection_set_invalidate :: proc() {
	selectionSet.n = -1
}

// Editor_SelectionSetRelease frees the set (the editor's shutdown).
Editor_SelectionSetRelease :: proc() {
	delete(selectionSet.set)
	selectionSet = {}
}

Editor_HasMultiSelection :: proc(state: ^EditorState) -> bool {
	return len(state.selection) >= 2
}

// Editor_SelectNode selects `n`; `additive` toggles it in the selection.
Editor_SelectNode :: proc(state: ^EditorState, n: ^e.Node, additive := false) {
	state.inspectResource = false // the Inspector goes back to nodes
	if !additive || n == nil {
		clear(&state.selection)
		if n != nil do append(&state.selection, n)
		state.selectedNode = n
		return
	}
	if i, found := slice.linear_search(state.selection[:], n); found {
		ordered_remove(&state.selection, i)
		state.selectedNode = state.selection[len(state.selection) - 1] if len(state.selection) > 0 else nil
	} else {
		append(&state.selection, n)
		state.selectedNode = n
	}
}

// Selection_Paths: the active scene's selection as child-index paths
// (temp allocated) - it survives rebuilding nodes, which pointers don't.
Selection_Paths :: struct {
	primary: string,
	all:     [dynamic]string,
}

Editor_SaveSelection :: proc(state: ^EditorState) -> Selection_Paths {
	sp := Selection_Paths{primary = Editor_NodePath(state, state.selectedNode), all = make([dynamic]string, context.temp_allocator)}
	for n in state.selection do append(&sp.all, Editor_NodePath(state, n))
	return sp
}

// Editor_RestoreSelection selects the nodes now at the saved paths (after
// instances were rebuilt: Apply / Revert / Save as Component, #74).
Editor_RestoreSelection :: proc(state: ^EditorState, sp: Selection_Paths) {
	clear(&state.selection)
	for p in sp.all do if n := Editor_NodeAtPath(state, p); n != nil do append(&state.selection, n)
	state.selectedNode = Editor_NodeAtPath(state, sp.primary) if sp.primary != "" else nil
	if state.selectedNode != nil && len(state.selection) == 0 do append(&state.selection, state.selectedNode)
}

Editor_ClearSelection :: proc(state: ^EditorState) {
	clear(&state.selection)
	state.selectedNode = nil
}

Editor_SelectAllNodes :: proc(state: ^EditorState) {
	if state.activeScene == nil do return
	clear(&state.selection)
	for n in state.activeScene.manager.nodes {
		if n == nil || n == state.activeScene.rootNode || n.transient || Editor_NodeLocked(state, n) do continue
		append(&state.selection, n)
	}
	state.selectedNode = state.selection[len(state.selection) - 1] if len(state.selection) > 0 else nil
}

// Editor_SelectionRoots: selected nodes without a selected ancestor (what
// delete/copy/duplicate/move operate on), in tree order.
Editor_SelectionRoots :: proc(state: ^EditorState, allocator := context.temp_allocator) -> []^e.Node {
	out := make([dynamic]^e.Node, allocator)
	if state.activeScene == nil do return out[:]
	mgr := state.activeScene.manager
	for n in mgr.nodes {
		if !Editor_IsSelected(state, n) || n == state.activeScene.rootNode do continue
		covered := false
		for p := e.GetParent(mgr, n); p != nil; p = e.GetParent(mgr, p) {
			if Editor_IsSelected(state, p) {covered = true; break}
		}
		if !covered do append(&out, n)
	}
	return out[:]
}

// --- delete / duplicate ------------------------------------------------------------

// Editor_DeleteSelection deletes every selected node (one undo step).
Editor_DeleteSelection :: proc(state: ^EditorState) -> int {
	roots := Editor_SelectionRoots(state)
	targets := make([dynamic]^e.Node, context.temp_allocator)
	for n in roots do append(&targets, n)
	if len(targets) == 0 do return 0
	label := fmt.tprintf("Delete %s", targets[0].name) if len(targets) == 1 else fmt.tprintf("Delete %d nodes", len(targets))
	Editor_RecordUndo(state, label)
	for n in targets do e.RemoveNode(state.activeScene.manager, n)
	e.ProcessNodeQueues(state.activeScene.manager, &state.game.gameContext)
	Editor_ClearSelection(state)
	return len(targets)
}

// Editor_DuplicateSelection duplicates every selected node and selects the copies.
Editor_DuplicateSelection :: proc(state: ^EditorState) -> int {
	roots := Editor_SelectionRoots(state)
	if len(roots) <= 1 {
		if state.selectedNode != nil && Editor_DuplicateNode(state, state.selectedNode) != nil do return 1
		return 0
	}
	Editor_RecordUndo(state, fmt.tprintf("Duplicate %d nodes", len(roots)))
	json := Editor_SerializeNodes(state, roots)
	copies := Editor_InstantiateNodes(state, json, -1, {state.gridSize if state.gridSize > 0 else 16, state.gridSize if state.gridSize > 0 else 16})
	return copies
}

// --- clipboard ---------------------------------------------------------------------

NODE_CLIPBOARD_PREFIX :: "rayzr-nodes:"

@(private = "file")
nodeClipboard: string

Editor_HasClipboardNodes :: proc() -> bool {
	return nodeClipboard != ""
}

// Editor_SerializeNodes: a JSON array of node subtrees.
Editor_SerializeNodes :: proc(state: ^EditorState, nodes: []^e.Node) -> string {
	sb := strings.builder_make(context.temp_allocator)
	strings.write_byte(&sb, '[')
	for n, i in nodes {
		if i > 0 do strings.write_byte(&sb, ',')
		strings.write_string(&sb, e.Node_SerializeToJSON(n, state.activeScene.manager, context.temp_allocator))
	}
	strings.write_byte(&sb, ']')
	return strings.to_string(sb)
}

// Editor_InstantiateNodes adds the nodes of a JSON array (from
// Editor_SerializeNodes) next to their originals' parent — the primary
// selection's parent, or root — offset by `offset`; selects them.
Editor_InstantiateNodes :: proc(state: ^EditorState, json: string, _: int, offset: [2]f32, worlds: [][2]f32 = nil) -> int {
	if state.activeScene == nil do return 0
	mgr := state.activeScene.manager
	parent := state.activeScene.rootNode
	if state.selectedNode != nil && state.selectedNode != state.activeScene.rootNode {
		if p := e.GetParent(mgr, state.selectedNode); p != nil do parent = p
	}
	if root := e.Node_ComponentRoot(mgr, parent); root != nil do parent = e.GetParent(mgr, root)
	items := split_json_array(json)
	Editor_ClearSelection(state)
	for item, i in items {
		n := e.Scene_InstantiateNodeFromJSON(state.activeScene, transmute([]u8)item, parent, &state.game.gameContext)
		if n == nil do continue
		n.name = strings.clone(Editor_UniqueChildName(state, parent, n.name, n), n.allocator)
		n.position += offset
		// From another scene: at the same world position.
		if i < len(worlds) do n.position = Editor_WorldToLocal(parent, worlds[i])
		append(&state.selection, n)
		state.selectedNode = n
	}
	e.ProcessNodeQueues(mgr, &state.game.gameContext)
	for n in state.selection do e.Node_ForgetCopiedUids(mgr, n) // (copies are new nodes: #77)
	e.Node_SetGlobalPositions(mgr, state.activeScene.rootNode)
	return len(state.selection)
}

// split_json_array splits a top-level JSON array into its element texts.
split_json_array :: proc(json: string) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	s := strings.trim_space(json)
	if len(s) < 2 || s[0] != '[' do return out[:]
	depth := 0
	inStr := false
	start := -1
	for i := 1; i < len(s) - 1; i += 1 {
		c := s[i]
		if inStr {
			if c == '\\' do i += 1
			else if c == '"' do inStr = false
			continue
		}
		switch c {
		case '"': inStr = true
		case '{', '[':
			if depth == 0 do start = i
			depth += 1
		case '}', ']':
			depth -= 1
			if depth == 0 && start >= 0 {
				append(&out, s[start:i + 1])
				start = -1
			}
		}
	}
	return out[:]
}

Editor_CopySelection :: proc(state: ^EditorState) {
	roots := Editor_SelectionRoots(state)
	if len(roots) == 0 do return
	delete(nodeClipboard)
	nodeClipboard = strings.clone(Editor_SerializeNodes(state, roots))
	Clipboard_NoteSource(state, roots)
	imgui.SetClipboardText(strings.clone_to_cstring(strings.concatenate({NODE_CLIPBOARD_PREFIX, nodeClipboard}, context.temp_allocator), context.temp_allocator))
	Editor_Log(state, .Info, "Copied %d node(s)", len(roots))
}

Editor_CutSelection :: proc(state: ^EditorState) {
	Editor_CopySelection(state)
	Editor_DeleteSelection(state)
}

// Editor_PasteNodesInto pastes the copied nodes as children of `parent`.
Editor_PasteNodesInto :: proc(state: ^EditorState, parent: ^e.Node) {
	if nodeClipboard == "" || state.activeScene == nil || parent == nil do return
	Editor_RecordUndo(state, "Paste as child")
	mgr := state.activeScene.manager
	items := split_json_array(nodeClipboard)
	Editor_ClearSelection(state)
	for item in items {
		n := e.Scene_InstantiateNodeFromJSON(state.activeScene, transmute([]u8)item, parent, &state.game.gameContext)
		if n == nil do continue
		n.name = strings.clone(Editor_UniqueChildName(state, parent, n.name, n), n.allocator)
		n.position = {0, 0}
		append(&state.selection, n)
		state.selectedNode = n
	}
	e.ProcessNodeQueues(mgr, &state.game.gameContext)
	for n in state.selection do e.Node_ForgetCopiedUids(mgr, n) // (copies are new nodes: #77)
	e.Node_SetGlobalPositions(mgr, state.activeScene.rootNode)
}

Editor_PasteNodes :: proc(state: ^EditorState) {
	// Nodes copied in another editor window arrive through the system clipboard.
	if clip := imgui.GetClipboardText(); clip != nil && strings.has_prefix(string(clip), NODE_CLIPBOARD_PREFIX) {
		if string(clip)[len(NODE_CLIPBOARD_PREFIX):] != nodeClipboard {
			delete(nodeClipboardScene) // from another window: no source scene
			nodeClipboardScene = ""
			clear(&nodeClipboardWorld)
		}
		delete(nodeClipboard)
		nodeClipboard = strings.clone(string(clip)[len(NODE_CLIPBOARD_PREFIX):])
	}
	if nodeClipboard == "" || state.activeScene == nil do return
	Editor_RecordUndo(state, "Paste")
	step := state.gridSize if state.gridSize > 0 else 16
	n: int
	if Clipboard_FromOtherScene(state) {
		n = Editor_InstantiateNodes(state, nodeClipboard, -1, {}, nodeClipboardWorld[:])
	} else {
		n = Editor_InstantiateNodes(state, nodeClipboard, -1, {step, step})
	}
	Editor_Log(state, .Info, "Pasted %d node(s)", n)
}

// --- nudge -------------------------------------------------------------------------

@(private = "file")
lastNudge: time.Tick

// Editor_NudgeSelection moves the selection by one pixel (Shift: one grid
// step) in world space. A burst of nudges is one undo step.
Editor_NudgeSelection :: proc(state: ^EditorState, dir: [2]f32) {
	roots := Editor_SelectionRoots(state)
	if len(roots) == 0 do return
	io := imgui.GetIO()
	step: f32 = 1
	if io.KeyShift do step = state.gridSize if state.gridSize > 0 else 16
	if time.tick_since(lastNudge) > 600 * time.Millisecond do Editor_RecordUndo(state, "Nudge")
	lastNudge = time.tick_now()
	mgr := state.activeScene.manager
	for n in roots {
		n.position = e.Node_WorldToParent(mgr, n, n.globalPosition + dir * step)
	}
	e.Node_SetGlobalPositions(mgr, state.activeScene.rootNode)
}

// --- align -------------------------------------------------------------------------

Align_Mode :: enum {
	Left,
	CenterX,
	Right,
	Top,
	CenterY,
	Bottom,
	DistributeX,
	DistributeY,
}

@(private = "file")
node_aabb :: proc(state: ^EditorState, n: ^e.Node) -> (mn, mx: [2]f32) {
	q, _ := Node_Bounds(state, n)
	mn, mx = q[0], q[0]
	for p in q {
		mn = {min(mn.x, p.x), min(mn.y, p.y)}
		mx = {max(mx.x, p.x), max(mx.y, p.y)}
	}
	return
}

// Editor_Align lines up the selected nodes' bounds (world space).
Editor_Align :: proc(state: ^EditorState, mode: Align_Mode) {
	roots := Editor_SelectionRoots(state)
	if len(roots) < 2 do return
	mgr := state.activeScene.manager
	Editor_RecordUndo(state, fmt.tprintf("Align %v", mode))
	// Overall bounds.
	allMn, allMx := node_aabb(state, roots[0])
	for n in roots[1:] {
		a, b := node_aabb(state, n)
		allMn = {min(allMn.x, a.x), min(allMn.y, a.y)}
		allMx = {max(allMx.x, b.x), max(allMx.y, b.y)}
	}
	move :: proc(state: ^EditorState, mgr: ^e.NodeManager, n: ^e.Node, d: [2]f32) {
		n.position = e.Node_WorldToParent(mgr, n, n.globalPosition + d)
	}
	switch mode {
	case .Left, .CenterX, .Right, .Top, .CenterY, .Bottom:
		for n in roots {
			mn, mx := node_aabb(state, n)
			d: [2]f32
			switch mode {
			case .Left:    d.x = allMn.x - mn.x
			case .Right:   d.x = allMx.x - mx.x
			case .CenterX: d.x = (allMn.x + allMx.x) * 0.5 - (mn.x + mx.x) * 0.5
			case .Top:     d.y = allMn.y - mn.y
			case .Bottom:  d.y = allMx.y - mx.y
			case .CenterY: d.y = (allMn.y + allMx.y) * 0.5 - (mn.y + mx.y) * 0.5
			case .DistributeX, .DistributeY:
			}
			move(state, mgr, n, d)
		}
	case .DistributeX, .DistributeY:
		axis := 0 if mode == .DistributeX else 1
		sorted := slice.clone(roots, context.temp_allocator)
		Center_Sort :: struct {state: ^EditorState, axis: int}
		ctx := Center_Sort{state, axis}
		center :: proc(state: ^EditorState, n: ^e.Node, axis: int) -> f32 {
			mn, mx := node_aabb(state, n)
			return (mn[axis] + mx[axis]) * 0.5
		}
		// Insertion sort by center (small lists).
		for i in 1 ..< len(sorted) {
			for j := i; j > 0 && center(ctx.state, sorted[j], axis) < center(ctx.state, sorted[j - 1], axis); j -= 1 {
				sorted[j], sorted[j - 1] = sorted[j - 1], sorted[j]
			}
		}
		first := center(state, sorted[0], axis)
		last := center(state, sorted[len(sorted) - 1], axis)
		gap := (last - first) / f32(len(sorted) - 1)
		for n, i in sorted {
			d: [2]f32
			d[axis] = first + gap * f32(i) - center(state, n, axis)
			move(state, mgr, n, d)
		}
	}
	e.Node_SetGlobalPositions(mgr, state.activeScene.rootNode)
	_ = math.PI
}

// --- rename ------------------------------------------------------------------------

@(private = "file")
renameTarget: ^e.Node
@(private = "file")
renameBuf: [128]u8
@(private = "file")
renameOpen := false

Editor_BeginRename :: proc(state: ^EditorState) {
	if state.selectedNode == nil do return
	renameTarget = state.selectedNode
	renameBuf = {}
	copy(renameBuf[:len(renameBuf) - 1], renameTarget.name)
	renameOpen = true
}

// Rename_Render draws the F2 rename popup.
Rename_Render :: proc(state: ^EditorState) {
	if renameOpen {
		imgui.OpenPopup("Rename Node###RenameNode")
		renameOpen = false
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, {}, {0.5, 0.5})
	if !imgui.BeginPopupModal("Rename Node###RenameNode", nil, {.NoTitleBar, .AlwaysAutoResize}) do return
	UI_PanelTitle(ICON_FA_PEN, "Rename node")
	if imgui.IsWindowAppearing() do imgui.SetKeyboardFocusHere()
	imgui.SetNextItemWidth(320)
	enter := imgui.InputText("##rename", cstring(raw_data(renameBuf[:])), len(renameBuf), {.EnterReturnsTrue, .AutoSelectAll})
	Drive_Item("rename.input")
	if (enter || UI_PrimaryButton("Rename", "rename.ok")) && e.Node_IsAlive(renameTarget) {
		name := strings.trim_space(string(cstring(raw_data(renameBuf[:]))))
		if name != "" && name != renameTarget.name {
			Editor_RecordUndo(state, "Rename")
			parent := e.GetParent(state.activeScene.manager, renameTarget)
			snap := NodeRefs_Capture(state)
			renameTarget.name = strings.clone(Editor_UniqueChildName(state, parent, name, renameTarget), renameTarget.allocator)
			NodeRefs_AfterChange(state, snap)
		}
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Cancel", "rename.cancel") || imgui.IsKeyPressed(.Escape, false) do imgui.CloseCurrentPopup()
	imgui.EndPopup()
}
