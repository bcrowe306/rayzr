package engine

import rl "vendor:raylib"

// ============================================================================
// Bloom (the scene's Environment node, lighting_nodes.odin): the frame's
// bright parts - lights pushed past the art with Overbright, emission,
// bright art - blurred and added back, so they glow past their edges.
// It runs first in the post chain (Post_Process), before the scene's own
// Post Effects.
//
//   bright pass   pixels over Threshold (a soft knee), at half size
//   blur          separable, ~Radius pixels (two rounds when wide)
//   composite     the frame + glow x Strength
// ============================================================================

@(private = "file")
BRIGHT_FS :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;
uniform sampler2D texture0;
uniform float threshold;
void main() {
    vec3 c = texture(texture0, fragTexCoord).rgb;
    float l = max(c.r, max(c.g, c.b));
    float k = clamp((l - threshold) / max(1.0 - threshold, 0.001), 0.0, 1.0);
    finalColor = vec4(c * k * k, 1.0);
}
`

@(private = "file")
BLUR_FS :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;
uniform sampler2D texture0;
uniform vec2 dir;
void main() {
    float w[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);
    vec3 s = texture(texture0, fragTexCoord).rgb * w[0];
    for (int i = 1; i < 5; i++) {
        s += texture(texture0, fragTexCoord + dir * float(i)).rgb * w[i];
        s += texture(texture0, fragTexCoord - dir * float(i)).rgb * w[i];
    }
    finalColor = vec4(s, 1.0);
}
`

@(private = "file")
COMPOSITE_FS :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;
uniform sampler2D texture0;
uniform sampler2D glow;
uniform float strength;
void main() {
    vec4 c = texture(texture0, fragTexCoord);
    finalColor = vec4(c.rgb + texture(glow, fragTexCoord).rgb * strength, c.a);
}
`

@(private = "file")
bloom: struct {
	ok:            bool,
	tried:         bool,
	bright, blur, composite: rl.Shader,
	locThreshold, locDir, locGlow, locStrength: i32,
	a, b:          rl.RenderTexture2D, // half size (ping-pong)
	out:           rl.RenderTexture2D, // full size
	size:          [2]i32,
}

// Bloom_Active: the scene's Environment when it has Bloom on (nil: none).
Bloom_Active :: proc(scene: ^Scene) -> ^EnvironmentNode {
	if !Lighting_Enabled() do return nil
	env := Scene_Environment(scene)
	if env == nil || !env.bloom || env.bloomStrength <= 0 do return nil
	return env
}

// Post_Wanted: the frame goes through the post chain (effects or bloom).
Post_Wanted :: proc(scene: ^Scene, effects: []^Node) -> bool {
	return len(effects) > 0 || Bloom_Active(scene) != nil
}

@(private = "file")
bloom_ensure :: proc(w, h: i32) -> bool {
	if !rl.IsWindowReady() || w <= 0 || h <= 0 do return false
	if !bloom.tried {
		bloom.tried = true
		bloom.bright = rl.LoadShaderFromMemory(nil, Shader_Port(BRIGHT_FS))
		bloom.blur = rl.LoadShaderFromMemory(nil, Shader_Port(BLUR_FS))
		bloom.composite = rl.LoadShaderFromMemory(nil, Shader_Port(COMPOSITE_FS))
		bloom.ok = rl.IsShaderValid(bloom.bright) && rl.IsShaderValid(bloom.blur) && rl.IsShaderValid(bloom.composite)
		bloom.locThreshold = rl.GetShaderLocation(bloom.bright, "threshold")
		bloom.locDir = rl.GetShaderLocation(bloom.blur, "dir")
		bloom.locGlow = rl.GetShaderLocation(bloom.composite, "glow")
		bloom.locStrength = rl.GetShaderLocation(bloom.composite, "strength")
	}
	if !bloom.ok do return false
	if bloom.size != {w, h} {
		for t in ([?]^rl.RenderTexture2D{&bloom.a, &bloom.b, &bloom.out}) do if t.id != 0 do rl.UnloadRenderTexture(t^)
		hw, hh := max(w / 2, 1), max(h / 2, 1)
		bloom.a = rl.LoadRenderTexture(hw, hh)
		bloom.b = rl.LoadRenderTexture(hw, hh)
		bloom.out = rl.LoadRenderTexture(w, h)
		rl.SetTextureFilter(bloom.a.texture, .BILINEAR)
		rl.SetTextureFilter(bloom.b.texture, .BILINEAR)
		bloom.size = {w, h}
	}
	return true
}

// Bloom_Apply: the frame with the Environment's bloom (src itself when it
// can't). The result is valid until the next frame's bloom.
Bloom_Apply :: proc(env: ^EnvironmentNode, src: rl.Texture2D) -> rl.Texture2D {
	if env == nil || !bloom_ensure(src.width, src.height) do return src
	w, h := f32(src.width), f32(src.height)
	hw, hh := f32(bloom.a.texture.width), f32(bloom.a.texture.height)
	// Bright pass, at half size.
	thr := clamp(env.bloomThreshold, 0, 1)
	rl.BeginTextureMode(bloom.a)
	rl.ClearBackground(rl.BLACK)
	rl.BeginShaderMode(bloom.bright)
	rl.SetShaderValue(bloom.bright, bloom.locThreshold, &thr, .FLOAT)
	rl.DrawTexturePro(src, {0, 0, w, -h}, {0, 0, hw, hh}, {0, 0}, 0, rl.WHITE)
	rl.EndShaderMode()
	rl.EndTextureMode()
	// Blur (half-size pixels: the radius halves).
	px := max(env.bloomRadius, 1) * 0.5
	rounds := 1 if px <= 8 else 2
	step := px / 4 / f32(rounds)
	for _ in 0 ..< rounds {
		bloom_blur(&bloom.a, &bloom.b, {step / hw, 0})
		bloom_blur(&bloom.b, &bloom.a, {0, step / hh})
	}
	// The frame + the glow.
	s := env.bloomStrength
	rl.BeginTextureMode(bloom.out)
	rl.ClearBackground({0, 0, 0, 0})
	rl.BeginShaderMode(bloom.composite)
	rl.SetShaderValue(bloom.composite, bloom.locStrength, &s, .FLOAT)
	rl.SetShaderValueTexture(bloom.composite, bloom.locGlow, bloom.a.texture)
	rl.DrawTextureRec(src, {0, 0, w, -h}, {0, 0}, rl.WHITE)
	rl.EndShaderMode()
	rl.EndTextureMode()
	return bloom.out.texture
}

@(private = "file")
bloom_blur :: proc(src, dst: ^rl.RenderTexture2D, dir: [2]f32) {
	d := dir
	rl.BeginTextureMode(dst^)
	rl.ClearBackground(rl.BLACK)
	rl.BeginShaderMode(bloom.blur)
	rl.SetShaderValue(bloom.blur, bloom.locDir, &d, .VEC2)
	t := src.texture
	rl.DrawTextureRec(t, {0, 0, f32(t.width), -f32(t.height)}, {0, 0}, rl.WHITE)
	rl.EndShaderMode()
	rl.EndTextureMode()
}

// Bloom_Unload frees its targets and shaders.
Bloom_Unload :: proc() {
	if rl.IsWindowReady() {
		for t in ([?]^rl.RenderTexture2D{&bloom.a, &bloom.b, &bloom.out}) do if t.id != 0 do rl.UnloadRenderTexture(t^)
		if bloom.ok {
			rl.UnloadShader(bloom.bright)
			rl.UnloadShader(bloom.blur)
			rl.UnloadShader(bloom.composite)
		}
	}
	bloom = {}
}
