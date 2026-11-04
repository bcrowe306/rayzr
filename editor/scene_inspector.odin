package editor

import "core:c"
import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Right Sidebar: Clean Hierarchy (No bullets / trailing arrows) & Inspector
// ============================================================================

SceneInspector_Render :: proc(state: ^EditorState) {
	SceneHierarchy_RenderWindow(state)
	PropertyInspector_RenderWindow(state)
}

// ----------------------------------------------------------------------------
// 1. Scene tree: flat rows with type icons; drag a row onto another to
//    re-parent (onto empty space = root); right-click for actions; the eye
//    toggles visibility; double-click frames the node in the viewport.
// ----------------------------------------------------------------------------

hierarchyFilterBuf: [128]u8
hierarchyPendingFocus: ^e.Node
inlineRenameNode: ^e.Node
inlineRenameBuf: [128]u8
inlineRenameFocus: bool

Editor_BeginInlineRename :: proc(state: ^EditorState, node: ^e.Node) {
	if node == nil || state.activeScene == nil || node == state.activeScene.rootNode do return
	if node.editorLocked || Editor_NodeLocked(state, node) do return
	inlineRenameNode = node
	inlineRenameBuf = {}
	copy(inlineRenameBuf[:len(inlineRenameBuf) - 1], node.name)
	inlineRenameFocus = true
}

SceneHierarchy_RenderWindow :: proc(state: ^EditorState) {
	defer imgui.End()
	if !imgui.Begin("Scene###SceneHierarchyWindow") do return
	Drive_Window("scene") // (annotated docs screenshots)
	PanelHelp_Mark("scene-tree")
	// While the game runs: Local (the edited scene) / Remote (the game's live tree).
	if RemoteView_Header(state) {
		RemoteTree_Render(state, "hier")
		return
	}
	if state.activeScene == nil {
		inlineRenameNode = nil
		UI_DimText("No scene open")
		return
	}
	if inlineRenameNode != nil && (!e.Node_IsAlive(inlineRenameNode) || !node_in_scene(state, inlineRenameNode)) {
		inlineRenameNode = nil
	}

	// Header: scene name (+ modified dot) and actions on the right.
	modified := Editor_SceneIsModifiedCached(state, state.activeScene)
	title := Asset_DisplayName(state.activeScenePath) if state.activeScenePath != "" else state.activeScene.name
	UI_PanelTitle(ICON_FA_LAYER_GROUP, title)
	if modified {
		imgui.SameLine(0, 6)
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.PushFont(GlobalFonts.small)
		imgui.TextUnformatted(ICON_FA_CIRCLE)
		imgui.PopFont()
		imgui.PopStyleColor()
		UI_Tooltip("Unsaved changes (Ctrl+S to save)")
	}
	canModify := state.selectedNode != nil && state.selectedNode != state.activeScene.rootNode
	UI_HeaderButtons(3)
	if UI_HeaderButton(ICON_FA_PLUS, "hier.add", "Add node (Ctrl+A)") do AddNodeDialog_Open()
	if !canModify do imgui.BeginDisabled(true)
	if UI_HeaderButton(ICON_FA_COPY, "hier.duplicate", "Duplicate (Ctrl+D)") do SceneHierarchy_DuplicateSelected(state)
	if UI_HeaderButton(ICON_FA_TRASH, "hier.delete", "Delete (Del)") do SceneHierarchy_DeleteSelected(state)
	if !canModify do imgui.EndDisabled()
	Editor_FormatNewerBanner(state)

	// Tabs: the tree, the scene's signal connections, its settings (#195).
	req, hasReq := scenePanelTabRequest.?
	scenePanelTabRequest = nil
	tabFlags :: proc(t, req: Scene_Panel_Tab, has: bool) -> imgui.TabItemFlags {return {.SetSelected} if has && req == t else {}}
	if !imgui.BeginTabBar("##scene_panel_tabs", {}) do return
	defer imgui.EndTabBar()
	showTree := imgui.BeginTabItem(fmt.ctprintf("%s  Tree###scene_tree", ICON_FA_SITEMAP), nil, tabFlags(.Tree, req, hasReq))
	Drive_Item("scene.tab:tree")
	if showTree {
		scenePanelTab = .Tree
		scene_tree(state)
		imgui.EndTabItem()
	}
	if imgui.BeginTabItem(fmt.ctprintf("%s  Signals###scene_signals", ICON_FA_BOLT), nil, tabFlags(.Signals, req, hasReq)) {
		scenePanelTab = .Signals
		ScenePanel_Signals(state)
		imgui.EndTabItem()
	}
	Drive_Item("scene.tab:signals")
	UI_Tooltip("Every signal connection in this scene")
	if imgui.BeginTabItem(fmt.ctprintf("%s  Settings###scene_settings", ICON_FA_SLIDERS), nil, tabFlags(.Settings, req, hasReq)) {
		scenePanelTab = .Settings
		ScenePanel_Settings(state)
		imgui.EndTabItem()
	}
	Drive_Item("scene.tab:settings")
	UI_Tooltip("The scene's own settings: background, ambient light")
}

