package editor

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import e "../engine"
import rl "vendor:raylib"

// ============================================================================
// New-project templates (the Welcome window; File > New Project uses Empty).
//
// Built in (made here): Empty (a camera) and Menu (a title screen whose Play
// button opens the game scene). The others are complete small games kept as
// project folders - templates/<id>/ in the editor's resources (the repo's
// templates/, built by scripts/templates/make_templates.py): Platformer,
// Top-down RPG, Shoot 'em up, Puzzle, Visual Novel, Isometric Dungeon, Hex
// Island, each with a template.json (name,
// description, icon, order) and a preview.png. Templates installed from the
// registry (#296) are listed too, from the user's templates folder. Samples are bigger projects
// to look at (the Asteroids demo).
// ============================================================================

Project_Template :: enum {
	Empty,
	Menu,
}

Template_Info :: struct {
	name, icon, description: string,
}

PROJECT_TEMPLATES := [Project_Template]Template_Info {
	.Empty = {"Empty", ICON_FA_FILE, "A scene with a camera."},
	.Menu  = {"Menu", ICON_FA_HAND_POINTER, "A title screen whose Play button opens the game scene."},
}

// Template_Entry: one choice in the Welcome window.
Template_Entry :: struct {
	name, icon, description: string,
	order:   int,
	builtin: Project_Template, // dir == "": made by Project_CreateFromTemplate
	dir:     string,           // a template / sample folder (copied)
	preview: string,           // its preview.png ("" = none)
	sample:  bool,
}

// Templates_List: the built-in templates, then the template folders (by
// order), then the samples (temp).
Templates_List :: proc() -> []Template_Entry {
	out := make([dynamic]Template_Entry, context.temp_allocator)
	for t in Project_Template {
		info := PROJECT_TEMPLATES[t]
		append(&out, Template_Entry{name = info.name, icon = info.icon, description = info.description, order = -10 + int(t), builtin = t})
	}
	// The editor's own templates, then the ones installed from the registry
	// (Tools > Registry: the user's templates folder).
	for root in ([]string{Resource_Path("templates"), Registry_TemplateRoot()}) {
		infos, err := os.read_all_directory_by_path(root, context.temp_allocator)
		if err != nil do continue
		for fi in infos {
			if fi.type != .Directory || strings.has_prefix(fi.name, ".") do continue
			dir, _ := filepath.join({root, fi.name}, context.temp_allocator)
			meta, _ := filepath.join({dir, "template.json"}, context.temp_allocator)
			data, rerr := os.read_entire_file(meta, context.temp_allocator)
			if rerr != nil do continue
			v, jerr := json.parse(data, allocator = context.temp_allocator)
			if jerr != nil do continue
			o, ok := v.(json.Object)
			if !ok do continue
			e := Template_Entry{dir = dir}
			e.name, _ = o["name"].(json.String)
			e.description, _ = o["description"].(json.String)
			if f, isNum := o["order"].(json.Float); isNum do e.order = int(f)
			e.sample = (o["kind"].(json.String) or_else "") == "sample"
			icon, _ := o["icon"].(json.String)
			e.icon = template_icon(icon)
			pv, _ := filepath.join({dir, "preview.png"}, context.temp_allocator)
			if os.is_file(pv) do e.preview = pv
			if e.name == "" do e.name = fi.name
			append(&out, e)
		}
	}
	// The demo project: a sample (the repo's own in a checkout).
	demo := "assets/demo_project" if Resources_InCheckout() else Resource_Path("templates", "demo_project")
	if os.is_dir(demo) {
		pv, _ := filepath.join({demo, "preview.png"}, context.temp_allocator)
		append(&out, Template_Entry{name = "Asteroids (sample)", icon = ICON_FA_ROCKET, order = 100, dir = demo, sample = true,
			description = "The demo: a space shooter using most of the engine - physics, particles, lighting, state machines, components, scripts.",
			preview = pv if os.is_file(pv) else ""})
	}
	slice.sort_by(out[:], proc(a, b: Template_Entry) -> bool {
		if a.sample != b.sample do return !a.sample
		return a.order < b.order
	})
	return out[:]
}

@(private = "file")
template_icon :: proc(name: string) -> string {
	switch name {
	case "person-running": return ICON_FA_PERSON_RUNNING
	case "dungeon": return ICON_FA_DUNGEON
	case "jet-fighter": return ICON_FA_JET_FIGHTER
	case "puzzle-piece": return ICON_FA_PUZZLE_PIECE
	case "rocket": return ICON_FA_ROCKET
	case "gamepad": return ICON_FA_GAMEPAD
	case "book": return ICON_FA_BOOK
	case "map": return ICON_FA_MAP
	case "bezier-curve": return ICON_FA_BEZIER_CURVE
	}
	return ICON_FA_FILE
}

// Project_CreateFromEntry makes a project from a Welcome choice: a built-in
// is generated, a folder is copied (its project.json renamed). False when
// `dir` holds a project already.
Project_CreateFromEntry :: proc(dir, name: string, entry: Template_Entry) -> bool {
	if entry.dir == "" do return Project_CreateFromTemplate(dir, name, entry.builtin)
	pj, _ := filepath.join({dir, "project.json"}, context.temp_allocator)
	if os.is_file(pj) do return false
	if !template_copy(entry.dir, dir) do return false
	// The project's own name and window title.
	data, rerr := os.read_entire_file(pj, context.temp_allocator)
	if rerr != nil do return false
	cfg, ok := e.Project_ParseConfig(data, context.temp_allocator)
	if !ok do return false
	cfg.name = name
	cfg.windowTitle = name
	return e.Project_SaveConfigToFile(dir, &cfg)
}

