package editor

import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// LDtk tab (bottom panel): everything about the LDtk level of the selected
// LdtkLevelNode (or the scene's only one).
//
//   Header      world and level pickers, World mode (every level of the
//               world at its world position), parallax preview around the
//               editor camera, IntGrid overlay, fit, reload, open in LDtk.
//   Layers      every layer, read-only: show/hide (editor view only), solo,
//               hover to outline it in the viewport; IntGrid value legend.
//   Entities    entity definitions: what each spawns as (Auto / component /
//               plain Node / nothing), "Create Component" from the entity's
//               fields, which fields reach script properties, and the
//               placed instances (click to frame one).
//   Collision   per IntGrid layer and value: None / Solid / One-way /
//               Trigger, friction and restitution, collision layers and
//               mask (the level's default, or the value's own - #405).
//   Links       EntityRef fields: rules (connect a signal to a method,
//               parent target or source) and the references in the level.
//   Level Fields, Enums, World (mini-map: click a level to open/frame it).
//
// LDtk owns the level data: it is shown here, edited in LDtk (saving there
// reloads the viewport).
// ============================================================================

@(private = "file")
LDTK_PAGES := []string{"Layers", "Entities", "Collision", "Links", "Level Fields", "Enums", "World"}

@(private = "file")
Ldtk_Panel :: struct {
	page:       int,
	node:       ^e.LdtkLevelNode,
	selEntity:  string,
	selLayer:   string,
	focusIid:   string,
	focusUntil: time.Time,
	showIntGrid: bool,
	noParallax: bool, // parallax preview off
}

@(private = "file")
lp: Ldtk_Panel

ldtkTabRequest := false // select the LDtk tab next frame

// LdtkPanel_Target: the level node the tab shows (selection, its LDtk
// ancestor, the last shown, else the scene's first).
LdtkPanel_Target :: proc(state: ^EditorState) -> ^e.LdtkLevelNode {
	scene := state.activeScene
	if scene == nil || scene.manager == nil do return nil
	for n := state.selectedNode; n != nil; n = e.GetParent(scene.manager, n) {
		if n.typeId == e.LdtkLevelNode do return cast(^e.LdtkLevelNode)n
	}
	if lp.node != nil && e.Node_IsAlive(lp.node) && e.GetParent(scene.manager, lp.node) != nil do return lp.node
	for n in scene.manager.nodes do if n != nil && n.typeId == e.LdtkLevelNode do return cast(^e.LdtkLevelNode)n
	return nil
}

// Ldtk_EditorSync sets the editor-view state of every level node before
// the viewport draws (layer overrides, parallax around the editor camera).
Ldtk_EditorSync :: proc(state: ^EditorState) {
	if state.activeScene == nil || state.activeScene.manager == nil do return
	target := LdtkPanel_Target(state)
	for n in state.activeScene.manager.nodes {
		if n == nil || n.typeId != e.LdtkLevelNode do continue
		ln := cast(^e.LdtkLevelNode)n
		ln.editorPreview = true
		ln.editorCamera = state.cameraPos
		ln.editorParallax = !lp.noParallax
		ln.editorShowIntGrid = lp.showIntGrid
		if ln != target {
			ln.editorHighlight = ""
			ln.editorSoloLayer = ""
		}
	}
}

// hint: a faint line of help that wraps to the panel width.
@(private = "file")
hint :: proc(text: string) {
	imgui.PushStyleColorImVec4(.Text, UI_TEXT_FAINT)
	imgui.TextWrapped(strings.clone_to_cstring(text, context.temp_allocator))
	imgui.PopStyleColor()
}

@(private = "file")
v4 :: proc(c: rl.Color) -> imgui.Vec4 {
	return {f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, f32(c.a) / 255}
}

@(private = "file")
swatch :: proc(id: string, col: rl.Color, size: f32 = 14) {
	imgui.ColorButton(fmt.ctprintf("##sw_%s", id), v4(col), {.NoTooltip, .NoDragDrop}, {size, size})
}

// tile_image draws a tileset sub-rectangle (if the tileset is loaded).
@(private = "file")
tile_image :: proc(proj: ^e.LdtkProject, t: e.LdtkTileRect, size: f32) -> bool {
	if !t.has do return false
	ts := e.Ldtk_GetTilesetByUid(proj, t.tilesetUid)
	if ts == nil || !ts.textureLoaded || ts.texture.width == 0 do return false
	tw, th := f32(ts.texture.width), f32(ts.texture.height)
	uv0 := imgui.Vec2{t.rect.x / tw, t.rect.y / th}
	uv1 := imgui.Vec2{(t.rect.x + t.rect.width) / tw, (t.rect.y + t.rect.height) / th}
	imgui.Image(transmute(imgui.TextureID)&ts.texture, {size, size}, uv0, uv1, {1, 1, 1, 1}, {0, 0, 0, 0})
	return true
}

// enum_chip: an enum value in its LDtk colour.
@(private = "file")
enum_chip :: proc(proj: ^e.LdtkProject, enumName, id: string) {
	val, _ := e.Ldtk_GetEnumValue(proj, enumName, id)
	col := rl.Color{160, 160, 170, 255}
	if val != nil do col = val.color
	if val != nil && tile_image(proj, val.tile, 14) do imgui.SameLine(0, 4)
	else {
		swatch(fmt.tprintf("chip_%s_%s", enumName, id), col, 10)
		imgui.SameLine(0, 4)
	}
	imgui.TextUnformatted(strings.clone_to_cstring(id, context.temp_allocator))
}

@(private = "file")
field_value_cell :: proc(proj: ^e.LdtkProject, f: ^e.LdtkFieldInstance) {
	if !f.isNull && f.enumName != "" && !f.isArray {
		enum_chip(proj, f.enumName, f.valueString)
		return
	}
	if !f.isNull && strings.has_prefix(f.typeName, "Color") {
		swatch(fmt.tprintf("fc_%p", f), f.valueColor, 12)
		imgui.SameLine(0, 4)
	}
	text := e.Ldtk_FieldValueText(f)
	if f.isNull do UI_DimText(text)
	else do imgui.TextUnformatted(strings.clone_to_cstring(text, context.temp_allocator))
}

LdtkPanel_Render :: proc(state: ^EditorState) {
	ln := LdtkPanel_Target(state)
	lp.node = ln
	if ln == nil {
		imgui.Dummy({0, 8})
		UI_DimText("   No LDtk level in this scene.")
		imgui.Dummy({0, 4})
		imgui.Indent(12)
		levels := Editor_ListProjectFiles(state, "", {".ldtk"})
		if len(levels) == 0 {
			UI_DimText("Import an LDtk project (.ldtk) to get started.")
		} else {
			UI_DimText("Add one of the project's levels:")
			for rel in levels {
				if UI_Button(fmt.tprintf("%s  %s", ICON_FA_TABLE_CELLS, rel), fmt.tprintf("ldtk.add:%s", rel)) do Editor_AddLevel(state, rel, state.cameraPos)
				imgui.SameLine()
			}
			imgui.NewLine()
		}
		if UI_Button(fmt.tprintf("%s  Import LDtk Project...", ICON_FA_FILE_IMPORT), "ldtk.import") do Asset_OpenImportDialog(state, {"ldtk"}, "Import LDtk Project")
		imgui.Unindent(12)
		return
	}
	header(state, ln)
	if ln.project == nil {
		imgui.Dummy({0, 6})
		UI_DimText(fmt.tprintf("   %s", "Pick an LDtk project for this node in the Inspector." if ln.projectPath == "" else fmt.tprintf("Could not load %s", ln.projectPath)))
		return
	}

	// Pages: a narrow nav on the left, the page on the right.
	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##ldtk_nav", {132, avail.y}, {}, {}) {
		for name, i in LDTK_PAGES {
			if imgui.Selectable(fmt.ctprintf("%s##ldtknav%d", name, i), lp.page == i, {}, {0, 24}) do lp.page = i
			Drive_Item(fmt.tprintf("ldtk.page:%s", name))
		}
	}
	imgui.EndChild()
	imgui.SameLine(0, 8)
	if imgui.BeginChild("##ldtk_page", {0, avail.y}, {}, {}) {
		switch lp.page {
		case 0: page_layers(state, ln)
		case 1: page_entities(state, ln)
		case 2: page_collision(state, ln)
		case 3: page_links(state, ln)
		case 4: page_level_fields(state, ln)
		case 5: page_enums(state, ln)
		case 6: page_world(state, ln)
		}
	}
	imgui.EndChild()
}

