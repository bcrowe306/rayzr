package editor

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Level editor canvas: draws the active world's levels (the active one on
// top, the others dimmed) and runs the tools on the active layer.
//
//   IntGrid  Brush / Rectangle / Erase / Fill / Pick; right button erases
//   Tiles    the palette's stamp (with flips); same tools
//   Entities Brush places the picked entity, Select moves / resizes,
//            right click / Delete removes
//   Any      Move Levels drags levels in the world; a click in another level
//            makes it active; middle drag / Space+drag pans, wheel zooms
//
// Every stroke is one undo step (Ldtk_Doc_BeginCells / EndCells); auto
// tiles follow each painted cell (Ldtk_Doc_ApplyRules).
// ============================================================================

LevelCanvas_SetZoom :: proc(z: f32) {
	GlobalLevel.zoom = clamp(z, 0.1, 16)
}

@(private = "file")
to_screen :: proc(w: [2]f32) -> [2]f32 {
	L := &GlobalLevel
	return L.canvasMin + (w - L.cam) * L.zoom + L.canvasSize * 0.5
}

@(private = "file")
to_world :: proc(s: [2]f32) -> [2]f32 {
	L := &GlobalLevel
	return (s - L.canvasMin - L.canvasSize * 0.5) / L.zoom + L.cam
}

@(private = "file")
fit_level :: proc() {
	L := &GlobalLevel
	doc := L.doc
	if doc == nil || len(doc.levels) == 0 || L.canvasSize.x <= 0 do return
	p := e.Ldtk_Doc_LevelPos(doc, L.level)
	s := e.Ldtk_Doc_LevelSize(doc, L.level)
	L.cam = {f32(p.x) + f32(s.x) * 0.5, f32(p.y) + f32(s.y) * 0.5}
	z := min((L.canvasSize.x - 40) / f32(max(s.x, 1)), (L.canvasSize.y - 40) / f32(max(s.y, 1)))
	// whole steps keep pixel art crisp
	L.zoom = z >= 1 ? math.floor(z) : clamp(z, 0.1, 1)
}

col_rl :: proc(c: rl.Color, a: f32) -> rl.Color {
	return {c.r, c.g, c.b, u8(clamp(f32(c.a) * a, 0, 255))}
}

LevelCanvas_Render :: proc(state: ^EditorState) {
	L := &GlobalLevel
	imgui.PushStyleVarImVec2(.WindowPadding, {0, 0})
	defer imgui.PopStyleVar()
	defer imgui.End()
	if L.zen {
		// zen mode (Tab): the canvas over the whole Level tab
		imgui.SetNextWindowPos(L.dockPos)
		imgui.SetNextWindowSize(L.dockSize)
		if !imgui.Begin("##LevelZenCanvas", nil, {.NoTitleBar, .NoResize, .NoScrollbar, .NoCollapse, .NoDocking, .NoMove, .NoSavedSettings, .NoScrollWithMouse}) do return
	} else if !imgui.Begin(LEVEL_CANVAS_WINDOW, nil, {.NoScrollbar, .NoScrollWithMouse}) do return
	driveNoScroll = true
	defer driveNoScroll = false
	LevelRef_Panel(LEVEL_TOOL_INFO[GlobalLevel.tool].topic) // F1 over the canvas: the current tool
	avail := imgui.GetContentRegionAvail()
	w := i32(max(avail.x, 64))
	h := i32(max(avail.y, 64))
	if L.rt.id == 0 || L.rt.texture.width != w || L.rt.texture.height != h {
		if L.rt.id != 0 do rl.UnloadRenderTexture(L.rt)
		L.rt = rl.LoadRenderTexture(w, h)
	}
	cursor := imgui.GetCursorScreenPos()
	L.canvasMin = {cursor.x, cursor.y}
	L.canvasSize = {f32(w), f32(h)}
	if L.fitRequest {
		L.fitRequest = false
		fit_level()
	}
	canvas_draw()
	imgui.Image(transmute(imgui.TextureID)&L.rt.texture, {f32(w), f32(h)}, {0, 1}, {1, 0})
	Drive_Item("level.canvas")
	L.hovered = imgui.IsItemHovered()
	doc := L.doc
	if doc != nil && len(doc.levels) > 0 {
		// drive anchor: the active level's top-left corner (+ the layer offset)
		lp := e.Ldtk_Doc_LevelPos(doc, L.level)
		o := [2]f32{f32(lp.x), f32(lp.y)}
		if ly, _ := level_active_layer(); ly != nil {
			off := e.Ldtk_Doc_LayerOffset(ly)
			o += {f32(off.x), f32(off.y)}
		}
		so := to_screen(o)
		Drive_ItemRect("level.origin", so, so + 1, true)
		canvas_input(state)
		canvas_overlay()
	}
}

// ----------------------------------------------------------------------------
// Drawing
// ----------------------------------------------------------------------------

@(private = "file")
canvas_draw :: proc() {
	L := &GlobalLevel
	doc := L.doc
	rl.BeginTextureMode(L.rt)
	defer rl.EndTextureMode()
	bg := doc != nil ? e.Ldtk_ParseHexColor(e.LdtkJson_Str(doc.root, "bgColor", "#40465B")) : rl.Color{23, 26, 33, 255}
	rl.ClearBackground(bg)
	if doc == nil || len(doc.levels) == 0 do return
	cam := rl.Camera2D{offset = L.canvasSize * 0.5, target = L.cam, zoom = L.zoom}
	rl.BeginMode2D(cam)
	// levels of the world, by depth (the active one last at its depth)
	order := make([dynamic]int, context.temp_allocator)
	for &lv, i in doc.levels do if lv.world == L.world do append(&order, i)
	for i in 1 ..< len(order) {
		for j := i; j > 0; j -= 1 {
			a, b := order[j - 1], order[j]
			da := e.LdtkJson_Int(doc.levels[a].obj, "worldDepth")
			db := e.LdtkJson_Int(doc.levels[b].obj, "worldDepth")
			if da > db || (da == db && a == L.level) {
				order[j - 1], order[j] = b, a
			} else do break
		}
	}
	for li in order do draw_level(li, li == L.level)
	if !L.hideDetails do draw_field_geometry()
	draw_rule_preview()
	draw_level_spot()
	draw_selection()
	draw_tool_preview()
	draw_pick_hint()
	rl.EndMode2D()
}

@(private = "file")
draw_level :: proc(li: int, active: bool) {
	L := &GlobalLevel
	doc := L.doc
	lv := &doc.levels[li]
	p := e.Ldtk_Doc_LevelPos(doc, li)
	s := e.Ldtk_Doc_LevelSize(doc, li)
	origin := [2]f32{f32(p.x), f32(p.y)}
	bg := e.Ldtk_ParseHexColor(e.LdtkJson_Str(lv.obj, "__bgColor", e.LdtkJson_Str(doc.root, "defaultLevelBgColor", "#696A79")))
	rl.DrawRectangleV(origin, {f32(s.x), f32(s.y)}, bg)
	draw_level_bg(li, origin, s)
	// layers: index 0 is the top one
	#reverse for &ly, i in lv.layers {
		if !e.LdtkJson_Bool(ly.obj, "visible", true) do continue
		d := e.Ldtk_Doc_LayerDef(doc, &ly)
		// the active level's other layers: inactive opacity, parallax
		inactive := active && i != L.layer
		if inactive && d != nil && e.LdtkJson_Float(d.obj, "inactiveOpacity", 1) <= 0 do continue
		off, sc := layer_parallax(li, i)
		if off != {} || sc != 1 {
			rlgl.PushMatrix()
			rlgl.Translatef(origin.x + off.x, origin.y + off.y, 0)
			rlgl.Scalef(sc, sc, 1)
			rlgl.Translatef(-origin.x, -origin.y, 0)
		}
		draw_layer(li, i, &ly, origin, active && i == L.layer, inactive)
		if off != {} || sc != 1 do rlgl.PopMatrix()
	}
	if !active {
		// levels of another world depth (PageUp / PageDown) fade more
		otherDepth := e.LdtkJson_Int(lv.obj, "worldDepth") != e.LdtkJson_Int(doc.levels[L.level].obj, "worldDepth")
		rl.DrawRectangleV(origin, {f32(s.x), f32(s.y)}, {0, 0, 0, otherDepth ? 175 : 90})
	}
	thick := 1 / L.zoom
	rl.DrawRectangleLinesEx({origin.x, origin.y, f32(s.x), f32(s.y)}, (active ? 2 : 1) * thick, active ? rl.Color{255, 255, 255, 200} : rl.Color{0, 0, 0, 120})
}

// draw_level_bg: the background image (Level.createBgTiledTexture).
@(private = "file")
draw_level_bg :: proc(li: int, origin: [2]f32, s: [2]int) {
	L := &GlobalLevel
	lv := &L.doc.levels[li]
	rel := e.LdtkJson_Str(lv.obj, "bgRelPath")
	if rel == "" do return
	tex := level_bg_texture(rel)
	if tex.id == 0 do return
	pos, _ := e.Ldtk_BgPosOf(e.LdtkJson_Str(lv.obj, "bgPos", "Cover"))
	pivot := [2]f64{e.LdtkJson_Float(lv.obj, "bgPivotX", 0.5), e.LdtkJson_Float(lv.obj, "bgPivotY", 0.5)}
	bg := e.Ldtk_LevelBgInfo(s, {int(tex.width), int(tex.height)}, pos, pivot)
	if pos != .Repeat {
		src := rl.Rectangle{f32(bg.crop[0]), f32(bg.crop[1]), f32(bg.crop[2]), f32(bg.crop[3])}
		dst := rl.Rectangle{origin.x + f32(bg.topLeft.x), origin.y + f32(bg.topLeft.y), f32(bg.crop[2] * bg.scale.x), f32(bg.crop[3] * bg.scale.y)}
		rl.DrawTexturePro(tex, src, dst, {}, 0, rl.WHITE)
		return
	}
	// repeat the crop over the level, aligned by the pivot
	tw, th := f32(bg.crop[2]), f32(bg.crop[3])
	if tw < 1 || th < 1 do return
	nx, ny := math.ceil(f32(s.x) / tw), math.ceil(f32(s.y) / th)
	start := [2]f32{f32(pivot.x) * (f32(s.x) - nx * tw), f32(pivot.y) * (f32(s.y) - ny * th)}
	for y := start.y; y < f32(s.y); y += th {
		for x := start.x; x < f32(s.x); x += tw {
			// clip to the level
			x0, y0 := max(x, 0), max(y, 0)
			x1, y1 := min(x + tw, f32(s.x)), min(y + th, f32(s.y))
			if x1 <= x0 || y1 <= y0 do continue
			src := rl.Rectangle{f32(bg.crop[0]) + (x0 - x), f32(bg.crop[1]) + (y0 - y), x1 - x0, y1 - y0}
			rl.DrawTexturePro(tex, src, {origin.x + x0, origin.y + y0, x1 - x0, y1 - y0}, {}, 0, rl.WHITE)
		}
	}
}

