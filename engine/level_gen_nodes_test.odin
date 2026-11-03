package engine

import "core:fmt"
import "core:hash"
import "core:math"
import "core:strings"
import "core:testing"

// #171 part 2: the noise node's types (value / Perlin / Simplex) and the
// Poisson-disc scatter.

@(private = "file")
nodes_grid :: proc(t: ^testing.T, size: [2]int, seed: u64, nodes: string, id := 1) -> Gen_Grid {
	text := fmt.tprintf(`{{"size": [%d, %d], "seed": %d, "nodes": [%s]}}`, size.x, size.y, seed, nodes)
	g, err := Gen_GraphParse(transmute([]u8)text, context.temp_allocator)
	testing.expectf(t, err == "", "parse: %s", err)
	grid, e := Gen_Evaluate(&g, id, 0, context.temp_allocator)
	testing.expectf(t, e == "", "evaluate: %s", e)
	return grid
}

@(private = "file")
grid_hash :: proc(g: Gen_Grid) -> u64 {
	return hash.fnv64a(([^]u8)(raw_data(g.v))[:len(g.v) * size_of(f32)])
}

// Value noise (every graph saved before the type existed) gives exactly the
// grids it gave before: hashes of the grids' bits, taken before the change.
@(test)
test_level_gen_noise_value_pinned :: proc(t: ^testing.T) {
	Case :: struct {
		size:  [2]int,
		seed:  u64,
		node:  string,
		hash:  u64,
	}
	cases := []Case{
		{{64, 48}, 7, `{"id": 1, "type": "noise"}`, 0x9b92acee7cd07eb4},
		{{256, 256}, 3, `{"id": 1, "type": "noise", "params": {"scale": 24, "octaves": 4, "persistence": 0.6, "seed": 2}}`, 0x8bb06c62016e33de},
		// (Tiny features: hashed corners instead of a lattice.)
		{{50, 30}, 11, `{"id": 1, "type": "noise", "params": {"scale": 0.5, "octaves": 6}}`, 0x87e33785e3f6bba7},
	}
	for c in cases {
		g := nodes_grid(t, c.size, c.seed, c.node)
		h := grid_hash(g)
		testing.expectf(t, h == c.hash, "%s on %v (seed %d): hash 0x%x, was 0x%x", c.node, c.size, c.seed, h, c.hash)
	}
}

// Perlin and Simplex: 0..1, smooth, spread out, the same for a seed and
// different for another.
@(test)
test_level_gen_noise_gradient_types :: proc(t: ^testing.T) {
	for type in ([]string{"perlin", "simplex"}) {
		node := fmt.tprintf(`{{"id": 1, "type": "noise", "params": {{"type": %q, "scale": 12, "octaves": 1}}}}`, type)
		a := nodes_grid(t, {96, 64}, 5, node)
		b := nodes_grid(t, {96, 64}, 5, node)
		c := nodes_grid(t, {96, 64}, 6, node)
		testing.expectf(t, grid_hash(a) == grid_hash(b), "%s: the same seed gives the same grid", type)
		testing.expectf(t, grid_hash(a) != grid_hash(c), "%s: another seed gives another grid", type)
		lo, hi: f32 = 1, 0
		jump: f32
		for y in 0 ..< a.h do for x in 0 ..< a.w {
			v := a.v[y * a.w + x]
			lo, hi = min(lo, v), max(hi, v)
			if x > 0 do jump = max(jump, abs(v - a.v[y * a.w + x - 1]))
			if y > 0 do jump = max(jump, abs(v - a.v[(y - 1) * a.w + x]))
		}
		testing.expectf(t, lo >= 0 && hi <= 1, "%s: values %.3f..%.3f in 0..1", type, lo, hi)
		testing.expectf(t, hi - lo > 0.5, "%s: values spread (%.3f..%.3f)", type, lo, hi)
		testing.expectf(t, jump < 0.4, "%s: neighbours close (largest step %.3f)", type, jump)
		// Not value noise (nor each other).
		v := nodes_grid(t, {96, 64}, 5, `{"id": 1, "type": "noise", "params": {"scale": 12, "octaves": 1}}`)
		testing.expectf(t, grid_hash(a) != grid_hash(v), "%s differs from value noise", type)
		// With octaves: still 0..1, still the same for a seed.
		node = fmt.tprintf(`{{"id": 1, "type": "noise", "params": {{"type": %q, "scale": 20, "octaves": 5, "persistence": 0.55}}}}`, type)
		d := nodes_grid(t, {300, 200}, 9, node)
		e := nodes_grid(t, {300, 200}, 9, node)
		testing.expectf(t, grid_hash(d) == grid_hash(e), "%s: octaves (on the workers) the same each time", type)
		for v in d.v do if v < 0 || v > 1 {
			testing.expectf(t, false, "%s: fBm value %.3f out of 0..1", type, v)
			break
		}
	}
}

