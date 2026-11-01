package engine

import "core:math"
import "core:strings"
import "core:math/noise"
import "core:math/rand"
import rl "vendor:raylib"

// ============================================================================
// ProCam2D-inspired Camera Enums & Configurations
// ============================================================================

CameraFollowMode :: enum {
	Static,
	SingleTarget,
	MultiTarget,
	Manual,
}

CameraDragType :: enum {
	None,
	SmoothDamp,
	SpringDamp,
	LookAhead,
	AutoSpeed,
}

CameraShakeType :: enum {
	Vertical,
	Horizontal,
	Random,
	Perlin,
	Rotate,
	Circular,
	Zoom,
}

CameraShakePreset :: enum {
	Custom,
	Gunshot,
	Earthquake,
	Handheld,
	Explosion,
	Impact,
	Rumble,
	Vibration,
	Wobbly,
}

CameraRoomSide :: enum {
	Left,
	Right,
	Top,
	Bottom,
}
CameraRoomSides :: bit_set[CameraRoomSide]

CameraMagnetShape :: enum {
	Circle,
	Rectangle,
}

CameraMagnetMode :: enum {
	Attract,
	Repel,
}

// ============================================================================
// Influence & Constraint Structs
// ============================================================================

CameraTarget :: struct {
	node:              ^Node,
	position:          [2]f32,
	offset:            [2]f32,
	priority:          int,
	influence:         [2]f32,
	rotationInfluence: f32,
	radius:            f32,
	enabled:           bool,
	prevPosition:      [2]f32,
	velocity:          [2]f32,
}

CameraRoom :: struct {
	id:        string,
	rect:      rl.Rectangle,
	zoom:      f32,
	priority:  int,
	openSides: CameraRoomSides,
	enabled:   bool,
}

CameraMagnet :: struct {
	id:           string,
	position:     [2]f32,
	shape:        CameraMagnetShape,
	mode:         CameraMagnetMode,
	radius:       f32,
	size:         [2]f32,
	force:        f32,
	useFullForce: bool,
	enabled:      bool,
}

CameraCinematicPoint :: struct {
	id:             string,
	position:       [2]f32,
	zoom:           f32,
	rotation:       f32,
	holdTime:       f32,
	dragSpeed:      [2]f32,
	zoomSpeed:      f32,
	rotationSpeed:  f32,
}

// ============================================================================
// CameraNode Definition
// ============================================================================

CameraNode :: struct {
	using node: Node,

	// Active status & layers
	isCurrent:    bool `gui:"true"`,
	targetLayers: bit_set[RenderLayer],

	// Follow & drag modes
	followMode: CameraFollowMode `gui:"true"`,
	dragType:   CameraDragType `gui:"true"`,

	// Target tracking
	// followTarget: the node to follow, as a path relative to the camera
	// ("../Player"), saved with the scene ("follow") and resolved when the
	// camera becomes ready (retried until the node exists, e.g. spawned).
	followTarget:    string,
	followResolved:  bool,
	target:          ^Node,
	targets:         [dynamic]CameraTarget,
	targetPosition:  [2]f32 `gui:"true"`,
	currentPosition: [2]f32 `gui:"true" save:"false"`,
	currentVelocity: [2]f32,
	targetVelocity:  [2]f32,
	prevTargetPos:   [2]f32,

	// Smoothing settings
	smoothDrag:      bool `gui:"true"`,
	smoothDragSpeed: [2]f32 `gui:"true"`,
	springConstant:  f32 `gui:"true" min:"1" max:"100"`,
	dampingRatio:    f32 `gui:"true" min:"0.1" max:"5"`,
	predictionTime:  [2]f32 `gui:"true"`,
	maxDistance:     [2]f32 `gui:"true"`,

	// Offset & pan
	offset:                [2]f32 `gui:"true"`,
	smoothOffset:          bool `gui:"true"`,
	smoothOffsetSpeed:     f32 `gui:"true" min:"0.1" max:"20"`,
	currentOffset:         [2]f32,
	currentOffsetVelocity: [2]f32,
	screenOffset:          [2]f32 `gui:"true"`,
	customScreenOffset:    bool `gui:"true"`,

	// Rotation
	currentRotation:         f32 `gui:"true" min:"-360" max:"360" save:"false"`,
	targetRotation:          f32 `gui:"true" min:"-360" max:"360"`,
	allowRotation:           bool `gui:"true"`,
	smoothRotation:          bool `gui:"true"`,
	smoothRotationSpeed:     f32 `gui:"true" min:"0.1" max:"20"`,
	currentRotationVelocity: f32,

	// Zoom
	zoom:                f32 `gui:"true" min:"0.01" max:"50" save:"false"`, // now; Target Zoom is the setting
	currentZoom:         f32,
	targetZoom:          f32 `gui:"true" min:"0.01" max:"50"`,
	smoothZoom:          bool `gui:"true"`,
	smoothZoomSpeed:     f32 `gui:"true" min:"0.1" max:"20"`,
	currentZoomVelocity: f32,
	minZoom:             f32 `gui:"true" min:"0.01" max:"10"`,
	maxZoom:             f32 `gui:"true" min:"0.1" max:"50"`,
	autoZoom:            bool `gui:"true"`,
	zoomMargin:          f32 `gui:"true" min:"0" max:"1"`,

	// Boundaries / Limits
	hasLimits:   bool `gui:"true"`,
	smoothLimit: bool `gui:"true"`,
	leftLimit:   f32 `gui:"true"`,
	rightLimit:  f32 `gui:"true"`,
	topLimit:    f32 `gui:"true"`,
	bottomLimit: f32 `gui:"true"`,

	// Margins / Deadzones
	useHMargins:  bool `gui:"true"`,
	useVMargins:  bool `gui:"true"`,
	leftMargin:   f32 `gui:"true" min:"0" max:"0.5"`,
	rightMargin:  f32 `gui:"true" min:"0" max:"0.5"`,
	topMargin:    f32 `gui:"true" min:"0" max:"0.5"`,
	bottomMargin: f32 `gui:"true" min:"0" max:"0.5"`,

	// Pointer / Mouse Follow Influence
	enableMouseFollow: bool `gui:"true"`,
	mouseInfluence:    [2]f32 `gui:"true"`,

	// Screen Shake
	shakePreset:    CameraShakePreset `gui:"true"`,
	shakeTypes:     bit_set[CameraShakeType] `gui:"true"`,
	isShaking:      bool `gui:"true" save:"false"`,
	shakeSpeed:     f32 `gui:"true"`,
	shakeIntensity: f32 `gui:"true"`,
	shakeTrauma:    f32 `gui:"true"`,
	shakeAttack:     f32,
	shakeDuration:   f32,
	shakeDecay:      f32,
	shakeElapsed:    f32,
	shakeEndless:    bool,
	shakeOffset:     [2]f32,
	shakeRotation:   f32,
	shakeZoom:       f32,
	// The shake playing (CameraNode_Shake); the settings above stay as set.
	activeShakeIntensity: f32,
	activeShakeSpeed:     f32,
	activeShakeTypes:     bit_set[CameraShakeType],

	// Rooms & Magnets
	rooms:   [dynamic]CameraRoom,
	magnets: [dynamic]CameraMagnet,

	// Cinematics
	cinematics:            [dynamic]CameraCinematicPoint,
	playingCinematic:      bool,
	activeCinematicId:     string,
	currentCinematicIndex: int,
	cinematicHoldTimer:    f32,

	// Viewport size cache
	viewportSize: [2]f32,
}

