package engine

import "core:c"
import "core:math"
import "core:math/noise"
import "core:strings"
import lua "lua54"

// ============================================================================
// AdvancedCameraNode (docs/advanced_camera.md): a virtual camera in the
// style of Phantom Camera / Cinemachine. Any number of them sit in a scene;
// the scene's current CameraNode (the host) shows the highest-priority one
// and blends (tweens) to another when it takes over. Each decides where to
// look:
//
//   follow modes   None (stays), Glued (exactly on the target), Simple
//                  (with an offset, optional damping and look-ahead),
//                  Group (frames several targets, auto-zooms), Path (on a
//                  PathNode, the closest point to the target), Framed
//                  (moves only when the target leaves a dead zone)
//   limits         a rectangle, a node's bounds (TileMap, LDtk level,
//                  NavigationRegion, StaticBody shapes), or the LDtk level
//                  the target is in - switching (smoothly) when it walks
//                  into a linked neighbour level
//   shake          trauma (trauma-gd): add_trauma(0..1) stacks to 1 and
//                  decays per second; the shake is trauma ^ exponent times
//                  the offset / rotation intensity, from smooth noise
//
// Inactive cameras keep tracking (cheap: a few vector ops), so a switch
// blends from where the new camera is right now.
// ============================================================================

AdvCam_Follow :: enum u8 {None, Glued, Simple, Group, Path, Framed}
AdvCam_Axis :: enum u8 {None, X, Y, XY}
AdvCam_Limits :: enum u8 {None, Rect, Node, LdtkLevel}

AdvancedCameraNode :: struct {
	using node: Node,
	priority:       int `gui:"true" min:"-100" max:"100"`,
	followMode:     AdvCam_Follow `gui:"true"`,
	followTarget:   string `gui:"true"`, // node path (Glued / Simple / Path / Framed; Group's first)
	followTargets:  string `gui:"true"`, // more node paths for Group, comma separated
	followPath:     string `gui:"true"`, // a PathNode (Path mode)
	followOffset:   [2]f32 `gui:"true" min:"-2000" max:"2000"`,
	damping:        f32 `gui:"true" min:"0" max:"5"`,        // smoothing time (s); 0 = locked on
	axisLock:       AdvCam_Axis `gui:"true"`,              // don't follow along these axes
	lookahead:      f32 `gui:"true" min:"0" max:"2"`,        // seconds of the target's velocity to look ahead
	deadZone:       [2]f32 `gui:"true" min:"0" max:"1"`,    // Framed: fraction of the view the target can roam
	zoom:           f32 `gui:"true" min:"0.05" max:"20"`,
	autoZoom:       bool `gui:"true"`,                      // Group: zoom to fit the targets
	autoZoomMin:    f32 `gui:"true" min:"0.05" max:"20"`,
	autoZoomMax:    f32 `gui:"true" min:"0.05" max:"20"`,
	autoZoomMargin: f32 `gui:"true" min:"0" max:"2000"`,     // px around the targets
	limitMode:      AdvCam_Limits `gui:"true"`,
	limitRect:      [4]f32 `gui:"true"`,                    // left, top, right, bottom (Rect)
	limitNode:      string `gui:"true"`,                    // node path (Node)
	limitMargin:    f32 `gui:"true" min:"-500" max:"500"`,   // shrinks (+) / grows (-) the limits
	limitBlend:     f32 `gui:"true" min:"0" max:"5"`,        // seconds to glide to new limits (LDtk levels)
	blendTime:      f32 `gui:"true" min:"0" max:"10"`,       // the host's blend to this camera (s)
	blendEase:      Ease `gui:"true"`,
	snapToPixel:    bool `gui:"true"`,
	// Trauma shake (trauma-gd).
	shakeIntensity: f32 `gui:"true" min:"0" max:"500"`,      // px at trauma 1
	shakeRotation:  f32 `gui:"true" min:"0" max:"45"`,       // degrees at trauma 1
	shakeDecay:     f32 `gui:"true" min:"0" max:"20"`,       // trauma lost per second
	shakeFrequency: f32 `gui:"true" min:"0.1" max:"100"`,
	traumaExponent: f32 `gui:"true" min:"1" max:"4"`,
	trauma:         f32 `gui:"true" save:"false"`,
	active:         bool `gui:"true" save:"false"`,          // the host shows it now
	// Runtime.
	lookAt:       [2]f32, // where it looks (world)
	velocity:     [2]f32, // damping state
	curZoom:      f32,
	lastTarget:   [2]f32,
	targetVel:    [2]f32,
	limitCur:     [4]f32, // the limits now (gliding to limitWant)
	limitWant:    [4]f32,
	hasLimit:     bool,
	limitLevel:   ^LdtkLevel, // the LDtk level the limits are from
	noiseT:       f32,
	started:      bool,
	previewOf:    ^Node, // set on a copy made by AdvCam_Preview (paths resolve from the original)
	onActive:     EventSubject, // "became_active"
	onInactive:   EventSubject, // "became_inactive"
}

