package engine

// ============================================================================
// TrueType outlines (#270): just enough of a .ttf to get glyph shapes for
// MSDF text (msdf.odin) - cmap (formats 4 and 12), head, hhea, hmtx, loca
// and glyf (simple and composite glyphs). CFF-flavoured .otf fonts have no
// glyf table: Ttf_Open fails and the text falls back to the plain SDF.
// Coordinates are font units, y up.
// ============================================================================

Ttf_Font :: struct {
	data:          []u8,
	unitsPerEm:    f32,
	ascent:        f32,
	descent:       f32, // negative
	lineGap:       f32,
	numGlyphs:     int,
	locaLong:      bool,
	numHMetrics:   int,
	cmap, loca, glyf, hmtx: int, // table offsets
	cmapFormat:    u16,
}

// Ttf_Point: a contour point (on the curve, or a quadratic control point).
Ttf_Point :: struct {
	p:  [2]f32,
	on: bool,
}

@(private = "file")
be16 :: proc(d: []u8, o: int) -> u16 {
	if o + 2 > len(d) do return 0
	return u16(d[o]) << 8 | u16(d[o + 1])
}

@(private = "file")
be32 :: proc(d: []u8, o: int) -> u32 {
	if o + 4 > len(d) do return 0
	return u32(d[o]) << 24 | u32(d[o + 1]) << 16 | u32(d[o + 2]) << 8 | u32(d[o + 3])
}

@(private = "file")
bes16 :: proc(d: []u8, o: int) -> i16 {return i16(be16(d, o))}

// Ttf_Open reads a font's tables (the data stays the caller's).
Ttf_Open :: proc(data: []u8) -> (f: Ttf_Font, ok: bool) {
	if len(data) < 12 do return
	f.data = data
	numTables := int(be16(data, 4))
	head, hhea, maxp := -1, -1, -1
	f.cmap, f.loca, f.glyf, f.hmtx = -1, -1, -1, -1
	for i in 0 ..< numTables {
		rec := 12 + i * 16
		tag := string(data[rec:rec + 4]) if rec + 4 <= len(data) else ""
		off := int(be32(data, rec + 8))
		switch tag {
		case "head": head = off
		case "hhea": hhea = off
		case "maxp": maxp = off
		case "cmap": f.cmap = off
		case "loca": f.loca = off
		case "glyf": f.glyf = off
		case "hmtx": f.hmtx = off
		}
	}
	if head < 0 || hhea < 0 || maxp < 0 || f.cmap < 0 || f.loca < 0 || f.glyf < 0 || f.hmtx < 0 do return
	f.unitsPerEm = f32(be16(data, head + 18))
	f.locaLong = be16(data, head + 50) != 0
	f.ascent = f32(bes16(data, hhea + 4))
	f.descent = f32(bes16(data, hhea + 6))
	f.lineGap = f32(bes16(data, hhea + 8))
	f.numHMetrics = int(be16(data, hhea + 34))
	f.numGlyphs = int(be16(data, maxp + 4))
	// cmap: the best Unicode subtable (format 12, else 4).
	n := int(be16(data, f.cmap + 2))
	best := -1
	for i in 0 ..< n {
		rec := f.cmap + 4 + i * 8
		platform, encoding := be16(data, rec), be16(data, rec + 2)
		sub := f.cmap + int(be32(data, rec + 4))
		format := be16(data, sub)
		unicode := platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10))
		if !unicode do continue
		if format == 12 || (format == 4 && best < 0) {
			best = sub
			f.cmapFormat = format
		}
	}
	if best < 0 || f.unitsPerEm <= 0 do return
	f.cmap = best
	return f, true
}

// Ttf_GlyphIndex: a codepoint's glyph (0: missing).
Ttf_GlyphIndex :: proc(f: ^Ttf_Font, cp: rune) -> int {
	d := f.data
	c := u32(cp)
	switch f.cmapFormat {
	case 4:
		if c > 0xFFFF do return 0
		segX2 := int(be16(d, f.cmap + 6))
		ends := f.cmap + 14
		starts := ends + segX2 + 2
		deltas := starts + segX2
		ranges := deltas + segX2
		for s := 0; s < segX2; s += 2 {
			end := u32(be16(d, ends + s))
			if c > end do continue
			start := u32(be16(d, starts + s))
			if c < start do return 0
			delta := be16(d, deltas + s)
			ro := int(be16(d, ranges + s))
			if ro == 0 do return int(u16(c) + delta)
			gi := int(be16(d, ranges + s + ro + int(c - start) * 2))
			return int(u16(gi) + delta) if gi != 0 else 0
		}
	case 12:
		groups := int(be32(d, f.cmap + 12))
		for i in 0 ..< groups {
			g := f.cmap + 16 + i * 12
			start, end := be32(d, g), be32(d, g + 4)
			if c >= start && c <= end do return int(be32(d, g + 8) + (c - start))
		}
	}
	return 0
}

