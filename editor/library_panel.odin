package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"
import rl "vendor:raylib"

// ============================================================================
// The Library (#269): a bottom tab with a vector file's symbols - its named
// groups - as previews, with how many nodes of the open scene use each.
//
//   drag a symbol into the viewport   a Vector Shape drawing it, there
//   double-click                      edit it in place (a node using it, else
//                                     a new one at the view's centre)
//   right-click                       Place, Rename, Duplicate, Delete
//
// The file is the selected Vector Shape's (when one is selected), else the
// one picked at the top.
// ============================================================================

LIBRARY_PAYLOAD :: "RAYZR_SYMBOL"

@(private = "file")
Library_Payload :: struct {
	file:  [256]u8,
	group: [256]u8,
}

@(private = "file")
lib: struct {
	file:     string,
	thumbs:   map[string]rl.Texture2D, // "file|group|version" -> preview
	renameOf: int,
	nameBuf:  [64]u8,
	menuFor:  int,
}

LibraryPanel_Render :: proc(state: ^EditorState) {
	if lib.thumbs == nil do lib.thumbs = make(map[string]rl.Texture2D)
	// The file: the selected Vector Shape's, else the picked one.
	if sel := state.selectedNode; sel != nil && sel.typeId == e.VectorShapeNode {
		if f := (cast(^e.VectorShapeNode)sel).file; f != "" && f != lib.file do library_set_file(f)
	}
	imgui.TextUnformatted("File")
	imgui.SameLine()
	imgui.SetNextItemWidth(320)
	if path, ok := asset_picker("library.file", lib.file, vector_files(state), allowNone = false); ok do library_set_file(path)
	if lib.file == "" {
		UI_DimText("Pick an SVG (or select a Vector Shape) to see its symbols.")
		return
	}
	r := library_resource(state, lib.file)
	if r == nil {
		UI_DimText("Could not load the file.")
		return
	}
	named := make([dynamic]int, context.temp_allocator)
	for g, i in r.doc.groups do if g.name != "" do append(&named, i)
	imgui.SameLine()
	UI_DimText(fmt.tprintf("%d symbols", len(named)))
	Drive_Item("library.count")
	if len(named) == 0 {
		UI_DimText("No symbols yet: name groups in your vector app, or select shapes while drawing and press F8 (Convert to Symbol).")
		return
	}
	TILE :: 96
	avail := imgui.GetContentRegionAvail().x
	perRow := max(int(avail / (TILE + 12)), 1)
	for gi, k in named {
		path := e.Vector_GroupPath(r, gi)
		if k % perRow != 0 do imgui.SameLine(0, 12)
		imgui.BeginGroup()
		imgui.PushIDInt(i32(gi))
		at := imgui.GetCursorScreenPos()
		imgui.InvisibleButton("##tile", {TILE, TILE})
		hovered := imgui.IsItemHovered()
		Drive_ItemRect(fmt.tprintf("library.symbol:%s", path), at, at + {TILE, TILE}, inWindow = true)
		dl := imgui.GetWindowDrawList()
		imgui.DrawList_AddRectFilled(dl, at, at + {TILE, TILE}, col_u32(ui_line(0.08)), 4)
		if tex := library_thumb(r, gi); tex.id != 0 {
			s := min(f32(TILE - 8) / f32(tex.width), f32(TILE - 8) / f32(tex.height))
			sz := [2]f32{f32(tex.width) * s, f32(tex.height) * s}
			p := at + ([2]f32{TILE, TILE} - sz) * 0.5
			t := tex
			imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)&t, p, p + sz)
		}
		imgui.DrawList_AddRect(dl, at, at + {TILE, TILE}, col_u32(UI_ACCENT if hovered else ui_line(0.25)), 4)
		// Drag into the viewport: an instance.
		if imgui.BeginDragDropSource({}) {
			pl: Library_Payload
			copy(pl.file[:255], lib.file)
			copy(pl.group[:255], path)
			imgui.SetDragDropPayload(LIBRARY_PAYLOAD, &pl, size_of(pl))
			imgui.TextUnformatted(fmt.ctprintf("%s  %s", ICON_FA_CUBE, path))
			imgui.EndDragDropSource()
		}
		if hovered && imgui.IsMouseDoubleClicked(.Left) do library_edit(state, lib.file, path)
		if imgui.IsItemClicked(.Right) {
			lib.menuFor = gi
			imgui.OpenPopup("##library_menu")
		}
		uses := library_uses(state, lib.file, path)
		name := r.doc.groups[gi].name
		imgui.TextUnformatted(fmt.ctprintf("%s", name if len(name) <= 14 else fmt.tprintf("%s...", name[:12])))
		UI_Tooltip(fmt.tprintf("%s - used by %d node(s) in this scene. Drag into the viewport, double-click to edit, right-click for more.", path, uses))
		UI_DimText(fmt.tprintf("%d use%s", uses, "" if uses == 1 else "s"))
		Drive_Item(fmt.tprintf("library.uses:%s", path))
		if lib.menuFor == gi do library_menu(state, r, gi, path)
		imgui.PopID()
		imgui.EndGroup()
	}
	library_rename_dialog(state, r)
}

