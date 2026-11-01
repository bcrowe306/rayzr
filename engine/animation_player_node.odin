package engine

import "core:log"
import "core:math"
import "core:strings"
import "core:time"




AnimationPlayerNode :: struct {
	using node: Node,
	shininess: f32 `gui:"true" min:"0" max:"1"`, // lit: a glint from lights (#274; its image's _s.png too)
	animations: [dynamic]^Animation,
	animationIndex: int,
	currentFrame: int,
	ticker: Ticker,
	reverse: bool `gui:"true"`,
	autoplay: bool `gui:"true"`, // start playing when the node becomes ready
	fps: f32, // frames per second of animations without their own
	defaultAnimation: string, // selected when the node becomes ready ("" = the saved current one)
	// "animation_finished"(name): a non-looping animation reached its end.
	onFinished: EventSubject,
	// "animation_event"(method): a Method key fired (also for listeners
	// without a script method of that name).
	onEvent: EventSubject,
	finishedNotified: bool,
	loopsDone:        int, // times a looping animation wrapped since it started (state machines' "animation finished")
	// Animations added with AddFrameAnimation/AddSheetAnimation are owned
	// (freed with the node); AddAnimation keeps caller-owned ones as is.
	owned: [dynamic]^Animation,
	// Crossfade (AnimationPlayerNode_Play with a blend time): property tracks
	// shared with the previous animation blend from it.
	blendFrom:      ^Animation,
	blendFromTime:  f32,
	blendTime:      f32,
	blendElapsed:   f32,
	// The track clock (#176): seconds into the current animation. The sprite
	// frames drive it (their frame's time and the part of it shown), unless
	// the tracks run longer than the frames - then it runs on its own and
	// decides the loops and the end.
	time:    f32,
	playing: bool, // started and not stopped (pausing: the ticker)
}

AnimationPlayerNode_AddAnimation :: proc(animationPlayer: ^AnimationPlayerNode, animation: ^Animation) {
	found:bool
	for a in animationPlayer.animations {
		if a == animation {
			found = true
			break
		}
	}
	if !found {
		_, err := append(&animationPlayer.animations, animation)
		if err != nil {
			log.error("Error appending animation to AnimationPlayerNode: ", err)
			return
		}
		if len(animationPlayer.animations) > 0 {
			animationPlayer.animationIndex = len(animationPlayer.animations) - 1
		}
	}
	else {
		log.warn("Animation is already in the animations collection for this AnimationPlayerNode")
	}
}

AnimationPlayerNode_RemoveAnimation :: proc(animationPlayer: ^AnimationPlayerNode, index: int) -> (success: bool) {
	if index < 0 || index >= len(animationPlayer.animations) {
		log.errorf("Cannot remove animation with index %d. Index is out of bounds", index)
		return false
	}
	ordered_remove(&animationPlayer.animations, index)
	return true

}


AnimationPlayerNode_Create :: proc(scene: ^Scene, name: string = "") -> ^AnimationPlayerNode {

	apn := CreateNode(scene.manager, AnimationPlayerNode)
	AnimationPlayerNode_Init(apn)
	if name != "" {
		apn.name = strings.clone(name, apn.allocator) // owned: callers pass temp strings too
	}
	return apn
}

AnimationPlayerNode_Init :: proc(apn: ^AnimationPlayerNode) {
	apn.animations = make([dynamic]^Animation, apn.allocator)
	Ticker_Init(&apn.ticker, false)
	apn.update = AnimationPlayerNode_Update
	apn.render = AnimationPlayerNode_Render
	apn.ready = AnimationPlayerNode_Ready
	apn.onDestroy = AnimationPlayerNode_Destroy
	apn.owned = make([dynamic]^Animation, apn.allocator)
	InitializeSubject(&apn.onFinished, "animation_finished", apn)
	InitializeSubject(&apn.onEvent, "animation_event", apn)
	apn.fps = 12
	apn.ticker->setFPS(12)
	apn.ticker->setCallback(proc(ticker: ^Ticker, currentTick: int, user_data: rawptr) {
		apn := cast(^AnimationPlayerNode)user_data
		AnimationPlayerNode_AdvanceFrame(apn)
	}, apn)
}


