package engine

import "core:c"
import "core:fmt"
import "core:math"
import "core:strings"
import lua "lua54"

// ============================================================================
// The GOAP node: an agent (its keys, goals, actions and sensors: goap.odin)
// that senses, plans and runs actions for its actor (its parent).
//
// Each frame: sensors fill keys (on their timers); a goal whose conditions
// are met completes; with no action (or one that ended, or Resolve Interval
// passed while the action allows it) it plans; then the action runs - going
// to its target first (Navigation Agent, else straight at Move Speed), then
// performing until it completes or stops.
//
// Lua actions (`X.goap = "action"`): start(actor), is_valid(actor),
// before_perform(actor), perform(actor, ctx) -> "continue" /
// "continue_or_resolve" / "completed" / "stop" / {wait = s [, then = ...]},
// finish(actor) at the end, get_cost(actor, target). Lua sensors
// (`X.goap = "sensor"`): sense(actor) -> a number (world key) or a node /
// vector (target key). Lua goals (`X.goap = "goal"`): get_cost(actor).
// ============================================================================

Goap_Agent_State :: enum u8 {
	No_Action,
	Moving_To_Target,
	Performing_Action,
	Moving_While_Performing,
}

Goap_Run_State :: enum u8 {
	Continue,
	Continue_Or_Resolve,
	Completed,
	Stop,
	Wait,
}

GoapNode :: struct {
	using node:         Node,
	active:             bool `gui:"true"`,
	actor:              string `gui:"true"`,                 // the node it acts for ("": its parent)
	requestAll:         bool `gui:"true"`,                   // every goal is requested at the start
	resolveInterval:    f32 `gui:"true" min:"0" max:"60"`,   // plan again this often (0: only when an action ends)
	distanceMultiplier: f32 `gui:"true" min:"0" max:"10"`,   // distance's part of an action's cost (per px)
	moveSpeed:          f32 `gui:"true" min:"0" max:"5000"`, // px/s going to a target without a Navigation Agent
	keys:               [dynamic]Goap_Key,
	goals:              [dynamic]Goap_Goal,
	actions:            [dynamic]Goap_Action,
	sensors:            [dynamic]Goap_Sensor,
	onGoalStarted:      EventSubject,
	onGoalCompleted:    EventSubject,
	onActionStarted:    EventSubject,
	onActionCompleted:  EventSubject,
	onActionStopped:    EventSubject,
	onNoAction:         EventSubject,
	// runtime
	values:             map[string]int,
	targets:            map[string]Goap_Target,
	sensedAt:           map[string]f64,
	requested:          [dynamic]int,
	goal:               int,   // -1: none
	action:             int,   // -1: none
	plan:               [dynamic]int,
	planCost:           f32,
	state:              Goap_Agent_State,
	inRange:            bool,
	performing:         bool,  // before_perform ran
	runState:           Goap_Run_State,
	waitUntil:          f64,
	waitThen:           Goap_Run_State,
	actionTime:         f32,
	time:               f64,
	nextResolve:        f64,
	needResolve:        bool,
	started:            bool,
	noActionSent:       bool,
	resolves:           u64,
}

GoapNode_Create :: proc(scene: ^Scene, name: string = "GOAP", parent: ^Node = nil) -> ^GoapNode {
	g := CreateNode(scene.manager, GoapNode)
	GoapNode_Init(g)
	g.name = strings.clone(name, g.allocator)
	scene->addNode(g, parent)
	return g
}

GoapNode_Init :: proc(g: ^GoapNode) {
	InitializeSubject(&g.onGoalStarted, "goal_started", g)       // a new goal (its name)
	InitializeSubject(&g.onGoalCompleted, "goal_completed", g)   // the goal's conditions are met (its name)
	InitializeSubject(&g.onActionStarted, "action_started", g)   // an action began (its name)
	InitializeSubject(&g.onActionCompleted, "action_completed", g) // an action completed (its name)
	InitializeSubject(&g.onActionStopped, "action_stopped", g)   // an action stopped early (its name)
	InitializeSubject(&g.onNoAction, "no_action_found", g)       // nothing it can do reaches a requested goal
	g.active = true
	g.requestAll = true
	g.resolveInterval = 1
	g.distanceMultiplier = 0.01
	g.moveSpeed = 120
	g.renderable = false
	g.goal, g.action = -1, -1
	g.keys = make([dynamic]Goap_Key, g.allocator)
	g.goals = make([dynamic]Goap_Goal, g.allocator)
	g.actions = make([dynamic]Goap_Action, g.allocator)
	g.sensors = make([dynamic]Goap_Sensor, g.allocator)
	g.update = GoapNode_Update
	g.onDestroy = GoapNode_Destroy
}

GoapNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	g := cast(^GoapNode)node
	Goap_ClearDefinitions(g)
	delete(g.keys)
	delete(g.goals)
	delete(g.actions)
	delete(g.sensors)
	goap_clear_state(g)
	delete(g.requested)
	delete(g.plan)
	for s in ([]^EventSubject{&g.onGoalStarted, &g.onGoalCompleted, &g.onActionStarted, &g.onActionCompleted, &g.onActionStopped, &g.onNoAction}) do DestroySubject(s)
}

@(private = "file")
goap_clear_state :: proc(g: ^GoapNode) {
	for k in g.values do delete(k, Engine_HeapAllocator())
	delete(g.values)
	g.values = nil
	for k, t in g.targets {
		delete(k, Engine_HeapAllocator())
		delete(t.node, Engine_HeapAllocator())
	}
	delete(g.targets)
	g.targets = nil
	for k in g.sensedAt do delete(k, Engine_HeapAllocator())
	delete(g.sensedAt)
	g.sensedAt = nil
}

// GoapNode_Stop ends the running action and forgets the plan and the
// sensed state (the next update starts again).
GoapNode_Stop :: proc(g: ^GoapNode) {
	if g.action >= 0 && g.action < len(g.actions) do goap_end_action(g, false)
	g.action, g.goal = -1, -1
	clear(&g.plan)
	g.state = .No_Action
	g.started = false
	goap_clear_state(g)
	for &s in g.sensors do s.sensed = false
}

// ----------------------------------------------------------------------------
// Keys: local ones in the agent, global ones shared.
// ----------------------------------------------------------------------------

Goap_FindKey :: proc(g: ^GoapNode, name: string) -> int {
	for k, i in g.keys do if k.name == name do return i
	return -1
}

@(private = "file")
goap_is_global :: proc(g: ^GoapNode, key: string) -> bool {
	i := Goap_FindKey(g, key)
	return i >= 0 && g.keys[i].global
}

Goap_GetValue :: proc(g: ^GoapNode, key: string) -> (int, bool) {
	if goap_is_global(g, key) do return goapGlobalKeys[key] or_else 0, key in goapGlobalKeys
	if v, ok := g.values[key]; ok do return v, true
	if i := Goap_FindKey(g, key); i >= 0 do return g.keys[i].initial, false
	return 0, false
}

Goap_SetValue :: proc(g: ^GoapNode, key: string, v: int) {
	m := &goapGlobalKeys if goap_is_global(g, key) else &g.values
	if m^ == nil do m^ = make(map[string]int, Engine_HeapAllocator())
	if key in m^ {
		for k in m^ do if k == key {m^[k] = v; break}
	} else {
		m^[strings.clone(key, Engine_HeapAllocator())] = v
	}
	goap_mark_sensed(g, key)
}

Goap_GetTarget :: proc(g: ^GoapNode, key: string) -> (Goap_Target, bool) {
	m := &goapGlobalTargets if goap_is_global(g, key) else &g.targets
	t, ok := m[key]
	if ok && t.node != "" {
		// A node target follows it.
		if n := goap_resolve(g, t.node); n != nil do t.pos = n.globalPosition
		else do t.valid = false
	}
	return t, ok
}

Goap_SetTarget :: proc(g: ^GoapNode, key: string, t: Goap_Target) {
	m := &goapGlobalTargets if goap_is_global(g, key) else &g.targets
	if m^ == nil do m^ = make(map[string]Goap_Target, Engine_HeapAllocator())
	nt := t
	nt.node = strings.clone(t.node, Engine_HeapAllocator()) if t.node != "" else ""
	for k, old in m^ do if k == key {
		delete(old.node, Engine_HeapAllocator())
		m^[k] = nt
		goap_mark_sensed(g, key)
		return
	}
	m^[strings.clone(key, Engine_HeapAllocator())] = nt
	goap_mark_sensed(g, key)
}

@(private = "file")
goap_mark_sensed :: proc(g: ^GoapNode, key: string) {
	m := &goapGlobalSensed if goap_is_global(g, key) else &g.sensedAt
	if m^ == nil do m^ = make(map[string]f64, Engine_HeapAllocator())
	for k in m^ do if k == key {m^[k] = g.time; return}
	m^[strings.clone(key, Engine_HeapAllocator())] = g.time
}

// Goap_SensedAge: seconds since a key was sensed or set (-1: never).
Goap_SensedAge :: proc(g: ^GoapNode, key: string) -> f64 {
	m := &goapGlobalSensed if goap_is_global(g, key) else &g.sensedAt
	if t, ok := m[key]; ok do return max(g.time - t, 0)
	return -1
}

// ----------------------------------------------------------------------------
// Nodes.
// ----------------------------------------------------------------------------

Goap_Actor :: proc(g: ^GoapNode) -> ^Node {
	if g.actor != "" do return goap_resolve(g, g.actor)
	return g.parent
}

