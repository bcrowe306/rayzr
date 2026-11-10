package engine

import "core:encoding/json"
import "core:strings"
import "core:testing"

// ============================================================================
// Scene merge by node uid (#293): scene_merge.odin
// ============================================================================

@(private = "file")
MERGE_BASE :: `{"name": "m", "root": {"type": "Node", "name": "root", "uid": "r", "children": [
 {"type": "TextNode", "name": "Title", "uid": "t", "position": [0, 0], "properties": {"text": "hi", "fontSize": 20}},
 {"type": "Node", "name": "Box", "uid": "b", "children": [{"type": "Node", "name": "Inner", "uid": "i"}]},
 {"type": "Node", "name": "Spare", "uid": "s"}]}}`

@(private = "file")
merge_node :: proc(text: string, uid: string) -> json.Object {
	v, _ := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	find :: proc(v: json.Value, uid: string) -> json.Object {
		o, ok := v.(json.Object)
		if !ok do return nil
		if u, has := o["uid"].(json.String); has && string(u) == uid do return o
		if r, has := o["root"]; has do if f := find(r, uid); f != nil do return f
		if kids, has := o["children"].(json.Array); has do for k in kids do if f := find(k, uid); f != nil do return f
		return nil
	}
	return find(v, uid)
}

@(private = "file")
merge_child_names :: proc(text, uid: string) -> string {
	n := merge_node(text, uid)
	names := make([dynamic]string, context.temp_allocator)
	if kids, has := n["children"].(json.Array); has do for k in kids do append(&names, string(k.(json.Object)["name"].(json.String)))
	return strings.join(names[:], ",", context.temp_allocator)
}

@(private = "file")
merge3 :: proc(t: ^testing.T, ours, theirs: string) -> Merge_Result {
	res, ok, why := Scene_Merge(transmute([]u8)string(MERGE_BASE), transmute([]u8)ours, transmute([]u8)theirs)
	testing.expectf(t, ok, "merged (%s)", why)
	return res
}

@(private = "file")
edit :: proc(text, a, b: string) -> string {
	out, n := strings.replace(text, a, b, 1, context.temp_allocator)
	assert(n, "the edit applies")
	return out
}

@(test)
test_scene_merge_different_fields_merge_cleanly :: proc(t: ^testing.T) {
	// Ours: the text; theirs: the size and the position - all three kept.
	ours := edit(MERGE_BASE, `"text": "hi"`, `"text": "hello"`)
	theirs := edit(edit(MERGE_BASE, `"fontSize": 20`, `"fontSize": 32`), `"position": [0, 0]`, `"position": [5, 6]`)
	res := merge3(t, ours, theirs)
	testing.expect_value(t, len(res.conflicts), 0)
	title := merge_node(res.text, "t")
	props := title["properties"].(json.Object)
	testing.expect_value(t, string(props["text"].(json.String)), "hello")
	testing.expect_value(t, merge_compact(props["fontSize"]), "32")
	testing.expect_value(t, merge_compact(title["position"]), "[5, 6]")
}

@(test)
test_scene_merge_same_field_conflicts_and_resolves :: proc(t: ^testing.T) {
	ours := edit(MERGE_BASE, `"text": "hi"`, `"text": "ours"`)
	theirs := edit(MERGE_BASE, `"text": "hi"`, `"text": "theirs"`)
	res := merge3(t, ours, theirs)
	testing.expect_value(t, len(res.conflicts), 1)
	c := res.conflicts[0]
	testing.expect_value(t, c.kind, Merge_Conflict_Kind.Value)
	testing.expect_value(t, c.name, "Title")
	testing.expect_value(t, c.field, "properties/text")
	testing.expect_value(t, c.ours, `"ours"`)
	testing.expect_value(t, c.theirs, `"theirs"`)
	testing.expect_value(t, c.base, `"hi"`)
	// Ours is in the file; picking theirs (through the sidecar) puts it in.
	testing.expect_value(t, string(merge_node(res.text, "t")["properties"].(json.Object)["text"].(json.String)), "ours")
	side := Merge_ConflictsJSON("scenes/m.scene.json", res.conflicts[:], context.temp_allocator)
	file, back, ok := Merge_ReadConflicts(transmute([]u8)side, context.temp_allocator)
	testing.expect(t, ok && file == "scenes/m.scene.json" && len(back) == 1 && back[0].theirs == `"theirs"`, "the sidecar round-trips")
	resolved, rok := Merge_Resolve(transmute([]u8)res.text, back[:], []Merge_Pick{.Theirs}, context.temp_allocator)
	testing.expect(t, rok, "resolved")
	testing.expect_value(t, string(merge_node(resolved, "t")["properties"].(json.Object)["text"].(json.String)), "theirs")
	based, _ := Merge_Resolve(transmute([]u8)res.text, back[:], []Merge_Pick{.Base}, context.temp_allocator)
	testing.expect_value(t, string(merge_node(based, "t")["properties"].(json.Object)["text"].(json.String)), "hi")
}