// --- header --------------------------------------------------------------------------

@(private = "file")
header :: proc(state: ^EditorState, ln: ^e.LdtkLevelNode) {
	imgui.Dummy({0, 1})
	imgui.AlignTextToFramePadding()
	imgui.PushFont(GlobalFonts.semibold)
	imgui.TextUnformatted(fmt.ctprintf("%s  %s", ICON_FA_TABLE_CELLS, ln.name))
	imgui.PopFont()
	imgui.SameLine(0, 6)
	UI_DimText(asset_rel_editor(state, ln.projectPath))
	proj := ln.project
	if proj == nil do return

	if len(proj.worlds) > 1 {
		imgui.SameLine(0, UI_SPACE)
		imgui.SetNextItemWidth(130)
		if imgui.BeginCombo("##ldtkworld", fmt.ctprintf("%s  %s", ICON_FA_FOLDER, ln.worldIdentifier)) {
			for &w in proj.worlds {
				if imgui.Selectable(strings.clone_to_cstring(w.identifier, context.temp_allocator), w.identifier == ln.worldIdentifier) {
					Editor_RecordUndo(state, "Set LDtk world")
					e.LdtkLevelNode_SetWorld(ln, w.identifier)
				}
				Drive_Item(fmt.tprintf("pick:%s", w.identifier))
			}
			imgui.EndCombo()
		}
		Drive_Item("ldtk.world")
	}
	imgui.SameLine(0, 6)
	imgui.SetNextItemWidth(150)
	cur := ln.level.identifier if ln.level != nil else ""
	if imgui.BeginCombo("##ldtklevelpick", strings.clone_to_cstring(cur, context.temp_allocator)) {
		if w := e.Ldtk_WorldOf(proj, ln.level); w != nil {
			for i in w.levels {
				lvl := &proj.levels[i]
				if imgui.Selectable(strings.clone_to_cstring(lvl.identifier, context.temp_allocator), lvl == ln.level) {
					Editor_RecordUndo(state, "Set LDtk level")
					e.LdtkLevelNode_SetLevel(ln, lvl)
				}
				Drive_Item(fmt.tprintf("pick:%s", lvl.identifier))
			}
		}
		imgui.EndCombo()
	}
	Drive_Item("ldtk.level")
	imgui.SameLine(0, UI_SPACE)
	if UI_IconButton(ICON_FA_TABLE_CELLS_LARGE, "ldtk.world-mode", "World mode: show and build every level of the world at its world position" if !ln.worldMode else "World mode on: every level of the world (click for just this level)", ln.worldMode, 26) {
		Editor_RecordUndo(state, "LDtk world mode")
		e.LdtkLevelNode_SetWorldMode(ln, !ln.worldMode)
	}
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_LAYER_GROUP, "ldtk.parallax", "Parallax preview: layers move with the editor camera like in the game", !lp.noParallax, 26) do lp.noParallax = !lp.noParallax
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_BORDER_ALL, "ldtk.intgrid", "Show IntGrid values in their LDtk colours", lp.showIntGrid, 26) do lp.showIntGrid = !lp.showIntGrid
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_EXPAND, "ldtk.fit", "Fit the level in the viewport", size = 26) do Ldtk_FitLevel(state, ln, nil)
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_ROTATE_RIGHT, "ldtk.reload", "Reload the .ldtk file", size = 26) {
		path := strings.clone(ln.projectPath, context.temp_allocator)
		e.LdtkLevelNode_SetProject(ln, path, strings.clone(ln.levelIdentifier, context.temp_allocator))
		Editor_Log(state, .Info, "Reloaded %s", asset_rel_editor(state, path))
	}
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_MAP, "ldtk.edit", "Edit in the Level tab", size = 26) do LevelEditor_OpenAt(state, asset_rel_editor(state, ln.projectPath), ln.levelIdentifier)
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_UP_RIGHT_FROM_SQUARE, "ldtk.open", "Open in LDtk", size = 26) do Editor_OpenExternally(state, ln.projectPath)
	if ln.level != nil {
		imgui.SameLine(0, UI_SPACE)
		UI_DimText(fmt.tprintf("%d x %d px%s", ln.level.pxWid, ln.level.pxHei, fmt.tprintf(" · %d levels", len(ln.activeLevels)) if ln.worldMode else ""))
	}
	imgui.Separator()
}

// Ldtk_FitLevel frames a level (nil: the active levels) in the viewport.
Ldtk_FitLevel :: proc(state: ^EditorState, ln: ^e.LdtkLevelNode, only: ^e.LdtkLevel) {
	mn, mx: [2]f32
	have := false
	for lvl in ln.activeLevels {
		if only != nil && lvl != only do continue
		o := ln.globalPosition + e.LdtkLevelNode_LevelOffset(ln, lvl) * ln.globalScale
		p1 := o + [2]f32{f32(lvl.pxWid), f32(lvl.pxHei)} * ln.globalScale
		if !have do mn, mx, have = o, p1, true
		mn = {min(mn.x, o.x), min(mn.y, o.y)}
		mx = {max(mx.x, p1.x), max(mx.y, p1.y)}
	}
	if have do Viewport_FitRect(state, mn, mx)
}

// --- Layers --------------------------------------------------------------------------

@(private = "file")
layer_icon :: proc(t: e.LdtkLayerType) -> string {
	switch t {
	case .IntGrid:   return ICON_FA_BORDER_ALL
	case .Entities:  return ICON_FA_CUBES
	case .Tiles:     return ICON_FA_TABLE_CELLS
	case .AutoLayer: return ICON_FA_WAND_MAGIC_SPARKLES
	}
	return ICON_FA_LAYER_GROUP
}

