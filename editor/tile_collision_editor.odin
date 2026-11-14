package editor

import "core:c"
import "core:fmt"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"
import "core:math"

// ============================================================================
// The Tile Map tab's Collision page (engine/tile_collision.odin): pick tiles
// on the right (Shift / Cmd add), then on the left their shape (a preset
// or a polygon drawn on the tile), friction and bounce of their own, and
// Trigger (detects instead of blocking: tile_entered / tile_exited). The
// tiles show their shapes. Saved at once in the tileset's file
// (<image>.tileset.json), shared by every map on the tileset; the scene's
// maps take it straight away.
// ============================================================================

@(private = "file")
tileColl: struct {
	selected: map[i32]bool,
	image:    string, // the tileset the picks belong to (heap)
	dragging: int,    // the polygon point being dragged (-1 none)
}

@(private = "file")
TC_CANVAS :: 168 // px: the polygon editor's tile

TileCollisionPanel_Render :: proc(state: ^EditorState, tm: ^e.TileMapNode) {
	ts := Editor_Terrains(state, tm.tilesetPath)
	if ts == nil || tm.tileset == nil {
		imgui.Dummy({0, 4})
		UI_DimText("   Pick a tileset image above: its tiles' collision is kept next to it.")
		return
	}
	if tileColl.image != tm.tilesetPath {
		delete(tileColl.image)
		tileColl.image = strings.clone(tm.tilesetPath)
		clear(&tileColl.selected)
		tileColl.dragging = -1
	}
	avail := imgui.GetContentRegionAvail()
	left := min(max(avail.x * 0.3, 300), avail.x - 160)
	if imgui.BeginChild("##tilecoll_props", {left, 0}, {.Borders}) do tilecoll_props(state, tm, ts)
	imgui.EndChild()
	imgui.SameLine()
	// The polygon (one Custom tile picked): a column of its own.
	if len(tileColl.selected) == 1 {
		for t in tileColl.selected do if e.TileCollision_Get(ts, t).shape == .Custom {
			if imgui.BeginChild("##tilecoll_poly", {TC_CANVAS + 24, 0}, {.Borders}) {
				if tilecoll_polygon(tm, ts, t) do tilecoll_changed(state, tm, ts)
			}
			imgui.EndChild()
			imgui.SameLine()
		}
	}
	if imgui.BeginChild("##tilecoll_tiles", {0, 0}, {}, {.HorizontalScrollbar}) do tilecoll_tiles(state, tm, ts)
	imgui.EndChild()
}

// tilecoll_changed: saved, and the scene's maps on the tileset take it.
@(private = "file")
tilecoll_changed :: proc(state: ^EditorState, tm: ^e.TileMapNode, ts: ^e.Tile_Terrains) {
	Editor_SaveTerrains(state, tm.tilesetPath)
	if state.activeScene == nil || state.activeScene.manager == nil do return
	for n in state.activeScene.manager.nodes {
		if n == nil || n.typeId != e.TileMapNode do continue
		m := cast(^e.TileMapNode)n
		if m.tilesetPath != tm.tilesetPath || m.sidecar == nil do continue
		e.TileCollision_CopyAll(m.sidecar, ts)
		e.TileMapNode_Changed(m)
	}
}

