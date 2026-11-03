package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Assets panel: scenes, components, scripts, textures, audio and exported
// packages of the open project. Double-click opens a scene / instantiates a
// component; drag textures, components, audio or scripts into the viewport.
// Two views - by type, or the project's real folders (asset_folders.odin:
// create, rename, move by drag with references updated) - each as a list
// or a grid of thumbnails.
// ============================================================================

assetFilterBuf: [64]u8

Asset_View :: enum {
	Types,
	Folders,
}

assetView: Asset_View
assetGrid: bool

ASSET_PAYLOAD :: "RAYZR_ASSET"

// Asset_Payload is the drag & drop payload: a project-relative path.
Asset_Payload :: struct {
	path: [512]u8,
	len:  int,
}

Asset_Kind :: enum {
	Other,
	Scene,
	Component,
	Script,
	Texture,
	Audio,
	Level,   // LDtk project (.ldtk)
	Shader,  // fragment shader (.fs / .glsl / .frag)
	Package,
	Aseprite, // .aseprite / .ase (aseprite_editor.odin)
	Vector,   // .svg (vector_editor.odin)
	Resource, // .resource.json: data of a Lua resource class (engine/script_resources.odin)
	CustomNode, // .node.json: a custom node type (engine/custom_nodes.odin)
	Generator, // .levelgen.json: a procedural level generator (level_gen_editor.odin)
}

Asset_KindOf :: proc(path: string) -> Asset_Kind {
	lower := strings.to_lower(path, context.temp_allocator)
	switch {
	case strings.has_suffix(lower, ".scene.json"): return .Scene
	case strings.has_suffix(lower, ".component.json"): return .Component
	case strings.has_suffix(lower, e.CUSTOM_NODE_SUFFIX): return .CustomNode
	case strings.has_suffix(lower, e.RESOURCE_EXT): return .Resource
	case strings.has_suffix(lower, ".levelgen.json"): return .Generator
	case strings.has_suffix(lower, ".lua"): return .Script
	case strings.has_suffix(lower, ".ldtk"): return .Level
	case e.Is_PackagePath(lower): return .Package
	case strings.has_suffix(lower, ".aseprite"), strings.has_suffix(lower, ".ase"): return .Aseprite
	case strings.has_suffix(lower, ".svg"): return .Vector
	case strings.has_suffix(lower, ".fs"), strings.has_suffix(lower, ".glsl"), strings.has_suffix(lower, ".frag"): return .Shader
	}
	ext := filepath.ext(lower)
	switch {
	case slice.contains(TEXTURE_EXTS, ext): return .Texture
	case slice.contains(AUDIO_EXTS, ext): return .Audio
	}
	return .Other
}

kind_icon :: proc(k: Asset_Kind) -> (string, imgui.Vec4) {
	switch k {
	case .Scene: return ICON_FA_CLAPPERBOARD, UI_ACCENT
	case .Component: return ICON_FA_CUBES, {0.70, 0.52, 1.0, 1}
	case .Script: return ICON_FA_FILE_CODE, {0.40, 0.75, 1.0, 1}
	case .Texture: return ICON_FA_FILE_IMAGE, {0.95, 0.68, 0.35, 1}
	case .Audio: return ICON_FA_FILE_AUDIO, UI_SUCCESS
	case .Level: return ICON_FA_TABLE_CELLS, {0.35, 0.82, 0.86, 1}
	case .Shader: return ICON_FA_WAND_MAGIC_SPARKLES, {0.92, 0.55, 0.95, 1}
	case .Package: return ICON_FA_BOX_ARCHIVE, UI_TEXT_DIM
	case .Aseprite: return ICON_FA_PALETTE, {0.98, 0.55, 0.55, 1}
	case .Vector: return ICON_FA_PAINTBRUSH, {0.55, 0.85, 0.65, 1}
	case .Resource: return ICON_FA_GEM, {0.98, 0.80, 0.30, 1}
	case .CustomNode: return ICON_FA_PUZZLE_PIECE, {0.93, 0.47, 0.80, 1}
	case .Generator: return ICON_FA_SHUFFLE, {0.55, 0.80, 0.98, 1}
	case .Other: return ICON_FA_FILE, UI_TEXT_DIM
	}
	return ICON_FA_FILE, UI_TEXT_DIM
}

// The rows drawn this frame, in order (the arrow keys step through them),
// and one to scroll into view (#203).
@(private = "file")
assetRows: [dynamic]string
@(private = "file")
assetScrollTo: string