@(test)
test_scene_merge_move_and_edit :: proc(t: ^testing.T) {
	// Ours moves Title into Box; theirs renames it: moved and renamed.
	moved := `{"name": "m", "root": {"type": "Node", "name": "root", "uid": "r", "children": [
 {"type": "Node", "name": "Box", "uid": "b", "children": [{"type": "Node", "name": "Inner", "uid": "i"},
  {"type": "TextNode", "name": "Title", "uid": "t", "position": [0, 0], "properties": {"text": "hi", "fontSize": 20}}]},
 {"type": "Node", "name": "Spare", "uid": "s"}]}}`
	theirs := edit(MERGE_BASE, `"name": "Title"`, `"name": "Heading"`)
	res := merge3(t, moved, theirs)
	testing.expect_value(t, len(res.conflicts), 0)
	testing.expect_value(t, merge_child_names(res.text, "r"), "Box,Spare")
	testing.expect_value(t, merge_child_names(res.text, "b"), "Inner,Heading")
}

@(test)
test_scene_merge_adds_and_deletes :: proc(t: ^testing.T) {
	// Ours adds A after Title; theirs adds B after Box and deletes Spare.
	ours := edit(MERGE_BASE, `{"type": "Node", "name": "Box"`, `{"type": "Node", "name": "A", "uid": "a"},
 {"type": "Node", "name": "Box"`)
	theirs := edit(MERGE_BASE, `,
 {"type": "Node", "name": "Spare", "uid": "s"}`, `,
 {"type": "Node", "name": "B", "uid": "bb"}`)
	res := merge3(t, ours, theirs)
	testing.expect_value(t, len(res.conflicts), 0)
	testing.expect_value(t, merge_child_names(res.text, "r"), "Title,A,Box,B")
}

@(test)
test_scene_merge_delete_vs_change :: proc(t: ^testing.T) {
	// Theirs deletes Spare; ours renames it: a conflict, the node kept.
	ours := edit(MERGE_BASE, `"name": "Spare"`, `"name": "Kept"`)
	theirs := edit(MERGE_BASE, `,
 {"type": "Node", "name": "Spare", "uid": "s"}`, "")
	res := merge3(t, ours, theirs)
	testing.expect_value(t, len(res.conflicts), 1)
	testing.expect_value(t, res.conflicts[0].kind, Merge_Conflict_Kind.DeletedChanged)
	testing.expect(t, !res.conflicts[0].oursDeleted, "theirs deleted it")
	testing.expect_value(t, merge_child_names(res.text, "r"), "Title,Box,Kept")
	// Picking theirs: deleted.
	gone, _ := Merge_Resolve(transmute([]u8)res.text, res.conflicts[:], []Merge_Pick{.Theirs}, context.temp_allocator)
	testing.expect_value(t, merge_child_names(gone, "r"), "Title,Box")
	// Deleted on one side, unchanged on the other: just gone.
	clean := merge3(t, MERGE_BASE, theirs)
	testing.expect_value(t, len(clean.conflicts), 0)
	testing.expect_value(t, merge_child_names(clean.text, "r"), "Title,Box")
}

@(test)
test_scene_merge_needs_uids :: proc(t: ^testing.T) {
	noUid := `{"name": "m", "root": {"type": "Node", "name": "root", "children": [{"type": "Node", "name": "X"}]}}`
	_, ok, why := Scene_Merge(transmute([]u8)string(noUid), transmute([]u8)string(noUid), transmute([]u8)string(noUid))
	testing.expect(t, !ok, "not mergeable by uid")
	testing.expect(t, strings.contains(why, "uid"), "says why")
}

@(test)
test_scene_diff_by_node :: proc(t: ^testing.T) {
	// Title's text changed, Inner moved out of Box, Spare removed, New added.
	after := `{"name": "m2", "root": {"type": "Node", "name": "root", "uid": "r", "children": [
 {"type": "TextNode", "name": "Title", "uid": "t", "position": [0, 0], "properties": {"text": "bye", "fontSize": 20}},
 {"type": "Node", "name": "Box", "uid": "b"},
 {"type": "Node", "name": "Inner", "uid": "i"},
 {"type": "Node", "name": "New", "uid": "n"}]}}`
	changes, ok := Scene_Diff(transmute([]u8)string(MERGE_BASE), transmute([]u8)after)
	testing.expect(t, ok, "diffed")
	got := make(map[string]Scene_Change, allocator = context.temp_allocator)
	for c in changes do got[c.name] = c
	testing.expect_value(t, len(changes), 5) // (scene), Title, Inner, New, Spare
	testing.expect_value(t, got["(scene)"].fields[0].field, "name")
	testing.expect_value(t, got["Title"].kind, Scene_Change_Kind.Changed)
	testing.expect_value(t, got["Title"].fields[0].field, "properties/text")
	testing.expect_value(t, got["Title"].fields[0].after, `"bye"`)
	testing.expect_value(t, got["Inner"].kind, Scene_Change_Kind.Moved)
	testing.expect_value(t, got["New"].kind, Scene_Change_Kind.Added)
	testing.expect_value(t, got["Spare"].kind, Scene_Change_Kind.Removed)
	// A new file: everything added.
	added, aok := Scene_Diff(nil, transmute([]u8)after)
	testing.expectf(t, aok && len(added) >= 5, "a new file: %v %d", aok, len(added))
}
