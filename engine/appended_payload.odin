package engine

import "core:encoding/endian"
import os "osx"
import "core:path/filepath"
import "core:strings"

// ============================================================================
// Single-file games (#292): an exported Windows / Linux game is its runner
// with game.rayzr and the UI font appended, then a 32-byte footer:
//
//     [runner][game.rayzr][font][packageOffset u64][packageSize u64][fontSize u64]["RAYZRAPP"]
//
// (little-endian; the font follows the package). The runner finds its game
// at "<exe>#game.rayzr" (Engine_FindBundledProject), a path RayzrPackage_Open
// reads from the executable; the font is written to the temp folder once,
// for the loaders that want a file. Windows signing must come after
// appending (the signature covers the whole file).
// ============================================================================

APPENDED_MAGIC :: "RAYZRAPP"
APPENDED_FOOTER_SIZE :: 32
// The path suffix naming a package inside an executable.
APPENDED_PACKAGE_SUFFIX :: "#game.rayzr"

Appended_Footer :: struct {
	packageOffset, packageSize, fontSize: u64,
}

// Appended_Build: the runner's bytes with the package and the font appended.
Appended_Build :: proc(runner, pkg, font: []byte, allocator := context.allocator) -> []byte {
	out := make([]byte, len(runner) + len(pkg) + len(font) + APPENDED_FOOTER_SIZE, allocator)
	copy(out, runner)
	copy(out[len(runner):], pkg)
	copy(out[len(runner) + len(pkg):], font)
	f := out[len(out) - APPENDED_FOOTER_SIZE:]
	endian.put_u64(f[0:8], .Little, u64(len(runner)))
	endian.put_u64(f[8:16], .Little, u64(len(pkg)))
	endian.put_u64(f[16:24], .Little, u64(len(font)))
	copy(f[24:32], APPENDED_MAGIC)
	return out
}

// Appended_Find: the footer of an executable with a game appended.
Appended_Find :: proc(exePath: string) -> (foot: Appended_Footer, ok: bool) {
	f, err := os.open(exePath)
	if err != nil do return
	defer os.close(f)
	size, serr := os.file_size(f)
	if serr != nil || size < APPENDED_FOOTER_SIZE do return
	buf: [APPENDED_FOOTER_SIZE]byte
	if n, rerr := os.read_at(f, buf[:], size - APPENDED_FOOTER_SIZE); rerr != nil || n != APPENDED_FOOTER_SIZE do return
	if string(buf[24:32]) != APPENDED_MAGIC do return
	foot.packageOffset, _ = endian.get_u64(buf[0:8], .Little)
	foot.packageSize, _ = endian.get_u64(buf[8:16], .Little)
	foot.fontSize, _ = endian.get_u64(buf[16:24], .Little)
	end := foot.packageOffset + foot.packageSize + foot.fontSize
	if end > u64(size) - APPENDED_FOOTER_SIZE || foot.packageSize == 0 do return {}, false
	return foot, true
}

// Appended_Read: bytes [offset, offset + size) of a file.
Appended_Read :: proc(path: string, offset, size: u64, allocator := context.allocator) -> ([]byte, bool) {
	f, err := os.open(path)
	if err != nil do return nil, false
	defer os.close(f)
	data := make([]byte, int(size), allocator)
	n, rerr := os.read_at(f, data, i64(offset))
	if rerr != nil || n != int(size) {
		delete(data, allocator)
		return nil, false
	}
	return data, true
}

// Appended_PackageBytes: the package inside "<exe>#game.rayzr".
Appended_PackageBytes :: proc(path: string, allocator := context.allocator) -> ([]byte, bool) {
	exe := strings.trim_suffix(path, APPENDED_PACKAGE_SUFFIX)
	foot, ok := Appended_Find(exe)
	if !ok do return nil, false
	return Appended_Read(exe, foot.packageOffset, foot.packageSize, allocator)
}

// Appended_ExtractFont writes an executable's appended font to the temp
// folder (once: kept while its size matches) and returns its path, "" when
// there is none.
Appended_ExtractFont :: proc(exePath: string, allocator := context.allocator) -> string {
	foot, ok := Appended_Find(exePath)
	if !ok || foot.fontSize == 0 do return ""
	tmp := os.get_env("TEMP", context.temp_allocator)
	if tmp == "" do tmp = os.get_env("TMPDIR", context.temp_allocator)
	if tmp == "" do tmp = "/tmp"
	name := strings.trim_suffix(filepath.base(exePath), ".exe")
	dir, _ := filepath.join({tmp, strings.concatenate({"rayzr-", name}, context.temp_allocator)}, context.temp_allocator)
	path, _ := filepath.join({dir, "OpenSans-Regular.ttf"}, context.temp_allocator)
	if st, err := os.stat(path, context.temp_allocator); err == nil && u64(st.size) == foot.fontSize do return strings.clone(path, allocator)
	data, rok := Appended_Read(exePath, foot.packageOffset + foot.packageSize, foot.fontSize, context.temp_allocator)
	if !rok do return ""
	_ = os.make_directory_all(dir)
	if os.write_entire_file(path, data) != nil do return ""
	return strings.clone(path, allocator)
}
