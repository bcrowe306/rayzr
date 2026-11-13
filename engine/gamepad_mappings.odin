package engine

import "core:fmt"
import "core:log"
import os "osx"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Gamepad mappings: which button of a controller is "A". raylib (GLFW) only
// treats a controller as a gamepad when it has a mapping for its GUID - an
// SDL_GameControllerDB line:
//
//   030000005e040000130b000001050000,Xbox Series Controller,a:b0,b:b1,...,platform:Mac OS X,
//
// Without one the controller is "connected" but every button reads up. So
// besides GLFW's own (compiled-in) mappings, the engine loads, in order (a
// later one wins for the same controller):
//
//   1. the full SDL_GameControllerDB (engine/gamepad/gamecontrollerdb.txt,
//      refreshed weekly by .github/workflows/gamepad-db.yml),
//   2. the project's gamecontrollerdb.txt (next to project.json; exported
//      with the game),
//   3. the player's own (<user data>/gamecontrollerdb.txt: the built-in
//      Controller Setup screen and Input.mapping_finish write it),
//   4. SDL_GAMECONTROLLERCONFIG (lines) and SDL_GAMECONTROLLERCONFIG_FILE
//      (a file), the usual SDL overrides.
//
// A controller still without a mapping when it connects gets one made for
// it (Gamepad_ResolveFallback):
//   - the same controller's line for another platform (controllers without
//     a vendor id get a GUID from their name, the same everywhere; USB and
//     Bluetooth GUIDs differ only in the bus) - rewritten for this one,
//   - else, unless the project turned it off ("input": {"gamepad_fallback":
//     false}), a standard layout guessed from its counts (Gamepad_GenericMapping),
//     with a warning that suggests Controller Setup (gamepad_setup.odin).
//
// Everything ends up as a mapping line given to GLFW, so the rest of input
// (players, bindings, prompts, the recorder) sees an ordinary gamepad.
// ============================================================================

GAMEPAD_DB :: #load("gamepad/gamecontrollerdb.txt", string)
GAMEPAD_DB_FILE :: "gamecontrollerdb.txt"

// Pad_MapSource: where a controller's mapping came from.
Pad_MapSource :: enum u8 {
	None,           // no mapping: not a gamepad
	Builtin,        // GLFW's own
	Bundled,        // the engine's SDL_GameControllerDB
	Project,        // the project's gamecontrollerdb.txt
	Player,         // the player's gamecontrollerdb.txt
	Environment,    // SDL_GAMECONTROLLERCONFIG(_FILE)
	Other_Platform, // another platform's line for it, rewritten
	Generic,        // the guessed standard layout
	Setup,          // made in Controller Setup (not saved)
	Script,         // Input.set_gamepad_mapping (not saved)
}

PAD_MAP_SOURCE_NAMES := [Pad_MapSource]string {
	.None           = "none",
	.Builtin        = "builtin",
	.Bundled        = "bundled",
	.Project        = "project",
	.Player         = "player",
	.Environment    = "environment",
	.Other_Platform = "other_platform",
	.Generic        = "generic",
	.Setup          = "setup",
	.Script         = "script",
}

Pad_Mapping :: struct {
	line:   string, // (heap)
	source: Pad_MapSource,
}

@(private = "file")
padMaps: struct {
	applied:    bool,   // the files are in GLFW
	noFallback: bool,   // the project turned the generic layout off
	usePlayer:  bool,   // read the player's file (games, not the editor)
	project:    string, // (heap) the project's file
	player:     string, // (heap) the player's file, as read
	env:        string, // (heap) the environment's lines
	inUse:      map[string]Pad_Mapping, // guid (heap) -> the mapping given to GLFW for this platform
	looked:     map[string]bool,        // guids (heap) a fallback was decided for
}