// tilecoll_props: the picked tiles' collision.
@(private = "file")
tilecoll_props :: proc(state: ^EditorState, tm: ^e.TileMapNode, ts: ^e.Tile_Terrains) {
	n := len(tileColl.selected)
	UI_DimText("Collision")
	UI_Tooltip("How the picked tiles collide on Solid maps. Unset tiles are Full. Slopes, halves and polygons are for square grids.")
	if n == 0 {
		UI_DimText("Pick tiles on the right to set their shape (Shift or Cmd adds).")
		tilecoll_legend()
		return
	}
	first: e.Tile_Collision
	sameShape, sameFric, sameBounce, sameTrig := true, true, true, true
	k := 0
	for t in tileColl.selected {
		col := e.TileCollision_Get(ts, t)
		if k == 0 do first = col
		else {
			if col.shape != first.shape do sameShape = false
			if col.friction != first.friction do sameFric = false
			if col.bounce != first.bounce do sameBounce = false
			if col.trigger != first.trigger do sameTrig = false
		}
		k += 1
	}
	UI_DimText(fmt.tprintf("%d tile%s picked", n, "" if n == 1 else "s"))
	changed := false
	apply :: proc(ts: ^e.Tile_Terrains, f: proc(c: ^e.Tile_Collision, data: rawptr), data: rawptr) {
		for t in tileColl.selected {
			col := e.TileCollision_Get(ts, t)
			f(&col, data)
			e.TileCollision_Set(ts, t, col)
		}
	}

	// Shape.
	labels := make([]string, len(e.Tile_Shape), context.temp_allocator)
	for s, i in e.Tile_Shape do labels[i] = e.TILE_SHAPE_LABELS[s]
	imgui.AlignTextToFramePadding()
	imgui.Text("Shape")
	imgui.SameLine(90)
	imgui.SetNextItemWidth(220)
	if v, ok := UI_Combo("tilecoll.shape", int(first.shape), labels, !sameShape); ok {
		to := e.Tile_Shape(v)
		set :: proc(col: ^e.Tile_Collision, data: rawptr) {
			to := (cast(^e.Tile_Shape)data)^
			if to == .Custom && col.shape != .Custom {
				// (A polygon starts as the shape it was: then drag its corners.)
				poly := e.TileCollision_Polygon(col^)
				if len(poly) < 3 do poly = e.TileCollision_Polygon(e.TILE_COLLISION_DEFAULT)
				col.count = min(len(poly), e.TILE_CUSTOM_MAX)
				for p, i in poly[:col.count] do col.points[i] = p
			} else if to != .Custom {
				col.points = {}
				col.count = 0
			}
			col.shape = to
		}
		apply(ts, set, &to)
		changed = true
	}
	UI_Tooltip("Full: the whole cell. Halves, 45° and 22.5° slopes (a 22.5° ramp is a low then a high tile), ceilings. One-way: a platform you jump up through. Custom: a polygon you draw below.")

	// Friction / bounce of their own.
	material :: proc(ts: ^e.Tile_Terrains, label, id, tip: string, cur: f32, same: bool, mapValue: f32, isBounce: bool) -> bool {
		on := cur >= 0
		imgui.AlignTextToFramePadding()
		mixed_push(!same)
		changed := false
		if imgui.Checkbox(fmt.ctprintf("%s##%s.set", label, id), &on) {
			v := mapValue if on else -1
			Ctx :: struct {v: f32, bounce: bool}
			cx := Ctx{v, isBounce}
			set :: proc(col: ^e.Tile_Collision, data: rawptr) {
				cx := cast(^Ctx)data
				if cx.bounce do col.bounce = cx.v
				else do col.friction = cx.v
			}
			apply(ts, set, &cx)
			changed = true
		}
		mixed_pop(!same)
		Drive_Item(fmt.tprintf("%s.set", id))
		UI_Tooltip(tip)
		imgui.SameLine(90)
		if on {
			v := cur
			imgui.SetNextItemWidth(120)
			if imgui.DragFloat(fmt.ctprintf("##%s", id), &v, 0.01, 0, 2 if !isBounce else 1, MIXED_TEXT if !same else "%.2f") {
				Ctx :: struct {v: f32, bounce: bool}
				cx := Ctx{max(v, 0), isBounce}
				set :: proc(col: ^e.Tile_Collision, data: rawptr) {
					cx := cast(^Ctx)data
					if cx.bounce do col.bounce = cx.v
					else do col.friction = cx.v
				}
				apply(ts, set, &cx)
				changed = true
			}
			Drive_Item(id)
		} else {
			UI_DimText(fmt.tprintf("the map's (%.2f)", mapValue))
		}
		return changed
	}
	if material(ts, "Friction", "tilecoll.friction", "On: the picked tiles' own friction (ice 0.02, mud 1.5); off: the map's Friction", first.friction, sameFric, tm.friction, false) do changed = true
	if material(ts, "Bounce", "tilecoll.bounce", "On: the picked tiles' own bounce (a trampoline 0.9); off: the map's Bounce", first.bounce, sameBounce, tm.bounce, true) do changed = true

	// Trigger.
	trig := first.trigger
	mixed_push(!sameTrig)
	if imgui.Checkbox("Trigger##tilecoll.trigger", &trig) {
		set :: proc(col: ^e.Tile_Collision, data: rawptr) {col.trigger = (cast(^bool)data)^}
		apply(ts, set, &trig)
		changed = true
	}
	mixed_pop(!sameTrig)
	Drive_Item("tilecoll.trigger")
	UI_Tooltip("Detects instead of blocking (water, spikes, ladders): the map sends tile_entered / tile_exited {x, y, tile, other}")

	if changed do tilecoll_changed(state, tm, ts)
	imgui.Separator()
	tilecoll_legend()
}