AdvancedCameraNode_Create :: proc(scene: ^Scene, name: string = "AdvancedCamera", parent: ^Node = nil) -> ^AdvancedCameraNode {
	c := CreateNode(scene.manager, AdvancedCameraNode)
	c.name = strings.clone(name, c.allocator)
	c.followMode = .Simple
	c.zoom = 1
	c.autoZoomMin, c.autoZoomMax, c.autoZoomMargin = 0.25, 2, 120
	c.deadZone = {0.3, 0.3}
	c.blendTime = 0.8
	c.blendEase = .In_Out_Sine
	c.limitBlend = 0.4
	c.shakeIntensity, c.shakeRotation, c.shakeDecay, c.shakeFrequency, c.traumaExponent = 24, 2, 1.5, 12, 2
	c.update = AdvancedCameraNode_Update
	c.onDestroy = proc(n: ^Node, ctx: ^GameContext) {
		cc := cast(^AdvancedCameraNode)n
		DestroySubject(&cc.onActive)
		DestroySubject(&cc.onInactive)
	}
	InitializeSubject(&c.onActive, "became_active", c)
	InitializeSubject(&c.onInactive, "became_inactive", c)
	scene->addNode(c, parent)
	return c
}

// AdvCam_AddTrauma stacks trauma (capped at 1).
AdvCam_AddTrauma :: proc(c: ^AdvancedCameraNode, amount: f32) {c.trauma = clamp(c.trauma + amount, 0, 1)}

@(private = "file")
advcam_node :: proc(c: ^AdvancedCameraNode, m: ^NodeManager, path: string) -> ^Node {
	if path == "" || m == nil do return nil
	p := strings.trim_space(path)
	if n := Node_ResolvePath(m, c.previewOf if c.previewOf != nil else c, p); n != nil do return n
	// A bare name ("Player"): the first node with it (scripts set these).
	if !strings.contains(p, "/") do for n in m.nodes do if n != nil && !n.removing && n.name == p do return n
	return nil
}

// advcam_targets: the follow targets' world positions (temp).
@(private = "file")
advcam_targets :: proc(c: ^AdvancedCameraNode, m: ^NodeManager) -> [][2]f32 {
	out := make([dynamic][2]f32, context.temp_allocator)
	if n := advcam_node(c, m, c.followTarget); n != nil do append(&out, Node_ComputeWorldPosition(m, n))
	if c.followMode == .Group && c.followTargets != "" {
		for part in strings.split(c.followTargets, ",", context.temp_allocator) {
			if n := advcam_node(c, m, part); n != nil do append(&out, Node_ComputeWorldPosition(m, n))
		}
	}
	return out[:]
}

// AdvCam_ViewSize: the world size the camera shows at a zoom.
AdvCam_ViewSize :: proc(ctx: ^GameContext, zoom: f32) -> [2]f32 {
	vw, vh: f32 = 1280, 720
	if ctx != nil && ctx.game != nil && ctx.game.virtualSize.x > 0 do vw, vh = ctx.game.virtualSize.x, ctx.game.virtualSize.y
	z := max(zoom, 0.01)
	return {vw / z, vh / z}
}