AnimationPlayerNode_AdvanceFrame :: proc(apn: ^AnimationPlayerNode) {
	if len(apn.animations) == 0 do return
	a := apn.animations[apn.animationIndex]
	reversed := AnimationPlayerNode_IsReversed(apn, a)
	prevFrame := apn.currentFrame
	if reversed {
		if apn.currentFrame <= auto_cast a.startFrame {
			if a.loop {
				apn.currentFrame = a.endFrame
				if a.tracks == nil || !Animation_TracksLonger(apn, a) do apn.loopsDone += 1
			}
		}
		else {
			apn.currentFrame -= 1
		}
	}
	else {
		if apn.currentFrame >= auto_cast a.endFrame {
			if a.loop {
				apn.currentFrame = a.startFrame
				if a.tracks == nil || !Animation_TracksLonger(apn, a) do apn.loopsDone += 1
			}
		}
		else {
			apn.currentFrame += 1
		}
	}
	_ = prevFrame
	tracksLonger := a.tracks != nil && Animation_TracksLonger(apn, a)
	if tracksLonger && apn.currentFrame != prevFrame && (apn.currentFrame == a.startFrame || apn.currentFrame == a.endFrame) {
		// (The frames looping under longer tracks: not the animation's loop.)
	}
	if a != nil && len(a.frameDurations) > apn.currentFrame && a.frameDurations[apn.currentFrame] > 0 {
		dur := a.frameDurations[apn.currentFrame]
		apn.ticker.secondsPerFrame = time.Duration(math.round(f64(dur) * f64(time.Second)))
	} else {
		fps := AnimationPlayerNode_FPS(apn)
		if fps <= 0 do apn.ticker.secondsPerFrame = max(time.Duration)
		else do apn.ticker.secondsPerFrame = time.Duration(math.round(f64(time.Second) / f64(fps)))
	}
	// A non-looping animation that reached its last frame finishes once
	// (tracks running longer: when they end - AnimationPlayerNode_Update).
	atEnd := apn.currentFrame <= a.startFrame if reversed else apn.currentFrame >= a.endFrame
	if !a.loop && atEnd && !apn.finishedNotified && !tracksLonger {
		apn.finishedNotified = true
		apn.ticker->stop()
		apn.onFinished->notify(apn, a.name, apn.gameContext)
	}
}

AnimationPlayerNode_Ready :: proc(node: ^Node, gameContext: ^GameContext) {
	apn := cast(^AnimationPlayerNode)node
	if apn.defaultAnimation != "" {
		for a, i in apn.animations do if a.name == apn.defaultAnimation do AnimationPlayerNode_SetAnimationIndex(apn, i)
	}
	if apn.autoplay && len(apn.animations) > 0 do AnimationPlayerNode_Start(apn)
}

// AnimationPlayerNode_IsReversed: the animation plays backwards (its own
// Reverse, flipped by the player's).
AnimationPlayerNode_IsReversed :: proc(apn: ^AnimationPlayerNode, a: ^Animation) -> bool {
	return apn.reverse != (a != nil && a.reverse)
}

// AnimationPlayerNode_FPS: the current animation's rate (its own, else the
// player's).
AnimationPlayerNode_FPS :: proc(apn: ^AnimationPlayerNode) -> f32 {
	if a := AnimationPlayerNode_GetAnimation(apn); a != nil && a.fps > 0 do return a.fps
	return apn.fps if apn.fps > 0 else 12
}

