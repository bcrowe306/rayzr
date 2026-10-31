package engine

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// TIER 1: Logical Game Actions & Action States
// ============================================================================

InputAction :: enum {
	MoveUp,
	MoveDown,
	MoveLeft,
	MoveRight,
	Jump,
	Fire,
	SecondaryAction,
	Boost,
	Interact,
	Pause,
	Confirm,
	Cancel,
	Custom1,
	Custom2,
	Custom3,
	Custom4,
}

ActionState :: struct {
	pressed:      bool, // True only on the frame the action transitioned from up -> down
	down:         bool, // True while the action is held down
	released:     bool, // True only on the frame the action transitioned from down -> up
	value:        f32,  // Analog/digital strength in [0.0, 1.0]
	durationHeld: f32,  // Seconds the action has been continuously held down
}

// ============================================================================
// TIER 2: Physical Hardware Input Bindings & Action-to-Key Mapping Table
// ============================================================================

MAX_BINDINGS_PER_ACTION :: 4

InputDeviceType :: enum {
	None,
	KeyboardKey,
	MouseButton,
	GamepadButton,
	GamepadAxis,
}

InputBinding :: struct {
	deviceType:        InputDeviceType,
	key:               rl.KeyboardKey,
	mouseButton:       rl.MouseButton,
	gamepadButton:     rl.GamepadButton,
	gamepadAxis:       rl.GamepadAxis,
	axisPositive:      bool, // True for +axis direction, False for -axis direction
	axisDeadzone:      f32,  // Deadzone threshold in [0.05, 0.95]
}

ActionMapping :: struct {
	bindings:     [MAX_BINDINGS_PER_ACTION]InputBinding,
	bindingCount: int,
}

InputSystem :: struct {
	mappings:      [InputAction]ActionMapping,
	states:        [InputAction]ActionState,
	gamepadIndex:  i32 `gui:"true" min:"0" max:"3"`,
	enabled:       bool `gui:"true"`,

	// Optional simulated physical/logical states for headless unit testing
	simulatedKeysDown:    map[rl.KeyboardKey]bool,
	// The simulated keys as of this frame's update and the one before
	// (is_key_pressed / is_key_released on simulated input).
	simulatedKeysNow:     map[rl.KeyboardKey]bool,
	simulatedKeysPrev:    map[rl.KeyboardKey]bool,
	simulatedMouseDown:   map[rl.MouseButton]bool,
	simulatedActionsDown: [InputAction]bool,
	simulatedActionVals:  [InputAction]f32,
	useSimulatedInput:    bool,
	mouseBlocked:         bool, // a UI widget has the mouse: mouse bindings read up (#228)
	keyboardBlocked:      bool, // the developer console is open: key bindings read up (#285)

	// Project-defined actions (input_actions.odin).
	named: [dynamic]Named_Action,

	// Players 2-4, gamepads, hot-plug, rumble (input_players.odin).
	pads: Input_Pads,

	// Player rebinding (input_rebind.odin).
	rebind: Input_Rebind,

	// Fingers, gestures, on-screen controls' actions (touch.odin).
	touch: Input_Touch,
	// (Older UIs read these: they mirror `rebind` for built-in actions.)
	isListeningForRebind: bool,
	rebindTargetAction:   InputAction,
}

// ============================================================================
// Initialization & Default Action-to-Key Mapping Table
// ============================================================================

InputSystem_Init :: proc(input: ^InputSystem) {
	if input == nil do return
	input.enabled = true
	input.gamepadIndex = 0
	input.useSimulatedInput = false
	input.touch.asMouse = true
	input.touch.pinchIds = {-1, -1}
	Input_PadsInit(input)
	Input_ResetDefaultBindings(input)
}

