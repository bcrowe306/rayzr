package editor

import "core:os"
import "core:strings"

// ============================================================================
// Running git (#293): the installed `git`, in a folder. Used by the scene
// merge set-up and the conflict window (scene_merge.odin); the Code tab's
// gutter has its own worker (code_git.odin).
// ============================================================================

// Git_Run runs `git -C dir <args>` to completion: its output (stdout,
// trimmed; temp) and whether it exited 0. missing: no git installed.
Git_Run :: proc(dir: string, args: ..string) -> (out: string, ok: bool, missing: bool) {
	cmd := make([dynamic]string, 0, len(args) + 3, context.temp_allocator)
	append(&cmd, "git", "-C", dir)
	append(&cmd, ..args)
	st, stdout, stderr, err := os.process_exec({command = cmd[:]}, context.temp_allocator)
	if err != nil do return "", false, true
	text := strings.trim_space(string(stdout))
	if st.exit_code != 0 && text == "" do text = strings.trim_space(string(stderr))
	return text, st.exit_code == 0, false
}

// Git_Root: the repository a folder is in ("" if none, or no git).
Git_Root :: proc(dir: string) -> string {
	out, ok, _ := Git_Run(dir, "rev-parse", "--show-toplevel")
	return out if ok else ""
}
