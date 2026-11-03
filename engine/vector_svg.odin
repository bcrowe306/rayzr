package engine

import "core:encoding/xml"
import "core:fmt"
import "core:math"
import vmem "core:mem/virtual"
import "core:strconv"
import "core:strings"

// ============================================================================
// SVG import (Phase 14 V.5): an SVG file -> a Vector_Doc (shapes with their
// styles, clips and named groups), the subset Inkscape, Illustrator,
// Affinity and Figma export:
//
//   elements    svg (viewBox, width / height), g, path, rect (rounded),
//               circle, ellipse, line, polyline, polygon, use, defs,
//               linearGradient / radialGradient (+ href inheritance),
//               clipPath, style (CSS)
//   styling     presentation attributes, style="", <style> rules with tag /
//               .class / #id selectors (Illustrator's CSS export),
//               inheritance; fill / stroke (colours, url(#gradient), none,
//               currentColor), fill-rule, stroke-width / linejoin / linecap /
//               miterlimit / dasharray / dashoffset, opacity, fill-opacity,
//               stroke-opacity, display / visibility
//   geometry    transform lists (matrix, translate, scale, rotate, skewX,
//               skewY), the path grammar (M L H V C S Q T A Z, relative and
//               absolute; arcs become cubics), units (px, pt, pc, mm, cm,
//               in, %)
//
// Not supported (a warning each): text (convert it to outlines), images,
// filters, masks, patterns, markers, a radial gradient's focal point.
// Transforms are baked into the points; every shape remembers the groups
// it was in (symbols, part swapping: M3).
// ============================================================================

Vector_Group :: struct {
	name:   string, // id, or inkscape:label / data-name when there is one
	parent: int,    // -1: the document
	first:  int,    // its shapes: [first, first + count) (children's included)
	count:  int,
	hidden: bool,   // display:none / visibility:hidden - drawn only when picked (a swap frame)
}

Vector_Doc :: struct {
	arena:    vmem.Arena, // everything below lives in it
	shapes:   [dynamic]Vector_Shape,
	groups:   [dynamic]Vector_Group,
	min:      [2]f32, // the document's box (after its viewBox mapping)
	size:     [2]f32,
	drawn:    [4]f32, // what the shapes cover, strokes included (min x, min y, max x, max y)
	warnings: [dynamic]string,
	visible:  [][]Vector_Shape, // per part + 1: its shapes without hidden groups inside it (nil: all of its range)
}

Vector_Doc_Destroy :: proc(doc: ^Vector_Doc) {
	if doc == nil do return
	vmem.arena_destroy(&doc.arena)
	doc^ = {}
}

@(private = "file")
Svg_Paint :: struct {
	kind:  enum u8 {Inherit, None, Color, Url, Current},
	color: [4]u8,
	url:   string,
}

// The inheritable style, as the walk goes down.
@(private = "file")
Svg_State :: struct {
	fill, stroke:   Svg_Paint,
	color:          [4]u8, // currentColor
	fillOpacity:    f32,
	strokeOpacity:  f32,
	opacity:        f32, // (group opacity multiplies into its shapes: an approximation)
	strokeWidth:    f32,
	fillRule:       Vector_Fill_Rule,
	clipRule:       Vector_Fill_Rule,
	join:           Vector_Join,
	cap:            Vector_Cap,
	miterLimit:     f32,
	dash:           Vector_Dash,
	visible:        bool,
	xf:             [6]f32,
	group:          int,
	clip:           ^Vector_Clip, // a group's clip-path (its shapes inherit it)
}

@(private = "file")
Svg_Rule :: struct {
	selector: string, // "tag", ".class", "#id"
	decls:    string,
	order:    int,
}

@(private = "file")
Svg_Parser :: struct {
	x:        ^xml.Document,
	doc:      ^Vector_Doc,
	ids:      map[string]xml.Element_ID,
	rules:    [dynamic]Svg_Rule,
	viewport: [2]f32,
	warned:   map[string]bool,
	depth:    int,
}

@(private = "file")
XF_ID :: [6]f32{1, 0, 0, 1, 0, 0}

// Vector_LoadSVG parses SVG text into a document (ok=false: not an SVG).
Vector_LoadSVG :: proc(text: string, doc: ^Vector_Doc) -> (ok: bool) {
	doc^ = {}
	if vmem.arena_init_growing(&doc.arena) != nil do return false
	context.allocator = vmem.arena_allocator(&doc.arena)
	doc.shapes = make([dynamic]Vector_Shape)
	doc.groups = make([dynamic]Vector_Group)
	doc.warnings = make([dynamic]string)
	x, err := xml.parse_string(text, xml.Options{flags = {.Ignore_Unsupported}})
	if err != nil || x == nil || x.element_count == 0 {
		append(&doc.warnings, fmt.aprintf("not an XML file (%v)", err))
		return false
	}
	p := Svg_Parser{x = x, doc = doc}
	p.ids = make(map[string]xml.Element_ID)
	p.rules = make([dynamic]Svg_Rule)
	p.warned = make(map[string]bool)
	root := xml.Element_ID(0)
	if x.elements[root].ident != "svg" {
		append(&doc.warnings, "the root element isn't <svg>")
		return false
	}
	// Ids and <style> rules first (references may point forward).
	for el, i in x.elements {
		if id, has := attr(&x.elements[i], "id"); has do p.ids[id] = xml.Element_ID(i)
		if el.ident == "style" do parse_css(&p, element_text(&p, xml.Element_ID(i)))
	}
	// The document box: width / height (default: the viewBox), the viewBox
	// mapped onto it (preserveAspectRatio xMidYMid meet).
	r := &x.elements[root]
	vb, hasVB := parse_numbers4(attr_or(r, "viewBox", ""))
	// (A percentage size - "100%" from Affinity - is of the viewBox.)
	w := length(attr_or(r, "width", ""), vb[2] if hasVB else 300, vb[2] if hasVB else 300)
	h := length(attr_or(r, "height", ""), vb[3] if hasVB else 150, vb[3] if hasVB else 150)
	if attr_or(r, "width", "") == "" && hasVB do w = vb[2]
	if attr_or(r, "height", "") == "" && hasVB do h = vb[3]
	doc.size = {w, h}
	p.viewport = {vb[2], vb[3]} if hasVB else {w, h}
	st := Svg_State{
		fill = {kind = .Color, color = {0, 0, 0, 255}}, stroke = {kind = .None},
		color = {0, 0, 0, 255}, fillOpacity = 1, strokeOpacity = 1, opacity = 1,
		strokeWidth = 1, miterLimit = 4, visible = true, xf = XF_ID, group = -1,
	}
	if hasVB && vb[2] > 0 && vb[3] > 0 {
		s := min(w / vb[2], h / vb[3])
		tx := (w - vb[2] * s) * 0.5 - vb[0] * s
		ty := (h - vb[3] * s) * 0.5 - vb[1] * s
		st.xf = {s, 0, 0, s, tx, ty}
	}
	walk(&p, root, st)
	vector_doc_visible(doc)
	doc.drawn = Vector_ShapesBounds(Vector_DocShapes(doc, -1))
	return true
}

// Vector_DocShapes: what a part draws (-1: the document) - its shapes less
// the hidden groups inside it (a hidden group drawn as the part itself
// shows: swap frames hidden in the file).
Vector_DocShapes :: proc(doc: ^Vector_Doc, part: int) -> []Vector_Shape {
	if part + 1 < len(doc.visible) && doc.visible[part + 1] != nil do return doc.visible[part + 1]
	if part < 0 || part >= len(doc.groups) do return doc.shapes[:]
	g := doc.groups[part]
	return doc.shapes[g.first:g.first + g.count]
}

