package engine

import "core:c"
import "core:encoding/json"
import "core:fmt"
import os "osx"
import "core:path/filepath"
import "core:strings"
import lua "lua54"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// Accessibility (docs/accessibility.md): the player's settings, saved in
// accessibility.json next to the save files and loaded when the game
// starts (the project's defaults first, from project.json "accessibility"):
//
//   ui_scale             every top-level UI element grows around the
//                        corner / edge / centre of the screen it is
//                        nearest to (HUD corners stay in their corners);
//                        UI input reads the mouse in the same space
//   colorblind           protanopia / deuteranopia / tritanopia: the frame
//                        is corrected (daltonized) on its way to the
//                        screen - "simulate" shows how it looks instead
//                        (for designers); strength 0..1
//   subtitles, captions  the subtitle track (subtitles.odin): dialogue
//                        lines / sound captions; their size and backdrop
//   screen_shake         scales every camera shake and trauma (0 = none)
//
// Input rebinding is input_rebind.odin (Input.listen).
// ============================================================================

Colorblind_Mode :: enum u8 {None, Protanopia, Deuteranopia, Tritanopia}

Access_Settings :: struct {
	uiScale:            f32,
	colorblind:         Colorblind_Mode,
	colorblindStrength: f32,
	simulate:           bool,
	subtitles:          bool,
	captions:           bool,
	subtitleScale:      f32,
	subtitleBackground: f32,
	screenShake:        f32,
}

ACCESS_DEFAULTS :: Access_Settings{uiScale = 1, colorblindStrength = 1, subtitles = true, subtitleScale = 1, subtitleBackground = 0.6, screenShake = 1}

// The running game's settings, and the project's defaults (Reset).
access := ACCESS_DEFAULTS
accessDefaults := ACCESS_DEFAULTS

// Access_SetDefaults: the project's defaults (project.json) - also the
// current settings until the player's own are loaded.
Access_SetDefaults :: proc(d: Access_Settings) {
	accessDefaults = Access_Clamp(d)
	access = accessDefaults
}

Access_Clamp :: proc(s: Access_Settings) -> Access_Settings {
	c := s
	c.uiScale = clamp(c.uiScale if c.uiScale > 0 else 1, 0.5, 3)
	c.colorblindStrength = clamp(c.colorblindStrength, 0, 1)
	c.subtitleScale = clamp(c.subtitleScale if c.subtitleScale > 0 else 1, 0.5, 3)
	c.subtitleBackground = clamp(c.subtitleBackground, 0, 1)
	c.screenShake = clamp(c.screenShake, 0, 2)
	return c
}

// --- JSON --------------------------------------------------------------------------------

colorblind_name :: proc(m: Colorblind_Mode) -> string {
	switch m {
	case .None: return "none"
	case .Protanopia: return "protanopia"
	case .Deuteranopia: return "deuteranopia"
	case .Tritanopia: return "tritanopia"
	}
	return "none"
}

Colorblind_Parse :: proc(s: string) -> (Colorblind_Mode, bool) {
	switch strings.to_lower(s, context.temp_allocator) {
	case "none", "": return .None, true
	case "protanopia", "protan": return .Protanopia, true
	case "deuteranopia", "deutan": return .Deuteranopia, true
	case "tritanopia", "tritan": return .Tritanopia, true
	}
	return .None, false
}

// Access_ToJSON: the settings as a JSON object (only what differs from
// `base` when it is given).
Access_ToJSON :: proc(s: Access_Settings, allocator := context.allocator, base: Maybe(Access_Settings) = nil) -> string {
	b, hasBase := base.?
	sb := strings.builder_make(allocator)
	strings.write_string(&sb, "{")
	n := 0
	add :: proc(sb: ^strings.Builder, n: ^int, text: string) {
		strings.write_string(sb, ", " if n^ > 0 else "")
		strings.write_string(sb, text)
		n^ += 1
	}
	if !hasBase || s.uiScale != b.uiScale do add(&sb, &n, fmt.tprintf("\"ui_scale\": %.2f", s.uiScale))
	if !hasBase || s.colorblind != b.colorblind do add(&sb, &n, fmt.tprintf("\"colorblind\": %q", colorblind_name(s.colorblind)))
	if !hasBase || s.colorblindStrength != b.colorblindStrength do add(&sb, &n, fmt.tprintf("\"colorblind_strength\": %.2f", s.colorblindStrength))
	if !hasBase || s.simulate != b.simulate do add(&sb, &n, fmt.tprintf("\"colorblind_simulate\": %t", s.simulate))
	if !hasBase || s.subtitles != b.subtitles do add(&sb, &n, fmt.tprintf("\"subtitles\": %t", s.subtitles))
	if !hasBase || s.captions != b.captions do add(&sb, &n, fmt.tprintf("\"captions\": %t", s.captions))
	if !hasBase || s.subtitleScale != b.subtitleScale do add(&sb, &n, fmt.tprintf("\"subtitle_scale\": %.2f", s.subtitleScale))
	if !hasBase || s.subtitleBackground != b.subtitleBackground do add(&sb, &n, fmt.tprintf("\"subtitle_background\": %.2f", s.subtitleBackground))
	if !hasBase || s.screenShake != b.screenShake do add(&sb, &n, fmt.tprintf("\"screen_shake\": %.2f", s.screenShake))
	strings.write_string(&sb, "}")
	return strings.to_string(sb)
}

