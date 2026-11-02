package engine

import "base:runtime"
import "core:c"
import "core:encoding/json"
import "core:fmt"
import os "osx"
import "core:path/filepath"
import "core:strings"
import lua "lua54"
import rl "vendor:raylib"

// ============================================================================
// Player rebinding (docs/input_rebinding.md).
//
// - Any action (built-in or the project's) can have its bindings read,
//   replaced, added or cleared; Input_RebindListen captures the next key,
//   mouse button, gamepad button or stick push for one (Escape cancels).
//   Listening waits until everything is released first, so the key or
//   button that opened the menu isn't bound by accident.
// - A binding another action already uses is removed there (conflicts
//   "clear", the default), swapped ("swap") or kept ("allow").
// - The player's bindings are saved next to the save files
//   (input_bindings.json) and loaded when the game starts, over the
//   project's; Input_RebindReset goes back to the project's.
// - Player-facing names: "Space", "Left Shift", "A", "Left Stick Right".
// ============================================================================

Rebind_Device :: enum u8 {Any, Keyboard_Mouse, Gamepad}
Rebind_Conflicts :: enum u8 {Clear, Swap, Allow}
Rebind_Result :: enum u8 {None, Bound, Cancelled}

Input_Rebind :: struct {
	listening: bool,
	armed:     bool, // everything was released since listening began
	action:    string, // heap
	slot:      int,    // 1-based binding to replace; 0 = the first of the same device kind (else add)
	device:    Rebind_Device,
	conflicts: Rebind_Conflicts,
	cancelKey: rl.KeyboardKey,
	result:    Rebind_Result,
	bound:     InputBinding,
	callback:  i32, // Lua registry ref called when done (0 = none)
	// Project defaults (Input_RebindReset) and where user bindings save.
	defaults:  [dynamic]Input_Action_Config, // heap
	autoSave:  bool,
	lastDevice: Rebind_Device, // the device the player used last (prompts)
}

// Input_MappingOf: an action's bindings (a project action, else built-in).
Input_MappingOf :: proc(input: ^InputSystem, name: string) -> ^ActionMapping {
	if n := Input_FindNamed(input, name); n != nil do return &n.mapping
	if a, ok := Builtin_ActionByName(name); ok do return &input.mappings[a]
	return nil
}

// Input_RebindSetDefaults keeps a copy of the project's actions (reset).
Input_RebindSetDefaults :: proc(input: ^InputSystem, actions: []Input_Action_Config) {
	a := Engine_HeapAllocator()
	Input_ActionConfigs_Destroy(&input.rebind.defaults, a)
	input.rebind.defaults = make([dynamic]Input_Action_Config, a)
	src := actions
	builtin: [dynamic]Input_Action_Config
	if len(src) == 0 {
		builtin = Input_DefaultActionConfigs(context.temp_allocator)
		src = builtin[:]
	}
	for c in src {
		cc := Input_Action_Config{name = strings.clone(c.name, a), bindings = make([dynamic]InputBinding, a)}
		for b in c.bindings do append(&cc.bindings, b)
		append(&input.rebind.defaults, cc)
	}
	input.rebind.autoSave = true
}

Input_RebindDestroy :: proc(input: ^InputSystem) {
	a := Engine_HeapAllocator()
	Input_ActionConfigs_Destroy(&input.rebind.defaults, a)
	delete(input.rebind.action, a)
	input.rebind.action = ""
}

// Input_RebindReset puts one action (or all, name "") back to the project's
// bindings.
Input_RebindReset :: proc(input: ^InputSystem, name := "") {
	for c in input.rebind.defaults {
		if name != "" && !strings.equal_fold(c.name, name) do continue
		Input_DefineAction(input, c.name, c.bindings[:])
	}
}

binding_device :: proc(b: InputBinding) -> Rebind_Device {
	#partial switch b.deviceType {
	case .GamepadButton, .GamepadAxis: return .Gamepad
	case .None: return .Any
	}
	return .Keyboard_Mouse
}

