package editor

import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Level Generator window (#142, phase 2): edits a .levelgen.json graph
// (engine/level_gen.odin) - double-click one in Assets, or + > New Level
// Generator. A dockable window:
//
//   canvas     the nodes, each with a thumbnail of its grid; drag a node by
//              its title; drag from an output (the dot on the right) onto an
//              input (left) to connect; right-click an input to disconnect;
//              right-click the canvas to add a node (type to search), a node
//              to duplicate / delete / make it the output; Shift- or
//              Cmd-click and a box on the empty canvas select several;
//              Delete removes the selection; Ctrl/Cmd+C / V / D copy, paste
//              (at the mouse, into any generator) and duplicate; comment
//              frames (titled, coloured) move the nodes inside them;
//              wheel pans, Ctrl/Cmd+wheel zooms, F frames everything.
//   side       the level's size, seed (dice: a new one) and output; the
//              selected node's parameters and (tile output) rules; a large
//              preview of the selected node's grid (else the output's).
//   toolbar    Save (Ctrl/Cmd+S), Undo / Redo (Ctrl/Cmd+Z, Shift+Z),
//              Apply to the selected TileMap (undoable, like any edit).
//
// After a change a background job evaluates a copy of the graph (#171):
// each node once, and only the nodes the change reaches - the others come
// from a cache kept between changes - while the window stays responsive.
// Undo keeps the graph's text before each change.
// ============================================================================

LEVEL_GEN_WINDOW :: "Level Generator###LevelGenWindow"

// levelGenFocused: the window has focus (its Save / Undo / Delete aren't the
// scene's; actions.odin).
levelGenFocused: bool

@(private = "file")
LGE_NODE_W :: f32(170)
@(private = "file")
LGE_THUMB :: f32(64)

@(private = "file")
lge: struct {
	open:      bool,
	path:      string, // project-relative (heap)
	graph:     e.Gen_Graph,
	loaded:    bool,
	dirty:     bool,
	undo:      [dynamic]string, // the graph's text before each change (heap)
	redo:      [dynamic]string,
	selected:  int, // node id (0 none): the one the side panel shows
	sel:       map[int]bool, // every selected node (holds `selected`)
	clickAdd:  bool, // the node click held Shift / Cmd (adds to the selection)
	boxing:    bool, // a selection box is being dragged on the empty canvas
	boxFrom:   [2]f32, // where it started (world)
	frameSel:  int, // the selected frame (index + 1; 0 none)
	frameDrag: int, // the frame being moved (index + 1)
	frameSize: int, // the frame being resized (index + 1)
	frameUndo: bool,
	frameNodes: [dynamic]int, // the nodes the moved frame carries
	titleBuf:  [128]u8, // the frame title being typed in
	titleFor:  int, // the frame (index + 1) titleBuf belongs to
	mouseWorld: [2]f32, // the mouse on the canvas (world), for Paste
	mouseOnCanvas: bool,
	centreWorld: [2]f32, // the canvas's middle (world): Paste from the toolbar
	searchBuf: [64]u8, // the add menu's search
	searchFocus: bool,
	colorUndo: bool, // a frame's colour pick recorded its undo step
	dragNode:  int,
	dragUndo:  bool,
	linkFrom:  int, // output being dragged from (node id)
	pan:       [2]f32,
	zoom:      f32,
	frame:     bool,
	version:   int, // bumped by every change (previews follow)
	thumbs:    map[int]rl.Texture2D, // node id -> its grid (for `thumbVersion`; also the large preview)
	thumbKeys: map[int]u64, // node id -> the cache key its thumbnail shows
	thumbVersion: int,
	scriptsStale: bool, // the script nodes' files are read again before the next evaluation
	terrainsSeen: int,  // terrainsVersion the graph's terrain files were read at
	errors:    map[int]string, // node id -> why it can't be evaluated (heap)
	chunked:   bool,          // a Level Generator in the scene makes this file's levels in chunks (#171)
	unsafe:    map[int]bool,  // then: the nodes that aren't chunk-safe (this frame's)
	cache:     e.Gen_Cache, // nodes' grids between evaluations (the job's while it runs)
	job:       ^Lge_Job,
	tilesets:  map[string]^Lge_Tileset, // tile outputs' tilesets by path (heap; nil texture: couldn't load)
	ctxWorld:  [2]f32,
	ctxNode:   int,
	closePrompt: bool,
	tilesBuf:  [128]u8, // the tiles of the rule being typed in ("3, 4")
	tilesFor:  [2]int,  // (node, rule) tilesBuf belongs to ({-1, -1}: none)
	layerBuf:  [64]u8,  // the layer name being typed in
	layerFor:  int,     // the node layerBuf belongs to (0: none)
	nameBuf:   [64]u8,  // a height output's map name being typed in (a level's, or the walls')
	nameFor:   [2]int,  // (node, level; -1: the walls) nameBuf belongs to ({0, 0}: none)
	wfcBrush:  i32,     // the tile a WFC node's sample is painted with (-1: the eraser)
}

// The node clipboard, shared by every generator opened in this editor
// session (the system clipboard holds the same text, so a paste works in
// the next session or another editor too).
@(private = "file")
lgeClip: string

// LevelGenEditor_Open shows a generator file (project-relative).
LevelGenEditor_Open :: proc(state: ^EditorState, rel: string) {
	if lge.loaded && lge.path == rel {
		lge.open = true
		imgui.SetWindowFocusStr(LEVEL_GEN_WINDOW)
		return
	}
	if lge.loaded && lge.dirty do lge_save(state) // (switching files keeps the edits)
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	data, err := os.read_entire_file(full, context.temp_allocator)
	if err != nil {
		Editor_Log(state, .Error, "Level Generator: can't read %s", rel)
		return
	}
	g, why := e.Gen_GraphParse(data)
	if why != "" {
		e.Gen_GraphDestroy(&g)
		Editor_Log(state, .Error, "Level Generator: %s: %s", rel, why)
		return
	}
	lge_unload()
	lge.graph = g
	lge.path = strings.clone(rel)
	lge.loaded, lge.open, lge.dirty = true, true, false
	lge.zoom, lge.frame = 1, true
	lge_select(0)
	lge.scriptsStale = true
	lge.version += 1
	imgui.SetWindowFocusStr(LEVEL_GEN_WINDOW)
}

// LevelGenEditor_New creates levels/<name>.levelgen.json (a cave) and opens it.
LevelGenEditor_New :: proc(state: ^EditorState, baseName := "new_level") -> string {
	if state.projectPath == "" do return ""
	dir, _ := filepath.join({state.projectPath, "levels"}, context.temp_allocator)
	_ = os.make_directory_all(dir)
	rel := ""
	for i := 1; ; i += 1 {
		name := baseName if i == 1 else fmt.tprintf("%s_%d", baseName, i)
		rel = fmt.tprintf("levels/%s.levelgen.json", name)
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		if !os.exists(full) do break
	}
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	if os.write_entire_file(full, transmute([]u8)string(e.GEN_TEMPLATE_CAVE)) != nil {
		Editor_Log(state, .Error, "Could not create %s", rel)
		return ""
	}
	Editor_InvalidateProjectFiles()
	Editor_Log(state, .Info, "Created %s", rel)
	LevelGenEditor_Open(state, rel)
	return strings.clone(rel, context.temp_allocator)
}

@(private = "file")
lge_unload :: proc() {
	if lge.loaded do e.Gen_GraphDestroy(&lge.graph)
	lge.graph = {}
	delete(lge.path)
	lge.path = ""
	lge.loaded = false
	for s in lge.undo do delete(s)
	clear(&lge.undo)
	for s in lge.redo do delete(s)
	clear(&lge.redo)
	lge_forget_previews()
	if lge.cache.entries != nil do e.Gen_CacheClear(&lge.cache) // (another file's node ids)
	lge_forget_tilesets()
}

// A tile output's tileset: its texture (the palette, swatches) and its
// pixels (the previews draw real tiles from them).
@(private = "file")
Lge_Tileset :: struct {
	tex:    rl.Texture2D,
	colors: [^]rl.Color, // (raylib's)
	size:   [2]int,
}

// lge_tileset: a project image loaded once (nil: none, or it can't be read).
@(private = "file")
lge_tileset :: proc(state: ^EditorState, path: string) -> ^Lge_Tileset {
	if path == "" do return nil
	if ts, ok := lge.tilesets[path]; ok do return ts if ts.tex.id != 0 else nil
	ts := new(Lge_Tileset)
	lge.tilesets[strings.clone(path)] = ts
	full, _ := filepath.join({state.projectPath, path}, context.temp_allocator)
	img := rl.LoadImage(strings.clone_to_cstring(full, context.temp_allocator))
	if img.data == nil do return nil
	defer rl.UnloadImage(img)
	rl.ImageFormat(&img, .UNCOMPRESSED_R8G8B8A8)
	ts.tex = rl.LoadTextureFromImage(img)
	rl.SetTextureFilter(ts.tex, .POINT)
	ts.colors = rl.LoadImageColors(img)
	ts.size = {int(img.width), int(img.height)}
	return ts
}

@(private = "file")
lge_forget_tilesets :: proc() {
	for path, ts in lge.tilesets {
		if ts.tex.id != 0 do rl.UnloadTexture(ts.tex)
		if ts.colors != nil do rl.UnloadImageColors(ts.colors)
		free(ts)
		delete(path)
	}
	clear(&lge.tilesets)
}

// The tileset's grid: columns and tiles of a tile size.
@(private = "file")
lge_tile_grid :: proc(ts: ^Lge_Tileset, tile: [2]int) -> (cols, count: int) {
	if ts == nil || tile.x <= 0 || tile.y <= 0 do return 0, 0
	cols = ts.size.x / tile.x
	return cols, cols * (ts.size.y / tile.y)
}

// lge_tile_uv: a tile's rectangle in its tileset texture (0..1).
@(private = "file")
lge_tile_uv :: proc(ts: ^Lge_Tileset, tile: [2]int, t: i32) -> (uv0, uv1: [2]f32) {
	cols, _ := lge_tile_grid(ts, tile)
	if cols == 0 do return
	x, y := int(t) % cols * tile.x, int(t) / cols * tile.y
	sz := [2]f32{f32(ts.size.x), f32(ts.size.y)}
	return {f32(x), f32(y)} / sz, {f32(x + tile.x), f32(y + tile.y)} / sz
}

// lge_tile_pixels: a tile output drawn with its tiles - `scale` pixels a
// cell (up to the tile's own size, the image at most ~1024 across); tiles
// the tileset doesn't have in their colours.
@(private = "file")
lge_tile_pixels :: proc(ts: ^Lge_Tileset, tile: [2]int, tiles: []i32, w, h: int) -> (pixels: []rl.Color, pw, ph: int) {
	cols, count := lge_tile_grid(ts, tile)
	s := clamp(1024 / max(w, h), 1, max(tile.x, tile.y, 1))
	pw, ph = w * s, h * s
	pixels = make([]rl.Color, pw * ph, context.temp_allocator)
	#no_bounds_check for t, i in tiles {
		if t < 0 do continue
		cx, cy := i % w, i / w
		if int(t) >= count {
			c := lge_tile_color(t)
			for py in 0 ..< s do for px in 0 ..< s do pixels[(cy * s + py) * pw + cx * s + px] = c
			continue
		}
		tx, ty := int(t) % cols * tile.x, int(t) / cols * tile.y
		for py in 0 ..< s {
			row := (ty + py * tile.y / s) * ts.size.x
			for px in 0 ..< s do pixels[(cy * s + py) * pw + cx * s + px] = ts.colors[row + tx + px * tile.x / s]
		}
	}
	return
}

// A tile output's tile size (its tile_w / tile_h).
@(private = "file")
lge_tile_size :: proc(n: ^e.Gen_Node) -> [2]int {
	return {max(int(e.Gen_Param(n, "tile_w")), 1), max(int(e.Gen_Param(n, "tile_h")), 1)}
}

@(private = "file")
lge_forget_previews :: proc() {
	lge_job_wait()
	for _, tex in lge.thumbs do if tex.id != 0 do rl.UnloadTexture(tex)
	clear(&lge.thumbs)
	clear(&lge.thumbKeys)
	for _, s in lge.errors do delete(s)
	clear(&lge.errors)
	lge.thumbVersion = -1
}

LevelGenEditor_Shutdown :: proc() {
	lge_unload()
	delete(lge.undo)
	delete(lge.redo)
	delete(lge.thumbs)
	delete(lge.thumbKeys)
	delete(lge.errors)
	delete(lge.tilesets)
	delete(lge.sel)
	delete(lge.frameNodes)
	delete(lgeClip)
	lgeClip = ""
	if lge.cache.entries != nil do e.Gen_CacheDestroy(&lge.cache)
	lge = {}
}

// --- changes and undo -----------------------------------------------------------------

// lge_change records the graph before an edit (call it first).
@(private = "file")
lge_change :: proc() {
	append(&lge.undo, e.Gen_GraphSerialize(&lge.graph))
	if len(lge.undo) > 100 {
		delete(lge.undo[0])
		ordered_remove(&lge.undo, 0)
	}
	for s in lge.redo do delete(s)
	clear(&lge.redo)
	lge.dirty = true
	lge.version += 1
}

// lge_edited: a widget changed the graph in place (the undo step was
// recorded when it became active).
@(private = "file")
lge_edited :: proc() {
	lge.dirty = true
	lge.version += 1
}

@(private = "file")
lge_restore :: proc(from, to: ^[dynamic]string) {
	if len(from) == 0 do return
	text := pop(from)
	defer delete(text)
	append(to, e.Gen_GraphSerialize(&lge.graph))
	g, why := e.Gen_GraphParse(transmute([]u8)text)
	if why != "" {
		e.Gen_GraphDestroy(&g)
		return
	}
	e.Gen_GraphDestroy(&lge.graph)
	lge.graph = g
	lge_prune_selection()
	lge.scriptsStale = true
	lge.dirty = true
	lge.version += 1
}

@(private = "file")
lge_save :: proc(state: ^EditorState) -> bool {
	if !lge.loaded || Editor_FormatBlocksSave(state, lge.path) do return false // (from a newer Rayzr: #326)
	full, _ := filepath.join({state.projectPath, lge.path}, context.temp_allocator)
	if os.write_entire_file(full, transmute([]u8)e.Gen_GraphSerialize(&lge.graph, context.temp_allocator)) != nil {
		Editor_Log(state, .Error, "Could not save %s", lge.path)
		return false
	}
	lge.dirty = false
	Editor_Log(state, .Info, "Saved %s", lge.path)
	return true
}

// Undo snapshot when a widget starts being edited (a drag is one step).
@(private = "file")
lge_undo_on_activate :: proc() {
	if imgui.IsItemActivated() do lge_change()
	if imgui.IsItemEdited() do lge_edited()
}

// lge_commit: an edit made after taking the graph's text (`before`, heap) -
// for edits that may turn out to change nothing (then: delete it instead).
@(private = "file")
lge_commit :: proc(before: string) {
	append(&lge.undo, before)
	for s in lge.redo do delete(s)
	clear(&lge.redo)
	lge_edited()
}

// --- selection, clipboard, frames --------------------------------------------------------

// lge_select: just this node (0: nothing); a frame's selection goes.
@(private = "file")
lge_select :: proc(id: int) {
	clear(&lge.sel)
	lge.selected = id
	if id != 0 do lge.sel[id] = true
	lge.frameSel = 0
}

// lge_select_add: another node, now the one the side panel shows.
@(private = "file")
lge_select_add :: proc(id: int) {
	lge.sel[id] = true
	lge.selected = id
	lge.frameSel = 0
}

