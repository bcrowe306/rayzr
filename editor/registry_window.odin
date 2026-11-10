package editor

import "core:fmt"
import vmem "core:mem/virtual"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import e "../engine"
import imgui "lib/imgui"
import rl "vendor:raylib"

// ============================================================================
// Tools > Registry (#296; registry.odin has the index and installing): browse
// the registry's plugins and templates - search, a kind filter, a list, and
// the selected one's details (screenshot, description, license, links, its
// README once installed) with Install / Update / Remove.
//
// - The index is fetched in the background (curl; file:// and local paths
//   are read directly) and kept in <user config>/registry/index.json: the
//   window shows that copy at once, and offline it's what you get (with a
//   note). It's fetched again when older than an hour, or on Refresh.
// - Installing a plugin asks first (who made it, its repo, license and
//   permissions; plugins run code in the editor) and where: your plugins
//   folder (every project) or this project's plugins/. Templates install
//   without asking into your templates folder (Welcome > New Project).
// ============================================================================

REGISTRY_REFRESH :: time.Hour

@(private = "file")
Registry_Job :: struct {
	url, dest: string,
	err:       string, // "" = ok
	done:      bool,
	thread:    ^thread.Thread,
	// what it's for
	id:        string, // an entry (a download)
	project:   bool,   // install into this project
}

@(private = "file")
registry: struct {
	open:       bool,
	focus:      bool,
	arena:      vmem.Arena, // the index's entries
	index:      Registry_Index,
	loaded:     bool,
	status:     string, // "" | why the list is old / missing (heap)
	fetch:      ^Registry_Job,
	download:   ^Registry_Job,
	shotJob:    ^Registry_Job,
	shots:      map[string]^rl.Texture2D, // screenshot url -> texture (id 0: failed)
	search:     [128]u8,
	kind:       int, // 0 all, 1 plugins, 2 templates
	selected:   string,
	confirm:    string, // the plugin the install dialog is for
	confirmProj: bool,  // ... into this project
	askOpen:    bool,   // open the dialog (at the window's level: its popup id)
	readme:     Md_Doc,
	readmeFor:  string, // the folder readme was read from
	urlOverride: string, // a drive's fixture index (registry-url)
}

// Registry_IndexURL: the index this editor reads (Settings > General >
// Registry Index; RAYZR_REGISTRY_URL; a drive's registry-url).
Registry_IndexURL :: proc() -> string {
	if registry.urlOverride != "" do return registry.urlOverride
	if u := os.get_env("RAYZR_REGISTRY_URL", context.temp_allocator); u != "" do return u
	if GlobalSettings.registryUrl != "" do return GlobalSettings.registryUrl
	return REGISTRY_INDEX_URL
}

// Registry_SetURL: a drive's fixture index (it's fetched again).
Registry_SetURL :: proc(url: string) {
	delete(registry.urlOverride)
	registry.urlOverride = strings.clone(url)
	registry.loaded = false
}

// Registry_Open shows the window (kind: 1 plugins, 2 templates, 0 all).
Registry_Open :: proc(state: ^EditorState, kind := -1) {
	registry.open = true
	registry.focus = true
	if kind >= 0 do registry.kind = kind
	if !registry.loaded do registry_load(state, false)
}

@(private = "file")
registry_cache :: proc(state: ^EditorState, rel: string = "") -> string {
	dir := Editor_UserDir("registry", state.userDataDir)
	if rel == "" do return dir
	p, _ := filepath.join({dir, rel}, context.temp_allocator)
	return p
}

// Registry_PluginRoot: where plugins install (the user's folder, or the
// project's plugins/).
Registry_PluginRoot :: proc(state: ^EditorState, project: bool) -> string {
	if project {
		p, _ := filepath.join({state.projectPath, "plugins"}, context.temp_allocator)
		return p
	}
	return Plugins_UserDir()
}

// Registry_TemplateRoot: where templates install (Welcome lists them).
Registry_TemplateRoot :: proc() -> string {
	return Editor_UserDir("templates", GlobalEditor.userDataDir)
}

