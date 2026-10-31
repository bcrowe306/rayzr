package engine

import "base:runtime"
import "core:math"
import "core:strings"
import "core:sync"
import rl "vendor:raylib"

// ============================================================================
// The audio mixer (docs/audio_mixer.md).
//
// Every game sound and music track is a *voice* playing into a *bus*. A bus
// has a volume (fader), pan, mute / solo, an effects chain and an output -
// the Master bus or another bus. Each audio block:
//
//   1. every playing voice is mixed (pitch = resampling, volume / pan
//      ramped over the block so changes don't click) into its bus,
//   2. buses are processed children first: effects, then fader and pan,
//      peaks for the meters, added into their output bus,
//   3. Master's result (effects, fader, a final clip) goes to the device.
//
// Sounds are decoded once to 48 kHz stereo floats; music streams - frames
// are pulled from raylib's decoder for the file (mixer_decode.odin). The
// mixer runs behind one raylib audio stream whose callback renders blocks
// on the audio thread; game-thread calls take a mutex for a moment, the
// callback holds it for one block and never allocates.
// ============================================================================

MIXER_RATE :: 48000
MIXER_MAX_BUSES :: 32
MIXER_MAX_VOICES :: 128
MIXER_MAX_EFFECTS :: 8
MIXER_BLOCK :: 4096 // frames per callback at most
MIXER_STREAM_FIFO :: 8192 // frames buffered per streaming voice

Mixer_Bus :: struct {
	used:     bool,
	name:     string, // heap
	volume:   f32,    // linear (fader); 1 = 0 dB
	pan:      f32,    // -1 left .. 1 right
	mute:     bool,
	solo:     bool,
	output:   int,    // bus index (-1: the device - Master only)
	effects:  [MIXER_MAX_EFFECTS]Mixer_Effect,
	effectCount: int,
	// Audio thread.
	buf:      []f32,  // 2 * MIXER_BLOCK (heap)
	gainL, gainR: f32, // last fader / pan gains (ramped)
	peak:     [2]f32, // post-fader peaks for the meters (decaying)
	clip:     f32,    // > 0 for a while after the output went over 0 dB
}

Mixer_Voice_Kind :: enum u8 {Sound, Music}

Mixer_Voice :: struct {
	active:  bool,
	gen:     u32,     // handle generation (stale handles do nothing)
	kind:    Mixer_Voice_Kind,
	bus:     int,
	volume:  f32,
	pan:     f32,     // -1 .. 1
	pitch:   f32,
	loop:    bool,
	paused:  bool,
	ended:   bool,    // reached the end (audio thread); the game thread reaps it
	owner:   rawptr,  // what started it (a sound resource / music): stop with it
	// Sound: the samples (48 kHz stereo, owned by the sound resource).
	pcm:     []f32,
	pos:     f64,     // frame position (fractional)
	// Music: raylib's decoder and a FIFO of decoded stereo frames.
	music:   rl.Music,
	srcRate: f32,
	srcCh:   int,
	fifo:    []f32,   // 2 * MIXER_STREAM_FIFO (heap)
	fifoAt:  int,     // first frame
	fifoN:   int,     // frames in it
	dec:     []f32,   // decode scratch (heap)
	dec16:   []i16,
	frac:    f64,     // position between fifo[0] and fifo[1]
	played:  f64,     // source frames played (time)
	srcEnded: bool,
	// Ramped gains.
	gainL, gainR: f32,
	started: bool,
}

// Mixer_Voice_Handle: a voice and its generation (0 = none).
Mixer_Voice_Handle :: struct {
	index: i32,
	gen:   u32,
}

@(private = "file")
mixer: struct {
	lock:     sync.Mutex,
	buses:    [MIXER_MAX_BUSES]Mixer_Bus,
	order:    [MIXER_MAX_BUSES]int, // processing order (children first)
	orderN:   int,
	voices:   [MIXER_MAX_VOICES]Mixer_Voice,
	stream:   rl.AudioStream,
	running:  bool,
	soloAny:  bool,
	scratch:  []f32,  // a voice's resampled block (heap)
	nextGen:  u32,
}

// --- setup -------------------------------------------------------------------------------

