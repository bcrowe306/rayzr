package editor

import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Multi-Asset Preview Panel Subsystem
// Previews Textures, Audio Playback, Sprite Animations, Scene Data & Lua Script References
// ============================================================================

ScriptReference :: struct {
	sourceType: string, // "Active Scene", "Scene File", "Component"
	sourceName: string, // "battle_arena.scene.json" or "PlayerSpaceship.component.json"
	nodeName:   string, // "PlayerShip"
	nodeType:   string, // "TextureNode"
	isLiveNode: bool,
	liveNode:   ^e.Node,
}

// ----------------------------------------------------------------------------
// Asset & Node Selection Event Hooks
// ----------------------------------------------------------------------------

PreviewPanel_OnAssetSelected :: proc(state: ^EditorState, fullPath: string) {
	if state == nil || fullPath == "" do return

	ext := strings.to_lower(filepath.ext(fullPath), context.temp_allocator)

	switch ext {
	case ".png", ".jpg", ".jpeg", ".bmp", ".tga", ".svg":
		PreviewPanel_LoadTexture(state, fullPath)
		if state.previewAutoSwitch {
			state.previewTab = .Texture
		}

	case ".wav", ".mp3", ".ogg", ".flac":
		PreviewPanel_LoadAudio(state, fullPath)
		if state.previewAutoSwitch {
			state.previewTab = .Audio
		}
		if GlobalSettings.previewAutoplay do PreviewPanel_PlayAudio(state) // (browsing: hear it, #203)

	case ".aseprite", ".ase", ".gif":
		// Animated: its frames in the Animation tab (a still GIF: the image).
		if PreviewPanel_LoadAnimationFile(state, fullPath) {
			if state.previewAutoSwitch do state.previewTab = .Animation
		} else if ext == ".gif" {
			PreviewPanel_LoadTexture(state, fullPath)
			if state.previewAutoSwitch do state.previewTab = .Texture
		}

	case ".scene.json", ".json":
		if strings.ends_with(fullPath, ".scene.json") {
			state.previewScenePath = strings.clone(fullPath)
			if state.previewAutoSwitch {
				state.previewTab = .Scene
			}
		} else if strings.ends_with(fullPath, ".component.json") {
			// Components can preview their script or texture
			state.previewScenePath = strings.clone(fullPath)
		}

	case ".lua":
		state.previewScriptPath = strings.clone(fullPath)
		if state.previewAutoSwitch {
			state.previewTab = .Script
		}
	}
}

PreviewPanel_OnNodeSelected :: proc(state: ^EditorState, node: ^e.Node) {
	if state == nil || node == nil do return

	if node.typeId == typeid_of(e.TextureNode) {
		tn := cast(^e.TextureNode)node
		if tn.filePath != "" {
			resolved := e.Project_ResolveAssetPath(&state.game.gameContext, tn.filePath)
			PreviewPanel_LoadTexture(state, resolved)
			if state.previewAutoSwitch {
				state.previewTab = .Texture
			}
		}
	} else if node.typeId == typeid_of(e.AtlasSpriteNode) {
		an := cast(^e.AtlasSpriteNode)node
		if an.filePath != "" {
			resolved := e.Project_ResolveAssetPath(&state.game.gameContext, an.filePath)
			PreviewPanel_LoadTexture(state, resolved)
			if state.previewAutoSwitch {
				state.previewTab = .Texture
			}
		}
	} else if node.typeId == typeid_of(e.FrameAnimationNode) {
		PreviewPanel_LoadAnimationFromNode(state, cast(^e.FrameAnimationNode)node)
		if state.previewAutoSwitch {
			state.previewTab = .Animation
		}
	} else if node.typeId == typeid_of(e.SoundNode) {
		sn := cast(^e.SoundNode)node
		_ = sn
		if state.previewAutoSwitch {
			state.previewTab = .Audio
		}
	} else if node.scriptInstance != nil {
		inst := cast(^e.ScriptInstance)node.scriptInstance
		if inst.modulePath != "" {
			resolved := e.Project_ResolveAssetPath(&state.game.gameContext, inst.modulePath)
			state.previewScriptPath = strings.clone(resolved)
			if state.previewAutoSwitch {
				state.previewTab = .Script
			}
		}
	} else if node == state.activeScene.rootNode {
		if state.previewAutoSwitch {
			state.previewTab = .Scene
		}
	}
}

// ----------------------------------------------------------------------------
// Resource Loaders
// ----------------------------------------------------------------------------

PreviewPanel_LoadTexture :: proc(state: ^EditorState, fullPath: string) {
	if state.previewTexturePath == fullPath && state.previewTextureLoaded do return

	if state.previewTextureLoaded {
		rl.UnloadTexture(state.previewTexture)
		state.previewTextureLoaded = false
	}

	pathC := strings.clone_to_cstring(fullPath, context.temp_allocator)
	tex: rl.Texture2D
	if e.Vector_IsPath(fullPath) {
		// Vector art: rendered to fit 512 px (vector_editor.odin).
		img := e.Vector_FileImage(fullPath, 512)
		if img.data != nil {
			tex = rl.LoadTextureFromImage(img)
			rl.UnloadImage(img)
			rl.SetTextureFilter(tex, .BILINEAR)
		}
	} else {
		tex = rl.LoadTexture(pathC)
	}
	if tex.id > 0 {
		state.previewTexture = tex
		state.previewTextureLoaded = true
		state.previewTexturePath = strings.clone(fullPath)
	}
}

PreviewPanel_LoadAudio :: proc(state: ^EditorState, fullPath: string) {
	if state.previewSoundPath == fullPath && state.previewSoundLoaded do return

	if state.previewSoundLoaded {
		if state.previewAudioPlaying {
			rl.StopSound(state.previewSound)
			state.previewAudioPlaying = false
		}
		rl.UnloadSound(state.previewSound)
		state.previewSoundLoaded = false
	}
	delete(state.previewSoundPath)
	state.previewSoundPath = ""

	if !rl.IsAudioDeviceReady() {
		rl.InitAudioDevice()
	}

	pathC := strings.clone_to_cstring(fullPath, context.temp_allocator)
	snd := rl.LoadSound(pathC)
	if rl.IsSoundReady(snd) {
		state.previewSound = snd
		state.previewSoundLoaded = true
		state.previewSoundPath = strings.clone(fullPath)
		state.previewAudioPlaying = false
		state.previewAudioTimer = 0.0

		// Estimate duration: frameCount / sampleRate
		rate: f32 = 44100.0
		if snd.stream.sampleRate > 0 do rate = f32(snd.stream.sampleRate)
		state.previewAudioDuration = f32(snd.frameCount) / rate
		if state.previewAudioDuration <= 0 do state.previewAudioDuration = 1.0
	}
}

PreviewPanel_PlayAudio :: proc(state: ^EditorState) {
	if state == nil do return
	if rl.IsSoundReady(state.previewSound) {
		rl.SetSoundVolume(state.previewSound, GlobalSettings.previewVolume * e.Asset_GainLinear(e.Asset_ImportGet(&state.game.resourceManager, state.previewSoundPath))) // (with the import gain)
		rl.PlaySound(state.previewSound)
		state.previewAudioPlaying = true
		state.previewAudioTimer = 0.0
	}
}

PreviewPanel_StopAudio :: proc(state: ^EditorState) {
	if state == nil do return
	if rl.IsSoundReady(state.previewSound) {
		rl.StopSound(state.previewSound)
	}
	state.previewAudioPlaying = false
	state.previewAudioTimer = 0.0
}

