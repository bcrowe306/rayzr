#+build darwin, linux, windows
package engine

import "core:c"

// ============================================================================
// Raw joysticks on the desktop (gamepad_mappings.odin): raylib's GLFW, read
// directly - raylib links GLFW statically and exports its functions, so
// these resolve against the raylib library already on the link line (the
// import below only gives the foreign block a library to hang on).
// Android's raylib has no GLFW: no raw joysticks there.
// ============================================================================

JOY_MAX :: 16 // GLFW_JOYSTICK_1 .. GLFW_JOYSTICK_LAST

when ODIN_PLATFORM_SUBTARGET == .Android {
	JOY_RAW :: false
	GAMEPAD_PLATFORM :: "Android"

	joy_present :: proc(jid: i32) -> bool {return false}
	joy_is_gamepad :: proc(jid: i32) -> bool {return false}
	joy_name :: proc(jid: i32) -> string {return ""}
	joy_guid :: proc(jid: i32) -> string {return ""}
	joy_axes :: proc(jid: i32) -> []f32 {return nil}
	joy_buttons :: proc(jid: i32) -> []u8 {return nil}
	joy_hats :: proc(jid: i32) -> []u8 {return nil}
} else {
	JOY_RAW :: true
	GAMEPAD_PLATFORM :: "Windows" when ODIN_OS == .Windows else ("Mac OS X" when ODIN_OS == .Darwin else "Linux")

	when ODIN_OS == .Windows {
		foreign import glfw_in_raylib "system:kernel32.lib"
	} else {
		foreign import glfw_in_raylib "system:c"
	}

	@(default_calling_convention = "c")
	foreign glfw_in_raylib {
		glfwJoystickPresent :: proc(jid: c.int) -> c.int ---
		glfwJoystickIsGamepad :: proc(jid: c.int) -> c.int ---
		glfwGetJoystickName :: proc(jid: c.int) -> cstring ---
		glfwGetJoystickGUID :: proc(jid: c.int) -> cstring ---
		glfwGetJoystickAxes :: proc(jid: c.int, count: ^c.int) -> [^]f32 ---
		glfwGetJoystickButtons :: proc(jid: c.int, count: ^c.int) -> [^]u8 ---
		glfwGetJoystickHats :: proc(jid: c.int, count: ^c.int) -> [^]u8 ---
	}

	joy_present :: proc(jid: i32) -> bool {return jid >= 0 && jid < JOY_MAX && glfwJoystickPresent(c.int(jid)) != 0}
	joy_is_gamepad :: proc(jid: i32) -> bool {return joy_present(jid) && glfwJoystickIsGamepad(c.int(jid)) != 0}
	// (Borrowed: valid until the pad disconnects.)
	joy_name :: proc(jid: i32) -> string {return string(glfwGetJoystickName(c.int(jid))) if joy_present(jid) else ""}
	joy_guid :: proc(jid: i32) -> string {return string(glfwGetJoystickGUID(c.int(jid))) if joy_present(jid) else ""}
	// (Borrowed: valid until the next poll.)
	joy_axes :: proc(jid: i32) -> []f32 {
		if !joy_present(jid) do return nil
		n: c.int
		p := glfwGetJoystickAxes(c.int(jid), &n)
		return p[:n] if p != nil else nil
	}
	joy_buttons :: proc(jid: i32) -> []u8 {
		if !joy_present(jid) do return nil
		n: c.int
		p := glfwGetJoystickButtons(c.int(jid), &n)
		return p[:n] if p != nil else nil
	}
	joy_hats :: proc(jid: i32) -> []u8 {
		if !joy_present(jid) do return nil
		n: c.int
		p := glfwGetJoystickHats(c.int(jid), &n)
		return p[:n] if p != nil else nil
	}
}