// Input_SetBinding puts `b` in an action's slot (1-based; 0 = replace the
// first binding of the same device kind, else add; a slot past the end
// adds), handling conflicts with other actions. A `.None` binding removes
// the slot. Returns false for an unknown action.
Input_SetBinding :: proc(input: ^InputSystem, name: string, slot: int, b: InputBinding, conflicts := Rebind_Conflicts.Clear) -> bool {
	m := Input_MappingOf(input, name)
	if m == nil do return false
	if b.deviceType == .None {
		if slot >= 1 && slot <= m.bindingCount do mapping_remove(m, slot - 1)
		return true
	}
	// Where it goes.
	idx := -1
	if slot >= 1 && slot <= m.bindingCount do idx = slot - 1
	else if slot == 0 {
		for i in 0 ..< m.bindingCount do if binding_device(m.bindings[i]) == binding_device(b) {idx = i; break}
	}
	// A full action without this binding has no room: nothing changes.
	if idx < 0 && m.bindingCount >= MAX_BINDINGS_PER_ACTION {
		has := false
		for i in 0 ..< m.bindingCount do if bindings_equal(m.bindings[i], b) {has = true; break}
		if !has do return false
	}
	old := m.bindings[idx] if idx >= 0 else InputBinding{}
	// Other actions using it.
	if conflicts != .Allow {
		for other in Input_Conflicts(input, b, context.temp_allocator) {
			if strings.equal_fold(other, name) do continue
			om := Input_MappingOf(input, other)
			if om == nil do continue
			for i := om.bindingCount - 1; i >= 0; i -= 1 do if bindings_equal(om.bindings[i], b) {
				if conflicts == .Swap && old.deviceType != .None do om.bindings[i] = old
				else do mapping_remove(om, i)
			}
		}
	}
	// A duplicate in this action goes away (the new one takes its place).
	for i := m.bindingCount - 1; i >= 0; i -= 1 do if i != idx && bindings_equal(m.bindings[i], b) {
		mapping_remove(m, i)
		if idx > i do idx -= 1
	}
	if idx >= 0 do m.bindings[idx] = b
	else if m.bindingCount < MAX_BINDINGS_PER_ACTION {
		m.bindings[m.bindingCount] = b
		m.bindingCount += 1
	}
	return true
}

@(private = "file")
mapping_remove :: proc(m: ^ActionMapping, i: int) {
	for k in i ..< m.bindingCount - 1 do m.bindings[k] = m.bindings[k + 1]
	m.bindingCount -= 1
	m.bindings[m.bindingCount] = {}
}

bindings_equal :: proc(a, b: InputBinding) -> bool {
	if a.deviceType != b.deviceType do return false
	switch a.deviceType {
	case .KeyboardKey:   return a.key == b.key
	case .MouseButton:   return a.mouseButton == b.mouseButton
	case .GamepadButton: return a.gamepadButton == b.gamepadButton
	case .GamepadAxis:   return a.gamepadAxis == b.gamepadAxis && a.axisPositive == b.axisPositive
	case .None:          return true
	}
	return false
}

// Input_Conflicts: the actions (by name) that already use a binding.
Input_Conflicts :: proc(input: ^InputSystem, b: InputBinding, allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, allocator)
	seen := make(map[string]bool, allocator = context.temp_allocator)
	for &n in input.named {
		for i in 0 ..< n.mapping.bindingCount do if bindings_equal(n.mapping.bindings[i], b) {
			append(&out, n.name)
			seen[strings.to_lower(n.name, context.temp_allocator)] = true
			break
		}
	}
	for a in InputAction {
		name := Builtin_ActionName(a)
		if strings.to_lower(name, context.temp_allocator) in seen || Input_FindNamed(input, name) != nil do continue
		m := &input.mappings[a]
		for i in 0 ..< m.bindingCount do if bindings_equal(m.bindings[i], b) {
			append(&out, name)
			break
		}
	}
	return out[:]
}

