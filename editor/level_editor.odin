package editor

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Level editor (the "Level" root tab)
//
// Edits LDtk projects (.ldtk, with external .ldtkl levels) in place: the
// file stays the level format, so it still opens in LDtk and the game's
// LdtkLevelNodes read it (they reload when it is saved). The model is
// e.Ldtk_Doc (engine/ldtk_doc*.odin): an order-preserving JSON tree, typed
// cell data, LDtk's auto-layer rule engine, undo.
//
// Layout (its own dock space, resizable and rearrangeable): Levels on the
// left, Layers (with the active layer's palette) on the right, the canvas in
// the middle over the bottom panel's tabs (World, Level, Tilesets, Entities,
// Enums, Layers, Rules, Project - level_defs.odin). The toolbar switches to
// level tools while this tab is shown; Play stays.
// ============================================================================

Root_Tab :: enum u8 {
	Game,
	Level,
}

Level_Tool :: enum u8 {
	Brush,
	Rect,
	Erase,
	Fill,
	Pick,
	Select,
	Move_Level,
}

// The bottom panel's tabs.
Level_Panel_Tab :: enum u8 {
	World,
	Level,
	Tilesets,
	Entities,
	Enums,
	Layers,
	Rules,
	Project,
}

LEVEL_TOOL_INFO := [Level_Tool]struct {icon, name, key, tip, topic: string}{
	.Brush      = {ICON_FA_PAINTBRUSH, "Brush", "B", "Paint the picked value / tiles, place the picked entity. Right button erases.", "tool.brush"},
	.Rect       = {ICON_FA_VECTOR_SQUARE, "Rectangle", "R", "Drag a rectangle to fill it (right button: erase it).", "tool.rect"},
	.Erase      = {ICON_FA_ERASER, "Erase", "E", "Erase IntGrid values and tiles.", "tool.erase"},
	.Fill       = {ICON_FA_FILL_DRIP, "Fill", "F", "Fill the connected area of equal cells.", "tool.fill"},
	.Pick       = {ICON_FA_EYE_DROPPER, "Pick", "I", "Pick the value or tile under the mouse.", "tool.pick"},
	.Select     = {ICON_FA_ARROW_POINTER, "Select", "V", "Select cells and entities, move, copy, delete them. Also: hold Alt with any tool.", "tool.select"},
	.Move_Level = {ICON_FA_ARROWS_UP_DOWN_LEFT_RIGHT, "Move levels", "M", "Drag levels around the world.", "tool.movelevel"},
}

LevelEd :: struct {
	tab:          Root_Tab,
	doc:          ^e.Ldtk_Doc,
	layerUid:     int, // def uid of the active layer (kept across definition changes)
	rel:          string, // project-relative path (heap)
	level:        int,
	layer:        int,
	world:        int,
	tool:         Level_Tool,
	intValue:     int,
	tileSel:      [dynamic]i32, // picked tile ids (heap); a stamp keeps their places in the tileset
	tileSelW:     int,          // their bounds in tiles
	tileSelH:     int,
	tileRandom:   bool,         // Random mode: one random tile of the selection per cell
	stacking:     bool,         // tiles go on top of the cell's tiles (non-opaque ones)
	flips:        u8,
	entityDef:    int, // uid
	showGrid:     bool,
	showIntGrid:  bool,
	singleLayer:  bool, // LDtk's single layer mode: the other layers faded
	hideAuto:     bool, // auto-layer tiles not drawn (their IntGrid values show)
	hideDetails:  bool, // no level names / entity labels / field shapes
	selectEmpty:  bool, // rectangle selections include empty cells
	zen:          bool, // the canvas alone (Tab)
	spotPick:     bool, // picking the spot of a new level (LevelSpotPicker)
	dockPos:      [2]f32,
	dockSize:     [2]f32,
	// canvas
	cam:          [2]f32,
	zoom:         f32,
	rt:           rl.RenderTexture2D,
	canvasMin:    [2]f32,
	canvasSize:   [2]f32,
	hovered:      bool,
	fitRequest:   bool,
	textures:     map[int]rl.Texture2D, // tileset uid -> texture
	texDefsRev:   u64,
	// interaction
	painting:     bool,
	paintErase:   bool,
	lastCell:     [2]int,
	rectStart:    [2]int,
	rectActive:   bool,
	panning:      bool,
	selEntity:    ^e.LdtkJson, // the selection's only entity (nil otherwise)
	selEntityLayer: int,
	sel:          e.Ldtk_Selection, // selected cells / entities of the active level
	clip:         e.Ldtk_Clipboard,
	selMoving:    bool,    // dragging the selection
	selMoved:     bool,    // ... past the start threshold
	selCopy:      bool,    // Cmd+Alt: copy instead of move
	selGrab:      [2]f32,  // world position the drag started at
	selRect:      bool,    // rectangle selection in progress
	selRectStart: [2]f32,
	entDrag:      bool,
	entResize:    bool,
	entHandle:    Level_Handle, // the entity handle being dragged
	entMoved:     bool,
	entGrab:      [2]int,
	levelDrag:    bool,
	levelMoved:   bool,
	levelGrab:    [2]int,
	resizeHandle: Level_Handle, // dragging a level edge / corner
	resizeFrom:   [2]f32,
	bgTextures:   map[string]rl.Texture2D, // level background images (bgRelPath)
	// panels
	dockBuilt:    bool,
	paletteZoom:  f32,
	paletteDrag:  bool,
	paletteStart: [2]int,
	panelTab:     Level_Panel_Tab,
	panelRequest: Maybe(Level_Panel_Tab), // select this tab next frame
	lastSel:      ^e.LdtkJson,          // entity selected last frame
	layerDrag:    int,                  // layer row being dragged (-1 none)
	renameLevel:  int,
	renameRequest: bool,
	renameBuf:    [128]u8,
	newPrompt:    bool,
	closePrompt:  bool,
	closeThen:    string, // file to open after the close prompt ("" = none)
	nameBuf:      [128]u8,
	sizeBuf:      [2]i32,
	error:        string,
}

GlobalLevel := LevelEd{zoom = 2, showGrid = true, showIntGrid = true, paletteZoom = 2, panelTab = .World, layerDrag = -1}

LEVEL_TAB_TOPIC := [Level_Panel_Tab]string{
	.World = "tab.world", .Level = "tab.level", .Tilesets = "tab.tilesets", .Entities = "tab.entities",
	.Enums = "tab.enums", .Layers = "tab.layers", .Rules = "tab.rules", .Project = "tab.project",
}

LEVEL_TAB_TIP := [Level_Panel_Tab]string{
	.World    = "World layout and grid, a map of the levels",
	.Level    = "The active level's values and fields - or the selected entity's",
	.Tilesets = "Tilesets: images, tile size, per-tile data, animations, tags",
	.Entities = "Entity definitions and their fields",
	.Enums    = "Enumerations for fields and tile tags",
	.Layers   = "Layer settings and IntGrid values",
	.Rules    = "Auto-layer rules and terrains",
	.Project  = "Project defaults, JSON options, level fields",
}

// LevelEditor_ShowTab brings a bottom-panel tab to the front.
LevelEditor_ShowTab :: proc(t: Level_Panel_Tab) {
	GlobalLevel.panelRequest = t
}

LevelEditor_Active :: proc() -> bool {return GlobalLevel.tab == .Level}

// ----------------------------------------------------------------------------
// Open / save / close
// ----------------------------------------------------------------------------

level_abs :: proc(state: ^EditorState, rel: string) -> string {
	p, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	return p
}

// level_doc_rel: a project-relative path made relative to the .ldtk.
level_doc_rel :: proc(state: ^EditorState, rel: string) -> string {
	abs := level_abs(state, rel)
	r, err := filepath.rel(GlobalLevel.doc.dir, abs, context.temp_allocator)
	if err != nil do r = rel
	r, _ = strings.replace_all(r, "\\", "/", context.temp_allocator)
	return r
}

// LevelEditor_OpenAt opens a file at a level (by identifier).
LevelEditor_OpenAt :: proc(state: ^EditorState, rel: string, levelIdentifier: string) {
	if !LevelEditor_Open(state, rel) do return
	L := &GlobalLevel
	for &lv, i in L.doc.levels {
		if e.LdtkJson_Str(lv.obj, "identifier") == levelIdentifier {
			L.level = -1
			LevelEditor_SetLevel(i)
			L.fitRequest = true
			break
		}
	}
}

// LevelEditor_Open loads a project-relative .ldtk file into the Level tab.
LevelEditor_Open :: proc(state: ^EditorState, rel: string) -> bool {
	L := &GlobalLevel
	if L.doc != nil && L.rel == rel {
		L.tab = .Level
		return true
	}
	if L.doc != nil && L.doc.modified {
		L.closePrompt = true
		delete(L.closeThen)
		L.closeThen = strings.clone(rel)
		L.tab = .Level
		return false
	}
	doc, ok := e.Ldtk_Doc_Load(level_abs(state, rel))
	if !ok {
		Editor_Log(state, .Error, "Could not open %s as an LDtk project", rel)
		return false
	}
	level_close_doc()
	L.doc = doc
	L.rel = strings.clone(rel)
	L.level, L.world, L.layer = 0, 0, 0
	level_clear_selection()
	level_pick_default_layer()
	L.fitRequest = true
	L.tab = .Level
	Editor_Log(state, .Info, "Editing level %s", rel)
	LevelProject_AfterLoad(state)
	return true
}

@(private = "file")
level_close_doc :: proc() {
	L := &GlobalLevel
	LevelFields_CancelPick()
	for _, t in L.textures do rl.UnloadTexture(t)
	clear(&L.textures)
	for k, t in L.bgTextures {
		if t.id != 0 do rl.UnloadTexture(t)
		delete(k)
	}
	clear(&L.bgTextures)
	L.texDefsRev = 0
	e.Ldtk_Doc_Destroy(L.doc)
	L.doc = nil
	delete(L.rel)
	L.rel = ""
	level_clear_selection()
	L.painting, L.rectActive, L.entDrag, L.levelDrag = false, false, false, false
}

// level_clear_selection empties the selection.
level_clear_selection :: proc() {
	L := &GlobalLevel
	e.Ldtk_Selection_Clear(&L.sel)
	L.selEntity = nil
	L.selMoving, L.selRect = false, false
}

// level_sync_selection drops elements that no longer exist (after undo,
// deleted layers / levels) and derives selEntity.
level_sync_selection :: proc() {
	L := &GlobalLevel
	doc := L.doc
	if doc == nil || len(doc.levels) == 0 || L.level >= len(doc.levels) {
		level_clear_selection()
		return
	}
	lv := &doc.levels[L.level]
	w := 0
	for c in L.sel.cells {
		if c.layer < len(lv.layers) && c.cx >= 0 && c.cy >= 0 && c.cx < lv.layers[c.layer].cWid && c.cy < lv.layers[c.layer].cHei {
			L.sel.cells[w] = c
			w += 1
		}
	}
	resize(&L.sel.cells, w)
	w = 0
	for se in L.sel.entities {
		ok := false
		if se.layer < len(lv.layers) do for ent in e.LdtkJson_Arr(lv.layers[se.layer].obj, "entityInstances") do if ent == se.obj do ok = true
		if ok {
			L.sel.entities[w] = se
			w += 1
		}
	}
	resize(&L.sel.entities, w)
	L.selEntity = nil
	if len(L.sel.entities) == 1 && len(L.sel.cells) == 0 {
		L.selEntity = L.sel.entities[0].obj
		L.selEntityLayer = L.sel.entities[0].layer
	}
}

// level_select_entity makes one entity the selection.
level_select_entity :: proc(layer: int, ent: ^e.LdtkJson) {
	L := &GlobalLevel
	level_clear_selection()
	if ent == nil do return
	append(&L.sel.entities, e.Ldtk_SelEntity{layer, ent})
	L.selEntity, L.selEntityLayer = ent, layer
}

Stamp_Tile :: struct {
	tid: i32,
	d:   [2]int, // offset in the stamp (flips applied)
}

// level_set_tile_sel picks tiles (their bounds use the active layer's
// tileset).
level_set_tile_sel :: proc(ids: []i32) {
	L := &GlobalLevel
	clear(&L.tileSel)
	append(&L.tileSel, ..ids)
	ts: ^e.Ldtk_DocTileset
	if ly, _ := level_active_layer(); ly != nil do ts = e.Ldtk_Doc_LayerTileset(L.doc, ly)
	_, L.tileSelW, L.tileSelH = level_stamp(ts)
}

// level_stamp: the picked tiles as a stamp - each tile at its place in the
// tileset relative to the selection's top-left (mirrored by the flips),
// and the stamp's size (temp-allocated).
level_stamp :: proc(ts: ^e.Ldtk_DocTileset) -> ([]Stamp_Tile, int, int) {
	L := &GlobalLevel
	out := make([]Stamp_Tile, len(L.tileSel), context.temp_allocator)
	if len(L.tileSel) == 0 do return out, 1, 1
	cw := ts != nil ? max(ts.cWid, 1) : 1 << 20
	mn := [2]int{max(int), max(int)}
	mx := [2]int{min(int), min(int)}
	for t in L.tileSel {
		p := [2]int{int(t) % cw, int(t) / cw}
		mn = {min(mn.x, p.x), min(mn.y, p.y)}
		mx = {max(mx.x, p.x), max(mx.y, p.y)}
	}
	for t, i in L.tileSel {
		p := [2]int{int(t) % cw, int(t) / cw}
		d := p - mn
		if (L.flips & 1) != 0 do d.x = mx.x - p.x
		if (L.flips & 2) != 0 do d.y = mx.y - p.y
		out[i] = {t, d}
	}
	return out, mx.x - mn.x + 1, mx.y - mn.y + 1
}

// level_pick_default_layer: the first layer you can paint.
level_pick_default_layer :: proc() {
	L := &GlobalLevel
	doc := L.doc
	if doc == nil || L.level >= len(doc.levels) do return
	lv := &doc.levels[L.level]
	L.layer = 0
	for &ly, i in lv.layers {
		d := e.Ldtk_Doc_LayerDef(doc, &ly)
		if d != nil && (d.type == .IntGrid || d.type == .Tiles) {
			L.layer = i
			break
		}
	}
	level_sync_palette()
}

// level_sync_palette keeps the picked value / entity valid for the layer.
level_sync_palette :: proc() {
	L := &GlobalLevel
	ly, d := level_active_layer()
	if ly == nil || d == nil do return
	L.layerUid = d.uid
	switch d.type {
	case .IntGrid:
		if e.Ldtk_Doc_IntValue(d, L.intValue) == nil do L.intValue = len(d.values) > 0 ? d.values[0].value : 0
	case .Entities:
		if e.Ldtk_Doc_EntityDef(L.doc, L.entityDef) == nil do L.entityDef = len(L.doc.entityDefs) > 0 ? L.doc.entityDefs[0].uid : -1
	case .Tiles, .AutoLayer:
	}
}