// advcam_limits: the limits it wants now (left, top, right, bottom).
@(private = "file")
advcam_limits :: proc(c: ^AdvancedCameraNode, m: ^NodeManager, target: [2]f32) -> ([4]f32, bool) {
	switch c.limitMode {
	case .None: return {}, false
	case .Rect: return c.limitRect, true
	case .Node:
		n := advcam_node(c, m, c.limitNode)
		if n == nil do return {}, false
		return Node_WorldBounds(n, m)
	case .LdtkLevel:
		// The level the target is in (of any LDtk node in the scene).
		if m == nil do return {}, false
		for nn in m.nodes {
			if nn == nil || nn.typeId != LdtkLevelNode || !nn.enabled do continue
			ln := cast(^LdtkLevelNode)nn
			for lvl in ln.activeLevels {
				o := ln.globalPosition + LdtkLevelNode_LevelOffset(ln, lvl) * ln.globalScale
				sz := [2]f32{f32(lvl.pxWid), f32(lvl.pxHei)} * ln.globalScale
				if target.x >= o.x && target.y >= o.y && target.x < o.x + sz.x && target.y < o.y + sz.y {
					c.limitLevel = lvl
					return {o.x, o.y, o.x + sz.x, o.y + sz.y}, true
				}
			}
		}
		return c.limitWant, c.hasLimit // (between levels: keep the last)
	}
	return {}, false
}

// Node_WorldBounds: a node's world rectangle for camera limits (left, top,
// right, bottom) - a tile map, an LDtk level (its active levels), a
// navigation region, a static body's shapes.
Node_WorldBounds :: proc(n: ^Node, m: ^NodeManager) -> ([4]f32, bool) {
	switch n.typeId {
	case TileMapNode:
		tm := cast(^TileMapNode)n
		if tm.layout == .Square {
			a := TileMapNode_CellCorner(tm, {0, 0})
			b := TileMapNode_CellCorner(tm, tm.mapSize)
			return {min(a.x, b.x), min(a.y, b.y), max(a.x, b.x), max(a.y, b.y)}, true
		}
		o := TileMapNode_MapOutline(tm)
		r := tilemap_aabb(o)
		return {r.x, r.y, r.x + r.width, r.y + r.height}, true
	case LdtkLevelNode:
		ln := cast(^LdtkLevelNode)n
		have := false
		r: [4]f32
		for lvl in ln.activeLevels {
			o := ln.globalPosition + LdtkLevelNode_LevelOffset(ln, lvl) * ln.globalScale
			e := o + [2]f32{f32(lvl.pxWid), f32(lvl.pxHei)} * ln.globalScale
			if !have do r, have = {o.x, o.y, e.x, e.y}, true
			r = {min(r[0], o.x), min(r[1], o.y), max(r[2], e.x), max(r[3], e.y)}
		}
		return r, have
	case NavigationRegionNode:
		nr := cast(^NavigationRegionNode)n
		return {nr.globalPosition.x, nr.globalPosition.y, nr.globalPosition.x + nr.size.x, nr.globalPosition.y + nr.size.y}, true
	case StaticBodyNode:
		sb := cast(^StaticBodyNode)n
		if len(sb.shapes) == 0 do return {}, false
		rect: [4]f32
		haveRect := false
		for s in sb.shapes {
			half := s.size * 0.5 * sb.globalScale if s.type == .Box || s.type == .RoundedBox else [2]f32{s.radius, s.radius} * sb.globalScale
			c := sb.globalPosition + s.offset * sb.globalScale
			sr := [4]f32{c.x - abs(half.x), c.y - abs(half.y), c.x + abs(half.x), c.y + abs(half.y)}
			if !haveRect {
				rect, haveRect = sr, true
			} else {
				rect = {min(rect[0], sr[0]), min(rect[1], sr[1]), max(rect[2], sr[2]), max(rect[3], sr[3])}
			}
		}
		return rect, haveRect
	}
	return {}, false
}

