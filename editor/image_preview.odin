package editor

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
// Image previews (#399): double-click a texture, an Aseprite file or an SVG
// in Assets and it opens in a tab of its own beside the scene tabs; the
// Viewport shows it instead of the scene while its tab is selected. Wheel
// zooms at the cursor, dragging pans, Fit / 1:1; a checkerboard behind
// transparency, a pixel grid zoomed in (the texture's import filter
// applied); the frames it is sliced into (a sheet's slicing preset, an
// Aseprite file's frames); an info bar with the size, the file, its import
// settings and the pixel under the cursor. Tabs stay until closed (x,
// middle-click, Cmd+W); a changed file reloads.
// ============================================================================

Image_Preview :: struct {
	rel:      string, // project-relative
	full:     string,
	kind:     Asset_Kind, // .Texture, .Aseprite or .Vector
	tex:      rl.Texture2D,
	img:      rl.Image, // the pixels shown (the colour under the cursor)
	err:      string,   // why it couldn't be read ("" = shown)
	bytes:    i64,
	modTime:  time.Time,
	frames:   [dynamic]rl.Rectangle, // in image px
	framesOf: string, // what the frames are ("12 frames (4 x 3 slice)")
	docSize:  [2]f32, // an SVG's document size (the image is rendered at docScale)
	docScale: f32,
	zoom:     f32,
	offset:   [2]f32, // the image's top-left in the canvas (px)
	canvas:   [2]f32, // the canvas size (last frame)
	fitted:   bool,
	grid:     bool, // the pixel grid (zoomed in)
	showFrames: bool,
	hover:    [2]i32, // the pixel under the cursor (-1: none)
}

@(private = "file")
img: struct {
	open:    [dynamic]^Image_Preview,
	active:  ^Image_Preview, // its tab is the one selected (nil: a scene's)
	select:  ^Image_Preview, // select its tab (opened / switched to from Assets)
	closing: [dynamic]^Image_Preview,
	project: string, // the project they belong to
	checker: rl.Texture2D,
	checkFrame: i32,
}

IMG_PREVIEW_GRID_ZOOM :: 8 // the pixel grid from this zoom on
IMG_PREVIEW_MAX_ZOOM :: 64

// ImagePreview_IsKind: assets that open in an image preview.
ImagePreview_IsKind :: proc(k: Asset_Kind) -> bool {return k == .Texture || k == .Aseprite || k == .Vector}

// ImagePreview_Active: the preview whose tab is selected (nil: a scene).
ImagePreview_Active :: proc() -> ^Image_Preview {return img.active}

// ImagePreview_Open opens an image asset in a tab (or switches to its tab).
ImagePreview_Open :: proc(state: ^EditorState, rel: string) {
	image_preview_project(state)
	for p in img.open do if p.rel == rel {
		img.select = p
		return
	}
	p := new(Image_Preview)
	p.rel = strings.clone(rel)
	full, _ := filepath.join({state.projectPath, rel}, context.allocator)
	p.full = full
	p.kind = Asset_KindOf(rel)
	p.grid, p.showFrames = true, true
	p.hover = {-1, -1}
	image_preview_load(state, p)
	append(&img.open, p)
	img.select = p
}

// ImagePreview_CloseActive closes the selected preview tab (Cmd+W).
ImagePreview_CloseActive :: proc() {
	if img.active != nil do append(&img.closing, img.active)
}

// ImagePreview_Count: the open preview tabs.
ImagePreview_Count :: proc() -> int {return len(img.open)}

@(private = "file")
image_preview_project :: proc(state: ^EditorState) {
	if img.project == state.projectPath do return
	for p in img.open do image_preview_free(p)
	clear(&img.open)
	clear(&img.closing)
	img.active, img.select = nil, nil
	delete(img.project)
	img.project = strings.clone(state.projectPath)
}

@(private = "file")
image_preview_unload :: proc(p: ^Image_Preview) {
	if p.tex.id != 0 do rl.UnloadTexture(p.tex)
	if p.img.data != nil do rl.UnloadImage(p.img)
	p.tex, p.img = {}, {}
	clear(&p.frames)
	delete(p.framesOf)
	delete(p.err)
	p.framesOf, p.err = "", ""
}

