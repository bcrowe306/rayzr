package engine

import "core:c"
import "core:fmt"
import "core:log"
import "core:math"
import "core:strings"
import "core:time"
import lua "lua54"

// ============================================================================
// The Behavior Tree node and its runtime (the data: behavior_tree.odin).
// ============================================================================

BehaviorTreeNode :: struct {
	using node:     Node,
	active:         bool `gui:"true"`,                       // ticks (off: interrupted)
	processMode:    BT_Process `gui:"true"`,
	tickRate:       int `gui:"true" min:"1" max:"600"`,       // ticks every this many frames
	actor:          string `gui:"true"`,                     // the node it acts for ("": its parent)
	blackboardFrom: string `gui:"true"`,                     // another Behavior Tree whose blackboard it shares
	nodes:          [dynamic]BT_Node,
	bbInit:         [dynamic]BT_BB_Entry,
	onEnabled:      EventSubject,
	onDisabled:     EventSubject,
	// runtime
	bb:             map[string]BB_Value,
	bbReady:        bool,
	status:         BT_Status,
	ticks:          u64,
	frame:          int,
	time:           f64,     // seconds ticked (Cooldown)
	wasActive:      bool,
	runningAction:  int,     // the leaf running (-1: none)
	lastCondition:  int,
	lastConditionStatus: BT_Status,
	tickMicros:     f32,     // the last tick's cost
	bbRef:          i32,     // its blackboard's Lua table (registry ref)
	explain:        bool,    // the editor's live view is open (unused by the game)
}

BehaviorTreeNode_Create :: proc(scene: ^Scene, name: string = "BehaviorTree", parent: ^Node = nil) -> ^BehaviorTreeNode {
	t := CreateNode(scene.manager, BehaviorTreeNode)
	BehaviorTreeNode_Init(t)
	t.name = strings.clone(name, t.allocator)
	scene->addNode(t, parent)
	return t
}

BehaviorTreeNode_Init :: proc(t: ^BehaviorTreeNode) {
	InitializeSubject(&t.onEnabled, "tree_enabled", t)   // Active turned on
	InitializeSubject(&t.onDisabled, "tree_disabled", t) // Active turned off (the tree was interrupted)
	t.active = true
	t.wasActive = true
	t.tickRate = 1
	t.renderable = false
	t.runningAction = -1
	t.lastCondition = -1
	t.nodes = make([dynamic]BT_Node, t.allocator)
	t.bbInit = make([dynamic]BT_BB_Entry, t.allocator)
	t.update = BehaviorTreeNode_Update
	t.onDestroy = BehaviorTreeNode_Destroy
}

BehaviorTreeNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	t := cast(^BehaviorTreeNode)node
	bt_unwatch_all(t)
	BT_ClearNodes(t)
	delete(t.nodes)
	for e in t.bbInit {
		delete(e.key, t.allocator)
		delete(e.value, t.allocator)
	}
	delete(t.bbInit)
	BB_Clear(&t.bb)
	if t.bbRef != 0 {
		if mgr := bt_scripts(t); mgr != nil && mgr.L != nil do lua.L_unref(mgr.L, lua.REGISTRYINDEX, t.bbRef)
	}
	DestroySubject(&t.onEnabled)
	DestroySubject(&t.onDisabled)
}

BehaviorTreeNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	t := cast(^BehaviorTreeNode)node
	if t.active != t.wasActive {
		t.wasActive = t.active
		if t.active {
			t.onEnabled->notify(t, nil, gameContext)
		} else {
			BehaviorTree_Interrupt(t)
			t.onDisabled->notify(t, nil, gameContext)
		}
	}
	if !t.active || t.processMode == .Manual do return
	t.frame += 1
	if t.frame < max(t.tickRate, 1) do return
	t.frame = 0
	BehaviorTree_Tick(t, deltaTime * f32(max(t.tickRate, 1)))
}

// BehaviorTree_Tick runs the tree once (dt: the seconds since its last
// tick); its answer.
BehaviorTree_Tick :: proc(t: ^BehaviorTreeNode, dt: f32) -> BT_Status {
	if len(t.nodes) == 0 || bt_actor(t) == nil {
		t.status = .Failure
		return .Failure
	}
	start := time.tick_now()
	bt_blackboard_ready(t)
	t.ticks += 1
	t.time += f64(dt)
	s := bt_run(t, 0, dt)
	if s != .Running do t.runningAction = -1
	t.status = s
	t.tickMicros = f32(time.duration_microseconds(time.tick_since(start)))
	return s
}

// BehaviorTree_Interrupt stops the running branch (each running node's
// interrupt) and resets the tree to start over.
BehaviorTree_Interrupt :: proc(t: ^BehaviorTreeNode) {
	if len(t.nodes) > 0 && t.nodes[0].rt.status == .Running do bt_interrupt(t, 0)
	for &n in t.nodes {
		bt_runtime_reset(t, &n)
		n.rt.status = .None
	}
	t.status = .None
	t.runningAction = -1
}

