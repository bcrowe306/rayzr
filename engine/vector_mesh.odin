package engine

import "core:math"
import os "osx"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// Cached vector meshes and drawing them (vector_tess.odin makes them).
//
// A Vector_Cache holds one tessellation of some shapes for a scale bucket
// (powers of two of the screen-pixel size): moving, rotating and scaling
// within the bucket only changes the transform; zooming past it
// re-tessellates (so curves stay smooth and fringes one pixel wide).
//
// Two ways to draw (Vector_Draw_Mode; RAYZR_VECTOR_MODE=immediate|gpu
// overrides it for benchmarks):
//   .GPU        the mesh is uploaded once (vertex buffers, split at 65535
//               vertices) and drawn with a matrix: no per-frame vertex work
//   .Immediate  the triangles go through raylib's batch every frame
//               (rlgl: transformed on the CPU)
// Both work wherever raylib draws: the game, the editor's viewport, render
// textures and the web (WebGL 2).
// ============================================================================

Vector_Draw_Mode :: enum u8 {
	GPU,
	Immediate,
}

vectorDrawMode: Vector_Draw_Mode = .GPU

@(private = "file")
vector_mode_checked: bool

Vector_DrawModeNow :: proc() -> Vector_Draw_Mode {
	if !vector_mode_checked {
		vector_mode_checked = true
		switch os.get_env("RAYZR_VECTOR_MODE", context.temp_allocator) {
		case "immediate": vectorDrawMode = .Immediate
		case "gpu": vectorDrawMode = .GPU
		}
	}
	return vectorDrawMode
}

Vector_Cache :: struct {
	mesh:     Vector_Mesh,
	gpu:      [dynamic]rl.Mesh,
	gradTex:  rl.Texture2D, // the mesh's gradient rows (none: solid only)
	bucket:   f32, // the screen-pixel size it was tessellated for (0: never)
	dirty:    bool,
	uploaded: bool,
	stats:    struct {tessellations: int},
	// Skinning (vector_skin.odin): per-vertex bones and weights uploaded with
	// the mesh (not owned; cleared when it's re-tessellated).
	skinIds:      [][4]u8,
	skinWeights:  [][4]f32,
	skinUploaded: bool,
}

// The shaders: [plain, with gradients, plain + colour adjustment, with
// gradients + colour adjustment] (vector_shader_variant).
@(private = "file")
vflat: [4]struct {
	material:    rl.Material,
	ready:       bool,
	add, adjust: i32,
}

// The deforming variant (skin + warp; vector_skin.odin), the same four.
@(private = "file")
vskin: [4]struct {
	material:                    rl.Material,
	ready:                       bool,
	add, bones, skinOn, adjust:  i32,
	warpBox, warpA, warpB:       i32,
}

// VECTOR_NO_ADJUST: no colour adjustment (saturation, contrast, hue in
// degrees): Vector_Cache_Draw's default.
VECTOR_NO_ADJUST :: [3]f32{1, 1, 0}

// vector_shader_variant: the shader slot for a mesh and an adjustment, and
// its fragment shader's source (a #define picks the adjusting code; meshes
// without one keep the cheaper shaders).
@(private = "file")
vector_shader_variant :: proc(c: ^Vector_Cache, adjust: [3]f32) -> (slot: int, fs: cstring) {
	solid := Vector_Cache_Solid(c)
	slot = 0 if solid else 1
	if adjust != VECTOR_NO_ADJUST do slot += 2
	switch slot {
	case 0: fs = VECTOR_SOLID_FS
	case 1: fs = VECTOR_FS
	case 2: fs = VECTOR_SOLID_FS_ADJUST
	case: fs = VECTOR_FS_ADJUST
	}
	return
}

// vector_set_adjust uploads an adjustment (hue in degrees) to a shader.
@(private = "file")
vector_set_adjust :: proc(sh: rl.Shader, loc: i32, adjust: [3]f32) {
	if loc < 0 do return
	p := [3]f32{adjust[0], adjust[1], adjust[2] * math.RAD_PER_DEG}
	rl.SetShaderValue(sh, rl.ShaderLocationIndex(loc), &p, .VEC3)
}

