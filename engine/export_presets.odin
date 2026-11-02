package engine

import "core:encoding/json"
import "core:fmt"
import "core:path/filepath"
import "core:strings"

// ============================================================================
// Export presets (project.json "export": {"presets": [...]}): each one
// exports the game for one platform with its own settings - name, output
// folder, version, icon, window overrides, files to include / exclude, and
// a debug runner. Projects without presets get one per selected target.
// ============================================================================

Export_Toggle :: enum {
	Project, // keep the project's setting
	On,
	Off,
}

Export_Preset :: struct {
	name:           string,
	target:         Export_Target,
	executableName: string,  // "" = the project's export name
	outputDir:      string,  // "" = <export output>/<preset name>
	version:        string,  // "" = the project's
	icon:           string,  // "" = the project's
	windowTitle:    string,  // "" = the project's
	windowWidth:    int,     // 0 = the project's
	windowHeight:   int,
	fullscreen:     Export_Toggle,
	include:        [dynamic]string, // patterns; empty = everything
	exclude:        [dynamic]string,
	debug:          bool,    // the debug runner (logs, console on Windows)
	separateFiles:  bool,    // Windows / Linux: a folder (exe + game.rayzr + fonts/) instead of one file (#292)
}

Export_Preset_Destroy :: proc(p: ^Export_Preset, allocator := context.allocator) {
	for s in ([]string{p.name, p.executableName, p.outputDir, p.version, p.icon, p.windowTitle}) do if s != "" do delete(s, allocator)
	for s in p.include do delete(s, allocator)
	for s in p.exclude do delete(s, allocator)
	delete(p.include)
	delete(p.exclude)
	p^ = {}
}

Export_Preset_Clone :: proc(src: ^Export_Preset, allocator := context.allocator) -> Export_Preset {
	p := src^
	p.name = strings.clone(src.name, allocator)
	p.executableName = strings.clone(src.executableName, allocator)
	p.outputDir = strings.clone(src.outputDir, allocator)
	p.version = strings.clone(src.version, allocator)
	p.icon = strings.clone(src.icon, allocator)
	p.windowTitle = strings.clone(src.windowTitle, allocator)
	p.include = make([dynamic]string, allocator)
	p.exclude = make([dynamic]string, allocator)
	for s in src.include do append(&p.include, strings.clone(s, allocator))
	for s in src.exclude do append(&p.exclude, strings.clone(s, allocator))
	return p
}

Export_Target_Parse :: proc(s: string) -> (Export_Target, bool) {
	for t in Export_Target do if export_target_name(t) == strings.to_lower(s, context.temp_allocator) do return t, true
	return .MacOS, false
}

// --- project.json ----------------------------------------------------------------

@(private = "file")
str :: proc(o: json.Object, k: string) -> string {
	s, _ := o[k].(json.String)
	return s
}

@(private = "file")
num :: proc(o: json.Object, k: string) -> int {
	f, ok := json_number(o[k])
	return int(f) if ok else 0
}

@(private = "file")
str_list :: proc(o: json.Object, k: string, out: ^[dynamic]string, allocator := context.allocator) {
	arr, _ := o[k].(json.Array)
	for v in arr do if s, ok := v.(json.String); ok && s != "" do append(out, strings.clone(s, allocator))
}

Export_PresetsParse :: proc(exportObj: json.Object, x: ^Export_Settings, allocator := context.allocator) {
	arr, ok := exportObj["presets"].(json.Array)
	if !ok do return
	x.presets = make([dynamic]Export_Preset, allocator)
	for v in arr {
		o, isObj := v.(json.Object)
		if !isObj do continue
		t, tok := Export_Target_Parse(str(o, "target"))
		if !tok do continue
		p := Export_Preset{
			name           = strings.clone(str(o, "name") if str(o, "name") != "" else export_target_name(t), allocator),
			target         = t,
			executableName = strings.clone(str(o, "executable"), allocator),
			outputDir      = strings.clone(str(o, "output_dir"), allocator),
			version        = strings.clone(str(o, "version"), allocator),
			icon           = strings.clone(str(o, "icon"), allocator),
			windowTitle    = strings.clone(str(o, "window_title"), allocator),
			windowWidth    = num(o, "window_width"),
			windowHeight   = num(o, "window_height"),
			include        = make([dynamic]string, allocator),
			exclude        = make([dynamic]string, allocator),
		}
		if b, bok := o["debug"].(json.Boolean); bok do p.debug = bool(b)
		if b, bok := o["single_file"].(json.Boolean); bok do p.separateFiles = !bool(b)
		if b, bok := o["fullscreen"].(json.Boolean); bok do p.fullscreen = .On if b else .Off
		str_list(o, "include", &p.include, allocator)
		str_list(o, "exclude", &p.exclude, allocator)
		append(&x.presets, p)
	}
}

