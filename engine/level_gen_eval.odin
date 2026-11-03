package engine

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:hash"
import "core:math"
import "core:slice"
import "core:sync"
import "core:thread"
import lua "lua54"

// ============================================================================
// Level generator evaluation (#142, made fast in #171): a node's grid from
// its inputs, each node computed once per evaluation. The heavy kernels work
// on flat rows without bounds checks (cellular on a padded byte grid, blur
// as two sliding sums, noise from a precomputed lattice) and split their
// rows across a few worker threads (gen_parallel). A Gen_Cache keeps grids
// between evaluations, so the editor recomputes only what a change touches.
// ============================================================================

// Gen_Cache keeps nodes' grids between evaluations: a node whose settings,
// inputs, size, seed (and script text) are unchanged reuses its grid. One
// evaluation at a time uses it.
Gen_Cache :: struct {
	entries:   map[int]Gen_Cache_Entry,
	allocator: runtime.Allocator,
}

Gen_Cache_Entry :: struct {
	key:  u64,
	grid: Gen_Grid, // (the cache's allocator)
}

Gen_CacheInit :: proc(cache: ^Gen_Cache, allocator := context.allocator) {
	cache.allocator = allocator
	cache.entries = make(map[int]Gen_Cache_Entry, allocator)
}

Gen_CacheForget :: proc(cache: ^Gen_Cache, id: int) {
	if en, ok := cache.entries[id]; ok {
		delete(en.grid.v, cache.allocator)
		delete_key(&cache.entries, id)
	}
}

Gen_CacheClear :: proc(cache: ^Gen_Cache) {
	for _, en in cache.entries do delete(en.grid.v, cache.allocator)
	clear(&cache.entries)
}

Gen_CacheDestroy :: proc(cache: ^Gen_Cache) {
	Gen_CacheClear(cache)
	delete(cache.entries)
	cache^ = {}
}

// Gen_CachePrune forgets the nodes no longer in the graph.
Gen_CachePrune :: proc(cache: ^Gen_Cache, g: ^Gen_Graph) {
	gone := make([dynamic]int, context.temp_allocator)
	for id in cache.entries do if Gen_FindNode(g, id) == nil do append(&gone, id)
	for id in gone do Gen_CacheForget(cache, id)
}

// Gen_CacheGrid: a node's grid from the last evaluation that computed it.
Gen_CacheGrid :: proc(cache: ^Gen_Cache, id: int) -> (Gen_Grid, bool) {
	en, ok := cache.entries[id]
	return en.grid, ok
}

// --- one evaluation -------------------------------------------------------------------

@(private)
Gen_Eval :: struct {
	g:      ^Gen_Graph,
	seed:   u64,
	done:   map[int]Gen_Grid,
	active: map[int]bool, // being evaluated (a cycle if met again)
	keys:   map[int]u64,  // nodes' cache keys (with a cache)
	cache:  ^Gen_Cache,
	err:    string,
	L:      ^lua.State,   // Script nodes' (made by the first one, closed at the end)
	fns:    map[string]c.int, // script file -> its function (a registry ref in L)
	progress: ^Gen_Progress, // counts the nodes computed (nil: not followed)
}

// Gen_Progress follows a generation (#171): nodes computed of those it
// needs, mapped to a fraction 0..1 that only grows - readable from another
// thread while a worker generates (Gen_ProgressValue). Each attempt (a seed
// tried again after a Check refused one) fills most of what is left - the
// last allowed one all of it - so a retry carries on from where the failed
// attempt stopped.
Gen_Progress :: struct {
	done, total: int, // nodes computed / needed (this attempt)
	base, span:  f64, // this attempt's part of 0..1
	value:       u32, // the fraction in millionths (atomic)
}

GEN_PROGRESS_ONE :: 1_000_000

// Gen_ProgressValue: the fraction done, 0..1 (any thread).
Gen_ProgressValue :: proc(p: ^Gen_Progress) -> f64 {
	return f64(sync.atomic_load(&p.value)) / GEN_PROGRESS_ONE
}

// Gen_ProgressAttempt starts an attempt: `total` nodes to compute, filling
// all that is left when it is the last one allowed, else 90% of it.
Gen_ProgressAttempt :: proc(p: ^Gen_Progress, total: int, last: bool) {
	p.done, p.total = 0, max(total, 1)
	p.base = Gen_ProgressValue(p)
	p.span = (1 - p.base) * (1 if last else 0.9)
}

// gen_progress_step: one more node computed.
@(private)
gen_progress_step :: proc(p: ^Gen_Progress) {
	if p == nil do return
	p.done = min(p.done + 1, p.total)
	v := u32(clamp(p.base + p.span * f64(p.done) / f64(p.total), 0, 1) * GEN_PROGRESS_ONE)
	if v > sync.atomic_load(&p.value) do sync.atomic_store(&p.value, v)
}

// gen_progress_part: the node being computed is `frac` (0..1) done - for
// nodes that take a while on their own (Wave Function Collapse).
@(private)
gen_progress_part :: proc(p: ^Gen_Progress, frac: f64) {
	if p == nil do return
	v := u32(clamp(p.base + p.span * (f64(p.done) + clamp(frac, 0, 1)) / f64(p.total), 0, 1) * GEN_PROGRESS_ONE)
	if v > sync.atomic_load(&p.value) do sync.atomic_store(&p.value, v)
}

// Gen_NeededNodes: how many nodes a generation (Gen_Generate) computes -
// those its outputs read, each once.
Gen_NeededNodes :: proc(g: ^Gen_Graph) -> int {
	seen := make(map[int]bool, allocator = context.temp_allocator)
	visit :: proc(g: ^Gen_Graph, id: int, seen: ^map[int]bool) {
		if id == 0 || id in seen^ do return
		n := Gen_FindNode(g, id)
		if n == nil do return
		seen[id] = true
		for src in n.inputs do visit(g, src, seen)
	}
	main := Gen_OutputNode(g)
	if main != nil do visit(g, main.id, &seen)
	for &n in g.nodes {
		if n.kind == .Tile_Output && (n.layer != "" || Gen_WritesComponents(&n)) do visit(g, n.id, &seen)
		if n.kind == .Entity_Output && n.component != "" do visit(g, n.id, &seen)
	}
	return len(seen)
}

@(private)
gen_eval_begin :: proc(g: ^Gen_Graph, seed: u64, cache: ^Gen_Cache = nil) -> Gen_Eval {
	ev := Gen_Eval{g = g, seed = seed if seed != 0 else g.seed, cache = cache}
	ev.done = make(map[int]Gen_Grid, allocator = context.temp_allocator)
	ev.active = make(map[int]bool, allocator = context.temp_allocator)
	ev.keys = make(map[int]u64, allocator = context.temp_allocator)
	ev.fns = make(map[string]c.int, allocator = context.temp_allocator)
	return ev
}