// vector_doc_visible: the parts with hidden groups inside get their shapes
// without them (copies sharing the paths; made again after a rescale).
@(private)
vector_doc_visible :: proc(doc: ^Vector_Doc) {
	doc.visible = nil
	any := false
	for g in doc.groups do any ||= g.hidden
	if !any do return
	context.allocator = vmem.arena_allocator(&doc.arena)
	doc.visible = make([][]Vector_Shape, len(doc.groups) + 1)
	inside :: proc(doc: ^Vector_Doc, g, part: int) -> bool {
		for p := doc.groups[g].parent; p >= 0; p = doc.groups[p].parent do if p == part do return true
		return part < 0
	}
	for part in -1 ..< len(doc.groups) {
		first, count := 0, len(doc.shapes)
		if part >= 0 do first, count = doc.groups[part].first, doc.groups[part].count
		skip := make([]bool, count, context.temp_allocator)
		n := 0
		for g, gi in doc.groups do if g.hidden && gi != part && inside(doc, gi, part) {
			for i in g.first ..< g.first + g.count do if !skip[i - first] {skip[i - first] = true; n += 1}
		}
		if n == 0 do continue
		out := make([]Vector_Shape, count - n)
		k := 0
		for i in 0 ..< count do if !skip[i] {out[k] = doc.shapes[first + i]; k += 1}
		doc.visible[part + 1] = out
	}
}

// Vector_DocScale scales a document (an import's vector_scale): points,
// stroke widths, dashes, gradients, clips and its box.
Vector_DocScale :: proc(doc: ^Vector_Doc, s: f32) {
	if s == 1 || s <= 0 do return
	seen := make(map[^Vector_Clip]bool, allocator = context.temp_allocator)
	scale_paint :: proc(p: ^Vector_Paint, s: f32) {
		if p.kind == .Solid do return
		t := p.transform if p.transform != {} else [6]f32{1, 0, 0, 1, 0, 0}
		p.transform = {t[0] * s, t[1] * s, t[2] * s, t[3] * s, t[4] * s, t[5] * s}
	}
	for &sh in doc.shapes {
		for &pt in sh.path.pts do pt *= s
		sh.style.strokeWidth *= s
		for i in 0 ..< int(sh.style.dash.count) do sh.style.dash.values[i] *= s
		sh.style.dash.offset *= s
		scale_paint(&sh.style.fillPaint, s)
		scale_paint(&sh.style.strokePaint, s)
		if sh.clip != nil && sh.clip not_in seen {
			seen[sh.clip] = true
			for &pt in sh.clip.path.pts do pt *= s
		}
	}
	doc.min *= s
	doc.size *= s
	doc.drawn *= s
	vector_doc_visible(doc) // (the copies have the old styles)
}

// Vector_ShapesBounds: the box the shapes' points cover, widened by half
// their stroke widths (control points included: a little generous);
// strokes = false: the geometry only.
Vector_ShapesBounds :: proc(shapes: []Vector_Shape, strokes := true) -> [4]f32 {
	b := [4]f32{max(f32), max(f32), min(f32), min(f32)}
	for &s in shapes {
		pad := s.style.strokeWidth * 0.5 * max(s.style.miterLimit, 1) if s.style.stroke && strokes else 0
		for pt in s.path.pts {
			b[0] = min(b[0], pt.x - pad); b[1] = min(b[1], pt.y - pad)
			b[2] = max(b[2], pt.x + pad); b[3] = max(b[3], pt.y + pad)
		}
	}
	if b[0] > b[2] do return {}
	return b
}

// --- warnings -----------------------------------------------------------------------

@(private = "file")
warn_once :: proc(p: ^Svg_Parser, what: string) {
	if what in p.warned do return
	p.warned[what] = true
	append(&p.doc.warnings, strings.clone(what))
}

// --- the walk -----------------------------------------------------------------------

@(private = "file")
walk :: proc(p: ^Svg_Parser, id: xml.Element_ID, parent: Svg_State) {
	p.depth += 1
	defer p.depth -= 1
	if p.depth > 64 {warn_once(p, "elements nested too deep (or a <use> loop): skipped"); return}
	el := &p.x.elements[id]
	if el.kind != .Element do return
	tag := strip_ns(el.ident)
	switch tag {
	case "defs", "clipPath", "linearGradient", "radialGradient", "style", "title", "desc", "metadata", "symbol", "mask", "pattern", "marker", "filter":
		if tag == "mask" do warn_once(p, "masks aren't supported (yet): ignored")
		if tag == "pattern" do warn_once(p, "pattern fills aren't supported: ignored")
		if tag == "filter" do warn_once(p, "filters aren't supported: ignored")
		return // (referenced, not drawn)
	case "text", "tspan", "textPath":
		warn_once(p, "text isn't supported: convert it to outlines (Inkscape: Path > Object to Path; Illustrator: Create Outlines)")
		return
	case "image":
		warn_once(p, "embedded images aren't supported: ignored")
		return
	case "foreignObject", "script", "switch", "a":
		if tag == "a" || tag == "switch" do break // (their children draw)
		return
	}
	st := style_of(p, el, parent)
	hiddenGroup := false
	if !st.visible {
		// A hidden group is kept (a swap frame: shown when picked); other hidden elements are dropped.
		if tag != "g" do return
		hiddenGroup = true
		st.visible = true
	}
	if t, has := attr(el, "transform"); has do st.xf = xf_mul(parent.xf, parse_transform(t))
	switch tag {
	case "svg", "g", "a", "switch":
		if tag == "svg" && id != 0 {
			// A nested svg: its x / y.
			st.xf = xf_mul(st.xf, {1, 0, 0, 1, length(attr_or(el, "x", ""), 0, p.viewport.x), length(attr_or(el, "y", ""), 0, p.viewport.y)})
		}
		gi := -1
		if tag == "g" || (tag == "svg" && id != 0) {
			gi = len(p.doc.groups)
			name := attr_or(el, "inkscape:label", "")
			if name == "" do name = attr_or(el, "data-name", "")
			if name == "" do name = attr_or(el, "id", "")
			append(&p.doc.groups, Vector_Group{name = strings.clone(name), parent = parent.group, first = len(p.doc.shapes), hidden = hiddenGroup})
			st.group = gi
		}
		// A clip-path on a group clips everything in it (Figma exports do this).
		if c := style_value(p, el, "clip-path"); c != "" && c != "none" {
			if k := resolve_clip(p, c, st); k != nil {
				if st.clip != nil do warn_once(p, "nested clip paths: the inner one is used")
				st.clip = k
			}
		}
		for v in el.value do if child, ok := v.(xml.Element_ID); ok do walk(p, child, st)
		if gi >= 0 do p.doc.groups[gi].count = len(p.doc.shapes) - p.doc.groups[gi].first
	case "use":
		ref := strings.trim_prefix(attr_or(el, "href", attr_or(el, "xlink:href", "")), "#")
		target, found := p.ids[ref]
		if !found {warn_once(p, fmt.tprintf("<use> of a missing element #%s", ref)); return}
		st.xf = xf_mul(st.xf, {1, 0, 0, 1, length(attr_or(el, "x", ""), 0, p.viewport.x), length(attr_or(el, "y", ""), 0, p.viewport.y)})
		if strip_ns(p.x.elements[target].ident) == "symbol" {
			for v in p.x.elements[target].value do if child, ok := v.(xml.Element_ID); ok do walk(p, child, st)
		} else {
			walk(p, target, st)
		}
	case "path", "rect", "circle", "ellipse", "line", "polyline", "polygon":
		path: Vector_Path
		Vector_Path_Init(&path)
		geometry(p, el, tag, &path)
		if len(path.cmds) == 0 do return
		add_shape(p, el, &path, st)
	}
}

