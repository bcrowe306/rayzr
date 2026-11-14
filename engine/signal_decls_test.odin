package engine

import os "osx"
import "core:strings"
import "core:testing"
import lua "lua54"

// Declared signals (signal_decls.odin): on a node, a custom node type (and
// the types built on it), a script's ---@signal lines; saved, merged by
// name, raised by emit, listed to Lua; undeclared emits warn.

@(private = "file")
SG_DIR :: "test_signal_decls"

@(private = "file")
sg_write :: proc(rel, text: string) {
	full := strings.concatenate({SG_DIR, "/", rel}, context.temp_allocator)
	_ = os.make_directory_all(full[:strings.last_index_byte(full, '/')])
	_ = os.write_entire_file(full, transmute([]u8)text)
}

@(private = "file")
sg_setup :: proc(name: string) -> (^Game, ^Scene) {
	ScriptVFS_RegisterEmbedded("scripts/sg_enemy.lua", `
---@class SgEnemy
---@signal died
---@signal hit(damage: number) Took a hit
---@signal Bad(x)
local Enemy = {}
function Enemy:on_hit(v) own_log = (own_log or "") .. "own:" .. tostring(v) end
return Enemy
`)
	ScriptVFS_RegisterEmbedded("scripts/sg_boss.lua", `
---@signal enraged(level: integer)
---@signal hit(amount: number) Boss version (the base's stands)
local Boss = {}
Boss.extends = "scripts/sg_enemy.lua"
return Boss
`)
	CustomNodes_Forget()
	_ = os.make_directory_all(SG_DIR + "/nodes")
	sg_write("nodes/Crate.node.json", `{"name": "Crate", "base": "Node",
 "defaults": {"signals": [{"name": "opened", "param": "by", "type": "node", "description": "Someone opened it"}]}}`)
	sg_write("nodes/BigCrate.node.json", `{"name": "BigCrate", "inherits": "nodes/Crate.node.json",
 "defaults": {"signals": [{"name": "smashed"}]}}`)
	game := new(Game)
	InitializeGame(game)
	AssetManager_SetProjectDir(&game.assetManager, SG_DIR)
	scene := game->createScene(name, true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	return game, scene
}

@(private = "file")
sg_teardown :: proc(game: ^Game) {
	game->terminate()
	CustomNodes_Forget()
	os.remove_all(SG_DIR)
}

@(private = "file")
sg_names :: proc(list: []Signal_Info, origin: Signal_Origin) -> string {
	out := make([dynamic]string, context.temp_allocator)
	for s in list do if s.origin == origin do append(&out, s.name)
	return strings.join(out[:], ",", context.temp_allocator)
}

@(test)
test_signal_names_and_script_lines :: proc(t: ^testing.T) {
	ok, _ := Signal_IsValidName("health_changed")
	testing.expect(t, ok, "snake case")
	for bad in ([]string{"", "Health", "2x", "a-b", "a b"}) {
		valid, problem := Signal_IsValidName(bad)
		testing.expectf(t, !valid && problem != "", "%q refused", bad)
	}
	d, parsed := Script_ParseSignalLine("  ---@signal hit(damage: number) Took a hit")
	testing.expect(t, parsed, "parsed")
	testing.expect_value(t, d.name, "hit")
	testing.expect_value(t, d.param, "damage")
	testing.expect_value(t, d.type, "number")
	testing.expect_value(t, d.description, "Took a hit")
	d, parsed = Script_ParseSignalLine("---@signal opened(by: Node)")
	testing.expect(t, parsed && d.type == "node" && d.description == "", "Node is node")
	d, parsed = Script_ParseSignalLine("---@signal ping")
	testing.expect(t, parsed && d.param == "" && d.type == "", "no value")
	_, parsed = Script_ParseSignalLine("---@signals ping")
	testing.expect(t, !parsed, "another tag")
	_, parsed = Script_ParseSignalLine("---@signal Bad")
	testing.expect(t, !parsed, "a bad name")
	testing.expect_value(t, Script_SignalLine({"hit", "damage", "number", "Took a hit"}), "---@signal hit(damage: number) Took a hit")
	testing.expect_value(t, Script_SignalLine({"ping", "", "", ""}), "---@signal ping")
	lines := make([dynamic]int, context.temp_allocator)
	list := Script_ParseSignals("local x\n---@signal a\n---@signal a(dup)\n---@signal b(v)\n", context.temp_allocator, &lines)
	testing.expect(t, len(list) == 2 && list[0].name == "a" && list[1].name == "b", "the first of a name")
	testing.expect(t, len(lines) == 2 && lines[0] == 2 && lines[1] == 4, "their lines")
}

@(test)
test_signal_decls_on_nodes :: proc(t: ^testing.T) {
	game, scene := sg_setup("decls")
	defer sg_teardown(game)
	ctx := &game.gameContext

	// A plain node declares its own; saved and loaded back.
	n := Node_CreateByTypeName(scene, "Node")
	n.name = "Door"
	testing.expect(t, Node_AddSignal(n, {"opened", "by", "node", "Someone opened it"}), "added")
	testing.expect(t, !Node_AddSignal(n, {"opened", "", "", ""}), "a name once")
	testing.expect(t, Node_AddSignal(n, {"locked", "", "", ""}), "another")
	testing.expect(t, Node_AddConnection(n, "opened", ".", "on_door_opened"), "connected")
	ProcessNodeQueues(scene.manager, ctx)
	testing.expect(t, Node_HasSignal(n, "opened") && Node_HasSignal(n, "entered_tree") && !Node_HasSignal(n, "nope"), "has")
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(saved, `"signals": [{"name": "opened", "param": "by", "type": "node", "description": "Someone opened it"}, {"name": "locked"}]`), "saved: %s", saved)

	again := game->createScene("decls2", false)
	testing.expect(t, Scene_InstantiateFromJSON(again, transmute([]u8)saved, ctx), "loads")
	ProcessNodeQueues(again.manager, ctx)
	door := Scene_FindNodeByName(again, "Door")
	if !testing.expect(t, door != nil, "reloaded") do return
	testing.expect_value(t, sg_names(Node_Signals(door), .Node), "opened,locked")
	s, found := Node_FindSignal(door, "opened")
	testing.expect(t, found && s.param == "by" && s.type == "node", "its value")

	// Rename and remove (with connections).
	testing.expect(t, Node_SetSignal(door, "opened", {"unlocked", "by", "node", ""}), "renamed")
	testing.expect_value(t, Node_RenameConnections(door, "opened", "unlocked"), 1)
	testing.expect(t, door.signals[0].name == "unlocked" && door.signalConnections[0].signal == "unlocked", "in place")
	testing.expect(t, Node_RemoveSignal(door, "locked"), "removed")
	testing.expect_value(t, Node_RemoveConnectionsOf(door, "unlocked"), 1)
	testing.expect_value(t, len(door.signals), 1)
}

