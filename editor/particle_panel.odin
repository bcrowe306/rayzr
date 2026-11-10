package editor

import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Particle editor (bottom panel "Particles" tab) for ParticleEmitterNode:
// sub-tabs Emission / Shape / Motion / Size & Rotation / Color / Collision.
//
// Color: a gradient bar (colour over the particle's lifetime) with stops you
// drag, add (double-click the bar) and remove (right-click a stop); the
// selected stop's colour and alpha; and a plot of red, green, blue and alpha
// over the lifetime whose alpha points can be dragged directly.
// Every emitter runs in the viewport while editing (ParticlePreview_Tick)
// so its settings show live; the Particles tab's button pauses / resumes it.
// ============================================================================

@(private = "file")
Particle_Panel :: struct {
	selectedStop: int,
	dragStop:     int,  // stop being dragged on the gradient bar (-1 none)
	dragAlpha:    int,  // stop whose alpha is dragged on the plot (-1 none)
}

// particlePreview: emitters animate in the viewport outside Simulate.
particlePreview := true

// ParticlePreview_Tick runs the scene's particle emitters while editing
// (the editor doesn't update nodes outside Simulate).
ParticlePreview_Tick :: proc(state: ^EditorState, dt: f32) {
	if !particlePreview || state.activeScene == nil do return
	ctx := &state.game.gameContext
	for n in state.activeScene.manager.nodes {
		if n == nil || n.typeId != e.ParticleEmitterNode || n.removing do continue
		e.ParticleEmitterNode_Update(n, ctx, min(dt, 0.1))
	}
}

// ParticleAlive: live particles of an emitter (drives).
ParticleAlive :: proc(n: ^e.Node) -> int {
	if n == nil || n.typeId != e.ParticleEmitterNode do return -1
	return (cast(^e.ParticleEmitterNode)n).emitter.aliveCount // (CPU or GPU)
}

@(private = "file")
pp := Particle_Panel{dragStop = -1, dragAlpha = -1}

particleTabRequest := false // select the Particles tab next frame

// The sheet presets' texture and its licence (Kenney, CC0; #401), written
// into the project the first time one is applied.
PARTICLE_SHEET_PNG :: #load("../assets/kenney/particles/particles.png")
PARTICLE_SHEET_LICENSE :: #load("../assets/kenney/particles/License.txt")

// ParticleSheet_Ensure puts the particle sheet at e.PARTICLE_SHEET in the
// project (with its licence and a slicing preset) unless it is there.
ParticleSheet_Ensure :: proc(state: ^EditorState) -> bool {
	full, _ := filepath.join({state.projectPath, e.PARTICLE_SHEET}, context.temp_allocator)
	if os.is_file(full) do return true
	dir := filepath.dir(full, context.temp_allocator)
	_ = os.make_directory_all(dir)
	if os.write_entire_file(full, PARTICLE_SHEET_PNG) != nil {
		Editor_Log(state, .Error, "Could not write %s", e.PARTICLE_SHEET)
		return false
	}
	lic, _ := filepath.join({dir, "kenney_particles_License.txt"}, context.temp_allocator)
	_ = os.write_entire_file(lic, PARTICLE_SHEET_LICENSE)
	imp := Editor_AssetImport(state, full)
	imp.slice = {grid = {e.PARTICLE_SHEET_COLUMNS, 3}}
	preview_save_import(state, full, e.PARTICLE_SHEET, imp)
	Editor_InvalidateProjectFiles()
	Editor_Log(state, .Info, "Added %s (Kenney, CC0) for the particle sheet presets", e.PARTICLE_SHEET)
	return true
}

