package editor

import "core:c"
import "core:fmt"
import "core:math"
import os "core:os"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Tile map painting. Select a TileMapNode: the bottom panel's Tile Map tab
// shows its settings (tileset, tile size, map size), the tools and the
// tileset's tiles. Pick a tile and a tool, then paint in the viewport: left
// button paints (Paint), erases (Erase) or flood-fills (Fill); the right
// button always erases. One stroke is one undo step.
//
// The Terrains layer paints a terrain of the tileset (terrain_editor.odin):
// each cell takes the tile of its pattern of neighbours, the cells around
// it re-tiled as it's painted, erased or filled.
//
// The Components layer paints linked component instances on the same grid
// (engine/tilemap_components.odin): one per cell, bigger ones over their
// footprint, Shift places one off the grid; erase and fill work on it too.
// ============================================================================

Tile_Tool :: enum {
	None,
	Paint,
	Erase,
	Fill,
}

Tile_Layer :: enum {
	Tiles,      // tileset tiles
	Terrains,   // a terrain of the tileset (auto-tiled)
	Components, // component instances
}

Tile_State :: struct {
	tool:   Tile_Tool,
	layer:  Tile_Layer,
	comp:   string, // the component brush (project-relative .component.json; heap)
	placed: [dynamic]^e.Node, // instances this stroke placed (not replaced again as it passes)
	brush:  i32,
	stroke: bool, // a paint stroke is in progress (undo recorded)
	last:   [2]int, // the stroke's previous cell (painted to the current one in a line)
	zoom:   f32,    // the tile panel's scale (0: fit tiles to about 32 px)
	grid:   bool,   // lines between the tiles in the panel
	terrain: int,   // the terrain brush (index in the tileset's terrains)
	nameBuf: [64]u8, // a terrain name being typed in
	nameFor: int,    // the terrain nameBuf belongs to (+1; 0 none)
}

GlobalTiles: Tile_State

selected_tilemap :: proc(state: ^EditorState) -> ^e.TileMapNode {
	n := state.selectedNode
	if n == nil || n.typeId != e.TileMapNode do return nil
	return cast(^e.TileMapNode)n
}

// Inspector_TileMap: the Inspector only points at the Tile Map tab (the
// tile editing lives in the bottom panel, where there's room for it).
Inspector_TileMap :: proc(state: ^EditorState, tm: ^e.TileMapNode) {
	if !UI_SectionHeader("Tile Map") do return
	if tm.tileset == nil do UI_DimText("No tileset yet.")
	else do UI_DimText(fmt.tprintf("%s, %d x %d tiles of %d x %d px", asset_rel_editor(state, tm.tilesetPath), tm.mapSize.x, tm.mapSize.y, tm.tileSize.x, tm.tileSize.y))
	if UI_Button(fmt.tprintf("%s  Edit in Tile Map Tab", ICON_FA_TABLE_CELLS_LARGE), "insp.tile.open", {field_width() + 80, 0}) {
		bottomTabRequest = .TileMap
	}
	UI_Tooltip("The bottom panel's Tile Map tab: tileset, sizes, tools and the tiles to paint with")
}