AssetBrowser_Render :: proc(state: ^EditorState) {
	defer imgui.End()
	assetsOpen := imgui.Begin("Assets###AssetBrowserWindow")
	Drive_Window("assets") // (annotated docs screenshots)
	PanelHelp_Mark("assets")
	Dock_Remember(.Left) // (plugin panels dock next to it: plugin_panels.odin)
	if !assetsOpen do return
	UI_PanelTitle(ICON_FA_FOLDER_OPEN, "Assets")
	// View toggles and "+" at the right: import (system file dialog) or create.
	UI_HeaderButtons(3)
	if UI_HeaderButton(ICON_FA_FOLDER_TREE, "asset.view-folders", "Folders view (else by type)", assetView == .Folders) {
		assetView = .Types if assetView == .Folders else .Folders
	}
	if UI_HeaderButton(ICON_FA_TABLE_CELLS, "asset.view-grid", "Thumbnail grid (else a list)", assetGrid) do assetGrid = !assetGrid
	if UI_HeaderButton(ICON_FA_PLUS, "asset.add", "Import assets or create new", imgui.IsPopupOpen("##asset_add")) do imgui.OpenPopup("##asset_add")
	if imgui.BeginPopup("##asset_add") {
		Asset_AddMenu(state)
		imgui.EndPopup()
	}
	assetPanelRect.min = imgui.GetWindowPos()
	assetPanelRect.max = assetPanelRect.min + imgui.GetWindowSize()
	assetPanelRect.frame = imgui.GetFrameCount()

	imgui.SetNextItemWidth(-1)
	imgui.InputTextWithHint("##AssetFilter", fmt.ctprintf("%s  Search assets", ICON_FA_MAGNIFYING_GLASS), cstring(raw_data(assetFilterBuf[:])), len(assetFilterBuf), {})
	Drive_Item("asset.search")
	filter := strings.to_lower(string(cstring(raw_data(assetFilterBuf[:]))), context.temp_allocator)

	imgui.PushStyleVarImVec2(.ItemSpacing, {6, 2})
	defer imgui.PopStyleVar()
	if imgui.BeginChild("##assets", {0, 0}, {}, {}) {
		assetRows = make([dynamic]string, context.temp_allocator)
		defer asset_arrow_keys(state)
		if imgui.IsWindowHovered() && imgui.IsMouseClicked(.Left) && !imgui.IsAnyItemHovered() {
			Editor_ClearAssetSelection(state)
		}
		io := imgui.GetIO()
		// (Not while typing in the Code tab: its text area doesn't set
		// WantTextInput, and Backspace there with the mouse over Assets
		// asked to delete the selected asset - issue #60.)
		if (imgui.IsWindowFocused() || imgui.IsWindowHovered()) && !io.WantTextInput && !Code_HasFocus() && (imgui.IsKeyPressed(.Delete) || imgui.IsKeyPressed(.Backspace)) {
			if Editor_AssetSelectedCount(state) > 1 {
				rels := make([dynamic]string, context.temp_allocator)
				for f in state.selectedAssetPaths {
					rel := strings.trim_prefix(strings.trim_prefix(f, state.projectPath), "/")
					append(&rels, rel)
				}
				Asset_BeginDeleteMulti(rels[:])
			} else if state.selectedAssetPath != "" {
				rel := strings.trim_prefix(strings.trim_prefix(state.selectedAssetPath, state.projectPath), "/")
				Asset_BeginDelete(rel)
			}
		}
		if assetView == .Folders {
			Asset_FoldersView(state, filter)
		} else {
		section_files(state, "Scenes", Editor_ListProjectFiles(state, "scenes", {".scene.json"}), filter)
		section_components(state, filter)
		section_custom_nodes(state, filter)
		section_files(state, "Scripts", Editor_ListProjectFiles(state, "scripts", {".lua"}), filter)
		section_files(state, "Resources", Editor_ListProjectFiles(state, "resources", {e.RESOURCE_EXT}), filter)
		section_files(state, "Textures", Editor_ListProjectFiles(state, "textures", TEXTURE_EXTS), filter)
		section_files(state, "Aseprite", Editor_ListProjectFiles(state, "", {".aseprite", ".ase"}), filter)
		section_files(state, "Vector Art", Editor_ListProjectFiles(state, "", {".svg"}), filter)
		section_files(state, "Audio", Editor_ListProjectFiles(state, "audio", AUDIO_EXTS), filter)
		section_files(state, "Levels", Editor_ListProjectFiles(state, "", {".ldtk"}), filter)
		section_files(state, "Level Generators", Editor_ListProjectFiles(state, "", {".levelgen.json"}), filter)
		section_files(state, "Shaders", Editor_ListProjectFiles(state, "", SHADER_EXTS), filter)
		section_packages(state, filter)
		}
		imgui.Dummy({0, 8})
		UI_DimText(fmt.tprintf("%s  Drop files or folders here to import", ICON_FA_FILE_IMPORT))
	}
	imgui.EndChild()
}

// Asset_DisplayName: how a file is shown - the file name without the
// ".scene.json" / ".component.json" every scene and component has
// (keepDir: keep the folders before it).
Asset_DisplayName :: proc(path: string, keepDir := false) -> string {
	name := path if keepDir else filepath.base(path)
	for suffix in ([]string{".scene.json", ".component.json", e.RESOURCE_EXT, e.CUSTOM_NODE_SUFFIX}) {
		if strings.has_suffix(name, suffix) do return name[:len(name) - len(suffix)]
	}
	return name
}

