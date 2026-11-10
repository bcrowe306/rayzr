package engine

import "base:runtime"
import "core:path/filepath"
import "core:fmt"
import "core:log"
import os "osx"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

MAX_TEXTURES :: 1000
MAX_AUDIOSOUNDS :: 1000
MAX_AUDIOMUSIC :: 1000


Texture :: struct {
	filePath: string,
	fileName: string,
	texture: rl.Texture2D,
	refCount: int,
	modTime: time.Time, // of the file when loaded (hot reload)
	// Atlased (exported games, atlas.odin): `texture` is the page and this
	// its rectangle - use Texture_Size / Texture_Src. Zero = the whole texture.
	region: rl.Rectangle,
	page: int, // atlas page + 1 (0 = its own texture)
}

AudioSound :: struct {
	filePath: string,
	fileName: string,
	pcm:      []f32, // 48 kHz stereo frames for the mixer (heap; decoded once)
	sound:    rl.Sound, // the same as a raylib Sound, for code that plays it directly (bypasses the mixer)
	refCount: int,
}

AudioMusic :: struct {
	filePath: string,
	fileName: string,
	music: rl.Music,
	refCount: int,
	streamData: []byte, // in-memory stream source (assets from a .rayzr package)
	voice: Mixer_Voice_Handle, // Audio.play_music's voice (path-based music)
	gain: f32, // import gain (asset_import.odin) as a factor
}

ResourceManager :: struct {
	textures: [dynamic]^Texture,
	audioSounds: [MAX_AUDIOSOUNDS]AudioSound,
	audioMusic: [MAX_AUDIOMUSIC]AudioMusic,
	textureCount: int,
	audioCount: int,
	musicCount: int,
	loadTexture: proc(resourceManager: ^ResourceManager, filePath: string) -> (texture: ^Texture, ok: bool),
	getTexture: proc(rm: ^ResourceManager, fileName: string) -> (texture: ^Texture, ok: bool),
	unloadTexture: proc(rm: ^ResourceManager, fileName: string),
	loadAudioSound: proc(rm: ^ResourceManager, filePath: string) -> (audioSound: ^AudioSound, ok: bool),
	getAudioSound: proc(rm: ^ResourceManager, fileName: string) -> (texture: ^AudioSound, ok: bool),
	unloadAudioSound: proc(rm: ^ResourceManager, fileName: string),
	loadAudioMusic: proc(rm: ^ResourceManager, filePath: string) -> (audioMusic: ^AudioMusic, ok: bool),
	getAudioMusic: proc(rm: ^ResourceManager, fileName: string) -> (audioMusic: ^AudioMusic, ok: bool),
	unloadAudioMusic: proc(rm: ^ResourceManager, fileName: string),

	// Exported games: resources missing on disk are read from the mounted
	// .rayzr package (paths relative to projectDir).
	package_: ^RayzrPackage,
	projectDir: string,
	atlas: Atlas_Index, // the package's sprite atlas (atlas.odin)
	aseprite: map[string]^Ase_Resource, // Aseprite files (aseprite_resource.odin)
	vectors:  map[string]^Vector_Resource, // SVG files (vector_asset.odin)
}

ResourceManager_Init :: proc(rm: ^ResourceManager) {
	rm.textures = make([dynamic]^Texture)
	rm.loadTexture = LoadTexture_FilePath
	rm.getTexture = GetTexture
	rm.unloadTexture = UnloadTexture
	rm.loadAudioSound = ResourceManager_LoadAudioSound
	rm.getAudioSound = GetAudioSound
	rm.unloadAudioSound = UnloadAudioSound
	rm.loadAudioMusic = ResourceManager_LoadAudioMusic
	rm.getAudioMusic = GetAudioMusic
	rm.unloadAudioMusic = UnloadAudioMusic
}