PreviewPanel_LoadAnimationFromNode :: proc(state: ^EditorState, fan: ^e.FrameAnimationNode) {
	if fan == nil || len(fan.frames) == 0 do return

	// Clear previous
	for &tex in state.previewAnimFrames {
		rl.UnloadTexture(tex)
	}
	clear(&state.previewAnimFrames)
	clear(&state.previewAnimPaths)
	clear(&state.previewAnimDurations)

	for frame in fan.frames {
		if frame != nil && frame.texture.id > 0 {
			append(&state.previewAnimFrames, frame.texture)
			append(&state.previewAnimPaths, strings.clone(frame.filePath))
		}
	}

	state.previewAnimIndex = 0
	state.previewAnimTimer = 0.0
	state.previewAnimPlaying = true
	state.previewAnimLoadedPath = "Active FrameAnimationNode"
}

// PreviewPanel_LoadAnimationFile: an Aseprite file's or an animated GIF's
// frames, each with its own time (#203); playing when Autoplay is on.
PreviewPanel_LoadAnimationFile :: proc(state: ^EditorState, path: string) -> bool {
	if state.previewAnimLoadedPath == path && len(state.previewAnimFrames) > 0 {
		state.previewAnimPlaying = GlobalSettings.previewAutoplay
		state.previewAnimIndex, state.previewAnimTimer = 0, 0
		return true
	}
	strip, ok := e.Anim_LoadFileStrip(path)
	if !ok do return false
	defer e.Anim_StripDestroy(&strip)
	for &tex in state.previewAnimFrames do rl.UnloadTexture(tex)
	clear(&state.previewAnimFrames)
	clear(&state.previewAnimPaths)
	clear(&state.previewAnimDurations)
	for d, i in strip.durations {
		frame := rl.ImageFromImage(strip.image, e.Anim_StripFrameRect(strip, i))
		append(&state.previewAnimFrames, rl.LoadTextureFromImage(frame))
		rl.UnloadImage(frame)
		append(&state.previewAnimPaths, strings.clone(fmt.tprintf("%s #%d", filepath.base(path), i + 1)))
		append(&state.previewAnimDurations, d)
	}
	state.previewAnimIndex = 0
	state.previewAnimTimer = 0
	state.previewAnimPlaying = GlobalSettings.previewAutoplay
	state.previewAnimLoadedPath = strings.clone(path)
	return true
}

PreviewPanel_LoadAnimationFromFolder :: proc(state: ^EditorState, folderPath: string) {
	if state.previewAnimLoadedPath == folderPath && len(state.previewAnimFrames) > 0 do return

	for &tex in state.previewAnimFrames {
		rl.UnloadTexture(tex)
	}
	clear(&state.previewAnimFrames)
	clear(&state.previewAnimPaths)
	clear(&state.previewAnimDurations)

	if h, err := os.open(folderPath); err == nil {
		fis, _ := os.read_dir(h, -1, context.temp_allocator)
		os.close(h)

		for fi in fis {
			if strings.has_suffix(fi.name, ".png") {
				p, _ := filepath.join({folderPath, fi.name}, context.temp_allocator)
				pathC := strings.clone_to_cstring(p, context.temp_allocator)
				tex := rl.LoadTexture(pathC)
				if tex.id > 0 {
					append(&state.previewAnimFrames, tex)
					append(&state.previewAnimPaths, strings.clone(fi.name))
				}
			}
		}
	}

	state.previewAnimIndex = 0
	state.previewAnimTimer = 0.0
	state.previewAnimPlaying = true
	state.previewAnimLoadedPath = strings.clone(folderPath)
}

// ----------------------------------------------------------------------------
// Main Panel Window Renderer
// ----------------------------------------------------------------------------

PreviewPanel_Render :: proc(state: ^EditorState) {
	defer imgui.End()
	if !imgui.Begin("Preview###PreviewPanelWindow") do return
	Drive_Window("preview") // (annotated docs screenshots)

	// Header: what is previewed, and a compact icon switcher (the preview
	// follows the selection automatically).
	assetName := "Nothing selected"
	if state.selectedAssetPath != "" {
		assetName = filepath.base(state.selectedAssetPath)
		if len(state.selectedAssetPaths) > 1 {
			assetName = fmt.tprintf("%s (+%d selected)", assetName, len(state.selectedAssetPaths) - 1)
		}
	} else if state.selectedNode != nil {
		assetName = state.selectedNode.name
	}
	modes := [?]struct {
		tab:  PreviewPanelTab,
		icon: string,
		tip:  string,
	}{
		{.Texture, ICON_FA_IMAGE, "Texture"},
		{.Audio, ICON_FA_MUSIC, "Audio"},
		{.Animation, ICON_FA_FILM, "Animation"},
		{.Scene, ICON_FA_CLAPPERBOARD, "Scene"},
		{.Script, ICON_FA_CODE, "Script"},
	}
	UI_PanelTitle("", Asset_DisplayName(assetName), maxWidth = imgui.GetContentRegionAvail().x - f32(len(modes)) * (PANEL_BUTTON + 2) - 8)
	UI_HeaderButtons(len(modes))
	for m in modes {
		if UI_HeaderButton(m.icon, fmt.tprintf("preview.%v", m.tab), m.tip, state.previewTab == m.tab) do state.previewTab = m.tab
	}

	switch state.previewTab {
	case .Texture: PreviewPanel_RenderTexture(state)
	case .Audio: PreviewPanel_RenderAudio(state)
	case .Animation: PreviewPanel_RenderAnimation(state)
	case .Scene: PreviewPanel_RenderScene(state)
	case .Script: PreviewPanel_RenderScript(state)
	}
}

// ----------------------------------------------------------------------------
// 1. Texture Preview Subsystem
// ----------------------------------------------------------------------------