// Access_FromJSON reads an object over `s` (missing keys keep their value).
Access_FromJSON :: proc(o: json.Object, s: Access_Settings) -> Access_Settings {
	out := s
	num :: proc(v: json.Value) -> (f32, bool) {
		#partial switch x in v {
		case json.Float: return f32(x), true
		case json.Integer: return f32(x), true
		}
		return 0, false
	}
	if v, ok := num(o["ui_scale"]); ok do out.uiScale = v
	if v, ok := o["colorblind"].(json.String); ok do out.colorblind, _ = Colorblind_Parse(v)
	if v, ok := num(o["colorblind_strength"]); ok do out.colorblindStrength = v
	if v, ok := o["colorblind_simulate"].(json.Boolean); ok do out.simulate = bool(v)
	if v, ok := o["subtitles"].(json.Boolean); ok do out.subtitles = bool(v)
	if v, ok := o["captions"].(json.Boolean); ok do out.captions = bool(v)
	if v, ok := num(o["subtitle_scale"]); ok do out.subtitleScale = v
	if v, ok := num(o["subtitle_background"]); ok do out.subtitleBackground = v
	if v, ok := num(o["screen_shake"]); ok do out.screenShake = v
	return Access_Clamp(out)
}

// Access_UserPath: accessibility.json next to the save files.
Access_UserPath :: proc(allocator := context.temp_allocator) -> string {
	p, _ := filepath.join({filepath.dir(Save_FilePath(), context.temp_allocator), "accessibility.json"}, allocator)
	return p
}

// Access_Save writes the player's settings (what differs from the
// project's defaults).
Access_Save :: proc() -> bool {
	path := Access_UserPath()
	_ = os.make_directory_all(filepath.dir(path, context.temp_allocator))
	text := Access_ToJSON(access, context.temp_allocator, accessDefaults)
	return os.write_entire_file(path, transmute([]u8)text) == nil
}

// Access_Load reads the player's settings over the project's defaults.
Access_Load :: proc() -> bool {
	data, err := os.read_entire_file(Access_UserPath(), context.temp_allocator)
	if err != nil do return false
	v, perr := json.parse(data, allocator = context.temp_allocator)
	if perr != nil do return false
	o, ok := v.(json.Object)
	if !ok do return false
	access = Access_FromJSON(o, accessDefaults)
	return true
}

// Access_Reset: back to the project's defaults (not saved until Access_Save).
Access_Reset :: proc() {access = accessDefaults}

// --- UI scale ------------------------------------------------------------------------------
// Each top-level UI element (a UI node whose parent isn't one) is drawn
// scaled around a pivot: per axis the start, centre or end of its rect,
// whichever third of the screen its centre is in. UI input converts the
// mouse into the element's unscaled space (UI_GetMousePos), so widgets
// keep their own coordinates.

// The UI node whose input is being handled (update / focus pass).
uiInputNode: ^Node

// UI_RootOf: the top-level UI element above a UI node (itself if it is one).
UI_RootOf :: proc(n: ^Node) -> ^Node {
	if n == nil || !n.isUI do return nil
	root := n
	m := n.gameContext.scene.manager if n.gameContext != nil && n.gameContext.scene != nil else nil
	if m == nil do return root
	for p := GetParent(m, root); p != nil && p.isUI; p = GetParent(m, p) do root = p
	return root
}