@(private = "file")
image_preview_free :: proc(p: ^Image_Preview) {
	image_preview_unload(p)
	delete(p.frames)
	delete(p.rel)
	delete(p.full)
	free(p)
}

// image_preview_load reads the file: its pixels, a texture with the import
// filter, the frames it is sliced into.
@(private = "file")
image_preview_load :: proc(state: ^EditorState, p: ^Image_Preview) {
	image_preview_unload(p)
	fi, serr := os.stat(p.full, context.temp_allocator)
	if serr != nil {
		p.err = strings.clone("The file is missing (moved or deleted?)")
		return
	}
	p.bytes, p.modTime = fi.size, fi.modification_time
	#partial switch p.kind {
	case .Aseprite:
		data, err := os.read_entire_file(p.full, context.temp_allocator)
		if err != nil do break
		doc, why := e.Ase_Load(data)
		if doc == nil {
			p.err = strings.clone(fmt.tprintf("Can't read the Aseprite file: %s", why))
			return
		}
		defer e.Ase_Destroy(doc)
		cols: int
		p.img, cols = e.Ase_SheetImage(doc)
		n := len(doc.frames)
		for f in 0 ..< n do append(&p.frames, rl.Rectangle{f32((f % cols) * doc.width), f32((f / cols) * doc.height), f32(doc.width), f32(doc.height)})
		p.framesOf = strings.clone(fmt.tprintf("%d frame%s of %d x %d", n, "" if n == 1 else "s", doc.width, doc.height))
	case .Vector:
		data, err := os.read_entire_file(p.full, context.temp_allocator)
		if err != nil do break
		doc: e.Vector_Doc
		defer e.Vector_Doc_Destroy(&doc)
		if !e.Vector_LoadSVG(string(data), &doc) || doc.size.x <= 0 || doc.size.y <= 0 {
			p.err = strings.clone("Can't read the SVG")
			return
		}
		// (Rendered at 2x, so zooming in stays sharp a while.)
		side := clamp(i32(max(doc.size.x, doc.size.y) * 2), 256, 4096)
		p.img = e.Vector_DocImage(&doc, side)
		p.docSize = doc.size
		p.docScale = f32(p.img.width) / doc.size.x if p.img.data != nil else 1
	case:
		p.img = rl.LoadImage(strings.clone_to_cstring(p.full, context.temp_allocator))
		if p.img.data == nil do break
		rl.ImageFormat(&p.img, .UNCOMPRESSED_R8G8B8A8)
		if imp := Editor_AssetImport(state, p.full); imp.slice.grid != {} || imp.slice.cellSize != {} {
			s := imp.slice
			size := [2]f32{f32(p.img.width), f32(p.img.height)}
			grid := s.grid
			if s.cellSize.x > 0 && s.cellSize.y > 0 do grid = e.SpriteSheet_FitGrid(size, s.margin, s.spacing, s.cellSize)
			n := max(grid.x, 0) * max(grid.y, 0)
			for c in 0 ..< n do append(&p.frames, e.SpriteSheet_CellRect(size, grid, s.margin, s.spacing, c, s.cellSize))
			if n > 0 do p.framesOf = strings.clone(fmt.tprintf("%d frame%s (%d x %d slice)", n, "" if n == 1 else "s", grid.x, grid.y))
		}
	}
	if p.img.data == nil {
		if p.err == "" do p.err = strings.clone("Can't read the image")
		return
	}
	p.tex = rl.LoadTextureFromImage(p.img)
	#partial switch p.kind {
	case .Aseprite: rl.SetTextureFilter(p.tex, .POINT) // (pixel art)
	case .Vector: rl.SetTextureFilter(p.tex, .BILINEAR)
	case: e.Texture_ApplyImport(&p.tex, e.Texture_ImportFor(&state.game.resourceManager, p.full))
	}
	rl.SetTextureWrap(p.tex, .CLAMP) // (the preview shows the image once)
}