// Vector_AdjustColor: a straight-alpha colour (0..1) through a colour
// adjustment - the shaders' maths (and vector_filters.odin's ADJUST_FS) for
// the immediate path: hue rotated round the grey axis, then saturation
// (0: grey), then contrast round mid grey.
Vector_AdjustColor :: proc(rgb: [3]f32, adjust: [3]f32) -> [3]f32 {
	h := adjust[2] * math.RAD_PER_DEG
	co, si := math.cos(h), math.sin(h)
	k := [3]f32{0.57735, 0.57735, 0.57735}
	kxr := [3]f32{k.y * rgb.z - k.z * rgb.y, k.z * rgb.x - k.x * rgb.z, k.x * rgb.y - k.y * rgb.x}
	kd := k.x * rgb.x + k.y * rgb.y + k.z * rgb.z
	c := rgb * co + kxr * si + k * kd * (1 - co)
	grey := c.x * 0.299 + c.y * 0.587 + c.z * 0.114
	c = grey + (c - grey) * adjust[0]
	c = (c - 0.5) * adjust[1] + 0.5
	return {clamp(c.x, 0, 1), clamp(c.y, 0, 1), clamp(c.z, 0, 1)}
}

// The vector shader: solid vertices use their colour; gradient vertices
// (mode > 0) look their colour up in the mesh's gradient texture at the
// position their gradient coordinates give (linear: x; radial: the length),
// after the spread (pad / reflect / repeat); alpha carries the edge fringe
// and opacity either way.
@(private = "file")
VECTOR_VS :: `#version 330
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec2 vertexTexCoord2;
in vec4 vertexColor;
uniform mat4 mvp;
out vec2 fragGrad;
out vec2 fragMode;
out vec4 fragColor;
void main() {
    fragGrad = vertexTexCoord;
    fragMode = vertexTexCoord2;
    fragColor = vertexColor;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`

// The vertex shader that bends: a four-corner warp over a box (bilinear),
// then up to four bones per vertex (ids packed in the normal: id0 + id1 *
// 256, id2 + id3 * 256; weights in the tangent), each bone two vec4s (a b c
// d, tx ty).
@(private = "file")
VECTOR_SKIN_VS :: `#version 330
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec2 vertexTexCoord2;
in vec4 vertexColor;
in vec3 vertexNormal;
in vec4 vertexTangent;
uniform mat4 mvp;
uniform vec4 bones[128];
uniform float skinOn;
uniform vec4 warpBox;
uniform vec4 warpA;
uniform vec4 warpB;
out vec2 fragGrad;
out vec2 fragMode;
out vec4 fragColor;
vec2 bone(float i, vec2 p) {
    int k = int(i + 0.5) * 2;
    vec4 m = bones[k];
    vec4 t = bones[k + 1];
    return vec2(m.x * p.x + m.y * p.y + t.x, m.z * p.x + m.w * p.y + t.y);
}
void main() {
    fragGrad = vertexTexCoord;
    fragMode = vertexTexCoord2;
    fragColor = vertexColor;
    vec2 p = vertexPosition.xy;
    if (warpBox.z > 0.0 && warpBox.w > 0.0) {
        vec2 u = (p - warpBox.xy) / warpBox.zw;
        vec2 top = mix(warpA.xy, warpA.zw, u.x);
        vec2 bot = mix(warpB.xy, warpB.zw, u.x);
        p += mix(top, bot, u.y);
    }
    if (skinOn > 0.5) {
        float i1 = floor(vertexNormal.x / 256.0);
        float i0 = vertexNormal.x - i1 * 256.0;
        float i3 = floor(vertexNormal.y / 256.0);
        float i2 = vertexNormal.y - i3 * 256.0;
        vec4 w = vertexTangent;
        vec2 q = bone(i0, p) * w.x;
        if (w.y > 0.0) q += bone(i1, p) * w.y;
        if (w.z > 0.0) q += bone(i2, p) * w.z;
        if (w.w > 0.0) q += bone(i3, p) * w.w;
        p = q;
    }
    gl_Position = mvp * vec4(p, 0.0, 1.0);
}
`