// BehaviorTree_Blackboard: the blackboard it uses (its own, or Blackboard From's).
BehaviorTree_Blackboard :: proc(t: ^BehaviorTreeNode) -> ^map[string]BB_Value {
	if t.blackboardFrom != "" {
		if other := bt_resolve(t, t.blackboardFrom); other != nil && other.typeId == BehaviorTreeNode && other != t {
			o := cast(^BehaviorTreeNode)other
			if o.blackboardFrom == "" {
				bt_blackboard_ready(o)
				return &o.bb
			}
		}
	}
	bt_blackboard_ready(t)
	return &t.bb
}

@(private = "file")
bt_blackboard_ready :: proc(t: ^BehaviorTreeNode) {
	if t.bbReady do return
	t.bbReady = true
	for e in t.bbInit do BB_Set(&t.bb, e.key, BB_Parse(e.value))
}

// bt_board: a leaf's blackboard (Global: the shared one).
@(private = "file")
bt_board :: proc(t: ^BehaviorTreeNode, n: ^BT_Node) -> ^map[string]BB_Value {
	return &btGlobal if n.global else BehaviorTree_Blackboard(t)
}

// bt_value: a value's text, "$key" read from the blackboard.
@(private = "file")
bt_value :: proc(t: ^BehaviorTreeNode, n: ^BT_Node, text: string) -> BB_Value {
	if strings.has_prefix(text, "$") {
		bb := bt_board(t, n)
		return bb[text[1:]] or_else nil
	}
	return BB_Parse(text)
}

// bt_actor: the node the tree acts for (its parent by default).
bt_actor :: proc(t: ^BehaviorTreeNode) -> ^Node {
	if t.actor != "" do return bt_resolve(t, t.actor)
	return t.parent
}

@(private = "file")
bt_manager :: proc(t: ^Node) -> ^NodeManager {
	for cur := t; cur != nil; cur = cur.parent {
		if cur.gameContext != nil && cur.gameContext.scene != nil do return cur.gameContext.scene.manager
	}
	return nil
}

bt_resolve :: proc(t: ^BehaviorTreeNode, path: string) -> ^Node {
	mgr := bt_manager(t)
	if mgr == nil || path == "" do return nil
	if path == "." do return t
	return Node_ResolvePath(mgr, t, path)
}

@(private = "file")
bt_scripts :: proc(t: ^BehaviorTreeNode) -> ^ScriptManager {
	for cur := cast(^Node)t; cur != nil; cur = cur.parent {
		if cur.gameContext != nil && cur.gameContext.scriptManager != nil do return cur.gameContext.scriptManager
	}
	return nil
}

// bt_target: a leaf's Target node ("": the actor).
@(private = "file")
bt_target :: proc(t: ^BehaviorTreeNode, n: ^BT_Node) -> ^Node {
	if n.target == "" do return bt_actor(t)
	return bt_resolve(t, n.target)
}

// bt_find_child_of: the first child (then grandchild) of `of` of a type.
@(private = "file")
bt_find_child_of :: proc(t: ^BehaviorTreeNode, of: ^Node, type: typeid) -> ^Node {
	mgr := bt_manager(t)
	if mgr == nil || of == nil do return nil
	for c in GetChildrenView(mgr, of) do if c != nil && c.typeId == type do return c
	for c in GetChildrenView(mgr, of) {
		if c == nil do continue
		for g in GetChildrenView(mgr, c) do if g != nil && g.typeId == type do return g
	}
	return nil
}

// ----------------------------------------------------------------------------
// Running a node: before_run when it starts, after_run when it ends.
// ----------------------------------------------------------------------------

@(private = "file")
bt_run :: proc(t: ^BehaviorTreeNode, i: int, dt: f32) -> BT_Status {
	n := &t.nodes[i]
	if n.rt.status != .Running do bt_before_run(t, i)
	s := bt_tick_node(t, i, dt)
	n = &t.nodes[i] // (a leaf's script may have edited the tree)
	n.rt.status = s
	n.rt.tick = t.ticks
	cat := BT_KINDS[n.kind].category
	if n.kind == .Script do cat = bt_script_category(t, n)
	if s == .Running && cat == .Action do t.runningAction = i
	if cat == .Condition {
		t.lastCondition = i
		t.lastConditionStatus = s
	}
	if s != .Running do bt_after_run(t, i)
	return s
}

// bt_child: run child k of node i, interrupting the child that was running
// before when it's another.
@(private = "file")
bt_child :: proc(t: ^BehaviorTreeNode, i, k: int, dt: f32) -> BT_Status {
	c := t.nodes[i].children[k]
	old := t.nodes[i].rt.running
	s := bt_run(t, c, dt)
	if old >= 0 && old != c && t.nodes[old].rt.status == .Running do bt_interrupt(t, old)
	t.nodes[i].rt.running = c if s == .Running else -1
	return s
}

