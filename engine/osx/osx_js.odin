#+build js
package osx

// ============================================================================
// osx on the web: emscripten's libc over its file system (MEMFS - the
// game's package is preloaded into it; save files go to /save, kept in the
// browser by the page's IDBFS sync). Directory listing, permissions and
// processes don't exist here; those calls report Unsupported.
// ============================================================================

import "core:c"
import "core:strings"
import "core:time"

General_Error :: enum u32 {
	None,
	Exist,
	Not_Exist,
	Unsupported,
	Invalid,
}

Error :: union #shared_nil {
	General_Error,
}

File_Type :: enum {
	Undetermined,
	Regular,
	Directory,
	Symlink,
	Named_Pipe,
	Socket,
	Block_Device,
	Character_Device,
}

File_Info :: struct {
	fullpath:          string,
	name:              string,
	size:              i64,
	type:              File_Type,
	modification_time: time.Time,
}

File :: struct {
	handle: rawptr,
}

Permissions :: distinct u32
Permissions_Default_File :: Permissions(0o644)
Permissions_Execute_All :: Permissions(0o111)

stdin: ^File
args: []string

@(private = "file")
@(default_calling_convention = "c")
foreign {
	fopen :: proc(path, mode: cstring) -> rawptr ---
	fclose :: proc(f: rawptr) -> i32 ---
	fread :: proc(buf: rawptr, size, count: uint, f: rawptr) -> uint ---
	fwrite :: proc(buf: rawptr, size, count: uint, f: rawptr) -> uint ---
	fseek :: proc(f: rawptr, offset: c.long, whence: i32) -> i32 ---
	ftell :: proc(f: rawptr) -> c.long ---
	opendir :: proc(path: cstring) -> rawptr ---
	closedir :: proc(d: rawptr) -> i32 ---
	mkdir :: proc(path: cstring, mode: u32) -> i32 ---
	unlink :: proc(path: cstring) -> i32 ---
	rmdir :: proc(path: cstring) -> i32 ---
	@(link_name = "rename") c_rename :: proc(old, new: cstring) -> i32 ---
}

@(private = "file")
cstr :: proc(s: string) -> cstring {return strings.clone_to_cstring(s, context.temp_allocator)}

read_entire_file :: proc(path: string, allocator := context.allocator) -> (data: []byte, err: Error) {
	f := fopen(cstr(path), "rb")
	if f == nil do return nil, .Not_Exist
	defer fclose(f)
	fseek(f, 0, 2) // (SEEK_END)
	size := ftell(f)
	fseek(f, 0, 0)
	if size < 0 do return nil, .Invalid
	data = make([]byte, int(size), allocator)
	if size > 0 && fread(raw_data(data), 1, uint(size), f) != uint(size) {
		delete(data, allocator)
		return nil, .Invalid
	}
	return data, nil
}

read_entire_file_from_path :: read_entire_file

make_directory :: proc(path: string, perm := Permissions(0o755)) -> Error {
	return nil if mkdir(cstr(path), u32(perm)) == 0 || is_dir(path) else .Invalid
}

write_entire_file :: proc(path: string, data: []byte, perm := Permissions_Default_File, truncate := true) -> Error {
	f := fopen(cstr(path), "wb")
	if f == nil do return .Not_Exist
	defer fclose(f)
	if len(data) > 0 && fwrite(raw_data(data), 1, uint(len(data)), f) != uint(len(data)) do return .Invalid
	return nil
}

is_dir :: proc(path: string) -> bool {
	d := opendir(cstr(path))
	if d == nil do return false
	closedir(d)
	return true
}

is_file :: proc(path: string) -> bool {
	if is_dir(path) do return false
	f := fopen(cstr(path), "rb")
	if f == nil do return false
	fclose(f)
	return true
}

exists :: proc(path: string) -> bool {return is_file(path) || is_dir(path)}

stat :: proc(path: string, allocator := context.allocator) -> (info: File_Info, err: Error) {
	if !exists(path) do return {}, .Not_Exist
	info.fullpath = strings.clone(path, allocator)
	info.name = info.fullpath[strings.last_index_byte(info.fullpath, '/') + 1:]
	info.type = .Directory if is_dir(path) else .Regular
	return info, nil // (no modification times: nothing reloads on the web)
}

make_directory_all :: proc(path: string, perm := Permissions(0o755)) -> Error {
	if path == "" || is_dir(path) do return nil
	for i in 1 ..= len(path) {
		if i == len(path) || path[i] == '/' {
			part := path[:i]
			if !is_dir(part) do mkdir(cstr(part), 0o755)
		}
	}
	return nil if is_dir(path) else .Invalid
}

remove :: proc(path: string) -> Error {
	if unlink(cstr(path)) == 0 || rmdir(cstr(path)) == 0 do return nil
	return .Not_Exist
}

remove_all :: proc(path: string) -> Error {return remove(path)}

rename :: proc(old, new: string) -> Error {
	return nil if c_rename(cstr(old), cstr(new)) == 0 else .Invalid
}

copy_file :: proc(dst, src: string) -> Error {
	data, err := read_entire_file(src, context.temp_allocator)
	if err != nil do return err
	return write_entire_file(dst, data)
}

chmod :: proc(path: string, perm: Permissions) -> Error {return .Unsupported}

get_env :: proc(key: string, allocator := context.allocator) -> string {return ""}

read_all_directory_by_path :: proc(path: string, allocator := context.allocator) -> ([]File_Info, Error) {return nil, .Unsupported}

open :: proc(path: string, flags := 0, perm := Permissions(0)) -> (^File, Error) {return nil, .Unsupported}

read_dir :: proc(f: ^File, n: int, allocator := context.allocator) -> ([]File_Info, Error) {return nil, .Unsupported}

close :: proc(f: ^File) -> Error {return nil}

read :: proc(f: ^File, buf: []byte) -> (int, Error) {return 0, .Unsupported}

read_at :: proc(f: ^File, buf: []byte, offset: i64) -> (int, Error) {return 0, .Unsupported}

file_size :: proc(f: ^File) -> (i64, Error) {return 0, .Unsupported}

pipe_has_data :: proc(f: ^File) -> (bool, Error) {return false, .Unsupported}

get_working_directory :: proc(allocator := context.allocator) -> (string, Error) {return strings.clone("/", allocator), nil}


exit :: proc "contextless" (code: int) -> ! {
	for {} // (a web page doesn't exit: the main loop simply ends)
}

// walk_files: (no directory listing on the web)
walk_files :: proc(root: string) -> []string {return nil}
