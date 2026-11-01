package engine

import "base:runtime"
import os "osx"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"

// ============================================================================
// Localization: string tables in the project's locale/ folder, as CSV:
//
//   key,en,fr,de
//   greeting,"Hello, {name}!","Bonjour, {name} !","Hallo, {name}!"
//   menu.start,Start,Commencer,Starten
//
// The first column is the key, the header names the languages; a text
// missing in the current language falls back to one that has it. Several files merge. Locale_Get / Lua `tr`
// look up a key in the current language ({name} placeholders filled from
// arguments); a missing text falls back to the first language, then the
// key itself. Files are re-read when they change (checked at most once a
// second), so editing a table updates a running game or the editor.
// ============================================================================

@(private = "file")
locale: struct {
	languages: [dynamic]string,          // heap
	tables:    map[string][dynamic]string, // key -> text per language (heap)
	current:   string,                   // heap; "" = the first language
	files:     map[string]time.Time,     // loaded files and their times
	checked:   time.Tick,
	loaded:    bool,
	game:      ^Game,
}

@(private = "file")
heap :: proc() -> runtime.Allocator {return Engine_HeapAllocator()}

Locale_Reset :: proc() {
	for l in locale.languages do delete(l, heap())
	delete(locale.languages)
	for k, row in locale.tables {
		delete(k, heap())
		for s in row do delete(s, heap())
		delete(row)
	}
	delete(locale.tables)
	for f in locale.files do delete(f, heap())
	delete(locale.files)
	delete(locale.current, heap())
	locale = {}
}

// Locale_ParseCSV splits CSV text into rows of fields (quotes, "" escapes,
// commas and newlines inside quotes). Temp-allocated.
Locale_ParseCSV :: proc(text: string) -> [][]string {
	rows := make([dynamic][]string, context.temp_allocator)
	row := make([dynamic]string, context.temp_allocator)
	field := strings.builder_make(context.temp_allocator)
	inQuotes := false
	i := 0
	t := strings.trim_prefix(text, "\xef\xbb\xbf") // a BOM from spreadsheet exports
	for i < len(t) {
		ch := t[i]
		if inQuotes {
			if ch == '"' {
				if i + 1 < len(t) && t[i + 1] == '"' {strings.write_byte(&field, '"'); i += 1}
				else do inQuotes = false
			} else {
				strings.write_byte(&field, ch)
			}
		} else {
			switch ch {
			case '"': inQuotes = true
			case ',':
				append(&row, strings.clone(strings.to_string(field), context.temp_allocator))
				strings.builder_reset(&field)
			case '\r':
			case '\n':
				append(&row, strings.clone(strings.to_string(field), context.temp_allocator))
				strings.builder_reset(&field)
				append(&rows, row[:])
				row = make([dynamic]string, context.temp_allocator)
			case: strings.write_byte(&field, ch)
			}
		}
		i += 1
	}
	if strings.builder_len(field) > 0 || len(row) > 0 {
		append(&row, strings.clone(strings.to_string(field), context.temp_allocator))
		append(&rows, row[:])
	}
	return rows[:]
}

// Locale_AddTable merges one CSV table.
Locale_AddTable :: proc(text: string) {
	rows := Locale_ParseCSV(text)
	if len(rows) == 0 || len(rows[0]) < 2 do return
	// Columns of this file -> language index.
	cols := make([]int, len(rows[0]), context.temp_allocator)
	for name, c in rows[0] {
		if c == 0 do continue
		lang := strings.trim_space(name)
		idx := -1
		for l, k in locale.languages do if l == lang do idx = k
		if idx < 0 {
			append(&locale.languages, strings.clone(lang, heap()))
			idx = len(locale.languages) - 1
		}
		cols[c] = idx
	}
	for r in rows[1:] {
		if len(r) == 0 do continue
		key := strings.trim_space(r[0])
		if key == "" || strings.has_prefix(key, "#") do continue
		entry, has := locale.tables[key]
		if !has {
			entry = make([dynamic]string, heap())
			locale.tables[strings.clone(key, heap())] = entry
		}
		for c in 1 ..< len(r) {
			lang := cols[c] if c < len(cols) else -1
			if lang < 0 do continue
			for len(entry) <= lang do append(&entry, "")
			if r[c] == "" do continue
			if entry[lang] != "" do delete(entry[lang], heap())
			entry[lang] = strings.clone(r[c], heap())
		}
		locale.tables[key] = entry
	}
}

// Locale_Load (re)reads every locale/*.csv of the game's project.
Locale_Load :: proc(game: ^Game) {
	cur := strings.clone(locale.current, context.temp_allocator)
	Locale_Reset()
	locale.game = game
	if cur != "" do locale.current = strings.clone(cur, heap())
	locale.loaded = true
	locale.checked = time.tick_now()
	if game == nil do return
	for rel in locale_files(game) {
		data, ok := AssetManager_ReadFileBytes(&game.assetManager, rel, context.temp_allocator)
		if !ok do continue
		Locale_AddTable(string(data))
		mt: time.Time
		if disk := AssetManager_ResolveDiskPath(&game.assetManager, rel); disk != "" {
			if info, err := os.stat(disk, context.temp_allocator); err == nil do mt = info.modification_time
		}
		locale.files[strings.clone(rel, heap())] = mt
	}
}