// UI_ScaleTransform: the pivot and scale a UI node is drawn with (scale 1
// when the UI scale is 1 or it isn't UI).
UI_ScaleTransform :: proc(n: ^Node) -> (pivot: [2]f32, scale: f32) {
	if access.uiScale == 1 || n == nil || !n.isUI do return {}, 1
	root := UI_RootOf(n)
	r := UI_GetElementRect(cast(^UIElement)root)
	vw, vh: f32 = 1280, 720
	if gc := root.gameContext; gc != nil && gc.game != nil && gc.game.virtualSize.x > 0 do vw, vh = gc.game.virtualSize.x, gc.game.virtualSize.y
	pick :: proc(start, size, screen: f32) -> f32 {
		c := start + size * 0.5
		if c < screen / 3 do return start
		if c > screen * 2 / 3 do return start + size
		return c
	}
	return {pick(r.x, r.width, vw), pick(r.y, r.height, vh)}, access.uiScale
}

// UI_BeginScaled / UI_EndScaled wrap a UI node's drawing.
UI_BeginScaled :: proc(n: ^Node) -> bool {
	if !rl.IsWindowReady() do return false
	pivot, s := UI_ScaleTransform(n)
	if s == 1 do return false
	rlgl.PushMatrix()
	rlgl.Translatef(pivot.x, pivot.y, 0)
	rlgl.Scalef(s, s, 1)
	rlgl.Translatef(-pivot.x, -pivot.y, 0)
	return true
}

UI_EndScaled :: proc() {rlgl.PopMatrix()}

// UI_UnscalePoint: a screen point in a UI node's unscaled space.
UI_UnscalePoint :: proc(n: ^Node, p: [2]f32) -> [2]f32 {
	pivot, s := UI_ScaleTransform(n)
	if s == 1 do return p
	return pivot + (p - pivot) / s
}

// --- colour-blind filter ---------------------------------------------------------------------
// Daltonization (Fidaner et al.): the colour as seen with the deficiency
// (LMS space, the missing cone rebuilt from the others), the lost
// difference moved into channels that are still seen. Simulate shows the
// first step only.