@(private)
gen_eval_end :: proc(ev: ^Gen_Eval) {
	if ev.L != nil do lua.close(ev.L)
	ev.L = nil
}

// Gen_Evaluate computes a node's grid (id 0: the output node) for a seed
// (the graph's seed when 0). The grid's values are in `allocator`. With a
// cache, unchanged nodes reuse their grids from earlier evaluations.
Gen_Evaluate :: proc(g: ^Gen_Graph, id := 0, seed: u64 = 0, allocator := context.allocator, cache: ^Gen_Cache = nil) -> (grid: Gen_Grid, err: string) {
	target := Gen_OutputNode(g) if id == 0 else Gen_FindNode(g, id)
	if target == nil do return {}, "the graph has no nodes" if id == 0 else fmt.tprintf("no node %d", id)
	ev := gen_eval_begin(g, seed, cache)
	defer gen_eval_end(&ev)
	tmp, ok := gen_eval(&ev, target.id)
	if !ok do return {}, ev.err
	grid = {tmp.w, tmp.h, make([]f32, len(tmp.v), allocator)}
	copy(grid.v, tmp.v)
	return grid, ""
}

Gen_GridDestroy :: proc(grid: ^Gen_Grid, allocator := context.allocator) {
	delete(grid.v, allocator)
	grid.v = nil
}

@(private)
gen_new :: proc(ev: ^Gen_Eval) -> Gen_Grid {
	w, h := ev.g.size.x, ev.g.size.y
	return {w, h, make([]f32, w * h, context.temp_allocator)}
}

// gen_input: a node's input grid (empty - zeros - when not connected).
@(private)
gen_input :: proc(ev: ^Gen_Eval, n: ^Gen_Node, i: int) -> (Gen_Grid, bool) {
	if n.inputs[i] == 0 do return gen_new(ev), true
	return gen_eval(ev, n.inputs[i])
}

// gen_key: what a node's grid depends on - its kind and settings, its
// inputs' keys, the size, the seed, a script's text, a custom kind's proc -
// hashed (equal keys: the same grid).
@(private)
gen_key :: proc(ev: ^Gen_Eval, id: int) -> u64 {
	if k, ok := ev.keys[id]; ok do return k
	ev.keys[id] = 0 // (a cycle: reported by the evaluation)
	n := Gen_FindNode(ev.g, id)
	if n == nil do return 0
	h := gen_mix(gen_mix(ev.seed, u64(id)), u64(n.kind) + 1)
	h = gen_mix(gen_mix(h, u64(ev.g.size.x)), u64(ev.g.size.y))
	for p in n.params do h = gen_mix(h, transmute(u64)p)
	for src in n.inputs do h = gen_mix(h, gen_key(ev, src) if src != 0 else 0x5eed)
	switch n.kind {
	case .Script:
		h = gen_mix(h, hash.fnv64a(transmute([]u8)n.script))
		if src, ok := ev.g.scripts[n.script]; ok do h = gen_mix(h, hash.fnv64a(transmute([]u8)src))
	case .Custom:
		h = gen_mix(h, hash.fnv64a(transmute([]u8)n.custom))
		if def := Gen_FindCustomKind(n.custom); def != nil do h = gen_mix(h, u64(uintptr(rawptr(def.eval))))
	case .WFC:
		h = gen_wfc_key(h, n)
	case .Constant, .Noise, .Random_Fill, .Gradient, .Border, .Rect, .Rooms, .Walker, .Lines, .Rectangles, .Circles, .Threshold, .Invert, .Remap, .Blur, .Cellular, .Dilate, .Erode, .Combine, .Scatter, .Poisson_Scatter, .Surface, .Flood_Fill, .Regions, .Connect_Regions, .Path, .Check, .Tile_Output, .Entity_Output:
	}
	ev.keys[id] = h
	return h
}

@(private)
gen_eval :: proc(ev: ^Gen_Eval, id: int) -> (result: Gen_Grid, ok: bool) {
	if grid, ok := ev.done[id]; ok do return grid, true
	n := Gen_FindNode(ev.g, id)
	if n == nil {
		ev.err = fmt.tprintf("a node is connected to node %d, which doesn't exist", id)
		return {}, false
	}
	if ev.active[id] {
		ev.err = fmt.tprintf("a cycle through node %d", id)
		return {}, false
	}
	key: u64
	if ev.cache != nil {
		key = gen_key(ev, id)
		if en, hit := ev.cache.entries[id]; hit && en.key == key && en.grid.w == ev.g.size.x && en.grid.h == ev.g.size.y {
			ev.done[id] = en.grid
			return en.grid, true
		}
	}
	ev.active[id] = true
	defer delete_key(&ev.active, id)
	out := gen_new(ev)
	gen_compute(ev, n, out) or_return
	gen_progress_step(ev.progress)
	if ev.cache != nil {
		// Kept for the next evaluation (replacing the node's last grid).
		Gen_CacheForget(ev.cache, id)
		kept := Gen_Grid{out.w, out.h, make([]f32, len(out.v), ev.cache.allocator)}
		copy(kept.v, out.v)
		ev.cache.entries[id] = {key, kept}
		out = kept
	}
	ev.done[id] = out
	return out, true
}

