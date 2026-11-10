package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Inspector: Material (shader, blend mode, shader parameters) on any
// renderable node. Parameters are the shader's uniforms; edited values are
// stored on the node, the reset button returns one to the shader's default.
// ============================================================================

SHADER_EXTS := []string{".fs", ".glsl", ".frag"}

SHADER_TEMPLATE :: `#version 330
// $NAME$: a fragment shader for a node's Material (Inspector > Material).
// Every uniform below becomes a parameter in the Inspector; hints after //:
//   color                 edit a vec4 as a colour
//   range <min> <max>     a slider
//   default <x> [y z w]   the value until it's edited
// "time" is set automatically (seconds). Lua: node:set_shader_param(name, ...).

in vec2 fragTexCoord;       // texture coordinate of this pixel
in vec4 fragColor;          // the node's tint
uniform sampler2D texture0; // the node's texture
uniform vec4 colDiffuse;
out vec4 finalColor;

uniform float time;
uniform vec4 tint_color; // color default 1 0.8 0.4 1
uniform float strength;  // range 0 1 default 0.5

void main() {
    vec4 c = texture(texture0, fragTexCoord) * colDiffuse * fragColor;
    float pulse = 0.5 + 0.5 * sin(time * 4.0);
    finalColor = vec4(mix(c.rgb, c.rgb * tint_color.rgb, strength * pulse), c.a);
}
`

// Editor_NewShader writes shaders/<name>.fs from the template and opens it.
Editor_NewShader :: proc(state: ^EditorState, baseName := "new_shader") -> string {
	Lua_MarkProjectTypesDirty()
	dir, _ := filepath.join({state.projectPath, "shaders"}, context.temp_allocator)
	_ = os.make_directory_all(dir)
	name := baseName
	rel := ""
	for i := 1; ; i += 1 {
		if i > 1 do name = fmt.tprintf("%s_%d", baseName, i)
		rel = fmt.tprintf("shaders/%s.fs", name)
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		if !os.exists(full) do break
	}
	text, _ := strings.replace_all(SHADER_TEMPLATE, "$NAME$", name, context.temp_allocator)
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	if os.write_entire_file(full, transmute([]u8)text) != nil {
		Editor_Log(state, .Error, "Could not create %s", rel)
		return ""
	}
	Editor_Log(state, .Info, "Created %s", rel)
	Editor_OpenScript(state, rel, 18, 0)
	return strings.clone(rel, context.temp_allocator)
}

@(private = "file")
shader_label :: proc(path: string) -> string {
	if path == "" do return "None"
	if strings.has_prefix(path, "builtin:") {
		n := path[len("builtin:"):]
		return fmt.tprintf("%s (built-in)", pretty_name(n))
	}
	return path
}

