package editor

import "core:fmt"
import os "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

// #291: the auto-updater - the manifest, the package for this install, the
// checksum, unpacking, the swap on a fake install and putting it back when
// the swap fails (no network: everything under a temp folder).

@(private = "file")
UPDATE_TEST_MANIFEST :: `{"schema": 1, "latest": "1.0.0",
 "stable": [
  {"version": "1.1.0-beta.1", "prerelease": true, "notes_url": "n/beta", "files": []},
  {"version": "1.0.0", "prerelease": false, "notes_url": "n/1.0.0", "files": [
    {"name": "SHA256SUMS.txt", "os": "any", "kind": "checksums", "sha256": "aa", "url": "u/sums"},
    {"name": "rayzr-editor-1.0.0-macos.dmg", "os": "macos", "kind": "dmg", "size": 10, "sha256": "d1", "url": "u/dmg"},
    {"name": "rayzr-editor-1.0.0-windows.zip", "os": "windows", "kind": "zip", "size": 11, "sha256": "w1", "url": "u/zip"},
    {"name": "rayzr-editor-1.0.0-linux-amd64.deb", "os": "linux", "kind": "deb", "size": 12, "sha256": "b1", "url": "u/deb"},
    {"name": "rayzr-editor-1.0.0-linux-x86_64.AppImage", "os": "linux", "kind": "appimage", "size": 13, "sha256": "a1", "url": "u/appimage"},
    {"name": "rayzr-editor-1.0.0-linux.tar.gz", "os": "linux", "kind": "tar.gz", "size": 14, "sha256": "t1", "url": "u/tgz"}]},
  {"version": "0.7.0", "prerelease": false, "notes_url": "n/0.7.0", "files": []}],
 "dev": {"version": "1.1.0-dev.925", "prerelease": true, "notes_url": "n/dev", "files": []}}`

@(test)
test_update_pick_entry_291 :: proc(t: ^testing.T) {
	pick :: proc(current: string) -> string {
		entry, ok := Update_PickEntry(UPDATE_TEST_MANIFEST, current)
		return entry.version if ok else "-"
	}
	// Releases: full releases only (the newest; the caller compares).
	testing.expect_value(t, pick("0.7.0"), "1.0.0")
	testing.expect_value(t, pick("1.0.0"), "1.0.0")
	// A beta sees betas too; a dev build the dev build too.
	testing.expect_value(t, pick("1.1.0-beta.0"), "1.1.0-beta.1")
	testing.expect_value(t, pick("1.1.0-dev.900"), "1.1.0-dev.925")
	testing.expect_value(t, pick("1.0.0-dev.3"), "1.1.0-dev.925")
	// Not a manifest.
	testing.expect_value(t, pick_text("not json"), "-")
	testing.expect_value(t, pick_text(`[1, 2]`), "-")
	testing.expect_value(t, pick_text(`{"stable": [], "dev": null}`), "-")

	entry, ok := Update_PickEntry(UPDATE_TEST_MANIFEST, "0.7.0")
	testing.expect(t, ok)
	testing.expect_value(t, entry.notes, "n/1.0.0")
	testing.expect_value(t, len(entry.files), 6)
	testing.expect_value(t, entry.files[1].size, i64(10))
	pick_text :: proc(text: string) -> string {
		entry, ok := Update_PickEntry(text, "1.0.0")
		return entry.version if ok else "-"
	}
}

@(test)
test_update_pick_file_291 :: proc(t: ^testing.T) {
	entry, _ := Update_PickEntry(UPDATE_TEST_MANIFEST, "0.7.0")
	name :: proc(entry: Update_Entry, platform: string, kind: Update_Kind) -> string {
		f, ok := Update_PickFile(entry, platform, kind)
		return f.url if ok else "-"
	}
	testing.expect_value(t, name(entry, "macos", .Mac_App), "u/dmg")
	testing.expect_value(t, name(entry, "windows", .Windows_Folder), "u/zip")
	testing.expect_value(t, name(entry, "linux", .Linux_Folder), "u/tgz")
	testing.expect_value(t, name(entry, "linux", .AppImage), "u/appimage")
	testing.expect_value(t, name(entry, "linux", .Deb), "u/deb")
	testing.expect_value(t, name(entry, "linux", .Mac_App), "-") // (no dmg for Linux)
	// No install (a checkout): the platform's first package, only to link.
	testing.expect_value(t, name(entry, "macos", .None), "u/dmg")
	testing.expect_value(t, name(entry, "freebsd", .None), "-")
}

