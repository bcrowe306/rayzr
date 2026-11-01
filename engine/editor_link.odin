package engine

import "core:fmt"
import os "osx"
import "core:strconv"
import "core:strings"
import lua "lua54"
import "core:time"
import rl "vendor:raylib"

// ============================================================================
// Editor link (--editor-link): the editor that launched the game drives it
// through stdin, one command per line; answers are stdout lines starting
// with "@rayzr:" (the editor reads them, its console hides them).
//
//   pause / resume              freeze the game (it is still drawn) / go on
//   step [n]                    while paused: run n frames of 1/60 s
//   tree [hash]                 -> @rayzr:tree {"frame", "frozen", "scene", "hash", "root"}, or
//                                  @rayzr:tree-same {"frame", ...} when the tree's hash is still `hash`
//   inspect <path>              -> @rayzr:node {"path", "props": [[name, value, kind, extra], ...]}
//                                  kind: float int bool vec2 color enum bit_set string (ro = read-only);
//                                  extra: enum names "A|B" or a range "min|max"
//   highlight <path>            outline that node in the game ("" = none)
//   pick                        the next click in the game picks the topmost node there -> @rayzr:picked <path>
//   remove <path>               remove a node -> @rayzr:removed <path> true|false
//   set <path> <prop> <value>   change a property ("position" "10,20", "rotation", any reflected one)
//   reload-scene <file>         re-read a scene file; restart it when it's the current scene
//   eval <lua>                  -> @rayzr:eval {"ok", "code", "text"} (the Console's Lua line)
//   sm <path>                   -> @rayzr:sm {status} (a state machine, live: state_machine_node.odin)
//   mixer-peaks                 -> @rayzr:mixer-peaks [[bus, left, right, clip], ...]
//   mixer-set <bus> volume|pan|mute|solo <v> / mixer-fx <bus> <slot> <param> <v> /
//   mixer-fx-enabled <bus> <slot> 0|1 / mixer-load <buses JSON>   the Mixer tab, live
//   sm-break <path> <state> 0|1 pause when that machine enters that state (-> @rayzr:sm-break)
//   break-set <file> <l,l,...>  breakpoints in a script (break-clear: none); a hit
//                               pauses the game in the script (lua_debugger.odin):
//                               -> @rayzr:stopped {...}, then continue / step-* / locals
//
// Paths are node names from the scene root, '/'-separated ("Player/Gun").
// Scripts and textures reload by themselves when their files change.
// ============================================================================

Editor_Link :: struct {
	enabled: bool,
	smBreaks: [dynamic]string, // "path|state": break on enter
	game:     ^Game,
	steps:   int, // frames to run while paused
	highlight: string, // the node outlined in the game (heap; "" = none)
	picking:   bool,   // the next click picks a node
	treeHash:  u64,
	frame:   int, // frames run (not counting frozen ones)
	inBuf:   [dynamic]u8,
}

editorLink: Editor_Link

EditorLink_Enable :: proc(game: ^Game) {
	editorLink.enabled = true
	editorLink.game = game
	StateMachine_EnterHook = link_sm_enter
	// Breakpoints: the debugger waits for commands on stdin while stopped.
	LuaDebugger_Attach(game.scriptManager.L, link_wait_command, proc(kind, json: string) {fmt.printfln("@rayzr:%s %s", kind, json)})
	luaDebugger.projectDir = game.assetManager.projectDir
	fmt.println("@rayzr:hello")
}

// link_wait_command blocks until the editor sends a line (the game is
// paused in a script); window events keep being handled meanwhile.
@(private = "file")
link_wait_command :: proc() -> string {
	for {
		for b, i in editorLink.inBuf {
			if b != '\n' do continue
			line := strings.clone(strings.trim_space(string(editorLink.inBuf[:i])), context.temp_allocator)
			remove_range(&editorLink.inBuf, 0, i + 1)
			if line != "" do return line
			break
		}
		has, err := os.pipe_has_data(os.stdin)
		if err != nil do return ""
		if has {
			chunk: [1024]u8
			n, rerr := os.read(os.stdin, chunk[:])
			if n <= 0 || rerr != nil do return "" // the editor went away
			append(&editorLink.inBuf, ..chunk[:n])
			continue
		}
		if rl.IsWindowReady() do rl.PollInputEvents()
		if rl.IsWindowReady() && rl.WindowShouldClose() do return ""
		time.sleep(10 * time.Millisecond)
	}
}

