package engine

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:strings"

// ============================================================================
// GOAP - goal-oriented action planning (after crashkonijn/GOAP): an agent
// picks, from the goals it's asked for, the cheapest one it can reach, and
// the action to do first on the way there.
//
//   World keys are whole numbers (HasAxe 0 / 1, Hunger 0-100, Wood 3),
//   kept fresh by sensors (or set by scripts and by actions' effects).
//   Target keys are positions (a node or a point), from target sensors.
//   Goals have conditions on world keys (Hunger <= 20) and a cost (their
//   priority: cheaper wins; a script can work it out).
//   Actions have conditions too, effects (Wood up, Hunger down), a cost,
//   and optionally a target to go to first (in range: Stopping Distance).
//
// The planner searches back from each goal: a condition not met now leads
// to the actions whose effects move that key the right way (> and >=: up,
// < and <=: down), and so on until it reaches an action it can do now (its
// conditions met, its target known). The cheapest such path wins - costs of
// the actions, the goal's cost, and distance (Distance Multiplier) between
// targets. Only that first action runs; when it ends the agent plans again.
// It doesn't simulate the world: sensors tell it how things are.
//
// Global keys and sensors are shared by every GOAP agent (the world's
// state); local ones are each agent's.
// ============================================================================

Goap_Compare :: enum u8 {
	Greater_Equal,
	Greater,
	Less_Equal,
	Less,
}

GOAP_COMPARE_TEXT := [Goap_Compare]string{.Greater_Equal = ">=", .Greater = ">", .Less_Equal = "<=", .Less = "<"}

Goap_Condition :: struct {
	key:    string,
	cmp:    Goap_Compare,
	amount: int,
	refKey: string, // compare with this key's value instead of Amount ("": Amount)
}

Goap_Effect :: struct {
	key:      string,
	increase: bool,
}

Goap_Goal :: struct {
	name:       string,
	baseCost:   f32,
	script:     string, // a Lua goal (`X.goap = "goal"`): get_cost(actor) ("": Base Cost)
	conditions: [dynamic]Goap_Condition,
	inst:       i32, // its Lua instance (runtime)
	instPath:   string,
	instBad:    bool,
}

Goap_Action_Kind :: enum u8 {
	Script,        // a Lua action (`X.goap = "action"`): start / perform / ...
	Behavior_Tree, // runs a Behavior Tree node (set to Manual) until it answers
	Wait,          // waits Seconds, then completes
	Call_Method,   // calls a method of the actor's script (its answer: the run state)
	Play_Animation,// plays an animation on the actor's Animation Player; completes when it ends
}

Goap_Move_Mode :: enum u8 {
	Move_Before_Performing, // go into range, then perform (staying there)
	Perform_While_Moving,   // perform every frame on the way too
}

Goap_Action :: struct {
	name:               string,
	kind:               Goap_Action_Kind,
	script:             string,
	props:              map[string]ScriptValue, // a Lua action's property values
	node:               string,  // Behavior Tree / Animation Player path
	method:             string,  // Call Method / the animation's name
	seconds:            f32,     // Wait
	baseCost:           f32,
	target:             string,  // a target key ("": no target)
	stoppingDistance:   f32,
	requiresTarget:     bool,
	validateConditions: bool,    // stop when its conditions stop being met
	moveMode:           Goap_Move_Mode,
	conditions:         [dynamic]Goap_Condition,
	effects:            [dynamic]Goap_Effect,
	// runtime
	disabledUntil:      f64,     // -1: disabled; > now: for a time
	inst:               i32,     // its Lua instance (registry ref)
	instPath:           string,
	instBad:            bool,
	lastCost:           f32,     // the cost at the last plan (the live graph)
}

Goap_Sensor_Kind :: enum u8 {
	Script,       // a Lua sensor (`X.goap = "sensor"`): sense(actor)
	Method,       // a method of the actor's script returns it
	Property,     // a node's number property (world) / position (target)
	Nearest_Tag,  // target: the nearest node with a tag (world: how many there are)
	Node,         // target: a node (world: 1 while it exists)
}

