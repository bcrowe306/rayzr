package engine

import "core:encoding/json"
import "core:fmt"
import "core:strconv"
import "core:strings"

// ============================================================================
// Behavior Tree (after bitbrain/beehave): a tree of composites, decorators
// and leaves, ticked every frame (or every Tick Rate frames, or by hand),
// each node answering Success, Failure or Running.
//
//   Composites run their children in order: Sequence (all must succeed),
//   Selector (the first that succeeds), their Reactive variants (start
//   from the first child every tick), Star (a failed Sequence retries the
//   child that failed), Random (a shuffled order, optionally weighted) and
//   Simple Parallel (a primary child and a secondary run alongside).
//   Decorators change one child's answer: Inverter, Always Succeed / Fail,
//   Until Fail, Repeater, Limiter, Time Limiter, Cooldown, Delayer.
//   Leaves do the work: built-ins (Wait, Move To, Play Animation, Set
//   Property, Call Method, signals, blackboard and State Machine leaves,
//   Subtree, Log) and Lua scripts (`MyLeaf.behavior = "action"` or
//   "condition", with tick(actor, blackboard, dt)).
//
// The tree lives inline in the node (saved with the scene). Its blackboard
// is its own unless Blackboard From points at another tree's; a global
// blackboard is shared by every tree (leaves' Global, Lua's global flag).
//
// The runtime follows Beehave: a child's before_run when it starts, its
// after_run when it finishes, interrupt down the running branch when a
// composite moves on or the tree is interrupted.
// ============================================================================

BT_Status :: enum u8 {
	None,    // not run (since the tree started)
	Success,
	Failure,
	Running,
}

BT_Kind :: enum u8 {
	// composites
	Sequence,
	Sequence_Star,
	Sequence_Reactive,
	Sequence_Random,
	Selector,
	Selector_Reactive,
	Selector_Random,
	Simple_Parallel,
	// decorators
	Inverter,
	Always_Succeed,
	Always_Fail,
	Until_Fail,
	Repeater,
	Limiter,
	Time_Limiter,
	Cooldown,
	Delayer,
	// leaves
	Script,
	Wait,
	Move_To,
	Play_Animation,
	Set_Property,
	Call_Method,
	Emit_Signal,
	Wait_Signal,
	Blackboard_Set,
	Blackboard_Erase,
	Blackboard_Has,
	Blackboard_Compare,
	State_Machine_Set,
	State_Machine_Trigger,
	State_Machine_In_State,
	Subtree,
	Log,
}

BT_Category :: enum u8 {
	Composite,
	Decorator,
	Action,
	Condition,
}

// BT_Field: the settings a kind uses (the editor shows only those).
BT_Field :: enum u8 {
	Number,  // seconds, repetitions, ticks...
	Number2, // a second number
	Flag,
	Flag2,
	Seed,
	Weights, // a Random composite: its children have weights
	Target,  // a node path
	Key,     // a blackboard key, property, method, signal, animation...
	Value,   // a value as text ("$key": a blackboard value)
	Op,
	Script,
	Global,  // the global blackboard
}

BT_Kind_Info :: struct {
	name:     string,
	category: BT_Category,
	fields:   bit_set[BT_Field],
	// labels of the fields that have one (the editor's rows)
	number, number2, flag, flag2, target, key, value: string,
	doc:      string,
}