// TileMapPanel_Render: the bottom panel's Tile Map tab - a settings row
// (tileset, tile size, map size), the tools, then the tileset's tiles laid
// out as in the image (click one to paint with it).
TileMapPanel_Render :: proc(state: ^EditorState) {
	tm := selected_tilemap(state)
	if tm == nil {
		GlobalTiles.tool = .None // (nothing to paint on)
		imgui.Dummy({0, 8})
		UI_DimText("   Select a Tile Map node to paint its tiles.")
		return
	}
	ts := &GlobalTiles
	imgui.Dummy({0, 2})
	tilemap_settings_row(state, tm)
	tilemap_tools_row(tm)
	imgui.Separator()
	if ts.layer == .Components {
		tilemap_component_palette(state, tm)
		return
	}
	if ts.layer == .Terrains {
		tilemap_terrain_palette(state, tm)
		return
	}
	if tm.tileset == nil {
		imgui.Dummy({0, 4})
		UI_DimText("   Pick a tileset image above to paint with.")
		return
	}
	// The tiles.
	if !imgui.BeginChild("##tile_palette", {0, 0}, {}, {.HorizontalScrollbar}) {
		imgui.EndChild()
		return
	}
	defer imgui.EndChild()
	cols := e.TileMapNode_Columns(tm)
	count := e.TileMapNode_TileCount(tm)
	tex := &tm.tileset.texture
	tw, th := f32(max(tm.tileSize.x, 1)), f32(max(tm.tileSize.y, 1))
	zoom := ts.zoom if ts.zoom > 0 else tile_auto_zoom(tm)
	cw, ch := tw * zoom, th * zoom
	gap: f32 = 0 if ts.grid else 2
	dl := imgui.GetWindowDrawList()
	origin := imgui.GetCursorScreenPos() + {4, 4}
	for i in 0 ..< count {
		cx, cy := i % cols, i / cols
		p := origin + {f32(cx) * (cw + gap), f32(cy) * (ch + gap)}
		imgui.SetCursorScreenPos(p)
		imgui.PushIDInt(c.int(i))
		if imgui.InvisibleButton("##tile", {cw, ch}) {
			if !TileAnimEditor_TakeClick(state, tm.tilesetPath, i32(i)) { // (adding frames: tile_anim_editor.odin)
				ts.brush = i32(i)
				if ts.tool == .None || ts.tool == .Erase do ts.tool = .Paint
			}
		}
		hovered := imgui.IsItemHovered()
		if hovered do imgui.SetItemTooltip("Tile %d  (column %d, row %d)", c.int(i), c.int(cx), c.int(cy))
		Drive_Item(fmt.tprintf("tile.palette:%d", i))
		imgui.PopID()
		u0 := [2]f32{f32(cx) * tw / f32(tex.width), f32(cy) * th / f32(tex.height)}
		u1 := u0 + {tw / f32(tex.width), th / f32(tex.height)}
		imgui.DrawList_AddRectFilled(dl, p, p + {cw, ch}, col_u32({0, 0, 0, 0.25})) // (behind transparent pixels)
		imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)tex, p, p + {cw, ch}, u0, u1)
		if ts.grid do imgui.DrawList_AddRect(dl, p, p + {cw, ch}, col_u32({1, 1, 1, 0.12}))
		if hovered do imgui.DrawList_AddRect(dl, p, p + {cw, ch}, col_u32({1, 1, 1, 0.7}), 0, {}, 1)
		if ts.brush == i32(i) {
			imgui.DrawList_AddRect(dl, p - 1, p + {cw, ch} + 1, col_u32(UI_ACCENT), 0, {}, 2)
		}
		if TileAnimEditor_Badge(state, tm.tilesetPath, i32(i)) {
			// (An animated tile: a film corner.)
			imgui.DrawList_AddTriangleFilled(dl, p + {cw - 12, 0}, p + {cw, 0}, p + {cw, 12}, col_u32(UI_ACCENT))
		}
	}
	// (The scroll area: the whole grid plus a margin.)
	rows := (count + cols - 1) / max(cols, 1)
	imgui.SetCursorScreenPos(origin + {f32(cols) * (cw + gap), f32(rows) * (ch + gap)})
	imgui.Dummy({4, 4})
}

// tile_auto_zoom: a scale that shows tiles at about 32 px.
@(private = "file")
tile_auto_zoom :: proc(tm: ^e.TileMapNode) -> f32 {
	s := f32(max(tm.tileSize.x, tm.tileSize.y, 1))
	return clamp(32 / s, 0.25, 8)
}

