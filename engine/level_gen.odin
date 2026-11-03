package engine

import "base:runtime"
import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:strings"
import lua "lua54"

// ============================================================================
// Procedural level generation (#142): a graph of nodes (Gaea style) whose
// output is a level. Every port carries a grid of numbers the size of the
// level (0 = empty / low, 1 = solid / high): generators make one, modifiers
// turn one (or two) into another, and the tile output maps value ranges to
// tiles and writes them into a TileMapNode (its colliders follow when it is
// Solid).
//
// A generator is a project file (.levelgen.json):
//
//   {"size": [64, 40], "seed": 7, "output": 4, "nodes": [
//     {"id": 1, "type": "random_fill", "params": {"density": 0.48}},
//     {"id": 2, "type": "cellular", "inputs": {"in": 1}, "params": {"iterations": 5}},
//     {"id": 3, "type": "border", "params": {"width": 1}},
//     {"id": 4, "type": "combine", "inputs": {"a": 2, "b": 3}, "params": {"op": "max"}},
//     {"id": 5, "type": "tile_output", "inputs": {"in": 4},
//      "rules": [{"min": 0.5, "max": 1, "tiles": [3, 4]}]}]}
//
// Deterministic: the same graph and seed give the same level on every
// platform (hash noise, no global random state). Each node's own seed mixes
// the graph's seed, its id and its "seed" parameter. Evaluation is
// depth-first with every node's grid computed once (a cycle is an error).
// ============================================================================

Gen_Kind :: enum {
	// Generators
	Constant,
	Noise,
	Random_Fill,
	Gradient,
	Border,
	Rect,
	Rooms,  // rooms joined by corridors (1 = floor)
	Walker, // a random walk carving tunnels (1 = walked)
	Lines,      // random lines: horizontal, vertical or any angle (#171)
	Rectangles, // random rectangles, filled or outlines (#171)
	Circles,    // random circles, filled or outlines (#171)
	// Modifiers
	Threshold,
	Invert,
	Remap,
	Blur,
	Cellular,
	Dilate,
	Erode,
	Combine,
	Scatter, // spaced random points (on the input's solid cells, if connected)
	Surface, // empty cells next to solid ones (ground to stand on)
	// Playable levels (#171; level_gen_regions.odin)
	Flood_Fill,      // the cells reachable from a start cell
	Regions,         // keep the largest open area / remove small ones
	Connect_Regions, // corridors joining every open area
	Path,            // a way from a start to an exit
	Check,           // refuses a level with too little open, or in pieces
	// Your own
	Script, // a Lua function (a .lua file) computes the grid
	Custom, // a kind registered from Odin (Gen_RegisterNode; `custom` names it)
	// Output
	Tile_Output,
	Entity_Output, // a component on every point (cells >= 0.5)
}

Gen_Param_Def :: struct {
	name:     string,
	default_: f64,
	choices:  []string, // a choice parameter (saved by name; the value is its index)
	doc:      string,
	integer:  bool,     // whole numbers (the editor's widget)
	toggle:   bool,     // on / off (saved as a number, read as true / false)
}

Gen_Kind_Info :: struct {
	name:   string, // in the file ("random_fill")
	label:  string,
	inputs: []string,
	params: []Gen_Param_Def,
	doc:    string,
}

GEN_COMBINE_OPS := []string{"add", "subtract", "multiply", "min", "max", "mask", "average"}
GEN_GRADIENT_DIRS := []string{"horizontal", "vertical", "radial"}
GEN_SURFACE_SIDES := []string{"top", "bottom", "any"}
GEN_LINE_DIRS := []string{"horizontal", "vertical", "both", "any"}