InputSystem_Destroy :: proc(input: ^InputSystem) {
	if input == nil do return
	Input_ClearNamed(input)
	delete(input.named)
	input.named = nil
	Input_RebindDestroy(input)
	Input_PadsDestroy(input)
	Input_TouchDestroy(input)
	if input.simulatedKeysDown != nil {
		delete(input.simulatedKeysDown)
		input.simulatedKeysDown = nil
	}
	if input.simulatedMouseDown != nil {
		delete(input.simulatedMouseDown)
		input.simulatedMouseDown = nil
	}
	delete(input.simulatedKeysNow)
	delete(input.simulatedKeysPrev)
	input.simulatedKeysNow, input.simulatedKeysPrev = nil, nil
}

Input_ResetDefaultBindings :: proc(input: ^InputSystem) {
	if input == nil do return

	for action in InputAction {
		Input_ClearActionBindings(input, action)
		input.states[action] = {}
	}

	// Movement: WASD + Arrow Keys + Gamepad Left Stick & D-Pad
	Input_BindKey(input, .MoveUp, .W)
	Input_BindKey(input, .MoveUp, .UP)
	Input_BindGamepadButton(input, .MoveUp, .LEFT_FACE_UP)
	Input_BindGamepadAxis(input, .MoveUp, .LEFT_Y, false, 0.25)

	Input_BindKey(input, .MoveDown, .S)
	Input_BindKey(input, .MoveDown, .DOWN)
	Input_BindGamepadButton(input, .MoveDown, .LEFT_FACE_DOWN)
	Input_BindGamepadAxis(input, .MoveDown, .LEFT_Y, true, 0.25)

	Input_BindKey(input, .MoveLeft, .A)
	Input_BindKey(input, .MoveLeft, .LEFT)
	Input_BindGamepadButton(input, .MoveLeft, .LEFT_FACE_LEFT)
	Input_BindGamepadAxis(input, .MoveLeft, .LEFT_X, false, 0.25)

	Input_BindKey(input, .MoveRight, .D)
	Input_BindKey(input, .MoveRight, .RIGHT)
	Input_BindGamepadButton(input, .MoveRight, .LEFT_FACE_RIGHT)
	Input_BindGamepadAxis(input, .MoveRight, .LEFT_X, true, 0.25)

	// Jump: Space + Gamepad South Face Button (A / Cross)
	Input_BindKey(input, .Jump, .SPACE)
	Input_BindGamepadButton(input, .Jump, .RIGHT_FACE_DOWN)

	// Fire / Primary Action: Space + Left Mouse Button + Gamepad Right Face / Trigger
	Input_BindKey(input, .Fire, .SPACE)
	Input_BindMouseButton(input, .Fire, .LEFT)
	Input_BindGamepadButton(input, .Fire, .RIGHT_FACE_LEFT)

	// Secondary Action: Right Mouse Button + Left Control + Gamepad East Face
	Input_BindMouseButton(input, .SecondaryAction, .RIGHT)
	Input_BindKey(input, .SecondaryAction, .LEFT_CONTROL)
	Input_BindGamepadButton(input, .SecondaryAction, .RIGHT_FACE_RIGHT)

	// Boost / Sprint: Left Shift + Right Shift + Gamepad Left Trigger/Shoulder
	Input_BindKey(input, .Boost, .LEFT_SHIFT)
	Input_BindKey(input, .Boost, .RIGHT_SHIFT)
	Input_BindGamepadButton(input, .Boost, .LEFT_TRIGGER_1)

	// Interact: E + F + Gamepad North Face
	Input_BindKey(input, .Interact, .E)
	Input_BindKey(input, .Interact, .F)
	Input_BindGamepadButton(input, .Interact, .RIGHT_FACE_UP)

	// Pause: Escape + P + Gamepad Middle Right (Start)
	Input_BindKey(input, .Pause, .ESCAPE)
	Input_BindKey(input, .Pause, .P)
	Input_BindGamepadButton(input, .Pause, .MIDDLE_RIGHT)

	// UI Confirm / Cancel
	Input_BindKey(input, .Confirm, .ENTER)
	Input_BindKey(input, .Confirm, .SPACE)
	Input_BindKey(input, .Cancel, .ESCAPE)
	Input_BindKey(input, .Cancel, .BACKSPACE)
}

