package editor

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"

// #296: the registry's index, version checks, hashes, zips and installing
// (registry.odin), against tests/drive/fixtures/registry (make_fixture.py).

@(private = "file")
FIX_INDEX :: #load("../tests/drive/fixtures/registry/index.json")
@(private = "file")
FIX_INDEX_V2 :: #load("../tests/drive/fixtures/registry/index_v2.json")
@(private = "file")
FIX_HELLO :: #load("../tests/drive/fixtures/registry/registry_hello_zz-1.0.0.zip")
@(private = "file")
FIX_HELLO_V2 :: #load("../tests/drive/fixtures/registry/registry_hello_zz-1.1.0.zip")
@(private = "file")
FIX_BLANK :: #load("../tests/drive/fixtures/registry/registry_blank_zz.zip")
@(private = "file")
FIX_EVIL :: #load("../tests/drive/fixtures/registry/evil_zz.zip")
@(private = "file")
FIX_SNEAKY :: #load("../tests/drive/fixtures/registry/sneaky_zz.zip")
@(private = "file")
FIX_EXTRA :: #load("../tests/drive/fixtures/registry/extra_sha256.json")

@(private = "file")
reg_temp_dir :: proc(t: ^testing.T, name: string) -> string {
	base := os.get_env("TMPDIR", context.temp_allocator)
	if base == "" do base = "/tmp"
	dir, _ := filepath.join({base, fmt.tprintf("rayzr_registry_%s_%d", name, time.to_unix_nanoseconds(time.now()))}, context.temp_allocator)
	testing.expect(t, os.make_directory_all(dir) == nil)
	return dir
}

@(private = "file")
reg_entry :: proc(idx: Registry_Index, id: string) -> (Registry_Entry, bool) {
	for en in idx.entries do if en.id == id do return en, true
	return {}, false
}

@(test)
test_registry_parse_index :: proc(t: ^testing.T) {
	idx, err, ok := Registry_ParseIndex(FIX_INDEX, "https://example.com/reg/index.json", context.temp_allocator)
	testing.expectf(t, ok, "parse failed: %s", err)
	testing.expect_value(t, len(idx.entries), 4)
	// The bad id and the missing hash are skipped, each with a warning.
	testing.expect_value(t, len(idx.warnings), 2)
	testing.expect(t, strings.contains(idx.warnings[0], "id must be"))
	testing.expect(t, strings.contains(idx.warnings[1], "sha256"))
	hello, found := reg_entry(idx, "registry_hello_zz")
	testing.expect(t, found)
	testing.expect_value(t, hello.kind, Registry_Kind.Plugin)
	testing.expect_value(t, hello.version, "1.0.0")
	testing.expect_value(t, hello.rayzr, "1.0.0") // (">=" trimmed)
	testing.expect_value(t, hello.license, "MIT")
	testing.expect_value(t, len(hello.tags), 2)
	// Relative urls are the index's neighbours.
	testing.expect_value(t, hello.url, "https://example.com/reg/registry_hello_zz-1.0.0.zip")
	testing.expect_value(t, hello.screenshot, "https://example.com/reg/hello_shot.png")
	blank, _ := reg_entry(idx, "registry_blank_zz")
	testing.expect_value(t, blank.kind, Registry_Kind.Template)

	// Not an index; a newer format.
	_, _, ok = Registry_ParseIndex(transmute([]u8)string("[1, 2]"), "", context.temp_allocator)
	testing.expect(t, !ok)
	_, _, ok = Registry_ParseIndex(transmute([]u8)string("nope"), "", context.temp_allocator)
	testing.expect(t, !ok)
	_, err, ok = Registry_ParseIndex(transmute([]u8)string(`{"format": 9, "entries": []}`), "", context.temp_allocator)
	testing.expect(t, !ok && strings.contains(err, "newer"))
	// The same id twice: the second is skipped.
	twice := fmt.tprintf(`{{"entries": [{{"id": "a", "kind": "plugin", "version": "1", "url": "a.zip", "sha256": "%s"}},
		{{"id": "a", "kind": "plugin", "version": "2", "url": "a.zip", "sha256": "%s"}}]}}`, strings.repeat("a", 64, context.temp_allocator), strings.repeat("b", 64, context.temp_allocator))
	idx, _, ok = Registry_ParseIndex(transmute([]u8)twice, "", context.temp_allocator)
	testing.expect(t, ok && len(idx.entries) == 1 && idx.entries[0].version == "1")
	testing.expect(t, len(idx.warnings) == 1 && strings.contains(idx.warnings[0], "twice"))
}