// lge_select_toggle: Shift / Cmd+click - in or out of the selection.
@(private = "file")
lge_select_toggle :: proc(id: int) {
	if id not_in lge.sel {
		lge_select_add(id)
		return
	}
	delete_key(&lge.sel, id)
	if lge.selected == id {
		lge.selected = 0
		for other in lge.sel do lge.selected = other
	}
}

// lge_selection: the selected node ids in the graph's order (temp).
@(private = "file")
lge_selection :: proc() -> []int {
	ids := make([dynamic]int, context.temp_allocator)
	for n in lge.graph.nodes do if n.id in lge.sel do append(&ids, n.id)
	return ids[:]
}

// lge_prune_selection: nodes and frames gone (undo, a delete) leave it.
@(private = "file")
lge_prune_selection :: proc() {
	gone := make([dynamic]int, context.temp_allocator)
	for id in lge.sel do if e.Gen_FindNode(&lge.graph, id) == nil do append(&gone, id)
	for id in gone do delete_key(&lge.sel, id)
	if lge.selected != 0 && lge.selected not_in lge.sel {
		lge.selected = 0
		for other in lge.sel do lge.selected = other
	}
	if lge.frameSel > len(lge.graph.frames) do lge.frameSel = 0
	lge.frameDrag, lge.frameSize, lge.titleFor = 0, 0, 0
}

// lge_node_size: a node's box in world units (its height follows its inputs).
@(private = "file")
lge_node_size :: proc(n: ^e.Gen_Node) -> [2]f32 {
	rows := max(len(e.Gen_NodeInfo(n).inputs), 1)
	return {LGE_NODE_W, 28 + f32(rows) * 20 + LGE_THUMB + 12}
}

// lge_copy puts the selected nodes on the clipboard (links between them
// kept).
@(private = "file")
lge_copy :: proc(state: ^EditorState) {
	ids := lge_selection()
	if len(ids) == 0 do return
	text := e.Gen_CopyNodes(&lge.graph, ids)
	if text == "" do return
	delete(lgeClip)
	lgeClip = text
	imgui.SetClipboardText(strings.clone_to_cstring(text, context.temp_allocator))
	Editor_Log(state, .Info, "Copied %d node%s", len(ids), "" if len(ids) == 1 else "s")
}

// lge_clip_text: nodes to paste - the system clipboard's when it holds
// some (copied in another editor or session), else this session's.
@(private = "file")
lge_clip_text :: proc() -> string {
	if c := imgui.GetClipboardText(); c != nil && e.Gen_IsNodesClip(string(c)) do return string(c)
	return lgeClip
}

// lge_paste_text adds nodes from clipboard text with their top-left at
// `at` (world) and selects them; one undo step.
@(private = "file")
lge_paste_text :: proc(state: ^EditorState, text: string, at: [2]f32) -> bool {
	if text == "" do return false
	before := e.Gen_GraphSerialize(&lge.graph)
	ids, err := e.Gen_PasteNodes(&lge.graph, text, at, context.temp_allocator)
	if err != "" {
		delete(before)
		Editor_Log(state, .Warn, "Level Generator: can't paste: %s", err)
		return false
	}
	lge_commit(before)
	lge_select(0)
	for id in ids do lge_select_add(id)
	lge.scriptsStale = true // (pasted script nodes' files)
	return true
}

// lge_paste: at the mouse when it's on the canvas, else the canvas's middle.
@(private = "file")
lge_paste :: proc(state: ^EditorState, at: Maybe([2]f32) = nil) {
	pos := at.? or_else (lge.mouseWorld if lge.mouseOnCanvas else lge.centreWorld)
	lge_paste_text(state, lge_clip_text(), pos)
}

// lge_duplicate copies the selection beside itself (the clipboard is left
// alone).
@(private = "file")
lge_duplicate :: proc(state: ^EditorState) {
	ids := lge_selection()
	if len(ids) == 0 do return
	text := e.Gen_CopyNodes(&lge.graph, ids, context.temp_allocator)
	lo := e.Gen_FindNode(&lge.graph, ids[0]).pos
	for id in ids do lo = {min(lo.x, e.Gen_FindNode(&lge.graph, id).pos.x), min(lo.y, e.Gen_FindNode(&lge.graph, id).pos.y)}
	lge_paste_text(state, text, lo + {30, 30})
}

// lge_delete_selection removes the selected frame, else the selected nodes.
@(private = "file")
lge_delete_selection :: proc() {
	if i := lge.frameSel - 1; i >= 0 && i < len(lge.graph.frames) {
		lge_change()
		e.Gen_RemoveFrame(&lge.graph, i)
		lge.frameSel = 0
		return
	}
	ids := lge_selection()
	if len(ids) == 0 do return
	lge_change()
	for id in ids do e.Gen_RemoveNode(&lge.graph, id)
	lge_select(0)
}

// lge_add_frame: a frame around the selected nodes (`aroundSelection`), else an empty one at
// `at` (world); selected, for its title and colour in the side panel.
@(private = "file")
lge_add_frame :: proc(at: [2]f32, aroundSelection := true) {
	ids := lge_selection() if aroundSelection else nil
	pos, size := at, [2]f32{320, 200}
	if len(ids) > 0 {
		n0 := e.Gen_FindNode(&lge.graph, ids[0])
		lo, hi := n0.pos, n0.pos + lge_node_size(n0)
		for id in ids {
			n := e.Gen_FindNode(&lge.graph, id)
			lo = {min(lo.x, n.pos.x), min(lo.y, n.pos.y)}
			hi = {max(hi.x, n.pos.x + lge_node_size(n).x), max(hi.y, n.pos.y + lge_node_size(n).y)}
		}
		// (Room for the title above the nodes.)
		pos, size = lo - {20, 44}, hi - lo + {40, 64}
	}
	lge_change()
	e.Gen_AddFrame(&lge.graph, pos, size)
	lge_select(0)
	lge.frameSel = len(lge.graph.frames)
}

// lge_frame_nodes: the nodes inside a frame (their middle in its box).
@(private = "file")
lge_frame_nodes :: proc(f: e.Gen_Frame, into: ^[dynamic]int) {
	clear(into)
	for &n in lge.graph.nodes {
		c := n.pos + lge_node_size(&n) * 0.5
		if c.x >= f.pos.x && c.x <= f.pos.x + f.size.x && c.y >= f.pos.y && c.y <= f.pos.y + f.size.y do append(into, n.id)
	}
}

// --- previews ---------------------------------------------------------------------------

// The largest level whose nodes are previewed (cells).
@(private = "file")
LGE_PREVIEW_MAX :: 1024 * 1024

// A background evaluation of the graph for the previews: a copy of it (the
// window edits the original meanwhile), every node evaluated through
// lge.cache, and why each failing node failed. What the job and the window
// share is in the (thread-safe) heap allocator; the job has its own temp
// allocator.
@(private = "file")
Lge_Job :: struct {
	thread:  ^thread.Thread,
	graph:   e.Gen_Graph,
	version: int,
	errors:  map[int]string, // (heap)
	done:    bool, // (atomic)
}

@(private = "file")
lge_job_run :: proc(t: ^thread.Thread) {
	context.allocator = e.Engine_HeapAllocator()
	j := cast(^Lge_Job)t.data
	e.Gen_CachePrune(&lge.cache, &j.graph)
	for n in j.graph.nodes {
		if _, err := e.Gen_Evaluate(&j.graph, n.id, 0, context.temp_allocator, &lge.cache); err != "" do j.errors[n.id] = strings.clone(err)
		free_all(context.temp_allocator)
	}
	sync.atomic_store(&j.done, true)
}

// lge_job_wait: the running job finished and freed (its results dropped).
@(private = "file")
lge_job_wait :: proc() {
	j := lge.job
	if j == nil do return
	thread.destroy(j.thread) // (joins)
	lge_job_free(j)
	lge.job = nil
}

@(private = "file")
lge_job_free :: proc(j: ^Lge_Job) {
	heap := e.Engine_HeapAllocator()
	e.Gen_GraphDestroy(&j.graph)
	for _, s in j.errors do delete(s, heap)
	delete(j.errors)
	free(j, heap)
}

// lge_grid_pixels: a grid as grey values (0 black .. 1 white), or for a tile
// output its tiles in colours (none: transparent).
@(private = "file")
lge_grid_pixels :: proc(g: ^e.Gen_Graph, n: ^e.Gen_Node, grid: e.Gen_Grid, pixels: []rl.Color) {
	if e.Gen_WritesComponents(n) {
		// (A colour per rule: where its component goes.)
		for k, i in e.Gen_ComponentsOf(n, grid, context.temp_allocator) do pixels[i] = lge_tile_color(i32(k)) if k >= 0 else {}
		return
	}
	if n.kind == .Tile_Output {
		for t, i in e.Gen_TilesOf(n, grid, g.seed, context.temp_allocator) do pixels[i] = lge_tile_color(t) if t >= 0 else {}
		return
	}
	if n.kind == .Height_Output {
		lge_height_pixels(n, grid, pixels)
		return
	}
	for v, i in grid.v {
		c := u8(clamp(v, 0, 1) * 255)
		pixels[i] = {c, c, c, 255}
	}
}

// lge_tile_color: a stable colour per tile index.
@(private = "file")
lge_tile_color :: proc(t: i32) -> rl.Color {
	h := f32((u32(t) * 2654435761) % 360)
	return rl.ColorFromHSV(h, 0.55, 0.9)
}