// Mixer_Init makes the buses' buffers and, with an audio device, starts the
// output stream. Master is bus 0; `Music` and `SFX` exist by default.
Mixer_Init :: proc() {
	a := Engine_HeapAllocator()
	if mixer.scratch == nil do mixer.scratch = make([]f32, 2 * MIXER_BLOCK, a)
	sync.mutex_lock(&mixer.lock)
	if !mixer.buses[0].used {
		mixer_add_bus_locked("Master", -1)
		mixer_add_bus_locked("Music", 0)
		mixer_add_bus_locked("SFX", 0)
		mixer_reorder_locked()
	}
	sync.mutex_unlock(&mixer.lock)
	if !mixer.running && rl.IsAudioDeviceReady() {
		rl.SetAudioStreamBufferSizeDefault(1024) // ~21 ms: responsive one-shots
		mixer.stream = rl.LoadAudioStream(MIXER_RATE, 32, 2)
		rl.SetAudioStreamCallback(mixer.stream, mixer_callback)
		rl.PlayAudioStream(mixer.stream)
		mixer.running = true
	}
}

// Mixer_Shutdown stops the stream and frees everything (game end).
Mixer_Shutdown :: proc() {
	if mixer.running {
		rl.StopAudioStream(mixer.stream)
		rl.UnloadAudioStream(mixer.stream)
		mixer.running = false
	}
	sync.mutex_lock(&mixer.lock)
	for i in 0 ..< MIXER_MAX_VOICES do mixer_free_voice_locked(i)
	for &b in mixer.buses do mixer_free_bus(&b)
	sync.mutex_unlock(&mixer.lock)
	if mixer.scratch != nil do delete(mixer.scratch, Engine_HeapAllocator())
	mixer = {}
}

@(private = "file")
mixer_free_bus :: proc(b: ^Mixer_Bus) {
	a := Engine_HeapAllocator()
	if b.name != "" do delete(b.name, a)
	if b.buf != nil do delete(b.buf, a)
	for &e in b.effects do Effect_Free(&e)
	b^ = {}
}

@(private = "file")
mixer_add_bus_locked :: proc(name: string, output: int) -> int {
	for &b, i in mixer.buses {
		if b.used do continue
		a := Engine_HeapAllocator()
		b = {used = true, name = strings.clone(name, a), volume = 1, output = output, gainL = 1, gainR = 1}
		b.buf = make([]f32, 2 * MIXER_BLOCK, a)
		return i
	}
	return -1
}

// mixer_reorder_locked: buses deepest first (a bus before its output).
@(private = "file")
mixer_reorder_locked :: proc() {
	depth :: proc(i: int) -> int {
		d := 0
		for j := i; j > 0 && d < MIXER_MAX_BUSES; d += 1 {
			o := mixer.buses[j].output
			if o < 0 || o >= MIXER_MAX_BUSES || !mixer.buses[o].used do break
			j = o
		}
		return d
	}
	mixer.orderN = 0
	for d := MIXER_MAX_BUSES; d >= 0; d -= 1 {
		for b, i in mixer.buses do if b.used && depth(i) == d {
			mixer.order[mixer.orderN] = i
			mixer.orderN += 1
		}
	}
	mixer.soloAny = false
	for b in mixer.buses do if b.used && b.solo do mixer.soloAny = true
}

// --- buses (game thread) ------------------------------------------------------------------

Mixer_BusIndex :: proc(name: string) -> int {
	for b, i in mixer.buses do if b.used && strings.equal_fold(b.name, name) do return i
	return -1
}

Mixer_BusCount :: proc() -> int {
	n := 0
	for b in mixer.buses do if b.used do n += 1
	return n
}

// Mixer_Bus_Info: a copy of a bus's settings (UI, saving).
Mixer_Bus_Info :: struct {
	index:   int,
	name:    string, // (the mixer's; valid until the bus is renamed / removed)
	volume:  f32,
	pan:     f32,
	mute:    bool,
	solo:    bool,
	output:  int,
	effects: []Mixer_Effect, // (a view; read only)
	peak:    [2]f32,
	clip:    bool,
}

// Mixer_Buses: the buses in index order (Master first).
Mixer_Buses :: proc(allocator := context.temp_allocator) -> []Mixer_Bus_Info {
	out := make([dynamic]Mixer_Bus_Info, allocator)
	for &b, i in mixer.buses do if b.used {
		append(&out, Mixer_Bus_Info{i, b.name, b.volume, b.pan, b.mute, b.solo, b.output, b.effects[:b.effectCount], b.peak, b.clip > 0})
	}
	return out[:]
}

