package engine

import "core:strings"
import "core:fmt"
import "core:math"
import "core:strconv"
import rl "vendor:raylib"
import uilib "../ui"

// ============================================================================
// UI Widget Types & Base Element (Backed by standalone `ui` package)
// ============================================================================
UIWidgetType :: uilib.WidgetType
UITreeViewItem :: uilib.TreeViewItem
UITextAlign :: uilib.TextAlign
UI_PointInRect :: uilib.PointInRect
UIVolumeMeterState :: uilib.VolumeMeterState
UISliderOrientation :: uilib.SliderOrientation
UIMeterOrientation :: uilib.MeterOrientation
UIBulletStyle :: uilib.BulletStyle
UINumberingStyle :: uilib.NumberingStyle
UIListItem :: uilib.ListItem
UITableColumn :: uilib.TableColumn
UITableRow :: uilib.TableRow
UITableCell :: uilib.TableCell
Icon :: uilib.Icon
ToolbarItem :: uilib.ToolbarItem
ToolbarItemType :: uilib.ToolbarItemType

UIElement :: struct {
	using node: Node,
	widgetType: UIWidgetType,
	size: [2]f32 `gui:"true" min:"4" max:"1280"`,
	keyboardFocus: bool `gui:"true"`, // Tab / arrows reach it (off: only the mouse - buttons beside gameplay keys)
	hovered: bool,
	focused: bool,
	justFocused: bool,
}

UIElement_Init :: proc(elem: ^UIElement, widgetType: UIWidgetType, size: [2]f32) {
	elem.isUI = true
	elem.widgetType = widgetType
	elem.size = size
	elem.keyboardFocus = true
	elem.layer = .Layer7
	elem.hovered = false
	elem.focused = false
	elem.justFocused = false
}

// ============================================================================
// UI Input & Viewport Coordinate Helpers (Window + Headless Test Compatible)
// ============================================================================
// UI_GetMousePos: the mouse in game units, in the unscaled space of the UI
// node whose input is being handled (accessibility UI scale).
UI_GetMousePos :: proc(gameContext: ^GameContext) -> [2]f32 {
	raw := UI_GetMousePosRaw(gameContext)
	if cam, ok := ui_world_camera(uiInputNode, gameContext); ok do return rl.GetScreenToWorld2D(raw, cam)
	return UI_UnscalePoint(uiInputNode, raw)
}

// ui_world_camera: the camera a UI node is drawn through when it's in the
// world - not under a Screen Layer, on a layer the current camera shows -
// so it reads the mouse in world coordinates too (#228).
@(private = "file")
ui_world_camera :: proc(n: ^Node, gc: ^GameContext) -> (cam: rl.Camera2D, ok: bool) {
	if n == nil || gc == nil || gc.game == nil || gc.scene == nil || gc.scene.manager == nil do return
	c := gc.scene.camera
	if c == nil || !c.enabled || !c.isCurrent || n.layer not_in c.targetLayers do return
	for p := GetParent(gc.scene.manager, n); p != nil; p = GetParent(gc.scene.manager, p) {
		if p.typeId == ScreenLayerNode do return
	}
	return CameraNode_GetCamera2D(c, gc.game.virtualSize[0], gc.game.virtualSize[1]), true
}

// UI_GetMousePosRaw: the mouse in game units (screen space).
UI_GetMousePosRaw :: proc(gameContext: ^GameContext) -> [2]f32 {
	if gameContext != nil && gameContext.game != nil {
		g := gameContext.game
		if p, ok := Game_Pointer(g); ok do return p.pos // (the test mouse, a finger)
		if rl.IsWindowReady() {
			mp := rl.GetMousePosition()
			cRect := g.viewportCanvasRect
			if cRect.width > 0 && cRect.height > 0 && g.virtualSize[0] > 0 && g.virtualSize[1] > 0 {
				return {
					(mp.x - cRect.x) * (g.virtualSize[0] / cRect.width),
					(mp.y - cRect.y) * (g.virtualSize[1] / cRect.height),
				}
			}
			return {mp.x, mp.y}
		}
	}
	if rl.IsWindowReady() {
		mp := rl.GetMousePosition()
		return {mp.x, mp.y}
	}
	return {-1000, -1000}
}

UI_IsMouseInViewport :: proc(gameContext: ^GameContext) -> bool {
	if gameContext != nil && gameContext.game != nil {
		g := gameContext.game
		if _, ok := Game_Pointer(g); ok do return true
		if rl.IsWindowReady() {
			mp := rl.GetMousePosition()
			cRect := g.viewportCanvasRect
			if cRect.width > 0 && cRect.height > 0 {
				return rl.CheckCollisionPointRec(mp, cRect)
			}
			return true
		}
	}
	return rl.IsWindowReady()
}

UI_IsMousePressed :: proc(gameContext: ^GameContext) -> bool {
	if gameContext != nil {
		if p, ok := Game_Pointer(gameContext.game); ok do return p.pressed
	}
	return rl.IsWindowReady() && UI_IsMouseInViewport(gameContext) && rl.IsMouseButtonPressed(.LEFT)
}

UI_IsMouseDown :: proc(gameContext: ^GameContext) -> bool {
	if gameContext != nil {
		if p, ok := Game_Pointer(gameContext.game); ok do return p.down
	}
	return rl.IsWindowReady() && rl.IsMouseButtonDown(.LEFT)
}

UI_IsMouseReleased :: proc(gameContext: ^GameContext) -> bool {
	if gameContext != nil {
		if p, ok := Game_Pointer(gameContext.game); ok do return p.released
	}
	return rl.IsWindowReady() && rl.IsMouseButtonReleased(.LEFT)
}

// UI_GetMouseWheel: the wheel this frame (+ up).
UI_GetMouseWheel :: proc(gameContext: ^GameContext) -> f32 {
	if gameContext != nil && gameContext.game != nil && gameContext.game.uiTestInputEnabled do return gameContext.game.uiTestWheel
	return rl.GetMouseWheelMove() if rl.IsWindowReady() else 0
}

UI_IsRightMousePressed :: proc(gameContext: ^GameContext) -> bool {
	if gameContext != nil && gameContext.game != nil && gameContext.game.uiTestInputEnabled {
		return gameContext.game.uiTestRightPressed
	}
	return rl.IsWindowReady() && UI_IsMouseInViewport(gameContext) && rl.IsMouseButtonPressed(.RIGHT)
}

UI_IsShiftDown :: proc(gameContext: ^GameContext) -> bool {
	if gameContext != nil && gameContext.game != nil && gameContext.game.uiTestInputEnabled {
		return gameContext.game.uiTestShiftDown
	}
	return rl.IsWindowReady() && (rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT))
}

// ui_key: a key pressed this frame for the widgets - a simulated one (the
// engine's input layer: --input-script keys, Test.press_key; #362) or the
// keyboard's (`repeat`: its auto-repeat too).
@(private = "file")
ui_key :: proc(gameContext: ^GameContext, key: rl.KeyboardKey, repeat := false) -> bool {
	if gameContext != nil && gameContext.game != nil {
		input := &gameContext.game.input
		if input.useSimulatedInput && Input_SimulatedKeyPressed(input, key) do return true
	}
	return rl.IsWindowReady() && (rl.IsKeyPressed(key) || (repeat && rl.IsKeyPressedRepeat(key)))
}

UI_IsKeyPressedEnter :: proc(gameContext: ^GameContext) -> bool {
	if gameContext != nil && gameContext.game != nil && gameContext.game.uiTestInputEnabled {
		return gameContext.game.uiTestKeyEnter
	}
	return ui_key(gameContext, .ENTER) || ui_key(gameContext, .KP_ENTER) || uiPad.confirm
}

UI_IsKeyPressedSpace :: proc(gameContext: ^GameContext) -> bool {
	if gameContext != nil && gameContext.game != nil && gameContext.game.uiTestInputEnabled {
		return gameContext.game.uiTestKeySpace
	}
	return ui_key(gameContext, .SPACE)
}

UI_IsKeyPressedTab :: proc(gameContext: ^GameContext) -> bool {
	if gameContext != nil && gameContext.game != nil && gameContext.game.uiTestInputEnabled {
		return gameContext.game.uiTestKeyTab
	}
	return ui_key(gameContext, .TAB)
}

UI_IsKeyPressedUp :: proc(gameContext: ^GameContext) -> bool {
	if gameContext != nil && gameContext.game != nil && gameContext.game.uiTestInputEnabled {
		return gameContext.game.uiTestKeyUp
	}
	return ui_key(gameContext, .UP, true) || uiPad.fire[0]
}

UI_IsKeyPressedDown :: proc(gameContext: ^GameContext) -> bool {
	if gameContext != nil && gameContext.game != nil && gameContext.game.uiTestInputEnabled {
		return gameContext.game.uiTestKeyDown
	}
	return ui_key(gameContext, .DOWN, true) || uiPad.fire[1]
}

UI_IsKeyPressedLeft :: proc(gameContext: ^GameContext) -> bool {
	if gameContext != nil && gameContext.game != nil && gameContext.game.uiTestInputEnabled {
		return gameContext.game.uiTestKeyLeft
	}
	return ui_key(gameContext, .LEFT, true) || uiPad.fire[2]
}

UI_IsKeyPressedRight :: proc(gameContext: ^GameContext) -> bool {
	if gameContext != nil && gameContext.game != nil && gameContext.game.uiTestInputEnabled {
		return gameContext.game.uiTestKeyRight
	}
	return ui_key(gameContext, .RIGHT, true) || uiPad.fire[3]
}

UI_IsKeyPressedBackspace :: proc(gameContext: ^GameContext) -> bool {
	if gameContext != nil && gameContext.game != nil && gameContext.game.uiTestInputEnabled {
		return gameContext.game.uiTestKeyBackspace
	}
	return ui_key(gameContext, .BACKSPACE)
}

UI_IsKeyPressedEscape :: proc(gameContext: ^GameContext) -> bool {
	if gameContext != nil && gameContext.game != nil && gameContext.game.uiTestInputEnabled {
		return gameContext.game.uiTestKeyEscape
	}
	return ui_key(gameContext, .ESCAPE)
}

UI_PopCharPressed :: proc(gameContext: ^GameContext) -> u8 {
	if gameContext != nil && gameContext.game != nil && gameContext.game.uiTestInputEnabled {
		g := gameContext.game
		if g.uiTestCharCount > 0 {
			ch := g.uiTestCharQueue[0]
			for i in 0..<(g.uiTestCharCount - 1) {
				g.uiTestCharQueue[i] = g.uiTestCharQueue[i + 1]
			}
			g.uiTestCharCount -= 1
			return ch
		}
		return 0
	}
	if rl.IsWindowReady() {
		ch := rl.GetCharPressed()
		if ch >= 32 && ch <= 126 {
			return u8(ch)
		}
	}
	return 0
}

UI_GetElementPos :: proc(elem: ^UIElement) -> [2]f32 {
	if elem.globalPosition.x != 0 || elem.globalPosition.y != 0 {
		return elem.globalPosition
	}
	return elem.position
}

UI_GetElementRect :: proc(elem: ^UIElement) -> rl.Rectangle {
	pos := UI_GetElementPos(elem)
	return rl.Rectangle{pos.x, pos.y, elem.size.x, elem.size.y}
}

UI_IsBlockedByActiveDropdown :: proc(gameContext: ^GameContext, self: rawptr, mousePos: [2]f32) -> bool {
	if gameContext == nil || gameContext.game == nil do return false
	active := gameContext.game.activeDropdown
	if active == nil || active == self do return false
	dd := cast(^UIDropdownNode)active
	if !dd.isOpen do return false
	popupRect := UIDropdownNode_GetPopupRect(dd)
	return UI_PointInRect(mousePos, popupRect)
}

// ============================================================================
// Focus & Keyboard Navigation Management
// ============================================================================

UI_IsFocusable :: proc(elem: ^UIElement) -> bool {
	if elem == nil || !elem.enabled || !elem.renderable || !elem.keyboardFocus do return false
	return UI_IsFocusableType(elem.widgetType)
}

// UI_IsFocusableType: the widgets Tab, the arrows and node:ui_focus reach.
UI_IsFocusableType :: proc(t: UIWidgetType) -> bool {
	#partial switch t {
	case .Button, .Slider, .Checkbox, .ToggleSwitch, .Knob,
	     .TextInput, .Dropdown, .RadioGroup, .ListView, .TreeView, .TabContainer,
	     .NotchedSlider, .VolumeFader, .UnorderedList, .OrderedList, .Table: // (#228: their keys work)
		return true
	case:
		return false
	}
}

// UI_TakesInput: a widget reacts to the mouse and keys only while it's shown
// (set_visible(false) hid it but left it clickable, #228); hidden, it lets
// go of hover and focus.
UI_TakesInput :: proc(elem: ^UIElement) -> bool {
	if elem.enabled && elem.renderable do return true
	elem.hovered = false
	elem.focused = false
	return false
}

UI_CollectFocusableElementsRec :: proc(scene: ^Scene, node: ^Node, outList: ^[dynamic]^UIElement) {
	if node == nil || !node.enabled do return
	if node.isUI {
		elem := cast(^UIElement)node
		if elem.widgetType != .None && UI_IsFocusable(elem) {
			append(outList, elem)
		}
	}
	children := GetChildren(scene.manager, node)
	defer delete(children)
	for child in children {
		UI_CollectFocusableElementsRec(scene, child, outList)
	}
}

UI_CollectFocusableElements :: proc(scene: ^Scene, outList: ^[dynamic]^UIElement) {
	if scene == nil || scene.manager == nil || scene.rootNode == nil do return
	UI_CollectFocusableElementsRec(scene, scene.rootNode, outList)
}

UI_SetFocus :: proc(scene: ^Scene, target: ^UIElement) {
	if scene == nil || scene.manager == nil do return
	for n in scene.manager.nodes {
		if n == nil || !n.isUI do continue
		elem := cast(^UIElement)n
		if elem.widgetType != .None {
			wasFocused := elem.focused
			elem.focused = (elem == target)
			if elem.focused && !wasFocused {
				elem.justFocused = true
			}
		}
	}
}

// UI_FocusNode gives a widget the keyboard / gamepad focus, as Tab would
// (node:ui_focus: a menu focuses its first button when it opens). "" when
// it took it, else why not (nothing changes then).
UI_FocusNode :: proc(game: ^Game, node: ^Node) -> string {
	if node == nil do return "no node"
	elem := cast(^UIElement)node
	if !node.isUI || elem.widgetType == .None do return "is not a UI widget"
	if !UI_IsFocusableType(elem.widgetType) do return fmt.tprintf("is a %s: it doesn't take the focus (buttons, sliders, checkboxes, inputs, dropdowns and lists do)", Node_TypeName(node))
	if !elem.keyboardFocus do return "has Keyboard Focus off"
	if !node.enabled do return "is disabled"
	if !node.renderable do return "is hidden"
	for p := node.parent; p != nil; p = p.parent {
		if !p.enabled do return fmt.tprintf("is under a disabled node (%s)", p.name)
	}
	scene := ui_scene_of(game, node)
	if scene == nil || node.removing do return "is not in a running scene"
	UI_SetFocus(scene, elem)
	return ""
}

// ui_scene_of: the loaded scene whose nodes include `node` (the current
// one first; a scene being changed to runs its ready() before it's current).
@(private = "file")
ui_scene_of :: proc(game: ^Game, node: ^Node) -> ^Scene {
	if game == nil do return nil
	has :: proc(s: ^Scene, node: ^Node) -> bool {
		if s == nil || s.manager == nil do return false
		for n in s.manager.nodes do if n == node do return true
		return false
	}
	sm := &game.sceneManager
	if has(sm.currentScene, node) do return sm.currentScene
	if has(sm.nextScene, node) do return sm.nextScene
	for _, s in sm.scenes do if has(s, node) do return s
	return nil
}

// UI_HasFocus: the widget has the keyboard / gamepad focus (node:ui_has_focus).
UI_HasFocus :: proc(node: ^Node) -> bool {
	if node == nil || !node.isUI do return false
	elem := cast(^UIElement)node
	return elem.widgetType != .None && elem.focused
}