// EditorLink_Enabled: the editor drives this game (its Play).
EditorLink_Enabled :: proc() -> bool {return editorLink.enabled}

// EditorLink_BeginFrame reads pending commands and decides whether this
// frame runs (game.frozen = false) or only draws.
EditorLink_BeginFrame :: proc(game: ^Game) {
	if !editorLink.enabled do return
	for {
		has, err := os.pipe_has_data(os.stdin)
		if err != nil || !has do break
		chunk: [1024]u8
		n, rerr := os.read(os.stdin, chunk[:])
		if n <= 0 || rerr != nil {
			editorLink.enabled = false // the editor went away
			break
		}
		append(&editorLink.inBuf, ..chunk[:n])
	}
	for {
		idx := -1
		for b, i in editorLink.inBuf do if b == '\n' {idx = i; break}
		if idx < 0 do break
		line := strings.clone(strings.trim_space(string(editorLink.inBuf[:idx])), context.temp_allocator)
		remove_range(&editorLink.inBuf, 0, idx + 1)
		if line != "" do EditorLink_Command(game, line)
	}
	if game.linkPaused {
		game.frozen = editorLink.steps <= 0
		if editorLink.steps > 0 do editorLink.steps -= 1
	} else {
		game.frozen = false
	}
	if !game.frozen do editorLink.frame += 1
	EditorLink_UpdatePick(game)
}

