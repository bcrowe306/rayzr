package engine

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// Tile layer cache: static tile layers (TileMapNode, LDtk tile / auto
// layers) are drawn into render textures in chunks of up to
// TILE_CHUNK_PX x TILE_CHUNK_PX pixels, and then each visible chunk is one
// quad instead of hundreds of tiles (a 400x400 map seen zoomed out: ~57k
// tiles a frame).
//
// - Chunks are built in TileCache_Prepare (before the frame's render
//   target is bound: render textures can't nest), for what's in view.
// - Tiles are composited with premultiplied alpha (stacked auto-layer
//   tiles blend as they would on screen) and chunks are drawn with
//   premultiplied blending; the layer's tint and opacity apply when drawing.
// - Only layers with at least TILE_CACHE_MIN_TILES tiles in view use it.
// - A chunk is rebuilt when its layer's version changes. At most
//   TILE_CACHE_MAX_CHUNKS live at once (least recently used go first);
//   chunks that don't fit, and layers with a material (its shader expects
//   the tileset's texture coordinates), are drawn tile by tile as before.
// ============================================================================

TILE_CHUNK_PX :: 512
TILE_CACHE_MAX_CHUNKS :: 96

Tile_Chunk_Key :: struct {
	owner: rawptr, // the node
	layer: rawptr, // a layer within it (or the node)
	load:  u64,    // the layer data's load id (LDtk reloads reuse addresses)
	cx, cy: i32,
}

@(private = "file")
Tile_Chunk :: struct {
	rt:      rl.RenderTexture2D,
	version: u64,
	used:    u64, // frame last prepared for
}

@(private = "file")
tileCache: struct {
	chunks:  map[Tile_Chunk_Key]Tile_Chunk,
	frame:    u64,
	disabled: bool,
	builds:   int, // chunks built so far
}

TileCache_Enabled :: proc() -> bool {return !tileCache.disabled}

TileCache_SetEnabled :: proc(on: bool) {
	tileCache.disabled = !on
	if !on do TileCache_Clear()
}

// TileCache_Clear frees every chunk.
TileCache_Clear :: proc() {
	if rl.IsWindowReady() do for _, ch in tileCache.chunks do rl.UnloadRenderTexture(ch.rt)
	delete(tileCache.chunks)
	tileCache.chunks = nil
}

// TileCache_Evict frees a node's chunks (node destroyed or its data replaced).
TileCache_Evict :: proc(owner: rawptr) {
	if len(tileCache.chunks) == 0 do return
	keys := make([dynamic]Tile_Chunk_Key, context.temp_allocator)
	for k in tileCache.chunks do if k.owner == owner do append(&keys, k)
	for k in keys {
		if rl.IsWindowReady() do rl.UnloadRenderTexture(tileCache.chunks[k].rt)
		delete_key(&tileCache.chunks, k)
	}
}

// Layers with fewer tiles in view than this draw them directly (each chunk
// is its own texture, so a few chunks cost more than a few hundred tiles).
TILE_CACHE_MIN_TILES :: 2048

// TileCache_Prepare builds (or refreshes) the chunks of every tile layer in
// view. Call once a frame before binding the frame's render target, with
// the context the scene renders with.
TileCache_Prepare :: proc(scene: ^Scene, view: rl.Rectangle, ctx: ^GameContext) {
	tileCache.frame += 1
	if tileCache.disabled || scene == nil || scene.manager == nil || !rl.IsWindowReady() do return
	for n in scene.manager.nodes {
		if n == nil || !n.enabled || !Node_VisibleInTree(n) || n.material != nil do continue
		switch n.typeId {
		case TileMapNode:   TileMapNode_PrepareChunks(cast(^TileMapNode)n, view)
		case LdtkLevelNode: LdtkLevelNode_PrepareChunks(cast(^LdtkLevelNode)n, view, ctx)
		}
	}
	Render_RestoreFrameTarget() // post effects: back to the frame's target
}

