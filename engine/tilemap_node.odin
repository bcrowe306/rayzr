package engine

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// TileMapNode: a grid of tiles from one tileset image, painted in the
// editor (the bottom panel's Tile Map tab + viewport brush); components can
// be painted on the same grid too (tilemap_components.odin). Tile indices
// count left-to-right, top-to-bottom in the tileset; -1 is empty.
//
// With `solid` on, ready() builds static colliders for every painted tile
// (horizontal runs merged into single boxes), in a transient child body.
//
// Layout picks the grid (tilemap_grid.odin): square, isometric, staggered or
// hex cells, Cell Size apart from the tile size (tall tiles stand on their
// cell). With Y Sort on, the map's bands (rows) sort with Y-sorted sprites
// under the same Y-sorted parent - for walls and blocks things walk behind.
//
// Saved as reflected properties (solid, tint) plus "tilemap": {"tileset",
// "tile_size", "map_size", "data": [[count, tile], ...]} (run-length
// encoded, row-major over the map - or over "data_origin" / "data_size"
// when tiles were painted beyond it). Changing the map size never drops
// tiles: the storage covers the map and anything painted outside it.
// ============================================================================

TileMapNode :: struct {
	using node: Node,
	shininess: f32 `gui:"true" min:"0" max:"1"`, // lit: a glint from lights (#274; its image's _s.png too)
	tilesetPath: string,
	tileset:     ^Texture,
	tileSize:    [2]int, // pixels per tile (in the tileset and in the world)
	mapSize:     [2]int, // cells
	solid:       bool `gui:"true"`,                      // build colliders for painted tiles
	tint:        rl.Color `gui:"true"`,
	layout:      TileMap_Layout `gui:"true"`,             // the grid: square, isometric, staggered, hex
	stagger:     TileMap_Stagger `gui:"true"`,            // Staggered / hex: which rows (Hex Flat: columns) are shifted
	cellSize:    [2]f32 `gui:"true" min:"0" max:"1024"`,  // the grid's cell (0 = the tile size); taller tiles stand on it
	tileOffset:  [2]f32 `gui:"true" min:"-512" max:"512"`, // moves every tile image (art whose cell isn't at its bottom: a slab below a floor)
	// The tileset is an Aseprite file: the map is this tilemap layer of it
	// (its first frame), kept in sync when the file is saved (aseprite_tilemap).
	asepriteLayer: string `gui:"true"`,
	aseRes:        ^Ase_Resource,
	aseVersion:    int,
	// The painted cells: a dense grid of dataSize cells whose first cell is
	// dataOrigin (it may be negative). It always covers the map (0..mapSize)
	// and grows to take tiles painted outside it, so changing the map size
	// never loses tiles; mapSize is the map's outline / default area.
	tiles:       [dynamic]i32,
	dataOrigin:  [2]int,
	dataSize:    [2]int,
	staticBody:  ^StaticBodyNode,
	builtSize:   [2]int, // mapSize the storage was last made to cover
	// Chunk cache (tile_cache.odin): bumped when the tiles change; chunkVer
	// per chunk for single-cell edits.
	cacheVersion: u64,
	collidersDirty: bool, // tiles set while running (Lua): colliders rebuilt in the update (#220)
	chunkVer:     map[[2]i32]u64,
	// Components on the grid (tilemap_components.odin): their footprints in
	// cells, measured once per component and tile size.
	compFootprints: map[string][2]int,
	// Y Sort's bands this frame (Scene_CollectRenderables): [bandLo, bandHi),
	// drawn one per render call from bandNext.
	bandLo, bandHi, bandNext: int,
	bandMode: bool,
	// Animated tiles (tile_anims.odin): by the tile they start on.
	anims: map[i32]Tile_Anim,
}

TileMapNode_Create :: proc(scene: ^Scene, name: string = "TileMap", parent: ^Node = nil) -> ^TileMapNode {
	tm := CreateNode(scene.manager, TileMapNode)
	tm.name = strings.clone(name, tm.allocator) // owned: callers pass temp strings too
	tm.tileSize = {32, 32}
	tm.mapSize = {20, 12}
	tm.tint = rl.WHITE
	tm.tiles = make([dynamic]i32, tm.allocator)
	TileMapNode_Layout(tm)
	tm.ready = TileMapNode_Ready
	tm.update = TileMapNode_Update
	tm.render = TileMapNode_Render
	tm.onDestroy = TileMapNode_Destroy
	scene->addNode(tm, parent)
	return tm
}

