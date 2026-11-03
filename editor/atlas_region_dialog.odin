package editor

import "core:c"
import "core:encoding/uuid"
import "core:fmt"
import "core:math"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"
import rl "vendor:raylib"

// ============================================================================
// Atlas Region Editor Dialog
// Visual popup dialog allowing selection and adjustment of the sub-region
// (x, y, width, height) of an AtlasSpriteNode's texture.
// ============================================================================

@(private = "file")
atlasDialog: struct {
	open:         bool,
	// The node edited, held with its id: it may be deleted (or rebuilt by an
	// undo) while the window is open - atlas_node() checks before each use
	// (#375).
	node:         ^e.AtlasSpriteNode,
	nodeId:       uuid.Identifier,
	origRegion:   rl.Rectangle,
	region:       rl.Rectangle,
	// Grid snapping
	enableGrid:   bool,
	gridCols:     c.int,
	gridRows:     c.int,
	cellSize:     [2]c.int,
	// View & Zoom
	zoom:         f32,
	// Interactive dragging state
	dragging:     bool,
	dragStart:    [2]f32,
	openWinPos:   [2]f32,
	winPos:       [2]f32,
}

AtlasRegion_DriveQuery :: proc(q: string) -> (string, bool) {
	switch q {
	case "atlas.open":
		return "true" if atlasDialog.open else "false", true
	case "atlas.region":
		return fmt.tprintf("%.0f,%.0f,%.0f,%.0f", atlasDialog.region.x, atlasDialog.region.y, atlasDialog.region.width, atlasDialog.region.height), true
	case "atlas.win-pos":
		return fmt.tprintf("%.0f,%.0f", atlasDialog.winPos.x, atlasDialog.winPos.y), true
	case "atlas.win-moved":
		return "true" if atlasDialog.openWinPos != {} && atlasDialog.winPos != atlasDialog.openWinPos else "false", true
	}
	return "", false
}

AtlasRegion_Open :: proc(state: ^EditorState, node: ^e.AtlasSpriteNode) {
	if node == nil || state == nil do return
	atlasDialog.open = true
	atlasDialog.node = node
	atlasDialog.nodeId = node.id
	atlasDialog.origRegion = node.region
	atlasDialog.region = node.region
	atlasDialog.dragging = false
	atlasDialog.openWinPos = {}
	atlasDialog.winPos = {}
	atlasDialog.zoom = 0 // 0 = fit
	if atlasDialog.gridCols <= 0 do atlasDialog.gridCols = 4
	if atlasDialog.gridRows <= 0 do atlasDialog.gridRows = 4
	if node.texture != nil {
		tw := f32(node.texture.texture.width)
		th := f32(node.texture.texture.height)
		if atlasDialog.region.width <= 0 || atlasDialog.region.height <= 0 {
			atlasDialog.region = {0, 0, tw, th}
		}
		if atlasDialog.cellSize[0] <= 0 do atlasDialog.cellSize[0] = c.int(tw / max(f32(atlasDialog.gridCols), 1))
		if atlasDialog.cellSize[1] <= 0 do atlasDialog.cellSize[1] = c.int(th / max(f32(atlasDialog.gridRows), 1))
	}
}

// atlas_node: the node being edited, or nil once it's gone (deleted, or
// rebuilt by an undo).
@(private = "file")
atlas_node :: proc() -> ^e.AtlasSpriteNode {
	n := atlasDialog.node
	if n == nil || !e.Node_IsAlive(&n.node) || n.id != atlasDialog.nodeId || n.typeId != e.AtlasSpriteNode do return nil
	return n
}

// Atlas_ClampRegion: a region inside a w x h texture, at least 1 x 1 (a
// region starting on the right / bottom edge moves in by a pixel).
Atlas_ClampRegion :: proc(r: rl.Rectangle, w, h: f32) -> rl.Rectangle {
	out := r
	out.x = clamp(r.x, 0, max(w - 1, 0))
	out.y = clamp(r.y, 0, max(h - 1, 0))
	out.width = clamp(r.width, 1, max(w - out.x, 1))
	out.height = clamp(r.height, 1, max(h - out.y, 1))
	return out
}

