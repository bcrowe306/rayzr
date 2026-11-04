package editor

import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Project file list, cached. Asset lists and pickers ask for project files
// every frame (the asset browser alone several times); walking the project
// each time was a large share of the editor's frame. The project is
// scanned once and re-scanned when the editor changes files
// (Editor_InvalidateProjectFiles, called with Lua_MarkProjectTypesDirty)
// or every second (PROJECT_FILES_TTL) for changes made outside the editor.
// Hidden files and folders (.rayzr/, .luarc.json, ...) aren't listed.
// ============================================================================

PROJECT_FILES_TTL :: time.Second

@(private = "file")
projectFiles: struct {
	root:    string,          // heap
	files:   [dynamic]string, // heap, project-relative, sorted
	dirs:    [dynamic]string, // heap, project-relative folders (empty ones too), sorted
	scanned: time.Tick,
	valid:   bool,
	// Strings of earlier scans, freed a frame later: callers iterate the
	// lists while an edit (a move, a save) makes the next call re-scan.
	retired:      [dynamic]string,
	retiredFrame: i32,
	// .rayzr packages next to the project folder (exports).
	packages:        [dynamic]string,
	packagesScanned: time.Tick,
	packagesValid:   bool,
}

Editor_InvalidateProjectFiles :: proc() {
	e.Component_ForgetPrepared() // (a component file may be written: #80)
	assetThumbsStale = true // grid thumbnails reload
	projectFiles.valid = false
	projectFiles.packagesValid = false
}

ProjectFiles_Shutdown :: proc() {
	delete(projectFiles.root)
	projectFiles.root = ""
	for f in projectFiles.files do delete(f)
	delete(projectFiles.files)
	projectFiles.files = nil
	for d in projectFiles.dirs do delete(d)
	delete(projectFiles.dirs)
	projectFiles.dirs = nil
	for r in projectFiles.retired do delete(r)
	delete(projectFiles.retired)
	projectFiles.retired = nil
	for p in projectFiles.packages do delete(p)
	delete(projectFiles.packages)
	projectFiles.packages = nil
	projectFiles.valid = false
	projectFiles.packagesValid = false
}

// Editor_ParentPackages: the .rayzr files in the project's parent folder.
Editor_ParentPackages :: proc(state: ^EditorState) -> []string {
	if state.projectPath == "" do return nil
	if !projectFiles.packagesValid || time.tick_since(projectFiles.packagesScanned) > PROJECT_FILES_TTL {
		for p in projectFiles.packages do delete(p)
		clear(&projectFiles.packages)
		dir := filepath.dir(strings.trim_suffix(state.projectPath, "/"), context.temp_allocator)
		if infos, err := os.read_all_directory_by_path(dir, context.temp_allocator); err == nil {
			for fi in infos do if fi.type != .Directory && e.Is_PackagePath(fi.name) do append(&projectFiles.packages, strings.clone(fi.name))
		}
		slice.sort(projectFiles.packages[:])
		projectFiles.packagesScanned = time.tick_now()
		projectFiles.packagesValid = true
	}
	return projectFiles.packages[:]
}

@(private = "file")
scan_project :: proc(root: string) {
	if frame := (imgui.GetFrameCount() if imgui.GetCurrentContext() != nil else 0); frame != projectFiles.retiredFrame {
		for r in projectFiles.retired do delete(r)
		clear(&projectFiles.retired)
		projectFiles.retiredFrame = frame
	}
	// Custom node type files before (#156): added or removed ones (copied in,
	// a git checkout) - the loaded types are read again.
	typesBefore := make([dynamic]string, context.temp_allocator)
	for f in projectFiles.files do if strings.has_suffix(f, e.CUSTOM_NODE_SUFFIX) do append(&typesBefore, f)
	append(&projectFiles.retired, ..projectFiles.files[:])
	append(&projectFiles.retired, ..projectFiles.dirs[:])
	clear(&projectFiles.files)
	clear(&projectFiles.dirs)
	walk :: proc(root, rel: string, depth: int) {
		if depth > 8 do return
		full, _ := filepath.join({root, rel}, context.temp_allocator)
		infos, err := os.read_all_directory_by_path(full, context.temp_allocator)
		if err != nil do return
		for fi in infos {
			if strings.has_prefix(fi.name, ".") do continue
			if e.Asset_IsImportFile(fi.name) do continue // (shown as the asset's import settings)
			// (Project-relative paths use "/" on every OS, as the lists' callers
			// match them ("scenes/..."): filepath.join gave "scenes\..." on
			// Windows, and the asset browser listed nothing there, #330.)
			child := strings.concatenate({rel, "/", fi.name}, context.temp_allocator) if rel != "" else fi.name
			if fi.type == .Directory {
				append(&projectFiles.dirs, strings.clone(child))
				walk(root, child, depth + 1)
			} else {
				append(&projectFiles.files, strings.clone(child))
			}
		}
	}
	walk(root, "", 0)
	slice.sort(projectFiles.files[:])
	slice.sort(projectFiles.dirs[:])
	if projectFiles.root != root {
		delete(projectFiles.root)
		projectFiles.root = strings.clone(root)
	}
	projectFiles.scanned = time.tick_now()
	projectFiles.valid = true
	typesAfter := make([dynamic]string, context.temp_allocator)
	for f in projectFiles.files do if strings.has_suffix(f, e.CUSTOM_NODE_SUFFIX) do append(&typesAfter, f)
	if !slice.equal(typesBefore[:], typesAfter[:]) do Lua_MarkProjectTypesDirty() // (forgets the loaded types too)
}

// Editor_ProjectFiles: every (non-hidden) project file, project-relative,
// sorted.
Editor_ProjectFiles :: proc(state: ^EditorState) -> []string {
	if state.projectPath == "" do return nil
	if !projectFiles.valid || projectFiles.root != state.projectPath || time.tick_since(projectFiles.scanned) > PROJECT_FILES_TTL {
		scan_project(state.projectPath)
	}
	return projectFiles.files[:]
}

// Editor_ProjectDirs: every (non-hidden) project folder, project-relative,
// sorted.
Editor_ProjectDirs :: proc(state: ^EditorState) -> []string {
	_ = Editor_ProjectFiles(state) // (re)scans
	return projectFiles.dirs[:]
}

// Editor_ListProjectFiles lists project files under `subdir` (recursive;
// "" or "." = everything) with one of `exts`, as project-relative paths,
// sorted (temp-allocated).
Editor_ListProjectFiles :: proc(state: ^EditorState, subdir: string, exts: []string) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	dir := strings.trim_suffix(strings.trim_prefix(subdir, "./"), "/")
	if dir == "." do dir = ""
	prefix := strings.concatenate({dir, "/"}, context.temp_allocator) if dir != "" else ""
	for f in Editor_ProjectFiles(state) {
		if prefix != "" && !strings.has_prefix(f, prefix) do continue
		lower := strings.to_lower(f, context.temp_allocator)
		for ext in exts {
			if strings.has_suffix(lower, ext) {
				append(&out, f)
				break
			}
		}
	}
	return out[:]
}