// Ttf_Advance: a glyph's advance width and left side bearing (font units).
Ttf_Advance :: proc(f: ^Ttf_Font, glyph: int) -> (advance, lsb: f32) {
	if f.numHMetrics <= 0 do return
	if glyph < f.numHMetrics {
		return f32(be16(f.data, f.hmtx + glyph * 4)), f32(bes16(f.data, f.hmtx + glyph * 4 + 2))
	}
	advance = f32(be16(f.data, f.hmtx + (f.numHMetrics - 1) * 4))
	lsb = f32(bes16(f.data, f.hmtx + f.numHMetrics * 4 + (glyph - f.numHMetrics) * 2))
	return
}

@(private = "file")
glyph_offset :: proc(f: ^Ttf_Font, glyph: int) -> (start, end: int) {
	if glyph < 0 || glyph >= f.numGlyphs do return -1, -1
	if f.locaLong {
		start = int(be32(f.data, f.loca + glyph * 4))
		end = int(be32(f.data, f.loca + glyph * 4 + 4))
	} else {
		start = int(be16(f.data, f.loca + glyph * 2)) * 2
		end = int(be16(f.data, f.loca + glyph * 2 + 2)) * 2
	}
	return f.glyf + start, f.glyf + end
}

// Ttf_GlyphContours: a glyph's contours (temp allocated; empty for a space).
Ttf_GlyphContours :: proc(f: ^Ttf_Font, glyph: int, depth := 0) -> [dynamic][dynamic]Ttf_Point {
	out := make([dynamic][dynamic]Ttf_Point, context.temp_allocator)
	if depth > 8 do return out
	start, end := glyph_offset(f, glyph)
	if start < 0 || end <= start do return out
	d := f.data
	numContours := int(bes16(d, start))
	if numContours >= 0 {
		// A simple glyph.
		endPts := start + 10
		count := 0
		if numContours > 0 do count = int(be16(d, endPts + (numContours - 1) * 2)) + 1
		insLen := int(be16(d, endPts + numContours * 2))
		p := endPts + numContours * 2 + 2 + insLen
		flags := make([]u8, count, context.temp_allocator)
		for i := 0; i < count; {
			fl := d[p] if p < len(d) else 0
			p += 1
			flags[i] = fl
			i += 1
			if fl & 8 != 0 {
				rep := int(d[p]) if p < len(d) else 0
				p += 1
				for _ in 0 ..< rep do if i < count {flags[i] = fl; i += 1}
			}
		}
		xs := make([]f32, count, context.temp_allocator)
		ys := make([]f32, count, context.temp_allocator)
		v: f32 = 0
		for i in 0 ..< count {
			fl := flags[i]
			if fl & 2 != 0 {
				dx := f32(d[p]) if p < len(d) else 0
				p += 1
				v += dx if fl & 16 != 0 else -dx
			} else if fl & 16 == 0 {
				v += f32(bes16(d, p))
				p += 2
			}
			xs[i] = v
		}
		v = 0
		for i in 0 ..< count {
			fl := flags[i]
			if fl & 4 != 0 {
				dy := f32(d[p]) if p < len(d) else 0
				p += 1
				v += dy if fl & 32 != 0 else -dy
			} else if fl & 32 == 0 {
				v += f32(bes16(d, p))
				p += 2
			}
			ys[i] = v
		}
		first := 0
		for cIdx in 0 ..< numContours {
			last := int(be16(d, endPts + cIdx * 2))
			contour := make([dynamic]Ttf_Point, context.temp_allocator)
			for i in first ..= min(last, count - 1) do append(&contour, Ttf_Point{{xs[i], ys[i]}, flags[i] & 1 != 0})
			if len(contour) > 1 do append(&out, contour)
			first = last + 1
		}
		return out
	}
	// A composite glyph: its parts, each moved / scaled.
	p := start + 10
	for {
		fl := be16(d, p)
		sub := int(be16(d, p + 2))
		p += 4
		dx, dy: f32
		if fl & 1 != 0 {
			dx, dy = f32(bes16(d, p)), f32(bes16(d, p + 2))
			p += 4
		} else {
			dx, dy = f32(i8(d[p])), f32(i8(d[p + 1]))
			p += 2
		}
		m := [4]f32{1, 0, 0, 1}
		f2dot14 :: proc(d: []u8, o: int) -> f32 {return f32(bes16(d, o)) / 16384}
		if fl & 8 != 0 {
			s := f2dot14(d, p)
			m = {s, 0, 0, s}
			p += 2
		} else if fl & 0x40 != 0 {
			m = {f2dot14(d, p), 0, 0, f2dot14(d, p + 2)}
			p += 4
		} else if fl & 0x80 != 0 {
			m = {f2dot14(d, p), f2dot14(d, p + 2), f2dot14(d, p + 4), f2dot14(d, p + 6)}
			p += 8
		}
		for c in Ttf_GlyphContours(f, sub, depth + 1) {
			moved := make([dynamic]Ttf_Point, context.temp_allocator)
			for pt in c {
				x, y := pt.p.x, pt.p.y
				append(&moved, Ttf_Point{{m[0] * x + m[2] * y + dx, m[1] * x + m[3] * y + dy}, pt.on})
			}
			append(&out, moved)
		}
		if fl & 0x20 == 0 do break // (no more components)
	}
	return out
}