// particle_preset_menu: a starting look (fire, smoke, ...) for the emitter;
// it replaces the look and motion settings, so it's one undo step. Sheet
// presets (#401) also set the texture to the particle sheet.
@(private = "file")
particle_preset_menu :: proc(state: ^EditorState, pen: ^e.ParticleEmitterNode) {
	imgui.SetNextItemWidth(110)
	if imgui.BeginCombo("##particles.preset", ICON_FA_WAND_MAGIC_SPARKLES + " Preset", {.HeightLarge}) {
		for p in e.ParticlePreset {
			name := e.ParticlePreset_Name(p)
			if p == .Leaves {
				imgui.SeparatorText("With a sprite sheet")
			}
			if imgui.Selectable(fmt.ctprintf("%s", name)) {
				Editor_RecordUndo(state, fmt.tprintf("Apply %s preset", name))
				if !e.ParticlePreset_UsesSheet(p) || ParticleSheet_Ensure(state) {
					pen.gameContext = &state.game.gameContext
					e.ParticleEmitterNode_ApplyPreset(pen, p)
				}
				particlePreview = true
			}
			Drive_Item(fmt.tprintf("pick:%s", name))
			if e.ParticlePreset_UsesSheet(p) do UI_Tooltip("Sets the texture to " + e.PARTICLE_SHEET + " (Kenney's CC0 particle and foliage art, added to the project if it isn't there)")
		}
		imgui.EndCombo()
	}
	Drive_Item("particles.preset")
	UI_Tooltip("Give the emitter a starting look: fire, smoke, sparks, rain, snow, an explosion or magic - or leaves, debris, a smoke puff or a sparkle from a sprite sheet. Its look and motion settings are replaced; its texture stays (sheet presets set it)")
}

ParticlePanel_Render :: proc(state: ^EditorState) {
	node := state.selectedNode
	if node == nil || node.typeId != e.ParticleEmitterNode {
		imgui.Dummy({0, 8})
		UI_DimText("   Select a Particle Emitter node to edit its particles.")
		return
	}
	pen := cast(^e.ParticleEmitterNode)node
	em := &pen.emitter

	// Toolbar.
	imgui.Dummy({0, 2})
	if UI_IconButton(ICON_FA_PAUSE if particlePreview else ICON_FA_PLAY, "particles.preview", "Pause the particle preview in the viewport" if particlePreview else "Play the particle preview in the viewport", particlePreview, 26) {
		particlePreview = !particlePreview
	}
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_ROTATE_LEFT, "particles.restart", "Restart emission", size = 26) {
		for &p in em.particles do p.alive = false
		e.ParticleEmitter_Start(em)
	}
	imgui.SameLine(0, 2)
	particle_preset_menu(state, pen)
	imgui.SameLine(0, UI_SPACE)
	imgui.AlignTextToFramePadding()
	UI_DimText(fmt.tprintf("%d particles alive%s · %d per cycle · %.1fs lifetime", em.aliveCount, " (GPU)" if em.gpu else "", em.amount, em.lifetime))

	if !imgui.BeginTabBar("##particle_tabs", {}) do return
	defer imgui.EndTabBar()
	section :: proc(state: ^EditorState, node: ^e.Node, label: cstring, id: string, props: []string) {
		open := imgui.BeginTabItem(label)
		Drive_Item(id)
		if !open do return
		defer imgui.EndTabItem()
		if imgui.BeginChild("##ptab", {0, 0}, {}, {}) {
			if UI_BeginProps("##pprops") {
				for name in props {
					p, ok := e.Node_FindProperty(node, name)
					if !ok do continue
					UI_PropLabel(pretty_name(name))
					property_widget(state, node, p, false)
				}
				UI_EndProps()
			}
		}
		imgui.EndChild()
	}
	section(state, node, "Emission", "particles.tab:emission", {"emitter.gpu", "emitter.amount", "emitter.lifetime", "emitter.lifetimeVariance", "emitter.burst", "emitter.emitting", "emitter.continuous", "emitter.localSpace", "emitter.prewarm", "emitter.seed", "emitter.autoVisibility", "emitter.visibilityRect", "emitter.shape"})
	section(state, node, "Shape", "particles.tab:shape", {"emitter.emissionShape", "emitter.emissionRadius", "emitter.emissionInnerRadius", "emitter.emitAlongNormal", "emitter.spread", "emitter.angle", "emitter.angleVariance", "emitter.angleSpread"})
	section(state, node, "Motion", "particles.tab:motion", {"emitter.velocity", "emitter.velocityVariance", "emitter.velocitySpread", "emitter.velocityScale", "emitter.acceleration", "emitter.gravityDirection", "emitter.gravityVelocity", "emitter.wind", "emitter.radialVelocity", "emitter.orbitVelocity", "emitter.damping"})
	section(state, node, "Size & Rotation", "particles.tab:size", {"emitter.size", "emitter.sizeVariance", "emitter.sizeSpread", "emitter.scaleStart", "emitter.scaleEnd", "emitter.rotation", "emitter.rotationVariance", "emitter.rotationSpread", "emitter.torque", "emitter.torqueVariance", "emitter.torqueSpread", "emitter.torqueAcceleration"})
	colorOpen := imgui.BeginTabItem("Color")
	Drive_Item("particles.tab:color")
	if colorOpen {
		if imgui.BeginChild("##pcolor", {0, 0}, {}, {}) do particle_color(state, pen)
		imgui.EndChild()
		imgui.EndTabItem()
	}
	curvesOpen := imgui.BeginTabItem("Curves")
	Drive_Item("particles.tab:curves")
	if curvesOpen {
		if imgui.BeginChild("##pcurves", {0, 0}, {}, {}) do particle_curves(state, pen)
		imgui.EndChild()
		imgui.EndTabItem()
	}
	texOpen := imgui.BeginTabItem("Texture")
	Drive_Item("particles.tab:texture")
	if texOpen {
		if imgui.BeginChild("##ptex", {0, 0}, {}, {}) do particle_texture(state, pen)
		imgui.EndChild()
		imgui.EndTabItem()
	}
	if em.gpu {
		trailsOpen := imgui.BeginTabItem("Trails")
		Drive_Item("particles.tab:trails")
		if trailsOpen {
			imgui.Dummy({0, 6})
			UI_DimText("   GPU mode: particles have no trails (turn GPU off in Emission to use them).")
			imgui.EndTabItem()
		}
	} else {
		section(state, node, "Trails", "particles.tab:trails", {"emitter.trailLength", "emitter.trailSegment", "emitter.trailWidth"})
	}
	if em.gpu {
		// (GPU mode: no collision.)
		colOpen := imgui.BeginTabItem("Collision")
		Drive_Item("particles.tab:collision")
		if colOpen {
			imgui.Dummy({0, 6})
			UI_DimText("   GPU mode: particles don't collide (turn GPU off in Emission to use collision).")
			imgui.EndTabItem()
		}
	} else {
		section(state, node, "Collision", "particles.tab:collision", {"emitter.collisionEnabled", "emitter.collisionMode", "emitter.collisionLayers", "emitter.elasticity", "emitter.friction"})
	}
}

