package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import vmem "core:mem/virtual"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// The Git tab (#293): the project's repository with the installed `git`.
//   the header   the branch (switch / create), ahead / behind its upstream,
//                Fetch, Pull, Push (on a worker: the editor keeps running),
//                Refresh
//   Changes      the project's changed files: tick to stage, a message,
//                Commit; the selected file's diff - a scene or component
//                by node (added / removed / moved / changed fields, from the
//                last commit to the file on disk: Scene_Diff), other files
//                as text
//   History      the commits of the selected file (or the project)
// Switching branch and pulling need the open scenes saved (the files on
// disk change); the scene open in the viewport is reloaded after.
// ============================================================================

Git_File :: struct {
	path:   string, // repository-relative
	rel:    string, // project-relative ("" outside the project)
	index:  u8,     // git's X: staged change (' ' none, '?' untracked)
	work:   u8,     // git's Y: unstaged change
}

Git_Commit :: struct {hash, author, age, subject: string}

Git_View :: enum {Changes, History}

@(private = "file")
Git_Net_Job :: struct {
	dir:    string,
	args:   [dynamic]string,
	label:  string,
	output: string,
	ok:     bool,
	done:   bool,
	thread: ^thread.Thread,
}

@(private = "file")
gp: struct {
	arena:      vmem.Arena, // the status (freed on each refresh)
	diffArena:  vmem.Arena, // the selected file's diff / history
	ready:      bool,
	project:    string,
	root:       string,
	isRepo:     bool,
	missing:    bool, // no git
	branch:     string,
	upstream:   string,
	ahead, behind: int,
	branches:   [dynamic]string,
	files:      [dynamic]Git_File,
	selected:   string, // repository-relative path
	diffText:   string,
	diffNodes:  [dynamic]e.Scene_Change,
	diffIsScene: bool,
	history:    [dynamic]Git_Commit,
	view:       Git_View,
	commitBuf:  [1024]u8,
	branchBuf:  [96]u8,
	job:        ^Git_Net_Job,
	message:    string, // the last command's result (heap)
	refreshed:  time.Tick,
	dirty:      bool,
}

@(private = "file")
gp_init :: proc() {
	if gp.ready do return
	_ = vmem.arena_init_growing(&gp.arena)
	_ = vmem.arena_init_growing(&gp.diffArena)
	gp.ready = true
	gp.dirty = true
}

// GitPanel_Refresh re-reads the status (and the selected file's diff).
GitPanel_Refresh :: proc(state: ^EditorState) {gp_init(); gp.dirty = true}

@(private = "file")
gp_message :: proc(format: string, args: ..any) {
	delete(gp.message)
	gp.message = strings.clone(fmt.tprintf(format, ..args))
}

// gp_refresh: the branch, upstream, ahead / behind, branches and changed
// files (git status -z, the project's folder only).
@(private = "file")
gp_refresh :: proc(state: ^EditorState) {
	gp_init()
	vmem.arena_free_all(&gp.arena)
	context.allocator = vmem.arena_allocator(&gp.arena)
	gp.files = make([dynamic]Git_File)
	gp.branches = make([dynamic]string)
	gp.branch, gp.upstream, gp.ahead, gp.behind = "", "", 0, 0
	gp.project = strings.clone(state.projectPath)
	gp.refreshed = time.tick_now()
	gp.dirty = false
	_, _, missing := Git_Run(state.projectPath, "--version")
	gp.missing = missing
	root := Git_Root(state.projectPath) if !missing else ""
	gp.root = strings.clone(root)
	gp.isRepo = root != ""
	if !gp.isRepo do return
	out, ok, _ := Git_Run(state.projectPath, "status", "--porcelain=v1", "-z", "--branch", "--untracked-files=all", "--", ".")
	if !ok do return
	prefix := ""
	if absProj, aerr := filepath.abs(state.projectPath, context.temp_allocator); aerr == nil && strings.has_prefix(absProj, root) && len(absProj) > len(root) {
		prefix = strings.clone(strings.concatenate({absProj[len(root) + 1:], "/"}, context.temp_allocator))
	}
	entries := strings.split(out, "\x00", context.temp_allocator)
	for i := 0; i < len(entries); i += 1 {
		en := entries[i]
		if len(en) < 3 do continue
		if strings.has_prefix(en, "## ") {
			gp_parse_branch(en[3:])
			continue
		}
		f := Git_File{index = en[0], work = en[1], path = strings.clone(en[3:])}
		if en[0] == 'R' || en[0] == 'C' do i += 1 // (a rename: the old path follows)
		if prefix == "" do f.rel = f.path
		else if strings.has_prefix(f.path, prefix) do f.rel = f.path[len(prefix):]
		if strings.has_suffix(f.path, MERGE_SIDECAR) do continue // (the merge window's)
		append(&gp.files, f)
	}
	if bout, bok, _ := Git_Run(state.projectPath, "branch", "--format=%(refname:short)"); bok {
		for b in strings.split_lines(bout, context.temp_allocator) do if b != "" do append(&gp.branches, strings.clone(b))
	}
}

