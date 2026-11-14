package editor

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"
import imgui_rl "lib/imgui/imgui_impl_raylib"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// Play in Viewport: the Game view, a tab beside the scene tabs that shows
// the running game (Opt+F5 the project, Opt+F6 the current scene).
//
// The game is the same process Play starts (with every Play tool: the Game
// tab, breakpoints, Pause / Step, Remote), launched with --embed: its window
// stays hidden and its frames come here through a shared block
// (engine/embed.odin). Clicking the game hands it the keyboard and mouse
// ("in" lines over the editor link); Shift+Esc or clicking another panel
// takes them back. While the game has them, the editor's shortcuts are off
// but Play / Stop / Pause / Step and the debugger's (Actions_Dispatch).
// ============================================================================

GAME_VIEW_WINDOW :: "Game View###GameViewWindow"

Game_View_Size :: enum {
	Fit, // the panel's size: the game sees a window that size
	Project, // the project's window size
	Phone_Portrait,
	Phone_Landscape,
	Tablet,
	HD720,
	HD1080,
	Custom,
}

GAME_VIEW_SIZE_NAMES := [Game_View_Size]string {
	.Fit             = "fit",
	.Project         = "project",
	.Phone_Portrait  = "phone_portrait",
	.Phone_Landscape = "phone_landscape",
	.Tablet          = "tablet",
	.HD720           = "720p",
	.HD1080          = "1080p",
	.Custom          = "custom",
}

GAME_VIEW_SIZE_LABELS := [Game_View_Size]string {
	.Fit             = "Fit to Panel",
	.Project         = "Project Resolution",
	.Phone_Portrait  = "Phone Portrait (390 x 844)",
	.Phone_Landscape = "Phone Landscape (844 x 390)",
	.Tablet          = "Tablet (1024 x 768)",
	.HD720           = "720p (1280 x 720)",
	.HD1080          = "1080p (1920 x 1080)",
	.Custom          = "Custom",
}

GAME_VIEW_PRESETS := #partial [Game_View_Size][2]i32 {
	.Phone_Portrait  = {390, 844},
	.Phone_Landscape = {844, 390},
	.Tablet          = {1024, 768},
	.HD720           = {1280, 720},
	.HD1080          = {1920, 1080},
}

// Game_View_Zoom: how a fixed size (not Fit) is shown in the panel.
Game_View_Zoom :: enum {
	Fit, // scaled to fit, letterboxed
	X1,  // 100%
	X2,  // 200%
}

GAME_VIEW_ZOOM_NAMES := [Game_View_Zoom]string {
	.Fit = "fit",
	.X1  = "100",
	.X2  = "200",
}

GAME_VIEW_ZOOM_LABELS := [Game_View_Zoom]string {
	.Fit = "Fit",
	.X1  = "100%",
	.X2  = "200%",
}

// Game_View_Settings: kept in the editor settings ([game_view]).
Game_View_Settings :: struct {
	size:           Game_View_Size,
	zoom:           Game_View_Zoom,
	customW:        i32,
	customH:        i32,
	stats:          bool, // the stats overlay
	pauseUnfocused: bool, // pause the game when it loses the input
	mute:           bool,
}

Game_View_Stats :: struct {
	have:  bool,
	fps:   f64,
	ms:    f64,
	nodes: int,
	w, h:  int,
}

Game_View :: struct {
	open:         bool, // the tab is shown
	focusRequest: bool,
	active:       bool, // the running game plays here (the block is open)
	shm:          e.Shared_Memory,
	shmCount:     int,
	tex:          rl.Texture2D,
	lastSeq:      u64,
	frames:       int, // frames shown since the game started
	sentSize:     [2]i32, // the window size the game was last asked for
	sizeAskedAt:  f64,
	panel:        [2]f32, // the image area (points), last frame
	rect:         [4]f32, // where the frame is drawn (x, y, w, h)
	captured:     bool, // the game has the keyboard and mouse
	autoPaused:   bool, // paused because it lost them (Pause When Unfocused)
	windowFocused: bool,
	mouseSent:    [2]f32,
	btnSent:      [3]bool,
	stats:        Game_View_Stats,
	contentTop:   f32, // the window's first content row (below its tab)
}

