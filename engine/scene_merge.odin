package engine

import "core:encoding/json"
import "core:fmt"
import "core:slice"
import "core:strings"

// ============================================================================
// Scene merge (#293): a three-way merge of scene / component files by node
// uid (#328) - the git merge driver (`editor --merge-scene %O %A %B %P`,
// editor/scene_merge_cli.odin) and the editor's conflict window use it.
//
// Nodes are matched by uid, not by their place in the file, so one person
// moving or renaming a node while another edits it merges cleanly:
//   - a node's fields merge one by one, objects ("properties", "script", ...)
//     a level deeper: a field only one side changed takes that change; both
//     changed it differently: a conflict (ours kept, both recorded);
//   - nodes added on either side are kept; one deleted on one side and left
//     as it was on the other goes; deleted on one side and changed on the
//     other: a conflict (kept, with the change);
//   - a node moved to another parent on one side moves; moved to two
//     different parents: a conflict (ours);
//   - children keep our order, theirs' added (or moved-in) children placed
//     after the sibling they follow there;
//   - a component instance (a node with "component") merges as one value.
// Files with a node without a uid can't be merged this way (Scene_Merge
// says so: git's own text merge is the fallback).
// ============================================================================

Merge_Conflict_Kind :: enum {
	Value,          // a field both sides changed differently
	DeletedChanged, // deleted on one side, changed on the other (kept)
	Moved,          // moved to two different parents (ours)
}

Merge_Conflict :: struct {
	kind:   Merge_Conflict_Kind,
	uid:    string,
	name:   string, // the node's name (ours, else theirs)
	field:  string, // Value: the field's path in the node ("properties/text"); Moved: "parent"
	base:   string, // compact JSON of each side's value ("" = not there)
	ours:   string,
	theirs: string,
	oursDeleted: bool, // DeletedChanged: which side deleted it
}

Merge_Result :: struct {
	text:      string,           // the merged file (canonical when the caller formats it)
	value:     json.Value,
	conflicts: [dynamic]Merge_Conflict,
}

@(private = "file")
Merge_Node :: struct {
	obj:      json.Object, // the node's fields, without "children" (an instance: with them)
	parent:   string,
	children: [dynamic]string,
	found:    bool,
}

@(private = "file")
ROOT_UID :: "#root" // (a root without a uid)

// merge_flatten: every node of a file by uid. False when a node has none
// (the root may lack one).
@(private = "file")
merge_flatten :: proc(v: json.Value, parent: string, out: ^map[string]Merge_Node, isRoot := false) -> (uid: string, ok: bool) {
	o, isObj := v.(json.Object)
	if !isObj do return "", false
	u, hasUid := o["uid"].(json.String)
	uid = string(u) if hasUid && u != "" else (ROOT_UID if isRoot else "")
	if uid == "" || uid in out^ do return "", false
	n := Merge_Node{obj = make(json.Object, len(o), context.temp_allocator), parent = parent, found = true}
	_, isInstance := o["component"]
	for k, x in o do if k != "children" || isInstance do n.obj[k] = x
	n.children = make([dynamic]string, context.temp_allocator)
	if kids, has := o["children"].(json.Array); has && !isInstance {
		for c in kids {
			cu, cok := merge_flatten(c, uid, out)
			if !cok do return "", false
			append(&n.children, cu)
		}
	}
	out[uid] = n
	return uid, true
}

// merge_compact: a value as compact JSON with sorted keys ("" for none).
merge_compact :: proc(v: json.Value, present := true) -> string {
	if !present do return ""
	sb := strings.builder_make(context.temp_allocator)
	write :: proc(sb: ^strings.Builder, v: json.Value) {
		#partial switch x in v {
		case json.Object:
			keys := make([dynamic]string, context.temp_allocator)
			for k in x do append(&keys, k)
			slice.sort(keys[:])
			strings.write_byte(sb, '{')
			for k, i in keys {
				if i > 0 do strings.write_string(sb, ", ")
				fmt.sbprintf(sb, "%q: ", k)
				write(sb, x[k])
			}
			strings.write_byte(sb, '}')
		case json.Array:
			strings.write_byte(sb, '[')
			for e, i in x {
				if i > 0 do strings.write_string(sb, ", ")
				write(sb, e)
			}
			strings.write_byte(sb, ']')
		case:
			strings.write_string(sb, Json_Compact(v))
		}
	}
	write(&sb, v)
	return strings.to_string(sb)
}

