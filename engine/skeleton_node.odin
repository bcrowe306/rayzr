package engine

import "core:c"
import "core:math"
import "core:path/filepath"
import "core:strings"
import lua "lua54"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// SkeletonNode: plays a Spine or DragonBones export (docs/
// skeletal_animation.md) with the engine's own runtime (skeleton.odin).
// The file is loaded once and shared by every node showing it (a cache
// keyed by file / atlas / armature, counted). Animations crossfade over
// mixTime; events fire "skeleton_event"(name) and a non-looping animation
// "animation_finished"(name). Scripts can override bones' rotations (aim a
// gun arm). BoneAttachmentNode children follow a bone (a sword in the
// hand, a particle trail on a foot) - in the game and in the editor.
// ============================================================================

SkeletonNode :: struct {
	using node: Node,
	file:      string `gui:"true"`, // a Spine .json or a DragonBones _ske.json (project-relative)
	atlas:     string `gui:"true"`, // its atlas ("" = next to it: name.atlas / name_tex.json)
	armature:  string `gui:"true"`, // DragonBones: which armature ("" = the first)
	animation: string `gui:"true"`, // played on ready (and shown in the editor)
	skin:      string `gui:"true"`,
	loop:      bool `gui:"true"`,
	autoplay:  bool `gui:"true"`,
	speed:     f32 `gui:"true" min:"0" max:"5"`,
	mixTime:   f32 `gui:"true" min:"0" max:"2"`, // crossfade between animations (s)
	tint:      rl.Color `gui:"true"`,
	showBones: bool `gui:"true"`, // draw the bones (also in the game: debugging)
	// Runtime.
	data:       ^Skeleton_Data,
	pose:       Skeleton_Pose,
	loadedKey:  string,
	animIndex:  int,
	time:       f32,
	playing:    bool,
	prevAnim:   int,
	prevTime:   f32,
	mixElapsed: f32,
	mixLength:  f32, // this crossfade's length (SkeletonNode_Play's mix, or mixTime)
	overrides:  [dynamic]Skel_Override,
	bounds:     rl.Rectangle, // last drawn (local space)
	selectedBone: int, // editor: the highlighted bone (-1)
	onFinished: EventSubject,
	onEvent:    EventSubject,
}

Skel_Override :: struct {
	bone:     int,
	rotation: f32, // local rotation (degrees)
}

BoneAttachmentNode :: struct {
	using node: Node,
	bone:           string `gui:"true"`, // the parent skeleton's bone to follow
	followRotation: bool `gui:"true"`,
	followScale:    bool `gui:"true"`,
}

// --- shared data -------------------------------------------------------------------------

@(private = "file")
Skel_CacheEntry :: struct {
	data: ^Skeleton_Data,
	refs: int,
}

@(private = "file")
skelCache: map[string]Skel_CacheEntry

@(private = "file")
Skel_Load_Ctx :: struct {
	game: ^Game,
	dir:  string, // the atlas's folder (project-relative)
}

@(private = "file")
skel_load_page :: proc(page: string, data: rawptr) -> ^Texture {
	lc := cast(^Skel_Load_Ctx)data
	rel, _ := filepath.join({lc.dir, page}, context.temp_allocator)
	rm := &lc.game.resourceManager
	t, ok := rm.loadTexture(rm, Project_ResolveAssetPath(&lc.game.gameContext, rel))
	return t if ok else nil
}

