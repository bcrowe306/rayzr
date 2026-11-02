package engine

import "base:runtime"
import "core:c"
import "core:math"
import "core:mem"
import lua "lua54"
import rl "vendor:raylib"

// ============================================================================
// Drawing vectors from Lua (Phase 14 V.3): a script's `on_draw()` calls the
// `Vector` module - canvas-style paths (begin_path, move_to, cubic_to, rect,
// circle...), styles (colours, gradients, widths, joins, dashes) and fill /
// stroke, with save / restore / translate / rotate / scale - in its node's
// local space. Each node has a canvas: what it drew is tessellated once and
// reused while the drawing stays the same (a hash of the shapes) and the
// zoom stays in its bucket (vector_mesh.odin), so static procedural art
// costs nothing per frame; animated drawing re-tessellates (~0.3 ms for
// hundreds of curves).
//
// The engine calls on_draw in draw order (the node's layer / Z / Y-sort,
// like its sprite would be) for every node whose script defines it.
// ============================================================================

Vector_Canvas_State :: struct {
	style: Vector_Style,
	xf:    [6]f32, // a, b, c, d, e, f
	clip:  ^Vector_Clip, // Vector.clip(): what drawing is cut to (until restore)
}

Vector_Canvas :: struct {
	shapes:   [dynamic]Vector_Shape, // pool: the first `count` are this frame's
	count:    int,
	path:     Vector_Path,
	state:    Vector_Canvas_State,
	stack:    [dynamic]Vector_Canvas_State,
	cache:    Vector_Cache,
	lastHash: u64,
	clips:    [dynamic]^Vector_Clip, // pool: the first `clipCount` are this frame's
	clipCount: int,
}

@(private = "file")
XF_IDENTITY :: [6]f32{1, 0, 0, 1, 0, 0}

// The canvas a running on_draw records into (nil outside on_draw).
@(private = "file")
vectorCanvas: ^Vector_Canvas
@(private = "file")
canvasTess: Vector_Tess

Vector_Canvas_Create :: proc() -> ^Vector_Canvas {
	context.allocator = Engine_HeapAllocator()
	cv := new(Vector_Canvas)
	cv.shapes = make([dynamic]Vector_Shape)
	cv.stack = make([dynamic]Vector_Canvas_State)
	cv.clips = make([dynamic]^Vector_Clip)
	Vector_Path_Init(&cv.path)
	return cv
}

Vector_Canvas_Destroy :: proc(cv: ^Vector_Canvas) {
	if cv == nil do return
	context.allocator = Engine_HeapAllocator()
	for &s in cv.shapes do Vector_Path_Destroy(&s.path)
	delete(cv.shapes)
	delete(cv.stack)
	for k in cv.clips {
		Vector_Path_Destroy(&k.path)
		free(k)
	}
	delete(cv.clips)
	Vector_Path_Destroy(&cv.path)
	Vector_Cache_Destroy(&cv.cache)
	free(cv)
}

// Vector_Canvas_Begin starts a frame's drawing (a fresh default state).
Vector_Canvas_Begin :: proc(cv: ^Vector_Canvas) {
	cv.count = 0
	cv.clipCount = 0
	clear(&cv.stack)
	Vector_Path_Clear(&cv.path)
	cv.state = {style = VECTOR_STYLE_DEFAULT, xf = XF_IDENTITY}
	cv.state.style.stroke = false
}

// Vector_Canvas_Finish: the frame's shapes are final - re-tessellated only
// when they differ from the last drawing's.
Vector_Canvas_Finish :: proc(cv: ^Vector_Canvas) {
	h := vector_canvas_hash(cv)
	if h != cv.lastHash {
		cv.cache.dirty = true
		cv.lastHash = h
	}
}

// Vector_Canvas_Draw draws the canvas at a transform (the node's).
Vector_Canvas_Draw :: proc(cv: ^Vector_Canvas, pos: [2]f32, rotation: f32, scale: [2]f32, tint := rl.WHITE) {
	if cv.count == 0 do return
	{
		context.allocator = Engine_HeapAllocator()
		Vector_Cache_Ensure(&cv.cache, &canvasTess, cv.shapes[:cv.count], Vector_ScreenPixel(scale))
	}
	Vector_Cache_Draw(&cv.cache, pos, rotation, scale, tint)
}