AdvancedCameraNode_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	c := cast(^AdvancedCameraNode)node
	m := ctx.scene.manager if ctx != nil && ctx.scene != nil else nil
	dt := max(dt, 0.0001)
	// No camera to show it: add one (not saved with the scene).
	if c.previewOf == nil && ctx != nil && ctx.scene != nil && ctx.scene.camera == nil {
		h := CameraNode_Create(ctx.scene, "CameraHost", true)
		h.transient = true
	}
	targets := advcam_targets(c, m)
	if !c.started {
		// Starts on its target (or where it's placed).
		c.lookAt, c.curZoom, c.started = c.globalPosition, c.zoom, true
		if len(targets) > 0 && c.followMode != .None do c.lookAt, c.lastTarget = targets[0] + c.followOffset, targets[0]
	}
	want := c.lookAt
	zoom := c.zoom
	tpos := targets[0] if len(targets) > 0 else c.lookAt
	// Target velocity (look-ahead).
	if len(targets) > 0 {
		v := (tpos - c.lastTarget) / dt
		c.targetVel += (v - c.targetVel) * min(1, dt * 8)
		c.lastTarget = tpos
	}
	view := AdvCam_ViewSize(ctx, c.curZoom)
	mode := c.followMode
	if len(targets) == 0 && mode != .Path do mode = .None // (nothing to follow: stay)
	switch mode {
	case .None: if c.followMode == .None do want = c.globalPosition
	case .Glued: want = tpos
	case .Simple: want = tpos + c.followOffset + c.targetVel * c.lookahead
	case .Group:
		if len(targets) == 0 do break
		mn, mx := targets[0], targets[0]
		for p in targets[1:] do mn, mx = {min(mn.x, p.x), min(mn.y, p.y)}, {max(mx.x, p.x), max(mx.y, p.y)}
		want = (mn + mx) * 0.5 + c.followOffset
		if c.autoZoom {
			span := mx - mn + c.autoZoomMargin * 2
			base := AdvCam_ViewSize(ctx, 1)
			zoom = clamp(min(base.x / max(span.x, 1), base.y / max(span.y, 1)), c.autoZoomMin, c.autoZoomMax)
		}
	case .Path:
		if p := advcam_node(c, m, c.followPath); p != nil && p.typeId == PathNode {
			pn := cast(^PathNode)p
			lp, _ := PathNode_SampleLocal(pn, PathNode_ClosestOffset(pn, tpos))
			want = PathNode_ToWorld(pn, lp) + c.followOffset
		}
	case .Framed:
		// Only when the target leaves the dead zone (a fraction of the view).
		half := view * c.deadZone * 0.5
		d := tpos + c.followOffset - c.lookAt
		if d.x > half.x do want.x = c.lookAt.x + (d.x - half.x)
		else if d.x < -half.x do want.x = c.lookAt.x + (d.x + half.x)
		if d.y > half.y do want.y = c.lookAt.y + (d.y - half.y)
		else if d.y < -half.y do want.y = c.lookAt.y + (d.y + half.y)
	}
	// Axis lock.
	if c.axisLock == .X || c.axisLock == .XY do want.x = c.lookAt.x
	if c.axisLock == .Y || c.axisLock == .XY do want.y = c.lookAt.y
	// Damping (critically damped spring; Framed and Glued snap unless damped).
	if c.damping > 0 && c.followMode != .Glued {
		for k in 0 ..< 2 do want[k] = Camera_SmoothDamp(c.lookAt[k], want[k], &c.velocity[k], c.damping, math.F32_MAX, dt)
	}
	c.lookAt = want
	c.curZoom += (zoom - c.curZoom) * min(1, dt * 6) if c.followMode == .Group && c.autoZoom else zoom - c.curZoom
	// Limits: the view stays inside (centred when it's bigger than them).
	lim, has := advcam_limits(c, m, tpos)
	if has {
		lim = {lim[0] + c.limitMargin, lim[1] + c.limitMargin, lim[2] - c.limitMargin, lim[3] - c.limitMargin}
		if !c.hasLimit || c.limitBlend <= 0 do c.limitCur = lim
		else {
			k := min(1, dt / c.limitBlend * 3)
			for i in 0 ..< 4 do c.limitCur[i] += (lim[i] - c.limitCur[i]) * k
		}
		c.limitWant, c.hasLimit = lim, true
		v := AdvCam_ViewSize(ctx, c.curZoom) * 0.5
		l := c.limitCur
		c.lookAt.x = (l[0] + l[2]) * 0.5 if l[2] - l[0] < v.x * 2 else clamp(c.lookAt.x, l[0] + v.x, l[2] - v.x)
		c.lookAt.y = (l[1] + l[3]) * 0.5 if l[3] - l[1] < v.y * 2 else clamp(c.lookAt.y, l[1] + v.y, l[3] - v.y)
	} else {
		c.hasLimit = false
	}
	if c.snapToPixel do c.lookAt = {math.round(c.lookAt.x), math.round(c.lookAt.y)}
	// Trauma decays.
	c.trauma = max(c.trauma - c.shakeDecay * dt, 0)
	c.noiseT += dt
}