@(private = "file")
goap_manager :: proc(n: ^Node) -> ^NodeManager {
	for cur := n; cur != nil; cur = cur.parent do if cur.gameContext != nil && cur.gameContext.scene != nil do return cur.gameContext.scene.manager
	return nil
}

@(private = "file")
goap_resolve :: proc(g: ^GoapNode, path: string) -> ^Node {
	mgr := goap_manager(g)
	if mgr == nil || path == "" do return nil
	if path == "." do return g
	return Node_ResolvePath(mgr, g, path)
}

@(private = "file")
goap_scripts :: proc(g: ^GoapNode) -> ^ScriptManager {
	for cur := cast(^Node)g; cur != nil; cur = cur.parent do if cur.gameContext != nil && cur.gameContext.scriptManager != nil do return cur.gameContext.scriptManager
	return nil
}

@(private = "file")
goap_child_of :: proc(g: ^GoapNode, of: ^Node, type: typeid) -> ^Node {
	mgr := goap_manager(g)
	if mgr == nil || of == nil do return nil
	for c in GetChildrenView(mgr, of) do if c != nil && c.typeId == type do return c
	for c in GetChildrenView(mgr, of) {
		if c == nil do continue
		for gc in GetChildrenView(mgr, c) do if gc != nil && gc.typeId == type do return gc
	}
	return nil
}

// ----------------------------------------------------------------------------
// The update.
// ----------------------------------------------------------------------------

GoapNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	g := cast(^GoapNode)node
	if !g.active {
		if g.started do GoapNode_Stop(g)
		return
	}
	GoapNode_Advance(g, deltaTime)
}

// GoapNode_Advance runs the agent for dt seconds (the update; tests).
GoapNode_Advance :: proc(g: ^GoapNode, dt: f32) {
	if Goap_Actor(g) == nil do return
	g.time += f64(dt)
	if !g.started {
		g.started = true
		g.needResolve = true
		if g.requestAll && len(g.requested) == 0 do for _, i in g.goals do append(&g.requested, i)
	}
	goap_sense(g)
	// The goal reached?
	if g.goal >= 0 && g.goal < len(g.goals) && goap_goal_met(g, g.goal) {
		name := g.goals[g.goal].name
		if g.action >= 0 do goap_end_action(g, true)
		g.goal = -1
		clear(&g.plan)
		g.needResolve = true
		g.onGoalCompleted->notify(g, name, g.gameContext)
	}
	mayResolve := g.action < 0 || g.runState == .Continue_Or_Resolve
	if g.needResolve || (g.resolveInterval > 0 && g.time >= g.nextResolve && mayResolve) do GoapNode_Resolve(g)
	if g.action >= 0 do goap_run_action(g, dt)
}

@(private = "file")
goap_goal_met :: proc(g: ^GoapNode, i: int) -> bool {
	for c in g.goals[i].conditions do if !goap_condition_met(g, c) do return false
	return true
}

@(private = "file")
goap_condition_met :: proc(g: ^GoapNode, c: Goap_Condition) -> bool {
	v, _ := Goap_GetValue(g, c.key)
	ref := 0
	if c.refKey != "" do ref, _ = Goap_GetValue(g, c.refKey)
	return Goap_Met(c, v, ref)
}

// Goap_ActionEnabled: not disabled (for good, or still for a time).
Goap_ActionEnabled :: proc(g: ^GoapNode, i: int) -> bool {
	a := &g.actions[i]
	return a.disabledUntil == 0 || (a.disabledUntil > 0 && g.time >= a.disabledUntil)
}

// GoapNode_Resolve plans now: the goal and the action to do first.
GoapNode_Resolve :: proc(g: ^GoapNode) {
	g.needResolve = false
	g.nextResolve = g.time + f64(g.resolveInterval)
	g.resolves += 1
	actor := Goap_Actor(g)
	w := Goap_World{
		user = g,
		value = proc(user: rawptr, key: string) -> (int, bool) {return Goap_GetValue(cast(^GoapNode)user, key)},
		target = proc(user: rawptr, key: string) -> (Goap_Target, bool) {return Goap_GetTarget(cast(^GoapNode)user, key)},
		actionCost = proc(user: rawptr, i: int) -> f32 {return Goap_ActionCost(cast(^GoapNode)user, i)},
		goalCost = proc(user: rawptr, i: int) -> f32 {return Goap_GoalCost(cast(^GoapNode)user, i)},
		enabled = proc(user: rawptr, i: int) -> bool {return Goap_ActionEnabled(cast(^GoapNode)user, i)},
		agentPos = actor.globalPosition if actor != nil else {},
		distanceMultiplier = g.distanceMultiplier,
	}
	for &a, i in g.actions do a.lastCost = Goap_ActionCost(g, i)
	plan := Goap_Resolve(&w, g.goals[:], g.actions[:], g.requested[:], context.temp_allocator)
	if plan.goal < 0 {
		if g.action >= 0 do goap_end_action(g, false)
		g.goal = -1
		clear(&g.plan)
		if !g.noActionSent {
			g.noActionSent = true
			g.onNoAction->notify(g, nil, g.gameContext)
		}
		return
	}
	g.noActionSent = false
	clear(&g.plan)
	for a in plan.actions do append(&g.plan, a)
	g.planCost = plan.cost
	if plan.goal != g.goal {
		g.goal = plan.goal
		g.onGoalStarted->notify(g, g.goals[g.goal].name, g.gameContext)
	}
	first := plan.actions[0]
	if first != g.action {
		if g.action >= 0 do goap_end_action(g, false)
		goap_start_action(g, first)
	}
}

