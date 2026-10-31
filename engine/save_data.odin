package engine

import "base:runtime"
import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:math"
import os "osx"
import "core:path/filepath"
import "core:strings"
import lua "lua54"

// ============================================================================
// Save data (Lua `Save` module): a key/value store of plain Lua values
// (nil, booleans, numbers, strings, tables of those) kept as a Lua table and
// written as JSON to the platform's user-data folder:
//   macOS    ~/Library/Application Support/<game>/<slot>.json
//   Windows  %APPDATA%\<game>\<slot>.json
//   Linux    $XDG_DATA_HOME/<game>/<slot>.json (~/.local/share/<game>/...)
// <game> is the project name; the slot is "save" unless Save.slot() picks
// another. The file is read on first use and written by Save.flush() and
// when the game quits. --user-data <dir> (or Save_SetDirectory) puts the
// files somewhere else (tests, portable builds).
// ============================================================================

@(private = "file")
SAVE_REGISTRY_KEY :: "__rayzr_save"

@(private = "file")
save: struct {
	// Heap-allocated (set from Lua callbacks as well as engine code).
	gameName: string,
	dir:      string, // "" = the platform folder
	slot:     string, // "" = "save"
}

// Save_SetGameName: the folder name under the platform user-data folder.
Save_SetGameName :: proc(name: string) {
	delete(save.gameName, Engine_HeapAllocator())
	save.gameName = strings.clone(name, Engine_HeapAllocator())
}

// Save_SetDirectory overrides where save files go ("" = platform folder).
Save_SetDirectory :: proc(dir: string) {
	delete(save.dir, Engine_HeapAllocator())
	save.dir = strings.clone(dir, Engine_HeapAllocator())
}

Save_Reset :: proc() {
	delete(save.gameName, Engine_HeapAllocator())
	delete(save.dir, Engine_HeapAllocator())
	delete(save.slot, Engine_HeapAllocator())
	save = {}
}

