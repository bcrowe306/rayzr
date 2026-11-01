package engine

import "core:math"
import "core:slice"
import rl "vendor:raylib"

// ============================================================================
// Multi-channel signed distance fields for text (#270): sharp at any scale,
// corners included. Each glyph's outline (ttf_outline.odin) is split into
// edges, the edges coloured (each two of R, G, B; the colour changes at
// sharp corners), and every pixel stores, per channel, the distance to the
// nearest edge of that colour; alpha holds the true signed distance. The
// median of R, G, B rebuilds the shape with its corners (the shader:
// text.odin). Where the channels disagree with the true inside / outside,
// they take the true distance (a simple error correction).
// ============================================================================

MSDF_EM :: 48    // glyph size in the atlas (px of line height, as raylib fonts are sized)
MSDF_RANGE :: 4  // distance range (px either side of the edge)
// Which side of an edge (by its direction) is inside for an outline of
// positive signed area in y-down px.
@(private = "file")
MSDF_SIDE :: f32(1)

@(private = "file")
Msdf_Edge :: struct {
	pts:   [dynamic][2]f32, // the edge as a polyline (font px, y down)
	color: u8,              // 1 R, 2 G, 4 B
	lo, hi: [2]f32,         // its bounding box
}

@(private = "file")
Msdf_Contour :: struct {
	edges: [dynamic]Msdf_Edge,
}

// Msdf_Glyph: one glyph's field (RGBA, w x h) and where it sits.
Msdf_Glyph :: struct {
	cp:      rune,
	w, h:    int,
	pixels:  []u8,   // RGBA (temp)
	offset:  [2]f32, // the image's top-left from the pen (line top), px at MSDF_EM
	advance: f32,
}

// msdf_contours: a glyph's contours as coloured edges, in px (y down from
// the line's top) at `scale`.
@(private = "file")
msdf_contours :: proc(font: ^Ttf_Font, glyph: int, scale: f32) -> [dynamic]Msdf_Contour {
	out := make([dynamic]Msdf_Contour, context.temp_allocator)
	for raw in Ttf_GlyphContours(font, glyph) {
		// Font units (y up) -> px (y down from the ascent line).
		pts := make([dynamic]Ttf_Point, context.temp_allocator)
		for p in raw do append(&pts, Ttf_Point{{p.p.x * scale, (font.ascent - p.p.y) * scale}, p.on})
		n := len(pts)
		if n < 2 do continue
		// Start on an on-curve point (or the midpoint of two off-curve ones).
		startIdx := -1
		for p, i in pts do if p.on {startIdx = i; break}
		start: [2]f32
		if startIdx < 0 {
			start = (pts[0].p + pts[1].p) * 0.5
			startIdx = 0
		} else {
			start = pts[startIdx].p
			startIdx += 1
		}
		c := Msdf_Contour{edges = make([dynamic]Msdf_Edge, context.temp_allocator)}
		cur := start
		ctrl: [2]f32
		hasCtrl := false
		add_line :: proc(c: ^Msdf_Contour, a, b: [2]f32) {
			if a == b do return
			e := Msdf_Edge{pts = make([dynamic][2]f32, context.temp_allocator)}
			append(&e.pts, a, b)
			append(&c.edges, e)
		}
		add_quad :: proc(c: ^Msdf_Contour, a, q, b: [2]f32) {
			e := Msdf_Edge{pts = make([dynamic][2]f32, context.temp_allocator)}
			STEPS :: 10
			for i in 0 ..= STEPS {
				t := f32(i) / STEPS
				u := 1 - t
				append(&e.pts, u * u * a + 2 * u * t * q + t * t * b)
			}
			append(&c.edges, e)
		}
		for k in 0 ..< n {
			p := pts[(startIdx + k) % n]
			if p.on {
				if hasCtrl do add_quad(&c, cur, ctrl, p.p)
				else do add_line(&c, cur, p.p)
				cur, hasCtrl = p.p, false
			} else {
				if hasCtrl {
					mid := (ctrl + p.p) * 0.5
					add_quad(&c, cur, ctrl, mid)
					cur = mid
				}
				ctrl, hasCtrl = p.p, true
			}
		}
		if hasCtrl do add_quad(&c, cur, ctrl, start)
		else do add_line(&c, cur, start)
		if len(c.edges) > 0 do append(&out, c)
	}
	msdf_color_edges(out[:])
	for &c in out do for &e in c.edges {
		e.lo, e.hi = e.pts[0], e.pts[0]
		for p in e.pts {
			e.lo = {min(e.lo.x, p.x), min(e.lo.y, p.y)}
			e.hi = {max(e.hi.x, p.x), max(e.hi.y, p.y)}
		}
	}
	return out
}