@(private = "file")
to_vec4 :: proc(c: rl.Color) -> imgui.Vec4 {
	return {f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, f32(c.a) / 255}
}

@(private = "file")
to_color :: proc(v: imgui.Vec4) -> rl.Color {
	return {u8(clamp(v.x, 0, 1) * 255 + 0.5), u8(clamp(v.y, 0, 1) * 255 + 0.5), u8(clamp(v.z, 0, 1) * 255 + 0.5), u8(clamp(v.w, 0, 1) * 255 + 0.5)}
}

@(private = "file")
checker :: proc(dl: ^imgui.DrawList, mn, mx: [2]f32) {
	s := f32(8)
	imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32({0.35, 0.35, 0.38, 1}))
	for y := mn.y; y < mx.y; y += s {
		for x := mn.x; x < mx.x; x += s {
			if (int((x - mn.x) / s) + int((y - mn.y) / s)) % 2 == 0 {
				imgui.DrawList_AddRectFilled(dl, {x, y}, {min(x + s, mx.x), min(y + s, mx.y)}, col_u32({0.55, 0.55, 0.58, 1}))
			}
		}
	}
}

@(private = "file")
particle_color :: proc(state: ^EditorState, pen: ^e.ParticleEmitterNode) {
	em := &pen.emitter
	ramp := &em.colorRamp
	if UI_BeginProps("##pcolorprops") {
		UI_PropLabel("Color Over Lifetime")
		use := em.useColorRamp
		if imgui.Checkbox("Gradient##useramp", &use) {
			Editor_RecordUndo(state, "Toggle gradient")
			em.useColorRamp = use
		}
		Drive_Item("particles.use-gradient")
		if !em.useColorRamp {
			for name in ([]string{"emitter.particleColor", "emitter.colorEnd"}) {
				p, _ := e.Node_FindProperty(pen, name)
				UI_PropLabel(pretty_name(name))
				property_widget(state, pen, p, false)
			}
		}
		p, ok := e.Node_FindProperty(pen, "emitter.colorVariance")
		if ok {
			UI_PropLabel("Color Variance")
			property_widget(state, pen, p, false)
		}
		UI_EndProps()
	}
	if !em.useColorRamp do return

	io := imgui.GetIO()
	mouse := [2]f32{io.MousePos.x, io.MousePos.y}
	dl := imgui.GetWindowDrawList()
	w := imgui.GetContentRegionAvail().x - 16
	pos := imgui.GetCursorScreenPos() + {8, 4}

	// --- gradient bar ---
	barH := f32(28)
	mn := pos
	mx := pos + {w, barH}
	checker(dl, mn, mx)
	steps := 64
	for i in 0 ..< steps {
		t0 := f32(i) / f32(steps)
		t1 := f32(i + 1) / f32(steps)
		c0 := col_u32(to_vec4(e.ColorRamp_Evaluate(ramp, t0)))
		c1 := col_u32(to_vec4(e.ColorRamp_Evaluate(ramp, t1)))
		imgui.DrawList_AddRectFilledMultiColor(dl, {mn.x + w * t0, mn.y}, {mn.x + w * t1, mx.y}, c0, c1, c1, c0)
	}
	imgui.DrawList_AddRect(dl, mn, mx, col_u32(ui_line(0.25)), 3)
	imgui.SetCursorScreenPos(mn)
	imgui.InvisibleButton("##gradbar", {w, barH})
	Drive_Item("particles.gradient")
	UI_Tooltip("Double-click to add a color stop")
	if imgui.IsItemHovered() && imgui.IsMouseDoubleClicked(.Left) && ramp.count < e.MAX_COLOR_STOPS {
		t := clamp((mouse.x - mn.x) / w, 0, 1)
		Editor_RecordUndo(state, "Add color stop")
		pp.selectedStop = e.ColorRamp_AddStop(ramp, t, e.ColorRamp_Evaluate(ramp, t))
	}

	// --- stop markers ---
	my := mx.y + 2
	hovered := -1
	for i in 0 ..< ramp.count {
		st := ramp.stops[i]
		x := mn.x + st.position * w
		r := f32(7)
		tri := [3][2]f32{{x, my}, {x - r, my + 12}, {x + r, my + 12}}
		box := [2][2]f32{{x - r, my + 12}, {x + r, my + 24}}
		sel := i == pp.selectedStop
		imgui.DrawList_AddTriangleFilled(dl, tri[0], tri[1], tri[2], col_u32(UI_ACCENT if sel else {0.85, 0.85, 0.9, 1}))
		checker(dl, box[0], box[1])
		imgui.DrawList_AddRectFilled(dl, box[0], box[1], col_u32(to_vec4(st.color)))
		imgui.DrawList_AddRect(dl, box[0], box[1], col_u32(UI_ACCENT if sel else ui_line(0.6)), 0, {}, 2 if sel else 1)
		if point_in_rect(mouse, {x - r, my}, {x + r, my + 24}) do hovered = i
		Drive_ItemRect(fmt.tprintf("particles.stop:%d", i), {x - r, my}, {x + r, my + 24})
	}
	imgui.SetCursorScreenPos({mn.x, my})
	imgui.InvisibleButton("##stops", {w, 26})
	if hovered >= 0 && imgui.IsMouseClicked(.Left) {
		pp.selectedStop = hovered
		pp.dragStop = hovered
		Editor_RecordUndo(state, "Move color stop")
	}
	if hovered >= 0 && imgui.IsMouseClicked(.Right) && ramp.count > 2 {
		Editor_RecordUndo(state, "Remove color stop")
		e.ColorRamp_RemoveStop(ramp, hovered)
		pp.selectedStop = clamp(pp.selectedStop, 0, ramp.count - 1)
	}
	if pp.dragStop >= 0 {
		if imgui.IsMouseDown(.Left) && pp.dragStop < ramp.count {
			ramp.stops[pp.dragStop].position = clamp((mouse.x - mn.x) / w, 0, 1)
			e.ColorRamp_Sort(ramp, &pp.dragStop)
			pp.selectedStop = pp.dragStop
		} else {
			pp.dragStop = -1
		}
	}
	pp.selectedStop = clamp(pp.selectedStop, 0, max(ramp.count - 1, 0))

	// --- selected stop ---
	imgui.SetCursorScreenPos({mn.x - 8, my + 32})
	if ramp.count > 0 && UI_BeginProps("##stopprops") {
		st := &ramp.stops[pp.selectedStop]
		UI_PropLabel(fmt.tprintf("Stop %d of %d", pp.selectedStop + 1, ramp.count))
		imgui.SetNextItemWidth(field_width())
		posPct := st.position * 100
		if imgui.SliderFloat("##stoppos", &posPct, 0, 100, "at %.0f%% of life") {
			st.position = posPct / 100
			e.ColorRamp_Sort(ramp, &pp.selectedStop)
		}
		undo_on_activate(state, "Move color stop")
		Drive_Item("particles.stop-position")
		UI_PropLabel("Color & Alpha")
		col := to_vec4(ramp.stops[pp.selectedStop].color)
		imgui.SetNextItemWidth(field_width())
		if imgui.ColorEdit4("##stopcolor", &col, {.AlphaBar, .AlphaPreviewHalf}) do ramp.stops[pp.selectedStop].color = to_color(col)
		undo_on_activate(state, "Edit color stop")
		Drive_Item("particles.stop-color")
		UI_PropLabel("")
		if UI_Button(fmt.tprintf("%s  Remove Stop", ICON_FA_TRASH), "particles.stop-remove") && ramp.count > 2 {
			Editor_RecordUndo(state, "Remove color stop")
			e.ColorRamp_RemoveStop(ramp, pp.selectedStop)
			pp.selectedStop = clamp(pp.selectedStop, 0, ramp.count - 1)
		}
		imgui.SameLine()
		if UI_Button(fmt.tprintf("%s  Reset Gradient", ICON_FA_ROTATE_LEFT), "particles.gradient-reset") {
			Editor_RecordUndo(state, "Reset gradient")
			e.ColorRamp_Init(ramp)
			pp.selectedStop = 0
		}
		UI_EndProps()
	}

	// --- color / alpha plot ---
	imgui.Dummy({0, 6})
	UI_DimText("   Red, green, blue and alpha over the particle's lifetime (drag the white points to change alpha)")
	plotPos := imgui.GetCursorScreenPos() + {8, 4}
	plotW := w
	plotH := f32(120)
	pmn := plotPos
	pmx := plotPos + {plotW, plotH}
	imgui.DrawList_AddRectFilled(dl, pmn, pmx, col_u32(UI_BG_APP), 4)
	for g in 1 ..< 4 {
		y := pmn.y + plotH * f32(g) / 4
		imgui.DrawList_AddLine(dl, {pmn.x, y}, {pmx.x, y}, col_u32(ui_line(0.06)))
	}
	for g in 1 ..< 4 {
		x := pmn.x + plotW * f32(g) / 4
		imgui.DrawList_AddLine(dl, {x, pmn.y}, {x, pmx.y}, col_u32(ui_line(0.06)))
	}
	curve :: proc(dl: ^imgui.DrawList, ramp: ^e.ColorRamp, pmn: [2]f32, w, h: f32, channel: int, col: imgui.Vec4) {
		prev: [2]f32
		n := 80
		for i in 0 ..= n {
			t := f32(i) / f32(n)
			cc := e.ColorRamp_Evaluate(ramp, t)
			v := f32([4]u8{cc.r, cc.g, cc.b, cc.a}[channel]) / 255
			p := [2]f32{pmn.x + t * w, pmn.y + (1 - v) * h}
			if i > 0 do imgui.DrawList_AddLine(dl, prev, p, col_u32(col), 2 if channel == 3 else 1.5)
			prev = p
		}
	}
	curve(dl, ramp, pmn, plotW, plotH, 0, {0.94, 0.37, 0.37, 0.8})
	curve(dl, ramp, pmn, plotW, plotH, 1, {0.30, 0.81, 0.55, 0.8})
	curve(dl, ramp, pmn, plotW, plotH, 2, {0.36, 0.55, 1.00, 0.8})
	curve(dl, ramp, pmn, plotW, plotH, 3, {1, 1, 1, 1})
	imgui.SetCursorScreenPos(pmn)
	imgui.InvisibleButton("##alphaplot", {plotW, plotH})
	Drive_Item("particles.alpha-plot")
	for i in 0 ..< ramp.count {
		st := ramp.stops[i]
		p := [2]f32{pmn.x + st.position * plotW, pmn.y + (1 - f32(st.color.a) / 255) * plotH}
		hot := point_in_rect(mouse, p - 6, p + 6)
		imgui.DrawList_AddCircleFilled(dl, p, 5 if hot || pp.dragAlpha == i else 4, col_u32({1, 1, 1, 1}))
		imgui.DrawList_AddCircle(dl, p, 6, col_u32(UI_ACCENT if i == pp.selectedStop else {0, 0, 0, 0.6}))
		Drive_ItemRect(fmt.tprintf("particles.alpha:%d", i), p - 6, p + 6)
		if hot && imgui.IsMouseClicked(.Left) {
			pp.dragAlpha = i
			pp.selectedStop = i
			Editor_RecordUndo(state, "Edit alpha")
		}
	}
	if pp.dragAlpha >= 0 {
		if imgui.IsMouseDown(.Left) && pp.dragAlpha < ramp.count {
			a := clamp(1 - (mouse.y - pmn.y) / plotH, 0, 1)
			ramp.stops[pp.dragAlpha].color.a = u8(a * 255 + 0.5)
			imgui.SetTooltip("%s", fmt.ctprintf("alpha %.0f%%", a * 100))
		} else {
			pp.dragAlpha = -1
		}
	}
	imgui.Dummy({0, 8})
	_ = math.PI
	_ = c.int(0)
}

