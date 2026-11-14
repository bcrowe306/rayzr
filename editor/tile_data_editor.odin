package editor

import "core:c"
import "core:fmt"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// The Tile Map tab's Data page (engine/tile_data.odin): the tileset's fields
// (name, type, default) on the left; its tiles on the right - pick one or
// more (Shift / Cmd add) and set their values. Saved at once with the
// tileset's terrains (<image>.tileset.json), so every map on the tileset
// shares them. Tiles with values of their own have a dot.
// ============================================================================

@(private = "file")
tileData: struct {
	selected: map[i32]bool, // the picked tiles
	image:    string,       // the tileset they belong to (heap)
	newName:  [64]u8,
	newType:  int,
}

TileDataPanel_Render :: proc(state: ^EditorState, tm: ^e.TileMapNode) {
	ts := Editor_Terrains(state, tm.tilesetPath)
	if ts == nil || tm.tileset == nil {
		imgui.Dummy({0, 4})
		UI_DimText("   Pick a tileset image above: its tile data is kept next to it.")
		return
	}
	if tileData.image != tm.tilesetPath {
		delete(tileData.image)
		tileData.image = strings.clone(tm.tilesetPath)
		clear(&tileData.selected)
	}
	avail := imgui.GetContentRegionAvail()
	left := min(max(avail.x * 0.42, 300), avail.x - 160)
	if imgui.BeginChild("##tiledata_fields", {left, 0}, {.Borders}) do tiledata_fields(state, tm, ts)
	imgui.EndChild()
	imgui.SameLine()
	if imgui.BeginChild("##tiledata_tiles", {0, 0}, {}, {.HorizontalScrollbar}) do tiledata_tiles(state, tm, ts)
	imgui.EndChild()
}

