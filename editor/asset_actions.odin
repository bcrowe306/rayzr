package editor

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Asset actions: the context menu every asset row shows (open / add / use on
// the selection, plus copy, paste, duplicate, rename, delete, copy path and
// reveal), folder menus, and LDtk levels in the scene.
// ============================================================================

@(private = "file")
assetClipboard: string // project-relative path of the copied asset

@(private = "file")
pendingDelete: string
@(private = "file")
pendingDeleteMulti: [dynamic]string
@(private = "file")
pendingRename: string

// Asset_BeginRename / Asset_BeginDelete: ask for a new name / confirm
// (files and folders).
Asset_BeginRename :: proc(rel: string) {
	delete(pendingRename)
	pendingRename = strings.clone(rel)
	Prompt_Open(.RenameAsset, filepath.base(rel))
}

Asset_PendingRename :: proc() -> string {
	return pendingRename
}

Asset_BeginDelete :: proc(rel: string) {
	delete(pendingDelete)
	pendingDelete = strings.clone(rel)
	for s in pendingDeleteMulti do delete(s)
	clear(&pendingDeleteMulti)
}

Asset_BeginDeleteMulti :: proc(rels: []string) {
	delete(pendingDelete)
	pendingDelete = ""
	for s in pendingDeleteMulti do delete(s)
	clear(&pendingDeleteMulti)
	for r in rels {
		append(&pendingDeleteMulti, strings.clone(r))
	}
}

AssetActions_Shutdown :: proc() {
	delete(pendingDelete)
	pendingDelete = ""
	delete(pendingRename)
	pendingRename = ""
	delete(assetClipboard)
	assetClipboard = ""
	for s in pendingDeleteMulti do delete(s)
	delete(pendingDeleteMulti)
}

Asset_HasClipboard :: proc() -> bool {return assetClipboard != ""}

@(private = "file")
menu :: proc(icon, label: string, id: string, enabled := true, shortcut: cstring = nil) -> bool {
	clicked := imgui.MenuItem(fmt.ctprintf("%s  %s", icon, label), shortcut, false, enabled)
	Drive_Item(fmt.tprintf("ctx:%s", id))
	return clicked
}

// Editor_AddLevel adds an LdtkLevelNode for an LDtk project (first level).
Editor_AddLevel :: proc(state: ^EditorState, rel: string, worldPos: [2]f32) -> ^e.Node {
	if state.activeScene == nil do return nil
	saved := state.cameraPos
	state.cameraPos = worldPos
	node := Editor_CreateNode(state, "LdtkLevelNode", filepath.stem(rel))
	state.cameraPos = saved
	if node == nil do return nil
	ln := cast(^e.LdtkLevelNode)node
	e.LdtkLevelNode_SetProject(ln, e.Project_ResolveAssetPath(&state.game.gameContext, rel), "")
	Editor_Log(state, .Info, "Added LDtk level %s", rel)
	return node
}

@(private = "file")
attach_script :: proc(state: ^EditorState, n: ^e.Node, rel: string) {
	Editor_AttachScript(state, n, rel)
}

// Editor_AttachScript attaches a script to a node (undoable), replacing the
// one it has.
Editor_AttachScript :: proc(state: ^EditorState, n: ^e.Node, rel: string) -> bool {
	sm := &state.game.scriptManager
	if n.scriptInstance != nil && (cast(^e.ScriptInstance)n.scriptInstance).modulePath == e.ScriptVFS_NormalizePath(rel) do return true
	Editor_RecordUndo(state, "Attach script")
	if n.scriptInstance != nil {
		e.ScriptInstance_Destroy(cast(^e.ScriptInstance)n.scriptInstance, sm)
		n.scriptInstance = nil
	}
	n.gameContext = &state.game.gameContext
	if e.Script_AttachToNode(n, rel, nil, sm) == nil {
		Editor_Log(state, .Error, "Could not attach %s to %s (see errors above)", rel, n.name)
		return false
	}
	if n.typeId == e.CharacterMoverNode {
		(cast(^e.CharacterMoverNode)n).controlMode = .Script
	}
	Editor_Log(state, .Info, "Attached %s to %s", rel, n.name)
	return true
}

@(private = "file")
set_audio :: proc(state: ^EditorState, n: ^e.Node, rel: string) {
	rm := &state.game.resourceManager
	resolved := e.Project_ResolveAssetPath(&state.game.gameContext, rel)
	Editor_RecordUndo(state, "Set audio")
	if n.typeId == e.SoundNode {
		e.SoundNode_SetSound(cast(^e.SoundNode)n, rm, resolved) // (its list becomes this sound)
	} else if n.typeId == e.MusicNode {
		mn := cast(^e.MusicNode)n
		if mn.music != nil do e.ResourceManager_ReleaseMusic(rm, mn.music)
		mn.music = nil
		if m, ok := rm.loadAudioMusic(rm, resolved); ok do mn.music = m
	}
}

// Editor_SetScriptGlobal adds a script to the project's global scripts
// (named after its file: game_state.lua -> GameState) or removes it, saves
// project.json and reloads the globals.
Editor_SetScriptGlobal :: proc(state: ^EditorState, rel: string, global: bool) {
	g := &state.projectConfig.globals
	for x, i in g {
		if x.script != rel do continue
		if global do return
		Editor_Log(state, .Info, "%s is no longer global (%s)", rel, x.name)
		delete(x.name)
		delete(x.script)
		ordered_remove(g, i)
		break
	}
	if global {
		name := Globals_DefaultName(rel)
		append(g, e.Global_Script{strings.clone(name), strings.clone(rel)})
		Editor_Log(state, .Info, "%s is global: every script can use %s", rel, name)
	}
	e.Project_SaveConfigToFile(state.projectPath, &state.projectConfig)
	Editor_ReloadGlobals(state)
}

// Globals_DefaultName: a Lua global name from a script's file name
// ("scripts/game_state.lua" -> "GameState").
Globals_DefaultName :: proc(rel: string) -> string {
	base := strings.trim_suffix(filepath.base(rel), ".lua")
	sb := strings.builder_make(context.temp_allocator)
	up := true
	for r in base {
		switch r {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9':
			if strings.builder_len(sb) == 0 && r >= '0' && r <= '9' do strings.write_byte(&sb, '_')
			strings.write_rune(&sb, r - 32 if up && r >= 'a' && r <= 'z' else r)
			up = false
		case:
			up = true
		}
	}
	return strings.to_string(sb) if strings.builder_len(sb) > 0 else "Global"
}

// Editor_ReloadGlobals applies the project's global scripts to the editor's
// Lua state (outside Simulate: they start when it does) and refreshes the
// generated Lua types.
Editor_ReloadGlobals :: proc(state: ^EditorState) {
	Lua_MarkProjectTypesDirty()
	if state.isSimulating do return
	e.Globals_Load(&state.game.scriptManager, state.projectConfig.globals[:])
}

// Asset_ContextMenu draws the actions for one asset (inside a popup).
Asset_ContextMenu :: proc(state: ^EditorState, rel: string) {
	kind := Asset_KindOf(rel)
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	sel := state.selectedNode
	hasScene := state.activeScene != nil
	UI_DimText(filepath.base(rel))
	imgui.Separator()
	switch kind {
	case .Scene:
		if menu(ICON_FA_FOLDER_OPEN, "Open", "open-scene") do Editor_OpenScene(state, rel)
		if menu(ICON_FA_PLAY, "Play This Scene", "play-scene", !state.gameProcessRunning) {
			if Editor_OpenScene(state, rel) do Editor_PlayGameProcess(state, .CurrentScene)
		}
		if menu(ICON_FA_FLAG, "Set as Startup Scene", "startup-scene", state.projectConfig.initialScene != rel) {
			delete(state.projectConfig.initialScene)
			state.projectConfig.initialScene = strings.clone(rel)
			if !slice.contains(state.projectConfig.scenes[:], rel) do append(&state.projectConfig.scenes, strings.clone(rel))
			e.Project_SaveConfigToFile(state.projectPath, &state.projectConfig)
			Editor_Log(state, .Info, "Startup scene: %s", rel)
		}
	case .CustomNode:
		if menu(ICON_FA_PLUS, "Add to Scene", "add-custom-node", hasScene) do Editor_AddCustomNode(state, rel, state.cameraPos)
		if menu(ICON_FA_PLUS, "Add as Child of Selected", "add-custom-node-child", hasScene && sel != nil) {
			Editor_AddCustomNode(state, rel, sel.globalPosition)
		}
		t, _ := e.CustomNode_Get(&state.game.gameContext, rel)
		script := e.CustomNode_Script(t, &state.game.gameContext) if t != nil else ""
		if menu(ICON_FA_CODE, "Edit Script", "edit-custom-node-script", script != "") do Editor_OpenScript(state, script)
		if menu(ICON_FA_PEN_TO_SQUARE, "Edit Type", "edit-custom-node") do Editor_OpenCustomNodeType(state, rel)
		UI_Tooltip("Its default values as a node: the shape in the viewport, the values in the Inspector")
		if menu(ICON_FA_FILE_CODE, "Edit Definition", "edit-custom-node-file") do Editor_OpenScript(state, rel)
		UI_Tooltip("The .node.json as text (name, base, icon, category, defaults)")
		if menu(ICON_FA_PUZZLE_PIECE, "New Type Based on This...", "new-custom-node-from", t != nil) do CustomNodeDialog_Open(state, rel)
		if menu(ICON_FA_SHUFFLE, "Change Base Type...", "rebase-custom-node", t != nil) do CustomNodeRebase_Open(state, rel)
		UI_Tooltip("Another built-in type under it (Area -> Static Body...): a preview of what changes, then its nodes are converted")
	case .Component:
		if menu(ICON_FA_CUBES, "Edit Component", "edit-component") do Editor_OpenComponent(state, rel)
		if menu(ICON_FA_PLUS, "New Component...", "new-component-file") do NewComponentDialog_Open(state)
		if menu(ICON_FA_OBJECT_GROUP, "Select All Instances", "select-instances", hasScene && Editor_ComponentInstanceCount(state, rel) > 0) do Editor_SelectAllInstances(state, rel)
		if menu(ICON_FA_PLUS, "Add to Scene", "add-component", hasScene) do Editor_InstantiateComponentFile(state, rel, state.cameraPos)
		if menu(ICON_FA_PLUS, "Add as Child of Selected", "add-component-child", hasScene && sel != nil) {
			Editor_InstantiateComponentFile(state, rel, sel.globalPosition)
		}
	case .Generator:
		if menu(ICON_FA_SHUFFLE, "Open in Level Generator", "open-levelgen") do LevelGenEditor_Open(state, rel)
	case .Shader:
		if menu(ICON_FA_CODE, "Edit Shader", "edit-shader") do Editor_OpenScript(state, rel)
		if menu(ICON_FA_WAND_MAGIC_SPARKLES, "Use on Selected Node", "use-shader", sel != nil) {
			Editor_RecordUndo(state, "Set shader")
			e.Material_SetShader(sel, rel)
		}
	case .Script:
		if menu(ICON_FA_CODE, "Edit Script", "edit-script") do Editor_OpenScript(state, rel)
		if menu(ICON_FA_PLUS, "Attach to Selected Node", "attach-script", sel != nil && sel != state.activeScene.rootNode) {
			for n in Editor_SelectionRoots(state) do attach_script(state, n, rel)
		}
		if name := Asset_GlobalName(state, rel); name != "" {
			if menu(ICON_FA_GLOBE, fmt.tprintf("Remove Global (%s)", name), "remove-global") do Editor_SetScriptGlobal(state, rel, false)
		} else {
			if menu(ICON_FA_GLOBE, "Make Global", "make-global") do Editor_SetScriptGlobal(state, rel, true)
		}
	case .Texture:
		if menu(ICON_FA_PLUS, "Add Sprite to Scene", "add-sprite", hasScene) do Editor_DropAsset(state, rel, state.cameraPos)
		if menu(ICON_FA_IMAGE, "Use on Selected Sprite", "use-texture", sel != nil && (sel.typeId == e.TextureNode || sel.typeId == e.AtlasSpriteNode)) {
			Editor_RecordUndo(state, "Set texture")
			if sel.typeId == e.TextureNode {
				Editor_SetTexture(state, cast(^e.TextureNode)sel, rel)
			} else {
				Editor_SetAtlasTexture(state, cast(^e.AtlasSpriteNode)sel, rel)
			}
		}
		if menu(ICON_FA_TABLE_CELLS, "Slice Sprite Sheet...", "slice-sheet") do Slicer_Open(state, rel)
		if menu(ICON_FA_WAND_MAGIC_SPARKLES, "Generate Normal Map...", "normal-map") do NormalGen_Open(state, rel) // (lighting: normal_map_gen.odin)
		if menu(ICON_FA_TABLE_CELLS, "Use as Tileset of Selected Tile Map", "use-tileset", sel != nil && sel.typeId == e.TileMapNode) {
			Editor_RecordUndo(state, "Set tileset")
			e.TileMapNode_SetTileset(cast(^e.TileMapNode)sel, rel, &state.game.gameContext)
		}
	case .Audio:
		if menu(ICON_FA_PLUS, "Add Sound to Scene", "add-sound", hasScene) do Editor_DropAsset(state, rel, state.cameraPos)
		if menu(ICON_FA_PLUS, "Add Music to Scene", "add-music", hasScene) {
			saved := state.cameraPos
			n := Editor_CreateNode(state, "MusicNode", filepath.stem(rel))
			state.cameraPos = saved
			if n != nil do set_audio(state, n, rel)
		}
		if menu(ICON_FA_MUSIC, "Use on Selected Sound/Music", "use-audio", sel != nil && (sel.typeId == e.SoundNode || sel.typeId == e.MusicNode)) do set_audio(state, sel, rel)
	case .Level:
		if menu(ICON_FA_MAP, "Edit in Level Tab", "edit-level") do LevelEditor_Open(state, rel)
		if menu(ICON_FA_PLUS, "Add Level to Scene", "add-level", hasScene) do Editor_AddLevel(state, rel, state.cameraPos)
		if menu(ICON_FA_TABLE_CELLS, "Open in LDtk", "open-ldtk") do Editor_OpenExternally(state, full)
		if menu(ICON_FA_TABLE_CELLS, "Use on Selected Level", "use-level", sel != nil && sel.typeId == e.LdtkLevelNode) {
			Editor_RecordUndo(state, "Set LDtk project")
			e.LdtkLevelNode_SetProject(cast(^e.LdtkLevelNode)sel, e.Project_ResolveAssetPath(&state.game.gameContext, rel), "")
		}
	case .Aseprite:
		if menu(ICON_FA_PLUS, "Add Sprite to Scene", "add-aseprite", hasScene) do Editor_DropAsset(state, rel, state.cameraPos)
		if menu(ICON_FA_PERSON_RUNNING, "Use on Selected Aseprite Node", "use-aseprite", sel != nil && sel.typeId == e.AsepriteNode) {
			Editor_RecordUndo(state, "Set Aseprite file")
			an := cast(^e.AsepriteNode)sel
			an.file = strings.clone(rel, an.allocator)
		}
		if menu(ICON_FA_TABLE_CELLS, "Use as Tileset of Selected Tile Map", "use-ase-tileset", sel != nil && sel.typeId == e.TileMapNode) {
			// Its first tilemap layer becomes the map (TileMapNode_SyncAseprite).
			Editor_RecordUndo(state, "Set tileset")
			tm := cast(^e.TileMapNode)sel
			e.TileMapNode_SetTileset(tm, rel, &state.game.gameContext)
			if r := e.ResourceManager_LoadAseprite(&state.game.resourceManager, e.Project_ResolveAssetPath(&state.game.gameContext, rel)); r != nil {
				for l in r.doc.layers do if l.kind == .Tilemap {
					tm.asepriteLayer = strings.clone(l.name, tm.allocator)
					break
				}
				e.ResourceManager_ReleaseAseprite(r)
			}
			tm.aseVersion = -2 // (sync again)
			e.ResourceManager_ReleaseAseprite(tm.aseRes)
			tm.aseRes = nil
		}
		if menu(ICON_FA_PEN_TO_SQUARE, "Edit in Aseprite", "edit-aseprite") do Aseprite_Edit(state, full)
	case .Vector:
		if menu(ICON_FA_PLUS, "Add Vector Shape to Scene", "add-vector", hasScene) do Editor_DropAsset(state, rel, state.cameraPos)
		if menu(ICON_FA_PAINTBRUSH, "Use on Selected Vector Shape", "use-vector", sel != nil && sel.typeId == e.VectorShapeNode) {
			Editor_RecordUndo(state, "Set vector file")
			v := cast(^e.VectorShapeNode)sel
			v.file = strings.clone(rel, v.allocator)
		}
		if menu(ICON_FA_PEN_TO_SQUARE, "Edit in Vector App", "edit-vector") do Vector_EditExternal(state, full)
	case .Resource:
		class := resource_class_of(state, rel)
		if menu(ICON_FA_CODE, "Edit Class Script", "edit-resource-class", class != "") do Editor_OpenScript(state, class)
		if class != "" do UI_Tooltip(class)
		if menu(ICON_FA_GEM, "New Resource of This Class...", "new-resource-same", class != "") do NewResourceDialog_Open(state, class)
	case .Package, .Other:
		if menu(ICON_FA_FOLDER_OPEN, "Open With Default App", "open-external") do Editor_OpenExternally(state, full)
	}
	imgui.Separator()
	if menu(ICON_FA_COPY, "Copy", "copy-asset", shortcut = nil) {
		delete(assetClipboard)
		assetClipboard = strings.clone(rel)
		imgui.SetClipboardText(strings.clone_to_cstring(rel, context.temp_allocator))
	}
	if menu(ICON_FA_PASTE, "Paste Here", "paste-asset", assetClipboard != "") {
		Asset_Paste(state, filepath.dir(rel, context.temp_allocator))
	}
	if menu(ICON_FA_CLONE, "Duplicate", "duplicate-asset") do Asset_Duplicate(state, rel, filepath.dir(rel, context.temp_allocator))
	if menu(ICON_FA_PEN, "Rename...", "rename-asset") do Asset_BeginRename(rel)
	if menu(ICON_FA_MAGNIFYING_GLASS, "Find Usages", "find-usages") do Asset_ShowUsages(state, rel, false)
	if menu(ICON_FA_TRASH, "Delete...", "delete-asset") do Asset_BeginDelete(rel)
	imgui.Separator()
	if menu(ICON_FA_LINK, "Copy Path", "copy-path") do imgui.SetClipboardText(strings.clone_to_cstring(rel, context.temp_allocator))
	if menu(ICON_FA_FOLDER_OPEN, "Reveal in Finder" when ODIN_OS == .Darwin else "Show in Folder", "reveal") do Editor_OpenExternally(state, filepath.dir(full, context.temp_allocator))
}

// resource_class_of: the class script a resource file names ("" = unreadable).
@(private = "file")
resource_class_of :: proc(state: ^EditorState, rel: string) -> string {
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	data, err := os.read_entire_file(full, context.temp_allocator)
	if err != nil do return ""
	val, perr := json.parse(data, allocator = context.temp_allocator)
	if perr != .None do return ""
	obj, _ := val.(json.Object)
	return string(obj["script"].(json.String) or_else "")
}

// Asset_MultiContextMenu: actions when multiple assets are selected.
// Single-asset actions (rename, edit, play, attach, make global, slice) are excluded.
Asset_MultiContextMenu :: proc(state: ^EditorState) {
	count := Editor_AssetSelectedCount(state)
	UI_DimText(fmt.tprintf("%d assets selected", count))
	imgui.Separator()

	hasScene := state.activeScene != nil
	if hasScene {
		if menu(ICON_FA_PLUS, fmt.tprintf("Add All to Scene (%d)", count), "add-all-to-scene") {
			offset: [2]f32 = 0
			for f in state.selectedAssetPaths {
				rel := strings.trim_prefix(strings.trim_prefix(f, state.projectPath), "/")
				Editor_DropAsset(state, rel, state.cameraPos + offset)
				offset += {16, 16}
			}
		}
	}

	if menu(ICON_FA_CLONE, fmt.tprintf("Duplicate (%d items)", count), "duplicate-multi") {
		rels := make([dynamic]string, context.temp_allocator)
		for f in state.selectedAssetPaths {
			rel := strings.trim_prefix(strings.trim_prefix(f, state.projectPath), "/")
			append(&rels, rel)
		}
		for r in rels {
			Asset_Duplicate(state, r, filepath.dir(r, context.temp_allocator))
		}
	}

	if menu(ICON_FA_TRASH, fmt.tprintf("Delete (%d items)...", count), "delete-multi") {
		rels := make([dynamic]string, context.temp_allocator)
		for f in state.selectedAssetPaths {
			rel := strings.trim_prefix(strings.trim_prefix(f, state.projectPath), "/")
			append(&rels, rel)
		}
		Asset_BeginDeleteMulti(rels[:])
	}

	imgui.Separator()

	if menu(ICON_FA_LINK, "Copy Paths", "copy-paths-multi") {
		sb := strings.builder_make(context.temp_allocator)
		for f, i in state.selectedAssetPaths {
			rel := strings.trim_prefix(strings.trim_prefix(f, state.projectPath), "/")
			if i > 0 do strings.write_byte(&sb, '\n')
			strings.write_string(&sb, rel)
		}
		imgui.SetClipboardText(strings.clone_to_cstring(strings.to_string(sb), context.temp_allocator))
	}

	if menu(ICON_FA_FOLDER_OPEN, "Reveal in Finder" when ODIN_OS == .Darwin else "Show in Folder", "reveal-multi") {
		if len(state.selectedAssetPaths) > 0 {
			Editor_OpenExternally(state, filepath.dir(state.selectedAssetPaths[0], context.temp_allocator))
		}
	}
}

// Asset_FolderContextMenu: actions for a folder header in the Assets panel.
Asset_FolderContextMenu :: proc(state: ^EditorState, title: string) {
	folder := strings.to_lower(title, context.temp_allocator)
	switch title {
	case "Scenes": if menu(ICON_FA_PLUS, "New Scene", "new-scene") do Toolbar_NewScene(state)
	case "Scripts": if menu(ICON_FA_PLUS, "New Script...", "new-script") do NewScriptDialog_Open(state)
	case "Resources":
		if menu(ICON_FA_PLUS, "New Resource...", "new-resource") do NewResourceDialog_Open(state)
		if menu(ICON_FA_FILE_CODE, "New Resource Class...", "new-resource-class") do NewScriptDialog_Open(state, nil, "resource", "new_resource_class")
	case "Levels": if menu(ICON_FA_FILE_IMPORT, "Import LDtk Project...", "import-level") do Asset_OpenImportDialog(state, {"ldtk"}, "Import LDtk Project")
	case "Custom Nodes": if menu(ICON_FA_PLUS, "New Custom Node...", "new-custom-node") do CustomNodeDialog_Open(state)
	case "Components": if menu(ICON_FA_PLUS, "New Component...", "new-component") do NewComponentDialog_Open(state)
	}
	// Import with this folder's file types in the dialog filter.
	switch title {
	case "Textures": if menu(ICON_FA_FILE_IMPORT, "Import Textures...", "import-here") do Asset_OpenImportDialog(state, {"png", "jpg", "jpeg", "bmp", "tga"}, "Import Textures")
	case "Audio": if menu(ICON_FA_FILE_IMPORT, "Import Audio...", "import-here") do Asset_OpenImportDialog(state, {"wav", "ogg", "mp3"}, "Import Audio")
	case "Scripts": if menu(ICON_FA_FILE_IMPORT, "Import Scripts...", "import-here") do Asset_OpenImportDialog(state, {"lua"}, "Import Scripts")
	case "Scenes", "Components": if menu(ICON_FA_FILE_IMPORT, fmt.tprintf("Import %s...", title), "import-here") do Asset_OpenImportDialog(state, {"json"}, fmt.tprintf("Import %s", title))
	}
	if menu(ICON_FA_PASTE, "Paste", "paste-folder", assetClipboard != "") do Asset_Paste(state, folder)
	full, _ := filepath.join({state.projectPath, folder}, context.temp_allocator)
	if menu(ICON_FA_FOLDER_OPEN, "Reveal in Finder" when ODIN_OS == .Darwin else "Show in Folder", "reveal-folder") {
		_ = os.make_directory_all(full)
		Editor_OpenExternally(state, full)
	}
}

// --- file operations ---------------------------------------------------------------

// Asset_SuffixOf returns the canonical compound suffix (".scene.json",
// ".component.json", ".resource.json") or file extension (".lua", ".png", ...)
// of `path`.
Asset_SuffixOf :: proc(path: string) -> string {
	base := filepath.base(path)
	lower := strings.to_lower(base, context.temp_allocator)
	for suffix in ([]string{".scene.json", ".component.json", e.RESOURCE_EXT}) {
		if strings.has_suffix(lower, suffix) do return suffix
	}
	return filepath.ext(base)
}

// Asset_EnsureSuffix strips any partial or duplicate suffix (e.g. ".scene",
// ".json", or ".scene.json" when `suffix` is ".scene.json") and appends
// `suffix` so forgetting part or all of the suffix never drops the asset type.
Asset_EnsureSuffix :: proc(name, suffix: string) -> string {
	t := strings.trim_right(strings.trim_space(name), ".")
	if t == "" || suffix == "" do return t
	lowerSuffix := strings.to_lower(suffix, context.temp_allocator)
	lower := strings.to_lower(t, context.temp_allocator)
	if strings.has_suffix(lower, lowerSuffix) {
		t = strings.trim_right(t[:len(t) - len(suffix)], ".")
	} else {
		innerExt := filepath.ext(suffix)
		midExt := suffix[:len(suffix) - len(innerExt)]
		if midExt != "" {
			lowerMid := strings.to_lower(midExt, context.temp_allocator)
			lowerInner := strings.to_lower(innerExt, context.temp_allocator)
			if strings.has_suffix(lower, lowerInner) {
				t = strings.trim_right(t[:len(t) - len(innerExt)], ".")
				lower = strings.to_lower(t, context.temp_allocator)
			}
			if strings.has_suffix(lower, lowerMid) {
				t = strings.trim_right(t[:len(t) - len(midExt)], ".")
			}
		}
	}
	if t == "" do return ""
	return strings.concatenate({t, suffix}, context.temp_allocator)
}

// Asset_NormalizedRename returns `newName` with the appropriate compound
// suffix or file extension preserved from `oldRel` (unless `isFolder` is true).
Asset_NormalizedRename :: proc(oldRel, newName: string, isFolder := false) -> string {
	trimmed := strings.trim_space(newName)
	if isFolder || trimmed == "" do return trimmed
	suffix := Asset_SuffixOf(oldRel)
	if suffix == "" do return trimmed
	if suffix == ".scene.json" || suffix == ".component.json" || suffix == e.RESOURCE_EXT {
		return Asset_EnsureSuffix(trimmed, suffix)
	}
	clean := strings.trim_right(trimmed, ".")
	if clean == "" do return ""
	oldKind := Asset_KindOf(oldRel)
	if oldKind != .Other {
		if Asset_KindOf(clean) == oldKind do return clean
		return Asset_EnsureSuffix(clean, suffix)
	}
	if filepath.ext(clean) != "" do return clean
	return Asset_EnsureSuffix(clean, suffix)
}

@(private = "file")
unique_copy_name :: proc(state: ^EditorState, dir, base: string) -> string {
	// "ship.png" -> "ship_copy.png", "ship_copy_2.png", ...
	ext := Asset_SuffixOf(base)
	stem := base[:len(base) - len(ext)]
	for i := 1; ; i += 1 {
		name := fmt.tprintf("%s_copy%s", stem, ext) if i == 1 else fmt.tprintf("%s_copy_%d%s", stem, i, ext)
		rel, _ := filepath.join({dir, name}, context.temp_allocator)
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		if !os.exists(full) do return rel
	}
}

Asset_Duplicate :: proc(state: ^EditorState, rel, toDir: string) -> string {
	Lua_MarkProjectTypesDirty() // generated Lua types follow the project
	src, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	data, err := os.read_entire_file(src, context.temp_allocator)
	if err != nil {
		Editor_Log(state, .Error, "Could not read %s", rel)
		return ""
	}
	dst := unique_copy_name(state, toDir, filepath.base(rel))
	full, _ := filepath.join({state.projectPath, dst}, context.temp_allocator)
	_ = os.make_directory_all(filepath.dir(full, context.temp_allocator))
	if strings.has_suffix(dst, ".lua") do data = transmute([]u8)script_copy_renamed(string(data), dst)
	if os.write_entire_file(full, data) != nil {
		Editor_Log(state, .Error, "Could not write %s", dst)
		return ""
	}
	if side, serr := os.read_entire_file(strings.concatenate({src, e.IMPORT_SUFFIX}, context.temp_allocator), context.temp_allocator); serr == nil {
		_ = os.write_entire_file(strings.concatenate({full, e.IMPORT_SUFFIX}, context.temp_allocator), side) // (its import settings)
	}
	if Asset_KindOf(dst) == .Scene {
		append(&state.projectConfig.scenes, strings.clone(dst))
		e.Project_SaveConfigToFile(state.projectPath, &state.projectConfig)
	}
	Editor_Log(state, .Info, "Copied %s to %s", rel, dst)
	return dst
}

// script_copy_renamed: a script's text with its class renamed after the
// copy's file name (player_copy.lua: PlayerCopy), so the two don't declare
// the same class (lua-language-server would see each method twice, #264).
script_copy_renamed :: proc(text, dst: string) -> string {
	old := Script_ClassName(text)
	stem := strings.trim_suffix(filepath.base(dst), ".lua")
	cls := script_class_name(stem)
	if old == "" || cls == "" || cls == old do return text
	for ch, i in cls do if !((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_' || (i > 0 && ch >= '0' && ch <= '9')) do return text
	word :: proc(ch: u8) -> bool {return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_'}
	// Every whole-word use of the old name (---@class, local, function, return).
	sb := strings.builder_make(context.temp_allocator)
	i := 0
	for i < len(text) {
		j := strings.index(text[i:], old)
		if j < 0 do break
		at := i + j
		end := at + len(old)
		strings.write_string(&sb, text[i:at])
		if (at == 0 || !word(text[at - 1])) && (end == len(text) || !word(text[end])) {
			strings.write_string(&sb, cls)
		} else {
			strings.write_string(&sb, old)
		}
		i = end
	}
	strings.write_string(&sb, text[i:])
	return strings.to_string(sb)
}

Asset_Paste :: proc(state: ^EditorState, toDir: string) {
	if assetClipboard == "" do return
	Asset_Duplicate(state, assetClipboard, toDir)
}

Asset_Rename :: proc(state: ^EditorState, rel, newName: string) -> bool {
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	normalized := Asset_NormalizedRename(rel, newName, os.is_dir(full))
	if normalized == "" do return false
	dst, _ := filepath.join({filepath.dir(rel, context.temp_allocator), normalized}, context.temp_allocator)
	return Asset_Move(state, rel, dst) // references follow (asset_refs.odin)
}

Asset_Delete :: proc(state: ^EditorState, rel: string) -> bool {
	Lua_MarkProjectTypesDirty() // generated Lua types follow the project
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	isDir := os.is_dir(full)
	if (os.remove_all(full) if isDir else os.remove(full)) != nil {
		Editor_Log(state, .Error, "Could not delete %s", rel)
		return false
	}
	if !isDir do _ = os.remove(strings.concatenate({full, e.IMPORT_SUFFIX}, context.temp_allocator)) // (its import settings)
	e.Asset_ImportsReset()
	Editor_InvalidateProjectFiles()
	// Deleted scenes leave the project's scene list.
	prefix := strings.concatenate({rel, "/"}, context.temp_allocator)
	removed := false
	for i := len(state.projectConfig.scenes) - 1; i >= 0; i -= 1 {
		s := state.projectConfig.scenes[i]
		if s == rel || (isDir && strings.has_prefix(s, prefix)) {
			delete(s)
			ordered_remove(&state.projectConfig.scenes, i)
			removed = true
		}
	}
	if removed do e.Project_SaveConfigToFile(state.projectPath, &state.projectConfig)
	Editor_Log(state, .Info, "Deleted %s", rel)
	return true
}

// Asset_PromptApply finishes a rename started from a menu.
Asset_PromptApply :: proc(state: ^EditorState, kind: Prompt_Kind, text: string) {
	#partial switch kind {
	case .RenameAsset:
		if pendingRename != "" do Asset_Rename(state, pendingRename, text)
	}
}

// Asset_AddMenu: the Assets panel's "+" menu.
Asset_AddMenu :: proc(state: ^EditorState) {
	busy := NativeDialog_IsOpen()
	if menu(ICON_FA_FILE_IMPORT, "Import Assets...", "add-import", !busy) do Asset_OpenImportDialog(state)
	UI_Tooltip("Pick one or more files (images, audio, Lua, scenes, components, LDtk)")
	if menu(ICON_FA_FOLDER_PLUS, "Import Folder...", "add-import-folder", !busy) do Asset_OpenImportFolderDialog(state)
	UI_Tooltip("Imports every supported file in a folder, keeping its layout")
	imgui.Separator()
	if menu(ICON_FA_CLAPPERBOARD, "New Scene", "add-new-scene") do Toolbar_NewScene(state)
	if menu(ICON_FA_FILE_CODE, "New Script...", "add-new-script") do NewScriptDialog_Open(state)
	if menu(ICON_FA_GEM, "New Resource...", "add-new-resource") do NewResourceDialog_Open(state)
	UI_Tooltip("A data asset of a resource class (a script with a `resource` marker)")
	if menu(ICON_FA_CUBES, "New Component...", "add-new-component") do NewComponentDialog_Open(state)
	UI_Tooltip("A reusable piece of a scene, built from scratch: pick its root node, then add to it")
	if menu(ICON_FA_PUZZLE_PIECE, "New Custom Node...", "add-new-custom-node") do CustomNodeDialog_Open(state)
	UI_Tooltip("A node type of your own (a Hurtbox: an Area, its script and a box), listed in Add Node")
	if menu(ICON_FA_WAND_MAGIC_SPARKLES, "New Shader", "add-new-shader") do Editor_NewShader(state)
	if menu(ICON_FA_SHUFFLE, "New Level Generator", "add-new-levelgen") do LevelGenEditor_New(state)
	UI_Tooltip("A procedural level: a graph of nodes (noise, caves, ...) written into a TileMap")
}

// AssetDelete_Render: the delete confirmation (single or multi).
AssetDelete_Render :: proc(state: ^EditorState) {
	hasSingle := pendingDelete != ""
	hasMulti := len(pendingDeleteMulti) > 0
	if !hasSingle && !hasMulti do return

	if !imgui.IsPopupOpen("Delete Asset###DeleteAsset") do imgui.OpenPopup("Delete Asset###DeleteAsset")
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if !imgui.BeginPopupModal("Delete Asset###DeleteAsset", nil, {.NoTitleBar, .AlwaysAutoResize}) do return

	if hasMulti {
		UI_PanelTitle(ICON_FA_TRASH, fmt.tprintf("Delete %d assets?", len(pendingDeleteMulti)))
		imgui.Dummy({0, 4})
		imgui.TextUnformatted(fmt.ctprintf("Are you sure you want to delete these %d assets from the project?", len(pendingDeleteMulti)))
		imgui.Dummy({0, 2})
		maxShow := min(len(pendingDeleteMulti), 6)
		for i := 0; i < maxShow; i += 1 {
			UI_DimText(fmt.tprintf("  • %s", pendingDeleteMulti[i]))
		}
		if len(pendingDeleteMulti) > maxShow {
			UI_DimText(fmt.tprintf("  ... and %d more", len(pendingDeleteMulti) - maxShow))
		}
		imgui.Dummy({0, 4})
		UI_DimText("Scenes, scripts or components that use them will show them as missing.")
		imgui.Dummy({0, 6})
		if UI_PrimaryButton("Delete", "delete.ok", {96, 0}) {
			for r in pendingDeleteMulti {
				Asset_Delete(state, r)
				delete(r)
			}
			clear(&pendingDeleteMulti)
			Editor_ClearAssetSelection(state)
			imgui.CloseCurrentPopup()
		}
		imgui.SameLine()
		if UI_Button("Cancel", "delete.cancel", {96, 0}) || imgui.IsKeyPressed(.Escape, false) {
			for r in pendingDeleteMulti do delete(r)
			clear(&pendingDeleteMulti)
			imgui.CloseCurrentPopup()
		}
	} else {
		UI_PanelTitle(ICON_FA_TRASH, "Delete asset?")
		imgui.Dummy({0, 4})
		full, _ := filepath.join({state.projectPath, pendingDelete}, context.temp_allocator)
		if os.is_dir(full) {
			n := 0
			for f in Editor_ProjectFiles(state) do if strings.has_prefix(f, strings.concatenate({pendingDelete, "/"}, context.temp_allocator)) do n += 1
			imgui.TextUnformatted(fmt.ctprintf("The folder %s and the %d file(s) in it will be deleted.", pendingDelete, n))
		} else {
			imgui.TextUnformatted(fmt.ctprintf("%s will be deleted from the project folder.", pendingDelete))
		}
		UI_DimText("Scenes, scripts or components that use it will show it as missing.")
		imgui.Dummy({0, 6})
		if UI_PrimaryButton("Delete", "delete.ok", {96, 0}) {
			Asset_Delete(state, pendingDelete)
			delete(pendingDelete)
			pendingDelete = ""
			Editor_ClearAssetSelection(state)
			imgui.CloseCurrentPopup()
		}
		imgui.SameLine()
		if UI_Button("Cancel", "delete.cancel", {96, 0}) || imgui.IsKeyPressed(.Escape, false) {
			delete(pendingDelete)
			pendingDelete = ""
			imgui.CloseCurrentPopup()
		}
	}
	imgui.EndPopup()
}