// TileMapNode_Layout makes the storage cover the map (call after changing
// mapSize). Tiles are never dropped: outside the new map they're kept.
TileMapNode_Layout :: proc(tm: ^TileMapNode) {
	w, h := max(tm.mapSize.x, 1), max(tm.mapSize.y, 1)
	tm.mapSize = {w, h}
	if tm.builtSize == tm.mapSize && len(tm.tiles) == tm.dataSize.x * tm.dataSize.y && len(tm.tiles) > 0 do return
	if len(tm.tiles) == 0 || len(tm.tiles) != tm.dataSize.x * tm.dataSize.y {
		// (New / reset: just the map.)
		tilemap_restore(tm, {0, 0}, tm.mapSize)
	} else {
		TileMapNode_Compact(tm)
	}
	tm.builtSize = tm.mapSize
}

// TileMapNode_Compact trims the storage to the map plus whatever is painted
// outside it (empty margins go; saving does this).
TileMapNode_Compact :: proc(tm: ^TileMapNode) {
	lo, hi := [2]int{0, 0}, tm.mapSize
	if cmin, cmax, any := tilemap_content(tm); any {
		lo = {min(lo.x, cmin.x), min(lo.y, cmin.y)}
		hi = {max(hi.x, cmax.x), max(hi.y, cmax.y)}
	}
	tilemap_restore(tm, lo, hi - lo)
}

// TileMapNode_Reset empties the map: storage = the map, every cell empty.
TileMapNode_Reset :: proc(tm: ^TileMapNode) {
	clear(&tm.tiles)
	tm.dataOrigin, tm.dataSize = {}, {}
	tm.builtSize = {}
	TileMapNode_Layout(tm)
}

// TileMapNode_SetDataArea lays the storage out over an area (loading a
// map with tiles beyond it); the map stays covered.
TileMapNode_SetDataArea :: proc(tm: ^TileMapNode, origin, size: [2]int) {
	TileMapNode_Layout(tm)
	lo := [2]int{min(origin.x, 0), min(origin.y, 0)}
	hi := [2]int{max(origin.x + size.x, tm.mapSize.x), max(origin.y + size.y, tm.mapSize.y)}
	tilemap_restore(tm, lo, hi - lo)
}

// tilemap_content: the painted cells' bounds (max exclusive).
@(private = "file")
tilemap_content :: proc(tm: ^TileMapNode) -> (lo, hi: [2]int, any: bool) {
	w := tm.dataSize.x
	for t, i in tm.tiles {
		if t < 0 do continue
		c := tm.dataOrigin + {i % w, i / w}
		if !any {lo, hi, any = c, c + 1, true; continue}
		lo = {min(lo.x, c.x), min(lo.y, c.y)}
		hi = {max(hi.x, c.x + 1), max(hi.y, c.y + 1)}
	}
	return
}

// tilemap_restore re-lays the storage out as size cells from origin,
// keeping every tile inside it.
@(private = "file")
tilemap_restore :: proc(tm: ^TileMapNode, origin, size: [2]int) {
	size := [2]int{max(size.x, 1), max(size.y, 1)}
	if origin == tm.dataOrigin && size == tm.dataSize && len(tm.tiles) == size.x * size.y do return
	old := make([]i32, len(tm.tiles), context.temp_allocator)
	copy(old, tm.tiles[:])
	oo, os_ := tm.dataOrigin, tm.dataSize
	if tm.tiles.allocator.procedure == nil do tm.tiles = make([dynamic]i32, tm.allocator)
	resize(&tm.tiles, size.x * size.y)
	for &t in tm.tiles do t = -1
	if len(old) == os_.x * os_.y {
		for y in 0 ..< os_.y do for x in 0 ..< os_.x {
			c := oo + {x, y} - origin
			if c.x >= 0 && c.y >= 0 && c.x < size.x && c.y < size.y do tm.tiles[c.y * size.x + c.x] = old[y * os_.x + x]
		}
	}
	tm.dataOrigin, tm.dataSize = origin, size
	tm.cacheVersion += 1
}

// tilemap_index: a cell's slot in the storage (false: outside it).
tilemap_index :: #force_inline proc(tm: ^TileMapNode, x, y: int) -> (int, bool) {
	lx, ly := x - tm.dataOrigin.x, y - tm.dataOrigin.y
	if lx < 0 || ly < 0 || lx >= tm.dataSize.x || ly >= tm.dataSize.y do return 0, false
	return ly * tm.dataSize.x + lx, true
}

// TileMapNode_Extent: the cells that can hold tiles now - the map and
// anything painted beyond it (min, max exclusive).
TileMapNode_Extent :: proc(tm: ^TileMapNode) -> (lo, hi: [2]int) {
	TileMapNode_Layout(tm)
	return tm.dataOrigin, tm.dataOrigin + tm.dataSize
}