// ============================================================================
// Mathematical Helpers (Adapted from ProCam2D PCamUtils)
// ============================================================================

Camera_SmoothDamp :: proc(
	current: f32,
	target: f32,
	currentVelocity: ^f32,
	smoothTime: f32,
	maxSpeed: f32,
	delta: f32,
) -> f32 {
	st := max(0.0001, smoothTime)
	omega := 2.0 / st
	x := omega * delta
	texp := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	change := current - target
	maxChange := maxSpeed * st
	change = math.clamp(change, -maxChange, maxChange)
	adjustedTarget := current - change
	temp := (currentVelocity^ + omega * change) * delta
	currentVelocity^ = (currentVelocity^ - omega * temp) * texp
	newPosition := adjustedTarget + (change + temp) * texp

	if (target - current > 0.0) == (newPosition > target) {
		newPosition = target
		currentVelocity^ = (newPosition - target) / max(0.0001, delta)
	}
	return newPosition
}

Camera_SpringDamp :: proc(
	current: f32,
	target: f32,
	currentVelocity: ^f32,
	springConstant: f32,
	dampingRatio: f32,
	delta: f32,
) -> f32 {
	diff := target - current
	dr := max(dampingRatio, 0.0001)
	springForce := diff * springConstant
	dampingForce := (-currentVelocity^ / dr) * 10.0
	force := springForce + dampingForce
	currentVelocity^ += force * delta
	return current + currentVelocity^ * delta
}

Camera_AdaptiveSmoothDamp :: proc(
	current: f32,
	target: f32,
	currentVelocity: ^f32,
	maxSpeed: f32,
	delta: f32,
) -> f32 {
	speed := math.abs(currentVelocity^)
	baseSmoothTime: f32 = 0.3
	smoothTime := max(baseSmoothTime * (1.0 - speed / 100.0), 0.05)
	return Camera_SmoothDamp(current, target, currentVelocity, smoothTime, maxSpeed, delta)
}

Camera_ShortestAngleDistance :: proc(from: f32, to: f32) -> f32 {
	diff := math.mod(to - from, 360.0)
	return math.mod(diff + 540.0, 360.0) - 180.0
}

Camera_SmoothDampAngle :: proc(
	current: f32,
	target: f32,
	currentVelocity: ^f32,
	smoothTime: f32,
	maxSpeed: f32,
	delta: f32,
) -> f32 {
	targetAdj := current + Camera_ShortestAngleDistance(current, target)
	return Camera_SmoothDamp(current, targetAdj, currentVelocity, smoothTime, maxSpeed, delta)
}

Camera_PredictFuturePosition :: proc(currentPosition: f32, velocity: f32, predictionTime: f32) -> f32 {
	return currentPosition + velocity * predictionTime
}

// ============================================================================
// CameraNode Lifecycle
// ============================================================================

CameraNode_Init :: proc(cameraNode: ^CameraNode) {
	InitializeNode(cameraNode)

	cameraNode.isCurrent = true
	cameraNode.targetLayers = {.Layer1, .Layer2, .Layer3, .Layer4, .Layer5, .Layer6, .Layer7}

	cameraNode.followMode = .SingleTarget
	cameraNode.dragType = .SmoothDamp

	cameraNode.target = nil
	cameraNode.targets = make([dynamic]CameraTarget)
	cameraNode.targetPosition = {0, 0}
	cameraNode.currentPosition = {0, 0}
	cameraNode.currentVelocity = {0, 0}
	cameraNode.targetVelocity = {0, 0}
	cameraNode.prevTargetPos = {0, 0}

	cameraNode.smoothDrag = true
	cameraNode.smoothDragSpeed = {0.2, 0.2}
	cameraNode.springConstant = 15.0
	cameraNode.dampingRatio = 1.0
	cameraNode.predictionTime = {0.5, 0.5}
	cameraNode.maxDistance = {100000.0, 100000.0}

	cameraNode.offset = {0, 0}
	cameraNode.smoothOffset = true
	cameraNode.smoothOffsetSpeed = 0.2
	cameraNode.currentOffset = {0, 0}
	cameraNode.currentOffsetVelocity = {0, 0}
	cameraNode.screenOffset = {640, 360}
	cameraNode.customScreenOffset = false

	cameraNode.currentRotation = 0.0
	cameraNode.targetRotation = 0.0
	cameraNode.rotation = 0.0
	cameraNode.allowRotation = true
	cameraNode.smoothRotation = true
	cameraNode.smoothRotationSpeed = 0.2
	cameraNode.currentRotationVelocity = 0.0

	cameraNode.zoom = 1.0
	cameraNode.currentZoom = 1.0
	cameraNode.targetZoom = 1.0
	cameraNode.smoothZoom = true
	cameraNode.smoothZoomSpeed = 0.2
	cameraNode.currentZoomVelocity = 0.0
	cameraNode.minZoom = 0.1
	cameraNode.maxZoom = 10.0
	cameraNode.autoZoom = true
	cameraNode.zoomMargin = 0.1

	cameraNode.hasLimits = false
	cameraNode.smoothLimit = true
	cameraNode.leftLimit = -1000000.0
	cameraNode.rightLimit = 1000000.0
	cameraNode.topLimit = -1000000.0
	cameraNode.bottomLimit = 1000000.0

	cameraNode.useHMargins = false
	cameraNode.useVMargins = false
	cameraNode.leftMargin = 0.25
	cameraNode.rightMargin = 0.25
	cameraNode.topMargin = 0.25
	cameraNode.bottomMargin = 0.25

	cameraNode.enableMouseFollow = false
	cameraNode.mouseInfluence = {0.2, 0.2}

	cameraNode.shakePreset = .Custom
	cameraNode.shakeTypes = {.Horizontal, .Vertical, .Random}
	cameraNode.isShaking = false
	cameraNode.shakeSpeed = 15.0
	cameraNode.shakeIntensity = 10.0
	cameraNode.shakeTrauma = 1.0
	cameraNode.shakeAttack = 0.0
	cameraNode.shakeDuration = 0.3
	cameraNode.shakeDecay = 0.3
	cameraNode.shakeElapsed = 0.0
	cameraNode.shakeEndless = false
	cameraNode.shakeOffset = {0, 0}
	cameraNode.shakeRotation = 0.0
	cameraNode.shakeZoom = 0.0

	cameraNode.rooms = make([dynamic]CameraRoom)
	cameraNode.magnets = make([dynamic]CameraMagnet)
	cameraNode.cinematics = make([dynamic]CameraCinematicPoint)
	cameraNode.playingCinematic = false
	cameraNode.activeCinematicId = ""
	cameraNode.currentCinematicIndex = 0
	cameraNode.cinematicHoldTimer = 0.0

	cameraNode.viewportSize = {1280, 720}

	cameraNode.ready = CameraNode_Ready
	cameraNode.update = CameraNode_Update
	cameraNode.onDestroy = CameraNode_Destroy
}