@(test)
test_update_detect_install_291 :: proc(t: ^testing.T) {
	inst := Update_DetectFrom("/Applications/Rayzr Editor.app/Contents/MacOS/rayzr-editor", "", "macos")
	testing.expect_value(t, inst.kind, Update_Kind.Mac_App)
	testing.expect_value(t, inst.target, "/Applications/Rayzr Editor.app")
	testing.expect_value(t, Update_DetectFrom("/usr/local/bin/rayzr-editor", "", "macos").kind, Update_Kind.None)

	inst = Update_DetectFrom("/home/me/apps/rayzr-editor-linux/rayzr-editor", "", "linux")
	testing.expect_value(t, inst.kind, Update_Kind.Linux_Folder)
	testing.expect_value(t, inst.target, "/home/me/apps/rayzr-editor-linux")
	inst = Update_DetectFrom("/tmp/.mount_RayzrX/usr/bin/rayzr-editor", "/home/me/Rayzr.AppImage", "linux")
	testing.expect_value(t, inst.kind, Update_Kind.AppImage)
	testing.expect_value(t, inst.target, "/home/me/Rayzr.AppImage")
	testing.expect_value(t, Update_DetectFrom("/opt/rayzr-editor/rayzr-editor", "", "linux").kind, Update_Kind.Deb)
	testing.expect_value(t, Update_DetectFrom("/x/rayzr-editor-windows/rayzr-editor.exe", "", "windows").kind, Update_Kind.Windows_Folder)

	testing.expect_value(t, Update_KindPackage(.Mac_App), "dmg")
	testing.expect_value(t, Update_KindPackage(.Linux_Folder), "tar.gz")
	testing.expect_value(t, Update_KindPackage(.None), "")
	testing.expect_value(t, Update_Dir("/x/userdata"), filepath.join({"/x/userdata", "updates"}, context.temp_allocator) or_else "")
	testing.expect(t, strings.has_suffix(Update_Dir(""), "updates"))
	testing.expect_value(t, filepath.base(Update_BackupPath("/Applications/Rayzr Editor.app")), ".Rayzr Editor.app.rayzr-previous")

	testing.expect_value(t, Update_ParseTeam("Executable=/x\nAuthority=Developer ID Application: X (AB12CD34EF)\nTeamIdentifier=AB12CD34EF\n"), "AB12CD34EF")
	testing.expect_value(t, Update_ParseTeam("Signature=adhoc\nTeamIdentifier=not set\n"), "")
	testing.expect_value(t, Update_ParseTeam("code object is not signed at all"), "")
}

// (A fresh temp folder for one test.)
@(private = "file")
update_test_dir :: proc(name: string) -> string {
	tmp, _ := os.temp_directory(context.temp_allocator)
	dir, _ := filepath.join({tmp, name}, context.temp_allocator)
	_ = os.remove_all(dir)
	_ = os.make_directory_all(dir)
	return dir
}

@(private = "file")
update_test_write :: proc(dir, name, text: string) -> string {
	_ = os.make_directory_all(dir)
	p, _ := filepath.join({dir, name}, context.temp_allocator)
	_ = os.write_entire_file(p, text)
	return p
}

@(private = "file")
update_test_read :: proc(parts: ..string) -> string {
	p, _ := filepath.join(parts, context.temp_allocator)
	data, err := os.read_entire_file(p, context.temp_allocator)
	return string(data) if err == nil else "<missing>"
}