// Skeleton_LoadFile loads (or shares) the skeleton data of a file.
Skeleton_LoadFile :: proc(game: ^Game, file, atlas, armature: string) -> ^Skeleton_Data {
	if game == nil || file == "" do return nil
	key := strings.concatenate({file, "|", atlas, "|", armature}, context.temp_allocator)
	if e, ok := &skelCache[key]; ok {
		e.refs += 1
		return e.data
	}
	read :: proc(game: ^Game, rel: string) -> (string, bool) {
		b, ok := AssetManager_ReadFileBytes(&game.assetManager, rel, context.temp_allocator)
		return string(b), ok
	}
	text, ok := read(game, file)
	if !ok {
		log_warn("Skeleton file not found: %s", file)
		return nil
	}
	d: ^Skeleton_Data
	dragon := strings.has_suffix(file, "_ske.json") || strings.contains(text[:min(len(text), 4096)], "\"armature\"")
	if dragon {
		texPath := atlas
		if texPath == "" do texPath = strings.concatenate({strings.trim_suffix(strings.trim_suffix(file, ".json"), "_ske"), "_tex.json"}, context.temp_allocator)
		texText, _ := read(game, texPath)
		lc := Skel_Load_Ctx{game, filepath.dir(texPath, context.temp_allocator)}
		d, ok = Skeleton_LoadDragonBones(text, texText, armature, skel_load_page, &lc)
	} else {
		atlasPath := atlas
		atlasText: string
		if atlasPath == "" {
			for p in Skeleton_AtlasPathFor(file) {
				if t, found := read(game, p); found {atlasPath, atlasText = p, t; break}
			}
		} else {
			atlasText, _ = read(game, atlasPath)
		}
		// (No atlas - bones only, e.g. a rig for vector skinning: pages beside the file.)
		lc := Skel_Load_Ctx{game, filepath.dir(atlasPath if atlasPath != "" else file, context.temp_allocator)}
		d, ok = Skeleton_LoadSpine(text, atlasText, skel_load_page, &lc)
	}
	if !ok || d == nil {
		log_warn("Could not read the skeleton %s", file)
		return nil
	}
	if skelCache == nil do skelCache = make(map[string]Skel_CacheEntry, allocator = Engine_HeapAllocator())
	skelCache[strings.clone(key, Engine_HeapAllocator())] = {d, 1}
	return d
}

// Skeleton_Release drops a node's reference (the last frees the data).
Skeleton_Release :: proc(game: ^Game, d: ^Skeleton_Data) {
	if d == nil do return
	for k, &e in skelCache {
		if e.data != d do continue
		e.refs -= 1
		if e.refs <= 0 {
			Skeleton_DataDestroy(d, &game.resourceManager if game != nil else nil)
			delete_key(&skelCache, k)
			delete(k, Engine_HeapAllocator())
		}
		return
	}
}

// Skeleton_CacheCount: files loaded now (tests).
Skeleton_CacheCount :: proc() -> int {return len(skelCache)}

@(private = "file")
log_warn :: proc(format: string, args: ..any) {
	Script_Problem(.Warning, format, ..args)
}

// --- the node ---------------------------------------------------------------------------

SkeletonNode_Create :: proc(scene: ^Scene, name: string = "Skeleton", parent: ^Node = nil) -> ^SkeletonNode {
	sn := CreateNode(scene.manager, SkeletonNode)
	sn.name = strings.clone(name, sn.allocator)
	sn.loop, sn.autoplay, sn.speed, sn.mixTime = true, true, 1, 0.15
	sn.tint = rl.WHITE
	sn.animIndex, sn.prevAnim, sn.selectedBone = -1, -1, -1
	sn.update = SkeletonNode_Update
	sn.render = SkeletonNode_Render
	sn.ready = proc(n: ^Node, ctx: ^GameContext) {
		sn := cast(^SkeletonNode)n
		skel_ensure(sn)
		if sn.autoplay && sn.animation != "" do SkeletonNode_Play(sn, sn.animation, sn.loop, 0)
	}
	sn.onDestroy = proc(n: ^Node, ctx: ^GameContext) {
		sn := cast(^SkeletonNode)n
		skel_unload(sn)
		delete(sn.overrides)
		DestroySubject(&sn.onFinished)
		DestroySubject(&sn.onEvent)
	}
	InitializeSubject(&sn.onFinished, "animation_finished", sn)
	InitializeSubject(&sn.onEvent, "skeleton_event", sn)
	scene->addNode(sn, parent)
	return sn
}

