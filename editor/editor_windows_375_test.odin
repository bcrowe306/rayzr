package editor

import "core:testing"
import rl "vendor:raylib"

// #375: the Atlas Region Editor keeps a region at least 1 x 1 inside the
// texture and snaps to the cell size; the Sprite Slicer's Shift+click range
// never starts from a cell outside the grid.
@(test)
test_atlas_clamp_region :: proc(t: ^testing.T) {
	testing.expect_value(t, Atlas_ClampRegion({10, 10, 20, 20}, 64, 32), rl.Rectangle{10, 10, 20, 20})
	// At the right / bottom edge (Width was 0): moved in, 1 x 1.
	testing.expect_value(t, Atlas_ClampRegion({64, 32, 5, 5}, 64, 32), rl.Rectangle{63, 31, 1, 1})
	testing.expect_value(t, Atlas_ClampRegion({60, 0, 0, 0}, 64, 32), rl.Rectangle{60, 0, 1, 1})
	testing.expect_value(t, Atlas_ClampRegion({-4, -4, 100, 100}, 64, 32), rl.Rectangle{0, 0, 64, 32})
	testing.expect_value(t, Atlas_ClampRegion({50, 0, 100, 8}, 64, 32), rl.Rectangle{50, 0, 14, 8})
	// The snap step: the cell size when set (30 px, not 100 / 3), else the split.
	testing.expect_value(t, Atlas_SnapStep(100, 3, 30), f32(30))
	testing.expect_value(t, Atlas_SnapStep(100, 4, 0), f32(25))
	testing.expect_value(t, Atlas_SnapStep(100, 0, 0), f32(100))
}

@(test)
test_slicer_range_cells :: proc(t: ^testing.T) {
	expect_cells :: proc(t: ^testing.T, got: []int, want: []int) {
		testing.expectf(t, len(got) == len(want), "cells %v, want %v", got, want)
		if len(got) == len(want) do for v, i in want do testing.expectf(t, got[i] == v, "cells %v, want %v", got, want)
	}
	expect_cells(t, Slicer_RangeCells(1, 4, 8), {2, 3, 4})
	expect_cells(t, Slicer_RangeCells(6, 3, 8), {5, 4, 3})
	expect_cells(t, Slicer_RangeCells(2, 2, 8), {2})
	// No last cell, or one from a bigger grid: just the clicked cell.
	expect_cells(t, Slicer_RangeCells(-1, 3, 8), {3})
	expect_cells(t, Slicer_RangeCells(12, 3, 8), {3})
	// A clicked cell outside the grid: nothing.
	expect_cells(t, Slicer_RangeCells(1, 9, 8), {})
	free_all(context.temp_allocator)
}
