package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Level editor: the Project tab (LDtk's EditProject) and the project's save
// / load hooks (backups; external enums synced on load).
//
//   file      extension (.ldtk / .json), backups, minify, external levels
//   names     identifier style (applied everywhere), level name pattern
//   defaults  grid, entity size and pivot, colours
//   advanced  LDtk's project flags
//   notes     the project's description
// ============================================================================

@(private = "file")
lp: struct {
	styleReq:  bool,
	styleTo:   e.Ldtk_IdentifierStyle,
	descBuf:   [2048]u8,
	descFor:   rawptr,
}

PROJECT_TOPIC :: "tab.project"

// LevelProject_BeforeSave: a backup of the files on disk, when enabled.
LevelProject_BeforeSave :: proc(state: ^EditorState) {
	doc := GlobalLevel.doc
	if doc == nil || !e.LdtkJson_Bool(doc.root, "backupOnSave") do return
	if dir := e.Ldtk_Doc_Backup(doc); dir != "" do Editor_Log(state, .Info, "Backup: %s", dir)
}

// LevelProject_AfterSave: the exports the project asks for (images,
// simplified data, Tiled), then AfterSave commands.
LevelProject_AfterSave :: proc(state: ^EditorState) {
	doc := GlobalLevel.doc
	if doc == nil do return
	r := e.Ldtk_Doc_RunExports(doc)
	if r.files > 0 do Editor_Log(state, .Info, "Exported %d file(s)", r.files)
	for err in r.errors do Editor_Log(state, .Warn, "Export: %s", err)
	LevelCommands_Run(state, "AfterSave")
}

// LevelProject_AfterLoad: external enum files changed since the last sync are
// synced (asking first when used values would go); AfterLoad commands run.
LevelProject_AfterLoad :: proc(state: ^EditorState) {
	doc := GlobalLevel.doc
	if doc == nil do return
	defer LevelCommands_Run(state, "AfterLoad")
	for src in e.Ldtk_Doc_ExternalEnumSources(doc) {
		if src.missing {
			Editor_Log(state, .Warn, "External enum file not found: %s", src.relPath)
			continue
		}
		if src.modified do LevelEnums_Sync(state, src.relPath, true)
	}
}

LevelProject_Page :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	root := doc.root
	a := doc.allocator
	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##project_props", {460, avail.y}, {}, {}) {
		UI_PanelTitle(ICON_FA_GEAR, "Project", filepath.base(L.rel))
		UI_HeaderButtons(1)
		if UI_HeaderButton(ICON_FA_CIRCLE_QUESTION, "defs.project.help", "") do LevelRef_Open(PROJECT_TOPIC)
		level_tip("The Project tab in the reference", PROJECT_TOPIC)
		if UI_SectionHeader("File") && UI_BeginProps("##proj_file") {
			UI_PropLabel("File extension")
			ext := filepath.ext(doc.path)
			if pick, ch := UI_Combo("defs.project.ext", ext == ".json" ? 1 : 0, []string{".ldtk (LDtk's)", ".json"}); ch {
				project_set_extension(state, pick == 1 ? ".json" : ".ldtk")
			}
			level_tip("Renames the project file (the same JSON either way)", "project.file")
			prop_bool("Backup on save", "defs.project.backup", root, "backupOnSave", "Before each save, a copy of the files as they were goes to the backup folder", "project.file")
			if e.LdtkJson_Bool(root, "backupOnSave") {
				UI_PropLabel("Backups kept")
				if lim, set := level_input_int("##blimit", i32(e.LdtkJson_Int(root, "backupLimit", 10)), 1, 5); set {
					defs_checkpoint("Backup Limit")
					e.LdtkJson_SetInt(root, "backupLimit", int(clamp(lim, 3, 50)), a)
					e.Ldtk_Doc_Touch(doc)
				}
				Drive_Item("defs.project.backuplimit")
				level_tip("How many backups stay (3-50; the oldest go first)", "project.file")
				prop_text("Backup folder", "defs.project.backupdir", root, "backupRelPath", "Relative to the project file; empty: <project name>/backups", "project.file")
				UI_PropLabel("")
				if UI_Button(fmt.tprintf("%s  Open backups", ICON_FA_FOLDER_OPEN), "defs.project.openbackups") {
					dir := e.Ldtk_Doc_BackupDir(doc)
					_ = os.make_directory_all(dir)
					Editor_OpenExternally(state, dir)
				}
				level_tip("Show the backup folder", "project.file")
				imgui.SameLine()
				if UI_Button(fmt.tprintf("%s  Back up now", ICON_FA_COPY), "defs.project.backupnow") {
					if dir := e.Ldtk_Doc_Backup(doc); dir != "" do Editor_Log(state, .Info, "Backup: %s", dir)
					else do Editor_Log(state, .Warn, "Nothing to back up: save the project first")
				}
				level_tip("A backup of the saved files now", "project.file")
			}
			UI_PropLabel("Minify JSON")
			minify := e.LdtkJson_Bool(root, "minifyJson")
			if imgui.Checkbox("##minify", &minify) {
				defs_checkpoint("Minify JSON")
				e.LdtkJson_SetBool(root, "minifyJson", minify, a)
				doc.minify = minify
				for &lv in doc.levels do lv.dirty = true
				e.Ldtk_Doc_Touch(doc)
			}
			Drive_Item("defs.project.minify")
			level_tip("One line of JSON: smaller files, harder to read or merge", "project.file")
			UI_PropLabel("External level files")
			ext_on := doc.external
			if imgui.Checkbox("##external", &ext_on) {
				defs_checkpoint("External Levels")
				e.Ldtk_Doc_SetExternalLevels(doc, ext_on)
			}
			Drive_Item("defs.project.external")
			level_tip("Each level in its own .ldtkl file (in a folder named like the project): good for big projects and version control", "project.file")
			UI_EndProps()
		}
		if UI_SectionHeader("Exports", false) && UI_BeginProps("##proj_exports") {
			simplified := e.LdtkJson_Bool(root, "simplifiedExport")
			UI_PropLabel("Images")
			{
				labels := []string{"No images", "One PNG per layer", "One PNG per level (layers merged)", "One PNG per layer and per level"}
				mode := e.LdtkJson_Str(root, "imageExportMode", "None")
				cur := 0
				for m, i in e.LDTK_IMAGE_EXPORT_MODES do if m == mode do cur = i
				imgui.BeginDisabled(simplified)
				if pick, ch := UI_Combo("defs.project.images", cur, labels); ch {
					defs_checkpoint("Image Export")
					e.LdtkJson_SetStr(root, "imageExportMode", e.LDTK_IMAGE_EXPORT_MODES[pick], a)
					e.LdtkJson_SetNull(root, "pngFilePattern", a)
					e.Ldtk_Doc_Touch(doc)
				}
				imgui.EndDisabled()
				level_tip(simplified ? "The simplified export writes its own images" : "PNGs written to <project name>/png on each save (IntGrid layers also as one pixel per cell, \"-int\")", "project.exports")
			}
			if !simplified && e.LdtkJson_Str(root, "imageExportMode", "None") != "None" {
				UI_PropLabel("File names")
				buf: [256]u8
				pat := e.LdtkJson_Str(root, "pngFilePattern")
				copy(buf[:255], pat != "" ? pat : e.Ldtk_Doc_DefaultPngPattern(doc))
				if imgui.InputText("##pngpat", cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue}) || imgui.IsItemDeactivatedAfterEdit() {
					t := strings.trim_space(string(cstring(raw_data(buf[:]))))
					defs_checkpoint("PNG File Names")
					if t == "" || t == e.Ldtk_Doc_DefaultPngPattern(doc) do e.LdtkJson_SetNull(root, "pngFilePattern", a)
					else do e.LdtkJson_SetStr(root, "pngFilePattern", t, a)
					e.Ldtk_Doc_Touch(doc)
				}
				Drive_Item("defs.project.pngpattern")
				level_tip("%level_name, %level_idx, %layer_name, %layer_idx, %world (Enter applies; empty: the default)", "project.exports")
				prop_bool("Export backgrounds", "defs.project.exportbg", root, "exportLevelBg", "Levels' background colour and image as <level>_bg.png (and under the merged images)", "project.exports", true)
			}
			prop_bool("Simplified export", "defs.project.simplified", root, "simplifiedExport", "Per level, in <project name>/simplified: data.json (level, fields, entities), layer PNGs, a merged PNG, IntGrid CSVs", "project.exports")
			if prop_bool("Tiled export", "defs.project.tiled", root, "exportTiled", "A Tiled map (.tmx) per level and a .world file, in <project name>/tiled (one grid size; for engines that only read Tiled)", "project.exports") {
				if e.LdtkJson_Bool(root, "exportTiled") do Editor_Log(state, .Info, "Tiled export: only for engines that just read Tiled files; some features (several grid sizes, off-grid tiles) don't exist there")
			}
			UI_PropLabel("")
			if UI_Button(fmt.tprintf("%s  Export now", ICON_FA_FILE_EXPORT), "defs.project.exportnow") {
				r := e.Ldtk_Doc_RunExports(doc)
				Editor_Log(state, .Info, "Exported %d file(s)", r.files)
				for err in r.errors do Editor_Log(state, .Warn, "Export: %s", err)
				Editor_InvalidateProjectFiles()
			}
			level_tip("Run the exports now (they also run on each save)", "project.exports")
			imgui.SameLine()
			if UI_Button(fmt.tprintf("%s  Open folder", ICON_FA_FOLDER_OPEN), "defs.project.openexports") {
				dir := e.Ldtk_Doc_ExternalDir(doc)
				_ = os.make_directory_all(dir)
				Editor_OpenExternally(state, dir)
			}
			level_tip("Show the <project name> folder", "project.exports")
			UI_EndProps()
		}
		if UI_SectionHeader("Custom commands", false) {
			cmds := e.LdtkJson_Get(root, "customCommands")
			UI_DimText("Commands run in the project's folder (" + CMD + "+R runs the manual ones).")
			if cmds != nil && cmds.kind == .Array {
				for c, i in cmds.items {
					imgui.PushIDInt(i32(i))
					buf: [512]u8
					copy(buf[:511], e.LdtkJson_Str(c, "command"))
					imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x - 210)
					if imgui.InputTextWithHint("##cmd", "command and arguments", cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue}) || imgui.IsItemDeactivatedAfterEdit() {
						defs_checkpoint("Custom Command")
						e.LdtkJson_SetStr(c, "command", string(cstring(raw_data(buf[:]))), a)
						e.Ldtk_Doc_Touch(doc)
					}
					Drive_Item(fmt.tprintf("defs.command:%d", i))
					level_tip("The command (quotes group arguments; Enter applies). Right-click for more.", "project.commands")
					if imgui.BeginPopupContextItem("##cmdctx") {
						moved := false
						if ctx_item(ICON_FA_ARROW_UP, "Move up", "Run earlier", i > 0) {
							defs_checkpoint("Move Custom Command")
							cmds.items[i], cmds.items[i - 1] = cmds.items[i - 1], cmds.items[i]
							e.Ldtk_Doc_Touch(doc)
							moved = true
						}
						if ctx_item(ICON_FA_ARROW_DOWN, "Move down", "Run later", i + 1 < len(cmds.items)) {
							defs_checkpoint("Move Custom Command")
							cmds.items[i], cmds.items[i + 1] = cmds.items[i + 1], cmds.items[i]
							e.Ldtk_Doc_Touch(doc)
							moved = true
						}
						if ctx_item(ICON_FA_TRASH, "Remove", "Remove the command") {
							defs_checkpoint("Remove Custom Command")
							ordered_remove(&cmds.items, i)
							e.Ldtk_Doc_Touch(doc)
							moved = true
						}
						imgui.Separator()
						if ctx_item(ICON_FA_CIRCLE_QUESTION, "Help", "Custom commands in the reference") do LevelRef_Open("project.commands")
						imgui.EndPopup()
						if moved {
							imgui.PopID()
							break
						}
					}
					imgui.SameLine()
					imgui.SetNextItemWidth(140)
					cur := 0
					for w, k in LDTK_COMMAND_WHEN do if w == e.LdtkJson_Str(c, "when", "Manual") do cur = k
					if pick, ch := UI_Combo(fmt.tprintf("defs.command.when:%d", i), cur, LDTK_COMMAND_WHEN_LABELS[:]); ch {
						defs_checkpoint("Custom Command")
						e.LdtkJson_SetStr(c, "when", LDTK_COMMAND_WHEN[pick], a)
						e.Ldtk_Doc_Touch(doc)
					}
					level_tip("When it runs", "project.commands")
					imgui.SameLine()
					if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("defs.command.remove:%d", i), "", false, 24) {
						defs_checkpoint("Remove Custom Command")
						ordered_remove(&cmds.items, i)
						e.Ldtk_Doc_Touch(doc)
						imgui.PopID()
						break
					}
					level_tip("Remove the command", "project.commands")
					imgui.PopID()
				}
			}
			if UI_Button(fmt.tprintf("%s  Command", ICON_FA_PLUS), "defs.command.add") {
				defs_checkpoint("Add Custom Command")
				if cmds == nil || cmds.kind != .Array {
					cmds = e.LdtkJson_New(.Array, a)
					e.LdtkJson_Set(root, "customCommands", cmds, a)
				}
				o := e.LdtkJson_New(.Object, a)
				e.LdtkJson_Set(o, "command", e.LdtkJson_NewString("", a), a)
				e.LdtkJson_Set(o, "when", e.LdtkJson_NewString("Manual", a), a)
				append(&cmds.items, o)
				e.Ldtk_Doc_Touch(doc)
			}
			level_tip("A new command", "project.commands")
			imgui.SameLine()
			if UI_Button(fmt.tprintf("%s  Run manual", ICON_FA_PLAY), "defs.command.run") do LevelCommands_Run(state, "Manual")
			level_tip("Run the manual commands now (" + CMD + "+R)", "project.commands")
			iid := e.LdtkJson_Str(root, "iid")
			if t, known := GlobalSettings.ldtkTrust[iid]; known {
				imgui.SameLine()
				UI_DimText(t ? "(allowed)" : "(blocked)")
				imgui.SameLine()
				if UI_Button("Reset trust", "defs.command.resettrust") {
					for k in GlobalSettings.ldtkTrust do if k == iid {
						delete_key(&GlobalSettings.ldtkTrust, k)
						delete(k)
						break
					}
					Editor_SaveSettings()
				}
				level_tip("Ask again before running this project's commands", "project.commands")
			}
		}
		if UI_SectionHeader("Names") && UI_BeginProps("##proj_names") {
			UI_PropLabel("Identifier style")
			style := e.Ldtk_Doc_IdentifierStyle(doc)
			labels := []string{"Capitalize: My_identifier_1", "Uppercase: MY_IDENTIFIER_1", "Lowercase: my_identifier_1", "Free: my_IdEnTiFiEr_1"}
			if pick, ch := UI_Combo("defs.project.style", int(style), labels); ch && e.Ldtk_IdentifierStyle(pick) != style {
				lp.styleReq = true
				lp.styleTo = e.Ldtk_IdentifierStyle(pick)
			}
			level_tip("How identifiers are written; changing it converts every identifier (asks first)", "project.names")
			UI_PropLabel("Level names")
			if name, ok := defs_text_edit("defs.project.levelnames", root, "levelNamePattern"); ok {
				defs_checkpoint("Level Names")
				e.LdtkJson_SetStr(root, "levelNamePattern", name != "" ? name : "Level_%idx", a)
				e.Ldtk_Doc_Touch(doc)
			}
			level_tip("Levels' automatic names: %idx / %idx1 (index in the world), %world, %depth, %x / %y (position), %gx / %gy (GridVania cell)", "project.names")
			UI_EndProps()
		}
		if UI_SectionHeader("Defaults") && UI_BeginProps("##proj_defaults") {
			UI_PropLabel("Grid size")
			g := i32(e.LdtkJson_Int(root, "defaultGridSize", 16))
			if (imgui.InputInt("##pgrid", &g, 1, 8) || imgui.IsItemDeactivatedAfterEdit()) && g > 0 {
				defs_checkpoint("Default Grid")
				e.LdtkJson_SetInt(root, "defaultGridSize", int(clamp(g, 1, 1024)), a)
				e.Ldtk_Doc_Touch(doc)
			}
			Drive_Item("defs.project.grid")
			level_tip("The grid of new layers", "project.defaults")
			UI_PropLabel("Entity size")
			es := [2]i32{i32(e.LdtkJson_Int(root, "defaultEntityWidth", 16)), i32(e.LdtkJson_Int(root, "defaultEntityHeight", 16))}
			if project_pair("defs.project.entitysize", &es) && es.x > 0 && es.y > 0 {
				defs_checkpoint("Default Entity Size")
				e.LdtkJson_SetInt(root, "defaultEntityWidth", int(es.x), a)
				e.LdtkJson_SetInt(root, "defaultEntityHeight", int(es.y), a)
				e.Ldtk_Doc_Touch(doc)
			}
			level_tip("The size of new entities (width, height; Enter applies)", "project.defaults")
			UI_PropLabel("Entity pivot")
			pv := [2]f64{e.LdtkJson_Float(root, "defaultPivotX"), e.LdtkJson_Float(root, "defaultPivotY")}
			if p, ch := level_pivot_picker("defs.project.pivot", pv, "The pivot of new entities", "project.defaults"); ch {
				defs_checkpoint("Default Pivot")
				e.LdtkJson_SetFloat(root, "defaultPivotX", p.x, a)
				e.LdtkJson_SetFloat(root, "defaultPivotY", p.y, a)
				e.Ldtk_Doc_Touch(doc)
			}
			project_colour("Workspace", "bgColor", "#40465B", "The canvas background around the levels")
			project_colour("Level background", "defaultLevelBgColor", "#696A79", "The background of levels without their own colour")
			UI_EndProps()
		}
		if UI_SectionHeader("Advanced", false) {
			for f in e.LDTK_PROJECT_FLAGS {
				on := e.Ldtk_Doc_HasFlag(doc, f.name)
				if imgui.Checkbox(fmt.ctprintf("%s##%s", f.label, f.name), &on) {
					if f.name == "MultiWorlds" && !on && len(doc.worlds) > 1 {
						Editor_Log(state, .Warn, "Delete the other worlds first")
					} else {
						defs_checkpoint(f.label)
						e.Ldtk_Doc_SetProjectFlag(doc, f.name, on)
					}
				}
				Drive_Item(fmt.tprintf("defs.project.flag:%s", f.name))
				level_tip(f.desc, "project.flags")
				imgui.Indent(28)
				imgui.PushTextWrapPos(0)
				UI_DimText(f.desc)
				imgui.PopTextWrapPos()
				imgui.Unindent(28)
			}
		}
		if UI_SectionHeader("Description", false) {
			// the project's notes (LDtk's tutorialDesc)
			if lp.descFor != rawptr(doc) {
				lp.descFor = rawptr(doc)
				lp.descBuf = {}
				copy(lp.descBuf[:len(lp.descBuf) - 1], e.LdtkJson_Str(root, "tutorialDesc"))
			}
			imgui.InputTextMultiline("##desc", cstring(raw_data(lp.descBuf[:])), len(lp.descBuf), {-1, 90}, {})
			Drive_Item("defs.project.desc")
			level_tip("Notes about the project, saved in it", PROJECT_TOPIC)
			if imgui.IsItemDeactivatedAfterEdit() {
				text := string(cstring(raw_data(lp.descBuf[:])))
				defs_checkpoint("Project Description")
				if text == "" do e.LdtkJson_SetNull(root, "tutorialDesc", a)
				else do e.LdtkJson_SetStr(root, "tutorialDesc", text, a)
				e.Ldtk_Doc_Touch(doc)
			}
		}
	}
	imgui.EndChild()
	imgui.SameLine(0, 8)
	if imgui.BeginChild("##project_fields", {0, avail.y}, {}, {}) do LevelDefs_FieldsPanel(state, -1)
	imgui.EndChild()
	style_popup(state)
}

