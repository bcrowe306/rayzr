package engine

import "core:log"
import "core:math"
import "core:container/queue"
import "core:mem"
import vmem "core:mem/virtual"
import "core:strings"

// The hierarchy is kept on the nodes (node.parent, node.children: ordered),
// so every walk reads a node's children from the node itself - no lookup.
// (It was a pair of maps: a hash lookup per node per walk, several walks a
// frame.) The child lists are allocated by the manager's listAllocator.
NodeManager :: struct {
	nodes: [dynamic]^Node,
	addition: [dynamic]^Node,
	removal: [dynamic]^Node,
	listAllocator: mem.Allocator, // the nodes' child lists (context.allocator at NodeManager_Init)
	free: queue.Queue(int),
	arena: vmem.Arena,
	// VisibilityNotifierNodes in the manager (added / removed with them),
	// so the per-frame visibility pass touches only those.
	notifiers: [dynamic]^Node,
	// NavigationRegion / NavigationAgent nodes (navigation_nodes.odin).
	navRegions: [dynamic]^Node,
	navAgents:  [dynamic]^Node,
	// AdvancedCameraNodes (advanced_camera.odin), in the order added.
	advCameras: [dynamic]^Node,
	// Where Screen Layers' screen space is (screen_layer.odin): the game's
	// frame, or the camera's view in the editor.
	screen: Screen_Mapping,
}

NodeManagerStats :: struct {
	capacity: int,
	count: int,
	free: int,
}


NodeManager_GetStats :: proc(manager: ^NodeManager) -> NodeManagerStats {
	cap := len(manager.nodes)
	free := queue.len(manager.free)
	count: = cap - free
	return NodeManagerStats{
		capacity = cap,
		free = free,
		count = count
	}
}

NodeManager_Init :: proc(manager: ^NodeManager) {
	manager.nodes = nil
	manager.addition = nil
	manager.removal = nil
	manager.listAllocator = context.allocator
	manager.notifiers = nil
	err := vmem.arena_init_growing(&manager.arena)
	if err != nil {
		log.error(err)
	}
	queue.init(&manager.free)
}

NodeManager_Terminate :: proc(manager: ^NodeManager) {
	if manager == nil do return

	// Terminate any nodes still active or queued
	for node in manager.nodes {
		if node != nil {
			children_free(manager, node)
			Node_Terminate(node)
		}
	}
	for addNode in manager.addition {
		if addNode != nil {
			alreadyInNodes := false
			for n in manager.nodes {
				if n == addNode {
					alreadyInNodes = true
					break
				}
			}
			if !alreadyInNodes {
				children_free(manager, addNode)
				Node_Terminate(addNode)
			}
		}
	}

	delete(manager.addition)
	delete(manager.removal)
	delete(manager.nodes)
	delete(manager.notifiers)
	delete(manager.navRegions)
	delete(manager.navAgents)
	delete(manager.advCameras)
	queue.destroy(&manager.free)
	vmem.arena_destroy(&manager.arena)

	manager.addition = nil
	manager.removal = nil
	manager.nodes = nil
	manager.notifiers = nil
	manager.navRegions = nil
	manager.navAgents = nil
	manager.advCameras = nil
}

// GetChildrenView returns a node's children in order without allocating.
// The slice is invalidated by AddChild/RemoveChild on the same parent; copy
// it (GetChildren / GetChildrenTemp) when the loop may change the hierarchy.
GetChildrenView :: #force_inline proc(manager: ^NodeManager, parent: ^Node) -> []^Node {
	if parent == nil do return nil
	return parent.children.data[:parent.children.len]
}

// GetChildrenTemp copies a node's children into the temp allocator.
GetChildrenTemp :: proc(manager: ^NodeManager, parent: ^Node) -> []^Node {
	view := GetChildrenView(manager, parent)
	if len(view) == 0 do return nil
	out := make([]^Node, len(view), context.temp_allocator)
	copy(out, view)
	return out
}

// This allocates. Need to clean up when done
GetChildren :: proc(manager: ^NodeManager, parent: ^Node) -> [dynamic]^Node {
	nodes: [dynamic]^Node = make([dynamic]^Node)
	append(&nodes, ..GetChildrenView(manager, parent))
	return nodes
}

GetChild :: proc(manager: ^NodeManager, parent: ^Node) -> (node: ^Node, found: bool) {
	view := GetChildrenView(manager, parent)
	if len(view) > 0 do return view[0], true
	return nil, false
}

GetChildByName :: proc(manager: ^NodeManager, parent: ^Node, name: string) -> (node: ^Node, found: bool) {
	if parent == nil {
		log.error("Parent node is nil. Cannot get child by name")
		return nil, false
	}

	if name == "" {
		log.error("Child name is empty. Cannot get child by name")
		return nil, false
	}
	for child in GetChildrenView(manager, parent) {
		if child.name == name do return child, true
	}
	return nil, false
}