BoneAttachmentNode_Create :: proc(scene: ^Scene, name: string = "BoneAttachment", parent: ^Node = nil) -> ^BoneAttachmentNode {
	b := CreateNode(scene.manager, BoneAttachmentNode)
	b.name = strings.clone(name, b.allocator)
	b.followRotation, b.followScale = true, false
	scene->addNode(b, parent)
	return b
}

@(private = "file")
skel_game :: proc(sn: ^SkeletonNode) -> ^Game {
	return sn.gameContext.game if sn.gameContext != nil else nil
}

@(private = "file")
skel_unload :: proc(sn: ^SkeletonNode) {
	if sn.data != nil {
		Skeleton_PoseDestroy(&sn.pose, sn.allocator)
		Skeleton_Release(skel_game(sn), sn.data)
	}
	sn.data = nil
	sn.loadedKey = ""
}

// skel_ensure (re)loads the data when the file / atlas / armature changed.
@(private = "file")
skel_ensure :: proc(sn: ^SkeletonNode) -> bool {
	key := strings.concatenate({sn.file, "|", sn.atlas, "|", sn.armature}, context.temp_allocator)
	if sn.data != nil && key == sn.loadedKey do return true
	skel_unload(sn)
	game := skel_game(sn)
	if sn.file == "" || game == nil do return false
	sn.loadedKey = strings.clone(key, sn.allocator)
	sn.data = Skeleton_LoadFile(game, sn.file, sn.atlas, sn.armature)
	if sn.data == nil do return false
	Skeleton_PoseInit(&sn.pose, sn.data, sn.allocator)
	sn.animIndex = Skeleton_AnimationIndex(sn.data, sn.animation)
	sn.prevAnim = -1
	return true
}

// SkeletonNode_Play starts an animation (crossfading over mix seconds; <0
// = the node's mixTime). False when it has no such animation.
SkeletonNode_Play :: proc(sn: ^SkeletonNode, name: string, loop: bool, mix: f32 = -1) -> bool {
	if !skel_ensure(sn) do return false
	i := Skeleton_AnimationIndex(sn.data, name)
	if i < 0 do return false
	m := sn.mixTime if mix < 0 else mix
	if sn.animIndex >= 0 && sn.animIndex != i && m > 0 {
		sn.prevAnim, sn.prevTime, sn.mixElapsed, sn.mixLength = sn.animIndex, sn.time, 0, m
	} else {
		sn.prevAnim = -1
	}
	sn.animIndex, sn.time, sn.loop, sn.playing = i, 0, loop, true
	if sn.animation != name do sn.animation = strings.clone(name, sn.allocator)
	return true
}

SkeletonNode_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	sn := cast(^SkeletonNode)node
	if !skel_ensure(sn) || !sn.playing || sn.animIndex < 0 do return
	anim := sn.data.animations[sn.animIndex]
	from := sn.time
	sn.time += dt * sn.speed
	if sn.prevAnim >= 0 {
		sn.prevTime += dt * sn.speed
		sn.mixElapsed += dt
		if sn.mixElapsed >= sn.mixLength do sn.prevAnim = -1
	}
	ended := false
	if sn.time >= anim.duration {
		if sn.loop && anim.duration > 0 do sn.time = math.mod(sn.time, anim.duration)
		else {
			sn.time = anim.duration
			ended = true
		}
	}
	// Events passed this frame (wrapping when it looped).
	evs := make([dynamic]Skel_Key, context.temp_allocator)
	Skeleton_EventsBetween(sn.data, sn.animIndex, from, sn.time, &evs)
	for e in evs do sn.onEvent->notify(sn, e.name, ctx)
	if ended {
		sn.playing = false
		sn.onFinished->notify(sn, anim.name, ctx)
	}
	skel_pose(sn)
}