// AdvCam_Shake: this frame's shake offset (px) and rotation (degrees).
AdvCam_Shake :: proc(c: ^AdvancedCameraNode) -> ([2]f32, f32) {
	if c.trauma <= 0 do return {}, 0
	amt := math.pow(c.trauma, max(c.traumaExponent, 1))
	t := f64(c.noiseT * c.shakeFrequency)
	nx := noise.noise_2d(1, {t, 0})
	ny := noise.noise_2d(2, {t, 7})
	nr := noise.noise_2d(3, {t, 13})
	return {nx, ny} * c.shakeIntensity * amt, nr * c.shakeRotation * amt
}

// --- the host (a CameraNode) ----------------------------------------------------------

@(private = "file")
host: struct {
	camera:  rawptr, // the host it was for
	active:  ^AdvancedCameraNode,
	from:    [4]f32, // position x, y, zoom, rotation when the blend began
	t:       f32,    // seconds into the blend
	dur:     f32,
	ease:    Ease,
}

// AdvCam_Pick: the highest-priority enabled advanced camera (later in the
// tree wins a tie), or nil.
AdvCam_Pick :: proc(m: ^NodeManager) -> ^AdvancedCameraNode {
	if m == nil do return nil
	best: ^AdvancedCameraNode
	for n in m.advCameras {
		c := cast(^AdvancedCameraNode)n
		if !c.enabled || c.removing do continue
		if best == nil || c.priority >= best.priority do best = c
	}
	return best
}

// AdvCam_Host drives a CameraNode from the advanced cameras (CameraNode's
// update); false when the scene has none (the camera does its own thing).
AdvCam_Host :: proc(camera: ^CameraNode, ctx: ^GameContext, dt: f32) -> bool {
	m := ctx.scene.manager if ctx != nil && ctx.scene != nil else nil
	pick := AdvCam_Pick(m)
	if pick == nil {
		if host.camera == camera do host = {}
		return false
	}
	if host.camera != camera do host = {camera = camera}
	if pick != host.active {
		// A new camera: blend from what the host shows now.
		if host.active != nil && Node_IsAlive(host.active) {
			host.active.active = false
			host.active.onInactive->notify(host.active, nil, ctx)
		}
		host.from = {camera.currentPosition.x, camera.currentPosition.y, camera.currentZoom, camera.currentRotation}
		host.t = 0
		host.dur = pick.blendTime if host.active != nil else 0 // (the first one: at once)
		host.ease = pick.blendEase
		host.active = pick
		pick.active = true
		pick.onActive->notify(pick, nil, ctx)
	}
	host.t += dt
	k: f32 = 1
	if host.dur > 0 && host.t < host.dur do k = Ease_Apply(host.ease, host.t / host.dur)
	to := [4]f32{pick.lookAt.x, pick.lookAt.y, pick.curZoom, pick.globalRotation}
	cur := host.from + (to - host.from) * k
	camera.currentPosition, camera.targetPosition = {cur.x, cur.y}, {cur.x, cur.y}
	camera.currentZoom, camera.targetZoom = cur.z, cur.z
	camera.currentRotation, camera.targetRotation = cur.w, cur.w
	camera.currentOffset = {}
	off, rot := AdvCam_Shake(pick)
	camera.shakeOffset, camera.shakeRotation, camera.shakeZoom = off, rot, 0
	return true
}

// AdvCam_Active: the camera the host shows (or nil).
AdvCam_Active :: proc() -> ^AdvancedCameraNode {
	if host.active != nil && Node_IsAlive(host.active) do return host.active
	return nil
}

// AdvCam_Blending: a blend is under way.
AdvCam_Blending :: proc() -> bool {return host.active != nil && host.dur > 0 && host.t < host.dur}

// AdvCam_Preview: where a camera would look, its zoom and limits, right
// now and without damping - for the editor (it runs on a copy: the camera
// itself is untouched).
AdvCam_Preview :: proc(c: ^AdvancedCameraNode, ctx: ^GameContext) -> (center: [2]f32, zoom: f32, limits: [4]f32, hasLimits: bool) {
	tmp := c^
	tmp.previewOf = c
	tmp.started, tmp.damping, tmp.limitBlend, tmp.hasLimit, tmp.velocity, tmp.targetVel = false, 0, 0, false, {}, {}
	AdvancedCameraNode_Update(&tmp, ctx, 0.0001)
	if tmp.followMode == .Framed {
		if n := advcam_node(&tmp, ctx.scene.manager if ctx != nil && ctx.scene != nil else nil, tmp.followTarget); n != nil {
			tmp.lookAt = Node_ComputeWorldPosition(ctx.scene.manager, n) + tmp.followOffset
		}
	}
	return tmp.lookAt, tmp.curZoom, tmp.limitCur, tmp.hasLimit
}

