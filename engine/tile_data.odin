package engine

import "core:encoding/json"
import "core:fmt"
import "core:strings"

// ============================================================================
// Tile data: values a tileset's tiles carry - "breakable", "health",
// "sound" - kept with its terrains in <image>.tileset.json:
//
//   "fields": [{"name": "health", "type": "number", "default": 3}, ...],
//   "data":   [[tile, {"health": 5, "breakable": true}], ...]
//
// A field has a type (number, bool, string) and a default; a tile sets only
// the values that differ. Every map using the tileset shares them. On a
// map, a cell can also hold values of its own (TileMapNode_SetCellData:
// a cracked block's health left), which go when its tile changes
// (tile_runtime.odin).
// ============================================================================

Tile_Field_Type :: enum {
	Number,
	Bool,
	String,
}

TILE_FIELD_TYPE_NAMES := [Tile_Field_Type]string{.Number = "number", .Bool = "bool", .String = "string"}

Tile_Value :: union {
	f64,
	bool,
	string,
}

Tile_Field :: struct {
	name:    string,
	type:    Tile_Field_Type,
	default: Tile_Value,
}

// TileData_Parse reads "fields" and "data" (Terrains_Parse).
TileData_Parse :: proc(ts: ^Tile_Terrains, root: json.Object) {
	a := ts.allocator
	if ts.fields == nil do ts.fields = make([dynamic]Tile_Field, a)
	if ts.data == nil do ts.data = make(map[i32]map[string]Tile_Value, allocator = a)
	if fields, ok := root["fields"].(json.Array); ok do for v in fields {
		obj, isObj := v.(json.Object)
		if !isObj do continue
		name, _ := obj["name"].(json.String)
		if name == "" || TileData_FieldIndex(ts, string(name)) >= 0 do continue
		f := Tile_Field{name = strings.clone(string(name), a)}
		if t, tok := obj["type"].(json.String); tok do for tn, k in TILE_FIELD_TYPE_NAMES do if string(t) == tn do f.type = k
		f.default = tile_value_from_json(obj["default"], f.type, a)
		append(&ts.fields, f)
	}
	if data, ok := root["data"].(json.Array); ok do for v in data {
		pair, isArr := v.(json.Array)
		if !isArr || len(pair) < 2 do continue
		tile, _ := json_number(pair[0])
		vals, isObj := pair[1].(json.Object)
		if !isObj do continue
		for k, jv in vals {
			fi := TileData_FieldIndex(ts, k)
			if fi < 0 do continue
			TileData_Set(ts, i32(tile), k, tile_value_from_json(jv, ts.fields[fi].type, context.temp_allocator))
		}
	}
}

@(private = "file")
tile_value_from_json :: proc(v: json.Value, t: Tile_Field_Type, allocator := context.allocator) -> Tile_Value {
	switch t {
	case .Number:
		n, _ := json_number(v)
		return f64(n)
	case .Bool:
		b, _ := v.(json.Boolean)
		return bool(b)
	case .String:
		s, _ := v.(json.String)
		return strings.clone(string(s), allocator)
	}
	return nil
}

// TileData_Serialize writes "fields" and "data" (nothing when there are no fields).
TileData_Serialize :: proc(ts: ^Tile_Terrains, w: ^Json_Writer) {
	if len(ts.fields) == 0 do return
	strings.write_string(&w.sb, ",\n\"fields\": [")
	for f, i in ts.fields {
		strings.write_string(&w.sb, "," if i > 0 else "")
		strings.write_string(&w.sb, "\n  {\"name\": ")
		Json_String(w, f.name)
		strings.write_string(&w.sb, ", \"type\": ")
		Json_String(w, TILE_FIELD_TYPE_NAMES[f.type])
		strings.write_string(&w.sb, ", \"default\": ")
		tile_value_write(w, f.default)
		strings.write_byte(&w.sb, '}')
	}
	strings.write_string(&w.sb, "\n]")
	// The tiles in order (stable files).
	tiles := make([dynamic]i32, context.temp_allocator)
	for t, vals in ts.data do if len(vals) > 0 do append(&tiles, t)
	for i in 1 ..< len(tiles) do for j := i; j > 0 && tiles[j] < tiles[j - 1]; j -= 1 do tiles[j], tiles[j - 1] = tiles[j - 1], tiles[j]
	if len(tiles) == 0 do return
	strings.write_string(&w.sb, ",\n\"data\": [")
	for t, i in tiles {
		vals := ts.data[t]
		fmt.sbprintf(&w.sb, "%s\n  [%d, {{", "," if i > 0 else "", t)
		k := 0
		for f in ts.fields {
			v, has := vals[f.name]
			if !has do continue
			strings.write_string(&w.sb, ", " if k > 0 else "")
			Json_String(w, f.name)
			strings.write_string(&w.sb, ": ")
			tile_value_write(w, v)
			k += 1
		}
		strings.write_string(&w.sb, "}]")
	}
	strings.write_string(&w.sb, "\n]")
}

@(private = "file")
tile_value_write :: proc(w: ^Json_Writer, v: Tile_Value) {
	switch x in v {
	case f64:    Json_Float(w, f32(x))
	case bool:   strings.write_string(&w.sb, "true" if x else "false")
	case string: Json_String(w, x)
	case:        strings.write_string(&w.sb, "null")
	}
}

