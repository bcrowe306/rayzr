package editor

import "core:fmt"
import "core:math"
import os "core:os"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Terrain sets (#171; engine/terrain.odin) in the editor: a tileset's
// terrains (kept in <image>.tileset.json next to it), loaded once and saved
// as they're changed; the Terrain Tiles window, where each pattern (16
// edges, 47 blob) gets its tiles; the Tile Map tab's Terrains layer (its
// palette here, its painting in tilemap_editor.odin); the generator's rules
// name terrains too (level_gen_editor.odin).
// ============================================================================

// terrainsVersion: bumped when any tileset's terrains are saved (the
// generator window reloads them, its previews follow).
terrainsVersion: int

@(private = "file")
terrainSets: map[string]^e.Tile_Terrains // by tileset image (project-relative; heap)

@(private = "file")
terrainTextures: map[string]rl.Texture2D // the Terrain Tiles window's tileset pictures

// Editor_Terrains: a tileset image's terrains (an empty set when it has
// none yet; nil: no image).
Editor_Terrains :: proc(state: ^EditorState, image: string) -> ^e.Tile_Terrains {
	if image == "" do return nil
	if ts, ok := terrainSets[image]; ok do return ts
	ts := new(e.Tile_Terrains)
	full, _ := filepath.join({state.projectPath, e.Terrain_SidecarPath(image)}, context.temp_allocator)
	data, err := os.read_entire_file(full, context.temp_allocator)
	why: string
	ts^, why = e.Terrains_Parse(data if err == nil else nil)
	if why != "" do Editor_Log(state, .Error, "%s: %s", e.Terrain_SidecarPath(image), why)
	terrainSets[strings.clone(image)] = ts
	return ts
}

// Editor_SaveTerrains writes a tileset's terrains next to its image.
Editor_SaveTerrains :: proc(state: ^EditorState, image: string) {
	ts := terrainSets[image]
	if ts == nil do return
	rel := e.Terrain_SidecarPath(image)
	if Editor_FormatBlocksSave(state, rel) do return // (from a newer Rayzr: #326)
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	if os.write_entire_file(full, transmute([]u8)e.Terrains_Serialize(ts, context.temp_allocator)) != nil {
		Editor_Log(state, .Error, "Could not save %s", rel)
		return
	}
	Editor_InvalidateProjectFiles()
	terrainsVersion += 1
}

// Editor_ForgetTerrains: read the files again when next asked (a project
// opened, files changed).
Editor_ForgetTerrains :: proc() {
	for path, ts in terrainSets {
		e.Terrains_Destroy(ts)
		free(ts)
		delete(path)
	}
	clear(&terrainSets)
	for path, tex in terrainTextures {
		if tex.id != 0 do rl.UnloadTexture(tex)
		delete(path)
	}
	clear(&terrainTextures)
}

@(private = "file")
terrain_texture :: proc(state: ^EditorState, image: string) -> ^rl.Texture2D {
	if image == "" do return nil
	if image not_in terrainTextures {
		full, _ := filepath.join({state.projectPath, image}, context.temp_allocator)
		tex := rl.LoadTexture(strings.clone_to_cstring(full, context.temp_allocator))
		if tex.id != 0 do rl.SetTextureFilter(tex, .POINT)
		terrainTextures[strings.clone(image)] = tex
	}
	tex := &terrainTextures[image]
	return tex if tex.id != 0 else nil
}

// terrain_tile_image: one tile of a tileset texture drawn at p, size s.
terrain_tile_image :: proc(dl: ^imgui.DrawList, tex: ^rl.Texture2D, tile: [2]int, t: i32, p, s: [2]f32) {
	if tex == nil || t < 0 || tile.x <= 0 || tile.y <= 0 do return
	cols := max(int(tex.width) / tile.x, 1)
	x, y := int(t) % cols * tile.x, int(t) / cols * tile.y
	if y + tile.y > int(tex.height) do return
	sz := [2]f32{f32(tex.width), f32(tex.height)}
	imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)tex, p, p + s, {f32(x), f32(y)} / sz, {f32(x + tile.x), f32(y + tile.y)} / sz)
}