BT_KINDS := [BT_Kind]BT_Kind_Info{
	.Sequence = {"Sequence", .Composite, {}, "", "", "", "", "", "", "", "Runs its children in order until one fails (Failure) or all succeed (Success). A Running child is resumed next tick; after a failure it starts again from the first."},
	.Sequence_Star = {"Sequence Star", .Composite, {}, "", "", "", "", "", "", "", "A Sequence that, after a failure, retries the child that failed instead of starting over."},
	.Sequence_Reactive = {"Sequence Reactive", .Composite, {}, "", "", "", "", "", "", "", "A Sequence that starts from the first child every tick, so earlier conditions are checked again while a later child runs (and interrupt it when they fail)."},
	.Sequence_Random = {"Sequence Random", .Composite, {.Flag, .Flag2, .Seed, .Weights}, "", "", "Resume on Failure", "Resume on Interrupt", "", "", "", "A Sequence in a shuffled order (a new order each run). Resume keeps the order after a failure or an interrupt."},
	.Selector = {"Selector", .Composite, {}, "", "", "", "", "", "", "", "Tries its children in order until one succeeds (Success) or all fail (Failure). Children that failed aren't tried again while a later one runs."},
	.Selector_Reactive = {"Selector Reactive", .Composite, {}, "", "", "", "", "", "", "", "A Selector that tries again from the first child every tick, so a higher-priority branch takes over (interrupting the running one) as soon as it can."},
	.Selector_Random = {"Selector Random", .Composite, {.Seed, .Weights}, "", "", "", "", "", "", "", "A Selector in a shuffled order (a new order each run): pick one of several ways at random."},
	.Simple_Parallel = {"Simple Parallel", .Composite, {.Number, .Flag}, "Secondary Repeats", "", "Delay Mode", "", "", "", "", "Runs its first child (the primary) and its second together; its answer is the primary's. Secondary Repeats: how often the second runs (0: until the primary ends). Delay Mode: wait for the second's current run to end."},
	.Inverter = {"Inverter", .Decorator, {}, "", "", "", "", "", "", "", "Success becomes Failure and Failure Success."},
	.Always_Succeed = {"Always Succeed", .Decorator, {}, "", "", "", "", "", "", "", "Success when its child ends (Running passes through)."},
	.Always_Fail = {"Always Fail", .Decorator, {}, "", "", "", "", "", "", "", "Failure when its child ends (Running passes through)."},
	.Until_Fail = {"Until Fail", .Decorator, {}, "", "", "", "", "", "", "", "Runs its child again and again (Running) until it fails, then succeeds."},
	.Repeater = {"Repeater", .Decorator, {.Number}, "Repetitions", "", "", "", "", "", "", "Runs its child this many times (one run a tick), then succeeds; a failure stops it."},
	.Limiter = {"Limiter", .Decorator, {.Number}, "Max Ticks", "", "", "", "", "", "", "Lets its child run for at most this many ticks, then interrupts it and fails."},
	.Time_Limiter = {"Time Limiter", .Decorator, {.Number}, "Seconds", "", "", "", "", "", "", "Lets its child run for at most this long, then interrupts it and fails."},
	.Cooldown = {"Cooldown", .Decorator, {.Number}, "Seconds", "", "", "", "", "", "", "After its child ends, fails without running it until this long has passed."},
	.Delayer = {"Delayer", .Decorator, {.Number}, "Seconds", "", "", "", "", "", "", "Waits this long (Running) before running its child."},
	.Script = {"Script", .Action, {.Script}, "", "", "", "", "", "", "", "A Lua leaf: tick(actor, blackboard, dt) returns \"success\", \"failure\" or \"running\" (or true / false)."},
	.Wait = {"Wait", .Action, {.Number, .Number2}, "Seconds", "Random Extra", "", "", "", "", "", "Running for this long (plus up to Random Extra), then Success."},
	.Move_To = {"Move To", .Action, {.Target, .Key, .Number, .Number2}, "Arrive Distance", "Speed", "", "", "Target Node", "Target Key", "", "Moves the actor to a node or to a blackboard position (Target Key). It uses the actor's Navigation Agent if it has one, else moves straight at Speed. Success on arrival."},
	.Play_Animation = {"Play Animation", .Action, {.Target, .Key, .Flag}, "", "", "Wait Until Done", "", "Player", "Animation", "", "Plays an animation on an Animation Player (empty: the actor's). With Wait Until Done it runs until the animation ends."},
	.Set_Property = {"Set Property", .Action, {.Target, .Key, .Value}, "", "", "", "", "Node", "Property", "Value", "Sets a property of a node (empty: the actor) - \"$key\" takes a blackboard value."},
	.Call_Method = {"Call Method", .Action, {.Target, .Key, .Value}, "", "", "", "", "Node", "Method", "Argument", "Calls a method of a node's script (empty: the actor). It answers with what the method returns (true / false, \"running\"...); nothing is Success."},
	.Emit_Signal = {"Emit Signal", .Action, {.Target, .Key, .Value}, "", "", "", "", "Node", "Signal", "Value", "Emits a signal from a node (empty: the actor), like node:emit."},
	.Wait_Signal = {"Wait For Signal", .Action, {.Target, .Key, .Number}, "Timeout", "", "", "", "Node", "Signal", "", "Running until the node (empty: the actor) emits the signal, then Success; Failure after Timeout seconds (0: no timeout)."},
	.Blackboard_Set = {"Blackboard Set", .Action, {.Key, .Value, .Global}, "", "", "", "", "", "Key", "Value", "Sets a blackboard value (\"$other\" copies another key)."},
	.Blackboard_Erase = {"Blackboard Erase", .Action, {.Key, .Global}, "", "", "", "", "", "Key", "", "Removes a blackboard value."},
	.Blackboard_Has = {"Blackboard Has", .Condition, {.Key, .Global}, "", "", "", "", "", "Key", "", "Success when the blackboard has the key."},
	.Blackboard_Compare = {"Blackboard Compare", .Condition, {.Key, .Op, .Value, .Global}, "", "", "", "", "", "Key", "Value", "Compares a blackboard value with a value (\"$other\": another key): ==, !=, >, <, >=, <=."},
	.State_Machine_Set = {"State Machine Set", .Action, {.Target, .Key, .Value}, "", "", "", "", "State Machine", "Parameter", "Value", "Sets a State Machine's parameter (empty: the actor's State Machine)."},
	.State_Machine_Trigger = {"State Machine Trigger", .Action, {.Target, .Key}, "", "", "", "", "State Machine", "Trigger", "", "Fires a State Machine's trigger."},
	.State_Machine_In_State = {"State Machine In State", .Condition, {.Target, .Key}, "", "", "", "", "State Machine", "State", "", "Success when the State Machine is in this state."},
	.Subtree = {"Subtree", .Action, {.Target}, "", "", "", "", "Behavior Tree", "", "", "Runs another Behavior Tree node's tree (set it to Manual) with its own blackboard; its answer is the subtree's."},
	.Log = {"Log", .Action, {.Value}, "", "", "", "", "", "", "Message", "Writes a message to the log (\"$key\": a blackboard value), then Success."},
}