TileMapNode_Get :: proc(tm: ^TileMapNode, x, y: int) -> i32 {
	TileMapNode_Layout(tm)
	i, ok := tilemap_index(tm, x, y)
	return tm.tiles[i] if ok else -1
}

// TileMapNode_Set paints one cell (-1 erases), inside or outside the map
// (the storage grows to take it). Returns true if it changed.
TileMapNode_Set :: proc(tm: ^TileMapNode, x, y: int, tile: i32) -> bool {
	TileMapNode_Layout(tm)
	i, ok := tilemap_index(tm, x, y)
	if !ok {
		if tile < 0 do return false
		// Grow by a margin (a stroke outward doesn't re-lay out every cell).
		m := 8
		lo := [2]int{min(tm.dataOrigin.x, x - (m if x < tm.dataOrigin.x else 0)), min(tm.dataOrigin.y, y - (m if y < tm.dataOrigin.y else 0))}
		hi0 := tm.dataOrigin + tm.dataSize
		hi := [2]int{max(hi0.x, x + 1 + (m if x >= hi0.x else 0)), max(hi0.y, y + 1 + (m if y >= hi0.y else 0))}
		tilemap_restore(tm, lo, hi - lo)
		i, _ = tilemap_index(tm, x, y)
	}
	if tm.tiles[i] == tile do return false
	tm.tiles[i] = tile
	cs := tilemap_chunk_cells(tm)
	c := [2]i32{i32(floor_div(x, cs.x)), i32(floor_div(y, cs.y))}
	if tm.chunkVer == nil do tm.chunkVer = make(map[[2]i32]u64, tm.allocator)
	tm.chunkVer[c] = tm.chunkVer[c] + 1
	return true
}

@(private = "file")
floor_div :: #force_inline proc(a, b: int) -> int {
	q := a / b
	if (a % b != 0) && ((a < 0) != (b < 0)) do q -= 1
	return q
}

// TileMapNode_Changed: call after writing tm.tiles directly.
TileMapNode_Changed :: proc(tm: ^TileMapNode) {
	tm.cacheVersion += 1
}

// TileMapNode_Fill flood-fills the region of equal tiles around (x, y).
// Started inside the map it stays in the map; outside, it's bounded by
// what's painted beyond the map (empty space outside is endless).
TileMapNode_Fill :: proc(tm: ^TileMapNode, x, y: int, tile: i32) -> int {
	lo, hi := TileMapNode_Extent(tm)
	if x >= 0 && y >= 0 && x < tm.mapSize.x && y < tm.mapSize.y do lo, hi = {0, 0}, tm.mapSize
	target := TileMapNode_Get(tm, x, y)
	if x < lo.x || y < lo.y || x >= hi.x || y >= hi.y || target == tile do return 0
	stack := make([dynamic][2]int, context.temp_allocator)
	append(&stack, [2]int{x, y})
	n := 0
	for len(stack) > 0 {
		p := pop(&stack)
		if TileMapNode_Get(tm, p.x, p.y) != target do continue
		TileMapNode_Set(tm, p.x, p.y, tile)
		n += 1
		nb, k := TileMapNode_Neighbors(tm, p) // (hex: six; staggered: the diagonal rows)
		for q in nb[:k] do if q.x >= lo.x && q.y >= lo.y && q.x < hi.x && q.y < hi.y do append(&stack, q)
	}
	return n
}

// TileMapNode_Columns: tiles per row in the tileset image.
TileMapNode_Columns :: proc(tm: ^TileMapNode) -> int {
	if tm.tileset == nil || tm.tileSize.x <= 0 do return 0
	return max(int(Texture_Size(tm.tileset).x) / tm.tileSize.x, 1)
}

TileMapNode_TileCount :: proc(tm: ^TileMapNode) -> int {
	if tm.tileset == nil || tm.tileSize.y <= 0 do return 0
	return TileMapNode_Columns(tm) * max(int(Texture_Size(tm.tileset).y) / tm.tileSize.y, 1)
}

// TileMapNode_SetTileset loads the tileset image (project-relative path;
// an Aseprite file with Aseprite Layer set: that tilemap layer, see
// TileMapNode_SyncAseprite).
TileMapNode_SetTileset :: proc(tm: ^TileMapNode, path: string, ctx: ^GameContext) {
	rm := Node_ResourceManager(tm)
	if tm.tileset != nil && rm != nil do ResourceManager_ReleaseTexture(rm, tm.tileset)
	tm.tileset = nil
	tm.cacheVersion += 1
	tm.tilesetPath = strings.clone(path, tm.allocator)
	if path == "" || rm == nil || !rl.IsWindowReady() do return
	if tex, ok := rm.loadTexture(rm, Project_ResolveAssetPath(ctx, path)); ok do tm.tileset = tex
	// Its animated tiles, from the tileset's sidecar.
	gc := ctx if ctx != nil else tm.gameContext
	if gc != nil && gc.game != nil {
		ts, _ := Terrains_Load(gc, path, context.temp_allocator)
		TileMapNode_SetAnimations(tm, ts.animations[:])
	}
}