@(private = "file")
page_layers :: proc(state: ^EditorState, ln: ^e.LdtkLevelNode) {
	lvl := ln.level
	if lvl == nil do return
	hovered := ""
	hint("Layers as in LDtk (top first). The eye hides a layer in the editor only; the game uses LDtk's visibility.")
	if len(ln.layerVisibility) > 0 || ln.editorSoloLayer != "" {
		if UI_Button(fmt.tprintf("%s  Reset to LDtk", ICON_FA_ROTATE_LEFT), "ldtk.layers.reset") {
			Editor_RecordUndo(state, "Reset layer visibility")
			clear(&ln.layerVisibility)
			ln.editorSoloLayer = ""
		}
	}
	flags := imgui.TableFlags_RowBg | imgui.TableFlags_BordersInnerH | imgui.TableFlags_SizingStretchProp
	if imgui.BeginTable("##ldtk_layers", 8, flags) {
		imgui.TableSetupColumn("", {.WidthFixed}, 52)
		imgui.TableSetupColumn("Layer", {}, 0.24)
		imgui.TableSetupColumn("Type", {}, 0.12)
		imgui.TableSetupColumn("Grid", {}, 0.07)
		imgui.TableSetupColumn("Size", {}, 0.09)
		imgui.TableSetupColumn("Parallax", {}, 0.13)
		imgui.TableSetupColumn("Opacity", {}, 0.09)
		imgui.TableSetupColumn("Content", {}, 0.26)
		imgui.TableHeadersRow()
		for &layer in lvl.layers {
			imgui.PushIDPtr(&layer)
			imgui.TableNextRow()
			imgui.TableNextColumn()
			vis := e.LdtkLevelNode_LayerVisible(ln, &layer)
			solo := ln.editorSoloLayer == layer.identifier
			if UI_IconButton(ICON_FA_EYE if vis else ICON_FA_EYE_SLASH, fmt.tprintf("ldtk.layer.eye:%s", layer.identifier), "Hide in the editor" if vis else "Show in the editor", size = 22) {
				Editor_RecordUndo(state, "Toggle layer")
				ln.editorSoloLayer = ""
				if !vis == layer.visible do delete_key(&ln.layerVisibility, layer.identifier)
				else do ln.layerVisibility[strings.clone(layer.identifier, ln.allocator)] = !vis
			}
			imgui.SameLine(0, 2)
			if UI_IconButton(ICON_FA_BULLSEYE, fmt.tprintf("ldtk.layer.solo:%s", layer.identifier), "Show only this layer" if !solo else "Show all layers", solo, 22) {
				ln.editorSoloLayer = "" if solo else strings.clone(layer.identifier, ln.allocator)
			}
			imgui.TableNextColumn()
			imgui.AlignTextToFramePadding()
			sel := lp.selLayer == layer.identifier
			imgui.PushStyleColorImVec4(.Text, UI_TEXT if vis else UI_TEXT_FAINT)
			if imgui.Selectable(fmt.ctprintf("%s  %s", layer_icon(layer.type), layer.identifier), sel, {.SpanAllColumns, .AllowOverlap}) {
				lp.selLayer = strings.clone(layer.identifier)
			}
			imgui.PopStyleColor()
			Drive_Item(fmt.tprintf("ldtk.layer:%s", layer.identifier))
			if imgui.IsItemHovered() do hovered = layer.identifier
			if !layer.visible do UI_Tooltip("Hidden in LDtk: the game doesn't draw it")
			imgui.TableNextColumn()
			UI_DimText(fmt.tprint(layer.type))
			imgui.TableNextColumn()
			imgui.TextUnformatted(fmt.ctprintf("%d", layer.gridSize))
			imgui.TableNextColumn()
			imgui.TextUnformatted(fmt.ctprintf("%dx%d", layer.cWid, layer.cHei))
			imgui.TableNextColumn()
			if layer.parallax != {0, 0} {
				imgui.TextUnformatted(fmt.ctprintf("%.2f, %.2f%s", layer.parallax.x, layer.parallax.y, " ⤢" if layer.parallaxScaling else ""))
				UI_Tooltip("Parallax factor (x, y) with scaling" if layer.parallaxScaling else "Parallax factor (x, y)")
			} else {
				UI_DimText("-")
			}
			imgui.TableNextColumn()
			imgui.TextUnformatted(fmt.ctprintf("%d%%", int(layer.opacity * 100 + 0.5)))
			imgui.TableNextColumn()
			switch layer.type {
			case .Entities: UI_DimText(fmt.tprintf("%d entities", len(layer.entities)))
			case .IntGrid:
				n := 0
				for v in layer.intGrid do if v != 0 do n += 1
				UI_DimText(fmt.tprintf("%d cells%s", n, fmt.tprintf(", %d tiles", len(layer.autoLayerTiles)) if len(layer.autoLayerTiles) > 0 else ""))
			case .Tiles, .AutoLayer: UI_DimText(fmt.tprintf("%d tiles", len(layer.gridTiles) + len(layer.autoLayerTiles)))
			}
			imgui.PopID()
		}
		imgui.EndTable()
	}
	ln.editorHighlight = strings.clone(hovered, ln.allocator) if hovered != "" else ""

	// IntGrid legend of the selected layer.
	if sel := e.Ldtk_GetLayer(lvl, lp.selLayer); sel != nil && sel.type == .IntGrid {
		imgui.Dummy({0, 4})
		UI_DimText(fmt.tprintf("%s values", sel.identifier))
		if def := e.Ldtk_GetLayerDef(ln.project, sel.layerDefUid); def != nil {
			for v in def.intGridValues {
				swatch(fmt.tprintf("lg%d", v.value), v.color)
				imgui.SameLine(0, 4)
				imgui.TextUnformatted(fmt.ctprintf("%d  %s", v.value, v.identifier if v.identifier != "" else "(unnamed)"))
				imgui.SameLine(0, UI_SPACE)
			}
			imgui.NewLine()
		}
	}
}

// --- Entities ------------------------------------------------------------------------

@(private = "file")
count_instances :: proc(ln: ^e.LdtkLevelNode, identifier: string) -> int {
	n := 0
	for lvl in ln.activeLevels do for &layer in lvl.layers do for &ent in layer.entities do if ent.identifier == identifier do n += 1
	return n
}

@(private = "file")
mode_label :: proc(ln: ^e.LdtkLevelNode, state: ^EditorState, identifier: string) -> string {
	m := e.LdtkLevelNode_EntityMapping(ln, identifier)
	switch m.mode {
	case .Auto:
		if comp := e.LdtkLevelNode_EntityComponent(ln, identifier, &state.game.gameContext); comp != "" do return filepath.stem(filepath.stem(comp))
		if t := e.LdtkLevelNode_EntityCustomType(ln, identifier, &state.game.gameContext); t != nil do return t.name
		return "Node"
	case .Component: return filepath.stem(filepath.stem(m.component)) if m.component != "" else "(no component)"
	case .CustomNode:
		if t := e.LdtkLevelNode_EntityCustomType(ln, identifier, &state.game.gameContext); t != nil do return t.name
		return "(no custom node type)"
	case .Node: return "Node"
	case .None: return "not spawned"
	}
	return ""
}

@(private = "file")
page_entities :: proc(state: ^EditorState, ln: ^e.LdtkLevelNode) {
	proj := ln.project
	if len(proj.entityDefs) == 0 {
		UI_DimText("This project has no entity definitions.")
		return
	}
	if lp.selEntity == "" || e.Ldtk_GetEntityDef(proj, lp.selEntity) == nil do lp.selEntity = strings.clone(proj.entityDefs[0].identifier)
	// Auto mappings and the project's custom node types (#157): opt in.
	match := ln.matchCustomNodes
	if imgui.Checkbox("Auto also spawns the custom node type named like the entity", &match) {
		Editor_RecordUndo(state, "LDtk match custom nodes")
		ln.matchCustomNodes = match
		e.LdtkLevelNode_Rebuild(ln)
	}
	Drive_Item("ldtk.match-custom-nodes")
	UI_Tooltip("An entity set to Auto, with no component of its name: the custom node type of its name (Hurtbox for a Hurtbox entity), if the project has one")
	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##ldtk_entdefs", {220, avail.y}, {.Borders}, {}) {
		for &d in proj.entityDefs {
			imgui.PushIDPtr(&d)
			n := count_instances(ln, d.identifier)
			clicked := imgui.Selectable("##def", lp.selEntity == d.identifier, {.AllowOverlap}, {0, 24})
			Drive_Item(fmt.tprintf("ldtk.entity:%s", d.identifier))
			if clicked do lp.selEntity = strings.clone(d.identifier)
			min := imgui.GetItemRectMin()
			imgui.SetCursorScreenPos({min.x + 4, min.y + 5})
			if !tile_image(proj, d.tile, 14) do swatch("def", d.color)
			imgui.SameLine(0, 6)
			imgui.TextUnformatted(strings.clone_to_cstring(d.identifier, context.temp_allocator))
			imgui.SameLine(0, 6)
			UI_DimText(fmt.tprintf("%d · %s", n, mode_label(ln, state, d.identifier)))
			imgui.PopID()
		}
	}
	imgui.EndChild()
	imgui.SameLine(0, 8)
	if imgui.BeginChild("##ldtk_entdetail", {0, avail.y}, {}, {}) {
		if def := e.Ldtk_GetEntityDef(proj, lp.selEntity); def != nil do entity_detail(state, ln, def)
	}
	imgui.EndChild()
}