// lge_refresh: after a change, a job evaluates the graph; when it is done,
// the thumbnails of the nodes whose grids changed (and the tile outputs,
// whose rules aren't in their keys) are updated, and the errors replaced.
@(private = "file")
lge_refresh :: proc(state: ^EditorState) {
	if lge.cache.entries == nil do e.Gen_CacheInit(&lge.cache, e.Engine_HeapAllocator())
	if j := lge.job; j != nil {
		if !sync.atomic_load(&j.done) do return
		thread.destroy(j.thread)
		lge.job = nil
		defer lge_job_free(j)
		for _, s in lge.errors do delete(s)
		clear(&lge.errors)
		for id, why in j.errors do lge.errors[id] = strings.clone(why)
		// Thumbnails of nodes gone (or failing now) go.
		gone := make([dynamic]int, context.temp_allocator)
		for id in lge.thumbs do if e.Gen_FindNode(&j.graph, id) == nil || id in j.errors do append(&gone, id)
		for id in gone {
			if tex := lge.thumbs[id]; tex.id != 0 do rl.UnloadTexture(tex)
			delete_key(&lge.thumbs, id)
			delete_key(&lge.thumbKeys, id)
		}
		for &n in j.graph.nodes {
			if n.id in j.errors do continue
			en, ok := lge.cache.entries[n.id]
			if !ok do continue
			tex, have := lge.thumbs[n.id]
			if have && lge.thumbKeys[n.id] == en.key && n.kind != .Tile_Output && n.kind != .WFC && n.kind != .Height_Output && tex.width == i32(en.grid.w) && tex.height == i32(en.grid.h) do continue
			// (A tile output with its tileset: drawn with its tiles. A WFC
			// node's tile ids: with the tileset of the output it feeds.)
			pixels: []rl.Color
			pw, ph := en.grid.w, en.grid.h
			if n.kind == .WFC {
				ids := make([]i32, len(en.grid.v), context.temp_allocator)
				for v, i in en.grid.v do ids[i] = i32(math.round(v)) if v >= 0 else -1
				out := lge_wfc_output(&j.graph, n.id)
				if ts := lge_tileset(state, out.tileset if out != nil else ""); ts != nil {
					pixels, pw, ph = lge_tile_pixels(ts, lge_tile_size(out), ids, en.grid.w, en.grid.h)
				} else {
					pixels = make([]rl.Color, len(ids), context.temp_allocator)
					for t, i in ids do pixels[i] = lge_tile_color(t) if t >= 0 else {}
				}
			} else if ts := lge_tileset(state, n.tileset); n.kind == .Tile_Output && !e.Gen_WritesComponents(&n) && ts != nil {
				pixels, pw, ph = lge_tile_pixels(ts, lge_tile_size(&n), e.Gen_TilesOf(&n, en.grid, j.graph.seed, context.temp_allocator, Editor_Terrains(state, n.tileset)), en.grid.w, en.grid.h)
			} else {
				pixels = make([]rl.Color, len(en.grid.v), context.temp_allocator)
				lge_grid_pixels(&j.graph, &n, en.grid, pixels)
			}
			if have && tex.width == i32(pw) && tex.height == i32(ph) {
				rl.UpdateTexture(tex, raw_data(pixels))
			} else {
				if have && tex.id != 0 do rl.UnloadTexture(tex)
				img := rl.Image{data = raw_data(pixels), width = i32(pw), height = i32(ph), mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
				tex = rl.LoadTextureFromImage(img)
				rl.SetTextureFilter(tex, .POINT)
				lge.thumbs[n.id] = tex
			}
			lge.thumbKeys[n.id] = en.key
		}
		lge.thumbVersion = j.version
	}
	if lge.thumbVersion == lge.version do return
	if lge.graph.size.x * lge.graph.size.y > LGE_PREVIEW_MAX {
		// (Too big to preview every node.)
		for _, tex in lge.thumbs do if tex.id != 0 do rl.UnloadTexture(tex)
		clear(&lge.thumbs)
		clear(&lge.thumbKeys)
		lge.thumbVersion = lge.version
		return
	}
	// A copy of the graph (with its scripts' text) for the job.
	heap := e.Engine_HeapAllocator()
	g, why := e.Gen_GraphParse(transmute([]u8)e.Gen_GraphSerialize(&lge.graph, context.temp_allocator), heap)
	if why != "" {
		e.Gen_GraphDestroy(&g)
		lge.thumbVersion = lge.version
		return
	}
	for path, text in lge.graph.scripts do e.Gen_SetScriptSource(&g, path, text)
	j := new(Lge_Job, heap)
	j.version = lge.version
	j.graph = g
	j.errors = make(map[int]string, heap)
	j.thread = thread.create(lge_job_run)
	j.thread.data = j
	lge.job = j
	thread.start(j.thread)
}

// --- the window -------------------------------------------------------------------------

LevelGenEditor_Render :: proc(state: ^EditorState) {
	levelGenFocused = false
	if !lge.open || !lge.loaded do return
	// First shown: centred in the editor, as big as fits (up to 1040 x 620).
	vp := imgui.GetMainViewport()
	imgui.SetNextWindowPos(vp.WorkPos + vp.WorkSize * 0.5, .FirstUseEver, {0.5, 0.5})
	imgui.SetNextWindowSize({min(1040, vp.WorkSize.x - 40), min(620, vp.WorkSize.y - 40)}, .FirstUseEver)
	open := true
	title := fmt.ctprintf("%s  %s%s###LevelGenWindow", ICON_FA_SHUFFLE, filepath.base(lge.path), " *" if lge.dirty else "")
	visible := imgui.Begin(title, &open, {.NoScrollbar, .NoScrollWithMouse})
	defer imgui.End()
	{
		// (The title bar's close button, for drives.)
		wp, ws := imgui.GetWindowPos(), imgui.GetWindowSize()
		st := imgui.GetStyle()
		fs := imgui.GetFontSize()
		x := wp.x + ws.x - st.FramePadding.x - fs
		Drive_ItemRect("lge.close", {x, wp.y + st.FramePadding.y}, {x + fs, wp.y + st.FramePadding.y + fs})
	}
	// Shown again partly off the editor (a layout saved on a bigger screen):
	// moved back inside it.
	if imgui.IsWindowAppearing() && !imgui.IsWindowDocked() {
		pos, size := imgui.GetWindowPos(), imgui.GetWindowSize()
		lo, hi := vp.WorkPos, vp.WorkPos + vp.WorkSize
		fixed := [2]f32{clamp(pos.x, lo.x, max(hi.x - size.x, lo.x)), clamp(pos.y, lo.y, max(hi.y - size.y, lo.y))}
		if fixed != pos do imgui.SetWindowPos(fixed)
	}
	if !open {
		if lge.dirty do lge.closePrompt = true
		else do lge.open = false
	}
	lge_close_prompt(state)
	if !visible do return
	levelGenFocused = imgui.IsWindowFocused({.RootWindow, .ChildWindows})
	Drive_Window("levelgen")
	if lge.scriptsStale || lge.terrainsSeen != terrainsVersion {
		e.Gen_LoadScripts(&lge.graph, &state.game.gameContext) // (script nodes' files: opened, picked, reloaded)
		e.Gen_LoadTerrains(&lge.graph, &state.game.gameContext) // (tile outputs' tilesets' terrains; saved in the Terrain Tiles window)
		if lge.terrainsSeen != terrainsVersion do lge.version += 1 // (previews: auto-tiled again)
		lge.scriptsStale = false
		lge.terrainsSeen = terrainsVersion
	}
	lge_refresh(state)
	lge_keys(state)
	lge_toolbar(state)
	lge.chunked = lge_chunked_users(state, lge.path) > 0
	clear(&lge.unsafe)
	if lge.chunked {
		info := e.Gen_ChunkInfo(&lge.graph, context.temp_allocator)
		for id in info.unsafe do lge.unsafe[id] = true
		lge_chunk_note(&lge.graph, "lge.chunks")
	}
	avail := imgui.GetContentRegionAvail()
	// (NoMove: dragging a link or a node on the canvas must not move the
	// floating window - #334.)
	if imgui.BeginChild("##lge_canvas", {max(avail.x - 300, 200), avail.y}, {.ResizeX}, {.NoScrollbar, .NoScrollWithMouse, .NoMove}) do lge_canvas(state)
	imgui.EndChild()
	imgui.SameLine(0, 6)
	if imgui.BeginChild("##lge_side", {0, avail.y}, {}, {}) do lge_side(state)
	imgui.EndChild()
}

@(private = "file")
lge_close_prompt :: proc(state: ^EditorState) {
	if lge.closePrompt {
		imgui.OpenPopup("Unsaved Generator###LgeClose")
		lge.closePrompt = false
	}
	if !imgui.BeginPopupModal("Unsaved Generator###LgeClose", nil, {.NoTitleBar, .AlwaysAutoResize}) do return
	UI_PanelTitle(ICON_FA_TRIANGLE_EXCLAMATION, fmt.tprintf("Save %s?", filepath.base(lge.path)))
	imgui.Dummy({0, 4})
	if UI_PrimaryButton("Save", "lge.close-save", {96, 0}) {
		if lge_save(state) do lge.open = false
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Discard", "lge.close-discard", {96, 0}) {
		path := strings.clone(lge.path, context.temp_allocator)
		lge_unload()
		lge.open = false
		Editor_Log(state, .Info, "Closed %s without saving", path)
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Cancel", "lge.close-cancel", {96, 0}) || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
	imgui.EndPopup()
}

@(private = "file")
lge_keys :: proc(state: ^EditorState) {
	if !imgui.IsWindowFocused({.RootWindow, .ChildWindows}) do return
	io := imgui.GetIO()
	cmd := io.KeyCtrl || io.KeySuper
	if cmd && imgui.IsKeyPressed(.S) do lge_save(state)
	if cmd && imgui.IsKeyPressed(.Z) {
		if io.KeyShift do lge_restore(&lge.redo, &lge.undo)
		else do lge_restore(&lge.undo, &lge.redo)
	}
	if io.WantTextInput do return
	if imgui.IsKeyPressed(.Delete) || imgui.IsKeyPressed(.Backspace) do lge_delete_selection()
	if cmd && imgui.IsKeyPressed(.C) do lge_copy(state)
	if cmd && imgui.IsKeyPressed(.V) do lge_paste(state)
	if cmd && imgui.IsKeyPressed(.D) do lge_duplicate(state)
	if cmd && imgui.IsKeyPressed(.A) {
		lge_select(0)
		for n in lge.graph.nodes do lge_select_add(n.id)
	}
}

@(private = "file")
lge_toolbar :: proc(state: ^EditorState) {
	if UI_IconButton(ICON_FA_FLOPPY_DISK, "lge.save", "Save (Ctrl/Cmd+S)", lge.dirty, 26) do lge_save(state)
	imgui.SameLine(0, 2)
	imgui.BeginDisabled(len(lge.undo) == 0)
	if UI_IconButton(ICON_FA_ROTATE_LEFT, "lge.undo", "Undo (Ctrl/Cmd+Z)", size = 26) do lge_restore(&lge.undo, &lge.redo)
	imgui.EndDisabled()
	imgui.SameLine(0, 2)
	imgui.BeginDisabled(len(lge.redo) == 0)
	if UI_IconButton(ICON_FA_ROTATE_RIGHT, "lge.redo", "Redo (Ctrl/Cmd+Shift+Z)", size = 26) do lge_restore(&lge.redo, &lge.undo)
	imgui.EndDisabled()
	imgui.SameLine(0, 10)
	// The clipboard and frames (the canvas's menus and keys do the same).
	imgui.BeginDisabled(len(lge.sel) == 0)
	if UI_IconButton(ICON_FA_COPY, "lge.copy", "Copy the selected nodes and the links between them (Ctrl/Cmd+C) - paste them here or into another generator", size = 26) do lge_copy(state)
	imgui.EndDisabled()
	imgui.SameLine(0, 2)
	// (Not disabled when empty: that would read the system clipboard every frame.)
	if UI_IconButton(ICON_FA_PASTE, "lge.paste", "Paste copied nodes (Ctrl/Cmd+V: at the mouse) - new ids, the links between them kept", size = 26) do lge_paste(state)
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_OBJECT_GROUP, "lge.frame", "Add a comment frame around the selected nodes (none selected: an empty one); drag its title to move the nodes inside, its corner to resize", size = 26) do lge_add_frame(lge.centreWorld - {160, 100})
	imgui.SameLine(0, 10)
	tm := state.selectedNode if state.selectedNode != nil && state.selectedNode.typeId == e.TileMapNode else nil
	imgui.BeginDisabled(tm == nil)
	if UI_Button(fmt.tprintf("%s  Apply to TileMap", ICON_FA_TABLE_CELLS), "lge.apply") && tm != nil {
		Editor_RecordUndo(state, "Generate level")
		if err := e.Gen_ApplyTileMap(&lge.graph, cast(^e.TileMapNode)tm, 0, &state.game.gameContext, state.activeScene); err != "" {
			Editor_Log(state, .Error, "Level Generator: %s", err)
		} else {
			Editor_Log(state, .Info, "Generated %s into %s (seed %d)", filepath.base(lge.path), tm.name, lge.graph.seed)
		}
	}
	imgui.EndDisabled()
	UI_Tooltip("Writes the level (tiles and entities) into the TileMap selected in the scene (Ctrl/Cmd+Z undoes it)" if tm != nil else "Select a TileMap in the scene to write the level into it")
	// The Level tab's current IntGrid layer (an LDtk level being edited).
	imgui.SameLine(0, 4)
	doc := GlobalLevel.doc
	intGrid := doc != nil && GlobalLevel.level >= 0 && GlobalLevel.level < len(doc.levels) && GlobalLevel.layer >= 0 && GlobalLevel.layer < len(doc.levels[GlobalLevel.level].layers)
	if intGrid {
		ly := doc.levels[GlobalLevel.level].layers[GlobalLevel.layer]
		intGrid = ly.def >= 0 && doc.layerDefs[ly.def].type == .IntGrid
	}
	imgui.BeginDisabled(!intGrid)
	if UI_Button(fmt.tprintf("%s  Apply to LDtk Layer", ICON_FA_LAYER_GROUP), "lge.apply-ldtk") && intGrid {
		if err := e.Gen_ApplyIntGrid(&lge.graph, doc, GlobalLevel.level, GlobalLevel.layer); err != "" {
			Editor_Log(state, .Error, "Level Generator: %s", err)
		} else {
			Editor_Log(state, .Info, "Generated %s into the LDtk layer %s", filepath.base(lge.path), doc.layerDefs[doc.levels[GlobalLevel.level].layers[GlobalLevel.layer].def].identifier)
		}
	}
	imgui.EndDisabled()
	UI_Tooltip("Writes the tile output into the IntGrid layer picked in the Level tab: its tiles are the IntGrid values; the auto layers draw the rest (the Level tab's undo takes it back)" if intGrid else "Pick an IntGrid layer of a level in the Level tab")
	imgui.SameLine(0, 10)
	UI_DimText(fmt.tprintf("%d nodes · %d x %d cells", len(lge.graph.nodes), lge.graph.size.x, lge.graph.size.y))
}

@(private = "file")
lge_to_screen :: proc(origin, w: [2]f32) -> [2]f32 {return origin + lge.pan + w * lge.zoom}

@(private = "file")
lge_to_world :: proc(origin, s: [2]f32) -> [2]f32 {return (s - origin - lge.pan) / lge.zoom}

// lge_node_rect: a node's box on screen, and its height in world units.
@(private = "file")
lge_node_rect :: proc(origin: [2]f32, n: ^e.Gen_Node) -> (mn, mx: [2]f32) {
	rows := max(len(e.Gen_NodeInfo(n).inputs), 1)
	h := 28 + f32(rows) * 20 + LGE_THUMB + 12
	mn = lge_to_screen(origin, n.pos)
	mx = mn + [2]f32{LGE_NODE_W, h} * lge.zoom
	return
}

@(private = "file")
lge_in_port :: proc(mn: [2]f32, i: int) -> [2]f32 {return mn + [2]f32{0, 28 + f32(i) * 20 + 10} * lge.zoom}

@(private = "file")
lge_out_port :: proc(mn, mx: [2]f32) -> [2]f32 {return {mx.x, mn.y + 38 * lge.zoom}}

@(private = "file")
lge_canvas :: proc(state: ^EditorState) {
	g := &lge.graph
	dl := imgui.GetWindowDrawList()
	origin := imgui.GetCursorScreenPos()
	size := imgui.GetContentRegionAvail()
	io := imgui.GetIO()
	mouse := [2]f32{io.MousePos.x, io.MousePos.y}
	hovered := imgui.IsWindowHovered()
	imgui.DrawList_AddRectFilled(dl, origin, origin + size, col_u32(CODE_BG))
	Drive_ItemRect("lge.canvas", origin, origin + size, inWindow = true)
	step := 40 * lge.zoom
	if step > 8 {
		gx := math.mod(lge.pan.x, step)
		for x := origin.x + gx; x < origin.x + size.x; x += step do imgui.DrawList_AddLine(dl, {x, origin.y}, {x, origin.y + size.y}, col_u32(ui_line(0.03)))
		gy := math.mod(lge.pan.y, step)
		for y := origin.y + gy; y < origin.y + size.y; y += step do imgui.DrawList_AddLine(dl, {origin.x, y}, {origin.x + size.x, y}, col_u32(ui_line(0.03)))
	}
	if (lge.frame && size.x > 120 && size.y > 80) || (hovered && imgui.IsKeyPressed(.F) && !io.WantTextInput) {
		lge.frame = false
		if len(g.nodes) > 0 {
			mn, mx := g.nodes[0].pos, g.nodes[0].pos
			for n in g.nodes {
				mn = {min(mn.x, n.pos.x), min(mn.y, n.pos.y)}
				mx = {max(mx.x, n.pos.x + LGE_NODE_W), max(mx.y, n.pos.y + 160)}
			}
			ext := mx - mn + {80, 80}
			lge.zoom = clamp(min(size.x / ext.x, size.y / ext.y), 0.3, 1.0)
			lge.pan = (size - (mx - mn) * lge.zoom) * 0.5 - mn * lge.zoom
		}
	}
	if hovered && (io.MouseWheel != 0 || io.MouseWheelH != 0) {
		if io.KeyCtrl || io.KeySuper {
			before := lge_to_world(origin, mouse)
			lge.zoom = clamp(lge.zoom * (1 + io.MouseWheel * 0.1), 0.3, 2)
			lge.pan += mouse - lge_to_screen(origin, before)
		} else if io.KeyShift {
			lge.pan.x += io.MouseWheel * 30
		} else {
			lge.pan += {io.MouseWheelH * 30, io.MouseWheel * 30}
		}
	}
	if hovered && imgui.IsMouseDragging(.Middle) do lge.pan += {io.MouseDelta.x, io.MouseDelta.y}
	// (Where Ctrl/Cmd+V and the toolbar's Paste put nodes.)
	lge.mouseWorld = lge_to_world(origin, mouse)
	lge.mouseOnCanvas = hovered
	lge.centreWorld = lge_to_world(origin, origin + size * 0.5)

	// Comment frames, under everything: a header to drag (carrying the nodes
	// inside), a corner to resize.
	hoverFrame, hoverFrameSize := 0, 0
	for f, i in g.frames {
		mn, mx := lge_to_screen(origin, f.pos), lge_to_screen(origin, f.pos + f.size)
		head := [2]f32{mx.x, mn.y + 24 * lge.zoom}
		c := f.color
		imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32({c.r, c.g, c.b, c.a * 0.14}), 6)
		imgui.DrawList_AddRectFilled(dl, mn, head, col_u32({c.r, c.g, c.b, c.a * 0.6}), 6, imgui.DrawFlags_RoundCornersTop)
		selF := lge.frameSel == i + 1
		imgui.DrawList_AddRect(dl, mn, mx, col_u32(UI_ACCENT if selF else imgui.Vec4{c.r, c.g, c.b, c.a * 0.8}), 6, imgui.DrawFlags(0), 2 if selF else 1)
		if lge.zoom > 0.4 do imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, 14 * lge.zoom, mn + {8, 4} * lge.zoom, col_u32(UI_TEXT), fmt.ctprintf("%s", f.title))
		grip := mx - [2]f32{14, 14} * lge.zoom
		imgui.DrawList_AddTriangleFilled(dl, {mx.x, grip.y}, mx, {grip.x, mx.y}, col_u32({c.r, c.g, c.b, 0.9}))
		Drive_ItemRect(fmt.tprintf("lge.frame:%d", i), mn, head, inWindow = true)
		Drive_ItemRect(fmt.tprintf("lge.frame-size:%d", i), grip, mx, inWindow = true)
		if !hovered do continue
		if mouse.x >= grip.x && mouse.x <= mx.x && mouse.y >= grip.y && mouse.y <= mx.y do hoverFrameSize = i + 1
		else if mouse.x >= mn.x && mouse.x <= head.x && mouse.y >= mn.y && mouse.y <= head.y do hoverFrame = i + 1
	}

	// Links: from a node's output to the inputs reading it.
	for &n in g.nodes {
		mn, _ := lge_node_rect(origin, &n)
		for src, i in n.inputs[:len(e.Gen_NodeInfo(&n).inputs)] {
			if src == 0 do continue
			s := e.Gen_FindNode(g, src)
			if s == nil do continue
			smn, smx := lge_node_rect(origin, s)
			a, b := lge_out_port(smn, smx), lge_in_port(mn, i)
			d := max(abs(b.x - a.x) * 0.5, 30)
			imgui.DrawList_AddBezierCubic(dl, a, a + {d, 0}, b - {d, 0}, b, col_u32(ui_line(0.5)), 2 * lge.zoom)
		}
	}

	// Nodes.
	hoverNode, hoverIn, hoverInPort, hoverOut := 0, 0, -1, 0
	outputId := 0
	if out := e.Gen_OutputNode(g); out != nil do outputId = out.id
	for &n in g.nodes {
		info := e.Gen_NodeInfo(&n)
		mn, mx := lge_node_rect(origin, &n)
		sel := n.id in lge.sel
		imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32(UI_BG_RAISED), 6)
		head := [2]f32{mx.x, mn.y + 24 * lge.zoom}
		isOut := n.kind == .Tile_Output || n.kind == .Height_Output
		imgui.DrawList_AddRectFilled(dl, mn, head, col_u32(ui_accent(0.35) if isOut else ui_line(0.12)), 6, imgui.DrawFlags_RoundCornersTop)
		border := UI_ACCENT if sel else (UI_DANGER if n.id in lge.errors else (UI_WARNING if n.id in lge.unsafe else ui_line(0.2)))
		imgui.DrawList_AddRect(dl, mn, mx, col_u32(border), 6, imgui.DrawFlags(0), 2 if sel else 1)
		if lge.zoom > 0.5 {
			label := fmt.ctprintf("%s%s", info.label, "  (output)" if n.id == outputId else "")
			imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, 13 * lge.zoom, mn + {8, 5} * lge.zoom, col_u32(UI_TEXT), label)
			// (Chunked: not chunk-safe - a mark on its header.)
			if n.id in lge.unsafe do imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, 13 * lge.zoom, {mx.x - 20 * lge.zoom, mn.y + 5 * lge.zoom}, col_u32(UI_WARNING), ICON_FA_TRIANGLE_EXCLAMATION)
			for port, i in info.inputs do imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, 12 * lge.zoom, lge_in_port(mn, i) + {10 * lge.zoom, -7 * lge.zoom}, col_u32(UI_TEXT_DIM), fmt.ctprintf("%s", port))
		}
		// Thumbnail.
		rows := max(len(info.inputs), 1)
		tmn := mn + [2]f32{8, 28 + f32(rows) * 20} * lge.zoom
		tsz := [2]f32{LGE_NODE_W - 16, LGE_THUMB} * lge.zoom
		if tex, ok := &lge.thumbs[n.id]; ok && tex.id != 0 {
			ar := f32(tex.width) / f32(max(tex.height, 1))
			w := min(tsz.x, tsz.y * ar)
			hh := w / ar
			p := tmn + {(tsz.x - w) * 0.5, (tsz.y - hh) * 0.5}
			imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)tex, p, p + {w, hh})
		} else if why, bad := lge.errors[n.id]; bad && lge.zoom > 0.5 {
			imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, 11 * lge.zoom, tmn, col_u32(UI_DANGER), fmt.ctprintf("%s", why if len(why) < 40 else why[:40]))
		}
		// Ports.
		r := 5 * lge.zoom
		for _, i in info.inputs {
			p := lge_in_port(mn, i)
			on := n.inputs[i] != 0
			imgui.DrawList_AddCircleFilled(dl, p, r, col_u32(UI_ACCENT if on else ui_line(0.4)))
			if hovered && linalg_dist(mouse, p) < r * 2.2 do hoverIn, hoverInPort = n.id, i
			Drive_ItemRect(fmt.tprintf("lge.in:%d:%d", n.id, i), p - {r, r}, p + {r, r}, inWindow = true)
		}
		op := lge_out_port(mn, mx)
		imgui.DrawList_AddCircleFilled(dl, op, r, col_u32(UI_SUCCESS))
		if hovered && linalg_dist(mouse, op) < r * 2.2 do hoverOut = n.id
		Drive_ItemRect(fmt.tprintf("lge.out:%d", n.id), op - {r, r}, op + {r, r}, inWindow = true)
		Drive_ItemRect(fmt.tprintf("lge.node:%d", n.id), mn, head, inWindow = true)
		if hovered && mouse.x >= mn.x && mouse.x <= mx.x && mouse.y >= mn.y && mouse.y <= mx.y do hoverNode = n.id
	}

	// Mouse: links (from an output), moving, selecting, menus. (Nodes are
	// above frames: their clicks come first.)
	if hovered && imgui.IsMouseClicked(.Left) {
		additive := io.KeyShift || io.KeyCtrl || io.KeySuper
		if hoverOut != 0 {
			lge.linkFrom = hoverOut
		} else if hoverNode != 0 {
			// (A click on one of several selected keeps them, to drag them all;
			// let go without dragging and it's the only one.)
			if additive do lge_select_toggle(hoverNode)
			else if hoverNode not_in lge.sel do lge_select(hoverNode)
			else do lge.selected = hoverNode
			lge.frameSel = 0
			lge.clickAdd = additive
			lge.dragNode = hoverNode if hoverNode in lge.sel else 0
			lge.dragUndo = false
		} else if hoverFrameSize != 0 {
			lge_select(0)
			lge.frameSel, lge.frameSize, lge.frameUndo = hoverFrameSize, hoverFrameSize, false
		} else if hoverFrame != 0 {
			lge_select(0)
			lge.frameSel, lge.frameDrag, lge.frameUndo = hoverFrame, hoverFrame, false
			lge_frame_nodes(g.frames[hoverFrame - 1], &lge.frameNodes)
		} else {
			if !additive do lge_select(0)
			lge.frameSel = 0
			lge.boxing = true
			lge.boxFrom = lge_to_world(origin, mouse)
		}
	}
	// A box on the empty canvas selects the nodes it touches (Shift / Cmd:
	// adds them).
	if lge.boxing {
		a := lge_to_screen(origin, lge.boxFrom)
		lo, hi := [2]f32{min(a.x, mouse.x), min(a.y, mouse.y)}, [2]f32{max(a.x, mouse.x), max(a.y, mouse.y)}
		if imgui.IsMouseDown(.Left) {
			imgui.DrawList_AddRectFilled(dl, lo, hi, col_u32(ui_accent(0.12)))
			imgui.DrawList_AddRect(dl, lo, hi, col_u32(UI_ACCENT))
		} else {
			lge.boxing = false
			if hi.x - lo.x > 3 || hi.y - lo.y > 3 {
				for &n in g.nodes {
					mn, mx := lge_node_rect(origin, &n)
					if mx.x >= lo.x && mn.x <= hi.x && mx.y >= lo.y && mn.y <= hi.y do lge_select_add(n.id)
				}
			}
		}
	}
	if lge.frameDrag != 0 || lge.frameSize != 0 {
		i := max(lge.frameDrag, lge.frameSize) - 1
		if !imgui.IsMouseDown(.Left) || i >= len(g.frames) {
			lge.frameDrag, lge.frameSize = 0, 0
		} else if imgui.IsMouseDragging(.Left, 2) {
			if !lge.frameUndo {
				lge_change()
				lge.frameUndo = true
			}
			d := [2]f32{io.MouseDelta.x, io.MouseDelta.y} / lge.zoom
			f := &g.frames[i]
			if lge.frameSize != 0 {
				f.size = {max(f.size.x + d.x, 40), max(f.size.y + d.y, 40)}
			} else {
				f.pos += d
				for id in lge.frameNodes do if n := e.Gen_FindNode(g, id); n != nil do n.pos += d
			}
		}
	}
	if lge.linkFrom != 0 {
		if s := e.Gen_FindNode(g, lge.linkFrom); s != nil {
			smn, smx := lge_node_rect(origin, s)
			a := lge_out_port(smn, smx)
			imgui.DrawList_AddBezierCubic(dl, a, a + {40, 0}, mouse - {40, 0}, mouse, col_u32(UI_ACCENT), 2)
		}
		if !imgui.IsMouseDown(.Left) {
			if hoverIn != 0 && hoverIn != lge.linkFrom {
				before := e.Gen_GraphSerialize(g)
				if e.Gen_Connect(g, hoverIn, hoverInPort, lge.linkFrom) {
					// (A WFC node into a tile output: its values are tile ids.)
					dst, src := e.Gen_FindNode(g, hoverIn), e.Gen_FindNode(g, lge.linkFrom)
					if dst != nil && src != nil && dst.kind == .Tile_Output && src.kind == .WFC && hoverInPort == 0 do e.Gen_SetParam(dst, "tile_ids", 1)
					append(&lge.undo, before)
					for s in lge.redo do delete(s)
					clear(&lge.redo)
					lge_edited()
				} else {
					delete(before)
					Editor_Log(state, .Warn, "Level Generator: that link would make a loop")
				}
			}
			lge.linkFrom = 0
		}
	}
	if lge.dragNode != 0 {
		if imgui.IsMouseDown(.Left) {
			if imgui.IsMouseDragging(.Left, 2) {
				if !lge.dragUndo {
					lge_change()
					lge.dragUndo = true
				}
				for &n in g.nodes do if n.id in lge.sel do n.pos += [2]f32{io.MouseDelta.x, io.MouseDelta.y} / lge.zoom
			}
		} else {
			if !lge.dragUndo && !lge.clickAdd do lge_select(lge.dragNode) // (a click: just this one)
			lge.dragNode = 0
		}
	}
	if hovered && imgui.IsMouseClicked(.Right) {
		if hoverIn != 0 {
			if n := e.Gen_FindNode(g, hoverIn); n != nil && n.inputs[hoverInPort] != 0 {
				lge_change()
				n.inputs[hoverInPort] = 0
			}
		} else if hoverNode == 0 && (hoverFrame != 0 || hoverFrameSize != 0) {
			lge_select(0)
			lge.frameSel = max(hoverFrame, hoverFrameSize)
			imgui.OpenPopup("##lge_frame_ctx")
		} else {
			lge.ctxNode = hoverNode
			lge.ctxWorld = lge_to_world(origin, mouse)
			if hoverNode != 0 && hoverNode not_in lge.sel do lge_select(hoverNode)
			else if hoverNode != 0 do lge.selected = hoverNode
			if hoverNode == 0 {
				lge.searchBuf = {}
				lge.searchFocus = true
			}
			imgui.OpenPopup("##lge_ctx")
		}
	}
	if imgui.BeginPopup("##lge_frame_ctx") {
		if lge_menu(ICON_FA_TRASH, "Delete Frame", "lge-frame-delete") do lge_delete_selection()
		UI_Tooltip("Removes the frame; the nodes in it stay")
		imgui.EndPopup()
	}
	if imgui.BeginPopup("##lge_ctx") {
		if lge.ctxNode != 0 {
			many := len(lge.sel) > 1
			if lge_menu(ICON_FA_COPY, "Copy", "lge-copy") do lge_copy(state)
			UI_Tooltip("Copies the selected nodes and the links between them (Ctrl/Cmd+C); paste them here or in another generator")
			if lge_menu(ICON_FA_CLONE, "Duplicate", "lge-duplicate") do lge_duplicate(state)
			UI_Tooltip("A copy of the selected nodes beside them (Ctrl/Cmd+D)")
			if lge_menu(ICON_FA_FLAG, "Use as Output", "lge-output", lge.ctxNode != outputId && !many) {
				lge_change()
				g.output = lge.ctxNode
			}
			if lge_menu(ICON_FA_OBJECT_GROUP, "Frame Selection", "lge-frame-selection") do lge_add_frame(lge.ctxWorld)
			UI_Tooltip("A comment frame around the selected nodes: dragging its title moves them together")
			if lge_menu(ICON_FA_TRASH, "Delete", "lge-delete") do lge_delete_selection()
		} else {
			lge_add_menu(state)
		}
		imgui.EndPopup()
	}
}

