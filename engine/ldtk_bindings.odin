package engine

import "base:runtime"
import "core:c"
import "core:strings"
import lua "lua54"

// ============================================================================
// LDtk in Lua. Positions are world coordinates; levels are identified by
// identifier (or iid). Full reference: engine/LDTK.md.
//
// Level node (an LdtkLevelNode):
//   Levels & worlds   ldtk_get_level_identifier()  ldtk_get_levels([world])
//                     ldtk_load_level(id)  ldtk_get_level([id])  ldtk_get_level_size()
//                     ldtk_get_level_field(name, [level])  ldtk_get_level_fields([level])
//                     ldtk_get_neighbours([level])  ldtk_level_at(x, y)
//                     ldtk_get_worlds()  ldtk_get_world()  ldtk_set_world(id, [level])
//                     ldtk_set_world_mode(on)  ldtk_is_world_mode()
//   Layers            ldtk_get_layers([level])  ldtk_set_layer_visible(name, on)
//                     ldtk_is_layer_visible(name)
//   IntGrid           ldtk_get_int_grid(layer, x, y)  ldtk_get_int_grid_name(layer, x, y)
//                     ldtk_get_int_grid_cell(layer, cx, cy, [level])
//                     ldtk_get_int_grid_values(layer)  ldtk_world_to_cell(layer, x, y)
//                     ldtk_cell_to_world(layer, cx, cy)  ldtk_get_collision(x, y)
//                     ldtk_get_triggers()
//   Tiles & enums     ldtk_get_tile(layer, x, y)  ldtk_get_tile_enums(layer, x, y)
//                     ldtk_get_enum(name)  ldtk_get_enums()
//   Entities          ldtk_get_entities([identifier])  ldtk_get_entities_by_tag(tag)
//                     ldtk_get_entity(iid)  ldtk_get_entity_node(iid)
//                     ldtk_get_entity_defs()  ldtk_get_links()
// Any spawned entity's node:
//   ldtk_entity()  ldtk_level_node()  ldtk_field(name)
//   ldtk_ref(field)  ldtk_refs([field])  ldtk_referenced_by([field])
// ============================================================================

@(private = "file")
ldtk_node_arg :: proc(L: ^lua.State) -> ^LdtkLevelNode {
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != LdtkLevelNode do return nil
	return cast(^LdtkLevelNode)node
}

@(private = "file")
str_arg :: proc(L: ^lua.State, idx: c.int) -> (string, bool) {
	if lua.type(L, idx) != .STRING do return "", false
	return strings.clone(string(lua.tostring(L, idx)), context.temp_allocator), true
}

@(private = "file")
push_str :: proc(L: ^lua.State, s: string) {
	lua.pushstring(L, strings.clone_to_cstring(s, context.temp_allocator))
}

@(private = "file")
set_str :: proc(L: ^lua.State, key: cstring, s: string) {
	push_str(L, s)
	lua.setfield(L, -2, key)
}

@(private = "file")
set_num :: proc(L: ^lua.State, key: cstring, v: f32) {
	lua.pushnumber(L, lua.Number(v))
	lua.setfield(L, -2, key)
}

@(private = "file")
set_int :: proc(L: ^lua.State, key: cstring, v: int) {
	lua.pushinteger(L, lua.Integer(v))
	lua.setfield(L, -2, key)
}

@(private = "file")
set_bool :: proc(L: ^lua.State, key: cstring, v: bool) {
	lua.pushboolean(L, b32(v))
	lua.setfield(L, -2, key)
}

@(private = "file")
push_color :: proc(L: ^lua.State, col: [4]u8) {
	lua.createtable(L, 0, 4)
	set_int(L, "r", int(col[0]))
	set_int(L, "g", int(col[1]))
	set_int(L, "b", int(col[2]))
	set_int(L, "a", int(col[3]))
}

@(private = "file")
push_tile_rect :: proc(L: ^lua.State, t: LdtkTileRect) {
	if !t.has {
		lua.pushnil(L)
		return
	}
	lua.createtable(L, 0, 5)
	set_int(L, "tileset_uid", t.tilesetUid)
	set_num(L, "x", t.rect.x)
	set_num(L, "y", t.rect.y)
	set_num(L, "w", t.rect.width)
	set_num(L, "h", t.rect.height)
}