// Goap_ActionCost: Base Cost, or a Lua action's get_cost(actor, target).
Goap_ActionCost :: proc(g: ^GoapNode, i: int) -> f32 {
	a := &g.actions[i]
	if a.kind != .Script || a.script == "" do return a.baseCost
	L, top, eh, ok := goap_lua_begin(g, &a.inst, &a.instPath, &a.instBad, a.script, a.props, "get_cost")
	if !ok do return a.baseCost
	defer lua.settop(L, top)
	t, has := Goap_GetTarget(g, a.target)
	if has && t.valid do Lua_PushVec2(L, t.pos)
	else do lua.pushnil(L)
	if !goap_lua_call(g, L, 1, eh, "get_cost") || lua.type(L, -1) != .NUMBER do return a.baseCost
	return f32(lua.tonumber(L, -1))
}

// Goap_GoalCost: Base Cost, or a Lua goal's get_cost(actor).
Goap_GoalCost :: proc(g: ^GoapNode, i: int) -> f32 {
	goal := &g.goals[i]
	if goal.script == "" do return goal.baseCost
	L, top, eh, ok := goap_lua_begin(g, &goal.inst, &goal.instPath, &goal.instBad, goal.script, nil, "get_cost")
	if !ok do return goal.baseCost
	defer lua.settop(L, top)
	if !goap_lua_call(g, L, 0, eh, "get_cost") || lua.type(L, -1) != .NUMBER do return goal.baseCost
	return f32(lua.tonumber(L, -1))
}

// ----------------------------------------------------------------------------
// Running an action.
// ----------------------------------------------------------------------------

@(private = "file")
goap_start_action :: proc(g: ^GoapNode, i: int) {
	g.action = i
	g.performing = false
	g.runState = .Continue
	g.actionTime = 0
	g.inRange = false
	a := &g.actions[i]
	g.state = .Moving_To_Target if a.target != "" else .Performing_Action
	#partial switch a.kind {
	case .Script:
		goap_lua_simple(g, &a.inst, &a.instPath, &a.instBad, a.script, a.props, "start")
	case .Behavior_Tree:
		if bt := goap_tree(g, a); bt != nil do BehaviorTree_Interrupt(bt)
	}
	g.onActionStarted->notify(g, a.name, g.gameContext)
}

// goap_end_action: the action ends (completed: its effects on keys no
// sensor fills; else stopped).
@(private = "file")
goap_end_action :: proc(g: ^GoapNode, completed: bool) {
	i := g.action
	if i < 0 || i >= len(g.actions) do return
	a := &g.actions[i]
	g.action = -1
	g.state = .No_Action
	#partial switch a.kind {
	case .Script:
		goap_lua_simple(g, &a.inst, &a.instPath, &a.instBad, a.script, a.props, "finish")
	case .Behavior_Tree:
		if bt := goap_tree(g, a); bt != nil do BehaviorTree_Interrupt(bt)
	}
	goap_stop_moving(g)
	if completed {
		for e in a.effects {
			sensed := false
			for s in g.sensors do if s.key == e.key do sensed = true
			if sensed do continue
			v, _ := Goap_GetValue(g, e.key)
			Goap_SetValue(g, e.key, v + (1 if e.increase else -1))
		}
		g.onActionCompleted->notify(g, a.name, g.gameContext)
	} else {
		g.onActionStopped->notify(g, a.name, g.gameContext)
	}
	g.needResolve = true
}

@(private = "file")
goap_tree :: proc(g: ^GoapNode, a: ^Goap_Action) -> ^BehaviorTreeNode {
	n := goap_resolve(g, a.node)
	if n == nil || n.typeId != BehaviorTreeNode do return nil
	return cast(^BehaviorTreeNode)n
}