// Atlas_SnapStep: the grid's step on one axis - the cell size when set
// (what Snap to Grid snaps to), else the texture split into `count` cells.
Atlas_SnapStep :: proc(size: f32, count, cell: c.int) -> f32 {
	if cell > 0 do return f32(cell)
	return size / f32(max(count, 1))
}

AtlasRegion_IsOpen :: proc() -> bool {
	return atlasDialog.open
}

AtlasRegion_Close :: proc() {
	atlasDialog.open = false
	atlasDialog.node = nil
}

@(private = "file")
ATLAS_ZOOM_MIN :: f32(0.05)
@(private = "file")
ATLAS_ZOOM_MAX :: f32(32)

@(private = "file")
atlas_fit_scale :: proc(texW, texH: f32, avail: [2]f32) -> f32 {
	if texW <= 0 || texH <= 0 do return 1
	s := min((avail.x - 16) / texW, (avail.y - 16) / texH)
	return clamp(s, ATLAS_ZOOM_MIN, 8)
}

AtlasRegion_Render :: proc(state: ^EditorState) {
	if !atlasDialog.open || atlasDialog.node == nil do return
	node := atlas_node()

	imgui.SetNextWindowSize({820, 560}, .FirstUseEver)
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .FirstUseEver, {0.5, 0.5})
	defer imgui.End()
	if !imgui.Begin(fmt.ctprintf("%s  Atlas Region Editor###AtlasRegionEditor", ICON_FA_CROP), &atlasDialog.open, {.NoCollapse}) {
		return
	}
	PanelHelp_Mark("atlas-region")
	atlasDialog.winPos = imgui.GetWindowPos()
	if atlasDialog.openWinPos == {} do atlasDialog.openWinPos = atlasDialog.winPos

	// --- Left Settings Column ---
	if imgui.BeginChild("##atlas_side", {270, 0}, {}, {}) {
		if node == nil {
			// (Deleted while the window was open: nothing to apply to.)
			imgui.TextColored(UI_WARNING, "The Atlas Sprite was deleted.")
			UI_DimTextWrapped("Close this window and open the editor again from an Atlas Sprite's Inspector.")
			Drive_Item("atlas.gone")
			if UI_PrimaryButton(fmt.tprintf("%s  Apply", ICON_FA_CHECK), "atlas.apply", {120, 0}) {
				Editor_Log(state, .Warn, "Atlas Region Editor: the Atlas Sprite is gone - nothing applied")
				atlasDialog.open = false
			}
			imgui.SameLine()
			if UI_Button("Cancel", "atlas.cancel", {120, 0}) do atlasDialog.open = false
		} else if node.texture == nil {
			UI_DimText("No texture assigned to this node.")
		} else {
			tw := f32(node.texture.texture.width)
			th := f32(node.texture.texture.height)

			UI_DimText(fmt.tprintf("Texture: %d × %d px", int(tw), int(th)))
			if node.filePath != "" {
				UI_DimText(fmt.tprintf("File: %s", node.filePath))
			}

			imgui.Separator()
			if UI_BeginProps("##atlas_props") {
				UI_PropLabel("X")
				imgui.DragFloat("##at_x", &atlasDialog.region.x, 1, 0, tw, "%.0f")
				Drive_Item("atlas.x")

				UI_PropLabel("Y")
				imgui.DragFloat("##at_y", &atlasDialog.region.y, 1, 0, th, "%.0f")
				Drive_Item("atlas.y")

				UI_PropLabel("Width")
				imgui.DragFloat("##at_w", &atlasDialog.region.width, 1, 1, tw, "%.0f")
				Drive_Item("atlas.w")

				UI_PropLabel("Height")
				imgui.DragFloat("##at_h", &atlasDialog.region.height, 1, 1, th, "%.0f")
				Drive_Item("atlas.h")
				UI_EndProps()
			}

			// Clamp region (at least 1 x 1, inside the texture: #375)
			atlasDialog.region = Atlas_ClampRegion(atlasDialog.region, tw, th)

			if UI_Button("Full Texture", "atlas.full") {
				atlasDialog.region = {0, 0, tw, th}
			}
			imgui.SameLine()
			if UI_Button("Reset", "atlas.reset") {
				atlasDialog.region = atlasDialog.origRegion
			}

			imgui.Separator()
			imgui.Checkbox("Snap to Grid##at", &atlasDialog.enableGrid)
			Drive_Item("atlas.grid_snap")
			if atlasDialog.enableGrid {
				if UI_BeginProps("##atlas_grid_props") {
					UI_PropLabel("Columns")
					if imgui.DragInt("##at_cols", &atlasDialog.gridCols, 0.1, 1, 256) {
						if atlasDialog.gridCols > 0 do atlasDialog.cellSize[0] = c.int(tw / f32(atlasDialog.gridCols))
					}
					Drive_Item("atlas.cols")

					UI_PropLabel("Rows")
					if imgui.DragInt("##at_rows", &atlasDialog.gridRows, 0.1, 1, 256) {
						if atlasDialog.gridRows > 0 do atlasDialog.cellSize[1] = c.int(th / f32(atlasDialog.gridRows))
					}
					Drive_Item("atlas.rows")

					UI_PropLabel("Cell Size")
					if imgui.DragInt2("##at_cellsize", &atlasDialog.cellSize, 0.2, 1, 4096) {
						if atlasDialog.cellSize[0] > 0 do atlasDialog.gridCols = max(1, c.int(tw / f32(atlasDialog.cellSize[0])))
						if atlasDialog.cellSize[1] > 0 do atlasDialog.gridRows = max(1, c.int(th / f32(atlasDialog.cellSize[1])))
					}
					Drive_Item("atlas.cell_size")
					UI_EndProps()
				}
			}

			imgui.Separator()
			UI_DimText(fmt.tprintf("Selected Region: %.0f × %.0f px", atlasDialog.region.width, atlasDialog.region.height))

			// Cropped preview box
			previewBoxW: f32 = 250
			previewBoxH: f32 = 120
			if atlasDialog.region.width > 0 && atlasDialog.region.height > 0 && tw > 0 && th > 0 {
				scaleW := previewBoxW / atlasDialog.region.width
				scaleH := previewBoxH / atlasDialog.region.height
				s := min(scaleW, scaleH)
				s = min(s, 2.0)
				pw := atlasDialog.region.width * s
				ph := atlasDialog.region.height * s
				cur := imgui.GetCursorScreenPos()
				dl := imgui.GetWindowDrawList()
				imgui.DrawList_AddRectFilled(dl, cur, cur + {previewBoxW, previewBoxH}, col32(24, 28, 36, 255))
				imgui.DrawList_AddRect(dl, cur, cur + {previewBoxW, previewBoxH}, col32(50, 56, 70, 255))
				off := [2]f32{(previewBoxW - pw) * 0.5, (previewBoxH - ph) * 0.5}
				uv0 := [2]f32{atlasDialog.region.x / tw, atlasDialog.region.y / th}
				uv1 := [2]f32{(atlasDialog.region.x + atlasDialog.region.width) / tw, (atlasDialog.region.y + atlasDialog.region.height) / th}
				imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)&node.texture.texture, cur + off, cur + off + {pw, ph}, uv0, uv1)
				imgui.Dummy({previewBoxW, previewBoxH})
			}

			imgui.Separator()
			if UI_PrimaryButton(fmt.tprintf("%s  Apply", ICON_FA_CHECK), "atlas.apply", {120, 0}) {
				Editor_RecordUndo(state, "Edit Atlas Region")
				e.AtlasSpriteNode_SetRegion(node, atlasDialog.region)
				atlasDialog.open = false
			}
			imgui.SameLine()
			if UI_Button("Cancel", "atlas.cancel", {120, 0}) {
				atlasDialog.open = false
			}
		}
	}
	imgui.EndChild()
	imgui.SameLine()

	// --- Right Interactive Canvas Column ---
	if imgui.BeginChild("##atlas_sheet", {0, 0}, {.Borders}, {.HorizontalScrollbar, .NoMove}) {
		if node == nil || node.texture == nil {
			UI_DimText("No texture to display.")
		} else {
			atlas_canvas(state, node)
		}
	}
	imgui.EndChild()
}

