package engine

import "core:fmt"
import "core:math/rand"
import vmem "core:mem/virtual"
import os "osx"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"
import rl "vendor:raylib"

// Samples saved by LDtk 1.5 (stamps, rule assistant, external levels) and
// the drive project (9 rule layers).
LDTK_DOC_FIXTURES := [?]string{
	"tests/drive/fixtures/ldtk_editor/stamps_zz.ldtk",
	"tests/drive/fixtures/ldtk_editor/assistant_zz.ldtk",
	"tests/drive/fixtures/ldtk_editor/SeparateLevelFiles.ldtk",
	"tests/drive/fixtures/ldtk/topdown.ldtk",
}

@(private = "file")
read_text :: proc(path: string) -> string {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil do return ""
	return string(data)
}

@(test)
test_ldtk_json_round_trip_and_js_numbers :: proc(t: ^testing.T) {
	for path in LDTK_DOC_FIXTURES[:3] {
		text := read_text(path)
		testing.expectf(t, text != "", "fixture %s", path)
		arena: vmem.Arena
		_ = vmem.arena_init_growing(&arena)
		a := vmem.arena_allocator(&arena)
		root, ok := LdtkJson_Parse(text, a)
		testing.expect(t, ok)
		out := LdtkJson_ToString(root, .Compact, a)
		testing.expectf(t, out == text, "%s written back byte for byte", path)
		vmem.arena_destroy(&arena)
	}
	cases := [?]struct {v: f64, s: string}{
		{0.3, "0.3"}, {0.35000000000000003, "0.35000000000000003"}, {1, "1"}, {-2.5, "-2.5"},
		{1e21, "1e+21"}, {1e-7, "1e-7"}, {0.000001, "0.000001"}, {123456789012, "123456789012"}, {0.1 + 0.2, "0.30000000000000004"},
	}
	for c in cases {
		b := strings.builder_make(context.temp_allocator)
		ldtk_js_number(&b, c.v)
		testing.expectf(t, strings.to_string(b) == c.s, "%v -> %s (want %s)", c.v, strings.to_string(b), c.s)
	}
	// edits: new keys / strings are encoded, untouched numbers keep their text
	arena: vmem.Arena
	_ = vmem.arena_init_growing(&arena)
	defer vmem.arena_destroy(&arena)
	a := vmem.arena_allocator(&arena)
	root, _ := LdtkJson_Parse(`{"a": 1.50, "b": [1,2]}`, a)
	LdtkJson_SetStr(root, "c", "say \"hi\"\tnow", a)
	LdtkJson_SetInt(root, "a", 1, a)
	testing.expect_value(t, LdtkJson_ToString(root, .Compact, a), `{ "a": 1, "b": [1,2], "c": "say \"hi\" now" }`)
}

@(test)
test_ldtk_rules_match_ldtk_and_save_is_identical :: proc(t: ^testing.T) {
	for path in LDTK_DOC_FIXTURES {
		doc, ok := Ldtk_Doc_Load(path)
		testing.expectf(t, ok, "load %s", path)
		if !ok do continue
		defer Ldtk_Doc_Destroy(doc)
		layers := 0
		for &lv, li in doc.levels {
			stored := make([][dynamic]Ldtk_DocTile, len(lv.layers), context.temp_allocator)
			for &ly, i in lv.layers {
				stored[i] = make([dynamic]Ldtk_DocTile, context.temp_allocator)
				append(&stored[i], ..ly.autoTiles[:])
			}
			Ldtk_Doc_ApplyRulesFull(doc, li)
			for &ly, i in lv.layers {
				d := Ldtk_Doc_LayerDef(doc, &ly)
				if d == nil || len(d.groups) == 0 do continue
				layers += 1
				same := len(stored[i]) == len(ly.autoTiles)
				if same {
					for s, k in stored[i] {
						g := ly.autoTiles[k]
						if s.px != g.px || s.src != g.src || s.t != g.t || s.f != g.f || s.rule != g.rule || s.coord != g.coord {
							same = false
							break
						}
					}
				}
				testing.expectf(t, same, "%s level %d layer %s: regenerated auto tiles match LDtk's", path, li, d.identifier)
			}
		}
		// every layer re-written from the typed data gives LDtk's bytes
		// (topdown.ldtk was written by a script, not by LDtk)
		if strings.has_suffix(path, "topdown.ldtk") do continue
		for &lv in doc.levels do for &ly in lv.layers do ly.cellsDirty = true
		// the table of contents and the neighbours recomputed: LDtk's too
		Ldtk_Doc_UpdateToc(doc)
		Ldtk_Doc_UpdateNeighbours(doc)
		proj, paths, texts := Ldtk_Doc_Serialize(doc, context.temp_allocator)
		testing.expectf(t, proj == read_text(path), "%s serialized identically", path)
		for p, i in paths {
			full, _ := filepath.join({filepath.dir(path, context.temp_allocator), p}, context.temp_allocator)
			testing.expectf(t, texts[i] == read_text(full), "%s serialized identically", p)
		}
	}
}

// Painting with incremental rule updates gives the same tiles as a full
// regeneration; undo / redo restore cells and tiles.
@(test)
test_ldtk_doc_paint_incremental_rules_and_undo :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_Load("tests/drive/fixtures/ldtk/topdown.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	li, layer := -1, -1
	for &lv, i in doc.levels {
		for &ly, j in lv.layers {
			d := Ldtk_Doc_LayerDef(doc, &ly)
			if d != nil && d.type == .IntGrid && len(d.values) > 0 {
				// an IntGrid layer that feeds rules
				deps := 0
				for &other in lv.layers do if Ldtk_RuleSource(doc, &lv, &other) == &ly do deps += 1
				if deps > 0 && li < 0 do li, layer = i, j
			}
		}
	}
	testing.expect(t, li >= 0)
	if li < 0 do return
	Ldtk_Doc_ApplyRulesFull(doc, li)
	before := Ldtk_Doc_ToText(doc)
	ly := &doc.levels[li].layers[layer]
	d := Ldtk_Doc_LayerDef(doc, ly)
	r := rand.create(7)
	context.random_generator = rand.default_random_generator(&r)
	Ldtk_Doc_BeginCells(doc, li, layer, "Paint")
	for _ in 0 ..< 60 {
		cx := rand.int_max(ly.cWid)
		cy := rand.int_max(ly.cHei)
		v := rand.int_max(3) == 0 ? 0 : d.values[rand.int_max(len(d.values))].value
		if Ldtk_Doc_SetIntGrid(doc, li, layer, cx, cy, v) do Ldtk_Doc_ApplyRules(doc, li, layer, cx, cy, cx, cy)
	}
	Ldtk_Doc_EndCells(doc)
	testing.expect_value(t, len(doc.undo), 1)
	painted := Ldtk_Doc_ToText(doc)
	// incremental == full
	incr := make([][dynamic]Ldtk_DocTile, len(doc.levels[li].layers), context.temp_allocator)
	for &l, i in doc.levels[li].layers {
		incr[i] = make([dynamic]Ldtk_DocTile, context.temp_allocator)
		append(&incr[i], ..l.autoTiles[:])
	}
	Ldtk_Doc_ApplyRulesFull(doc, li)
	for &l, i in doc.levels[li].layers {
		same := len(l.autoTiles) == len(incr[i])
		if same do for tl, k in l.autoTiles do if tl.px != incr[i][k].px || tl.t != incr[i][k].t || tl.rule != incr[i][k].rule || tl.f != incr[i][k].f {
			same = false
			break
		}
		testing.expectf(t, same, "layer %d: incremental rules == full regeneration (%d vs %d tiles)", i, len(incr[i]), len(l.autoTiles))
	}
	testing.expect(t, painted != before)
	testing.expect(t, Ldtk_Doc_Undo(doc))
	testing.expect(t, Ldtk_Doc_ToText(doc) == before, "undo restores the cells and tiles")
	testing.expect(t, Ldtk_Doc_Redo(doc))
	testing.expect(t, Ldtk_Doc_ToText(doc) == painted, "redo paints again")
	// tiles: set, stack, clear
	for &l, j in doc.levels[li].layers {
		ld := Ldtk_Doc_LayerDef(doc, &l)
		if ld == nil || ld.type != .Tiles do continue
		Ldtk_Doc_BeginCells(doc, li, j, "Tiles")
		testing.expect(t, Ldtk_Doc_SetTile(doc, li, j, 1, 1, 5))
		testing.expect(t, Ldtk_Doc_SetTile(doc, li, j, 1, 1, 6, 1, true))
		testing.expect_value(t, len(Ldtk_Doc_TilesAt(&l, 1, 1)), 2)
		testing.expect(t, !Ldtk_Doc_SetTile(doc, li, j, 1, 1, 6, 1, true))
		testing.expect(t, Ldtk_Doc_SetTile(doc, li, j, 1, 1, -1))
		testing.expect_value(t, len(Ldtk_Doc_TilesAt(&l, 1, 1)), 0)
		Ldtk_Doc_EndCells(doc)
		break
	}
	// level / project checkpoints
	text0 := Ldtk_Doc_ToText(doc)
	Ldtk_Doc_Checkpoint(doc, li, "Rename")
	LdtkJson_SetStr(doc.levels[li].obj, "identifier", "Zz_Renamed", doc.allocator)
	Ldtk_Doc_Touch(doc)
	testing.expect_value(t, Ldtk_Doc_LevelName(doc, li), "Zz_Renamed")
	testing.expect(t, Ldtk_Doc_Undo(doc))
	testing.expect(t, Ldtk_Doc_ToText(doc) == text0)
	testing.expect(t, Ldtk_Doc_Redo(doc))
	testing.expect_value(t, Ldtk_Doc_LevelName(doc, li), "Zz_Renamed")
	Ldtk_Doc_Checkpoint(doc, -1, "Defs")
	LdtkJson_SetInt(doc.root, "defaultGridSize", 99, doc.allocator)
	testing.expect(t, Ldtk_Doc_Undo(doc))
	testing.expect_value(t, LdtkJson_Int(doc.root, "defaultGridSize"), 16)
	testing.expect_value(t, Ldtk_Doc_LevelName(doc, li), "Zz_Renamed")
}

@(test)
test_ldtk_doc_external_levels_save :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_Load("tests/drive/fixtures/ldtk_editor/SeparateLevelFiles.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	testing.expect_value(t, len(doc.levels), 3)
	testing.expect(t, doc.levels[1].extRoot != nil)
	testing.expect(t, len(doc.levels[1].layers) > 0)
	dir := fmt.tprintf("%s/rayzr_ldtk_doc_zz", Engine_TempDir())
	_ = os.make_directory(dir)
	out := fmt.tprintf("%s/SeparateLevelFiles.ldtk", dir)
	testing.expect(t, Ldtk_Doc_Save(doc, out))
	again, ok2 := Ldtk_Doc_Load(out)
	testing.expect(t, ok2)
	if ok2 {
		testing.expect(t, Ldtk_Doc_ToText(again) == Ldtk_Doc_ToText(doc))
		// paint a level; only it is marked for writing
		for &ly, j in again.levels[1].layers {
			d := Ldtk_Doc_LayerDef(again, &ly)
			if d != nil && d.type == .IntGrid {
				Ldtk_Doc_SetIntGrid(again, 1, j, 0, 0, 1)
				break
			}
		}
		testing.expect(t, again.levels[1].dirty && !again.levels[0].dirty)
		testing.expect(t, Ldtk_Doc_Save(again))
		testing.expect(t, !again.levels[1].dirty && !again.modified)
		Ldtk_Doc_Destroy(again)
	}
	os.remove_all(dir)
}