@(private = "file")
merge_same :: proc(a: json.Value, ah: bool, b: json.Value, bh: bool) -> bool {
	if ah != bh do return false
	return !ah || json_equal(a, b)
}

// merge_fields: a three-way merge of two objects' fields (into `out`);
// objects in both a level deeper. Conflicts keep ours.
@(private = "file")
merge_fields :: proc(o, a, b: json.Object, path, uid, name: string, out: ^json.Object, conflicts: ^[dynamic]Merge_Conflict) {
	keys := make(map[string]bool, allocator = context.temp_allocator)
	for k in a do keys[k] = true
	for k in b do keys[k] = true
	for k in o do keys[k] = true
	sorted := make([dynamic]string, context.temp_allocator)
	for k in keys do append(&sorted, k)
	slice.sort(sorted[:])
	for k in sorted {
		vo, oh := o[k]
		va, ah := a[k]
		vb, bh := b[k]
		fieldPath := k if path == "" else fmt.tprintf("%s/%s", path, k)
		switch {
		case merge_same(va, ah, vb, bh): if ah do out[k] = va
		case merge_same(va, ah, vo, oh): if bh do out[k] = vb // (theirs changed it)
		case merge_same(vb, bh, vo, oh): if ah do out[k] = va // (ours changed it)
		case:
			ao, aIsObj := va.(json.Object)
			bo, bIsObj := vb.(json.Object)
			if ah && bh && aIsObj && bIsObj {
				oo, _ := vo.(json.Object)
				if oo == nil do oo = make(json.Object, 0, context.temp_allocator)
				sub := make(json.Object, len(ao), context.temp_allocator)
				merge_fields(oo, ao, bo, fieldPath, uid, name, &sub, conflicts)
				out[k] = sub
				continue
			}
			append(conflicts, Merge_Conflict{kind = .Value, uid = uid, name = name, field = fieldPath,
				base = merge_compact(vo, oh), ours = merge_compact(va, ah), theirs = merge_compact(vb, bh)})
			if ah do out[k] = va
		}
	}
}

@(private = "file")
merge_node_name :: proc(a, b: Merge_Node) -> string {
	if a.found do if s, ok := a.obj["name"].(json.String); ok do return string(s)
	if b.found do if s, ok := b.obj["name"].(json.String); ok do return string(s)
	return ""
}

// merge_order: the merged children of a node - ours' order, then theirs'
// extra ones after the sibling they follow there; `keep`: the uids whose
// merged parent is this node.
@(private = "file")
merge_order :: proc(ours, theirs: []string, keep: map[string]bool) -> [dynamic]string {
	out := make([dynamic]string, context.temp_allocator)
	for u in ours do if u in keep do append(&out, u)
	for u, i in theirs {
		if u not_in keep || slice.contains(out[:], u) do continue
		at := 0
		for j := i - 1; j >= 0; j -= 1 {
			if p, found := slice.linear_search(out[:], theirs[j]); found {
				at = p + 1
				break
			}
		}
		inject_at(&out, at, u)
	}
	// (Any left: parents changed by a merge of moves.)
	for u in keep do if !slice.contains(out[:], u) do append(&out, u)
	return out
}