// --- the tabs ---------------------------------------------------------------

// ImagePreview_TabItems draws the preview tabs (inside the scene tab bar,
// after the scenes). sceneShown: a scene's tab is the selected one;
// sceneSwitched: the active scene changed (opened from Assets, Cmd+Tab) -
// it is shown again.
ImagePreview_TabItems :: proc(state: ^EditorState, sceneShown, sceneSwitched: bool) {
	image_preview_project(state)
	if sceneSwitched do img.select = nil
	shown: ^Image_Preview
	for p in img.open {
		tf: imgui.TabItemFlags
		if p == img.select do tf += {.SetSelected}
		open := true
		icon, _ := kind_icon(p.kind)
		visible := imgui.BeginTabItem(fmt.ctprintf("%s  %s###imgtab_%p", icon, filepath.base(p.rel), p), &open, tf)
		Drive_Item(fmt.tprintf("imgtab:%s", p.rel))
		if imgui.IsItemHovered() {
			imgui.SetTooltip(fmt.ctprintf("%s (preview)", p.rel))
			if imgui.IsMouseClicked(.Middle) do append(&img.closing, p)
		}
		if imgui.BeginPopupContextItem(fmt.ctprintf("##imgtab_ctx_%p", p)) {
			if imgui.MenuItem("Close", CMD + "+W") do append(&img.closing, p)
			Drive_Item("ctx:imgtab-close")
			if imgui.MenuItem("Close All Previews") do for o in img.open do append(&img.closing, o)
			imgui.Separator()
			if imgui.MenuItem("Copy Path") do imgui.SetClipboardText(fmt.ctprintf("%s", p.rel))
			imgui.EndPopup()
		}
		if visible {
			shown = p
			imgui.EndTabItem()
		}
		if !open do append(&img.closing, p)
	}
	// Which tab shows: a requested one until its tab is selected, else the
	// selected tab's.
	switch {
	case sceneSwitched: img.active = nil
	case img.select != nil:
		img.active = img.select
		if shown == img.select do img.select = nil
	case shown != nil: img.active = shown
	case sceneShown: img.active = nil
	}
}

// ImagePreview_EndFrame closes the tabs asked to close this frame.
ImagePreview_EndFrame :: proc() {
	for len(img.closing) > 0 {
		p := pop(&img.closing)
		for o, i in img.open do if o == p {
			ordered_remove(&img.open, i)
			if img.active == p do img.active = nil
			if img.select == p do img.select = nil
			image_preview_free(p)
			break
		}
	}
}

// --- the preview ------------------------------------------------------------

