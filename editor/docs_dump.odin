package editor

import "core:fmt"
import "core:os"
import "core:strings"
import e "../engine"

// ============================================================================
// Docs dump: `editor --dump-docs <file.json>` writes the node reference the
// documentation site is built from (docs/generated/nodes.json) - every node
// type in engine/node_registry.odin with its Add Node catalog entry (name,
// category, description) and its Inspector properties (kind, default value,
// range, enum names, help line from engine/property_docs.odin), plus the
// Transform properties every node shares. No window is opened.
// CI regenerates it and fails when the committed file is stale
// (scripts/docs/check_docs.py).
// ============================================================================

DocsDump_Run :: proc(path: string) -> int {
	game := new(e.Game)
	e.InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("docs", true)
	e.ProcessSceneChange(&game.sceneManager, &game.gameContext)

	w: e.Json_Writer
	w.sb = strings.builder_make()
	defer strings.builder_destroy(&w.sb)
	strings.write_string(&w.sb, "{")
	w.indent += 1
	first := true
	e.Json_Key(&w, "schema", &first)
	strings.write_string(&w.sb, "1")

	// The Transform section every node has.
	e.Json_Key(&w, "common", &first)
	base := e.Node_CreateByTypeName(scene, "TextureNode") // (has an origin)
	common := make([dynamic]e.Node_Property, context.temp_allocator)
	for name in ([]string{"position", "rotation", "scale", "origin", "layer", "zIndex", "ySort", "ySortOffset", "pauseMode", "paused", "enabled", "pixelFilter", "pixelSnap", "pixelText"}) {
		if p, ok := e.Node_BaseProperty(base, name); ok do append(&common, p)
	}
	docs_write_props(&w, common[:])

	e.Json_Key(&w, "nodes", &first)
	strings.write_string(&w.sb, "[")
	w.indent += 1
	missing := 0
	for info, i in e.NODE_TYPES {
		if i > 0 do strings.write_byte(&w.sb, ',')
		e.Json_NewLine(&w)
		strings.write_string(&w.sb, "{")
		w.indent += 1
		f := true
		e.Json_Key(&w, "type", &f)
		e.Json_String(&w, info.name)
		entry, found := docs_catalog_entry(info.name)
		if !found {
			fmt.eprintfln("[docs] %s has no Add Node catalog entry", info.name)
			missing += 1
		}
		e.Json_Key(&w, "name", &f)
		e.Json_String(&w, entry.name if found else info.name)
		e.Json_Key(&w, "category", &f)
		e.Json_String(&w, entry.category if found else "Other")
		e.Json_Key(&w, "description", &f)
		e.Json_String(&w, entry.description)
		e.Json_Key(&w, "aliases", &f)
		strings.write_byte(&w.sb, '[')
		for a, j in info.aliases {
			if j > 0 do strings.write_string(&w.sb, ", ")
			e.Json_String(&w, a)
		}
		strings.write_byte(&w.sb, ']')
		node := e.Node_CreateByTypeName(scene, info.name)
		e.Json_Key(&w, "hasOrigin", &f)
		strings.write_string(&w.sb, "true" if node != nil && e.Node_HasOrigin(node) else "false")
		e.Json_Key(&w, "properties", &f)
		if node != nil do docs_write_props(&w, e.Node_CollectProperties(node))
		else do strings.write_string(&w.sb, "[]")
		w.indent -= 1
		e.Json_NewLine(&w)
		strings.write_string(&w.sb, "}")
	}
	w.indent -= 1
	e.Json_NewLine(&w)
	strings.write_string(&w.sb, "]")
	w.indent -= 1
	e.Json_NewLine(&w)
	strings.write_string(&w.sb, "}\n")

	if err := os.write_entire_file(path, transmute([]u8)strings.to_string(w.sb)); err != nil {
		fmt.eprintfln("[docs] cannot write %s: %v", path, err)
		return 1
	}
	fmt.printfln("[docs] %d node types -> %s", len(e.NODE_TYPES), path)
	return 1 if missing > 0 else 0
}

@(private = "file")
docs_catalog_entry :: proc(typeName: string) -> (NodeCatalogEntry, bool) {
	for c in NODE_CATALOG do if c.typeName == typeName do return c, true
	return {}, false
}

@(private = "file")
docs_kind :: proc(k: e.Property_Kind) -> string {
	switch k {
	case .Float: return "number"
	case .Int: return "integer"
	case .Bool: return "boolean"
	case .Vec2: return "vec2"
	case .Color: return "color"
	case .Enum: return "enum"
	case .Bit_Set: return "flags"
	case .String: return "string"
	case .String_List: return "list"
	}
	return ""
}

@(private = "file")
docs_write_props :: proc(w: ^e.Json_Writer, props: []e.Node_Property) {
	strings.write_byte(&w.sb, '[')
	w.indent += 1
	for p, i in props {
		if i > 0 do strings.write_byte(&w.sb, ',')
		e.Json_NewLine(w)
		strings.write_byte(&w.sb, '{')
		f := true
		docs_inline_key(w, "name", &f)
		e.Json_String(w, p.name)
		docs_inline_key(w, "kind", &f)
		e.Json_String(w, docs_kind(p.kind))
		docs_inline_key(w, "owner", &f)
		e.Json_String(w, p.owner)
		docs_inline_key(w, "default", &f)
		e.Property_WriteJSON(w, p)
		if p.has_range {
			docs_inline_key(w, "min", &f)
			e.Json_Float(w, p.min)
			docs_inline_key(w, "max", &f)
			e.Json_Float(w, p.max)
		}
		if p.kind == .Enum || p.kind == .Bit_Set {
			docs_inline_key(w, "values", &f)
			strings.write_byte(&w.sb, '[')
			for n, j in e.Property_EnumNames(p) {
				if j > 0 do strings.write_string(&w.sb, ", ")
				e.Json_String(w, n)
			}
			strings.write_byte(&w.sb, ']')
		}
		if p.runtime {
			docs_inline_key(w, "runtime", &f)
			strings.write_string(&w.sb, "true")
		}
		docs_inline_key(w, "doc", &f)
		e.Json_String(w, e.Property_Doc(p))
		strings.write_byte(&w.sb, '}')
	}
	w.indent -= 1
	if len(props) > 0 do e.Json_NewLine(w)
	strings.write_byte(&w.sb, ']')
}

@(private = "file")
docs_inline_key :: proc(w: ^e.Json_Writer, key: string, first: ^bool) {
	if !first^ do strings.write_string(&w.sb, ", ")
	first^ = false
	e.Json_String(w, key)
	strings.write_string(&w.sb, ": ")
}
