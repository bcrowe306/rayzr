package engine

import "core:c"
import "core:strings"
import lua "lua54"

// ============================================================================
// Runtime tiles' Lua API (tile_runtime.odin, tile_data.odin):
//
//   map:tilemap_set_terrain(x, y, name)       a terrain cell, neighbours re-picked (nil / "" empties)
//   map:tilemap_terrain_names()                the tileset's terrains
//   map:tilemap_get_data(x, y, name)           a cell's value (its own, else its tile's)
//   map:tilemap_set_data(x, y, name, value)    a cell's own value (until its tile changes)
//   map:tilemap_tile_data(tile, name)          a tile's value (the tileset's)
//   map:tilemap_damage(x, y, amount)           -> health left, destroyed
//   map:tilemap_tile_rect(tile)                -> x, y, w, h in the tileset image
//   map:tilemap_cell_hit(contact)              -> x, y, tile: the cell a collision touched
//   sprite:atlas_show_tile(map, tile)          an Atlas Sprite shows a map's tile
// ============================================================================

@(private = "file")
tr_map :: proc(L: ^lua.State, fn: string) -> ^TileMapNode {
	n, ok := to_node_userdata(L, 1)
	if !ok || n == nil || n.typeId != TileMapNode {
		Script_Problem(.Warning, "%s: called on something that isn't a Tile Map", fn)
		return nil
	}
	return cast(^TileMapNode)n
}

@(private = "file")
tr_cell :: proc(L: ^lua.State) -> [2]int {
	return {int(lua.tointeger(L, 2)), int(lua.tointeger(L, 3))}
}

@(private = "file")
tr_push_value :: proc(L: ^lua.State, v: Tile_Value) {
	switch x in v {
	case f64:    lua.pushnumber(L, lua.Number(x))
	case bool:   lua.pushboolean(L, b32(x))
	case string: lua.pushstring(L, strings.clone_to_cstring(x, context.temp_allocator))
	case:        lua.pushnil(L)
	}
}

// tr_arg_value: a Lua value as the field's type (ok = false: the wrong type).
@(private = "file")
tr_arg_value :: proc(L: ^lua.State, idx: c.int, t: Tile_Field_Type) -> (Tile_Value, bool) {
	#partial switch lua.type(L, idx) {
	case .NUMBER:  if t == .Number do return f64(lua.tonumber(L, idx)), true
	case .BOOLEAN: if t == .Bool do return bool(lua.toboolean(L, idx)), true
	case .STRING:  if t == .String do return strings.clone(string(lua.tostring(L, idx)), context.temp_allocator), true
	}
	return nil, false
}

@(private = "file")
lua_tilemap_set_terrain :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	tm := tr_map(L, "tilemap_set_terrain")
	if tm == nil {
		lua.pushboolean(L, false)
		return 1
	}
	name := ""
	if lua.type(L, 4) == .STRING do name = string(lua.tostring(L, 4))
	if t, _ := Terrains_Find(tm.sidecar, name); name != "" && t == nil {
		Script_Problem(.Warning, "tilemap_set_terrain: the tileset has no terrain \"%s\"", name)
		lua.pushboolean(L, false)
		return 1
	}
	lua.pushboolean(L, b32(TileMapNode_SetTerrain(tm, tr_cell(L), name)))
	return 1
}

@(private = "file")
lua_tilemap_terrain_names :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	tm := tr_map(L, "tilemap_terrain_names")
	lua.newtable(L)
	if tm == nil || tm.sidecar == nil do return 1
	for t, i in tm.sidecar.terrains {
		lua.pushstring(L, strings.clone_to_cstring(t.name, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

@(private = "file")
lua_tilemap_get_data :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	tm := tr_map(L, "tilemap_get_data")
	if tm == nil || lua.type(L, 4) != .STRING {
		lua.pushnil(L)
		return 1
	}
	v, ok := TileMapNode_CellData(tm, tr_cell(L), string(lua.tostring(L, 4)))
	if ok do tr_push_value(L, v)
	else do lua.pushnil(L)
	return 1
}

@(private = "file")
lua_tilemap_set_data :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	tm := tr_map(L, "tilemap_set_data")
	if tm == nil || lua.type(L, 4) != .STRING do return 0
	name := string(lua.tostring(L, 4))
	fi := TileData_FieldIndex(tm.sidecar, name)
	if fi < 0 {
		Script_Problem(.Warning, "tilemap_set_data: the tileset has no field \"%s\" (the Tile Map tab's Data page)", name)
		return 0
	}
	v, ok := tr_arg_value(L, 5, tm.sidecar.fields[fi].type)
	if !ok {
		Script_Problem(.Warning, "tilemap_set_data: \"%s\" is a %s", name, TILE_FIELD_TYPE_NAMES[tm.sidecar.fields[fi].type])
		return 0
	}
	TileMapNode_SetCellData(tm, tr_cell(L), name, v)
	return 0
}

@(private = "file")
lua_tilemap_tile_data :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	tm := tr_map(L, "tilemap_tile_data")
	if tm == nil || tm.sidecar == nil || lua.type(L, 3) != .STRING {
		lua.pushnil(L)
		return 1
	}
	v, ok := TileData_Get(tm.sidecar, i32(lua.tointeger(L, 2)), string(lua.tostring(L, 3)))
	if ok do tr_push_value(L, v)
	else do lua.pushnil(L)
	return 1
}