// registry_load shows the cached index, and fetches it again when it's old
// (or `force`: Refresh).
@(private = "file")
registry_load :: proc(state: ^EditorState, force: bool) {
	cached := registry_cache(state, "index.json")
	source := registry_cache(state, "index.source") // the url the cache came from
	src, _ := os.read_entire_file(source, context.temp_allocator)
	sameURL := string(src) == Registry_IndexURL()
	if sameURL && registry_read(cached) {
		registry.loaded = true
		info, err := os.stat(cached, context.temp_allocator)
		if !force && err == nil && time.since(info.modification_time) < REGISTRY_REFRESH do return
	} else {
		registry_clear()
	}
	registry.loaded = true
	if registry.fetch != nil do return
	_ = os.make_directory_all(registry_cache(state))
	registry.fetch = registry_start(Registry_IndexURL(), strings.concatenate({cached, ".part"}, context.temp_allocator))
}

@(private = "file")
registry_clear :: proc() {
	vmem.arena_destroy(&registry.arena)
	registry.arena = {}
	registry.index = {}
}

// registry_read parses an index file into the window (false: none / bad).
@(private = "file")
registry_read :: proc(path: string) -> bool {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil do return false
	registry_clear()
	if vmem.arena_init_growing(&registry.arena) != nil do return false
	idx, perr, ok := Registry_ParseIndex(data, Registry_IndexURL(), vmem.arena_allocator(&registry.arena))
	if !ok {
		registry_set_status(fmt.tprintf("The registry index can't be read: %s", perr))
		return false
	}
	registry.index = idx
	return true
}

@(private = "file")
registry_set_status :: proc(s: string) {
	delete(registry.status)
	registry.status = strings.clone(s)
}

// registry_start fetches `url` into `dest` on a thread.
@(private = "file")
registry_start :: proc(url, dest: string) -> ^Registry_Job {
	job := new(Registry_Job)
	job.url = strings.clone(url)
	job.dest = strings.clone(dest)
	job.thread = thread.create_and_start_with_poly_data(job, proc(job: ^Registry_Job) {
		job.err = registry_fetch(job.url, job.dest)
		sync.atomic_store(&job.done, true)
	})
	return job
}

// registry_fetch copies a url into `dest` (heap error, "" = ok). file://
// urls and plain paths are read directly; the rest by curl.
@(private = "file")
registry_fetch :: proc(url, dest: string) -> string {
	_ = os.make_directory_all(filepath.dir(dest, context.temp_allocator))
	local := ""
	if strings.has_prefix(url, "file://") {
		local = url[len("file://"):]
		// (file:///C:/... on Windows.)
		if len(local) > 2 && local[0] == '/' && local[2] == ':' do local = local[1:]
	} else if !strings.contains(url, "://") {
		local = url
	}
	if local != "" {
		data, err := os.read_entire_file(local, context.allocator)
		if err != nil do return fmt.aprintf("can't read %s (%v)", local, err)
		defer delete(data)
		if werr := os.write_entire_file(dest, data); werr != nil do return fmt.aprintf("can't write %s (%v)", dest, werr)
		return ""
	}
	_ = os.remove(dest)
	cmd := []string{"curl", "-fsSL", "--connect-timeout", "15", "-m", "300", "-o", dest, url}
	st, out, errOut, err := os.process_exec({command = cmd}, context.allocator)
	defer {delete(out); delete(errOut)}
	if err != nil do return fmt.aprintf("couldn't run curl: %v", err)
	if st.exit_code != 0 {
		_ = os.remove(dest)
		msg := strings.trim_space(string(errOut))
		return strings.clone(msg if msg != "" else fmt.tprintf("curl failed (%d)", st.exit_code))
	}
	return ""
}

@(private = "file")
registry_take :: proc(job: ^^Registry_Job) -> ^Registry_Job {
	j := job^
	if j == nil || !sync.atomic_load(&j.done) do return nil
	job^ = nil
	thread.join(j.thread)
	thread.destroy(j.thread)
	return j
}

@(private = "file")
registry_free :: proc(j: ^Registry_Job) {
	delete(j.url); delete(j.dest); delete(j.err); delete(j.id)
	free(j)
}