@(private = "file")
atlas_canvas :: proc(state: ^EditorState, node: ^e.AtlasSpriteNode) {
	if node.texture == nil do return
	tw := f32(node.texture.texture.width)
	th := f32(node.texture.texture.height)
	if tw <= 0 || th <= 0 do return

	io := imgui.GetIO()

	// --- Zoom Bar ---
	avail := imgui.GetContentRegionAvail()
	fitScale := atlas_fit_scale(tw, th, avail - {0, 36})
	scale := atlasDialog.zoom if atlasDialog.zoom > 0 else fitScale
	zoomTo := f32(-1)

	if UI_IconButton(ICON_FA_MINUS, "atlas.zoom-out", "Zoom out", size = 24) do zoomTo = scale / 1.25
	imgui.SameLine(0, 2)
	imgui.SetNextItemWidth(64)
	pct := scale * 100
	if imgui.DragFloat("##atlas_zoom", &pct, 1, ATLAS_ZOOM_MIN * 100, ATLAS_ZOOM_MAX * 100, "%.0f%%") do zoomTo = pct / 100
	Drive_Item("atlas.zoom")
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_PLUS, "atlas.zoom-in", "Zoom in", size = 24) do zoomTo = scale * 1.25
	imgui.SameLine(0, UI_SPACE)
	if UI_Button("Fit", "atlas.zoom-fit") do atlasDialog.zoom = 0
	imgui.SameLine(0, 2)
	if UI_Button("1:1", "atlas.zoom-1") do zoomTo = 1
	imgui.SameLine(0, UI_SPACE)
	imgui.AlignTextToFramePadding()
	UI_DimText("Cmd+wheel zooms · drag across to select region")

	// --- Canvas Viewport ---
	canvasOpen := imgui.BeginChild("##atlas_canvas", {0, 0}, {}, {.HorizontalScrollbar, .NoScrollWithMouse, .NoMove})
	defer imgui.EndChild()
	if !canvasOpen do return

	canvasMn := imgui.GetWindowPos()
	mouse := [2]f32{io.MousePos.x, io.MousePos.y}
	canvasHovered := imgui.IsWindowHovered({})
	if canvasHovered {
		if io.MouseWheel != 0 && (io.KeySuper || io.KeyCtrl) {
			zoomTo = scale * (1.15 if io.MouseWheel > 0 else 1 / 1.15)
		} else if io.MouseWheel != 0 || io.MouseWheelH != 0 {
			dx, dy := io.MouseWheelH, io.MouseWheel
			if io.KeyShift && dx == 0 do dx, dy = dy, 0
			imgui.SetScrollX(imgui.GetScrollX() - dx * 40)
			imgui.SetScrollY(imgui.GetScrollY() - dy * 40)
		}
	}
	if canvasHovered && imgui.IsMouseDragging(.Middle) {
		d := io.MouseDelta
		imgui.SetScrollX(imgui.GetScrollX() - d.x)
		imgui.SetScrollY(imgui.GetScrollY() - d.y)
	}
	if zoomTo > 0 {
		zoomTo = clamp(zoomTo, ATLAS_ZOOM_MIN, ATLAS_ZOOM_MAX)
		anchor := mouse - canvasMn if canvasHovered else imgui.GetWindowSize() * 0.5
		content := ([2]f32{imgui.GetScrollX(), imgui.GetScrollY()} + anchor) / scale
		atlasDialog.zoom = zoomTo
		scale = zoomTo
		imgui.SetScrollX(max(content.x * scale - anchor.x, 0))
		imgui.SetScrollY(max(content.y * scale - anchor.y, 0))
	}
	if atlasDialog.zoom == 0 do scale = fitScale

	imgSize := [2]f32{tw, th} * scale
	p0 := imgui.GetCursorScreenPos()
	dl := imgui.GetWindowDrawList()

	// Background and Image
	imgui.DrawList_AddRectFilled(dl, p0, p0 + imgSize, col32(30, 34, 44, 255))
	imgui.InvisibleButton("##atlas_canvas_hit", {max(imgSize.x, 1), max(imgSize.y, 1)}, {.MouseButtonLeft, .MouseButtonMiddle})
	hovered := imgui.IsItemHovered()
	active := imgui.IsItemActive()
	imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)&node.texture.texture, p0, p0 + imgSize, {0, 0}, {1, 1}, col32(255, 255, 255, 255))
	Drive_ItemRect("atlas.canvas", p0, p0 + imgSize, inWindow = true)

	// Grid lines if enabled
	// (Every cell-size step: what Snap to Grid snaps to - #375.)
	stepX := Atlas_SnapStep(tw, atlasDialog.gridCols, atlasDialog.cellSize[0])
	stepY := Atlas_SnapStep(th, atlasDialog.gridRows, atlasDialog.cellSize[1])
	if atlasDialog.enableGrid {
		for x := f32(0); x <= tw + 0.01; x += stepX {
			sx := p0.x + x * scale
			imgui.DrawList_AddLine(dl, {sx, p0.y}, {sx, p0.y + imgSize.y}, col32(255, 255, 255, 45), 1)
		}
		for y := f32(0); y <= th + 0.01; y += stepY {
			sy := p0.y + y * scale
			imgui.DrawList_AddLine(dl, {p0.x, sy}, {p0.x + imgSize.x, sy}, col32(255, 255, 255, 45), 1)
		}
	}

	// Interactive Selection
	texelMouse := (mouse - p0) / scale
	snapCoord :: proc(v: f32, step: f32) -> f32 {
		if step <= 0 do return v
		return math.round(v / step) * step
	}

	if (hovered || active) && imgui.IsMouseClicked(.Left) {
		atlasDialog.dragging = true
		pt := texelMouse
		if atlasDialog.enableGrid {
			pt.x = snapCoord(pt.x, stepX)
			pt.y = snapCoord(pt.y, stepY)
		}
		atlasDialog.dragStart = pt
	}

	if atlasDialog.dragging {
		if imgui.IsMouseDown(.Left) {
			pt := texelMouse
			if atlasDialog.enableGrid {
				pt.x = snapCoord(pt.x, stepX)
				pt.y = snapCoord(pt.y, stepY)
			}
			x0 := clamp(min(atlasDialog.dragStart.x, pt.x), 0, tw)
			y0 := clamp(min(atlasDialog.dragStart.y, pt.y), 0, th)
			x1 := clamp(max(atlasDialog.dragStart.x, pt.x), 0, tw)
			y1 := clamp(max(atlasDialog.dragStart.y, pt.y), 0, th)
			atlasDialog.region = Atlas_ClampRegion({x0, y0, x1 - x0, y1 - y0}, tw, th)
		} else {
			atlasDialog.dragging = false
		}
	}

	// Draw Region Highlight
	rMn := p0 + [2]f32{atlasDialog.region.x, atlasDialog.region.y} * scale
	rMx := rMn + [2]f32{atlasDialog.region.width, atlasDialog.region.height} * scale
	imgui.DrawList_AddRectFilled(dl, rMn, rMx, col32(0, 206, 201, 75))
	imgui.DrawList_AddRect(dl, rMn, rMx, col32(0, 206, 201, 230), 0, {}, 2)
	Drive_ItemRect("atlas.region_rect", rMn, rMx, inWindow = true)

	// Label above region
	label := fmt.ctprintf("%.0f, %.0f (%0.f × %.0f)", atlasDialog.region.x, atlasDialog.region.y, atlasDialog.region.width, atlasDialog.region.height)
	imgui.DrawList_AddText(dl, rMn + {4, 3}, col32(255, 255, 255, 240), label)
}
