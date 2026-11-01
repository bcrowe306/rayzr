package engine

import "core:encoding/json"
import "core:strings"
import "core:testing"
import lua "lua54"

// GOAP: planning (cheapest path, distance, chains through conditions),
// running (moving to targets, effects on unsensed keys, goals completing,
// signals), Lua actions / sensors / goals, a Behavior Tree action,
// disabling, goal requests, saving.

@(private = "file")
goap_setup :: proc() -> (^Game, ^Scene, ^Node, ^GoapNode) {
	game := new(Game)
	InitializeGame(game)
	scene := game->createScene("goap", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	world := Node_CreateByTypeName(scene, "Node")
	world.name = strings.clone("World", world.allocator)
	actor := Node_CreateByTypeName(scene, "Node", world)
	actor.name = strings.clone("Jack", actor.allocator)
	g := cast(^GoapNode)Node_CreateByTypeName(scene, "GoapNode", actor)
	for name, i in ([]string{"Axe", "Tree"}) {
		n := Node_CreateByTypeName(scene, "Node", world)
		n.name = strings.clone(name, n.allocator)
		n.position = {50 * f32(i + 1), 0}
		n.globalPosition = n.position
	}
	ProcessNodeQueues(scene.manager, &game.gameContext)
	return game, scene, actor, g
}

@(private = "file")
Goap_Log :: struct {
	sb: strings.Builder,
}

@(private = "file")
goap_listen :: proc(g: ^GoapNode, log: ^Goap_Log) {
	log.sb = strings.builder_make(context.temp_allocator)
	cb :: proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {
		l := cast(^Goap_Log)ud
		if s, ok := v.(string); ok do strings.write_string(&l.sb, s)
		else do strings.write_string(&l.sb, "?")
		strings.write_byte(&l.sb, ' ')
	}
	Subscribe(&g.onActionStarted, cb, log)
	Subscribe(&g.onGoalCompleted, cb, log)
}

@(test)
test_goap_planning_and_running :: proc(t: ^testing.T) {
	game, _, actor, g := goap_setup()
	defer game->terminate()
	Goap_AddKey(g, "HasAxe")
	Goap_AddKey(g, "Wood")
	Goap_AddKey(g, "AxeSpot", target = true)
	Goap_AddKey(g, "TreeSpot", target = true)
	Goap_AddSensor(g, "AxeSpot", .Node)
	Goap_SetString(g, &g.sensors[0].node, "../../Axe")
	Goap_AddSensor(g, "TreeSpot", .Node)
	Goap_SetString(g, &g.sensors[1].node, "../../Tree")
	gi := Goap_AddGoal(g, "GatherWood")
	Goap_AddCondition(g, &g.goals[gi].conditions, "Wood", .Greater_Equal, 3)
	pick := Goap_AddAction(g, "PickUpAxe")
	Goap_AddEffect(g, &g.actions[pick], "HasAxe", true)
	Goap_SetString(g, &g.actions[pick].target, "AxeSpot")
	g.actions[pick].seconds = 0.1
	chop := Goap_AddAction(g, "ChopWood")
	Goap_AddCondition(g, &g.actions[chop].conditions, "HasAxe", .Greater_Equal, 1)
	Goap_AddEffect(g, &g.actions[chop], "Wood", true)
	Goap_SetString(g, &g.actions[chop].target, "TreeSpot")
	g.actions[chop].seconds = 0.2
	punch := Goap_AddAction(g, "PunchTree")
	Goap_AddEffect(g, &g.actions[punch], "Wood", true)
	g.actions[punch].baseCost = 10
	g.actions[punch].seconds = 0.2
	g.moveSpeed = 100

	log: Goap_Log
	goap_listen(g, &log)
	GoapNode_Advance(g, 0.05)
	// The plan: get the axe, then chop (cheaper than punching).
	testing.expect_value(t, g.goal, gi)
	testing.expect_value(t, len(g.plan), 2)
	testing.expect(t, len(g.plan) == 2 && g.plan[0] == pick && g.plan[1] == chop, "axe, then chop")
	testing.expect_value(t, g.state, Goap_Agent_State.Moving_To_Target)
	for _ in 0 ..< 200 {
		GoapNode_Advance(g, 0.05)
		if g.goal < 0 do break
	}
	wood, _ := Goap_GetValue(g, "Wood")
	testing.expect_value(t, wood, 3)
	testing.expect_value(t, strings.to_string(log.sb), "PickUpAxe ChopWood ChopWood ChopWood GatherWood ")
	testing.expect(t, abs(actor.position.x - 100) <= 16, "at the tree")

	// Punching wins when the axe is disabled; a cooldown passes.
	Goap_SetValue(g, "Wood", 0)
	Goap_SetValue(g, "HasAxe", 0)
	g.actions[pick].disabledUntil = -1
	GoapNode_Resolve(g)
	testing.expect(t, len(g.plan) == 1 && g.plan[0] == punch, "punch: no way to the axe")
	g.actions[pick].disabledUntil = g.time + 1
	GoapNode_Advance(g, 2)
	GoapNode_Resolve(g)
	testing.expect(t, len(g.plan) >= 1 && g.plan[0] != punch, "the axe again after its cooldown")

	// A goal already met: nothing to do (no_action_found once).
	GoapNode_Stop(g)
	Goap_SetValue(g, "Wood", 5)
	GoapNode_Advance(g, 0.05)
	testing.expect_value(t, g.action, -1)
	testing.expect_value(t, g.goal, -1)
	free_all(context.temp_allocator)
}

@(test)
test_goap_lua_and_trees :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("goap_eat.lua", `
local Eat = {}
Eat.goap = "action"
Eat.properties = { bites = { type = "int", default = 2 } }
function Eat:start(actor) self.left = self.bites end
function Eat:perform(actor, ctx)
    self.left = self.left - 1
    if self.left > 0 then return "continue" end
    self.agent:goap_set_key("Hunger", 0)
    return { wait = 0.1, ["then"] = "completed" }
end
function Eat:get_cost(actor, target) return 2 end
return Eat
`)
	ScriptVFS_RegisterEmbedded("goap_hunger.lua", `
local Hunger = {}
Hunger.goap = "sensor"
function Hunger:sense(actor) return hunger_level or 0 end
return Hunger
`)
	ScriptVFS_RegisterEmbedded("goap_fed.lua", `
local Fed = {}
Fed.goap = "goal"
function Fed:get_cost(actor) return 100 - (hunger_level or 0) end
return Fed
`)
	game, scene, actor, g := goap_setup()
	defer game->terminate()
	ctx := &game.gameContext
	L := game.scriptManager.L
	Goap_AddKey(g, "Hunger")
	Goap_AddKey(g, "Rested")
	s := Goap_AddSensor(g, "Hunger", .Script)
	Goap_SetString(g, &g.sensors[s].script, "goap_hunger.lua")
	fed := Goap_AddGoal(g, "Fed")
	Goap_SetString(g, &g.goals[fed].script, "goap_fed.lua")
	Goap_AddCondition(g, &g.goals[fed].conditions, "Hunger", .Less_Equal, 0)
	rest := Goap_AddGoal(g, "Rest")
	g.goals[rest].baseCost = 50
	Goap_AddCondition(g, &g.goals[rest].conditions, "Rested", .Greater_Equal, 1)
	eat := Goap_AddAction(g, "Eat", .Script)
	Goap_SetString(g, &g.actions[eat].script, "goap_eat.lua")
	Goap_AddEffect(g, &g.actions[eat], "Hunger", false)
	// Rest: a Behavior Tree (Manual) that waits a little.
	bt := cast(^BehaviorTreeNode)Node_CreateByTypeName(scene, "BehaviorTreeNode", actor)
	bt.name = strings.clone("Nap", bt.allocator)
	bt.processMode = .Manual
	ProcessNodeQueues(scene.manager, ctx)
	BT_AddNode(bt, -1, .Wait)
	bt.nodes[0].number = 0.1
	nap := Goap_AddAction(g, "Nap", .Behavior_Tree)
	Goap_SetString(g, &g.actions[nap].node, "../Nap")
	Goap_AddEffect(g, &g.actions[nap], "Rested", true)

	// Hungry (the Lua sensor): Fed costs 100 - 80 = 20 < Rest's 50.
	lua.pushinteger(L, 80)
	lua.setglobal(L, "hunger_level")
	GoapNode_Advance(g, 0.05)
	hunger, _ := Goap_GetValue(g, "Hunger")
	testing.expect_value(t, hunger, 80)
	testing.expect_value(t, g.goal, fed)
	testing.expect_value(t, g.action, eat)
	testing.expect_value(t, Goap_ActionCost(g, eat), 2)
	// Two bites, then a wait, then completed.
	lua.pushinteger(L, 0)
	lua.setglobal(L, "hunger_level")
	g.sensors[s].timer = .Once // (keep the value the action sets)
	GoapNode_Advance(g, 0.05) // bite 2: sets Hunger 0, waits
	testing.expect_value(t, g.runState, Goap_Run_State.Wait)
	GoapNode_Advance(g, 0.2)  // (the goal's met: it completes)
	testing.expect(t, g.goal != fed, "fed")

	// Rest: the tree runs until it succeeds.
	for _ in 0 ..< 20 do GoapNode_Advance(g, 0.05)
	rested, _ := Goap_GetValue(g, "Rested")
	testing.expect_value(t, rested, 1)

	// Lua: request a goal, keys, the plan, the state.
	push_node_userdata(L, g)
	lua.setglobal(L, "agent")
	Goap_SetValue(g, "Rested", 0)
	text, _ := Lua_Eval(L, `agent:goap_request_goal("Rest"); agent:goap_resolve(); return agent:goap_goal() .. " " .. agent:goap_action() .. " " .. #agent:goap_plan() .. " " .. agent:goap_get_key("Rested") .. " " .. agent:goap_state()`, context.temp_allocator)
	testing.expect_value(t, text, `"Rest Nap 1 0 performing"`)
	testing.expect_value(t, len(g.requested), 1)
	free_all(context.temp_allocator)
}