// template_copy: the folder, without the template's own files (template.json,
// preview.png) and editor / tool leftovers (.rayzr, .editor_settings.ini).
@(private = "file")
template_copy :: proc(src, dst: string) -> bool {
	if os.make_directory_all(dst) != nil do return false
	infos, err := os.read_all_directory_by_path(src, context.temp_allocator)
	if err != nil do return false
	for fi in infos {
		switch fi.name {
		case "template.json", "preview.png", ".rayzr", ".ore", ".editor_settings.ini", ".luarc.json", ".DS_Store": continue
		}
		from, _ := filepath.join({src, fi.name}, context.temp_allocator)
		to, _ := filepath.join({dst, fi.name}, context.temp_allocator)
		if fi.type == .Directory {
			if !template_copy(from, to) do return false
		} else {
			data, rerr := os.read_entire_file(from, context.temp_allocator)
			if rerr != nil || os.write_entire_file(to, data) != nil do return false
		}
	}
	return true
}

@(private = "file")
write_text :: proc(dir, rel, text: string) -> bool {
	p, _ := filepath.join({dir, rel}, context.temp_allocator)
	_ = os.make_directory_all(filepath.dir(p, context.temp_allocator))
	return os.write_entire_file(p, transmute([]u8)text) == nil
}

// write_box_png: a placeholder image - a filled rectangle with a darker edge.
@(private = "file")
write_box_png :: proc(dir, rel: string, w, h: i32, col: rl.Color) {
	p, _ := filepath.join({dir, rel}, context.temp_allocator)
	_ = os.make_directory_all(filepath.dir(p, context.temp_allocator))
	img := rl.GenImageColor(w, h, col)
	edge := rl.Color{u8(f32(col.r) * 0.6), u8(f32(col.g) * 0.6), u8(f32(col.b) * 0.6), 255}
	rl.ImageDrawRectangleLines(&img, {0, 0, f32(w), f32(h)}, 2, edge)
	rl.ExportImage(img, strings.clone_to_cstring(p, context.temp_allocator))
	rl.UnloadImage(img)
}

@(private = "file")
CAMERA_JSON :: `{"type": "CameraNode", "name": "Camera", "position": [640, 360], "properties": {"isCurrent": true}}`

// Project_CreateFromTemplate makes a project folder (project.json, folders,
// scenes, scripts, images). False when `dir` already holds a project.
Project_CreateFromTemplate :: proc(dir, name: string, tmpl: Project_Template) -> bool {
	pj, _ := filepath.join({dir, "project.json"}, context.temp_allocator)
	if os.is_file(pj) do return false
	for sub in ([]string{"scenes", "scripts", "textures", "audio", "components", "levels"}) {
		p, _ := filepath.join({dir, sub}, context.temp_allocator)
		_ = os.make_directory_all(p)
	}
	cfg, _ := e.Project_ParseConfig(transmute([]u8)string("{}"), context.temp_allocator)
	cfg.name = name
	cfg.windowTitle = name
	cfg.initialScene = "scenes/main.scene.json"
	cfg.gravity = {0, 980}
	cfg.fill = .Expand // (new projects: no bars; older ones keep their look)
	append(&cfg.scenes, "scenes/main.scene.json")

	ok := true
	switch tmpl {
	case .Empty:
		ok = write_text(dir, "scenes/main.scene.json", fmt.tprintf(`{{"name": "main", "root": {{"type": "Node", "name": "root", "children": [%s]}}}}`, CAMERA_JSON))
	case .Menu:
		cfg.initialScene = "scenes/menu.scene.json"
		clear(&cfg.scenes)
		append(&cfg.scenes, "scenes/menu.scene.json", "scenes/main.scene.json")
		ok = write_text(dir, "scripts/play_button.lua", `---@class PlayButton
local PlayButton = {}

-- The button's "clicked" event.
function PlayButton:on_clicked()
    Scene.change_scene("main", { transition = "fade", duration = 0.4 })
end

return PlayButton
`) && write_text(dir, "scenes/menu.scene.json", fmt.tprintf(`{{"name": "menu", "background": [18, 20, 30, 255], "root": {{"type": "Node", "name": "root", "children": [
  %s,
  {{"type": "TextNode", "name": "Title", "position": [640, 260], "properties": {{"text": "%s", "fontSize": 64, "centered": true}}}},
  {{"type": "UIButtonNode", "name": "PlayButton", "position": [560, 380], "layer": 7, "properties": {{"text": "Play", "size": [160, 48]}}, "script": {{"path": "scripts/play_button.lua"}}}}
]}}}}`, CAMERA_JSON, name)) && write_text(dir, "scenes/main.scene.json", fmt.tprintf(`{{"name": "main", "root": {{"type": "Node", "name": "root", "children": [
  %s,
  {{"type": "TextNode", "name": "Hello", "position": [640, 360], "properties": {{"text": "The game starts here", "fontSize": 40, "centered": true}}}}
]}}}}`, CAMERA_JSON))
	}
	return ok && e.Project_SaveConfigToFile(dir, &cfg)
}
