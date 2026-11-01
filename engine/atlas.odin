package engine

import "core:encoding/json"
import "core:fmt"
import os "osx"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import vmem "core:mem/virtual"
import rl "vendor:raylib"

// ============================================================================
// Sprite atlases (docs/atlas.md). Textures whose import settings say
// "atlas": true are packed on export into a few big pages - so sprites
// that used different images now share one GPU texture and raylib draws
// them in one batch (the draw batching in batching.odin groups by texture).
//
//   export   Atlas_Build: the flagged textures (of what the preset
//            exports), grouped by filter, packed with MaxRects (best short
//            side fit) into pages up to ATLAS_PAGE px, 2 px apart with
//            their edge pixels repeated into the gap (no bleeding when
//            filtered or scaled); written as atlas/page_<n>.png plus
//            atlas/atlas.json {pages, sprites: path -> page + rect}. The
//            original files stay in the package (shaders' textures, LDtk
//            and code reading images directly use them).
//   runtime  Atlas_Mount reads atlas.json from the package; loading an
//            atlased path gives a Texture whose `texture` is the page and
//            `region` its rectangle - Texture_Size / Texture_Src turn
//            sizes and source rectangles into page coordinates. Pages load
//            on first use and unload with their last sprite.
//
// The editor never sees atlases: they exist only in exported packages.
// ============================================================================

ATLAS_PAGE :: 2048 // max page size (px); smaller when everything fits
ATLAS_GAP :: 2     // between sprites, filled with their edge pixels
ATLAS_JSON :: "atlas/atlas.json"

Atlas_Entry :: struct {
	page: int,
	rect: rl.Rectangle, // in the page (px)
}

Atlas_Page :: struct {
	file:    string,
	filter:  Texture_Filter,
	texture: rl.Texture2D,
	refs:    int,
}

// Atlas_Index: a mounted package's atlas (ResourceManager.atlas). Strings
// and tables live in its arena.
Atlas_Index :: struct {
	arena:   vmem.Arena,
	ready:   bool,
	entries: map[string]Atlas_Entry, // project-relative path
	pages:   [dynamic]Atlas_Page,
}

// --- sizes and source rectangles --------------------------------------------------------

// Texture_Size: a texture's size in pixels (its region's for an atlased one).
Texture_Size :: proc(t: ^Texture) -> [2]f32 {
	if t == nil do return {}
	if t.region.width > 0 do return {t.region.width, t.region.height}
	return {f32(t.texture.width), f32(t.texture.height)}
}

// Texture_Src: a source rectangle in the texture's own pixels turned into
// the GPU texture's (offset into the page for an atlased one; negative
// sizes - flips - stay as they are).
Texture_Src :: proc(t: ^Texture, src: rl.Rectangle) -> rl.Rectangle {
	if t == nil || t.region.width <= 0 do return src
	return {src.x + t.region.x, src.y + t.region.y, src.width, src.height}
}

// Texture_Full: the whole texture as a source rectangle (GPU coordinates).
Texture_Full :: proc(t: ^Texture) -> rl.Rectangle {
	s := Texture_Size(t)
	return Texture_Src(t, {0, 0, s.x, s.y})
}

// --- packing ------------------------------------------------------------------------------