// Registry_Update: finished fetches and downloads (every frame).
Registry_Update :: proc(state: ^EditorState) {
	if j := registry_take(&registry.fetch); j != nil {
		defer registry_free(j)
		final := strings.trim_suffix(j.dest, ".part")
		if j.err == "" {
			_ = os.remove(final)
			_ = os.rename(j.dest, final)
			if registry_read(final) {
				registry_set_status("")
				url := Registry_IndexURL()
				_ = os.write_entire_file(registry_cache(state, "index.source"), transmute([]u8)url)
				for w in registry.index.warnings do Editor_Log(state, .Warn, "Registry: skipped %s", w)
			}
		} else {
			when_ := ""
			if info, err := os.stat(final, context.temp_allocator); err == nil && len(registry.index.entries) > 0 {
				when_ = fmt.tprintf(": showing the list from %s", registry_date(info.modification_time))
			}
			registry_set_status(fmt.tprintf("Offline - the registry couldn't be reached (%s)%s", j.err, when_))
			Editor_Log(state, .Warn, "Registry: couldn't fetch %s (%s)", j.url, j.err)
		}
	}
	if j := registry_take(&registry.download); j != nil {
		defer registry_free(j)
		defer _ = os.remove(j.dest)
		en, found := registry_entry(j.id)
		switch {
		case j.err != "":
			Editor_Log(state, .Error, "Registry: couldn't download %s (%s)", j.id, j.err)
		case !found:
			Editor_Log(state, .Error, "Registry: %s isn't in the index any more", j.id)
		case:
			data, _ := os.read_entire_file(j.dest, context.temp_allocator)
			root := Registry_PluginRoot(state, j.project) if en.kind == .Plugin else Registry_TemplateRoot()
			if err := Registry_Install(en, data, root); err != "" {
				Editor_Log(state, .Error, "Registry: %s wasn't installed: %s", en.name, err)
			} else {
				where_ := "your templates (Welcome > New Project)"
				if en.kind == .Plugin do where_ = "this project's plugins" if j.project else "your plugins (every project)"
				Editor_Log(state, .Info, "Registry: installed %s %s into %s", en.name, en.version, where_)
				if en.kind == .Plugin {
					Plugins_Load(state, ask = false)
					if j.project && !(Plugins_Trusted().? or_else false) {
						Editor_Log(state, .Warn, "Registry: this project's plugins aren't allowed yet - Settings > Plugins > Allow runs %s", en.name)
					}
				}
			}
		}
		registry_forget_readme() // (read again)
	}
	if j := registry_take(&registry.shotJob); j != nil {
		defer registry_free(j)
		tex := new(rl.Texture2D)
		if j.err == "" do tex^ = rl.LoadTexture(strings.clone_to_cstring(j.dest, context.temp_allocator))
		if tex.id != 0 do rl.SetTextureFilter(tex^, .BILINEAR)
		registry.shots[strings.clone(j.url)] = tex
	}
}

@(private = "file")
registry_forget_readme :: proc() {
	delete(registry.readmeFor)
	registry.readmeFor = ""
}

@(private = "file")
registry_date :: proc(t: time.Time) -> string {
	y, m, d := time.date(t)
	return fmt.tprintf("%d-%02d-%02d", y, int(m), d)
}

@(private = "file")
registry_entry :: proc(id: string) -> (Registry_Entry, bool) {
	for en in registry.index.entries do if en.id == id do return en, true
	return {}, false
}

// registry_installed: where the entry is installed from the registry (the
// project's plugins first) and its version ("" = not).
@(private = "file")
registry_installed :: proc(state: ^EditorState, en: Registry_Entry) -> (version, dir: string, project: bool) {
	if en.kind == .Template {
		root := Registry_TemplateRoot()
		v := Registry_InstalledVersion(root, en.id)
		p, _ := filepath.join({root, en.id}, context.temp_allocator)
		return v, p if v != "" else "", false
	}
	for proj in ([]bool{true, false}) {
		root := Registry_PluginRoot(state, proj)
		if v := Registry_InstalledVersion(root, en.id); v != "" {
			p, _ := filepath.join({root, en.id}, context.temp_allocator)
			return v, p, proj
		}
	}
	return "", "", false
}

