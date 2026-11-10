package engine

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// GPU particles (#129). An emitter in GPU mode keeps, per particle, only
// the record of its birth: where, how fast, when, how long it lives, its
// size, spin, colour jitter and random seed. The CPU emits as usual (the
// same shapes and variances) and uploads the new records; each frame one
// instanced draw of quads lets the vertex shader work out every particle
// from its age in closed form:
//
//   position   p0 + v0 t + 1/2 F t^2          (damping k: p0 + F/k t + (v0 - F/k)(1 - e^-kt)/k)
//   rotation   r0 + w t + 1/2 a t^2           (align to velocity: the velocity's angle)
//   orbit      the offset from the emitter turned by orbitVelocity t, then pushed
//              out by radialVelocity t (applied to the path - near the CPU mode's)
//   size       Scale Start -> End, or the size curve
//   colour     the ramp (or Color -> Color End) + jitter, x the alpha curve
//   frame      the frame (over life / speed / random; a grid, a list, timed: #401)
//
// F is gravity + wind (in the particles' space) + the particle's own
// acceleration. Desktop GL 3.3 and WebGL2 (Shader_Port); no compute
// shaders (macOS GL 4.1 and WebGL2 don't have them). Not in GPU mode:
// collision, Lua custom shapes, the speed curve. ParticleGPU_Evaluate is
// the same maths on the CPU (tests).
// ============================================================================

// GPU_PARTICLE_MAX: records per emitter (a ring about twice `amount`).
GPU_PARTICLE_MAX :: 262144

// One particle's birth, as uploaded (16 floats, the shader's attributes 1-7).
Particle_GPU_Record :: struct {
	spawn:    [2]f32, // where (the emitter's space if local, else world)
	velocity: [2]f32,
	accel:    [2]f32, // its own acceleration (along its angle)
	birth:    f32,    // the emitter's GPU clock at birth (< 0 far: an empty slot)
	lifetime: f32,
	size:     [2]f32,
	rotation: f32,    // degrees
	torque:   f32,    // degrees/s
	jitter:   [3]f32, // colour jitter (0..255 units)
	seed:     f32,    // its random number (the sheet frame: Random)
}

Particle_GPU :: struct {
	records:        []Particle_GPU_Record,
	head:           int,
	clock:          f32,
	dirtyLo:        int, // records to upload (lo >= hi: none)
	dirtyHi:        int,
	vao, vboCorner: u32,
	vboRecords:     u32,
	uploaded:       int, // the GL buffer's size in records
}

EMPTY_BIRTH :: -1e9

// particle_gpu_data: the emitter's GPU state, its ring sized for `amount`.
@(private = "file")
particle_gpu_data :: proc(emitter: ^ParticleEmitter) -> ^Particle_GPU {
	alloc := emitter.allocator if emitter.allocator.procedure != nil else context.allocator
	if emitter.gpuData == nil do emitter.gpuData = new(Particle_GPU, alloc)
	g := emitter.gpuData
	want := clamp(emitter.amount * 2 + 4, 16, GPU_PARTICLE_MAX)
	if len(g.records) != want {
		old := g.records
		g.records = make([]Particle_GPU_Record, want, alloc)
		for &r in g.records do r.birth = EMPTY_BIRTH
		if emitter.allocator.procedure == nil && old != nil do delete(old, alloc)
		g.head = 0
		g.dirtyLo, g.dirtyHi = 0, want
	}
	return g
}

// ParticleGPU_Push stores a particle made by ParticleEmitter_Emit.
ParticleGPU_Push :: proc(emitter: ^ParticleEmitter, p: Particle) {
	g := particle_gpu_data(emitter)
	i := g.head % len(g.records)
	g.head = (i + 1) % len(g.records)
	g.records[i] = {
		spawn = p.position, velocity = p.velocity, accel = p.acceleration,
		birth = g.clock, lifetime = p.lifetime, size = p.size,
		rotation = p.rotation, torque = p.torque,
		jitter = p.colorJitter, seed = f32(p.frameSeed % 65536),
	}
	if g.dirtyLo >= g.dirtyHi {
		g.dirtyLo, g.dirtyHi = i, i + 1
	} else {
		g.dirtyLo, g.dirtyHi = min(g.dirtyLo, i), max(g.dirtyHi, i + 1)
	}
}