GEN_KINDS := [Gen_Kind]Gen_Kind_Info{
	.Constant = {"constant", "Constant", {}, {{name = "value", default_ = 1, doc = "Every cell's value"}}, "The same value everywhere."},
	.Noise = {"noise", "Noise", {}, {
		{name = "scale", default_ = 16, doc = "Size of the features (cells)"},
		{name = "octaves", default_ = 3, doc = "Layers of detail (1-8)", integer = true},
		{name = "persistence", default_ = 0.5, doc = "How much each finer layer adds"},
		{name = "seed", default_ = 0, doc = "Added to the graph's seed", integer = true},
	}, "Smooth value noise (fBm), 0..1: hills, islands, caves before a threshold."},
	.Random_Fill = {"random_fill", "Random Fill", {}, {
		{name = "density", default_ = 0.45, doc = "Fraction of cells set to 1"},
		{name = "seed", default_ = 0, doc = "Added to the graph's seed", integer = true},
	}, "Each cell 1 with a chance of `density`, else 0 (the start of cellular caves)."},
	.Gradient = {"gradient", "Gradient", {}, {
		{name = "direction", default_ = 0, choices = GEN_GRADIENT_DIRS, doc = "horizontal (0 left .. 1 right), vertical (0 top .. 1 bottom), radial (1 centre .. 0 corners)"},
	}, "A ramp across the level (a ground line with a threshold, an island with radial)."},
	.Border = {"border", "Border", {}, {{name = "width", default_ = 1, doc = "Cells from each edge", integer = true}}, "1 within `width` cells of the edge, else 0 (walls around a level)."},
	.Rect = {"rect", "Rectangle", {}, {
		{name = "x", default_ = 0, doc = "Left cell", integer = true},
		{name = "y", default_ = 0, doc = "Top cell", integer = true},
		{name = "w", default_ = 8, doc = "Width (cells)", integer = true},
		{name = "h", default_ = 8, doc = "Height (cells)", integer = true},
		{name = "value", default_ = 1, doc = "Inside (0 outside)"},
	}, "A filled rectangle (a spawn room, a floor)."},
	.Threshold = {"threshold", "Threshold", {"in"}, {
		{name = "value", default_ = 0.5, doc = "Cells at or above it become 1, the rest 0"},
		{name = "invert", default_ = 0, doc = "1: below becomes 1 instead", toggle = true},
	}, "Turns values into solid (1) and empty (0)."},
	.Invert = {"invert", "Invert", {"in"}, {}, "1 - value (solid <-> empty)."},
	.Remap = {"remap", "Remap", {"in"}, {
		{name = "from_min", default_ = 0, doc = ""},
		{name = "from_max", default_ = 1, doc = ""},
		{name = "to_min", default_ = 0, doc = ""},
		{name = "to_max", default_ = 1, doc = ""},
	}, "Maps one range of values onto another (clamped to it)."},
	.Blur = {"blur", "Blur", {"in"}, {{name = "radius", default_ = 1, doc = "Cells averaged on each side", integer = true}}, "Averages each cell with its neighbours (smooths noise and edges)."},
	.Cellular = {"cellular", "Cellular Automaton", {"in"}, {
		{name = "iterations", default_ = 4, doc = "Smoothing passes", integer = true},
		{name = "birth", default_ = 5, doc = "An empty cell with at least this many solid neighbours (of 8) becomes solid", integer = true},
		{name = "survive", default_ = 4, doc = "A solid cell with fewer solid neighbours becomes empty", integer = true},
		{name = "edge_solid", default_ = 1, doc = "1: cells beyond the edge count as solid (closed caves)", toggle = true},
	}, "Cave smoothing: random fill becomes cave walls and open rooms."},
	.Dilate = {"dilate", "Dilate", {"in"}, {{name = "iterations", default_ = 1, doc = "", integer = true}}, "Grows solid areas by a cell per iteration."},
	.Erode = {"erode", "Erode", {"in"}, {{name = "iterations", default_ = 1, doc = "", integer = true}}, "Shrinks solid areas by a cell per iteration."},
	.Combine = {"combine", "Combine", {"a", "b"}, {
		{name = "op", default_ = 0, choices = GEN_COMBINE_OPS, doc = "add, subtract, multiply, min, max, mask (a where b is solid), average"},
	}, "Two grids into one."},
	.Rooms = {"rooms", "Rooms & Corridors", {}, {
		{name = "min_size", default_ = 4, doc = "Smallest room side (cells)", integer = true},
		{name = "max_size", default_ = 10, doc = "Largest room side (cells)", integer = true},
		{name = "corridor", default_ = 1, doc = "Corridor width (cells)", integer = true},
		{name = "seed", default_ = 0, doc = "Added to the graph's seed", integer = true},
	}, "A dungeon: the level split in two again and again (BSP), a room in each part, corridors joining them. 1 = floor; invert it for walls."},
	.Walker = {"walker", "Walker", {}, {
		{name = "steps", default_ = 400, doc = "Steps of each walker", integer = true},
		{name = "walkers", default_ = 1, doc = "How many walk (from the centre)", integer = true},
		{name = "brush", default_ = 1, doc = "Width of the tunnel (cells)", integer = true},
		{name = "seed", default_ = 0, doc = "Added to the graph's seed", integer = true},
	}, "Random walks from the centre (\"drunkard's walk\"): winding tunnels and caverns. 1 = walked."},
	.Lines = {"lines", "Random Lines", {}, {
		{name = "count", default_ = 6, doc = "How many lines", integer = true},
		{name = "min_length", default_ = 6, doc = "Shortest line (cells)", integer = true},
		{name = "max_length", default_ = 20, doc = "Longest line (cells)", integer = true},
		{name = "thickness", default_ = 1, doc = "Line width (cells)", integer = true},
		{name = "direction", default_ = 2, choices = GEN_LINE_DIRS, doc = "horizontal, vertical, both (each line one or the other), any (any angle)"},
		{name = "seed", default_ = 0, doc = "Added to the graph's seed", integer = true},
	}, "Lines at random places (1 on a line, else 0), the same for a seed: platforms, ledges, walls, cracks. Each fits inside the level."},
	.Rectangles = {"rectangles", "Random Rectangles", {}, {
		{name = "count", default_ = 5, doc = "How many rectangles", integer = true},
		{name = "min_size", default_ = 4, doc = "Smallest side (cells)", integer = true},
		{name = "max_size", default_ = 12, doc = "Largest side (cells)", integer = true},
		{name = "thickness", default_ = 1, doc = "Outline width (cells; filled: ignored)", integer = true},
		{name = "filled", default_ = 0, doc = "Filled rectangles instead of outlines", toggle = true},
		{name = "seed", default_ = 0, doc = "Added to the graph's seed", integer = true},
	}, "Rectangles at random places and sizes, outlines or filled (1 = on), the same for a seed: rooms, ruins, crates. Each fits inside the level."},
	.Circles = {"circles", "Random Circles", {}, {
		{name = "count", default_ = 5, doc = "How many circles", integer = true},
		{name = "min_radius", default_ = 3, doc = "Smallest radius (cells)", integer = true},
		{name = "max_radius", default_ = 8, doc = "Largest radius (cells)", integer = true},
		{name = "thickness", default_ = 1, doc = "Outline width (cells; filled: ignored)", integer = true},
		{name = "filled", default_ = 0, doc = "Filled circles instead of rings", toggle = true},
		{name = "seed", default_ = 0, doc = "Added to the graph's seed", integer = true},
	}, "Circles at random places and sizes, rings or filled (1 = on), the same for a seed: craters, arenas, pools. Each fits inside the level when it can."},
	.Flood_Fill = {"flood_fill", "Flood Fill", {"in"}, {
		{name = "x", default_ = -1, doc = "Start cell's column (-1: the middle); a closed cell starts from the nearest open one", integer = true},
		{name = "y", default_ = -1, doc = "Start cell's row (-1: the middle)", integer = true},
		{name = "open", default_ = 0, choices = GEN_OPEN_SIDES, doc = GEN_OPEN_DOC},
		{name = "diagonal", default_ = 0, doc = GEN_DIAGONAL_DOC, toggle = true},
	}, "1 on the open cells reachable from a start cell, 0 elsewhere: where the player can get to (mask spawns with it)."},
	.Regions = {"regions", "Regions", {"in"}, {
		{name = "mode", default_ = 0, choices = GEN_REGION_MODES, doc = "keep_largest: only the biggest open area stays open; remove_small: areas under min_size cells are filled"},
		{name = "min_size", default_ = 20, doc = "remove_small: areas with fewer cells are filled", integer = true},
		{name = "open", default_ = 0, choices = GEN_OPEN_SIDES, doc = GEN_OPEN_DOC},
		{name = "diagonal", default_ = 0, doc = GEN_DIAGONAL_DOC, toggle = true},
	}, "Fills open areas the player couldn't reach: all but the largest, or the small ones (cave pockets). The input back, 0 / 1, open where it stays open."},
	.Connect_Regions = {"connect_regions", "Connect Regions", {"in"}, {
		{name = "width", default_ = 1, doc = "Corridor width (cells)", integer = true},
		{name = "min_size", default_ = 0, doc = "Areas with fewer cells are filled instead of joined (0: join every one)", integer = true},
		{name = "open", default_ = 0, choices = GEN_OPEN_SIDES, doc = GEN_OPEN_DOC},
		{name = "diagonal", default_ = 0, doc = GEN_DIAGONAL_DOC, toggle = true},
	}, "Joins every open area to the largest with the shortest corridors (never through the outer row): one connected level. The input back, 0 / 1, corridors open."},
	.Path = {"path", "Start-to-Exit Path", {"in"}, {
		{name = "placement", default_ = 0, choices = GEN_PATH_PLACEMENTS, doc = "Where the start and exit are: left_right / top_bottom (the open cells nearest those edges' middles), farthest (the two open cells farthest apart), custom (the cells below)"},
		{name = "start_x", default_ = 0, doc = "custom: the start cell's column", integer = true},
		{name = "start_y", default_ = 0, doc = "custom: the start cell's row", integer = true},
		{name = "end_x", default_ = 0, doc = "custom: the exit cell's column", integer = true},
		{name = "end_y", default_ = 0, doc = "custom: the exit cell's row", integer = true},
		{name = "width", default_ = 1, doc = "Width of what it carves (cells)", integer = true},
		{name = "open", default_ = 0, choices = GEN_OPEN_SIDES, doc = GEN_OPEN_DOC},
		{name = "output", default_ = 0, choices = GEN_PATH_OUTPUTS, doc = "level: the input with the path carved; path: 1 on the path; start / end: 1 on that cell (feed an Entity Output: the player, the door)"},
	}, "Guarantees a way from a start to an exit: the cheapest route, through open cells where it can, carving rock where it must."},
	.Check = {"check", "Check", {"in"}, {
		{name = "min_open", default_ = 0.25, doc = "At least this fraction of the level open (0..1)"},
		{name = "connected", default_ = 1, doc = "All open cells in one area", toggle = true},
		{name = "open", default_ = 0, choices = GEN_OPEN_SIDES, doc = GEN_OPEN_DOC},
		{name = "diagonal", default_ = 0, doc = GEN_DIAGONAL_DOC, toggle = true},
	}, "Its input unchanged - or an error when the level isn't playable enough (too little open, in pieces). A Level Generator with Random Seed and Attempts then tries other seeds."},
	.Tile_Output = {"tile_output", "Tile Output", {"in"}, {
		{name = "empty", default_ = -1, doc = "The tile for cells no rule takes (-1 = none)", integer = true},
		{name = "tile_w", default_ = 16, doc = "Tile width in the tileset (pixels): the tile picker and previews", integer = true},
		{name = "tile_h", default_ = 16, doc = "Tile height in the tileset (pixels)", integer = true},
	}, "Rules turn value ranges into tiles (a random one of each rule's tiles, the same for a seed); written into a TileMap - or, as IntGrid values, into an LDtk layer. With a Layer name, into the TileMap of that name next to the main one."},
	.Scatter = {"scatter", "Scatter", {"in"}, {
		{name = "chance", default_ = 0.05, doc = "Chance of a point on each allowed cell"},
		{name = "spacing", default_ = 4, doc = "At least this many cells between points", integer = true},
		{name = "seed", default_ = 0, doc = "Added to the graph's seed", integer = true},
	}, "Random points (1) spaced apart - on the input's solid cells when it is connected, anywhere otherwise. Feed an entity output."},
	.Surface = {"surface", "Surface", {"in"}, {
		{name = "side", default_ = 0, choices = GEN_SURFACE_SIDES, doc = "top: empty cells with solid below (ground to stand on), bottom: with solid above (ceilings), any: next to solid"},
	}, "Empty cells against the input's solid ones: where things stand, hang or cling."},
	.Script = {"script", "Lua Script", {"a", "b"}, {
		{name = "p1", default_ = 0, doc = "A number for the script (ctx.params.p1)"},
		{name = "p2", default_ = 0, doc = "A number for the script (ctx.params.p2)"},
		{name = "p3", default_ = 0, doc = "A number for the script (ctx.params.p3)"},
		{name = "p4", default_ = 0, doc = "A number for the script (ctx.params.p4)"},
		{name = "seed", default_ = 0, doc = "Added to the graph's seed", integer = true},
	}, "Your own node: a .lua file returning function(ctx) - ctx.a and ctx.b are its inputs, ctx.out the grid to fill (flat, row-major, from 1), ctx.random(x, y) a number for a cell."},
	.Custom = {"custom", "Custom", {}, {}, "A node registered from Odin (Gen_RegisterNode)."},
	.Entity_Output = {"entity_output", "Entity Output", {"in"}, {
		{name = "max", default_ = 0, doc = "At most this many (0 = every point)", integer = true},
	}, "Puts its component (a .component.json) on every point of its input (cells >= 0.5): enemies, pickups, the player's start."},
}

// A tile rule: cells with min <= value <= max get one of `tiles`.
Gen_Tile_Rule :: struct {
	min, max: f32,
	tiles:    [dynamic]i32,
	terrain:  string, // instead of tiles: a terrain of the output's tileset (auto-tiled; the graph's allocator)
}

// A pattern rule (a tile output's; #171): where the 3x3 cells around a
// cell match - each cell 0 any, 1 its value in min..max, -1 not - the cell
// takes one of `tiles` (with `chance`). Pattern rules run after the rules
// (and terrains), the first that matches wins; cells beyond the level are
// in range. Cells: row by row, the middle (index 4) the cell itself.
Gen_Pattern_Rule :: struct {
	min, max: f32,
	cells:    [9]i8,
	tiles:    [dynamic]i32,
	chance:   f32, // 0..1 (1: every match)
}

