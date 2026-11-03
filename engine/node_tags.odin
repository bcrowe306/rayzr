package engine

import "base:runtime"
import "core:c"
import "core:strings"
import lua "lua54"

// ============================================================================
// Node tags (groups): any number of names per node ("enemy", "pickup"),
// saved with the scene ("tags"), searchable in the editor's scene tree
// ("#enemy") and from scripts:
//
//     node:add_tag("enemy") / remove_tag / has_tag / get_tags()
//     for _, e in ipairs(Scene.find_by_tag("enemy")) do ... end
// ============================================================================

Node_HasTag :: proc(node: ^Node, tag: string) -> bool {
	if node == nil do return false
	for t in node.tags do if t == tag do return true
	return false
}

// Node_AddTag adds a tag once (empty tags and duplicates are ignored).
Node_AddTag :: proc(node: ^Node, tag: string) -> bool {
	tag := strings.trim_space(tag)
	if node == nil || tag == "" || Node_HasTag(node, tag) do return false
	if node.tags == nil do node.tags = make([dynamic]string, node.allocator)
	append(&node.tags, strings.clone(tag, node.allocator))
	return true
}

Node_RemoveTag :: proc(node: ^Node, tag: string) -> bool {
	if node == nil do return false
	for t, i in node.tags {
		if t == tag {
			ordered_remove(&node.tags, i)
			return true
		}
	}
	return false
}

// Scene_FindByTag: the nodes with a tag, in tree order (temp-allocated).
Scene_FindByTag :: proc(scene: ^Scene, tag: string, allocator := context.temp_allocator) -> []^Node {
	out := make([dynamic]^Node, allocator)
	if scene == nil || scene.manager == nil || scene.rootNode == nil do return out[:]
	walk :: proc(m: ^NodeManager, n: ^Node, tag: string, out: ^[dynamic]^Node) {
		if n == nil || n.removing do return // (queued for removal: gone already, #356)
		if Node_HasTag(n, tag) do append(out, n)
		for child in GetChildrenView(m, n) do walk(m, child, tag, out)
	}
	walk(scene.manager, scene.rootNode, tag, &out)
	return out[:]
}

// --- Lua ------------------------------------------------------------------------------

lua_node_add_tag :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	tag := lua.tostring(L, 2)
	lua.pushboolean(L, b32(ok && tag != nil && Node_AddTag(node, string(tag))))
	return 1
}

lua_node_remove_tag :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	tag := lua.tostring(L, 2)
	lua.pushboolean(L, b32(ok && tag != nil && Node_RemoveTag(node, string(tag))))
	return 1
}

lua_node_has_tag :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	tag := lua.tostring(L, 2)
	lua.pushboolean(L, b32(ok && tag != nil && Node_HasTag(node, string(tag))))
	return 1
}

lua_node_get_tags :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.newtable(L)
		return 1
	}
	lua.createtable(L, c.int(len(node.tags)), 0)
	for t, i in node.tags {
		lua.pushstring(L, strings.clone_to_cstring(t, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

// Scene.find_by_tag(tag) -> { node, ... } (tree order)
lua_scene_find_by_tag :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	tag := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if tag == nil || sm == nil || sm.game == nil || sm.game.sceneManager.currentScene == nil {
		lua.newtable(L)
		return 1
	}
	nodes := Scene_FindByTag(sm.game.sceneManager.currentScene, string(tag))
	lua.createtable(L, c.int(len(nodes)), 0)
	for n, i in nodes {
		push_node_userdata(L, n)
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}
