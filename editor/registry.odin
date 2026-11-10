package editor

import "core:bytes"
import "core:compress/zlib"
import "core:crypto/sha2"
import "core:encoding/endian"
import "core:encoding/hex"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import e "../engine"

// ============================================================================
// Plugin and template registry (#296; docs/editor/registry.md): community
// plugins and project templates listed in a JSON index (the rayzr-registry
// GitHub repository's index.json; Settings can point at another one), browsed
// and installed from Tools > Registry (registry_window.odin).
//
// - The index: {"format": 1, "entries": [...]}; each entry names its id,
//   kind (plugin / template), version, a zip's url (absolute, or relative to
//   the index's own url) and that zip's sha256, the oldest editor it needs
//   ("rayzr": ">=1.1.0"), and what the window shows (name, author,
//   description, license, repo, homepage, screenshot, tags, permissions).
// - Installing: the zip is downloaded, its SHA-256 must be the index's (or
//   nothing is installed), it's unpacked (here: stored + deflate, no paths
//   outside the folder) into <root>/.<id>.installing, which must hold the
//   kind's manifest (plugin.json / template.json), then replaces <root>/<id>.
//   A .registry.json in it records what was installed (updates, Remove).
// - Plugins go to the user plugins folder (every project) or this project's
//   plugins/; templates to the user templates folder (the Welcome window
//   lists them). Remove only deletes folders the registry installed.
// ============================================================================

// The official index (the rayzr-registry repository; authors add entries by
// pull request: docs/editor/publishing.md).
REGISTRY_INDEX_URL :: "https://raw.githubusercontent.com/bcrowe306/rayzr-registry/main/index.json"
REGISTRY_FORMAT :: 1
REGISTRY_RECORD :: ".registry.json" // in an installed folder: what was installed

Registry_Kind :: enum {
	Plugin,
	Template,
}

Registry_Entry :: struct {
	id, name, author, description: string,
	kind:        Registry_Kind,
	version:     string,
	url:         string, // the zip (resolved against the index's url)
	sha256:      string, // lower-case hex
	rayzr:       string, // the oldest editor it needs ("1.1.0"; "" = any)
	license:     string,
	repo:        string, // "owner/name" (its GitHub page)
	homepage:    string,
	screenshot:  string, // an image url (resolved)
	tags:        []string,
	permissions: []string, // a plugin's: "process", "network"
}

Registry_Index :: struct {
	entries:  []Registry_Entry,
	warnings: []string, // entries skipped (why)
}