// AdvCam_MakeActive raises a camera's priority just above every other one.
AdvCam_MakeActive :: proc(c: ^AdvancedCameraNode, m: ^NodeManager) {
	top := c.priority
	if m != nil do for n in m.advCameras do if n != c do top = max(top, (cast(^AdvancedCameraNode)n).priority + 1)
	c.priority = top
}

// AdvCam_Snap jumps a camera to where it wants to be (no damping, limits
// at once), and ends the host's blend if it's the active one.
AdvCam_Snap :: proc(c: ^AdvancedCameraNode, ctx: ^GameContext) {
	c.lookAt, c.curZoom, c.limitCur, c.hasLimit = AdvCam_Preview(c, ctx)
	c.limitWant, c.velocity = c.limitCur, {}
	if host.active == c do host.t = host.dur
}

// --- Lua -------------------------------------------------------------------------------
// cam:add_trauma(amount)   stack shake (0..1)
// cam:make_active()        priority above every other camera
// cam:is_active()          the host shows it
// cam:snap()               jump to the target now (no damping / blend)
// Camera.add_trauma(amount) / Camera.get_active() - the active advanced camera

@(private = "file")
lua_advcam :: proc(L: ^lua.State) -> ^AdvancedCameraNode {
	n, ok := to_node_userdata(L, 1)
	return cast(^AdvancedCameraNode)n if ok && n.typeId == AdvancedCameraNode else nil
}

@(private = "file")
lua_advcam_ctx :: proc(L: ^lua.State) -> ^GameContext {
	sm := get_script_manager(L)
	return &sm.game.gameContext if sm != nil && sm.game != nil else nil
}

@(private = "file")
lua_advcam_add_trauma :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if c := lua_advcam(L); c != nil do AdvCam_AddTrauma(c, f32(lua.tonumber(L, 2)))
	return 0
}

@(private = "file")
lua_advcam_make_active :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	ctx := lua_advcam_ctx(L)
	if c := lua_advcam(L); c != nil do AdvCam_MakeActive(c, ctx.scene.manager if ctx != nil && ctx.scene != nil else nil)
	return 0
}

@(private = "file")
lua_advcam_is_active :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	c := lua_advcam(L)
	lua.pushboolean(L, b32(c != nil && c.active))
	return 1
}

@(private = "file")
lua_advcam_snap :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if c := lua_advcam(L); c != nil do AdvCam_Snap(c, lua_advcam_ctx(L))
	return 0
}

@(private = "file")
lua_camera_add_trauma :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if c := AdvCam_Active(); c != nil do AdvCam_AddTrauma(c, f32(lua.tonumber(L, 1)))
	return 0
}

@(private = "file")
lua_camera_get_active :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if c := AdvCam_Active(); c != nil do push_node_userdata(L, c)
	else do lua.pushnil(L)
	return 1
}

// Script_RegisterAdvCamNodeBindings adds the methods to the node metatable
// (on the stack).
Script_RegisterAdvCamNodeBindings :: proc(L: ^lua.State) {
	lua.pushcfunction(L, lua_advcam_add_trauma); lua.setfield(L, -2, "add_trauma")
	lua.pushcfunction(L, lua_advcam_make_active); lua.setfield(L, -2, "make_active")
	lua.pushcfunction(L, lua_advcam_is_active); lua.setfield(L, -2, "is_active")
	lua.pushcfunction(L, lua_advcam_snap); lua.setfield(L, -2, "snap")
}

// Script_RegisterAdvCamCameraBindings adds Camera.add_trauma / get_active
// (the Camera table on the stack).
Script_RegisterAdvCamCameraBindings :: proc(L: ^lua.State) {
	lua.pushcfunction(L, lua_camera_add_trauma); lua.setfield(L, -2, "add_trauma")
	lua.pushcfunction(L, lua_camera_get_active); lua.setfield(L, -2, "get_active")
	Script_RegisterFeelCameraBindings(L) // Camera.kick (game_feel.odin)
}