@(private = "file")
entity_detail :: proc(state: ^EditorState, ln: ^e.LdtkLevelNode, def: ^e.LdtkEntityDef) {
	proj := ln.project
	ctx := &state.game.gameContext
	imgui.PushFont(GlobalFonts.semibold)
	imgui.TextUnformatted(strings.clone_to_cstring(def.identifier, context.temp_allocator))
	imgui.PopFont()
	if len(def.tags) > 0 {
		imgui.SameLine(0, 8)
		UI_DimText(strings.join(def.tags[:], ", ", context.temp_allocator))
	}

	m := e.LdtkLevelNode_EntityMapping(ln, def.identifier)
	if UI_BeginProps("##ent_map") {
		UI_PropLabel("Spawn as")
		names := []string{"Auto (component by name)", "Component", "Plain Node", "Don't spawn", "Custom Node Type"}
		if v, changed := UI_Combo("ldtk.spawn-mode", int(m.mode), names); changed {
			Editor_RecordUndo(state, "LDtk entity mapping")
			m.mode = e.LdtkSpawnMode(v)
			e.LdtkLevelNode_SetEntityMapping(ln, m)
			e.LdtkLevelNode_Rebuild(ln)
		}
		#partial switch m.mode {
		case .Auto:
			UI_PropLabel("")
			if comp := e.LdtkLevelNode_EntityComponent(ln, def.identifier, ctx); comp != "" do UI_DimText(comp)
			else if t := e.LdtkLevelNode_EntityCustomType(ln, def.identifier, ctx); t != nil do UI_DimText(fmt.tprintf("the %s custom node type (%s)", t.name, t.path))
			else do UI_DimText(fmt.tprintf("components/%s.component.json not found: a plain Node", def.identifier))
		case .CustomNode:
			UI_PropLabel("Node type")
			if path, ok := asset_picker("ldtk.node-type", m.nodeType, Editor_ListProjectFiles(state, "", {e.CUSTOM_NODE_SUFFIX})); ok {
				Editor_RecordUndo(state, "LDtk entity node type")
				m.nodeType = path
				e.LdtkLevelNode_SetEntityMapping(ln, m)
				e.LdtkLevelNode_Rebuild(ln)
			}
		case .Component:
			UI_PropLabel("Component")
			if path, ok := asset_picker("ldtk.component", m.component, Editor_ListProjectFiles(state, "components", {".component.json"})); ok {
				Editor_RecordUndo(state, "LDtk entity component")
				m.component = path
				e.LdtkLevelNode_SetEntityMapping(ln, m)
				e.LdtkLevelNode_Rebuild(ln)
			}
		}
		UI_PropLabel("")
		if UI_Button(fmt.tprintf("%s  Create Component...", ICON_FA_CUBES), "ldtk.create-component") {
			if rel := Ldtk_CreateEntityComponent(state, def); rel != "" {
				Editor_RecordUndo(state, "LDtk entity component")
				e.LdtkLevelNode_SetEntityMapping(ln, {entity = def.identifier, mode = .Component, component = rel})
				e.LdtkLevelNode_Rebuild(ln)
			}
		}
		UI_Tooltip("Creates components/<Entity>.component.json with a script whose properties match the entity's fields")
		UI_EndProps()
	}

	// Fields: which reach a script property.
	props: map[string]bool
	props.allocator = context.temp_allocator
	if t := e.LdtkLevelNode_EntityCustomType(ln, def.identifier, ctx); t != nil {
		// A custom node type: its script's properties.
		if script := e.CustomNode_Script(t, ctx); script != "" {
			if mod, ok := e.ScriptManager_LoadModule(script, &state.game.scriptManager); ok && mod != nil {
				for p in mod.properties do props[p.name] = true
			}
		}
	} else if comp := e.LdtkLevelNode_EntityComponent(ln, def.identifier, ctx); comp != "" {
		if data, ok := e.Component_ReadFile(ctx, comp); ok {
			if script := component_script(string(data)); script != "" {
				sm := &state.game.scriptManager
				if mod, has := sm.modules[e.ScriptVFS_NormalizePath(script)]; has && mod != nil {
					for p in mod.properties do props[p.name] = true
				}
			}
		}
	}
	if len(def.fields) > 0 && imgui.BeginTable("##ent_fields", 3, imgui.TableFlags_RowBg | imgui.TableFlags_SizingStretchProp) {
		imgui.TableSetupColumn("Field", {}, 0.35)
		imgui.TableSetupColumn("Type", {}, 0.35)
		imgui.TableSetupColumn("Script property", {}, 0.3)
		imgui.TableHeadersRow()
		for f in def.fields {
			imgui.TableNextRow()
			imgui.TableNextColumn()
			imgui.TextUnformatted(strings.clone_to_cstring(f.identifier, context.temp_allocator))
			imgui.TableNextColumn()
			UI_DimText(f.typeName)
			imgui.TableNextColumn()
			if strings.contains(f.typeName, "EntityRef") {
				UI_DimText("link (see Links)")
			} else if f.isArray {
				UI_DimText("node:ldtk_field()")
			} else if props[f.identifier] {
				imgui.PushStyleColorImVec4(.Text, UI_SUCCESS)
				imgui.TextUnformatted(fmt.ctprintf("%s  %s", ICON_FA_CHECK, f.identifier))
				imgui.PopStyleColor()
			} else {
				UI_DimText("node:ldtk_field()")
			}
		}
		imgui.EndTable()
	}

	// Instances.
	imgui.Dummy({0, 4})
	UI_DimText(fmt.tprintf("Placed in %s (click to frame)", "this world" if ln.worldMode else "this level"))
	if imgui.BeginTable("##ent_inst", 4, imgui.TableFlags_RowBg | imgui.TableFlags_BordersInnerH | imgui.TableFlags_SizingStretchProp) {
		imgui.TableSetupColumn("Instance", {}, 0.22)
		imgui.TableSetupColumn("Level", {}, 0.18)
		imgui.TableSetupColumn("Position", {}, 0.18)
		imgui.TableSetupColumn("Fields", {}, 0.42)
		imgui.TableHeadersRow()
		for lvl in ln.activeLevels {
			for &layer in lvl.layers {
				for &ent in layer.entities {
					if ent.identifier != def.identifier do continue
					imgui.PushIDPtr(&ent)
					imgui.TableNextRow()
					imgui.TableNextColumn()
					short := ent.iid[:min(8, len(ent.iid))]
					if imgui.Selectable(fmt.ctprintf("%s##inst", short), lp.focusIid == ent.iid, {.SpanAllColumns, .AllowOverlap}) {
						Ldtk_FocusEntity(state, ln, lvl, &ent)
					}
					Drive_Item(fmt.tprintf("ldtk.instance:%s", ent.iid))
					UI_Tooltip(ent.iid)
					imgui.TableNextColumn()
					imgui.TextUnformatted(strings.clone_to_cstring(lvl.identifier, context.temp_allocator))
					imgui.TableNextColumn()
					imgui.TextUnformatted(fmt.ctprintf("%d, %d", int(ent.px.x), int(ent.px.y)))
					imgui.TableNextColumn()
					for &f, i in ent.fields {
						if i > 0 do imgui.SameLine(0, 10)
						UI_DimText(fmt.tprintf("%s:", f.identifier))
						imgui.SameLine(0, 4)
						field_value_cell(proj, &f)
					}
					imgui.PopID()
				}
			}
		}
		imgui.EndTable()
	}
}

// component_script: the script path of a component file's root ("" none).
@(private = "file")
component_script :: proc(text: string) -> string {
	i := strings.index(text, "\"script\"")
	if i < 0 do return ""
	rest := text[i:]
	j := strings.index(rest, "\"path\"")
	if j < 0 do return ""
	rest = rest[j + 6:]
	q1 := strings.index_byte(rest, '"')
	if q1 < 0 do return ""
	rest = rest[q1 + 1:]
	q2 := strings.index_byte(rest, '"')
	if q2 < 0 do return ""
	return rest[:q2]
}

// Ldtk_FocusEntity frames an entity in the viewport and highlights it.
Ldtk_FocusEntity :: proc(state: ^EditorState, ln: ^e.LdtkLevelNode, lvl: ^e.LdtkLevel, ent: ^e.LdtkEntityInstance) {
	lp.focusIid = strings.clone(ent.iid)
	lp.focusUntil = time.time_add(time.now(), 2 * time.Second)
	center := ent.px + ent.size * ([2]f32{0.5, 0.5} - ent.pivot)
	state.cameraPos = ln.globalPosition + (e.LdtkLevelNode_LevelOffset(ln, lvl) + center) * ln.globalScale
}

