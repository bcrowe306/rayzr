package engine

import "core:fmt"
import "core:strings"
import "core:testing"
import "core:time"

// #171: the Wave Function Collapse node - rules learned from a painted
// sample (or Wang tiles' edges), the solver's results, the file.

// A sample of grass (0), path (51) and water (451): water only ever touches
// path or water, never grass.
@(private = "file")
WFC_SAMPLE :: `"sample": {"size": [8, 8], "cells": [
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 51, 51, 51, 0, 0, 0,
	0, 51, 51, 451, 451, 51, 0, 0,
	0, 51, 451, 451, 451, 51, 0, 0,
	0, 51, 51, 451, 51, 51, 0, 0,
	0, 0, 51, 51, 51, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0]}`

@(private = "file")
wfc_graph :: proc(t: ^testing.T, size: [2]int, seed: u64, nodes: string) -> Gen_Graph {
	text := fmt.tprintf(`{{"size": [%d, %d], "seed": %d, "nodes": [%s]}}`, size.x, size.y, seed, nodes)
	g, err := Gen_GraphParse(transmute([]u8)text, context.temp_allocator)
	testing.expectf(t, err == "", "parse: %s", err)
	return g
}

@(private = "file")
wfc_node :: proc(extra := "") -> string {
	return fmt.tprintf(`{{"id": 1, "type": "wfc"%s, %s}}`, extra, WFC_SAMPLE)
}

// Every pair of neighbours in the output is a pair the sample has, and
// every tile is one of the sample's.
@(test)
test_level_gen_wfc_follows_sample :: proc(t: ^testing.T) {
	g := wfc_graph(t, {40, 30}, 3, wfc_node())
	grid, err := Gen_Evaluate(&g, 1, 0, context.temp_allocator)
	testing.expectf(t, err == "", "evaluate: %s", err)
	rules, why := Gen_WFCRules(&g.nodes[0])
	testing.expectf(t, why == "", "rules: %s", why)
	testing.expect_value(t, len(rules.tiles), 3)
	testing.expect(t, !Gen_WFCAllows(&rules, 0, 451, 0) && !Gen_WFCAllows(&rules, 451, 0, 1), "grass never next to water")
	seen: map[i32]int
	defer delete(seen)
	bad := 0
	for y in 0 ..< grid.h do for x in 0 ..< grid.w {
		a := i32(Gen_GridAt(grid, x, y))
		seen[a] += 1
		testing.expectf(t, a == 0 || a == 51 || a == 451, "a tile of the sample (%d)", a)
		if x + 1 < grid.w && !Gen_WFCAllows(&rules, a, i32(Gen_GridAt(grid, x + 1, y)), 0) do bad += 1
		if y + 1 < grid.h && !Gen_WFCAllows(&rules, a, i32(Gen_GridAt(grid, x, y + 1)), 1) do bad += 1
	}
	testing.expectf(t, bad == 0, "%d neighbours the sample doesn't have", bad)
	testing.expect(t, seen[0] > 0 && seen[51] > 0, "grass and path both used")
}

@(test)
test_level_gen_wfc_deterministic :: proc(t: ^testing.T) {
	run :: proc(t: ^testing.T, seed: u64) -> string {
		g := wfc_graph(t, {32, 24}, seed, wfc_node())
		grid, err := Gen_Evaluate(&g, 1, 0, context.temp_allocator)
		testing.expectf(t, err == "", "evaluate: %s", err)
		sb := strings.builder_make(context.temp_allocator)
		for v in grid.v do fmt.sbprintf(&sb, "%v,", v)
		return strings.to_string(sb)
	}
	a, b, c := run(t, 7), run(t, 7), run(t, 8)
	testing.expect(t, a == b, "the same seed: the same level")
	testing.expect(t, a != c, "another seed: another level")
}

// Masked out: -1; inside: tiles.
@(test)
test_level_gen_wfc_mask :: proc(t: ^testing.T) {
	g := wfc_graph(t, {30, 20}, 2, `{"id": 2, "type": "rect", "params": {"x": 5, "y": 4, "w": 12, "h": 9}},
		{"id": 1, "type": "wfc", "inputs": {"mask": 2}, ` + WFC_SAMPLE + `}`)
	grid, err := Gen_Evaluate(&g, 1, 0, context.temp_allocator)
	testing.expectf(t, err == "", "evaluate: %s", err)
	for y in 0 ..< grid.h do for x in 0 ..< grid.w {
		inside := x >= 5 && x < 17 && y >= 4 && y < 13
		v := Gen_GridAt(grid, x, y)
		if inside do testing.expectf(t, v >= 0, "(%d, %d) filled", x, y)
		else do testing.expectf(t, v == -1, "(%d, %d) outside the mask: %v", x, y, v)
	}
}

