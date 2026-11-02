package engine

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:slice"
import "core:strings"
import "core:time"
import os "osx"

// ============================================================================
// Per-node overrides for linked component (prefab) instances.
//
// An instance is saved as its link plus what differs from the component
// file, for the root *and every child*:
//
//   {"name": "Ship2", "position": [..], "component": "components/ship.component.json",
//    "overrides": {".":        {"script": {"properties": {"speed": 300}}},
//                  "k3j9x0ab": {"properties": {"color": [255, 0, 0, 255]}},
//                  "k3j9x0ab/p0q9zz11": {"visible": false}}}
//
// Every node in a component file has a "uid" (8 base-36 characters, unique
// in the file, given when the file is written: Component_InstanceJSON /
// Component_FileJSON). Keys are child paths from the instance root ("." =
// the root), one segment per node: its uid, or its name for nodes without
// one (files written before uids; they get uids when next written). A
// segment matches a child by uid first, then by name, so old name-based
// scenes keep loading and switch to uids when saved. Renaming a node in the
// file or giving siblings the same name keeps each override on its node.
// On load the overrides are merged into the component's JSON before the
// nodes are built, so a changed component file still flows into every
// instance except for the values the instance overrides. "properties" and
// a script's "properties" merge key by key; other keys replace the value;
// null removes a key. The structure (which children exist) always comes
// from the component file.
// ============================================================================

// Set while serializing an instance in full (to diff it against its file).
@(private)
serializeFullInstance: ^Node
// ...with the instances nested in it in full as well (their link and own
// overrides too, for nodes added to an instance: to_link_form).
@(private)
serializeExpandNested: bool
// The uid written for this node instead of its own: the root of a component
// file being written (Component_InstanceJSON).
@(private = "file")
serializeRootUidNode: ^Node
@(private = "file")
serializeRootUid: string

// node_written_uid: the "uid" a node is saved with ("" = none).
@(private)
node_written_uid :: proc(node: ^Node) -> string {
	if node == serializeRootUidNode && serializeRootUid != "" do return serializeRootUid
	return node.uid
}

// Root keys an instance stores directly (not as overrides).
@(private = "file")
ROOT_DIRECT_KEYS :: []string{"type", "name", "uid", "position", "scale", "rotation", "enabled", "visible", "layer", "component", "overrides", "children", "connections"}

@(private = "file")
contains_str :: proc(list: []string, s: string) -> bool {
	for x in list do if x == s do return true
	return false
}

// json_equal compares two JSON values (numbers with a small tolerance).
json_equal :: proc(a, b: json.Value) -> bool {
	num :: proc(v: json.Value) -> (f64, bool) {
		#partial switch x in v {
		case json.Integer: return f64(x), true
		case json.Float:   return f64(x), true
		}
		return 0, false
	}
	if na, oka := num(a); oka {
		nb, okb := num(b)
		return okb && math.abs(na - nb) < 1e-4
	}
	switch x in a {
	case json.Null:
		_, ok := b.(json.Null)
		return ok || b == nil
	case json.Integer, json.Float:
		return false
	case json.Boolean:
		y, ok := b.(json.Boolean)
		return ok && x == y
	case json.String:
		y, ok := b.(json.String)
		return ok && x == y
	case json.Array:
		y, ok := b.(json.Array)
		if !ok || len(x) != len(y) do return false
		for i in 0 ..< len(x) do if !json_equal(x[i], y[i]) do return false
		return true
	case json.Object:
		y, ok := b.(json.Object)
		if !ok || len(x) != len(y) do return false
		for k, v in x {
			w, has := y[k]
			if !has || !json_equal(v, w) do return false
		}
		return true
	}
	return b == nil
}

// Json_WriteValue writes a JSON value with sorted object keys (stable
// output: scene "modified" checks compare serialized text).
Json_WriteValue :: proc(w: ^Json_Writer, v: json.Value) {
	json_write_value(w, v, false)
}

// json_write_value: Json_WriteValue; `noMarkers` writes the expansion
// markers of nested instances (COMPONENT_EXPANDED) as `true`, without the
// nested base text they carry while an instance is built.
@(private = "file")
json_write_value :: proc(w: ^Json_Writer, v: json.Value, noMarkers: bool) {
	switch x in v {
	case json.Null:    strings.write_string(&w.sb, "null")
	case json.Integer: fmt.sbprintf(&w.sb, "%d", x)
	case json.Float:   Json_Float(w, f32(x))
	case json.Boolean: strings.write_string(&w.sb, "true" if x else "false")
	case json.String:  Json_String(w, x)
	case json.Array:
		strings.write_byte(&w.sb, '[')
		for item, i in x {
			if i > 0 do strings.write_string(&w.sb, ", ")
			json_write_value(w, item, noMarkers)
		}
		strings.write_byte(&w.sb, ']')
	case json.Object:
		keys := make([dynamic]string, context.temp_allocator)
		for k in x do append(&keys, k)
		slice.sort(keys[:])
		strings.write_byte(&w.sb, '{')
		for k, i in keys {
			if i > 0 do strings.write_string(&w.sb, ", ")
			Json_String(w, k)
			strings.write_string(&w.sb, ": ")
			if noMarkers && k == COMPONENT_EXPANDED {
				strings.write_string(&w.sb, "true")
			} else {
				json_write_value(w, x[k], noMarkers)
			}
		}
		strings.write_byte(&w.sb, '}')
	case:
		strings.write_string(&w.sb, "null")
	}
}

@(private = "file")
diff_keywise :: proc(base, inst: json.Object) -> (json.Object, bool) {
	out := make(json.Object, 0, context.temp_allocator)
	for k, v in inst {
		bv, has := base[k]
		if !has || !json_equal(bv, v) do out[k] = v
	}
	for k in base {
		if _, has := inst[k]; !has do out[k] = json.Null{}
	}
	return out, len(out) > 0
}

// diff_node collects what `inst` changes relative to `base` (one node).
@(private)
diff_node :: proc(base, inst: json.Object, isRoot: bool) -> (json.Object, bool) {
	out := make(json.Object, 0, context.temp_allocator)
	// A nested instance expanded in the base: its nodes are diffed one by one
	// (paths cross the link), not its link or "overrides" (#79). One that
	// couldn't be expanded (file missing) keeps "overrides" as a whole.
	_, expanded := base[COMPONENT_EXPANDED]
	skip :: proc(k: string, expanded: bool) -> bool {
		return k == "children" || k == "type" || k == "uid" || k == "component" || strings.has_prefix(k, "$") || (expanded && k == "overrides")
	}
	for k, v in inst {
		if skip(k, expanded) do continue
		if isRoot && contains_str(ROOT_DIRECT_KEYS, k) do continue
		if !isRoot && k == "name" do continue
		bv, has := base[k]
		if !has {
			out[k] = v
			continue
		}
		if json_equal(bv, v) do continue
		bo, bIsObj := bv.(json.Object)
		io, iIsObj := v.(json.Object)
		switch {
		case k == "properties" && bIsObj && iIsObj:
			if d, changed := diff_keywise(bo, io); changed do out[k] = d
		case k == "script" && bIsObj && iIsObj && json_equal(bo["path"], io["path"]):
			bp, _ := bo["properties"].(json.Object)
			ip, _ := io["properties"].(json.Object)
			if bp == nil do bp = make(json.Object, 0, context.temp_allocator)
			if ip == nil do ip = make(json.Object, 0, context.temp_allocator)
			if d, changed := diff_keywise(bp, ip); changed {
				s := make(json.Object, 0, context.temp_allocator)
				s["properties"] = d
				out[k] = s
			}
		case:
			out[k] = v
		}
	}
	for k in base {
		if skip(k, expanded) || (isRoot && contains_str(ROOT_DIRECT_KEYS, k)) || (!isRoot && k == "name") do continue
		if _, has := inst[k]; !has do out[k] = json.Null{}
	}
	return out, len(out) > 0
}

