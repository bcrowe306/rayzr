package engine

import "core:c"
import "core:log"
import os "osx"
import "core:path/filepath"
import "core:strings"
import "core:time"
import lua "lua54"

// ============================================================================
// Lua hot reload
//
// Every loaded module remembers the file it came from. When that file
// changes, ScriptManager_ReloadModule recompiles it and swaps the new
// functions into the *existing* module table, which every instance uses as
// its metatable __index — so running instances pick up the new code while
// keeping their state (self.* fields and property values). Properties added
// to the script appear on instances with their defaults; removed ones go away.
// A script with a syntax or runtime error keeps running its old code.
// ============================================================================

HOT_RELOAD_INTERVAL :: 500 * time.Millisecond

// script_disk_path finds the file a module was loaded from ("" = embedded).
script_disk_path :: proc(mgr: ^ScriptManager, normPath: string) -> string {
	candidates := make([dynamic]string, context.temp_allocator)
	if mgr.game != nil && mgr.game.assetManager.projectDir != "" {
		dir := strings.trim_suffix(mgr.game.assetManager.projectDir, "/")
		rel := normPath
		if strings.has_prefix(rel, dir) && len(rel) > len(dir) && rel[len(dir)] == '/' do rel = rel[len(dir) + 1:]
		p, _ := filepath.join({dir, rel}, context.temp_allocator)
		append(&candidates, p)
	}
	append(&candidates, normPath, strings.concatenate({"assets/scripts/", normPath}, context.temp_allocator), strings.concatenate({"scripts/", normPath}, context.temp_allocator))
	for p in candidates {
		if os.is_file(p) do return p
	}
	return ""
}

@(private)
file_mtime :: proc(path: string) -> time.Time {
	if path == "" do return {}
	info, err := os.stat(path, context.temp_allocator)
	if err != nil do return {}
	return info.modification_time
}

// ScriptModule_TrackFile records where a module came from (called on load).
ScriptModule_TrackFile :: proc(mgr: ^ScriptManager, mod: ^ScriptModule) {
	if mod.diskPath != "" do delete(mod.diskPath)
	mod.diskPath = strings.clone(script_disk_path(mgr, mod.path))
	mod.modTime = file_mtime(mod.diskPath)
}

// ScriptManager_CheckForChanges reloads every module whose file changed.
// Cheap enough to call every frame; it stats files at most twice a second.
ScriptManager_CheckForChanges :: proc(mgr: ^ScriptManager, force := false) -> int {
	if mgr == nil || !mgr.isReady do return 0
	if !force && time.tick_since(mgr.lastHotReloadCheck) < HOT_RELOAD_INTERVAL do return 0
	mgr.lastHotReloadCheck = time.tick_now()
	reloaded := 0
	for path, mod in mgr.modules {
		if mod.diskPath == "" do continue
		mt := file_mtime(mod.diskPath)
		if time.diff(mod.modTime, mt) > 0 {
			mod.modTime = mt
			if ScriptManager_ReloadModule(mgr, path) do reloaded += 1
		}
	}
	reloaded += resources_check_for_changes(mgr)
	return reloaded
}

// ScriptManager_ReloadModule recompiles a module from its file and updates
// the module table and its instances in place.
ScriptManager_ReloadModule :: proc(mgr: ^ScriptManager, path: string, quiet := false) -> bool {
	mod, ok := mgr.modules[ScriptVFS_NormalizePath(path)]
	if !ok || mod.diskPath == "" do return false
	data, err := os.read_entire_file(mod.diskPath, context.temp_allocator)
	if err != nil do return false
	L := mgr.L

	chunk := strings.clone_to_cstring(strings.concatenate({"@", mod.path}, context.temp_allocator), context.temp_allocator)
	if lua.L_loadbuffer(L, cast([^]u8)raw_data(data), c.size_t(len(data)), chunk) != .OK {
		Script_Problem(.Warning, "[HotReload] %s: %s (keeping the previous version)", mod.path, lua.tostring(L, -1))
		lua.pop(L, 1)
		return false
	}
	if lua.pcall(L, 0, 1, 0) != 0 {
		Script_Problem(.Warning, "[HotReload] %s: %s (keeping the previous version)", mod.path, lua.tostring(L, -1))
		lua.pop(L, 1)
		return false
	}
	if lua.type(L, -1) != .TABLE {
		Script_Problem(.Warning, "[HotReload] %s did not return a table (keeping the previous version)", mod.path)
		lua.pop(L, 1)
		return false
	}
	newIdx := lua.gettop(L)

	key := strings.clone_to_cstring(strings.concatenate({"__Engine_Module_", mod.path}, context.temp_allocator), context.temp_allocator)
	lua.getfield(L, lua.REGISTRYINDEX, key)
	oldIdx := lua.gettop(L)
	// Clear the old table, then copy the new one into it (same table object,
	// so every instance's __index sees the new functions).
	keys := make([dynamic]c.int, context.temp_allocator)
	lua.pushnil(L)
	for lua.next(L, oldIdx) != 0 {
		lua.pop(L, 1) // value
		lua.pushvalue(L, -1)
		append(&keys, lua.L_ref(L, lua.REGISTRYINDEX)) // keep the key alive
	}
	for k in keys {
		lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(k))
		lua.pushnil(L)
		lua.rawset(L, oldIdx)
		lua.L_unref(L, lua.REGISTRYINDEX, k)
	}
	lua.pushnil(L)
	for lua.next(L, newIdx) != 0 {
		lua.pushvalue(L, -2) // key
		lua.insert(L, -2)    // key, key, value
		lua.rawset(L, oldIdx)
	}

	// New property declarations (with its base's: `extends`).
	script_extends_apply(mgr, mod, oldIdx, true)
	newProps := Script_ParseProperties(L, oldIdx)
	isClass, localCopy := script_parse_resource_marker(L, oldIdx, mod.path)
	Script_ParseBehaviorMarker(L, oldIdx, mod)
	lua.pop(L, 2) // old (now updated) table, new table
	mod.isResourceClass, mod.resourceLocalCopy = isClass, localCopy
	script_module_set_properties(mgr, mod, newProps)
	if isClass do script_warn_resource_props(mod)
	// The scripts built on this one: its new properties.
	script_extends_refresh(mgr, mod.path)
	if !quiet do log.infof("[HotReload] Reloaded %s", mod.path)
	return true
}