// msdf_color_edges: the colour changes at sharp corners, so each corner
// keeps two distances (its sharpness); a smooth contour is all white.
@(private = "file")
msdf_color_edges :: proc(contours: []Msdf_Contour) {
	CYAN, MAGENTA, YELLOW, WHITE :: u8(6), u8(5), u8(3), u8(7)
	cycle := [3]u8{CYAN, MAGENTA, YELLOW}
	dir_out :: proc(e: Msdf_Edge) -> [2]f32 {return linalg_norm(e.pts[len(e.pts) - 1] - e.pts[len(e.pts) - 2])}
	dir_in :: proc(e: Msdf_Edge) -> [2]f32 {return linalg_norm(e.pts[1] - e.pts[0])}
	for &c in contours {
		n := len(c.edges)
		corners := make([dynamic]int, context.temp_allocator)
		for i in 0 ..< n {
			a := dir_out(c.edges[(i + n - 1) % n])
			b := dir_in(c.edges[i])
			cross := a.x * b.y - a.y * b.x
			if a.x * b.x + a.y * b.y <= 0 || abs(cross) > math.sin(f32(3.0)) do append(&corners, i)
		}
		switch len(corners) {
		case 0:
			for &e in c.edges do e.color = WHITE
		case 1:
			// One corner (a teardrop): three colours around it.
			s := corners[0]
			for k in 0 ..< n do c.edges[(s + k) % n].color = cycle[min(3 * k / max(n, 1), 2)]
			if n < 3 do for k in 0 ..< n do c.edges[(s + k) % n].color = cycle[k % 3]
		case:
			ci := 0
			s := corners[0]
			color := cycle[0]
			for k in 0 ..< n {
				i := (s + k) % n
				if slice.contains(corners[:], i) && k > 0 {
					ci += 1
					color = cycle[ci % 3]
				}
				c.edges[i].color = color
			}
			// The last run must differ from the first (they meet at corner s).
			first := c.edges[s].color
			last := c.edges[(s + n - 1) % n].color
			if first == last {
				for col in cycle do if col != first && col != c.edges[(s + n - 2) % n].color {
					// recolour the last run
					for k := n - 1; k > 0; k -= 1 {
						i := (s + k) % n
						if c.edges[i].color != last do break
						c.edges[i].color = col
						if slice.contains(corners[:], i) do break
					}
					break
				}
			}
		}
	}
}

@(private = "file")
linalg_norm :: proc(v: [2]f32) -> [2]f32 {
	l := math.sqrt(v.x * v.x + v.y * v.y)
	return v / l if l > 0 else {1, 0}
}

// msdf_edge_distance: a point's distance to an edge (signed: the edge's
// left negative in y-down px, TrueType's outer contours making their inside
// positive), its orthogonality (tie-break) and the pseudo-distance (past an
// end, to the end segment's line).
@(private = "file")
msdf_edge_distance :: proc(e: Msdf_Edge, p: [2]f32) -> (dist, ortho, pseudo: f32) {
	best := max(f32)
	bestSign: f32 = 1
	bestOrtho: f32 = 0
	bestSeg := 0
	bestT: f32 = 0
	n := len(e.pts)
	for i in 0 ..< n - 1 {
		a, b := e.pts[i], e.pts[i + 1]
		ab := b - a
		l2 := ab.x * ab.x + ab.y * ab.y
		t: f32 = 0
		if l2 > 0 do t = ((p - a).x * ab.x + (p - a).y * ab.y) / l2
		tc := clamp(t, 0, 1)
		q := a + ab * tc
		dv := p - q
		d := math.sqrt(dv.x * dv.x + dv.y * dv.y)
		cross := ab.x * (p - a).y - ab.y * (p - a).x
		o: f32 = 0
		if d > 0 && l2 > 0 do o = abs(cross) / (d * math.sqrt(l2))
		if d < best - 1e-4 || (abs(d - best) <= 1e-4 && o > bestOrtho) {
			best, bestOrtho, bestSeg, bestT = d, o, i, t
			bestSign = 1 if cross > 0 else -1
		}
	}
	dist = best * bestSign
	pseudo = dist
	// Past the edge's start / end: the distance to that segment's line.
	if (bestSeg == 0 && bestT < 0) || (bestSeg == n - 2 && bestT > 1) {
		a, b := e.pts[bestSeg], e.pts[bestSeg + 1]
		ab := linalg_norm(b - a)
		perp := ab.x * (p - a).y - ab.y * (p - a).x
		if abs(perp) <= abs(dist) do pseudo = perp
	}
	return dist, bestOrtho, pseudo
}