// Ldtk_CreateEntityComponent writes components/<Entity>.component.json and
// scripts/<entity>.lua declaring a property per (non-array) LDtk field.
Ldtk_CreateEntityComponent :: proc(state: ^EditorState, def: ^e.LdtkEntityDef) -> string {
	ident := def.identifier
	compRel := fmt.tprintf("components/%s.component.json", ident)
	compFull, _ := filepath.join({state.projectPath, compRel}, context.temp_allocator)
	if os.exists(compFull) {
		Editor_Log(state, .Info, "%s already exists: using it", compRel)
		return strings.clone(compRel, context.temp_allocator)
	}
	snake := strings.to_snake_case(ident, context.temp_allocator)
	scriptRel := fmt.tprintf("scripts/%s.lua", snake)
	scriptFull, _ := filepath.join({state.projectPath, scriptRel}, context.temp_allocator)
	if !os.exists(scriptFull) {
		cls := strings.to_pascal_case(ident, context.temp_allocator)
		sb := strings.builder_make(context.temp_allocator)
		fmt.sbprintf(&sb, "-- %s: spawned for each LDtk %s entity.\n", snake, ident)
		strings.write_string(&sb, "-- LDtk fields with the same name as a property below are copied onto\n-- it when the level is built; self.node:ldtk_entity() has all of them.\n")
		fmt.sbprintf(&sb, "---@class %s : ScriptInstanceBase\nlocal %s = {{}}\n\n", cls, cls)
		fmt.sbprintf(&sb, "%s.properties = {{\n", cls)
		refs := make([dynamic]string, context.temp_allocator)
		for f in def.fields {
			if strings.contains(f.typeName, "EntityRef") {
				append(&refs, f.identifier)
				continue
			}
			if f.isArray {
				fmt.sbprintf(&sb, "    -- %s (%s): self.node:ldtk_field(\"%s\")\n", f.identifier, f.typeName, f.identifier)
				continue
			}
			kind, dflt := "string", "\"\""
			switch {
			case f.typeName == "Int": kind, dflt = "int", "0"
			case f.typeName == "Float": kind, dflt = "float", "0.0"
			case f.typeName == "Bool": kind, dflt = "bool", "false"
			case f.typeName == "Color": kind, dflt = "color", "{ 1, 1, 1, 1 }"
			case f.typeName == "Point": kind, dflt = "vector2", "{ 0, 0 }"
			}
			fmt.sbprintf(&sb, "    %s = {{ type = \"%s\", default = %s }},%s\n", f.identifier, kind, dflt, fmt.tprintf(" -- enum %s", f.enumName) if f.enumName != "" else "")
		}
		strings.write_string(&sb, "}\n\n")
		fmt.sbprintf(&sb, "function %s:ready()\n", cls)
		for r in refs do fmt.sbprintf(&sb, "    -- local target = self.node:ldtk_ref(\"%s\")  -- linked entity's node\n", r)
		strings.write_string(&sb, "end\n\n---@param dt number\n")
		fmt.sbprintf(&sb, "function %s:update(dt)\nend\n\nreturn %s\n", cls, cls)
		_ = os.make_directory_all(filepath.dir(scriptFull, context.temp_allocator))
		Editor_InvalidateProjectFiles() // the asset lists rescan
		if os.write_entire_file(scriptFull, transmute([]u8)strings.to_string(sb)) != nil {
			Editor_Log(state, .Error, "Could not write %s", scriptRel)
			return ""
		}
		Editor_Log(state, .Info, "Created %s", scriptRel)
	}
	comp := fmt.tprintf("{{\n  \"name\": \"%s\",\n  \"component\": true,\n  \"type\": \"Node\",\n  \"script\": {{\"path\": \"%s\"}}\n}}\n", ident, scriptRel)
	_ = os.make_directory_all(filepath.dir(compFull, context.temp_allocator))
	Editor_InvalidateProjectFiles() // the asset lists rescan
	if os.write_entire_file(compFull, transmute([]u8)comp) != nil {
		Editor_Log(state, .Error, "Could not write %s", compRel)
		return ""
	}
	// Load the script so the Inspector / field matching sees its properties.
	e.ScriptManager_LoadModule(scriptRel, &state.game.scriptManager)
	Editor_Log(state, .Info, "Created %s (spawned for LDtk %s entities)", compRel, ident)
	return strings.clone(compRel, context.temp_allocator)
}

// --- Collision -----------------------------------------------------------------------

@(private = "file")
page_collision :: proc(state: ^EditorState, ln: ^e.LdtkLevelNode) {
	proj := ln.project
	any := false
	if !ln.enablePhysics {
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextUnformatted(fmt.ctprintf("%s  Physics is off for this level (Inspector: Enable Physics).", ICON_FA_TRIANGLE_EXCLAMATION))
		imgui.PopStyleColor()
	}
	imgui.Checkbox("Show colliders while simulating", &ln.drawDebugColliders)
	Drive_Item("ldtk.show-colliders")
	hint("What each IntGrid value builds when the level runs. Neighbouring cells with the same setting merge into a few large boxes.")
	// The level's collision layers and mask: the default for every value
	// that doesn't set its own (also in the Inspector).
	imgui.AlignTextToFramePadding()
	imgui.TextUnformatted("Default layers")
	imgui.SameLine()
	imgui.SetNextItemWidth(170)
	if set := ln.categoryLayers; layer_set_combo("ldtk.layers.default", &set) {
		Editor_RecordUndo(state, "LDtk collision layers")
		ln.categoryLayers = set
		e.LdtkLevelNode_Rebuild(ln)
	}
	UI_Tooltip("The collision layers the level's colliders are on, unless a value sets its own (Project Settings > General > Collision Layers names them)")
	imgui.SameLine(0, 12)
	imgui.TextUnformatted("Mask")
	imgui.SameLine()
	imgui.SetNextItemWidth(170)
	if set := ln.maskLayers; layer_set_combo("ldtk.mask.default", &set) {
		Editor_RecordUndo(state, "LDtk collision mask")
		ln.maskLayers = set
		e.LdtkLevelNode_Rebuild(ln)
	}
	UI_Tooltip("The collision layers the level's colliders collide with, unless a value sets its own")
	for &def in proj.layerDefs {
		if def.type != .IntGrid || len(def.intGridValues) == 0 do continue
		any = true
		imgui.Dummy({0, 2})
		imgui.PushFont(GlobalFonts.semibold)
		imgui.TextUnformatted(fmt.ctprintf("%s  %s", ICON_FA_BORDER_ALL, def.identifier))
		imgui.PopFont()
		counts := make(map[int]int, allocator = context.temp_allocator)
		for lvl in ln.activeLevels {
			if layer := e.Ldtk_GetLayer(lvl, def.identifier); layer != nil do for v in layer.intGrid do counts[v] += 1
		}
		imgui.PushIDPtr(&def)
		if imgui.BeginTable("##coll", 8, imgui.TableFlags_RowBg | imgui.TableFlags_BordersInnerH | imgui.TableFlags_SizingFixedFit) {
			imgui.TableSetupColumn("", {.WidthFixed}, 22)
			imgui.TableSetupColumn("Value", {.WidthStretch}, 0)
			imgui.TableSetupColumn("Cells", {.WidthFixed}, 50)
			imgui.TableSetupColumn("Collision", {.WidthFixed}, 130)
			imgui.TableSetupColumn("Friction", {.WidthFixed}, 80)
			imgui.TableSetupColumn("Bounce", {.WidthFixed}, 80)
			imgui.TableSetupColumn("Layers", {.WidthFixed}, 120)
			imgui.TableSetupColumn("Mask", {.WidthFixed}, 120)
			imgui.TableHeadersRow()
			for v in def.intGridValues {
				imgui.PushIDInt(c.int(v.value))
				imgui.TableNextRow()
				imgui.TableNextColumn()
				swatch("v", v.color)
				imgui.TableNextColumn()
				imgui.AlignTextToFramePadding()
				imgui.TextUnformatted(fmt.ctprintf("%d  %s", v.value, v.identifier if v.identifier != "" else ""))
				imgui.TableNextColumn()
				UI_DimText(fmt.tprint(counts[v.value]))
				rule := e.LdtkLevelNode_CollisionRule(ln, def.identifier, v.value)
				imgui.TableNextColumn()
				imgui.SetNextItemWidth(-1)
				names := []string{"None", "Solid", "One-way", "Trigger"}
				if t, changed := UI_Combo(fmt.tprintf("ldtk.coll:%s:%d", def.identifier, v.value), int(rule.type), names); changed {
					Editor_RecordUndo(state, "LDtk collision")
					rule.type = e.LdtkCollisionType(t)
					if rule.friction == 0 && rule.restitution == 0 do rule.friction, rule.restitution = e.DEFAULT_LDTK_FRICTION, e.DEFAULT_LDTK_RESTITUTION
					e.LdtkLevelNode_SetCollisionRule(ln, rule)
					e.LdtkLevelNode_Rebuild(ln)
				}
				if rule.type == .Trigger do UI_Tooltip(fmt.tprintf("An AreaNode \"%s\": body_entered / body_exited. Lua: level:ldtk_get_triggers()", e.Ldtk_TriggerName(ln, def.identifier, v.value)))
				if rule.type == .OneWay do UI_Tooltip("Solid from above, passable from below (platforms)")
				solidish := rule.type == .Solid || rule.type == .OneWay
				imgui.TableNextColumn()
				if solidish {
					imgui.SetNextItemWidth(-1)
					f := rule.friction
					if imgui.DragFloat("##fr", &f, 0.01, 0, 2, "%.2f") {
						rule.friction = f
						e.LdtkLevelNode_SetCollisionRule(ln, rule)
					}
					if imgui.IsItemActivated() do Editor_RecordUndo(state, "LDtk friction")
					if imgui.IsItemDeactivatedAfterEdit() do e.LdtkLevelNode_Rebuild(ln)
				}
				imgui.TableNextColumn()
				if solidish {
					imgui.SetNextItemWidth(-1)
					r := rule.restitution
					if imgui.DragFloat("##re", &r, 0.01, 0, 1, "%.2f") {
						rule.restitution = r
						e.LdtkLevelNode_SetCollisionRule(ln, rule)
					}
					if imgui.IsItemActivated() do Editor_RecordUndo(state, "LDtk bounce")
					if imgui.IsItemDeactivatedAfterEdit() do e.LdtkLevelNode_Rebuild(ln)
				}
				// Collision layers and mask: the level's default, or its own.
				cat, mask := e.LdtkLevelNode_RuleLayers(ln, rule)
				for k in 0 ..< 2 {
					imgui.TableNextColumn()
					if rule.type == .None do continue
					set := cat if k == 0 else mask
					useDefault := !rule.customLayers
					imgui.SetNextItemWidth(-1)
					id := fmt.tprintf("ldtk.coll-%s:%s:%d", "layers" if k == 0 else "mask", def.identifier, v.value)
					if layer_set_combo(id, &set, &useDefault) {
						Editor_RecordUndo(state, "LDtk collision layers")
						// Its own starts from what it had (the default's).
						rule.customLayers = !useDefault
						rule.categoryLayers, rule.maskLayers = cat, mask
						if k == 0 do rule.categoryLayers = set
						else do rule.maskLayers = set
						e.LdtkLevelNode_SetCollisionRule(ln, rule)
						e.LdtkLevelNode_Rebuild(ln)
					}
					UI_Tooltip(fmt.tprintf("%s: %s", "The collision layers its colliders are on" if k == 0 else "The collision layers its colliders collide with", "the level's default" if useDefault else "its own"))
				}
				imgui.PopID()
			}
			imgui.EndTable()
		}
		imgui.PopID()
	}
	if !any do UI_DimText("This project has no IntGrid layers.")
}