// particle_texture: the Texture tab (#126, #401) - the texture (shape
// Texture), where its frames come from (a grid, the slicing preset, regions
// picked in the Sprite Slicer, an Aseprite tag), how they play, and the
// look (blend, align, pivot, flips).
@(private = "file")
particle_texture :: proc(state: ^EditorState, pen: ^e.ParticleEmitterNode) {
	em := &pen.emitter
	prop :: proc(state: ^EditorState, pen: ^e.ParticleEmitterNode, name: string) {
		p, ok := e.Node_FindProperty(pen, name)
		if !ok do return
		UI_PropLabel(pretty_name(name))
		property_widget(state, pen, p, false)
	}
	if !UI_BeginProps("##ptexprops") do return
	ParticleTexture_Row(state, pen, "particles.texture")
	if em.shape != .Texture && pen.texturePath != "" {
		UI_PropLabel("")
		UI_DimText("Shown when Shape is Texture (Emission tab)")
	}
	prop(state, pen, "emitter.frameSource")
	switch em.frameSource {
	case .Grid:
		for name in ([]string{"emitter.sheetColumns", "emitter.sheetRows", "emitter.frameFirst", "emitter.frameCount"}) do prop(state, pen, name)
	case .Slices:
		UI_PropLabel("")
		if pen.texture != nil && e.Asset_ImportGet(&state.game.resourceManager, pen.texture.filePath).slice.grid == {} {
			UI_DimText("No slicing preset: Sprite Slicer > Save Preset")
		} else {
			UI_DimText("The texture's slicing preset")
		}
		for name in ([]string{"emitter.frameFirst", "emitter.frameCount"}) do prop(state, pen, name)
	case .Regions:
		particle_regions(state, pen)
	case .Aseprite:
		UI_PropLabel("Tag")
		imgui.SetNextItemWidth(field_width())
		doc := pen.ase.doc if pen.ase != nil else nil
		if doc == nil {
			UI_DimText("Pick an .aseprite texture")
		} else if imgui.BeginCombo("##particles.tag", fmt.ctprintf("%s", pen.frameTag if pen.frameTag != "" else "(every frame)")) {
			pick :: proc(state: ^EditorState, pen: ^e.ParticleEmitterNode, tag: string, label: string) {
				if imgui.Selectable(fmt.ctprintf("%s", label), pen.frameTag == tag) {
					Editor_RecordUndo(state, "Set particle tag")
					pen.frameTag = strings.clone(tag, pen.allocator)
				}
				Drive_Item(fmt.tprintf("pick:%s", label))
			}
			pick(state, pen, "", "(every frame)")
			for t in doc.tags do pick(state, pen, t.name, t.name)
			imgui.EndCombo()
		}
		Drive_Item("particles.tag")
		UI_Tooltip("The Aseprite tag whose frames play, in its direction (forward, reverse, ping-pong); up to 64 frames")
		prop(state, pen, "emitter.frameFileTiming")
	}
	if pen.texturePath != "" && !e.Ase_IsPath(pen.texturePath) {
		UI_PropLabel("")
		if UI_Button(fmt.tprintf("%s  Pick Frames in Sprite Slicer", ICON_FA_TABLE_CELLS), "particles.slicer") do Slicer_Open(state, pen.texturePath)
		UI_Tooltip("Open the Sprite Sheet Slicer on this texture: pick cells (or none for all of them) and press Use for Particles")
	}
	for name in ([]string{"emitter.frameMode", "emitter.frameSpeed", "emitter.frameLoop", "emitter.frameRandomStart", "emitter.blendMode", "emitter.alignToVelocity", "emitter.texturePivot", "emitter.randomFlipX", "emitter.randomFlipY"}) do prop(state, pen, name)
	UI_EndProps()

	// The texture (an Aseprite file: its sheet) with its frames outlined.
	e.ParticleEmitterNode_ResolveFrames(pen)
	if tex := em.texture; tex != nil && tex.id != 0 {
		fr := &em.frames
		w := min(imgui.GetContentRegionAvail().x, 240)
		h := w * f32(tex.height) / max(f32(tex.width), 1)
		p0 := imgui.GetCursorScreenPos()
		imgui.Image(transmute(imgui.TextureID)tex, {w, h})
		Drive_Item("particles.texture-preview")
		dl := imgui.GetWindowDrawList()
		sx, sy := w / max(f32(tex.width), 1), h / max(f32(tex.height), 1)
		for i in 0 ..< min(fr.count, 512) {
			r := e.Particle_FrameRect(fr, i) if fr.count > 1 || fr.list else rl.Rectangle{fr.origin.x, fr.origin.y, fr.cell.x, fr.cell.y}
			imgui.DrawList_AddRect(dl, {p0.x + r.x * sx, p0.y + r.y * sy}, {p0.x + (r.x + r.width) * sx, p0.y + (r.y + r.height) * sy}, col_u32(UI_ACCENT))
		}
		UI_DimText(fmt.tprintf("%d frame%s", max(fr.count, 1), "" if fr.count <= 1 else "s"))
	}
}