// scene_tree: the Tree tab - the filter and the node tree.
@(private = "file")
scene_tree :: proc(state: ^EditorState) {
	imgui.SetNextItemWidth(-1)
	imgui.InputTextWithHint("##hierfilter", fmt.ctprintf("%s  Filter: name  #tag  t:type", ICON_FA_MAGNIFYING_GLASS), cstring(raw_data(hierarchyFilterBuf[:])), len(hierarchyFilterBuf), {})
	Drive_Item("hier.filter")
	imgui.Dummy({0, 2})

	filter := strings.to_lower(string(cstring(raw_data(hierarchyFilterBuf[:]))), context.temp_allocator)
	imgui.PushStyleVarImVec2(.ItemSpacing, {4, 2})
	imgui.PushStyleVarImVec2(.FramePadding, {6, 4})
	if imgui.BeginChild("##tree", {0, 0}, {}, {}) {
		root := state.activeScene.rootNode
		if root != nil {
			kids := e.GetChildrenTemp(state.activeScene.manager, root)
			render_rows(state, kids, "", filter)
			if len(kids) == 0 && filter == "" {
				// An empty scene: what to do first.
				imgui.Dummy({0, 6})
				imgui.PushTextWrapPos(0)
				imgui.PushStyleColorImVec4(.Text, UI_TEXT_FAINT)
				imgui.TextWrapped("%s", fmt.ctprintf("This scene is empty. Add a node with %s (" + CMD + "+A), or drag an image, component or level from Assets into the viewport.", ICON_FA_PLUS))
				imgui.PopStyleColor()
				imgui.PopTextWrapPos()
				Drive_Item("hier.empty-hint")
			}
			// Drop on empty space: move to the root.
			imgui.Dummy({imgui.GetContentRegionAvail().x, max(imgui.GetContentRegionAvail().y, 40)})
			Drive_Item("hier.empty")
			if imgui.BeginDragDropTarget() {
				if payload := imgui.AcceptDragDropPayload("RAYZR_NODE"); payload != nil {
					dragged := (^^e.Node)(payload.Data)^
					Editor_ReparentNode(state, dragged, root)
				}
				imgui.EndDragDropTarget()
			}
			if imgui.IsItemClicked(.Left) do state.selectedNode = nil
			if imgui.BeginPopupContextItem("##hier_empty_ctx") {
				Editor_ClearSelection(state)
				if hier_menu(ICON_FA_PLUS, "Add Node...", "add-node", true, CMD + "+A") do AddNodeDialog_Open()
				if hier_menu(ICON_FA_PASTE, "Paste", "paste", Editor_HasClipboardNodes(), CMD + "+V") do Editor_PasteNodes(state)
				if hier_menu(ICON_FA_CHECK, "Select All", "select-all", true, CMD + "+Shift+A") do Editor_SelectAllNodes(state)
				imgui.EndPopup()
			}
		}
	}
	imgui.EndChild()
	imgui.PopStyleVar(2)
}

// subtree_matches: a node is shown when it or a descendant matches the filter.
@(private = "file")
subtree_matches :: proc(state: ^EditorState, node: ^e.Node, filter: string) -> bool {
	if node_matches(node, filter) do return true
	for c in e.GetChildrenView(state.activeScene.manager, node) do if subtree_matches(state, c, filter) do return true
	return false
}