// Registry_ParseIndex reads an index.json (everything in `allocator`).
// Entries that are missing what an install needs are skipped, with a
// warning each; ok = false when it isn't an index at all.
Registry_ParseIndex :: proc(data: []u8, baseURL: string, allocator := context.allocator) -> (idx: Registry_Index, err: string, ok: bool) {
	context.allocator = allocator
	v, jerr := json.parse(data, allocator = context.temp_allocator)
	if jerr != nil do return {}, fmt.aprintf("not JSON (%v)", jerr), false
	root, isObj := v.(json.Object)
	if !isObj do return {}, strings.clone("not an index (no object)"), false
	if f, num := root["format"].(json.Float); num && int(f) > REGISTRY_FORMAT {
		return {}, fmt.aprintf("index format %d is newer than this editor reads (%d): update the editor", int(f), REGISTRY_FORMAT), false
	}
	list, isArr := root["entries"].(json.Array)
	if !isArr do return {}, strings.clone("not an index (no \"entries\")"), false
	entries := make([dynamic]Registry_Entry)
	warnings := make([dynamic]string)
	seen := make(map[string]bool, allocator = context.temp_allocator)
	str :: proc(o: json.Object, k: string) -> string {
		s, _ := o[k].(json.String)
		return strings.clone(strings.trim_space(s))
	}
	strs :: proc(o: json.Object, k: string) -> []string {
		a, _ := o[k].(json.Array)
		out := make([dynamic]string)
		for x in a do if s, isStr := x.(json.String); isStr do append(&out, strings.clone(s))
		return out[:]
	}
	for item, i in list {
		o, isEntry := item.(json.Object)
		if !isEntry {
			append(&warnings, fmt.aprintf("entry %d: not an object", i + 1))
			continue
		}
		en := Registry_Entry {
			id          = str(o, "id"),
			name        = str(o, "name"),
			author      = str(o, "author"),
			description = str(o, "description"),
			version     = str(o, "version"),
			sha256      = strings.to_lower(strings.trim_space(o["sha256"].(json.String) or_else "")),
			rayzr       = strings.clone(strings.trim_left(o["rayzr"].(json.String) or_else "", ">= ")),
			license     = str(o, "license"),
			repo        = str(o, "repo"),
			homepage    = str(o, "homepage"),
			tags        = strs(o, "tags"),
			permissions = strs(o, "permissions"),
		}
		en.url = Registry_ResolveURL(baseURL, o["url"].(json.String) or_else "")
		if s, has := o["screenshot"].(json.String); has && s != "" do en.screenshot = Registry_ResolveURL(baseURL, s)
		kind := o["kind"].(json.String) or_else ""
		why := ""
		switch {
		case !Registry_ValidId(en.id): why = "id must be lower-case letters, digits, _ or - (1-64)"
		case kind == "plugin": en.kind = .Plugin
		case kind == "template": en.kind = .Template
		case: why = fmt.tprintf("kind %q (plugin or template)", kind)
		}
		if why == "" {
			switch {
			case en.id in seen: why = "listed twice"
			case en.version == "": why = "no version"
			case en.url == "": why = "no url"
			case !registry_valid_sha(en.sha256): why = "sha256 must be 64 hex digits"
			}
		}
		if why != "" {
			append(&warnings, fmt.aprintf("%s: %s", en.id if en.id != "" else fmt.tprintf("entry %d", i + 1), why))
			continue
		}
		seen[en.id] = true
		if en.name == "" do en.name = en.id
		append(&entries, en)
	}
	return {entries[:], warnings[:]}, "", true
}

// Registry_ValidId: an id is a folder name everywhere (lower-case letters,
// digits, '_' and '-'; not starting with '.' or '-').
Registry_ValidId :: proc(id: string) -> bool {
	if len(id) == 0 || len(id) > 64 || id[0] == '-' do return false
	for c in id {
		switch c {
		case 'a' ..= 'z', '0' ..= '9', '_', '-':
		case: return false
		}
	}
	return true
}

@(private = "file")
registry_valid_sha :: proc(s: string) -> bool {
	if len(s) != 64 do return false
	for c in s {
		switch c {
		case '0' ..= '9', 'a' ..= 'f':
		case: return false
		}
	}
	return true
}

// Registry_ResolveURL: `ref` as is when it's a url ("https://...",
// "file://..."), else relative to the index's folder (a fixture or a
// self-hosted index next to its zips). Absolute local paths become file://.
Registry_ResolveURL :: proc(base, ref: string, allocator := context.allocator) -> string {
	ref := strings.trim_space(ref)
	if ref == "" do return ""
	if strings.contains(ref, "://") do return strings.clone(ref, allocator)
	if filepath.is_abs(ref) do return strings.concatenate({"file://", ref}, allocator)
	b := base
	if i := strings.last_index_byte(b, '/'); i >= 0 do b = b[:i + 1]
	else do b = ""
	if !strings.contains(b, "://") && b != "" && filepath.is_abs(b) do return strings.concatenate({"file://", b, ref}, allocator)
	return strings.concatenate({b, ref}, allocator)
}

