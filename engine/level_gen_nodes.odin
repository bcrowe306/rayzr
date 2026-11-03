package engine

import "core:math"

// ============================================================================
// More level generator nodes (#171): gradient noise for the noise node's
// Perlin and Simplex types, and the Poisson-disc scatter.
//
// Gradient noise is computed from each cell's absolute position (the grid's
// origin plus the cell) and a permutation table per octave shuffled by the
// node's own seed - no global table, nothing that depends on the grid's
// size - so a chunk of a bigger level gets the same values at the same
// cells. Only + - * and floor: the same numbers on every platform.
// ============================================================================

GEN_NOISE_TYPES := []string{"value", "perlin", "simplex"}

// GEN_PERM: entries in a permutation table (a power of two). The lattice
// repeats after this many lattice cells - 4096 * scale / 2^octave cells.
@(private)
GEN_PERM :: 4096

@(private = "file")
GEN_GRAD2 := [8][2]f32{{1, 1}, {-1, 1}, {1, -1}, {-1, -1}, {1, 0}, {-1, 0}, {0, 1}, {0, -1}}

// The raw noises brought to -1..1 with a similar spread: Perlin's values
// bunch near 0 (spread 0.26 against Simplex's 0.47, measured), so it is
// raised and its rare extremes clip.
@(private = "file")
GEN_PERLIN_GAIN :: 1.6
@(private = "file")
GEN_SIMPLEX_GAIN :: 70.0

@(private = "file")
Gen_Gradient_Job :: struct {
	out:       Gen_Grid,
	origin:    [2]int,
	simplex:   bool,
	octaves:   int,
	freq, amp: [8]f32,
	norm:      f32,
	perm:      [8][]u16,
}

// gen_perm_table: 0 .. GEN_PERM-1 shuffled by a seed (Fisher-Yates on the
// node's own sequence).
@(private = "file")
gen_perm_table :: proc(seed: u64) -> []u16 {
	perm := make([]u16, GEN_PERM, context.temp_allocator)
	for &v, i in perm do v = u16(i)
	rng := seed
	for i := GEN_PERM - 1; i > 0; i -= 1 {
		j := gen_rand_int(&rng, 0, i)
		perm[i], perm[j] = perm[j], perm[i]
	}
	return perm
}

// gen_perm_hash: a lattice point's gradient (0..7) - any integer point,
// negative too (the mask wraps it).
@(private = "file")
gen_perm_hash :: #force_inline proc(perm: []u16, ix, iy: int) -> int #no_bounds_check {
	M :: GEN_PERM - 1
	return int(perm[(int(perm[ix & M]) + iy) & M]) & 7
}

@(private = "file")
gen_grad_dot :: #force_inline proc(h: int, x, y: f32) -> f32 #no_bounds_check {
	g := GEN_GRAD2[h]
	return g.x * x + g.y * y
}

// gen_perlin: classic gradient noise (quintic fade), -1..1.
@(private)
gen_perlin :: proc(perm: []u16, x, y: f32) -> f32 {
	x0, y0 := math.floor(x), math.floor(y)
	ix, iy := int(x0), int(y0)
	fx, fy := x - x0, y - y0
	u := fx * fx * fx * (fx * (fx * 6 - 15) + 10)
	v := fy * fy * fy * (fy * (fy * 6 - 15) + 10)
	n00 := gen_grad_dot(gen_perm_hash(perm, ix, iy), fx, fy)
	n10 := gen_grad_dot(gen_perm_hash(perm, ix + 1, iy), fx - 1, fy)
	n01 := gen_grad_dot(gen_perm_hash(perm, ix, iy + 1), fx, fy - 1)
	n11 := gen_grad_dot(gen_perm_hash(perm, ix + 1, iy + 1), fx - 1, fy - 1)
	return clamp(math.lerp(math.lerp(n00, n10, u), math.lerp(n01, n11, u), v) * GEN_PERLIN_GAIN, -1, 1)
}

// gen_simplex: 2D simplex noise (Gustavson's), -1..1.
@(private)
gen_simplex :: proc(perm: []u16, x, y: f32) -> f32 {
	F2 :: 0.36602540378 // (sqrt(3) - 1) / 2
	G2 :: 0.21132486540 // (3 - sqrt(3)) / 6
	s := (x + y) * F2
	fi, fj := math.floor(x + s), math.floor(y + s)
	i, j := int(fi), int(fj)
	t := (fi + fj) * G2
	x0, y0 := x - (fi - t), y - (fj - t)
	i1, j1: int = 1, 0
	if x0 <= y0 do i1, j1 = 0, 1
	x1, y1 := x0 - f32(i1) + G2, y0 - f32(j1) + G2
	x2, y2 := x0 - 1 + 2 * G2, y0 - 1 + 2 * G2
	corner :: #force_inline proc(perm: []u16, i, j: int, x, y: f32) -> f32 {
		t := 0.5 - x * x - y * y
		if t <= 0 do return 0
		t *= t
		return t * t * gen_grad_dot(gen_perm_hash(perm, i, j), x, y)
	}
	n := corner(perm, i, j, x0, y0) + corner(perm, i + i1, j + j1, x1, y1) + corner(perm, i + 1, j + 1, x2, y2)
	return clamp(n * GEN_SIMPLEX_GAIN, -1, 1)
}