// ImagePreview_Draw fills the Viewport with the preview: a toolbar, the
// canvas, the info bar.
ImagePreview_Draw :: proc(state: ^EditorState, p: ^Image_Preview) {
	// A changed file reloads (checked twice a second).
	if f := imgui.GetFrameCount(); f - img.checkFrame > 30 || f < img.checkFrame {
		img.checkFrame = f
		if fi, err := os.stat(p.full, context.temp_allocator); err == nil {
			if fi.modification_time != p.modTime || p.err != "" do image_preview_load(state, p)
		} else if p.err == "" {
			image_preview_load(state, p)
		}
	}
	image_preview_toolbar(p)
	// The canvas: what the toolbar leaves, less the info bar.
	avail := imgui.GetContentRegionAvail()
	canvasMin := imgui.GetCursorScreenPos()
	canvasSize := [2]f32{max(avail.x, 64), max(avail.y - imgui.GetFrameHeightWithSpacing() - 6, 64)}
	p.canvas = canvasSize
	imgui.InvisibleButton("##imgpreview_canvas", canvasSize, {.MouseButtonLeft, .MouseButtonMiddle})
	Drive_Item("imgpreview.canvas")
	hovered, active := imgui.IsItemHovered(), imgui.IsItemActive()
	dl := imgui.GetWindowDrawList()
	imgui.DrawList_AddRectFilled(dl, canvasMin, canvasMin + canvasSize, col_u32(UI_BG_APP))
	if p.err != "" || p.tex.id == 0 {
		msg := fmt.ctprintf("%s  %s", ICON_FA_TRIANGLE_EXCLAMATION, p.err if p.err != "" else "Can't read the image")
		w := imgui.CalcTextSize(msg).x
		imgui.DrawList_AddText(dl, canvasMin + canvasSize * 0.5 - {w * 0.5, 8}, col_u32(UI_TEXT_DIM), msg)
		p.hover = {-1, -1}
		image_preview_info(p)
		return
	}
	size := [2]f32{f32(p.tex.width), f32(p.tex.height)}
	if !p.fitted {
		image_preview_fit(p, canvasSize)
		p.fitted = true
	}
	io := imgui.GetIO()
	mouse := [2]f32{io.MousePos.x, io.MousePos.y}
	// Wheel: zoom at the cursor; drag: pan.
	if hovered && io.MouseWheel != 0 {
		image_preview_zoom_at(p, p.zoom * math.pow(f32(1.25), io.MouseWheel), mouse - canvasMin)
	}
	if active && (imgui.IsMouseDragging(.Left, 0) || imgui.IsMouseDragging(.Middle, 0)) {
		p.offset += [2]f32{io.MouseDelta.x, io.MouseDelta.y}
		imgui.SetMouseCursor(.ResizeAll)
	}
	p0 := canvasMin + p.offset
	p1 := p0 + size * p.zoom
	imgui.DrawList_PushClipRect(dl, canvasMin, canvasMin + canvasSize, true)
	// The checkerboard behind transparency (8 px squares on screen).
	image_preview_checker()
	CHECK :: 8
	imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)&img.checker, p0, p1, {0, 0}, (p1 - p0) / (2 * CHECK))
	imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)&p.tex, p0, p1)
	// The pixel grid, zoomed in (the visible part only).
	if p.grid && p.zoom >= IMG_PREVIEW_GRID_ZOOM {
		lo := linalg_max(p0, canvasMin)
		hi := linalg_min(p1, canvasMin + canvasSize)
		gc := col_u32({0, 0, 0, 0.35})
		x0 := int(math.floor((lo.x - p0.x) / p.zoom))
		x1 := int(math.ceil((hi.x - p0.x) / p.zoom))
		for x in x0 ..= x1 {
			sx := p0.x + f32(x) * p.zoom
			imgui.DrawList_AddLine(dl, {sx, lo.y}, {sx, hi.y}, gc)
		}
		y0 := int(math.floor((lo.y - p0.y) / p.zoom))
		y1 := int(math.ceil((hi.y - p0.y) / p.zoom))
		for y in y0 ..= y1 {
			sy := p0.y + f32(y) * p.zoom
			imgui.DrawList_AddLine(dl, {lo.x, sy}, {hi.x, sy}, gc)
		}
	}
	// The frames it is sliced into.
	if p.showFrames && len(p.frames) > 0 {
		fc := col_u32({UI_ACCENT.x, UI_ACCENT.y, UI_ACCENT.z, 0.85})
		for r, i in p.frames {
			a := p0 + [2]f32{r.x, r.y} * p.zoom
			b := a + [2]f32{r.width, r.height} * p.zoom
			imgui.DrawList_AddRect(dl, a, b, fc)
			if b.x - a.x >= 24 && b.y - a.y >= 18 do imgui.DrawList_AddText(dl, a + {3, 2}, fc, fmt.ctprintf("%d", i))
		}
	}
	imgui.DrawList_AddRect(dl, p0 - {1, 1}, p1 + {1, 1}, col_u32({1, 1, 1, 0.15}))
	imgui.DrawList_PopClipRect(dl)
	// The pixel under the cursor.
	p.hover = {-1, -1}
	if hovered {
		px := (mouse - p0) / p.zoom
		if px.x >= 0 && px.y >= 0 && px.x < size.x && px.y < size.y do p.hover = {i32(px.x), i32(px.y)}
	}
	image_preview_info(p)
}

