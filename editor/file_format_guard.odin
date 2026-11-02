package editor

import "core:fmt"
import "core:path/filepath"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Files from a newer Rayzr (#326, engine/file_format.odin): opened read-only.
// Every editor write of a versioned project file asks Editor_FormatBlocksSave
// first; the file on disk decides, so it covers files that aren't open
// (Apply Override, re-saving users of a custom node type, moving assets).
// ============================================================================

// Editor_FormatBlocksSave: true (and logged) when `rel` - project-relative -
// is a versioned file saved by a newer Rayzr, which this one won't save over.
Editor_FormatBlocksSave :: proc(state: ^EditorState, rel: string) -> bool {
	kind, ok := e.Format_KindOfPath(rel)
	if !ok do return false
	full := rel
	if !filepath.is_abs(rel) do full, _ = filepath.join({state.projectPath, rel}, context.temp_allocator)
	if !e.Format_FileIsNewer(kind, full) do return false
	Editor_Log(state, .Error, "%s was saved by a newer version of Rayzr: not saved over it (Save As writes a copy)", rel)
	return true
}

// Editor_FormatNewerBanner: the read-only notice over the Scene panel when
// the open scene / component came from a newer Rayzr.
Editor_FormatNewerBanner :: proc(state: ^EditorState) {
	if state.activeScene == nil || !state.activeScene.formatNewer do return
	UI_BeginBanner()
	imgui.PushStyleColorImVec4(.Text, UI_WARNING)
	imgui.TextUnformatted(fmt.ctprintf("%s  Saved by a newer Rayzr: read-only", ICON_FA_LOCK))
	imgui.PopStyleColor()
	Drive_Item("scene.format_newer")
	imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
	imgui.TextWrapped("This version shows what it understands; saving over the file would lose what the newer version added. Open it there to edit it, or use Save As for a copy.")
	imgui.PopStyleColor()
	UI_EndBanner({UI_WARNING.x, UI_WARNING.y, UI_WARNING.z, 0.12})
}
