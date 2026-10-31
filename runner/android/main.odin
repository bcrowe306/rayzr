package main

// ============================================================================
// The Android runner (built by scripts/build_android_runner.sh into
// runners/android/libmain.so): Odin compiled for linux_arm64 / android and
// linked with raylib's NativeActivity glue (raylib calls this main), Lua,
// Box2D and Clipper2 built with the NDK. The Android export puts it in an
// APK / AAB next to the game: assets/game.rayzr and assets/fonts/.
//
// An APK's assets aren't files: the game and the font are copied out to
// the app's own folder first (again when the APK's copy changed), and the
// save data lives there too (Android removes it with the app).
// ============================================================================

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import e "../../engine"

@(default_calling_convention = "c")
foreign {
	rayzr_android_internal_path :: proc() -> cstring --- // (android_glue.c)
	rayzr_android_read_asset :: proc(name: cstring, size: ^i64) -> [^]u8 ---
	free :: proc(p: rawptr) ---
	rayzr_android_install_hooks :: proc() ---
	__android_log_write :: proc(prio: c.int, tag: cstring, text: cstring) -> c.int ---
}

ANDROID_LOG_INFO :: 4
ANDROID_LOG_WARN :: 5
ANDROID_LOG_ERROR :: 6

// android_logger: logs go to logcat (adb logcat -s Rayzr).
@(private = "file")
android_logger :: proc(data: rawptr, level: runtime.Logger_Level, text: string, options: runtime.Logger_Options, location := #caller_location) {
	prio: c.int = ANDROID_LOG_ERROR if level >= .Error else (ANDROID_LOG_WARN if level == .Warning else ANDROID_LOG_INFO)
	__android_log_write(prio, "Rayzr", fmt.ctprintf("%s", text))
}

// extract copies an asset out of the APK to `dst` when it's missing or
// differs (false: no such asset).
@(private = "file")
extract :: proc(asset, dst: string) -> bool {
	size: i64
	data := rayzr_android_read_asset(fmt.ctprintf("%s", asset), &size)
	if data == nil do return false
	defer free(data)
	bytes := data[:size]
	if old, err := os.read_entire_file(dst, context.temp_allocator); err == nil && len(old) == len(bytes) && string(old) == string(bytes) do return true
	if err := os.write_entire_file(dst, bytes); err != nil {
		log.errorf("[android] can't write %s: %v", dst, err)
		return false
	}
	return true
}

// rayzr_android_suspend: the app left the screen (1) or came back (0) -
// called from android_glue.c on raylib's thread, between frames.
@(export)
rayzr_android_suspend :: proc "c" (on: c.int) {
	context = runtime.default_context()
	context.logger = {procedure = android_logger, lowest_level = .Info}
	e.Mixer_Suspend(on != 0)
	log.infof("[android] %s", "in the background: paused" if on != 0 else "back: resumed")
}

main :: proc() {
	context.logger = {procedure = android_logger, lowest_level = .Info}
	dir := string(rayzr_android_internal_path())
	game, _ := filepath.join({dir, "game.rayzr"}, context.allocator)
	font, _ := filepath.join({dir, "OpenSans-Regular.ttf"}, context.allocator)
	save, _ := filepath.join({dir, "save"}, context.allocator)
	if !extract("game.rayzr", game) {
		log.error("[android] no game.rayzr in the APK's assets")
		return
	}
	if extract("fonts/OpenSans-Regular.ttf", font) do e.Runner_FontPath = font
	log.infof("[android] starting %s", game)
	e.Runner_AfterWindow = proc() {rayzr_android_install_hooks()}
	e.Engine_RunProject(e.Run_Options{projectPath = game, userDataDir = save})
}
