package engine

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:math"
import os "osx"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"
import b2 "vendor:box2d"
import rl "vendor:raylib"

// ============================================================================
// LdtkLevelNode: an LDtk level (or a whole world) in a scene.
//
// Saved with the scene: the project file, the world and level, and how the
// level is built (the "ldtk" object of the node):
//
//   - World mode: every level of the world is shown and built at its world
//     position; otherwise only the current level, at the node's origin.
//   - Collision rules: per IntGrid layer and value - None, Solid, One-way
//     (passable from below) or Trigger (an AreaNode raising body_entered /
//     body_exited), with friction and restitution. Neighbouring cells with
//     the same rule merge into a few large boxes. Without rules, the legacy
//     collisionLayer + solidValues settings are used.
//   - Entity mappings: what an LDtk entity spawns - Auto (the component
//     components/<Identifier>.component.json if it exists; with Match
//     Custom Nodes, else the project's custom node type of that name; else a
//     Node), a chosen component, a chosen custom node type (#157), a plain
//     Node, or nothing. LDtk fields set script properties of the same name.
//   - Link rules: what an EntityRef field does once both ends are spawned -
//     connect a signal of the source to a method of the target, or parent
//     one to the other. Scripts can always follow links with
//     node:ldtk_ref(field) / node:ldtk_refs(field) / node:ldtk_referenced_by().
//
// Colliders and spawned entities are transient: built when the node becomes
// ready (in the game, or Simulate in the editor), never saved. Layers draw
// with LDtk's parallax. Editing the .ldtk file reloads the level live.
// Events: "level_loaded" (level identifier; once spawned entities are
// ready), "entity_spawned" (node).
// ============================================================================

LdtkCollisionType :: enum {
	None,
	Solid,
	OneWay,  // solid from above only (platforms you jump through)
	Trigger, // sensor area: body_entered / body_exited
}

LdtkCollisionRule :: struct {
	layer:       string,
	value:       int,
	type:        LdtkCollisionType,
	friction:    f32,
	restitution: f32,
}

LdtkSpawnMode :: enum {
	Auto,       // components/<Identifier>.component.json if it exists (then, with matchCustomNodes, the custom node type <Identifier>), else a Node
	Component,  // the mapping's component
	Node,       // a plain Node
	None,       // not spawned
	CustomNode, // the mapping's custom node type (#157)
}

LdtkEntityMapping :: struct {
	entity:    string,
	mode:      LdtkSpawnMode,
	component: string, // project-relative .component.json
	nodeType:  string, // (CustomNode) project-relative .node.json
}

LdtkLinkAction :: enum {
	Signal,               // source:<signal> -> target:<method>(value, source)
	ParentTargetToSource, // the target becomes a child of the source
	ParentSourceToTarget, // the source becomes a child of the target
}

LdtkLinkRule :: struct {
	entity: string, // source entity identifier
	field:  string, // its EntityRef field (single or array)
	action: LdtkLinkAction,
	signal: string,
	method: string,
}

// A resolved EntityRef between two spawned entities.
Ldtk_Link :: struct {
	source:    ^Node,
	target:    ^Node, // nil when the target isn't spawned (other level, not mapped)
	sourceIid: string,
	targetIid: string,
	field:     string,
	index:     int,
}

LdtkLevelNode :: struct {
	using node:          Node,
	shininess: f32 `gui:"true" min:"0" max:"1"`, // lit: a glint from lights (#274; its image's _s.png too)
	scene:               ^Scene,
	project:             ^LdtkProject,
	level:               ^LdtkLevel,  // current level (the focus in world mode)
	levelIdentifier:     string,
	worldIdentifier:     string,
	worldMode:           bool,        // show and build every level of the world
	projectPath:         string,      // .ldtk file the project was loaded from (saved with the scene)
	ownsProject:         bool,
	enablePhysics:       bool `gui:"true"`,   // build colliders (collision rules)
	spawnEntities:       bool `gui:"true"`,   // spawn entities when ready
	parallax:            bool `gui:"true"`,   // LDtk layer parallax
	drawBackground:      bool `gui:"true"`,
	drawEntityTiles:     bool `gui:"true"`,   // draw entities' LDtk tiles (editor visuals)
	tintColor:           rl.Color `gui:"true"`,
	drawDebugColliders:  bool `gui:"true"`,
	drawDebugEntities:   bool `gui:"true"`,
	// Auto mappings also spawn the project's custom node type named like the
	// entity (when there's no component of that name). Off: opt in (#157).
	matchCustomNodes:    bool `gui:"true"`,
	// Legacy collision settings (used when there are no collision rules).
	collisionLayer:      string,
	solidValues:         string,
	collisionRules:      [dynamic]LdtkCollisionRule,
	entityMappings:      [dynamic]LdtkEntityMapping,
	linkRules:           [dynamic]LdtkLinkRule,
	// Built state.
	activeLevels:        [dynamic]^LdtkLevel,
	staticBody:          ^StaticBodyNode, // solid colliders
	oneWayBody:          ^StaticBodyNode,
	triggers:            [dynamic]^AreaNode,
	solidLayerName:      string,
	entitySpawner:       LdtkEntitySpawner,
	spawnOffset:         [2]f32, // level offset of the entity being spawned (world mode)
	spawnedEntities:     [dynamic]^Node,
	spawnedByIid:        map[string]^Node,
	entityOfNode:        map[^Node]^LdtkEntityInstance,
	links:               [dynamic]Ldtk_Link,
	onLevelLoaded:       EventSubject,
	onEntitySpawned:     EventSubject,
	pendingLoaded:       bool,
	fileModTime:         time.Time,
	lastFileCheck:       time.Tick,
	built:               bool,
	// Editor view (not used by the game): layer visibility overrides, solo
	// and highlighted layer, parallax preview around the editor camera.
	layerVisibility:     map[string]bool,
	editorPreview:       bool,
	editorParallax:      bool,
	editorCamera:        [2]f32,
	editorSoloLayer:     string,
	editorHighlight:     string,
	editorShowIntGrid:   bool,
}

LdtkEntitySpawner :: proc(levelNode: ^LdtkLevelNode, entity: ^LdtkEntityInstance, scene: ^Scene, ctx: ^GameContext) -> ^Node

DEFAULT_LDTK_FRICTION :: 0.5
DEFAULT_LDTK_RESTITUTION :: 0.2

@(private = "file")
ldtk_node_init :: proc(node: ^LdtkLevelNode, scene: ^Scene, name: string) {
	node.name = strings.clone(name, node.allocator) // owned: callers pass temp strings too
	node.scene = scene
	node.tintColor = rl.WHITE
	node.enablePhysics = true
	node.collisionLayer = "Collisions"
	node.solidValues = "1"
	node.spawnEntities = true
	node.drawBackground = true
	node.parallax = true
	node.editorParallax = true
	node.spawnedEntities = make([dynamic]^Node, node.allocator)
	node.spawnedByIid = make(map[string]^Node, allocator = node.allocator)
	node.entityOfNode = make(map[^Node]^LdtkEntityInstance, allocator = node.allocator)
	node.links = make([dynamic]Ldtk_Link, node.allocator)
	node.triggers = make([dynamic]^AreaNode, node.allocator)
	node.activeLevels = make([dynamic]^LdtkLevel, node.allocator)
	node.collisionRules = make([dynamic]LdtkCollisionRule, node.allocator)
	node.entityMappings = make([dynamic]LdtkEntityMapping, node.allocator)
	node.linkRules = make([dynamic]LdtkLinkRule, node.allocator)
	node.layerVisibility = make(map[string]bool, allocator = node.allocator)
	node.update = LdtkLevelNode_Update
	node.render = LdtkLevelNode_Render
	node.ready = LdtkLevelNode_Ready
	node.onDestroy = LdtkLevelNode_Destroy
	InitializeSubject(&node.onLevelLoaded, "level_loaded", node)
	InitializeSubject(&node.onEntitySpawned, "entity_spawned", node)
}

LdtkLevelNode_Create :: proc(
	scene: ^Scene,
	name: string = "LdtkLevel",
	projectPath: string = "",
	levelIdentifier: string = "",
	parent: ^Node = nil,
) -> ^LdtkLevelNode {
	node := CreateNode(scene.manager, LdtkLevelNode)
	ldtk_node_init(node, scene, name)
	if len(projectPath) > 0 do LdtkLevelNode_SetProject(node, projectPath, levelIdentifier)
	scene->addNode(node, parent)
	return node
}