// terrain_pattern_diagram: a pattern as 3x3 squares - the cell and the
// neighbours that are the terrain filled.
@(private = "file")
terrain_pattern_diagram :: proc(dl: ^imgui.DrawList, kind: e.Terrain_Kind, mask: u8, p: [2]f32, size: f32) {
	if kind == .Hex {
		// The cell and its six sides clockwise from the right (Hex Pointy;
		// on Hex Flat the same bits start at the top).
		ctr := p + size * 0.5
		r := size * 0.17
		imgui.DrawList_AddCircleFilled(dl, ctr, r, col_u32(UI_SUCCESS))
		for i in 0 ..< 6 {
			a := f32(i) * math.PI / 3
			q := ctr + [2]f32{math.cos(a), math.sin(a)} * size * 0.34
			imgui.DrawList_AddCircleFilled(dl, q, r, col_u32(UI_ACCENT if mask & (1 << uint(i)) != 0 else ui_line(0.12)))
		}
		return
	}
	c := size / 3
	on: [3][3]bool
	on[1][1] = true
	switch kind {
	case .Edges:
		on[0][1], on[1][2], on[2][1], on[1][0] = mask & 1 != 0, mask & 2 != 0, mask & 4 != 0, mask & 8 != 0
	case .Blob:
		on[0][1], on[0][2], on[1][2], on[2][2] = mask & e.TERRAIN_N != 0, mask & e.TERRAIN_NE != 0, mask & e.TERRAIN_E != 0, mask & e.TERRAIN_SE != 0
		on[2][1], on[2][0], on[1][0], on[0][0] = mask & e.TERRAIN_S != 0, mask & e.TERRAIN_SW != 0, mask & e.TERRAIN_W != 0, mask & e.TERRAIN_NW != 0
	case .Hex: // (drawn above)
	}
	for y in 0 ..< 3 do for x in 0 ..< 3 {
		mn := p + {f32(x), f32(y)} * c
		col := UI_ACCENT if on[y][x] else ui_line(0.12)
		if x == 1 && y == 1 do col = UI_SUCCESS
		imgui.DrawList_AddRectFilled(dl, mn + 0.5, mn + c - 0.5, col_u32(col))
	}
}

// --- the Terrain Tiles window ------------------------------------------------------------

@(private = "file")
terrainWin: struct {
	open:    bool,
	image:   string, // the tileset image (heap)
	tile:    [2]int, // its tile size
	index:   int,    // the terrain
	pattern: int,    // the selected pattern (index into Terrain_Patterns)
	advance: bool,   // a picked tile moves on to the next pattern
}

// TerrainEditor_Open shows the Terrain Tiles window for a tileset's terrain.
TerrainEditor_Open :: proc(image: string, tile: [2]int, index: int) {
	delete(terrainWin.image)
	terrainWin.image = strings.clone(image)
	terrainWin.tile, terrainWin.index, terrainWin.pattern = tile, index, 0
	terrainWin.open, terrainWin.advance = true, true
	imgui.SetWindowFocusStr("Terrain Tiles###TerrainTiles")
}

TerrainEditor_Shutdown :: proc() {
	delete(terrainWin.image)
	terrainWin = {}
	Editor_ForgetTerrains()
	delete(terrainSets)
	delete(terrainTextures)
}