GetParent :: #force_inline proc(manager: ^NodeManager, node: ^Node) -> ^Node {
	return node.parent if node != nil else nil
}

GetRootNode :: proc(scene: ^Scene) -> ^Node {
	return scene.rootNode
}

HasParent :: proc(manager: ^NodeManager, node: ^Node) -> bool {
	return node != nil && node.parent != nil
}


// RemoveNode queues a node and its subtree for removal (at the end of the
// frame). A node taken from a pool goes back to its pool instead.
RemoveNode :: proc(manager: ^NodeManager, node: ^Node) {
	if node == nil || node.removing do return
	if node.pool != nil && node.enabled && Pool_Return(manager, node, node.gameContext) do return
	remove_tree(manager, node)
}

@(private = "file")
remove_tree :: proc(manager: ^NodeManager, node: ^Node) {
	if node == nil || node.removing do return
	node.removing = true
	for child in GetChildrenTemp(manager, node) do remove_tree(manager, child)
	append(&manager.removal, node)
}



ProcessNodeQueues :: proc(manager: ^NodeManager, gameContext: ^GameContext) {
	// Remove. The parents' child lists lose their removed children in one
	// pass each (removing them one by one is quadratic for big scenes).
	filtered := make(map[^Node]bool, context.temp_allocator)
	for n in manager.removal {
		if parent := n.parent; parent != nil && !parent.removing && parent not_in filtered {
			filtered[parent] = true
			list := GetChildrenView(manager, parent)
			keep := 0
			for c in list do if !c.removing {list[keep] = c; keep += 1}
			parent.children.len = i32(keep)
		}
	}
	for removingNode in manager.removal {
		// Remove relationships (to its parent and to its children).
		if parent := removingNode.parent; parent != nil {
			Node_NotifyEvent(parent, .Child_Removed, removingNode, gameContext)
			Node_NotifyEvent(removingNode, .Parent_Removed, parent, gameContext)
			if parent in filtered {
				if removingNode.parent == parent do removingNode.parent = nil
			} else {
				unlink(manager, parent, removingNode)
			}
		}
		for child in GetChildrenTemp(manager, removingNode) {
			Node_NotifyEvent(removingNode, .Child_Removed, child, gameContext)
			Node_NotifyEvent(child, .Parent_Removed, removingNode, gameContext)
			unlink(manager, removingNode, child)
		}
		children_free(manager, removingNode)

		// Remove nodes from manager. No modify node array. use free list
		index := removingNode.managerIndex - 1
		if index < 0 || index >= len(manager.nodes) || manager.nodes[index] != removingNode {
			index = -1
			for node, i in manager.nodes do if node == removingNode {index = i; break}
		}
		if index >= 0 {
			node := removingNode
			log.debug("Removing node from tree: ", node)
			node.gameContext = gameContext
			Node_NotifyEvent(node, .Exited_Tree, nil, gameContext)

			if node.pool != nil do Pool_Forget(node) // freed with its parent (not returned)
			if node.typeId == VisibilityNotifierNode {
				for n, k in manager.notifiers do if n == node {unordered_remove(&manager.notifiers, k); break}
			}
			if node.typeId == NavigationRegionNode {
				for n, k in manager.navRegions do if n == node {unordered_remove(&manager.navRegions, k); break}
			}
			if node.typeId == NavigationAgentNode {
				for n, k in manager.navAgents do if n == node {unordered_remove(&manager.navAgents, k); break}
			}
			if node.typeId == AdvancedCameraNode {
				for n, k in manager.advCameras do if n == node {ordered_remove(&manager.advCameras, k); break}
			}
			// Frees node's arena, subjects, and any custom onDestroy resources.
			Node_Terminate(node)
			manager.nodes[index] = nil
			queue.push_back(&manager.free, index)
		} else {
			removingNode.removing = false // not in the list (yet): it stays
		}
	}
	clear(&manager.removal)


	// Addition. Notify "entered_tree" after the whole batch is in, so
	// handlers can see their new siblings/children.
	added := make([dynamic]^Node, context.temp_allocator)
	for addNode in manager.addition {
		if addNode != nil {
			addNode.gameContext = gameContext
		}
		index, ok := queue.pop_back_safe(&manager.free)
		if ok {
			log.debug("Adding node using free list")
			manager.nodes[index] = addNode
		}
		else {
			log.debug("Adding node")
			append(&manager.nodes, addNode)
			index = len(manager.nodes) - 1
		}
		if addNode != nil do addNode.managerIndex = index + 1
		if addNode != nil do append(&added, addNode)
		if addNode != nil && addNode.typeId == VisibilityNotifierNode do append(&manager.notifiers, addNode)
		if addNode != nil && addNode.typeId == NavigationRegionNode do append(&manager.navRegions, addNode)
		if addNode != nil && addNode.typeId == NavigationAgentNode do append(&manager.navAgents, addNode)
		if addNode != nil && addNode.typeId == AdvancedCameraNode do append(&manager.advCameras, addNode)
	}
	clear(&manager.addition)
	for n in added {
		if Node_IsAlive(n) do Node_NotifyEvent(n, .Entered_Tree, nil, gameContext)
	}
}


