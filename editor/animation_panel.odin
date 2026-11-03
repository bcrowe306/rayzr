package editor

import "core:c"
import "core:fmt"
import "core:path/filepath"
import "core:math"
import "core:math/rand"
import "core:slice"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Animation timeline (bottom panel "Animation" tab) for AnimationPlayerNode.
//
//   toolbar   animation picker, new, play/stop preview, loop, reverse, the
//             animation's FPS, default-on-load, frame; range (start / end),
//             copy / paste / delete the selected frames
//   frames    every source frame (frames outside the range dimmed; the range
//             handles in the header drag); click selects (Shift: a run,
//             Cmd: toggle) and scrubs; drag to reorder; drop textures from
//             Assets to append; right-click: copy, paste, delete, set range;
//             Delete / Cmd+C / Cmd+V while the panel has focus
//   tracks    keyframed properties (engine/animation_tracks.odin): a row per
//             target.property with diamonds on keyed frames. "Key" records
//             the property's current value at the playhead; right-click a
//             diamond to delete it; "Add Track" picks node + property.
//
// Scrubbing and previewing apply the tracks to the scene; Stop (or leaving
// the node) puts the animated properties back, so previews never end up
// saved into the scene.
// ============================================================================

CELL_W :: f32(34) // a frame column at zoom 1
LABEL_W :: f32(230)
GROUP_H :: f32(20) // a node's row above its tracks

// cellW: a frame column at the timeline's zoom.
@(private = "file")
cellW: f32 = CELL_W
ROW_H :: f32(30)
THUMB_H :: f32(40)

@(private = "file")
Preview_Value :: struct {
	node:     ^e.Node,
	property: string,
	value:    [4]f32,
}

@(private = "file")
Anim_Panel :: struct {
	node:       ^e.AnimationPlayerNode, // node the saved values belong to
	saved:      [dynamic]Preview_Value,
	playing:    bool,
	lastTick:   time.Tick,
	accum:      f32,
	accumTime:  f32,
	trackNode:  ^e.Node, // Add Track dialog
	trackOpen:  bool,
	newName:    [64]u8,
	// Selected source frames (of selAnim) and the last one clicked.
	sel:        [dynamic]int,
	selAnim:    ^e.Animation,
	anchor:     int,
	rangeDrag:  int, // 1: dragging the range start handle, 2: the end
	// The preview at the right: loops the range by itself (paused: shows
	// the frame scrubbed to).
	miniPaused: bool,
	miniAccum:  f32,
	miniTick:   time.Tick,
	selectedTrack: int,
	zoom:          f32, // timeline zoom (0: 1)
	rulerSeconds:  bool, // the ruler in seconds (else frames)
	collapsed:     map[string]bool, // node groups folded (by target path)
	pasteKeys:     bool, // Cmd+V pastes keys (copied last), else frames
	// The player edited while other nodes are selected (to key them): its
	// path in pinScene (paths survive undo, which rebuilds nodes).
	pinPath:       string,
	pinScene:      ^e.Scene,
	graph:         bool, // the value graph instead of the track rows (#180)
}

PREVIEW_W :: f32(200)

// The copied frames (Copy / Paste in the timeline).
frameClip: e.Frame_Clip

// animTimelineFocused: the Animation tab has focus (its keys aren't the
// scene's: Delete, Cmd+C / V act on frames).
animTimelineFocused: bool

@(private = "file")
panel: Anim_Panel

// preview_capture remembers the animated properties' values (once per
// preview session) so they can be restored.
@(private = "file")
preview_capture :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode) {
	if panel.node == apn && len(panel.saved) > 0 do return
	preview_restore(state)
	panel.node = apn
	anim := e.AnimationPlayerNode_GetAnimation(apn)
	if anim == nil do return
	mgr := state.activeScene.manager
	for tr in anim.tracks {
		target: ^e.Node = apn
		if tr.target != "." && tr.target != "" do target = e.Node_ResolvePath(mgr, apn, tr.target)
		if target == nil do continue
		p, ok := e.Track_FindProperty(target, tr.property)
		if !ok do continue
		v, vok := e.Property_GetTrackValue(p)
		if !vok do continue
		append(&panel.saved, Preview_Value{target, strings.clone(tr.property), v})
	}
}

// preview_restore puts animated properties back to their pre-preview values.
@(private = "file")
preview_restore :: proc(state: ^EditorState) {
	for pv in panel.saved {
		if e.Node_IsAlive(pv.node) {
			if p, ok := e.Track_FindProperty(pv.node, pv.property); ok do e.Property_SetTrackValue(p, pv.value)
		}
		delete(pv.property)
	}
	clear(&panel.saved)
	if panel.node != nil && e.Node_IsAlive(panel.node) {
		if a := e.AnimationPlayerNode_GetAnimation(panel.node); a != nil do panel.node.currentFrame = a.startFrame
	}
	panel.playing = false
	panel.node = nil
}

// AnimationPanel_Shutdown frees the panel's preview state.
AnimationPanel_Shutdown :: proc() {
	for pv in panel.saved do delete(pv.property)
	delete(panel.saved)
	for k in panel.collapsed do delete(k)
	delete(panel.collapsed)
	AnimKeys_Shutdown()
	AutoKey_Shutdown()
	AnimGraph_Shutdown()
	delete(panel.pinPath)
}

@(private = "file")
scrub :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation, frame: int) {
	preview_capture(state, apn)
	length := e.Animation_Length(anim, apn)
	f := clamp(frame, 0, length - 1)
	apn.currentFrame = anim.startFrame + min(f, max(anim->frameCount() - 1, 0))
	apn.time = e.Animation_FrameTime(apn, anim, f32(f))
	e.AnimationPlayerNode_ApplyTracks(apn, apn.time)
	panel.accum = f32(f)
}

// playhead: the timeline column the playhead is on - the frame shown, or,
// past the frames (tracks longer than them), the time scrubbed to.
@(private = "file")
playhead :: proc(apn: ^e.AnimationPlayerNode, anim: ^e.Animation) -> int {
	f := apn.currentFrame - anim.startFrame
	t := int(math.round(e.Animation_TimeFrame(apn, anim, apn.time)))
	if t > f && f == max(anim->frameCount() - 1, 0) do return t
	return f
}

@(private = "file")
selected :: proc(f: int) -> bool {
	for s in panel.sel do if s == f do return true
	return false
}

// frame_select: a click on source frame f (Shift extends, Cmd toggles).
@(private = "file")
frame_select :: proc(f: int) {
	io := imgui.GetIO()
	if io.KeyShift && len(panel.sel) > 0 {
		clear(&panel.sel)
		for i in min(panel.anchor, f) ..= max(panel.anchor, f) do append(&panel.sel, i)
		return
	}
	if io.KeySuper || io.KeyCtrl {
		for s, i in panel.sel do if s == f {ordered_remove(&panel.sel, i); return}
		append(&panel.sel, f)
	} else {
		clear(&panel.sel)
		append(&panel.sel, f)
	}
	panel.anchor = f
}

@(private = "file")
frames_delete :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation, frames: []int) {
	if len(frames) == 0 do return
	Editor_RecordUndo(state, "Delete frames")
	n := e.Animation_RemoveFrames(apn, anim, frames, &state.game.resourceManager)
	clear(&panel.sel)
	Editor_Log(state, .Info, "Deleted %d frame(s)", n)
}

@(private = "file")
frames_copy :: proc(state: ^EditorState, anim: ^e.Animation, frames: []int) {
	if len(frames) == 0 do return
	n := e.Animation_CopyFrames(anim, frames, &frameClip)
	panel.pasteKeys = false
	Editor_Log(state, .Info, "Copied %d frame(s)", n)
}

// frames_paste: after the last selected frame (else at the end).
@(private = "file")
frames_paste :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation) {
	if e.Frame_ClipEmpty(&frameClip) do return
	at := e.Animation_SourceCount(anim)
	if len(panel.sel) > 0 {
		at = 0
		for s in panel.sel do at = max(at, s + 1)
	}
	Editor_RecordUndo(state, "Paste frames")
	n := e.Animation_PasteFrames(apn, anim, at, &frameClip, &state.game.resourceManager)
	if n == 0 {
		Editor_Log(state, .Warn, "Those frames don't fit this animation (images go into frame animations, cells into the same sprite sheet)")
		return
	}
	clear(&panel.sel)
	for i in at ..< at + n do append(&panel.sel, i)
	Editor_Log(state, .Info, "Pasted %d frame(s)", n)
}

// paste_any: the keys copied last at the playhead, else the frames.
@(private = "file")
paste_any :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation) {
	if panel.pasteKeys && AnimKeys_CanPaste() do AnimKeys_Paste(state, apn, anim, e.Animation_FrameTime(apn, anim, f32(playhead(apn, anim))), panel.selectedTrack)
	else if !e.Frame_ClipEmpty(&frameClip) do frames_paste(state, apn, anim)
}

// ruler_step: label every n-th column, n a round number leaving room for
// the label.
@(private = "file")
ruler_step :: proc(cell, labelW: f32) -> int {
	for n in ([?]int{1, 2, 5, 10, 20, 50, 100, 200, 500}) do if f32(n) * cell >= labelW do return n
	return 1000
}

// group_toggle folds / unfolds a node's tracks.
@(private = "file")
group_toggle :: proc(target: string) {
	for k in panel.collapsed do if k == target {
		delete_key(&panel.collapsed, k)
		delete(k)
		return
	}
	panel.collapsed[strings.clone(target)] = true
}

AnimationPanel_Zoom :: proc() -> f32 {return panel.zoom if panel.zoom > 0 else 1}

// AnimationPanel_PlayheadTime: the playhead's time (seconds).
AnimationPanel_PlayheadTime :: proc(apn: ^e.AnimationPlayerNode, anim: ^e.Animation) -> f32 {
	return e.Animation_FrameTime(apn, anim, f32(playhead(apn, anim)))
}

// AnimationPanel_ScrubTo moves the playhead to the frame at `at` (seconds).
AnimationPanel_ScrubTo :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation, at: f32) {
	panel.playing = false
	scrub(state, apn, anim, int(math.round(e.Animation_TimeFrame(apn, anim, at))))
	animAutoKey.valid = false // (the scrub's values aren't edits)
}

// panel_player: the selected AnimationPlayer (pinned: it stays while other
// nodes are selected, so their properties can be keyed into it).
@(private = "file")
panel_player :: proc(state: ^EditorState) -> ^e.AnimationPlayerNode {
	node := state.selectedNode
	if node != nil && node.typeId == e.AnimationPlayerNode {
		path := Editor_NodePath(state, node)
		if panel.pinPath != path || panel.pinScene != state.activeScene {
			delete(panel.pinPath)
			panel.pinPath = strings.clone(path)
			panel.pinScene = state.activeScene
		}
		return cast(^e.AnimationPlayerNode)node
	}
	if panel.pinPath == "" || panel.pinScene != state.activeScene || state.activeScene == nil do return nil
	if n := Editor_NodeAtPath(state, panel.pinPath); n != nil && n.typeId == e.AnimationPlayerNode do return cast(^e.AnimationPlayerNode)n
	return nil
}

// AnimationPanel_Rescrub shows the scene at the playhead again (after keys
// change).
AnimationPanel_Rescrub :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation) {
	scrub(state, apn, anim, playhead(apn, anim))
}

AnimationPanel_SelectTrack :: proc(i: int) {panel.selectedTrack = i}

// track_has_panel: tracks with settings right of the timeline.
@(private = "file")
track_has_panel :: proc(kind: e.Track_Kind) -> bool {
	#partial switch kind {
	case .Audio, .Method, .EmitParticles, .InstantiateComponent, .SetEnabled: return true
	}
	return false
}

// side_panel: right of the timeline - a sound / script-call / event track's
// settings, else the selected keys' inspector, else the preview.
@(private = "file")
side_panel :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation, size: [2]f32) {
	if panel.selectedTrack >= 0 && panel.selectedTrack < len(anim.tracks) {
		tr := &anim.tracks[panel.selectedTrack]
		if tr.kind == .Audio {
			anim_sound_settings_panel(state, apn, anim, tr, size)
			return
		}
		if tr.kind == .Method {
			anim_method_settings_panel(state, apn, anim, tr, size)
			return
		}
		if track_has_panel(tr.kind) {
			anim_event_settings_panel(state, apn, anim, tr, size)
			return
		}
	}
	if len(animKeys.sel) > 0 do AnimKeys_InspectorPanel(state, apn, anim, size)
	else do anim_preview(state, apn, anim, size)
}