UI_GetFocusedElement :: proc(scene: ^Scene) -> ^UIElement {
	if scene == nil || scene.manager == nil do return nil
	for n in scene.manager.nodes {
		if n == nil || !n.isUI do continue
		elem := cast(^UIElement)n
		if elem.widgetType != .None && elem.focused {
			return elem
		}
	}
	return nil
}

UI_ClearFocus :: proc(scene: ^Scene) {
	if scene == nil || scene.manager == nil do return
	for n in scene.manager.nodes {
		if n == nil || !n.isUI do continue
		elem := cast(^UIElement)n
		if elem.widgetType != .None {
			elem.focused = false
		}
	}
}

UI_DoesWidgetConsumeDirection :: proc(elem: ^UIElement, dir: uilib.NavDirection) -> bool {
	if elem == nil do return false
	#partial switch elem.widgetType {
	case .Slider:
		return dir == .Left || dir == .Right
	case .ToggleSwitch:
		return dir == .Left || dir == .Right
	case .Knob:
		return dir == .Left || dir == .Right
	case .RadioGroup:
		rg := cast(^UIRadioGroupNode)elem
		if rg.horizontal {
			return dir == .Left || dir == .Right
		} else {
			return dir == .Up || dir == .Down
		}
	case .ListView, .VolumeFader, .UnorderedList, .OrderedList, .Table:
		return dir == .Up || dir == .Down
	case .NotchedSlider:
		return dir == .Left || dir == .Right
	case .TreeView:
		return true
	case .Dropdown:
		dd := cast(^UIDropdownNode)elem
		return dd.isOpen && (dir == .Up || dir == .Down)
	case .TabContainer:
		tc := cast(^UITabContainerNode)elem
		if tc.tabDirection == .Horizontal {
			return dir == .Left || dir == .Right
		} else {
			return dir == .Up || dir == .Down
		}
	case:
		return false
	}
}

// Gamepad menu navigation: the D-pad or the left stick move the focus
// (repeating while held, like keys), A confirms - computed once a frame.
@(private = "file")
uiPad: struct {
	fire:    [4]bool, // up, down, left, right: move this frame
	held:    [4]f32,  // seconds held
	confirm: bool,
	aDown:   bool, // A held last frame (confirm: when it goes down)
}

UI_PAD_REPEAT_DELAY :: 0.4
UI_PAD_REPEAT_EVERY :: 0.12

@(private = "file")
ui_update_pad :: proc(gameContext: ^GameContext) {
	uiPad.fire, uiPad.confirm = {}, false
	if gameContext == nil || gameContext.game == nil || !rl.IsWindowReady() do return
	// (Player 1's pad, real or simulated: input_players.odin.)
	input := &gameContext.game.input
	pad := input.gamepadIndex
	if !Input_PadConnected(input, pad) {
		uiPad.held = {}
		uiPad.aDown = false
		return
	}
	lx, ly := Input_PadAxis(input, pad, .LEFT_X), Input_PadAxis(input, pad, .LEFT_Y)
	down := [4]bool{
		Input_PadButtonDown(input, pad, .LEFT_FACE_UP) || ly < -0.5,
		Input_PadButtonDown(input, pad, .LEFT_FACE_DOWN) || ly > 0.5,
		Input_PadButtonDown(input, pad, .LEFT_FACE_LEFT) || lx < -0.5,
		Input_PadButtonDown(input, pad, .LEFT_FACE_RIGHT) || lx > 0.5,
	}
	dt := rl.GetFrameTime()
	for i in 0 ..< 4 {
		if !down[i] {
			uiPad.held[i] = 0
			continue
		}
		before := uiPad.held[i]
		uiPad.held[i] += dt
		if before == 0 do uiPad.fire[i] = true
		else if uiPad.held[i] >= UI_PAD_REPEAT_DELAY {
			// Every UI_PAD_REPEAT_EVERY after the delay.
			n0 := int((before - UI_PAD_REPEAT_DELAY) / UI_PAD_REPEAT_EVERY) if before >= UI_PAD_REPEAT_DELAY else -1
			n1 := int((uiPad.held[i] - UI_PAD_REPEAT_DELAY) / UI_PAD_REPEAT_EVERY)
			uiPad.fire[i] = n1 != n0
		}
	}
	a := Input_PadButtonDown(input, pad, .RIGHT_FACE_DOWN)
	uiPad.confirm = a && !uiPad.aDown
	uiPad.aDown = a
}

UI_UpdateFocusNavigation :: proc(scene: ^Scene, gameContext: ^GameContext) {
	if scene == nil || scene.manager == nil do return
	ui_update_pad(gameContext)

	// Reset justFocused flags from previous frame
	for n in scene.manager.nodes {
		if n == nil || !n.isUI do continue
		elem := cast(^UIElement)n
		if elem.widgetType != .None {
			elem.justFocused = false
		}
	}

	// 1. Mouse Click Focusing
	if UI_IsMousePressed(gameContext) {
		if gameContext != nil && gameContext.game != nil && gameContext.game.activeDropdown != nil {
			// let dropdown overlay process
		} else {
			elements := make([dynamic]^UIElement)
			defer delete(elements)
			UI_CollectFocusableElements(scene, &elements)

			mp := UI_GetMousePosRaw(gameContext)
			clickedElem: ^UIElement = nil
			for elem in elements {
				rect := UI_GetElementRect(elem)
				if UI_PointInRect(UI_UnscalePoint(elem, mp), rect) { // (in its UI-scale space)
					clickedElem = elem
					break
				}
			}

			if clickedElem != nil {
				UI_SetFocus(scene, clickedElem)
			}
		}
	}

	// 2. Tab / Shift+Tab Cycling
	if UI_IsKeyPressedTab(gameContext) {
		elements := make([dynamic]^UIElement)
		defer delete(elements)
		UI_CollectFocusableElements(scene, &elements)

		count := len(elements)
		if count > 0 {
			curIdx := -1
			for i in 0..<count {
				if elements[i].focused {
					curIdx = i
					break
				}
			}
			isShift := UI_IsShiftDown(gameContext)
			nextIdx := uilib.NavCycle(count, curIdx, !isShift)
			if nextIdx >= 0 && nextIdx < count {
				UI_SetFocus(scene, elements[nextIdx])
			}
		}
		return
	}

	// 3. Directional Navigation (Up, Down, Left, Right)
	dir: uilib.NavDirection
	hasDir := false
	if UI_IsKeyPressedUp(gameContext) {
		dir = .Up
		hasDir = true
	} else if UI_IsKeyPressedDown(gameContext) {
		dir = .Down
		hasDir = true
	} else if UI_IsKeyPressedLeft(gameContext) {
		dir = .Left
		hasDir = true
	} else if UI_IsKeyPressedRight(gameContext) {
		dir = .Right
		hasDir = true
	}

	if hasDir {
		cur := UI_GetFocusedElement(scene)
		// If currently focused element consumes this direction, it handles it in its own update!
		if cur != nil && UI_DoesWidgetConsumeDirection(cur, dir) {
			// Do not move focus spatially; widget handles directional key internally
		} else {
			// Spatial 2D navigation
			elements := make([dynamic]^UIElement)
			defer delete(elements)
			UI_CollectFocusableElements(scene, &elements)

			count := len(elements)
			if count > 0 {
				curIdx := -1
				rects := make([]rl.Rectangle, count)
				defer delete(rects)

				for i in 0..<count {
					rects[i] = UI_GetElementRect(elements[i])
					if elements[i].focused {
						curIdx = i
					}
				}

				nextIdx := uilib.NavFindNextSpatial(rects, curIdx, dir)
				if nextIdx >= 0 && nextIdx < count {
					UI_SetFocus(scene, elements[nextIdx])
				}
			}
		}
	}
}

// ============================================================================
// 1. UILabelNode (Label)
// ============================================================================
UILabelNode :: struct {
	using ui: UIElement,
	text: string `gui:"true"`,
	fontSize: f32 `gui:"true" min:"8" max:"72"`,
	textColor: rl.Color `gui:"true"`,
	align: UITextAlign `gui:"true"`,
	drawBackground: bool `gui:"true"`,
	backgroundColor: rl.Color `gui:"true"`,
}

UILabel :: UILabelNode

UILabelNode_Create :: proc(
	scene: ^Scene,
	name: string = "Label",
	text: string = "Label",
	fontSize: f32 = uilib.DEFAULT_FONT_SIZE,
	parent: ^Node = nil,
	textColor: rl.Color = {238, 240, 246, 255},
) -> ^UILabelNode {
	lbl := CreateNode(scene.manager, UILabelNode)
	lbl.name = strings.clone(name, lbl.allocator) // owned: callers pass temp strings too
	UIElement_Init(&lbl.ui, .Label, {240, fontSize + 8})
	lbl.text = strings.clone(text, lbl.allocator)
	lbl.fontSize = fontSize
	lbl.textColor = textColor
	lbl.align = .Left
	lbl.drawBackground = false
	lbl.backgroundColor = {30, 32, 38, 200}
	lbl.render = UILabelNode_Render
	scene->addNode(lbl, parent)
	return lbl
}

UILabelNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	lbl := cast(^UILabelNode)node
	rect := UI_GetElementRect(&lbl.ui)
	uilib.RenderLabel(rect, lbl.text, lbl.fontSize, lbl.textColor, lbl.align, lbl.drawBackground, lbl.backgroundColor)
}

// ============================================================================
// 2. UIButtonNode (Button)
// ============================================================================
UIButtonNode :: struct {
	using ui: UIElement,
	text: string `gui:"true"`,
	fontSize: f32 `gui:"true" min:"8" max:"48"`,
	icon: Icon `gui:"true"`,
	iconSize: f32 `gui:"true" min:"0" max:"64"`,
	normalColor: rl.Color `gui:"true"`,
	hoverColor: rl.Color `gui:"true"`,
	pressedColor: rl.Color `gui:"true"`,
	borderColor: rl.Color `gui:"true"`,
	textColor: rl.Color `gui:"true"`,
	align: UITextAlign `gui:"true"`,
	isPressed: bool,
	wasClicked: bool,
	onClick: EventSubject,
	onClickCallback: proc(btn: ^UIButtonNode, gameContext: ^GameContext),
}

UIButton :: UIButtonNode

UIButtonNode_Create :: proc(
	scene: ^Scene,
	name: string = "Button",
	text: string = "Button",
	size: [2]f32 = {200, 36},
	parent: ^Node = nil,
	fontSize: f32 = uilib.DEFAULT_FONT_SIZE,
	icon: Icon = .None,
	iconSize: f32 = 0,
) -> ^UIButtonNode {
	btn := CreateNode(scene.manager, UIButtonNode)
	btn.name = strings.clone(name, btn.allocator) // owned: callers pass temp strings too
	UIElement_Init(&btn.ui, .Button, size)
	btn.text = strings.clone(text, btn.allocator)
	btn.fontSize = fontSize
	btn.icon = icon
	btn.iconSize = iconSize
	btn.normalColor = {35, 39, 49, 255}
	btn.hoverColor = {50, 56, 72, 255}
	btn.pressedColor = {37, 99, 235, 255}
	btn.borderColor = {75, 83, 102, 255}
	btn.textColor = {238, 240, 246, 255}
	btn.align = .Center
	btn.isPressed = false
	btn.wasClicked = false
	InitializeSubject(&btn.onClick, "clicked", btn)
	btn.update = UIButtonNode_Update
	btn.render = UIButtonNode_Render
	btn.onDestroy = UIButtonNode_Destroy
	scene->addNode(btn, parent)
	return btn
}

UIButtonNode_TriggerClick :: proc(btn: ^UIButtonNode, gameContext: ^GameContext) {
	btn.wasClicked = true
	if btn.onClick.notify != nil {
		btn.onClick->notify(btn, true, gameContext)
	}
	if btn.onClickCallback != nil {
		btn->onClickCallback(gameContext)
	}
}

UIButtonNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	btn := cast(^UIButtonNode)node
	btn.wasClicked = false
	if !UI_TakesInput(btn) do return

	// Keyboard activation when focused
	if btn.focused && !btn.justFocused && (UI_IsKeyPressedEnter(gameContext) || UI_IsKeyPressedSpace(gameContext)) {
		UIButtonNode_TriggerClick(btn, gameContext)
	}

	mp := UI_GetMousePos(gameContext)
	if UI_IsBlockedByActiveDropdown(gameContext, btn, mp) {
		btn.hovered = false
		btn.isPressed = false
		return
	}

	rect := UI_GetElementRect(&btn.ui)
	btn.hovered = UI_IsMouseInViewport(gameContext) && UI_PointInRect(mp, rect)

	if btn.hovered {
		if gameContext != nil && gameContext.game != nil {
			gameContext.game.uiMouseConsumed = true
		}
		if UI_IsMousePressed(gameContext) {
			btn.isPressed = true
		}
	}

	if btn.isPressed {
		if UI_IsMouseReleased(gameContext) {
			btn.isPressed = false
			if btn.hovered {
				UIButtonNode_TriggerClick(btn, gameContext)
			}
		} else if !UI_IsMouseDown(gameContext) {
			btn.isPressed = false
		}
	}
}

UIButtonNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	btn := cast(^UIButtonNode)node
	rect := UI_GetElementRect(&btn.ui)
	if btn.icon != .None {
		uilib.RenderIconButton(
			rect,
			btn.icon,
			btn.text,
			btn.iconSize,
			btn.hovered,
			btn.isPressed,
			btn.focused,
			false,
			btn.normalColor,
			btn.hoverColor,
			btn.pressedColor,
			btn.borderColor,
			btn.textColor,
			btn.align,
		)
	} else {
		uilib.RenderButton(
			rect,
			btn.text,
			btn.fontSize,
			btn.hovered,
			btn.isPressed,
			btn.normalColor,
			btn.hoverColor,
			btn.pressedColor,
			btn.borderColor,
			btn.textColor,
			align = btn.align,
			focused = btn.focused,
		)
	}
}

UIButtonNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	btn := cast(^UIButtonNode)node
	DestroySubject(&btn.onClick)
}

// ============================================================================
// 3. UISliderNode (Slider with Editable Text, Shift Fine Adjust, & Reset)
// ============================================================================
UISliderNode :: struct {
	using ui: UIElement,
	label: string `gui:"true"`,
	value: f32 `gui:"true" min:"-1000" max:"1000"`,
	minValue: f32 `gui:"true" min:"-10000" max:"10000"`,
	maxValue: f32 `gui:"true" min:"-10000" max:"10000"`,
	defaultValue: f32 `gui:"true" min:"-10000" max:"10000"`,
	fineScale: f32 `gui:"true" min:"0.01" max:"0.5"`,
	isInteger: bool `gui:"true"`,
	showResetButton: bool `gui:"true"`,
	labelWidth: f32 `gui:"true" min:"0" max:"300"`,
	isDragging: bool,
	isEditingText: bool,
	fineModeActive: bool,
	dragLastMouseX: f32,
	editBuffer: [64]u8,
	editLen: int,
	onChanged: EventSubject,
	onChangedCallback: proc(s: ^UISliderNode, val: f32, gameContext: ^GameContext),
}

UISlider :: UISliderNode

UISliderNode_Create :: proc(
	scene: ^Scene,
	name: string = "Slider",
	label: string = "Value",
	value: f32 = 0.5,
	minValue: f32 = 0.0,
	maxValue: f32 = 1.0,
	parent: ^Node = nil,
	defaultValue: f32 = math.F32_MAX,
	isInteger: bool = false,
	showResetButton: bool = true,
) -> ^UISliderNode {
	s := CreateNode(scene.manager, UISliderNode)
	s.name = strings.clone(name, s.allocator) // owned: callers pass temp strings too
	UIElement_Init(&s.ui, .Slider, {360, 28})
	s.label = strings.clone(label, s.allocator)
	s.value = value
	s.minValue = minValue
	s.maxValue = maxValue
	s.defaultValue = value if defaultValue == math.F32_MAX else defaultValue
	s.fineScale = 0.1
	s.isInteger = isInteger
	s.showResetButton = showResetButton
	s.labelWidth = 110
	s.isDragging = false
	s.isEditingText = false
	s.fineModeActive = false
	s.editLen = 0
	InitializeSubject(&s.onChanged, "value_changed", s)
	s.update = UISliderNode_Update
	s.render = UISliderNode_Render
	s.onDestroy = UISliderNode_Destroy
	scene->addNode(s, parent)
	return s
}

