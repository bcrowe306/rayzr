package engine

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// Vector filters (Phase 14 V.11): Flash's per-instance filters - drop
// shadow, glow, outline, blur and colour adjustment (saturation, contrast,
// hue) - as shader passes.
//
// A Vector Shape with filters is drawn through a texture: before the frame
// draws (Vector_FiltersPrepare, beside the tile cache's prepare pass - render
// textures can't nest inside the frame's), its mesh is drawn at screen
// resolution into a premultiplied texture with room round it, blurred /
// tinted / adjusted into the node's own texture, and that is drawn as one
// rotated quad. The texture is remade only when something it shows changes
// (the art, the zoom, the node's scale, a filter setting, the colour
// effects): an idle filtered character costs one textured quad.
// ============================================================================

VECTOR_FILTER_MAX :: 2048 // the largest filter texture (px a side)

Vector_Filter_State :: struct {
	rt:     rl.RenderTexture2D, // the filtered drawing (premultiplied)
	size:   [2]i32,             // what's used of rt
	origin: [2]f32,             // the node-space point at the texture's top left
	scale:  f32,                // texture px per node unit
	key:    Vector_Filter_Key,
	valid:  bool,
}

Vector_Filter_Key :: struct {
	cache:                  ^Vector_Cache,
	tessellations:          int,
	bucket, scale:          f32,
	offset:                 [2]f32,
	tint, colorAdd:         rl.Color,
	brightness:             f32,
	shadowColor, glowColor: rl.Color,
	outlineColor:           rl.Color,
	shadow:                 [3]f32, // offset, blur
	glow:                   [2]f32,
	outlineWidth, blur:     f32,
	adjust:                 [3]f32, // saturation, contrast, hue
}

@(private = "file")
vfilt: struct {
	ready:                      bool,
	blur, tint, dilate, adjust: rl.Shader,
	blurDir, blurRadius:        i32,
	tintColor, dilateRadius:    i32,
	dilateStep, dilateTint:     i32,
	adjustParams:               i32,
	scratch:                    [3]rl.RenderTexture2D,
	prepared:                   int, // textures made (tests, the profiler)
}

// A separable Gaussian blur along dir (texels), radius in px (17 taps,
// spread for bigger radii).
@(private = "file")
BLUR_FS :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
uniform vec2 dir;
uniform float radius;
out vec4 finalColor;
void main() {
    if (radius < 0.5) { finalColor = texture(texture0, fragTexCoord); return; }
    float sigma = radius * 0.5;
    float step = max(radius / 8.0, 1.0);
    vec4 sum = vec4(0.0);
    float wsum = 0.0;
    for (int i = -8; i <= 8; i++) {
        float x = float(i) * step;
        float w = exp(-0.5 * x * x / (sigma * sigma));
        sum += texture(texture0, fragTexCoord + dir * x) * w;
        wsum += w;
    }
    finalColor = sum / wsum;
}
`

// The texture's coverage as a colour (premultiplied): shadows and glows.
@(private = "file")
TINT_FS :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
uniform vec4 tint; // rgb, strength * alpha
out vec4 finalColor;
void main() {
    float a = clamp(texture(texture0, fragTexCoord).a * tint.a, 0.0, 1.0);
    finalColor = vec4(tint.rgb * a, a);
}
`

// Coverage grown by radius px (the most coverage in a ring of samples): an
// outline round the whole drawing.
@(private = "file")
DILATE_FS :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
uniform vec4 tint;
uniform float radius;
uniform vec2 texel;
out vec4 finalColor;
void main() {
    float a = texture(texture0, fragTexCoord).a;
    for (int r = 1; r <= 3; r++) {
        float d = radius * float(r) / 3.0;
        for (int i = 0; i < 16; i++) {
            float ang = float(i) * 0.39269908;
            a = max(a, texture(texture0, fragTexCoord + vec2(cos(ang), sin(ang)) * d * texel).a);
        }
    }
    a *= tint.a;
    finalColor = vec4(tint.rgb * a, a);
}
`

// Saturation / contrast / hue on premultiplied colour.
@(private = "file")
ADJUST_FS :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
uniform vec3 params; // saturation, contrast, hue (radians)
out vec4 finalColor;
void main() {
    vec4 c = texture(texture0, fragTexCoord);
    if (c.a <= 0.0) { finalColor = vec4(0.0); return; }
    vec3 rgb = c.rgb / c.a;
    // Hue: rotate round the grey axis.
    float co = cos(params.z), si = sin(params.z);
    vec3 k = vec3(0.57735);
    rgb = rgb * co + cross(k, rgb) * si + k * dot(k, rgb) * (1.0 - co);
    float grey = dot(rgb, vec3(0.299, 0.587, 0.114));
    rgb = mix(vec3(grey), rgb, params.x);
    rgb = (rgb - 0.5) * params.y + 0.5;
    rgb = clamp(rgb, 0.0, 1.0);
    finalColor = vec4(rgb * c.a, c.a);
}
`

