package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Scene merging with git (#293; the merge itself: engine/scene_merge.odin).
//   editor --merge-scene %O %A %B %P   the merge driver git runs for a scene
//                                      or component file both branches
//                                      changed: merged by node uid into %A
//                                      (formatted as the editor saves it);
//                                      conflicts keep ours and go to
//                                      <file>.merge.json, exit 1 (git marks
//                                      the file conflicted). A file it can't
//                                      merge by uid: git merge-file's text
//                                      merge (conflict markers).
//   Tools > Set Up Scene Merging      .gitattributes in the project + the
//                                      driver in the clone's git config.
//   the Merge Conflicts window        a scene's conflicts: per node and field
//                                      ours / theirs / base; Apply writes the
//                                      file, Mark Resolved runs `git add`.
// ============================================================================

MERGE_DRIVER :: "rayzr-scene"
MERGE_SIDECAR :: ".merge.json"
MERGE_ATTRIBUTES :: "*.scene.json merge=rayzr-scene\n*.component.json merge=rayzr-scene\n"

// MergeScene_Run: `--merge-scene <base> <ours> <theirs> [<path>]` (git's
// %O %A %B %P; the result goes into <ours>).
MergeScene_Run :: proc(args: []string) -> int {
	if len(args) < 3 {
		fmt.eprintln("--merge-scene <base> <ours> <theirs> [<path>]")
		return 2
	}
	basePath, oursPath, theirsPath := args[0], args[1], args[2]
	path := args[3] if len(args) > 3 else oursPath
	read :: proc(p: string) -> []u8 {
		d, err := os.read_entire_file(p, context.temp_allocator)
		return d if err == nil else nil
	}
	base, ours, theirs := read(basePath), read(oursPath), read(theirsPath)
	if base == nil do base = transmute([]u8)string("{}") // (added on both sides)
	res, ok, why := e.Scene_Merge(base, ours, theirs)
	if !ok {
		fmt.eprintfln("rayzr: %s can't be merged by node: %s - a text merge instead", path, why)
		_, mok, missing := Git_Run(".", "merge-file", "-L", "ours", "-L", "base", "-L", "theirs", oursPath, basePath, theirsPath)
		return 1 if !mok || missing else 0
	}
	text := res.text
	// As the editor saves it (its project: the project.json above the file).
	if proj := e.Canonical_ProjectOf(path); proj != "" {
		Resources_Init()
		game := new(e.Game)
		e.InitializeGame(game)
		_, _ = e.Game_LoadProjectForEditing(game, proj)
		abs, _ := filepath.abs(path, context.temp_allocator)
		rel := abs[len(proj) + 1:] if strings.has_prefix(abs, proj) && len(abs) > len(proj) else filepath.base(path)
		if out, fwhy := e.Canonical_Format(game, rel, transmute([]u8)text, context.temp_allocator); fwhy == "" do text = out
		game->terminate()
	}
	if os.write_entire_file(oursPath, transmute([]u8)text) != nil {
		fmt.eprintfln("rayzr: can't write %s", oursPath)
		return 2
	}
	sidecar := strings.concatenate({path, MERGE_SIDECAR}, context.temp_allocator)
	if len(res.conflicts) == 0 {
		if os.exists(sidecar) do _ = os.remove(sidecar)
		return 0
	}
	_ = os.write_entire_file(sidecar, transmute([]u8)e.Merge_ConflictsJSON(path, res.conflicts[:], context.temp_allocator))
	fmt.eprintfln("rayzr: %s merged with %d conflict(s) (ours kept): open the project in the editor to pick (Merge Conflicts)", path, len(res.conflicts))
	return 1
}

// MergeScene_Setup: Tools > Set Up Scene Merging - the driver in the clone's
// git config (this editor's path) and the project's .gitattributes.
MergeScene_Setup :: proc(state: ^EditorState) {
	if state.projectPath == "" do return
	root := Git_Root(state.projectPath)
	if root == "" {
		Editor_Log(state, .Warn, "Scene merging: the project isn't in a git repository (or git isn't installed)")
		return
	}
	exe, _ := filepath.abs(os.args[0], context.temp_allocator)
	driver := fmt.tprintf("'%s' --merge-scene %%O %%A %%B %%P", exe)
	_, ok1, _ := Git_Run(state.projectPath, "config", fmt.tprintf("merge.%s.name", MERGE_DRIVER), "Rayzr scene merge (by node uid)")
	_, ok2, _ := Git_Run(state.projectPath, "config", fmt.tprintf("merge.%s.driver", MERGE_DRIVER), driver)
	if !ok1 || !ok2 {
		Editor_Log(state, .Error, "Scene merging: git config failed")
		return
	}
	attr, _ := filepath.join({state.projectPath, ".gitattributes"}, context.temp_allocator)
	data, _ := os.read_entire_file(attr, context.temp_allocator)
	if !strings.contains(string(data), "merge=" + MERGE_DRIVER) {
		text := string(data)
		if text != "" && !strings.has_suffix(text, "\n") do text = strings.concatenate({text, "\n"}, context.temp_allocator)
		text = strings.concatenate({text, "# Rayzr: scenes merge by node (#293)\n", MERGE_ATTRIBUTES}, context.temp_allocator)
		if os.write_entire_file(attr, transmute([]u8)text) != nil {
			Editor_Log(state, .Error, "Scene merging: can't write %s", attr)
			return
		}
		Editor_Log(state, .Info, "Scene merging set up: .gitattributes added to the project (commit it, so everyone's clone uses it)")
	} else {
		Editor_Log(state, .Info, "Scene merging set up for this clone (the driver: %s)", exe)
	}
}

// MergeScene_DriverSet: the clone has the driver (Tools menu: checked).
MergeScene_DriverSet :: proc(state: ^EditorState) -> bool {
	if state.projectPath == "" do return false
	out, ok, _ := Git_Run(state.projectPath, "config", "--get", fmt.tprintf("merge.%s.driver", MERGE_DRIVER))
	return ok && out != ""
}

// --- the Merge Conflicts window ------------------------------------------------

@(private = "file")
mergeUI: struct {
	open:      bool,
	files:     [dynamic]string,         // project-relative scenes with a sidecar
	current:   int,
	conflicts: [dynamic]e.Merge_Conflict,
	picks:     [dynamic]e.Merge_Pick,
	scanned:   bool,
}

// MergeConflicts_Scan looks for sidecars (project open, files changed);
// opens the window when there are some.
MergeConflicts_Scan :: proc(state: ^EditorState) {
	clear(&mergeUI.files)
	for rel in Editor_ProjectFiles(state) {
		if !strings.has_suffix(rel, MERGE_SIDECAR) do continue
		append(&mergeUI.files, strings.clone(strings.trim_suffix(rel, MERGE_SIDECAR)))
	}
	mergeUI.scanned = true
	if len(mergeUI.files) > 0 {
		mergeUI.open = true
		merge_load(state, 0)
		Editor_Log(state, .Warn, "%d scene file(s) with merge conflicts: pick in the Merge Conflicts window", len(mergeUI.files))
	}
}

MergeConflicts_Open :: proc(state: ^EditorState) {
	Editor_InvalidateProjectFiles() // (a merge since the last scan)
	MergeConflicts_Scan(state)
	mergeUI.open = true
}

MergeConflicts_Count :: proc() -> int {return len(mergeUI.conflicts) if mergeUI.open else -1}

@(private = "file")
merge_load :: proc(state: ^EditorState, i: int) {
	clear(&mergeUI.conflicts)
	clear(&mergeUI.picks)
	mergeUI.current = i
	if i < 0 || i >= len(mergeUI.files) do return
	side, _ := filepath.join({state.projectPath, strings.concatenate({mergeUI.files[i], MERGE_SIDECAR}, context.temp_allocator)}, context.temp_allocator)
	data, err := os.read_entire_file(side, context.temp_allocator)
	if err != nil do return
	_, cs, ok := e.Merge_ReadConflicts(data)
	if !ok do return
	for c in cs {
		append(&mergeUI.conflicts, c)
		append(&mergeUI.picks, e.Merge_Pick.Ours)
	}
}

// merge_apply writes the picks into the file, removes its sidecar and
// reloads it if it's open; `stage`: then `git add` it (resolved).
@(private = "file")
merge_apply :: proc(state: ^EditorState, stage: bool) {
	i := mergeUI.current
	if i < 0 || i >= len(mergeUI.files) do return
	rel := mergeUI.files[i]
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	data, err := os.read_entire_file(full, context.temp_allocator)
	if err != nil do return
	text, ok := e.Merge_Resolve(data, mergeUI.conflicts[:], mergeUI.picks[:], context.temp_allocator)
	if !ok {
		Editor_Log(state, .Error, "Merge: %s couldn't be read", rel)
		return
	}
	if out, why := e.Canonical_Format(state.game, rel, transmute([]u8)text, context.temp_allocator); why == "" do text = out
	Editor_RecordFileUndo(state, rel, fmt.tprintf("Resolve %s", rel))
	if os.write_entire_file(full, transmute([]u8)text) != nil {
		Editor_Log(state, .Error, "Merge: can't write %s", rel)
		return
	}
	_ = os.remove(strings.concatenate({full, MERGE_SIDECAR}, context.temp_allocator))
	Editor_InvalidateProjectFiles()
	if stage {
		if _, gok, _ := Git_Run(state.projectPath, "add", "--", rel); gok do Editor_Log(state, .Info, "Resolved %s (git add)", rel)
		else do Editor_Log(state, .Warn, "Resolved %s; git add failed: add it yourself", rel)
	} else {
		Editor_Log(state, .Info, "Resolved %s (git add it when you're done)", rel)
	}
	for s in SceneTabs_Open() do if s != nil && s.filePath == rel {
		Editor_Log(state, .Info, "%s is open: close it without saving and open it again to see the merge", rel)
	}
	ordered_remove(&mergeUI.files, i)
	merge_load(state, min(i, len(mergeUI.files) - 1))
	if len(mergeUI.files) == 0 do mergeUI.open = false
}

MergeConflicts_Render :: proc(state: ^EditorState) {
	if !mergeUI.scanned && state.projectPath != "" do MergeConflicts_Scan(state)
	if !mergeUI.open do return
	imgui.SetNextWindowSize({720, 460}, .FirstUseEver)
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	defer imgui.End()
	if !imgui.Begin(fmt.ctprintf("%s  Merge Conflicts###MergeConflicts", ICON_FA_CODE_BRANCH), &mergeUI.open, {.NoCollapse}) do return
	Drive_Window("merge")
	if len(mergeUI.files) == 0 {
		UI_DimText("No scene merge conflicts. When git merges two branches that changed the same field of a scene, its conflicts show here.")
		return
	}
	// The files.
	imgui.TextUnformatted("File")
	imgui.SameLine()
	imgui.SetNextItemWidth(360)
	if imgui.BeginCombo("##mergefile", fmt.ctprintf("%s", mergeUI.files[mergeUI.current])) {
		for f, i in mergeUI.files do if imgui.Selectable(fmt.ctprintf("%s", f), i == mergeUI.current) do merge_load(state, i)
		imgui.EndCombo()
	}
	Drive_Item("merge.file")
	imgui.SameLine()
	UI_DimText(fmt.tprintf("%d conflict(s): ours is in the file now", len(mergeUI.conflicts)))
	imgui.Separator()
	// The conflicts: node, field, the three values; pick one.
	h := imgui.GetContentRegionAvail().y - imgui.GetFrameHeightWithSpacing() - 8
	if imgui.BeginChild("##mergelist", {0, h}) {
		for c, i in mergeUI.conflicts {
			imgui.PushIDInt(i32(i))
			what: string
			switch c.kind {
			case .Value: what = c.field
			case .Moved: what = "moved to different parents"
			case .DeletedChanged: what = "deleted by us, changed by them" if c.oursDeleted else "changed by us, deleted by them"
			}
			imgui.TextUnformatted(fmt.ctprintf("%s  %s", ICON_FA_CUBE, c.name if c.name != "" else c.uid))
			imgui.SameLine()
			UI_DimText(what)
			row :: proc(label: string, value: string, pick: e.Merge_Pick, cur: ^e.Merge_Pick, id: string) {
				shown := value if value != "" else "(none)"
				if imgui.RadioButton(fmt.ctprintf("%s##%s", label, id), cur^ == pick) do cur^ = pick
				Drive_Item(id)
				imgui.SameLine(110)
				imgui.TextWrapped(fmt.ctprintf("%s", shown))
			}
			oursText := c.ours
			theirsText := c.theirs
			if c.kind == .DeletedChanged {
				if c.oursDeleted do oursText = "(deleted)"
				else do theirsText = "(deleted)"
			}
			row("Ours", oursText, .Ours, &mergeUI.picks[i], fmt.tprintf("merge.pick:%d:ours", i))
			row("Theirs", theirsText, .Theirs, &mergeUI.picks[i], fmt.tprintf("merge.pick:%d:theirs", i))
			row("Base", c.base, .Base, &mergeUI.picks[i], fmt.tprintf("merge.pick:%d:base", i))
			imgui.Separator()
			imgui.PopID()
		}
	}
	imgui.EndChild()
	if UI_PrimaryButton("Apply and Mark Resolved", "merge.resolve") do merge_apply(state, true)
	UI_Tooltip("Write the picks into the file and git add it")
	imgui.SameLine()
	if UI_Button("Apply", "merge.apply") do merge_apply(state, false)
	UI_Tooltip("Write the picks into the file (git add it yourself)")
}

// MergeConflicts_DriveQuery: merge.files, merge.conflicts, merge.open.
MergeConflicts_DriveQuery :: proc(q: string) -> (string, bool) {
	switch q {
	case "merge.files": return fmt.tprint(len(mergeUI.files)), true
	case "merge.conflicts": return fmt.tprint(len(mergeUI.conflicts)), true
	case "merge.open": return "true" if mergeUI.open else "false", true
	}
	return "", false
}
