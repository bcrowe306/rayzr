package engine

import "base:runtime"
import "core:fmt"
import os "osx"
import "core:strconv"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

// ============================================================================
// Materials: a shader, a blend mode and shader parameters on any node.
//
// node.material (nil = plain drawing) is applied around the node's own
// render: sprites, tile maps, particles, LDtk levels, ... The shader is a
// built-in ("builtin:flash", "builtin:outline", "builtin:dissolve",
// "builtin:grayscale", "builtin:wave") or a project fragment shader
// (".fs" / ".glsl", GLSL 330 like raylib's). Parameters are the shader's
// uniforms, found by reading its source:
//
//   uniform float amount;       // range 0 1   default 0.5
//   uniform vec4  flash_color;  // color       default 1 1 1 1
//   uniform sampler2D noise;    // a texture parameter (project path)
//   uniform float time;         // set automatically (seconds)
//
// Saved with the node ("material": {"shader", "blend", "params"}).
// Lua: node:set_shader(path), node:set_shader_param(name, ...),
// node:get_shader_param(name), node:set_blend_mode(name).
// ============================================================================

Material_Blend :: enum {
	Alpha,
	Additive,
	Multiply,
	AddColors,
	SubtractColors,
	Premultiplied,
}

Material_ParamKind :: enum {
	Float,
	Vec2,
	Vec3,
	Vec4,
	Int,
	Texture,
}

Material_Param :: struct {
	name:    string,
	value:   [4]f32,
	texture: string, // Texture params: project-relative image path
}

Material :: struct {
	shader: string, // "" = none (blend mode only)
	blend:  Material_Blend,
	params: [dynamic]Material_Param,
}

// A uniform the shader declares (editable parameter).
Shader_Uniform :: struct {
	name:     string,
	kind:     Material_ParamKind,
	isColor:  bool,
	hasRange: bool,
	min, max: f32,
	default_: [4]f32,
	auto:     bool, // set by the engine (time)
}

@(private = "file")
Shader_Entry :: struct {
	shader:    rl.Shader,
	loaded:    bool,
	failed:    bool,
	source:    string,
	uniforms:  [dynamic]Shader_Uniform,
	locs:      map[string]i32,
	modTime:   time.Time,
	diskPath:  string,
}

@(private = "file")
shaderCache: map[string]^Shader_Entry

@(private = "file")
lastShaderCheck: time.Tick

BUILTIN_SHADERS :: []string{"builtin:flash", "builtin:outline", "builtin:dissolve", "builtin:grayscale", "builtin:wave",
	// For PostEffectNodes (the whole screen):
	"builtin:vignette", "builtin:crt", "builtin:pixelate", "builtin:chromatic"}

@(private = "file")
SHADER_HEADER :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
uniform vec4 colDiffuse;
out vec4 finalColor;
`

Builtin_ShaderSource :: proc(name: string) -> string {
	switch name {
	case "builtin:flash":
		return SHADER_HEADER + `
uniform vec4 flash_color; // color default 1 1 1 1
uniform float amount; // range 0 1 default 0.8
void main() {
    vec4 c = texture(texture0, fragTexCoord) * colDiffuse * fragColor;
    finalColor = vec4(mix(c.rgb, flash_color.rgb, amount), c.a);
}
`
	case "builtin:outline":
		return SHADER_HEADER + `
uniform vec4 outline_color; // color default 1 1 1 1
uniform float width; // range 0 8 default 1.5
void main() {
    vec2 px = width / vec2(textureSize(texture0, 0));
    vec4 c = texture(texture0, fragTexCoord) * colDiffuse * fragColor;
    float a = 0.0;
    a = max(a, texture(texture0, fragTexCoord + vec2(px.x, 0.0)).a);
    a = max(a, texture(texture0, fragTexCoord - vec2(px.x, 0.0)).a);
    a = max(a, texture(texture0, fragTexCoord + vec2(0.0, px.y)).a);
    a = max(a, texture(texture0, fragTexCoord - vec2(0.0, px.y)).a);
    float edge = clamp(a - c.a, 0.0, 1.0) * outline_color.a;
    finalColor = mix(c, vec4(outline_color.rgb, 1.0), edge * (1.0 - c.a)) ;
    finalColor.a = max(c.a, edge);
}
`
	case "builtin:dissolve":
		return SHADER_HEADER + `