LdtkLevelNode_CreateFromProject :: proc(
	scene: ^Scene,
	name: string = "LdtkLevel",
	project: ^LdtkProject,
	levelIdentifier: string = "",
	parent: ^Node = nil,
) -> ^LdtkLevelNode {
	node := CreateNode(scene.manager, LdtkLevelNode)
	ldtk_node_init(node, scene, name)
	node.project = project
	node.ownsProject = false
	if project != nil {
		Ldtk_LoadTextures(project)
		ldtk_pick_level(node, levelIdentifier)
	}
	scene->addNode(node, parent)
	return node
}

// ldtk_asset_reader reads project files from disk, else through the game's
// asset manager (mounted .rayzr package).
@(private = "file")
ldtk_asset_reader :: proc(path: string, user: rawptr) -> ([]byte, bool) {
	if data, err := os.read_entire_file(path, context.temp_allocator); err == nil do return data, true
	if user != nil {
		am := cast(^AssetManager)user
		rel := path
		if dir := strings.trim_suffix(am.projectDir, "/"); dir != "" && strings.has_prefix(rel, dir) && len(rel) > len(dir) do rel = rel[len(dir) + 1:]
		return AssetManager_ReadFileBytes(am, rel, context.temp_allocator)
	}
	return nil, false
}

// ldtk_pick_level selects the level (by identifier, within the current
// world when set) and refreshes the active levels.
@(private = "file")
ldtk_pick_level :: proc(ln: ^LdtkLevelNode, levelIdentifier: string) {
	proj := ln.project
	ln.level = nil
	if proj == nil do return
	world := Ldtk_GetWorld(proj, ln.worldIdentifier) if ln.worldIdentifier != "" else nil
	if levelIdentifier != "" do ln.level = Ldtk_GetLevelInWorld(proj, world, levelIdentifier)
	if ln.level == nil && world != nil && len(world.levels) > 0 do ln.level = &proj.levels[world.levels[0]]
	if ln.level == nil do ln.level = Ldtk_GetLevelByIndex(proj, 0)
	if ln.level != nil {
		if ln.level.identifier != ln.levelIdentifier do ln.levelIdentifier = strings.clone(ln.level.identifier, ln.allocator)
		if w := Ldtk_WorldOf(proj, ln.level); w != nil && w.identifier != ln.worldIdentifier do ln.worldIdentifier = strings.clone(w.identifier, ln.allocator)
	}
	LdtkLevelNode_RefreshActiveLevels(ln)
}

// LdtkLevelNode_RefreshActiveLevels: the levels drawn and built - the
// current one, or in world mode every level of its world at its depth.
LdtkLevelNode_RefreshActiveLevels :: proc(ln: ^LdtkLevelNode) {
	clear(&ln.activeLevels)
	if ln.project == nil || ln.level == nil do return
	world := Ldtk_WorldOf(ln.project, ln.level)
	if ln.worldMode && world != nil {
		for i in world.levels {
			lvl := &ln.project.levels[i]
			if lvl.worldDepth == ln.level.worldDepth do append(&ln.activeLevels, lvl)
		}
	} else {
		append(&ln.activeLevels, ln.level)
	}
}

// LdtkLevelNode_LevelOffset: where a level sits relative to the node.
LdtkLevelNode_LevelOffset :: proc(ln: ^LdtkLevelNode, level: ^LdtkLevel) -> [2]f32 {
	if !ln.worldMode || level == nil do return {}
	return {f32(level.worldX), f32(level.worldY)}
}

// LdtkLevelNode_SetProject (re)loads the node's LDtk project and level.
LdtkLevelNode_SetProject :: proc(node: ^LdtkLevelNode, projectPath: string, levelIdentifier: string = "") {
	if node == nil do return
	TileCache_Evict(node)
	LdtkLevelNode_ClearBuilt(node)
	if node.ownsProject && node.project != nil do Ldtk_DestroyProject(node.project)
	node.project = nil
	node.level = nil
	node.ownsProject = false
	clear(&node.activeLevels)
	if projectPath != node.projectPath do node.worldIdentifier = "" // another project: its own worlds
	node.projectPath = strings.clone(projectPath, node.allocator)
	node.levelIdentifier = strings.clone(levelIdentifier, node.allocator)
	if projectPath == "" do return
	am: rawptr = nil
	if node.gameContext != nil && node.gameContext.game != nil do am = &node.gameContext.game.assetManager
	proj, ok := Ldtk_LoadProjectFromFile(projectPath, context.allocator, ldtk_asset_reader, am)
	if !ok || proj == nil {
		log.errorf("[LDtk] Failed to load project: %s", projectPath)
		return
	}
	node.project = proj
	node.ownsProject = true
	if rl.IsWindowReady() do Ldtk_LoadTextures(proj)
	ldtk_pick_level(node, levelIdentifier)
	if info, err := os.stat(projectPath, context.temp_allocator); err == nil do node.fileModTime = info.modification_time
	if node.isReady do LdtkLevelNode_Build(node, node.gameContext)
}

// LdtkLevelNode_LoadLevel switches to another level (of the current world
// first, else any world).
LdtkLevelNode_LoadLevel :: proc(node: ^LdtkLevelNode, identifier: string) -> bool {
	if node == nil || node.project == nil do return false
	world := Ldtk_GetWorld(node.project, node.worldIdentifier)
	lvl := Ldtk_GetLevelInWorld(node.project, world, identifier)
	if lvl == nil do lvl = Ldtk_GetLevel(node.project, identifier)
	if lvl == nil do lvl = Ldtk_GetLevelByIid(node.project, identifier)
	if lvl == nil do return false
	return LdtkLevelNode_SetLevel(node, lvl)
}

LdtkLevelNode_SetLevel :: proc(node: ^LdtkLevelNode, lvl: ^LdtkLevel) -> bool {
	if lvl == nil do return false
	LdtkLevelNode_ClearBuilt(node)
	node.level = lvl
	node.levelIdentifier = strings.clone(lvl.identifier, node.allocator)
	if w := Ldtk_WorldOf(node.project, lvl); w != nil do node.worldIdentifier = strings.clone(w.identifier, node.allocator)
	LdtkLevelNode_RefreshActiveLevels(node)
	if node.isReady do LdtkLevelNode_Build(node, node.gameContext)
	return true
}

// LdtkLevelNode_SetWorld switches world (its first level, or `level`).
LdtkLevelNode_SetWorld :: proc(node: ^LdtkLevelNode, world: string, level := "") -> bool {
	if node == nil || node.project == nil do return false
	w := Ldtk_GetWorld(node.project, world)
	if w == nil || len(w.levels) == 0 do return false
	lvl := &node.project.levels[w.levels[0]]
	if level != "" {
		lvl = Ldtk_GetLevelInWorld(node.project, w, level)
		if lvl == nil do return false // (no such level in the world: nothing changes)
	}
	return LdtkLevelNode_SetLevel(node, lvl)
}

// LdtkLevelNode_SetWorldMode shows the whole world (or just the level).
LdtkLevelNode_SetWorldMode :: proc(node: ^LdtkLevelNode, on: bool) {
	if node.worldMode == on do return
	LdtkLevelNode_ClearBuilt(node)
	node.worldMode = on
	LdtkLevelNode_RefreshActiveLevels(node)
	if node.isReady do LdtkLevelNode_Build(node, node.gameContext)
}

// LdtkLevelNode_Rebuild rebuilds colliders, entities and links (after
// changing rules or mappings while running).
LdtkLevelNode_Rebuild :: proc(ln: ^LdtkLevelNode) {
	LdtkLevelNode_ClearBuilt(ln)
	if ln.isReady do LdtkLevelNode_Build(ln, ln.gameContext)
}

LdtkLevelNode_Ready :: proc(node: ^Node, ctx: ^GameContext) {
	LdtkLevelNode_Build(cast(^LdtkLevelNode)node, ctx)
}

// LdtkLevelNode_Build creates colliders, spawns entities and links them.
LdtkLevelNode_Build :: proc(ln: ^LdtkLevelNode, ctx: ^GameContext) {
	if ln.level == nil || ln.built do return
	if len(ln.activeLevels) == 0 do LdtkLevelNode_RefreshActiveLevels(ln)
	ln.built = true
	if ln.enablePhysics do LdtkLevelNode_BuildColliders(ln, ctx)
	if ln.spawnEntities {
		LdtkLevelNode_SpawnEntities(ln, ctx)
		LdtkLevelNode_ResolveLinks(ln)
	}
	ln.pendingLoaded = true
}

