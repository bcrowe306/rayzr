package engine

import "core:fmt"
import os "osx"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// Lighting's per-node passes (lighting.odin): the world drawn again, each
// node as a flat value instead of its colours, where it covers.
//
//   Info:     r = the light layers that light it (Lit By), g = 1 unlit
//             (Ignore Lighting). Read by each light (lights skip pixels
//             not on their layers) and the unlit pass.
//   Emission: what glows - the node's Emission colour x strength, plus its
//             image's emission map (<image>_e.png, or its import setting
//             "emission_map"; "none" off). Added after the light multiply,
//             so it shows in the dark (and Bloom catches it).
//
// Nodes that set their own shader (text's SDF / MSDF) read the pass's
// value through Value_Pass* (text.odin). GPU particles and post effects
// aren't drawn in these passes: they're lit by every light and don't glow.
// ============================================================================

Value_Pass :: enum {None, Info, Emission}

// The pass being drawn (render_bucket draws each node with its value).
renderValuePass: Value_Pass
// The current node's value (rgba 0..1), for shaders of their own (text).
renderPassValue: [4]f32
// The current draw uses its image's emission map (Emission pass).
renderPassUseMap: bool

EMISSION_SUFFIX :: "_e"

@(private = "file")
VALUE_SHADER :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;
uniform sampler2D texture0;
uniform vec4 passValue;
uniform float useMap;   // the texture is an emission map: its colour adds
void main() {
    vec4 t = texture(texture0, fragTexCoord);
    if (t.a * fragColor.a < 0.5) discard;
    vec3 c = passValue.rgb;
    if (useMap > 0.5) c += t.rgb;
    finalColor = vec4(c, passValue.a);
}
`

@(private = "file")
vp: struct {
	shader:   rl.Shader,
	ok:       bool,
	locValue: i32,
	locMap:   i32,
	value:    [4]f32, // the uniforms as set (changing them flushes the batch)
	useMap:   bool,
	maps:     map[u32]Emission_Entry, // an image's GPU texture id -> its emission map
	checked:  bool,
	any:      bool, // the project has an emission map
}

@(private = "file")
Emission_Entry :: struct {
	tex: rl.Texture2D,
	has: bool,
}

// Value_BeginPass starts a pass into `target` (cleared to its "nothing"
// value) through the world camera. False: no shader (nothing drawn).
Value_BeginPass :: proc(pass: Value_Pass, target: ^rl.RenderTexture2D, cam: rl.Camera2D) -> bool {
	if !vp.ok && rl.IsWindowReady() {
		vp.shader = rl.LoadShaderFromMemory(nil, Shader_Port(VALUE_SHADER))
		vp.ok = rl.IsShaderValid(vp.shader)
		vp.locValue = rl.GetShaderLocation(vp.shader, "passValue")
		vp.locMap = rl.GetShaderLocation(vp.shader, "useMap")
	}
	if !vp.ok do return false
	rl.BeginTextureMode(target^)
	// Info: lit by every layer, not unlit. Emission: none.
	rl.ClearBackground({255, 0, 0, 255} if pass == .Info else {0, 0, 0, 255})
	rl.BeginMode2D(cam)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableColorBlend()
	rl.BeginShaderMode(vp.shader)
	renderValuePass = pass
	vp.value = {-1, -1, -1, -1} // (set at the first node)
	vp.useMap = true
	value_set_map(false)
	return true
}

Value_EndPass :: proc() {
	rlgl.DrawRenderBatchActive()
	rl.EndShaderMode()
	rlgl.EnableColorBlend()
	rl.EndMode2D()
	rl.EndTextureMode()
	renderValuePass = .None
	renderPassUseMap = false
}

// Value_NodeDrawn: drawn in the passes (not GPU particles, post effects).
Value_NodeDrawn :: proc(n: ^Node) -> bool {
	switch n.typeId {
	case PostEffectNode, LightNode, EnvironmentNode, LightOccluderNode:
		return false
	case ParticleEmitterNode:
		return !(cast(^ParticleEmitterNode)n).emitter.gpu
	}
	return true
}

// Value_BeginNode: the pass's value for this node (the uniform changes only
// when it differs: batching holds across nodes alike).
Value_BeginNode :: proc(n: ^Node) {
	v: [4]f32
	switch renderValuePass {
	case .Info:
		v = {f32(transmute(u8)n.litLayers) / 255, 1 if n.ignoreLighting else 0, 0, 1}
	case .Emission:
		s := max(n.emissionStrength, 0)
		e := n.emission
		v = {f32(e.r) / 255 * s, f32(e.g) / 255 * s, f32(e.b) / 255 * s, 1}
	case .None:
		return
	}
	renderPassValue = v
	rl.BeginShaderMode(vp.shader) // (back after a node with a shader of its own)
	if v != vp.value {
		rlgl.DrawRenderBatchActive()
		vv := v
		rl.SetShaderValue(vp.shader, vp.locValue, &vv, .VEC4)
		vp.value = v
	}
	value_set_map(false)
}

@(private = "file")
value_set_map :: proc(on: bool) {
	renderPassUseMap = on
	if on == vp.useMap do return
	rlgl.DrawRenderBatchActive()
	f: f32 = 1 if on else 0
	rl.SetShaderValue(vp.shader, vp.locMap, &f, .FLOAT)
	vp.useMap = on
}

// Value_Texture: in the emission pass, the image's emission map instead of
// the image (Lit_Draw); elsewhere the image itself.
Value_Texture :: proc(rm: ^ResourceManager, tex: rl.Texture2D) -> rl.Texture2D {
	if renderValuePass != .Emission do return tex
	if m, ok := Emission_TextureFor(rm, tex); ok {
		value_set_map(true)
		return m
	}
	value_set_map(false)
	return tex
}

// Lighting_NeedsInfo: a node lit by only some layers or unlit, or a light
// on only some layers - the info pass is needed (anyUnlit: Ignore Lighting).
Lighting_NeedsInfo :: proc(scene: ^Scene) -> (need, anyUnlit: bool) {
	for n in scene.manager.nodes {
		if n == nil || !n.enabled do continue
		if n.ignoreLighting {
			need, anyUnlit = true, true
		} else if n.litLayers != ALL_LIGHT_LAYERS {
			need = true
		}
		if n.typeId == LightNode && (cast(^LightNode)n).layers != ALL_LIGHT_LAYERS do need = true
	}
	return
}

// Lighting_NeedsEmission: a node glows, or an image has an emission map.
Lighting_NeedsEmission :: proc(scene: ^Scene) -> bool {
	for n in scene.manager.nodes do if n != nil && n.enabled && n.emissionStrength > 0 do return true
	rm := Node_ResourceManager(scene.rootNode)
	if rm == nil do return false
	if !vp.checked {
		vp.checked = true
		vp.any = false
		for t in rm.textures do if t != nil && t.page == 0 && Emission_PathFor(rm, t.filePath) != "" {
			vp.any = true
			break
		}
	}
	return vp.any
}

// Emission_PathFor: an image's emission map ("" none): its import setting,
// else <image>_e.png beside it.
Emission_PathFor :: proc(rm: ^ResourceManager, imagePath: string) -> string {
	if imagePath == "" || strings.contains(imagePath, "://") do return ""
	if imp := Asset_ImportGet(rm, imagePath); imp != nil {
		if imp.emissionMap == "none" do return ""
		if imp.emissionMap != "" {
			p := imp.emissionMap
			if !filepath.is_abs(p) && rm.projectDir != "" do p, _ = filepath.join({rm.projectDir, p}, context.temp_allocator)
			return p if emission_exists(rm, p) else ""
		}
	}
	ext := filepath.ext(imagePath)
	if ext == "" do return ""
	base := imagePath[:len(imagePath) - len(ext)]
	for suf in ([?]string{EMISSION_SUFFIX, NORMAL_SUFFIX, SPECULAR_SUFFIX}) do if strings.has_suffix(base, suf) do return "" // (a map itself)
	p := strings.concatenate({base, EMISSION_SUFFIX, ".png"}, context.temp_allocator)
	return p if emission_exists(rm, p) else ""
}

@(private = "file")
emission_exists :: proc(rm: ^ResourceManager, p: string) -> bool {
	if os.is_file(p) do return true
	if rm != nil && rm.package_ != nil {
		if b, ok := resource_bytes(rm, p); ok {
			delete(b)
			return true
		}
	}
	return false
}

// Emission_TextureFor: an image's emission map, sized like it and keeping
// its alpha (has = false: none).
Emission_TextureFor :: proc(rm: ^ResourceManager, tex: rl.Texture2D) -> (rl.Texture2D, bool) {
	if e, ok := vp.maps[tex.id]; ok do return e.tex, e.has
	if vp.maps == nil do vp.maps = make(map[u32]Emission_Entry, allocator = Engine_HeapAllocator())
	entry: Emission_Entry
	defer vp.maps[tex.id] = entry
	if rm == nil || !rl.IsWindowReady() do return {}, false
	imagePath := ""
	for t in rm.textures do if t != nil && t.page == 0 && t.texture.id == tex.id {
		imagePath = t.filePath
		break
	}
	p := Emission_PathFor(rm, imagePath)
	if p == "" do return {}, false
	img: rl.Image
	if os.is_file(p) {
		img = rl.LoadImage(fmt.ctprint(p))
	} else if b, ok := resource_bytes(rm, p); ok {
		img = rl.LoadImageFromMemory(fmt.ctprint(Image_ExtFor(b, p)), raw_data(b), i32(len(b)))
		delete(b)
	}
	if img.data == nil do return {}, false
	rl.ImageFormat(&img, .UNCOMPRESSED_R8G8B8A8)
	if img.width != tex.width || img.height != tex.height do rl.ImageResize(&img, tex.width, tex.height)
	entry.tex = rl.LoadTextureFromImage(img)
	rl.UnloadImage(img)
	rl.SetTextureFilter(entry.tex, .POINT)
	rl.SetTextureWrap(entry.tex, .CLAMP)
	entry.has = true
	return entry.tex, true
}

// Emission_ForgetAll drops every emission map (an image or its settings
// changed; they're loaded again as needed).
Emission_ForgetAll :: proc() {
	if rl.IsWindowReady() do for _, e in vp.maps do if e.has do rl.UnloadTexture(e.tex)
	clear(&vp.maps)
	vp.checked = false
}

// Value_Unload frees the passes' shader and maps.
Value_Unload :: proc() {
	if rl.IsWindowReady() {
		for _, e in vp.maps do if e.has do rl.UnloadTexture(e.tex)
		if vp.ok do rl.UnloadShader(vp.shader)
	}
	delete(vp.maps)
	vp = {}
}