GAME_VIEW_BAR_H :: 38 // the toolbar's height

gameView: Game_View

// GameView_Captured: the game has the keyboard and mouse.
GameView_Captured :: proc() -> bool {return gameView.captured}

// GameView_Active: the running game plays in the Game view.
GameView_Active :: proc() -> bool {return gameView.active}

// GameView_Open shows the tab (and brings it to the front).
GameView_Open :: proc() {
	gameView.open = true
	gameView.focusRequest = true
}

// GameView_WantedSize: the window size the game should have (points).
GameView_WantedSize :: proc(state: ^EditorState) -> [2]i32 {
	g := &GlobalSettings.gameView
	out: [2]i32
	switch g.size {
	case .Fit:
		p := gameView.panel
		if p.x < 16 || p.y < 16 do p = state.viewportSize // (not drawn yet: the viewport's)
		if p.x < 16 || p.y < 16 do p = {1280, 720}
		out = {i32(p.x), i32(p.y)}
	case .Project:
		out = {i32(state.projectConfig.windowWidth), i32(state.projectConfig.windowHeight)}
		if out.x <= 0 || out.y <= 0 do out = {1280, 720}
	case .Custom:
		out = {g.customW, g.customH}
	case .Phone_Portrait, .Phone_Landscape, .Tablet, .HD720, .HD1080:
		out = GAME_VIEW_PRESETS[g.size]
	}
	return e.Embed_ClampSize(out)
}

// GameView_LaunchArgs makes the block for a game about to start and
// returns its command-line options (nil: couldn't - the game plays in its
// own window).
GameView_LaunchArgs :: proc(state: ^EditorState) -> []string {
	GameView_Ended()
	gameView.shmCount += 1
	name := e.Shm_Name(os.get_pid(), gameView.shmCount, context.temp_allocator)
	shm, ok := e.Shm_Create(name, e.EMBED_BYTES)
	if !ok {
		Editor_Log(state, .Error, "Play in Viewport: couldn't make the shared frame buffer; playing in a window")
		return nil
	}
	e.Embed_InitBlock(&shm)
	gameView.shm = shm
	gameView.active = true
	gameView.lastSeq = 0
	gameView.frames = 0
	gameView.stats = {}
	gameView.sentSize = GameView_WantedSize(state)
	gameView.sizeAskedAt = rl.GetTime()
	GameView_Open()
	args := make([]string, 4, context.temp_allocator)
	args[0], args[1] = "--embed", strings.clone(name, context.temp_allocator)
	args[2], args[3] = "--embed-size", fmt.tprintf("%dx%d", gameView.sentSize.x, gameView.sentSize.y)
	return args
}

// GameView_Started: the game is running (its link attached).
GameView_Started :: proc() {
	if gameView.active && GlobalSettings.gameView.mute do RemoteGame_Send("embed-mute 1")
}

// GameView_Ended: the game stopped (or didn't start).
GameView_Ended :: proc() {
	if gameView.shm.data != nil do e.Shm_Close(&gameView.shm)
	gameView.active = false
	gameView.captured = false
	gameView.autoPaused = false
	gameView.btnSent = {}
	gameView.stats = {}
	if gameView.tex.id != 0 {
		rl.UnloadTexture(gameView.tex)
		gameView.tex = {}
	}
}

// GameView_HandleStats reads an @rayzr:stats line.
GameView_HandleStats :: proc(text: string) {
	v, err := json.parse_string(text, allocator = context.temp_allocator)
	if err != nil do return
	o, ok := v.(json.Object)
	if !ok do return
	num :: proc(o: json.Object, k: string) -> f64 {
		if x, ok := o[k].(json.Float); ok do return f64(x)
		if x, ok := o[k].(json.Integer); ok do return f64(x)
		return 0
	}
	gameView.stats = {true, num(o, "fps"), num(o, "ms"), int(num(o, "nodes")), int(num(o, "w")), int(num(o, "h"))}
}

