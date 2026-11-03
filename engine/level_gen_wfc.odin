package engine

import "core:encoding/json"
import "core:fmt"
import "core:hash"
import "core:math"
import "core:math/bits"
import "core:strings"

// ============================================================================
// Wave Function Collapse (#171, a stretch item): the level generator's WFC
// node, the "tiled" model. Its rules say which tile may sit next to which,
// in each of the four directions - learned from a small sample painted on
// the node (every pair of neighbours in it is allowed; how often a tile
// appears is its weight), or declared by Wang tiles (each tile's four edges
// have colours; touching edges must match). The node's grid holds tile ids
// (-1: none), for a Tile Output with `tile_ids` on.
//
// The solver: every cell starts able to be any tile (a bitset domain); the
// undecided cell of lowest entropy (a heap, stale entries skipped) collapses
// to one of its tiles by weight; the change spreads (a stack of cells whose
// domains shrank, arc consistency in the AC-3 way: a neighbour keeps only
// the tiles some tile of the cell allows). A cell left with no tile is a
// contradiction: the node starts again with the next seed, `attempts` times
// in all, then reports it. Deterministic: only the node's seed decides.
// ============================================================================

// A painted sample: w x h tile ids, row by row (-1: not painted - nothing is
// learned from it).
Gen_WFC_Sample :: struct {
	w, h:  int,
	cells: [dynamic]i32,
}

// A Wang tile: a tile and its edges' colours - north, east, south, west.
// Two tiles may touch when their touching edges have the same colour.
Gen_Wang_Tile :: struct {
	tile:   i32,
	edges:  [4]i32, // N, E, S, W
	weight: f32,    // how often it is picked (relative; default 1)
}

GEN_WFC_SAMPLE_MAX :: 64
GEN_WFC_SAMPLE_DEFAULT :: 8
GEN_WFC_MAX_TILES :: 1024

// The solver's directions: east, south, west, north (opposite: +2).
@(private = "file")
WFC_DX := [4]int{1, 0, -1, 0}
@(private = "file")
WFC_DY := [4]int{0, 1, 0, -1}

// Gen_WFC_Rules: the tiles (an index each) and which may sit next to which:
// allow[d][a * words ..][b] - tile b may be in direction d of tile a.
Gen_WFC_Rules :: struct {
	tiles:   []i32, // index -> tile id
	weights: []f64,
	allow:   [4][]u64,
	words:   int, // u64s in a bitset of tiles
}