Goap_Timer :: enum u8 {
	Always,   // every frame
	Once,     // the first time only
	Interval, // every Interval seconds
}

Goap_Sensor :: struct {
	key:      string,  // the key it fills (world or target, from the key's kind)
	kind:     Goap_Sensor_Kind,
	script:   string,
	props:    map[string]ScriptValue,
	node:     string,  // Property / Node: a path ("": the actor)
	text:     string,  // Method: its name; Property: the property; Nearest Tag: the tag
	timer:    Goap_Timer,
	interval: f32,
	// runtime
	nextAt:   f64,
	sensed:   bool,
	inst:     i32,
	instPath: string,
	instBad:  bool,
}

Goap_Key :: struct {
	name:    string,
	target:  bool, // a target (position) key; else a world (number) key
	global:  bool, // shared by every GOAP agent
	initial: int,  // a world key's starting value
}

Goap_Target :: struct {
	pos:   [2]f32,
	valid: bool,
	node:  string, // the node it follows ("": a fixed position)
}

// The world: global keys' values (every agent) and when they were sensed.
goapGlobalKeys:    map[string]int
goapGlobalTargets: map[string]Goap_Target
goapGlobalSensed:  map[string]f64 // key -> the game time it was last sensed

Goap_ResetGlobals :: proc() {
	for k in goapGlobalKeys do delete(k, Engine_HeapAllocator())
	delete(goapGlobalKeys)
	goapGlobalKeys = nil
	for k, t in goapGlobalTargets {
		delete(k, Engine_HeapAllocator())
		delete(t.node, Engine_HeapAllocator())
	}
	delete(goapGlobalTargets)
	goapGlobalTargets = nil
	for k in goapGlobalSensed do delete(k, Engine_HeapAllocator())
	delete(goapGlobalSensed)
	goapGlobalSensed = nil
}

// Goap_Met: a condition against a value (and the referenced key's).
Goap_Met :: proc(c: Goap_Condition, value: int, ref: int) -> bool {
	b := ref if c.refKey != "" else c.amount
	switch c.cmp {
	case .Greater_Equal: return value >= b
	case .Greater:       return value > b
	case .Less_Equal:    return value <= b
	case .Less:          return value < b
	}
	return false
}

// Goap_Satisfies: an effect moves a condition's key its way.
Goap_Satisfies :: proc(e: Goap_Effect, c: Goap_Condition) -> bool {
	if e.key != c.key do return false
	up := c.cmp == .Greater_Equal || c.cmp == .Greater
	return e.increase == up
}

// Goap_Conflicts: an effect pushes a condition's key the wrong way.
Goap_Conflicts :: proc(e: Goap_Effect, c: Goap_Condition) -> bool {
	return e.key == c.key && !Goap_Satisfies(e, c)
}

Goap_ConditionText :: proc(c: Goap_Condition, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("%s %s %s", c.key, GOAP_COMPARE_TEXT[c.cmp], c.refKey if c.refKey != "" else fmt.tprintf("%d", c.amount), allocator = allocator)
}

// ----------------------------------------------------------------------------
// The planner: A* back from the goals.
// ----------------------------------------------------------------------------

// Goap_World: what the planner asks of the agent.
Goap_World :: struct {
	user:       rawptr,
	value:      proc(user: rawptr, key: string) -> (int, bool),
	target:     proc(user: rawptr, key: string) -> (Goap_Target, bool),
	actionCost: proc(user: rawptr, i: int) -> f32,
	goalCost:   proc(user: rawptr, i: int) -> f32,
	enabled:    proc(user: rawptr, i: int) -> bool,
	agentPos:   [2]f32,
	distanceMultiplier: f32,
}

Goap_Plan :: struct {
	goal:    int,         // -1: none found
	actions: [dynamic]int, // the first one runs; then on to the goal
	cost:    f32,
}

@(private = "file")
Goap_Search_Node :: struct {
	action: int,   // -1: a goal
	goal:   int,
	parent: int,   // search node index (-1: none)
	pos:    [2]f32,
	g, f:   f32,
	depth:  int,
}