// Msdf_GenerateGlyph: a codepoint's field at MSDF_EM px per em (nil pixels
// for an empty glyph such as a space).
Msdf_GenerateGlyph :: proc(font: ^Ttf_Font, cp: rune) -> (g: Msdf_Glyph) {
	g.cp = cp
	scale := f32(MSDF_EM) / max(font.ascent - font.descent, 1) // (raylib sizes fonts by pixel height: ascent to descent)
	glyph := Ttf_GlyphIndex(font, cp)
	adv, _ := Ttf_Advance(font, glyph)
	g.advance = adv * scale
	contours := msdf_contours(font, glyph, scale)
	if len(contours) == 0 do return
	lo, hi := [2]f32{max(f32), max(f32)}, [2]f32{min(f32), min(f32)}
	for c in contours do for e in c.edges do for p in e.pts {
		lo = {min(lo.x, p.x), min(lo.y, p.y)}
		hi = {max(hi.x, p.x), max(hi.y, p.y)}
	}
	pad := f32(MSDF_RANGE)
	x0, y0 := math.floor(lo.x) - pad, math.floor(lo.y) - pad
	g.w = int(math.ceil(hi.x) + pad - x0)
	g.h = int(math.ceil(hi.y) + pad - y0)
	g.offset = {x0, y0}
	g.pixels = make([]u8, g.w * g.h * 4, context.temp_allocator)
	// The edges' side that is inside: from the outline's overall winding
	// (its signed area), so fonts wound either way work.
	area: f32 = 0
	for c in contours do for e in c.edges do for i in 0 ..< len(e.pts) - 1 {
		a, b := e.pts[i], e.pts[i + 1]
		area += a.x * b.y - b.x * a.y
	}
	signFix: f32 = MSDF_SIDE if area > 0 else -MSDF_SIDE
	crossings := make([dynamic]Msdf_Crossing, context.temp_allocator)
	for y in 0 ..< g.h {
		// Inside / outside for the whole row: the outline's crossings of it.
		py := y0 + f32(y) + 0.5
		clear(&crossings)
		for c in contours do for e in c.edges do for i in 0 ..< len(e.pts) - 1 {
			a, b := e.pts[i], e.pts[i + 1]
			if (a.y <= py) != (b.y <= py) {
				append(&crossings, Msdf_Crossing{a.x + (py - a.y) / (b.y - a.y) * (b.x - a.x), 1 if b.y > a.y else -1})
			}
		}
		slice.sort_by(crossings[:], proc(a, b: Msdf_Crossing) -> bool {return a.x < b.x})
	for x in 0 ..< g.w {
		p := [2]f32{x0 + f32(x) + 0.5, py}
		best := [3]f32{max(f32), max(f32), max(f32)}
		bestO: [3]f32
		val: [3]f32
		trueD := max(f32)
		for c in contours do for e in c.edges {
			// (Farther than every channel's best: can't matter.)
			bx := max(e.lo.x - p.x, 0, p.x - e.hi.x)
			by := max(e.lo.y - p.y, 0, p.y - e.hi.y)
			bd := math.sqrt(bx * bx + by * by)
			if bd > trueD && bd > best[0] && bd > best[1] && bd > best[2] do continue
			d, o, pd := msdf_edge_distance(e, p)
			if abs(d) < trueD do trueD = abs(d)
			for ch in 0 ..< 3 {
				if e.color & (1 << u8(ch)) == 0 do continue
				if abs(d) < best[ch] - 1e-4 || (abs(abs(d) - best[ch]) <= 1e-4 && o > bestO[ch]) {
					best[ch], bestO[ch], val[ch] = abs(d), o, pd
				}
			}
		}
		w := 0
		for cr in crossings do if cr.x > p.x do w += cr.dir
		inside := w != 0
		sd := trueD if inside else -trueD
		// The edges' own sign: inside positive (fixed once the first inside pixel tells).
		ch3 := val * signFix
		med := max(min(ch3.x, ch3.y), min(max(ch3.x, ch3.y), ch3.z))
		// Error correction: channels that disagree with the true side take the true distance.
		if (med > 0) != (sd > 0) do ch3 = {sd, sd, sd}
		enc :: proc(d: f32) -> u8 {return u8(clamp(0.5 + d / (2 * MSDF_RANGE), 0, 1) * 255 + 0.5)}
		i := (y * g.w + x) * 4
		g.pixels[i + 0], g.pixels[i + 1], g.pixels[i + 2], g.pixels[i + 3] = enc(ch3.x), enc(ch3.y), enc(ch3.z), enc(sd)
	}
	}
	return
}

