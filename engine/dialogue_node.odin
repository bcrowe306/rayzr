package engine

import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// DialogueNode: a dialogue box on a UI layer. Scripts queue lines (a
// speaker and rich text, or localization keys); each line types out at
// revealSpeed characters per second; the advance action (default
// "confirm") shows the rest of a line, then the next one; after the last
// the box closes. Events: "line_shown"(index, 1-based) when a line is fully
// shown, "finished" when the box closes.
//
// A line may offer choices: once it is shown they are listed above the box
// (move_up / move_down or the mouse pick one, the advance action or a click
// takes it); "chosen"(choice, 1-based) fires, then the next line follows
// unless the handler showed new lines. Auto advance goes on by itself a
// moment after each line; skip shows and passes lines at once. Both stop
// at choices.
//
// A line may name a voice sound (played when the line starts). Mode
// Subtitles shows the lines on the subtitle track instead of a box
// (subtitles.odin: cutscene voice-over, barks): each line stays for its
// voice's length (else its reading time), then the next one follows by
// itself; the advance action skips. With the player's subtitles turned off
// the lines still play and time out (events too), unseen.
// ============================================================================

Dialogue_Line :: struct {
	speaker: string,
	text:    string,
	voice:   string, // a sound played with the line ("" = none)
	choices: []string, // offered once the line is shown (none = a plain line)
}

Dialogue_Mode :: enum u8 {Box, Subtitles}

DialogueNode :: struct {
	using ui:      UIElement,
	font:          string `gui:"true"`,
	fontSize:      f32 `gui:"true" min:"8" max:"96"`,
	textColor:     rl.Color `gui:"true"`,
	speakerColor:  rl.Color `gui:"true"`,
	panelColor:    rl.Color `gui:"true"`,
	borderColor:   rl.Color `gui:"true"`,
	padding:       f32 `gui:"true" min:"0" max:"100"`,
	revealSpeed:   f32 `gui:"true" min:"0" max:"500"`, // characters per second (0 = whole lines)
	advanceAction: string `gui:"true"`,                 // input action that advances ("confirm")
	localized:     bool `gui:"true"`,                   // lines are locale keys
	mode:          Dialogue_Mode `gui:"true"`,          // a box, or the subtitle track
	lipSync:       string `gui:"true"`,                 // a LipSyncNode (path) moving a mouth with the voices
	choiceColor:   rl.Color `gui:"true"`,               // the selected choice's fill
	autoAdvance:   bool `gui:"true"`,                   // go on by itself after each line
	autoDelay:     f32 `gui:"true" min:"0" max:"10"`,   // seconds after a line is shown (plus a little per character)
	skip:          bool,                                // show and pass lines at once (scripts toggle it)

	lines:         [dynamic]Dialogue_Line,
	current:       int,  // index into lines; -1 = closed
	revealed:      f32,
	lineDone:      bool,
	time:          f32,
	started:       bool, // the current line's voice / subtitle began
	lineTime:      f32,  // Subtitles mode: seconds left on this line
	subId:         u64,
	voice:         Mixer_Voice_Handle,
	voiceSound:    ^AudioSound,
	choice:        int,  // the selected choice (0-based) while choices are up
	choiceTaken:   int,  // the last choice taken (1-based; 0 = none yet)
	waited:        f32,  // seconds since the line was shown (auto / skip)
	shows:         int,  // DialogueNode_Show calls (a "chosen" handler that shows new lines)
	onLineShown:   EventSubject,
	onFinished:    EventSubject,
	onChosen:      EventSubject,
}

DialogueNode_Create :: proc(scene: ^Scene, name: string = "Dialogue", parent: ^Node = nil) -> ^DialogueNode {
	d := CreateNode(scene.manager, DialogueNode)
	DialogueNode_Init(d)
	d.name = strings.clone(name, d.allocator) // owned: callers pass temp strings too
	scene->addNode(d, parent)
	return d
}