// particle_regions: Frame Source Regions - the texture's rectangles (x, y,
// w, h px), each a frame; picked in the Sprite Slicer or typed.
@(private = "file")
particle_regions :: proc(state: ^EditorState, pen: ^e.ParticleEmitterNode) {
	rg := &pen.emitter.regions
	@(static) dragging: int = -1
	remove := -1
	for i in 0 ..< rg.count {
		UI_PropLabel(fmt.tprintf("Region %d", i + 1))
		r := rg.rects[i]
		v := [4]f32{r.x, r.y, r.width, r.height}
		imgui.SetNextItemWidth(field_width() - 28)
		if imgui.DragFloat4(fmt.ctprintf("##particles.region%d", i), &v, 0.5, 0, 16384, "%.0f") {
			if dragging != i do Editor_RecordUndo(state, "Edit particle region")
			dragging = i
			rg.rects[i] = {v[0], v[1], max(v[2], 1), max(v[3], 1)}
		}
		Drive_Item(fmt.tprintf("particles.region%d", i))
		imgui.SameLine(0, 2)
		if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("particles.region%d.remove", i), "Remove this region", size = 22) do remove = i
	}
	if !imgui.IsMouseDown(.Left) do dragging = -1
	if remove >= 0 {
		Editor_RecordUndo(state, "Remove particle region")
		for k in remove ..< rg.count - 1 do rg.rects[k] = rg.rects[k + 1]
		rg.count -= 1
	}
	UI_PropLabel("")
	if rg.count == 0 do UI_DimText("No regions: the whole texture")
	if rg.count < e.MAX_PARTICLE_FRAMES && UI_Button(fmt.tprintf("%s  Add Region", ICON_FA_PLUS), "particles.region-add") {
		Editor_RecordUndo(state, "Add particle region")
		last := rg.rects[rg.count - 1] if rg.count > 0 else rl.Rectangle{0, 0, 16, 16}
		rg.rects[rg.count] = last
		rg.count += 1
	}
}