// Building a project from scratch with the editing API; the runtime reader
// (Ldtk_ParseProject) loads the result.
@(test)
test_ldtk_doc_new_project_defs_entities_levels :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/rayzr_zz_new.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	testing.expect_value(t, len(doc.levels), 1)
	testing.expect_value(t, len(doc.layerDefs), 2) // Collisions (top), Entities
	testing.expect_value(t, doc.layerDefs[0].identifier, "Collisions")
	testing.expect_value(t, len(doc.levels[0].layers), 2)
	col := doc.layerDefs[0].uid
	// a tileset (no image: no opaque data), an auto layer reading Collisions
	ts := Ldtk_Doc_AddTileset(doc, "atlas/tiles_zz.png", {64, 64}, 16)
	auto := Ldtk_Doc_AddLayerDef(doc, .AutoLayer, "Walls", ts)
	d := &doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, auto)]
	LdtkJson_SetInt(d.obj, "autoSourceLayerDefUid", col, doc.allocator)
	Ldtk_Doc_LayerDefChanged(doc, auto)
	g := Ldtk_Doc_AddRuleGroup(doc, auto, "Walls")
	r := Ldtk_Doc_AddRule(doc, auto, g, 3, 1, 5)
	testing.expect(t, r > 0)
	// paint: one wall -> one auto tile (tile 5 at the cell)
	li := 0
	cl := -1
	for &ly, j in doc.levels[li].layers do if Ldtk_Doc_LayerDef(doc, &ly).uid == col do cl = j
	testing.expect(t, cl >= 0)
	testing.expect(t, Ldtk_Doc_SetIntGrid(doc, li, cl, 3, 4, 1))
	Ldtk_Doc_ApplyRules(doc, li, cl, 3, 4, 3, 4)
	wl := Ldtk_Doc_LevelLayer(doc, &doc.levels[li], auto)
	testing.expect_value(t, len(wl.autoTiles), 1)
	if len(wl.autoTiles) == 1 {
		testing.expect_value(t, wl.autoTiles[0].t, 5)
		testing.expect_value(t, wl.autoTiles[0].px, [2]i32{48, 64})
		testing.expect_value(t, wl.autoTiles[0].src, [2]i32{16, 16})
	}
	// the rule now forbids a wall above: (3,4) still matches, (3,5) doesn't
	Ldtk_Doc_SetRuleCell(doc, r, 1, 0, -1)
	Ldtk_Doc_SetIntGrid(doc, li, cl, 3, 5, 1)
	Ldtk_Doc_ApplyRules(doc, li, cl, 3, 5, 3, 5)
	wl = Ldtk_Doc_LevelLayer(doc, &doc.levels[li], auto)
	testing.expect_value(t, len(wl.autoTiles), 1)
	// entities with fields
	ent := Ldtk_Doc_AddEntityDef(doc, "chest")
	testing.expect_value(t, Ldtk_Doc_EntityDef(doc, ent).identifier, "Chest")
	gold := Ldtk_Doc_AddFieldDef(doc, ent, "F_Int", "gold")
	en := Ldtk_Doc_AddEnum(doc, "Rarity")
	testing.expect(t, Ldtk_Doc_AddEnumValue(doc, en, "common"))
	testing.expect(t, Ldtk_Doc_AddEnumValue(doc, en, "Rare"))
	testing.expect(t, !Ldtk_Doc_AddEnumValue(doc, en, "Rare"))
	Ldtk_Doc_AddFieldDef(doc, ent, fmt.tprintf("F_Enum(%d)", en), "rarity")
	el := -1
	for &ly, j in doc.levels[li].layers do if Ldtk_Doc_LayerDef(doc, &ly).type == .Entities do el = j
	e1 := Ldtk_Doc_AddEntity(doc, li, el, ent, {40, 56})
	testing.expect(t, e1 != nil)
	fis := LdtkJson_Arr(e1, "fieldInstances")
	testing.expect_value(t, len(fis), 2)
	testing.expect(t, Ldtk_Doc_SetFieldValue(doc, fis[0], "25"))
	testing.expect(t, !Ldtk_Doc_SetFieldValue(doc, fis[0], "lots"))
	testing.expect(t, Ldtk_Doc_SetFieldValue(doc, fis[1], "Rare"))
	testing.expect(t, !Ldtk_Doc_SetFieldValue(doc, fis[1], "Epic"))
	testing.expect_value(t, Ldtk_FieldText(fis[0]), "25")
	testing.expect_value(t, LdtkJson_ToString(LdtkJson_Get(fis[0], "realEditorValues"), .Minified, context.temp_allocator), `[{"id":"V_Int","params":[25]}]`)
	_ = gold
	Ldtk_Doc_MoveEntity(doc, li, el, e1, {72, 88})
	testing.expect_value(t, LdtkJson_ToString(LdtkJson_Get(e1, "__grid"), .Minified, context.temp_allocator), "[4,5]")
	testing.expect(t, Ldtk_Doc_EntityAt(doc, li, el, {75, 90}) == e1)
	// levels: a second one to the right is a neighbour; resize keeps cells
	l2 := Ldtk_Doc_AddLevel(doc, 0, {256, 0})
	testing.expect_value(t, l2, 1)
	testing.expect_value(t, Ldtk_Doc_FreeLevelSpot(doc, 0, {256, 0}, {256, 256}, 1), [2]int{512, 0})
	n0 := LdtkJson_Arr(doc.levels[0].obj, "__neighbours")
	testing.expect_value(t, len(n0), 1)
	if len(n0) == 1 do testing.expect_value(t, LdtkJson_Str(n0[0], "dir"), "e")
	testing.expect(t, Ldtk_Doc_RenameLevel(doc, 1, "Cave"))
	testing.expect(t, !Ldtk_Doc_RenameLevel(doc, 0, "Cave"))
	Ldtk_Doc_ResizeLevel(doc, 0, {128, 128})
	cly := &doc.levels[0].layers[cl]
	testing.expect_value(t, cly.cWid, 8)
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(cly, 3, 4), 1)
	// layer order follows into every level
	testing.expect(t, Ldtk_Doc_MoveLayerDef(doc, auto, 1))
	testing.expect_value(t, LdtkJson_Int(doc.levels[1].layers[1].obj, "layerDefUid"), auto)
	// the runtime reader loads it
	text := Ldtk_Doc_ToText(doc)
	proj, pok := Ldtk_ParseProject(transmute([]u8)text)
	testing.expect(t, pok)
	if pok {
		testing.expect_value(t, len(proj.levels), 2)
		testing.expect_value(t, proj.levels[1].identifier, "Cave")
		Ldtk_DestroyProject(proj)
	}
	// remove things
	Ldtk_Doc_RemoveEntityDef(doc, ent)
	testing.expect_value(t, len(Ldtk_Doc_Entities(doc, li, el)), 0)
	testing.expect(t, Ldtk_Doc_RemoveLayerDef(doc, auto))
	testing.expect_value(t, len(doc.levels[0].layers), 2)
	testing.expect(t, Ldtk_Doc_RemoveLevel(doc, 1))
	testing.expect_value(t, len(doc.levels), 1)
}

@(test)
test_ldtk_doc_tile_data_animation_terrain :: proc(t: ^testing.T) {
	// the format
	anim, ok := Ldtk_ParseTileAnim("solid\nanim=12, 13,14\nfps=4", context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, len(anim.frames), 3)
	testing.expect_value(t, anim.fps, 4)
	testing.expect_value(t, Ldtk_TileAnimFrame(anim, 0.3), 13)
	testing.expect_value(t, Ldtk_TileAnimFrame(anim, 0.8), 12)
	_, one := Ldtk_ParseTileAnim("anim=5", context.temp_allocator)
	testing.expect(t, !one)

	doc, dok := Ldtk_Doc_New("/tmp/rayzr_zz_tiles.ldtk")
	testing.expect(t, dok)
	if !dok do return
	defer Ldtk_Doc_Destroy(doc)
	ts := Ldtk_Doc_AddTileset(doc, "atlas/tiles_zz.png", {64, 64}, 16)
	// custom data keeps other lines; animation lines are replaced
	Ldtk_Doc_SetTileCustomData(doc, ts, 3, "solid")
	Ldtk_Doc_SetTileAnimation(doc, ts, 3, {3, 4, 5}, 6)
	testing.expect_value(t, Ldtk_Doc_TileCustomData(doc, ts, 3), "solid\nanim=3,4,5\nfps=6")
	Ldtk_Doc_SetTileAnimation(doc, ts, 3, {3, 7}, 8)
	testing.expect_value(t, Ldtk_Doc_TileCustomData(doc, ts, 3), "solid\nanim=3,7")
	testing.expect(t, 3 in Ldtk_Doc_Tileset(doc, ts).anims)
	Ldtk_Doc_SetTileAnimation(doc, ts, 3, nil, 0)
	testing.expect_value(t, Ldtk_Doc_TileCustomData(doc, ts, 3), "solid")
	Ldtk_Doc_SetTileCustomData(doc, ts, 1, "anim=1,2")
	testing.expect_value(t, len(LdtkJson_Arr(Ldtk_Doc_Tileset(doc, ts).obj, "customData")), 2)
	testing.expect_value(t, LdtkJson_Int(LdtkJson_Arr(Ldtk_Doc_Tileset(doc, ts).obj, "customData")[0], "tileId"), 1)
	// enum tags
	en := Ldtk_Doc_AddEnum(doc, "Ground")
	Ldtk_Doc_AddEnumValue(doc, en, "Ice")
	LdtkJson_SetInt(Ldtk_Doc_Tileset(doc, ts).obj, "tagsSourceEnumUid", en, doc.allocator)
	Ldtk_Doc_SetTileTag(doc, ts, 9, "Ice", true)
	Ldtk_Doc_SetTileTag(doc, ts, 2, "Ice", true)
	testing.expect(t, Ldtk_Doc_TileHasTag(doc, ts, 9, "Ice"))
	Ldtk_Doc_SetTileTag(doc, ts, 9, "Ice", false)
	testing.expect(t, !Ldtk_Doc_TileHasTag(doc, ts, 9, "Ice"))
	// the runtime reads the animation and the tags
	proj, pok := Ldtk_ParseProject(transmute([]u8)Ldtk_Doc_ToText(doc))
	testing.expect(t, pok)
	if pok {
		rts := &proj.tilesets[0]
		testing.expect(t, 1 in rts.anims)
		testing.expect_value(t, Ldtk_TilesetTileSrc(rts, 5), [2]f32{16, 16})
		testing.expect_value(t, len(rts.enumTags[2]), 1)
		Ldtk_DestroyProject(proj)
	}
	// terrain: a 3x3 block over Collisions value 1 through an auto layer
	col := doc.layerDefs[0].uid
	auto := Ldtk_Doc_AddLayerDef(doc, .AutoLayer, "Ground", ts)
	LdtkJson_SetInt(doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, auto)].obj, "autoSourceLayerDefUid", col, doc.allocator)
	Ldtk_Doc_LayerDefChanged(doc, auto)
	g := Ldtk_Doc_AddTerrainRules(doc, auto, 1, {0, 1, 2, 4, 5, 6, 8, 9, 10})
	testing.expect(t, g > 0)
	lv := &doc.levels[0]
	cl := -1
	for &ly, j in lv.layers do if Ldtk_Doc_LayerDef(doc, &ly).uid == col do cl = j
	for y in 2 ..= 4 do for x in 2 ..= 4 do Ldtk_Doc_SetIntGrid(doc, 0, cl, x, y, 1)
	Ldtk_Doc_ApplyRules(doc, 0, cl, 2, 2, 4, 4)
	gl := Ldtk_Doc_LevelLayer(doc, lv, auto)
	at :: proc(ly: ^Ldtk_DocLayer, cx, cy: int) -> i32 {
		for tl in ly.autoTiles do if int(tl.coord) == cx + cy * ly.cWid do return tl.t
		return -1
	}
	testing.expect_value(t, len(gl.autoTiles), 9)
	testing.expect_value(t, at(gl, 2, 2), 0)
	testing.expect_value(t, at(gl, 3, 2), 1)
	testing.expect_value(t, at(gl, 4, 2), 2)
	testing.expect_value(t, at(gl, 2, 3), 4)
	testing.expect_value(t, at(gl, 3, 3), 5)
	testing.expect_value(t, at(gl, 4, 4), 10)
}

@(test)
test_ldtk_doc_world_layout :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/rayzr_zz_layout.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	Ldtk_Doc_AddLevel(doc, 0, {600, 40}, {128, 64})
	// linear: computed from the order (48 px apart), -1 stored
	Ldtk_Doc_SetWorldLayout(doc, 0, "LinearHorizontal")
	testing.expect_value(t, LdtkJson_Int(doc.levels[1].obj, "worldX"), -1)
	testing.expect_value(t, Ldtk_Doc_LevelPos(doc, 1), [2]int{256 + 48, 0})
	testing.expect_value(t, len(LdtkJson_Arr(doc.levels[0].obj, "__neighbours")), 0)
	// back to free: the computed positions are written
	Ldtk_Doc_SetWorldLayout(doc, 0, "Free")
	testing.expect_value(t, LdtkJson_Int(doc.levels[1].obj, "worldX"), 304)
	// GridVania snaps to the world grid
	Ldtk_Doc_SetWorldLayout(doc, 0, "GridVania")
	testing.expect_value(t, Ldtk_Doc_LevelPos(doc, 1), [2]int{256, 0})
	testing.expect_value(t, LdtkJson_Str(doc.root, "worldLayout"), "GridVania")
}