@(private = "file")
Msdf_Crossing :: struct {
	x:   f32,
	dir: int,
}

// Msdf_BuildFont: a raylib Font whose atlas holds the codepoints' fields
// (glyphPadding = MSDF_RANGE; offsets and advances at MSDF_EM px).
Msdf_BuildFont :: proc(font: ^Ttf_Font, cps: []rune) -> (f: rl.Font, ok: bool) {
	glyphs := make([]Msdf_Glyph, len(cps), context.temp_allocator)
	for cp, i in cps do glyphs[i] = Msdf_GenerateGlyph(font, cp)
	// Shelf packing into a 1024-wide atlas.
	W :: 1024
	x, y, rowH := 1, 1, 0
	pos := make([][2]int, len(cps), context.temp_allocator)
	for g, i in glyphs {
		if g.w == 0 do continue
		if x + g.w + 1 > W {
			x = 1
			y += rowH + 1
			rowH = 0
		}
		pos[i] = {x, y}
		x += g.w + 1
		rowH = max(rowH, g.h)
	}
	H := 1
	for H < y + rowH + 2 do H *= 2
	atlas := rl.GenImageColor(W, i32(H), {0, 0, 0, 0})
	px := ([^]u8)(atlas.data)
	for g, i in glyphs {
		if g.w == 0 do continue
		for row in 0 ..< g.h {
			dst := ((pos[i].y + row) * W + pos[i].x) * 4
			copy(px[dst:dst + g.w * 4], g.pixels[row * g.w * 4:(row + 1) * g.w * 4])
		}
	}
	pad := f32(MSDF_RANGE)
	f.baseSize = MSDF_EM
	f.glyphCount = i32(len(cps))
	f.glyphPadding = MSDF_RANGE
	f.recs = ([^]rl.Rectangle)(rl.MemAlloc(u32(size_of(rl.Rectangle) * len(cps))))
	f.glyphs = ([^]rl.GlyphInfo)(rl.MemAlloc(u32(size_of(rl.GlyphInfo) * len(cps))))
	for g, i in glyphs {
		// The rectangle without the padding (raylib's convention).
		f.recs[i] = {f32(pos[i].x) + pad, f32(pos[i].y) + pad, max(f32(g.w) - 2 * pad, 0), max(f32(g.h) - 2 * pad, 0)}
		f.glyphs[i] = {value = g.cp, offsetX = i32(g.offset.x + pad), offsetY = i32(g.offset.y + pad), advanceX = i32(math.round(g.advance))}
	}
	f.texture = rl.LoadTextureFromImage(atlas)
	rl.UnloadImage(atlas)
	rl.SetTextureFilter(f.texture, .BILINEAR)
	return f, f.texture.id != 0
}

// --- fonts whose glyphs are made as they're needed -----------------------------------

// Msdf_Font: a font's MSDF atlas, laid out up front (cheap: each glyph's box
// from its outline) and filled a glyph at a time the first time it's drawn,
// a few milliseconds' worth a frame - until then that glyph draws from the
// bitmap font (Text_DrawGlyphs).
Msdf_Font :: struct {
	data:  []u8, // the .ttf (heap)
	ttf:   Ttf_Font,
	font:  rl.Font, // atlas texture, recs, glyph metrics (at MSDF_EM)
	pos:   [][2]int,
	size:  [][2]int,
	ready: []bool,
}

// The frame's generation budget (Msdf_EnsureGlyph).
@(private = "file")
msdfBudget: struct {
	frameTime: f64, // rl.GetTime() of the frame the budget belongs to
	spentMs:   f64,
}

MSDF_FRAME_BUDGET_MS :: 4.0