// Mixer_AddBus: a new bus into Master (or `output`); its index (-1: full / taken).
Mixer_AddBus :: proc(name: string, output := 0) -> int {
	if name == "" || Mixer_BusIndex(name) >= 0 do return -1
	sync.mutex_lock(&mixer.lock)
	defer sync.mutex_unlock(&mixer.lock)
	i := mixer_add_bus_locked(name, output)
	mixer_reorder_locked()
	return i
}

// Mixer_RemoveBus: its voices and the buses feeding it go to Master.
Mixer_RemoveBus :: proc(index: int) {
	if index <= 0 || index >= MIXER_MAX_BUSES || !mixer.buses[index].used do return
	sync.mutex_lock(&mixer.lock)
	defer sync.mutex_unlock(&mixer.lock)
	for &v in mixer.voices do if v.active && v.bus == index do v.bus = 0
	for &b in mixer.buses do if b.used && b.output == index do b.output = 0
	mixer_free_bus(&mixer.buses[index])
	mixer_reorder_locked()
}

Mixer_RenameBus :: proc(index: int, name: string) -> bool {
	if index <= 0 || index >= MIXER_MAX_BUSES || !mixer.buses[index].used || name == "" do return false
	if j := Mixer_BusIndex(name); j >= 0 && j != index do return false
	a := Engine_HeapAllocator()
	delete(mixer.buses[index].name, a)
	mixer.buses[index].name = strings.clone(name, a)
	return true
}

// Mixer_SetBus sets a bus's fader (linear), pan, mute and solo.
Mixer_SetBusVolume :: proc(index: int, v: f32) {if mixer_bus_ok(index) do mixer.buses[index].volume = max(v, 0)}
Mixer_SetBusPan :: proc(index: int, p: f32) {if mixer_bus_ok(index) do mixer.buses[index].pan = clamp(p, -1, 1)}
Mixer_SetBusMute :: proc(index: int, m: bool) {if mixer_bus_ok(index) do mixer.buses[index].mute = m}
Mixer_SetBusSolo :: proc(index: int, s: bool) {
	if !mixer_bus_ok(index) do return
	sync.mutex_lock(&mixer.lock)
	mixer.buses[index].solo = s
	mixer_reorder_locked()
	sync.mutex_unlock(&mixer.lock)
}

// Mixer_SetBusOutput routes a bus (not into itself or its own inputs).
Mixer_SetBusOutput :: proc(index, output: int) -> bool {
	if index <= 0 || !mixer_bus_ok(index) || !mixer_bus_ok(output) || output == index do return false
	for j, d := output, 0; j > 0 && d < MIXER_MAX_BUSES; d += 1 {
		if j == index do return false // a loop
		j = mixer.buses[j].output
	}
	sync.mutex_lock(&mixer.lock)
	mixer.buses[index].output = output
	mixer_reorder_locked()
	sync.mutex_unlock(&mixer.lock)
	return true
}

@(private = "file")
mixer_bus_ok :: proc(index: int) -> bool {return index >= 0 && index < MIXER_MAX_BUSES && mixer.buses[index].used}

// Mixer_AddEffect appends an effect to a bus (its slot, -1 when full).
Mixer_AddEffect :: proc(bus: int, t: Mixer_Effect_Type) -> int {
	if !mixer_bus_ok(bus) || t == .None do return -1
	b := &mixer.buses[bus]
	if b.effectCount >= MIXER_MAX_EFFECTS do return -1
	e: Mixer_Effect
	Effect_Init(&e, t, MIXER_RATE) // (buffers made here, not on the audio thread)
	sync.mutex_lock(&mixer.lock)
	b.effects[b.effectCount] = e
	b.effectCount += 1
	sync.mutex_unlock(&mixer.lock)
	return b.effectCount - 1
}

Mixer_RemoveEffect :: proc(bus, slot: int) {
	if !mixer_bus_ok(bus) do return
	b := &mixer.buses[bus]
	if slot < 0 || slot >= b.effectCount do return
	sync.mutex_lock(&mixer.lock)
	old := b.effects[slot]
	for k in slot ..< b.effectCount - 1 do b.effects[k] = b.effects[k + 1]
	b.effectCount -= 1
	b.effects[b.effectCount] = {}
	sync.mutex_unlock(&mixer.lock)
	Effect_Free(&old)
}