// layer_set_text: "All", "None", or the layers' names ("Walls, 3").
@(private = "file")
layer_set_text :: proc(set: e.CollisionLayerSet) -> string {
	if set == e.DEFAULT_COLLISION_MASK do return "All"
	if set == {} do return "None"
	parts := make([dynamic]string, context.temp_allocator)
	for l in e.CollisionLayer do if l in set {
		name := e.collisionLayerNames[int(l)]
		append(&parts, name if name != "" else fmt.tprint(int(l) + 1))
	}
	return strings.join(parts[:], ", ", context.temp_allocator)
}

// layer_set_combo: the 16 collision layers (the project's names) as
// checkboxes; with useDefault, a "Level default" item first. Drives:
// @<id>, then @<id>/default and @<id>/<1-16>.
@(private = "file")
layer_set_combo :: proc(id: string, set: ^e.CollisionLayerSet, useDefault: ^bool = nil) -> (changed: bool) {
	preview := layer_set_text(set^)
	if useDefault != nil && useDefault^ do preview = fmt.tprintf("Default: %s", preview)
	if imgui.BeginCombo(fmt.ctprintf("##%s", id), strings.clone_to_cstring(preview, context.temp_allocator), {.HeightLarge}) {
		if useDefault != nil {
			if imgui.Checkbox("Level default", useDefault) do changed = true
			Drive_Item(fmt.tprintf("%s/default", id))
			UI_Tooltip("Use the level's layers and mask (the Inspector's Category / Mask Layers)")
			imgui.Separator()
		}
		for l in e.CollisionLayer {
			on := l in set^
			if imgui.Checkbox(fmt.ctprintf("%s##%v", e.CollisionLayer_DisplayName(l), l), &on) {
				if on do set^ += {l}
				else do set^ -= {l}
				if useDefault != nil do useDefault^ = false // picking a layer: its own
				changed = true
			}
			Drive_Item(fmt.tprintf("%s/%d", id, int(l) + 1))
		}
		imgui.EndCombo()
	}
	Drive_Item(id)
	return
}

// layer_set_query: "1,3" / "all" / "none" (drive queries).
@(private = "file")
layer_set_query :: proc(set: e.CollisionLayerSet) -> string {
	if set == e.DEFAULT_COLLISION_MASK do return "all"
	if set == {} do return "none"
	parts := make([dynamic]string, context.temp_allocator)
	for l in e.CollisionLayer do if l in set do append(&parts, fmt.tprint(int(l) + 1))
	return strings.join(parts[:], ",", context.temp_allocator)
}

// --- Links ---------------------------------------------------------------------------

@(private = "file")
edit_text :: proc(state: ^EditorState, id, hint: string, value: ^string, alloc := context.allocator) -> bool {
	buf: [128]u8
	copy(buf[:len(buf) - 1], value^)
	imgui.SetNextItemWidth(130)
	changed := imgui.InputTextWithHint(fmt.ctprintf("##%s", id), strings.clone_to_cstring(hint, context.temp_allocator), cstring(raw_data(buf[:])), len(buf), {})
	Drive_Item(id)
	if imgui.IsItemActivated() do Editor_RecordUndo(state, "LDtk link rule")
	if changed do value^ = strings.clone(string(cstring(raw_data(buf[:]))), alloc)
	return changed
}