// image_preview_px: image px per unit the zoom is shown in (an SVG is
// rendered at docScale px per document unit; 1 otherwise).
@(private = "file")
image_preview_px :: proc(p: ^Image_Preview) -> f32 {
	return p.docScale if p.kind == .Vector && p.docScale > 0 else 1
}

@(private = "file")
linalg_max :: proc(a, b: [2]f32) -> [2]f32 {return {max(a.x, b.x), max(a.y, b.y)}}

@(private = "file")
linalg_min :: proc(a, b: [2]f32) -> [2]f32 {return {min(a.x, b.x), min(a.y, b.y)}}

// image_preview_fit: the whole image in the canvas, centred (a small one
// enlarged in whole steps, at most 8x: crisp pixel art).
@(private = "file")
image_preview_fit :: proc(p: ^Image_Preview, canvas: [2]f32) {
	size := [2]f32{f32(max(p.tex.width, 1)), f32(max(p.tex.height, 1))}
	z := min((canvas.x - 32) / size.x, (canvas.y - 32) / size.y)
	if z > 1 do z = min(math.floor(z), IMG_PREVIEW_GRID_ZOOM) // (whole steps: crisp pixels)
	p.zoom = clamp(z, 0.01, IMG_PREVIEW_MAX_ZOOM)
	p.offset = (canvas - size * p.zoom) * 0.5
}

// image_preview_zoom_at: zoom keeping the image point under `at` (canvas px) still.
@(private = "file")
image_preview_zoom_at :: proc(p: ^Image_Preview, zoom: f32, at: [2]f32) {
	z := clamp(zoom, 0.01, IMG_PREVIEW_MAX_ZOOM)
	q := (at - p.offset) / p.zoom
	p.zoom = z
	p.offset = at - q * z
}

@(private = "file")
image_preview_checker :: proc() {
	if img.checker.id != 0 do return
	c := rl.GenImageChecked(2, 2, 1, 1, {58, 58, 64, 255}, {44, 44, 50, 255})
	img.checker = rl.LoadTextureFromImage(c)
	rl.UnloadImage(c)
	rl.SetTextureFilter(img.checker, .POINT)
	rl.SetTextureWrap(img.checker, .REPEAT)
}

@(private = "file")
image_preview_toolbar :: proc(p: ^Image_Preview) {
	imgui.Dummy({0, 2})
	imgui.Dummy({4, 0})
	imgui.SameLine(0, 0)
	canvas := p.canvas // (last frame's)
	if UI_IconButton(ICON_FA_EXPAND, "imgpreview.fit", "Fit the image in the view", false, 26) do image_preview_fit(p, canvas)
	imgui.SameLine(0, 4)
	if UI_Button("1:1", "imgpreview.actual", {0, 26}) do image_preview_zoom_at(p, 1 / image_preview_px(p), canvas * 0.5)
	UI_Tooltip("Actual size: one image pixel per screen pixel")
	imgui.SameLine(0, 8)
	if UI_IconButton(ICON_FA_MINUS, "imgpreview.zoom-out", "Zoom out (or the mouse wheel)", false, 26) do image_preview_zoom_at(p, p.zoom / 1.25, canvas * 0.5)
	imgui.SameLine(0, 4)
	imgui.AlignTextToFramePadding()
	imgui.TextUnformatted(fmt.ctprintf("%.0f%%", p.zoom * image_preview_px(p) * 100))
	Drive_Item("imgpreview.zoom")
	imgui.SameLine(0, 4)
	if UI_IconButton(ICON_FA_PLUS, "imgpreview.zoom-in", "Zoom in (or the mouse wheel)", false, 26) do image_preview_zoom_at(p, p.zoom * 1.25, canvas * 0.5)
	imgui.SameLine(0, 12)
	if UI_IconButton(ICON_FA_BORDER_ALL, "imgpreview.grid", fmt.tprintf("Pixel grid (shown from %dx zoom)", IMG_PREVIEW_GRID_ZOOM), p.grid, 26) do p.grid = !p.grid
	if len(p.frames) > 0 {
		imgui.SameLine(0, 4)
		if UI_IconButton(ICON_FA_TABLE_CELLS, "imgpreview.frames", fmt.tprintf("Frames: %s", p.framesOf), p.showFrames, 26) do p.showFrames = !p.showFrames
	}
}