// GameView_Render draws the tab (every frame; nothing while it's closed).
GameView_Render :: proc(state: ^EditorState) {
	if gameView.active do gameview_pull_frame()
	if !gameView.open {
		if gameView.captured do gameview_release(state)
		return
	}
	if gameView.focusRequest {
		imgui.SetWindowFocusStr(GAME_VIEW_WINDOW)
		gameView.focusRequest = false
	}
	if state.viewportDockId != 0 do imgui.SetNextWindowDockID(state.viewportDockId, .FirstUseEver)
	imgui.PushStyleVarImVec2(.WindowPadding, {0, 0})
	// (No close button while a game plays in it.)
	visible := imgui.Begin(GAME_VIEW_WINDOW, nil if gameView.active else &gameView.open, {.NoScrollbar, .NoScrollWithMouse})
	imgui.PopStyleVar()
	gameView.windowFocused = imgui.IsWindowFocused(imgui.FocusedFlags_RootAndChildWindows)
	PanelHelp_Mark("game-view")
	Dock_Remember(.Center)
	hovered := false
	if visible {
		Drive_Window("game-view")
		gameview_toolbar(state)
		hovered = gameview_image(state)
	}
	imgui.End()
	gameview_input(state, visible, hovered)
	if gameView.active do gameview_send_size(state)
}