@(private = "file")
library_set_file :: proc(f: string) {
	if lib.file != "" do delete(lib.file)
	lib.file = strings.clone(f)
}

// library_resource: the file's loaded document (shared with the nodes
// drawing it; loaded through a node-less reference otherwise).
@(private = "file")
library_resource :: proc(state: ^EditorState, rel: string) -> ^e.Vector_Resource {
	full := e.Project_ResolveAssetPath(&state.game.gameContext, rel)
	rm := &state.game.resourceManager
	if rm.vectors != nil {
		if r, ok := rm.vectors[full]; ok do return r
	}
	return e.ResourceManager_LoadVector(rm, full) // (kept while the editor runs)
}

@(private = "file")
library_thumb :: proc(r: ^e.Vector_Resource, g: int) -> rl.Texture2D {
	key := fmt.tprintf("%s|%d|%d", r.path, g, r.version)
	if t, ok := lib.thumbs[key]; ok do return t
	img := e.Vector_PartImage(r, g, 128)
	defer if img.data != nil do rl.UnloadImage(img)
	t: rl.Texture2D
	if img.data != nil {
		t = rl.LoadTextureFromImage(img)
		rl.SetTextureFilter(t, .BILINEAR)
	}
	lib.thumbs[strings.clone(key)] = t
	return t
}

// library_uses: the open scene's Vector Shapes drawing that symbol.
@(private = "file")
library_uses :: proc(state: ^EditorState, file, path: string) -> int {
	if state.activeScene == nil do return 0
	n := 0
	for node in state.activeScene.manager.nodes {
		if node == nil || node.typeId != e.VectorShapeNode do continue
		v := cast(^e.VectorShapeNode)node
		if v.file == file && v.group == path do n += 1
	}
	return n
}

// library_place: a Vector Shape drawing the symbol, at a world position
// (under the scene's root), selected.
library_place :: proc(state: ^EditorState, file, path: string, world: [2]f32) -> ^e.VectorShapeNode {
	if state.activeScene == nil do return nil
	Editor_RecordUndo(state, fmt.tprintf("Place %s", path))
	scene := state.activeScene
	root := scene.rootNode
	v := cast(^e.VectorShapeNode)e.Node_CreateByTypeName(scene, "VectorShapeNode", root)
	if v == nil do return nil
	leaf := path[strings.last_index_byte(path, '/') + 1:]
	v.name = strings.clone(Editor_UniqueChildName(state, root, leaf), v.allocator)
	v.file = strings.clone(file, v.allocator)
	v.group = strings.clone(path, v.allocator)
	v.gameContext = &state.game.gameContext
	v.position = world
	e.ProcessNodeQueues(scene.manager, &state.game.gameContext)
	e.Node_SetGlobalPositions(scene.manager, root)
	Editor_SelectNode(state, &v.node)
	return v
}

// Library_HandleViewportDrop: a symbol dropped on the viewport.
Library_HandleViewportDrop :: proc(state: ^EditorState, world: [2]f32) {
	if !imgui.BeginDragDropTarget() do return
	defer imgui.EndDragDropTarget()
	payload := imgui.AcceptDragDropPayload(LIBRARY_PAYLOAD)
	if payload == nil do return
	p := (^Library_Payload)(payload.Data)
	file := strings.clone(string(cstring(raw_data(p.file[:]))), context.temp_allocator)
	group := strings.clone(string(cstring(raw_data(p.group[:]))), context.temp_allocator)
	library_place(state, file, group, world)
}

// library_edit: a node drawing the symbol (the selected one, else the
// scene's first, else a new one at the view's centre), editing its art.
@(private = "file")
library_edit :: proc(state: ^EditorState, file, path: string) {
	target: ^e.VectorShapeNode
	if sel := state.selectedNode; sel != nil && sel.typeId == e.VectorShapeNode {
		v := cast(^e.VectorShapeNode)sel
		if v.file == file && v.group == path do target = v
	}
	if target == nil && state.activeScene != nil {
		for node in state.activeScene.manager.nodes {
			if node == nil || node.typeId != e.VectorShapeNode do continue
			v := cast(^e.VectorShapeNode)node
			if v.file == file && v.group == path {target = v; break}
		}
	}
	if target == nil do target = library_place(state, file, path, Viewport_ScreenToWorld(state, state.viewportPos + state.viewportSize * 0.5))
	if target == nil do return
	Editor_SelectNode(state, &target.node)
	VectorDraw_Enter(state, target)
}