// Gen_WFCRules: a WFC node's rules (from its sample or its Wang tiles; in
// `allocator`), or why it has none.
Gen_WFCRules :: proc(n: ^Gen_Node, allocator := context.temp_allocator) -> (r: Gen_WFC_Rules, err: string) {
	context.allocator = allocator
	wang := int(Gen_Param(n, "rules")) == 1
	ids := make([dynamic]i32, context.temp_allocator)
	index := make(map[i32]int, allocator = context.temp_allocator)
	weights := make([dynamic]f64, context.temp_allocator)
	add :: proc(ids: ^[dynamic]i32, index: ^map[i32]int, weights: ^[dynamic]f64, t: i32, w: f64) -> int {
		if k, ok := index[t]; ok {
			weights[k] += w
			return k
		}
		index[t] = len(ids)
		append(ids, t)
		append(weights, w)
		return len(ids) - 1
	}
	if wang {
		for wt in n.wang do if wt.tile >= 0 && wt.tile not_in index do add(&ids, &index, &weights, wt.tile, f64(wt.weight if wt.weight > 0 else 1))
		if len(ids) == 0 do return {}, "add its Wang tiles"
	} else {
		s := &n.sample
		for t in s.cells[:min(len(s.cells), s.w * s.h)] do if t >= 0 do add(&ids, &index, &weights, t, 1)
		if len(ids) == 0 do return {}, "paint its sample (the tiles it learns from)"
	}
	if len(ids) > GEN_WFC_MAX_TILES do return {}, fmt.tprintf("more than %d different tiles", GEN_WFC_MAX_TILES)
	T := len(ids)
	r.words = (T + 63) / 64
	r.tiles = make([]i32, T)
	copy(r.tiles, ids[:])
	r.weights = make([]f64, T)
	copy(r.weights, weights[:])
	for d in 0 ..< 4 do r.allow[d] = make([]u64, T * r.words)
	allow2 :: proc(r: ^Gen_WFC_Rules, d, a, b: int) {
		r.allow[d][a * r.words + b / 64] |= 1 << uint(b % 64)
		o := (d + 2) % 4
		r.allow[o][b * r.words + a / 64] |= 1 << uint(a % 64)
	}
	if wang {
		// Edges N, E, S, W; a tile b east of a: a's east edge is b's west one.
		for wa in n.wang {
			a, aok := index[wa.tile]
			if !aok do continue
			for wb in n.wang {
				b, bok := index[wb.tile]
				if !bok do continue
				if wa.edges[1] == wb.edges[3] do allow2(&r, 0, a, b) // b east of a
				if wa.edges[2] == wb.edges[0] do allow2(&r, 1, a, b) // b south of a
			}
		}
		return r, ""
	}
	s := &n.sample
	wrap := Gen_Param(n, "wrap") != 0
	at :: proc(s: ^Gen_WFC_Sample, x, y: int) -> i32 {return s.cells[y * s.w + x]}
	for y in 0 ..< s.h do for x in 0 ..< s.w {
		a := at(s, x, y)
		if a < 0 do continue
		for d in 0 ..< 2 { // east and south (allow2 adds the opposite)
			nx, ny := x + WFC_DX[d], y + WFC_DY[d]
			if nx >= s.w || ny >= s.h {
				if !wrap do continue
				nx, ny = nx % s.w, ny % s.h
			}
			b := at(s, nx, ny)
			if b >= 0 do allow2(&r, d, index[a], index[b])
		}
	}
	return r, ""
}

// Gen_WFCAllows: may tile id `b` sit in direction `dir` (0 east, 1 south,
// 2 west, 3 north) of tile id `a`?
Gen_WFCAllows :: proc(r: ^Gen_WFC_Rules, a, b: i32, dir: int) -> bool {
	ia, ib := -1, -1
	for t, i in r.tiles {
		if t == a do ia = i
		if t == b do ib = i
	}
	if ia < 0 || ib < 0 do return false
	return r.allow[dir][ia * r.words + ib / 64] & (1 << uint(ib % 64)) != 0
}

// Gen_WFCResizeSample: a WFC node's sample of another size (1..64 each),
// its painted cells kept where they fit, new ones unpainted.
Gen_WFCResizeSample :: proc(g: ^Gen_Graph, n: ^Gen_Node, size: [2]int) {
	w, h := clamp(size.x, 1, GEN_WFC_SAMPLE_MAX), clamp(size.y, 1, GEN_WFC_SAMPLE_MAX)
	if n.sample.w == w && n.sample.h == h && len(n.sample.cells) == w * h do return
	cells := make([dynamic]i32, w * h, g.allocator)
	for &c in cells do c = -1
	old := &n.sample
	for y in 0 ..< min(h, old.h) do for x in 0 ..< min(w, old.w) do if y * old.w + x < len(old.cells) do cells[y * w + x] = old.cells[y * old.w + x]
	delete(old.cells)
	n.sample = {w, h, cells}
}

// Gen_WFCSetCell paints a sample cell (-1: unpainted); false outside it.
Gen_WFCSetCell :: proc(n: ^Gen_Node, x, y: int, tile: i32) -> bool {
	s := &n.sample
	if x < 0 || y < 0 || x >= s.w || y >= s.h || y * s.w + x >= len(s.cells) do return false
	if s.cells[y * s.w + x] == tile do return false
	s.cells[y * s.w + x] = tile
	return true
}

// --- the file ---------------------------------------------------------------------------

