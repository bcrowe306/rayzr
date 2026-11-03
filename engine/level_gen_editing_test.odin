package engine

import "core:strings"
import "core:testing"

// The Level Generator window's conveniences in the graph (#171): comment
// frames saved in the file, and nodes copied / pasted as text.

@(test)
test_level_gen_frames_round_trip :: proc(t: ^testing.T) {
	text := `{"size": [8, 8], "nodes": [
		{"id": 1, "type": "constant", "pos": [10, 20]}
	], "frames": [
		{"title": "Caves", "pos": [0, 0], "size": [320, 180], "color": [0.2, 0.4, 0.6, 1]},
		{"title": "", "pos": [400, 50], "size": [10, 10], "color": [1, 0, 0]}
	]}`
	g, err := Gen_GraphParse(transmute([]u8)text)
	defer Gen_GraphDestroy(&g)
	testing.expectf(t, err == "", "parse: %s", err)
	testing.expect_value(t, len(g.frames), 2)
	testing.expect_value(t, g.frames[0].title, "Caves")
	testing.expect_value(t, g.frames[0].size, [2]f32{320, 180})
	testing.expect_value(t, g.frames[0].color, [4]f32{0.2, 0.4, 0.6, 1})
	testing.expect_value(t, g.frames[1].size, [2]f32{40, 40}) // (a minimum size)
	testing.expect_value(t, g.frames[1].color.a, 1) // (rgb: opaque)

	saved := Gen_GraphSerialize(&g, context.temp_allocator)
	g2, err2 := Gen_GraphParse(transmute([]u8)saved)
	defer Gen_GraphDestroy(&g2)
	testing.expectf(t, err2 == "", "re-parse: %s", err2)
	testing.expect_value(t, len(g2.frames), 2)
	testing.expect_value(t, g2.frames[0].title, "Caves")
	testing.expect_value(t, g2.frames[0].pos, g.frames[0].pos)
	testing.expect_value(t, g2.frames[1].pos, [2]f32{400, 50})
	testing.expect_value(t, Gen_GraphSerialize(&g2, context.temp_allocator), saved)
}

@(test)
test_level_gen_no_frames_unchanged :: proc(t: ^testing.T) {
	// A file from before frames loads with none and saves without the key.
	g, err := Gen_GraphParse(transmute([]u8)string(GEN_TEMPLATE_CAVE))
	defer Gen_GraphDestroy(&g)
	testing.expectf(t, err == "", "parse: %s", err)
	testing.expect_value(t, len(g.frames), 0)
	saved := Gen_GraphSerialize(&g, context.temp_allocator)
	testing.expect(t, !strings.contains(saved, "frames"), "no frames key")
	testing.expect(t, strings.has_suffix(saved, "\n]}\n"), "ends as before")
}

@(test)
test_level_gen_copy_paste :: proc(t: ^testing.T) {
	g, err := Gen_GraphParse(transmute([]u8)string(GEN_TEMPLATE_CAVE))
	defer Gen_GraphDestroy(&g)
	testing.expectf(t, err == "", "parse: %s", err)
	// cellular (2) reads random fill (1); combine (4) reads 2 and border (3);
	// the tile output (5) reads 4. Copy 2, 4 and 5: 4 -> 5 and 2 -> 4 are
	// kept, the links from 1 and 3 dropped.
	clip := Gen_CopyNodes(&g, {2, 4, 5})
	defer delete(clip)
	testing.expect(t, Gen_IsNodesClip(clip), "marked as nodes")
	testing.expect(t, !strings.contains(clip, "random_fill"), "only the copied nodes")

	ids, perr := Gen_PasteNodes(&g, clip, {1000, 500})
	defer delete(ids)
	testing.expectf(t, perr == "", "paste: %s", perr)
	testing.expect_value(t, len(ids), 3)
	testing.expect_value(t, len(g.nodes), 8)
	testing.expect_value(t, ids[0], 6) // (new ids after the highest)
	cell, comb, out := Gen_FindNode(&g, ids[0]), Gen_FindNode(&g, ids[1]), Gen_FindNode(&g, ids[2])
	testing.expect_value(t, cell.kind, Gen_Kind.Cellular)
	testing.expect_value(t, cell.inputs[0], 0) // (from the random fill: dropped)
	testing.expect_value(t, comb.inputs, [2]int{ids[0], 0}) // (a kept, b dropped)
	testing.expect_value(t, out.inputs[0], ids[1])
	testing.expect_value(t, len(out.rules), 1) // (a tile output's rules come along)
	testing.expect_value(t, cell.pos, [2]f32{1000, 500}) // (the group's top-left at `at`)
	testing.expect_value(t, comb.pos, [2]f32{1220, 560})
	testing.expect_value(t, Gen_Param(cell, "iterations"), 5)
	// The originals are as they were.
	testing.expect_value(t, Gen_FindNode(&g, 4).inputs, [2]int{2, 3})

	// Into another generator.
	other, oerr := Gen_GraphParse(transmute([]u8)string(`{"size": [8, 8], "nodes": [{"id": 9, "type": "noise"}]}`))
	defer Gen_GraphDestroy(&other)
	testing.expectf(t, oerr == "", "parse: %s", oerr)
	ids2, perr2 := Gen_PasteNodes(&other, clip, {0, 0})
	defer delete(ids2)
	testing.expectf(t, perr2 == "", "paste: %s", perr2)
	testing.expect_value(t, len(other.nodes), 4)
	testing.expect_value(t, ids2[0], 10)
	testing.expect_value(t, Gen_FindNode(&other, ids2[2]).inputs[0], ids2[1])
	_, everr := Gen_Evaluate(&other, ids2[2], 0, context.temp_allocator)
	testing.expectf(t, everr == "", "the pasted nodes evaluate: %s", everr)

	// Other text isn't pasted.
	_, bad := Gen_PasteNodes(&other, "hello", {})
	testing.expect(t, bad != "", "plain text refused")
	testing.expect_value(t, len(other.nodes), 4)
	testing.expect_value(t, Gen_CopyNodes(&g, {77}, context.temp_allocator), "")
}

@(test)
test_level_gen_frame_edit :: proc(t: ^testing.T) {
	g, err := Gen_GraphParse(transmute([]u8)string(GEN_TEMPLATE_CAVE))
	defer Gen_GraphDestroy(&g)
	testing.expectf(t, err == "", "parse: %s", err)
	f := Gen_AddFrame(&g, {-20, -40}, {10, 500})
	testing.expect_value(t, f.title, "Comment")
	testing.expect_value(t, f.size, [2]f32{40, 500})
	Gen_SetFrameTitle(&g, f, "Walls")
	Gen_AddFrame(&g, {0, 0}, {100, 100}, "Second")
	testing.expect(t, Gen_RemoveFrame(&g, 0), "removed")
	testing.expect(t, !Gen_RemoveFrame(&g, 5), "no such frame")
	testing.expect_value(t, len(g.frames), 1)
	testing.expect_value(t, g.frames[0].title, "Second")
	testing.expect_value(t, len(g.nodes), 5) // (its nodes stay)
}