// node_segment: a node's path segment in override keys (its uid, else its name).
@(private = "file")
node_segment :: proc(obj: json.Object) -> string {
	if u, _ := obj["uid"].(json.String); u != "" do return string(u)
	n, _ := obj["name"].(json.String)
	return string(n)
}

@(private = "file")
join_path :: proc(parent, segment: string) -> string {
	return segment if parent == "." else fmt.tprintf("%s/%s", parent, segment)
}

// child_index: the child an override segment refers to - by uid, else by
// name (-1: none).
@(private = "file")
child_index :: proc(kids: json.Array, segment: string) -> int {
	for c, i in kids {
		co, isObj := c.(json.Object)
		if !isObj do continue
		if u, _ := co["uid"].(json.String); u != "" && string(u) == segment do return i
	}
	for c, i in kids {
		co, isObj := c.(json.Object)
		if !isObj do continue
		if n, _ := co["name"].(json.String); string(n) == segment do return i
	}
	return -1
}

// match_base_child: the component child an instance child was built from
// (-1: added to the instance). By uid when the component child has one,
// else by name; each component child matches once (a copy of a node made
// inside the instance has the original's uid, and is an added node).
@(private = "file")
match_base_child :: proc(baseKids: json.Array, co: json.Object, matched: []bool) -> int {
	uid, _ := co["uid"].(json.String)
	name, _ := co["name"].(json.String)
	for c, i in baseKids {
		bo, isObj := c.(json.Object)
		if !isObj || matched[i] do continue
		bu, _ := bo["uid"].(json.String)
		if bu != "" {
			if bu == uid do return i
		} else if bn, _ := bo["name"].(json.String); bn == name {
			return i
		}
	}
	return -1
}

// strip_uids: an added node is scene data, not a node of the component
// file: it is saved without uids (they are given when it's applied).
@(private = "file")
strip_uids :: proc(v: ^json.Value) {
	o, ok := &v.(json.Object)
	if !ok do return
	delete_key(o, "uid")
	if kids, has := o["children"].(json.Array); has do for &k in kids do strip_uids(&k)
}

// The keys of an instance saved as a link (write_node's link form).
@(private = "file")
LINK_FORM_KEYS :: []string{"type", "name", "uid", "position", "scale", "rotation", "pivot", "enabled", "visible", "layer", "z_index", "y_sort", "y_sort_offset", "pause_mode", "paused", "editor_locked", "editor_hidden", "tags", "component", "overrides", "connections"}

// to_link_form: instances inside a node added to an instance are saved as
// links with their own overrides (the full serialization expands them).
@(private = "file")
to_link_form :: proc(v: ^json.Value) {
	o, ok := &v.(json.Object)
	if !ok do return
	if _, isLink := o["component"]; isLink {
		drop := make([dynamic]string, context.temp_allocator)
		for k in o do if !contains_str(LINK_FORM_KEYS, k) do append(&drop, k)
		for k in drop do delete_key(o, k)
		return
	}
	if kids, has := o["children"].(json.Array); has do for &k in kids do to_link_form(&k)
}

@(private = "file")
diff_tree :: proc(base, inst: json.Object, path: string, out: ^json.Object, added: ^json.Object, removed: ^json.Array, order: ^json.Object) {
	if d, changed := diff_node(base, inst, path == "."); changed do out[path] = d
	instKids, _ := inst["children"].(json.Array)
	baseKids, _ := base["children"].(json.Array)
	matched := make([]bool, len(baseKids), context.temp_allocator)
	// The children's order: kept when it isn't the natural one (the
	// component's children in its order, then the added ones).
	segments := make(json.Array, 0, len(instKids), context.temp_allocator)
	natural := true
	lastBase, seenAdded := -1, false
	for &c in instKids {
		co, isObj := c.(json.Object)
		if !isObj do continue
		i := match_base_child(baseKids, co, matched)
		if i < 0 {
			// A node added to this instance: saved in full under its parent.
			strip_uids(&c)
			to_link_form(&c)
			co = c.(json.Object)
			list, _ := added[path].(json.Array)
			if list == nil do list = make(json.Array, context.temp_allocator)
			append(&list, co)
			added[path] = list
			name, _ := co["name"].(json.String)
			append(&segments, json.String(strings.concatenate({ORDER_ADDED_PREFIX, string(name)}, context.temp_allocator)))
			seenAdded = true
			continue
		}
		if seenAdded || i < lastBase do natural = false
		lastBase = i
		matched[i] = true
		bc := baseKids[i].(json.Object)
		append(&segments, json.String(node_segment(bc)))
		diff_tree(bc, co, join_path(path, node_segment(bc)), out, added, removed, order)
	}
	if !natural do order[path] = segments
	// Component children removed from this instance.
	for c, i in baseKids {
		co, isObj := c.(json.Object)
		if !isObj || matched[i] do continue
		append(removed, json.String(join_path(path, node_segment(co))))
	}
}

// component_base_json: the component file's node object.
@(private = "file")
component_base_json :: proc(ctx: ^GameContext, compPath: string) -> (json.Object, bool) {
	data, ok := Component_ReadFile(ctx, compPath)
	if !ok do return nil, false
	val, err := json.parse(data, allocator = context.temp_allocator)
	if err != .None do return nil, false
	obj, isObj := val.(json.Object)
	if !isObj do return nil, false
	if inner, has := obj["node"].(json.Object); has do obj = inner
	return obj, true
}

// --- nested instances ---------------------------------------------------------------
// A component's JSON is used with the instances it nests *expanded*: each
// nested link object becomes the nested component's tree (normalized, its
// own nested instances expanded, the link's overrides applied), with the
// link's own keys (name, uid, transform...) on top and COMPONENT_EXPANDED
// set. So override paths cross nested links ("bina0000/cinb0000/1eaf0000")
// and every level's override of a node merges per node (#79). The tree is
// built as is (read_node), and each nested root gets the base text stored
// under the marker.

// Set on an expanded nested link object: its base text while building, `true`
// in stored base text.
COMPONENT_EXPANDED :: "$expanded"

// Component_KeepBases: instances remember the component JSON they were
// built from (componentBase), to diff against it after the file changes -
// the editor. A game (Engine_RunProject) turns it off: its files don't
// change while it runs, so overrides are diffed against the file (#80).
Component_KeepBases := true

// --- prepared components cache (#80) -----------------------------------------------
// Expanding a component (read, parse, normalize, expand what it nests) is
// done once per path; instances are built from a parse of the cached text.
// An entry lists every file it read (the component and what it nests, also
// missing ones) with its size and time, and is dropped when one differs;
// writers that may write twice within the time resolution call
// Component_ForgetPrepared.