@(private = "file")
vfilt_init :: proc() -> bool {
	if vfilt.ready do return true
	if !rl.IsWindowReady() do return false
	vfilt.blur = rl.LoadShaderFromMemory(nil, Shader_Port(BLUR_FS))
	vfilt.tint = rl.LoadShaderFromMemory(nil, Shader_Port(TINT_FS))
	vfilt.dilate = rl.LoadShaderFromMemory(nil, Shader_Port(DILATE_FS))
	vfilt.adjust = rl.LoadShaderFromMemory(nil, Shader_Port(ADJUST_FS))
	vfilt.blurDir = rl.GetShaderLocation(vfilt.blur, "dir")
	vfilt.blurRadius = rl.GetShaderLocation(vfilt.blur, "radius")
	vfilt.tintColor = rl.GetShaderLocation(vfilt.tint, "tint")
	vfilt.dilateRadius = rl.GetShaderLocation(vfilt.dilate, "radius")
	vfilt.dilateStep = rl.GetShaderLocation(vfilt.dilate, "texel")
	vfilt.dilateTint = rl.GetShaderLocation(vfilt.dilate, "tint")
	vfilt.adjustParams = rl.GetShaderLocation(vfilt.adjust, "params")
	vfilt.ready = true
	return true
}

// Vector_FiltersShutdown frees the shaders and scratch textures.
Vector_FiltersShutdown :: proc() {
	if !vfilt.ready do return
	rl.UnloadShader(vfilt.blur)
	rl.UnloadShader(vfilt.tint)
	rl.UnloadShader(vfilt.dilate)
	rl.UnloadShader(vfilt.adjust)
	for s in vfilt.scratch do if s.id != 0 do rl.UnloadRenderTexture(s)
	vfilt = {}
}

// Vector_FiltersPrepared: how many filter textures were made (tests).
Vector_FiltersPrepared :: proc() -> int {return vfilt.prepared}

// Vector_FiltersActive: whether the node draws through filters.
Vector_FiltersActive :: proc(v: ^VectorShapeNode) -> bool {
	if VectorShapeNode_Deformed(v) do return false // (bent art draws as a mesh: only the colour adjustment applies, in its shader - #389)
	return v.shadowColor.a > 0 || v.glowColor.a > 0 || v.outlineColor.a > 0 || v.blur > 0 || v.saturation != 1 || v.contrast != 1 || v.hue != 0
}

// Vector_FilterRelease frees a node's filter texture.
Vector_FilterRelease :: proc(v: ^VectorShapeNode) {
	if v.filter.rt.id != 0 do rl.UnloadRenderTexture(v.filter.rt)
	v.filter = {}
}

// Vector_FiltersPrepare makes the filter textures of a scene's filtered
// Vector Shapes that changed - before the frame draws (no render texture
// bound). zoom: the camera's (screen px per world unit).
Vector_FiltersPrepare :: proc(scene: ^Scene, zoom: f32) {
	if scene == nil || scene.manager == nil || !rl.IsWindowReady() do return
	any := false
	for n in scene.manager.nodes {
		if n == nil || !n.enabled || n.typeId != VectorShapeNode || !Node_VisibleInTree(n) do continue
		v := cast(^VectorShapeNode)n
		if !Vector_FiltersActive(v) {
			if v.filter.rt.id != 0 do Vector_FilterRelease(v)
			continue
		}
		if !vfilt_init() do return
		if vector_filter_prepare(v, zoom) do any = true
	}
	if any do Render_RestoreFrameTarget() // post effects: back to the frame's target
}

// vector_filter_pad: the room the filters need round the drawing (px).
@(private = "file")
vector_filter_pad :: proc(v: ^VectorShapeNode) -> f32 {
	pad: f32 = 2
	if v.shadowColor.a > 0 do pad = max(pad, max(abs(v.shadowOffset.x), abs(v.shadowOffset.y)) + v.shadowBlur * 1.5)
	if v.glowColor.a > 0 do pad = max(pad, v.glowSize * 1.5)
	if v.outlineColor.a > 0 do pad = max(pad, v.outlineWidth + 2)
	pad = max(pad, v.blur * 1.5)
	return math.ceil(pad)
}