// add_shape: the element's geometry in document space with its style.
@(private = "file")
add_shape :: proc(p: ^Svg_Parser, el: ^xml.Element, path: ^Vector_Path, st: Svg_State) {
	box := path_bounds(path) // (in the element's own space: gradient bbox units)
	for &pt in path.pts do pt = xf_point(st.xf, pt)
	s := Vector_Shape{path = path^, style = VECTOR_STYLE_DEFAULT}
	s.style.opacity = st.opacity
	k := xf_scale_of(st.xf)
	if fill, ok := resolve_paint(p, st.fill, st, st.fillOpacity, box, &s.style.fillPaint); ok {
		s.style.fill = true
		s.style.fillColor = fill
	} else do s.style.fill = false
	if stroke, ok := resolve_paint(p, st.stroke, st, st.strokeOpacity, box, &s.style.strokePaint); ok && st.strokeWidth > 0 {
		s.style.stroke = true
		s.style.strokeColor = stroke
		s.style.strokeWidth = st.strokeWidth * k
		s.style.dash = st.dash
		for i in 0 ..< int(s.style.dash.count) do s.style.dash.values[i] *= k
		s.style.dash.offset *= k
	}
	if !s.style.fill && !s.style.stroke do return
	s.style.fillRule = st.fillRule
	s.style.join = st.join
	s.style.cap = st.cap
	s.style.miterLimit = st.miterLimit
	s.clip = st.clip
	if c := style_value(p, el, "clip-path"); c != "" && c != "none" {
		if k := resolve_clip(p, c, st); k != nil {
			if s.clip != nil do warn_once(p, "nested clip paths: the inner one is used")
			s.clip = k
		}
	}
	append(&p.doc.shapes, s)
}

// --- geometry -----------------------------------------------------------------------

@(private = "file")
geometry :: proc(p: ^Svg_Parser, el: ^xml.Element, tag: string, path: ^Vector_Path) {
	vw, vh := p.viewport.x, p.viewport.y
	diag := math.sqrt(vw * vw + vh * vh) / math.SQRT_TWO
	num :: proc(el: ^xml.Element, name: string, rel: f32) -> f32 {return length(attr_or(el, name, ""), 0, rel)}
	switch tag {
	case "path":
		parse_path_data(attr_or(el, "d", ""), path)
	case "rect":
		x, y, w, h := num(el, "x", vw), num(el, "y", vh), num(el, "width", vw), num(el, "height", vh)
		if w <= 0 || h <= 0 do return
		rx, hasRx := attr(el, "rx")
		ry, hasRy := attr(el, "ry")
		r := [2]f32{length(rx, 0, vw), length(ry, 0, vh)}
		if hasRx && !hasRy do r.y = r.x
		if hasRy && !hasRx do r.x = r.y
		r = {min(r.x, w / 2), min(r.y, h / 2)}
		if r.x <= 0 || r.y <= 0 {
			Vector_Rect(path, {x, y}, {x + w, y + h})
			return
		}
		K :: 0.5522847498
		k := r * K
		Vector_MoveTo(path, {x + r.x, y})
		Vector_LineTo(path, {x + w - r.x, y})
		Vector_CubicTo(path, {x + w - r.x + k.x, y}, {x + w, y + r.y - k.y}, {x + w, y + r.y})
		Vector_LineTo(path, {x + w, y + h - r.y})
		Vector_CubicTo(path, {x + w, y + h - r.y + k.y}, {x + w - r.x + k.x, y + h}, {x + w - r.x, y + h})
		Vector_LineTo(path, {x + r.x, y + h})
		Vector_CubicTo(path, {x + r.x - k.x, y + h}, {x, y + h - r.y + k.y}, {x, y + h - r.y})
		Vector_LineTo(path, {x, y + r.y})
		Vector_CubicTo(path, {x, y + r.y - k.y}, {x + r.x - k.x, y}, {x + r.x, y})
		Vector_Close(path)
	case "circle":
		r := num(el, "r", diag)
		if r > 0 do Vector_Ellipse(path, {num(el, "cx", vw), num(el, "cy", vh)}, {r, r})
	case "ellipse":
		rx, ry := num(el, "rx", vw), num(el, "ry", vh)
		if rx > 0 && ry > 0 do Vector_Ellipse(path, {num(el, "cx", vw), num(el, "cy", vh)}, {rx, ry})
	case "line":
		Vector_MoveTo(path, {num(el, "x1", vw), num(el, "y1", vh)})
		Vector_LineTo(path, {num(el, "x2", vw), num(el, "y2", vh)})
	case "polyline", "polygon":
		ns := parse_number_list(attr_or(el, "points", ""), context.temp_allocator)
		for i := 0; i + 1 < len(ns); i += 2 {
			if i == 0 do Vector_MoveTo(path, {ns[0], ns[1]})
			else do Vector_LineTo(path, {ns[i], ns[i + 1]})
		}
		if tag == "polygon" && len(ns) >= 6 do Vector_Close(path)
	}
}

@(private = "file")
path_bounds :: proc(path: ^Vector_Path) -> [4]f32 {
	if len(path.pts) == 0 do return {}
	b := [4]f32{max(f32), max(f32), min(f32), min(f32)}
	for pt in path.pts {
		b[0] = min(b[0], pt.x); b[1] = min(b[1], pt.y)
		b[2] = max(b[2], pt.x); b[3] = max(b[3], pt.y)
	}
	return b
}

// --- path data ----------------------------------------------------------------------

// Vector_ParsePathData appends SVG path data ("M10 10 L20 20 ...") to a path.
Vector_ParsePathData :: proc(d: string, path: ^Vector_Path) {parse_path_data(d, path)}