UISliderNode_GetSubRects :: proc(s: ^UISliderNode) -> (trackRect, valBoxRect, resetRect: rl.Rectangle) {
	rect := UI_GetElementRect(&s.ui)
	return uilib.GetSliderSubRects(rect, s.label != "", s.labelWidth, s.showResetButton)
}

UISliderNode_SetValue :: proc(s: ^UISliderNode, val: f32, gameContext: ^GameContext = nil) {
	clamped := clamp(val, s.minValue, s.maxValue)
	if s.isInteger {
		clamped = math.round(clamped)
	}
	if abs(s.value - clamped) > 0.0001 {
		s.value = clamped
		if s.onChanged.notify != nil {
			s.onChanged->notify(s, s.value, gameContext)
		}
		if s.onChangedCallback != nil {
			s->onChangedCallback(s.value, gameContext)
		}
	}
}

UISliderNode_Reset :: proc(s: ^UISliderNode, gameContext: ^GameContext = nil) {
	s.isEditingText = false
	s.isDragging = false
	UISliderNode_SetValue(s, s.defaultValue, gameContext)
}

UISliderNode_BeginTextEdit :: proc(s: ^UISliderNode) {
	s.isEditingText = true
	s.isDragging = false
	s.editLen = 0
	valStr: string
	if s.isInteger {
		valStr = fmt.tprintf("%d", int(math.round(s.value)))
	} else {
		valStr = fmt.tprintf("%.2f", s.value)
	}
	copy(s.editBuffer[:], valStr)
	s.editLen = len(valStr)
}

UISliderNode_CommitTextEdit :: proc(s: ^UISliderNode, gameContext: ^GameContext = nil) {
	s.isEditingText = false
	if s.editLen > 0 {
		str := string(s.editBuffer[:s.editLen])
		parsed, ok := strconv.parse_f64(str)
		if ok {
			UISliderNode_SetValue(s, f32(parsed), gameContext)
		}
	}
}

UISliderNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	s := cast(^UISliderNode)node
	if !UI_TakesInput(s) do return

	mp := UI_GetMousePos(gameContext)
	if UI_IsBlockedByActiveDropdown(gameContext, s, mp) {
		s.hovered = false
		return
	}

	rect := UI_GetElementRect(&s.ui)
	trackRect, valBoxRect, resetRect := UISliderNode_GetSubRects(s)

	s.hovered = UI_IsMouseInViewport(gameContext) && UI_PointInRect(mp, rect)
	shiftHeld := UI_IsShiftDown(gameContext)
	s.fineModeActive = shiftHeld && (s.isDragging || s.hovered)

	if s.hovered && gameContext != nil && gameContext.game != nil {
		gameContext.game.uiMouseConsumed = true
	}

	// 1. Handle Reset Button click or Right-Click on track
	if s.showResetButton && UI_PointInRect(mp, resetRect) && UI_IsMousePressed(gameContext) {
		UISliderNode_Reset(s, gameContext)
		return
	}
	if UI_PointInRect(mp, trackRect) && UI_IsRightMousePressed(gameContext) {
		UISliderNode_Reset(s, gameContext)
		return
	}

	// 2. Handle Editable Text Box
	if s.isEditingText {
		if UI_IsKeyPressedEscape(gameContext) {
			s.isEditingText = false
			return
		}
		if UI_IsKeyPressedEnter(gameContext) || (UI_IsMousePressed(gameContext) && !UI_PointInRect(mp, valBoxRect)) {
			UISliderNode_CommitTextEdit(s, gameContext)
			return
		}
		if UI_IsKeyPressedBackspace(gameContext) && s.editLen > 0 {
			s.editLen -= 1
		}
		for {
			ch := UI_PopCharPressed(gameContext)
			if ch == 0 do break
			if (ch >= '0' && ch <= '9') || ch == '.' || ch == '-' {
				if s.editLen < len(s.editBuffer) - 1 {
					s.editBuffer[s.editLen] = ch
					s.editLen += 1
				}
			}
		}
		return
	}

	// Keyboard arrow navigation when focused
	if s.focused && !s.justFocused && !s.isEditingText {
		step: f32 = (s.maxValue - s.minValue) * (0.01 if shiftHeld else 0.05)
		if s.isInteger do step = max(math.round(step), 1.0)
		if UI_IsKeyPressedLeft(gameContext) {
			UISliderNode_SetValue(s, s.value - step, gameContext)
		} else if UI_IsKeyPressedRight(gameContext) {
			UISliderNode_SetValue(s, s.value + step, gameContext)
		}
		if UI_IsKeyPressedEnter(gameContext) {
			UISliderNode_BeginTextEdit(s)
			return
		}
	}

	// Click on value box (or Ctrl+click track) starts text editing
	ctrlHeld := rl.IsWindowReady() && (rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL))
	if UI_IsMousePressed(gameContext) {
		if UI_PointInRect(mp, valBoxRect) || (ctrlHeld && UI_PointInRect(mp, trackRect)) {
			UISliderNode_BeginTextEdit(s)
			return
		}
		if UI_PointInRect(mp, trackRect) {
			s.isDragging = true
			s.dragLastMouseX = mp.x
			if !shiftHeld && trackRect.width > 1 {
				t := clamp((mp.x - trackRect.x) / trackRect.width, 0.0, 1.0)
				UISliderNode_SetValue(s, s.minValue + t * (s.maxValue - s.minValue), gameContext)
			}
		}
	}

	// 3. Handle Dragging (with Shift for fine adjustment!)
	if s.isDragging {
		if !UI_IsMouseDown(gameContext) || UI_IsMouseReleased(gameContext) {
			s.isDragging = false
		} else if trackRect.width > 1 {
			dx := mp.x - s.dragLastMouseX
			s.dragLastMouseX = mp.x
			if abs(dx) > 0.0001 {
				range := s.maxValue - s.minValue
				if shiftHeld {
					deltaVal := (dx / trackRect.width) * range * s.fineScale
					UISliderNode_SetValue(s, s.value + deltaVal, gameContext)
				} else {
					t := clamp((mp.x - trackRect.x) / trackRect.width, 0.0, 1.0)
					UISliderNode_SetValue(s, s.minValue + t * range, gameContext)
				}
			}
		}
	}
}

UISliderNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	s := cast(^UISliderNode)node
	rect := UI_GetElementRect(&s.ui)
	uilib.RenderSlider(
		rect,
		s.label,
		s.value,
		s.minValue,
		s.maxValue,
		s.defaultValue,
		s.isInteger,
		s.showResetButton,
		s.labelWidth,
		s.hovered,
		s.isDragging,
		s.fineModeActive,
		s.isEditingText,
		string(s.editBuffer[:s.editLen]),
		focused = s.focused,
	)
}

UISliderNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	s := cast(^UISliderNode)node
	DestroySubject(&s.onChanged)
}

// ============================================================================
// 4. UICheckboxNode (Checkbox)
// ============================================================================
UICheckboxNode :: struct {
	using ui: UIElement,
	label: string `gui:"true"`,
	checked: bool `gui:"true"`,
	defaultChecked: bool `gui:"true"`,
	accentColor: rl.Color `gui:"true"`,
	boxSize: f32 `gui:"true" min:"12" max:"40"`,
	onChanged: EventSubject,
	onChangedCallback: proc(cb: ^UICheckboxNode, checked: bool, gameContext: ^GameContext),
}

UICheckbox :: UICheckboxNode

UICheckboxNode_Create :: proc(
	scene: ^Scene,
	name: string = "Checkbox",
	label: string = "Checkbox",
	checked: bool = false,
	parent: ^Node = nil,
) -> ^UICheckboxNode {
	cb := CreateNode(scene.manager, UICheckboxNode)
	cb.name = strings.clone(name, cb.allocator) // owned: callers pass temp strings too
	UIElement_Init(&cb.ui, .Checkbox, {260, 26})
	cb.label = strings.clone(label, cb.allocator)
	cb.checked = checked
	cb.defaultChecked = checked
	cb.accentColor = {59, 130, 246, 255}
	cb.boxSize = 14
	InitializeSubject(&cb.onChanged, "value_changed", cb)
	cb.update = UICheckboxNode_Update
	cb.render = UICheckboxNode_Render
	cb.onDestroy = UICheckboxNode_Destroy
	scene->addNode(cb, parent)
	return cb
}

UICheckboxNode_SetChecked :: proc(cb: ^UICheckboxNode, val: bool, gameContext: ^GameContext = nil) {
	if cb.checked != val {
		cb.checked = val
		if cb.onChanged.notify != nil {
			cb.onChanged->notify(cb, cb.checked, gameContext)
		}
		if cb.onChangedCallback != nil {
			cb->onChangedCallback(cb.checked, gameContext)
		}
	}
}

UICheckboxNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	cb := cast(^UICheckboxNode)node
	if !UI_TakesInput(cb) do return

	// Keyboard activation when focused
	if cb.focused && !cb.justFocused && (UI_IsKeyPressedEnter(gameContext) || UI_IsKeyPressedSpace(gameContext)) {
		UICheckboxNode_SetChecked(cb, !cb.checked, gameContext)
	}

	mp := UI_GetMousePos(gameContext)
	if UI_IsBlockedByActiveDropdown(gameContext, cb, mp) {
		cb.hovered = false
		return
	}

	rect := UI_GetElementRect(&cb.ui)
	cb.hovered = UI_IsMouseInViewport(gameContext) && UI_PointInRect(mp, rect)
	if cb.hovered {
		if gameContext != nil && gameContext.game != nil {
			gameContext.game.uiMouseConsumed = true
		}
		if UI_IsMousePressed(gameContext) {
			UICheckboxNode_SetChecked(cb, !cb.checked, gameContext)
		} else if UI_IsRightMousePressed(gameContext) {
			UICheckboxNode_SetChecked(cb, cb.defaultChecked, gameContext)
		}
	}
}

UICheckboxNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	cb := cast(^UICheckboxNode)node
	rect := UI_GetElementRect(&cb.ui)
	uilib.RenderCheckbox(rect, cb.label, cb.checked, cb.hovered, cb.accentColor, cb.boxSize, focused = cb.focused)
}

UICheckboxNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	cb := cast(^UICheckboxNode)node
	DestroySubject(&cb.onChanged)
}

// ============================================================================
// 5. UITextInputNode (TextInput)
// ============================================================================
UITextInputNode :: struct {
	using ui: UIElement,
	label: string `gui:"true"`,
	placeholder: string `gui:"true"`,
	text: string `gui:"true"`, // what's typed (saved; set from the Inspector or Lua - #227)
	syncedText: string,      // text as last matched to the buffer
	labelWidth: f32 `gui:"true" min:"0" max:"300"`,
	maxLength: int `gui:"true" min:"1" max:"255"`,
	buffer: [256]u8,
	textLen: int,
	blinkTimer: f32,
	onChanged: EventSubject,
	onSubmit: EventSubject,
}

UITextInput :: UITextInputNode

UITextInputNode_Create :: proc(
	scene: ^Scene,
	name: string = "TextInput",
	label: string = "Input",
	defaultText: string = "",
	placeholder: string = "Enter text...",
	parent: ^Node = nil,
) -> ^UITextInputNode {
	ti := CreateNode(scene.manager, UITextInputNode)
	ti.name = strings.clone(name, ti.allocator) // owned: callers pass temp strings too
	UIElement_Init(&ti.ui, .TextInput, {360, 28})
	ti.label = strings.clone(label, ti.allocator)
	ti.placeholder = strings.clone(placeholder, ti.allocator)
	ti.labelWidth = 130
	ti.maxLength = 64
	InitializeSubject(&ti.onChanged, "value_changed", ti)
	InitializeSubject(&ti.onSubmit, "submitted", ti)
	UITextInputNode_SetText(ti, defaultText)
	ti.update = UITextInputNode_Update
	ti.render = UITextInputNode_Render
	ti.onDestroy = UITextInputNode_Destroy
	scene->addNode(ti, parent)
	return ti
}

UITextInputNode_GetText :: proc(ti: ^UITextInputNode) -> string {
	text_input_sync(ti)
	return string(ti.buffer[:ti.textLen])
}

// text_input_sync keeps `text` and the typing buffer together: `text` set
// from outside (Inspector, scene, set_property) fills the buffer; typing
// updates `text`.
@(private = "file")
text_input_sync :: proc(ti: ^UITextInputNode) {
	if ti.text != ti.syncedText {
		n := min(len(ti.text), min(ti.maxLength, len(ti.buffer) - 1))
		copy(ti.buffer[:n], ti.text[:n])
		ti.textLen = n
		ti.syncedText = ti.text
	} else if typed := string(ti.buffer[:ti.textLen]); typed != ti.text {
		ti.text = strings.clone(typed, ti.allocator)
		ti.syncedText = ti.text
	}
}

UITextInputNode_SetText :: proc(ti: ^UITextInputNode, text: string, gameContext: ^GameContext = nil) {
	n := min(len(text), min(ti.maxLength, len(ti.buffer) - 1))
	for i in 0..<n {
		ti.buffer[i] = text[i]
	}
	ti.textLen = n
	if ti.onChanged.notify != nil {
		ti.onChanged->notify(ti, UITextInputNode_GetText(ti), gameContext)
	}
}

UITextInputNode_InsertChar :: proc(ti: ^UITextInputNode, ch: u8, gameContext: ^GameContext = nil) {
	if ti.textLen < min(ti.maxLength, len(ti.buffer) - 1) && ch >= 32 && ch <= 126 {
		ti.buffer[ti.textLen] = ch
		ti.textLen += 1
		if ti.onChanged.notify != nil {
			ti.onChanged->notify(ti, UITextInputNode_GetText(ti), gameContext)
		}
	}
}

UITextInputNode_Backspace :: proc(ti: ^UITextInputNode, gameContext: ^GameContext = nil) {
	if ti.textLen > 0 {
		ti.textLen -= 1
		if ti.onChanged.notify != nil {
			ti.onChanged->notify(ti, UITextInputNode_GetText(ti), gameContext)
		}
	}
}

UITextInputNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	ti := cast(^UITextInputNode)node
	if !UI_TakesInput(ti) do return
	text_input_sync(ti)

	ti.blinkTimer += deltaTime
	mp := UI_GetMousePos(gameContext)
	if UI_IsBlockedByActiveDropdown(gameContext, ti, mp) {
		ti.hovered = false
		return
	}

	rect := UI_GetElementRect(&ti.ui)
	lw := ti.labelWidth if ti.label != "" else 0
	boxRect := rl.Rectangle{rect.x + lw, rect.y + 2, max(rect.width - lw, 60), rect.height - 4}

	ti.hovered = UI_IsMouseInViewport(gameContext) && UI_PointInRect(mp, boxRect)
	if ti.hovered && gameContext != nil && gameContext.game != nil {
		gameContext.game.uiMouseConsumed = true
	}

	if UI_IsMousePressed(gameContext) {
		ti.focused = ti.hovered
	}

	if ti.focused {
		if UI_IsKeyPressedEscape(gameContext) {
			ti.focused = false
			return
		}
		if UI_IsKeyPressedEnter(gameContext) {
			if ti.onSubmit.notify != nil {
				ti.onSubmit->notify(ti, UITextInputNode_GetText(ti), gameContext)
			}
			ti.focused = false
			return
		}
		if UI_IsKeyPressedBackspace(gameContext) {
			UITextInputNode_Backspace(ti, gameContext)
		}
		for {
			ch := UI_PopCharPressed(gameContext)
			if ch == 0 do break
			UITextInputNode_InsertChar(ti, ch, gameContext)
		}
	}
}

UITextInputNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	ti := cast(^UITextInputNode)node
	rect := UI_GetElementRect(&ti.ui)
	uilib.RenderTextInput(
		rect,
		ti.label,
		UITextInputNode_GetText(ti),
		ti.placeholder,
		ti.labelWidth,
		ti.hovered,
		ti.focused,
		ti.blinkTimer,
	)
}

UITextInputNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	ti := cast(^UITextInputNode)node
	DestroySubject(&ti.onChanged)
	DestroySubject(&ti.onSubmit)
}

