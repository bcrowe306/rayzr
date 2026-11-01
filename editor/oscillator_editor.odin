package editor

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:strings"
import imgui "lib/imgui"
import e "../engine"

// ============================================================================
// The Oscillator's Inspector: its wave as a graph (a playhead while it
// runs), Preview (runs it in the editor; Stop puts the targets back) and
// the mappings - a node, a property of it, Min / Max, Relative or
// Absolute, Phase and Value Offset.
// ============================================================================

// oscPreview: the oscillator running in the editor (nil: none).
oscPreview: ^e.OscillatorNode

// OscPreview_Tick advances the previewed oscillator (outside Simulate).
OscPreview_Tick :: proc(state: ^EditorState, dt: f32) {
	o := oscPreview
	if o == nil do return
	if !e.Node_IsAlive(o) || state.activeScene == nil || o.gameContext == nil || o.gameContext.scene != state.activeScene {
		oscPreview = nil // (gone: an undo, another scene)
		return
	}
	if state.isSimulating {
		OscPreview_Stop()
		return
	}
	e.OscillatorNode_Advance(o, min(dt, 0.1))
	if o.state == .Stopped do OscPreview_Stop() // its Loops ran
}

// OscPreview_Stop ends the preview: the targets go back as they were.
OscPreview_Stop :: proc() {
	o := oscPreview
	oscPreview = nil
	if o == nil || !e.Node_IsAlive(o) do return
	e.OscillatorNode_Stop(o)
	o.preview = false
}

@(private = "file")
osc_preview_start :: proc(o: ^e.OscillatorNode) {
	OscPreview_Stop()
	o.preview = true
	e.OscillatorNode_Start(o)
	oscPreview = o
}