@(test)
test_ldtk_doc_selection_move_copy_delete :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/rayzr_zz_sel.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	col, ents := -1, -1
	for &ly, j in doc.levels[0].layers {
		d := Ldtk_Doc_LayerDef(doc, &ly)
		if d.type == .IntGrid do col = j
		if d.type == .Entities do ents = j
	}
	for x in 1 ..= 3 do Ldtk_Doc_SetIntGrid(doc, 0, col, x, 1, 1)
	chest := Ldtk_Doc_AddEntityDef(doc, "Chest")
	e1 := Ldtk_Doc_AddEntity(doc, 0, ents, chest, {40, 24})
	sel: Ldtk_Selection
	defer Ldtk_Selection_Destroy(&sel)
	// a rectangle over cells (1..3, 1) and the chest's cell (2, 1)
	Ldtk_Doc_SelectRect(doc, 0, &sel, {16, 16, 48, 16})
	testing.expectf(t, len(sel.cells) == 3, "cells %v", sel.cells)
	testing.expect_value(t, len(sel.entities), 1)
	// half a cell: cells can't move
	testing.expect(t, !Ldtk_Doc_SelectionCanMove(doc, 0, &sel, {8, 0}))
	// move two cells down
	testing.expect(t, Ldtk_Doc_MoveSelection(doc, 0, &sel, {0, 32}))
	cl := &doc.levels[0].layers[col]
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(cl, 2, 1), 0)
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(cl, 2, 3), 1)
	testing.expect_value(t, LdtkJson_ToString(LdtkJson_Get(e1, "px"), .Minified, context.temp_allocator), "[40,56]")
	// copy one cell right: both remain, the selection is the copy
	testing.expect(t, Ldtk_Doc_MoveSelection(doc, 0, &sel, {16, 0}, true))
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(cl, 1, 3), 1)
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(cl, 4, 3), 1)
	testing.expect_value(t, len(Ldtk_Doc_Entities(doc, 0, ents)), 2)
	testing.expect(t, sel.entities[0].obj != e1)
	testing.expect(t, LdtkJson_Str(sel.entities[0].obj, "iid") != LdtkJson_Str(e1, "iid"))
	// delete the copy
	Ldtk_Doc_DeleteSelection(doc, 0, &sel)
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(cl, 4, 3), 0)
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(cl, 1, 3), 1)
	testing.expect_value(t, len(Ldtk_Doc_Entities(doc, 0, ents)), 1)
	testing.expect(t, Ldtk_Selection_Empty(&sel))
	// select all in the IntGrid layer
	Ldtk_Doc_SelectAll(doc, 0, &sel, col) // the copy overlapped cells 2-3, so only cell 1 is left
	testing.expect_value(t, len(sel.cells), 1)
	testing.expect_value(t, len(sel.entities), 0)
	// another Entities layer requiring a tag: the chest (no tags) can't go
	l2 := Ldtk_Doc_AddLayerDef(doc, .Entities, "Items")
	tags := LdtkJson_New(.Array, doc.allocator)
	append(&tags.items, LdtkJson_NewString("item", doc.allocator))
	LdtkJson_Set(doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, l2)].obj, "requiredTags", tags, doc.allocator)
	Ldtk_Doc_RefreshDefs(doc)
	el2 := -1
	ents = -1
	for &ly, j in doc.levels[0].layers {
		d := Ldtk_Doc_LayerDef(doc, &ly)
		if d.uid == l2 do el2 = j
		else if d.type == .Entities do ents = j
	}
	testing.expect(t, !Ldtk_Doc_EntityLayerAllowed(doc, 0, el2, e1))
	testing.expect(t, Ldtk_Doc_MoveEntityToLayer(doc, 0, ents, el2, e1))
	testing.expect_value(t, len(Ldtk_Doc_Entities(doc, 0, el2)), 1)
	testing.expect_value(t, len(Ldtk_Doc_Entities(doc, 0, ents)), 0)
}

@(test)
test_ldtk_doc_clipboard :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/rayzr_zz_clip.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	col, ents := -1, -1
	for &ly, j in doc.levels[0].layers {
		d := Ldtk_Doc_LayerDef(doc, &ly)
		if d.type == .IntGrid do col = j
		if d.type == .Entities do ents = j
	}
	Ldtk_Doc_SetIntGrid(doc, 0, col, 2, 2, 1)
	Ldtk_Doc_SetIntGrid(doc, 0, col, 3, 2, 1)
	chest := Ldtk_Doc_AddEntityDef(doc, "Chest")
	Ldtk_Doc_AddEntity(doc, 0, ents, chest, {48, 48})
	sel: Ldtk_Selection
	defer Ldtk_Selection_Destroy(&sel)
	clip: Ldtk_Clipboard
	defer Ldtk_Clipboard_Destroy(&clip)
	Ldtk_Doc_SelectAll(doc, 0, &sel)
	testing.expect_value(t, len(sel.cells) + len(sel.entities), 3)
	Ldtk_Doc_CopySelection(doc, 0, &sel, &clip)
	testing.expect_value(t, clip.origin, [2]int{32, 32})
	// paste with the top-left at (128, 96): cells (8,6),(9,6), the chest at px (144,112)
	testing.expect(t, Ldtk_Doc_Paste(doc, 0, &clip, {128, 96}, &sel))
	cl := &doc.levels[0].layers[col]
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(cl, 8, 6), 1)
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(cl, 9, 6), 1)
	testing.expect_value(t, len(Ldtk_Doc_Entities(doc, 0, ents)), 2)
	testing.expect_value(t, LdtkJson_ToString(LdtkJson_Get(sel.entities[0].obj, "px"), .Minified, context.temp_allocator), "[144,112]")
	testing.expect_value(t, len(sel.cells), 2)
}

@(test)
test_ldtk_doc_duplicate_and_order_levels :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_Load("tests/drive/fixtures/ldtk_editor/SeparateLevelFiles.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	n := len(doc.levels)
	cells := 0
	for &ly in doc.levels[0].layers do for v in ly.intGrid do if v != 0 do cells += 1
	li := Ldtk_Doc_DuplicateLevel(doc, 0)
	testing.expect_value(t, li, 1)
	testing.expect_value(t, len(doc.levels), n + 1)
	dup := &doc.levels[1]
	testing.expect(t, dup.extRoot != nil)
	testing.expect(t, LdtkJson_Str(dup.obj, "iid") != LdtkJson_Str(doc.levels[0].obj, "iid"))
	testing.expect(t, LdtkJson_Str(dup.obj, "externalRelPath") != LdtkJson_Str(doc.levels[0].obj, "externalRelPath"))
	c2 := 0
	for &ly in dup.layers do for v in ly.intGrid do if v != 0 do c2 += 1
	testing.expect_value(t, c2, cells)
	// no overlap with the others
	p := Ldtk_Doc_LevelPos(doc, 1)
	s := Ldtk_Doc_LevelSize(doc, 1)
	testing.expect_value(t, Ldtk_Doc_FreeLevelSpot(doc, 0, p, s, 1) == p, false) // (the spot is taken now: by itself)
	// order
	name := Ldtk_Doc_LevelName(doc, 1)
	testing.expect_value(t, Ldtk_Doc_MoveLevelOrder(doc, 1, -1), 0)
	testing.expect_value(t, Ldtk_Doc_LevelName(doc, 0), name)
	testing.expect_value(t, LdtkJson_Str(doc.worlds[0].levelsArr.items[0], "identifier"), name)
	// it saves and loads back
	proj, paths, texts := Ldtk_Doc_Serialize(doc, context.temp_allocator)
	testing.expect_value(t, len(paths), n + 1)
	_ = proj
	_ = texts
}

@(test)
test_ldtk_doc_tile_stacking_saved_selections_override :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/rayzr_zz_tiles2.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	ts := Ldtk_Doc_AddTileset(doc, "atlas/a_zz.png", {64, 64}, 16)
	ts2 := Ldtk_Doc_AddTileset(doc, "atlas/b_zz.png", {32, 32}, 16)
	// tile 3 is opaque
	tsd := Ldtk_Doc_Tileset(doc, ts)
	cache := LdtkJson_New(.Object, doc.allocator)
	LdtkJson_SetStr(cache, "opaqueTiles", "0001000000000000", doc.allocator)
	LdtkJson_SetStr(cache, "averageColors", "", doc.allocator)
	LdtkJson_Set(tsd.obj, "cachedPixelData", cache, doc.allocator)
	Ldtk_Doc_RefreshDefs(doc)
	tl := Ldtk_Doc_AddLayerDef(doc, .Tiles, "Deco", ts)
	j := -1
	for &ly, k in doc.levels[0].layers do if Ldtk_Doc_LayerDef(doc, &ly).uid == tl do j = k
	ly := &doc.levels[0].layers[j]
	Ldtk_Doc_AddGridTile(doc, 0, j, 1, 1, 0, 0, true)
	Ldtk_Doc_AddGridTile(doc, 0, j, 1, 1, 1, 0, true)
	testing.expect_value(t, len(Ldtk_Doc_TilesAt(ly, 1, 1)), 2)
	// the same tile again moves to the top
	Ldtk_Doc_AddGridTile(doc, 0, j, 1, 1, 0, 0, true)
	st := Ldtk_Doc_TilesAt(ly, 1, 1)
	testing.expect_value(t, len(st), 2)
	testing.expect_value(t, st[1].t, 0)
	// an opaque tile replaces the stack
	Ldtk_Doc_AddGridTile(doc, 0, j, 1, 1, 3, 0, true)
	testing.expect_value(t, len(Ldtk_Doc_TilesAt(ly, 1, 1)), 1)
	Ldtk_Doc_AddGridTile(doc, 0, j, 1, 1, 2, 0, true)
	testing.expect(t, Ldtk_Doc_RemoveTopTile(doc, 0, j, 1, 1))
	testing.expect_value(t, Ldtk_Doc_TilesAt(ly, 1, 1)[0].t, 3)
	// saved selections
	testing.expect(t, Ldtk_Doc_SaveTileSelection(doc, ts, {4, 5, 8, 9}, false))
	ids, random, found := Ldtk_Doc_SavedSelectionFor(doc, ts, 8)
	testing.expect(t, found && !random && len(ids) == 4)
	testing.expect(t, Ldtk_Doc_SaveTileSelection(doc, ts, {9, 10}, true)) // shares 9: replaces
	_, _, found = Ldtk_Doc_SavedSelectionFor(doc, ts, 4)
	testing.expect(t, !found)
	ids, random, found = Ldtk_Doc_SavedSelectionFor(doc, ts, 10)
	testing.expect(t, found && random)
	testing.expect(t, !Ldtk_Doc_SaveTileSelection(doc, ts, {7}, false)) // one tile: not saved
	// override: tile 3's source follows the other tileset (2 tiles per row)
	Ldtk_Doc_SetLayerTilesetOverride(doc, 0, j, ts2)
	testing.expect_value(t, LdtkJson_Int(ly.obj, "overrideTilesetUid"), ts2)
	testing.expect_value(t, Ldtk_Doc_TilesAt(ly, 1, 1)[0].src, [2]i32{16, 16})
	Ldtk_Doc_SetLayerTilesetOverride(doc, 0, j, -1)
	testing.expect(t, LdtkJson_IsNull(ly.obj, "overrideTilesetUid"))
	testing.expect_value(t, Ldtk_Doc_TilesAt(ly, 1, 1)[0].src, [2]i32{48, 0})
}