Gen_Node :: struct {
	id:     int,
	kind:   Gen_Kind,
	inputs: [2]int, // source node ids, in the kind's input order (0 = not connected)
	params: [8]f64, // in the kind's parameter order
	rules:  [dynamic]Gen_Tile_Rule, // Tile_Output
	patterns: [dynamic]Gen_Pattern_Rule, // Tile_Output: after the rules
	component: string, // Entity_Output: what it places (the graph's allocator)
	tileset: string, // Tile_Output: the tileset image its tiles index (the tile picker, previews; the graph's allocator)
	layer:   string, // Tile_Output: the TileMap it fills, by name, next to the main one ("": the main one; the graph's allocator)
	script: string, // Script: its .lua file (the graph's allocator)
	custom: string, // Custom: the registered kind's name (the graph's allocator)
	pos:    [2]f32, // where the editor draws it
}

// A comment frame on the editor's canvas (#171): a titled, coloured box
// around nodes. Only the editor reads it - moving it moves the nodes inside.
Gen_Frame :: struct {
	title: string, // (the graph's allocator)
	color: [4]f32, // 0..1
	pos:   [2]f32, // its top-left, in the canvas's units
	size:  [2]f32,
}

GEN_FRAME_COLOR :: [4]f32{0.35, 0.55, 0.85, 1}

Gen_Graph :: struct {
	size:      [2]int,
	seed:      u64,
	output:    int, // the node whose grid is the result (0 = the last Tile_Output, else the last node)
	nodes:     [dynamic]Gen_Node,
	frames:    [dynamic]Gen_Frame, // the editor's comment frames (optional in the file)
	scripts:   map[string]string, // Script nodes' sources by file (Gen_LoadScripts; the graph's allocator)
	tilesets:  map[string]string, // tile outputs' tilesets' terrain files' text by image (Gen_LoadTerrains; the graph's allocator)
	allocator: runtime.Allocator,
	// The target map's grid (not saved; whoever generates sets it): terrains'
	// neighbours on isometric, staggered and hex maps.
	layout:    TileMap_Layout,
	stagger:   TileMap_Stagger,
}

// A grid of values (row-major, w * h).
Gen_Grid :: struct {
	w, h: int,
	v:    []f32,
}

Gen_GridAt :: #force_inline proc(g: Gen_Grid, x, y: int) -> f32 {return g.v[y * g.w + x]}

// --- the graph ------------------------------------------------------------------------

Gen_Kind_FromName :: proc(name: string) -> (Gen_Kind, bool) {
	for info, k in GEN_KINDS do if k != .Custom && info.name == name do return k, true
	return .Constant, false
}

// Gen_NodeDefaults: a node of a kind with its default parameters (a
// Custom one: of the registered kind `custom`; the name isn't copied).
Gen_NodeDefaults :: proc(kind: Gen_Kind, id: int, custom := "") -> Gen_Node {
	n := Gen_Node{id = id, kind = kind, custom = custom}
	for p, i in Gen_NodeInfo(&n).params do n.params[i] = p.default_
	n.custom = ""
	return n
}

// Gen_NodeInfo: what a node's kind is - its name, inputs, parameters (a
// Custom node's from its registration).
Gen_NodeInfo :: proc(n: ^Gen_Node) -> Gen_Kind_Info {
	if n.kind != .Custom do return GEN_KINDS[n.kind]
	if def := Gen_FindCustomKind(n.custom); def != nil do return def.info
	return {name = n.custom, label = n.custom, doc = "Not registered (Gen_RegisterNode)."}
}

// Gen_Param reads a node's parameter by name (its default when unknown).
Gen_Param :: proc(n: ^Gen_Node, name: string) -> f64 {
	for p, i in Gen_NodeInfo(n).params do if p.name == name do return n.params[i]
	return 0
}

Gen_SetParam :: proc(n: ^Gen_Node, name: string, value: f64) -> bool {
	for p, i in Gen_NodeInfo(n).params do if p.name == name {
		n.params[i] = value
		return true
	}
	return false
}

Gen_FindNode :: proc(g: ^Gen_Graph, id: int) -> ^Gen_Node {
	for &n in g.nodes do if n.id == id do return &n
	return nil
}

Gen_GraphDestroy :: proc(g: ^Gen_Graph) {
	for &n in g.nodes do gen_node_free(g, &n)
	delete(g.nodes)
	g.nodes = nil
	for &f in g.frames do gen_set_text(g, &f.title, "")
	delete(g.frames)
	g.frames = nil
	gen_scripts_clear(g)
	delete(g.scripts)
	g.scripts = nil
	gen_tilesets_clear(g)
	delete(g.tilesets)
	g.tilesets = nil
}

@(private = "file")
gen_node_free :: proc(g: ^Gen_Graph, n: ^Gen_Node) {
	Gen_NodeClearRules(n, g.allocator)
	gen_set_text(g, &n.component, "")
	gen_set_text(g, &n.script, "")
	gen_set_text(g, &n.custom, "")
	gen_set_text(g, &n.tileset, "")
	gen_set_text(g, &n.layer, "")
}

// (a node's text, owned by the graph)
@(private = "file")
gen_set_text :: proc(g: ^Gen_Graph, field: ^string, text: string) {
	if field^ != "" do delete(field^, g.allocator)
	field^ = strings.clone(text, g.allocator) if text != "" else ""
}

// Gen_SetComponent: an entity output's component (the graph owns the text).
Gen_SetComponent :: proc(g: ^Gen_Graph, n: ^Gen_Node, path: string) {gen_set_text(g, &n.component, path)}

// Gen_SetScript: a script node's .lua file (load it with Gen_LoadScripts).
Gen_SetScript :: proc(g: ^Gen_Graph, n: ^Gen_Node, path: string) {gen_set_text(g, &n.script, path)}
Gen_SetTileset :: proc(g: ^Gen_Graph, n: ^Gen_Node, path: string) {gen_set_text(g, &n.tileset, path)}
Gen_SetLayer :: proc(g: ^Gen_Graph, n: ^Gen_Node, name: string) {gen_set_text(g, &n.layer, name)}

Gen_NodeClearRules :: proc(n: ^Gen_Node, allocator := context.allocator) {
	for &r in n.rules do Gen_RuleFree(&r, allocator)
	delete(n.rules)
	n.rules = nil
	for p in n.patterns do delete(p.tiles)
	delete(n.patterns)
	n.patterns = nil
}

// Gen_RuleFree: a tile rule's tiles and terrain name (allocator: the graph's).
Gen_RuleFree :: proc(r: ^Gen_Tile_Rule, allocator := context.allocator) {
	delete(r.tiles)
	if r.terrain != "" do delete(r.terrain, allocator)
	r.tiles, r.terrain = nil, ""
}

// Gen_RuleSetTerrain: the rule's terrain ("": its tiles instead).
Gen_RuleSetTerrain :: proc(g: ^Gen_Graph, r: ^Gen_Tile_Rule, name: string) {
	if r.terrain != "" do delete(r.terrain, g.allocator)
	r.terrain = strings.clone(name, g.allocator) if name != "" else ""
}