@(private = "file")
registry_start_install :: proc(state: ^EditorState, en: Registry_Entry, project: bool) {
	if registry.download != nil do return
	dest := registry_cache(state, fmt.tprintf("downloads/%s-%s.zip", en.id, en.version))
	j := registry_start(en.url, dest)
	j.id = strings.clone(en.id)
	j.project = project
	registry.download = j
	Editor_Log(state, .Info, "Registry: downloading %s %s", en.name, en.version)
}

@(private = "file")
registry_matches :: proc(en: Registry_Entry) -> bool {
	if registry.kind == 1 && en.kind != .Plugin do return false
	if registry.kind == 2 && en.kind != .Template do return false
	q := strings.trim_space(string(cstring(raw_data(registry.search[:]))))
	if q == "" do return true
	q = strings.to_lower(q, context.temp_allocator)
	hay := strings.to_lower(strings.join({en.id, en.name, en.author, en.description, strings.join(en.tags, " ", context.temp_allocator)}, " ", context.temp_allocator), context.temp_allocator)
	for word in strings.fields(q, context.temp_allocator) do if !strings.contains(hay, word) do return false
	return true
}

// Registry_Render: the window and its install dialog (every frame).
Registry_Render :: proc(state: ^EditorState) {
	Registry_Update(state)
	if !registry.open do return
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	imgui.SetNextWindowSize({900, 600}, .Appearing)
	if registry.focus {
		imgui.SetNextWindowFocus()
		registry.focus = false
	}
	defer imgui.End()
	if !imgui.Begin(fmt.ctprintf("%s  Registry###RegistryWindow", ICON_FA_PUZZLE_PIECE), &registry.open, {.NoCollapse, .NoDocking}) do return
	Drive_Window("registry")
	PanelHelp_Mark("registry")

	// --- the top bar: search, kinds, refresh ---
	imgui.SetNextItemWidth(260)
	imgui.InputTextWithHint("##regsearch", "Search plugins and templates", cstring(raw_data(registry.search[:])), len(registry.search))
	Drive_Item("registry.search")
	kinds := [3]string{"All", "Plugins", "Templates"}
	for k, i in kinds {
		imgui.SameLine()
		if imgui.RadioButton(fmt.ctprintf("%s##regkind%d", k, i), registry.kind == i) do registry.kind = i
		Drive_Item(fmt.tprintf("registry.kind:%s", strings.to_lower(k, context.temp_allocator)))
	}
	imgui.SameLine(imgui.GetWindowWidth() - 110)
	imgui.BeginDisabled(registry.fetch != nil)
	if UI_Button(fmt.tprintf("%s  Refresh", ICON_FA_ROTATE_RIGHT), "registry.refresh", {100, 0}) do registry_load(state, true)
	imgui.EndDisabled()
	UI_Tooltip(fmt.tprintf("Fetch the list again (%s)", Registry_IndexURL()))
	if registry.fetch != nil do UI_DimText("Fetching the registry...")
	if registry.status != "" {
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextWrapped("%s", strings.clone_to_cstring(registry.status, context.temp_allocator))
		imgui.PopStyleColor()
		Drive_Item("registry.status")
	}
	imgui.Separator()

	// --- the list ---
	shown := 0
	if imgui.BeginChild("##reglist", {300, -4}, {.Borders}, {}) {
		for en in registry.index.entries {
			if !registry_matches(en) do continue
			shown += 1
			if registry.selected == "" do registry.selected = strings.clone(en.id)
			ver, _, _ := registry_installed(state, en)
			mark := ""
			switch {
			case ver != "" && e.Version_Compare(en.version, ver) > 0: mark = "  " + ICON_FA_ARROW_UP
			case ver != "": mark = "  " + ICON_FA_CHECK
			}
			icon := ICON_FA_PUZZLE_PIECE if en.kind == .Plugin else ICON_FA_FILE
			compat := Registry_Compatible(en, e.RAYZR_RELEASE)
			if !compat do imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
			if imgui.Selectable(fmt.ctprintf("%s  %s%s##reg_%s", icon, en.name, mark, en.id), registry.selected == en.id, {}, {0, 22}) {
				delete(registry.selected)
				registry.selected = strings.clone(en.id)
			}
			if !compat do imgui.PopStyleColor()
			Drive_Item(fmt.tprintf("registry.item:%s", en.id))
			UI_Tooltip(en.description)
		}
		if shown == 0 {
			if len(registry.index.entries) == 0 {
				UI_DimTextWrapped("Nothing to show yet." if registry.fetch != nil else "The registry has nothing to show (it couldn't be fetched, or it's empty).")
			} else {
				UI_DimText("Nothing matches.")
			}
		}
	}
	imgui.EndChild()
	imgui.SameLine()

	// --- the details ---
	if imgui.BeginChild("##regdetail", {0, -4}, {.Borders}, {}) {
		if en, ok := registry_entry(registry.selected); ok && registry_matches(en) {
			registry_details(state, en)
		} else {
			UI_DimText("Select a plugin or template.")
		}
	}
	imgui.EndChild()
	registry_confirm(state)
}

