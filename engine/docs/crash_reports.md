# Crash reports

When the editor or an exported game crashes, it writes a **crash report**: a
small text file with what crashed, where, and what it was doing just before.
Nothing is sent anywhere by itself.

## What counts as a crash

- an Odin panic, a failed `assert`, a failed runtime check (out-of-bounds
  index, bad type assertion);
- invalid memory access, an illegal instruction, division by zero, an abort
  (macOS / Linux: SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT, SIGTRAP; Windows:
  the matching exceptions, stack overflow included).

Lua errors in game scripts are **not** crashes: the script stops and the error
is logged (the Console in the editor), and the game keeps running. They do
appear in a later report's recent lines.

## A report

```
Asteroids crash report
version:  0.1.0-dev.240
platform: macOS arm64
time:     1792938203 (unix)
reason:   SIGSEGV (invalid memory access)

stack:
  0  0x1049f6c6c  engine::Scene_Update + 736  (runner+0x76c6c)
  1  0x100e45850  main + 5400  (runner+0x1d850)

recent:
  [Info] [Game] Playing scene 'level_1' (scenes/level_1.scene.json)
  [lua] entered the boss room
```

- **stack** - the functions that were running, innermost first. macOS shows
  names; Linux and Windows show `module+offset` too: resolve them with the
  debug build (`runner-debug`: `addr2line -e runner-debug 0x...`, `atos`, or
  the `.pdb` on Windows). If the stack walk itself fails, the report says
  "(the stack walk stopped here)" and still has the rest.
- **recent** - the last 48 log lines (the editor: also the actions run), and
  your game's `Crash.note(...)` lines.

The path is also printed to stderr (`Crash report: ...`), so a crash during
Play shows it in the editor's Console.

## Where they go

| | Folder |
|---|---|
| Editor | `~/.config/rayzr_editor/crashes/` (`RAYZR_CRASH_DIR` overrides it) |
| A game | `<user data>/crashes/` - macOS `~/Library/Application Support/<game>`, Windows `%APPDATA%\<game>`, Linux `~/.local/share/<game>` (the Save folder) |

The newest 20 reports are kept.

## In the editor

After a crash, the next start shows **Rayzr Editor Crashed** with the report:

- **Report on GitHub** opens a new issue on the engine's repository with the
  report filled in, in your browser. You can edit or remove anything before
  submitting; nothing is sent until you do.
- **Copy Report**, **Open Folder**, **Dismiss** (not offered again; the file
  stays, renamed `.seen`).

**Help > Report a Bug...** opens a new issue with the editor version, the
platform and the console's last lines. **Help > Open Crash Reports Folder**.

## In your game: the Crash module

Your game decides what to do with its players' reports - nothing happens by
default. Read them at startup:

```lua
function ready()
    for _, report in ipairs(Crash.pending()) do
        -- Ask the player, then send it to your own server (or show the text
        -- so they can paste it into your Discord / email).
        show_crash_dialog(report.text, function(send)
            if send then my_upload(report.text) end
            Crash.dismiss(report.path)
        end)
    end
end
```

| | |
|---|---|
| `Crash.pending()` | Reports from earlier runs not yet dismissed: `{ {path =, text =}, ... }` |
| `Crash.dismiss(path)` | Don't return it again (renamed `.seen`) |
| `Crash.note(text)` | A line for the next report's recent list ("entered level 3") |
| `Crash.get_dir()` | The crash folder |

Notes are cheap (a copy into a fixed ring of 48 lines): call them at
milestones, not every frame.

## Testing

`--crash-test panic | segv | abort` makes the editor or the runner crash on
purpose once loaded. `scripts/test_crash.sh` crashes both for real and checks
the reports and the editor's next start (CI runs it on Linux);
`tests/drive/crash_report.drive` checks the dialog and Report a Bug.

## How it works

`engine/crash_report.odin`: the report is preformatted (the header at start,
the recent lines in a fixed ring), so writing it needs no allocation - it's
safe from a signal handler. Handlers run on their own stack (a stack overflow
still reports). Stacks come from the unwinder (Odin code keeps no frame
pointers, so `backtrace()` would stop at one frame). On macOS the process
first clears inherited Mach exception ports, which otherwise take hardware
faults before they become signals (a launcher or tool that set one would make
the crashing thread hang instead of reporting). Platform parts:
`crash_report_posix.odin`, `crash_report_windows.odin`, `crash_report_js.odin`
(the web: the browser's console has the error).