ResourceManager_Terminate :: proc(rm: ^ResourceManager) {
	if rm == nil do return
	for tex in rm.textures {
		if tex != nil {
			if tex.page == 0 && tex.texture.id > 0 && rl.IsWindowReady() {
				rl.UnloadTexture(tex.texture)
				tex.texture.id = 0
			}
			delete(tex.filePath)
			free(tex)
		}
	}
	delete(rm.textures)
	Ase_ReleaseAll(rm)
	Vector_ReleaseAll(rm)
	rm.textures = nil
	Atlas_Unmount(rm) // (its pages)

	for i in 0..<rm.audioCount {
		audio := &rm.audioSounds[i]
		Mixer_StopOwner(audio) // its voices first (they read the samples)
		delete(audio.pcm, Engine_HeapAllocator())
		if audio.sound.frameCount > 0 && rl.IsAudioDeviceReady() do rl.UnloadSound(audio.sound)
		delete(audio.filePath)
		audio^ = {}
	}
	rm.audioCount = 0

	for i in 0..<rm.musicCount {
		m := &rm.audioMusic[i]
		Mixer_StopOwner(m)
		if rl.IsAudioDeviceReady() && rl.IsMusicValid(m.music) {
			rl.UnloadMusicStream(m.music)
		}
		delete(m.filePath)
		delete(m.streamData)
		m^ = {}
	}
	rm.musicCount = 0
}

// resource_bytes reads a resource that isn't on disk from the mounted .rayzr
// package (exported games ship their assets inside it).
resource_bytes :: proc(rm: ^ResourceManager, filePath: string) -> ([]byte, bool) {
	if modPath, modded := Mods_ResourceDiskPath(rm.projectDir, filePath); modded {
		if data, err := os.read_entire_file(modPath, context.allocator); err == nil do return data, true
	}
	if rm.package_ == nil do return nil, false
	rel := filePath
	if dir := rm.projectDir; dir != "" && len(rel) > len(dir) && rel[:len(dir)] == dir && rel[len(dir)] == '/' {
		rel = rel[len(dir) + 1:]
	}
	return RayzrPackage_ReadFile(rm.package_, rel, context.allocator)
}

@(private = "file")
file_ext_cstring :: proc(path: string) -> cstring {
	return fmt.ctprintf("%s", filepath.ext(path))
}

LoadTexture_FilePath :: proc(rm: ^ResourceManager, filePath: string) -> (texture: ^Texture, ok: bool) {
	return texture_load(rm, filePath, false)
}

// ResourceManager_LoadTextureOwn: a texture of its own even when the image
// is in the sprite atlas (shaders sample whole textures).
ResourceManager_LoadTextureOwn :: proc(rm: ^ResourceManager, filePath: string) -> (texture: ^Texture, ok: bool) {
	return texture_load(rm, filePath, true)
}

@(private = "file")
texture_load :: proc(rm: ^ResourceManager, filePath: string, own: bool) -> (texture: ^Texture, ok: bool) {
	for tex in rm.textures {
		if tex != nil && tex.filePath == filePath && !(own && tex.page > 0) {
			tex.refCount += 1
			return tex, true
		}
	}
	// A mod's image (mods.odin): its own texture, never the atlas's.
	diskPath, modded := Mods_ResourceDiskPath(rm.projectDir, filePath)
	// In the package's atlas: the page and the image's rectangle in it.
	if e, inAtlas := Atlas_Lookup(rm, filePath); inAtlas && !own && !modded {
		tex := new(Texture)
		tex.filePath = strings.clone(filePath)
		tex.fileName = filepath.base(tex.filePath)
		tex.texture = Atlas_AcquirePage(rm, e.page)
		tex.region = e.rect
		tex.page = e.page + 1
		tex.refCount = 1
		append(&rm.textures, tex)
		return tex, true
	}

	texture2d: rl.Texture2D
	if strings.has_prefix(filePath, PROMPTS_PREFIX) {
		// A button prompt (input_glyphs.odin).
		img, ok := Prompt_Image(filePath)
		if !ok {
			log.errorf("No button prompt %s", filePath)
			return nil, false
		}
		if rl.IsWindowReady() do texture2d = rl.LoadTextureFromImage(img)
		rl.UnloadImage(img)
	} else if Ase_IsPath(filePath) {
		// An Aseprite file: its first frame (aseprite_resource.odin).
		img, ok := ase_texture_image(rm, filePath)
		if !ok do return nil, false
		if rl.IsWindowReady() do texture2d = rl.LoadTextureFromImage(img)
		rl.UnloadImage(img)
	} else if os.is_file(diskPath) {
		if rl.IsWindowReady() do texture2d = rl.LoadTexture(fmt.ctprint(diskPath))
	} else if bytes, found := resource_bytes(rm, filePath); found {
		defer delete(bytes)
		if rl.IsWindowReady() {
			img := rl.LoadImageFromMemory(fmt.ctprint(Image_ExtFor(bytes, filePath)), raw_data(bytes), i32(len(bytes))) // (QOI from export)
			texture2d = rl.LoadTextureFromImage(img)
			rl.UnloadImage(img)
		}
	} else {
		log.errorf("Texture not found: %s", filePath)
		return nil, false
	}
	tex := new(Texture)
	// Owned copies: callers usually pass temporary strings.
	tex.filePath = strings.clone(filePath)
	tex.fileName = filepath.base(tex.filePath)
	tex.texture = texture2d
	tex.refCount = 1
	Texture_ApplyImport(&tex.texture, Texture_ImportFor(rm, filePath)) // project.json "texture_import"
	if info, serr := os.stat(filePath, context.temp_allocator); serr == nil do tex.modTime = info.modification_time
	append(&rm.textures, tex)
	return tex, true
}