// TileMapNode_CellAt: the cell under a world position (may be outside the map).
TileMapNode_CellAt :: proc(tm: ^TileMapNode, world: [2]f32) -> [2]int {
	return TileMapNode_LocalCellAt(tm, TileMapNode_WorldToLocal(tm, world))
}

// TileMapNode_CellCorner: world position of a cell's box's top-left corner
// (square cells: the cell's corner; cell + 1's is the opposite one).
TileMapNode_CellCorner :: proc(tm: ^TileMapNode, cell: [2]int) -> [2]f32 {
	if tm.layout == .Square {
		c := TileMapNode_CellSize(tm)
		return TileMapNode_LocalToWorld(tm, {f32(cell.x) * c.x, f32(cell.y) * c.y})
	}
	b := TileMapNode_CellBox(tm, cell)
	return TileMapNode_LocalToWorld(tm, {b.x, b.y})
}

// tilemap_visible_cells: the cell range in a view (unrotated maps; rotated
// ones: all).
@(private = "file")
tilemap_visible_cells :: proc(tm: ^TileMapNode, view: rl.Rectangle, hasView: bool) -> (x0, y0, x1, y1: int) {
	lo, hi := tm.dataOrigin, tm.dataOrigin + tm.dataSize // (the map and tiles beyond it)
	x0, y0, x1, y1 = lo.x, lo.y, hi.x, hi.y
	tw, th := f32(tm.tileSize.x), f32(tm.tileSize.y)
	sx := tm.globalScale.x if tm.globalScale.x != 0 else 1
	sy := tm.globalScale.y if tm.globalScale.y != 0 else 1
	if hasView && tm.globalRotation == 0 && sx > 0 && sy > 0 {
		o := TileMapNode_CellCorner(tm, {0, 0})
		x0 = clamp(int(math.floor((view.x - o.x) / (tw * sx))), lo.x, hi.x)
		y0 = clamp(int(math.floor((view.y - o.y) / (th * sy))), lo.y, hi.y)
		x1 = clamp(int(math.ceil((view.x + view.width - o.x) / (tw * sx))), lo.x, hi.x)
		y1 = clamp(int(math.ceil((view.y + view.height - o.y) / (th * sy))), lo.y, hi.y)
	}
	return
}

// tilemap_chunk_cells: cells per cache chunk (up to TILE_CHUNK_PX pixels).
@(private = "file")
tilemap_chunk_cells :: proc(tm: ^TileMapNode) -> [2]int {
	return {max(TILE_CHUNK_PX / max(tm.tileSize.x, 1), 1), max(TILE_CHUNK_PX / max(tm.tileSize.y, 1), 1)}
}

@(private = "file")
tilemap_chunk_version :: proc(tm: ^TileMapNode, c: [2]i32) -> u64 {
	v := tm.cacheVersion * 1_000_003 + u64(tm.tileset.texture.id) * 7919 + u64(tm.tileSize.x) * 131 + u64(tm.tileSize.y)
	return v + tm.chunkVer[c] * 0x9E3779B97F4A7C15
}

// tilemap_tile_now: the tile a cell shows now (an animated tile's frame).
@(private = "file")
tilemap_tile_now :: #force_inline proc(tm: ^TileMapNode, t: i32, x, y: int, now: f64) -> i32 {
	if len(tm.anims) == 0 do return t
	if a, ok := &tm.anims[t]; ok do return Tile_AnimFrame(a, now, {x, y})
	return t
}