uniform float threshold; // range 0 1 default 0.3
uniform float edge_width; // range 0 0.3 default 0.05
uniform vec4 edge_color; // color default 1 0.5 0.1 1
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
void main() {
    vec4 c = texture(texture0, fragTexCoord) * colDiffuse * fragColor;
    float n = noise(fragTexCoord * 12.0);
    if (n < threshold) discard;
    float e = 1.0 - smoothstep(0.0, edge_width, n - threshold);
    finalColor = vec4(mix(c.rgb, edge_color.rgb, e * step(0.0001, threshold)), c.a);
}
`
	case "builtin:grayscale":
		return SHADER_HEADER + `
uniform float amount; // range 0 1 default 1
void main() {
    vec4 c = texture(texture0, fragTexCoord) * colDiffuse * fragColor;
    float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
    finalColor = vec4(mix(c.rgb, vec3(g), amount), c.a);
}
`
	case "builtin:wave":
		return SHADER_HEADER + `
uniform float time;
uniform float amplitude; // range 0 0.1 default 0.02
uniform float frequency; // range 0 40 default 12
uniform float speed; // range 0 10 default 3
void main() {
    vec2 uv = fragTexCoord;
    uv.x += sin(uv.y * frequency + time * speed) * amplitude;
    finalColor = texture(texture0, uv) * colDiffuse * fragColor;
}
`
	case "builtin:vignette":
		return SHADER_HEADER + `
uniform float strength; // range 0 2 default 0.8
uniform float radius; // range 0.2 1.5 default 0.75
uniform vec4 tint; // color default 0 0 0 1
void main() {
    vec4 c = texture(texture0, fragTexCoord) * colDiffuse * fragColor;
    float d = distance(fragTexCoord, vec2(0.5)) * 1.414;
    float v = smoothstep(radius, radius - 0.45, d);
    finalColor = vec4(mix(tint.rgb, c.rgb, mix(1.0, v, clamp(strength, 0.0, 1.0))), c.a);
}
`
	case "builtin:crt":
		return SHADER_HEADER + `
uniform float time;
uniform vec2 resolution;
uniform float curvature; // range 0 0.3 default 0.08
uniform float scanlines; // range 0 1 default 0.35
uniform float noise; // range 0 0.2 default 0.03
void main() {
    vec2 uv = fragTexCoord * 2.0 - 1.0;
    uv *= 1.0 + curvature * dot(uv, uv) * 0.5;
    uv = uv * 0.5 + 0.5;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { finalColor = vec4(0.0, 0.0, 0.0, 1.0); return; }
    vec4 c = texture(texture0, uv) * colDiffuse * fragColor;
    float line = 0.5 + 0.5 * sin(uv.y * resolution.y * 3.14159);
    c.rgb *= 1.0 - scanlines * (1.0 - line);
    float n = fract(sin(dot(uv * resolution + time, vec2(12.9898, 78.233))) * 43758.5453);
    c.rgb += (n - 0.5) * noise;
    finalColor = vec4(c.rgb, 1.0);
}
`
	case "builtin:pixelate":
		return SHADER_HEADER + `
uniform vec2 resolution;
uniform float pixel_size; // range 1 32 default 4
void main() {
    vec2 cell = pixel_size / resolution;
    vec2 uv = (floor(fragTexCoord / cell) + 0.5) * cell;
    finalColor = texture(texture0, uv) * colDiffuse * fragColor;
}
`
	case "builtin:chromatic":
		return SHADER_HEADER + `
uniform float amount; // range 0 0.02 default 0.004
void main() {
    vec2 dir = fragTexCoord - vec2(0.5);
    float r = texture(texture0, fragTexCoord + dir * amount).r;
    vec4 g = texture(texture0, fragTexCoord);
    float b = texture(texture0, fragTexCoord - dir * amount).b;
    finalColor = vec4(r, g.g, b, g.a) * colDiffuse * fragColor;
}
`
	case "builtin:passthrough":
		return SHADER_HEADER + `
void main() { finalColor = texture(texture0, fragTexCoord) * colDiffuse * fragColor; }
`
	// Scene transitions (scene_transition.odin): texture0 = the old scene's
	// frame, new_scene = the new one's; progress 0 (old) .. 1 (new).
	case "builtin:transition_dissolve":
		return SHADER_HEADER + `