// gen_compute fills `out` (zeros, the level's size) with a node's grid.
@(private)
gen_compute :: proc(ev: ^Gen_Eval, n: ^Gen_Node, out: Gen_Grid) -> bool {
	nodeSeed := gen_mix(gen_mix(ev.seed, u64(n.id)), u64(i64(Gen_Param(n, "seed"))))
	w, h := out.w, out.h
	p :: Gen_Param
	switch n.kind {
	case .Constant:
		slice.fill(out.v, f32(p(n, "value")))
	case .Noise:
		scale, octaves, persistence := max(f32(p(n, "scale")), 0.5), clamp(int(p(n, "octaves")), 1, 8), f32(p(n, "persistence"))
		switch int(p(n, "type")) {
		case 1: gen_gradient_noise(out, {0, 0}, scale, octaves, persistence, nodeSeed, false)
		case 2: gen_gradient_noise(out, {0, 0}, scale, octaves, persistence, nodeSeed, true)
		case: gen_noise(out, scale, octaves, persistence, nodeSeed)
		}
	case .Random_Fill:
		job := Gen_Fill_Job{out, f32(p(n, "density")), nodeSeed}
		gen_parallel(h, w, &job, proc(data: rawptr, y0, y1: int) {
			j := cast(^Gen_Fill_Job)data
			#no_bounds_check for y in y0 ..< y1 do for x in 0 ..< j.out.w do j.out.v[y * j.out.w + x] = 1 if gen_hash01(x, y, j.seed) < j.density else 0
		})
	case .Gradient:
		dir := int(p(n, "direction"))
		for y in 0 ..< h do for x in 0 ..< w {
			v: f32
			switch dir {
			case 1: v = f32(y) / f32(max(h - 1, 1))
			case 2:
				dx, dy := (f32(x) - f32(w - 1) * 0.5) / max(f32(w - 1) * 0.5, 1), (f32(y) - f32(h - 1) * 0.5) / max(f32(h - 1) * 0.5, 1)
				v = clamp(1 - math.sqrt(dx * dx + dy * dy) / math.SQRT_TWO, 0, 1)
			case: v = f32(x) / f32(max(w - 1, 1))
			}
			out.v[y * w + x] = v
		}
	case .Border:
		bw := int(p(n, "width"))
		for y in 0 ..< h do for x in 0 ..< w do out.v[y * w + x] = 1 if x < bw || y < bw || x >= w - bw || y >= h - bw else 0
	case .Rect:
		rx, ry, rw, rh := int(p(n, "x")), int(p(n, "y")), int(p(n, "w")), int(p(n, "h"))
		val := f32(p(n, "value"))
		x0 := clamp(rx, 0, w)
		x1 := clamp(rx + rw, x0, w)
		for y in max(ry, 0) ..< min(ry + rh, h) do slice.fill(out.v[y * w + x0:y * w + x1], val)
	case .Threshold:
		src := gen_input(ev, n, 0) or_return
		t := f32(p(n, "value"))
		inv := p(n, "invert") != 0
		#no_bounds_check for v, i in src.v do out.v[i] = 1 if (v >= t) != inv else 0
	case .Invert:
		src := gen_input(ev, n, 0) or_return
		#no_bounds_check for v, i in src.v do out.v[i] = 1 - v
	case .Remap:
		src := gen_input(ev, n, 0) or_return
		a0, a1, b0, b1 := f32(p(n, "from_min")), f32(p(n, "from_max")), f32(p(n, "to_min")), f32(p(n, "to_max"))
		span := a1 - a0 if a1 != a0 else 1
		#no_bounds_check for v, i in src.v do out.v[i] = b0 + clamp((v - a0) / span, 0, 1) * (b1 - b0)
	case .Blur:
		src := gen_input(ev, n, 0) or_return
		gen_blur(src, out, clamp(int(p(n, "radius")), 0, 32))
	case .Cellular:
		src := gen_input(ev, n, 0) or_return
		gen_cellular(src, out, clamp(int(p(n, "iterations")), 0, 64), int(p(n, "birth")), int(p(n, "survive")), p(n, "edge_solid") != 0)
	case .Dilate, .Erode:
		src := gen_input(ev, n, 0) or_return
		gen_morph(src, out, clamp(int(p(n, "iterations")), 0, 64), n.kind == .Dilate)
	case .Combine:
		a := gen_input(ev, n, 0) or_return
		b := gen_input(ev, n, 1) or_return
		gen_combine(a.v, b.v, out.v, int(p(n, "op")))
	case .Script:
		gen_script(ev, n, nodeSeed, out) or_return
	case .Custom:
		def := Gen_FindCustomKind(n.custom)
		if def == nil {
			ev.err = fmt.tprintf("node %d: no node type %q is registered", n.id, n.custom)
			return false
		}
		call := Gen_Custom_Call{node = n, out = out, seed = nodeSeed}
		for i in 0 ..< len(def.info.inputs) do call.inputs[i] = gen_input(ev, n, i) or_return
		if e := def.eval(&call); e != "" {
			ev.err = fmt.tprintf("node %d (%s): %s", n.id, n.custom, e)
			return false
		}
	case .Tile_Output, .Entity_Output:
		src := gen_input(ev, n, 0) or_return
		copy(out.v, src.v) // (the tiles / entities come from Gen_Tiles / Gen_Entities: its grid is its input's)
	case .Rooms:
		minS := clamp(int(p(n, "min_size")), 2, 256)
		maxS := clamp(int(p(n, "max_size")), minS, 512)
		rng := nodeSeed
		out := out
		gen_bsp(&out, {1, 1, w - 2, h - 2}, minS, maxS, max(int(p(n, "corridor")), 1), &rng, 0)
	case .Walker:
		rng := nodeSeed
		out := out
		brush := clamp(int(p(n, "brush")), 1, 16)
		dirs := [4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
		for _ in 0 ..< clamp(int(p(n, "walkers")), 1, 64) {
			pos := [2]int{w / 2, h / 2}
			for _ in 0 ..< clamp(int(p(n, "steps")), 0, 1_000_000) {
				gen_carve(&out, pos.x - (brush - 1) / 2, pos.y - (brush - 1) / 2, brush, brush)
				d := dirs[gen_rand_int(&rng, 0, 3)]
				pos = {clamp(pos.x + d.x, 1, max(w - 2, 1)), clamp(pos.y + d.y, 1, max(h - 2, 1))}
			}
		}
	case .Lines:
		gen_lines(out, clamp(int(p(n, "count")), 0, 10_000), int(p(n, "min_length")), int(p(n, "max_length")), clamp(int(p(n, "thickness")), 1, 64), int(p(n, "direction")), nodeSeed)
	case .Rectangles:
		gen_rectangles(out, clamp(int(p(n, "count")), 0, 10_000), int(p(n, "min_size")), int(p(n, "max_size")), clamp(int(p(n, "thickness")), 1, 64), p(n, "filled") != 0, nodeSeed)
	case .Circles:
		gen_circles(out, clamp(int(p(n, "count")), 0, 10_000), int(p(n, "min_radius")), int(p(n, "max_radius")), clamp(int(p(n, "thickness")), 1, 64), p(n, "filled") != 0, nodeSeed)
	case .Scatter:
		src := gen_input(ev, n, 0) or_return
		gen_scatter(src, out, n.inputs[0] != 0, f32(p(n, "chance")), clamp(int(p(n, "spacing")), 0, 256), nodeSeed)
	case .Poisson_Scatter:
		src := gen_input(ev, n, 0) or_return
		gen_poisson(src, out, n.inputs[0] != 0, clamp(f32(p(n, "radius")), 1, 256), clamp(int(p(n, "attempts")), 1, 100), nodeSeed)
	case .Surface:
		src := gen_input(ev, n, 0) or_return
		gen_surface(src, out, int(p(n, "side")))
	case .Flood_Fill:
		src := gen_input(ev, n, 0) or_return
		gen_flood_fill(src, out, int(p(n, "x")), int(p(n, "y")), p(n, "open") != 0, p(n, "diagonal") != 0)
	case .Regions:
		src := gen_input(ev, n, 0) or_return
		gen_regions(src, out, p(n, "mode") != 0, int(p(n, "min_size")), p(n, "open") != 0, p(n, "diagonal") != 0)
	case .Connect_Regions:
		src := gen_input(ev, n, 0) or_return
		gen_connect_regions(src, out, clamp(int(p(n, "width")), 1, 16), int(p(n, "min_size")), p(n, "open") != 0, p(n, "diagonal") != 0)
	case .Path:
		src := gen_input(ev, n, 0) or_return
		custom := [4]int{int(p(n, "start_x")), int(p(n, "start_y")), int(p(n, "end_x")), int(p(n, "end_y"))}
		gen_path(src, out, int(p(n, "placement")), custom, clamp(int(p(n, "width")), 1, 16), p(n, "open") != 0, int(p(n, "output")))
	case .WFC:
		gen_wfc(ev, n, nodeSeed, out) or_return
	case .Check:
		src := gen_input(ev, n, 0) or_return
		if why := gen_check(src, f32(p(n, "min_open")), p(n, "connected") != 0, p(n, "open") != 0, p(n, "diagonal") != 0); why != "" {
			ev.err = fmt.tprintf("node %d (check): %s", n.id, why)
			return false
		}
		copy(out.v, src.v)
	}
	return true
}

// --- tiles and entities -----------------------------------------------------------------

// Gen_Tiles turns a Tile_Output node's grid into tile indices (row-major;
// -1 = empty): the first rule whose range holds the value, one of its
// tiles picked by a hash of the cell and the seed.
Gen_Tiles :: proc(g: ^Gen_Graph, outputId := 0, seed: u64 = 0, allocator := context.allocator, cache: ^Gen_Cache = nil) -> (tiles: []i32, size: [2]int, err: string) {
	ev := gen_eval_begin(g, seed, cache)
	defer gen_eval_end(&ev)
	return gen_tiles(&ev, outputId, allocator)
}

@(private)
gen_tiles :: proc(ev: ^Gen_Eval, outputId: int, allocator: runtime.Allocator) -> (tiles: []i32, size: [2]int, err: string) {
	out := Gen_OutputNode(ev.g) if outputId == 0 else Gen_FindNode(ev.g, outputId)
	if out == nil do return nil, {}, "the graph has no nodes"
	if out.kind != .Tile_Output do return nil, {}, fmt.tprintf("node %d isn't a tile output", out.id)
	grid, ok := gen_eval(ev, out.id)
	if !ok do return nil, {}, ev.err
	terrains: Tile_Terrains
	if text, ok := ev.g.tilesets[out.tileset]; ok do terrains, _ = Terrains_Parse(transmute([]u8)text, context.temp_allocator)
	return Gen_TilesOf(out, grid, ev.seed, allocator, &terrains, ev.g.layout, ev.g.stagger), {grid.w, grid.h}, ""
}

// Gen_TilesOf: a tile output's tiles for its grid (already evaluated) and
// the evaluation's seed (the graph's when it was 0). A rule naming a
// terrain (of `terrains`, its tileset's) makes its cells that terrain, each
// then given the tile of its pattern - cells beyond the level count as the
// terrain, so it runs on past the edges. A terrain it doesn't have: empty.
Gen_TilesOf :: proc(out: ^Gen_Node, grid: Gen_Grid, seed: u64, allocator := context.allocator, terrains: ^Tile_Terrains = nil, layout := TileMap_Layout.Square, stagger := TileMap_Stagger.Odd) -> []i32 {
	pickSeed := gen_mix(gen_mix(seed, u64(out.id)), 0x7111e)
	empty := i32(Gen_Param(out, "empty"))
	tiles := make([]i32, len(grid.v), allocator)
	if Gen_Param(out, "tile_ids") != 0 {
		// (#171) The values are the tiles (a Wave Function Collapse node's).
		#no_bounds_check for v, i in grid.v do tiles[i] = i32(math.round(v)) if v >= 0 else empty
		gen_pattern_rules(out, grid, tiles, pickSeed)
		return tiles
	}
	// (Each rule's terrain, found once; -1: tiles.)
	ruleTerrain := make([]int, len(out.rules), context.temp_allocator)
	anyTerrain := false
	for r, k in out.rules {
		ruleTerrain[k] = -1
		if r.terrain == "" do continue
		anyTerrain = true
		ruleTerrain[k] = -2 // (named, but not in the tileset)
		if _, ti := Terrains_Find(terrains, r.terrain); ti >= 0 do ruleTerrain[k] = ti
	}
	cellTerrain: []i16
	if anyTerrain {
		cellTerrain = make([]i16, len(grid.v), context.temp_allocator)
		for &c in cellTerrain do c = -1
	}
	#no_bounds_check for v, i in grid.v {
		t := empty
		for r, k in out.rules {
			if v < r.min || v > r.max do continue
			if ruleTerrain[k] != -1 {
				if ruleTerrain[k] >= 0 do cellTerrain[i] = i16(ruleTerrain[k])
				break
			}
			if len(r.tiles) == 0 do continue
			t = r.tiles[0] if len(r.tiles) == 1 else r.tiles[int(gen_hash01(i % grid.w, i / grid.w, pickSeed) * f32(len(r.tiles))) % len(r.tiles)]
			break
		}
		tiles[i] = t
	}
	w, h := grid.w, grid.h
	defer gen_pattern_rules(out, grid, tiles, pickSeed) // (last: over the rules' and terrains' tiles)
	if !anyTerrain do return tiles
	if layout != .Square {
		// Isometric, staggered, hex: the grid's own neighbours.
		Ctx :: struct {cells: []i16, w, h: int, c: i16}
		member :: proc(q: [2]int, data: rawptr) -> bool {
			k := cast(^Ctx)data
			return q.x < 0 || q.y < 0 || q.x >= k.w || q.y >= k.h || k.cells[q.y * k.w + q.x] == k.c
		}
		for c, i in cellTerrain {
			if c < 0 do continue
			k := Ctx{cellTerrain[:], w, h, c}
			t := &terrains.terrains[c]
			if tile := Terrain_Tile(t, Terrain_MaskAt(t.kind, layout, stagger, {i % w, i / w}, &k, member), i % w, i / w, pickSeed); tile >= 0 do tiles[i] = tile
		}
		return tiles
	}
	#no_bounds_check for c, i in cellTerrain {
		if c < 0 do continue
		x, y := i % w, i / w
		nb: [3][3]bool
		for dy in 0 ..< 3 do for dx in 0 ..< 3 {
			nx, ny := x + dx - 1, y + dy - 1
			nb[dy][dx] = nx < 0 || ny < 0 || nx >= w || ny >= h || cellTerrain[ny * w + nx] == c
		}
		t := &terrains.terrains[c]
		if tile := Terrain_Tile(t, Terrain_Mask(t.kind, nb), x, y, pickSeed); tile >= 0 do tiles[i] = tile
	}
	return tiles
}