// Vector_CanvasShapes: this frame's shapes (tests, editor previews).
Vector_CanvasShapes :: proc(cv: ^Vector_Canvas) -> []Vector_Shape {return cv.shapes[:cv.count]}

Vector_Canvas_ShutdownScratch :: proc() {
	Vector_Tess_Destroy(&canvasTess)
}

@(private = "file")
vector_canvas_hash :: proc(cv: ^Vector_Canvas) -> u64 {
	h: u64 = 14695981039346656037
	mix :: proc(h: ^u64, data: []u8) {
		for b in data {
			h^ ~= u64(b)
			h^ *= 1099511628211
		}
	}
	n := cv.count
	mix(&h, mem.ptr_to_bytes(&n))
	for &s in cv.shapes[:cv.count] {
		mix(&h, mem.slice_to_bytes(s.path.cmds[:]))
		mix(&h, mem.slice_to_bytes(s.path.pts[:]))
		mix(&h, mem.ptr_to_bytes(&s.style))
		if s.clip != nil {
			mix(&h, mem.slice_to_bytes(s.clip.path.cmds[:]))
			mix(&h, mem.slice_to_bytes(s.clip.path.pts[:]))
			rule := s.clip.rule
			mix(&h, mem.ptr_to_bytes(&rule))
		}
	}
	return h
}

// --- recording ----------------------------------------------------------------------

@(private = "file")
xf_apply :: #force_inline proc(xf: [6]f32, p: [2]f32) -> [2]f32 {
	return {xf[0] * p.x + xf[2] * p.y + xf[4], xf[1] * p.x + xf[3] * p.y + xf[5]}
}

@(private = "file")
xf_mul :: proc(a, b: [6]f32) -> [6]f32 {
	// a * b: b applied first.
	return {
		a[0] * b[0] + a[2] * b[1], a[1] * b[0] + a[3] * b[1],
		a[0] * b[2] + a[2] * b[3], a[1] * b[2] + a[3] * b[3],
		a[0] * b[4] + a[2] * b[5] + a[4], a[1] * b[4] + a[3] * b[5] + a[5],
	}
}

@(private = "file")
xf_scale :: proc(xf: [6]f32) -> f32 {return math.sqrt(abs(xf[0] * xf[3] - xf[1] * xf[2]))}

// canvas_commit: the current path as a shape with the current style (fill
// or stroke), points already transformed.
@(private = "file")
canvas_commit :: proc(cv: ^Vector_Canvas, fill: bool) {
	if len(cv.path.cmds) == 0 do return
	context.allocator = Engine_HeapAllocator()
	if cv.count == len(cv.shapes) {
		s: Vector_Shape
		Vector_Path_Init(&s.path)
		append(&cv.shapes, s)
	}
	s := &cv.shapes[cv.count]
	cv.count += 1
	Vector_Path_Clear(&s.path)
	append(&s.path.cmds, ..cv.path.cmds[:])
	append(&s.path.pts, ..cv.path.pts[:])
	s.style = cv.state.style
	s.clip = cv.state.clip
	s.style.fill = fill
	s.style.stroke = !fill
	k := xf_scale(cv.state.xf)
	s.style.strokeWidth *= k
	for i in 0 ..< int(s.style.dash.count) do s.style.dash.values[i] *= k
	s.style.dash.offset *= k
	// Gradients follow the transform they were filled under.
	paint := &s.style.fillPaint if fill else &s.style.strokePaint
	if paint.kind != .Solid {
		pt := paint.transform if paint.transform != {} else XF_IDENTITY
		paint.transform = xf_mul(cv.state.xf, pt)
	}
}