// ============================================================================
// Rebinding & Mapping Modification API
// ============================================================================

Input_ClearActionBindings :: proc(input: ^InputSystem, action: InputAction) {
	if input == nil do return
	input.mappings[action].bindingCount = 0
	for i in 0..<MAX_BINDINGS_PER_ACTION {
		input.mappings[action].bindings[i] = {}
	}
}

Input_AddBinding :: proc(input: ^InputSystem, action: InputAction, binding: InputBinding, clearExisting: bool = false) -> bool {
	if input == nil do return false
	if clearExisting {
		Input_ClearActionBindings(input, action)
	}
	mapping := &input.mappings[action]
	// Avoid duplicate identical bindings
	for i in 0..<mapping.bindingCount {
		b := mapping.bindings[i]
		if b.deviceType == binding.deviceType {
			switch b.deviceType {
			case .None:
			case .KeyboardKey:
				if b.key == binding.key do return true
			case .MouseButton:
				if b.mouseButton == binding.mouseButton do return true
			case .GamepadButton:
				if b.gamepadButton == binding.gamepadButton do return true
			case .GamepadAxis:
				if b.gamepadAxis == binding.gamepadAxis && b.axisPositive == binding.axisPositive do return true
			}
		}
	}
	if mapping.bindingCount >= MAX_BINDINGS_PER_ACTION {
		// Replace last slot if full
		mapping.bindings[MAX_BINDINGS_PER_ACTION - 1] = binding
		return true
	}
	mapping.bindings[mapping.bindingCount] = binding
	mapping.bindingCount += 1
	return true
}

Input_BindKey :: proc(input: ^InputSystem, action: InputAction, key: rl.KeyboardKey, clearExisting: bool = false) -> bool {
	return Input_AddBinding(input, action, InputBinding{
		deviceType = .KeyboardKey,
		key        = key,
	}, clearExisting)
}

Input_BindMouseButton :: proc(input: ^InputSystem, action: InputAction, button: rl.MouseButton, clearExisting: bool = false) -> bool {
	return Input_AddBinding(input, action, InputBinding{
		deviceType  = .MouseButton,
		mouseButton = button,
	}, clearExisting)
}

Input_BindGamepadButton :: proc(input: ^InputSystem, action: InputAction, button: rl.GamepadButton, clearExisting: bool = false) -> bool {
	return Input_AddBinding(input, action, InputBinding{
		deviceType    = .GamepadButton,
		gamepadButton = button,
	}, clearExisting)
}

Input_BindGamepadAxis :: proc(
	input: ^InputSystem,
	action: InputAction,
	axis: rl.GamepadAxis,
	positiveDirection: bool,
	deadzone: f32 = 0.25,
	clearExisting: bool = false,
) -> bool {
	return Input_AddBinding(input, action, InputBinding{
		deviceType   = .GamepadAxis,
		gamepadAxis  = axis,
		axisPositive = positiveDirection,
		axisDeadzone = clamp(deadzone, 0.05, 0.95),
	}, clearExisting)
}

// Start interactive rebind mode for a built-in action (the next input
// replaces its binding of the same device kind; input_rebind.odin).
Input_StartRebind :: proc(input: ^InputSystem, action: InputAction) {
	if input == nil do return
	Input_RebindListen(input, Builtin_ActionName(action))
	input.rebindTargetAction = action
	input.isListeningForRebind = true
}