// tilemap_settings_row: Tileset, Tile Size (x, y), Map Size (x, y) on one line.
@(private = "file")
tilemap_settings_row :: proc(state: ^EditorState, tm: ^e.TileMapNode) {
	label :: proc(text: string) {
		imgui.AlignTextToFramePadding()
		UI_DimText(text)
		imgui.SameLine(0, 6)
	}
	label("Tileset")
	imgui.SetNextItemWidth(220)
	textures := Editor_ListProjectFiles(state, "", TEXTURE_EXTS)
	current := asset_rel_editor(state, tm.tilesetPath)
	if path, ok := asset_picker("tile.tileset", current, textures, allowNone = true); ok && path != current {
		Editor_RecordUndo(state, "Set tileset")
		e.TileMapNode_SetTileset(tm, path, &state.game.gameContext)
	}
	UI_Tooltip("The image the tiles are cut from (a grid of Tile Size cells)")
	imgui.SameLine(0, UI_SPACE * 2)
	label("Tile Size")
	for k in 0 ..< 2 {
		if k == 1 do imgui.SameLine(0, 4)
		v := c.int(tm.tileSize[k])
		imgui.SetNextItemWidth(56)
		if imgui.DragInt(fmt.ctprintf("##tilesize%d", k), &v, 0.2, 1, 512, "x %d" if k == 0 else "y %d") {
			tm.tileSize[k] = int(max(v, 1))
			e.TileMapNode_Layout(tm)
		}
		undo_on_activate(state, "Tile size")
		Drive_Item(fmt.tprintf("tile.size-%s", "x" if k == 0 else "y"))
	}
	imgui.SameLine(0, UI_SPACE * 2)
	label("Map Size")
	for k in 0 ..< 2 {
		if k == 1 do imgui.SameLine(0, 4)
		v := c.int(tm.mapSize[k])
		imgui.SetNextItemWidth(64)
		if imgui.DragInt(fmt.ctprintf("##mapsize%d", k), &v, 0.2, 1, 1024, "x %d" if k == 0 else "y %d") {
			tm.mapSize[k] = int(max(v, 1))
			e.TileMapNode_Layout(tm)
		}
		undo_on_activate(state, "Map size")
		Drive_Item(fmt.tprintf("tile.map-%s", "w" if k == 0 else "h"))
	}
	UI_Tooltip("The map in cells: columns, rows")
	// The grid (#278): its shape, the cell, which rows are shifted - on
	// this line when there's room, else the next.
	room := imgui.GetWindowPos().x + imgui.GetWindowWidth() - imgui.GetItemRectMax().x
	if room > 420 do imgui.SameLine(0, UI_SPACE * 2)
	label("Grid")
	imgui.SetNextItemWidth(110)
	if imgui.BeginCombo("##tile.layout", fmt.ctprintf("%s", TILEMAP_LAYOUT_NAMES[tm.layout])) {
		for l in e.TileMap_Layout {
			if imgui.Selectable(fmt.ctprintf("%s", TILEMAP_LAYOUT_NAMES[l]), l == tm.layout) && l != tm.layout {
				Editor_RecordUndo(state, "Tile map grid")
				tm.layout = l
				// (A diamond / hex grid usually wants a cell half as tall as the tile.)
				if l != .Square && tm.cellSize == {} do tm.cellSize = {f32(tm.tileSize.x), f32(max(tm.tileSize.y / 2, 1))}
				e.TileMapNode_Changed(tm)
			}
			Drive_Item(fmt.tprintf("pick:%s", TILEMAP_LAYOUT_NAMES[l]))
		}
		imgui.EndCombo()
	}
	Drive_Item("tile.layout")
	UI_Tooltip("The cells' shape: Square; Isometric (diamonds on a turned grid); Staggered (diamonds in shifted rows); Hex with a point or a flat side on top")
	cell := e.TileMapNode_CellSize(tm)
	imgui.SameLine(0, UI_SPACE)
	label("Cell")
	for k in 0 ..< 2 {
		if k == 1 do imgui.SameLine(0, 4)
		v := c.int(cell[k])
		imgui.SetNextItemWidth(56)
		if imgui.DragInt(fmt.ctprintf("##cellsize%d", k), &v, 0.2, 1, 1024, "x %d" if k == 0 else "y %d") {
			tm.cellSize = cell
			tm.cellSize[k] = f32(max(v, 1))
			e.TileMapNode_Changed(tm)
		}
		undo_on_activate(state, "Cell size")
		Drive_Item(fmt.tprintf("tile.cell-%s", "x" if k == 0 else "y"))
	}
	UI_Tooltip("The grid's cell in pixels. Tiles taller than it (walls, blocks) stand on their cell")
	if tm.layout != .Square && tm.layout != .Isometric {
		imgui.SameLine(0, UI_SPACE)
		odd := tm.stagger == .Odd
		if imgui.Checkbox("Odd shifted##tile.stagger", &odd) {
			Editor_RecordUndo(state, "Tile map stagger")
			tm.stagger = .Odd if odd else .Even
			e.TileMapNode_Changed(tm)
		}
		Drive_Item("tile.stagger")
		UI_Tooltip("On: the odd rows (Hex Flat: columns) are the shifted ones. Off: the even ones")
	}
}