@(private = "file")
draw_layer :: proc(li, layer: int, ly: ^e.Ldtk_DocLayer, origin: [2]f32, isActive: bool, inactive := false) {
	L := &GlobalLevel
	doc := L.doc
	d := e.Ldtk_Doc_LayerDef(doc, ly)
	if d == nil do return
	off := e.Ldtk_Doc_LayerOffset(ly)
	o := origin + {f32(off.x), f32(off.y)}
	opacity := d.opacity
	if inactive do opacity *= f32(e.LdtkJson_Float(d.obj, "inactiveOpacity", 1))
	if inactive && L.singleLayer do opacity *= 0.2
	ts := e.Ldtk_Doc_LayerTileset(doc, ly)
	if ts != nil {
		if tex, ok := level_texture(ts.uid); ok {
			gs := f32(ts.gridSize)
			draw :: proc(tex: rl.Texture2D, ts: ^e.Ldtk_DocTileset, t: e.Ldtk_DocTile, o: [2]f32, gs: f32, opacity: f32) {
				src := rl.Rectangle{f32(t.src.x), f32(t.src.y), gs, gs}
				if anim, ok := ts.anims[t.t]; ok {
					p := e.Ldtk_Doc_TileSrc(ts, int(e.Ldtk_TileAnimFrame(anim, rl.GetTime())))
					src.x, src.y = f32(p.x), f32(p.y)
				}
				if (t.f & 1) != 0 do src.width = -gs
				if (t.f & 2) != 0 do src.height = -gs
				dst := rl.Rectangle{o.x + f32(t.px.x), o.y + f32(t.px.y), gs, gs}
				rl.DrawTexturePro(tex, src, dst, {}, 0, {255, 255, 255, u8(clamp(f32(t.a) * opacity * 255, 0, 255))})
			}
			if !L.hideAuto do for t in ly.autoTiles do draw(tex, ts, t, o, gs, opacity)
			for t in ly.gridTiles do draw(tex, ts, t, o, gs, opacity)
		}
	}
	if d.type == .IntGrid {
		// values: full colour without a tileset, faint over the active layer's auto tiles
		alpha: f32 = ts == nil || L.hideAuto ? opacity : (isActive && L.showIntGrid ? 0.35 : 0)
		if alpha > 0 {
			g := f32(d.gridSize)
			for cy in 0 ..< ly.cHei {
				for cx in 0 ..< ly.cWid {
					v := ly.intGrid[cx + cy * ly.cWid]
					if v == 0 do continue
					iv := e.Ldtk_Doc_IntValue(d, int(v))
					c := iv != nil ? iv.color : rl.MAGENTA
					rl.DrawRectangleV(o + {f32(cx) * g, f32(cy) * g}, {g, g}, col_rl(c, alpha))
				}
			}
		}
	}
	if d.type == .Entities {
		for ent in e.LdtkJson_Arr(ly.obj, "entityInstances") {
			r := e.Ldtk_Doc_EntityRect(ent)
			draw_entity(ent, {o.x + f32(r[0]), o.y + f32(r[1]), f32(r[2]), f32(r[3])}, opacity)
		}
	}
	if isActive && L.showGrid && d.type != .Entities {
		g := f32(d.gridSize)
		lc := rl.Color{255, 255, 255, 22}
		if L.zoom * g >= 6 {
			for cx in 0 ..= ly.cWid do rl.DrawLineV(o + {f32(cx) * g, 0}, o + {f32(cx) * g, f32(ly.cHei) * g}, lc)
			for cy in 0 ..= ly.cHei do rl.DrawLineV(o + {0, f32(cy) * g}, o + {f32(ly.cWid) * g, f32(cy) * g}, lc)
		}
	}
	// the guide grid (LevelRender: every guideGridWid / Hei pixels)
	if isActive {
		s := e.Ldtk_Doc_LevelSize(doc, li)
		gc := rl.Color{255, 255, 255, 84}
		thick := 1 / L.zoom
		if gw := e.LdtkJson_Int(d.obj, "guideGridWid"); gw > 1 {
			for x := o.x; x <= origin.x + f32(s.x); x += f32(gw) {
				if x < origin.x do continue
				rl.DrawLineEx({x, max(o.y, origin.y)}, {x, origin.y + f32(s.y)}, thick, gc)
			}
		}
		if gh := e.LdtkJson_Int(d.obj, "guideGridHei"); gh > 1 {
			for y := o.y; y <= origin.y + f32(s.y); y += f32(gh) {
				if y < origin.y do continue
				rl.DrawLineEx({max(o.x, origin.x), y}, {origin.x + f32(s.x), y}, thick, gc)
			}
		}
	}
}

// layer_parallax: Camera.getParallaxOffset / LayerDef.getScale for the
// active level's inactive layers (the active layer stays put for editing).
@(private = "file")
layer_parallax :: proc(li, layer: int) -> (off: [2]f32, scale: f32) {
	L := &GlobalLevel
	doc := L.doc
	scale = 1
	if li != L.level || layer == L.layer do return
	d := e.Ldtk_Doc_LayerDef(doc, &doc.levels[li].layers[layer])
	if d == nil do return
	fx := f32(e.LdtkJson_Float(d.obj, "parallaxFactorX"))
	fy := f32(e.LdtkJson_Float(d.obj, "parallaxFactorY"))
	if fx == 0 && fy == 0 do return
	scaling := e.LdtkJson_Bool(d.obj, "parallaxScaling", true)
	p := e.Ldtk_Doc_LevelPos(doc, li)
	s := e.Ldtk_Doc_LevelSize(doc, li)
	cam := to_world(L.canvasMin + L.canvasSize * 0.5)
	lx, ly := cam.x - f32(p.x), cam.y - f32(p.y)
	off = {lx * fx + (scaling ? 0 : -f32(s.x) * 0.5 * fx), ly * fy + (scaling ? 0 : -f32(s.y) * 0.5 * fy)}
	if scaling && fx != 0 do scale = max(0.01, 1 - fx)
	return
}

// layer_origin: world position of the active layer's cell (0, 0).
@(private = "file")
layer_origin :: proc() -> [2]f32 {
	L := &GlobalLevel
	lp := e.Ldtk_Doc_LevelPos(L.doc, L.level)
	o := [2]f32{f32(lp.x), f32(lp.y)}
	if ly, _ := level_active_layer(); ly != nil {
		off := e.Ldtk_Doc_LayerOffset(ly)
		o += {f32(off.x), f32(off.y)}
	}
	return o
}

@(private = "file")
mouse_cell :: proc() -> ([2]int, bool) {
	L := &GlobalLevel
	ly, d := level_active_layer()
	if ly == nil || d == nil do return {}, false
	m := imgui.GetIO().MousePos
	local := to_world({m.x, m.y}) - layer_origin()
	g := f32(d.gridSize)
	c := [2]int{int(math.floor(local.x / g)), int(math.floor(local.y / g))}
	return c, c.x >= 0 && c.y >= 0 && c.x < ly.cWid && c.y < ly.cHei
}

@(private = "file")
draw_tool_preview :: proc() {
	L := &GlobalLevel
	if !L.hovered && !L.rectActive do return
	ly, d := level_active_layer()
	if ly == nil || d == nil || d.type == .Entities || d.type == .AutoLayer do return
	if L.tool == .Select || L.tool == .Move_Level do return
	g := f32(d.gridSize)
	o := layer_origin()
	c, _ := mouse_cell()
	thick := 1.5 / L.zoom
	col := L.tool == .Erase ? rl.Color{240, 90, 90, 230} : rl.Color{255, 220, 80, 230}
	if L.rectActive {
		a, b := L.rectStart, c
		mn := [2]int{min(a.x, b.x), min(a.y, b.y)}
		mx := [2]int{max(a.x, b.x), max(a.y, b.y)}
		if L.paintErase do col = {240, 90, 90, 230}
		rl.DrawRectangleLinesEx({o.x + f32(mn.x) * g, o.y + f32(mn.y) * g, f32(mx.x - mn.x + 1) * g, f32(mx.y - mn.y + 1) * g}, thick, col)
		return
	}
	w, h := 1, 1
	if d.type == .Tiles && L.tool == .Brush && len(L.tileSel) > 0 {
		// ghost of the stamp (random mode: the first tile)
		ts := e.Ldtk_Doc_LayerTileset(L.doc, ly)
		stamp, sw, sh := level_stamp(ts)
		if !L.tileRandom do w, h = sw, sh
		if ts != nil {
			if tex, ok := level_texture(ts.uid); ok {
				gs := f32(ts.gridSize)
				for st, k in stamp {
					if L.tileRandom && k > 0 do break
					src := e.Ldtk_Doc_TileSrc(ts, int(st.tid))
					p := L.tileRandom ? [2]int{} : st.d
					sr := rl.Rectangle{f32(src.x), f32(src.y), gs, gs}
					if (L.flips & 1) != 0 do sr.width = -gs
					if (L.flips & 2) != 0 do sr.height = -gs
					rl.DrawTexturePro(tex, sr, {o.x + f32(c.x + p.x) * g, o.y + f32(c.y + p.y) * g, gs, gs}, {}, 0, {255, 255, 255, 150})
				}
			}
		}
	}
	rl.DrawRectangleLinesEx({o.x + f32(c.x) * g, o.y + f32(c.y) * g, f32(w) * g, f32(h) * g}, thick, col)
}

// canvas_overlay: level names and the status line (screen space).
@(private = "file")
canvas_overlay :: proc() {
	L := &GlobalLevel
	doc := L.doc
	dl := imgui.GetWindowDrawList()
	if !L.hideDetails {
		for &lv, i in doc.levels {
			if lv.world != L.world do continue
			p := e.Ldtk_Doc_LevelPos(doc, i)
			sp := to_screen({f32(p.x), f32(p.y)})
			name := e.LdtkJson_Str(lv.obj, "identifier")
			imgui.DrawList_AddText(dl, {sp.x + 2, sp.y - 18}, col_u32(i == L.level ? UI_TEXT : UI_TEXT_DIM), fmt.ctprintf("%s", name))
		}
		draw_field_labels(dl)
	}
	draw_level_handles(dl)
	if L.selEntity != nil && entity_resizable(L.selEntity) {
		// resize handles (ResizeTool: the sides the definition allows)
		m := imgui.GetIO().MousePos
		for h in Level_Handle {
			if !ent_handle_active(L.selEntity, h) do continue
			mn, mx := ent_handle_rect(h)
			over := m.x >= mn.x - 2 && m.y >= mn.y - 2 && m.x < mx.x + 2 && m.y < mx.y + 2
			imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32(over || L.entHandle == h ? UI_ACCENT : UI_WARNING), 1, {})
			Drive_ItemRect(fmt.tprintf("level.entity.resize:%v", h), mn, mx, true)
			if over && L.hovered && !L.entResize {
				#partial switch h {
				case .Left, .Right: imgui.SetMouseCursor(.ResizeEW)
				case .Top, .Bottom: imgui.SetMouseCursor(.ResizeNS)
				case .TopLeft, .BottomRight: imgui.SetMouseCursor(.ResizeNWSE)
				case: imgui.SetMouseCursor(.ResizeNESW)
				}
				imgui.SetTooltip("Drag to resize (snaps to the grid; Shift: free; the pivot stays put)\n\nF1: more")
				LevelRef_Hover("palette.entities")
			}
		}
	}
	ly, d := level_active_layer()
	status := fmt.tprintf("%s  %s", e.Ldtk_Doc_LevelName(doc, L.level), d != nil ? d.identifier : "")
	if c, inside := mouse_cell(); inside && L.hovered && ly != nil && d != nil {
		status = fmt.tprintf("%s   cell %d,%d", status, c.x, c.y)
		if d.type == .IntGrid {
			v := e.Ldtk_Doc_GetIntGrid(ly, c.x, c.y)
			iv := e.Ldtk_Doc_IntValue(d, v)
			status = fmt.tprintf("%s   value %d%s", status, v, iv != nil && iv.identifier != "" ? fmt.tprintf(" (%s)", iv.identifier) : "")
		}
	}
	if d != nil && d.type == .AutoLayer do status = fmt.tprintf("%s   (auto layer: paint its source IntGrid layer)", status)
	if hint := LevelCanvas_PickHintText(); hint != "" do status = hint
	if L.spotPick do status = "Click where the new level goes (Esc or right click cancels)"
	h := imgui.GetTextLineHeight()
	pos := [2]f32{L.canvasMin.x + 8, L.canvasMin.y + L.canvasSize.y - h - 8}
	tw := imgui.CalcTextSize(fmt.ctprintf("%s", status)).x
	imgui.DrawList_AddRectFilled(dl, {pos.x - 4, pos.y - 2}, {pos.x + tw + 4, pos.y + h + 2}, col_u32({0, 0, 0, 0.55}), 3, {})
	imgui.DrawList_AddText(dl, pos, col_u32(UI_TEXT), fmt.ctprintf("%s", status))
}

@(private = "file")
entity_resizable :: proc(ent: ^e.LdtkJson) -> bool {
	ed := e.Ldtk_Doc_EntityDef(GlobalLevel.doc, e.LdtkJson_Int(ent, "defUid", -1))
	return ed != nil && (e.LdtkJson_Bool(ed.obj, "resizableX") || e.LdtkJson_Bool(ed.obj, "resizableY"))
}