// draw_cells draws cells' tiles; `local`: into a cache chunk (animated
// tiles left out: drawn every frame); `onlyAnimated`: just those.
@(private = "file")
draw_cells :: proc(tm: ^TileMapNode, cols, x0, y0, x1, y1: int, local: bool, origin: [2]int = {}, onlyAnimated := false) {
	tw, th := f32(tm.tileSize.x), f32(tm.tileSize.y)
	sx := tm.globalScale.x if tm.globalScale.x != 0 else 1
	sy := tm.globalScale.y if tm.globalScale.y != 0 else 1
	now := Tile_AnimClock(tm.gameContext)
	animated := len(tm.anims) > 0
	for y in y0 ..< y1 {
		for x in x0 ..< x1 {
			i, ok := tilemap_index(tm, x, y)
			if !ok do continue
			t := tm.tiles[i]
			if t < 0 do continue
			if animated {
				isAnim := t in tm.anims
				if (local && isAnim) || (onlyAnimated && !isAnim) do continue
				t = tilemap_tile_now(tm, t, x, y, now)
			} else if onlyAnimated {
				return
			}
			src := Texture_Src(tm.tileset, {f32(int(t) % cols) * tw, f32(int(t) / cols) * th, tw, th})
			if local {
				// Into a chunk: unscaled pixels from the chunk's corner.
				Lit_Draw(tm.tileset.texture, src, {f32(x - origin.x) * tw, f32(y - origin.y) * th, tw, th}, {0, 0}, 0, rl.WHITE)
			} else {
				p := TileMapNode_CellCorner(tm, {x, y})
				Lit_Draw(tm.tileset.texture, src, {p.x, p.y, tw * sx, th * sy}, {0, 0}, tm.globalRotation, tm.tint)
			}
		}
	}
}

// TileMapNode_PrepareChunks builds the cached chunks in view.
TileMapNode_PrepareChunks :: proc(tm: ^TileMapNode, view: rl.Rectangle) {
	if tm.tileset == nil || tm.tileset.texture.id == 0 || !TileMapNode_IsPlainGrid(tm) || tm.ySort do return
	TileMapNode_Layout(tm)
	if TileMapNode_Columns(tm) <= 0 do return
	x0, y0, x1, y1 := tilemap_visible_cells(tm, view, true)
	if (x1 - x0) * (y1 - y0) < TILE_CACHE_MIN_TILES do return
	cs := tilemap_chunk_cells(tm)
	size := [2]i32{i32(cs.x * tm.tileSize.x), i32(cs.y * tm.tileSize.y)}
	build :: proc(data: rawptr, key: Tile_Chunk_Key) {
		tm := cast(^TileMapNode)data
		cs := tilemap_chunk_cells(tm)
		o := [2]int{int(key.cx) * cs.x, int(key.cy) * cs.y}
		draw_cells(tm, TileMapNode_Columns(tm), o.x, o.y, o.x + cs.x, o.y + cs.y, true, o)
	}
	if x1 <= x0 || y1 <= y0 do return
	for cy in floor_div(y0, cs.y) ..= floor_div(y1 - 1, cs.y) {
		for cx in floor_div(x0, cs.x) ..= floor_div(x1 - 1, cs.x) {
			c := [2]i32{i32(cx), i32(cy)}
			TileCache_Ensure({tm, tm, 0, c.x, c.y}, tilemap_chunk_version(tm, c), size, build, tm)
		}
	}
}

// tilemap_view_cells: the stored cells in view (with tall tiles' room).
@(private = "file")
tilemap_view_cells :: proc(tm: ^TileMapNode) -> (lo, hi: [2]int) {
	lo, hi = tm.dataOrigin, tm.dataOrigin + tm.dataSize
	if !renderView.active do return
	v := renderView.rect
	corners := [4][2]f32{{v.x, v.y}, {v.x + v.width, v.y}, {v.x, v.y + v.height}, {v.x + v.width, v.y + v.height}}
	mn, mx: [2]f32
	for p, i in corners {
		q := TileMapNode_WorldToLocal(tm, p)
		if i == 0 do mn, mx = q, q
		mn = {min(mn.x, q.x), min(mn.y, q.y)}
		mx = {max(mx.x, q.x), max(mx.y, q.y)}
	}
	return TileMapNode_CellsInLocalRect(tm, {mn.x, mn.y, mx.x - mn.x, mx.y - mn.y}, lo, hi)
}

// draw_band: one band's tiles (any grid), standing on their cells.
@(private = "file")
draw_band :: proc(tm: ^TileMapNode, b: int, lo, hi: [2]int) {
	TileMapNode_BandCells(tm, b, lo, hi, nil, proc(tm: ^TileMapNode, cell: [2]int, _: rawptr) {
		i, ok := tilemap_index(tm, cell.x, cell.y)
		if !ok do return
		t := tm.tiles[i]
		if t < 0 do return
		t = tilemap_tile_now(tm, t, cell.x, cell.y, Tile_AnimClock(tm.gameContext))
		cols := TileMapNode_Columns(tm)
		tw, th := f32(tm.tileSize.x), f32(tm.tileSize.y)
		src := Texture_Src(tm.tileset, {f32(int(t) % cols) * tw, f32(int(t) / cols) * th, tw, th})
		r := TileMapNode_TileRect(tm, cell)
		p := TileMapNode_LocalToWorld(tm, {r.x, r.y})
		sx := tm.globalScale.x if tm.globalScale.x != 0 else 1
		sy := tm.globalScale.y if tm.globalScale.y != 0 else 1
		Lit_Draw(tm.tileset.texture, src, {p.x, p.y, tw * sx, th * sy}, {0, 0}, tm.globalRotation, tm.tint)
	})
}