@(private = "file")
scratch_rt :: proc(i: int, w, h: i32) -> ^rl.RenderTexture2D {
	s := &vfilt.scratch[i]
	if s.id == 0 || s.texture.width < w || s.texture.height < h {
		nw, nh := max(w, s.texture.width), max(h, s.texture.height)
		if s.id != 0 do rl.UnloadRenderTexture(s^)
		s^ = rl.LoadRenderTexture(nw, nh)
		rl.SetTextureFilter(s.texture, .BILINEAR)
	}
	return s
}

// src_rect: the w x h drawn at the top left of a render texture, upright.
@(private = "file")
src_rect :: proc(rt: ^rl.RenderTexture2D, w, h: i32) -> rl.Rectangle {
	return {0, f32(rt.texture.height - h), f32(w), -f32(h)}
}

// pass: draws src's w x h into dst (cleared first unless keep) with a shader.
@(private = "file")
pass :: proc(src, dst: ^rl.RenderTexture2D, w, h: i32, shader: rl.Shader, keep := false, at: [2]f32 = {}) {
	rl.BeginTextureMode(dst^)
	if !keep do rl.ClearBackground({0, 0, 0, 0})
	rlgl.SetBlendFactors(rlgl.ONE, rlgl.ONE_MINUS_SRC_ALPHA, rlgl.FUNC_ADD) // (premultiplied over)
	rl.BeginBlendMode(.CUSTOM)
	if shader.id != 0 do rl.BeginShaderMode(shader)
	rl.DrawTextureRec(src.texture, src_rect(src, w, h), at, rl.WHITE)
	if shader.id != 0 do rl.EndShaderMode()
	rl.EndBlendMode()
	rl.EndTextureMode()
}

@(private = "file")
blur_into :: proc(src, tmp, dst: ^rl.RenderTexture2D, w, h: i32, radius: f32) {
	r := radius
	rl.SetShaderValue(vfilt.blur, vfilt.blurRadius, &r, .FLOAT)
	d := [2]f32{1 / f32(src.texture.width), 0}
	rl.SetShaderValue(vfilt.blur, vfilt.blurDir, &d, .VEC2)
	pass(src, tmp, w, h, vfilt.blur)
	d = {0, 1 / f32(tmp.texture.height)}
	rl.SetShaderValue(vfilt.blur, vfilt.blurDir, &d, .VEC2)
	pass(tmp, dst, w, h, vfilt.blur)
}

@(private = "file")
color4 :: proc(c: rl.Color, strength: f32 = 1) -> [4]f32 {
	return {f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, f32(c.a) / 255 * strength}
}

