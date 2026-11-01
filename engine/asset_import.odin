package engine

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import os "osx"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import vmem "core:mem/virtual"

// ============================================================================
// Per-asset import settings (docs/import_settings.md): a small JSON file next
// to the asset, `<asset>.import.json` - e.g. textures/hero.png.import.json -
// so the settings travel with the file (copy, rename, version control, the
// exported package):
//
//   textures   filter (point / bilinear / trilinear), wrap, mipmaps,
//              a slicing preset (columns x rows, margin, spacing) the
//              Sprite Sheet Slicer starts from, "atlas" (packed into an
//              atlas on export; docs/atlas.md), "compress" on export
//              ("keep" the file as is, or "qoi": decodes several times
//              faster than PNG, a bigger file)
//   audio      gain (dB, applied when decoded / to the stream), the bus it
//              plays into when the node / call names none
//   vector art (.svg) vector_scale (document units -> px, e.g. 0.5 for art
//              drawn twice as big), origin (the pivot new Vector Shapes get,
//              a fraction of the document box)
//
// Read when an asset loads (and cached per path, misses too - one lookup
// per path); the editor writes them and forgets the cached entry. Older
// projects' project.json "texture_import" entries still apply to textures
// without a file.
// ============================================================================

IMPORT_SUFFIX :: ".import.json"

Texture_Compress :: enum u8 {Keep, QOI}

Asset_Slice :: struct {
	grid:     [2]int, // columns, rows (0 = no preset)
	margin:   [2]int,
	spacing:  [2]int,
	cellSize: [2]int, // px per cell: slice by cell size (0 = by the grid, #233)
}

Asset_Import :: struct {
	// Textures.
	filter:   Texture_Filter,
	wrap:     Texture_Wrap,
	mipmaps:  bool,
	slice:    Asset_Slice,
	atlas:    bool,
	compress: Texture_Compress,
	normalMap: string, // its normal map (#274): "" = <image>_n.png if there is one, "none" = off, else a project path
	normalGreenDown: bool, // the normal map's green points down (DirectX style)
	// Audio.
	gainDb:   f32,
	bus:      string,
	// Vector art.
	vectorScale: f32,    // 0 = 1
	origin:      [2]f32, // the default pivot (hasOrigin)
	hasOrigin:   bool,
	// A file was found (else the defaults).
	found:    bool,
}

// The cache: entries (and their strings) live in one arena, freed together
// when the project changes (Asset_ImportsReset).
@(private = "file")
imports: struct {
	arena: vmem.Arena,
	ready: bool,
	byPath: map[string]^Asset_Import,
}

@(private = "file")
imports_alloc :: proc() -> runtime.Allocator {
	if !imports.ready {
		_ = vmem.arena_init_growing(&imports.arena)
		imports.byPath = make(map[string]^Asset_Import, 64, vmem.arena_allocator(&imports.arena))
		imports.ready = true
	}
	return vmem.arena_allocator(&imports.arena)
}

// Asset_ImportsReset forgets every cached entry (project change, shutdown).
Asset_ImportsReset :: proc() {
	if !imports.ready do return
	vmem.arena_destroy(&imports.arena)
	imports = {}
}

// Asset_ImportForget drops one path's cached entry (the editor changed or
// removed its file). The arena keeps the old bytes until the next reset.
Asset_ImportForget :: proc(rel: string) {
	if imports.ready do delete_key(&imports.byPath, rel)
}

// Asset_RelPath: a project-relative path from a full or relative one.
Asset_RelPath :: proc(rm: ^ResourceManager, filePath: string) -> string {
	rel := filePath
	if rm != nil && rm.projectDir != "" && strings.has_prefix(rel, rm.projectDir) && len(rel) > len(rm.projectDir) && rel[len(rm.projectDir)] == '/' {
		rel = rel[len(rm.projectDir) + 1:]
	}
	return rel
}