@(private = "file")
safe_name :: proc(name: string, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make(allocator)
	for r in strings.trim_space(name) {
		ok := (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == ' ' || r == '-' || r == '_' || r == '.'
		strings.write_rune(&sb, r if ok else '_')
	}
	s := strings.to_string(sb)
	s = strings.trim(s, ". ")
	return s if s != "" else "RayzrGame"
}

// Save_GameName: the game's name (the user-data folder's).
Save_GameName :: proc() -> string {return save.gameName}

// Save_CrashDir: <user data>/crashes (crash reports: crash_report.odin).
Save_CrashDir :: proc(allocator := context.temp_allocator) -> string {
	p, _ := filepath.join({Save_UserDataDir(save.gameName), "crashes"}, allocator)
	return p
}

// Save_UserDataDir: the folder save files for `gameName` go in.
Save_UserDataDir :: proc(gameName: string, allocator := context.temp_allocator) -> string {
	if save.dir != "" do return strings.clone(save.dir, allocator)
	name := safe_name(gameName)
	base := ""
	when ODIN_OS == .Darwin {
		base, _ = filepath.join({os.get_env("HOME", context.temp_allocator), "Library", "Application Support"}, context.temp_allocator)
	} else when ODIN_OS == .Windows {
		base = os.get_env("APPDATA", context.temp_allocator)
		if base == "" do base, _ = filepath.join({os.get_env("USERPROFILE", context.temp_allocator), "AppData", "Roaming"}, context.temp_allocator)
	} else {
		base = os.get_env("XDG_DATA_HOME", context.temp_allocator)
		if base == "" do base, _ = filepath.join({os.get_env("HOME", context.temp_allocator), ".local", "share"}, context.temp_allocator)
	}
	dir, _ := filepath.join({base, name}, allocator)
	return dir
}

// Save_GameDataDir: the game's save-data folder.
Save_GameDataDir :: proc(allocator := context.temp_allocator) -> string {return Save_UserDataDir(save.gameName, allocator)}

// Save_FilePath: the current slot's file.
Save_FilePath :: proc(allocator := context.temp_allocator) -> string {
	slot := save.slot if save.slot != "" else "save"
	p, _ := filepath.join({Save_UserDataDir(save.gameName), strings.concatenate({safe_name(slot), ".json"}, context.temp_allocator)}, allocator)
	return p
}

// --- JSON <-> Lua ------------------------------------------------------------------

// Lua_PushJSONText pushes a JSON text as a Lua value (nil if it doesn't parse).
Lua_PushJSONText :: proc(L: ^lua.State, text: string) {
	v, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None {
		lua.pushnil(L)
		return
	}
	push_json(L, v)
}

// lua_to_json: the Lua value at `idx` as JSON text (temp).
lua_to_json :: proc(L: ^lua.State, idx: c.int) -> string {
	sb := strings.builder_make(context.temp_allocator)
	write_lua(L, lua.absindex(L, idx), &sb, 0, "")
	return strings.to_string(sb)
}

@(private = "file")
push_json :: proc(L: ^lua.State, v: json.Value) {
	switch x in v {
	case json.Null:    lua.pushnil(L)
	case json.Integer: lua.pushinteger(L, lua.Integer(x))
	case json.Float:   lua.pushnumber(L, lua.Number(x))
	case json.Boolean: lua.pushboolean(L, b32(x))
	case json.String:  lua.pushstring(L, strings.clone_to_cstring(x, context.temp_allocator))
	case json.Array:
		lua.createtable(L, c.int(len(x)), 0)
		for e, i in x {
			push_json(L, e)
			lua.rawseti(L, -2, lua.Integer(i + 1))
		}
	case json.Object:
		lua.createtable(L, 0, c.int(len(x)))
		for k, e in x {
			push_json(L, e)
			lua.setfield(L, -2, strings.clone_to_cstring(k, context.temp_allocator))
		}
	}
}

// write_lua writes the value at `idx` as JSON; functions, userdata and
// threads are written as null (with a warning), as are cycles past depth 64.
@(private = "file")
write_lua :: proc(L: ^lua.State, idx: c.int, sb: ^strings.Builder, depth: int, path: string) {
	idx := lua.absindex(L, idx)
	#partial switch lua.type(L, idx) {
	case .NIL:
		strings.write_string(sb, "null")
	case .BOOLEAN:
		strings.write_string(sb, "true" if lua.toboolean(L, idx) else "false")
	case .NUMBER:
		if lua.isinteger(L, idx) {
			fmt.sbprintf(sb, "%d", i64(lua.tointeger(L, idx)))
		} else {
			f := f64(lua.tonumber(L, idx))
			if math.is_nan(f) || math.is_inf(f) do strings.write_string(sb, "null")
			else {
				s := fmt.tprintf("%.17g", f)
				strings.write_string(sb, s)
				// Keep it a float when read back.
				if !strings.contains_any(s, ".eE") do strings.write_string(sb, ".0")
			}
		}
	case .STRING:
		w := Json_Writer{sb = sb^}
		Json_String(&w, string(lua.tostring(L, idx)))
		sb^ = w.sb
	case .TABLE:
		if depth > 64 {
			log.warnf("[Save] %s: nested too deep (a cycle?), written as null", path)
			strings.write_string(sb, "null")
			return
		}
		// An array when the keys are exactly 1..n (n > 0).
		n := int(lua.rawlen(L, idx))
		count := 0
		lua.pushnil(L)
		for lua.next(L, idx) != 0 {
			count += 1
			lua.pop(L, 1)
		}
		if n > 0 && count == n {
			strings.write_byte(sb, '[')
			for i in 1 ..= n {
				if i > 1 do strings.write_string(sb, ", ")
				lua.rawgeti(L, idx, lua.Integer(i))
				write_lua(L, -1, sb, depth + 1, path)
				lua.pop(L, 1)
			}
			strings.write_byte(sb, ']')
			return
		}
		strings.write_byte(sb, '{')
		first := true
		lua.pushnil(L)
		for lua.next(L, idx) != 0 {
			// Key: strings as is, numbers as their text (others skipped).
			key := ""
			#partial switch lua.type(L, -2) {
			case .STRING: key = strings.clone(string(lua.tostring(L, -2)), context.temp_allocator)
			case .NUMBER:
				if lua.isinteger(L, -2) do key = fmt.tprintf("%d", i64(lua.tointeger(L, -2)))
				else do key = fmt.tprintf("%g", f64(lua.tonumber(L, -2)))
			}
			if key != "" {
				if !first do strings.write_string(sb, ", ")
				first = false
				w := Json_Writer{sb = sb^}
				Json_String(&w, key)
				sb^ = w.sb
				strings.write_string(sb, ": ")
				write_lua(L, -1, sb, depth + 1, key)
			}
			lua.pop(L, 1)
		}
		strings.write_byte(sb, '}')
	case:
		log.warnf("[Save] %s: a %s can't be saved (written as null)", path, lua.typename(L, lua.type(L, idx)))
		strings.write_string(sb, "null")
	}
}