// gp_parse_branch: "main...origin/main [ahead 1, behind 2]" (or "No
// commits yet on main", or "HEAD (no branch)").
@(private = "file")
gp_parse_branch :: proc(s: string) {
	line := s
	if strings.has_prefix(line, "No commits yet on ") do line = line[len("No commits yet on "):]
	rest := ""
	if i := strings.index(line, " ["); i >= 0 {
		rest = line[i + 2:]
		line = line[:i]
	}
	if i := strings.index(line, "..."); i >= 0 {
		gp.branch = strings.clone(line[:i])
		gp.upstream = strings.clone(line[i + 3:])
	} else {
		gp.branch = strings.clone(line)
	}
	for part in strings.split(strings.trim_suffix(rest, "]"), ", ", context.temp_allocator) {
		if strings.has_prefix(part, "ahead ") do gp.ahead, _ = strconv.parse_int(part[6:])
		if strings.has_prefix(part, "behind ") do gp.behind, _ = strconv.parse_int(part[7:])
	}
}

// gp_select loads a file's diff and history.
@(private = "file")
gp_select :: proc(state: ^EditorState, path: string) {
	vmem.arena_free_all(&gp.diffArena)
	context.allocator = vmem.arena_allocator(&gp.diffArena)
	gp.selected = strings.clone(path)
	gp.diffText, gp.diffIsScene = "", false
	gp.diffNodes = make([dynamic]e.Scene_Change)
	gp.history = make([dynamic]Git_Commit)
	if path != "" {
		full, _ := filepath.join({gp.root, path}, context.temp_allocator)
		if e.Canonical_KindOf(path) != .Unknown {
			before, inHead, _ := Git_Run(gp.root, "show", fmt.tprintf("HEAD:%s", path))
			if !inHead do before = "" // (new: not in the last commit)
			after, _ := os.read_entire_file(full, context.temp_allocator)
			if changes, ok := e.Scene_Diff(transmute([]u8)before, after); ok {
				gp.diffIsScene = true
				for c in changes {
					cc := c
					cc.uid, cc.name = strings.clone(c.uid), strings.clone(c.name)
					cc.fields = make([dynamic]e.Scene_Field_Change, 0, len(c.fields))
					for f in c.fields do append(&cc.fields, e.Scene_Field_Change{strings.clone(f.field), strings.clone(f.before), strings.clone(f.after)})
					append(&gp.diffNodes, cc)
				}
			}
		}
		if !gp.diffIsScene {
			text, _, _ := Git_Run(gp.root, "diff", "HEAD", "--", path)
			if text == "" do if data, err := os.read_entire_file(full, context.temp_allocator); err == nil do text = fmt.tprintf("(new file)\n%s", string(data)[:min(len(data), 20000)])
			gp.diffText = strings.clone(text)
		}
	}
	// History: the file's, or the project's.
	target := path if path != "" else "."
	if out, ok, _ := Git_Run(gp.root if path != "" else gp.project, "log", "-n", "100", "--format=%h%x1f%an%x1f%ar%x1f%s", "--", target); ok {
		for line in strings.split_lines(out, context.temp_allocator) {
			p := strings.split(line, "\x1f", context.temp_allocator)
			if len(p) == 4 do append(&gp.history, Git_Commit{strings.clone(p[0]), strings.clone(p[1]), strings.clone(p[2]), strings.clone(p[3])})
		}
	}
}