// gameview_pull_frame uploads the game's newest frame.
@(private = "file")
gameview_pull_frame :: proc() {
	if gameView.shm.data == nil do return
	px, w, h, seq, ok := e.Embed_ReadLatest(&gameView.shm, gameView.lastSeq)
	if !ok do return
	if gameView.tex.id == 0 || gameView.tex.width != w || gameView.tex.height != h {
		if gameView.tex.id != 0 do rl.UnloadTexture(gameView.tex)
		id := rlgl.LoadTexture(nil, w, h, i32(rl.PixelFormat.UNCOMPRESSED_R8G8B8A8), 1)
		gameView.tex = {id = id, width = w, height = h, mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
	}
	rl.UpdateTexture(gameView.tex, px)
	// (Rewritten while it was read: the next one shows instead.)
	if e.Embed_StillValid(&gameView.shm, seq) {
		gameView.lastSeq = seq
		gameView.frames += 1
	}
}

@(private = "file")
gameview_toolbar :: proc(state: ^EditorState) {
	g := &GlobalSettings.gameView
	imgui.PushStyleVarImVec2(.FramePadding, {6, 4})
	defer imgui.PopStyleVar()
	top := imgui.GetCursorPos() // (under the tab bar when docked)
	gameView.contentTop = top.y
	imgui.SetCursorPos({top.x + 8, top.y + 6})
	changed := false
	imgui.SetNextItemWidth(200)
	if imgui.BeginCombo("##gv-size", strings.clone_to_cstring(GAME_VIEW_SIZE_LABELS[g.size], context.temp_allocator)) {
		for s in Game_View_Size {
			label := GAME_VIEW_SIZE_LABELS[s]
			if s == .Project do label = fmt.tprintf("Project Resolution (%d x %d)", state.projectConfig.windowWidth, state.projectConfig.windowHeight)
			if imgui.Selectable(strings.clone_to_cstring(label, context.temp_allocator), g.size == s) {
				g.size = s
				changed = true
			}
			Drive_Item(fmt.tprintf("gv-size:%s", GAME_VIEW_SIZE_NAMES[s]))
		}
		imgui.EndCombo()
	}
	Drive_Item("gv-size")
	UI_Tooltip("The game's window size. Fit to Panel: the game sees a window the panel's size (its stretch settings apply as you resize). The others: that size, shown at the zoom beside")
	if g.size == .Custom {
		w, h := g.customW, g.customH
		imgui.SameLine()
		imgui.SetNextItemWidth(64)
		if imgui.InputInt("##gv-w", &w, 0, 0) do g.customW = clamp(w, 16, e.EMBED_MAX_W)
		if imgui.IsItemDeactivatedAfterEdit() do changed = true
		Drive_Item("gv-w")
		imgui.SameLine()
		imgui.TextUnformatted("x")
		imgui.SameLine()
		imgui.SetNextItemWidth(64)
		if imgui.InputInt("##gv-h", &h, 0, 0) do g.customH = clamp(h, 16, e.EMBED_MAX_H)
		if imgui.IsItemDeactivatedAfterEdit() do changed = true
		Drive_Item("gv-h")
	}
	if g.size != .Fit {
		imgui.SameLine()
		imgui.SetNextItemWidth(70)
		if imgui.BeginCombo("##gv-zoom", strings.clone_to_cstring(GAME_VIEW_ZOOM_LABELS[g.zoom], context.temp_allocator)) {
			for z in Game_View_Zoom {
				if imgui.Selectable(strings.clone_to_cstring(GAME_VIEW_ZOOM_LABELS[z], context.temp_allocator), g.zoom == z) {
					g.zoom = z
					changed = true
				}
				Drive_Item(fmt.tprintf("gv-zoom:%s", GAME_VIEW_ZOOM_NAMES[z]))
			}
			imgui.EndCombo()
		}
		Drive_Item("gv-zoom")
		UI_Tooltip("Zoom: Fit scales the game to the panel; 100% and 200% show it pixel for pixel (cut at the edges when it's bigger)")
	}

	// Status, then the toggles on the right.
	imgui.SameLine()
	status: string
	switch {
	case gameView.captured: status = ICON_FA_KEYBOARD + "  Playing - Shift+Esc gives the keyboard back"
	case gameView.active && gameView.frames > 0: status = "Click the game to play"
	case gameView.active: status = "Starting the game..."
	case: status = "Not running"
	}
	imgui.PushStyleColorImVec4(.Text, UI_ACCENT if gameView.captured else UI_TEXT_DIM)
	imgui.AlignTextToFramePadding()
	imgui.TextUnformatted(strings.clone_to_cstring(status, context.temp_allocator))
	imgui.PopStyleColor()

	btn :: 26
	right := imgui.GetWindowWidth() - 3 * (btn + 4) - 8
	imgui.SameLine(max(right, imgui.GetCursorPosX() + 8))
	if UI_IconButton(ICON_FA_GAUGE, "gv-stats", "Stats: the game's frame rate, frame time (update + draw), node count and window size", g.stats, btn) {
		g.stats = !g.stats
		changed = true
	}
	imgui.SameLine(0, 4)
	if UI_IconButton(ICON_FA_PAUSE, "gv-pause-unfocused", "Pause When Unfocused: the game pauses when it loses the keyboard (Shift+Esc, another panel, another app) and goes on when you click it again", g.pauseUnfocused, btn) {
		g.pauseUnfocused = !g.pauseUnfocused
		changed = true
	}
	imgui.SameLine(0, 4)
	if UI_IconButton(ICON_FA_VOLUME_XMARK if g.mute else ICON_FA_VOLUME_HIGH, "gv-mute", "Mute the game" if !g.mute else "Unmute the game", g.mute, btn) {
		g.mute = !g.mute
		changed = true
		if gameView.active && RemoteGame_Connected() do RemoteGame_Send("embed-mute 1" if g.mute else "embed-mute 0")
	}
	if changed do _ = Editor_SaveSettings()
}

// gameview_image draws the frame (or what to do); true while the mouse is
// over the game's picture.
@(private = "file")
gameview_image :: proc(state: ^EditorState) -> bool {
	g := &GlobalSettings.gameView
	imgui.SetCursorPos({0, gameView.contentTop + GAME_VIEW_BAR_H})
	origin := imgui.GetCursorScreenPos()
	avail := imgui.GetContentRegionAvail()
	avail = {max(avail.x, 16), max(avail.y, 16)}
	gameView.panel = {avail.x, avail.y}
	dl := imgui.GetWindowDrawList()
	imgui.DrawList_AddRectFilled(dl, origin, origin + avail, col_u32({0.05, 0.06, 0.08, 1}))
	imgui.InvisibleButton("##gameview", avail, {.MouseButtonLeft, .MouseButtonRight, .MouseButtonMiddle})
	Drive_Item("game-view")
	hovered := imgui.IsItemHovered()

	if !gameView.active || gameView.tex.id == 0 {
		gameView.rect = {}
		gameview_placeholder(state, origin, avail)
		return false
	}
	// The window's size in points (what the mouse maps to).
	win := [2]f32{f32(gameView.sentSize.x), f32(gameView.sentSize.y)}
	if gameView.stats.have && gameView.stats.w > 0 do win = {f32(gameView.stats.w), f32(gameView.stats.h)}
	size := avail
	if g.size != .Fit {
		scale: f32 = 1
		switch g.zoom {
		case .Fit: scale = min(avail.x / win.x, avail.y / win.y)
		case .X1:  scale = 1
		case .X2:  scale = 2
		}
		size = win * scale
	} else {
		size = win // (the panel's size, a frame behind while it changes)
	}
	pos := origin + (avail - size) * 0.5
	pos = {f32(i32(pos.x)), f32(i32(pos.y))}
	gameView.rect = {pos.x, pos.y, size.x, size.y}
	// Pixel for pixel or a whole zoom: sharp; else smooth.
	whole := size.x == f32(gameView.tex.width) || size.x == 2 * f32(gameView.tex.width)
	rl.SetTextureFilter(gameView.tex, .POINT if whole else .BILINEAR)
	imgui.DrawList_PushClipRect(dl, origin, origin + avail, true)
	imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)&gameView.tex, pos, pos + size, {0, 1}, {1, 0})
	if gameView.captured do imgui.DrawList_AddRect(dl, pos, pos + size, col_u32(UI_ACCENT), 0, {}, 1)
	if g.stats do gameview_stats_overlay(dl, pos)
	if RemoteGame_Paused() {
		label := cstring(ICON_FA_PAUSE + "  Paused")
		tw := imgui.CalcTextSize(label)
		at := imgui.Vec2{pos.x + size.x - tw.x - 14, pos.y + 8}
		imgui.DrawList_AddRectFilled(dl, at - {6, 3}, at + tw + {6, 3}, col_u32({0, 0, 0, 0.6}), 4)
		imgui.DrawList_AddText(dl, at, col_u32(UI_ACCENT), label)
	}
	imgui.DrawList_PopClipRect(dl)
	mp := imgui.GetIO().MousePos
	inside := mp.x >= pos.x && mp.y >= pos.y && mp.x < pos.x + size.x && mp.y < pos.y + size.y
	return hovered && inside
}