// ent_handle_active: ResizeTool.isHandleActive - X-only entities get the side
// handles, Y-only ones top / bottom, both every handle.
@(private = "file")
ent_handle_active :: proc(ent: ^e.LdtkJson, h: Level_Handle) -> bool {
	ed := e.Ldtk_Doc_EntityDef(GlobalLevel.doc, e.LdtkJson_Int(ent, "defUid", -1))
	if ed == nil || h == .None do return false
	rx, ry := e.LdtkJson_Bool(ed.obj, "resizableX"), e.LdtkJson_Bool(ed.obj, "resizableY")
	#partial switch h {
	case .Left, .Right: return rx
	case .Top, .Bottom: return ry
	}
	return rx && ry
}

@(private = "file")
ent_handle_rect :: proc(h: Level_Handle) -> (mn, mx: [2]f32) {
	r, _ := selected_rect_screen()
	PAD :: 6
	HS :: 4
	c := [2]f32{(r[0] + r[2]) * 0.5, (r[1] + r[3]) * 0.5}
	at: [2]f32
	#partial switch h {
	case .Top: at = {c.x, r[1] - PAD}
	case .Bottom: at = {c.x, r[3] + PAD}
	case .Left: at = {r[0] - PAD, c.y}
	case .Right: at = {r[2] + PAD, c.y}
	case .TopLeft: at = {r[0] - PAD, r[1] - PAD}
	case .TopRight: at = {r[2] + PAD, r[1] - PAD}
	case .BottomLeft: at = {r[0] - PAD, r[3] + PAD}
	case .BottomRight: at = {r[2] + PAD, r[3] + PAD}
	}
	return at - HS, at + HS
}

// selected_rect_screen: the selected entity's box on screen (x0, y0, x1, y1).
@(private = "file")
selected_rect_screen :: proc() -> ([4]f32, bool) {
	L := &GlobalLevel
	if L.selEntity == nil do return {}, false
	r := e.Ldtk_Doc_EntityRect(L.selEntity)
	o := layer_origin_of(L.selEntityLayer)
	a := to_screen(o + {f32(r[0]), f32(r[1])})
	b := to_screen(o + {f32(r[0] + r[2]), f32(r[1] + r[3])})
	return {a.x, a.y, b.x, b.y}, true
}

// ----------------------------------------------------------------------------
// Input
// ----------------------------------------------------------------------------

@(private = "file")
canvas_input :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	io := imgui.GetIO()
	mouse := [2]f32{io.MousePos.x, io.MousePos.y}
	mw := to_world(mouse)
	// zoom around the mouse
	if L.hovered && io.MouseWheel != 0 {
		before := mw
		LevelCanvas_SetZoom(L.zoom * (1 + io.MouseWheel * 0.15))
		L.cam += before - to_world(mouse)
	}
	// pan: middle drag, or Space + left drag
	if L.hovered && (imgui.IsMouseClicked(.Middle) || (imgui.IsKeyDown(.Space) && imgui.IsMouseClicked(.Left))) do L.panning = true
	if L.panning {
		L.cam -= [2]f32{io.MouseDelta.x, io.MouseDelta.y} / L.zoom
		if !imgui.IsMouseDown(.Middle) && !imgui.IsMouseDown(.Left) do L.panning = false
		return
	}
	ly, d := level_active_layer()
	pressL := L.hovered && imgui.IsMouseClicked(.Left)
	pressR := L.hovered && imgui.IsMouseClicked(.Right)
	if levelPick.active {
		pick_input(state, pressL, pressR, mw)
		return
	}
	// picking the spot of a new level
	if L.spotPick {
		if pressR || imgui.IsKeyPressed(.Escape) {
			L.spotPick = false
			return
		}
		if pressL {
			sp := e.Ldtk_Doc_LevelSpot(doc, L.world, {f64(mw.x), f64(mw.y)}, max(e.LdtkJson_Int(doc.root, "defaultGridSize", 16), 1))
			if sp.overlaps || !sp.ok {
				Editor_Log(state, .Info, "No room there: pick an empty spot")
				return
			}
			depth := len(doc.levels) > 0 ? e.LdtkJson_Int(doc.levels[L.level].obj, "worldDepth") : 0
			e.Ldtk_Doc_Checkpoint(doc, -1, "Add Level")
			li := e.Ldtk_Doc_AddLevelAtSpot(doc, L.world, sp, depth)
			e.Ldtk_Doc_ApplyAutoLevelIdentifiers(doc, L.world)
			L.spotPick = false
			if li >= 0 {
				L.level = -1
				LevelEditor_SetLevel(li)
			}
		}
		return
	}
	if level_resize_input(state, pressL, mouse, mw) do return
	// move levels
	if L.tool == .Move_Level {
		if pressL {
			li := e.Ldtk_Doc_LevelAt(doc, L.world, {int(math.floor(mw.x)), int(math.floor(mw.y))})
			if li >= 0 {
				LevelEditor_SetLevel(li)
				p := e.Ldtk_Doc_LevelPos(doc, li)
				L.levelGrab = {int(mw.x) - p.x, int(mw.y) - p.y}
				L.levelDrag, L.levelMoved = true, false
			}
		}
		if L.levelDrag {
			snap := level_snap()
			np := [2]int{int(mw.x) - L.levelGrab.x, int(mw.y) - L.levelGrab.y}
			np = {int(math.round(f32(np.x) / f32(snap.x))) * snap.x, int(math.round(f32(np.y) / f32(snap.y))) * snap.y}
			if np != e.Ldtk_Doc_LevelPos(doc, L.level) {
				if !L.levelMoved do e.Ldtk_Doc_Checkpoint(doc, level_move_scope(), "Move Level")
				L.levelMoved = true
				e.Ldtk_Doc_MoveLevel(doc, L.level, np)
			}
			if !imgui.IsMouseDown(.Left) {
				L.levelDrag = false
				// automatic level identifiers follow the positions (WorldTool)
				if L.levelMoved do e.Ldtk_Doc_ApplyAutoLevelIdentifiers(doc, L.world)
			}
		}
		return
	}
	// a click in another level makes it active
	if (pressL || pressR) && !L.painting {
		li := e.Ldtk_Doc_LevelAt(doc, L.world, {int(math.floor(mw.x)), int(math.floor(mw.y))})
		if li >= 0 && li != L.level {
			LevelEditor_SetLevel(li)
			return
		}
	}
	if !L.painting && selection_input(state, pressL, mw) do return
	if ly == nil || d == nil do return
	if L.tool == .Select do return
	switch d.type {
	case .IntGrid, .Tiles: cells_input(state, ly, d, pressL, pressR)
	case .Entities: entities_input(state, ly, d, pressL, pressR, mw)
	case .AutoLayer:
	}
}

// ----------------------------------------------------------------------------
// Level resizing (LDtk's Rulers): handles around the active level's edges
// and corners; dragging snaps to the active layer's grid (the world grid in
// GridVania); left / top edges move the level, content keeps its place.
// ----------------------------------------------------------------------------

Level_Handle :: enum u8 {
	None,
	Top,
	Bottom,
	Left,
	Right,
	TopLeft,
	TopRight,
	BottomLeft,
	BottomRight,
}

@(private = "file")
handle_rect :: proc(h: Level_Handle) -> (mn, mx: [2]f32) {
	L := &GlobalLevel
	p := e.Ldtk_Doc_LevelPos(L.doc, L.level)
	s := e.Ldtk_Doc_LevelSize(L.doc, L.level)
	a := to_screen({f32(p.x), f32(p.y)})
	b := to_screen({f32(p.x + s.x), f32(p.y + s.y)})
	PAD :: 8
	HS :: 5
	c := (a + b) * 0.5
	at: [2]f32
	switch h {
	case .None: return
	case .Top: at = {c.x, a.y - PAD}
	case .Bottom: at = {c.x, b.y + PAD}
	case .Left: at = {a.x - PAD, c.y}
	case .Right: at = {b.x + PAD, c.y}
	case .TopLeft: at = {a.x - PAD, a.y - PAD}
	case .TopRight: at = {b.x + PAD, a.y - PAD}
	case .BottomLeft: at = {a.x - PAD, b.y + PAD}
	case .BottomRight: at = {b.x + PAD, b.y + PAD}
	}
	return at - HS, at + HS
}

@(private = "file")
handle_at :: proc(m: [2]f32) -> Level_Handle {
	for h in Level_Handle {
		if h == .None do continue
		mn, mx := handle_rect(h)
		if m.x >= mn.x - 2 && m.y >= mn.y - 2 && m.x < mx.x + 2 && m.y < mx.y + 2 do return h
	}
	return .None
}

@(private = "file")
resize_grid :: proc() -> int {
	if _, d := level_active_layer(); d != nil do return max(d.gridSize, 1)
	return max(e.LdtkJson_Int(GlobalLevel.doc.root, "defaultGridSize", 16), 1)
}

// resize_bounds: Rulers.getResizedBounds - left, top, right, bottom relative
// to the level's top-left.
@(private = "file")
resize_bounds :: proc(mw: [2]f32) -> [4]int {
	L := &GlobalLevel
	doc := L.doc
	g := resize_grid()
	s := e.Ldtk_Doc_LevelSize(doc, L.level)
	dx := int(math.floor((mw.x - L.resizeFrom.x) / f32(g))) * g
	dy := int(math.floor((mw.y - L.resizeFrom.y) / f32(g))) * g
	b := [4]int{0, 0, s.x, s.y}
	#partial switch L.resizeHandle {
	case .Left, .TopLeft, .BottomLeft: b[0] = dx
	}
	#partial switch L.resizeHandle {
	case .Top, .TopLeft, .TopRight: b[1] = dy
	}
	#partial switch L.resizeHandle {
	case .Right, .TopRight, .BottomRight: b[2] = s.x + dx
	}
	#partial switch L.resizeHandle {
	case .Bottom, .BottomLeft, .BottomRight: b[3] = s.y + dy
	}
	if LdtkJson_GridVania(doc) {
		gw := max(e.Ldtk_Doc_WorldInt(doc, L.world, "worldGridWidth", 256), 1)
		gh := max(e.Ldtk_Doc_WorldInt(doc, L.world, "worldGridHeight", 256), 1)
		b[0] = int(math.round(f32(b[0]) / f32(gw))) * gw
		b[2] = int(math.round(f32(b[2]) / f32(gw))) * gw
		b[1] = int(math.round(f32(b[1]) / f32(gh))) * gh
		b[3] = int(math.round(f32(b[3]) / f32(gh))) * gh
	}
	return b
}

@(private = "file")
level_resize_input :: proc(state: ^EditorState, pressL: bool, mouse, mw: [2]f32) -> bool {
	L := &GlobalLevel
	doc := L.doc
	if L.resizeHandle != .None {
		if !imgui.IsMouseDown(.Left) {
			b := resize_bounds(mw)
			s := e.Ldtk_Doc_LevelSize(doc, L.level)
			g := resize_grid()
			if b != {0, 0, s.x, s.y} {
				if b[2] >= b[0] + g && b[3] >= b[1] + g {
					e.Ldtk_Doc_Checkpoint(doc, -1, "Resize Level")
					n := e.Ldtk_Doc_ResizeLevelBounds(doc, L.level, b[0], b[1], b[2] - b[0], b[3] - b[1])
					e.Ldtk_Doc_ApplyAutoLevelIdentifiers(doc, L.world)
					level_clear_selection()
					if n > 0 do Editor_Log(state, .Warn, "%d entit%s outside the level deleted", n, n == 1 ? "y" : "ies")
				} else do Editor_Log(state, .Info, "A level can't be smaller than one cell")
			}
			L.resizeHandle = .None
		}
		return true
	}
	if L.painting || L.levelDrag || L.selMoving || !L.hovered do return false
	h := handle_at(mouse)
	if h == .None do return false
	#partial switch h {
	case .Left, .Right: imgui.SetMouseCursor(.ResizeEW)
	case .Top, .Bottom: imgui.SetMouseCursor(.ResizeNS)
	case .TopLeft, .BottomRight: imgui.SetMouseCursor(.ResizeNWSE)
	case: imgui.SetMouseCursor(.ResizeNESW)
	}
	imgui.SetTooltip("Drag to resize the level (snaps to the grid)\n\nF1: more")
	LevelRef_Hover("level.resize")
	if pressL {
		L.resizeHandle = h
		L.resizeFrom = mw
		return true
	}
	return true
}