// Gen_GraphParse reads a .levelgen.json (allocator: the graph's).
Gen_GraphParse :: proc(data: []u8, allocator := context.allocator) -> (g: Gen_Graph, err: string) {
	g.allocator = allocator
	g.nodes = make([dynamic]Gen_Node, allocator)
	g.frames = make([dynamic]Gen_Frame, allocator)
	g.size = {32, 24}
	value, perr := json.parse(data, allocator = context.temp_allocator)
	if perr != .None do return g, fmt.tprintf("not valid JSON (%v)", perr)
	root, ok := value.(json.Object)
	if !ok do return g, "not a JSON object"
	Format_Migrate(.LevelGen, &root)
	if sz, sok := root["size"].(json.Array); sok && len(sz) >= 2 {
		w, _ := json_number(sz[0])
		h, _ := json_number(sz[1])
		g.size = {clamp(int(w), 1, 4096), clamp(int(h), 1, 4096)}
	}
	if s, sok := json_number(root["seed"]); sok do g.seed = u64(s)
	if o, ook := json_number(root["output"]); ook do g.output = int(o)
	// (An optional key added within format 1: a file without it - every
	// older one - has no frames, so there is nothing to migrate.)
	if frames, fok := root["frames"].(json.Array); fok {
		for fv in frames {
			fo, isObj := fv.(json.Object)
			if !isObj do continue
			f := Gen_Frame{color = GEN_FRAME_COLOR, size = {300, 200}}
			if t, tok := fo["title"].(json.String); tok && t != "" do f.title = strings.clone(string(t), allocator)
			if pos, pok := fo["pos"].(json.Array); pok && len(pos) >= 2 {
				f.pos.x, _ = json_number(pos[0])
				f.pos.y, _ = json_number(pos[1])
			}
			if sz, sok := fo["size"].(json.Array); sok && len(sz) >= 2 {
				f.size.x, _ = json_number(sz[0])
				f.size.y, _ = json_number(sz[1])
			}
			f.size = {max(f.size.x, 40), max(f.size.y, 40)}
			if c, cok := fo["color"].(json.Array); cok && len(c) >= 3 {
				for i in 0 ..< min(len(c), 4) do f.color[i], _ = json_number(c[i])
				if len(c) == 3 do f.color[3] = 1
			}
			append(&g.frames, f)
		}
	}
	nodes, nok := root["nodes"].(json.Array)
	if !nok do return g, ""
	for v in nodes {
		obj, isObj := v.(json.Object)
		if !isObj do continue
		typeName, _ := obj["type"].(json.String)
		kind, known := Gen_Kind_FromName(string(typeName))
		if !known && Gen_FindCustomKind(string(typeName)) != nil do kind, known = .Custom, true
		if !known do return g, fmt.tprintf("unknown node type %q", string(typeName))
		idf, _ := json_number(obj["id"])
		n := Gen_NodeDefaults(kind, int(idf), string(typeName))
		if n.id <= 0 do return g, fmt.tprintf("a %s node has no id", string(typeName))
		if Gen_FindNode(&g, n.id) != nil do return g, fmt.tprintf("two nodes have the id %d", n.id)
		if kind == .Custom do n.custom = strings.clone(string(typeName), allocator)
		info := Gen_NodeInfo(&n)
		if ins, iok := obj["inputs"].(json.Object); iok {
			for port, i in info.inputs {
				if src, sok := json_number(ins[port]); sok do n.inputs[i] = int(src)
			}
		}
		if ps, pok := obj["params"].(json.Object); pok {
			for p, i in info.params {
				pv, has := ps[p.name]
				if !has do continue
				if num, isNum := json_number(pv); isNum {
					n.params[i] = f64(num)
				} else if b, isBool := pv.(json.Boolean); isBool {
					n.params[i] = 1 if b else 0
				} else if s, isStr := pv.(json.String); isStr && len(p.choices) > 0 {
					for ch, ci in p.choices do if ch == string(s) do n.params[i] = f64(ci)
				}
			}
		}
		if pos, pok := obj["pos"].(json.Array); pok && len(pos) >= 2 {
			n.pos.x, _ = json_number(pos[0])
			n.pos.y, _ = json_number(pos[1])
		}
		if comp, cok := obj["component"].(json.String); cok do n.component = strings.clone(string(comp), allocator)
		if file, sok := obj["script"].(json.String); sok && kind == .Script do n.script = strings.clone(string(file), allocator)
		if kind == .Tile_Output {
			if ts, tok := obj["tileset"].(json.String); tok && ts != "" do n.tileset = strings.clone(string(ts), allocator)
			if ly, lok := obj["layer"].(json.String); lok && ly != "" do n.layer = strings.clone(string(ly), allocator)
		}
		if rules, rok := obj["rules"].(json.Array); rok {
			n.rules = make([dynamic]Gen_Tile_Rule, allocator)
			for rv in rules {
				ro, isObj2 := rv.(json.Object)
				if !isObj2 do continue
				r := Gen_Tile_Rule{min = 0, max = 1, tiles = make([dynamic]i32, allocator)}
				if m, mok := json_number(ro["min"]); mok do r.min = m
				if m, mok := json_number(ro["max"]); mok do r.max = m
				if t, tok := json_number(ro["tile"]); tok do append(&r.tiles, i32(t))
				if ts, tok := ro["tiles"].(json.Array); tok do for tv in ts do if t, isNum := json_number(tv); isNum do append(&r.tiles, i32(t))
				if tn, tok := ro["terrain"].(json.String); tok && tn != "" do r.terrain = strings.clone(string(tn), allocator)
				append(&n.rules, r)
			}
		}
		if pats, pok := obj["patterns"].(json.Array); pok && kind == .Tile_Output {
			n.patterns = make([dynamic]Gen_Pattern_Rule, allocator)
			for pv in pats {
				po, isObj3 := pv.(json.Object)
				if !isObj3 do continue
				pr := Gen_Pattern_Rule{min = 0.5, max = 1, chance = 1, tiles = make([dynamic]i32, allocator)}
				if m, mok := json_number(po["min"]); mok do pr.min = m
				if m, mok := json_number(po["max"]); mok do pr.max = m
				if c, cok := json_number(po["chance"]); cok do pr.chance = clamp(c, 0, 1)
				if cs, cok := po["cells"].(json.Array); cok do for cv, ci in cs {
					if ci >= 9 do break
					if c, isNum := json_number(cv); isNum do pr.cells[ci] = i8(clamp(int(c), -1, 1))
				}
				if ts, tok := po["tiles"].(json.Array); tok do for tv in ts do if t, isNum := json_number(tv); isNum do append(&pr.tiles, i32(t))
				append(&n.patterns, pr)
			}
		}
		append(&g.nodes, n)
	}
	return g, ""
}

// Gen_GraphSerialize writes a graph as .levelgen.json text.
Gen_GraphSerialize :: proc(g: ^Gen_Graph, allocator := context.allocator) -> string {
	w: Json_Writer
	w.sb = strings.builder_make(allocator)
	fmt.sbprintf(&w.sb, "{{\"%s\": %d, \"size\": [%d, %d], \"seed\": %d", FORMAT_KEY, FORMAT_CURRENT[.LevelGen], g.size.x, g.size.y, g.seed)
	if g.output != 0 do fmt.sbprintf(&w.sb, ", \"output\": %d", g.output)
	strings.write_string(&w.sb, ", \"nodes\": [")
	for &n, i in g.nodes {
		strings.write_string(&w.sb, "," if i > 0 else "")
		strings.write_string(&w.sb, "\n  {\"id\": ")
		fmt.sbprintf(&w.sb, "%d, \"type\": ", n.id)
		info := Gen_NodeInfo(&n)
		Json_String(&w, info.name)
		if len(info.inputs) > 0 {
			strings.write_string(&w.sb, ", \"inputs\": {")
			k := 0
			for port, pi in info.inputs {
				if n.inputs[pi] == 0 do continue
				if k > 0 do strings.write_string(&w.sb, ", ")
				Json_String(&w, port)
				fmt.sbprintf(&w.sb, ": %d", n.inputs[pi])
				k += 1
			}
			strings.write_byte(&w.sb, '}')
		}
		if len(info.params) > 0 {
			strings.write_string(&w.sb, ", \"params\": {")
			for p, pi in info.params {
				if pi > 0 do strings.write_string(&w.sb, ", ")
				Json_String(&w, p.name)
				strings.write_string(&w.sb, ": ")
				if len(p.choices) > 0 do Json_String(&w, p.choices[clamp(int(n.params[pi]), 0, len(p.choices) - 1)])
				else do Json_Float(&w, f32(n.params[pi]))
			}
			strings.write_byte(&w.sb, '}')
		}
		if n.kind == .Tile_Output {
			strings.write_string(&w.sb, ", \"rules\": [")
			for r, ri in n.rules {
				if ri > 0 do strings.write_string(&w.sb, ", ")
				strings.write_string(&w.sb, "{\"min\": ")
				Json_Float(&w, r.min)
				strings.write_string(&w.sb, ", \"max\": ")
				Json_Float(&w, r.max)
				strings.write_string(&w.sb, ", \"tiles\": [")
				for t, ti in r.tiles do fmt.sbprintf(&w.sb, "%s%d", ", " if ti > 0 else "", t)
				strings.write_byte(&w.sb, ']')
				if r.terrain != "" {
					strings.write_string(&w.sb, ", \"terrain\": ")
					Json_String(&w, r.terrain)
				}
				strings.write_byte(&w.sb, '}')
			}
			strings.write_byte(&w.sb, ']')
			if len(n.patterns) > 0 {
				strings.write_string(&w.sb, ", \"patterns\": [")
				for pr, pi in n.patterns {
					if pi > 0 do strings.write_string(&w.sb, ", ")
					strings.write_string(&w.sb, "{\"min\": ")
					Json_Float(&w, pr.min)
					strings.write_string(&w.sb, ", \"max\": ")
					Json_Float(&w, pr.max)
					strings.write_string(&w.sb, ", \"chance\": ")
					Json_Float(&w, pr.chance)
					strings.write_string(&w.sb, ", \"cells\": [")
					for c, ci in pr.cells do fmt.sbprintf(&w.sb, "%s%d", ", " if ci > 0 else "", c)
					strings.write_string(&w.sb, "], \"tiles\": [")
					for t, ti in pr.tiles do fmt.sbprintf(&w.sb, "%s%d", ", " if ti > 0 else "", t)
					strings.write_string(&w.sb, "]}")
				}
				strings.write_byte(&w.sb, ']')
			}
			if n.tileset != "" {
				strings.write_string(&w.sb, ", \"tileset\": ")
				Json_String(&w, n.tileset)
			}
			if n.layer != "" {
				strings.write_string(&w.sb, ", \"layer\": ")
				Json_String(&w, n.layer)
			}
		}
		if n.kind == .Entity_Output {
			strings.write_string(&w.sb, ", \"component\": ")
			Json_String(&w, n.component)
		}
		if n.kind == .Script {
			strings.write_string(&w.sb, ", \"script\": ")
			Json_String(&w, n.script)
		}
		if n.pos != {} {
			strings.write_string(&w.sb, ", \"pos\": ")
			Json_Vec2(&w, n.pos)
		}
		strings.write_byte(&w.sb, '}')
	}
	strings.write_string(&w.sb, "\n]")
	// (Only when there are any: a graph without frames saves as before.)
	if len(g.frames) > 0 {
		strings.write_string(&w.sb, ", \"frames\": [")
		for f, i in g.frames {
			strings.write_string(&w.sb, "," if i > 0 else "")
			strings.write_string(&w.sb, "\n  {\"title\": ")
			Json_String(&w, f.title)
			strings.write_string(&w.sb, ", \"pos\": ")
			Json_Vec2(&w, f.pos)
			strings.write_string(&w.sb, ", \"size\": ")
			Json_Vec2(&w, f.size)
			strings.write_string(&w.sb, ", \"color\": [")
			for c, ci in f.color {
				if ci > 0 do strings.write_string(&w.sb, ", ")
				Json_Float(&w, c)
			}
			strings.write_string(&w.sb, "]}")
		}
		strings.write_string(&w.sb, "\n]")
	}
	strings.write_string(&w.sb, "}\n")
	return strings.to_string(w.sb)
}