// TileMapNode_Bands: the bands Y Sort draws one by one (the stored cells').
TileMapNode_Bands :: proc(tm: ^TileMapNode) -> (lo, hi: int) {
	TileMapNode_Layout(tm)
	return TileMapNode_BandRange(tm, tm.dataOrigin, tm.dataOrigin + tm.dataSize)
}

// TileMapNode_BandSortY: band b's Y-sort key (its feet line, in the world).
TileMapNode_BandSortY :: proc(tm: ^TileMapNode, b: int) -> f32 {
	return TileMapNode_LocalToWorld(tm, {0, TileMapNode_BandBottom(tm, b)}).y + tm.ySortOffset
}

TileMapNode_Render :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	tm := cast(^TileMapNode)node
	TileMapNode_SyncAseprite(tm)
	if !tm.renderable || tm.tileset == nil do return
	TileMapNode_Layout(tm)
	cols := TileMapNode_Columns(tm)
	if cols <= 0 do return
	if tm.bandMode {
		// Y Sort: one band per call, in the order they were collected.
		b := tm.bandLo + tm.bandNext
		tm.bandNext += 1
		if b >= tm.bandHi do return
		lo, hi := tilemap_view_cells(tm)
		draw_band(tm, b, lo, hi)
		return
	}
	if !TileMapNode_IsPlainGrid(tm) {
		lo, hi := tilemap_view_cells(tm)
		b0, b1 := TileMapNode_BandRange(tm, lo, hi)
		for b in b0 ..< b1 do draw_band(tm, b, lo, hi)
		return
	}
	x0, y0, x1, y1 := tilemap_visible_cells(tm, renderView.rect, renderView.active)
	if x1 <= x0 || y1 <= y0 do return
	if tm.material != nil || !TileCache_Enabled() || renderNormalPass || (x1 - x0) * (y1 - y0) < TILE_CACHE_MIN_TILES { // (the normal pass: tile by tile)
		draw_cells(tm, cols, x0, y0, x1, y1, false)
		return
	}
	// Cached chunks as single quads; the rest tile by tile.
	tw, th := f32(tm.tileSize.x), f32(tm.tileSize.y)
	sx := tm.globalScale.x if tm.globalScale.x != 0 else 1
	sy := tm.globalScale.y if tm.globalScale.y != 0 else 1
	cs := tilemap_chunk_cells(tm)
	missing := make([dynamic][2]int, context.temp_allocator)
	TileCache_BeginDraw()
	dataHi := tm.dataOrigin + tm.dataSize
	for cy in floor_div(y0, cs.y) ..= floor_div(y1 - 1, cs.y) {
		for cx in floor_div(x0, cs.x) ..= floor_div(x1 - 1, cs.x) {
			c := [2]i32{i32(cx), i32(cy)}
			o := [2]int{cx * cs.x, cy * cs.y}
			w, h := min(cs.x, dataHi.x - o.x), min(cs.y, dataHi.y - o.y)
			p := TileMapNode_CellCorner(tm, o)
			src := rl.Rectangle{0, 0, f32(w) * tw, f32(h) * th}
			dst := rl.Rectangle{p.x, p.y, f32(w) * tw * sx, f32(h) * th * sy}
			if !TileCache_Draw({tm, tm, 0, c.x, c.y}, tilemap_chunk_version(tm, c), src, dst, tm.globalRotation, tm.tint) do append(&missing, o)
		}
	}
	TileCache_EndDraw()
	// Chunks of a map don't overlap: the rest can follow.
	for o in missing {
		draw_cells(tm, cols, max(o.x, x0), max(o.y, y0), min(o.x + cs.x, x1), min(o.y + cs.y, y1), false)
	}
	// Animated tiles aren't in the chunks: their frame now (cells drawn in
	// full above already showed theirs).
	if len(tm.anims) > 0 {
		missed :: proc(missing: [][2]int, x, y: int, cs: [2]int) -> bool {
			for o in missing do if x >= o.x && y >= o.y && x < o.x + cs.x && y < o.y + cs.y do return true
			return false
		}
		if len(missing) == 0 {
			draw_cells(tm, cols, x0, y0, x1, y1, false, onlyAnimated = true)
		} else {
			for y in y0 ..< y1 do for x in x0 ..< x1 do if !missed(missing[:], x, y, cs) do draw_cells(tm, cols, x, y, x + 1, y + 1, false, onlyAnimated = true)
		}
	}
}