// The colour adjustment (a Vector Shape's saturation / contrast / hue, as
// vector_filters.odin's ADJUST_FS) in the adjusting variants: for bent
// shapes, which draw as a mesh (no filter texture: #389).
@(private = "file")
VECTOR_ADJUST_GLSL :: `
#ifdef ADJUST
uniform vec3 adjust; // saturation, contrast, hue (radians)
vec3 vector_adjust(vec3 rgb) {
    float co = cos(adjust.z), si = sin(adjust.z);
    vec3 k = vec3(0.57735);
    rgb = rgb * co + cross(k, rgb) * si + k * dot(k, rgb) * (1.0 - co);
    float grey = dot(rgb, vec3(0.299, 0.587, 0.114));
    rgb = mix(vec3(grey), rgb, adjust.x);
    rgb = (rgb - 0.5) * adjust.y + 0.5;
    return clamp(rgb, 0.0, 1.0);
}
#else
vec3 vector_adjust(vec3 rgb) { return rgb; }
#endif
`

@(private = "file")
VECTOR_FS :: "#version 330\n" + VECTOR_FS_BODY
@(private = "file")
VECTOR_FS_ADJUST :: "#version 330\n#define ADJUST 1\n" + VECTOR_FS_BODY

@(private = "file")
VECTOR_FS_BODY :: VECTOR_ADJUST_GLSL + `
in vec2 fragGrad;
in vec2 fragMode;
in vec4 fragColor;
uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform vec4 colAdd;
out vec4 finalColor;
void main() {
    vec4 c = fragColor;
    if (fragMode.y > 0.5) {
        float mode = floor(fragMode.y + 0.5) - 1.0;
        float kind = floor(mode / 4.0);
        float spread = mode - kind * 4.0;
        float t = kind < 0.5 ? fragGrad.x : length(fragGrad);
        if (spread < 0.5) t = clamp(t, 0.0, 1.0);
        else if (spread < 1.5) t = 1.0 - abs(mod(t, 2.0) - 1.0);
        else t = fract(t);
        vec4 g = texture(texture0, vec2((t * 255.0 + 0.5) / 256.0, fragMode.x));
        c = vec4(g.rgb, g.a * fragColor.a);
    }
    finalColor = c * colDiffuse;
    finalColor.rgb = vector_adjust(min(finalColor.rgb + colAdd.rgb, vec3(1.0))); // (straight alpha)
}
`

// The plain variant: meshes without gradient vertices (most art; linear
// two-stop gradients are baked into vertex colours: vector_tess.odin) skip
// the texture look-up and spread maths - the same pixels, cheaper per pixel
// (software GL runs every branch of a shader for every pixel, #331).
@(private = "file")
VECTOR_SOLID_FS :: "#version 330\n" + VECTOR_SOLID_FS_BODY
@(private = "file")
VECTOR_SOLID_FS_ADJUST :: "#version 330\n#define ADJUST 1\n" + VECTOR_SOLID_FS_BODY

@(private = "file")
VECTOR_SOLID_FS_BODY :: VECTOR_ADJUST_GLSL + `
in vec2 fragGrad;
in vec2 fragMode;
in vec4 fragColor;
uniform vec4 colDiffuse;
uniform vec4 colAdd;
out vec4 finalColor;
void main() {
    finalColor = fragColor * colDiffuse;
    finalColor.rgb = vector_adjust(min(finalColor.rgb + colAdd.rgb, vec3(1.0))); // (straight alpha)
}
`

// Vector_Cache_Solid: whether a cache's mesh has no gradient vertices (it
// draws through the plain shader).
Vector_Cache_Solid :: proc(c: ^Vector_Cache) -> bool {
	return len(c.mesh.gradients) == 0
}

// Vector_Cache_Destroy frees the mesh and its GPU buffers.
Vector_Cache_Destroy :: proc(c: ^Vector_Cache) {
	vector_cache_unload(c)
	delete(c.gpu)
	Vector_Mesh_Destroy(&c.mesh)
	c^ = {}
}

@(private = "file")
vector_cache_unload :: proc(c: ^Vector_Cache) {
	if c.gradTex.id != 0 && rl.IsWindowReady() do rl.UnloadTexture(c.gradTex)
	c.gradTex = {}
	for &m in c.gpu {
		if rl.IsWindowReady() do rl.UnloadMesh(m)
		else {
			// (No GL context: only the CPU copies.)
			free_mesh_cpu(&m)
		}
	}
	clear(&c.gpu)
	c.uploaded = false
}