@(private = "file")
matches :: proc(path, filter: string) -> bool {
	return filter == "" || strings.contains(strings.to_lower(path, context.temp_allocator), filter)
}

@(private = "file")
section_files :: proc(state: ^EditorState, title: string, files: []string, filter: string) {
	n := 0
	for f in files do if matches(f, filter) do n += 1
	if filter != "" && n == 0 do return
	open := asset_folder_header(title, n, add_scene = title == "Scenes", add_script = title == "Scripts", add_resource = title == "Resources", state = state)
	if !open do return
	shown := make([dynamic]string, context.temp_allocator)
	for f in files do if matches(f, filter) do append(&shown, f)
	Asset_Items(state, shown[:])
}

// Asset_Items draws files as rows, or as a grid of tiles (assetGrid).
Asset_Items :: proc(state: ^EditorState, files: []string, labelBase := false) {
	if !assetGrid {
		for f in files do asset_row(state, f, filepath.base(f) if labelBase else "", files)
		return
	}
	TILE :: 76
	perRow := max(1, int((imgui.GetContentRegionAvail().x + 6) / (TILE + 6)))
	for f, i in files {
		if i % perRow != 0 do imgui.SameLine(0, 6)
		asset_tile(state, f, files)
	}
}

// asset_row draws one file row; returns true when double-clicked.
@(private = "file")
asset_row :: proc(state: ^EditorState, rel: string, label: string = "", files: []string = nil) -> bool {
	kind := Asset_KindOf(rel)
	icon, col := kind_icon(kind)
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	selected := Editor_AssetIsSelected(state, full)
	isActive := kind == .Scene && state.activeScenePath == rel

	name := label if label != "" else rel
	// Show paths below the category folder ("textures/exhaust/x.png" -> "exhaust/x.png").
	if label == "" {
		if i := strings.index_byte(rel, '/'); i >= 0 do name = rel[i + 1:]
	}
	name = Asset_DisplayName(name, keepDir = true)
	suffix := ""
	if kind == .Scene {
		if s := e.Game_FindSceneByFile(state.game, rel); s != nil && Editor_SceneIsModifiedCached(state, s) do suffix = "  " + ICON_FA_CIRCLE
	}
	if kind == .Script && Code_IsDirty(state, rel) do suffix = "  " + ICON_FA_CIRCLE
	global := Asset_GlobalName(state, rel) if kind == .Script else ""

	x0 := imgui.GetCursorPosX() // indented in the Folders view
	imgui.PushStyleColorImVec4(.Text, col)
	clicked := imgui.Selectable(fmt.ctprintf("%s##a_%s", icon, rel), selected || isActive, {.AllowDoubleClick}, {0, 24})
	imgui.PopStyleColor()
	dbl := asset_events(state, rel, kind, full, name, icon, clicked, files)
	imgui.SameLine(x0 + 32)
	imgui.PushStyleColorImVec4(.Text, UI_ACCENT if isActive else UI_TEXT)
	imgui.TextUnformatted(fmt.ctprintf("%s%s", name, suffix))
	imgui.PopStyleColor()
	if global != "" {
		// A global script (Project Settings > Globals): a globe and its name.
		imgui.SameLine(0, 8)
		imgui.PushStyleColorImVec4(.Text, UI_ACCENT)
		imgui.TextUnformatted(fmt.ctprintf("%s %s", ICON_FA_GLOBE, global))
		imgui.PopStyleColor()
		Drive_Item(fmt.tprintf("asset.global:%s", rel))
		UI_Tooltip(fmt.tprintf("Global script: every script can use %s (Project Settings > Globals)", global))
	}
	if kind == .Component {
		// How many instances the open documents use (#86).
		if n := Editor_ComponentInstanceCount(state, rel); n > 0 {
			imgui.SameLine(0, 8)
			imgui.PushStyleColorImVec4(.Text, UI_TEXT_FAINT)
			imgui.TextUnformatted(fmt.ctprintf("×%d", n))
			imgui.PopStyleColor()
			Drive_Item(fmt.tprintf("asset.instances:%s", rel))
			UI_Tooltip(fmt.tprintf("%d instance(s) in the open scenes (right-click: Select All Instances)", n))
		}
	}
	return dbl
}

// asset_arrow_keys: Up / Down (the grid: Left / Right too) select the
// next or previous asset shown (Shift: a range) - its preview follows
// (sounds and animations play with Autoplay on).
@(private = "file")
asset_arrow_keys :: proc(state: ^EditorState) {
	io := imgui.GetIO()
	if !imgui.IsWindowFocused({.RootWindow, .ChildWindows}) || io.WantTextInput || Code_HasFocus() || len(assetRows) == 0 do return
	d := 0
	if imgui.IsKeyPressed(.DownArrow) || (assetGrid && imgui.IsKeyPressed(.RightArrow)) do d = 1
	if imgui.IsKeyPressed(.UpArrow) || (assetGrid && imgui.IsKeyPressed(.LeftArrow)) do d = -1
	if d == 0 do return
	cur := -1
	for r, i in assetRows do if r == state.selectedAssetPath do cur = i
	next := clamp(cur + d, 0, len(assetRows) - 1) if cur >= 0 else (0 if d > 0 else len(assetRows) - 1)
	full := assetRows[next]
	if io.KeyShift do Editor_SelectAssetRange(state, full, assetRows[:])
	else do Editor_SelectAsset(state, full)
	delete(assetScrollTo)
	assetScrollTo = strings.clone(full)
}