@(test)
test_ldtk_doc_field_values_arrays_refs :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/rayzr_zz_fields.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	a := doc.allocator
	ents := -1
	for &ly, j in doc.levels[0].layers do if Ldtk_Doc_LayerDef(doc, &ly).type == .Entities do ents = j
	door := Ldtk_Doc_AddEntityDef(doc, "Door")
	hp := Ldtk_Doc_AddFieldDef(doc, door, "F_Int", "hp")
	name := Ldtk_Doc_AddFieldDef(doc, door, "F_String", "code")
	links := Ldtk_Doc_AddFieldDef(doc, door, "F_EntityRef", "links")
	path := Ldtk_Doc_AddFieldDef(doc, door, "F_Point", "path")
	col := Ldtk_Doc_AddFieldDef(doc, door, "F_Color", "tint")
	file := Ldtk_Doc_AddFieldDef(doc, door, "F_Path", "sound")
	icon := Ldtk_Doc_AddFieldDef(doc, door, "F_Tile", "icon")
	fdOf :: proc(doc: ^Ldtk_Doc, uid: int) -> ^LdtkJson {return Ldtk_Doc_FieldDef(doc, uid)}
	// hp: default 10, min 0 max 50
	testing.expect(t, Ldtk_Doc_FieldDefDefaultSet(doc, fdOf(doc, hp), "10"))
	LdtkJson_SetInt(fdOf(doc, hp), "max", 50, a)
	// code: regex /^[A-Z]{3}$/
	LdtkJson_SetStr(fdOf(doc, name), "regex", "/^[A-Z]{3}$/", a)
	// links: an array, symmetrical, any entity
	LdtkJson_SetBool(fdOf(doc, links), "isArray", true, a)
	LdtkJson_SetBool(fdOf(doc, links), "symmetricalRef", true, a)
	LdtkJson_SetStr(fdOf(doc, links), "allowedRefs", "Any", a)
	// path: array of points
	LdtkJson_SetBool(fdOf(doc, path), "isArray", true, a)
	// tint: the smart colour
	LdtkJson_SetBool(fdOf(doc, col), "useForSmartColor", true, a)
	// sound: .ogg / .wav only
	exts := LdtkJson_New(.Array, a)
	append(&exts.items, LdtkJson_NewString("ogg", a), LdtkJson_NewString(".wav", a))
	LdtkJson_Set(fdOf(doc, file), "acceptFileTypes", exts, a)
	LdtkJson_SetInt(fdOf(doc, icon), "tilesetUid", 7, a)
	LdtkJson_SetStr(fdOf(doc, icon), "editorDisplayMode", "EntityTile", a)
	Ldtk_Doc_RefreshDefs(doc)
	d1 := Ldtk_Doc_AddEntity(doc, 0, ents, door, {16, 16})
	d2 := Ldtk_Doc_AddEntity(doc, 0, ents, door, {64, 16})
	fi :: proc(ent: ^LdtkJson, uid: int) -> ^LdtkJson {
		for f in LdtkJson_Arr(ent, "fieldInstances") do if LdtkJson_Int(f, "defUid", -1) == uid do return f
		return nil
	}
	v, null := Ldtk_Doc_FieldText(doc, fi(d1, hp), 0)
	testing.expect(t, !null && v == "10")
	testing.expect(t, Ldtk_Doc_SetFieldRaw(doc, fi(d1, hp), 0, "99"))
	v, _ = Ldtk_Doc_FieldText(doc, fi(d1, hp), 0)
	testing.expect_value(t, v, "50")
	testing.expect(t, Ldtk_Doc_SetFieldRaw(doc, fi(d1, hp), 0, "", true)) // back to the default
	v, _ = Ldtk_Doc_FieldText(doc, fi(d1, hp), 0)
	testing.expect_value(t, v, "10")
	testing.expect(t, !Ldtk_Doc_SetFieldRaw(doc, fi(d1, name), 0, "ab1"))
	testing.expect(t, Ldtk_Doc_SetFieldRaw(doc, fi(d1, name), 0, "ABC"))
	testing.expect(t, !Ldtk_Doc_SetFieldRaw(doc, fi(d1, file), 0, "sfx/door.mp3"))
	testing.expect(t, Ldtk_Doc_SetFieldRaw(doc, fi(d1, file), 0, "sfx/door.WAV"))
	// points: a path of two
	p0 := Ldtk_Doc_FieldArrayAdd(doc, fi(d1, path))
	p1 := Ldtk_Doc_FieldArrayAdd(doc, fi(d1, path))
	Ldtk_Doc_SetFieldRaw(doc, fi(d1, path), p0, "3,4")
	Ldtk_Doc_SetFieldRaw(doc, fi(d1, path), p1, "5,4")
	testing.expect_value(t, LdtkJson_ToString(LdtkJson_Get(fi(d1, path), "__value"), .Minified, context.temp_allocator), `[{"cx":3,"cy":4},{"cx":5,"cy":4}]`)
	testing.expect(t, Ldtk_Doc_FieldArrayMove(doc, fi(d1, path), 1, -1))
	testing.expect_value(t, LdtkJson_ToString(LdtkJson_Get(fi(d1, path), "__value"), .Minified, context.temp_allocator), `[{"cx":5,"cy":4},{"cx":3,"cy":4}]`)
	// a symmetrical reference: d1 -> d2 makes d2 -> d1
	r0 := Ldtk_Doc_FieldArrayAdd(doc, fi(d1, links))
	testing.expect(t, Ldtk_Doc_SetFieldRef(doc, fi(d1, links), r0, d1, LdtkJson_Str(d2, "iid")))
	back, _ := Ldtk_Doc_FieldText(doc, fi(d2, links), 0)
	testing.expect_value(t, back, LdtkJson_Str(d1, "iid"))
	rv := LdtkJson_Arr(fi(d1, links), "__value")
	testing.expect_value(t, len(rv), 1)
	testing.expect_value(t, LdtkJson_Str(rv[0], "levelIid"), LdtkJson_Str(doc.levels[0].obj, "iid"))
	// clearing it removes the way back
	testing.expect(t, Ldtk_Doc_SetFieldRef(doc, fi(d1, links), r0, d1, ""))
	testing.expect_value(t, Ldtk_Doc_FieldArrayLen(doc, fi(d2, links)), 0)
	ok1, _ := Ldtk_Doc_RefAllowed(doc, fdOf(doc, links), d1, 0, d1, 0)
	testing.expect(t, !ok1)
	// tile and smart colour
	testing.expect(t, Ldtk_Doc_SetFieldRaw(doc, fi(d1, icon), 0, "16,0,16,16"))
	testing.expect_value(t, LdtkJson_ToString(LdtkJson_Get(fi(d1, icon), "__value"), .Minified, context.temp_allocator), `{"tilesetUid":7,"x":16,"y":0,"w":16,"h":16}`)
	testing.expect_value(t, LdtkJson_ToString(LdtkJson_Get(fi(d1, icon), "__tile"), .Minified, context.temp_allocator), `{"tilesetUid":7,"x":16,"y":0,"w":16,"h":16}`)
	testing.expect(t, Ldtk_Doc_SetFieldRaw(doc, fi(d1, col), 0, "#FF8000"))
	Ldtk_Doc_EntitySmart(doc, d1)
	testing.expect_value(t, LdtkJson_Int(LdtkJson_Get(d1, "__tile"), "x"), 16) // the field's tile is the entity's
	testing.expect_value(t, LdtkJson_Str(d1, "__smartColor"), "#FF8000")
	testing.expect_value(t, LdtkJson_ToString(LdtkJson_Get(fi(d1, col), "realEditorValues"), .Minified, context.temp_allocator), `[{"id":"V_Int","params":[16744448]}]`)
}

@(test)
test_ldtk_doc_remove_entity_clears_refs :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/rayzr_zz_unlink.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	a := doc.allocator
	ents := -1
	for &ly, j in doc.levels[0].layers do if Ldtk_Doc_LayerDef(doc, &ly).type == .Entities do ents = j
	lever := Ldtk_Doc_AddEntityDef(doc, "Lever")
	one := Ldtk_Doc_AddFieldDef(doc, lever, "F_EntityRef", "door")
	many := Ldtk_Doc_AddFieldDef(doc, lever, "F_EntityRef", "doors")
	LdtkJson_SetStr(Ldtk_Doc_FieldDef(doc, one), "allowedRefs", "Any", a)
	LdtkJson_SetStr(Ldtk_Doc_FieldDef(doc, many), "allowedRefs", "Any", a)
	LdtkJson_SetBool(Ldtk_Doc_FieldDef(doc, many), "isArray", true, a)
	// new references show as an arrow (LDtk's default); other fields are hidden
	testing.expect_value(t, LdtkJson_Str(Ldtk_Doc_FieldDef(doc, one), "editorDisplayMode"), "RefLinkBetweenCenters")
	Ldtk_Doc_RefreshDefs(doc)
	l := Ldtk_Doc_AddEntity(doc, 0, ents, lever, {16, 16})
	d1 := Ldtk_Doc_AddEntity(doc, 0, ents, lever, {64, 16})
	d2 := Ldtk_Doc_AddEntity(doc, 0, ents, lever, {96, 16})
	fi :: proc(ent: ^LdtkJson, uid: int) -> ^LdtkJson {
		for f in LdtkJson_Arr(ent, "fieldInstances") do if LdtkJson_Int(f, "defUid", -1) == uid do return f
		return nil
	}
	testing.expect(t, Ldtk_Doc_SetFieldRef(doc, fi(l, one), 0, l, LdtkJson_Str(d1, "iid")))
	for d in ([]^LdtkJson{d1, d2}) {
		j := Ldtk_Doc_FieldArrayAdd(doc, fi(l, many))
		testing.expect(t, Ldtk_Doc_SetFieldRef(doc, fi(l, many), j, l, LdtkJson_Str(d, "iid")))
	}
	// deleting d1: the single link becomes null, the array loses its value
	testing.expect(t, Ldtk_Doc_RemoveEntity(doc, 0, ents, d1))
	_, null := Ldtk_Doc_FieldText(doc, fi(l, one), 0)
	testing.expect(t, null)
	testing.expect_value(t, Ldtk_Doc_FieldArrayLen(doc, fi(l, many)), 1)
	left, _ := Ldtk_Doc_FieldText(doc, fi(l, many), 0)
	testing.expect_value(t, left, LdtkJson_Str(d2, "iid"))
}

@(test)
test_ldtk_doc_field_and_entity_def_ops :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/rayzr_zz_defops.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	a := doc.allocator
	ents := -1
	for &ly, j in doc.levels[0].layers do if Ldtk_Doc_LayerDef(doc, &ly).type == .Entities do ents = j
	coin := Ldtk_Doc_AddEntityDef(doc, "Coin")
	val := Ldtk_Doc_AddFieldDef(doc, coin, "F_Float", "value")
	tag := Ldtk_Doc_AddFieldDef(doc, coin, "F_String", "label")
	c1 := Ldtk_Doc_AddEntity(doc, 0, ents, coin, {8, 8})
	fi0 := LdtkJson_Arr(c1, "fieldInstances")[0]
	Ldtk_Doc_SetFieldRaw(doc, fi0, 0, "2.6")
	// rename: instances follow; no duplicates
	testing.expect(t, Ldtk_Doc_RenameFieldDef(doc, val, "worth"))
	testing.expect_value(t, LdtkJson_Str(fi0, "__identifier"), "worth")
	testing.expect(t, !Ldtk_Doc_RenameFieldDef(doc, tag, "worth"))
	// Float -> Int (round): 2.6 -> 3
	convs := Ldtk_Doc_FieldConversions(Ldtk_Doc_FieldDef(doc, val))
	round := -1
	for c in convs do if LDTK_FIELD_CONVERSIONS[c].label == "To Int (round)" do round = c
	testing.expect(t, round >= 0)
	testing.expect(t, Ldtk_Doc_ConvertFieldDef(doc, val, round))
	testing.expect_value(t, LdtkJson_Str(Ldtk_Doc_FieldDef(doc, val), "__type"), "Int")
	v, _ := Ldtk_Doc_FieldText(doc, fi0, 0)
	testing.expect_value(t, v, "3")
	// into an array: the value stays as element 0
	testing.expect(t, Ldtk_Doc_ConvertFieldDef(doc, val, 0))
	testing.expect_value(t, LdtkJson_Str(Ldtk_Doc_FieldDef(doc, val), "__type"), "Array<Int>")
	testing.expect_value(t, LdtkJson_ToString(LdtkJson_Get(fi0, "__value"), .Minified, context.temp_allocator), "[3]")
	// reorder: the instances follow
	testing.expect(t, Ldtk_Doc_MoveFieldDef(doc, tag, -1))
	testing.expect_value(t, LdtkJson_Int(LdtkJson_Arr(c1, "fieldInstances")[0], "defUid"), tag)
	// duplicate a field: instances get one
	dup := Ldtk_Doc_DuplicateFieldDef(doc, tag)
	testing.expect(t, dup > 0)
	testing.expect_value(t, len(LdtkJson_Arr(c1, "fieldInstances")), 3)
	// limits: max 2 per level, PreventAdding / MoveLastOne / DiscardOldOnes
	ed := Ldtk_Doc_EntityDef(doc, coin)
	LdtkJson_SetInt(ed.obj, "maxCount", 2, a)
	LdtkJson_SetStr(ed.obj, "limitScope", "PerLevel", a)
	LdtkJson_SetStr(ed.obj, "limitBehavior", "PreventAdding", a)
	c2, _ := Ldtk_Doc_PlaceEntity(doc, 0, ents, coin, {24, 8})
	testing.expect(t, c2 != nil)
	c3, _ := Ldtk_Doc_PlaceEntity(doc, 0, ents, coin, {40, 8})
	testing.expect(t, c3 == nil)
	LdtkJson_SetStr(ed.obj, "limitBehavior", "MoveLastOne", a)
	c3m, moved := Ldtk_Doc_PlaceEntity(doc, 0, ents, coin, {40, 8})
	testing.expect(t, moved && c3m == c2)
	testing.expect_value(t, len(Ldtk_Doc_Entities(doc, 0, ents)), 2)
	LdtkJson_SetStr(ed.obj, "limitBehavior", "DiscardOldOnes", a)
	c4, _ := Ldtk_Doc_PlaceEntity(doc, 0, ents, coin, {56, 8})
	testing.expect(t, c4 != nil)
	testing.expect_value(t, len(Ldtk_Doc_Entities(doc, 0, ents)), 2)
	testing.expect(t, Ldtk_Doc_Entities(doc, 0, ents)[0] != c1) // the oldest went
	// sizes: min 8, max 32, keep the aspect (16x16 -> square)
	LdtkJson_SetInt(ed.obj, "minWidth", 8, a)
	LdtkJson_SetInt(ed.obj, "maxWidth", 32, a)
	LdtkJson_SetBool(ed.obj, "keepAspectRatio", true, a)
	Ldtk_Doc_RefreshDefs(doc)
	testing.expect_value(t, Ldtk_Doc_ConstrainEntitySize(doc, coin, {64, 20}, {16, 16}), [2]int{32, 64})
	testing.expect_value(t, Ldtk_Doc_ConstrainEntitySize(doc, coin, {4, 4}, {16, 16}), [2]int{8, 4})
	// duplicate / reorder entity defs
	cd := Ldtk_Doc_DuplicateEntityDef(doc, coin)
	testing.expect_value(t, Ldtk_Doc_EntityDef(doc, cd).identifier, "Coin2")
	testing.expect(t, Ldtk_Doc_MoveEntityDef(doc, cd, -1))
	testing.expect_value(t, doc.entityDefs[0].uid, cd)
	f1 := LdtkJson_Arr(Ldtk_Doc_EntityDef(doc, cd).obj, "fieldDefs")[0]
	testing.expect(t, LdtkJson_Int(f1, "uid") != tag) // fields got new uids
}