// level_follow_layer_uid keeps the active layer on the same definition when
// layers are added, removed or reordered.
level_follow_layer_uid :: proc() {
	L := &GlobalLevel
	if L.doc == nil || len(L.doc.levels) == 0 do return
	lv := &L.doc.levels[L.level]
	if L.layer >= 0 && L.layer < len(lv.layers) {
		if d := e.Ldtk_Doc_LayerDef(L.doc, &lv.layers[L.layer]); d != nil && d.uid == L.layerUid do return
	}
	for &ly, i in lv.layers {
		if d := e.Ldtk_Doc_LayerDef(L.doc, &ly); d != nil && d.uid == L.layerUid {
			L.layer = i
			return
		}
	}
	L.layer = clamp(L.layer, 0, max(len(lv.layers) - 1, 0))
	if ly, d := level_active_layer(); ly != nil && d != nil do L.layerUid = d.uid
}

level_active_layer :: proc() -> (^e.Ldtk_DocLayer, ^e.Ldtk_DocLayerDef) {
	L := &GlobalLevel
	if L.doc == nil || L.level < 0 || L.level >= len(L.doc.levels) do return nil, nil
	lv := &L.doc.levels[L.level]
	if L.layer < 0 || L.layer >= len(lv.layers) do return nil, nil
	ly := &lv.layers[L.layer]
	return ly, e.Ldtk_Doc_LayerDef(L.doc, ly)
}

// LevelEditor_Save writes the project (and changed external levels) like
// LDtk's saver: BeforeSave commands (the save waits for them), a backup,
// the files, exports, AfterSave commands.
LevelEditor_Save :: proc(state: ^EditorState) -> bool {
	L := &GlobalLevel
	if L.doc == nil do return false
	if LevelCommands_Busy() {
		Editor_Log(state, .Warn, "A custom command is running: save again when it ends")
		return false
	}
	has := false
	for c in e.LdtkJson_Arr(L.doc.root, "customCommands") do if e.LdtkJson_Str(c, "when") == "BeforeSave" && strings.trim_space(e.LdtkJson_Str(c, "command")) != "" do has = true
	if has {
		LevelCommands_Run(state, "BeforeSave", .Save)
		return true
	}
	return LevelEditor_SaveNow(state)
}

// LevelEditor_SaveNow: the save itself (after the BeforeSave commands).
LevelEditor_SaveNow :: proc(state: ^EditorState) -> bool {
	L := &GlobalLevel
	if L.doc == nil do return false
	LevelProject_BeforeSave(state)
	if !e.Ldtk_Doc_Save(L.doc) {
		Editor_Log(state, .Error, "Could not save %s", L.rel)
		return false
	}
	Editor_Log(state, .Info, "Saved level %s", L.rel)
	LevelExtras_ProjectSaved()
	LevelProject_AfterSave(state)
	Editor_InvalidateProjectFiles()
	return true
}

// LevelEditor_SetLevel makes a level active (keeping the layer by def).
LevelEditor_SetLevel :: proc(li: int) {
	L := &GlobalLevel
	if L.doc == nil || li < 0 || li >= len(L.doc.levels) || li == L.level do return
	defUid := -1
	if ly, d := level_active_layer(); ly != nil && d != nil do defUid = d.uid
	L.level = li
	L.world = L.doc.levels[li].world
	level_clear_selection()
	L.layer = 0
	found := false
	for &ly, i in L.doc.levels[li].layers {
		if d := e.Ldtk_Doc_LayerDef(L.doc, &ly); d != nil && d.uid == defUid {
			L.layer = i
			found = true
		}
	}
	if !found do level_pick_default_layer()
	else do level_sync_palette()
}

// ----------------------------------------------------------------------------
// Root tabs
// ----------------------------------------------------------------------------

ROOT_TABS_HEIGHT :: f32(30)

// RootTabs_Render draws the Game / Level strip under the toolbar.
RootTabs_Render :: proc(state: ^EditorState, width, posY: f32) {
	L := &GlobalLevel
	imgui.SetNextWindowPos({0, posY})
	imgui.SetNextWindowSize({width, ROOT_TABS_HEIGHT})
	flags: imgui.WindowFlags = {.NoTitleBar, .NoResize, .NoMove, .NoScrollbar, .NoSavedSettings, .NoDocking, .NoScrollWithMouse, .NoBringToFrontOnFocus}
	imgui.PushStyleVarImVec2(.WindowPadding, {10, 3})
	imgui.PushStyleVarImVec2(.ItemSpacing, {2, 0})
	imgui.PushStyleColorImVec4(.WindowBg, UI_BG_APP)
	defer {
		imgui.PopStyleColor()
		imgui.PopStyleVar(2)
	}
	defer imgui.End()
	if !imgui.Begin("RootTabs###RootTabsWindow", nil, flags) do return
	Drive_Window("roottabs") // (annotated docs screenshots)
	tab :: proc(label: string, id: string, active: bool) -> bool {
		imgui.PushStyleVarImVec2(.FramePadding, {14, 4})
		if active {
			imgui.PushStyleColorImVec4(.Button, UI_BG_PANEL)
			imgui.PushStyleColorImVec4(.ButtonHovered, UI_BG_PANEL)
			imgui.PushStyleColorImVec4(.Text, UI_TEXT)
		} else {
			imgui.PushStyleColorImVec4(.Button, {0, 0, 0, 0})
			imgui.PushStyleColorImVec4(.ButtonHovered, UI_BG_HOVER)
			imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
		}
		imgui.PushFont(GlobalFonts.semibold)
		pressed := imgui.Button(fmt.ctprintf("%s##%s", label, id))
		imgui.PopFont()
		if active {
			mn, mx := imgui.GetItemRectMin(), imgui.GetItemRectMax()
			imgui.DrawList_AddLine(imgui.GetWindowDrawList(), {mn.x + 6, mx.y - 1}, {mx.x - 6, mx.y - 1}, col_u32(UI_ACCENT), 2)
		}
		imgui.PopStyleColor(3)
		imgui.PopStyleVar()
		Drive_Item(id)
		imgui.SameLine()
		return pressed
	}
	if tab(fmt.tprintf("%s  Game", ICON_FA_GAMEPAD), "root.game", L.tab == .Game) do L.tab = .Game
	UI_Tooltip("Scenes, nodes and scripts (Cmd+Shift+1)")
	levelLabel := fmt.tprintf("%s  Level", ICON_FA_MAP)
	if L.doc != nil do levelLabel = fmt.tprintf("%s  Level  -  %s%s", ICON_FA_MAP, filepath.base(L.rel), L.doc.modified ? "  " + ICON_FA_CIRCLE : "")
	if tab(levelLabel, "root.level", L.tab == .Level) do L.tab = .Level
	UI_Tooltip("Edit LDtk levels: worlds, layers, tiles, auto-tile rules, entities (Cmd+Shift+2)")
}

// ----------------------------------------------------------------------------
// Main render (the Level tab's dock space and panels)
// ----------------------------------------------------------------------------

LEVEL_CANVAS_WINDOW :: "Level###LevelCanvasWindow"
LEVEL_LEVELS_WINDOW :: "Levels###LevelLevelsWindow"
LEVEL_LAYERS_WINDOW :: "Layers###LevelLayersWindow"
LEVEL_PANEL_WINDOW :: "Level Panel###LevelPanelWindow"

LevelEditor_Render :: proc(state: ^EditorState, pos, size: [2]f32) {
	L := &GlobalLevel
	L.dockPos, L.dockSize = pos, size
	imgui.SetNextWindowPos(pos)
	imgui.SetNextWindowSize(size)
	hostFlags: imgui.WindowFlags = {.NoTitleBar, .NoCollapse, .NoResize, .NoMove, .NoBringToFrontOnFocus, .NoNavFocus, .NoBackground}
	imgui.PushStyleVarImVec2(.WindowPadding, {0, 0})
	imgui.Begin("##LevelDockSpaceHost", nil, hostFlags)
	imgui.PopStyleVar()
	dockID := imgui.GetID("LevelEditorDockSpace_v3")
	if DockBuilderGetNode(dockID) == nil || !L.dockBuilt {
		L.dockBuilt = true
		if DockBuilderGetNode(dockID) == nil {
			DockBuilderRemoveNode(dockID)
			DockBuilderAddNode(dockID, 0)
			DockBuilderSetNodePos(dockID, pos)
			DockBuilderSetNodeSize(dockID, size)
			// Levels | canvas over the bottom panel | Layers; the side
			// panels run the full height (300 px of 1920 at the start)
			main := dockID
			left, right, bottom: imgui.ID
			DockBuilderSplitNode(main, .Left, 0.156, &left, &main)
			DockBuilderSplitNode(main, .Right, 0.185, &right, &main)
			DockBuilderSplitNode(main, .Down, 0.37, &bottom, &main)
			DockBuilderDockWindow(LEVEL_LEVELS_WINDOW, left)
			DockBuilderDockWindow(LEVEL_LAYERS_WINDOW, right)
			DockBuilderDockWindow(LEVEL_PANEL_WINDOW, bottom)
			DockBuilderDockWindow(LEVEL_CANVAS_WINDOW, main)
			DockBuilderFinish(dockID)
		}
	}
	dockFlags: imgui.DockNodeFlags = {.PassthruCentralNode}
	if !GlobalSettings.showTabBars do dockFlags += {.AutoHideTabBar}
	imgui.DockSpace(dockID, {0, 0}, dockFlags)
	imgui.End()

	if L.doc == nil {
		level_start_page(state)
	} else {
		if L.level >= len(L.doc.levels) do L.level = max(len(L.doc.levels) - 1, 0)
		level_follow_layer_uid()
		level_sync_selection()
		level_sync_textures(state)
		LevelCanvas_Render(state)
		if !L.zen {
			level_levels_panel(state)
			level_layers_panel(state)
			level_bottom_panel(state)
		}
		LevelDefs_NewLayerDialog(state)
		LevelExtras_Palette(state)
		LevelExtras_Watch(state)
		level_rename_popup(state)
		LevelCommands_Update(state)
		LevelCommands_Window(state)
	}
	level_prompts(state)
}

// level_start_page: the canvas window without a document (pick / create).
@(private = "file")
level_start_page :: proc(state: ^EditorState) {
	L := &GlobalLevel
	if imgui.Begin(LEVEL_CANVAS_WINDOW, nil, {}) {
		PanelHelp_Mark("level") // (F1 here: the Level Editor Reference; Help menu: level.md)
		imgui.Dummy({0, 16})
		imgui.Indent(24)
		imgui.PushFont(GlobalFonts.semibold)
		imgui.TextUnformatted(fmt.ctprintf("%s  Level editor", ICON_FA_MAP))
		imgui.PopFont()
		UI_DimText("Edit LDtk projects (.ldtk) here: levels, layers, tiles, auto-tile rules and entities.")
		UI_DimText("The file stays an LDtk project, so it still opens in LDtk and the game reads it.")
		imgui.Dummy({0, 12})
		files := Editor_ListProjectFiles(state, "", {".ldtk"})
		if len(files) > 0 {
			UI_SectionHeader("Project levels")
			for rel in files {
				if UI_Button(fmt.tprintf("%s  %s", ICON_FA_TABLE_CELLS, rel), fmt.tprintf("level.open:%s", rel)) do LevelEditor_Open(state, rel)
				level_tip(fmt.tprintf("Open %s", rel), "overview")
			}
			imgui.Dummy({0, 8})
		}
		if UI_PrimaryButton(fmt.tprintf("%s  New LDtk Project...", ICON_FA_PLUS), "level.new") {
			L.newPrompt = true
			copy(L.nameBuf[:], "levels/world.ldtk\x00")
		}
		level_tip("A new LDtk project file in this project (one level, an IntGrid layer)", "overview")
		imgui.Unindent(24)
	}
	imgui.End()
	for w in ([]cstring{LEVEL_LEVELS_WINDOW, LEVEL_LAYERS_WINDOW, LEVEL_PANEL_WINDOW}) {
		if imgui.Begin(w, nil, {}) do UI_DimText("  No level open.")
		imgui.End()
	}
}

@(private = "file")
level_prompts :: proc(state: ^EditorState) {
	L := &GlobalLevel
	if L.newPrompt {
		imgui.OpenPopup("New LDtk Project###LevelNewPrompt")
		L.newPrompt = false
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if imgui.BeginPopupModal("New LDtk Project###LevelNewPrompt", nil, {.AlwaysAutoResize}) {
		UI_DimText("Project-relative path of the new .ldtk file:")
		imgui.SetNextItemWidth(360)
		if imgui.IsWindowAppearing() do imgui.SetKeyboardFocusHere()
		enter := imgui.InputText("##level_new_path", cstring(raw_data(L.nameBuf[:])), len(L.nameBuf), {.EnterReturnsTrue}) || imgui.IsItemDeactivatedAfterEdit()
		Drive_Item("level.new.path")
		level_tip("Relative to the game project (.ldtk is added)", "overview")
		rel := strings.trim_space(string(cstring(raw_data(L.nameBuf[:]))))
		if !strings.has_suffix(rel, ".ldtk") do rel = fmt.tprintf("%s.ldtk", rel)
		exists := os.exists(level_abs(state, rel))
		if exists do UI_DimText("A file with this name exists.")
		if (UI_PrimaryButton("Create", "level.new.create") || enter) && !exists && rel != ".ldtk" {
			path := level_abs(state, rel)
			_ = os.make_directory_all(filepath.dir(path, context.temp_allocator))
			if doc, ok := e.Ldtk_Doc_New(path); ok {
				e.Ldtk_Doc_Save(doc)
				e.Ldtk_Doc_Destroy(doc)
				Editor_InvalidateProjectFiles()
				LevelEditor_Open(state, rel)
				Editor_Log(state, .Info, "Created %s", rel)
			}
			imgui.CloseCurrentPopup()
		}
		level_tip("Create the file and open it", "overview")
		imgui.SameLine()
		if UI_Button("Cancel", "level.new.cancel") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
		level_tip("Close without creating a file", "overview")
		imgui.EndPopup()
	}
	if L.closePrompt {
		imgui.OpenPopup("Unsaved Level###LevelClosePrompt")
		L.closePrompt = false
	}
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if imgui.BeginPopupModal("Unsaved Level###LevelClosePrompt", nil, {.AlwaysAutoResize}) {
		imgui.TextUnformatted(fmt.ctprintf("%s has unsaved changes.", L.rel))
		imgui.Dummy({0, 6})
		next := strings.clone(L.closeThen, context.temp_allocator)
		finish :: proc(state: ^EditorState, next: string) {
			level_close_doc()
			delete(GlobalLevel.closeThen)
			GlobalLevel.closeThen = ""
			if next != "" do LevelEditor_Open(state, next)
			imgui.CloseCurrentPopup()
		}
		if UI_PrimaryButton("Save", "level.close.save") {
			if LevelEditor_Save(state) do finish(state, next)
		}
		level_tip("Save the changes, then close", "saving")
		imgui.SameLine()
		if UI_Button("Don't Save", "level.close.discard") do finish(state, next)
		level_tip("Close and lose the changes", "saving")
		imgui.SameLine()
		if UI_Button("Cancel", "level.close.cancel") || imgui.IsKeyPressed(.Escape) {
			delete(L.closeThen)
			L.closeThen = ""
			imgui.CloseCurrentPopup()
		}
		level_tip("Keep editing", "saving")
		imgui.EndPopup()
	}
}

// LevelEditor_Close closes the document (asks about unsaved changes).
LevelEditor_Close :: proc(state: ^EditorState) {
	L := &GlobalLevel
	if L.doc == nil do return
	if L.doc.modified {
		L.closePrompt = true
		return
	}
	level_close_doc()
}

// LevelEditor_HasUnsaved: for the quit prompt.
LevelEditor_HasUnsaved :: proc() -> bool {return GlobalLevel.doc != nil && GlobalLevel.doc.modified}

LevelEditor_Shutdown :: proc() {
	L := &GlobalLevel
	level_close_doc()
	delete(L.textures)
	delete(L.bgTextures)
	delete(L.tileSel)
	delete(L.closeThen)
	e.Ldtk_Selection_Destroy(&L.sel)
	e.Ldtk_Clipboard_Destroy(&L.clip)
	if L.rt.id != 0 do rl.UnloadRenderTexture(L.rt)
	L.rt = {}
}

// level_sync_textures loads the tilesets' images (again after defs change).
@(private = "file")
level_sync_textures :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	if L.texDefsRev == doc.defsRevision do return
	L.texDefsRev = doc.defsRevision
	keep := make(map[int]bool, allocator = context.temp_allocator)
	for &ts in doc.tilesets {
		keep[ts.uid] = true
		if _, ok := L.textures[ts.uid]; ok || ts.relPath == "" do continue
		p, _ := filepath.join({doc.dir, ts.relPath}, context.temp_allocator)
		if !os.exists(p) do continue
		tex := rl.LoadTexture(strings.clone_to_cstring(p, context.temp_allocator))
		if tex.id != 0 do L.textures[ts.uid] = tex
	}
	for uid, t in L.textures {
		if !keep[uid] {
			rl.UnloadTexture(t)
			delete_key(&L.textures, uid)
		}
	}
}