// ResourceManager_TextureFromImage: the cached texture for a path (a
// reference taken), else one uploaded from an already decoded image (the
// background decoder, async_decode.odin). The image stays the caller's.
ResourceManager_TextureFromImage :: proc(rm: ^ResourceManager, filePath: string, img: rl.Image) -> ^Texture {
	for tex in rm.textures {
		if tex != nil && tex.filePath == filePath {
			tex.refCount += 1
			return tex
		}
	}
	tex := new(Texture)
	tex.filePath = strings.clone(filePath)
	tex.fileName = filepath.base(tex.filePath)
	tex.texture = rl.LoadTextureFromImage(img)
	tex.refCount = 1
	Texture_ApplyImport(&tex.texture, Texture_ImportFor(rm, filePath))
	if info, serr := os.stat(filePath, context.temp_allocator); serr == nil do tex.modTime = info.modification_time
	append(&rm.textures, tex)
	return tex
}

// ResourceManager_HasTexture: is a path's texture cached (no reference taken)?
ResourceManager_HasTexture :: proc(rm: ^ResourceManager, filePath: string) -> bool {
	for tex in rm.textures do if tex != nil && tex.filePath == filePath do return true
	return false
}

GetTexture :: proc(rm: ^ResourceManager, fileName: string) -> (texture: ^Texture, ok: bool) {
	for tex in rm.textures {
		if tex != nil && tex.fileName == fileName {
			tex.refCount += 1
			return tex, true
		}
	}
	return nil ,false
}

UnloadTexture :: proc(rm: ^ResourceManager, fileName: string) {
	for tex in rm.textures {
		if tex != nil && (tex.filePath == fileName || tex.fileName == fileName) {
			ResourceManager_ReleaseTexture(rm, tex)
			return
		}
	}
}

// ResourceManager_ReleaseTexture drops one reference; the GPU texture is
// freed when nothing uses it any more.
ResourceManager_ReleaseTexture :: proc(rm: ^ResourceManager, tex: ^Texture) {
	if rm == nil || tex == nil do return
	for t, i in rm.textures {
		if t != tex do continue
		tex.refCount -= 1
		if tex.refCount > 0 do return
		if tex.page > 0 do Atlas_ReleasePage(rm, tex.page - 1)
		else if tex.texture.id > 0 && rl.IsWindowReady() do rl.UnloadTexture(tex.texture)
		delete(tex.filePath)
		free(tex)
		ordered_remove(&rm.textures, i)
		return
	}
}