// Mixer_MoveEffect moves an effect up / down the chain.
Mixer_MoveEffect :: proc(bus, slot, to: int) {
	if !mixer_bus_ok(bus) do return
	b := &mixer.buses[bus]
	if slot < 0 || slot >= b.effectCount || to < 0 || to >= b.effectCount || slot == to do return
	sync.mutex_lock(&mixer.lock)
	e := b.effects[slot]
	if slot < to do for k in slot ..< to do b.effects[k] = b.effects[k + 1]
	else do for k := slot; k > to; k -= 1 do b.effects[k] = b.effects[k - 1]
	b.effects[to] = e
	sync.mutex_unlock(&mixer.lock)
}

// Mixer_Effect_Ref: an effect's parameters (written directly: the audio
// thread picks changes up on its next block) - nil when out of range.
Mixer_EffectRef :: proc(bus, slot: int) -> ^Mixer_Effect {
	if !mixer_bus_ok(bus) || slot < 0 || slot >= mixer.buses[bus].effectCount do return nil
	return &mixer.buses[bus].effects[slot]
}

// Mixer_SetEffectEnabled: bypass (false) / enable an effect; a re-enabled
// one starts without its old tail.
Mixer_SetEffectEnabled :: proc(bus, slot: int, on: bool) {
	e := Mixer_EffectRef(bus, slot)
	if e == nil || e.enabled == on do return
	sync.mutex_lock(&mixer.lock)
	if on do Effect_Clear(e)
	e.enabled = on
	sync.mutex_unlock(&mixer.lock)
}

// Mixer_EffectParamIndex: a parameter's slot by name (-1).
Mixer_EffectParamIndex :: proc(t: Mixer_Effect_Type, name: string) -> int {
	for d, i in MIXER_EFFECT_PARAMS[t] do if d.name == name do return i
	return -1
}

// Mixer_ResetBuses: back to Master / Music / SFX (a project load).
Mixer_ResetBuses :: proc() {
	sync.mutex_lock(&mixer.lock)
	for &v in mixer.voices do if v.active do v.bus = 0
	for &b in mixer.buses do mixer_free_bus(&b)
	mixer_add_bus_locked("Master", -1)
	mixer_add_bus_locked("Music", 0)
	mixer_add_bus_locked("SFX", 0)
	mixer_reorder_locked()
	sync.mutex_unlock(&mixer.lock)
}

// --- voices (game thread) -------------------------------------------------------------

@(private = "file")
mixer_free_voice_locked :: proc(i: int) {
	v := &mixer.voices[i]
	a := Engine_HeapAllocator()
	if v.kind == .Music && v.fifo != nil {
		delete(v.fifo, a)
		delete(v.dec, a)
		delete(v.dec16, a)
	}
	gen := v.gen
	v^ = {gen = gen}
}

@(private = "file")
mixer_alloc_voice_locked :: proc() -> int {
	for v, i in mixer.voices do if !v.active do return i
	for v, i in mixer.voices do if v.ended {
		mixer_free_voice_locked(i)
		return i
	}
	// All busy: steal the quietest sound voice.
	best, quiet := -1, max(f32)
	for v, i in mixer.voices do if v.kind == .Sound && v.volume < quiet {best, quiet = i, v.volume}
	if best >= 0 do mixer_free_voice_locked(best)
	return best
}

// Mixer_PlaySound plays decoded samples (48 kHz stereo frames, which must
// outlive the voice - stop it before freeing them: Mixer_StopOwner).
Mixer_PlaySound :: proc(pcm: []f32, bus: int, volume: f32 = 1, pan: f32 = 0, pitch: f32 = 1, loop := false, owner: rawptr = nil) -> Mixer_Voice_Handle {
	if len(pcm) < 2 do return {}
	sync.mutex_lock(&mixer.lock)
	defer sync.mutex_unlock(&mixer.lock)
	i := mixer_alloc_voice_locked()
	if i < 0 do return {}
	mixer.nextGen += 1
	mixer.voices[i] = {active = true, gen = mixer.nextGen, kind = .Sound, bus = bus if mixer_bus_ok(bus) else 0, volume = volume, pan = pan, pitch = max(pitch, 0.01), loop = loop, owner = owner, pcm = pcm}
	return {i32(i), mixer.nextGen}
}