// Atlas_Pack places rectangles (sizes, gaps included by the caller) into
// pages of at most `pageSize`; returns each one's page and position, and
// each page's used size. Sizes larger than a page get page -1.
Atlas_Pack :: proc(sizes: [][2]int, pageSize: int, allocator := context.allocator) -> (pos: [][3]int, pages: [][2]int) {
	pos = make([][3]int, len(sizes), allocator)
	out := make([dynamic][2]int, allocator)
	order := make([]int, len(sizes), context.temp_allocator)
	for i in 0 ..< len(sizes) do order[i] = i
	// Biggest first (by longer side, then area): fewer, fuller pages.
	// (Insertion sort: stable, and the lists are short.)
	for i in 1 ..< len(order) {
		j := i
		for j > 0 && pack_less(sizes[order[j]], sizes[order[j - 1]]) {
			order[j], order[j - 1] = order[j - 1], order[j]
			j -= 1
		}
	}
	Free :: struct {x, y, w, h: int}
	pageFree := make([dynamic][dynamic]Free, context.temp_allocator)
	for i in order {
		w, h := sizes[i].x, sizes[i].y
		if w > pageSize || h > pageSize || w <= 0 || h <= 0 {
			pos[i] = {-1, 0, 0}
			continue
		}
		placed := false
		for p := 0; !placed; p += 1 {
			if p == len(pageFree) {
				fl := make([dynamic]Free, context.temp_allocator)
				append(&fl, Free{0, 0, pageSize, pageSize})
				append(&pageFree, fl)
				append(&out, [2]int{0, 0})
			}
			fl := &pageFree[p]
			// Best short side fit.
			best, bestShort, bestLong := -1, max(int), max(int)
			for f, k in fl {
				if f.w < w || f.h < h do continue
				short := min(f.w - w, f.h - h)
				long := max(f.w - w, f.h - h)
				if short < bestShort || (short == bestShort && long < bestLong) {
					best, bestShort, bestLong = k, short, long
				}
			}
			if best < 0 do continue
			x, y := fl[best].x, fl[best].y
			pos[i] = {p, x, y}
			out[p] = {max(out[p].x, x + w), max(out[p].y, y + h)}
			placed = true
			// Split every free rectangle the new one overlaps (the others stay).
			used := Free{x, y, w, h}
			next := make([dynamic]Free, 0, len(fl) + 4, context.temp_allocator)
			for f in fl {
				if used.x >= f.x + f.w || used.x + used.w <= f.x || used.y >= f.y + f.h || used.y + used.h <= f.y {
					append(&next, f)
					continue
				}
				if used.x > f.x do append(&next, Free{f.x, f.y, used.x - f.x, f.h})
				if used.x + used.w < f.x + f.w do append(&next, Free{used.x + used.w, f.y, f.x + f.w - used.x - used.w, f.h})
				if used.y > f.y do append(&next, Free{f.x, f.y, f.w, used.y - f.y})
				if used.y + used.h < f.y + f.h do append(&next, Free{f.x, used.y + used.h, f.w, f.y + f.h - used.y - used.h})
			}
			clear(fl)
			append(fl, ..next[:])
			// Drop free rectangles inside others.
			for a := 0; a < len(fl); a += 1 {
				for b := 0; b < len(fl); b += 1 {
					if a == b do continue
					fa, fb := fl[a], fl[b]
					if fa.x >= fb.x && fa.y >= fb.y && fa.x + fa.w <= fb.x + fb.w && fa.y + fa.h <= fb.y + fb.h {
						unordered_remove(fl, a)
						a -= 1
						break
					}
				}
			}
		}
	}
	return pos, out[:]
}

@(private = "file")
pack_less :: proc(a, b: [2]int) -> bool {
	la, lb := max(a.x, a.y), max(b.x, b.y)
	if la != lb do return la > lb
	return a.x * a.y > b.x * b.y
}

// --- export ------------------------------------------------------------------------------