// skel_pose: the pose for now, in the node's local space; places the
// BoneAttachment children.
@(private = "file")
skel_pose :: proc(sn: ^SkeletonNode) {
	d := sn.data
	if d == nil do return
	Skeleton_SetupPose(&sn.pose, d)
	sn.pose.skin = max(Skeleton_SkinIndex(d, sn.skin), 0)
	idx := sn.animIndex
	if idx < 0 && sn.animation != "" do idx = Skeleton_AnimationIndex(d, sn.animation)
	if sn.prevAnim >= 0 && sn.mixLength > 0 {
		Skeleton_Apply(&sn.pose, d, sn.prevAnim, skel_wrap(d, sn.prevAnim, sn.prevTime), 1)
		Skeleton_Apply(&sn.pose, d, idx, sn.time, clamp(sn.mixElapsed / sn.mixLength, 0, 1))
	} else {
		Skeleton_Apply(&sn.pose, d, idx, sn.time, 1)
	}
	for o in sn.overrides do if o.bone >= 0 && o.bone < len(sn.pose.bones) do sn.pose.bones[o.bone].rotation = o.rotation
	Skeleton_UpdateWorld(&sn.pose, d, {0, 0})
	// Children following bones (local space: they compose with the node).
	if sn.gameContext != nil && sn.gameContext.scene != nil {
		for ch in GetChildrenView(sn.gameContext.scene.manager, sn) {
			if ch == nil || ch.typeId != BoneAttachmentNode do continue
			ba := cast(^BoneAttachmentNode)ch
			bi := Skeleton_BoneIndex(d, ba.bone)
			if bi < 0 do continue
			b := sn.pose.bones[bi]
			ba.position = {b.wx, b.wy}
			if ba.followRotation do ba.rotation = Skeleton_BoneWorldRotation(b)
			if ba.followScale do ba.scale = Skeleton_BoneWorldScale(b)
		}
	}
}

@(private = "file")
skel_wrap :: proc(d: ^Skeleton_Data, anim: int, t: f32) -> f32 {
	if anim < 0 do return t
	dur := d.animations[anim].duration
	return math.mod(t, dur) if dur > 0 else t
}

SkeletonNode_Render :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	sn := cast(^SkeletonNode)node
	if !skel_ensure(sn) || !rl.IsWindowReady() do return
	if !sn.playing do skel_pose(sn) // (editor preview / stopped: the current frame)
	rlgl.DrawRenderBatchActive()
	rlgl.PushMatrix()
	rlgl.Translatef(sn.globalPosition.x, sn.globalPosition.y, 0)
	rlgl.Rotatef(sn.globalRotation, 0, 0, 1)
	rlgl.Scalef(sn.globalScale.x, sn.globalScale.y, 1)
	Skeleton_Draw(&sn.pose, sn.data, sn.tint)
	if sn.showBones || sn.selectedBone >= 0 do Skeleton_DrawBones(&sn.pose, sn.data, 1.5 / max(abs(sn.globalScale.x), 0.01), sn.selectedBone)
	rlgl.DrawRenderBatchActive()
	rlgl.PopMatrix()
	sn.bounds = skel_bounds(sn)
}

// skel_bounds: the bones' extent in local space (with a margin for the
// art around them).
@(private = "file")
skel_bounds :: proc(sn: ^SkeletonNode) -> rl.Rectangle {
	if sn.data == nil || len(sn.pose.bones) == 0 do return {}
	mn := [2]f32{math.F32_MAX, math.F32_MAX}
	mx := [2]f32{-math.F32_MAX, -math.F32_MAX}
	for b, i in sn.pose.bones {
		tip := Skeleton_LocalToWorld(b, {sn.data.bones[i].length, 0})
		for p in ([2][2]f32{{b.wx, b.wy}, tip}) {
			mn = {min(mn.x, p.x), min(mn.y, p.y)}
			mx = {max(mx.x, p.x), max(mx.y, p.y)}
		}
	}
	pad: f32 = 48
	return {mn.x - pad, mn.y - pad, mx.x - mn.x + pad * 2, mx.y - mn.y + pad * 2}
}