// --- network commands on a worker -----------------------------------------------

@(private = "file")
gp_start :: proc(label: string, args: ..string) {
	if gp.job != nil do return
	job := new(Git_Net_Job)
	job.dir = strings.clone(gp.project)
	job.label = strings.clone(label)
	job.args = make([dynamic]string)
	for a in args do append(&job.args, strings.clone(a))
	job.thread = thread.create_and_start_with_poly_data(job, proc(job: ^Git_Net_Job) {
		cmd := make([dynamic]string, context.temp_allocator)
		append(&cmd, "git", "-C", job.dir)
		append(&cmd, ..job.args[:])
		// (No prompts: a push needing a password fails instead of waiting.)
		env := make([dynamic]string, context.temp_allocator)
		if cur, eerr := os.environ(context.temp_allocator); eerr == nil do append(&env, ..cur)
		append(&env, "GIT_TERMINAL_PROMPT=0")
		st, out, errOut, err := os.process_exec({command = cmd[:], env = env[:]}, context.temp_allocator)
		text := strings.trim_space(string(errOut) if len(errOut) > 0 else string(out))
		job.output = strings.clone(text, context.allocator)
		job.ok = err == nil && st.exit_code == 0
		if err != nil do job.output = strings.clone("git isn't installed")
		sync.atomic_store(&job.done, true)
	})
	gp.job = job
}

@(private = "file")
gp_poll :: proc(state: ^EditorState) {
	job := gp.job
	if job == nil || !sync.atomic_load(&job.done) do return
	thread.join(job.thread)
	thread.destroy(job.thread)
	if job.ok {
		gp_message("%s: done", job.label)
		Editor_Log(state, .Info, "Git %s done", job.label)
		if job.label == "Pull" do gp_reload_active(state)
	} else {
		first := strings.split_lines(job.output, context.temp_allocator)
		gp_message("%s failed: %s", job.label, first[0] if len(first) > 0 else "")
		Editor_Log(state, .Error, "Git %s failed: %s", job.label, job.output)
	}
	delete(job.dir)
	delete(job.label)
	delete(job.output)
	for a in job.args do delete(a)
	delete(job.args)
	free(job)
	gp.job = nil
	gp.dirty = true
}

// gp_reload_active: after a pull / branch switch the open scene's file may
// have changed - read it again (the scenes were saved first).
@(private = "file")
gp_reload_active :: proc(state: ^EditorState) {
	Editor_InvalidateProjectFiles()
	if state.activeScene != nil && state.activeScene.filePath != "" && !Editor_SceneIsModified(state, state.activeScene) do Editor_RevertScene(state)
	if len(SceneTabs_Open()) > 1 do Editor_Log(state, .Info, "Other open scene tabs show the files as they were: close and open them again")
}

@(private = "file")
gp_needs_saved :: proc(state: ^EditorState, what: string) -> bool {
	if n := Editor_ModifiedSceneCount(state); n > 0 {
		gp_message("%s: save (or revert) the %d scene(s) with changes first", what, n)
		return true
	}
	return false
}

// --- the tab ----------------------------------------------------------------------

GitPanel_Render :: proc(state: ^EditorState) {
	gp_init()
	gp_poll(state)
	if state.projectPath == "" {
		UI_DimText("Open a project to see its git repository.")
		return
	}
	if gp.dirty || gp.project != state.projectPath || time.duration_seconds(time.tick_since(gp.refreshed)) > 3 {
		sel := strings.clone(gp.selected, context.temp_allocator)
		gp_refresh(state)
		if gp.isRepo do gp_select(state, sel)
	}
	if gp.missing {
		UI_DimText("git isn't installed: install it (git-scm.com) to use this tab.")
		return
	}
	if !gp.isRepo {
		UI_DimText("This project isn't in a git repository.")
		if UI_Button(fmt.tprintf("%s  Create Repository", ICON_FA_CODE_BRANCH), "git.init") {
			if _, ok, _ := Git_Run(state.projectPath, "init", "-q"); ok {
				gp_message("Created a repository in the project's folder")
				Editor_Log(state, .Info, "git init: %s", state.projectPath)
			}
			gp.dirty = true
		}
		UI_Tooltip("git init in the project's folder")
		return
	}
	gp_header(state)
	imgui.Separator()
	if imgui.BeginTabBar("##gitviews") {
		if imgui.BeginTabItem(fmt.ctprintf("Changes (%d)###gitchanges", len(gp.files))) {
			gp.view = .Changes
			gp_changes(state)
			imgui.EndTabItem()
		}
		Drive_Item("git.view:changes")
		if imgui.BeginTabItem("History###githistory") {
			gp.view = .History
			gp_history(state)
			imgui.EndTabItem()
		}
		Drive_Item("git.view:history")
		imgui.EndTabBar()
	}
}

