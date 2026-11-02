package engine

import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Ldtk_Doc definitions: layers, IntGrid values, entities and their fields,
// enums, tilesets and auto-layer rules
//
// New definitions are written with every key LDtk writes (in its order), so
// LDtk opens the project unchanged. Changing a layer definition updates the
// layer instances of every level. Take a project undo step first
// (Ldtk_Doc_Checkpoint(doc, -1, ...)); these call Ldtk_Doc_RefreshDefs.
// ============================================================================

LDTK_EMPTY_PROJECT :: `{
	"__header__": {
		"fileType": "LDtk Project JSON",
		"app": "LDtk",
		"doc": "https://ldtk.io/json",
		"schema": "https://ldtk.io/files/JSON_SCHEMA.json",
		"appAuthor": "Sebastien 'deepnight' Benard",
		"appVersion": "1.5.3",
		"url": "https://ldtk.io"
	},
	"iid": "",
	"jsonVersion": "1.5.3",
	"appBuildId": 473702,
	"nextUid": 1,
	"identifierStyle": "Capitalize",
	"toc": [],
	"worldLayout": "Free",
	"worldGridWidth": 256,
	"worldGridHeight": 256,
	"defaultLevelWidth": 256,
	"defaultLevelHeight": 256,
	"defaultPivotX": 0,
	"defaultPivotY": 0,
	"defaultGridSize": 16,
	"defaultEntityWidth": 16,
	"defaultEntityHeight": 16,
	"bgColor": "#40465B",
	"defaultLevelBgColor": "#696A79",
	"minifyJson": false,
	"externalLevels": false,
	"exportTiled": false,
	"simplifiedExport": false,
	"imageExportMode": "None",
	"exportLevelBg": true,
	"pngFilePattern": null,
	"backupOnSave": false,
	"backupLimit": 10,
	"backupRelPath": null,
	"levelNamePattern": "Level_%idx",
	"tutorialDesc": null,
	"customCommands": [],
	"flags": [],
	"defs": { "layers": [], "entities": [], "tilesets": [], "enums": [], "externalEnums": [], "levelFields": [] },
	"levels": [],
	"worlds": [],
	"dummyWorldIid": ""
}`

// LDtk's palette for new IntGrid values / entities.
LDTK_PALETTE := [?]string{"#E4A672", "#B86F50", "#743F39", "#3F2832", "#9E2835", "#E53B44", "#FB922B", "#FFE762", "#63C64D", "#327345", "#193D3F", "#4F6781", "#AFBFD2", "#FFFFFF", "#2CE8F4", "#0484D1"}

// Ldtk_Doc_New makes an empty project (one level, an IntGrid "Collisions"
// layer with a "walls" value and an "Entities" layer); save it with
// Ldtk_Doc_Save.
Ldtk_Doc_New :: proc(path: string, heap := context.allocator) -> (^Ldtk_Doc, bool) {
	text, _ := strings.replace(LDTK_EMPTY_PROJECT, `"iid": ""`, fmt.tprintf(`"iid": "%s"`, Ldtk_Doc_Iid(context.temp_allocator)), 1, context.temp_allocator)
	text, _ = strings.replace(text, `"dummyWorldIid": ""`, fmt.tprintf(`"dummyWorldIid": "%s"`, Ldtk_Doc_Iid(context.temp_allocator)), 1, context.temp_allocator)
	doc, ok := Ldtk_Doc_LoadFromMemory(text, path, heap)
	if !ok do return nil, false
	Ldtk_Doc_AddLevel(doc, 0, {0, 0})
	Ldtk_Doc_AddLayerDef(doc, .Entities, "Entities")
	col := Ldtk_Doc_AddLayerDef(doc, .IntGrid, "Collisions", 1)
	Ldtk_Doc_AddIntGridValue(doc, col, "walls")
	doc.modified = true
	return doc, true
}