// Fixed cells keep their tile; with a tile output in tile_ids mode the ids
// become the tiles (-1: its empty).
@(test)
test_level_gen_wfc_fixed_and_output :: proc(t: ^testing.T) {
	g := wfc_graph(t, {12, 10}, 4, `{"id": 2, "type": "constant", "params": {"value": 451}},
		{"id": 1, "type": "wfc", "inputs": {"fixed": 2}, ` + WFC_SAMPLE + `},
		{"id": 3, "type": "tile_output", "inputs": {"in": 1}, "params": {"tile_ids": true}}`)
	tiles, size, err := Gen_Tiles(&g, 3, 0, context.temp_allocator)
	testing.expectf(t, err == "", "tiles: %s", err)
	testing.expect_value(t, size, [2]int{12, 10})
	for v in tiles do testing.expect_value(t, v, i32(451))
	// Saved only when on.
	text := Gen_GraphSerialize(&g, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"tile_ids": 1`), "tile_ids saved")
	Gen_SetParam(&g.nodes[2], "tile_ids", 0)
	testing.expect(t, !strings.contains(Gen_GraphSerialize(&g, context.temp_allocator), `"tile_ids"`), "off: not written")
}

// Rules that can't fill a row (a tile whose east edge matches no west
// edge): every try fails, quickly, and the node says so.
@(test)
test_level_gen_wfc_contradiction :: proc(t: ^testing.T) {
	g := wfc_graph(t, {64, 64}, 1, `{"id": 1, "type": "wfc", "params": {"rules": "wang", "attempts": 5}, "wang": [
		{"tile": 1, "edges": [0, 1, 0, 2]}, {"tile": 2, "edges": [0, 1, 0, 3]}]}`)
	start := time.tick_now()
	_, err := Gen_Evaluate(&g, 1, 0, context.temp_allocator)
	testing.expectf(t, strings.contains(err, "node 1 (wfc)") && strings.contains(err, "contradiction"), "reported: %q", err)
	testing.expect(t, time.duration_seconds(time.tick_since(start)) < 5, "no hang")
	// No sample painted: says what to do.
	g2 := wfc_graph(t, {8, 8}, 1, `{"id": 1, "type": "wfc"}`)
	_, err2 := Gen_Evaluate(&g2, 1, 0, context.temp_allocator)
	testing.expectf(t, strings.contains(err2, "paint its sample"), "empty sample: %q", err2)
}

// Wang tiles: every touching pair of edges matches.
@(test)
test_level_gen_wfc_wang :: proc(t: ^testing.T) {
	// All 16 tiles of 2 colours on the east/south edges, west/north the
	// same set: tile id = n + 2e + 4s + 8w.
	sb := strings.builder_make(context.temp_allocator)
	for id in 0 ..< 16 {
		fmt.sbprintf(&sb, `%s{{"tile": %d, "edges": [%d, %d, %d, %d], "weight": %d}}`, ", " if id > 0 else "", id, id & 1, (id >> 1) & 1, (id >> 2) & 1, (id >> 3) & 1, 1 + id % 3)
	}
	g := wfc_graph(t, {32, 32}, 9, fmt.tprintf(`{{"id": 1, "type": "wfc", "params": {{"rules": "wang"}}, "wang": [%s]}}`, strings.to_string(sb)))
	grid, err := Gen_Evaluate(&g, 1, 0, context.temp_allocator)
	testing.expectf(t, err == "", "evaluate: %s", err)
	edge :: proc(id, side: int) -> int {return (id >> uint(side)) & 1}
	bad := 0
	used: [16]bool
	for y in 0 ..< grid.h do for x in 0 ..< grid.w {
		a := int(Gen_GridAt(grid, x, y))
		used[a] = true
		if x + 1 < grid.w && edge(a, 1) != edge(int(Gen_GridAt(grid, x + 1, y)), 3) do bad += 1
		if y + 1 < grid.h && edge(a, 2) != edge(int(Gen_GridAt(grid, x, y + 1)), 0) do bad += 1
	}
	testing.expectf(t, bad == 0, "%d edges don't match", bad)
	kinds := 0
	for u in used do if u do kinds += 1
	testing.expectf(t, kinds >= 12, "most tiles used (%d)", kinds)
}

// The sample and Wang tiles come back from the file; a duplicate and a
// resize keep the cells.
@(test)
test_level_gen_wfc_file :: proc(t: ^testing.T) {
	g := wfc_graph(t, {16, 16}, 1, wfc_node(`, "params": {"wrap": true, "attempts": 3}, "wang": [{"tile": 7, "edges": [1, 2, 3, 4], "weight": 0.5}]`))
	text := Gen_GraphSerialize(&g, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"sample": {"size": [8, 8], "cells": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 51, 51, 51,`), "the sample written")
	testing.expect(t, strings.contains(text, `"wang": [{"tile": 7, "edges": [1, 2, 3, 4], "weight": 0.5}]`), "the Wang tiles written")
	g2, err := Gen_GraphParse(transmute([]u8)text, context.temp_allocator)
	testing.expectf(t, err == "", "parse: %s", err)
	testing.expect(t, Gen_GraphSerialize(&g2, context.temp_allocator) == text, "round trip")
	n := &g2.nodes[0]
	testing.expect_value(t, n.sample.w, 8)
	testing.expect_value(t, n.sample.cells[3 * 8 + 3], i32(451))
	testing.expect(t, Gen_Param(n, "wrap") != 0, "wrap")

	d := Gen_DuplicateNode(&g2, 1)
	testing.expect(t, d != nil && len(d.sample.cells) == 64 && d.sample.cells[3 * 8 + 3] == 451 && len(d.wang) == 1, "duplicated")
	Gen_WFCResizeSample(&g2, d, {4, 10})
	testing.expect_value(t, d.sample.w, 4)
	testing.expect_value(t, d.sample.cells[3 * 4 + 3], i32(451))
	testing.expect_value(t, d.sample.cells[9 * 4], i32(-1))
	testing.expect(t, Gen_WFCSetCell(d, 0, 9, 51) && d.sample.cells[9 * 4] == 51, "painted")
	testing.expect(t, n.sample.w == 8, "the original keeps its sample")

	// A new node starts with an unpainted 8 x 8 sample - so does one read
	// without "sample" - written once painted or resized.
	a := Gen_AddNode(&g2, .WFC, {})
	testing.expect(t, a.sample.w == GEN_WFC_SAMPLE_DEFAULT && len(a.sample.cells) == 64 && a.sample.cells[0] == -1, "default sample")
	g3 := wfc_graph(t, {8, 8}, 1, `{"id": 1, "type": "wfc"}`)
	testing.expect(t, g3.nodes[0].sample.w == 8 && len(g3.nodes[0].sample.cells) == 64, "a sample to paint")
	testing.expect(t, !strings.contains(Gen_GraphSerialize(&g3, context.temp_allocator), `"sample": {`), "unpainted: not written")
	Gen_WFCSetCell(&g3.nodes[0], 2, 1, 5)
	testing.expect(t, strings.contains(Gen_GraphSerialize(&g3, context.temp_allocator), `"sample": {"size": [8, 8], "cells": [-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 5,`), "painted: written")
}

