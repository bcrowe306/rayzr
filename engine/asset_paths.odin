package engine

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Asset paths and import settings.
//
// AssetPath_Rewrite / AssetPath_Count: project-relative asset paths as
// quoted strings in project files (scenes, components, project.json, Lua),
// for renaming / moving assets with their references and Find Usages. A
// folder (`isFolder`) matches every path inside it ("textures/" prefix).
//
// Texture import settings (project.json "texture_import"): filtering, wrap
// and mipmaps per texture, applied when the texture loads.
// ============================================================================

// AssetPath_Rewrite replaces quoted references to `old` with `new` (both
// project-relative, '/' separated). Returns the new text and the count.
AssetPath_Rewrite :: proc(text, old, new: string, isFolder: bool, allocator := context.allocator) -> (string, int) {
	if old == "" || old == new do return strings.clone(text, allocator), 0
	sb := strings.builder_make(allocator)
	count := 0
	i := 0
	for i < len(text) {
		q := text[i]
		if (q == '"' || q == '\'') && i + 1 + len(old) <= len(text) && text[i + 1:i + 1 + len(old)] == old {
			end := i + 1 + len(old)
			if isFolder {
				if end < len(text) && text[end] == '/' {
					strings.write_byte(&sb, q)
					strings.write_string(&sb, new)
					i = end
					count += 1
					continue
				}
			} else if end < len(text) && text[end] == q {
				strings.write_byte(&sb, q)
				strings.write_string(&sb, new)
				strings.write_byte(&sb, q)
				i = end + 1
				count += 1
				continue
			}
		}
		strings.write_byte(&sb, q)
		i += 1
	}
	return strings.to_string(sb), count
}

// AssetPath_Count: how many quoted references to `path` a text has.
AssetPath_Count :: proc(text, path: string, isFolder: bool) -> int {
	_, n := AssetPath_Rewrite(text, path, "\x00", isFolder, context.temp_allocator)
	return n
}

// --- texture import settings ----------------------------------------------------------

Texture_Filter :: enum {
	Point,     // pixel art (raylib's default)
	Bilinear,
	Trilinear, // with mipmaps
}

Texture_Wrap :: enum {
	Repeat,
	Clamp,
}

Texture_Import :: struct {
	path:    string, // project-relative
	filter:  Texture_Filter,
	wrap:    Texture_Wrap,
	mipmaps: bool,
}

// The running project's settings (Game_LoadProjectConfig).
textureImports: [dynamic]Texture_Import

Texture_ImportsSet :: proc(list: []Texture_Import) {
	for t in textureImports do delete(t.path)
	clear(&textureImports)
	if len(list) == 0 {
		delete(textureImports) // (none: no array kept)
		textureImports = nil
		return
	}
	for t in list {
		c := t
		c.path = strings.clone(t.path)
		append(&textureImports, c)
	}
}

// Texture_ImportFor: the settings for a texture file (full or project-
// relative path); the defaults when it has none.
Texture_ImportFor :: proc(rm: ^ResourceManager, filePath: string) -> Texture_Import {
	rel := Asset_RelPath(rm, filePath)
	// The file next to the texture (asset_import.odin) wins over project.json.
	if e := Asset_ImportGet(rm, filePath); e.found do return {path = rel, filter = e.filter, wrap = e.wrap, mipmaps = e.mipmaps}
	for t in textureImports do if t.path == rel do return t
	return {path = rel}
}

// Texture_ApplyImport sets a loaded texture's filtering / wrap / mipmaps.
Texture_ApplyImport :: proc(tex: ^rl.Texture2D, imp: Texture_Import) {
	if tex == nil || tex.id == 0 || !rl.IsWindowReady() do return
	if (imp.mipmaps || imp.filter == .Trilinear) && tex.mipmaps <= 1 do rl.GenTextureMipmaps(tex)
	switch imp.filter {
	case .Point: rl.SetTextureFilter(tex^, .POINT)
	case .Bilinear: rl.SetTextureFilter(tex^, .BILINEAR)
	case .Trilinear: rl.SetTextureFilter(tex^, .TRILINEAR)
	}
	Pixel_RecordFilter(tex.id, .POINT if imp.filter == .Point else .BILINEAR if imp.filter == .Bilinear else .TRILINEAR) // (a node's Texture Filter puts it back: pixel_perfect.odin)
	rl.SetTextureWrap(tex^, .CLAMP if imp.wrap == .Clamp else .REPEAT)
}

// ResourceManager_ReapplyImports: after the settings changed (editor).
ResourceManager_ReapplyImports :: proc(rm: ^ResourceManager) {
	for t in rm.textures do if t != nil do Texture_ApplyImport(&t.texture, Texture_ImportFor(rm, t.filePath))
}

Texture_ImportIsDefault :: proc(t: Texture_Import) -> bool {
	return t.filter == .Point && t.wrap == .Repeat && !t.mipmaps
}

// texture_imports_write: project.json's "texture_import" object.
texture_imports_write :: proc(sb: ^strings.Builder, list: []Texture_Import) {
	n := 0
	for t in list do if !Texture_ImportIsDefault(t) do n += 1
	if n == 0 do return
	strings.write_string(sb, "  \"texture_import\": {\n")
	k := 0
	for t in list {
		if Texture_ImportIsDefault(t) do continue
		fmt.sbprintf(sb, "    %q: {{\"filter\": %q, \"wrap\": %q, \"mipmaps\": %t}}", t.path, texture_filter_name(t.filter), "clamp" if t.wrap == .Clamp else "repeat", t.mipmaps)
		k += 1
		strings.write_string(sb, ",\n" if k < n else "\n")
	}
	strings.write_string(sb, "  },\n")
}

texture_imports_read :: proc(root: json.Object, out: ^[dynamic]Texture_Import, allocator := context.allocator) {
	obj, ok := root["texture_import"].(json.Object)
	if !ok do return
	for path, v in obj {
		o, isObj := v.(json.Object)
		if !isObj do continue
		t := Texture_Import{path = strings.clone(path, allocator)}
		if f, isStr := o["filter"].(json.String); isStr {
			switch f {
			case "bilinear": t.filter = .Bilinear
			case "trilinear": t.filter = .Trilinear
			}
		}
		if w, isStr := o["wrap"].(json.String); isStr && w == "clamp" do t.wrap = .Clamp
		if m, isBool := o["mipmaps"].(json.Boolean); isBool do t.mipmaps = bool(m)
		append(out, t)
	}
}

texture_filter_name :: proc(f: Texture_Filter) -> string {
	switch f {
	case .Point: return "point"
	case .Bilinear: return "bilinear"
	case .Trilinear: return "trilinear"
	}
	return "point"
}

// ProjectConfig_SetTextureImport stores (or, at the defaults, drops) a
// texture's settings in the config.
ProjectConfig_SetTextureImport :: proc(cfg: ^ProjectConfig, imp: Texture_Import) {
	for &t, i in cfg.textureImport {
		if t.path != imp.path do continue
		if Texture_ImportIsDefault(imp) {
			delete(t.path)
			ordered_remove(&cfg.textureImport, i)
		} else {
			t.filter, t.wrap, t.mipmaps = imp.filter, imp.wrap, imp.mipmaps
		}
		return
	}
	if Texture_ImportIsDefault(imp) do return
	c := imp
	c.path = strings.clone(imp.path)
	append(&cfg.textureImport, c)
}