@(test)
test_registry_ids_and_urls :: proc(t: ^testing.T) {
	testing.expect(t, Registry_ValidId("level_notes-2"))
	testing.expect(t, !Registry_ValidId(""))
	testing.expect(t, !Registry_ValidId("../x"))
	testing.expect(t, !Registry_ValidId(".hidden"))
	testing.expect(t, !Registry_ValidId("-x"))
	testing.expect(t, !Registry_ValidId("Caps"))
	testing.expect_value(t, Registry_ResolveURL("https://a.b/c/index.json", "https://x.y/z.zip", context.temp_allocator), "https://x.y/z.zip")
	testing.expect_value(t, Registry_ResolveURL("https://a.b/c/index.json", "z.zip", context.temp_allocator), "https://a.b/c/z.zip")
	testing.expect_value(t, Registry_ResolveURL("file:///tmp/r/index.json", "sub/z.zip", context.temp_allocator), "file:///tmp/r/sub/z.zip")
	when ODIN_OS != .Windows {
		testing.expect_value(t, Registry_ResolveURL("/tmp/r/index.json", "z.zip", context.temp_allocator), "file:///tmp/r/z.zip")
		testing.expect_value(t, Registry_ResolveURL("", "/abs/z.zip", context.temp_allocator), "file:///abs/z.zip")
	}
}

@(test)
test_registry_compatible :: proc(t: ^testing.T) {
	en := Registry_Entry{rayzr = "1.1.0"}
	testing.expect(t, Registry_Compatible(en, "1.1.0"))
	testing.expect(t, Registry_Compatible(en, "1.2.0"))
	testing.expect(t, !Registry_Compatible(en, "1.0.9"))
	testing.expect(t, !Registry_Compatible(en, "1.1.0-dev.5")) // (before 1.1.0)
	testing.expect(t, Registry_Compatible(en, "0.0.0-dev")) // local builds use everything
	testing.expect(t, Registry_Compatible({}, "0.5.0")) // no minimum
}