// Perlin and Simplex depend on the absolute cell only: a grid shifted by an
// origin (a chunk of a bigger level) has the same values at the same cells,
// and a bigger level the same values where they overlap.
@(test)
test_level_gen_noise_gradient_absolute :: proc(t: ^testing.T) {
	for simplex in ([]bool{false, true}) {
		a := Gen_Grid{64, 48, make([]f32, 64 * 48, context.temp_allocator)}
		b := Gen_Grid{40, 30, make([]f32, 40 * 30, context.temp_allocator)}
		origin := [2]int{13, -7}
		gen_gradient_noise(a, {0, 0}, 10, 4, 0.5, 77, simplex)
		gen_gradient_noise(b, origin, 10, 4, 0.5, 77, simplex)
		same := 0
		for y in 0 ..< b.h do for x in 0 ..< b.w {
			ax, ay := origin.x + x, origin.y + y
			if ax < 0 || ay < 0 || ax >= a.w || ay >= a.h do continue
			if b.v[y * b.w + x] == a.v[ay * a.w + ax] do same += 1
			else do testing.expectf(t, false, "simplex=%v: cell (%d, %d) %.6f vs %.6f", simplex, ax, ay, b.v[y * b.w + x], a.v[ay * a.w + ax])
		}
		testing.expectf(t, same == 40 * 23, "simplex=%v: %d overlapping cells match", simplex, same)
		// Negative cells (left of / above the origin) are fine too: smooth across 0.
		c := Gen_Grid{20, 20, make([]f32, 400, context.temp_allocator)}
		gen_gradient_noise(c, {-10, -10}, 6, 1, 0.5, 77, simplex)
		for y in 0 ..< 20 do for x in 1 ..< 20 do testing.expectf(t, abs(c.v[y * 20 + x] - c.v[y * 20 + x - 1]) < 0.6, "simplex=%v: smooth across 0 at (%d, %d)", simplex, x - 10, y - 10)
	}
	// Through the graph: the level's size doesn't matter.
	for type in ([]string{"perlin", "simplex"}) {
		node := fmt.tprintf(`{{"id": 1, "type": "noise", "params": {{"type": %q, "scale": 9, "octaves": 3}}}}`, type)
		small := nodes_grid(t, {50, 40}, 3, node)
		big := nodes_grid(t, {130, 90}, 3, node)
		diff := 0
		for y in 0 ..< small.h do for x in 0 ..< small.w do if small.v[y * small.w + x] != big.v[y * big.w + x] do diff += 1
		testing.expectf(t, diff == 0, "%s: %d cells differ between a 50x40 and a 130x90 level", type, diff)
	}
}

// The type is saved by name; a file without it is value noise, and value
// saves as before plus "type": "value".
@(test)
test_level_gen_noise_type_file :: proc(t: ^testing.T) {
	g, err := Gen_GraphParse(transmute([]u8)string(`{"size": [8, 8], "nodes": [{"id": 1, "type": "noise", "params": {"scale": 5}}, {"id": 2, "type": "noise", "params": {"type": "simplex"}}]}`), context.temp_allocator)
	testing.expectf(t, err == "", "parse: %s", err)
	testing.expect_value(t, Gen_Param(Gen_FindNode(&g, 1), "type"), 0)
	testing.expect_value(t, Gen_Param(Gen_FindNode(&g, 1), "scale"), 5)
	testing.expect_value(t, Gen_Param(Gen_FindNode(&g, 2), "type"), 2)
	text := Gen_GraphSerialize(&g, context.temp_allocator)
	testing.expectf(t, strings.contains(text, `"type": "value"`) && strings.contains(text, `"type": "simplex"`), "saved by name: %s", text)
	h, herr := Gen_GraphParse(transmute([]u8)text, context.temp_allocator)
	testing.expectf(t, herr == "", "reparse: %s", herr)
	testing.expect_value(t, Gen_Param(Gen_FindNode(&h, 2), "type"), 2)
	testing.expect_value(t, Gen_Param(Gen_FindNode(&h, 1), "type"), 0)
}

@(private = "file")
poisson_points :: proc(g: Gen_Grid) -> [dynamic][2]int {
	pts := make([dynamic][2]int, context.temp_allocator)
	for y in 0 ..< g.h do for x in 0 ..< g.w {
		v := g.v[y * g.w + x]
		testing_ok := v == 0 || v == 1
		assert(testing_ok)
		if v >= 0.5 do append(&pts, [2]int{x, y})
	}
	return pts
}

