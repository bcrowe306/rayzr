package engine

import "core:c"
import "core:math"
import "core:strings"
import lua "lua54"
import rl "vendor:raylib"

// ============================================================================
// On-screen controls (#276): a Touch Joystick drives four input actions
// (move_left / right / up / down by default) with analog strength; a Touch
// Button presses one action (jump, fire...) while a finger is on it. Put
// them under a Screen Layer: their position is then on the screen.
//
// They show once the device has been touched (Always Show: from the start;
// the editor always shows them), so keyboard and gamepad players never see
// them. A finger that lands on one is the control's (touch.odin): it isn't
// the mouse and makes no gestures.
// ============================================================================

TouchJoystickNode :: struct {
	using node:  Node,
	radius:      f32 `gui:"true" min:"10" max:"400"`,  // the base's radius: a full push
	knobRadius:  f32 `gui:"true" min:"4" max:"200"`,
	floating:    bool `gui:"true"`,                    // the base appears where the thumb lands (in Area)
	area:        [2]f32 `gui:"true" min:"0" max:"4000"`, // Floating: where a thumb starts it (centred on the node)
	deadzone:    f32 `gui:"true" min:"0" max:"0.9"`,
	actionLeft:  string `gui:"true"`,
	actionRight: string `gui:"true"`,
	actionUp:    string `gui:"true"`,
	actionDown:  string `gui:"true"`,
	color:       rl.Color `gui:"true"`,
	knobColor:   rl.Color `gui:"true"`,
	alwaysShow:  bool `gui:"true"`,                    // shown before the device is touched too
	vector:      [2]f32, // this frame's push (-1..1 each way; length up to 1)
	center:      [2]f32, // the base's centre now (global)
	held:        bool,
}

TouchButtonNode :: struct {
	using node:   Node,
	radius:       f32 `gui:"true" min:"8" max:"300"`,
	action:       string `gui:"true"`, // the input action it presses (several: comma-separated)
	label:        string `gui:"true"`,
	fontSize:     f32 `gui:"true" min:"6" max:"128"`,
	color:        rl.Color `gui:"true"`,
	pressedColor: rl.Color `gui:"true"`,
	textColor:    rl.Color `gui:"true"`,
	alwaysShow:   bool `gui:"true"`,
	down:         bool, // a finger is on it
}

TouchJoystickNode_Create :: proc(scene: ^Scene, name: string = "TouchJoystick", parent: ^Node = nil) -> ^TouchJoystickNode {
	j := CreateNode(scene.manager, TouchJoystickNode)
	TouchJoystickNode_Init(j)
	j.name = strings.clone(name, j.allocator)
	scene->addNode(j, parent)
	return j
}

TouchJoystickNode_Init :: proc(j: ^TouchJoystickNode) {
	j.radius, j.knobRadius = 70, 32
	j.area = {480, 480}
	j.deadzone = 0.2
	j.actionLeft = strings.clone("move_left", j.allocator)
	j.actionRight = strings.clone("move_right", j.allocator)
	j.actionUp = strings.clone("move_up", j.allocator)
	j.actionDown = strings.clone("move_down", j.allocator)
	j.color = {255, 255, 255, 60}
	j.knobColor = {255, 255, 255, 150}
	j.layer = .Layer8
	j.render = TouchJoystickNode_Render
}

TouchButtonNode_Create :: proc(scene: ^Scene, name: string = "TouchButton", parent: ^Node = nil) -> ^TouchButtonNode {
	b := CreateNode(scene.manager, TouchButtonNode)
	TouchButtonNode_Init(b)
	b.name = strings.clone(name, b.allocator)
	scene->addNode(b, parent)
	return b
}

TouchButtonNode_Init :: proc(b: ^TouchButtonNode) {
	b.radius = 48
	b.action = strings.clone("jump", b.allocator)
	b.label = strings.clone("A", b.allocator)
	b.fontSize = 28
	b.color = {255, 255, 255, 60}
	b.pressedColor = {255, 255, 255, 140}
	b.textColor = {255, 255, 255, 220}
	b.layer = .Layer8
	b.render = TouchButtonNode_Render
}

// TouchControl_Shown: the control draws and takes fingers.
TouchControl_Shown :: proc(n: ^Node, always: bool) -> bool {
	if !n.enabled || !n.renderable do return false
	gc := n.gameContext
	if always || gc == nil || gc.game == nil do return true
	return gc.game.inEditor || gc.game.input.touch.everTouched
}

// TouchControl_Claim: the control a finger landing at `pos` belongs to (nil: none).
TouchControl_Claim :: proc(game: ^Game, pos: [2]f32) -> ^Node {
	scene := game.sceneManager.currentScene
	if scene == nil || scene.manager == nil do return nil
	for n in scene.manager.nodes {
		if n == nil do continue
		switch n.typeId {
		case TouchJoystickNode:
			j := cast(^TouchJoystickNode)n
			// (A finger lands after the first touch: shown or showing now.)
			if !j.enabled || !j.renderable do continue
			if j.floating {
				h := j.area * 0.5 * abs_scale(j)
				if abs(pos.x - j.globalPosition.x) <= h.x && abs(pos.y - j.globalPosition.y) <= h.y do return n
			} else if dist2(pos, j.globalPosition) <= sq(j.radius * 1.3 * abs_scale(j).x) {
				return n
			}
		case TouchButtonNode:
			b := cast(^TouchButtonNode)n
			if !b.enabled || !b.renderable do continue
			if dist2(pos, b.globalPosition) <= sq(b.radius * 1.15 * abs_scale(b).x) do return n
		}
	}
	return nil
}