// --- editing (the editor's Generator window) -------------------------------------------

// GEN_TEMPLATE_CAVE: a new generator - a closed cave on 48 x 32 cells.
GEN_TEMPLATE_CAVE :: `{"size": [48, 32], "seed": 1, "nodes": [
  {"id": 1, "type": "random_fill", "params": {"density": 0.48}, "pos": [0, 0]},
  {"id": 2, "type": "cellular", "inputs": {"in": 1}, "params": {"iterations": 5}, "pos": [220, 0]},
  {"id": 3, "type": "border", "params": {"width": 1}, "pos": [220, 170]},
  {"id": 4, "type": "combine", "inputs": {"a": 2, "b": 3}, "params": {"op": "max"}, "pos": [440, 60]},
  {"id": 5, "type": "tile_output", "inputs": {"in": 4}, "rules": [{"min": 0.5, "max": 1, "tiles": [0]}], "pos": [660, 60]}
]}
`

// Gen_AddNode adds a node of a kind (default parameters; a tile output gets
// one rule for solid cells) with a new id. A Custom one: the registered
// kind `custom`.
Gen_AddNode :: proc(g: ^Gen_Graph, kind: Gen_Kind, pos: [2]f32, custom := "") -> ^Gen_Node {
	id := 1
	for n in g.nodes do id = max(id, n.id + 1)
	n := Gen_NodeDefaults(kind, id, custom)
	n.pos = pos
	if kind == .Custom do gen_set_text(g, &n.custom, custom)
	if kind == .Tile_Output {
		n.rules = make([dynamic]Gen_Tile_Rule, g.allocator)
		r := Gen_Tile_Rule{min = 0.5, max = 1, tiles = make([dynamic]i32, g.allocator)}
		append(&r.tiles, 0)
		append(&n.rules, r)
	}
	append(&g.nodes, n)
	return &g.nodes[len(g.nodes) - 1]
}

// Gen_DuplicateNode copies a node (parameters, rules; not its inputs).
Gen_DuplicateNode :: proc(g: ^Gen_Graph, id: int, offset := [2]f32{30, 30}) -> ^Gen_Node {
	src := Gen_FindNode(g, id)
	if src == nil do return nil
	copied := src^
	n := Gen_AddNode(g, copied.kind, copied.pos + offset)
	newId := n.id
	Gen_NodeClearRules(n, g.allocator)
	n^ = copied
	n.id, n.pos, n.inputs = newId, copied.pos + offset, {}
	n.rules, n.patterns = nil, nil
	n.component, n.script, n.custom, n.tileset, n.layer = "", "", "", "", ""
	Gen_SetComponent(g, n, copied.component)
	Gen_SetTileset(g, n, copied.tileset)
	Gen_SetLayer(g, n, copied.layer)
	Gen_SetScript(g, n, copied.script)
	gen_set_text(g, &n.custom, copied.custom)
	if len(copied.rules) > 0 {
		n.rules = make([dynamic]Gen_Tile_Rule, g.allocator)
		for r in copied.rules {
			c := Gen_Tile_Rule{min = r.min, max = r.max, tiles = make([dynamic]i32, g.allocator), terrain = strings.clone(r.terrain, g.allocator) if r.terrain != "" else ""}
			append(&c.tiles, ..r.tiles[:])
			append(&n.rules, c)
		}
	}
	if len(copied.patterns) > 0 {
		n.patterns = make([dynamic]Gen_Pattern_Rule, g.allocator)
		for pr in copied.patterns {
			c := pr
			c.tiles = make([dynamic]i32, g.allocator)
			append(&c.tiles, ..pr.tiles[:])
			append(&n.patterns, c)
		}
	}
	return n
}

// Gen_RemoveNode deletes a node; inputs that read it are disconnected.
Gen_RemoveNode :: proc(g: ^Gen_Graph, id: int) -> bool {
	for &n, i in g.nodes {
		if n.id != id do continue
		gen_node_free(g, &n)
		ordered_remove(&g.nodes, i)
		for &o in g.nodes do for &src in o.inputs do if src == id do src = 0
		if g.output == id do g.output = 0
		return true
	}
	return false
}

// GEN_CLIP_KEY marks clipboard text as level generator nodes (#171): the
// editor pastes text only when it carries it.
GEN_CLIP_KEY :: "rayzr_levelgen_nodes"

// Gen_CopyNodes writes nodes as clipboard text: a .levelgen.json holding
// only them (and the key above). Links between them are kept; links to
// nodes left out are dropped. "" when none of `ids` is in the graph.
Gen_CopyNodes :: proc(g: ^Gen_Graph, ids: []int, allocator := context.allocator) -> string {
	// (Through the text: a deep copy for free, and Gen_RemoveNode already
	// disconnects whatever read a node that isn't copied.)
	c, err := Gen_GraphParse(transmute([]u8)Gen_GraphSerialize(g, context.temp_allocator), context.temp_allocator)
	if err != "" do return ""
	for i := len(c.nodes) - 1; i >= 0; i -= 1 {
		keep := false
		for id in ids do if c.nodes[i].id == id do keep = true
		if !keep do Gen_RemoveNode(&c, c.nodes[i].id)
	}
	if len(c.nodes) == 0 do return ""
	c.output = 0
	clear(&c.frames)
	text := Gen_GraphSerialize(&c, context.temp_allocator)
	return fmt.aprintf("{{\"%s\": true, %s", GEN_CLIP_KEY, text[1:], allocator = allocator)
}

// Gen_IsNodesClip: the text is Gen_CopyNodes's.
Gen_IsNodesClip :: proc(text: string) -> bool {
	return strings.has_prefix(text, "{\"" + GEN_CLIP_KEY + "\"")
}

// Gen_PasteNodes adds the nodes of clipboard text (Gen_CopyNodes) to a
// graph with new ids, their links kept, placed so the top-left of the group
// is at `at`. Returns the new ids (allocator) or why it can't (an unknown -
// unregistered - node type, not node text).
Gen_PasteNodes :: proc(g: ^Gen_Graph, text: string, at: [2]f32, allocator := context.allocator) -> (ids: []int, err: string) {
	if !Gen_IsNodesClip(text) do return nil, "not level generator nodes"
	c, perr := Gen_GraphParse(transmute([]u8)text, g.allocator)
	if perr != "" {
		Gen_GraphDestroy(&c)
		return nil, perr
	}
	defer Gen_GraphDestroy(&c)
	if len(c.nodes) == 0 do return nil, "no nodes"
	next := 1
	for n in g.nodes do next = max(next, n.id + 1)
	remap := make(map[int]int, context.temp_allocator)
	lo := c.nodes[0].pos
	for n in c.nodes {
		remap[n.id] = next
		next += 1
		lo = {min(lo.x, n.pos.x), min(lo.y, n.pos.y)}
	}
	out := make([]int, len(c.nodes), allocator)
	// The parsed nodes' text and rules are in the graph's allocator: they
	// move over as they are (c is left with none to free).
	for n, i in c.nodes {
		m := n
		m.id = remap[n.id]
		for &src in m.inputs do src = remap[src] or_else 0
		m.pos = at + (n.pos - lo)
		append(&g.nodes, m)
		out[i] = m.id
	}
	clear(&c.nodes)
	return out, ""
}

// Gen_AddFrame adds a comment frame (titled "Comment", the default colour).
Gen_AddFrame :: proc(g: ^Gen_Graph, pos, size: [2]f32, title := "Comment") -> ^Gen_Frame {
	if g.frames == nil do g.frames = make([dynamic]Gen_Frame, g.allocator)
	f := Gen_Frame{color = GEN_FRAME_COLOR, pos = pos, size = {max(size.x, 40), max(size.y, 40)}}
	gen_set_text(g, &f.title, title)
	append(&g.frames, f)
	return &g.frames[len(g.frames) - 1]
}

// Gen_SetFrameTitle: the graph owns the text.
Gen_SetFrameTitle :: proc(g: ^Gen_Graph, f: ^Gen_Frame, title: string) {gen_set_text(g, &f.title, title)}

// Gen_RemoveFrame deletes a frame (by index); the nodes in it stay.
Gen_RemoveFrame :: proc(g: ^Gen_Graph, i: int) -> bool {
	if i < 0 || i >= len(g.frames) do return false
	gen_set_text(g, &g.frames[i].title, "")
	ordered_remove(&g.frames, i)
	return true
}

// Gen_Reads: does node `id` read `src`, directly or through others?
Gen_Reads :: proc(g: ^Gen_Graph, id, src: int, depth := 0) -> bool {
	if id == src do return true
	n := Gen_FindNode(g, id)
	if n == nil || depth > 256 do return false
	for i in n.inputs do if i != 0 && Gen_Reads(g, i, src, depth + 1) do return true
	return false
}

// Gen_Connect links `src`'s output to input `port` of `dst` (0 = none);
// refused when it would make a cycle or the port doesn't exist.
Gen_Connect :: proc(g: ^Gen_Graph, dst: int, port: int, src: int) -> bool {
	n := Gen_FindNode(g, dst)
	if n == nil || port < 0 || port >= len(Gen_NodeInfo(n).inputs) do return false
	if src != 0 && (Gen_FindNode(g, src) == nil || Gen_Reads(g, src, dst)) do return false
	n.inputs[port] = src
	return true
}

