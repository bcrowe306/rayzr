package engine

import "base:runtime"
import "core:encoding/uuid"
import "core:log"

// ============================================================================
// Events
//
// An EventSubject is a named event owned by a node ("timeout" on a TimerNode,
// "body_entered" on an AreaNode, ...). Odin code subscribes callbacks; Lua
// scripts receive the same events (see script_events.odin):
//   * a method on the owner's script named `on_<event>` (e.g. on_timeout), and
//   * functions connected from any script with node:connect("<event>", fn).
// Notify is re-entrancy safe: listeners may subscribe/unsubscribe, emit other
// events or destroy nodes while being notified.
// ============================================================================

ListenerId :: uuid.Identifier

EventValue :: union {
	int,
	f32,
	f64,
	bool,
	u32,
	u64,
	string,
	^Node, // the other node of a collision / overlap / child event
	Lua_Value_Ref, // a Lua table or function (node:emit; the registry ref lives while it's delivered)
}

// Lua_Value_Ref: a Lua value held in the registry (script_events.odin).
Lua_Value_Ref :: distinct i32

EventSubscription :: struct {
	id: uuid.Identifier,
	userData: rawptr,
	callback: proc(source: rawptr, value: EventValue, gameContext: ^GameContext, user_data: rawptr)
}

EventSubject :: struct {
	name: string, // Lua-facing event name, e.g. "timeout"
	owner: ^Node, // node the event belongs to (nil for non-node subjects)
	listeners: [dynamic]EventSubscription,
	subscribe: proc(subject: ^EventSubject, callback: proc(source: rawptr, value: EventValue,  gameContext: ^GameContext, user_data: rawptr), user_data: rawptr ) -> ListenerId,
	unsubscribe: proc(subject: ^EventSubject, id: ListenerId),
	notify: proc(subject: ^EventSubject, source: rawptr, value: EventValue, gameContext: ^GameContext),
}

InitializeSubject :: proc(subject: ^EventSubject, name: string = "", owner: ^Node = nil) {
	subject.notify = Notify
	subject.subscribe = Subscribe
	subject.unsubscribe = UnSubscribe
	subject.name = name
	subject.owner = owner
}

DestroySubject :: proc(subject: ^EventSubject) {
	if subject == nil do return
	delete(subject.listeners)
	subject.listeners = nil
}

@(private = "file")
nextListenerId: u64

Subscribe :: proc(subject: ^EventSubject, callback: proc(source: rawptr, value: EventValue,  gameContext: ^GameContext, user_data: rawptr), user_data: rawptr ) -> ListenerId {
	// A counter is enough to identify a subscription (the crypto RNG UUID
	// cost a syscall per subscribe).
	nextListenerId += 1
	id: ListenerId
	(^u64)(&id[0])^ = nextListenerId
	_, err := append(&subject.listeners, EventSubscription{id = id, userData = user_data, callback = callback})
	if err != nil {
		log.error(err)
	}
	return id
}

Notify :: proc(subject: ^EventSubject, source: rawptr, value: EventValue, gameContext: ^GameContext) {
	if subject == nil do return
	if len(subject.listeners) > 0 {
		// Iterate a copy: callbacks may (un)subscribe while we notify.
		snapshot := make([]EventSubscription, len(subject.listeners), context.temp_allocator)
		copy(snapshot, subject.listeners[:])
		for listener in snapshot {
			if listener.callback != nil {
				listener.callback(source, value, gameContext, listener.userData)
			}
		}
	}
	if subject.owner != nil && subject.name != "" {
		Script_DispatchEvent(subject.owner, subject.name, value, gameContext)
	}
}

UnSubscribe :: proc(subject: ^EventSubject, id: ListenerId) {
	for listener, i in subject.listeners {
		if listener.id == id {
			ordered_remove(&subject.listeners, i) // keep notification order
			return
		}
	}
	log.debugf("Cannot unsubscribe: listener %v not found", id)
}

// ============================================================================
// Live node registry: Lua holds node references by id; looking the id up
// here (instead of dereferencing a pointer that may have been freed) turns a
// destroyed node into nil.
// ============================================================================

@(private = "file")
liveNodes: map[uuid.Identifier]^Node
@(private = "file")
livePtrs: map[^Node]bool

// The live-node table: every registered node has a slot; a Lua reference
// keeps (slot, generation) to find its node with an array read instead of
// hashing the id (Node_FromSlot). A slot's generation changes when its node
// goes, so stale references miss. Kept for the process (generations must
// not restart).
Node_Live_Slot :: struct {
	node: ^Node,
	gen:  u32,
}
@(private = "file")
liveSlots: [dynamic]Node_Live_Slot
@(private = "file")
freeSlots: [dynamic]u32

Node_Register :: proc(node: ^Node) {
	if liveNodes == nil {
		// Process-lifetime registry: not owned by whatever allocator the
		// caller happens to use.
		liveNodes = make(map[uuid.Identifier]^Node, allocator = Engine_HeapAllocator())
		livePtrs = make(map[^Node]bool, allocator = Engine_HeapAllocator())
	}
	liveNodes[node.id] = node
	livePtrs[node] = true
	if node.liveSlot == 0 {
		if liveSlots == nil {
			liveSlots = make([dynamic]Node_Live_Slot, Engine_HeapAllocator())
			freeSlots = make([dynamic]u32, Engine_HeapAllocator())
		}
		i: u32
		if len(freeSlots) > 0 {
			i = pop(&freeSlots)
		} else {
			i = u32(len(liveSlots))
			append(&liveSlots, Node_Live_Slot{})
		}
		liveSlots[i].node = node
		node.liveSlot = i + 1
	}
}

Node_Unregister :: proc(node: ^Node) {
	if liveNodes == nil do return
	if p, ok := liveNodes[node.id]; ok && p == node {
		delete_key(&liveNodes, node.id)
	}
	delete_key(&livePtrs, node)
	if node.liveSlot > 0 {
		i := node.liveSlot - 1
		if int(i) < len(liveSlots) && liveSlots[i].node == node {
			liveSlots[i].node = nil
			liveSlots[i].gen += 1
			append(&freeSlots, i)
		}
		node.liveSlot = 0
	}
	if len(liveNodes) == 0 && len(livePtrs) == 0 {
		delete(liveNodes)
		delete(livePtrs)
		liveNodes = nil
		livePtrs = nil
	}
}

// Node_FromId returns the live node with that id (nil once destroyed).
Node_FromId :: proc(id: uuid.Identifier) -> ^Node {
	if liveNodes == nil do return nil
	return liveNodes[id]
}

// Node_SlotOf: a live node's (slot, generation) for Node_FromSlot.
Node_SlotOf :: proc "contextless" (node: ^Node) -> (slot, gen: u32) {
	if node == nil || node.liveSlot == 0 || int(node.liveSlot - 1) >= len(liveSlots) do return 0, 0
	return node.liveSlot, liveSlots[node.liveSlot - 1].gen
}

// Node_FromSlot: the live node in `slot` if its generation is still `gen`.
Node_FromSlot :: #force_inline proc "contextless" (slot, gen: u32) -> ^Node {
	if slot == 0 || int(slot - 1) >= len(liveSlots) do return nil
	s := liveSlots[slot - 1]
	return s.node if s.gen == gen else nil
}

// Node_IsAlive reports whether a pointer still refers to a live node.
Node_IsAlive :: proc(node: ^Node) -> bool {
	if node == nil || livePtrs == nil do return false
	return livePtrs[node]
}
