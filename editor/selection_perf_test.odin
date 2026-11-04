package editor

import "core:fmt"
import "core:testing"
import "core:time"
import e "../engine"

// #331: a large selection (5000 nodes) - Editor_IsSelected through a set,
// Editor_SyncSelection against a set of the scene's nodes, the multi-edit
// Inspector's per-type offsets - give the same answers as before, faster.

@(private = "file")
make_scene :: proc(n: int) -> (^e.Scene, []^e.Node) {
	scene := new(e.Scene)
	e.InitializeScene(scene)
	nodes := make([]^e.Node, n)
	for i in 0 ..< n {
		s := e.CreateNode(scene.manager, e.TextureNode)
		s.name = "S"
		s.position = {f32(i), 0}
		scene->addNode(s)
		nodes[i] = s
	}
	e.ProcessNodeQueues(scene.manager, nil)
	return scene, nodes
}

@(private = "file")
free_scene :: proc(scene: ^e.Scene, nodes: []^e.Node) {
	e.TerminateScene(scene)
	free(scene)
	delete(nodes)
}

@test
test_selection_set_matches_the_selection :: proc(t: ^testing.T) {
	scene, nodes := make_scene(400)
	defer free_scene(scene, nodes)
	state: EditorState
	state.activeScene = scene
	defer {delete(state.selection); Editor_SelectionSetRelease()}
	for n, i in nodes do if i % 3 == 0 do append(&state.selection, n)
	frameTiming.frameIndex += 1
	for n, i in nodes do testing.expectf(t, Editor_IsSelected(&state, n) == (i % 3 == 0), "node %d", i)
	// Changed in the same frame: appended, removed, replaced in the middle.
	append(&state.selection, nodes[1])
	testing.expect(t, Editor_IsSelected(&state, nodes[1]), "an appended node is selected")
	ordered_remove(&state.selection, 0)
	testing.expect(t, !Editor_IsSelected(&state, nodes[0]), "a removed node isn't")
	frameTiming.frameIndex += 1 // (a replacement keeping the length and ends: seen the next frame at the latest)
	state.selection[len(state.selection) / 2 + 1] = nodes[2]
	frameTiming.frameIndex += 1
	testing.expect(t, Editor_IsSelected(&state, nodes[2]), "a replaced entry is selected")
	clear(&state.selection)
	testing.expect(t, !Editor_IsSelected(&state, nodes[3]), "nothing selected")
}

@test
test_selection_sync_large :: proc(t: ^testing.T) {
	scene, nodes := make_scene(200)
	defer free_scene(scene, nodes)
	state: EditorState
	state.activeScene = scene
	defer {delete(state.selection); Editor_SelectionSetRelease()}
	for n in nodes do append(&state.selection, n)
	stranger := new(e.Node) // (not in the scene)
	defer free(stranger)
	append(&state.selection, stranger)
	state.selectedNode = nodes[10]
	Editor_SyncSelection(&state)
	testing.expect_value(t, len(state.selection), 200)
	testing.expect(t, !Editor_IsSelected(&state, stranger), "a node outside the scene is dropped")
}

@test
test_multi_others_by_type_offset :: proc(t: ^testing.T) {
	scene, nodes := make_scene(50)
	defer free_scene(scene, nodes)
	other := e.CreateNode(scene.manager, e.TextNode) // (another type: its own lookup)
	scene->addNode(other)
	e.ProcessNodeQueues(scene.manager, nil)
	state: EditorState
	state.activeScene = scene
	defer {delete(state.selection); Editor_SelectionSetRelease()}
	for n in nodes do append(&state.selection, n)
	append(&state.selection, other)
	state.selectedNode = nodes[0]
	frameTiming.frameIndex += 1
	for p in e.Node_CollectProperties(nodes[0]) {
		got := multi_others(&state, nodes[0], p)
		want := 0
		for n in state.selection[1:] {
			q, ok := e.Node_FindProperty(n, p.name)
			if !ok || q.type.id != p.type.id do continue
			found := false
			for g in got do if g.node == n {
				found = true
				testing.expectf(t, g.prop.ptr == q.ptr, "%s: the same field of %p", p.name, n)
			}
			testing.expectf(t, found, "%s: %p is among the others", p.name, n)
			want += 1
		}
		testing.expectf(t, len(got) == want, "%s: %d others, want %d", p.name, len(got), want)
	}
	free_all(context.temp_allocator)
}

// The cost of a frame's Editor_IsSelected over every node with all 5000
// selected: a scan of the selection per node (before) and the set (now).
@test
bench_selection_5000 :: proc(t: ^testing.T) {
	scene, nodes := make_scene(5000)
	defer free_scene(scene, nodes)
	state: EditorState
	state.activeScene = scene
	defer {delete(state.selection); Editor_SelectionSetRelease()}
	for n in nodes do append(&state.selection, n)
	frameTiming.frameIndex += 1
	start := time.tick_now()
	hits := 0
	for n in nodes do for s in state.selection do if s == n {hits += 1; break}
	scan := time.duration_milliseconds(time.tick_since(start))
	start = time.tick_now()
	for n in nodes do if Editor_IsSelected(&state, n) do hits += 1
	set := time.duration_milliseconds(time.tick_since(start))
	start = time.tick_now()
	Editor_SyncSelection(&state)
	sync := time.duration_milliseconds(time.tick_since(start))
	fmt.printfln("[bench] 5000 selected: IsSelected over the scene %.3f ms (a scan: %.3f ms) | SyncSelection %.3f ms", set, scan, sync)
	testing.expect_value(t, hits, 10000)
	testing.expect(t, set < scan, "the set is faster than a scan")
	free_all(context.temp_allocator)
}
