#+build !js
package osx

// ============================================================================
// osx: the file system calls the engine uses, so the same code builds for
// the desktop (this file: core:os) and the web (osx_js.odin: emscripten's
// libc over its in-memory file system - core:os doesn't exist on js/wasm).
// Engine files import it as `os` and keep calling os.read_entire_file etc.
// ============================================================================

import "core:os"
import "core:path/filepath"
import "core:strings"

Error :: os.Error
File :: os.File
File_Info :: os.File_Info
File_Type :: os.File_Type
Permissions_Default_File :: os.Permissions_Default_File
Permissions_Execute_All :: os.Permissions_Execute_All

read_entire_file :: os.read_entire_file
read_entire_file_from_path :: os.read_entire_file_from_path
make_directory :: os.make_directory
write_entire_file :: os.write_entire_file
is_file :: os.is_file
is_dir :: os.is_dir
exists :: os.exists
stat :: os.stat
make_directory_all :: os.make_directory_all
remove :: os.remove
remove_all :: os.remove_all
rename :: os.rename
copy_file :: os.copy_file
chmod :: os.chmod
get_env :: os.get_env
read_all_directory_by_path :: os.read_all_directory_by_path
open :: os.open
read_dir :: os.read_dir
close :: os.close
read :: os.read
read_at :: os.read_at
file_size :: os.file_size
pipe_has_data :: os.pipe_has_data
get_working_directory :: os.get_working_directory
exit :: os.exit

// The process's stdin and arguments (set before main runs).
stdin: ^File
args: []string

@(init)
osx_init :: proc "contextless" () {
	stdin = os.stdin
	args = os.args
}

// walk_files: every regular file under root (full paths, temp-allocated).
walk_files :: proc(root: string) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	w := filepath.walker_create(root)
	defer filepath.walker_destroy(&w)
	for info in filepath.walker_walk(&w) {
		if info.type == .Regular do append(&out, strings.clone(info.fullpath, context.temp_allocator)) // (the walker reuses its buffer)
	}
	return out[:]
}
