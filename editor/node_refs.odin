package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import buf "../odin_editor/buffer"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Rename-safe references. Renaming or moving a node can break what scene
// objects and scripts say about it:
// 1. Scene references: AnimationPlayer tracks, Camera follow targets,
//    AdvancedCamera targets/paths/limits, JointNode bodies, Signal connections,
//    StateMachine player/sub-machines, NavigationAgent map, Dialogue/LipSync,
//    and script node-reference properties.
// 2. Script references: `self.node:get_node("...")`, `self.node:get_child("...")`,
//    and `Scene.find_node("...")`.
// Before the change NodeRefs_Capture records what each of those points at;
// NodeRefs_AfterChange recomputes them: when paths or names change, a prompt
// notifies the user and offers to update all scene and script references.
// ============================================================================

Ref_Scene_Kind :: enum {
	AnimTrack,
	CameraFollow,
	AdvCamTarget,
	AdvCamPath,
	AdvCamLimit,
	JointBodyA,
	JointBodyB,
	Signal,
	StateMachinePlayer,
	StateMachineChild,
	NavMap,
	DialogueLipSync,
	TextPath,        // a Text node's Path (#270)
	OscTarget,       // an Oscillator mapping's node
	BTPath,          // a Behavior Tree's Actor (-1), Blackboard From (-2) or a node's Target (its index)
	LipSyncMouth,
	ScriptProp,
}

Ref_Scene_Item :: struct {
	kind:      Ref_Scene_Kind,
	owner:     ^e.Node,
	target:    ^e.Node,
	oldPath:   string,
	extraIdx:  int,
	extraIdx2: int,
	propName:  string,
	label:     string,
}

Ref_Scene_Edit :: struct {
	kind:        Ref_Scene_Kind,
	owner:       ^e.Node,
	target:      ^e.Node,
	oldPath:     string,
	newPath:     string,
	extraIdx:    int,
	extraIdx2:   int,
	propName:    string,
	description: string,
}

@(private = "file")
Ref_Literal :: struct {
	script: string, // project-relative
	call:   string, // the text before the literal: e.g. `self.node:get_node(`
	old:    string,
	owner:  ^e.Node,
	target: ^e.Node,
	byName: bool, // find_node / get_child: the name, not a path
}

Ref_Snapshot :: struct {
	lits:       [dynamic]Ref_Literal,
	sceneItems: [dynamic]Ref_Scene_Item,
}

Ref_Edit :: struct {
	script, call, old, new: string,
}

@(private = "file")
refs: struct {
	sceneEdits:  [dynamic]Ref_Scene_Edit, // waiting for the prompt (heap)
	scriptEdits: [dynamic]Ref_Edit,       // waiting for the prompt (heap)
	open:        bool,
}

@(private = "file")
REF_CALLS :: [?]string{"self.node:get_node(", "self.node:get_child(", "Scene.find_node("}

// script_text: an open document's text, else the file's.
@(private = "file")
script_text :: proc(state: ^EditorState, rel: string) -> string {
	abs := code_abs_path(state, rel)
	for d in GlobalCode.docs do if d.path == abs do return Code_DocText(d)
	data, err := os.read_entire_file(abs, context.temp_allocator)
	return string(data) if err == nil else ""
}

// literals: each string literal passed to `call` in a script.
@(private = "file")
literals :: proc(text, call: string) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	rest := text
	for {
		i := strings.index(rest, call)
		if i < 0 do break
		rest = rest[i + len(call):]
		t := strings.trim_left_space(rest)
		if len(t) < 2 || (t[0] != '"' && t[0] != '\'') do continue
		if j := strings.index_byte(t[1:], t[0]); j > 0 do append(&out, t[1:1 + j])
	}
	return out[:]
}