// Scene_Merge: a three-way merge of a scene or component file's text
// (base, ours, theirs). ok = false: not mergeable by uid (why says what).
Scene_Merge :: proc(base, ours, theirs: []u8) -> (res: Merge_Result, ok: bool, why: string) {
	res.conflicts = make([dynamic]Merge_Conflict, context.temp_allocator)
	parse :: proc(data: []u8) -> (json.Object, bool) {
		v, err := json.parse(data, allocator = context.temp_allocator)
		if err != .None do return nil, false
		o, isObj := v.(json.Object)
		return o, isObj
	}
	fo, ook := parse(base)
	fa, aok := parse(ours)
	fb, bok := parse(theirs)
	if !ook || !aok || !bok do return res, false, "not valid JSON"
	// A scene keeps its nodes under "root"; a component file is its root node.
	isScene := "root" in fa || "root" in fb || "root" in fo
	rootOf :: proc(f: json.Object, isScene: bool) -> json.Value {return f["root"] if isScene else json.Value(f)}
	no := make(map[string]Merge_Node, allocator = context.temp_allocator)
	na := make(map[string]Merge_Node, allocator = context.temp_allocator)
	nb := make(map[string]Merge_Node, allocator = context.temp_allocator)
	ro, rok := merge_flatten(rootOf(fo, isScene), "", &no, true)
	ra, rak := merge_flatten(rootOf(fa, isScene), "", &na, true)
	rb, rbk := merge_flatten(rootOf(fb, isScene), "", &nb, true)
	if !rok || !rak || !rbk do return res, false, "a node without a uid (or a uid twice): open and save the file in the editor first"
	if ra != rb || ro != ra do return res, false, "the root node differs"

	// The nodes, field by field.
	uids := make(map[string]bool, allocator = context.temp_allocator)
	for u in na do uids[u] = true
	for u in nb do uids[u] = true
	for u in no do uids[u] = true
	sortedUids := make([dynamic]string, context.temp_allocator)
	for u in uids do append(&sortedUids, u)
	slice.sort(sortedUids[:])
	merged := make(map[string]Merge_Node, allocator = context.temp_allocator)
	empty := make(json.Object, 0, context.temp_allocator)
	for u in sortedUids {
		o, a, b := no[u], na[u], nb[u]
		name := merge_node_name(a, b)
		m := Merge_Node{found = true}
		switch {
		case a.found && b.found:
			m.obj = make(json.Object, len(a.obj), context.temp_allocator)
			merge_fields(o.obj if o.found else empty, a.obj, b.obj, "", u, name, &m.obj, &res.conflicts)
			switch {
			case a.parent == b.parent || !o.found: m.parent = a.parent
			case a.parent == o.parent: m.parent = b.parent
			case b.parent == o.parent: m.parent = a.parent
			case:
				m.parent = a.parent
				append(&res.conflicts, Merge_Conflict{kind = .Moved, uid = u, name = name, field = "parent", base = o.parent, ours = a.parent, theirs = b.parent})
			}
		case a.found && !o.found: m = a // (added by us)
		case b.found && !o.found: m = b // (added by them)
		case a.found: // (deleted by them)
			if merge_compact(a.obj) == merge_compact(o.obj) && a.parent == o.parent do continue
			m = a
			append(&res.conflicts, Merge_Conflict{kind = .DeletedChanged, uid = u, name = name, base = merge_compact(o.obj), ours = merge_compact(a.obj), oursDeleted = false})
		case b.found: // (deleted by us)
			if merge_compact(b.obj) == merge_compact(o.obj) && b.parent == o.parent do continue
			m = b
			append(&res.conflicts, Merge_Conflict{kind = .DeletedChanged, uid = u, name = name, base = merge_compact(o.obj), theirs = merge_compact(b.obj), oursDeleted = true})
		case: continue // (deleted by both)
		}
		merged[u] = m
	}
	// A node whose parent went: under the root.
	for u, &m in merged do if u != ra && m.parent not_in merged do m.parent = ra

	// The tree back: each node's children in order.
	byParent := make(map[string]map[string]bool, allocator = context.temp_allocator)
	for u, m in merged {
		if u == ra do continue
		set, has := byParent[m.parent]
		if !has do set = make(map[string]bool, allocator = context.temp_allocator)
		set[u] = true
		byParent[m.parent] = set
	}
	build :: proc(u: string, merged: map[string]Merge_Node, na, nb: map[string]Merge_Node, byParent: map[string]map[string]bool) -> json.Value {
		m := merged[u]
		o := make(json.Object, len(m.obj) + 1, context.temp_allocator)
		for k, v in m.obj do o[k] = v
		if _, isInstance := m.obj["component"]; isInstance do return o
		keep := byParent[u]
		if len(keep) > 0 {
			order := merge_order(na[u].children[:] if u in na else nil, nb[u].children[:] if u in nb else nil, keep)
			kids := make(json.Array, 0, len(order), context.temp_allocator)
			for c in order do append(&kids, build(c, merged, na, nb, byParent))
			o["children"] = kids
		}
		return o
	}
	root := build(ra, merged, na, nb, byParent)

	// The file's own fields (a scene's name, background, ...).
	if isScene {
		top := make(json.Object, len(fa), context.temp_allocator)
		strip :: proc(f: json.Object) -> json.Object {
			c := make(json.Object, len(f), context.temp_allocator)
			for k, v in f do if k != "root" do c[k] = v
			return c
		}
		merge_fields(strip(fo), strip(fa), strip(fb), "", "", "(scene)", &top, &res.conflicts)
		top["root"] = root
		res.value = top
	} else {
		res.value = root
	}
	text, merr := json.marshal(res.value, {pretty = true, sort_maps_by_key = true}, context.temp_allocator)
	if merr != nil do return res, false, "could not be written"
	res.text = string(text)
	return res, true, ""
}