@(private = "file")
gameview_stats_overlay :: proc(dl: ^imgui.DrawList, pos: imgui.Vec2) {
	s := gameView.stats
	text := "Waiting for stats..."
	if s.have do text = fmt.tprintf("%.0f fps   %.2f ms   %d nodes   %d x %d", s.fps, s.ms, s.nodes, s.w, s.h)
	c := strings.clone_to_cstring(text, context.temp_allocator)
	tw := imgui.CalcTextSize(c)
	at := pos + {10, 8}
	imgui.DrawList_AddRectFilled(dl, at - {6, 3}, at + tw + {6, 3}, col_u32({0, 0, 0, 0.6}), 4)
	imgui.DrawList_AddText(dl, at, col_u32({0.85, 0.95, 0.85, 1}), c)
}

@(private = "file")
gameview_placeholder :: proc(state: ^EditorState, origin, avail: imgui.Vec2) {
	center := origin + avail * 0.5
	if gameView.active {
		msg := cstring("Starting the game...")
		w := imgui.CalcTextSize(msg).x
		imgui.DrawList_AddText(imgui.GetWindowDrawList(), {center.x - w * 0.5, center.y - 8}, col_u32(UI_TEXT_DIM), msg)
		return
	}
	msg := fmt.ctprintf("Play the game here, with the bottom panel beside it: %s or %s", Action_ShortcutText(Action_Find("game.play_view")), Action_ShortcutText(Action_Find("game.play_scene_view")))
	w := imgui.CalcTextSize(msg).x
	imgui.DrawList_AddText(imgui.GetWindowDrawList(), {center.x - w * 0.5, center.y - 40}, col_u32(UI_TEXT_DIM), msg)
	bw: f32 = 170
	imgui.SetCursorScreenPos({center.x - bw - 6, center.y - 10})
	enabled := !state.gameProcessRunning && !state.buildRunning
	if !enabled do imgui.BeginDisabled()
	if UI_PrimaryButton(ICON_FA_PLAY + "  Play Project", "gv-play", {bw, 30}) do Editor_PlayInView(state, .Project)
	imgui.SameLine(0, 12)
	if imgui.Button(ICON_FA_PLAY + "  Play Current Scene##gv-play-scene", {bw, 30}) do Editor_PlayInView(state, .CurrentScene)
	Drive_Item("gv-play-scene")
	if !enabled do imgui.EndDisabled()
}