CameraNode_Create :: proc(
	scene: ^Scene,
	name: string = "CameraNode",
	isCurrent: bool = true,
	parent: ^Node = nil,
) -> ^CameraNode {
	cameraNode := CreateNode(scene.manager, CameraNode)
	CameraNode_Init(cameraNode)
	cameraNode.name = strings.clone(name, cameraNode.allocator) // owned: callers pass temp strings too
	cameraNode.isCurrent = isCurrent && !(parent != nil && parent.typeId == ViewportNode) // (a viewport's camera isn't the scene's)
	if cameraNode.isCurrent && scene != nil {
		scene.camera = cameraNode
	}
	scene->addNode(cameraNode, parent)
	return cameraNode
}

CameraNode_Ready :: proc(node: ^Node, gameContext: ^GameContext) {
	cameraNode := cast(^CameraNode)node
	if cameraNode == nil do return

	if cameraNode.parent != nil && cameraNode.parent.typeId == ViewportNode do cameraNode.isCurrent = false // (the viewport's view)
	if cameraNode.isCurrent && gameContext != nil && gameContext.scene != nil {
		gameContext.scene.camera = cameraNode
	}

	CameraNode_ResolveFollowTarget(cameraNode, gameContext)

	// A camera with no follow target and no explicit target position looks at
	// its own node position — so placing the camera in the editor is what
	// the game shows (CameraNode_ViewCenter is the same rule).
	if cameraNode.target == nil && len(cameraNode.targets) == 0 && cameraNode.targetPosition == {0, 0} {
		cameraNode.targetPosition = cameraNode.globalPosition
		cameraNode.currentPosition = cameraNode.globalPosition
	}

	// Snap initial position to target if available
	if cameraNode.target != nil {
		world := cameraNode.target.globalPosition
		if gameContext != nil && gameContext.scene != nil do world = Node_ComputeWorldPosition(gameContext.scene.manager, cameraNode.target)
		cameraNode.targetPosition = world + cameraNode.offset
		cameraNode.currentPosition = cameraNode.targetPosition
		cameraNode.prevTargetPos = world
	}
	cameraNode.currentOffset = cameraNode.offset
	cameraNode.currentRotation = cameraNode.targetRotation
	cameraNode.rotation = cameraNode.targetRotation
	cameraNode.currentZoom = cameraNode.targetZoom
	cameraNode.zoom = cameraNode.targetZoom
}

CameraNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	cameraNode := cast(^CameraNode)node
	if cameraNode == nil do return

	if gameContext != nil && gameContext.scene != nil && gameContext.scene.camera == cameraNode {
		gameContext.scene.camera = nil
	}

	delete(cameraNode.targets)
	cameraNode.targets = nil

	delete(cameraNode.rooms)
	cameraNode.rooms = nil

	delete(cameraNode.magnets)
	cameraNode.magnets = nil

	delete(cameraNode.cinematics)
	cameraNode.cinematics = nil
}

// CameraNode_ViewCenter is where the camera looks when the game starts.
CameraNode_ViewCenter :: proc(camera: ^CameraNode) -> [2]f32 {
	if camera.target != nil do return camera.target.globalPosition + camera.offset
	if camera.targetPosition != {0, 0} do return camera.targetPosition
	return camera.globalPosition
}

CameraNode_MakeCurrent :: proc(camera: ^CameraNode, scene: ^Scene = nil) {
	if camera == nil do return
	camera.isCurrent = true
	if scene != nil {
		scene.camera = camera
	}
}

// ============================================================================
// Target & Follow Controls
// ============================================================================

// CameraNode_ResolveFollowTarget finds the saved follow target (once).
CameraNode_ResolveFollowTarget :: proc(camera: ^CameraNode, gameContext: ^GameContext) {
	if camera.followResolved || camera.followTarget == "" do return
	ctx := gameContext if gameContext != nil else camera.gameContext
	if ctx == nil || ctx.scene == nil || ctx.scene.manager == nil do return
	if n := Node_ResolvePath(ctx.scene.manager, camera, camera.followTarget); n != nil && n != camera {
		camera.followResolved = true
		CameraNode_SetTarget(camera, n)
		// Start on it (its globalPosition may not be computed yet).
		world := Node_ComputeWorldPosition(ctx.scene.manager, n)
		camera.targetPosition = world + camera.offset
		camera.currentPosition = camera.targetPosition
		camera.prevTargetPos = world
	}
}

// CameraNode_SetFollowTarget saves `target` as the camera's follow target
// (a path relative to the camera) and follows it; nil clears it.
CameraNode_SetFollowTarget :: proc(camera: ^CameraNode, manager: ^NodeManager, target: ^Node) {
	if camera == nil do return
	if target == nil || manager == nil {
		camera.followTarget = ""
		CameraNode_SetTarget(camera, nil)
		if camera.followMode == .SingleTarget do camera.followMode = .Static
		return
	}
	camera.followTarget = strings.clone(Node_RelativePath(manager, camera, target), camera.allocator)
	camera.followResolved = true
	CameraNode_SetTarget(camera, target)
}

CameraNode_SetTarget :: proc(camera: ^CameraNode, target: ^Node) {
	if camera == nil do return
	camera.followResolved = true // an explicit target wins over the saved one
	camera.target = target
	if target != nil {
		camera.followMode = .SingleTarget
		camera.targetPosition = target.globalPosition + camera.offset
		camera.prevTargetPos = target.globalPosition
	}
}

CameraNode_SetTargetPosition :: proc(camera: ^CameraNode, position: [2]f32) {
	if camera == nil do return
	camera.targetPosition = position
	if camera.followMode != .MultiTarget {
		camera.followMode = .Manual
	}
}

// CameraNode_AddTarget adds a target to the group the camera frames (their
// weighted centre; with autoZoom, zoomed to fit them). A single follow
// target joins the group first.
CameraNode_AddTarget :: proc(camera: ^CameraNode, target: CameraTarget) {
	if camera == nil do return
	if camera.target != nil && Node_IsAlive(camera.target) && target.node != camera.target {
		already := false
		for t in camera.targets do if t.node == camera.target do already = true
		if !already {
			p := camera.target.globalPosition
			append(&camera.targets, CameraTarget{node = camera.target, position = p, influence = {1, 1}, radius = 50, enabled = true, prevPosition = p})
		}
	}
	for &t in camera.targets {
		if t.node != nil && t.node == target.node {
			t = target // already in the group: update it
			camera.followMode = .MultiTarget
			return
		}
	}
	append(&camera.targets, target)
	camera.followMode = .MultiTarget
}