ParticleGPU_Advance :: proc(emitter: ^ParticleEmitter, dt: f32) {
	if emitter.gpuData != nil do emitter.gpuData.clock += dt
}

ParticleGPU_AliveCount :: proc(emitter: ^ParticleEmitter) -> int {
	g := emitter.gpuData
	if g == nil do return 0
	n := 0
	for r in g.records {
		age := g.clock - r.birth
		if age >= 0 && age < r.lifetime do n += 1
	}
	return n
}

ParticleGPU_Clear :: proc(emitter: ^ParticleEmitter) {
	g := emitter.gpuData
	if g == nil do return
	for &r in g.records do r.birth = EMPTY_BIRTH
	g.dirtyLo, g.dirtyHi = 0, len(g.records)
}

// ParticleGPU_Release frees the GL buffers (the node's destroy; GPU off).
ParticleGPU_Release :: proc(emitter: ^ParticleEmitter) {
	g := emitter.gpuData
	if g == nil do return
	if rl.IsWindowReady() {
		if g.vao != 0 do rlgl.UnloadVertexArray(g.vao)
		if g.vboCorner != 0 do rlgl.UnloadVertexBuffer(g.vboCorner)
		if g.vboRecords != 0 do rlgl.UnloadVertexBuffer(g.vboRecords)
	}
	g.vao, g.vboCorner, g.vboRecords, g.uploaded = 0, 0, 0, 0
	g.dirtyLo, g.dirtyHi = 0, len(g.records)
}

// --- the maths (the shader's, on the CPU) -----------------------------------------------

Particle_GPU_State :: struct {
	alive:    bool,
	position: [2]f32, // world
	velocity: [2]f32, // the particles' space
	rotation: f32,    // world, degrees
	scale:    [2]f32,
	color:    rl.Color,
}

// ParticleGPU_Evaluate: a record's particle at the emitter's clock `now`,
// as the vertex shader computes it.
ParticleGPU_Evaluate :: proc(emitter: ^ParticleEmitter, r: Particle_GPU_Record, now: f32) -> (s: Particle_GPU_State) {
	t := now - r.birth
	if t < 0 || t >= r.lifetime do return
	s.alive = true
	gravity, wind := particle_forces(emitter)
	F := gravity + wind + r.accel
	k := max(emitter.damping, 0)
	disp, vel: [2]f32
	if k > 0.0001 {
		e := math.exp(-k * t)
		disp = F / k * t + (r.velocity - F / k) * (1 - e) / k
		vel = F / k + (r.velocity - F / k) * e
	} else {
		disp = r.velocity * t + 0.5 * F * t * t
		vel = r.velocity + F * t
	}
	pos := r.spawn + disp * emitter.velocityScale
	if emitter.orbitVelocity != 0 || emitter.radialVelocity != 0 {
		center := [2]f32{} if emitter.localSpace else emitter.position
		d := particle_rotate(pos - center, emitter.orbitVelocity * t)
		l := math.sqrt(d.x * d.x + d.y * d.y)
		if l > 0.0001 do d += d / l * emitter.radialVelocity * t
		pos = center + d
	}
	life := t / r.lifetime
	s.rotation = r.rotation + r.torque * t + 0.5 * emitter.torqueAcceleration * t * t
	if emitter.alignToVelocity && (vel.x != 0 || vel.y != 0) do s.rotation = math.to_degrees(math.atan2(vel.y, vel.x)) + emitter.rotation
	if emitter.sizeCurve.count > 0 {
		c := ParticleCurve_Sample(&emitter.sizeCurve, life)
		s.scale = {c, c}
	} else {
		s.scale = math.lerp(emitter.scaleStart, emitter.scaleEnd, life)
	}
	base: [4]f32
	if emitter.useColorRamp {
		c := ColorRamp_Evaluate(&emitter.colorRamp, life)
		base = {f32(c.r) + r.jitter.x, f32(c.g) + r.jitter.y, f32(c.b) + r.jitter.z, f32(c.a)}
	} else {
		a, b := emitter.particleColor, emitter.colorEnd
		j := [4]f32{r.jitter.x, r.jitter.y, r.jitter.z, 0} if emitter.colorVariance > 0 else {}
		ca := [4]f32{f32(a.r), f32(a.g), f32(a.b), f32(a.a)} + j
		cb := [4]f32{f32(b.r), f32(b.g), f32(b.b), f32(b.a)} + j
		base = math.lerp(ca, cb, life)
	}
	base.a *= ParticleCurve_Sample(&emitter.alphaCurve, life)
	s.color = {u8(math.clamp(base.r, 0, 255)), u8(math.clamp(base.g, 0, 255)), u8(math.clamp(base.b, 0, 255)), u8(math.clamp(base.a, 0, 255))}
	s.velocity = vel
	if emitter.localSpace {
		s.position = particle_to_world(emitter, pos)
		s.rotation += emitter.originRotation
	} else {
		s.position = pos
	}
	return
}