TILEMAP_LAYOUT_NAMES := [e.TileMap_Layout]string {
	.Square    = "Square",
	.Isometric = "Isometric",
	.Staggered = "Staggered",
	.HexPointy = "Hex (pointy)",
	.HexFlat   = "Hex (flat)",
}

// draw_cell_outline: a cell's outline in the viewport (any grid).
@(private = "file")
draw_cell_outline :: proc(state: ^EditorState, drawList: ^imgui.DrawList, tm: ^e.TileMapNode, cell: [2]int, col: imgui.Vec4, thick: f32) {
	pts, n := e.TileMapNode_CellOutline(tm, cell)
	scr: [6]imgui.Vec2
	for i in 0 ..< n do scr[i] = Viewport_WorldToScreen(state, e.TileMapNode_LocalToWorld(tm, pts[i]))
	imgui.DrawList_AddPolyline(drawList, &scr[0], c.int(n), col_u32(col), imgui.DrawFlags_Closed, thick)
}

// draw_map_outline: the map's outline (a diamond for Isometric).
@(private = "file")
draw_map_outline :: proc(state: ^EditorState, drawList: ^imgui.DrawList, tm: ^e.TileMapNode) {
	o := e.TileMapNode_MapOutline(tm)
	scr: [4]imgui.Vec2
	for p, i in o do scr[i] = Viewport_WorldToScreen(state, p)
	imgui.DrawList_AddPolyline(drawList, &scr[0], 4, col_u32({1, 1, 1, 0.35}), imgui.DrawFlags_Closed, 1)
}

