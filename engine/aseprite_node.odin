package engine

import "core:c"
import "core:fmt"
import "core:strings"
import lua "lua54"
import rl "vendor:raylib"

// ============================================================================
// AsepriteNode (TODO E.3): shows an Aseprite file (.aseprite / .ase) and
// plays its tags as Aseprite does - per-frame durations, the tag's
// direction (forward, reverse, ping-pong, ping-pong reverse) and repeat
// count - with layers hidden / shown per node, the origin following a slice's
// pivot (per frame), and the file's slices / user data for scripts. Saving
// the file in Aseprite updates the node (in the editor and in a running
// game: aseprite_resource.odin).
//
// Events: "animation_finished"(tag) when a tag's repeats are done,
// "animation_looped"(tag) at each repeat, "frame_changed"(frame).
// ============================================================================

AsepriteNode :: struct {
	using node:  Node,
	shininess: f32 `gui:"true" min:"0" max:"1"`, // lit: a glint from lights (#274; its image's _s.png too)
	file:        string `gui:"true"`, // the .aseprite / .ase (project-relative)
	animation:   string `gui:"true"`, // a tag ("" = every frame, in order)
	autoplay:    bool `gui:"true"`,
	loop:        bool `gui:"true"`,   // tags without a repeat count loop (else: once)
	speed:       f32 `gui:"true" min:"0" max:"5"`,
	frame:       int `gui:"true" min:"0"`, // the frame shown (the start, or where it stopped)
	hideLayers:  string `gui:"true"`, // layer names (comma separated) not drawn
	showLayers:  string `gui:"true"`, // hidden-in-the-file layers drawn anyway
	pivotSlice:  string `gui:"true"`, // a slice with a pivot: the origin follows it ("" = the node's pivot)
	tint:        rl.Color `gui:"true"`,
	// Runtime.
	res:         ^Ase_Resource,
	loadedPath:  string,
	tag:         int, // index (-1: every frame)
	playing:     bool,
	elapsed:     f32, // ms into the current frame
	dir:         int, // +1 / -1
	passes:      int, // ping-pong passes / loops done in this tag
	onFinished:  EventSubject,
	onLooped:    EventSubject,
	onFrame:     EventSubject,
}

AsepriteNode_Create :: proc(scene: ^Scene, name: string = "Aseprite", parent: ^Node = nil) -> ^AsepriteNode {
	an := CreateNode(scene.manager, AsepriteNode)
	an.name = strings.clone(name, an.allocator)
	an.autoplay, an.loop, an.speed, an.tint = true, true, 1, rl.WHITE
	an.tag, an.dir = -1, 1
	an.update = AsepriteNode_Update
	an.render = AsepriteNode_Render
	an.ready = proc(n: ^Node, ctx: ^GameContext) {
		an := cast(^AsepriteNode)n
		ase_ensure(an)
		if an.autoplay do AsepriteNode_Play(an, an.animation)
	}
	an.onDestroy = proc(n: ^Node, ctx: ^GameContext) {
		an := cast(^AsepriteNode)n
		ResourceManager_ReleaseAseprite(an.res)
		an.res = nil
		delete(an.loadedPath, an.allocator)
		DestroySubject(&an.onFinished)
		DestroySubject(&an.onLooped)
		DestroySubject(&an.onFrame)
	}
	InitializeSubject(&an.onFinished, "animation_finished", an)
	InitializeSubject(&an.onLooped, "animation_looped", an)
	InitializeSubject(&an.onFrame, "frame_changed", an)
	scene->addNode(an, parent)
	return an
}

// ase_ensure: the file loaded (again, if `file` changed).
@(private = "file")
ase_ensure :: proc(an: ^AsepriteNode) -> bool {
	if an.file == an.loadedPath && an.res != nil do return true
	if an.file == an.loadedPath && an.file == "" do return false
	ResourceManager_ReleaseAseprite(an.res)
	an.res = nil
	delete(an.loadedPath, an.allocator)
	an.loadedPath = strings.clone(an.file, an.allocator)
	if an.file == "" || an.gameContext == nil || an.gameContext.game == nil do return false
	rm := &an.gameContext.game.resourceManager
	an.res = ResourceManager_LoadAseprite(rm, Project_ResolveAssetPath(an.gameContext, an.file))
	if an.res == nil do return false
	an.tag = ase_tag_index(an.res.doc, an.animation)
	an.frame = clamp(an.frame, 0, max(len(an.res.doc.frames) - 1, 0))
	return true
}