// gen_pattern_rules: a tile output's pattern rules over its tiles - each
// cell the first rule whose 3x3 pattern matches the grid around it (and
// whose chance the cell's hash is under) takes one of its tiles.
@(private = "file")
gen_pattern_rules :: proc(out: ^Gen_Node, grid: Gen_Grid, tiles: []i32, seed: u64) #no_bounds_check {
	if len(out.patterns) == 0 do return
	w, h := grid.w, grid.h
	for y in 0 ..< h do for x in 0 ..< w {
		for &pr, k in out.patterns {
			if len(pr.tiles) == 0 do continue
			match := true
			for c, ci in pr.cells {
				if c == 0 do continue
				nx, ny := x + ci % 3 - 1, y + ci / 3 - 1
				inside := nx < 0 || ny < 0 || nx >= w || ny >= h
				if !inside {
					v := grid.v[ny * w + nx]
					inside = v >= pr.min && v <= pr.max
				}
				if inside != (c > 0) {
					match = false
					break
				}
			}
			if !match do continue
			ps := gen_mix(seed, u64(k) + 0x9a77)
			if pr.chance < 1 && gen_hash01(x, y, ps) >= pr.chance do continue
			tiles[y * w + x] = pr.tiles[0] if len(pr.tiles) == 1 else pr.tiles[int(gen_hash01(x, y, ps ~ 0x51) * f32(len(pr.tiles))) % len(pr.tiles)]
			break
		}
	}
}