// Gen_OutputNode: the node whose grid is the graph's result.
Gen_OutputNode :: proc(g: ^Gen_Graph) -> ^Gen_Node {
	if g.output != 0 do if n := Gen_FindNode(g, g.output); n != nil do return n
	#reverse for &n in g.nodes do if n.kind == .Tile_Output do return &n
	return &g.nodes[len(g.nodes) - 1] if len(g.nodes) > 0 else nil
}

// Gen_ApplyTileMap generates into a tile map: its map becomes the level's
// size and its cells the tiles (colliders rebuilt when it is Solid and in
// the game).
Gen_ApplyTileMap :: proc(g: ^Gen_Graph, tm: ^TileMapNode, seed: u64 = 0, ctx: ^GameContext = nil, scene: ^Scene = nil) -> string {
	g.layout, g.stagger = tm.layout, tm.stagger
	r, err := Gen_Generate(g, seed, context.temp_allocator)
	if err != "" do return err
	return Gen_ApplyResult(&r, tm, ctx, scene)
}

// Gen_ApplyResult writes a generated level into a tile map (tiles,
// colliders) - and each layer into the TileMap of its name next to it (a
// sibling, or a child) - and spawns its entities under it (those of the
// last generation go first). A layer without its TileMap is an error (the
// rest is written).
Gen_ApplyResult :: proc(r: ^Gen_Result, tm: ^TileMapNode, ctx: ^GameContext = nil, scene: ^Scene = nil) -> string {
	gen_apply_tiles(tm, r.tiles, r.size, ctx)
	missing := ""
	for ly in r.layers {
		target := Gen_LayerTileMap(tm, ly.name)
		if target == nil {
			if missing == "" do missing = fmt.tprintf("no TileMap %q next to %s for its layer", ly.name, tm.name)
			continue
		}
		gen_apply_tiles(target, ly.tiles, r.size, ctx)
	}

	// Entities: children of the map, at their cells' centres; those of the
	// last generation go first.
	sc := scene
	if sc == nil && ctx != nil do sc = ctx.scene if ctx.scene != nil else (ctx.game.sceneManager.currentScene if ctx.game != nil else nil)
	if sc == nil do return missing
	for c in GetChildrenTemp(sc.manager, tm) do if c != nil && !c.removing && Node_HasTag(c, GEN_ENTITY_TAG) do RemoveNode(sc.manager, c)
	for en in r.entities {
		n := Scene_InstantiateComponent(sc, en.component, tm, ctx)
		if n == nil do return fmt.tprintf("no component %s", en.component)
		n.position = TileMapNode_CellLocalCenter(tm, en.cell) // (any grid)
		Node_AddTag(n, GEN_ENTITY_TAG)
	}
	return missing
}

// Gen_LayerTileMap: the TileMap a layer named `name` fills - next to the
// main map (its sibling), else its child.
Gen_LayerTileMap :: proc(main: ^TileMapNode, name: string) -> ^TileMapNode {
	if main == nil || name == "" do return nil
	for list in ([2][]^Node{GetChildrenView(nil, main.parent), GetChildrenView(nil, main)}) {
		for c in list do if c != nil && !c.removing && c.typeId == TileMapNode && c.name == name && c != main do return cast(^TileMapNode)c
	}
	return nil
}

@(private = "file")
gen_apply_tiles :: proc(tm: ^TileMapNode, tiles: []i32, size: [2]int, ctx: ^GameContext) {
	tm.mapSize = size
	TileMapNode_Reset(tm)
	for t, i in tiles do if t >= 0 do TileMapNode_Set(tm, i % size.x, i / size.x, t)
	TileMapNode_Changed(tm)
	if tm.solid && tm.isReady && ctx != nil do TileMapNode_BuildColliders(tm, ctx)
}

// Gen_LoadFile reads a project's .levelgen.json.
Gen_LoadFile :: proc(ctx: ^GameContext, path: string, allocator := context.allocator) -> (Gen_Graph, string) {
	if ctx == nil || ctx.game == nil do return {}, "no game"
	text, ok := AssetManager_ReadFileString(&ctx.game.assetManager, path, context.temp_allocator)
	if !ok do return {}, fmt.tprintf("no file %s", path)
	g, err := Gen_GraphParse(transmute([]u8)text, allocator)
	if err != "" {
		Gen_GraphDestroy(&g)
		return {}, fmt.tprintf("%s: %s", path, err)
	}
	Gen_LoadScripts(&g, ctx)
	Gen_LoadTerrains(&g, ctx)
	return g, ""
}

// --- rooms and corridors ----------------------------------------------------------------

@(private)
gen_carve :: proc(out: ^Gen_Grid, x, y, w, h: int) {
	for yy in max(y, 0) ..< min(y + h, out.h) do for xx in max(x, 0) ..< min(x + w, out.w) do out.v[yy * out.w + xx] = 1
}

// gen_bsp splits an area in two until its parts are small, puts a room in
// each part and joins the two halves of every split with a corridor
// (between a room of each). Returns the centre of one of its rooms.
@(private)
gen_bsp :: proc(out: ^Gen_Grid, r: [4]int, minS, maxS, corridor: int, rng: ^u64, depth: int) -> [2]int {
	x, y, w, h := r[0], r[1], r[2], r[3]
	need := minS + 2 // a room and a cell around it
	canW, canH := w >= need * 2, h >= need * 2
	if depth < 16 && (canW || canH) && (w > maxS + 2 || h > maxS + 2) {
		vertical := canW && (!canH || w > h || (w == h && gen_rand_int(rng, 0, 1) == 0))
		a, b: [4]int
		if vertical {
			s := gen_rand_int(rng, need, w - need)
			a, b = {x, y, s, h}, {x + s, y, w - s, h}
		} else {
			s := gen_rand_int(rng, need, h - need)
			a, b = {x, y, w, s}, {x, y + s, w, h - s}
		}
		c1 := gen_bsp(out, a, minS, maxS, corridor, rng, depth + 1)
		c2 := gen_bsp(out, b, minS, maxS, corridor, rng, depth + 1)
		// An L: along x at c1's row, then along y at c2's column.
		gen_carve(out, min(c1.x, c2.x), c1.y, abs(c2.x - c1.x) + corridor, corridor)
		gen_carve(out, c2.x, min(c1.y, c2.y), corridor, abs(c2.y - c1.y) + corridor)
		return c1 if gen_rand_int(rng, 0, 1) == 0 else c2
	}
	// A leaf: a room inside it (a cell of wall around).
	rw := clamp(gen_rand_int(rng, minS, maxS), 1, max(w - 2, 1))
	rh := clamp(gen_rand_int(rng, minS, maxS), 1, max(h - 2, 1))
	rx := x + gen_rand_int(rng, 1, max(w - rw - 1, 1))
	ry := y + gen_rand_int(rng, 1, max(h - rh - 1, 1))
	gen_carve(out, rx, ry, rw, rh)
	return {rx + rw / 2, ry + rh / 2}
}

// gen_rand_int: the next random number in lo..hi (inclusive) of a
// node's own sequence.
@(private)
gen_rand_int :: proc(state: ^u64, lo, hi: int) -> int {
	if hi <= lo do return lo
	state^ = gen_mix(state^, 0x2545f4914f6cdd1d)
	return lo + int(state^ % u64(hi - lo + 1))
}

// --- entities and LDtk ----------------------------------------------------------------

// GEN_ENTITY_TAG marks the nodes a generator spawned (generating again
// replaces them).
GEN_ENTITY_TAG :: "levelgen"

// Gen_ApplyIntGrid writes the output's tiles into an LDtk IntGrid layer as
// values (empty and negative: 0), one undo step, then runs the auto
// layers' rules. The layer keeps its size: cells outside the generator are
// left as they are.
Gen_ApplyIntGrid :: proc(g: ^Gen_Graph, doc: ^Ldtk_Doc, li, layer: int, seed: u64 = 0) -> string {
	if doc == nil || li < 0 || li >= len(doc.levels) || layer < 0 || layer >= len(doc.levels[li].layers) do return "no such LDtk layer"
	ly := &doc.levels[li].layers[layer]
	if ly.def < 0 || doc.layerDefs[ly.def].type != .IntGrid do return "not an IntGrid layer"
	tiles, size, err := Gen_Tiles(g, 0, seed, context.temp_allocator)
	if err != "" do return err
	Ldtk_Doc_BeginCells(doc, li, layer, "Generate level")
	for y in 0 ..< min(size.y, ly.cHei) do for x in 0 ..< min(size.x, ly.cWid) {
		Ldtk_Doc_SetIntGrid(doc, li, layer, x, y, max(int(tiles[y * size.x + x]), 0))
	}
	Ldtk_Doc_EndCells(doc)
	Ldtk_Doc_ApplyRules(doc, li, layer, 0, 0, ly.cWid, ly.cHei)
	return ""
}

// --- your own nodes: Odin --------------------------------------------------------------