// tiledata_fields: the fields, then the picked tiles' values.
@(private = "file")
tiledata_fields :: proc(state: ^EditorState, tm: ^e.TileMapNode, ts: ^e.Tile_Terrains) {
	changed := false
	UI_DimText("Fields")
	UI_Tooltip("The values this tileset's tiles can carry. Scripts read them: map:tilemap_get_data(x, y, \"health\")")
	types := []string{"Number", "Bool", "String"}
	remove := ""
	for &f, i in ts.fields {
		imgui.PushIDInt(c.int(i))
		buf: [64]u8
		copy(buf[:63], f.name)
		imgui.SetNextItemWidth(110)
		if imgui.InputText("##name", cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue}) {
			to := strings.trim_space(string(cstring(raw_data(buf[:]))))
			if to != f.name && e.TileData_RenameField(ts, f.name, to) do changed = true
		}
		Drive_Item(fmt.tprintf("tiledata.field:%d.name", i))
		UI_Tooltip("Its name (Enter renames it, and every tile's value of it)")
		imgui.SameLine(0, 4)
		UI_DimText(types[int(f.type)])
		imgui.SameLine(0, 4)
		if tiledata_value_widget(fmt.tprintf("tiledata.field:%d.default", i), f.type, &f.default, 120, false) {
			e.TileData_SetDefault(ts, f.name, f.default)
			changed = true
		}
		UI_Tooltip("Its default: the value of tiles that don't set their own")
		imgui.SameLine(0, 4)
		if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("tiledata.field:%d.remove", i), "Remove the field (and every tile's value of it)", size = 24) do remove = f.name
		imgui.PopID()
	}
	if remove != "" {
		e.TileData_RemoveField(ts, strings.clone(remove, context.temp_allocator))
		changed = true
	}
	// A new field.
	imgui.SetNextItemWidth(110)
	imgui.InputTextWithHint("##tiledata_new", "new field", cstring(raw_data(tileData.newName[:])), len(tileData.newName))
	Drive_Item("tiledata.new-name")
	imgui.SameLine(0, 4)
	imgui.SetNextItemWidth(80)
	if v, ok := UI_Combo("tiledata.new-type", tileData.newType, types); ok do tileData.newType = v
	imgui.SameLine(0, 4)
	name := strings.trim_space(string(cstring(raw_data(tileData.newName[:]))))
	if name == "" do imgui.BeginDisabled()
	if UI_Button(fmt.tprintf("%s  Add Field", ICON_FA_PLUS), "tiledata.add") {
		if e.TileData_AddField(ts, name, e.Tile_Field_Type(tileData.newType)) {
			tileData.newName = {}
			changed = true
		} else {
			Editor_Log(state, .Warn, "Tile data: a field \"%s\" exists already", name)
		}
	}
	if name == "" do imgui.EndDisabled()
	UI_Tooltip("A field every tile of this tileset can set (health, breakable, sound...)")

	// The picked tiles' values.
	imgui.Separator()
	n := len(tileData.selected)
	if n == 0 {
		UI_DimText("Pick tiles on the right to set their values (Shift or Cmd adds).")
	} else if len(ts.fields) == 0 {
		UI_DimText("Add a field above first.")
	} else {
		UI_DimText(fmt.tprintf("%d tile%s picked", n, "" if n == 1 else "s"))
		for &f, i in ts.fields {
			imgui.PushIDInt(c.int(1000 + i))
			// Set: every picked tile sets its own; mixed when only some do.
			setCount := 0
			first, own: e.Tile_Value // (own: a value one of them sets)
			same := true
			k := 0
			for t in tileData.selected {
				if e.TileData_Has(ts, t, f.name) {
					setCount += 1
					if own == nil do own, _ = e.TileData_Get(ts, t, f.name)
				}
				v, _ := e.TileData_Get(ts, t, f.name)
				if k == 0 do first = v
				else if e.Tile_ValueText(v) != e.Tile_ValueText(first) do same = false
				k += 1
			}
			if own != nil do first = own
			mixedSet := setCount > 0 && setCount < n
			on := setCount > 0
			mixed_push(mixedSet)
			if imgui.Checkbox(fmt.ctprintf("%s##set", f.name), &on) {
				if mixedSet do on = true // (some have one: all get it)
				for t in tileData.selected {
					if on do e.TileData_Set(ts, t, f.name, first)
					else do e.TileData_Clear(ts, t, f.name)
				}
				changed = true
			}
			mixed_pop(setCount > 0 && setCount < n)
			Drive_Item(fmt.tprintf("tiledata.set:%s", f.name))
			UI_Tooltip("On: the picked tiles have their own value; off: the field's default")
			if on {
				imgui.SameLine(140)
				v := first
				if tiledata_value_widget(fmt.tprintf("tiledata.value:%s", f.name), f.type, &v, 140, !same) {
					for t in tileData.selected do e.TileData_Set(ts, t, f.name, v)
					changed = true
				}
			}
			imgui.PopID()
		}
	}
	if changed do Editor_SaveTerrains(state, tm.tilesetPath)
}

// tiledata_value_widget edits a value of a type (true when changed).
@(private = "file")
tiledata_value_widget :: proc(id: string, t: e.Tile_Field_Type, v: ^e.Tile_Value, w: f32, mixed: bool) -> bool {
	imgui.SetNextItemWidth(w)
	changed := false
	switch t {
	case .Number:
		x, _ := v.(f64)
		f := f32(x)
		if imgui.DragFloat(fmt.ctprintf("##%s", id), &f, 0.1, 0, 0, MIXED_TEXT if mixed else "%g") {
			v^ = f64(f)
			changed = true
		}
	case .Bool:
		b, _ := v.(bool)
		mixed_push(mixed)
		if imgui.Checkbox(fmt.ctprintf("##%s", id), &b) {
			v^ = b
			changed = true
		}
		mixed_pop(mixed)
	case .String:
		s, _ := v.(string)
		buf: [128]u8
		if !mixed do copy(buf[:127], s)
		if imgui.InputTextWithHint(fmt.ctprintf("##%s", id), MIXED_TEXT if mixed else "", cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue}) || imgui.IsItemDeactivatedAfterEdit() {
			v^ = strings.clone(string(cstring(raw_data(buf[:]))), context.temp_allocator)
			changed = true
		}
	}
	Drive_Item(id)
	return changed
}