// EditorLink_Command runs one command (also used by tests).
EditorLink_Command :: proc(game: ^Game, line: string) {
	cmd, rest := line, ""
	if i := strings.index_byte(line, ' '); i >= 0 do cmd, rest = line[:i], strings.trim_space(line[i + 1:])
	switch cmd {
	case "pause":
		game.linkPaused = true
		fmt.println("@rayzr:paused")
	case "resume":
		game.linkPaused = false
		editorLink.steps = 0
		fmt.println("@rayzr:resumed")
	case "step":
		n := 1
		if v, ok := strconv.parse_int(rest); ok do n = max(v, 1)
		game.linkPaused = true
		editorLink.steps += n
		fmt.printfln("@rayzr:stepped %d", n)
	case "tree":
		// "tree <hash>": unchanged trees answer in a few bytes.
		root, h := EditorLink_TreeRootJSON(game)
		if rest != "" && rest == fmt.tprint(h) {
			fmt.printfln("@rayzr:tree-same {{\"frame\": %d, \"frozen\": %t, \"paused\": %t}}", editorLink.frame, game.frozen, game.linkPaused)
		} else {
			fmt.printfln("@rayzr:tree %s", EditorLink_TreeJSON(game, root, h))
		}
	case "highlight":
		delete(editorLink.highlight)
		editorLink.highlight = strings.clone(rest) if rest != "" else ""
	case "pick":
		editorLink.picking = rest != "off"
	case "remove":
		n := link_find(game, rest)
		ok := n != nil && n != game.sceneManager.currentScene.rootNode
		if ok do RemoveNode(game.sceneManager.currentScene.manager, n)
		fmt.printfln("@rayzr:removed %s %t", rest, ok)
	case "inspect":
		fmt.printfln("@rayzr:node %s", EditorLink_NodeJSON(game, rest))
	case "set":
		parts := strings.fields(rest, context.temp_allocator)
		if len(parts) >= 3 {
			value := strings.join(parts[2:], " ", context.temp_allocator)
			ok := EditorLink_Set(game, parts[0], parts[1], value)
			fmt.printfln("@rayzr:set %s %s %t", parts[0], parts[1], ok)
		}
	case "break-set":
		LuaDebugger_Command(rest)
	case "break-clear":
		LuaDebugger_ClearBreakpoints()
	case "break-cond":
		LuaDebugger_CondCommand(rest)
	case "reload-scene":
		fmt.printfln("@rayzr:reloaded %s %t", rest, Game_ReloadSceneFile(game, rest))
	case "sm":
		n := link_find(game, rest)
		if n == nil || n.typeId != StateMachineNode {
			sb := strings.builder_make(context.temp_allocator)
			strings.write_string(&sb, "{\"path\": ")
			link_str(&sb, rest)
			strings.write_string(&sb, ", \"missing\": true}")
			fmt.printfln("@rayzr:sm %s", strings.to_string(sb))
		} else {
			sm := cast(^StateMachineNode)n
			sm.explain = true // the editor shows its ways out (from the next update)
			fmt.printfln("@rayzr:sm %s", StateMachine_StatusJSON(sm, rest))
		}
	case "bt":
		// -> @rayzr:bt {"path", "ticks", "status", "micros", "running", "nodes": [[status, ticks ago]], "blackboard": {}}
		n := link_find(game, rest)
		if n == nil || n.typeId != BehaviorTreeNode {
			sb := strings.builder_make(context.temp_allocator)
			strings.write_string(&sb, "{\"path\": ")
			link_str(&sb, rest)
			strings.write_string(&sb, ", \"missing\": true}")
			fmt.printfln("@rayzr:bt %s", strings.to_string(sb))
		} else {
			fmt.printfln("@rayzr:bt %s", BehaviorTree_StatusJSON(cast(^BehaviorTreeNode)n, rest))
		}
	case "mixer-peaks":
		// -> @rayzr:mixer-peaks [[index, left, right, clip], ...] (the meters while the game plays)
		sb := strings.builder_make(context.temp_allocator)
		strings.write_byte(&sb, '[')
		for b, i in Mixer_Buses() {
			if i > 0 do strings.write_string(&sb, ", ")
			fmt.sbprintf(&sb, "[%d, %.4f, %.4f, %d]", b.index, b.peak[0], b.peak[1], 1 if b.clip else 0)
		}
		strings.write_byte(&sb, ']')
		fmt.printfln("@rayzr:mixer-peaks %s", strings.to_string(sb))
	case "mixer-set":
		// mixer-set <bus> volume|pan|mute|solo <value>
		parts := strings.fields(rest, context.temp_allocator)
		if len(parts) == 3 {
			bus, _ := strconv.parse_int(parts[0])
			v, _ := strconv.parse_f32(parts[2])
			switch parts[1] {
			case "volume": Mixer_SetBusVolume(bus, v)
			case "pan":    Mixer_SetBusPan(bus, v)
			case "mute":   Mixer_SetBusMute(bus, v != 0)
			case "solo":   Mixer_SetBusSolo(bus, v != 0)
			}
		}
	case "mixer-fx":
		// mixer-fx <bus> <slot> <param> <value>
		parts := strings.fields(rest, context.temp_allocator)
		if len(parts) == 4 {
			bus, _ := strconv.parse_int(parts[0])
			slot, _ := strconv.parse_int(parts[1])
			pi, _ := strconv.parse_int(parts[2])
			v, _ := strconv.parse_f32(parts[3])
			if e := Mixer_EffectRef(bus, slot); e != nil && pi >= 0 && pi < MIXER_MAX_PARAMS do e.params[pi] = v
		}
	case "mixer-fx-enabled":
		parts := strings.fields(rest, context.temp_allocator)
		if len(parts) == 3 {
			bus, _ := strconv.parse_int(parts[0])
			slot, _ := strconv.parse_int(parts[1])
			Mixer_SetEffectEnabled(bus, slot, parts[2] == "1")
		}
	case "mixer-load":
		// mixer-load <buses JSON>: the editor changed the mixer's layout.
		Mixer_LoadJSON(rest)
	case "sm-break":
		// sm-break <path> <state> 0|1
		parts := strings.fields(rest, context.temp_allocator)
		if len(parts) == 3 {
			key := strings.concatenate({parts[0], "|", parts[1]}, context.temp_allocator)
			for k, i in editorLink.smBreaks do if k == key {
				delete(k)
				ordered_remove(&editorLink.smBreaks, i)
				break
			}
			if parts[2] == "1" do append(&editorLink.smBreaks, strings.clone(key))
		}
	case "eval":
		text, ok := Lua_Eval(game.scriptManager.L, rest, context.temp_allocator)
		sb := strings.builder_make(context.temp_allocator)
		fmt.sbprintf(&sb, "{{\"ok\": %t, \"code\": ", ok)
		link_str(&sb, rest)
		strings.write_string(&sb, ", \"text\": ")
		link_str(&sb, text)
		fmt.printfln("@rayzr:eval %s}", strings.to_string(sb))
	case "record-start":
		// The editor's Record button (input_recorder.odin).
		Recorder_Start(game)
		fmt.printfln("@rayzr:recording true")
	case "record-stop":
		// rest: where to write it (project-relative); "" discards it.
		if rest == "" {
			Recorder_Discard()
			fmt.printfln("@rayzr:recording false")
		} else {
			path, ok := Recorder_Stop(game, rest)
			sb := strings.builder_make(context.temp_allocator)
			fmt.sbprintf(&sb, "{{\"ok\": %t, \"path\": ", ok)
			link_str(&sb, path)
			fmt.printfln("@rayzr:recorded %s}", strings.to_string(sb))
		}
	case "debug-draw":
		// Colliders, joints and areas drawn (the toolbar's Show Colliders).
		game.physicsWorld.drawPhysicsDebug = rest == "true"
		fmt.printfln("@rayzr:debug-draw %t", game.physicsWorld.drawPhysicsDebug)
	}
}

