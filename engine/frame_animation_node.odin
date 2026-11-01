package engine

import rl "vendor:raylib"
import "core:log"

FrameAnimationNode :: struct {
	using node: Node,
	shininess: f32 `gui:"true" min:"0" max:"1"`, // lit: a glint from lights (#274; its image's _s.png too)
	ticker: Ticker,
	start: u32,
	end: u32,
	currentFrame: u32,
	reverse: bool,
	loop: bool,
	frames: [dynamic]^Texture,
	// "animation_finished": a non-looping animation reached its last frame.
	onFinished: EventSubject,
	finishedNotified: bool,
}

FrameAnimationNode_Create :: proc(scene: ^Scene) -> ^FrameAnimationNode {
	fan := CreateNode(scene.manager, FrameAnimationNode)
	FrameAnimationNode_Init(fan)
	return fan
}

FrameAnimationNode_Init :: proc(fan: ^FrameAnimationNode) {
	fan.frames = make([dynamic]^Texture, fan.allocator)
	Ticker_Init(&fan.ticker, false)
	fan.update = FrameAnimationNode_Update
	fan.render = FrameAnimationNode_Render
	fan.onDestroy = FrameAnimationNode_Destroy
	InitializeSubject(&fan.onFinished, "animation_finished", fan)
	fan.ticker->setFPS(12)
	fan.ticker->setCallback(proc(ticker: ^Ticker, currentTick: int, user_data: rawptr) {
		fan := cast(^FrameAnimationNode)user_data
		FrameAnimationNode_AdvanceFrame(fan)
	}, fan)
}

FrameAnimationNode_AddFrame :: proc(fan: ^FrameAnimationNode, rm: ^ResourceManager, filePath: string) {
	texture, ok := rm->loadTexture(filePath)
	if ok && texture != nil {
		append(&fan.frames, texture)
		fan.end = auto_cast len(fan.frames) - 1
	} else {
		log.error("Error adding frame. Texture file loading error: ", filePath)
	}
}

FrameAnimationNode_AdvanceFrame :: proc(fan: ^FrameAnimationNode) {
	if len(fan.frames) == 0 do return
	if fan.reverse {
		if fan.currentFrame <= auto_cast fan.start {
			if fan.loop {
				fan.currentFrame = fan.end
			}
		} else {
			fan.currentFrame -= 1
		}
	} else {
		if fan.currentFrame >= auto_cast fan.end {
			if fan.loop {
				fan.currentFrame = fan.start
			}
		} else {
			fan.currentFrame += 1
		}
	}
	atEnd := fan.currentFrame <= fan.start if fan.reverse else fan.currentFrame >= fan.end
	if !fan.loop && atEnd && !fan.finishedNotified {
		fan.finishedNotified = true
		fan.ticker->stop()
		fan.onFinished->notify(fan, nil, fan.gameContext)
	}
}

FrameAnimationNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	fan := cast(^FrameAnimationNode)node
	DestroySubject(&fan.onFinished)
	FrameAnimationNode_ClearFrames(fan)
}

// FrameAnimationNode_ClearFrames removes all frames, releasing their textures.
FrameAnimationNode_ClearFrames :: proc(fan: ^FrameAnimationNode) {
	rm := Node_ResourceManager(fan)
	for f in fan.frames do ResourceManager_ReleaseTexture(rm, f)
	clear(&fan.frames)
	fan.currentFrame = 0
	fan.end = 0
}

FrameAnimationNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	fan := cast(^FrameAnimationNode)node
	fan.ticker->process()
}

FrameAnimationNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	fan := cast(^FrameAnimationNode)node
	if len(fan.frames) == 0 do return
	if !fan.enabled do return

	// Process ticker so animation cycles in both editor viewport and game
	fan.ticker->process()

	idx := int(fan.currentFrame) % len(fan.frames)
	texture := fan.frames[idx]
	if texture == nil || texture.texture.id == 0 do return

	source := Texture_Full(texture) // (its rectangle on an atlas page)

	pos := fan.globalPosition
	scl := fan.globalScale
	rot := fan.globalRotation

	// Around the origin (node_origin.odin); a negative scale mirrors there.
	size := Texture_Size(texture)
	origin := Node_OriginPx(fan, size)
	if rl.IsWindowReady() && texture.texture.id > 0 {
		Texture_DrawScaled(texture.texture, source, pos, size, scl, origin, rot, rl.WHITE)
	}
}

FrameAnimationNode_Start :: proc(fan: ^FrameAnimationNode) {
	fan.finishedNotified = false
	fan.ticker->start(true)
}
FrameAnimationNode_Stop :: proc(fan: ^FrameAnimationNode) {
	fan.ticker->stop()
}
FrameAnimationNode_Reset :: proc(fan: ^FrameAnimationNode) {
	fan.ticker->reset()
}
FrameAnimationNode_Pause :: proc(fan: ^FrameAnimationNode) {
	fan.ticker->pause()
}