// --- the shader ---------------------------------------------------------------------

@(private = "file")
PARTICLE_GPU_VS :: `#version 330
layout(location = 0) in vec2 a_corner;
layout(location = 1) in vec2 a_spawn;
layout(location = 2) in vec2 a_vel;
layout(location = 3) in vec2 a_acc;
layout(location = 4) in vec2 a_life;   // birth, lifetime
layout(location = 5) in vec2 a_size;
layout(location = 6) in vec2 a_rot;    // rotation, torque (degrees)
layout(location = 7) in vec4 a_jit;    // jitter rgb (0..255), seed
uniform mat4 u_mvp;
uniform float u_time;
uniform int u_local;
uniform vec2 u_origin;
uniform float u_originRot;
uniform vec2 u_originScale;
uniform vec2 u_force;
uniform float u_damping;
uniform float u_velScale;
uniform float u_torqueAcc;
uniform float u_radial;
uniform float u_orbit;
uniform int u_useRamp;
uniform int u_rampCount;
uniform float u_rampPos[8];
uniform vec4 u_rampCol[8];   // 0..255
uniform vec4 u_colStart;     // 0..255
uniform vec4 u_colEnd;
uniform int u_jitterFlat;    // Color -> Color End without variance: no jitter
uniform vec2 u_scaleStart;
uniform vec2 u_scaleEnd;
uniform int u_sizeCount;
uniform vec2 u_sizeCurve[8];
uniform int u_alphaCount;
uniform vec2 u_alphaCurve[8];
uniform int u_shape;         // 0 circle, 1 ellipse, 2 rectangle, 3 pixel, 4 line, 5 texture
uniform int u_align;
uniform float u_rotOffset;
uniform int u_frameMode;     // 0 over life, 1 speed, 2 random
uniform float u_frameSpeed;
// The frames (#401; Particle_Frames): a grid of cells or a list of
// rectangles (px), each frame's end when timed; uv = px / u_texSize.
uniform int u_fCount;
uniform int u_fList;
uniform vec2 u_fOrigin;
uniform vec2 u_fStep;
uniform vec2 u_fCell;
uniform int u_fCols;
uniform int u_fFirst;
uniform vec4 u_fRects[64];
uniform int u_fTimed;
uniform vec4 u_fEnds[16];    // 64 ends, 4 a vector
uniform int u_fLoop;
uniform int u_fRandStart;
uniform int u_fWhole;        // the whole texture (uv 0..1)
uniform vec2 u_texSize;
uniform vec2 u_pivot;
uniform int u_flipX;
uniform int u_flipY;
out vec2 v_uv;
out vec4 v_col;

vec2 rot(vec2 v, float deg) {
	float r = radians(deg);
	float c = cos(r), s = sin(r);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}
float curve(vec2 pts[8], int n, float t, float none) {
	if (n == 0) return none;
	if (t <= pts[0].x) return pts[0].y;
	for (int i = 1; i < 8; i++) {
		if (i >= n) break;
		if (t <= pts[i].x) {
			float span = pts[i].x - pts[i - 1].x;
			float f = span > 0.0 ? (t - pts[i - 1].x) / span : 0.0;
			return mix(pts[i - 1].y, pts[i].y, f);
		}
	}
	return pts[n - 1].y;
}
vec4 ramp(float t) {
	if (u_rampCount == 0) return vec4(255.0);
	if (u_rampCount == 1 || t <= u_rampPos[0]) return u_rampCol[0];
	for (int i = 1; i < 8; i++) {
		if (i >= u_rampCount) break;
		if (t <= u_rampPos[i]) {
			float d = u_rampPos[i] - u_rampPos[i - 1];
			float f = d > 0.0001 ? (t - u_rampPos[i - 1]) / d : 0.0;
			return mix(u_rampCol[i - 1], u_rampCol[i], f);
		}
	}
	return u_rampCol[u_rampCount - 1];
}

float frameEnd(int i) {return u_fEnds[i / 4][i % 4];}
// The frame a particle shows (Particle_Frame on the CPU).
int frameIndex(float t, float life, int seed) {
	int n = u_fCount;
	if (n <= 1) return 0;
	if (u_frameMode == 2) return seed % n;
	int start = u_fRandStart == 1 ? (seed >> 10) % n : 0;
	bool wraps = u_frameMode == 0 || u_fLoop == 1;
	if (u_fTimed == 1) {
		float total = frameEnd(n - 1);
		float tt = u_frameMode == 0 ? life * total : t;
		if (start > 0) tt += frameEnd(start - 1);
		tt = wraps ? mod(tt, total) : min(tt, total * 0.99999);
		for (int i = 0; i < 64; i++) {
			if (i >= n) break;
			if (tt < frameEnd(i)) return i;
		}
		return n - 1;
	}
	int f = u_frameMode == 0 ? min(int(floor(life * float(n))), n - 1) : int(floor(t * u_frameSpeed));
	f += start;
	return wraps ? f % n : min(f, n - 1);
}

void main() {
	float t = u_time - a_life.x;
	if (t < 0.0 || t >= a_life.y) {
		gl_Position = vec4(2.0, 2.0, 2.0, 1.0); // (not alive: off screen)
		v_uv = vec2(0.0); v_col = vec4(0.0);
		return;
	}
	vec2 F = u_force + a_acc;
	float k = u_damping;
	vec2 disp, vel;
	if (k > 0.0001) {
		float e = exp(-k * t);
		disp = F / k * t + (a_vel - F / k) * (1.0 - e) / k;
		vel = F / k + (a_vel - F / k) * e;
	} else {
		disp = a_vel * t + 0.5 * F * t * t;
		vel = a_vel + F * t;
	}
	vec2 pos = a_spawn + disp * u_velScale;
	if (u_orbit != 0.0 || u_radial != 0.0) {
		vec2 center = u_local == 1 ? vec2(0.0) : u_origin;
		vec2 d = rot(pos - center, u_orbit * t);
		float l = length(d);
		if (l > 0.0001) d += d / l * u_radial * t;
		pos = center + d;
	}
	float life = t / a_life.y;
	float r = a_rot.x + a_rot.y * t + 0.5 * u_torqueAcc * t * t;
	if (u_align == 1 && (vel.x != 0.0 || vel.y != 0.0)) r = degrees(atan(vel.y, vel.x)) + u_rotOffset;
	vec2 scl = u_sizeCount > 0 ? vec2(curve(u_sizeCurve, u_sizeCount, life, 1.0)) : mix(u_scaleStart, u_scaleEnd, life);
	vec4 col;
	vec4 jit = vec4(a_jit.xyz, 0.0);
	if (u_useRamp == 1) col = ramp(life) + jit;
	else col = mix(u_colStart + (u_jitterFlat == 1 ? vec4(0.0) : jit), u_colEnd + (u_jitterFlat == 1 ? vec4(0.0) : jit), life);
	col.a *= curve(u_alphaCurve, u_alphaCount, life, 1.0);
	v_col = clamp(col, 0.0, 255.0) / 255.0;
	vec2 size = a_size;
	if (u_local == 1) {
		pos = u_origin + rot(pos * u_originScale, u_originRot);
		size *= abs(u_originScale);
		r += u_originRot;
	}
	// The quad as the CPU renderer draws each shape.
	vec2 q;
	vec2 center = pos;
	if (u_shape == 0) { q = vec2(2.0 * size.x * scl.x); r = 0.0; }
	else if (u_shape == 1) { q = 2.0 * size * scl; r = 0.0; }
	else if (u_shape == 3) { q = vec2(1.0); center += 0.5; r = 0.0; }
	else if (u_shape == 4) { q = vec2(size.x * scl.x, max(scl.y, 0.01)); }
	else { q = size * scl; }
	vec2 uv = a_corner + 0.5;
	vec2 pv = vec2(0.5);
	if (u_shape == 5) {
		// The frame (#401), flipped per particle, and the pivot.
		int seed = int(a_jit.w);
		bool fx = u_flipX == 1 && ((seed >> 8) & 1) == 1;
		bool fy = u_flipY == 1 && ((seed >> 9) & 1) == 1;
		pv = vec2(fx ? 1.0 - u_pivot.x : u_pivot.x, fy ? 1.0 - u_pivot.y : u_pivot.y);
		vec2 fuv = vec2(fx ? 1.0 - uv.x : uv.x, fy ? 1.0 - uv.y : uv.y);
		if (u_fWhole == 1) {
			uv = fuv;
		} else {
			int f = frameIndex(t, life, seed);
			vec4 rc;
			if (u_fList == 1) rc = u_fRects[f];
			else {
				int cell = u_fFirst + f;
				rc = vec4(u_fOrigin + vec2(float(cell % u_fCols), float(cell / u_fCols)) * u_fStep, u_fCell);
			}
			uv = (rc.xy + fuv * rc.zw) / u_texSize;
		}
	}
	v_uv = uv;
	gl_Position = u_mvp * vec4(center + rot((a_corner + 0.5 - pv) * q, r), 0.0, 1.0);
}
`