// Gamepad_ConfigureMappings (Game_LoadProjectConfig): the project's
// mappings (its gamecontrollerdb.txt text) and settings. Applied at the
// next frame (the window has to be open).
Gamepad_ConfigureMappings :: proc(project: string, fallback := true, player := true) {
	heap := Engine_HeapAllocator()
	delete(padMaps.project, heap)
	padMaps.project = strings.clone(project, heap)
	padMaps.noFallback = !fallback
	padMaps.usePlayer = player
	padMaps.applied = false
	for k in padMaps.looked do delete(k, heap)
	clear(&padMaps.looked)
}

// Gamepad_FallbackEnabled: unknown controllers get the standard layout.
Gamepad_FallbackEnabled :: proc() -> bool {return !padMaps.noFallback}

Gamepad_MappingsShutdown :: proc() {
	heap := Engine_HeapAllocator()
	delete(padMaps.project, heap)
	delete(padMaps.player, heap)
	delete(padMaps.env, heap)
	for k, m in padMaps.inUse {
		delete(k, heap)
		delete(m.line, heap)
	}
	delete(padMaps.inUse)
	for k in padMaps.looked do delete(k, heap)
	delete(padMaps.looked)
	padMaps = {}
}

// Gamepad_PlayerMappingsPath: the player's own mappings (next to the saves).
Gamepad_PlayerMappingsPath :: proc(allocator := context.temp_allocator) -> string {
	p, _ := filepath.join({filepath.dir(Save_FilePath(), context.temp_allocator), GAMEPAD_DB_FILE}, allocator)
	return p
}

// Gamepad_MappingsFrame (each frame): the files once the window is open,
// then a fallback for each controller that connected without a mapping.
Gamepad_MappingsFrame :: proc() {
	when !JOY_RAW {
		return
	} else {
		if !rl.IsWindowReady() do return
		if !padMaps.applied do pad_apply_all()
		for jid in 0 ..< i32(JOY_MAX) {
			if !joy_present(jid) || joy_is_gamepad(jid) do continue
			guid := strings.to_lower(joy_guid(jid), context.temp_allocator)
			if guid == "" || guid in padMaps.looked do continue
			pad_looked(guid)
			name := joy_name(jid)
			line, src := Gamepad_ResolveFallback(guid, name, len(joy_axes(jid)), len(joy_buttons(jid)), len(joy_hats(jid)))
			if line == "" {
				log.warnf("[Gamepad] %q (%s) has no mapping, so its buttons don't work - set it up with Controller Setup (Input.open_controller_setup, or Tools > Controllers in the editor)", name, guid)
				continue
			}
			Gamepad_ApplyMapping(line, src)
			if src == .Generic {
				log.warnf("[Gamepad] %q (%s) isn't in the controller database: using a standard layout. If buttons are wrong, set it up with Controller Setup (Input.open_controller_setup, or Tools > Controllers in the editor)", name, guid)
			} else {
				log.infof("[Gamepad] %q (%s): using its mapping from another platform", name, guid)
			}
		}
	}
}

@(private = "file")
pad_looked :: proc(guid: string) {
	heap := Engine_HeapAllocator()
	if padMaps.looked == nil do padMaps.looked = make(map[string]bool, heap)
	if guid not_in padMaps.looked do padMaps.looked[strings.clone(guid, heap)] = true
}

@(private = "file")
pad_apply_all :: proc() {
	heap := Engine_HeapAllocator()
	padMaps.applied = true
	pad_apply_text(GAMEPAD_DB, .Bundled)
	pad_apply_text(padMaps.project, .Project)
	delete(padMaps.player, heap)
	padMaps.player = ""
	if padMaps.usePlayer {
		if data, err := os.read_entire_file(Gamepad_PlayerMappingsPath(), context.temp_allocator); err == nil {
			padMaps.player = strings.clone(string(data), heap)
		}
	}
	pad_apply_text(padMaps.player, .Player)
	env := strings.builder_make(context.temp_allocator)
	if lines := os.get_env("SDL_GAMECONTROLLERCONFIG", context.temp_allocator); lines != "" {
		strings.write_string(&env, lines)
		strings.write_byte(&env, '\n')
	}
	if path := os.get_env("SDL_GAMECONTROLLERCONFIG_FILE", context.temp_allocator); path != "" {
		if data, err := os.read_entire_file(path, context.temp_allocator); err == nil do strings.write_string(&env, string(data))
	}
	delete(padMaps.env, heap)
	padMaps.env = strings.clone(strings.to_string(env), heap)
	pad_apply_text(padMaps.env, .Environment)
}