// Game_ReloadSceneFile re-reads a registered scene's file; the current
// scene restarts with it.
Game_ReloadSceneFile :: proc(game: ^Game, rel: string) -> bool {
	scene := Game_FindSceneByFile(game, rel)
	if scene == nil do return false
	bytes, ok := AssetManager_ReadFileBytes(&game.assetManager, rel, context.temp_allocator)
	if !ok do return false
	allocator := game.sceneManager.allocator if game.sceneManager.allocator.procedure != nil else context.allocator
	scene.sourceJson = strings.clone(string(bytes), allocator)
	if scene == game.sceneManager.currentScene do ChangeScene_ByName(&game.sceneManager, scene.name)
	return true
}

// link_find: a node by its name path from the current scene's root.
@(private = "file")
link_find :: proc(game: ^Game, path: string) -> ^Node {
	scene := game.sceneManager.currentScene
	if scene == nil || scene.rootNode == nil do return nil
	n := scene.rootNode
	if path == "" || path == "/" do return n
	for part in strings.split(path, "/", context.temp_allocator) {
		next: ^Node
		for c in GetChildrenView(scene.manager, n) do if c != nil && c.name == part {next = c; break}
		if next == nil do return nil
		n = next
	}
	return n
}

// EditorLink_TreeJSON: the current scene's tree (its root JSON and hash
// from EditorLink_TreeRootJSON, or computed).
EditorLink_TreeJSON :: proc(game: ^Game, root := "", hash: u64 = 0) -> string {
	root, hash := root, hash
	if root == "" do root, hash = EditorLink_TreeRootJSON(game)
	sb := strings.builder_make(context.temp_allocator)
	scene := game.sceneManager.currentScene
	fmt.sbprintf(&sb, "{{\"frame\": %d, \"frozen\": %t, \"paused\": %t, \"hash\": \"%d\", \"scene\": ", editorLink.frame, game.frozen, game.linkPaused, hash)
	link_str(&sb, scene.filePath if scene != nil else "")
	strings.write_string(&sb, ", \"root\": ")
	strings.write_string(&sb, root)
	strings.write_byte(&sb, '}')
	return strings.to_string(sb)
}

// EditorLink_TreeRootJSON: the scene tree (names, types, enabled /
// visible) and its FNV-1a hash.
EditorLink_TreeRootJSON :: proc(game: ^Game) -> (string, u64) {
	sb := strings.builder_make(context.temp_allocator)
	scene := game.sceneManager.currentScene
	walk :: proc(sb: ^strings.Builder, m: ^NodeManager, n: ^Node) {
		strings.write_string(sb, "{\"name\": ")
		link_str(sb, n.name)
		strings.write_string(sb, ", \"type\": ")
		link_str(sb, Node_TypeName(n))
		fmt.sbprintf(sb, ", \"enabled\": %t, \"visible\": %t", n.enabled, n.renderable)
		kids := GetChildrenView(m, n)
		if len(kids) > 0 {
			strings.write_string(sb, ", \"children\": [")
			k := 0
			for c in kids {
				if c == nil do continue
				if k > 0 do strings.write_string(sb, ", ")
				walk(sb, m, c)
				k += 1
			}
			strings.write_byte(sb, ']')
		}
		strings.write_byte(sb, '}')
	}
	if scene != nil && scene.rootNode != nil do walk(&sb, scene.manager, scene.rootNode)
	else do strings.write_string(&sb, "null")
	text := strings.to_string(sb)
	h: u64 = 14695981039346656037
	for i in 0 ..< len(text) do h = (h ~ u64(text[i])) * 1099511628211
	return text, h
}