GOAP_MAX_DEPTH :: 16

// Goap_ConditionMet: a condition against the world now.
Goap_ConditionMet :: proc(w: ^Goap_World, c: Goap_Condition) -> bool {
	v, _ := w.value(w.user, c.key)
	ref := 0
	if c.refKey != "" do ref, _ = w.value(w.user, c.refKey)
	return Goap_Met(c, v, ref)
}

// Goap_Executable: an action that can run now.
Goap_Executable :: proc(w: ^Goap_World, a: ^Goap_Action, i: int) -> bool {
	if !w.enabled(w.user, i) do return false
	for c in a.conditions do if !Goap_ConditionMet(w, c) do return false
	if a.requiresTarget && a.target != "" {
		t, ok := w.target(w.user, a.target)
		if !ok || !t.valid do return false
	}
	return true
}

// Goap_Resolve plans for the requested goals (indices into goals): the
// goal reached cheapest and the actions from the first one to it.
Goap_Resolve :: proc(w: ^Goap_World, goals: []Goap_Goal, actions: []Goap_Action, requested: []int, allocator := context.allocator) -> (plan: Goap_Plan) {
	plan.goal = -1
	plan.actions = make([dynamic]int, allocator)
	nodes := make([dynamic]Goap_Search_Node, context.temp_allocator)
	open := make([dynamic]int, context.temp_allocator)
	dist :: proc(a, b: [2]f32) -> f32 {
		d := a - b
		return math.sqrt(d.x * d.x + d.y * d.y)
	}
	// h: for each unmet condition, the cheapest action that moves it.
	h :: proc(w: ^Goap_World, conds: []Goap_Condition, actions: []Goap_Action) -> f32 {
		total: f32 = 0
		for c in conds {
			if Goap_ConditionMet(w, c) do continue
			best: f32 = -1
			for &a, i in actions {
				if !w.enabled(w.user, i) do continue
				for e in a.effects do if Goap_Satisfies(e, c) {
					cost := w.actionCost(w.user, i)
					if best < 0 || cost < best do best = cost
				}
			}
			if best > 0 do total += best
		}
		return total
	}
	for gi in requested {
		if gi < 0 || gi >= len(goals) do continue
		g := &goals[gi]
		done := true
		for c in g.conditions do if !Goap_ConditionMet(w, c) do done = false
		if done do continue // (already met: nothing to do for it)
		cost := w.goalCost(w.user, gi)
		append(&nodes, Goap_Search_Node{action = -1, goal = gi, parent = -1, pos = w.agentPos, g = cost, f = cost + h(w, g.conditions[:], actions)})
		append(&open, len(nodes) - 1)
	}
	inPath :: proc(nodes: []Goap_Search_Node, n, action: int) -> bool {
		for p := n; p >= 0; p = nodes[p].parent do if nodes[p].action == action do return true
		return false
	}
	for len(open) > 0 && len(nodes) < 4096 {
		// the cheapest open node
		bi := 0
		for k in 1 ..< len(open) do if nodes[open[k]].f < nodes[open[bi]].f do bi = k
		ni := open[bi]
		unordered_remove(&open, bi)
		n := nodes[ni]
		if n.action >= 0 && Goap_Executable(w, &actions[n.action], n.action) {
			// Found: the path from this action up to its goal.
			plan.goal = n.goal
			plan.cost = n.g
			for p := ni; p >= 0 && nodes[p].action >= 0; p = nodes[p].parent do append(&plan.actions, nodes[p].action)
			return
		}
		if n.depth >= GOAP_MAX_DEPTH do continue
		conds := goals[n.goal].conditions[:] if n.action < 0 else actions[n.action].conditions[:]
		for c in conds {
			if Goap_ConditionMet(w, c) do continue
			for &a, ai in actions {
				if !w.enabled(w.user, ai) || inPath(nodes[:], ni, ai) do continue
				moves, conflicts := false, false
				for e in a.effects {
					if Goap_Satisfies(e, c) do moves = true
					for pc in conds do if Goap_Conflicts(e, pc) do conflicts = true
				}
				if !moves || conflicts do continue
				pos := n.pos
				if a.target != "" {
					if t, ok := w.target(w.user, a.target); ok && t.valid do pos = t.pos
				}
				cost := w.actionCost(w.user, ai)
				g := n.g + cost + dist(n.pos, pos) * w.distanceMultiplier
				append(&nodes, Goap_Search_Node{action = ai, goal = n.goal, parent = ni, pos = pos, g = g, depth = n.depth + 1})
				k := len(nodes) - 1
				nodes[k].f = g + dist(w.agentPos, pos) * w.distanceMultiplier + h(w, a.conditions[:], actions)
				append(&open, k)
			}
		}
	}
	return
}

