package engine

import rl "vendor:raylib"

// ============================================================================
// Animated tiles (#275): a tileset's tiles that play frames - water,
// torches, grass. Kept with the tileset's terrains in its sidecar
// (<image>.tileset.json, terrain.odin):
//
//   "animations": [{"frames": [[12, 120], [13, 120], [14, 200]], "desync": true}]
//
// Each frame is a tile and how long it shows (ms). Wherever the first frame's
// tile (12) is painted, every TileMap on the tileset plays the animation.
// All copies share one clock (they move in step); with desync each cell
// starts at its own point, so neighbours don't flicker in unison.
// ============================================================================

Tile_Anim :: struct {
	frames:    [dynamic]i32,
	durations: [dynamic]f32, // seconds, one per frame
	desync:    bool,
}

// Tile_AnimTotal: one loop's length in seconds.
Tile_AnimTotal :: proc(a: ^Tile_Anim) -> f32 {
	t: f32
	for d in a.durations do t += max(d, 0.001)
	return t
}

// Tile_AnimFrame: the tile an animation shows at `t` seconds in a cell.
Tile_AnimFrame :: proc(a: ^Tile_Anim, t: f64, cell: [2]int) -> i32 {
	n := len(a.frames)
	if n == 0 do return -1
	total := f64(Tile_AnimTotal(a))
	if total <= 0 do return a.frames[0]
	tt := t
	if a.desync do tt += f64(gen_hash01(cell.x, cell.y, 0x7a11e5)) * total
	tt = tt - total * f64(i64(tt / total))
	for d, i in a.durations {
		tt -= f64(max(d, 0.001))
		if tt < 0 do return a.frames[i]
	}
	return a.frames[n - 1]
}

// Tile_AnimClock: the time tile animations play by - the game's clock
// while it runs (fixed steps: the same in every test run), else real time
// (the editor).
Tile_AnimClock :: proc(ctx: ^GameContext) -> f64 {
	if ctx != nil && ctx.game != nil && ctx.game.clockRunning do return ctx.game.clock
	return rl.GetTime() if rl.IsWindowReady() else 0
}

// TileMapNode_SetAnimations takes a tileset's animations (keyed by their
// first frame's tile) - SetTileset loads them; the editor after an edit.
TileMapNode_SetAnimations :: proc(tm: ^TileMapNode, anims: []Tile_Anim) {
	tilemap_free_anims(tm)
	for &a in anims {
		if len(a.frames) < 2 do continue
		if tm.anims == nil do tm.anims = make(map[i32]Tile_Anim, allocator = tm.allocator)
		c := Tile_Anim{make([dynamic]i32, tm.allocator), make([dynamic]f32, tm.allocator), a.desync}
		append(&c.frames, ..a.frames[:])
		append(&c.durations, ..a.durations[:])
		tm.anims[a.frames[0]] = c
	}
	tm.cacheVersion += 1 // (chunks leave animated tiles out)
}

tilemap_free_anims :: proc(tm: ^TileMapNode) {
	for _, &a in tm.anims {
		delete(a.frames)
		delete(a.durations)
	}
	clear(&tm.anims)
}