uniform float progress;
uniform vec2 resolution;
uniform vec4 transition_color;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void main() {
    vec2 px = fragTexCoord * resolution;
    float n = noise(px / 28.0) * 0.7 + noise(px / 6.0) * 0.3;
    float t = progress * 1.08; // (all of it gone at 1)
    if (n < t) discard;
    vec4 c = texture(texture0, fragTexCoord);
    float edge = 1.0 - smoothstep(t, t + 0.06, n); // a burning rim in the colour
    finalColor = vec4(mix(c.rgb, transition_color.rgb, edge * transition_color.a * step(0.001, progress)), 1.0);
}
`
	case "builtin:transition_pixelate":
		return SHADER_HEADER + `
uniform float progress;
uniform vec2 resolution;
uniform sampler2D new_scene;
void main() {
    float k = 1.0 - abs(progress * 2.0 - 1.0); // 0 -> 1 (halfway) -> 0
    float block = max(1.0, floor(k * 48.0));
    vec2 cell = block / resolution;
    vec2 uv = (floor(fragTexCoord / cell) + 0.5) * cell;
    vec4 c = progress < 0.5 ? texture(texture0, uv) : texture(new_scene, uv);
    finalColor = vec4(c.rgb, 1.0);
}
`
	}
	return ""
}

// Shader_ParseUniforms reads the editable uniforms (and their hints) of a
// fragment shader.
Shader_ParseUniforms :: proc(source: string, allocator := context.allocator) -> [dynamic]Shader_Uniform {
	out := make([dynamic]Shader_Uniform, allocator)
	for raw in strings.split_lines(source, context.temp_allocator) {
		line := strings.trim_space(raw)
		if !strings.has_prefix(line, "uniform ") do continue
		code := line
		comment := ""
		if i := strings.index(line, "//"); i >= 0 {
			code = strings.trim_space(line[:i])
			comment = strings.trim_space(line[i + 2:])
		}
		code = strings.trim_suffix(strings.trim_space(code), ";")
		parts := strings.fields(code, context.temp_allocator)
		if len(parts) < 3 do continue
		typ, name := parts[1], parts[2]
		switch name {
		case "texture0", "colDiffuse", "mvp", "matModel", "matView", "matProjection", "matNormal":
			continue
		}
		u := Shader_Uniform{name = strings.clone(name, allocator)}
		switch typ {
		case "float": u.kind = .Float
		case "vec2":  u.kind = .Vec2
		case "vec3":  u.kind = .Vec3
		case "vec4":  u.kind = .Vec4
		case "int", "bool": u.kind = .Int
		case "sampler2D": u.kind = .Texture
		case: continue
		}
		if name == "time" && u.kind == .Float do u.auto = true
		if name == "resolution" && u.kind == .Vec2 do u.auto = true // the target's size (post effects)
		// Hints: "color", "range a b", "default x y z w".
		words := strings.fields(comment, context.temp_allocator)
		for i := 0; i < len(words); i += 1 {
			switch words[i] {
			case "color":
				u.isColor = true
			case "range":
				if i + 2 < len(words) {
					u.min, _ = strconv.parse_f32(words[i + 1])
					u.max, _ = strconv.parse_f32(words[i + 2])
					u.hasRange = true
					i += 2
				}
			case "default":
				for k in 0 ..< 4 {
					if i + 1 >= len(words) do break
					v, ok := strconv.parse_f32(words[i + 1])
					if !ok do break
					u.default_[k] = v
					i += 1
				}
			}
		}
		if u.isColor && comment != "" && !strings.contains(comment, "default") do u.default_ = {1, 1, 1, 1}
		append(&out, u)
	}
	return out
}

// shader_entry finds or prepares a shader (loaded on first use with a window).
@(private = "file")
shader_entry :: proc(path: string, ctx: ^GameContext) -> ^Shader_Entry {
	if path == "" do return nil
	// The cache is global (also used from Lua callbacks): always the heap.
	context.allocator = Engine_HeapAllocator()
	if shaderCache == nil do shaderCache = make(map[string]^Shader_Entry)
	if en, ok := shaderCache[path]; ok do return en
	en := new(Shader_Entry)
	en.locs = make(map[string]i32)
	src := Builtin_ShaderSource(path)
	if src == "" {
		if ctx != nil && ctx.game != nil {
			if data, ok := AssetManager_ReadFileString(&ctx.game.assetManager, path, context.temp_allocator); ok do src = data
			en.diskPath = strings.clone(AssetManager_ResolveDiskPath(&ctx.game.assetManager, path))
		} else if data, err := os.read_entire_file(path, context.temp_allocator); err == nil {
			src = string(data)
			en.diskPath = strings.clone(path)
		}
		if en.diskPath != "" {
			if info, err := os.stat(en.diskPath, context.temp_allocator); err == nil do en.modTime = info.modification_time
		}
	}
	if src == "" {
		en.failed = true
	} else {
		en.source = strings.clone(src)
		en.uniforms = Shader_ParseUniforms(src)
	}
	shaderCache[strings.clone(path)] = en
	return en
}

// Shader_Get: a shader by path (a project file or "builtin:<name>"), loaded
// on first use and cached (project files reload when saved).
Shader_Get :: proc(path: string, ctx: ^GameContext) -> (rl.Shader, bool) {
	en := shader_entry(path, ctx)
	if en == nil || !shader_ensure_loaded(en) do return {}, false
	return en.shader, true
}

// Shader_Uniforms: the editable uniforms of a shader (for the Inspector).
Shader_Uniforms :: proc(path: string, ctx: ^GameContext) -> []Shader_Uniform {
	en := shader_entry(path, ctx)
	return en.uniforms[:] if en != nil else nil
}

// Shader_Failed: the shader couldn't be read or compiled.
Shader_Failed :: proc(path: string, ctx: ^GameContext) -> bool {
	en := shader_entry(path, ctx)
	return en == nil || en.failed
}

@(private = "file")
shader_ensure_loaded :: proc(en: ^Shader_Entry) -> bool {
	if en.failed do return false
	if en.loaded do return true
	if !rl.IsWindowReady() do return false
	src := strings.clone_to_cstring(en.source, context.temp_allocator)
	en.shader = rl.LoadShaderFromMemory(nil, Shader_Port(src))
	if !rl.IsShaderValid(en.shader) {
		en.failed = true
		fmt.eprintln("[Material] Shader failed to compile")
		return false
	}
	en.loaded = true
	for u in en.uniforms {
		en.locs[u.name] = rl.GetShaderLocation(en.shader, strings.clone_to_cstring(u.name, context.temp_allocator))
	}
	return true
}

@(private = "file")
shader_release :: proc(en: ^Shader_Entry) {
	context.allocator = Engine_HeapAllocator()
	if en.loaded && rl.IsWindowReady() do rl.UnloadShader(en.shader)
	delete(en.source)
	for u in en.uniforms do delete(u.name)
	delete(en.uniforms)
	delete(en.locs)
	delete(en.diskPath)
	free(en)
}

// Shader_CheckForChanges reloads project shaders saved since they were
// loaded (polled at most twice a second). Returns how many reloaded.
Shader_CheckForChanges :: proc() -> int {
	context.allocator = Engine_HeapAllocator()
	if time.tick_since(lastShaderCheck) < 500 * time.Millisecond do return 0
	lastShaderCheck = time.tick_now()
	n := 0
	for path, en in shaderCache {
		if en.diskPath == "" do continue
		info, err := os.stat(en.diskPath, context.temp_allocator)
		if err != nil || time.diff(en.modTime, info.modification_time) <= 0 do continue
		delete_key(&shaderCache, path)
		shader_release(en)
		delete(path)
		n += 1
	}
	return n
}

// Shader_UnloadAll releases every cached shader.
Shader_UnloadAll :: proc() {
	context.allocator = Engine_HeapAllocator()
	for k in materialTextures do delete(k)
	delete(materialTextures)
	materialTextures = nil
	for path, en in shaderCache {
		shader_release(en)
		delete(path)
	}
	delete(shaderCache)
	shaderCache = nil
}

// --- materials ----------------------------------------------------------------------

Node_EnsureMaterial :: proc(node: ^Node) -> ^Material {
	if node.material == nil {
		node.material = new(Material, node.allocator)
		node.material.params = make([dynamic]Material_Param, node.allocator)
	}
	return node.material
}

Material_SetShader :: proc(node: ^Node, shader: string) {
	m := Node_EnsureMaterial(node)
	m.shader = strings.clone(shader, node.allocator)
}

// Material_SetParam sets a parameter's value (adding it).
Material_SetParam :: proc(node: ^Node, name: string, value: [4]f32, texture := "") {
	m := Node_EnsureMaterial(node)
	for &p in m.params {
		if p.name == name {
			p.value = value
			if texture != "" do p.texture = strings.clone(texture, node.allocator)
			return
		}
	}
	append(&m.params, Material_Param{strings.clone(name, node.allocator), value, strings.clone(texture, node.allocator)})
}

// Material_GetParam: a parameter's value, else the shader's default.
Material_GetParam :: proc(node: ^Node, name: string) -> (value: [4]f32, texture: string, ok: bool) {
	if node.material == nil do return
	for p in node.material.params do if p.name == name do return p.value, p.texture, true
	for u in Shader_Uniforms(node.material.shader, node.gameContext) do if u.name == name do return u.default_, "", true
	return
}

Material_RemoveParam :: proc(node: ^Node, name: string) {
	if node.material == nil do return
	for p, i in node.material.params {
		if p.name == name {
			ordered_remove(&node.material.params, i)
			return
		}
	}
}

@(private = "file")
blend_mode :: proc(b: Material_Blend) -> rl.BlendMode {
	switch b {
	case .Alpha:          return .ALPHA
	case .Additive:       return .ADDITIVE
	case .Multiply:       return .MULTIPLIED
	case .AddColors:      return .ADD_COLORS
	case .SubtractColors: return .SUBTRACT_COLORS
	case .Premultiplied:  return .ALPHA_PREMULTIPLY
	}
	return .ALPHA
}

// Textures used by material parameters: loaded once (one reference kept for
// the run) - not a new reference every frame.
@(private = "file")
materialTextures: map[string]^Texture

@(private = "file")
material_texture :: proc(path: string, ctx: ^GameContext) -> ^Texture {
	if path == "" || ctx == nil || ctx.game == nil do return nil
	if t, ok := materialTextures[path]; ok do return t
	rm := &ctx.game.resourceManager
	t, ok := ResourceManager_LoadTextureOwn(rm, Project_ResolveAssetPath(ctx, path)) // (not an atlas page: shaders sample the whole texture)
	if !ok do return nil
	if materialTextures == nil do materialTextures = make(map[string]^Texture, allocator = Engine_HeapAllocator())
	materialTextures[strings.clone(path, Engine_HeapAllocator())] = t
	return t
}

// Material_Begin applies a node's material (returns false if nothing to do).
Material_Begin :: proc(node: ^Node, ctx: ^GameContext) -> bool {
	m := node.material
	if m == nil || !rl.IsWindowReady() do return false
	active := false
	if m.shader != "" {
		if en := shader_entry(m.shader, ctx); en != nil && shader_ensure_loaded(en) {
			rl.BeginShaderMode(en.shader)
			for u in en.uniforms {
				loc := en.locs[u.name]
				if loc < 0 do continue
				v := u.default_
				tex := ""
				if u.auto {
					if u.name == "resolution" do v.xy = {f32(rl.GetRenderWidth()), f32(rl.GetRenderHeight())}
					else do v.x = f32(rl.GetTime())
				} else {
					for p in m.params do if p.name == u.name {v, tex = p.value, p.texture; break}
				}
				switch u.kind {
				case .Float: rl.SetShaderValue(en.shader, loc, &v.x, .FLOAT)
				case .Vec2:  rl.SetShaderValue(en.shader, loc, &v, .VEC2)
				case .Vec3:  rl.SetShaderValue(en.shader, loc, &v, .VEC3)
				case .Vec4:  rl.SetShaderValue(en.shader, loc, &v, .VEC4)
				case .Int:
					iv := i32(v.x)
					rl.SetShaderValue(en.shader, loc, &iv, .INT)
				case .Texture:
					if Viewport_IsPath(tex) {
						if vt, _ := Viewport_TextureByPath(ctx, tex); vt.id != 0 do rl.SetShaderValueTexture(en.shader, loc, vt) // (a Viewport's picture)
					} else if t := material_texture(tex, ctx); t != nil do rl.SetShaderValueTexture(en.shader, loc, t.texture)
				}
			}
			active = true
		}
	}
	if m.blend != .Alpha {
		rl.BeginBlendMode(blend_mode(m.blend))
		active = true
	}
	return active
}

Material_End :: proc(node: ^Node) {
	m := node.material
	if m.blend != .Alpha do rl.EndBlendMode()
	if m.shader != "" do rl.EndShaderMode()
}

Material_BlendName :: proc(b: Material_Blend) -> string {
	switch b {
	case .Alpha:          return "alpha"
	case .Additive:       return "additive"
	case .Multiply:       return "multiply"
	case .AddColors:      return "add_colors"
	case .SubtractColors: return "subtract_colors"
	case .Premultiplied:  return "premultiplied"
	}
	return "alpha"
}

Material_BlendParse :: proc(s: string) -> Material_Blend {
	for b in Material_Blend do if Material_BlendName(b) == s do return b
	return .Alpha
}