@(private = "file")
goap_run_action :: proc(g: ^GoapNode, dt: f32) {
	a := &g.actions[g.action]
	actor := Goap_Actor(g)
	// Still valid?
	valid := Goap_ActionEnabled(g, g.action)
	if valid && a.validateConditions do for c in a.conditions do if !goap_condition_met(g, c) do valid = false
	if valid && a.requiresTarget && a.target != "" {
		t, ok := Goap_GetTarget(g, a.target)
		if !ok || !t.valid do valid = false
	}
	if valid && a.kind == .Script {
		if L, top, eh, ok := goap_lua_begin(g, &a.inst, &a.instPath, &a.instBad, a.script, a.props, "is_valid"); ok {
			if goap_lua_call(g, L, 0, eh, "is_valid") && lua.type(L, -1) == .BOOLEAN && !lua.toboolean(L, -1) do valid = false
			lua.settop(L, top)
		}
	}
	if !valid {
		goap_end_action(g, false)
		return
	}
	// Its target: go there first.
	if a.target != "" {
		t, ok := Goap_GetTarget(g, a.target)
		if ok && t.valid && actor != nil {
			d := t.pos - actor.globalPosition
			dist := math.sqrt(d.x * d.x + d.y * d.y)
			g.inRange = dist <= max(a.stoppingDistance, 0.5)
			if !g.inRange {
				goap_move(g, actor, t.pos, dt)
				if a.moveMode == .Move_Before_Performing && !g.performing {
					g.state = .Moving_To_Target
					return
				}
				g.state = .Moving_While_Performing if a.moveMode == .Perform_While_Moving else .Performing_Action
			} else {
				goap_stop_moving(g)
				g.state = .Performing_Action
			}
		} else {
			g.inRange = true
			g.state = .Performing_Action
		}
	} else {
		g.inRange = true
		g.state = .Performing_Action
	}
	// Waiting (a run state)?
	if g.runState == .Wait {
		if g.time < g.waitUntil do return
		g.runState = g.waitThen
		switch g.runState {
		case .Completed: goap_end_action(g, true); return
		case .Stop:      goap_end_action(g, false); return
		case .Continue, .Continue_Or_Resolve, .Wait:
		}
	}
	if !g.performing {
		g.performing = true
		if a.kind == .Script do goap_lua_simple(g, &a.inst, &a.instPath, &a.instBad, a.script, a.props, "before_perform")
	}
	g.actionTime += dt
	s := goap_perform(g, a, dt)
	if g.action < 0 do return // (ended inside)
	switch s {
	case .Completed: goap_end_action(g, true)
	case .Stop:      goap_end_action(g, false)
	case .Continue, .Continue_Or_Resolve, .Wait: g.runState = s
	}
}

@(private = "file")
goap_perform :: proc(g: ^GoapNode, a: ^Goap_Action, dt: f32) -> Goap_Run_State {
	actor := Goap_Actor(g)
	switch a.kind {
	case .Script:
		L, top, eh, ok := goap_lua_begin(g, &a.inst, &a.instPath, &a.instBad, a.script, a.props, "perform")
		if !ok do return .Stop if a.instBad || a.script == "" else .Completed
		defer lua.settop(L, top)
		lua.createtable(L, 0, 3)
		lua.pushnumber(L, lua.Number(dt))
		lua.setfield(L, -2, "dt")
		lua.pushboolean(L, b32(g.inRange))
		lua.setfield(L, -2, "in_range")
		lua.pushnumber(L, lua.Number(g.actionTime))
		lua.setfield(L, -2, "time")
		if !goap_lua_call(g, L, 1, eh, "perform") do return .Stop
		return goap_run_state(g, L, -1)
	case .Behavior_Tree:
		bt := goap_tree(g, a)
		if bt == nil do return .Stop
		switch BehaviorTree_Tick(bt, dt) {
		case .Running, .None: return .Continue
		case .Success:        return .Completed
		case .Failure:        return .Stop
		}
	case .Wait:
		return .Completed if g.actionTime >= a.seconds else .Continue
	case .Call_Method:
		if actor == nil || actor.scriptInstance == nil || a.method == "" do return .Stop
		inst := cast(^ScriptInstance)actor.scriptInstance
		mgr := goap_scripts(g)
		if mgr == nil || !inst.isReady do return .Stop
		L := mgr.L
		top := lua.gettop(L)
		defer lua.settop(L, top)
		lua.pushcfunction(L, lua_traceback_error_handler)
		eh := lua.gettop(L)
		lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef))
		lua.getfield(L, -1, strings.clone_to_cstring(a.method, context.temp_allocator))
		if lua.type(L, -1) != .FUNCTION do return .Stop
		lua.pushvalue(L, -2)
		lua.pushnumber(L, lua.Number(dt))
		prev := mgr.currentInstance
		mgr.currentInstance = inst
		defer mgr.currentInstance = prev
		if lua.pcall(L, 2, 1, eh) != 0 {
			Script_Problem(.Error, "[GOAP] %s: error in %s(): %s", g.name, a.method, lua.tostring(L, -1))
			return .Stop
		}
		return goap_run_state(g, L, -1)
	case .Play_Animation:
		apn: ^AnimationPlayerNode
		if a.node != "" {
			if p := goap_resolve(g, a.node); p != nil && p.typeId == AnimationPlayerNode do apn = cast(^AnimationPlayerNode)p
		} else if p := goap_child_of(g, actor, AnimationPlayerNode); p != nil {
			apn = cast(^AnimationPlayerNode)p
		}
		if apn == nil do return .Stop
		if g.actionTime <= dt + 1e-6 {
			AnimationPlayerNode_Play(apn, a.method)
			return .Continue
		}
		return .Continue if apn.playing else .Completed
	}
	return .Stop
}

