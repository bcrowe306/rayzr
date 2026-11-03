package editor

import "core:fmt"
import "core:strconv"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Fill and stroke while drawing vector art (#268): the Inspector's Fill /
// Stroke for the selected shape - or, with none selected, for new shapes:
// none / solid / linear / radial gradient (a stop bar: click to add a stop,
// drag to move, right-click to remove; the Gradient tool (F) moves its
// ends on the canvas), opacity, width, joins, caps, miter limit, dashes,
// fill rule. Swatches are the project's palette (project.json "palette"),
// with the colours the open file uses beside it.
// ============================================================================

Vd_Paint_Choice :: enum {
	None,
	Solid,
	Linear,
	Radial,
}

@(private = "file")
vs: struct {
	stop:     [2]int, // the selected stop of the fill (0) and the stroke (1)
	dragStop: int,    // 0: none; else (which * 100 + stop + 1) being dragged
	dashBuf:  [64]u8,
	dashFor:  rawptr, // the style the dash text was read from
}

// VectorStyle_Edit: the Fill / Stroke section for `st` (a shape's style or
// the new-shape defaults); `bounds` places new gradients (document units).
// True when it changed something this frame.
VectorStyle_Edit :: proc(state: ^EditorState, st: ^e.Vector_Style, bounds: [4]f32, palette_target: ^[4]u8 = nil) -> (changed: bool) {
	// --- Fill
	imgui.SeparatorText("Fill")
	changed |= paint_row(state, "fill", &st.fill, &st.fillColor, &st.fillPaint, bounds, 0)
	if st.fill && UI_BeginProps("##vdfillrule") {
		UI_PropLabel("Rule")
		imgui.SetNextItemWidth(-1)
		if k, ch := UI_Combo("vd.style.fillrule", int(st.fillRule), {"Non-zero", "Even-odd (holes)"}); ch {
			st.fillRule = e.Vector_Fill_Rule(k)
			changed = true
		}
		UI_Tooltip("Even-odd: overlapping parts of the path become holes")
		UI_EndProps()
	}
	// --- Stroke
	imgui.SeparatorText("Stroke")
	changed |= paint_row(state, "stroke", &st.stroke, &st.strokeColor, &st.strokePaint, bounds, 1)
	if st.stroke {
		if !UI_BeginProps("##vdstroke") do return
		defer UI_EndProps()
		UI_PropLabel("Width")
		imgui.SetNextItemWidth(-1)
		if imgui.DragFloat("##vdsw", &st.strokeWidth, 0.1, 0, 200, "%.1f") do changed = true
		Drive_Item("vd.style.width")
		UI_PropLabel("Joins")
		imgui.SetNextItemWidth(-1)
		if k, ch := UI_Combo("vd.style.join", int(st.join), {"Miter", "Round", "Bevel"}); ch {st.join = e.Vector_Join(k); changed = true}
		if st.join == .Miter {
			UI_PropLabel("Miter Limit")
			imgui.SetNextItemWidth(-1)
			if imgui.DragFloat("##vdml", &st.miterLimit, 0.05, 1, 20, "%.1f") do changed = true
			UI_Tooltip("How far a sharp corner may point before it's cut off (bevelled)")
		}
		UI_PropLabel("Caps")
		imgui.SetNextItemWidth(-1)
		if k, ch := UI_Combo("vd.style.cap", int(st.cap), {"Butt", "Round", "Square"}); ch {st.cap = e.Vector_Cap(k); changed = true}
		UI_PropLabel("Dashes")
		if vs.dashFor != st {
			vs.dashFor = st
			vs.dashBuf = {}
			copy(vs.dashBuf[:63], dash_text(st.dash))
		}
		imgui.SetNextItemWidth(-1)
		if imgui.InputTextWithHint("##vddash", "solid (or: 8 4, 2 6...)", cstring(raw_data(vs.dashBuf[:])), len(vs.dashBuf)) {
			st.dash = dash_parse(string(cstring(raw_data(vs.dashBuf[:]))), st.dash.offset)
			changed = true
		}
		Drive_Item("vd.style.dash")
		UI_Tooltip("Dash, gap, dash, gap... in the shape's units (up to 8); empty: a solid line")
		if st.dash.count > 0 {
			UI_PropLabel("Dash Offset")
			imgui.SetNextItemWidth(-1)
			if imgui.DragFloat("##vddo", &st.dash.offset, 0.2) do changed = true
		}
	}
	// --- The whole shape
	imgui.SeparatorText("Shape")
	if UI_BeginProps("##vdshape") {
		UI_PropLabel("Opacity")
		imgui.SetNextItemWidth(-1)
		op := st.opacity if st.opacity > 0 else 1
		if imgui.SliderFloat("##vdop", &op, 0.01, 1, "%.2f") {st.opacity = op; changed = true}
		Drive_Item("vd.style.opacity")
		UI_EndProps()
	}
	return
}

// paint_row: a paint's kind (none / solid / gradients), its colour or its
// stop bar. `which`: 0 fill, 1 stroke.
@(private = "file")
paint_row :: proc(state: ^EditorState, name: string, on: ^bool, color: ^[4]u8, paint: ^e.Vector_Paint, bounds: [4]f32, which: int) -> (changed: bool) {
	if !UI_BeginProps(fmt.tprintf("##vd%s", name)) do return
	defer UI_EndProps()
	choice := Vd_Paint_Choice.None
	if on^ {
		switch paint.kind {
		case .Solid:  choice = .Solid
		case .Linear: choice = .Linear
		case .Radial: choice = .Radial
		}
	}
	UI_PropLabel("Paint")
	imgui.SetNextItemWidth(-1)
	if k, ch := UI_Combo(fmt.tprintf("vd.style.%s.kind", name), int(choice), {"None", "Colour", "Linear gradient", "Radial gradient"}); ch {
		switch Vd_Paint_Choice(k) {
		case .None:   on^ = false
		case .Solid:  on^, paint^ = true, {}
		case .Linear: on^, paint^ = true, default_gradient(.Linear, color^, bounds)
		case .Radial: on^, paint^ = true, default_gradient(.Radial, color^, bounds)
		}
		vs.stop[which] = 0
		changed = true
	}
	if !on^ do return
	if paint.kind == .Solid {
		UI_PropLabel("Colour")
		changed |= colour_edit(fmt.tprintf("vd.style.%s.color", name), color)
		return
	}
	UI_PropLabel("Stops")
	changed |= stop_bar(fmt.tprintf("vd.style.%s.stops", name), paint, which)
	if s := vs.stop[which]; s >= 0 && s < int(paint.stopCount) {
		UI_PropLabel("Stop Colour")
		changed |= colour_edit(fmt.tprintf("vd.style.%s.stopcolor", name), &paint.stops[s].color)
	}
	UI_PropLabel("Spread")
	imgui.SetNextItemWidth(-1)
	if k, ch := UI_Combo(fmt.tprintf("vd.style.%s.spread", name), int(paint.spread), {"Pad", "Reflect", "Repeat"}); ch {
		paint.spread = e.Vector_Spread(k)
		changed = true
	}
	UI_Tooltip("Past the gradient's ends: the end colours (Pad), back and forth, or over again. The Gradient tool (F) moves its ends on the canvas.")
	return
}

@(private = "file")
colour_edit :: proc(id: string, c: ^[4]u8) -> bool {
	f := [4]f32{f32(c[0]) / 255, f32(c[1]) / 255, f32(c[2]) / 255, f32(c[3]) / 255}
	imgui.SetNextItemWidth(-1)
	ch := imgui.ColorEdit4(fmt.ctprintf("##%s", id), &f, {.AlphaBar, .AlphaPreviewHalf})
	Drive_Item(id)
	if ch do c^ = {u8(f[0] * 255 + 0.5), u8(f[1] * 255 + 0.5), u8(f[2] * 255 + 0.5), u8(f[3] * 255 + 0.5)}
	return ch
}

// default_gradient: a new gradient across the shape (left to right, or
// round its centre), from its colour to black (a light colour) or white.
default_gradient :: proc(kind: e.Vector_Paint_Kind, color: [4]u8, b: [4]f32) -> e.Vector_Paint {
	bb := b
	if bb[2] <= bb[0] || bb[3] <= bb[1] do bb = {0, 0, 100, 100}
	light := int(color.r) * 3 + int(color.g) * 6 + int(color.b) > 1280 // (perceived brightness above half)
	end := [4]u8{255, 255, 255, 255}
	if light do end = {0, 0, 0, 255}
	stops := []e.Vector_Stop{{0, color}, {1, end}}
	cy := (bb[1] + bb[3]) * 0.5
	if kind == .Linear do return e.Vector_LinearGradient({bb[0], cy}, {bb[2], cy}, stops)
	return e.Vector_RadialGradient({(bb[0] + bb[2]) * 0.5, cy}, max(bb[2] - bb[0], bb[3] - bb[1]) * 0.5, stops)
}

// stop_bar: the gradient drawn left to right with its stops under it -
// click the bar to add one, drag a stop along, right-click to remove it
// (two are kept).
@(private = "file")
stop_bar :: proc(id: string, p: ^e.Vector_Paint, which: int) -> (changed: bool) {
	w := imgui.GetContentRegionAvail().x
	H :: 18
	origin := imgui.GetCursorScreenPos()
	imgui.InvisibleButton(fmt.ctprintf("##%s", id), {w, H + 12})
	Drive_ItemRect(id, origin, origin + {w, H}, inWindow = true)
	dl := imgui.GetWindowDrawList()
	// The bar: each pair of stops a horizontal blend.
	col :: proc(c: [4]u8) -> u32 {return col_u32({f32(c[0]) / 255, f32(c[1]) / 255, f32(c[2]) / 255, f32(c[3]) / 255})}
	n := int(p.stopCount)
	imgui.DrawList_AddRectFilled(dl, origin, origin + {w, H}, col_u32({0.5, 0.5, 0.5, 1}))
	for i in 0 ..< n - 1 {
		a, b := p.stops[i], p.stops[i + 1]
		x0, x1 := origin.x + a.offset * w, origin.x + b.offset * w
		imgui.DrawList_AddRectFilledMultiColor(dl, {x0, origin.y}, {x1, origin.y + H}, col(a.color), col(b.color), col(b.color), col(a.color))
	}
	if n > 0 {
		imgui.DrawList_AddRectFilled(dl, origin, {origin.x + p.stops[0].offset * w, origin.y + H}, col(p.stops[0].color))
		imgui.DrawList_AddRectFilled(dl, {origin.x + p.stops[n - 1].offset * w, origin.y}, origin + {w, H}, col(p.stops[n - 1].color))
	}
	imgui.DrawList_AddRect(dl, origin, origin + {w, H}, col_u32(ui_line(0.5)))
	io := imgui.GetIO()
	mouse := [2]f32{io.MousePos.x, io.MousePos.y}
	hover := -1
	for i in 0 ..< n {
		x := origin.x + p.stops[i].offset * w
		at := [2]f32{x, origin.y + H + 5}
		sel := vs.stop[which] == i
		imgui.DrawList_AddTriangleFilled(dl, {x, origin.y + H}, {x - 5, origin.y + H + 9}, {x + 5, origin.y + H + 9}, col_u32(UI_ACCENT if sel else {0.85, 0.85, 0.85, 1}))
		Drive_ItemRect(fmt.tprintf("%s:%d", id, i), at - {5, 5}, at + {5, 5}, inWindow = true)
		if abs(mouse.x - x) < 6 && mouse.y > origin.y + H - 2 && mouse.y < origin.y + H + 12 do hover = i
	}
	t := clamp((mouse.x - origin.x) / max(w, 1), 0, 1)
	key := which * 100
	if imgui.IsItemClicked(.Left) {
		if hover >= 0 {
			vs.stop[which], vs.dragStop = hover, key + hover + 1
		} else if n < e.VECTOR_MAX_STOPS {
			// A new stop where clicked, coloured as the gradient is there.
			c := stop_color_at(p, t)
			i := 0
			for i < n && p.stops[i].offset <= t do i += 1
			for k := n; k > i; k -= 1 do p.stops[k] = p.stops[k - 1]
			p.stops[i] = {t, c}
			p.stopCount += 1
			vs.stop[which], vs.dragStop = i, key + i + 1
			changed = true
		}
	}
	if imgui.IsItemClicked(.Right) && hover >= 0 && n > 2 {
		for k in hover ..< n - 1 do p.stops[k] = p.stops[k + 1]
		p.stopCount -= 1
		vs.stop[which] = min(vs.stop[which], int(p.stopCount) - 1)
		changed = true
	}
	if vs.dragStop > key && vs.dragStop <= key + 100 {
		if imgui.IsMouseDown(.Left) {
			i := vs.dragStop - key - 1
			if i < int(p.stopCount) && p.stops[i].offset != t {
				p.stops[i].offset = t
				// Kept in order (the dragged one passes its neighbours).
				for i > 0 && p.stops[i - 1].offset > p.stops[i].offset {p.stops[i - 1], p.stops[i] = p.stops[i], p.stops[i - 1]; i -= 1}
				for i + 1 < int(p.stopCount) && p.stops[i + 1].offset < p.stops[i].offset {p.stops[i + 1], p.stops[i] = p.stops[i], p.stops[i + 1]; i += 1}
				vs.stop[which], vs.dragStop = i, key + i + 1
				changed = true
			}
		} else do vs.dragStop = 0
	}
	return
}

// stop_color_at: the gradient's colour at t (0..1 along it).
@(private = "file")
stop_color_at :: proc(p: ^e.Vector_Paint, t: f32) -> [4]u8 {
	n := int(p.stopCount)
	if n == 0 do return {255, 255, 255, 255}
	if t <= p.stops[0].offset do return p.stops[0].color
	for i in 1 ..< n {
		a, b := p.stops[i - 1], p.stops[i]
		if t <= b.offset {
			f := (t - a.offset) / max(b.offset - a.offset, 1e-4)
			out: [4]u8
			for k in 0 ..< 4 do out[k] = u8(f32(a.color[k]) + (f32(b.color[k]) - f32(a.color[k])) * f + 0.5)
			return out
		}
	}
	return p.stops[n - 1].color
}

@(private = "file")
dash_text :: proc(d: e.Vector_Dash) -> string {
	sb := strings.builder_make(context.temp_allocator)
	dd := d
	for v, i in dd.values[:dd.count] {
		if i > 0 do strings.write_byte(&sb, ' ')
		fmt.sbprintf(&sb, "%g", v)
	}
	return strings.to_string(sb)
}

@(private = "file")
dash_parse :: proc(s: string, offset: f32) -> e.Vector_Dash {
	d := e.Vector_Dash{offset = offset}
	for f in strings.fields(strings.trim_space(strings.join(strings.split(s, ",", context.temp_allocator), " ", context.temp_allocator)), context.temp_allocator) {
		if d.count >= 8 do break
		if v, ok := strconv.parse_f32(f); ok && v >= 0 {
			d.values[d.count] = v
			d.count += 1
		}
	}
	// (All zeros: nothing would draw - a solid line instead.)
	total: f32
	for v in d.values[:d.count] do total += v
	if total <= 0 do d.count = 0
	return d
}

// --- swatches -------------------------------------------------------------------------

// VectorStyle_Swatches: the project's palette (click: the fill, Shift+click:
// the line; right-click: removed; + adds the current fill) and the solid
// colours the file uses. True when a colour was applied.
VectorStyle_Swatches :: proc(state: ^EditorState, st: ^e.Vector_Style, used: [][4]u8) -> (changed: bool) {
	imgui.SeparatorText("Swatches")
	swatch :: proc(id: string, c: [4]u8) -> (left, right: bool) {
		f := imgui.Vec4{f32(c[0]) / 255, f32(c[1]) / 255, f32(c[2]) / 255, f32(c[3]) / 255}
		left = imgui.ColorButton(fmt.ctprintf("##%s", id), f, {.AlphaPreviewHalf}, {18, 18})
		Drive_Item(id)
		right = imgui.IsItemClicked(.Right)
		return
	}
	pal := &state.projectConfig.palette
	shift := imgui.GetIO().KeyShift
	remove := -1
	for c, i in pal {
		if i > 0 && i % 10 != 0 do imgui.SameLine(0, 3)
		l, r := swatch(fmt.tprintf("vd.swatch:%d", i), c)
		UI_Tooltip(fmt.tprintf("#%02x%02x%02x%02x - click: fill, Shift+click: line, right-click: remove", c.r, c.g, c.b, c.a))
		if l {apply_swatch(st, c, shift); changed = true}
		if r do remove = i
	}
	if remove >= 0 {
		ordered_remove(pal, remove)
		e.Project_SaveConfigToFile(state.projectPath, &state.projectConfig)
	}
	if len(pal) > 0 do imgui.SameLine(0, 3)
	if UI_IconButton(ICON_FA_PLUS, "vd.swatch.add", "Add the fill colour to the project's swatches (project.json)", false, 20) {
		c := st.fillColor if st.fill else st.strokeColor
		if pal^ == nil do pal^ = make([dynamic][4]u8)
		append(pal, c)
		e.Project_SaveConfigToFile(state.projectPath, &state.projectConfig)
	}
	if len(used) > 0 {
		UI_DimText("In this file:")
		for c, i in used {
			if i > 0 && i % 10 != 0 do imgui.SameLine(0, 3)
			l, _ := swatch(fmt.tprintf("vd.used:%d", i), c)
			if l {apply_swatch(st, c, shift); changed = true}
		}
	}
	return
}

@(private = "file")
apply_swatch :: proc(st: ^e.Vector_Style, c: [4]u8, line: bool) {
	if line {
		st.stroke, st.strokeColor, st.strokePaint = true, c, {}
		if st.strokeWidth <= 0 do st.strokeWidth = 1
	} else {
		st.fill, st.fillColor, st.fillPaint = true, c, {}
	}
}

// VectorStyle_UsedColours: the solid colours a document's shapes use (up to 20).
VectorStyle_UsedColours :: proc(doc: ^e.Vector_Doc) -> [][4]u8 {
	out := make([dynamic][4]u8, context.temp_allocator)
	add :: proc(out: ^[dynamic][4]u8, c: [4]u8) {
		for x in out do if x == c do return
		if len(out) < 20 do append(out, c)
	}
	for &s in doc.shapes {
		if s.style.fill && s.style.fillPaint.kind == .Solid do add(&out, s.style.fillColor)
		if s.style.stroke && s.style.strokePaint.kind == .Solid do add(&out, s.style.strokeColor)
	}
	return out[:]
}