// Format human-readable binding list for an action (using temp allocator)
Input_GetActionBindingsString :: proc(input: ^InputSystem, action: InputAction) -> string {
	if input == nil do return "Unbound"
	mapping := &input.mappings[action]
	if mapping.bindingCount == 0 do return "Unbound"

	b := strings.builder_make(context.temp_allocator)
	written := 0
	for i in 0..<mapping.bindingCount {
		bind := mapping.bindings[i]
		label := ""
		switch bind.deviceType {
		case .None:
		case .KeyboardKey:
			label = fmt.tprintf("%v", bind.key)
		case .MouseButton:
			label = fmt.tprintf("Mouse %v", bind.mouseButton)
		case .GamepadButton:
			label = fmt.tprintf("Pad %v", bind.gamepadButton)
		case .GamepadAxis:
			dir := "+" if bind.axisPositive else "-"
			label = fmt.tprintf("Axis %s%v", dir, bind.gamepadAxis)
		}
		if label != "" {
			if written > 0 {
				strings.write_string(&b, " / ")
			}
			strings.write_string(&b, label)
			written += 1
		}
	}
	return strings.to_string(b)
}

// ============================================================================
// Simulation Helpers (for Headless Unit Tests)
// ============================================================================

Input_SetSimulatedKey :: proc(input: ^InputSystem, key: rl.KeyboardKey, isDown: bool) {
	if input == nil do return
	input.useSimulatedInput = true
	if input.simulatedKeysDown == nil {
		input.simulatedKeysDown = make(map[rl.KeyboardKey]bool)
	}
	input.simulatedKeysDown[key] = isDown
}

Input_SetSimulatedMouseButton :: proc(input: ^InputSystem, button: rl.MouseButton, isDown: bool) {
	if input == nil do return
	input.useSimulatedInput = true
	if input.simulatedMouseDown == nil {
		input.simulatedMouseDown = make(map[rl.MouseButton]bool)
	}
	input.simulatedMouseDown[button] = isDown
}

Input_SetSimulatedAction :: proc(input: ^InputSystem, action: InputAction, isDown: bool, value: f32 = 1.0) {
	if input == nil do return
	input.useSimulatedInput = true
	input.simulatedActionsDown[action] = isDown
	input.simulatedActionVals[action] = value if isDown else 0.0
}

// Input_SimulatedKeyPressed / Released: a simulated key went down / up
// between the last two updates.
Input_SimulatedKeyPressed :: proc(input: ^InputSystem, key: rl.KeyboardKey) -> bool {
	return input.simulatedKeysNow[key] && !input.simulatedKeysPrev[key]
}

Input_SimulatedKeyReleased :: proc(input: ^InputSystem, key: rl.KeyboardKey) -> bool {
	return !input.simulatedKeysNow[key] && input.simulatedKeysPrev[key]
}

Input_ClearSimulatedInputs :: proc(input: ^InputSystem) {
	if input == nil do return
	if input.simulatedKeysDown != nil {
		clear(&input.simulatedKeysDown)
	}
	if input.simulatedMouseDown != nil {
		clear(&input.simulatedMouseDown)
	}
	for action in InputAction {
		input.simulatedActionsDown[action] = false
		input.simulatedActionVals[action] = 0.0
	}
}

// ============================================================================
// Step 3: Poll and Update Input Once Per Frame
// ============================================================================

Input_EvaluateBinding :: proc(input: ^InputSystem, bind: InputBinding) -> (isDown: bool, strength: f32) {
	return Input_EvaluateBindingFor(input, bind, input.gamepadIndex, true)
}