// ============================================================================
// 6. UIDropdownNode (Dropdown / ComboBox)
// ============================================================================
UIDropdownNode :: struct {
	using ui: UIElement,
	label: string `gui:"true"`,
	items: [dynamic]string `gui:"true"`,
	selectedIndex: int `gui:"true" min:"0" max:"32"`,
	defaultIndex: int `gui:"true" min:"0" max:"32"`,
	labelWidth: f32 `gui:"true" min:"0" max:"300"`,
	isOpen: bool `gui:"true"`,
	hoveredItemIndex: int,
	justOpenedFrame: bool,
	onChanged: EventSubject,
	onChangedCallback: proc(dd: ^UIDropdownNode, index: int, gameContext: ^GameContext),
}

UIDropdown :: UIDropdownNode

UIDropdownNode_Create :: proc(
	scene: ^Scene,
	name: string = "Dropdown",
	label: string = "Select",
	items: []string = nil,
	selectedIndex: int = 0,
	parent: ^Node = nil,
) -> ^UIDropdownNode {
	dd := CreateNode(scene.manager, UIDropdownNode)
	dd.name = strings.clone(name, dd.allocator) // owned: callers pass temp strings too
	UIElement_Init(&dd.ui, .Dropdown, {360, 28})
	dd.label = strings.clone(label, dd.allocator)
	dd.items = make([dynamic]string, dd.allocator)
	for item in items {
		append(&dd.items, item)
	}
	dd.selectedIndex = selectedIndex
	dd.defaultIndex = selectedIndex
	dd.labelWidth = 130
	dd.isOpen = false
	dd.hoveredItemIndex = -1
	InitializeSubject(&dd.onChanged, "value_changed", dd)
	dd.update = UIDropdownNode_Update
	dd.render = UIDropdownNode_Render
	dd.onDestroy = UIDropdownNode_Destroy
	scene->addNode(dd, parent)
	return dd
}

UIDropdownNode_AddItem :: proc(dd: ^UIDropdownNode, item: string) {
	append(&dd.items, item)
}

UIDropdownNode_GetSelectedText :: proc(dd: ^UIDropdownNode) -> string {
	if dd.selectedIndex >= 0 && dd.selectedIndex < len(dd.items) {
		return dd.items[dd.selectedIndex]
	}
	return ""
}

UIDropdownNode_Select :: proc(dd: ^UIDropdownNode, index: int, gameContext: ^GameContext = nil) {
	if index >= 0 && index < len(dd.items) && dd.selectedIndex != index {
		dd.selectedIndex = index
		if dd.onChanged.notify != nil {
			dd.onChanged->notify(dd, dd.selectedIndex, gameContext)
		}
		if dd.onChangedCallback != nil {
			dd->onChangedCallback(dd.selectedIndex, gameContext)
		}
	}
}

UIDropdownNode_GetBoxRect :: proc(dd: ^UIDropdownNode) -> rl.Rectangle {
	rect := UI_GetElementRect(&dd.ui)
	lw := dd.labelWidth if dd.label != "" else 0
	return rl.Rectangle{rect.x + lw, rect.y + 2, max(rect.width - lw, 80), rect.height - 4}
}

UIDropdownNode_GetPopupRect :: proc(dd: ^UIDropdownNode) -> rl.Rectangle {
	boxRect := UIDropdownNode_GetBoxRect(dd)
	itemH: f32 = 24
	return rl.Rectangle{boxRect.x, boxRect.y + boxRect.height + 2, boxRect.width, f32(len(dd.items)) * itemH + 4}
}

UIDropdownNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	dd := cast(^UIDropdownNode)node
	if !UI_TakesInput(dd) do return

	// (justOpenedFrame: the popup took this Enter to pick an item - it ran
	// first - so it doesn't open again here, #228.)
	if dd.focused && !dd.justFocused && !dd.justOpenedFrame {
		if UI_IsKeyPressedEnter(gameContext) || UI_IsKeyPressedSpace(gameContext) {
			dd.isOpen = !dd.isOpen
			if gameContext != nil && gameContext.game != nil {
				gameContext.game.activeDropdown = dd if dd.isOpen else nil
			}
		} else if UI_IsKeyPressedEscape(gameContext) && dd.isOpen {
			dd.isOpen = false
			if gameContext != nil && gameContext.game != nil {
				gameContext.game.activeDropdown = nil
			}
		}
	}

	mp := UI_GetMousePos(gameContext)
	if UI_IsBlockedByActiveDropdown(gameContext, dd, mp) {
		dd.hovered = false
		return
	}

	boxRect := UIDropdownNode_GetBoxRect(dd)
	dd.hovered = UI_IsMouseInViewport(gameContext) && UI_PointInRect(mp, boxRect)
	if dd.hovered && gameContext != nil && gameContext.game != nil {
		gameContext.game.uiMouseConsumed = true
	}

	if dd.hovered && UI_IsMousePressed(gameContext) && !dd.justOpenedFrame {
		dd.isOpen = !dd.isOpen
		if gameContext != nil && gameContext.game != nil {
			gameContext.game.activeDropdown = dd if dd.isOpen else nil
		}
	}
	dd.justOpenedFrame = false
}

UI_UpdateActiveDropdownOverlay :: proc(gameContext: ^GameContext) {
	if gameContext == nil || gameContext.game == nil do return
	if gameContext.game.activeDropdown == nil do return

	dd := cast(^UIDropdownNode)gameContext.game.activeDropdown
	if !dd.isOpen || !dd.enabled || !dd.renderable {
		dd.isOpen = false
		gameContext.game.activeDropdown = nil
		return
	}

	// Keyboard arrow navigation and Enter selection inside dropdown popup
	if UI_IsKeyPressedUp(gameContext) {
		dd.hoveredItemIndex = max(dd.hoveredItemIndex - 1, 0)
	} else if UI_IsKeyPressedDown(gameContext) {
		dd.hoveredItemIndex = min(dd.hoveredItemIndex + 1, len(dd.items) - 1)
	}
	if (UI_IsKeyPressedEnter(gameContext) || UI_IsKeyPressedSpace(gameContext)) && dd.hoveredItemIndex >= 0 {
		UIDropdownNode_Select(dd, dd.hoveredItemIndex, gameContext)
		dd.isOpen = false
		dd.justOpenedFrame = true
		gameContext.game.activeDropdown = nil
		return
	}
	if UI_IsKeyPressedEscape(gameContext) {
		dd.isOpen = false
		gameContext.game.activeDropdown = nil
		return
	}

	mp := UI_GetMousePos(gameContext)
	popupRect := UIDropdownNode_GetPopupRect(dd)
	boxRect := UIDropdownNode_GetBoxRect(dd)
	itemH: f32 = 24

	if UI_PointInRect(mp, popupRect) {
		gameContext.game.uiMouseConsumed = true
		idx := int((mp.y - (popupRect.y + 2)) / itemH)
		if idx >= 0 && idx < len(dd.items) {
			dd.hoveredItemIndex = idx
			if UI_IsMousePressed(gameContext) {
				UIDropdownNode_Select(dd, idx, gameContext)
				dd.isOpen = false
				dd.justOpenedFrame = true
				gameContext.game.activeDropdown = nil
				return
			}
		}
	} else if UI_IsMousePressed(gameContext) && !UI_PointInRect(mp, boxRect) {
		dd.isOpen = false
		gameContext.game.activeDropdown = nil
	}
}

UIDropdownNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	dd := cast(^UIDropdownNode)node
	rect := UI_GetElementRect(&dd.ui)
	boxRect := UIDropdownNode_GetBoxRect(dd)
	uilib.RenderDropdownBox(rect, dd.label, boxRect, UIDropdownNode_GetSelectedText(dd), dd.hovered, dd.isOpen, focused = dd.focused)
}

UI_RenderActiveDropdownOverlay :: proc(gameContext: ^GameContext) {
	if gameContext == nil || gameContext.game == nil do return
	if gameContext.game.activeDropdown == nil do return

	dd := cast(^UIDropdownNode)gameContext.game.activeDropdown
	if !dd.isOpen || !dd.enabled || !dd.renderable do return

	popupRect := UIDropdownNode_GetPopupRect(dd)
	scaled := UI_BeginScaled(dd) // (with its UI-scale transform)
	uilib.RenderDropdownPopup(popupRect, dd.items[:], dd.selectedIndex, dd.hoveredItemIndex, 24)
	if scaled do UI_EndScaled()
}

UIDropdownNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	dd := cast(^UIDropdownNode)node
	if gameContext != nil && gameContext.game != nil && gameContext.game.activeDropdown == dd {
		gameContext.game.activeDropdown = nil
	}
	delete(dd.items)
	DestroySubject(&dd.onChanged)
}

// ============================================================================
// 7. UIRadioGroupNode (RadioButtons)
// ============================================================================
UIRadioGroupNode :: struct {
	using ui: UIElement,
	label: string `gui:"true"`,
	labelWidth: f32 `gui:"true" min:"0" max:"300"`,
	options: [dynamic]string `gui:"true"`,
	selectedIndex: int `gui:"true" min:"0" max:"16"`,
	defaultIndex: int `gui:"true" min:"0" max:"16"`,
	hoveredOption: int,
	horizontal: bool `gui:"true"`,
	onChanged: EventSubject,
	onChangedCallback: proc(rg: ^UIRadioGroupNode, index: int, gameContext: ^GameContext),
}

UIRadioGroup :: UIRadioGroupNode

UIRadioGroupNode_Create :: proc(
	scene: ^Scene,
	name: string = "RadioGroup",
	label: string = "Option",
	options: []string = nil,
	selectedIndex: int = 0,
	horizontal: bool = false,
	parent: ^Node = nil,
) -> ^UIRadioGroupNode {
	rg := CreateNode(scene.manager, UIRadioGroupNode)
	rg.name = strings.clone(name, rg.allocator) // owned: callers pass temp strings too
	h: f32 = 28 if horizontal else f32(max(len(options), 1)) * 26 + 4
	UIElement_Init(&rg.ui, .RadioGroup, {360, h})
	rg.label = strings.clone(label, rg.allocator)
	rg.labelWidth = 110
	rg.options = make([dynamic]string, rg.allocator)
	for opt in options {
		append(&rg.options, opt)
	}
	rg.selectedIndex = selectedIndex
	rg.defaultIndex = selectedIndex
	rg.hoveredOption = -1
	rg.horizontal = horizontal
	InitializeSubject(&rg.onChanged, "value_changed", rg)
	rg.update = UIRadioGroupNode_Update
	rg.render = UIRadioGroupNode_Render
	rg.onDestroy = UIRadioGroupNode_Destroy
	scene->addNode(rg, parent)
	return rg
}

UIRadioGroupNode_Select :: proc(rg: ^UIRadioGroupNode, index: int, gameContext: ^GameContext = nil) {
	if index >= 0 && index < len(rg.options) && rg.selectedIndex != index {
		rg.selectedIndex = index
		if rg.onChanged.notify != nil {
			rg.onChanged->notify(rg, rg.selectedIndex, gameContext)
		}
		if rg.onChangedCallback != nil {
			rg->onChangedCallback(rg.selectedIndex, gameContext)
		}
	}
}

UIRadioGroupNode_GetOptionRect :: proc(rg: ^UIRadioGroupNode, index: int) -> rl.Rectangle {
	rect := UI_GetElementRect(&rg.ui)
	return uilib.GetRadioGroupOptionRect(rect, rg.label != "", rg.labelWidth, len(rg.options), rg.horizontal, index)
}

UIRadioGroupNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	rg := cast(^UIRadioGroupNode)node
	if !UI_TakesInput(rg) do return

	// Keyboard arrow navigation when focused
	if rg.focused && !rg.justFocused && len(rg.options) > 0 {
		count := len(rg.options)
		if rg.horizontal {
			if UI_IsKeyPressedLeft(gameContext) {
				UIRadioGroupNode_Select(rg, (rg.selectedIndex - 1 + count) % count, gameContext)
			} else if UI_IsKeyPressedRight(gameContext) {
				UIRadioGroupNode_Select(rg, (rg.selectedIndex + 1) % count, gameContext)
			}
		} else {
			if UI_IsKeyPressedUp(gameContext) {
				UIRadioGroupNode_Select(rg, (rg.selectedIndex - 1 + count) % count, gameContext)
			} else if UI_IsKeyPressedDown(gameContext) {
				UIRadioGroupNode_Select(rg, (rg.selectedIndex + 1) % count, gameContext)
			}
		}
	}

	mp := UI_GetMousePos(gameContext)
	if UI_IsBlockedByActiveDropdown(gameContext, rg, mp) {
		rg.hovered = false
		rg.hoveredOption = -1
		return
	}

	rect := UI_GetElementRect(&rg.ui)
	rg.hovered = UI_IsMouseInViewport(gameContext) && UI_PointInRect(mp, rect)
	rg.hoveredOption = -1

	for _, i in rg.options {
		optRect := UIRadioGroupNode_GetOptionRect(rg, i)
		if UI_IsMouseInViewport(gameContext) && UI_PointInRect(mp, optRect) {
			rg.hoveredOption = i
			if gameContext != nil && gameContext.game != nil {
				gameContext.game.uiMouseConsumed = true
			}
			if UI_IsMousePressed(gameContext) {
				UIRadioGroupNode_Select(rg, i, gameContext)
			}
		}
	}
}

UIRadioGroupNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	rg := cast(^UIRadioGroupNode)node
	rect := UI_GetElementRect(&rg.ui)
	uilib.RenderRadioGroup(
		rect,
		rg.label,
		rg.labelWidth,
		rg.options[:],
		rg.selectedIndex,
		rg.hoveredOption,
		rg.horizontal,
		focused = rg.focused,
	)
}

UIRadioGroupNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	rg := cast(^UIRadioGroupNode)node
	delete(rg.options)
	DestroySubject(&rg.onChanged)
}

// ============================================================================
// 8. UIXYPlotNode (DearImGui / ImPlot style X/Y Plot Widget)
// ============================================================================
UIXYPlotNode :: struct {
	using ui: UIElement,
	title: string `gui:"true"`,
	xLabel: string `gui:"true"`,
	yLabel: string `gui:"true"`,
	series1Name: string `gui:"true"`,
	series2Name: string `gui:"true"`,
	points: [dynamic][2]f32,
	secondaryPoints: [dynamic][2]f32,
	xMin: f32 `gui:"true"`,
	xMax: f32 `gui:"true"`,
	yMin: f32 `gui:"true"`,
	yMax: f32 `gui:"true"`,
	autoScaleX: bool `gui:"true"`,
	autoScaleY: bool `gui:"true"`,
	showGrid: bool `gui:"true"`,
	showPoints: bool `gui:"true"`,
	showCrosshair: bool `gui:"true"`,
	lineColor: rl.Color `gui:"true"`,
	secondaryLineColor: rl.Color `gui:"true"`,
	gridColor: rl.Color `gui:"true"`,
	hoveredDataPos: [2]f32,
}

UIXYPlot :: UIXYPlotNode

UIXYPlotNode_Create :: proc(
	scene: ^Scene,
	name: string = "Plot",
	title: string = "Signal vs Time",
	size: [2]f32 = {380, 180},
	parent: ^Node = nil,
) -> ^UIXYPlotNode {
	plot := CreateNode(scene.manager, UIXYPlotNode)
	plot.name = strings.clone(name, plot.allocator) // owned: callers pass temp strings too
	UIElement_Init(&plot.ui, .XYPlot, size)
	plot.title = strings.clone(title, plot.allocator)
	plot.xLabel = "X Axis"
	plot.series1Name = "Series A"
	plot.series2Name = "Series B"
	plot.points = make([dynamic][2]f32, plot.allocator)
	plot.secondaryPoints = make([dynamic][2]f32, plot.allocator)
	plot.xMin = 0.0
	plot.xMax = 10.0
	plot.yMin = -1.5
	plot.yMax = 1.5
	plot.autoScaleX = false
	plot.autoScaleY = false
	plot.showGrid = true
	plot.showPoints = true
	plot.showCrosshair = true
	plot.lineColor = {59, 130, 246, 255}
	plot.secondaryLineColor = {245, 158, 11, 255}
	plot.gridColor = {40, 44, 55, 255}
	plot.update = UIXYPlotNode_Update
	plot.render = UIXYPlotNode_Render
	plot.onDestroy = UIXYPlotNode_Destroy
	scene->addNode(plot, parent)
	return plot
}