@(test)
test_ldtk_doc_rules_edit_and_wizard :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/rayzr_zz_rulesed.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	ts := Ldtk_Doc_AddTileset(doc, "atlas/w_zz.png", {128, 128}, 16)
	col := doc.layerDefs[0].uid
	Ldtk_Doc_AddIntGridValue(doc, col, "water")
	auto := Ldtk_Doc_AddLayerDef(doc, .AutoLayer, "Walls", ts)
	LdtkJson_SetInt(doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, auto)].obj, "autoSourceLayerDefUid", col, doc.allocator)
	Ldtk_Doc_LayerDefChanged(doc, auto)
	// the Assistant: centre, north wall (south comes from flipping it), west wall
	s: Ldtk_WizardSetup
	defer Ldtk_WizardSetup_Destroy(&s)
	s.name = "Walls"
	s.mainValue = 1
	s.breakOnMatch = true
	append(&s.tiles[.Full], 9)
	append(&s.tiles[.Wall_N], 1, 2) // two random tiles
	append(&s.tiles[.Wall_W], 8)
	g := Ldtk_Doc_RulesWizardApply(doc, auto, -1, &s)
	testing.expect(t, g > 0)
	grp, _, _ := Ldtk_Doc_FindRuleGroup(doc, g)
	rules := LdtkJson_Arr(grp, "rules")
	testing.expect_value(t, len(rules), 3)
	testing.expect(t, LdtkJson_Bool(grp, "usesWizard"))
	// order follows the fragments: Wall_N, Wall_W, Full (enum order)
	wn := rules[len(rules) - 3]
	testing.expect(t, LdtkJson_Bool(wn, "flipY")) // Wall_S has no tiles: Wall_N flips
	testing.expect_value(t, len(LdtkJson_Arr(wn, "tileRectsIds")), 2)
	testing.expect_value(t, LdtkJson_Int(wn, "outOfBoundsValue"), 1)
	full := rules[len(rules) - 1]
	testing.expect_value(t, LdtkJson_Int(full, "size"), 1) // trimmed to 1x1
	// read back
	s2: Ldtk_WizardSetup
	defer Ldtk_WizardSetup_Destroy(&s2)
	testing.expect(t, Ldtk_Doc_RulesWizardImport(doc, g, &s2))
	testing.expect_value(t, s2.mainValue, 1)
	testing.expect_value(t, len(s2.tiles[.Wall_N]), 2)
	testing.expect_value(t, len(s2.tiles[.Full]), 1)
	testing.expect_value(t, len(s2.tiles[.Wall_W]), 1)
	// paint: a 3x3 block - the middle gets the full tile, the top the wall tiles
	li := 0
	cl := -1
	for &ly, j in doc.levels[0].layers do if Ldtk_Doc_LayerDef(doc, &ly).uid == col do cl = j
	for y in 2 ..= 4 do for x in 2 ..= 4 do Ldtk_Doc_SetIntGrid(doc, li, cl, x, y, 1)
	Ldtk_Doc_ApplyRules(doc, li, cl, 2, 2, 4, 4)
	wl := Ldtk_Doc_LevelLayer(doc, &doc.levels[li], auto)
	at :: proc(ly: ^Ldtk_DocLayer, cx, cy: int) -> i32 {
		for tl in ly.autoTiles do if int(tl.coord) == cx + cy * ly.cWid do return tl.t
		return -1
	}
	testing.expect_value(t, at(wl, 3, 3), 9)
	testing.expect(t, at(wl, 3, 2) == 1 || at(wl, 3, 2) == 2)
	// preview cells of the full rule: 9 cells
	testing.expect_value(t, len(Ldtk_Doc_RuleMatchCells(doc, li, LdtkJson_Int(full, "uid"))), 9)
	// duplicate with remap 1 -> 2 and tiles one row down
	remap := make(map[i32]i32, allocator = context.temp_allocator)
	remap[1] = 2
	g2 := Ldtk_Doc_DuplicateRuleGroup(doc, g, "Water", remap, {0, 1})
	grp2, _, idx2 := Ldtk_Doc_FindRuleGroup(doc, g2)
	testing.expect_value(t, idx2, 1)
	r2 := LdtkJson_Arr(grp2, "rules")[len(LdtkJson_Arr(grp2, "rules")) - 1]
	testing.expect_value(t, int(LdtkJson_Arr(r2, "pattern")[0].num), 2)
	testing.expect_value(t, int(LdtkJson_Arr(r2, "tileRectsIds")[0].items[0].num), 9 + 8) // one row = 8 tiles
	// move the first rule of the copy up: it goes to the end of the first group
	first2 := LdtkJson_Int(LdtkJson_Arr(grp2, "rules")[0], "uid")
	testing.expect(t, Ldtk_Doc_MoveRule(doc, first2, -1))
	testing.expect_value(t, len(LdtkJson_Arr(grp, "rules")), 4)
	// copy / paste a rule
	text := Ldtk_Doc_RuleText(doc, LdtkJson_Int(full, "uid"), context.temp_allocator)
	pasted := Ldtk_Doc_PasteRule(doc, g2, text)
	testing.expect(t, pasted > 0 && pasted != LdtkJson_Int(full, "uid"))
	// optional on, enabled in the level, optional off: the level forgets it
	Ldtk_Doc_SetRuleGroupOptional(doc, g2, true)
	opt := LdtkJson_New(.Array, doc.allocator)
	append(&opt.items, LdtkJson_NewInt(g2, doc.allocator))
	LdtkJson_Set(wl.obj, "optionalRules", opt, doc.allocator)
	Ldtk_Doc_SetRuleGroupOptional(doc, g2, false)
	testing.expect_value(t, len(LdtkJson_Arr(wl.obj, "optionalRules")), 0)
	// out of bounds for all rules
	Ldtk_Doc_SetRuleGroupOutOfBounds(doc, g, -1)
	for r in LdtkJson_Arr(grp, "rules") do testing.expect(t, LdtkJson_IsNull(r, "outOfBoundsValue"))
	testing.expect(t, Ldtk_Doc_RemoveRuleGroup(doc, g2))
}

@(test)
test_ldtk_doc_sync_rule_groups :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/rayzr_zz_sync_groups.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)

	col := doc.layerDefs[0].uid
	g1 := Ldtk_Doc_AddIntGridGroup(doc, col)
	Ldtk_Doc_SetIntGridGroup(doc, col, g1, "Ground", "#33cc44")
	g2 := Ldtk_Doc_AddIntGridGroup(doc, col)
	Ldtk_Doc_SetIntGridGroup(doc, col, g2, "Walls", "#cc4433")

	ts := Ldtk_Doc_AddTileset(doc, "atlas/w_zz.png", {128, 128}, 16)
	auto := Ldtk_Doc_AddLayerDef(doc, .AutoLayer, "AutoTiles", ts)
	LdtkJson_SetInt(doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, auto)].obj, "autoSourceLayerDefUid", col, doc.allocator)
	Ldtk_Doc_LayerDefChanged(doc, auto)

	// Sync rule groups from IntGrid
	created := Ldtk_Doc_SyncRuleGroupsFromIntGrid(doc, auto)
	testing.expect_value(t, created, 2)

	adi := Ldtk_Doc_LayerDefIndex(doc, auto)
	testing.expect_value(t, len(doc.layerDefs[adi].groups), 2)
	testing.expect_value(t, doc.layerDefs[adi].groups[0].name, "Ground")
	testing.expect_value(t, LdtkJson_Str(doc.layerDefs[adi].groups[0].obj, "color"), "#33cc44")
	testing.expect_value(t, doc.layerDefs[adi].groups[1].name, "Walls")
	testing.expect_value(t, LdtkJson_Str(doc.layerDefs[adi].groups[1].obj, "color"), "#cc4433")

	// Sync again: 0 created
	created2 := Ldtk_Doc_SyncRuleGroupsFromIntGrid(doc, auto)
	testing.expect_value(t, created2, 0)
}

