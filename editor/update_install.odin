package editor

import "base:runtime"
import "core:crypto/sha2"
import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:path/slashpath"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

// ============================================================================
// Installing an update (#291; update_check.odin finds and offers it).
//
// How the editor is installed decides what is replaced (Update_Detect):
//   macOS    <X>.app (from the .dmg)        the bundle: the dmg is mounted,
//            the app copied out (ditto: its signature intact), checked
//            (codesign --verify; the same Team ID as the running app)
//   Windows  rayzr-editor-windows\ (.zip)   the folder: unzipped beside it;
//            a copy of the running exe (--apply-update) waits for the
//            editor to exit and swaps it (Windows can't rename a folder in use)
//   Linux    rayzr-editor-linux/ (.tar.gz)  the folder: unpacked beside it
//            <X>.AppImage ($APPIMAGE)       the file: copied beside it
//            /opt/rayzr-editor (.deb)       not replaced: the verified .deb
//                                           is opened (installing needs root)
//   a source checkout                       nothing: the release page
// Every download is checked against the manifest's SHA-256 first. The
// replacement is unpacked next to the install (.rayzr-update/, same disk:
// the swap is two renames), and the old version is kept beside it
// (.<name>.rayzr-previous: Help > Roll Back swaps them again). A failed
// swap puts the old one back. Failures after the editor quit go to
// updates/last_error.txt, reported at the next start.
//
// Files: <config>/updates/ (~/.config/rayzr_editor/updates; --user-data
// <dir>: <dir>/updates) - download/ (the package, replaced by the next),
// previous.txt (the version Roll Back returns to), last_error.txt.
// ============================================================================

Update_Kind :: enum {
	None,           // a source checkout / unknown: link the release page
	Mac_App,        // .dmg
	Windows_Folder, // .zip
	Linux_Folder,   // .tar.gz
	AppImage,       // .AppImage
	Deb,            // .deb (opened, not replaced)
}

// Update_Install: what this editor runs from (target: the .app, folder or
// AppImage that an update replaces).
Update_Install :: struct {
	kind:   Update_Kind,
	target: string,
}

// Update_KindPackage: the manifest's "kind" of the package an install takes.
Update_KindPackage :: proc(kind: Update_Kind) -> string {
	switch kind {
	case .None: return ""
	case .Mac_App: return "dmg"
	case .Windows_Folder: return "zip"
	case .Linux_Folder: return "tar.gz"
	case .AppImage: return "appimage"
	case .Deb: return "deb"
	}
	return ""
}

// Update_PlatformName: this platform as the manifest names it.
Update_PlatformName :: proc() -> string {
	when ODIN_OS == .Darwin {
		return "macos"
	} else when ODIN_OS == .Windows {
		return "windows"
	} else {
		return "linux"
	}
}

@(private = "file")
update_override: Update_Install // (drives: a fake install; heap target)

// Update_Detect: this editor's install (temp target).
Update_Detect :: proc() -> Update_Install {
	if update_override.kind != .None do return {update_override.kind, update_override.target}
	if Resources_InCheckout() do return {}
	exe, err := os.get_executable_path(context.temp_allocator)
	if err != nil do return {}
	return Update_DetectFrom(exe, os.get_env("APPIMAGE", context.temp_allocator), Update_PlatformName())
}

// Update_DetectFrom: the install an executable at `exe` belongs to (temp).
Update_DetectFrom :: proc(exe, appimage, platform: string) -> Update_Install {
	switch platform {
	case "macos":
		if i := strings.index(exe, ".app/Contents/MacOS/"); i >= 0 do return {.Mac_App, exe[:i + 4]}
	case "windows":
		return {.Windows_Folder, filepath.dir(exe, context.temp_allocator)}
	case "linux":
		if appimage != "" do return {.AppImage, appimage}
		// (Linux paths: "/" whatever the host - the tests run this on Windows too.)
		dir := slashpath.dir(exe, context.temp_allocator)
		if strings.has_prefix(dir, "/opt/") || strings.has_prefix(dir, "/usr/") do return {.Deb, dir}
		return {.Linux_Folder, dir}
	}
	return {}
}