// CameraNode_RemoveTarget takes a node out of the group.
CameraNode_RemoveTarget :: proc(camera: ^CameraNode, node: ^Node) {
	if camera == nil do return
	for t, i in camera.targets {
		if t.node == node {
			ordered_remove(&camera.targets, i)
			break
		}
	}
	if camera.target == node do camera.target = nil
	if len(camera.targets) == 0 && camera.followMode == .MultiTarget do camera.followMode = .Static
}

CameraNode_AddTargetNode :: proc(
	camera: ^CameraNode,
	node: ^Node,
	influence: [2]f32 = {1, 1},
	rotationInfluence: f32 = 0.0,
	radius: f32 = 50.0,
	priority: int = 0,
) {
	if camera == nil || node == nil do return
	t := CameraTarget{
		node              = node,
		position          = node.globalPosition,
		offset            = {0, 0},
		priority          = priority,
		influence         = influence,
		rotationInfluence = rotationInfluence,
		radius            = radius,
		enabled           = true,
		prevPosition      = node.globalPosition,
		velocity          = {0, 0},
	}
	CameraNode_AddTarget(camera, t)
}

CameraNode_ClearTargets :: proc(camera: ^CameraNode) {
	if camera == nil do return
	clear(&camera.targets)
	camera.target = nil
	camera.followMode = .Static
}

// ============================================================================
// Parameter Setters: Pan, Offset, Rotation, Zoom, Limits, Margins
// ============================================================================

CameraNode_Pan :: proc(camera: ^CameraNode, delta: [2]f32) {
	if camera == nil do return
	camera.targetPosition += delta
	if camera.followMode == .SingleTarget && camera.target == nil {
		camera.followMode = .Manual
	}
}

CameraNode_SetOffset :: proc(camera: ^CameraNode, offset: [2]f32) {
	if camera == nil do return
	camera.offset = offset
	if !camera.smoothOffset {
		camera.currentOffset = offset
	}
}

CameraNode_SetRotation :: proc(camera: ^CameraNode, angleDegrees: f32) {
	if camera == nil do return
	camera.targetRotation = angleDegrees
	if !camera.smoothRotation {
		camera.currentRotation = angleDegrees
		camera.rotation = angleDegrees
		camera.currentRotationVelocity = 0.0
	}
}

CameraNode_RotateBy :: proc(camera: ^CameraNode, deltaDegrees: f32) {
	if camera == nil do return
	CameraNode_SetRotation(camera, camera.targetRotation + deltaDegrees)
}

CameraNode_SetZoom :: proc(camera: ^CameraNode, zoom: f32) {
	if camera == nil do return
	clampedZoom := math.clamp(zoom, camera.minZoom, camera.maxZoom)
	camera.targetZoom = clampedZoom
	if !camera.smoothZoom {
		camera.currentZoom = clampedZoom
		camera.zoom = clampedZoom
		camera.currentZoomVelocity = 0.0
	}
}

CameraNode_ZoomBy :: proc(camera: ^CameraNode, factor: f32) {
	if camera == nil do return
	CameraNode_SetZoom(camera, camera.targetZoom * factor)
}

CameraNode_SetLimits :: proc(camera: ^CameraNode, left, right, top, bottom: f32) {
	if camera == nil do return
	camera.hasLimits = true
	camera.leftLimit = left
	camera.rightLimit = right
	camera.topLimit = top
	camera.bottomLimit = bottom
}

CameraNode_ClearLimits :: proc(camera: ^CameraNode) {
	if camera == nil do return
	camera.hasLimits = false
}

CameraNode_SetDeadzones :: proc(
	camera: ^CameraNode,
	left, right, top, bottom: f32,
	horizontal: bool = true,
	vertical: bool = true,
) {
	if camera == nil do return
	camera.useHMargins = horizontal
	camera.useVMargins = vertical
	camera.leftMargin = math.clamp(left, 0.0, 0.49)
	camera.rightMargin = math.clamp(right, 0.0, 0.49)
	camera.topMargin = math.clamp(top, 0.0, 0.49)
	camera.bottomMargin = math.clamp(bottom, 0.0, 0.49)
}

CameraNode_Reset :: proc(camera: ^CameraNode) {
	if camera == nil do return
	if camera.target != nil {
		camera.targetPosition = camera.target.globalPosition + camera.offset
		camera.prevTargetPos = camera.target.globalPosition
	}
	camera.currentPosition = camera.targetPosition
	camera.currentVelocity = {0, 0}
	camera.currentOffset = camera.offset
	camera.currentOffsetVelocity = {0, 0}
	camera.currentRotation = camera.targetRotation
	camera.rotation = camera.targetRotation
	camera.currentRotationVelocity = 0.0
	camera.currentZoom = camera.targetZoom
	camera.zoom = camera.targetZoom
	camera.node.position = camera.currentPosition + camera.currentOffset
	camera.node.rotation = camera.rotation
}

// ============================================================================
// Screen Shake System (PCamShake integration)
// ============================================================================

CameraNode_Shake :: proc(
	camera: ^CameraNode,
	intensity: f32,
	duration: f32,
	speed: f32 = 15.0,
	types: bit_set[CameraShakeType] = {.Horizontal, .Vertical, .Random},
	attack: f32 = 0.0,
	decay: f32 = 0.3,
	endless: bool = false,
) {
	if camera == nil do return
	camera.isShaking = true
	camera.activeShakeIntensity = intensity
	camera.shakeDuration = duration
	camera.activeShakeSpeed = speed
	camera.activeShakeTypes = types
	camera.shakeAttack = attack
	camera.shakeDecay = decay
	camera.shakeTrauma = 1.0
	camera.shakeElapsed = 0.0
	camera.shakeEndless = endless
}

// A preset's shake; Custom is the node's Shake Types / Speed / Intensity.
Camera_Shake_Settings :: struct {
	intensity, duration, speed, attack, decay: f32,
	types:                                     bit_set[CameraShakeType],
	endless:                                   bool,
}

