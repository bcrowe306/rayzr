package engine

import "core:fmt"
import "core:strings"
import "core:testing"

// Every hand-written function in engine_api.lua has a description and an
// "Example:" line above it - the editor's hover and completion docs (the
// generated regions are checked by their own tests).
@(test)
test_lua_api_documented :: proc(t: ^testing.T) {
	lines := strings.split_lines(ENGINE_API_LUA, context.temp_allocator)
	generated := false
	missing := make([dynamic]string, context.temp_allocator)
	count := 0
	for l, i in lines {
		if strings.has_prefix(l, "-- ") && strings.contains(l, " begin (generated") {generated = true; continue}
		if generated && strings.has_prefix(l, "-- ") && strings.has_suffix(l, " end") {generated = false; continue}
		if generated || !strings.has_prefix(l, "function ") do continue
		count += 1
		hasDesc, hasExample, deprecated := false, false, false
		for j := i - 1; j >= 0 && strings.has_prefix(lines[j], "---"); j -= 1 {
			d := lines[j][3:]
			if strings.has_prefix(d, "@deprecated") do deprecated = true // (an old name: it points at the new one, #327)
			if strings.has_prefix(d, "@") || strings.trim_space(d) == "" do continue
			if strings.has_prefix(d, "Example:") do hasExample = true
			else do hasDesc = true
		}
		if deprecated do continue
		if !hasDesc || !hasExample do append(&missing, fmt.tprintf("%s%s%s", l, "" if hasDesc else "  (no description)", "" if hasExample else "  (no example)"))
	}
	for m in missing do fmt.println(m)
	testing.expectf(t, len(missing) == 0, "%d of %d API functions lack a description or an example", len(missing), count)
	testing.expect(t, count > 300, "found the API functions")
}