@(private = "file")
draw_level_handles :: proc(dl: ^imgui.DrawList) {
	L := &GlobalLevel
	if L.painting || L.levelDrag do return
	m := imgui.GetIO().MousePos
	hover := L.hovered ? handle_at({m.x, m.y}) : .None
	for h in Level_Handle {
		if h == .None do continue
		mn, mx := handle_rect(h)
		on := h == hover || h == L.resizeHandle
		imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32(on ? UI_ACCENT : imgui.Vec4{0.85, 0.85, 0.9, 0.55}), 2, {})
		Drive_ItemRect(fmt.tprintf("level.resize:%v", h), mn, mx, true)
	}
	if L.resizeHandle == .None do return
	b := resize_bounds(to_world({m.x, m.y}))
	p := e.Ldtk_Doc_LevelPos(L.doc, L.level)
	a := to_screen({f32(p.x + b[0]), f32(p.y + b[1])})
	c := to_screen({f32(p.x + b[2]), f32(p.y + b[3])})
	g := resize_grid()
	ok := b[2] >= b[0] + g && b[3] >= b[1] + g
	col := ok ? UI_ACCENT : UI_DANGER
	imgui.DrawList_AddRectFilled(dl, a, c, col_u32({col.x, col.y, col.z, 0.12}), 0, {})
	imgui.DrawList_AddRect(dl, a, c, col_u32(col), 0, {}, 2)
	imgui.DrawList_AddText(dl, {a.x + 4, c.y + 4}, col_u32(UI_TEXT), fmt.ctprintf("%dx%d", b[2] - b[0], b[3] - b[1]))
}

// level_snap: the step levels move by (the world grid in GridVania).
@(private = "file")
level_snap :: proc() -> [2]int {
	doc := GlobalLevel.doc
	if LdtkJson_GridVania(doc) do return {max(e.Ldtk_Doc_WorldInt(doc, GlobalLevel.world, "worldGridWidth", 256), 1), max(e.Ldtk_Doc_WorldInt(doc, GlobalLevel.world, "worldGridHeight", 256), 1)}
	g := max(e.LdtkJson_Int(doc.root, "defaultGridSize", 16), 1)
	return {g, g}
}

// paint_cell applies the tool at one cell (inside a stroke).
@(private = "file")
paint_cell :: proc(ly: ^e.Ldtk_DocLayer, d: ^e.Ldtk_DocLayerDef, c: [2]int, erase: bool) {
	L := &GlobalLevel
	doc := L.doc
	if d.type == .IntGrid {
		v := erase ? 0 : L.intValue
		if e.Ldtk_Doc_SetIntGrid(doc, L.level, L.layer, c.x, c.y, v) do e.Ldtk_Doc_ApplyRules(doc, L.level, L.layer, c.x, c.y, c.x, c.y)
		return
	}
	// tiles: the stamp anchored at c, or one random tile of the selection
	if erase || len(L.tileSel) == 0 {
		if erase_tile(c) do e.Ldtk_Doc_ApplyRules(doc, L.level, L.layer, c.x, c.y, c.x, c.y)
		return
	}
	if L.tileRandom {
		if e.Ldtk_Doc_AddGridTile(doc, L.level, L.layer, c.x, c.y, random_tile(), L.flips, L.stacking) do e.Ldtk_Doc_ApplyRules(doc, L.level, L.layer, c.x, c.y, c.x, c.y)
		return
	}
	stamp, w, h := level_stamp(e.Ldtk_Doc_LayerTileset(doc, ly))
	for st in stamp do e.Ldtk_Doc_AddGridTile(doc, L.level, L.layer, c.x + st.d.x, c.y + st.d.y, int(st.tid), L.flips, L.stacking)
	e.Ldtk_Doc_ApplyRules(doc, L.level, L.layer, c.x, c.y, c.x + w - 1, c.y + h - 1)
}

// erase_tile: the whole cell, or with stacking its top tile.
@(private = "file")
erase_tile :: proc(c: [2]int) -> bool {
	L := &GlobalLevel
	if L.stacking do return e.Ldtk_Doc_RemoveTopTile(L.doc, L.level, L.layer, c.x, c.y)
	return e.Ldtk_Doc_SetTile(L.doc, L.level, L.layer, c.x, c.y, -1)
}

@(private = "file")
random_tile :: proc() -> int {
	L := &GlobalLevel
	if len(L.tileSel) == 0 do return -1
	return int(L.tileSel[rand.int_max(len(L.tileSel))])
}

// put_tile: one cell of a rectangle / fill (random mode: a random tile; a
// stamp's hole: nothing).
@(private = "file")
put_tile :: proc(x, y: int, anchor: [2]int, erase: bool) {
	L := &GlobalLevel
	if erase {
		erase_tile({x, y})
		return
	}
	tid := L.tileRandom ? random_tile() : tile_for({x, y}, anchor)
	if tid >= 0 do e.Ldtk_Doc_AddGridTile(L.doc, L.level, L.layer, x, y, tid, L.flips, L.stacking)
}

// tile_for: the stamp's tile repeating over a rectangle / fill.
@(private = "file")
tile_for :: proc(c, anchor: [2]int) -> int {
	L := &GlobalLevel
	if len(L.tileSel) == 0 do return -1
	ly, _ := level_active_layer()
	stamp, w, h := level_stamp(ly != nil ? e.Ldtk_Doc_LayerTileset(L.doc, ly) : nil)
	i := ((c.x - anchor.x) % w + w) % w
	j := ((c.y - anchor.y) % h + h) % h
	for st in stamp do if st.d == {i, j} do return int(st.tid)
	return -1
}

@(private = "file")
cells_input :: proc(state: ^EditorState, ly: ^e.Ldtk_DocLayer, d: ^e.Ldtk_DocLayerDef, pressL, pressR: bool) {
	L := &GlobalLevel
	doc := L.doc
	c, inside := mouse_cell()
	if (pressL || pressR) && L.tool == .Pick {
		if inside do pick_at(ly, d, c)
		return
	}
	if (pressL || pressR) && inside && !L.painting {
		L.paintErase = pressR || L.tool == .Erase
		tool := L.tool
		if (tool == .Brush || tool == .Erase) && imgui.GetIO().KeyShift do tool = .Rect // LDtk: Shift + drag = rectangle
		switch tool {
		case .Brush, .Erase:
			e.Ldtk_Doc_BeginCells(doc, L.level, L.layer, "Paint")
			L.painting = true
			L.lastCell = c
			paint_cell(ly, d, c, L.paintErase)
		case .Rect:
			e.Ldtk_Doc_BeginCells(doc, L.level, L.layer, "Rectangle")
			L.painting, L.rectActive = true, true
			L.rectStart = c
		case .Fill:
			e.Ldtk_Doc_BeginCells(doc, L.level, L.layer, "Fill")
			flood_fill(ly, d, c, L.paintErase)
			e.Ldtk_Doc_EndCells(doc)
		case .Pick, .Select, .Move_Level:
		}
		return
	}
	if !L.painting do return
	down := imgui.IsMouseDown(.Left) || imgui.IsMouseDown(.Right)
	if (L.tool == .Brush || L.tool == .Erase) && c != L.lastCell {
		// every cell on the line from the last one (fast strokes leave no gaps)
		a, b := L.lastCell, c
		dx, dy := abs(b.x - a.x), -abs(b.y - a.y)
		sx := a.x < b.x ? 1 : -1
		sy := a.y < b.y ? 1 : -1
		err := dx + dy
		p := a
		for {
			if p != a do paint_cell(ly, d, p, L.paintErase)
			if p == b do break
			e2 := 2 * err
			if e2 >= dy {
				err += dy
				p.x += sx
			}
			if e2 <= dx {
				err += dx
				p.y += sy
			}
		}
		L.lastCell = c
	}
	if !down {
		if L.rectActive {
			a := L.rectStart
			b := [2]int{clamp(c.x, 0, ly.cWid - 1), clamp(c.y, 0, ly.cHei - 1)}
			mn := [2]int{min(a.x, b.x), min(a.y, b.y)}
			mx := [2]int{max(a.x, b.x), max(a.y, b.y)}
			for y in mn.y ..= mx.y {
				for x in mn.x ..= mx.x {
					if d.type == .IntGrid {
						e.Ldtk_Doc_SetIntGrid(doc, L.level, L.layer, x, y, L.paintErase ? 0 : L.intValue)
					} else {
						put_tile(x, y, mn, L.paintErase)
					}
				}
			}
			e.Ldtk_Doc_ApplyRules(doc, L.level, L.layer, mn.x, mn.y, mx.x, mx.y)
			L.rectActive = false
		}
		e.Ldtk_Doc_EndCells(doc)
		L.painting = false
	}
}

@(private = "file")
pick_at :: proc(ly: ^e.Ldtk_DocLayer, d: ^e.Ldtk_DocLayerDef, c: [2]int) {
	L := &GlobalLevel
	if d.type == .IntGrid {
		if v := e.Ldtk_Doc_GetIntGrid(ly, c.x, c.y); v != 0 do L.intValue = v
		return
	}
	tiles := e.Ldtk_Doc_TilesAt(ly, c.x, c.y)
	if len(tiles) == 0 do return
	t := tiles[len(tiles) - 1]
	level_set_tile_sel({t.t})
	L.flips = t.f
	L.tool = .Brush
}

// flood_fill fills the 4-connected area of equal cells (IntGrid value, or
// top tile) from c.
@(private = "file")
flood_fill :: proc(ly: ^e.Ldtk_DocLayer, d: ^e.Ldtk_DocLayerDef, start: [2]int, erase: bool) {
	L := &GlobalLevel
	doc := L.doc
	key :: proc(ly: ^e.Ldtk_DocLayer, d: ^e.Ldtk_DocLayerDef, c: [2]int) -> int {
		if d.type == .IntGrid do return e.Ldtk_Doc_GetIntGrid(ly, c.x, c.y)
		tiles := e.Ldtk_Doc_TilesAt(ly, c.x, c.y)
		return len(tiles) > 0 ? int(tiles[len(tiles) - 1].t) : -1
	}
	target := key(ly, d, start)
	if d.type == .IntGrid && target == (erase ? 0 : L.intValue) do return
	seen := make([]bool, ly.cWid * ly.cHei, context.temp_allocator)
	stack := make([dynamic][2]int, context.temp_allocator)
	append(&stack, start)
	mn, mx := start, start
	for len(stack) > 0 {
		c := pop(&stack)
		if c.x < 0 || c.y < 0 || c.x >= ly.cWid || c.y >= ly.cHei do continue
		i := c.x + c.y * ly.cWid
		if seen[i] || key(ly, d, c) != target do continue
		seen[i] = true
		mn = {min(mn.x, c.x), min(mn.y, c.y)}
		mx = {max(mx.x, c.x), max(mx.y, c.y)}
		append(&stack, [2]int{c.x + 1, c.y}, [2]int{c.x - 1, c.y}, [2]int{c.x, c.y + 1}, [2]int{c.x, c.y - 1})
	}
	for y in mn.y ..= mx.y {
		for x in mn.x ..= mx.x {
			if !seen[x + y * ly.cWid] do continue
			if d.type == .IntGrid {
				e.Ldtk_Doc_SetIntGrid(doc, L.level, L.layer, x, y, erase ? 0 : L.intValue)
			} else {
				put_tile(x, y, start, erase)
			}
		}
	}
	e.Ldtk_Doc_ApplyRules(doc, L.level, L.layer, mn.x, mn.y, mx.x, mx.y)
}

