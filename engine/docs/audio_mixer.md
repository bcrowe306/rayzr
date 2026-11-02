# The audio mixer

Every sound and music track in the game plays into a **bus**. A bus is a
channel on a mixing console: it has a **fader** (volume), **pan**,
**mute** and **solo**, a chain of **effects**, and an **output** - the
Master bus, or another bus. Master goes to the speakers.

```
 SoundNode "Laser" ─┐
 SoundNode "Boom"  ─┼─▶ [ Weapons ] ─┐
                     │   reverb       ├─▶ [ SFX ] ─┐
 Audio.play_sound()  ┴───────────────┘   EQ       ├─▶ [ Master ] ─▶ speakers
 MusicNode "Theme"  ────▶ [ Music ] ─────────────┘    limiter
```

Grouping sounds on buses means one fader for all weapons, one reverb for
all footsteps in a cave, a "duck the music" setting, and players' volume
options (Music / Effects sliders) that are just bus faders.

Every project starts with **Master**, **Music** and **SFX**. Sound nodes
play into SFX and music nodes into Music unless you pick another bus.

## The Mixer tab

Bottom panel > **Mixer**. One strip per bus, left to right; **Master** is
pinned at the far right.

| Strip | |
|---|---|
| Name | Double-click (or right-click > Rename) to rename; right-click > Delete Bus. |
| Effects | The chain, top to bottom. Click an effect to edit its parameters (a popup with sliders; Defaults resets them); the dot bypasses it; right-click moves it up / down or removes it. **+ Effect** adds one. A compressor or limiter shows how much it is reducing (e.g. `Compressor -4`). |
| → Output | Where the bus goes: Master or another bus (a *group*). A choice that would loop is refused. |
| Pan | Left / right. Double-click: centre. |
| Fader | Volume. 0 dB (unchanged) at about 70 % of the travel, up to +6 dB. Double-click: 0 dB. |
| Meter | The bus's level after its fader (left / right): green, yellow from -12 dB, red over 0 dB; a red bar on top when it clipped recently. |
| M / S | Mute; solo (only soloed buses - and the buses they feed - are heard). |
| dB field | The fader's level - type a value (`-6`, `-inf`) and press Enter. |

**+ Bus** adds a bus into Master.

Changes apply immediately and are saved in `project.json`. In **Simulate**
you hear them through the editor's mixer. While the game runs (**Play**)
the tab drives the running game's mixer live and its meters show the
game's levels - mix while you play.

A Sound or Music node's **Bus** (Inspector) picks the bus it plays into.

## Effects

| Effect | Parameters | Use |
|---|---|---|
| **EQ** | low / mid / high gain (dB) and frequency | Shape the tone: cut boom from ambience, add presence to voices. |
| **Low-pass** | cutoff (Hz), resonance | Muffle: underwater, behind a wall, pause menus. |
| **High-pass** | cutoff (Hz), resonance | Thin out: radio, phone, remove rumble. |
| **Compressor** | threshold, ratio, attack, release, makeup | Even out loud and quiet sounds (dialogue, many overlapping effects). |
| **Limiter** | ceiling (dB), release | Stop the master going over 0 dB (put it last on Master). |
| **Delay** | time (ms), feedback, mix | Echoes: canyons, sci-fi weapons. |
| **Reverb** | room size, damping, mix | Space: caves, halls, churches. |
| **Distortion** | drive, mix, output | Grit: damaged robots, radio, power-ups. |

Up to 8 effects per bus; they run in order.

## Tutorial: buses for a typical game

1. **Mixer** tab: **+ Bus** twice; rename them **Voice** and **Ambience**.
   Leave both going to Master.
2. On **Master**: **+ Effect > Limiter** (ceiling -1 dB) - nothing ever
   clips, whatever happens on screen.
3. On **Voice**: **+ Effect > Compressor** (threshold -18, ratio 4) - quiet
   and loud lines sound equally present; **+ Effect > EQ** with High -3 dB
   if voices sound harsh.
4. On **Ambience**: fader down to -8 dB so it sits under everything.
5. Select your NPC's Sound nodes (Shift+click several) and set **Bus** to
   **Voice**; the wind and birds to **Ambience**.
6. Play and watch the meters; move faders while the game runs.

### An options menu

Players' Music and Effects sliders are the bus faders:

```lua
function Options:ready()
    self.music_slider.value = Audio.get_bus_volume("Music") * 100
    self.music_slider:connect("value_changed", function(v)
        Audio.set_bus_volume("Music", v / 100)
    end)
end
```