@(private = "file")
Prepared_Dep :: struct {
	path:   string,
	exists: bool,
	size:   i64,
	mod:    time.Time,
}

@(private = "file")
Prepared :: struct {
	text: string, // the expanded tree (nested base texts under their markers)
	base: string,
	deps: []Prepared_Dep,
	// A file it read was modified just before it was made: written again
	// in the same file time (same size), a change couldn't be told - so it's
	// expanded again until its files are older (git's "racy clean").
	racy: bool,
}

// RACY_WINDOW: how recently modified a file must be for an entry reading it
// to be racy (file times are coarse on some systems).
@(private = "file")
RACY_WINDOW :: 2 * time.Second

@(private = "file")
preparedCache: map[string]Prepared
// The files read by the expansion being cached (nil: not caching).
@(private = "file")
preparedDeps: ^[dynamic]string

// Component_ForgetPrepared drops every prepared component (a component file
// was written).
Component_ForgetPrepared :: proc() {
	heap := runtime_heap()
	for k, p in preparedCache {
		delete(k, heap)
		delete(p.text, heap)
		delete(p.base, heap)
		for d in p.deps do delete(d.path, heap)
		delete(p.deps, heap)
	}
	delete(preparedCache)
	preparedCache = nil
}

// Component_PreparedCount: how many prepared components are cached.
Component_PreparedCount :: proc() -> int {
	return len(preparedCache)
}

@(private = "file")
prepared_dep :: proc(ctx: ^GameContext, path: string) -> Prepared_Dep {
	d := Prepared_Dep{path = path}
	disk := path
	if ctx != nil && ctx.game != nil {
		// (Files in a mounted .rayzr don't change.)
		if ctx.game.assetManager.package_ != nil && RayzrPackage_HasFile(ctx.game.assetManager.package_, path) {
			d.exists = true
			return d
		}
		disk = AssetManager_ResolveDiskPath(&ctx.game.assetManager, path)
	}
	if info, err := os.stat(disk, context.temp_allocator); err == nil {
		d.exists, d.size, d.mod = true, info.size, info.modification_time
	}
	return d
}

@(private = "file")
prepared_fresh :: proc(ctx: ^GameContext, p: Prepared) -> bool {
	for d in p.deps {
		now := prepared_dep(ctx, d.path)
		if now.exists != d.exists || now.size != d.size || now.mod != d.mod do return false
	}
	return true
}

// drop_prepared removes an entry. A stale one's base is kept in staleBases
// without bases (a game): the instances built from it diff against it when
// they're rebuilt (Component_HotReload).
@(private = "file")
drop_prepared :: proc(compPath: string, stale := true) {
	heap := runtime_heap()
	key, p := delete_key(&preparedCache, compPath)
	if stale && !Component_KeepBases && !(key in staleBases) {
		// (Gone stale twice before a rebuild: the first base is the one
		// most instances were built from.)
		if staleBases == nil do staleBases = make(map[string]string, 4, heap)
		staleBases[key] = p.base
	} else {
		delete(key, heap)
		delete(p.base, heap)
	}
	delete(p.text, heap)
	for d in p.deps do delete(d.path, heap)
	delete(p.deps, heap)
}

// --- hot reload (#83) --------------------------------------------------------------
// A game (development runs: scriptManager.hotReload) rebuilds the instances
// of a component whose file changed - the outermost instance holding each,
// with its overrides (diffed against the base it was built from, kept in
// staleBases), transform and place in the tree. The editor (bases kept)
// refreshes instances itself when it writes a component file.

@(private = "file")
staleBases: map[string]string
@(private = "file")
lastComponentCheck: time.Tick

@(private = "file")
forget_stale_bases :: proc() {
	heap := runtime_heap()
	for k, v in staleBases {
		delete(k, heap)
		delete(v, heap)
	}
	delete(staleBases)
	staleBases = nil
}

// Component_HotReload checks the prepared components' files (every
// HOT_RELOAD_INTERVAL unless `force`) and rebuilds the instances of the
// changed ones in every loaded scene. Returns how many it rebuilt.
Component_HotReload :: proc(game: ^Game, force := false) -> int {
	if game == nil || Component_KeepBases do return 0
	if !force && time.tick_since(lastComponentCheck) < HOT_RELOAD_INTERVAL do return 0
	lastComponentCheck = time.tick_now()
	ctx := &game.gameContext
	stale := make([dynamic]string, context.temp_allocator)
	for k, p in preparedCache do if !prepared_fresh(ctx, p) do append(&stale, k)
	for k in stale do drop_prepared(k)
	if len(staleBases) == 0 do return 0
	defer forget_stale_bases()
	count := 0
	for _, scene in game.sceneManager.scenes {
		if scene == nil || !scene.isLoaded || scene.manager == nil do continue
		targets := make([dynamic]^Node, context.temp_allocator)
		for n in scene.manager.nodes {
			if n == nil || !(n.componentPath in staleBases) do continue
			outer := n
			for p := GetParent(scene.manager, n); p != nil; p = GetParent(scene.manager, p) do if p.componentPath != "" do outer = p
			if !slice.contains(targets[:], outer) do append(&targets, outer)
		}
		rebuilt := 0
		for old in targets {
			base, has := staleBases[old.componentPath]
			if !has {
				// (Built before the cache knew it: its overrides can't be told
				// from the file's old values.)
				log.warnf("[HotReload] %s: instance %s kept as it is (restart to update it)", old.componentPath, old.name)
				continue
			}
			if old.componentBase == "" do old.componentBase = strings.clone(base, old.allocator)
			path := strings.clone(old.componentPath, context.temp_allocator)
			if Scene_RebuildInstance(scene, old, "", ctx) != nil {
				rebuilt += 1
				log.infof("[HotReload] Rebuilt an instance of %s", path)
			}
		}
		// (Tile maps measure painted components again: their size may have changed.)
		if rebuilt > 0 do for n in scene.manager.nodes do if n != nil && n.typeId == TileMapNode do TileMapNode_ForgetFootprints(cast(^TileMapNode)n)
		count += rebuilt
	}
	return count
}

// Component_Expand: the component file's node JSON, normalized, its nested
// instances expanded; and its base text (what instances diff against).
// `stack`: the components being expanded / built around it (loops: #75).
// Outside any other component (an empty stack) it comes from the cache.
@(private)
Component_Expand :: proc(ctx: ^GameContext, compPath: string, stack: ^[dynamic]string) -> (obj: json.Object, baseText: string, problem: string) {
	if len(stack) > 0 || preparedDeps != nil do return component_expand(ctx, compPath, stack)
	if p, cached := preparedCache[compPath]; cached {
		fresh := prepared_fresh(ctx, p)
		if fresh && !p.racy {
			val, err := json.parse(transmute([]u8)p.text, allocator = context.temp_allocator)
			if o, isObj := val.(json.Object); err == .None && isObj do return o, p.base, ""
		}
		drop_prepared(compPath, stale = !fresh)
	}
	deps := make([dynamic]string, context.temp_allocator)
	preparedDeps = &deps
	obj, baseText, problem = component_expand(ctx, compPath, stack)
	preparedDeps = nil
	if problem != "" do return // (a missing / broken file isn't cached: it may come back)
	heap := runtime_heap()
	w := Json_Writer{sb = strings.builder_make(context.temp_allocator)}
	json_write_value(&w, obj, false)
	entry := Prepared{text = strings.clone(strings.to_string(w.sb), heap), base = strings.clone(baseText, heap), deps = make([]Prepared_Dep, len(deps), heap)}
	now := time.now()
	for path, i in deps {
		entry.deps[i] = prepared_dep(ctx, path)
		entry.deps[i].path = strings.clone(path, heap)
		if d := entry.deps[i]; d.exists && time.diff(d.mod, now) < RACY_WINDOW do entry.racy = true
	}
	if preparedCache == nil do preparedCache = make(map[string]Prepared, 16, heap)
	preparedCache[strings.clone(compPath, heap)] = entry
	return
}

