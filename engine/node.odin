package engine

import "core:math/rand"

import "base:runtime"

import "core:log"
import "core:mem"
import "core:crypto"
import "core:encoding/uuid"
import vmem "core:mem/virtual"

// Field order: what the per-frame walks (update, transforms, Y-sort,
// render, Lua calls) read comes first, packed (the bools and small enums
// together), so a walk touches the node's first cache lines; the rest
// (identity, memory, prefab and editor data) after. The Inspector lists the
// gui:"true" fields in this order.
Node :: struct {
	// --- Read every frame -------------------------------------------------
	// The hierarchy (node_manager.odin: AddChild / GetChildrenView / GetParent).
	parent: ^Node,
	children: Node_Children,
	update: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32),
	render: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32),
	scriptInstance: rawptr, // Pointer to ScriptInstance attached to this node
	gameContext: ^GameContext, // Node does not own this
	position: [2]f32 `gui:"true" min:"0" max:"1280"`,
	scale: [2]f32 `gui:"true" min:"0.01" max:"10"`,
	rotation: f32 `gui:"true" min:"0" max:"360"`,
	globalRotation: f32,
	globalPosition: [2]f32,
	globalScale: [2]f32,
	// The origin (node_origin.odin): where in what the node draws its
	// position is - and what it rotates and scales around - as a fraction
	// of the drawn size ({0.5, 0.5} = the centre, {0, 0} the top-left).
	pivot: [2]f32,
	// Draw order within a layer (scene.odin): zIndex adds to the parent's
	// (higher draws later); a ySort node draws its children ordered by
	// their Y (+ their ySortOffset, the "feet" line), each child with its
	// subtree - top-down and isometric depth.
	zIndex: i32,
	ySortOffset: f32,
	liveSlot: u32,    // its slot in the live-node table (+1; 0 = not registered; events.odin)
	layer: RenderLayer,
	// Pixel art (pixel_perfect.odin, #409): this node's Texture Filter, Snap
	// to Pixels, and (text / UI) where it draws when the frame is scaled up.
	pixelFilter: Pixel_Filter,
	pixelSnap:   Pixel_Snap,
	pixelText:   Pixel_Text,
	renderable: bool `gui:"true"`,
	enabled: bool `gui:"true"`,
	ySort: bool,
	isReady: bool,
	isUI: bool,
	inTree: bool, // queued for (or in) a scene's node list (SceneAddNode)
	// Pausing (scene_flow.odin): `paused` pauses this subtree; pauseMode
	// decides whether the node stops when its parent / the game pauses.
	pauseMode: Pause_Mode,
	paused: bool,
	pausedNow: bool,  // paused this frame (set by the update pass)
	bodyPaused: bool, // its physics body was disabled by a pause
	removing: bool, // queued for removal (RemoveNode)
	poolSpawn: bool,  // taken from its pool: on_spawn before its next update
	// Runtime-only node (built by another node, e.g. LDtk colliders and
	// spawned entities): never saved with the scene.
	transient: bool,
	// Editor-only (saved with the scene, ignored by the game): a locked node
	// and its children can't be picked or moved in the viewport; a hidden
	// one isn't drawn there (Render_HideEditorHidden).
	editorLocked: bool,
	editorHidden: bool,
	// Shader / blend mode / shader parameters applied around render (nil =
	// plain drawing; material.odin).
	material: ^Material,
	typeId: typeid, // Concrete runtime type of the node (e.g. Node, TextureNode, DynamicBodyNode)
	id: uuid.Identifier,
	// The tree events every node raises (Node_Event), with their listeners -
	// allocated when something subscribes (most nodes never have one):
	// Node_Subject / Node_NotifyEvent.
	events: ^Node_Events,
	drawBounds: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32),

	// --- The rest ----------------------------------------------------------
	ready: proc(node: ^Node, gameContext: ^GameContext),
	onDestroy: proc(node: ^Node, gameContext: ^GameContext),
	managerIndex: int, // slot in the manager's node list (+1; 0 = not in it)
	pool: ^Node_Pool, // the pool it came from (node_pool.odin): removing returns it there
	name: string, // Name of the node
	resource: rawptr, // Pointer to the resource associated with this node. Used to give data to the node. Resoruce is stored on node's arena, and dealloc'd when node terminates.
	allocator: mem.Allocator,
	arena: vmem.Arena,
	// Linked prefab instance: project-relative component file this node was
	// instantiated from ("" = not an instance). Its subtree comes from that
	// file; the scene stores only the instance's name and transform.
	componentPath: string,
	// Stable id in the component file (or component document) the node was
	// loaded from: 8 base-36 characters, unique in that file; "" for plain
	// scene nodes. Instance overrides refer to nodes by uid paths
	// (component_overrides.odin).
	uid: string,
	// The (normalized) component JSON the instance was built from; overrides
	// are what differs from it (component_overrides.odin).
	componentBase: string,
	// The component file couldn't be loaded (missing, unreadable, or a loop):
	// this node is a placeholder that keeps the instance's link and its
	// "overrides" JSON as they were, so saving doesn't lose them (#72).
	componentMissing:      bool,
	componentRawOverrides: string,
	componentProblem:      string, // why it couldn't be loaded (for the Inspector)
	// A component's root (in its file / document, and on its instances): the
	// properties of its nodes shown on every instance (#85).
	componentExposed: []Component_Exposed,
	// A custom node type (custom_nodes.odin): the project-relative .node.json
	// this node is one of ("" = none). Saved as its base type, the link, and
	// only what differs from the type's defaults.
	customType: string,
	// The definition couldn't be loaded: the node is its base type, and its
	// keys are saved back as they were loaded (customRaw, JSON).
	customMissing: bool,
	customRaw:     string,
	// The type's values the node was built from (JSON): it saves what
	// differs from them, so a type changed since (its file edited, undone)
	// doesn't pin the old values on it (like componentBase).
	customBase: string,
	// Saved signal connections from this node's events to script methods
	// (signals.odin).
	signalConnections: [dynamic]Signal_Connection,
	// Signals declared on this node (signal_decls.odin; its custom type's
	// and its script's are not in here).
	signals: [dynamic]Signal_Decl,
	tags: [dynamic]string, // groups ("enemy"); node_tags.odin
}