// An entry of the add menu: a built-in kind, the Lua Script node, or a
// type registered from Odin (Gen_RegisterNode).
@(private = "file")
Lge_Add :: struct {
	label, name, doc: string,
	kind:   e.Gen_Kind,
	custom: string,
}

// lge_add_menu: the canvas's add menu - a search field on top (focused;
// typing filters every kind by its label or name, Enter adds the first
// match), the kinds by group while it's empty; Paste and Add Frame below.
@(private = "file")
lge_add_menu :: proc(state: ^EditorState) {
	g := &lge.graph
	groups := [4]struct {
		label: string,
		kinds: []e.Gen_Kind,
	}{
		{"Generators", {.Constant, .Noise, .Random_Fill, .Gradient, .Border, .Rect, .Rooms, .Walker, .Lines, .Rectangles, .Circles, .WFC}},
		{"Modifiers", {.Threshold, .Invert, .Remap, .Blur, .Cellular, .Dilate, .Erode, .Combine, .Scatter, .Poisson_Scatter, .Surface}},
		{"Playable", {.Flood_Fill, .Regions, .Connect_Regions, .Path, .Check}},
		{"Output", {.Tile_Output, .Entity_Output, .Height_Output}},
	}
	// Every entry, with the index where each group starts ("Your Own": a Lua
	// script, and the types registered from Odin).
	entries := make([dynamic]Lge_Add, context.temp_allocator)
	starts: [5]int
	for grp, gi in groups {
		starts[gi] = len(entries)
		for k in grp.kinds {
			info := e.GEN_KINDS[k]
			append(&entries, Lge_Add{info.label, info.name, info.doc, k, ""})
		}
	}
	starts[4] = len(entries)
	script := e.GEN_KINDS[.Script]
	append(&entries, Lge_Add{script.label, script.name, script.doc, .Script, ""})
	for def in e.Gen_CustomKinds() {
		append(&entries, Lge_Add{def.info.label if def.info.label != "" else def.info.name, def.info.name, def.info.doc, .Custom, def.info.name})
	}

	if lge.searchFocus {
		imgui.SetKeyboardFocusHere()
		lge.searchFocus = false
	}
	imgui.SetNextItemWidth(240)
	entered := imgui.InputTextWithHint("##lge_search", fmt.ctprintf("%s  Search nodes", ICON_FA_MAGNIFYING_GLASS), cstring(raw_data(lge.searchBuf[:])), len(lge.searchBuf), {.EnterReturnsTrue})
	Drive_Item("lge.search")
	UI_Tooltip("Type to filter the node types; Enter adds the first match")
	filter := strings.to_lower(strings.trim_space(string(cstring(raw_data(lge.searchBuf[:])))), context.temp_allocator)

	if filter != "" {
		first := -1
		for a, i in entries {
			if !strings.contains(strings.to_lower(a.label, context.temp_allocator), filter) && !strings.contains(a.name, filter) do continue
			if first < 0 do first = i
			lge_add_item(a)
		}
		if first < 0 do UI_DimText("No node matches")
		if entered && first >= 0 {
			lge_add_node(entries[first])
			imgui.CloseCurrentPopup()
		}
	} else {
		for grp, gi in groups {
			imgui.SeparatorText(strings.clone_to_cstring(grp.label, context.temp_allocator))
			for a in entries[starts[gi]:starts[gi + 1]] do lge_add_item(a)
		}
		imgui.SeparatorText("Your Own")
		for a in entries[starts[4]:] do lge_add_item(a)
	}
	imgui.Separator()
	clip := lge_clip_text()
	if lge_menu(ICON_FA_PASTE, "Paste", "lge-paste", clip != "") do lge_paste_text(state, clip, lge.ctxWorld)
	UI_Tooltip("Pastes copied nodes here (Ctrl/Cmd+V), from this generator or another")
	if lge_menu(ICON_FA_OBJECT_GROUP, "Add Frame", "lge-add-frame") do lge_add_frame(lge.ctxWorld, false)
	UI_Tooltip("A comment frame: a title and a colour around nodes; dragging its title moves the nodes inside")
}

@(private = "file")
lge_add_node :: proc(a: Lge_Add) {
	lge_change()
	lge_select(e.Gen_AddNode(&lge.graph, a.kind, lge.ctxWorld, a.custom).id)
}

@(private = "file")
lge_add_item :: proc(a: Lge_Add) {
	if imgui.MenuItem(fmt.ctprintf("%s", a.label)) do lge_add_node(a)
	Drive_Item(fmt.tprintf("ctx:lge-add:%s", a.name))
	if a.doc != "" do UI_Tooltip(a.doc)
}

@(private = "file")
lge_menu :: proc(icon, label: string, id: string, enabled := true) -> bool {
	clicked := imgui.MenuItem(fmt.ctprintf("%s  %s", icon, label), nil, false, enabled)
	Drive_Item(fmt.tprintf("ctx:%s", id))
	return clicked
}