TileData_Destroy :: proc(ts: ^Tile_Terrains) {
	for f in ts.fields {
		delete(f.name, ts.allocator)
		if s, ok := f.default.(string); ok do delete(s, ts.allocator)
	}
	delete(ts.fields)
	for _, vals in ts.data {
		for k, v in vals {
			delete(k, ts.allocator)
			if s, ok := v.(string); ok do delete(s, ts.allocator)
		}
		delete(vals)
	}
	delete(ts.data)
}

TileData_FieldIndex :: proc(ts: ^Tile_Terrains, name: string) -> int {
	if ts == nil do return -1
	for f, i in ts.fields do if f.name == name do return i
	return -1
}

// TileData_AddField: a new field (false: the name is taken or empty).
TileData_AddField :: proc(ts: ^Tile_Terrains, name: string, type: Tile_Field_Type) -> bool {
	if name == "" || TileData_FieldIndex(ts, name) >= 0 do return false
	f := Tile_Field{name = strings.clone(name, ts.allocator), type = type}
	switch type {
	case .Number: f.default = f64(0)
	case .Bool:   f.default = false
	case .String: f.default = strings.clone("", ts.allocator)
	}
	append(&ts.fields, f)
	return true
}

// TileData_RemoveField drops a field and every tile's value of it.
TileData_RemoveField :: proc(ts: ^Tile_Terrains, name: string) {
	fi := TileData_FieldIndex(ts, name)
	if fi < 0 do return
	for _, &vals in ts.data {
		for k, v in vals do if k == name {
			key := k
			if s, ok := v.(string); ok do delete(s, ts.allocator)
			delete_key(&vals, name)
			delete(key, ts.allocator)
			break
		}
	}
	f := ts.fields[fi]
	delete(f.name, ts.allocator)
	if s, ok := f.default.(string); ok do delete(s, ts.allocator)
	ordered_remove(&ts.fields, fi)
}

// TileData_RenameField renames a field (and the tiles' values of it).
TileData_RenameField :: proc(ts: ^Tile_Terrains, from, to: string) -> bool {
	fi := TileData_FieldIndex(ts, from)
	if fi < 0 || to == "" || TileData_FieldIndex(ts, to) >= 0 do return false
	for _, &vals in ts.data {
		for k, v in vals do if k == from {
			key := k
			delete_key(&vals, from)
			delete(key, ts.allocator)
			vals[strings.clone(to, ts.allocator)] = v
			break
		}
	}
	delete(ts.fields[fi].name, ts.allocator)
	ts.fields[fi].name = strings.clone(to, ts.allocator)
	return true
}

// TileData_SetDefault: a field's default (a copy is kept).
TileData_SetDefault :: proc(ts: ^Tile_Terrains, name: string, v: Tile_Value) {
	fi := TileData_FieldIndex(ts, name)
	if fi < 0 do return
	f := &ts.fields[fi]
	if s, ok := f.default.(string); ok do delete(s, ts.allocator)
	f.default = tile_value_clone(v, ts.allocator)
}

// TileData_Get: a tile's value of a field (its own, else the field's
// default); ok = false when there's no such field.
TileData_Get :: proc(ts: ^Tile_Terrains, tile: i32, name: string) -> (v: Tile_Value, ok: bool) {
	fi := TileData_FieldIndex(ts, name)
	if fi < 0 do return nil, false
	if vals, has := ts.data[tile]; has {
		if x, set := vals[name]; set do return x, true
	}
	return ts.fields[fi].default, true
}

// TileData_Has: the tile sets a value of its own for the field.
TileData_Has :: proc(ts: ^Tile_Terrains, tile: i32, name: string) -> bool {
	if ts == nil do return false
	vals, has := ts.data[tile]
	return has && name in vals
}

// TileData_Set: a tile's value of a field (a copy is kept).
TileData_Set :: proc(ts: ^Tile_Terrains, tile: i32, name: string, v: Tile_Value) {
	if TileData_FieldIndex(ts, name) < 0 do return
	vals, has := ts.data[tile]
	if !has do vals = make(map[string]Tile_Value, allocator = ts.allocator)
	if old, set := vals[name]; set {
		if s, ok := old.(string); ok do delete(s, ts.allocator)
		vals[name] = tile_value_clone(v, ts.allocator)
	} else {
		vals[strings.clone(name, ts.allocator)] = tile_value_clone(v, ts.allocator)
	}
	ts.data[tile] = vals
}

// TileData_Clear: the tile's own value goes (back to the default).
TileData_Clear :: proc(ts: ^Tile_Terrains, tile: i32, name: string) {
	vals, has := ts.data[tile]
	if !has do return
	for k, v in vals do if k == name {
		key := k
		if s, ok := v.(string); ok do delete(s, ts.allocator)
		delete_key(&vals, name)
		delete(key, ts.allocator)
		break
	}
	ts.data[tile] = vals
}

tile_value_clone :: proc(v: Tile_Value, allocator := context.allocator) -> Tile_Value {
	if s, ok := v.(string); ok do return strings.clone(s, allocator)
	return v
}

// Tile_ValueText: a value as text (the editor, tests).
Tile_ValueText :: proc(v: Tile_Value) -> string {
	switch x in v {
	case f64:    return fmt.tprintf("%g", x)
	case bool:   return "true" if x else "false"
	case string: return x
	}
	return ""
}