// Atlas_Build packs the textures flagged "atlas" (that `include` accepts)
// into pages and adds them and atlas.json to the package's overrides.
// Returns the number of textures packed and pages written.
Atlas_Build :: proc(projectDir: string, overrides: ^map[string][]u8, include: proc(path: string, data: rawptr) -> bool = nil, includeData: rawptr = nil, allocator := context.allocator) -> (sprites: int, pageCount: int) {
	absDir, absErr := filepath.abs(projectDir, context.temp_allocator)
	if absErr != nil do return
	Item :: struct {rel: string, img: rl.Image, filter: Texture_Filter}
	items := make([dynamic]Item, context.temp_allocator)
	defer for it in items do rl.UnloadImage(it.img)
	for fullpath in os.walk_files(absDir) {
		if !Asset_IsImportFile(fullpath) do continue
		asset := fullpath[:len(fullpath) - len(IMPORT_SUFFIX)]
		rel, err := filepath.rel(absDir, asset, context.temp_allocator)
		if err != nil do continue
		rel, _ = strings.replace_all(rel, "\\", "/", context.temp_allocator)
		if include != nil && !include(rel, includeData) do continue
		data, rerr := os.read_entire_file(fullpath, context.temp_allocator)
		if rerr != nil do continue
		imp: Asset_Import
		Asset_ImportParse(string(data), &imp, context.temp_allocator)
		// Mipmapped / repeating textures need their own texture.
		if !imp.atlas || imp.mipmaps || imp.filter == .Trilinear do continue
		// A normal-mapped image keeps its own texture (the normal pass swaps it whole: normal_maps.odin).
		if imp.normalMap != "none" {
			if imp.normalMap != "" do continue
			ext := filepath.ext(asset)
			if ext != "" && os.is_file(strings.concatenate({asset[:len(asset) - len(ext)], NORMAL_SUFFIX, ".png"}, context.temp_allocator)) do continue
		}
		img := rl.LoadImage(fmt.ctprint(asset))
		if img.data == nil do continue
		rl.ImageFormat(&img, .UNCOMPRESSED_R8G8B8A8)
		append(&items, Item{strings.clone(rel, context.temp_allocator), img, imp.filter})
	}
	if len(items) == 0 do return
	// Deterministic output (walk order differs between systems).
	slice.sort_by(items[:], proc(a, b: Item) -> bool {return a.rel < b.rel})

	sbJ := strings.builder_make(context.temp_allocator)
	strings.write_string(&sbJ, "{\"pages\": [")
	sprJ := strings.builder_make(context.temp_allocator)
	nSpr := 0
	for filter in Texture_Filter {
		group := make([dynamic]int, context.temp_allocator)
		for it, i in items do if it.filter == filter do append(&group, i)
		if len(group) == 0 do continue
		sizes := make([][2]int, len(group), context.temp_allocator)
		for gi, k in group do sizes[k] = {int(items[gi].img.width) + ATLAS_GAP * 2, int(items[gi].img.height) + ATLAS_GAP * 2}
		pos, used := Atlas_Pack(sizes, ATLAS_PAGE, context.temp_allocator)
		for size, p in used {
			page := rl.GenImageColor(i32(size.x), i32(size.y), rl.BLANK)
			for gi, k in group {
				if pos[k][0] != p do continue
				it := items[gi]
				x, y := i32(pos[k][1] + ATLAS_GAP), i32(pos[k][2] + ATLAS_GAP)
				iw, ih := f32(it.img.width), f32(it.img.height)
				rl.ImageDraw(&page, it.img, {0, 0, iw, ih}, {f32(x), f32(y), iw, ih}, rl.WHITE)
				atlas_extrude(&page, it.img, x, y)
				fmt.sbprintf(&sprJ, "%s\n  %q: {{\"page\": %d, \"rect\": [%d, %d, %d, %d]}}", "," if nSpr > 0 else "", it.rel, pageCount, x, y, it.img.width, it.img.height)
				nSpr += 1
				sprites += 1
			}
			size_: i32
			png := rl.ExportImageToMemory(page, ".png", &size_)
			rl.UnloadImage(page)
			if png == nil do continue
			bytes := make([]byte, int(size_), allocator)
			copy(bytes, ([^]u8)(png)[:size_])
			rl.MemFree(png)
			file := fmt.aprintf("atlas/page_%d.png", pageCount, allocator = allocator)
			overrides[file] = bytes
			fmt.sbprintf(&sbJ, "%s{{\"file\": %q, \"filter\": %q}}", ", " if pageCount > 0 else "", file, texture_filter_name(filter))
			pageCount += 1
		}
		// (Sprites too big for a page get page -1: left out, they load as
		// their own textures.)
	}
	strings.write_string(&sbJ, "],\n\"sprites\": {")
	strings.write_string(&sbJ, strings.to_string(sprJ))
	strings.write_string(&sbJ, "\n}}\n")
	overrides[strings.clone(ATLAS_JSON, allocator)] = transmute([]u8)strings.clone(strings.to_string(sbJ), allocator)
	return
}

// atlas_extrude repeats a sprite's edge pixels into the gap around it.
@(private = "file")
atlas_extrude :: proc(page: ^rl.Image, img: rl.Image, x, y: i32) {
	w, h := img.width, img.height
	src := ([^]rl.Color)(img.data)
	dst := ([^]rl.Color)(page.data)
	pw, ph := page.width, page.height
	for g in i32(1) ..= ATLAS_GAP {
		for i in 0 ..< w {
			if y - g >= 0 do dst[(y - g) * pw + x + i] = src[i]
			if y + h - 1 + g < ph do dst[(y + h - 1 + g) * pw + x + i] = src[(h - 1) * w + i]
		}
		for j in -g ..< h + g {
			sj := clamp(j, 0, h - 1)
			if y + j < 0 || y + j >= ph do continue
			if x - g >= 0 do dst[(y + j) * pw + x - g] = src[sj * w]
			if x + w - 1 + g < pw do dst[(y + j) * pw + x + w - 1 + g] = src[sj * w + w - 1]
		}
	}
}

// --- runtime ------------------------------------------------------------------------------