@(private = "file")
draw_frame_thumb :: proc(dl: ^imgui.DrawList, anim: ^e.Animation, frame: int, mn, mx: [2]f32) {
	tex: ^rl.Texture2D
	uv0, uv1 := [2]f32{0, 0}, [2]f32{1, 1}
	isEmpty := false
	if anim.renderFrame == e.SSA_RenderFrame {
		// `frame` is a source frame: a cell of the sheet.
		ssa := cast(^e.SpriteSheetAnimation)anim
		if ssa.spriteSheet == nil || ssa.grid.x <= 0 || ssa.grid.y <= 0 do return
		cell := ssa.cells[frame] if frame >= 0 && frame < len(ssa.cells) else frame
		if cell < 0 {
			isEmpty = true
		} else {
			tex = &ssa.spriteSheet.texture
			size := [2]f32{f32(tex.width), f32(tex.height)}
			r := e.SpriteSheet_CellRect(size, ssa.grid, ssa.margin, ssa.spacing, cell, ssa.cellSize)
			uv0 = {r.x / max(size.x, 1), r.y / max(size.y, 1)}
			uv1 = uv0 + {r.width / max(size.x, 1), r.height / max(size.y, 1)}
		}
	} else {
		fa := cast(^e.FrameAnimation)anim
		if frame < 0 || frame >= len(fa.frames) do return
		if fa.frames[frame] == nil {
			isEmpty = true
		} else {
			tex = &fa.frames[frame].texture
		}
	}
	if isEmpty {
		imgui.DrawList_AddRect(dl, mn + {2, 2}, mx - {2, 2}, col_u32(UI_TEXT_DIM), 2)
		// (A frame cell is too narrow for a word: a centred icon.)
		label := strings.clone_to_cstring(ICON_FA_MINUS, context.temp_allocator)
		ts := imgui.CalcTextSize(label)
		imgui.DrawList_AddText(dl, (mn + mx) * 0.5 - ts * 0.5, col_u32(UI_TEXT_DIM), label)
		return
	}
	if tex == nil || tex.id == 0 do return
	// Fit, keeping the aspect ratio.
	w := f32(tex.width) * (uv1.x - uv0.x)
	h := f32(tex.height) * (uv1.y - uv0.y)
	boxW, boxH := mx.x - mn.x - 4, mx.y - mn.y - 4
	s := min(boxW / max(w, 1), boxH / max(h, 1))
	dw, dh := w * s, h * s
	p := [2]f32{mn.x + (mx.x - mn.x - dw) * 0.5, mn.y + (mx.y - mn.y - dh) * 0.5}
	imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)tex, p, {p.x + dw, p.y + dh}, uv0, uv1)
}

// The key whose context menu is open.
@(private = "file")
keyMenu: struct {
	track: int,
	time:  f32, // the key's time (seconds)
} = {track = -1}

// key_frame: the frame column a key sits on (keys are timed in seconds).
@(private = "file")
key_frame :: proc(apn: ^e.AnimationPlayerNode, anim: ^e.Animation, k: e.Track_Key) -> int {
	return int(math.round(e.Animation_TimeFrame(apn, anim, k.time)))
}

// ease_preview: a tooltip with the curve's shape.
@(private = "file")
ease_preview :: proc(ease: e.Ease) {
	if !imgui.BeginTooltip() do return
	defer imgui.EndTooltip()
	size := imgui.Vec2{120, 70}
	o := imgui.GetCursorScreenPos()
	imgui.Dummy(size)
	dl := imgui.GetWindowDrawList()
	imgui.DrawList_AddRectFilled(dl, o, o + size, col_u32(UI_BG_APP), 3)
	prev: imgui.Vec2
	for i in 0 ..= 40 {
		t := f32(i) / 40
		v := e.Ease_Apply(ease, t)
		p := imgui.Vec2{o.x + 6 + t * (size.x - 12), o.y + size.y - 10 - v * (size.y - 20)}
		if i > 0 do imgui.DrawList_AddLine(dl, prev, p, col_u32(UI_ACCENT), 2)
		prev = p
	}
}

AnimationPanel_Render :: proc(state: ^EditorState) {
	// Auto-key: changes since the last frame become keys; then the tab; then
	// the values the next changes are measured from.
	apn := panel_player(state)
	anim := e.AnimationPlayerNode_GetAnimation(apn) if apn != nil else nil
	if anim != nil && !panel.playing do AutoKey_Record(state, apn, anim, AnimationPanel_PlayheadTime(apn, anim))
	animation_panel(state, apn)
	apn = panel_player(state)
	anim = e.AnimationPlayerNode_GetAnimation(apn) if apn != nil else nil
	if anim != nil do AnimKeyTarget_Set(state, apn, anim)
	if panel.playing do animAutoKey.valid = false
	else do AutoKey_Snapshot(state, apn, anim)
}