// tilemap_tools_row: the painting tools, the picked tile, the tile view's zoom and grid.
@(private = "file")
tilemap_tools_row :: proc(tm: ^e.TileMapNode) {
	ts := &GlobalTiles
	// The layer the tools work on.
	for l in Tile_Layer {
		if l != .Tiles do imgui.SameLine(0, 2)
		icon := ICON_FA_TABLE_CELLS_LARGE if l == .Tiles else ICON_FA_MOUNTAIN if l == .Terrains else ICON_FA_CUBES
		name := "Tiles" if l == .Tiles else "Terrains" if l == .Terrains else "Components"
		active := ts.layer == l // (the click below may change ts.layer: push / pop by this)
		if active do imgui.PushStyleColorImVec4(.Button, UI_ACCENT)
		if imgui.Button(fmt.ctprintf("%s  %s##tilelayer", icon, name), {0, 28}) do ts.layer = l
		if active do imgui.PopStyleColor()
		Drive_Item(fmt.tprintf("tile.layer:%s", name))
		UI_Tooltip("Paint tileset tiles" if l == .Tiles else "Paint a terrain: each cell takes its tile from its neighbours (edges and corners draw themselves)" if l == .Terrains else "Paint component instances on the grid (one per cell; Shift places one off the grid)")
	}
	imgui.SameLine(0, UI_SPACE * 2)
	tool :: proc(icon, id, tip: string, t: Tile_Tool) {
		if UI_IconButton(icon, id, tip, GlobalTiles.tool == t, 28) {
			GlobalTiles.tool = .None if GlobalTiles.tool == t else t
		}
	}
	tool(ICON_FA_PAINTBRUSH, "tile.paint", "Paint tiles (left button; right erases)", .Paint)
	imgui.SameLine(0, 2)
	tool(ICON_FA_ERASER, "tile.erase", "Erase tiles", .Erase)
	imgui.SameLine(0, 2)
	tool(ICON_FA_FILL_DRIP, "tile.fill", "Flood fill", .Fill)
	imgui.SameLine(0, UI_SPACE * 2)
	imgui.AlignTextToFramePadding()
	if ts.layer == .Components {
		n := len(e.TileMapNode_Components(tm))
		if ts.comp == "" do UI_DimText(fmt.tprintf("No component picked  -  %d on the map", n))
		else do UI_DimText(fmt.tprintf("%s  -  %d on the map", Asset_DisplayName(ts.comp), n))
		return
	}
	if ts.layer == .Terrains {
		terrains := Editor_Terrains(&GlobalEditor, tm.tilesetPath)
		if terrains != nil && ts.terrain < len(terrains.terrains) do UI_DimText(fmt.tprintf("Terrain: %s", terrains.terrains[ts.terrain].name))
		else do UI_DimText("No terrain picked")
		return
	}
	if tm.tileset != nil {
		UI_DimText(fmt.tprintf("Tile %d of %d", ts.brush, e.TileMapNode_TileCount(tm)))
		imgui.SameLine(0, 6)
		if UI_IconButton(ICON_FA_FILM, "tile.animate", "Animate the picked tile: its frames and how long each shows (every Tile Map on this tileset plays it)", size = 28) {
			TileAnimEditor_Open(&GlobalEditor, tm.tilesetPath, ts.brush)
		}
	} else {
		UI_DimText(fmt.tprintf("Tile %d", ts.brush))
	}
	if tm.tileset == nil do return
	// (Right side: the tile view.)
	imgui.SameLine(0, UI_SPACE * 2)
	zoom := ts.zoom if ts.zoom > 0 else tile_auto_zoom(tm)
	if UI_IconButton(ICON_FA_MINUS, "tile.zoom-out", "Smaller tiles", size = 28) do ts.zoom = max(zoom / 1.25, 0.25)
	imgui.SameLine(0, 2)
	imgui.AlignTextToFramePadding()
	UI_DimText(fmt.tprintf("%d%%", int(zoom * 100 + 0.5)))
	Drive_Item("tile.zoom")
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_PLUS, "tile.zoom-in", "Bigger tiles", size = 28) do ts.zoom = min(zoom * 1.25, 8)
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_BORDER_ALL, "tile.grid", "Grid: the tiles touching, with lines between (off: spaced apart)", ts.grid, 28) do ts.grid = !ts.grid
}