// image_preview_info: the info bar - the image, the file, its import
// settings, the pixel under the cursor.
@(private = "file")
image_preview_info :: proc(p: ^Image_Preview) {
	imgui.Dummy({0, 2})
	imgui.Dummy({4, 0})
	imgui.SameLine(0, 0)
	sb := strings.builder_make(context.temp_allocator)
	ext := strings.to_upper(strings.trim_prefix(filepath.ext(p.rel), "."), context.temp_allocator)
	switch {
	case p.tex.id == 0:
	case p.kind == .Vector: fmt.sbprintf(&sb, "%.0f x %.0f (document)  ·  shown at %.0fx", p.docSize.x, p.docSize.y, p.docScale)
	case: fmt.sbprintf(&sb, "%d x %d px", p.tex.width, p.tex.height)
	}
	fmt.sbprintf(&sb, "%s%s  ·  %s", "  ·  " if strings.builder_len(sb) > 0 else "", ext, FileBrowser_SizeText(p.bytes))
	if p.kind == .Texture && p.tex.id != 0 {
		imp := Editor_AssetImport(&GlobalEditor, p.full)
		fmt.sbprintf(&sb, "  ·  %v, %v%s%s", imp.filter, imp.wrap, ", mipmaps" if imp.mipmaps else "", ", atlas" if imp.atlas else "")
	}
	if p.framesOf != "" do fmt.sbprintf(&sb, "  ·  %s", p.framesOf)
	imgui.AlignTextToFramePadding()
	UI_DimText(strings.to_string(sb))
	Drive_Item("imgpreview.info")
	if p.hover.x >= 0 && p.img.data != nil {
		c := rl.GetImageColor(p.img, p.hover.x, p.hover.y)
		imgui.SameLine(0, 16)
		at := fmt.tprintf("%d, %d", p.hover.x, p.hover.y)
		if p.kind == .Vector do at = fmt.tprintf("%.1f, %.1f", f32(p.hover.x) / p.docScale, f32(p.hover.y) / p.docScale)
		imgui.TextUnformatted(fmt.ctprintf("%s  #%02X%02X%02X%02X", at, c.r, c.g, c.b, c.a))
		imgui.SameLine(0, 6)
		pos := imgui.GetCursorScreenPos()
		h := imgui.GetFrameHeight() - 6
		dl := imgui.GetWindowDrawList()
		imgui.DrawList_AddRectFilled(dl, pos + {0, 3}, pos + {h * 1.6, 3 + h}, transmute(u32)c, 3)
		imgui.DrawList_AddRect(dl, pos + {0, 3}, pos + {h * 1.6, 3 + h}, col_u32({1, 1, 1, 0.3}), 3)
		imgui.Dummy({h * 1.6, h})
	}
}

// ImagePreview_DriveQuery: imgpreview.active (its path, "" for a scene),
// imgpreview.tabs, imgpreview.zoom (%), imgpreview.frames, imgpreview.size,
// imgpreview.error.
ImagePreview_DriveQuery :: proc(q: string) -> (string, bool) {
	p := img.active
	switch q {
	case "imgpreview.active": return p.rel if p != nil else "", true
	case "imgpreview.tabs": return fmt.tprint(len(img.open)), true
	case "imgpreview.zoom": return fmt.tprintf("%.0f", p.zoom * image_preview_px(p) * 100) if p != nil else "", true
	case "imgpreview.frames": return fmt.tprint(len(p.frames)) if p != nil else "", true
	case "imgpreview.size": return fmt.tprintf("%dx%d", p.tex.width, p.tex.height) if p != nil else "", true
	case "imgpreview.error": return p.err if p != nil else "", true
	}
	return "", false
}
