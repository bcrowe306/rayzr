package engine

import "core:encoding/json"
import "core:fmt"
import "core:strings"

// ============================================================================
// Tile collision (tilemap_colliders.odin builds it): how each tile of a
// tileset collides, kept with its terrains and data in <image>.tileset.json:
//
//   "collision": [[tile, {"shape": "slope_up_right", "friction": 0.1,
//                         "bounce": 0, "trigger": false,
//                         "points": [[x, y], ...]}], ...]
//
// A tile without an entry is Full (the whole cell solid, the map's
// friction). Shapes are in the cell's unit square (0..1, y down):
//   full, none, half_top / half_bottom / half_left / half_right,
//   slope_up_right / slope_up_left (45 degree floors), ceiling_right /
//   ceiling_left (45 degree ceilings), slope_up_right_low / _high and
//   slope_up_left_low / _high (22.5 degree floors in two tiles),
//   one_way (a platform: solid from above only), custom (`points`: a
//   convex polygon, up to 8 corners).
// Friction / bounce: -1 = the map's. Trigger: the shape detects instead of
// blocking (water, spikes, ladders): "tile_entered" / "tile_exited".
// Partial shapes are for square grids; other grids treat them as full.
// ============================================================================

Tile_Shape :: enum u8 {
	Full,
	None,
	Half_Top,
	Half_Bottom,
	Half_Left,
	Half_Right,
	Slope_Up_Right,
	Slope_Up_Left,
	Ceiling_Right,
	Ceiling_Left,
	Slope_Up_Right_Low,
	Slope_Up_Right_High,
	Slope_Up_Left_Low,
	Slope_Up_Left_High,
	One_Way,
	Custom,
}

TILE_SHAPE_NAMES := [Tile_Shape]string {
	.Full                = "full",
	.None                = "none",
	.Half_Top            = "half_top",
	.Half_Bottom         = "half_bottom",
	.Half_Left           = "half_left",
	.Half_Right          = "half_right",
	.Slope_Up_Right      = "slope_up_right",
	.Slope_Up_Left       = "slope_up_left",
	.Ceiling_Right       = "ceiling_right",
	.Ceiling_Left        = "ceiling_left",
	.Slope_Up_Right_Low  = "slope_up_right_low",
	.Slope_Up_Right_High = "slope_up_right_high",
	.Slope_Up_Left_Low   = "slope_up_left_low",
	.Slope_Up_Left_High  = "slope_up_left_high",
	.One_Way             = "one_way",
	.Custom              = "custom",
}

TILE_SHAPE_LABELS := [Tile_Shape]string {
	.Full                = "Full",
	.None                = "None",
	.Half_Top            = "Half (top)",
	.Half_Bottom         = "Half (bottom)",
	.Half_Left           = "Half (left)",
	.Half_Right          = "Half (right)",
	.Slope_Up_Right      = "Slope up right (45°)",
	.Slope_Up_Left       = "Slope up left (45°)",
	.Ceiling_Right       = "Ceiling right (45°)",
	.Ceiling_Left        = "Ceiling left (45°)",
	.Slope_Up_Right_Low  = "Slope up right, low (22.5°)",
	.Slope_Up_Right_High = "Slope up right, high (22.5°)",
	.Slope_Up_Left_Low   = "Slope up left, low (22.5°)",
	.Slope_Up_Left_High  = "Slope up left, high (22.5°)",
	.One_Way             = "One-way platform",
	.Custom              = "Custom polygon",
}

TILE_CUSTOM_MAX :: 8

Tile_Collision :: struct {
	shape:    Tile_Shape,
	friction: f32, // -1: the map's
	bounce:   f32, // -1: the map's
	trigger:  bool,
	points:   [TILE_CUSTOM_MAX][2]f32, // custom: the polygon (unit square)
	count:    int,
}

TILE_COLLISION_DEFAULT :: Tile_Collision{shape = .Full, friction = -1, bounce = -1}

// TileCollision_Get: a tile's collision (Full when it has none set).
TileCollision_Get :: proc(ts: ^Tile_Terrains, tile: i32) -> Tile_Collision {
	if ts == nil do return TILE_COLLISION_DEFAULT
	if c, ok := ts.collision[tile]; ok do return c
	return TILE_COLLISION_DEFAULT
}

// TileCollision_Set: a tile's collision (the default removes its entry).
TileCollision_Set :: proc(ts: ^Tile_Terrains, tile: i32, c: Tile_Collision) {
	if ts.collision == nil do ts.collision = make(map[i32]Tile_Collision, allocator = ts.allocator)
	if c == TILE_COLLISION_DEFAULT {
		delete_key(&ts.collision, tile)
		return
	}
	ts.collision[tile] = c
}