@(private = "file")
poisson_min_dist2 :: proc(pts: [dynamic][2]int) -> int {
	best := max(int)
	for a, i in pts do for b in pts[i + 1:] {
		d := b - a
		best = min(best, d.x * d.x + d.y * d.y)
	}
	return best
}

// Poisson-disc: every pair at least `radius` apart, filling the level
// (about as many as a random close packing holds), the same for a seed.
@(test)
test_level_gen_poisson :: proc(t: ^testing.T) {
	Case :: struct {
		size:   [2]int,
		radius: f32,
	}
	for c in ([]Case{{{64, 64}, 4}, {{128, 96}, 2.5}, {{90, 70}, 7}, {{40, 30}, 1}}) {
		node := fmt.tprintf(`{{"id": 1, "type": "poisson_scatter", "params": {{"radius": %v}}}}`, c.radius)
		g := nodes_grid(t, c.size, 4, node)
		pts := poisson_points(g)
		d2 := poisson_min_dist2(pts)
		testing.expectf(t, f32(d2) >= c.radius * c.radius, "r %v: two points %.2f apart", c.radius, math.sqrt(f32(d2)))
		// A maximal disc packing holds between about 1 / (2.5 r^2) and 1 / (0.87 r^2) points per cell.
		area := f32(c.size.x * c.size.y)
		lo, hi := int(area / (2.5 * c.radius * c.radius)), int(area / (0.87 * c.radius * c.radius)) + 4
		testing.expectf(t, len(pts) >= lo && len(pts) <= hi, "r %v on %v: %d points (expected %d..%d)", c.radius, c.size, len(pts), lo, hi)
		again := nodes_grid(t, c.size, 4, node)
		testing.expectf(t, grid_hash(g) == grid_hash(again), "r %v: the same seed, the same points", c.radius)
		// (Radius 1: every cell - the same for any seed.)
		other := nodes_grid(t, c.size, 5, node)
		testing.expectf(t, c.radius <= 1 || grid_hash(g) != grid_hash(other), "r %v: another seed, other points", c.radius)
		if c.radius <= 1 do testing.expect_value(t, len(pts), c.size.x * c.size.y)
	}
	// No empty stretches: every cell within 2 r of a point.
	g := nodes_grid(t, {80, 60}, 2, `{"id": 1, "type": "poisson_scatter", "params": {"radius": 5}}`)
	pts := poisson_points(g)
	worst := 0
	for y in 0 ..< g.h do for x in 0 ..< g.w {
		near := max(int)
		for p in pts do near = min(near, (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y))
		worst = max(worst, near)
	}
	testing.expectf(t, worst <= 100, "a cell %.1f cells from every point", math.sqrt(f32(worst)))
	// Fewer attempts: sparser, never closer.
	sparse := poisson_points(nodes_grid(t, {80, 60}, 2, `{"id": 1, "type": "poisson_scatter", "params": {"radius": 5, "attempts": 1}}`))
	testing.expectf(t, len(sparse) < len(pts) && poisson_min_dist2(sparse) >= 25, "attempts 1: %d points (30: %d)", len(sparse), len(pts))
}

// With a mask: points only on its solid cells - both of two islands far
// apart get theirs (each walk starts again where none reached).
@(test)
test_level_gen_poisson_mask :: proc(t: ^testing.T) {
	nodes := `{"id": 1, "type": "rect", "params": {"x": 2, "y": 2, "w": 20, "h": 16}},
		{"id": 2, "type": "rect", "params": {"x": 60, "y": 30, "w": 15, "h": 15}},
		{"id": 3, "type": "combine", "inputs": {"a": 1, "b": 2}, "params": {"op": "max"}},
		{"id": 4, "type": "poisson_scatter", "inputs": {"mask": 3}, "params": {"radius": 3}}`
	for seed in u64(1) ..= 8 {
		mask := nodes_grid(t, {80, 50}, seed, nodes, 3)
		g := nodes_grid(t, {80, 50}, seed, nodes, 4)
		pts := poisson_points(g)
		inA, inB := 0, 0
		for p in pts {
			testing.expectf(t, mask.v[p.y * mask.w + p.x] >= 0.5, "seed %d: a point off the mask at %v", seed, p)
			if p.x < 30 do inA += 1
			else do inB += 1
		}
		testing.expectf(t, inA >= 15 && inB >= 10, "seed %d: %d points on the first island, %d on the second", seed, inA, inB)
		testing.expectf(t, poisson_min_dist2(pts) >= 9, "seed %d: two points too close", seed)
	}
	// An empty mask: no points.
	g := nodes_grid(t, {30, 30}, 1, `{"id": 1, "type": "constant", "params": {"value": 0}}, {"id": 2, "type": "poisson_scatter", "inputs": {"mask": 1}}`, 2)
	testing.expect_value(t, len(poisson_points(g)), 0)
}