inspector_oscillator :: proc(state: ^EditorState, o: ^e.OscillatorNode) {
	if UI_SectionHeader("Wave") {
		osc_graph(o)
		previewing := oscPreview == o
		if state.isSimulating {
			UI_DimTextWrapped(fmt.tprintf("%s · %.2f cycles", o.state, o.cycles))
		} else if UI_Button(previewing ? fmt.tprintf("%s  Stop Preview", ICON_FA_STOP) : fmt.tprintf("%s  Preview", ICON_FA_PLAY), "insp.osc.preview", {-1, 0}) {
			if previewing do OscPreview_Stop()
			else do osc_preview_start(o)
		}
		UI_Tooltip("Runs the oscillator here, without playing; Stop puts its targets back (the preview's values are never saved)")
		if o.wave == .Curve {
			if UI_BeginProps("##osccurve") {
				UI_PropLabel("Curve")
				sb := strings.builder_make(context.temp_allocator)
				strings.write_byte(&sb, '[')
				for i in 0 ..< o.curve.count {
					if i > 0 do strings.write_string(&sb, ", ")
					fmt.sbprintf(&sb, "[%g, %g]", o.curve.points[i].x, o.curve.points[i].y)
				}
				strings.write_byte(&sb, ']')
				@(static) dragging: bool
				if text, changed := script_curve_field("insp.osc.curve", strings.to_string(sb)); changed {
					if !dragging do Editor_RecordUndo(state, "Edit oscillator curve") // (one step per drag)
					dragging = true
					if v, err := json.parse_string(text, allocator = context.temp_allocator); err == .None {
						if arr, ok := v.(json.Array); ok do e.ParticleCurve_FromJSON(&o.curve, arr)
					}
				}
				if !imgui.IsMouseDown(.Left) do dragging = false
				UI_EndProps()
			}
		}
	}
	if !UI_SectionHeader("Mappings") do return
	if len(o.mappings) == 0 do UI_DimTextWrapped("Add the properties it drives: a node, one of its properties, and the range.")
	remove := -1
	for &m, i in o.mappings {
		imgui.PushIDInt(i32(i))
		imgui.Separator()
		UI_DimText(fmt.tprintf("%d", i + 1))
		imgui.SameLine()
		target := osc_target_node(state, o, m.target)
		UI_DimText(fmt.tprintf("%s  %s", target.name if target != nil else m.target, m.property) if m.property != "" else "(no property)")
		imgui.SameLine(imgui.GetContentRegionAvail().x + imgui.GetCursorPosX() - 24)
		if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("insp.osc.remove:%d", i), "Remove this mapping (its target goes back as it was)", size = 24) do remove = i
		if UI_BeginProps("##oscmap") {
			UI_PropLabel("Node")
			if path, changed := node_ref_field(state, o, fmt.tprintf("insp.osc.target:%d", i), m.target); changed {
				Editor_RecordUndo(state, "Oscillator target")
				e.OscillatorNode_ReleaseMapping(o, i)
				delete(m.target, o.allocator)
				m.target = strings.clone(path, o.allocator)
				target = osc_target_node(state, o, m.target)
			}
			UI_PropLabel("Property")
			osc_property_combo(state, o, i, target)
			width := e.Osc_PropertyWidth(target, m.property) if target != nil else 0
			if width == 0 && m.property != "" do UI_DimText(fmt.tprintf("%s not a number on this node", ICON_FA_TRIANGLE_EXCLAMATION))
			width = max(width, 1)
			UI_PropLabel("Mode")
			mode := i32(m.mode)
			imgui.SetNextItemWidth(-1)
			if imgui.Combo("##mode", &mode, "Relative\x00Absolute\x00") {
				Editor_RecordUndo(state, "Oscillator mode")
				m.mode = e.Osc_Apply(mode)
			}
			Drive_Item(fmt.tprintf("insp.osc.mode:%d", i))
			UI_Tooltip("Relative: added to the property's value when it starts (a platform moves around where you put it). Absolute: the property is set to it")
			osc_values(state, "Min", fmt.tprintf("insp.osc.min:%d", i), &m.min, width, "The value at the bottom of the wave (Relative: added to the property's own value)")
			osc_values(state, "Max", fmt.tprintf("insp.osc.max:%d", i), &m.max, width, "The value at the top of the wave")
			UI_PropLabel("Phase")
			imgui.SetNextItemWidth(-1)
			imgui.DragFloat("##phase", &m.phase, 1, -360, 360, "%.0f°")
			undo_on_activate(state, "Oscillator phase")
			Drive_Item(fmt.tprintf("insp.osc.phase:%d", i))
			UI_Tooltip("Shifts this mapping along the cycle (degrees): 180 is half a cycle out of step")
			osc_values(state, "Value Offset", fmt.tprintf("insp.osc.offset:%d", i), &m.offset, width, "Added to the value")
			UI_EndProps()
		}
		imgui.PopID()
	}
	if remove >= 0 {
		Editor_RecordUndo(state, "Remove oscillator mapping")
		e.OscillatorNode_RemoveMapping(o, remove)
	}
	imgui.Dummy({0, 4})
	if UI_Button(fmt.tprintf("%s  Add Mapping", ICON_FA_PLUS), "insp.osc.add", {-1, 0}) {
		Editor_RecordUndo(state, "Add oscillator mapping")
		target := ".." if o.parent != nil && o.parent != state.activeScene.rootNode else ""
		e.OscillatorNode_AddMapping(o, target, "position.y", {-16, 0, 0, 0}, {16, 0, 0, 0})
	}
	UI_Tooltip("Drive another property (a new mapping bobs its parent up and down)")
}

@(private = "file")
osc_target_node :: proc(state: ^EditorState, o: ^e.OscillatorNode, path: string) -> ^e.Node {
	if path == "" || path == "." do return o
	return e.Node_ResolvePath(state.activeScene.manager, o, path)
}

// osc_values: Min / Max / Value Offset as 1, 2 or 4 numbers.
@(private = "file")
osc_values :: proc(state: ^EditorState, label, id: string, v: ^[4]f32, width: int, tip: string) {
	UI_PropLabel(label)
	imgui.SetNextItemWidth(-1)
	cid := fmt.ctprintf("##%s", id)
	switch width {
	case 1: imgui.DragFloat(cid, &v[0], 0.5, 0, 0, "%.2f")
	case 2: imgui.DragFloat2(cid, cast(^[2]f32)v, 0.5, 0, 0, "%.2f")
	case:   imgui.DragFloat4(cid, v, 0.5, 0, 0, "%.0f")
	}
	undo_on_activate(state, fmt.tprintf("Oscillator %s", label))
	Drive_Item(id)
	UI_Tooltip(tip if width != 4 else fmt.tprintf("%s (colours: 0-255 each)", tip))
}

