package engine

import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Subtitles (docs/accessibility.md): a track of lines shown at the bottom
// centre of the screen over everything, each for a time. Two kinds:
// Dialogue (spoken lines - DialogueNode in Subtitles mode, scripts) shown
// when the player's "subtitles" setting is on, and Caption (sounds:
// "[explosion]" - a Sound / Music node's Caption) when "captions" is on.
// Up to SUBTITLE_MAX at once (the oldest gives way). Size and backdrop
// follow the accessibility settings.
// ============================================================================

SUBTITLE_MAX :: 3

Subtitle_Kind :: enum u8 {Dialogue, Caption}

Subtitle :: struct {
	id:       u64,
	text:     string, // (heap)
	speaker:  string, // (heap)
	color:    rl.Color,
	timeLeft: f32,
	kind:     Subtitle_Kind,
}

@(private = "file")
subs: struct {
	lines:  [dynamic]Subtitle,
	nextId: u64,
	font:   string, // project font for subtitles ("" = the default)
}

// Subtitles_Show adds a line (returns its id, 0 when that kind is turned
// off - the caller's timing still runs).
Subtitles_Show :: proc(text: string, speaker := "", duration: f32 = 3, kind := Subtitle_Kind.Dialogue, color := rl.Color{}) -> u64 {
	if text == "" do return 0
	if kind == .Dialogue && !access.subtitles do return 0
	if kind == .Caption && !access.captions do return 0
	if len(subs.lines) >= SUBTITLE_MAX do subtitle_remove(0)
	subs.nextId += 1
	append(&subs.lines, Subtitle{
		id = subs.nextId,
		text = strings.clone(text),
		speaker = strings.clone(speaker),
		color = color if color != {} else (rl.Color{170, 205, 255, 255} if kind == .Caption else rl.Color{240, 240, 240, 255}), // (captions bluish)
		timeLeft = max(duration, 0.1),
		kind = kind,
	})
	return subs.nextId
}

// Subtitles_Hide removes one line (0 = nothing).
Subtitles_Hide :: proc(id: u64) {
	for s, i in subs.lines do if s.id == id {
		subtitle_remove(i)
		return
	}
}

Subtitles_Clear :: proc() {
	for len(subs.lines) > 0 do subtitle_remove(len(subs.lines) - 1)
	delete(subs.lines)
	subs.lines = nil
}

Subtitles_Count :: proc() -> int {return len(subs.lines)}

Subtitles_Lines :: proc() -> []Subtitle {return subs.lines[:]}

@(private = "file")
subtitle_remove :: proc(i: int) {
	delete(subs.lines[i].text)
	delete(subs.lines[i].speaker)
	ordered_remove(&subs.lines, i)
}

// Subtitles_Update counts lines down (real time: subtitles keep their
// pace through pauses).
Subtitles_Update :: proc(dt: f32) {
	for i := len(subs.lines) - 1; i >= 0; i -= 1 {
		subs.lines[i].timeLeft -= dt
		if subs.lines[i].timeLeft <= 0 do subtitle_remove(i)
	}
}

// Subtitles_ReadingTime: how long a line needs on screen (0.8 s + 15
// characters a second, at least 1.5 s).
Subtitles_ReadingTime :: proc(text: string) -> f32 {
	return max(0.8 + f32(Text_PlainLength(text, true)) / 15, 1.5)
}

// Subtitles_Render draws the track (screen space, bottom centre, newest at
// the bottom) - after the scene's layers.
Subtitles_Render :: proc(ctx: ^GameContext) {
	if len(subs.lines) == 0 || !rl.IsWindowReady() do return
	vw, vh: f32 = 1280, 720
	if ctx != nil && ctx.game != nil && ctx.game.virtualSize.x > 0 do vw, vh = ctx.game.virtualSize.x, ctx.game.virtualSize.y
	size := vh / 30 * access.subtitleScale // 24 px at 720
	f := Text_GetFont("", size, false, ctx)
	measure :: proc(r: rune, size: f32, data: rawptr) -> f32 {return Text_MeasureRune(cast(^Text_Font)data, r, size)}
	maxW := vw * 0.8
	pad := size * 0.4
	y := vh - size * 1.6
	for i := len(subs.lines) - 1; i >= 0; i -= 1 {
		s := subs.lines[i]
		text := s.text
		if s.speaker != "" do text = strings.concatenate({"[color=#facc15]", s.speaker, ":[/color] ", s.text}, context.temp_allocator)
		glyphs, ts := Text_Layout(text, {s.color, size, {}}, maxW, 1, 1.2, true, measure, f) // (lines centred)
		box := rl.Rectangle{(vw - ts.x) / 2 - pad, y - ts.y - pad, ts.x + pad * 2, ts.y + pad * 2}
		if access.subtitleBackground > 0 do rl.DrawRectangleRounded(box, 0.25, 6, rl.ColorAlpha(rl.BLACK, access.subtitleBackground))
		Text_DrawGlyphs(f, glyphs, {(vw - ts.x) / 2, y - ts.y}, 0, 1, -1, 0, ctx = ctx)
		y = box.y - size * 0.3
	}
}
