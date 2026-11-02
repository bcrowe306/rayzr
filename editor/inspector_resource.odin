package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// The Inspector for a resource file (a .resource.json selected in Assets):
// its class, and the class's properties with the same rows as a node
// script's (script_props_editor), holding the file's values.
//
// Saving: an edit is written when its field is let go (no widget active) -
// a drag or typing writes once at the end, a checkbox or a pick at once.
// The file keeps only values that differ from the class's defaults, plus
// keys the class doesn't declare. Every edit is an undo step in the one
// undo stack (Editor_RecordFileUndo). A running game / Simulate picks
// the file up through hot reload.
// ============================================================================

@(private = "file")
Resource_Inspector :: struct {
	path:     string,                    // project-relative (heap)
	modTime:  time.Time,                 // the file's, when read / written
	class:    string,                    // its "script" (heap)
	classMod: time.Time,                 // the class module's modTime when read
	values:   map[string]e.ScriptValue,  // the declared properties (heap, owned strings)
	raw:      map[string]string,         // keys the class doesn't declare: JSON (heap)
	problem:  string,                    // why it can't be edited ("" = fine; heap)
	pending:  bool,                      // edited, not written yet
}

@(private = "file")
ri: Resource_Inspector

// ResourceInspector_Render draws the selected resource (from inspector_body).
ResourceInspector_Render :: proc(state: ^EditorState, rel: string) {
	if ri.path != rel do ResourceInspector_Flush(state)
	ri_sync(state, rel)
	mod := ri_module(state)

	// Header: icon, name, path.
	imgui.PushStyleColorImVec4(.Text, {0.98, 0.80, 0.30, 1})
	imgui.TextUnformatted(ICON_FA_GEM)
	imgui.PopStyleColor()
	imgui.SameLine(0, UI_SPACE)
	imgui.PushFont(GlobalFonts.semibold)
	imgui.TextUnformatted(strings.clone_to_cstring(Asset_DisplayName(rel), context.temp_allocator))
	imgui.PopFont()
	Drive_Item("insp.resource-name")
	imgui.PushFont(GlobalFonts.small)
	UI_DimText(rel)
	imgui.PopFont()
	imgui.Dummy({0, 4})

	if !UI_SectionHeader("Resource") do return
	if !UI_BeginProps("##resource") do return
	defer UI_EndProps()
	UI_PropLabel("Class")
	if ri.class != "" {
		if UI_Button(fmt.tprintf("%s  %s", ICON_FA_CODE, ri.class), "insp.resource-class", {-1, 0}) do Editor_OpenScript(state, ri.class)
		UI_Tooltip("Edit the class script")
	} else {
		UI_DimText("-")
	}
	if ri.problem != "" {
		UI_PropLabel("")
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextWrapped("%s  %s", ICON_FA_TRIANGLE_EXCLAMATION, strings.clone_to_cstring(ri.problem, context.temp_allocator))
		imgui.PopStyleColor()
		Drive_Item("insp.resource-problem")
		return
	}
	UI_PropLabel("Copies")
	UI_DimText("one per component instance" if mod.resourceLocalCopy else "shared (one table everywhere)")
	UI_Tooltip("The class's `resource.local_copy` (a script's property can change it with local_copy)")

	target := Script_PropsTarget{
		mod         = mod,
		modulePath  = ri.class,
		values      = &ri.values,
		owner       = nil, // a resource has no node
		idPrefix    = "insp.resource",
		data        = state,
		set         = proc(state: ^EditorState, t: ^Script_PropsTarget, name: string, val: e.ScriptValue) {
			ri_set_value(name, val)
			ri.pending = true
		},
		record_undo = proc(state: ^EditorState, t: ^Script_PropsTarget, label: string) {
			ResourceInspector_Flush(state)
			Editor_RecordFileUndo(state, ri.path, label)
		},
	}
	if script_props_editor(state, &target) == 0 {
		UI_PropLabel("")
		UI_DimText("The class declares no properties")
	}
	if len(ri.raw) > 0 {
		keys := make([dynamic]string, context.temp_allocator)
		for k in ri.raw do append(&keys, k)
		slice.sort(keys[:])
		UI_PropLabel("")
		UI_DimText(fmt.tprintf("Kept, not declared by the class: %s", strings.join(keys[:], ", ", context.temp_allocator)))
	}
	// Written when the field is let go.
	if ri.pending && !imgui.IsAnyItemActive() do ResourceInspector_Flush(state)
}

// ResourceInspector_Flush writes an edit not written yet.
ResourceInspector_Flush :: proc(state: ^EditorState) {
	if !ri.pending || ri.path == "" do return
	ri.pending = false
	mod := ri_module(state)
	if mod == nil || Editor_FormatBlocksSave(state, ri.path) do return // (from a newer Rayzr: #326)
	full, _ := filepath.join({state.projectPath, ri.path}, context.temp_allocator)
	text := e.Resource_FileText(ri.class, ri.values, mod, ri.raw, context.temp_allocator)
	if os.write_entire_file(full, transmute([]u8)text) != nil {
		Editor_Log(state, .Error, "Could not save %s", ri.path)
		return
	}
	ri.modTime = file_mod_time(full)
	Editor_Log(state, .Info, "Saved %s", ri.path)
}