// Input_EvaluateBindingFor: a binding for a player's pad (-1: none) and,
// for player 1, the keyboard + mouse.
Input_EvaluateBindingFor :: proc(input: ^InputSystem, bind: InputBinding, pad: i32, keyboard: bool) -> (isDown: bool, strength: f32) {
	switch bind.deviceType {
	case .None:
		return false, 0.0

	case .KeyboardKey:
		if !keyboard do return false, 0
		if input.useSimulatedInput && input.simulatedKeysDown != nil {
			if down, ok := input.simulatedKeysDown[bind.key]; ok && down {
				return true, 1.0
			}
		}
		if !input.keyboardBlocked && rl.IsWindowReady() && rl.IsKeyDown(bind.key) {
			return true, 1.0
		}

	case .MouseButton:
		if !keyboard do return false, 0
		if input.useSimulatedInput && input.simulatedMouseDown != nil {
			if down, ok := input.simulatedMouseDown[bind.mouseButton]; ok && down {
				return true, 1.0
			}
		}
		if game := touch_mouse_game; game != nil && game.touchMouse.active && bind.mouseButton == .LEFT && !input.mouseBlocked {
			if game.touchMouse.down do return true, 1.0 // (a finger is the left button)
		}
		if !input.mouseBlocked && rl.IsWindowReady() && rl.IsMouseButtonDown(bind.mouseButton) {
			return true, 1.0
		}

	case .GamepadButton:
		if Input_PadButtonDown(input, pad, bind.gamepadButton) {
			return true, 1.0
		}

	case .GamepadAxis:
		if Input_PadConnected(input, pad) {
			rawVal := Input_PadAxis(input, pad, bind.gamepadAxis)
			dz := bind.axisDeadzone if bind.axisDeadzone > 0 else 0.25
			if bind.axisPositive && rawVal > dz {
				norm := clamp((rawVal - dz) / (1.0 - dz), 0.0, 1.0)
				return true, norm
			} else if !bind.axisPositive && rawVal < -dz {
				norm := clamp((-rawVal - dz) / (1.0 - dz), 0.0, 1.0)
				return true, norm
			}
		}
	}
	return false, 0.0
}

InputSystem_Update :: proc(input: ^InputSystem, deltaTime: f32) {
	if input == nil do return

	if !input.enabled {
		for action in InputAction {
			input.states[action] = {}
		}
		return
	}

	// Simulated keys: last frame's and this frame's (pressed / released).
	if input.useSimulatedInput {
		input.simulatedKeysPrev, input.simulatedKeysNow = input.simulatedKeysNow, input.simulatedKeysPrev
		clear(&input.simulatedKeysNow)
		for k, down in input.simulatedKeysDown do if down do input.simulatedKeysNow[k] = true
	}

	// Player rebinding: capture the next input while listening (input_rebind.odin).
	Input_RebindUpdate(input)
	input.isListeningForRebind = input.rebind.listening

	// Poll all physical bindings for each logical action and compute new ActionState
	for action in InputAction {
		prevState := input.states[action]
		currentDown := false
		maxStrength: f32 = 0.0

		// 1. Check direct logical action simulation (for headless tests)
		if input.useSimulatedInput && input.simulatedActionsDown[action] {
			currentDown = true
			simVal := input.simulatedActionVals[action]
			maxStrength = simVal if simVal > 0.0 else 1.0
		}

		// On-screen controls (touch_controls.odin).
		if tv := Input_TouchAction(input, Builtin_ActionName(action)); tv > 0 {
			currentDown = true
			maxStrength = max(maxStrength, tv)
		}

		// 2. Check all physical hardware bindings mapped to this action
		mapping := &input.mappings[action]
		for i in 0..<mapping.bindingCount {
			bDown, bStrength := Input_EvaluateBinding(input, mapping.bindings[i])
			if bDown {
				currentDown = true
				if bStrength > maxStrength {
					maxStrength = bStrength
				}
			}
		}

		newState := ActionState{
			pressed      = currentDown && !prevState.down,
			down         = currentDown,
			released     = !currentDown && prevState.down,
			value        = maxStrength if currentDown else 0.0,
			durationHeld = (prevState.durationHeld + deltaTime) if currentDown else 0.0,
		}
		input.states[action] = newState
	}
	Input_UpdateNamed(input, deltaTime)
	Input_UpdatePlayers(input, deltaTime)
}

// ============================================================================
// Step 4: Query Actions in Game Logic (Overloaded for InputSystem, Game, GameContext)
// ============================================================================

IsActionPressed_Input :: proc(input: ^InputSystem, action: InputAction) -> bool {
	if input == nil do return false
	return input.states[action].pressed
}
IsActionPressed_Game :: proc(game: ^Game, action: InputAction) -> bool {
	if game == nil do return false
	return game.input.states[action].pressed
}
IsActionPressed_Context :: proc(ctx: ^GameContext, action: InputAction) -> bool {
	if ctx == nil || ctx.game == nil do return false
	return ctx.game.input.states[action].pressed
}
IsActionPressed :: proc {
	IsActionPressed_Input,
	IsActionPressed_Game,
	IsActionPressed_Context,
}