// Input_RebindListen starts capturing the next input for an action.
Input_RebindListen :: proc(input: ^InputSystem, name: string, slot := 0, device := Rebind_Device.Any, conflicts := Rebind_Conflicts.Clear, cancelKey := rl.KeyboardKey.ESCAPE) -> bool {
	if Input_MappingOf(input, name) == nil do return false
	a := Engine_HeapAllocator()
	delete(input.rebind.action, a)
	input.rebind.action = strings.clone(name, a)
	input.rebind.slot, input.rebind.device, input.rebind.conflicts, input.rebind.cancelKey = slot, device, conflicts, cancelKey
	input.rebind.listening, input.rebind.armed, input.rebind.result = true, false, .None
	return true
}

// Input_RebindCancel stops listening (result Cancelled).
Input_RebindCancel :: proc(input: ^InputSystem) {
	if !input.rebind.listening do return
	input.rebind.listening = false
	input.rebind.result = .Cancelled
}

REBIND_AXIS_PUSH :: 0.6

// Input_RebindUpdate (InputSystem_Update): while listening, the first input
// after everything was released; also tracks the last device used.
Input_RebindUpdate :: proc(input: ^InputSystem) -> (done: bool) {
	if !rl.IsWindowReady() do return false
	pad := input.gamepadIndex
	padOk := pad >= 0 && pad < MAX_PADS && rl.IsGamepadAvailable(pad)
	// The last device (for prompts / glyphs).
	if rl.IsMouseButtonPressed(.LEFT) do input.rebind.lastDevice = .Keyboard_Mouse
	else do for k in 32 ..< 350 do if rl.IsKeyPressed(rl.KeyboardKey(k)) {input.rebind.lastDevice = .Keyboard_Mouse; break}
	if padOk do for gb in rl.GamepadButton do if gb != .UNKNOWN && rl.IsGamepadButtonPressed(pad, gb) {input.rebind.lastDevice = .Gamepad; break}
	r := &input.rebind
	if !r.listening do return false
	if !r.armed {
		// Wait for the key / button that opened the menu to be let go.
		for k in 1 ..< 350 do if rl.IsKeyDown(rl.KeyboardKey(k)) do return false
		for m in rl.MouseButton do if rl.IsMouseButtonDown(m) do return false
		if padOk {
			for gb in rl.GamepadButton do if gb != .UNKNOWN && rl.IsGamepadButtonDown(pad, gb) do return false
			for ax in rl.GamepadAxis do if abs(rl.GetGamepadAxisMovement(pad, ax)) > REBIND_AXIS_PUSH * 0.5 && !axis_is_trigger(ax) do return false
		}
		r.armed = true
		return false
	}
	b: InputBinding
	if r.device != .Gamepad {
		for k in 1 ..< 350 do if rl.IsKeyPressed(rl.KeyboardKey(k)) {
			key := rl.KeyboardKey(k)
			if key == r.cancelKey {
				r.listening, r.result = false, .Cancelled
				return true
			}
			b = {deviceType = .KeyboardKey, key = key}
			break
		}
		if b.deviceType == .None do for m in rl.MouseButton do if rl.IsMouseButtonPressed(m) {
			b = {deviceType = .MouseButton, mouseButton = m}
			break
		}
	}
	if b.deviceType == .None && r.device != .Keyboard_Mouse && padOk {
		for gb in rl.GamepadButton do if gb != .UNKNOWN && rl.IsGamepadButtonPressed(pad, gb) {
			b = {deviceType = .GamepadButton, gamepadButton = gb}
			break
		}
		if b.deviceType == .None do for ax in rl.GamepadAxis {
			if axis_is_trigger(ax) do continue // triggers come as buttons too
			v := rl.GetGamepadAxisMovement(pad, ax)
			if abs(v) > REBIND_AXIS_PUSH {
				b = {deviceType = .GamepadAxis, gamepadAxis = ax, axisPositive = v > 0, axisDeadzone = 0.25}
				break
			}
		}
	}
	if b.deviceType == .None do return false
	return Input_RebindApply(input, b)
}

