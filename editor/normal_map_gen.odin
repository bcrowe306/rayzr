package editor

import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"
import rl "vendor:raylib"

// ============================================================================
// Generate Normal Map (#274; an image's right-click menu in Assets): a
// normal map from the sprite's shape (a bevel) and / or brightness, with a
// lit preview (the light follows the mouse over it). Save writes
// <image>_n.png next to it, which lighting picks up by itself.
// ============================================================================

@(private = "file")
gen: struct {
	open:     bool,
	rel:      string, // the image (project-relative, heap)
	src:      rl.Image,
	diffuse:  rl.Texture2D,
	normal:   rl.Texture2D,
	preview:  rl.RenderTexture2D,
	shader:   rl.Shader,
	shaderOk: bool,
	opts:     e.Normal_Gen_Options,
	dirty:    bool,
	light:    [2]f32, // 0..1 over the image
}

@(private = "file")
PREVIEW_FS :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;
uniform sampler2D texture0;
uniform sampler2D normalTex;
uniform vec2 lightPos;
uniform vec2 size;
void main() {
    vec4 d = texture(texture0, fragTexCoord);
    vec2 nxy = texture(normalTex, fragTexCoord).rg * 2.0 - 1.0;
    nxy.y = -nxy.y; // (green up)
    vec3 N = vec3(nxy, sqrt(max(0.0, 1.0 - dot(nxy, nxy))));
    vec3 L = normalize(vec3((lightPos - fragTexCoord) * size, max(size.x, size.y) * 0.35));
    float lit = 0.2 + max(dot(N, L), 0.0) * 0.95;
    finalColor = vec4(d.rgb * lit, d.a);
}
`

NormalGen_Open :: proc(state: ^EditorState, rel: string) {
	NormalGen_Close()
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	img := rl.LoadImage(fmt.ctprint(full))
	if img.data == nil {
		Editor_Log(state, .Error, "Generate Normal Map: can't read %s", rel)
		return
	}
	gen.rel = strings.clone(rel)
	gen.src = img
	gen.diffuse = rl.LoadTextureFromImage(img)
	gen.opts = {strength = 3, softness = 6, shape = true, brightness = true}
	gen.light = {0.25, 0.25}
	gen.dirty = true
	gen.open = true
	imgui.SetWindowFocusStr("Generate Normal Map###NormalGen")
}

NormalGen_Close :: proc() {
	if gen.src.data != nil do rl.UnloadImage(gen.src)
	if gen.diffuse.id != 0 do rl.UnloadTexture(gen.diffuse)
	if gen.normal.id != 0 do rl.UnloadTexture(gen.normal)
	if gen.preview.id != 0 do rl.UnloadRenderTexture(gen.preview)
	if gen.shaderOk do rl.UnloadShader(gen.shader)
	delete(gen.rel)
	gen = {}
}

@(private = "file")
gen_normal_path :: proc(state: ^EditorState) -> (rel, full: string) {
	ext := filepath.ext(gen.rel)
	rel = strings.concatenate({gen.rel[:len(gen.rel) - len(ext)], e.NORMAL_SUFFIX, ".png"}, context.temp_allocator)
	full, _ = filepath.join({state.projectPath, rel}, context.temp_allocator)
	return
}

@(private = "file")
gen_rebuild :: proc() {
	img := e.Normal_Generate(gen.src, gen.opts)
	if gen.normal.id != 0 do rl.UnloadTexture(gen.normal)
	gen.normal = rl.LoadTextureFromImage(img)
	rl.UnloadImage(img)
	gen.dirty = false
}

// gen_draw_preview: the image lit by the normal map, into the preview texture.
@(private = "file")
gen_draw_preview :: proc() {
	w, h := gen.src.width, gen.src.height
	if gen.preview.id == 0 do gen.preview = rl.LoadRenderTexture(w, h)
	if !gen.shaderOk {
		gen.shader = rl.LoadShaderFromMemory(nil, e.Shader_Port(PREVIEW_FS))
		gen.shaderOk = rl.IsShaderValid(gen.shader)
	}
	rl.BeginTextureMode(gen.preview)
	rl.ClearBackground({30, 32, 40, 255})
	if gen.shaderOk {
		rl.BeginShaderMode(gen.shader)
		lp := gen.light
		sz := [2]f32{f32(w), f32(h)}
		rl.SetShaderValue(gen.shader, rl.GetShaderLocation(gen.shader, "lightPos"), &lp, .VEC2)
		rl.SetShaderValue(gen.shader, rl.GetShaderLocation(gen.shader, "size"), &sz, .VEC2)
		rl.SetShaderValueTexture(gen.shader, rl.GetShaderLocation(gen.shader, "normalTex"), gen.normal)
	}
	rl.DrawTexture(gen.diffuse, 0, 0, rl.WHITE)
	if gen.shaderOk do rl.EndShaderMode()
	rl.EndTextureMode()
}

NormalGen_Render :: proc(state: ^EditorState) {
	if !gen.open do return
	vp := imgui.GetMainViewport()
	imgui.SetNextWindowPos(vp.WorkPos + vp.WorkSize * 0.5, .FirstUseEver, {0.5, 0.5})
	imgui.SetNextWindowSize({620, 460}, .FirstUseEver)
	open := true
	visible := imgui.Begin(fmt.ctprintf("%s  Generate Normal Map: %s###NormalGen", ICON_FA_WAND_MAGIC_SPARKLES, gen.rel), &open, {})
	defer imgui.End()
	if !open {
		NormalGen_Close()
		return
	}
	if !visible do return
	Drive_Window("normal-gen")
	UI_DimTextWrapped("Lights shade the image by this normal map: the outline rises into a bevel (Shape) and lighter parts stand out (Brightness). Move the mouse over the preview to move the light.")
	o := &gen.opts
	if imgui.SliderFloat("Strength##ng", &o.strength, 0.5, 12, "%.1f") do gen.dirty = true
	Drive_Item("normal-gen.strength")
	UI_Tooltip("How steep the slopes are")
	soft := i32(o.softness)
	if imgui.SliderInt("Softness##ng", &soft, 0, 48) {
		o.softness = int(soft)
		gen.dirty = true
	}
	Drive_Item("normal-gen.softness")
	UI_Tooltip("How wide the bevel around the outline is (px)")
	if imgui.Checkbox("Shape##ng", &o.shape) do gen.dirty = true
	Drive_Item("normal-gen.shape")
	UI_Tooltip("The outline rises into a rounded bevel")
	imgui.SameLine(0, UI_SPACE * 2)
	if imgui.Checkbox("Brightness##ng", &o.brightness) do gen.dirty = true
	Drive_Item("normal-gen.brightness")
	UI_Tooltip("Lighter pixels are higher: painted detail catches the light")
	imgui.SameLine(0, UI_SPACE * 2)
	if imgui.Checkbox("Invert##ng", &o.invert) do gen.dirty = true
	Drive_Item("normal-gen.invert")
	UI_Tooltip("Darker pixels are higher instead (dark outlines, engraved detail)")
	if gen.dirty do gen_rebuild()
	gen_draw_preview()
	// The normal map and the lit image, side by side.
	avail := imgui.GetContentRegionAvail()
	w, h := f32(gen.src.width), f32(gen.src.height)
	side := min((avail.x - UI_SPACE * 2) * 0.5, avail.y - 60)
	sc := min(side / max(w, 1), side / max(h, 1))
	sz := imgui.Vec2{w * sc, h * sc}
	imgui.Image(transmute(imgui.TextureID)&gen.normal, sz)
	imgui.SameLine(0, UI_SPACE * 2)
	p := imgui.GetCursorScreenPos()
	imgui.Image(transmute(imgui.TextureID)&gen.preview.texture, sz, {0, 1}, {1, 0})
	Drive_Item("normal-gen.preview")
	if imgui.IsItemHovered() {
		m := imgui.GetMousePos()
		gen.light = {(m.x - p.x) / sz.x, (m.y - p.y) / sz.y}
	} else {
		t := f32(rl.GetTime())
		gen.light = {0.5 + 0.45 * math.cos(t), 0.5 + 0.45 * math.sin(t)}
	}
	rel, full := gen_normal_path(state)
	if UI_Button(fmt.tprintf("%s  Save %s", ICON_FA_FLOPPY_DISK, filepath.base(rel)), "normal-gen.save") {
		img := e.Normal_Generate(gen.src, gen.opts)
		ok := rl.ExportImage(img, fmt.ctprint(full))
		rl.UnloadImage(img)
		if ok {
			Editor_Log(state, .Info, "Saved %s: lights now shade %s by it", rel, gen.rel)
			Editor_InvalidateProjectFiles()
			e.Lit_ForgetAll()
		} else {
			Editor_Log(state, .Error, "Couldn't write %s", rel)
		}
	}
	if os.exists(full) {
		imgui.SameLine()
		UI_DimText("(replaces the one there)")
	}
}