// Export_PresetsWrite writes `, "presets": [...]` (nothing without presets).
Export_PresetsWrite :: proc(sb: ^strings.Builder, x: ^Export_Settings) {
	if len(x.presets) == 0 do return
	w := Json_Writer{sb = sb^}
	defer sb^ = w.sb
	key :: proc(w: ^Json_Writer, k: string) {fmt.sbprintf(&w.sb, ", \"%s\": ", k)}
	strings.write_string(&w.sb, ", \"presets\": [")
	for p, i in x.presets {
		if i > 0 do strings.write_string(&w.sb, ",")
		strings.write_string(&w.sb, "\n    {\"name\": ")
		Json_String(&w, p.name)
		key(&w, "target"); Json_String(&w, export_target_name(p.target))
		if p.executableName != "" {key(&w, "executable"); Json_String(&w, p.executableName)}
		if p.outputDir != "" {key(&w, "output_dir"); Json_String(&w, p.outputDir)}
		if p.version != "" {key(&w, "version"); Json_String(&w, p.version)}
		if p.icon != "" {key(&w, "icon"); Json_String(&w, p.icon)}
		if p.windowTitle != "" {key(&w, "window_title"); Json_String(&w, p.windowTitle)}
		if p.windowWidth > 0 && p.windowHeight > 0 {
			fmt.sbprintf(&w.sb, ", \"window_width\": %d, \"window_height\": %d", p.windowWidth, p.windowHeight)
		}
		if p.fullscreen != .Project do fmt.sbprintf(&w.sb, ", \"fullscreen\": %t", p.fullscreen == .On)
		lists := [2][]string{p.include[:], p.exclude[:]}
		names := [2]string{"include", "exclude"}
		for l, k in lists {
			if len(l) == 0 do continue
			key(&w, names[k])
			strings.write_byte(&w.sb, '[')
			for s, j in l {
				if j > 0 do strings.write_string(&w.sb, ", ")
				Json_String(&w, s)
			}
			strings.write_byte(&w.sb, ']')
		}
		if p.debug do strings.write_string(&w.sb, ", \"debug\": true")
		if p.separateFiles do strings.write_string(&w.sb, ", \"single_file\": false")
		strings.write_byte(&w.sb, '}')
	}
	strings.write_string(&w.sb, "\n  ]")
}

// --- using presets -------------------------------------------------------------------

// Export_EffectivePresets: the project's presets, or one per selected
// target (this platform when none is) - allocated in the temp allocator.
Export_EffectivePresets :: proc(x: ^Export_Settings) -> []Export_Preset {
	if len(x.presets) > 0 do return x.presets[:]
	out := make([dynamic]Export_Preset, context.temp_allocator)
	targets := x.targets if x.targets != {} else {native_export_target()}
	for t in Export_Target do if t in targets do append(&out, Export_Preset{name = export_target_name(t), target = t})
	return out[:]
}

// Export_PresetConfig: the project settings with a preset's overrides (the
// project.json packaged into that export). Temp-allocated strings.
Export_PresetConfig :: proc(cfg: ^ProjectConfig, p: ^Export_Preset) -> ProjectConfig {
	c := cfg^
	if p.version != "" do c.version = p.version
	if p.icon != "" do c.icon = p.icon
	if p.windowTitle != "" do c.windowTitle = p.windowTitle
	if p.windowWidth > 0 && p.windowHeight > 0 {
		c.windowWidth = p.windowWidth
		c.windowHeight = p.windowHeight
	}
	switch p.fullscreen {
	case .Project:
	case .On:  c.fullscreen = true
	case .Off: c.fullscreen = false
	}
	return c
}

// Export_PatternMatch: does a project-relative path ("a/b.png") match a
// pattern? "dir" / "dir/" match everything under it, a pattern without
// "/" matches file names anywhere ("*.psd"), others match the whole path
// ("levels/*.ldtk").
Export_PatternMatch :: proc(pattern, path: string) -> bool {
	pat := strings.trim_space(pattern)
	if pat == "" do return false
	pat = strings.trim_prefix(pat, "./")
	if strings.has_suffix(pat, "/") || !strings.contains_any(pat, "*?[") {
		dir := strings.trim_suffix(pat, "/")
		if path == dir || strings.has_prefix(path, strings.concatenate({dir, "/"}, context.temp_allocator)) do return true
		if strings.has_suffix(pat, "/") do return false
	}
	// (Segment by segment: package paths use "/" everywhere, filepath.match
	// splits on the OS's separator - a backslash on Windows.)
	if !strings.contains(pat, "/") {
		base := path[strings.last_index_byte(path, '/') + 1:]
		ok, _ := filepath.match(pat, base)
		return ok
	}
	pats := strings.split(pat, "/", context.temp_allocator)
	parts := strings.split(path, "/", context.temp_allocator)
	if len(pats) != len(parts) do return false
	for p, i in pats {
		if ok, _ := filepath.match(p, parts[i]); !ok do return false
	}
	return true
}

// Export_PresetIncludes: whether a project file goes into the preset's
// package (project.json always does).
Export_PresetIncludes :: proc(p: ^Export_Preset, path: string) -> bool {
	if path == "project.json" do return true
	for pat in p.exclude do if Export_PatternMatch(pat, path) do return false
	if len(p.include) == 0 do return true
	for pat in p.include do if Export_PatternMatch(pat, path) do return true
	return false
}
