package engine

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:reflect"
import "core:strconv"
import "core:strings"
import lua "lua54"
import uilib "../ui"

// ============================================================================
// UI node content as lines (#227): the lists UI nodes show - a Dropdown's
// items, a Table's rows, a Tree View's items... - edited in the Inspector,
// saved with the scene and set from Lua (set_property / ui_set_items).
//
// Lists of plain text are gui-tagged [dynamic]string fields (reflected as
// String_List). Lists of structs are read and written here, one item a line:
//   Tree View, Bullet / Numbered List  "  Child" (2 spaces a level deeper)
//   Table columns                      "Title" or "Title|width" (<= 1: share)
//   Table rows                         "cell|cell|cell"
//   Toolbar items                      "Icon|Label|Tooltip" ("toggle:" first
//                                      makes a toggle), "-" a separator,
//                                      "~" a spacer
//   XY Plot points                     "x, y"
// ============================================================================

UI_List_Prop :: struct {
	type:  typeid,
	name:  string,
	owner: string,
	get:   proc(node: ^Node, allocator := context.temp_allocator) -> []string,
	set:   proc(node: ^Node, items: []string),
}

UI_LIST_PROPS := [?]UI_List_Prop{
	{UITreeViewNode, "items", "UITreeViewNode", tree_items_get, tree_items_set},
	{UIUnorderedListNode, "items", "UIUnorderedListNode", ul_items_get, ul_items_set},
	{UIOrderedListNode, "items", "UIOrderedListNode", ol_items_get, ol_items_set},
	{UITableNode, "columns", "UITableNode", table_columns_get, table_columns_set},
	{UITableNode, "rows", "UITableNode", table_rows_get, table_rows_set},
	{UIToolbarNode, "items", "UIToolbarNode", toolbar_items_get, toolbar_items_set},
	{UIXYPlotNode, "points", "UIXYPlotNode", plot_points_get, plot_points_set},
	{UIXYPlotNode, "secondaryPoints", "UIXYPlotNode", plot_points2_get, plot_points2_set},
}

// UI_MainList: the list ui_set_items / ui_get_items mean for a node type.
UI_MainList :: proc(node: ^Node) -> string {
	switch node.typeId {
	case UIRadioGroupNode:    return "options"
	case UITableNode:         return "rows"
	case UIXYPlotNode:        return "points"
	case UITabContainerNode:  return "tabNames"
	case UINotchedSliderNode: return "notchLabels"
	case UIDropdownNode, UIListViewNode, UITreeViewNode, UIUnorderedListNode, UIOrderedListNode, UIToolbarNode:
		return "items"
	}
	return ""
}

// --- lines -------------------------------------------------------------------------

// (Leading spaces, 2 a level: the depth; the rest: the text.)
@(private = "file")
line_depth :: proc(line: string) -> (depth: int, text: string) {
	n := 0
	for n < len(line) && line[n] == ' ' do n += 1
	return n / 2, strings.trim_space(line)
}

@(private = "file")
indented :: proc(depth: int, text: string, allocator := context.temp_allocator) -> string {
	return strings.concatenate({strings.repeat("  ", max(depth, 0), context.temp_allocator), text}, allocator)
}

@(private = "file")
fields :: proc(line: string) -> []string {
	parts := strings.split(line, "|", context.temp_allocator)
	for &p in parts do p = strings.trim_space(p)
	return parts
}

// --- Tree View ---------------------------------------------------------------------

@(private = "file")
tree_items_get :: proc(node: ^Node, allocator := context.temp_allocator) -> []string {
	tv := cast(^UITreeViewNode)node
	out := make([]string, len(tv.items), allocator)
	for it, i in tv.items do out[i] = indented(it.depth, it.label, allocator)
	return out
}

@(private = "file")
tree_items_set :: proc(node: ^Node, items: []string) {
	tv := cast(^UITreeViewNode)node
	if tv.items == nil do tv.items = make([dynamic]uilib.TreeViewItem, tv.allocator)
	clear(&tv.items)
	for line, i in items {
		d, text := line_depth(line)
		if len(tv.items) == 0 do d = 0
		else do d = min(d, tv.items[len(tv.items) - 1].depth + 1) // (one level at a time)
		append(&tv.items, uilib.TreeViewItem{id = i + 1, label = strings.clone(text, tv.allocator), depth = d})
	}
	// Parents and last children from the depths.
	for &it, i in tv.items {
		it.hasChildren = i + 1 < len(tv.items) && tv.items[i + 1].depth > it.depth
		it.isLastChild = true
		for j in i + 1 ..< len(tv.items) {
			if tv.items[j].depth < it.depth do break
			if tv.items[j].depth == it.depth {it.isLastChild = false; break}
		}
	}
}

// --- Bullet / Numbered List --------------------------------------------------------