TerrainEditor_Render :: proc(state: ^EditorState) {
	if !terrainWin.open do return
	ts := Editor_Terrains(state, terrainWin.image)
	if ts == nil || terrainWin.index < 0 || terrainWin.index >= len(ts.terrains) {
		terrainWin.open = false
		return
	}
	t := &ts.terrains[terrainWin.index]
	vp := imgui.GetMainViewport()
	imgui.SetNextWindowPos(vp.WorkPos + vp.WorkSize * 0.5, .FirstUseEver, {0.5, 0.5})
	imgui.SetNextWindowSize({min(900, vp.WorkSize.x - 40), min(600, vp.WorkSize.y - 40)}, .FirstUseEver)
	open := true
	visible := imgui.Begin(fmt.ctprintf("%s  Terrain Tiles: %s###TerrainTiles", ICON_FA_TABLE_CELLS, t.name), &open, {})
	defer imgui.End()
	PanelHelp_Mark("terrain-tiles")
	if !open do terrainWin.open = false
	if !visible do return
	Drive_Window("terrain")
	patterns := e.Terrain_Patterns(t.kind)
	terrainWin.pattern = clamp(terrainWin.pattern, 0, len(patterns) - 1)
	tex := terrain_texture(state, terrainWin.image)
	changed := false

	UI_DimTextWrapped("Click a pattern, then the tiles for it in the tileset (click again to remove one). The middle square is the cell; blue squares are neighbours of the same terrain. Several tiles for a pattern: one is picked per cell. Right-click a pattern to clear it.")
	if imgui.Checkbox("Next pattern after a pick", &terrainWin.advance) {}
	Drive_Item("terrain.advance")
	UI_Tooltip("After a tile is added, select the next pattern (quick to go through all of them)")
	imgui.SameLine(0, UI_SPACE)
	if UI_Button("Done", "terrain.done") do terrainWin.open = false
	UI_Tooltip("Close (the tiles are saved as you pick them)")
	avail := imgui.GetContentRegionAvail()

	// The patterns.
	if imgui.BeginChild("##terrain_patterns", {avail.x * 0.5, avail.y}, {.Borders}, {}) {
		dl := imgui.GetWindowDrawList()
		CARD :: [2]f32{70, 38}
		perRow := max(int(imgui.GetContentRegionAvail().x / (CARD.x + 6)), 1)
		start := imgui.GetCursorScreenPos()
		for m, i in patterns {
			p := start + {f32(i % perRow) * (CARD.x + 6), f32(i / perRow) * (CARD.y + 6)}
			imgui.SetCursorScreenPos(p)
			imgui.PushIDInt(i32(i))
			if imgui.InvisibleButton("##pat", CARD) do terrainWin.pattern = i
			if imgui.IsItemClicked(.Right) && len(t.tiles[m]) > 0 {
				clear(&t.tiles[m])
				changed = true
			}
			UI_Tooltip(fmt.tprintf("Pattern %d: %d tile(s)", m, len(t.tiles[m])))
			Drive_Item(fmt.tprintf("terrain.pattern:%d", i))
			imgui.PopID()
			sel := i == terrainWin.pattern
			imgui.DrawList_AddRectFilled(dl, p, p + CARD, col_u32(ui_accent(0.25) if sel else ui_line(0.05)), 4)
			terrain_pattern_diagram(dl, t.kind, m, p + {4, 4}, 30)
			if len(t.tiles[m]) > 0 do terrain_tile_image(dl, tex, terrainWin.tile, t.tiles[m][0], p + {36, 4}, {30, 30})
			else do imgui.DrawList_AddRect(dl, p + {36, 4}, p + {66, 34}, col_u32(ui_line(0.25)), 3)
			if len(t.tiles[m]) > 1 do imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, 11, p + {58, 24}, col_u32(UI_TEXT), fmt.ctprintf("%d", len(t.tiles[m])))
			if sel do imgui.DrawList_AddRect(dl, p, p + CARD, col_u32(UI_ACCENT), 4, imgui.DrawFlags(0), 2)
		}
		rows := (len(patterns) + perRow - 1) / perRow
		imgui.SetCursorScreenPos(start + {0, f32(rows) * (CARD.y + 6)})
		imgui.Dummy({1, 1})
	}
	imgui.EndChild()
	imgui.SameLine(0, 6)

	// The tileset.
	if imgui.BeginChild("##terrain_tileset", {0, avail.y}, {.Borders}, {.HorizontalScrollbar}) {
		if tex == nil {
			UI_DimText("Can't read the tileset image.")
		} else {
			m := patterns[terrainWin.pattern]
			tile := terrainWin.tile
			cols := max(int(tex.width) / max(tile.x, 1), 1)
			count := cols * (int(tex.height) / max(tile.y, 1))
			scale := clamp(f32(32) / f32(max(tile.x, tile.y, 1)), 0.5, 4)
			cell := [2]f32{f32(tile.x), f32(tile.y)} * scale
			p0 := imgui.GetCursorScreenPos()
			size := [2]f32{f32(tex.width), f32(tex.height)} * scale
			imgui.InvisibleButton("##terrain_img", size)
			clicked := imgui.IsItemClicked(.Left)
			dl := imgui.GetWindowDrawList()
			imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)tex, p0, p0 + size)
			for k in 0 ..< min(count, 4096) {
				mn := p0 + {f32(k % cols), f32(k / cols)} * cell
				in_pat := false
				for x in t.tiles[m] do if x == i32(k) do in_pat = true
				used := !in_pat && e.Terrain_Has(t, i32(k))
				if in_pat || used do imgui.DrawList_AddRect(dl, mn, mn + cell, col_u32(UI_ACCENT if in_pat else ui_line(0.35)), 0, imgui.DrawFlags(0), 2 if in_pat else 1)
				Drive_ItemRect(fmt.tprintf("terrain.tile:%d", k), mn, mn + cell, inWindow = true)
			}
			if clicked {
				rel := imgui.GetMousePos() - p0
				cx, cy := int(rel.x / cell.x), int(rel.y / cell.y)
				if cx >= 0 && cx < cols && cy >= 0 && cy * cols + cx < count {
					k := i32(cy * cols + cx)
					found := -1
					for x, j in t.tiles[m] do if x == k do found = j
					if found >= 0 {
						ordered_remove(&t.tiles[m], found)
					} else {
						append(&t.tiles[m], k)
						if terrainWin.advance do terrainWin.pattern = min(terrainWin.pattern + 1, len(patterns) - 1)
					}
					changed = true
				}
			}
		}
	}
	imgui.EndChild()
	if changed do Editor_SaveTerrains(state, terrainWin.image)
}