// Vector_Canvas_* : the recording calls (the Lua module's, usable from Odin).
Vector_Canvas_MoveTo :: proc(cv: ^Vector_Canvas, p: [2]f32) {Vector_MoveTo(&cv.path, xf_apply(cv.state.xf, p))}
Vector_Canvas_LineTo :: proc(cv: ^Vector_Canvas, p: [2]f32) {vector_canvas_start(cv); Vector_LineTo(&cv.path, xf_apply(cv.state.xf, p))}
Vector_Canvas_QuadTo :: proc(cv: ^Vector_Canvas, c, p: [2]f32) {
	vector_canvas_start(cv)
	Vector_QuadTo(&cv.path, xf_apply(cv.state.xf, c), xf_apply(cv.state.xf, p))
}
Vector_Canvas_CubicTo :: proc(cv: ^Vector_Canvas, c1, c2, p: [2]f32) {
	vector_canvas_start(cv)
	Vector_CubicTo(&cv.path, xf_apply(cv.state.xf, c1), xf_apply(cv.state.xf, c2), xf_apply(cv.state.xf, p))
}
Vector_Canvas_Close :: proc(cv: ^Vector_Canvas) {if len(cv.path.cmds) > 0 do Vector_Close(&cv.path)}

// (A path that starts with line_to starts at the origin.)
@(private = "file")
vector_canvas_start :: proc(cv: ^Vector_Canvas) {
	if len(cv.path.cmds) == 0 do Vector_MoveTo(&cv.path, xf_apply(cv.state.xf, {0, 0}))
}

// Vector_Canvas_Arc: a circular arc (degrees, clockwise on screen; ccw
// reverses), joined to the current point by a line, as cubics of <= 90.
Vector_Canvas_Arc :: proc(cv: ^Vector_Canvas, c: [2]f32, r: f32, a0_deg, a1_deg: f32, ccw := false) {
	a0 := a0_deg * math.RAD_PER_DEG
	a1 := a1_deg * math.RAD_PER_DEG
	sweep := a1 - a0
	if !ccw && sweep < 0 do sweep += 2 * math.PI * math.ceil(-sweep / (2 * math.PI))
	if ccw && sweep > 0 do sweep -= 2 * math.PI * math.ceil(sweep / (2 * math.PI))
	start := c + [2]f32{math.cos(a0), math.sin(a0)} * r
	if len(cv.path.cmds) == 0 do Vector_Canvas_MoveTo(cv, start)
	else do Vector_Canvas_LineTo(cv, start)
	segs := max(1, int(math.ceil(abs(sweep) / (math.PI / 2) - 1e-4)))
	step := sweep / f32(segs)
	k := 4.0 / 3.0 * math.tan(step / 4) * r
	a := a0
	for _ in 0 ..< segs {
		b := a + step
		p0 := c + [2]f32{math.cos(a), math.sin(a)} * r
		p3 := c + [2]f32{math.cos(b), math.sin(b)} * r
		t0 := [2]f32{-math.sin(a), math.cos(a)} * k
		t3 := [2]f32{-math.sin(b), math.cos(b)} * k
		Vector_Canvas_CubicTo(cv, p0 + t0, p3 - t3, p3)
		a = b
	}
}

Vector_Canvas_Rect :: proc(cv: ^Vector_Canvas, x, y, w, h: f32) {
	Vector_Canvas_MoveTo(cv, {x, y})
	Vector_Canvas_LineTo(cv, {x + w, y})
	Vector_Canvas_LineTo(cv, {x + w, y + h})
	Vector_Canvas_LineTo(cv, {x, y + h})
	Vector_Canvas_Close(cv)
}

Vector_Canvas_Ellipse :: proc(cv: ^Vector_Canvas, c, r: [2]f32) {
	K :: 0.5522847498
	k := r * K
	Vector_Canvas_MoveTo(cv, {c.x + r.x, c.y})
	Vector_Canvas_CubicTo(cv, {c.x + r.x, c.y + k.y}, {c.x + k.x, c.y + r.y}, {c.x, c.y + r.y})
	Vector_Canvas_CubicTo(cv, {c.x - k.x, c.y + r.y}, {c.x - r.x, c.y + k.y}, {c.x - r.x, c.y})
	Vector_Canvas_CubicTo(cv, {c.x - r.x, c.y - k.y}, {c.x - k.x, c.y - r.y}, {c.x, c.y - r.y})
	Vector_Canvas_CubicTo(cv, {c.x + k.x, c.y - r.y}, {c.x + r.x, c.y - k.y}, {c.x + r.x, c.y})
	Vector_Canvas_Close(cv)
}

Vector_Canvas_Fill :: proc(cv: ^Vector_Canvas) {canvas_commit(cv, true)}