// push_ldtk_field pushes a field value (arrays become Lua arrays).
push_ldtk_field :: proc(L: ^lua.State, f: ^LdtkFieldInstance) {
	if f.isNull {
		lua.pushnil(L)
		return
	}
	if f.isArray {
		lua.createtable(L, c.int(len(f.values)), 0)
		for &el, i in f.values {
			push_ldtk_field(L, &el)
			lua.rawseti(L, -2, lua.Integer(i + 1))
		}
		return
	}
	t := f.typeName
	if strings.has_prefix(t, "Array<") do t = t[6:len(t) - 1]
	switch {
	case t == "Int": lua.pushinteger(L, lua.Integer(f.valueInt))
	case t == "Float": lua.pushnumber(L, lua.Number(f.valueFloat))
	case t == "Bool": lua.pushboolean(L, b32(f.valueBool))
	case t == "Point":
		lua.createtable(L, 0, 2)
		set_num(L, "cx", f.valuePoint.x)
		set_num(L, "cy", f.valuePoint.y)
	case f.tile.has:
		push_tile_rect(L, f.tile)
	case:
		// String, Multilines, Enum (value id), FilePath, Color (hex), EntityRef (iid)
		push_str(L, f.valueString)
	}
}

@(private = "file")
push_fields :: proc(L: ^lua.State, fields: []LdtkFieldInstance) {
	lua.createtable(L, 0, c.int(len(fields)))
	for &f in fields {
		push_ldtk_field(L, &f)
		lua.setfield(L, -2, strings.clone_to_cstring(f.identifier, context.temp_allocator))
	}
}

// ldtk_find_layer: the layer instance + level containing world point `p`
// (the current level when p isn't given or not in world mode).
@(private = "file")
level_local :: proc(ln: ^LdtkLevelNode, world: [2]f32) -> (^LdtkLevel, [2]f32) {
	sx := ln.globalScale.x if ln.globalScale.x != 0 else 1
	sy := ln.globalScale.y if ln.globalScale.y != 0 else 1
	local := (world - ln.globalPosition) / [2]f32{sx, sy}
	if ln.worldMode {
		for lvl in ln.activeLevels {
			o := LdtkLevelNode_LevelOffset(ln, lvl)
			p := local - o
			if p.x >= 0 && p.y >= 0 && p.x < f32(lvl.pxWid) && p.y < f32(lvl.pxHei) do return lvl, p
		}
		return nil, {}
	}
	return ln.level, local
}

@(private = "file")
level_arg :: proc(L: ^lua.State, ln: ^LdtkLevelNode, idx: c.int) -> ^LdtkLevel {
	if id, ok := str_arg(L, idx); ok {
		if lvl := Ldtk_GetLevel(ln.project, id); lvl != nil do return lvl
		return Ldtk_GetLevelByIid(ln.project, id)
	}
	return ln.level
}

@(private = "file")
type_name :: proc(t: LdtkLayerType) -> string {
	switch t {
	case .IntGrid:   return "IntGrid"
	case .Entities:  return "Entities"
	case .Tiles:     return "Tiles"
	case .AutoLayer: return "AutoLayer"
	}
	return ""
}