// tiledata_tiles: the tileset's tiles - click picks (Shift / Cmd add).
@(private = "file")
tiledata_tiles :: proc(state: ^EditorState, tm: ^e.TileMapNode, ts: ^e.Tile_Terrains) {
	cols := e.TileMapNode_Columns(tm)
	count := e.TileMapNode_TileCount(tm)
	tw, th := f32(max(tm.tileSize.x, 1)), f32(max(tm.tileSize.y, 1))
	zoom := clamp(36 / max(tw, th), 0.5, 4)
	cw, ch := tw * zoom, th * zoom
	dl := imgui.GetWindowDrawList()
	origin := imgui.GetCursorScreenPos() + {4, 4}
	io := imgui.GetIO()
	for i in 0 ..< count {
		tile := i32(i)
		p := origin + {f32(i % cols) * (cw + 2), f32(i / cols) * (ch + 2)}
		imgui.SetCursorScreenPos(p)
		imgui.PushIDInt(c.int(i))
		if imgui.InvisibleButton("##t", {cw, ch}) {
			add := io.KeyShift || io.KeyCtrl || io.KeySuper
			if !add do clear(&tileData.selected)
			if add && tileData.selected[tile] do delete_key(&tileData.selected, tile)
			else do tileData.selected[tile] = true
		}
		Drive_Item(fmt.tprintf("tiledata.tile:%d", i))
		terrain_tile_image(dl, &tm.tileset.texture, tm.tileSize, tile, p, {cw, ch})
		if tileData.selected[tile] do imgui.DrawList_AddRect(dl, p, p + {cw, ch}, col_u32(UI_ACCENT), 0, {}, 2)
		if vals, has := ts.data[tile]; has && len(vals) > 0 {
			// A dot: values of its own.
			imgui.DrawList_AddCircleFilled(dl, p + {cw - 5, 5}, 3.5, col_u32(UI_WARNING))
		}
		if imgui.IsItemHovered() {
			lines := make([dynamic]string, context.temp_allocator)
			append(&lines, fmt.tprintf("Tile %d", i))
			for f in ts.fields {
				v, _ := e.TileData_Get(ts, tile, f.name)
				append(&lines, fmt.tprintf("%s: %s%s", f.name, e.Tile_ValueText(v), "" if e.TileData_Has(ts, tile, f.name) else " (default)"))
			}
			UI_Tooltip(strings.join(lines[:], "\n", context.temp_allocator))
		}
		imgui.PopID()
	}
	imgui.SetCursorScreenPos(origin + {0, f32((count + cols - 1) / max(cols, 1)) * (ch + 2) + 4})
	imgui.Dummy({1, 1})
}

// TileData_DriveQuery: tiledata:<tile>.<field> - a tile's value (drives).
TileData_DriveQuery :: proc(state: ^EditorState, q: string) -> (string, bool) {
	if !strings.has_prefix(q, "tiledata:") do return "", false
	tm := selected_tilemap(state)
	if tm == nil do return "<no tile map>", true
	ts := Editor_Terrains(state, tm.tilesetPath)
	body := q[len("tiledata:"):]
	dot := strings.index_byte(body, '.')
	if dot < 0 do return fmt.tprint(len(ts.fields) if ts != nil else 0), true
	tile := 0
	for ch in body[:dot] do tile = tile * 10 + int(ch - '0')
	v, ok := e.TileData_Get(ts, i32(tile), body[dot + 1:])
	if !ok do return "<no field>", true
	return e.Tile_ValueText(v), true
}