@(private = "file")
animation_panel :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode) {
	animTimelineFocused = false
	if panel.node != nil && panel.node != apn do preview_restore(state)
	if apn == nil {
		imgui.Dummy({0, 8})
		UI_DimText("   Select an AnimationPlayer node to edit its animations and keyframes.")
		return
	}
	ctx := &state.game.gameContext
	_ = ctx

	// --- toolbar ---
	imgui.Dummy({0, 2})
	// Another node selected: the player stays (pinned) to key it.
	if state.selectedNode != apn {
		if UI_Button(fmt.tprintf("%s  %s", ICON_FA_THUMBTACK, apn.name), "anim.pinned") do Editor_SelectNode(state, apn, false)
		UI_Tooltip("Editing this AnimationPlayer while other nodes are selected - key their properties with the Inspector's diamonds (click: select it)")
		imgui.SameLine(0, 2)
		if UI_IconButton(ICON_FA_XMARK, "anim.unpin", "Stop editing this AnimationPlayer", size = 26) {
			preview_restore(state)
			delete(panel.pinPath)
			panel.pinPath = ""
			return
		}
		imgui.SameLine(0, UI_SPACE)
	}
	names := make([dynamic]string, context.temp_allocator)
	for a in apn.animations do append(&names, a.name)
	imgui.SetNextItemWidth(170)
	if idx, changed := UI_Combo("anim.select", apn.animationIndex, names[:]); changed {
		preview_restore(state)
		Editor_RecordUndo(state, "Set animation")
		e.AnimationPlayerNode_SetAnimationIndex(apn, idx)
		if a := e.AnimationPlayerNode_GetAnimation(apn); a != nil do apn.currentFrame = a.startFrame
	}
	imgui.SameLine(0, 4)
	if UI_IconButton(ICON_FA_PLUS, "anim.new", "New animation", size = 26) {
		Editor_RecordUndo(state, "New animation")
		name := fmt.tprintf("anim_%d", len(apn.animations) + 1)
		e.AnimationPlayerNode_AddFrameAnimation(apn, &state.game.resourceManager, name, nil)
		e.AnimationPlayerNode_SetAnimationIndex(apn, len(apn.animations) - 1)
	}
	// More ways to make one: a folder of frames, a sprite sheet, the slicer.
	imgui.SameLine(0, 0)
	if UI_IconButton(ICON_FA_CHEVRON_DOWN, "anim.new-from", "New animation from a folder of frames or a sprite sheet", size = 20) do imgui.OpenPopup("##anim_new_from")
	if imgui.BeginPopup("##anim_new_from") {
		rm := &state.game.resourceManager
		gctx := &state.game.gameContext
		added := false
		if imgui.BeginMenu(fmt.ctprintf("%s  From a Folder of Frames", ICON_FA_FOLDER)) {
			for d in Editor_ListProjectDirs(state, "textures") {
				if imgui.MenuItem(strings.clone_to_cstring(d, context.temp_allocator)) {
					Editor_RecordUndo(state, "Add animation")
					paths := make([dynamic]string, context.temp_allocator)
					for f in Editor_ListProjectFiles(state, d, {".png"}) do append(&paths, e.Project_ResolveAssetPath(gctx, f))
					name := e.AnimationPlayerNode_UniqueAnimationName(apn, filepath.base(d))
					e.AnimationPlayerNode_AddFrameAnimation(apn, rm, name, paths[:], true)
					added = true
				}
				Drive_Item(fmt.tprintf("pick:%s", d))
			}
			imgui.EndMenu()
		}
		Drive_Item("anim.new-folder")
		if imgui.BeginMenu(fmt.ctprintf("%s  From a Sprite Sheet", ICON_FA_TABLE_CELLS)) {
			for f in Editor_ListProjectFiles(state, "textures", {".png"}) {
				if imgui.MenuItem(strings.clone_to_cstring(f, context.temp_allocator)) {
					Editor_RecordUndo(state, "Add animation")
					name := e.AnimationPlayerNode_UniqueAnimationName(apn, filepath.stem(f))
					e.AnimationPlayerNode_AddSheetAnimation(apn, rm, name, e.Project_ResolveAssetPath(gctx, f), {4, 1}, 0, 3, true)
					added = true
				}
				Drive_Item(fmt.tprintf("pick:%s", f))
			}
			imgui.EndMenu()
		}
		Drive_Item("anim.new-sheet")
		imgui.Separator()
		if imgui.MenuItem(fmt.ctprintf("%s  Slice a Sprite Sheet...", ICON_FA_SCISSORS)) do Slicer_Open(state, "")
		Drive_Item("anim.new-slicer")
		if added {
			preview_restore(state)
			e.AnimationPlayerNode_SetAnimationIndex(apn, len(apn.animations) - 1)
			if a := e.AnimationPlayerNode_GetAnimation(apn); a != nil do apn.currentFrame = a.startFrame
		}
		imgui.EndPopup()
	}
	anim := e.AnimationPlayerNode_GetAnimation(apn)
	if anim == nil {
		imgui.SameLine()
		UI_DimText("No animations yet: add one with +")
		return
	}
	// Rename / duplicate / delete the current animation.
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_PEN, "anim.rename", "Rename animation", size = 26) {
		panel.newName = {}
		copy(panel.newName[:len(panel.newName) - 1], anim.name)
		imgui.OpenPopup("##anim_rename")
	}
	if imgui.BeginPopup("##anim_rename") {
		UI_DimText("Rename animation")
		if imgui.IsWindowAppearing() do imgui.SetKeyboardFocusHere()
		imgui.SetNextItemWidth(200)
		enter := imgui.InputText("##anim_new_name", cstring(raw_data(panel.newName[:])), len(panel.newName), {.EnterReturnsTrue, .AutoSelectAll})
		Drive_Item("anim.rename-field")
		imgui.SameLine(0, 4)
		if UI_Button("Rename", "anim.rename-ok") || enter {
			old := strings.clone(anim.name, context.temp_allocator)
			name := strings.trim_space(string(cstring(raw_data(panel.newName[:]))))
			if name == old {
				imgui.CloseCurrentPopup()
			} else if name == "" {
				Editor_Log(state, .Warn, "An animation needs a name")
			} else if e.AnimationPlayerNode_FindAnimation(apn, name) >= 0 {
				Editor_Log(state, .Warn, "There is already an animation named \"%s\"", name)
			} else {
				Editor_RecordUndo(state, "Rename animation")
				e.AnimationPlayerNode_RenameAnimation(apn, apn.animationIndex, name)
				rename_state_machine_refs(state, apn, old, anim.name)
				imgui.CloseCurrentPopup()
			}
		}
		typed := strings.trim_space(string(cstring(raw_data(panel.newName[:]))))
		if typed != anim.name && e.AnimationPlayerNode_FindAnimation(apn, typed) >= 0 {
			imgui.PushStyleColorImVec4(.Text, UI_WARNING)
			imgui.TextUnformatted(fmt.ctprintf("%s  Another animation is named \"%s\"", ICON_FA_TRIANGLE_EXCLAMATION, typed))
			imgui.PopStyleColor()
		}
		if imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
		imgui.EndPopup()
	}
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_CLONE, "anim.duplicate", "Duplicate animation (frames, range, settings and tracks)", size = 26) {
		preview_restore(state)
		Editor_RecordUndo(state, "Duplicate animation")
		if d := e.AnimationPlayerNode_DuplicateAnimation(apn, apn.animationIndex, &state.game.resourceManager); d != nil {
			Editor_Log(state, .Info, "Duplicated animation as %s", d.name)
		}
		return
	}
	imgui.SameLine(0, 2)
	UI_IconButton(ICON_FA_HAND, "anim.drag", "Drag into a script: animation_play(\"name\") on this player", size = 26)
	code_item_drag(.Animation, anim.name, apn)
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_TRASH, "anim.delete-animation", "Delete animation (" + CMD + "+Z brings it back)", size = 26) {
		preview_restore(state)
		Editor_RecordUndo(state, "Delete animation")
		name := strings.clone(anim.name, context.temp_allocator)
		e.AnimationPlayerNode_DeleteAnimation(apn, apn.animationIndex, &state.game.resourceManager)
		clear(&panel.sel)
		panel.selAnim = nil
		Editor_Log(state, .Info, "Deleted animation %s", name)
		return
	}
	length := e.Animation_Length(anim, apn)
	rel := playhead(apn, anim)
	imgui.SameLine(0, UI_SPACE)
	UI_VerticalDivider(20)
	if UI_IconButton(ICON_FA_PAUSE if panel.playing else ICON_FA_PLAY, "anim.play", "Pause preview" if panel.playing else "Play preview", panel.playing, 26) {
		if panel.playing {
			panel.playing = false
		} else {
			preview_capture(state, apn)
			panel.playing = true
			panel.lastTick = time.tick_now()
			panel.accum = f32(rel)
		}
	}
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_STOP, "anim.stop", "Stop (restore the scene)", size = 26) do preview_restore(state)
	imgui.SameLine(0, 2)
	// Auto-key: every property change of the selected nodes keys it at the playhead.
	if UI_IconButton(ICON_FA_CIRCLE, "anim.autokey", "Auto-key on: changes to the selected nodes are keyed at the playhead (click: off)" if animAutoKey.on else "Auto-key: key every property change at the playhead", animAutoKey.on, 26, tint = UI_DANGER) {
		animAutoKey.on = !animAutoKey.on
		animAutoKey.valid = false
	}
	imgui.SameLine(0, UI_SPACE)
	imgui.Checkbox("Loop##anim_loop", &anim.loop)
	undo_on_activate(state, "Toggle loop")
	Drive_Item("anim.loop")
	imgui.SameLine(0, UI_SPACE)
	imgui.Checkbox("Reverse##anim_rev", &anim.reverse)
	undo_on_activate(state, "Toggle reverse")
	Drive_Item("anim.reverse")
	UI_Tooltip("Play this animation from its last frame to its first")
	imgui.SameLine(0, UI_SPACE)
	Onion_ToolbarButton(state)
	// This animation's frame rate (anim.fps 0 = the player's).
	imgui.SameLine(0, UI_SPACE)
	imgui.SetNextItemWidth(96)
	// Shows the rate it plays at: its own, else the player's (dimmed);
	// dragging gives it its own, right-click goes back to the player's.
	inherited := anim.fps <= 0
	fps := apn.fps if inherited else anim.fps
	if inherited do imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
	if imgui.DragFloat("##anim_fps", &fps, 0.2, 1, 120, "%.0f fps") {
		anim.fps = max(fps, 1)
		e.AnimationPlayerNode_SetAnimationIndex(apn, apn.animationIndex)
	}
	if inherited do imgui.PopStyleColor()
	undo_on_activate(state, "Edit FPS")
	Drive_Item("anim.fps")
	if !inherited && imgui.IsItemHovered() && imgui.IsMouseClicked(.Right) {
		Editor_RecordUndo(state, "Edit FPS")
		anim.fps = 0
		e.AnimationPlayerNode_SetAnimationIndex(apn, apn.animationIndex)
	}
	UI_Tooltip("Frames per second: the player's (set in the Inspector) until you change it here" if inherited else "This animation's frames per second (right-click: use the player's)")
	imgui.SameLine(0, 2)
	isDefault := apn.defaultAnimation == anim.name
	if UI_IconButton(ICON_FA_STAR, "anim.default", "The animation selected when the scene loads - it plays with Autoplay (click to clear)" if isDefault else "Make this the animation selected when the scene loads (it plays with Autoplay)", isDefault, 26) {
		Editor_RecordUndo(state, "Default animation")
		apn.defaultAnimation = "" if isDefault else strings.clone(anim.name, apn.allocator)
	}
	UI_SameLineOrWrap(80, UI_SPACE)
	imgui.AlignTextToFramePadding()
	UI_DimText(fmt.tprintf("Frame %d / %d  (%.2fs)", rel + 1, length, e.Animation_FrameTime(apn, anim, f32(rel))))
	UI_SameLineOrWrap(100, UI_SPACE)
	selFrame := panel.anchor if len(panel.sel) > 0 else rel
	frameDur := e.Animation_GetFrameDuration(anim, selFrame, e.AnimationPlayerNode_FPS(apn))
	imgui.SetNextItemWidth(80)
	if imgui.DragFloat("##frame_dur", &frameDur, 0.01, 0.01, 30.0, "%.2fs") {
		Editor_RecordUndo(state, "Frame duration")
		if len(panel.sel) > 0 {
			for sf in panel.sel do e.Animation_SetFrameDuration(anim, sf, frameDur, apn.allocator)
		} else {
			e.Animation_SetFrameDuration(anim, selFrame, frameDur, apn.allocator)
		}
	}
	Drive_Item("anim.frame-duration")
	UI_Tooltip("Duration of the selected frame in seconds (right-click to reset to 1/fps)")
	if imgui.IsItemHovered() && imgui.IsMouseClicked(.Right) {
		Editor_RecordUndo(state, "Reset frame duration")
		if len(panel.sel) > 0 {
			for sf in panel.sel do e.Animation_SetFrameDuration(anim, sf, 0, apn.allocator)
		} else {
			e.Animation_SetFrameDuration(anim, selFrame, 0, apn.allocator)
		}
	}
	UI_SameLineOrWrap(110, UI_SPACE)
	if UI_Button(fmt.tprintf("%s  Add Track", ICON_FA_PLUS), "anim.add-track") {
		panel.trackNode = apn
		imgui.OpenPopup("##anim_add_track")
	}
	UI_Tooltip("Scrub the header · drag frames to reorder · drop textures on + · right-click a key to delete")
	mgr := state.activeScene.manager
	if imgui.BeginPopup("##anim_add_track") {
		UI_DimText("Animate a property of:")
		// The player and any node in the scene.
		draw :: proc(state: ^EditorState, mgr: ^e.NodeManager, n: ^e.Node, depth: int) {
			if n.transient do return
			if imgui.Selectable(fmt.ctprintf("%*s%s  %s###tn%p", depth * 3, "", Editor_NodeIcon(n), n.name, n), panel.trackNode == n, {.NoAutoClosePopups}) do panel.trackNode = n
			Drive_Item(fmt.tprintf("anim.track-node:%s", n.name))
			for c in e.GetChildrenView(mgr, n) do if c != nil do draw(state, mgr, c, depth + 1)
		}
		rootNode := state.activeScene.rootNode if state.activeScene != nil && state.activeScene.rootNode != nil else cast(^e.Node)apn
		draw(state, mgr, rootNode, 0)
		imgui.Separator()
		if panel.trackNode != nil && e.Node_IsAlive(panel.trackNode) {
			props := make([dynamic]string, context.temp_allocator)
			append(&props, "position", "rotation", "scale", "origin", "zIndex", "enabled")
			for p in e.Node_CollectProperties(panel.trackNode) do if e.Track_IsAnimatable(p) && !p.runtime {
				found := false
				for pr in props do if pr == p.name { found = true; break }
				if !found do append(&props, p.name)
			}
			for pname in props {
				if imgui.MenuItem(strings.clone_to_cstring(pname, context.temp_allocator)) {
					Editor_RecordUndo(state, "Add track")
					target := e.Node_RelativePath(mgr, apn, panel.trackNode)
					tr := e.Animation_AddTrack(apn, anim, target, pname)
					// First key: the current value at the playhead.
					if p, ok := e.Track_FindProperty(panel.trackNode, pname); ok {
						at := e.Animation_FrameTime(apn, anim, f32(playhead(apn, anim)))
						if e.Track_IsStepped(p) && p.kind == .String {
							if text, tok := e.Property_GetTrackText(p); tok do e.Track_SetEventKey(tr, at, text, apn.allocator)
						} else if v, vok := e.Property_GetTrackValue(p); vok {
							e.Track_SetKey(tr, at, v)
						}
					}
				}
				Drive_Item(fmt.tprintf("anim.track-prop:%s", pname))
			}
			imgui.SeparatorText("Events")
			target := e.Node_RelativePath(mgr, apn, panel.trackNode)
			if imgui.MenuItem(fmt.ctprintf("%s  Call Script Methods", ICON_FA_CODE)) {
				Editor_RecordUndo(state, "Add track")
				e.Animation_AddEventTrack(apn, anim, target, .Method)
			}
			Drive_Item("anim.track-methods")
			UI_Tooltip("Keys call a method on this node's script when playback reaches them")
			if imgui.MenuItem(fmt.ctprintf("%s  Play Sounds", ICON_FA_MUSIC)) {
				Editor_RecordUndo(state, "Add track")
				tr := e.Animation_AddEventTrack(apn, anim, target, .Audio)
				panel.selectedTrack = len(anim.tracks) - 1
			}
			Drive_Item("anim.track-sounds")
			// Particles: one of the scene's emitters.
			if imgui.BeginMenu(fmt.ctprintf("%s  Emit Particles", ICON_FA_WAND_MAGIC_SPARKLES)) {
				emitters := Anim_SceneEmitters(state)
				if len(emitters) == 0 do UI_DimText("No particle emitters in the scene")
				for n in emitters {
					if imgui.MenuItem(fmt.ctprintf("%s##%p", n.name, n)) {
						Editor_RecordUndo(state, "Add track")
						e.Animation_AddEventTrack(apn, anim, e.Node_RelativePath(mgr, apn, n), .EmitParticles)
						panel.selectedTrack = len(anim.tracks) - 1
						imgui.CloseCurrentPopup()
					}
					Drive_Item(fmt.tprintf("anim.track-particles:%s", n.name))
				}
				imgui.EndMenu()
			}
			Drive_Item("anim.track-particles")
			UI_Tooltip("Keys restart, burst, start or stop one of the scene's particle emitters")
			if imgui.MenuItem(fmt.ctprintf("%s  Spawn Component", ICON_FA_CUBES)) {
				Editor_RecordUndo(state, "Add track")
				tr := e.Animation_AddEventTrack(apn, anim, target, .InstantiateComponent)
				panel.selectedTrack = len(anim.tracks) - 1
			}
			Drive_Item("anim.track-spawn")
			UI_Tooltip("Keys instantiate a component/prefab at this node's position")
			if imgui.MenuItem(fmt.ctprintf("%s  Enable / Disable", ICON_FA_TOGGLE_ON)) {
				Editor_RecordUndo(state, "Add track")
				tr := e.Animation_AddEventTrack(apn, anim, target, .SetEnabled)
				panel.selectedTrack = len(anim.tracks) - 1
			}
			Drive_Item("anim.track-enable")
			UI_Tooltip("Keys enable or disable this node (e.g. AreaNode, RaycastNode)")
		}
		imgui.EndPopup()
	}

	// Selection follows the animation.
	if panel.selAnim != anim {
		clear(&panel.sel)
		panel.selAnim = anim
		panel.selectedTrack = -1
	}
	srcCount := e.Animation_SourceCount(anim)

	AnimKeys_Follow(anim)
	hasSel := len(panel.sel) > 0
	hasKeys := len(animKeys.sel) > 0
	canPaste := !e.Frame_ClipEmpty(&frameClip)
	// Keys while the panel has focus (not while typing in a field): on the
	// selected keys, else the selected frames.
	animTimelineFocused = imgui.IsWindowFocused(imgui.FocusedFlags_RootAndChildWindows)
	if animTimelineFocused && !imgui.GetIO().WantTextInput {
		primary := imgui.GetIO().KeySuper || imgui.GetIO().KeyCtrl
		del := imgui.IsKeyPressed(.Delete) || imgui.IsKeyPressed(.Backspace)
		if hasKeys {
			if del do AnimKeys_Delete(state, anim)
			if primary && imgui.IsKeyPressed(.C) {
				AnimKeys_Copy(state, anim)
				panel.pasteKeys = true
			}
			if primary && imgui.IsKeyPressed(.D) {
				AnimKeys_Duplicate(state, apn, anim)
				panel.pasteKeys = true
			}
		} else {
			if hasSel && del do frames_delete(state, apn, anim, slice.clone(panel.sel[:], context.temp_allocator))
			if hasSel && primary && imgui.IsKeyPressed(.C) do frames_copy(state, anim, panel.sel[:])
		}
		if primary && imgui.IsKeyPressed(.V) do paste_any(state, apn, anim)
		hasKeys = len(animKeys.sel) > 0
	}
	srcCount = e.Animation_SourceCount(anim)
	length = e.Animation_Length(anim, apn)
	rel = clamp(playhead(apn, anim), 0, max(length - 1, 0))

	// Preview playback (the editor doesn't run node updates outside Simulate).
	reversed := e.AnimationPlayerNode_IsReversed(apn, anim)
	if panel.playing {
		dt := f32(time.duration_seconds(time.tick_since(panel.lastTick)))
		panel.lastTick = time.tick_now()
		panel.accumTime += dt
		curF := int(panel.accum)
		dur := e.Animation_GetFrameDuration(anim, anim.startFrame + curF, e.AnimationPlayerNode_FPS(apn))
		for panel.accumTime >= dur && length > 0 {
			panel.accumTime -= dur
			panel.accum += 1
			if int(panel.accum) >= length {
				if anim.loop do panel.accum = 0
				else {
					panel.accum = f32(length - 1)
					panel.playing = false
					break
				}
			}
			curF = int(panel.accum)
			dur = e.Animation_GetFrameDuration(anim, anim.startFrame + curF, e.AnimationPlayerNode_FPS(apn))
		}
		f := int(panel.accum)
		if reversed do f = length - 1 - f
		apn.currentFrame = anim.startFrame + min(f, max(anim->frameCount() - 1, 0))
		apn.time = e.Animation_FrameTime(apn, anim, f32(f))
		e.AnimationPlayerNode_ApplyTracks(apn, apn.time)
		rel = f
	}

	// --- timeline: one column per source frame; the range starts at `base` ---
	avail := imgui.GetContentRegionAvail()
	hasAudioPanel := panel.selectedTrack >= 0 && panel.selectedTrack < len(anim.tracks) && anim.tracks[panel.selectedTrack].kind == .Audio
	hasMethodPanel := panel.selectedTrack >= 0 && panel.selectedTrack < len(anim.tracks) && anim.tracks[panel.selectedTrack].kind == .Method
	hasEventPanel := panel.selectedTrack >= 0 && panel.selectedTrack < len(anim.tracks) && track_has_panel(anim.tracks[panel.selectedTrack].kind)
	hasSidePanel := hasAudioPanel || hasMethodPanel || hasEventPanel || len(animKeys.sel) > 0
	sideW: f32 = 0
	if hasSidePanel {
		sideW = 320 if avail.x >= 720 else (PREVIEW_W if avail.x >= 540 else 0)
	} else if avail.x >= 640 {
		sideW = PREVIEW_W
	}

	zoomMod := imgui.GetIO().KeySuper || imgui.GetIO().KeyCtrl
	timelineFlags: imgui.WindowFlags = {.HorizontalScrollbar}
	if zoomMod || panel.graph do timelineFlags += {.NoScrollWithMouse} // (the graph's wheel moves values)
	if !imgui.BeginChild("##anim_timeline", {avail.x - sideW - (UI_SPACE if sideW > 0 else 0), max(avail.y, 40)}, {}, timelineFlags) {
		imgui.EndChild()
		if sideW > 0 do side_panel(state, apn, anim, {sideW, max(avail.y, 40)})
		return
	}
	dl := imgui.GetWindowDrawList()
	origin := imgui.GetCursorScreenPos()
	scrollX := imgui.GetScrollX()
	x0 := origin.x + LABEL_W
	io := imgui.GetIO()
	mouse := [2]f32{io.MousePos.x, io.MousePos.y}
	cellW = CELL_W * AnimationPanel_Zoom()
	base := anim.startFrame
	cols := max(srcCount, base + length)
	// Rows: the tracks grouped by node (the player's first), each group
	// under its node's row (click: fold).
	ty := origin.y + 20 + THUMB_H + 4
	Group_Row :: struct {target: string, y: f32, folded: bool}
	groups := make([dynamic]Group_Row, context.temp_allocator)
	order := make([dynamic]int, context.temp_allocator)
	rowY := make([]f32, len(anim.tracks), context.temp_allocator)
	targets := make([dynamic]string, context.temp_allocator)
	for tr in anim.tracks {
		t := "." if tr.target == "" else tr.target
		found := false
		for x in targets do if x == t do found = true
		if !found do append(&targets, t)
	}
	slice.stable_sort_by(targets[:], proc(a, b: string) -> bool {return a == "." && b != "."})
	rowsH := f32(0)
	for t in targets {
		folded := t in panel.collapsed
		append(&groups, Group_Row{t, ty + rowsH, folded})
		rowsH += GROUP_H
		for tr, ti in anim.tracks {
			if ("." if tr.target == "" else tr.target) != t do continue
			rowY[ti] = ty + rowsH
			if folded do continue
			append(&order, ti)
			rowsH += ROW_H
		}
	}
	// The graph: the rest of the panel's height.
	if panel.graph do rowsH = max(imgui.GetWindowHeight() - (20 + THUMB_H + 4) - 22, 60) // (fits: the wheel moves values here)
	totalH := 20 + THUMB_H + 4 + rowsH
	imgui.Dummy({LABEL_W + f32(cols + 4) * cellW, totalH})
	colX :: proc(x0: f32, col: int) -> f32 {return x0 + f32(col) * cellW}
	// Zoom: Cmd / Ctrl + wheel, or the wheel over the ruler - the frame under
	// the mouse stays put.
	if imgui.IsWindowHovered({}) && io.MouseWheel != 0 && mouse.x >= x0 && (zoomMod || (mouse.y >= origin.y && mouse.y < origin.y + 20)) {
		z := clamp(AnimationPanel_Zoom() * (1.2 if io.MouseWheel > 0 else 1 / 1.2), 0.25, 6)
		col := (mouse.x - x0) / cellW
		imgui.SetScrollX(scrollX + col * (CELL_W * z - cellW))
		panel.zoom = z
	}

	// Header: frame numbers and the range band with its handles; click /
	// drag inside the range scrubs.
	headMn := [2]f32{x0, origin.y}
	headMx := [2]f32{colX(x0, cols), origin.y + 18}
	imgui.DrawList_AddRectFilled(dl, headMn, headMx, col_u32(UI_BG_RAISED), 4)
	rangeMn := [2]f32{colX(x0, base), origin.y}
	rangeMx := [2]f32{colX(x0, base + length), origin.y + 18}
	imgui.DrawList_AddRectFilled(dl, rangeMn, rangeMx, col_u32(UI_ACCENT_SOFT), 4)
	// The ruler: frame numbers, or seconds from the range's start.
	step := ruler_step(cellW, 44 if panel.rulerSeconds else 26)
	for f in 0 ..< cols {
		x := colX(x0, f)
		inRange := f >= base && f < base + length
		if f % step == 0 {
			text := fmt.ctprintf("%d", f + 1)
			if panel.rulerSeconds do text = fmt.ctprintf("%.2fs", e.Animation_FrameTime(apn, anim, f32(f - base))) if f >= base else ""
			imgui.DrawList_AddText(dl, {x + 4, origin.y + 3}, col_u32(UI_TEXT_DIM if inRange else UI_TEXT_FAINT), text)
		}
		if cellW >= 8 || f % step == 0 do imgui.DrawList_AddLine(dl, {x, origin.y + 14}, {x, origin.y + 20}, col_u32(ui_line(0.12)))
	}
	// Left of the header: copy / paste / delete the selected frames.
	{
		imgui.PushStyleVarImVec2(.FramePadding, {3, 1})
		bx := origin.x + scrollX + 6
		imgui.SetCursorScreenPos({bx, origin.y})
		what := "keys" if hasKeys else "frames"
		any := hasSel || hasKeys
		if !any do imgui.BeginDisabled(true)
		if UI_IconButton(ICON_FA_COPY, "anim.copy", fmt.tprintf("Copy the selected %s (" + CMD + "+C)", what), size = 20) {
			if hasKeys {
				AnimKeys_Copy(state, anim)
				panel.pasteKeys = true
			} else do frames_copy(state, anim, panel.sel[:])
		}
		if !any do imgui.EndDisabled()
		imgui.SameLine(0, 2)
		canPasteAny := canPaste || (panel.pasteKeys && AnimKeys_CanPaste())
		if !canPasteAny do imgui.BeginDisabled(true)
		if UI_IconButton(ICON_FA_PASTE, "anim.paste", "Paste keys at the playhead (" + CMD + "+V)" if panel.pasteKeys && AnimKeys_CanPaste() else "Paste frames after the selection, else at the end (" + CMD + "+V)", size = 20) do paste_any(state, apn, anim)
		if !canPasteAny do imgui.EndDisabled()
		imgui.SameLine(0, 2)
		if !any do imgui.BeginDisabled(true)
		if UI_IconButton(ICON_FA_TRASH, "anim.delete", fmt.tprintf("Delete the selected %s (Delete)", what), size = 20, tint = UI_DANGER) {
			if hasKeys do AnimKeys_Delete(state, anim)
			else do frames_delete(state, apn, anim, slice.clone(panel.sel[:], context.temp_allocator))
		}
		if !any do imgui.EndDisabled()
		imgui.SameLine(0, 6)
		imgui.SetCursorPosY(imgui.GetCursorPosY() + 2)
		UI_DimText(fmt.tprintf("%d key(s)", len(animKeys.sel)) if hasKeys else (fmt.tprintf("%d selected", len(panel.sel)) if hasSel else ""))
		// At the ruler: its units and the zoom (Cmd / Ctrl + wheel over the
		// timeline, or the wheel over the ruler).
		imgui.SetCursorScreenPos({origin.x + scrollX + LABEL_W - 96, origin.y})
		if UI_IconButton(ICON_FA_CHART_LINE, "anim.graph", "Track rows (click)" if panel.graph else "Value graph: the curves, with bezier handles (click)", panel.graph, size = 20) {
			panel.graph = !panel.graph
			AnimGraph_FrameAll()
		}
		imgui.SameLine(0, 2)
		if UI_IconButton(ICON_FA_CLOCK, "anim.ruler-units", "Ruler in seconds (click: frames)" if panel.rulerSeconds else "Ruler in frames (click: seconds)", panel.rulerSeconds, size = 20) {
			panel.rulerSeconds = !panel.rulerSeconds
		}
		imgui.SameLine(0, 2)
		if UI_Button(fmt.tprintf("%d%%", int(math.round(AnimationPanel_Zoom() * 100))), "anim.zoom-reset", {46, 0}) do panel.zoom = 1
		UI_Tooltip("Timeline zoom: Cmd / Ctrl + wheel over the timeline, or the wheel over the ruler (click: 100%)")
		imgui.PopStyleVar()
	}
	imgui.SetCursorScreenPos(headMn)
	imgui.InvisibleButton("##anim_head", {max(headMx.x - headMn.x, 1), 20})
	imgui.SetItemKeyOwner(.MouseWheelY) // (the wheel zooms here)
	Drive_ItemRect("anim.header", rangeMn, {rangeMx.x, rangeMn.y + 20}, inWindow = true)
	if imgui.IsItemActive() && panel.rangeDrag == 0 {
		f := int((mouse.x - rangeMn.x) / cellW)
		scrub(state, apn, anim, f)
		panel.playing = false
		rel = clamp(f, 0, length - 1)
	}
	// Range handles: drag to the first / last frame played.
	handle :: proc(id: string, x, y: f32) -> bool {
		imgui.SetCursorScreenPos({x - 4, y})
		imgui.InvisibleButton(strings.clone_to_cstring(id, context.temp_allocator), {8, 20})
		Drive_Item(id)
		hot := imgui.IsItemHovered() || imgui.IsItemActive()
		imgui.DrawList_AddRectFilled(imgui.GetWindowDrawList(), {x - 2, y}, {x + 2, y + 20}, col_u32(UI_ACCENT if hot else ui_accent(0.7)), 2)
		if hot do imgui.SetMouseCursor(.ResizeEW)
		return imgui.IsItemActive()
	}
	if handle("anim.range-start", rangeMn.x, origin.y) {
		if panel.rangeDrag == 0 do Editor_RecordUndo(state, "Edit range")
		panel.rangeDrag = 1
		e.Animation_SetRange(anim, int(math.round((mouse.x - x0) / cellW)), anim.endFrame)
	} else if handle("anim.range-end", rangeMx.x, origin.y) {
		if panel.rangeDrag == 0 do Editor_RecordUndo(state, "Edit range")
		panel.rangeDrag = 2
		e.Animation_SetRange(anim, anim.startFrame, int(math.round((mouse.x - x0) / cellW)) - 1)
	} else if !imgui.IsMouseDown(.Left) {
		panel.rangeDrag = 0
	}

	// Frames row: every source frame.
	fy := origin.y + 20
	label :: proc(dl: ^imgui.DrawList, x, y: f32, text: string, col: imgui.Vec4) {
		imgui.DrawList_AddText(dl, {x + 8, y}, col_u32(col), strings.clone_to_cstring(text, context.temp_allocator))
	}
	label(dl, origin.x + scrollX, fy + 1, fmt.tprintf("%s  Frames", ICON_FA_IMAGE), UI_TEXT)
	// Under the label: the range played (first / last frame).
	{
		imgui.PushStyleVarImVec2(.FramePadding, {4, 1})
		imgui.SetCursorScreenPos({origin.x + scrollX + 8, fy + 19})
		imgui.SetNextItemWidth(56)
		first := c.int(anim.startFrame + 1)
		if imgui.DragInt("##anim_start", &first, 0.1, 1, c.int(max(srcCount, 1)), "from %d") do e.Animation_SetRange(anim, int(first) - 1, max(anim.endFrame, int(first) - 1))
		undo_on_activate(state, "Edit range")
		Drive_Item("anim.start")
		UI_Tooltip("First frame played (or drag the range handles in the header)")
		imgui.SameLine(0, 3)
		imgui.SetNextItemWidth(56)
		last := c.int(anim.endFrame + 1)
		if imgui.DragInt("##anim_end", &last, 0.1, 1, c.int(max(srcCount, 1)), "to %d") do e.Animation_SetRange(anim, anim.startFrame, int(last) - 1)
		undo_on_activate(state, "Edit range")
		Drive_Item("anim.end")
		UI_Tooltip("Last frame played")
		imgui.SameLine(0, 4)
		imgui.SetCursorPosY(imgui.GetCursorPosY() + 1)
		UI_DimText(fmt.tprintf("/ %d", srcCount))
		imgui.PopStyleVar()
	}
	isFrames := anim.renderFrame == e.FA_RenderFrame
	ctxFrame := -1
	for f in 0 ..< srcCount {
		mn := [2]f32{colX(x0, f) + 1, fy}
		mx := [2]f32{mn.x + cellW - 2, fy + THUMB_H}
		inRange := f >= base && f <= anim.endFrame
		imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32(UI_ACCENT_SOFT if f == apn.currentFrame else UI_BG_RAISED), 4)
		draw_frame_thumb(dl, anim, f, mn, mx)
		if !inRange do imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32({UI_BG_PANEL.x, UI_BG_PANEL.y, UI_BG_PANEL.z, 0.65}), 4)
		if selected(f) do imgui.DrawList_AddRect(dl, mn, mx, col_u32(UI_ACCENT), 4, {}, 2)
		imgui.SetCursorScreenPos(mn)
		imgui.PushIDInt(c.int(f))
		if imgui.InvisibleButton("##frame", mx - mn) {
			frame_select(f)
			clear(&animKeys.sel)
			panel.playing = false
			if inRange do scrub(state, apn, anim, f - base)
			else do apn.currentFrame = f // just show it
		}
		Drive_Item(fmt.tprintf("anim.frame:%d", f + 1))
		if imgui.IsItemHovered() && imgui.IsMouseClicked(.Right) {
			if !selected(f) {
				clear(&panel.sel)
				append(&panel.sel, f)
			}
			panel.anchor = f
			ctxFrame = f
		}
		if isFrames {
			// Drag to reorder.
			if imgui.BeginDragDropSource({}) {
				idx := c.int(f)
				imgui.SetDragDropPayload("RAYZR_ANIM_FRAME", &idx, size_of(c.int))
				imgui.TextUnformatted(fmt.ctprintf("Frame %d", f + 1))
				imgui.EndDragDropSource()
			}
			if imgui.BeginDragDropTarget() {
				if pl := imgui.AcceptDragDropPayload("RAYZR_ANIM_FRAME"); pl != nil {
					from := int((cast(^c.int)pl.Data)^)
					if from != f {
						Editor_RecordUndo(state, "Move frame")
						e.Animation_MoveFrame(anim, from, f)
						clear(&panel.sel)
						append(&panel.sel, f)
					}
				}
				imgui.EndDragDropTarget()
			}
		}
		imgui.PopID()
	}
	if ctxFrame >= 0 do imgui.OpenPopup("##frame_ctx")
	if imgui.BeginPopup("##frame_ctx") {
		f := panel.anchor
		UI_DimText(fmt.tprintf("%d frame(s) selected", len(panel.sel)))
		imgui.Separator()
		if imgui.MenuItem(fmt.ctprintf("%s  Copy", ICON_FA_COPY), CMD + "+C") do frames_copy(state, anim, panel.sel[:])
		Drive_Item("anim.ctx-copy")
		if imgui.MenuItem(fmt.ctprintf("%s  Paste After", ICON_FA_PASTE), CMD + "+V", false, !e.Frame_ClipEmpty(&frameClip)) do frames_paste(state, apn, anim)
		Drive_Item("anim.ctx-paste")
		if imgui.MenuItem(fmt.ctprintf("%s  Delete", ICON_FA_TRASH), "Del") do frames_delete(state, apn, anim, slice.clone(panel.sel[:], context.temp_allocator))
		Drive_Item("anim.ctx-delete")
		imgui.Separator()
		if imgui.MenuItem(fmt.ctprintf("%s  Insert Empty Frame", ICON_FA_PLUS)) {
			Editor_RecordUndo(state, "Insert empty frame")
			e.Animation_InsertEmptyFrame(apn, anim, f)
		}
		Drive_Item("anim.ctx-insert-empty")
		if imgui.MenuItem(fmt.ctprintf("%s  Append Empty Frame", ICON_FA_PLUS)) {
			Editor_RecordUndo(state, "Append empty frame")
			e.Animation_AddEmptyFrame(apn, anim)
		}
		Drive_Item("anim.ctx-add-empty")
		imgui.Separator()
		if imgui.MenuItem(fmt.ctprintf("Start the Range Here (frame %d)", f + 1)) {
			Editor_RecordUndo(state, "Edit range")
			e.Animation_SetRange(anim, f, max(anim.endFrame, f))
		}
		Drive_Item("anim.ctx-range-start")
		if imgui.MenuItem(fmt.ctprintf("End the Range Here (frame %d)", f + 1)) {
			Editor_RecordUndo(state, "Edit range")
			e.Animation_SetRange(anim, min(anim.startFrame, f), f)
		}
		Drive_Item("anim.ctx-range-end")
		imgui.EndPopup()
	}
	// Drop textures to append frames.
	if isFrames {
		dropMn := [2]f32{colX(x0, srcCount) + 1, fy}
		dropMx := [2]f32{dropMn.x + cellW * 2, fy + THUMB_H}
		imgui.DrawList_AddRect(dl, dropMn, dropMx, col_u32(ui_line(0.15)), 4)
		imgui.DrawList_AddText(dl, {dropMn.x + cellW - 6, fy + THUMB_H * 0.5 - 8}, col_u32(UI_TEXT_FAINT), ICON_FA_PLUS)
		imgui.SetCursorScreenPos(dropMn)
		imgui.InvisibleButton("##frame_drop", dropMx - dropMn)
		Drive_Item("anim.frame-drop")
		UI_Tooltip("Drop textures from Assets here to add frames")
		if imgui.BeginDragDropTarget() {
			if pl := imgui.AcceptDragDropPayload(ASSET_PAYLOAD); pl != nil {
				p := (^Asset_Payload)(pl.Data)
				rel := strings.clone(string(p.path[:p.len]), context.temp_allocator)
				if Asset_KindOf(rel) == .Texture {
					Editor_Log(state, .Info, "Added frame %s", rel)
					Editor_RecordUndo(state, "Add frame")
					fa := cast(^e.FrameAnimation)anim
					e.FrameAnimation_AddFrame(fa, &state.game.resourceManager, e.Project_ResolveAssetPath(&state.game.gameContext, rel))
				}
			}
			imgui.EndDragDropTarget()
		}
	}

	removeTrack := -1
	if panel.graph {
		AnimGraph_Render(state, apn, anim, dl, origin.x + scrollX, origin.x + scrollX + LABEL_W, origin.x + scrollX + imgui.GetWindowWidth() - 4, ty, rowsH, x0, base, cellW, imgui.IsWindowHovered({}))
	} else {
		// Node rows: fold / unfold its tracks; folded, its keys as dots.
		for g in groups {
			gy := g.y
			imgui.DrawList_AddRectFilled(dl, {origin.x + scrollX, gy}, {colX(x0, cols), gy + GROUP_H - 2}, col_u32(ui_line(0.06)), 3)
			gname := apn.name if g.target == "." else g.target
			if g.target != "." {
				if n := e.Node_ResolvePath(mgr, apn, g.target); n != nil do gname = n.name
			}
			label(dl, origin.x + scrollX, gy + 2, fmt.tprintf("%s  %s", ICON_FA_CARET_RIGHT if g.folded else ICON_FA_CARET_DOWN, gname), UI_TEXT_DIM)
			imgui.SetCursorScreenPos({origin.x + scrollX, gy})
			if imgui.InvisibleButton(fmt.ctprintf("##group_%s", g.target), {LABEL_W - 8, GROUP_H - 2}) do group_toggle(g.target)
			Drive_Item(fmt.tprintf("anim.group:%s", g.target))
			UI_Tooltip("Fold this node's tracks" if !g.folded else "Show this node's tracks")
			if g.folded {
				for tr in anim.tracks {
					if ("." if tr.target == "" else tr.target) != g.target do continue
					for k in tr.keys {
						kx := x0 + (f32(base) + e.Animation_TimeFrame(apn, anim, k.time)) * cellW + cellW * 0.5
						imgui.DrawList_AddCircleFilled(dl, {kx, gy + GROUP_H * 0.5 - 1}, 3, col_u32(UI_TEXT_DIM))
					}
				}
			}
		}

		// Track rows. Keys: click selects (Shift / Cmd: adds), drag moves the
		// selection (snapping to frames; Shift: free), a box from an empty spot
		// selects; right-click: the key's menu.
		canInteract := imgui.IsWindowHovered({})
		keyHit := false
		clear(&animKeys.boxHits)
		boxMn := [2]f32{min(animKeys.boxFrom.x, mouse.x), min(animKeys.boxFrom.y, mouse.y)}
		boxMx := [2]f32{max(animKeys.boxFrom.x, mouse.x), max(animKeys.boxFrom.y, mouse.y)}
		for ti in order {
			tr := &anim.tracks[ti]
			y := rowY[ti]
			imgui.DrawList_AddRectFilled(dl, {origin.x + scrollX, y}, {colX(x0, cols), y + ROW_H - 2}, col_u32(ui_line(0.025)), 3)
			target: ^e.Node = apn
			if tr.target != "." && tr.target != "" do target = e.Node_ResolvePath(mgr, apn, tr.target)
			prop := tr.property
			if tr.kind == .Method {
				scriptRel := node_script_rel(state, target)
				if scriptRel != "" do prop = fmt.tprintf("calls() -> %s", filepath.base(scriptRel))
				else do prop = "calls() (no script!)"
			}
			if tr.kind == .Audio {
				if tr.name != "" do prop = tr.name
				else if tr.property == "@audio" do prop = "sounds"
				else if strings.has_prefix(tr.property, "@audio_") do prop = fmt.tprintf("sounds %s", tr.property[len("@audio_"):])
				else do prop = "sounds"
			}
			#partial switch tr.kind {
			case .EmitParticles:        prop = "particles"
			case .InstantiateComponent: prop = "spawn component"
			case .SetEnabled:           prop = "enable / disable"
			}
			name := prop // (under its node's row)
			isSelectedTrack := panel.selectedTrack == ti
			if isSelectedTrack {
				imgui.DrawList_AddRect(dl, {origin.x + scrollX, y}, {colX(x0, cols), y + ROW_H - 2}, col_u32(UI_ACCENT), 3, thickness = 1.5)
			}
			labelCol := UI_TEXT if target != nil else UI_DANGER
			if target != nil && tr.kind == .Method && node_script_rel(state, target) == "" do labelCol = UI_WARNING
			btnStart := LABEL_W - (82 if track_has_panel(tr.kind) else 58)

			// Clip label text before btnStart so text never bleeds over the buttons
			imgui.DrawList_PushClipRect(dl, {origin.x + scrollX, y}, {origin.x + scrollX + btnStart - 4, y + ROW_H}, true)
			label(dl, origin.x + scrollX + 10, y + 6, name, labelCol)
			imgui.DrawList_PopClipRect(dl)

			// Hover tooltip over track header showing full track name
			headerMn := [2]f32{origin.x + scrollX, y}
			headerMx := [2]f32{origin.x + scrollX + btnStart - 4, y + ROW_H}
			mousePos := imgui.GetMousePos()
			if mousePos.x >= headerMn.x && mousePos.x <= headerMx.x && mousePos.y >= headerMn.y && mousePos.y <= headerMx.y {
				imgui.SetTooltip("%s", fmt.ctprintf("%s.%s (%s)", apn.name if tr.target == "." || tr.target == "" else tr.target, name, tr.property))
			}

			imgui.PushIDInt(c.int(ti) + 1000)
			// Row buttons (fixed at the left).
			imgui.SetCursorScreenPos({origin.x + scrollX + btnStart, y + 2})
			keyTip := "Key the current value at the playhead"
			if tr.kind == .Method do keyTip = "Call a method at the playhead (right-click the key to name it)"
			if tr.kind == .Audio do keyTip = "Play a sound at the playhead (right-click the key to pick it)"
			if tr.kind == .EmitParticles do keyTip = "Emit particles at the playhead (right-click to edit action)"
			if tr.kind == .InstantiateComponent do keyTip = "Spawn component at the playhead (right-click to pick component)"
			if tr.kind == .SetEnabled do keyTip = "Toggle enable/disable at the playhead"
			keyClicked := UI_IconButton(ICON_FA_CIRCLE, fmt.tprintf("anim.key:%s", tr.property), keyTip, size = 24, tint = UI_WARNING)
			if keyClicked && tr.kind != .Property {
				Editor_RecordUndo(state, "Add event key")
				text := "on_animation_event"
				if tr.kind == .Audio {
					audio := Editor_ListProjectFiles(state, "", AUDIO_EXTS)
					text = audio[0] if len(audio) > 0 else ""
					panel.selectedTrack = ti
				} else if tr.kind == .Method {
					if methods := Script_ListMethods(state, target); len(methods) > 0 do text = methods[0]
					panel.selectedTrack = ti
				} else if tr.kind == .EmitParticles {
					text = e.Particle_KeyText(.Restart, 0)
				} else if tr.kind == .InstantiateComponent {
					comps := Editor_ListProjectFiles(state, "", {".component.json"})
					text = comps[0] if len(comps) > 0 else ""
				} else if tr.kind == .SetEnabled {
					text = "disable"
				}
				// The previous key's text is the likely next one.
				at := e.Animation_FrameTime(apn, anim, f32(rel))
				for k in tr.keys do if k.time < at && k.text != "" do text = k.text
				e.Track_SetEventKey(tr, at, text, apn.allocator)
			} else if keyClicked && target != nil {
				if p, ok := e.Track_FindProperty(target, tr.property); ok {
					at := e.Animation_FrameTime(apn, anim, f32(rel))
					if p.kind == .String {
						if text, tok := e.Property_GetTrackText(p); tok {
							Editor_RecordUndo(state, "Set key")
							e.Track_SetEventKey(tr, at, text, apn.allocator)
						}
					} else if v, vok := e.Property_GetTrackValue(p); vok {
						Editor_RecordUndo(state, "Set key")
						e.Track_SetKey(tr, at, v)
						// The value the user just set is the one to come back to.
						for &pv in panel.saved do if pv.node == target && pv.property == tr.property do pv.value = v
					}
				}
			}
			if tr.kind == .Audio {
				imgui.SameLine(0, 2)
				if UI_IconButton(ICON_FA_SLIDERS, fmt.tprintf("anim.track-settings:%s", tr.property), "Sound Track Settings", isSelectedTrack, size = 24) {
					panel.selectedTrack = ti if panel.selectedTrack != ti else -1
				}
			} else if tr.kind == .Method {
				imgui.SameLine(0, 2)
				if UI_IconButton(ICON_FA_CODE, fmt.tprintf("anim.track-settings:%s", tr.property), "Script Call Settings", isSelectedTrack, size = 24) {
					panel.selectedTrack = ti if panel.selectedTrack != ti else -1
				}
			} else if track_has_panel(tr.kind) {
				imgui.SameLine(0, 2)
				if UI_IconButton(ICON_FA_SLIDERS, fmt.tprintf("anim.track-settings:%s", tr.property), "Track settings: the target and every key", isSelectedTrack, size = 24) {
					panel.selectedTrack = ti if panel.selectedTrack != ti else -1
				}
			}
			imgui.SameLine(0, 2)
			if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("anim.remove-track:%s", tr.property), "Remove track", size = 24) {
				removeTrack = ti
				if panel.selectedTrack == ti do panel.selectedTrack = -1
			}
			// The curves between keys (eased / custom ones).
			Key_X :: struct {x0: f32, base: int, apn: ^e.AnimationPlayerNode, anim: ^e.Animation}
			kx := Key_X{x0, base, apn, anim}
			Track_DrawCurves(dl, tr, proc(time: f32, data: rawptr) -> f32 {
				k := cast(^Key_X)data
				return k.x0 + (f32(k.base) + e.Animation_TimeFrame(k.apn, k.anim, time)) * cellW + cellW * 0.5
			}, &kx, y + 5, y + ROW_H - 7)
			// Keys (right-click: easing to the next key, delete).
			for k, ki in tr.keys {
				kf := key_frame(apn, anim, k)
				isSel := AnimKeys_IsSelected(ti, k.time)
				// (Dragged: drawn where it will land.)
				at := k.time + (animKeys.delta if animKeys.dragging && isSel else 0)
				cx := x0 + (f32(base) + e.Animation_TimeFrame(apn, anim, at)) * cellW + cellW * 0.5
				cy := y + ROW_H * 0.5 - 1
				r := f32(6)
				pts := [4][2]f32{{cx, cy - r}, {cx + r, cy}, {cx, cy + r}, {cx - r, cy}}
				hot := canInteract && !animKeys.dragging && !animKeys.boxing && point_in_rect(mouse, {cx - r, cy - r}, {cx + r, cy + r})
				if animKeys.boxing && point_in_rect({cx, cy}, boxMn, boxMx) {
					append(&animKeys.boxHits, Key_Ref{ti, k.time})
					isSel = true
				}
				col := col_u32(UI_WARNING if !hot else {1, 0.85, 0.5, 1})
				if tr.kind == .Property {
					imgui.DrawList_AddQuadFilled(dl, pts[0], pts[1], pts[2], pts[3], col)
				} else {
					// Event keys: a square (method) or a circle (sound).
					ec := col_u32({0.55, 0.75, 1, 1} if !hot else {0.75, 0.88, 1, 1})
					if tr.kind == .Method do imgui.DrawList_AddRectFilled(dl, {cx - r + 1, cy - r + 1}, {cx + r - 1, cy + r - 1}, ec, 2)
					else do imgui.DrawList_AddCircleFilled(dl, {cx, cy}, r - 1, ec)
				}
				if isSel {
					o := r + 3
					imgui.DrawList_AddQuad(dl, {cx, cy - o}, {cx + o, cy}, {cx, cy + o}, {cx - o, cy}, col_u32(UI_TEXT), 1.5)
				}
				// Event keys say what they do (up to the next key).
				if tr.kind != .Property {
					limit := colX(x0, cols + 4)
					if ki + 1 < len(tr.keys) do limit = x0 + (f32(base) + e.Animation_TimeFrame(apn, anim, tr.keys[ki + 1].time)) * cellW + cellW * 0.5 - r - 3
					if limit - (cx + r + 4) > 14 {
						imgui.DrawList_PushClipRect(dl, {cx + r + 3, y}, {limit, y + ROW_H}, true)
						imgui.DrawList_AddText(dl, {cx + r + 4, cy - 8}, col_u32(UI_TEXT_DIM), strings.clone_to_cstring(Anim_EventKeyLabel(tr, k), context.temp_allocator))
						imgui.DrawList_PopClipRect(dl)
					}
				}
				if tr.kind == .Property && (k.ease != .Linear || k.bezier) do imgui.DrawList_AddCircleFilled(dl, {cx, cy + r + 4}, 2, col_u32(UI_ACCENT))
				Drive_ItemRect(fmt.tprintf("anim.keyframe:%s:%d", tr.property, kf + 1), {cx - r, cy - r}, {cx + r, cy + r})
				if hot {
					switch tr.kind {
					case .Property:
						curve := "bezier handles" if k.bezier else e.Ease_Name(k.ease)
						value := k.text if k.text != "" else fmt.tprintf("%.2f %.2f %.2f %.2f", k.value[0], k.value[1], k.value[2], k.value[3])
						imgui.SetTooltip("%s", fmt.ctprintf("Frame %d (%.2fs): %s\nTo the next key: %s  (right-click: easing, curve, delete)", kf + 1, k.time, value, curve))
					case .Method:   imgui.SetTooltip("%s", fmt.ctprintf("Frame %d (%.2fs): calls %s:%s(%s)  (right-click: edit, delete)", kf + 1, k.time, tr.target, k.text, k.arg if k.arg != "" else "frame"))
					case .Audio:    imgui.SetTooltip("%s", fmt.ctprintf("Frame %d (%.2fs): plays %s  (right-click: edit, delete)", kf + 1, k.time, k.text))
					case .EmitParticles:
						action, count := e.Particle_KeyAction(k.text)
						what := fmt.tprintf("emits %d particles", count) if action == .Emit else fmt.tprintf("%vs the emitter", action)
						imgui.SetTooltip("%s", fmt.ctprintf("Frame %d (%.2fs): %s  (right-click: edit, delete)", kf + 1, k.time, strings.to_lower(what, context.temp_allocator)))
					case .InstantiateComponent:  imgui.SetTooltip("%s", fmt.ctprintf("Frame %d (%.2fs): spawn component %s  (right-click: edit, delete)", kf + 1, k.time, k.text))
					case .SetEnabled:            imgui.SetTooltip("%s", fmt.ctprintf("Frame %d (%.2fs): %s %s  (right-click: edit, delete)", kf + 1, k.time, k.text, tr.target))
					}
					if imgui.IsMouseClicked(.Left) && !keyHit {
						keyHit = true
						AnimKeys_Click(ti, k.time, mouse.x)
						clear(&panel.sel)
						scrub(state, apn, anim, kf)
						// (Sound / script-call keys: their track's settings; others: the key inspector.)
						panel.selectedTrack = ti if track_has_panel(tr.kind) else -1
					}
					if imgui.IsMouseClicked(.Right) {
						if !isSel {
							clear(&animKeys.sel)
							append(&animKeys.sel, Key_Ref{ti, k.time})
						}
						keyMenu = {ti, k.time}
						if track_has_panel(tr.kind) do panel.selectedTrack = ti
						imgui.OpenPopup("##key_ctx")
					}
				}
			}
			if keyMenu.track == ti && imgui.BeginPopup("##key_ctx") {
				key: ^e.Track_Key
				for &k in tr.keys do if abs(k.time - keyMenu.time) < e.TRACK_KEY_EPS do key = &k
				if key != nil {
					UI_DimText(fmt.tprintf("Key at frame %d (%.2fs)", key_frame(apn, anim, key^) + 1, key.time))
					imgui.Separator()
					if tr.kind == .Method {
						buf: [128]u8
						copy(buf[:len(buf) - 1], key.text)
						imgui.SetNextItemWidth(220)
						if imgui.InputTextWithHint("##method", "method name", cstring(raw_data(buf[:])), len(buf), {.AutoSelectAll}) {
							key.text = strings.clone(string(cstring(raw_data(buf[:]))), apn.allocator)
						}
						if imgui.IsItemActivated() do Editor_RecordUndo(state, "Event key")
						Drive_Item("anim.event-method")
						// The target script's methods.
						if methods := Script_ListMethods(state, target); len(methods) > 0 {
							imgui.SameLine()
							if imgui.BeginCombo("##method_pick", nil, {.NoPreview}) {
								for m in methods {
									if imgui.Selectable(fmt.ctprintf("%s", m), m == key.text) {
										Editor_RecordUndo(state, "Event key")
										key.text = strings.clone(m, apn.allocator)
									}
									Drive_Item(fmt.tprintf("pick:%s", m))
								}
								imgui.EndCombo()
							}
							Drive_Item("anim.event-method-pick")
							UI_Tooltip("The target script's methods")
						}
						abuf: [128]u8
						copy(abuf[:len(abuf) - 1], key.arg)
						imgui.SetNextItemWidth(220)
						if imgui.InputTextWithHint("##method_arg", "argument (empty: the frame)", cstring(raw_data(abuf[:])), len(abuf), {.AutoSelectAll}) {
							key.arg = strings.clone(string(cstring(raw_data(abuf[:]))), apn.allocator)
						}
						if imgui.IsItemActivated() do Editor_RecordUndo(state, "Event key")
						Drive_Item("anim.event-arg")
						UI_DimText("Called on the target's script: method(argument) - a number when it reads as one. The player also emits animation_event(method).")
						if imgui.MenuItem(fmt.ctprintf("%s  Script Call Settings...", ICON_FA_SLIDERS)) {
							panel.selectedTrack = ti
						}
					} else if tr.kind == .Audio {
						if path, ok := asset_picker("anim.event-sound", key.text, Editor_ListProjectFiles(state, "", AUDIO_EXTS), allowNone = false); ok {
							Editor_RecordUndo(state, "Event key")
							key.text = strings.clone(path, apn.allocator)
						}
						if imgui.MenuItem(fmt.ctprintf("%s  Sound Settings...", ICON_FA_SLIDERS)) {
							panel.selectedTrack = ti
						}
					} else {
						Anim_EventKeyEditor(state, apn, tr, key) // particles / spawn / enable
					}
					if tr.kind == .Property && imgui.BeginMenu(fmt.ctprintf("%s  Easing: %s", ICON_FA_WAVE_SQUARE, e.Ease_Name(key.ease))) {
						for ease in e.Ease {
							if imgui.MenuItem(strings.clone_to_cstring(e.Ease_Name(ease), context.temp_allocator), nil, ease == key.ease) {
								Editor_RecordUndo(state, "Key easing")
								key.ease = ease
							}
							Drive_Item(fmt.tprintf("anim.ease:%s", e.Ease_Name(ease)))
							if imgui.IsItemHovered() do ease_preview(ease)
						}
						imgui.EndMenu()
					}
					Drive_Item("anim.key-easing")
					if tr.kind == .Property {
						if imgui.MenuItem(fmt.ctprintf("%s  Edit Curve...%s", ICON_FA_BEZIER_CURVE, " (bezier)" if key.bezier else "")) do curveEdit = {true, ti, key.time}
						Drive_Item("anim.key-curve")
					}
					if imgui.MenuItem(fmt.ctprintf("%s  Delete Key", ICON_FA_TRASH)) {
						Editor_RecordUndo(state, "Delete key")
						e.Track_RemoveKey(tr, keyMenu.time)
						clear(&animKeys.sel)
					}
					Drive_Item("anim.key-delete")
				}
				imgui.EndPopup()
			}
			imgui.PopID()
		}
		// A box from an empty spot among the tracks; a drag of the keys.
		tracksMn := [2]f32{x0, ty}
		tracksMx := [2]f32{colX(x0, cols + 4), ty + rowsH}
		if canInteract && imgui.IsMouseClicked(.Left) && !keyHit && !imgui.IsAnyItemHovered() && point_in_rect(mouse, tracksMn, tracksMx) {
			animKeys.boxing = true
			animKeys.boxFrom = mouse
		}
		if animKeys.boxing {
			imgui.DrawList_AddRectFilled(dl, boxMn, boxMx, col_u32(ui_accent(0.12)))
			imgui.DrawList_AddRect(dl, boxMn, boxMx, col_u32(UI_ACCENT))
			if !imgui.IsMouseDown(.Left) {
				AnimKeys_BoxEnd()
				if len(animKeys.sel) > 0 do clear(&panel.sel)
			}
		}
		if animKeys.pressed {
			if imgui.IsMouseDown(.Left) {
				AnimKeys_DragUpdate(apn, anim, mouse.x, cellW)
				if animKeys.dragging do imgui.SetMouseCursor(.ResizeEW)
			} else {
				AnimKeys_DragEnd(state, anim)
			}
		}
	}
	CurveEditor_Render(state, apn, anim)
	if removeTrack >= 0 {
		Editor_RecordUndo(state, "Remove track")
		preview_restore(state)
		e.Animation_RemoveTrack(anim, removeTrack)
		clear(&animKeys.sel) // (track indices moved)
	}

	// Playhead.
	px := x0 + (f32(base + rel) + 0.5) * cellW
	imgui.DrawList_AddLine(dl, {px, origin.y}, {px, ty + rowsH}, col_u32(UI_ACCENT), 2)
	// Its knob on the ruler (dragging the ruler moves it).
	imgui.DrawList_AddTriangleFilled(dl, {px - 6, origin.y}, {px + 6, origin.y}, {px, origin.y + 8}, col_u32(UI_ACCENT))
	Drive_ItemRect("anim.playhead", {px - 6, origin.y}, {px + 6, origin.y + 18}, inWindow = true)
	imgui.EndChild()
	if sideW > 0 do side_panel(state, apn, anim, {sideW, max(avail.y, 40)})
}