EditorLink_NodeJSON :: proc(game: ^Game, path: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "{\"path\": ")
	link_str(&sb, path)
	n := link_find(game, path)
	if n == nil {
		strings.write_string(&sb, ", \"missing\": true}")
		return strings.to_string(sb)
	}
	strings.write_string(&sb, ", \"type\": ")
	link_str(&sb, Node_TypeName(n))
	strings.write_string(&sb, ", \"props\": [")
	prop :: proc(sb: ^strings.Builder, first: ^bool, name, value: string, kind := "string", extra := "") {
		if !first^ do strings.write_string(sb, ", ")
		first^ = false
		strings.write_byte(sb, '[')
		link_str(sb, name)
		strings.write_string(sb, ", ")
		link_str(sb, value)
		strings.write_string(sb, ", ")
		link_str(sb, kind)
		strings.write_string(sb, ", ")
		link_str(sb, extra)
		strings.write_byte(sb, ']')
	}
	first := true
	prop(&sb, &first, "position", fmt.tprintf("%.2f,%.2f", n.position.x, n.position.y), "vec2")
	prop(&sb, &first, "global", fmt.tprintf("%.2f,%.2f", n.globalPosition.x, n.globalPosition.y), "ro")
	prop(&sb, &first, "rotation", fmt.tprintf("%.2f", n.rotation), "float")
	prop(&sb, &first, "scale", fmt.tprintf("%.3f,%.3f", n.scale.x, n.scale.y), "vec2")
	prop(&sb, &first, "enabled", fmt.tprintf("%t", n.enabled), "bool")
	prop(&sb, &first, "visible", fmt.tprintf("%t", n.renderable), "bool")
	for p in Node_CollectProperties(n) {
		kind, extra := link_prop_kind(p)
		prop(&sb, &first, p.name, Property_ToString(p), kind, extra)
	}
	// Its script's exported properties ("script.<name>"), live from self.
	if inst := cast(^ScriptInstance)n.scriptInstance; inst != nil && game.scriptManager.L != nil {
		if mod, ok := game.scriptManager.modules[ScriptVFS_NormalizePath(inst.modulePath)]; ok && mod != nil {
			L := game.scriptManager.L
			for p in mod.properties {
				lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef))
				lua.getfield(L, -1, strings.clone_to_cstring(p.name, context.temp_allocator))
				text: string
				#partial switch lua.type(L, -1) {
				case .NUMBER:   text = fmt.tprintf("%v", f64(lua.tonumber(L, -1)))
				case .BOOLEAN:  text = "true" if lua.toboolean(L, -1) else "false"
				case .STRING:   text = strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
				case .TABLE:
					if p.type == .Color || p.type == .Vector2 {
						// "r,g,b,a" / "x,y" (as the Game tab edits them)
						parts := make([dynamic]string, context.temp_allocator)
						for i in 1 ..= int(lua.rawlen(L, -1)) {
							lua.rawgeti(L, -1, lua.Integer(i))
							append(&parts, fmt.tprintf("%v", f64(lua.tonumber(L, -1))))
							lua.pop(L, 1)
						}
						text = strings.join(parts[:], ",", context.temp_allocator)
					} else {
						text = lua_to_json(L, -1)
					}
				case .USERDATA:
					if target, isNode := to_node_userdata(L, -1); isNode && target != nil do text = target.name
				case: text = ""
				}
				lua.pop(L, 2)
				sk, sx := "string", ""
				#partial switch p.type {
				case .Float: sk = "float"
				case .Int: sk = "int"
				case .Boolean: sk = "bool"
				case .Vector2: sk = "vec2"
				case .Color: sk = "color01"
				}
				if len(p.values) > 0 do sk, sx = "enum", strings.join(p.values[:], "|", context.temp_allocator)
				else if (sk == "float" || sk == "int") && p.max > p.min do sx = fmt.tprintf("%g|%g", p.min, p.max)
				prop(&sb, &first, fmt.tprintf("script.%s", p.name), text, sk, sx)
			}
		}
	}
	strings.write_string(&sb, "]}")
	return strings.to_string(sb)
}

