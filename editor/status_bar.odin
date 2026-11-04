package editor

import "core:fmt"
import "core:path/filepath"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Status bar: scene + save state, selection, game state; cursor/zoom/FPS.
// ============================================================================

StatusBar_Render :: proc(state: ^EditorState, width, displayH, barHeight: f32) {
	imgui.SetNextWindowPos({0, displayH - barHeight})
	imgui.SetNextWindowSize({width, barHeight})
	flags: imgui.WindowFlags = {.NoTitleBar, .NoResize, .NoMove, .NoScrollbar, .NoSavedSettings, .NoDocking, .NoScrollWithMouse}
	imgui.PushStyleVarImVec2(.WindowPadding, {12, (barHeight - imgui.GetTextLineHeight()) * 0.5})
	imgui.PushStyleVarImVec2(.ItemSpacing, {14, 0})
	imgui.PushStyleColorImVec4(.WindowBg, UI_BG_APP)
	defer {
		imgui.PopStyleColor()
		imgui.PopStyleVar(2)
	}
	defer imgui.End()
	if !imgui.Begin("StatusBar###FixedStatusBarWindow", nil, flags) do return
	Drive_Window("statusbar") // (annotated docs screenshots)
	imgui.PushFont(GlobalFonts.small)
	defer imgui.PopFont()

	modified := Editor_ModifiedSceneCountCached(state)
	scene := Asset_DisplayName(state.activeScenePath) if state.activeScenePath != "" else "no scene"
	if modified > 0 {
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextUnformatted(fmt.ctprintf("%s  %s - %d unsaved", ICON_FA_CLAPPERBOARD, scene, modified))
		imgui.PopStyleColor()
	} else {
		UI_DimText(fmt.tprintf("%s  %s - saved", ICON_FA_CLAPPERBOARD, scene))
	}
	imgui.SameLine()
	if node := state.selectedNode; node != nil {
		UI_DimText(fmt.tprintf("%s  %s  ·  %s  ·  (%.0f, %.0f)", Editor_NodeIcon(node), node.name, e.Node_TypeName(node), node.position.x, node.position.y))
	}
	imgui.SameLine()
	switch {
	case state.buildRunning:
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextUnformatted(fmt.ctprintf("%s  Building game...", ICON_FA_HAMMER))
		imgui.PopStyleColor()
	case state.gameProcessRunning && (RemoteGame_Paused() || Debug_IsStopped()):
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextUnformatted(fmt.ctprintf("%s  Game paused%s (PID %d)", ICON_FA_PAUSE, " at a breakpoint" if Debug_IsStopped() else "", state.gameProcess.pid))
		imgui.PopStyleColor()
	case state.gameProcessRunning:
		imgui.PushStyleColorImVec4(.Text, UI_SUCCESS)
		imgui.TextUnformatted(fmt.ctprintf("%s  Game running (PID %d)", ICON_FA_PLAY, state.gameProcess.pid))
		imgui.PopStyleColor()
	case state.isSimulating:
		imgui.PushStyleColorImVec4(.Text, UI_ACCENT)
		imgui.TextUnformatted(fmt.ctprintf("%s  Simulating in editor", ICON_FA_PLAY))
		imgui.PopStyleColor()
	}

	UpdateCheck_StatusBar(state)
	Bundletool_StatusBar(state)

	io := imgui.GetIO()
	world := Viewport_ScreenToWorld(state, {io.MousePos.x, io.MousePos.y})
	right := fmt.tprintf("%.0f, %.0f     %d%%     %d FPS", world.x, world.y, int(state.cameraZoom * 100 + 0.5), rl.GetFPS())
	tw := imgui.CalcTextSize(fmt.ctprintf("%s", right)).x
	imgui.SameLine(width - tw - 14)
	UI_DimText(right)
}
