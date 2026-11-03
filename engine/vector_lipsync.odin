package engine

import "core:encoding/json"
import os "osx"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

// ============================================================================
// Lip-sync (Phase 14 V.7): mouth shapes timed to a voice. Rhubarb Lip Sync
// (github.com/DanielSWolf/rhubarb-lip-sync, MIT) turns a recording into
// mouth cues - A (M B P), B (most consonants), C (E), D (A), E (O), F (U W),
// and optionally G (F V), H (L), X (rest) - written as TSV ("0.00\tX") or
// JSON ({"mouthCues": [{"start", "end", "value"}]}).
//
// A LipSyncNode points at a mouth - a VectorShapeNode whose group's child
// groups are the mouth shapes (named A..H / X, or mapped: "A=MBP,B=etc") -
// and either plays its own sound or follows a voice someone else plays (a
// DialogueNode's lines). While the voice plays, the mouth's frame follows
// the cue at the voice's playback time; missing shapes fall back as
// Rhubarb's do (G -> B, H -> C, X -> A); at the end the mouth rests.
// ============================================================================

Lip_Cue :: struct {
	start: f32,
	shape: u8, // 'A'..'H', 'X'
}

// Lip_ParseCues: Rhubarb's TSV or JSON output (start times; each cue lasts
// until the next) - false when it's neither.
Lip_ParseCues :: proc(text: string, out: ^[dynamic]Lip_Cue) -> bool {
	clear(out)
	t := strings.trim_space(text)
	if strings.has_prefix(t, "{") {
		v, err := json.parse_string(t, allocator = context.temp_allocator)
		if err != nil do return false
		o, isObj := v.(json.Object)
		if !isObj do return false
		cues, isArr := o["mouthCues"].(json.Array)
		if !isArr do return false
		for c in cues {
			co, ok := c.(json.Object)
			if !ok do continue
			start: f32
			#partial switch x in co["start"] {
			case json.Float: start = f32(x)
			case json.Integer: start = f32(x)
			}
			val, _ := co["value"].(json.String)
			if len(val) > 0 do append(out, Lip_Cue{start, val[0]})
		}
		return len(out) > 0
	}
	for line in strings.split_lines(t, context.temp_allocator) {
		fields := strings.fields(line, context.temp_allocator)
		if len(fields) < 2 do continue
		start, ok := strconv.parse_f32(fields[0])
		if !ok || len(fields[1]) == 0 do continue
		append(out, Lip_Cue{start, fields[1][0]})
	}
	return len(out) > 0
}

// Lip_CueAt: the mouth shape at a time ('X' before the first cue).
Lip_CueAt :: proc(cues: []Lip_Cue, t: f32) -> u8 {
	shape: u8 = 'X'
	for c in cues {
		if c.start > t do break
		shape = c.shape
	}
	return shape
}

// Lip_FrameFor: the frame index showing a shape - its mapped name (mapping
// "A=MBP,B=etc"), else the shape's letter, else Rhubarb's fallback (G -> B,
// H -> C, X -> A); -1 when the mouth has none.
Lip_FrameFor :: proc(frames: []string, mapping: string, shape: u8) -> int {
	find :: proc(frames: []string, mapping: string, shape: u8) -> int {
		letter := string([]u8{shape})
		name := letter
		for pair in strings.split(mapping, ",", context.temp_allocator) {
			eq := strings.index_byte(pair, '=')
			if eq < 0 do continue
			if strings.trim_space(pair[:eq]) == letter do name = strings.trim_space(pair[eq + 1:])
		}
		for f, i in frames do if f == name do return i
		return -1
	}
	if i := find(frames, mapping, shape); i >= 0 do return i
	fallback: u8
	switch shape {
	case 'G': fallback = 'B'
	case 'H': fallback = 'C'
	case 'X': fallback = 'A'
	}
	if fallback != 0 do return find(frames, mapping, fallback)
	return -1
}

LipSyncNode :: struct {
	using node: Node,
	mouth:      string `gui:"true"`, // the mouth: a VectorShapeNode (path from this node, e.g. "../Mouth")
	sound:      string `gui:"true"`, // the voice it plays
	cues:       string `gui:"true"`, // Rhubarb's output ("" = the sound's .json / .tsv beside it)
	mapping:    string `gui:"true"`, // mouth frame names per shape ("A=MBP,B=etc"; "" = named A-H / X)
	autoplay:   bool `gui:"true"`,
	playing:    bool `gui:"true" save:"false"`,
	time:       f32 `gui:"true" save:"false"`, // seconds into the voice
	cueList:    [dynamic]Lip_Cue,
	voice:      Mixer_Voice_Handle,
	voiceSound: ^AudioSound, // (only when it plays its own sound)
	ownVoice:   bool,
	onFinished: EventSubject,
}