@(private = "file")
ase_tag_index :: proc(doc: ^Ase_Document, name: string) -> int {
	if name == "" do return -1
	for t, i in doc.tags do if t.name == name do return i
	return -1
}

// The frame range now playing: a tag's, or every frame.
@(private = "file")
ase_range :: proc(an: ^AsepriteNode) -> (from, to: int, direction: Ase_Direction, repeats: int) {
	doc := an.res.doc
	if an.tag >= 0 && an.tag < len(doc.tags) {
		t := doc.tags[an.tag]
		return clamp(t.from, 0, len(doc.frames) - 1), clamp(t.to, 0, len(doc.frames) - 1), t.direction, t.repeats
	}
	return 0, max(len(doc.frames) - 1, 0), .Forward, 0
}

// AsepriteNode_Play starts a tag ("" = every frame) from its first frame
// (the last for reverse directions).
AsepriteNode_Play :: proc(an: ^AsepriteNode, tag: string) {
	if tag != an.animation {
		delete(an.animation, an.allocator)
		an.animation = strings.clone(tag, an.allocator)
	}
	if !ase_ensure(an) do return
	an.tag = ase_tag_index(an.res.doc, tag)
	from, to, direction, _ := ase_range(an)
	reverse := direction == .Reverse || direction == .Ping_Pong_Reverse
	an.dir = -1 if reverse else 1
	ase_set_frame(an, to if reverse else from)
	an.elapsed, an.passes = 0, 0
	an.playing = true
}

AsepriteNode_Stop :: proc(an: ^AsepriteNode) {an.playing = false}

@(private = "file")
ase_set_frame :: proc(an: ^AsepriteNode, f: int) {
	if f == an.frame do return
	an.frame = f
	an.onFrame->notify(an, f, an.gameContext)
}

// The tag's name for its events ("" for every frame).
@(private = "file")
ase_tag_name :: proc(an: ^AsepriteNode) -> string {
	return an.res.doc.tags[an.tag].name if an.tag >= 0 else ""
}

// ase_step: the next frame, as Aseprite plays the tag. False: it finished.
@(private = "file")
ase_step :: proc(an: ^AsepriteNode) -> bool {
	from, to, direction, repeats := ase_range(an)
	limit := repeats
	if limit == 0 && !an.loop do limit = 1 // (once)
	next := an.frame + an.dir
	if next >= from && next <= to {
		ase_set_frame(an, next)
		return true
	}
	// The end of a pass.
	an.passes += 1
	if limit > 0 && an.passes >= limit {
		an.onFinished->notify(an, ase_tag_name(an), an.gameContext)
		return false
	}
	an.onLooped->notify(an, ase_tag_name(an), an.gameContext)
	switch direction {
	case .Forward: ase_set_frame(an, from)
	case .Reverse: ase_set_frame(an, to)
	case .Ping_Pong, .Ping_Pong_Reverse:
		// Turn around (the end frame isn't shown twice).
		an.dir = -an.dir
		if from != to do ase_set_frame(an, an.frame + an.dir)
	}
	return true
}

AsepriteNode_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	an := cast(^AsepriteNode)node
	if !ase_ensure(an) do return
	if an.res.doc != nil && an.tag >= 0 && an.tag >= len(an.res.doc.tags) do an.tag = ase_tag_index(an.res.doc, an.animation) // (reloaded)
	if !an.playing || an.speed <= 0 do return
	doc := an.res.doc
	an.frame = clamp(an.frame, 0, len(doc.frames) - 1)
	an.elapsed += dt * 1000 * an.speed
	for guard := 0; an.playing && guard < 64; guard += 1 {
		d := f32(max(doc.frames[an.frame].duration, 1))
		if an.elapsed < d do break
		an.elapsed -= d
		if !ase_step(an) {
			an.playing = false
			an.elapsed = 0
		}
	}
}