// ----------------------------------------------------------------------------
// Saved with the scene: "goap": {"keys", "goals", "actions", "sensors"}.
// ----------------------------------------------------------------------------

@(private = "file")
goap_write_conditions :: proc(w: ^Json_Writer, list: []Goap_Condition) {
	strings.write_byte(&w.sb, '[')
	for c, i in list {
		if i > 0 do strings.write_string(&w.sb, ", ")
		strings.write_string(&w.sb, "{\"key\": ")
		Json_String(w, c.key)
		fmt.sbprintf(&w.sb, ", \"cmp\": \"%s\"", GOAP_COMPARE_TEXT[c.cmp])
		if c.refKey != "" {
			strings.write_string(&w.sb, ", \"ref\": ")
			Json_String(w, c.refKey)
		} else {
			fmt.sbprintf(&w.sb, ", \"amount\": %d", c.amount)
		}
		strings.write_byte(&w.sb, '}')
	}
	strings.write_byte(&w.sb, ']')
}

@(private = "file")
goap_write_props :: proc(w: ^Json_Writer, props: map[string]ScriptValue) {
	if len(props) == 0 do return
	strings.write_string(&w.sb, ", \"properties\": {")
	keys := make([dynamic]string, context.temp_allocator)
	for k in props do append(&keys, k)
	for i in 1 ..< len(keys) do for j := i; j > 0 && keys[j] < keys[j - 1]; j -= 1 do keys[j], keys[j - 1] = keys[j - 1], keys[j]
	for k, j in keys {
		if j > 0 do strings.write_string(&w.sb, ", ")
		Json_String(w, k)
		strings.write_string(&w.sb, ": ")
		v := props[k]
		switch v.type {
		case .Float:   Json_Float(w, v.valFloat)
		case .Int:     fmt.sbprintf(&w.sb, "%d", v.valInt)
		case .Boolean: strings.write_string(&w.sb, "true" if v.valBool else "false")
		case .Vector2: fmt.sbprintf(&w.sb, "[%v, %v]", v.valVec2.x, v.valVec2.y)
		case .Color:   fmt.sbprintf(&w.sb, "[%v, %v, %v, %v]", v.valColor[0], v.valColor[1], v.valColor[2], v.valColor[3])
		case .String:  Json_String(w, v.valString)
		}
	}
	strings.write_byte(&w.sb, '}')
}