IsPlayerActionPressed_Input :: proc(input: ^InputSystem, action: InputAction, player: int) -> bool {
	if input == nil || player < 1 || player > MAX_PLAYERS do return false
	if player == 1 do return input.states[action].pressed
	return input.pads.players[player - 1].states[action].pressed
}
IsPlayerActionPressed_Game :: proc(game: ^Game, action: InputAction, player: int) -> bool {
	if game == nil do return false
	return IsPlayerActionPressed_Input(&game.input, action, player)
}
IsPlayerActionPressed_Context :: proc(ctx: ^GameContext, action: InputAction, player: int) -> bool {
	if ctx == nil || ctx.game == nil do return false
	return IsPlayerActionPressed_Input(&ctx.game.input, action, player)
}
IsPlayerActionPressed :: proc {
	IsPlayerActionPressed_Input,
	IsPlayerActionPressed_Game,
	IsPlayerActionPressed_Context,
}

IsActionDown_Input :: proc(input: ^InputSystem, action: InputAction) -> bool {
	if input == nil do return false
	return input.states[action].down
}
IsActionDown_Game :: proc(game: ^Game, action: InputAction) -> bool {
	if game == nil do return false
	return game.input.states[action].down
}
IsActionDown_Context :: proc(ctx: ^GameContext, action: InputAction) -> bool {
	if ctx == nil || ctx.game == nil do return false
	return ctx.game.input.states[action].down
}
IsActionDown :: proc {
	IsActionDown_Input,
	IsActionDown_Game,
	IsActionDown_Context,
}

IsActionReleased_Input :: proc(input: ^InputSystem, action: InputAction) -> bool {
	if input == nil do return false
	return input.states[action].released
}
IsActionReleased_Game :: proc(game: ^Game, action: InputAction) -> bool {
	if game == nil do return false
	return game.input.states[action].released
}
IsActionReleased_Context :: proc(ctx: ^GameContext, action: InputAction) -> bool {
	if ctx == nil || ctx.game == nil do return false
	return ctx.game.input.states[action].released
}
IsActionReleased :: proc {
	IsActionReleased_Input,
	IsActionReleased_Game,
	IsActionReleased_Context,
}

GetActionValue_Input :: proc(input: ^InputSystem, action: InputAction) -> f32 {
	if input == nil do return 0.0
	return input.states[action].value
}
GetActionValue_Game :: proc(game: ^Game, action: InputAction) -> f32 {
	if game == nil do return 0.0
	return game.input.states[action].value
}
GetActionValue_Context :: proc(ctx: ^GameContext, action: InputAction) -> f32 {
	if ctx == nil || ctx.game == nil do return 0.0
	return ctx.game.input.states[action].value
}
GetActionValue :: proc {
	GetActionValue_Input,
	GetActionValue_Game,
	GetActionValue_Context,
}

GetActionState_Input :: proc(input: ^InputSystem, action: InputAction) -> ActionState {
	if input == nil do return {}
	return input.states[action]
}
GetActionState_Game :: proc(game: ^Game, action: InputAction) -> ActionState {
	if game == nil do return {}
	return game.input.states[action]
}
GetActionState_Context :: proc(ctx: ^GameContext, action: InputAction) -> ActionState {
	if ctx == nil || ctx.game == nil do return {}
	return ctx.game.input.states[action]
}
GetActionState :: proc {
	GetActionState_Input,
	GetActionState_Game,
	GetActionState_Context,
}