// entities_input: the Brush places the picked entity (Shift: off the grid);
// the right button deletes the entity under the mouse. Selecting, moving and
// resizing are selection_input's.
@(private = "file")
entities_input :: proc(state: ^EditorState, ly: ^e.Ldtk_DocLayer, d: ^e.Ldtk_DocLayerDef, pressL, pressR: bool, mw: [2]f32) {
	L := &GlobalLevel
	doc := L.doc
	o := layer_origin()
	local := mw - o
	lp := [2]int{int(math.floor(local.x)), int(math.floor(local.y))}
	g := d.gridSize
	if pressR {
		if ent := e.Ldtk_Doc_EntityAt(doc, L.level, L.layer, lp); ent != nil {
			e.Ldtk_Doc_Checkpoint(doc, L.level, "Delete Entity")
			e.Ldtk_Doc_RemoveEntity(doc, L.level, L.layer, ent)
			level_sync_selection()
		}
		return
	}
	if pressL && L.tool == .Brush && L.entityDef >= 0 && lp.x >= 0 && lp.y >= 0 && lp.x < ly.cWid * g && lp.y < ly.cHei * g {
		ed := e.Ldtk_Doc_EntityDef(doc, L.entityDef)
		if ed == nil do return
		cell := [2]int{lp.x / g, lp.y / g}
		px := [2]int{cell.x * g + int(ed.pivot.x * f64(g)), cell.y * g + int(ed.pivot.y * f64(g))}
		if imgui.GetIO().KeyShift do px = lp
		e.Ldtk_Doc_Checkpoint(doc, L.level, "Add Entity")
		placed, moved := e.Ldtk_Doc_PlaceEntity(doc, L.level, L.layer, L.entityDef, px)
		if placed == nil {
			Editor_Log(state, .Info, "%s: its limit is reached (Entities tab > Max count)", ed.identifier)
			return
		}
		if moved do Editor_Log(state, .Info, "%s: its limit is reached - the last one moved here", ed.identifier)
		// it may have moved from another layer / level (the limit's scope)
		for &l, j in doc.levels[L.level].layers do for x in e.LdtkJson_Arr(l.obj, "entityInstances") do if x == placed do level_select_entity(j, placed)
	}
}

// ----------------------------------------------------------------------------
// Selection (LDtk's Selection tool: the Select tool, or Alt with any tool)
// ----------------------------------------------------------------------------

// layer_origin_of: world position of a layer's cell (0, 0) in the level.
@(private = "file")
layer_origin_of :: proc(layer: int) -> [2]f32 {
	L := &GlobalLevel
	lp := e.Ldtk_Doc_LevelPos(L.doc, L.level)
	o := [2]f32{f32(lp.x), f32(lp.y)}
	lv := &L.doc.levels[L.level]
	if layer >= 0 && layer < len(lv.layers) {
		off := e.Ldtk_Doc_LayerOffset(&lv.layers[layer])
		o += {f32(off.x), f32(off.y)}
	}
	return o
}

// element_at: the entity or the cell with a value under a world position -
// the active layer first, then the others from the top (visible ones).
@(private = "file")
element_at :: proc(mw: [2]f32) -> (cell: e.Ldtk_SelCell, ent: e.Ldtk_SelEntity, found: bool) {
	L := &GlobalLevel
	doc := L.doc
	lv := &doc.levels[L.level]
	try :: proc(doc: ^e.Ldtk_Doc, li, j: int, mw: [2]f32) -> (e.Ldtk_SelCell, e.Ldtk_SelEntity, bool) {
		ly := &doc.levels[li].layers[j]
		if !e.LdtkJson_Bool(ly.obj, "visible", true) do return {}, {}, false
		d := e.Ldtk_Doc_LayerDef(doc, ly)
		if d == nil do return {}, {}, false
		if j != GlobalLevel.layer && !e.LdtkJson_Bool(d.obj, "canSelectWhenInactive", true) do return {}, {}, false
		mw := mw
		if off, sc := layer_parallax(li, j); off != {} || sc != 1 {
			lp0 := e.Ldtk_Doc_LevelPos(doc, li)
			lo := [2]f32{f32(lp0.x), f32(lp0.y)}
			mw = lo + (mw - lo - off) / sc
		}
		o := layer_origin_of(j)
		lp := [2]int{int(math.floor(mw.x - o.x)), int(math.floor(mw.y - o.y))}
		#partial switch d.type {
		case .Entities:
			if ent := e.Ldtk_Doc_EntityAt(doc, li, j, lp); ent != nil do return {}, {j, ent}, true
		case .IntGrid:
			c := [2]int{ldtk_floor(lp.x, d.gridSize), ldtk_floor(lp.y, d.gridSize)}
			if e.Ldtk_Doc_GetIntGrid(ly, c.x, c.y) != 0 do return {j, c.x, c.y}, {}, true
		case .Tiles:
			c := [2]int{ldtk_floor(lp.x, d.gridSize), ldtk_floor(lp.y, d.gridSize)}
			if len(e.Ldtk_Doc_TilesAt(ly, c.x, c.y)) > 0 do return {j, c.x, c.y}, {}, true
		}
		return {}, {}, false
	}
	if L.layer < len(lv.layers) {
		if c, en, ok := try(doc, L.level, L.layer, mw); ok do return c, en, true
	}
	for _, j in lv.layers {
		if j == L.layer do continue
		if c, en, ok := try(doc, L.level, j, mw); ok do return c, en, true
	}
	return {}, {}, false
}

@(private = "file")
ldtk_floor :: proc(a, b: int) -> int {
	if b == 0 do return 0
	q := a / b
	if a % b != 0 && (a < 0) != (b < 0) do q -= 1
	return q
}

// over_selection: is a world position on a selected cell or entity?
@(private = "file")
over_selection :: proc(mw: [2]f32) -> bool {
	L := &GlobalLevel
	doc := L.doc
	lv := &doc.levels[L.level]
	for c in L.sel.cells {
		d := e.Ldtk_Doc_LayerDef(doc, &lv.layers[c.layer])
		if d == nil do continue
		o := layer_origin_of(c.layer)
		g := f32(d.gridSize)
		x, y := o.x + f32(c.cx) * g, o.y + f32(c.cy) * g
		if mw.x >= x && mw.y >= y && mw.x < x + g && mw.y < y + g do return true
	}
	for se in L.sel.entities {
		o := layer_origin_of(se.layer)
		r := e.Ldtk_Doc_EntityRect(se.obj)
		if mw.x >= o.x + f32(r[0]) && mw.y >= o.y + f32(r[1]) && mw.x < o.x + f32(r[0] + r[2]) && mw.y < o.y + f32(r[1] + r[3]) do return true
	}
	return false
}

// sel_delta: the drag's offset, snapped (entities alone with Shift: free).
@(private = "file")
sel_delta :: proc(mw: [2]f32) -> [2]int {
	L := &GlobalLevel
	raw := mw - L.selGrab
	g := 16
	if _, d := level_active_layer(); d != nil do g = d.gridSize
	// the cells' coarsest grid decides the step
	for c in L.sel.cells {
		if d := e.Ldtk_Doc_LayerDef(L.doc, &L.doc.levels[L.level].layers[c.layer]); d != nil do g = max(g, d.gridSize)
	}
	if len(L.sel.cells) == 0 && imgui.GetIO().KeyShift do return {int(math.round(raw.x)), int(math.round(raw.y))}
	return {int(math.round(raw.x / f32(g))) * g, int(math.round(raw.y / f32(g))) * g}
}

// LevelCanvas_PasteAt: where Cmd+V puts the clipboard's top-left - the cell
// under the mouse (the clip's place when the mouse is off the canvas).
LevelCanvas_PasteAt :: proc() -> [2]int {
	L := &GlobalLevel
	if !L.hovered do return L.clip.origin
	m := imgui.GetIO().MousePos
	lp := e.Ldtk_Doc_LevelPos(L.doc, L.level)
	w := to_world({m.x, m.y}) - {f32(lp.x), f32(lp.y)}
	g := 16
	if _, d := level_active_layer(); d != nil do g = d.gridSize
	return {ldtk_floor(int(w.x), g) * g, ldtk_floor(int(w.y), g) * g}
}