UIXYPlotNode_AddSecondaryPoint :: proc(plot: ^UIXYPlotNode, x, y: f32) {
	UIXYPlotNode_AddPoint(plot, x, y, isSecondary = true)
}

UIXYPlotNode_AddPoint :: proc(plot: ^UIXYPlotNode, x, y: f32, isSecondary: bool = false) {
	if isSecondary {
		append(&plot.secondaryPoints, [2]f32{x, y})
	} else {
		append(&plot.points, [2]f32{x, y})
	}
}

UIXYPlotNode_Clear :: proc(plot: ^UIXYPlotNode) {
	UIXYPlotNode_ClearPoints(plot)
}

UIXYPlotNode_ClearPoints :: proc(plot: ^UIXYPlotNode) {
	clear(&plot.points)
	clear(&plot.secondaryPoints)
}

UIXYPlotNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	plot := cast(^UIXYPlotNode)node
	if !UI_TakesInput(plot) do return

	mp := UI_GetMousePos(gameContext)
	if UI_IsBlockedByActiveDropdown(gameContext, plot, mp) {
		plot.hovered = false
		return
	}

	rect := UI_GetElementRect(&plot.ui)
	canvas := uilib.GetXYPlotCanvasRect(rect, plot.title != "")
	plot.hovered = UI_IsMouseInViewport(gameContext) && UI_PointInRect(mp, canvas)

	if plot.hovered {
		if gameContext != nil && gameContext.game != nil {
			gameContext.game.uiMouseConsumed = true
		}
		normX := clamp((mp.x - canvas.x) / max(canvas.width, 1.0), 0.0, 1.0)
		normY := clamp(1.0 - (mp.y - canvas.y) / max(canvas.height, 1.0), 0.0, 1.0)
		plot.hoveredDataPos = {
			plot.xMin + normX * (plot.xMax - plot.xMin),
			plot.yMin + normY * (plot.yMax - plot.yMin),
		}
	}
}

UIXYPlotNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	plot := cast(^UIXYPlotNode)node
	rect := UI_GetElementRect(&plot.ui)
	mp := UI_GetMousePos(gameContext)
	xMin, xMax, yMin, yMax := UIXYPlotNode_Range(plot)
	uilib.RenderXYPlot(
		rect,
		plot.title,
		plot.xLabel,
		plot.series1Name,
		plot.series2Name,
		plot.points[:],
		plot.secondaryPoints[:],
		xMin,
		xMax,
		yMin,
		yMax,
		plot.showGrid,
		plot.showPoints,
		plot.showCrosshair,
		plot.hovered,
		mp,
		plot.hoveredDataPos,
		plot.lineColor,
		plot.secondaryLineColor,
		plot.gridColor,
	)
	// The Y label, turned up the left edge (the plot draws only X's).
	if plot.yLabel != "" && rl.IsWindowReady() {
		font := uilib.GetFont(12)
		text := strings.clone_to_cstring(plot.yLabel, context.temp_allocator)
		w := rl.MeasureTextEx(font, text, 12, 1).x
		rl.DrawTextPro(font, text, {rect.x + 2, rect.y + rect.height * 0.5 + w * 0.5}, {}, -90, 12, 1, {170, 178, 196, 255})
	}
}

// UIXYPlotNode_Range: the axes - X Min / Max..., or fitted to the points
// with Auto Scale X / Y (#229).
UIXYPlotNode_Range :: proc(plot: ^UIXYPlotNode) -> (xMin, xMax, yMin, yMax: f32) {
	xMin, xMax, yMin, yMax = plot.xMin, plot.xMax, plot.yMin, plot.yMax
	if !plot.autoScaleX && !plot.autoScaleY do return
	lo, hi := [2]f32{max(f32), max(f32)}, [2]f32{-max(f32), -max(f32)}
	found := false
	for series in ([2][][2]f32{plot.points[:], plot.secondaryPoints[:]}) do for p in series {
		lo = {min(lo.x, p.x), min(lo.y, p.y)}
		hi = {max(hi.x, p.x), max(hi.y, p.y)}
		found = true
	}
	if !found do return
	pad :: proc(a, b: f32) -> (f32, f32) {
		if b - a < 0.0001 do return a - 1, b + 1
		m := (b - a) * 0.05
		return a - m, b + m
	}
	if plot.autoScaleX do xMin, xMax = pad(lo.x, hi.x)
	if plot.autoScaleY do yMin, yMax = pad(lo.y, hi.y)
	return
}

UIXYPlotNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	plot := cast(^UIXYPlotNode)node
	delete(plot.points)
	delete(plot.secondaryPoints)
}

// ============================================================================
// 9. UISeparatorNode & UIProgressBarNode
// ============================================================================
UISeparatorNode :: struct {
	using ui: UIElement,
	label: string `gui:"true"`,
	lineColor: rl.Color `gui:"true"`,
}

UISeparator :: UISeparatorNode

UISeparatorNode_Create :: proc(
	scene: ^Scene,
	name: string = "Separator",
	label: string = "",
	parent: ^Node = nil,
) -> ^UISeparatorNode {
	sep := CreateNode(scene.manager, UISeparatorNode)
	sep.name = strings.clone(name, sep.allocator) // owned: callers pass temp strings too
	UIElement_Init(&sep.ui, .Separator, {360, 18 if label != "" else 10})
	sep.label = strings.clone(label, sep.allocator)
	sep.lineColor = rl.Color{62, 68, 82, 255}
	sep.render = UISeparatorNode_Render
	scene->addNode(sep, parent)
	return sep
}

UISeparatorNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	sep := cast(^UISeparatorNode)node
	if sep.label != "" && sep.size.y < 18 do sep.size.y = 18 // (room for its label, #229)
	rect := UI_GetElementRect(&sep.ui)
	uilib.RenderSeparator(rect, sep.label, sep.lineColor)
}

UIProgressBarNode :: struct {
	using ui: UIElement,
	label: string `gui:"true"`,
	value: f32 `gui:"true" min:"0" max:"100"`,
	minValue: f32 `gui:"true" min:"0" max:"100"`,
	maxValue: f32 `gui:"true" min:"1" max:"1000"`,
	fillColor: rl.Color `gui:"true"`,
	direction: uilib.ProgressBarDirection `gui:"true"`,
	showText: bool `gui:"true"`,
}

UIProgressBar :: UIProgressBarNode

UIProgressBarNode_Create :: proc(
	scene: ^Scene,
	name: string = "ProgressBar",
	label: string = "Progress",
	value: f32 = 0.5,
	minValue: f32 = 0.0,
	maxValue: f32 = 1.0,
	parent: ^Node = nil,
	direction: uilib.ProgressBarDirection = .Horizontal,
) -> ^UIProgressBarNode {
	pb := CreateNode(scene.manager, UIProgressBarNode)
	pb.name = strings.clone(name, pb.allocator) // owned: callers pass temp strings too
	size: [2]f32 = {360, 22} if direction == .Horizontal else {28, 160}
	UIElement_Init(&pb.ui, .ProgressBar, size)
	pb.label = strings.clone(label, pb.allocator)
	pb.value = value
	pb.minValue = minValue
	pb.maxValue = maxValue
	pb.fillColor = rl.Color{16, 185, 129, 255}
	pb.direction = direction
	pb.showText = true
	pb.render = UIProgressBarNode_Render
	scene->addNode(pb, parent)
	return pb
}

UIProgressBarNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	pb := cast(^UIProgressBarNode)node
	rect := UI_GetElementRect(&pb.ui)
	uilib.RenderProgressBar(rect, pb.label, pb.value, pb.minValue, pb.maxValue, pb.fillColor, pb.direction, pb.showText)
}

// ============================================================================
// 10. UIToggleSwitchNode
// ============================================================================
UIToggleSwitchNode :: struct {
	using ui: UIElement,
	label: string `gui:"true"`,
	active: bool `gui:"true"`,
	userData: rawptr,
	onChange: proc(node: ^UIToggleSwitchNode, active: bool),
	onChanged: EventSubject, // "value_changed"(active) - #229
}
UIToggleSwitch :: UIToggleSwitchNode

UIToggleSwitchNode_Create :: proc(
	scene: ^Scene,
	name: string = "ToggleSwitch",
	label: string = "Toggle",
	active: bool = false,
	parent: ^Node = nil,
) -> ^UIToggleSwitchNode {
	ts := CreateNode(scene.manager, UIToggleSwitchNode)
	ts.name = strings.clone(name, ts.allocator) // owned: callers pass temp strings too
	UIElement_Init(&ts.ui, .ToggleSwitch, {140, 24})
	ts.label = strings.clone(label, ts.allocator)
	ts.active = active
	ts.update = UIToggleSwitchNode_Update
	ts.render = UIToggleSwitchNode_Render
	ts.onDestroy = proc(node: ^Node, gameContext: ^GameContext) {DestroySubject(&(cast(^UIToggleSwitchNode)node).onChanged)}
	InitializeSubject(&ts.onChanged, "value_changed", ts)
	scene->addNode(ts, parent)
	return ts
}

UIToggleSwitchNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	ts := cast(^UIToggleSwitchNode)node
	if !UI_TakesInput(ts) do return

	// Keyboard activation when focused
	if ts.focused && !ts.justFocused {
		if UI_IsKeyPressedEnter(gameContext) || UI_IsKeyPressedSpace(gameContext) {
			ts.active = !ts.active
			toggle_changed(ts, gameContext)
		} else if UI_IsKeyPressedLeft(gameContext) && ts.active {
			ts.active = false
			toggle_changed(ts, gameContext)
		} else if UI_IsKeyPressedRight(gameContext) && !ts.active {
			ts.active = true
			toggle_changed(ts, gameContext)
		}
	}

	rect := UI_GetElementRect(&ts.ui)
	mousePos := UI_GetMousePos(gameContext)
	ts.hovered = uilib.PointInRect(mousePos, rect)
	if ts.hovered && UI_IsMousePressed(gameContext) {
		ts.active = !ts.active
		toggle_changed(ts, gameContext)
	}
}

@(private = "file")
toggle_changed :: proc(ts: ^UIToggleSwitchNode, gameContext: ^GameContext) {
	if ts.onChange != nil do ts.onChange(ts, ts.active)
	Notify(&ts.onChanged, rawptr(ts), ts.active, gameContext)
}

UIToggleSwitchNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	ts := cast(^UIToggleSwitchNode)node
	rect := UI_GetElementRect(&ts.ui)
	uilib.RenderToggleSwitch(rect, ts.label, ts.active, ts.hovered, focused = ts.focused)
}

// ============================================================================
// 11. UIKnobNode
// ============================================================================
UIKnobNode :: struct {
	using ui: UIElement,
	label: string `gui:"true"`,
	value: f32 `gui:"true" min:"0" max:"100"`,
	minValue: f32 `gui:"true" min:"0" max:"100"`,
	maxValue: f32 `gui:"true" min:"1" max:"1000"`,
	defaultValue: f32 `gui:"true"`,
	format: string,
	isDragging: bool,
	dragStartMouse: [2]f32,
	dragStartVal: f32,
	userData: rawptr,
	onChanged: EventSubject,
	onChangedCallback: proc(node: ^UIKnobNode, value: f32, gameContext: ^GameContext),
	onChange: proc(node: ^UIKnobNode, value: f32),
}
UIKnob :: UIKnobNode

UIKnobNode_Create :: proc(
	scene: ^Scene,
	name: string = "Knob",
	label: string = "Volume",
	value: f32 = 50.0,
	minValue: f32 = 0.0,
	maxValue: f32 = 100.0,
	defaultValue: f32 = 50.0,
	format: string = "%.1f",
	parent: ^Node = nil,
) -> ^UIKnobNode {
	knob := CreateNode(scene.manager, UIKnobNode)
	knob.name = strings.clone(name, knob.allocator) // owned: callers pass temp strings too
	UIElement_Init(&knob.ui, .Knob, {64, 80})
	knob.label = strings.clone(label, knob.allocator)
	knob.value = value
	knob.minValue = minValue
	knob.maxValue = maxValue
	knob.defaultValue = defaultValue
	knob.format = format
	InitializeSubject(&knob.onChanged, "value_changed", knob)
	knob.update = UIKnobNode_Update
	knob.render = UIKnobNode_Render
	knob.onDestroy = UIKnobNode_Destroy
	scene->addNode(knob, parent)
	return knob
}

UIKnobNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	knob := cast(^UIKnobNode)node
	if !UI_TakesInput(knob) do return

	// Keyboard arrow navigation when focused
	if knob.focused && !knob.justFocused && !knob.isDragging {
		step: f32 = (knob.maxValue - knob.minValue) * (0.01 if UI_IsShiftDown(gameContext) else 0.05)
		if UI_IsKeyPressedLeft(gameContext) {
			newVal := clamp(knob.value - step, knob.minValue, knob.maxValue)
			if newVal != knob.value {
				knob.value = newVal
				if knob.onChange != nil do knob.onChange(knob, knob.value)
				if knob.onChangedCallback != nil do knob.onChangedCallback(knob, knob.value, gameContext)
				if knob.onChanged.notify != nil do knob.onChanged->notify(knob, knob.value, gameContext)
			}
		} else if UI_IsKeyPressedRight(gameContext) {
			newVal := clamp(knob.value + step, knob.minValue, knob.maxValue)
			if newVal != knob.value {
				knob.value = newVal
				if knob.onChange != nil do knob.onChange(knob, knob.value)
				if knob.onChangedCallback != nil do knob.onChangedCallback(knob, knob.value, gameContext)
				if knob.onChanged.notify != nil do knob.onChanged->notify(knob, knob.value, gameContext)
			}
		}
	}

	rect := UI_GetElementRect(&knob.ui)
	mousePos := UI_GetMousePos(gameContext)
	knob.hovered = uilib.PointInRect(mousePos, rect)
	if knob.hovered && UI_IsRightMousePressed(gameContext) && knob.value != knob.defaultValue {
		// Right-click: back to Default Value (#229), as the slider.
		knob.value = knob.defaultValue
		if knob.onChangedCallback != nil do knob.onChangedCallback(knob, knob.value, gameContext)
		if knob.onChanged.notify != nil do knob.onChanged->notify(knob, knob.value, gameContext)
	}

	if knob.hovered && UI_IsMousePressed(gameContext) {
		knob.isDragging = true
		knob.dragStartMouse = mousePos
		knob.dragStartVal = knob.value
	}

	if knob.isDragging {
		if rl.IsMouseButtonReleased(.LEFT) {
			knob.isDragging = false
		} else {
			dy := knob.dragStartMouse.y - mousePos.y
			fine := UI_IsShiftDown(gameContext)
			speed: f32 = 0.005 if fine else 0.02
			vRange := knob.maxValue - knob.minValue
			newVal := clamp(knob.dragStartVal + dy * speed * vRange, knob.minValue, knob.maxValue)
			if newVal != knob.value {
				knob.value = newVal
				if knob.onChange != nil do knob.onChange(knob, knob.value)
				if knob.onChangedCallback != nil do knob.onChangedCallback(knob, knob.value, gameContext)
				if knob.onChanged.notify != nil do knob.onChanged->notify(knob, knob.value, gameContext)
			}
		}
	}
}

UIKnobNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	knob := cast(^UIKnobNode)node
	rect := UI_GetElementRect(&knob.ui)
	uilib.RenderKnob(rect, knob.label, knob.value, knob.minValue, knob.maxValue, knob.format, knob.hovered, knob.isDragging, focused = knob.focused)
}

UIKnobNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	knob := cast(^UIKnobNode)node
	DestroySubject(&knob.onChanged)
}

// ============================================================================
// 12. UIListViewNode
// ============================================================================
UIListViewNode :: struct {
	using ui: UIElement,
	items: [dynamic]string `gui:"true"`,
	selectedIndex: int `gui:"true" min:"-1" max:"100"`,
	scroll: [2]f32,
	itemHeight: f32 `gui:"true" min:"16" max:"48"`,
	userData: rawptr,
	onSelect: proc(node: ^UIListViewNode, index: int),
	onSelected: EventSubject, // "selected"(index) - #229
}
UIListView :: UIListViewNode