//   "sample": {"size": [w, h], "cells": [row by row; -1 unpainted]},
//   "wang": [{"tile": 3, "edges": [n, e, s, w], "weight": 1}]
// (No "sample": an unpainted 8 x 8 one, as a new node has - not written
// back until it is painted or resized.)
@(private)
gen_wfc_parse :: proc(n: ^Gen_Node, obj: json.Object, allocator := context.allocator) {
	{
		so, _ := obj["sample"].(json.Object)
		w, h := GEN_WFC_SAMPLE_DEFAULT, GEN_WFC_SAMPLE_DEFAULT
		if sz, sok := so["size"].(json.Array); sok && len(sz) >= 2 {
			fw, _ := json_number(sz[0])
			fh, _ := json_number(sz[1])
			w, h = clamp(int(fw), 1, GEN_WFC_SAMPLE_MAX), clamp(int(fh), 1, GEN_WFC_SAMPLE_MAX)
		}
		cells := make([dynamic]i32, w * h, allocator)
		for &c in cells do c = -1
		if cs, cok := so["cells"].(json.Array); cok do for cv, i in cs {
			if i >= w * h do break
			if v, isNum := json_number(cv); isNum do cells[i] = i32(v) if v >= 0 else -1
		}
		n.sample = {w, h, cells}
	}
	if ws, ok := obj["wang"].(json.Array); ok {
		n.wang = make([dynamic]Gen_Wang_Tile, allocator)
		for wv in ws {
			wo, isObj := wv.(json.Object)
			if !isObj do continue
			wt := Gen_Wang_Tile{weight = 1}
			if t, tok := json_number(wo["tile"]); tok do wt.tile = i32(t)
			if es, eok := wo["edges"].(json.Array); eok do for ev, i in es {
				if i >= 4 do break
				if v, isNum := json_number(ev); isNum do wt.edges[i] = i32(v)
			}
			if wgt, wok := json_number(wo["weight"]); wok do wt.weight = max(wgt, 0)
			append(&n.wang, wt)
		}
	}
}

@(private)
gen_wfc_serialize :: proc(w: ^Json_Writer, n: ^Gen_Node) {
	painted := false
	for c in n.sample.cells do if c >= 0 do painted = true
	if s := &n.sample; s.w > 0 && s.h > 0 && (painted || s.w != GEN_WFC_SAMPLE_DEFAULT || s.h != GEN_WFC_SAMPLE_DEFAULT) {
		fmt.sbprintf(&w.sb, ", \"sample\": {{\"size\": [%d, %d], \"cells\": [", s.w, s.h)
		for c, i in s.cells do fmt.sbprintf(&w.sb, "%s%d", ", " if i > 0 else "", c)
		strings.write_string(&w.sb, "]}")
	}
	if len(n.wang) > 0 {
		strings.write_string(&w.sb, ", \"wang\": [")
		for wt, i in n.wang {
			fmt.sbprintf(&w.sb, "%s{{\"tile\": %d, \"edges\": [%d, %d, %d, %d], \"weight\": ", ", " if i > 0 else "", wt.tile, wt.edges[0], wt.edges[1], wt.edges[2], wt.edges[3])
			Json_Float(w, wt.weight)
			strings.write_byte(&w.sb, '}')
		}
		strings.write_byte(&w.sb, ']')
	}
}

// gen_wfc_key: the sample and Wang tiles in a WFC node's cache key.
@(private)
gen_wfc_key :: proc(h: u64, n: ^Gen_Node) -> u64 {
	h := gen_mix(gen_mix(h, u64(n.sample.w)), u64(n.sample.h))
	if len(n.sample.cells) > 0 do h = gen_mix(h, hash.fnv64a(([^]u8)(raw_data(n.sample.cells))[:len(n.sample.cells) * size_of(i32)]))
	if len(n.wang) > 0 do h = gen_mix(h, hash.fnv64a(([^]u8)(raw_data(n.wang))[:len(n.wang) * size_of(Gen_Wang_Tile)]))
	return h
}

// --- the node ---------------------------------------------------------------------------