BT_Compare :: enum u8 {
	Equal,
	Not_Equal,
	Greater,
	Less,
	Greater_Equal,
	Less_Equal,
}

BT_COMPARE_TEXT := [BT_Compare]string{.Equal = "==", .Not_Equal = "!=", .Greater = ">", .Less = "<", .Greater_Equal = ">=", .Less_Equal = "<="}

// BT_Runtime: a node's state while the tree runs (reset by Interrupt).
BT_Runtime :: struct {
	status:        BT_Status, // its last answer (None: hasn't run)
	tick:          u64,       // the tree tick it last ran on (the live view)
	running:       int,       // a composite / decorator's running child (node index, -1: none)
	index:         int,       // Sequence: children done; Selector: children failed
	count:         int,
	timer:         f32,
	duration:      f32,
	until:         f64,       // Cooldown: the tree time it may run again
	bag:           [dynamic]int,
	rng:           u64,
	primaryDone:   bool,      // Simple Parallel
	primaryStatus: BT_Status,
	repeatLeft:    int,
	inst:          i32,       // a Script leaf's Lua instance (registry ref; 0: none)
	instPath:      string,
	instBad:       bool,      // the script failed to load (warned once)
	fired:         bool,      // Wait For Signal
	watching:      bool,
	animStarted:   bool,
}

BT_Node :: struct {
	kind:     BT_Kind,
	name:     string,       // the name shown ("": the kind's)
	parent:   int,          // -1: the root
	children: [dynamic]int,
	number:   f32,
	number2:  f32,
	flag:     bool,
	flag2:    bool,
	seed:     int,
	weights:  bool,
	weight:   f32,          // under a weighted Random composite (1-100)
	target:   string,
	key:      string,
	value:    string,
	op:       BT_Compare,
	script:   string,
	global:   bool,
	props:    map[string]ScriptValue, // a Script leaf's property values
	rt:       BT_Runtime,
}