// pad_apply_text: every line in GLFW (it keeps this platform's), and which
// line each controller now uses.
@(private = "file")
pad_apply_text :: proc(text: string, source: Pad_MapSource) {
	if strings.trim_space(text) == "" do return
	when JOY_RAW do rl.SetGamepadMappings(strings.clone_to_cstring(text, context.temp_allocator))
	it := text
	for raw in strings.split_lines_iterator(&it) {
		p, ok := Gamepad_ParseLine(raw)
		if !ok || (p.platform != "" && p.platform != GAMEPAD_PLATFORM) do continue
		pad_record(p.guid, strings.trim_space(raw), source)
	}
}

@(private = "file")
pad_record :: proc(guid, line: string, source: Pad_MapSource) {
	heap := Engine_HeapAllocator()
	if padMaps.inUse == nil do padMaps.inUse = make(map[string]Pad_Mapping, heap)
	key := strings.to_lower(guid, context.temp_allocator)
	if old, has := padMaps.inUse[key]; has {
		delete(old.line, heap)
		padMaps.inUse[key] = {strings.clone(line, heap), source}
		return
	}
	padMaps.inUse[strings.clone(key, heap)] = {strings.clone(line, heap), source}
}

// Gamepad_ApplyMapping: a mapping line in use now (this platform's, whatever
// its platform field says). false for a line that isn't one.
Gamepad_ApplyMapping :: proc(line: string, source: Pad_MapSource) -> bool {
	p, ok := Gamepad_ParseLine(line)
	if !ok do return false
	l := Gamepad_BuildLine(p.guid, p.name, p.fields[:], GAMEPAD_PLATFORM)
	when JOY_RAW do rl.SetGamepadMappings(strings.clone_to_cstring(l, context.temp_allocator))
	pad_record(p.guid, l, source)
	return true
}

// Gamepad_MappingOf: the mapping a GUID uses (its line; "" for GLFW's own).
Gamepad_MappingOf :: proc(guid: string) -> (Pad_Mapping, bool) {
	m, ok := padMaps.inUse[strings.to_lower(guid, context.temp_allocator)]
	return m, ok
}

// Gamepad_SourceOf: where joystick jid's mapping came from.
Gamepad_SourceOf :: proc(jid: i32) -> Pad_MapSource {
	if !joy_present(jid) do return .None
	if !joy_is_gamepad(jid) do return .None
	if m, ok := Gamepad_MappingOf(joy_guid(jid)); ok do return m.source
	return .Builtin
}

// --- mapping lines ---------------------------------------------------------------

Pad_LineParts :: struct {
	guid:     string, // lower case
	name:     string,
	platform: string, // "" = every platform
	fields:   [dynamic]string, // "a:b0", ... (no platform)
}