// LdtkLevelNode_EntityVisual: how an entity is drawn by its level - its
// LDtk icon (with Draw Entity Tiles, and always in the editor, where
// entities aren't spawned), else in the editor its box in its colour.
LdtkLevelNode_EntityVisual :: proc(ln: ^LdtkLevelNode, ent: ^LdtkEntityInstance) -> (icon, outline: bool) {
	icon = ent.tile.has && (ln.drawEntityTiles || ln.editorPreview)
	outline = ln.editorPreview
	return
}

// LdtkLevelNode_ClearBuilt removes colliders, triggers and spawned entities.
LdtkLevelNode_ClearBuilt :: proc(ln: ^LdtkLevelNode) {
	scene := ln.scene
	if scene == nil && ln.gameContext != nil do scene = ln.gameContext.scene
	if scene != nil && scene.manager != nil {
		if ln.staticBody != nil && Node_IsAlive(ln.staticBody) do RemoveNode(scene.manager, ln.staticBody)
		if ln.oneWayBody != nil && Node_IsAlive(ln.oneWayBody) do RemoveNode(scene.manager, ln.oneWayBody)
		for a in ln.triggers do if Node_IsAlive(a) do RemoveNode(scene.manager, a)
		for n in ln.spawnedEntities do if Node_IsAlive(n) do RemoveNode(scene.manager, n)
	}
	ln.staticBody = nil
	ln.oneWayBody = nil
	clear(&ln.triggers)
	clear(&ln.spawnedEntities)
	clear(&ln.spawnedByIid)
	clear(&ln.entityOfNode)
	clear(&ln.links)
	ln.built = false
	ln.pendingLoaded = false
}

@(private = "file")
ldtk_scene :: proc(ln: ^LdtkLevelNode, ctx: ^GameContext) -> ^Scene {
	scene := ln.scene
	if scene == nil && ln.gameContext != nil do scene = ln.gameContext.scene
	if scene == nil && ctx != nil do scene = ctx.scene
	return scene
}

// ----------------------------------------------------------------------------
// Collision
// ----------------------------------------------------------------------------

LdtkCollisionType_Name :: proc(t: LdtkCollisionType) -> string {
	switch t {
	case .None:    return "none"
	case .Solid:   return "solid"
	case .OneWay:  return "one_way"
	case .Trigger: return "trigger"
	}
	return "none"
}

LdtkCollisionType_Parse :: proc(s: string) -> LdtkCollisionType {
	switch s {
	case "solid":   return .Solid
	case "one_way": return .OneWay
	case "trigger": return .Trigger
	}
	return .None
}

// LdtkLevelNode_CollisionRule: how a value of an IntGrid layer collides
// (rules, else the legacy collisionLayer / solidValues).
LdtkLevelNode_CollisionRule :: proc(ln: ^LdtkLevelNode, layer: string, value: int) -> LdtkCollisionRule {
	if value == 0 do return {layer = layer, value = 0}
	if len(ln.collisionRules) > 0 {
		for r in ln.collisionRules do if r.layer == layer && r.value == value do return r
		return {layer = layer, value = value}
	}
	if layer == ln.collisionLayer {
		for part in strings.split(ln.solidValues if ln.solidValues != "" else "1", ",", context.temp_allocator) {
			if v, ok := strconv.parse_int(strings.trim_space(part)); ok && v == value {
				return {layer = layer, value = value, type = .Solid, friction = DEFAULT_LDTK_FRICTION, restitution = DEFAULT_LDTK_RESTITUTION}
			}
		}
	}
	return {layer = layer, value = value}
}

// LdtkLevelNode_SetCollisionRule adds or replaces a rule (the legacy
// settings become rules first, so nothing silently stops colliding).
LdtkLevelNode_SetCollisionRule :: proc(ln: ^LdtkLevelNode, rule: LdtkCollisionRule) {
	if len(ln.collisionRules) == 0 && ln.project != nil {
		// Materialise the legacy setup for every IntGrid value we know of.
		for &def in ln.project.layerDefs {
			if def.type != .IntGrid do continue
			for v in def.intGridValues {
				r := LdtkLevelNode_CollisionRule(ln, def.identifier, v.value)
				if r.type != .None do append(&ln.collisionRules, LdtkCollisionRule{strings.clone(def.identifier, ln.allocator), v.value, r.type, r.friction, r.restitution})
			}
		}
	}
	for &r in ln.collisionRules {
		if r.layer == rule.layer && r.value == rule.value {
			r.type, r.friction, r.restitution = rule.type, rule.friction, rule.restitution
			return
		}
	}
	append(&ln.collisionRules, LdtkCollisionRule{strings.clone(rule.layer, ln.allocator), rule.value, rule.type, rule.friction, rule.restitution})
}

@(private = "file")
Ldtk_Rect :: struct {
	x0, y0, x1, y1: int, // cells, exclusive end
	key:            int,
}

// ldtk_merge_cells merges cells with equal keys (>= 0) into rectangles:
// horizontal runs, then runs stacked on equal runs below.
@(private = "file")
ldtk_merge_cells :: proc(keys: []int, w, h: int) -> [dynamic]Ldtk_Rect {
	out := make([dynamic]Ldtk_Rect, context.temp_allocator)
	open := make([dynamic]int, context.temp_allocator) // indices in out, ending at the previous row
	next := make([dynamic]int, context.temp_allocator)
	for y in 0 ..< h {
		clear(&next)
		x := 0
		for x < w {
			k := keys[y * w + x]
			if k < 0 {
				x += 1
				continue
			}
			start := x
			for x < w && keys[y * w + x] == k do x += 1
			extended := false
			for oi in open {
				r := &out[oi]
				if r.x0 == start && r.x1 == x && r.key == k && r.y1 == y {
					r.y1 = y + 1
					append(&next, oi)
					extended = true
					break
				}
			}
			if !extended {
				append(&out, Ldtk_Rect{start, y, x, y + 1, k})
				append(&next, len(out) - 1)
			}
		}
		open, next = next, open
	}
	return out
}

// LdtkLevelNode_BuildColliders builds the colliders and triggers of the
// active levels from the collision rules.
LdtkLevelNode_BuildColliders :: proc(ln: ^LdtkLevelNode, ctx: ^GameContext, onlyLayer := "", overrideSolids: []int = nil) {
	scene := ldtk_scene(ln, ctx)
	if scene == nil do return
	gc := ctx if ctx != nil else ln.gameContext
	// Boxes are in level pixels: the collider bodies are children at the
	// level's origin, so they follow its position, rotation and scale.
	Material :: struct {
		type:                  LdtkCollisionType,
		friction, restitution: f32,
		value:                 int, // triggers: one area per value
		layer:                 string,
	}
	for lvl in ln.activeLevels {
		off := LdtkLevelNode_LevelOffset(ln, lvl)
		for &layer in lvl.layers {
			if layer.type != .IntGrid && layer.type != .AutoLayer do continue
			if len(layer.intGrid) == 0 || layer.cWid <= 0 || layer.cHei <= 0 do continue
			if onlyLayer != "" && layer.identifier != onlyLayer do continue
			mats := make([dynamic]Material, context.temp_allocator)
			keyOf := make(map[int]int, allocator = context.temp_allocator) // value -> material index (-1 none)
			keys := make([]int, layer.cWid * layer.cHei, context.temp_allocator)
			for v, i in layer.intGrid {
				if i >= len(keys) do break
				k, seen := keyOf[v]
				if !seen {
					k = -1
					rule: LdtkCollisionRule
					if overrideSolids != nil {
						if slice.contains(overrideSolids, v) do rule = {layer.identifier, v, .Solid, DEFAULT_LDTK_FRICTION, DEFAULT_LDTK_RESTITUTION}
					} else {
						rule = LdtkLevelNode_CollisionRule(ln, layer.identifier, v)
					}
					if rule.type != .None {
						m := Material{rule.type, rule.friction, rule.restitution, v if rule.type == .Trigger else -1, layer.identifier}
						for existing, mi in mats do if existing == m {k = mi; break}
						if k < 0 {
							append(&mats, m)
							k = len(mats) - 1
						}
					}
					keyOf[v] = k
				}
				keys[i] = k
			}
			if len(mats) == 0 do continue
			ln.solidLayerName = layer.identifier
			g := f32(layer.gridSize)
			for r in ldtk_merge_cells(keys, layer.cWid, layer.cHei) {
				m := mats[r.key]
				size := [2]f32{f32(r.x1 - r.x0) * g, f32(r.y1 - r.y0) * g}
				center := off + layer.offset + [2]f32{f32(r.x0) * g, f32(r.y0) * g} + size * 0.5
				shape := MakeBoxPhysicsShape(size.x, size.y, center, 0)
				shape.friction = m.friction
				shape.restitution = m.restitution
				switch m.type {
				case .None:
				case .Solid:
					if ln.staticBody == nil {
						// A transient child at the origin: physics follows the level node.
						ln.staticBody = StaticBodyNode_Create(scene, fmt.tprintf("%s_Colliders", ln.name), ln)
						ln.staticBody.position = {0, 0}
						ln.staticBody.transient = true
						ln.staticBody.gameContext = gc
					}
					StaticBodyNode_AddShape(ln.staticBody, shape, gc)
				case .OneWay:
					if ln.oneWayBody == nil {
						ln.oneWayBody = StaticBodyNode_Create(scene, fmt.tprintf("%s_OneWay", ln.name), ln)
						ln.oneWayBody.position = {0, 0}
						ln.oneWayBody.transient = true
						ln.oneWayBody.gameContext = gc
						ln.oneWayBody.oneWay = true // jump-through (physics_extras.odin)
					}
					StaticBodyNode_AddShape(ln.oneWayBody, shape, gc)
				case .Trigger:
					area := ldtk_trigger_area(ln, scene, gc, m.layer, m.value)
					AreaNode_AddShape(area, shape, gc)
				}
			}
		}
	}
}