PreviewPanel_RenderTexture :: proc(state: ^EditorState) {
	// Fallback check: if no texture loaded yet, attempt to load selected asset or default ship texture
	if !state.previewTextureLoaded {
		fallback := preview_project_path(state, "textures/Spaceship_1.png")
		if state.selectedAssetPath != "" && strings.has_suffix(state.selectedAssetPath, ".png") {
			fallback = state.selectedAssetPath
		}
		if os.exists(fallback) {
			PreviewPanel_LoadTexture(state, fallback)
		}
	}

	// Quick Selector Combo for all textures
	texDir := preview_project_path(state, "textures")
	if os.is_dir(texDir) {
		if h, err := os.open(texDir); err == nil {
			fis, _ := os.read_dir(h, -1, context.temp_allocator)
			os.close(h)

			curName := filepath.base(state.previewTexturePath)
			imgui.SetNextItemWidth(260)
			if imgui.BeginCombo("##TexSelectCombo", fmt.ctprintf("%s %s", ICON_FA_IMAGE, curName)) {
				for fi in fis {
					if strings.has_suffix(fi.name, ".png") {
						isSel := (fi.name == curName)
						if imgui.Selectable(fmt.ctprintf("%s  %s", ICON_FA_IMAGE, fi.name), isSel) {
							p, _ := filepath.join({texDir, fi.name}, context.temp_allocator)
							PreviewPanel_LoadTexture(state, p)
						}
					}
				}
				imgui.EndCombo()
			}
		}
	}

	if !state.previewTextureLoaded || state.previewTexture.id == 0 {
		imgui.TextDisabled("No texture loaded. Select an image file (.png, .jpg) in the Asset Browser.")
		return
	}

	tex := state.previewTexture
	texW := f32(tex.width)
	texH := f32(tex.height)

	// Information badges
	imgui.SameLine()
	imgui.TextColored(imgui.Vec4{0.75, 0.80, 0.88, 1.0}, fmt.ctprintf("[%dx%d px | ID: %d]", int(texW), int(texH), tex.id))

	imgui.SameLine()
	imgui.SetNextItemWidth(100)
	imgui.SliderFloat("Zoom", &state.previewTextureZoom, 0.25, 4.0, "%.2fx")

	imgui.SameLine()
	imgui.Checkbox("Fit", &state.previewTextureFit)
	if e.Vector_IsPath(state.previewTexturePath) do Vector_ImportRows(state, state.previewTexturePath)
	else do preview_texture_import(state)

	imgui.Separator()

	// Canvas Region
	avail := imgui.GetContentRegionAvail()
	if avail.x <= 10 || avail.y <= 10 do return

	dispW := texW * state.previewTextureZoom
	dispH := texH * state.previewTextureZoom

	if state.previewTextureFit {
		aspect := texW / max(texH, 1.0)
		availAspect := avail.x / max(avail.y, 1.0)
		if availAspect > aspect {
			dispH = avail.y - 10.0
			dispW = dispH * aspect
		} else {
			dispW = avail.x - 10.0
			dispH = dispW / aspect
		}
	}

	if imgui.BeginChild("##TexCanvas", avail, {.Borders}, {.HorizontalScrollbar}) {
		// Draw checkerboard background for alpha transparency inspection
		p0 := imgui.GetCursorScreenPos()
		drawList := imgui.GetWindowDrawList()
		if drawList != nil {
			colA := col32(28, 32, 42, 255)
			colB := col32(38, 44, 58, 255)
			gridSz: f32 = 16.0
			for gy: f32 = 0; gy < dispH; gy += gridSz {
				for gx: f32 = 0; gx < dispW; gx += gridSz {
					c := (((int(gx/gridSz) + int(gy/gridSz)) % 2) == 0) ? colA : colB
					rx := p0.x + gx
					ry := p0.y + gy
					rw := min(gridSz, dispW - gx)
					rh := min(gridSz, dispH - gy)
					imgui.DrawList_AddRectFilled(drawList, imgui.Vec2{rx, ry}, imgui.Vec2{rx + rw, ry + rh}, c)
				}
			}
		}

		// Render the Texture image
		imgui.Image(
			transmute(imgui.TextureID)&state.previewTexture,
			imgui.Vec2{dispW, dispH},
			imgui.Vec2{0, 0},
			imgui.Vec2{1, 1},
			imgui.Vec4{1, 1, 1, 1},
			imgui.Vec4{0.25, 0.35, 0.50, 0.60},
		)

		if imgui.IsItemHovered() {
			mPos := imgui.GetIO().MousePos
			relX := int((mPos.x - p0.x) / max(dispW, 1.0) * texW)
			relY := int((mPos.y - p0.y) / max(dispH, 1.0) * texH)
			Editor_Tooltip(fmt.tprintf("Pixel: (%d, %d)", relX, relY))
		}
	}
	imgui.EndChild()
}

// ----------------------------------------------------------------------------
// 2. Audio Playback Subsystem
// ----------------------------------------------------------------------------

PreviewPanel_RenderAudio :: proc(state: ^EditorState) {
	// Fallback check: if no sound loaded yet, load cannon-gunshot-1.wav or selected audio asset
	if !state.previewSoundLoaded {
		fallback := preview_project_path(state, "audio/cannon-gunshot-1.wav")
		if state.selectedAssetPath != "" {
			ext := strings.to_lower(filepath.ext(state.selectedAssetPath), context.temp_allocator)
			if ext == ".wav" || ext == ".ogg" || ext == ".mp3" || ext == ".flac" {
				fallback = state.selectedAssetPath
			}
		}
		if os.exists(fallback) {
			PreviewPanel_LoadAudio(state, fallback)
		}
	}

	// Quick Selector Combo for all audio clips
	audioDir := preview_project_path(state, "audio")
	if os.is_dir(audioDir) {
		if h, err := os.open(audioDir); err == nil {
			fis, _ := os.read_dir(h, -1, context.temp_allocator)
			os.close(h)

			curName := filepath.base(state.previewSoundPath)
			imgui.SetNextItemWidth(260)
			if imgui.BeginCombo("##AudioSelectCombo", fmt.ctprintf("%s %s", ICON_FA_MUSIC, curName)) {
				for fi in fis {
					if strings.has_suffix(fi.name, ".wav") || strings.has_suffix(fi.name, ".ogg") || strings.has_suffix(fi.name, ".mp3") {
						isSel := (fi.name == curName)
						if imgui.Selectable(fmt.ctprintf("%s  %s", ICON_FA_MUSIC, fi.name), isSel) {
							p, _ := filepath.join({audioDir, fi.name}, context.temp_allocator)
							PreviewPanel_LoadAudio(state, p)
						}
					}
				}
				imgui.EndCombo()
			}
		}
	}

	if !state.previewSoundLoaded {
		imgui.TextDisabled("No audio loaded. Select an audio file (.wav, .ogg) in the Asset Browser.")
		return
	}

	sndName := filepath.base(state.previewSoundPath)
	duration := state.previewAudioDuration

	imgui.SameLine()
	imgui.TextColored(imgui.Vec4{0.75, 0.85, 0.95, 1.0}, fmt.ctprintf("[Duration: %.2fs | 44.1 kHz]", duration))

	imgui.Separator()

	// 1. Interactive Audio Controls Toolbar
	imgui.PushStyleVarImVec2(imgui.StyleVar.ItemSpacing, imgui.Vec2{8, 4})

	// Play button
	wasPlaying := state.previewAudioPlaying
	if wasPlaying {
		imgui.PushStyleColorImVec4(imgui.Col.Button, imgui.Vec4{0.0, 0.65, 0.50, 1.0})
	}
	if imgui.Button(fmt.ctprintf("%s Play###AudioPlayBtn", ICON_FA_PLAY), imgui.Vec2{72, 28}) {
		PreviewPanel_PlayAudio(state)
	}
	if wasPlaying {
		imgui.PopStyleColor()
	}
	Drive_Item("preview.audio.play")

	// Stop button
	imgui.SameLine()
	if imgui.Button(fmt.ctprintf("%s Stop###AudioStopBtn", ICON_FA_STOP), imgui.Vec2{72, 28}) {
		PreviewPanel_StopAudio(state)
	}
	Drive_Item("preview.audio.stop")

	// Autoplay, loop, volume (shared with the File Browser, #203)
	imgui.SameLine()
	if Preview_Toggles("preview.audio") {
		if rl.IsSoundReady(state.previewSound) {
			rl.SetSoundVolume(state.previewSound, GlobalSettings.previewVolume * e.Asset_GainLinear(e.Asset_ImportGet(&state.game.resourceManager, state.previewSoundPath))) // (with the import gain)
		}
	}

	preview_audio_import(state)

	imgui.PopStyleVar()

	// Advance playback timer
	if state.previewAudioPlaying {
		dt := rl.GetFrameTime()
		state.previewAudioTimer += dt
		if state.previewAudioTimer >= duration {
			if GlobalSettings.previewLoop {
				state.previewAudioTimer = 0.0
				rl.PlaySound(state.previewSound)
			} else {
				state.previewAudioPlaying = false
				state.previewAudioTimer = 0.0
			}
		}
	}

	// 2. Playback Scrubber & Progress Bar
	prog := math.clamp(state.previewAudioTimer / max(duration, 0.001), f32(0.0), f32(1.0))
	timeStr := fmt.tprintf("%.2fs / %.2fs", state.previewAudioTimer, duration)
	timeC := strings.clone_to_cstring(timeStr, context.temp_allocator)
	imgui.ProgressBar(prog, imgui.Vec2{-1, 16}, timeC)

	// 3. Real-Time Animated Spectrum Waveform Visualizer
	avail := imgui.GetContentRegionAvail()
	if avail.x > 20 && avail.y > 40 {
		if imgui.BeginChild("##WaveformChild", imgui.Vec2{-1, max(avail.y, 60)}, {.Borders}, {}) {
			p0 := imgui.GetCursorScreenPos()
			wSize := imgui.GetWindowSize()
			drawList := imgui.GetWindowDrawList()

			if drawList != nil {
				// Dark studio waveform background
				imgui.DrawList_AddRectFilled(drawList, p0, imgui.Vec2{p0.x + wSize.x, p0.y + wSize.y}, col32(16, 20, 28, 255))

				// Center line
				midY := p0.y + wSize.y * 0.5
				imgui.DrawList_AddLine(drawList, imgui.Vec2{p0.x, midY}, imgui.Vec2{p0.x + wSize.x, midY}, col32(45, 55, 75, 180), 1.0)

				barCount := 36
				barW := (wSize.x - 20.0) / f32(barCount)
				baseAmp: f32 = 8.0
				nowT := f32(rl.GetTime())

				for i := 0; i < barCount; i += 1 {
					bx := p0.x + 10.0 + f32(i) * barW

					// Frequency height response
					barHeight: f32 = baseAmp
					if state.previewAudioPlaying {
						freq := f32(i) * 0.4
						wave := math.sin(nowT * 14.0 + freq) * math.cos(nowT * 8.0 - f32(i) * 0.2)
						barHeight = baseAmp + math.abs(wave) * (wSize.y * 0.42)
					}

					bTop := midY - barHeight * 0.5
					bBot := midY + barHeight * 0.5

					// Dynamic audio visualizer color gradient (Teal -> Emerald -> Amber)
					barCol := col32(0, 206, 201, 220)
					if i > 24 {
						barCol = col32(255, 195, 18, 240)
					} else if i > 14 {
						barCol = col32(46, 213, 115, 230)
					}

					imgui.DrawList_AddRectFilled(drawList, imgui.Vec2{bx + 1, bTop}, imgui.Vec2{bx + barW - 2, bBot}, barCol, 2.0)
				}
			}
		}
		imgui.EndChild()
	}
}