@(private = "file")
push_entity :: proc(L: ^lua.State, ln: ^LdtkLevelNode, ent: ^LdtkEntityInstance) {
	lua.createtable(L, 0, 16)
	set_str(L, "identifier", ent.identifier)
	set_str(L, "iid", ent.iid)
	// World position of the pivot (level offset and node transform applied).
	lvl: ^LdtkLevel
	if ln != nil && ln.project != nil {
		_, lvl = Ldtk_FindEntity(ln.project, ent.iid)
	}
	off := LdtkLevelNode_LevelOffset(ln, lvl) if ln != nil else [2]f32{}
	world := ent.px + off
	if ln != nil do world = ln.globalPosition + world * ln.globalScale
	set_num(L, "x", ent.px.x) // level pixels (pivot)
	set_num(L, "y", ent.px.y)
	set_num(L, "world_x", world.x)
	set_num(L, "world_y", world.y)
	set_int(L, "cx", ent.grid.x)
	set_int(L, "cy", ent.grid.y)
	set_num(L, "width", ent.size.x)
	set_num(L, "height", ent.size.y)
	set_num(L, "pivot_x", ent.pivot.x)
	set_num(L, "pivot_y", ent.pivot.y)
	push_color(L, {ent.smartColor.r, ent.smartColor.g, ent.smartColor.b, ent.smartColor.a})
	lua.setfield(L, -2, "color")
	if lvl != nil do set_str(L, "level", lvl.identifier)
	push_tile_rect(L, ent.tile)
	lua.setfield(L, -2, "tile")
	lua.createtable(L, c.int(len(ent.tags)), 0)
	for tag, i in ent.tags {
		push_str(L, tag)
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	lua.setfield(L, -2, "tags")
	push_fields(L, ent.fields[:])
	lua.setfield(L, -2, "fields")
	// Enum fields: field name -> enum name.
	lua.newtable(L)
	for f in ent.fields {
		if f.enumName == "" do continue
		set_str(L, strings.clone_to_cstring(f.identifier, context.temp_allocator), f.enumName)
	}
	lua.setfield(L, -2, "enums")
	// References: { {field, iid, index, level}, ... }
	refs := Ldtk_EntityRefs(ent)
	lua.createtable(L, c.int(len(refs)), 0)
	for r, i in refs {
		lua.createtable(L, 0, 4)
		set_str(L, "field", r.field)
		set_str(L, "iid", r.ref.entityIid)
		set_int(L, "index", r.index + 1 if r.index >= 0 else 0)
		if ln != nil {
			if l := Ldtk_GetLevelByIid(ln.project, r.ref.levelIid); l != nil do set_str(L, "level", l.identifier)
		}
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	lua.setfield(L, -2, "refs")
	if ln != nil {
		if n, ok := ln.spawnedByIid[ent.iid]; ok && Node_IsAlive(n) {
			push_node_userdata(L, n)
			lua.setfield(L, -2, "node")
		}
	}
}

// --- levels & worlds ------------------------------------------------------------------

lua_ldtk_get_levels :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	lua.newtable(L)
	if ln == nil || ln.project == nil do return 1
	n := 0
	if wid, ok := str_arg(L, 2); ok {
		w := Ldtk_GetWorld(ln.project, wid)
		if w == nil do return 1
		for i in w.levels {
			n += 1
			push_str(L, ln.project.levels[i].identifier)
			lua.rawseti(L, -2, lua.Integer(n))
		}
		return 1
	}
	for &lvl in ln.project.levels {
		n += 1
		push_str(L, lvl.identifier)
		lua.rawseti(L, -2, lua.Integer(n))
	}
	return 1
}

lua_ldtk_load_level :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	id, ok := str_arg(L, 2)
	lua.pushboolean(L, b32(ln != nil && ok && LdtkLevelNode_LoadLevel(ln, id)))
	return 1
}

lua_ldtk_get_level :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	if ln == nil || ln.project == nil {
		lua.pushnil(L)
		return 1
	}
	lvl := level_arg(L, ln, 2)
	if lvl == nil {
		lua.pushnil(L)
		return 1
	}
	lua.createtable(L, 0, 14)
	set_str(L, "identifier", lvl.identifier)
	set_str(L, "iid", lvl.iid)
	set_int(L, "uid", lvl.uid)
	if w := Ldtk_WorldOf(ln.project, lvl); w != nil do set_str(L, "world", w.identifier)
	set_int(L, "world_x", lvl.worldX)
	set_int(L, "world_y", lvl.worldY)
	set_int(L, "depth", lvl.worldDepth)
	set_int(L, "width", lvl.pxWid)
	set_int(L, "height", lvl.pxHei)
	off := LdtkLevelNode_LevelOffset(ln, lvl)
	origin := ln.globalPosition + off * ln.globalScale
	set_num(L, "x", origin.x)
	set_num(L, "y", origin.y)
	push_color(L, {lvl.bgColor.r, lvl.bgColor.g, lvl.bgColor.b, lvl.bgColor.a})
	lua.setfield(L, -2, "bg_color")
	push_fields(L, lvl.fields[:])
	lua.setfield(L, -2, "fields")
	lua.createtable(L, c.int(len(lvl.layers)), 0)
	for &layer, i in lvl.layers {
		push_str(L, layer.identifier)
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	lua.setfield(L, -2, "layers")
	push_neighbours(L, ln, lvl)
	lua.setfield(L, -2, "neighbours")
	return 1
}

@(private = "file")
push_neighbours :: proc(L: ^lua.State, ln: ^LdtkLevelNode, lvl: ^LdtkLevel) {
	lua.createtable(L, c.int(len(lvl.neighbours)), 0)
	for nb, i in lvl.neighbours {
		lua.createtable(L, 0, 3)
		set_str(L, "dir", nb.dir)
		set_str(L, "iid", nb.levelIid)
		if other := Ldtk_GetLevelByIid(ln.project, nb.levelIid); other != nil do set_str(L, "level", other.identifier)
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
}

lua_ldtk_get_neighbours :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	if ln == nil || ln.project == nil {
		lua.newtable(L)
		return 1
	}
	lvl := level_arg(L, ln, 2)
	if lvl == nil {
		lua.newtable(L)
		return 1
	}
	push_neighbours(L, ln, lvl)
	return 1
}

lua_ldtk_get_level_size :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	if ln == nil || ln.level == nil {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	lua.pushnumber(L, lua.Number(ln.level.pxWid))
	lua.pushnumber(L, lua.Number(ln.level.pxHei))
	return 2
}