@(private = "file")
apply_fps :: proc(apn: ^AnimationPlayerNode) {
	fps := AnimationPlayerNode_FPS(apn)
	a := AnimationPlayerNode_GetAnimation(apn)
	apn.ticker.framesPerSecond = fps
	if a != nil && len(a.frameDurations) > apn.currentFrame && a.frameDurations[apn.currentFrame] > 0 {
		dur := a.frameDurations[apn.currentFrame]
		apn.ticker.secondsPerFrame = time.Duration(math.round(f64(dur) * f64(time.Second)))
	} else {
		if fps <= 0 do apn.ticker.secondsPerFrame = max(time.Duration)
		else do apn.ticker.secondsPerFrame = time.Duration(math.round(f64(time.Second) / f64(fps)))
	}
}

AnimationPlayerNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	apn := cast(^AnimationPlayerNode)node
	DestroySubject(&apn.onFinished)
	DestroySubject(&apn.onEvent)
	rm := &gameContext.game.resourceManager if gameContext != nil && gameContext.game != nil else Node_ResourceManager(apn)
	for a in apn.owned {
		if a.renderFrame == FA_RenderFrame {
			fa := cast(^FrameAnimation)a
			for f in fa.frames do if f != nil do ResourceManager_ReleaseTexture(rm, f)
			FrameAnimation_Destroy(fa)
		} else if a.renderFrame == SSA_RenderFrame {
			ssa := cast(^SpriteSheetAnimation)a
			if ssa.spriteSheet != nil do ResourceManager_ReleaseTexture(rm, ssa.spriteSheet)
			delete(ssa.cells)
			delete(ssa.frameDurations)
		}
	}
	clear(&apn.owned)
	clear(&apn.animations)
}

// AnimationPlayerNode_AddFrameAnimation adds an owned animation that plays
// a list of image files.
AnimationPlayerNode_AddFrameAnimation :: proc(apn: ^AnimationPlayerNode, rm: ^ResourceManager, name: string, framePaths: []string, loop := true) -> ^FrameAnimation {
	fa := new(FrameAnimation, apn.allocator)
	fa.frames = make([dynamic]^Texture, apn.allocator)
	FrameAnimation_Init(fa, strings.clone(name, apn.allocator))
	fa.loop = loop
	if rm != nil {
		for p in framePaths do FrameAnimation_AddFrame(fa, rm, p)
	}
	append(&apn.owned, cast(^Animation)fa)
	AnimationPlayerNode_AddAnimation(apn, fa)
	return fa
}

// AnimationPlayerNode_AddSheetAnimation adds an owned sprite-sheet animation
// (grid columns x rows, frames start..end in reading order).
AnimationPlayerNode_AddSheetAnimation :: proc(apn: ^AnimationPlayerNode, rm: ^ResourceManager, name: string, sheetPath: string, grid: [2]int, start, end: int, loop := true) -> ^SpriteSheetAnimation {
	ssa := new(SpriteSheetAnimation, apn.allocator)
	SpriteSheetAnimation_Init(ssa, strings.clone(name, apn.allocator))
	ssa.grid = {max(grid.x, 1), max(grid.y, 1)}
	ssa.startFrame, ssa.endFrame = start, end
	ssa.loop = loop
	if rm != nil && sheetPath != "" do SpriteSheetAnimation_LoadSpirteSheet(ssa, rm, sheetPath)
	append(&apn.owned, cast(^Animation)ssa)
	AnimationPlayerNode_AddAnimation(apn, ssa)
	return ssa
}

AnimationPlayerNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	apn := cast(^AnimationPlayerNode)node
	Ticker_ProcessDt(&apn.ticker, deltaTime)
	if apn.blendFrom != nil {
		apn.blendElapsed += deltaTime
		if apn.blendElapsed >= apn.blendTime do apn.blendFrom = nil
	}
	if a := AnimationPlayerNode_GetAnimation(apn); a != nil && len(a.tracks) > 0 {
		AnimationPlayerNode_AdvanceClock(apn, a, deltaTime)
		AnimationPlayerNode_ApplyTracks(apn, apn.time)
	}
}