// goap_run_state reads a Lua answer: "continue", "continue_or_resolve",
// "completed", "stop", true (completed) / false (stop), nil (completed),
// {wait = seconds, then = "completed" / "stop" / "continue"}.
@(private = "file")
goap_run_state :: proc(g: ^GoapNode, L: ^lua.State, idx: c.int) -> Goap_Run_State {
	#partial switch lua.type(L, idx) {
	case .NIL:     return .Completed
	case .BOOLEAN: return .Completed if lua.toboolean(L, idx) else .Stop
	case .STRING:
		switch strings.to_lower(string(lua.tostring(L, idx)), context.temp_allocator) {
		case "continue", "running":         return .Continue
		case "continue_or_resolve":         return .Continue_Or_Resolve
		case "completed", "complete", "success", "done": return .Completed
		}
		return .Stop
	case .TABLE:
		t := lua.absindex(L, idx)
		lua.getfield(L, t, "wait")
		secs := f64(lua.tonumber(L, -1))
		lua.pop(L, 1)
		lua.getfield(L, t, "then")
		then := strings.to_lower(string(lua.tostring(L, -1)), context.temp_allocator) if lua.type(L, -1) == .STRING else "continue"
		lua.pop(L, 1)
		g.waitUntil = g.time + secs
		switch then {
		case "completed", "complete": g.waitThen = .Completed
		case "stop":                  g.waitThen = .Stop
		case:                         g.waitThen = .Continue
		}
		return .Wait
	}
	return .Stop
}

@(private = "file")
goap_move :: proc(g: ^GoapNode, actor: ^Node, goal: [2]f32, dt: f32) {
	if agent := goap_child_of(g, actor, NavigationAgentNode); agent != nil {
		NavAgent_SetTarget(cast(^NavigationAgentNode)agent, goal)
		return
	}
	d := goal - actor.globalPosition
	dist := math.sqrt(d.x * d.x + d.y * d.y)
	if dist <= 0 do return
	step := min(g.moveSpeed * dt, dist)
	actor.position += d / dist * step
	actor.globalPosition += d / dist * step
}

@(private = "file")
goap_stop_moving :: proc(g: ^GoapNode) {
	actor := Goap_Actor(g)
	if actor == nil do return
	if agent := goap_child_of(g, actor, NavigationAgentNode); agent != nil do NavAgent_Stop(cast(^NavigationAgentNode)agent)
}

// ----------------------------------------------------------------------------
// Sensors.
// ----------------------------------------------------------------------------

@(private = "file")
goap_sense :: proc(g: ^GoapNode) {
	actor := Goap_Actor(g)
	for &s in g.sensors {
		switch s.timer {
		case .Always:
		case .Once:     if s.sensed do continue
		case .Interval: if s.sensed && g.time < s.nextAt do continue
		}
		s.sensed = true
		s.nextAt = g.time + f64(max(s.interval, 0))
		ki := Goap_FindKey(g, s.key)
		isTarget := ki >= 0 && g.keys[ki].target
		Goap_SenseOnce(g, &s, actor, isTarget)
	}
}