// link_set_script sets an exported script property from text, by its
// declared type: numbers, true / false, "x,y" / "r,g,b,a", JSON lists,
// strings (and enums, asset paths, node paths) as they are.
@(private = "file")
link_set_script :: proc(game: ^Game, n: ^Node, field, value: string) -> bool {
	inst := cast(^ScriptInstance)n.scriptInstance
	if inst == nil do return false
	mod, ok := game.scriptManager.modules[ScriptVFS_NormalizePath(inst.modulePath)]
	if !ok || mod == nil do return false
	for p in mod.properties {
		if p.name != field do continue
		v := ScriptValue{type = p.type}
		parts := strings.split(value, ",", context.temp_allocator)
		switch p.type {
		case .Float:
			f, fok := strconv.parse_f32(strings.trim_space(value))
			if !fok do return false
			v.valFloat = f
		case .Int:
			i, iok := strconv.parse_i64(strings.trim_space(value))
			if !iok do return false
			v.valInt = i
		case .Boolean:
			v.valBool = strings.trim_space(value) == "true"
		case .String:
			v.valString = strings.clone(value, context.temp_allocator)
		case .Vector2:
			if len(parts) != 2 do return false
			for i in 0 ..< 2 do v.valVec2[i], _ = strconv.parse_f32(strings.trim_space(parts[i]))
		case .Color:
			if len(parts) < 3 do return false
			v.valColor = {1, 1, 1, 1}
			for i in 0 ..< min(len(parts), 4) do v.valColor[i], _ = strconv.parse_f32(strings.trim_space(parts[i]))
		}
		return ScriptInstance_SetProperty(inst, field, v, &game.scriptManager)
	}
	return false
}

// EditorLink_Set changes a node's transform or reflected property from text.
EditorLink_Set :: proc(game: ^Game, path, name, value: string) -> bool {
	n := link_find(game, path)
	if n == nil do return false
	return Node_SetFromText(game, n, name, value)
}

// Node_SetFromText sets a node's transform, reflected property or (in a
// running game) script property from its text form - the live inspector's
// edits, and the editor applying runtime values to a scene.
Node_SetFromText :: proc(game: ^Game, n: ^Node, name, value: string) -> bool {
	vec :: proc(s: string) -> ([2]f32, bool) {
		parts := strings.split(s, ",", context.temp_allocator)
		if len(parts) != 2 do return {}, false
		x, ok1 := strconv.parse_f32(strings.trim_space(parts[0]))
		y, ok2 := strconv.parse_f32(strings.trim_space(parts[1]))
		return {x, y}, ok1 && ok2
	}
	switch name {
	case "position":
		v, ok := vec(value)
		if ok do n.position = v
		return ok
	case "scale":
		v, ok := vec(value)
		if ok do n.scale = v
		return ok
	case "rotation":
		v, ok := strconv.parse_f32(value)
		if ok do n.rotation = v
		return ok
	case "enabled": n.enabled = value == "true"; return true
	case "visible": n.renderable = value == "true"; return true
	}
	if strings.has_prefix(name, "script.") do return link_set_script(game, n, name[len("script."):], value)
	p, found := Node_FindProperty(n, name)
	if !found do return false
	return Property_FromString(n, p, value)
}

// Property_ToString / Property_FromString: a property's value as text
// ("1.5", "true", "10,20", "#ff8800ff", enum names, bit-set names joined
// with '|').
Property_ToString :: proc(p: Node_Property) -> string {
	switch p.kind {
	case .Float: return fmt.tprintf("%v", Property_GetFloat(p))
	case .Int: return fmt.tprintf("%v", Property_GetInt(p))
	case .Bool: return "true" if (^bool)(p.ptr)^ else "false"
	case .Vec2:
		v := (^[2]f32)(p.ptr)^
		return fmt.tprintf("%v,%v", v.x, v.y)
	case .Color:
		c := (^rl.Color)(p.ptr)^
		return fmt.tprintf("#%02x%02x%02x%02x", c.r, c.g, c.b, c.a)
	case .String: return (^string)(p.ptr)^
	case .String_List: return strings.join(Property_GetList(p), "\n", context.temp_allocator) // (a line each)
	case .Enum:
		names := Property_EnumNames(p)
		i := Property_GetEnumIndex(p)
		return names[i] if i >= 0 && i < len(names) else ""
	case .Bit_Set:
		on := make([dynamic]string, context.temp_allocator)
		for nm, i in Property_EnumNames(p) do if Property_BitSetHas(p, i) do append(&on, nm)
		return strings.join(on[:], "|", context.temp_allocator)
	}
	return ""
}