// SkeletonNode_WorldBounds: the last drawn extent in the world (picking,
// culling).
SkeletonNode_WorldBounds :: proc(sn: ^SkeletonNode) -> (rl.Rectangle, bool) {
	if sn.bounds.width <= 0 do return {sn.globalPosition.x - 32, sn.globalPosition.y - 32, 64, 64}, true
	b := sn.bounds
	s := [2]f32{abs(sn.globalScale.x), abs(sn.globalScale.y)}
	// (rotation ignored: a generous box)
	r := max(b.width * s.x, b.height * s.y)
	c := sn.globalPosition + ([2]f32{b.x + b.width * 0.5, b.y + b.height * 0.5}) * s
	return {c.x - r * 0.5, c.y - r * 0.5, r, r}, true
}

// SkeletonNode_BoneWorld: a bone's world position and rotation.
SkeletonNode_BoneWorld :: proc(sn: ^SkeletonNode, bone: string) -> (pos: [2]f32, rot: f32, ok: bool) {
	if !skel_ensure(sn) do return
	bi := Skeleton_BoneIndex(sn.data, bone)
	if bi < 0 do return
	b := sn.pose.bones[bi]
	r := math.to_radians(sn.globalRotation)
	cr, sr := math.cos(r), math.sin(r)
	lp := [2]f32{b.wx * sn.globalScale.x, b.wy * sn.globalScale.y}
	return sn.globalPosition + {cr * lp.x - sr * lp.y, sr * lp.x + cr * lp.y}, sn.globalRotation + Skeleton_BoneWorldRotation(b), true
}

// SkeletonNode_SetBoneRotation overrides a bone's local rotation (nil-like:
// clear = true removes the override).
SkeletonNode_SetBoneRotation :: proc(sn: ^SkeletonNode, bone: string, rotation: f32, clear := false) -> bool {
	if !skel_ensure(sn) do return false
	bi := Skeleton_BoneIndex(sn.data, bone)
	if bi < 0 do return false
	for o, i in sn.overrides do if o.bone == bi {
		if clear do unordered_remove(&sn.overrides, i)
		else do sn.overrides[i].rotation = rotation
		return true
	}
	if !clear {
		if sn.overrides == nil do sn.overrides = make([dynamic]Skel_Override, sn.allocator)
		append(&sn.overrides, Skel_Override{bi, rotation})
	}
	return true
}

// --- Lua -------------------------------------------------------------------------------
// skel:skeleton_play(name [, loop = true [, mix]]) -> ok
// skel:skeleton_stop() / skeleton_is_playing() / skeleton_set_skin(name)
// skel:skeleton_animations() / skeleton_skins() / skeleton_bones() -> { names }
// skel:skeleton_bone_position(name) -> Vec2 (world) / skeleton_bone_rotation(name)
// skel:skeleton_set_bone_rotation(name, degrees | nil)
// skel:skeleton_duration([name])

@(private = "file")
lua_skel :: proc(L: ^lua.State) -> ^SkeletonNode {
	n, ok := to_node_userdata(L, 1)
	return cast(^SkeletonNode)n if ok && n.typeId == SkeletonNode else nil
}

@(private = "file")
lua_skel_play :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sn := lua_skel(L)
	ok := false
	if sn != nil {
		loop := lua.type(L, 3) != .BOOLEAN || bool(lua.toboolean(L, 3))
		mix := f32(lua.tonumber(L, 4)) if lua.type(L, 4) == .NUMBER else -1
		name := string(lua.tostring(L, 2))
		// (Like animation_play, #222) the animation already playing keeps
		// going - safe to call every frame.
		if sn.playing && sn.animIndex >= 0 && sn.animation == name {
			sn.loop = loop
			ok = true
		} else {
			ok = SkeletonNode_Play(sn, name, loop, mix)
		}
	}
	lua.pushboolean(L, b32(ok))
	return 1
}

@(private = "file")
lua_skel_stop :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if sn := lua_skel(L); sn != nil do sn.playing = false
	return 0
}