// Asset_ImportGet: an asset's settings (defaults when it has no file).
// The pointer stays valid until the entry is forgotten / reset.
Asset_ImportGet :: proc(rm: ^ResourceManager, filePath: string) -> ^Asset_Import {
	a := imports_alloc()
	rel := Asset_RelPath(rm, filePath)
	if e, ok := imports.byPath[rel]; ok do return e
	e := new(Asset_Import, a)
	data, found := asset_import_bytes(rm, filePath)
	if found {
		defer delete(data)
		Asset_ImportParse(string(data), e, a)
	}
	imports.byPath[strings.clone(rel, a)] = e
	return e
}

@(private = "file")
asset_import_bytes :: proc(rm: ^ResourceManager, filePath: string) -> ([]byte, bool) {
	side := strings.concatenate({filePath, IMPORT_SUFFIX}, context.temp_allocator)
	if rm != nil && rm.projectDir != "" && !strings.has_prefix(side, rm.projectDir) && !os.is_file(side) {
		full := strings.concatenate({rm.projectDir, "/", side}, context.temp_allocator)
		if os.is_file(full) do side = full
	}
	if os.is_file(side) {
		data, err := os.read_entire_file(side, context.allocator)
		return data, err == nil
	}
	if rm != nil do return resource_bytes(rm, side)
	return nil, false
}

// Asset_ImportParse reads a settings file's text into `e` (strings in
// `allocator`). Unknown keys are ignored; a broken file gives the defaults.
Asset_ImportParse :: proc(text: string, e: ^Asset_Import, allocator := context.allocator) {
	v, err := json.parse_string(text, allocator = context.temp_allocator)
	if err != nil do return
	o, ok := v.(json.Object)
	if !ok do return
	e.found = true
	num :: proc(o: json.Object, k: string) -> (f64, bool) {
		#partial switch x in o[k] {
		case json.Float: return x, true
		case json.Integer: return f64(x), true
		}
		return 0, false
	}
	pair :: proc(o: json.Object, k: string) -> [2]int {
		arr, ok := o[k].(json.Array)
		if !ok || len(arr) < 2 do return {}
		out: [2]int
		for i in 0 ..< 2 {
			#partial switch x in arr[i] {
			case json.Float: out[i] = int(x)
			case json.Integer: out[i] = int(x)
			}
		}
		return out
	}
	if f, isStr := o["filter"].(json.String); isStr {
		switch f {
		case "bilinear": e.filter = .Bilinear
		case "trilinear": e.filter = .Trilinear
		case: e.filter = .Point
		}
	}
	if w, isStr := o["wrap"].(json.String); isStr do e.wrap = .Clamp if w == "clamp" else .Repeat
	if m, isBool := o["mipmaps"].(json.Boolean); isBool do e.mipmaps = bool(m)
	if s, isObj := o["slice"].(json.Object); isObj {
		e.slice = {grid = pair(s, "grid"), margin = pair(s, "margin"), spacing = pair(s, "spacing"), cellSize = pair(s, "cell_size")}
		e.slice.grid = {max(e.slice.grid.x, 0), max(e.slice.grid.y, 0)}
	}
	if b, isBool := o["atlas"].(json.Boolean); isBool do e.atlas = bool(b)
	if c, isStr := o["compress"].(json.String); isStr do e.compress = .QOI if c == "qoi" else .Keep
	if nm, isStr := o["normal_map"].(json.String); isStr do e.normalMap = strings.clone(nm, allocator)
	if gd, isBool := o["normal_green_down"].(json.Boolean); isBool do e.normalGreenDown = bool(gd)
	if g, ok := num(o, "gain_db"); ok do e.gainDb = clamp(f32(g), -60, 24)
	if b, isStr := o["bus"].(json.String); isStr do e.bus = strings.clone(b, allocator)
	if s, ok := num(o, "vector_scale"); ok && s > 0 do e.vectorScale = clamp(f32(s), 0.001, 1000)
	if arr, isArr := o["origin"].(json.Array); isArr && len(arr) >= 2 {
		for i in 0 ..< 2 {
			#partial switch x in arr[i] {
			case json.Float: e.origin[i] = f32(x)
			case json.Integer: e.origin[i] = f32(x)
			}
		}
		e.hasOrigin = true
	}
}