// A generated level: its tiles and entity placements (Gen_Generate) -
// computed on any thread (the graph untouched), applied on the main one
// (Gen_ApplyResult). The entities' components are the graph's: keep it
// until the result is applied.
Gen_Result :: struct {
	size:     [2]int,
	tiles:    []i32, // the output's (the main map; nil when the output writes components)
	layers:   [dynamic]Gen_Layer_Tiles, // the other tile outputs with a layer
	entities: [dynamic]Gen_Entity,
	components: [dynamic]Gen_Layer_Component, // tile outputs that write components (#171)
}

// A component an output that writes components paints on the component
// layer of its map (`layer`: the TileMap of that name next to the main
// one; "": the main one), at a cell.
Gen_Layer_Component :: struct {
	layer:     string, // (the graph's)
	component: string, // (the graph's)
	cell:      [2]int,
}

// A layer's tiles: for the TileMap named `name` next to the main one.
Gen_Layer_Tiles :: struct {
	name:  string, // (the graph's)
	tiles: []i32,
}

// Gen_Generate: the level's tiles, components and entities, the graph
// evaluated once. `progress`: counts the nodes computed (for a loading bar;
// Gen_ProgressAttempt first).
Gen_Generate :: proc(g: ^Gen_Graph, seed: u64 = 0, allocator := context.allocator, progress: ^Gen_Progress = nil) -> (r: Gen_Result, err: string) {
	ev := gen_eval_begin(g, seed)
	ev.progress = progress
	defer gen_eval_end(&ev)
	main := Gen_OutputNode(g)
	r.layers = make([dynamic]Gen_Layer_Tiles, allocator)
	r.components = make([dynamic]Gen_Layer_Component, allocator)
	if main != nil && Gen_WritesComponents(main) {
		r.size = g.size // (the main map's tiles stay)
	} else {
		r.tiles, r.size, err = gen_tiles(&ev, 0, allocator)
	}
	if err == "" do for &n in g.nodes {
		if n.kind != .Tile_Output do continue
		if Gen_WritesComponents(&n) {
			grid, ok := gen_eval(&ev, n.id)
			if !ok {
				err = ev.err
				break
			}
			for k, i in Gen_ComponentsOf(&n, grid, context.temp_allocator) {
				if k >= 0 do append(&r.components, Gen_Layer_Component{n.layer, n.rules[k].component, {i % grid.w, i / grid.w}})
			}
			continue
		}
		if n.layer == "" || (main != nil && n.id == main.id) do continue
		tiles: []i32
		tiles, _, err = gen_tiles(&ev, n.id, allocator)
		if err != "" do break
		append(&r.layers, Gen_Layer_Tiles{n.layer, tiles})
	}
	if err == "" do r.entities, err = gen_entities(&ev, allocator)
	if err != "" do Gen_ResultDestroy(&r, allocator)
	return
}

// Gen_ComponentsOf: for an output that writes components, each cell's rule
// (an index into its rules: the first whose range holds the value and that
// names a component; -1: none).
Gen_ComponentsOf :: proc(out: ^Gen_Node, grid: Gen_Grid, allocator := context.allocator) -> []int {
	ks := make([]int, len(grid.v), allocator)
	#no_bounds_check for v, i in grid.v {
		ks[i] = -1
		for r, k in out.rules do if r.component != "" && v >= r.min && v <= r.max {
			ks[i] = k
			break
		}
	}
	return ks
}

Gen_ResultDestroy :: proc(r: ^Gen_Result, allocator := context.allocator) {
	delete(r.tiles, allocator)
	for ly in r.layers do delete(ly.tiles, allocator)
	delete(r.layers)
	delete(r.entities)
	delete(r.components)
	r^ = {}
}

// A component placed by an entity output, at a cell.
Gen_Entity :: struct {
	component: string, // (the graph's)
	cell:      [2]int,
}

// Gen_Entities: every entity output's placements (its points: cells >=
// 0.5; with `max`, that many picked by the seed), in node then row order.
Gen_Entities :: proc(g: ^Gen_Graph, seed: u64 = 0, allocator := context.allocator) -> (out: [dynamic]Gen_Entity, err: string) {
	ev := gen_eval_begin(g, seed)
	defer gen_eval_end(&ev)
	return gen_entities(&ev, allocator)
}

@(private)
gen_entities :: proc(ev: ^Gen_Eval, allocator: runtime.Allocator) -> (out: [dynamic]Gen_Entity, err: string) {
	out = make([dynamic]Gen_Entity, allocator)
	for &n in ev.g.nodes {
		if n.kind != .Entity_Output || n.component == "" do continue
		grid, ok := gen_eval(ev, n.id)
		if !ok do return out, ev.err
		Cell :: struct {cell: [2]int, key: f32}
		cells := make([dynamic]Cell, context.temp_allocator)
		pickSeed := gen_mix(gen_mix(ev.seed, u64(n.id)), 0xe171)
		for v, i in grid.v do if v >= 0.5 do append(&cells, Cell{{i % grid.w, i / grid.w}, gen_hash01(i % grid.w, i / grid.w, pickSeed)})
		limit := int(Gen_Param(&n, "max"))
		if limit > 0 && len(cells) > limit {
			// The `limit` with the lowest keys, back in row order.
			keys := make([]f32, len(cells), context.temp_allocator)
			for c, i in cells do keys[i] = c.key
			slice.sort(keys)
			cut := keys[limit - 1]
			kept := 0
			for c in cells do if c.key <= cut && kept < limit {
				append(&out, Gen_Entity{n.component, c.cell})
				kept += 1
			}
			continue
		}
		for c in cells do append(&out, Gen_Entity{n.component, c.cell})
	}
	return out, ""
}