UIListViewNode_Create :: proc(
	scene: ^Scene,
	name: string = "ListView",
	items: []string,
	size: [2]f32 = {200, 160},
	parent: ^Node = nil,
) -> ^UIListViewNode {
	lv := CreateNode(scene.manager, UIListViewNode)
	lv.name = strings.clone(name, lv.allocator) // owned: callers pass temp strings too
	UIElement_Init(&lv.ui, .ListView, size)
	for it in items do append(&lv.items, it)
	lv.selectedIndex = 0 if len(items) > 0 else -1
	lv.scroll = {0, 0}
	lv.itemHeight = 24
	lv.onDestroy = UIListViewNode_Destroy
	lv.update = UIListViewNode_Update
	lv.render = UIListViewNode_Render
	InitializeSubject(&lv.onSelected, "selected", lv)
	scene->addNode(lv, parent)
	return lv
}

UIListViewNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	lv := cast(^UIListViewNode)node
	delete(lv.items)
	DestroySubject(&lv.onSelected)
}

// list_select: the List View's selection changed (its callback and signal),
// scrolled into view.
@(private = "file")
list_select :: proc(lv: ^UIListViewNode, idx: int, gameContext: ^GameContext) {
	lv.selectedIndex = idx
	if lv.onSelect != nil do lv.onSelect(lv, idx)
	Notify(&lv.onSelected, rawptr(lv), idx, gameContext)
	h := max(lv.itemHeight, 1)
	view := max(math.floor(UI_GetElementRect(&lv.ui).height / h), 1) * h
	if f32(idx) * h < lv.scroll.y do lv.scroll.y = f32(idx) * h
	if f32(idx + 1) * h > lv.scroll.y + view do lv.scroll.y = f32(idx + 1) * h - view
}

UIListViewNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	lv := cast(^UIListViewNode)node
	if !UI_TakesInput(lv) do return

	// Keyboard arrow navigation when focused
	if lv.focused && !lv.justFocused && len(lv.items) > 0 {
		if UI_IsKeyPressedUp(gameContext) {
			newIdx := max(lv.selectedIndex - 1, 0)
			if newIdx != lv.selectedIndex do list_select(lv, newIdx, gameContext)
		} else if UI_IsKeyPressedDown(gameContext) {
			newIdx := min(lv.selectedIndex + 1, len(lv.items) - 1)
			if newIdx != lv.selectedIndex do list_select(lv, newIdx, gameContext)
		} else if (UI_IsKeyPressedEnter(gameContext) || UI_IsKeyPressedSpace(gameContext)) && lv.selectedIndex >= 0 {
			list_select(lv, lv.selectedIndex, gameContext)
		}
	}

	rect := UI_GetElementRect(&lv.ui)
	mousePos := UI_GetMousePos(gameContext)
	lv.hovered = uilib.PointInRect(mousePos, rect)
	// The wheel scrolls it a row at a time (#229).
	h := max(lv.itemHeight, 1)
	maxScroll := max(f32(len(lv.items)) * h - math.floor(rect.height / h) * h, 0)
	if lv.hovered {
		if w := UI_GetMouseWheel(gameContext); w != 0 do lv.scroll.y -= math.sign(w) * h
	}
	lv.scroll.y = clamp(lv.scroll.y, 0, maxScroll)
	if lv.hovered && UI_IsMousePressed(gameContext) {
		relY := mousePos.y - rect.y + lv.scroll.y
		idx := int(relY / h)
		if idx >= 0 && idx < len(lv.items) && lv.selectedIndex != idx do list_select(lv, idx, gameContext)
	}
}

UIListViewNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	lv := cast(^UIListViewNode)node
	rect := UI_GetElementRect(&lv.ui)
	// Only the rows that fit, from the first scrolled to (it doesn't clip).
	h := max(lv.itemHeight, 1)
	first := clamp(int(lv.scroll.y / h + 0.5), 0, len(lv.items))
	last := clamp(first + int(rect.height / h), first, len(lv.items))
	uilib.RenderListView(rect, lv.items[first:last], lv.selectedIndex - first, -1, 0, h, focused = lv.focused)
}

// ============================================================================
// 13. UITreeViewNode
// ============================================================================
UITreeViewNode :: struct {
	using ui: UIElement,
	items: [dynamic]uilib.TreeViewItem,
	selectedId: int `gui:"true" min:"-1" max:"1000"`,
	scroll: [2]f32,
	itemHeight: f32 `gui:"true" min:"16" max:"48"`,
	onSelect: proc(node: ^UITreeViewNode, id: int),
}
UITreeView :: UITreeViewNode

UITreeViewNode_Create :: proc(
	scene: ^Scene,
	name: string = "TreeView",
	size: [2]f32 = {220, 200},
	parent: ^Node = nil,
) -> ^UITreeViewNode {
	tv := CreateNode(scene.manager, UITreeViewNode)
	tv.name = strings.clone(name, tv.allocator) // owned: callers pass temp strings too
	UIElement_Init(&tv.ui, .TreeView, size)
	tv.selectedId = -1
	tv.scroll = {0, 0}
	tv.itemHeight = 22
	tv.onDestroy = UITreeViewNode_Destroy
	tv.update = UITreeViewNode_Update
	tv.render = UITreeViewNode_Render
	scene->addNode(tv, parent)
	return tv
}

UITreeViewNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	tv := cast(^UITreeViewNode)node
	delete(tv.items)
}

UITreeViewNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	tv := cast(^UITreeViewNode)node
	if !UI_TakesInput(tv) do return

	// Keyboard arrow navigation when focused
	if tv.focused && len(tv.items) > 0 {
		curIdx := -1
		for i in 0..<len(tv.items) {
			if tv.items[i].id == tv.selectedId {
				curIdx = i
				break
			}
		}
		// Up / Down move between the shown rows.
		vis := tree_visible(tv)
		row := -1
		for v, r in vis do if v == curIdx do row = r
		if UI_IsKeyPressedUp(gameContext) {
			newIdx := vis[max(row - 1, 0)]
			tv.selectedId = tv.items[newIdx].id
			if tv.onSelect != nil do tv.onSelect(tv, tv.selectedId)
		} else if UI_IsKeyPressedDown(gameContext) {
			newIdx := vis[min(row + 1, len(vis) - 1)]
			tv.selectedId = tv.items[newIdx].id
			if tv.onSelect != nil do tv.onSelect(tv, tv.selectedId)
		} else if curIdx >= 0 {
			if UI_IsKeyPressedLeft(gameContext) {
				tv.items[curIdx].isCollapsed = true
			} else if UI_IsKeyPressedRight(gameContext) {
				tv.items[curIdx].isCollapsed = false
			} else if UI_IsKeyPressedEnter(gameContext) || UI_IsKeyPressedSpace(gameContext) {
				if tv.items[curIdx].hasChildren {
					tv.items[curIdx].isCollapsed = !tv.items[curIdx].isCollapsed
				}
				if tv.onSelect != nil do tv.onSelect(tv, tv.selectedId)
			}
		}
	}

	rect := UI_GetElementRect(&tv.ui)
	mousePos := UI_GetMousePos(gameContext)
	tv.hovered = uilib.PointInRect(mousePos, rect)

	if tv.hovered && UI_IsMousePressed(gameContext) {
		for i, row in tree_visible(tv) {
			item := &tv.items[i]
			itemY := rect.y + tv.scroll.y + f32(row) * tv.itemHeight
			itemRect := rl.Rectangle{rect.x, itemY, rect.width, tv.itemHeight}

			if uilib.PointInRect(mousePos, itemRect) {
				indent := f32(item.depth) * 16.0
				if item.hasChildren {
					boxRect := rl.Rectangle{rect.x + indent + 2, itemY + (tv.itemHeight - 14) * 0.5, 14, 14}
					if uilib.PointInRect(mousePos, boxRect) {
						item.isCollapsed = !item.isCollapsed
						break
					}
				}
				if tv.selectedId != item.id {
					tv.selectedId = item.id
					if tv.onSelect != nil do tv.onSelect(tv, item.id)
				}
				break
			}
		}
	}
}

// tree_visible: the rows shown - items whose parents are all expanded (#229).
@(private = "file")
tree_visible :: proc(tv: ^UITreeViewNode) -> []int {
	out := make([dynamic]int, context.temp_allocator)
	hideBelow := max(int) // depth under a collapsed item
	for it, i in tv.items {
		if it.depth > hideBelow do continue
		hideBelow = max(int)
		append(&out, i)
		if it.hasChildren && it.isCollapsed do hideBelow = it.depth
	}
	return out[:]
}

UITreeViewNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	tv := cast(^UITreeViewNode)node
	rect := UI_GetElementRect(&tv.ui)
	uilib.BeginClipRect(rect)
	defer uilib.EndClipRect()

	rl.DrawRectangleRec(rect, rl.Color{24, 26, 32, 240})
	borderColor := rl.Color{110, 168, 254, 255} if tv.focused else rl.Color{55, 60, 75, 255}
	rl.DrawRectangleLinesEx(rect, 1, borderColor)

	if tv.focused && !tv.justFocused {
		uilib.RenderFocusRing(rect, true, 2.0)
	}

	for i, row in tree_visible(tv) {
		item := &tv.items[i]
		item.isSelected = (item.id == tv.selectedId)
		itemY := rect.y + tv.scroll.y + f32(row) * tv.itemHeight
		itemRect := rl.Rectangle{rect.x, itemY, rect.width, tv.itemHeight}
		itemFocused := tv.focused && item.isSelected
		uilib.RenderTreeNode(itemRect, item^, focused = itemFocused)
	}
}

// ============================================================================
// 14. UIVolumeFaderNode (Console-Grade Log-Taper Fader Node)
// ============================================================================
UIVolumeFaderNode :: struct {
	using ui: UIElement,
	label: string `gui:"true"`,
	valueDb: f32 `gui:"true" min:"-60" max:"6"`,
	minDb: f32 `gui:"true" min:"-100" max:"0"`,
	maxDb: f32 `gui:"true" min:"0" max:"24"`,
	defaultDb: f32 `gui:"true" min:"-60" max:"6"`,
	isDragging: bool,
	fineMode: bool,
	dragStartMouseY: f32,
	dragStartValDb: f32,
	userData: rawptr,
	onChanged: EventSubject,
	onChangedCallback: proc(node: ^UIVolumeFaderNode, valDb: f32, gameContext: ^GameContext),
	onChange: proc(node: ^UIVolumeFaderNode, valDb: f32),
}
UIVolumeFader :: UIVolumeFaderNode

UIVolumeFaderNode_Create :: proc(
	scene: ^Scene,
	name: string = "VolumeFader",
	label: string = "Master",
	valueDb: f32 = 0.0,
	minDb: f32 = -60.0,
	maxDb: f32 = 6.0,
	defaultDb: f32 = 0.0,
	parent: ^Node = nil,
) -> ^UIVolumeFaderNode {
	fader := CreateNode(scene.manager, UIVolumeFaderNode)
	fader.name = strings.clone(name, fader.allocator) // owned: callers pass temp strings too
	UIElement_Init(&fader.ui, .VolumeFader, {96, 320})
	fader.label = strings.clone(label, fader.allocator)
	fader.valueDb = valueDb
	fader.minDb = minDb
	fader.maxDb = maxDb
	fader.defaultDb = defaultDb
	InitializeSubject(&fader.onChanged, "value_changed", fader)
	fader.update = UIVolumeFaderNode_Update
	fader.render = UIVolumeFaderNode_Render
	fader.onDestroy = UIVolumeFaderNode_Destroy
	scene->addNode(fader, parent)
	return fader
}

UIVolumeFaderNode_SetValue :: proc(fader: ^UIVolumeFaderNode, valDb: f32, gameContext: ^GameContext) {
	clamped := clamp(valDb, fader.minDb, fader.maxDb)
	if abs(clamped - fader.valueDb) > 0.0001 {
		fader.valueDb = clamped
		Notify(&fader.onChanged, rawptr(fader), fader.valueDb, gameContext)
		if fader.onChangedCallback != nil do fader.onChangedCallback(fader, fader.valueDb, gameContext)
		if fader.onChange != nil do fader.onChange(fader, fader.valueDb)
	}
}

UIVolumeFaderNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	fader := cast(^UIVolumeFaderNode)node
	if !UI_TakesInput(fader) do return

	rect := UI_GetElementRect(&fader.ui)
	mp := UI_GetMousePos(gameContext)
	fader.hovered = UI_PointInRect(mp, rect) && !UI_IsBlockedByActiveDropdown(gameContext, nil, mp)

	shiftHeld := UI_IsShiftDown(gameContext)
	fader.fineMode = shiftHeld && (fader.focused || fader.isDragging)

	slotTop := rect.y + 26
	slotBottom := rect.y + rect.height - 30
	slotH := max(slotBottom - slotTop, 40.0)

	// Keyboard arrow navigation when focused
	if fader.focused && !fader.justFocused && !fader.isDragging {
		step: f32 = 0.1 if fader.fineMode else 0.5
		if UI_IsKeyPressedUp(gameContext) {
			UIVolumeFaderNode_SetValue(fader, fader.valueDb + step, gameContext)
		} else if UI_IsKeyPressedDown(gameContext) {
			UIVolumeFaderNode_SetValue(fader, fader.valueDb - step, gameContext)
		}
	}

	// Mouse interaction
	if fader.hovered && UI_IsRightMousePressed(gameContext) {
		UIVolumeFaderNode_SetValue(fader, fader.defaultDb, gameContext)
		return
	}

	if fader.hovered && UI_IsMousePressed(gameContext) {
		fader.isDragging = true
		fader.dragStartMouseY = mp.y
		fader.dragStartValDb = fader.valueDb
		if !fader.fineMode {
			norm := clamp((slotBottom - mp.y) / slotH, 0.0, 1.0)
			newDb := uilib.FaderNormToDb(norm, fader.minDb, fader.maxDb)
			UIVolumeFaderNode_SetValue(fader, newDb, gameContext)
		}
	}

	if fader.isDragging {
		if !UI_IsMouseDown(gameContext) || UI_IsMouseReleased(gameContext) {
			fader.isDragging = false
		} else {
			if fader.fineMode {
				dy := fader.dragStartMouseY - mp.y
				deltaDb := (dy / slotH) * (fader.maxDb - fader.minDb) * 0.15
				UIVolumeFaderNode_SetValue(fader, fader.dragStartValDb + deltaDb, gameContext)
			} else {
				norm := clamp((slotBottom - mp.y) / slotH, 0.0, 1.0)
				newDb := uilib.FaderNormToDb(norm, fader.minDb, fader.maxDb)
				UIVolumeFaderNode_SetValue(fader, newDb, gameContext)
			}
		}
	}
}

UIVolumeFaderNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	fader := cast(^UIVolumeFaderNode)node
	rect := UI_GetElementRect(&fader.ui)
	uilib.RenderVolumeFader(
		rect,
		fader.label,
		fader.valueDb,
		fader.minDb,
		fader.maxDb,
		fader.defaultDb,
		fader.hovered,
		fader.isDragging,
		focused = fader.focused,
		fineMode = fader.fineMode,
	)
}

UIVolumeFaderNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	fader := cast(^UIVolumeFaderNode)node
	DestroySubject(&fader.onChanged)
}

// ============================================================================
// 15. UIVolumeMeterNode (Segmented LED Ladder VU/Peak Meter Node)
// ============================================================================
UIVolumeMeterNode :: struct {
	using ui: UIElement,
	label: string `gui:"true"`,
	levelL: f32 `gui:"true" min:"-60" max:"3"`,
	levelR: f32 `gui:"true" min:"-120" max:"3"`,
	minDb: f32 `gui:"true" min:"-100" max:"0"`,
	maxDb: f32 `gui:"true" min:"0" max:"12"`,
	orientation: uilib.MeterOrientation `gui:"true"`,
	state: uilib.VolumeMeterState,
	userData: rawptr,
}
UIVolumeMeter :: UIVolumeMeterNode