// BB_Value: a blackboard value (nil: none).
BB_Value :: union {
	bool,
	f64,
	string,
	[2]f32,
}

BT_BB_Entry :: struct {
	key, value: string, // the starting values (value as text)
}

BT_Process :: enum u8 {
	Every_Frame, // ticks in the node's update (every Tick Rate frames)
	Manual,      // only bt_tick() (a script) or a Subtree leaf
}

// btGlobal: the global blackboard (every tree's Global leaves, Lua's global flag).
btGlobal: map[string]BB_Value

BT_NodeName :: proc(n: ^BT_Node) -> string {
	return n.name if n.name != "" else BT_KINDS[n.kind].name
}

BT_IsComposite :: proc(k: BT_Kind) -> bool {return BT_KINDS[k].category == .Composite}
BT_IsDecorator :: proc(k: BT_Kind) -> bool {return BT_KINDS[k].category == .Decorator}
BT_IsLeaf :: proc(k: BT_Kind) -> bool {return !BT_IsComposite(k) && !BT_IsDecorator(k)}

// BT_MaxChildren: how many children a kind takes (-1: any).
BT_MaxChildren :: proc(k: BT_Kind) -> int {
	if k == .Simple_Parallel do return 2
	if BT_IsComposite(k) do return -1
	if BT_IsDecorator(k) do return 1
	return 0
}

// BT_KindDefaults: a new node's settings.
@(private = "file")
bt_kind_defaults :: proc(n: ^BT_Node) {
	n.weight = 1
	#partial switch n.kind {
	case .Repeater:     n.number = 3
	case .Limiter:      n.number = 10
	case .Time_Limiter, .Cooldown, .Delayer, .Wait: n.number = 1
	case .Move_To:      n.number, n.number2 = 8, 120
	case .Play_Animation: n.flag = true
	}
}

// ----------------------------------------------------------------------------
// Editing: nodes[0] is the root; every other node is under it.
// ----------------------------------------------------------------------------

// BT_AddNode adds a node under `parent` (-1: as the root, when there is
// none) at position `at` among its children (-1: last); its index.
BT_AddNode :: proc(t: ^BehaviorTreeNode, parent: int, kind: BT_Kind, at := -1) -> int {
	if parent < 0 && len(t.nodes) > 0 do return -1
	if parent >= len(t.nodes) do return -1
	if parent >= 0 {
		max := BT_MaxChildren(t.nodes[parent].kind)
		if max >= 0 && len(t.nodes[parent].children) >= max do return -1
	}
	n := BT_Node{kind = kind, parent = parent}
	n.children = make([dynamic]int, t.allocator)
	n.rt.running = -1
	bt_kind_defaults(&n)
	append(&t.nodes, n)
	i := len(t.nodes) - 1
	if parent >= 0 {
		ch := &t.nodes[parent].children
		if at < 0 || at >= len(ch) do append(ch, i)
		else do inject_at(ch, at, i)
	}
	return i
}

// BT_RemoveNode removes a node and everything under it (indices change).
BT_RemoveNode :: proc(t: ^BehaviorTreeNode, i: int) {
	if i < 0 || i >= len(t.nodes) do return
	BehaviorTree_Interrupt(t)
	gone := make([]bool, len(t.nodes), context.temp_allocator)
	mark :: proc(t: ^BehaviorTreeNode, i: int, gone: []bool) {
		gone[i] = true
		for c in t.nodes[i].children do mark(t, c, gone)
	}
	mark(t, i, gone)
	if p := t.nodes[i].parent; p >= 0 {
		ch := &t.nodes[p].children
		for c, k in ch do if c == i {ordered_remove(ch, k); break}
	}
	remap := make([]int, len(t.nodes), context.temp_allocator)
	kept := 0
	for g, k in gone {
		remap[k] = -1 if g else kept
		if !g do kept += 1
	}
	out := make([dynamic]BT_Node, t.allocator)
	for &n, k in t.nodes {
		if gone[k] {
			bt_node_free(t, &n)
			continue
		}
		if n.parent >= 0 do n.parent = remap[n.parent]
		for &c in n.children do c = remap[c]
		append(&out, n)
	}
	delete(t.nodes)
	t.nodes = out
}