// Update_Dir: the updater's folder (follows --user-data; temp).
Update_Dir :: proc(userDataDir: string) -> string {
	if userDataDir != "" {
		p, _ := filepath.join({userDataDir, "updates"}, context.temp_allocator)
		return p
	}
	home, err := os.user_home_dir(context.temp_allocator)
	if err != nil do return ""
	p, _ := filepath.join({home, ".config", "rayzr_editor", "updates"}, context.temp_allocator)
	return p
}

// Update_BackupPath: where the replaced version is kept (beside the
// install, hidden: .<name>.rayzr-previous; temp).
Update_BackupPath :: proc(target: string) -> string {
	p, _ := filepath.join({filepath.dir(target, context.temp_allocator), fmt.tprintf(".%s.rayzr-previous", filepath.base(target))}, context.temp_allocator)
	return p
}

// Update_StageDir: where the replacement is unpacked (beside the install; temp).
Update_StageDir :: proc(target: string) -> string {
	p, _ := filepath.join({filepath.dir(target, context.temp_allocator), ".rayzr-update"}, context.temp_allocator)
	return p
}

// Update_VerifyFile: the file's SHA-256 is `want` (hex, any case).
Update_VerifyFile :: proc(path, want: string) -> bool {
	if strings.trim_space(want) == "" do return false
	f, err := os.open(path)
	if err != nil do return false
	defer os.close(f)
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	buf := make([]u8, 1 << 20, context.temp_allocator)
	for {
		n, rerr := os.read(f, buf)
		if n > 0 do sha2.update(&ctx, buf[:n])
		if rerr != nil || n <= 0 do break
	}
	sum: [sha2.DIGEST_SIZE_256]u8
	sha2.final(&ctx, sum[:])
	return strings.equal_fold(string(hex.encode(sum[:], context.temp_allocator)), strings.trim_space(want))
}

// (SHA-256 as hex; temp.)
@(private)
update_sha256_hex :: proc(data: []u8) -> string {
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, data)
	sum: [sha2.DIGEST_SIZE_256]u8
	sha2.final(&ctx, sum[:])
	return string(hex.encode(sum[:], context.temp_allocator))
}

// Update_Swap puts `staged` in place of `target`, keeping the old one at
// `backup` (an older backup is replaced once the swap is done). On failure
// nothing changes ("" = done).
Update_Swap :: proc(target, staged, backup: string) -> string {
	if !os.exists(staged) do return fmt.tprintf("nothing to install (%s is missing)", staged)
	older := fmt.tprintf("%s.old", backup)
	_ = os.remove_all(older)
	if os.exists(backup) {
		if err := os.rename(backup, older); err != nil do return fmt.tprintf("could not move the old backup %s aside: %v", backup, err)
	}
	restore :: proc(backup, older: string) {
		if os.exists(older) do _ = os.rename(older, backup)
	}
	if os.exists(target) {
		if err := os.rename(target, backup); err != nil {
			restore(backup, older)
			return fmt.tprintf("could not move %s aside: %v", target, err)
		}
	}
	if err := os.rename(staged, target); err != nil {
		if rerr := os.rename(backup, target); rerr != nil do return fmt.tprintf("could not install %s (%v), and could not restore %s (%v)", staged, err, target, rerr)
		restore(backup, older)
		return fmt.tprintf("could not install %s: %v (the old version is back)", staged, err)
	}
	_ = os.remove_all(older)
	return ""
}