@(private = "file")
linalg_dist :: proc(a, b: [2]f32) -> f32 {
	d := a - b
	return math.sqrt(d.x * d.x + d.y * d.y)
}

@(private = "file")
lge_side :: proc(state: ^EditorState) {
	g := &lge.graph
	if UI_SectionHeader("Level") && UI_BeginProps("##lge_level") {
		UI_PropLabel("Size")
		sz := [2]i32{i32(g.size.x), i32(g.size.y)}
		if imgui.DragInt2("##lge_size", &sz, 0.5, 1, 4096) do g.size = {int(max(sz.x, 1)), int(max(sz.y, 1))}
		lge_undo_on_activate()
		Drive_Item("lge.size")
		UI_PropLabel("Seed")
		seed := i32(g.seed)
		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x - 34)
		if imgui.DragInt("##lge_seed", &seed, 0.2, 0, 1 << 30) do g.seed = u64(max(seed, 0))
		lge_undo_on_activate()
		Drive_Item("lge.seed")
		imgui.SameLine(0, 4)
		if UI_IconButton(ICON_FA_SHUFFLE, "lge.reseed", "A new seed", size = 26) {
			lge_change()
			g.seed = u64(rl.GetRandomValue(1, 1 << 30))
		}
		UI_PropLabel("Output")
		out := e.Gen_OutputNode(g)
		outLabel := fmt.tprintf("%d  %s", out.id, e.Gen_NodeInfo(out).label) if out != nil else "None"
		if imgui.BeginCombo("##lge_output", strings.clone_to_cstring(outLabel, context.temp_allocator)) {
			for &n in g.nodes {
				if imgui.Selectable(fmt.ctprintf("%d  %s", n.id, e.Gen_NodeInfo(&n).label), out != nil && n.id == out.id) {
					lge_change()
					g.output = n.id
				}
			}
			imgui.EndCombo()
		}
		UI_EndProps()
	}
	if i := lge.frameSel - 1; i >= 0 && i < len(g.frames) do lge_frame_props(i)
	if len(lge.sel) > 1 do UI_DimText(fmt.tprintf("%d nodes selected (this one below)", len(lge.sel)))
	if n := e.Gen_FindNode(g, lge.selected); n != nil {
		info := e.Gen_NodeInfo(n)
		if UI_SectionHeader(fmt.tprintf("%s  (node %d)", info.label, n.id)) {
			UI_DimTextWrapped(info.doc)
			if n.id in lge.unsafe do imgui.TextColored(UI_WARNING, fmt.ctprintf("%s  Not chunk-safe: in a chunked level each chunk makes its own (seams)", ICON_FA_TRIANGLE_EXCLAMATION))
			if why, bad := lge.errors[n.id]; bad {
				// (Unformatted, wrapped: an error may hold a "%".)
				imgui.PushStyleColorImVec4(.Text, UI_DANGER)
				imgui.PushTextWrapPos(0)
				imgui.TextUnformatted(strings.clone_to_cstring(why, context.temp_allocator))
				imgui.PopTextWrapPos()
				imgui.PopStyleColor()
			}
			if len(info.params) > 0 && UI_BeginProps("##lge_params") {
				for p, i in info.params {
					UI_PropLabel(p.name)
					imgui.PushIDInt(i32(i))
					imgui.SetNextItemWidth(-1)
					if len(p.choices) > 0 {
						cur := clamp(int(n.params[i]), 0, len(p.choices) - 1)
						if v, changed := UI_Combo(fmt.tprintf("lge.param:%s", p.name), cur, p.choices); changed {
							lge_change()
							n.params[i] = f64(v)
						}
					} else if p.toggle {
						on := n.params[i] != 0
						if imgui.Checkbox("##v", &on) {
							lge_change()
							n.params[i] = 1 if on else 0
						}
					} else if p.integer {
						v := i32(n.params[i])
						if imgui.DragInt("##v", &v, 0.1) do n.params[i] = f64(v)
						lge_undo_on_activate()
					} else {
						v := f32(n.params[i])
						if imgui.DragFloat("##v", &v, 0.01, 0, 0, "%.3f") do n.params[i] = f64(v)
						lge_undo_on_activate()
					}
					Drive_Item(fmt.tprintf("lge.param:%s", p.name))
					if p.doc != "" do UI_Tooltip(p.doc)
					imgui.PopID()
				}
				UI_EndProps()
			}
			if n.kind == .Tile_Output {
				lge_tile_output(state, n)
				lge_rules(state, n)
			}
			if n.kind == .Height_Output do lge_height_output(state, n)
			if n.kind == .Entity_Output {
				imgui.SeparatorText("Component")
				files := make([dynamic]string, context.temp_allocator)
				for f in Editor_ListProjectFiles(state, "", {".component.json"}) do append(&files, f)
				imgui.SetNextItemWidth(-1)
				if path, ok := asset_picker("lge.component", n.component, files[:], false); ok {
					lge_change()
					e.Gen_SetComponent(g, n, path)
				}
				Drive_Item("lge.component")
				if n.component == "" do imgui.TextColored(UI_WARNING, "Pick the component it places")
			}
			if n.kind == .Script do lge_script_picker(state, n)
			if n.kind == .WFC do lge_wfc(state, n)
		}
	}
	// The preview: the selected node's grid, else the output's.
	if UI_SectionHeader("Preview") {
		id := lge.selected
		if id == 0 do if out := e.Gen_OutputNode(g); out != nil do id = out.id
		big := g.size.x * g.size.y > LGE_PREVIEW_MAX
		if big do UI_DimTextWrapped("Too big to preview here: Apply to a TileMap to see it.")
		if tex, ok := &lge.thumbs[id]; ok && !big && tex.id != 0 {
			availW := imgui.GetContentRegionAvail().x
			w := availW
			h := w * f32(tex.height) / f32(max(tex.width, 1))
			imgui.Image(transmute(imgui.TextureID)tex, {w, h})
			if lge.job != nil do UI_DimText("Updating...")
		} else if lge.job != nil {
			UI_DimText("Generating...")
		} else {
			UI_DimText("Nothing to preview.")
		}
	}
}

// lge_frame_props: the selected comment frame's title and colour.
@(private = "file")
lge_frame_props :: proc(i: int) {
	g := &lge.graph
	f := &g.frames[i]
	if !UI_SectionHeader("Frame") do return
	if UI_BeginProps("##lge_frame") {
		UI_PropLabel("Title")
		// (The title being typed keeps its own buffer until Enter or leaving.)
		local: [128]u8
		buf := lge.titleBuf[:] if lge.titleFor == i + 1 else local[:]
		if lge.titleFor != i + 1 do copy(local[:127], f.title)
		imgui.SetNextItemWidth(-1)
		entered := imgui.InputTextWithHint("##lge_frame_title", "Comment", cstring(raw_data(buf)), len(buf), {.EnterReturnsTrue})
		if imgui.IsItemActivated() {
			lge.titleBuf = local
			lge.titleFor = i + 1
		}
		if entered || imgui.IsItemDeactivatedAfterEdit() {
			title := strings.trim_space(string(cstring(raw_data(buf))))
			if title != f.title {
				lge_change()
				e.Gen_SetFrameTitle(g, f, title)
			}
		}
		if imgui.IsItemDeactivated() && lge.titleFor == i + 1 do lge.titleFor = 0
		Drive_Item("lge.frame-title")
		UI_Tooltip("The frame's title, drawn in its header")
		UI_PropLabel("Colour")
		imgui.SetNextItemWidth(-1)
		// (One undo step per pick: the first change records the graph.)
		col := f.color
		if imgui.ColorEdit4("##lge_frame_color", &col, {.AlphaBar}) {
			if !lge.colorUndo do lge_change()
			lge.colorUndo = true
			f.color = col
			lge_edited()
		} else if !imgui.IsAnyItemActive() {
			lge.colorUndo = false
		}
		Drive_Item("lge.frame-color")
		UI_Tooltip("The frame's colour (its fill is a light tint of it)")
		UI_EndProps()
	}
	if UI_Button(fmt.tprintf("%s  Delete Frame", ICON_FA_TRASH), "lge.frame-delete") do lge_delete_selection()
	UI_Tooltip("Removes the frame (Delete); the nodes in it stay")
}

// lge_script_picker: a script node's .lua file - pick one, start a new one
// (the template), edit it in the Code tab, reload it after editing.
@(private = "file")
lge_script_picker :: proc(state: ^EditorState, n: ^e.Gen_Node) {
	g := &lge.graph
	imgui.SeparatorText("Script")
	files := make([dynamic]string, context.temp_allocator)
	for f in Editor_ListProjectFiles(state, "", {".lua"}) do append(&files, f)
	imgui.SetNextItemWidth(-1)
	if path, ok := asset_picker("lge.script", n.script, files[:], false); ok {
		lge_change()
		e.Gen_SetScript(g, n, path)
		lge.scriptsStale = true
	}
	Drive_Item("lge.script")
	if UI_Button(fmt.tprintf("%s  New", ICON_FA_PLUS), "lge.script-new") {
		if rel := lge_new_script(state, n.id); rel != "" {
			lge_change()
			e.Gen_SetScript(g, n, rel)
			lge.scriptsStale = true
			Editor_OpenScript(state, rel)
		}
	}
	UI_Tooltip("A new script from a template (levels/<name>.gen.lua), opened in the Code tab")
	imgui.SameLine(0, 4)
	imgui.BeginDisabled(n.script == "")
	if UI_Button(fmt.tprintf("%s  Edit", ICON_FA_CODE), "lge.script-edit") do Editor_OpenScript(state, n.script)
	imgui.SameLine(0, 4)
	if UI_Button(fmt.tprintf("%s  Reload", ICON_FA_ROTATE), "lge.script-reload") {
		lge.scriptsStale = true // (read again; its new text changes its cache key)
		lge.version += 1
	}
	UI_Tooltip("Read the script again (after saving it in the Code tab)")
	imgui.EndDisabled()
	if n.script == "" do imgui.TextColored(UI_WARNING, "Pick or create its script")
}

// lge_new_script writes levels/<generator>_<node>.gen.lua (the template).
@(private = "file")
lge_new_script :: proc(state: ^EditorState, id: int) -> string {
	base := strings.trim_suffix(filepath.base(lge.path), ".levelgen.json")
	for i := 1; ; i += 1 {
		rel := fmt.tprintf("levels/%s_%d.gen.lua", base, id) if i == 1 else fmt.tprintf("levels/%s_%d_%d.gen.lua", base, id, i)
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		if os.exists(full) do continue
		_ = os.make_directory_all(filepath.dir(full, context.temp_allocator))
		if os.write_entire_file(full, transmute([]u8)string(e.GEN_SCRIPT_TEMPLATE)) != nil {
			Editor_Log(state, .Error, "Could not create %s", rel)
			return ""
		}
		Editor_InvalidateProjectFiles()
		Editor_Log(state, .Info, "Created %s", rel)
		return rel
	}
}

// lge_tile_output: a tile output's tileset (its tiles' picture: the palette,
// the previews), from the project or the TileMap selected in the scene, and
// its layer (the TileMap it fills, by name, next to the main one).
@(private = "file")
lge_tile_output :: proc(state: ^EditorState, n: ^e.Gen_Node) {
	g := &lge.graph
	// (writes components: no tileset; the layer names whose component layer.)
	comps := e.Gen_WritesComponents(n)
	imgui.SeparatorText("Components" if comps else "Tiles")
	if UI_BeginProps("##lge_tiles") {
		if !comps {
			UI_PropLabel("Tileset")
			imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x - 34)
			if path, ok := asset_picker("lge.tileset", n.tileset, Editor_ListProjectFiles(state, "", TEXTURE_EXTS)); ok {
				lge_change()
				e.Gen_SetTileset(g, n, path)
				lge.scriptsStale = true // (its terrains read)
			}
			Drive_Item("lge.tileset")
			UI_Tooltip("The image its tile numbers count in (left to right, top to bottom, tile_w x tile_h each): pick tiles from it, see real tiles in the previews")
			imgui.SameLine(0, 4)
			tm := cast(^e.TileMapNode)state.selectedNode if state.selectedNode != nil && state.selectedNode.typeId == e.TileMapNode else nil
			imgui.BeginDisabled(tm == nil || tm.tilesetPath == "")
			if UI_IconButton(ICON_FA_TABLE_CELLS_LARGE, "lge.tileset-from-map", "Use the tileset and tile size of the TileMap selected in the scene", size = 26) {
				lge_change()
				e.Gen_SetTileset(g, n, tm.tilesetPath)
				lge.scriptsStale = true
				e.Gen_SetParam(n, "tile_w", f64(tm.tileSize.x))
				e.Gen_SetParam(n, "tile_h", f64(tm.tileSize.y))
			}
			imgui.EndDisabled()
		}
		UI_PropLabel("Layer")
		// (The name being typed keeps its own buffer until Enter or leaving.)
		local: [64]u8
		buf := lge.layerBuf[:] if lge.layerFor == n.id else local[:]
		if lge.layerFor != n.id do copy(local[:63], n.layer)
		imgui.SetNextItemWidth(-1)
		entered := imgui.InputTextWithHint("##lge_layer", "the main TileMap", cstring(raw_data(buf)), len(buf), {.EnterReturnsTrue})
		if imgui.IsItemActivated() {
			lge.layerBuf = local
			lge.layerFor = n.id
		}
		if entered || imgui.IsItemDeactivatedAfterEdit() {
			name := strings.trim_space(string(cstring(raw_data(buf))))
			if name != n.layer {
				lge_change()
				e.Gen_SetLayer(g, n, name)
			}
		}
		if imgui.IsItemDeactivated() && lge.layerFor == n.id do lge.layerFor = 0
		Drive_Item("lge.layer")
		if comps do UI_Tooltip("Empty: the main TileMap's component layer. A name: the component layer of the TileMap of that name next to the main one (its sibling); its tiles stay")
		else do UI_Tooltip("Empty: the main TileMap (the output's). A name: the TileMap of that name next to the main one (its sibling) - one generator fills ground, walls and decoration at once")
		UI_EndProps()
	}
	if !comps && n.tileset != "" && lge_tileset(state, n.tileset) == nil do imgui.TextColored(UI_WARNING, "Can't read the tileset image")
}