@(private = "file")
tilecoll_legend :: proc() {
	UI_DimText("Green: solid. Yellow: one-way (top). Blue: trigger. Dot: friction / bounce of its own.")
}

// tilecoll_polygon: the custom polygon on a zoomed tile - click adds a
// corner, drag moves one, right-click removes one. Convex, up to 8.
@(private = "file")
tilecoll_polygon :: proc(tm: ^e.TileMapNode, ts: ^e.Tile_Terrains, tile: i32) -> bool {
	col := e.TileCollision_Get(ts, tile)
	UI_DimText("Polygon")
	UI_Tooltip("Click adds a corner, drag moves one, right-click removes one (3 to 8, convex)")
	dl := imgui.GetWindowDrawList()
	p := imgui.GetCursorScreenPos()
	sz := [2]f32{TC_CANVAS, TC_CANVAS}
	imgui.InvisibleButton("##tilecoll.poly", sz, {.MouseButtonLeft, .MouseButtonRight})
	Drive_Item("tilecoll.poly")
	hovered := imgui.IsItemHovered()
	terrain_tile_image(dl, &tm.tileset.texture, tm.tileSize, tile, p, sz)
	imgui.DrawList_AddRect(dl, p, p + sz, col_u32({1, 1, 1, 0.3}))
	for i in 1 ..< 4 {
		f := f32(i) / 4
		imgui.DrawList_AddLine(dl, p + {f * sz.x, 0}, p + {f * sz.x, sz.y}, col_u32({1, 1, 1, 0.08}))
		imgui.DrawList_AddLine(dl, p + {0, f * sz.y}, p + {sz.x, f * sz.y}, col_u32({1, 1, 1, 0.08}))
	}
	mouse := imgui.GetMousePos()
	unit := [2]f32{clamp((mouse.x - p.x) / sz.x, 0, 1), clamp((mouse.y - p.y) / sz.y, 0, 1)}
	// (Snapped to sixteenths of the tile: pixel art lines up.)
	unit = {f32(int(unit.x * 16 + 0.5)) / 16, f32(int(unit.y * 16 + 0.5)) / 16}
	near := -1
	for q, i in col.points[:col.count] {
		d := (q - unit) * sz
		if d.x * d.x + d.y * d.y < 64 do near = i
	}
	changed := false
	if imgui.IsItemActivated() && imgui.IsMouseDown(.Left) {
		if near >= 0 {
			tileColl.dragging = near
		} else if col.count < e.TILE_CUSTOM_MAX {
			col.points[col.count] = unit
			col.count += 1
			tilecoll_order(&col)
			changed = true
		}
	}
	if tileColl.dragging >= 0 && tileColl.dragging < col.count {
		if imgui.IsMouseDown(.Left) {
			if col.points[tileColl.dragging] != unit {
				col.points[tileColl.dragging] = unit
				changed = true
			}
		} else {
			tilecoll_order(&col)
			tileColl.dragging = -1
			changed = true
		}
	}
	if hovered && imgui.IsMouseClicked(.Right) && near >= 0 && col.count > 3 {
		for i in near ..< col.count - 1 do col.points[i] = col.points[i + 1]
		col.count -= 1
		changed = true
	}
	// The polygon.
	scr: [e.TILE_CUSTOM_MAX][2]f32
	for q, i in col.points[:col.count] do scr[i] = p + q * sz
	if col.count >= 3 do imgui.DrawList_AddConvexPolyFilled(dl, &scr[0], c.int(col.count), col_u32({0.3, 0.9, 0.5, 0.3}))
	if col.count >= 2 do imgui.DrawList_AddPolyline(dl, &scr[0], c.int(col.count), col_u32({0.3, 0.9, 0.5, 1}), imgui.DrawFlags_Closed, 2)
	for q, i in scr[:col.count] do imgui.DrawList_AddCircleFilled(dl, q, 4 if i != near else 6, col_u32(UI_ACCENT))
	convex := tilecoll_convex(col)
	if !convex {
		imgui.TextColored(UI_WARNING, "Not convex")
		UI_Tooltip("The physics uses its hull (the outer corners)")
	}
	if UI_Button(fmt.tprintf("%s  Square", ICON_FA_SQUARE), "tilecoll.poly.reset") {
		col.count = 4
		col.points[0], col.points[1], col.points[2], col.points[3] = {0, 0}, {1, 0}, {1, 1}, {0, 1}
		changed = true
	}
	UI_Tooltip("Start again from the whole cell")
	if changed do e.TileCollision_Set(ts, tile, col)
	return changed && tileColl.dragging < 0 // (saved when a drag ends, not every frame of it)
}