// --- the data table ------------------------------------------------------------------

// push_data pushes the slot's data table, reading the file the first time.
@(private = "file")
push_data :: proc(L: ^lua.State) {
	lua.getfield(L, lua.REGISTRYINDEX, SAVE_REGISTRY_KEY)
	if lua.type(L, -1) == .TABLE do return
	lua.pop(L, 1)
	loaded := false
	path := Save_FilePath()
	if data, err := os.read_entire_file(path, context.temp_allocator); err == nil {
		if v, perr := json.parse(data, parse_integers = true, allocator = context.temp_allocator); perr == nil {
			if _, isObj := v.(json.Object); isObj {
				push_json(L, v)
				loaded = true
			}
		} else {
			log.warnf("[Save] %s is not valid JSON (%v); starting empty", path, perr)
		}
	}
	if !loaded do lua.newtable(L)
	lua.pushvalue(L, -1)
	lua.setfield(L, lua.REGISTRYINDEX, SAVE_REGISTRY_KEY)
}

// Save_Flush writes the slot's data (when it has been used) to its file.
Save_Flush :: proc(L: ^lua.State) -> bool {
	if L == nil do return false
	lua.getfield(L, lua.REGISTRYINDEX, SAVE_REGISTRY_KEY)
	defer lua.pop(L, 1)
	if lua.type(L, -1) != .TABLE do return true // never used: nothing to write
	sb := strings.builder_make(context.temp_allocator)
	write_lua(L, -1, &sb, 0, "Save")
	strings.write_byte(&sb, '\n')
	path := Save_FilePath()
	_ = os.make_directory_all(filepath.dir(path, context.temp_allocator))
	// Written next to it, then renamed over it: a crash mid-write keeps the old file.
	tmp := strings.concatenate({path, ".tmp"}, context.temp_allocator)
	if err := os.write_entire_file(tmp, transmute([]u8)strings.to_string(sb)); err != nil {
		log.errorf("[Save] Could not write %s: %v", tmp, err)
		return false
	}
	if err := os.rename(tmp, path); err != nil {
		log.errorf("[Save] Could not replace %s: %v", path, err)
		return false
	}
	return true
}

// Save_Forget drops the in-memory data (the next use reads the file).
Save_Forget :: proc(L: ^lua.State) {
	if L == nil do return
	lua.pushnil(L)
	lua.setfield(L, lua.REGISTRYINDEX, SAVE_REGISTRY_KEY)
}

// --- Lua ---------------------------------------------------------------------------

@(private = "file")
key_arg :: proc(L: ^lua.State) -> (cstring, bool) {
	if lua.type(L, 1) != .STRING {
		lua.L_error(L, "Save: the key must be a string")
		return nil, false
	}
	return lua.tostring(L, 1), true
}