// A call of a registered node's proc: its input grids (zeros when not
// connected), the grid to fill (zeros) and its own seed (the graph's, its
// id and its "seed" parameter mixed; Gen_Random01 makes numbers of it).
Gen_Custom_Call :: struct {
	node:   ^Gen_Node, // (Gen_Param(call.node, "name") reads a parameter)
	inputs: [2]Gen_Grid,
	out:    Gen_Grid,
	seed:   u64,
}

// The proc of a registered node: fills call.out; an error stops the graph.
Gen_Custom_Proc :: #type proc(call: ^Gen_Custom_Call) -> (err: string)

Gen_Custom_Kind :: struct {
	info: Gen_Kind_Info,
	eval: Gen_Custom_Proc,
}

@(private = "file")
gen_custom_kinds: [dynamic]Gen_Custom_Kind

// Gen_RegisterNode adds a node type of your own, from Odin (a game's or an
// editor plugin's startup): `info` names it ("type" in the file; not a
// built-in's), its inputs (at most 2) and parameters (at most 8). Its
// strings and slices must stay valid (constants). Registering a name again
// replaces it. Returns why it was refused ("" = done).
Gen_RegisterNode :: proc(info: Gen_Kind_Info, eval: Gen_Custom_Proc) -> string {
	if info.name == "" || eval == nil do return "a node type needs a name and a proc"
	if _, builtin := Gen_Kind_FromName(info.name); builtin || info.name == "custom" do return fmt.tprintf("%q is a built-in node type", info.name)
	if len(info.inputs) > 2 do return "at most 2 inputs"
	if len(info.params) > 8 do return "at most 8 parameters"
	if def := Gen_FindCustomKind(info.name); def != nil {
		def^ = {info, eval}
		return ""
	}
	if gen_custom_kinds == nil do gen_custom_kinds = make([dynamic]Gen_Custom_Kind, Engine_HeapAllocator())
	append(&gen_custom_kinds, Gen_Custom_Kind{info, eval})
	return ""
}

Gen_UnregisterNode :: proc(name: string) -> bool {
	for def, i in gen_custom_kinds do if def.info.name == name {
		ordered_remove(&gen_custom_kinds, i)
		return true
	}
	return false
}

Gen_FindCustomKind :: proc(name: string) -> ^Gen_Custom_Kind {
	if name == "" do return nil
	for &def in gen_custom_kinds do if def.info.name == name do return &def
	return nil
}

// Gen_CustomKinds: the registered node types (the editor's Add menu).
Gen_CustomKinds :: proc() -> []Gen_Custom_Kind {return gen_custom_kinds[:]}

// Gen_Random01: a cell's random number in [0, 1) for a seed - the same
// one every time (for a registered node: call.seed).
Gen_Random01 :: proc(x, y: int, seed: u64) -> f32 {return gen_hash01(x, y, seed)}

// --- your own nodes: Lua ---------------------------------------------------------------
//
// A Script node runs a .lua file that returns a function of ctx:
//
//   return function(ctx)
//       for y = 0, ctx.height - 1 do
//           for x = 0, ctx.width - 1 do
//               local i = y * ctx.width + x + 1
//               ctx.out[i] = ctx.a[i] > 0.5 and ctx.random(x, y) or 0
//           end
//       end
//   end
//
// ctx: width, height, seed (the node's), params {p1..p4}, a and b (the
// inputs: flat row-major arrays from 1, zeros when not connected), out (the
// grid to fill: zeros), random(x, y) (the cell's number in [0, 1) - the same
// for a seed). It may return its own array instead of filling out. Scripts
// run in a sandbox of their own (base, math, string, table; no files),
// deterministic, and are stopped after GEN_SCRIPT_BUDGET instructions.

GEN_SCRIPT_TEMPLATE :: `-- A level generator node (#142): fills ctx.out from its inputs.
-- ctx.width, ctx.height, ctx.seed, ctx.params.p1 .. p4,
-- ctx.a / ctx.b (the inputs) and ctx.out: flat arrays, row by row, from 1.
-- ctx.random(x, y): the cell's number in [0, 1), the same for a seed.
return function(ctx)
    for y = 0, ctx.height - 1 do
        for x = 0, ctx.width - 1 do
            local i = y * ctx.width + x + 1
            -- Stripes every p1 cells (4 when it is 0), over input a.
            local every = ctx.params.p1 > 0 and ctx.params.p1 or 4
            ctx.out[i] = math.max(ctx.a[i], (x % every == 0) and 1 or 0)
        end
    end
end
`

// GEN_SCRIPT_BUDGET: instructions a graph's scripts may run per evaluation
// (then "ran too long": a script that never ends doesn't hang the editor).
GEN_SCRIPT_BUDGET := c.int(200_000_000)

// Gen_LoadScripts reads the script nodes' files (a project's) into the
// graph, again when called again (an edited script). A file that can't be
// read is an error when the node is evaluated.
Gen_LoadScripts :: proc(g: ^Gen_Graph, ctx: ^GameContext) {
	gen_scripts_clear(g)
	if ctx == nil || ctx.game == nil do return
	for &n in g.nodes {
		if n.kind != .Script || n.script == "" || n.script in g.scripts do continue
		if text, ok := AssetManager_ReadFileString(&ctx.game.assetManager, n.script, context.temp_allocator); ok do Gen_SetScriptSource(g, n.script, text)
	}
}

// Gen_LoadTerrains reads the terrains of the tile outputs' tilesets
// (their .tileset.json files) into the graph, again when called again.
Gen_LoadTerrains :: proc(g: ^Gen_Graph, ctx: ^GameContext) {
	gen_tilesets_clear(g)
	if ctx == nil || ctx.game == nil do return
	for &n in g.nodes {
		if n.kind != .Tile_Output || n.tileset == "" || n.tileset in g.tilesets do continue
		if text, ok := AssetManager_ReadFileString(&ctx.game.assetManager, Terrain_SidecarPath(n.tileset), context.temp_allocator); ok do Gen_SetTerrainSource(g, n.tileset, text)
	}
}

// Gen_SetTerrainSource gives the graph a tileset's terrains file text (as
// if read for the image `image`).
Gen_SetTerrainSource :: proc(g: ^Gen_Graph, image, text: string) {
	if g.tilesets == nil do g.tilesets = make(map[string]string, g.allocator)
	if old, ok := g.tilesets[image]; ok {
		delete(old, g.allocator)
		g.tilesets[image] = strings.clone(text, g.allocator)
		return
	}
	g.tilesets[strings.clone(image, g.allocator)] = strings.clone(text, g.allocator)
}

@(private = "file")
gen_tilesets_clear :: proc(g: ^Gen_Graph) {
	for k, v in g.tilesets {
		delete(k, g.allocator)
		delete(v, g.allocator)
	}
	clear(&g.tilesets)
}

// Gen_SetScriptSource gives the graph a script's text (as if read from `path`).
Gen_SetScriptSource :: proc(g: ^Gen_Graph, path, text: string) {
	if g.scripts == nil do g.scripts = make(map[string]string, g.allocator)
	if old, ok := g.scripts[path]; ok {
		delete(old, g.allocator)
		g.scripts[path] = strings.clone(text, g.allocator)
		return
	}
	g.scripts[strings.clone(path, g.allocator)] = strings.clone(text, g.allocator)
}

@(private = "file")
gen_scripts_clear :: proc(g: ^Gen_Graph) {
	for k, v in g.scripts {
		delete(k, g.allocator)
		delete(v, g.allocator)
	}
	clear(&g.scripts)
}

// gen_script: a Script node's grid from its function.
@(private)
gen_script :: proc(ev: ^Gen_Eval, n: ^Gen_Node, seed: u64, out: Gen_Grid) -> bool {
	fail :: proc(ev: ^Gen_Eval, n: ^Gen_Node, why: string) -> bool {
		ev.err = fmt.tprintf("node %d (%s): %s", n.id, n.script, why) if n.script != "" else fmt.tprintf("node %d: %s", n.id, why)
		return false
	}
	if n.script == "" do return fail(ev, n, "pick its script (a .lua file)")
	src, have := ev.g.scripts[n.script]
	if !have do return fail(ev, n, "no such script (or not loaded)")
	a := gen_input(ev, n, 0) or_return
	b := gen_input(ev, n, 1) or_return
	if ev.L == nil do ev.L = gen_lua_sandbox()
	L := ev.L
	top := lua.gettop(L)
	defer lua.settop(L, top)
	errText :: proc(L: ^lua.State) -> string {
		msg := lua.tostring(L, -1)
		return strings.clone(string(msg), context.temp_allocator) if msg != nil else "error"
	}
	ref, loaded := ev.fns[n.script]
	if !loaded {
		chunk := fmt.ctprintf("@%s", n.script)
		if lua.L_loadbuffer(L, raw_data(src), len(src), chunk, "t") != .OK do return fail(ev, n, errText(L))
		if lua.pcall(L, 0, 1, 0) != 0 do return fail(ev, n, errText(L))
		if !lua.isfunction(L, -1) do return fail(ev, n, "the script must return a function(ctx)")
		ref = lua.L_ref(L, lua.REGISTRYINDEX)
		ev.fns[n.script] = ref
	}
	cells := len(out.v)
	pushGrid :: proc(L: ^lua.State, g: Gen_Grid) {
		lua.createtable(L, c.int(len(g.v)), 0)
		for v, i in g.v {
			lua.pushnumber(L, lua.Number(v))
			lua.rawseti(L, -2, lua.Integer(i + 1))
		}
	}
	pushGrid(L, out) // (kept below the call: ctx.out)
	outIdx := lua.gettop(L)
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(ref))
	lua.createtable(L, 0, 9)
	lua.pushinteger(L, lua.Integer(out.w))
	lua.setfield(L, -2, "width")
	lua.pushinteger(L, lua.Integer(out.h))
	lua.setfield(L, -2, "height")
	lua.pushinteger(L, lua.Integer(seed >> 1)) // (a positive integer)
	lua.setfield(L, -2, "seed")
	lua.createtable(L, 0, 4)
	for name in ([]cstring{"p1", "p2", "p3", "p4"}) {
		lua.pushnumber(L, lua.Number(Gen_Param(n, string(name))))
		lua.setfield(L, -2, name)
	}
	lua.setfield(L, -2, "params")
	pushGrid(L, a)
	lua.setfield(L, -2, "a")
	pushGrid(L, b)
	lua.setfield(L, -2, "b")
	lua.pushvalue(L, outIdx)
	lua.setfield(L, -2, "out")
	lua.pushinteger(L, lua.Integer(seed >> 1))
	lua.pushcclosure(L, gen_lua_random, 1)
	lua.setfield(L, -2, "random")
	if lua.pcall(L, 1, 1, 0) != 0 do return fail(ev, n, errText(L))
	res := lua.gettop(L) if lua.istable(L, -1) else outIdx
	for i in 0 ..< cells {
		lua.rawgeti(L, res, lua.Integer(i + 1))
		ok: b32
		v := lua.tonumber(L, -1, &ok)
		out.v[i] = f32(v) if ok else 0
		lua.pop(L, 1)
	}
	return true
}