// ParticleEmitter_UseCells: the Sprite Slicer's result for an emitter
// (#401) - its texture, and the picked cells' rectangles as its regions
// (none picked: every cell, by the texture's slicing preset).
ParticleEmitter_UseCells :: proc(state: ^EditorState, pen: ^e.ParticleEmitterNode, texRel: string, cells: []rl.Rectangle) {
	Editor_RecordUndo(state, "Use sheet cells for particles")
	if pen.texturePath != texRel {
		pen.gameContext = &state.game.gameContext
		e.ParticleEmitterNode_SetTexture(pen, texRel)
	}
	pen.emitter.shape = .Texture
	em := &pen.emitter
	if len(cells) == 0 {
		em.frameSource, em.frameFirst, em.frameCount = .Slices, 0, 0
		return
	}
	em.frameSource = .Regions
	em.regions.count = min(len(cells), e.MAX_PARTICLE_FRAMES)
	for i in 0 ..< em.regions.count do em.regions.rects[i] = cells[i]
}

// ParticleTexture_Row: a props-table row picking a particle emitter's
// texture (the Particles panel's Texture tab and the Inspector). Picking
// one switches the shape to Texture.
ParticleTexture_Row :: proc(state: ^EditorState, pen: ^e.ParticleEmitterNode, id: string) {
	UI_PropLabel("Texture")
	imgui.SetNextItemWidth(field_width())
	files := make([dynamic]string, context.temp_allocator)
	append(&files, ..Editor_ListProjectFiles(state, "textures", TEXTURE_EXTS))
	append(&files, ..Editor_ListProjectFiles(state, "", {".aseprite", ".ase"})) // (#401: a tag's frames)
	if path, ok := asset_picker(id, pen.texturePath, files[:]); ok {
		Editor_RecordUndo(state, "Set particle texture")
		pen.gameContext = &state.game.gameContext
		e.ParticleEmitterNode_SetTexture(pen, path)
		if pen.emitter.shape != .Texture do pen.emitter.shape = .Texture // (what a texture is for)
		if e.Ase_IsPath(path) do pen.emitter.frameSource = .Aseprite
		else if pen.emitter.frameSource == .Aseprite do pen.emitter.frameSource = .Grid
	}
	if field_reset(id, pen.texturePath != "") {
		Editor_RecordUndo(state, "Clear particle texture")
		e.ParticleEmitterNode_SetTexture(pen, "")
	}
}

