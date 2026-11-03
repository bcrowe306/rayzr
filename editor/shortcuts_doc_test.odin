package editor

import "core:strings"
import "core:testing"

// docs/editor/keyboard-shortcuts.md lists every action with its default
// shortcuts (shortcuts_doc.odin): regenerate it with
// `bin/editor --dump-shortcuts docs/editor/keyboard-shortcuts.md`.
@(test)
shortcuts_page_in_step :: proc(t: ^testing.T) {
	page := NodeReference_Markdown("editor/keyboard-shortcuts", context.temp_allocator)
	body, ok := ShortcutsDoc_Current(page)
	testing.expect(t, ok, "docs/editor/keyboard-shortcuts.md has no shortcuts:begin / shortcuts:end markers")
	want := strings.trim_space(ShortcutsDoc_Markdown(context.temp_allocator))
	testing.expect(t, body == want, "docs/editor/keyboard-shortcuts.md is out of date: run `bin/editor --dump-shortcuts docs/editor/keyboard-shortcuts.md`")
}
