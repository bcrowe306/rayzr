package engine

import os "osx"
import "core:strings"
import "core:testing"
import lua "lua54"

// Reads the global Lua array `events` as "a,b,c".
@(private = "file")
lua_events :: proc(game: ^Game) -> string {
	L := game.scriptManager.L
	lua.getglobal(L, "events")
	defer lua.pop(L, 1)
	if lua.type(L, -1) != .TABLE do return "<no events table>"
	sb := strings.builder_make(context.temp_allocator)
	n := int(lua.rawlen(L, -1))
	for i in 1 ..= n {
		lua.rawgeti(L, -1, lua.Integer(i))
		if i > 1 do strings.write_byte(&sb, ',')
		strings.write_string(&sb, string(lua.tostring(L, -1)))
		lua.pop(L, 1)
	}
	return strings.to_string(sb)
}

@(test)
test_lua_receives_node_events :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("event_listener.lua", `
local S = {}
S.properties = {}
function S:ready()
    events = events or {}
    table.insert(events, "ready")
end
function S:on_timeout() table.insert(events, "timeout") end
function S:on_custom(v) table.insert(events, "method:" .. tostring(v)) end
function S:on_child_added(c) table.insert(events, "child:" .. c:get_type()) end
return S
`)
	ScriptVFS_RegisterEmbedded("event_watcher.lua", `
local W = {}
W.properties = {}
function W:ready()
    events = events or {}
    local timer = self.node:get_parent()
    self.conn = timer:connect("custom", function(v, src)
        table.insert(events, "conn:" .. tostring(v) .. ":" .. src:get_name())
    end)
    timer_ref = timer
end
function W:stop_listening()
    self.node:get_parent():disconnect(self.conn)
end
return W
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("events", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	timer := cast(^TimerNode)Node_CreateByTypeName(scene, "TimerNode")
	timer.name = "Clock"
	timer->setDuration(0.05)
	timer.running = true
	timer.gameContext = &game.gameContext
	Script_AttachToNode(timer, "event_listener.lua", nil, &game.scriptManager)
	watcher := Node_CreateByTypeName(scene, "Node", timer)
	watcher.name = "Watcher"
	watcher.gameContext = &game.gameContext
	Script_AttachToNode(watcher, "event_watcher.lua", nil, &game.scriptManager)

	game->run(0.016) // ready() for both; child_added was raised before the scripts were ready
	game->run(0.05)  // timer expires
	ev := lua_events(game)
	testing.expectf(t, strings.contains(ev, "ready") && strings.contains(ev, "timeout"), "on_timeout ran: %s", ev)

	// A custom event reaches the owner's method and the connection.
	Script_DispatchEvent(timer, "custom", int(7), &game.gameContext)
	ev = lua_events(game)
	testing.expectf(t, strings.contains(ev, "method:7"), "owner method: %s", ev)
	testing.expectf(t, strings.contains(ev, "conn:7:Clock"), "connected handler with source: %s", ev)
	testing.expect_value(t, len(game.scriptManager.connections), 1)

	// child_added reaches the parent's script with the child node.
	extra := Node_CreateByTypeName(scene, "Node", timer)
	extra.name = "Extra"
	testing.expectf(t, strings.contains(lua_events(game), "child:Node"), "child_added: %s", lua_events(game))

	// Destroying the connecting script's node releases its connection; a
	// Lua reference to a destroyed node is nil, not a crash.
	RemoveNode(scene.manager, watcher)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect_value(t, len(game.scriptManager.connections), 0)
	RemoveNode(scene.manager, timer)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	L := game.scriptManager.L
	testing.expect(t, lua.L_dostring(L, "dead_name = timer_ref:get_name()") == 0, "calling a method on a destroyed node doesn't error")
	lua.getglobal(L, "dead_name")
	testing.expect(t, lua.isnil(L, -1), "destroyed node reads as nil")
	lua.pop(L, 1)
}

@(test)
test_area_and_collision_events_reach_lua :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("area_listener.lua", `
local A = {}
A.properties = {}
function A:on_body_entered(other) events = events or {}; table.insert(events, "entered:" .. (other and other:get_name() or "nil")) end
function A:on_body_exited(other) table.insert(events, "exited:" .. (other and other:get_name() or "nil")) end
return A
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("areas", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	area := cast(^AreaNode)Node_CreateByTypeName(scene, "AreaNode")
	area.gameContext = &game.gameContext
	Script_AttachToNode(area, "area_listener.lua", nil, &game.scriptManager)
	visitor := Node_CreateByTypeName(scene, "DynamicBodyNode")
	visitor.name = "Crate"
	game.state = .Running
	game->run(0.016) // scripts ready

	AreaNode_HandleEnter(area, visitor, &game.gameContext)
	testing.expect_value(t, area.overlapCount, 1)
	// The visitor is destroyed while overlapping: the area drops it and
	// reports an exit (with nil, since the node is gone).
	RemoveNode(scene.manager, visitor)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	AreaNode_Update(area, &game.gameContext, 0.016)
	testing.expect_value(t, area.overlapCount, 0)
	ev := lua_events(game)
	testing.expectf(t, ev == "entered:Crate,exited:nil", "area events: %s", ev)

	// Destroyed this frame (queued for removal): no body_entered any more -
	// neither for a body entering a destroyed area, nor a destroyed body.
	other := Node_CreateByTypeName(scene, "DynamicBodyNode")
	other.name = "Doomed"
	RemoveNode(scene.manager, other)
	AreaNode_HandleEnter(area, other, &game.gameContext)
	testing.expect_value(t, area.overlapCount, 0)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	third := Node_CreateByTypeName(scene, "DynamicBodyNode")
	third.name = "Late"
	RemoveNode(scene.manager, area)
	AreaNode_HandleEnter(area, third, &game.gameContext)
	ev = lua_events(game)
	testing.expectf(t, ev == "entered:Crate,exited:nil", "events after the removals: %s", ev)
}

// A node destroyed in the frame it was created (before it was added - e.g.
// a coin a level generator spawned, destroyed by the "generated" handler)
// never enters the tree; it used to be added anyway, cut off from its
// parent, its area still working.
@(test)
test_node_destroyed_before_added_never_enters :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("spawned", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	coin := Node_CreateByTypeName(scene, "AreaNode")
	sprite := Node_CreateByTypeName(scene, "Node", coin)
	kept := Node_CreateByTypeName(scene, "Node")
	RemoveNode(scene.manager, coin)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect(t, !Node_IsAlive(coin), "the destroyed node is gone")
	testing.expect(t, !Node_IsAlive(sprite), "its child too")
	testing.expect(t, Node_IsAlive(kept), "the other new node is in")
	testing.expect_value(t, len(scene.manager.addition), 0)
	children := GetChildrenView(scene.manager, scene.rootNode)
	testing.expect_value(t, len(children), 1)
	if len(children) == 1 do testing.expect(t, children[0] == kept)
	found := 0
	for n in scene.manager.nodes do if n == kept do found += 1
	testing.expect_value(t, found, 1)
}

@(test)
test_lua_hot_reload_updates_running_instances :: proc(t: ^testing.T) {
	dir :: "test_hot_reload"
	path :: "test_hot_reload/mover.lua"
	_ = os.make_directory_all(dir)
	defer os.remove_all(dir)
	_ = os.write_entire_file(path, transmute([]u8)string(`
local M = {}
M.properties = { speed = { type = "float", default = 1 } }
function M:ready() self.counter = 0 end
function M:update(dt) self.counter = self.counter + 1; self.node:set_position(self.speed, self.counter) end
return M
`))
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("hot", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	n := Node_CreateByTypeName(scene, "Node")
	n.gameContext = &game.gameContext
	inst := Script_AttachToNode(n, path, nil, &game.scriptManager)
	testing.expect(t, inst != nil, "attached")
	game->run(0.016)
	game->run(0.016)
	testing.expect_value(t, n.position, [2]f32{1, 2})

	// Edit the file: new update() and a new property.
	_ = os.write_entire_file(path, transmute([]u8)string(`
local M = {}
M.properties = { speed = { type = "float", default = 1 }, bonus = { type = "float", default = 100 } }
function M:ready() self.counter = 0 end
function M:update(dt) self.counter = self.counter + 1; self.node:set_position(self.speed + self.bonus, self.counter) end
return M
`))
	game.scriptManager.modules[path].modTime = {} // force "changed" (same-second writes)
	testing.expect_value(t, ScriptManager_CheckForChanges(&game.scriptManager, force = true), 1)
	game->run(0.016)
	testing.expectf(t, n.position == {101, 3}, "new code runs with old state (counter kept), got %v", n.position)
	testing.expect_value(t, inst.properties["bonus"].valFloat, f32(100))

	// A broken edit keeps the old code.
	_ = os.write_entire_file(path, transmute([]u8)string(`local M = {} function M:update( return M`))
	game.scriptManager.modules[path].modTime = {}
	testing.expect_value(t, ScriptManager_CheckForChanges(&game.scriptManager, force = true), 0)
	game->run(0.016)
	testing.expectf(t, n.position == {101, 4}, "old code still running, got %v", n.position)
}

LDTK_TEST_PROJECT :: `{
  "jsonVersion": "1.5.3", "iid": "proj", "worldLayout": "Free", "externalLevels": true,
  "defs": {
    "layers": [{"uid": 10, "identifier": "Far", "parallaxFactorX": 0.5, "parallaxFactorY": 0.25, "parallaxScaling": false}],
    "tilesets": [{"uid": 1, "identifier": "T", "relPath": "tiles.png", "pxWid": 32, "pxHei": 16, "tileGridSize": 16,
                  "customData": [{"tileId": 1, "data": "lava"}]}]
  },
  "levels": [{"identifier": "Level_0", "iid": "l0", "uid": 0, "worldX": 0, "worldY": 0, "pxWid": 64, "pxHei": 32,
              "externalRelPath": "Level_0.ldtkl",
              "fieldInstances": [{"__identifier": "music", "__type": "String", "__value": "theme.ogg"},
                                 {"__identifier": "par_time", "__type": "Float", "__value": 42.5}],
              "layerInstances": null}]
}`

LDTK_TEST_LEVEL :: `{
  "identifier": "Level_0", "iid": "l0",
  "layerInstances": [
    {"__identifier": "Entities", "__type": "Entities", "__cWid": 4, "__cHei": 2, "__gridSize": 16, "visible": true,
     "entityInstances": [
       {"__identifier": "Turret", "iid": "t1", "px": [16, 16], "__pivot": [0.5, 0.5], "width": 16, "height": 16, "__grid": [1, 1], "__tags": ["enemy"],
        "fieldInstances": [{"__identifier": "health", "__type": "Int", "__value": 250},
                           {"__identifier": "waypoints", "__type": "Array<Point>", "__value": [{"cx": 1, "cy": 0}, {"cx": 3, "cy": 1}]},
                           {"__identifier": "target", "__type": "EntityRef", "__value": {"entityIid": "d1", "layerIid": "x", "levelIid": "l0", "worldIid": "w"}}]},
       {"__identifier": "Door", "iid": "d1", "px": [48, 16], "__pivot": [0, 0], "width": 16, "height": 16, "fieldInstances": []}
     ]},
    {"__identifier": "Hidden", "__type": "Tiles", "__cWid": 4, "__cHei": 2, "__gridSize": 16, "visible": false, "layerDefUid": 10, "gridTiles": []},
    {"__identifier": "Collisions", "__type": "IntGrid", "__cWid": 4, "__cHei": 2, "__gridSize": 16, "visible": true,
     "intGridCsv": [1, 1, 0, 0, 0, 0, 2, 1]}
  ]
}`

@(test)
test_ldtk_external_levels_fields_spawning_and_lua :: proc(t: ^testing.T) {
	_ = os.make_directory_all("test_ldtk/components")
	defer os.remove_all("test_ldtk")
	_ = os.write_entire_file("test_ldtk/game.ldtk", transmute([]u8)string(LDTK_TEST_PROJECT))
	_ = os.write_entire_file("test_ldtk/Level_0.ldtkl", transmute([]u8)string(LDTK_TEST_LEVEL))
	ScriptVFS_RegisterEmbedded("turret_ai.lua", `
local T = {}
T.properties = { health = { type = "int", default = 1 } }
function T:ready() end
return T
`)
	_ = os.write_entire_file("test_ldtk/components/Turret.component.json", transmute([]u8)string(`{"type": "Node", "name": "Turret", "script": {"path": "turret_ai.lua"}}`))

	proj, ok := Ldtk_LoadProjectFromFile("test_ldtk/game.ldtk")
	testing.expect(t, ok && proj != nil, "project loads")
	if proj == nil do return
	lvl := Ldtk_GetLevel(proj, "Level_0")
	testing.expect(t, lvl != nil && len(lvl.layers) == 3, "external level's layers loaded")
	testing.expect_value(t, Ldtk_GetLevelField(lvl, "music").valueString, "theme.ogg")
	testing.expect_value(t, Ldtk_GetLevelField(lvl, "par_time").valueFloat, f32(42.5))
	turret := Ldtk_GetEntityByIid(lvl, "t1")
	wp := Ldtk_GetField(turret, "waypoints")
	testing.expect(t, wp != nil && wp.isArray && len(wp.values) == 2 && wp.values[1].valuePoint == {3, 1}, "array of points")
	testing.expect_value(t, Ldtk_GetField(turret, "target").entityRef, "d1")
	hidden := Ldtk_GetLayer(lvl, "Hidden")
	testing.expect(t, !hidden.visible && hidden.parallax == {0.5, 0.25}, "visibility and parallax")
	testing.expect_value(t, Ldtk_GetTileCustomData(proj, 1, 1), "lava")
	Ldtk_DestroyProject(proj)

	// Node in a game: ready builds colliders and spawns entities (Turret via its component,
	// LDtk "health" copied onto the script property).
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, "test_ldtk")
	scene := game->createScene("ldtk", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	ln := cast(^LdtkLevelNode)Node_CreateByTypeName(scene, "LdtkLevelNode")
	ln.gameContext = &game.gameContext
	ln.solidValues = "1,2"
	LdtkLevelNode_SetProject(ln, "test_ldtk/game.ldtk", "Level_0")
	game->run(0.016)
	testing.expect(t, ln.staticBody != nil && len(ln.staticBody.shapes) == 2, "colliders from IntGrid values 1 and 2")
	testing.expect_value(t, len(ln.spawnedEntities), 2)
	turretNode := ln.spawnedByIid["t1"]
	testing.expect(t, turretNode != nil && turretNode.componentPath == "components/Turret.component.json", "spawned as component instance")
	if turretNode != nil && turretNode.scriptInstance != nil {
		testing.expect_value(t, (cast(^ScriptInstance)turretNode.scriptInstance).properties["health"].valInt, i64(250))
	}
	// Spawned entities and colliders are not saved with the scene.
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, !strings.contains(text, "Turret") && !strings.contains(text, "_Colliders"), "transient nodes not saved")

	// Lua API.
	L := game.scriptManager.L
	ScriptVFS_RegisterEmbedded("ldtk_probe.lua", `
local P = {}
P.properties = {}
function P:ready()
    local level = self.node
    local ents = level:ldtk_get_entities("Turret")
    probe = ents[1].identifier .. ":" .. ents[1].fields.health .. ":" .. ents[1].fields.target
            .. ":" .. #ents[1].fields.waypoints .. ":" .. level:ldtk_get_level_field("music")
            .. ":" .. level:ldtk_get_int_grid("Collisions", 8, 8)
            .. ":" .. level:ldtk_get_entity_node("t1"):get_name()
end
return P
`)
	Script_AttachToNode(ln, "ldtk_probe.lua", nil, &game.scriptManager)
	game->run(0.016)
	lua.getglobal(L, "probe")
	testing.expect_value(t, string(lua.tostring(L, -1)), "Turret:250:d1:2:theme.ogg:1:Turret")
	lua.pop(L, 1)

	// Hot reload: editing the level file rebuilds.
	edited, _ := strings.replace(string(LDTK_TEST_LEVEL), `[1, 1, 0, 0, 0, 0, 2, 1]`, `[1, 1, 1, 1, 0, 0, 0, 0]`, 1, context.temp_allocator)
	_ = os.write_entire_file("test_ldtk/Level_0.ldtkl", transmute([]u8)edited)
	_ = os.write_entire_file("test_ldtk/game.ldtk", transmute([]u8)string(LDTK_TEST_PROJECT)) // project file is what's watched
	ln.fileModTime = {}
	testing.expect(t, LdtkLevelNode_CheckForChanges(ln, force = true), "reloaded")
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect(t, ln.staticBody != nil && len(ln.staticBody.shapes) == 1, "colliders rebuilt from the edited grid (one merged row)")
}

@(test)
test_saved_signal_connections_call_script_methods :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("signal_target.lua", `
local T = {}
T.properties = {}
function T:ready() events = events or {} end
function T:on_clock_timeout(value, source)
    table.insert(events, "handled:" .. source:get_name())
end
return T
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	src := game->createScene("sig_src", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)

	timer := cast(^TimerNode)Node_CreateByTypeName(src, "TimerNode")
	timer.name = "Clock"
	timer->setDuration(0.05)
	timer.running = true
	listener := Node_CreateByTypeName(src, "Node")
	listener.name = "Listener"
	listener.gameContext = &game.gameContext
	Script_AttachToNode(listener, "signal_target.lua", nil, &game.scriptManager)
	ProcessNodeQueues(src.manager, &game.gameContext)

	// Events offered by a TimerNode, and the default handler name.
	names := Node_EventNames(timer)
	hasTimeout, hasTick, hasTree := false, false, false
	for e in names {
		if e.name == "timeout" do hasTimeout = true
		if e.name == "tick" && e.param == "elapsed" do hasTick = true
		if e.name == "entered_tree" do hasTree = true
	}
	testing.expect(t, hasTimeout && hasTick && hasTree, "TimerNode events listed")
	testing.expect_value(t, Signal_HandlerName("Clock", "timeout"), "on_clock_timeout")
	testing.expect_value(t, Signal_HandlerName("PlayerShip2", "body_entered"), "on_player_ship2_body_entered")

	// Connect (relative path), save, reload into the running scene.
	path := Node_RelativePath(src.manager, timer, listener)
	testing.expect_value(t, path, "../Listener")
	testing.expect(t, Node_ResolvePath(src.manager, timer, path) == listener, "path resolves")
	Node_AddConnection(timer, "timeout", path, "on_clock_timeout")
	text := Scene_SerializeToJSON(src, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"connections": [{"signal": "timeout", "target": "../Listener", "method": "on_clock_timeout"}]`), "connection saved")

	scene := game->createScene("sig_run", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	Scene_InstantiateFromJSON(scene, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	game.state = .Running
	game->run(0.016) // scripts ready
	game->run(0.06)  // timer fires
	ev := lua_events(game)
	testing.expectf(t, strings.contains(ev, "handled:Clock"), "saved connection called the method: %s", ev)

	// Disconnect: no more calls.
	clock := Scene_FindNodeByName(scene, "Clock")
	testing.expect(t, clock != nil && Node_RemoveConnection(clock, "timeout", "../Listener", "on_clock_timeout"), "removed")
}

@(test)
test_simulation_globals_are_restored :: proc(t: ^testing.T) {
	dir :: "test_sim_globals"
	defer os.remove_all(dir)
	_ = os.make_directory_all(dir + "/scripts")
	_ = os.write_entire_file(dir + "/scripts/counter.lua", transmute([]u8)string(`
local M = {}
M.properties = {}
local count = 0
function M:update(dt)
    count = count + 1
    sim_count = count
end
return M
`))
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, dir)
	scene := game->createScene("sim", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	n := Node_CreateByTypeName(scene, "Node")
	n.gameContext = &game.gameContext
	Script_AttachToNode(n, "scripts/counter.lua", nil, &game.scriptManager)
	game.state = .Running
	L := game.scriptManager.L
	read_count :: proc(L: ^lua.State) -> int {
		lua.getglobal(L, "sim_count")
		defer lua.pop(L, 1)
		return int(lua.tointeger(L, -1)) if lua.type(L, -1) == .NUMBER else -1
	}

	ScriptManager_SnapshotGlobals(&game.scriptManager)
	for _ in 0 ..< 3 do game->run(0.016)
	testing.expect(t, read_count(L) >= 2, "simulation ran")

	testing.expect(t, ScriptManager_RestoreGlobals(&game.scriptManager), "restored")
	testing.expect_value(t, read_count(L), -1) // global created by the simulation is gone
	// Module-level locals restart: the next run counts from 1 again.
	game->run(0.016)
	testing.expect_value(t, read_count(L), 1)
}