@(private = "file")
project_pair :: proc(id: string, v: ^[2]i32) -> bool {
	w := (imgui.GetContentRegionAvail().x - 4) * 0.5
	imgui.SetNextItemWidth(w)
	a := imgui.InputInt(fmt.ctprintf("##%s.x", id), &v.x, 0, 0) || imgui.IsItemDeactivatedAfterEdit()
	Drive_Item(fmt.tprintf("%s.x", id))
	imgui.SameLine(0, 4)
	imgui.SetNextItemWidth(w)
	b := imgui.InputInt(fmt.ctprintf("##%s.y", id), &v.y, 0, 0) || imgui.IsItemDeactivatedAfterEdit()
	Drive_Item(fmt.tprintf("%s.y", id))
	return a || b
}

@(private = "file")
project_colour :: proc(label, key, def, tip: string) {
	doc := GlobalLevel.doc
	UI_PropLabel(label)
	c := e.Ldtk_ParseHexColor(e.LdtkJson_Str(doc.root, key, def))
	col := [3]f32{f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255}
	if imgui.ColorEdit3(fmt.ctprintf("##%s", key), &col, {.NoInputs}) {
		e.Ldtk_Doc_CheckpointOnce(doc, -1, label, rawptr(raw_data(key)))
		hex := e.Ldtk_ColorHex({u8(col[0] * 255 + 0.5), u8(col[1] * 255 + 0.5), u8(col[2] * 255 + 0.5), 255})
		e.LdtkJson_SetStr(doc.root, key, hex, doc.allocator)
		if key == "defaultLevelBgColor" {
			// levels using the default follow
			for &lv, li in doc.levels do if e.LdtkJson_IsNull(lv.obj, "bgColor") do e.Ldtk_Doc_SetLevelBgColor(doc, li, "")
		}
		e.Ldtk_Doc_Touch(doc)
	}
	if imgui.IsItemDeactivated() do e.Ldtk_Doc_EndCoalesce(doc)
	level_tip(tip, "project.defaults")
}