@(private = "file")
gp_header :: proc(state: ^EditorState) {
	imgui.AlignTextToFramePadding()
	imgui.TextUnformatted(fmt.ctprintf("%s", ICON_FA_CODE_BRANCH))
	imgui.SameLine()
	imgui.SetNextItemWidth(200)
	if imgui.BeginCombo("##gitbranch", fmt.ctprintf("%s", gp.branch if gp.branch != "" else "(no branch)")) {
		for b in gp.branches {
			if imgui.Selectable(fmt.ctprintf("%s", b), b == gp.branch) && b != gp.branch {
				if !gp_needs_saved(state, "Switch branch") {
					if out, ok, _ := Git_Run(state.projectPath, "switch", b); ok {
						gp_message("On %s", b)
						gp_reload_active(state)
					} else do gp_message("Switch failed: %s", out)
					gp.dirty = true
				}
			}
		}
		imgui.Separator()
		imgui.SetNextItemWidth(150)
		imgui.InputTextWithHint("##gitnewbranch", "new branch", cstring(raw_data(gp.branchBuf[:])), len(gp.branchBuf))
		Drive_Item("git.newbranch")
		imgui.SameLine()
		name := strings.trim_space(string(cstring(raw_data(gp.branchBuf[:]))))
		if UI_Button("Create", "git.createbranch") && name != "" {
			if out, ok, _ := Git_Run(state.projectPath, "switch", "-c", name); ok {
				gp_message("Created %s", name)
				gp.branchBuf = {}
			} else do gp_message("Create failed: %s", out)
			gp.dirty = true
			imgui.CloseCurrentPopup()
		}
		imgui.EndCombo()
	}
	Drive_Item("git.branch")
	UI_Tooltip("The branch: switch (save your scenes first) or create one")
	imgui.SameLine()
	if gp.upstream != "" do UI_DimText(fmt.tprintf("%s  %d ahead, %d behind", gp.upstream, gp.ahead, gp.behind))
	else do UI_DimText("no upstream")
	Drive_Item("git.sync")
	busy := gp.job != nil
	imgui.SameLine(0, 16)
	if busy do imgui.BeginDisabled(true)
	if UI_Button("Fetch", "git.fetch") do gp_start("Fetch", "fetch", "--prune")
	UI_Tooltip("Get the remote's commits (changes nothing here)")
	imgui.SameLine()
	if UI_Button(fmt.tprintf("%s  Pull", ICON_FA_ARROW_DOWN), "git.pull") && !gp_needs_saved(state, "Pull") do gp_start("Pull", "pull")
	UI_Tooltip("Fetch and merge the remote's commits (scenes merge by node once Tools > Set Up Scene Merging ran)")
	imgui.SameLine()
	if UI_Button(fmt.tprintf("%s  Push", ICON_FA_ARROW_UP), "git.push") {
		if gp.upstream != "" do gp_start("Push", "push")
		else do gp_start("Push", "push", "-u", "origin", gp.branch)
	}
	UI_Tooltip("Send your commits to the remote (a branch without one: to origin)")
	if busy do imgui.EndDisabled()
	imgui.SameLine()
	if UI_IconButton(ICON_FA_ROTATE, "git.refresh", "Refresh", false, 26) do gp.dirty = true
	if busy {
		imgui.SameLine()
		UI_DimText(fmt.tprintf("%s...", gp.job.label))
	} else if gp.message != "" {
		imgui.SameLine()
		UI_DimText(gp.message)
	}
	Drive_Item("git.message")
}