// Node_SetGlobalPositions composes transforms down the tree: a child's
// position is scaled and rotated by its parent (so children orbit and scale
// with their parent), scales multiply and rotations add.
Node_SetGlobalPositions :: proc(manager: ^NodeManager, node: ^Node, positionOffset: [2]f32 = {0,0}, scaleOffset: [2]f32 = {1, 1}, rotationOffset: f32 = 0) {
	if node == nil {
		return
	}
	if node.typeId == ScreenLayerNode {
		// Screen space: anchored to the frame, not to its parent.
		node.globalPosition, node.globalScale = ScreenLayer_Global(manager.screen, cast(^ScreenLayerNode)node)
		node.globalRotation = node.rotation
	} else {
		node.globalPosition = positionOffset + rotate_vec(node.position * scaleOffset, rotationOffset)
		node.globalScale = node.scale * scaleOffset
		if len(nodeFx) > 0 do node.globalScale *= Fx_ScaleOf(node) // (node:squash)
		node.globalRotation = node.rotation + rotationOffset
	}
	for child in GetChildrenView(manager, node) {
		Node_SetGlobalPositions(manager, child, node.globalPosition, node.globalScale, node.globalRotation)
	}
}

// Node_ComputeWorldPosition: a node's world position from its parent chain,
// for when globalPosition isn't up to date yet (e.g. during ready).
Node_ComputeWorldPosition :: proc(manager: ^NodeManager, node: ^Node) -> [2]f32 {
	chain := make([dynamic]^Node, context.temp_allocator)
	for n := node; n != nil; n = GetParent(manager, n) do append(&chain, n)
	pos, scl, rot := [2]f32{0, 0}, [2]f32{1, 1}, f32(0)
	#reverse for n in chain {
		if n.typeId == ScreenLayerNode {
			pos, scl = ScreenLayer_Global(manager.screen, cast(^ScreenLayerNode)n)
			rot = n.rotation
			continue
		}
		pos = pos + rotate_vec(n.position * scl, rot)
		scl *= n.scale
		rot += n.rotation
	}
	return pos
}

@(private)
rotate_vec :: proc(v: [2]f32, degrees: f32) -> [2]f32 {
	if degrees == 0 do return v
	r := math.to_radians(degrees)
	c, s := math.cos(r), math.sin(r)
	return {v.x * c - v.y * s, v.x * s + v.y * c}
}

// Node_ParentToWorld / Node_WorldToParent convert points between world space
// and the space a node's `position` is expressed in (its parent's space).
Node_WorldToParent :: proc(manager: ^NodeManager, node: ^Node, world: [2]f32) -> [2]f32 {
	if node != nil && node.typeId == ScreenLayerNode do return ScreenLayer_PositionAt(manager.screen, cast(^ScreenLayerNode)node, world)
	parent := GetParent(manager, node)
	if parent == nil do return world
	local := rotate_vec(world - parent.globalPosition, -parent.globalRotation)
	sx := parent.globalScale.x if parent.globalScale.x != 0 else 1
	sy := parent.globalScale.y if parent.globalScale.y != 0 else 1
	return {local.x / sx, local.y / sy}
}

Node_ParentToWorld :: proc(manager: ^NodeManager, node: ^Node, local: [2]f32) -> [2]f32 {
	if node != nil && node.typeId == ScreenLayerNode {
		size, s := screen_frame(manager.screen)
		return manager.screen.origin + (Screen_AnchorFactor((cast(^ScreenLayerNode)node).anchor) * size + local) * s
	}
	parent := GetParent(manager, node)
	if parent == nil do return local
	return parent.globalPosition + rotate_vec(local * parent.globalScale, parent.globalRotation)
}