// render_rows draws sibling rows. Runs of leaf rows outside the visible
// part of the panel are skipped as one spacer (rows have a fixed height):
// a flat list of thousands of nodes costs only the rows on screen. Skipped
// rows still register for test drives (and scroll into view).
@(private = "file")
render_rows :: proc(state: ^EditorState, children: []^e.Node, parentPath: string, filter: string) {
	mgr := state.activeScene.manager
	step := imgui.GetFrameHeight() + imgui.GetStyle().ItemSpacing.y
	top := imgui.GetScrollY() - step
	bottom := imgui.GetScrollY() + imgui.GetWindowHeight()
	skippable :: proc(mgr: ^e.NodeManager, n: ^e.Node, filter: string) -> bool {
		return filter == "" && len(e.GetChildrenView(mgr, n)) == 0 && n != hierarchyPendingFocus
	}
	i := 0
	for i < len(children) {
		y := imgui.GetCursorPosY()
		if skippable(mgr, children[i], filter) && (y + step < top || y > bottom) {
			// A run of off-screen leaves.
			start := imgui.GetCursorScreenPos()
			width := imgui.GetContentRegionAvail().x
			count := 0
			for i + count < len(children) && skippable(mgr, children[i + count], filter) {
				ry := y + f32(count) * step
				if !(ry + step < top || ry > bottom) do break
				if GlobalDrive.enabled && !FrameTiming_Benching() { // (not while a drive times frames: drive-only work)
					n := children[i + count]
					path := n.name if parentPath == "" else fmt.tprintf("%s/%s", parentPath, n.name)
					mn := [2]f32{start.x, start.y + f32(count) * step}
					Drive_ItemRect(fmt.tprintf("hier:%s", path), mn, mn + {width, step - imgui.GetStyle().ItemSpacing.y}, inWindow = true)
				}
				count += 1
			}
			imgui.Dummy({1, f32(count) * step - imgui.GetStyle().ItemSpacing.y})
			i += count
			continue
		}
		SceneHierarchy_RenderNodeTree(state, children[i], parentPath, filter)
		i += 1
	}
}

// The row pressed (selected on release unless it was dragged).
@(private = "file")
hierPress: struct {
	node: ^e.Node,
	at:   [2]f32,
}