// anim_preview: the animation playing in a box right of the timeline - its
// range, at its FPS, in its direction - with pause (then it shows the frame
// the timeline is on).
@(private = "file")
anim_preview :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation, size: [2]f32) {
	imgui.SameLine(0, UI_SPACE)
	imgui.PushStyleColorImVec4(.ChildBg, UI_BG_APP)
	defer imgui.PopStyleColor()
	if !imgui.BeginChild("##anim_preview", size, {}, {.NoScrollbar, .NoScrollWithMouse}) {
		imgui.EndChild()
		return
	}
	defer imgui.EndChild()
	length := max(anim.endFrame - anim.startFrame + 1, 1)
	if !panel.miniPaused {
		dt := f32(time.duration_seconds(time.tick_since(panel.miniTick)))
		panel.miniAccum += min(dt, 0.25) * max(e.AnimationPlayerNode_FPS(apn), 1)
		if panel.miniAccum >= f32(length) {
			// A non-looping animation holds its last frame a moment, then starts over.
			hold: f32 = 0 if anim.loop else max(e.AnimationPlayerNode_FPS(apn), 1) * 0.6
			if panel.miniAccum >= f32(length) + hold do panel.miniAccum = 0
		}
	}
	panel.miniTick = time.tick_now()
	f := min(int(panel.miniAccum), length - 1)
	if e.AnimationPlayerNode_IsReversed(apn, anim) do f = length - 1 - f
	frame := anim.startFrame + f
	if panel.miniPaused do frame = clamp(apn.currentFrame, 0, max(e.Animation_SourceCount(anim) - 1, 0))

	// Checkerboard behind the frame (transparency), the frame fitted.
	o := imgui.GetCursorScreenPos()
	dl := imgui.GetWindowDrawList()
	box := [2]f32{size.x, size.y - 26}
	CHECK :: f32(10)
	for y: f32 = 0; y < box.y; y += CHECK {
		for x: f32 = 0; x < box.x; x += CHECK {
			dark := (int(x / CHECK) + int(y / CHECK)) % 2 == 0
			c := UI_BG_PANEL if dark else UI_BG_RAISED
			imgui.DrawList_AddRectFilled(dl, o + {x, y}, o + {min(x + CHECK, box.x), min(y + CHECK, box.y)}, col_u32(c))
		}
	}
	draw_frame_thumb(dl, anim, frame, o + {6, 6}, o + box - {6, 6})
	Drive_ItemRect("anim.preview", o, o + box, inWindow = true)

	// Under it: pause / play and the frame shown.
	imgui.SetCursorScreenPos({o.x + 2, o.y + box.y + 2})
	if UI_IconButton(ICON_FA_PLAY if panel.miniPaused else ICON_FA_PAUSE, "anim.preview-toggle", "Play the preview" if panel.miniPaused else "Pause the preview (then it shows the timeline's frame)", size = 22) {
		panel.miniPaused = !panel.miniPaused
	}
	imgui.SameLine(0, 6)
	imgui.SetCursorPosY(imgui.GetCursorPosY() + 3)
	UI_DimText(fmt.tprintf("%s  %d / %d  ·  %.0f fps%s", anim.name, frame + 1, e.Animation_SourceCount(anim), e.AnimationPlayerNode_FPS(apn), "  ·  reverse" if e.AnimationPlayerNode_IsReversed(apn, anim) else ""))
}