@(private = "file")
parse_path_data :: proc(d: string, path: ^Vector_Path) {
	s := d
	i := 0
	cur, start, lastCtrl: [2]f32
	lastCmd: u8
	cmd: u8
	skip_ws :: proc(s: string, i: ^int) {
		for i^ < len(s) && (s[i^] == ' ' || s[i^] == ',' || s[i^] == '\t' || s[i^] == '\n' || s[i^] == '\r') do i^ += 1
	}
	next_num :: proc(s: string, i: ^int) -> (f32, bool) {
		skip_ws(s, i)
		j := i^
		if j < len(s) && (s[j] == '-' || s[j] == '+') do j += 1
		dot, digits := false, false
		for j < len(s) {
			c := s[j]
			if c >= '0' && c <= '9' {digits = true; j += 1}
			else if c == '.' && !dot {dot = true; j += 1}
			else do break
		}
		if !digits do return 0, false
		if j < len(s) && (s[j] == 'e' || s[j] == 'E') {
			k := j + 1
			if k < len(s) && (s[k] == '-' || s[k] == '+') do k += 1
			if k < len(s) && s[k] >= '0' && s[k] <= '9' {
				for k < len(s) && s[k] >= '0' && s[k] <= '9' do k += 1
				j = k
			}
		}
		v, _ := strconv.parse_f32(s[i^:j])
		i^ = j
		return v, true
	}
	next_flag :: proc(s: string, i: ^int) -> (bool, bool) {
		// (Arc flags may be packed without separators: "a10 10 0 01 20 20".)
		skip_ws(s, i)
		if i^ < len(s) && (s[i^] == '0' || s[i^] == '1') {
			v := s[i^] == '1'
			i^ += 1
			return v, true
		}
		return false, false
	}
	for {
		skip_ws(s, &i)
		if i >= len(s) do break
		c := s[i]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') {
			cmd = c
			i += 1
		} else if cmd == 0 {
			return // (data before any command)
		} else if cmd == 'M' {
			cmd = 'L' // (implicit lines after a move)
		} else if cmd == 'm' {
			cmd = 'l'
		} else if cmd == 'z' || cmd == 'Z' {
			return
		}
		rel := cmd >= 'a'
		base := cur if rel else [2]f32{}
		switch cmd {
		case 'M', 'm':
			x, ok1 := next_num(s, &i); y, ok2 := next_num(s, &i)
			if !ok1 || !ok2 do return
			cur = base + {x, y}
			start = cur
			Vector_MoveTo(path, cur)
		case 'L', 'l':
			x, ok1 := next_num(s, &i); y, ok2 := next_num(s, &i)
			if !ok1 || !ok2 do return
			cur = base + {x, y}
			Vector_LineTo(path, cur)
		case 'H', 'h':
			x, ok := next_num(s, &i)
			if !ok do return
			cur.x = cur.x + x if rel else x
			Vector_LineTo(path, cur)
		case 'V', 'v':
			y, ok := next_num(s, &i)
			if !ok do return
			cur.y = cur.y + y if rel else y
			Vector_LineTo(path, cur)
		case 'C', 'c':
			v: [6]f32
			for k in 0 ..< 6 {n, ok := next_num(s, &i); if !ok do return; v[k] = n}
			c1, c2, e := base + {v[0], v[1]}, base + {v[2], v[3]}, base + {v[4], v[5]}
			Vector_CubicTo(path, c1, c2, e)
			lastCtrl = c2
			cur = e
		case 'S', 's':
			v: [4]f32
			for k in 0 ..< 4 {n, ok := next_num(s, &i); if !ok do return; v[k] = n}
			c1 := cur
			if lastCmd == 'C' || lastCmd == 'c' || lastCmd == 'S' || lastCmd == 's' do c1 = 2 * cur - lastCtrl
			c2, e := base + {v[0], v[1]}, base + {v[2], v[3]}
			Vector_CubicTo(path, c1, c2, e)
			lastCtrl = c2
			cur = e
		case 'Q', 'q':
			v: [4]f32
			for k in 0 ..< 4 {n, ok := next_num(s, &i); if !ok do return; v[k] = n}
			c, e := base + {v[0], v[1]}, base + {v[2], v[3]}
			Vector_QuadTo(path, c, e)
			lastCtrl = c
			cur = e
		case 'T', 't':
			v: [2]f32
			for k in 0 ..< 2 {n, ok := next_num(s, &i); if !ok do return; v[k] = n}
			c := cur
			if lastCmd == 'Q' || lastCmd == 'q' || lastCmd == 'T' || lastCmd == 't' do c = 2 * cur - lastCtrl
			e := base + {v[0], v[1]}
			Vector_QuadTo(path, c, e)
			lastCtrl = c
			cur = e
		case 'A', 'a':
			rx, ok1 := next_num(s, &i); ry, ok2 := next_num(s, &i); rot, ok3 := next_num(s, &i)
			large, ok4 := next_flag(s, &i); sweep, ok5 := next_flag(s, &i)
			x, ok6 := next_num(s, &i); y, ok7 := next_num(s, &i)
			if !(ok1 && ok2 && ok3 && ok4 && ok5 && ok6 && ok7) do return
			e := base + {x, y}
			arc_to_cubics(path, cur, e, {rx, ry}, rot, large, sweep)
			cur = e
		case 'Z', 'z':
			Vector_Close(path)
			cur = start
		case:
			return
		}
		lastCmd = cmd
	}
}

// arc_to_cubics: an SVG elliptical arc as cubic Beziers (the SVG
// implementation notes' endpoint -> centre conversion, then <= 90 degree
// segments).
@(private = "file")
arc_to_cubics :: proc(path: ^Vector_Path, p0, p1: [2]f32, radii: [2]f32, rotDeg: f32, large, sweep: bool) {
	if p0 == p1 do return
	rx, ry := abs(radii.x), abs(radii.y)
	if rx < 1e-6 || ry < 1e-6 {Vector_LineTo(path, p1); return}
	phi := rotDeg * math.RAD_PER_DEG
	cp, sp := math.cos(phi), math.sin(phi)
	d := (p0 - p1) * 0.5
	x1 := cp * d.x + sp * d.y
	y1 := -sp * d.x + cp * d.y
	lambda := (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
	if lambda > 1 {s := math.sqrt(lambda); rx *= s; ry *= s}
	num := rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
	den := rx * rx * y1 * y1 + ry * ry * x1 * x1
	coef := math.sqrt(max(num / den, 0)) if den > 0 else 0
	if large == sweep do coef = -coef
	cx1 := coef * rx * y1 / ry
	cy1 := -coef * ry * x1 / rx
	mid := (p0 + p1) * 0.5
	center := [2]f32{cp * cx1 - sp * cy1 + mid.x, sp * cx1 + cp * cy1 + mid.y}
	angle :: proc(u, v: [2]f32) -> f32 {
		a := math.atan2(u.x * v.y - u.y * v.x, u.x * v.x + u.y * v.y)
		return a
	}
	u := [2]f32{(x1 - cx1) / rx, (y1 - cy1) / ry}
	v := [2]f32{(-x1 - cx1) / rx, (-y1 - cy1) / ry}
	theta := angle({1, 0}, u)
	delta := angle(u, v)
	if !sweep && delta > 0 do delta -= 2 * math.PI
	if sweep && delta < 0 do delta += 2 * math.PI
	segs := max(1, int(math.ceil(abs(delta) / (math.PI / 2) - 1e-4)))
	step := delta / f32(segs)
	k := 4.0 / 3.0 * math.tan(step / 4)
	pt :: proc(c: [2]f32, rx, ry, cp, sp, a: f32) -> [2]f32 {
		x, y := rx * math.cos(a), ry * math.sin(a)
		return {c.x + cp * x - sp * y, c.y + sp * x + cp * y}
	}
	dt :: proc(rx, ry, cp, sp, a: f32) -> [2]f32 {
		x, y := -rx * math.sin(a), ry * math.cos(a)
		return {cp * x - sp * y, sp * x + cp * y}
	}
	a := theta
	for s in 0 ..< segs {
		b := a + step
		q0 := pt(center, rx, ry, cp, sp, a)
		q3 := pt(center, rx, ry, cp, sp, b) if s < segs - 1 else p1
		Vector_CubicTo(path, q0 + dt(rx, ry, cp, sp, a) * k, q3 - dt(rx, ry, cp, sp, b) * k, q3)
		a = b
	}
}

// --- transforms ---------------------------------------------------------------------

@(private = "file")
xf_point :: #force_inline proc(xf: [6]f32, p: [2]f32) -> [2]f32 {
	return {xf[0] * p.x + xf[2] * p.y + xf[4], xf[1] * p.x + xf[3] * p.y + xf[5]}
}

@(private = "file")
xf_mul :: proc(a, b: [6]f32) -> [6]f32 {
	return {
		a[0] * b[0] + a[2] * b[1], a[1] * b[0] + a[3] * b[1],
		a[0] * b[2] + a[2] * b[3], a[1] * b[2] + a[3] * b[3],
		a[0] * b[4] + a[2] * b[5] + a[4], a[1] * b[4] + a[3] * b[5] + a[5],
	}
}

@(private = "file")
xf_scale_of :: proc(xf: [6]f32) -> f32 {return math.sqrt(abs(xf[0] * xf[3] - xf[1] * xf[2]))}

// Vector_ParseTransform: an SVG transform list as a 2x3 matrix.
Vector_ParseTransform :: proc(s: string) -> [6]f32 {return parse_transform(s)}