@(private = "file")
lua_skel_is_playing :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sn := lua_skel(L)
	lua.pushboolean(L, b32(sn != nil && sn.playing))
	return 1
}

@(private = "file")
lua_skel_set_skin :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if sn := lua_skel(L); sn != nil do sn.skin = strings.clone(string(lua.tostring(L, 2)), sn.allocator)
	return 0
}

@(private = "file")
push_names :: proc(L: ^lua.State, names: []string) {
	lua.createtable(L, c.int(len(names)), 0)
	for n, i in names {
		lua.pushstring(L, strings.clone_to_cstring(n, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
}

@(private = "file")
lua_skel_list :: proc(L: ^lua.State, which: int) -> c.int {
	sn := lua_skel(L)
	names := make([dynamic]string, context.temp_allocator)
	if sn != nil && skel_ensure(sn) {
		switch which {
		case 0: for a in sn.data.animations do append(&names, a.name)
		case 1: for s in sn.data.skins do append(&names, s.name)
		case 2: for b in sn.data.bones do append(&names, b.name)
		}
	}
	push_names(L, names[:])
	return 1
}

@(private = "file")
lua_skel_animations :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); return lua_skel_list(L, 0)}
@(private = "file")
lua_skel_skins :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); return lua_skel_list(L, 1)}
@(private = "file")
lua_skel_bones :: proc "c" (L: ^lua.State) -> c.int {context = Script_Context(L); return lua_skel_list(L, 2)}

@(private = "file")
lua_skel_bone_position :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sn := lua_skel(L)
	if sn != nil {
		if p, _, ok := SkeletonNode_BoneWorld(sn, string(lua.tostring(L, 2))); ok {
			Lua_PushVec2(L, p)
			return 1
		}
	}
	lua.pushnil(L)
	return 1
}

@(private = "file")
lua_skel_bone_rotation :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sn := lua_skel(L)
	if sn != nil {
		if _, r, ok := SkeletonNode_BoneWorld(sn, string(lua.tostring(L, 2))); ok {
			lua.pushnumber(L, lua.Number(r))
			return 1
		}
	}
	lua.pushnil(L)
	return 1
}

@(private = "file")
lua_skel_set_bone_rotation :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sn := lua_skel(L)
	ok := sn != nil && SkeletonNode_SetBoneRotation(sn, string(lua.tostring(L, 2)), f32(lua.tonumber(L, 3)), lua.type(L, 3) != .NUMBER)
	lua.pushboolean(L, b32(ok))
	return 1
}

@(private = "file")
lua_skel_duration :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sn := lua_skel(L)
	dur: f32
	if sn != nil && skel_ensure(sn) {
		idx := sn.animIndex
		if lua.type(L, 2) == .STRING do idx = Skeleton_AnimationIndex(sn.data, string(lua.tostring(L, 2)))
		if idx >= 0 do dur = sn.data.animations[idx].duration
	}
	lua.pushnumber(L, lua.Number(dur))
	return 1
}

// Script_RegisterSkeletonBindings adds the methods to the node metatable
// (on the stack).
Script_RegisterSkeletonBindings :: proc(L: ^lua.State) {
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "skeleton_play", lua_skel_play)
	reg(L, "skeleton_stop", lua_skel_stop)
	reg(L, "skeleton_is_playing", lua_skel_is_playing)
	reg(L, "skeleton_set_skin", lua_skel_set_skin)
	reg(L, "skeleton_animations", lua_skel_animations)
	reg(L, "skeleton_skins", lua_skel_skins)
	reg(L, "skeleton_bones", lua_skel_bones)
	reg(L, "skeleton_bone_position", lua_skel_bone_position)
	reg(L, "skeleton_bone_rotation", lua_skel_bone_rotation)
	reg(L, "skeleton_set_bone_rotation", lua_skel_set_bone_rotation)
	reg(L, "skeleton_get_duration", lua_skel_duration)
	Lua_SetDeprecated(L, lua_skel_duration, "skeleton_duration", "skeleton_get_duration")
}