// AnimationPanel_PreviewPaused: the preview is paused (drives).
AnimationPanel_PreviewPaused :: proc() -> bool {return panel.miniPaused}

// rename_state_machine_refs: states of machines driving `apn` that play
// `old` play `name` instead.
@(private = "file")
rename_state_machine_refs :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, old, name: string) {
	if state.activeScene == nil do return
	mgr := state.activeScene.manager
	for n in mgr.nodes {
		if n == nil || n.typeId != e.StateMachineNode do continue
		sm := cast(^e.StateMachineNode)n
		if e.StateMachine_Player(sm, mgr) != apn do continue
		for &s in sm.states do if s.animation == old do s.animation = strings.clone(name, sm.allocator)
	}
}

// anim_sound_settings_panel: controls routing, volume range, pitch range, pan range,
// positional 2D attenuation, voices, and SFX node target for an audio track (Issues #24 & #27).
@(private = "file")
anim_sound_settings_panel :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation, tr: ^e.Property_Track, size: [2]f32) {
	if tr == nil do return
	imgui.SameLine(0, UI_SPACE)
	imgui.PushStyleColorImVec4(.ChildBg, UI_BG_APP)
	defer imgui.PopStyleColor()
	if !imgui.BeginChild("##anim_sound_settings", size, {}, {}) {
		imgui.EndChild()
		return
	}
	defer imgui.EndChild()

	cfg := &tr.audioSettings

	// Title bar with close button
	imgui.TextUnformatted(fmt.ctprintf("%s  Sound Track Settings", ICON_FA_MUSIC))
	winW := imgui.GetWindowWidth()
	imgui.SameLine(max(winW - 28, 120))
	if UI_IconButton(ICON_FA_XMARK, "anim.sound-close", "Close sound settings", size = 20) {
		panel.selectedTrack = -1
		return
	}
	imgui.Separator()

	// Track Name
	UI_DimText("TRACK NAME")
	nameBuf: [64]u8
	curName := tr.name if tr.name != "" else "sounds"
	copy(nameBuf[:len(nameBuf) - 1], curName)
	imgui.SetNextItemWidth(-1)
	if imgui.InputTextWithHint("##sound_track_name", "Track Name (e.g. Footsteps)", cstring(raw_data(nameBuf[:])), len(nameBuf)) {
		Editor_RecordUndo(state, "Rename audio track")
		tr.name = strings.clone(string(cstring(raw_data(nameBuf[:]))), apn.allocator)
	}
	UI_Tooltip("Custom name for this sound track in the timeline")

	imgui.Spacing()
	UI_DimText("ROUTING")

	// Bus Picker
	buses := e.Mixer_Buses()
	curBus := cfg.bus if cfg.bus != "" else "SFX"
	imgui.SetNextItemWidth(140)
	if imgui.BeginCombo("Bus", strings.clone_to_cstring(curBus, context.temp_allocator)) {
		for b in buses {
			if imgui.Selectable(strings.clone_to_cstring(b.name, context.temp_allocator), b.name == curBus) {
				Editor_RecordUndo(state, "Change audio bus")
				cfg.bus = strings.clone(b.name, apn.allocator)
			}
		}
		imgui.EndCombo()
	}

	// SFX Node Target (optional SoundNode in scene)
	sfxNodes := make([dynamic]string, context.temp_allocator)
	append(&sfxNodes, "")
	if state.activeScene != nil && state.activeScene.manager != nil {
		for node in state.activeScene.manager.nodes {
			if node != nil && node.typeId == typeid_of(e.SoundNode) {
				path := e.Node_RelativePath(state.activeScene.manager, apn, node)
				append(&sfxNodes, path)
			}
		}
	}

	curSfx := cfg.sfxNode if cfg.sfxNode != "" else "(Direct playback)"
	imgui.SetNextItemWidth(140)
	if imgui.BeginCombo("SFX Node", strings.clone_to_cstring(curSfx, context.temp_allocator)) {
		for path in sfxNodes {
			label := "(Direct playback)" if path == "" else path
			if imgui.Selectable(strings.clone_to_cstring(label, context.temp_allocator), path == cfg.sfxNode) {
				Editor_RecordUndo(state, "Change SFX node target")
				cfg.sfxNode = strings.clone(path, apn.allocator)
			}
		}
		imgui.EndCombo()
	}
	UI_Tooltip("Optionally route playback through an existing SoundNode in the scene")

	imgui.Spacing()
	UI_DimText("VOLUME & PITCH")

	// Volume Min & Max
	imgui.TextUnformatted("Volume (Min / Max)")
	imgui.SetNextItemWidth(84)
	if imgui.DragFloat("##vol_min", &cfg.volumeMin, 0.01, 0, 2, "Min: %.2f") {
		Editor_RecordUndo(state, "Change volume min")
	}
	imgui.SameLine()
	imgui.SetNextItemWidth(84)
	if imgui.DragFloat("##vol_max", &cfg.volumeMax, 0.01, 0, 2, "Max: %.2f") {
		Editor_RecordUndo(state, "Change volume max")
	}
	UI_Tooltip("Volume range (equal for static volume, or range for randomized volume)")

	// Pitch Min & Max
	imgui.TextUnformatted("Pitch (Min / Max)")
	imgui.SetNextItemWidth(84)
	if imgui.DragFloat("##pitch_min", &cfg.pitchMin, 0.01, 0.1, 3, "Min: %.2f") {
		Editor_RecordUndo(state, "Change pitch min")
	}
	imgui.SameLine()
	imgui.SetNextItemWidth(84)
	if imgui.DragFloat("##pitch_max", &cfg.pitchMax, 0.01, 0.1, 3, "Max: %.2f") {
		Editor_RecordUndo(state, "Change pitch max")
	}
	UI_Tooltip("Pitch range (equal for static pitch, or range for randomized pitch)")

	// Pan Min & Max
	imgui.TextUnformatted("Stereo Pan (Min / Max)")
	imgui.SetNextItemWidth(84)
	if imgui.DragFloat("##pan_min", &cfg.panMin, 0.02, -1, 1, "Min: %.2f") {
		Editor_RecordUndo(state, "Change pan min")
	}
	imgui.SameLine()
	imgui.SetNextItemWidth(84)
	if imgui.DragFloat("##pan_max", &cfg.panMax, 0.02, -1, 1, "Max: %.2f") {
		Editor_RecordUndo(state, "Change pan max")
	}
	UI_Tooltip("Stereo panning range (-1.0 Left to +1.0 Right)")

	imgui.Spacing()
	UI_DimText("SPATIAL & VOICES")

	if imgui.Checkbox("Positional 2D Sound", &cfg.positional) {
		Editor_RecordUndo(state, "Toggle positional sound")
	}
	if cfg.positional {
		imgui.SetNextItemWidth(90)
		if imgui.DragFloat("Min Dist", &cfg.minDistance, 10, 0, 4000, "%.0f px") do Editor_RecordUndo(state, "Change min distance")
		imgui.SetNextItemWidth(90)
		if imgui.DragFloat("Max Dist", &cfg.maxDistance, 10, 1, 8000, "%.0f px") do Editor_RecordUndo(state, "Change max distance")
	}

	voices := i32(cfg.voices)
	imgui.SetNextItemWidth(100)
	if imgui.SliderInt("Voices", &voices, 1, e.AUDIO_MAX_VOICES) {
		Editor_RecordUndo(state, "Change voice limit")
		cfg.voices = int(voices)
	}
	UI_Tooltip("Max concurrent overlapping sounds for this track")

	imgui.Spacing()
	imgui.Separator()

	// Test Sound Button
	firstSound := ""
	for k in tr.keys {
		if k.text != "" {
			firstSound = k.text
			break
		}
	}
	if firstSound != "" {
		if UI_Button(fmt.tprintf("%s  Test (%s)", ICON_FA_PLAY, filepath.base(firstSound)), "anim.test-sound") {
			ctx := &state.game.gameContext
			rm := &state.game.resourceManager
			if s, ok := rm.loadAudioSound(rm, e.Project_ResolveAssetPath(ctx, firstSound)); ok {
				bus := e.Audio_BusFor(rm, s.filePath, "SFX")
				if cfg.bus != "" {
					if b := e.Mixer_BusIndex(cfg.bus); b >= 0 do bus = b
				}
				vol := cfg.volumeMin
				if cfg.volumeMax > cfg.volumeMin do vol = rand.float32_range(cfg.volumeMin, cfg.volumeMax)
				pitch := cfg.pitchMin
				if cfg.pitchMax > cfg.pitchMin do pitch = rand.float32_range(cfg.pitchMin, cfg.pitchMax)
				pan := cfg.panMin
				if cfg.panMax > cfg.panMin do pan = rand.float32_range(cfg.panMin, cfg.panMax)
				e.Mixer_PlaySound(s.pcm, bus, vol, pan, pitch, owner = s)
			}
		}
	} else {
		UI_DimText("No sounds placed on track yet")
	}
}