// Goap_SenseOnce runs a sensor now.
Goap_SenseOnce :: proc(g: ^GoapNode, s: ^Goap_Sensor, actor: ^Node, isTarget: bool) {
	target := actor if s.node == "" else goap_resolve(g, s.node)
	switch s.kind {
	case .Script, .Method:
		L: ^lua.State
		top, eh: c.int
		ok: bool
		if s.kind == .Script {
			L, top, eh, ok = goap_lua_begin(g, &s.inst, &s.instPath, &s.instBad, s.script, s.props, "sense")
			if !ok do return
			if !goap_lua_call(g, L, 0, eh, "sense") {
				lua.settop(L, top)
				return
			}
		} else {
			if actor == nil || actor.scriptInstance == nil || s.text == "" do return
			inst := cast(^ScriptInstance)actor.scriptInstance
			mgr := goap_scripts(g)
			if mgr == nil || !inst.isReady do return
			L = mgr.L
			top = lua.gettop(L)
			lua.pushcfunction(L, lua_traceback_error_handler)
			eh = lua.gettop(L)
			lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef))
			lua.getfield(L, -1, strings.clone_to_cstring(s.text, context.temp_allocator))
			if lua.type(L, -1) != .FUNCTION {
				lua.settop(L, top)
				return
			}
			lua.pushvalue(L, -2)
			if lua.pcall(L, 1, 1, eh) != 0 {
				Script_Problem(.Error, "[GOAP] %s: error in %s(): %s", g.name, s.text, lua.tostring(L, -1))
				lua.settop(L, top)
				return
			}
		}
		defer lua.settop(L, top)
		if isTarget {
			goap_set_target_from_lua(g, s.key, L, -1)
		} else {
			#partial switch lua.type(L, -1) {
			case .NUMBER:  Goap_SetValue(g, s.key, int(math.round(f64(lua.tonumber(L, -1)))))
			case .BOOLEAN: Goap_SetValue(g, s.key, 1 if lua.toboolean(L, -1) else 0)
			}
		}
	case .Property:
		if target == nil do return
		if isTarget {
			Goap_SetTarget(g, s.key, {pos = target.globalPosition, valid = true, node = goap_path(g, target)})
		} else if v, ok := Osc_ReadProperty(target, s.text); ok {
			Goap_SetValue(g, s.key, int(math.round(v[0])))
		}
	case .Nearest_Tag:
		scene := actor.gameContext.scene if actor != nil && actor.gameContext != nil else nil
		if scene == nil do return
		found := Scene_FindByTag(scene, s.text)
		if !isTarget {
			Goap_SetValue(g, s.key, len(found))
			return
		}
		best: ^Node
		bestD: f32 = -1
		for n in found {
			if n == actor do continue
			d := n.globalPosition - actor.globalPosition
			dd := d.x * d.x + d.y * d.y
			if bestD < 0 || dd < bestD {best, bestD = n, dd}
		}
		if best == nil do Goap_SetTarget(g, s.key, {})
		else do Goap_SetTarget(g, s.key, {pos = best.globalPosition, valid = true, node = goap_path(g, best)})
	case .Node:
		n := goap_resolve(g, s.node)
		if isTarget {
			if n == nil do Goap_SetTarget(g, s.key, {})
			else do Goap_SetTarget(g, s.key, {pos = n.globalPosition, valid = true, node = goap_path(g, n)})
		} else {
			Goap_SetValue(g, s.key, 1 if n != nil else 0)
		}
	}
}

@(private = "file")
goap_path :: proc(g: ^GoapNode, n: ^Node) -> string {
	mgr := goap_manager(g)
	if mgr == nil do return ""
	return Node_RelativePath(mgr, g, n)
}

// goap_set_target_from_lua: a node, a vector ({x, y}) or nil (no target).
goap_set_target_from_lua :: proc(g: ^GoapNode, key: string, L: ^lua.State, idx: c.int) {
	#partial switch lua.type(L, idx) {
	case .USERDATA:
		if n, ok := to_node_userdata(L, idx); ok {
			Goap_SetTarget(g, key, {pos = n.globalPosition, valid = true, node = goap_path(g, n)})
			return
		}
	case .TABLE:
		x, y := arg_xy(L, idx)
		Goap_SetTarget(g, key, {pos = {x, y}, valid = true})
		return
	}
	Goap_SetTarget(g, key, {})
}

// ----------------------------------------------------------------------------
// Lua instances (actions, sensors, goals): one per entry, made on first use.
// ----------------------------------------------------------------------------

@(private = "file")
goap_instance :: proc(g: ^GoapNode, inst: ^i32, instPath: ^string, bad: ^bool, script: string, props: map[string]ScriptValue) -> bool {
	mgr := goap_scripts(g)
	if mgr == nil || mgr.L == nil || script == "" do return false
	if inst^ != 0 && instPath^ == script do return true
	if bad^ && instPath^ == script do return false
	goap_release_instance(g, inst, instPath)
	instPath^ = strings.clone(script, Engine_HeapAllocator())
	mod, ok := ScriptManager_LoadModule(script, mgr)
	if !ok || mod == nil {
		bad^ = true
		Script_Problem(.Warning, "[GOAP] %s: script %s didn't load", g.name, script)
		return false
	}
	bad^ = false
	L := mgr.L
	lua.newtable(L)
	idx := lua.gettop(L)
	lua.newtable(L)
	lua.getfield(L, lua.REGISTRYINDEX, strings.clone_to_cstring(strings.concatenate({"__Engine_Module_", mod.path}, context.temp_allocator), context.temp_allocator))
	lua.setfield(L, -2, "__index")
	lua.setmetatable(L, idx)
	{
		context.allocator = context.temp_allocator
		values := make(map[string]ScriptValue)
		script_apply_properties(L, idx, mod, props, &values)
	}
	push_node_userdata(L, g)
	lua.setfield(L, idx, "agent")
	if actor := Goap_Actor(g); actor != nil {
		push_node_userdata(L, actor)
		lua.setfield(L, idx, "actor")
	}
	inst^ = i32(lua.L_ref(L, lua.REGISTRYINDEX))
	return true
}