CameraNode_ShakeSettings :: proc(camera: ^CameraNode, preset: CameraShakePreset) -> Camera_Shake_Settings {
	switch preset {
	case .Gunshot:    return {intensity = 12, duration = 0.1, speed = 25, types = {.Horizontal, .Vertical, .Random}, decay = 0.25}
	case .Earthquake: return {intensity = 8, duration = 2, speed = 15, types = {.Vertical, .Horizontal, .Perlin}, attack = 0.5, decay = 1}
	case .Handheld:   return {intensity = 2, speed = 4, types = {.Perlin, .Rotate}, endless = true}
	case .Explosion:  return {intensity = 25, duration = 0.2, speed = 30, types = {.Random, .Rotate, .Circular, .Zoom}, decay = 0.6}
	case .Impact:     return {intensity = 15, duration = 0.05, speed = 20, types = {.Vertical, .Horizontal}, decay = 0.2}
	case .Rumble:     return {intensity = 5, duration = 1.5, speed = 10, types = {.Vertical, .Perlin}, attack = 0.2, decay = 0.5}
	case .Vibration:  return {intensity = 4, duration = 0.3, speed = 50, types = {.Random, .Horizontal}, decay = 0.2}
	case .Wobbly:     return {intensity = 8, duration = 1, speed = 6, types = {.Rotate, .Circular}, attack = 0.2, decay = 0.8}
	case .Custom:
	}
	return {intensity = camera.shakeIntensity, duration = 0.5, speed = camera.shakeSpeed, types = camera.shakeTypes, decay = 0.3}
}

// CameraNode_PlayShake plays the node's Shake Preset (Custom: its Shake
// Types / Speed / Intensity); strength (px) / duration (s) < 0 = the preset's.
// Lua's camera_shake / Camera.shake (#215).
CameraNode_PlayShake :: proc(camera: ^CameraNode, strength: f32 = -1, duration: f32 = -1) {
	if camera == nil do return
	s := CameraNode_ShakeSettings(camera, camera.shakePreset)
	if strength >= 0 do s.intensity = strength
	if duration >= 0 {
		s.duration = duration
		s.endless = false
	}
	CameraNode_Shake(camera, s.intensity, s.duration, s.speed, s.types, s.attack, s.decay, s.endless)
}

CameraNode_ApplyShakePreset :: proc(camera: ^CameraNode, preset: CameraShakePreset) {
	if camera == nil do return
	camera.shakePreset = preset
	CameraNode_PlayShake(camera)
}

CameraNode_StopShake :: proc(camera: ^CameraNode) {
	if camera == nil do return
	camera.isShaking = false
	camera.shakeElapsed = 0.0
	camera.shakeOffset = {0, 0}
	camera.shakeRotation = 0.0
	camera.shakeZoom = 0.0
}

CameraNode_IsShaking :: proc(camera: ^CameraNode) -> bool {
	if camera == nil do return false
	return camera.isShaking
}

// ============================================================================
// Rooms, Magnets & Cinematics Management
// ============================================================================

CameraNode_AddRoom :: proc(camera: ^CameraNode, room: CameraRoom) {
	if camera == nil do return
	append(&camera.rooms, room)
}

CameraNode_AddMagnet :: proc(camera: ^CameraNode, magnet: CameraMagnet) {
	if camera == nil do return
	append(&camera.magnets, magnet)
}

CameraNode_AddCinematicPoint :: proc(camera: ^CameraNode, point: CameraCinematicPoint) {
	if camera == nil do return
	append(&camera.cinematics, point)
}

CameraNode_StartCinematic :: proc(camera: ^CameraNode, id: string) {
	if camera == nil do return
	camera.activeCinematicId = id
	camera.currentCinematicIndex = -1
	for point, idx in camera.cinematics {
		if point.id == id {
			camera.currentCinematicIndex = idx
			break
		}
	}
	if camera.currentCinematicIndex >= 0 {
		camera.playingCinematic = true
		camera.cinematicHoldTimer = 0.0
	}
}

CameraNode_StopCinematic :: proc(camera: ^CameraNode) {
	if camera == nil do return
	camera.playingCinematic = false
	camera.activeCinematicId = ""
	camera.currentCinematicIndex = -1
	camera.cinematicHoldTimer = 0.0
}

CameraNode_IsCinematicPlaying :: proc(camera: ^CameraNode) -> bool {
	if camera == nil do return false
	return camera.playingCinematic
}

// ============================================================================
// CameraNode Update Loop
// ============================================================================

CameraNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	camera := cast(^CameraNode)node
	if camera == nil || !camera.enabled do return

	dt := max(0.0001, deltaTime)

	// Saved follow target spawned after the camera was ready.
	if !camera.followResolved && camera.followTarget != "" do CameraNode_ResolveFollowTarget(camera, gameContext)
	// Followed nodes that were destroyed.
	if camera.target != nil && !Node_IsAlive(camera.target) do camera.target = nil
	for i := len(camera.targets) - 1; i >= 0; i -= 1 {
		if n := camera.targets[i].node; n != nil && !Node_IsAlive(n) do ordered_remove(&camera.targets, i)
	}

	// Cache viewport size (a Viewport's camera: its picture's)
	if camera.parent != nil && camera.parent.typeId == ViewportNode {
		rs := ViewportNode_RenderSize(cast(^ViewportNode)camera.parent)
		camera.viewportSize = {f32(rs.x), f32(rs.y)}
	} else if gameContext != nil && gameContext.game != nil && gameContext.game.virtualSize.x > 0 {
		camera.viewportSize = gameContext.game.virtualSize
	} else if rl.IsWindowReady() {
		camera.viewportSize = {f32(rl.GetRenderWidth()), f32(rl.GetRenderHeight())}
	}

	// Advanced cameras in the scene: this camera hosts them (shows the
	// highest-priority one, blending between them).
	if AdvCam_Host(camera, gameContext, dt) do return

	// ------------------------------------------------------------------------
	// 1. Cinematic Sequence Update
	// ------------------------------------------------------------------------
	if camera.playingCinematic && camera.currentCinematicIndex >= 0 && camera.currentCinematicIndex < len(camera.cinematics) {
		pt := &camera.cinematics[camera.currentCinematicIndex]
		camera.targetPosition = pt.position
		camera.targetZoom = pt.zoom
		camera.targetRotation = pt.rotation

		// Check distance to target to initiate hold timer
		dist := math.sqrt(math.pow(camera.currentPosition.x - pt.position.x, 2) + math.pow(camera.currentPosition.y - pt.position.y, 2))
		if dist < 5.0 {
			camera.cinematicHoldTimer += dt
			if camera.cinematicHoldTimer >= pt.holdTime {
				// Find next cinematic point with same id
				nextIdx := -1
				for i := camera.currentCinematicIndex + 1; i < len(camera.cinematics); i += 1 {
					if camera.cinematics[i].id == camera.activeCinematicId {
						nextIdx = i
						break
					}
				}
				if nextIdx >= 0 {
					camera.currentCinematicIndex = nextIdx
					camera.cinematicHoldTimer = 0.0
				} else {
					CameraNode_StopCinematic(camera)
				}
			}
		}
	} else {
		// ------------------------------------------------------------------------
		// 2. Normal Follow Modes: SingleTarget / MultiTarget
		// ------------------------------------------------------------------------
		switch camera.followMode {
		case .SingleTarget:
			if camera.target != nil {
				targetPos := camera.target.globalPosition + camera.offset
				camera.targetVelocity = (camera.target.globalPosition - camera.prevTargetPos) / dt
				camera.prevTargetPos = camera.target.globalPosition

				if camera.dragType == .LookAhead {
					targetPos.x = Camera_PredictFuturePosition(targetPos.x, camera.targetVelocity.x, camera.predictionTime.x)
					targetPos.y = Camera_PredictFuturePosition(targetPos.y, camera.targetVelocity.y, camera.predictionTime.y)
				}
				camera.targetPosition = targetPos
			}

		case .MultiTarget:
			if len(camera.targets) > 0 {
				totalWeight: [2]f32 = {0, 0}
				weightedPos: [2]f32 = {0, 0}
				weightedVel: [2]f32 = {0, 0}

				minBounds := [2]f32{1e9, 1e9}
				maxBounds := [2]f32{-1e9, -1e9}

				for &t in camera.targets {
					if !t.enabled do continue
					pos := t.node != nil ? t.node.globalPosition + t.offset : t.position + t.offset
					t.velocity = (pos - t.prevPosition) / dt
					t.prevPosition = pos

					weight := t.influence
					totalWeight += weight
					weightedPos += pos * weight
					weightedVel += t.velocity * weight

					minBounds.x = min(minBounds.x, pos.x - t.radius)
					minBounds.y = min(minBounds.y, pos.y - t.radius)
					maxBounds.x = max(maxBounds.x, pos.x + t.radius)
					maxBounds.y = max(maxBounds.y, pos.y + t.radius)
				}

				if totalWeight.x > 0 && totalWeight.y > 0 {
					camera.targetPosition = weightedPos / totalWeight
					camera.targetVelocity = weightedVel / totalWeight
				}

				// Auto-zoom to fit bounding box
				if camera.autoZoom && maxBounds.x > minBounds.x && maxBounds.y > minBounds.y {
					boundW := (maxBounds.x - minBounds.x) * (1.0 + camera.zoomMargin)
					boundH := (maxBounds.y - minBounds.y) * (1.0 + camera.zoomMargin)
					if boundW > 0 && boundH > 0 {
						reqZoom := min(camera.viewportSize.x / boundW, camera.viewportSize.y / boundH)
						camera.targetZoom = math.clamp(reqZoom, camera.minZoom, camera.maxZoom)
					}
				}
			}

		case .Static, .Manual:
			// Position is controlled manually or stays static
		}
	}

	// ------------------------------------------------------------------------
	// 3. Deadzones / Margins (SingleTarget)
	// ------------------------------------------------------------------------
	if camera.followMode == .SingleTarget && !camera.playingCinematic && (camera.useHMargins || camera.useVMargins) {
		currentZ := max(0.001, camera.currentZoom)
		viewW := camera.viewportSize.x / currentZ
		viewH := camera.viewportSize.y / currentZ
		halfW := viewW * 0.5
		halfH := viewH * 0.5

		deadzoneLeft := -halfW + (halfW * camera.leftMargin)
		deadzoneRight := halfW - (halfW * camera.rightMargin)
		deadzoneTop := -halfH + (halfH * camera.topMargin)
		deadzoneBottom := halfH - (halfH * camera.bottomMargin)

		relPos := camera.targetPosition - camera.currentPosition

		if camera.useHMargins {
			if relPos.x < deadzoneLeft {
				camera.targetPosition.x = camera.currentPosition.x + (relPos.x - deadzoneLeft)
			} else if relPos.x > deadzoneRight {
				camera.targetPosition.x = camera.currentPosition.x + (relPos.x - deadzoneRight)
			} else {
				camera.targetPosition.x = camera.currentPosition.x
			}
		}

		if camera.useVMargins {
			if relPos.y < deadzoneTop {
				camera.targetPosition.y = camera.currentPosition.y + (relPos.y - deadzoneTop)
			} else if relPos.y > deadzoneBottom {
				camera.targetPosition.y = camera.currentPosition.y + (relPos.y - deadzoneBottom)
			} else {
				camera.targetPosition.y = camera.currentPosition.y
			}
		}
	}

	// ------------------------------------------------------------------------
	// 4. Magnet Influences
	// ------------------------------------------------------------------------
	for magnet in camera.magnets {
		if !magnet.enabled do continue
		diff := magnet.position - camera.targetPosition
		dist := math.sqrt(diff.x * diff.x + diff.y * diff.y)
		isInside := false

		if magnet.shape == .Circle {
			isInside = dist <= magnet.radius
		} else {
			halfSz := magnet.size * 0.5
			isInside = math.abs(diff.x) <= halfSz.x && math.abs(diff.y) <= halfSz.y
		}

		if isInside {
			if magnet.useFullForce {
				if magnet.mode == .Attract {
					camera.targetPosition = magnet.position
				} else if dist > 0.001 {
					dir := -diff / dist
					camera.targetPosition += dir * (magnet.radius - dist)
				}
			} else if dist > 0.001 {
				dir := diff / dist
				if magnet.mode == .Repel do dir = -dir
				pull := magnet.force * (1.0 - math.clamp(dist / max(1.0, magnet.radius), 0.0, 1.0))
				camera.targetPosition += dir * pull * 50.0 * dt
			}
		}
	}

	// ------------------------------------------------------------------------
	// 5. Room Constraints
	// ------------------------------------------------------------------------
	for room in camera.rooms {
		if !room.enabled do continue
		r := room.rect
		if camera.targetPosition.x >= r.x && camera.targetPosition.x <= (r.x + r.width) &&
		   camera.targetPosition.y >= r.y && camera.targetPosition.y <= (r.y + r.height) {

			currentZ := max(0.001, camera.targetZoom)
			halfW := (camera.viewportSize.x * 0.5) / currentZ
			halfH := (camera.viewportSize.y * 0.5) / currentZ

			minX := r.x + halfW
			maxX := r.x + r.width - halfW
			minY := r.y + halfH
			maxY := r.y + r.height - halfH

			if !(.Left in room.openSides) && camera.targetPosition.x < minX do camera.targetPosition.x = minX
			if !(.Right in room.openSides) && camera.targetPosition.x > maxX do camera.targetPosition.x = maxX
			if !(.Top in room.openSides) && camera.targetPosition.y < minY do camera.targetPosition.y = minY
			if !(.Bottom in room.openSides) && camera.targetPosition.y > maxY do camera.targetPosition.y = maxY

			if room.zoom > 0 {
				camera.targetZoom = room.zoom
			}
		}
	}

	// ------------------------------------------------------------------------
	// 6. Pointer / Mouse Follow Influence
	// ------------------------------------------------------------------------
	if camera.enableMouseFollow && rl.IsWindowReady() {
		mp := rl.GetMousePosition()
		screenCenter := camera.viewportSize * 0.5
		mouseDelta := mp - screenCenter
		camera.targetPosition += mouseDelta * camera.mouseInfluence
	}

	// ------------------------------------------------------------------------
	// 7. Boundaries & Limits (Target Clamping)
	// ------------------------------------------------------------------------
	if camera.hasLimits {
		currentZ := max(0.001, camera.currentZoom)
		halfW := (camera.viewportSize.x * 0.5) / currentZ
		halfH := (camera.viewportSize.y * 0.5) / currentZ

		if (camera.rightLimit - camera.leftLimit) >= (halfW * 2.0) {
			camera.targetPosition.x = math.clamp(camera.targetPosition.x, camera.leftLimit + halfW, camera.rightLimit - halfW)
		} else {
			camera.targetPosition.x = (camera.leftLimit + camera.rightLimit) * 0.5
		}

		if (camera.bottomLimit - camera.topLimit) >= (halfH * 2.0) {
			camera.targetPosition.y = math.clamp(camera.targetPosition.y, camera.topLimit + halfH, camera.bottomLimit - halfH)
		} else {
			camera.targetPosition.y = (camera.topLimit + camera.bottomLimit) * 0.5
		}
	}

	// ------------------------------------------------------------------------
	// 8. Smoothing / Position Damping
	// ------------------------------------------------------------------------
	if camera.smoothDrag {
		switch camera.dragType {
		case .SmoothDamp:
			camera.currentPosition.x = Camera_SmoothDamp(camera.currentPosition.x, camera.targetPosition.x, &camera.currentVelocity.x, camera.smoothDragSpeed.x, 100000.0, dt)
			camera.currentPosition.y = Camera_SmoothDamp(camera.currentPosition.y, camera.targetPosition.y, &camera.currentVelocity.y, camera.smoothDragSpeed.y, 100000.0, dt)
		case .SpringDamp:
			camera.currentPosition.x = Camera_SpringDamp(camera.currentPosition.x, camera.targetPosition.x, &camera.currentVelocity.x, camera.springConstant, camera.dampingRatio, dt)
			camera.currentPosition.y = Camera_SpringDamp(camera.currentPosition.y, camera.targetPosition.y, &camera.currentVelocity.y, camera.springConstant, camera.dampingRatio, dt)
		case .LookAhead:
			speedFactor := camera.smoothDragSpeed * 0.2
			camera.currentPosition.x = Camera_SmoothDamp(camera.currentPosition.x, camera.targetPosition.x, &camera.currentVelocity.x, speedFactor.x, 100000.0, dt)
			camera.currentPosition.y = Camera_SmoothDamp(camera.currentPosition.y, camera.targetPosition.y, &camera.currentVelocity.y, speedFactor.y, 100000.0, dt)
		case .AutoSpeed:
			camera.currentPosition.x = Camera_AdaptiveSmoothDamp(camera.currentPosition.x, camera.targetPosition.x, &camera.currentVelocity.x, 100000.0, dt)
			camera.currentPosition.y = Camera_AdaptiveSmoothDamp(camera.currentPosition.y, camera.targetPosition.y, &camera.currentVelocity.y, 100000.0, dt)
		case .None:
			camera.currentPosition = camera.targetPosition
			camera.currentVelocity = {0, 0}
		}
	} else {
		camera.currentPosition = camera.targetPosition
		camera.currentVelocity = {0, 0}
	}

	// Max Distance: the smoothing never trails the target by more (px, per axis) (#215).
	for i in 0 ..< 2 {
		lag := camera.currentPosition[i] - camera.targetPosition[i]
		if lim := max(camera.maxDistance[i], 0); abs(lag) > lim {
			camera.currentPosition[i] = camera.targetPosition[i] + math.sign(lag) * lim
			camera.currentVelocity[i] = 0
		}
	}

	// Enforce limits strictly after smoothing so camera never renders outside limits
	if camera.hasLimits {
		currentZ := max(0.001, camera.currentZoom)
		halfW := (camera.viewportSize.x * 0.5) / currentZ
		halfH := (camera.viewportSize.y * 0.5) / currentZ

		if (camera.rightLimit - camera.leftLimit) >= (halfW * 2.0) {
			camera.currentPosition.x = math.clamp(camera.currentPosition.x, camera.leftLimit + halfW, camera.rightLimit - halfW)
		} else {
			camera.currentPosition.x = (camera.leftLimit + camera.rightLimit) * 0.5
		}

		if (camera.bottomLimit - camera.topLimit) >= (halfH * 2.0) {
			camera.currentPosition.y = math.clamp(camera.currentPosition.y, camera.topLimit + halfH, camera.bottomLimit - halfH)
		} else {
			camera.currentPosition.y = (camera.topLimit + camera.bottomLimit) * 0.5
		}
	}

	// ------------------------------------------------------------------------
	// 9. Offset Smoothing
	// ------------------------------------------------------------------------
	if camera.smoothOffset {
		camera.currentOffset.x = Camera_SmoothDamp(camera.currentOffset.x, camera.offset.x, &camera.currentOffsetVelocity.x, camera.smoothOffsetSpeed, 100000.0, dt)
		camera.currentOffset.y = Camera_SmoothDamp(camera.currentOffset.y, camera.offset.y, &camera.currentOffsetVelocity.y, camera.smoothOffsetSpeed, 100000.0, dt)
	} else {
		camera.currentOffset = camera.offset
		camera.currentOffsetVelocity = {0, 0}
	}

	// ------------------------------------------------------------------------
	// 10. Rotation Smoothing
	// ------------------------------------------------------------------------
	if camera.allowRotation {
		if camera.smoothRotation {
			camera.currentRotation = Camera_SmoothDampAngle(camera.currentRotation, camera.targetRotation, &camera.currentRotationVelocity, camera.smoothRotationSpeed, 100000.0, dt)
		} else {
			camera.currentRotation = camera.targetRotation
			camera.currentRotationVelocity = 0.0
		}
	}

	// ------------------------------------------------------------------------
	// 11. Zoom Smoothing
	// ------------------------------------------------------------------------
	if camera.smoothZoom {
		camera.currentZoom = Camera_SmoothDamp(camera.currentZoom, camera.targetZoom, &camera.currentZoomVelocity, camera.smoothZoomSpeed, 100000.0, dt)
	} else {
		camera.currentZoom = camera.targetZoom
		camera.currentZoomVelocity = 0.0
	}
	camera.currentZoom = math.clamp(camera.currentZoom, camera.minZoom, camera.maxZoom)
	camera.zoom = camera.currentZoom

	// ------------------------------------------------------------------------
	// 12. Screen Shake Trauma & Offset Evaluation
	// ------------------------------------------------------------------------
	if camera.isShaking {
		camera.shakeElapsed += dt
		totalDuration := camera.shakeAttack + camera.shakeDuration + camera.shakeDecay

		currentTrauma: f32 = 0.0
		if camera.shakeAttack > 0.0 && camera.shakeElapsed < camera.shakeAttack {
			currentTrauma = (camera.shakeElapsed / camera.shakeAttack) * camera.shakeTrauma
		} else if camera.shakeEndless || camera.shakeElapsed < (camera.shakeAttack + camera.shakeDuration) {
			currentTrauma = camera.shakeTrauma
		} else if camera.shakeElapsed < totalDuration && camera.shakeDecay > 0.0 {
			decayProg := (camera.shakeElapsed - camera.shakeAttack - camera.shakeDuration) / camera.shakeDecay
			currentTrauma = max(0.0, camera.shakeTrauma * (1.0 - decayProg))
		} else if !camera.shakeEndless {
			CameraNode_StopShake(camera)
		}

		shakeFactor := currentTrauma * currentTrauma
		camera.shakeOffset = {0, 0}
		camera.shakeRotation = 0.0
		camera.shakeZoom = 0.0

		if .Horizontal in camera.activeShakeTypes {
			camera.shakeOffset.x += math.sin(camera.shakeElapsed * camera.activeShakeSpeed * 10.0) * camera.activeShakeIntensity * shakeFactor
		}
		if .Vertical in camera.activeShakeTypes {
			camera.shakeOffset.y += math.cos((camera.shakeElapsed + 100.0) * camera.activeShakeSpeed * 10.0) * camera.activeShakeIntensity * shakeFactor
		}
		if .Random in camera.activeShakeTypes {
			rx := (rand.float32() * 2.0 - 1.0) * camera.activeShakeIntensity * shakeFactor
			ry := (rand.float32() * 2.0 - 1.0) * camera.activeShakeIntensity * shakeFactor
			camera.shakeOffset += {rx, ry}
		}
		if .Perlin in camera.activeShakeTypes {
			noiseCoord := [2]f64{f64(camera.shakeElapsed * camera.activeShakeSpeed), 0.0}
			nx := noise.noise_2d(1337, noiseCoord) * camera.activeShakeIntensity * shakeFactor
			ny := noise.noise_2d(7331, noiseCoord) * camera.activeShakeIntensity * shakeFactor
			camera.shakeOffset += {nx, ny}
		}
		if .Rotate in camera.activeShakeTypes {
			camera.shakeRotation = math.sin(camera.shakeElapsed * camera.activeShakeSpeed * 8.0) * (camera.activeShakeIntensity * 0.5) * shakeFactor
		}
		if .Circular in camera.activeShakeTypes {
			cx := math.cos(camera.shakeElapsed * camera.activeShakeSpeed * 8.0) * camera.activeShakeIntensity * shakeFactor
			cy := math.sin(camera.shakeElapsed * camera.activeShakeSpeed * 8.0) * camera.activeShakeIntensity * shakeFactor
			camera.shakeOffset += {cx, cy}
		}
		if .Zoom in camera.activeShakeTypes {
			camera.shakeZoom = math.sin(camera.shakeElapsed * camera.activeShakeSpeed * 12.0) * (camera.activeShakeIntensity * 0.02) * shakeFactor
		}
	}

	// ------------------------------------------------------------------------
	// 13. Synchronize Node Transform
	// ------------------------------------------------------------------------
	node.position = camera.currentPosition + camera.currentOffset + camera.shakeOffset
	node.rotation = camera.currentRotation + camera.shakeRotation
}