// Update_SwapBack exchanges `target` and `backup` (Roll Back; twice rolls
// forward again). On failure nothing changes.
Update_SwapBack :: proc(target, backup: string) -> string {
	if !os.exists(backup) do return fmt.tprintf("no previous version at %s", backup)
	tmp := fmt.tprintf("%s.swap", backup)
	_ = os.remove_all(tmp)
	if err := os.rename(target, tmp); err != nil do return fmt.tprintf("could not move %s aside: %v", target, err)
	if err := os.rename(backup, target); err != nil {
		_ = os.rename(tmp, target)
		return fmt.tprintf("could not restore %s: %v", backup, err)
	}
	if err := os.rename(tmp, backup); err != nil do return fmt.tprintf("rolled back, but could not keep the newer version (%v)", err)
	return ""
}

// --- previous.txt: what Roll Back returns to -------------------------------------------

// Update_PreviousVersion: Roll Back's version, when this install's backup
// is there (temp).
Update_PreviousVersion :: proc(state: ^EditorState) -> (string, bool) {
	inst := Update_Detect()
	if inst.kind == .None || inst.kind == .Deb do return "", false
	ver, target := update_read_previous(Update_Dir(state.userDataDir))
	if ver == "" || target != inst.target || !os.exists(Update_BackupPath(target)) do return "", false
	return ver, true
}

@(private)
update_read_previous :: proc(dir: string) -> (version, target: string) {
	p, _ := filepath.join({dir, "previous.txt"}, context.temp_allocator)
	data, err := os.read_entire_file(p, context.temp_allocator)
	if err != nil do return
	lines := strings.split_lines(string(data), context.temp_allocator)
	if len(lines) < 2 do return
	return strings.trim_space(lines[0]), strings.trim_space(lines[1])
}

@(private)
update_write_previous :: proc(dir, version, target: string) {
	_ = os.make_directory_all(dir)
	p, _ := filepath.join({dir, "previous.txt"}, context.temp_allocator)
	_ = os.write_entire_file(p, fmt.tprintf("%s\n%s\n", version, target))
}

@(private)
update_write_error :: proc(dir, msg: string) {
	_ = os.make_directory_all(dir)
	p, _ := filepath.join({dir, "last_error.txt"}, context.temp_allocator)
	_ = os.write_entire_file(p, msg)
}

// (A failure after the editor quit: reported at the next start, once.)
@(private)
update_report_last_error :: proc() {
	dir := Update_Dir(GlobalEditor.userDataDir)
	p, _ := filepath.join({dir, "last_error.txt"}, context.temp_allocator)
	data, err := os.read_entire_file(p, context.temp_allocator)
	if err != nil do return
	_ = os.remove(p)
	Editor_Log(&GlobalEditor, .Warn, "The last update didn't install: %s", strings.trim_space(string(data)))
}

// --- the download (a thread: download, verify, unpack) ---------------------------------

@(private)
Update_Download_Job :: struct {
	url, sha256, name, version: string, // (heap)
	kind:                       Update_Kind,
	target, dir:                string,
	part:                       string, // the partial download (progress)
	pkgPath, staged, err:       string, // results (heap)
	done:                       bool,
	allocator:                  runtime.Allocator,
	thread:                     ^thread.Thread,
}

@(private)
update_download_start :: proc(f: Update_File, inst: Update_Install, version, dir: string) -> ^Update_Download_Job {
	dl := new(Update_Download_Job)
	dl.url = strings.clone(f.url)
	dl.sha256 = strings.clone(f.sha256)
	dl.name = strings.clone(filepath.base(f.name))
	dl.version = strings.clone(version)
	dl.kind = inst.kind
	dl.target = strings.clone(inst.target)
	dl.dir = strings.clone(dir)
	dl.part = strings.concatenate({dir, "/download/", dl.name, ".part"})
	dl.allocator = context.allocator
	dl.thread = thread.create_and_start_with_poly_data(dl, proc(dl: ^Update_Download_Job) {
		context.allocator = dl.allocator
		update_download_run(dl)
		sync.atomic_store(&dl.done, true)
	})
	return dl
}

