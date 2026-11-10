package engine

import "core:encoding/json"
import "core:fmt"
import "core:hash"
import "core:math"
import os "osx"
import "core:path/filepath"
import "core:strings"

// ============================================================================
// Canonical scene files (#293): a scene or component file rewritten exactly
// as the editor saves it - so a file written by hand or by a generator
// (scripts/templates/make_templates.py) doesn't turn into a whole-file diff
// the first time someone saves it in the editor. The editor's saves are
// already stable (the same scene always writes the same text); this makes
// every file start out that way (`--fmt` on the editor, Project > Format
// Scene Files).
//
// Nodes without a uid get one made from the file's path and the node's place
// in the tree, so formatting the same file twice gives the same text (the
// editor's own saves use random ones). A rewrite must keep every value the
// file had (Canonical_Lossless): one that would lose or change something is
// refused, the file left as it is.
// ============================================================================

Canonical_Kind :: enum {Unknown, Scene, Component}

// Canonical_KindOf: what a path holds (custom node types, *.node.json, are
// definitions the editor writes itself: not formatted).
Canonical_KindOf :: proc(path: string) -> Canonical_Kind {
	switch {
	case strings.has_suffix(path, ".scene.json"): return .Scene
	case strings.has_suffix(path, ".component.json"): return .Component
	}
	return .Unknown
}

// Canonical_Format: a file's text as the editor would save it (rel: its
// project-relative path, the uid seed). problem != "": not formatted (newer
// format, unreadable, or a rewrite that would lose something).
Canonical_Format :: proc(game: ^Game, rel: string, data: []u8, allocator := context.allocator) -> (out: string, problem: string) {
	kind := Canonical_KindOf(rel)
	if kind == .Unknown do return "", "not a scene or component file"
	fk: Format_Kind = .Scene if kind == .Scene else .Component
	if Format_IsNewer(fk, Format_OfText(data)) do return "", fmt.tprintf("made by a newer Rayzr (format %d)", Format_OfText(data))
	parsed, perr := json.parse(data, allocator = context.temp_allocator)
	if perr != .None do return "", fmt.tprintf("not valid JSON (%v)", perr)
	// (Uids first, in the text: a load gives random ones to nodes without.)
	seeded := data
	if root, isObj := parsed.(json.Object); isObj {
		node := root["root"] if kind == .Scene else parsed
		if seededNode, given := canonical_seed_uids(node, rel); given {
			// (A map written to is a new value: stored back where it was.)
			if kind == .Scene {
				root["root"] = seededNode
				parsed = root
			} else do parsed = seededNode
			text, merr := json.marshal(parsed, allocator = context.temp_allocator)
			if merr != nil do return "", "could not be read"
			seeded = text
		}
	}
	ctx := &game.gameContext
	// (One scratch scene, let go of after: the editor formats with its own
	// game - its current scene stays the current one.)
	current, ctxScene, muted := game.sceneManager.currentScene, ctx.scene, Script_CallbacksMuted
	Script_CallbacksMuted = true // (the game's scripts don't run: on_destroy)
	s := game->createScene("fmt:canonical", false)
	defer {
		TerminateScene(s)
		game.sceneManager.currentScene, ctx.scene = current, ctxScene
		Script_CallbacksMuted = muted
	}
	text: string
	switch kind {
	case .Scene:
		if !Scene_InstantiateFromJSON(s, seeded, ctx) do return "", "could not be loaded"
		ProcessNodeQueues(s.manager, ctx)
		// (Its own name, not the one the load used: a file without one gets its stem.)
		name := Scene_ReadJSONName(data)
		if name == "" do name = strings.trim_suffix(filepath.base(rel), ".scene.json")
		s.name = strings.clone(name, game.sceneManager.allocator)
		text = Scene_SerializeToJSON(s, context.temp_allocator)
	case .Component:
		// (As the editor opens a component document: components.odin.)
		s.rootNode.gameContext = ctx
		node := Scene_InstantiateNodeFromJSON(s, seeded, s.rootNode, ctx)
		if node == nil do return "", "could not be loaded"
		node.position = {0, 0}
		ProcessNodeQueues(s.manager, ctx)
		text = Component_FileJSON(node, s.manager, context.temp_allocator)
	case .Unknown:
	}
	if why := Canonical_Lossless(data, transmute([]u8)text); why != "" do return "", why
	return strings.clone(text, allocator), ""
}