// Ldtk_CleanIdentifier: an LDtk identifier (letters, digits, _; not starting
// with a digit; first letter upper case).
Ldtk_CleanIdentifier :: proc(s: string, allocator := context.temp_allocator, keepCase := false) -> string {
	b := strings.builder_make(allocator)
	for r, i in strings.trim_space(s) {
		ok := (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || r == '_' || (r >= '0' && r <= '9')
		c := ok ? r : '_'
		if i == 0 && c >= '0' && c <= '9' do strings.write_byte(&b, '_')
		strings.write_rune(&b, c)
	}
	out := strings.to_string(b)
	if out == "" do return strings.clone("Unnamed", allocator)
	if !keepCase && out[0] >= 'a' && out[0] <= 'z' {
		bytes := transmute([]u8)out
		bytes[0] -= 32
	}
	return out
}

Ldtk_IdentifierStyle :: enum u8 {
	Capitalize,
	Uppercase,
	Lowercase,
	Free,
}

LDTK_IDENTIFIER_STYLES := [Ldtk_IdentifierStyle]string {
	.Capitalize = "Capitalize",
	.Uppercase  = "Uppercase",
	.Lowercase  = "Lowercase",
	.Free       = "Free",
}

Ldtk_Doc_IdentifierStyle :: proc(doc: ^Ldtk_Doc) -> Ldtk_IdentifierStyle {
	s := LdtkJson_Str(doc.root, "identifierStyle", "Capitalize")
	for n, st in LDTK_IDENTIFIER_STYLES do if n == s do return st
	return .Capitalize
}

// Ldtk_CleanIdentifierStyle: Project.cleanupIdentifier - invalid characters
// and leading digits become "_", repeated "_" collapse, then the style.
Ldtk_CleanIdentifierStyle :: proc(s: string, style: Ldtk_IdentifierStyle, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(context.temp_allocator)
	for r in strings.trim_space(s) {
		ok := (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || r == '_' || (r >= '0' && r <= '9')
		c := ok ? r : '_'
		// collapse "_" runs
		if c == '_' && strings.builder_len(b) > 0 && strings.to_string(b)[strings.builder_len(b) - 1] == '_' do continue
		strings.write_rune(&b, c)
	}
	id := strings.to_string(b)
	if id == "" do return strings.clone("Unnamed", allocator)
	if id[0] >= '0' && id[0] <= '9' {
		// leading digits -> "_"
		k := 0
		for k < len(id) && id[k] >= '0' && id[k] <= '9' do k += 1
		id = fmt.tprintf("_%s", id[k:])
	}
	out := strings.clone(id, allocator)
	bytes := transmute([]u8)out
	switch style {
	case .Capitalize:
		for i in 0 ..< len(bytes) {
			if bytes[i] == '_' do continue
			if bytes[i] >= 'a' && bytes[i] <= 'z' do bytes[i] -= 32
			break
		}
	case .Uppercase: for &c in bytes do if c >= 'a' && c <= 'z' do c -= 32
	case .Lowercase: for &c in bytes do if c >= 'A' && c <= 'Z' do c += 32
	case .Free:
	}
	return out
}

// Ldtk_Doc_CleanIdentifier: cleanupIdentifier with the project's style.
Ldtk_Doc_CleanIdentifier :: proc(doc: ^Ldtk_Doc, s: string, allocator := context.temp_allocator) -> string {
	return Ldtk_CleanIdentifierStyle(s, Ldtk_Doc_IdentifierStyle(doc), allocator)
}

@(private = "file")
jo :: proc(a: mem.Allocator) -> ^LdtkJson {return LdtkJson_New(.Object, a)}
@(private = "file")
ja :: proc(a: mem.Allocator) -> ^LdtkJson {return LdtkJson_New(.Array, a)}
@(private = "file")
put :: proc(o: ^LdtkJson, key: string, v: ^LdtkJson, a: mem.Allocator) {
	append(&o.keys, strings.clone(key, a))
	append(&o.items, v)
}
@(private = "file")
pint :: proc(o: ^LdtkJson, key: string, v: int, a: mem.Allocator) {put(o, key, LdtkJson_NewInt(v, a), a)}
@(private = "file")
pnum :: proc(o: ^LdtkJson, key: string, v: f64, a: mem.Allocator) {put(o, key, LdtkJson_NewFloat(v, a), a)}
@(private = "file")
pstr :: proc(o: ^LdtkJson, key: string, v: string, a: mem.Allocator) {put(o, key, LdtkJson_NewString(v, a), a)}
@(private = "file")
pbool :: proc(o: ^LdtkJson, key: string, v: bool, a: mem.Allocator) {put(o, key, LdtkJson_NewBool(v, a), a)}
@(private = "file")
pnull :: proc(o: ^LdtkJson, key: string, a: mem.Allocator) {put(o, key, LdtkJson_New(.Null, a), a)}

@(private = "file")
defs_arr :: proc(doc: ^Ldtk_Doc, key: string) -> ^LdtkJson {
	defs := LdtkJson_Get(doc.root, "defs")
	if defs == nil {
		defs = jo(doc.allocator)
		LdtkJson_Set(doc.root, "defs", defs, doc.allocator)
	}
	arr := LdtkJson_Get(defs, key)
	if arr == nil || arr.kind != .Array {
		arr = ja(doc.allocator)
		LdtkJson_Set(defs, key, arr, doc.allocator)
	}
	return arr
}

// Ldtk_Doc_UniqueIdentifier: `base`, or base2, base3... unused in a defs list.
Ldtk_Doc_UniqueIdentifier :: proc(doc: ^Ldtk_Doc, list: string, base: string, allocator := context.temp_allocator) -> string {
	// Project.fixUniqueIdStr: the name, else a trailing number counts up
	// ("Wall2" -> "Wall3"), else "2", "3"... are appended
	arr := defs_arr(doc, list)
	clean := Ldtk_Doc_CleanIdentifier(doc, base)
	used :: proc(arr: ^LdtkJson, name: string) -> bool {
		for d in arr.items do if LdtkJson_Str(d, "identifier") == name do return true
		return false
	}
	if !used(arr, clean) do return strings.clone(clean, allocator)
	stem, idx := clean, 2
	end := len(clean)
	for end > 0 && clean[end - 1] >= '0' && clean[end - 1] <= '9' do end -= 1
	if end < len(clean) && end > 0 {
		n := 0
		for c in clean[end:] do n = n * 10 + int(c - '0')
		stem, idx = clean[:end], n
	}
	for _ in 0 ..< 100000 {
		name := fmt.tprintf("%s%d", stem, idx)
		if !used(arr, name) do return strings.clone(name, allocator)
		idx += 1
	}
	return strings.clone(clean, allocator)
}

LDTK_LAYER_TYPE_NAMES := [LdtkLayerType]string{
	.IntGrid   = "IntGrid",
	.Entities  = "Entities",
	.Tiles     = "Tiles",
	.AutoLayer = "AutoLayer",
}

// Ldtk_Doc_AddLayerDef adds a layer definition (on top, like LDtk) and an
// instance of it to every level; returns its uid. tilesetUid < 0: none.
Ldtk_Doc_AddLayerDef :: proc(doc: ^Ldtk_Doc, type: LdtkLayerType, identifier: string, tilesetUid := -1) -> int {
	a := doc.allocator
	uid := Ldtk_Doc_NextUid(doc)
	grid := LdtkJson_Int(doc.root, "defaultGridSize", 16)
	tn := LDTK_LAYER_TYPE_NAMES[type]
	o := jo(a)
	pstr(o, "__type", tn, a)
	pstr(o, "identifier", Ldtk_Doc_UniqueIdentifier(doc, "layers", identifier), a)
	pstr(o, "type", tn, a)
	pint(o, "uid", uid, a)
	pnull(o, "doc", a)
	pnull(o, "uiColor", a)
	pint(o, "gridSize", grid, a)
	pint(o, "guideGridWid", 0, a)
	pint(o, "guideGridHei", 0, a)
	pint(o, "displayOpacity", 1, a)
	pint(o, "inactiveOpacity", 1, a)
	pbool(o, "hideInList", false, a)
	pbool(o, "hideFieldsWhenInactive", false, a)
	pbool(o, "canSelectWhenInactive", true, a)
	pbool(o, "renderInWorldView", true, a)
	pint(o, "pxOffsetX", 0, a)
	pint(o, "pxOffsetY", 0, a)
	pint(o, "parallaxFactorX", 0, a)
	pint(o, "parallaxFactorY", 0, a)
	pbool(o, "parallaxScaling", true, a)
	put(o, "requiredTags", ja(a), a)
	put(o, "excludedTags", ja(a), a)
	pnull(o, "autoTilesKilledByOtherLayerUid", a)
	put(o, "uiFilterTags", ja(a), a)
	pbool(o, "useAsyncRender", false, a)
	put(o, "intGridValues", ja(a), a)
	put(o, "intGridValuesGroups", ja(a), a)
	put(o, "autoRuleGroups", ja(a), a)
	pnull(o, "autoSourceLayerDefUid", a)
	if tilesetUid >= 0 && type != .Entities do pint(o, "tilesetDefUid", tilesetUid, a)
	else do pnull(o, "tilesetDefUid", a)
	pint(o, "tilePivotX", 0, a)
	pint(o, "tilePivotY", 0, a)
	pnull(o, "biomeFieldUid", a)
	arr := defs_arr(doc, "layers")
	inject_at(&arr.items, 0, o)
	Ldtk_Doc_RefreshDefs(doc)
	di := Ldtk_Doc_LayerDefIndex(doc, uid)
	for &lv, li in doc.levels {
		size := Ldtk_Doc_LevelSize(doc, li)
		inst := Ldtk_Doc_NewLayerInstance(doc, &doc.layerDefs[di], LdtkJson_Int(lv.obj, "uid"), size, a)
		layers := LdtkJson_Get(lv.data, "layerInstances")
		if layers == nil || layers.kind != .Array {
			layers = ja(a)
			LdtkJson_Set(lv.data, "layerInstances", layers, a)
		}
		inject_at(&layers.items, 0, inst)
		ldtk_level_index_layers(doc, &lv)
		lv.dirty = true
	}
	Ldtk_Doc_Touch(doc)
	return uid
}

// Ldtk_Doc_RemoveLayerDef removes a layer definition and its instances.
Ldtk_Doc_RemoveLayerDef :: proc(doc: ^Ldtk_Doc, uid: int) -> bool {
	arr := defs_arr(doc, "layers")
	found := false
	for d, i in arr.items do if LdtkJson_Int(d, "uid", -1) == uid {
		ordered_remove(&arr.items, i)
		found = true
		break
	}
	if !found do return false
	// references from other layers
	for d in arr.items {
		for key in ([]string{"autoSourceLayerDefUid", "autoTilesKilledByOtherLayerUid"}) {
			if LdtkJson_Int(d, key, -1) == uid do LdtkJson_SetNull(d, key, doc.allocator)
		}
	}
	for &lv in doc.levels {
		layers := LdtkJson_Get(lv.data, "layerInstances")
		if layers == nil do continue
		for inst, i in layers.items do if LdtkJson_Int(inst, "layerDefUid", -1) == uid {
			ordered_remove(&layers.items, i)
			break
		}
		lv.dirty = true
	}
	Ldtk_Doc_RefreshDefs(doc)
	for &lv in doc.levels do ldtk_level_index_layers(doc, &lv)
	for &lv in doc.levels do for &ly in lv.layers do ly.cellsDirty, ly.autoDirty = true, true
	Ldtk_Doc_Touch(doc)
	return true
}

// Ldtk_Doc_MoveLayerDef moves a layer up (delta < 0, drawn above) or down,
// in the definitions and every level.
Ldtk_Doc_MoveLayerDef :: proc(doc: ^Ldtk_Doc, uid: int, delta: int) -> bool {
	move :: proc(arr: ^LdtkJson, key: string, uid, delta: int) -> bool {
		if arr == nil do return false
		for d, i in arr.items do if LdtkJson_Int(d, key, -1) == uid {
			j := i + delta
			if j < 0 || j >= len(arr.items) do return false
			arr.items[i], arr.items[j] = arr.items[j], arr.items[i]
			return true
		}
		return false
	}
	if !move(defs_arr(doc, "layers"), "uid", uid, delta) do return false
	for &lv in doc.levels {
		move(LdtkJson_Get(lv.data, "layerInstances"), "layerDefUid", uid, delta)
		ldtk_level_index_layers(doc, &lv)
		for &ly in lv.layers do ly.cellsDirty, ly.autoDirty = true, true
		lv.dirty = true
	}
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_Touch(doc)
	return true
}

// Ldtk_Doc_RenameLayerDef renames a layer def and its instances' cache.
Ldtk_Doc_RenameLayerDef :: proc(doc: ^Ldtk_Doc, uid: int, name: string) {
	a := doc.allocator
	clean := Ldtk_Doc_CleanIdentifier(doc, name)
	for d in defs_arr(doc, "layers").items do if LdtkJson_Int(d, "uid", -1) == uid do LdtkJson_SetStr(d, "identifier", clean, a)
	for &lv in doc.levels {
		for &ly in lv.layers do if LdtkJson_Int(ly.obj, "layerDefUid", -1) == uid do LdtkJson_SetStr(ly.obj, "__identifier", clean, a)
		lv.dirty = true
	}
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_LayerDefChanged re-syncs the level instances after a layer def
// edit (grid size, offsets, tileset, opacity, rule source) and regenerates
// auto tiles.
Ldtk_Doc_LayerDefChanged :: proc(doc: ^Ldtk_Doc, uid: int) {
	a := doc.allocator
	Ldtk_Doc_RefreshDefs(doc)
	di := Ldtk_Doc_LayerDefIndex(doc, uid)
	if di < 0 do return
	d := &doc.layerDefs[di]
	ts := Ldtk_Doc_Tileset(doc, d.tilesetUid)
	for &lv, li in doc.levels {
		for &ly in lv.layers {
			if LdtkJson_Int(ly.obj, "layerDefUid", -1) != uid do continue
			LdtkJson_SetStr(ly.obj, "__identifier", d.identifier, a)
			LdtkJson_SetInt(ly.obj, "__gridSize", d.gridSize, a)
			LdtkJson_SetFloat(ly.obj, "__opacity", f64(d.opacity), a)
			LdtkJson_SetInt(ly.obj, "__pxTotalOffsetX", LdtkJson_Int(ly.obj, "pxOffsetX") + d.pxOffset.x, a)
			LdtkJson_SetInt(ly.obj, "__pxTotalOffsetY", LdtkJson_Int(ly.obj, "pxOffsetY") + d.pxOffset.y, a)
			if LdtkJson_IsNull(ly.obj, "overrideTilesetUid") {
				if ts != nil {
					LdtkJson_SetInt(ly.obj, "__tilesetDefUid", ts.uid, a)
					LdtkJson_SetStr(ly.obj, "__tilesetRelPath", ts.relPath, a)
				} else {
					LdtkJson_SetNull(ly.obj, "__tilesetDefUid", a)
					LdtkJson_SetNull(ly.obj, "__tilesetRelPath", a)
				}
			}
			size := Ldtk_Doc_LevelSize(doc, li)
			off := Ldtk_Doc_LayerOffset(&ly)
			cw := max(int(ldtk_ceil_div(size.x - off.x, d.gridSize)), 0)
			ch := max(int(ldtk_ceil_div(size.y - off.y, d.gridSize)), 0)
			if cw != ly.cWid || ch != ly.cHei {
				// a new grid: cells can't keep their meaning, start empty
				delete(ly.intGrid, doc.heap)
				ly.intGrid = make([]i32, cw * ch, doc.heap)
				clear(&ly.gridTiles)
				ly.cWid, ly.cHei = cw, ch
				LdtkJson_SetInt(ly.obj, "__cWid", cw, a)
				LdtkJson_SetInt(ly.obj, "__cHei", ch, a)
			} else {
				// tiles: source rectangles follow the (new) tileset
				for &t in ly.gridTiles do t.src = Ldtk_Doc_TileSrc(Ldtk_Doc_LayerTileset(doc, &ly), int(t.t))
			}
			ly.cellsDirty = true
			lv.dirty = true
		}
	}
	Ldtk_Doc_ApplyRulesFull(doc, -1)
	Ldtk_Doc_Touch(doc)
}

@(private = "file")
ldtk_ceil_div :: proc(a, b: int) -> int {
	if b <= 0 do return 0
	if a <= 0 do return 0
	return (a + b - 1) / b
}

// Ldtk_Doc_AddIntGridValue adds the next value to an IntGrid layer.
Ldtk_Doc_AddIntGridValue :: proc(doc: ^Ldtk_Doc, layerUid: int, identifier := "") -> int {
	a := doc.allocator
	di := Ldtk_Doc_LayerDefIndex(doc, layerUid)
	if di < 0 do return -1
	d := doc.layerDefs[di].obj
	vals := LdtkJson_Get(d, "intGridValues")
	next := 1
	for v in vals.items do next = max(next, LdtkJson_Int(v, "value") + 1)
	o := jo(a)
	pint(o, "value", next, a)
	if identifier != "" do pstr(o, "identifier", identifier, a)
	else do pnull(o, "identifier", a)
	pstr(o, "color", LDTK_PALETTE[(next - 1) % len(LDTK_PALETTE)], a)
	pnull(o, "tile", a)
	pint(o, "groupUid", 0, a)
	append(&vals.items, o)
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_Touch(doc)
	return next
}

// Ldtk_Doc_RemoveIntGridValue removes a value and clears its cells.
Ldtk_Doc_RemoveIntGridValue :: proc(doc: ^Ldtk_Doc, layerUid: int, value: int) {
	di := Ldtk_Doc_LayerDefIndex(doc, layerUid)
	if di < 0 do return
	vals := LdtkJson_Get(doc.layerDefs[di].obj, "intGridValues")
	for v, i in vals.items do if LdtkJson_Int(v, "value") == value {
		ordered_remove(&vals.items, i)
		break
	}
	for &lv in doc.levels {
		for &ly in lv.layers {
			if LdtkJson_Int(ly.obj, "layerDefUid", -1) != layerUid do continue
			for &c in ly.intGrid do if int(c) == value {
				c = 0
				ly.cellsDirty = true
				lv.dirty = true
			}
		}
	}
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_ApplyRulesFull(doc, -1)
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_AddEntityDef adds an entity definition; returns its uid.
Ldtk_Doc_AddEntityDef :: proc(doc: ^Ldtk_Doc, identifier: string) -> int {
	a := doc.allocator
	uid := Ldtk_Doc_NextUid(doc)
	arr := defs_arr(doc, "entities")
	o := jo(a)
	pstr(o, "identifier", Ldtk_Doc_UniqueIdentifier(doc, "entities", identifier), a)
	pint(o, "uid", uid, a)
	put(o, "tags", ja(a), a)
	pbool(o, "exportToToc", false, a)
	pbool(o, "allowOutOfBounds", false, a)
	pnull(o, "doc", a)
	pint(o, "width", LdtkJson_Int(doc.root, "defaultEntityWidth", 16), a)
	pint(o, "height", LdtkJson_Int(doc.root, "defaultEntityHeight", 16), a)
	pbool(o, "resizableX", false, a)
	pbool(o, "resizableY", false, a)
	pnull(o, "minWidth", a)
	pnull(o, "maxWidth", a)
	pnull(o, "minHeight", a)
	pnull(o, "maxHeight", a)
	pbool(o, "keepAspectRatio", false, a)
	pint(o, "tileOpacity", 1, a)
	pnum(o, "fillOpacity", 0.08, a)
	pint(o, "lineOpacity", 1, a)
	pbool(o, "hollow", false, a)
	pstr(o, "color", LDTK_PALETTE[(len(arr.items) + 6) % len(LDTK_PALETTE)], a)
	pstr(o, "renderMode", "Rectangle", a)
	pbool(o, "showName", true, a)
	pnull(o, "tilesetId", a)
	pstr(o, "tileRenderMode", "FitInside", a)
	pnull(o, "tileRect", a)
	pnull(o, "uiTileRect", a)
	put(o, "nineSliceBorders", ja(a), a)
	pint(o, "maxCount", 0, a)
	pstr(o, "limitScope", "PerLevel", a)
	pstr(o, "limitBehavior", "MoveLastOne", a)
	pnum(o, "pivotX", LdtkJson_Float(doc.root, "defaultPivotX"), a)
	pnum(o, "pivotY", LdtkJson_Float(doc.root, "defaultPivotY"), a)
	put(o, "fieldDefs", ja(a), a)
	append(&arr.items, o)
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_Touch(doc)
	return uid
}

// Ldtk_Doc_SetEntityTile sets an entity def's tile (w = 0 clears it).
Ldtk_Doc_SetEntityTile :: proc(doc: ^Ldtk_Doc, entityUid: int, tilesetUid: int, rect: [4]int) {
	a := doc.allocator
	ed := Ldtk_Doc_EntityDef(doc, entityUid)
	if ed == nil do return
	if rect[2] <= 0 || tilesetUid < 0 {
		LdtkJson_SetNull(ed.obj, "tileRect", a)
		LdtkJson_SetNull(ed.obj, "tilesetId", a)
		LdtkJson_SetStr(ed.obj, "renderMode", "Rectangle", a)
	} else {
		tr := jo(a)
		pint(tr, "tilesetUid", tilesetUid, a)
		pint(tr, "x", rect[0], a)
		pint(tr, "y", rect[1], a)
		pint(tr, "w", rect[2], a)
		pint(tr, "h", rect[3], a)
		LdtkJson_Set(ed.obj, "tileRect", tr, a)
		LdtkJson_SetInt(ed.obj, "tilesetId", tilesetUid, a)
		LdtkJson_SetStr(ed.obj, "renderMode", "Tile", a)
	}
	Ldtk_Doc_EntityDefChanged(doc, entityUid)
}

// Ldtk_Doc_EntityDefChanged updates the "__" caches of its instances.
Ldtk_Doc_EntityDefChanged :: proc(doc: ^Ldtk_Doc, entityUid: int) {
	a := doc.allocator
	Ldtk_Doc_RefreshDefs(doc)
	ed := Ldtk_Doc_EntityDef(doc, entityUid)
	if ed == nil do return
	tile := LdtkJson_Get(ed.obj, "tileRect")
	for &lv in doc.levels {
		for &ly in lv.layers {
			for ent in LdtkJson_Arr(ly.obj, "entityInstances") {
				if LdtkJson_Int(ent, "defUid", -1) != entityUid do continue
				LdtkJson_SetStr(ent, "__identifier", ed.identifier, a)
				LdtkJson_Set(ent, "__pivot", ldtk_pair_f(ed.pivot, a), a)
				tags := LdtkJson_New(.Array, a)
				for t in LdtkJson_Arr(ed.obj, "tags") do append(&tags.items, LdtkJson_Clone(t, a))
				LdtkJson_Set(ent, "__tags", tags, a)
				LdtkJson_Set(ent, "__tile", tile != nil && tile.kind == .Object ? LdtkJson_Clone(tile, a) : LdtkJson_New(.Null, a), a)
				LdtkJson_SetStr(ent, "__smartColor", Ldtk_ColorHex(ed.color), a)
				if !LdtkJson_Bool(ed.obj, "resizableX") do LdtkJson_SetInt(ent, "width", ed.size.x, a)
				if !LdtkJson_Bool(ed.obj, "resizableY") do LdtkJson_SetInt(ent, "height", ed.size.y, a)
				lv.dirty = true
			}
		}
	}
	Ldtk_Doc_Touch(doc)
}

@(private = "file")
ldtk_pair_f :: proc(v: [2]f64, a: mem.Allocator) -> ^LdtkJson {
	arr := ja(a)
	append(&arr.items, LdtkJson_NewFloat(v.x, a), LdtkJson_NewFloat(v.y, a))
	return arr
}

// Ldtk_Doc_RemoveEntityDef removes an entity def and its instances.
Ldtk_Doc_RemoveEntityDef :: proc(doc: ^Ldtk_Doc, entityUid: int) {
	arr := defs_arr(doc, "entities")
	for d, i in arr.items do if LdtkJson_Int(d, "uid", -1) == entityUid {
		ordered_remove(&arr.items, i)
		break
	}
	for &lv in doc.levels {
		for &ly in lv.layers {
			list := LdtkJson_Get(ly.obj, "entityInstances")
			if list == nil do continue
			w := 0
			for ent in list.items {
				if LdtkJson_Int(ent, "defUid", -1) == entityUid do continue
				list.items[w] = ent
				w += 1
			}
			if w != len(list.items) do lv.dirty = true
			resize(&list.items, w)
		}
	}
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_Touch(doc)
}

LDTK_FIELD_TYPES := [?]struct {type, label: string}{
	{"F_Int", "Int"}, {"F_Float", "Float"}, {"F_Bool", "Bool"}, {"F_String", "String"},
	{"F_Text", "Multilines"}, {"F_Color", "Color"}, {"F_Point", "Point"}, {"F_Path", "FilePath"},
	{"F_EntityRef", "EntityRef"}, {"F_Tile", "Tile"},
}

// Ldtk_Doc_AddFieldDef adds a field to an entity def (entityUid) or to the
// levels (entityUid < 0); `type` is an LDtk field type ("F_Int", ...,
// "F_Enum(<uid>)"). Existing instances get the default value.
Ldtk_Doc_AddFieldDef :: proc(doc: ^Ldtk_Doc, entityUid: int, type: string, identifier: string) -> int {
	a := doc.allocator
	list: ^LdtkJson
	if entityUid >= 0 {
		ed := Ldtk_Doc_EntityDef(doc, entityUid)
		if ed == nil do return -1
		list = LdtkJson_Get(ed.obj, "fieldDefs")
	} else {
		list = defs_arr(doc, "levelFields")
	}
	if list == nil do return -1
	uid := Ldtk_Doc_NextUid(doc)
	label := type
	for t in LDTK_FIELD_TYPES do if t.type == type do label = t.label
	if strings.has_prefix(type, "F_Enum(") {
		ed := Ldtk_Doc_EnumDef(doc, Ldtk_FieldTypeEnumUid(type))
		label = fmt.tprintf("%s.%s", Ldtk_Doc_EnumIsExternal(ed) ? "ExternEnum" : "LocalEnum", LdtkJson_Str(ed, "identifier"))
	}
	name := Ldtk_CleanIdentifier(identifier)
	// unique among this list
	for n := 2; ; n += 1 {
		used := false
		for f in list.items do if LdtkJson_Str(f, "identifier") == name do used = true
		if !used do break
		name = fmt.tprintf("%s%d", Ldtk_CleanIdentifier(identifier), n)
	}
	name = strings.to_lower(name[:1], context.temp_allocator) == name[:1] ? name : fmt.tprintf("%s%s", strings.to_lower(name[:1], context.temp_allocator), name[1:])
	nullable := type == "F_Point" || type == "F_Path" || type == "F_EntityRef" || type == "F_Tile"
	o := jo(a)
	pstr(o, "identifier", name, a)
	pnull(o, "doc", a)
	pstr(o, "__type", label, a)
	pint(o, "uid", uid, a)
	pstr(o, "type", type, a)
	pbool(o, "isArray", false, a)
	pbool(o, "canBeNull", nullable, a)
	pnull(o, "arrayMinLength", a)
	pnull(o, "arrayMaxLength", a)
	pstr(o, "editorDisplayMode", type == "F_EntityRef" ? "RefLinkBetweenCenters" : "Hidden", a) // (references: an arrow, like LDtk)
	pint(o, "editorDisplayScale", 1, a)
	pstr(o, "editorDisplayPos", "Above", a)
	pstr(o, "editorLinkStyle", "StraightArrow", a)
	pnull(o, "editorDisplayColor", a)
	pbool(o, "editorAlwaysShow", false, a)
	pbool(o, "editorShowInWorld", true, a)
	pbool(o, "editorCutLongValues", true, a)
	pnull(o, "editorTextSuffix", a)
	pnull(o, "editorTextPrefix", a)
	pbool(o, "useForSmartColor", false, a)
	pbool(o, "exportToToc", false, a)
	pbool(o, "searchable", false, a)
	pnull(o, "min", a)
	pnull(o, "max", a)
	pnull(o, "regex", a)
	put(o, "acceptFileTypes", LdtkJson_New(.Null, a), a)
	pnull(o, "defaultOverride", a)
	pnull(o, "textLanguageMode", a)
	pbool(o, "symmetricalRef", false, a)
	pbool(o, "autoChainRef", true, a)
	pbool(o, "allowOutOfLevelRef", true, a)
	pstr(o, "allowedRefs", "OnlySame", a)
	pnull(o, "allowedRefsEntityUid", a)
	put(o, "allowedRefTags", ja(a), a)
	pnull(o, "tilesetUid", a)
	append(&list.items, o)
	Ldtk_Doc_RefreshDefs(doc)
	// instances
	for &lv in doc.levels {
		if entityUid < 0 {
			for target in ([]^LdtkJson{lv.obj, lv.extRoot}) {
				if target == nil do continue
				fis := LdtkJson_Get(target, "fieldInstances")
				if fis != nil do append(&fis.items, Ldtk_Doc_NewFieldInstance(doc, o, a))
			}
			lv.dirty = true
			continue
		}
		for &ly in lv.layers {
			for ent in LdtkJson_Arr(ly.obj, "entityInstances") {
				if LdtkJson_Int(ent, "defUid", -1) != entityUid do continue
				fis := LdtkJson_Get(ent, "fieldInstances")
				if fis != nil do append(&fis.items, Ldtk_Doc_NewFieldInstance(doc, o, a))
				lv.dirty = true
			}
		}
	}
	Ldtk_Doc_Touch(doc)
	return uid
}

// Ldtk_Doc_RemoveFieldDef removes a field def and its instances.
Ldtk_Doc_RemoveFieldDef :: proc(doc: ^Ldtk_Doc, fieldUid: int) {
	strip :: proc(list: ^LdtkJson, uid: int, key: string) -> bool {
		if list == nil do return false
		for f, i in list.items do if LdtkJson_Int(f, key, -1) == uid {
			ordered_remove(&list.items, i)
			return true
		}
		return false
	}
	defs := LdtkJson_Get(doc.root, "defs")
	strip(LdtkJson_Get(defs, "levelFields"), fieldUid, "uid")
	for e in LdtkJson_Arr(defs, "entities") do strip(LdtkJson_Get(e, "fieldDefs"), fieldUid, "uid")
	for &lv in doc.levels {
		if strip(LdtkJson_Get(lv.obj, "fieldInstances"), fieldUid, "defUid") do lv.dirty = true
		if lv.extRoot != nil do strip(LdtkJson_Get(lv.extRoot, "fieldInstances"), fieldUid, "defUid")
		for &ly in lv.layers {
			for ent in LdtkJson_Arr(ly.obj, "entityInstances") {
				if strip(LdtkJson_Get(ent, "fieldInstances"), fieldUid, "defUid") do lv.dirty = true
			}
		}
	}
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_AddEnum adds an enum def; returns its uid.
Ldtk_Doc_AddEnum :: proc(doc: ^Ldtk_Doc, identifier: string) -> int {
	a := doc.allocator
	uid := Ldtk_Doc_NextUid(doc)
	o := jo(a)
	pstr(o, "identifier", Ldtk_Doc_UniqueIdentifier(doc, "enums", identifier), a)
	pint(o, "uid", uid, a)
	put(o, "values", ja(a), a)
	pnull(o, "iconTilesetUid", a)
	pnull(o, "externalRelPath", a)
	pnull(o, "externalFileChecksum", a)
	put(o, "tags", ja(a), a)
	append(&defs_arr(doc, "enums").items, o)
	Ldtk_Doc_Touch(doc)
	return uid
}

// Ldtk_Doc_AddEnumValue adds a value id to an enum.
Ldtk_Doc_AddEnumValue :: proc(doc: ^Ldtk_Doc, enumUid: int, id: string) -> bool {
	a := doc.allocator
	ed := Ldtk_Doc_EnumDef(doc, enumUid)
	if ed == nil do return false
	vals := LdtkJson_Get(ed, "values")
	clean := Ldtk_Doc_CleanIdentifier(doc, id)
	for v in vals.items do if LdtkJson_Str(v, "id") == clean do return false
	// a palette colour no value uses yet (Const.suggestNiceColor)
	color := 0
	for hex in LDTK_PALETTE {
		c := Ldtk_ParseHexColor(hex)
		rgb := int(c.r) << 16 | int(c.g) << 8 | int(c.b)
		used := false
		for v in vals.items do if LdtkJson_Int(v, "color") == rgb do used = true
		if !used {
			color = rgb
			break
		}
	}
	o := jo(a)
	pstr(o, "id", clean, a)
	pnull(o, "tileRect", a)
	pint(o, "color", color, a)
	append(&vals.items, o)
	Ldtk_Doc_Touch(doc)
	return true
}

// Ldtk_Doc_ReloadTilesetImage: the image changed on disk - like a new
// image (Ldtk_Doc_SetTilesetImage): sizes, cached pixel data (opaque tiles,
// which rules use), tile ids remapped when the size changed.
Ldtk_Doc_ReloadTilesetImage :: proc(doc: ^Ldtk_Doc, tilesetUid: int, img: ^rl.Image) {
	Ldtk_Doc_SetTilesetImage(doc, tilesetUid, "", img)
}

// Ldtk_Doc_AddTileset adds a tileset from an image (path relative to the
// project file). `img` (optional) fills LDtk's cached opaque-tile data,
// which the rule engine uses.
Ldtk_Doc_AddTileset :: proc(doc: ^Ldtk_Doc, relPath: string, pxSize: [2]int, grid: int, img: ^rl.Image = nil) -> int {
	a := doc.allocator
	uid := Ldtk_Doc_NextUid(doc)
	base := relPath
	if i := strings.last_index_byte(base, '/'); i >= 0 do base = base[i + 1:]
	if i := strings.last_index_byte(base, '.'); i >= 0 do base = base[:i]
	cw := grid > 0 ? (pxSize.x + grid - 1) / grid : 0
	ch := grid > 0 ? (pxSize.y + grid - 1) / grid : 0
	o := jo(a)
	pint(o, "__cWid", cw, a)
	pint(o, "__cHei", ch, a)
	pstr(o, "identifier", Ldtk_Doc_UniqueIdentifier(doc, "tilesets", base), a)
	pint(o, "uid", uid, a)
	pstr(o, "relPath", relPath, a)
	pnull(o, "embedAtlas", a)
	pint(o, "pxWid", pxSize.x, a)
	pint(o, "pxHei", pxSize.y, a)
	pint(o, "tileGridSize", grid, a)
	pint(o, "spacing", 0, a)
	pint(o, "padding", 0, a)
	put(o, "tags", ja(a), a)
	pnull(o, "tagsSourceEnumUid", a)
	put(o, "enumTags", ja(a), a)
	put(o, "customData", ja(a), a)
	put(o, "savedSelections", ja(a), a)
	if img != nil && img.data != nil {
		put(o, "cachedPixelData", Ldtk_TilesetPixelData(img, grid, 0, 0, a), a)
	} else {
		pnull(o, "cachedPixelData", a)
	}
	append(&defs_arr(doc, "tilesets").items, o)
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_Touch(doc)
	return uid
}

// Ldtk_TilesetPixelData: {"opaqueTiles": "0101...", "averageColors": "..."}
// (TilesetDef.buildPixelData: a tile is opaque when every pixel is; the
// average colour is 4 hex digits ARGB per tile).
Ldtk_TilesetPixelData :: proc(img: ^rl.Image, grid, spacing, padding: int, a: mem.Allocator) -> ^LdtkJson {
	o := jo(a)
	step := grid + spacing
	if step <= 0 do return o
	cw := (int(img.width) - padding * 2 + step - 1) / step
	ch := (int(img.height) - padding * 2 + step - 1) / step
	opaque := strings.builder_make(context.temp_allocator)
	avg := strings.builder_make(context.temp_allocator)
	colors := rl.LoadImageColors(img^)
	defer rl.UnloadImageColors(colors)
	w, h := int(img.width), int(img.height)
	for ty in 0 ..< ch {
		for tx in 0 ..< cw {
			x0 := padding + tx * step
			y0 := padding + ty * step
			isOpaque := true
			sum: [4]f64
			n := 0.0
			for y in y0 ..< min(y0 + grid, h) {
				for x in x0 ..< min(x0 + grid, w) {
					c := colors[x + y * w]
					if c.a < 255 do isOpaque = false
					if c.a > 0 {
						sum += {f64(c.a), f64(c.r), f64(c.g), f64(c.b)}
						n += 1
					}
				}
			}
			strings.write_byte(&opaque, isOpaque ? '1' : '0')
			if n > 0 {
				av := sum / n
				fmt.sbprintf(&avg, "%x%x%x%x", int(av[0]) >> 4, int(av[1]) >> 4, int(av[2]) >> 4, int(av[3]) >> 4)
			} else do strings.write_string(&avg, "0000")
		}
	}
	pstr(o, "opaqueTiles", strings.to_string(opaque), a)
	pstr(o, "averageColors", strings.to_string(avg), a)
	return o
}

// ----------------------------------------------------------------------------
// Auto-layer rules
// ----------------------------------------------------------------------------

// Ldtk_Doc_AddRuleGroup adds a rule group to a layer def.
Ldtk_Doc_AddRuleGroup :: proc(doc: ^Ldtk_Doc, layerUid: int, name: string) -> int {
	a := doc.allocator
	di := Ldtk_Doc_LayerDefIndex(doc, layerUid)
	if di < 0 do return -1
	groups := LdtkJson_Get(doc.layerDefs[di].obj, "autoRuleGroups")
	uid := Ldtk_Doc_NextUid(doc)
	o := jo(a)
	pint(o, "uid", uid, a)
	pstr(o, "name", name, a)
	pnull(o, "color", a)
	pnull(o, "icon", a)
	pbool(o, "active", true, a)
	pbool(o, "isOptional", false, a)
	put(o, "rules", ja(a), a)
	pbool(o, "usesWizard", false, a)
	put(o, "requiredBiomeValues", ja(a), a)
	pint(o, "biomeRequirementMode", 0, a)
	append(&groups.items, o)
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_Touch(doc)
	return uid
}

// Ldtk_Doc_AddRule adds a rule (size x size, odd, up to 9) to a group:
// placing `tileId` where the centre cell has `value`. Returns the rule uid.
Ldtk_Doc_AddRule :: proc(doc: ^Ldtk_Doc, layerUid: int, groupUid: int, size := 3, value := 1, tileId := 0) -> int {
	a := doc.allocator
	di := Ldtk_Doc_LayerDefIndex(doc, layerUid)
	if di < 0 do return -1
	g := ldtk_find_group(doc, di, groupUid)
	if g == nil do return -1
	size := clamp(size | 1, 1, LDTK_MAX_AUTO_PATTERN_SIZE)
	uid := Ldtk_Doc_NextUid(doc)
	o := jo(a)
	pint(o, "uid", uid, a)
	pbool(o, "active", true, a)
	pint(o, "size", size, a)
	rects := ja(a)
	one := ja(a)
	append(&one.items, LdtkJson_NewInt(tileId, a))
	append(&rects.items, one)
	put(o, "tileRectsIds", rects, a)
	pint(o, "alpha", 1, a)
	pint(o, "chance", 1, a)
	pbool(o, "breakOnMatch", true, a)
	pat := ja(a)
	for i in 0 ..< size * size do append(&pat.items, LdtkJson_NewInt(i == size * size / 2 ? value : 0, a))
	put(o, "pattern", pat, a)
	pbool(o, "flipX", false, a)
	pbool(o, "flipY", false, a)
	pint(o, "xModulo", 1, a)
	pint(o, "yModulo", 1, a)
	pint(o, "xOffset", 0, a)
	pint(o, "yOffset", 0, a)
	pint(o, "tileXOffset", 0, a)
	pint(o, "tileYOffset", 0, a)
	pint(o, "tileRandomXMin", 0, a)
	pint(o, "tileRandomXMax", 0, a)
	pint(o, "tileRandomYMin", 0, a)
	pint(o, "tileRandomYMax", 0, a)
	pstr(o, "checker", "None", a)
	pstr(o, "tileMode", "Single", a)
	pint(o, "pivotX", 0, a)
	pint(o, "pivotY", 0, a)
	pnull(o, "outOfBoundsValue", a)
	pbool(o, "invalidated", false, a)
	pbool(o, "perlinActive", false, a)
	pint(o, "perlinSeed", int(Ldtk_RandSeedCoords(uid, 7, 13, 9999999)) & 0x7FFFFF, a)
	pnum(o, "perlinScale", 0.2, a)
	pint(o, "perlinOctaves", 2, a)
	append(&LdtkJson_Get(g, "rules").items, o)
	Ldtk_Doc_RulesChanged(doc, layerUid)
	return uid
}

@(private = "file")
ldtk_find_group :: proc(doc: ^Ldtk_Doc, di: int, groupUid: int) -> ^LdtkJson {
	for g in LdtkJson_Arr(doc.layerDefs[di].obj, "autoRuleGroups") do if LdtkJson_Int(g, "uid", -1) == groupUid do return g
	return nil
}

// Ldtk_Doc_FindRule: a rule's object by uid (any layer).
Ldtk_Doc_FindRule :: proc(doc: ^Ldtk_Doc, ruleUid: int) -> (rule: ^LdtkJson, group: ^LdtkJson, layerUid: int) {
	for &d in doc.layerDefs {
		for g in LdtkJson_Arr(d.obj, "autoRuleGroups") {
			for r in LdtkJson_Arr(g, "rules") do if LdtkJson_Int(r, "uid", -1) == ruleUid do return r, g, d.uid
		}
	}
	return nil, nil, -1
}

// Ldtk_Doc_SetRuleCell sets one pattern cell of a rule (0 ignore, v
// require, -v forbid, +/-1000001 anything / nothing).
Ldtk_Doc_SetRuleCell :: proc(doc: ^Ldtk_Doc, ruleUid: int, cx, cy: int, v: int) {
	r, _, layerUid := Ldtk_Doc_FindRule(doc, ruleUid)
	if r == nil do return
	size := LdtkJson_Int(r, "size", 3)
	if cx < 0 || cy < 0 || cx >= size || cy >= size do return
	pat := LdtkJson_Get(r, "pattern")
	if pat == nil || len(pat.items) != size * size do return
	pat.items[cx + cy * size] = LdtkJson_NewInt(v, doc.allocator)
	Ldtk_Doc_RulesChanged(doc, layerUid)
}

// Ldtk_Doc_RemoveRule removes a rule from its group.
Ldtk_Doc_RemoveRule :: proc(doc: ^Ldtk_Doc, ruleUid: int) {
	r, g, layerUid := Ldtk_Doc_FindRule(doc, ruleUid)
	if r == nil do return
	rules := LdtkJson_Get(g, "rules")
	for it, i in rules.items do if it == r {
		ordered_remove(&rules.items, i)
		break
	}
	Ldtk_Doc_RulesChanged(doc, layerUid)
}

// Ldtk_Doc_RulesChanged re-reads the rules and regenerates the auto tiles
// of every level.
Ldtk_Doc_RulesChanged :: proc(doc: ^Ldtk_Doc, layerUid: int) {
	Ldtk_Doc_RefreshDefs(doc)
	for &lv, li in doc.levels {
		for &ly, j in lv.layers {
			d := Ldtk_Doc_LayerDef(doc, &ly)
			if d == nil do continue
			if d.uid == layerUid || d.autoSourceUid == layerUid do Ldtk_Doc_ApplyRulesLayer(doc, li, j)
		}
	}
	Ldtk_Doc_Touch(doc)
}

// ----------------------------------------------------------------------------
// Field definitions: rename, convert, reorder, duplicate
// ----------------------------------------------------------------------------

// ldtk_field_owner: the fieldDefs list holding a field def, and the entity
// def uid (-1 for level fields).
@(private = "file")
ldtk_field_owner :: proc(doc: ^Ldtk_Doc, fieldUid: int) -> (list: ^LdtkJson, entityUid: int) {
	defs := LdtkJson_Get(doc.root, "defs")
	lf := LdtkJson_Get(defs, "levelFields")
	if lf != nil do for f in lf.items do if LdtkJson_Int(f, "uid", -1) == fieldUid do return lf, -1
	for ed in LdtkJson_Arr(defs, "entities") {
		fl := LdtkJson_Get(ed, "fieldDefs")
		if fl != nil do for f in fl.items do if LdtkJson_Int(f, "uid", -1) == fieldUid do return fl, LdtkJson_Int(ed, "uid")
	}
	return nil, -1
}

// ldtk_each_field_instance calls fn for every instance of a field def.
@(private = "file")
ldtk_each_field_instance :: proc(doc: ^Ldtk_Doc, fieldUid: int, fn: proc(doc: ^Ldtk_Doc, fi: ^LdtkJson, data: rawptr), data: rawptr = nil) {
	for &lv in doc.levels {
		for target in ([]^LdtkJson{lv.obj, lv.extRoot}) {
			if target == nil do continue
			for fi in LdtkJson_Arr(target, "fieldInstances") do if LdtkJson_Int(fi, "defUid", -1) == fieldUid do fn(doc, fi, data)
		}
		for &ly in lv.layers {
			for ent in LdtkJson_Arr(ly.obj, "entityInstances") {
				for fi in LdtkJson_Arr(ent, "fieldInstances") do if LdtkJson_Int(fi, "defUid", -1) == fieldUid do fn(doc, fi, data)
			}
		}
		lv.dirty = true
	}
}

// Ldtk_Doc_RenameFieldDef renames a field (and its instances' __identifier).
Ldtk_Doc_RenameFieldDef :: proc(doc: ^Ldtk_Doc, fieldUid: int, name: string) -> bool {
	list, _ := ldtk_field_owner(doc, fieldUid)
	if list == nil do return false
	clean := Ldtk_CleanIdentifier(name, keepCase = true) // (fields keep their case)
	for f in list.items do if LdtkJson_Int(f, "uid", -1) != fieldUid && LdtkJson_Str(f, "identifier") == clean do return false
	fd := Ldtk_Doc_FieldDef(doc, fieldUid)
	LdtkJson_SetStr(fd, "identifier", clean, doc.allocator)
	set :: proc(doc: ^Ldtk_Doc, fi: ^LdtkJson, data: rawptr) {LdtkJson_SetStr(fi, "__identifier", (cast(^string)data)^, doc.allocator)}
	ldtk_each_field_instance(doc, fieldUid, set, &clean)
	Ldtk_Doc_Touch(doc)
	return true
}

// Ldtk_FieldConversion: misc/FieldTypeConverter's conversions.
Ldtk_FieldConversion :: struct {
	from, to: string, // "F_Int"... ("" from: any type, to: "array")
	label:    string,
	lossless: bool,
}

LDTK_FIELD_CONVERSIONS := [?]Ldtk_FieldConversion{
	{"", "array", "Turn into an array", true},
	{"F_String", "F_Text", "To Multilines", true},
	{"F_Text", "F_String", "To String (removes line breaks)", false},
	{"F_Path", "F_String", "To String", true},
	{"F_String", "F_Path", "To FilePath", true},
	{"F_Int", "F_Float", "To Float", true},
	{"F_Bool", "F_Int", "To Int (0 / 1)", true},
	{"F_Float", "F_Int", "To Int (truncate)", false},
	{"F_Float", "F_Int", "To Int (round)", false},
}

// Ldtk_Doc_FieldConversions: the conversions a field def offers (indices in
// LDTK_FIELD_CONVERSIONS).
Ldtk_Doc_FieldConversions :: proc(fd: ^LdtkJson) -> []int {
	out := make([dynamic]int, context.temp_allocator)
	t := LdtkJson_Str(fd, "type")
	for c, i in LDTK_FIELD_CONVERSIONS {
		if c.from == "" {
			if !LdtkJson_Bool(fd, "isArray") do append(&out, i)
		} else if c.from == t do append(&out, i)
	}
	return out[:]
}

// Ldtk_FieldTypeLabel: "F_Int" -> "Int" (LDtk's __type names).
Ldtk_FieldTypeLabel :: proc(t: string) -> string {
	for x in LDTK_FIELD_TYPES do if x.type == t do return x.label
	return t
}

// Ldtk_Doc_ConvertFieldDef applies a conversion (index in
// LDTK_FIELD_CONVERSIONS) to a field def and its values.
Ldtk_Doc_ConvertFieldDef :: proc(doc: ^Ldtk_Doc, fieldUid: int, conv: int) -> bool {
	a := doc.allocator
	fd := Ldtk_Doc_FieldDef(doc, fieldUid)
	if fd == nil || conv < 0 || conv >= len(LDTK_FIELD_CONVERSIONS) do return false
	c := LDTK_FIELD_CONVERSIONS[conv]
	if c.from != "" && c.from != LdtkJson_Str(fd, "type") do return false
	State :: struct {conv: int}
	st := State{conv}
	if c.to == "array" {
		LdtkJson_SetBool(fd, "isArray", true, a)
		LdtkJson_SetStr(fd, "__type", fmt.tprintf("Array<%s>", LdtkJson_Str(fd, "__type")), a)
	} else {
		LdtkJson_SetStr(fd, "type", c.to, a)
		label := Ldtk_FieldTypeLabel(c.to)
		LdtkJson_SetStr(fd, "__type", LdtkJson_Bool(fd, "isArray") ? fmt.tprintf("Array<%s>", label) : label, a)
		// the default follows
		if over := LdtkJson_Get(fd, "defaultOverride"); over != nil && over.kind == .Object {
			LdtkJson_Set(fd, "defaultOverride", ldtk_convert_value(over, conv, a), a)
		}
		if c.to == "F_Int" {
			for key in ([]string{"min", "max"}) {
				if v := LdtkJson_Get(fd, key); v != nil && v.kind == .Number do LdtkJson_SetFloat(fd, key, conv == 8 ? math.round(v.num) : f64(i64(v.num)), a)
			}
		}
	}
	conv_inst :: proc(doc: ^Ldtk_Doc, fi: ^LdtkJson, data: rawptr) {
		st := cast(^State)data
		rev := LdtkJson_Get(fi, "realEditorValues")
		if rev != nil do for v, i in rev.items do rev.items[i] = ldtk_convert_value(v, st.conv, doc.allocator)
	}
	ldtk_each_field_instance(doc, fieldUid, conv_inst, &st)
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_RefreshFieldInstances(doc, fieldUid)
	Ldtk_Doc_Touch(doc)
	return true
}

// ldtk_convert_value: one internal value through a conversion.
@(private = "file")
ldtk_convert_value :: proc(v: ^LdtkJson, conv: int, a: mem.Allocator) -> ^LdtkJson {
	if v == nil || v.kind != .Object do return v // the default / missing: unchanged
	id := LdtkJson_Str(v, "id")
	if id == "V_Null" do return v
	p := LdtkJson_Arr(v, "params")
	if len(p) == 0 do return v
	x := p[0]
	mk :: proc(id: string, x: ^LdtkJson, a: mem.Allocator) -> ^LdtkJson {
		o := LdtkJson_New(.Object, a)
		arr := LdtkJson_New(.Array, a)
		append(&arr.items, x)
		append(&o.keys, strings.clone("id", a), strings.clone("params", a))
		append(&o.items, LdtkJson_NewString(id, a), arr)
		return o
	}
	switch conv {
	case 2: // Text -> String
		s, _ := strings.replace_all(x.text, "\n", " ", context.temp_allocator)
		return mk("V_String", LdtkJson_NewString(s, a), a)
	case 5: return mk("V_Float", LdtkJson_NewFloat(x.num, a), a) // Int -> Float
	case 6: return mk("V_Int", LdtkJson_NewInt(x.kind == .Bool && x.b ? 1 : 0, a), a) // Bool -> Int
	case 7: return mk("V_Int", LdtkJson_NewFloat(f64(i64(x.num)), a), a) // truncate
	case 8: return mk("V_Int", LdtkJson_NewFloat(math.round(x.num), a), a) // round
	}
	return v
}

// Ldtk_Doc_MoveFieldDef moves a field def up / down (instances follow, like
// LDtk keeps them in the definitions' order).
Ldtk_Doc_MoveFieldDef :: proc(doc: ^Ldtk_Doc, fieldUid: int, delta: int) -> bool {
	list, _ := ldtk_field_owner(doc, fieldUid)
	if list == nil do return false
	idx := -1
	for f, i in list.items do if LdtkJson_Int(f, "uid", -1) == fieldUid do idx = i
	j := idx + delta
	if idx < 0 || j < 0 || j >= len(list.items) do return false
	other := LdtkJson_Int(list.items[j], "uid", -1)
	list.items[idx], list.items[j] = list.items[j], list.items[idx]
	// swap the instances too
	swap_in :: proc(fis: ^LdtkJson, a, b: int) {
		if fis == nil do return
		ia, ib := -1, -1
		for f, i in fis.items {
			if LdtkJson_Int(f, "defUid", -1) == a do ia = i
			if LdtkJson_Int(f, "defUid", -1) == b do ib = i
		}
		if ia >= 0 && ib >= 0 do fis.items[ia], fis.items[ib] = fis.items[ib], fis.items[ia]
	}
	for &lv in doc.levels {
		swap_in(LdtkJson_Get(lv.obj, "fieldInstances"), fieldUid, other)
		if lv.extRoot != nil do swap_in(LdtkJson_Get(lv.extRoot, "fieldInstances"), fieldUid, other)
		for &ly in lv.layers do for ent in LdtkJson_Arr(ly.obj, "entityInstances") do swap_in(LdtkJson_Get(ent, "fieldInstances"), fieldUid, other)
		lv.dirty = true
	}
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_Touch(doc)
	return true
}

// Ldtk_Doc_DuplicateFieldDef copies a field def (instances get its default).
Ldtk_Doc_DuplicateFieldDef :: proc(doc: ^Ldtk_Doc, fieldUid: int) -> int {
	a := doc.allocator
	list, entityUid := ldtk_field_owner(doc, fieldUid)
	if list == nil do return -1
	src := Ldtk_Doc_FieldDef(doc, fieldUid)
	copy := LdtkJson_Clone(src, a)
	uid := Ldtk_Doc_NextUid(doc)
	LdtkJson_SetInt(copy, "uid", uid, a)
	base := LdtkJson_Str(src, "identifier")
	name := base
	for n := 2; ; n += 1 {
		name = fmt.tprintf("%s%d", base, n)
		used := false
		for f in list.items do if LdtkJson_Str(f, "identifier") == name do used = true
		if !used do break
	}
	LdtkJson_SetStr(copy, "identifier", name, a)
	at := len(list.items)
	for f, i in list.items do if f == src do at = i + 1
	inject_at(&list.items, at, copy)
	Ldtk_Doc_RefreshDefs(doc)
	// instances (after the source's)
	add :: proc(fis: ^LdtkJson, doc: ^Ldtk_Doc, srcUid: int, fd: ^LdtkJson) {
		if fis == nil do return
		at := len(fis.items)
		for f, i in fis.items do if LdtkJson_Int(f, "defUid", -1) == srcUid do at = i + 1
		inject_at(&fis.items, at, Ldtk_Doc_NewFieldInstance(doc, fd, doc.allocator))
	}
	for &lv in doc.levels {
		if entityUid < 0 {
			add(LdtkJson_Get(lv.obj, "fieldInstances"), doc, fieldUid, copy)
			if lv.extRoot != nil do add(LdtkJson_Get(lv.extRoot, "fieldInstances"), doc, fieldUid, copy)
		} else {
			for &ly in lv.layers do for ent in LdtkJson_Arr(ly.obj, "entityInstances") do if LdtkJson_Int(ent, "defUid", -1) == entityUid do add(LdtkJson_Get(ent, "fieldInstances"), doc, fieldUid, copy)
		}
		lv.dirty = true
	}
	Ldtk_Doc_Touch(doc)
	return uid
}

// ----------------------------------------------------------------------------
// Entity definitions: reorder, duplicate, limits, sizes
// ----------------------------------------------------------------------------

// Ldtk_Doc_MoveEntityDef moves an entity def up / down in the list.
Ldtk_Doc_MoveEntityDef :: proc(doc: ^Ldtk_Doc, entityUid: int, delta: int) -> bool {
	arr := defs_arr(doc, "entities")
	for d, i in arr.items {
		if LdtkJson_Int(d, "uid", -1) != entityUid do continue
		j := i + delta
		if j < 0 || j >= len(arr.items) do return false
		arr.items[i], arr.items[j] = arr.items[j], arr.items[i]
		Ldtk_Doc_RefreshDefs(doc)
		Ldtk_Doc_Touch(doc)
		return true
	}
	return false
}

// Ldtk_Doc_DuplicateEntityDef copies an entity def (with its fields).
Ldtk_Doc_DuplicateEntityDef :: proc(doc: ^Ldtk_Doc, entityUid: int) -> int {
	a := doc.allocator
	ed := Ldtk_Doc_EntityDef(doc, entityUid)
	if ed == nil do return -1
	copy := LdtkJson_Clone(ed.obj, a)
	uid := Ldtk_Doc_NextUid(doc)
	LdtkJson_SetInt(copy, "uid", uid, a)
	LdtkJson_SetStr(copy, "identifier", Ldtk_Doc_UniqueIdentifier(doc, "entities", ed.identifier), a)
	for f in LdtkJson_Arr(copy, "fieldDefs") do LdtkJson_SetInt(f, "uid", Ldtk_Doc_NextUid(doc), a)
	arr := defs_arr(doc, "entities")
	at := len(arr.items)
	for d, i in arr.items do if d == ed.obj do at = i + 1
	inject_at(&arr.items, at, copy)
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_Touch(doc)
	return uid
}

// Ldtk_Doc_PlaceEntity adds an entity respecting its def's "maxCount"
// (limitScope: PerLayer / PerLevel / PerWorld; limitBehavior: MoveLastOne -
// the last one moves here, DiscardOldOnes - the oldest goes, PreventAdding).
// Returns the placed (or moved) entity, nil when prevented.
Ldtk_Doc_PlaceEntity :: proc(doc: ^Ldtk_Doc, li, layer: int, defUid: int, px: [2]int) -> (ent: ^LdtkJson, moved: bool) {
	ed := Ldtk_Doc_EntityDef(doc, defUid)
	if ed == nil do return nil, false
	maxCount := LdtkJson_Int(ed.obj, "maxCount")
	if maxCount > 0 {
		scope := LdtkJson_Str(ed.obj, "limitScope", "PerLevel")
		Found :: struct {li, layer: int, ent: ^LdtkJson}
		found := make([dynamic]Found, context.temp_allocator)
		for &lv, i in doc.levels {
			if scope != "PerWorld" && i != li do continue
			if scope == "PerWorld" && lv.world != doc.levels[li].world do continue
			for &ly, j in lv.layers {
				if scope == "PerLayer" && (i != li || j != layer) do continue
				for e in LdtkJson_Arr(ly.obj, "entityInstances") do if LdtkJson_Int(e, "defUid", -1) == defUid do append(&found, Found{i, j, e})
			}
		}
		if len(found) >= maxCount {
			switch LdtkJson_Str(ed.obj, "limitBehavior", "MoveLastOne") {
			case "PreventAdding":
				return nil, false
			case "DiscardOldOnes":
				for k in 0 ..= len(found) - maxCount do Ldtk_Doc_RemoveEntity(doc, found[k].li, found[k].layer, found[k].ent)
			case: // MoveLastOne
				last := found[len(found) - 1]
				if last.li == li && last.layer == layer {
					Ldtk_Doc_MoveEntity(doc, li, layer, last.ent, px)
					return last.ent, true
				}
				Ldtk_Doc_RemoveEntity(doc, last.li, last.layer, last.ent)
			}
		}
	}
	return Ldtk_Doc_AddEntity(doc, li, layer, defUid, px), false
}

// Ldtk_Doc_ConstrainEntitySize: a size within the def's min / max (and its
// aspect ratio when kept).
Ldtk_Doc_ConstrainEntitySize :: proc(doc: ^Ldtk_Doc, defUid: int, size: [2]int, keepFrom: [2]int = {}) -> [2]int {
	ed := Ldtk_Doc_EntityDef(doc, defUid)
	if ed == nil do return size
	s := size
	if LdtkJson_Bool(ed.obj, "keepAspectRatio") && ed.size.x > 0 && ed.size.y > 0 {
		// follow the axis that changed the most
		if abs(s.x - keepFrom.x) >= abs(s.y - keepFrom.y) do s.y = int(math.round(f64(s.x) * f64(ed.size.y) / f64(ed.size.x)))
		else do s.x = int(math.round(f64(s.y) * f64(ed.size.x) / f64(ed.size.y)))
	}
	lim :: proc(o: ^LdtkJson, key: string, v: int, isMin: bool) -> int {
		x := LdtkJson_Get(o, key)
		if x == nil || x.kind != .Number do return v
		return isMin ? max(v, int(x.num)) : min(v, int(x.num))
	}
	s.x = lim(ed.obj, "maxWidth", lim(ed.obj, "minWidth", s.x, true), false)
	s.y = lim(ed.obj, "maxHeight", lim(ed.obj, "minHeight", s.y, true), false)
	return {max(s.x, 1), max(s.y, 1)}
}