// TileCollision_Polygon: a tile's solid shape in the unit square (0..1, y
// down); empty for None. Full and One-Way are the whole square.
TileCollision_Polygon :: proc(c: Tile_Collision, allocator := context.temp_allocator) -> [][2]f32 {
	pts: [][2]f32
	switch c.shape {
	case .None:                return nil
	case .Full, .One_Way:      pts = {{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	case .Half_Top:            pts = {{0, 0}, {1, 0}, {1, 0.5}, {0, 0.5}}
	case .Half_Bottom:         pts = {{0, 0.5}, {1, 0.5}, {1, 1}, {0, 1}}
	case .Half_Left:           pts = {{0, 0}, {0.5, 0}, {0.5, 1}, {0, 1}}
	case .Half_Right:          pts = {{0.5, 0}, {1, 0}, {1, 1}, {0.5, 1}}
	case .Slope_Up_Right:      pts = {{1, 0}, {1, 1}, {0, 1}}
	case .Slope_Up_Left:       pts = {{0, 0}, {1, 1}, {0, 1}}
	case .Ceiling_Right:       pts = {{0, 0}, {1, 0}, {1, 1}}
	case .Ceiling_Left:        pts = {{0, 0}, {1, 0}, {0, 1}}
	case .Slope_Up_Right_Low:  pts = {{1, 0.5}, {1, 1}, {0, 1}}
	case .Slope_Up_Right_High: pts = {{0, 0.5}, {1, 0}, {1, 1}, {0, 1}}
	case .Slope_Up_Left_Low:   pts = {{0, 0.5}, {1, 1}, {0, 1}}
	case .Slope_Up_Left_High:  pts = {{0, 0}, {1, 0.5}, {1, 1}, {0, 1}}
	case .Custom:
		n := clamp(c.count, 0, TILE_CUSTOM_MAX)
		if n < 3 do return nil
		out := make([][2]f32, n, allocator)
		src := c.points
		copy(out, src[:n])
		return out
	}
	out := make([][2]f32, len(pts), allocator)
	copy(out, pts)
	return out
}

// TileCollision_Parse reads "collision" (Terrains_Parse).
TileCollision_Parse :: proc(ts: ^Tile_Terrains, root: json.Object) {
	if ts.collision == nil do ts.collision = make(map[i32]Tile_Collision, allocator = ts.allocator)
	list, ok := root["collision"].(json.Array)
	if !ok do return
	for v in list {
		pair, isArr := v.(json.Array)
		if !isArr || len(pair) < 2 do continue
		tile, _ := json_number(pair[0])
		obj, isObj := pair[1].(json.Object)
		if !isObj do continue
		c := TILE_COLLISION_DEFAULT
		if s, sok := obj["shape"].(json.String); sok do for name, k in TILE_SHAPE_NAMES do if string(s) == name do c.shape = k
		if f, fok := json_number(obj["friction"]); fok && "friction" in obj do c.friction = f
		if b, bok := json_number(obj["bounce"]); bok && "bounce" in obj do c.bounce = b
		if t, tok := obj["trigger"].(json.Boolean); tok do c.trigger = bool(t)
		if pts, pok := obj["points"].(json.Array); pok do for pv in pts {
			p, isP := pv.(json.Array)
			if !isP || len(p) < 2 || c.count >= TILE_CUSTOM_MAX do continue
			x, _ := json_number(p[0])
			y, _ := json_number(p[1])
			c.points[c.count] = {clamp(x, 0, 1), clamp(y, 0, 1)}
			c.count += 1
		}
		TileCollision_Set(ts, i32(tile), c)
	}
}

// TileCollision_Serialize writes "collision" (nothing when every tile is Full).
TileCollision_Serialize :: proc(ts: ^Tile_Terrains, w: ^Json_Writer) {
	if len(ts.collision) == 0 do return
	tiles := make([dynamic]i32, context.temp_allocator)
	for t in ts.collision do append(&tiles, t)
	for i in 1 ..< len(tiles) do for j := i; j > 0 && tiles[j] < tiles[j - 1]; j -= 1 do tiles[j], tiles[j - 1] = tiles[j - 1], tiles[j]
	strings.write_string(&w.sb, ",\n\"collision\": [")
	for t, i in tiles {
		c := ts.collision[t]
		fmt.sbprintf(&w.sb, "%s\n  [%d, {{\"shape\": \"%s\"", "," if i > 0 else "", t, TILE_SHAPE_NAMES[c.shape])
		if c.friction >= 0 {strings.write_string(&w.sb, ", \"friction\": "); Json_Float(w, c.friction)}
		if c.bounce >= 0 {strings.write_string(&w.sb, ", \"bounce\": "); Json_Float(w, c.bounce)}
		if c.trigger do strings.write_string(&w.sb, ", \"trigger\": true")
		if c.shape == .Custom && c.count > 0 {
			strings.write_string(&w.sb, ", \"points\": [")
			for p, k in c.points[:c.count] {
				strings.write_string(&w.sb, ", " if k > 0 else "")
				strings.write_byte(&w.sb, '[')
				Json_Float(w, p.x)
				strings.write_string(&w.sb, ", ")
				Json_Float(w, p.y)
				strings.write_byte(&w.sb, ']')
			}
			strings.write_byte(&w.sb, ']')
		}
		strings.write_string(&w.sb, "}]")
	}
	strings.write_string(&w.sb, "\n]")
}

// TileCollision_CopyAll: every tile's collision from another set (the
// editor's Collision page to the scene's maps on the tileset).
TileCollision_CopyAll :: proc(dst, src: ^Tile_Terrains) {
	if dst == nil || src == nil || dst == src do return
	if dst.collision == nil do dst.collision = make(map[i32]Tile_Collision, allocator = dst.allocator)
	clear(&dst.collision)
	for t, c in src.collision do dst.collision[t] = c
}