// ----------------------------------------------------------------------------
// 3. Animation Preview Subsystem
// ----------------------------------------------------------------------------

PreviewPanel_RenderAnimation :: proc(state: ^EditorState) {
	// Auto-load exhaust animation frames if empty
	if len(state.previewAnimFrames) == 0 {
		exhaustFolder := preview_project_path(state, "textures/exhaust")
		if os.is_dir(exhaustFolder) {
			PreviewPanel_LoadAnimationFromFolder(state, exhaustFolder)
		}
	}

	// Animation Set Selector
	curAnimName := state.previewAnimLoadedPath
	imgui.SetNextItemWidth(260)
	if imgui.BeginCombo("##AnimSetCombo", fmt.ctprintf("%s %s", ICON_FA_FILM, curAnimName)) {
		if imgui.Selectable("Engine Exhaust (5 frames)", curAnimName == preview_project_path(state, "textures/exhaust")) {
			PreviewPanel_LoadAnimationFromFolder(state, preview_project_path(state, "textures/exhaust"))
		}
		if state.activeScene != nil && state.activeScene.rootNode != nil {
			if imgui.Selectable("Active Scene Exhaust Node", curAnimName == "Active FrameAnimationNode") {
				// Search for FrameAnimationNode
				for n in state.activeScene.manager.nodes {
					if n != nil && n.typeId == typeid_of(e.FrameAnimationNode) {
						PreviewPanel_LoadAnimationFromNode(state, cast(^e.FrameAnimationNode)n)
						break
					}
				}
			}
		}
		imgui.EndCombo()
	}

	frameCount := len(state.previewAnimFrames)
	if frameCount == 0 {
		imgui.TextDisabled("No animation frames found. Add an animation or select a FrameAnimationNode.")
		return
	}

	// 1. Playback Controls Toolbar
	imgui.SameLine()
	imgui.TextColored(imgui.Vec4{0.75, 0.85, 0.95, 1.0}, fmt.ctprintf("[%d Frames | Frame: %d / %d]", frameCount, state.previewAnimIndex + 1, frameCount))

	imgui.Separator()

	imgui.PushStyleVarImVec2(imgui.StyleVar.ItemSpacing, imgui.Vec2{6, 4})

	// First Frame
	if imgui.Button(fmt.ctprintf("%s###AnimFirst", ICON_FA_BACKWARD_STEP), imgui.Vec2{30, 26}) {
		state.previewAnimIndex = 0
	}
	// Prev Frame
	imgui.SameLine()
	if imgui.Button(fmt.ctprintf("%s###AnimPrev", ICON_FA_CHEVRON_LEFT), imgui.Vec2{30, 26}) {
		state.previewAnimIndex = (state.previewAnimIndex - 1 + frameCount) % frameCount
	}
	// Play / Pause
	imgui.SameLine()
	playIcon := state.previewAnimPlaying ? ICON_FA_PAUSE : ICON_FA_PLAY
	if imgui.Button(fmt.ctprintf("%s###AnimPlay", playIcon), imgui.Vec2{36, 26}) {
		state.previewAnimPlaying = !state.previewAnimPlaying
	}
	// Next Frame
	imgui.SameLine()
	if imgui.Button(fmt.ctprintf("%s###AnimNext", ICON_FA_CHEVRON_RIGHT), imgui.Vec2{30, 26}) {
		state.previewAnimIndex = (state.previewAnimIndex + 1) % frameCount
	}
	// Last Frame
	imgui.SameLine()
	if imgui.Button(fmt.ctprintf("%s###AnimLast", ICON_FA_FORWARD_STEP), imgui.Vec2{30, 26}) {
		state.previewAnimIndex = frameCount - 1
	}

	// FPS drag
	imgui.SameLine()
	imgui.SetNextItemWidth(80)
	imgui.DragFloat("##AnimFPS", &state.previewAnimFPS, 1.0, 1.0, 60.0, "%.0f FPS")

	// Loop (the browsing previews' setting, #203)
	imgui.SameLine()
	if imgui.Checkbox("Loop", &GlobalSettings.previewLoop) do _ = Editor_SaveSettings()

	imgui.PopStyleVar()

	// Advance animation frame
	if state.previewAnimPlaying && state.previewAnimFPS > 0 {
		dt := rl.GetFrameTime()
		state.previewAnimTimer += dt
		frameDur := 1.0 / state.previewAnimFPS
		// (An Aseprite file / GIF: each frame's own time.)
		if state.previewAnimIndex < len(state.previewAnimDurations) do frameDur = state.previewAnimDurations[state.previewAnimIndex]
		if state.previewAnimTimer >= frameDur {
			state.previewAnimTimer = 0.0
			state.previewAnimIndex += 1
			if state.previewAnimIndex >= frameCount {
				if GlobalSettings.previewLoop {
					state.previewAnimIndex = 0
				} else {
					state.previewAnimIndex = frameCount - 1
					state.previewAnimPlaying = false
				}
			}
		}
	}

	// 2. Active Frame Viewport
	state.previewAnimIndex = math.clamp(state.previewAnimIndex, 0, frameCount - 1)
	activeTex := state.previewAnimFrames[state.previewAnimIndex]

	avail := imgui.GetContentRegionAvail()
	filmstripHeight: f32 = 64.0
	viewH := max(avail.y - filmstripHeight - 12.0, 80.0)

	if imgui.BeginChild("##AnimViewChild", imgui.Vec2{-1, viewH}, {.Borders}, {}) {
		p0 := imgui.GetCursorScreenPos()
		wSize := imgui.GetWindowSize()

		dispSz: f32 = min(wSize.x - 20.0, wSize.y - 20.0)
		posX := p0.x + (wSize.x - dispSz) * 0.5
		posY := p0.y + (wSize.y - dispSz) * 0.5

		imgui.SetCursorScreenPos(imgui.Vec2{posX, posY})
		imgui.Image(
			transmute(imgui.TextureID)&activeTex,
			imgui.Vec2{dispSz, dispSz},
			imgui.Vec2{0, 0},
			imgui.Vec2{1, 1},
			imgui.Vec4{1, 1, 1, 1},
			imgui.Vec4{0.0, 0.85, 0.75, 0.40},
		)
	}
	imgui.EndChild()

	// 3. Filmstrip of All Thumbnails
	if imgui.BeginChild("##AnimFilmstrip", imgui.Vec2{-1, filmstripHeight}, {}, {.HorizontalScrollbar}) {
		imgui.PushStyleVarImVec2(imgui.StyleVar.ItemSpacing, imgui.Vec2{6, 2})
		for idx in 0..<frameCount {
			if idx > 0 do imgui.SameLine()
			thumbTex := state.previewAnimFrames[idx]
			isCur := (idx == state.previewAnimIndex)

			borderCol := isCur ? imgui.Vec4{0.0, 0.85, 0.75, 1.0} : imgui.Vec4{0.25, 0.30, 0.40, 0.50}

			imgui.PushIDInt(c.int(idx))
			if imgui.ImageButton(
				fmt.ctprintf("###thumb_%d", idx),
				transmute(imgui.TextureID)&thumbTex,
				imgui.Vec2{48, 48},
				imgui.Vec2{0, 0},
				imgui.Vec2{1, 1},
				imgui.Vec4{0.1, 0.12, 0.16, 1.0},
				imgui.Vec4{1, 1, 1, 1},
			) {
				state.previewAnimIndex = idx
			}
			imgui.PopID()
			Editor_Tooltip(fmt.tprintf("Frame %d", idx + 1))
		}
		imgui.PopStyleVar()
	}
	imgui.EndChild()
}

