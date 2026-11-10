package engine

import "core:log"
import os "osx"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

// ============================================================================
// Aseprite files as resources (TODO E.3): loaded once per path (counted),
// reloaded when the file changes (ResourceManager_CheckForChanges: saving in
// Aseprite shows up in the editor and in a running game at once). A sheet
// is every frame composited into one texture, per set of shown layers
// (AsepriteNode: hidden / shown layer overrides) - made when first needed.
// Any image path can be an Aseprite file: TextureNode, NineSlice, UI images,
// tilesets... get its first frame (resource_manager.odin: texture_load).
// ============================================================================

Ase_Resource :: struct {
	path:     string, // as loaded (project-resolved)
	doc:      ^Ase_Document,
	refs:     int,
	version:  int, // +1 per reload (nodes rebuild what they derived)
	modTime:  time.Time,
	sheets:   [dynamic]^Ase_Sheet,
	owner:    ^ResourceManager,
}

Ase_Sheet :: struct {
	key:      string,   // which layers ("" = the file's visibility)
	texture:  rl.Texture2D,
	cols:     int,      // frames per row (cells: the sprite's size)
	version:  int,      // the resource version it was made from
}

// Ase_IsPath: an Aseprite file's path (.aseprite / .ase).
Ase_IsPath :: proc(path: string) -> bool {
	lower := strings.to_lower(path, context.temp_allocator)
	return strings.has_suffix(lower, ".aseprite") || strings.has_suffix(lower, ".ase")
}

// ResourceManager_LoadAseprite: the file's resource (a reference taken),
// nil if it can't be read.
ResourceManager_LoadAseprite :: proc(rm: ^ResourceManager, path: string) -> ^Ase_Resource {
	if r, ok := rm.aseprite[path]; ok {
		r.refs += 1
		return r
	}
	data, found := aseprite_bytes(rm, path)
	if !found {
		log.errorf("Aseprite file not found: %s", path)
		return nil
	}
	defer delete(data, Engine_HeapAllocator())
	doc, why := Ase_Load(data)
	if doc == nil {
		log.errorf("Can't read the Aseprite file %s: %s", path, why)
		return nil
	}
	r := new(Ase_Resource, Engine_HeapAllocator())
	r.path = strings.clone(path, Engine_HeapAllocator())
	r.doc = doc
	r.refs = 1
	r.sheets = make([dynamic]^Ase_Sheet, Engine_HeapAllocator())
	r.owner = rm
	if info, err := os.stat(path, context.temp_allocator); err == nil do r.modTime = info.modification_time
	if rm.aseprite == nil do rm.aseprite = make(map[string]^Ase_Resource, allocator = Engine_HeapAllocator())
	rm.aseprite[r.path] = r
	return r
}

// ResourceManager_ReleaseAseprite drops a reference (the last frees it).
ResourceManager_ReleaseAseprite :: proc(r: ^Ase_Resource) {
	if r == nil do return
	r.refs -= 1
	if r.refs > 0 do return
	if r.owner != nil do delete_key(&r.owner.aseprite, r.path)
	ase_resource_free(r)
}

@(private = "file")
ase_resource_free :: proc(r: ^Ase_Resource) {
	for s in r.sheets {
		if s.texture.id != 0 && rl.IsWindowReady() do rl.UnloadTexture(s.texture)
		delete(s.key, Engine_HeapAllocator())
		free(s, Engine_HeapAllocator())
	}
	delete(r.sheets)
	Ase_Destroy(r.doc)
	delete(r.path, Engine_HeapAllocator())
	free(r, Engine_HeapAllocator())
}

// Ase_ReleaseAll frees a resource manager's Aseprite files (its shutdown).
Ase_ReleaseAll :: proc(rm: ^ResourceManager) {
	for _, r in rm.aseprite do ase_resource_free(r)
	delete(rm.aseprite)
	rm.aseprite = nil
}

// Ase_ResourceCount: files loaded now (tests).
Ase_ResourceCount :: proc(rm: ^ResourceManager) -> int {return len(rm.aseprite)}

@(private = "file")
aseprite_bytes :: proc(rm: ^ResourceManager, path: string) -> ([]u8, bool) {
	if os.is_file(path) {
		data, err := os.read_entire_file(path, Engine_HeapAllocator())
		return data, err == nil
	}
	if rm != nil {
		if b, ok := resource_bytes(rm, path); ok {
			defer delete(b)
			c := make([]u8, len(b), Engine_HeapAllocator())
			copy(c, b)
			return c, true
		}
	}
	return nil, false
}

// Ase_LoadFileImage: a file's first frame as a raylib image (thumbnails;
// the caller unloads it; no data when it can't be read).
Ase_LoadFileImage :: proc(path: string) -> rl.Image {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil do return {}
	doc, _ := Ase_Load(data)
	if doc == nil do return {}
	defer Ase_Destroy(doc)
	return Ase_FrameImage(doc, 0)
}

// Ase_FrameImage: a frame composited as a raylib image (heap; the caller
// unloads it).
Ase_FrameImage :: proc(doc: ^Ase_Document, frame: int, opts := Ase_Render_Options{}) -> rl.Image {
	img := rl.GenImageColor(i32(doc.width), i32(doc.height), {0, 0, 0, 0})
	Ase_RenderFrame(doc, frame, ([^]u8)(img.data)[:doc.width * doc.height * 4], opts)
	return img
}