// lge_height_output: a height output's tileset, walls map and levels - each
// level's map, tiles or terrain, cliff face and whether its edges are solid
// (#171, height layers).
@(private = "file")
lge_height_output :: proc(state: ^EditorState, n: ^e.Gen_Node) {
	g := &lge.graph
	e.Gen_HeightsEnsure(g, n) // (a level added by Levels: its settings)
	imgui.SeparatorText("Tiles")
	if UI_BeginProps("##lge_heights") {
		UI_PropLabel("Tileset")
		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x - 34)
		if path, ok := asset_picker("lge.tileset", n.tileset, Editor_ListProjectFiles(state, "", TEXTURE_EXTS)); ok {
			lge_change()
			e.Gen_SetTileset(g, n, path)
			lge.scriptsStale = true // (its terrains read)
		}
		Drive_Item("lge.tileset")
		UI_Tooltip("The image the levels' tile numbers count in (tile_w x tile_h each), and whose terrains (Tile Map tab > Terrains) draw their edges")
		imgui.SameLine(0, 4)
		tm := cast(^e.TileMapNode)state.selectedNode if state.selectedNode != nil && state.selectedNode.typeId == e.TileMapNode else nil
		imgui.BeginDisabled(tm == nil || tm.tilesetPath == "")
		if UI_IconButton(ICON_FA_TABLE_CELLS_LARGE, "lge.tileset-from-map", "Use the tileset and tile size of the TileMap selected in the scene", size = 26) {
			lge_change()
			e.Gen_SetTileset(g, n, tm.tilesetPath)
			lge.scriptsStale = true
			e.Gen_SetParam(n, "tile_w", f64(tm.tileSize.x))
			e.Gen_SetParam(n, "tile_h", f64(tm.tileSize.y))
		}
		imgui.EndDisabled()
		UI_PropLabel("Walls")
		if name, ok := lge_name_field(n, -1, n.layer, "no walls", "lge.walls"); ok {
			lge_change()
			e.Gen_SetLayer(g, n, name)
		}
		UI_Tooltip("The TileMap (by name, next to the main one) the edges of Solid levels go into, as walls_tile: make it Solid for cliff walls (and hide it, or give walls_tile a see-through tile). Empty: no walls")
		UI_EndProps()
	}
	if n.tileset != "" && lge_tileset(state, n.tileset) == nil do imgui.TextColored(UI_WARNING, "Can't read the tileset image")
	imgui.SeparatorText("Levels")
	UI_DimTextWrapped("Level 0 is the ground; each level above goes into its own TileMap (empty: the main one). Tiles, or a terrain drawn with edges where the height drops below the level; a cliff face below those edges.")
	custom := int(e.Gen_Param(n, "thresholds")) == 1
	count := e.Gen_HeightCount(n)
	mins := e.Gen_HeightThresholds(n)
	for k in 0 ..< count {
		hl := &n.heights[k]
		imgui.PushIDInt(i32(k))
		defer imgui.PopID()
		from := fmt.tprintf("from %.2f", mins[k]) if k > 0 else "the ground"
		imgui.TextUnformatted(fmt.ctprintf("Level %d  (%s)", k, from))
		if !UI_BeginProps("##lge_level") do continue
		if k > 0 && custom {
			UI_PropLabel("From")
			imgui.SetNextItemWidth(-1)
			imgui.DragFloat("##min", &hl.min, 0.005, 0, 1, "%.3f")
			lge_undo_on_activate()
			Drive_Item(fmt.tprintf("lge.height-min:%d", k))
			UI_Tooltip("The lowest value at this level (never below the level under it)")
		}
		UI_PropLabel("Map")
		if name, ok := lge_name_field(n, k, hl.layer, "the main TileMap", fmt.tprintf("lge.height-layer:%d", k)); ok {
			lge_change()
			e.Gen_HeightSetText(g, &hl.layer, name)
		}
		UI_Tooltip("The TileMap this level fills, by name, next to the main one (its sibling). Empty: the main TileMap. Levels naming the same map are laid over each other")
		UI_PropLabel("Tiles")
		imgui.SetNextItemWidth(-1)
		if name, ok := lge_terrain_combo(state, n, hl.terrain, "Tiles (no terrain)", fmt.tprintf("lge.height-terrain:%d", k)); ok {
			lge_change()
			e.Gen_HeightSetText(g, &hl.terrain, name)
		}
		UI_Tooltip("Tiles (one picked per cell), or a terrain of the tileset: auto-tiled, its edges where the height drops below this level")
		if hl.terrain == "" {
			UI_PropLabel("")
			lge_rule_tiles(state, n, &hl.tiles, fmt.tprintf("lge.height-pick:%d", k))
		}
		if k > 0 {
			UI_PropLabel("Cliff")
			imgui.SetNextItemWidth(-1)
			if name, ok := lge_terrain_combo(state, n, hl.cliff_terrain, "Tiles (no terrain)", fmt.tprintf("lge.height-cliff-terrain:%d", k)); ok {
				lge_change()
				e.Gen_HeightSetText(g, &hl.cliff_terrain, name)
			}
			UI_Tooltip("The cliff face (top-down): the cells just south of this level's edges - tiles, or a terrain (auto-tiled along the face). No tiles: no face")
			if hl.cliff_terrain == "" {
				UI_PropLabel("")
				lge_rule_tiles(state, n, &hl.cliff, fmt.tprintf("lge.height-cliff-pick:%d", k))
			}
			UI_PropLabel("Solid")
			solid := hl.solid
			if imgui.Checkbox("##solid", &solid) {
				lge_change()
				hl.solid = solid
			}
			Drive_Item(fmt.tprintf("lge.height-solid:%d", k))
			UI_Tooltip("Its edges (and cliff face) go into the Walls map as walls_tile: cliff walls")
		}
		UI_EndProps()
	}
	if n.layer == "" do for k in 1 ..< count do if n.heights[k].solid {
		imgui.TextColored(UI_WARNING, "Name the Walls map for the solid levels' walls")
		break
	}
}

// lge_name_field: a map name typed in (kept in its own buffer until Enter
// or leaving the field); ok when it changed.
@(private = "file")
lge_name_field :: proc(n: ^e.Gen_Node, slot: int, cur, hint, driveId: string) -> (name: string, ok: bool) {
	key := [2]int{n.id, slot}
	local: [64]u8
	buf := lge.nameBuf[:] if lge.nameFor == key else local[:]
	if lge.nameFor != key do copy(local[:63], cur)
	imgui.SetNextItemWidth(-1)
	entered := imgui.InputTextWithHint(fmt.ctprintf("##%s", driveId), strings.clone_to_cstring(hint, context.temp_allocator), cstring(raw_data(buf)), len(buf), {.EnterReturnsTrue})
	if imgui.IsItemActivated() {
		lge.nameBuf = local
		lge.nameFor = key
	}
	if entered || imgui.IsItemDeactivatedAfterEdit() {
		name = strings.trim_space(string(cstring(raw_data(buf))))
		ok = name != cur
		name = strings.clone(name, context.temp_allocator)
	}
	if imgui.IsItemDeactivated() && lge.nameFor == key do lge.nameFor = {}
	Drive_Item(driveId)
	return
}

// lge_terrain_combo: none (tiles) or a terrain of the node's tileset; the
// name picked ("": none) when it changed.
@(private = "file")
lge_terrain_combo :: proc(state: ^EditorState, n: ^e.Gen_Node, cur, none, driveId: string) -> (name: string, ok: bool) {
	terrains := Editor_Terrains(state, n.tileset)
	names := make([dynamic]string, context.temp_allocator)
	append(&names, none)
	at := 0
	if terrains != nil do for t, k in terrains.terrains {
		append(&names, fmt.tprintf("Terrain: %s", t.name))
		if t.name == cur do at = k + 1
	}
	if cur != "" && at == 0 {
		append(&names, fmt.tprintf("Terrain: %s (missing)", cur))
		at = len(names) - 1
	}
	v, changed := UI_Combo(driveId, at, names[:])
	if !changed || v == at do return "", false
	if v > 0 && terrains != nil && v - 1 < len(terrains.terrains) do return terrains.terrains[v - 1].name, true
	return "", true
}

// lge_height_pixels: a height output's preview - each level a shade (the
// ground dark, the top light), its edges darker, cliff faces brown.
@(private = "file")
lge_height_pixels :: proc(n: ^e.Gen_Node, grid: e.Gen_Grid, pixels: []rl.Color) {
	lv := e.Gen_HeightLevelsOf(n, grid, context.temp_allocator)
	count := e.Gen_HeightCount(n)
	w, h := grid.w, grid.h
	at :: proc(lv: []u8, w, h, x, y: int, def: u8) -> u8 {return lv[y * w + x] if x >= 0 && y >= 0 && x < w && y < h else def}
	for l, i in lv {
		x, y := i % w, i / w
		f := f32(l) / f32(max(count - 1, 1))
		c := rl.ColorFromHSV(130 - 90 * f, 0.35, 0.3 + 0.65 * f)
		edge := false
		for d in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do if at(lv, w, h, x + d.x, y + d.y, l) < l do edge = true
		if at(lv, w, h, x, y - 1, l) > l {
			c = rl.ColorFromHSV(28, 0.55, 0.3 + 0.5 * f) // (a face: the level above's)
		} else if edge {
			c = {u8(f32(c.r) * 0.55), u8(f32(c.g) * 0.55), u8(f32(c.b) * 0.55), 255}
		}
		pixels[i] = c
	}
}

// lge_wfc_output: the tile output a WFC node feeds (its tileset paints the
// sample and draws the previews; nil: none).
@(private = "file")
lge_wfc_output :: proc(g: ^e.Gen_Graph, id: int) -> ^e.Gen_Node {
	for &o in g.nodes do if o.kind == .Tile_Output && o.inputs[0] == id && !e.Gen_WritesComponents(&o) do return &o
	return nil
}

// lge_draw_tile: a tile in a rectangle - from the tileset, else in its
// colour; -1 (unpainted) a dark cell.
@(private = "file")
lge_draw_tile :: proc(dl: ^imgui.DrawList, ts: ^Lge_Tileset, tile: [2]int, t: i32, mn, mx: [2]f32) {
	if t < 0 {
		imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32(ui_line(0.06)))
		return
	}
	if _, count := lge_tile_grid(ts, tile); ts != nil && int(t) < count {
		uv0, uv1 := lge_tile_uv(ts, tile, t)
		imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)&ts.tex, mn, mx, uv0, uv1)
		return
	}
	c := lge_tile_color(t)
	imgui.DrawList_AddRectFilled(dl, mn, mx, col32(u32(c.r), u32(c.g), u32(c.b)))
}

// lge_wfc: a Wave Function Collapse node's rules - the sample painted with
// the tiles of the tileset of the output it feeds (left button paints the
// brush, right erases), or its Wang tiles.
@(private = "file")
lge_wfc :: proc(state: ^EditorState, n: ^e.Gen_Node) {
	g := &lge.graph
	out := lge_wfc_output(g, n.id)
	ts: ^Lge_Tileset
	tile := [2]int{16, 16}
	if out != nil {
		ts = lge_tileset(state, out.tileset)
		tile = lge_tile_size(out)
	}
	if out == nil do imgui.TextColored(UI_WARNING, "Connect it to a Tile Output: its tileset paints the sample")
	else if ts == nil do UI_DimTextWrapped("Pick the Tile Output's Tileset to paint with its tiles (until then: tile numbers, in colours).")
	if int(e.Gen_Param(n, "rules")) == 1 {
		lge_wang(n, ts, tile)
		return
	}
	imgui.SeparatorText("Sample")
	UI_DimTextWrapped("Paint how the tiles go together: the level only puts a tile next to another (left, right, above, below) where the sample does, and uses each about as often. Left button paints the brush, right erases; unpainted cells teach nothing.")
	if UI_BeginProps("##lge_wfc") {
		UI_PropLabel("Size")
		sz := [2]i32{i32(n.sample.w), i32(n.sample.h)}
		if imgui.DragInt2("##lge_wfc_size", &sz, 0.1, 1, e.GEN_WFC_SAMPLE_MAX) do e.Gen_WFCResizeSample(g, n, {int(sz.x), int(sz.y)})
		lge_undo_on_activate()
		Drive_Item("lge.wfc-size")
		UI_Tooltip("The sample's cells across and down (1-64); cells outside a smaller size are dropped")
		UI_PropLabel("Brush")
		if ts == nil {
			b := lge.wfcBrush
			imgui.SetNextItemWidth(-1)
			if imgui.DragInt("##lge_wfc_brush", &b, 0.1, -1, 1 << 20) do lge.wfcBrush = b
			Drive_Item("lge.wfc-brush")
			UI_Tooltip("The tile number to paint (-1: erase)")
		} else {
			p := imgui.GetCursorScreenPos()
			lge_draw_tile(imgui.GetWindowDrawList(), ts, tile, lge.wfcBrush, p, p + 20)
			imgui.Dummy({20, 20})
			imgui.SameLine(0, 6)
			imgui.TextUnformatted(fmt.ctprintf("%d", lge.wfcBrush) if lge.wfcBrush >= 0 else "Eraser")
		}
		UI_EndProps()
	}
	if UI_Button(fmt.tprintf("%s  Eraser", ICON_FA_ERASER), "lge.wfc-eraser") do lge.wfcBrush = -1
	UI_Tooltip("Paint with nothing (right-click erases too)")
	imgui.SameLine(0, 4)
	if UI_Button(fmt.tprintf("%s  Fill", ICON_FA_FILL_DRIP), "lge.wfc-fill") {
		lge_change()
		for &c in n.sample.cells do c = lge.wfcBrush
	}
	UI_Tooltip("Every cell of the sample the brush's tile")

	// The tiles in the sample already (pick one again), then the tileset.
	if rules, why := e.Gen_WFCRules(n); why == "" {
		for t, k in rules.tiles {
			if k > 0 do imgui.SameLine(0, 2)
			if k == 0 do imgui.TextUnformatted("In it:")
			if k == 0 do imgui.SameLine(0, 6)
			p := imgui.GetCursorScreenPos()
			imgui.PushIDInt(i32(k))
			if imgui.InvisibleButton("##used", {20, 20}) do lge.wfcBrush = t
			imgui.PopID()
			Drive_Item(fmt.tprintf("lge.wfc-used:%d", t))
			UI_Tooltip(fmt.tprintf("Tile %d", t))
			dl := imgui.GetWindowDrawList()
			lge_draw_tile(dl, ts, tile, t, p, p + 20)
			if t == lge.wfcBrush do imgui.DrawList_AddRect(dl, p - 1, p + 21, col_u32(UI_ACCENT), 0, imgui.DrawFlags(0), 2)
		}
	}
	if ts != nil {
		cols, count := lge_tile_grid(ts, tile)
		scale := clamp((imgui.GetContentRegionAvail().x - 4) / f32(max(ts.size.x, 1)), 0.25, 4)
		size := [2]f32{f32(ts.size.x), f32(ts.size.y)} * scale
		p0 := imgui.GetCursorScreenPos()
		imgui.InvisibleButton("##lge_wfc_palette", size)
		dl := imgui.GetWindowDrawList()
		imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)&ts.tex, p0, p0 + size)
		cell := [2]f32{f32(tile.x), f32(tile.y)} * scale
		for t in 0 ..< min(count, 4096) {
			mn := p0 + {f32(t % cols), f32(t / cols)} * cell
			if i32(t) == lge.wfcBrush do imgui.DrawList_AddRect(dl, mn, mn + cell, col_u32(UI_ACCENT), 0, imgui.DrawFlags(0), 2)
			Drive_ItemRect(fmt.tprintf("lge.wfc-brush:%d", t), mn, mn + cell, inWindow = true)
		}
		if imgui.IsItemClicked(.Left) {
			m := imgui.GetMousePos() - p0
			cx, cy := int(m.x / cell.x), int(m.y / cell.y)
			if cx >= 0 && cx < cols && cy >= 0 && cols > 0 && cy * cols + cx < count do lge.wfcBrush = i32(cy * cols + cx)
		}
		UI_Tooltip("Click a tile: the brush")
	}

	// The sample: drag to paint.
	s := &n.sample
	if s.w <= 0 || s.h <= 0 || len(s.cells) < s.w * s.h do return
	cs := clamp(math.floor((imgui.GetContentRegionAvail().x - 4) / f32(s.w)), 6, 32)
	p0 := imgui.GetCursorScreenPos()
	size := [2]f32{cs * f32(s.w), cs * f32(s.h)}
	imgui.InvisibleButton("##lge_wfc_sample", size, {.MouseButtonLeft, .MouseButtonRight})
	if imgui.IsItemActivated() do lge_change()
	if imgui.IsItemActive() {
		m := imgui.GetMousePos() - p0
		cx, cy := int(math.floor(m.x / cs)), int(math.floor(m.y / cs))
		t := lge.wfcBrush if !imgui.IsMouseDown(.Right) else -1
		if e.Gen_WFCSetCell(n, cx, cy, t) do lge_edited()
	}
	dl := imgui.GetWindowDrawList()
	for y in 0 ..< s.h do for x in 0 ..< s.w {
		mn := p0 + {f32(x), f32(y)} * cs
		lge_draw_tile(dl, ts, tile, s.cells[y * s.w + x], mn, mn + cs)
		Drive_ItemRect(fmt.tprintf("lge.wfc-cell:%d:%d", x, y), mn, mn + cs, inWindow = true)
	}
	imgui.DrawList_AddRect(dl, p0, p0 + size, col_u32(ui_line(0.3)))
	if rules, why := e.Gen_WFCRules(n); why == "" {
		pairs := 0
		for d in 0 ..< 2 do for word in rules.allow[d] do pairs += int(card(transmute(bit_set[0 ..< 64; u64])word))
		UI_DimText(fmt.tprintf("Learned: %d tiles, %d neighbour pairs", len(rules.tiles), pairs))
	} else {
		imgui.TextColored(UI_WARNING, fmt.ctprintf("%s", why))
	}
}