// Merge_ConflictsJSON: the conflicts as the sidecar file the editor's
// conflict window reads (<file>.merge.json).
Merge_ConflictsJSON :: proc(file: string, conflicts: []Merge_Conflict, allocator := context.allocator) -> string {
	w := Json_Writer{sb = strings.builder_make(allocator)}
	strings.write_byte(&w.sb, '{')
	w.indent = 1
	first := true
	Json_Key(&w, "file", &first)
	Json_String(&w, file)
	Json_Key(&w, "conflicts", &first)
	strings.write_byte(&w.sb, '[')
	w.indent += 1
	for c, i in conflicts {
		if i > 0 do strings.write_byte(&w.sb, ',')
		Json_NewLine(&w)
		strings.write_byte(&w.sb, '{')
		w.indent += 1
		f := true
		Json_Key(&w, "kind", &f); Json_String(&w, fmt.tprint(c.kind))
		Json_Key(&w, "uid", &f); Json_String(&w, c.uid)
		Json_Key(&w, "name", &f); Json_String(&w, c.name)
		Json_Key(&w, "field", &f); Json_String(&w, c.field)
		Json_Key(&w, "base", &f); Json_String(&w, c.base)
		Json_Key(&w, "ours", &f); Json_String(&w, c.ours)
		Json_Key(&w, "theirs", &f); Json_String(&w, c.theirs)
		if c.kind == .DeletedChanged {Json_Key(&w, "ours_deleted", &f); strings.write_string(&w.sb, "true" if c.oursDeleted else "false")}
		w.indent -= 1
		Json_NewLine(&w)
		strings.write_byte(&w.sb, '}')
	}
	w.indent -= 1
	if len(conflicts) > 0 do Json_NewLine(&w)
	strings.write_byte(&w.sb, ']')
	w.indent = 0
	Json_NewLine(&w)
	strings.write_string(&w.sb, "}\n")
	return strings.to_string(w.sb)
}