// gen_wfc: a WFC node's grid - tile ids, -1 where its mask is empty.
@(private)
gen_wfc :: proc(ev: ^Gen_Eval, n: ^Gen_Node, seed: u64, out: Gen_Grid) -> bool {
	fail :: proc(ev: ^Gen_Eval, n: ^Gen_Node, why: string) -> bool {
		ev.err = fmt.tprintf("node %d (wfc): %s", n.id, why)
		return false
	}
	rules, why := Gen_WFCRules(n)
	if why != "" do return fail(ev, n, why)
	mask := gen_input(ev, n, 0) or_return
	fixedGrid := gen_input(ev, n, 1) or_return
	cells := out.w * out.h
	active: []bool
	if n.inputs[0] != 0 {
		active = make([]bool, cells, context.temp_allocator)
		for v, i in mask.v do active[i] = v >= 0.5
	}
	fixed: []i32
	if n.inputs[1] != 0 {
		index := make(map[i32]int, allocator = context.temp_allocator)
		for t, i in rules.tiles do index[t] = i
		fixed = make([]i32, cells, context.temp_allocator)
		for v, i in fixedGrid.v {
			fixed[i] = -1
			if v < 0 do continue
			if k, ok := index[i32(math.round(v))]; ok do fixed[i] = i32(k)
		}
	}
	attempts := clamp(int(Gen_Param(n, "attempts")), 1, 100)
	s: Wfc_Solver
	wfc_init(&s, &rules, out.w, out.h, active)
	for try in 0 ..< attempts {
		trySeed := gen_mix(seed, u64(try) + 0x3fc)
		if wfc_run(&s, fixed, trySeed, ev.progress) {
			for i in 0 ..< cells {
				out.v[i] = -1
				if s.active != nil && !s.active[i] do continue
				out.v[i] = f32(rules.tiles[wfc_first(s.dom[i * s.words:(i + 1) * s.words])])
			}
			return true
		}
	}
	return fail(ev, n, fmt.tprintf("a contradiction on every try (%d) - the tiles can't fill the level next to each other as the rules say; paint a bigger sample, turn on wrap, or add tiles that fit between the others", attempts))
}

// --- the solver -------------------------------------------------------------------------

@(private = "file")
Wfc_Entry :: struct {
	key:   f64,
	cell:  i32,
	stamp: u32,
}

@(private = "file")
Wfc_Solver :: struct {
	r:        ^Gen_WFC_Rules,
	w, h:     int,
	words:    int,
	active:   []bool, // nil: every cell
	dom:      []u64,  // cells * words: the tiles each cell may still be
	count:    []i32,  // tiles left per cell
	sumW:     []f64,  // their weights' sum
	sumWLogW: []f64,  // sum of weight * log(weight)
	noise:    []f64,  // a cell's tie-breaker (tiny)
	stamp:    []u32,  // bumped when a cell's domain changes (older heap entries are stale)
	inStack:  []bool,
	stack:    [dynamic]i32,
	heap:     [dynamic]Wfc_Entry,
	full:     [4][]u64, // per direction: what a cell that can be any tile allows
	all:      []u64,    // every tile
	union_:   []u64,    // scratch
	wlogw:    []f64,    // per tile
	todo:     int,      // active cells
	decided:  int,
}

@(private = "file")
wfc_init :: proc(s: ^Wfc_Solver, r: ^Gen_WFC_Rules, w, h: int, active: []bool) {
	context.allocator = context.temp_allocator
	cells := w * h
	s.r, s.w, s.h, s.words, s.active = r, w, h, r.words, active
	s.dom = make([]u64, cells * s.words)
	s.count = make([]i32, cells)
	s.sumW = make([]f64, cells)
	s.sumWLogW = make([]f64, cells)
	s.noise = make([]f64, cells)
	s.stamp = make([]u32, cells)
	s.inStack = make([]bool, cells)
	s.stack = make([dynamic]i32, 0, cells)
	s.heap = make([dynamic]Wfc_Entry, 0, cells * 2)
	s.all = make([]u64, s.words)
	s.union_ = make([]u64, s.words)
	T := len(r.tiles)
	for t in 0 ..< T do s.all[t / 64] |= 1 << uint(t % 64)
	s.wlogw = make([]f64, T)
	for wt, t in r.weights do s.wlogw[t] = wt * math.ln(wt)
	for d in 0 ..< 4 {
		s.full[d] = make([]u64, s.words)
		for t in 0 ..< T do for k in 0 ..< s.words do s.full[d][k] |= r.allow[d][t * s.words + k]
	}
	s.todo = cells
	if active != nil {
		s.todo = 0
		for a in active do if a do s.todo += 1
	}
}