// ldtk_trigger_area: the AreaNode for an IntGrid value ("<Layer>_<name>").
@(private = "file")
ldtk_trigger_area :: proc(ln: ^LdtkLevelNode, scene: ^Scene, gc: ^GameContext, layer: string, value: int) -> ^AreaNode {
	name := Ldtk_TriggerName(ln, layer, value)
	for a in ln.triggers do if a.name == name do return a
	area := AreaNode_Create(scene, strings.clone(name, context.temp_allocator), ln)
	area.name = strings.clone(name, area.allocator)
	area.position = {0, 0}
	area.transient = true
	area.gameContext = gc
	append(&ln.triggers, area)
	return area
}

// Ldtk_TriggerName: "<Layer>_<value identifier>" (or the value number).
Ldtk_TriggerName :: proc(ln: ^LdtkLevelNode, layer: string, value: int, allocator := context.temp_allocator) -> string {
	if ln.project != nil {
		if def := Ldtk_GetLayerDefByName(ln.project, layer); def != nil {
			for v in def.intGridValues do if v.value == value && v.identifier != "" do return fmt.aprintf("%s_%s", layer, v.identifier, allocator = allocator)
		}
	}
	return fmt.aprintf("%s_%d", layer, value, allocator = allocator)
}

// Builds Box2D static collision bodies for the given IntGrid values of one
// layer (explicit setup; replaces the automatic build).
LdtkLevelNode_BuildCollisionBodies :: proc(
	node: ^LdtkLevelNode,
	layerName: string = "Collisions",
	solidValues: []int = {1},
	ctx: ^GameContext = nil,
) {
	if node == nil || node.level == nil do return
	if len(node.activeLevels) == 0 do LdtkLevelNode_RefreshActiveLevels(node)
	node.built = true // explicit calls replace the automatic build on ready
	LdtkLevelNode_BuildColliders(node, ctx, layerName, solidValues)
}

// ----------------------------------------------------------------------------
// Entities
// ----------------------------------------------------------------------------

LdtkSpawnMode_Name :: proc(m: LdtkSpawnMode) -> string {
	switch m {
	case .Auto:      return "auto"
	case .Component: return "component"
	case .Node:      return "node"
	case .None:      return "none"
	case .CustomNode: return "custom_node"
	}
	return "auto"
}

LdtkSpawnMode_Parse :: proc(s: string) -> LdtkSpawnMode {
	switch s {
	case "component": return .Component
	case "node":      return .Node
	case "none":      return .None
	case "custom_node": return .CustomNode
	}
	return .Auto
}

LdtkLevelNode_EntityMapping :: proc(ln: ^LdtkLevelNode, identifier: string) -> LdtkEntityMapping {
	for m in ln.entityMappings do if m.entity == identifier do return m
	return {entity = identifier, mode = .Auto}
}

LdtkLevelNode_SetEntityMapping :: proc(ln: ^LdtkLevelNode, m: LdtkEntityMapping) {
	for &existing in ln.entityMappings {
		if existing.entity == m.entity {
			existing.mode = m.mode
			existing.component = strings.clone(m.component, ln.allocator)
			existing.nodeType = strings.clone(m.nodeType, ln.allocator)
			return
		}
	}
	append(&ln.entityMappings, LdtkEntityMapping{strings.clone(m.entity, ln.allocator), m.mode, strings.clone(m.component, ln.allocator), strings.clone(m.nodeType, ln.allocator)})
}

// LdtkLevelNode_EntityCustomType: the custom node type an entity spawns as
// (nil = none): its mapping's, or with matchCustomNodes an Auto one's type
// named like the entity (when no component of that name exists).
LdtkLevelNode_EntityCustomType :: proc(ln: ^LdtkLevelNode, identifier: string, ctx: ^GameContext) -> ^CustomNodeType {
	m := LdtkLevelNode_EntityMapping(ln, identifier)
	#partial switch m.mode {
	case .CustomNode:
		if m.nodeType == "" do return nil
		t, _ := CustomNode_Get(ctx, m.nodeType)
		return t
	case .Auto:
		if !ln.matchCustomNodes || LdtkLevelNode_EntityComponent(ln, identifier, ctx) != "" do return nil
		return CustomNode_FindByName(ctx, identifier)
	}
	return nil
}

// LdtkLevelNode_EntityComponent: the component an entity spawns as ("" = none).
LdtkLevelNode_EntityComponent :: proc(ln: ^LdtkLevelNode, identifier: string, ctx: ^GameContext) -> string {
	m := LdtkLevelNode_EntityMapping(ln, identifier)
	#partial switch m.mode {
	case .Component: return m.component
	case .Auto:
		path := fmt.tprintf("components/%s.component.json", identifier)
		if _, ok := Component_ReadFile(ctx, path); ok do return path
	}
	return ""
}

// Ldtk_FieldToScriptValue converts an LDtk field to a script property value.
Ldtk_FieldToScriptValue :: proc(f: ^LdtkFieldInstance, gridSize: f32) -> (ScriptValue, bool) {
	if f.isNull || f.isArray do return {}, false
	t := f.typeName
	switch {
	case t == "Int": return ScriptValue{type = .Int, valInt = i64(f.valueInt)}, true
	case t == "Float": return ScriptValue{type = .Float, valFloat = f.valueFloat}, true
	case t == "Bool": return ScriptValue{type = .Boolean, valBool = f.valueBool}, true
	case t == "Color":
		c := f.valueColor
		return ScriptValue{type = .Color, valColor = {f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, f32(c.a) / 255}}, true
	case t == "Point":
		return ScriptValue{type = .Vector2, valVec2 = f.valuePoint * gridSize + gridSize * 0.5}, true
	}
	return ScriptValue{type = .String, valString = f.valueString}, true
}

// ldtk_entity_grid_size: grid size of the layer holding `entity` (Point
// fields are in grid cells).
@(private = "file")
ldtk_entity_grid_size :: proc(ln: ^LdtkLevelNode, entity: ^LdtkEntityInstance) -> f32 {
	for lvl in ln.activeLevels {
		for &layer in lvl.layers do if layer.iid == entity.layerIid && layer.gridSize > 0 do return f32(layer.gridSize)
	}
	return 16
}