// Asset_ImportIsDefault: nothing worth a file.
Asset_ImportIsDefault :: proc(e: Asset_Import) -> bool {
	return e.filter == .Point && e.wrap == .Repeat && !e.mipmaps && e.slice == {} && !e.atlas && e.compress == .Keep && e.gainDb == 0 && e.bus == "" && (e.vectorScale == 0 || e.vectorScale == 1) && !e.hasOrigin && e.normalMap == "" && !e.normalGreenDown
}

// Asset_ImportToJSON: a settings file's text (only what differs from the
// defaults, so the files stay short).
Asset_ImportToJSON :: proc(e: Asset_Import, allocator := context.allocator) -> string {
	sb := strings.builder_make(allocator)
	strings.write_string(&sb, "{")
	n := 0
	sep :: proc(sb: ^strings.Builder, n: ^int) {
		strings.write_string(sb, ",\n  " if n^ > 0 else "\n  ")
		n^ += 1
	}
	if e.filter != .Point {sep(&sb, &n); fmt.sbprintf(&sb, "\"filter\": %q", texture_filter_name(e.filter))}
	if e.wrap != .Repeat {sep(&sb, &n); strings.write_string(&sb, "\"wrap\": \"clamp\"")}
	if e.mipmaps {sep(&sb, &n); strings.write_string(&sb, "\"mipmaps\": true")}
	if e.slice != {} {
		sep(&sb, &n)
		s := e.slice
		fmt.sbprintf(&sb, "\"slice\": {{\"grid\": [%d, %d], \"margin\": [%d, %d], \"spacing\": [%d, %d]", s.grid.x, s.grid.y, s.margin.x, s.margin.y, s.spacing.x, s.spacing.y)
		if s.cellSize != {} do fmt.sbprintf(&sb, ", \"cell_size\": [%d, %d]", s.cellSize.x, s.cellSize.y)
		strings.write_byte(&sb, '}')
	}
	if e.atlas {sep(&sb, &n); strings.write_string(&sb, "\"atlas\": true")}
	if e.compress == .QOI {sep(&sb, &n); strings.write_string(&sb, "\"compress\": \"qoi\"")}
	if e.gainDb != 0 {sep(&sb, &n); fmt.sbprintf(&sb, "\"gain_db\": %.1f", e.gainDb)}
	if e.bus != "" {sep(&sb, &n); fmt.sbprintf(&sb, "\"bus\": %q", e.bus)}
	if e.vectorScale != 0 && e.vectorScale != 1 {sep(&sb, &n); fmt.sbprintf(&sb, "\"vector_scale\": %g", e.vectorScale)}
	if e.hasOrigin {sep(&sb, &n); fmt.sbprintf(&sb, "\"origin\": [%g, %g]", e.origin.x, e.origin.y)}
	if e.normalMap != "" {sep(&sb, &n); fmt.sbprintf(&sb, "\"normal_map\": %q", e.normalMap)}
	if e.normalGreenDown {sep(&sb, &n); strings.write_string(&sb, "\"normal_green_down\": true")}
	strings.write_string(&sb, "\n}\n" if n > 0 else "}\n")
	return strings.to_string(sb)
}

// Asset_ImportSave writes (or, at the defaults, deletes) an asset's file
// and forgets the cached entry. `fullPath` is the asset's path on disk.
Asset_ImportSave :: proc(rm: ^ResourceManager, fullPath: string, e: Asset_Import) -> bool {
	side := strings.concatenate({fullPath, IMPORT_SUFFIX}, context.temp_allocator)
	Asset_ImportForget(Asset_RelPath(rm, fullPath))
	if Asset_ImportIsDefault(e) {
		if os.is_file(side) do return os.remove(side) == nil
		return true
	}
	text := Asset_ImportToJSON(e, context.temp_allocator)
	return os.write_entire_file(side, transmute([]u8)text) == nil
}

// Asset_IsImportFile: a settings file (hidden in the Assets panel, moved
// with its asset).
Asset_IsImportFile :: proc(path: string) -> bool {return strings.has_suffix(path, IMPORT_SUFFIX)}