// asset_events: what an asset row / tile does (call right after its item):
// select, double-click to open, context menu, drag (into the viewport or
// onto a folder), tooltip, import highlight.
@(private = "file")
asset_events :: proc(state: ^EditorState, rel: string, kind: Asset_Kind, full, name, icon: string, clicked: bool, files: []string = nil) -> bool {
	Drive_Item(fmt.tprintf("asset:%s", rel))
	append(&assetRows, full)
	if assetScrollTo != "" && assetScrollTo == full {
		if !imgui.IsItemVisible() do imgui.SetScrollHereY(0.5)
		delete(assetScrollTo)
		assetScrollTo = ""
	}
	rowMin, rowMax := imgui.GetItemRectMin(), imgui.GetItemRectMax()
	dbl := imgui.IsItemHovered() && imgui.IsMouseDoubleClicked(.Left)

	// If right-clicked on an unselected item, select it alone before context menu.
	// If right-clicked on an already-selected item, preserve multi-selection!
	if imgui.IsItemClicked(.Right) {
		if !Editor_AssetIsSelected(state, full) {
			Editor_SelectAsset(state, full)
		}
	}

	if imgui.BeginPopupContextItem(fmt.ctprintf("ctx_%s", rel)) {
		if Editor_AssetSelectedCount(state) > 1 && Editor_AssetIsSelected(state, full) {
			Asset_MultiContextMenu(state)
		} else {
			Asset_ContextMenu(state, rel)
		}
		imgui.EndPopup()
	}
	// Drag into the viewport, or onto a folder (Folders view).
	if kind != .Package && imgui.BeginDragDropSource({}) {
		p: Asset_Payload
		p.len = copy(p.path[:], rel)
		imgui.SetDragDropPayload(ASSET_PAYLOAD, &p, size_of(Asset_Payload))
		if Editor_AssetSelectedCount(state) > 1 && Editor_AssetIsSelected(state, full) {
			imgui.TextUnformatted(fmt.ctprintf("%s  %s (+%d more)", icon, name, Editor_AssetSelectedCount(state) - 1))
		} else {
			imgui.TextUnformatted(fmt.ctprintf("%s  %s", icon, name))
		}
		imgui.EndDragDropSource()
	}
	if clicked {
		io := imgui.GetIO()
		if io.KeyShift {
			Editor_SelectAssetRange(state, full, files)
		} else if io.KeyCtrl || io.KeySuper {
			Editor_ToggleAssetSelection(state, full)
		} else {
			Editor_SelectAsset(state, full)
		}
	}
	if Asset_IsHighlighted(rel) {
		imgui.DrawList_AddRectFilled(imgui.GetWindowDrawList(), rowMin, rowMax, col_u32(UI_ACCENT_SOFT), 4)
		if importHighlight.focus {
			imgui.SetScrollHereY(0.5)
			importHighlight.focus = false
		}
	}
	if dbl {
		#partial switch kind {
		case .Scene: Editor_OpenScene(state, rel)
		case .Component: Editor_InstantiateComponentFile(state, rel, state.cameraPos)
		case .CustomNode: Editor_AddCustomNode(state, rel, state.cameraPos)
		case .Script: Editor_OpenScript(state, rel)
		case .Level: Editor_AddLevel(state, rel, state.cameraPos)
		case .Shader: Editor_OpenScript(state, rel)
		case .Aseprite: Aseprite_Edit(state, full)
		case .Vector: Vector_EditExternal(state, full)
		case .Generator: LevelGenEditor_Open(state, rel)
		}
	}
	UI_Tooltip(asset_tooltip(kind, rel))
	return dbl
}