// gen_lua_sandbox: a Lua state for scripts - base, math, string, table; no
// files, no modules; stopped when it runs too long.
@(private = "file")
gen_lua_sandbox :: proc() -> ^lua.State {
	L := lua.L_newstate()
	libs := [?]struct {
		name: cstring,
		open: lua.CFunction,
	}{{"_G", lua.open_base}, {"math", lua.open_math}, {"string", lua.open_string}, {"table", lua.open_table}}
	for lib in libs {
		lua.L_requiref(L, lib.name, lib.open, 1)
		lua.pop(L, 1)
	}
	for name in ([]cstring{"dofile", "loadfile", "require"}) {
		lua.pushnil(L)
		lua.setglobal(L, name)
	}
	lua.sethook(L, gen_lua_too_long, lua.MASKCOUNT, GEN_SCRIPT_BUDGET)
	return L
}

@(private = "file")
gen_lua_too_long :: proc "c" (L: ^lua.State, ar: ^lua.Debug) {
	lua.L_error(L, "ran too long (stopped)")
}

// ctx.random(x, y): the cell's number in [0, 1) for the node's seed.
@(private = "file")
gen_lua_random :: proc "c" (L: ^lua.State) -> c.int {
	context = Engine_DefaultContext()
	seed := u64(lua.tointeger(L, lua.REGISTRYINDEX - 1))
	lua.pushnumber(L, lua.Number(gen_hash01(int(lua.tointeger(L, 1)), int(lua.tointeger(L, 2)), seed)))
	return 1
}

// --- deterministic noise --------------------------------------------------------------

@(private)
gen_mix :: proc(a, b: u64) -> u64 {
	// splitmix64 of a combination: stable on every platform.
	z := a ~ (b + 0x9e3779b97f4a7c15 + (a << 6) + (a >> 2))
	z = (z ~ (z >> 30)) * 0xbf58476d1ce4e5b9
	z = (z ~ (z >> 27)) * 0x94d049bb133111eb
	return z ~ (z >> 31)
}

// gen_hash01: a cell's random number in [0, 1) for a seed.
@(private)
gen_hash01 :: proc(x, y: int, seed: u64) -> f32 {
	h := gen_mix(gen_mix(seed, u64(i64(x))), u64(i64(y)) + 0x51ed27)
	return f32(h >> 40) / f32(1 << 24)
}

@(private)
gen_value_noise :: proc(x, y: f32, seed: u64) -> f32 {
	x0, y0 := math.floor(x), math.floor(y)
	fx, fy := x - x0, y - y0
	ix, iy := int(x0), int(y0)
	sx, sy := fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
	a := gen_hash01(ix, iy, seed)
	b := gen_hash01(ix + 1, iy, seed)
	c := gen_hash01(ix, iy + 1, seed)
	d := gen_hash01(ix + 1, iy + 1, seed)
	return math.lerp(math.lerp(a, b, sx), math.lerp(c, d, sx), sy)
}

// --- Lua: LevelGen ------------------------------------------------------------------------
// LevelGen.generate(generator, tilemap [, seed]) -> true | false, why (tiles and entities)
// LevelGen.values(generator [, seed [, node_id]]) -> {width, height, values = {row-major}} | nil, why

@(private = "file")
lua_levelgen_generate :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	tmNode, isNode := to_node_userdata(L, 2)
	fail :: proc(L: ^lua.State, why: string) -> c.int {
		lua.pushboolean(L, false)
		lua.pushstring(L, strings.clone_to_cstring(why, context.temp_allocator))
		return 2
	}
	if sm == nil || sm.game == nil || lua.type(L, 1) != .STRING do return fail(L, "usage: LevelGen.generate(\"levels/caves.levelgen.json\", tilemap [, seed])")
	if !isNode || tmNode.typeId != TileMapNode do return fail(L, "the second argument isn't a TileMap node")
	seed := u64(lua.tointeger(L, 3)) if lua.type(L, 3) == .NUMBER else 0
	g, err := Gen_LoadFile(&sm.game.gameContext, string(lua.tostring(L, 1)), context.temp_allocator)
	if err != "" do return fail(L, err)
	defer Gen_GraphDestroy(&g)
	if e := Gen_ApplyTileMap(&g, cast(^TileMapNode)tmNode, seed, &sm.game.gameContext); e != "" do return fail(L, e)
	EventBus_Publish(&sm.game.events, "level_generated", tmNode.name, tmNode)
	lua.pushboolean(L, true)
	return 1
}

@(private = "file")
lua_levelgen_values :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || lua.type(L, 1) != .STRING {
		lua.pushnil(L)
		lua.pushstring(L, "usage: LevelGen.values(\"levels/caves.levelgen.json\" [, seed [, node_id]])")
		return 2
	}
	seed := u64(lua.tointeger(L, 2)) if lua.type(L, 2) == .NUMBER else 0
	id := int(lua.tointeger(L, 3)) if lua.type(L, 3) == .NUMBER else 0
	g, err := Gen_LoadFile(&sm.game.gameContext, string(lua.tostring(L, 1)), context.temp_allocator)
	defer Gen_GraphDestroy(&g)
	grid: Gen_Grid
	if err == "" do grid, err = Gen_Evaluate(&g, id, seed, context.temp_allocator)
	if err != "" {
		lua.pushnil(L)
		lua.pushstring(L, strings.clone_to_cstring(err, context.temp_allocator))
		return 2
	}
	lua.createtable(L, 0, 3)
	lua.pushinteger(L, lua.Integer(grid.w))
	lua.setfield(L, -2, "width")
	lua.pushinteger(L, lua.Integer(grid.h))
	lua.setfield(L, -2, "height")
	lua.createtable(L, c.int(len(grid.v)), 0)
	for v, i in grid.v {
		lua.pushnumber(L, lua.Number(v))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	lua.setfield(L, -2, "values")
	return 1
}

// LevelGen.entities(generator [, seed]) -> {{component, x, y}, ...} (cells) | nil, why
@(private = "file")
lua_levelgen_entities :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || lua.type(L, 1) != .STRING {
		lua.pushnil(L)
		lua.pushstring(L, "usage: LevelGen.entities(\"levels/caves.levelgen.json\" [, seed])")
		return 2
	}
	seed := u64(lua.tointeger(L, 2)) if lua.type(L, 2) == .NUMBER else 0
	g, err := Gen_LoadFile(&sm.game.gameContext, string(lua.tostring(L, 1)), context.temp_allocator)
	defer Gen_GraphDestroy(&g)
	ents: [dynamic]Gen_Entity
	if err == "" do ents, err = Gen_Entities(&g, seed, context.temp_allocator)
	if err != "" {
		lua.pushnil(L)
		lua.pushstring(L, strings.clone_to_cstring(err, context.temp_allocator))
		return 2
	}
	lua.createtable(L, c.int(len(ents)), 0)
	for en, i in ents {
		lua.createtable(L, 0, 3)
		lua.pushstring(L, strings.clone_to_cstring(en.component, context.temp_allocator))
		lua.setfield(L, -2, "component")
		lua.pushinteger(L, lua.Integer(en.cell.x))
		lua.setfield(L, -2, "x")
		lua.pushinteger(L, lua.Integer(en.cell.y))
		lua.setfield(L, -2, "y")
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

// Script_RegisterLevelGenModule creates the global LevelGen table.
Script_RegisterLevelGenModule :: proc(L: ^lua.State) {
	lua.newtable(L)
	lua.pushcfunction(L, lua_levelgen_generate)
	lua.setfield(L, -2, "generate")
	lua.pushcfunction(L, lua_levelgen_values)
	lua.setfield(L, -2, "values")
	lua.pushcfunction(L, lua_levelgen_entities)
	lua.setfield(L, -2, "entities")
	lua.setglobal(L, "LevelGen")
}