@(private = "file")
COLORBLIND_FS :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform int mode;        // 1 protanopia, 2 deuteranopia, 3 tritanopia
uniform float strength;
uniform int simulate;
out vec4 finalColor;
void main() {
    vec4 c = texture(texture0, fragTexCoord) * colDiffuse * fragColor;
    vec3 rgb = c.rgb;
    float L = 17.8824 * rgb.r + 43.5161 * rgb.g + 4.11935 * rgb.b;
    float M = 3.45565 * rgb.r + 27.1554 * rgb.g + 3.86714 * rgb.b;
    float S = 0.0299566 * rgb.r + 0.184309 * rgb.g + 1.46709 * rgb.b;
    float l = L, m = M, s = S;
    if (mode == 1) { l = 2.02344 * M - 2.52581 * S; }
    else if (mode == 2) { m = 0.494207 * L + 1.24827 * S; }
    else if (mode == 3) { s = -0.395913 * L + 0.801109 * M; }
    vec3 sim = vec3(
        0.0809444479 * l - 0.130504409 * m + 0.116721066 * s,
        -0.0102485335 * l + 0.0540193266 * m - 0.113614708 * s,
        -0.000365296938 * l - 0.00412161469 * m + 0.693511405 * s);
    vec3 outc;
    if (simulate == 1) {
        outc = sim;
    } else {
        vec3 err = rgb - sim;
        outc = rgb + vec3(0.0, 0.7 * err.r + err.g, 0.7 * err.r + err.b);
    }
    finalColor = vec4(clamp(mix(rgb, outc, strength), 0.0, 1.0), c.a);
}
`

@(private = "file")
cbShader: struct {
	shader:                    rl.Shader,
	loaded:                    bool,
	locMode, locStrength, locSim: i32,
}

// Colorblind_Begin starts drawing through the filter for these settings
// (false = no filter); Colorblind_End after the draws.
Colorblind_Begin :: proc(mode: Colorblind_Mode, strength: f32, simulate: bool) -> bool {
	if mode == .None || strength <= 0 || !rl.IsWindowReady() do return false
	if !cbShader.loaded {
		cbShader.shader = rl.LoadShaderFromMemory(nil, Shader_Port(COLORBLIND_FS))
		cbShader.loaded = true
		cbShader.locMode = rl.GetShaderLocation(cbShader.shader, "mode")
		cbShader.locStrength = rl.GetShaderLocation(cbShader.shader, "strength")
		cbShader.locSim = rl.GetShaderLocation(cbShader.shader, "simulate")
	}
	if cbShader.shader.id == 0 do return false
	m := i32(mode)
	st := strength
	sim := i32(1 if simulate else 0)
	rl.SetShaderValue(cbShader.shader, cbShader.locMode, &m, .INT)
	rl.SetShaderValue(cbShader.shader, cbShader.locStrength, &st, .FLOAT)
	rl.SetShaderValue(cbShader.shader, cbShader.locSim, &sim, .INT)
	rl.BeginShaderMode(cbShader.shader)
	return true
}

Colorblind_End :: proc() {rl.EndShaderMode()}

// Colorblind_Unload frees the shader (window closing).
Colorblind_Unload :: proc() {
	if cbShader.loaded && cbShader.shader.id != 0 && rl.IsWindowReady() do rl.UnloadShader(cbShader.shader)
	cbShader = {}
	if cbTarget.id != 0 && rl.IsWindowReady() do rl.UnloadRenderTexture(cbTarget)
	cbTarget = {}
}

// Colorblind_Apply: a colour through the filter on the CPU (tests, docs;
// the same maths as the shader).
Colorblind_Apply :: proc(c: [3]f32, mode: Colorblind_Mode, strength: f32, simulate: bool) -> [3]f32 {
	if mode == .None do return c
	L := 17.8824 * c.r + 43.5161 * c.g + 4.11935 * c.b
	M := 3.45565 * c.r + 27.1554 * c.g + 3.86714 * c.b
	S := 0.0299566 * c.r + 0.184309 * c.g + 1.46709 * c.b
	l, m, s := L, M, S
	switch mode {
	case .None:
	case .Protanopia: l = 2.02344 * M - 2.52581 * S
	case .Deuteranopia: m = 0.494207 * L + 1.24827 * S
	case .Tritanopia: s = -0.395913 * L + 0.801109 * M
	}
	sim := [3]f32{
		0.0809444479 * l - 0.130504409 * m + 0.116721066 * s,
		-0.0102485335 * l + 0.0540193266 * m - 0.113614708 * s,
		-0.000365296938 * l - 0.00412161469 * m + 0.693511405 * s,
	}
	out := sim
	if !simulate {
		err := c - sim
		out = c + {0, 0.7 * err.r + err.g, 0.7 * err.r + err.b}
	}
	r := c + (out - c) * strength
	return {clamp(r.r, 0, 1), clamp(r.g, 0, 1), clamp(r.b, 0, 1)}
}

// --- Lua -------------------------------------------------------------------------------
// Accessibility.get(key) / set(key, value) / get_all() / save() / reset()
// Subtitles.show(text [, {speaker, duration, caption, color}]) -> id
// Subtitles.hide(id) / clear() / count()

ACCESS_KEYS :: [?]string{"ui_scale", "colorblind", "colorblind_strength", "colorblind_simulate", "subtitles", "captions", "subtitle_scale", "subtitle_background", "screen_shake"}

@(private = "file")
access_push :: proc(L: ^lua.State, key: string) -> bool {
	switch key {
	case "ui_scale": lua.pushnumber(L, lua.Number(access.uiScale))
	case "colorblind": lua.pushstring(L, strings.clone_to_cstring(colorblind_name(access.colorblind), context.temp_allocator))
	case "colorblind_strength": lua.pushnumber(L, lua.Number(access.colorblindStrength))
	case "colorblind_simulate": lua.pushboolean(L, b32(access.simulate))
	case "subtitles": lua.pushboolean(L, b32(access.subtitles))
	case "captions": lua.pushboolean(L, b32(access.captions))
	case "subtitle_scale": lua.pushnumber(L, lua.Number(access.subtitleScale))
	case "subtitle_background": lua.pushnumber(L, lua.Number(access.subtitleBackground))
	case "screen_shake": lua.pushnumber(L, lua.Number(access.screenShake))
	case: return false
	}
	return true
}

@(private = "file")
lua_access_get :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if !access_push(L, string(lua.tostring(L, 1))) do lua.pushnil(L)
	return 1
}

@(private = "file")
lua_access_set :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	key := string(lua.tostring(L, 1))
	num := f32(lua.tonumber(L, 2))
	flag := bool(lua.toboolean(L, 2))
	ok := true
	s := access
	switch key {
	case "ui_scale": s.uiScale = num
	case "colorblind":
		m, valid := Colorblind_Parse(string(lua.tostring(L, 2)))
		s.colorblind, ok = m, valid
	case "colorblind_strength": s.colorblindStrength = num
	case "colorblind_simulate": s.simulate = flag
	case "subtitles": s.subtitles = flag
	case "captions": s.captions = flag
	case "subtitle_scale": s.subtitleScale = num
	case "subtitle_background": s.subtitleBackground = num
	case "screen_shake": s.screenShake = num
	case: ok = false
	}
	if ok do access = Access_Clamp(s)
	else do Script_Problem(.Warning, "Accessibility.set: unknown setting or value '%s'", key)
	lua.pushboolean(L, b32(ok))
	return 1
}

@(private = "file")
lua_access_get_all :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	keys := ACCESS_KEYS
	lua.createtable(L, 0, c.int(len(keys)))
	for k in keys {
		access_push(L, k)
		lua.setfield(L, -2, strings.clone_to_cstring(k, context.temp_allocator))
	}
	return 1
}

@(private = "file")
lua_access_save :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	lua.pushboolean(L, b32(Access_Save()))
	return 1
}

@(private = "file")
lua_access_reset :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	Access_Reset()
	return 0
}

@(private = "file")
lua_sub_show :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	text := string(lua.tostring(L, 1))
	speaker := ""
	duration: f32 = 0
	kind := Subtitle_Kind.Dialogue
	color: rl.Color
	if lua.type(L, 2) == .TABLE {
		lua.getfield(L, 2, "speaker")
		if s := lua.tostring(L, -1); s != nil do speaker = strings.clone(string(s), context.temp_allocator)
		lua.pop(L, 1)
		lua.getfield(L, 2, "duration")
		duration = f32(lua.tonumber(L, -1))
		lua.pop(L, 1)
		lua.getfield(L, 2, "caption")
		if bool(lua.toboolean(L, -1)) do kind = .Caption
		lua.pop(L, 1)
		lua.getfield(L, 2, "color")
		if c, _, ok := Lua_ArgColor(L, lua.gettop(L)); ok do color = c // (any colour form; 0..255 still read: #327)
		lua.pop(L, 1)
	}
	if duration <= 0 do duration = Subtitles_ReadingTime(text)
	lua.pushinteger(L, lua.Integer(Subtitles_Show(text, speaker, duration, kind, color)))
	return 1
}

@(private = "file")
lua_sub_hide :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	Subtitles_Hide(u64(lua.tointeger(L, 1)))
	return 0
}

@(private = "file")
lua_sub_clear :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	Subtitles_Clear()
	return 0
}

@(private = "file")
lua_sub_count :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	lua.pushinteger(L, lua.Integer(Subtitles_Count()))
	return 1
}

// Script_RegisterAccessibilityModules creates the Accessibility and
// Subtitles tables.
Script_RegisterAccessibilityModules :: proc(L: ^lua.State) {
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	lua.newtable(L)
	reg(L, "get", lua_access_get)
	reg(L, "set", lua_access_set)
	reg(L, "get_all", lua_access_get_all)
	reg(L, "save", lua_access_save)
	reg(L, "reset", lua_access_reset)
	lua.setglobal(L, "Accessibility")
	lua.newtable(L)
	reg(L, "show", lua_sub_show)
	reg(L, "hide", lua_sub_hide)
	reg(L, "clear", lua_sub_clear)
	reg(L, "count", lua_sub_count)
	lua.setglobal(L, "Subtitles")
}

@(private = "file")
cbTarget: rl.RenderTexture2D

// Colorblind_Process draws a render texture through the filter into the
// filter's own target (same orientation) and returns it - the editor's
// Colour Vision preview. Returns `src` when there is nothing to do.
Colorblind_Process :: proc(src: rl.Texture2D, mode: Colorblind_Mode, strength: f32, simulate: bool) -> rl.Texture2D {
	if mode == .None || src.id == 0 || !rl.IsWindowReady() do return src
	if cbTarget.id == 0 || cbTarget.texture.width != src.width || cbTarget.texture.height != src.height {
		if cbTarget.id != 0 do rl.UnloadRenderTexture(cbTarget)
		cbTarget = rl.LoadRenderTexture(src.width, src.height)
	}
	rl.BeginTextureMode(cbTarget)
	rl.ClearBackground({0, 0, 0, 0})
	on := Colorblind_Begin(mode, strength, simulate)
	rl.DrawTextureRec(src, {0, 0, f32(src.width), -f32(src.height)}, {0, 0}, rl.WHITE)
	if on do Colorblind_End()
	rl.EndTextureMode()
	return cbTarget.texture
}
