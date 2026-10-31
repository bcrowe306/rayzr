package editor

import "core:c"
import "core:fmt"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"
import rl "vendor:raylib"

// ============================================================================
// The Tile Animation window (#275): the frames of the tile picked in the Tile
// Map tab - each a tile and how long it shows - and Desync. Saved in the
// tileset's sidecar with its terrains (Editor_SaveTerrains); every TileMap
// on the tileset in the scene plays it at once.
//
// While "Add frames" is on, clicking tiles in the Tile Map tab adds them as
// frames (TileAnimEditor_TakeClick) instead of picking a brush.
// ============================================================================

@(private = "file")
animWin: struct {
	open:   bool,
	image:  string, // the tileset image (heap)
	tile:   i32,    // the tile the animation starts on
	adding: bool,   // clicks in the tile palette add frames
	allMs:  c.int,  // "set every frame to" value
}

// TileAnimEditor_Open: the animation starting on `tile` of a tileset (made
// with that one frame when it has none yet).
TileAnimEditor_Open :: proc(state: ^EditorState, image: string, tile: i32) {
	delete(animWin.image)
	animWin.image = strings.clone(image)
	animWin.tile = tile
	animWin.open = true
	animWin.allMs = 120
	ts := Editor_Terrains(state, image)
	if ts != nil && e.Terrains_AnimationOf(ts, tile) < 0 {
		a := e.Tile_Anim{make([dynamic]i32, ts.allocator), make([dynamic]f32, ts.allocator), false}
		append(&a.frames, tile)
		append(&a.durations, 0.12)
		append(&ts.animations, a)
		animWin.adding = true // (the next clicks add its frames)
	}
	imgui.SetWindowFocusStr("Tile Animation###TileAnimation")
}

TileAnimEditor_Shutdown :: proc() {
	delete(animWin.image)
	animWin = {}
}

// TileAnimEditor_TakeClick: a tile clicked in the Tile Map tab - a frame
// while adding (true: taken, not a brush pick).
TileAnimEditor_TakeClick :: proc(state: ^EditorState, image: string, tile: i32) -> bool {
	if !animWin.open || !animWin.adding || image != animWin.image do return false
	ts := Editor_Terrains(state, image)
	i := e.Terrains_AnimationOf(ts, animWin.tile)
	if i < 0 do return false
	a := &ts.animations[i]
	append(&a.frames, tile)
	append(&a.durations, a.durations[len(a.durations) - 1] if len(a.durations) > 0 else 0.12)
	tile_anim_save(state)
	return true
}

// TileAnimEditor_Badge: the tile starts an animation (the palette marks it).
TileAnimEditor_Badge :: proc(state: ^EditorState, image: string, tile: i32) -> bool {
	ts := Editor_Terrains(state, image)
	if i := e.Terrains_AnimationOf(ts, tile); i >= 0 do return len(ts.animations[i].frames) > 1
	return false
}

// tile_anim_save writes the sidecar and gives the scene's maps on the
// tileset the new animations.
@(private = "file")
tile_anim_save :: proc(state: ^EditorState) {
	ts := Editor_Terrains(state, animWin.image)
	if ts == nil do return
	Editor_SaveTerrains(state, animWin.image)
	if state.activeScene == nil || state.activeScene.manager == nil do return
	for n in state.activeScene.manager.nodes {
		if n == nil || n.typeId != e.TileMapNode do continue
		tm := cast(^e.TileMapNode)n
		if tm.tilesetPath == animWin.image do e.TileMapNode_SetAnimations(tm, ts.animations[:])
	}
}