// selection_input runs the selection gestures; returns true when it took
// the mouse this frame (painting tools then don't).
@(private = "file")
selection_input :: proc(state: ^EditorState, pressL: bool, mw: [2]f32) -> bool {
	L := &GlobalLevel
	doc := L.doc
	io := imgui.GetIO()
	selectMode := L.tool == .Select || io.KeyAlt
	// resizing the selected entity by a handle (ResizeTool): the handle follows
	// the mouse, the entity grows around its pivot
	if L.entResize {
		ent := L.selEntity
		if ent == nil {
			L.entResize, L.entHandle = false, .None
			return true
		}
		ed := e.Ldtk_Doc_EntityDef(doc, e.LdtkJson_Int(ent, "defUid", -1))
		ld := e.Ldtk_Doc_LayerDef(doc, &doc.levels[L.level].layers[L.selEntityLayer])
		g := ld != nil ? ld.gridSize : 16
		o := layer_origin_of(L.selEntityLayer)
		m := [2]f64{f64(mw.x - o.x), f64(mw.y - o.y)}
		px := e.LdtkJson_Arr(ent, "px")
		pos := [2]f64{len(px) >= 2 ? px[0].num : 0, len(px) >= 2 ? px[1].num : 0}
		pv := e.LdtkJson_Arr(ent, "__pivot")
		piv := [2]f64{len(pv) >= 2 ? pv[0].num : 0, len(pv) >= 2 ? pv[1].num : 0}
		r := e.Ldtk_Doc_EntityRect(ent)
		size := [2]int{r[2], r[3]}
		side := [2]int{}
		h := L.entHandle
		#partial switch h {
		case .Left, .TopLeft, .BottomLeft:
			side.x = -1
			size.x = piv.x > 0 ? int((pos.x - m.x) / piv.x) : int(f64(r[0] + r[2]) - m.x)
		case .Right, .TopRight, .BottomRight:
			side.x = 1
			size.x = piv.x < 1 ? int((m.x - pos.x) / (1 - piv.x)) : int(m.x - f64(r[0]))
		}
		#partial switch h {
		case .Top, .TopLeft, .TopRight:
			side.y = -1
			size.y = piv.y > 0 ? int((pos.y - m.y) / piv.y) : int(f64(r[1] + r[3]) - m.y)
		case .Bottom, .BottomLeft, .BottomRight:
			side.y = 1
			size.y = piv.y < 1 ? int((m.y - pos.y) / (1 - piv.y)) : int(m.y - f64(r[1]))
		}
		// the grid (Shift: free)
		if !io.KeyShift {
			if side.x != 0 do size.x = max(int(math.round(f32(size.x) / f32(g))), 1) * g
			if side.y != 0 do size.y = max(int(math.round(f32(size.y) / f32(g))), 1) * g
		}
		if ed != nil {
			// keep the aspect ratio like ResizeTool: top / bottom drive the width,
			// the others the height
			if e.LdtkJson_Bool(ed.obj, "keepAspectRatio") && e.LdtkJson_Bool(ed.obj, "resizableX") && e.LdtkJson_Bool(ed.obj, "resizableY") && ed.size.x > 0 {
				ar := f64(ed.size.y) / f64(ed.size.x)
				if side.x == 0 do size.x = int(math.round(f64(size.y) / ar))
				else do size.y = int(math.round(f64(size.x) * ar))
			}
			lim :: proc(o: ^e.LdtkJson, key: string, v: int, isMin: bool) -> int {
				x := e.LdtkJson_Get(o, key)
				if x == nil || x.kind != .Number do return v
				return isMin ? max(v, int(x.num)) : min(v, int(x.num))
			}
			size.x = lim(ed.obj, "maxWidth", lim(ed.obj, "minWidth", size.x, true), false)
			size.y = lim(ed.obj, "maxHeight", lim(ed.obj, "minHeight", size.y, true), false)
		}
		size = {max(size.x, 1), max(size.y, 1)}
		if size.x != r[2] || size.y != r[3] {
			if !L.entMoved do e.Ldtk_Doc_Checkpoint(doc, L.level, "Resize Entity")
			L.entMoved = true
			e.Ldtk_Doc_ResizeEntityAround(doc, L.level, L.selEntityLayer, ent, size, side)
		}
		if !imgui.IsMouseDown(.Left) do L.entResize, L.entHandle = false, .None
		return true
	}
	// dragging the selection: a ghost follows, the move happens on release
	if L.selMoving {
		if !L.selMoved && linalg_len(mw - L.selGrab) * L.zoom >= 4 do L.selMoved = true
		if !imgui.IsMouseDown(.Left) {
			L.selMoving = false
			if L.selMoved {
				delta := sel_delta(mw)
				if delta != {} || L.selCopy {
					if e.Ldtk_Doc_SelectionCanMove(doc, L.level, &L.sel, delta) {
						e.Ldtk_Doc_Checkpoint(doc, L.level, L.selCopy ? "Copy Selection" : "Move Selection")
						e.Ldtk_Doc_MoveSelection(doc, L.level, &L.sel, delta, L.selCopy)
						level_sync_selection()
					} else do Editor_Log(state, .Warn, "The selection can't move by %d,%d px: its layers' grids don't line up", delta.x, delta.y)
				}
			}
		}
		return true
	}
	// rectangle selection
	if L.selRect {
		if !imgui.IsMouseDown(.Left) {
			L.selRect = false
			lp := e.Ldtk_Doc_LevelPos(doc, L.level)
			a := L.selRectStart - {f32(lp.x), f32(lp.y)}
			b := mw - {f32(lp.x), f32(lp.y)}
			mn := [2]f32{min(a.x, b.x), min(a.y, b.y)}
			mx := [2]f32{max(a.x, b.x), max(a.y, b.y)}
			r := [4]int{int(math.floor(mn.x)), int(math.floor(mn.y)), max(int(mx.x - mn.x), 1), max(int(mx.y - mn.y), 1)}
			e.Ldtk_Doc_SelectRect(doc, L.level, &L.sel, r, activeLayer = L.layer, includeEmpty = L.selectEmpty)
			level_sync_selection()
		}
		return true
	}
	if !pressL do return false
	// a handle of the selected resizable entity
	if L.selEntity != nil && entity_resizable(L.selEntity) {
		m := io.MousePos
		for h in Level_Handle {
			if !ent_handle_active(L.selEntity, h) do continue
			mn, mx := ent_handle_rect(h)
			if m.x >= mn.x - 2 && m.y >= mn.y - 2 && m.x < mx.x + 2 && m.y < mx.y + 2 {
				L.entResize, L.entMoved, L.entHandle = true, false, h
				return true
			}
		}
	}
	startMove :: proc(mw: [2]f32) {
		L := &GlobalLevel
		io := imgui.GetIO()
		L.selMoving, L.selMoved = true, false
		L.selGrab = mw
		L.selCopy = (io.KeySuper || io.KeyCtrl) && io.KeyAlt
	}
	// on the selection (any tool): move it
	if !e.Ldtk_Selection_Empty(&L.sel) && over_selection(mw) && !io.KeyShift {
		startMove(mw)
		return true
	}
	cell, ent, found := element_at(mw)
	if !selectMode {
		// with the painting tools, a click on an entity of the active Entities layer selects it
		if _, d := level_active_layer(); d != nil && d.type == .Entities && found && ent.obj != nil && ent.layer == L.layer {
			level_select_entity(ent.layer, ent.obj)
			startMove(mw)
			return true
		}
		return false
	}
	if io.KeyShift {
		// add / remove, or a rectangle from empty space
		if found {
			if ent.obj != nil do e.Ldtk_Selection_ToggleEntity(&L.sel, ent)
			else do e.Ldtk_Selection_ToggleCell(&L.sel, cell)
			level_sync_selection()
		} else {
			L.selRect = true
			L.selRectStart = mw
		}
		return true
	}
	if !found {
		level_clear_selection()
		L.selRect = true // a drag from empty space selects a rectangle
		L.selRectStart = mw
		return true
	}
	// select it; its layer becomes active and the palette picks its value
	level_clear_selection()
	layer := ent.obj != nil ? ent.layer : cell.layer
	if layer != L.layer {
		L.layer = layer
		level_sync_palette()
	}
	if ent.obj != nil {
		level_select_entity(ent.layer, ent.obj)
		if ed := e.Ldtk_Doc_EntityDef(doc, e.LdtkJson_Int(ent.obj, "defUid", -1)); ed != nil do L.entityDef = ed.uid
	} else {
		append(&L.sel.cells, cell)
		ly := &doc.levels[L.level].layers[cell.layer]
		if v := e.Ldtk_Doc_GetIntGrid(ly, cell.cx, cell.cy); v != 0 do L.intValue = v
		if tiles := e.Ldtk_Doc_TilesAt(ly, cell.cx, cell.cy); len(tiles) > 0 {
			level_set_tile_sel({tiles[len(tiles) - 1].t})
			L.flips = tiles[len(tiles) - 1].f
		}
		level_sync_selection()
	}
	startMove(mw)
	return true
}

@(private = "file")
linalg_len :: proc(v: [2]f32) -> f32 {return math.sqrt(v.x * v.x + v.y * v.y)}

// draw_level_spot: where a new level would go (green) or can't (red).
@(private = "file")
draw_level_spot :: proc() {
	L := &GlobalLevel
	if !L.spotPick || !L.hovered do return
	m := imgui.GetIO().MousePos
	mw := to_world({m.x, m.y})
	sp := e.Ldtk_Doc_LevelSpot(L.doc, L.world, {f64(mw.x), f64(mw.y)}, max(e.LdtkJson_Int(L.doc.root, "defaultGridSize", 16), 1))
	if !sp.ok do return
	r := rl.Rectangle{f32(sp.rect[0]), f32(sp.rect[1]), f32(sp.rect[2]), f32(sp.rect[3])}
	col := sp.overlaps ? rl.Color{240, 90, 90, 255} : rl.Color{90, 220, 120, 255}
	rl.DrawRectangleRec(r, {col.r, col.g, col.b, 50})
	rl.DrawRectangleLinesEx(r, 2 / L.zoom, col)
}

// draw_rule_preview: the cells where the rule picked in the Rules tab matches.
@(private = "file")
draw_rule_preview :: proc() {
	L := &GlobalLevel
	doc := L.doc
	if doc == nil || len(doc.levels) == 0 || levelRulePreview == 0 do return
	_, _, layerUid := e.Ldtk_Doc_FindRule(doc, levelRulePreview)
	if layerUid < 0 {
		levelRulePreview = 0
		return
	}
	lv := &doc.levels[L.level]
	for &ly, i in lv.layers {
		d := e.Ldtk_Doc_LayerDef(doc, &ly)
		if d == nil || d.uid != layerUid do continue
		o := layer_origin_of(i)
		g := f32(d.gridSize)
		for c in e.Ldtk_Doc_RuleMatchCells(doc, L.level, levelRulePreview) {
			r := rl.Rectangle{o.x + f32(c.x) * g, o.y + f32(c.y) * g, g, g}
			rl.DrawRectangleRec(r, {80, 220, 120, 60})
			rl.DrawRectangleLinesEx(r, 1 / L.zoom, {80, 220, 120, 200})
		}
		break
	}
}

// draw_selection: outlines of the selection, the drag ghost, the rectangle.
@(private = "file")
draw_selection :: proc() {
	L := &GlobalLevel
	doc := L.doc
	if doc == nil || len(doc.levels) == 0 do return
	lv := &doc.levels[L.level]
	thick := 1.5 / L.zoom
	col := rl.Color{255, 220, 80, 255}
	off := [2]f32{}
	if L.selMoving && L.selMoved {
		m := imgui.GetIO().MousePos
		dd := sel_delta(to_world({m.x, m.y}))
		off = {f32(dd.x), f32(dd.y)}
	}
	for c in L.sel.cells {
		if c.layer >= len(lv.layers) do continue
		d := e.Ldtk_Doc_LayerDef(doc, &lv.layers[c.layer])
		if d == nil do continue
		o := layer_origin_of(c.layer) + off
		g := f32(d.gridSize)
		r := rl.Rectangle{o.x + f32(c.cx) * g, o.y + f32(c.cy) * g, g, g}
		if off != {} do rl.DrawRectangleRec(r, {255, 220, 80, 70})
		rl.DrawRectangleLinesEx(r, thick, col)
	}
	for se in L.sel.entities {
		o := layer_origin_of(se.layer) + off
		r := e.Ldtk_Doc_EntityRect(se.obj)
		rect := rl.Rectangle{o.x + f32(r[0]), o.y + f32(r[1]), f32(r[2]), f32(r[3])}
		if off != {} do rl.DrawRectangleRec(rect, {255, 220, 80, 70})
		rl.DrawRectangleLinesEx(rect, thick * 1.3, col)
	}
	if L.selRect {
		m := imgui.GetIO().MousePos
		b := to_world({m.x, m.y})
		a := L.selRectStart
		rl.DrawRectangleRec({min(a.x, b.x), min(a.y, b.y), abs(b.x - a.x), abs(b.y - a.y)}, {120, 170, 255, 40})
		rl.DrawRectangleLinesEx({min(a.x, b.x), min(a.y, b.y), abs(b.x - a.x), abs(b.y - a.y)}, thick, {120, 170, 255, 230})
	}
}

// ----------------------------------------------------------------------------
// Picking a field value in the canvas (points, entity references)
// ----------------------------------------------------------------------------

// pick_grid: the grid points are picked on (the owner's layer, else the
// active layer's, else the project's default).
@(private = "file")
pick_grid :: proc() -> (origin: [2]f32, g: int) {
	L := &GlobalLevel
	lv := &L.doc.levels[L.level]
	layer := levelPick.layer
	if layer < 0 || layer >= len(lv.layers) do layer = L.layer
	g = e.LdtkJson_Int(L.doc.root, "defaultGridSize", 16)
	if layer >= 0 && layer < len(lv.layers) {
		if d := e.Ldtk_Doc_LayerDef(L.doc, &lv.layers[layer]); d != nil do g = d.gridSize
	}
	return layer_origin_of(layer), max(g, 1)
}

@(private = "file")
pick_input :: proc(state: ^EditorState, pressL, pressR: bool, mw: [2]f32) {
	L := &GlobalLevel
	doc := L.doc
	if pressR {
		LevelFields_CancelPick()
		return
	}
	if !pressL do return
	p := &levelPick
	fd := e.Ldtk_Doc_FieldDef(doc, e.LdtkJson_Int(p.fi, "defUid", -1))
	if fd == nil {
		LevelFields_CancelPick()
		return
	}
	isArray := e.LdtkJson_Bool(fd, "isArray")
	chain := isArray && imgui.GetIO().KeyShift // Shift: keep adding values
	switch p.kind {
	case .Point:
		o, g := pick_grid()
		c := [2]int{ldtk_floor(int(math.floor(mw.x - o.x)), g), ldtk_floor(int(math.floor(mw.y - o.y)), g)}
		e.Ldtk_Doc_Checkpoint(doc, L.level, "Pick Point")
		idx := p.idx
		if idx < 0 do idx = e.Ldtk_Doc_FieldArrayAdd(doc, p.fi)
		if idx >= 0 do e.Ldtk_Doc_SetFieldRaw(doc, p.fi, idx, fmt.tprintf("%d,%d", c.x, c.y))
	case .EntityRef:
		// a click in another level opens it (references can point there)
		if li := e.Ldtk_Doc_LevelAt(doc, L.world, {int(math.floor(mw.x)), int(math.floor(mw.y))}); li >= 0 && li != L.level {
			L.level = li
			L.layer = 0
			level_sync_selection()
			return
		}
		_, ent, found := element_at(mw)
		if !found || ent.obj == nil {
			Editor_Log(state, .Info, "Click an entity (Esc cancels)")
			return
		}
		if allowed, why := e.Ldtk_Doc_RefAllowed(doc, fd, p.owner, p.ownerLevel, ent.obj, L.level); p.owner != nil && !allowed {
			Editor_Log(state, .Warn, "This reference allows %s", why)
			return
		}
		e.Ldtk_Doc_Checkpoint(doc, -1, "Pick Reference") // (may touch two levels)
		idx := p.idx
		if idx < 0 do idx = e.Ldtk_Doc_FieldArrayAdd(doc, p.fi)
		if idx >= 0 do e.Ldtk_Doc_SetFieldRef(doc, p.fi, idx, p.owner, e.LdtkJson_Str(ent.obj, "iid"))
	case .Int, .Float, .Bool, .String, .Text, .Color, .Enum, .Path, .Tile, .Other:
	}
	if p.owner != nil do e.Ldtk_Doc_EntitySmart(doc, p.owner)
	doc.levels[L.level].dirty = true
	if p.ownerLevel < len(doc.levels) do doc.levels[p.ownerLevel].dirty = true
	if chain do p.idx = -1
	else do LevelFields_CancelPick()
}