// NodeRefs_Capture records what scene objects, properties, and scripts point at now
// (temp-allocated; pass to NodeRefs_AfterChange the same frame).
NodeRefs_Capture :: proc(state: ^EditorState) -> (snap: Ref_Snapshot) {
	snap.lits = make([dynamic]Ref_Literal, context.temp_allocator)
	snap.sceneItems = make([dynamic]Ref_Scene_Item, context.temp_allocator)
	if state.activeScene == nil do return
	mgr := state.activeScene.manager

	// 1. Capture scene node references
	nodes := make([dynamic]^e.Node, context.temp_allocator)
	for n in mgr.nodes do append(&nodes, n)
	for n in mgr.addition do append(&nodes, n)

	for n in nodes {
		if n == nil || n.removing do continue

		switch n.typeId {
		case e.AnimationPlayerNode:
			apn := cast(^e.AnimationPlayerNode)n
			for anim, ai in apn.animations { if anim == nil do continue
				for &tr, ti in anim.tracks {
					if tr.target != "." && tr.target != "" {
						if target := e.Node_ResolvePath(mgr, apn, tr.target); target != nil {
							append(&snap.sceneItems, Ref_Scene_Item{
								kind = .AnimTrack,
								owner = n,
								target = target,
								oldPath = strings.clone(tr.target, context.temp_allocator),
								extraIdx = ai,
								extraIdx2 = ti,
								label = strings.clone(fmt.tprintf("Animation [%s] track '%s'", anim.name, tr.property), context.temp_allocator),
							})
						}
					}
				}
			}

		case e.CameraNode:
			cam := cast(^e.CameraNode)n
			if cam.followTarget != "" {
				if target := e.Node_ResolvePath(mgr, cam, cam.followTarget); target != nil {
					append(&snap.sceneItems, Ref_Scene_Item{
						kind = .CameraFollow,
						owner = n,
						target = target,
						oldPath = strings.clone(cam.followTarget, context.temp_allocator),
						label = "Follow Target",
					})
				}
			}

		case e.AdvancedCameraNode:
			ac := cast(^e.AdvancedCameraNode)n
			if ac.followTarget != "" {
				if target := e.Node_ResolvePath(mgr, ac, ac.followTarget); target != nil {
					append(&snap.sceneItems, Ref_Scene_Item{
						kind = .AdvCamTarget,
						owner = n,
						target = target,
						oldPath = strings.clone(ac.followTarget, context.temp_allocator),
						label = "Follow Target",
					})
				}
			}
			if ac.followPath != "" {
				if target := e.Node_ResolvePath(mgr, ac, ac.followPath); target != nil {
					append(&snap.sceneItems, Ref_Scene_Item{
						kind = .AdvCamPath,
						owner = n,
						target = target,
						oldPath = strings.clone(ac.followPath, context.temp_allocator),
						label = "Follow Path",
					})
				}
			}
			if ac.limitNode != "" {
				if target := e.Node_ResolvePath(mgr, ac, ac.limitNode); target != nil {
					append(&snap.sceneItems, Ref_Scene_Item{
						kind = .AdvCamLimit,
						owner = n,
						target = target,
						oldPath = strings.clone(ac.limitNode, context.temp_allocator),
						label = "Limit Node",
					})
				}
			}

		case e.JointNode:
			j := cast(^e.JointNode)n
			if j.bodyA != "" {
				if target := e.Node_ResolvePath(mgr, j, j.bodyA); target != nil {
					append(&snap.sceneItems, Ref_Scene_Item{
						kind = .JointBodyA,
						owner = n,
						target = target,
						oldPath = strings.clone(j.bodyA, context.temp_allocator),
						label = "Body A",
					})
				}
			}
			if j.bodyB != "" {
				if target := e.Node_ResolvePath(mgr, j, j.bodyB); target != nil {
					append(&snap.sceneItems, Ref_Scene_Item{
						kind = .JointBodyB,
						owner = n,
						target = target,
						oldPath = strings.clone(j.bodyB, context.temp_allocator),
						label = "Body B",
					})
				}
			}

		case e.StateMachineNode:
			sm := cast(^e.StateMachineNode)n
			if sm.player != "" {
				if target := e.Node_ResolvePath(mgr, sm, sm.player); target != nil {
					append(&snap.sceneItems, Ref_Scene_Item{
						kind = .StateMachinePlayer,
						owner = n,
						target = target,
						oldPath = strings.clone(sm.player, context.temp_allocator),
						label = "Player Node",
					})
				}
			}
			for &st, si in sm.states {
				if st.child != "" {
					if target := e.Node_ResolvePath(mgr, sm, st.child); target != nil {
						append(&snap.sceneItems, Ref_Scene_Item{
							kind = .StateMachineChild,
							owner = n,
							target = target,
							oldPath = strings.clone(st.child, context.temp_allocator),
							extraIdx = si,
							label = strings.clone(fmt.tprintf("State '%s' Sub-Machine", st.name), context.temp_allocator),
						})
					}
				}
			}

		case e.NavigationAgentNode:
			nav := cast(^e.NavigationAgentNode)n
			if nav.navMap != "" {
				if target := e.Node_ResolvePath(mgr, nav, nav.navMap); target != nil {
					append(&snap.sceneItems, Ref_Scene_Item{
						kind = .NavMap,
						owner = n,
						target = target,
						oldPath = strings.clone(nav.navMap, context.temp_allocator),
						label = "Navigation Map",
					})
				}
			}

		case e.BehaviorTreeNode:
			bt := cast(^e.BehaviorTreeNode)n
			bt_ref :: proc(snap: ^Ref_Snapshot, mgr: ^e.NodeManager, owner: ^e.Node, path: string, idx: int, label: string) {
				if path == "" || path == "." do return
				if target := e.Node_ResolvePath(mgr, owner, path); target != nil {
					append(&snap.sceneItems, Ref_Scene_Item{
						kind = .BTPath,
						owner = owner,
						target = target,
						oldPath = strings.clone(path, context.temp_allocator),
						extraIdx = idx,
						label = strings.clone(label, context.temp_allocator),
					})
				}
			}
			bt_ref(&snap, mgr, n, bt.actor, -1, "Behavior Tree Actor")
			bt_ref(&snap, mgr, n, bt.blackboardFrom, -2, "Behavior Tree Blackboard From")
			for &bn, bi in bt.nodes do bt_ref(&snap, mgr, n, bn.target, bi, fmt.tprintf("Behavior Tree node '%s'", e.BT_NodeName(&bn)))

		case e.OscillatorNode:
			o := cast(^e.OscillatorNode)n
			for &m, mi in o.mappings {
				if m.target == "" || m.target == "." do continue
				if target := e.Node_ResolvePath(mgr, o, m.target); target != nil {
					append(&snap.sceneItems, Ref_Scene_Item{
						kind = .OscTarget,
						owner = n,
						target = target,
						oldPath = strings.clone(m.target, context.temp_allocator),
						extraIdx = mi,
						label = strings.clone(fmt.tprintf("Oscillator mapping %d (%s)", mi + 1, m.property), context.temp_allocator),
					})
				}
			}

		case e.TextNode:
			tn := cast(^e.TextNode)n
			if tn.path != "" {
				if target := e.Node_ResolvePath(mgr, tn, tn.path); target != nil {
					append(&snap.sceneItems, Ref_Scene_Item{
						kind = .TextPath,
						owner = n,
						target = target,
						oldPath = strings.clone(tn.path, context.temp_allocator),
						label = "Text Path",
					})
				}
			}

		case e.DialogueNode:
			d := cast(^e.DialogueNode)n
			if d.lipSync != "" {
				if target := e.Node_ResolvePath(mgr, d, d.lipSync); target != nil {
					append(&snap.sceneItems, Ref_Scene_Item{
						kind = .DialogueLipSync,
						owner = n,
						target = target,
						oldPath = strings.clone(d.lipSync, context.temp_allocator),
						label = "LipSync Node",
					})
				}
			}

		case e.LipSyncNode:
			l := cast(^e.LipSyncNode)n
			if l.mouth != "" {
				if target := e.Node_ResolvePath(mgr, l, l.mouth); target != nil {
					append(&snap.sceneItems, Ref_Scene_Item{
						kind = .LipSyncMouth,
						owner = n,
						target = target,
						oldPath = strings.clone(l.mouth, context.temp_allocator),
						label = "Mouth Node",
					})
				}
			}
		}

		// Signal connections on this node
		for &c, ci in n.signalConnections {
			if c.target != "" {
				if target := e.Node_ResolvePath(mgr, n, c.target); target != nil {
					append(&snap.sceneItems, Ref_Scene_Item{
						kind = .Signal,
						owner = n,
						target = target,
						oldPath = strings.clone(c.target, context.temp_allocator),
						extraIdx = ci,
						label = strings.clone(fmt.tprintf("Signal '%s' -> %s", c.signal, c.method), context.temp_allocator),
					})
				}
			}
		}

		// Script component node-reference properties
		if n.scriptInstance != nil {
			inst := cast(^e.ScriptInstance)n.scriptInstance
			mod, ok := state.game.scriptManager.modules[e.ScriptVFS_NormalizePath(inst.modulePath)]
			if ok && mod != nil {
				for p in mod.properties {
					if p.assetKind != "node" do continue
					v := inst.properties[p.name] or_else {}
					if v.valString == "" do continue
					if target := e.Node_ResolvePath(mgr, n, v.valString); target != nil {
						append(&snap.sceneItems, Ref_Scene_Item{
							kind = .ScriptProp,
							owner = n,
							target = target,
							oldPath = strings.clone(v.valString, context.temp_allocator),
							propName = strings.clone(p.name, context.temp_allocator),
							label = strings.clone(fmt.tprintf("Script property '%s'", p.name), context.temp_allocator),
						})
					}
				}
			}
		}
	}

	// 2. Capture script text calls on scene node scripts
	for owner in mgr.nodes {
		if owner == nil || owner.scriptInstance == nil do continue
		inst := cast(^e.ScriptInstance)owner.scriptInstance
		rel := asset_rel_editor(state, inst.modulePath)
		text := script_text(state, rel)
		for call in REF_CALLS {
			for lit in literals(text, call) {
				target: ^e.Node
				byName := call != "self.node:get_node("
				switch call {
				case "self.node:get_node(":  target = e.Node_ResolvePath(mgr, owner, lit)
				case "self.node:get_child(": for c in e.GetChildrenView(mgr, owner) do if c != nil && c.name == lit {target = c; break}
				case "Scene.find_node(":     target = e.Scene_FindNodeByName(state.activeScene, lit)
				}
				if target != nil do append(&snap.lits, Ref_Literal{rel, call, lit, owner, target, byName})
			}
		}
	}

	// Also capture Scene.find_node in all project scripts
	for rel in Editor_ListProjectFiles(state, "", {".lua"}) {
		text := script_text(state, rel)
		for lit in literals(text, "Scene.find_node(") {
			if target := e.Scene_FindNodeByName(state.activeScene, lit); target != nil {
				dup := false
				for l in snap.lits do if l.script == rel && l.call == "Scene.find_node(" && l.old == lit do dup = true
				if !dup do append(&snap.lits, Ref_Literal{rel, "Scene.find_node(", lit, nil, target, true})
			}
		}
	}

	return
}