// Atlas_Mount reads a package's atlas.json (no atlas: nothing to do).
Atlas_Mount :: proc(rm: ^ResourceManager) -> bool {
	Atlas_Unmount(rm)
	if rm == nil || rm.package_ == nil do return false
	data, ok := RayzrPackage_ReadFile(rm.package_, ATLAS_JSON, context.temp_allocator)
	if !ok do return false
	return Atlas_Parse(&rm.atlas, string(data))
}

// Atlas_Parse fills an index from atlas.json text.
Atlas_Parse :: proc(ix: ^Atlas_Index, text: string) -> bool {
	_ = vmem.arena_init_growing(&ix.arena)
	ix.ready = true
	a := vmem.arena_allocator(&ix.arena)
	ix.entries = make(map[string]Atlas_Entry, 64, a)
	ix.pages = make([dynamic]Atlas_Page, a)
	v, err := json.parse_string(text, allocator = context.temp_allocator)
	if err != nil do return false
	root, isObj := v.(json.Object)
	if !isObj do return false
	if pages, ok := root["pages"].(json.Array); ok {
		for pv in pages {
			po, _ := pv.(json.Object)
			pg := Atlas_Page{}
			if f, ok2 := po["file"].(json.String); ok2 do pg.file = strings.clone(f, a)
			if f, ok2 := po["filter"].(json.String); ok2 {
				switch f {
				case "bilinear": pg.filter = .Bilinear
				case "trilinear": pg.filter = .Trilinear
				}
			}
			append(&ix.pages, pg)
		}
	}
	num :: proc(v: json.Value) -> f32 {
		#partial switch x in v {
		case json.Float: return f32(x)
		case json.Integer: return f32(x)
		}
		return 0
	}
	if spr, ok := root["sprites"].(json.Object); ok {
		for path, sv in spr {
			so, _ := sv.(json.Object)
			r, _ := so["rect"].(json.Array)
			if len(r) < 4 do continue
			p := int(num(so["page"]))
			if p < 0 || p >= len(ix.pages) do continue
			ix.entries[strings.clone(path, a)] = {page = p, rect = {num(r[0]), num(r[1]), num(r[2]), num(r[3])}}
		}
	}
	return true
}

// Atlas_Unmount frees the index (pages still loaded are unloaded).
Atlas_Unmount :: proc(rm: ^ResourceManager) {
	if rm == nil || !rm.atlas.ready do return
	for p in rm.atlas.pages do if p.texture.id > 0 && rl.IsWindowReady() do rl.UnloadTexture(p.texture)
	vmem.arena_destroy(&rm.atlas.arena)
	rm.atlas = {}
}

// Atlas_Lookup: an atlased texture's page and rectangle.
Atlas_Lookup :: proc(rm: ^ResourceManager, filePath: string) -> (Atlas_Entry, bool) {
	if rm == nil || !rm.atlas.ready do return {}, false
	return rm.atlas.entries[Asset_RelPath(rm, filePath)]
}

Atlas_Has :: proc(rm: ^ResourceManager, filePath: string) -> bool {
	_, ok := Atlas_Lookup(rm, filePath)
	return ok
}

// Atlas_AcquirePage: a page's GPU texture (loaded on first use; a reference).
Atlas_AcquirePage :: proc(rm: ^ResourceManager, page: int) -> rl.Texture2D {
	pg := &rm.atlas.pages[page]
	pg.refs += 1
	if pg.texture.id == 0 && rl.IsWindowReady() {
		if bytes, ok := resource_bytes(rm, pg.file); ok {
			defer delete(bytes)
			img := rl.LoadImageFromMemory(".png", raw_data(bytes), i32(len(bytes)))
			pg.texture = rl.LoadTextureFromImage(img)
			rl.UnloadImage(img)
			Texture_ApplyImport(&pg.texture, {filter = pg.filter, wrap = .Clamp})
		}
	}
	return pg.texture
}

// Atlas_ReleasePage drops a reference; the last one unloads the page.
Atlas_ReleasePage :: proc(rm: ^ResourceManager, page: int) {
	if rm == nil || !rm.atlas.ready || page < 0 || page >= len(rm.atlas.pages) do return
	pg := &rm.atlas.pages[page]
	pg.refs -= 1
	if pg.refs > 0 do return
	pg.refs = 0
	if pg.texture.id > 0 && rl.IsWindowReady() do rl.UnloadTexture(pg.texture)
	pg.texture = {}
}