// level_bg_texture: a level background image (loaded once; id 0 when the
// file can't be read).
level_bg_texture :: proc(rel: string) -> rl.Texture2D {
	L := &GlobalLevel
	if t, ok := L.bgTextures[rel]; ok do return t
	p, _ := filepath.join({L.doc.dir, rel}, context.temp_allocator)
	tex: rl.Texture2D
	if os.exists(p) do tex = rl.LoadTexture(strings.clone_to_cstring(p, context.temp_allocator))
	L.bgTextures[strings.clone(rel)] = tex
	return tex
}

// level_reload_texture / level_reload_bg_texture: the image changed on disk.
level_reload_texture :: proc(uid: int) {
	L := &GlobalLevel
	if t, ok := L.textures[uid]; ok {
		rl.UnloadTexture(t)
		delete_key(&L.textures, uid)
	}
	L.texDefsRev = 0 // reloaded on the next frame
}

level_reload_bg_texture :: proc(rel: string) {
	L := &GlobalLevel
	for k, t in L.bgTextures do if k == rel {
		if t.id != 0 do rl.UnloadTexture(t)
		delete_key(&L.bgTextures, k)
		delete(k)
		break
	}
}

level_texture :: proc(uid: int) -> (rl.Texture2D, bool) {
	t, ok := GlobalLevel.textures[uid]
	return t, ok
}

// level_texture_ptr: for imgui.Image, which keeps the pointer until the frame
// is drawn (map entries don't move during a frame).
level_texture_ptr :: proc(uid: int) -> ^rl.Texture2D {
	if uid not_in GlobalLevel.textures do return nil
	return &GlobalLevel.textures[uid]
}

// ----------------------------------------------------------------------------
// Levels panel
// ----------------------------------------------------------------------------

@(private = "file")
level_levels_panel :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	defer imgui.End()
	if !imgui.Begin(LEVEL_LEVELS_WINDOW, nil, {}) do return
	PanelHelp_Mark("level") // (F1 here: the Level Editor Reference; Help menu: level.md)
	Drive_Window("level-levels") // (annotated docs screenshots)
	LevelRef_Panel("panel.levels")
	UI_PanelTitle(ICON_FA_GLOBE, "Levels", fmt.tprintf("%d", len(doc.levels)))
	UI_HeaderButtons(3)
	if UI_HeaderButton(ICON_FA_CIRCLE_QUESTION, "level.help.levels", "") do LevelRef_Open("panel.levels")
	level_tip("About the Levels panel", "panel.levels")
	addClicked := UI_HeaderButton(ICON_FA_PLUS, "level.add", "")
	if addClicked && !imgui.GetIO().KeyShift {
		L.spotPick = true
		Editor_Log(state, .Info, "Click where the new level goes (Esc cancels)")
	} else if addClicked {
		pos := [2]int{0, 0}
		size := [2]int{e.Ldtk_Doc_WorldInt(doc, L.world, "defaultLevelWidth", 256), e.Ldtk_Doc_WorldInt(doc, L.world, "defaultLevelHeight", 256)}
		step := LdtkJson_GridVania(doc) ? max(e.Ldtk_Doc_WorldInt(doc, L.world, "worldGridWidth", 256), 1) : 1
		if len(doc.levels) > 0 {
			p := e.Ldtk_Doc_LevelPos(doc, L.level)
			s := e.Ldtk_Doc_LevelSize(doc, L.level)
			pos = {p.x + s.x, p.y}
			if step > 1 do pos.x = (pos.x + step - 1) / step * step
		}
		pos = e.Ldtk_Doc_FreeLevelSpot(doc, L.world, pos, size, step)
		e.Ldtk_Doc_Checkpoint(doc, -1, "Add Level")
		li := e.Ldtk_Doc_AddLevel(doc, L.world, pos)
		e.Ldtk_Doc_ApplyAutoLevelIdentifiers(doc, L.world)
		L.level = -1
		LevelEditor_SetLevel(li)
	}
	level_tip("Add a level: click where it goes in the canvas (Shift+click: right next to the active one)", "panel.levels")
	if UI_HeaderButton(ICON_FA_TRASH, "level.remove", "") && level_world_count(L.world) > 1 {
		e.Ldtk_Doc_Checkpoint(doc, -1, "Delete Level")
		e.Ldtk_Doc_RemoveLevel(doc, L.level)
		level_keep_world_level()
		level_clear_selection()
		level_pick_default_layer()
	}
	level_tip("Delete the active level (undo brings it back)", "panel.levels")
	if doc.multiWorlds {
		names := make([]string, len(doc.worlds), context.temp_allocator)
		for w, i in doc.worlds do names[i] = e.LdtkJson_Str(w.obj, "identifier", fmt.tprintf("World %d", i))
		imgui.SetNextItemWidth(-1)
		if wi, changed := UI_Combo("level.world", L.world, names); changed {
			L.world = wi
			for lv, i in doc.levels do if lv.world == wi {
				L.level = -1
				LevelEditor_SetLevel(i)
				L.fitRequest = true
				break
			}
		}
		level_tip("The world whose levels the list and the canvas show", "worlds")
	}
	imgui.Separator()
	filter := level_filter_box("levels", "Filter levels")
	if imgui.BeginChild("##level_list", {0, 0}, {}, {}) {
		for &lv, i in doc.levels {
			if lv.world != L.world do continue
			name := e.LdtkJson_Str(lv.obj, "identifier")
			if !level_filter_hit(filter, name) do continue
			s := e.Ldtk_Doc_LevelSize(doc, i)
			c := e.Ldtk_ParseHexColor(e.LdtkJson_Str(lv.obj, "__bgColor", "#696A79"))
			p := imgui.GetCursorScreenPos()
			imgui.DrawList_AddRectFilled(imgui.GetWindowDrawList(), {p.x + 4, p.y + 5}, {p.x + 14, p.y + 15}, col_u32({f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, 1}), 2, {})
			imgui.SetCursorScreenPos({p.x + 20, p.y})
			if imgui.Selectable(fmt.ctprintf("%s%s##lvl%d", name, lv.dirty ? " *" : "", i), i == L.level, {.AllowDoubleClick}, {0, 20}) {
				LevelEditor_SetLevel(i)
				if imgui.IsMouseDoubleClicked(.Left) do L.fitRequest = true
			}
			Drive_Item(fmt.tprintf("level.pick:%s", name))
			level_tip(fmt.tprintf("%s - %dx%d px. Double-click to frame it; right-click for more.", name, s.x, s.y), "panel.levels")
			level_row_menu(state, i)
			// the size, when it fits next to the name
			size := fmt.ctprintf("%dx%d", s.x, s.y)
			sw := imgui.CalcTextSize(size).x
			if imgui.GetItemRectMax().x - imgui.GetItemRectMin().x - imgui.CalcTextSize(fmt.ctprintf("%s *", name)).x > sw + 16 {
				imgui.SameLine(imgui.GetContentRegionMax().x - sw - 4)
				UI_DimText(string(size))
			}
		}
	}
	imgui.EndChild()
}

// level_keep_world_level: after a level is deleted, the active level is
// one of the same world.
level_keep_world_level :: proc() {
	L := &GlobalLevel
	L.level = clamp(L.level, 0, len(L.doc.levels) - 1)
	if L.doc.levels[L.level].world != L.world {
		for lv, i in L.doc.levels do if lv.world == L.world {
			L.level = i
			break
		}
	}
	L.world = L.doc.levels[L.level].world
}

// level_move_scope: the undo scope of a level move - the whole project when
// automatic identifiers may rename other levels.
level_move_scope :: proc() -> int {
	L := &GlobalLevel
	for &lv in L.doc.levels do if lv.world == L.world && e.LdtkJson_Bool(lv.obj, "useAutoIdentifier") do return -1
	return L.level
}

// level_world_count: the number of levels in a world.
level_world_count :: proc(world: int) -> int {
	n := 0
	for lv in GlobalLevel.doc.levels do if lv.world == world do n += 1
	return n
}

// ctx_item: a context-menu entry with a tooltip (drives: "ctx:<label>").
ctx_item :: proc(icon, label: string, tip: string, enabled := true, shortcut := "") -> bool {
	clicked := imgui.MenuItem(fmt.ctprintf("%s  %s", icon, label), shortcut != "" ? fmt.ctprintf("%s", shortcut) : nil, false, enabled)
	Drive_Item(fmt.tprintf("ctx:%s", label))
	if tip != "" && imgui.IsItemHovered(imgui.HoveredFlags_AllowWhenDisabled) do imgui.SetTooltip("%s", fmt.ctprintf("%s", tip))
	return clicked
}

// level_row_menu: a level's right-click menu.
@(private = "file")
level_row_menu :: proc(state: ^EditorState, li: int) {
	L := &GlobalLevel
	doc := L.doc
	if !imgui.BeginPopupContextItem(fmt.ctprintf("##lvlctx%d", li)) do return
	defer imgui.EndPopup()
	name := e.Ldtk_Doc_LevelName(doc, li)
	if ctx_item(ICON_FA_FOLDER_OPEN, "Open", "Make it the active level") do LevelEditor_SetLevel(li)
	if ctx_item(ICON_FA_EXPAND, "Frame", "Open it and fit it in the canvas") {
		LevelEditor_SetLevel(li)
		L.fitRequest = true
	}
	imgui.Separator()
	if ctx_item(ICON_FA_PEN_TO_SQUARE, "Rename...", "Change its identifier (external level files are renamed too)") {
		L.renameLevel = li
		L.renameRequest = true
		L.renameBuf = {}
		copy(L.renameBuf[:len(L.renameBuf) - 1], name)
	}
	if ctx_item(ICON_FA_CLONE, "Duplicate", "Copy the level with its content, next to it") {
		e.Ldtk_Doc_Checkpoint(doc, -1, "Duplicate Level")
		if ni := e.Ldtk_Doc_DuplicateLevel(doc, li); ni >= 0 {
			L.level = -1
			LevelEditor_SetLevel(ni)
		}
	}
	if ctx_item(ICON_FA_ARROW_UP, "Move up", "Earlier in the list (the order of linear layouts)", li > 0 && doc.levels[li - 1].world == doc.levels[li].world) {
		e.Ldtk_Doc_Checkpoint(doc, -1, "Reorder Levels")
		L.level = e.Ldtk_Doc_MoveLevelOrder(doc, li, -1)
	}
	if ctx_item(ICON_FA_ARROW_DOWN, "Move down", "Later in the list", li + 1 < len(doc.levels) && doc.levels[li + 1].world == doc.levels[li].world) {
		e.Ldtk_Doc_Checkpoint(doc, -1, "Reorder Levels")
		L.level = e.Ldtk_Doc_MoveLevelOrder(doc, li, 1)
	}
	imgui.Separator()
	if ctx_item(ICON_FA_TRASH, "Delete", "Delete the level (undo brings it back; not a world's last level)", level_world_count(doc.levels[li].world) > 1) {
		e.Ldtk_Doc_Checkpoint(doc, -1, "Delete Level")
		e.Ldtk_Doc_RemoveLevel(doc, li)
		level_keep_world_level()
		level_clear_selection()
		level_pick_default_layer()
	}
	imgui.Separator()
	if ctx_item(ICON_FA_CIRCLE_QUESTION, "Help", "The Levels panel in the reference") do LevelRef_Open("panel.levels")
}

// level_rename_popup: the Rename dialog of the Levels menu.
@(private = "file")
level_rename_popup :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	if L.renameRequest {
		imgui.OpenPopup("Rename Level###LevelRename")
		L.renameRequest = false
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if !imgui.BeginPopupModal("Rename Level###LevelRename", nil, {.AlwaysAutoResize}) do return
	defer imgui.EndPopup()
	imgui.SetNextItemWidth(300)
	if imgui.IsWindowAppearing() do imgui.SetKeyboardFocusHere()
	enter := imgui.InputText("##rename_level", cstring(raw_data(L.renameBuf[:])), len(L.renameBuf), {.EnterReturnsTrue}) || imgui.IsItemDeactivatedAfterEdit()
	Drive_Item("level.rename.name")
	level_tip("Letters, digits and _ (other characters become _)", "panel.levels")
	if UI_PrimaryButton("Rename", "level.rename.ok") || enter {
		if L.renameLevel >= 0 && L.renameLevel < len(doc.levels) {
			name := e.Ldtk_Doc_CleanIdentifier(doc, string(cstring(raw_data(L.renameBuf[:]))))
			e.Ldtk_Doc_Checkpoint(doc, L.renameLevel, "Rename Level")
			if !e.Ldtk_Doc_RenameLevel(doc, L.renameLevel, name) do Editor_Log(state, .Warn, "A level is already called %s", name)
		}
		imgui.CloseCurrentPopup()
	}
	level_tip("Rename the level (its external file too)", "panel.levels")
	imgui.SameLine()
	if UI_Button("Cancel", "level.rename.cancel") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
	level_tip("Keep the name", "panel.levels")
}

LdtkJson_GridVania :: proc(doc: ^e.Ldtk_Doc) -> bool {
	return e.Ldtk_Doc_WorldStr(doc, GlobalLevel.world, "worldLayout") == "GridVania"
}

// ----------------------------------------------------------------------------
// Layers panel (+ palette of the active layer)
// ----------------------------------------------------------------------------

LAYER_TYPE_ICON := [e.LdtkLayerType]string{
	.IntGrid   = ICON_FA_BORDER_ALL,
	.Entities  = ICON_FA_CUBE,
	.Tiles     = ICON_FA_TABLE_CELLS,
	.AutoLayer = ICON_FA_WAND_MAGIC_SPARKLES,
}