@(private)
update_download_free :: proc(dl: ^Update_Download_Job) {
	thread.join(dl.thread)
	thread.destroy(dl.thread)
	delete(dl.url); delete(dl.sha256); delete(dl.name); delete(dl.version)
	delete(dl.target); delete(dl.dir); delete(dl.part)
	delete(dl.pkgPath); delete(dl.staged); delete(dl.err)
	free(dl)
}

@(private = "file")
update_download_run :: proc(dl: ^Update_Download_Job) {
	fail :: proc(dl: ^Update_Download_Job, format: string, args: ..any) {
		dl.err = fmt.aprintf(format, ..args)
	}
	down, _ := filepath.join({dl.dir, "download"}, context.temp_allocator)
	_ = os.remove_all(down) // (the last update's package)
	if err := os.make_directory_all(down); err != nil {
		fail(dl, "could not create %s: %v", down, err)
		return
	}
	pkg, _ := filepath.join({down, dl.name}, context.temp_allocator)
	out, ok := update_run({"curl", "-fsSL", "--retry", "2", "-m", "1800", "-o", dl.part, dl.url})
	if !ok {
		fail(dl, "the download failed (%s)", out)
		return
	}
	if !Update_VerifyFile(dl.part, dl.sha256) {
		_ = os.remove(dl.part)
		fail(dl, "the download doesn't match the site's SHA-256 checksum (deleted)")
		return
	}
	if err := os.rename(dl.part, pkg); err != nil {
		fail(dl, "could not keep the download: %v", err)
		return
	}
	dl.pkgPath = strings.clone(pkg)
	if dl.kind == .Deb do return // (opened, not unpacked)
	staged, err := Update_Stage(dl.kind, pkg, dl.target, dl.dir)
	if err != "" {
		dl.err = strings.clone(err)
		return
	}
	dl.staged = strings.clone(staged)
}