@(private = "file")
PARTICLE_GPU_FS :: `#version 330
in vec2 v_uv;
in vec4 v_col;
uniform sampler2D texture0;
out vec4 finalColor;
void main() {
	finalColor = texture(texture0, v_uv) * v_col;
}
`

@(private = "file")
gpuShader: struct {
	shader: rl.Shader,
	loaded: bool,
	locs:   map[cstring]i32,
}

@(private = "file")
gpu_loc :: proc(name: cstring) -> i32 {
	if l, ok := gpuShader.locs[name]; ok do return l
	l := rl.GetShaderLocation(gpuShader.shader, name)
	if gpuShader.locs == nil do gpuShader.locs = make(map[cstring]i32, 64, Engine_HeapAllocator())
	gpuShader.locs[name] = l
	return l
}

// ParticleGPU_Shutdown frees the shared shader (engine shutdown).
ParticleGPU_Shutdown :: proc() {
	if gpuShader.loaded && rl.IsWindowReady() do rl.UnloadShader(gpuShader.shader)
	delete(gpuShader.locs)
	gpuShader = {}
}

@(private = "file")
set_f :: proc(name: cstring, v: f32) {v := v; rl.SetShaderValue(gpuShader.shader, gpu_loc(name), &v, .FLOAT)}
@(private = "file")
set_i :: proc(name: cstring, v: i32) {v := v; rl.SetShaderValue(gpuShader.shader, gpu_loc(name), &v, .INT)}
@(private = "file")
set_v2 :: proc(name: cstring, v: [2]f32) {v := v; rl.SetShaderValue(gpuShader.shader, gpu_loc(name), &v, .VEC2)}
@(private = "file")
set_v4 :: proc(name: cstring, v: [4]f32) {v := v; rl.SetShaderValue(gpuShader.shader, gpu_loc(name), &v, .VEC4)}

