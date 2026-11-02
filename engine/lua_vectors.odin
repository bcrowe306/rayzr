package engine

import "core:c"
import lua "lua54"

// ============================================================================
// Vec2 / Vec3 / Vec4 for Lua: small value types with operators, defined in
// Lua at startup (LUA_VECTORS). The API returns Vec2 for vector properties
// (get_property, node.position, exported vector2 properties) and setters
// taking x, y also take a vector (arg_xy). A vector still answers v[1] /
// v[2], so code written for {x, y} arrays keeps working.
// ============================================================================

LUA_VECTORS :: `
local function make(name, keys)
    local V = {}
    V.__name = name
    local n = #keys
    local idx = {}
    for i, k in ipairs(keys) do idx[i] = k end
    V.__index = function(t, k)
        if type(k) == "number" then return rawget(t, idx[k]) end
        return V[k]
    end
    local function new(...)
        local a = {...}
        local v = {}
        for i = 1, n do v[keys[i]] = a[i] or 0 end
        return setmetatable(v, V)
    end
    local function op(f)
        return function(a, b)
            local v = {}
            for i = 1, n do
                local k = keys[i]
                local x = type(a) == "number" and a or a[k]
                local y = type(b) == "number" and b or b[k]
                v[k] = f(x, y)
            end
            return setmetatable(v, V)
        end
    end
    V.__add = op(function(x, y) return x + y end)
    V.__sub = op(function(x, y) return x - y end)
    V.__mul = op(function(x, y) return x * y end)
    V.__div = op(function(x, y) return x / y end)
    V.__unm = function(a) local v = {} for i = 1, n do v[keys[i]] = -a[keys[i]] end return setmetatable(v, V) end
    V.__eq = function(a, b) for i = 1, n do if a[keys[i]] ~= b[keys[i]] then return false end end return true end
    V.__len = function() return n end
    V.__tostring = function(a)
        local parts = {}
        for i = 1, n do parts[i] = string.format("%g", a[keys[i]]) end
        return name .. "(" .. table.concat(parts, ", ") .. ")"
    end
    function V.dot(a, b) local s = 0 for i = 1, n do s = s + a[keys[i]] * b[keys[i]] end return s end
    function V.length_squared(a) return V.dot(a, a) end
    function V.length(a) return math.sqrt(V.dot(a, a)) end
    function V.normalized(a) local l = V.length(a) if l == 0 then return new() end return a / l end
    function V.distance(a, b) return V.length(a - b) end
    function V.lerp(a, b, t) return a + (b - a) * t end
    function V.unpack(a) local r = {} for i = 1, n do r[i] = a[keys[i]] end return table.unpack(r) end
    function V.copy(a) return new(V.unpack(a)) end
    return setmetatable({ new = new, _mt = V }, { __call = function(_, ...) return new(...) end }), V
end
local V2
Vec2, V2 = make("Vec2", {"x", "y"})
Vec3 = make("Vec3", {"x", "y", "z"})
Vec4 = make("Vec4", {"x", "y", "z", "w"})
function V2.angle(a) return math.deg(math.atan(a.y, a.x)) end
function V2.rotated(a, deg)
    local r = math.rad(deg)
    local c, s = math.cos(r), math.sin(r)
    return Vec2(a.x * c - a.y * s, a.x * s + a.y * c)
end
Vec2.ZERO, Vec2.ONE = Vec2(0, 0), Vec2(1, 1)
Vec2.UP, Vec2.DOWN, Vec2.LEFT, Vec2.RIGHT = Vec2(0, -1), Vec2(0, 1), Vec2(-1, 0), Vec2(1, 0)
`

// Lua_RegisterVectors runs LUA_VECTORS and keeps Vec2's metatable in the
// registry ("Engine.Vec2") for Lua_PushVec2.
Lua_RegisterVectors :: proc(L: ^lua.State) {
	_ = lua.L_dostring(L, LUA_VECTORS)
	lua.getglobal(L, "Vec2")
	if lua.type(L, -1) == .TABLE {
		lua.getfield(L, -1, "_mt")
		lua.setfield(L, lua.REGISTRYINDEX, "Engine.Vec2")
	}
	lua.pop(L, 1)
}

// Lua_PushVec2 pushes a Vec2 (a plain {x, y} table if Vec2 isn't loaded).
Lua_PushVec2 :: proc(L: ^lua.State, v: [2]f32) {
	lua.createtable(L, 0, 2)
	lua.pushnumber(L, lua.Number(v.x))
	lua.setfield(L, -2, "x")
	lua.pushnumber(L, lua.Number(v.y))
	lua.setfield(L, -2, "y")
	lua.getfield(L, lua.REGISTRYINDEX, "Engine.Vec2")
	if lua.type(L, -1) == .TABLE do lua.setmetatable(L, -2)
	else do lua.pop(L, 1)
}

// arg_xy: the x, y given at `idx` - two numbers, or a vector / table there
// ({x =, y =} or {x, y}).
// arg_xy_next: arg_xy and the index after it (a vector takes one slot, two
// numbers two), for calls taking two points: f(Vec2, Vec2) or f(x1, y1, x2, y2).
arg_xy_next :: proc(L: ^lua.State, idx: c.int) -> (x, y: f32, next: c.int) {
	x, y = arg_xy(L, idx)
	return x, y, idx + 1 if lua.type(L, idx) == .TABLE else idx + 2
}

arg_xy :: proc(L: ^lua.State, idx: c.int) -> (f32, f32) {
	if lua.type(L, idx) == .TABLE {
		read :: proc(L: ^lua.State, idx: c.int, key: cstring, i: lua.Integer) -> f32 {
			lua.getfield(L, idx, key)
			if lua.type(L, -1) != .NUMBER {
				lua.pop(L, 1)
				lua.rawgeti(L, idx, i)
			}
			defer lua.pop(L, 1)
			return f32(lua.tonumber(L, -1))
		}
		t := lua.absindex(L, idx)
		return read(L, t, "x", 1), read(L, t, "y", 2)
	}
	return f32(lua.tonumber(L, idx)), f32(lua.tonumber(L, idx + 1))
}