// project_set_extension renames the project file (.ldtk <-> .json).
@(private = "file")
project_set_extension :: proc(state: ^EditorState, ext: string) {
	L := &GlobalLevel
	doc := L.doc
	old := doc.path
	if filepath.ext(old) == ext do return
	next := fmt.tprintf("%s%s", strings.trim_suffix(old, filepath.ext(old)), ext)
	if os.exists(next) {
		Editor_Log(state, .Warn, "%s already exists", filepath.base(next))
		return
	}
	if !e.Ldtk_Doc_Save(doc, next) {
		Editor_Log(state, .Error, "Could not write %s", filepath.base(next))
		return
	}
	_ = os.remove(old)
	nrel := fmt.tprintf("%s%s", strings.trim_suffix(L.rel, filepath.ext(L.rel)), ext)
	delete(L.rel)
	L.rel = strings.clone(nrel)
	Editor_InvalidateProjectFiles()
	Editor_Log(state, .Info, "The project file is now %s", filepath.base(next))
}

@(private = "file")
style_popup :: proc(state: ^EditorState) {
	doc := GlobalLevel.doc
	if lp.styleReq {
		lp.styleReq = false
		imgui.OpenPopup("Identifier Style###LevelIdStyle")
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if !imgui.BeginPopupModal("Identifier Style###LevelIdStyle", nil, {.AlwaysAutoResize}) do return
	defer imgui.EndPopup()
	UI_DimText("Make sure the game and importers you use support this style.")
	if lp.styleTo != .Free do UI_DimText("Every identifier of the project is converted to it (undo brings them back).")
	if UI_PrimaryButton("Convert", "style.ok") {
		defs_checkpoint("Identifier Style")
		e.Ldtk_Doc_SetIdentifierStyle(doc, lp.styleTo)
		level_after_defs()
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Cancel", "style.cancel") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
	level_tip("Close without changing anything", "tab.project")
}