// AnimationPlayerNode_AdvanceClock moves the track clock `dt` seconds on
// and fires the event keys it passes (a loop: up to the end, then from the
// start).
AnimationPlayerNode_AdvanceClock :: proc(apn: ^AnimationPlayerNode, a: ^Animation, dt: f32) {
	reversed := AnimationPlayerNode_IsReversed(apn, a)
	D := Animation_Duration(apn, a)
	prev := apn.time
	if !Animation_TracksLonger(apn, a) {
		// The frames drive it: their frame's time and the part of it shown.
		rel := apn.currentFrame - a.startFrame
		fd := Animation_GetFrameDuration(a, apn.currentFrame, AnimationPlayerNode_FPS(apn))
		el := min(f32(time.duration_seconds(apn.ticker.elapsedTime)), fd) if apn.playing && apn.ticker.running else 0
		t := Animation_FrameTime(apn, a, f32(rel) + 1) - el if reversed else Animation_FrameTime(apn, a, f32(rel)) + el
		if !apn.playing && reversed do t = Animation_FrameTime(apn, a, f32(rel))
		t = clamp(t, 0, D)
		apn.time = t
		if !apn.playing || !apn.ticker.running do return
		if !reversed {
			if t + TRACK_KEY_EPS < prev && a.loop { // looped
				AnimationPlayerNode_FireEvents(apn, prev, D)
				AnimationPlayerNode_FireEvents(apn, 0, t, inclusive = true)
			} else if t > prev {
				AnimationPlayerNode_FireEvents(apn, prev, t)
			}
		} else {
			if t > prev + TRACK_KEY_EPS && a.loop {
				AnimationPlayerNode_FireEvents(apn, prev, 0)
				AnimationPlayerNode_FireEvents(apn, D, t, inclusive = true)
			} else if t < prev {
				AnimationPlayerNode_FireEvents(apn, prev, t)
			}
		}
		return
	}
	// The tracks run longer: the clock runs on its own.
	if !apn.playing || !apn.ticker.running || D <= 0 do return
	t := prev - dt if reversed else prev + dt
	switch {
	case !reversed && t >= D:
		AnimationPlayerNode_FireEvents(apn, prev, D)
		if a.loop {
			for t >= D do t -= D
			apn.loopsDone += 1
			AnimationPlayerNode_FireEvents(apn, 0, t, inclusive = true)
		} else {
			t = D
			animation_finish(apn, a)
		}
	case reversed && t <= 0:
		AnimationPlayerNode_FireEvents(apn, prev, 0)
		if a.loop {
			for t <= 0 do t += D
			apn.loopsDone += 1
			AnimationPlayerNode_FireEvents(apn, D, t, inclusive = true)
		} else {
			t = 0
			animation_finish(apn, a)
		}
	case:
		AnimationPlayerNode_FireEvents(apn, prev, t)
	}
	apn.time = t
}

// animation_finish: a non-looping animation reached its end (once).
@(private = "file")
animation_finish :: proc(apn: ^AnimationPlayerNode, a: ^Animation) {
	if apn.finishedNotified do return
	apn.finishedNotified = true
	apn.playing = false
	apn.ticker->stop()
	apn.onFinished->notify(apn, a.name, apn.gameContext)
}

AnimationPlayerNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	apn := cast(^AnimationPlayerNode)node
	if len(apn.animations) == 0 do return
	animation := apn.animations[apn.animationIndex]
	if animation != nil && animation.renderFrame != nil {
		animation->renderFrame(apn.currentFrame, node)
	}
}

AnimationPlayerNode_Start :: proc(apn: ^AnimationPlayerNode) {
	apn.finishedNotified = false
	apn.loopsDone = 0
	apply_fps(apn)
	apn.playing = true
	if a := AnimationPlayerNode_GetAnimation(apn); a != nil {
		reversed := AnimationPlayerNode_IsReversed(apn, a)
		apn.currentFrame = a.endFrame if reversed else a.startFrame
		apn.time = Animation_Duration(apn, a) if reversed else 0
		if a.tracks != nil do AnimationPlayerNode_FireEvents(apn, apn.time, apn.time, inclusive = true) // (the keys at the start)
	}
	apn.ticker->start(true)
}