DialogueNode_Init :: proc(d: ^DialogueNode) {
	UIElement_Init(&d.ui, .Label, {900, 170})
	d.position = {190, 520}
	d.fontSize = 24
	d.textColor = {238, 240, 246, 255}
	d.speakerColor = {250, 204, 21, 255}
	d.panelColor = {15, 18, 28, 230}
	d.borderColor = {92, 141, 255, 255}
	d.padding = 20
	d.revealSpeed = 40
	d.choiceColor = {92, 141, 255, 200}
	d.autoDelay = 1.2
	d.advanceAction = "confirm"
	d.lines = make([dynamic]Dialogue_Line, d.allocator)
	d.current = -1
	d.update = DialogueNode_Update
	d.render = DialogueNode_Render
	d.onDestroy = DialogueNode_Destroy
	InitializeSubject(&d.onLineShown, "line_shown", d)
	InitializeSubject(&d.onFinished, "finished", d)
	InitializeSubject(&d.onChosen, "chosen", d)
}

DialogueNode_Destroy :: proc(node: ^Node, ctx: ^GameContext) {
	d := cast(^DialogueNode)node
	line_end(d)
	DestroySubject(&d.onLineShown)
	DestroySubject(&d.onFinished)
	DestroySubject(&d.onChosen)
}

// DialogueNode_Show opens the box with these lines (replacing any).
DialogueNode_Show :: proc(d: ^DialogueNode, lines: []Dialogue_Line) {
	line_end(d)
	clear(&d.lines)
	for l in lines {
		choices := make([]string, len(l.choices), d.allocator)
		for c, i in l.choices do choices[i] = strings.clone(c, d.allocator)
		append(&d.lines, Dialogue_Line{strings.clone(l.speaker, d.allocator), strings.clone(l.text, d.allocator), strings.clone(l.voice, d.allocator), choices})
	}
	d.current = 0 if len(d.lines) > 0 else -1
	d.revealed = 0
	d.lineDone = false
	d.started = false
	d.choice = 0
	d.waited = 0
	d.shows += 1
}

// DialogueNode_HasChoices: the current line offers choices.
DialogueNode_HasChoices :: proc(d: ^DialogueNode) -> bool {
	return DialogueNode_IsOpen(d) && len(d.lines[d.current].choices) > 0
}

// DialogueNode_Choose takes choice `index` (0-based) of the shown line:
// "chosen"(index + 1), then the next line unless the handler showed others.
DialogueNode_Choose :: proc(d: ^DialogueNode, index: int, ctx: ^GameContext) -> bool {
	if !DialogueNode_HasChoices(d) || !d.lineDone || index < 0 || index >= len(d.lines[d.current].choices) do return false
	d.choiceTaken = index + 1
	shows := d.shows
	d.onChosen->notify(d, index + 1, ctx)
	if d.shows == shows && DialogueNode_HasChoices(d) do dialogue_next_line(d, ctx)
	return true
}

// line_start: the current line's voice and (Subtitles mode) subtitle.
@(private = "file")
line_start :: proc(d: ^DialogueNode, ctx: ^GameContext) {
	d.started = true
	gc := ctx if ctx != nil else d.gameContext
	l := d.lines[d.current]
	length: f32
	if l.voice != "" && gc != nil && gc.game != nil {
		rm := &gc.game.resourceManager
		if s, ok := rm.loadAudioSound(rm, Project_ResolveAssetPath(gc, l.voice)); ok {
			d.voiceSound = s
			length = f32(len(s.pcm) / 2) / MIXER_RATE
			if Audio_Ready() do d.voice = Mixer_PlaySound(s.pcm, Audio_BusFor(rm, s.filePath, "SFX"), owner = s)
		}
		if ls := dialogue_lipsync(d); ls != nil do LipSyncNode_Follow(ls, l.voice, d.voice)
	}
	if d.mode == .Subtitles {
		speaker, text := line_text(d, ctx)
		d.lineTime = length + 0.3 if length > 0 else Subtitles_ReadingTime(text)
		d.subId = Subtitles_Show(text, speaker, d.lineTime, .Dialogue)
		line_shown(d, ctx)
	}
}

// line_end: stops the line's voice and takes its subtitle down.
@(private = "file")
line_end :: proc(d: ^DialogueNode) {
	if ls := dialogue_lipsync(d); ls != nil && ls.playing do LipSyncNode_Stop(ls)
	Mixer_StopVoice(d.voice)
	d.voice = {}
	if d.voiceSound != nil {
		if gc := d.gameContext; gc != nil && gc.game != nil do ResourceManager_ReleaseSound(&gc.game.resourceManager, d.voiceSound)
		d.voiceSound = nil
	}
	Subtitles_Hide(d.subId)
	d.subId = 0
	d.started = false
}