@(private = "file")
wfc_first :: #force_inline proc(set: []u64) -> int #no_bounds_check {
	for word, k in set do if word != 0 do return k * 64 + int(bits.count_trailing_zeros(word))
	return -1
}

@(private = "file")
wfc_on :: #force_inline proc(s: ^Wfc_Solver, i: int) -> bool #no_bounds_check {
	return s.active == nil || s.active[i]
}

// wfc_entropy: Shannon entropy of a cell's weighted tiles (plus its noise).
@(private = "file")
wfc_entropy :: #force_inline proc(s: ^Wfc_Solver, i: int) -> f64 #no_bounds_check {
	sw := s.sumW[i]
	return math.ln(sw) - s.sumWLogW[i] / sw + s.noise[i]
}

@(private = "file")
wfc_heap_push :: proc(s: ^Wfc_Solver, i: int) #no_bounds_check {
	append(&s.heap, Wfc_Entry{wfc_entropy(s, i), i32(i), s.stamp[i]})
	k := len(s.heap) - 1
	for k > 0 {
		p := (k - 1) / 2
		if s.heap[p].key <= s.heap[k].key do break
		s.heap[p], s.heap[k] = s.heap[k], s.heap[p]
		k = p
	}
}

@(private = "file")
wfc_heap_pop :: proc(s: ^Wfc_Solver) -> Wfc_Entry #no_bounds_check {
	top := s.heap[0]
	last := pop(&s.heap)
	if len(s.heap) == 0 do return top
	s.heap[0] = last
	k, n := 0, len(s.heap)
	for {
		l, rr := 2 * k + 1, 2 * k + 2
		m := k
		if l < n && s.heap[l].key < s.heap[m].key do m = l
		if rr < n && s.heap[rr].key < s.heap[m].key do m = rr
		if m == k do break
		s.heap[m], s.heap[k] = s.heap[k], s.heap[m]
		k = m
	}
	return top
}

// wfc_restrict: a cell keeps only the tiles of `keep`; false when none is
// left (a contradiction). Its neighbours are looked at again (the stack).
@(private = "file")
wfc_restrict :: proc(s: ^Wfc_Solver, i: int, keep: []u64) -> bool #no_bounds_check {
	d := s.dom[i * s.words:(i + 1) * s.words]
	changed := false
	for k in 0 ..< s.words {
		gone := d[k] & ~keep[k]
		if gone == 0 do continue
		changed = true
		d[k] &= keep[k]
		for gone != 0 {
			b := int(bits.count_trailing_zeros(gone))
			gone &= gone - 1
			t := k * 64 + b
			s.count[i] -= 1
			s.sumW[i] -= s.r.weights[t]
			s.sumWLogW[i] -= s.wlogw[t]
		}
	}
	if !changed do return true
	if s.count[i] <= 0 do return false
	if s.count[i] == 1 {
		s.decided += 1
	} else {
		s.stamp[i] += 1
		wfc_heap_push(s, i)
	}
	if !s.inStack[i] {
		s.inStack[i] = true
		append(&s.stack, i32(i))
	}
	return true
}