// --- kernels ------------------------------------------------------------------------------

@(private = "file")
Gen_Fill_Job :: struct {
	out:     Gen_Grid,
	density: f32,
	seed:    u64,
}

// gen_noise: value noise fBm. Each octave's lattice of random corners is
// made once (a cell then reads four of them instead of hashing four) -
// unless the lattice would be far bigger than the grid (tiny features).
@(private = "file")
Gen_Noise_Job :: struct {
	out:         Gen_Grid,
	octaves:     int,
	freq, amp:   [8]f32,
	norm:        f32,
	seed:        u64,
	lattice:     [8][]f32,
	lw:          [8]int,
}

@(private = "file")
gen_noise :: proc(out: Gen_Grid, scale: f32, octaves: int, persistence: f32, seed: u64) {
	job := Gen_Noise_Job{out = out, octaves = octaves, seed = seed}
	amp, freq: f32 = 1, 1 / scale
	for o in 0 ..< octaves {
		job.freq[o], job.amp[o] = freq, amp
		job.norm += amp
		lw, lh := int(math.floor(f32(out.w - 1) * freq)) + 2, int(math.floor(f32(out.h - 1) * freq)) + 2
		if lw * lh <= 4 * out.w * out.h + 64 {
			oseed := seed + u64(o) * 7919
			lat := make([]f32, lw * lh, context.temp_allocator)
			for j in 0 ..< lh do for i in 0 ..< lw do lat[j * lw + i] = gen_hash01(i, j, oseed)
			job.lattice[o], job.lw[o] = lat, lw
		}
		amp *= persistence
		freq *= 2
	}
	job.norm = max(job.norm, 0.0001)
	gen_parallel(out.h, out.w * octaves * 2, &job, proc(data: rawptr, y0, y1: int) {
		j := cast(^Gen_Noise_Job)data
		w := j.out.w
		#no_bounds_check for y in y0 ..< y1 do for x in 0 ..< w {
			sum: f32
			for o in 0 ..< j.octaves {
				fx, fy := f32(x) * j.freq[o], f32(y) * j.freq[o]
				lat := j.lattice[o]
				if lat == nil {
					sum += gen_value_noise(fx, fy, j.seed + u64(o) * 7919) * j.amp[o]
					continue
				}
				x0, y0 := math.floor(fx), math.floor(fy)
				tx, ty := fx - x0, fy - y0
				ix, iy, lw := int(x0), int(y0), j.lw[o]
				sx, sy := tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
				k := iy * lw + ix
				a, b, c, d := lat[k], lat[k + 1], lat[k + lw], lat[k + lw + 1]
				sum += math.lerp(math.lerp(a, b, sx), math.lerp(c, d, sx), sy) * j.amp[o]
			}
			j.out.v[y * w + x] = sum / j.norm
		}
	})
}

// gen_blur: the average over a (2r+1)^2 box clipped to the grid - a
// sliding sum along each row, then one down each band of columns: the same
// cost whatever the radius.
@(private = "file")
Gen_Blur_Job :: struct {
	src, out: Gen_Grid,
	rows:     []f32, // the row sums
	r:        int,
}

GEN_BLUR_BAND :: 64

@(private = "file")
gen_blur :: proc(src, out: Gen_Grid, r: int) {
	if r == 0 {
		copy(out.v, src.v)
		return
	}
	job := Gen_Blur_Job{src = src, out = out, rows = make([]f32, len(src.v), context.temp_allocator), r = r}
	gen_parallel(out.h, out.w * 4, &job, proc(data: rawptr, y0, y1: int) {
		j := cast(^Gen_Blur_Job)data
		w, r := j.src.w, j.r
		#no_bounds_check for y in y0 ..< y1 {
			row := j.src.v[y * w:(y + 1) * w]
			sum: f64
			for x in 0 ..= min(r, w - 1) do sum += f64(row[x])
			for x in 0 ..< w {
				j.rows[y * w + x] = f32(sum)
				if x + r + 1 < w do sum += f64(row[x + r + 1])
				if x - r >= 0 do sum -= f64(row[x - r])
			}
		}
	})
	bands := (out.w + GEN_BLUR_BAND - 1) / GEN_BLUR_BAND
	gen_parallel(bands, out.h * GEN_BLUR_BAND * 4, &job, proc(data: rawptr, b0, b1: int) {
		j := cast(^Gen_Blur_Job)data
		w, h, r := j.src.w, j.src.h, j.r
		#no_bounds_check for b in b0 ..< b1 {
			x0, x1 := b * GEN_BLUR_BAND, min((b + 1) * GEN_BLUR_BAND, w)
			cols: [GEN_BLUR_BAND]f64
			for y in 0 ..= min(r, h - 1) do for x in x0 ..< x1 do cols[x - x0] += f64(j.rows[y * w + x])
			for y in 0 ..< h {
				ch := f64(min(y + r, h - 1) - max(y - r, 0) + 1)
				for x in x0 ..< x1 {
					cw := f64(min(x + r, w - 1) - max(x - r, 0) + 1)
					j.out.v[y * w + x] = f32(cols[x - x0] / (cw * ch))
				}
				if y + r + 1 < h do for x in x0 ..< x1 do cols[x - x0] += f64(j.rows[(y + r + 1) * w + x])
				if y - r >= 0 do for x in x0 ..< x1 do cols[x - x0] -= f64(j.rows[(y - r) * w + x])
			}
		}
	})
}

// gen_cellular: the cave automaton on bytes (1 = solid) with a cell of
// border all round (solid when edge cells count as solid), so a cell's
// eight neighbours are plain reads.
@(private = "file")
Gen_Cell_Job :: struct {
	cur, next:     []u8,
	w, pw:         int, // the grid's width, the padded one
	birth, survive: u8,
}

@(private = "file")
gen_cellular :: proc(src, out: Gen_Grid, iterations, birth, survive: int, edge: bool) {
	w, h := src.w, src.h
	pw := w + 2
	a := make([]u8, pw * (h + 2), context.temp_allocator)
	b := make([]u8, len(a), context.temp_allocator)
	slice.fill(a, 1 if edge else 0)
	for y in 0 ..< h do for x in 0 ..< w do a[(y + 1) * pw + x + 1] = 1 if src.v[y * w + x] >= 0.5 else 0
	copy(b, a)
	job := Gen_Cell_Job{a, b, w, pw, u8(clamp(birth, 0, 9)), u8(clamp(survive, 0, 9))}
	for _ in 0 ..< iterations {
		gen_parallel(h, w * 10, &job, proc(data: rawptr, y0, y1: int) {
			j := cast(^Gen_Cell_Job)data
			pw := j.pw
			c, nx := j.cur, j.next
			#no_bounds_check for y in y0 ..< y1 {
				row := (y + 1) * pw + 1
				for i in row ..< row + j.w {
					count := c[i - pw - 1] + c[i - pw] + c[i - pw + 1] + c[i - 1] + c[i + 1] + c[i + pw - 1] + c[i + pw] + c[i + pw + 1]
					nx[i] = 1 if (c[i] != 0 && count >= j.survive) || (c[i] == 0 && count >= j.birth) else 0
				}
			}
		})
		job.cur, job.next = job.next, job.cur
	}
	for y in 0 ..< h do for x in 0 ..< w do out.v[y * w + x] = f32(job.cur[(y + 1) * pw + x + 1])
}