// Vector_Canvas_Clip: the current path (by the fill rule) cuts what is drawn
// next, until restore (a clip inside a clip replaces it).
Vector_Canvas_Clip :: proc(cv: ^Vector_Canvas) {
	if len(cv.path.cmds) == 0 do return
	context.allocator = Engine_HeapAllocator()
	if cv.clipCount == len(cv.clips) {
		k := new(Vector_Clip)
		Vector_Path_Init(&k.path)
		append(&cv.clips, k)
	}
	k := cv.clips[cv.clipCount]
	cv.clipCount += 1
	Vector_Path_Clear(&k.path)
	append(&k.path.cmds, ..cv.path.cmds[:])
	append(&k.path.pts, ..cv.path.pts[:])
	k.rule = cv.state.style.fillRule
	cv.state.clip = k
}
Vector_Canvas_Stroke :: proc(cv: ^Vector_Canvas) {canvas_commit(cv, false)}
Vector_Canvas_BeginPath :: proc(cv: ^Vector_Canvas) {Vector_Path_Clear(&cv.path)}

Vector_Canvas_Save :: proc(cv: ^Vector_Canvas) {
	context.allocator = Engine_HeapAllocator()
	append(&cv.stack, cv.state)
}

Vector_Canvas_Restore :: proc(cv: ^Vector_Canvas) {
	if len(cv.stack) > 0 do cv.state = pop(&cv.stack)
}

Vector_Canvas_Translate :: proc(cv: ^Vector_Canvas, d: [2]f32) {cv.state.xf = xf_mul(cv.state.xf, {1, 0, 0, 1, d.x, d.y})}
Vector_Canvas_Rotate :: proc(cv: ^Vector_Canvas, deg: f32) {
	r := deg * math.RAD_PER_DEG
	co, si := math.cos(r), math.sin(r)
	cv.state.xf = xf_mul(cv.state.xf, {co, si, -si, co, 0, 0})
}
Vector_Canvas_Scale :: proc(cv: ^Vector_Canvas, s: [2]f32) {cv.state.xf = xf_mul(cv.state.xf, {s.x, 0, 0, s.y, 0, 0})}

// --- on_draw ------------------------------------------------------------------------

// Script_HasDraw: whether a node's script defines on_draw (looked up once
// per instance; a hot reload looks again).
Script_HasDraw :: proc(node: ^Node, sm: ^ScriptManager) -> bool {
	if node == nil || node.scriptInstance == nil do return false
	inst := cast(^ScriptInstance)node.scriptInstance
	if inst.drawState == 0 {
		inst.drawState = 1
		mgr := sm if sm != nil else (inst.scriptManager if inst.scriptManager != nil else &scriptManager)
		if mgr.isReady && mgr.L != nil && inst.registryRef != 0 {
			L := mgr.L
			lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef))
			lua.getfield(L, -1, "on_draw")
			if lua.type(L, -1) == .FUNCTION do inst.drawState = 2
			lua.pop(L, 2)
		}
	}
	return inst.drawState == 2
}

// Script_RunDraw runs the node's on_draw into its canvas (recording only;
// returns nil when the script has none).
Script_RunDraw :: proc(node: ^Node, ctx: ^GameContext) -> ^Vector_Canvas {
	sm := ctx.scriptManager if ctx != nil else nil
	if !Script_HasDraw(node, sm) do return nil
	inst := cast(^ScriptInstance)node.scriptInstance
	mgr := sm if sm != nil else (inst.scriptManager if inst.scriptManager != nil else &scriptManager)
	if inst.canvas == nil do inst.canvas = Vector_Canvas_Create()
	cv := cast(^Vector_Canvas)inst.canvas
	Vector_Canvas_Begin(cv)
	L := mgr.L
	lua.pushcfunction(L, lua_traceback_error_handler)
	errHandler := lua.gettop(L)
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef))
	lua.getfield(L, -1, "on_draw")
	lua.pushvalue(L, -2)
	prevCanvas, prevInst := vectorCanvas, mgr.currentInstance
	vectorCanvas, mgr.currentInstance = cv, inst
	status := lua.pcall(L, 1, 0, errHandler)
	vectorCanvas, mgr.currentInstance = prevCanvas, prevInst
	if status != 0 {
		Script_Problem(.Error, "[ScriptInstance] Error in on_draw() for '%s': %s", inst.modulePath, lua.tostring(L, -1))
		lua.pop(L, 1)
	}
	lua.pop(L, 2) // self, errHandler
	Vector_Canvas_Finish(cv)
	return cv
}