// osc_property_combo: the numeric properties of the target, whole and by
// component ("position", "position.x", "position.y").
@(private = "file")
osc_property_combo :: proc(state: ^EditorState, o: ^e.OscillatorNode, i: int, target: ^e.Node) {
	m := &o.mappings[i]
	imgui.SetNextItemWidth(-1)
	shown := m.property if m.property != "" else "(pick one)"
	if imgui.BeginCombo("##prop", strings.clone_to_cstring(shown, context.temp_allocator)) {
		if target == nil {
			UI_DimText("Pick a node first")
		} else {
			names := make([dynamic]string, context.temp_allocator)
			for n in ([]string{"position", "rotation", "scale"}) do append(&names, n)
			for p in e.Node_CollectProperties(target) do if !p.runtime do append(&names, p.name)
			for name in names {
				width := e.Osc_PropertyWidth(target, name)
				if width == 0 do continue
				osc_property_item(state, o, i, name)
				if width == 2 do for c in ([]string{"x", "y"}) do osc_property_item(state, o, i, fmt.tprintf("%s.%s", name, c), true)
				if width == 4 do for c in ([]string{"r", "g", "b", "a"}) do osc_property_item(state, o, i, fmt.tprintf("%s.%s", name, c), true)
			}
		}
		imgui.EndCombo()
	}
	Drive_Item(fmt.tprintf("insp.osc.property:%d", i))
	UI_Tooltip("The property it drives: a number, one component (position.x, color.a) or a whole vector or colour")
}

@(private = "file")
osc_property_item :: proc(state: ^EditorState, o: ^e.OscillatorNode, i: int, name: string, indent := false) {
	m := &o.mappings[i]
	label := fmt.ctprintf("%s%s", "    " if indent else "", name)
	if imgui.Selectable(label, m.property == name) && m.property != name {
		Editor_RecordUndo(state, "Oscillator property")
		e.OscillatorNode_ReleaseMapping(o, i)
		delete(m.property, o.allocator)
		m.property = strings.clone(name, o.allocator)
	}
	Drive_Item(fmt.tprintf("pick:%s", name))
}

// osc_graph: two cycles of the wave, and a playhead while it runs.
@(private = "file")
osc_graph :: proc(o: ^e.OscillatorNode) {
	w := imgui.GetContentRegionAvail().x
	h: f32 = 64
	cur := imgui.GetCursorScreenPos()
	mn := [2]f32{cur.x, cur.y}
	mx := mn + {w, h}
	dl := imgui.GetWindowDrawList()
	imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32(UI_BG_RAISED), 4)
	imgui.DrawList_AddRect(dl, mn, mx, col_u32(ui_line(0.15)), 4)
	pad: f32 = 6
	pw, ph := w - 2 * pad, h - 2 * pad
	imgui.DrawList_AddLine(dl, {mn.x + pad + pw / 2, mn.y + 2}, {mn.x + pad + pw / 2, mx.y - 2}, col_u32(ui_line(0.08)))
	// Noise shows this run's values when running, else a sample.
	seedWas := o.runSeed
	if o.runSeed == 0 do o.runSeed = u32(o.seed) if o.seed != 0 else 12345
	base := math.floor(o.cycles) if o.state != .Stopped else 0
	prev: [2]f32
	n := 160
	for k in 0 ..= n {
		t := f64(k) / f64(n) * 2
		v := e.OscillatorNode_Wave(o, base + t)
		p := [2]f32{mn.x + pad + f32(t / 2) * pw, mn.y + pad + (1 - v) * ph}
		if k > 0 do imgui.DrawList_AddLine(dl, prev, p, col_u32(UI_ACCENT), 2)
		prev = p
	}
	o.runSeed = seedWas
	if o.state != .Stopped {
		x := mn.x + pad + f32((o.cycles - base) / 2) * pw
		imgui.DrawList_AddLine(dl, {x, mn.y + 2}, {x, mx.y - 2}, col_u32(UI_TEXT), 1.5)
	}
	imgui.Dummy({w, h})
	Drive_Item("insp.osc.graph")
	hz := e.OscillatorNode_Hz(o)
	UI_Tooltip(fmt.tprintf("%v, two cycles (%.2f s each)", o.wave, 1 / hz) if hz > 0 else fmt.tprintf("%v (Rate 0: still)", o.wave))
}