// Registry_Compatible: this editor (`editor`, e.g. e.RAYZR_RELEASE) can use
// the entry - as plugin.json's "editor" check: development builds use all.
Registry_Compatible :: proc(en: Registry_Entry, editor: string) -> bool {
	if en.rayzr == "" || e.Version_IsDev(editor) do return true
	return e.Version_Compare(editor, en.rayzr) >= 0
}

// Registry_SHA256: the bytes' SHA-256, lower-case hex (temp).
Registry_SHA256 :: proc(data: []u8) -> string {
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, data)
	sum: [sha2.DIGEST_SIZE_256]u8
	sha2.final(&ctx, sum[:])
	return string(hex.encode(sum[:], context.temp_allocator))
}

// ----------------------------------------------------------------------------
// Zip files (what a release asset is): read the central directory, inflate
// each file. Only stored and deflated files (what every zip tool writes); no
// encryption, no zip64.
// ----------------------------------------------------------------------------

Zip_File :: struct {
	name: string, // "folder/file.lua" ('/', as stored)
	dir:  bool,
	data: []u8,
}

// Zip_Read lists a zip's files with their contents (temp). err names what's
// wrong ("" = ok).
Zip_Read :: proc(data: []u8) -> (files: []Zip_File, err: string) {
	u16le :: proc(b: []u8, at: int) -> int {v, _ := endian.get_u16(b[at:], .Little); return int(v)}
	u32le :: proc(b: []u8, at: int) -> int {v, _ := endian.get_u32(b[at:], .Little); return int(v)}
	// The end of central directory record (the last 22 bytes + a comment).
	eocd := -1
	for i := len(data) - 22; i >= max(0, len(data) - 22 - 65535); i -= 1 {
		if u32le(data, i) == 0x06054b50 {
			eocd = i
			break
		}
	}
	if eocd < 0 do return nil, "not a zip file"
	count := u16le(data, eocd + 10)
	at := u32le(data, eocd + 16)
	out := make([dynamic]Zip_File, context.temp_allocator)
	for _ in 0 ..< count {
		if at + 46 > len(data) || u32le(data, at) != 0x02014b50 do return nil, "damaged zip (central directory)"
		flags := u16le(data, at + 8)
		method := u16le(data, at + 10)
		csize := u32le(data, at + 20)
		usize := u32le(data, at + 24)
		nlen, xlen, clen := u16le(data, at + 28), u16le(data, at + 30), u16le(data, at + 32)
		local := u32le(data, at + 42)
		if at + 46 + nlen > len(data) do return nil, "damaged zip (name)"
		name := string(data[at + 46:][:nlen])
		at += 46 + nlen + xlen + clen
		if flags & 1 != 0 do return nil, fmt.tprintf("%s is encrypted", name)
		if csize == 0xFFFFFFFF || usize == 0xFFFFFFFF || local == 0xFFFFFFFF do return nil, "zip64 isn't supported"
		if local + 30 > len(data) || u32le(data, local) != 0x04034b50 do return nil, fmt.tprintf("damaged zip (%s)", name)
		start := local + 30 + u16le(data, local + 26) + u16le(data, local + 28)
		if start + csize > len(data) do return nil, fmt.tprintf("damaged zip (%s is cut short)", name)
		raw := data[start:][:csize]
		f := Zip_File{name = name, dir = strings.has_suffix(name, "/")}
		switch method {
		case 0:
			f.data = raw
		case 8:
			buf: bytes.Buffer
			bytes.buffer_init_allocator(&buf, 0, usize, context.temp_allocator)
			if zerr := zlib.inflate(raw, &buf, raw = true, expected_output_size = usize); zerr != nil {
				return nil, fmt.tprintf("can't unpack %s (%v)", name, zerr)
			}
			f.data = bytes.buffer_to_bytes(&buf)
		case:
			return nil, fmt.tprintf("%s uses compression method %d (only stored and deflate)", name, method)
		}
		if !f.dir && len(f.data) != usize do return nil, fmt.tprintf("damaged zip (%s's size)", name)
		append(&out, f)
	}
	return out[:], ""
}

