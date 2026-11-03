package engine

import "core:fmt"
import "core:strings"

// ============================================================================
// Writing SVG (#267): a Vector_Doc - what the importer made of a file, or
// art drawn in the editor - as a clean SVG that Inkscape / Illustrator /
// Affinity open again. Coordinates are the document's (transforms the file
// had are baked in), groups keep their names as ids (symbols, swap frames:
// display:none for hidden ones), gradients and clips go in <defs>.
// Vector_LoadSVG reads it back to the same shapes.
// ============================================================================

// A comment marking files Rayzr wrote.
VECTOR_SVG_MARK :: "<!-- Made with Rayzr -->"

// Vector_Doc_ToSVG: the document as SVG text.
Vector_Doc_ToSVG :: proc(doc: ^Vector_Doc, allocator := context.allocator) -> string {
	w := Svg_Writer{sb = strings.builder_make(context.temp_allocator), defs = strings.builder_make(context.temp_allocator)}
	w.clips = make(map[string]int, allocator = context.temp_allocator)
	w.ids = make(map[string]bool, allocator = context.temp_allocator)
	size := doc.size
	if size.x <= 0 || size.y <= 0 do size = {100, 100}
	fmt.sbprintf(&w.sb, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%s\" height=\"%s\" viewBox=\"0 0 %s %s\">\n", svg_num(size.x), svg_num(size.y), svg_num(size.x), svg_num(size.y))
	strings.write_string(&w.sb, VECTOR_SVG_MARK + "\n")

	// <defs>: the clips (one per clip region shapes share) and the gradients.
	body := strings.builder_make(context.temp_allocator)
	w.body = &body
	svg_write_range(&w, doc, -1, 0, len(doc.shapes), 1)
	if len(w.defs.buf) > 0 || len(w.clips) > 0 {
		strings.write_string(&w.sb, "  <defs>\n")
		strings.write_string(&w.sb, strings.to_string(w.defs))
		strings.write_string(&w.sb, "  </defs>\n")
	}
	strings.write_string(&w.sb, strings.to_string(body))
	strings.write_string(&w.sb, "</svg>\n")
	return strings.clone(strings.to_string(w.sb), allocator)
}

@(private = "file")
Svg_Writer :: struct {
	sb, defs:  strings.Builder,
	body:      ^strings.Builder,
	clips:     map[string]int, // a clip's path data + rule -> its id (shapes with the same clip share it)
	gradients: int,
	ids:       map[string]bool,
}

// svg_write_range writes shapes [from, to) of `parent`'s range, with the
// child groups starting in it as nested <g>s.
@(private = "file")
svg_write_range :: proc(w: ^Svg_Writer, doc: ^Vector_Doc, parent, from, to, depth: int) {
	i := from
	for {
		// Groups starting here (empty ones too), in the order they were read.
		wrote := false
		for g, gi in doc.groups {
			if g.parent != parent || g.first != i do continue
			indent(w.body, depth)
			strings.write_string(w.body, "<g")
			if id := svg_unique_id(w, g.name); id != "" do fmt.sbprintf(w.body, " id=\"%s\"", id)
			if g.hidden do strings.write_string(w.body, " style=\"display:none\"")
			strings.write_string(w.body, ">\n")
			svg_write_range(w, doc, gi, g.first, g.first + g.count, depth + 1)
			indent(w.body, depth)
			strings.write_string(w.body, "</g>\n")
			if g.count > 0 {
				i = g.first + g.count
				wrote = true
				break
			}
		}
		if wrote do continue
		if i >= to do break
		svg_write_shape(w, &doc.shapes[i], depth)
		i += 1
	}
}