// Editor_PlayInView plays in the Game view (Opt+F5 / Opt+F6).
Editor_PlayInView :: proc(state: ^EditorState, mode: Play_Mode) {
	if state.gameProcessRunning {
		Editor_StopGameProcess(state)
		return
	}
	state.pendingPlayInView = true
	Editor_PlayRequest(state, mode)
}

// gameview_send_size asks the game for a new window size (at most ten
// times a second while the panel is being resized).
@(private = "file")
gameview_send_size :: proc(state: ^EditorState) {
	if !RemoteGame_Connected() do return
	want := GameView_WantedSize(state)
	if want == gameView.sentSize do return
	now := rl.GetTime()
	if now - gameView.sizeAskedAt < 0.1 do return
	if RemoteGame_Send(fmt.tprintf("embed-size %d %d", want.x, want.y)) {
		gameView.sentSize = want
		gameView.sizeAskedAt = now
	}
}

// gameview_input: capture and release, and the input sent to the game.
@(private = "file")
gameview_input :: proc(state: ^EditorState, visible, hovered: bool) {
	io := imgui.GetIO()
	if !gameView.active || !RemoteGame_Connected() {
		if gameView.captured do gameview_release(state)
		return
	}
	if !gameView.captured {
		// A click on the game hands it the input (and is its first click).
		if visible && hovered && !Debug_IsStopped() && (imgui.IsMouseClicked(.Left) || imgui.IsMouseClicked(.Right) || imgui.IsMouseClicked(.Middle)) {
			gameview_capture(state)
		} else {
			return
		}
	} else {
		// Taken back: Shift+Esc, another panel (or app), the tab hidden.
		shiftEsc := imgui.IsKeyPressed(.Escape, false) && io.KeyShift
		appFocused := rl.IsWindowFocused() || imgui_rl.input_override // (drives: no real focus)
		if shiftEsc || !visible || !gameView.windowFocused || !appFocused || Debug_IsStopped() {
			gameview_release(state)
			return
		}
	}

	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "in")
	// Keys, as ImGui saw them (the raylib codes the game reads).
	for rk, ik in imgui_rl.raylib_key_map {
		if imgui.IsKeyPressed(ik, false) do fmt.sbprintf(&sb, " k%d+", int(rk))
		else if imgui.IsKeyPressed(ik, true) do fmt.sbprintf(&sb, " k%dr", int(rk))
		if imgui.IsKeyReleased(ik) do fmt.sbprintf(&sb, " k%d-", int(rk))
	}
	// Typed characters (this frame's).
	q := io.InputQueueCharacters
	for i in 0 ..< int(q.Size) {
		ch := ([^]imgui.Wchar)(q.Data)[i]
		if ch >= 32 do fmt.sbprintf(&sb, " c%d", int(ch))
	}
	// The mouse, in the game window's points.
	r := gameView.rect
	if r.z > 0 && r.w > 0 {
		win := [2]f32{f32(gameView.sentSize.x), f32(gameView.sentSize.y)}
		if gameView.stats.have && gameView.stats.w > 0 do win = {f32(gameView.stats.w), f32(gameView.stats.h)}
		mp := io.MousePos
		m := [2]f32{(mp.x - r.x) / r.z * win.x, (mp.y - r.y) / r.w * win.y}
		m = {f32(i32(m.x * 10)) / 10, f32(i32(m.y * 10)) / 10}
		if m != gameView.mouseSent && (hovered || gameView.btnSent != {}) {
			fmt.sbprintf(&sb, " m%.1f,%.1f", m.x, m.y)
			gameView.mouseSent = m
		}
	}
	// Buttons: presses over the game, releases anywhere.
	for b in 0 ..< 3 {
		down := io.MouseDown[b]
		if down && !gameView.btnSent[b] && hovered {
			fmt.sbprintf(&sb, " b%d+", b)
			gameView.btnSent[b] = true
		} else if !down && gameView.btnSent[b] {
			fmt.sbprintf(&sb, " b%d-", b)
			gameView.btnSent[b] = false
		}
	}
	if hovered && (io.MouseWheel != 0 || io.MouseWheelH != 0) do fmt.sbprintf(&sb, " w%.3f,%.3f", -io.MouseWheelH, io.MouseWheel)
	line := strings.to_string(sb)
	if line != "in" do RemoteGame_Send(line)
}

