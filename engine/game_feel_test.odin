package engine

import "core:strings"
import "core:testing"
import lua "lua54"

@(private = "file")
feel_seen: map[string]f32 // dt each test node got (by name)

// #287: game feel - the game's time scale, a tag's scale (children
// inherit), hit-stop (whole game / tags; UI keeps real time), slow motion,
// flash / blink / squash, Camera.kick, the Lua API.
@(test)
test_game_feel :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("feel", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	ctx := &game.gameContext
	feel_seen = make(map[string]f32, allocator = context.temp_allocator)
	track :: proc(n: ^Node, c: ^GameContext, dt: f32) {feel_seen[n.name] = dt}
	mk :: proc(scene: ^Scene, name: string, parent: ^Node = nil, tag := "") -> ^Node {
		n := CreateNode(scene.manager, Node)
		n.name = strings.clone(name, n.allocator)
		n.update = track
		if tag != "" do Node_AddTag(n, tag)
		scene->addNode(n, parent)
		return n
	}
	plain := mk(scene, "Plain")
	enemy := mk(scene, "Enemy", tag = "enemy")
	_ = mk(scene, "EnemyKid", enemy)
	ui := UIButtonNode_Create(scene, "Btn", "OK", {100, 40})
	ui.update = track
	ProcessNodeQueues(scene.manager, ctx)
	step :: proc(game: ^Game, n := 1) {for _ in 0 ..< n do game->run(1.0 / 60)}
	near :: proc(a, b: f32) -> bool {return abs(a - b) < 1e-4}
	step(game)
	testing.expect(t, near(feel_seen["Plain"], 1.0 / 60) && near(feel_seen["Enemy"], 1.0 / 60), "normal")

	// The whole game at half speed; enemies at a further half (children too).
	GameFeel_SetTimeScale(game, 0.5)
	GameFeel_SetTimeScale(game, 0.5, "enemy")
	step(game)
	testing.expect(t, near(feel_seen["Plain"], 0.5 / 60), "half")
	testing.expect(t, near(feel_seen["Enemy"], 0.25 / 60) && near(feel_seen["EnemyKid"], 0.25 / 60), "a quarter, inherited")
	testing.expect(t, near(feel_seen["Btn"], 1.0 / 60), "UI keeps real time")
	GameFeel_SetTimeScale(game, 1)
	GameFeel_SetTimeScale(game, 1, "enemy")
	testing.expect_value(t, len(game.feel.tagScales), 0)

	// Hit-stop: the whole game (UI goes on), 0.1 s of real time.
	GameFeel_HitStop(game, 0.1)
	step(game)
	testing.expect(t, feel_seen["Plain"] == 0 && near(feel_seen["Btn"], 1.0 / 60), "frozen, UI not")
	step(game, 6)
	testing.expect(t, near(feel_seen["Plain"], 1.0 / 60), "over after 0.1 s")
	// ...only enemies.
	GameFeel_HitStop(game, 0.05, {"enemy"})
	step(game)
	testing.expect(t, feel_seen["Enemy"] == 0 && feel_seen["EnemyKid"] == 0 && near(feel_seen["Plain"], 1.0 / 60), "tagged hit-stop")
	step(game, 4)
	testing.expect(t, near(feel_seen["Enemy"], 1.0 / 60) && len(game.feel.hitStopTags) == 0, "over")

	// Slow motion: down to 0.25, back up.
	GameFeel_SlowMotion(game, 0.25, 1.0, .Linear)
	step(game, 30)
	testing.expect(t, near(feel_seen["Plain"], 0.25 / 60), "slow in the middle")
	step(game, 40)
	testing.expect(t, near(feel_seen["Plain"], 1.0 / 60) && !game.feel.slowmo.on, "back to normal")

	// Flash, blink, squash: on the node, then gone.
	Node_Flash(plain, {255, 0, 0, 255}, 0.1)
	Node_Blink(enemy, 0.2, 10)
	Node_Squash(plain, 0.3, 0.2)
	testing.expect(t, plain in nodeFx && enemy in nodeFx, "effects on")
	step(game, 3)
	sq := Fx_ScaleOf(plain)
	testing.expect(t, sq.y != 1 && sq.x != 1, "squashed")
	hidden := false
	for _ in 0 ..< 12 {
		step(game)
		if nodeFx[enemy].blinkHidden do hidden = true
	}
	testing.expect(t, hidden, "blinked")
	step(game, 10)
	testing.expect(t, len(nodeFx) == 0 && Fx_ScaleOf(plain) == {1, 1}, "all over")

	// Camera.kick: a nudge that springs back.
	Camera_Kick({10, 0})
	step(game, 3)
	testing.expect(t, Camera_KickOffset().x > 1, "kicked")
	step(game, 90)
	testing.expect(t, abs(Camera_KickOffset().x) < 0.1, "back")

	// Lua.
	L := game.scriptManager.L
	code: cstring = `Engine.set_time_scale(0.5, "enemy"); a = Engine.get_time_scale("enemy"); b = Engine.get_time_scale()
		Engine.hit_stop(0.05, {"enemy"}); Scene.find_node("Plain"):flash("#ffffff", 0.2); Scene.find_node("Plain"):squash()
		Scene.find_node("Enemy"):blink(0.5); Engine.slow_motion(0.5, 0.5, "out_quad"); Camera.kick(0, 5)`
	if lua.L_dostring(L, code) != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	lua.getglobal(L, "a"); testing.expect_value(t, f32(lua.tonumber(L, -1)), 0.5); lua.pop(L, 1)
	lua.getglobal(L, "b"); testing.expect_value(t, f32(lua.tonumber(L, -1)), 1); lua.pop(L, 1)
	testing.expect(t, game.feel.hitStopTagT > 0 && game.feel.slowmo.on && plain in nodeFx && enemy in nodeFx, "all set from Lua")
	free_all(context.temp_allocator)
}