// asset_tile: one grid cell - a thumbnail (images) or a large icon, and
// the name.
@(private = "file")
asset_tile :: proc(state: ^EditorState, rel: string, files: []string = nil) {
	TILE :: 76
	kind := Asset_KindOf(rel)
	icon, col := kind_icon(kind)
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	selected := Editor_AssetIsSelected(state, full)
	isActive := kind == .Scene && state.activeScenePath == rel
	name := Asset_DisplayName(rel)
	clicked := imgui.Selectable(fmt.ctprintf("##t_%s", rel), selected || isActive, {.AllowDoubleClick}, {TILE, TILE + 18})
	mn, mx := imgui.GetItemRectMin(), imgui.GetItemRectMax()
	asset_events(state, rel, kind, full, name, icon, clicked, files)
	dl := imgui.GetWindowDrawList()
	box := [2]f32{TILE - 12, TILE - 12}
	origin := [2]f32{mn.x + 6, mn.y + 4}
	if tex := Asset_Thumbnail(full) if kind == .Texture || kind == .Aseprite || kind == .Vector else nil; tex != nil {
		s := min(box.x / f32(tex.width), box.y / f32(tex.height))
		size := [2]f32{f32(tex.width), f32(tex.height)} * s
		p0 := origin + (box - size) * 0.5
		imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)tex, p0, p0 + size)
	} else {
		fs: f32 = 30
		w := imgui.CalcTextSize(strings.clone_to_cstring(icon, context.temp_allocator)).x * fs / imgui.GetFontSize()
		imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.regular, fs, {origin.x + (box.x - w) * 0.5, origin.y + (box.y - fs) * 0.5}, col_u32(col), strings.clone_to_cstring(icon, context.temp_allocator))
	}
	clip := imgui.Vec4{mn.x + 2, mn.y, mx.x - 2, mx.y}
	label := strings.clone_to_cstring(name, context.temp_allocator)
	lw := imgui.CalcTextSize(label).x * 0.8
	imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, 12, {mn.x + max(2, (TILE - lw) * 0.5), mx.y - 16}, col_u32(UI_ACCENT if isActive else UI_TEXT), label, nil, 0, &clip)
	if kind == .Script && Asset_GlobalName(state, rel) != "" {
		imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.regular, 16, {mx.x - 20, mn.y + 4}, col_u32(UI_ACCENT), ICON_FA_GLOBE)
	}
}

// Asset_GlobalName: the Lua global a script is loaded as (Project Settings
// > Globals), "" if it isn't a global script.
Asset_GlobalName :: proc(state: ^EditorState, rel: string) -> string {
	return e.Globals_NameOf(state.projectConfig.globals[:], rel)
}

@(private = "file")
asset_tooltip :: proc(k: Asset_Kind, rel: string) -> string {
	#partial switch k {
	case .Scene: return fmt.tprintf("%s - double-click to open", rel)
	case .Component: return fmt.tprintf("%s - double-click or drag into the viewport to add", rel)
	case .Texture: return fmt.tprintf("%s - drag into the viewport to add a sprite", rel)
	case .Audio: return fmt.tprintf("%s - drag into the viewport to add a sound", rel)
	case .Script: return fmt.tprintf("%s - drag onto a node in the viewport to attach (or right-click > Make Global)", rel)
	case .Level: return fmt.tprintf("%s - LDtk project: double-click or drag into the viewport to add a level", rel)
	case .Aseprite: return fmt.tprintf("%s - Aseprite: drag into the viewport to add (its tags play); double-click to edit in Aseprite", rel)
	case .Vector: return fmt.tprintf("%s - vector art (SVG): drag into the viewport to add, or onto a Vector Shape to use it; double-click to edit it in your vector app", rel)
	case .Resource: return fmt.tprintf("%s - a resource: data of a Lua resource class; pick it in a script's resource property, or Resource.load it", rel)
	case .CustomNode: return fmt.tprintf("%s - a custom node type: double-click or drag into the viewport to add one", rel)
	case .Generator: return fmt.tprintf("%s - a procedural level generator: double-click to edit its graph; LevelGen.generate it into a TileMap", rel)
	}
	return rel
}

@(private = "file")
section_components :: proc(state: ^EditorState, filter: string) {
	files := Editor_ListProjectFiles(state, "components", {".component.json"})
	n := 0
	for f in files do if matches(f, filter) do n += 1
	if filter != "" && n == 0 do return
	if !asset_folder_header("Components", n, state = state) do return
	for f in files {
		if matches(f, filter) do asset_row(state, f, "", files)
	}
}

// section_custom_nodes: the project's custom node types (anywhere in it).
@(private = "file")
section_custom_nodes :: proc(state: ^EditorState, filter: string) {
	files := Editor_ListProjectFiles(state, "", {e.CUSTOM_NODE_SUFFIX})
	n := 0
	for f in files do if matches(f, filter) do n += 1
	if filter != "" && n == 0 do return
	if !asset_folder_header("Custom Nodes", n, add_custom_node = true, state = state) do return
	for f in files {
		if matches(f, filter) do asset_row(state, f, "", files)
	}
}