// tilemap_component_palette: the project's components as cards (a picture
// from the first image it uses, or its icon); click one to paint with it.
@(private = "file")
tilemap_component_palette :: proc(state: ^EditorState, tm: ^e.TileMapNode) {
	ts := &GlobalTiles
	files := Editor_ListProjectFiles(state, "", {".component.json"})
	if len(files) == 0 {
		imgui.Dummy({0, 4})
		UI_DimText("   No components in the project yet: select nodes and use Save as Component, then paint them here.")
		return
	}
	if !imgui.BeginChild("##tile_components", {0, 0}, {}, {}) {
		imgui.EndChild()
		return
	}
	defer imgui.EndChild()
	CARD :: 84
	dl := imgui.GetWindowDrawList()
	perRow := max(int((imgui.GetContentRegionAvail().x - 4) / (CARD + 6)), 1)
	imgui.Dummy({0, 2})
	for f, i in files {
		if i % perRow != 0 do imgui.SameLine(0, 6)
		else do imgui.SetCursorPosX(imgui.GetCursorPosX() + 4)
		picked := ts.comp == f
		if imgui.Selectable(fmt.ctprintf("##comp_%s", f), picked, {}, {CARD, CARD + 16}) {
			delete(ts.comp)
			ts.comp = strings.clone(f)
			if ts.tool == .None || ts.tool == .Erase do ts.tool = .Paint
		}
		Drive_Item(fmt.tprintf("tile.comp:%s", f))
		UI_Tooltip(fmt.tprintf("%s - click, then paint it on the map (Shift: off the grid)", f))
		mn, mx := imgui.GetItemRectMin(), imgui.GetItemRectMax()
		box := [2]f32{CARD - 12, CARD - 12}
		origin := [2]f32{mn.x + 6, mn.y + 4}
		if tex := component_picture(state, f); tex != nil {
			s := min(box.x / f32(tex.width), box.y / f32(tex.height))
			size := [2]f32{f32(tex.width), f32(tex.height)} * s
			p0 := origin + (box - size) * 0.5
			imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)tex, p0, p0 + size)
		} else {
			fs: f32 = 30
			icon := strings.clone_to_cstring(ICON_FA_CUBES, context.temp_allocator)
			w := imgui.CalcTextSize(icon).x * fs / imgui.GetFontSize()
			imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.regular, fs, {origin.x + (box.x - w) * 0.5, origin.y + (box.y - fs) * 0.5}, col_u32({0.70, 0.52, 1.0, 1}), icon)
		}
		if fp, ok := tm.compFootprints[fmt.tprintf("%s|%dx%d", f, tm.tileSize.x, tm.tileSize.y)]; ok && (fp.x > 1 || fp.y > 1) {
			tag := strings.clone_to_cstring(fmt.tprintf("%dx%d", fp.x, fp.y), context.temp_allocator)
			imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, 12, {mx.x - 26, mn.y + 3}, col_u32(UI_TEXT_DIM), tag)
		}
		clip := imgui.Vec4{mn.x + 2, mn.y, mx.x - 2, mx.y}
		label := strings.clone_to_cstring(Asset_DisplayName(f), context.temp_allocator)
		lw := imgui.CalcTextSize(label).x * 0.8
		imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, 12, {mn.x + max(2, (CARD - lw) * 0.5), mx.y - 16}, col_u32(UI_ACCENT if picked else UI_TEXT), label, nil, 0, &clip)
		if picked do imgui.DrawList_AddRect(dl, mn, mx, col_u32(UI_ACCENT), 4, {}, 2)
	}
}

// component_picture: a thumbnail for a component - the first image,
// Aseprite file or SVG its file names.
@(private = "file")
compPictures: map[string]string // component -> image (project-relative; "" = none)

@(private = "file")
component_picture :: proc(state: ^EditorState, rel: string) -> ^rl.Texture2D {
	img, known := compPictures[rel]
	if !known {
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		if data, err := os.read_entire_file_from_path(full, context.temp_allocator); err == nil {
			text := string(data)
			// (Every quoted string that names a picture, in order.)
			rest := text
			for len(rest) > 0 && img == "" {
				i := strings.index_byte(rest, '"')
				if i < 0 do break
				rest = rest[i + 1:]
				j := strings.index_byte(rest, '"')
				if j < 0 do break
				cand := rest[:j]
				rest = rest[j + 1:]
				low := strings.to_lower(cand, context.temp_allocator)
				if strings.has_suffix(low, ".png") || strings.has_suffix(low, ".jpg") || strings.has_suffix(low, ".svg") || strings.has_suffix(low, ".aseprite") || strings.has_suffix(low, ".ase") do img = cand
			}
		}
		compPictures[strings.clone(rel)] = strings.clone(img)
	}
	if img == "" do return nil
	full, _ := filepath.join({state.projectPath, img}, context.temp_allocator)
	return Asset_Thumbnail(full)
}

// tilemap_world_to_local: a world point in the map's own space.
@(private = "file")
tilemap_world_to_local :: proc(tm: ^e.TileMapNode, world: [2]f32) -> [2]f32 {
	local := world - tm.globalPosition
	rad := -tm.globalRotation * math.RAD_PER_DEG
	co, si := math.cos(rad), math.sin(rad)
	local = {local.x * co - local.y * si, local.x * si + local.y * co}
	sx := tm.globalScale.x if tm.globalScale.x != 0 else 1
	sy := tm.globalScale.y if tm.globalScale.y != 0 else 1
	return {local.x / sx, local.y / sy}
}

