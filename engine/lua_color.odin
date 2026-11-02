package engine

import "core:c"
import lua "lua54"
import rl "vendor:raylib"

// Lua_ArgColor reads a colour argument the one way the whole API takes them
// (#327): "#rrggbb[aa]", a table {r, g, b[, a]} (or {r = , g = , b = , a = })
// with channels 0..1, or the numbers r, g, b[, a] 0..1. A colour whose
// channels go above 1 is read as 0..255 (the form Subtitles once took).
// `next` is the argument after it; ok = false when there is no colour.
Lua_ArgColor :: proc(L: ^lua.State, idx: c.int) -> (col: rl.Color, next: c.int, ok: bool) {
	ch: [4]f32 = {0, 0, 0, 1}
	next = idx + 1
	#partial switch lua.type(L, idx) {
	case .STRING:
		col, ok = Color_FromHex(string(lua.tostring(L, idx)))
		return
	case .TABLE:
		t := lua.absindex(L, idx)
		keys := [4]cstring{"r", "g", "b", "a"}
		for k in 0 ..< 4 {
			lua.rawgeti(L, t, lua.Integer(k + 1))
			if lua.type(L, -1) != .NUMBER {
				lua.pop(L, 1)
				lua.getfield(L, t, keys[k])
			}
			if lua.type(L, -1) == .NUMBER do ch[k] = f32(lua.tonumber(L, -1))
			lua.pop(L, 1)
		}
	case .NUMBER:
		n := 3
		for k in 0 ..< 4 {
			if lua.type(L, idx + c.int(k)) != .NUMBER {
				if k < 3 do return {}, idx + c.int(k), false
				break
			}
			ch[k] = f32(lua.tonumber(L, idx + c.int(k)))
			n = k + 1
		}
		next = idx + c.int(n)
	case:
		return {}, idx, false
	}
	scale: f32 = 255
	if ch[0] > 1 || ch[1] > 1 || ch[2] > 1 || ch[3] > 1 {
		scale = 1
		if ch[3] == 1 do ch[3] = 255 // (an alpha left out)
	}
	to :: proc(v, scale: f32) -> u8 {return u8(clamp(v * scale, 0, 255) + 0.5)}
	return {to(ch[0], scale), to(ch[1], scale), to(ch[2], scale), to(ch[3], scale)}, next, true
}