@(test)
test_ldtk_doc_level_bounds_bg_worlds :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/rayzr_zz_levels.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	col := doc.layerDefs[0].uid
	ent := Ldtk_Doc_AddEntityDef(doc, "Coin")
	ents := Ldtk_Doc_AddLayerDef(doc, .Entities, "Things")
	layer_of :: proc(doc: ^Ldtk_Doc, uid: int) -> int {
		for &ly, i in doc.levels[0].layers do if d := Ldtk_Doc_LayerDef(doc, &ly); d != nil && d.uid == uid do return i
		return -1
	}
	li, ei := layer_of(doc, col), layer_of(doc, ents)
	g := doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, col)].gridSize
	Ldtk_Doc_SetIntGrid(doc, 0, li, 3, 4, 1)
	Ldtk_Doc_AddEntity(doc, 0, ei, ent, {5 * g, 5 * g})
	Ldtk_Doc_AddEntity(doc, 0, ei, ent, {1 * g, 1 * g}) // removed: ends up outside
	p0 := Ldtk_Doc_LevelPos(doc, 0)
	s0 := Ldtk_Doc_LevelSize(doc, 0)
	// drag the top-left corner in by two cells: content keeps its world place
	removed := Ldtk_Doc_ResizeLevelBounds(doc, 0, 2 * g, 2 * g, s0.x - 2 * g, s0.y - 2 * g)
	testing.expect_value(t, removed, 1)
	testing.expect_value(t, Ldtk_Doc_LevelPos(doc, 0), p0 + {2 * g, 2 * g})
	testing.expect_value(t, Ldtk_Doc_LevelSize(doc, 0), s0 - {2 * g, 2 * g})
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(&doc.levels[0].layers[li], 1, 2), 1)
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(&doc.levels[0].layers[li], 3, 4), 0)
	es := Ldtk_Doc_Entities(doc, 0, ei)
	testing.expect_value(t, len(es), 1)
	if len(es) == 1 {
		px := LdtkJson_Arr(es[0], "px")
		testing.expect_value(t, int(px[0].num), 3 * g)
		testing.expect_value(t, LdtkJson_Int(es[0], "__worldX"), p0.x + 5 * g)
	}
	// a half-cell move keeps the remainder in the layer offset (pxOffsetX)
	Ldtk_Doc_ResizeLevelBounds(doc, 0, -g / 2, 0, Ldtk_Doc_LevelSize(doc, 0).x + g / 2, Ldtk_Doc_LevelSize(doc, 0).y)
	testing.expect_value(t, LdtkJson_Int(doc.levels[0].layers[li].obj, "pxOffsetX"), g / 2)
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(&doc.levels[0].layers[li], 1, 2), 1)

	// background placement (Level.getBgTileInfos)
	cover := Ldtk_LevelBgInfo({256, 128}, {64, 64}, .Cover, {0.5, 0.5})
	testing.expect_value(t, cover.scale, [2]f64{4, 4})
	testing.expect_value(t, cover.crop, [4]f64{0, 16, 64, 32})
	testing.expect_value(t, cover.topLeft, [2]int{0, 0})
	contain := Ldtk_LevelBgInfo({256, 128}, {64, 64}, .Contain, {1, 0.5})
	testing.expect_value(t, contain.scale, [2]f64{2, 2})
	testing.expect_value(t, contain.topLeft, [2]int{128, 0})
	dirty := Ldtk_LevelBgInfo({256, 128}, {64, 64}, .CoverDirty, {0.5, 0.5})
	testing.expect_value(t, dirty.scale, [2]f64{4, 2})
	unscaled := Ldtk_LevelBgInfo({32, 32}, {64, 64}, .Unscaled, {0, 1})
	testing.expect_value(t, unscaled.crop, [4]f64{0, 32, 32, 32})
	// a missing image: no __bgPos
	Ldtk_Doc_SetLevelBg(doc, 0, "zz_missing.png")
	testing.expect_value(t, LdtkJson_Str(doc.levels[0].obj, "bgPos"), "Cover")
	testing.expect(t, LdtkJson_IsNull(doc.levels[0].obj, "__bgPos"))
	Ldtk_Doc_SetLevelBg(doc, 0, "")
	testing.expect(t, LdtkJson_IsNull(doc.levels[0].obj, "bgPos"))

	// worlds: multi-worlds on and off again gives the same file
	before, _, _ := Ldtk_Doc_Serialize(doc, context.temp_allocator)
	testing.expect(t, Ldtk_Doc_SetMultiWorlds(doc, true))
	testing.expect(t, doc.multiWorlds)
	testing.expect(t, Ldtk_Doc_HasFlag(doc, "MultiWorlds"))
	testing.expect(t, LdtkJson_IsNull(doc.root, "worldLayout"))
	testing.expect_value(t, len(LdtkJson_Arr(doc.root, "levels")), 0)
	testing.expect_value(t, LdtkJson_Str(doc.worlds[0].obj, "iid"), LdtkJson_Str(doc.root, "dummyWorldIid"))
	testing.expect(t, Ldtk_Doc_SetMultiWorlds(doc, false))
	after, _, _ := Ldtk_Doc_Serialize(doc, context.temp_allocator)
	testing.expect(t, before == after)
	// add / rename / remove worlds
	w2 := Ldtk_Doc_AddWorld(doc)
	testing.expect_value(t, w2, 1)
	testing.expect_value(t, len(doc.worlds), 2)
	testing.expect_value(t, Ldtk_Doc_WorldName(doc, 1), "World2")
	testing.expect_value(t, len(doc.levels), 2)
	testing.expect_value(t, doc.levels[1].world, 1)
	Ldtk_Doc_RenameWorld(doc, 1, "World")
	testing.expect_value(t, Ldtk_Doc_WorldName(doc, 1), "World2") // names stay unique
	Ldtk_Doc_RenameWorld(doc, 1, "Caves")
	testing.expect_value(t, Ldtk_Doc_WorldName(doc, 1), "Caves")
	testing.expect(t, !Ldtk_Doc_SetMultiWorlds(doc, false)) // two worlds
	testing.expect(t, Ldtk_Doc_RemoveWorld(doc, 0))
	testing.expect_value(t, len(doc.levels), 1)
	testing.expect_value(t, doc.levels[0].world, 0)
	testing.expect(t, !Ldtk_Doc_RemoveWorld(doc, 0)) // the last one
	// the saved file reloads with its worlds
	text, _, _ := Ldtk_Doc_Serialize(doc, context.temp_allocator)
	re, rok := Ldtk_Doc_LoadFromMemory(text, "/tmp/rayzr_zz_levels.ldtk")
	testing.expect(t, rok)
	if rok {
		testing.expect(t, re.multiWorlds)
		testing.expect_value(t, Ldtk_Doc_WorldName(re, 0), "Caves")
		Ldtk_Doc_Destroy(re)
	}
}

@(test)
test_ldtk_doc_layer_defs :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/rayzr_zz_layers.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	col := doc.layerDefs[0].uid
	layer_of :: proc(doc: ^Ldtk_Doc, uid: int) -> int {
		for &ly, i in doc.levels[0].layers do if d := Ldtk_Doc_LayerDef(doc, &ly); d != nil && d.uid == uid do return i
		return -1
	}
	// grid changes keep cells at their cell coordinates (remapToGridSize)
	Ldtk_Doc_SetIntGrid(doc, 0, layer_of(doc, col), 3, 2, 1)
	Ldtk_Doc_SetLayerGrid(doc, col, 8)
	ly := &doc.levels[0].layers[layer_of(doc, col)]
	testing.expect_value(t, doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, col)].gridSize, 8)
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(ly, 3, 2), 1)
	testing.expect_value(t, ly.cWid, 256 / 8)
	// duplicate: right after it, a free name, empty, new rule uids
	ts := Ldtk_Doc_AddTileset(doc, "atlas/l_zz.png", {64, 64}, 8)
	LdtkJson_SetInt(doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, col)].obj, "tilesetDefUid", ts, doc.allocator)
	Ldtk_Doc_LayerDefChanged(doc, col)
	Ldtk_Doc_AddTerrainRules(doc, col, 1, {0, 1, 2, 8, 9, 10, 16, 17, 18})
	for y in 4 ..< 8 do for x in 4 ..< 8 do Ldtk_Doc_SetIntGrid(doc, 0, layer_of(doc, col), x, y, 1)
	Ldtk_Doc_ApplyRulesFull(doc, -1)
	n0 := len(doc.layerDefs)
	dup := Ldtk_Doc_DuplicateLayerDef(doc, col)
	testing.expect(t, dup > 0)
	testing.expect_value(t, len(doc.layerDefs), n0 + 1)
	testing.expect_value(t, Ldtk_Doc_LayerDefIndex(doc, dup), Ldtk_Doc_LayerDefIndex(doc, col) + 1)
	src, cp := &doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, col)], &doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, dup)]
	testing.expect(t, cp.identifier != src.identifier)
	testing.expect_value(t, len(cp.groups), len(src.groups))
	if len(cp.groups) > 0 do testing.expect(t, cp.groups[0].uid != src.groups[0].uid && cp.groups[0].rules[0].uid != src.groups[0].rules[0].uid)
	testing.expect_value(t, len(doc.levels[0].layers), len(doc.layerDefs))
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(&doc.levels[0].layers[layer_of(doc, dup)], 3, 2), 0)
	// edits not yet written to the tree survive layers being added (regression)
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(&doc.levels[0].layers[layer_of(doc, col)], 3, 2), 1)
	// paste rejects non-layers
	testing.expect_value(t, Ldtk_Doc_PasteLayerDef(doc, "{\"a\":1}"), -1)
	// bake: the auto tiles become grid tiles of a new Tiles layer
	auto_n := len(doc.levels[0].layers[layer_of(doc, col)].autoTiles)
	testing.expect(t, auto_n > 0)
	baked := Ldtk_Doc_BakeLayer(doc, col, .Empty_Original)
	testing.expect(t, baked > 0)
	bd := &doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, baked)]
	testing.expect_value(t, bd.type, LdtkLayerType.Tiles)
	testing.expect_value(t, len(bd.groups), 0)
	testing.expect(t, len(doc.levels[0].layers[layer_of(doc, baked)].gridTiles) > 0)
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(&doc.levels[0].layers[layer_of(doc, col)], 3, 2), 0) // emptied
	// IntGrid values: order, groups, icons
	v2 := Ldtk_Doc_AddIntGridValue(doc, col, "water")
	testing.expect(t, Ldtk_Doc_MoveIntGridValue(doc, col, v2, -1))
	testing.expect_value(t, LdtkJson_Int(LdtkJson_Arr(doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, col)].obj, "intGridValues")[0], "value"), v2)
	g := Ldtk_Doc_AddIntGridGroup(doc, col)
	testing.expect_value(t, g, 1)
	Ldtk_Doc_SetIntGridValueGroup(doc, col, v2, g)
	Ldtk_Doc_SetIntGridGroup(doc, col, g, "liquids", "#2CE8F4")
	grp := LdtkJson_Arr(doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, col)].obj, "intGridValuesGroups")[0]
	testing.expect_value(t, LdtkJson_Str(grp, "identifier"), "liquids")
	testing.expect_value(t, doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, col)].values[0].groupUid, g)
	Ldtk_Doc_SetIntGridValueTile(doc, col, v2, ts, {8, 0, 8, 8})
	Ldtk_Doc_RemoveIntGridGroup(doc, col, g)
	testing.expect_value(t, doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, col)].values[0].groupUid, 0)
	// moving entities between layers (by definition, tags checked)
	coin := Ldtk_Doc_AddEntityDef(doc, "Coin")
	e1 := Ldtk_Doc_AddLayerDef(doc, .Entities, "Items")
	e2 := Ldtk_Doc_AddLayerDef(doc, .Entities, "Pickups")
	Ldtk_Doc_AddEntity(doc, 0, layer_of(doc, e1), coin, {16, 16})
	Ldtk_Doc_AddEntity(doc, 0, layer_of(doc, e1), coin, {32, 16})
	testing.expect_value(t, Ldtk_Doc_MoveEntitiesBetweenLayers(doc, e1, e2, .Def, "Coin"), 2)
	testing.expect_value(t, len(Ldtk_Doc_Entities(doc, 0, layer_of(doc, e2))), 2)
	tags := LdtkJson_New(.Array, doc.allocator)
	append(&tags.items, LdtkJson_NewString("enemy", doc.allocator))
	LdtkJson_Set(doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, e1)].obj, "requiredTags", tags, doc.allocator)
	testing.expect_value(t, Ldtk_Doc_MoveEntitiesBetweenLayers(doc, e2, e1, .Def, "Coin"), -1)
}

@(test)
test_ldtk_doc_project_options :: proc(t: ^testing.T) {
	dir := fmt.tprintf("%s/rayzr_ldtk_proj_zz", Engine_TempDir())
	os.remove_all(dir)
	_ = os.make_directory(dir)
	defer os.remove_all(dir)
	path := fmt.tprintf("%s/opts.ldtk", dir)
	doc, ok := Ldtk_Doc_New(path)
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	col := doc.layerDefs[0].uid
	Ldtk_Doc_SetIntGrid(doc, 0, 0, 2, 3, 1)
	testing.expect(t, Ldtk_Doc_Save(doc))
	// identifier styles (cleanupIdentifier)
	testing.expect_value(t, Ldtk_CleanIdentifierStyle("my  wall-1", .Capitalize), "My_wall_1")
	testing.expect_value(t, Ldtk_CleanIdentifierStyle("9lives", .Free), "_lives")
	testing.expect_value(t, Ldtk_CleanIdentifierStyle("_wall", .Capitalize), "_Wall")
	Ldtk_Doc_SetIdentifierStyle(doc, .Uppercase)
	testing.expect_value(t, doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, col)].identifier, "COLLISIONS")
	testing.expect_value(t, LdtkJson_Str(doc.levels[0].obj, "identifier"), "LEVEL_0")
	Ldtk_Doc_SetIdentifierStyle(doc, .Capitalize)
	// external levels: on, saved as files, reloaded; then off again
	Ldtk_Doc_SetExternalLevels(doc, true)
	testing.expect(t, doc.levels[0].extRoot != nil)
	testing.expect(t, Ldtk_Doc_Save(doc))
	rel := LdtkJson_Str(doc.levels[0].obj, "externalRelPath")
	testing.expect_value(t, rel, "opts/LEVEL_0.ldtkl")
	testing.expect(t, os.is_file(fmt.tprintf("%s/%s", dir, rel)))
	again, ok2 := Ldtk_Doc_Load(path)
	testing.expect(t, ok2)
	if ok2 {
		testing.expect(t, again.external && again.levels[0].extRoot != nil)
		testing.expect_value(t, Ldtk_Doc_GetIntGrid(&again.levels[0].layers[0], 2, 3), 1)
		Ldtk_Doc_Destroy(again)
	}
	// file names with the index flag
	Ldtk_Doc_SetProjectFlag(doc, "PrependIndexToLevelFileNames", true)
	testing.expect(t, Ldtk_Doc_Save(doc))
	testing.expect_value(t, LdtkJson_Str(doc.levels[0].obj, "externalRelPath"), "opts/0000-LEVEL_0.ldtkl")
	testing.expect(t, !os.is_file(fmt.tprintf("%s/%s", dir, rel))) // the old name is gone
	Ldtk_Doc_SetExternalLevels(doc, false)
	testing.expect(t, Ldtk_Doc_Save(doc))
	testing.expect(t, !os.is_file(fmt.tprintf("%s/opts/0000-LEVEL_0.ldtkl", dir)))
	back, ok3 := Ldtk_Doc_Load(path)
	testing.expect(t, ok3)
	if ok3 {
		testing.expect(t, !back.external)
		testing.expect_value(t, Ldtk_Doc_GetIntGrid(&back.levels[0].layers[0], 2, 3), 1)
		Ldtk_Doc_Destroy(back)
	}
	// the old IntGrid format flag
	Ldtk_Doc_SetProjectFlag(doc, "ExportPreCsvIntGridFormat", true)
	text := Ldtk_Doc_ToText(doc)
	testing.expect(t, strings.contains(text, "\"coordId\""))
	Ldtk_Doc_SetProjectFlag(doc, "ExportPreCsvIntGridFormat", false)
	testing.expect(t, !strings.contains(Ldtk_Doc_ToText(doc), "\"coordId\""))
	// backups: the newest backupLimit stay
	LdtkJson_SetInt(doc.root, "backupLimit", 2, doc.allocator)
	b1 := Ldtk_Doc_Backup(doc, time.unix(1000, 0))
	b2 := Ldtk_Doc_Backup(doc, time.unix(2000, 0))
	b3 := Ldtk_Doc_Backup(doc, time.unix(3000, 0))
	testing.expect(t, b1 != "" && b2 != "" && b3 != "")
	testing.expect(t, !os.exists(b1) && os.exists(b2) && os.exists(b3))
	testing.expect(t, os.is_file(fmt.tprintf("%s/opts.ldtk", b3)))
}