LAYER_TYPE_NAME := [e.LdtkLayerType]string{
	.IntGrid   = "IntGrid",
	.Entities  = "Entities",
	.Tiles     = "Tiles",
	.AutoLayer = "Auto",
}

// level_layers_panel: the active level's layers (top first) - grip to drag
// them into another order, "Type: Name", the eye on the right; + adds one.
// Under the list: the active layer's palette.
@(private = "file")
level_layers_panel :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	defer imgui.End()
	if !imgui.Begin(LEVEL_LAYERS_WINDOW, nil, {}) do return
	PanelHelp_Mark("level") // (F1 here: the Level Editor Reference; Help menu: level.md)
	Drive_Window("level-layers") // (annotated docs screenshots)
	LevelRef_Panel("panel.layers")
	UI_PanelTitle(ICON_FA_LAYER_GROUP, "Layers")
	UI_HeaderButtons(3)
	if UI_HeaderButton(ICON_FA_CIRCLE_QUESTION, "level.help.layers", "") do LevelRef_Open("panel.layers")
	level_tip("About the Layers panel", "panel.layers")
	if UI_HeaderButton(ICON_FA_PLUS, "level.layer.new", "") do LevelDefs_OpenNewLayer()
	level_tip("New layer: type, name, grid, tileset", "layer.new")
	if UI_HeaderButton(ICON_FA_SLIDERS, "level.layer.settings", "") do LevelEditor_ShowTab(.Layers)
	level_tip("Layer settings (the Layers tab)", "tab.layers")
	if len(doc.levels) == 0 {
		UI_DimText("No level.")
		return
	}
	lv := &doc.levels[L.level]
	ROW :: 26
	dropAt := -1 // drag: the row the dragged layer goes to
	targetY: f32 = -1
	targetX0, targetX1: f32
	m := imgui.GetIO().MousePos
	for &ly, i in lv.layers {
		d := e.Ldtk_Doc_LayerDef(doc, &ly)
		if d == nil do continue
		// "hide in list" layers stay out (unless active)
		if i != L.layer && e.LdtkJson_Bool(d.obj, "hideInList") do continue
		visible := e.LdtkJson_Bool(ly.obj, "visible", true)
		imgui.PushIDInt(i32(i))
		rowMin := imgui.GetCursorScreenPos()
		rowW := imgui.GetContentRegionAvail().x
		if hex := e.LdtkJson_Str(d.obj, "uiColor"); hex != "" {
			c := e.Ldtk_ParseHexColor(hex)
			imgui.DrawList_AddRectFilled(imgui.GetWindowDrawList(), {rowMin.x - 4, rowMin.y + 3}, {rowMin.x - 1, rowMin.y + ROW - 3}, col_u32({f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, 1}), 1, {})
		}
		// grip: press and drag to reorder
		imgui.AlignTextToFramePadding()
		imgui.PushStyleColorImVec4(.Text, UI_TEXT_FAINT)
		imgui.TextUnformatted(ICON_FA_GRIP_LINES)
		imgui.PopStyleColor()
		Drive_Item(fmt.tprintf("level.layer.grip:%s", d.identifier))
		level_tip("Drag to put the layer in another order (in every level)", "panel.layers")
		if imgui.IsItemHovered() do imgui.SetMouseCursor(.ResizeNS)
		if imgui.IsItemClicked() do L.layerDrag = i
		imgui.SameLine(0, 8)
		if !visible do imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
		label := fmt.ctprintf("%s: %s", LAYER_TYPE_NAME[d.type], d.identifier)
		if imgui.Selectable(label, i == L.layer, {.AllowOverlap}, {rowW - 60, ROW}) {
			L.layer = i
			level_clear_selection()
			level_sync_palette()
		}
		if !visible do imgui.PopStyleColor()
		Drive_Item(fmt.tprintf("level.layer:%s", d.identifier))
		layerTip := fmt.tprintf("%s layer \"%s\" (grid %d px). Click to edit it; right-click for more.", LAYER_TYPE_NAME[d.type], d.identifier, d.gridSize)
		if docText := e.LdtkJson_Str(d.obj, "doc"); docText != "" do layerTip = fmt.tprintf("%s\n\n%s", docText, layerTip)
		level_tip(layerTip, "panel.layers")
		if level_layer_menu(state, i, d.uid, visible) {
			imgui.PopID()
			return
		}
		imgui.SameLine(rowMin.x - imgui.GetWindowPos().x + rowW - 26)
		if UI_IconButton(visible ? ICON_FA_EYE : ICON_FA_EYE_SLASH, fmt.tprintf("level.eye:%s", d.identifier), "", false, 24) {
			e.Ldtk_Doc_Checkpoint(doc, L.level, "Layer Visibility")
			e.Ldtk_Doc_SetLayerVisible(doc, L.level, i, !visible)
		}
		level_tip(visible ? "Hide the layer in this level (saved, like LDtk)" : "Show the layer", "panel.layers")
		rowMax := [2]f32{rowMin.x + rowW, imgui.GetItemRectMax().y}
		if L.layerDrag >= 0 && m.y >= rowMin.y && m.y < rowMax.y + imgui.GetStyle().ItemSpacing.y {
			dropAt = i
			if dropAt > L.layerDrag {
				targetY = rowMax.y + imgui.GetStyle().ItemSpacing.y * 0.5
				targetX0, targetX1 = rowMin.x, rowMax.x
			} else if dropAt < L.layerDrag {
				targetY = rowMin.y - imgui.GetStyle().ItemSpacing.y * 0.5
				targetX0, targetX1 = rowMin.x, rowMax.x
			}
		}
		if L.layerDrag == i {
			imgui.DrawList_AddRect(imgui.GetWindowDrawList(), rowMin, rowMax, col_u32(UI_ACCENT), 3, {}, 1)
		}
		imgui.PopID()
	}
	if L.layerDrag >= 0 {
		// Draw blue insertion line at the exact position where the dragged layer will land
		if targetY >= 0 {
			dl := imgui.GetWindowDrawList()
			lineCol := col_u32(UI_ACCENT)
			imgui.DrawList_AddLine(dl, {targetX0, targetY}, {targetX1, targetY}, lineCol, 3.0)
			imgui.DrawList_AddCircleFilled(dl, {targetX0, targetY}, 4.0, lineCol)
			imgui.DrawList_AddCircleFilled(dl, {targetX1, targetY}, 4.0, lineCol)
		}
		// where it would land
		if dropAt >= 0 && dropAt != L.layerDrag {
			imgui.SetMouseCursor(.ResizeNS)
		}
		if !imgui.IsMouseDown(.Left) {
			from := L.layerDrag
			L.layerDrag = -1
			if dropAt >= 0 && dropAt != from && from < len(lv.layers) {
				if d := e.Ldtk_Doc_LayerDef(doc, &lv.layers[from]); d != nil {
					uid := d.uid
					e.Ldtk_Doc_Checkpoint(doc, -1, "Move Layer")
					step := dropAt > from ? 1 : -1
					for _ in 0 ..< abs(dropAt - from) do e.Ldtk_Doc_MoveLayerDef(doc, uid, step)
					L.layerUid = uid
					level_follow_layer_uid()
					return // the layers moved under this frame's list
				}
			}
		}
	}
	imgui.Separator()
	ly, d := level_active_layer()
	if ly == nil || d == nil do return
	switch d.type {
	case .IntGrid: level_palette_intgrid(state, d)
	case .Tiles: level_palette_tiles(state, ly)
	case .Entities: level_palette_entities(state)
	case .AutoLayer:
		if d.tilesetUid >= 0 do level_palette_tiles(state, ly)
		level_palette_auto(state, ly, d)
	}
	// rule tiles / terrains / animations are picked from the layer's tileset
	if d.type == .IntGrid && d.tilesetUid >= 0 {
		imgui.Dummy({0, 4})
		level_palette_tiles(state, ly)
	}
	if d.type == .IntGrid && len(d.groups) > 0 {
		imgui.Dummy({0, 4})
		level_palette_auto(state, ly, d)
	}
}

@(private = "file")
swatch :: proc(c: rl.Color, size: f32 = 14) {
	p := imgui.GetCursorScreenPos()
	h := imgui.GetFrameHeight()
	imgui.DrawList_AddRectFilled(imgui.GetWindowDrawList(), {p.x, p.y + (h - size) * 0.5}, {p.x + size, p.y + (h + size) * 0.5}, col_u32({f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, 1}), 3, {})
	imgui.Dummy({size, h})
	imgui.SameLine(0, 6)
}

@(private = "file")
level_palette_intgrid :: proc(state: ^EditorState, d: ^e.Ldtk_DocLayerDef) {
	L := &GlobalLevel
	UI_SectionHeader("Values")
	if len(d.values) == 0 do UI_DimText("No values: add some in the Layers tab.")
	groups := e.LdtkJson_Arr(d.obj, "intGridValuesGroups")
	vals := e.LdtkJson_Arr(d.obj, "intGridValues")
	// group order: ungrouped first, then the groups (LDtk's palette)
	order := make([dynamic]int, context.temp_allocator)
	gorder := make([dynamic]int, context.temp_allocator)
	append(&gorder, 0)
	for g in groups do append(&gorder, e.LdtkJson_Int(g, "uid"))
	for gu in gorder do for v, i in d.values do if v.groupUid == gu do append(&order, i)
	for v, i in d.values {
		found := false
		for o in order do if o == i do found = true
		if !found do append(&order, i) // a group that doesn't exist
	}
	lastGroup := -1
	for i in order {
		v := d.values[i]
		if len(groups) > 0 && v.groupUid != lastGroup {
			lastGroup = v.groupUid
			gname := "Ungrouped"
			for g in groups do if e.LdtkJson_Int(g, "uid") == v.groupUid do gname = e.LdtkJson_Str(g, "identifier", fmt.tprintf("Group %d", v.groupUid))
			UI_DimText(strings.to_upper(gname, context.temp_allocator))
		}
		// the icon, else the colour
		icon := false
		if i < len(vals) {
			if t := e.LdtkJson_Get(vals[i], "tile"); t != nil && t.kind == .Object {
				if ptr := level_texture_ptr(e.LdtkJson_Int(t, "tilesetUid", -1)); ptr != nil {
					tw, th := f32(ptr.width), f32(ptr.height)
					x, y, w, h := f32(e.LdtkJson_Int(t, "x")), f32(e.LdtkJson_Int(t, "y")), f32(e.LdtkJson_Int(t, "w")), f32(e.LdtkJson_Int(t, "h"))
					imgui.Image(transmute(imgui.TextureID)ptr, {18, 18}, {x / tw, y / th}, {(x + w) / tw, (y + h) / th})
					imgui.SameLine(0, 6)
					icon = true
				}
			}
		}
		if !icon do swatch(v.color)
		label := v.identifier != "" ? v.identifier : fmt.tprintf("value %d", v.value)
		if imgui.Selectable(fmt.ctprintf("%d  %s##iv%d", v.value, label, i), L.intValue == v.value, {}, {0, 22}) do L.intValue = v.value
		Drive_Item(fmt.tprintf("level.value:%d", v.value))
		level_tip(fmt.tprintf("Value %d (%s)%s. Click, then paint; right-click for more.", v.value, label, i < 9 ? fmt.tprintf(" - key %d", i + 1) : ""), "palette.intgrid")
		if imgui.BeginPopupContextItem(fmt.ctprintf("##ivctx%d", i)) {
			if ctx_item(ICON_FA_PAINTBRUSH, "Paint with it", "Pick it and the Brush") {
				L.intValue = v.value
				L.tool = .Brush
			}
			if ctx_item(ICON_FA_OBJECT_UNGROUP, "Select its cells", "Select every cell of this value in the layer") {
				level_clear_selection()
				lv := &L.doc.levels[L.level]
				ly := &lv.layers[L.layer]
				for cy in 0 ..< ly.cHei do for cx in 0 ..< ly.cWid do if e.Ldtk_Doc_GetIntGrid(ly, cx, cy) == v.value do append(&L.sel.cells, e.Ldtk_SelCell{L.layer, cx, cy})
				level_sync_selection()
			}
			if ctx_item(ICON_FA_SLIDERS, "Edit values", "Name, colour, add / remove values (Layers tab)") {
				LevelDefs_SelectLayer(d.uid)
				LevelEditor_ShowTab(.Layers)
			}
			imgui.Separator()
			if ctx_item(ICON_FA_CIRCLE_QUESTION, "Help", "IntGrid values in the reference") do LevelRef_Open("palette.intgrid")
			imgui.EndPopup()
		}
	}
	UI_DimText("Left paints, right erases; 1-9 picks a value.")
}

@(private = "file")
level_palette_entities :: proc(state: ^EditorState) {
	L := &GlobalLevel
	UI_SectionHeader("Entities")
	if len(L.doc.entityDefs) == 0 do UI_DimText("No entities: add some in the Entities tab.")
	for &ed in L.doc.entityDefs {
		swatch(ed.color)
		if imgui.Selectable(fmt.ctprintf("%s##ed%d", ed.identifier, ed.uid), L.entityDef == ed.uid, {}, {0, 22}) {
			L.entityDef = ed.uid
			if L.tool != .Brush do L.tool = .Brush
		}
		Drive_Item(fmt.tprintf("level.entity:%s", ed.identifier))
		level_tip(fmt.tprintf("%s (%dx%d). Click, then click in the level to place it; right-click for more.", ed.identifier, ed.size.x, ed.size.y), "palette.entities")
		if imgui.BeginPopupContextItem(fmt.ctprintf("##edctx%d", ed.uid)) {
			if ctx_item(ICON_FA_PAINTBRUSH, "Place", "Pick it and the Brush") {
				L.entityDef = ed.uid
				L.tool = .Brush
			}
			if ctx_item(ICON_FA_OBJECT_UNGROUP, "Select all of them", "Select its instances in this level") {
				level_clear_selection()
				for &ly, j in L.doc.levels[L.level].layers {
					for ent in e.LdtkJson_Arr(ly.obj, "entityInstances") do if e.LdtkJson_Int(ent, "defUid", -1) == ed.uid do append(&L.sel.entities, e.Ldtk_SelEntity{j, ent})
				}
				level_sync_selection()
			}
			if ctx_item(ICON_FA_SLIDERS, "Edit definition", "Size, colour, pivot, tile, fields (Entities tab)") {
				LevelDefs_SelectEntity(ed.uid)
				LevelEditor_ShowTab(.Entities)
			}
			imgui.Separator()
			if ctx_item(ICON_FA_CIRCLE_QUESTION, "Help", "Entities in the reference") do LevelRef_Open("palette.entities")
			imgui.EndPopup()
		}
	}
	UI_DimText("Brush places, Select (V) moves / resizes, Delete removes.")
}

