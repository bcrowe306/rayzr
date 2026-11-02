package engine

import "core:encoding/json"
import "core:log"
import os "osx"

// ============================================================================
// File format versions (#326): the 1.x compatibility promise.
//
// Every JSON file a project saves carries `"format": N`, an integer per file
// kind. Readers run the kind's migration chain first (step i turns format i
// into i + 1, JSON in, JSON out), so they only ever see the current format;
// writers stamp the current one. A file saved before formats existed (0.x)
// is format 0. Its older shapes (legacy blocks, renamed keys) are still read
// where the readers always read them - "format 0 support" - so the 0 -> 1
// step changes nothing.
//
// A file from a newer Rayzr (format above the current one) is read as well
// as possible with a warning; the editor opens it read-only and refuses to
// save over it, so what the newer version added isn't lost.
//
// Bumping a format: add a step to FORMAT_MIGRATIONS, raise FORMAT_CURRENT,
// add a fixture of the old format to tests/formats/<kind>/ and a line to
// engine/docs/compatibility.md.
// ============================================================================

FORMAT_KEY :: "format"

Format_Kind :: enum {
	Scene,      // *.scene.json
	Component,  // *.component.json (the key sits beside the root node's own)
	CustomNode, // *.node.json
	Resource,   // *.resource.json
	Project,    // project.json (export presets live inside it)
	Import,     // <asset>.import.json
	Tileset,    // <image>.tileset.json (terrains, tile animations)
	LevelGen,   // *.levelgen.json
}

FORMAT_CURRENT := [Format_Kind]int {
	.Scene      = 1,
	.Component  = 1,
	.CustomNode = 1,
	.Resource   = 1,
	.Project    = 1,
	.Import     = 1,
	.Tileset    = 1,
	.LevelGen   = 1,
}

// A step: the file's object in format i, changed in place to format i + 1.
Format_Step :: #type proc(obj: ^json.Object)

// FORMAT_MIGRATIONS[kind][i] turns format i into i + 1 (nil: no change).
FORMAT_MIGRATIONS := [Format_Kind][]Format_Step {
	.Scene      = {nil},
	.Component  = {nil},
	.CustomNode = {nil},
	.Resource   = {nil},
	.Project    = {nil},
	.Import     = {nil},
	.Tileset    = {nil},
	.LevelGen   = {nil},
}

// Format_Of: the format a parsed file says it is (0: none, a 0.x file).
Format_Of :: proc(obj: json.Object) -> int {
	#partial switch v in obj[FORMAT_KEY] {
	case json.Integer: return max(int(v), 0)
	case json.Float:   return max(int(v), 0)
	}
	return 0
}

// Format_Migrate brings a parsed file up to the current format in place and
// removes the key (readers never see it). `newer`: the file is from a newer
// Rayzr - left as it is, read as well as possible (warned about, once per
// `what` - a path or a name - when given).
Format_Migrate :: proc(kind: Format_Kind, obj: ^json.Object, what := "") -> (version: int, newer: bool) {
	if obj == nil || obj^ == nil do return 0, false
	version = Format_Of(obj^)
	delete_key(obj, FORMAT_KEY)
	if version > FORMAT_CURRENT[kind] {
		if what != "" do log.warnf("[Format] %s is format %d, from a newer Rayzr (this one reads %v format %d): loaded as well as possible", what, version, kind, FORMAT_CURRENT[kind])
		return version, true
	}
	steps := FORMAT_MIGRATIONS[kind]
	for v := version; v < FORMAT_CURRENT[kind]; v += 1 {
		if v < len(steps) && steps[v] != nil do steps[v](obj)
	}
	return version, false
}

// Format_OfText: the format of a file's text (0 when it has none or isn't
// a JSON object).
Format_OfText :: proc(data: []u8) -> int {
	val, err := json.parse(data, allocator = context.temp_allocator)
	if err != .None do return 0
	obj, isObj := val.(json.Object)
	if !isObj do return 0
	if inner, has := obj["node"].(json.Object); has && FORMAT_KEY not_in obj do return Format_Of(inner)
	return Format_Of(obj)
}

// Format_IsNewer: `version` is past what this Rayzr writes for `kind`.
Format_IsNewer :: proc(kind: Format_Kind, version: int) -> bool {
	return version > FORMAT_CURRENT[kind]
}

// Format_FileIsNewer: the file at `path` (on disk) is from a newer Rayzr -
// saving over it would lose what that version added. A missing file isn't.
Format_FileIsNewer :: proc(kind: Format_Kind, path: string) -> bool {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil do return false
	return Format_IsNewer(kind, Format_OfText(data))
}

// Format_KindOfPath: the kind of a project file by its name (ok = false: not
// a versioned kind).
Format_KindOfPath :: proc(path: string) -> (kind: Format_Kind, ok: bool) {
	switch {
	case has_suffix(path, ".scene.json"):     return .Scene, true
	case has_suffix(path, ".component.json"): return .Component, true
	case has_suffix(path, ".node.json"):      return .CustomNode, true
	case has_suffix(path, ".resource.json"):  return .Resource, true
	case has_suffix(path, ".import.json"):    return .Import, true
	case has_suffix(path, ".tileset.json"):   return .Tileset, true
	case has_suffix(path, ".levelgen.json"):  return .LevelGen, true
	case path == "project.json" || has_suffix(path, "/project.json"): return .Project, true
	}
	return {}, false
}

@(private = "file")
has_suffix :: proc(s, suffix: string) -> bool {
	return len(s) >= len(suffix) && s[len(s) - len(suffix):] == suffix
}