// Merge_ReadConflicts: a sidecar file's conflicts.
Merge_ReadConflicts :: proc(data: []u8, allocator := context.allocator) -> (file: string, conflicts: [dynamic]Merge_Conflict, ok: bool) {
	v, err := json.parse(data, allocator = context.temp_allocator)
	if err != .None do return
	o, isObj := v.(json.Object)
	if !isObj do return
	file = strings.clone(sj_string(o, "file"), allocator)
	conflicts = make([dynamic]Merge_Conflict, allocator)
	arr, _ := o["conflicts"].(json.Array)
	for x in arr {
		c, cok := x.(json.Object)
		if !cok do continue
		k: Merge_Conflict
		switch sj_string(c, "kind") {
		case "DeletedChanged": k.kind = .DeletedChanged
		case "Moved": k.kind = .Moved
		case: k.kind = .Value
		}
		k.uid = strings.clone(sj_string(c, "uid"), allocator)
		k.name = strings.clone(sj_string(c, "name"), allocator)
		k.field = strings.clone(sj_string(c, "field"), allocator)
		k.base = strings.clone(sj_string(c, "base"), allocator)
		k.ours = strings.clone(sj_string(c, "ours"), allocator)
		k.theirs = strings.clone(sj_string(c, "theirs"), allocator)
		if b, isBool := c["ours_deleted"].(json.Boolean); isBool do k.oursDeleted = bool(b)
		append(&conflicts, k)
	}
	return file, conflicts, true
}

Merge_Pick :: enum {Ours, Theirs, Base}

// Merge_Resolve applies picks to a merged file (which holds ours for every
// conflict): a Value conflict's field set to the picked side's value (or
// removed when that side had none); DeletedChanged: the node deleted, or
// kept as the side that changed it; Moved: the node under the picked parent.
Merge_Resolve :: proc(text: []u8, conflicts: []Merge_Conflict, picks: []Merge_Pick, allocator := context.allocator) -> (out: string, ok: bool) {
	v, err := json.parse(text, allocator = context.temp_allocator)
	if err != .None do return "", false
	top, isObj := v.(json.Object)
	if !isObj do return "", false
	isScene := "root" in top
	for c, i in conflicts {
		pick := picks[i] if i < len(picks) else .Ours
		if c.uid == "" {
			// (A scene's own field.)
			if c.kind == .Value do merge_set_field(&top, c.field, merge_pick_value(c, pick))
			continue
		}
		root := top["root"] if isScene else json.Value(top)
		switch c.kind {
		case .Value:
			root = merge_edit_node(root, c.uid, proc(n: ^json.Object, c: Merge_Conflict, pick: Merge_Pick) {merge_set_field(n, c.field, merge_pick_value(c, pick))}, c, pick)
		case .DeletedChanged:
			// Deleted by the side picked (or by base: as it was = gone).
			deleted := (pick == .Ours && c.oursDeleted) || (pick == .Theirs && !c.oursDeleted) || pick == .Base
			if deleted do root = merge_remove_node(root, c.uid)
		case .Moved:
			to := c.ours if pick == .Ours else (c.theirs if pick == .Theirs else c.base)
			root = merge_move_node(root, c.uid, to)
		}
		if isScene do top["root"] = root
		else if r, rok := root.(json.Object); rok do top = r
	}
	textOut, merr := json.marshal(json.Value(top), {pretty = true, sort_maps_by_key = true}, context.temp_allocator)
	if merr != nil do return "", false
	return strings.clone(string(textOut), allocator), true
}

// merge_pick_value: the picked side's value (present = false: it had none).
@(private = "file")
merge_pick_value :: proc(c: Merge_Conflict, pick: Merge_Pick) -> Maybe(json.Value) {
	s := c.ours if pick == .Ours else (c.theirs if pick == .Theirs else c.base)
	if s == "" do return nil
	v, err := json.parse(transmute([]u8)s, allocator = context.temp_allocator)
	if err != .None do return nil
	return v
}

