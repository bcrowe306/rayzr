package engine

import "core:strings"
import "core:testing"

// #403: the project's Lua Checks preset ("scripting": {"lua_checks"}) is
// read and written; the default (relaxed) isn't written, an unknown name
// reads as the default.
@(test)
test_project_lua_checks_round_trip :: proc(t: ^testing.T) {
	cfg, ok := Project_ParseConfig(transmute([]u8)string(`{"name": "x", "scripting": {"lua_checks": "strict"}}`))
	defer ProjectConfig_Destroy(&cfg)
	testing.expect(t, ok)
	testing.expect_value(t, cfg.luaChecks, Lua_Checks.Strict)
	text := Project_SerializeToJSON(&cfg, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"scripting": {"lua_checks": "strict"}`), text)
	again, ok2 := Project_ParseConfig(transmute([]u8)text)
	defer ProjectConfig_Destroy(&again)
	testing.expect(t, ok2)
	testing.expect_value(t, again.luaChecks, Lua_Checks.Strict)

	cfg.luaChecks = .Relaxed
	testing.expect(t, !strings.contains(Project_SerializeToJSON(&cfg, context.temp_allocator), `"scripting"`), "the default isn't written")
	odd, _ := Project_ParseConfig(transmute([]u8)string(`{"name": "x", "scripting": {"lua_checks": "pedantic"}}`))
	defer ProjectConfig_Destroy(&odd)
	testing.expect_value(t, odd.luaChecks, Lua_Checks.Relaxed)
	free_all(context.temp_allocator)
}