@(private = "file")
level_palette_auto :: proc(state: ^EditorState, ly: ^e.Ldtk_DocLayer, d: ^e.Ldtk_DocLayerDef) {
	L := &GlobalLevel
	doc := L.doc
	UI_SectionHeader("Auto-layer rules")
	if d.type == .AutoLayer {
		src := e.Ldtk_Doc_LevelLayer(doc, &doc.levels[L.level], d.autoSourceUid)
		if src != nil {
			sd := e.Ldtk_Doc_LayerDef(doc, src)
			UI_DimText(fmt.tprintf("Tiles come from rules over \"%s\": paint that layer.", sd != nil ? sd.identifier : "?"))
		} else do UI_DimText("Pick the IntGrid layer it reads in the Layers tab.")
	}
	optional := e.LdtkJson_Get(ly.obj, "optionalRules")
	for &g in d.groups {
		count := len(g.rules)
		if g.isOptional {
			on := false
			if optional != nil do for o in optional.items do if int(o.num) == g.uid do on = true
			if imgui.Checkbox(fmt.ctprintf("%s  (%d)##og%d", g.name, count, g.uid), &on) {
				e.Ldtk_Doc_Checkpoint(doc, L.level, "Optional Rules")
				if optional == nil {
					optional = e.LdtkJson_New(.Array, doc.allocator)
					e.LdtkJson_Set(ly.obj, "optionalRules", optional, doc.allocator)
				}
				if on {
					append(&optional.items, e.LdtkJson_NewInt(g.uid, doc.allocator))
				} else {
					for o, i in optional.items do if int(o.num) == g.uid {
						ordered_remove(&optional.items, i)
						break
					}
				}
				e.Ldtk_Doc_ApplyRulesLayer(doc, L.level, L.layer)
			}
			level_tip("Optional group: on or off in this level", "palette.auto")
		} else {
			UI_DimText(fmt.tprintf("%s %s  (%d rules)", g.active ? ICON_FA_CIRCLE : "-", g.name, count))
			level_tip(g.active ? "Active rule group (edit it in the Rules tab)" : "Inactive rule group", "palette.auto")
		}
		if imgui.BeginPopupContextItem(fmt.ctprintf("##grpctx%d", g.uid)) {
			if ctx_item(ICON_FA_WAND_MAGIC_SPARKLES, "Edit rules", "This layer's rules in the Rules tab") {
				LevelDefs_SelectRulesLayer(d.uid)
				LevelEditor_ShowTab(.Rules)
			}
			if ctx_item(ICON_FA_CIRCLE_QUESTION, "Help", "Auto-layer rules in the reference") do LevelRef_Open("palette.auto")
			imgui.EndPopup()
		}
	}
	if UI_Button(fmt.tprintf("%s  Re-run rules", ICON_FA_ROTATE_RIGHT), "level.rerun") {
		e.Ldtk_Doc_ApplyRulesFull(doc, L.level)
	}
	level_tip("Regenerate this level's auto tiles", "palette.auto")
}

// level_palette_tiles: the tileset; click / drag selects the stamp.
@(private = "file")
level_palette_tiles :: proc(state: ^EditorState, ly: ^e.Ldtk_DocLayer) {
	L := &GlobalLevel
	ts := e.Ldtk_Doc_LayerTileset(L.doc, ly)
	if ts == nil {
		UI_DimText("This layer has no tileset (set one in the Layers tab).")
		return
	}
	tex, ok := level_texture(ts.uid)
	UI_SectionHeader(fmt.tprintf("Tileset  %s", ts.identifier))
	if UI_IconButton("X", "level.flipx", "", (L.flips & 1) != 0, 24) do L.flips ~= 1
	level_tip("Flip what you paint horizontally (X)", "palette.tiles")
	imgui.SameLine()
	if UI_IconButton("Y", "level.flipy", "", (L.flips & 2) != 0, 24) do L.flips ~= 2
	level_tip("Flip what you paint vertically (Y)", "palette.tiles")
	imgui.SameLine()
	if UI_IconButton(ICON_FA_DICE, "level.tilerandom", "", L.tileRandom, 24) do L.tileRandom = !L.tileRandom
	level_tip(L.tileRandom ? "Random mode: each cell gets one of the picked tiles at random (Shift+R)" : "Stamp mode: the picked tiles are painted as a block (Shift+R: random)", "tile.modes")
	imgui.SameLine()
	if UI_IconButton(ICON_FA_LAYER_GROUP, "level.tilestack", "", L.stacking, 24) do L.stacking = !L.stacking
	level_tip(L.stacking ? "Stacking on: tiles go on top of the cell's tiles (opaque tiles still replace them); erasing removes the top one (Shift+T)" : "Stacking off: a tile replaces the cell's tiles (Shift+T)", "tile.stacking")
	imgui.SameLine()
	if UI_IconButton(ICON_FA_BOOKMARK, "level.tilesave", "", false, 24) do palette_save_selection(ts.uid)
	level_tip("Save the picked tiles as a group: clicking one of them picks the whole group again (Shift+S)", "tile.saved")
	UI_SameLineOrWrap(94)
	imgui.SetNextItemWidth(90)
	imgui.SliderFloat("##palzoom", &L.paletteZoom, 0.5, 6, "zoom %.1fx")
	level_tip("Zoom the tileset", "palette.tiles")
	if !ok {
		UI_DimText(fmt.tprintf("Image not found: %s", ts.relPath))
		return
	}
	// at least a few rows tall: the panel scrolls to it below long rule lists
	// (the drive anchor is registered even when the child is scrolled away)
	{
		c := imgui.GetCursorScreenPos()
		Drive_ItemRect("level.palette", {c.x, c.y}, {c.x + 1, c.y + 1}, true)
	}
	if imgui.BeginChild("##tileset_palette", {0, clamp(imgui.GetContentRegionAvail().y, 180, 320)}, {}, {.HorizontalScrollbar}) {
		z := L.paletteZoom
		p := imgui.GetCursorScreenPos()
		w, h := f32(tex.width) * z, f32(tex.height) * z
		dl := imgui.GetWindowDrawList()
		imgui.InvisibleButton("##palette", {w, h})
		Drive_ItemRect("level.palette", {p.x, p.y}, {p.x + 1, p.y + 1}, true) // anchor: tile (0, 0)'s corner
		level_tip("Click a tile, or drag over several to paint them as a stamp. A saved group is picked whole (Alt + click: just the tile). Right-click for more.", "palette.tiles")
		palette_menu(ts.uid)
		imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)level_texture_ptr(ts.uid), p, {p.x + w, p.y + h})
		step := f32(ts.gridSize + ts.spacing) * z
		pad := f32(ts.padding) * z
		gs := f32(ts.gridSize) * z
		// grid
		for cx in 0 ..= ts.cWid do imgui.DrawList_AddLine(dl, {p.x + pad + f32(cx) * step, p.y}, {p.x + pad + f32(cx) * step, p.y + h}, col_u32(ui_line(0.08)), 1)
		for cy in 0 ..= ts.cHei do imgui.DrawList_AddLine(dl, {p.x, p.y + pad + f32(cy) * step}, {p.x + w, p.y + pad + f32(cy) * step}, col_u32(ui_line(0.08)), 1)
		mouse := imgui.GetIO().MousePos
		cell := [2]int{int((mouse.x - p.x - pad) / step), int((mouse.y - p.y - pad) / step)}
		cell = {clamp(cell.x, 0, max(ts.cWid - 1, 0)), clamp(cell.y, 0, max(ts.cHei - 1, 0))}
		if imgui.IsItemActivated() {
			L.paletteDrag = true
			L.paletteStart = cell
		}
		if L.paletteDrag {
			a, b := L.paletteStart, cell
			mn := [2]int{min(a.x, b.x), min(a.y, b.y)}
			mx := [2]int{max(a.x, b.x), max(a.y, b.y)}
			imgui.DrawList_AddRect(dl, {p.x + pad + f32(mn.x) * step, p.y + pad + f32(mn.y) * step}, {p.x + pad + f32(mx.x) * step + gs, p.y + pad + f32(mx.y) * step + gs}, col_u32(UI_WARNING), 0, {}, 2)
			if !imgui.IsMouseDown(.Left) {
				L.paletteDrag = false
				ids := make([dynamic]i32, context.temp_allocator)
				for y in mn.y ..= mx.y do for x in mn.x ..= mx.x do append(&ids, i32(x + y * ts.cWid))
				// one tile of a saved group: the group (LDtk)
				if len(ids) == 1 && !imgui.GetIO().KeyAlt {
					if saved, random, found := e.Ldtk_Doc_SavedSelectionFor(L.doc, ts.uid, int(ids[0])); found {
						clear(&ids)
						append(&ids, ..saved)
						L.tileRandom = random
					}
				}
				level_set_tile_sel(ids[:])
				if L.tool != .Rect && L.tool != .Fill do L.tool = .Brush
			}
		}
		// saved groups (faint) and the picked tiles (accent)
		outline :: proc(dl: ^imgui.DrawList, p: [2]f32, pad, step, gs: f32, cw: int, tid: int, col: u32, thick: f32) {
			x, y := tid % max(cw, 1), tid / max(cw, 1)
			imgui.DrawList_AddRect(dl, {p.x + pad + f32(x) * step, p.y + pad + f32(y) * step}, {p.x + pad + f32(x) * step + gs, p.y + pad + f32(y) * step + gs}, col, 0, {}, thick)
		}
		for sel in e.LdtkJson_Arr(ts.obj, "savedSelections") {
			for v in e.LdtkJson_Arr(sel, "ids") do outline(dl, {p.x, p.y}, pad, step, gs, ts.cWid, int(v.num), col_u32({1, 1, 1, 0.35}), 1)
		}
		for t in L.tileSel do outline(dl, {p.x, p.y}, pad, step, gs, ts.cWid, int(t), col_u32(UI_ACCENT), 2)
	}
	imgui.EndChild()
}

// palette_save_selection: Shift+S / the bookmark button.
palette_save_selection :: proc(tilesetUid: int) {
	L := &GlobalLevel
	if len(L.tileSel) < 2 do return
	e.Ldtk_Doc_Checkpoint(L.doc, -1, "Save Tile Selection")
	e.Ldtk_Doc_SaveTileSelection(L.doc, tilesetUid, L.tileSel[:], L.tileRandom)
}

// palette_menu: the tileset palette's right-click menu.
@(private = "file")
palette_menu :: proc(tilesetUid: int) {
	L := &GlobalLevel
	if !imgui.BeginPopupContextItem("##palettectx") do return
	defer imgui.EndPopup()
	_, _, saved := e.Ldtk_Doc_SavedSelectionFor(L.doc, tilesetUid, len(L.tileSel) > 0 ? int(L.tileSel[0]) : -1)
	if ctx_item(ICON_FA_BOOKMARK, "Save selection", "Save the picked tiles as a group", len(L.tileSel) >= 2, "Shift+S") do palette_save_selection(tilesetUid)
	if ctx_item(ICON_FA_TRASH, "Forget saved group", "Remove the saved group of the picked tiles", saved) {
		e.Ldtk_Doc_Checkpoint(L.doc, -1, "Forget Tile Selection")
		e.Ldtk_Doc_ForgetTileSelection(L.doc, tilesetUid, L.tileSel[:])
	}
	imgui.Separator()
	if ctx_item(ICON_FA_DICE, L.tileRandom ? "Stamp mode" : "Random mode", "Paint the picked tiles as a block, or one at random per cell", true, "Shift+R") do L.tileRandom = !L.tileRandom
	if ctx_item(ICON_FA_LAYER_GROUP, L.stacking ? "Stacking off" : "Stacking on", "Put tiles on top of the cell's tiles instead of replacing them", true, "Shift+T") do L.stacking = !L.stacking
	if ctx_item("X", "Flip X", "Mirror what you paint horizontally", true, "X") do L.flips ~= 1
	if ctx_item("Y", "Flip Y", "Mirror what you paint vertically", true, "Y") do L.flips ~= 2
	imgui.Separator()
	if ctx_item(ICON_FA_TABLE_CELLS, "Tileset settings", "The Tilesets tab: tile size, per-tile data, animations") do LevelEditor_ShowTab(.Tilesets)
	if ctx_item(ICON_FA_CIRCLE_QUESTION, "Help", "Tiles in the reference") do LevelRef_Open("palette.tiles")
}

// ----------------------------------------------------------------------------
// Inspector (level or selected entity)
// ----------------------------------------------------------------------------

// level_layer_menu: a layer row's right-click menu; true when the layers
// changed (stop drawing the list).
@(private = "file")
level_layer_menu :: proc(state: ^EditorState, i: int, uid: int, visible: bool) -> bool {
	L := &GlobalLevel
	doc := L.doc
	if !imgui.BeginPopupContextItem("##layerctx") do return false
	defer imgui.EndPopup()
	d := &doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(doc, uid)]
	if ctx_item(ICON_FA_SLIDERS, "Settings", "Its settings in the Layers tab") {
		LevelDefs_SelectLayer(uid)
		LevelEditor_ShowTab(.Layers)
	}
	if d.type == .IntGrid || d.type == .AutoLayer {
		if ctx_item(ICON_FA_WAND_MAGIC_SPARKLES, "Rules", "Its auto-layer rules in the Rules tab") {
			LevelDefs_SelectRulesLayer(uid)
			LevelEditor_ShowTab(.Rules)
		}
	}
	if d.type != .Entities && len(doc.tilesets) > 0 {
		menuOpen := imgui.BeginMenu(fmt.ctprintf("%s  Tileset in this level", ICON_FA_TABLE_CELLS))
		Drive_Item("ctx:Tileset in this level")
		level_tip("Paint this level's layer with another tileset (same grid)", "layer.tileset.override")
		if menuOpen {
			ly := &doc.levels[L.level].layers[i]
			cur := e.Ldtk_Doc_LayerTileset(doc, ly)
			if imgui.MenuItem("The layer's own", nil, e.LdtkJson_IsNull(ly.obj, "overrideTilesetUid")) {
				e.Ldtk_Doc_Checkpoint(doc, L.level, "Layer Tileset")
				e.Ldtk_Doc_SetLayerTilesetOverride(doc, L.level, i, -1)
			}
			Drive_Item("ctx:The layer's own")
			for &ts in doc.tilesets {
				if imgui.MenuItem(fmt.ctprintf("%s", ts.identifier), nil, cur != nil && cur.uid == ts.uid && !e.LdtkJson_IsNull(ly.obj, "overrideTilesetUid")) {
					e.Ldtk_Doc_Checkpoint(doc, L.level, "Layer Tileset")
					e.Ldtk_Doc_SetLayerTilesetOverride(doc, L.level, i, ts.uid)
				}
				Drive_Item(fmt.tprintf("ctx:%s", ts.identifier))
			}
			imgui.EndMenu()
		}
		UI_Tooltip("Use another tileset for this layer in this level only (the tiles keep their ids)")
	}
	if ctx_item(visible ? ICON_FA_EYE_SLASH : ICON_FA_EYE, visible ? "Hide" : "Show", "Per-level visibility (saved)") {
		e.Ldtk_Doc_Checkpoint(doc, L.level, "Layer Visibility")
		e.Ldtk_Doc_SetLayerVisible(doc, L.level, i, !visible)
	}
	if ctx_item(ICON_FA_OBJECT_UNGROUP, "Select all", "Select everything in this layer (Cmd+A)") {
		L.layer = i
		level_sync_palette()
		e.Ldtk_Doc_SelectAll(doc, L.level, &L.sel, i)
		level_sync_selection()
	}
	imgui.Separator()
	n := len(doc.levels[L.level].layers)
	if ctx_item(ICON_FA_ARROW_UP, "Move up", "Draw it above the layer over it (every level)", i > 0) {
		e.Ldtk_Doc_Checkpoint(doc, -1, "Move Layer")
		e.Ldtk_Doc_MoveLayerDef(doc, uid, -1)
		return true
	}
	if ctx_item(ICON_FA_ARROW_DOWN, "Move down", "Draw it below the layer under it", i + 1 < n) {
		e.Ldtk_Doc_Checkpoint(doc, -1, "Move Layer")
		e.Ldtk_Doc_MoveLayerDef(doc, uid, 1)
		return true
	}
	imgui.Separator()
	if ctx_item(ICON_FA_TRASH, "Delete layer", "Delete the layer and its content in every level (undo brings it back)") {
		e.Ldtk_Doc_Checkpoint(doc, -1, "Delete Layer")
		e.Ldtk_Doc_RemoveLayerDef(doc, uid)
		level_after_defs()
		return true
	}
	imgui.Separator()
	if ctx_item(ICON_FA_CIRCLE_QUESTION, "Help", "The Layers panel in the reference") do LevelRef_Open("panel.layers")
	return false
}