// Script_DrawNode runs the node's on_draw and draws the result at the
// node's transform (the render passes call it after the node's own render).
Script_DrawNode :: proc(node: ^Node, ctx: ^GameContext) {
	if !rl.IsWindowReady() do return
	if cv := Script_RunDraw(node, ctx); cv != nil {
		Vector_Canvas_Draw(cv, node.globalPosition, node.globalRotation, node.globalScale)
	}
}

// --- the Lua module -----------------------------------------------------------------

@(private = "file")
canvas_or_error :: proc "contextless" (L: ^lua.State) -> ^Vector_Canvas {
	if vectorCanvas == nil {
		lua.L_error(L, "Vector: draw inside a script's on_draw()")
	}
	return vectorCanvas
}

@(private = "file")
num :: #force_inline proc "contextless" (L: ^lua.State, i: c.int, def: f32 = 0) -> f32 {
	return f32(lua.tonumber(L, i)) if lua.type(L, i) == .NUMBER else def
}

@(private = "file")
vec :: #force_inline proc "contextless" (L: ^lua.State, i: c.int) -> [2]f32 {return {num(L, i), num(L, i + 1)}}

// lua_color: (r, g, b[, a]) 0..1, {r, g, b[, a]} 0..1, or "#rrggbb[aa]"
// (Lua_ArgColor).
@(private = "file")
lua_color :: proc(L: ^lua.State, i: c.int) -> [4]u8 {
	col, _, ok := Lua_ArgColor(L, i)
	if !ok do return {0, 0, 0, 255}
	return {col.r, col.g, col.b, col.a}
}

// lua_paint: a gradient table made by Vector.linear_gradient /
// radial_gradient (kind, points, stops, spread).
@(private = "file")
lua_paint :: proc(L: ^lua.State, i: c.int) -> (p: Vector_Paint, ok: bool) {
	if lua.type(L, i) != .TABLE do return
	field :: proc(L: ^lua.State, i: c.int, name: cstring) -> f32 {
		lua.getfield(L, i, name)
		defer lua.pop(L, 1)
		return f32(lua.tonumber(L, -1)) if lua.type(L, -1) == .NUMBER else 0
	}
	lua.getfield(L, i, "kind")
	kind := string(lua.tostring(L, -1)) if lua.type(L, -1) == .STRING else ""
	lua.pop(L, 1)
	switch kind {
	case "linear":
		p.kind = .Linear
		p.p0 = {field(L, i, "x0"), field(L, i, "y0")}
		p.p1 = {field(L, i, "x1"), field(L, i, "y1")}
	case "radial":
		p.kind = .Radial
		p.center = {field(L, i, "cx"), field(L, i, "cy")}
		p.radius = field(L, i, "r")
	case:
		return
	}
	lua.getfield(L, i, "spread")
	switch string(lua.tostring(L, -1)) if lua.type(L, -1) == .STRING else "" {
	case "reflect": p.spread = .Reflect
	case "repeat": p.spread = .Repeat
	}
	lua.pop(L, 1)
	lua.getfield(L, i, "stops")
	if lua.type(L, -1) == .TABLE {
		n := min(int(lua.rawlen(L, -1)), VECTOR_MAX_STOPS)
		for k in 0 ..< n {
			lua.rawgeti(L, -1, lua.Integer(k + 1)) // {offset, colour}
			if lua.type(L, -1) == .TABLE {
				lua.rawgeti(L, -1, 1)
				off := f32(lua.tonumber(L, -1))
				lua.pop(L, 1)
				lua.rawgeti(L, -1, 2)
				col := lua_color(L, lua.gettop(L))
				lua.pop(L, 1)
				p.stops[p.stopCount] = {clamp(off, 0, 1), col}
				p.stopCount += 1
			}
			lua.pop(L, 1)
		}
	}
	lua.pop(L, 1)
	return p, p.stopCount > 0
}