// zip_safe_path: a stored name as a relative path inside the folder (false:
// absolute, "..", a drive letter - a zip that writes outside it).
@(private = "file")
zip_safe_path :: proc(name: string) -> (string, bool) {
	n, _ := strings.replace_all(name, "\\", "/", context.temp_allocator)
	if n == "" || n[0] == '/' || strings.contains(n, ":") do return "", false
	for part in strings.split(n, "/", context.temp_allocator) do if part == ".." do return "", false
	return n, true
}

// Zip_Extract writes a zip's files into `dest` (made). When every file is in
// one top folder (GitHub's "Source code" zips, a zipped folder), that folder
// is left out: its contents land in dest.
Zip_Extract :: proc(data: []u8, dest: string) -> (err: string) {
	files, zerr := Zip_Read(data)
	if zerr != "" do return zerr
	// The common top folder, if any.
	top, shared := "", true
	for f in files {
		n, ok := zip_safe_path(f.name)
		if !ok do return fmt.tprintf("%q points outside the folder", f.name)
		if strings.has_prefix(n, "__MACOSX/") do continue
		slash := strings.index_byte(n, '/')
		first := n[:slash + 1] if slash >= 0 else ""
		switch {
		case first == "": shared = false
		case top == "": top = first
		case first != top: shared = false
		}
	}
	if !shared do top = ""
	if os.make_directory_all(dest) != nil && !os.is_dir(dest) do return fmt.tprintf("can't make %s", dest)
	for f in files {
		n, _ := zip_safe_path(f.name)
		if strings.has_prefix(n, "__MACOSX/") || strings.has_suffix(n, ".DS_Store") do continue
		n = n[len(top):] if top != "" && strings.has_prefix(n, top) else n
		if n == "" do continue
		p, _ := filepath.join({dest, n}, context.temp_allocator)
		if f.dir {
			_ = os.make_directory_all(p)
			continue
		}
		_ = os.make_directory_all(filepath.dir(p, context.temp_allocator))
		if werr := os.write_entire_file(p, f.data); werr != nil do return fmt.tprintf("can't write %s (%v)", p, werr)
	}
	return ""
}

// ----------------------------------------------------------------------------
// Installing
// ----------------------------------------------------------------------------

// Registry_ManifestName: the file an entry's folder must have.
Registry_ManifestName :: proc(kind: Registry_Kind) -> string {
	return "plugin.json" if kind == .Plugin else "template.json"
}