@(private = "file")
section_packages :: proc(state: ^EditorState, filter: string) {
	dir := filepath.dir(strings.trim_suffix(state.projectPath, "/"), context.temp_allocator)
	pkgs := make([dynamic]string, context.temp_allocator)
	for name in Editor_ParentPackages(state) do if matches(name, filter) do append(&pkgs, name)
	if len(pkgs) == 0 do return
	if !asset_folder_header("Packages", len(pkgs), default_open = false) do return
	for p in pkgs {
		icon, col := kind_icon(.Package)
		imgui.PushStyleColorImVec4(.Text, col)
		imgui.Selectable(fmt.ctprintf("%s##pkg_%s", icon, p), false, {}, {0, 24})
		imgui.PopStyleColor()
		Drive_Item(fmt.tprintf("asset:package:%s", p))
		if imgui.BeginPopupContextItem(fmt.ctprintf("ctx_pkg_%s", p)) {
			pkgPath, _ := filepath.join({dir, p}, context.temp_allocator)
			if imgui.MenuItem(fmt.ctprintf("%s  Run Game From Package", ICON_FA_PLAY), nil, false, !state.gameProcessRunning) do Editor_RunPackage(state, pkgPath)
			Drive_Item("ctx:run-package")
			if imgui.MenuItem(fmt.ctprintf("%s  Reveal in Finder", ICON_FA_FOLDER_OPEN)) do Editor_OpenExternally(state, dir)
			if imgui.MenuItem(fmt.ctprintf("%s  Copy Path", ICON_FA_LINK)) do imgui.SetClipboardText(strings.clone_to_cstring(pkgPath, context.temp_allocator))
			imgui.Separator()
			if imgui.MenuItem(fmt.ctprintf("%s  Delete Package", ICON_FA_TRASH)) {
				if os.remove(pkgPath) == nil do Editor_Log(state, .Info, "Deleted %s", p)
			}
			imgui.EndPopup()
		}
		UI_Tooltip("Exported game package. Run it with: rayzr --project <file>.rayzr")
		imgui.SameLine(32)
		imgui.TextUnformatted(strings.clone_to_cstring(p, context.temp_allocator))
	}
}

// AssetBrowser_HandleViewportDrop accepts an asset dropped on the viewport
// (call right after the viewport image item).
AssetBrowser_HandleViewportDrop :: proc(state: ^EditorState, worldPos: [2]f32) {
	if !imgui.BeginDragDropTarget() do return
	defer imgui.EndDragDropTarget()
	payload := imgui.AcceptDragDropPayload(ASSET_PAYLOAD)
	if payload == nil do return
	p := (^Asset_Payload)(payload.Data)
	rel := strings.clone(string(p.path[:p.len]), context.temp_allocator)
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	if Editor_AssetIsSelected(state, full) && Editor_AssetSelectedCount(state) > 1 {
		offset: [2]f32 = 0
		for f in state.selectedAssetPaths {
			r := strings.trim_prefix(strings.trim_prefix(f, state.projectPath), "/")
			Editor_DropAsset(state, r, worldPos + offset)
			offset += {16, 16}
		}
	} else {
		Editor_DropAsset(state, rel, worldPos)
	}
}

// Editor_DropAsset adds an asset to the scene at a world position.
Editor_DropAsset :: proc(state: ^EditorState, rel: string, worldPos: [2]f32) {
	switch Asset_KindOf(rel) {
	case .CustomNode:
		state.selectedNode = nil // (at the drop, under the scene's root)
		Editor_AddCustomNode(state, rel, worldPos)
	case .Aseprite:
		saved := state.cameraPos
		state.cameraPos = worldPos
		state.selectedNode = nil
		node := Editor_CreateNode(state, "AsepriteNode", filepath.stem(rel))
		state.cameraPos = saved
		if node != nil {
			an := cast(^e.AsepriteNode)node
			an.file = strings.clone(rel, an.allocator)
			// The first tag (if any) plays.
			if r := e.ResourceManager_LoadAseprite(&state.game.resourceManager, e.Project_ResolveAssetPath(&state.game.gameContext, rel)); r != nil {
				if len(r.doc.tags) > 0 do an.animation = strings.clone(r.doc.tags[0].name, an.allocator)
				e.ResourceManager_ReleaseAseprite(r)
			}
		}
	case .Vector:
		// Onto a Vector Shape: it draws this file; elsewhere: a new one.
		if target := Viewport_PickNode(state, worldPos); target != nil && target.typeId == e.VectorShapeNode {
			Editor_RecordUndo(state, "Vector file")
			v := cast(^e.VectorShapeNode)target
			v.file = strings.clone(rel, v.allocator)
			state.selectedNode = target
			return
		}
		saved := state.cameraPos
		state.cameraPos = worldPos
		state.selectedNode = nil
		node := Editor_CreateNode(state, "VectorShapeNode", filepath.stem(rel))
		state.cameraPos = saved
		if node != nil {
			v := cast(^e.VectorShapeNode)node
			v.file = strings.clone(rel, v.allocator)
			full := e.Project_ResolveAssetPath(&state.game.gameContext, rel)
			if imp := e.Asset_ImportGet(&state.game.resourceManager, full); imp.hasOrigin do v.pivot = imp.origin
		}
	case .Texture:
		saved := state.cameraPos
		state.cameraPos = worldPos
		state.selectedNode = nil
		node := Editor_CreateNode(state, "TextureNode", filepath.stem(rel))
		state.cameraPos = saved
		if node != nil do Editor_SetTexture(state, cast(^e.TextureNode)node, rel)
	case .Audio:
		saved := state.cameraPos
		state.cameraPos = worldPos
		state.selectedNode = nil
		node := Editor_CreateNode(state, "SoundNode", filepath.stem(rel))
		state.cameraPos = saved
		if node != nil {
			e.SoundNode_AddSound(cast(^e.SoundNode)node, &state.game.resourceManager, e.Project_ResolveAssetPath(&state.game.gameContext, rel))
		}
	case .Component:
		state.selectedNode = nil
		Editor_InstantiateComponentFile(state, rel, worldPos)
	case .Script:
		target := Viewport_PickNode(state, worldPos)
		if target == nil do target = state.selectedNode
		if target == nil {
			Editor_Log(state, .Warn, "Drop the script onto a node to attach it")
			return
		}
		Editor_RecordUndo(state, "Attach script")
		target.gameContext = &state.game.gameContext
		if e.Script_AttachToNode(target, rel, nil, &state.game.scriptManager) != nil {
			state.selectedNode = target
			Editor_Log(state, .Info, "Attached %s to %s", rel, target.name)
		}
	case .Level:
		Editor_AddLevel(state, rel, worldPos)
	case .Shader:
		// Onto a node: it gets this shader.
		target := Viewport_PickNode(state, worldPos)
		if target == nil do target = state.selectedNode
		if target == nil {
			Editor_Log(state, .Warn, "Drop the shader onto a node to apply it")
			return
		}
		Editor_RecordUndo(state, "Set shader")
		e.Material_SetShader(target, rel)
		state.selectedNode = target
		Editor_Log(state, .Info, "%s uses %s", target.name, rel)
	case .Resource:
		Editor_Log(state, .Info, "A resource goes in a script's resource property (or Resource.load in code), not the scene")
	case .Generator:
		LevelGenEditor_Open(state, rel) // (select a TileMap, then Apply)
	case .Scene, .Package, .Other:
	}
}