// TileMapNode_BuildColliders (re)creates the static colliders for painted
// tiles, merging horizontal runs.
TileMapNode_BuildColliders :: proc(tm: ^TileMapNode, ctx: ^GameContext) {
	scene := ctx.scene if ctx != nil else nil
	if scene == nil && tm.gameContext != nil do scene = tm.gameContext.scene
	if scene == nil do return
	if tm.staticBody != nil && Node_IsAlive(tm.staticBody) {
		RemoveNode(scene.manager, tm.staticBody)
		ProcessNodeQueues(scene.manager, ctx)
	}
	tm.staticBody = StaticBodyNode_Create(scene, fmt.tprintf("%s_Colliders", tm.name), tm)
	tm.staticBody.position = {0, 0}
	tm.staticBody.transient = true
	tm.staticBody.gameContext = ctx
	lo, hi := TileMapNode_Extent(tm) // (tiles beyond the map are solid too)
	cs := TileMapNode_CellSize(tm)
	tw, th := cs.x, cs.y
	switch tm.layout {
	case .Square:
	case .Isometric:
		// Runs along x are parallelograms: the first cell's top and left
		// corners, the last one's right and bottom.
		for y in lo.y ..< hi.y {
			x := lo.x
			for x < hi.x {
				if TileMapNode_Get(tm, x, y) < 0 {
					x += 1
					continue
				}
				start := x
				for x < hi.x && TileMapNode_Get(tm, x, y) >= 0 do x += 1
				a, _ := TileMapNode_CellOutline(tm, {start, y})
				b, _ := TileMapNode_CellOutline(tm, {x - 1, y})
				StaticBodyNode_AddShape(tm.staticBody, MakePolygonPhysicsShape({a[0], b[1], b[2], a[3]}), ctx)
			}
		}
		return
	case .Staggered, .HexPointy, .HexFlat:
		// A cell each (neighbours touch at corners / slanted sides).
		for y in lo.y ..< hi.y do for x in lo.x ..< hi.x {
			if TileMapNode_Get(tm, x, y) < 0 do continue
			pts, n := TileMapNode_CellOutline(tm, {x, y})
			StaticBodyNode_AddShape(tm.staticBody, MakePolygonPhysicsShape(pts[:n]), ctx)
		}
		return
	}
	for y in lo.y ..< hi.y {
		x := lo.x
		for x < hi.x {
			if TileMapNode_Get(tm, x, y) < 0 {
				x += 1
				continue
			}
			start := x
			for x < hi.x && TileMapNode_Get(tm, x, y) >= 0 do x += 1
			w := f32(x - start) * tw
			shape := MakeBoxPhysicsShape(w, th, {f32(start) * tw + w * 0.5, f32(y) * th + th * 0.5}, 0)
			StaticBodyNode_AddShape(tm.staticBody, shape, ctx)
		}
	}
}

TileMapNode_Ready :: proc(node: ^Node, ctx: ^GameContext) {
	tm := cast(^TileMapNode)node
	TileMapNode_SyncAseprite(tm)
	if tm.solid do TileMapNode_BuildColliders(tm, ctx)
}

// TileMapNode_Update: a solid map's colliders follow tiles set while running
// (once a frame, however many changed).
TileMapNode_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	tm := cast(^TileMapNode)node
	if !tm.collidersDirty do return
	tm.collidersDirty = false
	if tm.solid do TileMapNode_BuildColliders(tm, ctx)
}

TileMapNode_Destroy :: proc(node: ^Node, ctx: ^GameContext) {
	tm := cast(^TileMapNode)node
	TileCache_Evict(tm)
	Nav_Forget(tm)
	if tm.tileset != nil {
		if rm := Node_ResourceManager(tm); rm != nil do ResourceManager_ReleaseTexture(rm, tm.tileset)
		tm.tileset = nil
	}
	ResourceManager_ReleaseAseprite(tm.aseRes)
	tm.aseRes = nil
	tilemap_free_anims(tm)
	delete(tm.anims)
}

// TileMapNode_EncodeRLE writes the tiles as [[count, tile], ...].
TileMapNode_EncodeRLE :: proc(tm: ^TileMapNode, sb: ^strings.Builder) {
	TileMapNode_Layout(tm)
	strings.write_byte(sb, '[')
	i := 0
	first := true
	for i < len(tm.tiles) {
		t := tm.tiles[i]
		j := i
		for j < len(tm.tiles) && tm.tiles[j] == t do j += 1
		if !first do strings.write_string(sb, ", ")
		first = false
		fmt.sbprintf(sb, "[%d, %d]", j - i, t)
		i = j
	}
	strings.write_byte(sb, ']')
}