@(test)
test_goap_saving :: proc(t: ^testing.T) {
	game, scene, _, g := goap_setup()
	defer game->terminate()
	Goap_AddKey(g, "Wood", global = true, initial = 2)
	Goap_AddKey(g, "TreeSpot", target = true)
	gi := Goap_AddGoal(g, "GatherWood")
	Goap_AddCondition(g, &g.goals[gi].conditions, "Wood", .Greater, 5)
	a := Goap_AddAction(g, "Chop", .Call_Method)
	Goap_SetString(g, &g.actions[a].method, "chop")
	Goap_SetString(g, &g.actions[a].target, "TreeSpot")
	g.actions[a].requiresTarget = true
	g.actions[a].moveMode = .Perform_While_Moving
	Goap_AddEffect(g, &g.actions[a], "Wood", true)
	s := Goap_AddSensor(g, "TreeSpot", .Nearest_Tag, "tree")
	g.sensors[s].timer = .Interval
	g.sensors[s].interval = 0.5
	w := Json_Writer{sb = strings.builder_make(context.temp_allocator)}
	first := true
	strings.write_byte(&w.sb, '{')
	Goap_WriteJSON(&w, g, &first)
	strings.write_byte(&w.sb, '}')
	saved := strings.to_string(w.sb)
	testing.expectf(t, strings.contains(saved, `"keys": [{"name": "Wood", "global": true, "initial": 2}, {"name": "TreeSpot", "target": true}]`), "keys: %s", saved)
	testing.expectf(t, strings.contains(saved, `{"name": "GatherWood", "cost": 1, "conditions": [{"key": "Wood", "cmp": ">", "amount": 5}]}`), "goal: %s", saved)
	testing.expectf(t, strings.contains(saved, `"kind": "Call_Method", "cost": 1, "method": "chop", "seconds": 1, "target": "TreeSpot", "stopping_distance": 16, "requires_target": true, "move_mode": "Perform_While_Moving"`), "action: %s", saved)
	testing.expectf(t, strings.contains(saved, `{"key": "TreeSpot", "kind": "Nearest_Tag", "timer": "Interval", "interval": 0.5, "text": "tree"}`), "sensor: %s", saved)
	v, err := json.parse_string(saved, allocator = context.temp_allocator)
	testing.expect(t, err == nil, "parses")
	g2 := cast(^GoapNode)Node_CreateByTypeName(scene, "GoapNode")
	Goap_ReadJSON(g2, v.(json.Object)["goap"].(json.Object))
	testing.expect(t, len(g2.keys) == 2 && g2.keys[0].global && g2.keys[0].initial == 2 && g2.keys[1].target, "keys back")
	testing.expect(t, len(g2.goals) == 1 && g2.goals[0].conditions[0].cmp == .Greater && g2.goals[0].conditions[0].amount == 5, "goal back")
	testing.expect(t, len(g2.actions) == 1 && g2.actions[0].kind == .Call_Method && g2.actions[0].requiresTarget && g2.actions[0].moveMode == .Perform_While_Moving && g2.actions[0].effects[0].increase, "action back")
	testing.expect(t, len(g2.sensors) == 1 && g2.sensors[0].kind == .Nearest_Tag && g2.sensors[0].interval == 0.5, "sensor back")
	testing.expect(t, strings.contains(Scene_SerializeToJSON(scene, context.temp_allocator), `"goap": {"keys"`), "in the scene")
	// Conditions and effects.
	testing.expect(t, Goap_Satisfies({"Wood", true}, {key = "Wood", cmp = .Greater_Equal}) && !Goap_Satisfies({"Wood", false}, {key = "Wood", cmp = .Greater}), "satisfies")
	testing.expect(t, Goap_Met({cmp = .Less_Equal, amount = 3}, 3, 0) && !Goap_Met({cmp = .Less, amount = 3}, 3, 0) && Goap_Met({cmp = .Greater, refKey = "x"}, 4, 3), "met")
	free_all(context.temp_allocator)
}