@(private = "file")
bt_before_run :: proc(t: ^BehaviorTreeNode, i: int) {
	n := &t.nodes[i]
	#partial switch n.kind {
	case .Repeater, .Limiter, .Time_Limiter:
		n.rt.count = 0
		n.rt.timer = 0
	case .Simple_Parallel:
		n.rt.primaryDone = false
		n.rt.repeatLeft = int(n.number)
	case .Sequence_Random, .Selector_Random:
		if len(n.rt.bag) == 0 do bt_shuffle(t, n)
	case .Wait:
		n.rt.timer = 0
		n.rt.duration = n.number + (bt_random(n) * n.number2 if n.number2 > 0 else 0)
	case .Wait_Signal:
		n.rt.timer = 0
		n.rt.fired = false
		bt_watch(t, i)
	case .Play_Animation:
		n.rt.animStarted = false
	case .Script:
		bt_script_call(t, i, "before_run", 0)
	}
}

@(private = "file")
bt_after_run :: proc(t: ^BehaviorTreeNode, i: int) {
	n := &t.nodes[i]
	n.rt.running = -1
	#partial switch n.kind {
	case .Selector, .Sequence_Reactive, .Selector_Reactive:
		n.rt.index = 0
	case .Sequence_Random:
		if !(n.flag && n.rt.status == .Failure) do bt_shuffle(t, n)
	case .Selector_Random:
		bt_shuffle(t, n)
	case .Wait_Signal:
		bt_unwatch(t, i)
	case .Move_To:
		bt_move_stop(t, n)
	case .Script:
		bt_script_call(t, i, "after_run", 0)
	}
}

// bt_interrupt: a running node and its running branch stop.
@(private = "file")
bt_interrupt :: proc(t: ^BehaviorTreeNode, i: int) {
	n := &t.nodes[i]
	if n.kind == .Simple_Parallel {
		for c in n.children do if t.nodes[c].rt.status == .Running do bt_interrupt(t, c)
	} else if r := n.rt.running; r >= 0 && t.nodes[r].rt.status == .Running {
		bt_interrupt(t, r)
	}
	n = &t.nodes[i]
	#partial switch n.kind {
	case .Sequence_Random:
		if !n.flag2 do bt_shuffle(t, n)
	case .Selector_Random:
		bt_shuffle(t, n)
	case .Wait_Signal:
		bt_unwatch(t, i)
	case .Move_To:
		bt_move_stop(t, n)
	case .Play_Animation:
	case .Subtree:
		if sub := bt_subtree(t, n); sub != nil do BehaviorTree_Interrupt(sub)
	case .Script:
		bt_script_call(t, i, "interrupt", 0)
	}
	keepBag := n.kind == .Sequence_Random && n.flag2
	bag := n.rt.bag
	if !keepBag do clear(&n.rt.bag)
	bt_runtime_reset(t, n)
	n.rt.bag = bag
	n.rt.status = .None
	if t.runningAction == i do t.runningAction = -1
}

// bt_runtime_reset: counters back to their start (keeps the Lua instance
// and the shuffled bag).
@(private = "file")
bt_runtime_reset :: proc(t: ^BehaviorTreeNode, n: ^BT_Node) {
	rt := &n.rt
	rt.running = -1
	rt.index = 0
	rt.count = 0
	rt.timer = 0
	rt.until = 0
	rt.primaryDone = false
	rt.fired = false
	rt.animStarted = false
}

bt_runtime_free :: proc(t: ^BehaviorTreeNode, n: ^BT_Node) {
	delete(n.rt.bag)
	n.rt.bag = nil
	if n.rt.inst != 0 {
		if mgr := bt_scripts(t); mgr != nil && mgr.L != nil do lua.L_unref(mgr.L, lua.REGISTRYINDEX, n.rt.inst)
		n.rt.inst = 0
	}
	delete(n.rt.instPath, Engine_HeapAllocator())
	n.rt.instPath = ""
}

// ----------------------------------------------------------------------------
// Each kind's tick.
// ----------------------------------------------------------------------------