// The progress of a generation moves while the node solves.
@(test)
test_level_gen_wfc_progress :: proc(t: ^testing.T) {
	g := wfc_graph(t, {64, 64}, 3, fmt.tprintf(`%s, {{"id": 2, "type": "tile_output", "inputs": {{"in": 1}}, "params": {{"tile_ids": true}}}}`, wfc_node()))
	p: Gen_Progress
	Gen_ProgressAttempt(&p, Gen_NeededNodes(&g), true)
	r, err := Gen_Generate(&g, 0, context.temp_allocator, &p)
	testing.expectf(t, err == "", "generate: %s", err)
	testing.expect(t, len(r.tiles) == 64 * 64 && r.tiles[0] >= 0, "tiles")
	testing.expect(t, Gen_ProgressValue(&p) == 1, "done")
}

// Timings (printed; scripts/bench.sh runs it with -o:speed).
@(test)
bench_level_gen_wfc :: proc(t: ^testing.T) {
	for size in ([]int{64, 128}) {
		g := wfc_graph(t, {size, size}, 5, wfc_node())
		RUNS :: 5
		start := time.tick_now()
		for _ in 0 ..< RUNS {
			_, err := Gen_Evaluate(&g, 1, 0, context.temp_allocator)
			testing.expectf(t, err == "", "evaluate: %s", err)
		}
		fmt.printf("[bench] levelgen wfc %dx%d (3 tiles, sample): %.2f ms\n", size, size, time.duration_milliseconds(time.tick_since(start)) / RUNS)
		free_all(context.temp_allocator)
	}
	for size in ([]int{64, 128}) {
		sb := strings.builder_make(context.temp_allocator)
		for id in 0 ..< 16 do fmt.sbprintf(&sb, `%s{{"tile": %d, "edges": [%d, %d, %d, %d]}}`, ", " if id > 0 else "", id, id & 1, (id >> 1) & 1, (id >> 2) & 1, (id >> 3) & 1)
		g := wfc_graph(t, {size, size}, 5, fmt.tprintf(`{{"id": 1, "type": "wfc", "params": {{"rules": "wang"}}, "wang": [%s]}}`, strings.to_string(sb)))
		RUNS :: 5
		start := time.tick_now()
		for _ in 0 ..< RUNS do _, _ = Gen_Evaluate(&g, 1, 0, context.temp_allocator)
		fmt.printf("[bench] levelgen wfc %dx%d (16 Wang tiles): %.2f ms\n", size, size, time.duration_milliseconds(time.tick_since(start)) / RUNS)
		free_all(context.temp_allocator)
	}
}