@(private = "file")
list_items_get :: proc(items: []uilib.ListItem, allocator: runtime.Allocator) -> []string {
	out := make([]string, len(items), allocator)
	for it, i in items do out[i] = indented(it.depth, it.text, allocator)
	return out
}

@(private = "file")
list_items_set :: proc(list: ^[dynamic]uilib.ListItem, node: ^Node, items: []string) {
	if list^ == nil do list^ = make([dynamic]uilib.ListItem, node.allocator)
	clear(list)
	for line in items {
		d, text := line_depth(line)
		append(list, uilib.ListItem{text = strings.clone(text, node.allocator), depth = d})
	}
}

@(private = "file")
ul_items_get :: proc(node: ^Node, allocator := context.temp_allocator) -> []string {
	return list_items_get((cast(^UIUnorderedListNode)node).items[:], allocator)
}

@(private = "file")
ul_items_set :: proc(node: ^Node, items: []string) {
	ul := cast(^UIUnorderedListNode)node
	list_items_set(&ul.items, node, items)
}

@(private = "file")
ol_items_get :: proc(node: ^Node, allocator := context.temp_allocator) -> []string {
	return list_items_get((cast(^UIOrderedListNode)node).items[:], allocator)
}

@(private = "file")
ol_items_set :: proc(node: ^Node, items: []string) {
	ol := cast(^UIOrderedListNode)node
	list_items_set(&ol.items, node, items)
}

// --- Table -------------------------------------------------------------------------

@(private = "file")
table_columns_get :: proc(node: ^Node, allocator := context.temp_allocator) -> []string {
	tbl := cast(^UITableNode)node
	out := make([]string, len(tbl.columns), allocator)
	for col, i in tbl.columns {
		out[i] = col.title if col.width == 0 else fmt.aprintf("%s|%g", col.title, col.width, allocator = allocator)
	}
	return out
}

@(private = "file")
table_columns_set :: proc(node: ^Node, items: []string) {
	tbl := cast(^UITableNode)node
	if tbl.columns == nil do tbl.columns = make([dynamic]uilib.TableColumn, tbl.allocator)
	clear(&tbl.columns)
	for line in items {
		f := fields(line)
		col := uilib.TableColumn{title = strings.clone(f[0], tbl.allocator), sortable = true}
		if len(f) > 1 do col.width, _ = strconv.parse_f32(f[1])
		append(&tbl.columns, col)
	}
}

@(private = "file")
table_rows_get :: proc(node: ^Node, allocator := context.temp_allocator) -> []string {
	tbl := cast(^UITableNode)node
	out := make([]string, len(tbl.rows), allocator)
	for row, i in tbl.rows {
		cells := make([]string, len(row.cells), context.temp_allocator)
		for c, j in row.cells do cells[j] = c.text
		out[i] = strings.join(cells, "|", allocator)
	}
	return out
}

@(private = "file")
table_rows_set :: proc(node: ^Node, items: []string) {
	tbl := cast(^UITableNode)node
	if tbl.rows == nil do tbl.rows = make([dynamic]uilib.TableRow, tbl.allocator)
	clear(&tbl.rows)
	for line, i in items {
		f := fields(line)
		cells := make([]uilib.TableCell, len(f), tbl.allocator)
		for text, j in f do cells[j] = {text = strings.clone(text, tbl.allocator)}
		append(&tbl.rows, uilib.TableRow{cells = cells, id = i + 1})
	}
}

// --- Toolbar -----------------------------------------------------------------------

@(private = "file")
toolbar_items_get :: proc(node: ^Node, allocator := context.temp_allocator) -> []string {
	tb := cast(^UIToolbarNode)node
	out := make([]string, len(tb.items), allocator)
	for it, i in tb.items {
		switch it.itemType {
		case .Separator: out[i] = "-"
		case .Spacer:    out[i] = "~"
		case .Button, .Toggle:
			icon := reflect.enum_string(it.icon) if it.icon != uilib.Icon(0) else ""
			line := fmt.tprintf("%s|%s", icon, it.label)
			if it.tooltip != "" do line = fmt.tprintf("%s|%s", line, it.tooltip)
			if it.itemType == .Toggle do line = fmt.tprintf("toggle:%s", line)
			out[i] = strings.clone(line, allocator)
		}
	}
	return out
}