lua_ldtk_get_level_field :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	name, ok := str_arg(L, 2)
	if ln == nil || !ok || ln.project == nil {
		lua.pushnil(L)
		return 1
	}
	f := Ldtk_GetLevelField(level_arg(L, ln, 3), name)
	if f == nil do lua.pushnil(L)
	else do push_ldtk_field(L, f)
	return 1
}

lua_ldtk_get_level_fields :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	if ln == nil || ln.project == nil {
		lua.newtable(L)
		return 1
	}
	lvl := level_arg(L, ln, 2)
	if lvl == nil {
		lua.newtable(L)
		return 1
	}
	push_fields(L, lvl.fields[:])
	return 1
}

lua_ldtk_level_at :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	if ln == nil {
		lua.pushnil(L)
		return 1
	}
	lvl, _ := level_local(ln, {f32(lua.tonumber(L, 2)), f32(lua.tonumber(L, 3))})
	if lvl == nil && ln.project != nil && ln.level != nil && !ln.worldMode {
		// Single level: look the point up in the world layout.
		sx := ln.globalScale.x if ln.globalScale.x != 0 else 1
		sy := ln.globalScale.y if ln.globalScale.y != 0 else 1
		local := ([2]f32{f32(lua.tonumber(L, 2)), f32(lua.tonumber(L, 3))} - ln.globalPosition) / [2]f32{sx, sy}
		lvl = Ldtk_LevelAt(ln.project, Ldtk_WorldOf(ln.project, ln.level), local + {f32(ln.level.worldX), f32(ln.level.worldY)}, ln.level.worldDepth)
	}
	if lvl == nil do lua.pushnil(L)
	else do push_str(L, lvl.identifier)
	return 1
}

lua_ldtk_get_worlds :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	lua.newtable(L)
	if ln == nil || ln.project == nil do return 1
	for &w, i in ln.project.worlds {
		lua.createtable(L, 0, 5)
		set_str(L, "identifier", w.identifier)
		set_str(L, "iid", w.iid)
		set_str(L, "layout", w.layout)
		set_int(L, "grid_width", w.gridSize.x)
		set_int(L, "grid_height", w.gridSize.y)
		lua.createtable(L, c.int(len(w.levels)), 0)
		for li, j in w.levels {
			push_str(L, ln.project.levels[li].identifier)
			lua.rawseti(L, -2, lua.Integer(j + 1))
		}
		lua.setfield(L, -2, "levels")
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

lua_ldtk_get_world :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	if ln == nil do lua.pushnil(L)
	else do push_str(L, ln.worldIdentifier)
	return 1
}

lua_ldtk_set_world :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	id, ok := str_arg(L, 2)
	level, _ := str_arg(L, 3)
	done := ln != nil && ok && LdtkLevelNode_SetWorld(ln, id, level)
	if ln != nil && ok && !done do Script_Problem(.Warning, "ldtk_set_world: no world '%s'%s%s (nothing changed)", id, " with level " if level != "" else "", level)
	lua.pushboolean(L, b32(done))
	return 1
}

lua_ldtk_set_world_mode :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if ln := ldtk_node_arg(L); ln != nil do LdtkLevelNode_SetWorldMode(ln, bool(lua.toboolean(L, 2)))
	return 0
}

lua_ldtk_is_world_mode :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	lua.pushboolean(L, b32(ln != nil && ln.worldMode))
	return 1
}

// --- layers ---------------------------------------------------------------------------

lua_ldtk_get_layers :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	lua.newtable(L)
	if ln == nil || ln.project == nil do return 1
	lvl := level_arg(L, ln, 2)
	if lvl == nil do return 1
	for &layer, i in lvl.layers {
		lua.createtable(L, 0, 14)
		set_str(L, "identifier", layer.identifier)
		set_str(L, "type", type_name(layer.type))
		set_int(L, "grid_size", layer.gridSize)
		set_int(L, "width", layer.cWid)
		set_int(L, "height", layer.cHei)
		set_bool(L, "visible", layer.visible)
		set_num(L, "opacity", layer.opacity)
		set_num(L, "parallax_x", layer.parallax.x)
		set_num(L, "parallax_y", layer.parallax.y)
		set_bool(L, "parallax_scaling", layer.parallaxScaling)
		set_num(L, "offset_x", layer.offset.x)
		set_num(L, "offset_y", layer.offset.y)
		set_int(L, "entities", len(layer.entities))
		set_int(L, "tiles", len(layer.gridTiles) + len(layer.autoLayerTiles))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

lua_ldtk_set_layer_visible :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	name, ok := str_arg(L, 2)
	if ln == nil || !ok do return 0
	on := bool(lua.toboolean(L, 3))
	for lvl in ln.activeLevels {
		if layer := Ldtk_GetLayer(lvl, name); layer != nil do layer.visible = on
	}
	return 0
}