@(private = "file")
bt_tick_node :: proc(t: ^BehaviorTreeNode, i: int, dt: f32) -> BT_Status {
	n := &t.nodes[i]
	count := len(n.children)
	switch n.kind {
	case .Sequence, .Sequence_Star:
		for k := n.rt.index; k < count; k += 1 {
			switch bt_child(t, i, k, dt) {
			case .Success, .None:
				t.nodes[i].rt.index = k + 1
			case .Failure:
				t.nodes[i].rt.index = k if t.nodes[i].kind == .Sequence_Star else 0
				return .Failure
			case .Running:
				t.nodes[i].rt.index = k
				return .Running
			}
		}
		t.nodes[i].rt.index = 0
		return .Success
	case .Sequence_Reactive:
		for k in 0 ..< count {
			s := bt_child(t, i, k, dt)
			if s == .Failure || s == .Running do return s
		}
		return .Success
	case .Selector:
		for k := n.rt.index; k < count; k += 1 {
			s := bt_child(t, i, k, dt)
			if s == .Failure {
				t.nodes[i].rt.index = max(t.nodes[i].rt.index, k + 1)
				continue
			}
			return s
		}
		t.nodes[i].rt.index = 0
		return .Failure
	case .Selector_Reactive:
		for k in 0 ..< count {
			s := bt_child(t, i, k, dt)
			if s != .Failure do return s
		}
		return .Failure
	case .Sequence_Random, .Selector_Random:
		isSeq := n.kind == .Sequence_Random
		if len(n.rt.bag) == 0 do bt_shuffle(t, n)
		for len(t.nodes[i].rt.bag) > 0 {
			c := t.nodes[i].rt.bag[0]
			k := -1
			for ch, j in t.nodes[i].children do if ch == c do k = j
			if k < 0 {
				ordered_remove(&t.nodes[i].rt.bag, 0)
				continue
			}
			s := bt_child(t, i, k, dt)
			if s == .Running do return .Running
			ordered_remove(&t.nodes[i].rt.bag, 0)
			if isSeq && s == .Failure do return .Failure
			if !isSeq && s == .Success do return .Success
		}
		return .Success if isSeq else .Failure
	case .Simple_Parallel:
		if count < 2 do return bt_child(t, i, 0, dt) if count == 1 else .Failure
		primary, secondary := n.children[0], n.children[1]
		if !n.rt.primaryDone {
			s := bt_run(t, primary, dt)
			n = &t.nodes[i]
			if s != .Running {
				n.rt.primaryDone = true
				n.rt.primaryStatus = s
			}
		}
		if n.rt.primaryDone && !n.flag {
			if t.nodes[secondary].rt.status == .Running do bt_interrupt(t, secondary)
			return t.nodes[i].rt.primaryStatus
		}
		if n.number <= 0 || n.rt.repeatLeft > 0 {
			s := bt_run(t, secondary, dt)
			n = &t.nodes[i]
			if s != .Running {
				if n.rt.repeatLeft > 0 do n.rt.repeatLeft -= 1
				if n.rt.primaryDone do return n.rt.primaryStatus
			}
		} else if n.rt.primaryDone {
			return n.rt.primaryStatus
		}
		return .Running
	case .Inverter, .Always_Succeed, .Always_Fail, .Until_Fail:
		if count == 0 do return .Failure
		s := bt_child(t, i, 0, dt)
		#partial switch t.nodes[i].kind {
		case .Inverter:
			if s == .Success do return .Failure
			if s == .Failure do return .Success
			return s
		case .Always_Succeed: return .Running if s == .Running else .Success
		case .Always_Fail:    return .Running if s == .Running else .Failure
		case .Until_Fail:     return .Success if s == .Failure else .Running
		}
		return s
	case .Repeater:
		if count == 0 do return .Failure
		if n.rt.count >= int(n.number) do return .Success
		s := bt_child(t, i, 0, dt)
		n = &t.nodes[i]
		if s == .Running do return .Running
		n.rt.count += 1
		if s == .Failure do return .Failure
		return .Success if n.rt.count >= int(n.number) else .Running
	case .Limiter:
		if count == 0 do return .Failure
		if n.rt.count < int(n.number) {
			n.rt.count += 1
			s := bt_child(t, i, 0, dt)
			if s != .Running do t.nodes[i].rt.count = 0
			return s
		}
		if c := n.children[0]; t.nodes[c].rt.status == .Running do bt_interrupt(t, c)
		t.nodes[i].rt.running = -1
		return .Failure
	case .Time_Limiter:
		if count == 0 do return .Failure
		n.rt.timer += dt
		if n.rt.timer >= n.number {
			if c := n.children[0]; t.nodes[c].rt.status == .Running do bt_interrupt(t, c)
			t.nodes[i].rt.running = -1
			return .Failure
		}
		return bt_child(t, i, 0, dt)
	case .Cooldown:
		if count == 0 do return .Failure
		if t.time < n.rt.until do return .Failure
		s := bt_child(t, i, 0, dt)
		if s != .Running do t.nodes[i].rt.until = t.time + f64(t.nodes[i].number)
		return s
	case .Delayer:
		if count == 0 do return .Failure
		if n.rt.timer < n.number {
			n.rt.timer += dt
			return .Running
		}
		s := bt_child(t, i, 0, dt)
		if s != .Running do t.nodes[i].rt.timer = 0
		return s
	case .Wait:
		n.rt.timer += dt
		return .Success if n.rt.timer >= n.rt.duration else .Running
	case .Script:
		return bt_script_tick(t, i, dt)
	case .Move_To:
		return bt_move_to(t, n, dt)
	case .Play_Animation:
		apn: ^AnimationPlayerNode
		if n.target != "" {
			if p := bt_resolve(t, n.target); p != nil && p.typeId == AnimationPlayerNode do apn = cast(^AnimationPlayerNode)p
		} else if p := bt_find_child_of(t, bt_actor(t), AnimationPlayerNode); p != nil {
			apn = cast(^AnimationPlayerNode)p
		}
		if apn == nil do return .Failure
		if !n.rt.animStarted {
			AnimationPlayerNode_Play(apn, n.key)
			n.rt.animStarted = true
			if !n.flag do return .Success
			return .Running
		}
		return .Running if apn.playing else .Success
	case .Set_Property:
		target := bt_target(t, n)
		if target == nil do return .Failure
		text := BB_Text(bt_value(t, n, n.value)) if strings.has_prefix(n.value, "$") else n.value
		if Osc_PropertyWidth(target, n.key) == 1 {
			if f, ok := bt_value(t, n, n.value).(f64); ok {
				Osc_WriteProperty(target, n.key, {f32(f), 0, 0, 0})
				return .Success
			}
		}
		p, found := Track_FindProperty(target, n.key)
		if !found do return .Failure
		return .Success if Property_FromString(target, p, text) else .Failure
	case .Call_Method:
		target := bt_target(t, n)
		if target == nil do return .Failure
		return bt_call_method(t, target, n)
	case .Emit_Signal:
		target := bt_target(t, n)
		if target == nil || n.key == "" do return .Failure
		val: EventValue
		if n.value != "" {
			switch v in bt_value(t, n, n.value) {
			case bool:   val = v
			case f64:    val = v
			case string: val = strings.clone(v, context.temp_allocator)
			case [2]f32: val = BB_Text(v)
			}
		}
		Script_DispatchEvent(target, n.key, val, target.gameContext if target.gameContext != nil else t.gameContext)
		return .Success
	case .Wait_Signal:
		if n.rt.fired do return .Success
		n.rt.timer += dt
		if n.number > 0 && n.rt.timer >= n.number do return .Failure
		return .Running
	case .Blackboard_Set:
		if n.key == "" do return .Failure
		BB_Set(bt_board(t, n), n.key, bt_value(t, n, n.value))
		return .Success
	case .Blackboard_Erase:
		BB_Erase(bt_board(t, n), n.key)
		return .Success
	case .Blackboard_Has:
		bb := bt_board(t, n)
		return .Success if n.key in bb^ else .Failure
	case .Blackboard_Compare:
		bb := bt_board(t, n)
		a, ok := bb[n.key]
		if !ok do return .Failure
		return .Success if BB_Compare(a, bt_value(t, n, n.value), n.op) else .Failure
	case .State_Machine_Set, .State_Machine_Trigger, .State_Machine_In_State:
		sm := bt_state_machine(t, n)
		if sm == nil do return .Failure
		#partial switch n.kind {
		case .State_Machine_Set:
			v: f32
			switch x in bt_value(t, n, n.value) {
			case f64:    v = f32(x)
			case bool:   v = 1 if x else 0
			case string, [2]f32:
			}
			if StateMachine_FindParam(sm, n.key) < 0 do return .Failure
			StateMachine_SetParam(sm, n.key, v)
			return .Success
		case .State_Machine_Trigger:
			return .Success if StateMachine_FireTrigger(sm, n.key) else .Failure
		}
		return .Success if StateMachine_CurrentName(sm) == n.key else .Failure
	case .Subtree:
		sub := bt_subtree(t, n)
		if sub == nil do return .Failure
		return BehaviorTree_Tick(sub, dt)
	case .Log:
		log.infof("[BehaviorTree] %s: %s", t.name, BB_Text(bt_value(t, n, n.value)) if strings.has_prefix(n.value, "$") else n.value)
		return .Success
	}
	return .Failure
}