@(private = "file")
svg_write_shape :: proc(w: ^Svg_Writer, s: ^Vector_Shape, depth: int) {
	st := &s.style
	indent(w.body, depth)
	fmt.sbprintf(w.body, "<path d=\"%s\"", svg_path_data(&s.path))
	if st.fill {
		fmt.sbprintf(w.body, " fill=\"%s\"", svg_paint(w, st.fillPaint, st.fillColor))
		if st.fillPaint.kind == .Solid && st.fillColor.a != 255 do fmt.sbprintf(w.body, " fill-opacity=\"%s\"", svg_num(f32(st.fillColor.a) / 255))
		if st.fillRule == .EvenOdd do strings.write_string(w.body, " fill-rule=\"evenodd\"")
	} else {
		strings.write_string(w.body, " fill=\"none\"")
	}
	if st.stroke {
		fmt.sbprintf(w.body, " stroke=\"%s\"", svg_paint(w, st.strokePaint, st.strokeColor))
		if st.strokePaint.kind == .Solid && st.strokeColor.a != 255 do fmt.sbprintf(w.body, " stroke-opacity=\"%s\"", svg_num(f32(st.strokeColor.a) / 255))
		if st.strokeWidth != 1 do fmt.sbprintf(w.body, " stroke-width=\"%s\"", svg_num(st.strokeWidth))
		if st.join != .Miter do fmt.sbprintf(w.body, " stroke-linejoin=\"%s\"", "round" if st.join == .Round else "bevel")
		if st.cap != .Butt do fmt.sbprintf(w.body, " stroke-linecap=\"%s\"", "round" if st.cap == .Round else "square")
		if st.miterLimit != 4 && st.miterLimit > 0 do fmt.sbprintf(w.body, " stroke-miterlimit=\"%s\"", svg_num(st.miterLimit))
		if st.dash.count > 0 {
			strings.write_string(w.body, " stroke-dasharray=\"")
			dash := st.dash
			for v, k in dash.values[:dash.count] {
				if k > 0 do strings.write_byte(w.body, ' ')
				strings.write_string(w.body, svg_num(v))
			}
			strings.write_byte(w.body, '"')
			if st.dash.offset != 0 do fmt.sbprintf(w.body, " stroke-dashoffset=\"%s\"", svg_num(st.dash.offset))
		}
	}
	if st.opacity > 0 && st.opacity < 1 do fmt.sbprintf(w.body, " opacity=\"%s\"", svg_num(st.opacity))
	if s.clip != nil {
		d := svg_path_data(&s.clip.path)
		key := fmt.tprintf("%s|%v", d, s.clip.rule)
		id, seen := w.clips[key]
		if !seen {
			id = len(w.clips) + 1
			w.clips[key] = id
			fmt.sbprintf(&w.defs, "    <clipPath id=\"clip%d\"><path d=\"%s\"%s/></clipPath>\n", id, d, " clip-rule=\"evenodd\"" if s.clip.rule == .EvenOdd else "")
		}
		fmt.sbprintf(w.body, " clip-path=\"url(#clip%d)\"", id)
	}
	strings.write_string(w.body, "/>\n")
}