// wfc_propagate: until the stack is empty, each cell on it narrows its
// neighbours to the tiles its own tiles allow next to it.
@(private = "file")
wfc_propagate :: proc(s: ^Wfc_Solver) -> bool #no_bounds_check {
	r := s.r
	W := s.words
	for len(s.stack) > 0 {
		i := int(pop(&s.stack))
		s.inStack[i] = false
		x, y := i % s.w, i / s.w
		d := s.dom[i * W:(i + 1) * W]
		full := int(s.count[i]) == len(r.tiles)
		for dir in 0 ..< 4 {
			nx, ny := x + WFC_DX[dir], y + WFC_DY[dir]
			if nx < 0 || ny < 0 || nx >= s.w || ny >= s.h do continue
			j := ny * s.w + nx
			if !wfc_on(s, j) do continue
			u := s.full[dir]
			if !full {
				u = s.union_
				for k in 0 ..< W do u[k] = 0
				allow := r.allow[dir]
				for k in 0 ..< W {
					word := d[k]
					for word != 0 {
						t := k * 64 + int(bits.count_trailing_zeros(word))
						word &= word - 1
						row := allow[t * W:(t + 1) * W]
						for m in 0 ..< W do u[m] |= row[m]
					}
				}
			}
			if !wfc_restrict(s, j, u) do return false
		}
	}
	return true
}

@(private = "file")
wfc_rand01 :: proc(state: ^u64) -> f64 {
	state^ = gen_mix(state^, 0x2545f4914f6cdd1d)
	return f64(state^ >> 11) / f64(u64(1) << 53)
}

// wfc_run: one try - every cell any tile (fixed cells their tile), then
// collapse the lowest entropy cell and spread, until all are decided.
@(private = "file")
wfc_run :: proc(s: ^Wfc_Solver, fixed: []i32, seed: u64, progress: ^Gen_Progress) -> bool #no_bounds_check {
	r := s.r
	W := s.words
	T := len(r.tiles)
	sumW, sumWLogW: f64
	for t in 0 ..< T {
		sumW += r.weights[t]
		sumWLogW += s.wlogw[t]
	}
	clear(&s.stack)
	clear(&s.heap)
	s.decided = 0
	cells := s.w * s.h
	for i in 0 ..< cells {
		copy(s.dom[i * W:(i + 1) * W], s.all)
		s.count[i], s.sumW[i], s.sumWLogW[i] = i32(T), sumW, sumWLogW
		s.noise[i] = f64(gen_hash01(i % s.w, i / s.w, seed)) * 1e-6
		s.stamp[i] = 0
		s.inStack[i] = false
	}
	one := s.union_
	for i in 0 ..< cells {
		if !wfc_on(s, i) do continue
		if T == 1 do s.decided += 1
		if fixed != nil && fixed[i] >= 0 {
			for k in 0 ..< W do one[k] = 0
			one[fixed[i] / 64] |= 1 << uint(fixed[i] % 64)
			if !wfc_restrict(s, i, one) do return false
		}
		// (Every cell once: a tile with no neighbour allowed in a direction
		// goes from cells that have a neighbour there.)
		if !s.inStack[i] {
			s.inStack[i] = true
			append(&s.stack, i32(i))
		}
		if s.count[i] > 1 do wfc_heap_push(s, i)
	}
	if !wfc_propagate(s) do return false
	rng := seed
	steps := 0
	for len(s.heap) > 0 {
		e := wfc_heap_pop(s)
		i := int(e.cell)
		if e.stamp != s.stamp[i] || s.count[i] <= 1 do continue
		// A tile by weight.
		pick := wfc_rand01(&rng) * s.sumW[i]
		d := s.dom[i * W:(i + 1) * W]
		chosen := -1
		for k in 0 ..< W {
			word := d[k]
			for word != 0 {
				t := k * 64 + int(bits.count_trailing_zeros(word))
				word &= word - 1
				chosen = t
				pick -= r.weights[t]
				if pick < 0 do break
			}
			if pick < 0 do break
		}
		for k in 0 ..< W do one[k] = 0
		one[chosen / 64] |= 1 << uint(chosen % 64)
		if !wfc_restrict(s, i, one) do return false
		if !wfc_propagate(s) do return false
		steps += 1
		if progress != nil && steps & 255 == 0 do gen_progress_part(progress, f64(s.decided) / f64(max(s.todo, 1)))
	}
	return true
}