// level_bottom_panel: the bottom panel's tab bar and the current page.
@(private = "file")
level_bottom_panel :: proc(state: ^EditorState) {
	L := &GlobalLevel
	defer imgui.End()
	if !imgui.Begin(LEVEL_PANEL_WINDOW, nil, {}) do return
	PanelHelp_Mark("level") // (F1 here: the Level Editor Reference; Help menu: level.md)
	Drive_Window("level-panel") // (annotated docs screenshots)
	// a newly selected entity shows its values
	if L.selEntity != nil && L.selEntity != L.lastSel do L.panelRequest = .Level
	L.lastSel = L.selEntity
	LevelRef_Panel(LEVEL_TAB_TOPIC[L.panelTab])
	if imgui.BeginTabBar("##level_panel_tabs", {}) {
		for t in Level_Panel_Tab {
			flags: imgui.TabItemFlags = {}
			if req, ok := L.panelRequest.?; ok && req == t do flags += {.SetSelected}
			if imgui.BeginTabItem(fmt.ctprintf("%v###lvltab%v", t, t), nil, flags) {
				L.panelTab = t
				imgui.EndTabItem()
			}
			Drive_Item(fmt.tprintf("level.tab:%v", t))
			level_tip(LEVEL_TAB_TIP[t], LEVEL_TAB_TOPIC[t])
		}
		imgui.EndTabBar()
	}
	L.panelRequest = nil
	if imgui.BeginChild("##level_panel_page", {0, 0}, {}, {}) {
		if L.panelTab == .Level do level_tab_level(state)
		else do LevelDefs_Page(state, L.panelTab)
	}
	imgui.EndChild()
}

// level_tab_level: the active level's values, or the selected entity's.
@(private = "file")
level_tab_level :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	if len(doc.levels) == 0 do return
	if L.selEntity != nil {
		level_entity_inspector(state)
		return
	}
	lv := &doc.levels[L.level]
	// two columns: the level's values | its fields and the project
	avail := imgui.GetContentRegionAvail()
	leftW := min(avail.x, 460)
	if !imgui.BeginChild("##lvl_left", {leftW, avail.y}, {}, {}) {
		imgui.EndChild()
		return
	}
	UI_PanelTitle(ICON_FA_MAP, e.LdtkJson_Str(lv.obj, "identifier"), "level")
	UI_HeaderButtons(1)
	if UI_HeaderButton(ICON_FA_CIRCLE_QUESTION, "level.help.level", "") do LevelRef_Open("tab.level")
	level_tip("The Level tab in the reference", "tab.level")
	if UI_BeginProps("##level_props") {
		UI_PropLabel("Identifier")
		nameBuf: [128]u8
		copy(nameBuf[:len(nameBuf) - 1], e.LdtkJson_Str(lv.obj, "identifier"))
		autoId := e.LdtkJson_Bool(lv.obj, "useAutoIdentifier")
		imgui.BeginDisabled(autoId)
		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x - 70)
		nameEntered := imgui.InputText("##lvl_name", cstring(raw_data(nameBuf[:])), len(nameBuf), {.EnterReturnsTrue}) || imgui.IsItemDeactivatedAfterEdit()
		Drive_Item("level.name")
		imgui.EndDisabled()
		level_tip(autoId ? "Automatic: the project's level name pattern (Project tab) - untick Auto to name it yourself" : "The level's identifier (unique; Enter applies)", "tab.level")
		imgui.SameLine()
		if imgui.Checkbox("Auto##lvl_auto", &autoId) {
			e.Ldtk_Doc_Checkpoint(doc, -1, "Automatic Level Identifier")
			e.Ldtk_Doc_SetLevelAutoIdentifier(doc, L.level, autoId)
		}
		Drive_Item("level.autoid")
		level_tip("Name it from the project's level name pattern (%idx, %x, %gx, %depth...), renamed when levels move", "project.names")
		if nameEntered {
			name := string(cstring(raw_data(nameBuf[:])))
			if name != e.LdtkJson_Str(lv.obj, "identifier") {
				e.Ldtk_Doc_Checkpoint(doc, L.level, "Rename Level")
				if !e.Ldtk_Doc_RenameLevel(doc, L.level, e.Ldtk_Doc_CleanIdentifier(doc, name)) do Editor_Log(state, .Warn, "A level is already called %s", name)
			}
		}
		p := e.Ldtk_Doc_LevelPos(doc, L.level)
		s := e.Ldtk_Doc_LevelSize(doc, L.level)
		UI_PropLabel("Position")
		pos := [2]i32{i32(p.x), i32(p.y)}
		if imgui.DragInt2("##lvl_pos", &pos, 1, 0, 0, "%d") {
			e.Ldtk_Doc_CheckpointOnce(doc, level_move_scope(), "Move Level", lv.obj)
			e.Ldtk_Doc_MoveLevel(doc, L.level, {int(pos.x), int(pos.y)})
		}
		if imgui.IsItemDeactivated() {
			e.Ldtk_Doc_EndCoalesce(doc)
			e.Ldtk_Doc_ApplyAutoLevelIdentifiers(doc, L.world)
		}
		Drive_Item("level.pos")
		level_tip("Its place in the world, in pixels (drag or type; linear layouts place levels themselves)", "tab.level")
		UI_PropLabel("Size (px)")
		sizeEdit, entered := level_input_int2("##lvl_size", {i32(s.x), i32(s.y)})
		Drive_Item("level.size")
		level_tip("Width, height in pixels (applied when you leave the field; resized from the top-left - drag the handles around the level for the other sides)", "level.resize")
		if entered && sizeEdit.x > 0 && sizeEdit.y > 0 && (int(sizeEdit.x) != s.x || int(sizeEdit.y) != s.y) {
			e.Ldtk_Doc_Checkpoint(doc, L.level, "Resize Level")
			e.Ldtk_Doc_ResizeLevel(doc, L.level, {int(sizeEdit.x), int(sizeEdit.y)})
		}
		UI_PropLabel("Depth")
		depth := i32(e.LdtkJson_Int(lv.obj, "worldDepth"))
		if imgui.InputInt("##lvl_depth", &depth) {
			e.Ldtk_Doc_Checkpoint(doc, L.level, "Level Depth")
			e.Ldtk_Doc_SetLevelDepth(doc, L.level, int(depth))
		}
		level_tip("World depth: levels overlapping at another depth are drawn above / below (PageUp / PageDown)", "navigation")
		UI_PropLabel("Background")
		c := e.Ldtk_ParseHexColor(e.LdtkJson_Str(lv.obj, "__bgColor", "#696A79"))
		col := [3]f32{f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255}
		if imgui.ColorEdit3("##lvl_bg", &col, {.NoInputs}) {
			e.Ldtk_Doc_CheckpointOnce(doc, L.level, "Level Colour", &lv.obj)
			e.Ldtk_Doc_SetLevelBgColor(doc, L.level, e.Ldtk_ColorHex({u8(col[0] * 255 + 0.5), u8(col[1] * 255 + 0.5), u8(col[2] * 255 + 0.5), 255}))
		}
		level_tip("The level's background colour (default: the project's)", "tab.level")
		if !e.LdtkJson_IsNull(lv.obj, "bgColor") {
			imgui.SameLine()
			if UI_Button("Default", "level.bg.default") {
				e.Ldtk_Doc_Checkpoint(doc, L.level, "Level Colour")
				e.Ldtk_Doc_SetLevelBgColor(doc, L.level, "")
			}
			level_tip("Use the project's default background colour", "tab.level")
		}
		level_bg_image_props(state)
		UI_EndProps()
	}
	imgui.EndChild()
	imgui.SameLine(0, 16)
	if !imgui.BeginChild("##lvl_right", {0, avail.y}, {}, {}) {
		imgui.EndChild()
		return
	}
	defer imgui.EndChild()
	fields := e.LdtkJson_Arr(lv.obj, "fieldInstances")
	if len(fields) > 0 && UI_SectionHeader("Level fields") {
		LevelFields_Editor(state, fields, lv.extRoot != nil ? e.LdtkJson_Arr(lv.extRoot, "fieldInstances") : nil, nil, -1)
	}
	if UI_SectionHeader("Project", false) {
		UI_DimText(fmt.tprintf("%s", L.rel))
		UI_DimText(fmt.tprintf("%d levels, %d layer defs, %d entities, %d tilesets", len(doc.levels), len(doc.layerDefs), len(doc.entityDefs), len(doc.tilesets)))
		UI_DimText(fmt.tprintf("World layout: %s%s", e.Ldtk_Doc_WorldStr(doc, L.world, "worldLayout"), doc.external ? ", external level files" : ""))
		if UI_Button(fmt.tprintf("%s  Open in LDtk", ICON_FA_UP_RIGHT_FROM_SQUARE), "level.open_ldtk") do Editor_OpenExternally(state, level_abs(state, L.rel))
		level_tip("Open the file with the system's application for .ldtk files (LDtk); save first", "saving")
		imgui.SameLine()
		if UI_Button(fmt.tprintf("%s  Close", ICON_FA_FOLDER_OPEN), "level.close") do LevelEditor_Close(state)
		level_tip("Close the project (asks when there are unsaved changes)", "saving")
	}
}

// level_bg_image_props: the level's background image, its position and
// pivot (LevelInstanceForm's image picker).
@(private = "file")
level_bg_image_props :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	lv := &doc.levels[L.level]
	rel := e.LdtkJson_Str(lv.obj, "bgRelPath")
	UI_PropLabel("Image")
	images := Editor_ListProjectFiles(state, "", {".png", ".jpg", ".jpeg", ".bmp"})
	names := make([dynamic]string, context.temp_allocator)
	rels := make([dynamic]string, context.temp_allocator)
	append(&names, "None")
	append(&rels, "")
	cur := 0
	for img in images {
		r := level_doc_rel(state, img)
		if r == rel do cur = len(names)
		append(&names, img)
		append(&rels, r)
	}
	if rel != "" && cur == 0 {
		cur = len(names)
		append(&names, fmt.tprintf("%s (missing)", rel))
		append(&rels, rel)
	}
	if pick, ch := UI_Combo("level.bg.image", cur, names[:]); ch && rels[pick] != rel {
		e.Ldtk_Doc_Checkpoint(doc, L.level, "Level Background")
		e.Ldtk_Doc_SetLevelBg(doc, L.level, rels[pick])
	}
	level_tip("An image drawn behind the level's layers (a project image)", "level.bg")
	if rel == "" do return
	if tex := level_bg_texture(rel); tex.id == 0 {
		UI_PropLabel("")
		imgui.TextColored(UI_DANGER, "Can't read %s", fmt.ctprintf("%s", rel))
	}
	UI_PropLabel("Image position")
	pos, _ := e.Ldtk_BgPosOf(e.LdtkJson_Str(lv.obj, "bgPos", "Cover"))
	labels := make([]string, len(e.Ldtk_BgPos), context.temp_allocator)
	for l, p in e.LDTK_BG_POS_LABELS do labels[int(p)] = l
	if pick, ch := UI_Combo("level.bg.pos", int(pos), labels); ch {
		e.Ldtk_Doc_Checkpoint(doc, L.level, "Level Background")
		e.Ldtk_Doc_SetLevelBgPos(doc, L.level, e.Ldtk_BgPos(pick))
	}
	level_tip("How the image fills the level: as is, fitted inside, covering it (cropped), stretched, or repeated", "level.bg")
	UI_PropLabel("Image pivot")
	pv := [2]f64{e.LdtkJson_Float(lv.obj, "bgPivotX", 0.5), e.LdtkJson_Float(lv.obj, "bgPivotY", 0.5)}
	if p, ch := level_pivot_picker("level.bg.pivot", pv, "Which part of the image stays visible when it is cropped, and where it sits", "level.bg"); ch {
		e.Ldtk_Doc_Checkpoint(doc, L.level, "Level Background")
		e.Ldtk_Doc_SetLevelBgPivot(doc, L.level, p)
	}
	UI_PropLabel("")
	if UI_Button(fmt.tprintf("%s  Remove image", ICON_FA_TRASH), "level.bg.remove") {
		e.Ldtk_Doc_Checkpoint(doc, L.level, "Level Background")
		e.Ldtk_Doc_SetLevelBg(doc, L.level, "")
	}
	level_tip("No background image", "level.bg")
}