SceneHierarchy_RenderNodeTree :: proc(state: ^EditorState, node: ^e.Node, parentPath: string, filter: string) {
	if node == nil || !subtree_matches(state, node, filter) do return
	mgr := state.activeScene.manager
	path := node.name if parentPath == "" else fmt.tprintf("%s/%s", parentPath, node.name)
	children := e.GetChildrenTemp(mgr, node)

	flags: imgui.TreeNodeFlags = {.SpanAvailWidth, .OpenOnArrow, .FramePadding}
	if len(children) == 0 do flags += {.Leaf, .NoTreePushOnOpen}
	else do flags += {.DefaultOpen}
	if filter != "" do imgui.SetNextItemOpen(true)
	if Editor_IsSelected(state, node) || node == state.selectedNode do flags += {.Selected}

	dim := !node.enabled || !node.renderable || node.editorHidden
	rowColor := UI_TEXT_FAINT if dim else UI_TEXT
	if node.componentMissing do rowColor = UI_DANGER // its component file is missing (a placeholder)
	else if node.componentPath != "" do rowColor = {0.75, 0.62, 1.0, 1} // component instance
	else if Editor_NodeLocked(state, node) do rowColor = {0.75, 0.62, 1.0, 0.55}
	else if t := e.Node_CustomType(node); t != nil {
		// A custom node type: its colour (#156).
		rowColor = CustomNode_Color(t)
		if dim do rowColor.w = 0.55
	}
	imgui.PushStyleColorImVec4(.Text, rowColor)
	imgui.SetNextItemAllowOverlap() // the visibility button sits on the row

	isRenaming := inlineRenameNode == node
	label := fmt.ctprintf("%s###n%p", Editor_NodeIcon(node), node) if isRenaming else fmt.ctprintf("%s   %s###n%p", Editor_NodeIcon(node), node.name, node)
	open := imgui.TreeNodeEx(label, flags)
	imgui.PopStyleColor()
	Drive_Item(fmt.tprintf("hier:%s", path))

	if isRenaming {
		imgui.SameLine(0, 6)
		if inlineRenameFocus {
			imgui.SetKeyboardFocusHere()
			inlineRenameFocus = false
		}
		imgui.PushStyleVarImVec2(.FramePadding, {2, 1})
		avail := imgui.GetWindowContentRegionMax().x - imgui.GetCursorPosX() - 50
		imgui.SetNextItemWidth(max(60, avail))
		enter := imgui.InputText("##inline_rename", cstring(raw_data(inlineRenameBuf[:])), len(inlineRenameBuf), {.EnterReturnsTrue, .AutoSelectAll})
		Drive_Item("hier.inline_rename")
		deactivated := imgui.IsItemDeactivatedAfterEdit()
		escape := imgui.IsKeyPressed(.Escape, false)
		if escape {
			inlineRenameNode = nil
		} else if enter || deactivated {
			name := strings.trim_space(string(cstring(raw_data(inlineRenameBuf[:]))))
			if name != "" && name != node.name && e.Node_IsAlive(node) {
				Editor_RecordUndo(state, "Rename")
				parent := e.GetParent(state.activeScene.manager, node)
				snap := NodeRefs_Capture(state)
				node.name = strings.clone(Editor_UniqueChildName(state, parent, name, node), node.allocator)
				NodeRefs_AfterChange(state, snap)
			}
			inlineRenameNode = nil
		} else if imgui.IsMouseClicked(.Left) && !imgui.IsItemHovered() {
			name := strings.trim_space(string(cstring(raw_data(inlineRenameBuf[:]))))
			if name != "" && name != node.name && e.Node_IsAlive(node) {
				Editor_RecordUndo(state, "Rename")
				parent := e.GetParent(state.activeScene.manager, node)
				snap := NodeRefs_Capture(state)
				node.name = strings.clone(Editor_UniqueChildName(state, parent, name, node), node.allocator)
				NodeRefs_AfterChange(state, snap)
			}
			inlineRenameNode = nil
		}
		imgui.PopStyleVar()
	}

	// Select on release, not press: dragging a row (onto the Inspector, e.g.
	// a camera's Follow Target) mustn't select it and swap the Inspector.
	if imgui.IsItemClicked(.Left) && !imgui.IsItemToggledOpen() {
		hierPress = {node, {imgui.GetIO().MousePos.x, imgui.GetIO().MousePos.y}}
	}
	if hierPress.node == node && imgui.IsMouseReleased(.Left) {
		io := imgui.GetIO()
		d := [2]f32{io.MousePos.x, io.MousePos.y} - hierPress.at
		if d.x * d.x + d.y * d.y < 36 {
			Editor_SelectNode(state, node, io.KeyCtrl || io.KeySuper || io.KeyShift)
			PreviewPanel_OnNodeSelected(state, node)
		}
		hierPress = {}
	}
	if imgui.IsItemHovered() && imgui.IsMouseDoubleClicked(.Left) && !isRenaming {
		state.cameraPos = node.globalPosition
		Editor_BeginInlineRename(state, node)
	}
	if node == hierarchyPendingFocus {
		imgui.SetScrollHereY(0.5)
		hierarchyPendingFocus = nil
	}

	// Drag to re-parent.
	if imgui.BeginDragDropSource({}) {
		n := node
		imgui.SetDragDropPayload("RAYZR_NODE", &n, size_of(^e.Node))
		imgui.TextUnformatted(fmt.ctprintf("%s  %s", Editor_NodeIcon(node), node.name))
		imgui.EndDragDropSource()
	}
	// The row's top / bottom edge: place before / after it; the middle:
	// make it a child.
	if imgui.BeginDragDropTarget() {
		rmin, rmax := imgui.GetItemRectMin(), imgui.GetItemRectMax()
		my := imgui.GetIO().MousePos.y
		edge := (rmax.y - rmin.y) * 0.28
		zone := 0
		if e.GetParent(mgr, node) != nil {
			if my < rmin.y + edge do zone = -1
			else if my > rmax.y - edge && !(open && len(children) > 0) do zone = 1
		}
		flags: imgui.DragDropFlags = {.AcceptBeforeDelivery}
		if zone != 0 do flags += {.AcceptNoDrawDefaultRect}
		if payload := imgui.AcceptDragDropPayload("RAYZR_NODE", flags); payload != nil {
			if zone != 0 {
				y := rmin.y if zone < 0 else rmax.y
				dl := imgui.GetWindowDrawList()
				imgui.DrawList_AddLine(dl, {rmin.x, y}, {rmax.x, y}, col_u32(UI_ACCENT), 2)
			}
			if payload.Delivery {
				dragged := (^^e.Node)(payload.Data)^
				if zone != 0 {
					_ = Editor_InsertNodeAt(state, dragged, node, zone > 0)
				} else if Editor_ReparentNode(state, dragged, node) {
					Editor_Log(state, .Info, "Moved %s under %s", dragged.name, node.name)
				}
			}
		}
		// A script from Assets: attach it (replacing the node's script).
		if payload := imgui.AcceptDragDropPayload(ASSET_PAYLOAD, {.AcceptBeforeDelivery, .AcceptNoDrawDefaultRect}); payload != nil {
			p := (^Asset_Payload)(payload.Data)
			rel := strings.clone(string(p.path[:p.len]), context.temp_allocator)
			if Asset_KindOf(rel) == .Script && node != state.activeScene.rootNode {
				rmin, rmax := imgui.GetItemRectMin(), imgui.GetItemRectMax()
				imgui.DrawList_AddRect(imgui.GetWindowDrawList(), rmin, rmax, col_u32(UI_ACCENT), 4, {}, 2)
				verb := "Replace the script of" if node.scriptInstance != nil else "Attach to"
				imgui.SetTooltip("%s", fmt.ctprintf("%s  %s %s", ICON_FA_FILE_CODE, verb, node.name))
				if payload.Delivery && Editor_AttachScript(state, node, rel) do Editor_SelectNode(state, node)
			}
		}
		imgui.EndDragDropTarget()
	}

	// Right-click actions.
	if imgui.BeginPopupContextItem(fmt.ctprintf("ctx%p", node)) {
		if !Editor_IsSelected(state, node) do Editor_SelectNode(state, node)
		Node_ContextMenu(state, node)
		imgui.EndPopup()
	}

	// Visibility toggle at the right edge of the row.
	rowMax := imgui.GetItemRectMax()
	imgui.SameLine(imgui.GetWindowContentRegionMax().x - 22)
	imgui.PushStyleColorImVec4(.Button, {0, 0, 0, 0})
	imgui.PushStyleColorImVec4(.ButtonHovered, UI_BG_HOVER)
	imgui.PushStyleColorImVec4(.Text, UI_TEXT_FAINT)
	imgui.PushStyleVarImVec2(.FramePadding, {3, 2})
	if imgui.SmallButton(fmt.ctprintf("%s##vis%p", ICON_FA_EYE if node.renderable else ICON_FA_EYE_SLASH, node)) {
		Editor_RecordUndo(state, "Toggle visibility")
		node.renderable = !node.renderable
	}
	Drive_Item(fmt.tprintf("hier.vis:%s", path))
	// Viewport lock / hidden-in-editor markers (click to clear), left of it.
	x := imgui.GetWindowContentRegionMax().x - 22
	if node.editorHidden {
		x -= 22
		imgui.SameLine(x)
		if imgui.SmallButton(fmt.ctprintf("%s##ehid%p", ICON_FA_EYE_LOW_VISION, node)) {
			Editor_RecordUndo(state, "Show in editor")
			node.editorHidden = false
		}
		UI_Tooltip("Hidden in the editor (the game shows it). Click to show")
		Drive_Item(fmt.tprintf("hier.ehidden:%s", path))
	}
	if node.editorLocked {
		x -= 22
		imgui.SameLine(x)
		if imgui.SmallButton(fmt.ctprintf("%s##lock%p", ICON_FA_LOCK, node)) {
			Editor_RecordUndo(state, "Unlock")
			node.editorLocked = false
		}
		UI_Tooltip("Locked: can't be picked or moved in the viewport. Click to unlock")
		Drive_Item(fmt.tprintf("hier.lock:%s", path))
	}
	// A script is attached: click to open it.
	if node.scriptInstance != nil {
		rel := asset_rel_editor(state, (cast(^e.ScriptInstance)node.scriptInstance).modulePath)
		x -= 22
		imgui.SameLine(x)
		imgui.PushStyleColorImVec4(.Text, UI_ACCENT)
		if imgui.SmallButton(fmt.ctprintf("%s##script%p", ICON_FA_FILE_CODE, node)) do Editor_OpenScript(state, rel)
		imgui.PopStyleColor()
		UI_Tooltip(fmt.tprintf("Script: %s - click to open it", rel))
		Drive_Item(fmt.tprintf("hier.script:%s", path))
	}
	imgui.PopStyleVar()
	imgui.PopStyleColor(3)
	_ = rowMax

	if open && len(children) > 0 {
		render_rows(state, children, path, filter)
		imgui.TreePop()
	}
}