@(private = "file")
component_expand :: proc(ctx: ^GameContext, compPath: string, stack: ^[dynamic]string) -> (obj: json.Object, baseText: string, problem: string) {
	if preparedDeps != nil do append(preparedDeps, compPath)
	for p in stack do if p == compPath {
		chain := make([dynamic]string, context.temp_allocator)
		append(&chain, ..stack[:])
		append(&chain, compPath)
		return nil, "", fmt.tprintf("the component contains itself (%s)", strings.join(chain[:], " -> ", context.temp_allocator))
	}
	if len(stack) >= 16 do return nil, "", "components nest too deep"
	data, ok := Component_ReadFile(ctx, compPath)
	if !ok do return nil, "", "the component file is missing"
	val, err := json.parse(data, allocator = context.temp_allocator)
	if err != .None do return nil, "", fmt.tprintf("the component file is not valid JSON (%v)", err)
	isObj: bool
	obj, isObj = val.(json.Object)
	if !isObj do return nil, "", "the component file is not a node"
	if inner, has := obj["node"].(json.Object); has do obj = inner
	normalize_base(&obj, ctx)
	append(stack, compPath)
	expand_links(ctx, &obj, stack)
	pop(stack)
	w := Json_Writer{sb = strings.builder_make(context.temp_allocator)}
	json_write_value(&w, obj, true)
	return obj, strings.to_string(w.sb), ""
}

// expand_links expands the nested instances below `obj` (in place). One
// that can't be expanded stays a link (it loads as a placeholder).
@(private = "file")
expand_links :: proc(ctx: ^GameContext, obj: ^json.Object, stack: ^[dynamic]string) {
	kids, has := obj["children"].(json.Array)
	if !has do return
	for &c in kids {
		co, isObj := &c.(json.Object)
		if !isObj do continue
		path, _ := co["component"].(json.String)
		if path == "" {
			expand_links(ctx, co, stack)
			continue
		}
		nested, nestedBase, problem := component_expand(ctx, string(path), stack)
		if problem != "" do continue
		if ov, hasOv := co["overrides"].(json.Object); hasOv do Component_ApplyOverrides(&nested, ov)
		// The link's keys on top (an instance's own lock / hide flags only).
		delete_key(&nested, "editor_locked")
		delete_key(&nested, "editor_hidden")
		for k, v in co^ do if k != "overrides" && k != "children" && k != "type" do nested[k] = v
		nested[COMPONENT_EXPANDED] = json.String(nestedBase)
		c = nested
	}
}

// is_expanded_link: a nested link object expanded in place.
@(private = "file")
is_expanded_link :: proc(obj: json.Object) -> bool {
	_, ok := obj[COMPONENT_EXPANDED]
	return ok
}

// --- base normalization ------------------------------------------------------------
// Hand-written (or older) component files omit default values. Before
// diffing, the base JSON gets each node type's defaults and each script's
// declared property defaults, so an unchanged instance has no overrides
// (and a later change to the component file isn't masked by a default).

@(private = "file")
typeDefaults: map[string]string // type name -> serialized default node

@(private)
type_defaults :: proc(typeName: string) -> (json.Object, bool) {
	text, cached := typeDefaults[typeName]
	if !cached {
		scratch := new(Scene)
		InitializeScene(scratch)
		n := Node_CreateByTypeName(scratch, typeName)
		if n != nil {
			ProcessNodeQueues(scratch.manager, nil)
			text = strings.clone(Node_SerializeToJSON(n, scratch.manager, context.temp_allocator), runtime_heap())
		}
		TerminateScene(scratch)
		free(scratch)
		if typeDefaults == nil do typeDefaults = make(map[string]string, 16, runtime_heap())
		typeDefaults[strings.clone(typeName, runtime_heap())] = text
	}
	if text == "" do return nil, false
	val, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None do return nil, false
	obj, ok := val.(json.Object)
	return obj, ok
}

@(private = "file")
script_value_json :: proc(v: ScriptValue) -> json.Value {
	switch v.type {
	case .Float:   return json.Float(v.valFloat)
	case .Int:     return json.Integer(v.valInt)
	case .Boolean: return json.Boolean(v.valBool)
	case .String:  return json.String(v.valString)
	case .Vector2:
		arr := make(json.Array, 2, context.temp_allocator)
		arr[0], arr[1] = json.Float(v.valVec2.x), json.Float(v.valVec2.y)
		return arr
	case .Color:
		arr := make(json.Array, 4, context.temp_allocator)
		for c, i in v.valColor do arr[i] = json.Float(c)
		return arr
	}
	return nil
}

// deep_fill sets obj[k] = v when missing; objects are filled key by key.
@(private = "file")
deep_fill :: proc(obj: ^json.Object, k: string, v: json.Value) {
	cur, has := obj[k]
	if !has {
		obj[k] = v
		return
	}
	co, cIsObj := cur.(json.Object)
	do_, dIsObj := v.(json.Object)
	if cIsObj && dIsObj {
		for sk, sv in do_ do deep_fill(&co, sk, sv)
		obj[k] = co
	}
}

// normalize_base fills defaults into a component node tree (in place).
@(private)
normalize_base :: proc(obj: ^json.Object, ctx: ^GameContext) {
	// A custom node is written as what differs from its type (custom_nodes.odin)
	// on both sides of a diff: its defaults stay out (its children don't).
	_, isCustom := obj[CUSTOM_NODE_KEY]
	typeName, _ := obj["type"].(json.String)
	if typeName == "" do typeName = "Node"
	if _, isLink := obj["component"]; !isLink {
		if defs, ok := type_defaults(string(typeName)); ok {
			for k, v in defs {
				if k == "children" || k == "name" do continue
				// (A custom node: only the keys it always writes - scale, rotation.)
				if isCustom && !Custom_IsDirectKey(k) do continue
				deep_fill(obj, k, v)
			}
		}
	}
	// Script property defaults.
	if so, has := obj["script"].(json.Object); has && !isCustom {
		path, _ := so["path"].(json.String)
		mgr := ctx.scriptManager if ctx != nil else nil
		if path != "" && mgr != nil {
			if mod, ok := ScriptManager_LoadModule(string(path), mgr); ok && mod != nil {
				props, hasProps := so["properties"].(json.Object)
				if !hasProps do props = make(json.Object, 0, context.temp_allocator)
				for p in mod.properties do if _, hp := props[p.name]; !hp do props[p.name] = script_value_json(p.defaultVal)
				so["properties"] = props
				obj["script"] = so
			}
		}
	}
	if arr, ok := obj["children"].(json.Array); ok {
		for &c in arr {
			if _, isObj := c.(json.Object); isObj do normalize_base(&c.(json.Object), ctx)
		}
	}
}