lua_ldtk_is_layer_visible :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	name, ok := str_arg(L, 2)
	layer := Ldtk_GetLayer(ln.level, name) if ln != nil && ok else nil
	lua.pushboolean(L, b32(layer != nil && layer.visible))
	return 1
}

// --- IntGrid --------------------------------------------------------------------------

// layer_at: the named layer of the level under world point (x, y) at stack
// idx, and the point in that level's pixels.
@(private = "file")
layer_at :: proc(L: ^lua.State, ln: ^LdtkLevelNode, nameIdx: c.int) -> (^LdtkLayerInstance, [2]f32) {
	name, ok := str_arg(L, nameIdx)
	if !ok do return nil, {}
	lvl, p := level_local(ln, {f32(lua.tonumber(L, nameIdx + 1)), f32(lua.tonumber(L, nameIdx + 2))})
	if lvl == nil do return nil, {}
	return Ldtk_GetLayer(lvl, name), p
}

lua_ldtk_get_int_grid :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	value := 0
	if ln != nil && ln.level != nil {
		if layer, p := layer_at(L, ln, 2); layer != nil do value = Ldtk_GetIntGridValueAtPixel(layer, p.x, p.y)
	}
	lua.pushinteger(L, lua.Integer(value))
	return 1
}

lua_ldtk_get_int_grid_name :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	name := ""
	if ln != nil && ln.level != nil {
		if layer, p := layer_at(L, ln, 2); layer != nil {
			if def := Ldtk_GetIntGridValueDef(ln.project, layer, Ldtk_GetIntGridValueAtPixel(layer, p.x, p.y)); def != nil do name = def.identifier
		}
	}
	push_str(L, name)
	return 1
}

lua_ldtk_get_int_grid_cell :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	name, ok := str_arg(L, 2)
	value := 0
	if ln != nil && ok && ln.project != nil {
		if layer := Ldtk_GetLayer(level_arg(L, ln, 5), name); layer != nil {
			value = Ldtk_GetIntGridValue(layer, int(lua.tointeger(L, 3)), int(lua.tointeger(L, 4)))
		}
	}
	lua.pushinteger(L, lua.Integer(value))
	return 1
}

lua_ldtk_get_int_grid_values :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	name, ok := str_arg(L, 2)
	lua.newtable(L)
	if ln == nil || !ok || ln.project == nil do return 1
	def := Ldtk_GetLayerDefByName(ln.project, name)
	if def == nil do return 1
	for v, i in def.intGridValues {
		lua.createtable(L, 0, 4)
		set_int(L, "value", v.value)
		set_str(L, "identifier", v.identifier)
		push_color(L, {v.color.r, v.color.g, v.color.b, v.color.a})
		lua.setfield(L, -2, "color")
		set_str(L, "collision", LdtkCollisionType_Name(LdtkLevelNode_CollisionRule(ln, name, v.value).type))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

lua_ldtk_world_to_cell :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	cx, cy := -1, -1
	if ln != nil && ln.level != nil {
		if layer, p := layer_at(L, ln, 2); layer != nil do cx, cy = Ldtk_PixelToCell(layer, p.x, p.y)
	}
	lua.pushinteger(L, lua.Integer(cx))
	lua.pushinteger(L, lua.Integer(cy))
	return 2
}

lua_ldtk_cell_to_world :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	name, ok := str_arg(L, 2)
	if ln == nil || !ok || ln.level == nil {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	// An unknown level: nil (not the current level's coordinates).
	if id, given := str_arg(L, 5); given && Ldtk_GetLevel(ln.project, id) == nil && Ldtk_GetLevelByIid(ln.project, id) == nil {
		lua.pushnil(L)
		return 1
	}
	lvl := level_arg(L, ln, 5)
	layer := Ldtk_GetLayer(lvl, name)
	g := f32(layer.gridSize) if layer != nil else 16
	off := layer.offset if layer != nil else {}
	local := LdtkLevelNode_LevelOffset(ln, lvl) + off + [2]f32{f32(lua.tonumber(L, 3)), f32(lua.tonumber(L, 4))} * g + g * 0.5
	world := ln.globalPosition + local * ln.globalScale
	lua.pushnumber(L, lua.Number(world.x))
	lua.pushnumber(L, lua.Number(world.y))
	return 2
}