// Returns a 1D axis in [-1.0, 1.0] from a pair of negative and positive logical actions
GetActionAxis_Input :: proc(input: ^InputSystem, negativeAction, positiveAction: InputAction) -> f32 {
	if input == nil do return 0.0
	return clamp(input.states[positiveAction].value - input.states[negativeAction].value, -1.0, 1.0)
}
GetActionAxis_Game :: proc(game: ^Game, negativeAction, positiveAction: InputAction) -> f32 {
	if game == nil do return 0.0
	return GetActionAxis_Input(&game.input, negativeAction, positiveAction)
}
GetActionAxis_Context :: proc(ctx: ^GameContext, negativeAction, positiveAction: InputAction) -> f32 {
	if ctx == nil || ctx.game == nil do return 0.0
	return GetActionAxis_Input(&ctx.game.input, negativeAction, positiveAction)
}
GetActionAxis :: proc {
	GetActionAxis_Input,
	GetActionAxis_Game,
	GetActionAxis_Context,
}

GetPlayerActionAxis_Input :: proc(input: ^InputSystem, negativeAction, positiveAction: InputAction, player: int) -> f32 {
	if input == nil || player < 1 || player > MAX_PLAYERS do return 0.0
	if player == 1 {
		return clamp(input.states[positiveAction].value - input.states[negativeAction].value, -1.0, 1.0)
	}
	p := &input.pads.players[player - 1]
	return clamp(p.states[positiveAction].value - p.states[negativeAction].value, -1.0, 1.0)
}
GetPlayerActionAxis_Game :: proc(game: ^Game, negativeAction, positiveAction: InputAction, player: int) -> f32 {
	if game == nil do return 0.0
	return GetPlayerActionAxis_Input(&game.input, negativeAction, positiveAction, player)
}
GetPlayerActionAxis_Context :: proc(ctx: ^GameContext, negativeAction, positiveAction: InputAction, player: int) -> f32 {
	if ctx == nil || ctx.game == nil do return 0.0
	return GetPlayerActionAxis_Input(&ctx.game.input, negativeAction, positiveAction, player)
}
GetPlayerActionAxis :: proc {
	GetPlayerActionAxis_Input,
	GetPlayerActionAxis_Game,
	GetPlayerActionAxis_Context,
}

// Returns a 2D vector from 4 directional actions (e.g., .MoveLeft, .MoveRight, .MoveUp, .MoveDown)
GetActionVector2_Input :: proc(
	input: ^InputSystem,
	leftAction: InputAction = .MoveLeft,
	rightAction: InputAction = .MoveRight,
	upAction: InputAction = .MoveUp,
	downAction: InputAction = .MoveDown,
	normalize: bool = false,
) -> [2]f32 {
	if input == nil do return {0, 0}
	vec := [2]f32{
		GetActionAxis_Input(input, leftAction, rightAction),
		GetActionAxis_Input(input, upAction, downAction),
	}
	if normalize {
		lenSq := vec.x * vec.x + vec.y * vec.y
		if lenSq > 1.0 {
			invLen := 1.0 / math.sqrt(lenSq)
			vec *= invLen
		}
	}
	return vec
}
GetActionVector2_Game :: proc(
	game: ^Game,
	leftAction: InputAction = .MoveLeft,
	rightAction: InputAction = .MoveRight,
	upAction: InputAction = .MoveUp,
	downAction: InputAction = .MoveDown,
	normalize: bool = false,
) -> [2]f32 {
	if game == nil do return {0, 0}
	return GetActionVector2_Input(&game.input, leftAction, rightAction, upAction, downAction, normalize)
}
GetActionVector2_Context :: proc(
	ctx: ^GameContext,
	leftAction: InputAction = .MoveLeft,
	rightAction: InputAction = .MoveRight,
	upAction: InputAction = .MoveUp,
	downAction: InputAction = .MoveDown,
	normalize: bool = false,
) -> [2]f32 {
	if ctx == nil || ctx.game == nil do return {0, 0}
	return GetActionVector2_Input(&ctx.game.input, leftAction, rightAction, upAction, downAction, normalize)
}
GetActionVector2 :: proc {
	GetActionVector2_Input,
	GetActionVector2_Game,
	GetActionVector2_Context,
}