// LdtkLevelNode_DefaultSpawner spawns per the entity mapping (Auto: the
// component components/<Identifier>.component.json, else a plain Node).
LdtkLevelNode_DefaultSpawner :: proc(levelNode: ^LdtkLevelNode, entity: ^LdtkEntityInstance, scene: ^Scene, ctx: ^GameContext) -> ^Node {
	ln := levelNode
	m := LdtkLevelNode_EntityMapping(ln, entity.identifier)
	if m.mode == .None do return nil
	node: ^Node
	if t := LdtkLevelNode_EntityCustomType(ln, entity.identifier, ctx); t != nil {
		node = Scene_CreateCustomNode(scene, t, ln, ctx)
		if node == nil do log.warnf("[LDtk] %s: a %s could not be created", entity.identifier, t.name)
	} else if compPath := LdtkLevelNode_EntityComponent(ln, entity.identifier, ctx); compPath != "" {
		node = Scene_InstantiateComponent(scene, compPath, ln, ctx)
		if node == nil do log.warnf("[LDtk] %s: component %s could not be instantiated", entity.identifier, compPath)
	}
	if node == nil do node = Node_CreateByTypeName(scene, "Node", ln)
	node.name = strings.clone(entity.identifier, node.allocator)
	node.position = ln.spawnOffset + entity.px
	node.gameContext = ctx
	// LDtk fields -> script properties of the same name.
	if node.scriptInstance != nil {
		inst := cast(^ScriptInstance)node.scriptInstance
		for &f in entity.fields {
			if _, declared := inst.properties[f.identifier]; !declared do continue
			if v, ok := Ldtk_FieldToScriptValue(&f, ldtk_entity_grid_size(ln, entity)); ok {
				cur := inst.properties[f.identifier]
				if cur.type == .Float && v.type == .Int do v = ScriptValue{type = .Float, valFloat = f32(v.valInt)}
				ScriptInstance_SetProperty(inst, f.identifier, v, ctx.scriptManager if ctx != nil else nil)
			}
		}
	}
	return node
}

LdtkLevelNode_SpawnEntities :: proc(node: ^LdtkLevelNode, ctx: ^GameContext = nil) {
	if node == nil || node.level == nil do return
	scene := ldtk_scene(node, ctx)
	if scene == nil do return
	if len(node.activeLevels) == 0 do LdtkLevelNode_RefreshActiveLevels(node)
	node.built = true
	spawner: LdtkEntitySpawner = node.entitySpawner if node.entitySpawner != nil else LdtkEntitySpawner(LdtkLevelNode_DefaultSpawner)
	for lvl in node.activeLevels {
		node.spawnOffset = LdtkLevelNode_LevelOffset(node, lvl)
		for &layer in lvl.layers {
			for &ent in layer.entities {
				spawned := spawner(node, &ent, scene, ctx)
				if spawned == nil do continue
				spawned.transient = true
				append(&node.spawnedEntities, spawned)
				node.spawnedByIid[strings.clone(ent.iid, node.allocator)] = spawned
				node.entityOfNode[spawned] = &ent
				node.onEntitySpawned->notify(node, spawned, ctx)
			}
		}
	}
	node.spawnOffset = {}
}

// ----------------------------------------------------------------------------
// Entity links (EntityRef fields)
// ----------------------------------------------------------------------------

LdtkLinkAction_Name :: proc(a: LdtkLinkAction) -> string {
	switch a {
	case .Signal:               return "signal"
	case .ParentTargetToSource: return "parent_target"
	case .ParentSourceToTarget: return "parent_source"
	}
	return "signal"
}

LdtkLinkAction_Parse :: proc(s: string) -> LdtkLinkAction {
	switch s {
	case "parent_target": return .ParentTargetToSource
	case "parent_source": return .ParentSourceToTarget
	}
	return .Signal
}

// LdtkLevelNode_ResolveLinks records every EntityRef between spawned
// entities and applies the link rules.
LdtkLevelNode_ResolveLinks :: proc(ln: ^LdtkLevelNode) {
	clear(&ln.links)
	scene := ldtk_scene(ln, nil)
	for src in ln.spawnedEntities {
		ent := ln.entityOfNode[src]
		if ent == nil do continue
		for r in Ldtk_EntityRefs(ent) {
			target := ln.spawnedByIid[r.ref.entityIid]
			append(&ln.links, Ldtk_Link{src, target, ent.iid, r.ref.entityIid, r.field, r.index})
			if target == nil || scene == nil do continue
			for rule in ln.linkRules {
				if rule.entity != ent.identifier || rule.field != r.field do continue
				switch rule.action {
				case .Signal:
					if rule.signal == "" || rule.method == "" do continue
					// Direct: spawned entities often share a name.
					Node_AddDirectConnection(src, rule.signal, target, rule.method)
				case .ParentTargetToSource:
					ldtk_reparent(scene.manager, target, src)
				case .ParentSourceToTarget:
					ldtk_reparent(scene.manager, src, target)
				}
			}
		}
	}
}

// ldtk_reparent moves a spawned entity under another keeping its place
// (both start as children of the level node).
@(private = "file")
ldtk_reparent :: proc(mgr: ^NodeManager, child, parent: ^Node) {
	if child == parent || GetParent(mgr, child) == parent do return
	// Don't create a cycle.
	for p := GetParent(mgr, parent); p != nil; p = GetParent(mgr, p) do if p == child do return
	world := child.position
	for p := GetParent(mgr, child); p != nil && p.typeId != LdtkLevelNode; p = GetParent(mgr, p) do world += p.position
	base := parent.position
	for p := GetParent(mgr, parent); p != nil && p.typeId != LdtkLevelNode; p = GetParent(mgr, p) do base += p.position
	AddChild(mgr, parent, child)
	child.position = world - base
}

// LdtkLevelNode_LevelNodeOf: the level node that spawned `node` (and its entity).
LdtkLevelNode_LevelNodeOf :: proc(node: ^Node) -> (^LdtkLevelNode, ^LdtkEntityInstance) {
	if node == nil || node.gameContext == nil || node.gameContext.scene == nil do return nil, nil
	mgr := node.gameContext.scene.manager
	for p := GetParent(mgr, node); p != nil; p = GetParent(mgr, p) {
		if p.typeId != LdtkLevelNode do continue
		ln := cast(^LdtkLevelNode)p
		if ent, ok := ln.entityOfNode[node]; ok do return ln, ent
	}
	// Reparented by a link rule: search every level node.
	for n in mgr.nodes {
		if n == nil || n.typeId != LdtkLevelNode do continue
		ln := cast(^LdtkLevelNode)n
		if ent, ok := ln.entityOfNode[node]; ok do return ln, ent
	}
	return nil, nil
}

// ----------------------------------------------------------------------------
// Update & render
// ----------------------------------------------------------------------------

// LdtkLevelNode_CheckForChanges reloads the level when the .ldtk file was
// saved in LDtk (polled at most twice a second).
LdtkLevelNode_CheckForChanges :: proc(ln: ^LdtkLevelNode, force := false) -> bool {
	if ln.projectPath == "" do return false
	if !force && time.tick_since(ln.lastFileCheck) < 500 * time.Millisecond do return false
	ln.lastFileCheck = time.tick_now()
	info, err := os.stat(ln.projectPath, context.temp_allocator)
	if err != nil || time.diff(ln.fileModTime, info.modification_time) <= 0 do return false
	path := strings.clone(ln.projectPath, context.temp_allocator)
	level := strings.clone(ln.levelIdentifier, context.temp_allocator)
	LdtkLevelNode_SetProject(ln, path, level)
	log.infof("[LDtk] Reloaded %s", path)
	return true
}

LdtkLevelNode_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	ln := cast(^LdtkLevelNode)node
	if !ln.enabled do return
	if ctx != nil && ctx.game != nil && ctx.game.scriptManager.hotReload do LdtkLevelNode_CheckForChanges(ln)

	// level_loaded once the spawned entities (and their scripts) are ready.
	if ln.pendingLoaded && ln.level != nil {
		for n in ln.spawnedEntities do if Node_IsAlive(n) && !n.isReady do return
		ln.pendingLoaded = false
		ln.onLevelLoaded->notify(ln, ln.level.identifier, ctx)
	}
}

// LdtkLevelNode_LayerVisible: drawn? (LDtk visibility, the editor's
// overrides and solo).
LdtkLevelNode_LayerVisible :: proc(ln: ^LdtkLevelNode, layer: ^LdtkLayerInstance) -> bool {
	if ln.editorPreview {
		if ln.editorSoloLayer != "" do return layer.identifier == ln.editorSoloLayer
		if v, ok := ln.layerVisibility[layer.identifier]; ok do return v
	}
	return layer.visible
}