AddChild :: proc(manager: ^NodeManager, parent, child: ^Node) {
	if parent == child {
		log.error("Child node cannot be it's own parent")
		return
	}
	if existing := child.parent; existing != nil {
		if existing == parent {
			log.error("Parent already has child")
			return
		}
		// A node has one parent: moving it detaches it from the old one.
		unlink(manager, existing, child)
	}
	children_insert(manager, parent, int(parent.children.len), child)
	child.parent = parent
	ctx := parent.gameContext if parent.gameContext != nil else child.gameContext
	Node_NotifyEvent(parent, .Child_Added, child, ctx)
	Node_NotifyEvent(child, .Parent_Added, parent, ctx)
}

// MoveChild moves a child to position `index` among its siblings.
MoveChild :: proc(manager: ^NodeManager, parent, child: ^Node, index: int) {
	if parent == nil || parent.children.len == 0 do return
	children_remove(parent, child)
	children_insert(manager, parent, clamp(index, 0, int(parent.children.len)), child)
}

RemoveChild :: proc(manager: ^NodeManager, parent, child: ^Node) {
	if child == nil || child.parent == nil || child.parent != parent {
		log.error("Child Relationship not found. Cannot remove")
		return
	}
	unlink(manager, parent, child)
}

// unlink removes a parent/child link, keeping the sibling order.
@(private = "file")
unlink :: proc(manager: ^NodeManager, parent, child: ^Node) {
	children_remove(parent, child)
	if child.parent == parent do child.parent = nil
}

// Node_Children: a node's ordered children - a pointer and 32-bit counts
// (16 bytes in every node; the allocator is the manager's).
Node_Children :: struct {
	data:     [^]^Node,
	len, cap: i32,
}

// children_insert puts `child` at `index` among parent's children.
@(private = "file")
children_insert :: proc(manager: ^NodeManager, parent: ^Node, index: int, child: ^Node) {
	c := &parent.children
	if c.len == c.cap {
		newCap := max(4, int(c.cap) * 2)
		data, err := mem.alloc(newCap * size_of(^Node), align_of(^Node), manager.listAllocator)
		if err != nil {
			log.errorf("AddChild: out of memory (%v)", err)
			return
		}
		grown := ([^]^Node)(data)
		copy(grown[:c.len], c.data[:c.len])
		if c.data != nil do mem.free(c.data, manager.listAllocator)
		c.data = grown
		c.cap = i32(newCap)
	}
	copy(c.data[index + 1:c.len + 1], c.data[index:c.len])
	c.data[index] = child
	c.len += 1
}

// children_remove takes `child` out of parent's children (keeping the order).
@(private = "file")
children_remove :: proc(parent: ^Node, child: ^Node) {
	if parent == nil do return
	c := &parent.children
	for i in 0 ..< int(c.len) {
		if c.data[i] == child {
			copy(c.data[i:c.len - 1], c.data[i + 1:c.len])
			c.len -= 1
			return
		}
	}
}

// children_free releases a node's child list (removed / terminated nodes).
@(private = "file")
children_free :: proc(manager: ^NodeManager, node: ^Node) {
	if node.children.data != nil do mem.free(node.children.data, manager.listAllocator)
	node.children = {}
}

PathStartState :: enum {
	Root,
	Relative,
	Parent,
}

GetNodeByPath :: proc(scene: ^Scene, currentNode: ^Node, path: string) -> (node: ^Node, found: bool) {
	if path == "" {
		log.error("Path is empty. Cannot get node by path")
		return nil, false
	}

	parts, err := strings.split(path, "/")
	if err != nil {
		log.error("Error splitting path: ", err)
		return nil, false
	}
	defer delete(parts)

	if len(parts) == 0 {
		log.error("Path is empty after splitting. Cannot get node by path")
		return nil, false
	}


	startState : PathStartState
	startingIndex := 0
	if parts[0] == "" {
		startState = PathStartState.Root
		startingIndex = 1
	}
	else if parts[0] == "." {
		startState = PathStartState.Relative
		startingIndex = 1
	}
	else if parts[0] == ".." {
		startState = PathStartState.Parent
		startingIndex = 1
	}
	else {
		startState = PathStartState.Relative
		startingIndex = 0
	}

	startingNode := scene.rootNode
	switch startState {
		case .Root:
			startingNode = scene.rootNode
		case .Relative:
			startingNode = currentNode
		case .Parent:
			parent := GetParent(scene.manager, currentNode)
			if parent == nil {
				log.error("Current node has no parent. Cannot get node by path")
				return nil, false
			}
			startingNode = parent
	}

	foundNode := startingNode
	for part in parts[startingIndex:] {
		if part == "" || part == "." || part == ".." {
			log.error("Path part is empty, relative, or parent. Cannot get node by path")
			return nil, false
		}

		child, found := GetChildByName(scene.manager, startingNode, part)
		if !found {
			log.error("Child node not found: ", part)
			return nil, false
		}
		startingNode = child
		foundNode = child
	}


	return foundNode, true
}