// svg_paint: a colour ("#rrggbb") or a gradient written to <defs> ("url(#gN)").
@(private = "file")
svg_paint :: proc(w: ^Svg_Writer, paint: Vector_Paint, color: [4]u8) -> string {
	p := paint
	if p.kind == .Solid do return fmt.tprintf("#%02x%02x%02x", color.r, color.g, color.b)
	w.gradients += 1
	id := fmt.tprintf("g%d", w.gradients)
	spread := ""
	switch p.spread {
	case .Pad:
	case .Reflect: spread = " spreadMethod=\"reflect\""
	case .Repeat:  spread = " spreadMethod=\"repeat\""
	}
	xf := ""
	if p.transform != {} do xf = fmt.tprintf(" gradientTransform=\"matrix(%s %s %s %s %s %s)\"", svg_num(p.transform[0]), svg_num(p.transform[1]), svg_num(p.transform[2]), svg_num(p.transform[3]), svg_num(p.transform[4]), svg_num(p.transform[5]))
	tag := "linearGradient"
	if p.kind == .Linear {
		fmt.sbprintf(&w.defs, "    <linearGradient id=\"%s\" gradientUnits=\"userSpaceOnUse\" x1=\"%s\" y1=\"%s\" x2=\"%s\" y2=\"%s\"%s%s>\n", id, svg_num(p.p0.x), svg_num(p.p0.y), svg_num(p.p1.x), svg_num(p.p1.y), spread, xf)
	} else {
		tag = "radialGradient"
		fmt.sbprintf(&w.defs, "    <radialGradient id=\"%s\" gradientUnits=\"userSpaceOnUse\" cx=\"%s\" cy=\"%s\" r=\"%s\"%s%s>\n", id, svg_num(p.center.x), svg_num(p.center.y), svg_num(p.radius), spread, xf)
	}
	for s in p.stops[:p.stopCount] {
		fmt.sbprintf(&w.defs, "      <stop offset=\"%s\" stop-color=\"#%02x%02x%02x\"", svg_num(s.offset), s.color.r, s.color.g, s.color.b)
		if s.color.a != 255 do fmt.sbprintf(&w.defs, " stop-opacity=\"%s\"", svg_num(f32(s.color.a) / 255))
		strings.write_string(&w.defs, "/>\n")
	}
	fmt.sbprintf(&w.defs, "    </%s>\n", tag)
	return fmt.tprintf("url(#%s)", id)
}

// svg_path_data: a path as SVG path data (absolute commands).
@(private = "file")
svg_path_data :: proc(p: ^Vector_Path) -> string {
	sb := strings.builder_make(context.temp_allocator)
	k := 0
	pt :: proc(sb: ^strings.Builder, a: [2]f32) {fmt.sbprintf(sb, "%s %s", svg_num(a.x), svg_num(a.y))}
	for c, i in p.cmds {
		if i > 0 do strings.write_byte(&sb, ' ')
		switch c {
		case .Move:  strings.write_string(&sb, "M"); pt(&sb, p.pts[k]); k += 1
		case .Line:  strings.write_string(&sb, "L"); pt(&sb, p.pts[k]); k += 1
		case .Quad:  strings.write_string(&sb, "Q"); pt(&sb, p.pts[k]); strings.write_byte(&sb, ' '); pt(&sb, p.pts[k + 1]); k += 2
		case .Cubic: strings.write_string(&sb, "C"); pt(&sb, p.pts[k]); strings.write_byte(&sb, ' '); pt(&sb, p.pts[k + 1]); strings.write_byte(&sb, ' '); pt(&sb, p.pts[k + 2]); k += 3
		case .Close: strings.write_string(&sb, "Z")
		}
	}
	return strings.to_string(sb)
}

// svg_num: a coordinate with up to 3 decimals, no trailing zeros.
@(private = "file")
svg_num :: proc(v: f32) -> string {
	s := fmt.tprintf("%.3f", v)
	s = strings.trim_right(s, "0")
	s = strings.trim_suffix(s, ".")
	if s == "-0" || s == "" do s = "0"
	return s
}

// svg_unique_id: a group name usable as an XML id, unique in the file.
@(private = "file")
svg_unique_id :: proc(w: ^Svg_Writer, name: string) -> string {
	if name == "" do return ""
	sb := strings.builder_make(context.temp_allocator)
	for r, i in name {
		ok := (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || r == '_' || (i > 0 && ((r >= '0' && r <= '9') || r == '-' || r == '.'))
		strings.write_rune(&sb, r if ok else '_')
	}
	base := strings.to_string(sb)
	id := base
	for n := 2; (id in w.ids); n += 1 do id = fmt.tprintf("%s_%d", base, n)
	w.ids[id] = true
	return id
}

@(private = "file")
indent :: proc(sb: ^strings.Builder, depth: int) {
	for _ in 0 ..< depth do strings.write_string(sb, "  ")
}