// merge_set_field sets (or removes) a field by path ("properties/text").
@(private = "file")
merge_set_field :: proc(o: ^json.Object, path: string, value: Maybe(json.Value)) {
	parts := strings.split(path, "/", context.temp_allocator)
	set :: proc(o: ^json.Object, parts: []string, value: Maybe(json.Value)) {
		if len(parts) == 1 {
			if v, has := value.?; has do o[parts[0]] = v
			else do delete_key(o, parts[0])
			return
		}
		sub, isObj := o[parts[0]].(json.Object)
		if !isObj do sub = make(json.Object, 0, context.temp_allocator)
		set(&sub, parts[1:], value)
		o[parts[0]] = sub // (a map written to is a new value: stored back)
	}
	set(o, parts, value)
}

@(private = "file")
merge_edit_node :: proc(v: json.Value, uid: string, edit: proc(n: ^json.Object, c: Merge_Conflict, pick: Merge_Pick), c: Merge_Conflict, pick: Merge_Pick) -> json.Value {
	o, isObj := v.(json.Object)
	if !isObj do return v
	if u, has := o["uid"].(json.String); has && string(u) == uid {
		edit(&o, c, pick)
		return o
	}
	if kids, has := o["children"].(json.Array); has {
		for k, i in kids do kids[i] = merge_edit_node(k, uid, edit, c, pick)
		o["children"] = kids
	}
	return o
}

@(private = "file")
merge_take_node :: proc(v: json.Value, uid: string) -> (rest: json.Value, taken: json.Value, found: bool) {
	o, isObj := v.(json.Object)
	if !isObj do return v, nil, false
	if kids, has := o["children"].(json.Array); has {
		out := make(json.Array, 0, len(kids), context.temp_allocator)
		for k in kids {
			if ko, kok := k.(json.Object); kok {
				if u, hu := ko["uid"].(json.String); hu && string(u) == uid {
					taken, found = k, true
					continue
				}
			}
			r, t, f := merge_take_node(k, uid)
			if f do taken, found = t, true
			append(&out, r)
		}
		o["children"] = out
	}
	return o, taken, found
}

@(private = "file")
merge_remove_node :: proc(v: json.Value, uid: string) -> json.Value {
	rest, _, _ := merge_take_node(v, uid)
	return rest
}

@(private = "file")
merge_move_node :: proc(v: json.Value, uid, parent: string) -> json.Value {
	rest, node, found := merge_take_node(v, uid)
	if !found do return v
	add :: proc(v: json.Value, parent: string, node: json.Value, isRoot: bool) -> (json.Value, bool) {
		o, isObj := v.(json.Object)
		if !isObj do return v, false
		u, _ := o["uid"].(json.String)
		if string(u) == parent || (parent == ROOT_UID && isRoot) {
			kids, _ := o["children"].(json.Array)
			append(&kids, node)
			o["children"] = kids
			return o, true
		}
		if kids, has := o["children"].(json.Array); has {
			for k, i in kids {
				nk, done := add(k, parent, node, false)
				kids[i] = nk
				if done {
					o["children"] = kids
					return o, true
				}
			}
		}
		return o, false
	}
	out, done := add(rest, parent, node, true)
	if !done {
		out, _ = add(rest, ROOT_UID, node, true) // (the parent went: under the root)
	}
	return out
}

// --- diff (the Git panel shows a scene's changes by node) ---------------------

Scene_Change_Kind :: enum {Added, Removed, Changed, Moved}

Scene_Field_Change :: struct {
	field:         string, // "properties/text"
	before, after: string, // compact JSON ("" = not there)
}

Scene_Change :: struct {
	kind:   Scene_Change_Kind,
	uid:    string,
	name:   string,
	fields: [dynamic]Scene_Field_Change, // Changed (a move with changes: Moved + fields)
}

