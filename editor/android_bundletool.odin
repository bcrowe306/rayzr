package editor

import "core:crypto/sha2"
import "core:encoding/hex"
import "core:fmt"
import os "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"
import imgui "lib/imgui"

// ============================================================================
// bundletool for the Android AAB (#330). An installed editor doesn't ship it:
// the first Android export that finds none downloads this pinned release
// (curl, on a thread - the editor keeps running; the status bar shows it)
// into the editor's per-user tools folder, checks its SHA-256 (a mismatch is
// thrown away and reported), then runs the export again. Later exports reuse
// it. What was there before still wins: RAYZR_BUNDLETOOL, a bundletool*.jar
// in runners/android/ or the SDK folder, or bin/android_tools in a checkout.
//
// The tools folder: ~/.config/rayzr_editor/tools (--user-data <dir>:
// <dir>/tools - drives). RAYZR_BUNDLETOOL_URL replaces the download's URL
// (tests: a file:// URL); the checksum stays the pinned one.
// ============================================================================

BUNDLETOOL_VERSION :: "1.18.3"
BUNDLETOOL_SHA256 :: "a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29"
BUNDLETOOL_JAR :: "bundletool-all-" + BUNDLETOOL_VERSION + ".jar"
BUNDLETOOL_URL :: "https://github.com/google/bundletool/releases/download/" + BUNDLETOOL_VERSION + "/" + BUNDLETOOL_JAR

@(private = "file")
Bundletool_Job :: struct {
	url, part, dest: string,
	ok:              bool,
	message:         string, // why it failed
	done:            bool,
	thread:          ^thread.Thread,
}

@(private = "file")
bundletool: struct {
	job:      ^Bundletool_Job,
	skipOnce: bool, // the download just failed: the re-run export makes the APK only
}

// Bundletool_ToolsDir: the editor's per-user tools folder.
Bundletool_ToolsDir :: proc(userDataDir: string) -> string {
	if userDataDir != "" {
		p, _ := filepath.join({userDataDir, "tools"}, context.temp_allocator)
		return p
	}
	home, err := os.user_home_dir(context.temp_allocator)
	if err != nil do return ""
	p, _ := filepath.join({home, ".config", "rayzr_editor", "tools"}, context.temp_allocator)
	return p
}

// Bundletool_Verify: the bytes' SHA-256 is `want` (hex, any case).
Bundletool_Verify :: proc(data: []u8, want: string) -> bool {
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, data)
	sum: [sha2.DIGEST_SIZE_256]u8
	sha2.final(&ctx, sum[:])
	got := string(hex.encode(sum[:], context.temp_allocator))
	return strings.equal_fold(got, strings.trim_space(want))
}

@(private = "file")
bundletool_verify_file :: proc(path, want: string) -> bool {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil do return false
	defer delete(data)
	return Bundletool_Verify(data, want)
}

// Bundletool_Cached: the downloaded jar in `toolsDir` ("" = none). One that
// fails the checksum (a damaged file) is removed: the next export fetches it
// again.
Bundletool_Cached :: proc(toolsDir: string, want := BUNDLETOOL_SHA256) -> string {
	if toolsDir == "" do return ""
	p, _ := filepath.join({toolsDir, BUNDLETOOL_JAR}, context.temp_allocator)
	if !os.is_file(p) do return ""
	if !bundletool_verify_file(p, want) {
		_ = os.remove(p)
		return ""
	}
	return p
}

// Bundletool_Downloading: a download is under way (exports wait for it).
Bundletool_Downloading :: proc() -> bool {return bundletool.job != nil}

// Bundletool_TakeSkip: true once after a failed download (that export goes
// on without the AAB instead of downloading again).
Bundletool_TakeSkip :: proc() -> bool {
	s := bundletool.skipOnce
	bundletool.skipOnce = false
	return s
}