@(private = "file")
abs_scale :: proc(n: ^Node) -> [2]f32 {
	s := [2]f32{abs(n.globalScale.x), abs(n.globalScale.y)}
	return {s.x if s.x > 0 else 1, s.y if s.y > 0 else 1}
}

@(private = "file")
dist2 :: #force_inline proc(a, b: [2]f32) -> f32 {d := a - b; return d.x * d.x + d.y * d.y}

@(private = "file")
sq :: #force_inline proc(v: f32) -> f32 {return v * v}

// TouchControls_Update: each control from its finger, and their actions
// (Input_Touch.actions) for this frame's input.
TouchControls_Update :: proc(game: ^Game) {
	t := &game.input.touch
	if t.actions == nil do t.actions = make(map[string]f32, allocator = Engine_HeapAllocator())
	clear(&t.actions)
	scene := game.sceneManager.currentScene
	if scene == nil || scene.manager == nil do return
	finger :: proc(t: ^Input_Touch, n: ^Node) -> ^Touch_Point {
		for i in 0 ..< t.count do if t.points[i].claim == n && t.points[i].down do return &t.points[i]
		return nil
	}
	add :: proc(t: ^Input_Touch, name: string, v: f32) {
		if name == "" || v <= 0 do return
		t.actions[name] = max(t.actions[name] or_else 0, v)
	}
	for n in scene.manager.nodes {
		if n == nil do continue
		switch n.typeId {
		case TouchJoystickNode:
			j := cast(^TouchJoystickNode)n
			p := finger(t, n)
			if p == nil {
				j.held, j.vector, j.center = false, {}, j.globalPosition
				continue
			}
			if !j.held do j.center = p.start if j.floating else j.globalPosition
			j.held = true
			r := j.radius * abs_scale(j).x
			v := (p.pos - j.center) / max(r, 1)
			l := math.sqrt(v.x * v.x + v.y * v.y)
			if l > 1 do v /= l
			if l < j.deadzone do v = {}
			j.vector = v
			add(t, j.actionLeft, -v.x)
			add(t, j.actionRight, v.x)
			add(t, j.actionUp, -v.y)
			add(t, j.actionDown, v.y)
		case TouchButtonNode:
			b := cast(^TouchButtonNode)n
			b.down = finger(t, n) != nil
			if b.down {
				rest := b.action // ("interact, confirm": both)
				for part in strings.split_iterator(&rest, ",") do add(t, strings.trim_space(part), 1)
			}
		}
	}
}

TouchJoystickNode_Render :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	j := cast(^TouchJoystickNode)node
	if !rl.IsWindowReady() || !TouchControl_Shown(j, j.alwaysShow) do return
	s := abs_scale(j).x
	c := j.center if j.held else j.globalPosition
	if gc := j.gameContext; gc != nil && gc.game != nil && gc.game.inEditor && j.floating {
		// (The editor: the area a thumb can start it in.)
		h := j.area * 0.5 * abs_scale(j)
		rl.DrawRectangleLinesEx({j.globalPosition.x - h.x, j.globalPosition.y - h.y, h.x * 2, h.y * 2}, 1, {255, 255, 255, 40})
	}
	rl.DrawCircleV(c, j.radius * s, j.color)
	rl.DrawCircleLinesV(c, j.radius * s, {j.knobColor.r, j.knobColor.g, j.knobColor.b, j.knobColor.a / 2})
	rl.DrawCircleV(c + j.vector * j.radius * s, j.knobRadius * s, j.knobColor)
}

TouchButtonNode_Render :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	b := cast(^TouchButtonNode)node
	if !rl.IsWindowReady() || !TouchControl_Shown(b, b.alwaysShow) do return
	s := abs_scale(b).x
	rl.DrawCircleV(b.globalPosition, b.radius * s, b.pressedColor if b.down else b.color)
	rl.DrawCircleLinesV(b.globalPosition, b.radius * s, b.textColor)
	if b.label != "" {
		f := Text_GetFont("", b.fontSize * s, false, ctx)
		measure :: proc(r: rune, size: f32, data: rawptr) -> f32 {return Text_MeasureRune(cast(^Text_Font)data, r, size)}
		g, size := Text_Layout(b.label, {b.textColor, b.fontSize * s, {}}, 0, 0, 1, false, measure, f)
		Text_DrawGlyphs(f, g, b.globalPosition - size * 0.5, 0, 1, -1, 0, ctx = ctx)
	}
}

// --- Lua: joystick:touch_get_vector(), button:touch_is_down() --------------------------

@(private = "file")
lua_touch_get_vector :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	n, ok := to_node_userdata(L, 1)
	v: [2]f32
	if ok && n.typeId == TouchJoystickNode do v = (cast(^TouchJoystickNode)n).vector
	lua.pushnumber(L, lua.Number(v.x))
	lua.pushnumber(L, lua.Number(v.y))
	return 2
}

@(private = "file")
lua_touch_is_down :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	n, ok := to_node_userdata(L, 1)
	down := false
	if ok && n.typeId == TouchButtonNode do down = (cast(^TouchButtonNode)n).down
	if ok && n.typeId == TouchJoystickNode do down = (cast(^TouchJoystickNode)n).held
	lua.pushboolean(L, b32(down))
	return 1
}

// Script_RegisterTouchControlBindings adds the controls' methods to the node metatable (on the stack).
Script_RegisterTouchControlBindings :: proc(L: ^lua.State) {
	lua.pushcfunction(L, lua_touch_get_vector)
	lua.setfield(L, -2, "touch_get_vector")
	lua.pushcfunction(L, lua_touch_is_down)
	lua.setfield(L, -2, "touch_is_down")
}