@(private = "file")
gp_status_text :: proc(f: Git_File) -> (string, imgui.Vec4) {
	switch {
	case f.index == '?': return "new", CHANGE_ADDED
	case f.index == 'U' || f.work == 'U' || (f.index == 'A' && f.work == 'A') || (f.index == 'D' && f.work == 'D'): return "conflict", UI_WARNING
	case f.index == 'D' || f.work == 'D': return "deleted", CHANGE_DELETED
	case f.index == 'A': return "added", CHANGE_ADDED
	case f.index == 'R': return "renamed", CHANGE_MODIFIED
	}
	return "changed", CHANGE_MODIFIED
}

@(private = "file")
gp_changes :: proc(state: ^EditorState) {
	avail := imgui.GetContentRegionAvail()
	listW := min(avail.x * 0.4, 420)
	if imgui.BeginChild("##gitfiles", {listW, 0}, {}, {}) {
		if len(gp.files) == 0 do UI_DimText("No changes: everything is committed.")
		for f in gp.files {
			staged := f.index != ' ' && f.index != '?'
			imgui.PushID(fmt.ctprintf("%s", f.path))
			if imgui.Checkbox("##stage", &staged) {
				if staged do Git_Run(gp.root, "add", "--", f.path)
				else do Git_Run(gp.root, "reset", "-q", "HEAD", "--", f.path)
				gp.dirty = true
			}
			Drive_Item(fmt.tprintf("git.stage:%s", f.rel if f.rel != "" else f.path))
			UI_Tooltip("Staged: in the next commit")
			imgui.SameLine()
			label, col := gp_status_text(f)
			imgui.PushStyleColorImVec4(.Text, col)
			imgui.TextUnformatted(fmt.ctprintf("%-8s", label))
			imgui.PopStyleColor()
			imgui.SameLine()
			if imgui.Selectable(fmt.ctprintf("%s", f.rel if f.rel != "" else f.path), gp.selected == f.path) do gp_select(state, f.path)
			Drive_Item(fmt.tprintf("git.file:%s", f.rel if f.rel != "" else f.path))
			imgui.PopID()
		}
		imgui.Separator()
		imgui.SetNextItemWidth(-1)
		imgui.InputTextMultiline("##gitmsg", cstring(raw_data(gp.commitBuf[:])), uint(len(gp.commitBuf)), {-1, 60})
		Drive_Item("git.message-box")
		msg := strings.trim_space(string(cstring(raw_data(gp.commitBuf[:]))))
		stagedCount := 0
		for f in gp.files do if f.index != ' ' && f.index != '?' do stagedCount += 1
		canCommit := msg != "" && stagedCount > 0
		if !canCommit do imgui.BeginDisabled(true)
		if UI_PrimaryButton(fmt.tprintf("Commit %d file(s)", stagedCount), "git.commit") {
			if out, ok, _ := Git_Run(gp.root, "commit", "-q", "-m", msg); ok {
				gp_message("Committed: %s", strings.split_lines(msg, context.temp_allocator)[0])
				Editor_Log(state, .Info, "git commit: %s", msg)
				gp.commitBuf = {}
			} else do gp_message("Commit failed: %s", out)
			gp.dirty = true
		}
		if !canCommit do imgui.EndDisabled()
		UI_Tooltip("Commit the staged files (save your scenes first: the files on disk are committed)")
		imgui.SameLine()
		if UI_Button("Stage All", "git.stage-all") {
			Git_Run(gp.project, "add", "-A", "--", ".")
			gp.dirty = true
		}
		UI_Tooltip("Stage every change in the project's folder")
	}
	imgui.EndChild()
	imgui.SameLine()
	if imgui.BeginChild("##gitdiff", {0, 0}, {.Borders}, {}) {
		gp_diff()
	}
	imgui.EndChild()
}