CreateNode :: proc(manager: ^NodeManager, $T: typeid) -> (node: ^T) {

	// Create allocator from the arena used to allocate the node
	allocator := vmem.arena_allocator(&manager.arena)
	node = new(T, allocator)
	genNode := cast(^Node)node
	InitializeNode(genNode)
	genNode.typeId = T
	node = cast(^T)genNode
	return node
}

// Node creation cost: every node owns a virtual-memory arena and a UUID.
// The arena is reserved on the node's first allocation (many nodes never
// allocate), arenas of destroyed nodes are recycled (reserving virtual
// memory is the expensive part), and UUIDs come from a fast generator
// seeded once from the OS (they only need to be unique, not unpredictable).
@(private = "file")
arenaPool: [dynamic]vmem.Arena
@(private = "file")
ARENA_POOL_MAX :: 16384
// First block of a node arena; most nodes need a few hundred bytes, the
// arena grows when one needs more.
NODE_ARENA_BLOCK :: 64 * mem.Kilobyte
@(private = "file")
idState: runtime.Default_Random_State
@(private = "file")
idSeeded: bool

@(private = "file")
node_new_id :: proc() -> uuid.Identifier {
	if !idSeeded {
		seed: [16]u8
		crypto.rand_bytes(seed[:])
		idState = rand.create(seed[:])
		idSeeded = true
	}
	context.random_generator = runtime.default_random_generator(&idState)
	return uuid.generate_v4()
}

// Node_ReleaseArenaPool frees the recycled arenas (engine shutdown).
Node_ReleaseArenaPool :: proc() {
	for &a in arenaPool do vmem.arena_destroy(&a)
	delete(arenaPool)
	arenaPool = nil
}

// node_arena_proc: the node's allocator - its arena, reserved (or taken
// from the pool) on the first allocation.
@(private = "file")
node_arena_proc :: proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int, old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]byte, mem.Allocator_Error) {
	arena := (^vmem.Arena)(data)
	if arena.total_reserved == 0 {
		#partial switch mode {
		case .Free, .Free_All: return nil, nil // nothing allocated yet
		case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
			if len(arenaPool) > 0 {
				arena^ = pop(&arenaPool)
			} else if err := vmem.arena_init_growing(arena, NODE_ARENA_BLOCK); err != nil {
				return nil, .Out_Of_Memory
			}
		}
	}
	return vmem.arena_allocator_proc(data, mode, size, alignment, old_memory, old_size, loc)
}