// --- the Tile Map tab's Terrains layer ---------------------------------------------------

// tilemap_terrain_palette: the tileset's terrains - pick one to paint with;
// add one, rename it, change its kind, edit its tiles, delete it.
tilemap_terrain_palette :: proc(state: ^EditorState, tm: ^e.TileMapNode) {
	ts := Editor_Terrains(state, tm.tilesetPath)
	if ts == nil || tm.tileset == nil {
		imgui.Dummy({0, 4})
		UI_DimText("   Pick a tileset image above: its terrains are kept next to it.")
		return
	}
	gt := &GlobalTiles
	if UI_Button(fmt.tprintf("%s  New Terrain", ICON_FA_PLUS), "tile.terrain-new") {
		name := "Terrain"
		for i := 2; ; i += 1 {
			if _, at := e.Terrains_Find(ts, name); at < 0 do break
			name = fmt.tprintf("Terrain %d", i)
		}
		e.Terrains_Add(ts, name)
		gt.terrain = len(ts.terrains) - 1
		Editor_SaveTerrains(state, tm.tilesetPath)
	}
	UI_Tooltip("A new terrain of this tileset (then Edit Tiles: a tile for each pattern)")
	if len(ts.terrains) == 0 {
		imgui.SameLine(0, UI_SPACE)
		imgui.AlignTextToFramePadding()
		UI_DimText("No terrains yet. A terrain picks each cell's tile from its neighbours: paint grass, its edges draw themselves.")
		return
	}
	gt.terrain = clamp(gt.terrain, 0, len(ts.terrains) - 1)
	remove := -1
	tile := tm.tileSize
	for &t, i in ts.terrains {
		imgui.PushIDInt(i32(i))
		sel := i == gt.terrain
		// A card: its full tile, its name; click to paint with it.
		p := imgui.GetCursorScreenPos()
		if imgui.InvisibleButton("##terrain", {36, 36}) {
			gt.terrain = i
			if gt.tool == .None do gt.tool = .Paint
		}
		Drive_Item(fmt.tprintf("tile.terrain:%d", i))
		dl := imgui.GetWindowDrawList()
		imgui.DrawList_AddRectFilled(dl, p, p + 36, col_u32(ui_accent(0.3) if sel else ui_line(0.08)), 4)
		terrain_tile_image(dl, &tm.tileset.texture, tile, e.Terrain_Tile(&t, e.Terrain_Full(t.kind), 0, 0), p + 2, {32, 32})
		if sel do imgui.DrawList_AddRect(dl, p, p + 36, col_u32(UI_ACCENT), 4, imgui.DrawFlags(0), 2)
		imgui.SameLine(0, 6)
		imgui.BeginGroup()
		// (The name being typed keeps its own buffer until Enter or leaving.)
		local: [64]u8
		buf := gt.nameBuf[:] if gt.nameFor == i + 1 else local[:]
		if gt.nameFor != i + 1 do copy(local[:63], t.name)
		imgui.SetNextItemWidth(160)
		entered := imgui.InputText("##name", cstring(raw_data(buf)), len(buf), {.EnterReturnsTrue})
		if imgui.IsItemActivated() {
			gt.nameBuf = local
			gt.nameFor = i + 1
		}
		if entered || imgui.IsItemDeactivatedAfterEdit() {
			name := strings.trim_space(string(cstring(raw_data(buf))))
			if name != "" && name != t.name {
				e.Terrain_Rename(ts, &t, name)
				Editor_SaveTerrains(state, tm.tilesetPath)
			}
		}
		if imgui.IsItemDeactivated() && gt.nameFor == i + 1 do gt.nameFor = 0
		Drive_Item(fmt.tprintf("tile.terrain-name:%d", i))
		imgui.SameLine(0, 4)
		kinds := []string{"Blob (47)", "Edges (16)", "Hex (64)"}
		imgui.SetNextItemWidth(110)
		if k, ch := UI_Combo(fmt.tprintf("tile.terrain-kind:%d", i), int(t.kind), kinds); ch {
			t.kind = e.Terrain_Kind(k)
			Editor_SaveTerrains(state, tm.tilesetPath)
		}
		UI_Tooltip("Blob: 47 patterns from the 8 neighbours (corners too). Edges: 16 patterns from the 4 sides. Hex: 64 patterns from a hex cell's 6 sides (for Hex grids)")
		imgui.SameLine(0, 4)
		if UI_Button(fmt.tprintf("%s  Edit Tiles", ICON_FA_TABLE_CELLS), fmt.tprintf("tile.terrain-edit:%d", i)) do TerrainEditor_Open(tm.tilesetPath, tile, i)
		imgui.SameLine(0, 4)
		if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("tile.terrain-delete:%d", i), "Delete the terrain (the tiles painted stay)", size = 26) do remove = i
		assigned := 0
		for list in t.tiles do if len(list) > 0 do assigned += 1
		UI_DimText(fmt.tprintf("%d of %d patterns have tiles", assigned, len(e.Terrain_Patterns(t.kind))))
		imgui.EndGroup()
		imgui.PopID()
	}
	if remove >= 0 {
		e.Terrains_Remove(ts, remove)
		Editor_SaveTerrains(state, tm.tilesetPath)
	}
}