// Bundletool_StartDownload fetches the pinned jar into the tools folder in
// the background; Bundletool_Poll re-runs the export when it's done.
Bundletool_StartDownload :: proc(state: ^EditorState) -> bool {
	if bundletool.job != nil do return true
	dir := Bundletool_ToolsDir(state.userDataDir)
	if dir == "" do return false
	if err := os.make_directory_all(dir); err != nil && !os.is_dir(dir) {
		Editor_Log(state, .Warn, "Android export: can't make %s (%v) to download bundletool into", dir, err)
		return false
	}
	url := os.get_env("RAYZR_BUNDLETOOL_URL", context.temp_allocator)
	if url == "" do url = BUNDLETOOL_URL
	job := new(Bundletool_Job)
	job.url = strings.clone(url)
	job.dest, _ = filepath.join({dir, BUNDLETOOL_JAR}, context.allocator)
	job.part = strings.concatenate({job.dest, ".part"})
	job.thread = thread.create_and_start_with_poly_data(job, proc(job: ^Bundletool_Job) {
		_ = os.remove(job.part)
		cmd := []string{"curl", "-fsSL", "--connect-timeout", "20", "-m", "900", "--retry", "2", "-o", job.part, job.url}
		st, out, errOut, err := os.process_exec({command = cmd}, context.allocator)
		defer {delete(out); delete(errOut)}
		switch {
		case err != nil:
			job.message = fmt.aprintf("couldn't run curl: %v", err)
		case st.exit_code != 0:
			job.message = strings.clone(strings.trim_space(string(errOut))) // ("curl: (7) Failed to connect ...")
		case !bundletool_verify_file(job.part, BUNDLETOOL_SHA256):
			job.message = strings.clone("the downloaded file's SHA-256 isn't the expected one - it was thrown away")
		case:
			if rerr := os.rename(job.part, job.dest); rerr != nil {
				job.message = fmt.aprintf("can't save it: %v", rerr)
			} else {
				job.ok = true
			}
		}
		if !job.ok do _ = os.remove(job.part)
		sync.atomic_store(&job.done, true)
	})
	bundletool.job = job
	Editor_Log(state, .Info, "Android export: downloading bundletool %s for the AAB (once; later exports reuse it): %s", BUNDLETOOL_VERSION, url)
	return true
}

// Bundletool_Poll takes a finished download and exports again (every frame).
Bundletool_Poll :: proc(state: ^EditorState) {
	job := bundletool.job
	if job == nil || !sync.atomic_load(&job.done) do return
	bundletool.job = nil
	thread.join(job.thread)
	thread.destroy(job.thread)
	if job.ok {
		Editor_Log(state, .Info, "Android export: bundletool %s downloaded and checked (SHA-256): %s", BUNDLETOOL_VERSION, job.dest)
	} else {
		Editor_Log(state, .Error, "Android export: couldn't download bundletool %s: %s. Add it by hand: download %s, check its SHA-256 is %s, and put it in %s (or set RAYZR_BUNDLETOOL to its path). Exporting the APK only.",
			BUNDLETOOL_VERSION, job.message, BUNDLETOOL_URL, BUNDLETOOL_SHA256, filepath.dir(job.dest, context.temp_allocator))
		bundletool.skipOnce = true
	}
	delete(job.url)
	delete(job.part)
	delete(job.dest)
	delete(job.message)
	free(job)
	Editor_ExportStandalone(state, only = state.exportOnly)
}

// Bundletool_StatusBar: "Downloading bundletool" while it runs.
Bundletool_StatusBar :: proc(state: ^EditorState) {
	job := bundletool.job
	if job == nil do return
	mb := 0.0
	if fi, err := os.stat(job.part, context.temp_allocator); err == nil do mb = f64(fi.size) / (1024 * 1024)
	imgui.SameLine()
	imgui.TextDisabled(fmt.ctprintf("Downloading bundletool %s for the Android AAB: %.1f MB", BUNDLETOOL_VERSION, mb))
	Drive_Item("status.bundletool")
}