@(test)
test_update_verify_file_291 :: proc(t: ^testing.T) {
	dir := update_test_dir("rayzr_update_test_verify")
	defer os.remove_all(dir)
	ABC :: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" // SHA-256("abc")
	p := update_test_write(dir, "pkg", "abc")
	testing.expect(t, Update_VerifyFile(p, ABC))
	testing.expect(t, Update_VerifyFile(p, strings.to_upper(ABC, context.temp_allocator)))
	testing.expect(t, !Update_VerifyFile(p, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ae"))
	testing.expect(t, !Update_VerifyFile(p, ""))
	testing.expect(t, !Update_VerifyFile(fmt.tprintf("%s/missing", dir), ABC))
	// Bigger than one read (1 MiB).
	big := strings.repeat("ab", 3 << 19, context.temp_allocator)
	bp := update_test_write(dir, "big", big)
	testing.expect(t, Update_VerifyFile(bp, update_sha256_hex(transmute([]u8)big)))
	testing.expect(t, Bundletool_Verify(transmute([]u8)big, update_sha256_hex(transmute([]u8)big)))
	testing.expect(t, !Update_VerifyFile(bp, update_sha256_hex(transmute([]u8)big[1:])))
}

@(test)
test_update_swap_291 :: proc(t: ^testing.T) {
	dir := update_test_dir("rayzr_update_test_swap")
	defer os.remove_all(dir)
	target, _ := filepath.join({dir, "rayzr-editor-linux"}, context.temp_allocator)
	update_test_write(target, "rayzr-editor", "v1")
	stage := Update_StageDir(target)
	staged, _ := filepath.join({stage, "rayzr-editor-linux"}, context.temp_allocator)
	update_test_write(staged, "rayzr-editor", "v2")
	backup := Update_BackupPath(target)

	// The swap: the new one in place, the old one kept.
	testing.expect_value(t, Update_Swap(target, staged, backup), "")
	testing.expect_value(t, update_test_read(target, "rayzr-editor"), "v2")
	testing.expect_value(t, update_test_read(backup, "rayzr-editor"), "v1")
	testing.expect(t, !os.exists(staged))

	// The next update replaces the backup.
	update_test_write(staged, "rayzr-editor", "v3")
	testing.expect_value(t, Update_Swap(target, staged, backup), "")
	testing.expect_value(t, update_test_read(target, "rayzr-editor"), "v3")
	testing.expect_value(t, update_test_read(backup, "rayzr-editor"), "v2")

	// Nothing staged: nothing changes.
	testing.expect(t, Update_Swap(target, staged, backup) != "")
	testing.expect_value(t, update_test_read(target, "rayzr-editor"), "v3")
	testing.expect_value(t, update_test_read(backup, "rayzr-editor"), "v2")

	// The swap fails half way (the staged copy lived inside the install,
	// so it's gone once the install moves aside): the old one comes back.
	inner, _ := filepath.join({target, "inner"}, context.temp_allocator)
	update_test_write(inner, "rayzr-editor", "v4")
	err := Update_Swap(target, inner, backup)
	testing.expect(t, strings.contains(err, "the old version is back"), err)
	testing.expect_value(t, update_test_read(target, "rayzr-editor"), "v3")

	// Roll Back exchanges them (twice: forward again).
	testing.expect_value(t, Update_SwapBack(target, backup), "")
	testing.expect_value(t, update_test_read(target, "rayzr-editor"), "v2")
	testing.expect_value(t, update_test_read(backup, "rayzr-editor"), "v3")
	testing.expect_value(t, Update_SwapBack(target, backup), "")
	testing.expect_value(t, update_test_read(target, "rayzr-editor"), "v3")
	testing.expect(t, Update_SwapBack(target, fmt.tprintf("%s/none", dir)) != "")
	testing.expect_value(t, update_test_read(target, "rayzr-editor"), "v3")
}

@(test)
test_update_apply_previous_291 :: proc(t: ^testing.T) {
	dir := update_test_dir("rayzr_update_test_apply")
	defer os.remove_all(dir)
	updates, _ := filepath.join({dir, "updates"}, context.temp_allocator)
	target := update_test_write(dir, "Rayzr.AppImage", "old")
	stage := Update_StageDir(target)
	staged := update_test_write(stage, "Rayzr.AppImage", "new")

	testing.expect_value(t, Update_Apply("install", target, staged, updates, "1.0.0"), "")
	testing.expect_value(t, update_test_read(target), "new")
	testing.expect(t, !os.exists(stage)) // (the staging folder goes)
	ver, tgt := update_read_previous(updates)
	testing.expect_value(t, ver, "1.0.0")
	testing.expect_value(t, tgt, target)

	// Roll Back (run by 1.1.0): 1.0.0 back; Roll Back again returns to 1.1.0.
	testing.expect_value(t, Update_Apply("rollback", target, Update_BackupPath(target), updates, "1.1.0"), "")
	testing.expect_value(t, update_test_read(target), "old")
	ver, _ = update_read_previous(updates)
	testing.expect_value(t, ver, "1.1.0")
	testing.expect_value(t, update_test_read(Update_BackupPath(target)), "new")
}

@(test)
test_update_stage_291 :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return // (tar.gz / AppImage installs are Linux's; the zip is unpacked by Windows' tar)
	} else {
		dir := update_test_dir("rayzr_update_test_stage")
		defer os.remove_all(dir)
		updates, _ := filepath.join({dir, "updates"}, context.temp_allocator)

		// A .tar.gz: unpacked beside the install, the editor folder inside.
		src, _ := filepath.join({dir, "src", "rayzr-editor-linux"}, context.temp_allocator)
		update_test_write(src, "rayzr-editor", "new")
		pkg, _ := filepath.join({dir, "pkg.tar.gz"}, context.temp_allocator)
		_, ok := update_run({"tar", "-czf", pkg, "-C", filepath.dir(src, context.temp_allocator), "rayzr-editor-linux"})
		testing.expect(t, ok)
		installDir, _ := filepath.join({dir, "apps"}, context.temp_allocator)
		target, _ := filepath.join({installDir, "rayzr-editor-linux"}, context.temp_allocator)
		update_test_write(target, "rayzr-editor", "old")
		staged, err := Update_Stage(.Linux_Folder, pkg, target, updates)
		testing.expect_value(t, err, "")
		testing.expect_value(t, filepath.dir(staged, context.temp_allocator), Update_StageDir(target))
		testing.expect_value(t, update_test_read(staged, "rayzr-editor"), "new")
		testing.expect_value(t, Update_Apply("install", target, staged, updates, "1.0.0"), "")
		testing.expect_value(t, update_test_read(target, "rayzr-editor"), "new")

		// A package without the editor: refused.
		empty, _ := filepath.join({dir, "src2", "rayzr-editor-linux"}, context.temp_allocator)
		update_test_write(empty, "README", "x")
		bad, _ := filepath.join({dir, "bad.tar.gz"}, context.temp_allocator)
		_, ok = update_run({"tar", "-czf", bad, "-C", filepath.dir(empty, context.temp_allocator), "rayzr-editor-linux"})
		_, err = Update_Stage(.Linux_Folder, bad, target, updates)
		testing.expect(t, strings.contains(err, "no rayzr-editor"), err)
		// Not a package at all.
		junk := update_test_write(dir, "junk.tar.gz", "not a tarball")
		_, err = Update_Stage(.Linux_Folder, junk, target, updates)
		testing.expect(t, err != "")

		// An AppImage: copied beside it, executable.
		app := update_test_write(dir, "Rayzr.AppImage", "old")
		newApp := update_test_write(dir, "download.AppImage", "new")
		staged, err = Update_Stage(.AppImage, newApp, app, updates)
		testing.expect_value(t, err, "")
		testing.expect_value(t, update_test_read(staged), "new")
		fi, _ := os.stat(staged, context.temp_allocator)
		testing.expect(t, .Execute_User in fi.mode, "the AppImage is executable")

		// A .deb isn't replaced.
		_, err = Update_Stage(.Deb, pkg, target, updates)
		testing.expect(t, err != "")
	}
}