Goap_WriteJSON :: proc(w: ^Json_Writer, g: ^GoapNode, first: ^bool) {
	Json_Key(w, "goap", first)
	str :: proc(w: ^Json_Writer, key, v: string) {
		if v == "" do return
		fmt.sbprintf(&w.sb, ", \"%s\": ", key)
		Json_String(w, v)
	}
	strings.write_string(&w.sb, "{\"keys\": [")
	for k, i in g.keys {
		if i > 0 do strings.write_string(&w.sb, ", ")
		strings.write_string(&w.sb, "{\"name\": ")
		Json_String(w, k.name)
		if k.target do strings.write_string(&w.sb, ", \"target\": true")
		if k.global do strings.write_string(&w.sb, ", \"global\": true")
		if k.initial != 0 do fmt.sbprintf(&w.sb, ", \"initial\": %d", k.initial)
		strings.write_byte(&w.sb, '}')
	}
	strings.write_string(&w.sb, "], \"goals\": [")
	for &goal, i in g.goals {
		if i > 0 do strings.write_string(&w.sb, ", ")
		strings.write_string(&w.sb, "{\"name\": ")
		Json_String(w, goal.name)
		strings.write_string(&w.sb, ", \"cost\": ")
		Json_Float(w, goal.baseCost)
		str(w, "script", goal.script)
		strings.write_string(&w.sb, ", \"conditions\": ")
		goap_write_conditions(w, goal.conditions[:])
		strings.write_byte(&w.sb, '}')
	}
	strings.write_string(&w.sb, "], \"actions\": [")
	for &a, i in g.actions {
		if i > 0 do strings.write_string(&w.sb, ", ")
		strings.write_string(&w.sb, "{\"name\": ")
		Json_String(w, a.name)
		fmt.sbprintf(&w.sb, ", \"kind\": \"%v\", \"cost\": ", a.kind)
		Json_Float(w, a.baseCost)
		str(w, "script", a.script)
		str(w, "node", a.node)
		str(w, "method", a.method)
		if a.seconds != 0 {
			strings.write_string(&w.sb, ", \"seconds\": ")
			Json_Float(w, a.seconds)
		}
		str(w, "target", a.target)
		if a.stoppingDistance != 0 {
			strings.write_string(&w.sb, ", \"stopping_distance\": ")
			Json_Float(w, a.stoppingDistance)
		}
		if a.requiresTarget do strings.write_string(&w.sb, ", \"requires_target\": true")
		if a.validateConditions do strings.write_string(&w.sb, ", \"validate_conditions\": true")
		if a.moveMode != .Move_Before_Performing do fmt.sbprintf(&w.sb, ", \"move_mode\": \"%v\"", a.moveMode)
		strings.write_string(&w.sb, ", \"conditions\": ")
		goap_write_conditions(w, a.conditions[:])
		strings.write_string(&w.sb, ", \"effects\": [")
		for e, j in a.effects {
			if j > 0 do strings.write_string(&w.sb, ", ")
			strings.write_string(&w.sb, "{\"key\": ")
			Json_String(w, e.key)
			fmt.sbprintf(&w.sb, ", \"increase\": %v}", e.increase)
		}
		strings.write_byte(&w.sb, ']')
		goap_write_props(w, a.props)
		strings.write_byte(&w.sb, '}')
	}
	strings.write_string(&w.sb, "], \"sensors\": [")
	for &s, i in g.sensors {
		if i > 0 do strings.write_string(&w.sb, ", ")
		strings.write_string(&w.sb, "{\"key\": ")
		Json_String(w, s.key)
		fmt.sbprintf(&w.sb, ", \"kind\": \"%v\", \"timer\": \"%v\"", s.kind, s.timer)
		if s.timer == .Interval {
			strings.write_string(&w.sb, ", \"interval\": ")
			Json_Float(w, s.interval)
		}
		str(w, "script", s.script)
		str(w, "node", s.node)
		str(w, "text", s.text)
		goap_write_props(w, s.props)
		strings.write_byte(&w.sb, '}')
	}
	strings.write_string(&w.sb, "]}")
}

@(private = "file")
goap_read_conditions :: proc(g: ^GoapNode, v: json.Value) -> [dynamic]Goap_Condition {
	out := make([dynamic]Goap_Condition, g.allocator)
	list, ok := v.(json.Array)
	if !ok do return out
	for it in list {
		o, cok := it.(json.Object)
		if !cok do continue
		c := Goap_Condition{key = goap_str(g, o, "key"), refKey = goap_str(g, o, "ref")}
		if t, tok := o["cmp"].(json.String); tok {
			for cmp in Goap_Compare do if GOAP_COMPARE_TEXT[cmp] == t do c.cmp = cmp
		}
		n, _ := json_number(o["amount"])
		c.amount = int(n)
		append(&out, c)
	}
	return out
}