// draw_block: a footprint's outline in the viewport.
@(private = "file")
draw_block :: proc(state: ^EditorState, drawList: ^imgui.DrawList, tm: ^e.TileMapNode, top, size: [2]int, col: imgui.Vec4, thick: f32) {
	if tm.layout != .Square {
		draw_cell_outline(state, drawList, tm, top, col, thick) // (a cell each off square grids)
		return
	}
	p := Viewport_WorldToScreen(state, e.TileMapNode_CellCorner(tm, top))
	q := Viewport_WorldToScreen(state, e.TileMapNode_CellCorner(tm, top + size))
	imgui.DrawList_AddRect(drawList, {min(p.x, q.x), min(p.y, q.y)}, {max(p.x, q.x), max(p.y, q.y)}, col_u32(col), 0, {}, thick)
}

// tilemap_paint_components: the viewport brush on the Components layer.
@(private = "file")
tilemap_paint_components :: proc(state: ^EditorState, drawList: ^imgui.DrawList, tm: ^e.TileMapNode, mouseWorld: [2]f32) -> bool {
	ts := &GlobalTiles
	cell := e.TileMapNode_CellAt(tm, mouseWorld)
	inside := cell.x >= 0 && cell.y >= 0 && cell.x < tm.mapSize.x && cell.y < tm.mapSize.y
	offGrid := imgui.GetIO().KeyShift
	// What's on the layer, faintly; the brush's footprint under the mouse.
	for tc in e.TileMapNode_Components(tm) do draw_block(state, drawList, tm, tc.cell, tc.size, {0.70, 0.52, 1.0, 0.45}, 1)
	if inside && state.viewportHovered {
		erasing := ts.tool == .Erase || imgui.IsMouseDown(.Right)
		if erasing {
			if n := e.TileMapNode_ComponentAt(tm, cell); n != nil {
				for tc in e.TileMapNode_Components(tm) do if tc.node == n do draw_block(state, drawList, tm, tc.cell, tc.size, UI_DANGER, 2)
			} else {
				draw_block(state, drawList, tm, cell, {1, 1}, UI_DANGER, 2)
			}
		} else {
			size := [2]int{1, 1}
			if fp, ok := tm.compFootprints[fmt.tprintf("%s|%dx%d", ts.comp, tm.tileSize.x, tm.tileSize.y)]; ok do size = fp
			top := e.TileMapNode_BlockFor(cell, size)
			top = {clamp(top.x, 0, max(tm.mapSize.x - size.x, 0)), clamp(top.y, 0, max(tm.mapSize.y - size.y, 0))}
			if offGrid && ts.tool == .Paint {
				c := Viewport_WorldToScreen(state, mouseWorld)
				imgui.DrawList_AddCircle(drawList, c, 6, col_u32(UI_ACCENT), 0, 2)
			} else {
				draw_block(state, drawList, tm, top, size, UI_ACCENT, 2)
			}
		}
	}
	if !state.viewportHovered && !ts.stroke do return true
	left := imgui.IsMouseDown(.Left)
	right := imgui.IsMouseDown(.Right)
	if !left && !right {
		ts.stroke = false
		clear(&ts.placed)
		return true
	}
	if !inside do return true
	erase := right || ts.tool == .Erase
	if !erase && ts.comp == "" {
		if !ts.stroke do Editor_Log(state, .Warn, "Pick a component in the Tile Map tab to paint with")
		ts.stroke = true
		return true
	}
	first := !ts.stroke
	if first {
		Editor_RecordUndo(state, "Paint components" if !erase else "Erase components")
		ts.stroke = true
		ts.last = cell
		clear(&ts.placed)
		if left && ts.tool == .Fill {
			n := e.TileMapNode_FillComponents(tm, cell, ts.comp)
			if n >= e.TILEMAP_FILL_MAX do Editor_Log(state, .Warn, "Fill stopped at %d components", n)
			return true
		}
		// Off the grid: one, where the mouse is.
		if left && ts.tool == .Paint && offGrid {
			if n := e.TileMapNode_PlaceComponent(tm, cell, ts.comp, true, tilemap_world_to_local(tm, mouseWorld)); n != nil do append(&ts.placed, n)
			return true
		}
	}
	if ts.tool == .Fill && !right do return true
	if left && ts.tool == .Paint && offGrid do return true // (one per click)
	// Every cell from the previous one to this one.
	from := ts.last
	steps := max(abs(cell.x - from.x), abs(cell.y - from.y))
	for i in 0 ..= steps {
		if !first && i == 0 && from == cell do continue
		t := f32(i) / f32(max(steps, 1))
		p := [2]int{from.x + int(math.round(f32(cell.x - from.x) * t)), from.y + int(math.round(f32(cell.y - from.y) * t))}
		if erase {
			e.TileMapNode_RemoveComponentAt(tm, p)
			continue
		}
		// (A cell this stroke already covered keeps what it got.)
		if occ := e.TileMapNode_ComponentAt(tm, p); occ != nil {
			mine := false
			for n in ts.placed do if n == occ {mine = true; break}
			if mine do continue
		}
		if n := e.TileMapNode_PlaceComponent(tm, p, ts.comp); n != nil do append(&ts.placed, n)
	}
	ts.last = cell
	return true
}