// script_module_set_properties replaces a module's property declarations;
// its instances get the new properties (defaults) and lose removed ones.
@(private)
script_module_set_properties :: proc(mgr: ^ScriptManager, mod: ^ScriptModule, newProps: [dynamic]ScriptProperty) {
	for &p in mod.properties do ScriptProperty_Destroy(&p)
	delete(mod.properties)
	mod.properties = newProps

	// Instances: add new properties (defaults), drop removed ones.
	for inst in mgr.instances {
		if inst.modulePath != mod.path do continue
		inst.drawState = 0 // (on_draw may have come or gone)
		for prop in mod.properties {
			if _, has := inst.properties[prop.name]; !has {
				ScriptInstance_SetProperty(inst, prop.name, prop.defaultVal, mgr)
			}
		}
		stale := make([dynamic]string, context.temp_allocator)
		for name in inst.properties {
			declared := false
			for prop in mod.properties do if prop.name == name do declared = true
			if !declared do append(&stale, name)
		}
		for name in stale {
			k, v := delete_key(&inst.properties, name)
			if v.type == .String && len(v.valString) > 0 do delete(v.valString)
			delete(k)
		}
	}
	// Resources of this class: new properties get their values.
	resources_module_reloaded(mgr, mod)
}

// --- simulation sandbox ------------------------------------------------------------
// The editor's Simulate runs scripts in the editor's Lua state. Starting a
// simulation snapshots the globals; stopping restores them and re-runs every
// module (fresh module-level locals), so nothing a simulation did leaks
// into the next one.

SIM_GLOBALS_KEY :: "__Engine_SimulationGlobals"

ScriptManager_SnapshotGlobals :: proc(mgr: ^ScriptManager) {
	if mgr == nil || mgr.L == nil do return
	L := mgr.L
	lua.newtable(L)
	snap := lua.gettop(L)
	lua.pushglobaltable(L)
	g := lua.gettop(L)
	lua.pushnil(L)
	for lua.next(L, g) != 0 {
		lua.pushvalue(L, -2) // key
		lua.insert(L, -2)    // key, key, value
		lua.rawset(L, snap)
	}
	lua.pop(L, 1) // _G
	lua.setfield(L, lua.REGISTRYINDEX, SIM_GLOBALS_KEY)
}

// ScriptManager_RestoreGlobals undoes global changes since the snapshot and
// reloads all modules from their files. Returns false without a snapshot.
ScriptManager_RestoreGlobals :: proc(mgr: ^ScriptManager) -> bool {
	if mgr == nil || mgr.L == nil do return false
	L := mgr.L
	lua.getfield(L, lua.REGISTRYINDEX, SIM_GLOBALS_KEY)
	if lua.type(L, -1) != .TABLE {
		lua.pop(L, 1)
		return false
	}
	snap := lua.gettop(L)
	lua.pushglobaltable(L)
	g := lua.gettop(L)
	// Remove globals created since the snapshot.
	added := make([dynamic]c.int, context.temp_allocator)
	lua.pushnil(L)
	for lua.next(L, g) != 0 {
		lua.pop(L, 1) // value
		lua.pushvalue(L, -1)
		lua.rawget(L, snap)
		isNew := lua.type(L, -1) == .NIL
		lua.pop(L, 1)
		if isNew {
			lua.pushvalue(L, -1)
			append(&added, lua.L_ref(L, lua.REGISTRYINDEX))
		}
	}
	for ref in added {
		lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(ref))
		lua.pushnil(L)
		lua.rawset(L, g)
		lua.L_unref(L, lua.REGISTRYINDEX, ref)
	}
	// Put changed ones back.
	lua.pushnil(L)
	for lua.next(L, snap) != 0 {
		lua.pushvalue(L, -2)
		lua.insert(L, -2)
		lua.rawset(L, g)
	}
	lua.pop(L, 2) // _G, snapshot
	lua.pushnil(L)
	lua.setfield(L, lua.REGISTRYINDEX, SIM_GLOBALS_KEY)
	// Resources the simulation loaded (and changed) start over.
	Resource_ClearAll(mgr)
	// Fresh module-level state.
	paths := make([dynamic]string, context.temp_allocator)
	for path in mgr.modules do append(&paths, path)
	for path in paths do ScriptManager_ReloadModule(mgr, path, quiet = true)
	return true
}