// Msdf_FontNew lays out a font's atlas (nil: not a glyf TrueType font).
Msdf_FontNew :: proc(data: []u8, cps: []rune) -> ^Msdf_Font {
	ttf, ok := Ttf_Open(data)
	if !ok || !rl.IsWindowReady() do return nil
	a := Engine_HeapAllocator()
	mf := new(Msdf_Font, a)
	mf.data = make([]u8, len(data), a)
	copy(mf.data, data)
	mf.ttf = ttf
	mf.ttf.data = mf.data
	n := len(cps)
	mf.pos = make([][2]int, n, a)
	mf.size = make([][2]int, n, a)
	mf.ready = make([]bool, n, a)
	scale := f32(MSDF_EM) / max(mf.ttf.ascent - mf.ttf.descent, 1) // (as raylib: pixel height)
	pad := f32(MSDF_RANGE)
	f := &mf.font
	f.baseSize = MSDF_EM
	f.glyphCount = i32(n)
	f.glyphPadding = MSDF_RANGE
	f.recs = ([^]rl.Rectangle)(rl.MemAlloc(u32(size_of(rl.Rectangle) * n)))
	f.glyphs = ([^]rl.GlyphInfo)(rl.MemAlloc(u32(size_of(rl.GlyphInfo) * n)))
	W :: 1024
	x, y, rowH := 1, 1, 0
	for cp, i in cps {
		glyph := Ttf_GlyphIndex(&mf.ttf, cp)
		adv, _ := Ttf_Advance(&mf.ttf, glyph)
		lo, hi := [2]f32{max(f32), max(f32)}, [2]f32{min(f32), min(f32)}
		for c in Ttf_GlyphContours(&mf.ttf, glyph) do for p in c {
			q := [2]f32{p.p.x * scale, (mf.ttf.ascent - p.p.y) * scale}
			lo = {min(lo.x, q.x), min(lo.y, q.y)}
			hi = {max(hi.x, q.x), max(hi.y, q.y)}
		}
		w, h := 0, 0
		x0, y0: f32
		if lo.x <= hi.x {
			x0, y0 = math.floor(lo.x) - pad, math.floor(lo.y) - pad
			w, h = int(math.ceil(hi.x) + pad - x0), int(math.ceil(hi.y) + pad - y0)
		}
		if w > 0 {
			if x + w + 1 > W {
				x = 1
				y += rowH + 1
				rowH = 0
			}
			mf.pos[i] = {x, y}
			x += w + 1
			rowH = max(rowH, h)
		} else {
			mf.ready[i] = true // (nothing to draw: a space)
		}
		mf.size[i] = {w, h}
		f.recs[i] = {f32(mf.pos[i].x) + pad, f32(mf.pos[i].y) + pad, max(f32(w) - 2 * pad, 0), max(f32(h) - 2 * pad, 0)}
		f.glyphs[i] = {value = cp, offsetX = i32(x0 + pad), offsetY = i32(y0 + pad), advanceX = i32(math.round(adv * scale))}
	}
	H := 1
	for H < y + rowH + 2 do H *= 2
	img := rl.GenImageColor(W, i32(H), {0, 0, 0, 0})
	f.texture = rl.LoadTextureFromImage(img)
	rl.UnloadImage(img)
	rl.SetTextureFilter(f.texture, .BILINEAR)
	return mf
}

Msdf_FontFree :: proc(mf: ^Msdf_Font) {
	if mf == nil do return
	a := Engine_HeapAllocator()
	if rl.IsWindowReady() do rl.UnloadFont(mf.font)
	delete(mf.data, a)
	delete(mf.pos, a)
	delete(mf.size, a)
	delete(mf.ready, a)
	free(mf, a)
}

// Msdf_EnsureGlyph: the glyph's field is in the atlas (made now if this
// frame's budget allows). false: not yet - draw it from the bitmap font.
Msdf_EnsureGlyph :: proc(mf: ^Msdf_Font, index: int) -> bool {
	if mf == nil || index < 0 || index >= len(mf.ready) do return false
	if mf.ready[index] do return true
	now := rl.GetTime()
	if now != msdfBudget.frameTime do msdfBudget = {frameTime = now}
	if msdfBudget.spentMs >= MSDF_FRAME_BUDGET_MS do return false
	t0 := rl.GetTime()
	g := Msdf_GenerateGlyph(&mf.ttf, mf.font.glyphs[index].value)
	if g.w > 0 && g.w == mf.size[index].x && g.h == mf.size[index].y {
		rl.UpdateTextureRec(mf.font.texture, {f32(mf.pos[index].x), f32(mf.pos[index].y), f32(g.w), f32(g.h)}, raw_data(g.pixels))
	}
	mf.ready[index] = true
	msdfBudget.spentMs += (rl.GetTime() - t0) * 1000
	return true
}