// particle_curves: the Curves tab (#127) - size, alpha and speed over a
// particle's life, each off (the linear settings) or a curve.
@(private = "file")
particle_curves :: proc(state: ^EditorState, pen: ^e.ParticleEmitterNode) {
	if !UI_BeginProps("##pcurveprops") do return
	defer UI_EndProps()
	Curve_Row :: struct {
		label, id, tip: string,
		curve:          ^e.ParticleCurve,
	}
	rows := []Curve_Row{
		{"Size over life", "particles.curve.size", "Scale over the particle's life (replaces Scale Start -> End): 1 = its size", &pen.emitter.sizeCurve},
		{"Alpha over life", "particles.curve.alpha", "Opacity over its life, multiplying its colour's: 1 = as is, 0 = gone", &pen.emitter.alphaCurve},
		{"Speed over life", "particles.curve.speed", "Movement over its life: 1 = as is, 0 = stopped, 2 = twice as fast", &pen.emitter.speedCurve},
	}
	for r in rows {
		UI_PropLabel(r.label)
		if pen.emitter.gpu && r.curve == &pen.emitter.speedCurve {
			UI_DimText("not in GPU mode")
			continue
		}
		on := r.curve.count > 0
		if imgui.Checkbox(fmt.ctprintf("##%s.on", r.id), &on) {
			Editor_RecordUndo(state, fmt.tprintf("%s %s", "Use" if on else "Clear", r.label))
			if on {
				r.curve^ = {count = 2}
				r.curve.points[0], r.curve.points[1] = {0, 1}, {1, 1}
			} else {
				r.curve.count = 0
			}
		}
		Drive_Item(fmt.tprintf("%s.on", r.id))
		UI_Tooltip(r.tip)
		if r.curve.count == 0 do continue
		UI_PropLabel("")
		sb := strings.builder_make(context.temp_allocator)
		strings.write_byte(&sb, '[')
		for i in 0 ..< r.curve.count {
			if i > 0 do strings.write_string(&sb, ", ")
			fmt.sbprintf(&sb, "[%g, %g]", r.curve.points[i].x, r.curve.points[i].y)
		}
		strings.write_byte(&sb, ']')
		@(static) dragging: string
		if text, changed := script_curve_field(r.id, strings.to_string(sb)); changed {
			if dragging != r.id do Editor_RecordUndo(state, fmt.tprintf("Edit %s", r.label)) // (one step per drag)
			dragging = r.id
			if v, err := json.parse_string(text, allocator = context.temp_allocator); err == .None {
				if arr, ok := v.(json.Array); ok do e.ParticleCurve_FromJSON(r.curve, arr)
			}
		}
		if !imgui.IsMouseDown(.Left) && dragging == r.id do dragging = ""
	}
}