inspector_material :: proc(state: ^EditorState, node: ^e.Node) {
	if !node.renderable && node.material == nil do return
	m := node.material
	// Collapsed until a node has a material (keeps the Inspector short).
	if !UI_SectionHeader("Material", m != nil) do return
	if !UI_BeginProps("##material") do return
	defer UI_EndProps()
	ctx := &state.game.gameContext

	// Shader.
	UI_PropLabel("Shader")
	cur := m.shader if m != nil else ""
	imgui.SetNextItemWidth(field_width())
	if imgui.BeginCombo("##shader", strings.clone_to_cstring(shader_label(cur), context.temp_allocator)) {
		pick :: proc(state: ^EditorState, node: ^e.Node, path, cur: string) {
			if imgui.Selectable(strings.clone_to_cstring(shader_label(path), context.temp_allocator), path == cur) && path != cur {
				Editor_RecordUndo(state, "Set shader")
				e.Material_SetShader(node, path)
			}
			Drive_Item(fmt.tprintf("pick:%s", path if path != "" else "None"))
		}
		pick(state, node, "", cur)
		imgui.SeparatorText("Built-in")
		for b in e.BUILTIN_SHADERS do pick(state, node, b, cur)
		files := Editor_ListProjectFiles(state, "", SHADER_EXTS)
		if len(files) > 0 do imgui.SeparatorText("Project")
		for f in files do pick(state, node, f, cur)
		imgui.EndCombo()
	}
	Drive_Item("insp.material.shader")
	if field_reset("insp.material.shader", cur != "") {
		Editor_RecordUndo(state, "Remove shader")
		e.Material_SetShader(node, "")
		clear(&node.material.params)
	}

	// Blend mode.
	UI_PropLabel("Blend")
	names := []string{"Alpha", "Additive", "Multiply", "Add Colors", "Subtract Colors", "Premultiplied"}
	blend := int(m.blend) if m != nil else 0
	imgui.SetNextItemWidth(field_width())
	if b, changed := UI_Combo("insp.material.blend", blend, names); changed {
		Editor_RecordUndo(state, "Blend mode")
		e.Node_EnsureMaterial(node).blend = e.Material_Blend(b)
	}
	if field_reset("insp.material.blend.r", blend != 0) {
		Editor_RecordUndo(state, "Blend mode")
		node.material.blend = .Alpha
	}

	if cur == "" {
		UI_PropLabel("")
		if UI_Button(fmt.tprintf("%s  New Shader...", ICON_FA_PLUS), "insp.material.new", {-1, 0}) {
			if rel := Editor_NewShader(state, strings.to_snake_case(node.name, context.temp_allocator)); rel != "" {
				Editor_RecordUndo(state, "Set shader")
				e.Material_SetShader(node, rel)
			}
		}
		return
	}
	if e.Shader_Failed(cur, ctx) {
		UI_PropLabel("")
		imgui.PushStyleColorImVec4(.Text, UI_DANGER)
		imgui.TextWrapped(fmt.ctprintf("%s  The shader couldn't be loaded or compiled (see the console).", ICON_FA_TRIANGLE_EXCLAMATION))
		imgui.PopStyleColor()
	}

	// Parameters from the shader's uniforms.
	for u in e.Shader_Uniforms(cur, ctx) {
		if u.auto do continue
		imgui.PushID(strings.clone_to_cstring(u.name, context.temp_allocator))
		UI_PropLabel(pretty_name(u.name))
		v, tex, _ := e.Material_GetParam(node, u.name)
		set := false
		id := fmt.tprintf("insp.material.param:%s", u.name)
		imgui.SetNextItemWidth(field_width())
		switch u.kind {
		case .Float:
			if u.hasRange do set = imgui.SliderFloat("##v", &v.x, u.min, u.max, "%.3g")
			else do set = imgui.DragFloat("##v", &v.x, 0.01, 0, 0, "%.3g")
		case .Int:
			iv := i32(v.x)
			if imgui.DragInt("##v", &iv, 0.2) {v.x = f32(iv); set = true}
		case .Vec2:
			set = imgui.DragFloat2("##v", cast(^[2]f32)&v, 0.01)
		case .Vec3:
			if u.isColor do set = imgui.ColorEdit3("##v", cast(^[3]f32)&v, {.Float})
			else do set = imgui.DragFloat3("##v", cast(^[3]f32)&v, 0.01)
		case .Vec4:
			if u.isColor do set = imgui.ColorEdit4("##v", &v, {.AlphaBar})
			else do set = imgui.DragFloat4("##v", &v, 0.01)
		case .Texture:
			if path, ok := asset_picker(id, tex, Editor_ListProjectFiles(state, "", TEXTURE_EXTS)); ok {
				Editor_RecordUndo(state, "Shader texture")
				e.Material_SetParam(node, u.name, {}, path)
			}
		}
		Drive_Item(id)
		undo_on_activate(state, fmt.tprintf("Edit %s", u.name))
		if set do e.Material_SetParam(node, u.name, v)
		// Edited (stored on the node) -> reset to the shader's default.
		stored := false
		for p in node.material.params do if p.name == u.name do stored = true
		if field_reset(id, stored) {
			Editor_RecordUndo(state, fmt.tprintf("Reset %s", u.name))
			e.Material_RemoveParam(node, u.name)
		}
		imgui.PopID()
	}
	if !strings.has_prefix(cur, "builtin:") {
		UI_PropLabel("")
		if UI_Button(fmt.tprintf("%s  Edit Shader", ICON_FA_CODE), "insp.material.edit", {-1, 0}) do Editor_OpenScript(state, cur)
		UI_Tooltip("Saving the shader reloads it in the viewport")
	}
}