@(private = "file")
bt_state_machine :: proc(t: ^BehaviorTreeNode, n: ^BT_Node) -> ^StateMachineNode {
	if n.target != "" {
		if p := bt_resolve(t, n.target); p != nil && p.typeId == StateMachineNode do return cast(^StateMachineNode)p
		return nil
	}
	if p := bt_find_child_of(t, bt_actor(t), StateMachineNode); p != nil do return cast(^StateMachineNode)p
	return nil
}

@(private = "file")
bt_subtree :: proc(t: ^BehaviorTreeNode, n: ^BT_Node) -> ^BehaviorTreeNode {
	p := bt_resolve(t, n.target)
	if p == nil || p.typeId != BehaviorTreeNode || p == t do return nil
	return cast(^BehaviorTreeNode)p
}

// ----------------------------------------------------------------------------
// Random composites: a shuffled bag of children (weighted: Efraimidis-Spirakis).
// ----------------------------------------------------------------------------

@(private = "file")
bt_random :: proc(n: ^BT_Node) -> f32 {
	if n.rt.rng == 0 do n.rt.rng = u64(n.seed) * 0x9E3779B97F4A7C15 + 1 if n.seed != 0 else u64(time.tick_now()._nsec) | 1
	n.rt.rng ~= n.rt.rng << 13
	n.rt.rng ~= n.rt.rng >> 7
	n.rt.rng ~= n.rt.rng << 17
	return f32(n.rt.rng >> 40) / f32(1 << 24)
}