// Ldtk_ParallaxTransform: where a layer is drawn (offset added to the
// level's origin, and scale) for a camera at `camLevel` (level pixels) -
// LDtk's own formula.
Ldtk_ParallaxTransform :: proc(layer: ^LdtkLayerInstance, camLevel: [2]f32) -> (offset: [2]f32, scale: f32) {
	f := layer.parallax
	scale = 1
	if f == {0, 0} do return
	offset = camLevel * f
	if layer.parallaxScaling {
		if f.x != 0 do scale = max(0.01, 1 - f.x)
	} else {
		size := [2]f32{f32(layer.cWid * layer.gridSize), f32(layer.cHei * layer.gridSize)}
		offset -= size * 0.5 * f
	}
	return
}

// ldtk_parallax_camera: the camera centre parallax follows (the editor's
// view, else the game camera) and whether parallax applies.
@(private = "file")
ldtk_parallax_camera :: proc(ln: ^LdtkLevelNode, ctx: ^GameContext) -> (cam: [2]f32, has: bool) {
	if ln.editorPreview {
		cam, has = ln.editorCamera, ln.editorParallax
	} else if ctx != nil && ctx.camera != nil {
		cam, has = ctx.camera.currentPosition, true
	}
	return cam, has && ln.parallax
}

// ldtk_layer_place: where a layer draws (its origin and scale, parallax
// included).
@(private = "file")
ldtk_layer_place :: proc(base, scale: [2]f32, layer: ^LdtkLayerInstance, camLevel: [2]f32, hasCam: bool) -> (origin, layerScale: [2]f32) {
	pOff, pScale := [2]f32{}, f32(1)
	if hasCam do pOff, pScale = Ldtk_ParallaxTransform(layer, camLevel)
	return base + (pOff + layer.offset * pScale) * scale, scale * pScale
}

@(private = "file")
ldtk_layer_tileset :: proc(ln: ^LdtkLevelNode, layer: ^LdtkLayerInstance) -> ^LdtkTilesetDef {
	ts := Ldtk_GetTilesetByUid(ln.project, layer.tilesetDefUid)
	if ts == nil && len(layer.tilesetRelPath) > 0 do ts = Ldtk_GetTilesetByRelPath(ln.project, layer.tilesetRelPath)
	return ts
}

// ldtk_draw_tiles draws tiles in view; `skip` leaves out tiles whose
// chunk is drawn from the cache.
@(private = "file")
// ldtk_draw_tiles draws tiles (animated ones at their current frame);
// `skip`: chunks drawn from the cache; `onlyAnimated`: just the animated
// tiles (over cached chunks, which leave them out).
ldtk_draw_tiles :: proc(tiles: []LdtkTileInstance, ts: ^LdtkTilesetDef, origin, scale: [2]f32, opacity: f32, tint: rl.Color, skip: map[[2]i32]bool = nil, onlyAnimated := false) {
	tex := ts.texture
	animated := len(ts.anims) > 0
	if onlyAnimated && !animated do return
	now := rl.GetTime()
	for t in tiles {
		if t.alpha <= 0.001 do continue
		anim, isAnim := animated ? ts.anims[t.tileId] : Ldtk_TileAnim{}, animated && t.tileId in ts.anims
		if onlyAnimated && !isAnim do continue
		if skip != nil {
			c := [2]i32{i32(t.px.x) / TILE_CHUNK_PX, i32(t.px.y) / TILE_CHUNK_PX}
			// cached chunks: everything but animated tiles is in the cache
			if (c in skip) != onlyAnimated do continue
		}
		dest := rl.Rectangle{origin.x + t.px.x * scale.x, origin.y + t.px.y * scale.y, t.size.x * scale.x, t.size.y * scale.y}
		if !Render_IsVisible({min(dest.x, dest.x + dest.width), min(dest.y, dest.y + dest.height), abs(dest.width), abs(dest.height)}) do continue
		src := rl.Rectangle{t.src.x, t.src.y, t.size.x, t.size.y}
		if isAnim {
			p := Ldtk_TilesetTileSrc(ts, int(Ldtk_TileAnimFrame(anim, now)))
			src.x, src.y = p.x, p.y
		}
		if t.flipX do src.width = -src.width
		if t.flipY do src.height = -src.height
		Lit_Draw(tex, src, dest, {0, 0}, 0, rl.ColorAlpha(tint, opacity * t.alpha))
	}
}

// ldtk_layer_chunks: the layer's chunk grid (its cells, plus a tile's worth
// for tiles hanging over the edge).
@(private = "file")
ldtk_layer_chunks :: proc(layer: ^LdtkLayerInstance) -> [2]int {
	w := (layer.cWid + 1) * layer.gridSize
	h := (layer.cHei + 1) * layer.gridSize
	return {(w + TILE_CHUNK_PX - 1) / TILE_CHUNK_PX, (h + TILE_CHUNK_PX - 1) / TILE_CHUNK_PX}
}

// ldtk_visible_chunks: the layer's chunks in view (ok = false: draw tiles).
@(private = "file")
ldtk_visible_chunks :: proc(layer: ^LdtkLayerInstance, origin, scale: [2]f32, view: rl.Rectangle, hasView: bool) -> (c0, c1: [2]int, ok: bool) {
	n := ldtk_layer_chunks(layer)
	c0, c1 = {0, 0}, n
	if scale.x <= 0 || scale.y <= 0 do return c0, c1, false
	if hasView {
		cp := f32(TILE_CHUNK_PX)
		c0.x = clamp(int(math.floor((view.x - origin.x) / scale.x / cp)), 0, n.x)
		c0.y = clamp(int(math.floor((view.y - origin.y) / scale.y / cp)), 0, n.y)
		c1.x = clamp(int(math.ceil((view.x + view.width - origin.x) / scale.x / cp)), 0, n.x)
		c1.y = clamp(int(math.ceil((view.y + view.height - origin.y) / scale.y / cp)), 0, n.y)
	}
	return c0, c1, true
}

@(private = "file")
Ldtk_Chunk_Build :: struct {
	layer: ^LdtkLayerInstance,
	ts:    ^LdtkTilesetDef,
}

@(private = "file")
ldtk_build_chunk :: proc(data: rawptr, key: Tile_Chunk_Key) {
	b := cast(^Ldtk_Chunk_Build)data
	cp := f32(TILE_CHUNK_PX)
	area := rl.Rectangle{f32(key.cx) * cp, f32(key.cy) * cp, cp, cp}
	for list in ([2][]LdtkTileInstance{b.layer.autoLayerTiles[:], b.layer.gridTiles[:]}) {
		for t in list {
			if t.alpha <= 0.001 do continue
			if t.tileId in b.ts.anims do continue // drawn every frame
			r := rl.Rectangle{t.px.x, t.px.y, t.size.x, t.size.y}
			if !(r.x < area.x + area.width && area.x < r.x + r.width && r.y < area.y + area.height && area.y < r.y + r.height) do continue
			src := rl.Rectangle{t.src.x, t.src.y, t.size.x, t.size.y}
			if t.flipX do src.width = -src.width
			if t.flipY do src.height = -src.height
			Lit_Draw(b.ts.texture, src, {r.x - area.x, r.y - area.y, r.width, r.height}, {0, 0}, 0, rl.ColorAlpha(rl.WHITE, t.alpha))
		}
	}
}