// ldtk_get_collision(x, y) -> type ("solid", "one_way", "trigger", "none"),
// layer, value name (or number).
lua_ldtk_get_collision :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	if ln != nil && ln.level != nil {
		lvl, p := level_local(ln, {f32(lua.tonumber(L, 2)), f32(lua.tonumber(L, 3))})
		if lvl != nil {
			for &layer in lvl.layers {
				if len(layer.intGrid) == 0 do continue
				v := Ldtk_GetIntGridValueAtPixel(&layer, p.x, p.y)
				if v == 0 do continue
				rule := LdtkLevelNode_CollisionRule(ln, layer.identifier, v)
				if rule.type == .None do continue
				push_str(L, LdtkCollisionType_Name(rule.type))
				push_str(L, layer.identifier)
				def := Ldtk_GetIntGridValueDef(ln.project, &layer, v)
				if def != nil && def.identifier != "" do push_str(L, def.identifier)
				else do lua.pushinteger(L, lua.Integer(v))
				return 3
			}
		}
	}
	push_str(L, "none")
	return 1
}

lua_ldtk_get_triggers :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	lua.newtable(L)
	if ln == nil do return 1
	for a in ln.triggers {
		if !Node_IsAlive(a) do continue
		push_node_userdata(L, a)
		lua.setfield(L, -2, strings.clone_to_cstring(a.name, context.temp_allocator))
	}
	return 1
}

// --- tiles & enums --------------------------------------------------------------------

lua_ldtk_get_tile :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	if ln != nil && ln.level != nil {
		if layer, p := layer_at(L, ln, 2); layer != nil {
			if t, ok := Ldtk_GetTileAt(layer, p.x, p.y); ok {
				tsUid := layer.tilesetDefUid
				lua.createtable(L, 0, 6)
				set_int(L, "id", t.tileId)
				set_int(L, "tileset_uid", tsUid)
				set_bool(L, "flip_x", t.flipX)
				set_bool(L, "flip_y", t.flipY)
				set_str(L, "custom_data", Ldtk_GetTileCustomData(ln.project, tsUid, t.tileId))
				tags := Ldtk_GetTileEnumTags(ln.project, tsUid, t.tileId)
				lua.createtable(L, c.int(len(tags)), 0)
				for tag, i in tags {
					push_str(L, tag)
					lua.rawseti(L, -2, lua.Integer(i + 1))
				}
				lua.setfield(L, -2, "enums")
				return 1
			}
		}
	}
	lua.pushnil(L)
	return 1
}

lua_ldtk_get_tile_enums :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	lua.newtable(L)
	if ln == nil || ln.level == nil do return 1
	layer, p := layer_at(L, ln, 2)
	if layer == nil do return 1
	if t, ok := Ldtk_GetTileAt(layer, p.x, p.y); ok {
		for tag, i in Ldtk_GetTileEnumTags(ln.project, layer.tilesetDefUid, t.tileId) {
			push_str(L, tag)
			lua.rawseti(L, -2, lua.Integer(i + 1))
		}
	}
	return 1
}

lua_ldtk_get_enum :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	name, ok := str_arg(L, 2)
	en := Ldtk_GetEnum(ln.project, name) if ln != nil && ok else nil
	if en == nil {
		lua.pushnil(L)
		return 1
	}
	lua.createtable(L, c.int(len(en.values)), 0)
	for v, i in en.values {
		lua.createtable(L, 0, 4)
		set_str(L, "id", v.id)
		set_int(L, "index", i + 1)
		push_color(L, {v.color.r, v.color.g, v.color.b, v.color.a})
		lua.setfield(L, -2, "color")
		push_tile_rect(L, v.tile)
		lua.setfield(L, -2, "tile")
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

lua_ldtk_get_enums :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	lua.newtable(L)
	if ln == nil || ln.project == nil do return 1
	for en in ln.project.enums {
		lua.createtable(L, c.int(len(en.values)), 0)
		for v, i in en.values {
			push_str(L, v.id)
			lua.rawseti(L, -2, lua.Integer(i + 1))
		}
		lua.setfield(L, -2, strings.clone_to_cstring(en.identifier, context.temp_allocator))
	}
	return 1
}

// --- entities -------------------------------------------------------------------------

lua_ldtk_get_entities :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	lua.newtable(L)
	if ln == nil || ln.level == nil do return 1
	filter, _ := str_arg(L, 2)
	n := 0
	for lvl in ln.activeLevels {
		for &layer in lvl.layers {
			for &ent in layer.entities {
				if filter != "" && ent.identifier != filter do continue
				push_entity(L, ln, &ent)
				n += 1
				lua.rawseti(L, -2, lua.Integer(n))
			}
		}
	}
	return 1
}