// gen_gradient_noise: Perlin or Simplex fBm, 0..1, into `out` - the cell
// (x, y) of `out` is the absolute cell origin + (x, y). Each octave doubles
// the frequency and multiplies the amplitude by `persistence` (as value
// noise does) and has its own table; rows split across the workers.
@(private)
gen_gradient_noise :: proc(out: Gen_Grid, origin: [2]int, scale: f32, octaves: int, persistence: f32, seed: u64, simplex: bool) {
	job := Gen_Gradient_Job{out = out, origin = origin, simplex = simplex, octaves = octaves}
	amp, freq: f32 = 1, 1 / scale
	for o in 0 ..< octaves {
		job.freq[o], job.amp[o] = freq, amp
		job.norm += abs(amp)
		job.perm[o] = gen_perm_table(gen_mix(seed + u64(o) * 7919, 0x9e7a))
		amp *= persistence
		freq *= 2
	}
	job.norm = max(job.norm, 0.0001)
	gen_parallel(out.h, out.w * octaves * 4, &job, proc(data: rawptr, y0, y1: int) {
		j := cast(^Gen_Gradient_Job)data
		w := j.out.w
		#no_bounds_check for y in y0 ..< y1 do for x in 0 ..< w {
			ax, ay := f32(j.origin.x + x), f32(j.origin.y + y)
			sum: f32
			for o in 0 ..< j.octaves {
				n := gen_simplex(j.perm[o], ax * j.freq[o], ay * j.freq[o]) if j.simplex else gen_perlin(j.perm[o], ax * j.freq[o], ay * j.freq[o])
				sum += n * j.amp[o]
			}
			j.out.v[y * w + x] = clamp(0.5 + 0.5 * sum / j.norm, 0, 1)
		}
	})
}

// gen_poisson: Poisson-disc points (Bridson's algorithm) - every two at
// least `radius` cells apart (between the cells' centres), on the input's
// solid cells when `masked`. From a first point, each step takes a random
// active point and tries `attempts` cells in the ring radius..2 * radius
// around it; the first one far enough from every point joins (and becomes
// active), and a point with no luck in all its tries stops being active.
// Instead of Bridson's background grid, each point marks the cells near it
// (a grid the level's size): a try is then one look-up. Areas the walk
// can't reach (allowed cells farther than 2 * radius from every point:
// another part of the mask) start walks of their own, in row order. One
// thread: each point depends on those before it.
@(private)
gen_poisson :: proc(src, out: Gen_Grid, masked: bool, radius: f32, attempts: int, seed: u64) #no_bounds_check {
	w, h := out.w, out.h
	if w <= 0 || h <= 0 do return
	Offset :: struct {
		dx, dy: i16,
		near:   u8, // 2: under radius, 1: under 2 * radius
	}
	P :: struct {
		src, out: Gen_Grid,
		masked:   bool,
		near:     []u8, // each cell: 2 within radius of a point, 1 within 2 * radius, 0 neither
		disc:     []Offset, // the offsets under 2 * radius
		pts:      [dynamic][2]i32,
		active:   [dynamic]i32,
	}
	p := P{src = src, out = out, masked = masked}
	p.near = make([]u8, w * h, context.temp_allocator)
	p.pts = make([dynamic][2]i32, context.temp_allocator)
	p.active = make([dynamic]i32, context.temp_allocator)
	// The ring's cells (radius..2 * radius) and the disc's (under 2 * radius).
	r2 := radius * radius
	ring := int(math.ceil(2 * radius))
	rings := make([dynamic][2]i16, context.temp_allocator)
	disc := make([dynamic]Offset, context.temp_allocator)
	for dy in -ring ..= ring do for dx in -ring ..= ring {
		d := f32(dx * dx + dy * dy)
		if d < 4 * r2 do append(&disc, Offset{i16(dx), i16(dy), 2 if d < r2 else 1})
		if d >= r2 && d <= 4 * r2 do append(&rings, [2]i16{i16(dx), i16(dy)})
	}
	p.disc = disc[:]

	allowed :: #force_inline proc(p: ^P, x, y: int) -> bool #no_bounds_check {
		if x < 0 || y < 0 || x >= p.out.w || y >= p.out.h do return false
		return !p.masked || p.src.v[y * p.src.w + x] >= 0.5
	}
	add :: proc(p: ^P, x, y: int) #no_bounds_check {
		append(&p.active, i32(len(p.pts)))
		append(&p.pts, [2]i32{i32(x), i32(y)})
		p.out.v[y * p.out.w + x] = 1
		for o in p.disc {
			xx, yy := x + int(o.dx), y + int(o.dy)
			if xx < 0 || yy < 0 || xx >= p.out.w || yy >= p.out.h do continue
			c := &p.near[yy * p.out.w + xx]
			c^ = max(c^, o.near)
		}
	}
	walk :: proc(p: ^P, rng: ^u64, rings: [][2]i16, attempts: int) #no_bounds_check {
		for len(p.active) > 0 {
			ai := gen_rand_int(rng, 0, len(p.active) - 1)
			c := p.pts[p.active[ai]]
			placed := false
			for _ in 0 ..< attempts {
				o := rings[gen_rand_int(rng, 0, len(rings) - 1)]
				x, y := int(c.x) + int(o.x), int(c.y) + int(o.y)
				if !allowed(p, x, y) || p.near[y * p.out.w + x] == 2 do continue
				add(p, x, y)
				placed = true
				break
			}
			if !placed do unordered_remove(&p.active, ai)
		}
	}

	rng := seed
	// The first point: a random allowed cell (a few tries).
	for _ in 0 ..< 64 {
		x, y := gen_rand_int(&rng, 0, w - 1), gen_rand_int(&rng, 0, h - 1)
		if !allowed(&p, x, y) do continue
		add(&p, x, y)
		walk(&p, &rng, rings[:], attempts)
		break
	}
	// Areas no walk reached.
	for y in 0 ..< h do for x in 0 ..< w {
		if p.near[y * w + x] != 0 || !allowed(&p, x, y) do continue
		add(&p, x, y)
		walk(&p, &rng, rings[:], attempts)
	}
}