// Registry_Install puts a downloaded zip in <root>/<id>: its SHA-256 checked
// against the index's, unpacked beside, checked for the kind's manifest, then
// swapped in for an older copy. err says why not ("" = installed).
Registry_Install :: proc(en: Registry_Entry, zip: []u8, root: string) -> (err: string) {
	if !Registry_ValidId(en.id) do return "bad id"
	if got := Registry_SHA256(zip); got != en.sha256 {
		return fmt.tprintf("the download's SHA-256 (%s) isn't the index's (%s): not installed", got, en.sha256)
	}
	if os.make_directory_all(root) != nil && !os.is_dir(root) do return fmt.tprintf("can't make %s", root)
	final, _ := filepath.join({root, en.id}, context.temp_allocator)
	if os.is_dir(final) && !Registry_IsManaged(final) {
		return fmt.tprintf("%s exists and wasn't installed from the registry: remove or rename it first", final)
	}
	stage, _ := filepath.join({root, fmt.tprintf(".%s.installing", en.id)}, context.temp_allocator)
	_ = os.remove_all(stage)
	ok := false
	defer if !ok do _ = os.remove_all(stage)
	if zerr := Zip_Extract(zip, stage); zerr != "" do return zerr
	manifest, _ := filepath.join({stage, Registry_ManifestName(en.kind)}, context.temp_allocator)
	if !os.is_file(manifest) do return fmt.tprintf("the zip has no %s at its top", Registry_ManifestName(en.kind))
	// A plugin asks for no more than the index (and the trust dialog) said.
	if en.kind == .Plugin {
		data, _ := os.read_entire_file(manifest, context.temp_allocator)
		v, jerr := json.parse(data, allocator = context.temp_allocator)
		if jerr != nil do return "its plugin.json isn't valid JSON"
		o, _ := v.(json.Object)
		perms, _ := o["permissions"].(json.Array)
		for p in perms {
			name, _ := p.(json.String)
			listed := false
			for q in en.permissions do if q == name do listed = true
			if !listed do return fmt.tprintf("its plugin.json asks for the %q permission, which the index doesn't list: not installed", name)
		}
	}
	rec, _ := filepath.join({stage, REGISTRY_RECORD}, context.temp_allocator)
	when_ := time.now()
	record := fmt.tprintf(`{{"id": %q, "kind": %q, "version": %q, "sha256": %q, "url": %q, "installed": %d}}` + "\n",
		en.id, "plugin" if en.kind == .Plugin else "template", en.version, en.sha256, en.url, time.to_unix_seconds(when_))
	if werr := os.write_entire_file(rec, transmute([]u8)record); werr != nil do return fmt.tprintf("can't write %s", rec)
	// Swap: the old copy aside, the new one in, the old one gone.
	old, _ := filepath.join({root, fmt.tprintf(".%s.old", en.id)}, context.temp_allocator)
	_ = os.remove_all(old)
	if os.is_dir(final) && os.rename(final, old) != nil do return fmt.tprintf("can't replace %s (in use?)", final)
	if rerr := os.rename(stage, final); rerr != nil {
		if os.is_dir(old) do _ = os.rename(old, final)
		return fmt.tprintf("can't move it into %s (%v)", final, rerr)
	}
	_ = os.remove_all(old)
	ok = true
	return ""
}

// Registry_IsManaged: the folder was installed from the registry.
Registry_IsManaged :: proc(dir: string) -> bool {
	p, _ := filepath.join({dir, REGISTRY_RECORD}, context.temp_allocator)
	return os.is_file(p)
}

// Registry_InstalledVersion: the version installed in <root>/<id> from the
// registry ("" = not installed from it).
Registry_InstalledVersion :: proc(root, id: string) -> string {
	if !Registry_ValidId(id) do return ""
	p, _ := filepath.join({root, id, REGISTRY_RECORD}, context.temp_allocator)
	data, err := os.read_entire_file(p, context.temp_allocator)
	if err != nil do return ""
	v, jerr := json.parse(data, allocator = context.temp_allocator)
	if jerr != nil do return ""
	o, _ := v.(json.Object)
	return o["version"].(json.String) or_else "?"
}

// Registry_Uninstall removes <root>/<id> - only a folder the registry put
// there (never one made by hand).
Registry_Uninstall :: proc(root, id: string) -> (err: string) {
	if !Registry_ValidId(id) do return "bad id"
	dir, _ := filepath.join({root, id}, context.temp_allocator)
	if !os.is_dir(dir) do return "not installed"
	if !Registry_IsManaged(dir) do return fmt.tprintf("%s wasn't installed from the registry: not removed", dir)
	if rerr := os.remove_all(dir); rerr != nil do return fmt.tprintf("can't remove %s (%v)", dir, rerr)
	return ""
}

// Editor_UserDir: a folder in the editor's per-user config (plugins,
// templates, registry cache) - under --user-data when given (drives, tests).
Editor_UserDir :: proc(sub: string, userDataDir := "") -> string {
	if userDataDir != "" {
		p, _ := filepath.join({userDataDir, sub}, context.temp_allocator)
		return p
	}
	home, err := os.user_home_dir(context.temp_allocator)
	if err != nil do return ""
	p, _ := filepath.join({home, ".config", "rayzr_editor", sub}, context.temp_allocator)
	return p
}