// Input_RebindApply binds the captured input (also for tests / scripts).
Input_RebindApply :: proc(input: ^InputSystem, b: InputBinding) -> bool {
	r := &input.rebind
	Input_SetBinding(input, r.action, r.slot, b, r.conflicts)
	r.listening, r.result, r.bound = false, .Bound, b
	if r.autoSave do Input_SaveUserBindings(input)
	return true
}

@(private = "file")
axis_is_trigger :: proc(ax: rl.GamepadAxis) -> bool {return ax == .LEFT_TRIGGER || ax == .RIGHT_TRIGGER}

// --- player-facing names --------------------------------------------------------------

// InputBinding_DisplayName: "Space", "Left Shift", "Mouse Left", "A", "Left Stick Right".
InputBinding_DisplayName :: proc(b: InputBinding, allocator := context.temp_allocator) -> string {
	switch b.deviceType {
	case .KeyboardKey:   return key_display(b.key, allocator)
	case .MouseButton:   return fmt.aprintf("Mouse %s", title_case(enum_name(b.mouseButton)), allocator = allocator)
	case .GamepadButton: return strings.clone(pad_button_name(b.gamepadButton), allocator)
	case .GamepadAxis:   return strings.clone(pad_axis_name(b.gamepadAxis, b.axisPositive), allocator)
	case .None:
	}
	return strings.clone("-", allocator)
}

@(private = "file")
title_case :: proc(s: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	up := true
	for r in s {
		if r == '_' {
			strings.write_byte(&sb, ' ')
			up = true
			continue
		}
		strings.write_rune(&sb, r if up else (r + 32 if r >= 'A' && r <= 'Z' else r))
		up = false
	}
	return strings.to_string(sb)
}

@(private = "file")
key_display :: proc(k: rl.KeyboardKey, allocator: runtime.Allocator) -> string {
	#partial switch k {
	case .APOSTROPHE: return strings.clone("'", allocator)
	case .COMMA: return strings.clone(",", allocator)
	case .MINUS: return strings.clone("-", allocator)
	case .PERIOD: return strings.clone(".", allocator)
	case .SLASH: return strings.clone("/", allocator)
	case .SEMICOLON: return strings.clone(";", allocator)
	case .EQUAL: return strings.clone("=", allocator)
	case .LEFT_BRACKET: return strings.clone("[", allocator)
	case .BACKSLASH: return strings.clone("\\", allocator)
	case .RIGHT_BRACKET: return strings.clone("]", allocator)
	case .GRAVE: return strings.clone("`", allocator)
	case .UP: return strings.clone("Up Arrow", allocator)
	case .DOWN: return strings.clone("Down Arrow", allocator)
	case .LEFT: return strings.clone("Left Arrow", allocator)
	case .RIGHT: return strings.clone("Right Arrow", allocator)
	case .LEFT_SUPER: return strings.clone("Left Cmd" when ODIN_OS == .Darwin else "Left Win", allocator)
	case .RIGHT_SUPER: return strings.clone("Right Cmd" when ODIN_OS == .Darwin else "Right Win", allocator)
	}
	name := enum_name(k)
	if strings.has_prefix(name, "KP_") do return fmt.aprintf("Numpad %s", title_case(name[3:]), allocator = allocator)
	if strings.has_prefix(name, "KEY_") do name = name[4:]
	if len(name) == 1 do return strings.clone(name, allocator) // A..Z
	return strings.clone(title_case(name), allocator)
}