@(private = "file")
free_mesh_cpu :: proc(m: ^rl.Mesh) {
	rl.MemFree(m.vertices)
	rl.MemFree(m.colors)
	rl.MemFree(m.texcoords)
	rl.MemFree(m.texcoords2)
	rl.MemFree(m.indices)
	rl.MemFree(m.normals)
	rl.MemFree(m.tangents)
	m^ = {}
}

// Vector_PixelBucket: the screen-pixel size rounded to a power of two.
Vector_PixelBucket :: proc(pixel: f32) -> f32 {
	return math.pow(2, math.round(math.log2(max(pixel, 1e-4))))
}

// Vector_Cache_Ensure (re)tessellates when the shapes changed (dirty) or the
// drawing scale left the bucket; then uploads for GPU drawing.
Vector_Cache_Ensure :: proc(c: ^Vector_Cache, t: ^Vector_Tess, shapes: []Vector_Shape, pixel: f32) {
	b := Vector_PixelBucket(pixel)
	if c.dirty || c.bucket != b {
		Vector_Tessellate(t, shapes, b, &c.mesh)
		c.bucket = b
		c.dirty = false
		c.stats.tessellations += 1
		c.skinIds, c.skinWeights = nil, nil // (for the old vertices)
		vector_cache_unload(c)
	}
	if Vector_DrawModeNow() == .GPU && !c.uploaded && rl.IsWindowReady() do vector_cache_upload(c)
}