bt_shuffle_for_test :: proc(t: ^BehaviorTreeNode, i: int) {bt_shuffle(t, &t.nodes[i])}

@(private = "file")
bt_shuffle :: proc(t: ^BehaviorTreeNode, n: ^BT_Node) {
	clear(&n.rt.bag)
	if n.rt.bag == nil do n.rt.bag = make([dynamic]int, Engine_HeapAllocator())
	keys := make([dynamic]f32, context.temp_allocator)
	for c in n.children {
		w := max(t.nodes[c].weight, 0.0001) if n.weights else 1
		append(&n.rt.bag, c)
		append(&keys, math.pow(max(bt_random(n), 1e-6), 1 / w))
	}
	// sort descending by key
	for i in 1 ..< len(keys) {
		for j := i; j > 0 && keys[j] > keys[j - 1]; j -= 1 {
			keys[j], keys[j - 1] = keys[j - 1], keys[j]
			n.rt.bag[j], n.rt.bag[j - 1] = n.rt.bag[j - 1], n.rt.bag[j]
		}
	}
}

// ----------------------------------------------------------------------------
// Move To: the actor's Navigation Agent, else straight at Speed.
// ----------------------------------------------------------------------------

@(private = "file")
bt_move_goal :: proc(t: ^BehaviorTreeNode, n: ^BT_Node) -> (goal: [2]f32, ok: bool) {
	if n.target != "" {
		if p := bt_resolve(t, n.target); p != nil do return p.globalPosition, true
		return
	}
	if n.key == "" do return
	bb := BehaviorTree_Blackboard(t)
	switch v in bb[n.key] or_else nil {
	case [2]f32: return v, true
	case string:
		if p := bt_resolve(t, v); p != nil do return p.globalPosition, true
	case bool, f64:
	}
	return
}

@(private = "file")
bt_move_to :: proc(t: ^BehaviorTreeNode, n: ^BT_Node, dt: f32) -> BT_Status {
	actor := bt_actor(t)
	goal, ok := bt_move_goal(t, n)
	if actor == nil || !ok do return .Failure
	arrive := max(n.number, 1)
	if agent := bt_find_child_of(t, actor, NavigationAgentNode); agent != nil {
		a := cast(^NavigationAgentNode)agent
		NavAgent_SetTarget(a, goal)
		d := goal - actor.globalPosition
		if math.sqrt(d.x * d.x + d.y * d.y) <= max(arrive, a.arriveDistance) || (a.finished && !a.hasTarget) do return .Success
		return .Running
	}
	d := goal - actor.globalPosition
	dist := math.sqrt(d.x * d.x + d.y * d.y)
	if dist <= arrive do return .Success
	step := min(n.number2 * dt, dist)
	actor.position += d / dist * step
	actor.globalPosition += d / dist * step
	return .Success if dist - step <= arrive else .Running
}

@(private = "file")
bt_move_stop :: proc(t: ^BehaviorTreeNode, n: ^BT_Node) {
	actor := bt_actor(t)
	if actor == nil do return
	if agent := bt_find_child_of(t, actor, NavigationAgentNode); agent != nil do NavAgent_Stop(cast(^NavigationAgentNode)agent)
}

// ----------------------------------------------------------------------------
// Wait For Signal: a watcher on Script_DispatchEvent (built-in and emitted
// signals both pass there).
// ----------------------------------------------------------------------------

BT_Watcher :: struct {
	tree:   ^BehaviorTreeNode,
	index:  int,
	source: ^Node,
	name:   string,
}

btWatchers: [dynamic]BT_Watcher

@(private = "file")
bt_watch :: proc(t: ^BehaviorTreeNode, i: int) {
	bt_unwatch(t, i)
	n := &t.nodes[i]
	src := bt_target(t, n)
	if src == nil || n.key == "" do return
	if btWatchers == nil do btWatchers = make([dynamic]BT_Watcher, Engine_HeapAllocator())
	append(&btWatchers, BT_Watcher{t, i, src, strings.clone(n.key, Engine_HeapAllocator())})
	n.rt.watching = true
}