@(private = "file")
parse_transform :: proc(s: string) -> [6]f32 {
	m := XF_ID
	rest := s
	for {
		rest = strings.trim_left(rest, " ,\t\n\r")
		open := strings.index_byte(rest, '(')
		close := strings.index_byte(rest, ')')
		if open < 0 || close < open do break
		name := strings.trim_space(rest[:open])
		args := parse_number_list(rest[open + 1:close], context.temp_allocator)
		rest = rest[close + 1:]
		a :: proc(args: []f32, i: int, def: f32) -> f32 {return args[i] if i < len(args) else def}
		t := XF_ID
		switch name {
		case "matrix":
			if len(args) >= 6 do t = {args[0], args[1], args[2], args[3], args[4], args[5]}
		case "translate":
			t = {1, 0, 0, 1, a(args, 0, 0), a(args, 1, 0)}
		case "scale":
			sx := a(args, 0, 1)
			t = {sx, 0, 0, a(args, 1, sx), 0, 0}
		case "rotate":
			r := a(args, 0, 0) * math.RAD_PER_DEG
			co, si := math.cos(r), math.sin(r)
			t = {co, si, -si, co, 0, 0}
			if len(args) >= 3 {
				cx, cy := args[1], args[2]
				t = xf_mul(xf_mul({1, 0, 0, 1, cx, cy}, t), {1, 0, 0, 1, -cx, -cy})
			}
		case "skewX":
			t = {1, 0, math.tan(a(args, 0, 0) * math.RAD_PER_DEG), 1, 0, 0}
		case "skewY":
			t = {1, math.tan(a(args, 0, 0) * math.RAD_PER_DEG), 0, 1, 0, 0}
		}
		m = xf_mul(m, t)
	}
	return m
}

// --- numbers and lengths ------------------------------------------------------------