// AsepriteNode_Origin: the origin (px from the sprite's top-left): the
// pivot slice's pivot in this frame, else the node's pivot.
AsepriteNode_Origin :: proc(an: ^AsepriteNode) -> [2]f32 {
	if an.res == nil do return {}
	doc := an.res.doc
	if an.pivotSlice != "" {
		if s := Ase_FindSlice(doc, an.pivotSlice); s != nil && s.has_pivot {
			if k, ok := Ase_SliceKey(s, an.frame); ok do return {f32(k.x + k.pivot[0]), f32(k.y + k.pivot[1])}
		}
	}
	return an.pivot * [2]f32{f32(doc.width), f32(doc.height)}
}

AsepriteNode_Render :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	if !rl.IsWindowReady() do return
	an := cast(^AsepriteNode)node
	if !ase_ensure(an) do return
	sheet := Ase_ResourceSheet(an.res, an.hideLayers, an.showLayers)
	if sheet == nil do return
	f := clamp(an.frame, 0, len(an.res.doc.frames) - 1)
	src := Ase_SheetRect(an.res, sheet, f)
	size := [2]f32{src.width, src.height}
	tint := an.tint if an.tint != {} else rl.WHITE
	Texture_DrawScaled(sheet.texture, src, an.globalPosition, size, an.globalScale, AsepriteNode_Origin(an), an.globalRotation, tint)
}

// AsepriteNode_Size: the sprite's size (px; {} until loaded).
AsepriteNode_Size :: proc(an: ^AsepriteNode) -> [2]f32 {
	if an.res == nil do ase_ensure(an)
	if an.res == nil do return {}
	return {f32(an.res.doc.width), f32(an.res.doc.height)}
}

// --- Lua: aseprite_* methods ------------------------------------------------------------

@(private = "file")
check_an :: proc(L: ^lua.State) -> ^AsepriteNode {
	n, ok := to_node_userdata(L, 1)
	if !ok || n.typeId != AsepriteNode do return nil
	an := cast(^AsepriteNode)n
	ase_ensure(an)
	return an
}

// node:aseprite_play([tag]) - "" / nil = every frame
@(private = "file")
lua_ase_play :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	an := check_an(L)
	if an == nil do return 0
	tag := string(lua.tostring(L, 2)) if lua.type(L, 2) == .STRING else an.animation
	AsepriteNode_Play(an, tag)
	return 0
}

@(private = "file")
lua_ase_stop :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if an := check_an(L); an != nil do AsepriteNode_Stop(an)
	return 0
}

// node:aseprite_resume() - goes on from where it stopped
@(private = "file")
lua_ase_resume :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if an := check_an(L); an != nil && an.res != nil do an.playing = true
	return 0
}

@(private = "file")
lua_ase_is_playing :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	an := check_an(L)
	lua.pushboolean(L, b32(an != nil && an.playing))
	return 1
}

// node:aseprite_frame() -> frame (0-based)
@(private = "file")
lua_ase_frame :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	an := check_an(L)
	lua.pushinteger(L, lua.Integer(an.frame if an != nil else 0))
	return 1
}

// node:aseprite_set_frame(frame) - shows a frame (0-based; playing goes on from it)
@(private = "file")
lua_ase_set_frame :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	an := check_an(L)
	if an == nil || an.res == nil do return 0
	ase_set_frame(an, clamp(int(lua.L_checkinteger(L, 2)), 0, len(an.res.doc.frames) - 1))
	an.elapsed = 0
	return 0
}