// Ase_ResourceSheet: every frame composited into one texture, for a set of
// layer overrides (hide / show: comma-separated layer names) - cached per
// key, remade after a reload.
Ase_ResourceSheet :: proc(r: ^Ase_Resource, hide, show: string) -> ^Ase_Sheet {
	if r == nil || r.doc == nil do return nil
	key := strings.concatenate({hide, "|", show}, context.temp_allocator)
	sheet: ^Ase_Sheet
	for s in r.sheets do if s.key == key do sheet = s
	if sheet != nil && sheet.version == r.version && sheet.texture.id != 0 do return sheet
	if !rl.IsWindowReady() do return nil
	doc := r.doc
	atlas, cols := Ase_SheetImage(doc, Ase_Render_Options{visible = Ase_LayerOverrides(doc, hide, show, context.temp_allocator)})
	defer rl.UnloadImage(atlas)
	if sheet == nil {
		sheet = new(Ase_Sheet, Engine_HeapAllocator())
		sheet.key = strings.clone(key, Engine_HeapAllocator())
		append(&r.sheets, sheet)
	} else if sheet.texture.id != 0 {
		rl.UnloadTexture(sheet.texture)
	}
	sheet.texture = rl.LoadTextureFromImage(atlas)
	rl.SetTextureFilter(sheet.texture, .POINT) // (pixel art)
	sheet.cols = cols
	sheet.version = r.version
	return sheet
}

// Ase_SheetImage: every frame composited into one image, cols frames per
// row (a square-ish grid; cells are the sprite's size) - heap, the caller
// unloads it.
Ase_SheetImage :: proc(doc: ^Ase_Document, opts := Ase_Render_Options{}) -> (img: rl.Image, cols: int) {
	n := max(len(doc.frames), 1)
	cols = 1
	for cols * cols < n do cols += 1
	rows := (n + cols - 1) / cols
	img = rl.GenImageColor(i32(cols * doc.width), i32(rows * doc.height), {0, 0, 0, 0})
	frame := make([]u8, doc.width * doc.height * 4, context.temp_allocator)
	dst := ([^]u8)(img.data)
	stride := cols * doc.width * 4
	for f in 0 ..< len(doc.frames) {
		Ase_RenderFrame(doc, f, frame, opts)
		cx, cy := (f % cols) * doc.width, (f / cols) * doc.height
		for y in 0 ..< doc.height {
			copy(dst[(cy + y) * stride + cx * 4:][:doc.width * 4], frame[y * doc.width * 4:][:doc.width * 4])
		}
	}
	return
}

// Ase_SheetRect: a frame's cell in a sheet.
Ase_SheetRect :: proc(r: ^Ase_Resource, s: ^Ase_Sheet, frame: int) -> rl.Rectangle {
	w, h := f32(r.doc.width), f32(r.doc.height)
	return {f32(frame % s.cols) * w, f32(frame / s.cols) * h, w, h}
}

// Ase_LayerOverrides: the layers to show - the file's visibility, minus
// `hide`, plus `show` (comma-separated names; a group's name covers its
// layers). nil when there are no overrides.
Ase_LayerOverrides :: proc(doc: ^Ase_Document, hide, show: string, allocator := context.allocator) -> []bool {
	if strings.trim_space(hide) == "" && strings.trim_space(show) == "" do return nil
	vis := make([]bool, len(doc.layers), allocator)
	for l, i in doc.layers do vis[i] = .Visible in l.flags
	set :: proc(doc: ^Ase_Document, vis: []bool, names: string, on: bool) {
		for part in strings.split(names, ",", context.temp_allocator) {
			name := strings.trim_space(part)
			if name == "" do continue
			for l, i in doc.layers do if l.name == name do vis[i] = on
		}
	}
	set(doc, vis, hide, false)
	set(doc, vis, show, true)
	return vis
}

// Ase_CheckForChanges reloads Aseprite files saved since they were loaded
// (sheets are remade on their next use). Returns how many.
Ase_CheckForChanges :: proc(rm: ^ResourceManager) -> int {
	n := 0
	for _, r in rm.aseprite {
		if r.modTime == {} do continue
		info, err := os.stat(r.path, context.temp_allocator)
		if err != nil || time.diff(r.modTime, info.modification_time) <= 0 do continue
		data, rerr := os.read_entire_file(r.path, context.temp_allocator)
		if rerr != nil do continue
		doc, _ := Ase_Load(data)
		if doc == nil do continue // half-written: next time
		Ase_Destroy(r.doc)
		r.doc = doc
		r.modTime = info.modification_time
		r.version += 1
		log.infof("Reloaded %s", r.path)
		n += 1
	}
	return n
}

// ase_texture_image: an Aseprite file's first frame (texture_load: any image
// path may be one). ok = false: not readable.
ase_texture_image :: proc(rm: ^ResourceManager, path: string) -> (rl.Image, bool) {
	r := ResourceManager_LoadAseprite(rm, path)
	if r == nil do return {}, false
	defer ResourceManager_ReleaseAseprite(r)
	return Ase_FrameImage(r.doc, 0), true
}