// ldtk_draw_layer_cached draws a tile layer from cached chunks (and the
// tiles of chunks that aren't cached).
@(private = "file")
ldtk_draw_layer_cached :: proc(ln: ^LdtkLevelNode, layer: ^LdtkLayerInstance, ts: ^LdtkTilesetDef, origin, scale: [2]f32) {
	c0, c1, ok := ldtk_visible_chunks(layer, origin, scale, renderView.rect, renderView.active)
	if !ok {
		ldtk_draw_tiles(layer.autoLayerTiles[:], ts, origin, scale, layer.opacity, ln.tintColor)
		ldtk_draw_tiles(layer.gridTiles[:], ts, origin, scale, layer.opacity, ln.tintColor)
		return
	}
	cached := make(map[[2]i32]bool, context.temp_allocator)
	missing := false
	cp := f32(TILE_CHUNK_PX)
	TileCache_BeginDraw()
	defer if missing {
		ldtk_draw_tiles(layer.autoLayerTiles[:], ts, origin, scale, layer.opacity, ln.tintColor, cached)
		ldtk_draw_tiles(layer.gridTiles[:], ts, origin, scale, layer.opacity, ln.tintColor, cached)
	}
	// animated tiles aren't in the cached chunks: drawn every frame
	defer if len(ts.anims) > 0 {
		ldtk_draw_tiles(layer.autoLayerTiles[:], ts, origin, scale, layer.opacity, ln.tintColor, cached, true)
		ldtk_draw_tiles(layer.gridTiles[:], ts, origin, scale, layer.opacity, ln.tintColor, cached, true)
	}
	defer TileCache_EndDraw()
	for cy in c0.y ..< c1.y {
		for cx in c0.x ..< c1.x {
			key := Tile_Chunk_Key{ln, layer, ln.project.loadId, i32(cx), i32(cy)}
			dst := rl.Rectangle{origin.x + f32(cx) * cp * scale.x, origin.y + f32(cy) * cp * scale.y, cp * scale.x, cp * scale.y}
			if TileCache_Draw(key, u64(ts.texture.id), {0, 0, cp, cp}, dst, 0, ln.tintColor, layer.opacity) {
				cached[{i32(cx), i32(cy)}] = true
			} else {
				missing = true
			}
		}
	}
}

// LdtkLevelNode_PrepareChunks builds the cached chunks of its tile layers
// in view.
LdtkLevelNode_PrepareChunks :: proc(ln: ^LdtkLevelNode, view: rl.Rectangle, ctx: ^GameContext) {
	if ln.level == nil || ln.project == nil do return
	if len(ln.activeLevels) == 0 do LdtkLevelNode_RefreshActiveLevels(ln)
	scale := ln.globalScale
	cam, hasCam := ldtk_parallax_camera(ln, ctx if ctx != nil else ln.gameContext)
	for lvl in ln.activeLevels {
		base := ln.globalPosition + LdtkLevelNode_LevelOffset(ln, lvl) * scale
		camLevel := (cam - base) / [2]f32{scale.x if scale.x != 0 else 1, scale.y if scale.y != 0 else 1}
		for i := len(lvl.layers) - 1; i >= 0; i -= 1 {
			layer := &lvl.layers[i]
			if !LdtkLevelNode_LayerVisible(ln, layer) || layer.opacity <= 0.001 do continue
			if len(layer.autoLayerTiles) + len(layer.gridTiles) < TILE_CACHE_MIN_TILES do continue
			ts := ldtk_layer_tileset(ln, layer)
			if ts == nil || !ts.textureLoaded do continue
			origin, layerScale := ldtk_layer_place(base, scale, layer, camLevel, hasCam)
			c0, c1, ok := ldtk_visible_chunks(layer, origin, layerScale, view, true)
			if !ok do continue
			b := Ldtk_Chunk_Build{layer, ts}
			for cy in c0.y ..< c1.y {
				for cx in c0.x ..< c1.x {
					TileCache_Ensure({ln, layer, ln.project.loadId, i32(cx), i32(cy)}, u64(ts.texture.id), {TILE_CHUNK_PX, TILE_CHUNK_PX}, ldtk_build_chunk, &b)
				}
			}
		}
	}
}

LdtkLevelNode_Render :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	if !rl.IsWindowReady() do return
	ln := cast(^LdtkLevelNode)node
	if ln.level == nil || ln.project == nil do return
	if len(ln.activeLevels) == 0 do LdtkLevelNode_RefreshActiveLevels(ln)
	pos := ln.globalPosition
	scale := ln.globalScale
	cam, hasCam := ldtk_parallax_camera(ln, ctx)

	for lvl in ln.activeLevels {
		base := pos + LdtkLevelNode_LevelOffset(ln, lvl) * scale
		if lvl.bgColor.a > 0 {
			rl.DrawRectangleRec({base.x, base.y, f32(lvl.pxWid) * scale.x, f32(lvl.pxHei) * scale.y}, lvl.bgColor)
		}
		if ln.drawBackground && lvl.bgLoaded && lvl.bgPos.has {
			bp := lvl.bgPos
			dest := rl.Rectangle{base.x + bp.topLeft.x * scale.x, base.y + bp.topLeft.y * scale.y, bp.crop.width * bp.scale.x * scale.x, bp.crop.height * bp.scale.y * scale.y}
			Lit_Draw(lvl.bgTexture, bp.crop, dest, {0, 0}, 0, ln.tintColor)
		}
		camLevel := (cam - base) / [2]f32{scale.x if scale.x != 0 else 1, scale.y if scale.y != 0 else 1}

		// LDtk lists layers top first: draw back to front.
		for i := len(lvl.layers) - 1; i >= 0; i -= 1 {
			layer := &lvl.layers[i]
			if !LdtkLevelNode_LayerVisible(ln, layer) || layer.opacity <= 0.001 do continue
			origin, layerScale := ldtk_layer_place(base, scale, layer, camLevel, hasCam)

			if ts := ldtk_layer_tileset(ln, layer); ts != nil && ts.textureLoaded {
				if ln.material == nil && TileCache_Enabled() && !renderNormalPass && len(layer.autoLayerTiles) + len(layer.gridTiles) >= TILE_CACHE_MIN_TILES {
					ldtk_draw_layer_cached(ln, layer, ts, origin, layerScale)
				} else {
					ldtk_draw_tiles(layer.autoLayerTiles[:], ts, origin, layerScale, layer.opacity, ln.tintColor)
					ldtk_draw_tiles(layer.gridTiles[:], ts, origin, layerScale, layer.opacity, ln.tintColor)
				}
			}
			// IntGrid cells in their LDtk colours (editor view of value layers).
			if ln.editorPreview && ln.editorShowIntGrid && layer.type == .IntGrid {
				g := f32(layer.gridSize)
				for v, ci in layer.intGrid {
					if v == 0 do continue
					col := rl.Color{255, 255, 255, 255}
					if def := Ldtk_GetIntGridValueDef(ln.project, layer, v); def != nil do col = def.color
					col.a = 110 if len(layer.autoLayerTiles) > 0 else u8(170 * layer.opacity) // over auto tiles: see-through
					cx, cy := ci % layer.cWid, ci / layer.cWid
					rl.DrawRectangleRec({origin.x + f32(cx) * g * layerScale.x, origin.y + f32(cy) * g * layerScale.y, g * layerScale.x, g * layerScale.y}, col)
				}
			}
			if ln.editorPreview && ln.editorHighlight == layer.identifier {
				w := f32(layer.cWid * layer.gridSize) * layerScale.x
				h := f32(layer.cHei * layer.gridSize) * layerScale.y
				rl.DrawRectangleLinesEx({origin.x, origin.y, w, h}, 2 / max(layerScale.x, 0.01), rl.Color{92, 141, 255, 230})
			}
		}

		// Entity tiles (their LDtk editor visual) and debug overlays.
		for &layer in lvl.layers {
			if !LdtkLevelNode_LayerVisible(ln, &layer) do continue
			for &ent in layer.entities {
				r := rl.Rectangle{base.x + (ent.px.x - ent.size.x * ent.pivot.x) * scale.x, base.y + (ent.px.y - ent.size.y * ent.pivot.y) * scale.y, ent.size.x * scale.x, ent.size.y * scale.y}
				icon, outline := LdtkLevelNode_EntityVisual(ln, &ent)
				drawn := false
				if icon {
					if ts := Ldtk_GetTilesetByUid(ln.project, ent.tile.tilesetUid); ts != nil && ts.textureLoaded {
						// (its shape kept, centred in the entity's box - LDtk's Fit Inside)
						src := ent.tile.rect
						k := min(r.width / max(src.width, 1), r.height / max(src.height, 1))
						w, h := src.width * k, src.height * k
						Lit_Draw(ts.texture, src, {r.x + (r.width - w) * 0.5, r.y + (r.height - h) * 0.5, w, h}, {0, 0}, 0, ln.tintColor)
						drawn = true
					}
				}
				if outline && !drawn {
					// No icon: its box in its LDtk colour (as the Level tab shows it).
					c := ent.smartColor
					rl.DrawRectangleRec(r, {c.r, c.g, c.b, 40})
					rl.DrawRectangleLinesEx(r, 1 / max(scale.x, 0.01), {c.r, c.g, c.b, 220})
				}
				if ln.drawDebugEntities {
					rl.DrawRectangleLinesEx(r, 1, rl.Color{245, 158, 11, 200})
					rl.DrawText(strings.clone_to_cstring(ent.identifier, context.temp_allocator), i32(r.x + 2), i32(r.y + 2), 10, rl.Color{254, 240, 138, 255})
				}
			}
		}
	}
	if ln.drawDebugColliders {
		bodies := [2]^StaticBodyNode{ln.staticBody, ln.oneWayBody}
		for sb, bi in bodies {
			if sb == nil || !Node_IsAlive(sb) do continue
			col := rl.Color{74, 222, 128, 200} if bi == 0 else rl.Color{96, 165, 250, 200}
			for &shape in sb.shapes do PhysicsShape_DrawDebug(&shape, sb.globalPosition, sb.globalRotation, col, sb.globalScale)
		}
		for a in ln.triggers {
			if !Node_IsAlive(a) do continue
			for &shape in a.shapes do PhysicsShape_DrawDebug(&shape, a.globalPosition, a.globalRotation, rl.Color{236, 72, 153, 200}, a.globalScale)
		}
	}
}