// node:aseprite_info() -> {width, height, frames = {ms...}, tags = {{name, from, to, direction, repeats}...}, layers = {names...}}
@(private = "file")
lua_ase_info :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	an := check_an(L)
	if an == nil || an.res == nil {
		lua.pushnil(L)
		return 1
	}
	doc := an.res.doc
	lua.createtable(L, 0, 6)
	set_int(L, "width", doc.width)
	set_int(L, "height", doc.height)
	lua.createtable(L, c.int(len(doc.frames)), 0)
	for f, i in doc.frames {
		lua.pushinteger(L, lua.Integer(f.duration))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	lua.setfield(L, -2, "frames")
	lua.createtable(L, c.int(len(doc.tags)), 0)
	for t, i in doc.tags {
		lua.createtable(L, 0, 6)
		set_str(L, "name", t.name)
		set_int(L, "from", t.from)
		set_int(L, "to", t.to)
		set_str(L, "direction", fmt.tprint(t.direction))
		set_int(L, "repeats", t.repeats)
		push_user_data(L, t.user)
		lua.setfield(L, -2, "user")
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	lua.setfield(L, -2, "tags")
	lua.createtable(L, c.int(len(doc.layers)), 0)
	for l, i in doc.layers {
		lua.pushstring(L, strings.clone_to_cstring(l.name, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	lua.setfield(L, -2, "layers")
	push_user_data(L, doc.user)
	lua.setfield(L, -2, "user")
	return 1
}

// node:aseprite_slice(name[, frame]) -> {x, y, width, height, center = {x, y, width, height}?, pivot = {x, y}?, user} | nil
@(private = "file")
lua_ase_slice :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	an := check_an(L)
	if an == nil || an.res == nil {
		lua.pushnil(L)
		return 1
	}
	s := Ase_FindSlice(an.res.doc, string(lua.L_checkstring(L, 2)))
	frame := int(lua.tointeger(L, 3)) if lua.type(L, 3) == .NUMBER else an.frame
	k: Ase_Slice_Key
	ok := false
	if s != nil do k, ok = Ase_SliceKey(s, frame)
	if !ok {
		lua.pushnil(L)
		return 1
	}
	lua.createtable(L, 0, 7)
	set_int(L, "x", k.x)
	set_int(L, "y", k.y)
	set_int(L, "width", k.w)
	set_int(L, "height", k.h)
	if s.nine_patch {
		lua.createtable(L, 0, 4)
		set_int(L, "x", k.center[0]); set_int(L, "y", k.center[1]); set_int(L, "width", k.center[2]); set_int(L, "height", k.center[3])
		lua.setfield(L, -2, "center")
	}
	if s.has_pivot {
		lua.createtable(L, 0, 2)
		set_int(L, "x", k.pivot[0]); set_int(L, "y", k.pivot[1])
		lua.setfield(L, -2, "pivot")
	}
	push_user_data(L, s.user)
	lua.setfield(L, -2, "user")
	return 1
}

// node:aseprite_layer_data(name) -> {text, color, properties} | nil
@(private = "file")
lua_ase_layer_data :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	an := check_an(L)
	if an == nil || an.res == nil {
		lua.pushnil(L)
		return 1
	}
	i := Ase_FindLayer(an.res.doc, string(lua.L_checkstring(L, 2)))
	if i < 0 do lua.pushnil(L)
	else do push_user_data(L, an.res.doc.layers[i].user)
	return 1
}

// node:aseprite_cel_data(layer[, frame]) -> {text, color, properties} | nil
@(private = "file")
lua_ase_cel_data :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	an := check_an(L)
	if an == nil || an.res == nil {
		lua.pushnil(L)
		return 1
	}
	doc := an.res.doc
	li := Ase_FindLayer(doc, string(lua.L_checkstring(L, 2)))
	frame := int(lua.tointeger(L, 3)) if lua.type(L, 3) == .NUMBER else an.frame
	if li >= 0 && frame >= 0 && frame < len(doc.frames) {
		for &cel in doc.frames[frame].cels do if cel.layer == li {
			push_user_data(L, cel.user)
			return 1
		}
	}
	lua.pushnil(L)
	return 1
}

// node:aseprite_set_layer_visible(name, visible)
@(private = "file")
lua_ase_set_layer_visible :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	an := check_an(L)
	if an == nil do return 0
	name := string(lua.L_checkstring(L, 2))
	on := bool(lua.toboolean(L, 3))
	remove :: proc(an: ^AsepriteNode, list: ^string, name: string) {
		parts := make([dynamic]string, context.temp_allocator)
		for p in strings.split(list^, ",", context.temp_allocator) do if strings.trim_space(p) != "" && strings.trim_space(p) != name do append(&parts, strings.trim_space(p))
		delete(list^, an.allocator)
		list^ = strings.join(parts[:], ",", an.allocator)
	}
	add :: proc(an: ^AsepriteNode, list: ^string, name: string) {
		old := list^
		list^ = strings.concatenate({old, "," if old != "" else "", name}, an.allocator)
		delete(old, an.allocator)
	}
	remove(an, &an.hideLayers, name)
	remove(an, &an.showLayers, name)
	add(an, &an.showLayers if on else &an.hideLayers, name)
	return 0
}

