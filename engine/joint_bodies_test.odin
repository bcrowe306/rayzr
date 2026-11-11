package engine

import "core:testing"
import lua "lua54"

// A Joint's bodies set from Lua while the game runs (joint_set_bodies): a
// Mouse joint on the player grabs one of two same-named spawned crates by
// node, carries it, lets go; bad input changes nothing; a held body that's
// destroyed leaves the joint empty.
@(test)
test_joint_set_bodies_at_runtime :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("joint_bodies", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	ctx := &game.gameContext
	player := CharacterMoverNode_Create(scene, "Player")
	player.enableKeyboardInput = false
	player.gravityScale = 0
	player.gameContext = ctx
	grab := JointNode_Create(scene, "Grab", player)
	grab.joint.type = .Mouse
	crates: [2]^DynamicBodyNode
	for &c, i in crates {
		c = DynamicBodyNode_Create(scene, "Crate") // (the same name, as spawned ones)
		c.position = {200 + f32(i) * 200, 0}
		c.gravityScale = 0
		c.gameContext = ctx
		DynamicBodyNode_AddShape(c, MakeBoxPhysicsShape(32, 32), ctx)
	}
	ProcessNodeQueues(scene.manager, ctx)
	game->run(1.0 / 60)
	testing.expect(t, !JointNode_IsActive(grab), "no Body B yet: no joint")

	L := game.scriptManager.L
	run :: proc(t: ^testing.T, L: ^lua.State, code: cstring, loc := #caller_location) {
		if lua.L_dostring(L, code) != 0 {
			testing.expectf(t, false, "Lua: %s", lua.tostring(L, -1), loc = loc)
			lua.pop(L, 1)
		}
	}
	global_bool :: proc(L: ^lua.State, name: cstring) -> bool {
		lua.getglobal(L, name)
		defer lua.pop(L, 1)
		return bool(lua.toboolean(L, -1))
	}
	push_node_userdata(L, crates[1])
	lua.setglobal(L, "crate")

	// Grab the second crate by node: held, not the first one with its name.
	run(t, L, `
		grab = Scene.find_node("Grab")
		local x, y = crate:get_global_position()
		grab:set_property("joint.mouse.target", x, y)
		grab:set_property("joint.mouse.max_force", crate:get_mass() * 1000 * 30)
		ok = grab:joint_set_bodies(nil, crate)
	`)
	testing.expect(t, global_bool(L, "ok"), "joint_set_bodies returns true")
	game->run(1.0 / 60)
	testing.expect(t, JointNode_IsActive(grab), "the joint is made")
	a, b := JointNode_Bodies(grab, scene.manager)
	testing.expect(t, a == player && b == crates[1], "Body A the parent, Body B the crate it was given")
	run(t, L, `local a, b = grab:joint_get_bodies(); same = b ~= nil and b:get_global_position() > 300 and a:get_name() == "Player"; active = grab:joint_is_active()`)
	testing.expect(t, global_bool(L, "same"), "joint_get_bodies gives the two bodies")
	testing.expect(t, global_bool(L, "active"), "joint_is_active")

	// Carried: the target moves, the crate follows; the other stays.
	run(t, L, `grab:set_property("joint.mouse.target", 400, -200)`)
	for _ in 0 ..< 90 do game->run(1.0 / 60)
	p := crates[1].globalPosition
	testing.expectf(t, abs(p.x - 400) < 8 && abs(p.y + 200) < 8, "the held crate is at the target (%v)", p)
	testing.expectf(t, abs(crates[0].globalPosition.y) < 1, "the other crate didn't move (%v)", crates[0].globalPosition)

	// Bad input: false, nothing changes.
	run(t, L, `bad = grab:joint_set_bodies(nil, 5)`)
	testing.expect(t, !global_bool(L, "bad"), "a number isn't a body")
	game->run(1.0 / 60)
	testing.expect(t, JointNode_IsActive(grab), "still held after bad input")

	// Let go (nil Body B), then grab again and destroy the held crate.
	run(t, L, `grab:joint_set_bodies(nil, nil)`)
	game->run(1.0 / 60)
	testing.expect(t, !JointNode_IsActive(grab), "let go")
	run(t, L, `grab:joint_set_bodies(nil, crate)`)
	game->run(1.0 / 60)
	testing.expect(t, JointNode_IsActive(grab), "grabbed again")
	run(t, L, `crate:destroy()`)
	game->run(1.0 / 60)
	game->run(1.0 / 60)
	testing.expect(t, !JointNode_IsActive(grab), "the destroyed crate's joint is gone")
	_, b = JointNode_Bodies(grab, scene.manager)
	testing.expect(t, b == nil, "Body B is empty once its node is destroyed")
}