@(test)
test_signal_decls_custom_types :: proc(t: ^testing.T) {
	game, scene := sg_setup("types")
	defer sg_teardown(game)
	ctx := &game.gameContext

	big, _ := CustomNode_Get(ctx, "nodes/BigCrate.node.json")
	if !testing.expect(t, big != nil, "the type") do return
	a := Scene_CreateCustomNode(scene, big, nil, ctx)
	b := Scene_CreateCustomNode(scene, big, nil, ctx)
	a.name, b.name = "CrateA", "CrateB"
	ProcessNodeQueues(scene.manager, ctx)
	// The parent type's first, then its own; none are the node's.
	testing.expect_value(t, sg_names(Node_Signals(a), .Type), "opened,smashed")
	testing.expect_value(t, len(a.signals), 0)
	// The type's document: only the parent's count as the type's.
	testing.expect_value(t, sg_names(Node_Signals(a, typeDoc = true), .Type), "opened")
	// B adds one of its own (and repeats a type's: the type's stands).
	Node_AddSignal(b, {"rattled", "", "", ""})
	Node_AddSignal(b, {"opened", "", "", "not this one"})
	testing.expect_value(t, sg_names(Node_Signals(b), .Node), "rattled")
	s, _ := Node_FindSignal(b, "opened")
	testing.expect_value(t, s.description, "Someone opened it")

	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	ai := strings.index(saved, `"name": "CrateA"`)
	bi := strings.index(saved, `"name": "CrateB"`)
	if !testing.expect(t, ai >= 0 && bi > ai, "both saved") do return
	testing.expectf(t, !strings.contains(saved[ai:bi], "signals"), "A has none of its own: %s", saved[ai:bi])
	testing.expectf(t, strings.contains(saved[bi:], `"signals": [{"name": "rattled"}, {"name": "opened", "description": "not this one"}]`), "B's own: %s", saved[bi:])

	// The type gains a signal: every node of it has it, B keeps its own.
	sg_write("nodes/BigCrate.node.json", `{"name": "BigCrate", "inherits": "nodes/Crate.node.json",
 "defaults": {"signals": [{"name": "smashed"}, {"name": "sealed"}]}}`)
	CustomNodes_Forget()
	again := game->createScene("types2", false)
	testing.expect(t, Scene_InstantiateFromJSON(again, transmute([]u8)saved, ctx), "loads")
	ProcessNodeQueues(again.manager, ctx)
	ra, rb := Scene_FindNodeByName(again, "CrateA"), Scene_FindNodeByName(again, "CrateB")
	if !testing.expect(t, ra != nil && rb != nil, "reloaded") do return
	testing.expect_value(t, sg_names(Node_Signals(ra), .Type), "opened,smashed,sealed")
	testing.expect_value(t, sg_names(Node_Signals(rb), .Node), "rattled")

	// Saving a type's document: its own signals go in its defaults.
	crate, _ := CustomNode_Get(ctx, "nodes/Crate.node.json")
	defaults := CustomNode_DefaultsFromNode(rb, again.manager, context.temp_allocator, crate)
	testing.expectf(t, strings.contains(defaults, `"signals"`) && strings.contains(defaults, "rattled"), "in the defaults: %s", defaults)
}

