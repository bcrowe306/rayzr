package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import e "../engine"

// ============================================================================
// Format Scene Files (#293): scene and component files rewritten exactly as
// the editor saves them (engine/canonical_files.odin), so a file written by
// hand or by a generator doesn't become a whole-file diff the first time
// someone saves it.
//   editor --fmt [--check] <file or folder>...   (exit 1 with --check when a
//                                                  file isn't canonical)
//   Tools > Format Scene Files                    (the open project; files
//                                                  open in a tab are left to
//                                                  their next save)
// A file a rewrite would lose something of (an old key the loader ignores,
// a newer format) is left as it is and reported.
// ============================================================================

Fmt_Result :: enum {Unchanged, Formatted, Refused}

// fmt_one formats one file of the project `game` has open (rel: project-
// relative); `check`: report only, don't write.
@(private = "file")
fmt_one :: proc(game: ^e.Game, full, rel: string, check: bool) -> (Fmt_Result, string) {
	data, err := os.read_entire_file(full, context.temp_allocator)
	if err != nil do return .Refused, "can't be read"
	out, why := e.Canonical_Format(game, rel, data, context.temp_allocator)
	if why != "" do return .Refused, why
	if out == string(data) do return .Unchanged, ""
	if !check && os.write_entire_file(full, transmute([]u8)out) != nil do return .Refused, "can't be written"
	return .Formatted, ""
}

// fmt_collect: the scene and component files at a path (a folder: all of
// them inside, skipping hidden folders such as .rayzr and build output).
@(private = "file")
fmt_collect :: proc(path: string, out: ^[dynamic]string) {
	if !os.is_dir(path) {
		if e.Canonical_KindOf(path) != .Unknown do append(out, strings.clone(path, context.temp_allocator))
		return
	}
	h, err := os.open(path)
	if err != nil do return
	fis, _ := os.read_dir(h, -1, context.temp_allocator)
	os.close(h)
	for fi in fis {
		if strings.has_prefix(fi.name, ".") || fi.name == "build" || fi.name == "export" do continue
		p, _ := filepath.join({path, fi.name}, context.temp_allocator)
		fmt_collect(p, out)
	}
}

// Fmt_Run: `--fmt [--check] <paths>`. Files are grouped by project (the
// project.json above them), each project opened once - its custom node
// types and components are what the files' nodes are read with.
Fmt_Run :: proc(args: []string) -> int {
	check := slice.contains(args, "--check")
	files := make([dynamic]string, context.temp_allocator)
	for a in args do if a != "--check" do fmt_collect(a, &files)
	if len(files) == 0 {
		fmt.eprintln("--fmt: no scene or component files (editor --fmt [--check] <file or folder>...)")
		return 2
	}
	slice.sort(files[:])
	Resources_Init()
	games := make(map[string]^e.Game, allocator = context.temp_allocator)
	defer for _, g in games do g->terminate()
	formatted, refused := 0, 0
	for f in files {
		abs, _ := filepath.abs(f, context.temp_allocator)
		proj := e.Canonical_ProjectOf(abs)
		if proj == "" {
			fmt.eprintfln("skipped %s: not in a project (no project.json above it)", f)
			refused += 1
			continue
		}
		game := games[proj]
		if game == nil {
			game = new(e.Game)
			e.InitializeGame(game)
			if _, ok := e.Game_LoadProjectForEditing(game, proj); !ok {
				fmt.eprintfln("skipped %s: its project can't be opened", f)
				refused += 1
				continue
			}
			games[proj] = game
		}
		res, why := fmt_one(game, abs, abs[len(proj) + 1:], check)
		switch res {
		case .Formatted:
			formatted += 1
			fmt.println(fmt.tprintf("%s %s", "not canonical:" if check else "formatted", f))
		case .Refused:
			refused += 1
			fmt.eprintfln("skipped %s: %s", f, why)
		case .Unchanged:
		}
	}
	fmt.printfln("%d file(s): %d %s, %d skipped", len(files), formatted, "to format" if check else "formatted", refused)
	return 1 if check && formatted > 0 else 0
}

// Fmt_Project: Tools > Format Scene Files on the open project.
Fmt_Project :: proc(state: ^EditorState) {
	if state.projectPath == "" do return
	Editor_InvalidateProjectFiles() // (files added outside the editor too)
	open := make(map[string]bool, allocator = context.temp_allocator)
	for s in SceneTabs_Open() do if s != nil do open[s.filePath] = true
	formatted, refused, skippedOpen := 0, 0, 0
	for rel in Editor_ProjectFiles(state) {
		if e.Canonical_KindOf(rel) == .Unknown do continue
		if rel in open {
			skippedOpen += 1
			continue
		}
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		res, why := fmt_one(state.game, full, rel, false)
		switch res {
		case .Formatted: formatted += 1
		case .Refused:
			refused += 1
			Editor_Log(state, .Warn, "Format: %s left as it is: %s", rel, why)
		case .Unchanged:
		}
	}
	if formatted > 0 do Editor_InvalidateProjectFiles()
	Editor_Log(state, .Info, "Formatted %d scene/component file(s)%s%s", formatted,
		fmt.tprintf(", %d left as they are (see above)", refused) if refused > 0 else "",
		fmt.tprintf(", %d open in a tab (formatted when saved)", skippedOpen) if skippedOpen > 0 else "")
}