@(private = "file")
color_v4 :: proc(c: rl.Color) -> [4]f32 {return {f32(c.r), f32(c.g), f32(c.b), f32(c.a)}}

// ParticleGPU_Render: the emitter's particles in one instanced draw.
ParticleGPU_Render :: proc(emitter: ^ParticleEmitter) {
	g := emitter.gpuData
	if g == nil || len(g.records) == 0 || !rl.IsWindowReady() do return
	if !gpuShader.loaded {
		gpuShader.shader = rl.LoadShaderFromMemory(Shader_Port(PARTICLE_GPU_VS), Shader_Port(PARTICLE_GPU_FS))
		gpuShader.loaded = true
	}
	if gpuShader.shader.id == 0 do return
	rlgl.DrawRenderBatchActive() // (what was drawn before: under the particles)

	// The buffers: a quad (two triangles) and the records, uploaded where new.
	stride := i32(size_of(Particle_GPU_Record))
	if g.vao == 0 || g.uploaded != len(g.records) {
		if g.vao != 0 do ParticleGPU_Release(emitter)
		corners := [12]f32{-0.5, -0.5, -0.5, 0.5, 0.5, 0.5, -0.5, -0.5, 0.5, 0.5, 0.5, -0.5}
		g.vao = rlgl.LoadVertexArray()
		rlgl.EnableVertexArray(g.vao)
		g.vboCorner = rlgl.LoadVertexBuffer(&corners, size_of(corners), false)
		rlgl.SetVertexAttribute(0, 2, rlgl.FLOAT, false, 0, 0)
		rlgl.EnableVertexAttribute(0)
		g.vboRecords = rlgl.LoadVertexBuffer(raw_data(g.records), i32(len(g.records)) * stride, true)
		layout := [7][2]i32{{1, 2}, {2, 2}, {3, 2}, {4, 2}, {5, 2}, {6, 2}, {7, 4}} // location, floats
		off: i32 = 0
		for a in layout {
			rlgl.SetVertexAttribute(u32(a[0]), a[1], rlgl.FLOAT, false, stride, off)
			rlgl.EnableVertexAttribute(u32(a[0]))
			rlgl.SetVertexAttributeDivisor(u32(a[0]), 1)
			off += a[1] * 4
		}
		rlgl.DisableVertexArray()
		g.uploaded = len(g.records)
		g.dirtyLo, g.dirtyHi = 0, 0
	} else if g.dirtyLo < g.dirtyHi {
		rlgl.UpdateVertexBuffer(g.vboRecords, &g.records[g.dirtyLo], i32(g.dirtyHi - g.dirtyLo) * stride, i32(g.dirtyLo) * stride)
		g.dirtyLo, g.dirtyHi = 0, 0
	}

	// The blend mode before the shader: switching it flushes raylib's batch,
	// which unbinds the shader in use (the particles drew with none).
	switch emitter.blendMode {
	case .Alpha:
	case .Additive:      rl.BeginBlendMode(.ADDITIVE)
	case .Multiply:      rl.BeginBlendMode(.MULTIPLIED)
	case .Premultiplied: rl.BeginBlendMode(.ALPHA_PREMULTIPLY)
	}
	defer if emitter.blendMode != .Alpha do rl.EndBlendMode()

	// The uniforms: what the CPU twin (ParticleGPU_Evaluate) reads.
	rlgl.EnableShader(gpuShader.shader.id)
	mvp := ParticleGPU_MVP(rlgl.GetMatrixModelview(), rlgl.GetMatrixProjection())
	rl.SetShaderValueMatrix(gpuShader.shader, gpu_loc("u_mvp"), mvp)
	set_f("u_time", g.clock)
	set_i("u_local", 1 if emitter.localSpace else 0)
	set_v2("u_origin", emitter.position)
	set_f("u_originRot", emitter.originRotation)
	set_v2("u_originScale", particle_scale(emitter))
	gravity, wind := particle_forces(emitter)
	set_v2("u_force", gravity + wind)
	set_f("u_damping", max(emitter.damping, 0))
	set_f("u_velScale", emitter.velocityScale)
	set_f("u_torqueAcc", emitter.torqueAcceleration)
	set_f("u_radial", emitter.radialVelocity)
	set_f("u_orbit", emitter.orbitVelocity)
	set_i("u_useRamp", 1 if emitter.useColorRamp else 0)
	ramp := &emitter.colorRamp
	set_i("u_rampCount", i32(ramp.count))
	pos: [8]f32
	cols: [8][4]f32
	for i in 0 ..< ramp.count {
		pos[i] = ramp.stops[i].position
		cols[i] = color_v4(ramp.stops[i].color)
	}
	rl.SetShaderValueV(gpuShader.shader, gpu_loc("u_rampPos"), &pos, .FLOAT, 8)
	rl.SetShaderValueV(gpuShader.shader, gpu_loc("u_rampCol"), &cols, .VEC4, 8)
	set_v4("u_colStart", color_v4(emitter.particleColor))
	set_v4("u_colEnd", color_v4(emitter.colorEnd))
	set_i("u_jitterFlat", 1 if emitter.colorVariance <= 0 else 0)
	set_v2("u_scaleStart", emitter.scaleStart)
	set_v2("u_scaleEnd", emitter.scaleEnd)
	set_i("u_sizeCount", i32(emitter.sizeCurve.count))
	rl.SetShaderValueV(gpuShader.shader, gpu_loc("u_sizeCurve"), &emitter.sizeCurve.points, .VEC2, 8)
	set_i("u_alphaCount", i32(emitter.alphaCurve.count))
	rl.SetShaderValueV(gpuShader.shader, gpu_loc("u_alphaCurve"), &emitter.alphaCurve.points, .VEC2, 8)
	shape: i32
	tex := rlgl.GetTextureIdDefault()
	switch emitter.shape {
	case .Circle:    shape, tex = 0, particle_circle_texture()
	case .Ellipse:   shape, tex = 1, particle_circle_texture()
	case .Rectangle: shape = 2
	case .Pixel:     shape = 3
	case .Line:      shape = 4
	case .Texture:
		shape = 5
		if emitter.texture == nil || emitter.texture.id == 0 {
			rlgl.DisableShader()
			return
		}
		tex = emitter.texture.id
	case .Custom:
		rlgl.DisableShader()
		return // (Lua custom shapes: not in GPU mode)
	}
	set_i("u_shape", shape)
	set_i("u_align", 1 if emitter.alignToVelocity else 0)
	set_f("u_rotOffset", emitter.rotation)
	set_i("u_frameMode", i32(emitter.frameMode))
	set_f("u_frameSpeed", emitter.frameSpeed)
	fr := &emitter.frames
	set_i("u_fCount", i32(fr.count))
	set_i("u_fList", 1 if fr.list else 0)
	set_v2("u_fOrigin", fr.origin)
	set_v2("u_fStep", fr.step)
	set_v2("u_fCell", fr.cell)
	set_i("u_fCols", i32(max(fr.cols, 1)))
	set_i("u_fFirst", i32(fr.first))
	if fr.list do rl.SetShaderValueV(gpuShader.shader, gpu_loc("u_fRects"), &fr.rects, .VEC4, MAX_PARTICLE_FRAMES)
	set_i("u_fTimed", 1 if fr.timed else 0)
	if fr.timed do rl.SetShaderValueV(gpuShader.shader, gpu_loc("u_fEnds"), &fr.ends, .VEC4, MAX_PARTICLE_FRAMES / 4)
	set_i("u_fLoop", 1 if emitter.frameLoop else 0)
	set_i("u_fRandStart", 1 if emitter.frameRandomStart else 0)
	whole := fr.texSize.x <= 0 || fr.texSize.y <= 0 || !(fr.count > 1 || fr.list || fr.cell != fr.texSize || fr.origin != {})
	set_i("u_fWhole", 1 if whole else 0)
	set_v2("u_texSize", fr.texSize)
	set_v2("u_pivot", emitter.texturePivot)
	set_i("u_flipX", 1 if emitter.randomFlipX else 0)
	set_i("u_flipY", 1 if emitter.randomFlipY else 0)
	rlgl.ActiveTextureSlot(0)
	rlgl.EnableTexture(tex)
	set_i("texture0", 0)

	rlgl.EnableVertexArray(g.vao)
	rlgl.DrawVertexArrayInstanced(0, 6, i32(len(g.records)))
	rlgl.DisableVertexArray()
	rlgl.DisableTexture()
	rlgl.DisableShader()
}

// ParticleGPU_MVP: the shader's matrix. (Odin's * is the true product, not
// raylib's MatrixMultiply(a, b) = b·a: the projection goes on the left.)
ParticleGPU_MVP :: proc(modelview, projection: rl.Matrix) -> rl.Matrix {
	return projection * modelview
}