@(private = "file") set_int :: proc(L: ^lua.State, k: cstring, v: int) {lua.pushinteger(L, lua.Integer(v)); lua.setfield(L, -2, k)}
@(private = "file") set_str :: proc(L: ^lua.State, k: cstring, v: string) {lua.pushstring(L, strings.clone_to_cstring(v, context.temp_allocator)); lua.setfield(L, -2, k)}

// push_user_data: {text, color = {r, g, b, a}?, properties = {...}}
@(private = "file")
push_user_data :: proc(L: ^lua.State, u: Ase_User_Data) {
	lua.createtable(L, 0, 3)
	set_str(L, "text", u.text)
	if u.has_color {
		lua.createtable(L, 4, 0)
		for ch, i in u.color {
			lua.pushinteger(L, lua.Integer(ch))
			lua.rawseti(L, -2, lua.Integer(i + 1))
		}
		lua.setfield(L, -2, "color")
	}
	lua.createtable(L, 0, c.int(len(u.properties)))
	for k, v in u.properties {
		push_ase_value(L, v)
		lua.setfield(L, -2, strings.clone_to_cstring(k, context.temp_allocator))
	}
	lua.setfield(L, -2, "properties")
}

@(private = "file")
push_ase_value :: proc(L: ^lua.State, v: Ase_Value) {
	switch x in v {
	case bool: lua.pushboolean(L, b32(x))
	case i64: lua.pushinteger(L, lua.Integer(x))
	case u64: lua.pushinteger(L, lua.Integer(x))
	case f64: lua.pushnumber(L, lua.Number(x))
	case string: lua.pushstring(L, strings.clone_to_cstring(x, context.temp_allocator))
	case Ase_Point:
		lua.createtable(L, 0, 2); set_int(L, "x", int(x[0])); set_int(L, "y", int(x[1]))
	case Ase_Size:
		lua.createtable(L, 0, 2); set_int(L, "width", int(x[0])); set_int(L, "height", int(x[1]))
	case Ase_Rect:
		lua.createtable(L, 0, 4); set_int(L, "x", int(x.x)); set_int(L, "y", int(x.y)); set_int(L, "width", int(x.w)); set_int(L, "height", int(x.h))
	case []Ase_Value:
		lua.createtable(L, c.int(len(x)), 0)
		for e, i in x {
			push_ase_value(L, e)
			lua.rawseti(L, -2, lua.Integer(i + 1))
		}
	case map[string]Ase_Value:
		lua.createtable(L, 0, c.int(len(x)))
		for k, e in x {
			push_ase_value(L, e)
			lua.setfield(L, -2, strings.clone_to_cstring(k, context.temp_allocator))
		}
	case Ase_UUID:
		id := x
		lua.pushstring(L, fmt.ctprintf("%x", id[:]))
	case:
		lua.pushnil(L)
	}
}

// Script_RegisterAsepriteBindings adds the methods to the node metatable
// (on the stack).
Script_RegisterAsepriteBindings :: proc(L: ^lua.State) {
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "aseprite_play", lua_ase_play)
	reg(L, "aseprite_stop", lua_ase_stop)
	reg(L, "aseprite_resume", lua_ase_resume)
	reg(L, "aseprite_is_playing", lua_ase_is_playing)
	reg(L, "aseprite_frame", lua_ase_frame)
	reg(L, "aseprite_set_frame", lua_ase_set_frame)
	reg(L, "aseprite_info", lua_ase_info)
	reg(L, "aseprite_slice", lua_ase_slice)
	reg(L, "aseprite_layer_data", lua_ase_layer_data)
	reg(L, "aseprite_cel_data", lua_ase_cel_data)
	reg(L, "aseprite_set_layer_visible", lua_ase_set_layer_visible)
}
