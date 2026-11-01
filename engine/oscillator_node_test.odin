package engine

import "core:math"
import "core:strings"
import "core:testing"

// The Oscillator node: waves, Relative / Absolute mappings, components and
// whole vectors, phase and value offsets, pause keeping the phase, Stop
// restoring, Loops and the signals, saving.
@(test)
test_oscillator_node :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("osc", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	ctx := &game.gameContext
	plat := TextNode_Create(scene, "Platform")
	plat.position = {100, 50}
	plat.color = {255, 255, 255, 200}
	o := cast(^OscillatorNode)Node_CreateByTypeName(scene, "OscillatorNode")
	ProcessNodeQueues(scene.manager, ctx)
	testing.expect(t, o.wave == .Sine && o.rate == 1 && o.autostart && o.loops == 0 && o.state == .Stopped, "defaults")

	o.wave = .Saw
	o.autostart = false
	OscillatorNode_AddMapping(o, "../Platform", "position.x", {-100, 0, 0, 0}, {20, 0, 0, 0})
	OscillatorNode_AddMapping(o, "../Platform", "scale", {1, 1, 0, 0}, {3, 2, 0, 0}, .Absolute)
	a := OscillatorNode_AddMapping(o, "../Platform", "color.a", {0, 0, 0, 0}, {200, 0, 0, 0}, .Absolute)
	o.mappings[a].phase = 180
	o.mappings[a].offset = {10, 0, 0, 0}
	Scene_CallReady(scene, scene.rootNode, ctx)
	testing.expect(t, o.state == .Stopped, "no autostart")

	cycles := 0
	finished := 0
	Subscribe(&o.onCycle, proc(src: rawptr, v: EventValue, g: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &cycles)
	Subscribe(&o.onFinished, proc(src: rawptr, v: EventValue, g: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &finished)

	OscillatorNode_Start(o)
	testing.expect_value(t, plat.position.x, 0) // Relative: 100 + -100
	OscillatorNode_Advance(o, 0.5, ctx)
	testing.expect_value(t, plat.position.x, 60) // 100 + -100 + 120 * 0.5
	testing.expect_value(t, plat.position.y, 50) // only x
	OscillatorNode_Pause(o)
	OscillatorNode_Advance(o, 1, ctx)
	testing.expect_value(t, plat.position.x, 60) // paused: held
	OscillatorNode_Resume(o)
	OscillatorNode_Advance(o, 0.25, ctx)
	testing.expect_value(t, plat.position.x, 90) // the phase carried on: 0.75
	testing.expect_value(t, plat.scale, [2]f32{2.5, 1.75})
	testing.expect_value(t, plat.color.a, 60) // phase 180: 0.25 * 200 + 10
	testing.expect_value(t, plat.color.r, 255)

	OscillatorNode_Advance(o, 0.5, ctx)
	testing.expect_value(t, cycles, 1)
	OscillatorNode_Stop(o)
	testing.expect(t, plat.position == {100, 50} && plat.scale == {1, 1} && plat.color.a == 200, "Stop restores")
	testing.expect(t, o.state == .Stopped && o.cycles == 0, "Stop rewinds")

	// Loops: stops after 2 cycles, keeps the last values, no drift on a restart.
	o.loops = 2
	o.rateUnit = .Seconds
	o.rate = 0.5 // 2 Hz
	cycles = 0
	OscillatorNode_Start(o)
	for _ in 0 ..< 30 do OscillatorNode_Advance(o, 0.05, ctx)
	testing.expect(t, cycles == 2 && finished == 1 && o.state == .Stopped, "finished after 2 cycles")
	testing.expect_value(t, plat.position.x, 0) // the end of the cycle (Saw at 0)
	OscillatorNode_Start(o)
	testing.expect_value(t, plat.position.x, 0) // base still 100
	OscillatorNode_Stop(o)
	testing.expect_value(t, plat.position.x, 100)

	// Waves.
	o.loops = 0
	expect_wave :: proc(t: ^testing.T, o: ^OscillatorNode, wave: Osc_Wave, at: f64, want: f32) {
		o.wave = wave
		got := OscillatorNode_Wave(o, at)
		testing.expectf(t, abs(got - want) < 0.001, "%v at %v: %v, want %v", wave, at, got, want)
	}
	expect_wave(t, o, .Sine, 0.25, 1)
	expect_wave(t, o, .Sine, 0.75, 0)
	expect_wave(t, o, .Triangle, 0.5, 1)
	expect_wave(t, o, .Triangle, 1.25, 0.5)
	o.pulseWidth = 0.2
	expect_wave(t, o, .Square, 0.1, 1)
	expect_wave(t, o, .Square, 0.3, 0)
	expect_wave(t, o, .Reverse_Saw, 0.25, 0.75)
	expect_wave(t, o, .Curve, 0.25, 0.5) // the default curve: 0 -> 1 -> 0
	o.seed = 7
	OscillatorNode_Start(o)
	o.wave = .Random
	r := OscillatorNode_Wave(o, 3.2)
	testing.expect(t, r >= 0 && r < 1 && r == OscillatorNode_Wave(o, 3.9), "Random holds a value through a cycle")
	o.wave = .Smooth_Noise
	testing.expect(t, abs(OscillatorNode_Wave(o, 3) - r) < 0.0001 && !math.is_nan(OscillatorNode_Wave(o, 3.5)), "Smooth Noise starts a cycle at its random value")
	OscillatorNode_Stop(o)

	testing.expect_value(t, Osc_PropertyWidth(plat, "position"), 2)
	testing.expect_value(t, Osc_PropertyWidth(plat, "color"), 4)
	testing.expect_value(t, Osc_PropertyWidth(plat, "position.y"), 1)
	testing.expect_value(t, Osc_PropertyWidth(plat, "text"), 0)
	testing.expect_value(t, Osc_PropertyWidth(plat, "nothing.x"), 0)

	// An editor preview's values aren't saved; it carries on afterwards.
	far := OscillatorNode_AddMapping(o, "../Platform", "position.y", {1234.5, 0, 0, 0}, {1234.5, 0, 0, 0}, .Absolute)
	o.preview = true
	OscillatorNode_Start(o)
	testing.expect_value(t, plat.position.y, 1234.5)
	held := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.count(held, "1234.5") == 2, "the saved position is the real one (only the mapping's min and max have 1234.5): %s", held)
	testing.expect_value(t, plat.position.y, 1234.5)
	OscillatorNode_Stop(o)
	o.preview = false
	OscillatorNode_RemoveMapping(o, far)
	testing.expect_value(t, plat.position.y, 50)

	// Saved and read back.
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(saved, `{"target": "../Platform", "property": "scale", "min": [1, 1], "max": [3, 2], "mode": "Absolute", "phase": 0, "offset": 0}`), "saved: %s", saved)
	o2 := cast(^OscillatorNode)Node_CreateByTypeName(scene, "OscillatorNode")
	start := strings.index(saved, `"oscillator": `) + len(`"oscillator": `)
	text := saved[start:]
	depth := 0
	for ch, i in text {
		if ch == '{' do depth += 1
		if ch == '}' {
			depth -= 1
			if depth == 0 {text = text[:i + 1]; break}
		}
	}
	Oscillator_ReadJSON_Text(o2, text)
	testing.expect_value(t, len(o2.mappings), 3)
	testing.expect(t, o2.mappings[2].property == "color.a" && o2.mappings[2].phase == 180 && o2.mappings[2].offset[0] == 10 && o2.mappings[2].mode == .Absolute, "a mapping read back")
	testing.expect(t, o2.mappings[0].mode == .Relative && o2.mappings[0].min[0] == -100, "relative read back")
	free_all(context.temp_allocator)
}