@(private = "file")
gradient_table :: proc(L: ^lua.State, kind: cstring, nums: []cstring, first: c.int, stopsArg: c.int, spreadArg: c.int) {
	lua.newtable(L)
	lua.pushstring(L, kind)
	lua.setfield(L, -2, "kind")
	for name, k in nums {
		lua.pushnumber(L, lua.Number(num(L, first + c.int(k))))
		lua.setfield(L, -2, name)
	}
	if lua.type(L, stopsArg) == .TABLE {
		lua.pushvalue(L, stopsArg)
		lua.setfield(L, -2, "stops")
	}
	if lua.type(L, spreadArg) == .STRING {
		lua.pushvalue(L, spreadArg)
		lua.setfield(L, -2, "spread")
	}
}

@(private = "file")
lv_begin_path :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); Vector_Canvas_BeginPath(canvas_or_error(L)); return 0}
@(private = "file")
lv_move_to :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); Vector_Canvas_MoveTo(canvas_or_error(L), vec(L, 1)); return 0}
@(private = "file")
lv_line_to :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); Vector_Canvas_LineTo(canvas_or_error(L), vec(L, 1)); return 0}
@(private = "file")
lv_quad_to :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); Vector_Canvas_QuadTo(canvas_or_error(L), vec(L, 1), vec(L, 3)); return 0}
@(private = "file")
lv_cubic_to :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); Vector_Canvas_CubicTo(canvas_or_error(L), vec(L, 1), vec(L, 3), vec(L, 5)); return 0}
@(private = "file")
lv_close_path :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); Vector_Canvas_Close(canvas_or_error(L)); return 0}
@(private = "file")
lv_arc :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	Vector_Canvas_Arc(canvas_or_error(L), vec(L, 1), num(L, 3), num(L, 4), num(L, 5), bool(lua.toboolean(L, 6)))
	return 0
}
@(private = "file")
lv_rect :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); Vector_Canvas_Rect(canvas_or_error(L), num(L, 1), num(L, 2), num(L, 3), num(L, 4)); return 0}
@(private = "file")
lv_circle :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); r := num(L, 3); Vector_Canvas_Ellipse(canvas_or_error(L), vec(L, 1), {r, r}); return 0}
@(private = "file")
lv_ellipse :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); Vector_Canvas_Ellipse(canvas_or_error(L), vec(L, 1), vec(L, 3)); return 0}
@(private = "file")
lv_fill :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); Vector_Canvas_Fill(canvas_or_error(L)); return 0}
@(private = "file")
lv_stroke :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); Vector_Canvas_Stroke(canvas_or_error(L)); return 0}
@(private = "file")
lv_clip :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); Vector_Canvas_Clip(canvas_or_error(L)); return 0}
@(private = "file")
lv_fill_color :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cv := canvas_or_error(L)
	cv.state.style.fillColor = lua_color(L, 1)
	cv.state.style.fillPaint = {}
	return 0
}
@(private = "file")
lv_stroke_color :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cv := canvas_or_error(L)
	cv.state.style.strokeColor = lua_color(L, 1)
	cv.state.style.strokePaint = {}
	return 0
}
@(private = "file")
lv_fill_paint :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cv := canvas_or_error(L)
	if p, ok := lua_paint(L, 1); ok {cv.state.style.fillPaint = p; cv.state.style.fillColor = {255, 255, 255, 255}}
	return 0
}
@(private = "file")
lv_stroke_paint :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cv := canvas_or_error(L)
	if p, ok := lua_paint(L, 1); ok {cv.state.style.strokePaint = p; cv.state.style.strokeColor = {255, 255, 255, 255}}
	return 0
}
@(private = "file")
lv_linear_gradient :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	gradient_table(L, "linear", {"x0", "y0", "x1", "y1"}, 1, 5, 6)
	return 1
}
@(private = "file")
lv_radial_gradient :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	gradient_table(L, "radial", {"cx", "cy", "r"}, 1, 4, 5)
	return 1
}
@(private = "file")
lv_stroke_width :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); canvas_or_error(L).state.style.strokeWidth = max(num(L, 1, 1), 0); return 0}
@(private = "file")
lv_miter_limit :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); canvas_or_error(L).state.style.miterLimit = max(num(L, 1, 4), 1); return 0}
@(private = "file")
lv_opacity :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); canvas_or_error(L).state.style.opacity = clamp(num(L, 1, 1), 0.0001, 1); return 0}
@(private = "file")
lv_line_join :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cv := canvas_or_error(L)
	switch string(lua.tostring(L, 1)) if lua.type(L, 1) == .STRING else "" {
	case "round": cv.state.style.join = .Round
	case "bevel": cv.state.style.join = .Bevel
	case: cv.state.style.join = .Miter
	}
	return 0
}
@(private = "file")
lv_line_cap :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cv := canvas_or_error(L)
	switch string(lua.tostring(L, 1)) if lua.type(L, 1) == .STRING else "" {
	case "round": cv.state.style.cap = .Round
	case "square": cv.state.style.cap = .Square
	case: cv.state.style.cap = .Butt
	}
	return 0
}
@(private = "file")
lv_fill_rule :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cv := canvas_or_error(L)
	cv.state.style.fillRule = .EvenOdd if lua.type(L, 1) == .STRING && string(lua.tostring(L, 1)) == "evenodd" else .NonZero
	return 0
}
@(private = "file")
lv_dash :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	cv := canvas_or_error(L)
	d := Vector_Dash{offset = num(L, 2)}
	if lua.type(L, 1) == .TABLE {
		n := min(int(lua.rawlen(L, 1)), 8)
		for k in 0 ..< n {
			lua.rawgeti(L, 1, lua.Integer(k + 1))
			d.values[k] = max(f32(lua.tonumber(L, -1)), 0)
			lua.pop(L, 1)
		}
		d.count = u8(n)
		// (An odd count repeats, as in SVG: 5 -> 5, 5.)
		if n % 2 == 1 && n * 2 <= 8 {
			for k in 0 ..< n do d.values[n + k] = d.values[k]
			d.count = u8(n * 2)
		}
	}
	cv.state.style.dash = d
	return 0
}
@(private = "file")
lv_save :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); Vector_Canvas_Save(canvas_or_error(L)); return 0}
@(private = "file")
lv_restore :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); Vector_Canvas_Restore(canvas_or_error(L)); return 0}
@(private = "file")
lv_translate :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); Vector_Canvas_Translate(canvas_or_error(L), vec(L, 1)); return 0}
@(private = "file")
lv_rotate :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); Vector_Canvas_Rotate(canvas_or_error(L), num(L, 1)); return 0}
@(private = "file")
lv_scale :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sx := num(L, 1, 1)
	Vector_Canvas_Scale(canvas_or_error(L), {sx, num(L, 2, sx)})
	return 0
}