// Update_Stage unpacks a verified package next to the install: the
// replacement's path ("" + an error on failure). dir: the updater's folder
// (the dmg's mount point).
Update_Stage :: proc(kind: Update_Kind, pkg, target, dir: string) -> (staged: string, err: string) {
	stage := Update_StageDir(target)
	_ = os.remove_all(stage)
	if merr := os.make_directory_all(stage); merr != nil {
		return "", fmt.tprintf("can't write next to the install (%s: %v) - install the downloaded package by hand", filepath.dir(target, context.temp_allocator), merr)
	}
	switch kind {
	case .None, .Deb:
		return "", "this install isn't updated in place"
	case .Mac_App:
		mnt, _ := filepath.join({dir, "mnt"}, context.temp_allocator)
		_ = os.make_directory_all(mnt)
		if out, ok := update_run({"hdiutil", "attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mnt, pkg}); !ok {
			return "", fmt.tprintf("could not open the disk image (%s)", out)
		}
		defer update_run({"hdiutil", "detach", mnt, "-force"})
		app := update_find_child(mnt, ".app", folders = true)
		if app == "" do return "", "no app in the disk image"
		staged, _ = filepath.join({stage, filepath.base(target)}, context.temp_allocator)
		if out, ok := update_run({"ditto", app, staged}); !ok do return "", fmt.tprintf("could not copy the app (%s)", out)
		update_run({"xattr", "-dr", "com.apple.quarantine", staged})
		if msg := update_mac_check(staged, target); msg != "" do return "", msg
		return staged, ""
	case .Windows_Folder, .Linux_Folder:
		tar := "tar"
		when ODIN_OS == .Windows {
			// (Windows' own bsdtar reads .zip; a Git Bash tar on PATH doesn't.)
			if sys := os.get_env("SystemRoot", context.temp_allocator); sys != "" {
				p, _ := filepath.join({sys, "System32", "tar.exe"}, context.temp_allocator)
				if os.exists(p) do tar = p
			}
		}
		if out, ok := update_run({tar, "-xf", pkg, "-C", stage}); !ok do return "", fmt.tprintf("could not unpack the update (%s)", out)
		folder := update_find_child(stage, "", folders = true)
		if folder == "" do return "", "the package has no editor folder"
		exe := "rayzr-editor.exe" if kind == .Windows_Folder else "rayzr-editor"
		p, _ := filepath.join({folder, exe}, context.temp_allocator)
		if !os.exists(p) do return "", fmt.tprintf("the package has no %s", exe)
		return folder, ""
	case .AppImage:
		staged, _ = filepath.join({stage, filepath.base(target)}, context.temp_allocator)
		if cerr := os.copy_file(staged, pkg); cerr != nil do return "", fmt.tprintf("could not copy the AppImage: %v", cerr)
		_ = os.change_mode(staged, {.Read_User, .Write_User, .Execute_User, .Read_Group, .Execute_Group, .Read_Other, .Execute_Other})
		return staged, ""
	}
	return "", "unknown install"
}

// (macOS: the new app's signature is valid, and from the same team as the
// running one - unless that one isn't Developer ID signed: local packages.)
@(private = "file")
update_mac_check :: proc(staged, target: string) -> string {
	if out, ok := update_run({"codesign", "--verify", "--deep", "--strict", staged}); !ok {
		return fmt.tprintf("the new app's code signature isn't valid (%s)", out)
	}
	oldInfo, _ := update_run({"codesign", "-dv", "--verbose=2", target})
	newInfo, _ := update_run({"codesign", "-dv", "--verbose=2", staged})
	old, new_ := Update_ParseTeam(oldInfo), Update_ParseTeam(newInfo)
	if old != "" && new_ != old do return fmt.tprintf("the new app is signed by another team (%q, this one %q)", new_, old)
	return ""
}

// Update_ParseTeam: the Team ID in `codesign -dv` output ("" = none / ad-hoc).
Update_ParseTeam :: proc(out: string) -> string {
	for line in strings.split_lines(out, context.temp_allocator) {
		if v, found := strings.substring_from(line, len("TeamIdentifier=")); found && strings.has_prefix(line, "TeamIdentifier=") {
			v = strings.trim_space(v)
			return "" if v == "not set" else v
		}
	}
	return ""
}

// (A child of `dir` with this suffix: a folder or file; temp.)
@(private = "file")
update_find_child :: proc(parent, suffix: string, folders := false) -> string {
	entries, err := os.read_all_directory_by_path(parent, context.temp_allocator)
	if err != nil do return ""
	for fi in entries {
		if strings.has_prefix(fi.name, ".") || !strings.has_suffix(fi.name, suffix) do continue
		if folders && fi.type != .Directory do continue
		p, _ := filepath.join({parent, fi.name}, context.temp_allocator)
		return p
	}
	return ""
}

// (Runs a command: its output (temp) and whether it exited 0.)
@(private)
update_run :: proc(cmd: []string) -> (string, bool) {
	st, out, errOut, err := os.process_exec({command = cmd}, context.temp_allocator)
	if err != nil do return fmt.tprintf("%s: %v", cmd[0], err), false
	text := strings.trim_space(strings.concatenate({string(out), string(errOut)}, context.temp_allocator))
	return text, st.exit_code == 0
}

// --- installing (when the editor quits) ------------------------------------------------

// Update_OnExit installs a staged update (or rolls back) as the editor
// quits, and starts the new editor after Restart to update. (After the
// main loop: unsaved work was already asked about.)
Update_OnExit :: proc(state: ^EditorState) {
	if GlobalDrive.enabled || update_headless() do return // (drives: update-install)
	install := update.state == .Ready && update.staged != "" && update.install.kind != .Deb
	if !install && !update.rollback do return
	inst := Update_Detect()
	if inst.kind == .None || inst.target != update.install.target do return
	relaunch := update.restart || update.rollback
	dir := Update_Dir(state.userDataDir)
	mode := "rollback" if update.rollback else "install"
	staged := update.staged if !update.rollback else Update_BackupPath(inst.target)
	when ODIN_OS == .Windows {
		// The folder can't be renamed while this exe runs from it: a copy
		// of it (outside) waits for this process to exit, then swaps.
		helperDir, _ := filepath.join({dir, "helper"}, context.temp_allocator)
		_ = os.make_directory_all(helperDir)
		helper, _ := filepath.join({helperDir, "rayzr-update-helper.exe"}, context.temp_allocator)
		exe, _ := os.get_executable_path(context.temp_allocator)
		if err := os.copy_file(helper, exe); err != nil {
			update_write_error(dir, fmt.tprintf("could not start the updater (%v)", err))
			return
		}
		cmd := []string{helper, "--apply-update", mode, fmt.tprint(os.get_pid()), inst.target, staged, dir, update_current(),
			state.projectPath if relaunch else "", "1" if relaunch else "0"}
		if _, err := os.process_start({command = cmd}); err != nil do update_write_error(dir, fmt.tprintf("could not start the updater (%v)", err))
	} else {
		err := Update_Apply(mode, inst.target, staged, dir, update_current())
		if err != "" {
			update_write_error(dir, err)
			fmt.eprintln("Update:", err)
		}
		if relaunch do update_launch(inst, state.projectPath)
	}
}

// Update_Apply swaps the install (mode "install": staged in, the old kept;
// "rollback": the kept one back) and records what Roll Back returns to
// ("" = done).
Update_Apply :: proc(mode, target, staged, dir, oldVersion: string) -> string {
	if mode == "rollback" {
		if err := Update_SwapBack(target, staged); err != "" do return err
		update_write_previous(dir, oldVersion, target) // (Roll Back again: forward)
		return ""
	}
	if err := Update_Swap(target, staged, Update_BackupPath(target)); err != "" do return err
	_ = os.remove_all(Update_StageDir(target))
	update_write_previous(dir, oldVersion, target)
	return ""
}

// (Starts the editor at `inst`, on `project`.)
@(private = "file")
update_launch :: proc(inst: Update_Install, project: string) {
	cmd := make([dynamic]string, context.temp_allocator)
	switch inst.kind {
	case .Mac_App:
		append(&cmd, "open", "-n", inst.target)
		if project != "" do append(&cmd, "--args", "--project", project)
	case .Windows_Folder, .Linux_Folder:
		exe := "rayzr-editor.exe" if inst.kind == .Windows_Folder else "rayzr-editor"
		p, _ := filepath.join({inst.target, exe}, context.temp_allocator)
		append(&cmd, p)
		if project != "" do append(&cmd, "--project", project)
	case .AppImage:
		append(&cmd, inst.target)
		if project != "" do append(&cmd, "--project", project)
	case .None, .Deb:
		return
	}
	if _, err := os.process_start({command = cmd[:]}); err != nil do fmt.eprintln("Could not start the updated editor:", err)
}

// Update_HelperMain: rayzr-update-helper.exe --apply-update <mode> <pid>
// <target> <staged> <updates dir> <old version> <project> <relaunch 0|1>
// (Windows: started by Update_OnExit from a copy outside the install).
// Waits for the editor to exit, swaps (retrying while files are still
// locked), starts the new editor.
Update_HelperMain :: proc(args: []string) -> int {
	if len(args) < 8 do return 2
	mode, target, staged, dir, oldVersion, project := args[0], args[2], args[3], args[4], args[5], args[6]
	if pid, ok := strconv.parse_int(args[1]); ok {
		if p, err := os.process_open(pid); err == nil do _, _ = os.process_wait(p, 120 * time.Second)
	}
	err := ""
	for _ in 0 ..< 40 {
		err = Update_Apply(mode, target, staged, dir, oldVersion)
		if err == "" do break
		time.sleep(250 * time.Millisecond)
	}
	if err != "" do update_write_error(dir, err)
	if args[7] == "1" {
		kind: Update_Kind = .Windows_Folder when ODIN_OS == .Windows else .Linux_Folder
		update_launch({kind, target}, project)
	}
	return 0 if err == "" else 1
}

// --- drives: a fake install, package and manifest --------------------------------------

// Update_DriveFake (drive: update-fake <version>): under <user data>/
// update_drive, a fake Linux-folder install (rayzr-editor says "old"), a
// .tar.gz of a newer one ("new") and a manifest (file:// URLs, its real
// SHA-256); then checks it, as a 1.0.0 install. ("" = started.)
Update_DriveFake :: proc(state: ^EditorState, version: string) -> string {
	base := state.userDataDir if state.userDataDir != "" else os.get_env("TMPDIR", context.temp_allocator)
	root, _ := filepath.join({base, "update_drive"}, context.temp_allocator)
	_ = os.remove_all(root)
	install, _ := filepath.join({root, "install", "rayzr-editor-linux"}, context.temp_allocator)
	src, _ := filepath.join({root, "src", "rayzr-editor-linux"}, context.temp_allocator)
	pkgDir, _ := filepath.join({root, "pkg"}, context.temp_allocator)
	for d in ([]string{install, src, pkgDir}) do if err := os.make_directory_all(d); err != nil do return fmt.tprintf("mkdir %s: %v", d, err)
	_ = os.write_entire_file(fmt.tprintf("%s/rayzr-editor", install), "old")
	_ = os.write_entire_file(fmt.tprintf("%s/rayzr-editor", src), "new")
	name := fmt.tprintf("rayzr-editor-%s-linux.tar.gz", version)
	pkg, _ := filepath.join({pkgDir, name}, context.temp_allocator)
	if out, ok := update_run({"tar", "-czf", pkg, "-C", filepath.dir(src, context.temp_allocator), "rayzr-editor-linux"}); !ok do return fmt.tprintf("tar: %s", out)
	data, rerr := os.read_entire_file(pkg, context.temp_allocator)
	if rerr != nil do return "no package"
	sha := update_sha256_hex(data)
	manifest, _ := filepath.join({root, "manifest.json"}, context.temp_allocator)
	url := fmt.tprintf("file://%s", pkg)
	_ = os.write_entire_file(manifest, fmt.tprintf(
		`{{"schema": 1, "latest": %q, "stable": [{{"version": %q, "prerelease": false, "notes_url": "https://example.invalid/notes", "files": [{{"name": %q, "os": %q, "kind": "tar.gz", "size": %d, "sha256": %q, "url": %q}}]}}], "dev": null}}`,
		version, version, name, Update_PlatformName(), len(data), sha, url))
	delete(update_override.target)
	update_override = {.Linux_Folder, strings.clone(install)}
	update.current = "1.0.0"
	update.state = .None
	update_start_check(fmt.tprintf("file://%s", manifest), manual = true)
	return ""
}

// Update_DriveInstall (drive: update-install / update-rollback): what quitting
// does, without quitting or starting anything ("" = done).
Update_DriveInstall :: proc(state: ^EditorState, rollback: bool) -> string {
	if update_override.kind == .None do return "no fake install (update-fake first)"
	dir := Update_Dir(state.userDataDir)
	target := update_override.target
	if rollback do return Update_Apply("rollback", target, Update_BackupPath(target), dir, update_current())
	if update.state != .Ready do return fmt.tprintf("not ready (%v: %s)", update.state, update.err)
	if err := Update_Apply("install", target, update.staged, dir, update_current()); err != "" do return err
	update.state = .Installed
	return ""
}

@(private)
update_drive_query_fake :: proc(q: string) -> (string, bool) {
	read :: proc(p: string) -> string {
		data, err := os.read_entire_file(p, context.temp_allocator)
		return string(data) if err == nil else ""
	}
	switch q {
	case "update.installed":
		return read(fmt.tprintf("%s/rayzr-editor", update_override.target)), true
	case "update.previous":
		return read(fmt.tprintf("%s/rayzr-editor", Update_BackupPath(update_override.target))), true
	case "update.rollback-version":
		v, _ := update_read_previous(Update_Dir(GlobalEditor.userDataDir))
		return v, true
	}
	return "", false
}
