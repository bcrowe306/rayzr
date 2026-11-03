#+build !js
package engine

import "core:strings"

// ============================================================================
// Window_CanOpenGL: can this machine open an OpenGL 3.3 window? Asked before
// rl.InitWindow, because raylib 5.5 doesn't survive the answer "no" on every
// machine: when GLFW can't make the window (no GPU / no accelerated OpenGL,
// e.g. GitHub's macOS runners) but the machine has a monitor, raylib's
// InitPlatform asks GetCurrentMonitor, which calls glfwGetWindowPos on the
// missing window - a GLFW assert that aborts the process before
// rl.IsWindowReady can say anything. Here: a hidden 1 x 1 window with the
// context raylib asks for (the same hints), made and destroyed through
// raylib's own GLFW (compiled into raylib's library - no second GLFW is
// linked), then GLFW shut down again so raylib starts it fresh.
// ok = false: reason is GLFW's own error text (temp-allocated).
// (Android and the web don't use GLFW: always ok.)
// ============================================================================

when ODIN_PLATFORM_SUBTARGET != .Android {
	@(private = "file")
	GLFW_FOCUSED :: 0x00020001
	@(private = "file")
	GLFW_VISIBLE :: 0x00020004
	@(private = "file")
	GLFW_SAMPLES :: 0x0002100D
	@(private = "file")
	GLFW_CONTEXT_VERSION_MAJOR :: 0x00022002
	@(private = "file")
	GLFW_CONTEXT_VERSION_MINOR :: 0x00022003
	@(private = "file")
	GLFW_OPENGL_FORWARD_COMPAT :: 0x00022006
	@(private = "file")
	GLFW_OPENGL_PROFILE :: 0x00022008
	@(private = "file")
	GLFW_OPENGL_CORE_PROFILE :: 0x00032001
	@(private = "file")
	GLFW_COCOA_CHDIR_RESOURCES :: 0x00051001

	@(private = "file", default_calling_convention = "c")
	foreign {
		glfwInitHint :: proc(hint, value: i32) ---
		glfwInit :: proc() -> i32 ---
		glfwTerminate :: proc() ---
		glfwGetError :: proc(description: ^cstring) -> i32 ---
		glfwDefaultWindowHints :: proc() ---
		glfwWindowHint :: proc(hint, value: i32) ---
		glfwCreateWindow :: proc(width, height: i32, title: cstring, monitor, share: rawptr) -> rawptr ---
		glfwDestroyWindow :: proc(window: rawptr) ---
	}
}

Window_CanOpenGL :: proc(msaa := false) -> (ok: bool, reason: string) {
	when ODIN_PLATFORM_SUBTARGET == .Android {
		return true, ""
	} else {
		glfw_error :: proc(what: string) -> string {
			desc: cstring
			code := glfwGetError(&desc)
			if code == 0 || desc == nil do return what
			return strings.concatenate({what, ": ", string(desc)}, context.temp_allocator)
		}
		// (As raylib's InitPlatform: the working folder stays where it is.)
		when ODIN_OS == .Darwin do glfwInitHint(GLFW_COCOA_CHDIR_RESOURCES, 0)
		if glfwInit() == 0 do return false, glfw_error("no window system")
		defer glfwTerminate()
		glfwDefaultWindowHints()
		glfwWindowHint(GLFW_VISIBLE, 0)
		glfwWindowHint(GLFW_FOCUSED, 0)
		if msaa do glfwWindowHint(GLFW_SAMPLES, 4)
		glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3)
		glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3)
		glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE)
		glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, 1 if ODIN_OS == .Darwin else 0)
		win := glfwCreateWindow(1, 1, "", nil, nil)
		if win == nil do return false, glfw_error("no OpenGL 3.3 window")
		glfwDestroyWindow(win)
		return true, ""
	}
}