@(private = "file")
level_entity_inspector :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	ent := L.selEntity
	ed := e.Ldtk_Doc_EntityDef(doc, e.LdtkJson_Int(ent, "defUid", -1))
	avail := imgui.GetContentRegionAvail()
	if !imgui.BeginChild("##ent_left", {min(avail.x, 460), avail.y}, {}, {}) {
		imgui.EndChild()
		return
	}
	UI_PanelTitle(ICON_FA_CUBE, e.LdtkJson_Str(ent, "__identifier"), "entity")
	UI_HeaderButtons(2)
	if UI_HeaderButton(ICON_FA_CIRCLE_QUESTION, "level.help.entity", "") do LevelRef_Open("palette.entities")
	level_tip("Entities in the reference", "palette.entities")
	if UI_HeaderButton(ICON_FA_TRASH, "level.entity.remove", "Delete (Delete)") {
		e.Ldtk_Doc_Checkpoint(doc, L.level, "Delete Entity")
		e.Ldtk_Doc_RemoveEntity(doc, L.level, L.selEntityLayer, ent)
		level_clear_selection()
		imgui.EndChild()
		return
	}
	if UI_BeginProps("##entity_props") {
		px := e.LdtkJson_Arr(ent, "px")
		pos := [2]i32{}
		if len(px) >= 2 do pos = {i32(px[0].num), i32(px[1].num)}
		UI_PropLabel("Position")
		if imgui.DragInt2("##ent_pos", &pos, 1, 0, 0, "%d") {
			e.Ldtk_Doc_CheckpointOnce(doc, L.level, "Move Entity", ent)
			e.Ldtk_Doc_MoveEntity(doc, L.level, L.selEntityLayer, ent, {int(pos.x), int(pos.y)})
		}
		if imgui.IsItemDeactivated() do e.Ldtk_Doc_EndCoalesce(doc)
		level_tip("Its position in the level (pixels; the pivot point)", "palette.entities")
		UI_PropLabel("Size")
		size := [2]i32{i32(e.LdtkJson_Int(ent, "width", 16)), i32(e.LdtkJson_Int(ent, "height", 16))}
		resizable := ed != nil && (e.LdtkJson_Bool(ed.obj, "resizableX") || e.LdtkJson_Bool(ed.obj, "resizableY"))
		if !resizable do imgui.BeginDisabled(true)
		if (imgui.InputInt2("##ent_size", &size) || imgui.IsItemDeactivatedAfterEdit()) && size.x > 0 && size.y > 0 {
			e.Ldtk_Doc_Checkpoint(doc, L.level, "Resize Entity")
			r := e.Ldtk_Doc_EntityRect(ent)
			e.Ldtk_Doc_ResizeEntityAround(doc, L.level, L.selEntityLayer, ent, e.Ldtk_Doc_ConstrainEntitySize(doc, e.LdtkJson_Int(ent, "defUid", -1), {int(size.x), int(size.y)}, {r[2], r[3]}))
		}
		if !resizable do imgui.EndDisabled()
		level_tip(resizable ? "Width, height (Enter applies; the definition's limits apply)" : "Its definition isn't resizable (Entities tab)", "tab.entities")
		// another Entities layer of the level (LDtk: move entities between layers)
		UI_PropLabel("Layer")
		lv := &doc.levels[L.level]
		names := make([dynamic]string, context.temp_allocator)
		idx := make([dynamic]int, context.temp_allocator)
		cur := 0
		for &ly, j in lv.layers {
			ld := e.Ldtk_Doc_LayerDef(doc, &ly)
			if ld == nil || ld.type != .Entities do continue
			if j == L.selEntityLayer do cur = len(names)
			allowed := e.Ldtk_Doc_EntityLayerAllowed(doc, L.level, j, ent)
			append(&names, allowed ? ld.identifier : fmt.tprintf("%s (tags don't match)", ld.identifier))
			append(&idx, j)
		}
		if pick, changed := UI_Combo("level.entity.layer", cur, names[:]); changed {
			e.Ldtk_Doc_Checkpoint(doc, L.level, "Move Entity to Layer")
			if e.Ldtk_Doc_MoveEntityToLayer(doc, L.level, L.selEntityLayer, idx[pick], ent) do level_select_entity(idx[pick], ent)
		}
		level_tip("The Entities layer it is in: pick another to move it there (its position is kept). Layers that require other tags say so.", "tool.select")
		UI_PropLabel("Iid")
		UI_DimText(e.LdtkJson_Str(ent, "iid"))
		UI_EndProps()
	}
	imgui.EndChild()
	imgui.SameLine(0, 16)
	if imgui.BeginChild("##ent_right", {0, avail.y}, {}, {}) {
		fields := e.LdtkJson_Arr(ent, "fieldInstances")
		if len(fields) > 0 && UI_SectionHeader("Fields") do LevelFields_Editor(state, fields, nil, ent, L.selEntityLayer)
		else if len(fields) == 0 do UI_DimText("No fields (add some in the Entities tab).")
	}
	imgui.EndChild()
}

// ----------------------------------------------------------------------------
// Toolbar (Level tab)
// ----------------------------------------------------------------------------

// LevelEditor_Toolbar draws the level tools; `play` draws the shared play
// controls.
LevelEditor_Toolbar :: proc(state: ^EditorState, width: f32, play: proc(state: ^EditorState, width: f32)) {
	L := &GlobalLevel
	imgui.PushStyleColorImVec4(.Button, {0, 0, 0, 0})
	imgui.PushStyleColorImVec4(.ButtonHovered, UI_BG_HOVER)
	imgui.PushStyleVarImVec2(.FramePadding, {8, 6})
	imgui.PushFont(GlobalFonts.semibold)
	label := L.doc != nil ? fmt.tprintf("%s  %s%s", ICON_FA_MAP, filepath.base(L.rel), L.doc.modified ? "  " + ICON_FA_CIRCLE : "") : fmt.tprintf("%s  No level", ICON_FA_MAP)
	imgui.Button(fmt.ctprintf("%s##crumb_level", label))
	imgui.PopFont()
	Drive_Item("toolbar.level")
	UI_Tooltip(L.doc != nil ? L.rel : "Open or create an LDtk project")
	imgui.PopStyleVar()
	imgui.PopStyleColor(2)
	UI_VerticalDivider()
	for t in Level_Tool {
		info := LEVEL_TOOL_INFO[t]
		if UI_IconButton(info.icon, fmt.tprintf("level.tool.%v", t), "", L.tool == t) do L.tool = t
		level_tip(fmt.tprintf("%s (%s)\n%s", info.name, info.key, info.tip), info.topic)
		imgui.SameLine()
	}
	UI_VerticalDivider()
	canUndo := L.doc != nil && e.Ldtk_Doc_CanUndo(L.doc)
	canRedo := L.doc != nil && e.Ldtk_Doc_CanRedo(L.doc)
	if !canUndo do imgui.BeginDisabled(true)
	if UI_IconButton(ICON_FA_ROTATE_LEFT, "level.undo", "Undo (Cmd+Z)") do level_undo(state)
	level_tip("", "undo")
	if !canUndo do imgui.EndDisabled()
	imgui.SameLine()
	if !canRedo do imgui.BeginDisabled(true)
	if UI_IconButton(ICON_FA_ROTATE_RIGHT, "level.redo", "Redo (Cmd+Shift+Z)") do level_redo(state)
	if !canRedo do imgui.EndDisabled()
	play(state, width)
	rightW: f32 = 7 * 32 + 76 + 40
	imgui.SameLine()
	imgui.SetCursorPosX(max(imgui.GetCursorPosX() + UI_SPACE * 3, width - rightW - 10))
	if UI_IconButton(ICON_FA_BORDER_ALL, "level.grid", "Show the grid (G)", L.showGrid) do L.showGrid = !L.showGrid
	imgui.SameLine()
	if UI_IconButton(ICON_FA_EYE, "level.intgrid", "Show IntGrid values over auto tiles", L.showIntGrid) do L.showIntGrid = !L.showIntGrid
	imgui.SameLine()
	if UI_IconButton(ICON_FA_LAYER_GROUP, "level.singlelayer", "Single layer mode: fade the other layers (Shift+A)", L.singleLayer) do L.singleLayer = !L.singleLayer
	imgui.SameLine()
	if UI_IconButton(ICON_FA_WAND_MAGIC_SPARKLES, "level.autorender", "Draw auto-layer tiles (Alt+R; off: their IntGrid values show)", !L.hideAuto) do L.hideAuto = !L.hideAuto
	imgui.SameLine()
	if UI_IconButton(ICON_FA_TAG, "level.details", "Show level names, entity labels and field shapes (Shift+H)", !L.hideDetails) do L.hideDetails = !L.hideDetails
	level_tip("", "view")
	imgui.SameLine()
	if UI_IconButton(ICON_FA_EXPAND, "level.fit", "Fit the level (Home)") do L.fitRequest = true
	imgui.SameLine()
	imgui.SetNextItemWidth(76)
	imgui.PushStyleVarImVec2(.FramePadding, {6, 7})
	if imgui.BeginCombo("##level_zoom", fmt.ctprintf("%.0f%%", L.zoom * 100)) {
		for z in ([]f32{0.5, 1, 2, 3, 4}) {
			if imgui.Selectable(fmt.ctprintf("%.0f%%", z * 100), abs(L.zoom - z) < 0.001) do LevelCanvas_SetZoom(z)
			level_tip("Canvas zoom (the mouse wheel zooms too)", "canvas")
			Drive_Item(fmt.tprintf("pick:%.0f%%", z * 100))
		}
		imgui.EndCombo()
	}
	imgui.PopStyleVar()
	Drive_Item("level.zoom")
	imgui.SameLine()
	modified := L.doc != nil && L.doc.modified
	if UI_IconButton(ICON_FA_FLOPPY_DISK, "level.save", "Save the level file (Cmd+S)", tint = UI_WARNING if modified else {}) do LevelEditor_Save(state)
}

level_undo :: proc(state: ^EditorState) {
	L := &GlobalLevel
	LevelFields_CancelPick()
	if L.doc == nil || !e.Ldtk_Doc_Undo(L.doc) do return
	level_clear_selection()
	level_fix_indices()
}

level_redo :: proc(state: ^EditorState) {
	L := &GlobalLevel
	LevelFields_CancelPick()
	if L.doc == nil || !e.Ldtk_Doc_Redo(L.doc) do return
	level_clear_selection()
	level_fix_indices()
}

@(private = "file")
level_fix_indices :: proc() {
	L := &GlobalLevel
	L.level = clamp(L.level, 0, max(len(L.doc.levels) - 1, 0))
	if len(L.doc.levels) > 0 {
		L.world = L.doc.levels[L.level].world
		L.layer = clamp(L.layer, 0, max(len(L.doc.levels[L.level].layers) - 1, 0))
	}
	level_sync_palette()
}

// ----------------------------------------------------------------------------
// Shortcuts (Level tab)
// ----------------------------------------------------------------------------

// LevelEditor_Shortcuts handles the Level tab's keys; returns true when it
// took the key press (the global action table is skipped then).
LevelEditor_Shortcuts :: proc(state: ^EditorState) -> bool {
	L := &GlobalLevel
	io := imgui.GetIO()
	if imgui.IsPopupOpen("", imgui.PopupFlags_AnyPopup) do return false
	cmd := io.KeySuper || io.KeyCtrl
	if LevelEditor_Active() && imgui.IsKeyPressed(.F1, false) {
		LevelRef_Open(LevelRef_HelpTopic() != "" ? LevelRef_HelpTopic() : "overview")
		return true
	}
	if !LevelEditor_Active() || io.WantTextInput do return false
	if L.doc == nil do return false
	if cmd {
		switch {
		case imgui.IsKeyPressed(.S, false):
			LevelEditor_Save(state)
			return true
		case imgui.IsKeyPressed(.R, false):
			// LDtk's "run manual commands"
			LevelCommands_Run(state, "Manual")
			return true
		case imgui.IsKeyPressed(.K, false), imgui.IsKeyPressed(.F, false):
			LevelExtras_OpenPalette()
			return true
		case imgui.IsKeyPressed(.PageUp, false):
			level_move_depth(state, 1)
			return true
		case imgui.IsKeyPressed(.PageDown, false):
			level_move_depth(state, -1)
			return true
		case imgui.IsKeyPressed(.Z, true) && io.KeyShift, imgui.IsKeyPressed(.Y, true):
			level_redo(state)
			return true
		case imgui.IsKeyPressed(.Z, true):
			level_undo(state)
			return true
		case imgui.IsKeyPressed(.A, false):
			layer := io.KeyShift ? -1 : L.layer
			e.Ldtk_Doc_SelectAll(L.doc, L.level, &L.sel, layer, L.layer)
			level_sync_selection()
			return true
		case imgui.IsKeyPressed(.C, false), imgui.IsKeyPressed(.X, false):
			if !e.Ldtk_Selection_Empty(&L.sel) {
				e.Ldtk_Doc_CopySelection(L.doc, L.level, &L.sel, &L.clip)
				if imgui.IsKeyPressed(.X, false) {
					e.Ldtk_Doc_Checkpoint(L.doc, L.level, "Cut")
					e.Ldtk_Doc_DeleteSelection(L.doc, L.level, &L.sel)
					level_sync_selection()
				}
			}
			return true
		case imgui.IsKeyPressed(.V, false):
			if !e.Ldtk_Clipboard_Empty(&L.clip) {
				e.Ldtk_Doc_Checkpoint(L.doc, L.level, "Paste")
				e.Ldtk_Doc_Paste(L.doc, L.level, &L.clip, LevelCanvas_PasteAt(), &L.sel)
				level_sync_selection()
			}
			return true
		case imgui.IsKeyPressed(.D, false):
			if !e.Ldtk_Selection_Empty(&L.sel) {
				g := 16
				if _, d := level_active_layer(); d != nil do g = d.gridSize
				if e.Ldtk_Doc_SelectionCanMove(L.doc, L.level, &L.sel, {g, 0}) {
					e.Ldtk_Doc_Checkpoint(L.doc, L.level, "Duplicate")
					e.Ldtk_Doc_MoveSelection(L.doc, L.level, &L.sel, {g, 0}, true)
					level_sync_selection()
				}
			}
			return true
		}
		return false
	}
	if io.KeyAlt {
		switch {
		case imgui.IsKeyPressed(.R, false):
			L.hideAuto = !L.hideAuto
			return true
		case imgui.IsKeyPressed(.LeftArrow, false): return level_goto_neighbour(state, {-1, 0})
		case imgui.IsKeyPressed(.RightArrow, false): return level_goto_neighbour(state, {1, 0})
		case imgui.IsKeyPressed(.UpArrow, false): return level_goto_neighbour(state, {0, -1})
		case imgui.IsKeyPressed(.DownArrow, false): return level_goto_neighbour(state, {0, 1})
		}
	}
	if io.KeyShift {
		switch {
		case imgui.IsKeyPressed(.PageUp, false):
			level_move_depth(state, 1)
			return true
		case imgui.IsKeyPressed(.PageDown, false):
			level_move_depth(state, -1)
			return true
		case imgui.IsKeyPressed(.A, false):
			L.singleLayer = !L.singleLayer
			return true
		case imgui.IsKeyPressed(.E, false):
			L.selectEmpty = !L.selectEmpty
			return true
		case imgui.IsKeyPressed(.H, false):
			L.hideDetails = !L.hideDetails
			return true
		case imgui.IsKeyPressed(.W, false):
			level_fit_world()
			LevelEditor_ShowTab(.World)
			return true
		case imgui.IsKeyPressed(.R, false):
			L.tileRandom = !L.tileRandom
			return true
		case imgui.IsKeyPressed(.T, false):
			L.stacking = !L.stacking
			return true
		case imgui.IsKeyPressed(.S, false):
			if ly, _ := level_active_layer(); ly != nil {
				if ts := e.Ldtk_Doc_LayerTileset(L.doc, ly); ts != nil do palette_save_selection(ts.uid)
			}
			return true
		}
	}
	keys := [Level_Tool]imgui.Key{.Brush = .B, .Rect = .R, .Erase = .E, .Fill = .F, .Pick = .I, .Select = .V, .Move_Level = .M}
	for k, t in keys {
		if imgui.IsKeyPressed(k, false) {
			L.tool = t
			return true
		}
	}
	switch {
	case imgui.IsKeyPressed(.Tab, false):
		L.zen = !L.zen
		return true
	case imgui.IsKeyPressed(.PageUp, false):
		level_goto_depth(state, 1)
		return true
	case imgui.IsKeyPressed(.PageDown, false):
		level_goto_depth(state, -1)
		return true
	case imgui.IsKeyPressed(.P, false):
		LevelEditor_ShowTab(.Project)
		return true
	case imgui.IsKeyPressed(.L, false):
		LevelEditor_ShowTab(.Layers)
		return true
	case imgui.IsKeyPressed(.U, false):
		LevelEditor_ShowTab(.Enums)
		return true
	case imgui.IsKeyPressed(.T, false):
		LevelEditor_ShowTab(.Tilesets)
		return true
	case imgui.IsKeyPressed(.C, false):
		LevelEditor_ShowTab(.Level)
		return true
	case imgui.IsKeyPressed(.G, false):
		L.showGrid = !L.showGrid
		return true
	case imgui.IsKeyPressed(.X, false):
		L.flips ~= 1
		return true
	case imgui.IsKeyPressed(.Y, false):
		L.flips ~= 2
		return true
	case imgui.IsKeyPressed(.Home, false):
		L.fitRequest = true
		return true
	case imgui.IsKeyPressed(.Delete, false), imgui.IsKeyPressed(.Backspace, false):
		if !e.Ldtk_Selection_Empty(&L.sel) {
			e.Ldtk_Doc_Checkpoint(L.doc, L.level, "Delete")
			e.Ldtk_Doc_DeleteSelection(L.doc, L.level, &L.sel)
			level_sync_selection()
		}
		return true
	case imgui.IsKeyPressed(.Escape, false):
		if LevelFields_PickActive() do LevelFields_CancelPick()
		else do level_clear_selection()
		return true
	case !e.Ldtk_Selection_Empty(&L.sel) && (imgui.IsKeyPressed(.LeftArrow, true) || imgui.IsKeyPressed(.RightArrow, true) || imgui.IsKeyPressed(.UpArrow, true) || imgui.IsKeyPressed(.DownArrow, true)):
		// move the selection by one cell of the active layer
		g := 16
		if _, d := level_active_layer(); d != nil do g = d.gridSize
		dir := [2]int{}
		if imgui.IsKeyPressed(.LeftArrow, true) do dir.x = -1
		if imgui.IsKeyPressed(.RightArrow, true) do dir.x = 1
		if imgui.IsKeyPressed(.UpArrow, true) do dir.y = -1
		if imgui.IsKeyPressed(.DownArrow, true) do dir.y = 1
		if e.Ldtk_Doc_SelectionCanMove(L.doc, L.level, &L.sel, dir * g) {
			e.Ldtk_Doc_CheckpointOnce(L.doc, L.level, "Move Selection", &L.sel)
			e.Ldtk_Doc_MoveSelection(L.doc, L.level, &L.sel, dir * g)
			level_sync_selection()
		}
		return true
	}
	if _, d := level_active_layer(); d != nil && d.type == .IntGrid {
		digits := [9]imgui.Key{._1, ._2, ._3, ._4, ._5, ._6, ._7, ._8, ._9}
		for k, i in digits {
			if imgui.IsKeyPressed(k, false) && i < len(d.values) {
				L.intValue = d.values[i].value
				return true
			}
		}
	}
	return false
}