// ResourceInspector_FileChanged: a resource file was written elsewhere
// (undo / redo); it is read again.
ResourceInspector_FileChanged :: proc(rel: string) {
	if ri.path == rel do ri.modTime = {}
}

// --- internals --------------------------------------------------------------------

@(private = "file")
ri_module :: proc(state: ^EditorState) -> ^e.ScriptModule {
	if ri.class == "" do return nil
	return state.game.scriptManager.modules[e.ScriptVFS_NormalizePath(ri.class)] or_else nil
}

@(private = "file")
file_mod_time :: proc(full: string) -> time.Time {
	info, err := os.stat(full, context.temp_allocator)
	return info.modification_time if err == nil else {}
}

// ri_sync reads the file when it is another one, changed on disk, or its
// class was reloaded.
@(private = "file")
ri_sync :: proc(state: ^EditorState, rel: string) {
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	mt := file_mod_time(full)
	if ri.path == rel && mt == ri.modTime {
		mod := ri_module(state)
		if mod == nil || mod.modTime == ri.classMod do return
	}
	if ri.pending do return // (our edit is written first)
	ri_clear()
	ri.path = strings.clone(rel)
	ri.modTime = mt
	ri.values = make(map[string]e.ScriptValue)
	ri.raw = make(map[string]string)
	data, err := os.read_entire_file(full, context.temp_allocator)
	if err != nil {
		ri.problem = strings.clone("The file can't be read")
		return
	}
	file, ok := e.Resource_ParseText(rel, string(data), quiet = true)
	if !ok {
		ri.problem = strings.clone("Not a valid resource file: it needs \"type\": \"resource\" and \"script\" (its class)")
		return
	}
	ri.class = strings.clone(file.script)
	m, loaded := e.ScriptManager_LoadModule(file.script, &state.game.scriptManager)
	if !loaded {
		ri.problem = strings.clone(fmt.tprintf("Its class %s can't be loaded (see the Console)", file.script))
		return
	}
	ri.classMod = m.modTime
	if !m.isResourceClass {
		ri.problem = strings.clone(fmt.tprintf("%s is not a resource class: add `resource = { local_copy = false }` to its table", file.script))
		return
	}
	for p in m.properties {
		ri.values[strings.clone(p.name)] = e.script_property_value(p, file.values)
	}
	for k, v in file.raw {
		if k in ri.values do continue
		ri.raw[strings.clone(k)] = strings.clone(v)
	}
}

@(private = "file")
ri_set_value :: proc(name: string, val: e.ScriptValue) {
	nv := val
	if nv.type == .String do nv.valString = strings.clone(val.valString)
	else do nv.valString = ""
	if name in ri.values {
		k, old := delete_key(&ri.values, name)
		if old.type == .String do delete(old.valString)
		ri.values[k] = nv
	} else {
		ri.values[strings.clone(name)] = nv
	}
}

@(private = "file")
ri_clear :: proc() {
	delete(ri.path)
	delete(ri.class)
	delete(ri.problem)
	for k, v in ri.values {
		delete(k)
		if v.type == .String do delete(v.valString)
	}
	delete(ri.values)
	for k, v in ri.raw {
		delete(k)
		delete(v)
	}
	delete(ri.raw)
	ri = {}
}

// --- resource files by class (pickers) ---------------------------------------------

@(private = "file")
classOfFile: struct {
	scanned: time.Tick,
	of:      map[string]string, // resource file -> its class (heap)
}

// Resource_FilesOfClass: the project's resource files whose class is
// `class` (every one for ""), temp allocated. Classes are re-read at most
// once a second.
Resource_FilesOfClass :: proc(state: ^EditorState, class: string) -> []string {
	files := Editor_ListProjectFiles(state, "resources", {e.RESOURCE_EXT})
	if class == "" do return files
	if classOfFile.of == nil || time.tick_since(classOfFile.scanned) > PROJECT_FILES_TTL {
		for k, v in classOfFile.of {
			delete(k)
			delete(v)
		}
		clear(&classOfFile.of)
		if classOfFile.of == nil do classOfFile.of = make(map[string]string)
		for rel in files {
			full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
			data, err := os.read_entire_file(full, context.temp_allocator)
			if err != nil do continue
			file, ok := e.Resource_ParseText(rel, string(data), quiet = true)
			if ok do classOfFile.of[strings.clone(rel)] = strings.clone(e.ScriptVFS_NormalizePath(file.script))
		}
		classOfFile.scanned = time.tick_now()
	}
	// (The class by path or by name: Resource_ClassMatches, #208.)
	out := make([dynamic]string, context.temp_allocator)
	for rel in files do if script, ok := classOfFile.of[rel]; ok && e.Resource_ClassMatches(class, script) do append(&out, rel)
	return out[:]
}