DialogueNode_IsOpen :: proc(d: ^DialogueNode) -> bool {
	return d.current >= 0 && d.current < len(d.lines)
}

@(private = "file")
line_text :: proc(d: ^DialogueNode, ctx: ^GameContext) -> (speaker, text: string) {
	l := d.lines[d.current]
	gc := ctx if ctx != nil else d.gameContext
	if d.localized && gc != nil {
		return Locale_Get(gc.game, l.speaker) if l.speaker != "" else "", Locale_Get(gc.game, l.text)
	}
	return l.speaker, l.text
}

// DialogueNode_Advance: the rest of the line, else the next line (closing
// after the last).
DialogueNode_Advance :: proc(d: ^DialogueNode, ctx: ^GameContext) {
	if !DialogueNode_IsOpen(d) do return
	if !d.lineDone {
		d.revealed = 1e9
		line_shown(d, ctx)
		return
	}
	if len(d.lines[d.current].choices) > 0 {
		DialogueNode_Choose(d, d.choice, ctx)
		return
	}
	dialogue_next_line(d, ctx)
}

@(private = "file")
line_shown :: proc(d: ^DialogueNode, ctx: ^GameContext) {
	d.lineDone = true
	d.waited = 0
	d.choice = 0
	d.onLineShown->notify(d, d.current + 1, ctx)
}

@(private = "file")
dialogue_next_line :: proc(d: ^DialogueNode, ctx: ^GameContext) {
	line_end(d)
	d.current += 1
	d.revealed = 0
	d.lineDone = false
	d.waited = 0
	if d.current >= len(d.lines) {
		d.current = -1
		d.onFinished->notify(d, nil, ctx)
	}
}

DialogueNode_Close :: proc(d: ^DialogueNode, ctx: ^GameContext) {
	if !DialogueNode_IsOpen(d) do return
	line_end(d)
	d.current = -1
	d.onFinished->notify(d, nil, ctx)
}

DialogueNode_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	d := cast(^DialogueNode)node
	d.time += dt
	if !DialogueNode_IsOpen(d) do return
	if !d.started do line_start(d, ctx)
	if d.mode == .Subtitles {
		d.lineTime -= dt
		if d.lineTime <= 0 {
			DialogueNode_Advance(d, ctx) // the next line by itself
			return
		}
	} else if !d.lineDone {
		_, text := line_text(d, ctx)
		total := Text_PlainLength(text, true)
		d.revealed += d.revealSpeed * dt if d.revealSpeed > 0 else f32(total)
		if d.skip do d.revealed = f32(total)
		if int(d.revealed) >= total do line_shown(d, ctx)
	}
	gc := ctx if ctx != nil else d.gameContext
	if DialogueNode_HasChoices(d) && d.lineDone {
		dialogue_choices_input(d, gc, ctx)
		return
	}
	if d.lineDone && (d.skip || d.autoAdvance) && d.mode == .Box {
		d.waited += dt
		_, text := line_text(d, ctx)
		wait := f32(0.05) if d.skip else d.autoDelay + 0.02 * f32(Text_PlainLength(text, true))
		if d.waited >= wait {
			DialogueNode_Advance(d, ctx)
			return
		}
	}
	if dialogue_pressed(gc, d.advanceAction) do DialogueNode_Advance(d, ctx)
}

@(private = "file")
dialogue_pressed :: proc(gc: ^GameContext, action: string) -> bool {
	if gc == nil || gc.input == nil || action == "" do return false
	st, ok := Input_ActionStateByName(gc.input, action)
	return ok && st.pressed
}

// dialogue_choices_input: move_up / move_down and the mouse pick, the
// advance action or a click takes.
@(private = "file")
dialogue_choices_input :: proc(d: ^DialogueNode, gc: ^GameContext, ctx: ^GameContext) {
	n := len(d.lines[d.current].choices)
	if dialogue_pressed(gc, "move_up") do d.choice = (d.choice + n - 1) % n
	if dialogue_pressed(gc, "move_down") do d.choice = (d.choice + 1) % n
	if gc != nil && gc.input != nil && UI_IsMouseInViewport(gc) {
		mouse := UI_GetMousePos(gc)
		for i in 0 ..< n {
			if UI_PointInRect(mouse, DialogueNode_ChoiceRect(d, i)) {
				d.choice = i
				if UI_IsMousePressed(gc) {
					DialogueNode_Choose(d, i, ctx)
					return
				}
			}
		}
	}
	if dialogue_pressed(gc, d.advanceAction) do DialogueNode_Choose(d, d.choice, ctx)
}