// Asset_GainLinear: an audio asset's gain as a factor.
Asset_GainLinear :: proc(e: ^Asset_Import) -> f32 {
	if e == nil || e.gainDb == 0 do return 1
	return math.pow(10, e.gainDb / 20)
}

// Image_ExtFor: the extension to decode bytes with - ".qoi" for QOI data
// (export may store a texture as QOI under its original name), else the
// path's own.
Image_ExtFor :: proc(bytes: []byte, path: string) -> string {
	if len(bytes) >= 4 && string(bytes[:4]) == "qoif" do return ".qoi"
	i := strings.last_index_byte(path, '.')
	return path[i:] if i >= 0 else ".png"
}

// Audio_BusFor: the bus an audio asset plays into when the node / call
// names none - its import "bus" if that bus exists, else `fallback`
// ("SFX" / "Music"), else Master.
Audio_BusFor :: proc(rm: ^ResourceManager, filePath: string, fallback: string) -> int {
	if filePath != "" {
		if e := Asset_ImportGet(rm, filePath); e.bus != "" {
			if i := Mixer_BusIndex(e.bus); i >= 0 do return i
		}
	}
	if i := Mixer_BusIndex(fallback); i >= 0 do return i
	return 0
}

// node_rm: a node's resource manager (nil outside a game).
node_rm :: proc(n: ^Node) -> ^ResourceManager {
	return &n.gameContext.game.resourceManager if n != nil && n.gameContext != nil && n.gameContext.game != nil else nil
}

// Asset_ExportOverrides adds export-time versions of assets to a package's
// overrides (archive path -> bytes, allocated with `allocator`): textures
// whose settings say "compress": "qoi" are re-encoded as QOI under their
// own name (the loaders recognise QOI data whatever the extension).
// Returns how many files it converted.
Asset_ExportOverrides :: proc(projectDir: string, overrides: ^map[string][]u8, include: proc(path: string, data: rawptr) -> bool = nil, includeData: rawptr = nil, allocator := context.allocator) -> int {
	absDir, absErr := filepath.abs(projectDir, context.temp_allocator)
	if absErr != nil do return 0
	n := 0
	for fullpath in os.walk_files(absDir) {
		if !Asset_IsImportFile(fullpath) do continue
		asset := fullpath[:len(fullpath) - len(IMPORT_SUFFIX)]
		rel, err := filepath.rel(absDir, asset, context.temp_allocator)
		if err != nil do continue
		rel, _ = strings.replace_all(rel, "\\", "/", context.temp_allocator)
		if include != nil && !include(rel, includeData) do continue
		if rel in overrides^ do continue
		data, rerr := os.read_entire_file(fullpath, context.temp_allocator)
		if rerr != nil do continue
		imp: Asset_Import
		Asset_ImportParse(string(data), &imp, context.temp_allocator)
		if imp.compress != .QOI do continue
		if bytes, ok := Image_EncodeQOI(asset, allocator); ok {
			overrides[strings.clone(rel, allocator)] = bytes
			n += 1
		}
	}
	return n
}

// Image_EncodeQOI: an image file's pixels as QOI bytes.
Image_EncodeQOI :: proc(path: string, allocator := context.allocator) -> ([]byte, bool) {
	img := rl.LoadImage(fmt.ctprint(path))
	if img.data == nil do return nil, false
	defer rl.UnloadImage(img)
	if img.format != .UNCOMPRESSED_R8G8B8A8 && img.format != .UNCOMPRESSED_R8G8B8 do rl.ImageFormat(&img, .UNCOMPRESSED_R8G8B8A8)
	tmp := fmt.tprintf("%s/rayzr_qoi_%d.qoi", Engine_TempDir(), rl.GetRandomValue(0, 1 << 30))
	if !rl.ExportImage(img, fmt.ctprint(tmp)) do return nil, false
	defer os.remove(tmp)
	data, err := os.read_entire_file(tmp, allocator)
	return data, err == nil
}