// ----------------------------------------------------------------------------
// 4. Scene Data Inspection Subsystem
// ----------------------------------------------------------------------------

PreviewPanel_RenderScene :: proc(state: ^EditorState) {
	scene := state.activeScene
	if scene == nil {
		imgui.TextDisabled("No active scene in editor.")
		return
	}

	// Header summary cards
	imgui.TextColored(imgui.Vec4{0.0, 0.85, 0.75, 1.0}, fmt.ctprintf("%s  %s", ICON_FA_CLAPPERBOARD, scene.name))
	imgui.SameLine()
	imgui.TextColored(imgui.Vec4{0.46, 0.85, 0.45, 1.0}, "[ACTIVE VIEWPORT SCENE]")

	imgui.Separator()

	// Metrics Overview Grid
	nodeCount := len(scene.manager.nodes) if scene.manager != nil else 0
	camTarget := scene.camera.currentPosition if scene.camera != nil else [2]f32{640, 360}
	camZoom := scene.camera.currentZoom if scene.camera != nil else 1.0
	grav := state.game.physicsWorld.gravity

	if imgui.BeginTable("##SceneMetricsTable", 4, imgui.TableFlags_BordersInnerV | imgui.TableFlags_BordersOuter) {
		imgui.TableNextRow()
		imgui.TableSetColumnIndex(0); imgui.TextDisabled("Total Nodes:"); imgui.Text(fmt.ctprintf("%d", nodeCount))
		imgui.TableSetColumnIndex(1); imgui.TextDisabled("Camera Focus:"); imgui.Text(fmt.ctprintf("[%.0f, %.0f]", camTarget.x, camTarget.y))
		imgui.TableSetColumnIndex(2); imgui.TextDisabled("Camera Zoom:"); imgui.Text(fmt.ctprintf("%.2fx", camZoom))
		imgui.TableSetColumnIndex(3); imgui.TextDisabled("World Gravity:"); imgui.Text(fmt.ctprintf("[%.1f, %.1f]", grav.x, grav.y))
		imgui.EndTable()
	}

	imgui.Spacing()

	// Complete Hierarchy Breakdown Table
	imgui.TextColored(imgui.Vec4{0.85, 0.90, 0.95, 1.0}, "Scene Node Breakdown:")
	if imgui.BeginTable("##SceneNodeTable", 6, imgui.TableFlags_Resizable | imgui.TableFlags_Reorderable | imgui.TableFlags_RowBg | imgui.TableFlags_Borders | imgui.TableFlags_ScrollY) {
		imgui.TableSetupColumn("Node Name", {.WidthStretch})
		imgui.TableSetupColumn("Type", {.WidthFixed}, 120)
		imgui.TableSetupColumn("Layer", {.WidthFixed}, 60)
		imgui.TableSetupColumn("Position", {.WidthFixed}, 110)
		imgui.TableSetupColumn("Scale", {.WidthFixed}, 90)
		imgui.TableSetupColumn("Script Attached", {.WidthStretch})
		imgui.TableHeadersRow()

		if scene.manager != nil {
			// Only the rows on screen are built (a scene can have thousands).
			rows := make([dynamic]^e.Node, 0, len(scene.manager.nodes), context.temp_allocator)
			for n in scene.manager.nodes do if n != nil do append(&rows, n)
			clipper: imgui.ListClipper
			imgui.ListClipper_Begin(&clipper, c.int(len(rows)))
			for imgui.ListClipper_Step(&clipper) do for n in rows[clipper.DisplayStart:clipper.DisplayEnd] {
				imgui.TableNextRow()
				isSelected := (n == state.selectedNode)
				if isSelected {
					imgui.TableSetBgColor(.RowBg0, col32(0, 168, 150, 60))
				}

				imgui.TableSetColumnIndex(0)
				nameStr := fmt.ctprintf("%s  %s", ICON_FA_FILE, n.name)
				if imgui.Selectable(nameStr, isSelected, {.SpanAllColumns}) {
					state.selectedNode = n
				}

				imgui.TableSetColumnIndex(1)
				imgui.TextUnformatted(fmt.ctprintf("%s", e.Node_TypeName(n)))

				imgui.TableSetColumnIndex(2)
				imgui.Text(fmt.ctprintf("%v", n.layer))

				imgui.TableSetColumnIndex(3)
				imgui.Text(fmt.ctprintf("[%.1f, %.1f]", n.position.x, n.position.y))

				imgui.TableSetColumnIndex(4)
				imgui.Text(fmt.ctprintf("[%.2f, %.2f]", n.scale.x, n.scale.y))

				imgui.TableSetColumnIndex(5)
				if n.scriptInstance != nil {
					inst := cast(^e.ScriptInstance)n.scriptInstance
					imgui.TextColored(imgui.Vec4{0.95, 0.77, 0.15, 1.0}, fmt.ctprintf("%s %s", ICON_FA_CODE, inst.modulePath))
				} else {
					imgui.TextDisabled("None")
				}
			}
		}
		imgui.EndTable()
	}
}

// ----------------------------------------------------------------------------
// 5. Lua Script Inspection & References Subsystem
// ----------------------------------------------------------------------------

