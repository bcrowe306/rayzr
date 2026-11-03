package engine

import "core:fmt"
import "core:testing"
import "core:time"

// #171: what generating a level costs - a cave + noise graph of every heavy
// kind (cellular, noise of each type, blur, scatter, Poisson scatter, the
// outputs) at 128 / 256 / 512 cells square: a whole generation (tiles and
// entities), the editor's previews (every node) cold and after one change,
// and each node alone (its inputs cached). Printed, not asserted (scripts/bench.sh runs it with
// -o:speed).

@(private = "file")
bench_graph_text :: proc(size: int) -> string {
	return fmt.tprintf(`{{"size": [%d, %d], "seed": 7, "output": 13, "nodes": [
		{{"id": 1, "type": "random_fill", "params": {{"density": 0.48}}}},
		{{"id": 2, "type": "cellular", "inputs": {{"in": 1}}, "params": {{"iterations": 5}}}},
		{{"id": 3, "type": "border", "params": {{"width": 1}}}},
		{{"id": 4, "type": "combine", "inputs": {{"a": 2, "b": 3}}, "params": {{"op": "max"}}}},
		{{"id": 5, "type": "noise", "params": {{"scale": 24, "octaves": 4}}}},
		{{"id": 6, "type": "blur", "inputs": {{"in": 5}}, "params": {{"radius": 3}}}},
		{{"id": 7, "type": "threshold", "inputs": {{"in": 6}}, "params": {{"value": 0.55}}}},
		{{"id": 8, "type": "combine", "inputs": {{"a": 4, "b": 7}}, "params": {{"op": "max"}}}},
		{{"id": 9, "type": "dilate", "inputs": {{"in": 7}}, "params": {{"iterations": 2}}}},
		{{"id": 10, "type": "surface", "inputs": {{"in": 8}}}},
		{{"id": 11, "type": "scatter", "inputs": {{"in": 10}}, "params": {{"chance": 0.05, "spacing": 6}}}},
		{{"id": 12, "type": "entity_output", "inputs": {{"in": 11}}, "component": "components/coin.component.json"}},
		{{"id": 13, "type": "tile_output", "inputs": {{"in": 8}}, "rules": [{{"min": 0.5, "max": 1, "tiles": [3, 4]}}]}},
		{{"id": 14, "type": "noise", "params": {{"type": "perlin", "scale": 24, "octaves": 4}}}},
		{{"id": 15, "type": "noise", "params": {{"type": "simplex", "scale": 24, "octaves": 4}}}},
		{{"id": 16, "type": "poisson_scatter", "params": {{"radius": 4}}}},
		{{"id": 17, "type": "poisson_scatter", "inputs": {{"mask": 10}}, "params": {{"radius": 6}}}}]}}`, size, size)
}

@(test)
bench_level_gen :: proc(t: ^testing.T) {
	for size in ([]int{128, 256, 512}) {
		g, err := Gen_GraphParse(transmute([]u8)bench_graph_text(size))
		testing.expectf(t, err == "", "parse: %s", err)
		defer Gen_GraphDestroy(&g)
		ms :: proc(start: time.Tick) -> f64 {return time.duration_milliseconds(time.tick_since(start))}

		// A whole generation, as the game's Level Generator node runs it.
		RUNS :: 5
		start := time.tick_now()
		entities := 0
		for _ in 0 ..< RUNS {
			r, e := Gen_Generate(&g, 0, context.temp_allocator)
			testing.expectf(t, e == "", "generate: %s", e)
			entities = len(r.entities)
			free_all(context.temp_allocator)
		}
		fmt.printf("[bench] levelgen %dx%d generate: %.2f ms (%d entities)\n", size, size, ms(start) / RUNS, entities)

		// The editor's previews: every node's grid, cold, then again after a
		// change to the last tile output's rule (nothing upstream changed).
		cache: Gen_Cache
		Gen_CacheInit(&cache)
		defer Gen_CacheDestroy(&cache)
		start = time.tick_now()
		for n in g.nodes {
			_, e := Gen_Evaluate(&g, n.id, 0, context.temp_allocator, &cache)
			testing.expectf(t, e == "", "evaluate %d: %s", n.id, e)
		}
		fmt.printf("[bench] levelgen %dx%d editor previews, cold: %.2f ms\n", size, size, ms(start))
		free_all(context.temp_allocator)
		Gen_SetParam(Gen_FindNode(&g, 9), "iterations", 3)
		start = time.tick_now()
		for n in g.nodes do _, _ = Gen_Evaluate(&g, n.id, 0, context.temp_allocator, &cache)
		fmt.printf("[bench] levelgen %dx%d editor previews, one node changed: %.2f ms\n", size, size, ms(start))
		free_all(context.temp_allocator)

		// Each node alone (its inputs from the cache).
		for &n in g.nodes {
			if n.kind == .Tile_Output || n.kind == .Entity_Output do continue
			Gen_CacheForget(&cache, n.id)
			start = time.tick_now()
			_, _ = Gen_Evaluate(&g, n.id, 0, context.temp_allocator, &cache)
			label := GEN_KINDS[n.kind].name
			if n.kind == .Noise do label = fmt.tprintf("noise %s", GEN_NOISE_TYPES[clamp(int(Gen_Param(&n, "type")), 0, len(GEN_NOISE_TYPES) - 1)])
			fmt.printf("[bench] levelgen %dx%d   %-16s %.3f ms\n", size, size, label, ms(start))
			free_all(context.temp_allocator)
		}
	}
}