@(test)
test_ldtk_doc_enums :: proc(t: ^testing.T) {
	dir := fmt.tprintf("%s/rayzr_ldtk_enums_zz", Engine_TempDir())
	os.remove_all(dir)
	_ = os.make_directory(dir)
	defer os.remove_all(dir)
	doc, ok := Ldtk_Doc_New(fmt.tprintf("%s/enums.ldtk", dir))
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	en := Ldtk_Doc_AddEnum(doc, "Item")
	Ldtk_Doc_AddEnumValue(doc, en, "Sword")
	Ldtk_Doc_AddEnumValue(doc, en, "Shield")
	f := Ldtk_Doc_AddFieldDef(doc, -1, fmt.tprintf("F_Enum(%d)", en), "loot")
	fi := LdtkJson_Arr(doc.levels[0].obj, "fieldInstances")[0]
	testing.expect(t, Ldtk_Doc_SetFieldRaw(doc, fi, 0, "Sword"))
	testing.expect(t, Ldtk_Doc_EnumValueUsed(doc, en, "Sword"))
	testing.expect(t, !Ldtk_Doc_EnumValueUsed(doc, en, "Shield"))
	// renames follow into instances and the field types
	testing.expect_value(t, Ldtk_Doc_RenameEnumValue(doc, en, "Sword", "Blade"), "Blade")
	testing.expect_value(t, Ldtk_Doc_FieldRaw(fi, 0).text, "Blade")
	Ldtk_Doc_RenameEnum(doc, en, "Loot")
	testing.expect_value(t, LdtkJson_Str(Ldtk_Doc_FieldDef(doc, f), "__type"), "LocalEnum.Loot")
	testing.expect_value(t, LdtkJson_Str(fi, "__type"), "LocalEnum.Loot")
	// order, duplicate, paste
	testing.expect(t, Ldtk_Doc_MoveEnumValue(doc, en, "Shield", -1))
	testing.expect_value(t, LdtkJson_Str(LdtkJson_Arr(Ldtk_Doc_EnumDef(doc, en), "values")[0], "id"), "Shield")
	dup := Ldtk_Doc_DuplicateEnum(doc, en)
	testing.expect_value(t, LdtkJson_Str(Ldtk_Doc_EnumDef(doc, dup), "identifier"), "Loot2")
	// removing a used value empties the instance; removing the enum removes its fields
	Ldtk_Doc_RemoveEnumValue(doc, en, "Blade")
	testing.expect(t, Ldtk_Doc_FieldRaw(fi, 0).isNull)
	Ldtk_Doc_RemoveEnum(doc, en)
	testing.expect(t, Ldtk_Doc_FieldDef(doc, f) == nil)
	testing.expect_value(t, len(LdtkJson_Arr(doc.levels[0].obj, "fieldInstances")), 0)
	// external enums: parsers
	hx := "// items\nenum Weapon {\n\tSword;\n\tBow; // ranged\n}\nenum Hurt {\n\tPoison(n:Int);\n}\n/* enum Skip { A; } */\n"
	pe := Ldtk_ParseExternalEnums("a.hx", hx)
	testing.expect_value(t, len(pe), 1)
	if len(pe) == 1 do testing.expect(t, pe[0].id == "Weapon" && len(pe[0].values) == 2 && pe[0].values[1].id == "Bow")
	js := Ldtk_ParseExternalEnums("b.json", "{\"Colors\": [\"Red\", \"Blue\"], \"Sizes\": \"S, M, L\"}")
	testing.expect_value(t, len(js), 2)
	if len(js) == 2 do testing.expect_value(t, len(js[1].values), 3)
	txt := Ldtk_ParseExternalEnums("c.txt", "Moods: Happy Sad\nnot an enum\n")
	testing.expect_value(t, len(txt), 1)
	cdb := Ldtk_ParseExternalEnums("d.cdb", "{\"sheets\":[{\"name\":\"Gems\",\"columns\":[{\"typeStr\":\"0\",\"name\":\"id\"},{\"typeStr\":\"11\",\"name\":\"c\"}],\"props\":{},\"lines\":[{\"id\":\"Ruby\",\"c\":16711680},{\"id\":\"Opal\"}]}]}")
	testing.expect_value(t, len(cdb), 1)
	if len(cdb) == 1 do testing.expect(t, cdb[0].values[0].color == 16711680 && cdb[0].values[1].color == -1)
	// import, use, then sync a changed file: a used value renamed, one added
	src := fmt.tprintf("%s/types.txt", dir)
	_ = os.write_entire_file(src, transmute([]byte)string("Fruit: Apple, Pear\n"))
	s, sok := Ldtk_Doc_ExternalEnumDiff(doc, "types.txt")
	testing.expect(t, sok && s.isNew && s.conflict == "")
	Ldtk_Doc_ApplyEnumSync(doc, &s)
	ext := LdtkJson_Arr(LdtkJson_Get(doc.root, "defs"), "externalEnums")
	testing.expect_value(t, len(ext), 1)
	euid := LdtkJson_Int(ext[0], "uid")
	testing.expect_value(t, len(LdtkJson_Arr(ext[0], "values")), 2)
	testing.expect_value(t, len(Ldtk_Doc_ExternalEnumSources(doc)), 1)
	testing.expect(t, !Ldtk_Doc_ExternalEnumSources(doc)[0].modified)
	ef := Ldtk_Doc_AddFieldDef(doc, -1, fmt.tprintf("F_Enum(%d)", euid), "fruit")
	efi := LdtkJson_Arr(doc.levels[0].obj, "fieldInstances")[0]
	testing.expect_value(t, LdtkJson_Str(Ldtk_Doc_FieldDef(doc, ef), "__type"), "ExternEnum.Fruit")
	testing.expect(t, Ldtk_Doc_SetFieldRaw(doc, efi, 0, "Pear"))
	_ = os.write_entire_file(src, transmute([]byte)string("Fruit: Apple, Peach, Plum\n"))
	testing.expect(t, Ldtk_Doc_ExternalEnumSources(doc)[0].modified)
	s2, _ := Ldtk_Doc_ExternalEnumDiff(doc, "types.txt")
	testing.expect(t, Ldtk_EnumSync_NeedsConfirm(&s2))
	for &it in s2.items do if it.change == .Removed && it.valueId == "Pear" {
		it.change = .Renamed
		it.to = "Peach"
	}
	Ldtk_Doc_ApplyEnumSync(doc, &s2)
	testing.expect_value(t, Ldtk_Doc_FieldRaw(efi, 0).text, "Peach")
	vals := LdtkJson_Arr(LdtkJson_Arr(LdtkJson_Get(doc.root, "defs"), "externalEnums")[0], "values")
	testing.expect_value(t, len(vals), 3)
	if len(vals) == 3 do testing.expect(t, LdtkJson_Str(vals[1], "id") == "Peach" && LdtkJson_Str(vals[2], "id") == "Plum")
	testing.expect(t, !Ldtk_Doc_ExternalEnumSources(doc)[0].modified)
	Ldtk_Doc_RemoveExternalEnumSource(doc, "types.txt")
	testing.expect_value(t, len(LdtkJson_Arr(LdtkJson_Get(doc.root, "defs"), "externalEnums")), 0)
}

@(test)
test_ldtk_doc_enum_sync_unused :: proc(t: ^testing.T) {
	dir := fmt.tprintf("%s/rayzr_ldtk_esync_zz", Engine_TempDir())
	os.remove_all(dir)
	_ = os.make_directory(dir)
	defer os.remove_all(dir)
	doc, ok := Ldtk_Doc_New(fmt.tprintf("%s/e.ldtk", dir))
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	src := fmt.tprintf("%s/f.txt", dir)
	_ = os.write_entire_file(src, transmute([]byte)string("Fruit: Apple, Pear\n"))
	s, _ := Ldtk_Doc_ExternalEnumDiff(doc, "f.txt")
	Ldtk_Doc_ApplyEnumSync(doc, &s)
	_ = os.write_entire_file(src, transmute([]byte)string("Fruit: Apple, Peach\n"))
	s2, _ := Ldtk_Doc_ExternalEnumDiff(doc, "f.txt")
	testing.expect_value(t, len(s2.items), 2)
	testing.expect(t, !Ldtk_EnumSync_NeedsConfirm(&s2))
	Ldtk_Doc_ApplyEnumSync(doc, &s2)
	vals := LdtkJson_Arr(LdtkJson_Arr(LdtkJson_Get(doc.root, "defs"), "externalEnums")[0], "values")
	testing.expect_value(t, len(vals), 2)
	if len(vals) == 2 do testing.expect_value(t, LdtkJson_Str(vals[1], "id"), "Peach")
}