// Mixer_PlayMusic streams a loaded raylib Music (never played by raylib;
// its decoder is read here). The Music must outlive the voice.
Mixer_PlayMusic :: proc(m: rl.Music, bus: int, volume: f32 = 1, loop := true, owner: rawptr = nil, startSeconds: f32 = 0) -> Mixer_Voice_Handle {
	if m.ctxData == nil do return {}
	a := Engine_HeapAllocator()
	ch := int(max(m.stream.channels, 1))
	v := Mixer_Voice{kind = .Music, bus = bus if mixer_bus_ok(bus) else 0, volume = volume, pitch = 1, loop = loop, owner = owner, music = m, srcRate = f32(m.stream.sampleRate), srcCh = ch}
	v.fifo = make([]f32, 2 * MIXER_STREAM_FIFO, a)
	v.dec = make([]f32, 1024 * max(ch, 2), a)
	v.dec16 = make([]i16, 1024 * 2, a)
	mm := m
	if startSeconds > 0 {
		music_seek(&mm, u64(startSeconds * v.srcRate))
		v.played = f64(startSeconds * v.srcRate)
	} else {
		music_rewind(&mm)
	}
	sync.mutex_lock(&mixer.lock)
	defer sync.mutex_unlock(&mixer.lock)
	i := mixer_alloc_voice_locked()
	if i < 0 {
		delete(v.fifo, a)
		delete(v.dec, a)
		delete(v.dec16, a)
		return {}
	}
	mixer.nextGen += 1
	v.active, v.gen = true, mixer.nextGen
	mixer.voices[i] = v
	return {i32(i), mixer.nextGen}
}

@(private = "file")
mixer_voice :: proc(h: Mixer_Voice_Handle) -> ^Mixer_Voice {
	if h.gen == 0 || h.index < 0 || int(h.index) >= MIXER_MAX_VOICES do return nil
	v := &mixer.voices[h.index]
	return v if v.active && v.gen == h.gen else nil
}

Mixer_VoicePlaying :: proc(h: Mixer_Voice_Handle) -> bool {
	v := mixer_voice(h)
	return v != nil && !v.ended
}

// Mixer_SetVoice updates a voice's volume / pan / pitch (ramped).
Mixer_SetVoice :: proc(h: Mixer_Voice_Handle, volume, pan, pitch: f32) {
	if v := mixer_voice(h); v != nil {
		v.volume, v.pan, v.pitch = volume, clamp(pan, -1, 1), max(pitch, 0.01)
	}
}

Mixer_SetVoiceBus :: proc(h: Mixer_Voice_Handle, bus: int) {if v := mixer_voice(h); v != nil && mixer_bus_ok(bus) do v.bus = bus}
Mixer_SetVoicePaused :: proc(h: Mixer_Voice_Handle, paused: bool) {if v := mixer_voice(h); v != nil do v.paused = paused}

// Mixer_Suspend stops (or restarts) all sound: the app is in the background
// (Android: the Home button, a call) - the voices carry on from where they were.
Mixer_Suspend :: proc(on: bool) {
	if !mixer.running do return
	if on do rl.PauseAudioStream(mixer.stream)
	else do rl.ResumeAudioStream(mixer.stream)
}
Mixer_SetVoiceLoop :: proc(h: Mixer_Voice_Handle, loop: bool) {if v := mixer_voice(h); v != nil do v.loop = loop}

// Mixer_VoiceTime: seconds into the sound / music.
Mixer_VoiceTime :: proc(h: Mixer_Voice_Handle) -> f32 {
	v := mixer_voice(h)
	if v == nil do return 0
	if v.kind == .Sound do return f32(v.pos / MIXER_RATE)
	return f32(v.played / f64(max(v.srcRate, 1)))
}

Mixer_StopVoice :: proc(h: Mixer_Voice_Handle) {
	sync.mutex_lock(&mixer.lock)
	defer sync.mutex_unlock(&mixer.lock)
	if v := mixer_voice(h); v != nil do mixer_free_voice_locked(int(h.index))
}

// Mixer_StopOwner stops every voice an owner started (before freeing its
// samples / music).
Mixer_StopOwner :: proc(owner: rawptr) {
	if owner == nil do return
	sync.mutex_lock(&mixer.lock)
	defer sync.mutex_unlock(&mixer.lock)
	for v, i in mixer.voices do if v.active && v.owner == owner do mixer_free_voice_locked(i)
}