TileAnimEditor_Render :: proc(state: ^EditorState) {
	if !animWin.open do return
	ts := Editor_Terrains(state, animWin.image)
	i := e.Terrains_AnimationOf(ts, animWin.tile)
	if ts == nil || i < 0 {
		animWin.open = false
		return
	}
	a := &ts.animations[i]
	vp := imgui.GetMainViewport()
	imgui.SetNextWindowPos(vp.WorkPos + vp.WorkSize * 0.5, .FirstUseEver, {0.5, 0.5})
	imgui.SetNextWindowSize({460, 420}, .FirstUseEver)
	open := true
	visible := imgui.Begin(fmt.ctprintf("%s  Tile Animation: tile %d###TileAnimation", ICON_FA_FILM, animWin.tile), &open, {})
	defer imgui.End()
	if !open {
		animWin.open = false
		animWin.adding = false
		// (One frame isn't an animation: dropped.)
		if len(a.frames) < 2 {
			delete(a.frames)
			delete(a.durations)
			ordered_remove(&ts.animations, i)
			tile_anim_save(state)
		}
	}
	if !visible do return
	Drive_Window("tile-anim")
	UI_DimTextWrapped("Wherever this tile is painted it plays these frames, on every Tile Map using the tileset. Turn on Add Frames, then click tiles in the Tile Map tab.")
	if imgui.Checkbox("Add Frames", &animWin.adding) {}
	Drive_Item("tile-anim.adding")
	UI_Tooltip("While on, clicking a tile in the Tile Map tab adds it as the next frame (instead of picking it to paint with)")
	imgui.SameLine(0, UI_SPACE * 2)
	if imgui.Checkbox("Desync", &a.desync) do tile_anim_save(state)
	Drive_Item("tile-anim.desync")
	UI_Tooltip("Each painted copy starts at its own point in the animation, so neighbours don't change in unison (grass, candles). Off: all copies in step (water)")
	changed := false
	// Every frame at once.
	imgui.SetNextItemWidth(90)
	imgui.DragInt("##allms", &animWin.allMs, 1, 10, 5000, "%d ms")
	imgui.SameLine(0, 4)
	if imgui.Button("Set Every Frame") {
		for &d in a.durations do d = f32(animWin.allMs) / 1000
		changed = true
	}
	Drive_Item("tile-anim.set-all")
	imgui.Separator()
	// The frames.
	tex := tile_anim_texture(state)
	remove := -1
	for f, k in a.frames {
		imgui.PushIDInt(c.int(k))
		if tex != nil {
			p := imgui.GetCursorScreenPos()
			terrain_tile_image(imgui.GetWindowDrawList(), tex, tile_anim_tile_size(state), f, p, {28, 28})
			imgui.Dummy({28, 28})
			imgui.SameLine(0, 6)
		}
		imgui.AlignTextToFramePadding()
		UI_DimText(fmt.tprintf("%d. tile %d", k + 1, f))
		imgui.SameLine(140)
		ms := c.int(a.durations[k] * 1000 + 0.5)
		imgui.SetNextItemWidth(110)
		if imgui.DragInt("##ms", &ms, 1, 10, 5000, "%d ms") {
			a.durations[k] = f32(max(ms, 10)) / 1000
			changed = true
		}
		Drive_Item(fmt.tprintf("tile-anim.ms:%d", k))
		if k > 0 {
			imgui.SameLine(0, 6)
			if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("tile-anim.remove:%d", k), "Remove this frame", size = 24) do remove = k
		}
		imgui.PopID()
	}
	if remove > 0 {
		ordered_remove(&a.frames, remove)
		ordered_remove(&a.durations, remove)
		changed = true
	}
	imgui.Separator()
	UI_DimText(fmt.tprintf("%d frames, %.2f s a loop", len(a.frames), e.Tile_AnimTotal(a)))
	if UI_Button(fmt.tprintf("%s  Remove Animation", ICON_FA_TRASH), "tile-anim.delete") {
		delete(a.frames)
		delete(a.durations)
		ordered_remove(&ts.animations, i)
		animWin.open = false
		changed = true
	}
	if changed do tile_anim_save(state)
}

// (The selected Tile Map's tileset texture and tile size, for the frames' pictures.)
@(private = "file")
tile_anim_texture :: proc(state: ^EditorState) -> ^rl.Texture2D {
	tm := selected_tilemap(state)
	if tm == nil || tm.tileset == nil || tm.tilesetPath != animWin.image do return nil
	return &tm.tileset.texture
}

@(private = "file")
tile_anim_tile_size :: proc(state: ^EditorState) -> [2]int {
	tm := selected_tilemap(state)
	return tm.tileSize if tm != nil else {16, 16}
}