@(private = "file")
registry_details :: proc(state: ^EditorState, en: Registry_Entry) {
	ver, dir, inProject := registry_installed(state, en)
	compat := Registry_Compatible(en, e.RAYZR_RELEASE)
	imgui.PushFont(GlobalFonts.semibold)
	imgui.TextUnformatted(strings.clone_to_cstring(fmt.tprintf("%s  %s", en.name, en.version), context.temp_allocator))
	imgui.PopFont()
	Drive_Item("registry.detail.name")
	by := fmt.tprintf("%s by %s", "Plugin" if en.kind == .Plugin else "Template", en.author if en.author != "" else "(unknown)")
	if en.license != "" do by = fmt.tprintf("%s  -  %s license", by, en.license)
	UI_DimText(by)

	// Actions.
	busy := registry.download != nil
	imgui.BeginDisabled(busy || !compat)
	switch {
	case ver == "":
		if UI_PrimaryButton(fmt.tprintf("%s  Install", ICON_FA_ARROW_DOWN), "registry.install") do registry_ask(state, en, false)
	case e.Version_Compare(en.version, ver) > 0:
		if UI_PrimaryButton(fmt.tprintf("%s  Update to %s", ICON_FA_ARROW_UP, en.version), "registry.update") do registry_ask(state, en, inProject)
	}
	imgui.EndDisabled()
	if ver != "" {
		if ver != "" && e.Version_Compare(en.version, ver) > 0 do imgui.SameLine()
		imgui.BeginDisabled(busy)
		if UI_Button(fmt.tprintf("%s  Remove", ICON_FA_TRASH), "registry.remove") {
			root := filepath.dir(dir, context.temp_allocator)
			if err := Registry_Uninstall(root, en.id); err != "" {
				Editor_Log(state, .Error, "Registry: %s wasn't removed: %s", en.name, err)
			} else {
				Editor_Log(state, .Info, "Registry: removed %s", en.name)
				if en.kind == .Plugin do Plugins_Load(state, ask = false)
				registry_forget_readme()
			}
		}
		imgui.EndDisabled()
		UI_Tooltip(fmt.tprintf("Delete %s", dir))
		imgui.SameLine()
		if UI_Button(fmt.tprintf("%s  Open Folder", ICON_FA_FOLDER_OPEN), "registry.folder") do Editor_OpenExternally(state, dir)
	}
	if en.repo != "" || en.homepage != "" {
		imgui.SameLine()
		page := en.homepage if en.homepage != "" else fmt.tprintf("https://github.com/%s", en.repo)
		if UI_Button(fmt.tprintf("%s  Page", ICON_FA_LINK), "registry.page") do Editor_OpenExternally(state, page)
		UI_Tooltip(page)
	}
	switch {
	case busy: UI_DimText(fmt.tprintf("Downloading %s...", registry.download.id))
	case !compat: UI_DimText(fmt.tprintf("Needs Rayzr Editor %s or newer (this is %s).", en.rayzr, e.RAYZR_RELEASE))
	case ver != "" && e.Version_Compare(en.version, ver) > 0: UI_DimText(fmt.tprintf("Installed: %s%s.", ver, " (this project)" if inProject else ""))
	case ver != "": UI_DimText(fmt.tprintf("Installed%s.", " in this project" if inProject else (" for every project" if en.kind == .Plugin else "")))
	}
	Drive_Item("registry.detail.state")
	imgui.Spacing()

	// The screenshot (fetched once, cached).
	if en.screenshot != "" {
		if tex, has := registry.shots[en.screenshot]; has {
			if tex.id != 0 {
				// (At most 200 high: the description and README stay in view.)
				w := min(imgui.GetContentRegionAvail().x, 480)
				h := w * f32(tex.height) / f32(max(tex.width, 1))
				if h > 200 {
					w *= 200 / h
					h = 200
				}
				imgui.Image(transmute(imgui.TextureID)tex, {w, h})
				Drive_Item("registry.screenshot")
			}
		} else if registry.shotJob == nil {
			ext := filepath.ext(en.screenshot)
			if ext == "" || len(ext) > 5 do ext = ".png"
			dest := registry_cache(state, fmt.tprintf("screens/%s%s", Registry_SHA256(transmute([]u8)en.screenshot)[:16], ext))
			if os.is_file(dest) {
				tex := new(rl.Texture2D)
				tex^ = rl.LoadTexture(strings.clone_to_cstring(dest, context.temp_allocator))
				if tex.id != 0 do rl.SetTextureFilter(tex^, .BILINEAR)
				registry.shots[strings.clone(en.screenshot)] = tex
			} else {
				registry.shotJob = registry_start(en.screenshot, dest)
			}
		}
	}
	imgui.PushTextWrapPos(0)
	imgui.TextUnformatted(strings.clone_to_cstring(en.description, context.temp_allocator))
	imgui.PopTextWrapPos()
	if len(en.tags) > 0 do UI_DimText(fmt.tprintf("Tags: %s", strings.join(en.tags, ", ", context.temp_allocator)))
	if en.kind == .Plugin {
		UI_DimText(fmt.tprintf("Permissions: %s", strings.join(en.permissions, ", ", context.temp_allocator) if len(en.permissions) > 0 else "none (it can't run programs or use the network)"))
	}
	if en.repo != "" do UI_DimText(fmt.tprintf("Source: github.com/%s", en.repo))

	// Its README, once installed.
	if dir != "" {
		if registry.readmeFor != dir {
			Md_Destroy(&registry.readme)
			registry.readme = {}
			delete(registry.readmeFor)
			registry.readmeFor = strings.clone(dir)
			p, _ := filepath.join({dir, "README.md"}, context.temp_allocator)
			if data, err := os.read_entire_file(p, context.temp_allocator); err == nil do registry.readme = Md_Parse(string(data))
		}
		if len(registry.readme.blocks) > 0 {
			imgui.Separator()
			if url := Md_Draw(&registry.readme); url != "" && strings.contains(url, "://") do Editor_OpenExternally(state, url)
		}
	} else {
		imgui.Spacing()
		UI_DimText("Its README shows here once it's installed.")
	}
}