// Component_OverridesJSON: the "overrides" object for an instance ("" if
// it matches its component file).
Component_OverridesJSON :: proc(node: ^Node, manager: ^NodeManager) -> string {
	if node == nil || node.componentPath == "" do return ""
	// Diff against the component JSON this instance was built from (not
	// the file as it is now: after the file changes, unchanged values must
	// still follow it).
	base: json.Object
	if node.componentBase != "" {
		val, err := json.parse(transmute([]u8)node.componentBase, allocator = context.temp_allocator)
		if err != .None do return ""
		base, _ = val.(json.Object)
	} else {
		stack := make([dynamic]string, context.temp_allocator)
		problem: string
		base, _, problem = Component_Expand(node.gameContext, node.componentPath, &stack)
		if problem != "" do return ""
	}
	// In full, nested instances expanded too (their nodes diff one by one).
	prev, prevExpand := serializeFullInstance, serializeExpandNested
	serializeFullInstance, serializeExpandNested = node, true
	full := Node_SerializeToJSON(node, manager, context.temp_allocator)
	serializeFullInstance, serializeExpandNested = prev, prevExpand
	val, err := json.parse(transmute([]u8)full, allocator = context.temp_allocator)
	if err != .None do return ""
	inst, isObj := val.(json.Object)
	if !isObj do return ""
	out := make(json.Object, 0, context.temp_allocator)
	added := make(json.Object, 0, context.temp_allocator)
	removed := make(json.Array, 0, context.temp_allocator)
	order := make(json.Object, 0, context.temp_allocator)
	diff_tree(base, inst, ".", &out, &added, &removed, &order)
	if len(added) > 0 do out[OVERRIDE_ADDED] = added
	if len(removed) > 0 do out[OVERRIDE_REMOVED] = removed
	if len(order) > 0 do out[OVERRIDE_ORDER] = order
	if len(out) == 0 do return ""
	w := Json_Writer{sb = strings.builder_make(context.temp_allocator)}
	Json_WriteValue(&w, out)
	return strings.to_string(w.sb)
}

@(private = "file")
merge_keywise :: proc(target: ^json.Object, ov: json.Object) {
	for k, v in ov {
		if _, isNull := v.(json.Null); isNull || v == nil {
			delete_key(target, k)
		} else {
			target[k] = v
		}
	}
}

@(private)
merge_node :: proc(target: ^json.Object, ov: json.Object) {
	for k, v in ov {
		if _, isNull := v.(json.Null); isNull || v == nil {
			delete_key(target, k)
			continue
		}
		vo, vIsObj := v.(json.Object)
		to, tIsObj := target[k].(json.Object)
		switch {
		case k == "properties" && vIsObj && tIsObj:
			merge_keywise(&to, vo)
			target[k] = to
		case k == "script" && vIsObj && tIsObj:
			for sk, sv in vo {
				svo, svIsObj := sv.(json.Object)
				tpo, tpIsObj := to[sk].(json.Object)
				if sk == "properties" && svIsObj && tpIsObj {
					merge_keywise(&tpo, svo)
					to[sk] = tpo
				} else {
					to[sk] = sv
				}
			}
			target[k] = to
		case:
			target[k] = v
		}
	}
}


// Component_ApplyOverrides merges an instance's overrides into the
// component's node JSON (in place).
// Keys of the structural changes in an "overrides" block.
OVERRIDE_ADDED :: "$added"     // {"parent/path": [node, ...]}: nodes added to the instance
OVERRIDE_REMOVED :: "$removed" // ["child/path", ...]: component nodes removed from it
// {"parent/path": [segment, ...]}: a parent's children in the instance's
// order, where it isn't the natural one (component children, then added
// ones). Component children by segment (uid / name), added ones by
// "+" + name.
OVERRIDE_ORDER :: "$order"
@(private = "file")
ORDER_ADDED_PREFIX :: "+"

// find_node_obj: the node object at an override path ("." = the root;
// segments are uids or names: child_index).
@(private = "file")
find_node_obj :: proc(root: ^json.Object, path: string) -> ^json.Object {
	target := root
	if path == "." || path == "" do return target
	for part in strings.split(path, "/", context.temp_allocator) {
		arr, has := target["children"].(json.Array)
		if !has do return nil
		i := child_index(arr, part)
		if i < 0 do return nil
		// json.Object is a map: the pointer we write through is the same map.
		co, cIsObj := &arr[i].(json.Object)
		if !cIsObj do return nil
		target = co
	}
	return target
}

// resolve_path: the node object at an override path, or - when the path
// goes into a nested instance that isn't expanded (its file is missing) -
// that link object and the rest of the path inside it ("." = its root;
// `structural`: a path naming the link itself refers to its children).
@(private = "file")
resolve_path :: proc(root: ^json.Object, path: string, structural := false) -> (target: ^json.Object, link: ^json.Object, rest: string) {
	target = root
	if path == "." || path == "" do return
	parts := strings.split(path, "/", context.temp_allocator)
	for part, n in parts {
		if _, isLink := target["component"]; isLink && !is_expanded_link(target^) && target != root {
			return nil, target, strings.join(parts[n:], "/", context.temp_allocator)
		}
		arr, has := target["children"].(json.Array)
		if !has do return nil, nil, ""
		i := child_index(arr, part)
		if i < 0 do return nil, nil, ""
		co, cIsObj := &arr[i].(json.Object)
		if !cIsObj do return nil, nil, ""
		target = co
	}
	if _, isLink := target["component"]; structural && isLink && !is_expanded_link(target^) do return nil, target, "."
	return
}

// link_overrides: an unexpanded link's own "overrides" (created if none);
// write it back with link["overrides"] = ... after changing it.
@(private = "file")
link_overrides :: proc(link: ^json.Object) -> json.Object {
	ov, _ := link["overrides"].(json.Object)
	if ov == nil do ov = make(json.Object, 0, context.temp_allocator)
	return ov
}

// merge_override_entry merges one override entry into another (the later
// one wins; nulls are kept: they remove the value from the component).
@(private = "file")
merge_override_entry :: proc(target: ^json.Object, ov: json.Object) {
	for k, v in ov {
		vo, vIsObj := v.(json.Object)
		to, tIsObj := target[k].(json.Object)
		switch {
		case k == "properties" && vIsObj && tIsObj:
			for pk, pv in vo do to[pk] = pv
			target[k] = to
		case k == "script" && vIsObj && tIsObj:
			for sk, sv in vo {
				svo, svIsObj := sv.(json.Object)
				tpo, tpIsObj := to[sk].(json.Object)
				if sk == "properties" && svIsObj && tpIsObj {
					for pk, pv in svo do tpo[pk] = pv
					to[sk] = tpo
				} else {
					to[sk] = sv
				}
			}
			target[k] = to
		case:
			target[k] = v
		}
	}
}

// parent_and_last splits "a/b/c" into "a/b" and "c" ("." for the root).
@(private = "file")
parent_and_last :: proc(p: string) -> (string, string) {
	slash := strings.last_index_byte(p, '/')
	return p[:slash] if slash >= 0 else ".", p[slash + 1:]
}