// NodeRefs_AfterChange collects scene and script edits that keep pointing at the same nodes.
NodeRefs_AfterChange :: proc(state: ^EditorState, snap: Ref_Snapshot) {
	if state.activeScene == nil do return
	mgr := state.activeScene.manager

	// 1. Check scene references
	sceneEdits := make([dynamic]Ref_Scene_Edit, context.temp_allocator)
	for item in snap.sceneItems {
		if item.owner == nil || item.owner.removing || item.target == nil || item.target.removing do continue
		newPath := e.Node_RelativePath(mgr, item.owner, item.target)
		if newPath == item.oldPath do continue
		desc := fmt.tprintf("%s on '%s'", item.label, item.owner.name)
		append(&sceneEdits, Ref_Scene_Edit{
			kind = item.kind,
			owner = item.owner,
			target = item.target,
			oldPath = item.oldPath,
			newPath = newPath,
			extraIdx = item.extraIdx,
			extraIdx2 = item.extraIdx2,
			propName = item.propName,
			description = desc,
		})
	}

	// 2. Check script references
	scriptEdits := make([dynamic]Ref_Edit, context.temp_allocator)
	for l in snap.lits {
		if l.target == nil || l.target.removing do continue
		if !l.byName && (l.owner == nil || l.owner.removing) do continue
		new := l.target.name if l.byName else e.Node_RelativePath(mgr, l.owner, l.target)
		if l.call == "self.node:get_child(" && l.owner != nil && e.GetParent(mgr, l.target) != l.owner do continue // not a child any more
		if new == l.old do continue
		dup := false
		for x in scriptEdits do if x.script == l.script && x.call == l.call && x.old == l.old do dup = true
		if !dup do append(&scriptEdits, Ref_Edit{l.script, l.call, l.old, new})
	}

	if len(sceneEdits) == 0 && len(scriptEdits) == 0 do return

	clear_all_edits()
	for s in sceneEdits {
		append(&refs.sceneEdits, Ref_Scene_Edit{
			kind = s.kind,
			owner = s.owner,
			target = s.target,
			oldPath = strings.clone(s.oldPath),
			newPath = strings.clone(s.newPath),
			extraIdx = s.extraIdx,
			extraIdx2 = s.extraIdx2,
			propName = strings.clone(s.propName),
			description = strings.clone(s.description),
		})
	}
	for x in scriptEdits {
		append(&refs.scriptEdits, Ref_Edit{
			script = strings.clone(x.script),
			call = strings.clone(x.call),
			old = strings.clone(x.old),
			new = strings.clone(x.new),
		})
	}
	refs.open = true
}