@(private = "file")
toolbar_items_set :: proc(node: ^Node, items: []string) {
	tb := cast(^UIToolbarNode)node
	if tb.items == nil do tb.items = make([dynamic]ToolbarItem, tb.allocator)
	clear(&tb.items)
	for raw, i in items {
		line := strings.trim_space(raw)
		it := ToolbarItem{id = i + 1}
		switch line {
		case "-": it.itemType = .Separator
		case "~": it.itemType = .Spacer
		case:
			if strings.has_prefix(line, "toggle:") {
				it.itemType = .Toggle
				line = line[len("toggle:"):]
			}
			f := fields(line)
			if len(f) == 1 {
				it.label = strings.clone(f[0], tb.allocator) // (just a label)
			} else {
				if icon, ok := reflect.enum_from_name(uilib.Icon, f[0]); ok do it.icon = icon
				it.label = strings.clone(f[1], tb.allocator)
				if len(f) > 2 do it.tooltip = strings.clone(f[2], tb.allocator)
			}
		}
		append(&tb.items, it)
	}
}

// --- XY Plot -----------------------------------------------------------------------

@(private = "file")
points_get :: proc(pts: [][2]f32, allocator: runtime.Allocator) -> []string {
	out := make([]string, len(pts), allocator)
	for p, i in pts do out[i] = fmt.aprintf("%g, %g", p.x, p.y, allocator = allocator)
	return out
}

@(private = "file")
points_set :: proc(pts: ^[dynamic][2]f32, node: ^Node, items: []string) {
	if pts^ == nil do pts^ = make([dynamic][2]f32, node.allocator)
	clear(pts)
	for line in items {
		xy := strings.split(line, ",", context.temp_allocator)
		if len(xy) < 2 do continue
		x, okx := strconv.parse_f32(strings.trim_space(xy[0]))
		y, oky := strconv.parse_f32(strings.trim_space(xy[1]))
		if okx && oky do append(pts, [2]f32{x, y})
	}
}

@(private = "file")
plot_points_get :: proc(node: ^Node, allocator := context.temp_allocator) -> []string {
	return points_get((cast(^UIXYPlotNode)node).points[:], allocator)
}

@(private = "file")
plot_points_set :: proc(node: ^Node, items: []string) {
	points_set(&(cast(^UIXYPlotNode)node).points, node, items)
}

@(private = "file")
plot_points2_get :: proc(node: ^Node, allocator := context.temp_allocator) -> []string {
	return points_get((cast(^UIXYPlotNode)node).secondaryPoints[:], allocator)
}

@(private = "file")
plot_points2_set :: proc(node: ^Node, items: []string) {
	points_set(&(cast(^UIXYPlotNode)node).secondaryPoints, node, items)
}

// --- Lua ---------------------------------------------------------------------------
// node:set_items({...}) / node:get_items() -> {...}: the node's main
// list (UI_MainList). Items are strings in the formats above; numbers and
// Vec2 / {x, y} tables (XY Plot points) are turned into text.

// Lua_ToStringList: the table at idx as lines (temp).
Lua_ToStringList :: proc(L: ^lua.State, idx: c.int) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	if lua.type(L, idx) != .TABLE do return out[:]
	n := int(lua.rawlen(L, idx))
	for i in 1 ..= n {
		lua.rawgeti(L, idx, lua.Integer(i))
		#partial switch lua.type(L, -1) {
		case .STRING:
			append(&out, strings.clone(string(lua.tostring(L, -1)), context.temp_allocator))
		case .NUMBER:
			append(&out, fmt.tprintf("%g", f64(lua.tonumber(L, -1))))
		case .TABLE, .USERDATA:
			x, y := arg_xy(L, -1)
			append(&out, fmt.tprintf("%g, %g", x, y))
		}
		lua.pop(L, 1)
	}
	return out[:]
}

// Lua_PushStringList pushes items as a table.
Lua_PushStringList :: proc(L: ^lua.State, items: []string) {
	lua.createtable(L, c.int(len(items)), 0)
	for it, i in items {
		lua.pushstring(L, strings.clone_to_cstring(it, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
}

@(private = "file")
lua_ui_set_items :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	if p, found := Node_FindProperty(node, UI_MainList(node)); found && p.kind == .String_List {
		Property_SetList(node, p, Lua_ToStringList(L, 2))
	}
	return 0
}

@(private = "file")
lua_ui_get_items :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	items: []string
	if ok {
		if p, found := Node_FindProperty(node, UI_MainList(node)); found && p.kind == .String_List do items = Property_GetList(p)
	}
	Lua_PushStringList(L, items)
	return 1
}

// Script_RegisterUIListBindings adds ui_set_items / ui_get_items to the node
// metatable (on the stack).
Script_RegisterUIListBindings :: proc(L: ^lua.State) {
	lua.pushcfunction(L, lua_ui_set_items)
	lua.setfield(L, -2, "set_items")
	Lua_SetDeprecated(L, lua_ui_set_items, "ui_set_items", "set_items")
	lua.pushcfunction(L, lua_ui_get_items)
	lua.setfield(L, -2, "get_items")
	Lua_SetDeprecated(L, lua_ui_get_items, "ui_get_items", "get_items")
}