// BT_MoveNode moves a node (and its subtree) under `parent` at `at`.
// False when that would put it inside itself or over a parent's limit.
BT_MoveNode :: proc(t: ^BehaviorTreeNode, i, parent: int, at := -1) -> bool {
	if i <= 0 || i >= len(t.nodes) || parent < 0 || parent >= len(t.nodes) do return false
	for p := parent; p >= 0; p = t.nodes[p].parent do if p == i do return false
	old := t.nodes[i].parent
	max := BT_MaxChildren(t.nodes[parent].kind)
	if parent != old && max >= 0 && len(t.nodes[parent].children) >= max do return false
	BehaviorTree_Interrupt(t)
	pos := at
	if old >= 0 {
		ch := &t.nodes[old].children
		for c, k in ch do if c == i {
			ordered_remove(ch, k)
			if old == parent && at > k do pos -= 1
			break
		}
	}
	ch := &t.nodes[parent].children
	if pos < 0 || pos >= len(ch) do append(ch, i)
	else do inject_at(ch, pos, i)
	t.nodes[i].parent = parent
	return true
}

// BT_WrapNode puts a new composite / decorator in node i's place with i as
// its child (wrapping the root makes the new node the root); its index.
BT_WrapNode :: proc(t: ^BehaviorTreeNode, i: int, kind: BT_Kind) -> int {
	if i < 0 || i >= len(t.nodes) || BT_IsLeaf(kind) do return -1
	BehaviorTree_Interrupt(t)
	n := BT_Node{kind = kind, parent = t.nodes[i].parent}
	n.children = make([dynamic]int, t.allocator)
	n.rt.running = -1
	bt_kind_defaults(&n)
	append(&t.nodes, n)
	w := len(t.nodes) - 1
	if p := t.nodes[i].parent; p >= 0 {
		for &c in t.nodes[p].children do if c == i do c = w
	}
	append(&t.nodes[w].children, i)
	t.nodes[i].parent = w
	if i == 0 {
		bt_swap(t, 0, w)
		return 0
	}
	return w
}

// bt_swap exchanges two nodes' places in the array (references follow).
@(private = "file")
bt_swap :: proc(t: ^BehaviorTreeNode, a, b: int) {
	t.nodes[a], t.nodes[b] = t.nodes[b], t.nodes[a]
	fix :: proc(x: ^int, a, b: int) {
		if x^ == a do x^ = b
		else if x^ == b do x^ = a
	}
	for &n in t.nodes {
		fix(&n.parent, a, b)
		for &c in n.children do fix(&c, a, b)
	}
}

// BT_SetKind changes a node's kind (children beyond the new kind's limit
// are removed; settings are kept where they mean something).
BT_SetKind :: proc(t: ^BehaviorTreeNode, i: int, kind: BT_Kind) {
	if i < 0 || i >= len(t.nodes) do return
	BehaviorTree_Interrupt(t)
	t.nodes[i].kind = kind
	max := BT_MaxChildren(kind)
	for max >= 0 && len(t.nodes[i].children) > max {
		BT_RemoveNode(t, t.nodes[i].children[len(t.nodes[i].children) - 1])
	}
}

// BT_SetString sets one of a node's text settings (cloned).
BT_SetString :: proc(t: ^BehaviorTreeNode, s: ^string, value: string) {
	if s^ == value do return
	delete(s^, t.allocator)
	s^ = strings.clone(value, t.allocator)
}