// ============================================================================
// Raylib Camera2D Projection & Coordinate Transformations
// ============================================================================

CameraNode_GetCamera2D :: proc(camera: ^CameraNode, viewportWidth: f32 = 1280, viewportHeight: f32 = 720) -> rl.Camera2D {
	if camera == nil {
		cam := rl.Camera2D{
			offset   = {viewportWidth * 0.5, viewportHeight * 0.5},
			target   = {0, 0},
			rotation = 0.0,
			zoom     = 1.0,
		}
		Pixel_SnapCamera(&cam)
		return cam
	}

	scrOffset := camera.customScreenOffset ? camera.screenOffset : [2]f32{viewportWidth * 0.5, viewportHeight * 0.5}
	camTarget := camera.currentPosition + camera.currentOffset + (camera.shakeOffset + Camera_KickOffset()) * access.screenShake // (accessibility: shake scale; Camera.kick)
	camRot := camera.currentRotation + camera.shakeRotation * access.screenShake
	camZoom := max(0.001, camera.currentZoom + camera.shakeZoom)

	cam := rl.Camera2D{
		offset   = scrOffset,
		target   = camTarget,
		rotation = camRot,
		zoom     = camZoom,
	}
	Pixel_SnapCamera(&cam) // pixel snap / the smooth camera's margin (pixel_perfect.odin)
	return cam
}

