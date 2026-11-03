package engine

import "core:strings"
import "core:testing"

// #268: the project's swatches round-trip through project.json.
@(test)
test_project_palette :: proc(t: ^testing.T) {
	cfg, ok := Project_ParseConfig(transmute([]u8)string(`{"name": "P", "palette": ["#ff000080", "#00ff00", "not a colour"]}`), context.temp_allocator)
	testing.expect(t, ok, "parsed")
	testing.expect(t, len(cfg.palette) == 2 && cfg.palette[0] == {255, 0, 0, 128} && cfg.palette[1] == {0, 255, 0, 255}, "two colours (the bad one skipped)")
	text := Project_SerializeToJSON(&cfg, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"palette": ["#ff000080", "#00ff00ff"]`), "written")
	again, _ := Project_ParseConfig(transmute([]u8)text, context.temp_allocator)
	testing.expect(t, len(again.palette) == 2 && again.palette[0] == cfg.palette[0], "read back")
	none, _ := Project_ParseConfig(transmute([]u8)string(`{"name": "P"}`), context.temp_allocator)
	testing.expect(t, !strings.contains(Project_SerializeToJSON(&none, context.temp_allocator), "palette"), "no palette: no key")
}