// vector_filter_prepare remakes one node's texture when out of date.
@(private = "file")
vector_filter_prepare :: proc(v: ^VectorShapeNode, zoom: f32) -> bool {
	scale := max(abs(v.globalScale.x), abs(v.globalScale.y), 1e-3) * max(zoom, 1e-3)
	cache, offset, ok := VectorShapeNode_Mesh(v, 1 / scale)
	if !ok || len(cache.mesh.idx) == 0 {
		v.filter.valid = false
		return false
	}
	key := Vector_Filter_Key{
		cache = cache, tessellations = cache.stats.tessellations, bucket = cache.bucket, scale = scale, offset = offset,
		tint = v.tint, colorAdd = v.colorAdd, brightness = v.brightness,
		shadowColor = v.shadowColor, glowColor = v.glowColor, outlineColor = v.outlineColor,
		shadow = {v.shadowOffset.x, v.shadowOffset.y, v.shadowBlur}, glow = {v.glowSize, v.glowStrength},
		outlineWidth = v.outlineWidth, blur = v.blur, adjust = {v.saturation, v.contrast, v.hue},
	}
	if v.filter.valid && key == v.filter.key do return false
	b := cache.mesh.bounds
	b = {b[0] + offset.x, b[1] + offset.y, b[2] + offset.x, b[3] + offset.y}
	pad := vector_filter_pad(v)
	s := scale
	size := [2]f32{(b[2] - b[0]) * s + 2 * pad, (b[3] - b[1]) * s + 2 * pad}
	if m := max(size.x, size.y); m > VECTOR_FILTER_MAX {
		// (Too big: a coarser texture.)
		s *= (VECTOR_FILTER_MAX - 2 * pad) / max(m - 2 * pad, 1)
		size = {(b[2] - b[0]) * s + 2 * pad, (b[3] - b[1]) * s + 2 * pad}
	}
	w, h := i32(math.ceil(size.x)), i32(math.ceil(size.y))
	if w <= 0 || h <= 0 do return false
	f := &v.filter
	if f.rt.id == 0 || f.rt.texture.width != w || f.rt.texture.height != h {
		if f.rt.id != 0 do rl.UnloadRenderTexture(f.rt)
		f.rt = rl.LoadRenderTexture(w, h)
		rl.SetTextureFilter(f.rt.texture, .BILINEAR)
	}
	art := scratch_rt(0, w, h)
	tmp := scratch_rt(1, w, h)
	aux := scratch_rt(2, w, h)
	// The drawing, premultiplied, at the top left of the art texture.
	rl.BeginTextureMode(art^)
	rl.ClearBackground({0, 0, 0, 0})
	rlgl.SetBlendFactorsSeparate(rlgl.SRC_ALPHA, rlgl.ONE_MINUS_SRC_ALPHA, rlgl.ONE, rlgl.ONE_MINUS_SRC_ALPHA, rlgl.FUNC_ADD, rlgl.FUNC_ADD)
	rl.BeginBlendMode(.CUSTOM_SEPARATE)
	mul, add := vector_color_effect(v)
	Vector_Cache_Draw(cache, {pad - b[0] * s, pad - b[1] * s} + offset * s, 0, {s, s}, mul, {}, add)
	rl.EndBlendMode()
	rl.EndTextureMode()
	if v.blur > 0 do blur_into(art, tmp, art, w, h, v.blur)
	// The node's texture: shadow, glow, outline, then the drawing.
	rl.BeginTextureMode(f.rt)
	rl.ClearBackground({0, 0, 0, 0})
	rl.EndTextureMode()
	if v.shadowColor.a > 0 {
		blur_into(art, tmp, aux, w, h, v.shadowBlur)
		c := color4(v.shadowColor)
		rl.SetShaderValue(vfilt.tint, vfilt.tintColor, &c, .VEC4)
		pass(aux, &f.rt, w, h, vfilt.tint, keep = true, at = v.shadowOffset)
	}
	if v.glowColor.a > 0 {
		blur_into(art, tmp, aux, w, h, v.glowSize)
		c := color4(v.glowColor, v.glowStrength)
		rl.SetShaderValue(vfilt.tint, vfilt.tintColor, &c, .VEC4)
		pass(aux, &f.rt, w, h, vfilt.tint, keep = true)
	}
	if v.outlineColor.a > 0 && v.outlineWidth > 0 {
		c := color4(v.outlineColor)
		r := v.outlineWidth
		texel := [2]f32{1 / f32(art.texture.width), 1 / f32(art.texture.height)}
		rl.SetShaderValue(vfilt.dilate, vfilt.dilateTint, &c, .VEC4)
		rl.SetShaderValue(vfilt.dilate, vfilt.dilateRadius, &r, .FLOAT)
		rl.SetShaderValue(vfilt.dilate, vfilt.dilateStep, &texel, .VEC2)
		pass(art, &f.rt, w, h, vfilt.dilate, keep = true)
	}
	adjust := v.saturation != 1 || v.contrast != 1 || v.hue != 0
	if adjust {
		p := [3]f32{v.saturation, v.contrast, v.hue * math.RAD_PER_DEG}
		rl.SetShaderValue(vfilt.adjust, vfilt.adjustParams, &p, .VEC3)
	}
	pass(art, &f.rt, w, h, vfilt.adjust if adjust else {}, keep = true)
	f.size = {w, h}
	f.scale = s
	f.origin = {b[0] - pad / s, b[1] - pad / s}
	f.key = key
	f.valid = true
	vfilt.prepared += 1
	return true
}

// Vector_FilterDraw draws a node's filter texture (false: none ready - the
// caller draws the plain mesh).
Vector_FilterDraw :: proc(v: ^VectorShapeNode) -> bool {
	f := &v.filter
	if !f.valid || f.rt.id == 0 do return false
	w, h := f32(f.size.x), f32(f.size.y)
	gs := v.globalScale
	src := rl.Rectangle{0, 0, w, -h}
	if gs.x < 0 do src.width = -src.width
	if gs.y < 0 do src.height = -src.height
	k := [2]f32{abs(gs.x), abs(gs.y)} / f.scale
	org := [2]f32{-f.origin.x * f.scale, -f.origin.y * f.scale} * k
	if gs.x < 0 do org.x = w * k.x - org.x
	if gs.y < 0 do org.y = h * k.y - org.y
	rl.BeginBlendMode(.ALPHA_PREMULTIPLY)
	rl.DrawTexturePro(f.rt.texture, src, {v.globalPosition.x, v.globalPosition.y, w * k.x, h * k.y}, org, v.globalRotation, rl.WHITE)
	rl.EndBlendMode()
	return true
}