@(private = "file")
bt_node_free :: proc(t: ^BehaviorTreeNode, n: ^BT_Node) {
	bt_runtime_free(t, n)
	delete(n.children)
	delete(n.name, t.allocator)
	delete(n.target, t.allocator)
	delete(n.key, t.allocator)
	delete(n.value, t.allocator)
	delete(n.script, t.allocator)
	for k, v in n.props {
		delete(k, t.allocator)
		if v.valString != "" do delete(v.valString, t.allocator)
	}
	delete(n.props)
}

BT_ClearNodes :: proc(t: ^BehaviorTreeNode) {
	for &n in t.nodes do bt_node_free(t, &n)
	clear(&t.nodes)
}

// ----------------------------------------------------------------------------
// Blackboard values as text: true / false, numbers, "x, y", anything else a
// string ("quoted" keeps a string that looks like a number).
// ----------------------------------------------------------------------------

BB_Parse :: proc(text: string) -> BB_Value {
	s := strings.trim_space(text)
	if s == "" do return string("")
	if s == "true" do return true
	if s == "false" do return false
	if len(s) >= 2 && s[0] == '"' && s[len(s) - 1] == '"' do return s[1:len(s) - 1]
	if f, ok := strconv.parse_f64(s); ok do return f
	inner := strings.trim(s, "()[]{} ")
	if parts := strings.split(inner, ",", context.temp_allocator); len(parts) == 2 {
		x, okx := strconv.parse_f32(strings.trim_space(parts[0]))
		y, oky := strconv.parse_f32(strings.trim_space(parts[1]))
		if okx && oky do return [2]f32{x, y}
	}
	return s
}

BB_Text :: proc(v: BB_Value, allocator := context.temp_allocator) -> string {
	switch x in v {
	case bool:   return "true" if x else "false"
	case f64:    return fmt.aprintf("%v", x, allocator = allocator)
	case string: return strings.clone(x, allocator)
	case [2]f32: return fmt.aprintf("%v, %v", x.x, x.y, allocator = allocator)
	}
	return ""
}

// BB_Compare: a op b (numbers by value; vectors and strings == / != only,
// strings also by order).
BB_Compare :: proc(a, b: BB_Value, op: BT_Compare) -> bool {
	if fa, ok := a.(f64); ok {
		fb: f64
		#partial switch y in b {
		case f64:  fb = y
		case bool: fb = 1 if y else 0
		case:      return op == .Not_Equal
		}
		switch op {
		case .Equal:         return fa == fb
		case .Not_Equal:     return fa != fb
		case .Greater:       return fa > fb
		case .Less:          return fa < fb
		case .Greater_Equal: return fa >= fb
		case .Less_Equal:    return fa <= fb
		}
	}
	if sa, ok := a.(string); ok {
		sb, okb := b.(string)
		if !okb do sb = BB_Text(b)
		switch op {
		case .Equal:         return sa == sb
		case .Not_Equal:     return sa != sb
		case .Greater:       return sa > sb
		case .Less:          return sa < sb
		case .Greater_Equal: return sa >= sb
		case .Less_Equal:    return sa <= sb
		}
	}
	same := false
	switch x in a {
	case bool:   y, ok := b.(bool); same = ok && x == y
	case [2]f32: y, ok := b.([2]f32); same = ok && x == y
	case f64, string:
	}
	if a == nil do same = b == nil
	#partial switch op {
	case .Equal:     return same
	case .Not_Equal: return !same
	}
	return false
}

// BB_Set stores a value (strings cloned onto the engine heap).
BB_Set :: proc(bb: ^map[string]BB_Value, key: string, v: BB_Value) {
	if key == "" do return
	if bb^ == nil do bb^ = make(map[string]BB_Value, Engine_HeapAllocator())
	val := v
	if s, ok := v.(string); ok do val = strings.clone(s, Engine_HeapAllocator())
	if k, old, found := map_entry(bb^, key); found {
		if s, ok := old.(string); ok do delete(s, Engine_HeapAllocator())
		bb^[k] = val
		return
	}
	bb^[strings.clone(key, Engine_HeapAllocator())] = val
}

BB_Erase :: proc(bb: ^map[string]BB_Value, key: string) {
	if k, old, found := map_entry(bb^, key); found {
		delete_key(bb, k)
		if s, ok := old.(string); ok do delete(s, Engine_HeapAllocator())
		delete(k, Engine_HeapAllocator())
	}
}

