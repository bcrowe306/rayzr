package engine

import "core:strings"
import "core:testing"
import lua "lua54"

// #285: the developer console - commands, Lua, Console.register, pause /
// step, completion, the keyboard while open, script logs.
@(test)
test_dev_console :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	_ = game->createScene("console", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	Console_Enable(game)
	defer Console_Shutdown()
	last :: proc() -> string {return devConsole.lines[len(devConsole.lines) - 1].text}
	has :: proc(s: string) -> bool {
		for l in devConsole.lines do if strings.contains(l.text, s) do return true
		return false
	}
	testing.expect(t, devConsole.key == .GRAVE, "the backquote opens it")

	// Lua: an expression shows its value; an error is shown too.
	Console_Exec(game, "1 + 2")
	testing.expect_value(t, last(), "3")
	Console_Exec(game, "nosuch.field")
	testing.expect(t, strings.contains(last(), "nosuch"), "error shown")
	testing.expect_value(t, len(devConsole.history), 2)

	// Built-ins.
	Console_Exec(game, "help")
	testing.expect(t, has("timescale [scale]") && has("pause:"), "help lists the commands")
	Console_Exec(game, "timescale 0.5")
	testing.expect_value(t, game.feel.timeScale, 0.5)
	Console_Exec(game, "timescale 0.25 enemy")
	testing.expect_value(t, GameFeel_TimeScale(game, "enemy"), 0.25)
	Console_Exec(game, "timescale 1")
	Console_Exec(game, "timescale 1 enemy")
	Console_Exec(game, "physics")
	testing.expect(t, game.physicsWorld.drawPhysicsDebug == false, "physics toggled off (on by default)")
	Console_Exec(game, "outlines")
	Console_Exec(game, "nav")
	testing.expect(t, devConsole.draws == {.Outlines, .Navigation}, "draw toggles")
	Console_Exec(game, "perf")
	testing.expect(t, devConsole.perf, "perf on")
	Console_Exec(game, "clear")
	testing.expect_value(t, len(devConsole.lines), 0)

	// Pause, then step 2 frames: frozen, two runs, frozen again.
	Console_Exec(game, "pause")
	testing.expect(t, !Console_Frame(game, 1.0 / 60) && game.frozen, "paused")
	Console_Exec(game, "step 2")
	testing.expect(t, Console_Frame(game, 1.0 / 60) && !game.frozen, "step 1")
	testing.expect(t, Console_Frame(game, 1.0 / 60) && !game.frozen, "step 2")
	testing.expect(t, !Console_Frame(game, 1.0 / 60) && game.frozen, "frozen again")
	Console_Exec(game, "pause")
	_ = Console_Frame(game, 1.0 / 60)
	testing.expect(t, !game.frozen && !devConsole.paused, "running")

	// Open: the game gets no keys.
	devConsole.open = true
	_ = Console_Frame(game, 1.0 / 60)
	testing.expect(t, game.input.keyboardBlocked, "keys blocked while open")
	devConsole.open = false
	_ = Console_Frame(game, 1.0 / 60)
	testing.expect(t, !game.input.keyboardBlocked, "keys back")

	// Console.register from Lua, called with its words; its result printed.
	L := game.scriptManager.L
	code: cstring = `Console.register("give", "give <item> [n]: an item", function(args)
			given = args[1] .. "x" .. (args[2] or "1"); return "gave " .. given end)
		Console.print("hello", 42); Log.warn("careful")`
	if lua.L_dostring(L, code) != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	testing.expect(t, has("hello\t42") && has("careful"), "Console.print and script logs")
	Console_Exec(game, "give sword 3")
	testing.expect_value(t, last(), "gave swordx3")
	lua.getglobal(L, "given"); testing.expect_value(t, string(lua.tostring(L, -1)), "swordx3"); lua.pop(L, 1)
	if lua.L_dostring(L, `Console.register("boom", "", function() error("no") end)`) != 0 do testing.fail_now(t, "register")
	Console_Exec(game, "boom")
	testing.expect(t, strings.contains(last(), "no"), "a failing command's error shown")

	// Tab completion: one match completes, a common start extends.
	clear(&devConsole.input)
	append(&devConsole.input, ..transmute([]u8)string("gi"))
	Console_Complete()
	testing.expect_value(t, string(devConsole.input[:]), "give ")
	clear(&devConsole.input)
	append(&devConsole.input, ..transmute([]u8)string("p"))
	Console_Complete() // pause, perf, physics: "p" stays, they're listed
	testing.expect(t, strings.contains(last(), "pause") && strings.contains(last(), "physics"), "matches listed")

	// Stats for the perf overlay.
	s := Console_GetStats(game)
	testing.expect(t, s.avgMs > 16 && s.avgMs < 17, "frame times recorded")
	free_all(context.temp_allocator)
}
