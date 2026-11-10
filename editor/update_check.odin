package editor

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Updates (TODO D.9, #291): at startup (Settings > General > Check for
// Updates, on by default) and from Help > Check for Updates, the downloads
// site's manifest (downloads.rayzr.app/manifest.json: scripts/ci/publish_r2.py)
// is read (curl, on a thread) and compared with this editor's version
// (RAYZR_RELEASE). Dev builds (<x.y.z>-dev.<n>, one per merge to main:
// release.yml) see the newest dev build and releases; releases see releases
// (a beta sees betas too).
//
// A newer one is downloaded in the background (Download Updates
// Automatically, on by default; else the status bar's button), checked
// against the manifest's SHA-256 and unpacked next to the install
// (update_install.odin). The status bar then shows "Restart to update":
// it asks about unsaved work as quitting does, swaps the install (the old
// version is kept for Help > Roll Back) and starts the new one. Quitting
// installs it too. A .deb (root-owned /opt) is downloaded, verified and
// opened instead; development builds (a source checkout) only link the
// release page.
//
// Not in local builds (0.0.0-dev) or test drives unless asked
// (RAYZR_UPDATE_URL points it at another manifest: tests; the drives'
// update-fake command).
// ============================================================================

UPDATE_MANIFEST_URL :: "https://downloads.rayzr.app/manifest.json"

// A package in the manifest (entry.files[]).
Update_File :: struct {
	name, os, kind, sha256, url: string,
	size:                        i64,
}

// A version in the manifest (stable[] or dev).
Update_Entry :: struct {
	version, notes: string,
	files:          []Update_File,
}

Update_State :: enum {
	None,
	Available,   // newer, not downloaded (auto-download off, or no in-place install)
	Downloading, // (and verifying, unpacking)
	Ready,       // staged: "Restart to update" (a .deb: open it)
	Installed,   // swapped (drives; a real install restarts)
	Failed,
}

@(private = "file")
Update_Job :: struct {
	url:    string,
	output: string,
	ok:     bool,
	done:   bool,
	thread: ^thread.Thread,
}

@(private)
update: struct {
	job:      ^Update_Job,
	manual:   bool,   // asked from the Help menu: say "up to date" too
	state:    Update_State,
	version:  string, // a newer release ("" = none)
	page:     string, // its release notes
	file:     Update_File, // its package for this install (name "" = none; heap)
	install:  Update_Install,
	dl:       ^Update_Download_Job,
	pkgPath:  string, // the verified download
	staged:   string, // the unpacked replacement ("" for a .deb)
	err:      string,
	progress: f32, // 0..1 while downloading
	restart:  bool, // Restart to update: quit, install, start the new one
	rollback: bool, // Help > Roll Back: quit, swap back, start the old one
	current:  string, // the version compared with ("" = RAYZR_RELEASE; drives)
}

// (A hidden / automated editor: no update of its own.)
@(private)
update_headless :: proc() -> bool {
	for a in os.args do if a == "--hidden" || a == "--test-e2e" || a == "--test" do return true
	return false
}

@(private)
update_current :: proc() -> string {
	return update.current if update.current != "" else e.RAYZR_RELEASE
}

// UpdateCheck_Start reads the manifest in the background (manual: from the
// menu - also in development builds, and reports "up to date").
UpdateCheck_Start :: proc(manual := false) {
	if update.job != nil || update.state == .Downloading || update.state == .Ready do return
	update_report_last_error()
	url := os.get_env("RAYZR_UPDATE_URL", context.temp_allocator)
	if url == "" {
		if !manual && (e.Version_IsDev(e.RAYZR_RELEASE) || GlobalDrive.enabled || !GlobalSettings.checkUpdates || update_headless()) do return
		url = UPDATE_MANIFEST_URL
	}
	update_start_check(url, manual)
}

@(private)
update_start_check :: proc(url: string, manual: bool) {
	update.manual = manual
	job := new(Update_Job)
	job.url = strings.clone(url)
	job.thread = thread.create_and_start_with_poly_data(job, proc(job: ^Update_Job) {
		cmd := []string{"curl", "-fsSL", "-m", "15", job.url}
		st, out, errOut, err := os.process_exec({command = cmd}, context.allocator)
		delete(errOut)
		if err == nil && st.exit_code == 0 {
			job.output = string(out)
			job.ok = true
		} else {
			delete(out)
		}
		sync.atomic_store(&job.done, true)
	})
	update.job = job
}

// UpdateCheck_Poll takes a finished check or download (every frame).
UpdateCheck_Poll :: proc(state: ^EditorState) {
	update_poll_download(state)
	// Restart to update, then Cancel in the unsaved-changes prompt: not now.
	if (update.restart || update.rollback) && !state.quitRequested && !state.quitConfirmed {
		update.restart = false
		update.rollback = false
	}
	job := update.job
	if job == nil || !sync.atomic_load(&job.done) do return
	update.job = nil
	defer {
		thread.join(job.thread)
		thread.destroy(job.thread)
		delete(job.url)
		delete(job.output)
		free(job)
	}
	entry, ok := Update_PickEntry(job.output, update_current())
	if !job.ok || !ok {
		if update.manual do Editor_Log(state, .Warn, "Could not check for updates (offline?)")
		return
	}
	if e.Version_Compare(entry.version, update_current()) <= 0 {
		if update.manual do Editor_Log(state, .Info, "Rayzr Editor %s is up to date", update_current())
		return
	}
	update_set_string(&update.version, strings.trim_prefix(entry.version, "v"))
	update_set_string(&update.page, entry.notes)
	update_file_delete(&update.file)
	update.install = Update_Detect()
	if f, found := Update_PickFile(entry, Update_PlatformName(), update.install.kind); found {
		update.file = update_file_clone(f)
	}
	update.state = .Available
	Editor_Log(state, .Info, "Rayzr Editor %s is available (this is %s): %s", update.version, update_current(), update.page)
	if GlobalSettings.autoDownloadUpdates && update.file.name != "" do Update_Download(state)
}

// UpdateCheck_Available: a newer release's version ("" = none) and page.
UpdateCheck_Available :: proc() -> (version, page: string) {
	return update.version, update.page
}

// Update_PickEntry reads the manifest and picks the newest version this
// build should be offered (the strings are temp): dev builds see the dev
// build and releases, betas see betas too, releases only full releases.
// ok = a version was found (it may not be newer: the caller compares).
Update_PickEntry :: proc(text, current: string) -> (best: Update_Entry, ok: bool) {
	v, err := json.parse_string(text, allocator = context.temp_allocator)
	if err != nil do return
	m := v.(json.Object) or_return
	devBuild := strings.contains(current, "-dev.")
	pre := e.Version_IsPrerelease(current)
	consider :: proc(best: ^Update_Entry, ok: ^bool, o: json.Object) {
		ver := o["version"].(json.String) or_else ""
		if ver == "" do return
		if ok^ && e.Version_Compare(ver, best.version) <= 0 do return
		files := make([dynamic]Update_File, context.temp_allocator)
		if arr, isArr := o["files"].(json.Array); isArr {
			for item in arr {
				f := item.(json.Object) or_continue
				append(&files, Update_File{
					name = f["name"].(json.String) or_else "",
					os = f["os"].(json.String) or_else "",
					kind = f["kind"].(json.String) or_else "",
					sha256 = f["sha256"].(json.String) or_else "",
					url = f["url"].(json.String) or_else "",
					size = i64(f["size"].(json.Float) or_else f64(f["size"].(json.Integer) or_else 0)),
				})
			}
		}
		best^ = {version = ver, notes = o["notes_url"].(json.String) or_else "", files = files[:]}
		ok^ = true
	}
	if stable, isArr := m["stable"].(json.Array); isArr {
		for item in stable {
			o := item.(json.Object) or_continue
			if (o["prerelease"].(json.Boolean) or_else false) && !pre do continue
			consider(&best, &ok, o)
		}
	}
	if devBuild {
		if dev, isObj := m["dev"].(json.Object); isObj do consider(&best, &ok, dev)
	}
	return
}

// Update_PickFile: the entry's package for this platform and install kind
// (a .deb install gets the .deb; no install: the platform's usual package,
// only to link).
Update_PickFile :: proc(entry: Update_Entry, platform: string, kind: Update_Kind) -> (Update_File, bool) {
	want := Update_KindPackage(kind)
	for f in entry.files {
		if f.os != platform || f.url == "" || f.sha256 == "" do continue
		if want == "" || f.kind == want do return f, true
	}
	return {}, false
}

// Update_Download starts (or retries) the download of the picked package.
Update_Download :: proc(state: ^EditorState) {
	if update.file.name == "" || update.dl != nil do return
	if update.install.kind == .None {
		if update.page != "" do Editor_OpenExternally(state, update.page)
		return
	}
	dir := Update_Dir(state.userDataDir)
	update.dl = update_download_start(update.file, update.install, update.version, dir)
	update.state = .Downloading
	update.progress = 0
	update_set_string(&update.err, "")
	Editor_Log(state, .Info, "Downloading Rayzr Editor %s (%s)", update.version, update.file.name)
}

@(private = "file")
update_poll_download :: proc(state: ^EditorState) {
	dl := update.dl
	if dl == nil do return
	if !sync.atomic_load(&dl.done) {
		// Progress: the partial file's size (every 10 frames).
		if update.file.size > 0 && update_tick() % 10 == 0 {
			if fi, err := os.stat(dl.part, context.temp_allocator); err == nil {
				update.progress = clamp(f32(fi.size) / f32(update.file.size), 0, 1)
			}
		}
		return
	}
	update.dl = nil
	defer update_download_free(dl)
	if dl.err != "" {
		update.state = .Failed
		update_set_string(&update.err, dl.err)
		update_set_string(&update.pkgPath, dl.pkgPath)
		Editor_Log(state, .Warn, "Rayzr Editor %s: the update failed: %s", update.version, dl.err)
		return
	}
	update_set_string(&update.pkgPath, dl.pkgPath)
	update_set_string(&update.staged, dl.staged)
	update.state = .Ready
	update.progress = 1
	if update.install.kind == .Deb {
		Editor_Log(state, .Info, "Rayzr Editor %s is downloaded and verified: %s (click Install in the status bar)", update.version, dl.pkgPath)
	} else {
		Editor_Log(state, .Info, "Rayzr Editor %s is ready: Restart to update (or it installs when you quit)", update.version)
	}
}

// Update_RequestRestart: Restart to update - the usual quit (unsaved work
// prompt), then install and start the new version (Update_OnExit).
Update_RequestRestart :: proc(state: ^EditorState) {
	if update.state != .Ready || update.staged == "" do return
	update.restart = true
	Editor_RequestQuit(state)
}

// Update_RequestRollback: Help > Roll Back - quit, swap the previous
// version back in and start it.
Update_RequestRollback :: proc(state: ^EditorState) {
	if _, ok := Update_PreviousVersion(state); !ok do return
	update.rollback = true
	Editor_RequestQuit(state)
}

// UpdateCheck_StatusBar draws the update button (status bar).
UpdateCheck_StatusBar :: proc(state: ^EditorState) {
	if update.state == .None do return
	imgui.SameLine()
	imgui.PushStyleColorImVec4(.Text, UI_WARNING if update.state == .Failed else UI_ACCENT)
	defer imgui.PopStyleColor()
	switch update.state {
	case .None:
	case .Available:
		installable := update.file.name != "" && update.install.kind != .None
		if imgui.SmallButton(fmt.ctprintf("%s  Update %s available%s###upd", ICON_FA_ARROW_DOWN, update.version, " - Download" if installable else "")) {
			if installable do Update_Download(state)
			else if update.page != "" do Editor_OpenExternally(state, update.page)
		}
		Drive_Item("status.update")
		UI_Tooltip("A newer Rayzr Editor is out: click to download it (checked against the site's SHA-256)" if installable else "A newer Rayzr Editor is out: click for its download page")
	case .Downloading:
		imgui.SmallButton(fmt.ctprintf("%s  Downloading %s... %d%%###upd", ICON_FA_ARROW_DOWN, update.version, int(update.progress * 100)))
		Drive_Item("status.update")
		UI_Tooltip("Downloading, verifying and unpacking the update in the background")
	case .Ready:
		if update.install.kind == .Deb {
			if imgui.SmallButton(fmt.ctprintf("%s  Install %s###upd", ICON_FA_ARROW_DOWN, update.version)) do Editor_OpenExternally(state, update.pkgPath)
			Drive_Item("status.update")
			UI_Tooltip("Downloaded and verified: click to open the .deb in your software installer")
		} else {
			if imgui.SmallButton(fmt.ctprintf("%s  Restart to update to %s###upd", ICON_FA_ROTATE, update.version)) do Update_RequestRestart(state)
			Drive_Item("status.update")
			UI_Tooltip("Quit (asks about unsaved work), install the new version and start it. Quitting installs it too.")
		}
	case .Installed:
		imgui.SmallButton(fmt.ctprintf("%s  Updated to %s###upd", ICON_FA_CHECK, update.version))
		Drive_Item("status.update")
	case .Failed:
		if imgui.SmallButton(fmt.ctprintf("%s  Update %s failed###upd", ICON_FA_TRIANGLE_EXCLAMATION, update.version)) {
			if update.pkgPath != "" do Editor_OpenExternally(state, filepath.dir(update.pkgPath, context.temp_allocator))
			else if update.page != "" do Editor_OpenExternally(state, update.page)
		}
		Drive_Item("status.update")
		UI_Tooltip(fmt.tprintf("%s\nClick to open %s", update.err, "the download's folder (install it by hand)" if update.pkgPath != "" else "the release page"))
	}
}

@(private = "file")
update_ticks: int

@(private = "file")
update_tick :: proc() -> int {
	update_ticks += 1
	return update_ticks
}

// Update_DriveQuery: update.state / version / error / progress / restart.
Update_DriveQuery :: proc(q: string) -> (string, bool) {
	switch q {
	case "update.state": return strings.to_lower(fmt.tprint(update.state), context.temp_allocator), true
	case "update.version": return update.version, true
	case "update.error": return update.err, true
	case "update.restart": return "true" if update.restart else "false", true
	case "update.file": return update.file.name, true
	}
	return update_drive_query_fake(q)
}

@(private)
update_set_string :: proc(dst: ^string, s: string) {
	delete(dst^)
	dst^ = strings.clone(s)
}

@(private = "file")
update_file_clone :: proc(f: Update_File) -> Update_File {
	return {name = strings.clone(f.name), os = strings.clone(f.os), kind = strings.clone(f.kind), sha256 = strings.clone(f.sha256), url = strings.clone(f.url), size = f.size}
}

@(private = "file")
update_file_delete :: proc(f: ^Update_File) {
	delete(f.name); delete(f.os); delete(f.kind); delete(f.sha256); delete(f.url)
	f^ = {}
}