Component_ApplyOverrides :: proc(base: ^json.Object, overrides: json.Object) {
	// Removed nodes first (paths refer to the component's structure).
	if removed, ok := overrides[OVERRIDE_REMOVED].(json.Array); ok {
		for rv in removed {
			path, isStr := rv.(json.String)
			if !isStr do continue
			parentPath, last := parent_and_last(string(path))
			parent, link, rest := resolve_path(base, parentPath, true)
			if link != nil {
				lov := link_overrides(link)
				list, _ := lov[OVERRIDE_REMOVED].(json.Array)
				if list == nil do list = make(json.Array, context.temp_allocator)
				append(&list, json.String(join_path(rest, last)))
				lov[OVERRIDE_REMOVED] = list
				link["overrides"] = lov
				continue
			}
			if parent == nil do continue
			kids, has := parent["children"].(json.Array)
			if !has do continue
			if i := child_index(kids, last); i >= 0 do ordered_remove(&kids, i)
			parent["children"] = kids
		}
	}
	for path, ov in overrides {
		if path == OVERRIDE_ADDED || path == OVERRIDE_REMOVED || path == OVERRIDE_ORDER do continue
		ovo, isObj := ov.(json.Object)
		if !isObj do continue
		target, link, rest := resolve_path(base, path)
		if link != nil {
			lov := link_overrides(link)
			entry, _ := lov[rest].(json.Object)
			if entry == nil do entry = make(json.Object, 0, context.temp_allocator)
			merge_override_entry(&entry, ovo)
			lov[rest] = entry
			link["overrides"] = lov
			continue
		}
		if target == nil do continue
		// (Saved before #79: a nested instance's whole "overrides" object.)
		if inner, has := ovo["overrides"].(json.Object); has && is_expanded_link(target^) {
			Component_ApplyOverrides(target, inner)
			local := make(json.Object, len(ovo), context.temp_allocator)
			for k, v in ovo do if k != "overrides" do local[k] = v
			ovo = local
		}
		merge_node(target, ovo)
	}
	// Added nodes go after the component's children, then $order puts them
	// (and moved ones) in place.
	baseCount := make(map[string]int, allocator = context.temp_allocator)
	if added, ok := overrides[OVERRIDE_ADDED].(json.Object); ok {
		for parentPath, list in added {
			parent, link, rest := resolve_path(base, parentPath, true)
			nodes, isArr := list.(json.Array)
			if !isArr do continue
			if link != nil {
				lov := link_overrides(link)
				lad, _ := lov[OVERRIDE_ADDED].(json.Object)
				if lad == nil do lad = make(json.Object, 0, context.temp_allocator)
				lad[rest] = list
				lov[OVERRIDE_ADDED] = lad
				link["overrides"] = lov
				continue
			}
			if parent == nil do continue
			kids, _ := parent["children"].(json.Array)
			if kids == nil do kids = make(json.Array, context.temp_allocator)
			baseCount[parentPath] = len(kids)
			for n in nodes do append(&kids, n)
			parent["children"] = kids
		}
	}
	if order, ok := overrides[OVERRIDE_ORDER].(json.Object); ok {
		for parentPath, list in order {
			parent, link, rest := resolve_path(base, parentPath, true)
			segments, isArr := list.(json.Array)
			if link != nil && isArr {
				lov := link_overrides(link)
				lor, _ := lov[OVERRIDE_ORDER].(json.Object)
				if lor == nil do lor = make(json.Object, 0, context.temp_allocator)
				lor[rest] = list
				lov[OVERRIDE_ORDER] = lor
				link["overrides"] = lov
				continue
			}
			if parent == nil || !isArr do continue
			kids, _ := parent["children"].(json.Array)
			nBase, hasAdded := baseCount[parentPath]
			if !hasAdded do nBase = len(kids)
			parent["children"] = order_children(kids, nBase, segments)
		}
	}
}

// order_children: `kids` (the component's first `nBase`, then the added
// ones) in the order `segments` lists; children it doesn't list (new in
// the component since) follow in their own order.
@(private = "file")
order_children :: proc(kids: json.Array, nBase: int, segments: json.Array) -> json.Array {
	used := make([]bool, len(kids), context.temp_allocator)
	out := make(json.Array, 0, len(kids), context.temp_allocator)
	pick :: proc(kids: json.Array, used: []bool, from, to: int, key, want: string) -> int {
		for i in from ..< to {
			co, isObj := kids[i].(json.Object)
			if !isObj || used[i] do continue
			if v, _ := co[key].(json.String); v != "" && string(v) == want do return i
		}
		return -1
	}
	for sv in segments {
		s, isStr := sv.(json.String)
		if !isStr do continue
		i := -1
		if strings.has_prefix(string(s), ORDER_ADDED_PREFIX) {
			i = pick(kids, used, nBase, len(kids), "name", string(s)[len(ORDER_ADDED_PREFIX):])
		} else {
			i = pick(kids, used, 0, nBase, "uid", string(s))
			if i < 0 do i = pick(kids, used, 0, nBase, "name", string(s))
		}
		if i < 0 do continue
		used[i] = true
		append(&out, kids[i])
	}
	for k, i in kids do if !used[i] do append(&out, k)
	return out
}

// Node_HasComponentOverrides: does this node (inside an instance) differ
// from the component file?
// The instance holding its overrides is the outermost one whose component
// contains the node (through nested instances, #79); an instance added to
// another keeps its own.
Node_ComponentOverridePath :: proc(manager: ^NodeManager, node: ^Node) -> (root: ^Node, path: string) {
	root = Node_ComponentRoot(manager, node)
	if root == nil do return nil, ""
	for {
		parent := GetParent(manager, root)
		outer := Node_ComponentRoot(manager, parent) if parent != nil else nil
		if outer == nil || !component_nests(outer, node_path_below(manager, root, outer)) do break
		root = outer
	}
	if root == node do return root, "."
	return root, node_path_below(manager, node, root)
}

// node_path_below: the override path of `node` from its ancestor `root`.
@(private = "file")
node_path_below :: proc(manager: ^NodeManager, node, root: ^Node) -> string {
	parts := make([dynamic]string, context.temp_allocator)
	for n := node; n != nil && n != root; n = GetParent(manager, n) do inject_at(&parts, 0, n.uid if n.uid != "" else n.name)
	return strings.join(parts[:], "/", context.temp_allocator)
}

// component_nests: is the node at `path` in instance `outer` a nested
// instance of its component (expanded in its base), not one added to it?
@(private = "file")
component_nests :: proc(outer: ^Node, path: string) -> bool {
	base: json.Object
	if outer.componentBase != "" {
		val, err := json.parse(transmute([]u8)outer.componentBase, allocator = context.temp_allocator)
		if err != .None do return false
		base, _ = val.(json.Object)
	} else {
		stack := make([dynamic]string, context.temp_allocator)
		problem: string
		base, _, problem = Component_Expand(outer.gameContext, outer.componentPath, &stack)
		if problem != "" do return false
	}
	target := find_node_obj(&base, path)
	return target != nil && is_expanded_link(target^)
}