@(private = "file")
goap_str :: proc(g: ^GoapNode, o: json.Object, key: string) -> string {
	s, _ := o[key].(json.String)
	return strings.clone(s, g.allocator) if s != "" else ""
}

@(private = "file")
goap_read_props :: proc(g: ^GoapNode, o: json.Object) -> map[string]ScriptValue {
	props, ok := o["properties"].(json.Object)
	if !ok do return nil
	out := make(map[string]ScriptValue, g.allocator)
	for k, v in parse_script_overrides(props) {
		sv := v
		if sv.valString != "" do sv.valString = strings.clone(sv.valString, g.allocator)
		out[strings.clone(k, g.allocator)] = sv
	}
	return out
}

@(private = "file")
goap_enum :: proc(o: json.Object, key: string, $T: typeid) -> (out: T) {
	s, _ := o[key].(json.String)
	for v in T do if fmt.tprintf("%v", v) == s do return v
	return
}

Goap_ReadJSON :: proc(g: ^GoapNode, obj: json.Object) {
	Goap_ClearDefinitions(g)
	if list, ok := obj["keys"].(json.Array); ok {
		for it in list {
			o, kok := it.(json.Object)
			if !kok do continue
			n, _ := json_number(o["initial"])
			append(&g.keys, Goap_Key{name = goap_str(g, o, "name"), target = o["target"].(json.Boolean) or_else false, global = o["global"].(json.Boolean) or_else false, initial = int(n)})
		}
	}
	if list, ok := obj["goals"].(json.Array); ok {
		for it in list {
			o, gok := it.(json.Object)
			if !gok do continue
			c, _ := json_number(o["cost"])
			append(&g.goals, Goap_Goal{name = goap_str(g, o, "name"), baseCost = c, script = goap_str(g, o, "script"), conditions = goap_read_conditions(g, o["conditions"])})
		}
	}
	if list, ok := obj["actions"].(json.Array); ok {
		for it in list {
			o, aok := it.(json.Object)
			if !aok do continue
			a := Goap_Action{name = goap_str(g, o, "name"), kind = goap_enum(o, "kind", Goap_Action_Kind)}
			a.baseCost, _ = json_number(o["cost"])
			a.script = goap_str(g, o, "script")
			a.node = goap_str(g, o, "node")
			a.method = goap_str(g, o, "method")
			a.seconds, _ = json_number(o["seconds"])
			a.target = goap_str(g, o, "target")
			a.stoppingDistance, _ = json_number(o["stopping_distance"])
			a.requiresTarget = o["requires_target"].(json.Boolean) or_else false
			a.validateConditions = o["validate_conditions"].(json.Boolean) or_else false
			a.moveMode = goap_enum(o, "move_mode", Goap_Move_Mode)
			a.conditions = goap_read_conditions(g, o["conditions"])
			a.effects = make([dynamic]Goap_Effect, g.allocator)
			if el, eok := o["effects"].(json.Array); eok {
				for e in el {
					eo, ok2 := e.(json.Object)
					if !ok2 do continue
					append(&a.effects, Goap_Effect{goap_str(g, eo, "key"), eo["increase"].(json.Boolean) or_else true})
				}
			}
			a.props = goap_read_props(g, o)
			append(&g.actions, a)
		}
	}
	if list, ok := obj["sensors"].(json.Array); ok {
		for it in list {
			o, sok := it.(json.Object)
			if !sok do continue
			s := Goap_Sensor{key = goap_str(g, o, "key"), kind = goap_enum(o, "kind", Goap_Sensor_Kind), timer = goap_enum(o, "timer", Goap_Timer)}
			s.interval, _ = json_number(o["interval"])
			s.script = goap_str(g, o, "script")
			s.node = goap_str(g, o, "node")
			s.text = goap_str(g, o, "text")
			s.props = goap_read_props(g, o)
			append(&g.sensors, s)
		}
	}
}

// ----------------------------------------------------------------------------
// Editing helpers (the editor's tab, Lua).
// ----------------------------------------------------------------------------

Goap_SetString :: proc(g: ^GoapNode, s: ^string, value: string) {
	if s^ == value do return
	delete(s^, g.allocator)
	s^ = strings.clone(value, g.allocator) if value != "" else ""
}