BB_Clear :: proc(bb: ^map[string]BB_Value) {
	for k, v in bb^ {
		if s, ok := v.(string); ok do delete(s, Engine_HeapAllocator())
		delete(k, Engine_HeapAllocator())
	}
	delete(bb^)
	bb^ = nil
}

@(private = "file")
map_entry :: proc(m: map[string]BB_Value, key: string) -> (string, BB_Value, bool) {
	for k, v in m do if k == key do return k, v, true
	return "", nil, false
}

// ----------------------------------------------------------------------------
// Saved with the scene: "behavior_tree": {"root": {"kind", ...settings,
// "children": [...]}, "blackboard": [{"key", "value"}]}.
// ----------------------------------------------------------------------------

BehaviorTree_WriteJSON :: proc(w: ^Json_Writer, t: ^BehaviorTreeNode, first: ^bool) {
	Json_Key(w, "behavior_tree", first)
	strings.write_string(&w.sb, "{\"root\": ")
	if len(t.nodes) == 0 do strings.write_string(&w.sb, "null")
	else do bt_write_node(w, t, 0)
	strings.write_string(&w.sb, ", \"blackboard\": [")
	for e, i in t.bbInit {
		if i > 0 do strings.write_string(&w.sb, ", ")
		strings.write_string(&w.sb, "{\"key\": ")
		Json_String(w, e.key)
		strings.write_string(&w.sb, ", \"value\": ")
		Json_String(w, e.value)
		strings.write_byte(&w.sb, '}')
	}
	strings.write_string(&w.sb, "]}")
}

@(private = "file")
bt_write_node :: proc(w: ^Json_Writer, t: ^BehaviorTreeNode, i: int) {
	n := &t.nodes[i]
	fmt.sbprintf(&w.sb, "{{\"kind\": \"%v\"", n.kind)
	str :: proc(w: ^Json_Writer, key, v: string) {
		if v == "" do return
		fmt.sbprintf(&w.sb, ", \"%s\": ", key)
		Json_String(w, v)
	}
	num :: proc(w: ^Json_Writer, key: string, v: f32) {
		if v == 0 do return
		fmt.sbprintf(&w.sb, ", \"%s\": ", key)
		Json_Float(w, v)
	}
	str(w, "name", n.name)
	num(w, "number", n.number)
	num(w, "number2", n.number2)
	if n.flag do strings.write_string(&w.sb, ", \"flag\": true")
	if n.flag2 do strings.write_string(&w.sb, ", \"flag2\": true")
	if n.seed != 0 do fmt.sbprintf(&w.sb, ", \"seed\": %d", n.seed)
	if n.weights do strings.write_string(&w.sb, ", \"weights\": true")
	if n.weight != 1 do num(w, "weight", n.weight)
	str(w, "target", n.target)
	str(w, "key", n.key)
	str(w, "value", n.value)
	if n.op != .Equal do fmt.sbprintf(&w.sb, ", \"op\": \"%s\"", BT_COMPARE_TEXT[n.op])
	str(w, "script", n.script)
	if n.global do strings.write_string(&w.sb, ", \"global\": true")
	if len(n.props) > 0 {
		strings.write_string(&w.sb, ", \"properties\": {")
		keys := make([dynamic]string, context.temp_allocator)
		for k in n.props do append(&keys, k)
		sort_strings(keys[:])
		for k, j in keys {
			if j > 0 do strings.write_string(&w.sb, ", ")
			Json_String(w, k)
			strings.write_string(&w.sb, ": ")
			Json_WriteValue(w, bt_script_value_json(n.props[k]))
		}
		strings.write_byte(&w.sb, '}')
	}
	if len(n.children) > 0 {
		strings.write_string(&w.sb, ", \"children\": [")
		for c, j in n.children {
			if j > 0 do strings.write_string(&w.sb, ", ")
			bt_write_node(w, t, c)
		}
		strings.write_byte(&w.sb, ']')
	}
	strings.write_byte(&w.sb, '}')
}