// Scene_Diff: what changed from one version of a scene / component file to
// another, node by node (by uid; the scene's own fields as "(scene)").
// ok = false: a node without a uid in either.
Scene_Diff :: proc(before, after: []u8) -> (changes: [dynamic]Scene_Change, ok: bool) {
	changes = make([dynamic]Scene_Change, context.temp_allocator)
	parse :: proc(data: []u8) -> (json.Object, bool) {
		if len(data) == 0 do return make(json.Object, 1, context.temp_allocator), true // (a new / deleted file)
		v, err := json.parse(data, allocator = context.temp_allocator)
		if err != .None do return nil, false
		o, isObj := v.(json.Object)
		return o, isObj
	}
	fa, aok := parse(before)
	fb, bok := parse(after)
	if !aok || !bok do return changes, false
	isScene := "root" in fa || "root" in fb
	na := make(map[string]Merge_Node, allocator = context.temp_allocator)
	nb := make(map[string]Merge_Node, allocator = context.temp_allocator)
	if len(fa) > 0 {
		if _, fok := merge_flatten(fa["root"] if isScene else json.Value(fa), "", &na, true); !fok do return changes, false
	}
	if len(fb) > 0 {
		if _, fok := merge_flatten(fb["root"] if isScene else json.Value(fb), "", &nb, true); !fok do return changes, false
	}
	fields :: proc(a, b: json.Object, path: string, out: ^[dynamic]Scene_Field_Change) {
		keys := make(map[string]bool, allocator = context.temp_allocator)
		for k in a do keys[k] = true
		for k in b do keys[k] = true
		sorted := make([dynamic]string, context.temp_allocator)
		for k in keys do if k != FORMAT_KEY do append(&sorted, k)
		slice.sort(sorted[:])
		for k in sorted {
			va, ah := a[k]
			vb, bh := b[k]
			if merge_same(va, ah, vb, bh) do continue
			p := k if path == "" else fmt.tprintf("%s/%s", path, k)
			ao, aIs := va.(json.Object)
			bo, bIs := vb.(json.Object)
			if ah && bh && aIs && bIs {
				fields(ao, bo, p, out)
				continue
			}
			append(out, Scene_Field_Change{field = p, before = merge_compact(va, ah), after = merge_compact(vb, bh)})
		}
	}
	name :: proc(n: Merge_Node) -> string {
		s, _ := n.obj["name"].(json.String)
		return string(s)
	}
	// The scene's own fields.
	if isScene {
		strip :: proc(f: json.Object) -> json.Object {
			c := make(json.Object, len(f), context.temp_allocator)
			for k, v in f do if k != "root" do c[k] = v
			return c
		}
		top := Scene_Change{kind = .Changed, name = "(scene)", fields = make([dynamic]Scene_Field_Change, context.temp_allocator)}
		fields(strip(fa), strip(fb), "", &top.fields)
		if len(top.fields) > 0 do append(&changes, top)
	}
	// The nodes, in the after file's order (removed ones after).
	order := make([dynamic]string, context.temp_allocator)
	walk :: proc(u: string, nodes: map[string]Merge_Node, out: ^[dynamic]string) {
		append(out, u)
		for c in nodes[u].children do walk(c, nodes, out)
	}
	if ROOT_UID in nb do walk(ROOT_UID, nb, &order)
	else do for u, n in nb do if n.parent == "" do walk(u, nb, &order)
	for u in na do if u not_in nb do append(&order, u)
	for u in order {
		a, inA := na[u]
		b, inB := nb[u]
		c := Scene_Change{uid = u, fields = make([dynamic]Scene_Field_Change, context.temp_allocator)}
		switch {
		case !inA:
			c.kind, c.name = .Added, name(b)
		case !inB:
			c.kind, c.name = .Removed, name(a)
		case:
			c.name = name(b)
			fields(a.obj, b.obj, "", &c.fields)
			if a.parent != b.parent {
				c.kind = .Moved
				pa, pb := na[a.parent], nb[b.parent]
				append(&c.fields, Scene_Field_Change{field = "parent", before = name(pa), after = name(pb)})
			} else if len(c.fields) > 0 {
				c.kind = .Changed
			} else do continue
		}
		append(&changes, c)
	}
	return changes, true
}