// anim_method_settings_panel: defines target node, attached script info, autogenerating
// or attaching scripts, method picker, argument fields, and open script shortcut (Issue #29).
@(private = "file")
anim_method_settings_panel :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation, tr: ^e.Property_Track, size: [2]f32) {
	if tr == nil do return
	imgui.SameLine(0, UI_SPACE)
	imgui.PushStyleColorImVec4(.ChildBg, UI_BG_APP)
	defer imgui.PopStyleColor()
	if !imgui.BeginChild("##anim_method_settings", size, {}, {}) {
		imgui.EndChild()
		return
	}
	defer imgui.EndChild()

	mgr := state.activeScene.manager if state.activeScene != nil else nil
	target: ^e.Node = apn
	if tr.target != "." && tr.target != "" && mgr != nil do target = e.Node_ResolvePath(mgr, apn, tr.target)

	// Title bar with close button
	imgui.TextUnformatted(fmt.ctprintf("%s  Script Call Settings", ICON_FA_CODE))
	winW := imgui.GetWindowWidth()
	imgui.SameLine(max(winW - 28, 120))
	if UI_IconButton(ICON_FA_XMARK, "anim.method-close", "Close script settings", size = 20) {
		panel.selectedTrack = -1
		return
	}
	imgui.Separator()

	// Target Node Info
	UI_DimText("TARGET NODE")
	targetName := target.name if target != nil else "(Node not found)"
	targetPath := tr.target if tr.target != "" else "."
	imgui.TextUnformatted(fmt.ctprintf("%s (%s)", targetName, targetPath))

	// Target Node Switcher
	if mgr != nil && len(mgr.nodes) > 1 {
		imgui.SetNextItemWidth(-1)
		if imgui.BeginCombo("##target_pick", strings.clone_to_cstring(fmt.tprintf("Change Target: %s", targetName), context.temp_allocator)) {
			for n in mgr.nodes {
				if n == nil do continue
				relPath := e.Node_RelativePath(mgr, apn, n)
				isSelected := relPath == tr.target || (relPath == "." && tr.target == "")
				if imgui.Selectable(strings.clone_to_cstring(fmt.tprintf("%s (%s)", n.name, relPath), context.temp_allocator), isSelected) {
					Editor_RecordUndo(state, "Change track target")
					tr.target = strings.clone(relPath, apn.allocator)
					target = n
				}
			}
			imgui.EndCombo()
		}
	}

	imgui.Spacing()
	UI_DimText("ATTACHED SCRIPT")

	scriptRel := node_script_rel(state, target)
	if scriptRel != "" {
		imgui.PushStyleColorImVec4(.Text, UI_SUCCESS)
		imgui.TextUnformatted(fmt.ctprintf("%s  %s", ICON_FA_FILE_CODE, filepath.base(scriptRel)))
		imgui.PopStyleColor()
		UI_DimText(scriptRel)

		if UI_Button(fmt.tprintf("%s  Open / Edit Script", ICON_FA_PEN_TO_SQUARE), "anim.open-script", {-1, 24}) {
			Editor_OpenScript(state, scriptRel)
		}

		scripts := Editor_ListProjectFiles(state, "", {".lua"})
		if len(scripts) > 0 {
			imgui.SetNextItemWidth(-1)
			if imgui.BeginCombo("##change_script", "Switch script...") {
				for s in scripts {
					if imgui.Selectable(strings.clone_to_cstring(s, context.temp_allocator), s == scriptRel) {
						Editor_RecordUndo(state, "Attach script")
						e.Script_AttachToNode(target, s, nil, &state.game.scriptManager)
					}
				}
				imgui.EndCombo()
			}
		}
	} else {
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextUnformatted(fmt.ctprintf("%s  No script attached to node!", ICON_FA_TRIANGLE_EXCLAMATION))
		imgui.PopStyleColor()
		UI_DimText("Calls events require a script on the target node to invoke methods.")

		imgui.Spacing()
		if target != nil {
			if UI_PrimaryButton(fmt.tprintf("%s  Create New Script for %s", ICON_FA_PLUS, target.name), "anim.create-script", {-1, 26}) {
				NewScriptDialog_Open(state, target)
			}
		}

		scripts := Editor_ListProjectFiles(state, "", {".lua"})
		if len(scripts) > 0 {
			imgui.SetNextItemWidth(-1)
			if imgui.BeginCombo("##attach_script", "Attach existing script...") {
				for s in scripts {
					if imgui.Selectable(strings.clone_to_cstring(s, context.temp_allocator)) {
						Editor_RecordUndo(state, "Attach script")
						if target != nil do e.Script_AttachToNode(target, s, nil, &state.game.scriptManager)
					}
				}
				imgui.EndCombo()
			}
		}
	}

	imgui.Spacing()
	imgui.Separator()
	UI_DimText("METHOD & ARGUMENTS")

	curRelFrame := f32(playhead(apn, anim))
	curTime := e.Animation_FrameTime(apn, anim, curRelFrame)
	key: ^e.Track_Key
	for &k in tr.keys {
		if abs(k.time - curTime) < e.TRACK_KEY_EPS {
			key = &k
			break
		}
	}

	if key != nil {
		imgui.TextUnformatted(fmt.ctprintf("Key at Frame %d", key_frame(apn, anim, key^) + 1))

		UI_DimText("Method Name:")
		methodBuf: [128]u8
		copy(methodBuf[:len(methodBuf) - 1], key.text)
		imgui.SetNextItemWidth(-1)
		if imgui.InputTextWithHint("##method_name_panel", "e.g. on_hit", cstring(raw_data(methodBuf[:])), len(methodBuf)) {
			Editor_RecordUndo(state, "Edit method name")
			key.text = strings.clone(string(cstring(raw_data(methodBuf[:]))), apn.allocator)
		}

		methods := Script_ListMethods(state, target)
		if len(methods) > 0 {
			imgui.SetNextItemWidth(-1)
			if imgui.BeginCombo("##method_pick_panel", strings.clone_to_cstring(fmt.tprintf("Pick method (%d available)", len(methods)), context.temp_allocator)) {
				for m in methods {
					if imgui.Selectable(strings.clone_to_cstring(m, context.temp_allocator), m == key.text) {
						Editor_RecordUndo(state, "Pick method")
						key.text = strings.clone(m, apn.allocator)
					}
				}
				imgui.EndCombo()
			}
		}

		UI_DimText("Argument (empty: passes frame number):")
		argBuf: [128]u8
		copy(argBuf[:len(argBuf) - 1], key.arg)
		imgui.SetNextItemWidth(-1)
		if imgui.InputTextWithHint("##arg_panel", "e.g. 2.5 or heavy", cstring(raw_data(argBuf[:])), len(argBuf)) {
			Editor_RecordUndo(state, "Edit method argument")
			key.arg = strings.clone(string(cstring(raw_data(argBuf[:]))), apn.allocator)
		}

		if scriptRel != "" && key.text != "" {
			methodExists := false
			for m in methods do if m == key.text { methodExists = true; break }
			if !methodExists {
				imgui.Spacing()
				imgui.PushStyleColorImVec4(.Text, UI_WARNING)
				imgui.TextUnformatted(fmt.ctprintf("Method '%s' not in script yet", key.text))
				imgui.PopStyleColor()
				if UI_Button(fmt.tprintf("%s  Generate %s in Script", ICON_FA_PLUS, key.text), "anim.gen-method", {-1, 24}) {
					Code_AddAnimationMethod(state, scriptRel, key.text)
				}
			}
		}

		if target != nil && key.text != "" {
			imgui.Spacing()
			if UI_Button(fmt.tprintf("%s  Test Call: %s()", ICON_FA_PLAY, key.text), "anim.test-call", {-1, 24}) {
				ctx := &state.game.gameContext
				if ctx.scriptManager != nil {
					e.Script_CallMethod(ctx.scriptManager, target, key.text, e.Track_EventArg(key^, key_frame(apn, anim, key^)), quiet = false)
					Editor_Log(state, .Info, "Called %s:%s()", target.name, key.text)
				}
			}
		}
	} else {
		imgui.TextUnformatted(fmt.ctprintf("No key at playhead (Frame %d)", int(curRelFrame) + 1))
		UI_DimText("Scrub to a frame with a key, or click below to add one at the playhead.")
		imgui.Spacing()
		if UI_Button(fmt.tprintf("%s  Add Method Key at Frame %d", ICON_FA_PLUS, int(curRelFrame) + 1), "anim.add-method-key", {-1, 26}) {
			Editor_RecordUndo(state, "Add method key")
			text := "on_animation_event"
			for k in tr.keys do if k.time < curTime && k.text != "" do text = k.text
			e.Track_SetEventKey(tr, curTime, text, apn.allocator)
		}
	}

	if target != nil && target.scriptInstance != nil {
		inst := cast(^e.ScriptInstance)target.scriptInstance
		if len(inst.properties) > 0 {
			imgui.Spacing()
			imgui.Separator()
			UI_DimText("SCRIPT PROPERTIES")
			for name, prop in inst.properties {
				#partial switch prop.type {
				case .Float:   imgui.TextUnformatted(fmt.ctprintf("  %s = %.2f", name, prop.valFloat))
				case .Int:     imgui.TextUnformatted(fmt.ctprintf("  %s = %d", name, prop.valInt))
				case .Boolean: imgui.TextUnformatted(fmt.ctprintf("  %s = %t", name, prop.valBool))
				case .String:  imgui.TextUnformatted(fmt.ctprintf("  %s = %q", name, prop.valString))
				case .Vector2: imgui.TextUnformatted(fmt.ctprintf("  %s = (%.2f, %.2f)", name, prop.valVec2.x, prop.valVec2.y))
				case:          imgui.TextUnformatted(fmt.ctprintf("  %s", name))
				}
			}
		}
	}
}
