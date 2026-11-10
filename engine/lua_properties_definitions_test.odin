package engine

import "core:fmt"
import "core:strings"
import "core:testing"
import "core:unicode"

// The per-class get_property / set_property declarations in engine_api.lua
// (between the "node properties" markers): each class's property paths as
// an alias (type and help on completion) and overloads typing the value.
// On drift the test prints the block to paste.
@(test)
test_lua_node_properties_definitions :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("props", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)

	sb := strings.builder_make(context.temp_allocator)
	bigEnums = make(map[string]string, allocator = context.temp_allocator)
	bigEnumOrder = make([dynamic]string, context.temp_allocator)
	strings.write_string(&sb, "-- node properties begin (generated from the engine: lua_properties_definitions_test.odin)\n")
	for info in NODE_TYPES {
		n := Node_CreateByTypeName(scene, info.name)
		if n == nil do continue
		props := make([dynamic]Node_Property, context.temp_allocator)
		for name in ([]string{"position", "scale", "rotation", "origin", "layer", "zIndex", "ySort", "ySortOffset", "pauseMode", "paused", "enabled", "visible", "pixelFilter", "pixelSnap", "pixelText"}) {
			if p, ok := Node_BaseProperty(n, name); ok do append(&props, p)
		}
		own := Node_CollectProperties(n)
		for p in own do append(&props, p)
		for name in ([]string{"fps", "defaultAnimation"}) {
			if p, ok := Node_BaseProperty(n, name); ok do append(&props, p)
		}
		if info.name != "Node" && len(own) == 0 && !Node_HasOrigin(n) && n.typeId != AnimationPlayerNode do continue // Node's own declarations cover it
		cls := info.name
		// Property-style access: node.<property> (paths without dots).
		fmt.sbprintf(&sb, "\n---@class %s\n", cls)
		// Scripts use the snake_case names (#327); the Inspector's camelCase
		// ones still work (scene files use them).
		for p in props {
			ty := lua_prop_type(p)
			if ty == "" || strings.contains(p.name, ".") do continue
			doc := Property_Doc(p)
			if len(doc) > 90 do doc = strings.concatenate({doc[:87], "..."}, context.temp_allocator)
			name := Property_ScriptName(n, p.name)
			fmt.sbprintf(&sb, "---@field %s %s %s\n", name, ty, doc)
			if name != p.name && name == Property_SnakeName(p.name) do fmt.sbprintf(&sb, "---@field %s %s Same as %s (the Inspector's name)\n", p.name, ty, name)
		}
		fmt.sbprintf(&sb, "\n---@alias %sProperty\n", cls)
		for p in props {
			ty := lua_prop_type(p)
			if ty == "" do continue
			doc := Property_Doc(p)
			if len(doc) > 90 do doc = strings.concatenate({doc[:87], "..."}, context.temp_allocator)
			fmt.sbprintf(&sb, "---| %q # %s%s%s\n", Property_ScriptName(n, p.name), ty, " (runtime)" if p.runtime else "", fmt.tprintf(" - %s", doc) if doc != "" else "")
		}
		// The examples use the class's own first scriptable property (else position).
		ex := Node_Property{name = "position", kind = .Vec2}
		for p in own {
			if lua_prop_type(p) != "" && !p.runtime && !strings.contains(p.name, ".") {ex = p; break}
		}
		ex.name = Property_ScriptName(n, ex.name)
		fmt.sbprintf(&sb, "\n---Reads an Inspector property by its path (vectors and colours as tables); \"script.<name>\" reads a field of the node's script.\n---\n---Example: `local value = self.node:get_property(%q)`\n---@param path %sProperty|string The property's path in snake_case (\"position\", \"z_index\", \"emitter.amount\"; the Inspector's camelCase names work too) or \"script.<field>\"\n---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)\n", ex.name, cls)
		for p in props {
			if ty := lua_prop_type(p); ty != "" do fmt.sbprintf(&sb, "---@overload fun(self: %s, path: %q): %s\n", cls, Property_ScriptName(n, p.name), ty)
		}
		fmt.sbprintf(&sb, "function %s:get_property(path) end\n", cls)
		fmt.sbprintf(&sb, "\n---Sets an Inspector property by its path: vectors as {{x, y}} or x, y; colours as {{r, g, b[, a]}} 0..1 or \"#rrggbb[aa]\"; enums by name; \"script.<name>\" a field of the node's script.\n---\n---Example: `self.node:set_property(%q, %s)`\n---@param path %sProperty|string The property's path in snake_case (the Inspector's camelCase names work too), or \"script.<field>\"\n---@param value any The new value: a number, boolean, string or enum name; a vector as {{x, y}} (or x here and y next); a colour as {{r, g, b[, a]}} 0..1 or \"#rrggbb[aa]\"\n---@param y? number A vector's y when value is its x\n", ex.name, lua_example_value(ex), cls)
		for p in props {
			ty := lua_prop_type(p)
			if ty == "" do continue
			if p.kind == .Vec2 do fmt.sbprintf(&sb, "---@overload fun(self: %s, path: %q, x: number|Vec2|number[], y?: number)\n", cls, Property_ScriptName(n, p.name))
			else do fmt.sbprintf(&sb, "---@overload fun(self: %s, path: %q, value: %s)\n", cls, Property_ScriptName(n, p.name), ty)
		}
		fmt.sbprintf(&sb, "function %s:set_property(path, value, y) end\n", cls)
	}
	// The long enums (the icon names), one alias each, a value per line:
	// on one line LuaLS stops reading the class's annotations (#403).
	for alias in bigEnumOrder {
		fmt.sbprintf(&sb, "\n---@alias %s\n", alias)
		for e in strings.split(bigEnums[alias], "\x00", context.temp_allocator) do fmt.sbprintf(&sb, "---| %q\n", e)
	}
	strings.write_string(&sb, "-- node properties end\n")
	want := strings.to_string(sb)

	api := ENGINE_API_LUA
	a := strings.index(api, "-- node properties begin")
	b := strings.index(api, "-- node properties end\n")
	have := api[a:b + len("-- node properties end\n")] if a >= 0 && b > a else ""
	if have != want {
		fmt.println("---- paste into engine_api.lua ----")
		fmt.print(want)
		fmt.println("---- end ----")
	}
	testing.expect(t, have == want, "engine_api.lua's per-class property declarations match the engine")
}