UIVolumeMeterNode_Create :: proc(
	scene: ^Scene,
	name: string = "VolumeMeter",
	label: string = "VU",
	levelL: f32 = -60.0,
	levelR: f32 = -120.0,
	orientation: uilib.MeterOrientation = .Vertical,
	size: [2]f32 = {120, 320},
	parent: ^Node = nil,
) -> ^UIVolumeMeterNode {
	meter := CreateNode(scene.manager, UIVolumeMeterNode)
	meter.name = strings.clone(name, meter.allocator) // owned: callers pass temp strings too
	UIElement_Init(&meter.ui, .VolumeMeter, size)
	meter.label = strings.clone(label, meter.allocator)
	meter.levelL = levelL
	meter.levelR = levelR
	meter.minDb = -60.0
	meter.maxDb = 3.0
	meter.orientation = orientation
	meter.update = UIVolumeMeterNode_Update
	meter.render = UIVolumeMeterNode_Render
	meter.onDestroy = UIVolumeMeterNode_Destroy
	scene->addNode(meter, parent)
	return meter
}

UIVolumeMeterNode_SetLevels :: proc(meter: ^UIVolumeMeterNode, levelL: f32, levelR: f32 = -120.0) {
	meter.levelL = levelL
	meter.levelR = levelR
}

UIVolumeMeterNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	meter := cast(^UIVolumeMeterNode)node
	if !meter.enabled do return

	dt := deltaTime if deltaTime > 0 else 0.016
	st := &meter.state
	// A clip lights for 1.5 s (the meter set it without a hold, #229).
	span := max(meter.maxDb - meter.minDb, 0.001)
	if (meter.levelL - meter.minDb) / span >= 0.98 {st.clipL = true; st.clipHoldTimerL = 1.5}
	if (meter.levelR - meter.minDb) / span >= 0.98 {st.clipR = true; st.clipHoldTimerR = 1.5}
	if st.peakHoldTimerL > 0 {
		st.peakHoldTimerL -= dt
	} else {
		st.peakL = max(st.peakL - dt * 0.45, 0.0)
	}
	if st.peakHoldTimerR > 0 {
		st.peakHoldTimerR -= dt
	} else {
		st.peakR = max(st.peakR - dt * 0.45, 0.0)
	}
	if st.clipL {
		st.clipHoldTimerL -= dt
		if st.clipHoldTimerL <= 0 do st.clipL = false
	}
	if st.clipR {
		st.clipHoldTimerR -= dt
		if st.clipHoldTimerR <= 0 do st.clipR = false
	}
}

UIVolumeMeterNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	meter := cast(^UIVolumeMeterNode)node
	rect := UI_GetElementRect(&meter.ui)
	uilib.RenderVolumeMeter(
		rect,
		meter.label,
		meter.levelL,
		meter.levelR,
		&meter.state,
		meter.orientation,
		meter.minDb,
		meter.maxDb,
	)
}

UIVolumeMeterNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	// Stateless cleanup
}

// ============================================================================
// 16. UINotchedSliderNode (Discrete Detented Slider Node)
// ============================================================================
UINotchedSliderNode :: struct {
	using ui: UIElement,
	label: string `gui:"true"`,
	value: f32 `gui:"true"`,
	minValue: f32 `gui:"true"`,
	maxValue: f32 `gui:"true"`,
	numNotches: int `gui:"true" min:"2" max:"32"`,
	notchLabels: [dynamic]string `gui:"true"`,
	snapToNotches: bool `gui:"true"`,
	orientation: uilib.SliderOrientation `gui:"true"`,
	isDragging: bool,
	fineMode: bool,
	dragStartMouse: [2]f32,
	dragStartVal: f32,
	userData: rawptr,
	onChanged: EventSubject,
	onChangedCallback: proc(node: ^UINotchedSliderNode, val: f32, notchIdx: int, gameContext: ^GameContext),
	onChange: proc(node: ^UINotchedSliderNode, val: f32, notchIdx: int),
}
UINotchedSlider :: UINotchedSliderNode

UINotchedSliderNode_Create :: proc(
	scene: ^Scene,
	name: string = "NotchedSlider",
	label: string = "Detents",
	value: f32 = 0.0,
	minValue: f32 = 0.0,
	maxValue: f32 = 4.0,
	numNotches: int = 5,
	notchLabels: []string = nil,
	snapToNotches: bool = true,
	orientation: uilib.SliderOrientation = .Horizontal,
	size: [2]f32 = {360, 48},
	parent: ^Node = nil,
) -> ^UINotchedSliderNode {
	ns := CreateNode(scene.manager, UINotchedSliderNode)
	ns.name = strings.clone(name, ns.allocator) // owned: callers pass temp strings too
	UIElement_Init(&ns.ui, .NotchedSlider, size)
	ns.label = strings.clone(label, ns.allocator)
	ns.value = value
	ns.minValue = minValue
	ns.maxValue = maxValue
	ns.numNotches = max(numNotches, 2)
	ns.snapToNotches = snapToNotches
	ns.orientation = orientation
	for l in notchLabels {
		append(&ns.notchLabels, l)
	}
	InitializeSubject(&ns.onChanged, "value_changed", ns)
	ns.update = UINotchedSliderNode_Update
	ns.render = UINotchedSliderNode_Render
	ns.onDestroy = UINotchedSliderNode_Destroy
	scene->addNode(ns, parent)
	return ns
}

UINotchedSliderNode_SetValue :: proc(ns: ^UINotchedSliderNode, val: f32, gameContext: ^GameContext) {
	clamped := clamp(val, ns.minValue, ns.maxValue)
	if abs(clamped - ns.value) > 0.0001 {
		ns.value = clamped
		notches := max(ns.numNotches, 2)
		curNorm := clamp((ns.value - ns.minValue) / max(ns.maxValue - ns.minValue, 0.0001), 0.0, 1.0)
		notchIdx := int(math.round(curNorm * f32(notches - 1)))
		Notify(&ns.onChanged, rawptr(ns), ns.value, gameContext)
		if ns.onChangedCallback != nil do ns.onChangedCallback(ns, ns.value, notchIdx, gameContext)
		if ns.onChange != nil do ns.onChange(ns, ns.value, notchIdx)
	}
}

UINotchedSliderNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	ns := cast(^UINotchedSliderNode)node
	if !UI_TakesInput(ns) do return

	rect := UI_GetElementRect(&ns.ui)
	mp := UI_GetMousePos(gameContext)
	ns.hovered = UI_PointInRect(mp, rect) && !UI_IsBlockedByActiveDropdown(gameContext, nil, mp)

	shiftHeld := UI_IsShiftDown(gameContext)
	ns.fineMode = shiftHeld && (ns.focused || ns.isDragging)

	notches := max(ns.numNotches, 2)
	stepSize := (ns.maxValue - ns.minValue) / f32(notches - 1)

	// Keyboard arrow navigation when focused
	if ns.focused && !ns.justFocused && !ns.isDragging {
		if ns.snapToNotches && !ns.fineMode {
			curNorm := clamp((ns.value - ns.minValue) / max(ns.maxValue - ns.minValue, 0.0001), 0.0, 1.0)
			curNotch := int(math.round(curNorm * f32(notches - 1)))
			if (ns.orientation == .Horizontal && UI_IsKeyPressedLeft(gameContext)) || (ns.orientation == .Vertical && UI_IsKeyPressedDown(gameContext)) {
				newNotch := max(curNotch - 1, 0)
				UINotchedSliderNode_SetValue(ns, ns.minValue + f32(newNotch) * stepSize, gameContext)
			} else if (ns.orientation == .Horizontal && UI_IsKeyPressedRight(gameContext)) || (ns.orientation == .Vertical && UI_IsKeyPressedUp(gameContext)) {
				newNotch := min(curNotch + 1, notches - 1)
				UINotchedSliderNode_SetValue(ns, ns.minValue + f32(newNotch) * stepSize, gameContext)
			}
		} else {
			fineStep := stepSize * (0.05 if ns.fineMode else 0.20)
			if (ns.orientation == .Horizontal && UI_IsKeyPressedLeft(gameContext)) || (ns.orientation == .Vertical && UI_IsKeyPressedDown(gameContext)) {
				UINotchedSliderNode_SetValue(ns, ns.value - fineStep, gameContext)
			} else if (ns.orientation == .Horizontal && UI_IsKeyPressedRight(gameContext)) || (ns.orientation == .Vertical && UI_IsKeyPressedUp(gameContext)) {
				UINotchedSliderNode_SetValue(ns, ns.value + fineStep, gameContext)
			}
		}
	}

	// Mouse Drag
	if ns.hovered && UI_IsMousePressed(gameContext) {
		ns.isDragging = true
		ns.dragStartMouse = mp
		ns.dragStartVal = ns.value
	}

	if ns.isDragging {
		if !UI_IsMouseDown(gameContext) || UI_IsMouseReleased(gameContext) {
			ns.isDragging = false
		} else {
			norm: f32
			if ns.orientation == .Horizontal {
				trackL := rect.x + 24
				trackR := rect.x + rect.width - 24
				trackW := max(trackR - trackL, 10.0)
				norm = clamp((mp.x - trackL) / trackW, 0.0, 1.0)
			} else {
				trackT := rect.y + 24
				trackB := rect.y + rect.height - 24
				trackH := max(trackB - trackT, 10.0)
				norm = clamp((trackB - mp.y) / trackH, 0.0, 1.0)
			}

			if ns.snapToNotches && !ns.fineMode {
				nearestIdx := math.round(norm * f32(notches - 1))
				norm = nearestIdx / f32(notches - 1)
			}
			newVal := ns.minValue + norm * (ns.maxValue - ns.minValue)
			UINotchedSliderNode_SetValue(ns, newVal, gameContext)
		}
	}
}

UINotchedSliderNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	ns := cast(^UINotchedSliderNode)node
	rect := UI_GetElementRect(&ns.ui)
	notches := max(ns.numNotches, 2)
	curNorm := clamp((ns.value - ns.minValue) / max(ns.maxValue - ns.minValue, 0.0001), 0.0, 1.0)
	snapped := int(math.round(curNorm * f32(notches - 1))) if ns.snapToNotches else -1
	uilib.RenderNotchedSlider(
		rect,
		ns.label,
		ns.value,
		ns.minValue,
		ns.maxValue,
		ns.numNotches,
		ns.notchLabels[:],
		ns.orientation,
		ns.hovered,
		ns.isDragging,
		ns.focused,
		ns.fineMode,
		snapped,
	)
}

UINotchedSliderNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	ns := cast(^UINotchedSliderNode)node
	delete(ns.notchLabels)
	DestroySubject(&ns.onChanged)
}

// ============================================================================
// 17. UIUnorderedListNode (HTML <ul> Unordered List Node)
// ============================================================================
UIUnorderedListNode :: struct {
	using ui: UIElement,
	items: [dynamic]uilib.ListItem,
	selectedIndex: int `gui:"true"`,
	defaultBullet: uilib.BulletStyle `gui:"true"`,
	itemHeight: f32 `gui:"true" min:"16" max:"48"`,
	scroll: [2]f32,
	userData: rawptr,
	onSelect: EventSubject,
	onSelectCallback: proc(node: ^UIUnorderedListNode, idx: int, gameContext: ^GameContext),
	onSelectItem: proc(node: ^UIUnorderedListNode, idx: int),
}
UIUnorderedList :: UIUnorderedListNode

UIUnorderedListNode_Create :: proc(
	scene: ^Scene,
	name: string = "UnorderedList",
	items: []uilib.ListItem = nil,
	defaultBullet: uilib.BulletStyle = .Disc,
	size: [2]f32 = {320, 220},
	parent: ^Node = nil,
) -> ^UIUnorderedListNode {
	ul := CreateNode(scene.manager, UIUnorderedListNode)
	ul.name = strings.clone(name, ul.allocator) // owned: callers pass temp strings too
	UIElement_Init(&ul.ui, .UnorderedList, size)
	ul.defaultBullet = defaultBullet
	ul.itemHeight = 24.0
	ul.selectedIndex = 0
	for it in items {
		append(&ul.items, it)
	}
	InitializeSubject(&ul.onSelect, "selected", ul)
	ul.update = UIUnorderedListNode_Update
	ul.render = UIUnorderedListNode_Render
	ul.onDestroy = UIUnorderedListNode_Destroy
	scene->addNode(ul, parent)
	return ul
}

UIUnorderedListNode_AddItem :: proc(ul: ^UIUnorderedListNode, item: uilib.ListItem) {
	append(&ul.items, item)
}

UIUnorderedListNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	ul := cast(^UIUnorderedListNode)node
	if !UI_TakesInput(ul) do return

	rect := UI_GetElementRect(&ul.ui)
	mp := UI_GetMousePos(gameContext)
	ul.hovered = UI_PointInRect(mp, rect) && !UI_IsBlockedByActiveDropdown(gameContext, nil, mp)

	// Keyboard arrow navigation when focused
	if ul.focused && !ul.justFocused && len(ul.items) > 0 {
		if UI_IsKeyPressedUp(gameContext) {
			newIdx := max(ul.selectedIndex - 1, 0)
			if newIdx != ul.selectedIndex {
				ul.selectedIndex = newIdx
				Notify(&ul.onSelect, rawptr(ul), ul.selectedIndex, gameContext)
				if ul.onSelectCallback != nil do ul.onSelectCallback(ul, ul.selectedIndex, gameContext)
				if ul.onSelectItem != nil do ul.onSelectItem(ul, ul.selectedIndex)
			}
		} else if UI_IsKeyPressedDown(gameContext) {
			newIdx := min(ul.selectedIndex + 1, len(ul.items) - 1)
			if newIdx != ul.selectedIndex {
				ul.selectedIndex = newIdx
				Notify(&ul.onSelect, rawptr(ul), ul.selectedIndex, gameContext)
				if ul.onSelectCallback != nil do ul.onSelectCallback(ul, ul.selectedIndex, gameContext)
				if ul.onSelectItem != nil do ul.onSelectItem(ul, ul.selectedIndex)
			}
		}
	}

	// Mouse click selection
	if ul.hovered && UI_IsMousePressed(gameContext) {
		for i in 0..<len(ul.items) {
			rowY := rect.y + ul.scroll.y + 6.0 + f32(i) * ul.itemHeight
			rowRect := rl.Rectangle{rect.x + 4, rowY, rect.width - 8, ul.itemHeight}
			if UI_PointInRect(mp, rowRect) {
				if ul.selectedIndex != i {
					ul.selectedIndex = i
					Notify(&ul.onSelect, rawptr(ul), ul.selectedIndex, gameContext)
					if ul.onSelectCallback != nil do ul.onSelectCallback(ul, i, gameContext)
					if ul.onSelectItem != nil do ul.onSelectItem(ul, i)
				}
				break
			}
		}
	}
}

UIUnorderedListNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	ul := cast(^UIUnorderedListNode)node
	rect := UI_GetElementRect(&ul.ui)
	scr := rl.Vector2{ul.scroll.x, ul.scroll.y}
	uilib.GuiUnorderedList(
		rect,
		ul.items[:],
		&ul.selectedIndex,
		&scr,
		ul.defaultBullet,
		ul.itemHeight,
		idKey = uintptr(rawptr(ul)),
	)
	ul.scroll = {scr.x, scr.y}
}

UIUnorderedListNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	ul := cast(^UIUnorderedListNode)node
	delete(ul.items)
	DestroySubject(&ul.onSelect)
}

// ============================================================================
// 18. UIOrderedListNode (HTML <ol> Ordered List Node)
// ============================================================================
UIOrderedListNode :: struct {
	using ui: UIElement,
	items: [dynamic]uilib.ListItem,
	selectedIndex: int `gui:"true"`,
	numbering: uilib.NumberingStyle `gui:"true"`,
	startNumber: int `gui:"true" min:"1" max:"100"`,
	itemHeight: f32 `gui:"true" min:"16" max:"48"`,
	scroll: [2]f32,
	userData: rawptr,
	onSelect: EventSubject,
	onSelectCallback: proc(node: ^UIOrderedListNode, idx: int, gameContext: ^GameContext),
	onSelectItem: proc(node: ^UIOrderedListNode, idx: int),
}
UIOrderedList :: UIOrderedListNode