// gen_morph: dilate (the largest of a cell and its four neighbours) or
// erode (the smallest), iterated.
@(private = "file")
Gen_Morph_Job :: struct {
	cur, next: []f32,
	w, h:      int,
	grow:      bool,
}

@(private = "file")
gen_morph :: proc(src, out: Gen_Grid, iterations: int, grow: bool) {
	if iterations == 0 {
		copy(out.v, src.v)
		return
	}
	job := Gen_Morph_Job{make([]f32, len(src.v), context.temp_allocator), make([]f32, len(src.v), context.temp_allocator), src.w, src.h, grow}
	copy(job.cur, src.v)
	for _ in 0 ..< iterations {
		gen_parallel(src.h, src.w * 5, &job, proc(data: rawptr, y0, y1: int) {
			j := cast(^Gen_Morph_Job)data
			w, h := j.w, j.h
			#no_bounds_check for y in y0 ..< y1 {
				row := j.cur[y * w:(y + 1) * w]
				above := j.cur[(y - 1) * w:y * w] if y > 0 else row
				below := j.cur[(y + 1) * w:(y + 2) * w] if y < h - 1 else row
				dst := j.next[y * w:(y + 1) * w]
				for x in 0 ..< w {
					l := row[x - 1] if x > 0 else row[x]
					r := row[x + 1] if x < w - 1 else row[x]
					if j.grow do dst[x] = max(row[x], l, r, above[x], below[x])
					else do dst[x] = min(row[x], l, r, above[x], below[x])
				}
			}
		})
		job.cur, job.next = job.next, job.cur
	}
	copy(out.v, job.cur)
}

@(private = "file")
gen_combine :: proc(a, b, out: []f32, op: int) {
	switch op {
	case 1: for i in 0 ..< len(out) do out[i] = a[i] - b[i]
	case 2: for i in 0 ..< len(out) do out[i] = a[i] * b[i]
	case 3: for i in 0 ..< len(out) do out[i] = min(a[i], b[i])
	case 4: for i in 0 ..< len(out) do out[i] = max(a[i], b[i])
	case 5: for i in 0 ..< len(out) do out[i] = a[i] if b[i] >= 0.5 else 0
	case 6: for i in 0 ..< len(out) do out[i] = (a[i] + b[i]) * 0.5
	case: for i in 0 ..< len(out) do out[i] = a[i] + b[i]
	}
}

// gen_scatter: random points at least `spacing` cells apart, in row order -
// a point is kept unless one already kept lies within spacing - 1 cells
// (left, right or above). The row of the last point in each column is kept,
// so the check is a scan along one row of columns.
@(private = "file")
gen_scatter :: proc(src, out: Gen_Grid, masked: bool, chance: f32, spacing: int, seed: u64) #no_bounds_check {
	w, h := src.w, src.h
	last := make([]int, w, context.temp_allocator)
	slice.fill(last, min(int) / 2)
	#no_bounds_check for y in 0 ..< h do for x in 0 ..< w {
		if masked && src.v[y * w + x] < 0.5 do continue
		if gen_hash01(x, y, seed) >= chance do continue
		near := false
		for xx in max(x - spacing + 1, 0) ..< min(x + spacing, w) do if last[xx] > y - spacing {
			near = true
			break
		}
		if near do continue
		out.v[y * w + x] = 1
		last[x] = y
	}
}

// --- shapes (#171) ---------------------------------------------------------------------
// Each shape takes its numbers from the node's own sequence (gen_rand_int),
// one shape after another: the same seed, the same shapes. Shapes are placed
// to fit inside the level (a shape bigger than it is clipped).

// gen_range: a size in lo..hi (the two in any order), at least 1.
@(private = "file")
gen_range :: proc(rng: ^u64, lo, hi: int) -> int {
	a, b := max(min(lo, hi), 1), max(max(lo, hi), 1)
	return gen_rand_int(rng, a, b)
}

// gen_fill_rect: 1 on the cells of x..x+w-1, y..y+h-1 inside the grid.
@(private = "file")
gen_fill_rect :: proc(out: Gen_Grid, x, y, w, h: int) #no_bounds_check {
	x0, x1 := clamp(x, 0, out.w), clamp(x + w, 0, out.w)
	for yy in clamp(y, 0, out.h) ..< clamp(y + h, 0, out.h) do slice.fill(out.v[yy * out.w + x0:yy * out.w + max(x1, x0)], 1)
}

@(private = "file")
gen_lines :: proc(out: Gen_Grid, count, minLen, maxLen, thickness, dir: int, seed: u64) {
	rng := seed
	w, h := out.w, out.h
	for _ in 0 ..< count {
		length := gen_range(&rng, minLen, maxLen)
		d := dir
		if d == 2 do d = gen_rand_int(&rng, 0, 1) // both: each line one or the other
		switch d {
		case 0: // horizontal
			l := min(length, w)
			x := gen_rand_int(&rng, 0, w - l)
			y := gen_rand_int(&rng, 0, max(h - thickness, 0))
			gen_fill_rect(out, x, y, l, thickness)
		case 1: // vertical
			l := min(length, h)
			x := gen_rand_int(&rng, 0, max(w - thickness, 0))
			y := gen_rand_int(&rng, 0, h - l)
			gen_fill_rect(out, x, y, thickness, l)
		case: // any angle: its middle where the whole line fits (when it can)
			angle := f32(gen_rand_int(&rng, 0, 3599)) * math.PI / 1800
			dx, dy := math.cos(angle), math.sin(angle)
			half := f32(length - 1) * 0.5
			ex, ey := abs(dx) * half + f32(thickness) * 0.5, abs(dy) * half + f32(thickness) * 0.5
			cx := f32(gen_rand_int(&rng, int(math.ceil(ex)), max(w - 1 - int(math.ceil(ex)), int(math.ceil(ex)))))
			cy := f32(gen_rand_int(&rng, int(math.ceil(ey)), max(h - 1 - int(math.ceil(ey)), int(math.ceil(ey)))))
			// A square brush stamped every half cell along it.
			steps := max(int(math.ceil(half * 4)), 1)
			for i in 0 ..= steps {
				t := -half + f32(i) * (2 * half) / f32(steps)
				px, py := int(math.round(cx + dx * t)), int(math.round(cy + dy * t))
				gen_fill_rect(out, px - (thickness - 1) / 2, py - (thickness - 1) / 2, thickness, thickness)
			}
		}
	}
}