InitializeNode :: proc(node: ^Node) {
	node.allocator = mem.Allocator{procedure = node_arena_proc, data = &node.arena}
	// Typed *_Init procs call InitializeNode again after CreateNode: keep
	// one registry entry per node.
	if Node_IsAlive(node) do Node_Unregister(node)
	node.id = node_new_id()
	Node_Register(node)
	if node.typeId == nil {
		node.typeId = Node
	}
	node.position = {0, 0}
	node.scale = {1, 1}
	node.rotation = 0
	node.pivot = {0.5, 0.5}
	node.enabled = true
	node.renderable = true
	node.layer = RenderLayer.Layer1
	node.events = nil
}

// Node_Event: the tree events every node raises.
Node_Event :: enum {
	Entered_Tree,   // "entered_tree": joined the scene
	Exited_Tree,    // "exited_tree": being removed
	Child_Added,    // "child_added"(child)
	Child_Removed,  // "child_removed"(child)
	Parent_Added,   // "parent_added"(parent)
	Parent_Removed, // "parent_removed"(parent)
}

NODE_EVENT_NAMES := [Node_Event]string {
	.Entered_Tree   = "entered_tree",
	.Exited_Tree    = "exited_tree",
	.Child_Added    = "child_added",
	.Child_Removed  = "child_removed",
	.Parent_Added   = "parent_added",
	.Parent_Removed = "parent_removed",
}

Node_Events :: struct {
	subjects: [Node_Event]EventSubject,
}

// Node_Subject: a node's tree event subject, made on first use (in the
// node's arena) - subscribe to it like any other event.
Node_Subject :: proc(node: ^Node, ev: Node_Event) -> ^EventSubject {
	if node.events == nil {
		node.events = new(Node_Events, node.allocator)
		for &s, k in node.events.subjects do InitializeSubject(&s, NODE_EVENT_NAMES[k], node)
	}
	return &node.events.subjects[ev]
}

// Node_NotifyEvent raises a tree event: its listeners (if any) and the
// node's Lua handlers / signal connections.
Node_NotifyEvent :: proc(node: ^Node, ev: Node_Event, value: EventValue, ctx: ^GameContext) {
	if node.events != nil {
		Notify(&node.events.subjects[ev], node, value, ctx)
	} else {
		Script_DispatchEvent(node, NODE_EVENT_NAMES[ev], value, ctx)
	}
}

Node_AddResource :: proc(node: ^Node, $T: typeid) -> ^T {
	resource, err := new(T, node.allocator)
	if err != nil {
		log.panic("Error allocating resource for node", err)
	}
	node.resource = cast(rawptr)resource
	return resource
}

Node_Terminate :: proc(node: ^Node) {
	if node == nil do return
	node.inTree = false
	node.removing = false
	node.managerIndex = 0

	if node.onDestroy != nil {
		destroyProc := node.onDestroy
		node.onDestroy = nil
		destroyProc(node, node.gameContext)
	}

	// Destroy script instance if attached
	if node.scriptInstance != nil {
		inst := cast(^ScriptInstance)node.scriptInstance
		inst.node = nil
		node.scriptInstance = nil
		ScriptInstance_Destroy(inst)
	}

	if node.events != nil {
		for &s in node.events.subjects do DestroySubject(&s)
		node.events = nil // its memory goes with the arena
	}
	// Lua: drop connections to/from this node; references become nil.
	Script_ForgetNode(node)
	// Event bus subscriptions scoped to this node.
	if node.gameContext != nil && node.gameContext.game != nil do EventBus_ForgetNode(&node.gameContext.game.events, node)
	// Resource copies local to this node (a component instance / tree root).
	Resource_ForgetScope(node)
	Node_Unregister(node)
	// Recycle the arena (keeps its first block reserved).
	if node.arena.total_reserved == 0 {
		// Never allocated: nothing to give back.
	} else if len(arenaPool) < ARENA_POOL_MAX && node.arena.kind == .Growing && node.arena.curr_block != nil {
		vmem.arena_free_all(&node.arena)
		if arenaPool == nil do arenaPool = make([dynamic]vmem.Arena, 0, 256, Engine_HeapAllocator())
		append(&arenaPool, node.arena)
	} else {
		vmem.arena_destroy(&node.arena)
	}
	node.arena = {}
}