UIOrderedListNode_Create :: proc(
	scene: ^Scene,
	name: string = "OrderedList",
	items: []uilib.ListItem = nil,
	numbering: uilib.NumberingStyle = .Decimal,
	startNumber: int = 1,
	size: [2]f32 = {320, 220},
	parent: ^Node = nil,
) -> ^UIOrderedListNode {
	ol := CreateNode(scene.manager, UIOrderedListNode)
	ol.name = strings.clone(name, ol.allocator) // owned: callers pass temp strings too
	UIElement_Init(&ol.ui, .OrderedList, size)
	ol.numbering = numbering
	ol.startNumber = startNumber
	ol.itemHeight = 24.0
	ol.selectedIndex = 0
	for it in items {
		append(&ol.items, it)
	}
	InitializeSubject(&ol.onSelect, "selected", ol)
	ol.update = UIOrderedListNode_Update
	ol.render = UIOrderedListNode_Render
	ol.onDestroy = UIOrderedListNode_Destroy
	scene->addNode(ol, parent)
	return ol
}

UIOrderedListNode_AddItem :: proc(ol: ^UIOrderedListNode, item: uilib.ListItem) {
	append(&ol.items, item)
}

UIOrderedListNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	ol := cast(^UIOrderedListNode)node
	if !UI_TakesInput(ol) do return

	rect := UI_GetElementRect(&ol.ui)
	mp := UI_GetMousePos(gameContext)
	ol.hovered = UI_PointInRect(mp, rect) && !UI_IsBlockedByActiveDropdown(gameContext, nil, mp)

	// Keyboard arrow navigation when focused
	if ol.focused && !ol.justFocused && len(ol.items) > 0 {
		if UI_IsKeyPressedUp(gameContext) {
			newIdx := max(ol.selectedIndex - 1, 0)
			if newIdx != ol.selectedIndex {
				ol.selectedIndex = newIdx
				Notify(&ol.onSelect, rawptr(ol), ol.selectedIndex, gameContext)
				if ol.onSelectCallback != nil do ol.onSelectCallback(ol, ol.selectedIndex, gameContext)
				if ol.onSelectItem != nil do ol.onSelectItem(ol, ol.selectedIndex)
			}
		} else if UI_IsKeyPressedDown(gameContext) {
			newIdx := min(ol.selectedIndex + 1, len(ol.items) - 1)
			if newIdx != ol.selectedIndex {
				ol.selectedIndex = newIdx
				Notify(&ol.onSelect, rawptr(ol), ol.selectedIndex, gameContext)
				if ol.onSelectCallback != nil do ol.onSelectCallback(ol, ol.selectedIndex, gameContext)
				if ol.onSelectItem != nil do ol.onSelectItem(ol, ol.selectedIndex)
			}
		}
	}

	// Mouse click selection
	if ol.hovered && UI_IsMousePressed(gameContext) {
		for i in 0..<len(ol.items) {
			rowY := rect.y + ol.scroll.y + 6.0 + f32(i) * ol.itemHeight
			rowRect := rl.Rectangle{rect.x + 4, rowY, rect.width - 8, ol.itemHeight}
			if UI_PointInRect(mp, rowRect) {
				if ol.selectedIndex != i {
					ol.selectedIndex = i
					Notify(&ol.onSelect, rawptr(ol), ol.selectedIndex, gameContext)
					if ol.onSelectCallback != nil do ol.onSelectCallback(ol, i, gameContext)
					if ol.onSelectItem != nil do ol.onSelectItem(ol, i)
				}
				break
			}
		}
	}
}

UIOrderedListNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	ol := cast(^UIOrderedListNode)node
	rect := UI_GetElementRect(&ol.ui)
	scr := rl.Vector2{ol.scroll.x, ol.scroll.y}
	uilib.GuiOrderedList(
		rect,
		ol.items[:],
		&ol.selectedIndex,
		&scr,
		ol.numbering,
		ol.startNumber,
		ol.itemHeight,
		idKey = uintptr(rawptr(ol)),
	)
	ol.scroll = {scr.x, scr.y}
}

UIOrderedListNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	ol := cast(^UIOrderedListNode)node
	delete(ol.items)
	DestroySubject(&ol.onSelect)
}

// ============================================================================
// 19. UITableNode (HTML <table> Data Table Node with Sorting & Selection)
// ============================================================================
UITableNode :: struct {
	using ui: UIElement,
	columns: [dynamic]uilib.TableColumn,
	rows: [dynamic]uilib.TableRow,
	selectedRow: int `gui:"true"`,
	sortColumn: int `gui:"true"`,
	sortAscending: bool `gui:"true"`,
	headerHeight: f32 `gui:"true" min:"20" max:"60"`,
	rowHeight: f32 `gui:"true" min:"18" max:"48"`,
	scroll: [2]f32,
	userData: rawptr,
	onSelectRow: EventSubject,
	onSelectRowCallback: proc(node: ^UITableNode, rowIdx: int, gameContext: ^GameContext),
	onSort: EventSubject,
	onSortCallback: proc(node: ^UITableNode, colIdx: int, asc: bool, gameContext: ^GameContext),
}
UITable :: UITableNode

UITableNode_Create :: proc(
	scene: ^Scene,
	name: string = "Table",
	columns: []uilib.TableColumn = nil,
	rows: []uilib.TableRow = nil,
	size: [2]f32 = {540, 280},
	parent: ^Node = nil,
) -> ^UITableNode {
	tbl := CreateNode(scene.manager, UITableNode)
	tbl.name = strings.clone(name, tbl.allocator) // owned: callers pass temp strings too
	UIElement_Init(&tbl.ui, .Table, size)
	tbl.headerHeight = 32.0
	tbl.rowHeight = 28.0
	tbl.selectedRow = 0
	tbl.sortColumn = 0
	tbl.sortAscending = true
	for c in columns {
		append(&tbl.columns, c)
	}
	for r in rows {
		append(&tbl.rows, r)
	}
	InitializeSubject(&tbl.onSelectRow, "row_selected", tbl)
	InitializeSubject(&tbl.onSort, "sorted", tbl)
	tbl.update = UITableNode_Update
	tbl.render = UITableNode_Render
	tbl.onDestroy = UITableNode_Destroy
	scene->addNode(tbl, parent)
	return tbl
}

UITableNode_AddColumn :: proc(tbl: ^UITableNode, col: uilib.TableColumn) {
	append(&tbl.columns, col)
}

UITableNode_AddRow :: proc(tbl: ^UITableNode, row: uilib.TableRow) {
	append(&tbl.rows, row)
}

UITableNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	tbl := cast(^UITableNode)node
	if !UI_TakesInput(tbl) do return

	rect := UI_GetElementRect(&tbl.ui)
	mp := UI_GetMousePos(gameContext)
	tbl.hovered = UI_PointInRect(mp, rect) && !UI_IsBlockedByActiveDropdown(gameContext, nil, mp)

	// Keyboard arrow navigation when focused
	if tbl.focused && !tbl.justFocused && len(tbl.rows) > 0 {
		if UI_IsKeyPressedUp(gameContext) {
			newRow := max(tbl.selectedRow - 1, 0)
			if newRow != tbl.selectedRow {
				tbl.selectedRow = newRow
				Notify(&tbl.onSelectRow, rawptr(tbl), tbl.selectedRow, gameContext)
				if tbl.onSelectRowCallback != nil do tbl.onSelectRowCallback(tbl, tbl.selectedRow, gameContext)
			}
		} else if UI_IsKeyPressedDown(gameContext) {
			newRow := min(tbl.selectedRow + 1, len(tbl.rows) - 1)
			if newRow != tbl.selectedRow {
				tbl.selectedRow = newRow
				Notify(&tbl.onSelectRow, rawptr(tbl), tbl.selectedRow, gameContext)
				if tbl.onSelectRowCallback != nil do tbl.onSelectRowCallback(tbl, tbl.selectedRow, gameContext)
			}
		}
	}
}

UITableNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	tbl := cast(^UITableNode)node
	rect := UI_GetElementRect(&tbl.ui)
	scr := rl.Vector2{tbl.scroll.x, tbl.scroll.y}
	oldRow := tbl.selectedRow
	oldSort := tbl.sortColumn
	oldAsc := tbl.sortAscending

	rClicked, hClicked := uilib.GuiTable(
		rect,
		tbl.columns[:],
		tbl.rows[:],
		&tbl.selectedRow,
		&tbl.sortColumn,
		&tbl.sortAscending,
		&scr,
		tbl.headerHeight,
		tbl.rowHeight,
		idKey = uintptr(rawptr(tbl)),
	)
	tbl.scroll = {scr.x, scr.y}

	// (#229) Clicks raise the signals too; a header click sorts the rows.
	if rClicked >= 0 || tbl.selectedRow != oldRow {
		if tbl.onSelectRowCallback != nil do tbl.onSelectRowCallback(tbl, tbl.selectedRow, gameContext)
		Notify(&tbl.onSelectRow, rawptr(tbl), tbl.selectedRow, gameContext)
	}
	if hClicked >= 0 || tbl.sortColumn != oldSort || tbl.sortAscending != oldAsc {
		UITableNode_SortRows(tbl)
		if tbl.onSortCallback != nil do tbl.onSortCallback(tbl, tbl.sortColumn, tbl.sortAscending, gameContext)
		Notify(&tbl.onSort, rawptr(tbl), tbl.sortColumn, gameContext)
	}
}

// UITableNode_SortRows orders the rows by the sort column (numbers as
// numbers), keeping the selected row selected.
UITableNode_SortRows :: proc(tbl: ^UITableNode) {
	if tbl.sortColumn < 0 || len(tbl.rows) < 2 do return
	selId := tbl.rows[tbl.selectedRow].id if tbl.selectedRow >= 0 && tbl.selectedRow < len(tbl.rows) else -1
	col, asc := tbl.sortColumn, tbl.sortAscending
	cell :: proc(r: uilib.TableRow, col: int) -> string {return r.cells[col].text if col < len(r.cells) else ""}
	less :: proc(a, b: string) -> bool {
		x, okx := strconv.parse_f64(strings.trim_space(a))
		y, oky := strconv.parse_f64(strings.trim_space(b))
		if okx && oky do return x < y
		return a < b
	}
	// (Stable insertion sort: tables are short.)
	for i in 1 ..< len(tbl.rows) {
		for j := i; j > 0; j -= 1 {
			a, b := cell(tbl.rows[j - 1], col), cell(tbl.rows[j], col)
			if !(less(b, a) if asc else less(a, b)) do break
			tbl.rows[j - 1], tbl.rows[j] = tbl.rows[j], tbl.rows[j - 1]
		}
	}
	if selId >= 0 do for r, i in tbl.rows do if r.id == selId do tbl.selectedRow = i
}

UITableNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	tbl := cast(^UITableNode)node
	delete(tbl.columns)
	delete(tbl.rows)
	DestroySubject(&tbl.onSelectRow)
	DestroySubject(&tbl.onSort)
}

// ============================================================================
// 17. UIIconNode (Font Awesome Vector Icon)
// ============================================================================
UIIconNode :: struct {
	using ui: UIElement,
	icon: Icon `gui:"true"`,
	iconSize: f32 `gui:"true" min:"8" max:"128"`,
	color: rl.Color `gui:"true"`,
	align: UITextAlign `gui:"true"`,
}

UIIcon :: UIIconNode

UIIconNode_Create :: proc(
	scene: ^Scene,
	name: string = "Icon",
	icon: Icon = .None,
	size: [2]f32 = {28, 28},
	iconSize: f32 = 0,
	parent: ^Node = nil,
	color: rl.Color = {238, 240, 246, 255},
	align: UITextAlign = .Center,
) -> ^UIIconNode {
	node := CreateNode(scene.manager, UIIconNode)
	node.name = strings.clone(name, node.allocator) // owned: callers pass temp strings too
	UIElement_Init(&node.ui, .Icon, size)
	node.icon = icon
	node.iconSize = iconSize
	node.color = color
	node.align = align
	node.render = UIIconNode_Render
	scene->addNode(node, parent)
	return node
}

UIIconNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	ic := cast(^UIIconNode)node
	rect := UI_GetElementRect(&ic.ui)
	uilib.RenderIcon(rect, ic.icon, ic.iconSize, ic.color, ic.align)
}

// ============================================================================
// 18. UIToolbarNode (Interactive Application Toolbar with Font Awesome Icons)
// ============================================================================
UIToolbarNode :: struct {
	using ui: UIElement,
	items: [dynamic]ToolbarItem,
	activeToggleId: int `gui:"true"`,
	buttonSize: [2]f32 `gui:"true"`,
	spacing: f32 `gui:"true" min:"0" max:"32"`,
	hoveredItemId: int,
	onItemClick: EventSubject,
	onItemClickCallback: proc(tb: ^UIToolbarNode, itemId: int, gameContext: ^GameContext),
}

UIToolbar :: UIToolbarNode

UIToolbarNode_Create :: proc(
	scene: ^Scene,
	name: string = "Toolbar",
	size: [2]f32 = {600, 42},
	parent: ^Node = nil,
	buttonSize: [2]f32 = {34, 32},
	spacing: f32 = 4.0,
) -> ^UIToolbarNode {
	tb := CreateNode(scene.manager, UIToolbarNode)
	tb.name = strings.clone(name, tb.allocator) // owned: callers pass temp strings too
	UIElement_Init(&tb.ui, .Toolbar, size)
	tb.items = make([dynamic]ToolbarItem, tb.allocator)
	tb.activeToggleId = -1
	tb.buttonSize = buttonSize
	tb.spacing = spacing
	tb.hoveredItemId = -1
	InitializeSubject(&tb.onItemClick, "item_clicked", tb)
	tb.update = UIToolbarNode_Update
	tb.render = UIToolbarNode_Render
	tb.onDestroy = UIToolbarNode_Destroy
	scene->addNode(tb, parent)
	return tb
}

UIToolbarNode_AddItem :: proc(
	tb: ^UIToolbarNode,
	id: int,
	icon: Icon,
	label: string = "",
	tooltip: string = "",
	itemType: ToolbarItemType = .Button,
	isSelected: bool = false,
) {
	append(&tb.items, ToolbarItem{
		id = id,
		icon = icon,
		label = label,
		tooltip = tooltip,
		itemType = itemType,
		isSelected = isSelected,
		disabled = false,
	})
}

UIToolbarNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	tb := cast(^UIToolbarNode)node
	if !UI_TakesInput(tb) do return
	rect := UI_GetElementRect(&tb.ui)
	mp := UI_GetMousePos(gameContext)
	inViewport := UI_IsMouseInViewport(gameContext)

	curX := rect.x + 8.0
	centerY := rect.y + rect.height * 0.5
	tb.hoveredItemId = -1

	for &item in tb.items {
		#partial switch item.itemType {
		case .Separator:
			curX += 8.0
		case .Spacer:
			curX += 16.0
		case .Button, .Toggle:
			btnW := tb.buttonSize.x
			if item.label != "" {
				labelW := uilib.MeasureTextStr(item.label, uilib.DEFAULT_FONT_SIZE_SM).x
				iconW: f32 = 18.0 if item.icon != .None else 0.0
				gap: f32 = 6.0 if (item.icon != .None && item.label != "") else 0.0
				btnW = max(btnW, iconW + gap + labelW + 16.0)
			}
			btnH := tb.buttonSize.y
			btnY := math.round(centerY - btnH * 0.5)
			btnRect := rl.Rectangle{curX, btnY, btnW, btnH}

			if inViewport && UI_PointInRect(mp, btnRect) {
				tb.hoveredItemId = item.id
				if UI_IsMousePressed(gameContext) && !item.disabled {
					if item.itemType == .Toggle {
						item.isSelected = !item.isSelected
						tb.activeToggleId = item.id if item.isSelected else -1
					}
					if tb.onItemClick.notify != nil {
						tb.onItemClick->notify(tb, item.id, gameContext)
					}
					if tb.onItemClickCallback != nil {
						tb.onItemClickCallback(tb, item.id, gameContext)
					}
				}
			}
			curX += btnW + tb.spacing
		}
	}
}

UIToolbarNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	tb := cast(^UIToolbarNode)node
	rect := UI_GetElementRect(&tb.ui)
	selectedId := tb.activeToggleId
	tooltip, tooltipPos := uilib.RenderToolbar(
		rect,
		tb.items[:],
		tb.hoveredItemId,
		selectedId,
		-1,
		tb.buttonSize,
		tb.spacing,
	)
	if tooltip != "" {
		uilib.RenderTooltip(tooltipPos, tooltip)
	}
}

UIToolbarNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	tb := cast(^UIToolbarNode)node
	delete(tb.items)
	DestroySubject(&tb.onItemClick)
}