@(private = "file")
parse_number_list :: proc(s: string, allocator := context.allocator) -> []f32 {
	out := make([dynamic]f32, allocator)
	i := 0
	for i < len(s) {
		for i < len(s) && (s[i] == ' ' || s[i] == ',' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r') do i += 1
		if i >= len(s) do break
		j := i
		if s[j] == '-' || s[j] == '+' do j += 1
		dot := false
		for j < len(s) && ((s[j] >= '0' && s[j] <= '9') || (s[j] == '.' && !dot)) {
			if s[j] == '.' do dot = true
			j += 1
		}
		if j < len(s) && (s[j] == 'e' || s[j] == 'E') {
			j += 1
			if j < len(s) && (s[j] == '-' || s[j] == '+') do j += 1
			for j < len(s) && s[j] >= '0' && s[j] <= '9' do j += 1
		}
		if j == i {i += 1; continue}
		v, _ := strconv.parse_f32(s[i:j])
		append(&out, v)
		i = j
	}
	return out[:]
}

@(private = "file")
parse_numbers4 :: proc(s: string) -> ([4]f32, bool) {
	ns := parse_number_list(s, context.temp_allocator)
	if len(ns) < 4 do return {}, false
	return {ns[0], ns[1], ns[2], ns[3]}, true
}

// length: "12", "12px", "9pt", "50%" (of rel), ... -> px; def when empty.
@(private = "file")
length :: proc(s: string, def: f32, rel: f32) -> f32 {
	t := strings.trim_space(s)
	if t == "" do return def
	unit := 1.0
	n := t
	switch {
	case strings.has_suffix(t, "%"): return parse_f(t[:len(t) - 1]) / 100 * rel
	case strings.has_suffix(t, "px"): n = t[:len(t) - 2]
	case strings.has_suffix(t, "pt"): n = t[:len(t) - 2]; unit = 96.0 / 72
	case strings.has_suffix(t, "pc"): n = t[:len(t) - 2]; unit = 16
	case strings.has_suffix(t, "mm"): n = t[:len(t) - 2]; unit = 96.0 / 25.4
	case strings.has_suffix(t, "cm"): n = t[:len(t) - 2]; unit = 96.0 / 2.54
	case strings.has_suffix(t, "in"): n = t[:len(t) - 2]; unit = 96
	case strings.has_suffix(t, "em"): n = t[:len(t) - 2]; unit = 16
	}
	return parse_f(n) * f32(unit)
}

@(private = "file")
parse_f :: proc(s: string) -> f32 {
	v, _ := strconv.parse_f32(strings.trim_space(s))
	return v
}

// --- attributes, CSS and style ------------------------------------------------------

@(private = "file")
strip_ns :: proc(s: string) -> string {
	if i := strings.index_byte(s, ':'); i >= 0 && !strings.has_prefix(s, "xlink") do return s[i + 1:]
	return s
}

@(private = "file")
attr :: proc(el: ^xml.Element, name: string) -> (string, bool) {
	for a in el.attribs do if a.key == name do return a.val, true
	return "", false
}

@(private = "file")
attr_or :: proc(el: ^xml.Element, name, def: string) -> string {
	if v, ok := attr(el, name); ok do return v
	return def
}

@(private = "file")
element_text :: proc(p: ^Svg_Parser, id: xml.Element_ID) -> string {
	b := strings.builder_make(context.temp_allocator)
	for v in p.x.elements[id].value do if s, ok := v.(string); ok do strings.write_string(&b, s)
	return strings.to_string(b)
}

// parse_css: "sel, sel { decls }" rules (comments dropped; @rules skipped).
@(private = "file")
parse_css :: proc(p: ^Svg_Parser, text: string) {
	t := text
	// (Strip comments and CDATA markers.)
	for {
		a := strings.index(t, "/*")
		if a < 0 do break
		b := strings.index(t[a:], "*/")
		if b < 0 {t = t[:a]; break}
		t = strings.concatenate({t[:a], t[a + b + 2:]}, context.temp_allocator)
	}
	t, _ = strings.replace_all(t, "<![CDATA[", "", context.temp_allocator)
	t, _ = strings.replace_all(t, "]]>", "", context.temp_allocator)
	for {
		open := strings.index_byte(t, '{')
		close := strings.index_byte(t, '}')
		if open < 0 || close < open do break
		sels := strings.trim_space(t[:open])
		decls := t[open + 1:close]
		t = t[close + 1:]
		if strings.has_prefix(sels, "@") do continue
		for sel in strings.split(sels, ",", context.temp_allocator) {
			ss := strings.trim_space(sel)
			if ss == "" do continue
			append(&p.rules, Svg_Rule{selector = strings.clone(ss), decls = strings.clone(decls), order = len(p.rules)})
		}
	}
}

// style_value: a property from the element's CSS rules and style="" (not
// inherited; "" when unset) - presentation attributes come first, then
// rules by specificity (tag < class < id), then style="".
@(private = "file")
style_value :: proc(p: ^Svg_Parser, el: ^xml.Element, name: string) -> string {
	v := attr_or(el, name, "")
	classes := strings.fields(attr_or(el, "class", ""), context.temp_allocator)
	id := attr_or(el, "id", "")
	tag := strip_ns(el.ident)
	for spec in 0 ..< 3 {
		for r in p.rules {
			match := false
			switch spec {
			case 0: match = r.selector == tag || r.selector == "*"
			case 1:
				if strings.has_prefix(r.selector, ".") do for c in classes do if c == r.selector[1:] do match = true
			case 2: match = id != "" && r.selector == strings.concatenate({"#", id}, context.temp_allocator)
			}
			if match do if d := decl(r.decls, name); d != "" do v = d
		}
	}
	if d := decl(attr_or(el, "style", ""), name); d != "" do v = d
	return strings.trim_space(v)
}

@(private = "file")
decl :: proc(decls, name: string) -> string {
	for part in strings.split(decls, ";", context.temp_allocator) {
		colon := strings.index_byte(part, ':')
		if colon < 0 do continue
		if strings.trim_space(part[:colon]) == name {
			v := strings.trim_space(part[colon + 1:])
			v = strings.trim_suffix(v, "!important")
			return strings.trim_space(v)
		}
	}
	return ""
}

@(private = "file")
style_of :: proc(p: ^Svg_Parser, el: ^xml.Element, parent: Svg_State) -> Svg_State {
	st := parent
	st.opacity = parent.opacity
	sv :: proc(p: ^Svg_Parser, el: ^xml.Element, name: string) -> string {
		v := style_value(p, el, name)
		return "" if v == "inherit" else v
	}
	if v := sv(p, el, "color"); v != "" {if c, ok := parse_color(v); ok do st.color = c}
	if v := sv(p, el, "fill"); v != "" do st.fill = parse_paint(v)
	if v := sv(p, el, "stroke"); v != "" do st.stroke = parse_paint(v)
	if v := sv(p, el, "fill-opacity"); v != "" do st.fillOpacity = clamp(opacity_value(v), 0, 1)
	if v := sv(p, el, "stroke-opacity"); v != "" do st.strokeOpacity = clamp(opacity_value(v), 0, 1)
	if v := sv(p, el, "opacity"); v != "" do st.opacity = parent.opacity * clamp(opacity_value(v), 0, 1)
	if v := sv(p, el, "stroke-width"); v != "" do st.strokeWidth = length(v, 1, math.sqrt(p.viewport.x * p.viewport.x + p.viewport.y * p.viewport.y) / math.SQRT_TWO)
	if v := sv(p, el, "fill-rule"); v != "" do st.fillRule = .EvenOdd if v == "evenodd" else .NonZero
	if v := sv(p, el, "clip-rule"); v != "" do st.clipRule = .EvenOdd if v == "evenodd" else .NonZero
	if v := sv(p, el, "stroke-linejoin"); v != "" do st.join = .Round if v == "round" else (.Bevel if v == "bevel" else .Miter)
	if v := sv(p, el, "stroke-linecap"); v != "" do st.cap = .Round if v == "round" else (.Square if v == "square" else .Butt)
	if v := sv(p, el, "stroke-miterlimit"); v != "" do st.miterLimit = max(parse_f(v), 1)
	if v := sv(p, el, "stroke-dasharray"); v != "" {
		st.dash = {}
		if v != "none" {
			ns := parse_number_list(v, context.temp_allocator)
			n := min(len(ns), 8)
			for k in 0 ..< n do st.dash.values[k] = max(ns[k], 0)
			st.dash.count = u8(n)
			if n % 2 == 1 && n * 2 <= 8 {
				for k in 0 ..< n do st.dash.values[n + k] = st.dash.values[k]
				st.dash.count = u8(n * 2)
			}
		}
	}
	if v := sv(p, el, "stroke-dashoffset"); v != "" do st.dash.offset = parse_f(v)
	if v := sv(p, el, "display"); v == "none" do st.visible = false
	if v := sv(p, el, "visibility"); v == "hidden" || v == "collapse" do st.visible = false
	return st
}

@(private = "file")
opacity_value :: proc(v: string) -> f32 {
	if strings.has_suffix(v, "%") do return parse_f(v[:len(v) - 1]) / 100
	return parse_f(v)
}

@(private = "file")
parse_paint :: proc(v: string) -> Svg_Paint {
	switch {
	case v == "none": return {kind = .None}
	case v == "currentColor": return {kind = .Current}
	case strings.has_prefix(v, "url("):
		close := strings.index_byte(v, ')')
		ref := strings.trim_space(v[4:close]) if close > 4 else ""
		ref = strings.trim(ref, "'\"")
		pnt := Svg_Paint{kind = .Url, url = strings.trim_prefix(ref, "#")}
		// A fallback colour after the url: "url(#g) red".
		if close >= 0 && close + 1 < len(v) {
			if c, ok := parse_color(strings.trim_space(v[close + 1:])); ok do pnt.color = c
		}
		return pnt
	}
	if c, ok := parse_color(v); ok do return {kind = .Color, color = c}
	return {kind = .None}
}

// resolve_paint: the shape's colour (solid; alpha with the opacity) or, for
// a gradient, its paint (filled in `out`; the colour is then white).
@(private = "file")
resolve_paint :: proc(p: ^Svg_Parser, pnt: Svg_Paint, st: Svg_State, opacity: f32, box: [4]f32, out: ^Vector_Paint) -> (col: [4]u8, ok: bool) {
	switch pnt.kind {
	case .None, .Inherit: return {}, false
	case .Color:
		c := pnt.color
		c.a = u8(f32(c.a) * opacity + 0.5)
		return c, c.a > 0
	case .Current:
		c := st.color
		c.a = u8(f32(c.a) * opacity + 0.5)
		return c, c.a > 0
	case .Url:
		if gradient(p, pnt.url, st.xf, box, opacity, out) do return {255, 255, 255, 255}, true
		// A fallback colour, or nothing.
		if pnt.color.a > 0 {
			c := pnt.color
			c.a = u8(f32(c.a) * opacity + 0.5)
			return c, true
		}
		return {}, false
	}
	return {}, false
}

// gradient: a linearGradient / radialGradient (following href for stops and
// attributes) as a paint in document space.
@(private = "file")
gradient :: proc(p: ^Svg_Parser, id: string, xf: [6]f32, box: [4]f32, opacity: f32, out: ^Vector_Paint) -> bool {
	gid, found := p.ids[id]
	if !found do return false
	el := &p.x.elements[gid]
	tag := strip_ns(el.ident)
	if tag != "linearGradient" && tag != "radialGradient" {
		if tag == "pattern" do warn_once(p, "pattern fills aren't supported: ignored")
		return false
	}
	// An attribute from the gradient or the ones it inherits from (href).
	g_attr :: proc(p: ^Svg_Parser, gid: xml.Element_ID, name: string) -> (string, bool) {
		cur := gid
		for _ in 0 ..< 16 {
			e := &p.x.elements[cur]
			if v, ok := attr(e, name); ok do return v, true
			ref := strings.trim_prefix(attr_or(e, "href", attr_or(e, "xlink:href", "")), "#")
			next, ok := p.ids[ref]
			if ref == "" || !ok do break
			cur = next
		}
		return "", false
	}
	userSpace := false
	if u, ok := g_attr(p, gid, "gradientUnits"); ok do userSpace = u == "userSpaceOnUse"
	pnt := Vector_Paint{}
	if s, ok := g_attr(p, gid, "spreadMethod"); ok do pnt.spread = .Reflect if s == "reflect" else (.Repeat if s == "repeat" else .Pad)
	relW, relH := (p.viewport.x if userSpace else 1), (p.viewport.y if userSpace else 1)
	coord :: proc(p: ^Svg_Parser, gid: xml.Element_ID, name: string, def: f32, rel: f32, userSpace: bool) -> f32 {
		v, ok := g_attr(p, gid, name)
		if !ok do return def
		if strings.has_suffix(strings.trim_space(v), "%") do return parse_f(strings.trim_space(v)[:len(strings.trim_space(v)) - 1]) / 100 * (rel if userSpace else 1)
		return length(v, def, rel)
	}
	if tag == "linearGradient" {
		pnt.kind = .Linear
		pnt.p0 = {coord(p, gid, "x1", 0, relW, userSpace), coord(p, gid, "y1", 0, relH, userSpace)}
		pnt.p1 = {coord(p, gid, "x2", relW if userSpace else 1, relW, userSpace), coord(p, gid, "y2", 0, relH, userSpace)}
	} else {
		pnt.kind = .Radial
		diag := math.sqrt(relW * relW + relH * relH) / math.SQRT_TWO
		pnt.center = {coord(p, gid, "cx", 0.5 * relW, relW, userSpace), coord(p, gid, "cy", 0.5 * relH, relH, userSpace)}
		pnt.radius = coord(p, gid, "r", 0.5 * diag, diag, userSpace)
		if _, hasF := g_attr(p, gid, "fx"); hasF do warn_once(p, "radial gradient focal points (fx / fy) aren't supported: centred")
	}
	// Stops: the first gradient in the href chain that has any.
	stopsFrom := gid
	for _ in 0 ..< 16 {
		has := false
		for v in p.x.elements[stopsFrom].value do if c, ok := v.(xml.Element_ID); ok && strip_ns(p.x.elements[c].ident) == "stop" do has = true
		if has do break
		ref := strings.trim_prefix(attr_or(&p.x.elements[stopsFrom], "href", attr_or(&p.x.elements[stopsFrom], "xlink:href", "")), "#")
		next, ok := p.ids[ref]
		if ref == "" || !ok do break
		stopsFrom = next
	}
	last: f32 = 0
	for v in p.x.elements[stopsFrom].value {
		c, ok := v.(xml.Element_ID)
		if !ok || strip_ns(p.x.elements[c].ident) != "stop" || int(pnt.stopCount) >= VECTOR_MAX_STOPS do continue
		se := &p.x.elements[c]
		off := opacity_value(style_value(p, se, "offset")) if style_value(p, se, "offset") != "" else 0
		off = max(clamp(off, 0, 1), last)
		last = off
		col := [4]u8{0, 0, 0, 255}
		if cs := style_value(p, se, "stop-color"); cs != "" {if cc, ok2 := parse_color(cs); ok2 do col = cc}
		so: f32 = 1
		if os := style_value(p, se, "stop-opacity"); os != "" do so = clamp(opacity_value(os), 0, 1)
		col.a = u8(f32(col.a) * so * opacity + 0.5)
		pnt.stops[pnt.stopCount] = {off, col}
		pnt.stopCount += 1
	}
	if pnt.stopCount == 0 do return false
	if pnt.stopCount == 1 {
		// (One stop: a solid colour, as a two-stop gradient.)
		pnt.stops[1] = {1, pnt.stops[0].color}
		pnt.stopCount = 2
	}
	// Gradient space -> document space: the element's transform, the bounding
	// box (objectBoundingBox units), then gradientTransform.
	g := XF_ID
	if t, ok := g_attr(p, gid, "gradientTransform"); ok do g = parse_transform(t)
	m := xf
	if !userSpace {
		w, h := box[2] - box[0], box[3] - box[1]
		if w <= 0 || h <= 0 do return false
		m = xf_mul(m, {w, 0, 0, h, box[0], box[1]})
	}
	pnt.transform = xf_mul(m, g)
	out^ = pnt
	return true
}

// resolve_clip: a clip-path="url(#id)" as a clip in document space (its
// children's paths together; clipPathUnits userSpaceOnUse).
@(private = "file")
resolve_clip :: proc(p: ^Svg_Parser, ref: string, st: Svg_State) -> ^Vector_Clip {
	if !strings.has_prefix(ref, "url(") do return nil
	close := strings.index_byte(ref, ')')
	id := strings.trim_prefix(strings.trim(strings.trim_space(ref[4:close]), "'\""), "#") if close > 4 else ""
	cid, found := p.ids[id]
	if !found do return nil
	el := &p.x.elements[cid]
	if strip_ns(el.ident) != "clipPath" do return nil
	if u, ok := attr(el, "clipPathUnits"); ok && u == "objectBoundingBox" do warn_once(p, "clipPathUnits=objectBoundingBox isn't supported: user space")
	k := new(Vector_Clip)
	Vector_Path_Init(&k.path)
	xf := st.xf
	if t, ok := attr(el, "transform"); ok do xf = xf_mul(xf, parse_transform(t))
	rule := Vector_Fill_Rule.NonZero
	for v in el.value {
		c, ok := v.(xml.Element_ID)
		if !ok do continue
		ce := &p.x.elements[c]
		tag := strip_ns(ce.ident)
		cxf := xf
		if t, has := attr(ce, "transform"); has do cxf = xf_mul(xf, parse_transform(t))
		if tag == "use" {
			ref2 := strings.trim_prefix(attr_or(ce, "href", attr_or(ce, "xlink:href", "")), "#")
			target, ok2 := p.ids[ref2]
			if !ok2 do continue
			ce = &p.x.elements[target]
			tag = strip_ns(ce.ident)
		}
		path: Vector_Path
		Vector_Path_Init(&path, context.temp_allocator)
		geometry(p, ce, tag, &path)
		for pt, i in path.pts do path.pts[i] = xf_point(cxf, pt)
		append(&k.path.cmds, ..path.cmds[:])
		append(&k.path.pts, ..path.pts[:])
		if r := style_value(p, ce, "clip-rule"); r == "evenodd" do rule = .EvenOdd
	}
	k.rule = rule
	if len(k.path.cmds) == 0 do return nil
	return k
}

// --- colours ------------------------------------------------------------------------

// Vector_ParseColor: an SVG / CSS colour (#rgb, #rgba, #rrggbb, #rrggbbaa,
// rgb(), rgba(), hsl(), hsla(), a named colour, transparent).
Vector_ParseColor :: proc(s: string) -> ([4]u8, bool) {return parse_color(s)}

@(private = "file")
parse_color :: proc(s_: string) -> ([4]u8, bool) {
	s := strings.trim_space(s_)
	if s == "" do return {}, false
	if s[0] == '#' {
		h := s[1:]
		hexv :: proc(c: u8) -> (u8, bool) {
			switch c {
			case '0' ..= '9': return c - '0', true
			case 'a' ..= 'f': return c - 'a' + 10, true
			case 'A' ..= 'F': return c - 'A' + 10, true
			}
			return 0, false
		}
		out := [4]u8{0, 0, 0, 255}
		switch len(h) {
		case 3, 4:
			for i in 0 ..< len(h) {
				v, ok := hexv(h[i])
				if !ok do return {}, false
				out[i] = v * 17
			}
		case 6, 8:
			for i in 0 ..< len(h) / 2 {
				a, ok1 := hexv(h[i * 2]); b, ok2 := hexv(h[i * 2 + 1])
				if !ok1 || !ok2 do return {}, false
				out[i] = a * 16 + b
			}
		case:
			return {}, false
		}
		return out, true
	}
	lower := strings.to_lower(s, context.temp_allocator)
	if strings.has_prefix(lower, "rgb") || strings.has_prefix(lower, "hsl") {
		open := strings.index_byte(lower, '(')
		close := strings.index_byte(lower, ')')
		if open < 0 || close < open do return {}, false
		inner, _ := strings.replace_all(lower[open + 1:close], "/", ",", context.temp_allocator)
		parts := strings.split(inner, ",", context.temp_allocator)
		if len(parts) == 1 do parts = strings.fields(lower[open + 1:close], context.temp_allocator)
		if len(parts) < 3 do return {}, false
		comp :: proc(v: string, scale: f32) -> f32 {
			t := strings.trim_space(v)
			if strings.has_suffix(t, "%") do return parse_f(t[:len(t) - 1]) / 100 * scale
			return parse_f(t)
		}
		a: f32 = 1
		if len(parts) >= 4 do a = comp(parts[3], 1)
		if strings.has_prefix(lower, "rgb") {
			return {u8(clamp(comp(parts[0], 255), 0, 255)), u8(clamp(comp(parts[1], 255), 0, 255)), u8(clamp(comp(parts[2], 255), 0, 255)), u8(clamp(a, 0, 1) * 255 + 0.5)}, true
		}
		hh := math.mod(comp(parts[0], 360) / 360, 1)
		if hh < 0 do hh += 1
		ss, ll := clamp(comp(parts[1], 1), 0, 1), clamp(comp(parts[2], 1), 0, 1)
		q := ll * (1 + ss) if ll < 0.5 else ll + ss - ll * ss
		pp := 2 * ll - q
		hue :: proc(p, q, t_: f32) -> f32 {
			t := t_
			if t < 0 do t += 1
			if t > 1 do t -= 1
			if t < 1.0 / 6 do return p + (q - p) * 6 * t
			if t < 0.5 do return q
			if t < 2.0 / 3 do return p + (q - p) * (2.0 / 3 - t) * 6
			return p
		}
		return {u8(hue(pp, q, hh + 1.0 / 3) * 255 + 0.5), u8(hue(pp, q, hh) * 255 + 0.5), u8(hue(pp, q, hh - 1.0 / 3) * 255 + 0.5), u8(clamp(a, 0, 1) * 255 + 0.5)}, true
	}
	if lower == "transparent" do return {0, 0, 0, 0}, true
	for nc in SVG_NAMED_COLORS do if nc.name == lower do return {u8(nc.rgb >> 16), u8(nc.rgb >> 8), u8(nc.rgb), 255}, true
	return {}, false
}

@(private = "file")
Svg_Named :: struct {
	name: string,
	rgb:  u32,
}

// The CSS / SVG named colours.
@(private = "file", rodata)
SVG_NAMED_COLORS := [?]Svg_Named{
	{"aliceblue", 0xf0f8ff}, {"antiquewhite", 0xfaebd7}, {"aqua", 0x00ffff}, {"aquamarine", 0x7fffd4}, {"azure", 0xf0ffff},
	{"beige", 0xf5f5dc}, {"bisque", 0xffe4c4}, {"black", 0x000000}, {"blanchedalmond", 0xffebcd}, {"blue", 0x0000ff},
	{"blueviolet", 0x8a2be2}, {"brown", 0xa52a2a}, {"burlywood", 0xdeb887}, {"cadetblue", 0x5f9ea0}, {"chartreuse", 0x7fff00},
	{"chocolate", 0xd2691e}, {"coral", 0xff7f50}, {"cornflowerblue", 0x6495ed}, {"cornsilk", 0xfff8dc}, {"crimson", 0xdc143c},
	{"cyan", 0x00ffff}, {"darkblue", 0x00008b}, {"darkcyan", 0x008b8b}, {"darkgoldenrod", 0xb8860b}, {"darkgray", 0xa9a9a9},
	{"darkgreen", 0x006400}, {"darkgrey", 0xa9a9a9}, {"darkkhaki", 0xbdb76b}, {"darkmagenta", 0x8b008b}, {"darkolivegreen", 0x556b2f},
	{"darkorange", 0xff8c00}, {"darkorchid", 0x9932cc}, {"darkred", 0x8b0000}, {"darksalmon", 0xe9967a}, {"darkseagreen", 0x8fbc8f},
	{"darkslateblue", 0x483d8b}, {"darkslategray", 0x2f4f4f}, {"darkslategrey", 0x2f4f4f}, {"darkturquoise", 0x00ced1}, {"darkviolet", 0x9400d3},
	{"deeppink", 0xff1493}, {"deepskyblue", 0x00bfff}, {"dimgray", 0x696969}, {"dimgrey", 0x696969}, {"dodgerblue", 0x1e90ff},
	{"firebrick", 0xb22222}, {"floralwhite", 0xfffaf0}, {"forestgreen", 0x228b22}, {"fuchsia", 0xff00ff}, {"gainsboro", 0xdcdcdc},
	{"ghostwhite", 0xf8f8ff}, {"gold", 0xffd700}, {"goldenrod", 0xdaa520}, {"gray", 0x808080}, {"grey", 0x808080},
	{"green", 0x008000}, {"greenyellow", 0xadff2f}, {"honeydew", 0xf0fff0}, {"hotpink", 0xff69b4}, {"indianred", 0xcd5c5c},
	{"indigo", 0x4b0082}, {"ivory", 0xfffff0}, {"khaki", 0xf0e68c}, {"lavender", 0xe6e6fa}, {"lavenderblush", 0xfff0f5},
	{"lawngreen", 0x7cfc00}, {"lemonchiffon", 0xfffacd}, {"lightblue", 0xadd8e6}, {"lightcoral", 0xf08080}, {"lightcyan", 0xe0ffff},
	{"lightgoldenrodyellow", 0xfafad2}, {"lightgray", 0xd3d3d3}, {"lightgreen", 0x90ee90}, {"lightgrey", 0xd3d3d3}, {"lightpink", 0xffb6c1},
	{"lightsalmon", 0xffa07a}, {"lightseagreen", 0x20b2aa}, {"lightskyblue", 0x87cefa}, {"lightslategray", 0x778899}, {"lightslategrey", 0x778899},
	{"lightsteelblue", 0xb0c4de}, {"lightyellow", 0xffffe0}, {"lime", 0x00ff00}, {"limegreen", 0x32cd32}, {"linen", 0xfaf0e6},
	{"magenta", 0xff00ff}, {"maroon", 0x800000}, {"mediumaquamarine", 0x66cdaa}, {"mediumblue", 0x0000cd}, {"mediumorchid", 0xba55d3},
	{"mediumpurple", 0x9370db}, {"mediumseagreen", 0x3cb371}, {"mediumslateblue", 0x7b68ee}, {"mediumspringgreen", 0x00fa9a}, {"mediumturquoise", 0x48d1cc},
	{"mediumvioletred", 0xc71585}, {"midnightblue", 0x191970}, {"mintcream", 0xf5fffa}, {"mistyrose", 0xffe4e1}, {"moccasin", 0xffe4b5},
	{"navajowhite", 0xffdead}, {"navy", 0x000080}, {"oldlace", 0xfdf5e6}, {"olive", 0x808000}, {"olivedrab", 0x6b8e23},
	{"orange", 0xffa500}, {"orangered", 0xff4500}, {"orchid", 0xda70d6}, {"palegoldenrod", 0xeee8aa}, {"palegreen", 0x98fb98},
	{"paleturquoise", 0xafeeee}, {"palevioletred", 0xdb7093}, {"papayawhip", 0xffefd5}, {"peachpuff", 0xffdab9}, {"peru", 0xcd853f},
	{"pink", 0xffc0cb}, {"plum", 0xdda0dd}, {"powderblue", 0xb0e0e6}, {"purple", 0x800080}, {"rebeccapurple", 0x663399},
	{"red", 0xff0000}, {"rosybrown", 0xbc8f8f}, {"royalblue", 0x4169e1}, {"saddlebrown", 0x8b4513}, {"salmon", 0xfa8072},
	{"sandybrown", 0xf4a460}, {"seagreen", 0x2e8b57}, {"seashell", 0xfff5ee}, {"sienna", 0xa0522d}, {"silver", 0xc0c0c0},
	{"skyblue", 0x87ceeb}, {"slateblue", 0x6a5acd}, {"slategray", 0x708090}, {"slategrey", 0x708090}, {"snow", 0xfffafa},
	{"springgreen", 0x00ff7f}, {"steelblue", 0x4682b4}, {"tan", 0xd2b48c}, {"teal", 0x008080}, {"thistle", 0xd8bfd8},
	{"tomato", 0xff6347}, {"turquoise", 0x40e0d0}, {"violet", 0xee82ee}, {"wheat", 0xf5deb3}, {"white", 0xffffff},
	{"whitesmoke", 0xf5f5f5}, {"yellow", 0xffff00}, {"yellowgreen", 0x9acd32},
}