// inspector_pixels: the Pixels section (#409) - a drawn node's Texture
// Filter and Snap to Pixels (Inherit: the textures' import filter / the
// project's Pixel Snap) and, for text and UI, where it draws when the game
// is scaled up (Native: crisp at the window's resolution; Pixel: in the
// game's pixels). Pixel_Filter / Pixel_Snap / Pixel_Text in the engine.
inspector_pixels :: proc(state: ^EditorState, node: ^e.Node) {
	if node.render == nil do return
	textual := node.isUI || node.typeId == e.TextNode
	changed := node.pixelFilter != .Inherit || node.pixelSnap != .Inherit || node.pixelText != .Default
	if !UI_SectionHeader("Pixels", changed) do return
	if !UI_BeginProps("##pixels") do return
	defer UI_EndProps()

	mfField := node_field(node, &node.pixelFilter, "pixelFilter", .Enum, e.Pixel_Filter)
	prop_row_label(state, node, "Texture Filter", mfField)
	mf := multi_begin(state, node, mfField)
	imgui.SetNextItemWidth(field_width())
	if v, ok := UI_Combo("insp.pixel-filter", int(node.pixelFilter), {"Inherit", "Sharp", "Smooth"}, mf.mixed[0]); ok {
		Editor_RecordUndo(state, "Texture filter")
		node.pixelFilter = e.Pixel_Filter(v)
	}
	UI_Tooltip("How its textures are sampled when drawn scaled or between pixels. Inherit: each texture's import setting (Assets); Sharp: nearest-neighbour (pixel art); Smooth: bilinear")
	multi_end(&mf)

	msField := node_field(node, &node.pixelSnap, "pixelSnap", .Enum, e.Pixel_Snap)
	prop_row_label(state, node, "Snap to Pixels", msField)
	ms := multi_begin(state, node, msField)
	imgui.SetNextItemWidth(field_width())
	if v, ok := UI_Combo("insp.pixel-snap", int(node.pixelSnap), {"Inherit", "On", "Off"}, ms.mixed[0]); ok {
		Editor_RecordUndo(state, "Snap to pixels")
		node.pixelSnap = e.Pixel_Snap(v)
	}
	UI_Tooltip("Draw it on whole game pixels (no shimmer, no uneven pixels while it moves). Inherit: the project's Pixel Snap (Project Settings > Video)")
	multi_end(&ms)

	if !textual do return
	mtField := node_field(node, &node.pixelText, "pixelText", .Enum, e.Pixel_Text)
	prop_row_label(state, node, "Text Pixels", mtField)
	mt := multi_begin(state, node, mtField)
	imgui.SetNextItemWidth(field_width())
	def := "UI: Native" if node.isUI else "Text: Pixel"
	if v, ok := UI_Combo("insp.pixel-text", int(node.pixelText), {fmt.tprintf("Default (%s)", def), "Native", "Pixel"}, mt.mixed[0]); ok {
		Editor_RecordUndo(state, "Text pixels")
		node.pixelText = e.Pixel_Text(v)
	}
	UI_Tooltip("When the game's low resolution is scaled up to the window. Native: drawn crisp at the window's resolution, over the game (in its order among Native nodes). Pixel: drawn in the game's pixels, scaled with them (pixel fonts)")
	multi_end(&mt)
}