// DialogueNode_ChoiceRect: where choice i is drawn - a column of buttons
// above the box, the first on top.
DialogueNode_ChoiceRect :: proc(d: ^DialogueNode, i: int) -> rl.Rectangle {
	rect := UI_GetElementRect(&d.ui)
	n := len(d.lines[d.current].choices) if DialogueNode_IsOpen(d) else 0
	h := d.fontSize * 1.8
	gap := d.fontSize * 0.4
	w := rect.width * 0.7
	top := rect.y - gap - f32(n) * (h + gap)
	return {rect.x + (rect.width - w) / 2, top + f32(i) * (h + gap), w, h}
}

DialogueNode_Render :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	d := cast(^DialogueNode)node
	if !rl.IsWindowReady() || !DialogueNode_IsOpen(d) || d.mode == .Subtitles do return // (Subtitles: on the track)
	rect := UI_GetElementRect(&d.ui)
	rl.DrawRectangleRounded(rect, 0.08, 8, d.panelColor)
	rl.DrawRectangleRoundedLinesEx(rect, 0.08, 8, 2, d.borderColor)
	speaker, text := line_text(d, ctx)
	f := Text_GetFont(d.font, d.fontSize, false, ctx)
	measure :: proc(r: rune, size: f32, data: rawptr) -> f32 {return Text_MeasureRune(cast(^Text_Font)data, r, size)}
	y := rect.y + d.padding
	if speaker != "" {
		sg, ss := Text_Layout(speaker, {d.speakerColor, d.fontSize * 0.9, {}}, 0, 0, 1, false, measure, f)
		Text_DrawGlyphs(f, sg, {rect.x + d.padding, y}, 0, 1, -1, d.time, ctx = ctx)
		y += ss.y + d.fontSize * 0.35
	}
	glyphs, _ := Text_Layout(text, {d.textColor, d.fontSize, {}}, rect.width - 2 * d.padding, 0, 1.25, true, measure, f)
	reveal := -1 if d.lineDone else int(d.revealed)
	Text_DrawGlyphs(f, glyphs, {rect.x + d.padding, y}, 0, 1, reveal, d.time, ctx = ctx)
	if d.lineDone && DialogueNode_HasChoices(d) {
		for c, i in d.lines[d.current].choices {
			r := DialogueNode_ChoiceRect(d, i)
			fill := d.choiceColor if i == d.choice else d.panelColor
			rl.DrawRectangleRounded(r, 0.25, 8, fill)
			rl.DrawRectangleRoundedLinesEx(r, 0.25, 8, 2, d.borderColor)
			label := Locale_Get(ctx.game, c) if d.localized && ctx != nil && ctx.game != nil else c
			cg, cs := Text_Layout(label, {d.textColor, d.fontSize, {}}, r.width - d.padding, 0, 1, false, measure, f)
			Text_DrawGlyphs(f, cg, {r.x + (r.width - cs.x) / 2, r.y + (r.height - cs.y) / 2}, 0, 1, -1, d.time, ctx = ctx)
		}
	} else if d.lineDone {
		// "More" marker, bobbing.
		bob := f32(int(d.time * 3) % 2) * 3
		p := [2]f32{rect.x + rect.width - d.padding, rect.y + rect.height - d.padding + bob}
		rl.DrawTriangle(p + {-12, -10}, p + {-6, 0}, p + {0, -10}, d.borderColor)
	}
}

// dialogue_lipsync: the Lip Sync node `lipSync` names (nil: none).
@(private = "file")
dialogue_lipsync :: proc(d: ^DialogueNode) -> ^LipSyncNode {
	if d.lipSync == "" || d.gameContext == nil || d.gameContext.scene == nil do return nil
	n := Node_ResolvePath(d.gameContext.scene.manager, d, d.lipSync)
	if n == nil || n.typeId != LipSyncNode do return nil
	return cast(^LipSyncNode)n
}
