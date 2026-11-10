package editor

import "core:fmt"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Main menu bar. Every menu and item registers a test-drive id
// ("menu:File", "menu:File/Save Scene").
// ============================================================================

@(private = "file")
menuCurrent: cstring

@(private = "file")
menu_begin :: proc(name: cstring) -> bool {
	open := imgui.BeginMenu(name)
	Drive_Item(fmt.tprintf("menu:%s", name))
	if open do menuCurrent = name
	return open
}

@(private = "file")
menu_item :: proc(label: cstring, shortcut: cstring = nil, selected := false, enabled := true) -> bool {
	r := imgui.MenuItem(label, shortcut, selected, enabled)
	Drive_Item(fmt.tprintf("menu:%s/%s", menuCurrent, label))
	return r
}

// menu_action draws an action's menu item (label/shortcut/check/enabled
// from the action table).
@(private = "file")
menu_action :: proc(state: ^EditorState, id: string, label: string = "") {
	a := Action_Find(id)
	if a == nil do return
	text := label if label != "" else a.label
	Actions_MenuItem(state, id, text)
	Drive_Item(fmt.tprintf("menu:%s/%s", menuCurrent, text))
}

MainMenu_Render :: proc(state: ^EditorState) -> f32 {
	menuBarH: f32 = 0.0
	imgui.PushStyleVarImVec2(.FramePadding, {10, 7})
	imgui.PushStyleVarImVec2(.ItemSpacing, {10, 8})
	defer imgui.PopStyleVar(2)

	if !imgui.BeginMainMenuBar() do return menuBarH
	menuBarH = imgui.GetFrameHeight()

	if menu_begin("File") {
		menu_action(state, "scene.new")
		menu_action(state, "code.new_script")
		menu_action(state, "file.new_project")
		imgui.Separator()
		menu_action(state, "file.open_project")
		recentOpen := imgui.BeginMenu("Open Recent", len(GlobalSettings.recentProjects) > 0)
		Drive_Item("menu:File/Open Recent")
		if recentOpen {
			for r in GlobalSettings.recentProjects {
				if imgui.MenuItem(strings.clone_to_cstring(r, context.temp_allocator)) do Editor_SwitchProject(state, r)
			}
			imgui.EndMenu()
		}
		menu_action(state, "palette.files", "Open File...")
		imgui.Separator()
		menu_action(state, "file.save")
		menu_action(state, "file.save_as")
		menu_action(state, "file.save_all")
		menu_action(state, "file.revert")
		imgui.Separator()
		exportOpen := imgui.BeginMenu("Export")
		Drive_Item("menu:File/Export")
		if exportOpen {
			menuCurrent = "Export"
			menu_action(state, "file.export", ".rayzr Package")
			menu_action(state, "file.export_standalone", "Standalone Game")
			menu_action(state, "file.open_web_export", "Open Web Export in Browser")
			menuCurrent = "File"
			imgui.EndMenu()
		}
		imgui.Separator()
		menu_action(state, "file.settings")
		imgui.Separator()
		menu_action(state, "file.quit")
		PluginAPI_MenuItems(state, "File") // plugin commands placed here (plugin_api.odin)
		imgui.EndMenu()
	}

	if menu_begin("Edit") {
		menu_action(state, "edit.undo")
		menu_action(state, "edit.redo")
		imgui.Separator()
		menu_action(state, "node.cut")
		menu_action(state, "node.copy")
		menu_action(state, "node.paste")
		menu_action(state, "node.duplicate")
		menu_action(state, "node.delete")
		menu_action(state, "node.rename")
		menu_action(state, "node.lock")
		menu_action(state, "node.editor_hide")
		imgui.Separator()
		menu_action(state, "node.add")
		menu_action(state, "node.select_all")
		menu_action(state, "node.deselect")
		imgui.Separator()
		alignOpen := imgui.BeginMenu("Align")
		Drive_Item("menu:Edit/Align")
		if alignOpen {
			for id in ([]string{"align.left", "align.center_x", "align.right", "align.top", "align.center_y", "align.bottom", "align.distribute_x", "align.distribute_y"}) {
				a := Action_Find(id)
				if Actions_MenuItem(state, id) {}
				Drive_Item(fmt.tprintf("menu:Align/%s", a.label))
			}
			imgui.EndMenu()
		}
		PluginAPI_MenuItems(state, "Edit") // plugin commands placed here (plugin_api.odin)
		imgui.EndMenu()
	}

	if menu_begin("View") {
		menu_action(state, "palette.commands")
		imgui.Separator()
		menu_action(state, "view.grid", "Grid")
		menu_action(state, "view.bounds", "Bounds & Colliders")
		menu_action(state, "view.camera_frames", "Camera Frames")
		menu_action(state, "view.colliders")
		menu_action(state, "view.rulers")
		menu_action(state, "view.clear_guides")
		menu_action(state, "view.inspector_help")
		menu_action(state, "view.file_browser")
		imgui.Separator()
		menu_action(state, "view.vision_protanopia")
		menu_action(state, "view.vision_deuteranopia")
		menu_action(state, "view.vision_tritanopia")
		imgui.Separator()
		menu_action(state, "view.snap_grid")
		menu_action(state, "view.snap_rotation")
		menu_action(state, "view.smart_snap")
		imgui.Separator()
		menu_action(state, "view.frame")
		menu_action(state, "view.zoom_in")
		menu_action(state, "view.zoom_out")
		menu_action(state, "view.reset_zoom")
		menu_action(state, "view.fit_scene")
		menu_action(state, "view.fit_game")
		menu_action(state, "view.fit_selection")
		imgui.Separator()
		menu_action(state, "view.viewport")
		menu_action(state, "view.code")
		menu_action(state, "view.console")
		BottomPanel_ViewMenu(state)
		imgui.Separator()
		wsOpen := imgui.BeginMenu(fmt.ctprintf("Workspaces (%s)", currentWorkspace))
		Drive_Item("menu:View/Workspaces")
		if wsOpen {
			for p in Layout_Preset {
				if imgui.MenuItem(fmt.ctprintf("%s", LAYOUT_PRESET_NAMES[p]), nil, currentWorkspace == LAYOUT_PRESET_NAMES[p]) do Workspace_RequestPreset(p)
				Drive_Item(fmt.tprintf("menu:Workspaces/%s", LAYOUT_PRESET_NAMES[p]))
			}
			saved := Workspace_List(state)
			if len(saved) > 0 do imgui.Separator()
			for name in saved {
				if imgui.MenuItem(fmt.ctprintf("%s", name), nil, currentWorkspace == name) do Workspace_Load(state, name)
				Drive_Item(fmt.tprintf("menu:Workspaces/%s", name))
			}
			imgui.Separator()
			if imgui.MenuItem("Save Workspace As...") do Prompt_Open(.SaveWorkspace, currentWorkspace)
			Drive_Item("menu:Workspaces/Save Workspace As...")
			if len(saved) > 0 && imgui.BeginMenu("Delete Workspace") {
				for name in saved {
					if imgui.MenuItem(fmt.ctprintf("%s", name)) do Workspace_Delete(state, name)
				}
				imgui.EndMenu()
			}
			imgui.EndMenu()
		}
		menu_action(state, "view.tab_bars")
		if menu_item("Reset Layout") {
			Workspace_RequestPreset(.Default)
			Editor_Log(state, .Info, "Layout reset")
		}
		PluginPanels_ViewMenu(state) // View > Plugins: their panels
		PluginAPI_MenuItems(state, "View") // plugin commands placed here (plugin_api.odin)
		imgui.EndMenu()
	}

	if menu_begin("Tools") {
		menu_action(state, "tool.select", "Select")
		menu_action(state, "tool.move", "Move")
		menu_action(state, "tool.rotate", "Rotate")
		menu_action(state, "tool.scale", "Scale")
		menu_action(state, "tool.pan", "Pan")
		imgui.Separator()
		menu_action(state, "tool.sprite_slicer")
		menu_action(state, "tool.new_plugin")
		menu_action(state, "tool.format_scenes")
		PluginAPI_MenuItems(state, "Tools") // plugin commands placed here (plugin_api.odin)
		imgui.EndMenu()
	}

	if menu_begin("Game") {
		menu_action(state, "game.play")
		menu_action(state, "game.play_scene")
		menu_action(state, "game.pause", "Pause")
		menu_action(state, "game.step", "Step One Frame")
		menu_action(state, "game.restart", "Restart")
		menu_action(state, "game.stop", "Stop")
		menu_action(state, "game.colliders")
		imgui.Separator()
		menu_action(state, "game.simulate")
		imgui.Separator()
		if imgui.BeginMenu("Save Data") {
			menu_action(state, "game.save_folder", "Open Folder")
			menu_action(state, "game.delete_save", "Delete Save Files")
			imgui.EndMenu()
		}
		PluginAPI_MenuItems(state, "Game") // plugin commands placed here (plugin_api.odin)
		imgui.EndMenu()
	}

	if menu_begin("Help") {
		menu_action(state, "help.welcome")
		menu_action(state, "help.reference")
		menu_action(state, "help.editor_manual")
		PanelHelp_MenuItem(state)
		menu_action(state, "help.node_reference")
		menu_action(state, "help.level_reference")
		menu_action(state, "help.level_shortcuts")
		menu_action(state, "help.shortcuts")
		menu_action(state, "palette.commands")
		if menu_item("Check for Updates") do UpdateCheck_Start(manual = true)
		if prev, ok := Update_PreviousVersion(state); ok {
			if menu_item(fmt.ctprintf("Roll Back to %s", prev)) do Update_RequestRollback(state)
			UI_Tooltip("Restart into the version the last update replaced (kept beside the install)")
		}
		imgui.Separator()
		menu_action(state, "help.report_bug")
		menu_action(state, "help.crash_folder")
		if menu_item("About") do Editor_Log(state, .Info, "Rayzr Editor %s - third-party notices: THIRD_PARTY_NOTICES.txt in the editor's folder", e.RAYZR_RELEASE)
		PluginAPI_MenuItems(state, "Help") // plugin commands placed here (plugin_api.odin)
		imgui.EndMenu()
	}

	imgui.EndMainMenuBar()
	return menuBarH
}