@(private = "file")
gen_rectangles :: proc(out: Gen_Grid, count, minSize, maxSize, thickness: int, filled: bool, seed: u64) {
	rng := seed
	w, h := out.w, out.h
	for _ in 0 ..< count {
		rw, rh := min(gen_range(&rng, minSize, maxSize), w), min(gen_range(&rng, minSize, maxSize), h)
		x, y := gen_rand_int(&rng, 0, w - rw), gen_rand_int(&rng, 0, h - rh)
		t := min(thickness, rw, rh)
		if filled || 2 * t >= rw || 2 * t >= rh {
			gen_fill_rect(out, x, y, rw, rh)
			continue
		}
		gen_fill_rect(out, x, y, rw, t) // top
		gen_fill_rect(out, x, y + rh - t, rw, t) // bottom
		gen_fill_rect(out, x, y + t, t, rh - 2 * t) // left
		gen_fill_rect(out, x + rw - t, y + t, t, rh - 2 * t) // right
	}
}

// gen_circles: a cell is in a circle of radius r when its centre is within
// r + 0.5 of the circle's (a cell-wide disc for r 0), in a ring when also
// further than r + 0.5 - thickness.
@(private = "file")
gen_circles :: proc(out: Gen_Grid, count, minR, maxR, thickness: int, filled: bool, seed: u64) #no_bounds_check {
	rng := seed
	w, h := out.w, out.h
	for _ in 0 ..< count {
		r := gen_range(&rng, minR + 1, maxR + 1) - 1 // (0 allowed)
		cx := gen_rand_int(&rng, min(r, w - 1), max(w - 1 - r, min(r, w - 1)))
		cy := gen_rand_int(&rng, min(r, h - 1), max(h - 1 - r, min(r, h - 1)))
		outer := f32(r) + 0.5
		inner := outer - f32(thickness)
		for y in max(cy - r, 0) ..= min(cy + r, h - 1) do for x in max(cx - r, 0) ..= min(cx + r, w - 1) {
			dx, dy := f32(x - cx), f32(y - cy)
			d2 := dx * dx + dy * dy
			if d2 > outer * outer do continue
			if !filled && inner > 0 && d2 <= inner * inner do continue
			out.v[y * w + x] = 1
		}
	}
}

@(private = "file")
gen_surface :: proc(src, out: Gen_Grid, side: int) {
	w, h := src.w, src.h
	solid :: #force_inline proc(g: Gen_Grid, x, y: int) -> bool #no_bounds_check {return x >= 0 && y >= 0 && x < g.w && y < g.h && g.v[y * g.w + x] >= 0.5}
	#no_bounds_check for y in 0 ..< h do for x in 0 ..< w {
		if src.v[y * w + x] >= 0.5 do continue
		on: bool
		switch side {
		case 1: on = solid(src, x, y - 1)
		case 2: on = solid(src, x + 1, y) || solid(src, x - 1, y) || solid(src, x, y + 1) || solid(src, x, y - 1)
		case: on = solid(src, x, y + 1)
		}
		out.v[y * w + x] = 1 if on else 0
	}
}

// --- worker threads -----------------------------------------------------------------------
//
// gen_parallel runs fn over items 0..<count (rows, bands) in chunks, on a
// few worker threads made once and on this thread, and returns when all are
// done. Each item writes only its own cells, so the result is the same as
// in one thread. Small jobs (count * cost per item under GEN_PARALLEL_MIN),
// the web build, and a second evaluation while one uses the workers (the
// editor's previews and a game's background generation) run here, in order.

GEN_PARALLEL_MIN :: #config(GEN_PARALLEL_MIN, 48_000)
GEN_MAX_WORKERS :: 7

Gen_Parallel_Proc :: #type proc(data: rawptr, lo, hi: int)

@(private = "file")
gen_pool: struct {
	once:      sync.Once,
	busy:      sync.Mutex, // one job at a time
	workers:   [GEN_MAX_WORKERS]^thread.Thread,
	count:     int,
	wake:      sync.Sema,
	finished:  sync.Sema,
	// The job.
	fn:        Gen_Parallel_Proc,
	data:      rawptr,
	items:     int,
	chunk:     int,
	next:      int, // (atomic) the next item to take
}

// Gen_ParallelWorkers: how many worker threads split the heavy nodes (0:
// they run on the calling thread only).
Gen_ParallelWorkers :: proc() -> int {
	when ODIN_OS == .JS {
		return 0
	} else {
		sync.once_do(&gen_pool.once, gen_pool_start)
		return gen_pool.count
	}
}

@(private = "file")
gen_pool_start :: proc() {
	when ODIN_OS != .JS {
		context.allocator = runtime.heap_allocator() // (the threads live as long as the program)
		n := clamp(Engine_CoreCount() - 1, 0, GEN_MAX_WORKERS)
		for i in 0 ..< n {
			t := thread.create(gen_pool_worker)
			if t == nil do break
			t.init_context = context
			thread.start(t)
			gen_pool.workers[i] = t
			gen_pool.count += 1
		}
	}
}

@(private = "file")
gen_pool_worker :: proc(t: ^thread.Thread) {
	for {
		sync.sema_wait(&gen_pool.wake)
		gen_pool_take()
		sync.sema_post(&gen_pool.finished)
	}
}

@(private = "file")
gen_pool_take :: proc() {
	for {
		lo := sync.atomic_add(&gen_pool.next, gen_pool.chunk)
		if lo >= gen_pool.items do return
		gen_pool.fn(gen_pool.data, lo, min(lo + gen_pool.chunk, gen_pool.items))
	}
}

@(private)
gen_parallel :: proc(count, costPerItem: int, data: rawptr, fn: Gen_Parallel_Proc) {
	if count <= 0 do return
	workers := Gen_ParallelWorkers() if count * max(costPerItem, 1) >= GEN_PARALLEL_MIN && count > 1 else 0
	if workers == 0 || !sync.mutex_try_lock(&gen_pool.busy) {
		fn(data, 0, count)
		return
	}
	defer sync.mutex_unlock(&gen_pool.busy)
	use := min(workers, count - 1)
	gen_pool.fn, gen_pool.data, gen_pool.items = fn, data, count
	gen_pool.chunk = max(count / ((use + 1) * 4), 1)
	sync.atomic_store(&gen_pool.next, 0)
	for _ in 0 ..< use do sync.sema_post(&gen_pool.wake)
	gen_pool_take()
	for _ in 0 ..< use do sync.sema_wait(&gen_pool.finished)
}