// locale_files: locale/*.csv in the project folder or package.
@(private = "file")
locale_files :: proc(game: ^Game) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	am := &game.assetManager
	if am.package_ != nil {
		for path in am.package_.entries do if strings.has_prefix(path, "locale/") && strings.has_suffix(strings.to_lower(path, context.temp_allocator), ".csv") do append(&out, path)
	} else if dir := AssetManager_ResolveDiskPath(am, "locale"); dir != "" {
		if infos, err := os.read_all_directory_by_path(dir, context.temp_allocator); err == nil {
			for fi in infos do if fi.type == .Regular && strings.has_suffix(strings.to_lower(fi.name, context.temp_allocator), ".csv") {
				p, _ := filepath.join({"locale", fi.name}, context.temp_allocator)
				append(&out, p)
			}
		}
	}
	slice.sort(out[:])
	return out[:]
}

@(private = "file")
locale_refresh :: proc(game: ^Game) {
	if game == nil do return
	if !locale.loaded || locale.game != game {
		Locale_Load(game)
		return
	}
	if time.tick_since(locale.checked) < time.Second do return
	locale.checked = time.tick_now()
	// A table added, removed or saved: read them again.
	files := locale_files(game)
	changed := len(files) != len(locale.files)
	for rel in files {
		old, has := locale.files[rel]
		if !has {changed = true; break}
		if disk := AssetManager_ResolveDiskPath(&game.assetManager, rel); disk != "" {
			if info, err := os.stat(disk, context.temp_allocator); err == nil && info.modification_time != old {changed = true; break}
		}
	}
	if changed do Locale_Load(game)
}

// Locale_SetLanguage: the language texts are shown in ("" = the first).
Locale_SetLanguage :: proc(lang: string) {
	delete(locale.current, heap())
	locale.current = strings.clone(lang, heap())
}

Locale_Language :: proc() -> string {
	if locale.current != "" do return locale.current
	return locale.languages[0] if len(locale.languages) > 0 else ""
}

// Locale_Languages: the languages the tables have (after a lookup / load).
Locale_Languages :: proc(game: ^Game) -> []string {
	locale_refresh(game)
	return locale.languages[:]
}

// Locale_Get: the text for a key in the current language (args fill
// {name} placeholders), the first language's, or the key.
Locale_Get :: proc(game: ^Game, key: string, args: map[string]string = nil, allocator := context.temp_allocator) -> string {
	locale_refresh(game)
	text := key
	if entry, ok := locale.tables[key]; ok {
		cur := -1
		for l, i in locale.languages do if l == Locale_Language() do cur = i
		if cur >= 0 && cur < len(entry) && entry[cur] != "" {
			text = entry[cur]
		} else {
			for s in entry do if s != "" {text = s; break} // any language that has it
		}
	}
	if len(args) == 0 || !strings.contains_rune(text, '{') do return strings.clone(text, allocator)
	sb := strings.builder_make(allocator)
	i := 0
	for i < len(text) {
		if text[i] == '{' {
			if end := strings.index_byte(text[i:], '}'); end > 0 {
				name := text[i + 1:i + end]
				if v, has := args[name]; has {
					strings.write_string(&sb, v)
					i += end + 1
					continue
				}
			}
		}
		strings.write_byte(&sb, text[i])
		i += 1
	}
	return strings.to_string(sb)
}

// --- The player's language, remembered (Locale.set) ------------------------------------

// Locale_ChoicePath: language.txt next to the save files.
Locale_ChoicePath :: proc(allocator := context.temp_allocator) -> string {
	p, _ := filepath.join({filepath.dir(Save_FilePath(), context.temp_allocator), "language.txt"}, allocator)
	return p
}

// Locale_SaveChoice remembers the language the player picked (Locale.set),
// so the game starts in it next time.
Locale_SaveChoice :: proc(lang: string) -> bool {
	path := Locale_ChoicePath()
	_ = os.make_directory_all(filepath.dir(path, context.temp_allocator))
	return os.write_entire_file(path, transmute([]u8)lang) == nil
}

// Locale_LoadChoice: the remembered language over the project's starting
// one (the game, not the editor); one the project no longer has is ignored.
Locale_LoadChoice :: proc(game: ^Game) -> bool {
	data, err := os.read_entire_file(Locale_ChoicePath(), context.temp_allocator)
	if err != nil do return false
	lang := strings.trim_space(string(data))
	if lang == "" do return false
	if langs := Locale_Languages(game); len(langs) > 0 && !slice.contains(langs, lang) do return false
	Locale_SetLanguage(lang)
	return true
}