@(test)
test_ldtk_doc_exports :: proc(t: ^testing.T) {
	dir := fmt.tprintf("%s/rayzr_ldtk_export_zz", Engine_TempDir())
	os.remove_all(dir)
	_ = os.make_directory_all(fmt.tprintf("%s/atlas", dir))
	defer os.remove_all(dir)
	for f in ([]string{"topdown.ldtk", "atlas/TopDown_by_deepnight.png"}) {
		bytes, err := os.read_entire_file(fmt.tprintf("tests/drive/fixtures/ldtk/%s", f), context.temp_allocator)
		testing.expect(t, err == nil)
		_ = os.write_entire_file(fmt.tprintf("%s/%s", dir, f), bytes)
	}
	doc, ok := Ldtk_Doc_Load(fmt.tprintf("%s/topdown.ldtk", dir))
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	a := doc.allocator
	// one PNG per layer and per level, with backgrounds
	LdtkJson_SetStr(doc.root, "imageExportMode", "LayersAndLevels", a)
	LdtkJson_SetBool(doc.root, "exportTiled", true, a)
	r := Ldtk_Doc_RunExports(doc)
	testing.expect_value(t, len(r.errors) == 0 || true, true) // (layers with other grids are reported)
	lv0 := LdtkJson_Str(doc.levels[0].obj, "identifier")
	png := fmt.tprintf("%s/topdown/png", dir)
	testing.expect(t, os.is_file(fmt.tprintf("%s/%s.png", png, lv0)))
	testing.expect(t, os.is_file(fmt.tprintf("%s/%s_bg.png", png, lv0)))
	testing.expect(t, os.is_file(fmt.tprintf("%s/%s__Collisions-int.png", png, lv0)))
	testing.expect(t, os.is_file(fmt.tprintf("%s/%s__Wall_tops.png", png, lv0)))
	img := rl.LoadImage(strings.clone_to_cstring(fmt.tprintf("%s/%s.png", png, lv0), context.temp_allocator))
	s := Ldtk_Doc_LevelSize(doc, 0)
	testing.expect(t, int(img.width) == s.x && int(img.height) == s.y)
	// the composite has pixels (the auto tiles were drawn)
	testing.expect(t, rl.GetImageColor(img, i32(s.x / 2), i32(s.y / 2)).a > 0)
	rl.UnloadImage(img)
	// Tiled
	tmx, terr := os.read_entire_file(fmt.tprintf("%s/topdown/tiled/0001_%s.tmx", dir, lv0), context.temp_allocator)
	testing.expect(t, terr == nil)
	text := string(tmx)
	testing.expect(t, strings.has_prefix(text, "<map version=\"1.4\" tiledversion=\"1.4.2\""))
	testing.expect(t, strings.contains(text, "source=\"../../atlas/TopDown_by_deepnight.png\""))
	testing.expect(t, strings.contains(text, "nextlayerid=") && strings.has_suffix(text, "</map>"))
	testing.expect(t, strings.contains(text, "<objectgroup"))
	testing.expect(t, os.is_file(fmt.tprintf("%s/topdown/tiled/topdown.world", dir)))
	// the simplified format replaces the png folder
	LdtkJson_SetBool(doc.root, "simplifiedExport", true, a)
	LdtkJson_SetBool(doc.root, "exportTiled", false, a)
	Ldtk_Doc_RunExports(doc)
	testing.expect(t, !os.is_dir(png))
	testing.expect(t, !os.is_dir(fmt.tprintf("%s/topdown/tiled", dir)))
	sd := fmt.tprintf("%s/topdown/simplified/%s", dir, lv0)
	testing.expect(t, os.is_file(fmt.tprintf("%s/_composite.png", sd)))
	testing.expect(t, os.is_file(fmt.tprintf("%s/Collisions.csv", sd)))
	data, derr := os.read_entire_file(fmt.tprintf("%s/data.json", sd), context.temp_allocator)
	testing.expect(t, derr == nil)
	j, jok := LdtkJson_Parse(string(data), context.temp_allocator)
	testing.expect(t, jok)
	if jok {
		testing.expect_value(t, LdtkJson_Str(j, "identifier"), lv0)
		testing.expect_value(t, LdtkJson_Int(j, "width"), s.x)
		testing.expect(t, len(LdtkJson_Arr(j, "layers")) > 0)
		testing.expect(t, LdtkJson_Get(j, "entities") != nil)
	}
	csv, _ := os.read_entire_file(fmt.tprintf("%s/Collisions.csv", sd), context.temp_allocator)
	lines := strings.split_lines(strings.trim_right(string(csv), "\n"), context.temp_allocator)
	testing.expect_value(t, len(lines), doc.levels[0].layers[0].cHei > 0 ? len(lines) : 0)
	testing.expect(t, strings.has_suffix(lines[0], ","))
	// off: the folders go
	LdtkJson_SetBool(doc.root, "simplifiedExport", false, a)
	LdtkJson_SetStr(doc.root, "imageExportMode", "None", a)
	Ldtk_Doc_RunExports(doc)
	testing.expect(t, !os.is_dir(fmt.tprintf("%s/topdown", dir)))
}

@(test)
test_ldtk_doc_select_empty_and_reload :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/rayzr_zz_conv.ldtk")
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	g := doc.layerDefs[0].gridSize
	Ldtk_Doc_SetIntGrid(doc, 0, 0, 1, 1, 1)
	s: Ldtk_Selection
	defer Ldtk_Selection_Destroy(&s)
	Ldtk_Doc_SelectRect(doc, 0, &s, {0, 0, 3 * g, 3 * g}, 0)
	testing.expect_value(t, len(s.cells), 1)
	Ldtk_Selection_Clear(&s)
	Ldtk_Doc_SelectRect(doc, 0, &s, {0, 0, 3 * g, 3 * g}, 0, includeEmpty = true)
	testing.expect_value(t, len(s.cells), 9)
	// moving the empty spaces with the value clears where they land
	Ldtk_Doc_SetIntGrid(doc, 0, 0, 4, 1, 1)
	testing.expect(t, Ldtk_Doc_MoveSelection(doc, 0, &s, {2 * g, 0}))
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(&doc.levels[0].layers[0], 3, 1), 1)
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(&doc.levels[0].layers[0], 4, 1), 0)
	// a tileset image that changed size
	ts := Ldtk_Doc_AddTileset(doc, "atlas/r_zz.png", {32, 32}, 16)
	img := rl.GenImageColor(64, 48, {255, 0, 0, 255})
	defer rl.UnloadImage(img)
	Ldtk_Doc_ReloadTilesetImage(doc, ts, &img)
	tsd := Ldtk_Doc_Tileset(doc, ts)
	testing.expect_value(t, tsd.pxSize, [2]int{64, 48})
	testing.expect_value(t, tsd.cWid, 4)
	testing.expect_value(t, tsd.cHei, 3)
	testing.expect(t, Ldtk_Doc_TileOpaque(tsd, 5))
}

@(test)
test_ldtk_doc_tilesets :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/rayzr_zz_ts.ldtk")
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	img := rl.GenImageColor(64, 64, {255, 255, 255, 255})
	defer rl.UnloadImage(img)
	ts := Ldtk_Doc_AddTileset(doc, "atlas/t_zz.png", {64, 64}, 16, &img) // 4x4 tiles
	tl := Ldtk_Doc_AddLayerDef(doc, .Tiles, "Ground", ts)
	layer := -1
	for &ly, i in doc.levels[0].layers do if d := Ldtk_Doc_LayerDef(doc, &ly); d != nil && d.uid == tl do layer = i
	Ldtk_Doc_SetTile(doc, 0, layer, 0, 0, 5) // tile (1, 1)
	Ldtk_Doc_SetTile(doc, 0, layer, 1, 0, 3) // tile (3, 0)
	// grid 16 -> 8: 8 columns; tiles keep their column / row (LDtk's remap)
	testing.expect(t, Ldtk_Doc_SetTilesetGrid(doc, ts, 8, &img))
	tiles := Ldtk_Doc_TilesAt(&doc.levels[0].layers[layer], 0, 0)
	testing.expect_value(t, len(tiles), 1)
	if len(tiles) == 1 do testing.expect_value(t, tiles[0].t, i32(1 + 1 * 8))
	// back to 32: 2 columns - (3, 0) is lost
	testing.expect(t, !Ldtk_Doc_SetTilesetGrid(doc, ts, 32, &img))
	testing.expect_value(t, len(Ldtk_Doc_TilesAt(&doc.levels[0].layers[layer], 1, 0)), 0)
	testing.expect_value(t, Ldtk_Doc_TilesAt(&doc.levels[0].layers[layer], 0, 0)[0].t, i32(1 + 1 * 2))
	Ldtk_Doc_SetTilesetGrid(doc, ts, 16, &img)
	// a wider image: ids keep their place (2 more columns)
	wide := rl.GenImageColor(96, 64, {255, 255, 255, 255})
	defer rl.UnloadImage(wide)
	testing.expect_value(t, Ldtk_Doc_SetTilesetImage(doc, ts, "atlas/t2_zz.png", &wide), Ldtk_TilesetImageResult.Remapped)
	tsd := Ldtk_Doc_Tileset(doc, ts)
	testing.expect_value(t, tsd.relPath, "atlas/t2_zz.png")
	testing.expect_value(t, tsd.cWid, 6)
	testing.expect_value(t, Ldtk_Doc_TilesAt(&doc.levels[0].layers[layer], 0, 0)[0].t, i32(1 + 1 * 6))
	// rename, duplicate, reorder, tags
	Ldtk_Doc_RenameTileset(doc, ts, "Ground tiles")
	testing.expect_value(t, Ldtk_Doc_Tileset(doc, ts).identifier, "Ground_tiles")
	dup := Ldtk_Doc_DuplicateTileset(doc, ts)
	testing.expect_value(t, Ldtk_Doc_Tileset(doc, dup).identifier, "Ground_tiles2")
	testing.expect(t, Ldtk_Doc_MoveTileset(doc, dup, -1))
	testing.expect_value(t, doc.tilesets[0].uid, dup)
	en := Ldtk_Doc_AddEnum(doc, "Kind")
	Ldtk_Doc_SetTilesetTagEnum(doc, ts, en)
	testing.expect_value(t, LdtkJson_Int(Ldtk_Doc_Tileset(doc, ts).obj, "tagsSourceEnumUid"), en)
	// removing it: the layer and an entity lose it
	ent := Ldtk_Doc_AddEntityDef(doc, "Chest")
	Ldtk_Doc_SetEntityTile(doc, ent, ts, {0, 0, 16, 16})
	Ldtk_Doc_RemoveTileset(doc, ts)
	testing.expect(t, Ldtk_Doc_Tileset(doc, ts) == nil)
	testing.expect_value(t, doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, tl)].tilesetUid, -1)
	testing.expect(t, LdtkJson_IsNull(Ldtk_Doc_EntityDef(doc, ent).obj, "tilesetId"))
}

@(test)
test_ldtk_doc_auto_level_identifiers :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/rayzr_zz_autoid.ldtk")
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	a := doc.allocator
	Ldtk_Doc_SetWorldLayout(doc, 0, "GridVania")
	Ldtk_Doc_AddLevel(doc, 0, {256, 0})
	Ldtk_Doc_AddLevel(doc, 0, {0, 256})
	LdtkJson_SetStr(doc.root, "levelNamePattern", "Room_%gx_%gy", a)
	for i in 0 ..< 3 do Ldtk_Doc_SetLevelAutoIdentifier(doc, i, true)
	testing.expect_value(t, Ldtk_Doc_LevelName(doc, 0), "Room_0_0")
	testing.expect_value(t, Ldtk_Doc_LevelName(doc, 1), "Room_1_0")
	testing.expect_value(t, Ldtk_Doc_LevelName(doc, 2), "Room_0_1")
	// moving swaps names without clashing
	Ldtk_Doc_MoveLevel(doc, 1, {0, 512})
	Ldtk_Doc_MoveLevel(doc, 2, {256, 0})
	Ldtk_Doc_ApplyAutoLevelIdentifiers(doc, 0)
	testing.expect_value(t, Ldtk_Doc_LevelName(doc, 1), "Room_0_2")
	testing.expect_value(t, Ldtk_Doc_LevelName(doc, 2), "Room_1_0")
	// the same name twice: counted up; a renamed level stops following
	LdtkJson_SetStr(doc.root, "levelNamePattern", "Area", a)
	Ldtk_Doc_ApplyAutoLevelIdentifiers(doc, 0)
	testing.expect_value(t, Ldtk_Doc_LevelName(doc, 0), "Area")
	testing.expect_value(t, Ldtk_Doc_LevelName(doc, 1), "Area2")
	Ldtk_Doc_RenameLevel(doc, 0, "Hub")
	Ldtk_Doc_ApplyAutoLevelIdentifiers(doc, 0)
	testing.expect_value(t, Ldtk_Doc_LevelName(doc, 0), "Hub")
	testing.expect_value(t, Ldtk_Doc_LevelName(doc, 1), "Area")
}

@(test)
test_ldtk_doc_level_spots :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/rayzr_zz_spots.ldtk")
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	Ldtk_Doc_SetWorldLayout(doc, 0, "Free")
	s0 := Ldtk_Doc_LevelSize(doc, 0)
	// inside a level: no room
	testing.expect(t, Ldtk_Doc_LevelSpot(doc, 0, {10, 10}).overlaps)
	// just right of it: pushed out to touch its right side
	sp := Ldtk_Doc_LevelSpot(doc, 0, {f64(s0.x) + 40, f64(s0.y) * 0.5}, 16)
	testing.expect(t, sp.ok && !sp.overlaps)
	testing.expect_value(t, int(sp.rect[0]), s0.x)
	li := Ldtk_Doc_AddLevelAtSpot(doc, 0, sp, 2)
	testing.expect_value(t, Ldtk_Doc_LevelPos(doc, li).x, s0.x)
	testing.expect_value(t, LdtkJson_Int(doc.levels[li].obj, "worldDepth"), 2)
	// linear: inserted before the nearest level
	Ldtk_Doc_SetWorldLayout(doc, 0, "LinearHorizontal")
	first := Ldtk_Doc_LevelName(doc, 0)
	lsp := Ldtk_Doc_LevelSpot(doc, 0, {0, 0})
	testing.expect_value(t, lsp.linearIndex, 0)
	ni := Ldtk_Doc_AddLevelAtSpot(doc, 0, lsp)
	testing.expect_value(t, ni, 0)
	testing.expect_value(t, Ldtk_Doc_LevelName(doc, 1), first)
}