@(private = "file")
gameview_capture :: proc(state: ^EditorState) {
	gameView.captured = true
	gameView.mouseSent = {-1, -1}
	RemoteGame_Send("in f1")
	if gameView.autoPaused {
		gameView.autoPaused = false
		if RemoteGame_Paused() do RemoteGame_Send("resume")
	}
}

@(private = "file")
gameview_release :: proc(state: ^EditorState) {
	gameView.captured = false
	gameView.btnSent = {}
	if !gameView.active || !RemoteGame_Connected() do return
	RemoteGame_Send("in r f0") // (every key and button up)
	if GlobalSettings.gameView.pauseUnfocused && !RemoteGame_Paused() && !Debug_IsStopped() {
		RemoteGame_Send("pause")
		gameView.autoPaused = true
	}
}

// GameView_AllowsAction: while the game has the keyboard, only the play
// controls and the debugger's keys reach the editor.
GameView_AllowsAction :: proc(id: string) -> bool {
	if !gameView.captured do return true
	return strings.has_prefix(id, "game.") || strings.has_prefix(id, "debug.")
}

// GameView_Query: the drives' gameview* queries.
GameView_Query :: proc(q: string) -> (string, bool) {
	switch q {
	case "gameview":
		if !gameView.active do return "inactive", true
		return "showing" if gameView.frames > 0 else "starting", true
	case "gameview-captured": return "true" if gameView.captured else "false", true
	case "gameview-open": return "true" if gameView.open else "false", true
	case "gameview-frames": return fmt.tprint(gameView.frames), true
	case "gameview-size": // the game's window, as it reported it
		if !gameView.stats.have do return "", true
		return fmt.tprintf("%dx%d", gameView.stats.w, gameView.stats.h), true
	case "gameview-tex": return fmt.tprintf("%dx%d", gameView.tex.width, gameView.tex.height), true
	case "gameview-stats":
		if !GlobalSettings.gameView.stats || !gameView.stats.have do return "", true
		return fmt.tprintf("%.0f fps %d nodes", gameView.stats.fps, gameView.stats.nodes), true
	}
	return "", false
}
