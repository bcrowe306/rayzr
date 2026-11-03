package engine

// ============================================================================
// Chunked level generation (#171, stretch): an endless level made a chunk
// at a time around the camera (LevelGeneratorNode's Chunked mode).
//
// A chunk is `chunkSize` x `chunkSize` cells of the level, chunk (cx, cy)
// starting at cell (cx, cy) * chunkSize - negative too. It is generated as a
// window of the endless level: the chunk plus an apron of extra cells on
// each side, evaluated with every position-reading node at absolute cells
// (noise, random fill, gradients, rectangles, tile picks...), then only the
// middle kept. The apron is what the graph's neighbourhood nodes need to
// see past the chunk's edge - blur's radius, cellular's iterations, dilate
// and erode's, surface and tile output's 1 - summed along each path to an
// output (Gen_ChunkInfo). So a chunk-safe graph gives every cell the value
// it has in one big level: no seams.
//
// Chunk-safe: constant, noise (all types), random fill, gradient (across
// the generator's size, clamped beyond it), rectangle (absolute cells),
// threshold, invert, remap, combine, blur, cellular, dilate, erode, scatter
// (in a chunk it keeps the candidates no closer one comes before - local,
// the same spacing), surface, tile output, entity output (`max`: per chunk).
//
// Not chunk-safe - they look at the whole level, or its edges: border, rooms
// & corridors, walker, random lines / rectangles / circles, Wave Function
// Collapse, Poisson scatter, flood fill, regions, connect regions, path,
// check, Lua Script and registered (Odin) nodes. They still run, on each
// chunk's window with the chunk's own seed (Gen_ChunkSeed: each chunk
// different, always the same for that chunk) - the seams show. The editor
// warns about them; the runtime doesn't refuse.
// ============================================================================

// Gen_KindChunkSafe: a node of this kind gives a cell the same value in a
// chunk as in the whole level (given its inputs do, and the apron).
Gen_KindChunkSafe :: proc(kind: Gen_Kind) -> bool {
	switch kind {
	case .Constant, .Noise, .Random_Fill, .Gradient, .Rect, .Threshold, .Invert, .Remap, .Blur, .Cellular, .Dilate, .Erode, .Combine, .Scatter, .Surface, .Tile_Output, .Entity_Output:
		return true
	case .Border, .Rooms, .Walker, .Lines, .Rectangles, .Circles, .WFC, .Poisson_Scatter, .Flood_Fill, .Regions, .Connect_Regions, .Path, .Check, .Script, .Custom:
		return false
	}
	return false
}

// Gen_NodeChunkReach: how many cells past a cell a node reads its input
// (its kernel's radius): the apron it adds.
Gen_NodeChunkReach :: proc(n: ^Gen_Node) -> int {
	#partial switch n.kind {
	case .Blur: return clamp(int(Gen_Param(n, "radius")), 0, 32)
	case .Cellular: return clamp(int(Gen_Param(n, "iterations")), 0, 64)
	case .Dilate, .Erode: return clamp(int(Gen_Param(n, "iterations")), 0, 64)
	case .Scatter: return max(clamp(int(Gen_Param(n, "spacing")), 0, 256) - 1, 0)
	case .Surface, .Tile_Output: return 1 // (the 3 x 3 around: terrains, pattern rules)
	}
	return 0
}

// What chunked generation needs to know about a graph.
Gen_Chunk_Info :: struct {
	apron:  int,   // extra cells generated around a chunk (then dropped)
	unsafe: []int, // the ids of the nodes a generation reads that aren't chunk-safe
}