@(private = "file")
gp_diff :: proc() {
	if gp.selected == "" {
		UI_DimText("Select a file to see its changes.")
		return
	}
	imgui.TextUnformatted(fmt.ctprintf("%s", gp.selected))
	Drive_Item("git.diff")
	if gp.diffIsScene {
		UI_DimText(fmt.tprintf("By node, from the last commit to the file on disk (%d change(s))", len(gp.diffNodes)))
		for c in gp.diffNodes {
			col: imgui.Vec4
			word: string
			switch c.kind {
			case .Added: col, word = CHANGE_ADDED, "added"
			case .Removed: col, word = CHANGE_DELETED, "removed"
			case .Changed: col, word = CHANGE_MODIFIED, "changed"
			case .Moved: col, word = CHANGE_MODIFIED, "moved"
			}
			imgui.PushStyleColorImVec4(.Text, col)
			imgui.TextUnformatted(fmt.ctprintf("%s  %s", ICON_FA_CUBE, c.name if c.name != "" else c.uid))
			imgui.PopStyleColor()
			imgui.SameLine()
			UI_DimText(word)
			for f in c.fields {
				imgui.Indent(24)
				imgui.TextUnformatted(fmt.ctprintf("%s", f.field))
				imgui.SameLine()
				UI_DimText(fmt.tprintf("%s  ->  %s", f.before if f.before != "" else "(none)", f.after if f.after != "" else "(none)"))
				imgui.Unindent(24)
			}
		}
		return
	}
	for line in strings.split_lines(gp.diffText, context.temp_allocator) {
		col := UI_TEXT_DIM
		switch {
		case strings.has_prefix(line, "+++") || strings.has_prefix(line, "---"):
		case strings.has_prefix(line, "+"): col = CHANGE_ADDED
		case strings.has_prefix(line, "-"): col = CHANGE_DELETED
		case strings.has_prefix(line, "@@"): col = CHANGE_MODIFIED
		}
		imgui.PushStyleColorImVec4(.Text, col)
		imgui.TextUnformatted(fmt.ctprintf("%s", line))
		imgui.PopStyleColor()
	}
}

@(private = "file")
gp_history :: proc(state: ^EditorState) {
	UI_DimText(fmt.tprintf("%s: the last %d commit(s)", gp.selected if gp.selected != "" else "the project", len(gp.history)))
	imgui.SameLine()
	if gp.selected != "" && UI_Button("Whole Project", "git.history-all") do gp_select(state, "")
	Drive_Item("git.history")
	if imgui.BeginTable("##githist", 4, imgui.TableFlags_RowBg | imgui.TableFlags_ScrollY | imgui.TableFlags_Resizable) {
		imgui.TableSetupColumn("Commit", {.WidthFixed}, 70)
		imgui.TableSetupColumn("Message", {.WidthStretch}, 1)
		imgui.TableSetupColumn("Author", {.WidthFixed}, 140)
		imgui.TableSetupColumn("When", {.WidthFixed}, 120)
		imgui.TableHeadersRow()
		for c in gp.history {
			imgui.TableNextRow()
			imgui.TableNextColumn(); UI_DimText(c.hash)
			imgui.TableNextColumn(); imgui.TextUnformatted(fmt.ctprintf("%s", c.subject))
			imgui.TableNextColumn(); imgui.TextUnformatted(fmt.ctprintf("%s", c.author))
			imgui.TableNextColumn(); UI_DimText(c.age)
		}
		imgui.EndTable()
	}
}

// GitPanel_DriveQuery: git.repo, git.branch, git.files, git.staged,
// git.diff-nodes, git.history, git.busy, git.message.
GitPanel_DriveQuery :: proc(q: string) -> (string, bool) {
	staged := 0
	for f in gp.files do if f.index != ' ' && f.index != '?' do staged += 1
	switch q {
	case "git.repo": return "true" if gp.isRepo else "false", true
	case "git.branch": return gp.branch, true
	case "git.files": return fmt.tprint(len(gp.files)), true
	case "git.staged": return fmt.tprint(staged), true
	case "git.diff-nodes": return fmt.tprint(len(gp.diffNodes)) if gp.diffIsScene else "-1", true
	case "git.history": return fmt.tprint(len(gp.history)), true
	case "git.busy": return "true" if gp.job != nil else "false", true
	case "git.message": return gp.message, true
	}
	return "", false
}