// draw_pick_hint: what picking expects, and the cell / entity it would take.
@(private = "file")
draw_pick_hint :: proc() {
	L := &GlobalLevel
	if !levelPick.active do return
	m := imgui.GetIO().MousePos
	mw := to_world({m.x, m.y})
	thick := 2 / L.zoom
	if levelPick.kind == .Point {
		o, g := pick_grid()
		c := [2]int{ldtk_floor(int(math.floor(mw.x - o.x)), g), ldtk_floor(int(math.floor(mw.y - o.y)), g)}
		rl.DrawRectangleLinesEx({o.x + f32(c.x * g), o.y + f32(c.y * g), f32(g), f32(g)}, thick, {120, 255, 160, 255})
	} else {
		if _, ent, found := element_at(mw); found && ent.obj != nil {
			o := layer_origin_of(ent.layer)
			r := e.Ldtk_Doc_EntityRect(ent.obj)
			rl.DrawRectangleLinesEx({o.x + f32(r[0]), o.y + f32(r[1]), f32(r[2]), f32(r[3])}, thick, {120, 255, 160, 255})
		}
	}
}

// LevelCanvas_PickHintText: the line shown while picking.
LevelCanvas_PickHintText :: proc() -> string {
	if !levelPick.active do return ""
	name := e.LdtkJson_Str(levelPick.fi, "__identifier")
	what := levelPick.kind == .Point ? "a cell" : "an entity"
	return fmt.tprintf("Picking %s for \"%s\": click %s%s - Esc or right-click cancels", levelPick.kind == .Point ? "a point" : "a reference", name, what, levelPick.idx < 0 ? " (Shift: keep adding)" : "")
}

// ----------------------------------------------------------------------------
// Field values in the canvas (FieldDef.editorDisplayMode, like LDtk's
// FieldInstanceRender): values / names above, at the centre or beneath an
// entity, array counts, points (path, loop, star), radii, reference arrows;
// errors in red. Geometry here, text in the overlay.
// ----------------------------------------------------------------------------

@(private = "file")
Field_Show :: struct {
	fi, fd: ^e.LdtkJson,
	mode:   string,
	color:  rl.Color,
}

// shown_fields: the fields of an entity / level to show.
@(private = "file")
shown_fields :: proc(fields: []^e.LdtkJson, owner: ^e.LdtkJson, base: rl.Color) -> []Field_Show {
	L := &GlobalLevel
	doc := L.doc
	out := make([dynamic]Field_Show, context.temp_allocator)
	for fi in fields {
		fd := e.Ldtk_Doc_FieldDef(doc, e.LdtkJson_Int(fi, "defUid", -1))
		if fd == nil do continue
		mode := e.LdtkJson_Str(fd, "editorDisplayMode", "Hidden")
		err := field_error(doc, fd, fi, 0, owner)
		if err == "" && mode == "Hidden" do continue
		isArray := e.LdtkJson_Bool(fd, "isArray")
		empty := isArray ? e.Ldtk_Doc_FieldArrayLen(doc, fi) == 0 : e.Ldtk_Doc_FieldRaw(fi, 0).isDefault
		if err == "" && empty && !e.LdtkJson_Bool(fd, "editorAlwaysShow") do continue
		col := base
		if dc := e.LdtkJson_Str(fd, "editorDisplayColor"); dc != "" do col = e.Ldtk_ParseHexColor(dc, base)
		append(&out, Field_Show{fi, fd, mode, col})
	}
	return out[:]
}

// field_value_text: a field's values as one line (prefix / suffix, cut).
@(private = "file")
field_value_text :: proc(fs: Field_Show) -> string {
	L := &GlobalLevel
	doc := L.doc
	n := e.Ldtk_Doc_FieldArrayLen(doc, fs.fi)
	b := strings.builder_make(context.temp_allocator)
	for i in 0 ..< n {
		t, isNull := e.Ldtk_Doc_FieldText(doc, fs.fi, i)
		if e.Ldtk_FieldKindOf(fs.fd) == .EntityRef && !isNull {
			if _, _, target, ok := e.Ldtk_Doc_FindEntity(doc, t); ok do t = e.LdtkJson_Str(target, "__identifier")
		}
		if i > 0 do strings.write_string(&b, ", ")
		strings.write_string(&b, e.LdtkJson_Str(fs.fd, "editorTextPrefix"))
		strings.write_string(&b, isNull ? "-" : t)
		strings.write_string(&b, e.LdtkJson_Str(fs.fd, "editorTextSuffix"))
	}
	s := strings.to_string(b)
	if e.LdtkJson_Bool(fs.fd, "editorCutLongValues", true) && len(s) > 40 do s = fmt.tprintf("%s...", s[:37])
	return s
}

// draw_field_geometry: points, radii and reference links of the active
// level's entities (world space).
draw_field_geometry :: proc() {
	L := &GlobalLevel
	doc := L.doc
	if doc == nil || len(doc.levels) == 0 do return
	lv := &doc.levels[L.level]
	thick := 1.5 / L.zoom
	for &ly, j in lv.layers {
		d := e.Ldtk_Doc_LayerDef(doc, &ly)
		if d == nil || d.type != .Entities || !e.LdtkJson_Bool(ly.obj, "visible", true) do continue
		if j != L.layer && e.LdtkJson_Bool(d.obj, "hideFieldsWhenInactive") do continue
		o := layer_origin_of(j)
		g := f32(d.gridSize)
		for ent in e.LdtkJson_Arr(ly.obj, "entityInstances") {
			base := e.Ldtk_ParseHexColor(e.LdtkJson_Str(ent, "__smartColor", "#FFFFFF"))
			px := e.LdtkJson_Arr(ent, "px")
			if len(px) < 2 do continue
			pivot := o + {f32(px[0].num), f32(px[1].num)}
			r := e.Ldtk_Doc_EntityRect(ent)
			center := o + {f32(r[0]) + f32(r[2]) * 0.5, f32(r[1]) + f32(r[3]) * 0.5}
			for fs in shown_fields(e.LdtkJson_Arr(ent, "fieldInstances"), ent, base) {
				n := e.Ldtk_Doc_FieldArrayLen(doc, fs.fi)
				switch fs.mode {
				case "Points", "PointPath", "PointPathLoop", "PointStar":
					prev := pivot
					first := [2]f32{}
					for i in 0 ..< n {
						t, isNull := e.Ldtk_Doc_FieldText(doc, fs.fi, i)
						if isNull do continue
						parts := strings.split(t, ",", context.temp_allocator)
						if len(parts) != 2 do continue
						cx, _ := strconv.parse_int(parts[0])
						cy, _ := strconv.parse_int(parts[1])
						p := o + {(f32(cx) + 0.5) * g, (f32(cy) + 0.5) * g}
						if i == 0 do first = p
						switch fs.mode {
						case "PointPath", "PointPathLoop": rl.DrawLineEx(prev, p, thick, col_rl(fs.color, 0.8))
						case "PointStar": rl.DrawLineEx(pivot, p, thick, col_rl(fs.color, 0.8))
						}
						rl.DrawRectangleV(p - g * 0.2, {g * 0.4, g * 0.4}, fs.color)
						prev = p
					}
					if fs.mode == "PointPathLoop" && n > 1 do rl.DrawLineEx(prev, first, thick, col_rl(fs.color, 0.8))
				case "RadiusPx", "RadiusGrid":
					t, isNull := e.Ldtk_Doc_FieldText(doc, fs.fi, 0)
					if isNull do continue
					v, _ := strconv.parse_f64(t)
					rad := f32(v) * (fs.mode == "RadiusGrid" ? g : 1)
					if rad > 0 do rl.DrawCircleLinesV(center, rad, fs.color)
				case "RefLinkBetweenPivots", "RefLinkBetweenCenters":
					draw_ref_links(ent, j, fs.fi, fs.fd, fs.mode == "RefLinkBetweenCenters", fs.color, thick, false)
				}
			}
			// The selected entity's links (out and in) show whatever the
			// field's display mode, like LDtk.
			for fi in e.LdtkJson_Arr(ent, "fieldInstances") {
				fd := e.Ldtk_Doc_FieldDef(doc, e.LdtkJson_Int(fi, "defUid", -1))
				if fd == nil || e.Ldtk_FieldKindOf(fd) != .EntityRef do continue
				mode := e.LdtkJson_Str(fd, "editorDisplayMode", "Hidden")
				if mode == "RefLinkBetweenPivots" || mode == "RefLinkBetweenCenters" do continue
				col := base
				if dc := e.LdtkJson_Str(fd, "editorDisplayColor"); dc != "" do col = e.Ldtk_ParseHexColor(dc, base)
				draw_ref_links(ent, j, fi, fd, true, col, thick, true)
			}
		}
	}
}

// draw_ref_links: the arrows of one EntityRef field of `ent` (on layer
// `layer`) to targets in the active level. onlySelected: only the links
// that start or end at a selected entity.
@(private = "file")
draw_ref_links :: proc(ent: ^e.LdtkJson, layer: int, fi, fd: ^e.LdtkJson, centers: bool, col: rl.Color, thick: f32, onlySelected: bool) {
	L := &GlobalLevel
	doc := L.doc
	endpoint :: proc(ent: ^e.LdtkJson, o: [2]f32, centers: bool) -> [2]f32 {
		if centers {
			r := e.Ldtk_Doc_EntityRect(ent)
			return o + {f32(r[0]) + f32(r[2]) * 0.5, f32(r[1]) + f32(r[3]) * 0.5}
		}
		px := e.LdtkJson_Arr(ent, "px")
		return len(px) >= 2 ? o + {f32(px[0].num), f32(px[1].num)} : o
	}
	srcSel := e.Ldtk_Selection_HasEntity(&L.sel, ent)
	for i in 0 ..< e.Ldtk_Doc_FieldArrayLen(doc, fi) {
		t, isNull := e.Ldtk_Doc_FieldText(doc, fi, i)
		if isNull do continue
		tli, tlayer, target, ok := e.Ldtk_Doc_FindEntity(doc, t)
		if !ok || tli != L.level do continue
		if onlySelected && !srcSel && !e.Ldtk_Selection_HasEntity(&L.sel, target) do continue
		a := endpoint(ent, layer_origin_of(layer), centers)
		b := endpoint(target, layer_origin_of(tlayer), centers)
		draw_link(a, b, e.LdtkJson_Str(fd, "editorLinkStyle", "StraightArrow"), col, thick)
	}
}

// draw_link: a reference arrow in one of LDtk's link styles.
@(private = "file")
draw_link :: proc(a, b: [2]f32, style: string, col: rl.Color, thick: f32) {
	d := b - a
	l := math.sqrt(d.x * d.x + d.y * d.y)
	if l < 1 do return
	dir := d / l
	nrm := [2]f32{-dir.y, dir.x}
	switch style {
	case "DashedLine":
		step: f32 = 6
		for t: f32 = 0; t < l; t += step * 2 do rl.DrawLineEx(a + dir * t, a + dir * min(t + step, l), thick, col)
	case "ZigZag":
		prev := a
		segs := max(int(l / 8), 2)
		for i in 1 ..= segs {
			t := f32(i) / f32(segs)
			off := (i % 2 == 0 ? -1 : 1) * f32(3) * (i == segs ? 0 : 1)
			p := a + d * t + nrm * off
			rl.DrawLineEx(prev, p, thick, col)
			prev = p
		}
	case "CurvedArrow":
		ctrl := a + d * 0.5 + nrm * l * 0.2
		prev := a
		for i in 1 ..= 16 {
			t := f32(i) / 16
			p := (1 - t) * (1 - t) * a + 2 * (1 - t) * t * ctrl + t * t * b
			rl.DrawLineEx(prev, p, thick, col)
			prev = p
		}
		dir = b - ctrl
		dir /= max(math.sqrt(dir.x * dir.x + dir.y * dir.y), 0.001)
	case "ArrowsLine":
		rl.DrawLineEx(a, b, thick, col)
		m := a + d * 0.5
		rl.DrawTriangle(m + dir * 4, m - dir * 3 - nrm * 3, m - dir * 3 + nrm * 3, col)
	case:
		rl.DrawLineEx(a, b, thick, col)
	}
	if style != "DashedLine" && style != "ArrowsLine" {
		h: f32 = 5
		n2 := [2]f32{-dir.y, dir.x}
		rl.DrawTriangle(b, b - dir * h - n2 * h * 0.6, b - dir * h + n2 * h * 0.6, col)
	}
}