// lge_wang: a WFC node's Wang tiles - each a tile, its edges' colours
// (north, east, south, west) and a weight.
@(private = "file")
lge_wang :: proc(n: ^e.Gen_Node, ts: ^Lge_Tileset, tile: [2]int) {
	g := &lge.graph
	imgui.SeparatorText("Wang Tiles")
	UI_DimTextWrapped("Each tile's four edges have a colour (a number): north, east, south, west. Two tiles only touch where their touching edges match. Weight: how often it is picked.")
	remove := -1
	for &wt, i in n.wang {
		imgui.PushIDInt(i32(2000 + i))
		p := imgui.GetCursorScreenPos()
		lge_draw_tile(imgui.GetWindowDrawList(), ts, tile, wt.tile, p, p + 20)
		imgui.Dummy({20, 20})
		imgui.SameLine(0, 4)
		w := (imgui.GetContentRegionAvail().x - 30 - 6 * 4) / 6
		imgui.SetNextItemWidth(w)
		t := wt.tile
		if imgui.DragInt("##tile", &t, 0.1, 0, 1 << 20, "tile %d") do wt.tile = t
		lge_undo_on_activate()
		Drive_Item(fmt.tprintf("lge.wang-tile:%d", i))
		UI_Tooltip("The tile (its number in the tileset)")
		for side, k in ([4]string{"N", "E", "S", "W"}) {
			imgui.SameLine(0, 4)
			imgui.SetNextItemWidth(w)
			imgui.PushIDInt(i32(k))
			c := wt.edges[k]
			if imgui.DragInt("##edge", &c, 0.05, 0, 255, fmt.ctprintf("%s %%d", side)) do wt.edges[k] = c
			lge_undo_on_activate()
			Drive_Item(fmt.tprintf("lge.wang-edge:%d:%d", i, k))
			imgui.PopID()
		}
		imgui.SameLine(0, 4)
		imgui.SetNextItemWidth(w)
		imgui.DragFloat("##weight", &wt.weight, 0.01, 0, 100, "x%.2f")
		lge_undo_on_activate()
		UI_Tooltip("Weight: how often it is picked (relative)")
		imgui.SameLine(0, 4)
		if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("lge.wang-remove:%d", i), "Remove the tile", size = 24) do remove = i
		imgui.PopID()
	}
	if remove >= 0 {
		lge_change()
		ordered_remove(&n.wang, remove)
	}
	if UI_Button(fmt.tprintf("%s  Add Wang Tile", ICON_FA_PLUS), "lge.wang-add") {
		lge_change()
		if n.wang == nil do n.wang = make([dynamic]e.Gen_Wang_Tile, g.allocator)
		next := i32(0)
		for wt in n.wang do next = max(next, wt.tile + 1)
		append(&n.wang, e.Gen_Wang_Tile{tile = next, weight = 1})
	}
	UI_Tooltip("Another tile (the next number; set its edges)")
}

// lge_rule_terrain: the rule's terrain (of the output's tileset; None: its
// tiles) - its cells then take the terrain's tiles by their neighbours.
@(private = "file")
lge_rule_terrain :: proc(state: ^EditorState, n: ^e.Gen_Node, r: ^e.Gen_Tile_Rule, i: int) {
	terrains := Editor_Terrains(state, n.tileset)
	names := make([dynamic]string, context.temp_allocator)
	append(&names, "Tiles (no terrain)")
	cur := 0
	if terrains != nil do for t, k in terrains.terrains {
		append(&names, fmt.tprintf("Terrain: %s", t.name))
		if t.name == r.terrain do cur = k + 1
	}
	if r.terrain != "" && cur == 0 do append(&names, fmt.tprintf("Terrain: %s (missing)", r.terrain))
	if r.terrain != "" && cur == 0 do cur = len(names) - 1
	if v, changed := UI_Combo(fmt.tprintf("lge.rule-terrain:%d", i), cur, names[:]); changed && v != cur {
		lge_change()
		e.Gen_RuleSetTerrain(&lge.graph, r, terrains.terrains[v - 1].name if v > 0 && terrains != nil && v - 1 < len(terrains.terrains) else "")
	}
	UI_Tooltip("A terrain of the tileset (Tile Map tab > Terrains): the rule's cells take its tiles by their neighbours - edges and corners drawn for you")
}

// lge_rule_tiles: a rule's tiles as small pictures (in colours without a
// tileset), and Pick: the tileset as a palette - click tiles to add or
// remove them.
@(private = "file")
lge_rule_tiles :: proc(state: ^EditorState, n: ^e.Gen_Node, list: ^[dynamic]i32, pickId: string) {
	ts := lge_tileset(state, n.tileset)
	tile := lge_tile_size(n)
	SW :: f32(20)
	for t, k in list {
		if k >= 12 {
			UI_DimText(fmt.tprintf("+%d", len(list) - 12))
			break
		}
		if k > 0 do imgui.SameLine(0, 2)
		if _, count := lge_tile_grid(ts, tile); ts != nil && int(t) < count && t >= 0 {
			uv0, uv1 := lge_tile_uv(ts, tile, t)
			imgui.Image(transmute(imgui.TextureID)&ts.tex, {SW, SW}, uv0, uv1)
		} else {
			p := imgui.GetCursorScreenPos()
			c := lge_tile_color(t)
			imgui.DrawList_AddRectFilled(imgui.GetWindowDrawList(), p, p + SW, col32(u32(c.r), u32(c.g), u32(c.b)), 3)
			imgui.Dummy({SW, SW})
		}
		UI_Tooltip(fmt.tprintf("Tile %d", t))
	}
	if len(list) > 0 do imgui.SameLine(0, 6)
	imgui.BeginDisabled(ts == nil)
	if UI_Button(fmt.tprintf("%s  Pick", ICON_FA_TABLE_CELLS), pickId) do imgui.OpenPopup("##lge_palette")
	imgui.EndDisabled()
	UI_Tooltip("Pick the rule's tiles from the tileset" if ts != nil else "Set the tile output's Tileset first")
	if ts == nil || !imgui.BeginPopup("##lge_palette") do return
	defer imgui.EndPopup()
	if imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
	cols, count := lge_tile_grid(ts, tile)
	UI_DimText(fmt.tprintf("Click tiles to add or remove them (%d picked)", len(list)))
	scale := clamp(f32(360) / f32(max(ts.size.x, 1)), 0.25, 4)
	size := [2]f32{f32(ts.size.x), f32(ts.size.y)} * scale
	p0 := imgui.GetCursorScreenPos()
	imgui.InvisibleButton("##lge_palette_img", size)
	dl := imgui.GetWindowDrawList()
	imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)&ts.tex, p0, p0 + size)
	cell := [2]f32{f32(tile.x), f32(tile.y)} * scale
	for t in 0 ..< min(count, 4096) {
		mn := p0 + {f32(t % cols), f32(t / cols)} * cell
		on := slice_contains_i32(list[:], i32(t))
		imgui.DrawList_AddRect(dl, mn, mn + cell, col_u32(UI_ACCENT if on else ui_line(0.25)), 0, imgui.DrawFlags(0), 2 if on else 1)
		Drive_ItemRect(fmt.tprintf("lge.palette-tile:%d", t), mn, mn + cell, inWindow = true)
	}
	if imgui.IsItemClicked(.Left) {
		m := imgui.GetMousePos() - p0
		cx, cy := int(m.x / cell.x), int(m.y / cell.y)
		if cx >= 0 && cx < cols && cy >= 0 && cols > 0 && cy * cols + cx < count {
			t := i32(cy * cols + cx)
			lge_change()
			if k, found := slice_index_i32(list[:], t); found do ordered_remove(list, k)
			else do append(list, t)
		}
	}
}

@(private = "file")
slice_contains_i32 :: proc(a: []i32, v: i32) -> bool {
	_, found := slice_index_i32(a, v)
	return found
}

@(private = "file")
slice_index_i32 :: proc(a: []i32, v: i32) -> (int, bool) {
	for x, i in a do if x == v do return i, true
	return -1, false
}

// lge_rules: a tile output's rules - range and tiles ("3, 4": one of them).
@(private = "file")
lge_rules :: proc(state: ^EditorState, n: ^e.Gen_Node) {
	if e.Gen_WritesComponents(n) {
		lge_component_rules(state, n)
		return
	}
	imgui.SeparatorText("Rules")
	if e.Gen_Param(n, "tile_ids") != 0 do UI_DimTextWrapped("tile_ids is on: each cell takes the tile its input holds (a Wave Function Collapse node's) and these rules are skipped; the pattern rules still run.")
	else do UI_DimTextWrapped("Each cell takes the first rule whose range holds its value: one of its tiles.")
	remove := -1
	for &r, i in n.rules {
		imgui.PushIDInt(i32(i))
		w := (imgui.GetContentRegionAvail().x - 34) / 3
		imgui.SetNextItemWidth(w)
		imgui.DragFloat("##min", &r.min, 0.01, 0, 0, "from %.2f")
		lge_undo_on_activate()
		imgui.SameLine(0, 4)
		imgui.SetNextItemWidth(w)
		imgui.DragFloat("##max", &r.max, 0.01, 0, 0, "to %.2f")
		lge_undo_on_activate()
		imgui.SameLine(0, 4)
		if r.terrain != "" {
			// A terrain rule: its cells auto-tiled (the tiles below unused).
			imgui.SetNextItemWidth(w)
			lge_rule_terrain(state, n, &r, i)
			imgui.SameLine(0, 4)
			if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("lge.rule-remove:%d", i), "Remove the rule", size = 24) do remove = i
			imgui.PopID()
			continue
		}
		// The tiles as text ("3, 4"): the row being typed in keeps its own
		// buffer (lge.tilesBuf) until Enter or leaving the field.
		key := [2]int{n.id, i}
		parts := make([dynamic]string, context.temp_allocator)
		for t in r.tiles do append(&parts, fmt.tprint(t))
		local: [128]u8
		buf := lge.tilesBuf[:] if lge.tilesFor == key else local[:]
		if lge.tilesFor != key do copy(local[:127], strings.join(parts[:], ", ", context.temp_allocator))
		imgui.SetNextItemWidth(w)
		entered := imgui.InputText("##tiles", cstring(raw_data(buf)), len(buf), {.EnterReturnsTrue})
		if imgui.IsItemActivated() {
			lge.tilesBuf = local
			lge.tilesFor = key
		}
		if entered || imgui.IsItemDeactivatedAfterEdit() {
			lge_change()
			clear(&r.tiles)
			for f in strings.split(string(cstring(raw_data(buf))), ",", context.temp_allocator) {
				if v, ok := strconv.parse_int(strings.trim_space(f)); ok do append(&r.tiles, i32(v))
			}
		}
		if imgui.IsItemDeactivated() && lge.tilesFor == key do lge.tilesFor = {-1, -1}
		Drive_Item(fmt.tprintf("lge.rule-tiles:%d", i))
		UI_Tooltip("Tile indices (in the TileMap's tileset), comma separated: one is picked per cell")
		imgui.SameLine(0, 4)
		if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("lge.rule-remove:%d", i), "Remove the rule", size = 24) do remove = i
		lge_rule_tiles(state, n, &r.tiles, fmt.tprintf("lge.rule-pick:%d", i))
		if terrains := Editor_Terrains(state, n.tileset); terrains != nil && len(terrains.terrains) > 0 {
			imgui.SameLine(0, 4)
			imgui.SetNextItemWidth(120)
			lge_rule_terrain(state, n, &r, i)
		}
		imgui.PopID()
	}
	if remove >= 0 {
		lge_change()
		e.Gen_RuleFree(&n.rules[remove], lge.graph.allocator)
		ordered_remove(&n.rules, remove)
	}
	if UI_Button(fmt.tprintf("%s  Add Rule", ICON_FA_PLUS), "lge.rule-add") {
		lge_change()
		if n.rules == nil do n.rules = make([dynamic]e.Gen_Tile_Rule, lge.graph.allocator)
		r := e.Gen_Tile_Rule{min = 0, max = 0.5, tiles = make([dynamic]i32, lge.graph.allocator)}
		append(&r.tiles, 1)
		append(&n.rules, r)
	}
	lge_pattern_rules(state, n)
}

// lge_component_rules: an output that writes components - each rule a
// value range and the component its cells get on the map's component layer.
@(private = "file")
lge_component_rules :: proc(state: ^EditorState, n: ^e.Gen_Node) {
	imgui.SeparatorText("Rules")
	UI_DimTextWrapped("Each cell takes the first rule whose range holds its value: its component, painted on the map's component layer (a bigger one covers its footprint; cells it covers are skipped). The tiles stay.")
	files := make([dynamic]string, context.temp_allocator)
	for f in Editor_ListProjectFiles(state, "", {".component.json"}) do append(&files, f)
	remove := -1
	for &r, i in n.rules {
		imgui.PushIDInt(i32(i))
		w := (imgui.GetContentRegionAvail().x - 34) / 3
		imgui.SetNextItemWidth(w)
		imgui.DragFloat("##min", &r.min, 0.01, 0, 0, "from %.2f")
		lge_undo_on_activate()
		imgui.SameLine(0, 4)
		imgui.SetNextItemWidth(w)
		imgui.DragFloat("##max", &r.max, 0.01, 0, 0, "to %.2f")
		lge_undo_on_activate()
		imgui.SameLine(0, 4)
		imgui.SetNextItemWidth(w)
		if path, ok := asset_picker(fmt.tprintf("lge.rule-component:%d", i), r.component, files[:]); ok {
			lge_change()
			e.Gen_RuleSetComponent(&lge.graph, &r, path)
		}
		Drive_Item(fmt.tprintf("lge.rule-component:%d", i))
		UI_Tooltip(r.component if r.component != "" else "The component the rule's cells get (a .component.json)")
		imgui.SameLine(0, 4)
		if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("lge.rule-remove:%d", i), "Remove the rule", size = 24) do remove = i
		imgui.PopID()
	}
	if remove >= 0 {
		lge_change()
		e.Gen_RuleFree(&n.rules[remove], lge.graph.allocator)
		ordered_remove(&n.rules, remove)
	}
	if UI_Button(fmt.tprintf("%s  Add Rule", ICON_FA_PLUS), "lge.rule-add") {
		lge_change()
		if n.rules == nil do n.rules = make([dynamic]e.Gen_Tile_Rule, lge.graph.allocator)
		append(&n.rules, e.Gen_Tile_Rule{min = 0.5, max = 1, tiles = make([dynamic]i32, lge.graph.allocator)})
	}
	missing := len(n.rules) == 0
	for r in n.rules do if r.component == "" do missing = true
	if missing do imgui.TextColored(UI_WARNING, "Pick each rule's component")
}

