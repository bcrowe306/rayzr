# Installation

Rayzr is one download: the editor, with everything it needs to run and
export games inside it (the game runners for every platform, the Lua
language server, the templates). You don't need a compiler or any other
tools.

## Download

Get the latest version from the [download page](https://rayzr.app/download/)
(or [GitHub Releases](https://github.com/bcrowe306/rayzr/releases)):

| Platform | File |
|---|---|
| macOS (Apple silicon) | `rayzr-editor-<version>-macos.dmg` |
| Windows (x64) | `rayzr-editor-<version>-windows.zip` |
| Linux (x64) | `rayzr-editor-<version>-linux-x86_64.AppImage`, `-amd64.deb` or `.tar.gz` |

Each release lists the SHA-256 checksum of every file (`SHA256SUMS.txt`).

## What it runs on

- **macOS** 12 or newer, Apple silicon (M1 and later).
- **Windows** 10 or 11, x64, with an OpenGL 3.3 graphics driver.
- **Linux** x64 with glibc 2.35 or newer (Ubuntu 22.04, Debian 12, Fedora
  36 and later), an OpenGL 3.3 driver and X11 or XWayland. The AppImage and
  the `.tar.gz` use the libraries every desktop has: OpenGL (Mesa), X11 with
  Xrandr, Xcursor, Xi and Xinerama, and ALSA for sound; the `.deb` installs
  them.

### Minimum and recommended

| | Minimum | Recommended |
|---|---|---|
| Processor | 2 cores, x64 or arm64 | 4 cores or more |
| Graphics | OpenGL 3.3, a software renderer included (Mesa's llvmpipe) | Any integrated GPU from the last ten years (Intel UHD, AMD Radeon Vega, Apple silicon) or better |
| Memory | 4 GB (the editor); 2 GB for a game | 8 GB |
| Android (games) | Android 7 (API 24), arm64, 2 cores, 2 GB | Android 10 or newer, 4 cores |

The minimum processor and graphics are what Rayzr is tested on (the editor
itself uses a few hundred MB of memory; the rest is room for the system and
your project): the Performance workflow
([Performance checks](../contributing/performance.md)) runs every
template game and the editor with a large scene on

- GitHub's Ubuntu runner held to **2 cores** with **Mesa llvmpipe**
  software OpenGL (no GPU at all), and
- the **Android 14 (API 34) x86_64 emulator** with **2 cores and 2 GB** of
  RAM (arm64 games through its ARM translation, software GL).

On the Linux runner's baseline CPU (an AMD EPYC 9V74 held to 2 cores)
each template game holds **60 fps** (95 frames in 100 under 16.7 ms; 20 ms
on the emulator, where frames wait for its 60 Hz display) and starts in under 3 seconds (6 on the emulator); the editor stays
responsive with a 5000-node scene, a 400x400 tile map or 5000 live
particles open (30 fps or better idle, 20 fps or better while selecting
and dragging), starts in under 8 seconds and plays a game in under 4. GitHub's runners come with different CPUs: on the slowest
seen (an AMD EPYC 7763) the same games take up to about 1.5x as long, and
the busiest (the Dungeon, the Vector Character) come out at 17-20 ms (p95)
rather than 60 fps. On
the recommended machines the same numbers are many times better: an
Apple M2 Pro plays every template at 1-2 ms a frame.

## macOS

1. Open the `.dmg` and drag **Rayzr Editor** to Applications.
2. The first time, right-click the app and choose **Open** (builds that
   aren't notarized yet show a warning otherwise), then **Open** again.

## Windows

1. Extract the `.zip` anywhere (for example `C:\Games\Rayzr`).
2. Run `rayzr-editor.exe`. If SmartScreen warns about an unknown publisher,
   choose **More info > Run anyway**.

## Linux

- **AppImage**: `chmod +x rayzr-editor-*.AppImage`, then run it. Without
  FUSE (some minimal installs and containers), run it with
  `--appimage-extract-and-run`.
- **Debian / Ubuntu**: `sudo apt install ./rayzr-editor-*-amd64.deb`, then
  start *Rayzr Editor* from your applications menu.
- **Any distribution**: extract the `.tar.gz` and run `rayzr-editor` inside.

## Updates

The editor checks for a newer version when it starts and shows it in the
status bar. Release builds offer releases; development builds also offer
newer development builds (one is published for every change merged into the
engine).

## Next

[Your first game](first-game.md) walks you from the Welcome window to a game
you changed yourself.