// Viewport_TilePaint handles painting; returns true when it owns the
// mouse this frame (no picking/gizmos).
Viewport_TilePaint :: proc(state: ^EditorState, drawList: ^imgui.DrawList, mouseScreen, mouseWorld: [2]f32) -> bool {
	tm := selected_tilemap(state)
	ts := &GlobalTiles
	if tm == nil || ts.tool == .None {
		ts.stroke = false
		return false
	}
	e.TileMapNode_Layout(tm)
	if ts.layer == .Components {
		draw_map_outline(state, drawList, tm)
		return tilemap_paint_components(state, drawList, tm, mouseWorld)
	}
	// Map outline and hovered cell.
	draw_map_outline(state, drawList, tm)
	// (Tiles can go outside the map too: the map is the outline, not a limit.)
	cell := e.TileMapNode_CellAt(tm, mouseWorld)
	if state.viewportHovered {
		col := UI_DANGER if ts.tool == .Erase || imgui.IsMouseDown(.Right) else UI_ACCENT
		draw_cell_outline(state, drawList, tm, cell, col, 2)
	}
	if !state.viewportHovered && !ts.stroke do return true
	left := imgui.IsMouseDown(.Left)
	right := imgui.IsMouseDown(.Right)
	if !left && !right {
		ts.stroke = false
		return true
	}
	// The Terrains layer: the brush is a terrain.
	terrain: ^e.Tile_Terrain
	if ts.layer == .Terrains {
		terrains := Editor_Terrains(state, tm.tilesetPath)
		if terrains == nil || ts.terrain >= len(terrains.terrains) do return true
		terrain = &terrains.terrains[ts.terrain]
	}
	if !ts.stroke {
		Editor_RecordUndo(state, "Paint terrain" if terrain != nil else "Paint tiles")
		ts.stroke = true
		ts.last = cell
		if left && ts.tool == .Fill {
			if terrain != nil do e.TileMapNode_FillTerrain(tm, terrain, cell.x, cell.y)
			else do e.TileMapNode_Fill(tm, cell.x, cell.y, ts.brush)
			return true
		}
	}
	tile: i32
	switch {
	case right || ts.tool == .Erase: tile = -1
	case ts.tool == .Paint:          tile = ts.brush
	case:                            return true
	}
	// Every cell from the previous one to this one: a fast stroke (or a
	// zoomed-out view) moves more than a cell per frame.
	from := ts.last
	steps := max(abs(cell.x - from.x), abs(cell.y - from.y))
	for i in 0 ..= steps {
		t := f32(i) / f32(max(steps, 1))
		p := [2]int{from.x + int(math.round(f32(cell.x - from.x) * t)), from.y + int(math.round(f32(cell.y - from.y) * t))}
		if terrain != nil do e.TileMapNode_PaintTerrain(tm, terrain, p.x, p.y, tile >= 0)
		else do e.TileMapNode_Set(tm, p.x, p.y, tile)
	}
	ts.last = cell
	return true
}