// lua_example_value: a sample value of a property's type for the examples.
@(private = "file")
lua_example_value :: proc(p: Node_Property) -> string {
	#partial switch p.kind {
	case .Float:  return "1.5"
	case .Int:    return "2"
	case .Bool:   return "true"
	case .Vec2:   return "100, 50"
	case .Color:  return "\"#ff8800\""
	case .String: return "\"text\""
	case .Enum:
		names := Property_EnumNames(p)
		if len(names) > 0 do return fmt.tprintf("%q", names[len(names) > 1 ? 1 : 0])
	}
	return "nil"
}

// Enums longer than this are written as an alias (bigEnums: alias -> the
// values joined by NULs, in bigEnumOrder).
@(private = "file")
BIG_ENUM :: 64
@(private = "file")
bigEnums: map[string]string
@(private = "file")
bigEnumOrder: [dynamic]string

// lua_prop_type: the Lua type of a property's value ("" = not scriptable).
@(private = "file")
lua_prop_type :: proc(p: Node_Property) -> string {
	switch p.kind {
	case .Float:  return "number"
	case .Int:    return "integer"
	case .Bool:   return "boolean"
	case .Vec2:   return "Vec2"
	case .Color:  return "number[]"
	case .String: return "string"
	case .String_List: return "string[]"
	case .Enum:
		values := Property_EnumNames(p)
		if len(values) > BIG_ENUM {
			// An alias named after the property ("icon" -> IconName).
			key := strings.join(values, "\x00", context.temp_allocator)
			for alias, k in bigEnums do if k == key do return alias
			base := Property_SnakeName(p.name)
			sb := strings.builder_make(context.temp_allocator)
			upper := true
			for ch in base {
				if ch == '_' {upper = true; continue}
				strings.write_rune(&sb, unicode.to_upper(ch) if upper else ch)
				upper = false
			}
			alias := fmt.tprintf("%sName", strings.to_string(sb))
			if alias in bigEnums do alias = fmt.tprintf("%s%d", alias, len(bigEnums) + 1)
			bigEnums[alias] = key
			append(&bigEnumOrder, alias)
			return alias
		}
		names := make([dynamic]string, context.temp_allocator)
		for e in values do append(&names, fmt.tprintf("%q", e))
		return strings.join(names[:], "|", context.temp_allocator)
	case .Bit_Set:
	}
	return ""
}