// Save.set(key, value): nil removes the key.
@(private = "file")
lua_save_set :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	key, ok := key_arg(L)
	if !ok do return 0
	lua.settop(L, 2)
	push_data(L)
	lua.pushvalue(L, 2)
	lua.setfield(L, -2, key)
	return 0
}

// Save.get(key [, default])
@(private = "file")
lua_save_get :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	key, ok := key_arg(L)
	if !ok do return 0
	lua.settop(L, 2)
	push_data(L)
	lua.getfield(L, -1, key)
	if lua.type(L, -1) == .NIL do lua.pushvalue(L, 2)
	return 1
}

@(private = "file")
lua_save_has :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	key, ok := key_arg(L)
	if !ok do return 0
	push_data(L)
	lua.getfield(L, -1, key)
	lua.pushboolean(L, b32(lua.type(L, -1) != .NIL))
	return 1
}

@(private = "file")
lua_save_delete :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	key, ok := key_arg(L)
	if !ok do return 0
	push_data(L)
	lua.pushnil(L)
	lua.setfield(L, -2, key)
	return 0
}

// Save.keys() -> sorted array of keys
@(private = "file")
lua_save_keys :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	push_data(L)
	data := lua.gettop(L)
	keys := make([dynamic]string, context.temp_allocator)
	lua.pushnil(L)
	for lua.next(L, data) != 0 {
		if lua.type(L, -2) == .STRING do append(&keys, strings.clone(string(lua.tostring(L, -2)), context.temp_allocator))
		lua.pop(L, 1)
	}
	// Sorted so scripts get a stable order.
	for i in 1 ..< len(keys) do for j := i; j > 0 && keys[j] < keys[j - 1]; j -= 1 do keys[j], keys[j - 1] = keys[j - 1], keys[j]
	lua.createtable(L, c.int(len(keys)), 0)
	for k, i in keys {
		lua.pushstring(L, strings.clone_to_cstring(k, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

// Save.clear(): removes every key (written on the next flush).
@(private = "file")
lua_save_clear :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	lua.newtable(L)
	lua.setfield(L, lua.REGISTRYINDEX, SAVE_REGISTRY_KEY)
	return 0
}

// Save.flush() -> ok
@(private = "file")
lua_save_flush :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	push_data(L) // flushing before any use writes an empty file
	lua.pop(L, 1)
	lua.pushboolean(L, b32(Save_Flush(L)))
	return 1
}

// Save.slot([name]) -> current slot. Switching writes the current slot first.
@(private = "file")
lua_save_slot :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if lua.type(L, 1) == .STRING {
		name := string(lua.tostring(L, 1))
		cur := save.slot if save.slot != "" else "save"
		if name != "" && name != cur {
			Save_Flush(L)
			Save_Forget(L)
			delete(save.slot, Engine_HeapAllocator())
			save.slot = strings.clone(name, Engine_HeapAllocator())
		}
	}
	lua.pushstring(L, strings.clone_to_cstring(save.slot if save.slot != "" else "save", context.temp_allocator))
	return 1
}

// Save.path() -> the slot's file
@(private = "file")
lua_save_path :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	lua.pushstring(L, strings.clone_to_cstring(Save_FilePath(), context.temp_allocator))
	return 1
}

// Script_RegisterSaveModule creates the global Save table.
Script_RegisterSaveModule :: proc(L: ^lua.State) {
	lua.newtable(L)
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "set", lua_save_set)
	reg(L, "get", lua_save_get)
	reg(L, "has", lua_save_has)
	reg(L, "delete", lua_save_delete)
	reg(L, "keys", lua_save_keys)
	reg(L, "clear", lua_save_clear)
	reg(L, "flush", lua_save_flush)
	reg(L, "slot", lua_save_slot)
	reg(L, "path", lua_save_path)
	lua.setglobal(L, "Save")
}
