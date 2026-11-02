## Use it for

- **Quick one-shots**: `Audio.play_sound` plays a file with no node - a UI
  click, a pickup. `Audio.play_sound_at` plays it from a world position, so
  it's quieter far from the listener and panned to its side.
- **Music by path**: `Audio.play_music`, `stop_music`, `pause_music` and
  `resume_music` stream a track without a node. For tracks placed in a
  scene, use a [Music Streamer](../nodes/MusicNode.md) and
  `Audio.crossfade` between two of them.
- **Volume options**: `Audio.set_bus_volume` and `get_bus_volume` move a
  bus fader - a Music or Effects slider in an options menu is just one call.
- **Moods and places**: `Audio.set_lowpass` and `Audio.set_reverb` put a
  filter or reverb on the whole mix (underwater, a pause menu, a cave);
  `Audio.set_effect` and `set_effect_enabled` change one effect on one bus.
- **Mixing from a script**: `set_bus_mute`, `set_bus_solo` and
  `set_bus_pan` act like the Mixer tab's buttons; `get_buses` lists the
  buses and `get_bus_peak` reads a bus's level for meters or music-reactive
  effects.

## Example

An options menu that sets the Music and Effects faders and keeps them for
the next run. The script is on a UI Container with two
[UI Slider](../nodes/UISliderNode.md) children named `MusicSlider` and
`SfxSlider` (range 0 to 1).

```lua
---@class AudioOptions : ScriptInstanceBase
local AudioOptions = {}

function AudioOptions:ready()
    local music = self.node:get_node("MusicSlider") ---@type UISliderNode
    local sfx = self.node:get_node("SfxSlider") ---@type UISliderNode

    -- The player's last choice, else the project's current fader.
    music.value = Save.get("music_volume", Audio.get_bus_volume("music"))
    sfx.value = Save.get("sfx_volume", Audio.get_bus_volume("sfx"))
    Audio.set_bus_volume("music", music.value)
    Audio.set_bus_volume("sfx", sfx.value)

    music:connect("value_changed", function(v)
        Audio.set_bus_volume("music", v)
        Save.set("music_volume", v)
    end)
    sfx:connect("value_changed", function(v)
        Audio.set_bus_volume("sfx", v)
        Save.set("sfx_volume", v)
        Audio.play_sound("audio/click.wav") -- hear the new level
    end)
end

function AudioOptions:on_destroy()
    Save.flush()
end

return AudioOptions
```

## Notes

- Paths are project-relative (`"audio/jump.wav"`). A file is loaded the
  first time it's played and kept after that.
- Without a `bus`, a sound plays into its import bus (set in the asset's
  import settings), else **SFX**; music into its import bus, else
  **Music**. Bus names don't care about case; an unknown name plays into
  Master.
- Faders are linear: 1 is 0 dB, 0.5 about -6 dB. The names `"master"`,
  `"music"` and `"sfx"` (any case) also set the project's volumes and are
  clamped to 0..1.
- `play_sound_at` is full volume within 100 px of the listener and silent
  beyond 900 px. The listener is the current camera, or the node given to
  `Audio.set_listener`.
- The [audio mixer guide](../../engine/docs/audio_mixer.md) explains buses
  and every effect parameter. A [Sound Effect](../nodes/SoundNode.md) node
  adds variation, voices and captions to one-shots.