// AnimationPlayerNode_Play switches to an animation (by name) and starts
// it; with blend > 0 its property tracks crossfade from the current
// animation's values over `blend` seconds.
AnimationPlayerNode_Play :: proc(apn: ^AnimationPlayerNode, name: string, blend: f32 = 0) {
	prev := AnimationPlayerNode_GetAnimation(apn)
	prevTime := apn.time
	if name != "" do AnimationPlayerNode_SetAnimationByName(apn, name)
	next := AnimationPlayerNode_GetAnimation(apn)
	apn.blendFrom = nil
	if blend > 0 && prev != nil && prev != next && len(prev.tracks) > 0 {
		apn.blendFrom = prev
		apn.blendFromTime = prevTime
		apn.blendTime = blend
		apn.blendElapsed = 0
	}
	AnimationPlayerNode_Start(apn)
}
AnimationPlayerNode_Stop :: proc(apn: ^AnimationPlayerNode) {
	apn.ticker->stop()
	apn.playing = false
	if a := AnimationPlayerNode_GetAnimation(apn); a != nil {
		for &tr in a.tracks {
			if tr.kind == .Audio {
				for &h in tr.voiceHandles {
					if Mixer_VoicePlaying(h) do Mixer_StopVoice(h)
					h = {}
				}
			}
		}
	}
}
// AnimationPlayerNode_Reset: back to the current animation's first frame
// (its last when reversed), playing or not.
AnimationPlayerNode_Reset :: proc(apn: ^AnimationPlayerNode) {
	apn.ticker->reset()
	apn.finishedNotified = false
	apn.loopsDone = 0
	apn.blendFrom = nil
	if a := AnimationPlayerNode_GetAnimation(apn); a != nil {
		reversed := AnimationPlayerNode_IsReversed(apn, a)
		apn.currentFrame = a.endFrame if reversed else a.startFrame
		apn.time = Animation_Duration(apn, a) if reversed else 0
	}
}

AnimationPlayerNode_Pause :: proc(apn: ^AnimationPlayerNode) {
	apn.ticker->pause()
}

AnimationPlayerNode_Resume :: proc(apn: ^AnimationPlayerNode) {
	apn.ticker->resume()
}

// AnimationPlayerNode_SetFPS: the player's rate (animations with their own
// FPS keep it).
AnimationPlayerNode_SetFPS :: proc(apn: ^AnimationPlayerNode, fps: f32) {
	apn.fps = max(fps, 0.1)
	apply_fps(apn)
}

AnimationPlayerNode_SetAnimationIndex :: proc(apn: ^AnimationPlayerNode, index: int) {
	if len(apn.animations) == 0 do return
	index := clamp(index, 0, len(apn.animations) - 1)
	apn.animationIndex = index
	apply_fps(apn)
}

AnimationPlayerNode_SetAnimationByName :: proc(apn: ^AnimationPlayerNode, name: string) {
	index := -1
	for animation, i in apn.animations {

		if animation.name == name {
			index = i
			break
		}
	}
	if index != -1 {
		AnimationPlayerNode_SetAnimationIndex(apn, index)
	}
	else {
		log.warnf("Animation with name '%s' not found in AnimationPlayerNode", name)
	}
}


AnimationPlayerNode_GetAnimation :: proc(apn: ^AnimationPlayerNode) -> ^Animation {
	if len(apn.animations) == 0 {
		return nil
	}
	return apn.animations[apn.animationIndex]
}

AnimationPlayerNode_GetAnimationName :: proc(apn: ^AnimationPlayerNode) -> string {
	animation := AnimationPlayerNode_GetAnimation(apn)
	if animation == nil {
		return ""
	}
	return animation.name
}
