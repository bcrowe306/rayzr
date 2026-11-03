package editor

import "core:fmt"
import "core:os"
import "core:strings"

// ============================================================================
// The Keyboard Shortcuts page's list (#45): docs/editor/keyboard-shortcuts.md
// lists every action of the table (actions.odin) with its default shortcuts,
// between the markers below. `editor --dump-shortcuts <page.md>` rewrites
// that part; shortcuts_doc_test.odin fails when it is out of date, so the
// page can't fall behind the bindings. Shortcuts use the macOS names (the
// page says Cmd is Ctrl elsewhere).
// ============================================================================

SHORTCUTS_DOC_BEGIN :: "<!-- shortcuts:begin - generated from editor/actions.odin by `bin/editor --dump-shortcuts docs/editor/keyboard-shortcuts.md`; don't edit by hand -->"
SHORTCUTS_DOC_END :: "<!-- shortcuts:end -->"

// ShortcutsDoc_Markdown: a table per category, in the table's order.
ShortcutsDoc_Markdown :: proc(allocator := context.allocator) -> string {
	Actions_Init()
	sb := strings.builder_make(allocator)
	cats := make([dynamic]string, context.temp_allocator)
	for a in GlobalActions {
		if a.plugin != nil do continue
		seen := false
		for c in cats do if c == a.category do seen = true
		if !seen do append(&cats, a.category)
	}
	for cat, i in cats {
		if i > 0 do strings.write_string(&sb, "\n")
		fmt.sbprintf(&sb, "### %s\n\n| Command | Shortcut | Where |\n|---|---|---|\n", cat)
		for &a in GlobalActions {
			if a.plugin != nil || a.category != cat do continue
			keys := make([dynamic]string, context.temp_allocator)
			for c in a.chords {
				if c.key == .None do continue
				if c.mods == EXPAND_MODS && (a.id == "code.expand_selection" || a.id == "code.shrink_selection") {
					// (The one binding that differs by platform: the same text everywhere.)
					arrow := "Right" if c.key == .RightArrow else "Left"
					append(&keys, fmt.tprintf("`Ctrl+Shift+%s` (Windows, Linux: `Alt+Shift+%s`)", arrow, arrow))
					continue
				}
				append(&keys, fmt.tprintf("`%s`", Chord_Text(c, mac = true)))
			}
			where_ := "Anywhere"
			switch a.scope {
			case .Global:
			case .Scene: where_ = "Scene editing"
			case .Code:  where_ = "Code tab"
			}
			label, _ := strings.replace_all(a.label, "|", "\\|", context.temp_allocator)
			fmt.sbprintf(&sb, "| %s | %s | %s |\n", label, strings.join(keys[:], ", ", context.temp_allocator) if len(keys) > 0 else "", where_)
		}
	}
	return strings.to_string(sb)
}

// ShortcutsDoc_Current: the page's generated part (between the markers).
ShortcutsDoc_Current :: proc(page: string) -> (body: string, ok: bool) {
	b := strings.index(page, SHORTCUTS_DOC_BEGIN)
	en := strings.index(page, SHORTCUTS_DOC_END)
	if b < 0 || en < b do return "", false
	return strings.trim_space(page[b + len(SHORTCUTS_DOC_BEGIN):en]), true
}

// ShortcutsDoc_Run: --dump-shortcuts <page.md> - rewrite the page's list.
ShortcutsDoc_Run :: proc(path: string) -> int {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fmt.eprintfln("Could not read %s", path)
		return 1
	}
	page := string(data)
	b := strings.index(page, SHORTCUTS_DOC_BEGIN)
	en := strings.index(page, SHORTCUTS_DOC_END)
	if b < 0 || en < b {
		fmt.eprintfln("%s has no %s ... %s markers", path, SHORTCUTS_DOC_BEGIN, SHORTCUTS_DOC_END)
		return 1
	}
	out := strings.concatenate({page[:b + len(SHORTCUTS_DOC_BEGIN)], "\n\n", ShortcutsDoc_Markdown(context.temp_allocator), "\n", page[en:]})
	if os.write_entire_file(path, transmute([]u8)out) != nil {
		fmt.eprintfln("Could not write %s", path)
		return 1
	}
	fmt.printfln("Wrote %s", path)
	return 0
}