// lge_pattern_rules: a tile output's pattern rules - a value range, a 3x3
// pattern (click a cell: any -> in range -> not), tiles, a chance.
@(private = "file")
lge_pattern_rules :: proc(state: ^EditorState, n: ^e.Gen_Node) {
	imgui.SeparatorText("Pattern Rules")
	UI_DimTextWrapped("After the rules: where the 3 x 3 cells around a cell match (blue: in the range, red: not, grey: any; the middle is the cell), it takes one of the tiles - decorations, ledges, corners. The first rule that matches wins; beyond the level counts as in the range.")
	remove := -1
	for &pr, i in n.patterns {
		imgui.PushIDInt(i32(1000 + i))
		// The pattern: 3 x 3 buttons.
		dl := imgui.GetWindowDrawList()
		p0 := imgui.GetCursorScreenPos()
		C :: f32(16)
		for ci in 0 ..< 9 {
			mn := p0 + {f32(ci % 3), f32(ci / 3)} * (C + 2)
			imgui.SetCursorScreenPos(mn)
			imgui.PushIDInt(i32(ci))
			if imgui.InvisibleButton("##cell", {C, C}) {
				lge_change()
				pr.cells[ci] = 1 if pr.cells[ci] == 0 else (-1 if pr.cells[ci] == 1 else 0)
			}
			Drive_Item(fmt.tprintf("lge.pattern-cell:%d:%d", i, ci))
			imgui.PopID()
			col := UI_ACCENT if pr.cells[ci] > 0 else (UI_DANGER if pr.cells[ci] < 0 else ui_line(0.15))
			imgui.DrawList_AddRectFilled(dl, mn, mn + C, col_u32(col), 2)
			if ci == 4 do imgui.DrawList_AddRect(dl, mn - 1, mn + C + 1, col_u32(UI_TEXT), 2, imgui.DrawFlags(0), 1.5)
		}
		imgui.SetCursorScreenPos(p0 + {3 * (C + 2) + 8, 0})
		imgui.BeginGroup()
		w := (imgui.GetContentRegionAvail().x - 34) / 3
		imgui.SetNextItemWidth(w)
		imgui.DragFloat("##pmin", &pr.min, 0.01, 0, 0, "from %.2f")
		lge_undo_on_activate()
		imgui.SameLine(0, 4)
		imgui.SetNextItemWidth(w)
		imgui.DragFloat("##pmax", &pr.max, 0.01, 0, 0, "to %.2f")
		lge_undo_on_activate()
		imgui.SameLine(0, 4)
		imgui.SetNextItemWidth(w)
		chance := pr.chance * 100
		if imgui.DragFloat("##pchance", &chance, 0.5, 0, 100, "%.0f%% chance") do pr.chance = clamp(chance / 100, 0, 1)
		lge_undo_on_activate()
		Drive_Item(fmt.tprintf("lge.pattern-chance:%d", i))
		UI_Tooltip("How many of the matching cells take a tile (the same ones for a seed)")
		imgui.SameLine(0, 4)
		if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("lge.pattern-remove:%d", i), "Remove the pattern rule", size = 24) do remove = i
		lge_rule_tiles(state, n, &pr.tiles, fmt.tprintf("lge.pattern-pick:%d", i))
		imgui.EndGroup()
		imgui.SetCursorScreenPos({p0.x, max(imgui.GetCursorScreenPos().y, p0.y + 3 * (C + 2)) + 4})
		imgui.Dummy({1, 1})
		imgui.PopID()
	}
	if remove >= 0 {
		lge_change()
		delete(n.patterns[remove].tiles)
		ordered_remove(&n.patterns, remove)
	}
	if UI_Button(fmt.tprintf("%s  Add Pattern Rule", ICON_FA_PLUS), "lge.pattern-add") {
		lge_change()
		if n.patterns == nil do n.patterns = make([dynamic]e.Gen_Pattern_Rule, lge.graph.allocator)
		// (A start: empty cells with solid below - things standing on ground.)
		pr := e.Gen_Pattern_Rule{min = 0.5, max = 1, chance = 1, tiles = make([dynamic]i32, lge.graph.allocator)}
		pr.cells[4], pr.cells[7] = -1, 1
		append(&n.patterns, pr)
	}
	UI_Tooltip("A new pattern rule (it starts as: an empty cell with solid below)")
}

// LevelGenEditor_DriveQuery answers test-drive queries ("lge.*").
LevelGenEditor_DriveQuery :: proc(q: string) -> (string, bool) {
	switch q {
	case "lge.open": return "true" if lge.open && lge.loaded else "false", true
	case "lge.path": return lge.path, true
	case "lge.dirty": return "true" if lge.dirty else "false", true
	case "lge.nodes": return fmt.tprint(len(lge.graph.nodes)), true
	case "lge.selected": return fmt.tprint(lge.selected), true
	case "lge.seed": return fmt.tprint(lge.graph.seed), true
	case "lge.undo": return fmt.tprint(len(lge.undo)), true
	case "lge.errors": return fmt.tprint(len(lge.errors)), true
	case "lge.text": return e.Gen_GraphSerialize(&lge.graph, context.temp_allocator) if lge.loaded else "", true
	case "lge.selection": return fmt.tprint(len(lge.sel)), true
	case "lge.frames": return fmt.tprint(len(lge.graph.frames)), true
	case "lge.frame-selected": return fmt.tprint(lge.frameSel - 1), true
	case "lge.wfc-brush": return fmt.tprint(lge.wfcBrush), true
	}
	if strings.has_prefix(q, "lge.pos:") {
		// lge.pos:<node> -> its position on the canvas ("x,y")
		id, _ := strconv.parse_int(q[len("lge.pos:"):])
		n := e.Gen_FindNode(&lge.graph, id)
		if n == nil do return "", true
		return fmt.tprintf("%v,%v", n.pos.x, n.pos.y), true
	}
	if strings.has_prefix(q, "lge.frame:") {
		// lge.frame:<index> -> "x,y" of the frame's top-left; lge.frame-title:<index>
		i, _ := strconv.parse_int(q[len("lge.frame:"):])
		if i < 0 || i >= len(lge.graph.frames) do return "", true
		return fmt.tprintf("%v,%v", lge.graph.frames[i].pos.x, lge.graph.frames[i].pos.y), true
	}
	if strings.has_prefix(q, "lge.frame-title:") {
		i, _ := strconv.parse_int(q[len("lge.frame-title:"):])
		if i < 0 || i >= len(lge.graph.frames) do return "", true
		return lge.graph.frames[i].title, true
	}
	if strings.has_prefix(q, "lge.frame-size:") {
		i, _ := strconv.parse_int(q[len("lge.frame-size:"):])
		if i < 0 || i >= len(lge.graph.frames) do return "", true
		return fmt.tprintf("%v,%v", lge.graph.frames[i].size.x, lge.graph.frames[i].size.y), true
	}
	if strings.has_prefix(q, "lge.input:") {
		// lge.input:<node>:<port> -> the node it reads (0 = none)
		parts := strings.split(q[len("lge.input:"):], ":", context.temp_allocator)
		if len(parts) != 2 do return "", true
		id, _ := strconv.parse_int(parts[0])
		port, _ := strconv.parse_int(parts[1])
		n := e.Gen_FindNode(&lge.graph, id)
		if n == nil || port < 0 || port > 1 do return "", true
		return fmt.tprint(n.inputs[port]), true
	}
	return "", false
}

// --- the Inspector of a LevelGeneratorNode ----------------------------------------------

@(private = "file")
lgi: struct {
	path:  string, // the generator file `graph` was read from (heap)
	graph: e.Gen_Graph,
	err:   string, // (heap)
	frame: int,    // re-read now and then: the file may have been edited
}

// inspector_level_generator: the generator file (open it in the Level
// Generator), the map it fills, Generate Now (baked into the scene,
// undoable) and the generator's parameters set on this node.
inspector_level_generator :: proc(state: ^EditorState, lg: ^e.LevelGeneratorNode) {
	if !UI_SectionHeader("Level Generator") do return
	files := make([dynamic]string, context.temp_allocator)
	for f in Editor_ListProjectFiles(state, "", {".json"}) do if strings.has_suffix(f, ".levelgen.json") do append(&files, f)
	imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x - 30)
	if path, ok := asset_picker("insp.levelgen.file", lg.generator, files[:], false); ok {
		Editor_RecordUndo(state, "Level generator file")
		lg.generator = strings.clone(path, lg.allocator)
	}
	Drive_Item("insp.levelgen.file")
	imgui.SameLine(0, 4)
	imgui.BeginDisabled(lg.generator == "")
	if UI_IconButton(ICON_FA_PEN_TO_SQUARE, "insp.levelgen.open", "Open it in the Level Generator", size = 24) do LevelGenEditor_Open(state, lg.generator)
	imgui.EndDisabled()
	if lg.generator == "" {
		imgui.TextColored(UI_WARNING, "Pick a generator (.levelgen.json)")
		return
	}
	tm := e.LevelGeneratorNode_Target(lg, &state.game.gameContext, state.activeScene)
	if tm != nil do UI_DimText(fmt.tprintf("Fills %s", tm.name))
	else do imgui.TextColored(UI_WARNING, "No TileMap: add one as a child, or set Tile Map")
	imgui.BeginDisabled(tm == nil)
	if UI_Button(fmt.tprintf("%s  Generate Now", ICON_FA_SHUFFLE), "insp.levelgen.generate") {
		Editor_RecordUndo(state, "Generate level")
		bg := lg.background
		lg.background = false // (the editor bakes it at once)
		ok, why := e.LevelGeneratorNode_Generate(lg, &state.game.gameContext, 0, state.activeScene)
		lg.background = bg
		if ok do Editor_Log(state, .Info, "Generated %s into %s (seed %d)", filepath.base(lg.generator), tm.name, lg.lastSeed)
		else do Editor_Log(state, .Error, "%s: %s", lg.name, why)
	}
	imgui.EndDisabled()
	UI_Tooltip("Writes a level into the TileMap now, to see it or paint over it (Ctrl/Cmd+Z undoes it); the game generates its own when the scene starts")

	// The generator's parameters: set one here and this node's levels use it.
	lgi_load(state, lg.generator)
	if lgi.err != "" {
		imgui.TextColored(UI_DANGER, fmt.ctprintf("%s", lgi.err))
		return
	}
	if lg.chunked do lge_chunk_note(&lgi.graph, "insp.levelgen.chunks")
	imgui.SeparatorText("Level Parameters")
	UI_DimTextWrapped("The generator's own values; change one to set it for this node (the dot resets it).")
	clear: struct {
		id:   int,
		name: string,
	}
	for &n in lgi.graph.nodes {
		info := e.Gen_NodeInfo(&n)
		if len(info.params) == 0 do continue
		if !imgui.TreeNodeEx(fmt.ctprintf("%d  %s##lgp%d", n.id, info.label, n.id), {.SpanAvailWidth}) do continue
		if UI_BeginProps(fmt.tprintf("##lgp_props%d", n.id)) {
			for p, i in info.params {
				imgui.PushIDInt(i32(n.id * 16 + i))
				set, isSet := e.LevelGeneratorNode_Param(lg, n.id, p.name)
				v := set if isSet else n.params[i]
				UI_PropLabel(p.name)
				if isSet {
					if UI_IconButton(ICON_FA_CIRCLE, fmt.tprintf("insp.levelgen.reset:%d:%s", n.id, p.name), "Set on this node - click to use the generator's value", size = 20) do clear = {n.id, p.name}
					imgui.SameLine(0, 4)
				}
				imgui.SetNextItemWidth(-1)
				changed := false
				if len(p.choices) > 0 {
					if c, ok := UI_Combo(fmt.tprintf("insp.levelgen.param:%d:%s", n.id, p.name), clamp(int(v), 0, len(p.choices) - 1), p.choices); ok {
						v, changed = f64(c), true
					}
				} else if p.toggle {
					on := v != 0
					if imgui.Checkbox("##v", &on) do v, changed = (1 if on else 0), true
				} else if p.integer {
					iv := i32(v)
					if imgui.DragInt("##v", &iv, 0.1) do v, changed = f64(iv), true
				} else {
					fv := f32(v)
					if imgui.DragFloat("##v", &fv, 0.01, 0, 0, "%.3f") do v, changed = f64(fv), true
				}
				if imgui.IsItemActivated() || (changed && len(p.choices) > 0) || (changed && p.toggle) do Editor_RecordUndo(state, "Level parameter")
				if changed do e.LevelGeneratorNode_SetParam(lg, n.id, p.name, v)
				Drive_Item(fmt.tprintf("insp.levelgen.param:%d:%s", n.id, p.name))
				if p.doc != "" do UI_Tooltip(p.doc)
				imgui.PopID()
			}
			UI_EndProps()
		}
		imgui.TreePop()
	}
	if clear.id != 0 {
		Editor_RecordUndo(state, "Reset level parameter")
		e.LevelGeneratorNode_ClearParam(lg, clear.id, clear.name)
	}
}

// lge_chunk_note: for a generator a Level Generator makes in chunks (#171) -
// the nodes that aren't chunk-safe (they run per chunk: seams between
// chunks), or that it is safe and its apron.
lge_chunk_note :: proc(g: ^e.Gen_Graph, driveId: string) {
	info := e.Gen_ChunkInfo(g, context.temp_allocator)
	if len(info.unsafe) == 0 {
		UI_DimTextWrapped(fmt.tprintf("%s  Chunk-safe: no seams between chunks (each made with %d extra cells around it)", ICON_FA_CIRCLE_CHECK, info.apron))
		Drive_Item(driveId)
		return
	}
	names := make([dynamic]string, context.temp_allocator)
	for id in info.unsafe do if n := e.Gen_FindNode(g, id); n != nil do append(&names, fmt.tprintf("%s (%d)", e.Gen_NodeInfo(n).label, id))
	imgui.PushStyleColorImVec4(.Text, UI_WARNING)
	imgui.PushTextWrapPos(0)
	text := fmt.tprintf("%s  Not chunk-safe: %s. They look at the whole level, so each chunk makes its own - seams show between chunks.", ICON_FA_TRIANGLE_EXCLAMATION, strings.join(names[:], ", ", context.temp_allocator))
	imgui.TextUnformatted(strings.clone_to_cstring(text, context.temp_allocator))
	imgui.PopTextWrapPos()
	imgui.PopStyleColor()
	Drive_Item(driveId)
	UI_Tooltip("Chunk-safe nodes give each cell the same value in a chunk as in one big level: noise, random fill, gradient, rectangle, threshold, invert, remap, combine, blur, cellular, dilate, erode, scatter, surface and the outputs. Others (rooms, walker, shapes, WFC, Poisson scatter, flood fill, regions, paths, check, border, scripts) still run in each chunk, with the chunk's own seed.")
}

// lge_chunked_users: Level Generator nodes of the open scene that make this
// file's levels in chunks.
@(private = "file")
lge_chunked_users :: proc(state: ^EditorState, path: string) -> int {
	if state.activeScene == nil || path == "" do return 0
	count := 0
	for n in state.activeScene.manager.nodes {
		if n == nil || n.typeId != e.LevelGeneratorNode do continue
		lg := cast(^e.LevelGeneratorNode)n
		if lg.chunked && lg.generator == path do count += 1
	}
	return count
}

// lgi_load reads the generator the Inspector shows (again every second or
// so, or for another file).
@(private = "file")
lgi_load :: proc(state: ^EditorState, rel: string) {
	lgi.frame += 1
	if lgi.path == rel && lgi.frame % 60 != 0 do return
	e.Gen_GraphDestroy(&lgi.graph)
	delete(lgi.path)
	delete(lgi.err)
	lgi.path, lgi.err, lgi.graph = strings.clone(rel), "", {}
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	data, rerr := os.read_entire_file(full, context.temp_allocator)
	if rerr != nil {
		lgi.err = strings.clone(fmt.tprintf("Can't read %s", rel))
		return
	}
	g, why := e.Gen_GraphParse(data)
	lgi.graph = g
	if why != "" do lgi.err = strings.clone(why)
}