SceneHierarchy_DuplicateSelected :: proc(state: ^EditorState) {
	if len(state.selection) > 1 {
		if n := Editor_DuplicateSelection(state); n > 0 do Editor_Log(state, .Info, "Duplicated %d nodes", n)
		return
	}
	if copy := Editor_DuplicateNode(state, state.selectedNode); copy != nil {
		Editor_Log(state, .Info, "Duplicated node as '%s'", copy.name)
	}
}

SceneHierarchy_DeleteSelected :: proc(state: ^EditorState) {
	if state.selectedNode == nil do return
	if len(state.selection) > 1 {
		if n := Editor_DeleteSelection(state); n > 0 do Editor_Log(state, .Info, "Deleted %d nodes", n)
		return
	}
	name := strings.clone(state.selectedNode.name, context.temp_allocator)
	if Editor_DeleteNode(state, state.selectedNode) {
		Editor_Log(state, .Info, "Deleted node '%s'", name)
	}
}


@(private = "file")
hier_menu :: proc(icon, label, id: string, enabled := true, shortcut: cstring = nil) -> bool {
	clicked := imgui.MenuItem(fmt.ctprintf("%s  %s", icon, label), shortcut, false, enabled)
	Drive_Item(fmt.tprintf("ctx:%s", id))
	return clicked
}