BehaviorTree_ReadJSON :: proc(t: ^BehaviorTreeNode, obj: json.Object) {
	BT_ClearNodes(t)
	for e in t.bbInit {
		delete(e.key, t.allocator)
		delete(e.value, t.allocator)
	}
	clear(&t.bbInit)
	if root, ok := obj["root"].(json.Object); ok do bt_read_node(t, root, -1)
	if list, ok := obj["blackboard"].(json.Array); ok {
		for v in list {
			eo, eok := v.(json.Object)
			if !eok do continue
			k, _ := eo["key"].(json.String)
			val, _ := eo["value"].(json.String)
			append(&t.bbInit, BT_BB_Entry{strings.clone(k, t.allocator), strings.clone(val, t.allocator)})
		}
	}
}

@(private = "file")
bt_read_node :: proc(t: ^BehaviorTreeNode, o: json.Object, parent: int) {
	kindText, _ := o["kind"].(json.String)
	kind := BT_Kind.Sequence
	for k in BT_Kind do if fmt.tprintf("%v", k) == kindText do kind = k
	// (children past a kind's limit: still read, so nothing is lost silently)
	n := BT_Node{kind = kind, parent = parent, weight = 1}
	n.children = make([dynamic]int, t.allocator)
	n.rt.running = -1
	str :: proc(t: ^BehaviorTreeNode, o: json.Object, key: string) -> string {
		s, _ := o[key].(json.String)
		return strings.clone(s, t.allocator) if s != "" else ""
	}
	num :: proc(o: json.Object, key: string) -> f32 {
		v, _ := json_number(o[key])
		return v
	}
	n.name = str(t, o, "name")
	n.number = num(o, "number")
	n.number2 = num(o, "number2")
	n.flag = o["flag"].(json.Boolean) or_else false
	n.flag2 = o["flag2"].(json.Boolean) or_else false
	n.seed = int(num(o, "seed"))
	n.weights = o["weights"].(json.Boolean) or_else false
	if w, ok := json_number(o["weight"]); ok do n.weight = w
	n.target = str(t, o, "target")
	n.key = str(t, o, "key")
	n.value = str(t, o, "value")
	if opText, ok := o["op"].(json.String); ok {
		for op in BT_Compare do if BT_COMPARE_TEXT[op] == opText do n.op = op
	}
	n.script = str(t, o, "script")
	n.global = o["global"].(json.Boolean) or_else false
	if props, ok := o["properties"].(json.Object); ok {
		n.props = make(map[string]ScriptValue, t.allocator)
		for k, v in parse_script_overrides(props) {
			sv := v
			if sv.valString != "" do sv.valString = strings.clone(sv.valString, t.allocator)
			n.props[strings.clone(k, t.allocator)] = sv
		}
	}
	append(&t.nodes, n)
	i := len(t.nodes) - 1
	if parent >= 0 do append(&t.nodes[parent].children, i)
	if list, ok := o["children"].(json.Array); ok {
		for c in list do if co, cok := c.(json.Object); cok do bt_read_node(t, co, i)
	}
}

@(private = "file")
bt_script_value_json :: proc(v: ScriptValue) -> json.Value {
	switch v.type {
	case .Float:   return json.Float(v.valFloat)
	case .Int:     return json.Integer(v.valInt)
	case .Boolean: return json.Boolean(v.valBool)
	case .Vector2:
		arr := make(json.Array, 2, context.temp_allocator)
		arr[0], arr[1] = json.Float(v.valVec2.x), json.Float(v.valVec2.y)
		return arr
	case .Color:
		arr := make(json.Array, 4, context.temp_allocator)
		for c, i in v.valColor do arr[i] = json.Float(c)
		return arr
	case .String:
	}
	return json.String(v.valString)
}

@(private = "file")
sort_strings :: proc(s: []string) {
	for i in 1 ..< len(s) {
		for j := i; j > 0 && s[j] < s[j - 1]; j -= 1 do s[j], s[j - 1] = s[j - 1], s[j]
	}
}