LipSyncNode_Create :: proc(scene: ^Scene, name: string = "LipSync", parent: ^Node = nil) -> ^LipSyncNode {
	l := CreateNode(scene.manager, LipSyncNode)
	l.name = strings.clone(name, l.allocator)
	l.mouth = strings.clone("../Mouth", l.allocator)
	l.cueList = make([dynamic]Lip_Cue, Engine_HeapAllocator())
	l.update = LipSyncNode_Update
	l.ready = proc(n: ^Node, ctx: ^GameContext) {
		l := cast(^LipSyncNode)n
		if l.autoplay && l.sound != "" do LipSyncNode_Play(l, l.sound)
	}
	l.onDestroy = proc(n: ^Node, ctx: ^GameContext) {
		l := cast(^LipSyncNode)n
		LipSyncNode_Stop(l)
		delete(l.cueList)
		DestroySubject(&l.onFinished)
	}
	InitializeSubject(&l.onFinished, "finished", l)
	scene->addNode(l, parent)
	return l
}

// lip_read_cues: a sound's cues - `cues`, else the sound's .json / .tsv /
// .txt beside it - from the game's package (an exported game, the web,
// Android) or the disk.
@(private = "file")
lip_read_cues :: proc(l: ^LipSyncNode, sound: string) -> (string, bool) {
	paths := make([dynamic]string, context.temp_allocator)
	if l.cues != "" {
		append(&paths, l.cues)
	} else {
		stem := strings.trim_suffix(sound, filepath.ext(sound))
		for ext in ([]string{".json", ".tsv", ".txt"}) do append(&paths, strings.concatenate({stem, ext}, context.temp_allocator))
	}
	gc := l.gameContext
	for p in paths {
		if gc != nil && gc.game != nil {
			if b, ok := AssetManager_ReadFileBytes(&gc.game.assetManager, p, context.temp_allocator); ok do return string(b), true
		}
		full := Project_ResolveAssetPath(gc, p)
		if os.is_file(full) {
			if data, err := os.read_entire_file(full, context.temp_allocator); err == nil do return string(data), true
		}
	}
	return "", false
}

// LipSyncNode_LoadCues reads a sound's cues; false when there are none.
LipSyncNode_LoadCues :: proc(l: ^LipSyncNode, sound: string) -> bool {
	text, ok := lip_read_cues(l, sound)
	if !ok do return false
	return Lip_ParseCues(text, &l.cueList)
}

// LipSyncNode_Play plays a voice and moves the mouth with its cues.
LipSyncNode_Play :: proc(l: ^LipSyncNode, sound: string) -> bool {
	LipSyncNode_Stop(l)
	if !LipSyncNode_LoadCues(l, sound) do return false
	gc := l.gameContext
	if gc != nil && gc.game != nil && Audio_Ready() {
		rm := &gc.game.resourceManager
		if s, ok := rm.loadAudioSound(rm, Project_ResolveAssetPath(gc, sound)); ok {
			l.voiceSound = s
			l.voice = Mixer_PlaySound(s.pcm, Audio_BusFor(rm, s.filePath, "SFX"), owner = s)
		}
	}
	l.ownVoice = true
	l.playing = true
	l.time = 0
	return true
}

// LipSyncNode_Follow: the mouth follows a voice someone else plays (its
// handle: the playback time) - a DialogueNode's line.
LipSyncNode_Follow :: proc(l: ^LipSyncNode, sound: string, voice: Mixer_Voice_Handle) -> bool {
	LipSyncNode_Stop(l)
	if !LipSyncNode_LoadCues(l, sound) do return false
	l.voice = voice
	l.ownVoice = false
	l.playing = true
	l.time = 0
	return true
}

// LipSyncNode_Stop stops (its own voice too) and rests the mouth.
LipSyncNode_Stop :: proc(l: ^LipSyncNode) {
	if l.ownVoice do Mixer_StopVoice(l.voice)
	if l.voiceSound != nil {
		if gc := l.gameContext; gc != nil && gc.game != nil do ResourceManager_ReleaseSound(&gc.game.resourceManager, l.voiceSound)
		l.voiceSound = nil
	}
	l.voice = {}
	if l.playing {
		l.playing = false
		lip_set_mouth(l, 'X')
	}
}

// LipSyncNode_Mouth: the mouth node (nil when the path finds no Vector Shape).
LipSyncNode_Mouth :: proc(l: ^LipSyncNode) -> ^VectorShapeNode {
	if l.gameContext == nil || l.gameContext.scene == nil do return nil
	n := Node_ResolvePath(l.gameContext.scene.manager, l, l.mouth)
	if n == nil || n.typeId != VectorShapeNode do return nil
	return cast(^VectorShapeNode)n
}

@(private = "file")
lip_set_mouth :: proc(l: ^LipSyncNode, shape: u8) {
	m := LipSyncNode_Mouth(l)
	if m == nil do return
	if f := Lip_FrameFor(VectorShapeNode_Frames(m), l.mapping, shape); f >= 0 do m.frame = f
}

LipSyncNode_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	l := cast(^LipSyncNode)node
	if !l.playing do return
	audible := l.voice != {} && Mixer_VoicePlaying(l.voice)
	// The voice's own clock when there is one (no drift); else game time.
	if audible do l.time = Mixer_VoiceTime(l.voice)
	else do l.time += dt
	last := l.cueList[len(l.cueList) - 1].start if len(l.cueList) > 0 else 0
	if !audible && l.time > last + 0.05 && (l.voice == {} || !Mixer_VoicePlaying(l.voice)) {
		LipSyncNode_Stop(l)
		l.onFinished->notify(l, nil, ctx)
		return
	}
	lip_set_mouth(l, Lip_CueAt(l.cueList[:], l.time))
}