@(private = "file")
pad_button_name :: proc(b: rl.GamepadButton) -> string {
	#partial switch b {
	case .RIGHT_FACE_DOWN:  return "A"
	case .RIGHT_FACE_RIGHT: return "B"
	case .RIGHT_FACE_LEFT:  return "X"
	case .RIGHT_FACE_UP:    return "Y"
	case .LEFT_FACE_UP:     return "D-Pad Up"
	case .LEFT_FACE_DOWN:   return "D-Pad Down"
	case .LEFT_FACE_LEFT:   return "D-Pad Left"
	case .LEFT_FACE_RIGHT:  return "D-Pad Right"
	case .LEFT_TRIGGER_1:   return "LB"
	case .RIGHT_TRIGGER_1:  return "RB"
	case .LEFT_TRIGGER_2:   return "LT"
	case .RIGHT_TRIGGER_2:  return "RT"
	case .MIDDLE_LEFT:      return "Back"
	case .MIDDLE:           return "Guide"
	case .MIDDLE_RIGHT:     return "Start"
	case .LEFT_THUMB:       return "L3"
	case .RIGHT_THUMB:      return "R3"
	}
	return "Pad ?"
}

@(private = "file")
pad_axis_name :: proc(ax: rl.GamepadAxis, positive: bool) -> string {
	#partial switch ax {
	case .LEFT_X:  return "Left Stick Right" if positive else "Left Stick Left"
	case .LEFT_Y:  return "Left Stick Down" if positive else "Left Stick Up"
	case .RIGHT_X: return "Right Stick Right" if positive else "Right Stick Left"
	case .RIGHT_Y: return "Right Stick Down" if positive else "Right Stick Up"
	case .LEFT_TRIGGER: return "LT"
	case .RIGHT_TRIGGER: return "RT"
	}
	return "Axis ?"
}

// --- saving -------------------------------------------------------------------------------

// Input_UserBindingsPath: input_bindings.json next to the save files.
Input_UserBindingsPath :: proc(allocator := context.temp_allocator) -> string {
	p, _ := filepath.join({filepath.dir(Save_FilePath(), context.temp_allocator), "input_bindings.json"}, allocator)
	return p
}

// Input_UserBindingsJSON: every action's bindings (the project's format).
Input_UserBindingsJSON :: proc(input: ^InputSystem, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make(allocator)
	strings.write_string(&sb, "{\"actions\": [")
	first := true
	write :: proc(sb: ^strings.Builder, first: ^bool, name: string, m: ^ActionMapping) {
		if !first^ do strings.write_string(sb, ",")
		first^ = false
		fmt.sbprintf(sb, "\n  {{\"name\": %q, \"bindings\": [", name)
		for i in 0 ..< m.bindingCount {
			if i > 0 do strings.write_string(sb, ", ")
			InputBinding_WriteJSON(sb, m.bindings[i])
		}
		strings.write_string(sb, "]}")
	}
	for &n in input.named do write(&sb, &first, n.name, &n.mapping)
	for a in InputAction {
		name := Builtin_ActionName(a)
		if Input_FindNamed(input, name) == nil do write(&sb, &first, name, &input.mappings[a])
	}
	strings.write_string(&sb, "\n]}\n")
	return strings.to_string(sb)
}

Input_SaveUserBindings :: proc(input: ^InputSystem) -> bool {
	path := Input_UserBindingsPath()
	_ = os.make_directory_all(filepath.dir(path, context.temp_allocator))
	return os.write_entire_file(path, transmute([]u8)Input_UserBindingsJSON(input)) == nil
}

// Input_LoadUserBindings applies saved player bindings (over the project's).
Input_LoadUserBindings :: proc(input: ^InputSystem) -> bool {
	data, err := os.read_entire_file(Input_UserBindingsPath(), context.temp_allocator)
	if err != nil do return false
	v, perr := json.parse(data, allocator = context.temp_allocator)
	if perr != nil do return false
	root, _ := v.(json.Object)
	arr, _ := root["actions"].(json.Array)
	for av in arr {
		ao, ok := av.(json.Object)
		if !ok do continue
		name, _ := ao["name"].(json.String)
		if Input_MappingOf(input, string(name)) == nil do continue // (no longer in the project)
		bindings := make([dynamic]InputBinding, context.temp_allocator)
		if barr, bok := ao["bindings"].(json.Array); bok {
			for bv in barr do if bo, isObj := bv.(json.Object); isObj {
				if b, bok2 := InputBinding_FromJSON(bo); bok2 do append(&bindings, b)
			}
		}
		Input_DefineAction(input, string(name), bindings[:])
	}
	return true
}

