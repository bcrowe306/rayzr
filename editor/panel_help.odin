package editor

import "core:fmt"
import imgui "lib/imgui"

// ============================================================================
// Panel help (#45): F1 opens the editor manual's page for the panel with
// focus - docs/editor/<page>.md in the Node Reference window - and Help >
// Help for <panel> the page of the last panel used. Each panel calls
// PanelHelp_Mark(page) right after its imgui.Begin; the bottom panel marks
// its selected tab's page (tab-<id>).
//
// The Code tab keeps F1 for the Scripting Reference of the symbol at the
// caret, and the Level tab for its Level Editor Reference (both are their own
// help); while no panel has focus, F1 is the command palette.
// ============================================================================

// PANEL_HELP_PAGES: every page a panel marks (the bottom tabs' are tab-<id>,
// BOTTOM_TABS). panel_help_test.odin checks each exists.
PANEL_HELP_PAGES := [?]struct {
	page:  string,
	title: string,
}{
	{"scene-tree", "Scene"},
	{"inspector", "Inspector"},
	{"viewport", "Viewport"},
	{"vector-edit", "Vector Edit Mode"},
	{"assets", "Assets"},
	{"code", "Code Tab"},
	{"level", "Level Tab"},
	{"level-generator", "Level Generator"},
	{"terrain-tiles", "Terrain Tiles"},
	{"tile-animation", "Tile Animation"},
	{"sprite-slicer", "Sprite Sheet Slicer"},
	{"atlas-region", "Atlas Region Editor"},
	{"normal-map", "Generate Normal Map"},
	{"toolbar-menus", "Toolbar and Menus"},
}

@(private = "file")
panelHelp: struct {
	page:  [64]u8, // the focused panel's page (this frame or the last)
	n:     int,
	frame: i32,
	last:  [64]u8, // the last panel that had focus
	lastN: int,
}

// PanelHelp_Mark: the current window (just begun) shows `page` on F1 while
// it, or a child of it, has focus.
PanelHelp_Mark :: proc(page: string) {
	if !imgui.IsWindowFocused(imgui.FocusedFlags_RootAndChildWindows) do return
	panelHelp.n = copy(panelHelp.page[:], page)
	panelHelp.lastN = copy(panelHelp.last[:], page)
	panelHelp.frame = imgui.GetFrameCount()
}

// PanelHelp_Page: the focused panel's page ("" = none has focus). Marks are
// a frame old when the shortcuts run (before the panels draw).
PanelHelp_Page :: proc() -> string {
	if imgui.GetFrameCount() - panelHelp.frame > 1 do return ""
	return string(panelHelp.page[:panelHelp.n])
}

// PanelHelp_Last: the page of the last panel that had focus ("" = none yet).
PanelHelp_Last :: proc() -> string {return string(panelHelp.last[:panelHelp.lastN])}

// PanelHelp_Title: a page's panel name, for the Help menu.
PanelHelp_Title :: proc(page: string) -> string {
	for p in PANEL_HELP_PAGES do if p.page == page do return p.title
	for t in BOTTOM_TABS do if fmt.tprintf("tab-%s", t.id) == page do return fmt.tprintf("%s Tab", t.name)
	return page
}

// PanelHelp_Open: F1 - the focused panel's page (the last one's from the menu).
PanelHelp_Open :: proc(state: ^EditorState) {
	page := PanelHelp_Page()
	if page == "" do page = PanelHelp_Last()
	if page == "" do return
	NodeReference_OpenEditor(page)
}

// PanelHelp_MenuItem: Help > Help for <the last panel used>.
PanelHelp_MenuItem :: proc(state: ^EditorState) {
	page := PanelHelp_Last()
	label := "Help for This Panel" if page == "" else fmt.tprintf("Help for %s", PanelHelp_Title(page))
	sc := ""
	if a := Action_Find("help.panel"); a != nil do sc = Action_ShortcutText(a)
	if imgui.MenuItem(fmt.ctprintf("%s", label), fmt.ctprintf("%s", sc), false, page != "") do NodeReference_OpenEditor(page)
	Drive_Item("menu:Help/Help for This Panel")
}