Property_FromString :: proc(node: ^Node, p: Node_Property, value: string) -> bool {
	value := strings.trim_space(value)
	switch p.kind {
	case .Float:
		v, ok := strconv.parse_f32(value)
		if ok do Property_SetFloat(p, v)
		return ok
	case .Int:
		v, ok := strconv.parse_i64(value)
		if ok do Property_SetInt(p, v)
		return ok
	case .Bool:
		(^bool)(p.ptr)^ = value == "true" || value == "1"
		return true
	case .Vec2:
		parts := strings.split(value, ",", context.temp_allocator)
		if len(parts) != 2 do return false
		x, ok1 := strconv.parse_f32(strings.trim_space(parts[0]))
		y, ok2 := strconv.parse_f32(strings.trim_space(parts[1]))
		if ok1 && ok2 do (^[2]f32)(p.ptr)^ = {x, y}
		return ok1 && ok2
	case .Color:
		hex := strings.trim_prefix(value, "#")
		if len(hex) != 6 && len(hex) != 8 do return false
		v, ok := strconv.parse_u64(hex, 16)
		if !ok do return false
		if len(hex) == 6 do v = v << 8 | 0xff
		(^rl.Color)(p.ptr)^ = {u8(v >> 24), u8(v >> 16), u8(v >> 8), u8(v)}
		return true
	case .String:
		Property_SetString(node, p, value)
		return true
	case .String_List:
		lines := strings.split_lines(value, context.temp_allocator)
		if value == "" do lines = nil
		Property_SetList(node, p, lines)
		return true
	case .Enum:
		for nm, i in Property_EnumNames(p) do if nm == value {Property_SetEnumIndex(p, i); return true}
		return false
	case .Bit_Set:
		names := Property_EnumNames(p)
		want := strings.split(value, "|", context.temp_allocator)
		for nm, i in names {
			on := false
			for w in want do if strings.trim_space(w) == nm do on = true
			Property_BitSetSet(p, i, on)
		}
		return true
	}
	return false
}

@(private = "file")
link_str :: proc(sb: ^strings.Builder, s: string) {
	strings.write_byte(sb, '"')
	for r in s {
		switch r {
		case '"': strings.write_string(sb, `\"`)
		case '\\': strings.write_string(sb, `\\`)
		case '\n': strings.write_string(sb, `\n`)
		case: strings.write_rune(sb, r)
		}
	}
	strings.write_byte(sb, '"')
}

// link_sm_enter: a machine entered a state - pause there when the editor
// asked (sm-break), like a breakpoint.
@(private = "file")
link_sm_enter :: proc(sm: ^StateMachineNode, state: string) {
	if len(editorLink.smBreaks) == 0 || editorLink.game == nil do return
	scene := editorLink.game.sceneManager.currentScene
	if scene == nil || scene.rootNode == nil do return
	path := Node_RelativePath(scene.manager, scene.rootNode, sm)
	key := strings.concatenate({path, "|", state}, context.temp_allocator)
	for k in editorLink.smBreaks do if k == key {
		editorLink.game.linkPaused = true
		sb := strings.builder_make(context.temp_allocator)
		strings.write_string(&sb, "{\"path\": ")
		link_str(&sb, path)
		strings.write_string(&sb, ", \"state\": ")
		link_str(&sb, state)
		strings.write_byte(&sb, '}')
		fmt.printfln("@rayzr:sm-break %s", strings.to_string(sb))
		fmt.println("@rayzr:paused")
		return
	}
}


// link_prop_kind: a reflected property's widget kind and extra (enum names,
// range) for the editor's live inspector.
@(private = "file")
link_prop_kind :: proc(p: Node_Property) -> (kind: string, extra: string) {
	switch p.kind {
	case .Float: kind = "float"
	case .Int: kind = "int"
	case .Bool: kind = "bool"
	case .Vec2: kind = "vec2"
	case .Color: kind = "color"
	case .Enum: kind = "enum"
	case .Bit_Set: kind = "bit_set"
	case .String: kind = "string"
	case .String_List: kind = "string_list"
	}
	if p.kind == .Enum || p.kind == .Bit_Set {
		extra = strings.join(Property_EnumNames(p), "|", context.temp_allocator)
	} else if p.has_range {
		extra = fmt.tprintf("%g|%g", p.min, p.max)
	}
	return
}

