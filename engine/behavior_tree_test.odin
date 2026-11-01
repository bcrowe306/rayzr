package engine

import "core:encoding/json"
import "core:strings"
import "core:testing"
import lua "lua54"

// Behavior Trees: composites (memory, Star, Reactive interrupting, Random,
// Simple Parallel), decorators, leaves (blackboard, Move To, signals, State
// Machine, Subtree), a Lua leaf (before_run / tick / after_run /
// interrupt), Lua's bt_* and Blackboard, saving.

@(private = "file")
bt_setup :: proc() -> (^Game, ^Scene, ^Node, ^BehaviorTreeNode) {
	game := new(Game)
	InitializeGame(game)
	scene := game->createScene("bt", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	actor := Node_CreateByTypeName(scene, "Node")
	delete(actor.name, actor.allocator)
	actor.name = strings.clone("Goblin", actor.allocator)
	t := cast(^BehaviorTreeNode)Node_CreateByTypeName(scene, "BehaviorTreeNode", actor)
	t.processMode = .Manual
	ProcessNodeQueues(scene.manager, &game.gameContext)
	return game, scene, actor, t
}

@(private = "file")
add :: proc(t: ^BehaviorTreeNode, parent: int, kind: BT_Kind, key := "", value := "", number: f32 = -1) -> int {
	i := BT_AddNode(t, parent, kind)
	if key != "" do BT_SetString(t, &t.nodes[i].key, key)
	if value != "" do BT_SetString(t, &t.nodes[i].value, value)
	if number >= 0 do t.nodes[i].number = number
	return i
}

@(private = "file")
bb_num :: proc(t: ^BehaviorTreeNode, key: string) -> f64 {
	bb := BehaviorTree_Blackboard(t)
	return bb[key].(f64) or_else -1
}

@(test)
test_behavior_tree_composites :: proc(t: ^testing.T) {
	game, _, _, bt := bt_setup()
	defer game->terminate()
	dt: f32 = 0.25

	// Sequence with memory: set, wait 0.5 s (Running twice), compare.
	root := add(bt, -1, .Sequence)
	add(bt, root, .Blackboard_Set, "a", "1")
	add(bt, root, .Wait, number = 0.5)
	cmp := add(bt, root, .Blackboard_Compare, "a", "1")
	testing.expect_value(t, BehaviorTree_Tick(bt, dt), BT_Status.Running)
	testing.expect_value(t, BehaviorTree_Tick(bt, dt), BT_Status.Success)
	testing.expect_value(t, bt.nodes[cmp].rt.status, BT_Status.Success)
	bt.nodes[cmp].op = .Greater
	testing.expect_value(t, BehaviorTree_Tick(bt, 1), BT_Status.Failure) // 1 > 1
	BT_RemoveNode(bt, 0)
	testing.expect_value(t, len(bt.nodes), 0)

	// Selector Reactive: a higher-priority branch interrupts a long Wait.
	root = add(bt, -1, .Selector_Reactive)
	seq := add(bt, root, .Sequence)
	add(bt, seq, .Blackboard_Has, "alarm")
	add(bt, seq, .Blackboard_Set, "fled", "true")
	long := add(bt, root, .Wait, number = 10)
	testing.expect_value(t, BehaviorTree_Tick(bt, dt), BT_Status.Running)
	testing.expect_value(t, bt.nodes[long].rt.status, BT_Status.Running)
	testing.expect_value(t, bt.runningAction, long)
	BB_Set(BehaviorTree_Blackboard(bt), "alarm", true)
	testing.expect_value(t, BehaviorTree_Tick(bt, dt), BT_Status.Success)
	testing.expect_value(t, bt.nodes[long].rt.status, BT_Status.None) // interrupted
	testing.expect(t, BehaviorTree_Blackboard(bt)["fled"].(bool) or_else false, "the alarm branch ran")
	BT_RemoveNode(bt, 0)

	// Sequence Star retries the failed child; a plain Sequence starts over.
	for kind in ([]BT_Kind{.Sequence, .Sequence_Star}) {
		root = add(bt, -1, kind)
		add(bt, root, .Blackboard_Erase, "x")
		add(bt, root, .Blackboard_Has, "go")
		testing.expect_value(t, BehaviorTree_Tick(bt, dt), BT_Status.Failure)
		testing.expect_value(t, bt.nodes[root].rt.index, 0 if kind == .Sequence else 1)
		BT_RemoveNode(bt, 0)
	}

	// Selector with memory: failed children aren't tried again while a later one runs.
	root = add(bt, -1, .Selector)
	f := add(bt, root, .Blackboard_Has, "nope")
	w := add(bt, root, .Wait, number = 0.5)
	testing.expect_value(t, BehaviorTree_Tick(bt, dt), BT_Status.Running)
	bt.nodes[f].rt.tick = 0
	testing.expect_value(t, BehaviorTree_Tick(bt, dt), BT_Status.Success)
	testing.expect_value(t, bt.nodes[f].rt.tick, u64(0)) // skipped
	testing.expect_value(t, bt.nodes[w].rt.status, BT_Status.Success)
	BT_RemoveNode(bt, 0)

	// Decorators.
	expect_kind :: proc(t: ^testing.T, bt: ^BehaviorTreeNode, kind: BT_Kind, child: BT_Kind, number: f32, want: []BT_Status, dt: f32 = 0.25) {
		root := add(bt, -1, kind, number = number)
		add(bt, root, child, key = "missing", number = 0)
		for w, k in want {
			got := BehaviorTree_Tick(bt, dt)
			testing.expectf(t, got == w, "%v over %v, tick %d: %v, want %v", kind, child, k + 1, got, w)
		}
		BT_RemoveNode(bt, 0)
	}
	expect_kind(t, bt, .Inverter, .Blackboard_Has, 0, {.Success})
	expect_kind(t, bt, .Always_Succeed, .Blackboard_Has, 0, {.Success})
	expect_kind(t, bt, .Always_Fail, .Blackboard_Erase, 0, {.Failure})
	expect_kind(t, bt, .Until_Fail, .Blackboard_Erase, 0, {.Running, .Running})
	expect_kind(t, bt, .Until_Fail, .Blackboard_Has, 0, {.Success})
	expect_kind(t, bt, .Repeater, .Blackboard_Erase, 3, {.Running, .Running, .Success})
	expect_kind(t, bt, .Repeater, .Blackboard_Has, 3, {.Failure})
	expect_kind(t, bt, .Delayer, .Blackboard_Erase, 0.5, {.Running, .Running, .Success})
	expect_kind(t, bt, .Cooldown, .Blackboard_Erase, 0.6, {.Success, .Failure, .Failure, .Success})
	expect_kind(t, bt, .Time_Limiter, .Wait_Signal, 0.6, {.Running, .Running, .Failure})
	expect_kind(t, bt, .Limiter, .Wait_Signal, 2, {.Running, .Running, .Failure})

	// Random: every child of a Sequence Random runs once a run, in some order;
	// the same seed gives the same order.
	orders: [2]string
	for run in 0 ..< 2 {
		root = add(bt, -1, .Sequence_Random)
		bt.nodes[root].seed = 42
		for _ in 0 ..< 4 do add(bt, root, .Blackboard_Erase, "x")
		bt_shuffle_for_test(bt, root)
		sb := strings.builder_make(context.temp_allocator)
		for c in bt.nodes[root].rt.bag do strings.write_int(&sb, c)
		orders[run] = strings.to_string(sb)
		testing.expect_value(t, BehaviorTree_Tick(bt, dt), BT_Status.Success)
		for c in bt.nodes[root].children do testing.expect_value(t, bt.nodes[c].rt.status, BT_Status.Success)
		BT_RemoveNode(bt, 0)
	}
	testing.expect_value(t, orders[0], orders[1])

	// Simple Parallel: the primary's answer; the secondary repeats meanwhile.
	root = add(bt, -1, .Simple_Parallel)
	add(bt, root, .Wait, number = 0.5)
	add(bt, root, .Blackboard_Erase, "x")
	testing.expect_value(t, BehaviorTree_Tick(bt, dt), BT_Status.Running)
	testing.expect_value(t, BehaviorTree_Tick(bt, dt), BT_Status.Success)
	testing.expect_value(t, BT_AddNode(bt, root, .Wait), -1) // (two children at most)
	BT_RemoveNode(bt, 0)
	free_all(context.temp_allocator)
}

@(test)
test_behavior_tree_leaves_and_lua :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("bt_count.lua", `
local Count = {}
Count.behavior = "action"
Count.properties = { needed = { type = "int", default = 2 } }
function Count:before_run(actor, bb) bb:set("starts", (bb:get("starts", 0)) + 1); self.n = 0 end
function Count:tick(actor, bb, dt)
    self.n = self.n + 1
    if self.n >= self.needed then return "success" end
    return "running"
end
function Count:after_run(actor, bb) bb:set("ends", bb:get("ends", 0) + 1) end
function Count:interrupt(actor, bb) bb:set("interrupted", true) end
return Count
`)
	ScriptVFS_RegisterEmbedded("bt_goblin.lua", `
local G = {}
function G:attack(target) hits = (hits or 0) + 1; return hits >= 2 end
return G
`)
	game, scene, actor, bt := bt_setup()
	defer game->terminate()
	ctx := &game.gameContext
	actor.gameContext = ctx
	Script_AttachToNode(actor, "bt_goblin.lua", nil, &game.scriptManager)
	game->run(0.016)

	// A Lua leaf: its property, before_run / after_run once a run.
	root := add(bt, -1, .Sequence)
	leaf := add(bt, root, .Script)
	BT_SetString(bt, &bt.nodes[leaf].script, "bt_count.lua")
	bt.nodes[leaf].props = make(map[string]ScriptValue, bt.allocator)
	bt.nodes[leaf].props[strings.clone("needed", bt.allocator)] = ScriptValue{type = .Int, valInt = 3}
	call := add(bt, root, .Call_Method, "attack")
	testing.expect_value(t, BehaviorTree_Tick(bt, 0.1), BT_Status.Running)
	testing.expect_value(t, BehaviorTree_Tick(bt, 0.1), BT_Status.Running)
	testing.expect_value(t, BehaviorTree_Tick(bt, 0.1), BT_Status.Failure) // attack(): hits 1 -> false
	testing.expect_value(t, bb_num(bt, "starts"), 1)
	testing.expect_value(t, bb_num(bt, "ends"), 1)
	testing.expect_value(t, bt.nodes[call].rt.status, BT_Status.Failure)
	BehaviorTree_Tick(bt, 0.1)
	BehaviorTree_Interrupt(bt) // the leaf was running: interrupt()
	testing.expect(t, BehaviorTree_Blackboard(bt)["interrupted"].(bool) or_else false, "the leaf's interrupt ran")
	testing.expect_value(t, bt_script_kind(game, "bt_count.lua"), "action")
	BT_RemoveNode(bt, 0)

	// Wait For Signal: an emitted signal ends it; Emit Signal emits one.
	root = add(bt, -1, .Sequence)
	ws := add(bt, root, .Wait_Signal, "spotted")
	testing.expect_value(t, BehaviorTree_Tick(bt, 0.1), BT_Status.Running)
	Script_DispatchEvent(actor, "spotted", nil, ctx)
	testing.expect_value(t, BehaviorTree_Tick(bt, 0.1), BT_Status.Success)
	testing.expect_value(t, len(btWatchers), 0)
	bt.nodes[ws].number = 0.15 // a timeout
	testing.expect_value(t, BehaviorTree_Tick(bt, 0.1), BT_Status.Running)
	testing.expect_value(t, BehaviorTree_Tick(bt, 0.1), BT_Status.Failure)
	BT_RemoveNode(bt, 0)

	// Move To (no Navigation Agent): straight at Speed to a blackboard position.
	actor.position = {0, 0}
	actor.globalPosition = {0, 0}
	root = add(bt, -1, .Move_To, key = "goal")
	bt.nodes[root].number, bt.nodes[root].number2 = 2, 100
	BB_Set(BehaviorTree_Blackboard(bt), "goal", [2]f32{100, 0})
	testing.expect_value(t, BehaviorTree_Tick(bt, 0.5), BT_Status.Running)
	testing.expect_value(t, actor.position, [2]f32{50, 0})
	testing.expect_value(t, BehaviorTree_Tick(bt, 0.5), BT_Status.Success)
	BT_RemoveNode(bt, 0)

	// State Machine leaves: the actor's State Machine.
	sm := cast(^StateMachineNode)Node_CreateByTypeName(scene, "StateMachineNode", actor)
	sm.gameContext = ctx
	StateMachine_AddState(sm, "idle")
	append(&sm.params, SM_Param{name = strings.clone("speed", sm.allocator)})
	ProcessNodeQueues(scene.manager, ctx)
	root = add(bt, -1, .Sequence)
	add(bt, root, .State_Machine_Set, "speed", "2.5")
	add(bt, root, .State_Machine_In_State, "idle")
	StateMachine_Start(sm)
	testing.expect_value(t, BehaviorTree_Tick(bt, 0.1), BT_Status.Success)
	testing.expect_value(t, StateMachine_GetParam(sm, "speed"), 2.5)
	BT_RemoveNode(bt, 0)

	// Subtree, Lua bt_* and the global Blackboard.
	sub := cast(^BehaviorTreeNode)Node_CreateByTypeName(scene, "BehaviorTreeNode", actor)
	delete(sub.name, sub.allocator)
	sub.name = strings.clone("Patrol", sub.allocator)
	sub.processMode = .Manual
	ProcessNodeQueues(scene.manager, ctx)
	add(sub, -1, .Blackboard_Set, "patrolled", "yes")
	root = add(bt, -1, .Subtree)
	BT_SetString(bt, &bt.nodes[root].target, "../Patrol")
	testing.expect_value(t, BehaviorTree_Tick(bt, 0.1), BT_Status.Success)
	testing.expect_value(t, BehaviorTree_Blackboard(sub)["patrolled"].(string) or_else "", "yes")
	L := game.scriptManager.L
	push_node_userdata(L, bt)
	lua.setglobal(L, "tree")
	text, _ := Lua_Eval(L, `tree:bt_set("hp", 5); Blackboard:set("alarm", true); return string.format("%d %s", tree:bt_get("hp") + (Blackboard:get("alarm") and 1 or 0), tree:bt_status())`, context.temp_allocator)
	testing.expect_value(t, text, `"6 success"`)
	testing.expect(t, btGlobal["alarm"].(bool) or_else false, "the global blackboard")
	BT_RemoveNode(bt, 0)
	free_all(context.temp_allocator)
}