// macOS: a disk image with an app - copied out, its signature checked (an
// unsigned app is refused; an ad-hoc signed one passes next to an ad-hoc
// install: no team to compare).
@(test)
test_update_stage_dmg_291 :: proc(t: ^testing.T) {
	when ODIN_OS != .Darwin {
		return
	} else {
		dir := update_test_dir("rayzr_update_test_dmg")
		defer os.remove_all(dir)
		updates, _ := filepath.join({dir, "updates"}, context.temp_allocator)
		make_app :: proc(root, text: string) -> string {
			app, _ := filepath.join({root, "Rayzr Editor.app"}, context.temp_allocator)
			macos, _ := filepath.join({app, "Contents", "MacOS"}, context.temp_allocator)
			_ = os.make_directory_all(macos)
			p, _ := filepath.join({macos, "rayzr-editor"}, context.temp_allocator)
			_ = os.write_entire_file(p, fmt.tprintf("#!/bin/sh\necho %s\n", text))
			_ = os.change_mode(p, {.Read_User, .Write_User, .Execute_User})
			plist, _ := filepath.join({app, "Contents", "Info.plist"}, context.temp_allocator)
			_ = os.write_entire_file(plist, `<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>rayzr-editor</string><key>CFBundleIdentifier</key><string>com.example.rayzr-update-test</string></dict></plist>`)
			return app
		}
		installed := make_app(fmt.tprintf("%s/Applications", dir), "old")
		srcRoot := fmt.tprintf("%s/dmgsrc", dir)
		newApp := make_app(srcRoot, "new")
		dmg := fmt.tprintf("%s/new.dmg", dir)
		_, ok := update_run({"hdiutil", "create", "-quiet", "-fs", "HFS+", "-srcfolder", srcRoot, "-volname", "RayzrTest", dmg})
		testing.expect(t, ok, "hdiutil create")
		// Unsigned: refused.
		_, err := Update_Stage(.Mac_App, dmg, installed, updates)
		testing.expect(t, strings.contains(err, "signature"), err)

		_, ok = update_run({"codesign", "--force", "-s", "-", newApp})
		testing.expect(t, ok, "codesign")
		_ = os.remove(dmg)
		_, ok = update_run({"hdiutil", "create", "-quiet", "-fs", "HFS+", "-srcfolder", srcRoot, "-volname", "RayzrTest", dmg})
		staged, err2 := Update_Stage(.Mac_App, dmg, installed, updates)
		testing.expect_value(t, err2, "")
		testing.expect_value(t, filepath.base(staged), "Rayzr Editor.app")
		testing.expect(t, strings.contains(update_test_read(staged, "Contents", "MacOS", "rayzr-editor"), "new"))
		testing.expect(t, !os.exists(fmt.tprintf("%s/mnt/Rayzr Editor.app", updates)), "the disk image is detached")
		testing.expect_value(t, Update_Apply("install", installed, staged, updates, "1.0.0"), "")
		testing.expect(t, strings.contains(update_test_read(installed, "Contents", "MacOS", "rayzr-editor"), "new"))
		testing.expect(t, strings.contains(update_test_read(Update_BackupPath(installed), "Contents", "MacOS", "rayzr-editor"), "old"))
	}
}