ResourceManager_LoadAudioSound :: proc(rm: ^ResourceManager, filePath: string) -> (audioSound: ^AudioSound, ok: bool) {
	for i in 0 ..< rm.audioCount {
		if rm.audioSounds[i].filePath == filePath {
			rm.audioSounds[i].refCount += 1
			return &rm.audioSounds[i], true
		}
	}
	slot := -1
	for i in 0 ..< rm.audioCount {
		if rm.audioSounds[i].filePath == "" {slot = i; break}
	}
	if slot < 0 && rm.audioCount >= MAX_AUDIOSOUNDS {
		log.error("Max audios reached")
		return nil, false
	}
	// Decoded once to the mixer's format (48 kHz stereo floats); no audio
	// device needed (tests mix them too).
	wave: rl.Wave
	diskPath, _ := Mods_ResourceDiskPath(rm.projectDir, filePath) // (a mod's sound: mods.odin)
	if os.is_file(diskPath) {
		wave = rl.LoadWave(fmt.ctprint(diskPath))
	} else if bytes, found := resource_bytes(rm, filePath); found {
		defer delete(bytes)
		wave = rl.LoadWaveFromMemory(file_ext_cstring(filePath), raw_data(bytes), i32(len(bytes)))
	} else {
		log.errorf("Sound not found: %s", filePath)
		return nil, false
	}
	pcm: []f32
	sound: rl.Sound
	if wave.data != nil && wave.frameCount > 0 {
		if rl.IsAudioDeviceReady() do sound = rl.LoadSoundFromWave(wave)
		rl.WaveFormat(&wave, MIXER_RATE, 32, 2)
		pcm = make([]f32, int(wave.frameCount) * 2, Engine_HeapAllocator())
		copy(pcm, ([^]f32)(wave.data)[:len(pcm)])
		// Import gain (asset_import.odin), applied once here.
		if g := Asset_GainLinear(Asset_ImportGet(rm, filePath)); g != 1 do for &v in pcm do v *= g
	}
	rl.UnloadWave(wave)
	owned := strings.clone(filePath)
	if slot < 0 {
		slot = rm.audioCount
		rm.audioCount += 1
	}
	rm.audioSounds[slot] = AudioSound{fileName = filepath.base(owned), filePath = owned, pcm = pcm, sound = sound, refCount = 1}
	return &rm.audioSounds[slot], true
}

GetAudioSound :: proc(rm: ^ResourceManager, fileName: string) -> (audioSound: ^AudioSound, ok: bool) {
	for &audio in rm.audioSounds {
		if audio.fileName == fileName {
			audio.refCount += 1
			return &audio, true
		}
	}
	return nil, false
}

UnloadAudioSound :: proc(rm: ^ResourceManager, fileName: string) {
	for i in 0 ..< rm.audioCount {
		if rm.audioSounds[i].filePath == fileName || rm.audioSounds[i].fileName == fileName {
			ResourceManager_ReleaseSound(rm, &rm.audioSounds[i])
			return
		}
	}
}

// ResourceManager_ReleaseSound drops one reference; at zero the sound is
// unloaded and its slot reused (slots never move, so other pointers stay valid).
ResourceManager_ReleaseSound :: proc(rm: ^ResourceManager, audio: ^AudioSound) {
	if rm == nil || audio == nil || audio.filePath == "" do return
	audio.refCount -= 1
	if audio.refCount > 0 do return
	Mixer_StopOwner(audio) // its voices first (they read the samples)
	delete(audio.pcm, Engine_HeapAllocator())
	if audio.sound.frameCount > 0 && rl.IsAudioDeviceReady() do rl.UnloadSound(audio.sound)
	delete(audio.filePath)
	audio^ = {}
}

ResourceManager_LoadAudioMusic :: proc(rm: ^ResourceManager, filePath: string) -> (audioMusic: ^AudioMusic, ok: bool) {
	for i in 0 ..< rm.musicCount {
		if rm.audioMusic[i].filePath == filePath {
			rm.audioMusic[i].refCount += 1
			return &rm.audioMusic[i], true
		}
	}
	mslot := -1
	for i in 0 ..< rm.musicCount {
		if rm.audioMusic[i].filePath == "" {mslot = i; break}
	}
	if mslot < 0 && rm.musicCount >= MAX_AUDIOMUSIC {
		log.error("Max music streams reached")
		return nil, false
	}
	music: rl.Music
	streamData: []byte
	diskPath, _ := Mods_ResourceDiskPath(rm.projectDir, filePath) // (a mod's music: mods.odin)
	if os.is_file(diskPath) {
		if rl.IsAudioDeviceReady() do music = rl.LoadMusicStream(fmt.ctprint(diskPath))
	} else if bytes, found := resource_bytes(rm, filePath); found {
		// Streams read their data lazily: keep the bytes alive with the music.
		streamData = bytes
		if rl.IsAudioDeviceReady() {
			music = rl.LoadMusicStreamFromMemory(file_ext_cstring(filePath), raw_data(bytes), i32(len(bytes)))
		}
	} else {
		log.errorf("Music not found: %s", filePath)
		return nil, false
	}
	owned := strings.clone(filePath)
	if mslot < 0 {
		mslot = rm.musicCount
		rm.musicCount += 1
	}
	rm.audioMusic[mslot] = AudioMusic{fileName = filepath.base(owned), filePath = owned, music = music, refCount = 1, streamData = streamData, gain = Asset_GainLinear(Asset_ImportGet(rm, filePath))}
	return &rm.audioMusic[mslot], true
}