// Input_DeleteUserBindings forgets the saved player bindings (file).
Input_DeleteUserBindings :: proc() {
	_ = os.remove(Input_UserBindingsPath())
}

// --- Lua: Input.* rebinding ----------------------------------------------------------
// Input.get_bindings(action) -> {{device, name, positive, text}, ...}
// Input.binding_text(action [, slot]) -> "Space / A" (or one slot's)
// Input.set_binding(action, slot, binding | nil [, conflicts])   binding: {key = "SPACE"} | {mouse = "LEFT"} | {button = "RIGHT_FACE_DOWN"} | {axis = "LEFT_X", positive = true}
// Input.listen(action [, {slot, device, conflicts, cancel, on_done}]) / Input.is_listening() / Input.cancel_listen()
// Input.reset_bindings([action]) / Input.save_bindings() / Input.find_conflicts(binding) / Input.last_device()

lua_input :: proc(L: ^lua.State) -> ^InputSystem {
	sm := get_script_manager(L)
	return &sm.game.input if sm != nil && sm.game != nil else nil
}

@(private = "file")
binding_from_lua :: proc(L: ^lua.State, idx: c.int) -> (InputBinding, bool) {
	if lua.type(L, idx) != .TABLE do return {}, false
	obj := make(json.Object, 4, context.temp_allocator)
	for k in ([]cstring{"key", "mouse", "button", "axis"}) {
		lua.getfield(L, idx, k)
		if lua.type(L, -1) == .STRING do obj[string(k)] = json.String(strings.clone(string(lua.tostring(L, -1)), context.temp_allocator))
		lua.pop(L, 1)
	}
	lua.getfield(L, idx, "positive")
	obj["positive"] = json.Boolean(bool(lua.toboolean(L, -1)))
	lua.pop(L, 1)
	return InputBinding_FromJSON(obj)
}

@(private = "file")
push_binding :: proc(L: ^lua.State, b: InputBinding) {
	lua.createtable(L, 0, 4)
	dev, name := "key", ""
	switch b.deviceType {
	case .KeyboardKey:   dev, name = "key", enum_name(b.key)
	case .MouseButton:   dev, name = "mouse", enum_name(b.mouseButton)
	case .GamepadButton: dev, name = "button", enum_name(b.gamepadButton)
	case .GamepadAxis:   dev, name = "axis", enum_name(b.gamepadAxis)
	case .None:          dev = "none"
	}
	lua.pushstring(L, strings.clone_to_cstring(dev, context.temp_allocator))
	lua.setfield(L, -2, "device")
	lua.pushstring(L, strings.clone_to_cstring(name, context.temp_allocator))
	lua.setfield(L, -2, strings.clone_to_cstring(dev, context.temp_allocator)) // {key = "SPACE"} (set_binding takes it back)
	lua.pushstring(L, strings.clone_to_cstring(name, context.temp_allocator))
	lua.setfield(L, -2, "name")
	if b.deviceType == .GamepadAxis {
		lua.pushboolean(L, b32(b.axisPositive))
		lua.setfield(L, -2, "positive")
	}
	lua.pushstring(L, strings.clone_to_cstring(InputBinding_DisplayName(b), context.temp_allocator))
	lua.setfield(L, -2, "text")
}