// Node_ComponentOverrides returns the override keys of a node inside an
// instance (empty when it matches the component).
Node_ComponentOverrides :: proc(manager: ^NodeManager, node: ^Node) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	root, path := Node_ComponentOverridePath(manager, node)
	if root == nil do return out[:]
	text := Component_OverridesJSON(root, manager)
	if text == "" do return out[:]
	val, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None do return out[:]
	obj, _ := val.(json.Object)
	// Structural changes at this node: children added / removed.
	if added, ok := obj[OVERRIDE_ADDED].(json.Object); ok {
		if list, has := added[path].(json.Array); has && len(list) > 0 do append(&out, fmt.tprintf("+%d child(ren)", len(list)))
	}
	if removed, ok := obj[OVERRIDE_REMOVED].(json.Array); ok {
		n := 0
		for rv in removed {
			p, _ := rv.(json.String)
			parent := "."
			if i := strings.last_index_byte(string(p), '/'); i >= 0 do parent = string(p)[:i]
			if parent == path do n += 1
		}
		if n > 0 do append(&out, fmt.tprintf("-%d child(ren)", n))
	}
	if order, ok := obj[OVERRIDE_ORDER].(json.Object); ok && path in order do append(&out, "child order")
	entry, has := obj[path].(json.Object)
	if !has do return out[:]
	for k, v in entry {
		if sub, isObj := v.(json.Object); isObj && (k == "properties" || k == "script") {
			if k == "script" {
				if p, hp := sub["properties"].(json.Object); hp {
					for pk in p do append(&out, fmt.tprintf("script.%s", pk))
					continue
				}
			}
			for sk in sub do append(&out, fmt.tprintf("%s.%s", k, sk) if k == "script" else sk)
			continue
		}
		append(&out, k)
	}
	slice.sort(out[:])
	return out[:]
}

// Scene_RevertComponentOverrides drops a node's overrides (all of them
// when `node` is the instance root) and rebuilds the instance.
Scene_RevertComponentOverrides :: proc(scene: ^Scene, node: ^Node, ctx: ^GameContext) -> ^Node {
	mgr := scene.manager
	root, path := Node_ComponentOverridePath(mgr, node)
	if root == nil do return nil
	instJson := Node_SerializeToJSON(root, mgr, context.temp_allocator)
	val, err := json.parse(transmute([]u8)instJson, allocator = context.temp_allocator)
	if err != .None do return nil
	obj, _ := val.(json.Object)
	if ov, has := obj["overrides"].(json.Object); has {
		if path == "." {
			delete_key(&obj, "overrides")
		} else {
			delete_key(&ov, path)
			// A nested instance: everything inside it too.
			if node.componentPath != "" {
				inside := strings.concatenate({path, "/"}, context.temp_allocator)
				drop :: proc(o: ^json.Object, prefix: string) {
					keys := make([dynamic]string, context.temp_allocator)
					for k in o do if strings.has_prefix(k, prefix) do append(&keys, k)
					for k in keys do delete_key(o, k)
				}
				drop(&ov, inside)
				for key in ([]string{OVERRIDE_ADDED, OVERRIDE_ORDER}) {
					if sub, ok := ov[key].(json.Object); ok {
						drop(&sub, inside)
						ov[key] = sub
					}
				}
				if removed, ok := ov[OVERRIDE_REMOVED].(json.Array); ok {
					kept := make(json.Array, 0, context.temp_allocator)
					for rv in removed do if p, _ := rv.(json.String); !strings.has_prefix(string(p), inside) do append(&kept, rv)
					ov[OVERRIDE_REMOVED] = kept
				}
			}
			// ...and the children added under / removed from this node.
			if added, ok := ov[OVERRIDE_ADDED].(json.Object); ok {
				delete_key(&added, path)
				ov[OVERRIDE_ADDED] = added
			}
			if order, ok := ov[OVERRIDE_ORDER].(json.Object); ok {
				delete_key(&order, path)
				ov[OVERRIDE_ORDER] = order
			}
			if removed, ok := ov[OVERRIDE_REMOVED].(json.Array); ok {
				kept := make(json.Array, 0, context.temp_allocator)
				for rv in removed {
					p, _ := rv.(json.String)
					parent := "."
					if i := strings.last_index_byte(string(p), '/'); i >= 0 do parent = string(p)[:i]
					if parent != path do append(&kept, rv)
				}
				ov[OVERRIDE_REMOVED] = kept
			}
			obj["overrides"] = ov
		}
	}
	w := Json_Writer{sb = strings.builder_make(context.temp_allocator)}
	Json_WriteValue(&w, obj)
	return Scene_RebuildInstance(scene, root, strings.to_string(w.sb), ctx)
}

// take_override_key removes one value from a node's override entry (`key`
// as Node_ComponentOverrides lists it: a node key, a reflected property, or
// "script.<name>") and returns it as an entry of its own.
@(private = "file")
take_override_key :: proc(entry: ^json.Object, key: string) -> (single: json.Object, found: bool) {
	single = make(json.Object, 0, context.temp_allocator)
	// (Maps are written back after a change: their length is in the value.)
	take :: proc(outer: ^json.Object, sub, key: string) -> (json.Value, bool) {
		o, _ := outer[sub].(json.Object)
		v, has := o[key]
		if !has do return nil, false
		delete_key(&o, key)
		if len(o) == 0 do delete_key(outer, sub)
		else do outer[sub] = o
		return v, true
	}
	wrap :: proc(key: string, v: json.Value) -> json.Object {
		o := make(json.Object, 0, context.temp_allocator)
		o[key] = v
		return o
	}
	if strings.has_prefix(key, "script.") {
		so, _ := entry["script"].(json.Object)
		v := take(&so, "properties", key[len("script."):]) or_return
		if len(so) == 0 do delete_key(entry, "script")
		else do entry["script"] = so
		single["script"] = wrap("properties", wrap(key[len("script."):], v))
		return single, true
	}
	if v, has := entry[key]; has && key != "properties" && key != "script" {
		delete_key(entry, key)
		single[key] = v
		return single, true
	}
	v := take(entry, "properties", key) or_return
	single["properties"] = wrap(key, v)
	return single, true
}

// Scene_RevertComponentOverride drops one overridden value of a node in an
// instance (`key` as Node_ComponentOverrides lists it) and rebuilds the
// instance. Returns its new root (nil: the node has no such override).
Scene_RevertComponentOverride :: proc(scene: ^Scene, node: ^Node, key: string, ctx: ^GameContext) -> ^Node {
	mgr := scene.manager
	root, path := Node_ComponentOverridePath(mgr, node)
	if root == nil do return nil
	instJson := Node_SerializeToJSON(root, mgr, context.temp_allocator)
	val, err := json.parse(transmute([]u8)instJson, allocator = context.temp_allocator)
	if err != .None do return nil
	obj, _ := val.(json.Object)
	ov, _ := obj["overrides"].(json.Object)
	entry, has := ov[path].(json.Object)
	if !has do return nil
	if _, found := take_override_key(&entry, key); !found do return nil
	if len(entry) == 0 do delete_key(&ov, path)
	else do ov[path] = entry
	if len(ov) == 0 do delete_key(&obj, "overrides")
	else do obj["overrides"] = ov
	w := Json_Writer{sb = strings.builder_make(context.temp_allocator)}
	Json_WriteValue(&w, obj)
	return Scene_RebuildInstance(scene, root, strings.to_string(w.sb), ctx)
}