@(private = "file")
bt_unwatch :: proc(t: ^BehaviorTreeNode, i: int) {
	if i < len(t.nodes) do t.nodes[i].rt.watching = false
	#reverse for w, k in btWatchers do if w.tree == t && w.index == i {
		delete(w.name, Engine_HeapAllocator())
		unordered_remove(&btWatchers, k)
	}
}

@(private = "file")
bt_unwatch_all :: proc(t: ^BehaviorTreeNode) {
	#reverse for w, k in btWatchers do if w.tree == t {
		delete(w.name, Engine_HeapAllocator())
		unordered_remove(&btWatchers, k)
	}
}

// BT_SignalSeen: called for every dispatched signal (script_events.odin).
BT_SignalSeen :: proc(owner: ^Node, name: string) {
	for w in btWatchers {
		if w.source != owner || w.name != name do continue
		if w.index < len(w.tree.nodes) do w.tree.nodes[w.index].rt.fired = true
	}
}

// ----------------------------------------------------------------------------
// Script leaves: a Lua class (`behavior = "action" / "condition"`), an
// instance per leaf: self.tree, self.actor, its properties;
// tick(self, actor, blackboard, dt) -> "success" / "failure" / "running"
// (true / false; nothing: success); before_run / after_run / interrupt.
// ----------------------------------------------------------------------------

@(private = "file")
bt_script_category :: proc(t: ^BehaviorTreeNode, n: ^BT_Node) -> BT_Category {
	mgr := bt_scripts(t)
	if mgr == nil || n.script == "" do return .Action
	if mod, ok := mgr.modules[ScriptVFS_NormalizePath(n.script)]; ok && mod != nil && mod.behavior == "condition" do return .Condition
	return .Action
}

// bt_script_instance: the leaf's Lua instance (made on first use, again
// when its script changes); pushes nothing. False: no script.
@(private = "file")
bt_script_instance :: proc(t: ^BehaviorTreeNode, i: int) -> bool {
	n := &t.nodes[i]
	mgr := bt_scripts(t)
	if mgr == nil || mgr.L == nil || n.script == "" do return false
	if n.rt.inst != 0 && n.rt.instPath == n.script do return true
	if n.rt.instBad && n.rt.instPath == n.script do return false
	if n.rt.inst != 0 do lua.L_unref(mgr.L, lua.REGISTRYINDEX, n.rt.inst)
	n.rt.inst = 0
	delete(n.rt.instPath, Engine_HeapAllocator())
	n.rt.instPath = strings.clone(n.script, Engine_HeapAllocator())
	mod, ok := ScriptManager_LoadModule(n.script, mgr)
	if !ok || mod == nil {
		n.rt.instBad = true
		Script_Problem(.Warning, "[BehaviorTree] %s: leaf script %s didn't load", t.name, n.script)
		return false
	}
	n.rt.instBad = false
	L := mgr.L
	lua.newtable(L)
	idx := lua.gettop(L)
	lua.newtable(L) // metatable {__index = the class}
	lua.getfield(L, lua.REGISTRYINDEX, strings.clone_to_cstring(strings.concatenate({"__Engine_Module_", mod.path}, context.temp_allocator), context.temp_allocator))
	lua.setfield(L, -2, "__index")
	lua.setmetatable(L, idx)
	{
		context.allocator = context.temp_allocator // (the values map is only for this)
		props := make(map[string]ScriptValue)
		script_apply_properties(L, idx, mod, n.props, &props)
	}
	push_node_userdata(L, t)
	lua.setfield(L, idx, "tree")
	if actor := bt_actor(t); actor != nil {
		push_node_userdata(L, actor)
		lua.setfield(L, idx, "actor")
	}
	n.rt.inst = i32(lua.L_ref(L, lua.REGISTRYINDEX))
	return true
}

// bt_script_call calls method(self, actor, blackboard, dt) on the leaf's
// instance; the answer (nret 1) is left for the caller to read at -1, or
// nothing. False: no such method (or an error).
@(private = "file")
bt_script_call :: proc(t: ^BehaviorTreeNode, i: int, method: string, nret: c.int, dt: f32 = 0) -> (called: bool, result: BT_Status) {
	if !bt_script_instance(t, i) do return false, .Failure
	mgr := bt_scripts(t)
	L := mgr.L
	top := lua.gettop(L)
	defer lua.settop(L, top)
	lua.pushcfunction(L, lua_traceback_error_handler)
	errHandler := lua.gettop(L)
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(t.nodes[i].rt.inst))
	lua.getfield(L, -1, strings.clone_to_cstring(method, context.temp_allocator))
	if lua.type(L, -1) != .FUNCTION do return false, .Success
	lua.pushvalue(L, -2) // self
	actor := bt_actor(t)
	if actor != nil do push_node_userdata(L, actor)
	else do lua.pushnil(L)
	BehaviorTree_PushBlackboard(L, t)
	lua.pushnumber(L, lua.Number(dt))
	if lua.pcall(L, 4, 1, errHandler) != 0 {
		Script_Problem(.Error, "[BehaviorTree] %s: error in %s:%s(): %s", t.name, t.nodes[i].script, method, lua.tostring(L, -1))
		return true, .Failure
	}
	return true, BT_StatusFromLua(L, -1)
}