// Script_RegisterVectorModule creates the global Vector table.
Script_RegisterVectorModule :: proc(L: ^lua.State) {
	lua.newtable(L)
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "begin_path", lv_begin_path)
	reg(L, "move_to", lv_move_to)
	reg(L, "line_to", lv_line_to)
	reg(L, "quad_to", lv_quad_to)
	reg(L, "cubic_to", lv_cubic_to)
	reg(L, "arc", lv_arc)
	reg(L, "close_path", lv_close_path)
	reg(L, "rect", lv_rect)
	reg(L, "circle", lv_circle)
	reg(L, "ellipse", lv_ellipse)
	reg(L, "fill", lv_fill)
	reg(L, "stroke", lv_stroke)
	reg(L, "clip", lv_clip)
	reg(L, "fill_color", lv_fill_color)
	reg(L, "stroke_color", lv_stroke_color)
	reg(L, "fill_paint", lv_fill_paint)
	reg(L, "stroke_paint", lv_stroke_paint)
	reg(L, "linear_gradient", lv_linear_gradient)
	reg(L, "radial_gradient", lv_radial_gradient)
	reg(L, "stroke_width", lv_stroke_width)
	reg(L, "line_join", lv_line_join)
	reg(L, "line_cap", lv_line_cap)
	reg(L, "miter_limit", lv_miter_limit)
	reg(L, "dash", lv_dash)
	reg(L, "fill_rule", lv_fill_rule)
	reg(L, "opacity", lv_opacity)
	reg(L, "save", lv_save)
	reg(L, "restore", lv_restore)
	reg(L, "translate", lv_translate)
	reg(L, "rotate", lv_rotate)
	reg(L, "scale", lv_scale)
	lua.setglobal(L, "Vector")
}

// (runtime is imported for Script_Context's type.)
@(private = "file")
_ :: runtime.Context