GetAudioMusic :: proc(rm: ^ResourceManager, fileName: string) -> (audioMusic: ^AudioMusic, ok: bool) {
	for &audio in rm.audioMusic {
		if audio.fileName == fileName {
			audio.refCount += 1
			return &audio, true
		}
	}
	return nil, false
}

UnloadAudioMusic :: proc(rm: ^ResourceManager, fileName: string) {
	for i in 0 ..< rm.musicCount {
		if rm.audioMusic[i].filePath == fileName || rm.audioMusic[i].fileName == fileName {
			ResourceManager_ReleaseMusic(rm, &rm.audioMusic[i])
			return
		}
	}
}

ResourceManager_ReleaseMusic :: proc(rm: ^ResourceManager, m: ^AudioMusic) {
	if rm == nil || m == nil || m.filePath == "" do return
	m.refCount -= 1
	if m.refCount > 0 do return
	Mixer_StopOwner(m) // its voice reads the decoder
	if rl.IsAudioDeviceReady() && rl.IsMusicValid(m.music) {
		rl.UnloadMusicStream(m.music)
	}
	delete(m.filePath)
	delete(m.streamData)
	m^ = {}
}

// Node_ResourceManager is the resource manager of the node's game (or nil).
Node_ResourceManager :: proc(node: ^Node) -> ^ResourceManager {
	if node != nil && node.gameContext != nil && node.gameContext.game != nil do return &node.gameContext.game.resourceManager
	return nil
}

@(private = "file")
textureCheck: time.Tick

// ResourceManager_CheckForChanges reloads textures whose files changed
// (an image edited while the game or editor runs); every user of the
// texture sees the new pixels. Stats files at most twice a second.
ResourceManager_CheckForChanges :: proc(rm: ^ResourceManager) -> int {
	if rm == nil || !rl.IsWindowReady() || time.tick_since(textureCheck) < 500 * time.Millisecond do return 0
	textureCheck = time.tick_now()
	n := Ase_CheckForChanges(rm) // (Aseprite files: aseprite_resource.odin)
	n += Vector_CheckForChanges(rm) // (SVG files: vector_asset.odin)
	for t in rm.textures {
		if t == nil || t.modTime == {} || t.page > 0 do continue
		info, err := os.stat(t.filePath, context.temp_allocator)
		if err != nil || time.diff(t.modTime, info.modification_time) <= 0 do continue
		fresh: rl.Texture2D
		if Ase_IsPath(t.filePath) {
			data, rerr := os.read_entire_file(t.filePath, context.temp_allocator)
			if rerr != nil do continue
			doc, _ := Ase_Load(data)
			if doc == nil do continue
			img := Ase_FrameImage(doc, 0)
			fresh = rl.LoadTextureFromImage(img)
			rl.UnloadImage(img)
			Ase_Destroy(doc)
		} else {
			fresh = rl.LoadTexture(strings.clone_to_cstring(t.filePath, context.temp_allocator))
		}
		if fresh.id == 0 do continue // half-written: try again later
		t.modTime = info.modification_time
		rl.UnloadTexture(t.texture)
		t.texture = fresh
		Texture_ApplyImport(&t.texture, Texture_ImportFor(rm, t.filePath))
		log.infof("Reloaded %s", t.fileName)
		n += 1
	}
	return n
}

// Decode_ReadBytes: a texture file's bytes for decoding (heap), from disk or
// the packed project (main thread).
Decode_ReadBytes :: proc(rm: ^ResourceManager, path: string) -> ([]u8, bool) {
	if os.is_file(path) {
		data, err := os.read_entire_file(path, Engine_HeapAllocator())
		return data, err == nil
	}
	if b, ok := resource_bytes(rm, path); ok {
		defer delete(b)
		c := make([]u8, len(b), Engine_HeapAllocator())
		copy(c, b)
		return c, true
	}
	return nil, false
}