// NodeRefs_Pending: reference edits waiting for an answer (drives).
NodeRefs_Pending :: proc() -> int {
	return len(refs.sceneEdits) + len(refs.scriptEdits)
}
NodeRefs_IsOpen :: proc() -> bool {
	return refs.open
}

NodeRefs_SceneEdits :: proc() -> []Ref_Scene_Edit {
	return refs.sceneEdits[:]
}

NodeRefs_ScriptEdits :: proc() -> []Ref_Edit {
	return refs.scriptEdits[:]
}

NodeRefs_Apply :: proc(state: ^EditorState) -> (sceneCount, scriptCount: int) {
	sceneCount = apply_scene_edits(state)
	scriptCount = apply_script_edits(state)
	return
}

NodeRefs_Clear :: proc() {
	clear_all_edits()
}


// NodeRefs_Render: the "update references" prompt window.
NodeRefs_Render :: proc(state: ^EditorState) {
	if refs.open {
		imgui.OpenPopup("Update References###NodeRefs")
		refs.open = false
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if !imgui.BeginPopupModal("Update References###NodeRefs", nil, {.AlwaysAutoResize, .NoTitleBar}) do return
	defer imgui.EndPopup()

	imgui.PushFont(GlobalFonts.semibold)
	imgui.TextUnformatted(fmt.ctprintf("%s  Update node references?", ICON_FA_PEN))
	imgui.PopFont()
	UI_DimText("The node moved or was renamed; these still point at the old place:")
	imgui.Dummy({0, 6})

	// Scene references section
	if len(refs.sceneEdits) > 0 {
		imgui.PushFont(GlobalFonts.semibold)
		UI_DimText(fmt.tprintf("Scene References (%d):", len(refs.sceneEdits)))
		imgui.PopFont()
		for s in refs.sceneEdits {
			imgui.TextUnformatted(strings.clone_to_cstring(s.description, context.temp_allocator))
			imgui.SameLine(0, 8)
			UI_DimText(fmt.tprintf("%q  %s  %q", s.oldPath, ICON_FA_ARROW_RIGHT, s.newPath))
		}
		imgui.Dummy({0, 4})
	}

	// Script references section
	if len(refs.scriptEdits) > 0 {
		imgui.PushFont(GlobalFonts.semibold)
		UI_DimText(fmt.tprintf("Script References (%d):", len(refs.scriptEdits)))
		imgui.PopFont()
		for x in refs.scriptEdits {
			imgui.TextUnformatted(strings.clone_to_cstring(x.script, context.temp_allocator))
			imgui.SameLine(0, 8)
			UI_DimText(fmt.tprintf("%s%q)  %s  %s%q)", x.call, x.old, ICON_FA_ARROW_RIGHT, x.call, x.new))
		}
		imgui.Dummy({0, 6})
	}

	if UI_PrimaryButton(fmt.tprintf("%s  Update", ICON_FA_CHECK), "refs.update", {120, 30}) {
		nScene := apply_scene_edits(state)
		nScript := apply_script_edits(state)
		Editor_Log(state, .Info, "Updated %d scene reference(s) and %d script reference(s)", nScene, nScript)
		clear_all_edits()
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Skip", "refs.skip", {90, 30}) || imgui.IsKeyPressed(.Escape) {
		clear_all_edits()
		imgui.CloseCurrentPopup()
	}
}

@(private = "file")
clear_all_edits :: proc() {
	for x in refs.scriptEdits {
		delete(x.script)
		delete(x.call)
		delete(x.old)
		delete(x.new)
	}
	delete(refs.scriptEdits)
	refs.scriptEdits = {}
	for s in refs.sceneEdits {
		delete(s.oldPath)
		delete(s.newPath)
		delete(s.propName)
		delete(s.description)
	}
	delete(refs.sceneEdits)
	refs.sceneEdits = {}
	refs.open = false
}

// apply_scene_edits applies all captured scene property and connection updates.
@(private = "file")
apply_scene_edits :: proc(state: ^EditorState) -> int {
	if state.activeScene == nil do return 0
	count := 0
	Editor_RecordUndo(state, "Update scene references")
	for s in refs.sceneEdits {
		if s.owner == nil || s.owner.removing do continue
		switch s.kind {
		case .AnimTrack:
			apn := cast(^e.AnimationPlayerNode)s.owner
			if s.extraIdx >= 0 && s.extraIdx < len(apn.animations) {
				anim := apn.animations[s.extraIdx]
				if anim != nil && s.extraIdx2 >= 0 && s.extraIdx2 < len(anim.tracks) {
					tr := &anim.tracks[s.extraIdx2]
					tr.target = strings.clone(s.newPath, apn.allocator)
					count += 1
				}
			}
		case .CameraFollow:
			cam := cast(^e.CameraNode)s.owner
			cam.followTarget = strings.clone(s.newPath, cam.allocator)
			count += 1
		case .AdvCamTarget:
			ac := cast(^e.AdvancedCameraNode)s.owner
			ac.followTarget = strings.clone(s.newPath, ac.allocator)
			count += 1
		case .AdvCamPath:
			ac := cast(^e.AdvancedCameraNode)s.owner
			ac.followPath = strings.clone(s.newPath, ac.allocator)
			count += 1
		case .AdvCamLimit:
			ac := cast(^e.AdvancedCameraNode)s.owner
			ac.limitNode = strings.clone(s.newPath, ac.allocator)
			count += 1
		case .JointBodyA:
			j := cast(^e.JointNode)s.owner
			j.bodyA = strings.clone(s.newPath, j.allocator)
			count += 1
		case .JointBodyB:
			j := cast(^e.JointNode)s.owner
			j.bodyB = strings.clone(s.newPath, j.allocator)
			count += 1
		case .Signal:
			if s.extraIdx >= 0 && s.extraIdx < len(s.owner.signalConnections) {
				conn := &s.owner.signalConnections[s.extraIdx]
				conn.target = strings.clone(s.newPath, s.owner.allocator)
				count += 1
			}
		case .StateMachinePlayer:
			sm := cast(^e.StateMachineNode)s.owner
			sm.player = strings.clone(s.newPath, sm.allocator)
			count += 1
		case .StateMachineChild:
			sm := cast(^e.StateMachineNode)s.owner
			if s.extraIdx >= 0 && s.extraIdx < len(sm.states) {
				st := &sm.states[s.extraIdx]
				st.child = strings.clone(s.newPath, sm.allocator)
				count += 1
			}
		case .NavMap:
			nav := cast(^e.NavigationAgentNode)s.owner
			nav.navMap = strings.clone(s.newPath, nav.allocator)
			count += 1
		case .DialogueLipSync:
			d := cast(^e.DialogueNode)s.owner
			d.lipSync = strings.clone(s.newPath, d.allocator)
			count += 1
		case .BTPath:
			bt := cast(^e.BehaviorTreeNode)s.owner
			switch {
			case s.extraIdx == -1: e.BT_SetString(bt, &bt.actor, s.newPath)
			case s.extraIdx == -2: e.BT_SetString(bt, &bt.blackboardFrom, s.newPath)
			case s.extraIdx >= 0 && s.extraIdx < len(bt.nodes): e.BT_SetString(bt, &bt.nodes[s.extraIdx].target, s.newPath)
			}
			count += 1
		case .OscTarget:
			o := cast(^e.OscillatorNode)s.owner
			if s.extraIdx >= 0 && s.extraIdx < len(o.mappings) {
				o.mappings[s.extraIdx].target = strings.clone(s.newPath, o.allocator)
				count += 1
			}
		case .TextPath:
			tn := cast(^e.TextNode)s.owner
			tn.path = strings.clone(s.newPath, tn.allocator)
			count += 1
		case .LipSyncMouth:
			l := cast(^e.LipSyncNode)s.owner
			l.mouth = strings.clone(s.newPath, l.allocator)
			count += 1
		case .ScriptProp:
			if s.owner.scriptInstance != nil {
				inst := cast(^e.ScriptInstance)s.owner.scriptInstance
				e.ScriptInstance_SetProperty(inst, s.propName, {type = .String, valString = s.newPath}, &state.game.scriptManager)
				count += 1
			}
		}
	}
	return count
}

// apply_script_edits rewrites `call"old")` to `call"new")` (either quote): in open
// scripts as one undo step, other files on disk.
@(private = "file")
apply_script_edits :: proc(state: ^EditorState) -> int {
	count := 0
	scripts := make(map[string]bool, allocator = context.temp_allocator)
	for x in refs.scriptEdits do scripts[x.script] = true
	for rel in scripts {
		abs := code_abs_path(state, rel)
		var_doc: ^Code_Doc
		for d in GlobalCode.docs do if d.path == abs do var_doc = d
		if var_doc != nil {
			b := &var_doc.buffer
			group := buf.buffer_next_group(b)
			for x in refs.scriptEdits {
				if x.script != rel do continue
				for q in ([]string{"\"", "'"}) {
					from := strings.concatenate({x.call, q, x.old, q}, context.temp_allocator)
					to := strings.concatenate({x.call, q, x.new, q}, context.temp_allocator)
					for ln in 0 ..< buf.buffer_line_count(b) {
						for {
							line := buf.buffer_line_str(b, ln)
							i := strings.index(line, from)
							if i < 0 do break
							buf.buffer_delete_range(b, {ln, i}, {ln, i + len(from)}, group)
							buf.buffer_insert_text(b, {ln, i}, to, group)
							count += 1
						}
					}
				}
			}
			continue
		}
		data, err := os.read_entire_file(abs, context.temp_allocator)
		if err != nil do continue
		text := string(data)
		for x in refs.scriptEdits {
			if x.script != rel do continue
			for q in ([]string{"\"", "'"}) {
				from := strings.concatenate({x.call, q, x.old, q}, context.temp_allocator)
				to := strings.concatenate({x.call, q, x.new, q}, context.temp_allocator)
				n := strings.count(text, from)
				if n > 0 {
					text, _ = strings.replace_all(text, from, to, context.temp_allocator)
					count += n
				}
			}
		}
		_ = os.write_entire_file(abs, transmute([]u8)text)
	}
	_ = filepath.base
	return count
}