@(private = "file")
page_links :: proc(state: ^EditorState, ln: ^e.LdtkLevelNode) {
	proj := ln.project
	hint("EntityRef fields link entities. When both ends are spawned, a rule can connect a signal or parent one to the other; scripts can always follow links (node:ldtk_ref).")
	found := false
	for &def in proj.entityDefs {
		for f in def.fields {
			if !strings.contains(f.typeName, "EntityRef") do continue
			found = true
			imgui.PushIDPtr(&def)
			imgui.PushID(strings.clone_to_cstring(f.identifier, context.temp_allocator))
			// References of this field in the active levels.
			refs := 0
			for lvl in ln.activeLevels do for &layer in lvl.layers do for &ent in layer.entities {
				if ent.identifier != def.identifier do continue
				for r in e.Ldtk_EntityRefs(&ent) do if r.field == f.identifier do refs += 1
			}
			imgui.Dummy({0, 2})
			imgui.PushFont(GlobalFonts.semibold)
			imgui.TextUnformatted(fmt.ctprintf("%s  %s.%s", ICON_FA_LINK, def.identifier, f.identifier))
			imgui.PopFont()
			imgui.SameLine(0, 8)
			UI_DimText(fmt.tprintf("%s · %d reference%s", f.typeName, refs, "" if refs == 1 else "s"))
			imgui.SameLine()
			if UI_Button(fmt.tprintf("%s  Add Rule", ICON_FA_PLUS), fmt.tprintf("ldtk.link.add:%s.%s", def.identifier, f.identifier)) {
				Editor_RecordUndo(state, "Add LDtk link rule")
				append(&ln.linkRules, e.LdtkLinkRule{entity = strings.clone(def.identifier, ln.allocator), field = strings.clone(f.identifier, ln.allocator), action = .Signal})
			}
			remove := -1
			for &r, ri in ln.linkRules {
				if r.entity != def.identifier || r.field != f.identifier do continue
				imgui.PushIDInt(c.int(ri))
				imgui.Indent(18)
				imgui.SetNextItemWidth(190)
				names := []string{"Connect signal", "Parent target to source", "Parent source to target"}
				if a, changed := UI_Combo(fmt.tprintf("ldtk.link.action:%d", ri), int(r.action), names); changed {
					Editor_RecordUndo(state, "LDtk link rule")
					r.action = e.LdtkLinkAction(a)
				}
				if r.action == .Signal {
					imgui.SameLine()
					imgui.AlignTextToFramePadding()
					UI_DimText(fmt.tprintf("%s's", def.identifier))
					imgui.SameLine()
					edit_text(state, fmt.tprintf("ldtk.link.signal:%d", ri), "signal", &r.signal, ln.allocator)
					imgui.SameLine()
					UI_DimText("->  target:")
					imgui.SameLine()
					edit_text(state, fmt.tprintf("ldtk.link.method:%d", ri), "method", &r.method, ln.allocator)
					if r.signal != "" && r.method != "" do UI_Tooltip(fmt.tprintf("When a %s emits \"%s\", Target:%s(value, source) runs on each entity in %s", def.identifier, r.signal, r.method, f.identifier))
				}
				imgui.SameLine()
				if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("ldtk.link.remove:%d", ri), "Remove rule", size = 24) do remove = ri
				imgui.Unindent(18)
				imgui.PopID()
			}
			if remove >= 0 {
				Editor_RecordUndo(state, "Remove LDtk link rule")
				ordered_remove(&ln.linkRules, remove)
			}
			imgui.PopID()
			imgui.PopID()
		}
	}
	if !found {
		UI_DimText("No entity has an EntityRef field.")
		return
	}
	// The references in the active levels.
	imgui.Dummy({0, 6})
	UI_DimText("References (click to frame the source)")
	if imgui.BeginTable("##ldtk_refs", 3, imgui.TableFlags_RowBg | imgui.TableFlags_BordersInnerH | imgui.TableFlags_SizingStretchProp) {
		imgui.TableSetupColumn("Source", {}, 0.35)
		imgui.TableSetupColumn("Field", {}, 0.25)
		imgui.TableSetupColumn("Target", {}, 0.4)
		imgui.TableHeadersRow()
		for lvl in ln.activeLevels do for &layer in lvl.layers do for &ent in layer.entities {
			for r in e.Ldtk_EntityRefs(&ent) {
				imgui.PushIDPtr(&ent)
				imgui.PushIDInt(c.int(r.index + 1))
				imgui.TableNextRow()
				imgui.TableNextColumn()
				if imgui.Selectable(fmt.ctprintf("%s  %s##ref%s", ent.identifier, ent.iid[:min(6, len(ent.iid))], r.field), false, {.SpanAllColumns}) do Ldtk_FocusEntity(state, ln, lvl, &ent)
				imgui.TableNextColumn()
				UI_DimText(r.field if r.index < 0 else fmt.tprintf("%s[%d]", r.field, r.index))
				imgui.TableNextColumn()
				tgt, tlvl := e.Ldtk_FindEntity(ln.project, r.ref.entityIid)
				if tgt == nil {
					UI_DimText(fmt.tprintf("missing %s", r.ref.entityIid))
				} else {
					inActive := slice.contains(ln.activeLevels[:], tlvl)
					imgui.TextUnformatted(fmt.ctprintf("%s  %s", tgt.identifier, tgt.iid[:min(6, len(tgt.iid))]))
					if tlvl != lvl {
						imgui.SameLine()
						UI_DimText(fmt.tprintf("in %s%s", tlvl.identifier, "" if inActive else " (not loaded: World mode links it)"))
					}
				}
				imgui.PopID()
				imgui.PopID()
			}
		}
		imgui.EndTable()
	}
}

// --- Level fields ----------------------------------------------------------------------

@(private = "file")
page_level_fields :: proc(state: ^EditorState, ln: ^e.LdtkLevelNode) {
	proj := ln.project
	if len(proj.levelFieldDefs) == 0 {
		UI_DimText("This project defines no level fields (LDtk: Project > Level fields).")
		return
	}
	hint("Lua: level:ldtk_get_level_field(name [, level]) / level:ldtk_get_level_fields([level]).")
	levels := ln.activeLevels[:]
	if imgui.BeginTable("##ldtk_lfields", c.int(2 + len(levels)), imgui.TableFlags_RowBg | imgui.TableFlags_BordersInnerH | imgui.TableFlags_SizingStretchProp | imgui.TableFlags_ScrollX) {
		imgui.TableSetupColumn("Field", {}, 0.2)
		imgui.TableSetupColumn("Type", {}, 0.18)
		for lvl in levels do imgui.TableSetupColumn(strings.clone_to_cstring(lvl.identifier, context.temp_allocator), {}, 0.62 / f32(len(levels)))
		imgui.TableHeadersRow()
		for fd in proj.levelFieldDefs {
			imgui.TableNextRow()
			imgui.TableNextColumn()
			imgui.TextUnformatted(strings.clone_to_cstring(fd.identifier, context.temp_allocator))
			Drive_Item(fmt.tprintf("ldtk.field:%s", fd.identifier))
			imgui.TableNextColumn()
			UI_DimText(fd.typeName)
			for lvl in levels {
				imgui.TableNextColumn()
				if f := e.Ldtk_GetLevelField(lvl, fd.identifier); f != nil do field_value_cell(proj, f)
				else do UI_DimText("-")
			}
		}
		imgui.EndTable()
	}
}

// --- Enums -----------------------------------------------------------------------------

@(private = "file")
page_enums :: proc(state: ^EditorState, ln: ^e.LdtkLevelNode) {
	proj := ln.project
	if len(proj.enums) == 0 {
		UI_DimText("This project has no enums.")
		return
	}
	hint("Enum fields reach scripts as the value's id (a string). Lua: level:ldtk_get_enum(name), level:ldtk_get_tile_enums(layer, x, y).")
	for &en in proj.enums {
		imgui.PushIDPtr(&en)
		// Where it's used.
		uses := make([dynamic]string, context.temp_allocator)
		for &d in proj.entityDefs do for f in d.fields do if f.enumName == en.identifier do append(&uses, fmt.tprintf("%s.%s", d.identifier, f.identifier))
		for f in proj.levelFieldDefs do if f.enumName == en.identifier do append(&uses, fmt.tprintf("level.%s", f.identifier))
		for &ts in proj.tilesets do if ts.tagsSourceEnumUid == en.uid do append(&uses, fmt.tprintf("tags of tileset %s (%d tiles)", ts.identifier, len(ts.enumTags)))
		imgui.Dummy({0, 2})
		imgui.PushFont(GlobalFonts.semibold)
		imgui.TextUnformatted(fmt.ctprintf("%s%s", en.identifier, "  (external)" if en.external else ""))
		imgui.PopFont()
		Drive_Item(fmt.tprintf("ldtk.enum:%s", en.identifier))
		if len(uses) > 0 {
			imgui.SameLine(0, 8)
			UI_DimText(fmt.tprintf("used by %s", strings.join(uses[:], ", ", context.temp_allocator)))
		}
		for v, i in en.values {
			if i > 0 do imgui.SameLine(0, 14)
			enum_chip(proj, en.identifier, v.id)
		}
		imgui.PopID()
	}
}

// --- World -----------------------------------------------------------------------------