@(test)
test_registry_sha256 :: proc(t: ^testing.T) {
	testing.expect_value(t, Registry_SHA256(transmute([]u8)string("abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
	idx, _, _ := Registry_ParseIndex(FIX_INDEX, "", context.temp_allocator)
	hello, _ := reg_entry(idx, "registry_hello_zz")
	testing.expect_value(t, Registry_SHA256(FIX_HELLO), hello.sha256)
}

@(test)
test_registry_zip_read :: proc(t: ^testing.T) {
	files, err := Zip_Read(FIX_HELLO)
	testing.expectf(t, err == "", "zip: %s", err)
	names := make(map[string]string, allocator = context.temp_allocator)
	for f in files do names[f.name] = string(f.data)
	testing.expect(t, strings.contains(names["registry_hello_zz-1.0.0/main.lua"], "hello from the registry"))
	testing.expect(t, strings.has_prefix(names["registry_hello_zz-1.0.0/README.md"], "# Registry Hello ZZ"))
	_, err = Zip_Read(transmute([]u8)string("not a zip at all, just some text that is long enough"))
	testing.expect(t, err != "")
	// Cut short: damaged.
	hello := FIX_HELLO
	_, err = Zip_Read(hello[:len(hello) / 2])
	testing.expect(t, err != "")
}

@(test)
test_registry_install_plugin_update_remove :: proc(t: ^testing.T) {
	root := reg_temp_dir(t, "plugins")
	defer os.remove_all(root)
	idx, _, _ := Registry_ParseIndex(FIX_INDEX, "", context.temp_allocator)
	hello, _ := reg_entry(idx, "registry_hello_zz")
	testing.expect_value(t, Registry_InstalledVersion(root, hello.id), "")

	err := Registry_Install(hello, FIX_HELLO, root)
	testing.expectf(t, err == "", "install: %s", err)
	// The zip's top folder is left out: plugin.json is at <root>/<id>/.
	pj, _ := filepath.join({root, hello.id, "plugin.json"}, context.temp_allocator)
	testing.expect(t, os.is_file(pj))
	testing.expect_value(t, Registry_InstalledVersion(root, hello.id), "1.0.0")
	stage, _ := filepath.join({root, ".registry_hello_zz.installing"}, context.temp_allocator)
	testing.expect(t, !os.exists(stage))

	// An update replaces it.
	idx2, _, _ := Registry_ParseIndex(FIX_INDEX_V2, "", context.temp_allocator)
	hello2, _ := reg_entry(idx2, "registry_hello_zz")
	err = Registry_Install(hello2, FIX_HELLO_V2, root)
	testing.expectf(t, err == "", "update: %s", err)
	testing.expect_value(t, Registry_InstalledVersion(root, hello.id), "1.1.0")
	data, _ := os.read_entire_file(pj, context.temp_allocator)
	testing.expect(t, strings.contains(string(data), "1.1.0"))
	old, _ := filepath.join({root, ".registry_hello_zz.old"}, context.temp_allocator)
	testing.expect(t, !os.exists(old))

	// Remove.
	testing.expect_value(t, Registry_Uninstall(root, hello.id), "")
	dir, _ := filepath.join({root, hello.id}, context.temp_allocator)
	testing.expect(t, !os.exists(dir))
	testing.expect(t, Registry_Uninstall(root, hello.id) != "")
}

@(test)
test_registry_install_refuses :: proc(t: ^testing.T) {
	root := reg_temp_dir(t, "refuse")
	defer os.remove_all(root)
	idx, _, _ := Registry_ParseIndex(FIX_INDEX, "", context.temp_allocator)
	extra, _ := json.parse(FIX_EXTRA, allocator = context.temp_allocator)
	sha :: proc(v: json.Value, k: string) -> string {return v.(json.Object)[k].(json.String)}

	// The hash isn't the index's: nothing installed.
	wrong, _ := reg_entry(idx, "wrong_hash_zz")
	err := Registry_Install(wrong, FIX_HELLO, root)
	testing.expect(t, strings.contains(err, "SHA-256"))
	wd, _ := filepath.join({root, wrong.id}, context.temp_allocator)
	testing.expect(t, !os.exists(wd))

	// A zip writing outside its folder.
	evil := Registry_Entry{id = "evil_zz", kind = .Plugin, version = "1", sha256 = sha(extra, "evil_zz.zip")}
	err = Registry_Install(evil, FIX_EVIL, root)
	testing.expectf(t, strings.contains(err, "outside"), "evil: %q", err)
	escaped, _ := filepath.join({filepath.dir(root, context.temp_allocator), "escaped_zz.txt"}, context.temp_allocator)
	testing.expect(t, !os.exists(escaped))
	ed, _ := filepath.join({root, "evil_zz"}, context.temp_allocator)
	testing.expect(t, !os.exists(ed))

	// plugin.json asks for a permission the index doesn't list.
	sneaky := Registry_Entry{id = "sneaky_zz", kind = .Plugin, version = "1", sha256 = sha(extra, "sneaky_zz.zip")}
	err = Registry_Install(sneaky, FIX_SNEAKY, root)
	testing.expectf(t, strings.contains(err, "network"), "sneaky: %q", err)
	sneaky.permissions = {"network"}
	testing.expect_value(t, Registry_Install(sneaky, FIX_SNEAKY, root), "")

	// A template zip as a plugin: no plugin.json.
	blank, _ := reg_entry(idx, "registry_blank_zz")
	asPlugin := blank
	asPlugin.kind = .Plugin
	err = Registry_Install(asPlugin, FIX_BLANK, root)
	testing.expect(t, strings.contains(err, "plugin.json"))

	// A folder made by hand is never replaced or removed.
	mine, _ := filepath.join({root, "registry_hello_zz"}, context.temp_allocator)
	testing.expect(t, os.make_directory_all(mine) == nil)
	hello, _ := reg_entry(idx, "registry_hello_zz")
	err = Registry_Install(hello, FIX_HELLO, root)
	testing.expect(t, strings.contains(err, "wasn't installed from the registry"))
	testing.expect(t, strings.contains(Registry_Uninstall(root, "registry_hello_zz"), "wasn't installed"))
	testing.expect(t, os.is_dir(mine))
}

@(test)
test_registry_install_template :: proc(t: ^testing.T) {
	root := reg_temp_dir(t, "templates")
	defer os.remove_all(root)
	idx, _, _ := Registry_ParseIndex(FIX_INDEX, "", context.temp_allocator)
	blank, _ := reg_entry(idx, "registry_blank_zz")
	err := Registry_Install(blank, FIX_BLANK, root)
	testing.expectf(t, err == "", "install: %s", err)
	for rel in ([]string{"template.json", "project.json", "preview.png", "scenes/main.scene.json"}) {
		p, _ := filepath.join({root, blank.id, rel}, context.temp_allocator)
		testing.expectf(t, os.is_file(p), "missing %s", rel)
	}
}