PreviewPanel_RenderScript :: proc(state: ^EditorState) {
	// Fallback to player_ship.lua if nothing selected
	if state.previewScriptPath == "" {
		state.previewScriptPath = strings.clone(preview_project_path(state, "scripts/player_ship.lua")) // (owned, as the other assignments)
	}

	// Quick Selector Combo for all Lua scripts in project
	scriptsDir := preview_project_path(state, "scripts")
	if os.is_dir(scriptsDir) {
		if h, err := os.open(scriptsDir); err == nil {
			fis, _ := os.read_dir(h, -1, context.temp_allocator)
			os.close(h)

			curName := filepath.base(state.previewScriptPath)
			imgui.SetNextItemWidth(260)
			if imgui.BeginCombo("##ScriptSelectCombo", fmt.ctprintf("%s %s", ICON_FA_CODE, curName)) {
				for fi in fis {
					if strings.has_suffix(fi.name, ".lua") {
						isSel := (fi.name == curName)
						if imgui.Selectable(fmt.ctprintf("%s  %s", ICON_FA_CODE, fi.name), isSel) {
							p, _ := filepath.join({scriptsDir, fi.name}, context.temp_allocator)
							state.previewScriptPath = strings.clone(p)
						}
					}
				}
				imgui.EndCombo()
			}
		}
	}

	scriptPath := state.previewScriptPath
	scriptName := filepath.base(scriptPath)

	imgui.SameLine()
	imgui.TextColored(imgui.Vec4{0.95, 0.77, 0.15, 1.0}, fmt.ctprintf("%s [Lua 5.4 Module]", scriptName))

	imgui.Separator()

	// Project names to drag into a script.
	if len(state.projectConfig.actions) > 0 {
		UI_DimText(fmt.tprintf("%s  Input actions - drag into the script:", ICON_FA_GAMEPAD))
		right := imgui.GetWindowPos().x + imgui.GetWindowContentRegionMax().x
		lastX: f32 = 0
		for a, i in state.projectConfig.actions {
			w := imgui.CalcTextSize(strings.clone_to_cstring(a.name, context.temp_allocator)).x + imgui.GetStyle().FramePadding.x * 2
			if i > 0 && lastX + 4 + w < right do imgui.SameLine(0, 4) // wrap when the row is full
			UI_Button(a.name, fmt.tprintf("preview.action:%s", a.name))
			code_item_drag(.Action, a.name)
			lastX = imgui.GetItemRectMax().x
		}
		imgui.Separator()
	}

	// 1. Exported Properties Table (inspected via engine ScriptManager)
	props, hasProps := e.Script_InspectProperties(scriptPath, state.game.gameContext.scriptManager)
	if hasProps && len(props) > 0 {
		imgui.TextColored(imgui.Vec4{0.0, 0.85, 0.75, 1.0}, fmt.ctprintf("Exported Script Properties (%d):", len(props)))
		if imgui.BeginTable("##ScriptPropsTable", 5, imgui.TableFlags_Resizable | imgui.TableFlags_RowBg | imgui.TableFlags_Borders) {
			imgui.TableSetupColumn("Property", {.WidthFixed}, 130)
			imgui.TableSetupColumn("Type", {.WidthFixed}, 80)
			imgui.TableSetupColumn("Default Value", {.WidthFixed}, 110)
			imgui.TableSetupColumn("Range [Min .. Max]", {.WidthFixed}, 140)
			imgui.TableSetupColumn("Inspector Label", {.WidthStretch})
			imgui.TableHeadersRow()

			for prop in props {
				imgui.TableNextRow()
				imgui.TableSetColumnIndex(0); imgui.Text(fmt.ctprintf("%s", prop.name))
				imgui.TableSetColumnIndex(1); imgui.Text(fmt.ctprintf("%v", prop.type))

				imgui.TableSetColumnIndex(2)
				#partial switch prop.type {
				case .Float: imgui.Text(fmt.ctprintf("%.2f", prop.defaultVal.valFloat))
				case .Int: imgui.Text(fmt.ctprintf("%d", prop.defaultVal.valInt))
				case .String: imgui.Text(fmt.ctprintf("\"%s\"", prop.defaultVal.valString))
				case .Boolean: imgui.Text(fmt.ctprintf("%t", prop.defaultVal.valBool))
				case .Vector2: imgui.Text(fmt.ctprintf("[%.1f, %.1f]", prop.defaultVal.valVec2.x, prop.defaultVal.valVec2.y))
				case: imgui.Text("-")
				}

				imgui.TableSetColumnIndex(3)
				if prop.min != 0 || prop.max != 0 {
					imgui.Text(fmt.ctprintf("[%.1f .. %.1f]", prop.min, prop.max))
				} else {
					imgui.TextDisabled("Unlimited")
				}

				imgui.TableSetColumnIndex(4)
				imgui.Text(fmt.ctprintf("%s", prop.label if prop.label != "" else prop.name))
			}
			imgui.EndTable()
		}
	}

	imgui.Spacing()

	// 2. SCRIPT REFERENCES & USAGE: Where this script is used across project scenes & components
	refs := PreviewPanel_FindScriptReferences(state, scriptName)
	defer delete(refs)

	imgui.TextColored(imgui.Vec4{0.95, 0.77, 0.15, 1.0}, fmt.ctprintf("%s  Script References & Usage Across Project (%d occurrences):", ICON_FA_MAGNIFYING_GLASS, len(refs)))

	if len(refs) == 0 {
		imgui.TextDisabled("No active nodes or scene references currently use this script.")
	} else {
		if imgui.BeginTable("##ScriptRefsTable", 5, imgui.TableFlags_Resizable | imgui.TableFlags_RowBg | imgui.TableFlags_Borders) {
			imgui.TableSetupColumn("Source / Container", {.WidthFixed}, 160)
			imgui.TableSetupColumn("Node Name", {.WidthFixed}, 150)
			imgui.TableSetupColumn("Node Type", {.WidthFixed}, 120)
			imgui.TableSetupColumn("Scope", {.WidthFixed}, 110)
			imgui.TableSetupColumn("Action", {.WidthFixed}, 120)
			imgui.TableHeadersRow()

			for ref, idx in refs {
				imgui.TableNextRow()
				imgui.TableSetColumnIndex(0)
				icon := (ref.sourceType == "Component") ? ICON_FA_CUBES : ICON_FA_CLAPPERBOARD
				imgui.Text(fmt.ctprintf("%s  %s", icon, ref.sourceName))

				imgui.TableSetColumnIndex(1)
				imgui.TextColored(imgui.Vec4{0.90, 0.95, 1.0, 1.0}, fmt.ctprintf("%s", ref.nodeName))

				imgui.TableSetColumnIndex(2)
				imgui.Text(fmt.ctprintf("%s", ref.nodeType))

				imgui.TableSetColumnIndex(3)
				if ref.isLiveNode {
					imgui.TextColored(imgui.Vec4{0.0, 0.85, 0.65, 1.0}, "Live In Viewport")
				} else {
					imgui.TextDisabled("Serialized File")
				}

				imgui.TableSetColumnIndex(4)
				if ref.isLiveNode && ref.liveNode != nil {
					imgui.PushIDInt(c.int(idx))
					if imgui.Button("Select Node") {
						state.selectedNode = ref.liveNode
						Editor_Log(state, .Info, "Selected script node: %s", ref.nodeName)
					}
					imgui.PopID()
				} else {
					imgui.TextDisabled("-")
				}
			}
			imgui.EndTable()
		}
	}

	imgui.Spacing()

	// 3. Lua Source Code Previewer with Syntax Viewer
	if bytes, err := os.read_entire_file(scriptPath, context.temp_allocator); err == nil {
		lines := strings.split_lines(string(bytes), context.temp_allocator)
		header := fmt.ctprintf("Lua Source Code (%d lines)###ScriptSourceHeader", len(lines))
		if imgui.CollapsingHeader(header, {.DefaultOpen}) {
			avail := imgui.GetContentRegionAvail()
			if imgui.BeginChild("##ScriptSourceCodeChild", imgui.Vec2{-1, min(avail.y, 220)}, {.Borders}, {}) {
				imgui.PushStyleColorImVec4(imgui.Col.Text, imgui.Vec4{0.80, 0.85, 0.92, 1.0})
				for line, lineIdx in lines {
					lineNumStr := fmt.tprintf("%3d |  ", lineIdx + 1)
					imgui.TextDisabled(strings.clone_to_cstring(lineNumStr, context.temp_allocator))
					imgui.SameLine()
					// Highlight comment lines
					trimmed := strings.trim_space(line)
					if strings.has_prefix(trimmed, "--") {
						imgui.TextColored(imgui.Vec4{0.45, 0.55, 0.65, 1.0}, strings.clone_to_cstring(line, context.temp_allocator))
					} else {
						imgui.Text(strings.clone_to_cstring(line, context.temp_allocator))
					}
				}
				imgui.PopStyleColor()
			}
			imgui.EndChild()
		}
	}
}