// Gen_ChunkInfo: a graph's apron - the longest sum of reaches along a path
// from an output back to a generator - and the nodes it reads that aren't
// chunk-safe (in graph order; unconnected nodes don't count).
Gen_ChunkInfo :: proc(g: ^Gen_Graph, allocator := context.allocator) -> Gen_Chunk_Info {
	State :: struct {
		g:      ^Gen_Graph,
		reach:  map[int]int, // a node's apron (-1: being visited: a cycle)
	}
	st := State{g = g, reach = make(map[int]int, allocator = context.temp_allocator)}
	visit :: proc(st: ^State, id: int) -> int {
		if id == 0 do return 0
		if r, ok := st.reach[id]; ok do return max(r, 0)
		n := Gen_FindNode(st.g, id)
		if n == nil do return 0
		st.reach[id] = -1
		inner := 0
		for src in n.inputs do inner = max(inner, visit(st, src))
		r := Gen_NodeChunkReach(n) + inner
		st.reach[id] = r
		return r
	}
	info: Gen_Chunk_Info
	main := Gen_OutputNode(g)
	if main != nil do info.apron = visit(&st, main.id)
	for &n in g.nodes {
		if (n.kind == .Tile_Output && (n.layer != "" || Gen_WritesComponents(&n))) || (n.kind == .Entity_Output && n.component != "") {
			info.apron = max(info.apron, visit(&st, n.id))
		}
	}
	unsafe := make([dynamic]int, allocator)
	for &n in g.nodes do if n.id in st.reach && !Gen_KindChunkSafe(n.kind) do append(&unsafe, n.id)
	info.unsafe = unsafe[:]
	return info
}

// Gen_ChunkSeed: chunk c's own seed for a level seed (never 0) - what the
// nodes that aren't chunk-safe use, so each chunk differs but always comes
// out the same.
Gen_ChunkSeed :: proc(seed: u64, c: [2]int) -> u64 {
	return gen_mix(gen_mix(seed ~ 0xc4a7c5, u64(i64(c.x))), u64(i64(c.y))) | 1
}

// Gen_GenerateWindow: the level's cells origin .. origin + size - a chunk,
// or any area - generated as a window with `apron` cells around it (use
// Gen_ChunkInfo's) and then cut to the area. Tiles, layers, components and
// entities as Gen_Generate's, cells relative to the area (r.origin is
// `origin`). chunkSeed: the seed the nodes that aren't chunk-safe use (0:
// the level's - an area, not a chunk).
Gen_GenerateWindow :: proc(g: ^Gen_Graph, seed: u64, origin, size: [2]int, apron: int, chunkSeed: u64 = 0, allocator := context.allocator, progress: ^Gen_Progress = nil) -> (r: Gen_Result, err: string) {
	ev := gen_eval_begin(g, seed)
	ev.progress = progress
	defer gen_eval_end(&ev)
	a := max(apron, 0)
	ev.origin = origin - a
	ev.size = {max(size.x, 1) + 2 * a, max(size.y, 1) + 2 * a}
	ev.windowed = true
	ev.chunkSeed = chunkSeed
	return gen_generate(&ev, allocator, a)
}

// Gen_GenerateChunk: chunk c (chunkSize cells square) of the level for a
// seed (0: the graph's), with its own chunk seed. `apron`: Gen_ChunkInfo's.
Gen_GenerateChunk :: proc(g: ^Gen_Graph, seed: u64, c: [2]int, chunkSize, apron: int, allocator := context.allocator) -> (r: Gen_Result, err: string) {
	s := seed if seed != 0 else g.seed
	return Gen_GenerateWindow(g, s, c * chunkSize, {chunkSize, chunkSize}, apron, Gen_ChunkSeed(s, c), allocator)
}

// Gen_ChunkOf: the chunk holding a cell (floor division: negative cells
// are in negative chunks).
Gen_ChunkOf :: proc(cell: [2]int, chunkSize: int) -> [2]int {
	fd :: proc(a, b: int) -> int {
		q := a / b
		if a % b != 0 && (a < 0) != (b < 0) do q -= 1
		return q
	}
	cs := max(chunkSize, 1)
	return {fd(cell.x, cs), fd(cell.y, cs)}
}