LdtkLevelNode_Destroy :: proc(node: ^Node, ctx: ^GameContext) {
	ln := cast(^LdtkLevelNode)node
	TileCache_Evict(ln)
	Nav_Forget(ln)
	DestroySubject(&ln.onLevelLoaded)
	DestroySubject(&ln.onEntitySpawned)
	delete(ln.spawnedEntities)
	delete(ln.spawnedByIid)
	delete(ln.entityOfNode)
	delete(ln.links)
	delete(ln.triggers)
	delete(ln.activeLevels)
	delete(ln.collisionRules)
	delete(ln.entityMappings)
	delete(ln.linkRules)
	delete(ln.layerVisibility)
	if ln.ownsProject && ln.project != nil {
		Ldtk_DestroyProject(ln.project)
		ln.project = nil
	}
}

// ----------------------------------------------------------------------------
// Scene file: the node's "ldtk" object
// ----------------------------------------------------------------------------

// Ldtk_WriteNodeConfig writes the fields after "project" and "level".
Ldtk_WriteNodeConfig :: proc(w: ^Json_Writer, ln: ^LdtkLevelNode) {
	sb := &w.sb
	if ln.worldIdentifier != "" {
		strings.write_string(sb, ", \"world\": ")
		Json_String(w, ln.worldIdentifier)
	}
	if ln.worldMode do strings.write_string(sb, ", \"world_mode\": true")
	if len(ln.collisionRules) > 0 {
		strings.write_string(sb, ", \"collision\": [")
		for r, i in ln.collisionRules {
			if i > 0 do strings.write_string(sb, ", ")
			strings.write_string(sb, "{\"layer\": ")
			Json_String(w, r.layer)
			fmt.sbprintf(sb, ", \"value\": %d, \"type\": \"%s\", \"friction\": %g, \"restitution\": %g}", r.value, LdtkCollisionType_Name(r.type), r.friction, r.restitution)
		}
		strings.write_byte(sb, ']')
	}
	if len(ln.entityMappings) > 0 {
		strings.write_string(sb, ", \"entities\": {")
		n := 0
		for m in ln.entityMappings {
			if m.mode == .Auto do continue
			if n > 0 do strings.write_string(sb, ", ")
			n += 1
			Json_String(w, m.entity)
			fmt.sbprintf(sb, ": {{\"mode\": \"%s\"", LdtkSpawnMode_Name(m.mode))
			if m.component != "" {
				strings.write_string(sb, ", \"component\": ")
				Json_String(w, m.component)
			}
			if m.nodeType != "" {
				strings.write_string(sb, ", \"node_type\": ")
				Json_String(w, m.nodeType)
			}
			strings.write_byte(sb, '}')
		}
		strings.write_byte(sb, '}')
	}
	if len(ln.linkRules) > 0 {
		strings.write_string(sb, ", \"links\": [")
		for r, i in ln.linkRules {
			if i > 0 do strings.write_string(sb, ", ")
			strings.write_string(sb, "{\"entity\": ")
			Json_String(w, r.entity)
			strings.write_string(sb, ", \"field\": ")
			Json_String(w, r.field)
			fmt.sbprintf(sb, ", \"action\": \"%s\"", LdtkLinkAction_Name(r.action))
			if r.action == .Signal {
				strings.write_string(sb, ", \"signal\": ")
				Json_String(w, r.signal)
				strings.write_string(sb, ", \"method\": ")
				Json_String(w, r.method)
			}
			strings.write_byte(sb, '}')
		}
		strings.write_byte(sb, ']')
	}
	if len(ln.layerVisibility) > 0 {
		names := make([dynamic]string, context.temp_allocator)
		for k in ln.layerVisibility do append(&names, k)
		slice.sort(names[:])
		strings.write_string(sb, ", \"layer_visibility\": {")
		for k, i in names {
			if i > 0 do strings.write_string(sb, ", ")
			Json_String(w, k)
			strings.write_string(sb, ": true" if ln.layerVisibility[k] else ": false")
		}
		strings.write_byte(sb, '}')
	}
	if ln.collisionLayer != "Collisions" || ln.solidValues != "1" {
		if len(ln.collisionRules) == 0 {
			strings.write_string(sb, ", \"collision_layer\": ")
			Json_String(w, ln.collisionLayer)
			strings.write_string(sb, ", \"solid_values\": ")
			Json_String(w, ln.solidValues)
		}
	}
}

// Ldtk_ReadNodeConfig reads the "ldtk" object (and legacy properties) and
// loads the project.
Ldtk_ReadNodeConfig :: proc(ln: ^LdtkLevelNode, ldtkObj: json.Object, nodeObj: json.Object, projectPath: string) {
	a := ln.allocator
	// Legacy: collisionLayer / solidValues were reflected properties.
	if props, ok := nodeObj["properties"].(json.Object); ok {
		if s, isStr := props["collisionLayer"].(json.String); isStr do ln.collisionLayer = strings.clone(s, a)
		if s, isStr := props["solidValues"].(json.String); isStr do ln.solidValues = strings.clone(s, a)
	}
	if s := json_get_str(ldtkObj, "collision_layer"); s != "" do ln.collisionLayer = strings.clone(s, a)
	if s := json_get_str(ldtkObj, "solid_values"); s != "" do ln.solidValues = strings.clone(s, a)
	ln.worldIdentifier = strings.clone(json_get_str(ldtkObj, "world"), a)
	ln.worldMode = json_get_bool(ldtkObj, "world_mode")
	clear(&ln.collisionRules)
	if arr, ok := json_get_arr(ldtkObj, "collision"); ok {
		for r in arr {
			append(&ln.collisionRules, LdtkCollisionRule{
				layer = strings.clone(json_get_str(r, "layer"), a),
				value = json_get_int(r, "value"),
				type = LdtkCollisionType_Parse(json_get_str(r, "type")),
				friction = json_get_float(r, "friction", DEFAULT_LDTK_FRICTION),
				restitution = json_get_float(r, "restitution", DEFAULT_LDTK_RESTITUTION),
			})
		}
	}
	clear(&ln.entityMappings)
	if obj, ok := json_get_obj(ldtkObj, "entities"); ok {
		for name, v in obj {
			append(&ln.entityMappings, LdtkEntityMapping{strings.clone(name, a), LdtkSpawnMode_Parse(json_get_str(v, "mode")), strings.clone(json_get_str(v, "component"), a), strings.clone(json_get_str(v, "node_type"), a)})
		}
	}
	clear(&ln.linkRules)
	if arr, ok := json_get_arr(ldtkObj, "links"); ok {
		for r in arr {
			append(&ln.linkRules, LdtkLinkRule{
				entity = strings.clone(json_get_str(r, "entity"), a),
				field = strings.clone(json_get_str(r, "field"), a),
				action = LdtkLinkAction_Parse(json_get_str(r, "action")),
				signal = strings.clone(json_get_str(r, "signal"), a),
				method = strings.clone(json_get_str(r, "method"), a),
			})
		}
	}
	clear(&ln.layerVisibility)
	if obj, ok := json_get_obj(ldtkObj, "layer_visibility"); ok {
		for name, v in obj {
			if b, isBool := v.(json.Boolean); isBool do ln.layerVisibility[strings.clone(name, a)] = bool(b)
		}
	}
	ln.projectPath = strings.clone(projectPath, a) // same project: keep the saved world
	LdtkLevelNode_SetProject(ln, projectPath, json_get_str(ldtkObj, "level"))
}