// tilecoll_order: the corners in order around their centre (a convex
// polygon's outline, whatever order they were added in).
@(private = "file")
tilecoll_order :: proc(col: ^e.Tile_Collision) {
	n := col.count
	if n < 3 do return
	ctr: [2]f32
	for q in col.points[:n] do ctr += q
	ctr /= f32(n)
	ang :: proc(q, ctr: [2]f32) -> f32 {return math.atan2(q.y - ctr.y, q.x - ctr.x)}
	for i in 1 ..< n do for j := i; j > 0 && ang(col.points[j], ctr) < ang(col.points[j - 1], ctr); j -= 1 {
		col.points[j], col.points[j - 1] = col.points[j - 1], col.points[j]
	}
}

@(private = "file")
tilecoll_convex :: proc(col: e.Tile_Collision) -> bool {
	n := col.count
	if n < 3 do return false
	sign := 0
	for i in 0 ..< n {
		a, b, d := col.points[i], col.points[(i + 1) % n], col.points[(i + 2) % n]
		cr := (b.x - a.x) * (d.y - b.y) - (b.y - a.y) * (d.x - b.x)
		if abs(cr) < 1e-6 do continue
		s := 1 if cr > 0 else -1
		if sign == 0 do sign = s
		else if s != sign do return false
	}
	return sign != 0
}