// canonical_seed_uids gives the node objects without a "uid" one made from
// `seed` and the node's child-index path (unique in the file); a component
// instance's contents keep their file's uids (not entered). Returns the
// node (its object updated) and whether any uid was given.
@(private = "file")
canonical_seed_uids :: proc(node: json.Value, seed: string) -> (json.Value, bool) {
	seen := make(map[string]bool, allocator = context.temp_allocator)
	collect :: proc(v: json.Value, seen: ^map[string]bool) {
		o, isObj := v.(json.Object)
		if !isObj do return
		if u, has := o["uid"].(json.String); has && u != "" do seen[string(u)] = true
		if _, inst := o["component"]; inst do return
		if kids, has := o["children"].(json.Array); has do for c in kids do collect(c, seen)
	}
	collect(node, &seen)
	give :: proc(v: json.Value, seed, path: string, seen: ^map[string]bool) -> (json.Value, bool) {
		o, isObj := v.(json.Object)
		if !isObj do return v, false
		given := false
		if u, has := o["uid"].(json.String); !has || u == "" {
			for attempt := 0; ; attempt += 1 {
				id := canonical_uid(fmt.tprintf("%s#%s#%d", seed, path, attempt))
				if id not_in seen^ {
					o["uid"] = json.String(id)
					seen[id] = true
					break
				}
			}
			given = true
		}
		if _, inst := o["component"]; inst do return o, given
		if kids, has := o["children"].(json.Array); has {
			for c, i in kids {
				nc, g := give(c, seed, fmt.tprintf("%s/%d", path, i), seen)
				kids[i] = nc
				if g do given = true
			}
			o["children"] = kids
		}
		return o, given
	}
	return give(node, seed, "", &seen)
}

// canonical_uid: 8 base-36 characters (as Component_NewUid) from a string.
@(private = "file")
canonical_uid :: proc(s: string) -> string {
	digits := "0123456789abcdefghijklmnopqrstuvwxyz"
	h := hash.fnv64a(transmute([]u8)s)
	buf: [8]u8
	for &b in buf {
		b = digits[h % 36]
		h /= 36
	}
	return strings.clone(string(buf[:]), context.temp_allocator)
}

// Canonical_Lossless: "" when `after` keeps every value of `before` (keys
// added - defaults, uids, "format" - are fine; numbers equal to the 4
// decimals the editor writes), else where the first difference is.
Canonical_Lossless :: proc(before, after: []u8) -> string {
	a, aerr := json.parse(before, allocator = context.temp_allocator)
	b, berr := json.parse(after, allocator = context.temp_allocator)
	if aerr != .None || berr != .None do return "not valid JSON"
	return canonical_keeps(a, b, "")
}

@(private = "file")
canonical_keeps :: proc(a, b: json.Value, path: string) -> string {
	number :: proc(v: json.Value) -> (f64, bool) {
		#partial switch x in v {
		case json.Integer: return f64(x), true
		case json.Float: return f64(x), true
		}
		return 0, false
	}
	if x, ok := number(a); ok {
		y, isNum := number(b)
		if !isNum do return fmt.tprintf("%s: a number became %v", path, b)
		if math.abs(x - y) > 0.0001 + math.abs(x) * 1e-6 do return fmt.tprintf("%s: %v became %v", path, x, y)
		return ""
	}
	#partial switch x in a {
	case json.Object:
		y, ok := b.(json.Object)
		if !ok do return fmt.tprintf("%s: an object became %v", path, b)
		for k, v in x {
			w, has := y[k]
			if !has {
				// (A default the editor doesn't write: 0, false, "", an empty list.)
				if canonical_is_default(v) do continue
				return fmt.tprintf("%s/%s: dropped", path, k)
			}
			if why := canonical_keeps(v, w, fmt.tprintf("%s/%s", path, k)); why != "" do return why
		}
		return ""
	case json.Array:
		y, ok := b.(json.Array)
		if !ok || len(x) != len(y) do return fmt.tprintf("%s: a list of %d became %v", path, len(x), b)
		for i in 0 ..< len(x) do if why := canonical_keeps(x[i], y[i], fmt.tprintf("%s[%d]", path, i)); why != "" do return why
		return ""
	case json.String:
		y, ok := b.(json.String)
		if !ok || x != y do return fmt.tprintf("%s: %q became %v", path, x, b)
		return ""
	case json.Boolean:
		y, ok := b.(json.Boolean)
		if !ok || x != y do return fmt.tprintf("%s: %v became %v", path, x, b)
		return ""
	case json.Null:
		return "" if b == nil else fmt.tprintf("%s: null became %v", path, b)
	}
	return ""
}

@(private = "file")
canonical_is_default :: proc(v: json.Value) -> bool {
	#partial switch x in v {
	case json.Null: return true
	case json.Integer: return x == 0
	case json.Float: return x == 0
	case json.Boolean: return !x
	case json.String: return x == ""
	case json.Array: return len(x) == 0
	case json.Object: return len(x) == 0
	}
	return false
}

// Canonical_ProjectOf: the folder holding the project.json a file belongs
// to ("" if none).
Canonical_ProjectOf :: proc(path: string, allocator := context.temp_allocator) -> string {
	abs, _ := filepath.abs(path, context.temp_allocator)
	d := filepath.dir(abs, context.temp_allocator)
	for d != "" && d != "/" && d != "." {
		pj, _ := filepath.join({d, "project.json"}, context.temp_allocator)
		if os.is_file(pj) do return strings.clone(d, allocator)
		up := filepath.dir(d, context.temp_allocator)
		if up == d do break
		d = up
	}
	return ""
}