// registry_ask: a plugin asks first (the dialog); a template installs.
@(private = "file")
registry_ask :: proc(state: ^EditorState, en: Registry_Entry, project: bool) {
	if en.kind == .Template {
		registry_start_install(state, en, false)
		return
	}
	delete(registry.confirm)
	registry.confirm = strings.clone(en.id)
	registry.confirmProj = project
	registry.askOpen = true
}

// registry_confirm: the install dialog - what the plugin is, what it may do,
// and where it goes.
@(private = "file")
registry_confirm :: proc(state: ^EditorState) {
	if registry.askOpen {
		registry.askOpen = false
		imgui.OpenPopup("Install Plugin?###RegistryConfirm")
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if !imgui.BeginPopupModal("Install Plugin?###RegistryConfirm", nil, {.AlwaysAutoResize}) do return
	defer imgui.EndPopup()
	Drive_Window("registry-confirm")
	en, ok := registry_entry(registry.confirm)
	if !ok {
		imgui.CloseCurrentPopup()
		return
	}
	imgui.PushFont(GlobalFonts.semibold)
	imgui.TextUnformatted(strings.clone_to_cstring(fmt.tprintf("%s %s", en.name, en.version), context.temp_allocator))
	imgui.PopFont()
	UI_DimText(fmt.tprintf("By %s%s", en.author if en.author != "" else "(unknown)", fmt.tprintf(" - github.com/%s", en.repo) if en.repo != "" else ""))
	UI_DimText(fmt.tprintf("License: %s", en.license if en.license != "" else "(none given)"))
	imgui.Spacing()
	imgui.PushStyleColorImVec4(.Text, UI_WARNING)
	imgui.TextUnformatted("Plugins are code that runs in your editor.")
	imgui.PopStyleColor()
	UI_DimText("Only install plugins from people you trust. The download must")
	UI_DimText("match the registry's SHA-256, or nothing is installed.")
	for p in en.permissions {
		switch p {
		case "process": imgui.BulletText("It can run programs on this computer.")
		case "network": imgui.BulletText("It can use the network.")
		case: imgui.BulletText("%s", fmt.ctprintf("It asks for %q.", p))
		}
	}
	if len(en.permissions) == 0 do imgui.BulletText("It can't run programs or use the network.")
	imgui.Spacing()
	if imgui.RadioButton("For every project (your plugins folder)", !registry.confirmProj) do registry.confirmProj = false
	Drive_Item("registry.confirm.user")
	if imgui.RadioButton("Only this project (its plugins/ folder, shared with it)", registry.confirmProj) do registry.confirmProj = true
	Drive_Item("registry.confirm.project")
	imgui.Spacing()
	if UI_PrimaryButton(fmt.tprintf("%s  Install", ICON_FA_ARROW_DOWN), "registry.confirm.install") {
		registry_start_install(state, en, registry.confirmProj)
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Cancel", "registry.confirm.cancel") do imgui.CloseCurrentPopup()
}

// Registry_DriveQuery: "registry.count" (entries listed), ".status",
// ".busy", ".open", ".templates" (Welcome's), ".<id>" (the installed version, "" = none; "<v> project" when in
// this project's plugins).
Registry_DriveQuery :: proc(state: ^EditorState, q: string) -> (string, bool) {
	rest := q[len("registry."):]
	switch rest {
	case "count":
		n := 0
		for en in registry.index.entries do if registry_matches(en) do n += 1
		return fmt.tprint(n), true
	case "status": return registry.status, true
	case "busy": return "true" if registry.download != nil || registry.fetch != nil else "false", true
	case "open": return "true" if registry.open else "false", true
	case "templates": // the Welcome window's choices
		names := make([dynamic]string, context.temp_allocator)
		for t in Templates_List() do append(&names, t.name)
		return strings.join(names[:], ", ", context.temp_allocator), true
	}
	en, ok := registry_entry(rest)
	if !ok do return "missing", true
	ver, _, proj := registry_installed(state, en)
	return fmt.tprintf("%s project", ver) if proj && ver != "" else ver, true
}

// Registry_Shutdown frees the window's state (quit).
Registry_Shutdown :: proc() {
	for j in ([]^^Registry_Job{&registry.fetch, &registry.download, &registry.shotJob}) {
		if j^ == nil do continue
		thread.join(j^.thread)
		thread.destroy(j^.thread)
		registry_free(j^)
		j^ = nil
	}
	for k, tex in registry.shots {
		if tex.id != 0 do rl.UnloadTexture(tex^)
		free(tex)
		delete(k)
	}
	delete(registry.shots)
	Md_Destroy(&registry.readme)
	registry_clear()
	delete(registry.status); delete(registry.selected); delete(registry.confirm)
	delete(registry.readmeFor); delete(registry.urlOverride)
	registry = {}
}