Goap_AddGoal :: proc(g: ^GoapNode, name: string) -> int {
	append(&g.goals, Goap_Goal{name = strings.clone(name, g.allocator), baseCost = 1, conditions = make([dynamic]Goap_Condition, g.allocator)})
	return len(g.goals) - 1
}

Goap_AddAction :: proc(g: ^GoapNode, name: string, kind := Goap_Action_Kind.Wait) -> int {
	append(&g.actions, Goap_Action{name = strings.clone(name, g.allocator), kind = kind, baseCost = 1, seconds = 1, stoppingDistance = 16, conditions = make([dynamic]Goap_Condition, g.allocator), effects = make([dynamic]Goap_Effect, g.allocator)})
	return len(g.actions) - 1
}

Goap_AddKey :: proc(g: ^GoapNode, name: string, target := false, global := false, initial := 0) -> int {
	append(&g.keys, Goap_Key{strings.clone(name, g.allocator), target, global, initial})
	return len(g.keys) - 1
}

Goap_AddSensor :: proc(g: ^GoapNode, key: string, kind: Goap_Sensor_Kind, text := "") -> int {
	append(&g.sensors, Goap_Sensor{key = strings.clone(key, g.allocator), kind = kind, text = strings.clone(text, g.allocator) if text != "" else ""})
	return len(g.sensors) - 1
}

Goap_AddCondition :: proc(g: ^GoapNode, list: ^[dynamic]Goap_Condition, key: string, cmp: Goap_Compare, amount: int) {
	append(list, Goap_Condition{key = strings.clone(key, g.allocator), cmp = cmp, amount = amount})
}

Goap_AddEffect :: proc(g: ^GoapNode, a: ^Goap_Action, key: string, increase: bool) {
	append(&a.effects, Goap_Effect{strings.clone(key, g.allocator), increase})
}

@(private = "file")
goap_free_conditions :: proc(g: ^GoapNode, list: ^[dynamic]Goap_Condition) {
	for c in list {
		delete(c.key, g.allocator)
		delete(c.refKey, g.allocator)
	}
	delete(list^)
}

@(private = "file")
goap_free_props :: proc(g: ^GoapNode, props: ^map[string]ScriptValue) {
	for k, v in props {
		delete(k, g.allocator)
		if v.valString != "" do delete(v.valString, g.allocator)
	}
	delete(props^)
	props^ = nil
}

Goap_FreeGoal :: proc(g: ^GoapNode, goal: ^Goap_Goal) {
	goap_release_instance(g, &goal.inst, &goal.instPath)
	delete(goal.name, g.allocator)
	delete(goal.script, g.allocator)
	goap_free_conditions(g, &goal.conditions)
}

Goap_FreeAction :: proc(g: ^GoapNode, a: ^Goap_Action) {
	goap_release_instance(g, &a.inst, &a.instPath)
	for s in ([]string{a.name, a.script, a.node, a.method, a.target}) do delete(s, g.allocator)
	goap_free_conditions(g, &a.conditions)
	for e in a.effects do delete(e.key, g.allocator)
	delete(a.effects)
	goap_free_props(g, &a.props)
}

Goap_FreeSensor :: proc(g: ^GoapNode, s: ^Goap_Sensor) {
	goap_release_instance(g, &s.inst, &s.instPath)
	for x in ([]string{s.key, s.script, s.node, s.text}) do delete(x, g.allocator)
	goap_free_props(g, &s.props)
}

Goap_ClearDefinitions :: proc(g: ^GoapNode) {
	GoapNode_Stop(g)
	for &goal in g.goals do Goap_FreeGoal(g, &goal)
	clear(&g.goals)
	for &a in g.actions do Goap_FreeAction(g, &a)
	clear(&g.actions)
	for &s in g.sensors do Goap_FreeSensor(g, &s)
	clear(&g.sensors)
	for k in g.keys do delete(k.name, g.allocator)
	clear(&g.keys)
}