@(private = "file")
lua_input_get_bindings :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	input := lua_input(L)
	m := Input_MappingOf(input, string(lua.tostring(L, 1))) if input != nil && lua.type(L, 1) == .STRING else nil
	lua.createtable(L, c.int(m.bindingCount if m != nil else 0), 0)
	if m != nil do for i in 0 ..< m.bindingCount {
		push_binding(L, m.bindings[i])
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

@(private = "file")
lua_input_binding_text :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	input := lua_input(L)
	m := Input_MappingOf(input, string(lua.tostring(L, 1))) if input != nil && lua.type(L, 1) == .STRING else nil
	sb := strings.builder_make(context.temp_allocator)
	if m != nil {
		slot := int(lua.tointeger(L, 2)) if lua.type(L, 2) == .NUMBER else 0
		if slot >= 1 {
			if slot <= m.bindingCount do strings.write_string(&sb, InputBinding_DisplayName(m.bindings[slot - 1]))
		} else {
			for i in 0 ..< m.bindingCount {
				if i > 0 do strings.write_string(&sb, " / ")
				strings.write_string(&sb, InputBinding_DisplayName(m.bindings[i]))
			}
		}
	}
	lua.pushstring(L, strings.clone_to_cstring(strings.to_string(sb) if strings.builder_len(sb) > 0 else "-", context.temp_allocator))
	return 1
}

@(private = "file")
conflicts_arg :: proc(L: ^lua.State, idx: c.int) -> Rebind_Conflicts {
	if lua.type(L, idx) != .STRING do return .Clear
	switch string(lua.tostring(L, idx)) {
	case "swap":  return .Swap
	case "allow": return .Allow
	}
	return .Clear
}

@(private = "file")
lua_input_set_binding :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	input := lua_input(L)
	if input == nil || lua.type(L, 1) != .STRING {
		lua.pushboolean(L, false)
		return 1
	}
	b, bok := binding_from_lua(L, 3) // nil: remove the slot
	if !bok && !lua.isnoneornil(L, 3) {
		// (Not a binding: change nothing rather than remove the slot.)
		lua.pushboolean(L, false)
		return 1
	}
	ok := Input_SetBinding(input, string(lua.tostring(L, 1)), int(lua.tointeger(L, 2)), b, conflicts_arg(L, 4))
	if ok && input.rebind.autoSave do Input_SaveUserBindings(input)
	lua.pushboolean(L, b32(ok))
	return 1
}

@(private = "file")
lua_input_listen :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	input := lua_input(L)
	if input == nil || lua.type(L, 1) != .STRING {
		lua.pushboolean(L, false)
		return 1
	}
	slot, device, conflicts, cancel := 0, Rebind_Device.Any, Rebind_Conflicts.Clear, rl.KeyboardKey.ESCAPE
	if lua.type(L, 2) == .TABLE {
		lua.getfield(L, 2, "slot"); slot = int(lua.tointeger(L, -1)); lua.pop(L, 1)
		lua.getfield(L, 2, "device")
		if lua.type(L, -1) == .STRING {
			switch string(lua.tostring(L, -1)) {
			case "keyboard", "mouse": device = .Keyboard_Mouse
			case "gamepad": device = .Gamepad
			}
		}
		lua.pop(L, 1)
		lua.getfield(L, 2, "conflicts"); conflicts = conflicts_arg(L, -1); lua.pop(L, 1)
		lua.getfield(L, 2, "cancel")
		if lua.type(L, -1) == .STRING do if k, kok := enum_parse(rl.KeyboardKey, string(lua.tostring(L, -1))); kok do cancel = k
		lua.pop(L, 1)
	}
	// A previous on_done that never ran is dropped.
	if input.rebind.callback != 0 {
		lua.L_unref(L, lua.REGISTRYINDEX, input.rebind.callback)
		input.rebind.callback = 0
	}
	ok := Input_RebindListen(input, string(lua.tostring(L, 1)), slot, device, conflicts, cancel)
	if ok && lua.type(L, 2) == .TABLE {
		lua.getfield(L, 2, "on_done")
		if lua.type(L, -1) != .FUNCTION { // (on_complete is the same: #327)
			lua.pop(L, 1)
			lua.getfield(L, 2, "on_complete")
		}
		if lua.type(L, -1) == .FUNCTION do input.rebind.callback = lua.L_ref(L, lua.REGISTRYINDEX)
		else do lua.pop(L, 1)
	}
	lua.pushboolean(L, b32(ok))
	return 1
}