// ----------------------------------------------------------------------------
// Drive queries: level.<what>
// ----------------------------------------------------------------------------

LevelEditor_DriveQuery :: proc(state: ^EditorState, q: string) -> (string, bool) {
	L := &GlobalLevel
	doc := L.doc
	switch q {
	case "level.tab": return L.tab == .Level ? "level" : "game", true
	case "level.open": return L.rel, true
	case "level.tool": return fmt.tprintf("%v", L.tool), true
	case "level.paneltab": return fmt.tprintf("%v", L.panelTab), true
	case "level.tilemode": return L.tileRandom ? "Random" : "Stamp", true
	case "level.layer.override":
		ly, _ := level_active_layer()
		if ly == nil || e.LdtkJson_IsNull(ly.obj, "overrideTilesetUid") do return "", true
		ts := e.Ldtk_Doc_LayerTileset(doc, ly)
		return ts != nil ? ts.identifier : "?", true
	case "level.stacking": return L.stacking ? "true" : "false", true
	case "level.ref": return LevelRef_IsOpen() ? LevelRef_Selected() : "", true
	}
	if doc == nil do return "<no level>", true
	switch q {
	case "level.modified": return doc.modified ? "true" : "false", true
	case "level.level": return e.Ldtk_Doc_LevelName(doc, L.level), true
	case "level.levels": return fmt.tprint(len(doc.levels)), true
	case "level.undo": return fmt.tprint(len(doc.undo)), true
	case "level.value": return fmt.tprint(L.intValue), true
	case "level.tilesel":
		b := strings.builder_make(context.temp_allocator)
		for t, i in L.tileSel {
			if i > 0 do strings.write_byte(&b, ',')
			fmt.sbprintf(&b, "%d", t)
		}
		return strings.to_string(b), true
	case "level.zoom": return fmt.tprintf("%.2f", L.zoom), true
	case "level.layer":
		_, d := level_active_layer()
		return d != nil ? d.identifier : "", true
	case "level.autotiles":
		n := 0
		if len(doc.levels) > 0 do for &ly in doc.levels[L.level].layers do n += len(ly.autoTiles)
		return fmt.tprint(n), true
	case "level.gridtiles":
		ly, _ := level_active_layer()
		return ly != nil ? fmt.tprint(len(ly.gridTiles)) : "0", true
	case "level.entities":
		n := 0
		if len(doc.levels) > 0 do for &ly in doc.levels[L.level].layers do n += len(e.LdtkJson_Arr(ly.obj, "entityInstances"))
		return fmt.tprint(n), true
	case "level.selection":
		return fmt.tprintf("%d cells, %d entities", len(L.sel.cells), len(L.sel.entities)), true
	case "level.selected":
		return L.selEntity != nil ? e.LdtkJson_Str(L.selEntity, "__identifier") : "", true
	case "level.selected.size":
		if L.selEntity == nil do return "", true
		return fmt.tprintf("%d,%d", e.LdtkJson_Int(L.selEntity, "width"), e.LdtkJson_Int(L.selEntity, "height")), true
	case "level.selected.px":
		if L.selEntity == nil do return "", true
		px := e.LdtkJson_Arr(L.selEntity, "px")
		return len(px) >= 2 ? fmt.tprintf("%d,%d", int(px[0].num), int(px[1].num)) : "", true
	case "level.size":
		s := e.Ldtk_Doc_LevelSize(doc, L.level)
		return fmt.tprintf("%d,%d", s.x, s.y), true
	case "level.worlds":
		b := strings.builder_make(context.temp_allocator)
		for _, i in doc.worlds {
			if i > 0 do strings.write_byte(&b, ',')
			strings.write_string(&b, e.Ldtk_Doc_WorldName(doc, i))
		}
		return strings.to_string(b), true
	case "level.world": return e.Ldtk_Doc_WorldName(doc, L.world), true
	case "level.modes": return fmt.tprintf("single=%t auto=%t details=%t empty=%t zen=%t", L.singleLayer, !L.hideAuto, !L.hideDetails, L.selectEmpty, L.zen), true
	case "level.depth": return fmt.tprint(e.LdtkJson_Int(doc.levels[L.level].obj, "worldDepth")), true
	case "level.bg":
		// "<bgPos> <bgRelPath> topLeft=x,y scale=sx,sy" (empty: no image)
		lv := &doc.levels[L.level]
		rel := e.LdtkJson_Str(lv.obj, "bgRelPath")
		if rel == "" do return "", true
		bp := e.LdtkJson_Get(lv.obj, "__bgPos")
		if bp == nil || bp.kind != .Object do return fmt.tprintf("%s %s", e.LdtkJson_Str(lv.obj, "bgPos"), rel), true
		tl := e.LdtkJson_Arr(bp, "topLeftPx")
		sc := e.LdtkJson_Arr(bp, "scale")
		return fmt.tprintf("%s %s topLeft=%v,%v scale=%v,%v", e.LdtkJson_Str(lv.obj, "bgPos"), rel, tl[0].num, tl[1].num, sc[0].num, sc[1].num), true
	case "level.pos":
		p := e.Ldtk_Doc_LevelPos(doc, L.level)
		return fmt.tprintf("%d,%d", p.x, p.y), true
	case "level.layerdefs":
		b := strings.builder_make(context.temp_allocator)
		for d, i in doc.layerDefs {
			if i > 0 do strings.write_byte(&b, ',')
			strings.write_string(&b, d.identifier)
		}
		return strings.to_string(b), true
	case "level.rules":
		n := 0
		for d in doc.layerDefs do for g in d.groups do n += len(g.rules)
		return fmt.tprint(n), true
	}
	// level.fieldvalue:<name> -> the selected entity's (else the level's) field values
	if strings.has_prefix(q, "level.fieldvalue:") {
		name := q[len("level.fieldvalue:"):]
		fields := L.selEntity != nil ? e.LdtkJson_Arr(L.selEntity, "fieldInstances") : e.LdtkJson_Arr(doc.levels[L.level].obj, "fieldInstances")
		for fi in fields {
			if e.LdtkJson_Str(fi, "__identifier") != name do continue
			b := strings.builder_make(context.temp_allocator)
			fd := e.Ldtk_Doc_FieldDef(doc, e.LdtkJson_Int(fi, "defUid", -1))
			for i in 0 ..< e.Ldtk_Doc_FieldArrayLen(doc, fi) {
				t, isNull := e.Ldtk_Doc_FieldText(doc, fi, i)
				if isNull do continue
				if fd != nil && e.Ldtk_FieldKindOf(fd) == .EntityRef {
					if _, _, target, ok := e.Ldtk_Doc_FindEntity(doc, t); ok do t = e.LdtkJson_Str(target, "__identifier")
				}
				if strings.builder_len(b) > 0 do strings.write_byte(&b, ';')
				strings.write_string(&b, t)
			}
			return strings.to_string(b), true
		}
		return "<no field>", true
	}
	if q == "level.fielddef" {
		fd := e.Ldtk_Doc_FieldDef(doc, LevelDefs_SelectedField())
		return fd != nil ? fmt.tprintf("%s %s %s", e.LdtkJson_Str(fd, "identifier"), e.LdtkJson_Str(fd, "__type"), e.LdtkJson_Str(fd, "editorDisplayMode")) : "", true
	}
	if v, ok := LevelRules_Query(q); ok do return v, true
	// level.enum:<name> -> its values; level.external / level.levelfile
	if strings.has_prefix(q, "level.enum:") {
		name := q[len("level.enum:"):]
		defs := e.LdtkJson_Get(doc.root, "defs")
		for key in ([]string{"enums", "externalEnums"}) do for en in e.LdtkJson_Arr(defs, key) do if e.LdtkJson_Str(en, "identifier") == name {
			b := strings.builder_make(context.temp_allocator)
			for v, i in e.LdtkJson_Arr(en, "values") {
				if i > 0 do strings.write_byte(&b, ',')
				strings.write_string(&b, e.LdtkJson_Str(v, "id"))
			}
			return strings.to_string(b), true
		}
		return "<no enum>", true
	}
	if q == "level.external" do return doc.external ? "true" : "false", true
	// level.file:<path relative to the .ldtk> -> whether it exists
	if strings.has_prefix(q, "level.file:") {
		p, _ := filepath.join({doc.dir, q[len("level.file:"):]}, context.temp_allocator)
		return os.exists(p) ? "true" : "false", true
	}
	if q == "level.commandoutput" do return LevelCommands_Output(), true
	if q == "level.levelfile" do return e.LdtkJson_Str(doc.levels[L.level].obj, "externalRelPath"), true
	// level.tilesets -> identifiers; level.tilesetprop:<tileset>.<key> -> JSON
	if q == "level.tilesets" {
		b := strings.builder_make(context.temp_allocator)
		for &ts, i in doc.tilesets {
			if i > 0 do strings.write_byte(&b, ',')
			strings.write_string(&b, ts.identifier)
		}
		return strings.to_string(b), true
	}
	if strings.has_prefix(q, "level.tilesetprop:") {
		rest := q[len("level.tilesetprop:"):]
		dot := strings.index_byte(rest, '.')
		if dot < 0 do return "<need tileset.key>", true
		for &ts in doc.tilesets do if ts.identifier == rest[:dot] {
			v := e.LdtkJson_Get(ts.obj, rest[dot + 1:])
			return v != nil ? e.LdtkJson_ToString(v, .Minified, context.temp_allocator) : "<none>", true
		}
		return "<no tileset>", true
	}
	// level.layerprop:<layer>.<key> -> a layer definition's JSON value
	if strings.has_prefix(q, "level.layerprop:") {
		rest := q[len("level.layerprop:"):]
		dot := strings.index_byte(rest, '.')
		if dot < 0 do return "<need layer.key>", true
		for &d in doc.layerDefs do if d.identifier == rest[:dot] {
			v := e.LdtkJson_Get(d.obj, rest[dot + 1:])
			return v != nil ? e.LdtkJson_ToString(v, .Minified, context.temp_allocator) : "<none>", true
		}
		return "<no layer>", true
	}
	case_pick := q == "level.picking"
	if case_pick do return LevelFields_PickActive() ? "true" : "false", true
	// level.cell:cx,cy -> IntGrid value of the active layer
	// level.tile:cx,cy -> tile ids at the cell of the active layer
	if strings.has_prefix(q, "level.cell:") || strings.has_prefix(q, "level.tile:") {
		parts := strings.split(q[11:], ",", context.temp_allocator)
		if len(parts) != 2 do return "<need cx,cy>", true
		cx, _ := strconv.parse_int(strings.trim_space(parts[0]))
		cy, _ := strconv.parse_int(strings.trim_space(parts[1]))
		ly, _ := level_active_layer()
		if ly == nil do return "<no layer>", true
		if strings.has_prefix(q, "level.cell:") do return fmt.tprint(e.Ldtk_Doc_GetIntGrid(ly, cx, cy)), true
		b := strings.builder_make(context.temp_allocator)
		for t, i in e.Ldtk_Doc_TilesAt(ly, cx, cy) {
			if i > 0 do strings.write_byte(&b, ',')
			fmt.sbprintf(&b, "%d", t.t)
		}
		return strings.to_string(b), true
	}
	return "", false
}

// --- numbers applied when editing ends (#99) -----------------------------------------
// Fields don't need Enter: a value is applied when editing ends (Enter,
// Tab, a click elsewhere, a step button). These ones rebuild data (grid
// sizes remap tiles, the level size crops, the backup limit deletes
// backups), so they don't apply each keystroke on the way ("512" isn't
// 5, then 51): the typed value waits until the field is left.

@(private = "file")
levelPendingInt: struct {
	id: imgui.ID,
	v:  [2]i32,
}

// level_input_int: an int field applied when editing ends; returns the new
// value and whether it changed.
level_input_int :: proc(label: cstring, cur: i32, step: i32 = 0, stepFast: i32 = 0) -> (i32, bool) {
	id := imgui.GetID(label)
	v := levelPendingInt.v[0] if levelPendingInt.id == id else cur
	imgui.InputInt(label, &v, step, stepFast)
	return level_pending_end(id, {v, 0}, {cur, 0}).x, imgui.IsItemDeactivatedAfterEdit() && v != cur
}

// level_input_int2: the same for a pair.
level_input_int2 :: proc(label: cstring, cur: [2]i32) -> ([2]i32, bool) {
	id := imgui.GetID(label)
	v := levelPendingInt.v if levelPendingInt.id == id else cur
	imgui.InputInt2(label, &v)
	return level_pending_end(id, v, cur), imgui.IsItemDeactivatedAfterEdit() && v != cur
}

@(private = "file")
level_pending_end :: proc(id: imgui.ID, v, cur: [2]i32) -> [2]i32 {
	if imgui.IsItemActive() {
		levelPendingInt = {id, v}
		return cur
	}
	if levelPendingInt.id == id do levelPendingInt = {}
	return v if imgui.IsItemDeactivatedAfterEdit() else cur
}
