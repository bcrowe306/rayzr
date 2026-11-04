package engine

import "core:time"
TimerNode :: struct {
	using node: Node,
	elapsed: time.Duration,
	running: bool,
	duration: time.Duration,
	loop: bool,
	onTick: EventSubject,
	onExpire: EventSubject,
	start: proc(timer: ^TimerNode),
	setDuration: proc(timer: ^TimerNode, durationSec: f32),
}

TimerNode_Init :: proc(timer: ^TimerNode) {
	InitializeNode(timer)
	InitializeSubject(&timer.onTick, "tick", timer)       // every update while running (elapsed seconds)
	InitializeSubject(&timer.onExpire, "timeout", timer)  // the duration elapsed
	timer.update = TimerNode_Update
	timer.onDestroy = TimerNode_Destroy
	timer.start = TimerNode_Start
	timer.setDuration = TimerNode_SetDuration
	timer.renderable = true // (draws nothing; visible so its children draw - #388)
	timer.elapsed = 0
}

TimerNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	timer := cast(^TimerNode)node
	DestroySubject(&timer.onTick)
	DestroySubject(&timer.onExpire)
}

TimerNode_Start :: proc(timer: ^TimerNode) {
	timer.elapsed = 0
	timer.running = true
}

TimerNode_Create :: proc(scene: ^Scene, durationSeconds: f32, auto_start: bool = false, loop: bool = false) -> ^TimerNode {
	timer := CreateNode(scene.manager, TimerNode)
	TimerNode_Init(timer)
	timer->setDuration(durationSeconds)
	timer.loop = loop
	timer.running = auto_start
	scene->addNode(timer)
	return timer
}

TimerNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	timer := cast(^TimerNode)node
	if !timer.running do return
	timer.elapsed += time.Duration(f64(deltaTime) * f64(time.Second))
	timer.onTick->notify(timer, f32(time.duration_seconds(timer.elapsed)), gameContext)
	if timer.elapsed >= timer.duration {
		// Reset first so a "timeout" handler can restart or reconfigure it.
		timer.elapsed = 0
		timer.running = timer.loop
		timer.onExpire->notify(timer, nil, gameContext)
	}
}

TimerNode_SetDuration :: proc(timer: ^TimerNode, durationSec: f32) {
	timer.duration = time.Duration(f64(durationSec) * f64(time.Second)) // f32 overflows past ~2.1s
}