// TileCache_Ensure makes sure a chunk exists and matches `version`,
// building it with `build` (drawing in chunk-local pixels) if not. Returns
// false when the cache is full of chunks in use this frame.
TileCache_Ensure :: proc(key: Tile_Chunk_Key, version: u64, size: [2]i32, build: proc(data: rawptr, key: Tile_Chunk_Key), data: rawptr) -> bool {
	ch, has := tileCache.chunks[key]
	if has && ch.version == version && ch.rt.texture.width == size.x && ch.rt.texture.height == size.y {
		ch.used = tileCache.frame
		tileCache.chunks[key] = ch
		return true
	}
	if !has {
		if len(tileCache.chunks) >= TILE_CACHE_MAX_CHUNKS && !evict_lru() do return false
		ch.rt = rl.LoadRenderTexture(size.x, size.y)
		if ch.rt.id == 0 do return false
	} else if ch.rt.texture.width != size.x || ch.rt.texture.height != size.y {
		rl.UnloadRenderTexture(ch.rt)
		ch.rt = rl.LoadRenderTexture(size.x, size.y)
	}
	rl.BeginTextureMode(ch.rt)
	rl.ClearBackground({0, 0, 0, 0})
	// Premultiplied "over": rgb = src.rgb*src.a + dst.rgb*(1-src.a),
	// a = src.a + dst.a*(1-src.a).
	rlgl.SetBlendFactorsSeparate(rlgl.SRC_ALPHA, rlgl.ONE_MINUS_SRC_ALPHA, rlgl.ONE, rlgl.ONE_MINUS_SRC_ALPHA, rlgl.FUNC_ADD, rlgl.FUNC_ADD)
	rl.BeginBlendMode(.CUSTOM_SEPARATE)
	build(data, key)
	rl.EndBlendMode()
	rl.EndTextureMode()
	ch.version = version
	ch.used = tileCache.frame
	tileCache.chunks[key] = ch
	tileCache.builds += 1
	return true
}

@(private = "file")
evict_lru :: proc() -> bool {
	oldest: Tile_Chunk_Key
	found := false
	at := tileCache.frame
	for k, ch in tileCache.chunks {
		if ch.used < at {
			at = ch.used
			oldest = k
			found = true
		}
	}
	if !found do return false // everything is in use this frame
	rl.UnloadRenderTexture(tileCache.chunks[oldest].rt)
	delete_key(&tileCache.chunks, oldest)
	return true
}

// TileCache_Draw draws a chunk prepared this frame (false: not cached - draw
// its tiles). `src` is the part of the chunk to show (edge chunks are
// partly empty); dst/rotation as for DrawTexturePro (rotation about the
// chunk's top-left corner). Draw a layer's chunks between
// TileCache_BeginDraw and TileCache_EndDraw (premultiplied blending,
// switched once: every blend change flushes raylib's batch, which stalls
// on some drivers), then its uncached tiles.
TileCache_Draw :: proc(key: Tile_Chunk_Key, version: u64, src: rl.Rectangle, dst: rl.Rectangle, rotation: f32, tint: rl.Color, opacity: f32 = 1) -> bool {
	ch, has := tileCache.chunks[key]
	if !has || ch.version != version || ch.used != tileCache.frame do return false
	o := clamp(opacity * f32(tint.a) / 255, 0, 1)
	col := rl.Color{u8(f32(tint.r) * o), u8(f32(tint.g) * o), u8(f32(tint.b) * o), u8(255 * o)}
	// Render textures are stored upside down.
	h := f32(ch.rt.texture.height)
	rl.DrawTexturePro(ch.rt.texture, {src.x, h - src.y - src.height, src.width, -src.height}, dst, {0, 0}, rotation, col)
	return true
}

TileCache_BeginDraw :: proc() {rl.BeginBlendMode(.ALPHA_PREMULTIPLY)}
TileCache_EndDraw :: proc() {rl.EndBlendMode()}

// TileCache_Stats: live chunks (tests, profiler).
TileCache_Stats :: proc() -> int {
	return len(tileCache.chunks)
}

// TileCache_Builds: chunks built since start (a steady scene stops building).
TileCache_Builds :: proc() -> int {
	return tileCache.builds
}