@(private = "file")
bt_script_kind :: proc(game: ^Game, path: string) -> string {
	mod, _ := ScriptManager_LoadModule(path, &game.scriptManager)
	return mod.behavior if mod != nil else ""
}


@(test)
test_behavior_tree_saving :: proc(t: ^testing.T) {
	game, scene, _, bt := bt_setup()
	defer game->terminate()
	root := add(bt, -1, .Selector_Random)
	bt.nodes[root].weights = true
	bt.nodes[root].seed = 7
	a := add(bt, root, .Blackboard_Compare, "hp", "$max")
	bt.nodes[a].op = .Less_Equal
	bt.nodes[a].weight = 5
	bt.nodes[a].global = true
	l := add(bt, root, .Script)
	BT_SetString(bt, &bt.nodes[l].script, "scripts/attack.lua")
	BT_SetString(bt, &bt.nodes[l].name, "Attack")
	append(&bt.bbInit, BT_BB_Entry{strings.clone("hp", bt.allocator), strings.clone("10", bt.allocator)})
	w := Json_Writer{sb = strings.builder_make(context.temp_allocator)}
	first := true
	strings.write_byte(&w.sb, '{')
	BehaviorTree_WriteJSON(&w, bt, &first)
	strings.write_byte(&w.sb, '}')
	saved := strings.to_string(w.sb)
	testing.expectf(t, strings.contains(saved, `"behavior_tree": {"root": {"kind": "Selector_Random", "seed": 7, "weights": true, "children": [{"kind": "Blackboard_Compare", "weight": 5, "key": "hp", "value": "$max", "op": "<=", "global": true}, {"kind": "Script", "name": "Attack", "script": "scripts/attack.lua"}]}, "blackboard": [{"key": "hp", "value": "10"}]}`), "saved: %s", saved)
	v, err := json.parse_string(saved, allocator = context.temp_allocator)
	testing.expect(t, err == nil, "parses")
	testing.expect(t, strings.contains(Scene_SerializeToJSON(scene, context.temp_allocator), `"kind": "Selector_Random"`), "in the scene")
	bt2 := cast(^BehaviorTreeNode)Node_CreateByTypeName(scene, "BehaviorTreeNode")
	BehaviorTree_ReadJSON(bt2, v.(json.Object)["behavior_tree"].(json.Object))
	testing.expect_value(t, len(bt2.nodes), 3)
	testing.expect(t, bt2.nodes[1].op == .Less_Equal && bt2.nodes[1].weight == 5 && bt2.nodes[1].global && bt2.nodes[2].name == "Attack", "read back")
	testing.expect_value(t, len(bt2.bbInit), 1)
	// Values as text.
	testing.expect_value(t, BB_Parse("12.5").(f64) or_else 0, 12.5)
	testing.expect_value(t, BB_Parse("3, 4").([2]f32) or_else {}, [2]f32{3, 4})
	testing.expect_value(t, BB_Parse(`"12"`).(string) or_else "", "12")
	testing.expect(t, BB_Compare(f64(3), f64(4), .Less) && BB_Compare("a", "a", .Equal) && !BB_Compare(true, false, .Equal), "compare")
	// Editing: move, limits, can't go inside itself.
	testing.expect(t, !BT_MoveNode(bt, root, 1), "not into itself (root)")
	testing.expect(t, BT_MoveNode(bt, 2, root, 0), "reorder")
	testing.expect_value(t, bt.nodes[root].children[0], 2)
	free_all(context.temp_allocator)
}
