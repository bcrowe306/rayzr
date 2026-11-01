package engine

import "core:fmt"
import "core:math"
import os "osx"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// Normal maps for 2D lighting (#274). An image's normal map is
// <image>_n.png next to it (or the image's import setting "normal_map";
// "none" turns it off); <image>_s.png is its specular map (how shiny,
// per pixel). Texture-drawn nodes (sprites, animation frames, nine
// slices, tile maps, LDtk tiles) have a Shininess too.
//
// When the scene is lit and the project uses normal maps or shininess, a
// normal pass (Lighting_Prepare) draws the world's texture-drawn nodes
// again into a normal buffer: each draw goes through Lit_Draw, which swaps
// the image for its "lit" texture (normal xy, specular, the image's alpha)
// and passes the draw's rotation, flips and shininess in the vertex colour
// (so drawing stays batched). Images without a normal map write "flat":
// those pixels light exactly as without normal maps. Each light then reads
// the buffer: N.L with the light's height, and a specular glint.
// ============================================================================

// The normal pass is drawing (Lit_Draw swaps textures; render_bucket skips
// what isn't texture-drawn).
renderNormalPass: bool
// The node being drawn (render_bucket): its shininess.
normalPassNode: ^Node

NORMAL_SUFFIX :: "_n"
SPECULAR_SUFFIX :: "_s"

@(private = "file")
Lit_Entry :: struct {
	tex:       rl.Texture2D, // normal xy (rg), specular (b), the image's alpha (a)
	has:       bool,
	greenDown: bool,
}

@(private = "file")
lit: struct {
	byId:      map[u32]Lit_Entry, // the image's GPU texture id
	shader:    rl.Shader,
	shaderOk:  bool,
	anyChecked: bool,
	any:       bool, // the project has a normal map
}