// tilecoll_tiles: the tileset's tiles with their shapes - click picks.
@(private = "file")
tilecoll_tiles :: proc(state: ^EditorState, tm: ^e.TileMapNode, ts: ^e.Tile_Terrains) {
	cols := e.TileMapNode_Columns(tm)
	count := e.TileMapNode_TileCount(tm)
	tw, th := f32(max(tm.tileSize.x, 1)), f32(max(tm.tileSize.y, 1))
	zoom := clamp(40 / max(tw, th), 0.5, 4)
	cw, ch := tw * zoom, th * zoom
	dl := imgui.GetWindowDrawList()
	origin := imgui.GetCursorScreenPos() + {4, 4}
	io := imgui.GetIO()
	for i in 0 ..< count {
		tile := i32(i)
		p := origin + {f32(i % max(cols, 1)) * (cw + 2), f32(i / max(cols, 1)) * (ch + 2)}
		imgui.SetCursorScreenPos(p)
		imgui.PushIDInt(c.int(i))
		if imgui.InvisibleButton("##t", {cw, ch}) {
			add := io.KeyShift || io.KeyCtrl || io.KeySuper
			if !add do clear(&tileColl.selected)
			if add && tileColl.selected[tile] do delete_key(&tileColl.selected, tile)
			else do tileColl.selected[tile] = true
			tileColl.dragging = -1
		}
		Drive_Item(fmt.tprintf("tilecoll.tile:%d", i))
		terrain_tile_image(dl, &tm.tileset.texture, tm.tileSize, tile, p, {cw, ch})
		col := e.TileCollision_Get(ts, tile)
		tilecoll_overlay(dl, col, p, {cw, ch})
		if tileColl.selected[tile] do imgui.DrawList_AddRect(dl, p, p + {cw, ch}, col_u32(UI_ACCENT), 0, {}, 2)
		if imgui.IsItemHovered() {
			lines := make([dynamic]string, context.temp_allocator)
			append(&lines, fmt.tprintf("Tile %d: %s", i, e.TILE_SHAPE_LABELS[col.shape]))
			if col.friction >= 0 do append(&lines, fmt.tprintf("friction %.2f", col.friction))
			if col.bounce >= 0 do append(&lines, fmt.tprintf("bounce %.2f", col.bounce))
			if col.trigger do append(&lines, "trigger")
			UI_Tooltip(strings.join(lines[:], "\n", context.temp_allocator))
		}
		imgui.PopID()
	}
	imgui.SetCursorScreenPos(origin + {0, f32((count + max(cols, 1) - 1) / max(cols, 1)) * (ch + 2) + 4})
	imgui.Dummy({1, 1})
}

// tilecoll_overlay: a tile's shape drawn over it.
@(private = "file")
tilecoll_overlay :: proc(dl: ^imgui.DrawList, col: e.Tile_Collision, p, sz: [2]f32) {
	if col.shape == .None do return
	tint := imgui.Vec4{0.3, 0.9, 0.5, 1} // solid
	if col.shape == .One_Way do tint = {1, 0.85, 0.3, 1}
	if col.trigger do tint = {0.35, 0.65, 1, 1}
	if col.shape == .One_Way && !col.trigger {
		imgui.DrawList_AddLine(dl, p + {1, 2}, p + {sz.x - 1, 2}, col_u32(tint), 3)
	} else if col.shape != .Full || col.trigger {
		poly := e.TileCollision_Polygon(col)
		if len(poly) >= 3 {
			scr: [e.TILE_CUSTOM_MAX][2]f32
			n := min(len(poly), e.TILE_CUSTOM_MAX)
			for q, i in poly[:n] do scr[i] = p + q * sz
			imgui.DrawList_AddConvexPolyFilled(dl, &scr[0], c.int(n), col_u32({tint.x, tint.y, tint.z, 0.35}))
			imgui.DrawList_AddPolyline(dl, &scr[0], c.int(n), col_u32(tint), imgui.DrawFlags_Closed, 1.5)
		}
	}
	if col.friction >= 0 || col.bounce >= 0 do imgui.DrawList_AddCircleFilled(dl, p + {sz.x - 5, 5}, 3.5, col_u32(UI_WARNING))
}

// TileCollision_DriveQuery: tilecoll:<tile> - "shape friction bounce trigger points" (drives).
TileCollision_DriveQuery :: proc(state: ^EditorState, q: string) -> (string, bool) {
	if !strings.has_prefix(q, "tilecoll:") do return "", false
	tm := selected_tilemap(state)
	if tm == nil do return "<no tile map>", true
	ts := Editor_Terrains(state, tm.tilesetPath)
	tile := 0
	for ch in q[len("tilecoll:"):] do if ch >= '0' && ch <= '9' do tile = tile * 10 + int(ch - '0')
	col := e.TileCollision_Get(ts, i32(tile))
	return fmt.tprintf("%s %.2f %.2f %v %d", e.TILE_SHAPE_NAMES[col.shape], col.friction, col.bounce, col.trigger, col.count), true
}