// draw_field_labels: values / names / counts of the active level's entities
// and the level's own fields (screen space).
draw_field_labels :: proc(dl: ^imgui.DrawList) {
	L := &GlobalLevel
	doc := L.doc
	lv := &doc.levels[L.level]
	h := imgui.GetTextLineHeight()
	label :: proc(dl: ^imgui.DrawList, pos: [2]f32, text: string, col: rl.Color, err: bool) {
		c := fmt.ctprintf("%s", text)
		w := imgui.CalcTextSize(c).x
		p := [2]f32{pos.x - w * 0.5, pos.y}
		imgui.DrawList_AddRectFilled(dl, {p.x - 3, p.y}, {p.x + w + 3, p.y + imgui.GetTextLineHeight()}, col_u32({0, 0, 0, 0.6}), 3, {})
		tc := err ? imgui.Vec4{1, 0.35, 0.2, 1} : imgui.Vec4{min(f32(col.r) / 255 + 0.35, 1), min(f32(col.g) / 255 + 0.35, 1), min(f32(col.b) / 255 + 0.35, 1), 1}
		imgui.DrawList_AddText(dl, {p.x, p.y}, col_u32(tc), c)
	}
	lines :: proc(fields: []Field_Show, owner: ^e.LdtkJson) -> ([dynamic]struct {text: string, pos: string, col: rl.Color, err: bool}) {
		out := make([dynamic]struct {text: string, pos: string, col: rl.Color, err: bool}, context.temp_allocator)
		doc := GlobalLevel.doc
		for fs in fields {
			name := e.LdtkJson_Str(fs.fi, "__identifier")
			pos := e.LdtkJson_Str(fs.fd, "editorDisplayPos", "Above")
			if err := field_error(doc, fs.fd, fs.fi, 0, owner); err != "" {
				append(&out, struct {text: string, pos: string, col: rl.Color, err: bool}{fmt.tprintf("%s <%s>", name, err), pos, fs.color, true})
				continue
			}
			text := ""
			switch fs.mode {
			case "ValueOnly": text = field_value_text(fs)
			case "NameAndValue": text = fmt.tprintf("%s = %s", name, field_value_text(fs))
			case "ArrayCountWithLabel": text = fmt.tprintf("%s: %d value(s)", name, e.Ldtk_Doc_FieldArrayLen(doc, fs.fi))
			case "ArrayCountNoLabel": text = fmt.tprintf("%d value(s)", e.Ldtk_Doc_FieldArrayLen(doc, fs.fi))
			}
			if text != "" do append(&out, struct {text: string, pos: string, col: rl.Color, err: bool}{text, pos, fs.color, false})
		}
		return out
	}
	for &ly, j in lv.layers {
		d := e.Ldtk_Doc_LayerDef(doc, &ly)
		if d == nil || d.type != .Entities || !e.LdtkJson_Bool(ly.obj, "visible", true) do continue
		if j != L.layer && e.LdtkJson_Bool(d.obj, "hideFieldsWhenInactive") do continue
		o := layer_origin_of(j)
		for ent in e.LdtkJson_Arr(ly.obj, "entityInstances") {
			base := e.Ldtk_ParseHexColor(e.LdtkJson_Str(ent, "__smartColor", "#FFFFFF"))
			r := e.Ldtk_Doc_EntityRect(ent)
			top := to_screen(o + {f32(r[0]) + f32(r[2]) * 0.5, f32(r[1])})
			bottom := to_screen(o + {f32(r[0]) + f32(r[2]) * 0.5, f32(r[1] + r[3])})
			mid := (top + bottom) * 0.5
			above, below, centre: f32
			ed := e.Ldtk_Doc_EntityDef(doc, e.LdtkJson_Int(ent, "defUid", -1))
			if ed != nil && e.LdtkJson_Bool(ed.obj, "showName", true) && L.zoom >= 1 {
				label(dl, {top.x, top.y - h - 1}, e.LdtkJson_Str(ent, "__identifier"), base, false)
				above += h + 1
			}
			for ln in lines(shown_fields(e.LdtkJson_Arr(ent, "fieldInstances"), ent, base), ent) {
				switch ln.pos {
				case "Beneath":
					label(dl, {bottom.x, bottom.y + 1 + below}, ln.text, ln.col, ln.err)
					below += h + 1
				case "Center":
					label(dl, {mid.x, mid.y - h * 0.5 + centre}, ln.text, ln.col, ln.err)
					centre += h + 1
				case:
					above += h + 1
					label(dl, {top.x, top.y - above}, ln.text, ln.col, ln.err)
				}
			}
		}
	}
	// the level's own fields, under its name
	p := e.Ldtk_Doc_LevelPos(doc, L.level)
	sp := to_screen({f32(p.x), f32(p.y)})
	y := sp.y + 2
	for ln in lines(shown_fields(e.LdtkJson_Arr(lv.obj, "fieldInstances"), nil, {200, 200, 200, 255}), nil) {
		w := imgui.CalcTextSize(fmt.ctprintf("%s", ln.text)).x
		label(dl, {sp.x + 6 + w * 0.5, y}, ln.text, ln.col, ln.err)
		y += h + 1
	}
}

// draw_entity: an entity the way its definition says (EntityRender):
// rectangle / ellipse / cross / tile (cover, fit inside, repeat, stretch,
// full size, 9-slice), fill / line / tile opacities, hollow.
draw_entity :: proc(ent: ^e.LdtkJson, rect: rl.Rectangle, layerOpacity: f32) {
	L := &GlobalLevel
	doc := L.doc
	ed := e.Ldtk_Doc_EntityDef(doc, e.LdtkJson_Int(ent, "defUid", -1))
	c := e.Ldtk_ParseHexColor(e.LdtkJson_Str(ent, "__smartColor", "#94D9B3"))
	if ed == nil {
		rl.DrawRectangleLinesEx(rect, 1 / L.zoom, c)
		return
	}
	obj := ed.obj
	mode := e.LdtkJson_Str(obj, "renderMode", "Rectangle")
	fillOp := f32(e.LdtkJson_Float(obj, "fillOpacity", 0.08)) * layerOpacity
	lineOp := f32(e.LdtkJson_Float(obj, "lineOpacity", 1)) * layerOpacity
	tileOp := f32(e.LdtkJson_Float(obj, "tileOpacity", 1)) * layerOpacity
	hollow := e.LdtkJson_Bool(obj, "hollow")
	thick := 1 / L.zoom
	// the tile: a field's (EntityTile) or the definition's
	tile := e.LdtkJson_Get(ent, "__tile")
	if tile != nil && tile.kind == .Object && (mode == "Tile" || mode == "Rectangle" || mode == "Ellipse") {
		tsUid := e.LdtkJson_Int(tile, "tilesetUid", -1)
		if tex, ok := level_texture(tsUid); ok {
			src := rl.Rectangle{f32(e.LdtkJson_Int(tile, "x")), f32(e.LdtkJson_Int(tile, "y")), f32(e.LdtkJson_Int(tile, "w")), f32(e.LdtkJson_Int(tile, "h"))}
			if mode == "Tile" {
				draw_entity_tile(tex, src, rect, e.LdtkJson_Str(obj, "tileRenderMode", "FitInside"), e.LdtkJson_Arr(obj, "nineSliceBorders"), e.LdtkJson_Arr(ent, "__pivot"), col_rl(rl.WHITE, tileOp))
			} else {
				// a shape with the tile as an icon in it
				sc := min(rect.width / max(src.width, 1), rect.height / max(src.height, 1))
				dw, dh := src.width * sc, src.height * sc
				rl.DrawTexturePro(tex, src, {rect.x + (rect.width - dw) * 0.5, rect.y + (rect.height - dh) * 0.5, dw, dh}, {}, 0, col_rl(rl.WHITE, tileOp))
			}
		}
	}
	switch mode {
	case "Ellipse":
		cx, cy := rect.x + rect.width * 0.5, rect.y + rect.height * 0.5
		if !hollow do rl.DrawEllipse(i32(cx), i32(cy), rect.width * 0.5, rect.height * 0.5, col_rl(c, fillOp))
		rl.DrawEllipseLines(i32(cx), i32(cy), rect.width * 0.5, rect.height * 0.5, col_rl(c, max(lineOp, 0.3)))
	case "Cross":
		rl.DrawLineEx({rect.x, rect.y}, {rect.x + rect.width, rect.y + rect.height}, thick * 2, col_rl(c, max(lineOp, 0.3)))
		rl.DrawLineEx({rect.x + rect.width, rect.y}, {rect.x, rect.y + rect.height}, thick * 2, col_rl(c, max(lineOp, 0.3)))
	case "Tile":
		if tile == nil || tile.kind != .Object do rl.DrawRectangleLinesEx(rect, thick, col_rl(c, 0.6)) // no tile: just the box
	case:
		if !hollow do rl.DrawRectangleRec(rect, col_rl(c, fillOp))
		rl.DrawRectangleLinesEx(rect, thick, col_rl(c, max(lineOp, 0.3)))
	}
}

// draw_entity_tile: a tile filling an entity box in an LDtk tile render mode.
@(private = "file")
draw_entity_tile :: proc(tex: rl.Texture2D, src: rl.Rectangle, r: rl.Rectangle, mode: string, nine: []^e.LdtkJson, pivot: []^e.LdtkJson, tint: rl.Color) {
	pv := [2]f32{0.5, 0.5}
	if len(pivot) >= 2 do pv = {f32(pivot[0].num), f32(pivot[1].num)}
	switch mode {
	case "Stretch":
		rl.DrawTexturePro(tex, src, r, {}, 0, tint)
	case "Cover":
		sc := max(r.width / src.width, r.height / src.height)
		// the part of the source that covers the box
		sw, sh := r.width / sc, r.height / sc
		s := rl.Rectangle{src.x + (src.width - sw) * pv.x, src.y + (src.height - sh) * pv.y, sw, sh}
		rl.DrawTexturePro(tex, s, r, {}, 0, tint)
	case "Repeat":
		for y := f32(0); y < r.height; y += src.height {
			for x := f32(0); x < r.width; x += src.width {
				w, h := min(src.width, r.width - x), min(src.height, r.height - y)
				rl.DrawTexturePro(tex, {src.x, src.y, w, h}, {r.x + x, r.y + y, w, h}, {}, 0, tint)
			}
		}
	case "FullSizeCropped":
		w, h := min(src.width, r.width), min(src.height, r.height)
		ox, oy := (r.width - w) * pv.x, (r.height - h) * pv.y
		rl.DrawTexturePro(tex, {src.x + (src.width - w) * pv.x, src.y + (src.height - h) * pv.y, w, h}, {r.x + ox, r.y + oy, w, h}, {}, 0, tint)
	case "FullSizeUncropped":
		rl.DrawTexturePro(tex, src, {r.x + (r.width - src.width) * pv.x, r.y + (r.height - src.height) * pv.y, src.width, src.height}, {}, 0, tint)
	case "NineSlice":
		b := [4]f32{}
		for x, i in nine do if i < 4 do b[i] = f32(x.num)
		info := rl.NPatchInfo{source = src, top = i32(b[0]), right = i32(b[1]), bottom = i32(b[2]), left = i32(b[3]), layout = .NINE_PATCH}
		rl.DrawTextureNPatch(tex, info, r, {}, 0, tint)
	case: // FitInside
		sc := min(r.width / src.width, r.height / src.height)
		dw, dh := src.width * sc, src.height * sc
		rl.DrawTexturePro(tex, src, {r.x + (r.width - dw) * pv.x, r.y + (r.height - dh) * pv.y, dw, dh}, {}, 0, tint)
	}
}
