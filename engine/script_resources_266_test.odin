package engine

import "core:strings"
import "core:testing"
import lua "lua54"

// #266: a resource property's value can be a file's per-instance values
// ({path, properties}) or an embedded resource ({class, properties}), and
// resource classes can have resource properties of their own (nested,
// cycles stopped).

@(private = "file")
setup_266 :: proc() -> (^Game, ^Scene) {
	ScriptVFS_RegisterEmbedded("r266/weapon.lua", `
local Weapon = {}
Weapon.resource = {}
Weapon.properties = {
    damage = { type = "int", default = 10 },
    name   = { type = "string", default = "?" },
    ammo   = { type = "resource", class = "r266/ammo.lua" },
}
function Weapon:on_load() loaded = (loaded or 0) + 1 end
return Weapon
`)
	ScriptVFS_RegisterEmbedded("r266/ammo.lua", `
local Ammo = {}
Ammo.resource = {}
Ammo.properties = { count = { type = "int", default = 5 }, next = { type = "resource" } }
return Ammo
`)
	ScriptVFS_RegisterEmbedded("r266/arrows.resource.json", `{"type": "resource", "script": "r266/ammo.lua", "properties": {"count": 30}}`)
	ScriptVFS_RegisterEmbedded("r266/bow.resource.json", `{"type": "resource", "script": "r266/weapon.lua", "properties": {"damage": 12, "name": "Bow", "ammo": "r266/arrows.resource.json"}}`)
	ScriptVFS_RegisterEmbedded("r266/loop_a.resource.json", `{"type": "resource", "script": "r266/ammo.lua", "properties": {"next": "r266/loop_b.resource.json"}}`)
	ScriptVFS_RegisterEmbedded("r266/loop_b.resource.json", `{"type": "resource", "script": "r266/ammo.lua", "properties": {"next": "r266/loop_a.resource.json"}}`)
	ScriptVFS_RegisterEmbedded("r266/archer.lua", `
local Archer = {}
Archer.properties = {
    weapon = { type = "resource", class = "r266/weapon.lua" },
    spare  = { type = "resource", class = "r266/weapon.lua" },
    trap   = { type = "resource" },
}
return Archer
`)
	game := new(Game)
	InitializeGame(game)
	scene := game->createScene("r266", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	return game, scene
}

@(private = "file")
archer :: proc(game: ^Game, scene: ^Scene, name, props: string) -> ^Node {
	file, _ := Resource_ParseText("x", strings.concatenate({`{"script": "x", "properties": `, props, `}`}, context.temp_allocator))
	n := Node_CreateByTypeName(scene, "Node")
	n.name = strings.clone(name, n.allocator)
	n.gameContext = &game.gameContext
	ProcessNodeQueues(scene.manager, &game.gameContext)
	Script_AttachToNode(n, "r266/archer.lua", file.values, &game.scriptManager)
	return n
}

@(test)
test_resources_embedded_overrides_nested :: proc(t: ^testing.T) {
	game, scene := setup_266()
	defer game->terminate()
	L := game.scriptManager.L
	// A: the file with damage overridden; B: the plain file; C: an embedded weapon.
	a := archer(game, scene, "A", `{"weapon": {"path": "r266/bow.resource.json", "properties": {"damage": 40}}, "trap": "r266/loop_a.resource.json"}`)
	b := archer(game, scene, "B", `{"weapon": "r266/bow.resource.json"}`)
	c := archer(game, scene, "C", `{"weapon": {"class": "r266/weapon.lua", "properties": {"name": "Rock", "ammo": {"class": "r266/ammo.lua", "properties": {"count": 1}}}}, "spare": {"class": "r266/ammo.lua", "properties": {}}}`)
	game->run(0.016)

	get :: proc(L: ^lua.State, n: ^Node, expr: string) -> string {
		lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer((cast(^ScriptInstance)n.scriptInstance).registryRef))
		lua.setglobal(L, "self")
		text, _ := Lua_Eval(L, expr, context.temp_allocator)
		return text
	}
	// Per-instance values: its own copy, the file's other values.
	testing.expect_value(t, get(L, a, "self.weapon.damage"), "40")
	testing.expect_value(t, get(L, a, "self.weapon.name"), "\"Bow\"")
	testing.expect_value(t, get(L, b, "self.weapon.damage"), "12")
	// Nested: the bow's arrows (a shared file) - the same table for A and B.
	testing.expect_value(t, get(L, a, "self.weapon.ammo.count"), "30")
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer((cast(^ScriptInstance)a.scriptInstance).registryRef))
	lua.setglobal(L, "a_self")
	testing.expect_value(t, get(L, b, "self.weapon.ammo == a_self.weapon.ammo"), "true")
	testing.expect_value(t, get(L, b, "self.weapon ~= a_self.weapon"), "true")
	// Embedded: no file, its values, an embedded resource inside it.
	testing.expect_value(t, get(L, c, "self.weapon.name"), "\"Rock\"")
	testing.expect_value(t, get(L, c, "self.weapon.damage"), "10")
	testing.expect_value(t, get(L, c, "self.weapon.ammo.count"), "1")
	testing.expect_value(t, get(L, c, "self.weapon.resource_path"), "nil")
	// The class is checked for embedded ones too: spare takes weapons.
	testing.expect_value(t, get(L, c, "self.spare"), "nil")
	// A loop stops (a -> b -> a): a's b has no next.
	testing.expect_value(t, get(L, a, "self.trap.next.count"), "5")
	testing.expect_value(t, get(L, a, "self.trap.next.next"), "nil")

	// The file changes: the copy keeps its own damage, takes the new name.
	ScriptVFS_RegisterEmbedded("r266/bow.resource.json", `{"type": "resource", "script": "r266/weapon.lua", "properties": {"damage": 13, "name": "Longbow", "ammo": "r266/arrows.resource.json"}}`)
	Resource_ReloadFile(&game.scriptManager, "r266/bow.resource.json")
	testing.expect_value(t, get(L, a, "self.weapon.damage"), "40")
	testing.expect_value(t, get(L, a, "self.weapon.name"), "\"Longbow\"")
	testing.expect_value(t, get(L, b, "self.weapon.damage"), "13")

	// Values written and read back.
	kind, path, _, values := Resource_ParseValue(`{"path": "r266/bow.resource.json", "properties": {"damage": 40}}`)
	testing.expect(t, kind == .Override && path == "r266/bow.resource.json" && (values["damage"].valInt == 40 || values["damage"].valFloat == 40), "parsed")
	mod, _ := ScriptManager_LoadModule("r266/weapon.lua", &game.scriptManager)
	text := Resource_ValueText(.Embedded, "r266/weapon.lua", values, mod, context.temp_allocator)
	testing.expect_value(t, text, `{"class": "r266/weapon.lua", "properties": {"damage": 40}}`)
	// The scene keeps them as JSON objects.
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(saved, `"weapon": {"path": "r266/bow.resource.json", "properties": {"damage": 40}}`), "an override saved as an object: %s", saved)
	testing.expect(t, strings.contains(saved, `"weapon": {"class": "r266/weapon.lua", "properties": {"ammo": {"class": "r266/ammo.lua", "properties": {"count": 1}}, "name": "Rock"}}`), "an embedded resource saved as an object")
	free_all(context.temp_allocator)
}