// TileMapNode_SyncAseprite: with an Aseprite file as the tileset and an
// Aseprite Layer, the map is that tilemap layer (frame 1): its tile size,
// its cells (from the cel's position), and a tileset texture made from the
// layer's tileset - flipped tiles (X / Y / diagonal) baked in as extra
// tiles. Again whenever the file is saved. True when it (re)built.
TileMapNode_SyncAseprite :: proc(tm: ^TileMapNode) -> bool {
	if tm.asepriteLayer == "" || !Ase_IsPath(tm.tilesetPath) do return false
	rm := Node_ResourceManager(tm)
	if rm == nil || !rl.IsWindowReady() do return false
	if tm.aseRes == nil {
		tm.aseRes = ResourceManager_LoadAseprite(rm, Project_ResolveAssetPath(tm.gameContext, tm.tilesetPath))
		if tm.aseRes == nil do return false
		tm.aseVersion = -1
	}
	if tm.aseVersion == tm.aseRes.version do return false
	tm.aseVersion = tm.aseRes.version
	doc := tm.aseRes.doc
	li := Ase_FindLayer(doc, tm.asepriteLayer)
	if li < 0 || doc.layers[li].kind != .Tilemap || doc.layers[li].tileset >= len(doc.tilesets) || len(doc.frames) == 0 {
		log_tilemap_warn("TileMap %s: %s has no tilemap layer %q", tm.name, tm.tilesetPath, tm.asepriteLayer)
		return false
	}
	ts := &doc.tilesets[doc.layers[li].tileset]
	cel: ^Ase_Cel
	for &c in doc.frames[0].cels do if c.layer == li do cel = &c
	tw, th := ts.tile_w, ts.tile_h
	// The tiles the map uses, flips included: each becomes one of ours.
	Key :: struct {index: u32, x, y, d: bool}
	ids := make(map[Key]i32, allocator = context.temp_allocator)
	order := make([dynamic]Key, context.temp_allocator)
	zeroEmpty := ts.flags & 4 != 0
	if cel != nil do for t in cel.tiles {
		if (zeroEmpty && t.index == 0) || int(t.index) >= ts.count do continue
		k := Key{t.index, t.xflip, t.yflip, t.dflip}
		if k not_in ids {
			ids[k] = i32(len(order))
			append(&order, k)
		}
	}
	// The tileset texture: those tiles in a grid.
	n := max(len(order), 1)
	cols := 1
	for cols * cols < n do cols += 1
	rows := (n + cols - 1) / cols
	img := rl.GenImageColor(i32(cols * tw), i32(rows * th), {0, 0, 0, 0})
	defer rl.UnloadImage(img)
	dst := ([^]u8)(img.data)
	one := make([]u8, tw * th * 4, context.temp_allocator)
	for k, i in order {
		Ase_TileImage(doc, ts, int(k.index), k.x, k.y, k.d, one)
		ox, oy := (i % cols) * tw, (i / cols) * th
		for y in 0 ..< th do copy(dst[((oy + y) * cols * tw + ox) * 4:][:tw * 4], one[y * tw * 4:][:tw * 4])
	}
	if tm.tileset != nil do ResourceManager_ReleaseTexture(rm, tm.tileset)
	key := fmt.tprintf("%s#tileset:%s:%d", tm.tilesetPath, tm.asepriteLayer, tm.aseVersion)
	tm.tileset = ResourceManager_TextureFromImage(rm, key, img)
	if tm.tileset != nil do rl.SetTextureFilter(tm.tileset.texture, .POINT)
	// The map: the cel's tiles, offset by its position.
	ox, oy := 0, 0
	w, h := 1, 1
	if cel != nil {
		ox, oy = max(cel.x / max(tw, 1), 0), max(cel.y / max(th, 1), 0)
		w, h = cel.w + ox, cel.h + oy
	}
	tm.tileSize = {tw, th}
	tm.mapSize = {w, h}
	TileMapNode_Reset(tm)
	if cel != nil do for ty in 0 ..< cel.h do for tx in 0 ..< cel.w {
		t := cel.tiles[ty * cel.w + tx]
		if id, ok := ids[Key{t.index, t.xflip, t.yflip, t.dflip}]; ok do tm.tiles[(ty + oy) * w + tx + ox] = id
	}
	TileMapNode_Changed(tm)
	if tm.solid && tm.isReady && tm.gameContext != nil do TileMapNode_BuildColliders(tm, tm.gameContext)
	return true
}

@(private = "file")
log_tilemap_warn :: proc(format: string, args: ..any) {
	Script_Problem(.Warning, format, ..args)
}