@(test)
test_signal_decls_scripts_and_lua :: proc(t: ^testing.T) {
	prev := Lua_WarnDeprecated
	defer Lua_WarnDeprecated = prev
	Lua_WarnDeprecated = true
	Signal_ForgetWarnings()
	defer Signal_ForgetWarnings()

	game, scene := sg_setup("scripts")
	defer sg_teardown(game)
	ctx := &game.gameContext
	boss := Node_CreateByTypeName(scene, "Node")
	boss.name = "Boss"
	Node_AddSignal(boss, {"phase", "n", "integer", ""})
	_ = Script_AttachToNode(boss, "scripts/sg_boss.lua", nil, ctx.scriptManager)
	ProcessNodeQueues(scene.manager, ctx)
	// Its own, then its script's (the base script's after), a name once.
	testing.expect_value(t, sg_names(Node_Signals(boss), .Node), "phase")
	testing.expect_value(t, sg_names(Node_Signals(boss), .Script), "enraged,hit,died")
	game->run(0.016) // (its ready)
	hit, _ := Node_FindSignal(boss, "hit")
	testing.expect(t, hit.param == "amount" && hit.from == "scripts/sg_boss.lua" && hit.line == 3, "the boss's own hit")
	died, _ := Node_FindSignal(boss, "died")
	testing.expect_value(t, died.from, "scripts/sg_enemy.lua")

	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local b = Scene.find_node("Boss")
names = {}
for _, s in ipairs(b:get_signals()) do
	if s.origin ~= "builtin" then names[#names + 1] = s.name .. ":" .. s.origin .. ":" .. s.type end
end
names = table.concat(names, ",")
has = b:has_signal("enraged") and b:has_signal("entered_tree") and not b:has_signal("nope")
got = {}
b:connect("hit", function(v, src) got[#got + 1] = "conn:" .. tostring(v) end)
b:emit("hit", 3)       -- declared: no warning
b:emit("surprise", 1)  -- undeclared: warns once per site
for i = 1, 3 do b:emit("other") end
own = own_log
got = table.concat(got, ",")
`)
	if ok != 0 do testing.expectf(t, false, "%s", lua.tostring(L, -1))
	lua.getglobal(L, "names")
	testing.expect_value(t, string(lua.tostring(L, -1)), "phase:node:integer,enraged:script:integer,hit:script:number,died:script:any")
	lua.getglobal(L, "has")
	testing.expect(t, bool(lua.toboolean(L, -1)), "has_signal")
	lua.getglobal(L, "own")
	testing.expect_value(t, string(lua.tostring(L, -1)), "own:3")
	lua.getglobal(L, "got")
	testing.expect_value(t, string(lua.tostring(L, -1)), "conn:3")
	lua.pop(L, 4)
	testing.expect_value(t, Signal_WarningCount(), 2) // "surprise", "other" (one site)

	Lua_WarnDeprecated = false
	_ = lua.L_dostring(L, `Scene.find_node("Boss"):emit("quiet")`)
	testing.expect_value(t, Signal_WarningCount(), 2)
}