// Component_ApplyOverrideJSON: the component file of the instance holding
// a node's override (`rel`, project-relative), with that one value (`key`
// as Node_ComponentOverrides lists it) written into it - inside a nested
// instance, into its link's overrides. ("", "": no such override.) It's
// written like Apply: a scratch instance with only that override, removed
// again.
Component_ApplyOverrideJSON :: proc(scene: ^Scene, node: ^Node, key: string, ctx: ^GameContext, allocator := context.allocator) -> (rel, text: string) {
	mgr := scene.manager
	root, path := Node_ComponentOverridePath(mgr, node)
	if root == nil || root.componentMissing do return "", ""
	ovText := Component_OverridesJSON(root, mgr)
	if ovText == "" do return "", ""
	val, err := json.parse(transmute([]u8)ovText, allocator = context.temp_allocator)
	if err != .None do return "", ""
	ov, _ := val.(json.Object)
	entry, has := ov[path].(json.Object)
	if !has do return "", ""
	single, found := take_override_key(&entry, key)
	if !found do return "", ""
	one := make(json.Object, 0, context.temp_allocator)
	one[path] = single
	link := make(json.Object, 0, context.temp_allocator)
	link["component"] = json.String(root.componentPath)
	link["overrides"] = one
	w := Json_Writer{sb = strings.builder_make(context.temp_allocator)}
	Json_WriteValue(&w, link)
	scratch := Scene_InstantiateNodeFromJSON(scene, transmute([]u8)strings.to_string(w.sb), GetParent(mgr, root), ctx)
	if scratch == nil do return "", ""
	ProcessNodeQueues(mgr, ctx)
	text = Component_InstanceJSON(scratch, mgr, allocator)
	RemoveNode(mgr, scratch)
	ProcessNodeQueues(mgr, ctx)
	return strings.clone(root.componentPath, allocator), text
}

@(private = "file")
runtime_heap :: proc() -> runtime.Allocator {
	return Engine_HeapAllocator()
}

// Component_ClearCaches frees the per-type default cache (engine shutdown / tests).
Component_ClearCaches :: proc() {
	for k, v in typeDefaults {
		delete(k, Engine_HeapAllocator())
		delete(v, Engine_HeapAllocator())
	}
	delete(typeDefaults)
	typeDefaults = nil
	Component_ForgetPrepared()
	forget_stale_bases()
}

// Component_InstanceJSON: an instance's whole subtree as a component file
// (its link and overrides baked in; Apply, Save as Component). Every node
// gets a uid unique in the file: the ones it has are kept (the root keeps
// the component's root uid); the others are given now, on the live nodes.
Component_InstanceJSON :: proc(node: ^Node, manager: ^NodeManager, allocator := context.allocator) -> string {
	rootUid := node.uid
	if node.componentPath != "" {
		// (The instance's own uid belongs to the document holding it.)
		base: json.Object
		if node.componentBase != "" {
			val, _ := json.parse(transmute([]u8)node.componentBase, allocator = context.temp_allocator)
			base, _ = val.(json.Object)
		} else {
			base, _ = component_base_json(node.gameContext, node.componentPath)
		}
		u, _ := base["uid"].(json.String)
		rootUid = string(u)
	}
	if rootUid == "" do rootUid = Component_NewUid(context.temp_allocator)
	seen := make(map[string]bool, allocator = context.temp_allocator)
	seen[rootUid] = true
	for c in GetChildrenView(manager, node) do assign_uids(manager, c, &seen)

	prevNode, prevUid := serializeRootUidNode, serializeRootUid
	serializeRootUidNode, serializeRootUid = node, rootUid
	// (Nested instances are written as links: their overrides baked in.)
	prev, prevExpand := serializeFullInstance, serializeExpandNested
	serializeFullInstance, serializeExpandNested = node, false
	defer {
		serializeFullInstance, serializeExpandNested = prev, prevExpand
		serializeRootUidNode, serializeRootUid = prevNode, prevUid
	}
	return Node_SerializeToJSON(node, manager, allocator)
}

// Component_FileJSON: a component document's root as its file, with a uid
// on every node (given now to the nodes without one, or with one another
// node of the file has already).
Component_FileJSON :: proc(root: ^Node, manager: ^NodeManager, allocator := context.allocator) -> string {
	seen := make(map[string]bool, allocator = context.temp_allocator)
	assign_uids(manager, root, &seen)
	return Node_SerializeToJSON(root, manager, allocator)
}

// Scene_AssignUids: a uid on every node of the scene, unique in it (#328):
// the ones it has are kept, missing or repeated ones are given now. Called
// on load and save, so old scenes get theirs when next saved.
Scene_AssignUids :: proc(scene: ^Scene) {
	if scene == nil || scene.rootNode == nil do return
	seen := make(map[string]bool, allocator = context.temp_allocator)
	assign_uids(scene.manager, scene.rootNode, &seen)
}

// Node_FindByUid: the node of the scene with this uid (the first, depth
// first; nodes inside linked instances share their file's uids).
Node_FindByUid :: proc(manager: ^NodeManager, root: ^Node, uid: string) -> ^Node {
	if root == nil || uid == "" do return nil
	if root.uid == uid do return root
	for c in GetChildrenView(manager, root) do if found := Node_FindByUid(manager, c, uid); found != nil do return found
	return nil
}

// Node_ForgetCopiedUids: a pasted or duplicated subtree keeps a uid only
// when no other node of the scene has it - a cut and pasted node keeps its
// identity (instances' overrides stay on it); a copy is a new node (given a
// uid when its component file is written).
Node_ForgetCopiedUids :: proc(manager: ^NodeManager, copy: ^Node) {
	if manager == nil || copy == nil do return
	mine := make(map[^Node]bool, allocator = context.temp_allocator)
	collect :: proc(manager: ^NodeManager, n: ^Node, into: ^map[^Node]bool) {
		into[n] = true
		// (A linked instance's own nodes have its file's uids, like every
		// other instance of that file.)
		if n.componentPath != "" do return
		for c in GetChildrenView(manager, n) do collect(manager, c, into)
	}
	collect(manager, copy, &mine)
	taken := make(map[string]bool, allocator = context.temp_allocator)
	for n in manager.nodes do if n != nil && n.uid != "" && n not_in mine do taken[n.uid] = true
	for n in mine do if n.uid in taken do n.uid = ""
}

// Component_NewUid: 8 random base-36 characters.
Component_NewUid :: proc(allocator := context.allocator) -> string {
	digits := "0123456789abcdefghijklmnopqrstuvwxyz"
	buf: [8]u8
	for &b in buf do b = digits[rand.int_max(len(digits))]
	return strings.clone(string(buf[:]), allocator)
}

// assign_uids: a uid for `n` and the nodes of the file below it (a nested
// instance's own nodes come from its file, so it stops there).
@(private = "file")
assign_uids :: proc(manager: ^NodeManager, n: ^Node, seen: ^map[string]bool) {
	if n.uid == "" || n.uid in seen^ {
		u := Component_NewUid(context.temp_allocator)
		for {
			if u not_in seen^ do break
			u = Component_NewUid(context.temp_allocator)
		}
		n.uid = strings.clone(u, n.allocator)
	}
	seen[n.uid] = true
	if n.componentPath != "" do return
	for c in GetChildrenView(manager, n) do assign_uids(manager, c, seen)
}