// vector_cache_upload: the mesh as raylib meshes of at most 65535 vertices
// (16-bit indices). Triangles never straddle chunks: a chunk takes whole
// triangles and copies the vertices they use.
@(private = "file")
vector_cache_upload :: proc(c: ^Vector_Cache) {
	m := &c.mesh
	c.skinUploaded = false
	if len(m.idx) == 0 {c.uploaded = true; return}
	skinned := len(c.skinIds) == len(m.verts) && len(c.skinWeights) == len(m.verts)
	// The gradient rows as a texture (rows = gradients; sampled at row centres).
	rows := len(m.gradients)
	if rows > 0 {
		img := rl.Image{data = raw_data(m.gradients), width = 256, height = i32(rows), mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
		c.gradTex = rl.LoadTextureFromImage(img)
		rl.SetTextureFilter(c.gradTex, .BILINEAR)
		rl.SetTextureWrap(c.gradTex, .CLAMP)
	}
	remap := make([]i32, len(m.verts), context.temp_allocator)
	tri := 0
	ntri := len(m.idx) / 3
	for tri < ntri {
		for &r in remap do r = -1
		verts := make([dynamic][3]f32, context.temp_allocator)
		cols := make([dynamic][4]u8, context.temp_allocator)
		gc := make([dynamic][2]f32, context.temp_allocator)
		gi := make([dynamic][2]f32, context.temp_allocator)
		idx := make([dynamic]u16, context.temp_allocator)
		normals := make([dynamic][3]f32, context.temp_allocator)
		tangents := make([dynamic][4]f32, context.temp_allocator)
		for tri < ntri {
			if len(verts) + 3 > 65535 do break
			for k in 0 ..< 3 {
				v := m.idx[tri * 3 + k]
				if remap[v] < 0 {
					remap[v] = i32(len(verts))
					append(&verts, [3]f32{m.verts[v].x, m.verts[v].y, 0})
					append(&cols, m.cols[v])
					append(&gc, m.gc[v])
					// (The row index as a texture coordinate at the row's centre.)
					g := m.gi[v]
					if g.y > 0 do g.x = (g.x + 0.5) / f32(max(rows, 1))
					append(&gi, g)
					if skinned {
						ids := c.skinIds[v]
						append(&normals, [3]f32{f32(ids[0]) + f32(ids[1]) * 256, f32(ids[2]) + f32(ids[3]) * 256, 0})
						append(&tangents, c.skinWeights[v])
					}
				}
				append(&idx, u16(remap[v]))
			}
			tri += 1
		}
		mesh: rl.Mesh
		mesh.vertexCount = i32(len(verts))
		mesh.triangleCount = i32(len(idx) / 3)
		mesh.vertices = cast([^]f32)rl.MemAlloc(u32(len(verts) * 12))
		mesh.colors = cast([^]u8)rl.MemAlloc(u32(len(cols) * 4))
		mesh.indices = cast([^]u16)rl.MemAlloc(u32(len(idx) * 2))
		mesh.texcoords = cast([^]f32)rl.MemAlloc(u32(len(gc) * 8))
		mesh.texcoords2 = cast([^]f32)rl.MemAlloc(u32(len(gi) * 8))
		copy((cast([^][3]f32)mesh.vertices)[:len(verts)], verts[:])
		copy((cast([^][4]u8)mesh.colors)[:len(cols)], cols[:])
		copy((cast([^][2]f32)mesh.texcoords)[:len(gc)], gc[:])
		copy((cast([^][2]f32)mesh.texcoords2)[:len(gi)], gi[:])
		copy(mesh.indices[:len(idx)], idx[:])
		if skinned {
			mesh.normals = cast([^]f32)rl.MemAlloc(u32(len(normals) * 12))
			mesh.tangents = cast([^]f32)rl.MemAlloc(u32(len(tangents) * 16))
			copy((cast([^][3]f32)mesh.normals)[:len(normals)], normals[:])
			copy((cast([^][4]f32)mesh.tangents)[:len(tangents)], tangents[:])
		}
		rl.UploadMesh(&mesh, false)
		append(&c.gpu, mesh)
	}
	c.uploaded = true
	c.skinUploaded = skinned
}

// Vector_Cache_SetSkin gives the mesh per-vertex bones and weights (one
// per vertex; kept by the caller) and uploads it again with them.
Vector_Cache_SetSkin :: proc(c: ^Vector_Cache, ids: [][4]u8, weights: [][4]f32) {
	c.skinIds, c.skinWeights = ids, weights
	if c.uploaded {
		vector_cache_unload(c)
		if Vector_DrawModeNow() == .GPU && rl.IsWindowReady() do vector_cache_upload(c)
	}
}

// Vector_ScreenPixel: the size of a screen pixel in a node's local units now
// (the current camera / viewport transform times the node's scale).
Vector_ScreenPixel :: proc(nodeScale: [2]f32) -> f32 {
	mv := rlgl.GetMatrixModelview()
	sx := math.sqrt(mv[0, 0] * mv[0, 0] + mv[1, 0] * mv[1, 0])
	s := sx * max(abs(nodeScale.x), abs(nodeScale.y))
	return 1 / max(s, 1e-4)
}

// Vector_Cache_Draw draws the cached mesh at a transform (degrees), tinted.
// offset moves the mesh in its own units first (an asset's origin).
// add is a colour offset (0..1, alpha unused) added after the tint.
// deform bends it first (a warp, bones: vector_skin.odin). adjust: a colour
// adjustment after the tint and offset (saturation, contrast, hue degrees).
Vector_Cache_Draw :: proc(c: ^Vector_Cache, pos: [2]f32, rotation: f32, scale: [2]f32, tint: rl.Color = rl.WHITE, offset: [2]f32 = {}, add: [4]f32 = {}, deform: ^Vector_Deform = nil, adjust := VECTOR_NO_ADJUST) {
	if !rl.IsWindowReady() || len(c.mesh.idx) == 0 do return
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling() // (the tessellator doesn't keep one winding)
	defer {
		rlgl.DrawRenderBatchActive()
		rlgl.EnableBackfaceCulling()
	}
	if deform != nil && Vector_DrawModeNow() == .GPU && c.uploaded {
		vector_draw_deformed(c, pos, rotation, scale, tint, offset, add, deform, adjust)
		return
	}
	if Vector_DrawModeNow() == .GPU && c.uploaded {
		slot, fs := vector_shader_variant(c, adjust)
		vf := &vflat[slot]
		if !vf.ready {
			vf.material = rl.LoadMaterialDefault()
			vf.material.shader = rl.LoadShaderFromMemory(Shader_Port(VECTOR_VS), Shader_Port(fs))
			vf.add = rl.GetShaderLocation(vf.material.shader, "colAdd")
			vf.adjust = rl.GetShaderLocation(vf.material.shader, "adjust")
			vf.ready = true
		}
		vf.material.maps[rl.MaterialMapIndex.ALBEDO].color = tint
		if vf.add >= 0 {
			a := add
			rl.SetShaderValue(vf.material.shader, rl.ShaderLocationIndex(vf.add), &a, .VEC4)
		}
		if slot >= 2 do vector_set_adjust(vf.material.shader, vf.adjust, adjust)
		vf.material.maps[rl.MaterialMapIndex.ALBEDO].texture = c.gradTex if c.gradTex.id != 0 else rl.Texture2D{id = rlgl.GetTextureIdDefault(), width = 1, height = 1, mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
		xf := rl.MatrixTranslate(pos.x, pos.y, 0) * rl.MatrixRotateZ(rotation * rl.DEG2RAD) * rl.MatrixScale(scale.x, scale.y, 1) * rl.MatrixTranslate(offset.x, offset.y, 0)
		for m in c.gpu do rl.DrawMesh(m, vf.material, xf)
		return
	}
	rlgl.PushMatrix()
	rlgl.Translatef(pos.x, pos.y, 0)
	rlgl.Rotatef(rotation, 0, 0, 1)
	rlgl.Scalef(scale.x, scale.y, 1)
	rlgl.Translatef(offset.x, offset.y, 0)
	rlgl.Begin(rlgl.TRIANGLES)
	tr, tg, tb, ta := u32(tint.r), u32(tint.g), u32(tint.b), u32(tint.a)
	adjusted := adjust != VECTOR_NO_ADJUST
	m := &c.mesh
	for i := 0; i < len(m.idx); i += 3 {
		_ = rlgl.CheckRenderBatchLimit(3) // (flushes when full; raylib keeps the mode)
		for k in 0 ..< 3 {
			v := m.idx[i + k]
			col := m.cols[v]
			if m.gi[v].y > 0 do col = vector_vertex_gradient(m, v) // (per vertex: an approximation)
			if adjusted {
				// (Tint, offset, then the adjustment: the shader's order.)
				rgb := [3]f32{f32(col.r) * f32(tr), f32(col.g) * f32(tg), f32(col.b) * f32(tb)} / (255 * 255)
				rgb = Vector_AdjustColor({min(rgb.x + add[0], 1), min(rgb.y + add[1], 1), min(rgb.z + add[2], 1)}, adjust)
				rlgl.Color4ub(u8(rgb.x * 255 + 0.5), u8(rgb.y * 255 + 0.5), u8(rgb.z * 255 + 0.5), u8(u32(col.a) * ta / 255))
			} else {
				if add != {} {
					// (The colour offset, premultiplied by the vertex alpha like the shader.)
					for ch in 0 ..< 3 do col[ch] = u8(min(f32(col[ch]) + add[ch] * 255, 255))
				}
				rlgl.Color4ub(u8(u32(col.r) * tr / 255), u8(u32(col.g) * tg / 255), u8(u32(col.b) * tb / 255), u8(u32(col.a) * ta / 255))
			}
			p := m.verts[v]
			if deform != nil {
				skinned := len(c.skinIds) == len(m.verts) && len(c.skinWeights) == len(m.verts)
				p = Vector_DeformPoint(deform, p, c.skinIds[v] if skinned else {}, c.skinWeights[v] if skinned else {})
			}
			rlgl.Vertex2f(p.x, p.y)
		}
	}
	rlgl.End()
	rlgl.PopMatrix()
}

// vector_draw_deformed: the GPU path through the bending shader.
@(private = "file")
vector_draw_deformed :: proc(c: ^Vector_Cache, pos: [2]f32, rotation: f32, scale: [2]f32, tint: rl.Color, offset: [2]f32, add: [4]f32, d: ^Vector_Deform, adjust: [3]f32) {
	slot, fs := vector_shader_variant(c, adjust)
	vs := &vskin[slot]
	if !vs.ready {
		vs.material = rl.LoadMaterialDefault()
		sh := rl.LoadShaderFromMemory(Shader_Port(VECTOR_SKIN_VS), Shader_Port(fs))
		vs.material.shader = sh
		vs.add = rl.GetShaderLocation(sh, "colAdd")
		vs.adjust = rl.GetShaderLocation(sh, "adjust")
		vs.bones = rl.GetShaderLocation(sh, "bones")
		vs.skinOn = rl.GetShaderLocation(sh, "skinOn")
		vs.warpBox = rl.GetShaderLocation(sh, "warpBox")
		vs.warpA = rl.GetShaderLocation(sh, "warpA")
		vs.warpB = rl.GetShaderLocation(sh, "warpB")
		vs.ready = true
	}
	sh := vs.material.shader
	vs.material.maps[rl.MaterialMapIndex.ALBEDO].color = tint
	vs.material.maps[rl.MaterialMapIndex.ALBEDO].texture = c.gradTex if c.gradTex.id != 0 else rl.Texture2D{id = rlgl.GetTextureIdDefault(), width = 1, height = 1, mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
	a := add
	if vs.add >= 0 do rl.SetShaderValue(sh, rl.ShaderLocationIndex(vs.add), &a, .VEC4)
	if slot >= 2 do vector_set_adjust(sh, vs.adjust, adjust)
	on: f32 = 1 if c.skinUploaded && len(d.bones) > 0 else 0
	if vs.skinOn >= 0 do rl.SetShaderValue(sh, rl.ShaderLocationIndex(vs.skinOn), &on, .FLOAT)
	if on > 0 && vs.bones >= 0 {
		n := min(len(d.bones), VECTOR_SKIN_MAX_BONES)
		packed: [VECTOR_SKIN_MAX_BONES * 2][4]f32
		for m, i in d.bones[:n] {
			packed[i * 2] = {m[0], m[1], m[2], m[3]}
			packed[i * 2 + 1] = {m[4], m[5], 0, 0}
		}
		rl.SetShaderValueV(sh, rl.ShaderLocationIndex(vs.bones), &packed, .VEC4, i32(n * 2))
	}
	box := [4]f32{d.box[0], d.box[1], d.box[2], d.box[3]}
	wa := [4]f32{d.warp[0].x, d.warp[0].y, d.warp[1].x, d.warp[1].y}
	wb := [4]f32{d.warp[2].x, d.warp[2].y, d.warp[3].x, d.warp[3].y}
	if vs.warpBox >= 0 do rl.SetShaderValue(sh, rl.ShaderLocationIndex(vs.warpBox), &box, .VEC4)
	if vs.warpA >= 0 do rl.SetShaderValue(sh, rl.ShaderLocationIndex(vs.warpA), &wa, .VEC4)
	if vs.warpB >= 0 do rl.SetShaderValue(sh, rl.ShaderLocationIndex(vs.warpB), &wb, .VEC4)
	xf := rl.MatrixTranslate(pos.x, pos.y, 0) * rl.MatrixRotateZ(rotation * rl.DEG2RAD) * rl.MatrixScale(scale.x, scale.y, 1) * rl.MatrixTranslate(offset.x, offset.y, 0)
	for m in c.gpu do rl.DrawMesh(m, vs.material, xf)
}

// Vector_DeformShutdown frees the bending shader (engine shutdown).
Vector_DeformShutdown :: proc() {
	for &v in vskin do if v.ready {
		// (Not UnloadMaterial: its albedo may be a cache's gradient texture.)
		if rl.IsWindowReady() do rl.UnloadShader(v.material.shader)
		rl.MemFree(v.material.maps)
		v = {}
	}
}

// vector_vertex_gradient: a gradient vertex's colour on the CPU (the
// immediate path; the shader does this per pixel).
@(private = "file")
vector_vertex_gradient :: proc(m: ^Vector_Mesh, v: u32) -> [4]u8 {
	g := m.gi[v]
	row := clamp(int(g.x), 0, len(m.gradients) - 1)
	mode := int(g.y + 0.5) - 1
	kind, spread := mode / 4, Vector_Spread(mode % 4)
	gc := m.gc[v]
	t := gc.x if kind == 0 else math.sqrt(gc.x * gc.x + gc.y * gc.y)
	t = Vector_PaintSpread(spread, t)
	c := m.gradients[row][clamp(int(t * 255 + 0.5), 0, 255)]
	return {c.r, c.g, c.b, u8(u32(c.a) * u32(m.cols[v].a) / 255)}
}