// Scans active scene, disk scenes, and components to find all references to a script
PreviewPanel_FindScriptReferences :: proc(state: ^EditorState, scriptBaseName: string) -> [dynamic]ScriptReference {
	refs := make([dynamic]ScriptReference, context.allocator)

	// 1. Scan Active Scene nodes
	if state.activeScene != nil && state.activeScene.manager != nil {
		for n in state.activeScene.manager.nodes {
			if n == nil do continue

			matches := false
			if n.scriptInstance != nil {
				inst := cast(^e.ScriptInstance)n.scriptInstance
				if strings.contains(inst.modulePath, scriptBaseName) {
					matches = true
				}
			} else if n.typeId == typeid_of(e.ScriptNode) {
				sn := cast(^e.ScriptNode)n
				if strings.contains(sn.scriptPath, scriptBaseName) {
					matches = true
				}
			}

			if matches {
				append(&refs, ScriptReference{
					sourceType = "Active Scene",
					sourceName = state.activeScene.name,
					nodeName   = n.name,
					nodeType   = fmt.tprintf("%v", n.typeId),
					isLiveNode = true,
					liveNode   = n,
				})
			}
		}
	}

	// 2. Scan Project Scene Files on Disk
	scenesDir := preview_project_path(state, "scenes")
	if os.is_dir(scenesDir) {
		if h, err := os.open(scenesDir); err == nil {
			fis, _ := os.read_dir(h, -1, context.temp_allocator)
			os.close(h)

			for fi in fis {
				if strings.ends_with(fi.name, ".scene.json") {
					p, _ := filepath.join({scenesDir, fi.name}, context.temp_allocator)
					if bytes, rErr := os.read_entire_file(p, context.temp_allocator); rErr == nil {
						// Fast substring check
						if strings.contains(string(bytes), scriptBaseName) {
							// Parse to find specific nodes
							if val, pErr := json.parse(bytes, allocator = context.temp_allocator); pErr == .None {
								if rootObj, isObj := val.(json.Object); isObj {
									if rNode, hasRoot := rootObj["root"].(json.Object); hasRoot {
										find_script_refs_in_json_node(rNode, fi.name, "Scene File", scriptBaseName, &refs)
									}
								}
							}
						}
					}
				}
			}
		}
	}

	// 3. Scan Components on Disk
	compDir := preview_project_path(state, "components")
	if os.is_dir(compDir) {
		if h, err := os.open(compDir); err == nil {
			fis, _ := os.read_dir(h, -1, context.temp_allocator)
			os.close(h)

			for fi in fis {
				if strings.ends_with(fi.name, ".component.json") {
					p, _ := filepath.join({compDir, fi.name}, context.temp_allocator)
					if bytes, rErr := os.read_entire_file(p, context.temp_allocator); rErr == nil {
						if strings.contains(string(bytes), scriptBaseName) {
							nameVal := fi.name
							typeVal := "Component"
							if val, pErr := json.parse(bytes, allocator = context.temp_allocator); pErr == .None {
								if compObj, isObj := val.(json.Object); isObj {
									if n, ok := compObj["name"].(json.String); ok do nameVal = n
									if t, ok := compObj["type"].(json.String); ok do typeVal = t
								}
							}
							append(&refs, ScriptReference{
								sourceType = "Component",
								sourceName = fi.name,
								nodeName   = nameVal,
								nodeType   = typeVal,
								isLiveNode = false,
								liveNode   = nil,
							})
						}
					}
				}
			}
		}
	}

	return refs
}

@(private="file")
find_script_refs_in_json_node :: proc(
	nodeObj: json.Object,
	sourceName: string,
	sourceType: string,
	scriptBaseName: string,
	refs: ^[dynamic]ScriptReference,
) {
	nodeName := "Node"
	if n, ok := nodeObj["name"].(json.String); ok do nodeName = n
	nodeType := "Node"
	if t, ok := nodeObj["type"].(json.String); ok do nodeType = t

	// Check script object
	if sObj, hasScript := nodeObj["script"].(json.Object); hasScript {
		if p, hasPath := sObj["path"].(json.String); hasPath {
			if strings.contains(p, scriptBaseName) {
				append(refs, ScriptReference{
					sourceType = sourceType,
					sourceName = sourceName,
					nodeName   = nodeName,
					nodeType   = nodeType,
					isLiveNode = false,
					liveNode   = nil,
				})
			}
		}
	}

	// Recursively check children
	if childrenArr, hasChildren := nodeObj["children"].(json.Array); hasChildren {
		for childVal in childrenArr {
			if childObj, isObj := childVal.(json.Object); isObj {
				find_script_refs_in_json_node(childObj, sourceName, sourceType, scriptBaseName, refs)
			}
		}
	}
}

// preview_texture_import: the previewed project texture's import settings,
// saved next to it (<file>.import.json, engine/asset_import.odin) and
// applied to every loaded copy at once. An older project.json entry is
// moved into the file on the first change.
@(private = "file")
preview_texture_import :: proc(state: ^EditorState) {
	root := strings.concatenate({state.projectPath, "/"}, context.temp_allocator)
	if state.projectPath == "" || !strings.has_prefix(state.previewTexturePath, root) do return
	rel := state.previewTexturePath[len(root):]
	rm := &state.game.resourceManager
	imp := Editor_AssetImport(state, state.previewTexturePath)
	changed := false
	UI_DimText("Import")
	same_or_wrap(96)
	imgui.SetNextItemWidth(96)
	if f, ok := UI_Combo("preview.import.filter", int(imp.filter), {"Point", "Bilinear", "Trilinear"}); ok {
		imp.filter = e.Texture_Filter(f)
		changed = true
	}
	UI_Tooltip("Filtering: Point keeps pixel art crisp; Bilinear / Trilinear smooth scaled images (Trilinear uses mipmaps)")
	same_or_wrap(84)
	imgui.SetNextItemWidth(84)
	if w, ok := UI_Combo("preview.import.wrap", int(imp.wrap), {"Repeat", "Clamp"}); ok {
		imp.wrap = e.Texture_Wrap(w)
		changed = true
	}
	UI_Tooltip("Wrap: Repeat tiles the texture past its edges (parallax, shaders); Clamp stretches the edge pixels")
	same_or_wrap(90)
	if imgui.Checkbox("Mipmaps##imp", &imp.mipmaps) do changed = true
	Drive_Item("preview.import.mipmaps")
	UI_Tooltip("Smaller copies for drawing the texture far smaller than its size")
	same_or_wrap(110)
	imgui.SetNextItemWidth(110)
	if c, ok := UI_Combo("preview.import.compress", int(imp.compress), {"Export: Keep", "Export: QOI"}); ok {
		imp.compress = e.Texture_Compress(c)
		changed = true
	}
	UI_Tooltip("How export stores it: Keep the file as it is, or QOI - decodes several times faster than PNG (faster loading), usually a bigger file")
	same_or_wrap(70)
	if imgui.Checkbox("Atlas##imp", &imp.atlas) do changed = true
	Drive_Item("preview.import.atlas")
	UI_Tooltip("Pack it into a sprite atlas on export: sprites sharing an atlas page draw in one batch (faster with many sprites). Not for textures with mipmaps / Trilinear, or ones a shader samples as a whole (those get their own copy)")
	// Normal map (#274): <image>_n.png found by itself, none, or another image.
	same_or_wrap(150)
	{
		choices := make([dynamic]string, context.temp_allocator)
		append(&choices, "Normal: Auto (_n)", "Normal: None")
		cur := 0 if imp.normalMap == "" else 1 if imp.normalMap == "none" else -1
		for t in Editor_ListProjectFiles(state, "", TEXTURE_EXTS) do if t != rel && (strings.contains(t, "_n.") || strings.contains(strings.to_lower(t, context.temp_allocator), "normal")) {
			if t == imp.normalMap do cur = len(choices)
			append(&choices, fmt.tprintf("Normal: %s", t))
		}
		if cur < 0 {
			cur = len(choices)
			append(&choices, fmt.tprintf("Normal: %s", imp.normalMap))
		}
		imgui.SetNextItemWidth(150)
		if c, ok := UI_Combo("preview.import.normal", cur, choices[:]); ok {
			switch c {
			case 0: imp.normalMap = ""
			case 1: imp.normalMap = "none"
			case: imp.normalMap = strings.clone(choices[c][len("Normal: "):], context.temp_allocator)
			}
			changed = true
			e.Lit_ForgetAll()
		}
		found, _ := e.Lit_NormalPathFor(rm, state.previewTexturePath)
		UI_Tooltip(fmt.tprintf("The normal map lights shade it by (2D lighting). Auto: %s next to it. Right-click the image > Generate Normal Map makes one.%s", filepath.base(found) if found != "" else "<image>_n.png", "" if found != "" else " (none found)"))
		same_or_wrap(100)
		if imgui.Checkbox("Green Down##imp", &imp.normalGreenDown) {
			changed = true
			e.Lit_ForgetAll()
		}
		Drive_Item("preview.import.green-down")
		UI_Tooltip("The normal map's green points down (DirectX style, e.g. from some 3D tools); off: up (OpenGL style, most 2D tools)")
	}
	// Slicing preset (the Sprite Sheet Slicer starts from it; Save Preset there).
	if imp.slice.grid != {} {
		same_or_wrap(110)
		if imp.slice.cellSize != {} do UI_DimText(fmt.tprintf("Slice %d x %d px cells (%d x %d)", imp.slice.cellSize.x, imp.slice.cellSize.y, imp.slice.grid.x, imp.slice.grid.y))
		else do UI_DimText(fmt.tprintf("Slice %d x %d", imp.slice.grid.x, imp.slice.grid.y))
		UI_Tooltip("The slicing preset the Sprite Sheet Slicer opens this sheet with (Save Preset in the slicer)")
		imgui.SameLine()
		if UI_IconButton(ICON_FA_XMARK, "preview.import.slice.clear", "Forget the slicing preset", size = 22) {
			imp.slice = {}
			changed = true
		}
	}
	if changed {
		preview_save_import(state, state.previewTexturePath, rel, imp)
		e.ResourceManager_ReapplyImports(rm)
		e.Texture_ApplyImport(&state.previewTexture, e.Texture_ImportFor(rm, rel))
		Editor_Log(state, .Info, "Import settings of %s: %v filter, %v wrap%s%s%s", rel, imp.filter, imp.wrap, ", mipmaps" if imp.mipmaps else "", ", QOI on export" if imp.compress == .QOI else "", ", atlas" if imp.atlas else "")
	}
}