Mixer_OwnerPlaying :: proc(owner: rawptr) -> bool {
	for v in mixer.voices do if v.active && v.owner == owner && !v.ended do return true
	return false
}

// Mixer_Reap frees voices that ended (once a frame, game thread).
Mixer_Reap :: proc() {
	sync.mutex_lock(&mixer.lock)
	defer sync.mutex_unlock(&mixer.lock)
	for v, i in mixer.voices do if v.active && v.ended do mixer_free_voice_locked(i)
}

Mixer_ActiveVoices :: proc() -> int {
	n := 0
	for v in mixer.voices do if v.active && !v.ended do n += 1
	return n
}

// --- rendering (audio thread) --------------------------------------------------------

@(private = "file")
mixer_callback :: proc "c" (buffer: rawptr, frames: u32) {
	context = Engine_DefaultContext()
	out := ([^]f32)(buffer)[:frames * 2]
	Mixer_Render(out)
}

// Mixer_Render renders interleaved stereo frames (the callback; tests call
// it directly without a device).
Mixer_Render :: proc(out: []f32) {
	total := len(out) / 2
	done := 0
	sync.mutex_lock(&mixer.lock)
	defer sync.mutex_unlock(&mixer.lock)
	for done < total {
		n := min(total - done, MIXER_BLOCK)
		mixer_render_block(out[done * 2:(done + n) * 2], n)
		done += n
	}
}

@(private = "file")
mixer_render_block :: proc(out: []f32, frames: int) {
	for &b in mixer.buses do if b.used do for i in 0 ..< frames * 2 do b.buf[i] = 0
	if !mixer.buses[0].used {
		for i in 0 ..< frames * 2 do out[i] = 0
		return
	}
	// 1. Voices into their buses.
	for &v in mixer.voices {
		if !v.active || v.ended || v.paused do continue
		bus := v.bus if mixer.buses[v.bus].used else 0
		mixer_voice_render(&v, mixer.buses[bus].buf[:frames * 2], frames)
	}
	// 2. Buses, children first, into their outputs.
	for k in 0 ..< mixer.orderN {
		i := mixer.order[k]
		b := &mixer.buses[i]
		s := b.buf[:frames * 2]
		for &e in b.effects[:b.effectCount] do Effect_Process(&e, s, MIXER_RATE)
		audible := !b.mute && (!mixer.soloAny || i == 0 || mixer_solo_path(i))
		vol := b.volume if audible else 0
		tl := vol * min(1, 1 - b.pan)
		tr := vol * min(1, 1 + b.pan)
		pk: [2]f32
		inv := 1 / f32(frames)
		for f in 0 ..< frames {
			t := f32(f) * inv
			gl := b.gainL + (tl - b.gainL) * t
			gr := b.gainR + (tr - b.gainR) * t
			s[f * 2] *= gl
			s[f * 2 + 1] *= gr
			pk[0] = max(pk[0], abs(s[f * 2]))
			pk[1] = max(pk[1], abs(s[f * 2 + 1]))
		}
		b.gainL, b.gainR = tl, tr
		decay := math.pow(f32(0.5), f32(frames) / (0.15 * MIXER_RATE)) // halves in 150 ms
		for ch in 0 ..< 2 do b.peak[ch] = max(pk[ch], b.peak[ch] * decay)
		if pk[0] > 1 || pk[1] > 1 do b.clip = 1.5 // seconds
		else do b.clip = max(b.clip - f32(frames) / MIXER_RATE, 0)
		if i == 0 do continue
		o := b.output if b.output >= 0 && mixer.buses[b.output].used else 0
		dst := mixer.buses[o].buf
		for j in 0 ..< frames * 2 do dst[j] += s[j]
	}
	// 3. Master to the device (a gentle clip past 0 dB).
	m := mixer.buses[0].buf
	for j in 0 ..< frames * 2 {
		x := m[j]
		out[j] = x if abs(x) <= 0.95 else math.copy_sign(0.95 + 0.05 * math.tanh((abs(x) - 0.95) / 0.05), x)
	}
}

// mixer_solo_path: with a solo somewhere, a bus plays if it is soloed, feeds
// a soloed bus, or is fed by one.
@(private = "file")
mixer_solo_path :: proc(i: int) -> bool {
	// Up: it or an output of it is soloed.
	for j, d := i, 0; j >= 0 && d < MIXER_MAX_BUSES; d += 1 {
		if mixer.buses[j].solo do return true
		if j == 0 do break
		j = mixer.buses[j].output
	}
	// Down: a soloed bus outputs (eventually) into it.
	for b, k in mixer.buses do if b.used && b.solo {
		for j, d := k, 0; j > 0 && d < MIXER_MAX_BUSES; d += 1 {
			j = mixer.buses[j].output
			if j == i do return true
		}
	}
	return false
}