CameraNode_Begin :: proc(camera: ^CameraNode, viewportWidth: f32 = 1280, viewportHeight: f32 = 720) {
	if camera == nil || !rl.IsWindowReady() do return
	cam2d := CameraNode_GetCamera2D(camera, viewportWidth, viewportHeight)
	rl.BeginMode2D(cam2d)
}

CameraNode_End :: proc() {
	if rl.IsWindowReady() {
		rl.EndMode2D()
	}
}

CameraNode_ScreenToWorld :: proc(camera: ^CameraNode, screenPos: [2]f32, viewportWidth: f32 = 1280, viewportHeight: f32 = 720) -> [2]f32 {
	if rl.IsWindowReady() {
		cam := CameraNode_GetCamera2D(camera, viewportWidth, viewportHeight)
		return rl.GetScreenToWorld2D(screenPos, cam)
	}
	cam := CameraNode_GetCamera2D(camera, viewportWidth, viewportHeight)
	return (screenPos - cam.offset) / cam.zoom + cam.target
}

CameraNode_WorldToScreen :: proc(camera: ^CameraNode, worldPos: [2]f32, viewportWidth: f32 = 1280, viewportHeight: f32 = 720) -> [2]f32 {
	if rl.IsWindowReady() {
		cam := CameraNode_GetCamera2D(camera, viewportWidth, viewportHeight)
		return rl.GetWorldToScreen2D(worldPos, cam)
	}
	cam := CameraNode_GetCamera2D(camera, viewportWidth, viewportHeight)
	return (worldPos - cam.target) * cam.zoom + cam.offset
}

CameraNode_GetVisibleWorldBounds :: proc(camera: ^CameraNode, viewportWidth: f32 = 1280, viewportHeight: f32 = 720) -> rl.Rectangle {
	cam := CameraNode_GetCamera2D(camera, viewportWidth, viewportHeight)
	viewW := viewportWidth / cam.zoom
	viewH := viewportHeight / cam.zoom
	return rl.Rectangle{
		x      = cam.target.x - viewW * 0.5,
		y      = cam.target.y - viewH * 0.5,
		width  = viewW,
		height = viewH,
	}
}
