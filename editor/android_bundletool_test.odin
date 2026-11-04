package editor

import os "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

// #330: the downloaded bundletool - the checksum check, the tools folder,
// a cached jar reused and a damaged one thrown away (no network).
@(test)
test_bundletool_cache_330 :: proc(t: ^testing.T) {
	// SHA-256("abc") (FIPS 180-2's example).
	ABC :: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
	testing.expect(t, Bundletool_Verify(transmute([]u8)string("abc"), ABC))
	testing.expect(t, Bundletool_Verify(transmute([]u8)string("abc"), strings.to_upper(ABC, context.temp_allocator)))
	testing.expect(t, !Bundletool_Verify(transmute([]u8)string("abd"), ABC))
	testing.expect(t, !Bundletool_Verify(transmute([]u8)string("abc"), BUNDLETOOL_SHA256))
	testing.expect(t, !Bundletool_Verify(transmute([]u8)string("abc"), ""))

	// The tools folder follows --user-data.
	testing.expect_value(t, Bundletool_ToolsDir("/x/userdata"), "/x/userdata/tools")
	testing.expect(t, strings.has_suffix(Bundletool_ToolsDir(""), "rayzr_editor/tools"))
	testing.expect(t, strings.contains(BUNDLETOOL_URL, BUNDLETOOL_VERSION) && strings.has_suffix(BUNDLETOOL_URL, BUNDLETOOL_JAR))

	tmp := os.get_env("TMPDIR", context.temp_allocator)
	if tmp == "" do tmp = "/tmp"
	dir, _ := filepath.join({tmp, "rayzr_bundletool_test_330"}, context.temp_allocator)
	_ = os.make_directory_all(dir)
	jar, _ := filepath.join({dir, BUNDLETOOL_JAR}, context.temp_allocator)
	_ = os.remove(jar)
	testing.expect_value(t, Bundletool_Cached(dir, ABC), "") // nothing yet: download

	// A cached jar with the expected checksum is reused (and kept).
	_ = os.write_entire_file(jar, transmute([]u8)string("abc"))
	testing.expect_value(t, Bundletool_Cached(dir, ABC), jar)
	testing.expect_value(t, Bundletool_Cached(dir, ABC), jar)
	// The wrong checksum: rejected and removed (the next export downloads it).
	testing.expect_value(t, Bundletool_Cached(dir), "")
	testing.expect(t, !os.is_file(jar))
	testing.expect_value(t, Bundletool_Cached("", ABC), "")

	_ = os.remove(dir)
	free_all(context.temp_allocator)
}