@(private = "file")
library_menu :: proc(state: ^EditorState, r: ^e.Vector_Resource, gi: int, path: string) {
	if !imgui.BeginPopup("##library_menu") do return
	defer imgui.EndPopup()
	if imgui.MenuItem("Place in the Scene") do library_place(state, lib.file, path, Viewport_ScreenToWorld(state, state.viewportPos + state.viewportSize * 0.5))
	Drive_Item("ctx:library-place")
	if imgui.MenuItem("Edit") do library_edit(state, lib.file, path)
	Drive_Item("ctx:library-edit")
	if imgui.MenuItem("Rename...") {
		lib.renameOf = gi + 1
		lib.nameBuf = {}
		copy(lib.nameBuf[:63], r.doc.groups[gi].name)
	}
	Drive_Item("ctx:library-rename")
	if imgui.MenuItem("Duplicate") {
		e.Vector_ResourceEditBegin(r)
		e.Vector_DocDuplicateGroup(&r.doc, gi, e.Vector_DocGroupNameFree(&r.doc, r.doc.groups[gi].name))
		library_save(state, r, "Duplicate symbol")
	}
	Drive_Item("ctx:library-duplicate")
	uses := library_uses(state, lib.file, path)
	if imgui.MenuItem(fmt.ctprintf("Delete%s", fmt.tprintf(" (%d node(s) use it)", uses) if uses > 0 else "")) {
		e.Vector_ResourceEditBegin(r)
		e.Vector_DocRemoveGroup(&r.doc, gi)
		library_save(state, r, "Delete symbol")
		if uses > 0 do Editor_Log(state, .Warn, "%d node(s) drew %s: they draw nothing now (pick another symbol, or undo)", uses, path)
	}
	Drive_Item("ctx:library-delete")
}

// library_rename_dialog: a symbol's new name; the scene's nodes drawing it
// follow (their Symbol field).
@(private = "file")
library_rename_dialog :: proc(state: ^EditorState, r: ^e.Vector_Resource) {
	if lib.renameOf == 0 do return
	gi := lib.renameOf - 1
	if gi >= len(r.doc.groups) {lib.renameOf = 0; return}
	if !imgui.IsPopupOpen("Rename Symbol###library_rename") do imgui.OpenPopup("Rename Symbol###library_rename")
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Always, {0.5, 0.5})
	if !imgui.BeginPopupModal("Rename Symbol###library_rename", nil, {.AlwaysAutoResize}) do return
	defer imgui.EndPopup()
	if imgui.IsWindowAppearing() do imgui.SetKeyboardFocusHere()
	imgui.SetNextItemWidth(260)
	enter := imgui.InputText("##libname", cstring(raw_data(lib.nameBuf[:])), len(lib.nameBuf), {.EnterReturnsTrue, .AutoSelectAll})
	Drive_Item("library.rename.name")
	if enter || UI_PrimaryButton("Rename", "library.rename.ok") {
		name := strings.trim_space(string(cstring(raw_data(lib.nameBuf[:]))))
		if name != "" && name != r.doc.groups[gi].name {
			old := e.Vector_GroupPath(r, gi)
			e.Vector_ResourceEditBegin(r)
			r.doc.groups[gi].name = strings.clone(e.Vector_DocGroupNameFree(&r.doc, name), e.Vector_EditAllocator(&r.doc))
			now := e.Vector_GroupPath(r, gi)
			// The nodes drawing it (or a symbol inside it) follow.
			if state.activeScene != nil {
				Editor_RecordUndo(state, "Rename symbol")
				for node in state.activeScene.manager.nodes {
					if node == nil || node.typeId != e.VectorShapeNode do continue
					v := cast(^e.VectorShapeNode)node
					if v.file != lib.file do continue
					if v.group == old do v.group = strings.clone(now, v.allocator)
					else if strings.has_prefix(v.group, strings.concatenate({old, "/"}, context.temp_allocator)) do v.group = strings.concatenate({now, v.group[len(old):]}, v.allocator)
				}
			}
			library_save(state, r, "Rename symbol")
		}
		lib.renameOf = 0
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Cancel", "library.rename.cancel") || imgui.IsKeyPressed(.Escape, false) {
		lib.renameOf = 0
		imgui.CloseCurrentPopup()
	}
}

// library_save: the changed document into its file (undoable).
@(private = "file")
library_save :: proc(state: ^EditorState, r: ^e.Vector_Resource, label: string) {
	e.Vector_ResourceEdited(r)
	Editor_RecordFileUndo(state, lib.file, label)
	if os.write_entire_file(r.path, transmute([]u8)e.Vector_Doc_ToSVG(&r.doc, context.temp_allocator)) != nil {
		Editor_Log(state, .Error, "Could not save %s", lib.file)
		return
	}
	e.Vector_ResourceSaved(r)
	Editor_InvalidateProjectFiles()
}

_ :: filepath.base