(`Save.set` them to keep the player's choice between runs.)

### Underwater

```lua
function Player:on_enter_water()
    Audio.set_effect_enabled("SFX", "lowpass", true)
    Audio.set_effect("SFX", "lowpass", "cutoff", 700)
    Audio.set_effect_enabled("Music", "lowpass", true)
end

function Player:on_exit_water()
    Audio.set_effect_enabled("SFX", "lowpass", false)
    Audio.set_effect_enabled("Music", "lowpass", false)
end
```

(Add a bypassed Low-pass to SFX and Music in the Mixer tab first.)

### Music-reactive visuals

```lua
function Speaker:update(dt)
    local l, r = Audio.get_bus_peak("Music")
    local s = 1 + math.max(l, r) * 0.3
    self.node.scale = {s, s}
end
```

## Sound variation (Sound Effect)

A **Sound Effect** holds a list of sounds (Inspector > Audio: **Add Sound**,
or drop audio from Assets; drag a row's number to reorder; each row has its
own play button). Its **Play Mode** picks what a play starts:

| Mode | Plays |
|---|---|
| Single | the chosen sound (`single`, 1 = the first) |
| All | every sound at once (layered: a body, a tail, a crunch) |
| Sequential | the next one each time, then the first again |
| Sequential Reversed | the same, from the last one |
| Random | one by **weight** (a row's `w`; 0 = never), never the one just played |
| Shuffle | each once in a random order, then a new order |

Each play varies (All: each sound on its own): **Volume Random** (+/- volume),
**Pitch Random** (+/- semitones - 1 or 2 keep footsteps from sounding
copied), **Pan Random** (+/-), **Delay Random** (a random 0..N s wait) -
and **Cooldown** skips plays within N seconds of the last (rapid fire
doesn't stack voices). The Inspector's **Preview** plays one play like
that (Sequential and Shuffle step on each press without moving the
node's own place; the Cooldown is for repeated plays, so it doesn't apply).
Scripts: `node:sound_play()` follows the mode, `node:sound_play_index(i)`
plays one, `node:sound_get_count()`, `node:sound_get_last()`.

## Scripting

| Function | |
|---|---|
| `Audio.play_sound(path [, volume [, pitch [, bus]]])` | A one-shot (default bus SFX). |
| `Audio.play_sound_at(path, x, y [, volume])` | A one-shot heard from a position. |
| `Audio.play_music(path [, loop [, bus]])` / `stop_music` / `pause_music` / `resume_music` / `is_music_playing` / `set_music_volume` | Music by path (default bus Music). |
| `Audio.set_bus_volume(bus, v)` / `get_bus_volume(bus)` | A fader (linear: 1 = 0 dB, 0.5 ≈ -6 dB). |
| `Audio.set_bus_mute(bus, on)` / `set_bus_solo(bus, on)` / `set_bus_pan(bus, p)` | |
| `Audio.get_buses()` | The bus names, Master first. |
| `Audio.get_bus_peak(bus)` | Left, right levels now. |
| `Audio.set_effect(bus, effect, param, value)` | An effect parameter (effect by type name or 1-based position). |
| `Audio.set_effect_enabled(bus, effect, on)` | Bypass / enable. |
| `Audio.set_lowpass(hz)` / `Audio.set_reverb(mix, size)` | Shortcuts: a low-pass / reverb on Master. |

Sound and Music nodes have a **bus** property (`node.bus = "Voice"`).

## Saved as

```json
"audio": {"master_volume": 1, "music_volume": 1, "sfx_volume": 1, "buses": [
    {"name": "Master", "volume": 1, "pan": 0, "effects": [{"type": "limiter", "enabled": true, "ceiling": -1, "release": 80}]},
    {"name": "Music", "output": "Master", "volume": 0.8, "pan": 0},
    {"name": "SFX", "output": "Master", "volume": 1, "pan": 0},
    {"name": "Voice", "output": "Master", "volume": 1, "pan": 0, "effects": [{"type": "compressor", "enabled": true, "threshold": -18, "ratio": 4, "attack": 10, "release": 150, "makeup": 3}]}
]}
```

Projects without `"buses"` get Master / Music / SFX at the project's
master / music / sound-effects volumes.

## How it works (performance and threads)

- The mixer runs on raylib's audio thread behind one output stream (48 kHz,
  ~21 ms blocks). Each block: every playing voice is resampled (pitch) and
  added into its bus; buses are processed children first (effects, fader,
  pan, meters) and added into their outputs; Master is clipped gently and
  sent to the speakers.
- **Sounds** are decoded once when loaded to 48 kHz stereo floats - playing
  one is a few multiply-adds per sample. **Music** streams: frames are
  pulled from raylib's decoder for the file (OGG, MP3, WAV, QOA, XM, MOD) as
  needed, a block at a time, so a long track costs a few kilobytes.
- The audio thread never allocates: effects' buffers (delay lines,
  reverb) are made when the effect is added. Game-thread calls take a lock
  for a moment; the audio thread holds it while it renders one block.
- Volume, pan and fader changes ramp over a block, so moving a fader never
  clicks.
- A sound being freed first stops the voices playing it (they read its
  samples).

## Notes

- Up to 32 buses, 128 voices (the quietest sound is replaced when all are
  busy), 8 effects per bus.
- `AudioSound.sound` (a raylib Sound) still exists for Odin code that plays
  it directly; such plays bypass the mixer.