lua_ldtk_get_entities_by_tag :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	lua.newtable(L)
	tag, ok := str_arg(L, 2)
	if ln == nil || !ok do return 1
	n := 0
	for lvl in ln.activeLevels {
		for &layer in lvl.layers {
			for &ent in layer.entities {
				has := false
				for t in ent.tags do if t == tag {has = true; break}
				if !has do continue
				push_entity(L, ln, &ent)
				n += 1
				lua.rawseti(L, -2, lua.Integer(n))
			}
		}
	}
	return 1
}

lua_ldtk_get_entity :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	iid, ok := str_arg(L, 2)
	ent: ^LdtkEntityInstance
	if ln != nil && ok do ent, _ = Ldtk_FindEntity(ln.project, iid)
	if ent == nil do lua.pushnil(L)
	else do push_entity(L, ln, ent)
	return 1
}

lua_ldtk_get_entity_node :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	iid, ok := str_arg(L, 2)
	if ln == nil || !ok {
		lua.pushnil(L)
		return 1
	}
	n := ln.spawnedByIid[iid]
	if n != nil && !Node_IsAlive(n) do n = nil // (destroyed since it was spawned)
	push_node_userdata(L, n)
	return 1
}

lua_ldtk_get_entity_defs :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	lua.newtable(L)
	if ln == nil || ln.project == nil do return 1
	for &d, i in ln.project.entityDefs {
		lua.createtable(L, 0, 6)
		set_str(L, "identifier", d.identifier)
		set_num(L, "width", d.size.x)
		set_num(L, "height", d.size.y)
		push_color(L, {d.color.r, d.color.g, d.color.b, d.color.a})
		lua.setfield(L, -2, "color")
		lua.createtable(L, c.int(len(d.tags)), 0)
		for t, j in d.tags {
			push_str(L, t)
			lua.rawseti(L, -2, lua.Integer(j + 1))
		}
		lua.setfield(L, -2, "tags")
		lua.createtable(L, c.int(len(d.fields)), 0)
		for f, j in d.fields {
			lua.createtable(L, 0, 3)
			set_str(L, "identifier", f.identifier)
			set_str(L, "type", f.typeName)
			if f.enumName != "" do set_str(L, "enum", f.enumName)
			lua.rawseti(L, -2, lua.Integer(j + 1))
		}
		lua.setfield(L, -2, "fields")
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

lua_ldtk_get_links :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ln := ldtk_node_arg(L)
	lua.newtable(L)
	if ln == nil do return 1
	for l, i in ln.links {
		lua.createtable(L, 0, 6)
		push_node_userdata(L, l.source)
		lua.setfield(L, -2, "source")
		if l.target != nil && Node_IsAlive(l.target) {
			push_node_userdata(L, l.target)
			lua.setfield(L, -2, "target")
		}
		set_str(L, "field", l.field)
		set_str(L, "source_iid", l.sourceIid)
		set_str(L, "target_iid", l.targetIid)
		set_int(L, "index", l.index + 1 if l.index >= 0 else 0)
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

// --- per-entity (any spawned node) ---------------------------------------------------

@(private = "file")
entity_arg :: proc(L: ^lua.State) -> (^Node, ^LdtkLevelNode, ^LdtkEntityInstance) {
	node, ok := to_node_userdata(L, 1)
	if !ok do return nil, nil, nil
	ln, ent := LdtkLevelNode_LevelNodeOf(node)
	return node, ln, ent
}

lua_ldtk_entity :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	_, ln, ent := entity_arg(L)
	if ent == nil do lua.pushnil(L)
	else do push_entity(L, ln, ent)
	return 1
}

lua_ldtk_level_node :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	_, ln, _ := entity_arg(L)
	push_node_userdata(L, ln)
	return 1
}

lua_ldtk_field :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	_, _, ent := entity_arg(L)
	name, ok := str_arg(L, 2)
	f := Ldtk_GetField(ent, name) if ent != nil && ok else nil
	if f == nil do lua.pushnil(L)
	else do push_ldtk_field(L, f)
	return 1
}

lua_ldtk_ref :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ln, _ := entity_arg(L)
	field, ok := str_arg(L, 2)
	if ln != nil && ok {
		for l in ln.links {
			if l.source == node && l.field == field && l.target != nil && Node_IsAlive(l.target) {
				push_node_userdata(L, l.target)
				return 1
			}
		}
	}
	lua.pushnil(L)
	return 1
}