// Gamepad_ParseLine: an SDL mapping line's parts (temp). false for comments,
// blank lines and anything else.
Gamepad_ParseLine :: proc(line: string) -> (p: Pad_LineParts, ok: bool) {
	l := strings.trim_space(line)
	if len(l) < 34 || l[32] != ',' do return
	for ch in l[:32] {
		if !((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')) do return
	}
	parts := strings.split(l, ",", context.temp_allocator)
	p.guid = strings.to_lower(parts[0], context.temp_allocator)
	p.name = strings.trim_space(parts[1])
	p.fields = make([dynamic]string, context.temp_allocator)
	for f in parts[2:] {
		f := strings.trim_space(f)
		if f == "" do continue
		if strings.has_prefix(f, "platform:") {
			p.platform = f[len("platform:"):]
			continue
		}
		append(&p.fields, f)
	}
	return p, true
}

// Gamepad_BuildLine: a mapping line (temp). Commas in the name become spaces.
Gamepad_BuildLine :: proc(guid, name: string, fields: []string, platform: string, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make(allocator)
	strings.write_string(&sb, strings.to_lower(guid, context.temp_allocator))
	strings.write_byte(&sb, ',')
	clean, _ := strings.replace_all(strings.trim_space(name), ",", " ", context.temp_allocator)
	strings.write_string(&sb, clean if clean != "" else "Controller")
	strings.write_byte(&sb, ',')
	for f in fields {
		strings.write_string(&sb, f)
		strings.write_byte(&sb, ',')
	}
	if platform != "" {
		strings.write_string(&sb, "platform:")
		strings.write_string(&sb, platform)
		strings.write_byte(&sb, ',')
	}
	return strings.to_string(sb)
}

// Pad_InputRef: what a mapping field reads - kind 'b' (button), 'a' (axis)
// or 'h' (hat) and its index.
Pad_InputRef :: struct {
	kind:  u8,
	index: int,
}

// Gamepad_FieldInput: the input of a field's value ("b3", "+a2", "a1~",
// "h0.4"); false for a value it can't read.
Gamepad_FieldInput :: proc(field: string) -> (ref: Pad_InputRef, ok: bool) {
	colon := strings.index_byte(field, ':')
	if colon < 0 do return
	v := field[colon + 1:]
	if len(v) > 0 && (v[0] == '+' || v[0] == '-') do v = v[1:]
	v = strings.trim_suffix(v, "~")
	if len(v) < 2 do return
	ref.kind = v[0]
	if ref.kind != 'a' && ref.kind != 'b' && ref.kind != 'h' do return
	n := 0
	digits := 0
	for i in 1 ..< len(v) {
		ch := v[i]
		if ch < '0' || ch > '9' do break
		n = n * 10 + int(ch - '0')
		digits += 1
	}
	if digits == 0 do return
	ref.index = n
	return ref, true
}

// Gamepad_FitFields: the fields the controller has the inputs for (GLFW
// rejects a whole mapping that names an input past its counts).
Gamepad_FitFields :: proc(fields: []string, axes, buttons, hats: int) -> [dynamic]string {
	out := make([dynamic]string, context.temp_allocator)
	for f in fields {
		ref, ok := Gamepad_FieldInput(f)
		if !ok do continue
		switch ref.kind {
		case 'a': if ref.index >= axes do continue
		case 'b': if ref.index >= buttons do continue
		case 'h': if ref.index >= hats do continue
		}
		append(&out, f)
	}
	return out
}

// Gamepad_GenericMapping: the standard layout guessed from a controller's
// counts - face buttons 0-3 (A B X Y), shoulders 4-5, triggers 6-7, back 8,
// start 9, stick presses 10-11, guide 12; the sticks on axes 0-3; the d-pad
// on the first hat. (temp)
Gamepad_GenericMapping :: proc(guid, name: string, axes, buttons, hats: int, allocator := context.temp_allocator) -> string {
	BUTTONS :: [?]string{"a", "b", "x", "y", "leftshoulder", "rightshoulder", "lefttrigger", "righttrigger", "back", "start", "leftstick", "rightstick", "guide"}
	STICKS :: [?]string{"leftx", "lefty", "rightx", "righty"}
	fields := make([dynamic]string, context.temp_allocator)
	buttonNames := BUTTONS
	for f, i in buttonNames do if i < buttons do append(&fields, fmt.tprintf("%s:b%d", f, i))
	stickNames := STICKS
	for f, i in stickNames do if i < axes do append(&fields, fmt.tprintf("%s:a%d", f, i))
	if hats > 0 do append(&fields, "dpup:h0.1", "dpright:h0.2", "dpdown:h0.4", "dpleft:h0.8")
	return Gamepad_BuildLine(guid, name, fields[:], GAMEPAD_PLATFORM, allocator)
}

// Gamepad_ResolveFallback: a mapping for a controller GLFW has none for -
// another platform's line for the same GUID (the bus-swapped GUID next),
// from the player's, the project's, the environment's then the bundled
// lines; else the generic layout (unless turned off). "" when neither.
Gamepad_ResolveFallback :: proc(guid, name: string, axes, buttons, hats: int) -> (string, Pad_MapSource) {
	g := strings.to_lower(guid, context.temp_allocator)
	cands := make([dynamic]string, context.temp_allocator)
	append(&cands, g)
	if len(g) == 32 {
		if strings.has_prefix(g, "05000000") do append(&cands, strings.concatenate({"03000000", g[8:]}, context.temp_allocator))
		else if strings.has_prefix(g, "03000000") do append(&cands, strings.concatenate({"05000000", g[8:]}, context.temp_allocator))
	}
	texts := [4]string{padMaps.player, padMaps.project, padMaps.env, GAMEPAD_DB}
	for cand in cands {
		for text in texts {
			it := text
			for raw in strings.split_lines_iterator(&it) {
				if len(raw) < 32 || !strings.equal_fold(raw[:32], cand) do continue
				p, ok := Gamepad_ParseLine(raw)
				if !ok do continue
				fit := Gamepad_FitFields(p.fields[:], axes, buttons, hats)
				if len(fit) == 0 do continue
				return Gamepad_BuildLine(g, name if name != "" else p.name, fit[:], GAMEPAD_PLATFORM), .Other_Platform
			}
		}
	}
	if padMaps.noFallback || buttons == 0 do return "", .None
	return Gamepad_GenericMapping(g, name, axes, buttons, hats), .Generic
}

// --- mapping files -----------------------------------------------------------------

// Gamepad_SaveMappingFile: a mapping line into a gamecontrollerdb.txt (made
// if missing), replacing that controller's line for this platform.
Gamepad_SaveMappingFile :: proc(path, line: string) -> bool {
	p, ok := Gamepad_ParseLine(line)
	if !ok || path == "" do return false
	sb := strings.builder_make(context.temp_allocator)
	pad_copy_other_lines(&sb, path, p.guid)
	strings.write_string(&sb, Gamepad_BuildLine(p.guid, p.name, p.fields[:], GAMEPAD_PLATFORM))
	strings.write_byte(&sb, '\n')
	_ = os.make_directory_all(filepath.dir(path, context.temp_allocator))
	return os.write_entire_file(path, transmute([]u8)strings.to_string(sb)) == nil
}

// Gamepad_RemoveMappingFile: a controller's line for this platform out of
// a gamecontrollerdb.txt. false when it had none.
Gamepad_RemoveMappingFile :: proc(path, guid: string) -> bool {
	if !Gamepad_FileHasMapping(path, guid) do return false
	sb := strings.builder_make(context.temp_allocator)
	pad_copy_other_lines(&sb, path, guid)
	return os.write_entire_file(path, transmute([]u8)strings.to_string(sb)) == nil
}

// Gamepad_FileHasMapping: the file has a line for this controller on this platform.
Gamepad_FileHasMapping :: proc(path, guid: string) -> bool {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil do return false
	it := string(data)
	for raw in strings.split_lines_iterator(&it) {
		if q, isMap := Gamepad_ParseLine(raw); isMap && pad_same(q, guid) do return true
	}
	return false
}

@(private = "file")
pad_same :: proc(q: Pad_LineParts, guid: string) -> bool {
	return strings.equal_fold(q.guid, guid) && (q.platform == "" || q.platform == GAMEPAD_PLATFORM)
}

@(private = "file")
pad_copy_other_lines :: proc(sb: ^strings.Builder, path, guid: string) {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil do return
	it := string(data)
	for raw in strings.split_lines_iterator(&it) {
		if q, isMap := Gamepad_ParseLine(raw); isMap && pad_same(q, guid) do continue
		strings.write_string(sb, raw)
		strings.write_byte(sb, '\n')
	}
}
