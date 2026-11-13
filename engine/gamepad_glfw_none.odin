#+build js, freebsd, openbsd, netbsd, haiku, wasi, freestanding
package engine

// No raw joysticks here (gamepad_glfw.odin): the web reads pads through the
// browser's Gamepad API, which maps them itself.

JOY_MAX :: 16
JOY_RAW :: false
GAMEPAD_PLATFORM :: "Web" when ODIN_OS == .JS else "Other"

joy_present :: proc(jid: i32) -> bool {return false}
joy_is_gamepad :: proc(jid: i32) -> bool {return false}
joy_name :: proc(jid: i32) -> string {return ""}
joy_guid :: proc(jid: i32) -> string {return ""}
joy_axes :: proc(jid: i32) -> []f32 {return nil}
joy_buttons :: proc(jid: i32) -> []u8 {return nil}
joy_hats :: proc(jid: i32) -> []u8 {return nil}
