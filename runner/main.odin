// Standalone game runner: plays a data-only project (scenes, Lua scripts,
// assets) with no game-specific code. "Export Standalone Game" in the
// editor builds this next to the game's .rayzr:
//
//   MyGame/
//     MyGame          (this program)
//     game.rayzr        (the packaged project)
//     fonts/OpenSans-Regular.ttf
//
// Usage: runner [project-dir | game.rayzr] [--scene <file>]
//        [--frames N]         (quit after N frames; a capture below is of frame N, else of frame 30)
//        [--screenshot out.png] [--dump-scene out.json] [--hidden]
//        [--user-data <dir>]  (Save data folder instead of the platform's)
//        [--bench N]          (N uncapped frames, then frame timings; scripts/make_bench_project.py)
//        [--uncapped]         (no vsync, no frame cap, frame time / FPS top left)
//        [--no-render-cache]  (no tile chunk cache / draw reordering, for comparisons)
//        [--input-script f]   (keys pressed on given frames - "30 RIGHT down", "40 SPACE tap 8"; fixed 1/60 s frames)
//        [--trace <node>]     (prints "@trace <frame> <scene> <x> <y>" every frame: game tests, bots)
//        [--crash-test kind]  (panic | segv | abort once loaded: crash report tests)
// With no project argument it looks for game.rayzr (or any .rayzr, or a
// project/ directory) next to the executable.
package main

import "core:fmt"
import "core:log"
import os "../engine/osx"
import e "../engine"

main :: proc() {
	context.logger = log.create_console_logger(.Info)
	opts := e.Engine_ParseRunArgs(os.args[1:])
	if opts.projectPath == "" do opts.projectPath = e.Engine_FindBundledProject(os.args[0])
	if opts.projectPath == "" {
		fmt.eprintln("No game found: put game.rayzr next to the runner, or pass a project directory / .rayzr file.")
		os.exit(2)
	}
	os.exit(e.Engine_RunProject(opts))
}