@(private = "file")
NORMAL_PASS_FS :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;
uniform sampler2D texture0;
// fragColor: r, g = the draw's rotation (cos, sin), b = flags (1 flip x, 2
// flip y, 4 flat: no normal map, 8 green down), a = shininess.
void main() {
    vec4 t = texture(texture0, fragTexCoord);
    if (t.a < 0.5) discard;
    float flags = floor(fragColor.b * 255.0 + 0.5);
    float shin = fragColor.a;
    if (mod(floor(flags / 4.0), 2.0) >= 1.0) {
        finalColor = vec4(0.5, 0.5, shin, 0.0);
        return;
    }
    vec2 n = t.rg * 2.0 - 1.0;
    if (mod(floor(flags / 8.0), 2.0) < 1.0) n.y = -n.y; // (image up is world -y)
    if (mod(flags, 2.0) >= 1.0) n.x = -n.x;
    if (mod(floor(flags / 2.0), 2.0) >= 1.0) n.y = -n.y;
    float c = fragColor.r * 2.0 - 1.0;
    float s = fragColor.g * 2.0 - 1.0;
    n = vec2(c * n.x - s * n.y, s * n.x + c * n.y);
    finalColor = vec4(n * 0.5 + 0.5, max(t.b, shin), 1.0);
}
`

// Lit_Shader: the normal pass's shader.
Lit_Shader :: proc() -> (rl.Shader, bool) {
	if !lit.shaderOk && rl.IsWindowReady() {
		lit.shader = rl.LoadShaderFromMemory(nil, Shader_Port(NORMAL_PASS_FS))
		lit.shaderOk = rl.IsShaderValid(lit.shader)
	}
	return lit.shader, lit.shaderOk
}

// Lit_Unload frees the lit textures (the project changing, shutdown).
Lit_Unload :: proc() {
	if rl.IsWindowReady() {
		for _, e in lit.byId do if e.has do rl.UnloadTexture(e.tex)
		if lit.shaderOk do rl.UnloadShader(lit.shader)
	}
	delete(lit.byId)
	lit = {}
}

// Lit_Forget drops one image's lit texture (the image unloaded or changed).
Lit_Forget :: proc(id: u32) {
	if e, ok := lit.byId[id]; ok {
		if e.has && rl.IsWindowReady() do rl.UnloadTexture(e.tex)
		delete_key(&lit.byId, id)
	}
	lit.anyChecked = false
}

// Lit_ProjectUsesNormals: a normal map anywhere in the loaded images, or a
// node with shininess (the normal pass is needed).
Lit_ProjectUsesNormals :: proc(scene: ^Scene, rm: ^ResourceManager) -> bool {
	if scene == nil || scene.manager == nil do return false
	for n in scene.manager.nodes do if n != nil && n.enabled && Node_Shininess(n) > 0 do return true
	if rm == nil do return false
	if !lit.anyChecked {
		lit.anyChecked = true
		lit.any = false
		for t in rm.textures do if t != nil && t.page == 0 {
			if p, _ := Lit_NormalPathFor(rm, t.filePath); p != "" {
				lit.any = true
				break
			}
		}
	}
	return lit.any
}

// Lit_NormalPathFor: an image's normal map file ("" none).
Lit_NormalPathFor :: proc(rm: ^ResourceManager, imagePath: string) -> (path: string, greenDown: bool) {
	if imagePath == "" || strings.contains(imagePath, "://") do return "", false
	imp := Asset_ImportGet(rm, imagePath)
	if imp != nil {
		greenDown = imp.normalGreenDown
		if imp.normalMap == "none" do return "", false
		if imp.normalMap != "" {
			p := imp.normalMap
			if !filepath.is_abs(p) && rm.projectDir != "" do p, _ = filepath.join({rm.projectDir, p}, context.temp_allocator)
			if lit_file_exists(rm, p) do return p, greenDown
			return "", false
		}
	}
	p := lit_sibling(imagePath, NORMAL_SUFFIX)
	if p != "" && lit_file_exists(rm, p) do return p, greenDown
	return "", false
}

// Lit_SpecularPathFor: an image's specular map (<image>_s.png; "" none).
Lit_SpecularPathFor :: proc(rm: ^ResourceManager, imagePath: string) -> string {
	p := lit_sibling(imagePath, SPECULAR_SUFFIX)
	if p != "" && lit_file_exists(rm, p) do return p
	return ""
}

// lit_sibling: "dir/hero.png" -> "dir/hero_n.png".
@(private = "file")
lit_sibling :: proc(imagePath, suffix: string) -> string {
	ext := filepath.ext(imagePath)
	if ext == "" do return ""
	base := imagePath[:len(imagePath) - len(ext)]
	if strings.has_suffix(base, NORMAL_SUFFIX) || strings.has_suffix(base, SPECULAR_SUFFIX) do return "" // (a map itself)
	return strings.concatenate({base, suffix, ".png"}, context.temp_allocator)
}

@(private = "file")
lit_file_exists :: proc(rm: ^ResourceManager, p: string) -> bool {
	if os.is_file(p) do return true
	if rm != nil && rm.package_ != nil {
		if b, ok := resource_bytes(rm, p); ok {
			delete(b)
			return true
		}
	}
	return false
}

@(private = "file")
lit_load_image :: proc(rm: ^ResourceManager, p: string) -> (rl.Image, bool) {
	if os.is_file(p) {
		img := rl.LoadImage(fmt.ctprint(p))
		return img, img.data != nil
	}
	if rm != nil {
		if b, ok := resource_bytes(rm, p); ok {
			defer delete(b)
			img := rl.LoadImageFromMemory(fmt.ctprint(Image_ExtFor(b, p)), raw_data(b), i32(len(b)))
			return img, img.data != nil
		}
	}
	return {}, false
}

// Lit_BuildTexture: the lit texture of an image - its normal map's xy, its
// specular map (0 without), its own alpha.
Lit_BuildImage :: proc(diffuse, normal: rl.Image, specular: Maybe(rl.Image)) -> rl.Image {
	d := rl.ImageCopy(diffuse)
	rl.ImageFormat(&d, .UNCOMPRESSED_R8G8B8A8)
	n := rl.ImageCopy(normal)
	rl.ImageFormat(&n, .UNCOMPRESSED_R8G8B8A8)
	if n.width != d.width || n.height != d.height do rl.ImageResize(&n, d.width, d.height)
	s: rl.Image
	hasS := false
	if sp, ok := specular.?; ok {
		s = rl.ImageCopy(sp)
		rl.ImageFormat(&s, .UNCOMPRESSED_R8G8B8A8)
		if s.width != d.width || s.height != d.height do rl.ImageResize(&s, d.width, d.height)
		hasS = true
	}
	count := int(d.width * d.height)
	dp := ([^]u8)(d.data)
	np := ([^]u8)(n.data)
	sp := ([^]u8)(s.data)
	for i in 0 ..< count {
		dp[i * 4 + 0] = np[i * 4 + 0]
		dp[i * 4 + 1] = np[i * 4 + 1]
		dp[i * 4 + 2] = sp[i * 4 + 0] if hasS else 0
		// (alpha: the image's own)
	}
	rl.UnloadImage(n)
	if hasS do rl.UnloadImage(s)
	return d
}

// Lit_TextureFor: the lit texture of an image's GPU texture (has = false:
// no normal map - drawn flat).
Lit_TextureFor :: proc(rm: ^ResourceManager, tex: rl.Texture2D) -> (e: rl.Texture2D, has: bool, greenDown: bool) {
	if entry, ok := lit.byId[tex.id]; ok do return entry.tex, entry.has, entry.greenDown
	if lit.byId == nil do lit.byId = make(map[u32]Lit_Entry, allocator = Engine_HeapAllocator())
	entry: Lit_Entry
	defer lit.byId[tex.id] = entry
	if rm == nil || !rl.IsWindowReady() do return
	imagePath := ""
	for t in rm.textures do if t != nil && t.page == 0 && t.texture.id == tex.id {
		imagePath = t.filePath
		break
	}
	normalPath, gd := Lit_NormalPathFor(rm, imagePath)
	if normalPath == "" do return
	diffuse, dok := lit_load_image(rm, imagePath)
	normal, nok := lit_load_image(rm, normalPath)
	if !dok || !nok {
		if dok do rl.UnloadImage(diffuse)
		if nok do rl.UnloadImage(normal)
		return
	}
	spec: Maybe(rl.Image)
	if sp := Lit_SpecularPathFor(rm, imagePath); sp != "" {
		if s, ok := lit_load_image(rm, sp); ok do spec = s
	}
	img := Lit_BuildImage(diffuse, normal, spec)
	rl.UnloadImage(diffuse)
	rl.UnloadImage(normal)
	if s, ok := spec.?; ok do rl.UnloadImage(s)
	entry.tex = rl.LoadTextureFromImage(img)
	rl.UnloadImage(img)
	rl.SetTextureFilter(entry.tex, .POINT) // (normals aren't blended at edges)
	rl.SetTextureWrap(entry.tex, .CLAMP)
	entry.has, entry.greenDown = true, gd
	return entry.tex, true, gd
}

// Node_Shininess: a texture-drawn node's Shininess (0: matte).
Node_Shininess :: proc(n: ^Node) -> f32 {
	if n == nil do return 0
	switch n.typeId {
	case TextureNode:         return (cast(^TextureNode)n).shininess
	case AtlasSpriteNode:     return (cast(^AtlasSpriteNode)n).shininess
	case AsepriteNode:        return (cast(^AsepriteNode)n).shininess
	case AnimationPlayerNode: return (cast(^AnimationPlayerNode)n).shininess
	case FrameAnimationNode:  return (cast(^FrameAnimationNode)n).shininess
	case NineSliceNode:       return (cast(^NineSliceNode)n).shininess
	case TileMapNode:         return (cast(^TileMapNode)n).shininess
	case LdtkLevelNode:       return (cast(^LdtkLevelNode)n).shininess
	}
	return 0
}

// Lit_NodeDrawn: drawn in the normal pass (texture-drawn nodes).
Lit_NodeDrawn :: proc(n: ^Node) -> bool {
	switch n.typeId {
	case TextureNode, AtlasSpriteNode, AsepriteNode, AnimationPlayerNode, FrameAnimationNode, NineSliceNode, TileMapNode, LdtkLevelNode:
		return true
	}
	return false
}

// lit_encode: the vertex colour carrying a draw's rotation, flips and shininess.
@(private = "file")
lit_encode :: proc(rotation: f32, flipX, flipY, flat, greenDown: bool) -> rl.Color {
	r := math.to_radians(rotation)
	c, s := math.cos(r), math.sin(r)
	flags: u8 = 0
	if flipX do flags |= 1
	if flipY do flags |= 2
	if flat do flags |= 4
	if greenDown do flags |= 8
	shin := clamp(Node_Shininess(normalPassNode), 0, 1)
	return {u8((c * 0.5 + 0.5) * 255 + 0.5), u8((s * 0.5 + 0.5) * 255 + 0.5), flags, u8(shin * 255 + 0.5)}
}

@(private = "file")
lit_rm :: proc() -> ^ResourceManager {
	if n := normalPassNode; n != nil {
		if rm := Node_ResourceManager(n); rm != nil do return rm
	}
	return nil
}

// Lit_Draw: rl.DrawTexturePro, or in the normal pass the image's lit
// texture (or flat) with its rotation, flips and shininess encoded.
Lit_Draw :: proc(tex: rl.Texture2D, src, dst: rl.Rectangle, origin: [2]f32, rotation: f32, tint: rl.Color) {
	if !renderNormalPass {
		rl.DrawTexturePro(tex, src, dst, origin, rotation, tint)
		return
	}
	l, has, gd := Lit_TextureFor(lit_rm(), tex)
	col := lit_encode(rotation, src.width < 0, src.height < 0, !has, gd)
	rl.DrawTexturePro(l if has else tex, src, dst, origin, rotation, col)
}

// Lit_DrawNPatch: rl.DrawTextureNPatch through the normal pass.
Lit_DrawNPatch :: proc(tex: rl.Texture2D, info: rl.NPatchInfo, dst: rl.Rectangle, origin: [2]f32, rotation: f32, tint: rl.Color) {
	if !renderNormalPass {
		rl.DrawTextureNPatch(tex, info, dst, origin, rotation, tint)
		return
	}
	l, has, gd := Lit_TextureFor(lit_rm(), tex)
	rl.DrawTextureNPatch(l if has else tex, info, dst, origin, rotation, lit_encode(rotation, false, false, !has, gd))
}

// Lit_BeginPass / Lit_EndPass: the normal pass's state (its shader, no
// blending: the buffer holds values, not colours).
Lit_BeginPass :: proc() -> bool {
	sh, ok := Lit_Shader()
	if !ok do return false
	rl.BeginShaderMode(sh)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableColorBlend()
	renderNormalPass = true
	return true
}

Lit_EndPass :: proc() {
	rlgl.DrawRenderBatchActive()
	rlgl.EnableColorBlend()
	rl.EndShaderMode()
	renderNormalPass = false
	normalPassNode = nil
}

// Lit_ForgetAll drops every lit texture (an image's normal map or its
// settings changed; they're built again as needed).
Lit_ForgetAll :: proc() {
	if rl.IsWindowReady() do for _, e in lit.byId do if e.has do rl.UnloadTexture(e.tex)
	clear(&lit.byId)
	lit.anyChecked = false
}

// Normal_Gen_Options: Generate Normal Map (the editor) - a height field from
// the image's shape (its alpha, softened into a bevel) and / or brightness.
Normal_Gen_Options :: struct {
	strength:   f32, // how steep (1: gentle .. 10: sharp)
	softness:   int, // bevel width: blur passes over the shape (px)
	shape:      bool, // the outline rises into a bevel
	brightness: bool, // lighter is higher (painted detail)
	invert:     bool, // darker is higher
}

// Normal_Generate: a normal map (OpenGL style: green up) for an image; its
// alpha is the image's. The caller unloads it.
Normal_Generate :: proc(src: rl.Image, o: Normal_Gen_Options) -> rl.Image {
	img := rl.ImageCopy(src)
	rl.ImageFormat(&img, .UNCOMPRESSED_R8G8B8A8)
	w, h := int(img.width), int(img.height)
	px := ([^]u8)(img.data)
	height := make([]f32, w * h, context.temp_allocator)
	shape := make([]f32, w * h, context.temp_allocator)
	for i in 0 ..< w * h do shape[i] = f32(px[i * 4 + 3]) / 255
	// The bevel: the alpha blurred (box blur passes), kept inside the shape.
	if o.shape && o.softness > 0 {
		tmp := make([]f32, w * h, context.temp_allocator)
		radius := max(o.softness / 3, 1)
		for _ in 0 ..< 3 {
			for y in 0 ..< h do for x in 0 ..< w {
				sum: f32 = 0
				for k in -radius ..= radius do sum += shape[y * w + clamp(x + k, 0, w - 1)]
				tmp[y * w + x] = sum / f32(radius * 2 + 1)
			}
			for y in 0 ..< h do for x in 0 ..< w {
				sum: f32 = 0
				for k in -radius ..= radius do sum += tmp[clamp(y + k, 0, h - 1) * w + x]
				shape[y * w + x] = sum / f32(radius * 2 + 1)
			}
		}
	}
	for i in 0 ..< w * h {
		v: f32 = 0
		if o.shape do v += shape[i]
		if o.brightness {
			l := (0.299 * f32(px[i * 4]) + 0.587 * f32(px[i * 4 + 1]) + 0.114 * f32(px[i * 4 + 2])) / 255
			v += (1 - l) if o.invert else l
		}
		height[i] = v
	}
	at :: proc(hf: []f32, w, h, x, y: int) -> f32 {return hf[clamp(y, 0, h - 1) * w + clamp(x, 0, w - 1)]}
	s := max(o.strength, 0.01)
	for y in 0 ..< h do for x in 0 ..< w {
		// Sobel slopes (image y down).
		dx := (at(height, w, h, x + 1, y - 1) + 2 * at(height, w, h, x + 1, y) + at(height, w, h, x + 1, y + 1)) - (at(height, w, h, x - 1, y - 1) + 2 * at(height, w, h, x - 1, y) + at(height, w, h, x - 1, y + 1))
		dy := (at(height, w, h, x - 1, y + 1) + 2 * at(height, w, h, x, y + 1) + at(height, w, h, x + 1, y + 1)) - (at(height, w, h, x - 1, y - 1) + 2 * at(height, w, h, x, y - 1) + at(height, w, h, x + 1, y - 1))
		n := [3]f32{-dx * s, -dy * s, 1}
		l := math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z)
		n /= l
		i := (y * w + x) * 4
		px[i + 0] = u8(clamp((n.x * 0.5 + 0.5) * 255, 0, 255))
		px[i + 1] = u8(clamp((-n.y * 0.5 + 0.5) * 255, 0, 255)) // (green up)
		px[i + 2] = u8(clamp((n.z * 0.5 + 0.5) * 255, 0, 255))
		// (alpha: the image's)
	}
	return img
}