goap_release_instance :: proc(g: ^GoapNode, inst: ^i32, instPath: ^string) {
	if inst^ != 0 {
		if mgr := goap_scripts(g); mgr != nil && mgr.L != nil do lua.L_unref(mgr.L, lua.REGISTRYINDEX, inst^)
		inst^ = 0
	}
	delete(instPath^, Engine_HeapAllocator())
	instPath^ = ""
}

// goap_lua_begin pushes [handler, instance, method, self, actor]; false
// when there's no such method (nothing left pushed).
@(private = "file")
goap_lua_begin :: proc(g: ^GoapNode, inst: ^i32, instPath: ^string, bad: ^bool, script: string, props: map[string]ScriptValue, method: string) -> (L: ^lua.State, top, eh: c.int, ok: bool) {
	if !goap_instance(g, inst, instPath, bad, script, props) do return
	L = goap_scripts(g).L
	top = lua.gettop(L)
	lua.pushcfunction(L, lua_traceback_error_handler)
	eh = lua.gettop(L)
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst^))
	lua.getfield(L, -1, strings.clone_to_cstring(method, context.temp_allocator))
	if lua.type(L, -1) != .FUNCTION {
		lua.settop(L, top)
		return L, top, eh, false
	}
	lua.pushvalue(L, -2)
	if actor := Goap_Actor(g); actor != nil do push_node_userdata(L, actor)
	else do lua.pushnil(L)
	return L, top, eh, true
}

// goap_lua_call calls what goap_lua_begin pushed (+ nargs more); the answer at -1.
@(private = "file")
goap_lua_call :: proc(g: ^GoapNode, L: ^lua.State, nargs: c.int, eh: c.int, method: string) -> bool {
	if lua.pcall(L, 2 + nargs, 1, eh) != 0 {
		Script_Problem(.Error, "[GOAP] %s: error in %s(): %s", g.name, method, lua.tostring(L, -1))
		return false
	}
	return true
}

@(private = "file")
goap_lua_simple :: proc(g: ^GoapNode, inst: ^i32, instPath: ^string, bad: ^bool, script: string, props: map[string]ScriptValue, method: string) {
	L, top, eh, ok := goap_lua_begin(g, inst, instPath, bad, script, props, method)
	if !ok do return
	goap_lua_call(g, L, 0, eh, method)
	lua.settop(L, top)
}

// ----------------------------------------------------------------------------
// The live view (the editor reads the node in Simulate; the game sends this
// in Play).
// ----------------------------------------------------------------------------

Goap_StatusJSON :: proc(g: ^GoapNode, path: string, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make(allocator)
	strings.write_string(&sb, "{\"path\": ")
	strings.write_quoted_string(&sb, path)
	fmt.sbprintf(&sb, ", \"goal\": %d, \"action\": %d, \"state\": %d, \"in_range\": %v, \"resolves\": %d, \"time\": %.2f, \"plan\": [", g.goal, g.action, int(g.state), g.inRange, g.resolves, g.time)
	for a, i in g.plan {
		if i > 0 do strings.write_string(&sb, ", ")
		fmt.sbprintf(&sb, "%d", a)
	}
	strings.write_string(&sb, "], \"action_costs\": [")
	for &a, i in g.actions {
		if i > 0 do strings.write_string(&sb, ", ")
		fmt.sbprintf(&sb, "[%.2f, %v]", a.lastCost, Goap_ActionEnabled(g, i))
	}
	strings.write_string(&sb, "], \"goal_costs\": [")
	for _, i in g.goals {
		if i > 0 do strings.write_string(&sb, ", ")
		fmt.sbprintf(&sb, "%.2f", Goap_GoalCost(g, i))
	}
	strings.write_string(&sb, "], \"keys\": [")
	for k, i in g.keys {
		if i > 0 do strings.write_string(&sb, ", ")
		age := Goap_SensedAge(g, k.name)
		if k.target {
			t, ok := Goap_GetTarget(g, k.name)
			fmt.sbprintf(&sb, "[%v, %.1f, %.1f, %.1f]", ok && t.valid, t.pos.x, t.pos.y, age)
		} else {
			v, _ := Goap_GetValue(g, k.name)
			fmt.sbprintf(&sb, "[%d, %.1f]", v, age)
		}
	}
	strings.write_string(&sb, "]}")
	return strings.to_string(sb)
}