// Node_ContextMenu: every action for a node (or the selection it is in).
// Editor_SceneCamera: the active scene's current camera (else its first).
Editor_SceneCamera :: proc(state: ^EditorState) -> ^e.CameraNode {
	if state.activeScene == nil || state.activeScene.manager == nil do return nil
	first: ^e.CameraNode
	for n in state.activeScene.manager.nodes {
		if n == nil || n.typeId != e.CameraNode do continue
		c := cast(^e.CameraNode)n
		if c.isCurrent do return c
		if first == nil do first = c
	}
	return first
}

Node_ContextMenu :: proc(state: ^EditorState, node: ^e.Node) {
	mgr := state.activeScene.manager
	isRoot := node == state.activeScene.rootNode
	locked := Editor_NodeLocked(state, node)
	inst := e.Node_ComponentRoot(mgr, node)
	multi := len(state.selection) > 1
	UI_DimText(fmt.tprintf("%d nodes", len(state.selection)) if multi else node.name)
	imgui.Separator()
	if hier_menu(ICON_FA_PLUS, "Add Child...", "add-child", true, CMD + "+A") {
		state.selectedNode = node
		AddNodeDialog_Open()
	}
	compOpen := imgui.BeginMenu(fmt.ctprintf("%s  Add Component as Child", ICON_FA_CUBES))
	Drive_Item("ctx:add-component-child")
	if compOpen {
		for rel in Editor_ListProjectFiles(state, "components", {".component.json"}) {
			if imgui.MenuItem(strings.clone_to_cstring(rel, context.temp_allocator)) {
				state.selectedNode = node
				Editor_InstantiateComponentFile(state, rel, node.globalPosition)
			}
			Drive_Item(fmt.tprintf("ctx:component:%s", rel))
		}
		imgui.EndMenu()
	}
	imgui.Separator()
	if hier_menu(ICON_FA_SCISSORS, "Cut", "cut", !isRoot, CMD + "+X") do Editor_CutSelection(state)
	if hier_menu(ICON_FA_COPY, "Copy", "copy", !isRoot, CMD + "+C") do Editor_CopySelection(state)
	if hier_menu(ICON_FA_PASTE, "Paste", "paste", Editor_HasClipboardNodes(), CMD + "+V") do Editor_PasteNodes(state)
	if hier_menu(ICON_FA_PASTE, "Paste as Child", "paste-child", Editor_HasClipboardNodes()) do Editor_PasteNodesInto(state, node)
	if hier_menu(ICON_FA_CLONE, "Duplicate", "duplicate", !isRoot, CMD + "+D") do SceneHierarchy_DuplicateSelected(state)
	if hier_menu(ICON_FA_PEN, "Rename", "rename", !isRoot && !locked && !multi, "F2") {
		state.selectedNode = node
		Editor_BeginRename(state)
	}
	if hier_menu(ICON_FA_TRASH, "Delete", "delete", !isRoot, "Del") do SceneHierarchy_DeleteSelected(state)
	imgui.Separator()
	parent := e.GetParent(mgr, node)
	index, count := 0, 0
	if parent != nil {
		kids := e.GetChildrenView(mgr, parent)
		count = len(kids)
		for k, i in kids do if k == node do index = i
	}
	// (Inside an instance too: its order is saved as an override, #78.)
	if hier_menu(ICON_FA_ARROW_UP, "Move Up", "move-up", parent != nil && index > 0) {
		Editor_RecordUndo(state, "Move up")
		e.MoveChild(mgr, parent, node, index - 1)
	}
	if hier_menu(ICON_FA_ARROW_DOWN, "Move Down", "move-down", parent != nil && index < count - 1) {
		Editor_RecordUndo(state, "Move down")
		e.MoveChild(mgr, parent, node, index + 1)
	}
	if hier_menu(ICON_FA_ARROW_TURN_UP, "Move to Root", "move-root", parent != nil && parent != state.activeScene.rootNode && !locked) {
		Editor_ReparentNode(state, node, state.activeScene.rootNode)
	}
	if hier_menu(ICON_FA_CHECK, "Select Children", "select-children", len(e.GetChildrenView(mgr, node)) > 0) {
		Editor_ClearSelection(state)
		for c in e.GetChildrenView(mgr, node) do if c != nil && !c.transient do Editor_SelectNode(state, c, true)
	}
	imgui.Separator()
	if hier_menu(ICON_FA_POWER_OFF, "Disable" if node.enabled else "Enable", "toggle-enabled", !isRoot) {
		Editor_RecordUndo(state, "Toggle enabled")
		on := !node.enabled
		for n in Editor_SelectionRoots(state) do n.enabled = on
	}
	if hier_menu(ICON_FA_EYE, "Hide" if node.renderable else "Show", "toggle-visible", !isRoot) {
		Editor_RecordUndo(state, "Toggle visible")
		on := !node.renderable
		for n in Editor_SelectionRoots(state) do n.renderable = on
	}
	if hier_menu(ICON_FA_LOCK_OPEN if node.editorLocked else ICON_FA_LOCK, "Unlock in Viewport" if node.editorLocked else "Lock in Viewport", "toggle-lock", !isRoot) do Editor_ToggleViewLock(state)
	if hier_menu(ICON_FA_EYE_LOW_VISION, "Show in Editor" if node.editorHidden else "Hide in Editor", "toggle-editor-hidden", !isRoot) do Editor_ToggleViewHidden(state)
	if hier_menu(ICON_FA_CROSSHAIRS, "Frame in Viewport", "frame", true, "F") do state.cameraPos = node.globalPosition
	if !isRoot {
		SendToScene_Menu(state, false)
		SendToScene_Menu(state, true)
	}
	imgui.Separator()
	// Script.
	if node.scriptInstance != nil {
		if hier_menu(ICON_FA_CODE, "Open Script", "open-script") do Editor_OpenScript(state, (cast(^e.ScriptInstance)node.scriptInstance).modulePath)
		if hier_menu(ICON_FA_XMARK, "Detach Script", "detach-script") {
			Editor_RecordUndo(state, "Detach script")
			e.ScriptInstance_Destroy(cast(^e.ScriptInstance)node.scriptInstance, &state.game.scriptManager)
			node.scriptInstance = nil
		}
	} else if !isRoot {
		attachOpen := imgui.BeginMenu(fmt.ctprintf("%s  Attach Script", ICON_FA_CODE))
		Drive_Item("ctx:attach-script")
		if attachOpen {
			if hier_menu(ICON_FA_PLUS, "New Script...", "attach-new-script") do NewScriptDialog_Open(state, node)
			imgui.Separator()
			for rel in Editor_ListProjectFiles(state, "scripts", {".lua"}) {
				if imgui.MenuItem(strings.clone_to_cstring(rel, context.temp_allocator)) {
					Editor_RecordUndo(state, "Attach script")
					node.gameContext = &state.game.gameContext
					e.Script_AttachToNode(node, rel, nil, &state.game.scriptManager)
				}
			}
			imgui.EndMenu()
		}
	}
	if hier_menu(ICON_FA_BOOK, "Documentation", "node-docs", shortcut = "Shift+F1") do NodeReference_Open(e.Node_TypeName(node))
	// Components.
	imgui.Separator()
	if inst != nil {
		if hier_menu(ICON_FA_CUBES, "Edit Component", "edit-component") do Editor_EditComponentAt(state, node)
		if hier_menu(ICON_FA_OBJECT_GROUP, "Select All Instances", "select-instances") do Editor_SelectAllInstances(state, strings.clone(inst.componentPath, context.temp_allocator))
		if hier_menu(ICON_FA_FLOPPY_DISK, "Apply Changes to Component", "apply-component") do Editor_ApplyInstanceToComponent(state, inst)
		if hier_menu(ICON_FA_CLONE, "Save as New Component...", "save-new-component") do Prompt_Open(.SaveComponentAs, fmt.tprintf("%s_variant", inst.name), inst)
		if hier_menu(ICON_FA_ROTATE_LEFT, "Revert Overrides" if node == inst else "Revert This Node", "revert-overrides") {
			Editor_RecordUndo(state, "Revert overrides")
			sel := Editor_SaveSelection(state) // (the instance is rebuilt: #74)
			e.Scene_RevertComponentOverrides(state.activeScene, node, &state.game.gameContext)
			Editor_RestoreSelection(state, sel)
		}
		if hier_menu(ICON_FA_LINK_SLASH, "Unlink", "unlink-component", node == inst) {
			Editor_RecordUndo(state, "Unlink component")
			e.Node_UnlinkComponent(node)
		}
	} else if !isRoot {
		if hier_menu(ICON_FA_CUBES, "Save as Component", "save-component") do Editor_SaveComponent(state, node)
		if hier_menu(ICON_FA_CLONE, "Save as Component Named...", "save-component-named") do Prompt_Open(.SaveComponentAs, node.name, node)
		if hier_menu(ICON_FA_PUZZLE_PIECE, "Save as Custom Node...", "save-custom-node", node.customType == "") do CustomNodeDialog_OpenFromNode(state, node)
		UI_Tooltip("A node type of your own from this node: its type, values and script (Add Node lists it); it becomes one")
	}
	if node.customType != "" && !node.customMissing && Editor_IsCustomNodeDoc(state, state.activeScene) {
		if hier_menu(ICON_FA_SHUFFLE, "Change Base Type...", "rebase-custom-node") do CustomNodeRebase_Open(state, node.customType)
	}
	if node.customType != "" && !node.customMissing && !Editor_IsCustomNodeDoc(state, state.activeScene) {
		if hier_menu(ICON_FA_PEN_TO_SQUARE, fmt.tprintf("Edit the %s Type", e.Node_ClassName(node)), "edit-custom-type") do Editor_OpenCustomNodeType(state, node.customType)
		UI_Tooltip("Its type's default values (every node of it that doesn't change them follows)")
	}
	imgui.Separator()
	if cam := Editor_SceneCamera(state); cam != nil && node.typeId != e.CameraNode && !node.transient {
		following := cam.followTarget != "" && e.Node_ResolvePath(state.activeScene.manager, cam, cam.followTarget) == node
		if hier_menu(ICON_FA_VIDEO, "Camera Stops Following" if following else "Camera Follows This", "camera-follow") {
			Editor_RecordUndo(state, "Camera follow target")
			e.CameraNode_SetFollowTarget(cam, state.activeScene.manager, nil if following else node)
		}
	}
	if hier_menu(ICON_FA_LINK, "Copy Node Path", "copy-node-path") {
		imgui.SetClipboardText(strings.clone_to_cstring(e.Node_RelativePath(mgr, state.activeScene.rootNode, node), context.temp_allocator))
	}
}