// link_path: a node's name path from the scene root ("Player/Gun").
link_path :: proc(m: ^NodeManager, root, n: ^Node) -> string {
	parts := make([dynamic]string, context.temp_allocator)
	for c := n; c != nil && c != root; c = GetParent(m, c) do inject_at(&parts, 0, c.name)
	return strings.join(parts[:], "/", context.temp_allocator)
}

// EditorLink_Pick: the topmost drawn node under a screen point (virtual
// game pixels), from the top layer down - each layer in the space it is
// drawn in (the camera's layers in the world).
EditorLink_Pick :: proc(game: ^Game, screen: [2]f32) -> ^Node {
	scene := game.sceneManager.currentScene
	if scene == nil do return nil
	buckets := Scene_CollectRenderables(scene)
	world := screen
	cam := scene.camera
	vw, vh: f32 = 1280, 720
	if game.virtualSize.x > 0 do vw, vh = game.virtualSize.x, game.virtualSize.y
	if cam != nil do world = rl.GetScreenToWorld2D(screen, CameraNode_GetCamera2D(cam, vw, vh))
	for li := len(RenderLayer) - 1; li >= 0; li -= 1 {
		layer := RenderLayer(li)
		isWorld := cam != nil && cam.enabled && cam.isCurrent && (layer in cam.targetLayers)
		p := world if isWorld else screen
		#reverse for n in buckets[layer] {
			if n == nil || n == scene.rootNode do continue
			r: rl.Rectangle
			ok: bool
			if n.isUI {
				r, ok = UI_GetElementRect(cast(^UIElement)n), true
			} else {
				r, ok = Node_RenderBounds(n)
			}
			if ok && p.x >= r.x && p.y >= r.y && p.x <= r.x + r.width && p.y <= r.y + r.height do return n
		}
	}
	return nil
}

// EditorLink_DrawOverlay outlines the highlighted node (after the scene's
// layers, with the camera for world nodes).
EditorLink_DrawOverlay :: proc(game: ^Game) {
	if !editorLink.enabled || editorLink.highlight == "" || !rl.IsWindowReady() do return
	n := link_find(game, editorLink.highlight)
	scene := game.sceneManager.currentScene
	if n == nil || scene == nil || n == scene.rootNode do return
	col := rl.Color{255, 196, 0, 255}
	r: rl.Rectangle
	ok: bool
	if n.isUI do r, ok = UI_GetElementRect(cast(^UIElement)n), true
	else do r, ok = Node_RenderBounds(n)
	if !ok do r = {n.globalPosition.x - 8, n.globalPosition.y - 8, 16, 16}
	// In the space its layer is drawn in.
	cam := scene.camera
	if cam != nil && !(cam.enabled && cam.isCurrent && (n.layer in cam.targetLayers)) do cam = nil
	vw, vh: f32 = 1280, 720
	if game.virtualSize.x > 0 do vw, vh = game.virtualSize.x, game.virtualSize.y
	zoom: f32 = 1
	if cam != nil {
		c2 := CameraNode_GetCamera2D(cam, vw, vh)
		zoom = max(c2.zoom, 0.01)
		rl.BeginMode2D(c2)
	}
	rl.DrawRectangleLinesEx(r, 2 / zoom, col)
	rl.DrawCircleV(n.globalPosition, 3 / zoom, col)
	if cam != nil do rl.EndMode2D()
}

// EditorLink_UpdatePick: while picking, a left click picks (game input
// still sees the click).
EditorLink_UpdatePick :: proc(game: ^Game) {
	if !editorLink.enabled || !editorLink.picking || !rl.IsWindowReady() do return
	if !rl.IsMouseButtonPressed(.LEFT) do return
	editorLink.picking = false
	scene := game.sceneManager.currentScene
	n := EditorLink_Pick(game, rl.GetMousePosition())
	path := link_path(scene.manager, scene.rootNode, n) if n != nil else ""
	fmt.printfln("@rayzr:picked %s", path)
}