@(private = "file")
page_world :: proc(state: ^EditorState, ln: ^e.LdtkLevelNode) {
	proj := ln.project
	world := e.Ldtk_WorldOf(proj, ln.level)
	if world == nil do return
	imgui.AlignTextToFramePadding()
	imgui.TextUnformatted(fmt.ctprintf("%s  %s", ICON_FA_FOLDER, world.identifier))
	imgui.SameLine(0, 8)
	UI_DimText(fmt.tprintf("%s layout · %d levels%s", world.layout, len(world.levels), fmt.tprintf(" · %d worlds in the project", len(proj.worlds)) if len(proj.worlds) > 1 else ""))
	imgui.SameLine()
	wm := ln.worldMode
	if imgui.Checkbox("World mode", &wm) {
		Editor_RecordUndo(state, "LDtk world mode")
		e.LdtkLevelNode_SetWorldMode(ln, wm)
	}
	Drive_Item("ldtk.world-mode-check")
	UI_Tooltip("Show and build every level of this world at its world position")

	// Mini-map: the world's levels (current depth) scaled into the panel.
	depth := ln.level.worldDepth
	mn, mx: [2]f32
	have := false
	for i in world.levels {
		l := &proj.levels[i]
		if l.worldDepth != depth do continue
		a := [2]f32{f32(l.worldX), f32(l.worldY)}
		b := a + [2]f32{f32(l.pxWid), f32(l.pxHei)}
		if !have do mn, mx, have = a, b, true
		mn = {min(mn.x, a.x), min(mn.y, a.y)}
		mx = {max(mx.x, b.x), max(mx.y, b.y)}
	}
	if !have do return
	avail := imgui.GetContentRegionAvail()
	canvasW := max(avail.x - 220, 160)
	canvasH := max(avail.y - 8, 80)
	size := mx - mn
	k := min(canvasW / max(size.x, 1), canvasH / max(size.y, 1))
	origin := imgui.GetCursorScreenPos()
	dl := imgui.GetWindowDrawList()
	imgui.DrawList_AddRectFilled(dl, origin, origin + {canvasW, canvasH}, col_u32(UI_BG_APP), 4)
	hovered: ^e.LdtkLevel
	for i in world.levels {
		l := &proj.levels[i]
		if l.worldDepth != depth do continue
		a := origin + ([2]f32{f32(l.worldX), f32(l.worldY)} - mn) * k
		b := a + [2]f32{f32(l.pxWid), f32(l.pxHei)} * k
		imgui.SetCursorScreenPos(a)
		imgui.InvisibleButton(fmt.ctprintf("##map_%s", l.iid), {max(b.x - a.x, 2), max(b.y - a.y, 2)})
		Drive_Item(fmt.tprintf("ldtk.map:%s", l.identifier))
		hot := imgui.IsItemHovered()
		if hot do hovered = l
		if imgui.IsItemClicked() {
			if ln.worldMode {
				Ldtk_FitLevel(state, ln, l)
			} else if l != ln.level {
				Editor_RecordUndo(state, "Set LDtk level")
				e.LdtkLevelNode_SetLevel(ln, l)
			}
		}
		bg := l.bgColor
		bg.a = 200
		imgui.DrawList_AddRectFilled(dl, a, b, col_u32(v4(bg)))
		current := l == ln.level
		border := UI_ACCENT if current else (UI_TEXT if hot else UI_TEXT_FAINT)
		imgui.DrawList_AddRect(dl, a, b, col_u32(border), 0, {}, 2 if current || hot else 1)
		if b.x - a.x > 40 do imgui.DrawList_AddText(dl, a + {4, 3}, col_u32(UI_TEXT), strings.clone_to_cstring(l.identifier, context.temp_allocator))
	}
	imgui.SetCursorScreenPos(origin + {canvasW + 12, 0})
	imgui.BeginGroup()
	show := hovered if hovered != nil else ln.level
	imgui.PushFont(GlobalFonts.semibold)
	imgui.TextUnformatted(strings.clone_to_cstring(show.identifier, context.temp_allocator))
	imgui.PopFont()
	UI_DimText(fmt.tprintf("%d x %d at %d, %d", show.pxWid, show.pxHei, show.worldX, show.worldY))
	if len(show.neighbours) > 0 {
		UI_DimText("Neighbours:")
		for nb in show.neighbours {
			if other := e.Ldtk_GetLevelByIid(proj, nb.levelIid); other != nil do imgui.TextUnformatted(fmt.ctprintf("  %s  %s", nb.dir, other.identifier))
		}
	}
	UI_DimText("Click a level to open it" if !ln.worldMode else "Click a level to frame it")
	imgui.EndGroup()
}

// --- drive queries ---------------------------------------------------------------------

// LdtkPanel_DriveQuery: ldtk.page, ldtk.node, ldtk.level, ldtk.world,
// ldtk.world-mode, ldtk.active-levels, ldtk.rules, ldtk.link-rules,
// ldtk.mapping:<entity>, ldtk.collision:<layer>:<value>,
// ldtk.collision-layers:<layer>:<value> ("default 1/all", "own 2/1,3"),
// ldtk.default-layers ("1/all"),
// ldtk.layer-visible:<layer>, ldtk.focus, ldtk.links (resolved, simulating),
// ldtk.spawned.
LdtkPanel_DriveQuery :: proc(state: ^EditorState, q: string) -> (string, bool) {
	ln := LdtkPanel_Target(state)
	if q == "ldtk.page" do return LDTK_PAGES[lp.page], true
	if ln == nil do return "<no level>", true
	switch q {
	case "ldtk.node": return ln.name, true
	case "ldtk.level": return ln.level.identifier if ln.level != nil else "", true
	case "ldtk.world": return ln.worldIdentifier, true
	case "ldtk.world-mode": return "true" if ln.worldMode else "false", true
	case "ldtk.active-levels": return fmt.tprint(len(ln.activeLevels)), true
	case "ldtk.rules": return fmt.tprint(len(ln.collisionRules)), true
	case "ldtk.link-rules": return fmt.tprint(len(ln.linkRules)), true
	case "ldtk.focus": return lp.focusIid, true
	case "ldtk.links": return fmt.tprint(len(ln.links)), true
	case "ldtk.spawned": return fmt.tprint(len(ln.spawnedEntities)), true
	case "ldtk.default-layers": return fmt.tprintf("%s/%s", layer_set_query(ln.categoryLayers), layer_set_query(ln.maskLayers)), true
	}
	if strings.has_prefix(q, "ldtk.mapping:") {
		m := e.LdtkLevelNode_EntityMapping(ln, q[13:])
		return strings.trim_space(fmt.tprintf("%s %s%s", e.LdtkSpawnMode_Name(m.mode), m.component, m.nodeType)), true
	}
	if strings.has_prefix(q, "ldtk.collision:") {
		parts := strings.split(q[15:], ":", context.temp_allocator)
		if len(parts) != 2 do return "<layer:value>", true
		v := 0
		for ch in parts[1] do v = v * 10 + int(ch - '0')
		return e.LdtkCollisionType_Name(e.LdtkLevelNode_CollisionRule(ln, parts[0], v).type), true
	}
	if strings.has_prefix(q, "ldtk.collision-layers:") {
		parts := strings.split(q[22:], ":", context.temp_allocator)
		if len(parts) != 2 do return "<layer:value>", true
		v := 0
		for ch in parts[1] do v = v * 10 + int(ch - '0')
		rule := e.LdtkLevelNode_CollisionRule(ln, parts[0], v)
		cat, mask := e.LdtkLevelNode_RuleLayers(ln, rule)
		return fmt.tprintf("%s %s/%s", "own" if rule.customLayers else "default", layer_set_query(cat), layer_set_query(mask)), true
	}
	if strings.has_prefix(q, "ldtk.layer-visible:") {
		if ln.level == nil do return "", true
		layer := e.Ldtk_GetLayer(ln.level, q[19:])
		if layer == nil do return "<no layer>", true
		return "true" if e.LdtkLevelNode_LayerVisible(ln, layer) else "false", true
	}
	return "", false
}

// Ldtk_FocusHighlight: the entity iid highlighted in the viewport ("" none).
Ldtk_FocusHighlight :: proc() -> string {
	if lp.focusIid == "" || time.diff(time.now(), lp.focusUntil) < 0 do return ""
	return lp.focusIid
}