@(private = "file")
lua_tilemap_damage :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	tm := tr_map(L, "tilemap_damage")
	if tm == nil {
		lua.pushnil(L)
		lua.pushboolean(L, false)
		return 2
	}
	amount := f64(lua.tonumber(L, 4)) if lua.type(L, 4) == .NUMBER else 1
	health, destroyed, ok := TileMapNode_Damage(tm, tr_cell(L), amount)
	if !ok {
		lua.pushnil(L)
		lua.pushboolean(L, false)
		return 2
	}
	lua.pushnumber(L, lua.Number(health))
	lua.pushboolean(L, b32(destroyed))
	return 2
}

@(private = "file")
lua_tilemap_tile_rect :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	tm := tr_map(L, "tilemap_tile_rect")
	if tm == nil {
		lua.pushnil(L)
		return 1
	}
	r, ok := TileMapNode_TileImageRect(tm, i32(lua.tointeger(L, 2)))
	if !ok {
		lua.pushnil(L)
		return 1
	}
	for v in r do lua.pushnumber(L, lua.Number(v))
	return 4
}

// map:tilemap_cell_hit(contact) - a body's own collision contact with the map.
@(private = "file")
lua_tilemap_cell_hit :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	tm := tr_map(L, "tilemap_cell_hit")
	if tm == nil || lua.type(L, 2) != .TABLE {
		lua.pushnil(L)
		return 1
	}
	num :: proc(L: ^lua.State, k: cstring) -> f32 {
		lua.getfield(L, 2, k)
		defer lua.pop(L, 1)
		return f32(lua.tonumber(L, -1))
	}
	p := [2]f32{num(L, "point_x"), num(L, "point_y")}
	n := [2]f32{num(L, "normal_x"), num(L, "normal_y")}
	cell, tile := TileMapNode_HitCell(tm, p, n)
	lua.pushinteger(L, lua.Integer(cell.x))
	lua.pushinteger(L, lua.Integer(cell.y))
	lua.pushinteger(L, lua.Integer(tile))
	return 3
}

// sprite:atlas_show_tile(map, tile) -> ok
@(private = "file")
lua_atlas_show_tile :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	n, ok := to_node_userdata(L, 1)
	m, mok := to_node_userdata(L, 2)
	if !ok || n == nil || n.typeId != AtlasSpriteNode || !mok || m == nil || m.typeId != TileMapNode {
		Script_Problem(.Warning, "atlas_show_tile: call it on an Atlas Sprite, with a Tile Map")
		lua.pushboolean(L, false)
		return 1
	}
	lua.pushboolean(L, b32(AtlasSprite_ShowTile(cast(^AtlasSpriteNode)n, cast(^TileMapNode)m, i32(lua.tointeger(L, 3)))))
	return 1
}

// TileRuntime_RegisterBindings adds them to the node methods table on the stack.
TileRuntime_RegisterBindings :: proc(L: ^lua.State) {
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "tilemap_set_terrain", lua_tilemap_set_terrain)
	reg(L, "tilemap_terrain_names", lua_tilemap_terrain_names)
	reg(L, "tilemap_get_data", lua_tilemap_get_data)
	reg(L, "tilemap_set_data", lua_tilemap_set_data)
	reg(L, "tilemap_tile_data", lua_tilemap_tile_data)
	reg(L, "tilemap_damage", lua_tilemap_damage)
	reg(L, "tilemap_tile_rect", lua_tilemap_tile_rect)
	reg(L, "tilemap_cell_hit", lua_tilemap_cell_hit)
	reg(L, "atlas_show_tile", lua_atlas_show_tile)
}