// ldtk_refs([field]) -> nodes referenced by one field (in order), or all
// references as { {field, node, iid}, ... } when no field is given.
lua_ldtk_refs :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ln, _ := entity_arg(L)
	field, hasField := str_arg(L, 2)
	lua.newtable(L)
	if ln == nil do return 1
	n := 0
	for l in ln.links {
		if l.source != node || (hasField && l.field != field) do continue
		if hasField {
			if l.target == nil || !Node_IsAlive(l.target) do continue
			n += 1
			push_node_userdata(L, l.target)
			lua.rawseti(L, -2, lua.Integer(n))
			continue
		}
		n += 1
		lua.createtable(L, 0, 3)
		set_str(L, "field", l.field)
		set_str(L, "iid", l.targetIid)
		if l.target != nil && Node_IsAlive(l.target) {
			push_node_userdata(L, l.target)
			lua.setfield(L, -2, "node")
		}
		lua.rawseti(L, -2, lua.Integer(n))
	}
	return 1
}

// ldtk_referenced_by([field]) -> { {node, field}, ... } entities whose
// EntityRef fields point at this one.
lua_ldtk_referenced_by :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ln, _ := entity_arg(L)
	field, hasField := str_arg(L, 2)
	lua.newtable(L)
	if ln == nil do return 1
	n := 0
	for l in ln.links {
		if l.target != node || (hasField && l.field != field) || !Node_IsAlive(l.source) do continue
		n += 1
		lua.createtable(L, 0, 2)
		push_node_userdata(L, l.source)
		lua.setfield(L, -2, "node")
		set_str(L, "field", l.field)
		lua.rawseti(L, -2, lua.Integer(n))
	}
	return 1
}

// Script_RegisterLdtkBindings adds the LDtk methods to the node method table
// at the top of the stack.
Script_RegisterLdtkBindings :: proc(L: ^lua.State) {
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "ldtk_get_levels", lua_ldtk_get_levels)
	reg(L, "ldtk_load_level", lua_ldtk_load_level)
	reg(L, "ldtk_get_level", lua_ldtk_get_level)
	reg(L, "ldtk_get_level_size", lua_ldtk_get_level_size)
	reg(L, "ldtk_get_level_field", lua_ldtk_get_level_field)
	reg(L, "ldtk_get_level_fields", lua_ldtk_get_level_fields)
	reg(L, "ldtk_get_neighbours", lua_ldtk_get_neighbours)
	reg(L, "ldtk_level_at", lua_ldtk_level_at)
	reg(L, "ldtk_get_worlds", lua_ldtk_get_worlds)
	reg(L, "ldtk_get_world", lua_ldtk_get_world)
	reg(L, "ldtk_set_world", lua_ldtk_set_world)
	reg(L, "ldtk_set_world_mode", lua_ldtk_set_world_mode)
	reg(L, "ldtk_is_world_mode", lua_ldtk_is_world_mode)
	reg(L, "ldtk_get_layers", lua_ldtk_get_layers)
	reg(L, "ldtk_set_layer_visible", lua_ldtk_set_layer_visible)
	reg(L, "ldtk_is_layer_visible", lua_ldtk_is_layer_visible)
	reg(L, "ldtk_get_int_grid", lua_ldtk_get_int_grid)
	reg(L, "ldtk_get_int_grid_name", lua_ldtk_get_int_grid_name)
	reg(L, "ldtk_get_int_grid_cell", lua_ldtk_get_int_grid_cell)
	reg(L, "ldtk_get_int_grid_values", lua_ldtk_get_int_grid_values)
	reg(L, "ldtk_world_to_cell", lua_ldtk_world_to_cell)
	reg(L, "ldtk_cell_to_world", lua_ldtk_cell_to_world)
	reg(L, "ldtk_get_collision", lua_ldtk_get_collision)
	reg(L, "ldtk_get_triggers", lua_ldtk_get_triggers)
	reg(L, "ldtk_get_tile", lua_ldtk_get_tile)
	reg(L, "ldtk_get_tile_enums", lua_ldtk_get_tile_enums)
	reg(L, "ldtk_get_enum", lua_ldtk_get_enum)
	reg(L, "ldtk_get_enums", lua_ldtk_get_enums)
	reg(L, "ldtk_get_entities", lua_ldtk_get_entities)
	reg(L, "ldtk_get_entities_by_tag", lua_ldtk_get_entities_by_tag)
	reg(L, "ldtk_get_entity", lua_ldtk_get_entity)
	reg(L, "ldtk_get_entity_node", lua_ldtk_get_entity_node)
	reg(L, "ldtk_get_entity_defs", lua_ldtk_get_entity_defs)
	reg(L, "ldtk_get_links", lua_ldtk_get_links)
	reg(L, "ldtk_entity", lua_ldtk_entity)
	reg(L, "ldtk_level_node", lua_ldtk_level_node)
	reg(L, "ldtk_field", lua_ldtk_field)
	reg(L, "ldtk_ref", lua_ldtk_ref)
	reg(L, "ldtk_refs", lua_ldtk_refs)
	reg(L, "ldtk_referenced_by", lua_ldtk_referenced_by)
}