// BT_StatusFromLua reads a leaf's answer: "success" / "failure" /
// "running" (any case), true / false, nil (success).
BT_StatusFromLua :: proc(L: ^lua.State, idx: c.int) -> BT_Status {
	#partial switch lua.type(L, idx) {
	case .NIL:     return .Success
	case .BOOLEAN: return .Success if lua.toboolean(L, idx) else .Failure
	case .STRING:
		switch strings.to_lower(string(lua.tostring(L, idx)), context.temp_allocator) {
		case "success", "succeeded", "ok": return .Success
		case "running":                    return .Running
		}
		return .Failure
	case .NUMBER:
		switch int(lua.tointeger(L, idx)) {
		case 0: return .Success
		case 2: return .Running
		}
		return .Failure
	}
	return .Failure
}

@(private = "file")
bt_script_tick :: proc(t: ^BehaviorTreeNode, i: int, dt: f32) -> BT_Status {
	called, s := bt_script_call(t, i, "tick", 1, dt)
	if !called do return .Failure if t.nodes[i].script == "" || t.nodes[i].rt.instBad else .Success
	return s
}

// bt_call_method: Call Method on a node's script; its answer.
@(private = "file")
bt_call_method :: proc(t: ^BehaviorTreeNode, target: ^Node, n: ^BT_Node) -> BT_Status {
	mgr := bt_scripts(t)
	if mgr == nil || target.scriptInstance == nil || n.key == "" do return .Failure
	inst := cast(^ScriptInstance)target.scriptInstance
	if !inst.isReady do return .Failure
	L := mgr.L
	top := lua.gettop(L)
	defer lua.settop(L, top)
	lua.pushcfunction(L, lua_traceback_error_handler)
	errHandler := lua.gettop(L)
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef))
	lua.getfield(L, -1, strings.clone_to_cstring(n.key, context.temp_allocator))
	if lua.type(L, -1) != .FUNCTION do return .Failure
	lua.pushvalue(L, -2)
	nargs: c.int = 1
	if n.value != "" {
		bt_push_bb_value(L, bt_value(t, n, n.value))
		nargs = 2
	}
	prev := mgr.currentInstance
	mgr.currentInstance = inst
	defer mgr.currentInstance = prev
	if lua.pcall(L, nargs, 1, errHandler) != 0 {
		Script_Problem(.Error, "[BehaviorTree] %s: error in %s(): %s", t.name, n.key, lua.tostring(L, -1))
		return .Failure
	}
	return BT_StatusFromLua(L, -1)
}

bt_push_bb_value :: proc(L: ^lua.State, v: BB_Value) {
	switch x in v {
	case bool:   lua.pushboolean(L, b32(x))
	case f64:    lua.pushnumber(L, lua.Number(x))
	case string: lua.pushstring(L, strings.clone_to_cstring(x, context.temp_allocator))
	case [2]f32: Lua_PushVec2(L, x)
	}
	if v == nil do lua.pushnil(L)
}

// ----------------------------------------------------------------------------
// The live view's status (the editor reads the nodes directly in Simulate;
// the game sends this to it in Play).
// ----------------------------------------------------------------------------

BehaviorTree_StatusJSON :: proc(t: ^BehaviorTreeNode, path: string, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make(allocator)
	strings.write_string(&sb, "{\"path\": ")
	strings.write_quoted_string(&sb, path)
	fmt.sbprintf(&sb, ", \"ticks\": %d, \"status\": %d, \"micros\": %.1f, \"running\": %d, \"nodes\": [", t.ticks, int(t.status), t.tickMicros, t.runningAction)
	for &n, i in t.nodes {
		if i > 0 do strings.write_string(&sb, ", ")
		// [status, ticks ago (0: this tick), node count check]
		ago := t.ticks - n.rt.tick if n.rt.tick > 0 else 1 << 30
		fmt.sbprintf(&sb, "[%d, %d]", int(n.rt.status), ago)
	}
	strings.write_string(&sb, "], \"blackboard\": {")
	bb := BehaviorTree_Blackboard(t)
	first := true
	for k, v in bb^ {
		if !first do strings.write_string(&sb, ", ")
		first = false
		strings.write_quoted_string(&sb, k)
		strings.write_string(&sb, ": ")
		strings.write_quoted_string(&sb, BB_Text(v))
	}
	strings.write_string(&sb, "}}")
	return strings.to_string(sb)
}