Editor_AssetIsSelected :: proc(state: ^EditorState, full: string) -> bool {
	if full == "" do return false
	if len(state.selectedAssetPaths) == 0 {
		return state.selectedAssetPath == full
	}
	for p in state.selectedAssetPaths {
		if p == full do return true
	}
	return false
}

Editor_AssetSelectedCount :: proc(state: ^EditorState) -> int {
	if len(state.selectedAssetPaths) > 0 {
		return len(state.selectedAssetPaths)
	}
	return 1 if state.selectedAssetPath != "" else 0
}

Editor_ClearAssetSelection :: proc(state: ^EditorState) {
	for p in state.selectedAssetPaths do delete(p)
	delete(state.selectedAssetPaths)
	state.selectedAssetPaths = nil
	delete(state.selectedAssetPath)
	state.selectedAssetPath = ""
	delete(state.assetAnchorPath)
	state.assetAnchorPath = ""
	PreviewPanel_OnAssetSelected(state, "")
}

// Editor_SelectAsset selects a file in the Assets panel (clearing multi-selection) and previews it.
Editor_SelectAsset :: proc(state: ^EditorState, full: string) {
	for p in state.selectedAssetPaths do delete(p)
	clear(&state.selectedAssetPaths)
	if full != "" {
		append(&state.selectedAssetPaths, strings.clone(full))
	}
	if state.selectedAssetPath != full {
		delete(state.selectedAssetPath)
		state.selectedAssetPath = strings.clone(full) if full != "" else ""
	}
	delete(state.assetAnchorPath)
	state.assetAnchorPath = strings.clone(full) if full != "" else ""
	PreviewPanel_OnAssetSelected(state, full)
	// A resource opens in the Inspector (until a node is selected).
	state.inspectResource = full != "" && Asset_KindOf(full) == .Resource
	state.inspectResourceNode = state.selectedNode
}

// Editor_ToggleAssetSelection toggles an individual asset (Control / Command click).
Editor_ToggleAssetSelection :: proc(state: ^EditorState, full: string) {
	if full == "" do return
	if len(state.selectedAssetPaths) == 0 && state.selectedAssetPath != "" {
		append(&state.selectedAssetPaths, strings.clone(state.selectedAssetPath))
	}

	foundIdx := -1
	for p, i in state.selectedAssetPaths {
		if p == full {
			foundIdx = i
			break
		}
	}

	if foundIdx >= 0 {
		delete(state.selectedAssetPaths[foundIdx])
		ordered_remove(&state.selectedAssetPaths, foundIdx)
		if state.selectedAssetPath == full {
			delete(state.selectedAssetPath)
			if len(state.selectedAssetPaths) > 0 {
				state.selectedAssetPath = strings.clone(state.selectedAssetPaths[len(state.selectedAssetPaths) - 1])
			} else {
				state.selectedAssetPath = ""
			}
			PreviewPanel_OnAssetSelected(state, state.selectedAssetPath)
		}
	} else {
		append(&state.selectedAssetPaths, strings.clone(full))
		delete(state.selectedAssetPath)
		state.selectedAssetPath = strings.clone(full)
		PreviewPanel_OnAssetSelected(state, full)
	}

	delete(state.assetAnchorPath)
	state.assetAnchorPath = strings.clone(full)
}

