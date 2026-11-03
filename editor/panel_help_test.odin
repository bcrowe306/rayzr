package editor

import "core:fmt"
import "core:strings"
import "core:testing"

// Every panel's F1 page (panel_help.odin) and every bottom tab's Help page
// exists in docs/editor, and each page is listed in the editor manual's
// index (docs/site.json's Editor section).
@(test)
panel_help_pages_exist :: proc(t: ^testing.T) {
	index := NodeReference_Markdown(EDITOR_INDEX, context.temp_allocator)
	check :: proc(t: ^testing.T, index, page: string) {
		testing.expectf(t, NodeReference_HasEditorPage(page), "no docs/editor/%s.md", page)
		testing.expectf(t, strings.contains(index, fmt.tprintf("(%s.md)", page)), "docs/editor/%s.md is not in docs/site.json's Editor section", page)
	}
	for p in PANEL_HELP_PAGES do check(t, index, p.page)
	for tab in BOTTOM_TABS do check(t, index, fmt.tprintf("tab-%s", tab.id))
}