// Editor_AssetImport: an asset's import settings to edit - its file, or for
// a texture without one an older project.json entry.
Editor_AssetImport :: proc(state: ^EditorState, full: string) -> e.Asset_Import {
	rm := &state.game.resourceManager
	imp := e.Asset_ImportGet(rm, full)^
	if !imp.found {
		legacy := e.Texture_ImportFor(rm, e.Asset_RelPath(rm, full))
		imp.filter, imp.wrap, imp.mipmaps = legacy.filter, legacy.wrap, legacy.mipmaps
	}
	return imp
}

// same_or_wrap: the next item on this line if `w` px fit, else on the next.
@(private = "file")
same_or_wrap :: proc(w: f32) {
	imgui.SameLine()
	if imgui.GetContentRegionAvail().x < w do imgui.NewLine()
}

// preview_save_import writes an asset's import settings file (and drops an
// older project.json texture entry for it).
preview_save_import :: proc(state: ^EditorState, full, rel: string, imp: e.Asset_Import) {
	rm := &state.game.resourceManager
	legacy := false
	for t in state.projectConfig.textureImport do if t.path == rel do legacy = true
	if legacy {
		e.ProjectConfig_SetTextureImport(&state.projectConfig, {path = rel}) // (the defaults: removes it)
		e.Project_SaveConfigToFile(state.projectPath, &state.projectConfig)
		e.Texture_ImportsSet(state.projectConfig.textureImport[:])
	}
	if !e.Asset_ImportSave(rm, full, imp) do Editor_Log(state, .Error, "Could not write %s%s", rel, e.IMPORT_SUFFIX)
	Editor_InvalidateProjectFiles()
}

// preview_audio_import: an audio file's import gain and default bus.
@(private = "file")
preview_audio_import :: proc(state: ^EditorState) {
	root := strings.concatenate({state.projectPath, "/"}, context.temp_allocator)
	if state.projectPath == "" || !strings.has_prefix(state.previewSoundPath, root) do return
	rel := state.previewSoundPath[len(root):]
	rm := &state.game.resourceManager
	imp := e.Asset_ImportGet(rm, state.previewSoundPath)^
	changed := false
	UI_DimText("Import")
	imgui.SameLine()
	half := max((imgui.GetContentRegionAvail().x - imgui.GetStyle().ItemSpacing.x) * 0.5, 60)
	imgui.SetNextItemWidth(half)
	// (edited in a buffer: saved when the drag ends, not every frame)
	@(static) gainBuf: f32
	@(static) gainActive: bool
	if !gainActive do gainBuf = imp.gainDb
	imgui.SliderFloat("##imp_gain", &gainBuf, -24, 12, "Gain %+.1f dB")
	gainActive = imgui.IsItemActive()
	if imgui.IsItemDeactivatedAfterEdit() {
		imp.gainDb = gainBuf
		changed = true
	}
	Drive_Item("preview.import.gain")
	UI_Tooltip("Louder / quieter wherever it plays (applied when loaded) - even out sounds recorded at different levels")
	imgui.SameLine()
	buses := e.Mixer_Buses()
	names := make([dynamic]string, context.temp_allocator)
	append(&names, "Default bus")
	cur := 0
	for b, i in buses {
		append(&names, b.name)
		if b.name == imp.bus do cur = i + 1
	}
	imgui.SetNextItemWidth(-1)
	if b, ok := UI_Combo("preview.import.bus", cur, names[:]); ok {
		imp.bus = names[b] if b > 0 else ""
		changed = true
	}
	UI_Tooltip("The mixer bus it plays into when the node or the script names none (else SFX for sounds, Music for music)")
	if changed {
		preview_save_import(state, state.previewSoundPath, rel, imp)
		Editor_Log(state, .Info, "Import settings of %s: gain %+.1f dB%s", rel, imp.gainDb, fmt.tprintf(", bus %s", imp.bus) if imp.bus != "" else "")
	}
}

// preview_project_path: a path in the open project (the previews' defaults
// and their folder lists: the demo project's names when it's open).
@(private = "file")
preview_project_path :: proc(state: ^EditorState, rel: string) -> string {
	p, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	return p
}


// PreviewPanel_Shutdown cleans up any assets and buffers held by the preview panel.
PreviewPanel_Shutdown :: proc(state: ^EditorState) {
	if state == nil do return
	if state.previewTextureLoaded {
		rl.UnloadTexture(state.previewTexture)
		state.previewTextureLoaded = false
	}
	delete(state.previewTexturePath)
	state.previewTexturePath = ""

	if state.previewSoundLoaded {
		if state.previewAudioPlaying {
			rl.StopSound(state.previewSound)
			state.previewAudioPlaying = false
		}
		rl.UnloadSound(state.previewSound)
		state.previewSoundLoaded = false
	}
	delete(state.previewSoundPath)
	state.previewSoundPath = ""

	for &tex in state.previewAnimFrames {
		rl.UnloadTexture(tex)
	}
	clear(&state.previewAnimFrames)
	clear(&state.previewAnimPaths)
	delete(state.previewAnimLoadedPath)
	state.previewAnimLoadedPath = ""

	delete(state.previewScenePath)
	state.previewScenePath = ""
	delete(state.previewScriptPath)
	state.previewScriptPath = ""
}