// mixer_voice_render adds a voice's next `frames` (resampled, ramped gains)
// into a bus buffer.
@(private = "file")
mixer_voice_render :: proc(v: ^Mixer_Voice, dst: []f32, frames: int) {
	tl := v.volume * min(1, 1 - v.pan)
	tr := v.volume * min(1, 1 + v.pan)
	if !v.started {
		v.gainL, v.gainR, v.started = tl, tr, true
	}
	inv := 1 / f32(frames)
	switch v.kind {
	case .Sound:
		n := len(v.pcm) / 2
		step := f64(v.pitch)
		for f in 0 ..< frames {
			i := int(v.pos)
			if i >= n {
				if v.loop && n > 0 {
					v.pos -= f64(n)
					i = int(v.pos)
				} else {
					v.ended = true
					break
				}
			}
			t := f32(v.pos - f64(i))
			j := i + 1 if i + 1 < n else (0 if v.loop else i)
			l := v.pcm[i * 2] + (v.pcm[j * 2] - v.pcm[i * 2]) * t
			r := v.pcm[i * 2 + 1] + (v.pcm[j * 2 + 1] - v.pcm[i * 2 + 1]) * t
			k := f32(f) * inv
			dst[f * 2] += l * (v.gainL + (tl - v.gainL) * k)
			dst[f * 2 + 1] += r * (v.gainR + (tr - v.gainR) * k)
			v.pos += step
		}
	case .Music:
		step := f64(v.srcRate) / MIXER_RATE * f64(v.pitch)
		for f in 0 ..< frames {
			if v.fifoN < 2 && !v.srcEnded do mixer_stream_fill(v)
			if v.fifoN < 2 {
				v.ended = v.srcEnded
				break
			}
			a := v.fifoAt
			b := (v.fifoAt + 1) % MIXER_STREAM_FIFO
			t := f32(v.frac)
			l := v.fifo[a * 2] + (v.fifo[b * 2] - v.fifo[a * 2]) * t
			r := v.fifo[a * 2 + 1] + (v.fifo[b * 2 + 1] - v.fifo[a * 2 + 1]) * t
			k := f32(f) * inv
			dst[f * 2] += l * (v.gainL + (tl - v.gainL) * k)
			dst[f * 2 + 1] += r * (v.gainR + (tr - v.gainR) * k)
			v.frac += step
			for v.frac >= 1 && v.fifoN > 1 {
				v.frac -= 1
				v.fifoAt = (v.fifoAt + 1) % MIXER_STREAM_FIFO
				v.fifoN -= 1
				v.played += 1
			}
		}
	}
	v.gainL, v.gainR = tl, tr
}

// mixer_stream_fill decodes more frames into a music voice's FIFO (as
// stereo); at the end it loops (rewinds) or marks the source ended.
@(private = "file")
mixer_stream_fill :: proc(v: ^Mixer_Voice) {
	space := MIXER_STREAM_FIFO - v.fifoN
	if space < 1024 do return
	ch := v.srcCh
	want := min(1024, space)
	got := music_decode(&v.music, v.dec, want, ch, v.dec16)
	if got <= 0 {
		if v.loop {
			music_rewind(&v.music)
			v.played = 0
			got = music_decode(&v.music, v.dec, want, ch, v.dec16)
		}
		if got <= 0 {
			v.srcEnded = true
			return
		}
	}
	for f in 0 ..< got {
		at := (v.fifoAt + v.fifoN) % MIXER_STREAM_FIFO
		l := v.dec[f * ch]
		r := v.dec[f * ch + 1] if ch > 1 else l
		v.fifo[at * 2] = l
		v.fifo[at * 2 + 1] = r
		v.fifoN += 1
	}
}

// --- meters -----------------------------------------------------------------------------

// Mixer_EffectReduction: a compressor / limiter's gain reduction now (dB).
Mixer_EffectReduction :: proc(bus, slot: int) -> f32 {
	e := Mixer_EffectRef(bus, slot)
	return e.gr if e != nil else 0
}