// Editor_SelectAssetRange selects a continuous range between the anchor and clicked item (Shift click).
Editor_SelectAssetRange :: proc(state: ^EditorState, clickedFull: string, files: []string) {
	if clickedFull == "" do return
	if len(files) == 0 {
		Editor_SelectAsset(state, clickedFull)
		return
	}

	clickedIdx := -1
	anchorIdx := -1
	for f, i in files {
		fFull, _ := filepath.join({state.projectPath, f}, context.temp_allocator)
		if fFull == clickedFull do clickedIdx = i
		if state.assetAnchorPath != "" && fFull == state.assetAnchorPath do anchorIdx = i
	}

	if clickedIdx == -1 {
		Editor_SelectAsset(state, clickedFull)
		return
	}

	if anchorIdx == -1 {
		anchorIdx = clickedIdx
	}

	savedAnchor := strings.clone(state.assetAnchorPath, context.temp_allocator) if state.assetAnchorPath != "" else strings.clone(clickedFull, context.temp_allocator)

	for p in state.selectedAssetPaths do delete(p)
	clear(&state.selectedAssetPaths)

	low := min(anchorIdx, clickedIdx)
	high := max(anchorIdx, clickedIdx)

	for i in low..=high {
		fFull, _ := filepath.join({state.projectPath, files[i]}, context.temp_allocator)
		append(&state.selectedAssetPaths, strings.clone(fFull))
	}

	delete(state.selectedAssetPath)
	state.selectedAssetPath = strings.clone(clickedFull)

	delete(state.assetAnchorPath)
	state.assetAnchorPath = strings.clone(savedAnchor)

	PreviewPanel_OnAssetSelected(state, clickedFull)
}

// Kept for callers of the previous API.
AssetBrowser_LoadSceneFile :: proc(state: ^EditorState, fullPath, relPath: string) {
	Editor_OpenScene(state, relPath)
}

// Open/closed state of the asset folders (default: open).
assetFolderClosed: map[string]bool

// asset_folder_header draws a folder row: open-folder icon when expanded,
// closed folder when collapsed (no tree arrow). Click toggles. The Scenes
// folder gets a "+" (new scene) button at its right edge.
@(private = "file")
asset_folder_header :: proc(title: string, count: int, default_open := true, add_scene := false, add_script := false, add_resource := false, add_custom_node := false, state: ^EditorState = nil) -> bool {
	if title not_in assetFolderClosed do assetFolderClosed[strings.clone(title)] = !default_open
	open := !assetFolderClosed[title]

	imgui.Dummy({0, 2})
	imgui.SetNextItemAllowOverlap() // the + button sits on the row
	if imgui.Selectable(fmt.ctprintf("##folder_%s", title), false, {}, {0, 26}) {
		assetFolderClosed[title] = open
		open = !open
	}
	Drive_Item(fmt.tprintf("section:%s", title))
	if state != nil && imgui.BeginPopupContextItem(fmt.ctprintf("ctx_folder_%s", title)) {
		Asset_FolderContextMenu(state, title)
		imgui.EndPopup()
	}
	rowMin := imgui.GetItemRectMin()
	rowMax := imgui.GetItemRectMax()

	// Icon + caption drawn over the selectable.
	imgui.SetCursorScreenPos({rowMin.x + 2, rowMin.y + 4})
	imgui.PushStyleColorImVec4(.Text, UI_WARNING)
	imgui.TextUnformatted(ICON_FA_FOLDER_OPEN if open else ICON_FA_FOLDER)
	imgui.PopStyleColor()
	imgui.SameLine(0, 8)
	imgui.PushFont(GlobalFonts.semibold)
	imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
	imgui.TextUnformatted(strings.clone_to_cstring(strings.to_upper(title, context.temp_allocator), context.temp_allocator))
	imgui.PopStyleColor()
	imgui.PopFont()
	imgui.SameLine(0, 6)
	UI_DimText(fmt.tprint(count))

	if add_scene && state != nil {
		imgui.SetCursorScreenPos({rowMax.x - 26, rowMin.y})
		if UI_IconButton(ICON_FA_PLUS, "asset.new-scene", "New scene (Ctrl+N)", size = 26) do Toolbar_NewScene(state)
	}
	if add_script && state != nil {
		imgui.SetCursorScreenPos({rowMax.x - 26, rowMin.y})
		if UI_IconButton(ICON_FA_PLUS, "asset.new-script", "New Lua script (from a template)", size = 26) do NewScriptDialog_Open(state)
	}
	if add_resource && state != nil {
		imgui.SetCursorScreenPos({rowMax.x - 26, rowMin.y})
		if UI_IconButton(ICON_FA_PLUS, "asset.new-resource", "New resource (data of a resource class)", size = 26) do NewResourceDialog_Open(state)
	}
	if add_custom_node && state != nil {
		imgui.SetCursorScreenPos({rowMax.x - 26, rowMin.y})
		if UI_IconButton(ICON_FA_PLUS, "asset.new-custom-node", "New custom node type (a base type, a script and default values)", size = 26) do CustomNodeDialog_Open(state)
	}
	imgui.SetCursorScreenPos({rowMin.x, rowMax.y + 2})
	imgui.Dummy({0, 0})
	return open
}