// Input_RebindDispatch (each frame, after input): calls a finished listen's
// on_done(result, text).
Input_RebindDispatch :: proc(input: ^InputSystem, L: ^lua.State) {
	r := &input.rebind
	if r.callback == 0 || r.listening || r.result == .None do return
	ref := r.callback
	r.callback = 0
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(ref))
	lua.L_unref(L, lua.REGISTRYINDEX, ref)
	lua.pushstring(L, "bound" if r.result == .Bound else "cancelled")
	lua.pushstring(L, strings.clone_to_cstring(InputBinding_DisplayName(r.bound) if r.result == .Bound else "", context.temp_allocator))
	if lua.pcall(L, 2, 0, 0) != 0 {
		Script_Problem(.Error, "Input.listen on_done: %s", lua.tostring(L, -1))
		lua.pop(L, 1)
	}
}

@(private = "file")
lua_input_is_listening :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	input := lua_input(L)
	lua.pushboolean(L, b32(input != nil && input.rebind.listening))
	return 1
}

@(private = "file")
lua_input_cancel_listen :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if input := lua_input(L); input != nil do Input_RebindCancel(input)
	return 0
}

@(private = "file")
lua_input_reset_bindings :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	input := lua_input(L)
	if input == nil do return 0
	Input_RebindReset(input, string(lua.tostring(L, 1)) if lua.type(L, 1) == .STRING else "")
	if input.rebind.autoSave do Input_SaveUserBindings(input)
	return 0
}

@(private = "file")
lua_input_save_bindings :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	input := lua_input(L)
	lua.pushboolean(L, b32(input != nil && Input_SaveUserBindings(input)))
	return 1
}

@(private = "file")
lua_input_find_conflicts :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	input := lua_input(L)
	b, ok := binding_from_lua(L, 1)
	names := Input_Conflicts(input, b) if input != nil && ok else nil
	lua.createtable(L, c.int(len(names)), 0)
	for n, i in names {
		lua.pushstring(L, strings.clone_to_cstring(n, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

@(private = "file")
lua_input_last_device :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	input := lua_input(L)
	lua.pushstring(L, "gamepad" if input != nil && input.rebind.lastDevice == .Gamepad else "keyboard")
	return 1
}

@(private = "file")
lua_input_get_actions :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	input := lua_input(L)
	n := len(input.rebind.defaults) if input != nil else 0
	lua.createtable(L, c.int(n), 0)
	if input != nil do for a, i in input.rebind.defaults {
		lua.pushstring(L, strings.clone_to_cstring(a.name, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

// Script_RegisterRebindBindings adds the rebinding functions to the Input
// table (on the stack).
Script_RegisterRebindBindings :: proc(L: ^lua.State) {
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "get_bindings", lua_input_get_bindings)
	reg(L, "get_binding_text", lua_input_binding_text)
	Lua_SetDeprecated(L, lua_input_binding_text, "binding_text", "Input.get_binding_text")
	reg(L, "set_binding", lua_input_set_binding)
	reg(L, "listen", lua_input_listen)
	reg(L, "is_listening", lua_input_is_listening)
	reg(L, "cancel_listen", lua_input_cancel_listen)
	reg(L, "reset_bindings", lua_input_reset_bindings)
	reg(L, "save_bindings", lua_input_save_bindings)
	reg(L, "find_conflicts", lua_input_find_conflicts)
	reg(L, "get_last_device", lua_input_last_device)
	Lua_SetDeprecated(L, lua_input_last_device, "last_device", "Input.get_last_device")
	reg(L, "get_actions", lua_input_get_actions)
}
