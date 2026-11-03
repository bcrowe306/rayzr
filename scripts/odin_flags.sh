#!/usr/bin/env bash
# Extra `odin build` / `odin test` flags this platform needs (printed; empty
# on macOS and Linux). Windows: raylib.lib is linked whole (/WHOLEARCHIVE) so
# its CloseWindow / ShowCursor are defined before the linker searches
# User32.lib - otherwise rl.CloseWindow can resolve to Win32's (User32.lib
# comes first on the link line through core:os) and the two collide.
# (raylib stays static: the mixer pulls frames from raylib's decoders, which
# raylib.dll doesn't export.) And the C runtime stays static (#330): Odin's
# raylib.lib is built against the DLL one (/MD: its /DEFAULTLIB:MSVCRT), which
# made every exe - the editor, the runners, exported games - need
# VCRUNTIME140.dll and VCRUNTIME140_1.dll, which a fresh Windows doesn't have;
# /NODEFAULTLIB:msvcrt.lib leaves the static one (LIBCMT) the rest links.
# (Both flags in a linker response file: `odin build` takes one
# -extra-linker-flags and the callers split this script's output on spaces.)
# macOS in CI (release builds): the oldest macOS the app runs on, as its
# Info.plist says (LSMinimumSystemVersion, scripts/package_editor.sh) -
# without it Odin targets the build machine's macOS (0.6.0 needed 14).
# (Not locally: Homebrew's raylib is built for a newer macOS, and every
# link would warn.)
#   odin build editor $(scripts/odin_flags.sh) ...
MACOS_MIN=12.0
case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*)
		rsp="$(cd "$(dirname "$0")/.." && pwd)/bin/windows_link.rsp"
		mkdir -p "$(dirname "$rsp")"
		printf '/WHOLEARCHIVE:"%s"\n/NODEFAULTLIB:msvcrt.lib\n/DEFAULTLIB:libcmt.lib\n/DEFAULTLIB:libvcruntime.lib\n/DEFAULTLIB:libucrt.lib\n/VERBOSE:LIB\n' "$(cygpath -w "$(odin root)/vendor/raylib/windows/raylib.lib")" > "$rsp.$$"
		mv -f "$rsp.$$" "$rsp" # (whole: builds run this in parallel)
		echo "-extra-linker-flags:@$(cygpath -w "$rsp")" ;;
	Darwin)
		[ -n "${CI:-}" ] && echo "-minimum-os-version:$MACOS_MIN" ;;
esac
